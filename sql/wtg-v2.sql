/*
================================================================================
  WTG v2 -- Working Time Gauge (Clean Design)
  Target DB : DB_TMMIN1_KRW_WTG_HV_BATTERY
  Objects   : TB_WTG_* / fn_WTG_* / V_WTG_* / SP_WTG_* / WTG_V2_TICKER
================================================================================

  PRINSIP DESAIN:
  ---------------
  MASALAH LAMA: SP increment +1 setiap detik --> kalau SQL Agent skip 1 tick,
    counter ketinggalan selamanya. Terlihat "berhenti".

  SOLUSI BARU: SP TIDAK menyimpan counter. SP menghitung ulang dari GETDATE()
    setiap dipanggil dan menulis HASIL ke register.
    --> Skip 3 detik pun, nilai yang ditulis TETAP AKURAT.
    --> V_WTG_STATUS selalu 100% akurat terlepas dari SP.

  FORMULA:
    WT_CLEAN_S = (GETDATE() - shift_start) - SUM(break_elapsed)
    OT_S       = GETDATE() - OT_OPEN  (jika ada OT session open)
    PLAN       = WT_CLEAN_S / TAKT_TIME_S
    EFF (%)    = ACTUAL_QTY * TAKT_TIME_S / WT_CLEAN_S * 100

  DOW BITMASK (DATEPART(WEEKDAY) based):
    1=Sun  2=Mon  4=Tue  8=Wed  16=Thu  32=Fri  64=Sat
    Mon-Fri = 62 | All days = 127 | Mon-Thu = 30

  OBJECTS:
    TB_WTG_SHIFT    -- master jadwal shift per line (dengan DOW bitmask)
    TB_WTG_BREAK    -- break slots (DOW-aware, tak terbatas)
    TB_WTG_OVERTIME -- sesi overtime open/close
    TB_WTG_REG      -- register real-time untuk PLC/display

    fn_WTG_CleanSeconds -- INTI: kalkulasi detik kerja bersih
    fn_WTG_OTSeconds    -- kalkulasi detik overtime
    fn_WTG_IsInBreak    -- apakah @now sedang di window break

    V_WTG_STATUS    -- view real-time per line (SELALU akurat)
    SP_WTG_Tick     -- tulis hasil kalkulasi ke TB_WTG_REG (untuk PLC)
    SP_WTG_OT_Open  -- buka sesi overtime
    SP_WTG_OT_Close -- tutup sesi overtime

    WTG_V2_TICKER   -- SQL Agent job, loop 57 detik per menit
================================================================================
*/

USE [DB_TMMIN1_KRW_WTG_HV_BATTERY];
GO
SET NOCOUNT ON;
GO

/* ============================================================
   1. TABLES
   ============================================================ */

IF OBJECT_ID('TB_WTG_SHIFT','U') IS NULL
    CREATE TABLE TB_WTG_SHIFT (
        SHIFT_ID    INT          IDENTITY(1,1) NOT NULL,
        LINENAME    VARCHAR(30)  NOT NULL,
        SHIFT_NO    TINYINT      NOT NULL,           -- 1=Day, 2=Night, ...
        SHIFT_LABEL VARCHAR(20)  NOT NULL,
        START_TIME  TIME(0)      NOT NULL,
        END_TIME    TIME(0)      NOT NULL,           -- < START_TIME = overnight
        APPLY_DOW   TINYINT      NOT NULL DEFAULT 62, -- Mon-Fri
        IS_ACTIVE   BIT          NOT NULL DEFAULT 1,
        CONSTRAINT PK_WTG_SHIFT PRIMARY KEY (SHIFT_ID),
        CONSTRAINT UQ_WTG_SHIFT UNIQUE (LINENAME, SHIFT_NO)
    );
GO

IF OBJECT_ID('TB_WTG_BREAK','U') IS NULL
    CREATE TABLE TB_WTG_BREAK (
        BREAK_ID    INT         IDENTITY(1,1) NOT NULL,
        SHIFT_ID    INT         NOT NULL,
        BREAK_SEQ   TINYINT     NOT NULL,
        BREAK_LABEL VARCHAR(20) NULL,
        BREAK_START TIME(0)     NOT NULL,
        BREAK_END   TIME(0)     NOT NULL,
        APPLY_DOW   TINYINT     NOT NULL DEFAULT 127, -- default semua hari
        IS_ACTIVE   BIT         NOT NULL DEFAULT 1,
        CONSTRAINT PK_WTG_BREAK PRIMARY KEY (BREAK_ID),
        CONSTRAINT FK_WTG_BREAK_SHIFT FOREIGN KEY (SHIFT_ID)
            REFERENCES TB_WTG_SHIFT(SHIFT_ID),
        CONSTRAINT UQ_WTG_BREAK UNIQUE (SHIFT_ID, BREAK_SEQ, APPLY_DOW)
    );
GO

IF OBJECT_ID('TB_WTG_OVERTIME','U') IS NULL
BEGIN
    CREATE TABLE TB_WTG_OVERTIME (
        OT_ID       INT          IDENTITY(1,1) NOT NULL,
        LINENAME    VARCHAR(30)  NOT NULL,
        OT_OPEN     DATETIME     NOT NULL DEFAULT GETDATE(),
        OT_CLOSE    DATETIME     NULL,               -- NULL = masih berjalan
        OT_REASON   VARCHAR(100) NULL,
        CREATED_BY  VARCHAR(30)  NOT NULL DEFAULT 'SYSTEM',
        CONSTRAINT PK_WTG_OT PRIMARY KEY (OT_ID)
    );
    CREATE INDEX IX_WTG_OT ON TB_WTG_OVERTIME (LINENAME, OT_OPEN DESC);
END
GO

-- Register untuk PLC/display. Diupdate SP_WTG_Tick setiap detik.
-- REG_NAME standar:
--   WT_CLEAN_S   = detik kerja bersih (integer sebagai string)
--   WT_CLEAN_HMS = HH:MM:SS
--   OT_S         = detik overtime
--   WORK_MODE    = WORKING / BREAK / OVERTIME / IDLE
--   SHIFT_NO     = nomor shift aktif
--   SHIFT_DATE   = tanggal logis shift (YYYY-MM-DD)
IF OBJECT_ID('TB_WTG_REG','U') IS NULL
    CREATE TABLE TB_WTG_REG (
        LINENAME   VARCHAR(30) NOT NULL,
        REG_NAME   VARCHAR(20) NOT NULL,
        REG_VALUE  VARCHAR(30) NOT NULL DEFAULT '',
        UPDATED_AT DATETIME    NOT NULL DEFAULT GETDATE(),
        CONSTRAINT PK_WTG_REG PRIMARY KEY (LINENAME, REG_NAME)
    );
GO

/* ============================================================
   2. CORE FUNCTION: fn_WTG_CleanSeconds
      Menghitung detik kerja bersih secara matematis murni.
      TIDAK mengakses TB_WTG_REG / TB_WTG_OVERTIME.
      TRY_CAST dipakai sebagai guard (TRY/CATCH dilarang di scalar fn).
   ============================================================ */

IF OBJECT_ID('dbo.fn_WTG_CleanSeconds','FN') IS NOT NULL
    DROP FUNCTION dbo.fn_WTG_CleanSeconds;
GO

CREATE FUNCTION dbo.fn_WTG_CleanSeconds (
    @linename VARCHAR(30),
    @now      DATETIME
)
RETURNS INT
AS
BEGIN
    DECLARE @shift_id INT;
    DECLARE @start_t  TIME(0);
    DECLARE @end_t    TIME(0);

    DECLARE @now_date DATE    = CAST(@now AS DATE);
    DECLARE @now_time TIME(0) = CAST(@now AS TIME(0));
    DECLARE @dow_bit  INT     = POWER(2, DATEPART(WEEKDAY, @now) - 1);

    -- Cari shift aktif yang mengandung @now
    SELECT TOP 1
        @shift_id = SHIFT_ID,
        @start_t  = START_TIME,
        @end_t    = END_TIME
    FROM TB_WTG_SHIFT
    WHERE LINENAME  = @linename
      AND IS_ACTIVE = 1
      AND (APPLY_DOW & @dow_bit) > 0
      AND (
          -- Shift normal (misal 07:20-20:00)
          (START_TIME <= END_TIME
           AND @now_time >= START_TIME
           AND @now_time <  END_TIME)
          OR
          -- Shift overnight (misal 20:00-06:45): sore ATAU pagi hari berikut
          (START_TIME > END_TIME
           AND (@now_time >= START_TIME OR @now_time < END_TIME))
      )
    ORDER BY SHIFT_NO;

    IF @shift_id IS NULL RETURN 0;

    -- Hitung absolute shift_start_dt dan shift_date
    -- shift_date = hari kalender dimana shift dimulai (penting untuk break lookup)
    DECLARE @shift_date     DATE;
    DECLARE @shift_start_dt DATETIME;
    DECLARE @shift_end_dt   DATETIME;

    IF @start_t <= @end_t
    BEGIN
        -- Normal shift: dimulai hari ini
        SET @shift_date     = @now_date;
        SET @shift_start_dt = CAST(@now_date AS DATETIME) + CAST(@start_t AS DATETIME);
        SET @shift_end_dt   = CAST(@now_date AS DATETIME) + CAST(@end_t   AS DATETIME);
    END
    ELSE IF @now_time >= @start_t
    BEGIN
        -- Overnight: bagian sore (shift baru mulai hari ini)
        SET @shift_date     = @now_date;
        SET @shift_start_dt = CAST(@now_date AS DATETIME) + CAST(@start_t AS DATETIME);
        SET @shift_end_dt   = CAST(DATEADD(DAY,1,@now_date) AS DATETIME) + CAST(@end_t AS DATETIME);
    END
    ELSE
    BEGIN
        -- Overnight: bagian pagi (shift dimulai kemarin)
        SET @shift_date     = CAST(DATEADD(DAY,-1,@now_date) AS DATE);
        SET @shift_start_dt = CAST(DATEADD(DAY,-1,@now_date) AS DATETIME) + CAST(@start_t AS DATETIME);
        SET @shift_end_dt   = CAST(@now_date AS DATETIME) + CAST(@end_t AS DATETIME);
    END

    -- Clamp @now ke shift_end (jika SP dipanggil setelah shift selesai)
    DECLARE @eff     DATETIME = CASE WHEN @now > @shift_end_dt THEN @shift_end_dt ELSE @now END;
    DECLARE @elapsed INT      = DATEDIFF(SECOND, @shift_start_dt, @eff);
    IF @elapsed <= 0 RETURN 0;

    -- DOW bit dari shift_date (untuk filter break yang DOW-aware)
    DECLARE @shift_dow INT = POWER(2, DATEPART(WEEKDAY, @shift_date) - 1);

    -- Hitung total detik break yang sudah terlewati
    -- Break datetime:
    --   BREAK_START >= shift START_TIME → break pada shift_date
    --   BREAK_START <  shift START_TIME → break pada shift_date + 1 (overnight post-midnight)
    DECLARE @break_ded INT = ISNULL((
        SELECT SUM(
            CASE
                WHEN @eff >= b_end   THEN DATEDIFF(SECOND, b_start, b_end)
                WHEN @eff >  b_start THEN DATEDIFF(SECOND, b_start, @eff)
                ELSE 0
            END
        )
        FROM (
            SELECT
                CASE WHEN BREAK_START >= @start_t
                     THEN CAST(@shift_date AS DATETIME) + CAST(BREAK_START AS DATETIME)
                     ELSE CAST(DATEADD(DAY,1,@shift_date) AS DATETIME) + CAST(BREAK_START AS DATETIME)
                END AS b_start,
                CASE WHEN BREAK_START >= @start_t
                     THEN CAST(@shift_date AS DATETIME) + CAST(BREAK_END AS DATETIME)
                     ELSE CAST(DATEADD(DAY,1,@shift_date) AS DATETIME) + CAST(BREAK_END AS DATETIME)
                END AS b_end
            FROM TB_WTG_BREAK
            WHERE SHIFT_ID  = @shift_id
              AND IS_ACTIVE = 1
              AND (APPLY_DOW & @shift_dow) > 0
        ) b
        WHERE @eff > b.b_start
    ), 0);

    DECLARE @result INT = @elapsed - @break_ded;
    RETURN CASE WHEN @result > 0 THEN @result ELSE 0 END;
END;
GO

/* ============================================================
   3. fn_WTG_OTSeconds
      Detik overtime dari sesi OT yang masih open hari ini.
   ============================================================ */

IF OBJECT_ID('dbo.fn_WTG_OTSeconds','FN') IS NOT NULL
    DROP FUNCTION dbo.fn_WTG_OTSeconds;
GO

CREATE FUNCTION dbo.fn_WTG_OTSeconds (
    @linename VARCHAR(30),
    @now      DATETIME
)
RETURNS INT
AS
BEGIN
    DECLARE @ot_open DATETIME;
    SELECT TOP 1 @ot_open = OT_OPEN
    FROM TB_WTG_OVERTIME
    WHERE LINENAME = @linename
      AND OT_CLOSE IS NULL
      AND CAST(OT_OPEN AS DATE) = CAST(@now AS DATE)
    ORDER BY OT_ID DESC;

    IF @ot_open IS NULL RETURN 0;
    RETURN ISNULL(DATEDIFF(SECOND, @ot_open, @now), 0);
END;
GO

/* ============================================================
   4. fn_WTG_IsInBreak
      Return 1 jika @now berada di dalam window break aktif.
   ============================================================ */

IF OBJECT_ID('dbo.fn_WTG_IsInBreak','FN') IS NOT NULL
    DROP FUNCTION dbo.fn_WTG_IsInBreak;
GO

CREATE FUNCTION dbo.fn_WTG_IsInBreak (
    @linename VARCHAR(30),
    @now      DATETIME
)
RETURNS BIT
AS
BEGIN
    DECLARE @shift_id INT;
    DECLARE @start_t  TIME(0);
    DECLARE @now_time TIME(0) = CAST(@now AS TIME(0));
    DECLARE @now_date DATE    = CAST(@now AS DATE);
    DECLARE @dow_bit  INT     = POWER(2, DATEPART(WEEKDAY, @now) - 1);

    SELECT TOP 1
        @shift_id = SHIFT_ID,
        @start_t  = START_TIME
    FROM TB_WTG_SHIFT
    WHERE LINENAME  = @linename
      AND IS_ACTIVE = 1
      AND (APPLY_DOW & @dow_bit) > 0
      AND (
          (START_TIME <= END_TIME AND @now_time >= START_TIME AND @now_time < END_TIME)
       OR (START_TIME >  END_TIME AND (@now_time >= START_TIME OR @now_time < END_TIME))
      )
    ORDER BY SHIFT_NO;

    IF @shift_id IS NULL RETURN 0;

    -- Tentukan shift_date (sama seperti di fn_WTG_CleanSeconds)
    DECLARE @shift_date DATE = CASE
        WHEN (SELECT END_TIME FROM TB_WTG_SHIFT WHERE SHIFT_ID = @shift_id) >= @start_t
             THEN @now_date
        WHEN @now_time >= @start_t THEN @now_date
        ELSE CAST(DATEADD(DAY,-1,@now_date) AS DATE)
    END;
    DECLARE @shift_dow INT = POWER(2, DATEPART(WEEKDAY, @shift_date) - 1);

    IF EXISTS (
        SELECT 1
        FROM TB_WTG_BREAK b
        WHERE b.SHIFT_ID  = @shift_id
          AND b.IS_ACTIVE = 1
          AND (b.APPLY_DOW & @shift_dow) > 0
          AND @now >= CASE WHEN b.BREAK_START >= @start_t
                          THEN CAST(@shift_date AS DATETIME) + CAST(b.BREAK_START AS DATETIME)
                          ELSE CAST(DATEADD(DAY,1,@shift_date) AS DATETIME) + CAST(b.BREAK_START AS DATETIME)
                     END
          AND @now <  CASE WHEN b.BREAK_START >= @start_t
                          THEN CAST(@shift_date AS DATETIME) + CAST(b.BREAK_END AS DATETIME)
                          ELSE CAST(DATEADD(DAY,1,@shift_date) AS DATETIME) + CAST(b.BREAK_END AS DATETIME)
                     END
    )
        RETURN 1;

    RETURN 0;
END;
GO

/* ============================================================
   5. VIEW V_WTG_STATUS
      Real-time status per line. SELALU akurat — query langsung
      ke fungsi kalkulasi, tidak mengandalkan TB_WTG_REG.
   ============================================================ */

IF OBJECT_ID('V_WTG_STATUS','V') IS NOT NULL DROP VIEW V_WTG_STATUS;
GO

CREATE VIEW V_WTG_STATUS AS
SELECT
    sh.LINENAME,
    sh.SHIFT_NO,
    sh.SHIFT_LABEL,
    GETDATE()                                                      AS NOW_DT,
    -- detik kerja bersih (selalu akurat)
    calc.clean_s                                                   AS CLEAN_SECONDS,
    -- format HH:MM:SS
    RIGHT('0'+CAST(calc.clean_s/3600 AS VARCHAR(4)),2)+':'+
    RIGHT('0'+CAST((calc.clean_s%3600)/60 AS VARCHAR(2)),2)+':'+
    RIGHT('0'+CAST(calc.clean_s%60 AS VARCHAR(2)),2)               AS CLEAN_HMS,
    -- detik overtime
    calc.ot_s                                                      AS OT_SECONDS,
    RIGHT('0'+CAST(calc.ot_s/3600 AS VARCHAR(4)),2)+':'+
    RIGHT('0'+CAST((calc.ot_s%3600)/60 AS VARCHAR(2)),2)+':'+
    RIGHT('0'+CAST(calc.ot_s%60 AS VARCHAR(2)),2)                  AS OT_HMS,
    -- status
    CASE
        WHEN calc.ot_s > 0                                          THEN 'OVERTIME'
        WHEN dbo.fn_WTG_IsInBreak(sh.LINENAME, GETDATE()) = 1      THEN 'BREAK'
        ELSE 'WORKING'
    END                                                            AS WORK_MODE,
    -- tanggal logis shift (overnight: jam 00-12 masih "kemarin")
    CAST(CASE
        WHEN sh.START_TIME > sh.END_TIME
             AND CAST(GETDATE() AS TIME(0)) < sh.END_TIME
        THEN DATEADD(DAY,-1, CAST(GETDATE() AS DATE))
        ELSE CAST(GETDATE() AS DATE)
    END AS DATE)                                                   AS SHIFT_DATE
FROM TB_WTG_SHIFT sh
CROSS APPLY (
    SELECT
        dbo.fn_WTG_CleanSeconds(sh.LINENAME, GETDATE()) AS clean_s,
        dbo.fn_WTG_OTSeconds(sh.LINENAME, GETDATE())    AS ot_s
) calc
WHERE sh.IS_ACTIVE = 1
  AND (sh.APPLY_DOW & POWER(2, DATEPART(WEEKDAY, GETDATE()) - 1)) > 0
  AND (
      (sh.START_TIME <= sh.END_TIME
       AND CAST(GETDATE() AS TIME(0)) >= sh.START_TIME
       AND CAST(GETDATE() AS TIME(0)) <  sh.END_TIME)
   OR (sh.START_TIME > sh.END_TIME
       AND (CAST(GETDATE() AS TIME(0)) >= sh.START_TIME
         OR CAST(GETDATE() AS TIME(0)) <  sh.END_TIME))
  );
GO

/* ============================================================
   6. SP_WTG_Tick
      Dipanggil SQL Agent setiap detik.
      Menghitung ulang dari GETDATE() lalu WRITE ke TB_WTG_REG.
      --> Tidak pernah drift. Skip beberapa detik = tidak masalah.
   ============================================================ */

IF OBJECT_ID('dbo.SP_WTG_Tick','P') IS NOT NULL DROP PROCEDURE dbo.SP_WTG_Tick;
GO

CREATE PROCEDURE [dbo].[SP_WTG_Tick]
    @linename VARCHAR(30) = 'ADAPTIVE'
AS
SET NOCOUNT ON;
SET XACT_ABORT ON;

DECLARE @now      DATETIME = GETDATE();
DECLARE @clean_s  INT      = dbo.fn_WTG_CleanSeconds(@linename, @now);
DECLARE @ot_s     INT      = dbo.fn_WTG_OTSeconds(@linename, @now);
DECLARE @in_break BIT      = dbo.fn_WTG_IsInBreak(@linename, @now);

DECLARE @work_mode VARCHAR(10) = CASE
    WHEN @ot_s > 0     THEN 'OVERTIME'
    WHEN @in_break = 1 THEN 'BREAK'
    WHEN @clean_s > 0  THEN 'WORKING'
    ELSE                    'IDLE'
END;

-- Shift aktif
DECLARE @shift_no    TINYINT;
DECLARE @shift_label VARCHAR(20);
DECLARE @start_t     TIME(0);
DECLARE @end_t       TIME(0);
DECLARE @dow_bit     INT = POWER(2, DATEPART(WEEKDAY, @now) - 1);

SELECT TOP 1
    @shift_no    = SHIFT_NO,
    @shift_label = SHIFT_LABEL,
    @start_t     = START_TIME,
    @end_t       = END_TIME
FROM TB_WTG_SHIFT
WHERE LINENAME  = @linename
  AND IS_ACTIVE = 1
  AND (APPLY_DOW & @dow_bit) > 0
  AND (
      (START_TIME <= END_TIME AND CAST(@now AS TIME(0)) >= START_TIME AND CAST(@now AS TIME(0)) < END_TIME)
   OR (START_TIME >  END_TIME AND (CAST(@now AS TIME(0)) >= START_TIME OR CAST(@now AS TIME(0)) < END_TIME))
  )
ORDER BY SHIFT_NO;

-- Tanggal logis shift
DECLARE @shift_date VARCHAR(10) = CASE
    WHEN @start_t IS NOT NULL AND @start_t > @end_t
         AND CAST(@now AS TIME(0)) < @end_t
    THEN CONVERT(VARCHAR(10), DATEADD(DAY,-1,CAST(@now AS DATE)), 126)
    ELSE CONVERT(VARCHAR(10), CAST(@now AS DATE), 126)
END;

-- Format HMS
DECLARE @clean_hms VARCHAR(8) =
    RIGHT('0'+CAST(@clean_s/3600 AS VARCHAR(4)),2)+':'+
    RIGHT('0'+CAST((@clean_s%3600)/60 AS VARCHAR(2)),2)+':'+
    RIGHT('0'+CAST(@clean_s%60 AS VARCHAR(2)),2);

DECLARE @ot_hms VARCHAR(8) =
    RIGHT('0'+CAST(@ot_s/3600 AS VARCHAR(4)),2)+':'+
    RIGHT('0'+CAST((@ot_s%3600)/60 AS VARCHAR(2)),2)+':'+
    RIGHT('0'+CAST(@ot_s%60 AS VARCHAR(2)),2);

-- UPSERT ke TB_WTG_REG (MERGE)
MERGE TB_WTG_REG AS t
USING (VALUES
    (@linename, 'WT_CLEAN_S',   CAST(@clean_s AS VARCHAR(30))),
    (@linename, 'WT_CLEAN_HMS', @clean_hms),
    (@linename, 'OT_S',         CAST(@ot_s AS VARCHAR(30))),
    (@linename, 'OT_HMS',       @ot_hms),
    (@linename, 'WORK_MODE',    @work_mode),
    (@linename, 'SHIFT_NO',     ISNULL(CAST(@shift_no AS VARCHAR(2)), '0')),
    (@linename, 'SHIFT_LABEL',  ISNULL(@shift_label, 'IDLE')),
    (@linename, 'SHIFT_DATE',   ISNULL(@shift_date, CONVERT(VARCHAR(10),CAST(@now AS DATE),126)))
) AS src (linename, reg_name, reg_value)
ON t.LINENAME = src.linename AND t.REG_NAME = src.reg_name
WHEN MATCHED     THEN UPDATE SET t.REG_VALUE = src.reg_value, t.UPDATED_AT = @now
WHEN NOT MATCHED THEN INSERT (LINENAME, REG_NAME, REG_VALUE, UPDATED_AT)
                      VALUES (src.linename, src.reg_name, src.reg_value, @now);
GO

/* ============================================================
   7. SP_WTG_OT_Open / SP_WTG_OT_Close
   ============================================================ */

IF OBJECT_ID('dbo.SP_WTG_OT_Open','P') IS NOT NULL DROP PROCEDURE dbo.SP_WTG_OT_Open;
GO

CREATE PROCEDURE [dbo].[SP_WTG_OT_Open]
    @linename VARCHAR(30)  = 'ADAPTIVE',
    @reason   VARCHAR(100) = NULL
AS
SET NOCOUNT ON;

IF EXISTS (
    SELECT 1 FROM TB_WTG_OVERTIME
    WHERE LINENAME = @linename
      AND OT_CLOSE IS NULL
      AND CAST(OT_OPEN AS DATE) = CAST(GETDATE() AS DATE)
)
BEGIN
    RAISERROR('OT session sudah open untuk line %s hari ini.', 16, 1, @linename);
    RETURN;
END

INSERT INTO TB_WTG_OVERTIME (LINENAME, OT_OPEN, OT_REASON)
VALUES (@linename, GETDATE(), @reason);

SELECT 'OPENED' AS STATUS, LINENAME, OT_OPEN, OT_REASON
FROM TB_WTG_OVERTIME WHERE OT_ID = SCOPE_IDENTITY();
GO

IF OBJECT_ID('dbo.SP_WTG_OT_Close','P') IS NOT NULL DROP PROCEDURE dbo.SP_WTG_OT_Close;
GO

CREATE PROCEDURE [dbo].[SP_WTG_OT_Close]
    @linename VARCHAR(30) = 'ADAPTIVE'
AS
SET NOCOUNT ON;

DECLARE @ot_id INT;
SELECT TOP 1 @ot_id = OT_ID FROM TB_WTG_OVERTIME
WHERE LINENAME = @linename AND OT_CLOSE IS NULL
ORDER BY OT_ID DESC;

IF @ot_id IS NULL
BEGIN
    RAISERROR('Tidak ada OT session open untuk line %s.', 16, 1, @linename);
    RETURN;
END

UPDATE TB_WTG_OVERTIME SET OT_CLOSE = GETDATE() WHERE OT_ID = @ot_id;

SELECT
    OT_ID, LINENAME, OT_OPEN, OT_CLOSE,
    DATEDIFF(SECOND, OT_OPEN, OT_CLOSE)                           AS OT_TOTAL_S,
    RIGHT('0'+CAST(DATEDIFF(SECOND,OT_OPEN,OT_CLOSE)/3600 AS VARCHAR),2)+':'+
    RIGHT('0'+CAST((DATEDIFF(SECOND,OT_OPEN,OT_CLOSE)%3600)/60 AS VARCHAR),2)+':'+
    RIGHT('0'+CAST(DATEDIFF(SECOND,OT_OPEN,OT_CLOSE)%60 AS VARCHAR),2) AS OT_TOTAL_HMS,
    OT_REASON
FROM TB_WTG_OVERTIME WHERE OT_ID = @ot_id;
GO

/* ============================================================
   8. SQL AGENT JOB: WTG_V2_TICKER
      Loop time-based 57 detik per run.
      SP tidak increment -- hitung ulang setiap detik --> gap-proof.
   ============================================================ */

USE msdb;
GO

IF EXISTS (SELECT 1 FROM msdb.dbo.sysjobs WHERE name = N'WTG_V2_TICKER')
    EXEC msdb.dbo.sp_delete_job @job_name = N'WTG_V2_TICKER';
GO

EXEC msdb.dbo.sp_add_job
    @job_name    = N'WTG_V2_TICKER',
    @enabled     = 1,
    @description = N'WTG v2: hitung jam kerja bersih setiap detik (matematis, tidak drift)';

EXEC msdb.dbo.sp_add_jobstep
    @job_name      = N'WTG_V2_TICKER',
    @step_name     = N'Tick',
    @subsystem     = N'TSQL',
    @database_name = N'DB_TMMIN1_KRW_WTG_HV_BATTERY',
    @command       = N'
-- Loop time-based: berjalan 57 detik, selesai sebelum schedule berikutnya (60s)
-- SP_WTG_Tick menghitung ulang dari GETDATE() setiap call -> tidak pernah drift
DECLARE @until DATETIME = DATEADD(SECOND, 57, GETDATE());
WHILE GETDATE() < @until
BEGIN
    EXEC dbo.SP_WTG_Tick @linename = ''ADAPTIVE'';
    WAITFOR DELAY ''00:00:01'';
END',
    @on_success_action = 1,
    @on_fail_action    = 2;

DECLARE @sch_id INT;
EXEC msdb.dbo.sp_add_schedule
    @schedule_name        = N'WTG_V2_Every_Minute',
    @freq_type            = 4,
    @freq_interval        = 1,
    @freq_subday_type     = 4,
    @freq_subday_interval = 1,
    @active_start_time    = 000000,
    @active_end_time      = 235959,
    @schedule_id          = @sch_id OUTPUT;

EXEC msdb.dbo.sp_attach_schedule
    @job_name    = N'WTG_V2_TICKER',
    @schedule_id = @sch_id;

EXEC msdb.dbo.sp_add_jobserver
    @job_name    = N'WTG_V2_TICKER',
    @server_name = N'(local)';
GO

USE [DB_TMMIN1_KRW_WTG_HV_BATTERY];
GO

/* ============================================================
   9. SEED DATA -- ADAPTIVE line
   ============================================================ */

-- Shift Day: 07:20 - 20:00, Mon-Fri (DOW=62)
IF NOT EXISTS (SELECT 1 FROM TB_WTG_SHIFT WHERE LINENAME='ADAPTIVE' AND SHIFT_NO=1)
    INSERT INTO TB_WTG_SHIFT (LINENAME,SHIFT_NO,SHIFT_LABEL,START_TIME,END_TIME,APPLY_DOW)
    VALUES ('ADAPTIVE',1,'Day','07:20','20:00',62);

-- Shift Night: 20:00 - 06:45, Mon-Fri (DOW=62)
IF NOT EXISTS (SELECT 1 FROM TB_WTG_SHIFT WHERE LINENAME='ADAPTIVE' AND SHIFT_NO=2)
    INSERT INTO TB_WTG_SHIFT (LINENAME,SHIFT_NO,SHIFT_LABEL,START_TIME,END_TIME,APPLY_DOW)
    VALUES ('ADAPTIVE',2,'Night','20:00','06:45',62);
GO

DECLARE @D INT = (SELECT SHIFT_ID FROM TB_WTG_SHIFT WHERE LINENAME='ADAPTIVE' AND SHIFT_NO=1);
DECLARE @N INT = (SELECT SHIFT_ID FROM TB_WTG_SHIFT WHERE LINENAME='ADAPTIVE' AND SHIFT_NO=2);

-- ── DAY SHIFT BREAKS ──────────────────────────────────────────
-- Rest 1: sama Mon-Fri (DOW=62)
IF @D IS NOT NULL AND NOT EXISTS (SELECT 1 FROM TB_WTG_BREAK WHERE SHIFT_ID=@D AND BREAK_SEQ=1 AND APPLY_DOW=62)
    INSERT INTO TB_WTG_BREAK VALUES (@D,1,'Rest 1','09:30','09:40',62,1);

-- Lunch Mon-Thu (DOW=30)
IF @D IS NOT NULL AND NOT EXISTS (SELECT 1 FROM TB_WTG_BREAK WHERE SHIFT_ID=@D AND BREAK_SEQ=2 AND APPLY_DOW=30)
    INSERT INTO TB_WTG_BREAK VALUES (@D,2,'Lunch','11:45','12:30',30,1);

-- Lunch Jumat (DOW=32, lebih panjang)
IF @D IS NOT NULL AND NOT EXISTS (SELECT 1 FROM TB_WTG_BREAK WHERE SHIFT_ID=@D AND BREAK_SEQ=2 AND APPLY_DOW=32)
    INSERT INTO TB_WTG_BREAK VALUES (@D,2,'Lunch Fri','11:45','13:00',32,1);

-- Rest 2: sama Mon-Fri (DOW=62)
IF @D IS NOT NULL AND NOT EXISTS (SELECT 1 FROM TB_WTG_BREAK WHERE SHIFT_ID=@D AND BREAK_SEQ=3 AND APPLY_DOW=62)
    INSERT INTO TB_WTG_BREAK VALUES (@D,3,'Rest 2','14:30','14:40',62,1);

-- Rest 3 Mon-Thu (DOW=30)
IF @D IS NOT NULL AND NOT EXISTS (SELECT 1 FROM TB_WTG_BREAK WHERE SHIFT_ID=@D AND BREAK_SEQ=4 AND APPLY_DOW=30)
    INSERT INTO TB_WTG_BREAK VALUES (@D,4,'Rest 3','18:00','18:15',30,1);

-- Rest 3 Jumat (DOW=32, lebih awal)
IF @D IS NOT NULL AND NOT EXISTS (SELECT 1 FROM TB_WTG_BREAK WHERE SHIFT_ID=@D AND BREAK_SEQ=4 AND APPLY_DOW=32)
    INSERT INTO TB_WTG_BREAK VALUES (@D,4,'Rest 3 Fri','16:30','16:45',32,1);

-- ── NIGHT SHIFT BREAKS ────────────────────────────────────────
-- Rest 1: sama Mon-Fri
IF @N IS NOT NULL AND NOT EXISTS (SELECT 1 FROM TB_WTG_BREAK WHERE SHIFT_ID=@N AND BREAK_SEQ=1 AND APPLY_DOW=62)
    INSERT INTO TB_WTG_BREAK VALUES (@N,1,'Rest 1','22:00','22:10',62,1);

-- Dinner Mon-Thu (DOW=30)
IF @N IS NOT NULL AND NOT EXISTS (SELECT 1 FROM TB_WTG_BREAK WHERE SHIFT_ID=@N AND BREAK_SEQ=2 AND APPLY_DOW=30)
    INSERT INTO TB_WTG_BREAK VALUES (@N,2,'Dinner','00:00','00:20',30,1);

-- Dinner Jumat (DOW=32)
IF @N IS NOT NULL AND NOT EXISTS (SELECT 1 FROM TB_WTG_BREAK WHERE SHIFT_ID=@N AND BREAK_SEQ=2 AND APPLY_DOW=32)
    INSERT INTO TB_WTG_BREAK VALUES (@N,2,'Dinner Fri','00:00','00:30',32,1);

-- Rest 2: sama Mon-Fri
IF @N IS NOT NULL AND NOT EXISTS (SELECT 1 FROM TB_WTG_BREAK WHERE SHIFT_ID=@N AND BREAK_SEQ=3 AND APPLY_DOW=62)
    INSERT INTO TB_WTG_BREAK VALUES (@N,3,'Rest 2','02:30','02:40',62,1);

-- Rest 3: sama Mon-Fri
IF @N IS NOT NULL AND NOT EXISTS (SELECT 1 FROM TB_WTG_BREAK WHERE SHIFT_ID=@N AND BREAK_SEQ=4 AND APPLY_DOW=62)
    INSERT INTO TB_WTG_BREAK VALUES (@N,4,'Rest 3','04:30','04:45',62,1);
GO

/* ============================================================
   10. PERMISSIONS untuk SQL Agent service account
   ============================================================ */

GRANT EXECUTE ON dbo.SP_WTG_Tick      TO [NT SERVICE\SQLSERVERAGENT];
GRANT EXECUTE ON dbo.SP_WTG_OT_Open   TO [NT SERVICE\SQLSERVERAGENT];
GRANT EXECUTE ON dbo.SP_WTG_OT_Close  TO [NT SERVICE\SQLSERVERAGENT];
GRANT EXECUTE ON dbo.fn_WTG_CleanSeconds TO [NT SERVICE\SQLSERVERAGENT];
GRANT EXECUTE ON dbo.fn_WTG_OTSeconds    TO [NT SERVICE\SQLSERVERAGENT];
GRANT EXECUTE ON dbo.fn_WTG_IsInBreak    TO [NT SERVICE\SQLSERVERAGENT];
GRANT SELECT  ON dbo.TB_WTG_SHIFT        TO [NT SERVICE\SQLSERVERAGENT];
GRANT SELECT  ON dbo.TB_WTG_BREAK        TO [NT SERVICE\SQLSERVERAGENT];
GRANT SELECT  ON dbo.TB_WTG_OVERTIME     TO [NT SERVICE\SQLSERVERAGENT];
GRANT SELECT, INSERT, UPDATE ON dbo.TB_WTG_REG TO [NT SERVICE\SQLSERVERAGENT];
GRANT SELECT  ON dbo.V_WTG_STATUS        TO [NT SERVICE\SQLSERVERAGENT];
GO

/* ============================================================
   SELESAI. Verifikasi:
   --> SELECT * FROM V_WTG_STATUS
   --> SELECT * FROM TB_WTG_REG WHERE LINENAME = 'ADAPTIVE'
   --> EXEC dbo.fn_WTG_CleanSeconds 'ADAPTIVE', GETDATE()
   Buka OT  : EXEC SP_WTG_OT_Open  'ADAPTIVE', 'alasan OT'
   Tutup OT : EXEC SP_WTG_OT_Close 'ADAPTIVE'
   ============================================================ */
PRINT '';
PRINT '=== WTG v2 install selesai ===';
PRINT 'Query: SELECT * FROM V_WTG_STATUS';
GO
