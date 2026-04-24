USE [DB_TMMIN1_KRW_PIS_HV_BATTERY]
GO
/****** Object:  StoredProcedure [dbo].[sp_RefreshBatteryTraceabilityView]    Script Date: 12/04/2026 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

-- =============================================
-- OPTIMIZED VERSION - MENGHILANGKAN TRIM() di JOIN
-- ADDED: ECU_ID dari TB_H_SHOP_MAN_ASSY1 setelah MODULE_2 CELL_ID_28
-- Asumsi: Data sudah clean atau akan dibersihkan di source
-- =============================================

ALTER PROCEDURE [dbo].[sp_RefreshBatteryTraceabilityView]
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
    DECLARE @ECUIDColumn NVARCHAR(MAX) = '';
    DECLARE @RowCount INT = 0;
    DECLARE @FinalJudgementColCount INT = 0;
    DECLARE @InspectionMachineColCount INT = 0;
    DECLARE @ModuleInspectionColCount INT = 0;
    DECLARE @TighteningColCount INT = 0;
    DECLARE @Module1CellColCount INT = 28;
    DECLARE @Module2CellColCount INT = 28;
    DECLARE @ECUIDColCount INT = 1;
    DECLARE @TotalColumnCount INT = 0;
    DECLARE @StartTime DATETIME = GETDATE();

    BEGIN TRY
        -- =============================================
        -- Step 1: Build Final Judgement columns (only 3 specific columns)
        -- =============================================
        PRINT '🔍 Building TB_H_POS_FINAL_JUDGEMENT columns...';
        
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
        PRINT '🔍 Auto-detecting TB_H_TRACEABILITY_INSPECTION_MACHINE columns...';
        
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
        PRINT '🔍 Auto-detecting TB_H_TRACEABILITY_MODULE_INSPECTION columns...';
        
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
        PRINT '🔋 Building MODULE_1 CELL_ID columns (28 cells)...';
        
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
        PRINT '🔋 Building MODULE_2 CELL_ID columns (28 cells)...';
        
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
        -- Step 6: Build ECU_ID column from TB_H_SHOP_MAN_ASSY1
        -- =============================================
        PRINT '🔌 Building ECU_ID column from TB_H_SHOP_MAN_ASSY1...';
        
        SET @ECUIDColumn = '    ecu.ECU_ID AS [ECU_ID]';
        
        PRINT '   Added 1 ECU_ID column (positioned after MODULE_2 CELL columns)';

        -- =============================================
        -- Step 7: Auto-detect tightening structure from master table
        -- =============================================
        PRINT '🔨 Building pivot columns with TighteningName (3 metrics: Torque, Angle, Result)...';
        
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
        -- Step 8: Validate column count
        -- =============================================
        SET @TotalColumnCount = 3 + @Module1CellColCount + @Module2CellColCount + @ECUIDColCount + 2 + @ModuleInspectionColCount + @TighteningColCount + @InspectionMachineColCount + @FinalJudgementColCount;
        
        PRINT '';
        PRINT '📊 Column Count Summary:';
        PRINT '   Base: 3 | M1_Cells: ' + CAST(@Module1CellColCount AS VARCHAR(10)) + 
              ' | M2_Cells: ' + CAST(@Module2CellColCount AS VARCHAR(10)) + 
              ' | ECU_ID: ' + CAST(@ECUIDColCount AS VARCHAR(10)) +
              ' | Lifetimes: 2';
        PRINT '   Module: ' + CAST(@ModuleInspectionColCount AS VARCHAR(10)) + 
              ' | Tightening: ' + CAST(@TighteningColCount AS VARCHAR(10)) + ' (Torque + Angle + Result)';
        PRINT '   Insp: ' + CAST(@InspectionMachineColCount AS VARCHAR(10)) + 
              ' | Final: ' + CAST(@FinalJudgementColCount AS VARCHAR(10));
        PRINT '   TOTAL: ' + CAST(@TotalColumnCount AS VARCHAR(10)) + ' / 1024';
        
        IF @TotalColumnCount > 1024
        BEGIN
            RAISERROR('❌ Column count exceeds 1024 limit!', 16, 1);
            RETURN;
        END
        PRINT '   ✅ Within safe limits';
        PRINT '';

        -- =============================================
        -- Step 9: Build OPTIMIZED VIEW (NO TRIM IN JOINS!)
        -- =============================================
        PRINT '📝 Generating OPTIMIZED VW_TRACEABILITY_PIS...';
        PRINT '⚡ KEY OPTIMIZATION: Removed TRIM() from all JOIN conditions for index usage';
        PRINT '   ⚠️  IMPORTANT: Ensure data is clean or create indexed computed columns';
        PRINT '   📌 EXCEPTION: CELL_ID JOINs use TRIM() due to cross-database requirements';
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
' + @ECUIDColumn + ',
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
        PACK_ID,
        ECU_ID,
        ROW_NUMBER() OVER (
            PARTITION BY PACK_ID 
            ORDER BY CREATED_AT DESC
        ) AS rn
    FROM TB_H_SHOP_MAN_ASSY1
) ecu ON u.PACK_ID = ecu.PACK_ID AND ecu.rn = 1

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
        PRINT '✅ VIEW created successfully in ' + CAST(@Duration AS VARCHAR(10)) + ' seconds!';
        PRINT '';
        PRINT '📌 NEXT STEPS FOR BETTER PERFORMANCE:';
        PRINT '   1. Create indexes on all JOIN key columns';
        PRINT '   2. If data has spaces, add computed persisted columns with TRIM()';
        PRINT '   3. Update statistics on all base tables';
        PRINT '   4. Consider indexed views for ROW_NUMBER() subqueries';

    END TRY
    BEGIN CATCH
        PRINT '❌ Error: ' + ERROR_MESSAGE();
        PRINT 'Line: ' + CAST(ERROR_LINE() AS VARCHAR(10));
        
        IF @@TRANCOUNT > 0
            ROLLBACK TRAN;
            
        THROW;
    END CATCH
END;
GO
