import { Request, Response } from 'express'
import { sequenceService } from '@/services/sequence.service'
import { asyncHandler } from '@/middleware/errorHandler'
import {
  createSequenceSchema,
  updateSequenceSchema,
  insertSequenceSchema,
  sequenceIdParamSchema,
} from '@/schemas/sequence.schema'
import { strategySchema } from '@/schemas/sequence.schema'
import { strategyStore } from '@/utils/strategyStore'
import { broadcastSnapshot } from '@/ws/connectionHandler'

export const sequenceController = {
  // ✅ Get all sequences (no validation needed for GET)
  getSequences: asyncHandler(async (req: Request, res: Response) => {
    const fresh = req.query.fresh === '1'
    const data = await sequenceService.getSequences({ fresh })
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

  // ✅ Get current sequence strategy
  getStrategy: asyncHandler(async (_req: Request, res: Response) => {
    res.json(strategyStore.get())
  }),

  // ✅ Set sequence strategy and broadcast fresh snapshot to all WS clients
  setStrategy: asyncHandler(async (req: Request, res: Response) => {
    const patch = strategySchema.partial().parse(req.body)
    const current = strategyStore.get()

    const merged = {
      ...current,
      ...patch,
      ratioValues: {
        ...current.ratioValues,
        ...(patch.ratioValues ?? {}),
      },
    }

    const validated = strategySchema.parse(merged)
    const updated = strategyStore.set(validated)

    // Apply strategy physically in DB so queue order is DB-driven
    await sequenceService.applyStrategyToDb(updated)

    // Push updated snapshot to all sequence-monitor clients immediately
    await broadcastSnapshot('sequences')

    res.json(updated)
  }),
}
