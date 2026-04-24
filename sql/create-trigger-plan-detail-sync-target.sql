-- Trigger: TR_PLAN_DETAIL_SYNC_TARGET_PROD
-- Purpose: When TB_H_PROD_PLAN_DETAIL.SEQ_GENERATED changes from 0 -> 1,
--          increment TB_R_ANDON_GLOBAL counter where FNAME='TARGET' by the QTY_PLAN value

USE [DB_TMMIN1_KRW_PIS_HV_BATTERY];
GO

CREATE OR ALTER TRIGGER [dbo].[TR_PLAN_DETAIL_SYNC_TARGET_PROD]
ON [dbo].[TB_H_PROD_PLAN_DETAIL]
AFTER INSERT, UPDATE
AS
BEGIN
    SET NOCOUNT ON;

    -- Only proceed if SEQ_GENERATED was updated
    IF NOT UPDATE(SEQ_GENERATED)
        RETURN;

    DECLARE @Now DATETIME = GETDATE();
    DECLARE @TotalQtyPlan INT = 0;

    -- Calculate sum of QTY_PLAN for rows where SEQ_GENERATED flips 0 -> 1
    SELECT @TotalQtyPlan = ISNULL(SUM(ISNULL(i.QTY_PLAN, 0)), 0)
    FROM inserted i
    JOIN deleted d ON i.FID = d.FID
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

END
GO
