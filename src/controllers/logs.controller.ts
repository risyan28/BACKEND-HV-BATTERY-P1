// src/controllers/logs.controller.ts

import { Request, Response } from 'express'
import { loggers } from '@/utils/logger'

export const logsController = {
  /**
   * Receive frontend logs
   * POST /api/logs
   */
  async receiveLogs(req: Request, res: Response) {
    try {
      const { level, message, context, timestamp, userAgent, url } = req.body

      // Log to backend with appropriate level
      const logData = {
        message,
        context: context || {},
        timestamp,
        userAgent,
        url,
        source: 'frontend',
      }

      switch (level) {
        case 'error':
          loggers.server.error(logData, `[FE] ${message}`)
          break
        case 'warn':
          loggers.server.warn(logData, `[FE] ${message}`)
          break
        case 'info':
          loggers.server.info(logData, `[FE] ${message}`)
          break
        case 'debug':
          loggers.server.debug(logData, `[FE] ${message}`)
          break
        default:
          loggers.server.info(logData, `[FE] ${message}`)
      }

      // Return 204 No Content
      res.status(204).send()
    } catch (err: any) {
      // Even if logging fails, return 204 to not break FE
      console.error('Failed to process FE log:', err.message)
      res.status(204).send()
    }
  },
}
