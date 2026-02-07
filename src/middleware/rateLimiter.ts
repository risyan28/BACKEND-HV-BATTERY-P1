// src/middleware/rateLimiter.ts
import rateLimit from 'express-rate-limit'
import { RATE_LIMIT } from '@/config/constants'
import { loggers } from '@/utils/logger'

/**
 * Rate Limiting Middleware
 *
 * Features:
 * - Prevents API abuse
 * - Configurable limits per endpoint
 * - Standard headers (X-RateLimit-*)
 * - Graceful handling
 */

/**
 * Standard rate limiter for most API endpoints
 * 100 requests per minute per IP
 */
export const apiLimiter = rateLimit({
  windowMs: RATE_LIMIT.WINDOW_MS,
  max: RATE_LIMIT.MAX_REQUESTS,
  standardHeaders: true, // Return rate limit info in `RateLimit-*` headers
  legacyHeaders: false, // Disable `X-RateLimit-*` headers
  handler: (req, res) => {
    loggers.api.warn({
      ip: req.ip,
      path: req.path,
      msg: 'Rate limit exceeded',
    })
    res.status(429).json({
      success: false,
      error: 'Too Many Requests',
      message: 'Rate limit exceeded. Please try again later.',
      retryAfter: Math.ceil(RATE_LIMIT.WINDOW_MS / 1000),
    })
  },
  skip: (req) => {
    // Skip rate limiting for health checks
    return req.path === '/api/health'
  },
})

/**
 * Strict rate limiter for write operations
 * 20 requests per minute per IP
 */
export const strictLimiter = rateLimit({
  windowMs: RATE_LIMIT.WINDOW_MS,
  max: 20,
  standardHeaders: true,
  legacyHeaders: false,
  handler: (req, res) => {
    loggers.api.warn({
      ip: req.ip,
      path: req.path,
      method: req.method,
      msg: 'Strict rate limit exceeded',
    })
    res.status(429).json({
      success: false,
      error: 'Too Many Requests',
      message: 'Too many write operations. Please slow down.',
      retryAfter: Math.ceil(RATE_LIMIT.WINDOW_MS / 1000),
    })
  },
})

/**
 * Lenient rate limiter for read-only operations
 * 200 requests per minute per IP
 */
export const lenientLimiter = rateLimit({
  windowMs: RATE_LIMIT.WINDOW_MS,
  max: 200,
  standardHeaders: true,
  legacyHeaders: false,
})
