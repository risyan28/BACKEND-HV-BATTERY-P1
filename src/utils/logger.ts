// src/utils/logger.ts
import pino from 'pino'

/**
 * Pino Logger Configuration
 *
 * Production: JSON format for log aggregation
 * Development: Pretty print for readability
 */
export const logger = pino({
  level: process.env.LOG_LEVEL || 'info',
  transport:
    process.env.NODE_ENV !== 'production'
      ? {
          target: 'pino-pretty',
          options: {
            colorize: true,
            translateTime: 'HH:MM:ss Z',
            ignore: 'pid,hostname',
            singleLine: false,
          },
        }
      : undefined,
  formatters: {
    level: (label) => {
      return { level: label.toUpperCase() }
    },
  },
  timestamp: pino.stdTimeFunctions.isoTime,
})

/**
 * Create child logger with context
 */
export function createLogger(context: string) {
  return logger.child({ context })
}

/**
 * Logger for specific modules
 */
export const loggers = {
  db: createLogger('DATABASE'),
  ws: createLogger('WEBSOCKET'),
  api: createLogger('API'),
  cache: createLogger('CACHE'),
  server: createLogger('SERVER'),
}
