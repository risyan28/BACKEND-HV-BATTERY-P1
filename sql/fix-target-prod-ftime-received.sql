USE [DB_TMMIN1_KRW_PIS_HV_BATTERY]
GO
/****** Object:  Trigger [dbo].[TB_R_TARGET_PROD_AFTER_UPDATE]    Script Date: 20/04/2026 09:57:21 ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
ALTER   TRIGGER [dbo].[TB_R_TARGET_PROD_AFTER_UPDATE]
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
