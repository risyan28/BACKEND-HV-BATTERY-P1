// src/utils/__tests__/logger.test.ts
import { describe, it, expect, beforeEach } from 'vitest'
import { createLogger, loggers } from '../logger'

describe('Logger Utils', () => {
  describe('createLogger', () => {
    it('should create a logger instance with context', () => {
      const logger = createLogger('test-context')
      expect(logger).toBeDefined()
      expect(logger.info).toBeDefined()
      expect(logger.error).toBeDefined()
      expect(logger.warn).toBeDefined()
      expect(logger.debug).toBeDefined()
    })

    it('should create different logger instances for different contexts', () => {
      const logger1 = createLogger('context1')
      const logger2 = createLogger('context2')
      expect(logger1).not.toBe(logger2)
    })
  })

  describe('Pre-configured loggers', () => {
    it('should have db logger', () => {
      expect(loggers.db).toBeDefined()
    })

    it('should have ws logger', () => {
      expect(loggers.ws).toBeDefined()
    })

    it('should have api logger', () => {
      expect(loggers.api).toBeDefined()
    })

    it('should have cache logger', () => {
      expect(loggers.cache).toBeDefined()
    })

    it('should have server logger', () => {
      expect(loggers.server).toBeDefined()
    })
  })
})
