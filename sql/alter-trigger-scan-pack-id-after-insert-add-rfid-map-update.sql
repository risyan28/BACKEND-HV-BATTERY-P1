USE [DB_TMMIN1_KRW_BARCODE_DS3678]
GO
/****** Object:  Trigger [dbo].[TB_R_SCAN_PACK_ID_AFTER_INSERT]    Script Date: 21/04/2026 17:25:58 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

ALTER TRIGGER [dbo].[TB_R_SCAN_PACK_ID_AFTER_INSERT]
ON [dbo].[TB_R_SCAN_PACK_ID]
AFTER INSERT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @ValidRows TABLE (
        ID BIGINT,
        FID BIGINT,
        REG_VALUE VARCHAR(255),
        TR_TIME DATETIME
    );

    -- Simpan hanya data PACK_ID yang valid (ada di TB_R_SEQUENCE_BATTERY.FBARCODE).
    INSERT INTO @ValidRows (ID, FID, REG_VALUE, TR_TIME)
    SELECT
        i.ID,
        i.FID,
        i.REG_VALUE,
        i.TR_TIME
    FROM inserted i
    WHERE EXISTS (
        SELECT 1
        FROM [DB_TMMIN1_KRW_PIS_HV_BATTERY].[dbo].[TB_R_SEQUENCE_BATTERY] b
        WHERE b.FBARCODE = i.REG_VALUE
    );

    -- Insert PACK_ID + JUDGE_PACK_ID dari data yang valid.
    INSERT INTO [DB_MYOPC_CLIENT_PIS_HV_BATTERY_P1].[dbo].[T_TRANSMIT] (
        DEV_NAME,
        REG_NAME,
        REG_VALUE,
        TTL,
        TR_TIME,
        ID
    )
    SELECT
        'PLC_HV_BATT.STATION UN LOADING',
        v.REG_NAME,
        v.REG_VALUE,
        10,
        ISNULL(vr.TR_TIME, GETDATE()),
        CAST(vr.FID AS VARCHAR(50))
    FROM @ValidRows vr
    CROSS APPLY (
        VALUES
            ('PACK_ID', vr.REG_VALUE),
            ('JUDGE_PACK_ID', '0')
    ) AS v(REG_NAME, REG_VALUE);

    -- Update RFID map FIELD_NAME = 'LABEL PACK ID' untuk station UNLOADING.
    ;WITH LatestPack AS (
        SELECT TOP (1)
            vr.REG_VALUE
        FROM @ValidRows vr
        ORDER BY vr.TR_TIME DESC, vr.ID DESC
    )
    UPDATE rm
    SET rm.VALUE_ASCII = lp.REG_VALUE
    FROM [DB_TMMIN1_KRW_RFID_V680S].[dbo].[TB_R_RFID_MAP] rm
    INNER JOIN LatestPack lp
        ON 1 = 1
    WHERE rm.STATION_NAME = 'UNLOADING'
      AND rm.FIELD_NAME = 'LABEL PACK ID';
END;
GO
