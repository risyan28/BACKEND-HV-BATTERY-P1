USE DB_TMMIN1_KRW_RFID_V680S;
GO

-- 1. Fix SP_GENERATE_REG_VALUE_FOR_WRITE: Process ALL fields including NULL (treated as empty -> cleared to 00)
CREATE OR ALTER PROCEDURE [dbo].[SP_GENERATE_REG_VALUE_FOR_WRITE]
    @StationName NVARCHAR(100)
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        DECLARE @RegisterTable TABLE (
            RegisterAddr INT PRIMARY KEY,
            HighByte CHAR(2) DEFAULT '00',
            LowByte CHAR(2) DEFAULT '00'
        );

        DECLARE @i INT = 0;
        WHILE @i <= 999
        BEGIN
            INSERT INTO @RegisterTable (RegisterAddr, HighByte, LowByte) 
            VALUES (@i, '00', '00');
            SET @i = @i + 1;
        END

        DECLARE @CurrentFieldName NVARCHAR(100), @CurrentFieldValue NVARCHAR(500);
        DECLARE field_cursor CURSOR FOR
            SELECT DISTINCT FIELD_NAME, ISNULL(VALUE_ASCII, '')
            FROM TB_R_RFID_MAP
            WHERE STATION_NAME = @StationName
              AND FIELD_NAME IS NOT NULL;

        OPEN field_cursor;
        FETCH NEXT FROM field_cursor INTO @CurrentFieldName, @CurrentFieldValue;

        WHILE @@FETCH_STATUS = 0
        BEGIN
            DECLARE @CharPos INT = 1;
            DECLARE @ByteAddr INT;
            DECLARE mapping_cursor CURSOR FOR
                SELECT CONVERT(INT, CONVERT(VARBINARY(2), m.REG_ADDRESS, 2)) AS ByteAddr
                FROM TB_M_RFID_MAPPING m
                INNER JOIN TB_R_RFID_MAP r ON m.DATA_INFO = r.FIELD_NAME
                WHERE r.STATION_NAME = @StationName
                  AND r.FIELD_NAME = @CurrentFieldName
                ORDER BY m.BYTE_INDEX;

            OPEN mapping_cursor;
            FETCH NEXT FROM mapping_cursor INTO @ByteAddr;

            WHILE @@FETCH_STATUS = 0 AND @CharPos <= LEN(@CurrentFieldValue)
            BEGIN
                DECLARE @Char NCHAR(1) = SUBSTRING(@CurrentFieldValue, @CharPos, 1);
                DECLARE @CharHex NVARCHAR(2) = FORMAT(CONVERT(INT, CONVERT(VARBINARY(1), @Char)), 'X2');
                DECLARE @WordAddr INT = @ByteAddr / 2;
                DECLARE @IsEvenByte INT = @ByteAddr % 2;

                IF @IsEvenByte = 0
                    UPDATE @RegisterTable SET LowByte = @CharHex WHERE RegisterAddr = @WordAddr;
                ELSE
                    UPDATE @RegisterTable SET HighByte = @CharHex WHERE RegisterAddr = @WordAddr;

                SET @CharPos = @CharPos + 1;
                FETCH NEXT FROM mapping_cursor INTO @ByteAddr;
            END

            CLOSE mapping_cursor;
            DEALLOCATE mapping_cursor;
            FETCH NEXT FROM field_cursor INTO @CurrentFieldName, @CurrentFieldValue;
        END

        CLOSE field_cursor;
        DEALLOCATE field_cursor;

        DECLARE @RegValue NVARCHAR(MAX) = '';
        SELECT @RegValue = @RegValue + LowByte + HighByte
        FROM @RegisterTable
        ORDER BY RegisterAddr;

        DECLARE @DeviceName NVARCHAR(100);
        SELECT TOP 1 @DeviceName = DEV_NAME 
        FROM TB_R_READ_DEVICE_AIS WITH (NOLOCK)
        WHERE PROTOCOL = 'OmronV680' AND GROUP_NAME = @StationName
        ORDER BY TR_TIME DESC;

        IF @DeviceName IS NULL SET @DeviceName = @StationName;

        IF EXISTS (
            SELECT 1 FROM TB_R_WRITE_DEVICE_AIS WITH (NOLOCK)
            WHERE DEV_NAME = @DeviceName AND PROTOCOL = 'OmronV680'
              AND GROUP_NAME = @StationName
              AND TAG_NAME = 'WRITE_FULL'
        )
        BEGIN
            UPDATE TB_R_WRITE_DEVICE_AIS
            SET REG_VALUE = @RegValue, WRITE_FLAG = 0, TR_TIME = GETDATE()
            WHERE DEV_NAME = @DeviceName AND PROTOCOL = 'OmronV680'
              AND GROUP_NAME = @StationName
              AND TAG_NAME = 'WRITE_FULL';
        END
        ELSE
        BEGIN
            INSERT INTO TB_R_WRITE_DEVICE_AIS (
                DEV_NAME, PROTOCOL, GROUP_NAME, TAG_NAME, REG_VALUE, DATA_TYPE, WRITE_METHOD, WRITE_FLAG, TR_TIME
            )
            VALUES (
                @DeviceName, 'OmronV680', @StationName, 'WRITE_FULL', @RegValue, 'HEX', 'SINGLE', 0, GETDATE()
            );
        END

        UPDATE TB_R_RFID_MAP SET WRITE_TIME = GETDATE() WHERE STATION_NAME = @StationName;
    END TRY
    BEGIN CATCH
        THROW;
    END CATCH
END;
GO

-- 2. Fix TB_R_READ_DEVICE_AIS_AFTER_UPDATE: Include MAN_ASSY_4 and MAN_ASSY_5
CREATE OR ALTER TRIGGER [dbo].[TB_R_READ_DEVICE_AIS_AFTER_UPDATE]
ON [dbo].[TB_R_READ_DEVICE_AIS]
AFTER UPDATE
AS
BEGIN
    SET NOCOUNT ON;

    IF EXISTS (
        SELECT 1 
        FROM inserted i 
        WHERE i.TAG_NAME = 'READ_COMPLETE'
          AND i.REG_VALUE = '1'
          AND i.GROUP_NAME IN ('UNLOADING', 'MAN_ASSY_1', 'MAN_ASSY_2', 'MAN_ASSY_3', 'MAN_ASSY_4', 'MAN_ASSY_5', 'FINAL_JUDGEMENT', 'SHOP_MAN_ASSY_1')
    )
    BEGIN
        DECLARE @sql NVARCHAR(MAX) = '';
        SELECT @sql = @sql + 
            'EXEC [dbo].[SP_PARSE_AND_UPDATE_RFID_READ_MAP] @StationName = ''' + GROUP_NAME + '''; '
        FROM inserted
        WHERE TAG_NAME = 'READ_COMPLETE'
          AND REG_VALUE = '1'
          AND GROUP_NAME IN ('UNLOADING', 'MAN_ASSY_1', 'MAN_ASSY_2', 'MAN_ASSY_3', 'MAN_ASSY_4', 'MAN_ASSY_5', 'FINAL_JUDGEMENT', 'SHOP_MAN_ASSY_1');

        IF @sql <> ''
            EXEC sp_executesql @sql;

        UPDATE [DB_TMMIN1_KRW_PIS_HV_BATTERY].[dbo].[TB_R_RFID_COMMAND]
        SET FVALUE = 0
        WHERE COMMAND = 'READ'
          AND STATION_NAME IN (
              SELECT DISTINCT i.GROUP_NAME
              FROM inserted i
              WHERE i.TAG_NAME = 'READ_COMPLETE'
                AND i.REG_VALUE = '1'
                AND i.GROUP_NAME IN ('UNLOADING', 'MAN_ASSY_1', 'MAN_ASSY_2', 'MAN_ASSY_3', 'MAN_ASSY_4', 'MAN_ASSY_5', 'FINAL_JUDGEMENT', 'SHOP_MAN_ASSY_1')
          );
    END

    INSERT INTO [DB_MYOPC_CLIENT_PIS_HV_BATTERY_P1].[dbo].[T_TRANSMIT] (
        DEV_NAME, REG_NAME, REG_VALUE, TTL, TR_TIME, ID
    )
    SELECT 
        CASE i.GROUP_NAME
            WHEN 'UNLOADING'      THEN 'PLC_HV_BATT.STATION UN LOADING'
            WHEN 'MAN_ASSY_1'     THEN 'PLC_HV_BATT.STATION MANUAL ASSY 1'
            WHEN 'MAN_ASSY_2'     THEN 'PLC_HV_BATT.STATION MANUAL ASSY 2'
            WHEN 'MAN_ASSY_3'     THEN 'PLC_HV_BATT.STATION MANUAL ASSY 3'
            WHEN 'MAN_ASSY_4'     THEN 'PLC_HV_BATT.STATION MANUAL ASSY 4'
            WHEN 'MAN_ASSY_5'     THEN 'PLC_HV_BATT.STATION MANUAL ASSY 5'
            WHEN 'FINAL_JUDGEMENT' THEN 'PLC_HV_BATT.STATION FINAL JUDGE'
            ELSE 'PLC_HV_BATT.STATION ' + i.GROUP_NAME
        END,
        'STOPPER_DOWN',
        '1',
        100,
        GETDATE(),
        10
    FROM inserted i
    WHERE i.TAG_NAME = 'WRITE_COMPLETE'
      AND i.REG_VALUE = '1'
      AND i.GROUP_NAME IN ('UNLOADING', 'MAN_ASSY_1', 'MAN_ASSY_2', 'MAN_ASSY_3', 'MAN_ASSY_4', 'MAN_ASSY_5', 'FINAL_JUDGEMENT');

    UPDATE [DB_TMMIN1_KRW_PIS_HV_BATTERY].[dbo].[TB_R_RFID_COMMAND]
    SET FVALUE = 0
    WHERE COMMAND = 'WRITE'
      AND STATION_NAME IN (
          SELECT DISTINCT i.GROUP_NAME
          FROM inserted i
          WHERE i.TAG_NAME = 'WRITE_COMPLETE'
            AND i.REG_VALUE = '1'
            AND i.GROUP_NAME IN ('UNLOADING', 'MAN_ASSY_1', 'MAN_ASSY_2', 'MAN_ASSY_3', 'MAN_ASSY_4', 'MAN_ASSY_5', 'FINAL_JUDGEMENT', 'SHOP_MAN_ASSY_1')
      );
END;
GO

PRINT 'RFID fixes applied successfully.';
