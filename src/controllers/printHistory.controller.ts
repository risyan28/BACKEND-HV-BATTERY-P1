// src/controllers/printHistory.controller.ts

import { Request, Response } from 'express'
import { printHistoryService } from '@/services/printHistory.service'
import { asyncHandler } from '@/middleware/errorHandler'
import { dateRangeQuerySchema } from '@/schemas/traceability.schema'

export const printHistoryController = {
  // ✅ Get print history by date range with pagination
  getByDateRange: asyncHandler(async (req: Request, res: Response) => {
    const validatedQuery = dateRangeQuerySchema.parse(req.query)

    const data = await printHistoryService.getByDateRange(
      validatedQuery.from,
      validatedQuery.to,
      validatedQuery.page,
      validatedQuery.limit,
    )

    console.log(
      `👉 Send API /print-history/search result (${data.length} items, page=${validatedQuery.page}, limit=${validatedQuery.limit})`,
    )
    console.log('📦 Data:', JSON.stringify(data, null, 2))
    res.json(data)
  }),

  async reprint(req: Request, res: Response) {
    try {
      const { id } = req.params
      const productionDate =
        typeof req.body?.productionDate === 'string'
          ? req.body.productionDate
          : undefined

      if (!id) {
        return res.status(400).json({ error: 'ID is required' })
      }

      const result = await printHistoryService.reprint(id, productionDate)
      console.log(`👉 Re-print triggered for ID: ${id}`)
      res.json(result)
    } catch (err: any) {
      const errorMsg = err.code || err.message || 'Unknown error'
      console.error('❌ Error in reprint:', errorMsg)
      if (err.message === 'Print log not found') {
        res.status(404).json({ error: err.message })
      } else {
        res
          .status(500)
          .json({ error: err.message || 'Failed to trigger re-print' })
      }
    }
  },
}
