// src/services/productionPlan.service.ts
import prisma from '@/prisma'
import type { SavePlanBody } from '@/schemas/productionPlan.schema'

export const productionPlanService = {
  /** Master: all order types sorted by SORT_ORDER (IS_ACTIVE controls editability in UI) */
  getOrderTypes: async () => {
    return prisma.tB_M_PROD_ORDER_TYPE.findMany({
      orderBy: { SORT_ORDER: 'asc' },
      select: {
        FID: true,
        ORDER_TYPE: true,
        SORT_ORDER: true,
        IS_ACTIVE: true,
      },
    })
  },

  /** Master: active models, default first */
  getModels: async () => {
    return prisma.tB_M_PROD_MODEL.findMany({
      where: { IS_ACTIVE: 1 },
      orderBy: [{ IS_DEFAULT: 'desc' }, { FID: 'asc' }],
      select: {
        FID: true,
        FMODEL_BATTERY: true,
        IS_DEFAULT: true,
        IS_ACTIVE: true,
      },
    })
  },

  /** Get plan header + details for a specific date & shift */
  getPlanByDateShift: async (date: string, shift: string) => {
    return prisma.tB_H_PROD_PLAN.findFirst({
      where: {
        PLAN_DATE: new Date(date),
        SHIFT: shift,
      },
      include: {
        details: {
          orderBy: [{ MODEL_NAME: 'asc' }, { ORDER_TYPE: 'asc' }],
        },
      },
    })
  },

  /**
   * Create a new plan if missing.
   * If a plan already exists, only persist detail rows with changed qty
   * (or newly added keys). If everything is unchanged, this is a no-op write.
   */
  savePlan: async (body: SavePlanBody) => {
    const planDate = new Date(body.date)
    const now = new Date()

    const existingPlan = await prisma.tB_H_PROD_PLAN.findUnique({
      where: {
        PLAN_DATE_SHIFT: {
          PLAN_DATE: planDate,
          SHIFT: body.shift,
        },
      },
      include: { details: true },
    })

    if (!existingPlan) {
      const createdPlan = await prisma.tB_H_PROD_PLAN.create({
        data: {
          PLAN_DATE: planDate,
          SHIFT: body.shift,
          IS_LOCKED: 1,
          CREATED_AT: now,
          UPDATED_AT: now,
          details: {
            create: body.details.map((d) => ({
              MODEL_NAME: d.modelName,
              ORDER_TYPE: d.orderType,
              QTY_PLAN: d.qtyPlan,
              SEQ_GENERATED: 0,
              CREATED_AT: now,
              UPDATED_AT: now,
            })),
          },
        },
        include: { details: true },
      })

      return createdPlan
    }

    const existingDetailByKey = new Map(
      existingPlan.details.map((d) => [`${d.MODEL_NAME}::${d.ORDER_TYPE}`, d]),
    )

    const detailsToCreate: SavePlanBody['details'] = []
    const detailsToUpdate: SavePlanBody['details'] = []

    for (const d of body.details) {
      const key = `${d.modelName}::${d.orderType}`
      const current = existingDetailByKey.get(key)

      if (!current) {
        detailsToCreate.push(d)
        continue
      }

      if (current.QTY_PLAN !== d.qtyPlan) {
        detailsToUpdate.push(d)
      }
    }

    const hasDetailChanges =
      detailsToCreate.length > 0 || detailsToUpdate.length > 0

    if (!hasDetailChanges && existingPlan.IS_LOCKED === 1) {
      return existingPlan
    }

    await prisma.$transaction(async (tx) => {
      await tx.tB_H_PROD_PLAN.update({
        where: { FID: existingPlan.FID },
        data: {
          IS_LOCKED: 1,
          UPDATED_AT: now,
        },
      })

      if (detailsToCreate.length > 0) {
        await tx.tB_H_PROD_PLAN_DETAIL.createMany({
          data: detailsToCreate.map((d) => ({
            FID_PLAN: existingPlan.FID,
            MODEL_NAME: d.modelName,
            ORDER_TYPE: d.orderType,
            QTY_PLAN: d.qtyPlan,
            SEQ_GENERATED: 0,
            CREATED_AT: now,
            UPDATED_AT: now,
          })),
        })
      }

      for (const d of detailsToUpdate) {
        await tx.tB_H_PROD_PLAN_DETAIL.update({
          where: {
            FID_PLAN_MODEL_NAME_ORDER_TYPE: {
              FID_PLAN: existingPlan.FID,
              MODEL_NAME: d.modelName,
              ORDER_TYPE: d.orderType,
            },
          },
          data: {
            QTY_PLAN: d.qtyPlan,
            UPDATED_AT: now,
          },
        })
      }
    })

    return prisma.tB_H_PROD_PLAN.findFirst({
      where: { FID: existingPlan.FID },
      include: { details: true },
    })
  },

  /**
   * Mark a specific detail row as sequence-generated.
   */
  generateSequence: async (
    planId: number,
    modelName: string,
    orderType: string,
  ) => {
    const now = new Date()
    const updated = await prisma.tB_H_PROD_PLAN_DETAIL.updateMany({
      where: {
        FID_PLAN: planId,
        MODEL_NAME: modelName,
        ORDER_TYPE: orderType,
      },
      data: {
        SEQ_GENERATED: 1,
        SEQ_GENERATED_AT: now,
        UPDATED_AT: now,
      },
    })

    if (updated.count === 0) {
      throw new Error(
        `Plan detail not found: planId=${planId}, model=${modelName}, orderType=${orderType}`,
      )
    }

    return { success: true, updatedAt: now }
  },

  /**
   * History: all plans in [from, to] date range with details.
   */
  getHistory: async (from: string, to: string) => {
    return prisma.tB_H_PROD_PLAN.findMany({
      where: {
        PLAN_DATE: {
          gte: new Date(from),
          lte: new Date(to),
        },
      },
      include: {
        details: {
          orderBy: [{ MODEL_NAME: 'asc' }, { ORDER_TYPE: 'asc' }],
        },
      },
      orderBy: [{ PLAN_DATE: 'desc' }, { SHIFT: 'asc' }],
    })
  },
}
