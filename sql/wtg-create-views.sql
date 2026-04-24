USE [WTG_DB_BATTERY];
GO

IF OBJECT_ID('V_WORK_STATUS','V') IS NOT NULL DROP VIEW V_WORK_STATUS;
GO
IF OBJECT_ID('V_LINE_WT_B','V') IS NOT NULL DROP VIEW V_LINE_WT_B;
GO

CREATE VIEW V_LINE_WT_B AS
WITH base AS (
    SELECT a.SHIFT_ID, a.LINENAME, a.SHIFT, a.SHIFT_LABEL, a.FNOW,
           a.WT_START_DT, a.WT_END_DT, a.FWT_START_DT, a.FWT_END_DT,
           a.IS_FRIDAY_SCHED, a.IS_IN_BREAK, a.IS_IN_FRIDAY_BREAK,
           DATEPART(WEEKDAY, GETDATE()) AS DOW
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
    CAST(CASE WHEN b.FNOW >= b.WT_START_DT AND b.FNOW < b.WT_END_DT
              THEN 1 ELSE 0 END AS BIT)                         AS WT_TIME,
    CAST(b.IS_IN_BREAK AS BIT)                                  AS IS_BREAK,
    b.FWT_START_DT,
    b.FWT_END_DT,
    CAST(CASE WHEN b.DOW = 6 AND b.IS_FRIDAY_SCHED = 1
                   AND b.FNOW >= b.FWT_START_DT AND b.FNOW < b.FWT_END_DT
              THEN 1 ELSE 0 END AS BIT)                         AS FWT_TIME,
    CAST(b.IS_IN_FRIDAY_BREAK AS BIT)                           AS FBREAK,
    CAST(CASE WHEN ot.OT_ID IS NOT NULL THEN 1 ELSE 0 END AS BIT) AS IS_OVERTIME,
    ot.OT_ID,
    ot.OT_START,
    ot.OT_SECONDS,
    CAST(
        ISNULL(
            (SELECT TRY_CAST(ws.FREG_VALUE AS INT)
             FROM TB_WT_STATUS ws
             WHERE ws.FDEV_NAME = 'WTG'
               AND ws.FLINE     = b.LINENAME
               AND ws.FREG_NAME = 'WT'),
        0)
    AS INT)                                                     AS WT_SECONDS
FROM base b
LEFT JOIN TB_OVERTIME_SESSION ot
    ON  ot.LINENAME = b.LINENAME
    AND ot.SHIFT_ID = b.SHIFT_ID
    AND ot.OT_END   IS NULL
    AND CAST(ot.OT_START AS DATE) = CAST(GETDATE() AS DATE);
GO

CREATE VIEW V_WORK_STATUS AS
SELECT
    b.LINENAME,
    b.SHIFT,
    b.SHIFT_LABEL,
    b.FNOW,
    CASE
        WHEN b.IS_OVERTIME = 1                              THEN 'OVERTIME'
        WHEN b.WT_TIME = 1  AND b.IS_BREAK = 0             THEN 'WORKING'
        WHEN b.WT_TIME = 1  AND b.IS_BREAK = 1             THEN 'BREAK'
        WHEN b.FWT_TIME = 1 AND b.FBREAK   = 0             THEN 'WORKING'
        WHEN b.FWT_TIME = 1 AND b.FBREAK   = 1             THEN 'BREAK'
        ELSE                                                     'IDLE'
    END                                                         AS WORK_MODE,
    b.WT_SECONDS,
    b.IS_BREAK,
    b.IS_OVERTIME,
    b.OT_SECONDS,
    CAST(
        CASE
            WHEN CAST(b.WT_START_DT AS TIME(0)) > CAST('12:00' AS TIME(0))
                 AND CAST(b.FNOW AS TIME(0)) < CAST('12:00' AS TIME(0))
            THEN CAST(DATEADD(DAY, -1, CAST(b.FNOW AS DATE)) AS DATE)
            ELSE CAST(b.FNOW AS DATE)
        END
    AS DATE)                                                    AS SHIFT_DATE,
    b.WT_START_DT,
    b.WT_END_DT
FROM V_LINE_WT_B b
WHERE b.WT_TIME = 1 OR b.FWT_TIME = 1 OR b.IS_OVERTIME = 1;
GO

PRINT 'V_LINE_WT_B and V_WORK_STATUS created OK';
GO
