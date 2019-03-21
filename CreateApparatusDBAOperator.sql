USE [msdb]
GO
EXEC msdb.dbo.sp_add_operator @name=N'Apparatus_DBA', 
		@enabled=1, 
		@weekday_pager_start_time=0, 
		@weekday_pager_end_time=235959, 
		@saturday_pager_start_time=0, 
		@saturday_pager_end_time=235959, 
		@sunday_pager_start_time=0, 
		@sunday_pager_end_time=235959, 
		@pager_days=127, 
		@email_address=N'cache.support@apparatus.net', 
		@pager_address=N'cache.urgent@apparatus.net', 
		@netsend_address=N''
GO