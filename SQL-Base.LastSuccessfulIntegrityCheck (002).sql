/*######################################
SQL-Base.LastSuccessfulCheckDB			
Author: Kyle Neier
Created: 20130806
Validated Versions: 2005, 2008, 2008R2, 2012
Validated Editions: Standard, Enterprise

Synopsis: Interrogates each database 
for the last known good check db.

Will Warn when last known good is older
than @WarningDays days old. Will Crit 
when last known good is older than
@CriticalDays days old.

20150710 - MJ - Added logic to accomodate restoredate and createdate to prevent false alarms

######################################*/
SET NOCOUNT ON
BEGIN TRY

/*Days Out of Spec*/
    DECLARE @WarningDays INT,
        @CriticalDays INT

    SELECT  @WarningDays=8,
            @CriticalDays=30

    SET NOCOUNT ON

    CREATE TABLE #DBInfo_LastKnownGoodCheckDB
        (
         ParentObject VARCHAR(1000) NULL,
         Object VARCHAR(1000) NULL,
         Field VARCHAR(1000) NULL,
         Value VARCHAR(1000) NULL,
         DatabaseName VARCHAR(1000) NULL
        )

/*Init some variables*/
    DECLARE @DatabaseName VARCHAR(1000),
        @SQL VARCHAR(8000),
        @VersionMajor TINYINT

/*Obtain current major version of SQL*/
    SELECT  @VersionMajor=LEFT(CAST(SERVERPROPERTY('ProductVersion') AS VARCHAR(100)), CHARINDEX('.', CAST(SERVERPROPERTY('ProductVersion') AS VARCHAR(100)))-1)

    DECLARE csrDatabases CURSOR FAST_FORWARD LOCAL
    FOR
        SELECT  name
        FROM    sys.databases
        WHERE   state_desc='ONLINE' /*can only get info for Online Databases*/
                AND source_database_id IS NULL
				AND is_read_only <> 1
				AND name <> 'tempdb'
 /* Snapshots never have accurate date - it's date at time of snap creation... don't worry thyself with these */

    OPEN csrDatabases

    FETCH NEXT FROM csrDatabases INTO @DatabaseName

/*Only if the instance is SQL 2005 or higher*/
    IF @VersionMajor>=9 
        BEGIN
            WHILE @@FETCH_STATUS=0 
                BEGIN

/*Create dynamic SQL to be inserted into temp table*/
                    SET @SQL='DBCC DBINFO ('+CHAR(39)+@DatabaseName+CHAR(39)+') WITH TABLERESULTS'

/*Insert the results of the DBCC DBINFO command into the temp table*/
                    INSERT  INTO #DBInfo_LastKnownGoodCheckDB
                            (
                             ParentObject,
                             Object,
                             Field,
                             Value
                            )
                            EXEC (
                                  @SQL
                                )

/*Set the database name where it has yet to be set
If the DatabaseName is not null, we've set it in an 
earlier loop*/
                    UPDATE  #DBInfo_LastKnownGoodCheckDB
                    SET     DatabaseName=@DatabaseName
                    WHERE   DatabaseName IS NULL

                    FETCH NEXT FROM csrDatabases INTO @DatabaseName

                END

/*Delete any other values from the temp table that are not
the last known good checkdb date*/
            DELETE  FROM #DBInfo_LastKnownGoodCheckDB
            WHERE   Field<>'dbi_dbccLastKnownGood'    

            CLOSE csrDatabases
            DEALLOCATE csrDatabases

        END

/*Add some reporting columns to the temporary table*/
    ALTER TABLE #DBInfo_LastKnownGoodCheckDB
    ADD [State] INT NULL,
    [LastCheckDateTime] DATETIME NULL

/*Set the LastCheckDateTime column 

This will consider the last restore date and the create date
so that we do not get false alarms
*/

    UPDATE  #DBInfo_LastKnownGoodCheckDB
    SET     LastCheckDateTime=CASE 
			WHEN (CAST(ISNULL([Value], '1/1/1900') AS DATETIME) > (SELECT TOP 1 CASE WHEN ISNULL(r.restore_date, '1/1/1900') > d.create_date THEN ISNULL(r.restore_date, '1/1/1900') ELSE d.create_date END  FROM master.sys.databases d LEFT OUTER JOIN msdb.dbo.[restorehistory] r ON r.[destination_database_name] = d.Name where d.name = DatabaseName order by r.restore_date DESC)) 
			then CAST(ISNULL([Value], '1/1/1900') AS DATETIME) 
			ELSE (SELECT TOP 1 CASE WHEN ISNULL(r.restore_date, '1/1/1900') > d.create_date THEN ISNULL(r.restore_date, '1/1/1900') ELSE d.create_date END FROM master.sys.databases d LEFT OUTER JOIN msdb.dbo.[restorehistory] r ON r.[destination_database_name] = d.Name where d.name = DatabaseName order by r.restore_date DESC)
			END

/*Set the state for each database as it relates to the CheckDB date*/
    UPDATE  #DBInfo_LastKnownGoodCheckDB
    SET     [State]=CASE WHEN DATEDIFF(dd, LastCheckDateTime, GETDATE())<@WarningDays THEN 0
                         WHEN DATEDIFF(dd, LastCheckDateTime, GETDATE())>@CriticalDays THEN 2
                         ELSE 1
                    END 



/*Build out the XML for the data portion*/
    DECLARE @x XML 
    SET @x=(SELECT  (SELECT db.Name AS [Instance/@Name],
                            'SQL Database' AS [Instance/@Type],
                            MAX(LastState.[State]) AS [Instance/@State],
                            'LastSuccessfulIntegrityCheck' AS [Instance/Value/@Name],
                            'datetime' AS [Instance/Value/@UofM],
                            MIN(LastState.LastCheckDateTime) AS [Instance/Value]
                     FROM   sys.databases db
                            LEFT JOIN #DBInfo_LastKnownGoodCheckDB LastState ON db.Name=LastState.DatabaseName
                     GROUP BY db.Name
                    FOR
                     XML PATH(''),
                         TYPE)
        FOR XML PATH('Data'),
                TYPE)


/*Init some more local variables*/
    DECLARE @WarningCount INT,
        @CriticalCount INT,
        @ShortMessage VARCHAR(255),
        @State CHAR(1)

/*Store the count of occurences*/
    SELECT  @WarningCount=COUNT(DISTINCT DatabaseName)
    FROM    #DBInfo_LastKnownGoodCheckDB
    WHERE   [State]=1

    SELECT  @CriticalCount=COUNT(DISTINCT DatabaseName)
    FROM    #DBInfo_LastKnownGoodCheckDB
    WHERE   [State]=2



/*Materialize the state and short message*/
    IF @WarningCount=0
        AND @CriticalCount=0 
        SELECT  @State=0,
                @ShortMessage='NO DATABASES WITH INVALID CHECKDB'
    ELSE 
        IF @CriticalCount>0 
            SELECT  @State=2,
                    @ShortMessage=CAST(@CriticalCount AS VARCHAR(5))+' DATABASES CRITICAL CHECKDB AGE, '+CAST(@WarningCount AS VARCHAR(5))
                    +' DATABASES IN WARNING'
        ELSE 
            SELECT  @State=1,
                    @ShortMessage=CAST(@WarningCount AS VARCHAR(5))+' DATABASES WARNING CHECKDB AGE'


/*Return the State, Message, and XML*/
    SELECT  @State+','+@ShortMessage+'|'+CAST(@x AS VARCHAR(MAX)) AS StringValue


/*Clean Up*/
    DROP TABLE #DBInfo_LastKnownGoodCheckDB
END TRY
BEGIN CATCH
			
		/*http://msdn.microsoft.com/en-us/library/ms179296%28v=SQL.105%29.aspx*/

    DECLARE @ErrorMessage NVARCHAR(4000),
        @ErrorNumber INT,
        @ErrorSeverity INT,
        @ErrorState INT,
        @ErrorLine INT,
        @ErrorProcedure NVARCHAR(200);

    /*Assign variables to error-handling functions that 
     capture information for RAISERROR.*/
    SELECT  @ErrorNumber=ERROR_NUMBER(),
            @ErrorSeverity=ERROR_SEVERITY(),
            @ErrorState=ERROR_STATE(),
            @ErrorLine=ERROR_LINE(),
            @ErrorProcedure=ISNULL(ERROR_PROCEDURE(), '-');

	/*Build the message string that will contain original
     error information.*/
    SELECT  @ErrorMessage=N'Error %d, Level %d, State %d, Procedure %s, Line %d, '+'Message: '+ERROR_MESSAGE();

    SELECT  '3|<Data><Instance Name="default" Type="SQL"><Value Name="Error" UofM="">'+REPLACE(REPLACE(REPLACE(REPLACE(@ErrorMessage, '&', '&amp;'), '<', '&lt;'),
                                                                                                       '>', '&gt;'),
                                                                                               'Error %d, Level %d, State %d, Procedure %s, Line %d, Message: ',
                                                                                               '')+'</Value></Instance></Data>' AS StringValue

    

    /*Raise an error: msg_str parameter of RAISERROR will contain
     the original error information.*/
    RAISERROR 
        (
        @ErrorMessage, 
        @ErrorSeverity, 
        1,               
        @ErrorNumber,    /* parameter: original error number.*/
        @ErrorSeverity,  /* parameter: original error severity.*/
        @ErrorState,     /* parameter: original error state.*/
        @ErrorProcedure, /* parameter: original error procedure name.*/
        @ErrorLine       /* parameter: original error line number.*/
        );

END CATCH      

