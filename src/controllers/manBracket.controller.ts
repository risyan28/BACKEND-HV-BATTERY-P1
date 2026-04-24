// src/controllers/manBracket.controller.ts

import { Request, Response } from 'express'
import prisma from '@/prisma'
import { manBracketService } from '@/services/manBracket.service'

export const manBracketController = {
  /**
   * Start Man Bracket Process
   * POST /api/man-bracket/start-process
   */
  async startProcess(req: Request, res: Response) {
    try {
      const { barcode, destination, startTime } = req.body

      if (!barcode || !destination) {
        return res.status(400).json({
          success: false,
          message: 'Barcode and Destination are required',
        })
      }

      const manBracketRecord = await manBracketService.startProcess(
        barcode,
        destination,
        startTime,
      )

      res.status(201).json({
        success: true,
        message: 'Man Bracket process started successfully',
        data: manBracketRecord,
      })
    } catch (error: any) {
      console.error('Error starting man bracket process:', error)
      res.status(500).json({
        success: false,
        message: 'Failed to start man bracket process',
        error: error.message,
      })
    }
  },

  /**
   * Complete Man Bracket Process Data
   * POST /api/man-bracket/complete-process
   */
  async completeProcess(req: Request, res: Response) {
    try {
      const { recordId, completedTime } = req.body

      if (!recordId) {
        return res.status(400).json({
          success: false,
          message: 'recordId is required',
        })
      }

      const existingRecord = await manBracketService.getRecord(Number(recordId))

      if (!existingRecord) {
        return res.status(404).json({
          success: false,
          message: 'Record not found',
        })
      }

      const manBracketRecord = await manBracketService.completeProcess(
        Number(recordId),
        completedTime,
      )

      res.status(200).json({
        success: true,
        message: 'Man Bracket process completed successfully',
        data: manBracketRecord,
      })
    } catch (error: any) {
      console.error('Error completing man bracket process:', error)
      res.status(500).json({
        success: false,
        message: 'Failed to complete man bracket process',
        error: error.message,
      })
    }
  },

  /**
   * Reset Man Bracket Process Data
   * POST /api/man-bracket/reset-process
   */
  async resetProcess(req: Request, res: Response) {
    try {
      const { recordId } = req.body

      if (!recordId) {
        return res.status(400).json({
          success: false,
          message: 'recordId is required',
        })
      }

      const existingRecord = await manBracketService.getRecord(Number(recordId))

      if (!existingRecord) {
        return res.status(404).json({
          success: false,
          message: 'Record not found',
        })
      }

      if (existingRecord.FVALUE === 1) {
        return res.status(400).json({
          success: false,
          message: 'Completed records cannot be reset',
        })
      }

      await manBracketService.resetProcess(Number(recordId))

      res.status(200).json({
        success: true,
        message: 'Man Bracket process reset successfully',
      })
    } catch (error: any) {
      console.error('Error resetting man bracket process:', error)
      res.status(500).json({
        success: false,
        message: 'Failed to reset man bracket process',
        error: error.message,
      })
    }
  },

  /**
   * Get Man Bracket Records
   * GET /api/man-bracket
   */
  async getRecords(req: Request, res: Response) {
    try {
      const { limit = 50, offset = 0, destination, fvalue } = req.query

      const { records, total } = await manBracketService.getRecords(
        Number(limit),
        Number(offset),
        destination as string | undefined,
        fvalue !== undefined ? Number(fvalue) : undefined,
      )

      res.status(200).json({
        success: true,
        data: records,
        pagination: {
          total,
          limit: Number(limit),
          offset: Number(offset),
        },
      })
    } catch (error: any) {
      console.error('Error fetching man bracket records:', error)
      res.status(500).json({
        success: false,
        message: 'Failed to fetch man bracket records',
        error: error.message,
      })
    }
  },

  /**
   * Get Single Man Bracket Record
   * GET /api/man-bracket/:id
   */
  async getRecord(req: Request, res: Response) {
    try {
      const { id } = req.params

      const record = await manBracketService.getRecord(Number(id))

      if (!record) {
        return res.status(404).json({
          success: false,
          message: 'Record not found',
        })
      }

      res.status(200).json({
        success: true,
        data: record,
      })
    } catch (error: any) {
      console.error('Error fetching man bracket record:', error)
      res.status(500).json({
        success: false,
        message: 'Failed to fetch man bracket record',
        error: error.message,
      })
    }
  },

  /**
   * Get Statistics
   * GET /api/man-bracket/stats
   */
  async getStats(req: Request, res: Response) {
    try {
      const { startDate, endDate } = req.query

      const statsResult = await manBracketService.getStats(
        startDate as string | undefined,
        endDate as string | undefined,
      )

      res.status(200).json({
        success: true,
        data: statsResult,
      })
    } catch (error: any) {
      console.error('Error fetching man bracket stats:', error)
      res.status(500).json({
        success: false,
        message: 'Failed to fetch man bracket stats',
        error: error.message,
      })
    }
  },

  /**
   * Get Active Destination Config (for AUTO mode)
   * GET /api/man-bracket/destination-config
   */
  async getDestinationConfig(req: Request, res: Response) {
    try {
      const destination = await manBracketService.getDestinationConfig()
      res.json({ success: true, data: { destination } })
    } catch {
      // Fallback default if table not available
      res.json({ success: true, data: { destination: 'ASSY' } })
    }
  },

  /**
   * Set Password for specific FID
   * PUT /api/man-bracket/destination-config
   * Body: { fid: number, password: string }
   */
  async setDestinationConfig(req: Request, res: Response) {
    try {
      const { fid, password } = req.body

      if (!fid || (fid !== 1 && fid !== 2)) {
        return res.status(400).json({
          success: false,
          message: 'fid must be 1 (ASSY) or 2 (CKD)',
        })
      }

      if (typeof password !== 'string' || !password.trim()) {
        return res.status(400).json({
          success: false,
          message: 'password must be a non-empty string',
        })
      }

      const result = await manBracketService.setDestinationConfig(fid, password)
      res.json({ success: true, ...result })
    } catch (error: any) {
      res.status(500).json({ success: false, message: error.message })
    }
  },

  /**
   * Set Interlock Mode
   * POST /api/man-bracket/interlock-mode
   * Body: { interlockOn: boolean, password: string, fid?: number }
   */
  async setInterlockMode(req: Request, res: Response) {
    try {
      const { interlockOn, password, fid } = req.body

      if (typeof interlockOn !== 'boolean') {
        return res.status(400).json({
          success: false,
          message: 'interlockOn must be a boolean',
        })
      }

      if (typeof password !== 'string' || !password.trim()) {
        return res.status(400).json({
          success: false,
          message: 'password is required',
        })
      }

      const result = await manBracketService.setInterlockMode(
        interlockOn,
        password,
        fid,
      )

      res.json(result)
    } catch (error: any) {
      const isConfigError = error.message.includes('Configuration not found')
      const statusCode = isConfigError ? 400 : 400

      res.status(statusCode).json({
        success: false,
        message: error.message,
      })
    }
  },
}
