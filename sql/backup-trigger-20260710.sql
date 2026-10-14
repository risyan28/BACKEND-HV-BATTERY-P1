
CREATE TRIGGER [dbo].[TB_R_REG_STATUS_AFTER_UPDATE]
   ON [dbo].[TB_R_REG_STATUS]
   AFTER UPDATE
AS 
BEGIN
    SET NOCOUNT ON;

    -- START PRINT SEQ STATION UN LOADING---
    IF EXISTS (
        SELECT 1
        FROM inserted i
        WHERE i.REG_VALUE = '1'
          AND i.TAG_NAME = 'PB_PRINT'
          AND i.GROUP_NAME = 'STATION UN LOADING'
          AND i.DEV_NAME = 'PLC_HV_BATT'
    )
    BEGIN
        INSERT INTO [DB_TMMIN1_KRW_PIS_HV_BATTERY].[dbo].[TB_R_PRINT_LABEL] (FPRINT_QRCODE, FMODEL_BATTERY, FDATETIME_MODIFIED, ORDER_TYPE,PROD_DATE)
        SELECT TOP 1 
               s.FBARCODE, 
               s.FMODEL_BATTERY, 
               GETDATE(),
               s.ORDER_TYPE,
               S.FSEQ_DATE
        FROM [DB_TMMIN1_KRW_PIS_HV_BATTERY].[dbo].[TB_R_SEQUENCE_BATTERY] s
        WHERE s.FSTATUS = '0'
        ORDER BY s.FID_ADJUST ASC;
    END
   -- END START PRINT SEQ STATION UN LOADING ---



    -- FINISH UPDATE STATUS STATION UN LOADING ---
    IF EXISTS (
        SELECT 1
        FROM inserted i
        WHERE i.REG_VALUE = '1'
          AND i.TAG_NAME IN ('FINISH', 'STOPPER_DOWN')
          AND i.GROUP_NAME = 'STATION UN LOADING'
          AND i.DEV_NAME = 'PLC_HV_BATT'
    )
    BEGIN
        UPDATE [DB_TMMIN1_KRW_PIS_HV_BATTERY].[dbo].[TB_R_SEQUENCE_BATTERY] 
        SET FSTATUS = 2, FTIME_COMPLETED = GETDATE()
        WHERE FSTATUS = 1;

    END
   -- END FINISH UPDATE STATUS STATION UN LOADING ---



   -- ? PART 1: TOTAL_STATUS  UPDATE RFID MAP (SEMUA STATION)
    IF EXISTS (
        SELECT 1
        FROM inserted i
        WHERE i.TAG_NAME = 'TOTAL_STATUS'
            AND i.REG_VALUE IN ('1', '2')
            AND i.DEV_NAME = 'PLC_HV_BATT'
    )
    BEGIN
        --  UPDATE GLOBAL: semua station (JUDGEMENT POS X) 
        UPDATE m
        SET 
            VALUE_ASCII = i.REG_VALUE,
            WRITE_TIME = GETDATE()
        FROM [DB_TMMIN1_KRW_RFID_V680S].[dbo].[TB_R_RFID_MAP] m
        INNER JOIN inserted i ON 
            m.STATION_NAME = CASE i.GROUP_NAME
                WHEN 'STATION UN LOADING'     THEN 'UNLOADING'
                WHEN 'STATION MANUAL ASSY 1'  THEN 'MAN_ASSY_1'
                WHEN 'STATION MANUAL ASSY 2'  THEN 'MAN_ASSY_2'
                WHEN 'STATION MANUAL ASSY 3'  THEN 'MAN_ASSY_3'
                WHEN 'STATION MANUAL ASSY 4'  THEN 'MAN_ASSY_4'
                WHEN 'STATION MANUAL ASSY 5'  THEN 'MAN_ASSY_5'
                ELSE NULL
            END
            AND m.FIELD_NAME = CASE i.GROUP_NAME
                WHEN 'STATION UN LOADING'     THEN 'MODULE INSPECTION'
                WHEN 'STATION MANUAL ASSY 1'  THEN 'MANUAL ASSY 1'
                WHEN 'STATION MANUAL ASSY 2'  THEN 'MANUAL ASSY 2'
                WHEN 'STATION MANUAL ASSY 3'  THEN 'MANUAL ASSY 3'
                WHEN 'STATION MANUAL ASSY 4'  THEN 'MANUAL ASSY 4'
                WHEN 'STATION MANUAL ASSY 5'  THEN 'MANUAL ASSY 5'
                ELSE NULL
            END
        WHERE i.TAG_NAME = 'TOTAL_STATUS'
            AND i.REG_VALUE IN ('1', '2')
            AND i.DEV_NAME = 'PLC_HV_BATT';
    END
    -- ? END PART 1

    -- ? PART 2: KHUSUS STATION UN LOADING  INSERT KE TB_H_POS_UNLOADING
    -- ? DIPISAH DARI IF PERTAMA UNTUK INDEPENDEN & MENGHINDARI TIMING ISSUE
    IF EXISTS (
            SELECT 1
            FROM inserted i
            WHERE i.TAG_NAME = 'TOTAL_STATUS'
                AND i.REG_VALUE IN ('1', '2')
                AND i.DEV_NAME = 'PLC_HV_BATT'
                AND i.GROUP_NAME = 'STATION UN LOADING'
            )
            BEGIN
                -- ? NO DELAY - Direct processing
                DECLARE @Module1 NVARCHAR(MAX), @Module2 NVARCHAR(MAX), @PackID NVARCHAR(MAX);
                DECLARE @Lifetime1 NVARCHAR(MAX), @Lifetime2 NVARCHAR(MAX), @TotalStatus NVARCHAR(1);

                -- Ambil TOTAL_STATUS dari inserted
                SELECT TOP 1 @TotalStatus = i.REG_VALUE
                FROM inserted i
                WHERE i.TAG_NAME = 'TOTAL_STATUS'
                  AND i.GROUP_NAME = 'STATION UN LOADING'
                ORDER BY i.TR_TIME DESC;

                -- ? SIMPLE: Langsung ambil data terbaru dari TB_R_REG_STATUS
                WITH LatestValues AS (
                    SELECT 
                        TAG_NAME,
                        REG_VALUE,
                        ROW_NUMBER() OVER (PARTITION BY TAG_NAME ORDER BY TR_TIME DESC) AS rn
                    FROM dbo.TB_R_REG_STATUS WITH (NOLOCK)
                    WHERE DEV_NAME = 'PLC_HV_BATT'
                      AND GROUP_NAME = 'STATION UN LOADING'
                      AND TAG_NAME IN ('MODULE_1', 'MODULE_2', 'PACK_ID', 'LIFETIME_MODULE1', 'LIFETIME_MODULE2')
                )
                SELECT
                    @Module1 = MAX(CASE WHEN TAG_NAME = 'MODULE_1' THEN REG_VALUE END),
                    @Module2 = MAX(CASE WHEN TAG_NAME = 'MODULE_2' THEN REG_VALUE END),
                    @PackID = MAX(CASE WHEN TAG_NAME = 'PACK_ID' THEN REG_VALUE END),
                    @Lifetime1 = MAX(CASE WHEN TAG_NAME = 'LIFETIME_MODULE1' THEN REG_VALUE END),
                    @Lifetime2 = MAX(CASE WHEN TAG_NAME = 'LIFETIME_MODULE2' THEN REG_VALUE END)
                FROM LatestValues
                WHERE rn = 1;

                -- ? Hanya lanjut jika SEMUA data ada DAN tidak kosong
                --IF @Module1 IS NOT NULL AND LTRIM(RTRIM(@Module1)) <> ''
                --    AND @Module2 IS NOT NULL AND LTRIM(RTRIM(@Module2)) <> ''
                --    AND @PackID IS NOT NULL AND LTRIM(RTRIM(@PackID)) <> ''
                --    AND @Lifetime1 IS NOT NULL 
                --    AND @Lifetime2 IS NOT NULL
                --BEGIN
                        -- 2a. INSERT ke TB_H_POS_UNLOADING
                        INSERT INTO [DB_TMMIN1_KRW_PIS_HV_BATTERY].[dbo].[TB_H_POS_UNLOADING] (
                            MODULE_1,
                            MODULE_2,
                            PACK_ID,
                            LIFETIME_MODULE1,
                            LIFETIME_MODULE2,
                            JUDGEMENT_VALUE
                        )
                        VALUES (
                            LTRIM(RTRIM(@Module1)),     -- ? TRIM untuk pastikan tidak ada whitespace
                            LTRIM(RTRIM(@Module2)),     -- ? TRIM untuk pastikan tidak ada whitespace
                            LTRIM(RTRIM(@PackID)),      -- ? TRIM untuk pastikan tidak ada whitespace
                            @Lifetime1,
                            @Lifetime2,
                            CASE @TotalStatus WHEN '1' THEN 'OK' ELSE 'NG' END
                        );

                        -- 2b. UPDATE FIELD TAMBAHAN DI TB_R_RFID_MAP (hanya untuk UNLOADING)
                        --UPDATE [DB_TMMIN1_KRW_RFID_V680S].[dbo].[TB_R_RFID_MAP]
                        --SET 
                        --    VALUE_ASCII = CASE FIELD_NAME
                        --        WHEN 'LI MODULE ASSY 1' THEN LTRIM(RTRIM(@Module1))
                        --        WHEN 'LI MODULE ASSY 2' THEN LTRIM(RTRIM(@Module2))
                        --        WHEN 'LABEL PACK ID' THEN LTRIM(RTRIM(@PackID))
                        --        ELSE VALUE_ASCII
                        --    END,
                        --    WRITE_TIME = GETDATE()
                        --WHERE 
                        --    STATION_NAME = 'UNLOADING'
                        --    AND FIELD_NAME IN ('LI MODULE ASSY 1', 'LI MODULE ASSY 2', 'LABEL PACK ID');


                        --UPDATE [DB_TMMIN1_KRW_PIS_HV_BATTERY].[dbo].[TB_R_RFID_COMMAND]
                        --SET 
                        --    FVALUE = 1,
                        --    FDATETIME_MODIFIED = GETDATE()
                        --WHERE STATION_NAME = 'UNLOADING'
                        --    AND COMMAND = 'WRITE'
                        

                        -- 2c. TRIGGER READ FLAG DI EXCEL READER MODULE INSPECTION
                        UPDATE [DB_TMMIN1_KRW_EXCEL_READER_PIS].[dbo].[TB_R_WRITE_DEVICE_AIS]
                        SET  
                            REG_VALUE = CONVERT(VARCHAR(8), GETDATE(), 112) + '.csv',
                            WRITE_FLAG = 0
                        WHERE DEV_NAME = 'EXCEL-READER-MODULE-INSPECTION'
                          AND GROUP_NAME = '\\192.168.250.3\Traceability';
               -- END
    END
    -- ? END PART 2: STATION UN LOADING SPECIFIC


    -- ? KHUSUS STATION 4  INSERT KE [TB_H_SHOP_MAN_ASSY1]
       IF EXISTS (
             SELECT 1 FROM inserted i
             WHERE i.TAG_NAME = 'TOTAL_STATUS'
                 AND i.REG_VALUE IN ('1', '2')
                 AND i.DEV_NAME = 'PLC_HV_BATT'
                 AND i.GROUP_NAME = 'STATION 4'
         )
         BEGIN
             DECLARE @EcuID NVARCHAR(MAX), @PackIDShop NVARCHAR(MAX);

             SELECT @EcuID = REG_VALUE
             FROM dbo.TB_R_REG_STATUS
             WHERE DEV_NAME = 'PLC_HV_BATT' 
                 AND GROUP_NAME = 'STATION 4'
                 AND TAG_NAME = 'SR1000_RESULT_READ'
             ORDER BY TR_TIME DESC;

             SELECT @PackIDShop = REG_VALUE
             FROM dbo.TB_R_REG_STATUS
             WHERE DEV_NAME = 'PLC_HV_BATT' 
                 AND GROUP_NAME = 'STATION 4'
                 AND TAG_NAME = 'PACK_ID_LABEL'
             ORDER BY TR_TIME DESC;

             --IF @EcuID IS NOT NULL AND @EcuID <> ''
             --BEGIN
                 INSERT INTO [DB_TMMIN1_KRW_PIS_HV_BATTERY].[dbo].[TB_H_SHOP_MAN_ASSY1] (
                     ECU_ID,
                     PACK_ID,
                     CREATED_AT
                 )
                 VALUES (
                     @EcuID,
                     @PackIDShop,
                     GETDATE()
                 );
            -- END
         END
        -- ? END KHUSUS STATION 4  INSERT KE [TB_H_SHOP_MAN_ASSY1]




   --  KHUSUS STATION FINAL JUDGE: Ambil data terbaru per TAG_NAME dalam 1 query 
        IF EXISTS (
            SELECT 1
            FROM inserted i
            WHERE i.TAG_NAME = 'TOTAL_STATUS'
                AND i.REG_VALUE IN ('1', '2')
                AND i.DEV_NAME = 'PLC_HV_BATT'
                AND i.GROUP_NAME = 'STATION FINAL JUDGE'
        )
        BEGIN
            DECLARE 
                @FinalTotalStatus NVARCHAR(1),
                @Module1FJ NVARCHAR(MAX), @Module2FJ NVARCHAR(MAX), @PackIDFJ NVARCHAR(MAX),
                @Lifetime1FJ NVARCHAR(MAX), @Lifetime2FJ NVARCHAR(MAX),
                @JudgeInspMachine NVARCHAR(10), @JudgeManAssy1 NVARCHAR(10), @JudgeManAssy2 NVARCHAR(10),
                @JudgeManAssy3 NVARCHAR(10), @JudgeInspModule NVARCHAR(10), @JudgeLabelCam NVARCHAR(10);

            -- Ambil TOTAL_STATUS dari inserted
            SELECT TOP 1 @FinalTotalStatus = i.REG_VALUE
            FROM inserted i
            WHERE i.TAG_NAME = 'TOTAL_STATUS'
              AND i.GROUP_NAME = 'STATION FINAL JUDGE'
            ORDER BY i.TR_TIME DESC;

            -- ? BARU: Clear data sebelumnya jika TOTAL_STATUS = '1' (OK)
            -- Set VALUE_ASCII = NULL untuk field-field yang akan diisi ulang
          --  IF @FinalTotalStatus = '1'
            IF @FinalTotalStatus IN ('1', '2')
                BEGIN
                    UPDATE [DB_TMMIN1_KRW_RFID_V680S].[dbo].[TB_R_RFID_MAP]
                    SET 
                        VALUE_ASCII = NULL,
                        WRITE_TIME = GETDATE()
                    WHERE 
                        STATION_NAME = 'FINAL_JUDGEMENT'
                        AND FIELD_NAME IN (
                            'MANUAL ASSY 1',
                            'PACK INSPECTION',
                            'LI MODULE ASSY 1',
                            'LABEL PACK ID',
                            'COMPLETE CHARGING TIME',
                            'MANUAL ASSY 3',
                            'MANUAL ASSY 2',
                            'MODULE INSPECTION',
                            'LI MODULE ASSY 2'
                        );
             END;

            -- Ambil SEMUA field terbaru per TAG_NAME dalam SATU query
            WITH LatestValues AS (
                SELECT 
                    TAG_NAME,
                    REG_VALUE,
                    ROW_NUMBER() OVER (PARTITION BY TAG_NAME ORDER BY TR_TIME DESC) AS rn
                FROM dbo.TB_R_REG_STATUS
                WHERE DEV_NAME = 'PLC_HV_BATT'
                  AND GROUP_NAME = 'STATION FINAL JUDGE'
                  AND TAG_NAME IN (
                      'MODULE_1', 'MODULE_2', 'PACK_ID',
                      'LIFETIME_MODULE1', 'LIFETIME_MODULE2',
                      'JUDGE_INSP_MACHINE', 'JUDGE_MAN_ASSY_1', 'JUDGE_MAN_ASSY_2',
                      'JUDGE_MAN_ASSY_3', 'JUDGE_INSP_MODULE', 'JUDGE_LABEL_CAM'
                  )
            )
            SELECT
                @Module1FJ = MAX(CASE WHEN TAG_NAME = 'MODULE_1' THEN REG_VALUE END),
                @Module2FJ = MAX(CASE WHEN TAG_NAME = 'MODULE_2' THEN REG_VALUE END),
                @PackIDFJ = MAX(CASE WHEN TAG_NAME = 'PACK_ID' THEN REG_VALUE END),
                @Lifetime1FJ = MAX(CASE WHEN TAG_NAME = 'LIFETIME_MODULE1' THEN REG_VALUE END),
                @Lifetime2FJ = MAX(CASE WHEN TAG_NAME = 'LIFETIME_MODULE2' THEN REG_VALUE END),
                @JudgeInspMachine = MAX(CASE WHEN TAG_NAME = 'JUDGE_INSP_MACHINE' THEN REG_VALUE END),
                @JudgeManAssy1 = MAX(CASE WHEN TAG_NAME = 'JUDGE_MAN_ASSY_1' THEN REG_VALUE END),
                @JudgeManAssy2 = MAX(CASE WHEN TAG_NAME = 'JUDGE_MAN_ASSY_2' THEN REG_VALUE END),
                @JudgeManAssy3 = MAX(CASE WHEN TAG_NAME = 'JUDGE_MAN_ASSY_3' THEN REG_VALUE END),
                @JudgeInspModule = MAX(CASE WHEN TAG_NAME = 'JUDGE_INSP_MODULE' THEN REG_VALUE END),
                @JudgeLabelCam = MAX(CASE WHEN TAG_NAME = 'JUDGE_LABEL_CAM' THEN REG_VALUE END)
            FROM LatestValues
            WHERE rn = 1;  -- Hanya ambil nilai terbaru per TAG_NAME

            -- ? Insert jika judgment lengkap
            IF @FinalTotalStatus IS NOT NULL
               AND @Module1FJ IS NOT NULL
               AND @Module2FJ IS NOT NULL
               AND @PackIDFJ IS NOT NULL
               AND @Lifetime1FJ IS NOT NULL
               AND @Lifetime2FJ IS NOT NULL
               AND @JudgeInspMachine IS NOT NULL
               AND @JudgeManAssy1 IS NOT NULL
               AND @JudgeManAssy2 IS NOT NULL
               AND @JudgeManAssy3 IS NOT NULL
               AND @JudgeInspModule IS NOT NULL
               AND @JudgeLabelCam IS NOT NULL
            BEGIN
                INSERT INTO [DB_TMMIN1_KRW_PIS_HV_BATTERY].[dbo].[TB_H_POS_FINAL_JUDGEMENT] (
                    MODULE_1, MODULE_2, PACK_ID,
                    LIFETIME_MODULE1, LIFETIME_MODULE2,
                    JUDGE_INSP_MACHINE, JUDGE_MAN_ASSY_1, JUDGE_MAN_ASSY_2, JUDGE_MAN_ASSY_3,
                    JUDGE_INSP_MODULE, JUDGE_LABEL_CAM,
                    OVERALL_JUDGEMENT, CREATED_AT
                )
                VALUES (
                    ISNULL(@Module1FJ, ''),
                    ISNULL(@Module2FJ, ''),
                    ISNULL(@PackIDFJ, ''),
                    ISNULL(@Lifetime1FJ, ''),
                    ISNULL(@Lifetime2FJ, ''),
                    CASE WHEN @JudgeInspMachine = '1' THEN 'OK' ELSE 'NG' END,
                    CASE WHEN @JudgeManAssy1 = '1' THEN 'OK' ELSE 'NG' END,
                    CASE WHEN @JudgeManAssy2 = '1' THEN 'OK' ELSE 'NG' END,
                    CASE WHEN @JudgeManAssy3 = '1' THEN 'OK' ELSE 'NG' END,
                    CASE WHEN @JudgeInspModule = '1' THEN 'OK' ELSE 'NG' END,
                    CASE WHEN @JudgeLabelCam = '1' THEN 'OK' ELSE 'NG' END,
                    CASE WHEN @FinalTotalStatus = '1' THEN 'OK' ELSE 'NG' END,
                    GETDATE()
                );
            END

                 -- 2. ? BARU: Insert ke T_TRANSMIT setelah sukses simpan final judgement
                 INSERT INTO [DB_MYOPC_CLIENT_PIS_HV_BATTERY_P1].[dbo].[T_TRANSMIT] (
                     DEV_NAME,
                     REG_NAME,
                     REG_VALUE,
                     TTL,
                     TR_TIME,
                     ID
                 )
                 SELECT 
                     'PLC_HV_BATT.STATION FINAL JUDGE' AS DEV_NAME,
                     v.REG_NAME,
                     v.REG_VALUE,
                     10 AS TTL,
                     GETDATE() AS TR_TIME,
                     CAST(@PackIDFJ AS VARCHAR(50)) AS ID
                 FROM (VALUES 
                     ('JUDGE_TRACEBILITY_COMPL', '1')
                 ) AS v(REG_NAME, REG_VALUE)
                 WHERE @PackIDFJ IS NOT NULL;

               
                     -- 3. ? Update Excel Reader
                UPDATE [DB_TMMIN1_KRW_EXCEL_READER_PIS].[dbo].[TB_R_WRITE_DEVICE_AIS]
                SET 
                    REG_VALUE = CONVERT(VARCHAR(8), GETDATE(), 112) + '.csv',
                    WRITE_FLAG = 0,
                    TR_TIME = GETDATE()
                WHERE 
                    DEV_NAME = 'EXCEL-READER-INSPECTION-MACHINE'
                    AND GROUP_NAME = N'\\192.168.250.4\Li5G'
                    AND TAG_NAME = 'READ_EXCEL';
        END
        --  END STATION FINAL JUDGE 


   -- ? HANDLE START & FINISH  UPDATE TB_R_POS_STATUS
    IF EXISTS (
        SELECT 1
        FROM inserted i
        WHERE i.TAG_NAME IN ('START', 'FINISH')
          AND i.DEV_NAME = 'PLC_HV_BATT'
          AND i.REG_VALUE IN ('0', '1')
    )
    BEGIN
        UPDATE [DB_TMMIN1_KRW_PIS_HV_BATTERY].[dbo].[TB_R_POS_STATUS]
        SET 
            FVALUE = CAST(i.REG_VALUE AS INT),
            FDATETIME_MODIFIED = GETDATE()
        FROM inserted i
        WHERE 
            TB_R_POS_STATUS.STATUS = LOWER(i.TAG_NAME)
            AND TB_R_POS_STATUS.STATION = CASE 
                WHEN i.GROUP_NAME = 'STATION UN LOADING' THEN 'UN LOADING'
                WHEN i.GROUP_NAME = 'STATION MANUAL ASSY 1' THEN 'MANUAL ASSY 1'
                WHEN i.GROUP_NAME = 'STATION MANUAL ASSY 2' THEN 'MANUAL ASSY 2'
                WHEN i.GROUP_NAME = 'STATION MANUAL ASSY 3' THEN 'MANUAL ASSY 3'
                WHEN i.GROUP_NAME = 'STATION MANUAL ASSY 4' THEN 'MANUAL ASSY 4'
                WHEN i.GROUP_NAME = 'STATION MANUAL ASSY 5' THEN 'MANUAL ASSY 5'
                WHEN i.GROUP_NAME = 'STATION FINAL JUDGE' THEN 'FINAL JUDGE'
                ELSE NULL
            END;
    END
    -- ? END HANDLE START & FINISH  UPDATE TB_R_POS_STATUS



    -- ? HANDLE CALLING_BOX ALL POS
            IF EXISTS (
                SELECT 1
                FROM inserted i
                WHERE i.TAG_NAME = 'CALLING_BOX'
                  AND i.DEV_NAME = 'PLC_HV_BATT'
                  AND i.REG_VALUE IN ('0', '1', '2')
            )
            BEGIN
                -- Simpan ke temp table supaya bisa dipakai lebih dari 1 statement
                SELECT 
                    GROUP_NAME,
                    REG_VALUE,
                    ROW_NUMBER() OVER (PARTITION BY GROUP_NAME ORDER BY (SELECT NULL)) AS rn
                INTO #LatestCall
                FROM inserted
                WHERE TAG_NAME = 'CALLING_BOX'
                  AND DEV_NAME = 'PLC_HV_BATT'
                  AND REG_VALUE IN ('0', '1', '2');

                -- 1. UPDATE TB_R_ANDON_STATUS
                UPDATE a
                SET 
                    FVALUE = CASE 
                        WHEN lc.REG_VALUE = '0' THEN 0
                        ELSE 1
                    END,
                    FDATETIME_MODIFIED = GETDATE()
                FROM [DB_TMMIN1_KRW_PIS_HV_BATTERY].[dbo].[TB_R_ANDON_STATUS] a
                INNER JOIN #LatestCall lc 
                    ON a.STATION = CASE 
                        WHEN lc.GROUP_NAME = 'STATION UN LOADING'    THEN 'UN LOADING'
                        WHEN lc.GROUP_NAME = 'STATION MANUAL ASSY 1' THEN 'MANUAL ASSY 1'
                        WHEN lc.GROUP_NAME = 'STATION MANUAL ASSY 2' THEN 'MANUAL ASSY 2'
                        WHEN lc.GROUP_NAME = 'STATION MANUAL ASSY 3' THEN 'MANUAL ASSY 3'
                        WHEN lc.GROUP_NAME = 'STATION MANUAL ASSY 4' THEN 'MANUAL ASSY 4'
                        WHEN lc.GROUP_NAME = 'STATION MANUAL ASSY 5' THEN 'MANUAL ASSY 5'
                        WHEN lc.GROUP_NAME = 'STATION INSP MACH' THEN 'INSPECT'
                        WHEN lc.GROUP_NAME = 'STATION FINAL JUDGE'   THEN 'FINAL JUDGE'
                        WHEN lc.GROUP_NAME = 'STATION MAN BRACKET'   THEN 'MAN BRACKET'
                        ELSE NULL
                    END
                WHERE 
                    lc.rn = 1
                    AND (
                        (lc.REG_VALUE = '0' AND a.CALL_TYPE IN ('LEADER', 'MTN'))
                        OR (lc.REG_VALUE = '1' AND a.CALL_TYPE = 'LEADER')
                        OR (lc.REG_VALUE = '2' AND a.CALL_TYPE = 'MTN')
                    );

                -- 2. UPDATE TB_R_WRITE_DEVICE_AIS
                UPDATE wda
                SET 
                    WRITE_FLAG = CASE 
                        WHEN lc.REG_VALUE = '0' THEN 4  -- Reset: Leader & MTC  flag 4
                        ELSE 0                           -- Call Leader/MTC  flag 0
                    END,
                    TR_TIME = GETDATE()
                FROM [DB_TMMIN1_KRW_ANDON_MELODY].[dbo].[TB_R_WRITE_DEVICE_AIS] wda
                INNER JOIN #LatestCall lc ON 1=1
                WHERE 
                    lc.rn = 1
                    AND wda.DEV_NAME IN ('ANDON-INDOOR', 'ANDON-OUTDOOR')
                    AND (
                        (lc.REG_VALUE = '1' AND wda.TAG_NAME = 'Leader')
                        OR (lc.REG_VALUE = '2' AND wda.TAG_NAME = 'MTC')
                        OR (lc.REG_VALUE = '0' AND wda.TAG_NAME IN ('Leader', 'MTC'))
                    );

                DROP TABLE #LatestCall;
            END
            -- ? END HANDLE CALLING_BOX ALL POS



        -- ? HANDLE TRG_READ_RFID & TRG_WRITE_RFID  UPDATE TB_R_RFID_COMMAND
        IF EXISTS (
            SELECT 1
            FROM inserted i
            WHERE i.TAG_NAME IN ('TRG_READ_RFID', 'TRG_WRITE_RFID')
              AND i.DEV_NAME = 'PLC_HV_BATT'
              AND i.REG_VALUE IN ('0', '1')
        )
        BEGIN
            UPDATE c
            SET 
                FVALUE = CAST(i.REG_VALUE AS INT),
                FDATETIME_MODIFIED = GETDATE()
            FROM [DB_TMMIN1_KRW_PIS_HV_BATTERY].[dbo].[TB_R_RFID_COMMAND] c
            INNER JOIN inserted i ON 
                c.STATION_NAME = CASE 
                    WHEN i.GROUP_NAME = 'STATION UN LOADING' THEN 'UNLOADING'
                    WHEN i.GROUP_NAME = 'STATION MANUAL ASSY 1' THEN 'MAN_ASSY_1'
                    WHEN i.GROUP_NAME = 'STATION MANUAL ASSY 2' THEN 'MAN_ASSY_2'
                    WHEN i.GROUP_NAME = 'STATION MANUAL ASSY 3' THEN 'MAN_ASSY_3'
                    WHEN i.GROUP_NAME = 'STATION FINAL JUDGE' THEN 'FINAL_JUDGEMENT'
                    WHEN i.GROUP_NAME = 'STATION 4' THEN 'SHOP_MAN_ASSY_1'
                    ELSE NULL
                END
                AND c.COMMAND = CASE 
                    WHEN i.TAG_NAME = 'TRG_READ_RFID' THEN 'READ'
                    WHEN i.TAG_NAME = 'TRG_WRITE_RFID' THEN 'WRITE'
                    ELSE NULL
                END
            WHERE 
                i.TAG_NAME IN ('TRG_READ_RFID', 'TRG_WRITE_RFID');
        END
       -- ? END HANDLE TRG_READ_RFID & TRG_WRITE_RFID  UPDATE TB_R_RFID_COMMAND



       -- TRG_RECAPTURE_CAMERA ---
            IF EXISTS (
                SELECT 1
                FROM inserted i
                WHERE i.REG_VALUE = '1'
                    AND i.TAG_NAME = 'TRG_RECAPTURE_CAMERA'
                    AND i.GROUP_NAME = 'STATION FINAL JUDGE'
                    AND i.DEV_NAME = 'PLC_HV_BATT'
            )
            BEGIN

            UPDATE [DB_TMMIN1_KRW_CAMERA_FINAL_JUDGEMENT].[dbo].[TB_R_SERIAL_NUMBER]
            SET 
                FFLAG = 1,
                FUPDATED_AT = GETDATE()
            WHERE FID = 1;

                --UPDATE [DB_TMMIN1_KRW_CAMERA_FINAL_JUDGEMENT].[dbo].[TB_M_SIGNAL]
                --SET 
                --    FSIGNAL = 1,
                --    FUPDATED_AT = GETDATE()
                --WHERE FDEVICE = 'trg_capture';
            END
       -- END TRG_RECAPTURE_CAMERA  ---


        -- SR1000_RESULT_READ ERROR CHECK ---
            IF EXISTS (
                SELECT 1
                FROM inserted i
                LEFT JOIN deleted d ON i.CLIENT_HDL = d.CLIENT_HDL
                WHERE LTRIM(RTRIM(i.REG_VALUE)) = 'ERROR'
                    AND i.TAG_NAME = 'SR1000_RESULT_READ'
                    AND i.GROUP_NAME = 'STATION 4'
                    AND i.DEV_NAME = 'PLC_HV_BATT'
                    AND (d.REG_VALUE IS NULL OR LTRIM(RTRIM(d.REG_VALUE)) <> 'ERROR')  -- Hanya jika berubah jadi ERROR
            )
            BEGIN
                UPDATE [DB_TMMIN1_KRW_PIS_HV_BATTERY].[dbo].[TB_R_NOTIF_ANDON]
                SET FVALUE = 1,
                    FDATETIME_MODIFIED = GETDATE()
                WHERE GROUP_NAME = 'SHOP-MAN-ASSY1'
                    AND NOTIF_NAME = 'NO DATA ECU ID, PLEASE RE-SCAN ECU ID';
            END


            -- MAN BRACKET BUFFER MODEL---
            IF EXISTS (
                SELECT 1
                FROM inserted i
                LEFT JOIN deleted d ON i.CLIENT_HDL = d.CLIENT_HDL
                WHERE i.TAG_NAME = 'MAN_BRACKET_LS'
                    AND i.GROUP_NAME = 'STATION MAN BRACKET'
                    AND i.DEV_NAME = 'PLC_HV_BATT'
                    AND (d.REG_VALUE IS NULL OR i.REG_VALUE <> d.REG_VALUE)
            )
            BEGIN
                UPDATE [DB_TMMIN1_KRW_PIS_HV_BATTERY].[dbo].[TB_R_MAN_BRACKET_INTERLOCK]
                SET DESTINATION = CASE
                                    (SELECT TOP 1 i2.REG_VALUE
                                     FROM inserted i2
                                     WHERE i2.TAG_NAME = 'MAN_BRACKET_LS'
                                       AND i2.GROUP_NAME = 'STATION MAN BRACKET'
                                       AND i2.DEV_NAME = 'PLC_HV_BATT')
                                    WHEN '0' THEN 'ASSY'
                                    WHEN '1' THEN 'CKD'
                                    ELSE DESTINATION
                                  END,
                    FUPDATE = GETDATE()
                WHERE FID = 1;
            END


             -- FINISH TIGHTENING MAN BRACKET ---
                IF EXISTS (
                    SELECT 1
                    FROM inserted i
                    WHERE i.REG_VALUE = '1'
                      AND i.TAG_NAME = 'COMPLETE_TIGHTENING'
                      AND i.GROUP_NAME = 'STATION MAN BRACKET'
                      AND i.DEV_NAME = 'PLC_HV_BATT'
                )
                BEGIN
                    UPDATE [DB_TMMIN1_KRW_PIS_HV_BATTERY].[dbo].[TB_R_MAN_BRACKET] 
                    SET FVALUE = 1, COMPLETED_TIME = GETDATE()
                    WHERE FVALUE = 0;

                END
               -- END FINISH TIGHTENING MAN BRACKET ---

END


(1 rows affected)
