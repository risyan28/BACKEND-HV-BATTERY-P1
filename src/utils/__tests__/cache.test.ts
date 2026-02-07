// src/utils/__tests__/cache.test.ts
import { describe, it, expect, beforeEach, vi } from 'vitest'
import { cache } from '../cache'

describe('CacheService', () => {
  describe('getOrSet', () => {
    it('should execute callback when cache is disabled', async () => {
      // Mock Redis as disabled
      process.env.REDIS_ENABLED = 'false'

      const callback = vi.fn(async () => ({ data: 'test-data' }))
      const result = await cache.getOrSet('test-key', callback, 60)

      expect(callback).toHaveBeenCalled()
      expect(result).toEqual({ data: 'test-data' })
    })

    it('should handle callback errors gracefully', async () => {
      process.env.REDIS_ENABLED = 'false'

      const callback = vi.fn(async () => {
        throw new Error('Callback error')
      })

      await expect(cache.getOrSet('test-key', callback, 60)).rejects.toThrow(
        'Callback error',
      )
    })
  })

  describe('set', () => {
    it('should not throw when Redis is disabled', async () => {
      process.env.REDIS_ENABLED = 'false'
      await expect(
        cache.set('test-key', { data: 'value' }, 60),
      ).resolves.not.toThrow()
    })
  })

  describe('get', () => {
    it('should return null when Redis is disabled', async () => {
      process.env.REDIS_ENABLED = 'false'
      const result = await cache.get('test-key')
      expect(result).toBeNull()
    })
  })

  describe('del', () => {
    it('should not throw when Redis is disabled', async () => {
      process.env.REDIS_ENABLED = 'false'
      await expect(cache.del('test-key')).resolves.not.toThrow()
    })
  })

  describe('delPattern', () => {
    it('should not throw when Redis is disabled', async () => {
      process.env.REDIS_ENABLED = 'false'
      await expect(cache.delPattern('test-*')).resolves.not.toThrow()
    })
  })

  describe('isAvailable', () => {
    it('should return false when Redis is disabled', () => {
      process.env.REDIS_ENABLED = 'false'
      const available = cache.isAvailable()
      expect(typeof available).toBe('boolean')
    })
  })
})
