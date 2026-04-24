-- Recreate SQL Agent Job for PC-BATTERY-P1
USE msdb;
GO

IF EXISTS (SELECT 1 FROM msdb.dbo.sysjobs WHERE name=N'WTG_DB_BATTERY_TICKER')
    EXEC msdb.dbo.sp_delete_job @job_name=N'WTG_DB_BATTERY_TICKER';
GO

EXEC msdb.dbo.sp_add_job
    @job_name   = N'WTG_DB_BATTERY_TICKER',
    @enabled    = 1,
    @description= N'Executes SP_WTG_DB every second to maintain working-time counter';

EXEC msdb.dbo.sp_add_jobstep
    @job_name      = N'WTG_DB_BATTERY_TICKER',
    @step_name     = N'Tick',
    @subsystem     = N'TSQL',
    @database_name = N'DB_TMMIN1_KRW_WTG_HV_BATTERY',
    @command       = N'
DECLARE @i INT = 0;
WHILE @i < 60
BEGIN
    EXEC dbo.SP_WTG_DB @VLINE = ''ADAPTIVE'';
    WAITFOR DELAY ''00:00:01'';
    SET @i = @i + 1;
END',
    @on_success_action = 1,
    @on_fail_action    = 2;

EXEC msdb.dbo.sp_add_schedule
    @schedule_name        = N'WTG_Every_Minute',
    @freq_type            = 4,
    @freq_interval        = 1,
    @freq_subday_type     = 4,
    @freq_subday_interval = 1,
    @active_start_time    = 000000,
    @active_end_time      = 235959;

EXEC msdb.dbo.sp_attach_schedule
    @job_name      = N'WTG_DB_BATTERY_TICKER',
    @schedule_name = N'WTG_Every_Minute';

EXEC msdb.dbo.sp_add_jobserver
    @job_name    = N'WTG_DB_BATTERY_TICKER',
    @server_name = N'(local)';

PRINT 'Job WTG_DB_BATTERY_TICKER created';
GO
