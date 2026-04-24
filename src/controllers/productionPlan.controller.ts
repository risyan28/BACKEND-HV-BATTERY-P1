// src/controllers/productionPlan.controller.ts
import { Request, Response } from 'express'
import { productionPlanService } from '@/services/productionPlan.service'
import { asyncHandler } from '@/middleware/errorHandler'
import {
  planQuerySchema,
  historyQuerySchema,
  savePlanBodySchema,
  generateSequenceParamSchema,
  generateSequenceBodySchema,
  cycleTimeBodySchema,
} from '@/schemas/productionPlan.schema'

export const productionPlanController = {
  /** GET /order-types */
  getOrderTypes: asyncHandler(async (_req: Request, res: Response) => {
    const data = await productionPlanService.getOrderTypes()
    res.json(data)
  }),

  /** GET /models */
  getModels: asyncHandler(async (_req: Request, res: Response) => {
    const data = await productionPlanService.getModels()
    res.json(data)
  }),

  /** GET /cycle-time */
  getCycleTime: asyncHandler(async (_req: Request, res: Response) => {
    const data = await productionPlanService.getCycleTime()
    res.json(data)
  }),

  /** PUT /cycle-time */
  setCycleTime: asyncHandler(async (req: Request, res: Response) => {
    const { cycleTime } = cycleTimeBodySchema.parse(req.body)
    const data = await productionPlanService.setCycleTime(cycleTime)
    res.json(data)
  }),

  /** POST /andon-global/reset-all */
  resetAndonGlobal: asyncHandler(async (_req: Request, res: Response) => {
    const data =
      await productionPlanService.resetAndonGlobalFvalueExceptTaktime()
    res.json(data)
  }),

  /** GET /?date=YYYY-MM-DD&shift=DAY|NIGHT */
  getPlan: asyncHandler(async (req: Request, res: Response) => {
    const { date, shift } = planQuerySchema.parse(req.query)
    const data = await productionPlanService.getPlanByDateShift(date, shift)
    res.json(data ?? null)
  }),

  /** POST / */
  savePlan: asyncHandler(async (req: Request, res: Response) => {
    const body = savePlanBodySchema.parse(req.body)
    const data = await productionPlanService.savePlan(body)
    res.json(data)
  }),

  /** POST /:planId/generate */
  generateSequence: asyncHandler(async (req: Request, res: Response) => {
    const { planId } = generateSequenceParamSchema.parse(req.params)
    const { modelName, orderType } = generateSequenceBodySchema.parse(req.body)
    const data = await productionPlanService.generateSequence(
      planId,
      modelName,
      orderType,
    )
    res.json(data)
  }),

  /** GET /history?from=YYYY-MM-DD&to=YYYY-MM-DD */
  getHistory: asyncHandler(async (req: Request, res: Response) => {
    const { from, to } = historyQuerySchema.parse(req.query)
    const data = await productionPlanService.getHistory(from, to)
    res.json(data)
  }),
}
