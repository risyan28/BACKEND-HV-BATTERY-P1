import sql from 'mssql'
import { DATABASE } from '@/config/constants'

const config: sql.config = {
  user: process.env.MSSQL_USER,
  password: process.env.MSSQL_PASSWORD,
  server: process.env.MSSQL_SERVER || 'localhost',
  database: process.env.MSSQL_DATABASE,
  port: Number(process.env.MSSQL_PORT) || 1433,
  options: {
    encrypt: false,
    trustServerCertificate: true,
  },
  pool: {
    max: DATABASE.POOL.MAX,
    min: DATABASE.POOL.MIN,
    idleTimeoutMillis: DATABASE.POOL.IDLE_TIMEOUT_MS,
  },
  // ✅ Add connection timeout
  connectionTimeout: 15000,
  requestTimeout: 30000,
}

let pool: sql.ConnectionPool | null = null
let isConnecting = false

/**
 * Get database connection with retry logic
 * @param retryCount - Current retry attempt (internal use)
 */
export async function getConnection(
  retryCount = 0,
): Promise<sql.ConnectionPool> {
  // ✅ Return existing pool if available
  if (pool && pool.connected) return pool

  // ✅ Prevent multiple simultaneous connection attempts
  if (isConnecting) {
    // Wait for ongoing connection attempt
    await new Promise((resolve) => setTimeout(resolve, 1000))
    if (pool && pool.connected) return pool
  }

  isConnecting = true

  try {
    // ✅ Close existing pool if not connected
    if (pool && !pool.connected) {
      await pool.close().catch(() => {})
      pool = null
    }

    pool = await sql.connect(config)
    console.log(
      `✅ [MSSQL] Connected → ${config.server}:${config.port} / DB: ${config.database}`,
    )
    isConnecting = false
    return pool
  } catch (err: any) {
    isConnecting = false

    // ✅ Retry logic with exponential backoff
    if (retryCount < DATABASE.RETRY.MAX_ATTEMPTS) {
      const delay = Math.min(
        DATABASE.RETRY.INITIAL_DELAY_MS *
          Math.pow(DATABASE.RETRY.BACKOFF_MULTIPLIER, retryCount),
        DATABASE.RETRY.MAX_DELAY_MS,
      )

      console.warn(
        `⚠️ [MSSQL] Connection attempt ${retryCount + 1}/${DATABASE.RETRY.MAX_ATTEMPTS} failed. Retrying in ${delay}ms...`,
      )

      await new Promise((resolve) => setTimeout(resolve, delay))
      return getConnection(retryCount + 1)
    }

    // ✅ Max retries exceeded
    const errorMsg = err.code || err.message || 'Unknown database error'
    console.error(
      `❌ [MSSQL] Failed to connect after ${DATABASE.RETRY.MAX_ATTEMPTS} attempts: ${errorMsg}`,
    )

    // ✅ Throw clean error without full stack trace
    const cleanError = new Error(`Database connection failed: ${errorMsg}`)
    cleanError.name = 'DatabaseConnectionError'
    throw cleanError
  }
}
