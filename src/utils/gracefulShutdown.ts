// src/utils/gracefulShutdown.ts
import { Server } from 'http'
import { getIO } from '@/ws/connectionHandler'
import prisma from '@/prisma'
import { SERVER } from '@/config/constants'

/**
 * Gracefully shutdown the server
 *
 * Steps:
 * 1. Stop accepting new connections
 * 2. Destroy all active connections (force close)
 * 3. Close all WebSocket connections
 * 4. Stop all active polling
 * 5. Close database connections
 * 6. Exit process
 */
export async function gracefulShutdown(
  httpServer: Server,
  signal: string,
): Promise<void> {
  console.log(`\n⚠️  Received ${signal}, starting graceful shutdown...`)

  // Set a timeout to force shutdown if graceful shutdown takes too long
  const forceShutdownTimer = setTimeout(() => {
    console.error('❌ Graceful shutdown timeout, forcing exit...')
    process.exit(1)
  }, SERVER.SHUTDOWN_TIMEOUT_MS)

  try {
    // 1. Stop accepting new connections & destroy active connections
    console.log('🔒 Closing HTTP server...')
    try {
      // Force close all active connections
      httpServer.closeAllConnections?.() // Node 18.2.0+

      await new Promise<void>((resolve, reject) => {
        httpServer.close((err) => {
          if (err) reject(err)
          else resolve()
        })
      })
      console.log('✅ HTTP server closed')
    } catch (err: any) {
      // Handle case where server is not running (common during nodemon restart)
      if (err.code === 'ERR_SERVER_NOT_RUNNING') {
        console.log('ℹ️  HTTP server already closed')
      } else {
        console.error('⚠️  Error closing HTTP server:', err.message)
      }
    }

    // 2. Close all WebSocket connections
    console.log('🔌 Closing WebSocket connections...')
    try {
      const io = getIO()
      io.close()
      console.log('✅ WebSocket connections closed')
    } catch (err) {
      console.log('ℹ️  No active WebSocket connections')
    }

    // 3. Close database connections
    console.log('💾 Closing database connections...')
    await prisma.$disconnect()
    console.log('✅ Database connections closed')

    clearTimeout(forceShutdownTimer)
    console.log('✅ Graceful shutdown completed')

    // Small delay to ensure port is fully released before process exits
    // This helps prevent EADDRINUSE errors in nodemon/dev mode
    await new Promise((resolve) => setTimeout(resolve, 500))

    process.exit(0)
  } catch (err) {
    console.error('❌ Error during graceful shutdown:', err)
    clearTimeout(forceShutdownTimer)
    process.exit(1)
  }
}
