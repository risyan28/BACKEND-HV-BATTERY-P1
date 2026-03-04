// src/ws/connectionHandler.ts
import { Server, Socket } from 'socket.io'
import { getConnection } from '@/utils/db'
import { CORS_DEFAULTS } from '@/config/constants'

let io: Server | null = null

// Simpan instance polling aktif per topik
const activePollings = new Map<string, { stop: () => void }>()

// Mapping topik ke konfigurasi
const topicConfig = new Map<string, { eventName: string; pollingModule: any }>()

export function initConnectionHandler(
  server: any,
  pollings: { name: string; module: any; eventName: string }[],
) {
  // ✅ CORS Configuration with whitelist for WebSocket
  const allowedOrigins = process.env.ALLOWED_ORIGINS
    ? process.env.ALLOWED_ORIGINS.split(',').map((origin) => origin.trim())
    : ['*']

  io = new Server(server, {
    cors: {
      origin: allowedOrigins.includes('*') ? '*' : allowedOrigins,
      credentials: true,
      maxAge: CORS_DEFAULTS.MAX_AGE,
    },
    transports: ['websocket'],
  })

  // Daftarkan konfigurasi per topik
  for (const { name, module, eventName } of pollings) {
    topicConfig.set(name, { eventName, pollingModule: module })
  }

  io.on('connection', async (socket: Socket) => {
    console.log(`✅ Client connected: ${socket.id}`)

    // 📥 Subscribe ke topik
    socket.on('subscribe', async (topic: string) => {
      const config = topicConfig.get(topic)
      if (!config) {
        console.warn(`⚠️ Unknown subscription topic: ${topic}`)
        return
      }

      socket.join(topic)
      console.log(`📥 Client ${socket.id} subscribed to: ${topic}`)

      // Jika subscriber pertama, mulai polling
      const currentSubscribers = io!.sockets.adapter.rooms.get(topic)?.size || 0
      if (currentSubscribers === 1) {
        try {
          const pollingResult = await config.pollingModule.start(io!, topic)
          if (pollingResult?.stop) {
            // Hanya simpan jika ini polling baru (belum ada sebelumnya)
            if (!activePollings.has(topic)) {
              activePollings.set(topic, pollingResult)
            }
          } else {
            console.error(`[WS] Invalid polling result for ${topic}`)
          }
        } catch (err: any) {
          const errorMsg = err.code || err.message || 'Unknown error'
          console.error(`❌ Failed to start polling for ${topic}: ${errorMsg}`)
        }
      } else {
        // ✅ ENHANCEMENT: Jika bukan subscriber pertama (polling sudah jalan),
        // tetap kirim snapshot FRESH untuk client yang baru subscribe
        console.log(
          `🔄 Client ${socket.id} joining existing room ${topic} (${currentSubscribers} subscribers)`,
        )
      }

      // Kirim snapshot TERBARU ke client yang baru subscribe
      try {
        const snapshot = await config.pollingModule.pollingLogic(
          await getConnection(),
        )
        socket.emit(config.eventName, snapshot)
        console.log(
          `📤 Sent initial snapshot to ${socket.id} for topic: ${topic}`,
        )
      } catch (err: any) {
        const errorMsg = err.code || err.message || 'Unknown error'
        console.error(
          `⚠️ [WS] Snapshot error for ${topic} (${socket.id}): ${errorMsg}`,
        )
        socket.emit(`${config.eventName}:error`, {
          message: 'Failed to fetch initial data. Database may be unavailable.',
          error: errorMsg,
        })
      }
    })

    // ✅ NEW: Manual sync request untuk force refresh data
    socket.on('sync', async (topic: string) => {
      const config = topicConfig.get(topic)
      if (!config) {
        console.warn(`⚠️ Unknown sync topic: ${topic}`)
        return
      }

      try {
        const snapshot = await config.pollingModule.pollingLogic(
          await getConnection(),
        )
        socket.emit(config.eventName, snapshot)
        console.log(`🔄 Manual sync sent to ${socket.id} for topic: ${topic}`)
      } catch (err: any) {
        const errorMsg = err.code || err.message || 'Unknown error'
        console.error(
          `⚠️ [WS] Sync error for ${topic} (${socket.id}): ${errorMsg}`,
        )
        socket.emit(`${config.eventName}:error`, {
          message: 'Failed to sync data. Database may be unavailable.',
          error: errorMsg,
        })
      }
    })

    // 📤 Unsubscribe
    socket.on('unsubscribe', (topic: string) => {
      socket.leave(topic)
      console.log(`📤 Client ${socket.id} unsubscribed from: ${topic}`)

      const currentSubscribers = io!.sockets.adapter.rooms.get(topic)?.size || 0
      if (currentSubscribers === 0) {
        const polling = activePollings.get(topic)
        if (polling) {
          polling.stop()
          activePollings.delete(topic)
        }
      }
    })

    socket.on('disconnect', () => {
      console.log(`❌ Client disconnected: ${socket.id}`)
    })
  })

  return io
}

export function getIO(): Server {
  if (!io) throw new Error('⚠️ Socket.IO not initialized!')
  return io
}
