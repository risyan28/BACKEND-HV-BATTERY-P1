-- =============================================
-- station-config.sql
-- Creates TB_M_STATION_CONFIG, seeds 5 stations,
-- inserts MAN_ASSY_4/5 into TB_R_RFID_COMMAND,
-- and creates SP_UPDATE_STATION_ID procedure.
-- =============================================

-- Drop table if exists for re-runnability
IF OBJECT_ID('TB_M_STATION_CONFIG', 'U') IS NOT NULL
    DROP TABLE TB_M_STATION_CONFIG;

-- Create station config table
CREATE TABLE TB_M_STATION_CONFIG (
    FID INT IDENTITY(1,1) PRIMARY KEY,
    STATION_NAME NVARCHAR(100) NOT NULL,
    DISPLAY_NAME NVARCHAR(100) NOT NULL,
    STATION_ID_SUFFIX VARCHAR(10) NULL,
    IS_MANDATORY BIT NOT NULL DEFAULT 0,
    SORT_ORDER INT NOT NULL DEFAULT 0,
    IS_ACTIVE BIT NOT NULL DEFAULT 1,
    CREATED_AT DATETIME NOT NULL DEFAULT GETDATE(),
    UPDATED_AT DATETIME NULL
);

-- Seed 5 stations
INSERT INTO TB_M_STATION_CONFIG (STATION_NAME, DISPLAY_NAME, STATION_ID_SUFFIX, IS_MANDATORY, SORT_ORDER, IS_ACTIVE)
VALUES
    ('MAN_ASSY_1', 'MANUAL ASSY 1', '1', 1, 1, 1),
    ('MAN_ASSY_2', 'MANUAL ASSY 2', '2', 1, 2, 1),
    ('MAN_ASSY_3', 'MANUAL ASSY 3', '3', 1, 3, 1),
    ('MAN_ASSY_4', 'MANUAL ASSY 4', '5', 0, 4, 0),
    ('MAN_ASSY_5', 'MANUAL ASSY 5', '6', 0, 5, 0);

-- Merge insert MAN_ASSY_4 and MAN_ASSY_5 into TB_R_RFID_COMMAND if not exist
MERGE INTO TB_R_RFID_COMMAND AS t
USING (
    SELECT 'MAN_ASSY_4' AS STATION_NAME, 'READ' AS COMMAND
    UNION SELECT 'MAN_ASSY_4', 'WRITE'
    UNION SELECT 'MAN_ASSY_5', 'READ'
    UNION SELECT 'MAN_ASSY_5', 'WRITE'
) AS s
    ON t.STATION_NAME = s.STATION_NAME AND t.COMMAND = s.COMMAND
WHEN NOT MATCHED THEN
    INSERT (STATION_NAME, STATION_ID, COMMAND, FVALUE, FDATETIME_MODIFIED)
    VALUES (s.STATION_NAME, NULL, s.COMMAND, 0, GETDATE());

GO

-- SP to update STATION_ID across all stations based on active config
CREATE OR ALTER PROCEDURE SP_UPDATE_STATION_ID
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @prefix VARCHAR(10);
    DECLARE @ma4_active BIT;
    DECLARE @ma5_active BIT;

    -- Read active status of configurable stations
    SELECT @ma4_active = IS_ACTIVE FROM TB_M_STATION_CONFIG WHERE STATION_NAME = 'MAN_ASSY_4';
    SELECT @ma5_active = IS_ACTIVE FROM TB_M_STATION_CONFIG WHERE STATION_NAME = 'MAN_ASSY_5';

    -- Determine prefix based on which stations are active
    IF @ma5_active = 1
        SET @prefix = '3';   -- all 5 stations get STATION_ID
    ELSE IF @ma4_active = 1
        SET @prefix = '2';   -- stations 1-4 get STATION_ID
    ELSE
        SET @prefix = '1';   -- only stations 1-3 get STATION_ID

    -- Cursor over station config ordered by SORT_ORDER
    DECLARE @station_name NVARCHAR(100);
    DECLARE @suffix VARCHAR(10);
    DECLARE @is_mandatory BIT;
    DECLARE @cur_active BIT;

    DECLARE sc CURSOR FOR
        SELECT STATION_NAME, STATION_ID_SUFFIX, IS_MANDATORY, IS_ACTIVE
        FROM TB_M_STATION_CONFIG
        ORDER BY SORT_ORDER;

    OPEN sc;
    FETCH NEXT FROM sc INTO @station_name, @suffix, @is_mandatory, @cur_active;

    WHILE @@FETCH_STATUS = 0
    BEGIN
        DECLARE @station_id NVARCHAR(100);
        SET @station_id = NULL;

        -- Assign STATION_ID if station qualifies
        IF @is_mandatory = 1
            OR (@station_name = 'MAN_ASSY_4' AND @ma4_active = 1)
            OR (@station_name = 'MAN_ASSY_5' AND @ma5_active = 1)
        BEGIN
            SET @station_id = @prefix + '_' + @suffix;
        END

        -- UPSERT READ + WRITE rows for this station
        MERGE INTO TB_R_RFID_COMMAND AS t
        USING (
            SELECT @station_name AS STATION_NAME, 'READ' AS COMMAND
            UNION SELECT @station_name, 'WRITE'
        ) AS s
            ON t.STATION_NAME = s.STATION_NAME AND t.COMMAND = s.COMMAND
        WHEN MATCHED THEN
            UPDATE SET
                STATION_ID = @station_id,
                FDATETIME_MODIFIED = GETDATE()
        WHEN NOT MATCHED THEN
            INSERT (STATION_NAME, STATION_ID, COMMAND, FVALUE, FDATETIME_MODIFIED)
            VALUES (s.STATION_NAME, @station_id, s.COMMAND, 0, GETDATE());

        FETCH NEXT FROM sc INTO @station_name, @suffix, @is_mandatory, @cur_active;
    END

    CLOSE sc;
    DEALLOCATE sc;
END;
GO
