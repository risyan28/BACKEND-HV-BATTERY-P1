// src/schemas/sequence.schema.ts
import { z } from 'zod'

type CanonicalOrderType = 'ASSY' | 'CKD' | 'SERVICE PART'

const toCanonicalOrderType = (
  value: unknown,
): CanonicalOrderType | undefined => {
  if (typeof value !== 'string') return undefined
  const upper = value.trim().toUpperCase()
  if (upper === 'ASSY') return 'ASSY'
  if (upper === 'CKD') return 'CKD'
  if (
    upper === 'SERVICE PART' ||
    upper === 'SERVICE_PART' ||
    upper === 'SERVICEPART'
  ) {
    return 'SERVICE PART'
  }
  return undefined
}

const orderTypeEnum = z.enum(['ASSY', 'CKD', 'SERVICE PART'])

const orderTypeSchema = z
  .string()
  .trim()
  .transform((v) => toCanonicalOrderType(v) ?? v.toUpperCase())
  .pipe(orderTypeEnum)

const ratioValuesSchema = z.preprocess(
  (input) => {
    if (!input || typeof input !== 'object') return input

    const raw = input as Record<string, unknown>
    const get = (keys: string[]) => {
      for (const key of keys) {
        if (key in raw) return raw[key]
      }
      return undefined
    }

    return {
      ASSY: get(['ASSY', 'Assy', 'assy']),
      CKD: get(['CKD', 'Ckd', 'ckd']),
      'SERVICE PART': get([
        'SERVICE PART',
        'Service Part',
        'service part',
        'SERVICE_PART',
        'Service_Part',
        'service_part',
        'SERVICEPART',
        'ServicePart',
        'servicepart',
      ]),
    }
  },
  z.object({
    ASSY: z.number().int().min(1).max(9),
    CKD: z.number().int().min(1).max(9),
    'SERVICE PART': z.number().int().min(1).max(9),
  }),
)

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
  ORDER_TYPE: orderTypeSchema,
  QTY: z.number().int().min(1).max(200),
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

export const strategySchema = z.object({
  mode: z.enum(['normal', 'priority', 'ratio']),
  priorityType: orderTypeSchema.optional(),
  ratioPrimary: orderTypeSchema.optional(),
  ratioSecondary: orderTypeSchema.optional(),
  ratioTertiary: orderTypeSchema.optional(),
  ratioValues: ratioValuesSchema.optional(),
})

// Type exports for TypeScript
export type StrategyInput = z.infer<typeof strategySchema>
export type CreateSequenceInput = z.infer<typeof createSequenceSchema>
export type UpdateSequenceInput = z.infer<typeof updateSequenceSchema>
export type InsertSequenceInput = z.infer<typeof insertSequenceSchema>
export type SequenceIdParam = z.infer<typeof sequenceIdParamSchema>
