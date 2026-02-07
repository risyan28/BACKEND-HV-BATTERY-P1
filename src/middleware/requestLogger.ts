// src/middleware/requestLogger.ts
import { Request, Response, NextFunction } from 'express'
import { logger } from '@/utils/logger'

/**
 * Request logging middleware using Pino
 * Logs all HTTP requests with method, path, status, and response time
 */
export function requestLogger(req: Request, res: Response, next: NextFunction) {
  const startTime = Date.now()

  // Log request
  logger.info({
    msg: 'Incoming request',
    method: req.method,
    path: req.path,
    query: req.query,
    ip: req.ip || req.socket.remoteAddress,
  })

  // Capture response
  res.on('finish', () => {
    const duration = Date.now() - startTime
    const logLevel = res.statusCode >= 400 ? 'error' : 'info'

    logger[logLevel]({
      msg: 'Request completed',
      method: req.method,
      path: req.path,
      statusCode: res.statusCode,
      duration: `${duration}ms`,
    })
  })

  next()
}
