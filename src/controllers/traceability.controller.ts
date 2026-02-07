// src/controllers/traceability.controller.ts

import { Request, Response } from 'express'
import { traceabilityService } from '@/services/traceability.service'

export const traceabilityController = {
  async getByDateRange(req: Request, res: Response) {
    try {
      const { from, to } = req.query

      if (!from || !to || typeof from !== 'string' || typeof to !== 'string') {
        return res.status(400).json({
          error: 'Query parameters "from" and "to" are required (format: YYYY-MM-DD)',
        })
      }

      // Validasi format tanggal sederhana
      const dateRegex = /^\d{4}-\d{2}-\d{2}$/
      if (!dateRegex.test(from) || !dateRegex.test(to)) {
        return res.status(400).json({
          error: 'Date must be in YYYY-MM-DD format',
        })
      }

      const data = await traceabilityService.getByDateRange(from, to)
      console.log(`👉 Send API /traceability/search result (${data.length} items)`)
      res.json(data)
    } catch (err: any) {
      console.error('❌ Error in search traceability:', err)
      res.status(500).json({ error: err.message || 'Failed to search traceability data' })
    }
  },
}
