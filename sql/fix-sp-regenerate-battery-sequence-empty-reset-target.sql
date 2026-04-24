USE [DB_TMMIN1_KRW_PIS_HV_BATTERY]
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER OFF
GO

/*
  Fix:
  If no pending sequence rows exist in TB_R_SEQUENCE_BATTERY (FSTATUS = 0),
  reset TB_R_TARGET_PROD as below:
  - FTARGET = 0
  - FPROD_DATE = GETDATE()
  - ORDER_TYPE = NULL
*/
ALTER PROCEDURE [dbo].[SP_REGENERATE_BATTERY_SEQUENCE]
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @RowsAffected INT = 0;
    DECLARE @TargetRowsAffected INT = 0;

    BEGIN TRY
        BEGIN TRANSACTION;

        -- Step 1: Generate new sequence numbers per FTYPE_BATTERY + FMODEL_BATTERY
        WITH RankedData AS (
            SELECT
                FID,
                FSEQ_NO AS OLD_FSEQ_NO,
                RTRIM(LTRIM(FTYPE_BATTERY)) AS FTYPE_BATTERY,
                FMODEL_BATTERY,
                FSEQ_DATE,
                FBARCODE AS OLD_FBARCODE,
                ROW_NUMBER() OVER (
                    PARTITION BY RTRIM(LTRIM(FTYPE_BATTERY)), RTRIM(LTRIM(FMODEL_BATTERY))
                    ORDER BY FSEQ_DATE, FID
                ) AS NEW_FSEQ_NO
            FROM [DB_TMMIN1_KRW_PIS_HV_BATTERY].[dbo].[TB_R_SEQUENCE_BATTERY]
            WHERE FSTATUS = 0
        ),
        -- Step 2: Rebuild FBARCODE from master tables
        UpdatedBarcode AS (
            SELECT
                R.FID,
                R.OLD_FSEQ_NO,
                R.NEW_FSEQ_NO,
                R.FTYPE_BATTERY,
                R.FMODEL_BATTERY,
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
        -- Step 3: Update records with new values
        UPDATE S
        SET
            S.FSEQ_NO = U.NEW_FSEQ_NO,
            S.FBARCODE = U.NEW_FBARCODE,
            S.FSEQ_DATE = GETDATE()
        FROM [DB_TMMIN1_KRW_PIS_HV_BATTERY].[dbo].[TB_R_SEQUENCE_BATTERY] S
        INNER JOIN UpdatedBarcode U ON S.FID = U.FID;

        SET @RowsAffected = @@ROWCOUNT;

        -- Step 4: Update FTARGET with latest generated sequence per TYPE + MODEL.
        -- If no active sequence rows are present, reset all targets.
        DECLARE @flagOn SQL_VARIANT = 1;
        EXEC sys.sp_set_session_context @key = N'skip_target_trigger', @value = @flagOn;

        IF EXISTS (
            SELECT 1
            FROM [DB_TMMIN1_KRW_PIS_HV_BATTERY].[dbo].[TB_R_SEQUENCE_BATTERY]
            WHERE FSTATUS = 0
        )
        BEGIN
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
                T.FPROD_DATE = L.LAST_PROD_DATE,
                T.FDATETIME_MODIFIED = GETDATE()
            FROM [DB_TMMIN1_KRW_PIS_HV_BATTERY].[dbo].[TB_R_TARGET_PROD] T
            INNER JOIN LatestSequencePerTypeModel L
                ON RTRIM(LTRIM(T.FTYPE_BATTERY)) = L.FTYPE_BATTERY
               AND RTRIM(LTRIM(T.FMODEL_BATTERY)) = L.FMODEL_BATTERY;

            SET @TargetRowsAffected = @@ROWCOUNT;
        END
        ELSE
        BEGIN
            UPDATE T
            SET T.FTARGET = 0,
                T.FPROD_DATE = GETDATE(),
                T.ORDER_TYPE = NULL,
                T.FDATETIME_MODIFIED = GETDATE()
            FROM [DB_TMMIN1_KRW_PIS_HV_BATTERY].[dbo].[TB_R_TARGET_PROD] T;

            SET @TargetRowsAffected = @@ROWCOUNT;
        END

        DECLARE @flagOff SQL_VARIANT = 0;
        EXEC sys.sp_set_session_context @key = N'skip_target_trigger', @value = @flagOff;

        COMMIT TRANSACTION;

        -- Return summary report
        SELECT
            'SUCCESS' AS STATUS,
            @RowsAffected AS ROWS_UPDATED,
            @TargetRowsAffected AS TARGET_ROWS_UPDATED,
            GETDATE() AS EXECUTION_TIME,
            'Sequence regenerated successfully' AS MESSAGE;

        -- Show updated records grouped by FTYPE_BATTERY + FMODEL_BATTERY
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
        DECLARE @flagOffOnError SQL_VARIANT = 0;
        EXEC sys.sp_set_session_context @key = N'skip_target_trigger', @value = @flagOffOnError;

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
