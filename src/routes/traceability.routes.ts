// src/routes/traceability.routes.ts

import { Router } from 'express'
import { traceabilityController } from '@/controllers/traceability.controller'

const router = Router()

/**
 * @swagger
 * /api/traceability/search:
 *   get:
 *     summary: Search traceability data
 *     description: Retrieve traceability records by production date range
 *     tags: [Traceability]
 *     parameters:
 *       - in: query
 *         name: from
 *         required: true
 *         schema:
 *           type: string
 *           format: date
 *           example: "2024-01-01"
 *         description: Start date (YYYY-MM-DD)
 *       - in: query
 *         name: to
 *         required: true
 *         schema:
 *           type: string
 *           format: date
 *           example: "2024-01-31"
 *         description: End date (YYYY-MM-DD)
 *     responses:
 *       200:
 *         description: Successfully retrieved traceability data
 *         content:
 *           application/json:
 *             schema:
 *               type: array
 *               items:
 *                 type: object
 *       400:
 *         $ref: '#/components/responses/ValidationError'
 *       500:
 *         $ref: '#/components/responses/InternalServerError'
 */
router.get('/search', traceabilityController.getByDateRange)

export default router
