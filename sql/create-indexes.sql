-- ========================================
-- PHASE 3 STEP 4: DATABASE INDEXES
-- Performance optimization for frequently queried columns
-- ========================================

USE DB_TMMIN1_KRW_PIS_HV_BATTERY;
GO

-- ========================================
-- 1. Check if indexes already exist
-- ========================================
IF EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IDX_SEQUENCE_STATUS_ADJUST' AND object_id = OBJECT_ID('TB_R_SEQUENCE_BATTERY'))
BEGIN
    PRINT '⚠️  Index IDX_SEQUENCE_STATUS_ADJUST already exists, dropping...'
    DROP INDEX IDX_SEQUENCE_STATUS_ADJUST ON TB_R_SEQUENCE_BATTERY;
END

IF EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IDX_PRINTLOG_PROD_DATE' AND object_id = OBJECT_ID('TB_H_PRINT_LOG'))
BEGIN
    PRINT '⚠️  Index IDX_PRINTLOG_PROD_DATE already exists, dropping...'
    DROP INDEX IDX_PRINTLOG_PROD_DATE ON TB_H_PRINT_LOG;
END

IF EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IDX_SEQUENCE_FID_ADJUST' AND object_id = OBJECT_ID('TB_R_SEQUENCE_BATTERY'))
BEGIN
    PRINT '⚠️  Index IDX_SEQUENCE_FID_ADJUST already exists, dropping...'
    DROP INDEX IDX_SEQUENCE_FID_ADJUST ON TB_R_SEQUENCE_BATTERY;
END

-- ========================================
-- 2. Create indexes for TB_R_SEQUENCE_BATTERY
-- ========================================

-- Index for sequence status queries (getSequences)
-- Covers: WHERE FSTATUS = 0/1/2/3 ORDER BY FID_ADJUST
PRINT '✅ Creating index: IDX_SEQUENCE_STATUS_ADJUST'
CREATE NONCLUSTERED INDEX IDX_SEQUENCE_STATUS_ADJUST
ON TB_R_SEQUENCE_BATTERY (FSTATUS, FID_ADJUST)
INCLUDE (FID, FSEQ_K0, FBODY_NO_K0, FTYPE_BATTERY, FMODEL_BATTERY, FSEQ_DATE, 
         FTIME_RECEIVED, FTIME_PRINTED, FTIME_COMPLETED, FALC_DATA)
GO

-- Index for FID_ADJUST range queries (moveSequenceUp/moveSequenceDown)
-- Covers: WHERE FID_ADJUST < @value or FID_ADJUST > @value
PRINT '✅ Creating index: IDX_SEQUENCE_FID_ADJUST'
CREATE NONCLUSTERED INDEX IDX_SEQUENCE_FID_ADJUST
ON TB_R_SEQUENCE_BATTERY (FID_ADJUST)
INCLUDE (FID, FSTATUS)
GO

-- ========================================
-- 3. Create indexes for TB_H_PRINT_LOG
-- ========================================

-- Index for production date range queries (getByDateRange)
-- Covers: WHERE PROD_DATE BETWEEN @from AND @to ORDER BY DATETIME_MODIFIED DESC
PRINT '✅ Creating index: IDX_PRINTLOG_PROD_DATE'
CREATE NONCLUSTERED INDEX IDX_PRINTLOG_PROD_DATE
ON TB_H_PRINT_LOG (PROD_DATE, DATETIME_MODIFIED DESC)
INCLUDE (FID, PRINT_QRCODE, FSHIFT, FMODEL_BATTERY, DATETIME_RECEIVED)
GO

-- ========================================
-- 4. Check index statistics
-- ========================================
PRINT ''
PRINT '========================================='
PRINT '📊 INDEX STATISTICS'
PRINT '========================================='

SELECT 
    OBJECT_NAME(indexes.object_id) AS table_name,
    indexes.name AS index_name,
    indexes.type_desc AS index_type,
    SUM(partitions.rows) AS row_count,
    SUM(allocation_units.total_pages) * 8 / 1024 AS size_mb
FROM sys.indexes
INNER JOIN sys.partitions ON indexes.object_id = partitions.object_id AND indexes.index_id = partitions.index_id
INNER JOIN sys.allocation_units ON partitions.partition_id = allocation_units.container_id
WHERE OBJECT_NAME(indexes.object_id) IN ('TB_R_SEQUENCE_BATTERY', 'TB_H_PRINT_LOG')
    AND indexes.name IN ('IDX_SEQUENCE_STATUS_ADJUST', 'IDX_SEQUENCE_FID_ADJUST', 'IDX_PRINTLOG_PROD_DATE')
GROUP BY indexes.object_id, indexes.name, indexes.type_desc
ORDER BY table_name, index_name
GO

PRINT ''
PRINT '✅ All indexes created successfully!'
PRINT '========================================='
