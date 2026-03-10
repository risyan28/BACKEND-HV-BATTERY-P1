// src/utils/cache.ts
import { getRedisClient } from '@/config/redis'
import { loggers } from '@/utils/logger'

/**
 * Cache utility with Redis fallback
 *
 * Features:
 * - Automatic JSON serialization/deserialization
 * - TTL support
 * - Graceful degradation (continues without cache if Redis unavailable)
 * - Type-safe
 */

interface MemoryCacheEntry {
  data: unknown
  expiresAt: number
}

export class CacheService {
  private redis = getRedisClient()
  private memoryCache = new Map<string, MemoryCacheEntry>()

  /**
   * Get cached value
   */
  async get<T>(key: string): Promise<T | null> {
    // In-memory fallback
    if (!this.redis) {
      const entry = this.memoryCache.get(key)
      if (entry) {
        if (Date.now() < entry.expiresAt) {
          loggers.cache.debug({ key }, 'Cache HIT (memory)')
          return entry.data as T
        }
        this.memoryCache.delete(key)
      }
      return null
    }

    try {
      const cached = await this.redis.get(key)
      if (!cached) return null

      const data = JSON.parse(cached) as T
      loggers.cache.debug({ key }, 'Cache HIT')
      return data
    } catch (error) {
      loggers.cache.warn({ error, key }, 'Cache GET failed')
      return null
    }
  }

  /**
   * Set cached value with optional TTL (in seconds)
   */
  async set<T>(key: string, value: T, ttl?: number): Promise<boolean> {
    // In-memory fallback
    if (!this.redis) {
      const expiresAt = Date.now() + (ttl ?? 60) * 1000
      this.memoryCache.set(key, { data: value, expiresAt })
      loggers.cache.debug({ key, ttl }, 'Cache SET (memory)')
      return true
    }

    try {
      const serialized = JSON.stringify(value)

      if (ttl) {
        await this.redis.setex(key, ttl, serialized)
      } else {
        await this.redis.set(key, serialized)
      }

      loggers.cache.debug({ key, ttl }, 'Cache SET')
      return true
    } catch (error) {
      loggers.cache.warn({ error, key }, 'Cache SET failed')
      return false
    }
  }

  /**
   * Delete cached value
   */
  async del(key: string): Promise<boolean> {
    if (!this.redis) return false

    try {
      await this.redis.del(key)
      loggers.cache.debug({ key }, 'Cache DEL')
      return true
    } catch (error) {
      loggers.cache.warn({ error, key }, 'Cache DEL failed')
      return false
    }
  }

  /**
   * Delete multiple keys by pattern
   */
  async delPattern(pattern: string): Promise<number> {
    if (!this.redis) return 0

    try {
      const keys = await this.redis.keys(pattern)
      if (keys.length === 0) return 0

      await this.redis.del(...keys)
      loggers.cache.debug({ pattern, count: keys.length }, 'Cache DEL pattern')
      return keys.length
    } catch (error) {
      loggers.cache.warn({ error, pattern }, 'Cache DEL pattern failed')
      return 0
    }
  }

  /**
   * Get or Set pattern (cache-aside)
   * If cached, return cached value
   * If not cached, fetch from callback and cache it
   */
  async getOrSet<T>(
    key: string,
    fetchFn: () => Promise<T>,
    ttl?: number,
  ): Promise<T> {
    // Try cache first
    const cached = await this.get<T>(key)
    if (cached !== null) {
      return cached
    }

    // Cache miss - fetch from source
    loggers.cache.debug({ key }, 'Cache MISS - fetching from source')
    const data = await fetchFn()

    // Cache the result
    await this.set(key, data, ttl)

    return data
  }

  /**
   * Check if Redis is available
   */
  isAvailable(): boolean {
    return this.redis !== null && this.redis.status === 'ready'
  }
}

// Export singleton instance
export const cache = new CacheService()
