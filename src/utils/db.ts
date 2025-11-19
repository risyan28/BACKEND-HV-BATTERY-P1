import sql from 'mssql'

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
    max: 10,
    min: 0,
    idleTimeoutMillis: 30000,
  },
}

let pool: sql.ConnectionPool | null = null

export async function getConnection() {
  if (pool) return pool

  try {
    pool = await sql.connect(config)
    console.log(
      `[MSSQL] Connected → ${config.server}:${config.port} / DB: ${config.database}`
    )
    return pool
  } catch (err) {
    console.error('[MSSQL] Connection error:', err)
    throw err
  }
}
