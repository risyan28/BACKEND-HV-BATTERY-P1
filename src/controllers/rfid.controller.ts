import { Request, Response, NextFunction } from 'express'
import { getConnection } from '@/utils/db'

export async function getRfidMap(req: Request, res: Response, next: NextFunction) {
  try {
    const { station } = req.query
    const pool = await getConnection()
    let query = `SELECT FID, STATION_NAME, FIELD_NAME, VALUE_ASCII,
      CONVERT(varchar(19), READ_TIME, 120) AS READ_TIME,
      CONVERT(varchar(19), WRITE_TIME, 120) AS WRITE_TIME
      FROM DB_TMMIN1_KRW_RFID_V680S.dbo.TB_R_RFID_MAP`
    if (station) {
      query += ` WHERE STATION_NAME = @station`
    }
    const request = pool.request()
    if (station) {
      request.input('station', station)
    }
    const result = await request.query(query)
    res.json({ success: true, data: result.recordset })
  } catch (err) {
    next(err)
  }
}

export async function updateRfidMapValue(req: Request, res: Response, next: NextFunction) {
  try {
    const { fid, valueAscii } = req.body
    if (!fid) {
      return res.status(400).json({ success: false, message: 'FID is required' })
    }
    const pool = await getConnection()
    await pool.request()
      .input('fid', fid)
      .input('val', valueAscii ?? null)
      .query('UPDATE DB_TMMIN1_KRW_RFID_V680S.dbo.TB_R_RFID_MAP SET VALUE_ASCII = @val, WRITE_TIME = GETDATE() WHERE FID = @fid')
    res.json({ success: true, message: 'RFID map value updated successfully' })
  } catch (err) {
    next(err)
  }
}

export async function triggerRfidCommand(req: Request, res: Response, next: NextFunction) {
  try {
    const { stationName, command } = req.body // command: 'READ' or 'WRITE'
    if (!stationName || !command) {
      return res.status(400).json({ success: false, message: 'stationName and command are required' })
    }
    const pool = await getConnection()
    // Upsert or insert into TB_R_RFID_COMMAND
    await pool.request()
      .input('station', stationName)
      .input('cmd', command)
      .query(`
        IF EXISTS (SELECT 1 FROM DB_TMMIN1_KRW_PIS_HV_BATTERY.dbo.TB_R_RFID_COMMAND WHERE STATION_NAME = @station AND COMMAND = @cmd)
          UPDATE DB_TMMIN1_KRW_PIS_HV_BATTERY.dbo.TB_R_RFID_COMMAND SET FVALUE = 1, FDATETIME_MODIFIED = GETDATE() WHERE STATION_NAME = @station AND COMMAND = @cmd
        ELSE
          INSERT INTO DB_TMMIN1_KRW_PIS_HV_BATTERY.dbo.TB_R_RFID_COMMAND (STATION_NAME, COMMAND, FVALUE, FDATETIME_MODIFIED) VALUES (@station, @cmd, 1, GETDATE())
      `)
    res.json({ success: true, message: `Command ${command} triggered for ${stationName}` })
  } catch (err) {
    next(err)
  }
}
