// src/routes/logs.routes.ts

import { Router } from 'express'
import { logsController } from '@/controllers/logs.controller'

const router = Router()

/**
 * @swagger
 * /api/logs:
 *   post:
 *     summary: Receive frontend logs
 *     description: Endpoint for frontend to send logs to backend
 *     tags: [Logs]
 *     requestBody:
 *       required: true
 *       content:
 *         application/json:
 *           schema:
 *             type: object
 *             required:
 *               - level
 *               - message
 *             properties:
 *               level:
 *                 type: string
 *                 enum: [error, warn, info, debug]
 *                 example: error
 *               message:
 *                 type: string
 *                 example: "Failed to fetch data"
 *               context:
 *                 type: object
 *                 example: { component: "UserDashboard", errorCode: 500 }
 *               timestamp:
 *                 type: string
 *                 format: date-time
 *                 example: "2026-03-04T10:30:00.000Z"
 *               userAgent:
 *                 type: string
 *                 example: "Mozilla/5.0..."
 *               url:
 *                 type: string
 *                 example: "/dashboard/users"
 *     responses:
 *       204:
 *         description: Log received successfully (no content)
 */
router.post('/', logsController.receiveLogs)

export { router as logsRouter }
