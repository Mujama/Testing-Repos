/*######################################
SQL-Base.InstanceCPU			
Author: Kyle Neier
Created: 20130806
Validated Versions: 2005, 2008, 2008R2, 2012
Validated Editions: Standard, Enterprise

Synopsis: Interrogates instance for most recent 
CPU usage of SQL Server


data collection adapted from
http://sqlserverperformance.wordpress.com/2009/07/30/how-to-get-sql-server-cpu-utilization-from-a-query/

######################################*/
SET NOCOUNT ON
BEGIN TRY

/*ANSI settings to allow XPath Queries*/
    SET ANSI_NULLS ON
    SET ANSI_PADDING ON
    SET ANSI_WARNINGS ON
    SET ARITHABORT ON
    SET CONCAT_NULL_YIELDS_NULL ON
    SET NUMERIC_ROUNDABORT OFF 
    SET QUOTED_IDENTIFIER ON

    DECLARE @VersionMajor INT,
        @ts_now BIGINT,
        @SQLProcessUtilization INT,
        @SystemIdleUtilization INT,
        @OtherProcessUtilization INT,
        @State CHAR(1),
        @LocalTime DATETIME,
        @ShortMessage VARCHAR(255)

/*Obtain current major version of SQL*/
    SELECT  @VersionMajor=LEFT(CAST(SERVERPROPERTY('ProductVersion') AS VARCHAR(100)), CHARINDEX('.', CAST(SERVERPROPERTY('ProductVersion') AS VARCHAR(100)))-1)
    CREATE TABLE #Apparatus_TSNow (TSNow FLOAT)

    IF @VersionMajor=9 /*SQL2005*/ 
        INSERT  INTO #Apparatus_TSNow
                (
                 TSNow
                )
                EXECUTE (
                         'SELECT cpu_ticks / CONVERT(float, cpu_ticks_in_ms) FROM sys.dm_os_sys_info'
                       )
    ELSE /*SQL2008, SQL2008R2, SQL2012*/ 
        INSERT  INTO #Apparatus_TSNow
                (
                 TSNow
                )
                EXECUTE (
                         'SELECT cpu_ticks/(cpu_ticks/ms_ticks)FROM sys.dm_os_sys_info'
                       )

    SELECT  @ts_now=TSNow
    FROM    #Apparatus_TSNow

    SELECT TOP (1)
            @SQLProcessUtilization=SQLProcessUtilization,
            @SystemIdleUtilization=SystemIdle,
            @OtherProcessUtilization=100-SystemIdle-SQLProcessUtilization,
            @LocalTime=DATEADD(ms, -1*(@ts_now-[timestamp]), GETDATE())
    FROM    (SELECT record.value('(./Record/@id)[1]', 'int') AS record_id,
                    record.value('(./Record/SchedulerMonitorEvent/SystemHealth/SystemIdle)[1]', 'int') AS [SystemIdle],
                    record.value('(./Record/SchedulerMonitorEvent/SystemHealth/ProcessUtilization)[1]', 'int') AS [SQLProcessUtilization],
                    [timestamp]
             FROM   (SELECT [timestamp],
                            CONVERT(XML, record) AS [record]
                     FROM   sys.dm_os_ring_buffers
                     WHERE  ring_buffer_type=N'RING_BUFFER_SCHEDULER_MONITOR'
                            AND record LIKE '%<SystemHealth>%') AS x) AS y
    ORDER BY record_id DESC;

    SELECT  @State=CASE WHEN @SQLProcessUtilization<50 THEN '0'
                        WHEN @SQLProcessUtilization>60THEN '2'
                        ELSE '0'
                   END

    DECLARE @x XML 

    SET @x=(SELECT  (SELECT 'default' AS [Instance/@Name],
                            'SQL CPU' AS [Instance/@Type],
                            @State AS [Instance/@State],
                            (SELECT *
                             FROM   (SELECT 'SQL CPU Utilization' AS [Value/@Name],
                                            '%' AS [Value/@UofM],
                                            '90' AS [Value/@Warning],
                                            '95' AS [Value/@Critical],
                                            CAST(@SQLProcessUtilization AS VARCHAR(2)) AS [Value]
                                     FROM   #Apparatus_TSNow
                                     UNION ALL
                                     SELECT 'OS Idle Utilization' AS [Value/@Name],
                                            '%' AS [Value/@UofM],
                                            '' AS [Value/@Warning],
                                            '' AS [Value/@Critical],
                                            CAST(@SystemIdleUtilization AS VARCHAR(2)) AS [Value]
                                     FROM   #Apparatus_TSNow
                                     UNION ALL
                                     SELECT 'OTHER CPU Utilization' AS [Value/@Name],
                                            '%' AS [Value/@UofM],
                                            '' AS [Value/@Warning],
                                            '' AS [Value/@Critical],
                                            CAST(@OtherProcessUtilization AS VARCHAR(2)) AS [Value]
                                     FROM   #Apparatus_TSNow
                                     UNION ALL
                                     SELECT 'LocalTime' AS [Value/@Name],
                                            'datetime' AS [Value/@UofM],
                                            '' AS [Value/@Warning],
                                            '' AS [Value/@Critical],
                                            CONVERT(VARCHAR(100), @LocalTime, 126) AS [Value]
                                     FROM   #Apparatus_TSNow) AS a
                            FOR
                             XML PATH(''),
                                 TYPE) Instance
                     FROM   #Apparatus_TSNow
                    FOR
                     XML PATH(''),
                         TYPE)
        FOR XML PATH('Data'),
                TYPE)


    IF @State='0' 
        SELECT  @ShortMessage='SQL Process Utilization: '+CAST(@SQLProcessUtilization AS VARCHAR(2))+'%'
    ELSE 
        IF @State='1' 
            SELECT  @ShortMessage='WARNING: SQL Process Utilization:'+CAST(@SQLProcessUtilization AS VARCHAR(2))+'%'
        ELSE 
            SELECT  @ShortMessage='CRITICAL: SQL Process Utilization:'+CAST(@SQLProcessUtilization AS VARCHAR(2))+'%'

    SELECT  @State+','+@ShortMessage+'|'+CAST(@x AS VARCHAR(MAX)) AS StringValue

/*Clean Up*/
    DROP TABLE #Apparatus_TSNow
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

