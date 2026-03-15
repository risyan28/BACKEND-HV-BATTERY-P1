// src/routes/productionPlan.routes.ts
import { Router } from 'express'
import { productionPlanController } from '@/controllers/productionPlan.controller'

const productionPlanRouter = Router()

productionPlanRouter.get('/order-types', productionPlanController.getOrderTypes)
productionPlanRouter.get('/models', productionPlanController.getModels)
productionPlanRouter.get('/history', productionPlanController.getHistory)
productionPlanRouter.get('/', productionPlanController.getPlan)
productionPlanRouter.post('/', productionPlanController.savePlan)
productionPlanRouter.post(
  '/:planId/generate',
  productionPlanController.generateSequence,
)

export { productionPlanRouter }
