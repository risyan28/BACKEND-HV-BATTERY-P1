// src\ws\ANDON\andonSummaryPolling.ws.ts

import { createCTPolling } from '@/ws/poller.ws'

export const andonSummaryPolling = createCTPolling({
  tableName: 'TB_R_ANDON_GLOBAL',
  eventName: 'summary:update',

  pollingLogic: async (pool) => {
    // 🔹 Ambil snapshot data summary
    const res = await pool.query(`
      SELECT 
        MAX(CASE WHEN FNAME = 'TARGET' THEN FVALUE END) AS [Target],
        MAX(CASE WHEN FNAME = 'PLAN' THEN FVALUE END) AS [Plan],
        MAX(CASE WHEN FNAME = 'ACT_CKD' THEN FVALUE END) AS [ActCkd],
        MAX(CASE WHEN FNAME = 'ACT_ASSY' THEN FVALUE END) AS [ActAssy],
        MAX(CASE WHEN FNAME = 'EFF' THEN FVALUE END) AS [Eff],
        MAX(CASE WHEN FNAME = 'TAKTIME' THEN FVALUE END) AS [TaktTime],
        MAX(FUPDATE) AS [UpdatedAt]
      FROM dbo.TB_R_ANDON_GLOBAL;
    `)

    const row = res.recordset[0] ?? {}

    // 🚦 Bentuk data yang akan di-emit
    const summary = {
      Target: Number(row.Target ?? 0),
      Plan: Number(row.Plan ?? 0),
      ActCkd: Number(row.ActCkd ?? 0),
      ActAssy: Number(row.ActAssy ?? 0),
      Eff: Number(row.Eff ?? 0),
      TaktTime: Number(row.TaktTime ?? 0),
      UpdatedAt: row.UpdatedAt || null,
    }

    return summary
  },
})
