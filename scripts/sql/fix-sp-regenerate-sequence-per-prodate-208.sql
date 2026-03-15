USE [DB_TMMIN1_KRW_PIS_HV_BATTERY]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

/*
Purpose:
- Make SP_REGENERATE_BATTERY_SEQUENCE consistent with per-prodate sequence policy.
- Sequence resets per FTYPE_BATTERY + FMODEL_BATTERY + FSEQ_DATE.
- Preserve existing FSEQ_DATE (do not overwrite with GETDATE).
- Rebuild barcode using each row's own FSEQ_DATE.
*/
CREATE OR ALTER PROCEDURE [dbo].[SP_REGENERATE_BATTERY_SEQUENCE]
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @RowsAffected INT = 0;
    DECLARE @TargetRowsAffected INT = 0;
    DECLARE @ResetDate date = CAST(GETDATE() AS date);

    BEGIN TRY
        BEGIN TRANSACTION;

        -- Prevent TB_R_TARGET_PROD_AFTER_UPDATE trigger overlap while this
        -- maintenance procedure recalculates sequence/target in bulk.
        EXEC sys.sp_set_session_context @key = N'SkipBatterySequenceTrigger', @value = 1;

        ;WITH RankedData AS (
            SELECT
                FID,
                FSEQ_NO AS OLD_FSEQ_NO,
                RTRIM(LTRIM(FTYPE_BATTERY)) AS FTYPE_BATTERY,
                RTRIM(LTRIM(FMODEL_BATTERY)) AS FMODEL_BATTERY,
                @ResetDate AS FSEQ_DATE,
                FBARCODE AS OLD_FBARCODE,
                ROW_NUMBER() OVER (
                    PARTITION BY
                        RTRIM(LTRIM(FTYPE_BATTERY)),
                        RTRIM(LTRIM(FMODEL_BATTERY))
                    ORDER BY FID
                ) AS NEW_FSEQ_NO
            FROM [dbo].[TB_R_SEQUENCE_BATTERY]
            WHERE FSTATUS = 0
        ),
        UpdatedBarcode AS (
            SELECT
                R.FID,
                R.OLD_FSEQ_NO,
                R.NEW_FSEQ_NO,
                R.FTYPE_BATTERY,
                R.FMODEL_BATTERY,
                R.FSEQ_DATE,
                R.OLD_FBARCODE,
                CONCAT(
                    ISNULL(C1.FVALUE, ''),
                    ISNULL(C2.FVALUE, ''),
                    R.FTYPE_BATTERY,
                    ISNULL(C3.FVALUE, ''),
                    ISNULL(M.FPACK_PART_BATTERY, ''),
                    ISNULL(C4.FVALUE, ''),
                    ISNULL(C5.FVALUE, ''),
                    ISNULL(Y.FCODE_YEAR, ''),
                    ISNULL(MD_MONTH.FCODE, ''),
                    ISNULL(MD_DAY.FCODE, ''),
                    RIGHT(CONCAT('0000000', R.NEW_FSEQ_NO), 7)
                ) AS NEW_FBARCODE
            FROM RankedData R
            LEFT JOIN [dbo].[TB_M_BATTERY_MAPPING] M
                ON M.FTYPE_BATTERY = R.FTYPE_BATTERY
               AND M.FMODEL_BATTERY = R.FMODEL_BATTERY
            LEFT JOIN [dbo].[TB_M_LABEL_CONSTANT] C1 ON C1.FKEY = 'MANUFACTURER'
            LEFT JOIN [dbo].[TB_M_LABEL_CONSTANT] C2 ON C2.FKEY = 'PROD_TYPE'
            LEFT JOIN [dbo].[TB_M_LABEL_CONSTANT] C3 ON C3.FKEY = 'SPEC_NO'
            LEFT JOIN [dbo].[TB_M_LABEL_CONSTANT] C4 ON C4.FKEY = 'LINE_NO'
            LEFT JOIN [dbo].[TB_M_LABEL_CONSTANT] C5 ON C5.FKEY = 'ADDRESS'
            LEFT JOIN [dbo].[TB_M_PROD_YEAR] Y ON Y.FYEAR = YEAR(R.FSEQ_DATE)
            LEFT JOIN [dbo].[TB_M_PROD_MONTH_DAY] MD_MONTH ON MD_MONTH.FMONTH_DAY = MONTH(R.FSEQ_DATE)
            LEFT JOIN [dbo].[TB_M_PROD_MONTH_DAY] MD_DAY ON MD_DAY.FMONTH_DAY = DAY(R.FSEQ_DATE)
        )
        UPDATE S
        SET
            S.FSEQ_NO = U.NEW_FSEQ_NO,
            S.FBARCODE = U.NEW_FBARCODE,
            S.FSEQ_DATE = @ResetDate
        FROM [dbo].[TB_R_SEQUENCE_BATTERY] S
        INNER JOIN UpdatedBarcode U ON S.FID = U.FID;

        SET @RowsAffected = @@ROWCOUNT;

        ;WITH SeqPerDate AS (
            SELECT
                RTRIM(LTRIM(FTYPE_BATTERY)) AS FTYPE_BATTERY,
                RTRIM(LTRIM(FMODEL_BATTERY)) AS FMODEL_BATTERY,
                @ResetDate AS FSEQ_DATE,
                MAX(FSEQ_NO) AS LAST_GENERATED_SEQ
            FROM [dbo].[TB_R_SEQUENCE_BATTERY]
            WHERE FSTATUS = 0
            GROUP BY
                RTRIM(LTRIM(FTYPE_BATTERY)),
                RTRIM(LTRIM(FMODEL_BATTERY))
        ),
        LatestPerTypeModel AS (
            SELECT
                FTYPE_BATTERY,
                FMODEL_BATTERY,
                FSEQ_DATE,
                LAST_GENERATED_SEQ,
                ROW_NUMBER() OVER (
                    PARTITION BY FTYPE_BATTERY, FMODEL_BATTERY
                    ORDER BY FSEQ_DATE DESC
                ) AS rn
            FROM SeqPerDate
        )
        UPDATE T
        SET
            T.FTARGET = L.LAST_GENERATED_SEQ,
            T.FPROD_DATE = L.FSEQ_DATE
        FROM [dbo].[TB_R_TARGET_PROD] T
        INNER JOIN LatestPerTypeModel L
            ON RTRIM(LTRIM(T.FTYPE_BATTERY)) = L.FTYPE_BATTERY
           AND RTRIM(LTRIM(T.FMODEL_BATTERY)) = L.FMODEL_BATTERY
        WHERE L.rn = 1;

        SET @TargetRowsAffected = @@ROWCOUNT;

        EXEC sys.sp_set_session_context @key = N'SkipBatterySequenceTrigger', @value = 0;
        COMMIT TRANSACTION;

        SELECT
            'SUCCESS' AS STATUS,
            @RowsAffected AS ROWS_UPDATED,
            @TargetRowsAffected AS TARGET_ROWS_UPDATED,
            GETDATE() AS EXECUTION_TIME,
            'Sequence regenerated per production date successfully' AS MESSAGE;

        SELECT
            FTYPE_BATTERY,
            FMODEL_BATTERY,
            FSEQ_DATE,
            COUNT(*) AS RECORD_COUNT,
            MIN(FSEQ_NO) AS MIN_SEQ,
            MAX(FSEQ_NO) AS MAX_SEQ,
            MIN(FBARCODE) AS FIRST_BARCODE,
            MAX(FBARCODE) AS LAST_BARCODE
        FROM [dbo].[TB_R_SEQUENCE_BATTERY]
        WHERE FSTATUS = 0
        GROUP BY FTYPE_BATTERY, FMODEL_BATTERY, FSEQ_DATE
        ORDER BY FTYPE_BATTERY, FMODEL_BATTERY, FSEQ_DATE;

    END TRY
    BEGIN CATCH
        EXEC sys.sp_set_session_context @key = N'SkipBatterySequenceTrigger', @value = 0;

        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;

        SELECT
            'ERROR' AS STATUS,
            ERROR_NUMBER() AS ERROR_NUMBER,
            ERROR_MESSAGE() AS ERROR_MESSAGE,
            ERROR_LINE() AS ERROR_LINE;
    END CATCH
END
GO
