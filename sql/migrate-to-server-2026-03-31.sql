-- ============================================================
-- MIGRATION SCRIPT: LOCAL -> SERVER (192.168.250.2,1433)
-- Generated: 2026-03-31 14:20
-- DB: DB_TMMIN1_KRW_PIS_HV_BATTERY
-- !! DATA IS NEVER MODIFIED. Safe to run multiple times. !!
-- ============================================================

USE [DB_TMMIN1_KRW_PIS_HV_BATTERY];
GO
SET NOCOUNT ON;
GO

PRINT '=== STEP 1: Functions ==='
GO
-- GetPackPartByModel
CREATE OR ALTER FUNCTION [dbo].[GetPackPartByModel] (@Model VARCHAR(50)) RETURNS VARCHAR(5) AS BEGIN DECLARE @Result VARCHAR(5) = NULL; SELECT TOP 1 @Result = RIGHT(NO_BATTERYPACK, 5) FROM TB_M_INIT_QRCODE WHERE FMODEL_BATTERY = @Model AND NO_BATTERYPACK IS NOT NULL ORDER BY FID ASC; RETURN @Result; END;
GO
PRINT '+ GetPackPartByModel : created/updated';
GO

PRINT '=== STEP 2: Stored Procedures ==='
GO
-- SP_APPLY_SEQUENCE_STRATEGY
CREATE OR ALTER PROCEDURE dbo.SP_APPLY_SEQUENCE_STRATEGY
  @Mode NVARCHAR(20),
  @PriorityType NVARCHAR(50) = NULL,
  @RatioPrimary NVARCHAR(50) = NULL,
  @RatioSecondary NVARCHAR(50) = NULL,
  @RatioTertiary NVARCHAR(50) = NULL,
  @RatioAssy INT = 2,
  @RatioCkd INT = 1,
  @RatioServicePart INT = 1
AS
BEGIN
  SET NOCOUNT ON;

  DECLARE @ModeN NVARCHAR(20) = LOWER(LTRIM(RTRIM(ISNULL(@Mode, 'normal'))));
  DECLARE @PriorityN NVARCHAR(50) = UPPER(LTRIM(RTRIM(ISNULL(@PriorityType, 'ASSY'))));
  DECLARE @PrimaryN NVARCHAR(50) = UPPER(LTRIM(RTRIM(ISNULL(@RatioPrimary, 'ASSY'))));
  DECLARE @SecondaryN NVARCHAR(50) = UPPER(LTRIM(RTRIM(ISNULL(@RatioSecondary, 'CKD'))));
  DECLARE @TertiaryN NVARCHAR(50) = UPPER(LTRIM(RTRIM(ISNULL(@RatioTertiary, 'SERVICE PART'))));

  IF (@RatioAssy IS NULL OR @RatioAssy < 1) SET @RatioAssy = 1;
  IF (@RatioCkd IS NULL OR @RatioCkd < 1) SET @RatioCkd = 1;
  IF (@RatioServicePart IS NULL OR @RatioServicePart < 1) SET @RatioServicePart = 1;

  DECLARE @Queue TABLE (
    FID INT PRIMARY KEY,
    FSEQ_NO INT,
    FID_ADJUST INT,
    ORDER_TYPE_NORM NVARCHAR(20),
    Processed BIT NOT NULL DEFAULT(0)
  );

  INSERT INTO @Queue (FID, FSEQ_NO, FID_ADJUST, ORDER_TYPE_NORM)
  SELECT
    s.FID,
    s.FSEQ_NO,
    ISNULL(s.FID_ADJUST, 2147483647),
    CASE
      WHEN UPPER(LTRIM(RTRIM(ISNULL(s.ORDER_TYPE, '')))) = 'ASSY'
        OR UPPER(LTRIM(RTRIM(ISNULL(s.ORDER_TYPE, '')))) LIKE '%- ASSY'
        OR UPPER(LTRIM(RTRIM(ISNULL(s.ORDER_TYPE, '')))) LIKE '%-ASSY' THEN 'ASSY'
      WHEN UPPER(LTRIM(RTRIM(ISNULL(s.ORDER_TYPE, '')))) = 'CKD'
        OR UPPER(LTRIM(RTRIM(ISNULL(s.ORDER_TYPE, '')))) LIKE '%- CKD'
        OR UPPER(LTRIM(RTRIM(ISNULL(s.ORDER_TYPE, '')))) LIKE '%-CKD' THEN 'CKD'
      WHEN UPPER(LTRIM(RTRIM(ISNULL(s.ORDER_TYPE, '')))) = 'SERVICE PART'
        OR UPPER(LTRIM(RTRIM(ISNULL(s.ORDER_TYPE, '')))) LIKE '%- SERVICE PART'
        OR UPPER(LTRIM(RTRIM(ISNULL(s.ORDER_TYPE, '')))) LIKE '%-SERVICE PART' THEN 'SERVICE PART'
      ELSE 'OTHER'
    END
  FROM dbo.TB_R_SEQUENCE_BATTERY s
  WHERE s.FSTATUS = 0;

  IF NOT EXISTS (SELECT 1 FROM @Queue)
    RETURN;

  DECLARE @Result TABLE (
    Seq INT IDENTITY(1,1) PRIMARY KEY,
    FID INT
  );

  IF @ModeN = 'normal'
  BEGIN
    INSERT INTO @Result(FID)
    SELECT q.FID
    FROM @Queue q
    ORDER BY q.FSEQ_NO, q.FID_ADJUST, q.FID;
  END
  ELSE IF @ModeN = 'priority'
  BEGIN
    INSERT INTO @Result(FID)
    SELECT q.FID
    FROM @Queue q
    ORDER BY
      CASE WHEN q.ORDER_TYPE_NORM = @PriorityN THEN 0 ELSE 1 END,
      q.FSEQ_NO,
      q.FID_ADJUST,
      q.FID;
  END
  ELSE
  BEGIN
    DECLARE @RatioOrder TABLE (
      Seq INT IDENTITY(1,1) PRIMARY KEY,
      ORDER_TYPE_NORM NVARCHAR(20) UNIQUE
    );

    ;WITH RawSort AS (
      SELECT
        CASE
          WHEN UPPER(LTRIM(RTRIM(ISNULL(ORDER_TYPE, '')))) = 'ASSY' THEN 'ASSY'
          WHEN UPPER(LTRIM(RTRIM(ISNULL(ORDER_TYPE, '')))) = 'CKD' THEN 'CKD'
          WHEN UPPER(LTRIM(RTRIM(ISNULL(ORDER_TYPE, '')))) IN ('SERVICE PART', 'SERVICE_PART') THEN 'SERVICE PART'
          ELSE NULL
        END AS ORDER_TYPE_NORM,
        ISNULL(SORT_ORDER, 2147483647) AS SORT_ORDER
      FROM dbo.TB_M_PROD_ORDER_TYPE
    ),
    Dedup AS (
      SELECT ORDER_TYPE_NORM, MIN(SORT_ORDER) AS SORT_ORDER
      FROM RawSort
      WHERE ORDER_TYPE_NORM IS NOT NULL
      GROUP BY ORDER_TYPE_NORM
    )
    INSERT INTO @RatioOrder (ORDER_TYPE_NORM)
    SELECT TOP 3 d.ORDER_TYPE_NORM
    FROM Dedup d
    ORDER BY d.SORT_ORDER, d.ORDER_TYPE_NORM;

    IF NOT EXISTS (SELECT 1 FROM @RatioOrder WHERE ORDER_TYPE_NORM = 'ASSY')
      INSERT INTO @RatioOrder (ORDER_TYPE_NORM) VALUES ('ASSY');
    IF NOT EXISTS (SELECT 1 FROM @RatioOrder WHERE ORDER_TYPE_NORM = 'CKD')
      INSERT INTO @RatioOrder (ORDER_TYPE_NORM) VALUES ('CKD');
    IF NOT EXISTS (SELECT 1 FROM @RatioOrder WHERE ORDER_TYPE_NORM = 'SERVICE PART')
      INSERT INTO @RatioOrder (ORDER_TYPE_NORM) VALUES ('SERVICE PART');

    DECLARE @Pattern TABLE (Seq INT IDENTITY(1,1) PRIMARY KEY, ORDER_TYPE_NORM NVARCHAR(20));
    DECLARE @PatternType NVARCHAR(20);
    DECLARE @RepeatCount INT;
    DECLARE @i INT;

    DECLARE ratio_order_cursor CURSOR LOCAL FAST_FORWARD FOR
      SELECT TOP 3 ORDER_TYPE_NORM
      FROM @RatioOrder
      ORDER BY Seq;

    OPEN ratio_order_cursor;
    FETCH NEXT FROM ratio_order_cursor INTO @PatternType;

    WHILE @@FETCH_STATUS = 0
    BEGIN
      SET @RepeatCount =
        CASE
          WHEN @PatternType = 'ASSY' THEN @RatioAssy
          WHEN @PatternType = 'CKD' THEN @RatioCkd
          ELSE @RatioServicePart
        END;

      SET @i = 1;
      WHILE @i <= @RepeatCount
      BEGIN
        INSERT INTO @Pattern (ORDER_TYPE_NORM) VALUES (@PatternType);
        SET @i += 1;
      END

      FETCH NEXT FROM ratio_order_cursor INTO @PatternType;
    END

    CLOSE ratio_order_cursor;
    DEALLOCATE ratio_order_cursor;

    DECLARE @PickFID INT;

    WHILE EXISTS (
      SELECT 1
      FROM @Queue
      WHERE Processed = 0
        AND ORDER_TYPE_NORM IN ('ASSY', 'CKD', 'SERVICE PART')
    )
    BEGIN
      DECLARE pattern_cursor CURSOR LOCAL FAST_FORWARD FOR
        SELECT ORDER_TYPE_NORM FROM @Pattern ORDER BY Seq;

      OPEN pattern_cursor;
      FETCH NEXT FROM pattern_cursor INTO @PatternType;

      WHILE @@FETCH_STATUS = 0
      BEGIN
        SET @PickFID = NULL;

        SELECT TOP 1 @PickFID = q.FID
        FROM @Queue q
        WHERE q.Processed = 0
          AND q.ORDER_TYPE_NORM = @PatternType
        ORDER BY q.FSEQ_NO, q.FID_ADJUST, q.FID;

        IF @PickFID IS NOT NULL
        BEGIN
          INSERT INTO @Result(FID) VALUES (@PickFID);
          UPDATE @Queue SET Processed = 1 WHERE FID = @PickFID;
        END

        FETCH NEXT FROM pattern_cursor INTO @PatternType;
      END

      CLOSE pattern_cursor;
      DEALLOCATE pattern_cursor;
    END

    INSERT INTO @Result(FID)
    SELECT q.FID
    FROM @Queue q
    WHERE q.Processed = 0
    ORDER BY
      CASE WHEN q.ORDER_TYPE_NORM IN ('ASSY', 'CKD', 'SERVICE PART') THEN 0 ELSE 1 END,
      q.FSEQ_NO,
      q.FID_ADJUST,
      q.FID;
  END

  UPDATE s
  SET s.FID_ADJUST = r.Seq
  FROM dbo.TB_R_SEQUENCE_BATTERY s
  INNER JOIN @Result r ON r.FID = s.FID
  WHERE s.FSTATUS = 0;
END
GO
PRINT '+ SP_APPLY_SEQUENCE_STRATEGY : created/updated';
GO

-- sp_RefreshBatteryTraceabilityView
-- =============================================
-- OPTIMIZED VERSION - MENGHILANGKAN TRIM() di JOIN
-- Asumsi: Data sudah clean atau akan dibersihkan di source
-- =============================================

CREATE OR ALTER PROCEDURE [dbo].[sp_RefreshBatteryTraceabilityView]
WITH RECOMPILE  -- Prevent compilation errors with dynamic schema
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @SQL NVARCHAR(MAX) = '';
    DECLARE @PivotColumns NVARCHAR(MAX) = '';
    DECLARE @SelectColumns NVARCHAR(MAX) = '';
    DECLARE @FinalJudgementColumns NVARCHAR(MAX) = '';
    DECLARE @InspectionMachineColumns NVARCHAR(MAX) = '';
    DECLARE @ModuleInspectionColumns NVARCHAR(MAX) = '';
    DECLARE @Module1CellColumns NVARCHAR(MAX) = '';
    DECLARE @Module2CellColumns NVARCHAR(MAX) = '';
    DECLARE @RowCount INT = 0;
    DECLARE @FinalJudgementColCount INT = 0;
    DECLARE @InspectionMachineColCount INT = 0;
    DECLARE @ModuleInspectionColCount INT = 0;
    DECLARE @TighteningColCount INT = 0;
    DECLARE @Module1CellColCount INT = 28;
    DECLARE @Module2CellColCount INT = 28;
    DECLARE @TotalColumnCount INT = 0;
    DECLARE @StartTime DATETIME = GETDATE();

    BEGIN TRY
        -- =============================================
        -- Step 1: Build Final Judgement columns (only 3 specific columns)
        -- =============================================
        PRINT '?? Building TB_H_POS_FINAL_JUDGEMENT columns...';
        
        -- Only include LIFETIME_MODULE1, LIFETIME_MODULE2, and OVERALL_JUDGEMENT
        SET @FinalJudgementColumns = 
            '    f.[LIFETIME_MODULE1] AS [LIFETIME_MODULE1_FINAL_JUDGE],' + CHAR(10) +
            '    f.[LIFETIME_MODULE2] AS [LIFETIME_MODULE2_FINAL_JUDGE],' + CHAR(10) +
            '    f.[OVERALL_JUDGEMENT]';
        
        SET @FinalJudgementColCount = 3;
        
        PRINT '   Using ' + CAST(@FinalJudgementColCount AS VARCHAR(10)) + ' columns (LIFETIME_MODULE1, LIFETIME_MODULE2, OVERALL_JUDGEMENT)';

        -- =============================================
        -- Step 2: Auto-detect Inspection Machine columns
        -- =============================================
        PRINT '?? Auto-detecting TB_H_TRACEABILITY_INSPECTION_MACHINE columns...';
        
        SELECT @InspectionMachineColumns = STUFF((
            SELECT ',' + CHAR(10) + '    tr.[' + COLUMN_NAME + '] AS [' + COLUMN_NAME + '_InspMachine]'
            FROM INFORMATION_SCHEMA.COLUMNS
            WHERE TABLE_NAME = 'TB_H_TRACEABILITY_INSPECTION_MACHINE'
                AND COLUMN_NAME NOT IN ('Pack_basic_information_Battery_pack_No', 'PACK_ID', 'MODULE_1', 'MODULE_2', 'LIFETIME_MODULE1', 'LIFETIME_MODULE2', 'JUDGEMENT_VALUE', 'CREATED_AT')
            ORDER BY ORDINAL_POSITION
            FOR XML PATH(''), TYPE
        ).value('.', 'NVARCHAR(MAX)'), 1, 2, '');
        
        SELECT @InspectionMachineColCount = COUNT(*) 
        FROM INFORMATION_SCHEMA.COLUMNS 
        WHERE TABLE_NAME = 'TB_H_TRACEABILITY_INSPECTION_MACHINE' 
            AND COLUMN_NAME NOT IN ('Pack_basic_information_Battery_pack_No', 'PACK_ID', 'MODULE_1', 'MODULE_2', 'LIFETIME_MODULE1', 'LIFETIME_MODULE2', 'JUDGEMENT_VALUE', 'CREATED_AT');
        
        PRINT '   Found ' + CAST(@InspectionMachineColCount AS VARCHAR(10)) + ' columns';

        -- =============================================
        -- Step 3: Auto-detect Module Inspection columns
        -- =============================================
        PRINT '?? Auto-detecting TB_H_TRACEABILITY_MODULE_INSPECTION columns...';
        
        SELECT @ModuleInspectionColumns = STUFF((
            SELECT ',' + CHAR(10) + '    m.[' + COLUMN_NAME + '] AS [' + COLUMN_NAME + '_Module]'
            FROM INFORMATION_SCHEMA.COLUMNS
            WHERE TABLE_NAME = 'TB_H_TRACEABILITY_MODULE_INSPECTION'
                AND COLUMN_NAME NOT IN ('Fr_stack_ID', 'Rr_stack_ID', 'PACK_ID', 'MODULE_1', 'MODULE_2', 'LIFETIME_MODULE1', 'LIFETIME_MODULE2', 'JUDGEMENT_VALUE', 'CREATED_AT')
            ORDER BY ORDINAL_POSITION
            FOR XML PATH(''), TYPE
        ).value('.', 'NVARCHAR(MAX)'), 1, 2, '');
        
        SELECT @ModuleInspectionColCount = COUNT(*) 
        FROM INFORMATION_SCHEMA.COLUMNS 
        WHERE TABLE_NAME = 'TB_H_TRACEABILITY_MODULE_INSPECTION' 
            AND COLUMN_NAME NOT IN ('Fr_stack_ID', 'Rr_stack_ID', 'PACK_ID', 'MODULE_1', 'MODULE_2', 'LIFETIME_MODULE1', 'LIFETIME_MODULE2', 'JUDGEMENT_VALUE', 'CREATED_AT');
        
        PRINT '   Found ' + CAST(@ModuleInspectionColCount AS VARCHAR(10)) + ' columns';

        -- =============================================
        -- Step 4: Build MODULE_1 CELL_ID columns (28 cells)
        -- =============================================
        PRINT '?? Building MODULE_1 CELL_ID columns (28 cells)...';
        
        DECLARE @i INT = 1;
        SET @Module1CellColumns = '';
        
        WHILE @i <= 28
        BEGIN
            SET @Module1CellColumns = @Module1CellColumns + 
                '    sm1.CELL_ID_' + CAST(@i AS VARCHAR(2)) + ' AS [MODULE_1_CELL_ID_' + CAST(@i AS VARCHAR(2)) + '],' + CHAR(10);
            SET @i = @i + 1;
        END
        
        -- Remove trailing comma and newline
        SET @Module1CellColumns = LEFT(@Module1CellColumns, LEN(@Module1CellColumns) - 2);
        
        PRINT '   Generated ' + CAST(@Module1CellColCount AS VARCHAR(10)) + ' MODULE_1 CELL_ID columns';

        -- =============================================
        -- Step 5: Build MODULE_2 CELL_ID columns (28 cells)
        -- =============================================
        PRINT '?? Building MODULE_2 CELL_ID columns (28 cells)...';
        
        SET @i = 1;
        SET @Module2CellColumns = '';
        
        WHILE @i <= 28
        BEGIN
            SET @Module2CellColumns = @Module2CellColumns + 
                '    sm2.CELL_ID_' + CAST(@i AS VARCHAR(2)) + ' AS [MODULE_2_CELL_ID_' + CAST(@i AS VARCHAR(2)) + '],' + CHAR(10);
            SET @i = @i + 1;
        END
        
        -- Remove trailing comma and newline
        SET @Module2CellColumns = LEFT(@Module2CellColumns, LEN(@Module2CellColumns) - 2);
        
        PRINT '   Generated ' + CAST(@Module2CellColCount AS VARCHAR(10)) + ' MODULE_2 CELL_ID columns';

        -- =============================================
        -- Step 6: Auto-detect tightening structure from master table
        -- =============================================
        PRINT '?? Building pivot columns with TighteningName (3 metrics: Torque, Angle, Result)...';
        
        DECLARE @TempPivot TABLE (
            StationName NVARCHAR(255),
            TighteningSequence INT,
            TighteningName NVARCHAR(255),
            CleanStationName NVARCHAR(255),
            CleanTighteningName NVARCHAR(255)
        );
        
        -- Get tightening names from master table
        INSERT INTO @TempPivot (StationName, TighteningSequence, TighteningName, CleanStationName, CleanTighteningName)
        SELECT DISTINCT
            tn.StationName,
            tn.TighteningSequence,
            tn.TighteningName,
            -- Clean station name for column naming (remove spaces, special chars)
            REPLACE(REPLACE(REPLACE(REPLACE(tn.StationName, ' ', '_'), ',', '_'), '.', '_'), '-', '_') AS CleanStationName,
            -- Clean tightening name for column naming
            REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(tn.TighteningName, ' ', '_'), ',', '_'), '.', '_'), '-', '_'), '/', '_') AS CleanTighteningName
        FROM TB_M_TIGHTENING_NAME tn
        INNER JOIN TB_H_TIGHTENING_RESULT tr 
            ON tn.StationName = tr.StationName 
            AND tn.TighteningSequence = tr.TighteningSequence
        ORDER BY tn.StationName, tn.TighteningSequence;
        
        -- Generate pivot columns with descriptive names (3 metrics: Torque, Angle, Result)
        SELECT @PivotColumns = @PivotColumns + ',' + CHAR(10) +
            '    MAX(CASE WHEN StationName = ''' + StationName + ''' AND TighteningSequence = ' + CAST(TighteningSequence AS VARCHAR(5)) + 
            ' THEN TorqueMeasured END) AS [' + CleanStationName + '_' + CleanTighteningName + '_Torque],' + CHAR(10) +
            '    MAX(CASE WHEN StationName = ''' + StationName + ''' AND TighteningSequence = ' + CAST(TighteningSequence AS VARCHAR(5)) + 
            ' THEN AngleMeasured END) AS [' + CleanStationName + '_' + CleanTighteningName + '_Angle],' + CHAR(10) +
            '    MAX(CASE WHEN StationName = ''' + StationName + ''' AND TighteningSequence = ' + CAST(TighteningSequence AS VARCHAR(5)) + 
            ' THEN ResultEvaluation END) AS [' + CleanStationName + '_' + CleanTighteningName + '_Result]'
        FROM @TempPivot
        ORDER BY StationName, TighteningSequence;

        SET @PivotColumns = STUFF(@PivotColumns, 1, 2, '');
        SELECT @TighteningColCount = COUNT(*) * 3 FROM @TempPivot;

        -- Generate select columns with descriptive names (3 metrics)
        SELECT @SelectColumns = @SelectColumns + ',' + CHAR(10) +
            '    t.[' + CleanStationName + '_' + CleanTighteningName + '_Torque],' + CHAR(10) +
            '    t.[' + CleanStationName + '_' + CleanTighteningName + '_Angle],' + CHAR(10) +
            '    t.[' + CleanStationName + '_' + CleanTighteningName + '_Result]'
        FROM @TempPivot
        ORDER BY StationName, TighteningSequence;

        SET @SelectColumns = STUFF(@SelectColumns, 1, 2, '');
        
        PRINT '   Generated ' + CAST(@TighteningColCount AS VARCHAR(10)) + ' columns (Torque + Angle + Result)';

        -- =============================================
        -- Step 7: Validate column count
        -- =============================================
        SET @TotalColumnCount = 3 + @Module1CellColCount + @Module2CellColCount + 2 + @ModuleInspectionColCount + @TighteningColCount + @InspectionMachineColCount + @FinalJudgementColCount;
        
        PRINT '';
        PRINT '?? Column Count Summary:';
        PRINT '   Base: 3 | M1_Cells: ' + CAST(@Module1CellColCount AS VARCHAR(10)) + 
              ' | M2_Cells: ' + CAST(@Module2CellColCount AS VARCHAR(10)) + 
              ' | Lifetimes: 2';
        PRINT '   Module: ' + CAST(@ModuleInspectionColCount AS VARCHAR(10)) + 
              ' | Tightening: ' + CAST(@TighteningColCount AS VARCHAR(10)) + ' (Torque + Angle + Result)';
        PRINT '   Insp: ' + CAST(@InspectionMachineColCount AS VARCHAR(10)) + 
              ' | Final: ' + CAST(@FinalJudgementColCount AS VARCHAR(10));
        PRINT '   TOTAL: ' + CAST(@TotalColumnCount AS VARCHAR(10)) + ' / 1024';
        
        IF @TotalColumnCount > 1024
        BEGIN
            RAISERROR('? Column count exceeds 1024 limit!', 16, 1);
            RETURN;
        END
        PRINT '   ? Within safe limits';
        PRINT '';

        -- =============================================
        -- Step 8: Build OPTIMIZED VIEW (NO TRIM IN JOINS!)
        -- =============================================
        PRINT '?? Generating OPTIMIZED VW_TRACEABILITY_PIS...';
        PRINT '? KEY OPTIMIZATION: Removed TRIM() from all JOIN conditions for index usage';
        PRINT '   ??  IMPORTANT: Ensure data is clean or create indexed computed columns';
        PRINT '   ?? EXCEPTION: CELL_ID JOINs use TRIM() due to cross-database requirements';
        PRINT '';
        
        SET @SQL = '
IF EXISTS (SELECT * FROM sys.views WHERE name = ''VW_TRACEABILITY_PIS'')
    DROP VIEW VW_TRACEABILITY_PIS;
';
        
        EXEC sp_executesql @SQL;
        
        SET @SQL = '
CREATE VIEW VW_TRACEABILITY_PIS AS
SELECT 
    u.PACK_ID,
    u.MODULE_1,
' + @Module1CellColumns + ',
    u.MODULE_2,
' + @Module2CellColumns + ',
    u.LIFETIME_MODULE1 AS [LIFETIME_MODULE1_MODUL_INSPECTION],
    u.LIFETIME_MODULE2 AS [LIFETIME_MODULE2_MODUL_INSPECTION]'
    + CASE WHEN LEN(@ModuleInspectionColumns) > 0 THEN ',' + CHAR(10) + @ModuleInspectionColumns ELSE '' END
    + CASE WHEN LEN(@SelectColumns) > 0 THEN ',' + CHAR(10) + @SelectColumns ELSE '' END
    + CASE WHEN LEN(@InspectionMachineColumns) > 0 THEN ',' + CHAR(10) + @InspectionMachineColumns ELSE '' END
    + CASE WHEN LEN(@FinalJudgementColumns) > 0 THEN ',' + CHAR(10) + @FinalJudgementColumns ELSE '' END
    + ',' + CHAR(10) + '    CAST(u.CREATED_AT AS DATE) AS PROD_DATE'
    + '

FROM (
    SELECT *,
        ROW_NUMBER() OVER (
            PARTITION BY PACK_ID, MODULE_1, MODULE_2 
            ORDER BY CREATED_AT DESC
        ) AS rn
    FROM TB_H_POS_UNLOADING
) u

LEFT JOIN (
    SELECT *,
        ROW_NUMBER() OVER (
            PARTITION BY PACK_ID, MODULE_1, MODULE_2 
            ORDER BY CREATED_AT DESC
        ) AS rn
    FROM TB_H_POS_FINAL_JUDGEMENT
) f ON u.PACK_ID = f.PACK_ID AND f.rn = 1

LEFT JOIN (
    SELECT 
        MODULE_ID,
        SCAN_NUMBER,
        CELL_ID_1, CELL_ID_2, CELL_ID_3, CELL_ID_4, CELL_ID_5,
        CELL_ID_6, CELL_ID_7, CELL_ID_8, CELL_ID_9, CELL_ID_10,
        CELL_ID_11, CELL_ID_12, CELL_ID_13, CELL_ID_14, CELL_ID_15,
        CELL_ID_16, CELL_ID_17, CELL_ID_18, CELL_ID_19, CELL_ID_20,
        CELL_ID_21, CELL_ID_22, CELL_ID_23, CELL_ID_24, CELL_ID_25,
        CELL_ID_26, CELL_ID_27, CELL_ID_28,
        ROW_NUMBER() OVER (
            PARTITION BY TRIM(MODULE_ID), SCAN_NUMBER 
            ORDER BY CREATED_AT DESC
        ) AS rn
    FROM [DB_TMMIN1_KRW_BARCODE_DS3678].[dbo].TB_R_SCAN_MODUL_ID
) sm1 ON TRIM(u.MODULE_1) = TRIM(sm1.MODULE_ID)
    AND sm1.SCAN_NUMBER = 1
    AND sm1.rn = 1

LEFT JOIN (
    SELECT 
        MODULE_ID,
        SCAN_NUMBER,
        CELL_ID_1, CELL_ID_2, CELL_ID_3, CELL_ID_4, CELL_ID_5,
        CELL_ID_6, CELL_ID_7, CELL_ID_8, CELL_ID_9, CELL_ID_10,
        CELL_ID_11, CELL_ID_12, CELL_ID_13, CELL_ID_14, CELL_ID_15,
        CELL_ID_16, CELL_ID_17, CELL_ID_18, CELL_ID_19, CELL_ID_20,
        CELL_ID_21, CELL_ID_22, CELL_ID_23, CELL_ID_24, CELL_ID_25,
        CELL_ID_26, CELL_ID_27, CELL_ID_28,
        ROW_NUMBER() OVER (
            PARTITION BY TRIM(MODULE_ID), SCAN_NUMBER 
            ORDER BY CREATED_AT DESC
        ) AS rn
    FROM [DB_TMMIN1_KRW_BARCODE_DS3678].[dbo].TB_R_SCAN_MODUL_ID
) sm2 ON TRIM(u.MODULE_2) = TRIM(sm2.MODULE_ID)
    AND sm2.SCAN_NUMBER = 2
    AND sm2.rn = 1

LEFT JOIN (
    SELECT 
        LabelPackID,
        MAX(ExtractedAt) AS ExtractedAt,
        ' + @PivotColumns + '
    FROM (
        SELECT *,
            ROW_NUMBER() OVER (
                PARTITION BY LabelPackID, StationName, TighteningSequence 
                ORDER BY CreationTime DESC
            ) AS rn
        FROM TB_H_TIGHTENING_RESULT
    ) t_inner
    WHERE rn = 1
    GROUP BY LabelPackID
) t ON u.PACK_ID = t.LabelPackID

LEFT JOIN (
    SELECT *,
        ROW_NUMBER() OVER (
            PARTITION BY Pack_basic_information_Battery_pack_No 
            ORDER BY CREATED_AT DESC
        ) AS rn
    FROM TB_H_TRACEABILITY_INSPECTION_MACHINE
) tr ON u.PACK_ID = tr.Pack_basic_information_Battery_pack_No AND tr.rn = 1

LEFT JOIN (
    SELECT *,
        ROW_NUMBER() OVER (
            PARTITION BY Rr_stack_ID, Fr_stack_ID 
            ORDER BY CREATED_AT DESC
        ) AS rn
    FROM TB_H_TRACEABILITY_MODULE_INSPECTION
) m ON u.MODULE_1 = m.Rr_stack_ID
    AND u.MODULE_2 = m.Fr_stack_ID
    AND m.rn = 1

WHERE u.rn = 1;
';

        EXEC sp_executesql @SQL;

        DECLARE @Duration INT = DATEDIFF(SECOND, @StartTime, GETDATE());
        PRINT '? VIEW created successfully in ' + CAST(@Duration AS VARCHAR(10)) + ' seconds!';
        PRINT '';
        PRINT '?? NEXT STEPS FOR BETTER PERFORMANCE:';
        PRINT '   1. Create indexes on all JOIN key columns';
        PRINT '   2. If data has spaces, add computed persisted columns with TRIM()';
        PRINT '   3. Update statistics on all base tables';
        PRINT '   4. Consider indexed views for ROW_NUMBER() subqueries';

    END TRY
    BEGIN CATCH
        PRINT '? Error: ' + ERROR_MESSAGE();
        PRINT 'Line: ' + CAST(ERROR_LINE() AS VARCHAR(10));
        
        IF @@TRANCOUNT > 0
            ROLLBACK TRAN;
            
        THROW;
    END CATCH
END;
GO
PRINT '+ sp_RefreshBatteryTraceabilityView : created/updated';
GO

-- SP_REGENERATE_BATTERY_SEQUENCE
CREATE OR ALTER PROCEDURE [dbo].[SP_REGENERATE_BATTERY_SEQUENCE]
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @RowsAffected INT = 0;
    DECLARE @TargetRowsAffected INT = 0;
    
    BEGIN TRY
        BEGIN TRANSACTION;
        
        --  Step 1: Generate new sequence numbers per FTYPE_BATTERY + FMODEL_BATTERY 
        WITH RankedData AS (
            SELECT 
                FID,
                FSEQ_NO AS OLD_FSEQ_NO,
                RTRIM(LTRIM(FTYPE_BATTERY)) AS FTYPE_BATTERY,
                FMODEL_BATTERY,
                FSEQ_DATE,
                FBARCODE AS OLD_FBARCODE,
                -- Generate new sequence number starting from 1 for each FTYPE_BATTERY + FMODEL_BATTERY
                -- PARTITION BY ensures sequence resets to 1 for each different TYPE + MODEL combination
                ROW_NUMBER() OVER (
                    PARTITION BY RTRIM(LTRIM(FTYPE_BATTERY)), RTRIM(LTRIM(FMODEL_BATTERY))
                    ORDER BY FSEQ_DATE, FID
                ) AS NEW_FSEQ_NO
            FROM [DB_TMMIN1_KRW_PIS_HV_BATTERY].[dbo].[TB_R_SEQUENCE_BATTERY]
            WHERE FSTATUS = 0
        ),
        --  Step 2: Rebuild FBARCODE from master tables 
        UpdatedBarcode AS (
            SELECT 
                R.FID,
                R.OLD_FSEQ_NO,
                R.NEW_FSEQ_NO,
                R.FTYPE_BATTERY,
                R.FMODEL_BATTERY,
                R.OLD_FBARCODE,
                -- Rebuild FBARCODE menggunakan data master
                CONCAT(
                    ISNULL(C1.FVALUE, ''),           -- MANUFACTURER
                    ISNULL(C2.FVALUE, ''),           -- PROD_TYPE
                    R.FTYPE_BATTERY,                 -- FTYPE_BATTERY
                    ISNULL(C3.FVALUE, ''),           -- SPEC_NO
                    ISNULL(M.FPACK_PART_BATTERY, ''), -- FPACK_PART_BATTERY
                    ISNULL(C4.FVALUE, ''),           -- LINE_NO
                    ISNULL(C5.FVALUE, ''),           -- ADDRESS
                    ISNULL(Y.FCODE_YEAR, ''),        -- YEAR CODE
                    ISNULL(MD_MONTH.FCODE, ''),      -- MONTH CODE
                    ISNULL(MD_DAY.FCODE, ''),        -- DAY CODE
                    RIGHT(CONCAT('0000000', R.NEW_FSEQ_NO), 7)  -- 7-digit sequence
                ) AS NEW_FBARCODE
            FROM RankedData R
            LEFT JOIN [DB_TMMIN1_KRW_PIS_HV_BATTERY].[dbo].[TB_M_BATTERY_MAPPING] M 
                ON M.FTYPE_BATTERY = R.FTYPE_BATTERY 
                AND M.FMODEL_BATTERY = R.FMODEL_BATTERY
            LEFT JOIN [DB_TMMIN1_KRW_PIS_HV_BATTERY].[dbo].[TB_M_LABEL_CONSTANT] C1
                ON C1.FKEY = 'MANUFACTURER'
            LEFT JOIN [DB_TMMIN1_KRW_PIS_HV_BATTERY].[dbo].[TB_M_LABEL_CONSTANT] C2
                ON C2.FKEY = 'PROD_TYPE'
            LEFT JOIN [DB_TMMIN1_KRW_PIS_HV_BATTERY].[dbo].[TB_M_LABEL_CONSTANT] C3
                ON C3.FKEY = 'SPEC_NO'
            LEFT JOIN [DB_TMMIN1_KRW_PIS_HV_BATTERY].[dbo].[TB_M_LABEL_CONSTANT] C4
                ON C4.FKEY = 'LINE_NO'
            LEFT JOIN [DB_TMMIN1_KRW_PIS_HV_BATTERY].[dbo].[TB_M_LABEL_CONSTANT] C5
                ON C5.FKEY = 'ADDRESS'
            LEFT JOIN [DB_TMMIN1_KRW_PIS_HV_BATTERY].[dbo].[TB_M_PROD_YEAR] Y 
                ON Y.FYEAR = YEAR(GETDATE())
            LEFT JOIN [DB_TMMIN1_KRW_PIS_HV_BATTERY].[dbo].[TB_M_PROD_MONTH_DAY] MD_MONTH 
                ON MD_MONTH.FMONTH_DAY = MONTH(GETDATE())
            LEFT JOIN [DB_TMMIN1_KRW_PIS_HV_BATTERY].[dbo].[TB_M_PROD_MONTH_DAY] MD_DAY   
                ON MD_DAY.FMONTH_DAY = DAY(GETDATE())
        )
        --  Step 3: Update records with new values 
        UPDATE S
        SET 
            S.FSEQ_NO = U.NEW_FSEQ_NO,
            S.FBARCODE = U.NEW_FBARCODE,
            S.FSEQ_DATE = GETDATE()
        FROM [DB_TMMIN1_KRW_PIS_HV_BATTERY].[dbo].[TB_R_SEQUENCE_BATTERY] S
        INNER JOIN UpdatedBarcode U ON S.FID = U.FID;
        
        SET @RowsAffected = @@ROWCOUNT;

        --  Step 4: Update FTARGET with latest generated sequence per TYPE + MODEL 
        ;WITH LatestSequencePerTypeModel AS (
            SELECT
                RTRIM(LTRIM(FTYPE_BATTERY)) AS FTYPE_BATTERY,
                RTRIM(LTRIM(FMODEL_BATTERY)) AS FMODEL_BATTERY,
                MAX(FSEQ_NO) AS LAST_GENERATED_SEQ,
                MAX(FSEQ_DATE) AS LAST_PROD_DATE
            FROM [DB_TMMIN1_KRW_PIS_HV_BATTERY].[dbo].[TB_R_SEQUENCE_BATTERY]
            WHERE FSTATUS = 0
            GROUP BY
                RTRIM(LTRIM(FTYPE_BATTERY)),
                RTRIM(LTRIM(FMODEL_BATTERY))
        )
        UPDATE T
        SET T.FTARGET = L.LAST_GENERATED_SEQ,
        T.FPROD_DATE = L.LAST_PROD_DATE  
        FROM [DB_TMMIN1_KRW_PIS_HV_BATTERY].[dbo].[TB_R_TARGET_PROD] T
        INNER JOIN LatestSequencePerTypeModel L
            ON RTRIM(LTRIM(T.FTYPE_BATTERY)) = L.FTYPE_BATTERY
           AND RTRIM(LTRIM(T.FMODEL_BATTERY)) = L.FMODEL_BATTERY;

        SET @TargetRowsAffected = @@ROWCOUNT;
        
        COMMIT TRANSACTION;
        
        --  Return summary report 
        SELECT 
            'SUCCESS' AS STATUS,
            @RowsAffected AS ROWS_UPDATED,
            @TargetRowsAffected AS TARGET_ROWS_UPDATED,
            GETDATE() AS EXECUTION_TIME,
            'Sequence regenerated successfully' AS MESSAGE;
        
        --  Show updated records grouped by FTYPE_BATTERY + FMODEL_BATTERY 
        SELECT 
            FTYPE_BATTERY,
            FMODEL_BATTERY,
            COUNT(*) AS RECORD_COUNT,
            MIN(FSEQ_NO) AS MIN_SEQ,
            MAX(FSEQ_NO) AS MAX_SEQ,
            MIN(FSEQ_DATE) AS MIN_FSEQ_DATE,
            MAX(FSEQ_DATE) AS MAX_FSEQ_DATE,
            MIN(FBARCODE) AS FIRST_BARCODE,
            MAX(FBARCODE) AS LAST_BARCODE
        FROM [DB_TMMIN1_KRW_PIS_HV_BATTERY].[dbo].[TB_R_SEQUENCE_BATTERY]
        WHERE FSTATUS = 0
        GROUP BY FTYPE_BATTERY, FMODEL_BATTERY
        ORDER BY FTYPE_BATTERY, FMODEL_BATTERY;
        
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;
        
        -- Return error details
        SELECT 
            'ERROR' AS STATUS,
            ERROR_NUMBER() AS ERROR_NUMBER,
            ERROR_MESSAGE() AS ERROR_MESSAGE,
            ERROR_LINE() AS ERROR_LINE;
    END CATCH
END
GO
PRINT '+ SP_REGENERATE_BATTERY_SEQUENCE : created/updated';
GO

PRINT '=== STEP 3: Triggers ==='
GO
-- TB_H_ANDON_STATUS_AFTER_UPDATE
CREATE OR ALTER TRIGGER [dbo].[TB_H_ANDON_STATUS_AFTER_UPDATE]
ON [dbo].[TB_H_ANDON_STATUS]
AFTER UPDATE
AS
BEGIN
    SET NOCOUNT ON;

    -- Hanya proses jika ada record yang selesai (DURATION_SECOND IS NOT NULL)
    IF EXISTS (SELECT 1 FROM inserted WHERE [DURATION_SECOND] IS NOT NULL)
    BEGIN
        -- 1. Update history harian (dengan PROD_DATE + PROD_SHIFT)
        WITH HistoryData AS (
            SELECT 
                STATION,
                PROD_DATE,
                PROD_SHIFT,
                DURATION_SECOND
            FROM inserted
            WHERE DURATION_SECOND IS NOT NULL
        )
        MERGE [dbo].[TB_H_DOWNTIME_LOG] AS target
        USING HistoryData AS source
        ON target.STATION = source.STATION
           AND target.PROD_DATE = source.PROD_DATE
           AND target.PROD_SHIFT = source.PROD_SHIFT
        WHEN MATCHED THEN
            UPDATE SET
                target.DURATION_SECOND = target.DURATION_SECOND + source.DURATION_SECOND,
                target.TOTAL_DOWNTIME = target.TOTAL_DOWNTIME + 1,
                target.FDATETIME_MODIFIED = GETDATE()
        WHEN NOT MATCHED THEN
            INSERT (STATION, PROD_DATE, PROD_SHIFT, DURATION_SECOND, TOTAL_DOWNTIME, FDATETIME_MODIFIED)
            VALUES (source.STATION, source.PROD_DATE, source.PROD_SHIFT, source.DURATION_SECOND, 1, GETDATE());

        -- 2. Update real-time summary (hanya per STATION, akumulasi semua)
        WITH SummaryData AS (
            SELECT 
                STATION,
                SUM(DURATION_SECOND) AS TotalDuration,
                COUNT(*) AS EventCount
            FROM inserted
            WHERE DURATION_SECOND IS NOT NULL
            GROUP BY STATION  -- ?? penting: aggregate per station
        )
        MERGE [dbo].[TB_R_DOWNTIME_LOG] AS target
        USING SummaryData AS source
        ON target.STATION = source.STATION
        WHEN MATCHED THEN
            UPDATE SET
                target.DURATION_SECOND = target.DURATION_SECOND + source.TotalDuration,
                target.TOTAL_DOWNTIME = target.TOTAL_DOWNTIME + source.EventCount,
                target.FDATETIME_MODIFIED = GETDATE()
        WHEN NOT MATCHED THEN
            INSERT (STATION, DURATION_SECOND, TOTAL_DOWNTIME, FDATETIME_MODIFIED)
            VALUES (source.STATION, source.TotalDuration, source.EventCount, GETDATE());
    END
END
GO
PRINT '+ TB_H_ANDON_STATUS_AFTER_UPDATE : created/updated';
GO

-- TB_M_BATTERY_MAPPING_AFTER_INSERT
CREATE OR ALTER TRIGGER [dbo].[TB_M_BATTERY_MAPPING_AFTER_INSERT]
ON dbo.TB_M_BATTERY_MAPPING
AFTER INSERT
AS
BEGIN
    SET NOCOUNT ON;

INSERT INTO TB_R_TARGET_PROD (
        FTYPE_BATTERY,
        FMODEL_BATTERY,
		FPACK_PART_BATTERY,
		FTARGET,
        FDATETIME_MODIFIED
    )
    SELECT 
        i.FTYPE_BATTERY,
        i.FMODEL_BATTERY,
		i.FPACK_PART_BATTERY,
		0,
        GETDATE()
    FROM inserted i
    WHERE NOT EXISTS (
        SELECT 1
        FROM TB_R_TARGET_PROD t
        WHERE t.FTYPE_BATTERY = i.ftype_battery
          AND t.FMODEL_BATTERY = i.fmodel_battery
    );
END;
GO
PRINT '+ TB_M_BATTERY_MAPPING_AFTER_INSERT : created/updated';
GO

-- TB_R_ANDON_STATUS_AFTER_UPDATE
CREATE OR ALTER TRIGGER [dbo].[TB_R_ANDON_STATUS_AFTER_UPDATE]
ON [dbo].[TB_R_ANDON_STATUS]
AFTER UPDATE
AS
BEGIN
    SET NOCOUNT ON;

    -- 1. INSERT: Saat FVALUE berubah dari 0  1
    INSERT INTO TB_H_ANDON_STATUS (
        STATION,
        PROD_DATE,
        PROD_SHIFT,
        START_TIME,
        END_TIME,
        FDATETIME_MODIFIED
    )
    SELECT 
        i.STATION,
        CAST(GETDATE() AS DATE),
        'SHIFT-A',
        GETDATE(),
        NULL,
        NULL
    FROM inserted i
    INNER JOIN deleted d ON i.STATION = d.STATION
    WHERE d.FVALUE = 0 AND i.FVALUE = 1;

    -- 2. UPDATE: Saat FVALUE berubah dari 1  0 (akhiri downtime)
    WITH LatestLog AS (
        SELECT 
            log.*,
            ROW_NUMBER() OVER (PARTITION BY log.STATION ORDER BY log.START_TIME DESC) AS rn
        FROM TB_H_ANDON_STATUS log
        INNER JOIN inserted i ON log.STATION = i.STATION
        WHERE log.END_TIME IS NULL
    )
    UPDATE LatestLog
    SET 
        END_TIME = GETDATE(),
        FDATETIME_MODIFIED = GETDATE()
    FROM inserted i
    INNER JOIN deleted d ON i.STATION = d.STATION
    WHERE 
        d.FVALUE = 1 
        AND i.FVALUE = 0
        AND LatestLog.rn = 1;
END;
GO
PRINT '+ TB_R_ANDON_STATUS_AFTER_UPDATE : created/updated';
GO

-- TB_R_PRINT_LABEL_AFTER_DELETE
CREATE OR ALTER TRIGGER [dbo].[TB_R_PRINT_LABEL_AFTER_DELETE]
   ON [dbo].[TB_R_PRINT_LABEL]
   AFTER DELETE
AS
BEGIN
    SET NOCOUNT ON;

    INSERT INTO [dbo].[TB_H_PRINT_LOG] (
        PRINT_QRCODE,
        FMODEL_BATTERY,
        FID_RECEIVER,
        FALC_DATA,
        DATETIME_RECEIVED,
        PROD_DATE,
        FSHIFT,
        DATETIME_MODIFIED
    )
    SELECT
        D.FPRINT_QRCODE,
        D.FMODEL_BATTERY,
        S.FID_RECEIVER,
        S.FALC_DATA,
        S.FTIME_RECEIVED,
        S.FSEQ_DATE,
        NULL AS FSHIFT,          -- placeholder shift
        GETDATE() AS DATETIME_MODIFIED
    FROM deleted D
    INNER JOIN TB_R_SEQUENCE_BATTERY S
        ON S.FBARCODE = D.FPRINT_QRCODE;



	-- Update status di sequence battery
    UPDATE S
    SET S.FSTATUS = '1',
	FTIME_PRINTED = GETDATE()
    FROM TB_R_SEQUENCE_BATTERY S
    INNER JOIN deleted D
        ON S.FBARCODE = D.FPRINT_QRCODE;
END
GO
PRINT '+ TB_R_PRINT_LABEL_AFTER_DELETE : created/updated';
GO

-- TB_R_RFID_COMMAND_AFTER_UPDATE
CREATE OR ALTER TRIGGER [dbo].[TB_R_RFID_COMMAND_AFTER_UPDATE]
ON [dbo].[TB_R_RFID_COMMAND]
AFTER UPDATE
AS
BEGIN
    SET NOCOUNT ON;

    -- Cek apakah FVALUE = 1 di inserted/updated rows
    IF EXISTS (
        SELECT 1 
        FROM inserted i 
        WHERE i.FVALUE = 1
    )
    BEGIN
        -- Update READ command
        UPDATE [DB_TMMIN1_KRW_RFID_V680S].[dbo].[TB_R_WRITE_DEVICE_AIS]
        SET 
            WRITE_FLAG = 0,
            TR_TIME = GETDATE()
        FROM [DB_TMMIN1_KRW_RFID_V680S].[dbo].[TB_R_WRITE_DEVICE_AIS] rfid
        INNER JOIN inserted i ON rfid.GROUP_NAME = i.STATION_NAME
        WHERE i.COMMAND = 'READ'
          AND i.FVALUE = 1
          AND rfid.TAG_NAME = 'READ_FULL';

        -- Handle WRITE command: Eksekusi SP_GENERATE_REG_VALUE_FOR_WRITE untuk setiap station
        DECLARE @sql NVARCHAR(MAX) = '';
        
        SELECT @sql = @sql + 
            'EXEC [DB_TMMIN1_KRW_RFID_V680S].[dbo].[SP_GENERATE_REG_VALUE_FOR_WRITE] @StationName = ''' + STATION_NAME + '''; '
        FROM inserted
        WHERE COMMAND = 'WRITE'
          AND FVALUE = 1;

        IF @sql <> ''
            EXEC sp_executesql @sql;
    END
END;
GO
PRINT '+ TB_R_RFID_COMMAND_AFTER_UPDATE : created/updated';
GO

-- TB_R_TARGET_PROD_AFTER_UPDATE
CREATE OR ALTER TRIGGER [dbo].[TB_R_TARGET_PROD_AFTER_UPDATE]
ON [dbo].[TB_R_TARGET_PROD]
AFTER UPDATE
AS
BEGIN
    SET NOCOUNT ON;

    -- Skip jika dipanggil dari SP_REGENERATE_BATTERY_SEQUENCE.
    -- Updating FTARGET di sana bersifat informational dan tidak boleh memicu trigger ini.
    IF CAST(SESSION_CONTEXT(N'skip_target_trigger') AS BIT) = 1
        RETURN;

    DECLARE @BaseAdjust INT;
    SELECT @BaseAdjust = ISNULL(MAX(FID_ADJUST), 0)
    FROM TB_R_SEQUENCE_BATTERY;

    -- Delta > 0: insert only additional sequences, continuing from MAX seq
    -- scoped by FTYPE+MODEL+ProdDate. (Tidak reset saat status berubah jadi 1/printed.)
    ;WITH Deltas AS (
        SELECT
            i.FID AS TargetFID,
            i.FTYPE_BATTERY,
            i.FMODEL_BATTERY,
            i.ORDER_TYPE,
            CAST(ISNULL(i.FPROD_DATE, GETDATE()) AS DATE) AS ProdDate,
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
            dm.FTYPE_BATTERY,
            dm.FMODEL_BATTERY,
            dm.ProdDate,
            ISNULL(MAX(s.FSEQ_NO), 0) AS MaxSeq
        FROM Deltas dm
        LEFT JOIN TB_R_SEQUENCE_BATTERY s
            ON s.FTYPE_BATTERY = dm.FTYPE_BATTERY
           AND s.FMODEL_BATTERY = dm.FMODEL_BATTERY
           AND s.FSEQ_DATE = dm.ProdDate
        GROUP BY dm.FTYPE_BATTERY, dm.FMODEL_BATTERY, dm.ProdDate
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
            CASE
                WHEN d.ORDER_TYPE = 'Assy' THEN ISNULL(d.FDATETIME_MODIFIED, GETDATE())
                ELSE GETDATE()
            END AS FTIME_RECEIVED,
            ISNULL(sm.MaxSeq, 0) + ROW_NUMBER() OVER (
                PARTITION BY d.FTYPE_BATTERY, d.FMODEL_BATTERY, d.ProdDate
                ORDER BY d.TargetFID, n.n
            ) AS FSEQ_NO
        FROM Deltas d
        JOIN Nums n ON n.n <= d.Delta
        LEFT JOIN ScopeMax sm
            ON sm.FTYPE_BATTERY = d.FTYPE_BATTERY
           AND sm.FMODEL_BATTERY = d.FMODEL_BATTERY
           AND sm.ProdDate = d.ProdDate
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
    LEFT JOIN (
        SELECT
            FTYPE_BATTERY,
            FMODEL_BATTERY,
            MAX(FPACK_PART_BATTERY) AS FPACK_PART_BATTERY
        FROM TB_M_BATTERY_MAPPING
        GROUP BY FTYPE_BATTERY, FMODEL_BATTERY
    ) M
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
          AND s.FSEQ_DATE = e.ProdDate
    );

    -- Delta < 0: delete newest pending rows only for affected order type and production date.
    ;WITH PlanDecreases AS (
        SELECT
            i.FTYPE_BATTERY,
            i.FMODEL_BATTERY,
            i.ORDER_TYPE,
            CAST(ISNULL(i.FPROD_DATE, GETDATE()) AS DATE) AS ProdDate,
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
           AND s.FSEQ_DATE = pd.ProdDate
        WHERE s.FSTATUS = 0
    )
    DELETE FROM TB_R_SEQUENCE_BATTERY
    WHERE FID IN (
        SELECT FID
        FROM PendingRanked
        WHERE rn <= DropCount
    );

    -- Resequence pending rows after decrease to maintain contiguous pending numbering,
    -- but NEVER overlap with completed/printed sequences (FSTATUS <> 0) for the same date.
    ;WITH PlanDecreases AS (
        SELECT DISTINCT
            i.FTYPE_BATTERY,
            i.FMODEL_BATTERY,
            CAST(ISNULL(i.FPROD_DATE, GETDATE()) AS DATE) AS ProdDate
        FROM inserted i
        JOIN deleted d ON i.FID = d.FID
        WHERE ISNULL(i.FTARGET, 0) < ISNULL(d.FTARGET, 0)
          AND i.ORDER_TYPE <> 'Assy'
    ),
    CompletedBase AS (
        SELECT
            pd.FTYPE_BATTERY,
            pd.FMODEL_BATTERY,
            pd.ProdDate,
            ISNULL(MAX(CASE WHEN s.FSTATUS <> 0 THEN s.FSEQ_NO END), 0) AS BaseSeq
        FROM PlanDecreases pd
        LEFT JOIN TB_R_SEQUENCE_BATTERY s
            ON s.FTYPE_BATTERY = pd.FTYPE_BATTERY
           AND s.FMODEL_BATTERY = pd.FMODEL_BATTERY
           AND s.FSEQ_DATE = pd.ProdDate
        GROUP BY pd.FTYPE_BATTERY, pd.FMODEL_BATTERY, pd.ProdDate
    ),
    PendingOrdered AS (
        SELECT
            s.FID,
            s.FTYPE_BATTERY,
            s.FMODEL_BATTERY,
            s.ORDER_TYPE,
            s.FSEQ_DATE,
            cb.BaseSeq + ROW_NUMBER() OVER (
                PARTITION BY s.FTYPE_BATTERY, s.FMODEL_BATTERY, s.FSEQ_DATE
                ORDER BY s.FSEQ_NO, s.FID
            ) AS NewSeq
        FROM TB_R_SEQUENCE_BATTERY s
        JOIN CompletedBase cb
            ON cb.FTYPE_BATTERY = s.FTYPE_BATTERY
           AND cb.FMODEL_BATTERY = s.FMODEL_BATTERY
           AND cb.ProdDate = s.FSEQ_DATE
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
    LEFT JOIN (
        SELECT
            FTYPE_BATTERY,
            FMODEL_BATTERY,
            MAX(FPACK_PART_BATTERY) AS FPACK_PART_BATTERY
        FROM TB_M_BATTERY_MAPPING
        GROUP BY FTYPE_BATTERY, FMODEL_BATTERY
    ) M
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
PRINT '+ TB_R_TARGET_PROD_AFTER_UPDATE : created/updated';
GO

-- TB_RECEIVER_SUBSYSTEM_AFTER_INSERT
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
PRINT '+ TB_RECEIVER_SUBSYSTEM_AFTER_INSERT : created/updated';
GO

-- TR_ORDER_TYPE_SYNC_QRCODE
CREATE OR ALTER TRIGGER TR_ORDER_TYPE_SYNC_QRCODE
ON TB_M_PROD_ORDER_TYPE
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
END
PRINT 'TR_ORDER_TYPE_SYNC_QRCODE updated'
GO
PRINT '+ TR_ORDER_TYPE_SYNC_QRCODE : created/updated';
GO

-- TR_PLAN_DETAIL_SYNC_TARGET_PROD
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
PRINT '+ TR_PLAN_DETAIL_SYNC_TARGET_PROD : created/updated';
GO

-- TR_PROD_MODEL_SYNC_QRCODE
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
END
PRINT 'TR_PROD_MODEL_SYNC_QRCODE updated'
GO
PRINT '+ TR_PROD_MODEL_SYNC_QRCODE : created/updated';
GO

PRINT '=============================='
PRINT 'MIGRATION COMPLETED SUCCESSFULLY'
PRINT '=============================='
GO

