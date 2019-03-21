/*

Find out when the auto file growth took place.
From the default trace

*/



DECLARE @path NVARCHAR(260);

SELECT    @path = REVERSE(SUBSTRING(REVERSE([path]),    CHARINDEX('\', REVERSE([path])), 260)) + N'log.trc'
FROM    sys.traces
WHERE   is_default = 1;




SELECT  DatabaseName,   
		[FileName],
		YEAR(StartTime) Yr,
		MONTH(StartTime) Mth,
		DAY(StartTime) Dy,
		DATEPART(HOUR, StartTime) HR,
		COUNT(*) AS NumOfGrowths
		
FROM sys.fn_trace_gettable(@path, DEFAULT)
WHERE   EventClass IN (92,93)
Group by DatabaseName,   
		[FileName],
		YEAR(StartTime) ,
		MONTH(StartTime) ,
		DAY(StartTime) ,
		DATEPART(HOUR, StartTime)
		
order by YEAR(StartTime) DESC,
		MONTH(StartTime) DESC,
		DAY(StartTime) DESC,
		DATEPART(HOUR, StartTime) DESC