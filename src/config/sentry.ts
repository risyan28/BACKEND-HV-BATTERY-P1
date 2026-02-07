// src/config/sentry.ts
import * as Sentry from '@sentry/node'
import { nodeProfilingIntegration } from '@sentry/profiling-node'
import { Express } from 'express'
import { loggers } from '@/utils/logger'

/**
 * Sentry Error Tracking Configuration
 *
 * Features:
 * - Real-time error tracking
 * - Performance monitoring
 * - Release tracking
 * - User context
 * - Environment-aware
 */

export function initializeSentry(app: Express) {
  // Skip if Sentry disabled or no DSN configured
  if (!process.env.SENTRY_DSN || process.env.SENTRY_ENABLED !== 'true') {
    loggers.server.info('Sentry error tracking disabled')
    return
  }

  try {
    Sentry.init({
      dsn: process.env.SENTRY_DSN,
      integrations: [
        // ✅ Sentry v10+ integrations (no parameters)
        Sentry.httpIntegration(),
        Sentry.expressIntegration(),
        nodeProfilingIntegration(),
      ],
      // Performance Monitoring
      tracesSampleRate: Number(process.env.SENTRY_TRACES_SAMPLE_RATE) || 0.1, // 10% of transactions

      // Profiling
      profilesSampleRate:
        Number(process.env.SENTRY_PROFILES_SAMPLE_RATE) || 0.1, // 10% of transactions

      // Environment
      environment: process.env.NODE_ENV || 'development',

      // Release tracking
      release: process.env.npm_package_version || '1.0.0',

      // Before send hook - filter out sensitive data
      beforeSend(event, hint) {
        // Don't send health check errors
        if (event.request?.url?.includes('/api/health')) {
          return null
        }

        // Filter sensitive headers
        if (event.request?.headers) {
          delete event.request.headers.authorization
          delete event.request.headers.cookie
        }

        // Filter sensitive data from body
        if (event.request?.data) {
          const data = event.request.data as any
          if (data.password) data.password = '[FILTERED]'
          if (data.token) data.token = '[FILTERED]'
        }

        return event
      },
    })

    // ✅ Setup Express error handler (v10+ automatic integration)
    Sentry.setupExpressErrorHandler(app)

    loggers.server.info('Sentry initialized successfully')
  } catch (error) {
    loggers.server.error({ error }, 'Failed to initialize Sentry')
  }
}

/**
 * ✅ Manually capture exception to Sentry
 */
export function captureException(error: Error, context?: Record<string, any>) {
  if (process.env.SENTRY_ENABLED !== 'true') return

  Sentry.captureException(error, {
    contexts: context ? { custom: context } : undefined,
  })
}

/**
 * ✅ Set user context for error tracking
 */
export function setUser(user: {
  id: string
  username?: string
  email?: string
}) {
  if (process.env.SENTRY_ENABLED !== 'true') return
  Sentry.setUser(user)
}

/**
 * ✅ Clear user context
 */
export function clearUser() {
  if (process.env.SENTRY_ENABLED !== 'true') return
  Sentry.setUser(null)
}
