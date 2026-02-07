// src/ws/poller.ws.ts
import sql from 'mssql'
import { getConnection } from '@/utils/db'
import { POLLING } from '@/config/constants'

// ---- Cursor helper ----
async function loadCursor(
  pool: sql.ConnectionPool,
  tableName: string,
): Promise<number | null> {
  const res = await pool
    .request()
    .input('table_name', sql.NVarChar, tableName)
    .query(`SELECT last_lsn FROM CDC_CURSOR WHERE table_name = @table_name`)
  if (!res.recordset[0]?.last_lsn) return null
  return Number(res.recordset[0].last_lsn)
}

async function saveCursor(
  pool: sql.ConnectionPool,
  tableName: string,
  version: number,
) {
  await pool
    .request()
    .input('table_name', sql.NVarChar, tableName)
    .input('version', sql.BigInt, version).query(`
      MERGE CDC_CURSOR AS target
      USING (SELECT @table_name AS table_name) AS source
      ON target.table_name = source.table_name
      WHEN MATCHED THEN
          UPDATE SET last_lsn = @version, updated_at = GETDATE()
      WHEN NOT MATCHED THEN
          INSERT (table_name, last_lsn) VALUES (@table_name, @version);
    `)
}

// ---- Reusable CT polling factory (ROOM-aware) ----
export function createCTPolling<T>({
  tableName,
  eventName,
  intervalMs = POLLING.INTERVAL_MS, // ✅ Use constant
  pollingLogic,
  onChangeDetected, // ✅ NEW: callback untuk cache invalidation
}: {
  tableName: string
  eventName: string
  intervalMs?: number
  pollingLogic: (pool: sql.ConnectionPool) => Promise<T>
  onChangeDetected?: () => Promise<void> // ✅ Optional async callback
}) {
  let pollingInterval: NodeJS.Timeout | null = null
  let lastVersion: number | null = null
  let retryCount = 0

  return {
    // 🔹 Terima io dan room
    start: async (io: any, room: string) => {
      if (pollingInterval) {
        console.log(
          `🔁 [WS] Polling for ${tableName} already running (room: ${room})`,
        )
        return {
          stop: () => {
            console.log(
              `ℹ️ [WS] Stop called on already running polling for ${tableName} (room: ${room})`,
            )
          },
        }
      }

      try {
        console.log(
          `🚀 [WS] Initializing CT polling for ${tableName} (room: ${room})`,
        )
        const pool = await getConnection()
        lastVersion = await loadCursor(pool, tableName)

        pollingInterval = setInterval(async () => {
          try {
            const pool = await getConnection()
            const result = await pool
              .request()
              .input('lastVersion', sql.BigInt, lastVersion ?? 0).query(`
            SELECT * 
            FROM CHANGETABLE(CHANGES dbo.[${tableName}], @lastVersion) AS c
          `)

            if (result.recordset.length > 0) {
              const maxVersion = Math.max(
                ...result.recordset.map((r) => Number(r.SYS_CHANGE_VERSION)),
              )
              await saveCursor(pool, tableName, maxVersion)
              lastVersion = maxVersion

              // ✅ INVALIDATE CACHE sebelum broadcast (ensure consistency)
              if (onChangeDetected) {
                await onChangeDetected()
              }

              const snapshot = await pollingLogic(pool)
              io.to(room).emit(eventName, snapshot)
              console.log(
                `📢 [WS] Broadcast ${tableName} to room ${room} (changes: ${result.recordset.length}, newVersion: ${maxVersion})`,
              )

              // ✅ Reset retry count on success
              retryCount = 0
            }
          } catch (err) {
            retryCount++
            console.error(
              `[WS] CT polling error for ${tableName} (retry ${retryCount}/${POLLING.MAX_RETRIES}):`,
              err,
            )

            // ✅ Stop polling if max retries exceeded
            if (retryCount >= POLLING.MAX_RETRIES) {
              console.error(
                `❌ [WS] Max retries exceeded for ${tableName}, stopping polling`,
              )
              if (pollingInterval) {
                clearInterval(pollingInterval)
                pollingInterval = null
              }
            }
          }
        }, intervalMs)

        return {
          stop: () => {
            if (pollingInterval) {
              clearInterval(pollingInterval)
              pollingInterval = null
              retryCount = 0
              console.log(
                `🛑 [WS] Stopped CT polling for ${tableName} (room: ${room})`,
              )
            }
          },
        }
      } catch (initError) {
        console.error(
          `💥 [WS] Failed to initialize polling for ${tableName}:`,
          initError,
        )
        return {
          stop: () => {
            console.log(
              `⚠️ [WS] Dummy stop for failed ${tableName} (room: ${room})`,
            )
          },
        }
      }
    },

    pollingLogic, // untuk snapshot awal
  }
}
