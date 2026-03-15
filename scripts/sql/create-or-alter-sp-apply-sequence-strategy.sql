USE [DB_TMMIN1_KRW_PIS_HV_BATTERY]
GO

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
