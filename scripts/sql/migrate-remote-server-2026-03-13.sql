-- ============================================================
-- MIGRATION SCRIPT: LOCAL -> REMOTE (192.168.250.2)
-- Date: 2026-03-13
-- DB: DB_TMMIN1_KRW_PIS_HV_BATTERY
-- Desc: Deploy all structural changes (schema, functions, triggers)
--       from local (localhost:1433) to remote server.
--       DATA is NOT modified.
-- Order: Schema changes FIRST, then Functions, then Triggers.
-- ============================================================

USE [DB_TMMIN1_KRW_PIS_HV_BATTERY];
GO
SET NOCOUNT ON;
GO

PRINT '=== STEP 1: Schema Changes ===';

-- --------------------------------------------------------
-- 1A. TB_M_BATTERY_MAPPING: ADD ORDER_TYPE (if not exists)
-- --------------------------------------------------------
IF NOT EXISTS (
    SELECT 1 FROM sys.columns
    WHERE object_id = OBJECT_ID('dbo.TB_M_BATTERY_MAPPING')
      AND name = 'ORDER_TYPE'
)
BEGIN
    ALTER TABLE dbo.TB_M_BATTERY_MAPPING
        ADD ORDER_TYPE nvarchar(100) NULL;
    PRINT '+ TB_M_BATTERY_MAPPING: ORDER_TYPE added';
END
ELSE
    PRINT '  TB_M_BATTERY_MAPPING: ORDER_TYPE already exists, skip';
GO

-- --------------------------------------------------------
-- 1B. TB_M_INIT_QRCODE: ADD ORDER_TYPE (if not exists)
-- --------------------------------------------------------
IF NOT EXISTS (
    SELECT 1 FROM sys.columns
    WHERE object_id = OBJECT_ID('dbo.TB_M_INIT_QRCODE')
      AND name = 'ORDER_TYPE'
)
BEGIN
    ALTER TABLE dbo.TB_M_INIT_QRCODE
        ADD ORDER_TYPE nvarchar(100) NULL;
    PRINT '+ TB_M_INIT_QRCODE: ORDER_TYPE added';
END
ELSE
    PRINT '  TB_M_INIT_QRCODE: ORDER_TYPE already exists, skip';
GO

-- --------------------------------------------------------
-- 1C. TB_M_PROD_MODEL: RENAME MODEL_NAME -> FMODEL_BATTERY
--     (only if MODEL_NAME exists)
-- --------------------------------------------------------
IF EXISTS (
    SELECT 1 FROM sys.columns
    WHERE object_id = OBJECT_ID('dbo.TB_M_PROD_MODEL')
      AND name = 'MODEL_NAME'
)
AND NOT EXISTS (
    SELECT 1 FROM sys.columns
    WHERE object_id = OBJECT_ID('dbo.TB_M_PROD_MODEL')
      AND name = 'FMODEL_BATTERY'
)
BEGIN
    EXEC sp_rename 'dbo.TB_M_PROD_MODEL.MODEL_NAME', 'FMODEL_BATTERY', 'COLUMN';
    PRINT '+ TB_M_PROD_MODEL: MODEL_NAME renamed to FMODEL_BATTERY';
END
ELSE IF EXISTS (
    SELECT 1 FROM sys.columns
    WHERE object_id = OBJECT_ID('dbo.TB_M_PROD_MODEL')
      AND name = 'FMODEL_BATTERY'
)
    PRINT '  TB_M_PROD_MODEL: FMODEL_BATTERY already exists, skip rename';
ELSE
    PRINT '  TB_M_PROD_MODEL: MODEL_NAME not found, skip rename';
GO

-- --------------------------------------------------------
-- 1D. TB_M_PROD_MODEL: ADD FTYPE_BATTERY (if not exists)
-- --------------------------------------------------------
IF NOT EXISTS (
    SELECT 1 FROM sys.columns
    WHERE object_id = OBJECT_ID('dbo.TB_M_PROD_MODEL')
      AND name = 'FTYPE_BATTERY'
)
BEGIN
    ALTER TABLE dbo.TB_M_PROD_MODEL
        ADD FTYPE_BATTERY varchar(1) NULL;
    PRINT '+ TB_M_PROD_MODEL: FTYPE_BATTERY added';
END
ELSE
    PRINT '  TB_M_PROD_MODEL: FTYPE_BATTERY already exists, skip';
GO

-- --------------------------------------------------------
-- 1E. TB_R_SEQUENCE_BATTERY: ADD ORDER_TYPE (if not exists)
-- --------------------------------------------------------
IF NOT EXISTS (
    SELECT 1 FROM sys.columns
    WHERE object_id = OBJECT_ID('dbo.TB_R_SEQUENCE_BATTERY')
      AND name = 'ORDER_TYPE'
)
BEGIN
    ALTER TABLE dbo.TB_R_SEQUENCE_BATTERY
        ADD ORDER_TYPE nvarchar(100) NULL;
    PRINT '+ TB_R_SEQUENCE_BATTERY: ORDER_TYPE added';
END
ELSE
    PRINT '  TB_R_SEQUENCE_BATTERY: ORDER_TYPE already exists, skip';
GO

-- --------------------------------------------------------
-- 1F. TB_R_TARGET_PROD: ADD ORDER_TYPE (if not exists)
-- --------------------------------------------------------
IF NOT EXISTS (
    SELECT 1 FROM sys.columns
    WHERE object_id = OBJECT_ID('dbo.TB_R_TARGET_PROD')
      AND name = 'ORDER_TYPE'
)
BEGIN
    ALTER TABLE dbo.TB_R_TARGET_PROD
        ADD ORDER_TYPE nvarchar(100) NULL;
    PRINT '+ TB_R_TARGET_PROD: ORDER_TYPE added';
END
ELSE
    PRINT '  TB_R_TARGET_PROD: ORDER_TYPE already exists, skip';
GO

PRINT '=== STEP 2: Functions ===';

-- --------------------------------------------------------
-- 2A. GetPackPartByModel: CREATE OR ALTER
-- --------------------------------------------------------
CREATE OR ALTER FUNCTION [dbo].[GetPackPartByModel] (@Model VARCHAR(50))
RETURNS VARCHAR(5)
AS
BEGIN
    DECLARE @Result VARCHAR(5) = NULL;
    SELECT TOP 1 @Result = RIGHT(NO_BATTERYPACK, 5)
    FROM TB_M_INIT_QRCODE
    WHERE FMODEL_BATTERY = @Model
      AND NO_BATTERYPACK IS NOT NULL
    ORDER BY FID ASC;
    RETURN @Result;
END;
GO
PRINT '+ GetPackPartByModel: updated';

PRINT '=== STEP 3: Triggers ===';

-- --------------------------------------------------------
-- 3A. TB_RECEIVER_SUBSYSTEM_AFTER_INSERT: CREATE OR ALTER
--     Depends on: TB_M_BATTERY_MAPPING.ORDER_TYPE, TB_R_TARGET_PROD.ORDER_TYPE
-- --------------------------------------------------------
CREATE OR ALTER TRIGGER [dbo].[TB_RECEIVER_SUBSYSTEM_AFTER_INSERT]
ON [dbo].[TB_R_RECEIVER_SUBSYSTEM]
AFTER INSERT
AS
BEGIN
    SET NOCOUNT ON;

    -- External READ_FLG update intentionally disabled.
    -- UPDATE r
    -- SET r.READ_FLG = 1
    -- FROM SUBSYSTEM_HV_P1.dbo.TB_R_RECEIVER r
    -- JOIN inserted i ON r.ID_RECEIVER = CONVERT(UNIQUEIDENTIFIER, i.ID_RECEIVER);

    DECLARE @IncomingUnits TABLE (
        FTYPE_BATTERY varchar(20),
        FMODEL_BATTERY varchar(30),
        ID_RECEIVER varchar(50),
        ALC_DATA varchar(255),
        FSEQ_K0 varchar(3),
        FBODY_NO_K0 varchar(5)
    );

    INSERT INTO @IncomingUnits (FTYPE_BATTERY, FMODEL_BATTERY, ID_RECEIVER, ALC_DATA, FSEQ_K0, FBODY_NO_K0)
    SELECT DISTINCT
        m.FTYPE_BATTERY,
        m.FMODEL_BATTERY,
        i.ID_RECEIVER,
        i.ALC_DATA,
        SUBSTRING(i.ALC_DATA, 4, 3) AS FSEQ_K0,
        SUBSTRING(i.ALC_DATA, 7, 5) AS FBODY_NO_K0
    FROM inserted i
    JOIN TB_M_BATTERY_MAPPING m
        ON m.FKATASHIKI = SUBSTRING(i.ALC_DATA, 50, 4)
    WHERE m.ORDER_TYPE = 'Assy';

    INSERT INTO TB_R_TARGET_PROD (FTYPE_BATTERY, FMODEL_BATTERY, ORDER_TYPE, FTARGET, FDATETIME_MODIFIED)
    SELECT DISTINCT u.FTYPE_BATTERY, u.FMODEL_BATTERY, 'Assy', 0, GETDATE()
    FROM @IncomingUnits u
    WHERE NOT EXISTS (
        SELECT 1
        FROM TB_R_TARGET_PROD t
        WHERE t.FTYPE_BATTERY = u.FTYPE_BATTERY
          AND t.FMODEL_BATTERY = u.FMODEL_BATTERY
    );

    UPDATE t
    SET
        t.FTARGET            = t.FTARGET + 1,
        t.ORDER_TYPE         = 'Assy',
        t.FID_RECEIVER       = u.ID_RECEIVER,
        t.FALC_DATA          = u.ALC_DATA,
        t.FSEQ_K0            = u.FSEQ_K0,
        t.FBODY_NO_K0        = u.FBODY_NO_K0,
        t.FPROD_DATE         = CAST(GETDATE() AS DATE),
        t.FDATETIME_MODIFIED = GETDATE()
    FROM TB_R_TARGET_PROD t
    JOIN @IncomingUnits u
        ON t.FTYPE_BATTERY = u.FTYPE_BATTERY
       AND t.FMODEL_BATTERY = u.FMODEL_BATTERY;
END;
GO
PRINT '+ TB_RECEIVER_SUBSYSTEM_AFTER_INSERT: updated';

-- --------------------------------------------------------
-- 3B. TB_R_TARGET_PROD_AFTER_UPDATE: CREATE OR ALTER
--     Delta-sequence trigger (global seq per FTYPE+MODEL)
--     Depends on: TB_R_TARGET_PROD.ORDER_TYPE,
--                 TB_R_SEQUENCE_BATTERY.ORDER_TYPE,
--                 TB_M_BATTERY_MAPPING.ORDER_TYPE
-- --------------------------------------------------------
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER OFF;
GO
CREATE OR ALTER TRIGGER [dbo].[TB_R_TARGET_PROD_AFTER_UPDATE]
ON [dbo].[TB_R_TARGET_PROD]
AFTER UPDATE
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @BaseAdjust INT;
    SELECT @BaseAdjust = ISNULL(MAX(FID_ADJUST), 0)
    FROM TB_R_SEQUENCE_BATTERY;

    -- Delta > 0: insert only additional sequences, continuing from global last seq
    -- per FTYPE+MODEL (shared across order types).
    ;WITH Deltas AS (
        SELECT
            i.FID AS TargetFID,
            i.FTYPE_BATTERY,
            i.FMODEL_BATTERY,
            i.ORDER_TYPE,
            ISNULL(i.FPROD_DATE, CAST(GETDATE() AS DATE)) AS ProdDate,
            i.FID_RECEIVER,
            i.FALC_DATA,
            i.FSEQ_K0,
            i.FBODY_NO_K0,
            i.FDATETIME_MODIFIED,
            ISNULL(i.FTARGET, 0) - ISNULL(d.FTARGET, 0) AS Delta
        FROM inserted i
        JOIN deleted d ON i.FID = d.FID
        WHERE ISNULL(i.FTARGET, 0) > ISNULL(d.FTARGET, 0)
    ),
    ScopeMax AS (
        SELECT
            s.FTYPE_BATTERY,
            s.FMODEL_BATTERY,
            ISNULL(MAX(s.FSEQ_NO), 0) AS MaxSeq
        FROM TB_R_SEQUENCE_BATTERY s
        WHERE EXISTS (
            SELECT 1
            FROM Deltas dm
            WHERE dm.FTYPE_BATTERY = s.FTYPE_BATTERY
              AND dm.FMODEL_BATTERY = s.FMODEL_BATTERY
        )
        GROUP BY s.FTYPE_BATTERY, s.FMODEL_BATTERY
    ),
    Nums AS (
        SELECT ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS n
        FROM (VALUES(0),(0),(0),(0),(0),(0),(0),(0),(0),(0)) a(x)
        CROSS JOIN (VALUES(0),(0),(0),(0),(0),(0),(0),(0),(0),(0)) b(x)
        CROSS JOIN (VALUES(0),(0),(0),(0),(0),(0),(0),(0),(0),(0)) c(x)
        CROSS JOIN (VALUES(0),(0),(0),(0),(0),(0),(0),(0),(0),(0)) d(x)
    ),
    Expanded AS (
        SELECT
            d.FTYPE_BATTERY,
            d.FMODEL_BATTERY,
            d.ORDER_TYPE,
            d.ProdDate,
            CASE WHEN d.ORDER_TYPE = 'Assy' THEN d.FID_RECEIVER ELSE NULL END AS FID_RECEIVER,
            CASE WHEN d.ORDER_TYPE = 'Assy' THEN d.FALC_DATA ELSE NULL END AS FALC_DATA,
            CASE WHEN d.ORDER_TYPE = 'Assy' THEN d.FSEQ_K0 ELSE NULL END AS FSEQ_K0,
            CASE WHEN d.ORDER_TYPE = 'Assy' THEN d.FBODY_NO_K0 ELSE NULL END AS FBODY_NO_K0,
            CASE WHEN d.ORDER_TYPE = 'Assy' THEN d.FDATETIME_MODIFIED ELSE NULL END AS FTIME_RECEIVED,
            ISNULL(sm.MaxSeq, 0) + ROW_NUMBER() OVER (
                PARTITION BY d.FTYPE_BATTERY, d.FMODEL_BATTERY
                ORDER BY d.TargetFID, n.n
            ) AS FSEQ_NO
        FROM Deltas d
        JOIN Nums n ON n.n <= d.Delta
        LEFT JOIN ScopeMax sm
            ON sm.FTYPE_BATTERY = d.FTYPE_BATTERY
           AND sm.FMODEL_BATTERY = d.FMODEL_BATTERY
    )
    INSERT INTO TB_R_SEQUENCE_BATTERY (
        FTYPE_BATTERY, FMODEL_BATTERY, ORDER_TYPE,
        FSEQ_NO, FSEQ_DATE, FSTATUS,
        FID_RECEIVER, FALC_DATA, FSEQ_K0, FBODY_NO_K0, FTIME_RECEIVED,
        FBARCODE, FID_ADJUST
    )
    SELECT
        e.FTYPE_BATTERY,
        e.FMODEL_BATTERY,
        e.ORDER_TYPE,
        e.FSEQ_NO,
        e.ProdDate,
        0,
        e.FID_RECEIVER,
        e.FALC_DATA,
        e.FSEQ_K0,
        e.FBODY_NO_K0,
        e.FTIME_RECEIVED,
        CONCAT(
            ISNULL(C1.FVALUE, ''), ISNULL(C2.FVALUE, ''), e.FTYPE_BATTERY,
            ISNULL(C3.FVALUE, ''), ISNULL(M.FPACK_PART_BATTERY, ''),
            ISNULL(C4.FVALUE, ''), ISNULL(C5.FVALUE, ''),
            ISNULL(Y.FCODE_YEAR, ''),
            ISNULL(MD_MONTH.FCODE, ''),
            ISNULL(MD_DAY.FCODE, ''),
            RIGHT(CONCAT('0000000', e.FSEQ_NO), 7)
        ),
        @BaseAdjust + ROW_NUMBER() OVER (
            ORDER BY e.FTYPE_BATTERY, e.FMODEL_BATTERY, e.ORDER_TYPE, e.FSEQ_NO
        )
    FROM Expanded e
    LEFT JOIN TB_M_BATTERY_MAPPING M
        ON M.FTYPE_BATTERY = e.FTYPE_BATTERY
       AND M.FMODEL_BATTERY = e.FMODEL_BATTERY
    LEFT JOIN TB_M_LABEL_CONSTANT C1 ON C1.FKEY = 'MANUFACTURER'
    LEFT JOIN TB_M_LABEL_CONSTANT C2 ON C2.FKEY = 'PROD_TYPE'
    LEFT JOIN TB_M_LABEL_CONSTANT C3 ON C3.FKEY = 'SPEC_NO'
    LEFT JOIN TB_M_LABEL_CONSTANT C4 ON C4.FKEY = 'LINE_NO'
    LEFT JOIN TB_M_LABEL_CONSTANT C5 ON C5.FKEY = 'ADDRESS'
    LEFT JOIN TB_M_PROD_YEAR Y ON Y.FYEAR = YEAR(e.ProdDate)
    LEFT JOIN TB_M_PROD_MONTH_DAY MD_MONTH ON MD_MONTH.FMONTH_DAY = MONTH(e.ProdDate)
    LEFT JOIN TB_M_PROD_MONTH_DAY MD_DAY ON MD_DAY.FMONTH_DAY = DAY(e.ProdDate)
    WHERE NOT EXISTS (
        SELECT 1
        FROM TB_R_SEQUENCE_BATTERY s
        WHERE s.FTYPE_BATTERY = e.FTYPE_BATTERY
          AND s.FMODEL_BATTERY = e.FMODEL_BATTERY
          AND s.FSEQ_NO = e.FSEQ_NO
    );

    -- Delta < 0: delete newest pending rows only for affected order type.
    ;WITH PlanDecreases AS (
        SELECT
            i.FTYPE_BATTERY,
            i.FMODEL_BATTERY,
            i.ORDER_TYPE,
            ISNULL(d.FTARGET, 0) - ISNULL(i.FTARGET, 0) AS DropCount
        FROM inserted i
        JOIN deleted d ON i.FID = d.FID
        WHERE ISNULL(i.FTARGET, 0) < ISNULL(d.FTARGET, 0)
          AND i.ORDER_TYPE <> 'Assy'
    ),
    PendingRanked AS (
        SELECT
            s.FID,
            ROW_NUMBER() OVER (
                PARTITION BY s.FTYPE_BATTERY, s.FMODEL_BATTERY, s.ORDER_TYPE
                ORDER BY s.FSEQ_NO DESC
            ) AS rn,
            pd.DropCount
        FROM TB_R_SEQUENCE_BATTERY s
        JOIN PlanDecreases pd
            ON s.FTYPE_BATTERY = pd.FTYPE_BATTERY
           AND s.FMODEL_BATTERY = pd.FMODEL_BATTERY
           AND s.ORDER_TYPE = pd.ORDER_TYPE
        WHERE s.FSTATUS = 0
    )
    DELETE FROM TB_R_SEQUENCE_BATTERY
    WHERE FID IN (
        SELECT FID
        FROM PendingRanked
        WHERE rn <= DropCount
    );

    -- Resequence pending rows after decrease to keep global continuity
    -- per FTYPE+MODEL while preserving completed sequence numbers.
    ;WITH PlanDecreases AS (
        SELECT DISTINCT
            i.FTYPE_BATTERY,
            i.FMODEL_BATTERY
        FROM inserted i
        JOIN deleted d ON i.FID = d.FID
        WHERE ISNULL(i.FTARGET, 0) < ISNULL(d.FTARGET, 0)
          AND i.ORDER_TYPE <> 'Assy'
    ),
    CompletedBase AS (
        SELECT
            pd.FTYPE_BATTERY,
            pd.FMODEL_BATTERY,
            ISNULL(MAX(CASE WHEN s.FSTATUS <> 0 THEN s.FSEQ_NO END), 0) AS BaseSeq
        FROM PlanDecreases pd
        LEFT JOIN TB_R_SEQUENCE_BATTERY s
            ON s.FTYPE_BATTERY = pd.FTYPE_BATTERY
           AND s.FMODEL_BATTERY = pd.FMODEL_BATTERY
        GROUP BY pd.FTYPE_BATTERY, pd.FMODEL_BATTERY
    ),
    PendingOrdered AS (
        SELECT
            s.FID,
            s.FTYPE_BATTERY,
            s.FMODEL_BATTERY,
            s.ORDER_TYPE,
            s.FSEQ_DATE,
            cb.BaseSeq + ROW_NUMBER() OVER (
                PARTITION BY s.FTYPE_BATTERY, s.FMODEL_BATTERY
                ORDER BY s.FSEQ_NO, s.FID
            ) AS NewSeq
        FROM TB_R_SEQUENCE_BATTERY s
        JOIN CompletedBase cb
            ON cb.FTYPE_BATTERY = s.FTYPE_BATTERY
           AND cb.FMODEL_BATTERY = s.FMODEL_BATTERY
        WHERE s.FSTATUS = 0
    )
    UPDATE s
    SET
        s.FSEQ_NO = p.NewSeq,
        s.FBARCODE = CONCAT(
            ISNULL(C1.FVALUE, ''), ISNULL(C2.FVALUE, ''), s.FTYPE_BATTERY,
            ISNULL(C3.FVALUE, ''), ISNULL(M.FPACK_PART_BATTERY, ''),
            ISNULL(C4.FVALUE, ''), ISNULL(C5.FVALUE, ''),
            ISNULL(Y.FCODE_YEAR, ''),
            ISNULL(MD_MONTH.FCODE, ''),
            ISNULL(MD_DAY.FCODE, ''),
            RIGHT(CONCAT('0000000', p.NewSeq), 7)
        )
    FROM TB_R_SEQUENCE_BATTERY s
    JOIN PendingOrdered p ON p.FID = s.FID
    LEFT JOIN TB_M_BATTERY_MAPPING M
        ON M.FTYPE_BATTERY = s.FTYPE_BATTERY
       AND M.FMODEL_BATTERY = s.FMODEL_BATTERY
    LEFT JOIN TB_M_LABEL_CONSTANT C1 ON C1.FKEY = 'MANUFACTURER'
    LEFT JOIN TB_M_LABEL_CONSTANT C2 ON C2.FKEY = 'PROD_TYPE'
    LEFT JOIN TB_M_LABEL_CONSTANT C3 ON C3.FKEY = 'SPEC_NO'
    LEFT JOIN TB_M_LABEL_CONSTANT C4 ON C4.FKEY = 'LINE_NO'
    LEFT JOIN TB_M_LABEL_CONSTANT C5 ON C5.FKEY = 'ADDRESS'
    LEFT JOIN TB_M_PROD_YEAR Y ON Y.FYEAR = YEAR(s.FSEQ_DATE)
    LEFT JOIN TB_M_PROD_MONTH_DAY MD_MONTH ON MD_MONTH.FMONTH_DAY = MONTH(s.FSEQ_DATE)
    LEFT JOIN TB_M_PROD_MONTH_DAY MD_DAY ON MD_DAY.FMONTH_DAY = DAY(s.FSEQ_DATE);

    -- READ_FLG update for Assy source rows.
    UPDATE r
    SET r.READ_FLG = 1
    FROM TB_R_RECEIVER_SUBSYSTEM r
    JOIN inserted i ON r.ID_RECEIVER = i.FID_RECEIVER
    WHERE i.ORDER_TYPE = 'Assy'
      AND i.FID_RECEIVER IS NOT NULL;
END;
GO
PRINT '+ TB_R_TARGET_PROD_AFTER_UPDATE: updated';

-- --------------------------------------------------------
-- 3C. TR_ORDER_TYPE_SYNC_QRCODE: CREATE OR ALTER (new trigger)
--     Syncs TB_M_PROD_ORDER_TYPE changes to TB_M_INIT_QRCODE
--     Depends on: TB_M_INIT_QRCODE.ORDER_TYPE, TB_M_PROD_MODEL.FMODEL_BATTERY
-- --------------------------------------------------------
CREATE OR ALTER TRIGGER [dbo].[TR_ORDER_TYPE_SYNC_QRCODE]
ON [dbo].[TB_M_PROD_ORDER_TYPE]
AFTER INSERT, UPDATE
AS
BEGIN
    SET NOCOUNT ON;

    -- IS_ACTIVE = 1: insert kombinasi ORDER_TYPE x FMODEL_BATTERY yang belum ada
    INSERT INTO TB_M_INIT_QRCODE (ORDER_TYPE, FMODEL_BATTERY)
    SELECT i.ORDER_TYPE, m.FMODEL_BATTERY
    FROM inserted i
    CROSS JOIN TB_M_PROD_MODEL m
    WHERE i.IS_ACTIVE = 1
      AND m.IS_ACTIVE = 1
      AND m.FMODEL_BATTERY IS NOT NULL
      AND NOT EXISTS (
          SELECT 1 FROM TB_M_INIT_QRCODE q
          WHERE q.ORDER_TYPE = i.ORDER_TYPE
            AND q.FMODEL_BATTERY = m.FMODEL_BATTERY
      );

    -- IS_ACTIVE = 0: delete semua kombinasi untuk order type ini
    DELETE q
    FROM TB_M_INIT_QRCODE q
    INNER JOIN inserted i ON q.ORDER_TYPE = i.ORDER_TYPE
    WHERE i.IS_ACTIVE = 0;
END;
GO
PRINT '+ TR_ORDER_TYPE_SYNC_QRCODE: created';

-- --------------------------------------------------------
-- 3D. TR_PROD_MODEL_SYNC_QRCODE: CREATE OR ALTER (new trigger)
--     Syncs TB_M_PROD_MODEL changes to TB_M_INIT_QRCODE
--     Depends on: TB_M_INIT_QRCODE.ORDER_TYPE, TB_M_PROD_MODEL.FMODEL_BATTERY
-- --------------------------------------------------------
CREATE OR ALTER TRIGGER [dbo].[TR_PROD_MODEL_SYNC_QRCODE]
ON [dbo].[TB_M_PROD_MODEL]
AFTER INSERT, UPDATE
AS
BEGIN
    SET NOCOUNT ON;

    -- IS_ACTIVE = 1: insert kombinasi FMODEL_BATTERY x ORDER_TYPE yang belum ada
    INSERT INTO TB_M_INIT_QRCODE (ORDER_TYPE, FMODEL_BATTERY)
    SELECT ot.ORDER_TYPE, i.FMODEL_BATTERY
    FROM inserted i
    CROSS JOIN TB_M_PROD_ORDER_TYPE ot
    WHERE i.IS_ACTIVE = 1
      AND i.FMODEL_BATTERY IS NOT NULL
      AND ot.IS_ACTIVE = 1
      AND NOT EXISTS (
          SELECT 1 FROM TB_M_INIT_QRCODE q
          WHERE q.ORDER_TYPE = ot.ORDER_TYPE
            AND q.FMODEL_BATTERY = i.FMODEL_BATTERY
      );

    -- IS_ACTIVE = 0: delete semua kombinasi untuk model ini
    DELETE q
    FROM TB_M_INIT_QRCODE q
    INNER JOIN inserted i ON q.FMODEL_BATTERY = i.FMODEL_BATTERY
    WHERE i.IS_ACTIVE = 0;
END;
GO
PRINT '+ TR_PROD_MODEL_SYNC_QRCODE: created';

-- --------------------------------------------------------
-- 3E. TR_PLAN_DETAIL_SYNC_TARGET_PROD: CREATE OR ALTER (new trigger)
--     Syncs TB_H_PROD_PLAN_DETAIL changes to TB_R_TARGET_PROD (delta qty)
--     Depends on: TB_R_TARGET_PROD.ORDER_TYPE, TB_M_PROD_MODEL.FTYPE_BATTERY
-- --------------------------------------------------------
CREATE OR ALTER TRIGGER [dbo].[TR_PLAN_DETAIL_SYNC_TARGET_PROD]
ON [dbo].[TB_H_PROD_PLAN_DETAIL]
AFTER INSERT, UPDATE
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @PlanDeltas TABLE (
        FTYPE_BATTERY varchar(20),
        FMODEL_BATTERY varchar(30),
        ORDER_TYPE nvarchar(50),
        DeltaQty int
    );

    INSERT INTO @PlanDeltas (FTYPE_BATTERY, FMODEL_BATTERY, ORDER_TYPE, DeltaQty)
    SELECT
        pm.FTYPE_BATTERY,
        pm.FMODEL_BATTERY,
        i.ORDER_TYPE,
        i.QTY_PLAN - CASE
            WHEN ISNULL(d.SEQ_GENERATED, 0) = 1 THEN ISNULL(d.QTY_PLAN, 0)
            ELSE 0
        END AS DeltaQty
    FROM inserted i
    LEFT JOIN deleted d ON d.FID = i.FID
    JOIN TB_M_PROD_MODEL pm ON UPPER(pm.FMODEL_BATTERY) = UPPER(i.MODEL_NAME)
    WHERE i.ORDER_TYPE <> 'Assy'
      AND ISNULL(i.SEQ_GENERATED, 0) = 1
      AND pm.FTYPE_BATTERY IS NOT NULL
      AND pm.FMODEL_BATTERY IS NOT NULL;

    INSERT INTO TB_R_TARGET_PROD (FTYPE_BATTERY, FMODEL_BATTERY, ORDER_TYPE, FTARGET, FDATETIME_MODIFIED)
    SELECT DISTINCT p.FTYPE_BATTERY, p.FMODEL_BATTERY, p.ORDER_TYPE, 0, GETDATE()
    FROM @PlanDeltas p
    WHERE NOT EXISTS (
        SELECT 1
        FROM TB_R_TARGET_PROD t
        WHERE t.FTYPE_BATTERY = p.FTYPE_BATTERY
          AND t.FMODEL_BATTERY = p.FMODEL_BATTERY
    );

    UPDATE t
    SET
        t.FTARGET = t.FTARGET + p.DeltaQty,
        t.ORDER_TYPE = p.ORDER_TYPE,
        t.FPROD_DATE = CAST(GETDATE() AS DATE),
        t.FDATETIME_MODIFIED = GETDATE()
    FROM TB_R_TARGET_PROD t
    JOIN @PlanDeltas p
      ON t.FTYPE_BATTERY = p.FTYPE_BATTERY
     AND t.FMODEL_BATTERY = p.FMODEL_BATTERY
    WHERE p.DeltaQty <> 0;
END;
GO
PRINT '+ TR_PLAN_DETAIL_SYNC_TARGET_PROD: created';

PRINT '';
PRINT '=== MIGRATION COMPLETE ===';
PRINT 'Summary of changes deployed to remote server:';
PRINT '  Schema: TB_M_BATTERY_MAPPING.ORDER_TYPE (add)';
PRINT '  Schema: TB_M_INIT_QRCODE.ORDER_TYPE (add)';
PRINT '  Schema: TB_M_PROD_MODEL.MODEL_NAME -> FMODEL_BATTERY (rename)';
PRINT '  Schema: TB_M_PROD_MODEL.FTYPE_BATTERY (add)';
PRINT '  Schema: TB_R_SEQUENCE_BATTERY.ORDER_TYPE (add)';
PRINT '  Schema: TB_R_TARGET_PROD.ORDER_TYPE (add)';
PRINT '  Function: GetPackPartByModel (update)';
PRINT '  Trigger: TB_RECEIVER_SUBSYSTEM_AFTER_INSERT (update)';
PRINT '  Trigger: TB_R_TARGET_PROD_AFTER_UPDATE (update - global delta seq)';
PRINT '  Trigger: TR_ORDER_TYPE_SYNC_QRCODE (new)';
PRINT '  Trigger: TR_PROD_MODEL_SYNC_QRCODE (new)';
PRINT '  Trigger: TR_PLAN_DETAIL_SYNC_TARGET_PROD (new)';
