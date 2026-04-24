USE [DB_TMMIN1_KRW_PIS_HV_BATTERY]
GO

-- 1) Enable Change Tracking at database level if not enabled
IF NOT EXISTS (
    SELECT 1
    FROM sys.change_tracking_databases
    WHERE database_id = DB_ID('DB_TMMIN1_KRW_PIS_HV_BATTERY')
)
BEGIN
    ALTER DATABASE [DB_TMMIN1_KRW_PIS_HV_BATTERY]
    SET CHANGE_TRACKING = ON
    (CHANGE_RETENTION = 7 DAYS, AUTO_CLEANUP = ON)

    PRINT 'Database Change Tracking enabled.'
END
ELSE
BEGIN
    PRINT 'Database Change Tracking already enabled.'
END
GO

-- 2) Enable Change Tracking for TB_H_PROD_PLAN_DETAIL table if not enabled
IF NOT EXISTS (
    SELECT 1
    FROM sys.change_tracking_tables
    WHERE object_id = OBJECT_ID(N'dbo.TB_H_PROD_PLAN_DETAIL')
)
BEGIN
    ALTER TABLE dbo.TB_H_PROD_PLAN_DETAIL
    ENABLE CHANGE_TRACKING
    WITH (TRACK_COLUMNS_UPDATED = OFF)

    PRINT 'Table Change Tracking enabled for TB_H_PROD_PLAN_DETAIL.'
END
ELSE
BEGIN
    PRINT 'Table Change Tracking already enabled for TB_H_PROD_PLAN_DETAIL.'
END
GO

-- 3) Quick verification
SELECT
    DB_NAME(ctd.database_id) AS database_name,
    ctd.is_auto_cleanup_on,
    ctd.retention_period,
    ctd.retention_period_units_desc
FROM sys.change_tracking_databases ctd
WHERE ctd.database_id = DB_ID('DB_TMMIN1_KRW_PIS_HV_BATTERY')
GO

SELECT
    OBJECT_NAME(ctt.object_id) AS tracked_table,
    ctt.is_track_columns_updated_on,
    ctt.begin_version,
    ctt.min_valid_version
FROM sys.change_tracking_tables ctt
WHERE ctt.object_id = OBJECT_ID(N'dbo.TB_H_PROD_PLAN_DETAIL')
GO
