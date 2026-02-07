// src/config/__tests__/telemetry.test.ts
import { describe, it, expect, beforeEach } from 'vitest'
import { initializeOpenTelemetry, shutdownOpenTelemetry } from '../telemetry'

describe('OpenTelemetry Configuration', () => {
  beforeEach(() => {
    // Disable OpenTelemetry for tests
    process.env.OTEL_ENABLED = 'false'
  })

  describe('initializeOpenTelemetry', () => {
    it('should not throw when disabled', () => {
      expect(() => initializeOpenTelemetry()).not.toThrow()
    })

    it('should handle missing configuration gracefully', () => {
      delete process.env.OTEL_SERVICE_NAME
      delete process.env.OTEL_EXPORTER_OTLP_ENDPOINT
      expect(() => initializeOpenTelemetry()).not.toThrow()
    })
  })

  describe('shutdownOpenTelemetry', () => {
    it('should not throw when SDK is not initialized', async () => {
      await expect(shutdownOpenTelemetry()).resolves.not.toThrow()
    })
  })
})
