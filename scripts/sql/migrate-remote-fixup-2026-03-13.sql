-- ============================================================
-- FIXUP MIGRATION: Remaining objects after partial deploy
-- Date: 2026-03-13
-- NOTE: Each CREATE OR ALTER must be the FIRST statement
--       in its GO batch. PRINT separated by GO.
-- ============================================================
USE [DB_TMMIN1_KRW_PIS_HV_BATTERY];
GO

-- --------------------------------------------------------
-- GetPackPartByModel: UPDATE
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
GO

-- --------------------------------------------------------
-- TB_RECEIVER_SUBSYSTEM_AFTER_INSERT: UPDATE
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
GO

-- --------------------------------------------------------
-- TR_ORDER_TYPE_SYNC_QRCODE: CREATE (new)
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
GO

-- --------------------------------------------------------
-- TR_PROD_MODEL_SYNC_QRCODE: CREATE (new)
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
GO

-- --------------------------------------------------------
-- TR_PLAN_DETAIL_SYNC_TARGET_PROD: CREATE (new)
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
GO
PRINT '=== ALL DONE ===';
GO
