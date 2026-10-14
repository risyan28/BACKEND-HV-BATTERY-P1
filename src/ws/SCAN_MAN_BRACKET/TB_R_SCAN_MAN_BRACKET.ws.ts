// src/ws/SCAN_MAN_BRACKET/TB_R_SCAN_MAN_BRACKET.ws.ts
// Simple polling: checks TB_R_SCAN_MAN_BRACKET for FLAG=0 rows every 1s.
// When a new scan event is detected (UPDATED_AT changed), emits
// 'man-bracket:serial-scan' to room 'man-bracket'.
// NOT using Change Tracking — just interval-based since the trigger writes directly.

import { getConnection } from '@/utils/db'

const POLL_INTERVAL_MS = 1000
let lastEmittedAt: Date | null = null

async function pollingLogic(pool: any) {
  try {
    const result = await pool.query(`
      SELECT TOP 1 FID, BARCODE, FLAG, UPDATED_AT
      FROM TB_R_SCAN_MAN_BRACKET
      WHERE FLAG = 0
      ORDER BY FID ASC
    `)

    const rows = result.recordset ?? []
    if (rows.length === 0) return null

    const row = rows[0]
    const barcode = row.BARCODE?.trim() ?? ''
    const updatedAt = row.UPDATED_AT ? new Date(row.UPDATED_AT) : null

    if (!barcode) return null

    // Only emit if UPDATED_AT changed (new scan event from trigger)
    if (lastEmittedAt && updatedAt && updatedAt <= lastEmittedAt) return null

    lastEmittedAt = updatedAt
    return { barcode }
  } catch (err: any) {
    console.error('[WS] SCAN_MAN_BRACKET poll error:', err.message)
    return null
  }
}

export const scanManBracketPolling = {
  start: async (io: any, topic: string) => {
    console.log(`[WS] Starting SCAN_MAN_BRACKET polling for topic: ${topic}`)

    const timer = setInterval(async () => {
      try {
        const pool = await getConnection()
        const data = await pollingLogic(pool)
        if (data) {
          io.to('man-bracket').emit('man-bracket:serial-scan', data)
          console.log('[WS] Emitted man-bracket:serial-scan:', data.barcode)
        }
      } catch (err: any) {
        console.error('[WS] SCAN_MAN_BRACKET poll error:', err.message)
      }
    }, POLL_INTERVAL_MS)

    return {
      stop: () => {
        clearInterval(timer)
        console.log('[WS] Stopped SCAN_MAN_BRACKET polling')
      },
    }
  },

  pollingLogic,
}
