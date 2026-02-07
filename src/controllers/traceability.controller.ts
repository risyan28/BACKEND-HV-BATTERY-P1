// src/controllers/traceability.controller.ts

import { Request, Response } from 'express'
import { traceabilityService } from '@/services/traceability.service'
import { asyncHandler } from '@/middleware/errorHandler'
import { dateRangeQuerySchema } from '@/schemas/traceability.schema'

export const traceabilityController = {
  // ✅ Get traceability data with validation + Pagination
  getByDateRange: asyncHandler(async (req: Request, res: Response) => {
    const validatedQuery = dateRangeQuerySchema.parse(req.query)

    const data = await traceabilityService.getByDateRange(
      validatedQuery.from,
      validatedQuery.to,
      validatedQuery.page,
      validatedQuery.limit,
    )

    console.log(
      `👉 Send API /traceability/search result (${data.length} items, page=${validatedQuery.page}, limit=${validatedQuery.limit})`,
    )
    res.json(data)
  }),
}
