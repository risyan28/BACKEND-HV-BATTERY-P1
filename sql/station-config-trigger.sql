-- Drop SP, replace with trigger
DROP PROCEDURE IF EXISTS SP_UPDATE_STATION_ID;
GO

CREATE TRIGGER TRG_M_STATION_CONFIG_UPDATE
ON TB_M_STATION_CONFIG
AFTER UPDATE
AS
BEGIN
  SET NOCOUNT ON;

  DECLARE @assy4_active BIT, @assy5_active BIT;
  SELECT @assy4_active = IS_ACTIVE FROM TB_M_STATION_CONFIG WHERE STATION_NAME = 'MAN_ASSY_4';
  SELECT @assy5_active = IS_ACTIVE FROM TB_M_STATION_CONFIG WHERE STATION_NAME = 'MAN_ASSY_5';

  DECLARE @prefix VARCHAR(10);
  IF @assy5_active = 1 SET @prefix = '3';
  ELSE IF @assy4_active = 1 SET @prefix = '2';
  ELSE SET @prefix = '1';

  DECLARE @sn NVARCHAR(100), @suffix VARCHAR(10), @mandatory BIT, @active BIT;
  DECLARE cur CURSOR LOCAL FAST_FORWARD FOR
    SELECT STATION_NAME, STATION_ID_SUFFIX, IS_MANDATORY, IS_ACTIVE
    FROM TB_M_STATION_CONFIG ORDER BY SORT_ORDER;

  OPEN cur;
  FETCH NEXT FROM cur INTO @sn, @suffix, @mandatory, @active;

  WHILE @@FETCH_STATUS = 0
  BEGIN
    DECLARE @station_id VARCHAR(20);

    IF @mandatory = 1 OR (@sn = 'MAN_ASSY_4' AND @assy4_active = 1) OR (@sn = 'MAN_ASSY_5' AND @assy5_active = 1)
      SET @station_id = @prefix + '_' + @suffix;
    ELSE
      SET @station_id = NULL;

    MERGE TB_R_RFID_COMMAND AS t
    USING (
      SELECT @sn AS SN, 'READ' AS CMD UNION SELECT @sn, 'WRITE'
    ) AS s ON t.STATION_NAME = s.SN AND t.COMMAND = s.CMD
    WHEN MATCHED THEN
      UPDATE SET STATION_ID = @station_id, FDATETIME_MODIFIED = GETDATE()
    WHEN NOT MATCHED THEN
      INSERT (STATION_NAME, STATION_ID, COMMAND, FVALUE, FDATETIME_MODIFIED)
      VALUES (s.SN, @station_id, s.CMD, 0, GETDATE());

    FETCH NEXT FROM cur INTO @sn, @suffix, @mandatory, @active;
  END;

  CLOSE cur; DEALLOCATE cur;
END;
GO
