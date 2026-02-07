// src/schemas/sequence.schema.ts
import { z } from 'zod'

/**
 * Validation schemas for sequence-related requests
 */

export const createSequenceSchema = z.object({
  FTYPE_BATTERY: z
    .string()
    .min(1, 'FTYPE_BATTERY is required')
    .max(10, 'FTYPE_BATTERY must be at most 10 characters'),
  FMODEL_BATTERY: z
    .string()
    .min(1, 'FMODEL_BATTERY is required')
    .max(20, 'FMODEL_BATTERY must be at most 20 characters'),
})

export const updateSequenceSchema = z.object({
  FTYPE_BATTERY: z.string().max(10).optional(),
  FMODEL_BATTERY: z.string().max(20).optional(),
  FSTATUS: z.number().int().min(0).max(3).optional(),
  FID_ADJUST: z.number().int().optional(),
})

export const insertSequenceSchema = z
  .object({
    anchorId: z.number().int().positive().optional(),
    position: z.enum(['beginning', 'end']).optional(),
  })
  .refine(
    (data) => {
      // Either anchorId or position must be provided, but not both
      const hasAnchor = data.anchorId !== undefined
      const hasPosition = data.position !== undefined
      return hasAnchor !== hasPosition // XOR logic
    },
    {
      message: 'Either anchorId or position must be provided, but not both',
    },
  )

export const sequenceIdParamSchema = z.object({
  id: z.string().regex(/^\d+$/, 'ID must be a valid number').transform(Number),
})

// Type exports for TypeScript
export type CreateSequenceInput = z.infer<typeof createSequenceSchema>
export type UpdateSequenceInput = z.infer<typeof updateSequenceSchema>
export type InsertSequenceInput = z.infer<typeof insertSequenceSchema>
export type SequenceIdParam = z.infer<typeof sequenceIdParamSchema>
