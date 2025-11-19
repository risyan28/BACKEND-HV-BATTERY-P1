// src/ws/ANDON/andonStatusPolling.ws.ts
import { createCTPolling } from '@/ws/poller.ws'

export const andonCallPolling = createCTPolling({
  tableName: 'TB_R_ANDON_STATUS',
  eventName: 'calls:update',

  pollingLogic: async (pool) => {
    const res = await pool.query(`
      SELECT STATION, CALL_TYPE
      FROM TB_R_ANDON_STATUS WHERE FVALUE = 1
      ORDER BY FID ASC
    `)

    // 🔍 DEBUG: Tampilkan hasil query di console BE
    // console.log('📞 [DEBUG] Active Calls from DB:', res.recordset)

    return res.recordset.map((row) => ({
      station: row.STATION,
      call_type: row.CALL_TYPE,
    }))
  },
})
