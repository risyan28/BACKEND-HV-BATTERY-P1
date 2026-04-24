-- Alter existing trigger to ADD new functionality
-- Adds: When SEQ_GENERATED flips 0->1, increment TB_R_ANDON_GLOBAL.FVALUE where FNAME='TARGET'
-- Existing code blocks remain UNCHANGED

USE [DB_TMMIN1_KRW_PIS_HV_BATTERY];
GO

ALTER TRIGGER [dbo].[TR_PLAN_DETAIL_SYNC_TARGET_PROD]
ON dbo.TB_H_PROD_PLAN_DETAIL
AFTER INSERT, UPDATE
AS
BEGIN
    SET NOCOUNT ON;

    -- ═══════════════════════════════════════════════════════════════
    -- EXISTING CODE BLOCK 1: Sync to TB_R_TARGET_PROD (UNCHANGED)
    -- ═══════════════════════════════════════════════════════════════
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

    -- ═══════════════════════════════════════════════════════════════
    -- NEW CODE BLOCK: Sync SEQ_GENERATED 0->1 to TB_R_ANDON_GLOBAL
    -- ═══════════════════════════════════════════════════════════════
    DECLARE @Now DATETIME = GETDATE();
    DECLARE @TotalQtyPlan INT = 0;

    -- Calculate sum of QTY_PLAN for rows where SEQ_GENERATED flips 0 -> 1
    SELECT @TotalQtyPlan = ISNULL(SUM(ISNULL(i.QTY_PLAN, 0)), 0)
    FROM inserted i
    LEFT JOIN deleted d ON i.FID = d.FID
    WHERE ISNULL(d.SEQ_GENERATED, 0) = 0
      AND ISNULL(i.SEQ_GENERATED, 0) = 1;

    -- Only update if there are rows that flipped 0 -> 1
    IF @TotalQtyPlan > 0
    BEGIN
        UPDATE dbo.TB_R_ANDON_GLOBAL
        SET
            FVALUE = ISNULL(FVALUE, 0) + @TotalQtyPlan,
            FUPDATE = @Now
        WHERE FNAME = 'TARGET';
    END

END;
GO
