USE [DB_TMMIN1_KRW_BARCODE_DS3678]
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

ALTER TRIGGER [dbo].[TB_R_SCAN_MODUL_ID_AFTER_INSERT]
ON [dbo].[TB_R_SCAN_MODUL_ID]
AFTER INSERT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @FinalRows TABLE (
        ScanID BIGINT,
        FID BIGINT,
        DEV_NAME VARCHAR(255),
        TR_TIME DATETIME,
        SCAN_NUMBER INT,
        First24Digits VARCHAR(24),
        DaysSinceProduction INT,
        JUDGE_VALUE VARCHAR(1),
        LIFETIME_VALUE VARCHAR(3),
        ModuleSuffix VARCHAR(1)
    );

    -- Hitung data sekali, lalu dipakai untuk insert T_TRANSMIT dan update RFID map.
    WITH ExtractedData AS (
        SELECT
            i.ID AS ScanID,
            i.FID,
            i.DEV_NAME,
            i.REG_VALUE,
            i.TR_TIME,
            i.SCAN_NUMBER,
            LEFT(i.REG_VALUE, 24) AS First24Digits
        FROM inserted i
        WHERE LEN(i.REG_VALUE) >= 24
    ),
    ProductionCode AS (
        SELECT
            ed.*,
            SUBSTRING(ed.First24Digits, 15, 1) AS YearCode,
            SUBSTRING(ed.First24Digits, 16, 1) AS MonthCode,
            SUBSTRING(ed.First24Digits, 17, 1) AS DayCode
        FROM ExtractedData ed
    ),
    ActualDate AS (
        SELECT
            pc.*,
            y.FYEAR AS ProductionYear,
            m1.FMONTH_DAY AS ProductionMonth,
            m2.FMONTH_DAY AS ProductionDay
        FROM ProductionCode pc
        INNER JOIN [DB_TMMIN1_KRW_PIS_HV_BATTERY].[dbo].[TB_M_PROD_YEAR] y
            ON pc.YearCode = y.FCODE_YEAR
        INNER JOIN [DB_TMMIN1_KRW_PIS_HV_BATTERY].[dbo].[TB_M_PROD_MONTH_DAY] m1
            ON pc.MonthCode = m1.FCODE
        INNER JOIN [DB_TMMIN1_KRW_PIS_HV_BATTERY].[dbo].[TB_M_PROD_MONTH_DAY] m2
            ON pc.DayCode = m2.FCODE
    ),
    DaysDiff AS (
        SELECT
            ad.*,
            DATEDIFF(
                DAY,
                CAST(CONCAT(ad.ProductionYear, '-', ad.ProductionMonth, '-', ad.ProductionDay) AS DATE),
                CAST(GETDATE() AS DATE)
            ) AS DaysSinceProduction
        FROM ActualDate ad
        WHERE TRY_CAST(CONCAT(ad.ProductionYear, '-', ad.ProductionMonth, '-', ad.ProductionDay) AS DATE) IS NOT NULL
    )
    INSERT INTO @FinalRows (
        ScanID,
        FID,
        DEV_NAME,
        TR_TIME,
        SCAN_NUMBER,
        First24Digits,
        DaysSinceProduction,
        JUDGE_VALUE,
        LIFETIME_VALUE,
        ModuleSuffix
    )
    SELECT
        dd.ScanID,
        dd.FID,
        dd.DEV_NAME,
        dd.TR_TIME,
        dd.SCAN_NUMBER,
        dd.First24Digits,
        dd.DaysSinceProduction,
        CASE
            WHEN dd.DaysSinceProduction <= 50 THEN '0'
            ELSE '1'
        END AS JUDGE_VALUE,
        CAST(dd.DaysSinceProduction AS VARCHAR(3)) AS LIFETIME_VALUE,
        CASE dd.SCAN_NUMBER
            WHEN 1 THEN '1'
            WHEN 2 THEN '2'
            ELSE 'X'
        END AS ModuleSuffix
    FROM DaysDiff dd;

    -- Jika lifetime <= 50, langsung kirim ke T_TRANSMIT.
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
        fr.TR_TIME,
        CAST(fr.FID AS VARCHAR(50))
    FROM @FinalRows fr
    CROSS APPLY (
        VALUES
            ('JUDGE_LIFETIME_MODULE' + fr.ModuleSuffix, fr.JUDGE_VALUE),
            ('LIFETIME_MODULE' + fr.ModuleSuffix, fr.LIFETIME_VALUE),
            ('MODULE_' + fr.ModuleSuffix, fr.First24Digits)
    ) AS v(REG_NAME, REG_VALUE)
    WHERE fr.DaysSinceProduction <= 50;

    -- Jika lifetime <= 50, update RFID map untuk station UNLOADING.
    ;WITH RfidMapSource AS (
        SELECT
            CASE fr.SCAN_NUMBER
                WHEN 1 THEN 'LI MODULE ASSY 1'
                WHEN 2 THEN 'LI MODULE ASSY 2'
                ELSE NULL
            END AS TargetName,
            fr.First24Digits AS TargetValueAscii,
            ROW_NUMBER() OVER (
                PARTITION BY fr.SCAN_NUMBER
                ORDER BY fr.TR_TIME DESC, fr.ScanID DESC
            ) AS rn
        FROM @FinalRows fr
        WHERE fr.DaysSinceProduction <= 50
          AND fr.SCAN_NUMBER IN (1, 2)
    )
    UPDATE rm
    SET rm.VALUE_ASCII = src.TargetValueAscii
    FROM [DB_TMMIN1_KRW_RFID_V680S].[dbo].[TB_R_RFID_MAP] rm
    INNER JOIN RfidMapSource src
        ON rm.FIELD_NAME = src.TargetName
       AND src.rn = 1
    WHERE rm.STATION_NAME = 'UNLOADING';
END;
GO
