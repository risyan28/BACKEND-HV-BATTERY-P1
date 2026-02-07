// src/routes/traceability.routes.ts

import { Router } from 'express'
import { traceabilityController } from '@/controllers/traceability.controller'

const router = Router()

/**
 * @GET    /api/traceability/search?from=YYYY-MM-DD&to=YYYY-MM-DD
 * @desc   Search traceability data by production date range (PROD_DATE_PrintLog)
 */
router.get('/search', traceabilityController.getByDateRange)

export default router
