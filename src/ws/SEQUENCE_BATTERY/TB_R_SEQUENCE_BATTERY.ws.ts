// src\ws\SEQUENCE_BATTERY\TB_R_SEQUENCE_BATTERY.ws.ts

import { createCTPolling } from '@/ws/poller.ws'
import { formatDate, formatDateTime } from '@/utils/date'

function mapSequence(s: any) {
  return {
    ...s,
    FSEQ_DATE: formatDate(s.FSEQ_DATE),
    FTIME_RECEIVED: formatDateTime(s.FTIME_RECEIVED),
    FTIME_PRINTED: formatDateTime(s.FTIME_PRINTED),
    FTIME_COMPLETED: formatDateTime(s.FTIME_COMPLETED),
    FALC_DATA:
      s.FALC_DATA && s.FALC_DATA.trim() !== '' ? 'ALC' : 'INJECT MANUAL',
  }
}

export const sequencePolling = createCTPolling({
  tableName: 'TB_R_SEQUENCE_BATTERY',
  eventName: 'sequences:update',
  pollingLogic: async (pool) => {
    // ❗ snapshot logic fleksibel, bisa disesuaikan tabel lain
    const currentRes = await pool.query(`
      SELECT TOP 1 * 
      FROM TB_R_SEQUENCE_BATTERY
      WHERE FSTATUS = 0 OR (FSTATUS = 1 AND FTIME_PRINTED IS NOT NULL)
      ORDER BY FID_ADJUST ASC
    `)
    const current = currentRes.recordset[0]
      ? mapSequence(currentRes.recordset[0])
      : null

    const queueRes = await pool.query(`
      SELECT TOP 500 * 
      FROM TB_R_SEQUENCE_BATTERY
      WHERE FSTATUS = 0 AND FID <> ${current?.FID ?? -1}
      ORDER BY FID_ADJUST ASC
    `)

    const completedRes = await pool.query(`
      SELECT TOP 100 * 
      FROM TB_R_SEQUENCE_BATTERY
      WHERE FSTATUS = 2
      ORDER BY FTIME_COMPLETED DESC
    `)

    const parkedRes = await pool.query(`
      SELECT * 
      FROM TB_R_SEQUENCE_BATTERY
      WHERE FSTATUS = 3
      ORDER BY FID_ADJUST ASC
    `)

    return {
      current,
      queue: queueRes.recordset.map(mapSequence),
      completed: completedRes.recordset.map(mapSequence),
      parked: parkedRes.recordset.map(mapSequence),
    }
  },
})
