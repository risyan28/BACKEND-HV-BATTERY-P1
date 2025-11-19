// src/index.ts
import 'module-alias/register';
import dotenv from 'dotenv'
import { createServer } from 'http'
import app from '@/app'
import { setupWebSocket } from './ws/setup'
import { logStartupInfo } from './utils/startupLogger'
import { getConnection } from './utils/db'

dotenv.config()

const PORT = Number(process.env.PORT) || 4001
const httpServer = createServer(app)

// Setup WebSocket
setupWebSocket(httpServer)

// Test koneksi database
getConnection().catch((err) => {
  console.error('[DATABASE] Failed to connect:', err)
  process.exit(1)
})

// Jalankan server
httpServer.listen(PORT, '0.0.0.0', () => {
  logStartupInfo(PORT)
})
