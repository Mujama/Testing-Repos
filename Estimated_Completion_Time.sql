USE master
GO
 
SELECT CASE WHEN ((estimated_completion_time/1000)/3600) < 10 THEN '0' +
CONVERT(VARCHAR(10),(estimated_completion_time/1000)/3600)
ELSE CONVERT(VARCHAR(10),(estimated_completion_time/1000)/3600)
END + ':' + 
CASE WHEN ((estimated_completion_time/1000)%3600/60) < 10 THEN '0' +
CONVERT(VARCHAR(10),(estimated_completion_time/1000)%3600/60) 
ELSE CONVERT(VARCHAR(10),(estimated_completion_time/1000)%3600/60)
END  + ':' + 
CASE WHEN ((estimated_completion_time/1000)%60) < 10 THEN '0' +
CONVERT(VARCHAR(10),(estimated_completion_time/1000)%60)
ELSE CONVERT(VARCHAR(10),(estimated_completion_time/1000)%60)
END
AS [Time Remaining],
percent_complete,
* FROM sys.dm_exec_requests
WHERE percent_complete > 0
