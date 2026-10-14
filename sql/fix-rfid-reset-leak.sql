USE DB_TMMIN1_KRW_RFID_V680S;
GO

-- =====================================================================
-- FIX: Comprehensive Reset Procedure for RFID on Final Judgement
-- Wipes ALL stations in TB_R_RFID_MAP and triggers hardware tag clear.
-- =====================================================================
CREATE OR ALTER PROCEDURE [dbo].[SP_RESET_ALL_RFID_STATIONS]
AS
BEGIN
    SET NOCOUNT ON;
    
    -- 1. Wipe ALL VALUE_ASCII across ALL stations in RFID MAP
    UPDATE TB_R_RFID_MAP
    SET VALUE_ASCII = NULL,
        WRITE_TIME = GETDATE();

    -- 2. Trigger WRITE_FULL (clear to 00) for all stations via TB_R_WRITE_DEVICE_AIS
    -- This ensures physical RFID tags are actually wiped out on hardware reader
    DECLARE @StationName NVARCHAR(100);
    
    DECLARE station_cursor CURSOR FOR
        SELECT DISTINCT STATION_NAME FROM TB_R_RFID_MAP;
        
    OPEN station_cursor;
    FETCH NEXT FROM station_cursor INTO @StationName;
    
    WHILE @@FETCH_STATUS = 0
    BEGIN
        -- Generate 0000... payload for this station and set WRITE_FLAG = 0
        EXEC [dbo].[SP_GENERATE_REG_VALUE_FOR_WRITE] @StationName = @StationName;
        
        FETCH NEXT FROM station_cursor INTO @StationName;
    END
    
    CLOSE station_cursor;
    DEALLOCATE station_cursor;
END;
GO

PRINT 'SP_RESET_ALL_RFID_STATIONS created successfully.';
GO
