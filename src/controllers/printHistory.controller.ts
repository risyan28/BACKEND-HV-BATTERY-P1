// src/controllers/printHistory.controller.ts

import { Request, Response } from 'express'
import { printHistoryService } from '@/services/printHistory.service'

export const printHistoryController = {
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

      const data = await printHistoryService.getByDateRange(from, to)
      console.log(`👉 Send API /print-history/search result (${data.length} items)`)
      res.json(data)
    } catch (err: any) {
      console.error('❌ Error in search print history:', err)
      res.status(500).json({ error: err.message || 'Failed to search print history' })
    }
  },

  async reprint(req: Request, res: Response) {
    try {
      const { id } = req.params

      if (!id) {
        return res.status(400).json({ error: 'ID is required' })
      }

      const result = await printHistoryService.reprint(id)
      console.log(`👉 Re-print triggered for ID: ${id}`)
      res.json(result)
    } catch (err: any) {
      console.error('❌ Error in reprint:', err)
      if (err.message === 'Print log not found') {
        res.status(404).json({ error: err.message })
      } else {
        res.status(500).json({ error: err.message || 'Failed to trigger re-print' })
      }
    }
  },
}