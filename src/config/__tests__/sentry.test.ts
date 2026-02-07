// src/config/__tests__/sentry.test.ts
import { describe, it, expect, vi, beforeEach } from 'vitest'
import { captureException, setUser, clearUser } from '../sentry'

describe('Sentry Configuration', () => {
  beforeEach(() => {
    // Disable Sentry for tests
    process.env.SENTRY_ENABLED = 'false'
  })

  describe('captureException', () => {
    it('should not throw when Sentry is disabled', () => {
      const error = new Error('Test error')
      expect(() => captureException(error)).not.toThrow()
    })

    it('should handle context parameter', () => {
      const error = new Error('Test error')
      const context = { userId: '123', action: 'test' }
      expect(() => captureException(error, context)).not.toThrow()
    })
  })

  describe('setUser', () => {
    it('should not throw when Sentry is disabled', () => {
      const user = {
        id: '123',
        username: 'testuser',
        email: 'test@example.com',
      }
      expect(() => setUser(user)).not.toThrow()
    })
  })

  describe('clearUser', () => {
    it('should not throw when Sentry is disabled', () => {
      expect(() => clearUser()).not.toThrow()
    })
  })
})
