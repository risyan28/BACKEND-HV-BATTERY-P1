import pino from 'pino'
import dayjs from 'dayjs'
import utc from 'dayjs/plugin/utc'
import timezone from 'dayjs/plugin/timezone'

dayjs.extend(utc)
dayjs.extend(timezone)

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
            ignore: 'pid,hostname',
            singleLine: false,
            messageFormat: '{msg}',
            timestampKey: 'timestamp',
          },
        }
      : undefined,
  formatters: {
    level: (label) => {
      return { level: label.toUpperCase() }
    },
    log: (object) => {
      // Tambahkan timestamp lokal Jakarta
      return {
        ...object,
        timestamp: dayjs().tz('Asia/Jakarta').format('YYYY-MM-DD HH:mm:ss'),
      }
    },
  },
  timestamp: () => '', // Nonaktifkan timestamp default
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
