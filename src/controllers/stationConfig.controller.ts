// src/controllers/stationConfig.controller.ts

import { Request, Response } from 'express'
import prisma from '@/prisma'

export const stationConfigController = {
  /**
   * Get Station Config
   * GET /api/station-config
   */
  async getConfig(req: Request, res: Response) {
    try {
      const stations = await prisma.tB_M_STATION_CONFIG.findMany({
        orderBy: { SORT_ORDER: 'asc' },
      })
      res.json({ success: true, data: stations })
    } catch (error: any) {
      console.error('Error fetching station config:', error)
      res.status(500).json({
        success: false,
        message: 'Failed to fetch station config',
        error: error.message,
      })
    }
  },

  /**
   * Update Station Config
   * PUT /api/station-config
   */
  async updateConfig(req: Request, res: Response) {
    try {
      const { station4Active, station5Active } = req.body

      // Auto-activate station 4 if station 5 is active
      const s4Active = station5Active ? true : !!station4Active
      const s5Active = !!station5Active

      await prisma.tB_M_STATION_CONFIG.updateMany({
        where: { STATION_NAME: 'MAN_ASSY_4' },
        data: { IS_ACTIVE: s4Active ? 1 : 0, UPDATED_AT: new Date() },
      })

      await prisma.tB_M_STATION_CONFIG.updateMany({
        where: { STATION_NAME: 'MAN_ASSY_5' },
        data: { IS_ACTIVE: s5Active ? 1 : 0, UPDATED_AT: new Date() },
      })

      // Trigger TRG_M_STATION_CONFIG_UPDATE handles STATION_ID propagation

      const stations = await prisma.tB_M_STATION_CONFIG.findMany({
        orderBy: { SORT_ORDER: 'asc' },
      })

      res.json({ success: true, data: stations })
    } catch (error: any) {
      console.error('Error updating station config:', error)
      res.status(500).json({
        success: false,
        message: 'Failed to update station config',
        error: error.message,
      })
    }
  },
}
