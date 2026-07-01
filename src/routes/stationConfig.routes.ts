// src/routes/stationConfig.routes.ts

import { Router } from 'express'
import { stationConfigController } from '@/controllers/stationConfig.controller'

const router = Router()

/**
 * @swagger
 * /api/station-config:
 *   get:
 *     summary: Get Station Configuration
 *     description: Retrieve all station configuration records ordered by SORT_ORDER
 *     tags: [Station Config]
 *     responses:
 *       200:
 *         description: Successfully retrieved station config
 *       500:
 *         description: Server error
 */
router.get('/', stationConfigController.getConfig)

/**
 * @swagger
 * /api/station-config:
 *   put:
 *     summary: Update Station Configuration
 *     description: Activate/deactivate MAN_ASSY_4 and MAN_ASSY_5 stations
 *     tags: [Station Config]
 *     requestBody:
 *       required: true
 *       content:
 *         application/json:
 *           schema:
 *             type: object
 *             properties:
 *               station4Active:
 *                 type: boolean
 *               station5Active:
 *                 type: boolean
 *     responses:
 *       200:
 *         description: Station config updated successfully
 *       500:
 *         description: Server error
 */
router.put('/', stationConfigController.updateConfig)

export { router as stationConfigRouter }
