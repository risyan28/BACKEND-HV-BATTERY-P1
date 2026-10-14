import { getConnection } from '@/utils/db'

const POLL_INTERVAL_MS = 2000
let lastPayload: string | null = null

async function pollingLogic(pool: any) {
  try {
    const result = await pool.query(`
      SELECT
        MAX(CASE WHEN FNAME = 'STD STOCK' THEN FVALUE END) AS StdStock,
        MAX(CASE WHEN FNAME = 'BUFFER STOCK' THEN FVALUE END) AS BufferStock
      FROM dbo.TB_R_ANDON_GLOBAL
      WHERE FNAME IN ('STD STOCK', 'BUFFER STOCK')
    `)

    const row = result.recordset?.[0]
    if (!row) return null

    const payload = {
      stdStock: Number(row.StdStock) || 0,
      bufferStock: Number(row.BufferStock) || 0,
    }

    const signature = JSON.stringify(payload)
    if (signature === lastPayload) return null
    lastPayload = signature

    return payload
  } catch (err: any) {
    console.error('[WS] STOCK poll error:', err.message)
    return null
  }
}

export const stockPolling = {
  start: async (io: any) => {
    console.log('[WS] Starting stock polling (TB_R_ANDON_GLOBAL)')

    const timer = setInterval(async () => {
      try {
        const pool = await getConnection()
        const data = await pollingLogic(pool)
        if (data) {
          io.to('man-bracket').emit('man-bracket:stock', data)
          console.log('[WS] Emitted man-bracket:stock:', data)
        }
      } catch (err: any) {
        console.error('[WS] stock poll error:', err.message)
      }
    }, POLL_INTERVAL_MS)

    return {
      stop: () => {
        clearInterval(timer)
        console.log('[WS] Stopped stock polling')
      },
    }
  },

  pollingLogic,
}
