/*
0.	OK - no need to notify anyone. All is as expected.
1.	WARNING - if the service is set to notify on warning, it will issue a non-urgent notification.
2.	CRITICAL - this will generate a notification. The service itself determines whether this is sent with a urgent or non-urgent status
3.	UNKNOWN - if the state cannot be determined or if there is an error. This will generate a notification with the same urgency as the critical level notifications

*/

DECLARE @WarningDuration int, @WarningCount int, @CriticalDuration int, @CriticalCount int

SELECT @WarningDuration = 60, @WarningCount = 100, @CriticalDuration = 120, @CriticalCount = 250

SET NOCOUNT ON

BEGIN TRY


    DECLARE @State CHAR(1)
	
	DECLARE @MaxDuration INT, @BlockedCount INT

CREATE TABLE #BlockedProcesses (session_id INT, blocking_session_id INT NULL, wait_time INT NULL)

INSERT INTO #BlockedProcesses (session_id, blocking_session_id, wait_time)
SELECT session_id, blocking_session_id, wait_time FROM sys.dm_exec_requests
WHERE blocking_session_id > 0



SELECT @MaxDuration = MAX(wait_time)/1000,
@BlockedCount = COUNT(DISTINCT session_id)
FROM #BlockedProcesses


    CREATE TABLE #Instance
        (
         InstanceID INT IDENTITY(1, 1)
                        NOT NULL,
         InstanceName NVARCHAR(1000) NOT NULL,
         InstanceType NVARCHAR(100) NULL,
         InstanceState NVARCHAR(100) NULL,
         InstanceStatus NVARCHAR(100) NULL
        )
    CREATE TABLE #Value
        (
         ValueID INT IDENTITY(1, 1)
                     NOT NULL,
         InstanceID INT NOT NULL,
         ValueName NVARCHAR(1000) NOT NULL,
         ValueUofM NVARCHAR(100) NOT NULL,
         [Value] NVARCHAR(1000) NOT NULL,
         ValueCritical NVARCHAR(100) NULL,
         ValueWarning NVARCHAR(100) NULL
        );

/*
Insert Instances into #Instance Table Here
INSERT INTO #Instance (InstanceName, InstanceType, InstanceState, InstanceStatus)
*/
DECLARE @DurationState INT, @CountState INT


SELECT @DurationState = 
CASE WHEN @MaxDuration < @WarningDuration THEN 0 WHEN @MaxDuration >= @WarningDuration AND @MaxDuration < @CriticalDuration THEN 1 WHEN @MaxDuration >= @CriticalDuration THEN 2 END

SELECT @CountState = 
CASE WHEN @BlockedCount < @WarningCount THEN 0 WHEN @BlockedCount >= @WarningCount AND @BlockedCount < @CriticalCount THEN 1 WHEN @BlockedCount >= @CriticalCount THEN 2 END

SELECT @State = MAX(st) FROM (SELECT @DurationState AS st UNION ALL SELECT @CountState) AS t


INSERT INTO #Instance (InstanceName, InstanceType, InstanceState, InstanceStatus)
VALUES ('BlockedProcess', 'Blocked Process', @State, NULL)

/*
Insert Values for Each Instance Here
INSERT INTO #Value (InstanceID, ValueName, ValueUofM, [Value], ValueCritical, ValueWarning)
*/
INSERT INTO #Value (InstanceID, ValueName, ValueUofM, [Value], ValueCritical, ValueWarning)
VALUES ('1', 'Max Blocked Duration', 's', ISNULL(@MaxDuration, 0), @CriticalDuration, @WarningDuration)

INSERT INTO #Value (InstanceID, ValueName, ValueUofM, [Value], ValueCritical, ValueWarning)
VALUES ('1', 'Total Blocked Count', '', ISNULL(@BlockedCount, 0), @CriticalCount, @WarningCount)


    DECLARE @x XML 
			
    SET @x=(SELECT  (SELECT i.InstanceName AS [Instance/@Name],
                            i.InstanceType AS [Instance/@Type],
                            i.InstanceState AS [Instance/@State],
                            i.InstanceStatus AS [Instance/@Status],
                            (SELECT v.ValueName AS [Value/@Name],
                                    v.ValueUofM AS [Value/@UofM],
                                    v.ValueCritical AS [Value/@Critical],
                                    v.ValueWarning AS [Value/@Warning],
                                    v.[Value] AS [Value]
                             FROM   #Value v
                             WHERE  v.InstanceID=i.InstanceID
                            FOR
                             XML PATH(''),
                                 TYPE) AS [Instance]
                     FROM   #Instance i
                    FOR
                     XML PATH(''),
                         ROOT('Data'),
                         TYPE))

    SELECT  @State=MAX(InstanceState)
    FROM    #Instance

    DROP TABLE #Instance
    DROP TABLE #Value
	DROP TABLE #BlockedProcesses

    SELECT  ISNULL(@State, '3')+'|'+ISNULL(CAST(@x AS NVARCHAR(MAX)), N'<Data><Instance Name="Unknown"><Value Name="Unknown" UofM=""/></Instance></Data>') AS StringValue


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

    SELECT  '3|<Data><Instance Name="default" Type="SQL"><Value Name="Error" UofM="">'+REPLACE(REPLACE(REPLACE(REPLACE(@ErrorMessage, '&', '&amp;'), '<', '&lt;'),'>', '&gt;'),'Error %d, Level %d, State %d, Procedure %s, Line %d, Message: ','')+'</Value></Instance></Data>' AS StringValue

    

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