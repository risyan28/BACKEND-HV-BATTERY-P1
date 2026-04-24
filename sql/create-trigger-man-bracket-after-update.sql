-- Trigger: TB_R_MAN_BRACKET_AFTER_INSERT (AFTER UPDATE)
-- Purpose: when TB_R_MAN_BRACKET.FVALUE changes from 0 -> 1, increment the
--          corresponding actual counter in TB_R_ANDON_GLOBAL:
--          DESTINATION='ASSY' -> FNAME='ACT_ASSY'
--          DESTINATION='CKD'  -> FNAME='ACT_CKD'

USE [DB_TMMIN1_KRW_PIS_HV_BATTERY];
GO

CREATE OR ALTER TRIGGER [dbo].[TB_R_MAN_BRACKET_AFTER_UPDATE]
ON [dbo].[TB_R_MAN_BRACKET]
AFTER UPDATE
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT UPDATE(FVALUE)
        RETURN;

    DECLARE @Now DATETIME = GETDATE();
    DECLARE @PackIDFJ NVARCHAR(100);
    DECLARE @ProdDate DATE;
    DECLARE @ShiftKey NVARCHAR(50);
    DECLARE @OrderTypeKey NVARCHAR(50);
    DECLARE @ModelKey NVARCHAR(50);

    -- Take BARCODE from the row(s) where FVALUE flips 0 -> 1
    SELECT TOP (1)
        @PackIDFJ = i.BARCODE
    FROM inserted i
    JOIN deleted d ON i.FID = d.FID
    WHERE ISNULL(d.FVALUE, 0) = 0
      AND ISNULL(i.FVALUE, 0) = 1
      AND NULLIF(LTRIM(RTRIM(i.BARCODE)), '') IS NOT NULL
    ORDER BY i.FID DESC;

    -- Increment once per destination (ASSY/CKD) for any row that flips 0->1
    UPDATE g
    SET
        g.FVALUE = ISNULL(g.FVALUE, 0) + 1,
        g.FUPDATE = @Now
    FROM dbo.TB_R_ANDON_GLOBAL g
    JOIN (
        SELECT DISTINCT
            UPPER(LTRIM(RTRIM(ISNULL(i.DESTINATION, '')))) AS DEST
        FROM inserted i
        JOIN deleted d ON i.FID = d.FID
        WHERE ISNULL(d.FVALUE, 0) = 0
          AND ISNULL(i.FVALUE, 0) = 1
          AND UPPER(LTRIM(RTRIM(ISNULL(i.DESTINATION, '')))) IN ('ASSY', 'CKD')
    ) x
      ON g.FNAME = 'ACT_' + x.DEST;


    -- Update production plan detail actual qty when FVALUE flips 0 -> 1
        -- Increment by +1 (assumes only one row flips 0->1 per update)
        SELECT TOP (1)
                @ProdDate = CONVERT(date, i.PROD_DATE),
                @ShiftKey = UPPER(LTRIM(RTRIM(ISNULL(i.SHIFT, '')))),
                @OrderTypeKey = UPPER(LTRIM(RTRIM(ISNULL(i.DESTINATION, '')))),
                @ModelKey = UPPER(LTRIM(RTRIM(ISNULL(i.FMODEL_BATTERY, ''))))
        FROM inserted i
        JOIN deleted d ON i.FID = d.FID
        WHERE ISNULL(d.FVALUE, 0) = 0
            AND ISNULL(i.FVALUE, 0) = 1
            AND i.PROD_DATE IS NOT NULL
            AND NULLIF(LTRIM(RTRIM(ISNULL(i.SHIFT, ''))), '') IS NOT NULL
            AND NULLIF(LTRIM(RTRIM(ISNULL(i.DESTINATION, ''))), '') IS NOT NULL
            AND NULLIF(LTRIM(RTRIM(ISNULL(i.FMODEL_BATTERY, ''))), '') IS NOT NULL
        ORDER BY i.FID DESC;

        IF (@ProdDate IS NOT NULL)
        BEGIN
                UPDATE d
                SET
                        d.QTY_ACTUAL = ISNULL(d.QTY_ACTUAL, 0) + 1,
                        d.UPDATED_AT = @Now
                FROM dbo.TB_H_PROD_PLAN_DETAIL d
                WHERE d.PROD_DATE = @ProdDate
                    AND UPPER(LTRIM(RTRIM(ISNULL(d.SHIFT, '')))) = @ShiftKey
                    AND UPPER(LTRIM(RTRIM(ISNULL(d.ORDER_TYPE, '')))) = @OrderTypeKey
                    AND UPPER(LTRIM(RTRIM(ISNULL(d.MODEL_NAME, '')))) = @ModelKey;
        END


    -- Also trigger UNIFY write only when there is a 0 -> 1 flip and BARCODE exists
    IF (@PackIDFJ IS NOT NULL)
    BEGIN
        UPDATE [DB_TMMIN1_KRW_ATLAS_COPCO].[dbo].[TB_R_WRITE_DEVICE_AIS]
        SET
            REG_VALUE = N'{"headers": {},"params": {"associatedEntityId": "'
                + REPLACE(@PackIDFJ, '"', '\"')
                + '","associatedEntityType": "20"}}',
            WRITE_FLAG = 0,
            TR_TIME = @Now
        WHERE
            DEV_NAME = 'UNIFY'
            AND TAG_NAME = '/unify/v1/results/tightening';
    END
END
GO
