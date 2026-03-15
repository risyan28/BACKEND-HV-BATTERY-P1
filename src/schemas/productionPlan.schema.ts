// src/schemas/productionPlan.schema.ts
import { z } from 'zod'

export const planQuerySchema = z.object({
  date: z.string().regex(/^\d{4}-\d{2}-\d{2}$/, 'date must be YYYY-MM-DD'),
  shift: z.enum(['DAY', 'NIGHT']),
})

export const historyQuerySchema = z.object({
  from: z.string().regex(/^\d{4}-\d{2}-\d{2}$/, 'from must be YYYY-MM-DD'),
  to: z.string().regex(/^\d{4}-\d{2}-\d{2}$/, 'to must be YYYY-MM-DD'),
})

const planDetailSchema = z.object({
  modelName: z.string().min(1).max(50),
  orderType: z.string().min(1).max(50),
  qtyPlan: z.number().int().min(0),
})

export const savePlanBodySchema = z.object({
  date: z.string().regex(/^\d{4}-\d{2}-\d{2}$/, 'date must be YYYY-MM-DD'),
  shift: z.enum(['DAY', 'NIGHT']),
  details: z.array(planDetailSchema).min(1),
})

export const generateSequenceParamSchema = z.object({
  planId: z
    .string()
    .regex(/^\d+$/, 'planId must be a number')
    .transform(Number),
})

export const generateSequenceBodySchema = z.object({
  modelName: z.string().min(1).max(50),
  orderType: z.string().min(1).max(50),
})

export type PlanQuery = z.infer<typeof planQuerySchema>
export type HistoryQuery = z.infer<typeof historyQuerySchema>
export type SavePlanBody = z.infer<typeof savePlanBodySchema>
export type GenerateSequenceParam = z.infer<typeof generateSequenceParamSchema>
export type GenerateSequenceBody = z.infer<typeof generateSequenceBodySchema>
