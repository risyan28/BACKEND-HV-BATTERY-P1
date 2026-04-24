/*
  Add columns to TB_H_PROD_PLAN_DETAIL:
  - PROD_DATE (date)
  - SHIFT (nvarchar(10))
  - QTY_ACTUAL (int, default 0)

  Safe to run multiple times.
*/

BEGIN TRY
  BEGIN TRAN;

  IF COL_LENGTH('dbo.TB_H_PROD_PLAN_DETAIL', 'PROD_DATE') IS NULL
  BEGIN
    ALTER TABLE dbo.TB_H_PROD_PLAN_DETAIL
      ADD PROD_DATE date NULL;
  END

  IF COL_LENGTH('dbo.TB_H_PROD_PLAN_DETAIL', 'SHIFT') IS NULL
  BEGIN
    ALTER TABLE dbo.TB_H_PROD_PLAN_DETAIL
      ADD SHIFT nvarchar(10) NULL;
  END

  IF COL_LENGTH('dbo.TB_H_PROD_PLAN_DETAIL', 'QTY_ACTUAL') IS NULL
  BEGIN
    ALTER TABLE dbo.TB_H_PROD_PLAN_DETAIL
      ADD QTY_ACTUAL int NOT NULL
          CONSTRAINT DF_TB_H_PROD_PLAN_DETAIL_QTY_ACTUAL DEFAULT (0);
  END

  -- Backfill + optional hardening must use dynamic SQL.
  -- Reason: SQL Server validates column names at compile-time per batch.
  IF COL_LENGTH('dbo.TB_H_PROD_PLAN_DETAIL', 'PROD_DATE') IS NOT NULL
     AND COL_LENGTH('dbo.TB_H_PROD_PLAN_DETAIL', 'SHIFT') IS NOT NULL
  BEGIN
    EXEC sys.sp_executesql N'
      UPDATE d
      SET
        d.PROD_DATE = p.PLAN_DATE,
        d.SHIFT = p.SHIFT
      FROM dbo.TB_H_PROD_PLAN_DETAIL d
      INNER JOIN dbo.TB_H_PROD_PLAN p
        ON p.FID = d.FID_PLAN
      WHERE d.PROD_DATE IS NULL
         OR d.SHIFT IS NULL;
    '

    EXEC sys.sp_executesql N'
      IF NOT EXISTS (
        SELECT 1
        FROM dbo.TB_H_PROD_PLAN_DETAIL
        WHERE PROD_DATE IS NULL
           OR SHIFT IS NULL
      )
      BEGIN
        ALTER TABLE dbo.TB_H_PROD_PLAN_DETAIL ALTER COLUMN PROD_DATE date NOT NULL;
        ALTER TABLE dbo.TB_H_PROD_PLAN_DETAIL ALTER COLUMN SHIFT nvarchar(10) NOT NULL;
      END
    '
  END

  COMMIT TRAN;
END TRY
BEGIN CATCH
  IF @@TRANCOUNT > 0 ROLLBACK TRAN;
  THROW;
END CATCH;
