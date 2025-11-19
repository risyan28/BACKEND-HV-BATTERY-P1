import { Request, Response } from 'express'
import { sequenceService } from '@/services/sequence.service'

export const sequenceController = {
  async getSequences(req: Request, res: Response) {
    const data = await sequenceService.getSequences()
    if (data) {
      console.log('👉 Send API /sequences result')
    }
    res.json(data)
  },

  async createSequence(req: Request, res: Response) {
    try {
      const { FTYPE_BATTERY, FMODEL_BATTERY } = req.body
      if (!FTYPE_BATTERY || !FMODEL_BATTERY) {
        return res
          .status(400)
          .json({ error: 'FTYPE_BATTERY and FMODEL_BATTERY are required' })
      }

      const data = await sequenceService.createSequence({
        FTYPE_BATTERY,
        FMODEL_BATTERY,
      })
      res.json(data)
    } catch (err: any) {
      console.error('❌ Error in createSequence:', err)
      res.status(500).json({ error: err.message || 'Internal Server Error' })
    }
  },

  async updateSequence(req: Request, res: Response) {
    const data = await sequenceService.updateSequence(
      Number(req.params.id),
      req.body
    )
    res.json(data)
  },

  async moveSequenceUp(req: Request, res: Response) {
    const data = await sequenceService.moveSequenceUp(Number(req.params.id))
    res.json(data)
  },

  async moveSequenceDown(req: Request, res: Response) {
    const data = await sequenceService.moveSequenceDown(Number(req.params.id))
    res.json(data)
  },

  async parkSequence(req: Request, res: Response) {
    const data = await sequenceService.parkSequence(Number(req.params.id))
    res.json(data)
  },

  async insertSequence(req: Request, res: Response) {
    const { anchorId, position } = req.body
    const parsedAnchorId = anchorId != null ? Number(anchorId) : undefined
    const pos: 'beginning' | 'end' | undefined =
      position === 'beginning' || position === 'end' ? position : undefined

    const data = await sequenceService.insertSequence(Number(req.params.id), {
      anchorId: parsedAnchorId,
      position: pos,
    })
    res.json(data)
  },

  async removeFromParked(req: Request, res: Response) {
    const data = await sequenceService.removeFromParked(Number(req.params.id))
    res.json(data)
  },
}
