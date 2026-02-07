// src/middleware/__tests__/rateLimiter.test.ts
import { describe, it, expect } from 'vitest'
import { apiLimiter, strictLimiter, lenientLimiter } from '../rateLimiter'

describe('Rate Limiter Middleware', () => {
  describe('apiLimiter', () => {
    it('should be defined', () => {
      expect(apiLimiter).toBeDefined()
      expect(typeof apiLimiter).toBe('function')
    })
  })

  describe('strictLimiter', () => {
    it('should be defined', () => {
      expect(strictLimiter).toBeDefined()
      expect(typeof strictLimiter).toBe('function')
    })
  })

  describe('lenientLimiter', () => {
    it('should be defined', () => {
      expect(lenientLimiter).toBeDefined()
      expect(typeof lenientLimiter).toBe('function')
    })
  })
})
