// src/routes/printHistory.routes.ts
import { Router } from 'express'
import { printHistoryController } from '@/controllers/printHistory.controller'

const router = Router()
/**
 * @GET    /api/print-history/search?from=YYYY-MM-DD&to=YYYY-MM-DD
 * @desc   Search print history by production date range
 */
router.get('/search', printHistoryController.getByDateRange)

/**
 * @POST   /api/print-history/:id/reprint
 * @desc   Trigger re-print for a specific print history record
 */
router.post('/:id/reprint', printHistoryController.reprint)

export default router