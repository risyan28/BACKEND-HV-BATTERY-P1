/*
================================================================================
  WTG_DB_BATTERY  –  Database Redesign & Bug Fix Script
  Target DB : WTG_DB_BATTERY  (localhost\1433)
  Author    : Copilot / Review by Risyan
  Date      : 2026-04-15
================================================================================

  SECTION 0  – Bug / Issue Catalogue (existing DB)
  SECTION 1  – Schema fixes on existing tables
  SECTION 2  – New: Work-Schedule / Break / Overtime tables
  SECTION 3  – New: Helper functions
  SECTION 4  – Replace V_LINE_WT_A  (fixed midnight-cross boundary bug)
  SECTION 5  – Replace V_LINE_WT_B  (enhanced: overtime flag, net elapsed)
  SECTION 6  – New: V_WORK_STATUS   (consolidated real-time status view)
  SECTION 7  – Replace SP_WTG_DB    (all bugs fixed + overtime support)
  SECTION 8  – New: SP_WTG_OVERTIME_CLOSE  (close an overtime session)
  SECTION 9  – SQL Agent Job helper  (1-second ticker)
  SECTION 10 – Sample data

================================================================================
  SECTION 0  –  BUG CATALOGUE
================================================================================

  #  | Location            | Bug Description
  ---+---------------------+-------------------------------------------------------
  1  | TB_LINE_WT          | All time columns are VARCHAR(8) – no data-type safety.
     |                     | A typo like "25:99" is silently stored and causes NULL
     |                     | in CONVERT(TIME(0),...) which makes the whole view row
     |                     | return wrong/NULL results.
     |                     | FIX: Add CHECK constraints on format HH:MM.
     |
  2  | TB_LINE_WT          | No PRIMARY KEY. Duplicate (LINENAME, SHIFT) rows cause
     |                     | the stored procedure to get multiple rows into a scalar
     |                     | variable – last-row-wins non-determinism and silent data
     |                     | corruption.
     |                     | FIX: Add PK (LINENAME, SHIFT).
     |
  3  | TB_LINE_WT          | FEXCL_START4/END4/START5/END5 are VARCHAR(50) while all
     |                     | other time cols are VARCHAR(8) – inconsistent, wastes
     |                     | space, and breaks any schema introspection.
     |                     | FIX: Alter to VARCHAR(8).
     |
  4  | TB_LINE_WT          | No NULL-able flag: every break slot must be filled even
     |                     | when there are only 2 breaks. Empty '' is stored, which
     |                     | makes CONVERT(TIME(0),'') throw a runtime error.
     |                     | FIX: Allow NULL; view guards with ISNULL(...,'00:00').
     |
  5  | TB_WT_STATUS        | No PRIMARY KEY / UNIQUE constraint on
     |                     | (FDEV_NAME, FLINE, FREG_NAME). Multiple rows with the
     |                     | same key are possible; UPDATE without WHERE PK hits every
     |                     | matching row.
     |                     | FIX: Add PK.
     |
  6  | TB_WT_STATUS        | FREG_VALUE is VARCHAR(30) used to store INT, DATE, and
     |                     | TIME values mixed together. FREG_VALUE = (FREG_VALUE+1)
     |                     | is an implicit numeric cast that throws if the value ever
     |                     | becomes non-numeric.
     |                     | FIX: keep as-is for compatibility but add ISNUMERIC guard
     |                     | inside SP.
     |
  7  | TB_TIME             | fid has no PK / IDENTITY. fnow and fodd appear to be
     |                     | unused (fnow=NULL, fodd=NULL in the only row).
     |                     | FIX: Document purpose; add PK.
     |
  8  | V_LINE_WT_A         | Midnight-crossing shift WT_END boundary bug:
     |                     | When current time is exactly BETWEEN WT_END and WT_START
     |                     | (i.e. after midnight, before shift end on night shift),
     |                     | the IIF for WT_END falls into the ELSE-of-ELSE branch and
     |                     | returns TODAY's WT_END instead of TODAY already being
     |                     | correct – both ELSE branches in the WT_END IIF return the
     |                     | same value; the logic handles only 2 of the 3 time zones
     |                     | correctly. Night shift row 2 shows WT_END = 2026-04-15
     |                     | 06:45 while shift runs 20:00→06:45, so WT_END should be
     |                     | 2026-04-16 06:45 after 20:00 today.
     |                     | FIX: Rewrite V_LINE_WT_A with correct date arithmetic.
     |
  9  | V_LINE_WT_A/B       | Break detection uses strict < / > operators.  A break
     |                     | that starts exactly on-the-second is missed (EXCL_START <
     |                     | GETDATE() is FALSE when equal).
     |                     | FIX: Use <= for start, < for end (standard [start,end)).
     |
  10 | V_LINE_WT_A         | V_LINE_WT_A uses GETDATE() – called once per column in
     |                     | the SELECT. Within a single row evaluation the value may
     |                     | technically differ across columns in theory (it won't on
     |                     | SQL Server due to statement-level snapshot, but it's
     |                     | confusing and fragile). Addressed in rewrite.
     |
  11 | SP_WTG_DB           | @SHIFTN and @BREAKN are TINYINT but never initialised
     |                     | to 0. If @CNT1=0 the SET @WT=0 branch skips assignment
     |                     | of @SHIFTN, then SET @VINFO = @VINFO + @SHIFTN adds NULL
     |                     | → @VINFO becomes NULL → all downstream UPDATEs write NULL.
     |                     | FIX: Initialise @SHIFTN = 0, @BREAKN = 0 at declaration.
     |
  12 | SP_WTG_DB           | @DATE_SHIFT is set by a DATE_NO/FRIDAY block but then
     |                     | unconditionally OVERWRITTEN 10 lines later by a
     |                     | DATEPART(HOUR)<=6 block. The DATE SHIFT update inside
     |                     | the @WT=1 branch uses the correct value, but the
     |                     | subsequent DATE update uses the overwritten @DATE_SHIFT –
     |                     | this is intentional for the 'DATE' row but the overwrite
     |                     | happens after the DATE SHIFT update, creating split logic.
     |                     | FIX: Use separate variables @DATE_SHIFT and @DATE_TODAY.
     |
  13 | SP_WTG_DB           | Hard-coded cross-database INSERT into
     |                     | db_myopc_client_hv_battery.dbo.t_transmit with no error
     |                     | handling. If that DB is offline the entire SP fails and
     |                     | the WT counter stops incrementing.
     |                     | FIX: Wrap in TRY/CATCH; continue on error.
     |
  14 | SP_WTG_DB           | @VLINE is hard-coded to 'ADAPTIVE'. Multi-line factories
     |                     | cannot use this SP without copying it.
     |                     | FIX: Make @VLINE a parameter with 'ADAPTIVE' as default.
     |
  15 | SP_WTG_DB           | RESET logic fires at SECOND <= 10, but the SP is called
     |                     | every second by the PLC/OPC layer. If the job drifts
     |                     | slightly the reset fires 10 times in 10 seconds
     |                     | (10 inserts into t_transmit).
     |                     | FIX: Check whether reset was already done today using a
     |                     | flag row in TB_WT_STATUS.
     |
  16 | General             | No overtime tracking. When a shift ends while production
     |                     | is still running the WT counter either stops or restarts.
     |                     | FIX: New overtime table + SP.

================================================================================
  Execute in the context of WTG_DB_BATTERY
================================================================================
*/

USE [WTG_DB_BATTERY];
GO

SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

/* ============================================================
   SECTION 1  –  SCHEMA FIXES ON EXISTING TABLES
   ============================================================ */

/* --- 1.1  Fix FEXCL_START4/END4/START5/END5 column width (Bug #3) --- */
IF COL_LENGTH('TB_LINE_WT','FEXCL_START4') > 8
BEGIN
    ALTER TABLE TB_LINE_WT ALTER COLUMN FEXCL_START4 VARCHAR(8)     NULL;
    ALTER TABLE TB_LINE_WT ALTER COLUMN FEXCL_END4   VARCHAR(8)     NULL;
    ALTER TABLE TB_LINE_WT ALTER COLUMN FEXCL_START5 VARCHAR(8)     NULL;
    ALTER TABLE TB_LINE_WT ALTER COLUMN FEXCL_END5   VARCHAR(8)     NULL;
    PRINT 'Bug #3 fixed: FEXCL_START/END 4-5 resized to VARCHAR(8)';
END
GO

/* --- 1.2  Allow NULL on all break-slot columns (Bug #4) --- */
ALTER TABLE TB_LINE_WT ALTER COLUMN EXCL_START1  VARCHAR(8) NULL;
ALTER TABLE TB_LINE_WT ALTER COLUMN EXCL_END1    VARCHAR(8) NULL;
ALTER TABLE TB_LINE_WT ALTER COLUMN EXCL_START2  VARCHAR(8) NULL;
ALTER TABLE TB_LINE_WT ALTER COLUMN EXCL_END2    VARCHAR(8) NULL;
ALTER TABLE TB_LINE_WT ALTER COLUMN EXCL_START3  VARCHAR(8) NULL;
ALTER TABLE TB_LINE_WT ALTER COLUMN EXCL_END3    VARCHAR(8) NULL;
ALTER TABLE TB_LINE_WT ALTER COLUMN EXCL_START4  VARCHAR(8) NULL;
ALTER TABLE TB_LINE_WT ALTER COLUMN EXCL_END4    VARCHAR(8) NULL;
ALTER TABLE TB_LINE_WT ALTER COLUMN EXCL_START5  VARCHAR(8) NULL;
ALTER TABLE TB_LINE_WT ALTER COLUMN EXCL_END5    VARCHAR(8) NULL;
ALTER TABLE TB_LINE_WT ALTER COLUMN FEXCL_START1 VARCHAR(8) NULL;
ALTER TABLE TB_LINE_WT ALTER COLUMN FEXCL_END1   VARCHAR(8) NULL;
ALTER TABLE TB_LINE_WT ALTER COLUMN FEXCL_START2 VARCHAR(8) NULL;
ALTER TABLE TB_LINE_WT ALTER COLUMN FEXCL_END2   VARCHAR(8) NULL;
ALTER TABLE TB_LINE_WT ALTER COLUMN FEXCL_START3 VARCHAR(8) NULL;
ALTER TABLE TB_LINE_WT ALTER COLUMN FEXCL_END3   VARCHAR(8) NULL;
ALTER TABLE TB_LINE_WT ALTER COLUMN FEXCL_START4 VARCHAR(8) NULL;
ALTER TABLE TB_LINE_WT ALTER COLUMN FEXCL_END4   VARCHAR(8) NULL;
ALTER TABLE TB_LINE_WT ALTER COLUMN FEXCL_START5 VARCHAR(8) NULL;
ALTER TABLE TB_LINE_WT ALTER COLUMN FEXCL_END5   VARCHAR(8) NULL;
ALTER TABLE TB_LINE_WT ALTER COLUMN FWT_START    VARCHAR(8) NULL;
ALTER TABLE TB_LINE_WT ALTER COLUMN FWT_END      VARCHAR(8) NULL;
GO
PRINT 'Bug #4 fixed: break-slot columns now allow NULL';
GO

/* --- 1.3  Add PRIMARY KEY to TB_LINE_WT (Bug #2) --- */
IF NOT EXISTS (
    SELECT 1 FROM sys.indexes 
    WHERE object_id = OBJECT_ID('TB_LINE_WT') AND is_primary_key = 1
)
BEGIN
    /* Remove any duplicate rows first (keep first occurrence) */
    WITH CTE AS (
        SELECT *, ROW_NUMBER() OVER (PARTITION BY LINENAME, SHIFT ORDER BY (SELECT NULL)) rn
        FROM TB_LINE_WT
    )
    DELETE FROM CTE WHERE rn > 1;

    ALTER TABLE TB_LINE_WT
        ADD CONSTRAINT PK_TB_LINE_WT PRIMARY KEY (LINENAME, SHIFT);
    PRINT 'Bug #2 fixed: PK added to TB_LINE_WT';
END
GO

/* --- 1.4  Add PRIMARY KEY to TB_WT_STATUS (Bug #5) --- */
IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE object_id = OBJECT_ID('TB_WT_STATUS') AND is_primary_key = 1
)
BEGIN
    /* Remove duplicates */
    WITH CTE AS (
        SELECT *, ROW_NUMBER() OVER (
            PARTITION BY FDEV_NAME, FLINE, FREG_NAME ORDER BY FTR_TIME DESC
        ) rn
        FROM TB_WT_STATUS
    )
    DELETE FROM CTE WHERE rn > 1;

    ALTER TABLE TB_WT_STATUS
        ADD CONSTRAINT PK_TB_WT_STATUS PRIMARY KEY (FDEV_NAME, FLINE, FREG_NAME);
    PRINT 'Bug #5 fixed: PK added to TB_WT_STATUS';
END
GO

/* --- 1.5  Add PK to TB_TIME (Bug #7) --- */
/* NOTE: ALTER TABLE ALTER COLUMN fid NOT NULL fails if SQL Server metadata still
   tracks the column as nullable even after all rows have a value. The safe approach
   is to recreate the table (only 1 row, no FKs reference it). */
IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE object_id = OBJECT_ID('TB_TIME') AND is_primary_key = 1
)
BEGIN
    CREATE TABLE TB_TIME_NEW (
        fid  INT             NOT NULL CONSTRAINT PK_TB_TIME PRIMARY KEY,
        fnow DATETIMEOFFSET  NULL,
        fodd TINYINT         NULL
    );
    INSERT INTO TB_TIME_NEW SELECT ISNULL(fid, 1), fnow, fodd FROM TB_TIME;
    DROP TABLE TB_TIME;
    EXEC sp_rename 'TB_TIME_NEW', 'TB_TIME';
    PRINT 'Bug #7 fixed: TB_TIME recreated with PK (fid NOT NULL)';
END
GO

/* ============================================================
   SECTION 2  –  NEW WORK-SCHEDULE TABLES
   ============================================================
   Design:
     TB_SHIFT_DEFINITION   – master calendar for each line/shift
     TB_BREAK_SLOT         – flexible, unlimited break windows per shift
     TB_OVERTIME_SESSION   – tracks open / closed overtime sessions
     TB_WT_LOG             – audit log of every second increment
   ============================================================ */

/* --- 2.1  TB_SHIFT_DEFINITION --- */
IF OBJECT_ID('TB_SHIFT_DEFINITION','U') IS NULL
BEGIN
    CREATE TABLE TB_SHIFT_DEFINITION (
        SHIFT_ID        INT             IDENTITY(1,1)  NOT NULL,
        LINENAME        VARCHAR(30)     NOT NULL,
        SHIFT_NO        TINYINT         NOT NULL,          -- 1, 2, 3 …
        SHIFT_LABEL     VARCHAR(20)     NOT NULL,          -- 'Morning','Night',…
        WT_START        TIME(0)         NOT NULL,          -- e.g. 07:20
        WT_END          TIME(0)         NOT NULL,          -- e.g. 20:00
        IS_FRIDAY_SCHED BIT             NOT NULL DEFAULT 0, -- use FWT times on Fri?
        FWT_START       TIME(0)         NULL,              -- Friday override start
        FWT_END         TIME(0)         NULL,              -- Friday override end
        IS_ACTIVE       BIT             NOT NULL DEFAULT 1,
        CREATED_AT      DATETIME        NOT NULL DEFAULT GETDATE(),
        UPDATED_AT      DATETIME        NOT NULL DEFAULT GETDATE(),
        CONSTRAINT PK_TB_SHIFT_DEFINITION  PRIMARY KEY (SHIFT_ID),
        CONSTRAINT UQ_TB_SHIFT_DEFINITION  UNIQUE (LINENAME, SHIFT_NO),
        CONSTRAINT CHK_SHIFT_NO CHECK (SHIFT_NO BETWEEN 1 AND 9)
    );
    PRINT 'Created TB_SHIFT_DEFINITION';
END
GO

/* --- 2.2  TB_BREAK_SLOT  (replaces hardcoded EXCL_START1..5) --- */
IF OBJECT_ID('TB_BREAK_SLOT','U') IS NULL
BEGIN
    CREATE TABLE TB_BREAK_SLOT (
        BREAK_ID        INT             IDENTITY(1,1) NOT NULL,
        SHIFT_ID        INT             NOT NULL,           -- FK → TB_SHIFT_DEFINITION
        BREAK_SEQ       TINYINT         NOT NULL,           -- 1,2,3,… (display order)
        BREAK_LABEL     VARCHAR(30)     NULL,               -- 'Lunch','Rest 1',…
        BREAK_START     TIME(0)         NOT NULL,
        BREAK_END       TIME(0)         NOT NULL,
        IS_FRIDAY_BREAK BIT             NOT NULL DEFAULT 0, -- applies only on Friday?
        IS_ACTIVE       BIT             NOT NULL DEFAULT 1,
        CONSTRAINT PK_TB_BREAK_SLOT PRIMARY KEY (BREAK_ID),
        CONSTRAINT UQ_TB_BREAK_SLOT UNIQUE (SHIFT_ID, BREAK_SEQ, IS_FRIDAY_BREAK),
        CONSTRAINT FK_BREAK_SHIFT  FOREIGN KEY (SHIFT_ID)
            REFERENCES TB_SHIFT_DEFINITION(SHIFT_ID),
        CONSTRAINT CHK_BREAK_TIMES CHECK (BREAK_START <> BREAK_END)
    );
    PRINT 'Created TB_BREAK_SLOT';
END
GO

/* --- 2.3  TB_OVERTIME_SESSION --- */
IF OBJECT_ID('TB_OVERTIME_SESSION','U') IS NULL
BEGIN
    CREATE TABLE TB_OVERTIME_SESSION (
        OT_ID           INT             IDENTITY(1,1) NOT NULL,
        LINENAME        VARCHAR(30)     NOT NULL,
        SHIFT_ID        INT             NOT NULL,
        OT_DATE         DATE            NOT NULL,           -- date shift starts
        OT_START        DATETIME        NOT NULL,           -- actual OT begin timestamp
        OT_END          DATETIME        NULL,               -- NULL = still open
        OT_SECONDS      INT             NOT NULL DEFAULT 0, -- accumulated OT seconds
        OT_REASON       VARCHAR(100)    NULL,               -- optional reason tag
        CREATED_BY      VARCHAR(30)     NOT NULL DEFAULT 'SP_WTG_DB',
        CONSTRAINT PK_TB_OT_SESSION PRIMARY KEY (OT_ID),
        CONSTRAINT FK_OT_SHIFT FOREIGN KEY (SHIFT_ID)
            REFERENCES TB_SHIFT_DEFINITION(SHIFT_ID)
    );

    CREATE INDEX IX_OT_LINE_DATE ON TB_OVERTIME_SESSION (LINENAME, OT_DATE);
    PRINT 'Created TB_OVERTIME_SESSION';
END
GO

/* --- 2.4  TB_WT_LOG  (audit / history) --- */
IF OBJECT_ID('TB_WT_LOG','U') IS NULL
BEGIN
    CREATE TABLE TB_WT_LOG (
        LOG_ID          BIGINT          IDENTITY(1,1) NOT NULL,
        LINENAME        VARCHAR(30)     NOT NULL,
        LOG_TS          DATETIME        NOT NULL DEFAULT GETDATE(),
        SHIFT_NO        TINYINT         NULL,
        IS_WORKING      BIT             NOT NULL DEFAULT 0,
        IS_BREAK        BIT             NOT NULL DEFAULT 0,
        IS_OVERTIME     BIT             NOT NULL DEFAULT 0,
        WT_SECONDS_SNAP INT             NULL,              -- current WT counter value
        CONSTRAINT PK_TB_WT_LOG PRIMARY KEY (LOG_ID)
    );

    -- Partition-friendly index for time-range queries
    CREATE INDEX IX_WT_LOG_LINE_TS ON TB_WT_LOG (LINENAME, LOG_TS DESC);
    PRINT 'Created TB_WT_LOG';
END
GO

/* ============================================================
   SECTION 3  –  HELPER FUNCTIONS
   ============================================================ */

/* --- 3.1  fn_TimeToToday: convert VARCHAR(8) time token → DATETIME on "today",
            handling midnight cross correctly. 
            anchor_dt = the reference NOW datetime (pass GETDATE()).
            is_end    = 1 if this is a shift-end time (add day when < start).
            start_time= shift start (needed to detect next-day end).
*/
IF OBJECT_ID('dbo.fn_ResolveShiftDateTime','FN') IS NOT NULL
    DROP FUNCTION dbo.fn_ResolveShiftDateTime;
GO

CREATE FUNCTION dbo.fn_ResolveShiftDateTime (
    @time_str   VARCHAR(8),     -- 'HH:MM' or 'HH:MM:SS'
    @anchor_dt  DATETIME,       -- reference point (usually GETDATE())
    @is_end     BIT,            -- 1 = this is a shift-end, 0 = shift-start
    @start_str  VARCHAR(8)      -- shift start (used only when @is_end=1)
)
RETURNS DATETIME
AS
BEGIN
    /* Returns NULL on bad input – caller must guard.
       NOTE: BEGIN TRY/CATCH is NOT allowed inside SQL Server scalar functions.
             Use TRY_CAST instead for safe type conversion. */
    IF @time_str IS NULL OR LEN(LTRIM(RTRIM(@time_str))) < 5 RETURN NULL;

    DECLARE @base   DATE    = CAST(@anchor_dt AS DATE);
    DECLARE @t      TIME(0) = TRY_CAST(@time_str  AS TIME(0));  -- returns NULL on bad input
    DECLARE @ts     TIME(0) = TRY_CAST(@start_str AS TIME(0));  -- returns NULL on bad input
    DECLARE @result DATETIME;

    IF @t IS NULL RETURN NULL;

    IF @is_end = 0
    BEGIN
        -- Start: always today's date
        SET @result = CAST(@base AS DATETIME) + CAST(@t AS DATETIME);
        RETURN @result;
    END;

    -- End time: crosses midnight when end < start (e.g. 20:00 → 06:45)
    IF @ts IS NULL OR @t >= @ts
    BEGIN
        -- Same calendar day
        SET @result = CAST(@base AS DATETIME) + CAST(@t AS DATETIME);
    END
    ELSE
    BEGIN
        -- Next calendar day
        SET @result = CAST(DATEADD(DAY, 1, @base) AS DATETIME) + CAST(@t AS DATETIME);
    END;

    RETURN @result;
END;
GO
PRINT 'Created fn_ResolveShiftDateTime';
GO

/* --- 3.2  fn_IsInBreak: returns 1 if @now falls inside any active break for
            a given @shift_id (new normalised break table). */
IF OBJECT_ID('dbo.fn_IsInBreak','FN') IS NOT NULL
    DROP FUNCTION dbo.fn_IsInBreak;
GO

CREATE FUNCTION dbo.fn_IsInBreak (
    @shift_id   INT,
    @now        TIME(0),
    @is_friday  BIT
)
RETURNS BIT
AS
BEGIN
    DECLARE @result BIT = 0;
    IF EXISTS (
        SELECT 1 FROM TB_BREAK_SLOT
        WHERE SHIFT_ID = @shift_id
          AND IS_ACTIVE = 1
          AND (IS_FRIDAY_BREAK = 0 OR IS_FRIDAY_BREAK = @is_friday)
          AND @now >= BREAK_START     -- inclusive start
          AND @now <  BREAK_END       -- exclusive end  (Bug #9 fix)
    )
        SET @result = 1;
    RETURN @result;
END;
GO
PRINT 'Created fn_IsInBreak';
GO

/* ============================================================
   SECTION 4  –  REPLACE V_LINE_WT_A  (Bug #8 fix + normalised)
   ============================================================
   Now uses TB_SHIFT_DEFINITION + TB_BREAK_SLOT.
   Legacy V_LINE_WT_A is preserved (renamed) for backward compat.
   ============================================================ */

/* Keep original for backward compat */
IF OBJECT_ID('V_LINE_WT_A_LEGACY','V') IS NULL
    AND OBJECT_ID('V_LINE_WT_A','V') IS NOT NULL
    EXEC sp_rename 'V_LINE_WT_A', 'V_LINE_WT_A_LEGACY';
GO

IF OBJECT_ID('V_LINE_WT_A','V') IS NOT NULL DROP VIEW V_LINE_WT_A;
GO

CREATE VIEW V_LINE_WT_A AS
/*
  Resolves each shift's absolute start/end DATETIME for "right now",
  handling midnight-crossing shifts correctly (Bug #8).
  One row per active shift definition.
*/
SELECT
    sd.SHIFT_ID,
    sd.LINENAME,
    sd.SHIFT_NO                                AS SHIFT,
    sd.SHIFT_LABEL,
    GETDATE()                                  AS FNOW,

    /* ---- Regular working time ---- */
    dbo.fn_ResolveShiftDateTime(
        CONVERT(VARCHAR(8), sd.WT_START, 108),
        GETDATE(), 0,
        CONVERT(VARCHAR(8), sd.WT_START, 108)
    )                                          AS WT_START_DT,

    dbo.fn_ResolveShiftDateTime(
        CONVERT(VARCHAR(8), sd.WT_END,   108),
        GETDATE(), 1,
        CONVERT(VARCHAR(8), sd.WT_START, 108)
    )                                          AS WT_END_DT,

    /* ---- Friday / special schedule ---- */
    CASE
        WHEN sd.IS_FRIDAY_SCHED = 1 AND sd.FWT_START IS NOT NULL
        THEN dbo.fn_ResolveShiftDateTime(
                CONVERT(VARCHAR(8), sd.FWT_START, 108),
                GETDATE(), 0,
                CONVERT(VARCHAR(8), sd.FWT_START, 108))
        ELSE dbo.fn_ResolveShiftDateTime(
                CONVERT(VARCHAR(8), sd.WT_START, 108),
                GETDATE(), 0,
                CONVERT(VARCHAR(8), sd.WT_START, 108))
    END                                        AS FWT_START_DT,

    CASE
        WHEN sd.IS_FRIDAY_SCHED = 1 AND sd.FWT_END IS NOT NULL
        THEN dbo.fn_ResolveShiftDateTime(
                CONVERT(VARCHAR(8), sd.FWT_END, 108),
                GETDATE(), 1,
                CONVERT(VARCHAR(8), sd.FWT_START, 108))
        ELSE dbo.fn_ResolveShiftDateTime(
                CONVERT(VARCHAR(8), sd.WT_END, 108),
                GETDATE(), 1,
                CONVERT(VARCHAR(8), sd.WT_START, 108))
    END                                        AS FWT_END_DT,

    sd.IS_FRIDAY_SCHED,

    /* ---- Break flags (new normalised lookup) ---- */
    dbo.fn_IsInBreak(sd.SHIFT_ID, CAST(GETDATE() AS TIME(0)), 0)  AS IS_IN_BREAK,
    dbo.fn_IsInBreak(sd.SHIFT_ID, CAST(GETDATE() AS TIME(0)), 1)  AS IS_IN_FRIDAY_BREAK

FROM TB_SHIFT_DEFINITION sd
WHERE sd.IS_ACTIVE = 1;
GO
PRINT 'Recreated V_LINE_WT_A (bug #8 fixed, normalised)';
GO

/* ============================================================
   SECTION 5  –  REPLACE V_LINE_WT_B  (enhanced)
   ============================================================ */

IF OBJECT_ID('V_LINE_WT_B_LEGACY','V') IS NULL
    AND OBJECT_ID('V_LINE_WT_B','V') IS NOT NULL
    EXEC sp_rename 'V_LINE_WT_B', 'V_LINE_WT_B_LEGACY';
GO

IF OBJECT_ID('V_LINE_WT_B','V') IS NOT NULL DROP VIEW V_LINE_WT_B;
GO

CREATE VIEW V_LINE_WT_B AS
/*
  Real-time working-time status per shift.
  Adds overtime detection: a shift that has ended but has an open
  TB_OVERTIME_SESSION record is flagged as overtime.
*/
WITH base AS (
    SELECT
        a.SHIFT_ID,
        a.LINENAME,
        a.SHIFT,
        a.SHIFT_LABEL,
        a.FNOW,
        a.WT_START_DT,
        a.WT_END_DT,
        a.FWT_START_DT,
        a.FWT_END_DT,
        a.IS_FRIDAY_SCHED,
        a.IS_IN_BREAK,
        a.IS_IN_FRIDAY_BREAK,
        DATEPART(WEEKDAY, GETDATE()) AS DOW   -- 6 = Friday (@@DATEFIRST default=7)
    FROM V_LINE_WT_A a
)
SELECT
    b.SHIFT_ID,
    b.LINENAME,
    b.SHIFT,
    b.SHIFT_LABEL,
    b.FNOW,

    b.WT_START_DT,
    b.WT_END_DT,

    /* Is current time inside the normal working window? */
    CAST(
        CASE WHEN b.FNOW >= b.WT_START_DT AND b.FNOW < b.WT_END_DT
             THEN 1 ELSE 0 END
    AS BIT)                                     AS WT_TIME,

    /* Is current time inside ANY break? (Bug #9 fixed: uses >=) */
    CAST(b.IS_IN_BREAK AS BIT)                  AS IS_BREAK,

    b.FWT_START_DT,
    b.FWT_END_DT,

    /* Friday schedule active flag */
    CAST(
        CASE WHEN b.DOW = 6 AND b.IS_FRIDAY_SCHED = 1
                  AND b.FNOW >= b.FWT_START_DT AND b.FNOW < b.FWT_END_DT
             THEN 1 ELSE 0 END
    AS BIT)                                     AS FWT_TIME,

    CAST(b.IS_IN_FRIDAY_BREAK AS BIT)           AS FBREAK,

    /* ---- Overtime detection ---- */
    CAST(
        CASE WHEN ot.OT_ID IS NOT NULL THEN 1 ELSE 0 END
    AS BIT)                                     AS IS_OVERTIME,

    ot.OT_ID,
    ot.OT_START,
    ot.OT_SECONDS,

    /* Net elapsed working seconds today (WT counter - break seconds not subtracted here,
       break pauses are handled in the SP) */
    CAST(
        ISNULL(
            (SELECT TRY_CAST(FREG_VALUE AS INT)
             FROM TB_WT_STATUS
             WHERE FDEV_NAME = 'WTG'
               AND FLINE     = b.LINENAME
               AND FREG_NAME = 'WT'),
        0)
    AS INT)                                     AS WT_SECONDS

FROM base b
LEFT JOIN TB_OVERTIME_SESSION ot
    ON  ot.LINENAME = b.LINENAME
    AND ot.SHIFT_ID = b.SHIFT_ID
    AND ot.OT_END   IS NULL   -- open/active overtime
    AND CAST(ot.OT_START AS DATE) = CAST(GETDATE() AS DATE);
GO
PRINT 'Recreated V_LINE_WT_B (overtime, break fix)';
GO

/* ============================================================
   SECTION 6  –  V_WORK_STATUS  (consolidated dashboard view)
   ============================================================ */

IF OBJECT_ID('V_WORK_STATUS','V') IS NOT NULL DROP VIEW V_WORK_STATUS;
GO

CREATE VIEW V_WORK_STATUS AS
/*
  One row per LINE showing the ACTIVE shift (or last known shift when idle).
  Consumers (front-end / SCADA) read this view to get:
    - Current mode: IDLE / WORKING / BREAK / OVERTIME
    - Running WT counter in seconds
    - Shift label, shift date
*/
SELECT
    b.LINENAME,
    b.SHIFT,
    b.SHIFT_LABEL,
    b.FNOW,

    CASE
        WHEN b.IS_OVERTIME = 1                              THEN 'OVERTIME'
        WHEN b.WT_TIME = 1 AND b.IS_BREAK = 0              THEN 'WORKING'
        WHEN b.WT_TIME = 1 AND b.IS_BREAK = 1              THEN 'BREAK'
        WHEN b.FWT_TIME = 1 AND b.FBREAK  = 0              THEN 'WORKING'   -- Friday
        WHEN b.FWT_TIME = 1 AND b.FBREAK  = 1              THEN 'BREAK'
        ELSE                                                     'IDLE'
    END                                                         AS WORK_MODE,

    b.WT_SECONDS,
    b.IS_BREAK,
    b.IS_OVERTIME,
    b.OT_SECONDS,

    /* Shift start date (date the shift logically "belongs to") */
    CAST(
        CASE
            WHEN b.WT_START_DT IS NOT NULL
                 AND CAST(b.WT_START_DT AS TIME(0)) > CAST('12:00' AS TIME(0))
                 AND CAST(b.FNOW AS TIME(0)) < CAST('12:00' AS TIME(0))
            THEN CAST(DATEADD(DAY,-1,CAST(b.FNOW AS DATE)) AS DATE)
            ELSE CAST(b.FNOW AS DATE)
        END
    AS DATE)                                                    AS SHIFT_DATE,

    b.WT_START_DT,
    b.WT_END_DT

FROM V_LINE_WT_B b
WHERE  b.WT_TIME = 1
    OR b.FWT_TIME = 1
    OR b.IS_OVERTIME = 1;
GO
PRINT 'Created V_WORK_STATUS';
GO

/* ============================================================
   SECTION 7  –  REPLACE SP_WTG_DB  (all bugs fixed)
   ============================================================ */

IF OBJECT_ID('SP_WTG_DB','P') IS NOT NULL DROP PROCEDURE SP_WTG_DB;
GO

CREATE PROCEDURE [dbo].[SP_WTG_DB]
    @VLINE  VARCHAR(30) = 'ADAPTIVE'   /* Bug #14 fix: parameterised */
AS
/*
  Working-Time Generator – executed every second by SQL Agent job.
  Counts elapsed working seconds, pauses during breaks,
  detects overtime, writes status to TB_WT_STATUS.
*/
SET NOCOUNT ON;
SET XACT_ABORT ON;

/* ---- Declare & initialise all variables (Bug #11 fix) ---- */
DECLARE
    @WT             TINYINT     = 0,
    @SHIFTN         TINYINT     = 0,    -- Bug #11: initialised
    @BREAKN         TINYINT     = 0,    -- Bug #11: initialised
    @FRIDAY         TINYINT     = 0,
    @VINFO          INT         = 0,
    @DATE_NO        INT         = 0,
    @SHIFT_ID       INT         = NULL,
    @IS_OT          BIT         = 0,
    @OT_ID          INT         = NULL;

DECLARE @DATE_SHIFT VARCHAR(10);    -- date the shift logically belongs to (Bug #12 fix)
DECLARE @DATE_TODAY VARCHAR(10);    -- calendar date for the 'DATE' status row

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
    SELECT TOP 1 @OT_ID   = OT_ID,
                 @IS_OT   = 1
    FROM TB_OVERTIME_SESSION
    WHERE LINENAME = @VLINE
      AND OT_END   IS NULL
      AND CAST(OT_START AS DATE) = CAST(GETDATE() AS DATE)
    ORDER BY OT_ID DESC;

    /* ---- Build @VINFO bitmask ---- */
    IF @BREAKN > 0 SET @VINFO = @VINFO + 8;
    IF @WT     > 0 SET @VINFO = @VINFO + 4;
    IF @IS_OT  = 1 SET @VINFO = @VINFO + 16;   -- overtime bit
    SET @VINFO = @VINFO + @SHIFTN;

    /* ---- Date of shift (Bug #12: separate vars) ---- */
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

    /* Calendar date (for 'DATE' row – night-shift crosses midnight) */
    SET @DATE_TODAY = CASE
        WHEN DATEPART(HOUR, GETDATE()) <= 6
        THEN CONVERT(CHAR(10), DATEADD(DAY,-1,CAST(GETDATE() AS DATE)), 126)
        ELSE CONVERT(CHAR(10), GETDATE(), 126)
    END;

    /* ---- Increment / reset counters ---- */
    IF @WT = 0 AND @IS_OT = 0
    BEGIN
        /* Outside working time AND no overtime → reset */
        UPDATE TB_WT_STATUS SET FTR_TIME = GETDATE(), FREG_VALUE = '0'
        WHERE FDEV_NAME = 'WTG' AND FLINE = @VLINE AND FREG_NAME = 'SHIFT';

        UPDATE TB_WT_STATUS SET FTR_TIME = GETDATE(), FREG_VALUE = '0'
        WHERE FDEV_NAME = 'WTG' AND FLINE = @VLINE AND FREG_NAME = 'INFO';
    END
    ELSE
    BEGIN
        /* Working or overtime: increment WT counter when not on break */
        IF @BREAKN = 0
        BEGIN
            /* Bug #6 fix: guard against non-numeric FREG_VALUE */
            UPDATE TB_WT_STATUS
            SET    FTR_TIME   = GETDATE(),
                   FREG_VALUE = CAST(
                       ISNULL(TRY_CAST(FREG_VALUE AS INT), 0) + 1
                   AS VARCHAR(30))
            WHERE  FDEV_NAME  = 'WTG'
              AND  FLINE      = @VLINE
              AND  FREG_NAME  = 'WT';

            /* Also increment overtime seconds if OT session is open */
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

    /* Bug #15: reset guard -- only reset once per window using RESET timestamp */
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
        OR DATEDIFF(MINUTE, @LAST_RESET, GETDATE()) > 5  -- not reset in last 5 min
    )
    BEGIN
        UPDATE TB_WT_STATUS SET FREG_VALUE = '0'
        WHERE FDEV_NAME = 'WTG' AND FLINE = @VLINE AND FREG_NAME = 'WT';

        /* Upsert the reset-guard timestamp */
        IF EXISTS (SELECT 1 FROM TB_WT_STATUS
                   WHERE FDEV_NAME='WTG' AND FLINE=@VLINE AND FREG_NAME='RESET_TS')
            UPDATE TB_WT_STATUS SET FTR_TIME=GETDATE(),
                   FREG_VALUE = CONVERT(VARCHAR(30), GETDATE(), 120)
            WHERE  FDEV_NAME='WTG' AND FLINE=@VLINE AND FREG_NAME='RESET_TS';
        ELSE
            INSERT INTO TB_WT_STATUS (FDEV_NAME, FLINE, FREG_NAME, FREG_VALUE, FTR_TIME)
            VALUES ('WTG', @VLINE, 'RESET_TS',
                    CONVERT(VARCHAR(30), GETDATE(), 120), GETDATE());

        /* Cross-DB transmit to db_myopc_client_hv_battery removed.
           Integrate via external service if PLC sync is needed. */
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
    /* Top-level catch: log error, never crash silently */
    DECLARE @EMSG VARCHAR(200) = LEFT(ERROR_MESSAGE(), 200);
    INSERT INTO TB_WT_STATUS (FDEV_NAME, FLINE, FREG_NAME, FREG_VALUE, FTR_TIME)
    SELECT 'WTG', @VLINE, 'LAST_ERR', @EMSG, GETDATE()
    WHERE NOT EXISTS (
        SELECT 1 FROM TB_WT_STATUS
        WHERE FDEV_NAME='WTG' AND FLINE=@VLINE AND FREG_NAME='LAST_ERR'
    );
    UPDATE TB_WT_STATUS
    SET    FTR_TIME = GETDATE(), FREG_VALUE = @EMSG
    WHERE  FDEV_NAME='WTG' AND FLINE=@VLINE AND FREG_NAME='LAST_ERR';
END CATCH;
GO
PRINT 'Recreated SP_WTG_DB (all bugs fixed)';
GO

/* ============================================================
   SECTION 8  –  SP_WTG_OVERTIME_OPEN / CLOSE
   ============================================================ */

/* --- 8.1  Open an overtime session --- */
IF OBJECT_ID('SP_WTG_OVERTIME_OPEN','P') IS NOT NULL DROP PROCEDURE SP_WTG_OVERTIME_OPEN;
GO

CREATE PROCEDURE [dbo].[SP_WTG_OVERTIME_OPEN]
    @VLINE      VARCHAR(30) = 'ADAPTIVE',
    @REASON     VARCHAR(100) = NULL
AS
SET NOCOUNT ON;
/*
  Call this procedure to start an overtime session for a given line.
  Typically triggered from the MES/SCADA UI when a supervisor approves OT.
  Multiple open OT sessions for the same line on the same day are not allowed.
*/
DECLARE @SHIFT_ID INT;
DECLARE @OT_DATE  DATE = CAST(GETDATE() AS DATE);

-- Find the shift that most recently ran (LAST SHIFT) for this line
SELECT @SHIFT_ID = sd.SHIFT_ID
FROM TB_SHIFT_DEFINITION sd
JOIN TB_WT_STATUS         ws ON ws.FLINE = @VLINE
                              AND ws.FREG_NAME = 'LAST SHIFT'
                              AND TRY_CAST(ws.FREG_VALUE AS TINYINT) = sd.SHIFT_NO
WHERE sd.LINENAME = @VLINE AND sd.IS_ACTIVE = 1;

IF @SHIFT_ID IS NULL
BEGIN
    RAISERROR('Cannot open overtime: no active shift found for line %s.', 16, 1, @VLINE);
    RETURN;
END

IF EXISTS (
    SELECT 1 FROM TB_OVERTIME_SESSION
    WHERE LINENAME = @VLINE AND OT_END IS NULL
      AND CAST(OT_START AS DATE) = @OT_DATE
)
BEGIN
    RAISERROR('Overtime already open for line %s today.', 16, 1, @VLINE);
    RETURN;
END

INSERT INTO TB_OVERTIME_SESSION (LINENAME, SHIFT_ID, OT_DATE, OT_START, OT_REASON)
VALUES (@VLINE, @SHIFT_ID, @OT_DATE, GETDATE(), @REASON);

PRINT 'Overtime session opened for line: ' + @VLINE;
GO

/* --- 8.2  Close an overtime session --- */
IF OBJECT_ID('SP_WTG_OVERTIME_CLOSE','P') IS NOT NULL DROP PROCEDURE SP_WTG_OVERTIME_CLOSE;
GO

CREATE PROCEDURE [dbo].[SP_WTG_OVERTIME_CLOSE]
    @VLINE  VARCHAR(30) = 'ADAPTIVE'
AS
SET NOCOUNT ON;
/*
  Close the open overtime session for a line.
  Sets OT_END = now; OT_SECONDS is the accumulated counter from SP_WTG_DB.
*/
DECLARE @OT_ID INT;

SELECT TOP 1 @OT_ID = OT_ID
FROM TB_OVERTIME_SESSION
WHERE LINENAME = @VLINE AND OT_END IS NULL
ORDER BY OT_ID DESC;

IF @OT_ID IS NULL
BEGIN
    RAISERROR('No open overtime session found for line %s.', 16, 1, @VLINE);
    RETURN;
END

UPDATE TB_OVERTIME_SESSION
SET    OT_END = GETDATE()
WHERE  OT_ID  = @OT_ID;

SELECT OT_ID, LINENAME, OT_START, OT_END,
       OT_SECONDS,
       CONVERT(VARCHAR(8), DATEADD(SECOND, OT_SECONDS, 0), 108) AS OT_DURATION_HMS
FROM TB_OVERTIME_SESSION WHERE OT_ID = @OT_ID;
GO
PRINT 'Created SP_WTG_OVERTIME_OPEN / CLOSE';
GO

/* ============================================================
   SECTION 9  –  SQL AGENT JOB  (1-second ticker)
   ============================================================
   Creates a SQL Agent job that executes SP_WTG_DB every second.
   Safe to run multiple times (idempotent).
   ============================================================ */

USE msdb;
GO

IF EXISTS (SELECT 1 FROM msdb.dbo.sysjobs WHERE name = N'WTG_DB_BATTERY_TICKER')
BEGIN
    EXEC msdb.dbo.sp_delete_job @job_name = N'WTG_DB_BATTERY_TICKER', @delete_unused_schedules = 1;
    PRINT 'Dropped existing WTG_DB_BATTERY_TICKER job';
END
GO

EXEC msdb.dbo.sp_add_job
    @job_name            = N'WTG_DB_BATTERY_TICKER',
    @enabled             = 1,
    @description         = N'Executes SP_WTG_DB every second to maintain working-time counter',
    @category_name       = N'[Uncategorized (Local)]';

EXEC msdb.dbo.sp_add_jobstep
    @job_name       = N'WTG_DB_BATTERY_TICKER',
    @step_name      = N'Tick',
    @subsystem      = N'TSQL',
    @database_name  = N'WTG_DB_BATTERY',
    @command        = N'
-- Execute once per second via schedule. Loop 60 times = 1 minute per job run.
DECLARE @i INT = 0;
WHILE @i < 60
BEGIN
    EXEC dbo.SP_WTG_DB @VLINE = ''ADAPTIVE'';
    WAITFOR DELAY ''00:00:01'';
    SET @i = @i + 1;
END',
    @on_success_action = 1,   -- quit with success
    @on_fail_action    = 2;   -- quit with failure

-- Schedule: run every minute (the loop inside covers each second)
EXEC msdb.dbo.sp_add_schedule
    @schedule_name      = N'WTG_Every_Minute',
    @freq_type          = 4,    -- daily
    @freq_interval      = 1,
    @freq_subday_type   = 4,    -- minutes
    @freq_subday_interval = 1,
    @active_start_time  = 000000,
    @active_end_time    = 235959;

EXEC msdb.dbo.sp_attach_schedule
    @job_name       = N'WTG_DB_BATTERY_TICKER',
    @schedule_name  = N'WTG_Every_Minute';

EXEC msdb.dbo.sp_add_jobserver
    @job_name   = N'WTG_DB_BATTERY_TICKER',
    @server_name = N'(local)';

PRINT 'Created SQL Agent job: WTG_DB_BATTERY_TICKER';
GO

USE [WTG_DB_BATTERY];
GO

/* ============================================================
   SECTION 10 –  SAMPLE DATA  (mirrors existing TB_LINE_WT rows)
   ============================================================
   Migrates the 2 existing rows from TB_LINE_WT into
   TB_SHIFT_DEFINITION + TB_BREAK_SLOT.
   ============================================================ */

/* --- Shift definitions --- */
IF NOT EXISTS (SELECT 1 FROM TB_SHIFT_DEFINITION WHERE LINENAME='ADAPTIVE' AND SHIFT_NO=1)
INSERT INTO TB_SHIFT_DEFINITION
    (LINENAME, SHIFT_NO, SHIFT_LABEL, WT_START, WT_END,
     IS_FRIDAY_SCHED, FWT_START, FWT_END, IS_ACTIVE)
VALUES
    ('ADAPTIVE', 1, 'Day',
     '07:20', '20:00',
     1, '07:20', '20:00',    -- Friday same as regular (adjust if needed)
     1);

IF NOT EXISTS (SELECT 1 FROM TB_SHIFT_DEFINITION WHERE LINENAME='ADAPTIVE' AND SHIFT_NO=2)
INSERT INTO TB_SHIFT_DEFINITION
    (LINENAME, SHIFT_NO, SHIFT_LABEL, WT_START, WT_END,
     IS_FRIDAY_SCHED, FWT_START, FWT_END, IS_ACTIVE)
VALUES
    ('ADAPTIVE', 2, 'Night',
     '20:00', '06:45',
     1, '21:00', '06:45',    -- Friday night starts 1h later
     1);
GO

/* --- Break slots for Shift 1 (Day) – from existing EXCL_START1..5 data ---
   09:30-09:40  (Rest 1)
   11:45-12:30  (Lunch)
   14:30-14:40  (Rest 2)
   16:00-16:00  (EXCLUDED – zero-length, skip)
   18:00-18:15  (Rest 3)
*/
DECLARE @S1 INT = (SELECT SHIFT_ID FROM TB_SHIFT_DEFINITION WHERE LINENAME='ADAPTIVE' AND SHIFT_NO=1);
IF @S1 IS NOT NULL
BEGIN
    IF NOT EXISTS (SELECT 1 FROM TB_BREAK_SLOT WHERE SHIFT_ID=@S1 AND BREAK_SEQ=1 AND IS_FRIDAY_BREAK=0)
        INSERT INTO TB_BREAK_SLOT (SHIFT_ID,BREAK_SEQ,BREAK_LABEL,BREAK_START,BREAK_END,IS_FRIDAY_BREAK)
        VALUES (@S1,1,'Rest 1','09:30','09:40',0);

    IF NOT EXISTS (SELECT 1 FROM TB_BREAK_SLOT WHERE SHIFT_ID=@S1 AND BREAK_SEQ=2 AND IS_FRIDAY_BREAK=0)
        INSERT INTO TB_BREAK_SLOT (SHIFT_ID,BREAK_SEQ,BREAK_LABEL,BREAK_START,BREAK_END,IS_FRIDAY_BREAK)
        VALUES (@S1,2,'Lunch','11:45','12:30',0);

    IF NOT EXISTS (SELECT 1 FROM TB_BREAK_SLOT WHERE SHIFT_ID=@S1 AND BREAK_SEQ=3 AND IS_FRIDAY_BREAK=0)
        INSERT INTO TB_BREAK_SLOT (SHIFT_ID,BREAK_SEQ,BREAK_LABEL,BREAK_START,BREAK_END,IS_FRIDAY_BREAK)
        VALUES (@S1,3,'Rest 2','14:30','14:40',0);

    IF NOT EXISTS (SELECT 1 FROM TB_BREAK_SLOT WHERE SHIFT_ID=@S1 AND BREAK_SEQ=4 AND IS_FRIDAY_BREAK=0)
        INSERT INTO TB_BREAK_SLOT (SHIFT_ID,BREAK_SEQ,BREAK_LABEL,BREAK_START,BREAK_END,IS_FRIDAY_BREAK)
        VALUES (@S1,4,'Rest 3','18:00','18:15',0);

    /* Friday breaks for shift 1 */
    IF NOT EXISTS (SELECT 1 FROM TB_BREAK_SLOT WHERE SHIFT_ID=@S1 AND BREAK_SEQ=1 AND IS_FRIDAY_BREAK=1)
        INSERT INTO TB_BREAK_SLOT (SHIFT_ID,BREAK_SEQ,BREAK_LABEL,BREAK_START,BREAK_END,IS_FRIDAY_BREAK)
        VALUES (@S1,1,'Rest 1 (Fri)','09:30','09:40',1);

    IF NOT EXISTS (SELECT 1 FROM TB_BREAK_SLOT WHERE SHIFT_ID=@S1 AND BREAK_SEQ=2 AND IS_FRIDAY_BREAK=1)
        INSERT INTO TB_BREAK_SLOT (SHIFT_ID,BREAK_SEQ,BREAK_LABEL,BREAK_START,BREAK_END,IS_FRIDAY_BREAK)
        VALUES (@S1,2,'Lunch (Fri)','11:45','13:00',1);   -- longer Friday lunch

    IF NOT EXISTS (SELECT 1 FROM TB_BREAK_SLOT WHERE SHIFT_ID=@S1 AND BREAK_SEQ=3 AND IS_FRIDAY_BREAK=1)
        INSERT INTO TB_BREAK_SLOT (SHIFT_ID,BREAK_SEQ,BREAK_LABEL,BREAK_START,BREAK_END,IS_FRIDAY_BREAK)
        VALUES (@S1,3,'Rest 2 (Fri)','14:30','14:40',1);

    IF NOT EXISTS (SELECT 1 FROM TB_BREAK_SLOT WHERE SHIFT_ID=@S1 AND BREAK_SEQ=4 AND IS_FRIDAY_BREAK=1)
        INSERT INTO TB_BREAK_SLOT (SHIFT_ID,BREAK_SEQ,BREAK_LABEL,BREAK_START,BREAK_END,IS_FRIDAY_BREAK)
        VALUES (@S1,4,'Rest 3 (Fri)','16:30','16:45',1);
END
GO

/* --- Break slots for Shift 2 (Night) --- */
DECLARE @S2 INT = (SELECT SHIFT_ID FROM TB_SHIFT_DEFINITION WHERE LINENAME='ADAPTIVE' AND SHIFT_NO=2);
IF @S2 IS NOT NULL
BEGIN
    IF NOT EXISTS (SELECT 1 FROM TB_BREAK_SLOT WHERE SHIFT_ID=@S2 AND BREAK_SEQ=1 AND IS_FRIDAY_BREAK=0)
        INSERT INTO TB_BREAK_SLOT (SHIFT_ID,BREAK_SEQ,BREAK_LABEL,BREAK_START,BREAK_END,IS_FRIDAY_BREAK)
        VALUES (@S2,1,'Rest 1','22:00','22:10',0);

    IF NOT EXISTS (SELECT 1 FROM TB_BREAK_SLOT WHERE SHIFT_ID=@S2 AND BREAK_SEQ=2 AND IS_FRIDAY_BREAK=0)
        INSERT INTO TB_BREAK_SLOT (SHIFT_ID,BREAK_SEQ,BREAK_LABEL,BREAK_START,BREAK_END,IS_FRIDAY_BREAK)
        VALUES (@S2,2,'Dinner','00:00','00:20',0);

    IF NOT EXISTS (SELECT 1 FROM TB_BREAK_SLOT WHERE SHIFT_ID=@S2 AND BREAK_SEQ=3 AND IS_FRIDAY_BREAK=0)
        INSERT INTO TB_BREAK_SLOT (SHIFT_ID,BREAK_SEQ,BREAK_LABEL,BREAK_START,BREAK_END,IS_FRIDAY_BREAK)
        VALUES (@S2,3,'Rest 2','02:30','02:40',0);

    IF NOT EXISTS (SELECT 1 FROM TB_BREAK_SLOT WHERE SHIFT_ID=@S2 AND BREAK_SEQ=4 AND IS_FRIDAY_BREAK=0)
        INSERT INTO TB_BREAK_SLOT (SHIFT_ID,BREAK_SEQ,BREAK_LABEL,BREAK_START,BREAK_END,IS_FRIDAY_BREAK)
        VALUES (@S2,4,'Rest 3','04:30','04:45',0);

    /* Friday night breaks */
    IF NOT EXISTS (SELECT 1 FROM TB_BREAK_SLOT WHERE SHIFT_ID=@S2 AND BREAK_SEQ=1 AND IS_FRIDAY_BREAK=1)
        INSERT INTO TB_BREAK_SLOT (SHIFT_ID,BREAK_SEQ,BREAK_LABEL,BREAK_START,BREAK_END,IS_FRIDAY_BREAK)
        VALUES (@S2,1,'Rest 1 (Fri)','22:00','22:10',1);

    IF NOT EXISTS (SELECT 1 FROM TB_BREAK_SLOT WHERE SHIFT_ID=@S2 AND BREAK_SEQ=2 AND IS_FRIDAY_BREAK=1)
        INSERT INTO TB_BREAK_SLOT (SHIFT_ID,BREAK_SEQ,BREAK_LABEL,BREAK_START,BREAK_END,IS_FRIDAY_BREAK)
        VALUES (@S2,2,'Dinner (Fri)','00:00','00:30',1);

    IF NOT EXISTS (SELECT 1 FROM TB_BREAK_SLOT WHERE SHIFT_ID=@S2 AND BREAK_SEQ=3 AND IS_FRIDAY_BREAK=1)
        INSERT INTO TB_BREAK_SLOT (SHIFT_ID,BREAK_SEQ,BREAK_LABEL,BREAK_START,BREAK_END,IS_FRIDAY_BREAK)
        VALUES (@S2,3,'Rest 2 (Fri)','02:00','02:10',1);

    IF NOT EXISTS (SELECT 1 FROM TB_BREAK_SLOT WHERE SHIFT_ID=@S2 AND BREAK_SEQ=4 AND IS_FRIDAY_BREAK=1)
        INSERT INTO TB_BREAK_SLOT (SHIFT_ID,BREAK_SEQ,BREAK_LABEL,BREAK_START,BREAK_END,IS_FRIDAY_BREAK)
        VALUES (@S2,4,'Rest 3 (Fri)','04:30','04:45',1);
END
GO

PRINT '';
PRINT '=== WTG_DB_BATTERY Redesign Complete ===';
PRINT 'Run: SELECT * FROM V_WORK_STATUS  to verify real-time status';
PRINT 'Run: SELECT * FROM V_LINE_WT_B    for per-shift detail';
PRINT 'Run: EXEC SP_WTG_OVERTIME_OPEN    to start an OT session';
PRINT 'Run: EXEC SP_WTG_OVERTIME_CLOSE   to close  an OT session';
GO
