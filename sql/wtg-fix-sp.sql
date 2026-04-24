USE [WTG_DB_BATTERY];
GO

IF OBJECT_ID('SP_WTG_DB','P') IS NOT NULL DROP PROCEDURE SP_WTG_DB;
GO

CREATE PROCEDURE [dbo].[SP_WTG_DB]
    @VLINE  VARCHAR(30) = 'ADAPTIVE'
AS
/*
  Working-Time Generator – executed every second by SQL Agent job.
  Counts elapsed working seconds, pauses during breaks, detects overtime.
  Cross-DB transmit to db_myopc_client_hv_battery has been removed;
  integrate via external service if PLC sync is needed.
*/
SET NOCOUNT ON;
SET XACT_ABORT ON;

DECLARE
    @WT             TINYINT     = 0,
    @SHIFTN         TINYINT     = 0,
    @BREAKN         TINYINT     = 0,
    @FRIDAY         TINYINT     = 0,
    @VINFO          INT         = 0,
    @DATE_NO        INT         = 0,
    @SHIFT_ID       INT         = NULL,
    @IS_OT          BIT         = 0,
    @OT_ID          INT         = NULL;

DECLARE @DATE_SHIFT VARCHAR(10);
DECLARE @DATE_TODAY VARCHAR(10);

/* ---- Determine day-of-week for Friday schedule ---- */
IF DATEPART(HOUR, GETDATE()) < 20
    SET @DATE_NO = DATEPART(WEEKDAY, GETDATE())
ELSE
    SELECT TOP 1 @DATE_NO = DATEPART(WEEKDAY, TRY_CAST(FREG_VALUE AS DATE))
    FROM TB_WT_STATUS
    WHERE FREG_NAME = 'DATE SHIFT'
      AND FLINE     = @VLINE;

SET @FRIDAY = CASE WHEN @DATE_NO = 6 THEN 1 ELSE 0 END;

BEGIN TRY
    /* ---- Determine active shift ---- */
    DECLARE @CNT1 TINYINT = 0;

    IF @FRIDAY = 1
        SELECT @CNT1 = COUNT(*) FROM V_LINE_WT_B
        WHERE FWT_TIME = 1 AND LINENAME = @VLINE;
    ELSE
        SELECT @CNT1 = COUNT(*) FROM V_LINE_WT_B
        WHERE WT_TIME  = 1 AND LINENAME = @VLINE;

    IF @CNT1 > 0
    BEGIN
        IF @FRIDAY = 1
            SELECT @SHIFTN = SHIFT, @BREAKN = FBREAK, @SHIFT_ID = SHIFT_ID
            FROM V_LINE_WT_B WHERE FWT_TIME = 1 AND LINENAME = @VLINE;
        ELSE
            SELECT @SHIFTN = SHIFT, @BREAKN = IS_BREAK, @SHIFT_ID = SHIFT_ID
            FROM V_LINE_WT_B WHERE WT_TIME  = 1 AND LINENAME = @VLINE;

        SET @WT = 1;
    END

    /* ---- Check open overtime ---- */
    SELECT TOP 1 @OT_ID = OT_ID,
                 @IS_OT = 1
    FROM TB_OVERTIME_SESSION
    WHERE LINENAME = @VLINE
      AND OT_END   IS NULL
      AND CAST(OT_START AS DATE) = CAST(GETDATE() AS DATE)
    ORDER BY OT_ID DESC;

    /* ---- Build @VINFO bitmask ---- */
    IF @BREAKN > 0 SET @VINFO = @VINFO + 8;
    IF @WT     > 0 SET @VINFO = @VINFO + 4;
    IF @IS_OT  = 1 SET @VINFO = @VINFO + 16;
    SET @VINFO = @VINFO + @SHIFTN;

    /* ---- Date of shift ---- */
    IF @SHIFTN = 1
        SET @DATE_SHIFT = CONVERT(CHAR(10), GETDATE(), 126);
    ELSE IF @SHIFTN = 2
        SET @DATE_SHIFT = CASE
            WHEN DATEPART(HOUR, GETDATE()) < 12
            THEN CONVERT(CHAR(10), DATEADD(DAY,-1,CAST(GETDATE() AS DATE)), 126)
            ELSE CONVERT(CHAR(10), GETDATE(), 126)
        END;
    ELSE
        SET @DATE_SHIFT = CONVERT(CHAR(10), GETDATE(), 126);

    /* Calendar date (night shift crosses midnight) */
    SET @DATE_TODAY = CASE
        WHEN DATEPART(HOUR, GETDATE()) <= 6
        THEN CONVERT(CHAR(10), DATEADD(DAY,-1,CAST(GETDATE() AS DATE)), 126)
        ELSE CONVERT(CHAR(10), GETDATE(), 126)
    END;

    /* ---- Increment / reset counters ---- */
    IF @WT = 0 AND @IS_OT = 0
    BEGIN
        UPDATE TB_WT_STATUS SET FTR_TIME = GETDATE(), FREG_VALUE = '0'
        WHERE FDEV_NAME = 'WTG' AND FLINE = @VLINE AND FREG_NAME = 'SHIFT';

        UPDATE TB_WT_STATUS SET FTR_TIME = GETDATE(), FREG_VALUE = '0'
        WHERE FDEV_NAME = 'WTG' AND FLINE = @VLINE AND FREG_NAME = 'INFO';
    END
    ELSE
    BEGIN
        IF @BREAKN = 0
        BEGIN
            UPDATE TB_WT_STATUS
            SET    FTR_TIME   = GETDATE(),
                   FREG_VALUE = CAST(ISNULL(TRY_CAST(FREG_VALUE AS INT), 0) + 1 AS VARCHAR(30))
            WHERE  FDEV_NAME  = 'WTG'
              AND  FLINE      = @VLINE
              AND  FREG_NAME  = 'WT';

            IF @IS_OT = 1 AND @OT_ID IS NOT NULL
                UPDATE TB_OVERTIME_SESSION
                SET    OT_SECONDS = OT_SECONDS + 1
                WHERE  OT_ID      = @OT_ID;
        END

        UPDATE TB_WT_STATUS SET FTR_TIME = GETDATE(), FREG_VALUE = CAST(@SHIFTN AS VARCHAR)
        WHERE FDEV_NAME = 'WTG' AND FLINE = @VLINE AND FREG_NAME = 'SHIFT';

        UPDATE TB_WT_STATUS SET FTR_TIME = GETDATE(), FREG_VALUE = CAST(@SHIFTN AS VARCHAR)
        WHERE FDEV_NAME = 'WTG' AND FLINE = @VLINE AND FREG_NAME = 'LAST SHIFT';

        UPDATE TB_WT_STATUS SET FTR_TIME = GETDATE(), FREG_VALUE = CAST(@VINFO AS VARCHAR)
        WHERE FDEV_NAME = 'WTG' AND FLINE = @VLINE AND FREG_NAME = 'INFO';

        UPDATE TB_WT_STATUS SET FTR_TIME = GETDATE(), FREG_VALUE = @DATE_SHIFT
        WHERE FDEV_NAME = 'WTG' AND FLINE = @VLINE AND FREG_NAME = 'DATE SHIFT';
    END

    /* DATE row always updated */
    UPDATE TB_WT_STATUS SET FTR_TIME = GETDATE(), FREG_VALUE = @DATE_TODAY
    WHERE FDEV_NAME = 'WTG' AND FLINE = @VLINE AND FREG_NAME = 'DATE';

    /* ---- Reset guard: reset WT counter once per reset window ---- */
    DECLARE @LAST_RESET DATETIME;
    SELECT @LAST_RESET = TRY_CAST(FREG_VALUE AS DATETIME)
    FROM TB_WT_STATUS
    WHERE FDEV_NAME = 'WTG' AND FLINE = @VLINE AND FREG_NAME = 'RESET_TS';

    IF  DATEPART(SECOND, GETDATE()) <= 10
    AND (
        (DATEPART(HOUR, GETDATE()) = 19 AND DATEPART(MINUTE, GETDATE()) = 55)
     OR (DATEPART(HOUR, GETDATE()) =  7 AND DATEPART(MINUTE, GETDATE()) =  5)
    )
    AND (
        @LAST_RESET IS NULL
        OR DATEDIFF(MINUTE, @LAST_RESET, GETDATE()) > 5
    )
    BEGIN
        UPDATE TB_WT_STATUS SET FREG_VALUE = '0'
        WHERE FDEV_NAME = 'WTG' AND FLINE = @VLINE AND FREG_NAME = 'WT';

        IF EXISTS (SELECT 1 FROM TB_WT_STATUS
                   WHERE FDEV_NAME='WTG' AND FLINE=@VLINE AND FREG_NAME='RESET_TS')
            UPDATE TB_WT_STATUS SET FTR_TIME=GETDATE(),
                   FREG_VALUE = CONVERT(VARCHAR(30), GETDATE(), 120)
            WHERE  FDEV_NAME='WTG' AND FLINE=@VLINE AND FREG_NAME='RESET_TS';
        ELSE
            INSERT INTO TB_WT_STATUS (FDEV_NAME, FLINE, FREG_NAME, FREG_VALUE, FTR_TIME)
            VALUES ('WTG', @VLINE, 'RESET_TS', CONVERT(VARCHAR(30), GETDATE(), 120), GETDATE());
    END

    /* ---- Update DATE NOW every 2 seconds ---- */
    IF DATEPART(SECOND, GETDATE()) % 2 = 1
    BEGIN
        UPDATE TB_WT_STATUS
        SET    FTR_TIME   = GETDATE(),
               FREG_VALUE = CONVERT(VARCHAR(30), CAST(GETDATE() AS DATE), 126)
        WHERE  FDEV_NAME  = 'WTG'
          AND  FLINE      = @VLINE
          AND  FREG_NAME  = 'DATE NOW';
    END

END TRY
BEGIN CATCH
    /* Top-level catch: log error to TB_WT_STATUS */
    DECLARE @EMSG VARCHAR(30) = LEFT(ERROR_MESSAGE(), 30);

    IF EXISTS (SELECT 1 FROM TB_WT_STATUS
               WHERE FDEV_NAME='WTG' AND FLINE=@VLINE AND FREG_NAME='LAST_ERR')
        UPDATE TB_WT_STATUS
        SET    FTR_TIME = GETDATE(), FREG_VALUE = @EMSG
        WHERE  FDEV_NAME='WTG' AND FLINE=@VLINE AND FREG_NAME='LAST_ERR';
    ELSE
        INSERT INTO TB_WT_STATUS (FDEV_NAME, FLINE, FREG_NAME, FREG_VALUE, FTR_TIME)
        VALUES ('WTG', @VLINE, 'LAST_ERR', @EMSG, GETDATE());
END CATCH;
GO

PRINT 'SP_WTG_DB recreated (cross-DB removed)';
GO
