// src/index.ts
// ⚠️ IMPORTANT: OpenTelemetry must be initialized FIRST before any other imports
import dotenv from 'dotenv'
dotenv.config() // Load env vars before OpenTelemetry

import {
  initializeOpenTelemetry,
  shutdownOpenTelemetry,
} from './config/telemetry'
initializeOpenTelemetry() // Must run before app imports

import 'module-alias/register'
import { createServer } from 'http'
import { app } from './app'
import { setupWebSocket } from './ws/setup'
import { logStartupInfo } from './utils/startupLogger'
import { getConnection } from './utils/db'
import { gracefulShutdown } from './utils/gracefulShutdown'
import { initializeSentry } from './config/sentry'
import { createRedisClient, disconnectRedis } from './config/redis'
import { SERVER } from './config/constants'
import { loggers } from './utils/logger'

const PORT = Number(process.env.PORT) || SERVER.DEFAULT_PORT
const httpServer = createServer(app)

// ✅ Initialize Sentry (must be before app initialization)
initializeSentry(app)

// ✅ Initialize Redis cache
createRedisClient()

// Setup WebSocket
setupWebSocket(httpServer)

// ✅ Test database connection with retry (startup check)
;(async () => {
  try {
    await getConnection()
    loggers.db.info('Database connection established')
  } catch (err: any) {
    const errorMsg = err.code || err.message || 'Unknown error'
    loggers.db.fatal(
      { error: errorMsg },
      'Failed to connect to database after retries',
    )
    process.exit(1)
  }
})()

// Jalankan server dengan retry logic untuk handle EADDRINUSE
const startServer = (retries = 3, delay = 2000) => {
  httpServer.listen(PORT, '0.0.0.0', () => {
    logStartupInfo(PORT)
    loggers.server.info(
      {
        redis: process.env.REDIS_ENABLED === 'true',
        sentry: process.env.SENTRY_ENABLED === 'true',
        otel: process.env.OTEL_ENABLED === 'true',
      },
      'Phase 2 features initialized',
    )
  })

  httpServer.on('error', (err: NodeJS.ErrnoException) => {
    if (err.code === 'EADDRINUSE' && retries > 0) {
      loggers.server.warn(
        { port: PORT, retriesLeft: retries - 1, delay },
        'Port in use, retrying...',
      )
      setTimeout(() => {
        httpServer.close()
        startServer(retries - 1, delay)
      }, delay)
    } else if (err.code === 'EADDRINUSE') {
      loggers.server.fatal(
        { port: PORT },
        'Port still in use after retries. Please run: npm run stop',
      )
      process.exit(1)
    } else {
      const errorMsg = err.code || err.message || 'Unknown error'
      loggers.server.fatal({ error: errorMsg }, 'Server error')
      process.exit(1)
    }
  })
}

startServer()

// ✅ Graceful shutdown handlers with complete cleanup
const handleShutdown = async (signal: string) => {
  loggers.server.info({ signal }, 'Shutting down gracefully...')
  await Promise.all([disconnectRedis(), shutdownOpenTelemetry()])
  gracefulShutdown(httpServer, signal)
}

process.on('SIGTERM', () => handleShutdown('SIGTERM'))
process.on('SIGINT', () => handleShutdown('SIGINT'))

// Handle uncaught errors with structured logging
process.on('uncaughtException', (err: NodeJS.ErrnoException) => {
  const errorMsg =
    (err as NodeJS.ErrnoException).code || err.message || String(err)
  loggers.server.fatal({ error: errorMsg }, 'Uncaught Exception')
  handleShutdown('uncaughtException')
})

process.on('unhandledRejection', (reason: any) => {
  const errorMsg = reason?.code || reason?.message || String(reason)
  loggers.server.fatal({ error: errorMsg }, 'Unhandled Rejection')
  handleShutdown('unhandledRejection')
})
