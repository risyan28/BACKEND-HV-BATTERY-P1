// src/config/constants.ts

/**
 * Application-wide constants
 * Centralized configuration for magic numbers and fixed values
 */

// ===== WebSocket Polling Configuration =====
export const POLLING = {
  /** Default polling interval in milliseconds */
  INTERVAL_MS: 2000,

  /** Maximum retry attempts for failed polling */
  MAX_RETRIES: 3,

  /** Timeout for stale connections in milliseconds */
  STALE_CONNECTION_TIMEOUT_MS: 60000, // 1 minute
} as const

// ===== Query Limits =====
export const QUERY_LIMITS = {
  /** Maximum number of queue items to fetch */
  MAX_QUEUE_SIZE: 500,

  /** Maximum number of completed items to fetch */
  MAX_COMPLETED_SIZE: 100,

  /** Default page size for pagination */
  DEFAULT_PAGE_SIZE: 50,
} as const

// ===== Database Configuration =====
export const DATABASE = {
  /** Connection pool configuration */
  POOL: {
    MAX: 10,
    MIN: 0,
    IDLE_TIMEOUT_MS: 30000,
  },

  /** Connection retry configuration */
  RETRY: {
    MAX_ATTEMPTS: 5,
    INITIAL_DELAY_MS: 1000,
    MAX_DELAY_MS: 30000,
    BACKOFF_MULTIPLIER: 2,
  },
} as const

// ===== Sequence Status Mapping =====
export const SEQUENCE_STATUS = {
  QUEUE: 0, // Belum diprint
  PRINTED: 1, // Sudah diprint, standby di proses
  COMPLETE: 2, // Workpiece keluar dari pos
  PARKED: 3, // Manual parked
} as const

// ===== CORS Configuration =====
export const CORS_DEFAULTS = {
  /** Default allowed origins in development */
  DEV_ORIGINS: ['http://localhost:3000', 'http://localhost:5173'],

  /** Default max age for preflight requests */
  MAX_AGE: 86400, // 24 hours
} as const

// ===== API Rate Limiting =====
export const RATE_LIMIT = {
  /** Time window in milliseconds */
  WINDOW_MS: 60000, // 1 minute

  /** Maximum requests per window */
  MAX_REQUESTS: 100,
} as const

// ===== Server Configuration =====
export const SERVER = {
  /** Default port if not specified in env */
  DEFAULT_PORT: 4001,

  /** Shutdown grace period in milliseconds */
  SHUTDOWN_TIMEOUT_MS: 10000, // 10 seconds
} as const
