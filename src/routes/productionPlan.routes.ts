// src/routes/productionPlan.routes.ts
import { Router } from 'express'
import { productionPlanController } from '@/controllers/productionPlan.controller'

const productionPlanRouter = Router()

productionPlanRouter.get('/order-types', productionPlanController.getOrderTypes)
productionPlanRouter.get('/models', productionPlanController.getModels)
productionPlanRouter.get('/cycle-time', productionPlanController.getCycleTime)
productionPlanRouter.put('/cycle-time', productionPlanController.setCycleTime)
productionPlanRouter.post(
  '/andon-global/reset-all',
  productionPlanController.resetAndonGlobal,
)
productionPlanRouter.get('/history', productionPlanController.getHistory)
productionPlanRouter.get('/', productionPlanController.getPlan)
productionPlanRouter.post('/', productionPlanController.savePlan)
productionPlanRouter.post(
  '/:planId/generate',
  productionPlanController.generateSequence,
)

export { productionPlanRouter }
