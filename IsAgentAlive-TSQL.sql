/*######################################
SQL-Base.IsAlive-Agent		
Author: Muktar Jama
Created: 01/25/2017
Validated Versions: 2005-2014

######################################*/
SET NOCOUNT ON


BEGIN TRY
	
	DECLARE @AgentState VARCHAR(50);
	IF OBJECT_ID('Tempdb..#AgentStatus', 'U') IS NOT NULL
	DROP TABLE #AgentStatus
 
	CREATE TABLE #AgentStatus ( Status VARCHAR(30))
	INSERT INTO #AgentStatus  EXEC xp_servicecontrol 'querystate', 'SQLSERVERAGENT'
	SELECT @agentstate = LEFT(Status,LEN(Status)-1) FROM #AgentStatus
    IF (@AgentState = 'Running')
        BEGIN
            SELECT  '0,Agent is running|<Data><Instance Name="default"><Value Name="AgentIsRunning" UofM="">1</Value></Instance></Data>' AS StringValue
        END
    ELSE
        BEGIN
            IF (@AgentState = 'Stopped')
               SELECT  '2,Agent is stopped|<Data><Instance Name="default"><Value Name="AgentIsStopped" UofM="">0</Value></Instance></Data>' AS StringValue
            ELSE
                SELECT  '2,Agent may is not installed|<Data><Instance Name="default"><Value Name="Unkown" UofM="">0</Value></Instance></Data>' AS StringValue
        END
		DROP TABLE #AgentStatus
END TRY

BEGIN CATCH
				
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
            @ErrorState=ERROR_STATE()

	/*Build the message string that will contain original
     error information.*/
    SELECT  @ErrorMessage=N'Error %d, Level %d, State %d '+'Message: '+ERROR_MESSAGE();

    SELECT  '3|<Data><Instance Name="default" Type="SQL"><Value Name="Error" UofM="">'+REPLACE(REPLACE(REPLACE(REPLACE(@ErrorMessage, '&', '&amp;'), '<', '&lt;'),
                                                                                                       '>', '&gt;'),
                                                                                               'Error %d, Level %d, State %d,  Message: ',
                                                                                             '')+'</Value></Instance></Data>' AS StringValue
END CATCH


