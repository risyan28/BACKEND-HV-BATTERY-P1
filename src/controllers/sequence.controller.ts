import { Request, Response } from 'express'
import { sequenceService } from '@/services/sequence.service'
import { asyncHandler } from '@/middleware/errorHandler'
import {
  createSequenceSchema,
  updateSequenceSchema,
  insertSequenceSchema,
  sequenceIdParamSchema,
} from '@/schemas/sequence.schema'

export const sequenceController = {
  // ✅ Get all sequences (no validation needed for GET)
  getSequences: asyncHandler(async (req: Request, res: Response) => {
    const data = await sequenceService.getSequences()
    if (data) {
      console.log('👉 Send API /sequences result')
    }
    res.json(data)
  }),

  // ✅ Create sequence with validation
  createSequence: asyncHandler(async (req: Request, res: Response) => {
    const validatedData = createSequenceSchema.parse(req.body)
    const data = await sequenceService.createSequence(validatedData)
    res.json(data)
  }),

  // ✅ Update sequence with validation
  updateSequence: asyncHandler(async (req: Request, res: Response) => {
    const { id } = sequenceIdParamSchema.parse(req.params)
    const validatedData = updateSequenceSchema.parse(req.body)
    const data = await sequenceService.updateSequence(id, validatedData)
    res.json(data)
  }),

  // ✅ Move sequence up
  moveSequenceUp: asyncHandler(async (req: Request, res: Response) => {
    const { id } = sequenceIdParamSchema.parse(req.params)
    const data = await sequenceService.moveSequenceUp(id)
    res.json(data)
  }),

  // ✅ Move sequence down
  moveSequenceDown: asyncHandler(async (req: Request, res: Response) => {
    const { id } = sequenceIdParamSchema.parse(req.params)
    const data = await sequenceService.moveSequenceDown(id)
    res.json(data)
  }),

  // ✅ Park sequence
  parkSequence: asyncHandler(async (req: Request, res: Response) => {
    const { id } = sequenceIdParamSchema.parse(req.params)
    const data = await sequenceService.parkSequence(id)
    res.json(data)
  }),

  // ✅ Insert sequence with validation
  insertSequence: asyncHandler(async (req: Request, res: Response) => {
    const { id } = sequenceIdParamSchema.parse(req.params)
    const validatedData = insertSequenceSchema.parse(req.body)

    const data = await sequenceService.insertSequence(id, {
      anchorId: validatedData.anchorId,
      position: validatedData.position,
    })
    res.json(data)
  }),

  // ✅ Remove from parked
  removeFromParked: asyncHandler(async (req: Request, res: Response) => {
    const { id } = sequenceIdParamSchema.parse(req.params)
    const data = await sequenceService.removeFromParked(id)
    res.json(data)
  }),
}
