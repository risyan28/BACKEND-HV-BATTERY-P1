// src/routes/printHistory.routes.ts
import { Router } from 'express'
import { printHistoryController } from '@/controllers/printHistory.controller'

const router = Router()

/**
 * @swagger
 * /api/print-history/search:
 *   get:
 *     summary: Search print history
 *     description: Retrieve print history records by production date range
 *     tags: [Print History]
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
 *         description: Successfully retrieved print history
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
router.get('/search', printHistoryController.getByDateRange)

/**
 * @swagger
 * /api/print-history/{id}/reprint:
 *   post:
 *     summary: Trigger reprint
 *     description: Initiate a reprint operation for a specific print history record
 *     tags: [Print History]
 *     parameters:
 *       - in: path
 *         name: id
 *         required: true
 *         schema:
 *           type: integer
 *         description: Print history record ID
 *     responses:
 *       200:
 *         description: Reprint triggered successfully
 *       404:
 *         description: Print history record not found
 *       500:
 *         $ref: '#/components/responses/InternalServerError'
 */
router.post('/:id/reprint', printHistoryController.reprint)

export default router
