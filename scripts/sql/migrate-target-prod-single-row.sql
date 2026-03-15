USE [DB_TMMIN1_KRW_PIS_HV_BATTERY]
GO

BEGIN TRY
    BEGIN TRAN;

    IF OBJECT_ID('tempdb..#TargetConsolidated') IS NOT NULL DROP TABLE #TargetConsolidated;

    ;WITH Base AS (
        SELECT
            t.FID,
            t.FTYPE_BATTERY,
            t.FMODEL_BATTERY,
            t.ORDER_TYPE,
            ISNULL(t.FTARGET, 0) AS FTARGET,
            t.FPROD_DATE,
            t.FDATETIME_MODIFIED,
            t.FID_RECEIVER,
            t.FALC_DATA,
            t.FSEQ_K0,
            t.FBODY_NO_K0
        FROM TB_R_TARGET_PROD t
    ),
    Agg AS (
        SELECT
            FTYPE_BATTERY,
            FMODEL_BATTERY,
            SUM(FTARGET) AS FTARGET_TOTAL,
            MAX(FPROD_DATE) AS LAST_PROD_DATE,
            MAX(FDATETIME_MODIFIED) AS LAST_MODIFIED
        FROM Base
        GROUP BY FTYPE_BATTERY, FMODEL_BATTERY
    ),
    LastOrder AS (
        SELECT
            b.FTYPE_BATTERY,
            b.FMODEL_BATTERY,
            b.ORDER_TYPE,
            ROW_NUMBER() OVER (
                PARTITION BY b.FTYPE_BATTERY, b.FMODEL_BATTERY
                ORDER BY b.FDATETIME_MODIFIED DESC, b.FID DESC
            ) AS rn
        FROM Base b
    ),
    LastAssy AS (
        SELECT
            b.FTYPE_BATTERY,
            b.FMODEL_BATTERY,
            b.FID_RECEIVER,
            b.FALC_DATA,
            b.FSEQ_K0,
            b.FBODY_NO_K0,
            ROW_NUMBER() OVER (
                PARTITION BY b.FTYPE_BATTERY, b.FMODEL_BATTERY
                ORDER BY b.FDATETIME_MODIFIED DESC, b.FID DESC
            ) AS rn
        FROM Base b
        WHERE b.ORDER_TYPE = 'Assy'
    )
    SELECT
        a.FTYPE_BATTERY,
        a.FMODEL_BATTERY,
        lo.ORDER_TYPE,
        a.FTARGET_TOTAL,
        a.LAST_PROD_DATE,
        a.LAST_MODIFIED,
        la.FID_RECEIVER,
        la.FALC_DATA,
        la.FSEQ_K0,
        la.FBODY_NO_K0
    INTO #TargetConsolidated
    FROM Agg a
    LEFT JOIN LastOrder lo
        ON lo.FTYPE_BATTERY = a.FTYPE_BATTERY
       AND lo.FMODEL_BATTERY = a.FMODEL_BATTERY
       AND lo.rn = 1
    LEFT JOIN LastAssy la
        ON la.FTYPE_BATTERY = a.FTYPE_BATTERY
       AND la.FMODEL_BATTERY = a.FMODEL_BATTERY
       AND la.rn = 1;

    DELETE FROM TB_R_TARGET_PROD;

    INSERT INTO TB_R_TARGET_PROD (
        FTYPE_BATTERY,
        FMODEL_BATTERY,
        ORDER_TYPE,
        FTARGET,
        FPROD_DATE,
        FID_RECEIVER,
        FALC_DATA,
        FSEQ_K0,
        FBODY_NO_K0,
        FDATETIME_MODIFIED
    )
    SELECT
        FTYPE_BATTERY,
        FMODEL_BATTERY,
        ORDER_TYPE,
        FTARGET_TOTAL,
        LAST_PROD_DATE,
        FID_RECEIVER,
        FALC_DATA,
        FSEQ_K0,
        FBODY_NO_K0,
        ISNULL(LAST_MODIFIED, GETDATE())
    FROM #TargetConsolidated;

    IF EXISTS (
        SELECT 1
        FROM sys.key_constraints
        WHERE parent_object_id = OBJECT_ID('TB_R_TARGET_PROD')
          AND name = 'UQ_TARGET_PROD_TYPE_MODEL_OT'
          AND type = 'UQ'
    )
    BEGIN
        ALTER TABLE TB_R_TARGET_PROD DROP CONSTRAINT UQ_TARGET_PROD_TYPE_MODEL_OT;
    END;

    IF NOT EXISTS (
        SELECT 1 FROM sys.indexes
        WHERE object_id = OBJECT_ID('TB_R_TARGET_PROD')
          AND name = 'UQ_TARGET_PROD_TYPE_MODEL'
    )
    BEGIN
        CREATE UNIQUE INDEX UQ_TARGET_PROD_TYPE_MODEL
            ON TB_R_TARGET_PROD (FTYPE_BATTERY, FMODEL_BATTERY);
    END;

    COMMIT TRAN;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRAN;
    THROW;
END CATCH;
GO

CREATE OR ALTER TRIGGER [dbo].[TR_PLAN_DETAIL_SYNC_TARGET_PROD]
ON [dbo].[TB_H_PROD_PLAN_DETAIL]
AFTER INSERT, UPDATE
AS
BEGIN
    SET NOCOUNT ON;

    ;WITH PlanDeltas AS (
        SELECT
            pm.FTYPE_BATTERY,
            pm.FMODEL_BATTERY,
            i.ORDER_TYPE,
            i.QTY_PLAN - ISNULL(d.QTY_PLAN, 0) AS DeltaQty
        FROM inserted i
        LEFT JOIN deleted d ON d.FID = i.FID
        JOIN TB_M_PROD_MODEL pm
            ON UPPER(pm.FMODEL_BATTERY) = UPPER(i.MODEL_NAME)
        WHERE i.ORDER_TYPE <> 'Assy'
          AND pm.FTYPE_BATTERY IS NOT NULL
          AND pm.FMODEL_BATTERY IS NOT NULL
    )
    INSERT INTO TB_R_TARGET_PROD (FTYPE_BATTERY, FMODEL_BATTERY, ORDER_TYPE, FTARGET, FDATETIME_MODIFIED)
    SELECT p.FTYPE_BATTERY, p.FMODEL_BATTERY, p.ORDER_TYPE, 0, GETDATE()
    FROM PlanDeltas p
    WHERE NOT EXISTS (
        SELECT 1 FROM TB_R_TARGET_PROD t
        WHERE t.FTYPE_BATTERY  = p.FTYPE_BATTERY
          AND t.FMODEL_BATTERY = p.FMODEL_BATTERY
    );

    UPDATE t
    SET
        t.FTARGET            = t.FTARGET + p.DeltaQty,
        t.ORDER_TYPE         = p.ORDER_TYPE,
        t.FPROD_DATE         = CAST(GETDATE() AS DATE),
        t.FDATETIME_MODIFIED = GETDATE()
    FROM TB_R_TARGET_PROD t
    JOIN PlanDeltas p
        ON t.FTYPE_BATTERY  = p.FTYPE_BATTERY
       AND t.FMODEL_BATTERY = p.FMODEL_BATTERY
    WHERE p.DeltaQty <> 0;
END;
GO

CREATE OR ALTER TRIGGER [dbo].[TB_RECEIVER_SUBSYSTEM_AFTER_INSERT]
ON [dbo].[TB_R_RECEIVER_SUBSYSTEM]
AFTER INSERT
AS
BEGIN
    SET NOCOUNT ON;

    UPDATE r
    SET r.READ_FLG = 1
    FROM SUBSYSTEM_HV_P1.dbo.TB_R_RECEIVER r
    JOIN inserted i ON r.ID_RECEIVER = CONVERT(UNIQUEIDENTIFIER, i.ID_RECEIVER);

    ;WITH IncomingUnits AS (
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
        WHERE m.ORDER_TYPE = 'Assy'
    )
    INSERT INTO TB_R_TARGET_PROD (FTYPE_BATTERY, FMODEL_BATTERY, ORDER_TYPE, FTARGET, FDATETIME_MODIFIED)
    SELECT DISTINCT u.FTYPE_BATTERY, u.FMODEL_BATTERY, 'Assy', 0, GETDATE()
    FROM IncomingUnits u
    WHERE NOT EXISTS (
        SELECT 1 FROM TB_R_TARGET_PROD t
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
    JOIN IncomingUnits u
        ON t.FTYPE_BATTERY = u.FTYPE_BATTERY
       AND t.FMODEL_BATTERY = u.FMODEL_BATTERY;
END;
GO
