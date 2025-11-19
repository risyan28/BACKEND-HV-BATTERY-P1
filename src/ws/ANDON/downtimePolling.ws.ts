// src/ws/ANDON/downtimePolling.ws.ts
import { createCTPolling } from '@/ws/poller.ws'

export const downtimePolling = createCTPolling({
  tableName: 'TB_R_DOWNTIME_LOG',
  eventName: 'downtime:update',

  pollingLogic: async (pool) => {
    const res = await pool.query(`
      SELECT 
        STATION AS station,
        TOTAL_DOWNTIME AS times,
        ISNULL(DURATION_MINUTE, 0) AS minutes
      FROM TB_R_DOWNTIME_LOG
      ORDER BY FID ASC
    `)

    // 🔍 DEBUG: Tampilkan hasil query di console BE
     // console.log('📞 [DEBUG] processStatuses from DB:', res.recordset)

    // ⚠️ Ubah nama kolom ke format yang diharapkan FE
    return res.recordset.map((row) => ({
      station: row.station, // ← bukan STATION
      times: row.times, // ← bukan TOTAL_DOWNTIME
      minutes: row.minutes, // ← bukan DURATION_MINUTE
    }))
  },
})
