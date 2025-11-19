// src/ws/ANDON/andonStatusPolling.ws.ts
import { createCTPolling } from '@/ws/poller.ws'

export const posStatusPolling = createCTPolling({
  tableName: 'TB_R_POS_STATUS',
  eventName: 'processes:update',

  pollingLogic: async (pool) => {
    const res = await pool.query(`
      SELECT STATION, STATUS, SOURCE
      FROM TB_R_POS_STATUS WHERE FVALUE = 1
      ORDER BY FID ASC
    `)

    // 🔍 DEBUG: Tampilkan hasil query di console BE
    // console.log('📞 [DEBUG] processStatuses from DB:', res.recordset)

    return res.recordset.map((row) => ({
      station: row.STATION,
      status: row.STATUS,
      source: row.SOURCE,
    }))
  },
})
