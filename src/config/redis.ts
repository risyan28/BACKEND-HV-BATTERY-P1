// src/config/redis.ts
import Redis from 'ioredis'
import { loggers } from '@/utils/logger'

/**
 * Redis Cache Configuration
 *
 * Features:
 * - Connection pooling
 * - Auto-reconnect
 * - Error handling
 * - Optional (gracefully degrades if Redis unavailable)
 */

let redisClient: Redis | null = null

export function createRedisClient(): Redis | null {
  // Skip if Redis disabled
  if (process.env.REDIS_ENABLED !== 'true') {
    loggers.cache.info('Redis caching disabled')
    return null
  }

  const redisUrl = process.env.REDIS_URL || 'redis://localhost:6379'

  try {
    const client = new Redis(redisUrl, {
      maxRetriesPerRequest: 3,
      retryStrategy: (times) => {
        if (times > 3) {
          loggers.cache.error('Redis max retries exceeded, disabling cache')
          return null // Stop retrying
        }
        const delay = Math.min(times * 50, 2000)
        return delay
      },
      reconnectOnError: (err) => {
        const targetError = 'READONLY'
        if (err.message.includes(targetError)) {
          return true
        }
        return false
      },
    })

    client.on('connect', () => {
      loggers.cache.info('Redis connected successfully')
    })

    client.on('error', (err) => {
      loggers.cache.error({ err }, 'Redis connection error')
    })

    client.on('close', () => {
      loggers.cache.warn('Redis connection closed')
    })

    redisClient = client
    return client
  } catch (error) {
    loggers.cache.error({ error }, 'Failed to create Redis client')
    return null
  }
}

export function getRedisClient(): Redis | null {
  return redisClient
}

export async function disconnectRedis(): Promise<void> {
  if (redisClient) {
    await redisClient.quit()
    redisClient = null
    loggers.cache.info('Redis disconnected')
  }
}
