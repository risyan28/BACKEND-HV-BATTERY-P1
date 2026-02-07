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

// Test koneksi database
getConnection().catch((err) => {
  loggers.db.error({ err }, 'Failed to connect to database')
  process.exit(1)
})

// Jalankan server
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

// ✅ Graceful shutdown handlers with complete cleanup
const handleShutdown = async (signal: string) => {
  loggers.server.info({ signal }, 'Shutting down gracefully...')
  await Promise.all([disconnectRedis(), shutdownOpenTelemetry()])
  gracefulShutdown(httpServer, signal)
}

process.on('SIGTERM', () => handleShutdown('SIGTERM'))
process.on('SIGINT', () => handleShutdown('SIGINT'))

// Handle uncaught errors with structured logging
process.on('uncaughtException', (err) => {
  loggers.server.fatal({ err }, 'Uncaught Exception')
  handleShutdown('uncaughtException')
})

process.on('unhandledRejection', (reason, promise) => {
  loggers.server.fatal({ reason, promise }, 'Unhandled Rejection')
  handleShutdown('unhandledRejection')
})
