-- =============================================
-- Trigger: TB_R_READ_DEVICE_AIS_AFTER_UPDATE
-- Database: DB_TMMIN1_KRW_BARCODE_DS3678
-- Table: dbo.TB_R_READ_DEVICE_AIS
-- Action: AFTER UPDATE
-- 
-- Description:
--   When the serial scanner (MAN-BRACKET-BARCODE) updates
--   RAW_DATA (TR_TIME changes), write the scanned barcode to
--   TB_R_SCAN_MAN_BRACKET in DB_TMMIN1_KRW_PIS_HV_BATTERY
--   so the backend WS can emit to the FE for auto-submit.
-- =============================================
USE DB_TMMIN1_KRW_BARCODE_DS3678;
GO

IF EXISTS (SELECT * FROM sys.triggers WHERE name = 'TB_R_READ_DEVICE_AIS_AFTER_UPDATE')
  DROP TRIGGER TB_R_READ_DEVICE_AIS_AFTER_UPDATE;
GO

CREATE TRIGGER dbo.TB_R_READ_DEVICE_AIS_AFTER_UPDATE
ON dbo.TB_R_READ_DEVICE_AIS
AFTER UPDATE
AS
BEGIN
  SET NOCOUNT ON;

  -- Only process MAN-BRACKET-BARCODE with RAW_DATA
  -- and only when TR_TIME actually changed (new scan event)
  IF EXISTS (
    SELECT 1
    FROM inserted i
    INNER JOIN deleted d ON d.FID = i.FID
    WHERE i.DEV_NAME = 'MAN-BRACKET-BARCODE'
      AND i.TAG_NAME = 'RAW_DATA'
      AND i.REG_VALUE IS NOT NULL
      AND LTRIM(RTRIM(i.REG_VALUE)) <> ''
      AND (i.TR_TIME <> d.TR_TIME
        OR (d.TR_TIME IS NULL AND i.TR_TIME IS NOT NULL))
  )
  BEGIN
    DECLARE @barcode VARCHAR(100)
    DECLARE @regValue VARCHAR(MAX)

    SELECT TOP 1 @regValue = i.REG_VALUE
    FROM inserted i
    INNER JOIN deleted d ON d.FID = i.FID
    WHERE i.DEV_NAME = 'MAN-BRACKET-BARCODE'
      AND i.TAG_NAME = 'RAW_DATA'
      AND i.REG_VALUE IS NOT NULL
      AND LTRIM(RTRIM(i.REG_VALUE)) <> ''
      AND (i.TR_TIME <> d.TR_TIME
        OR (d.TR_TIME IS NULL AND i.TR_TIME IS NOT NULL))
    ORDER BY i.FID DESC

    SET @barcode = UPPER(LTRIM(RTRIM(@regValue)))

    -- Write to scan buffer in PIS_HV_BATTERY database
    UPDATE DB_TMMIN1_KRW_PIS_HV_BATTERY.dbo.TB_R_SCAN_MAN_BRACKET
    SET BARCODE = @barcode,
        FLAG = 0,
        UPDATED_AT = GETDATE()
    WHERE FID = 1
  END
END;
GO

PRINT 'Trigger TB_R_READ_DEVICE_AIS_AFTER_UPDATE created successfully.';
SELECT 'Trigger created' AS result;
GO
