// src/services/productionPlan.service.ts
import prisma from '@/prisma'
import type { SavePlanBody } from '@/schemas/productionPlan.schema'
import { toJakartaDbDate } from '@/utils/date'

// NOTE: TB_H_PROD_PLAN.PLAN_DATE is SQL Server DATE (no timezone).
// Use explicit UTC day boundaries to avoid off-by-one issues.
const parseISODateStartUtc = (isoDate: string) =>
  new Date(`${isoDate}T00:00:00.000Z`)

const parseISODateEndUtc = (isoDate: string) =>
  new Date(`${isoDate}T23:59:59.999Z`)

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

  /** Global: cycle time (stored as TB_R_ANDON_GLOBAL.FNAME='TAKTIME') */
  getCycleTime: async () => {
    const latest = await prisma.tB_R_ANDON_GLOBAL.findFirst({
      where: { FNAME: 'TAKTIME' },
      orderBy: { FUPDATE: 'desc' },
      select: { FVALUE: true, FUPDATE: true },
    })

    return {
      cycleTime: latest?.FVALUE ?? 0,
      updatedAt: latest?.FUPDATE ?? null,
    }
  },

  /** Upsert-ish: update all TAKTIME rows; create if none exist */
  setCycleTime: async (cycleTime: number) => {
    const now = toJakartaDbDate()

    const updated = await prisma.tB_R_ANDON_GLOBAL.updateMany({
      where: { FNAME: 'TAKTIME' },
      data: { FVALUE: cycleTime, FUPDATE: now },
    })

    if (updated.count === 0) {
      await prisma.tB_R_ANDON_GLOBAL.create({
        data: { FNAME: 'TAKTIME', FVALUE: cycleTime, FUPDATE: now },
      })
    }

    return { success: true, cycleTime, updatedAt: now }
  },

  /** Reset all ANDON global FVALUE to 0 except TAKTIME */
  resetAndonGlobalFvalueExceptTaktime: async () => {
    const now = toJakartaDbDate()

    const [andonAffectedRows, downtimeAffectedRows] = await prisma.$transaction(
      [
        // Use raw SQL to ensure NULL FNAME rows are also reset.
        prisma.$executeRaw`
        UPDATE dbo.TB_R_ANDON_GLOBAL
        SET FVALUE = 0,
            FUPDATE = ${now}
        WHERE ISNULL(FNAME, '') <> 'TAKTIME';
      `,
        prisma.$executeRaw`
        UPDATE dbo.TB_R_DOWNTIME_LOG
        SET DURATION_SECOND = 0,
            TOTAL_DOWNTIME = 0,
            FDATETIME_MODIFIED = ${now};
      `,
      ],
    )

    // Keep legacy key `affectedRows` for FE compatibility (andon rows).
    return {
      success: true,
      affectedRows: andonAffectedRows,
      andonAffectedRows,
      downtimeAffectedRows,
      updatedAt: now,
    }
  },

  /** Get plan header + details for a specific date & shift */
  getPlanByDateShift: async (date: string, shift: string) => {
    return prisma.tB_H_PROD_PLAN.findFirst({
      where: {
        PLAN_DATE: parseISODateStartUtc(date),
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
    const planDate = parseISODateStartUtc(body.date)
    const now = toJakartaDbDate()

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
              PROD_DATE: planDate,
              SHIFT: body.shift,
              QTY_PLAN: d.qtyPlan,
              QTY_ACTUAL: 0,
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
            PROD_DATE: existingPlan.PLAN_DATE,
            SHIFT: existingPlan.SHIFT,
            QTY_PLAN: d.qtyPlan,
            QTY_ACTUAL: 0,
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
    const now = toJakartaDbDate()
    const updated = await prisma.tB_H_PROD_PLAN_DETAIL.updateMany({
      where: {
        FID_PLAN: planId,
        MODEL_NAME: modelName,
        ORDER_TYPE: orderType,
        SEQ_GENERATED: 0,
      },
      data: {
        SEQ_GENERATED: 1,
        SEQ_GENERATED_AT: now,
        UPDATED_AT: now,
      },
    })

    // Idempotent behavior: if already generated, treat as success.
    if (updated.count === 0) {
      const existing = await prisma.tB_H_PROD_PLAN_DETAIL.findUnique({
        where: {
          FID_PLAN_MODEL_NAME_ORDER_TYPE: {
            FID_PLAN: planId,
            MODEL_NAME: modelName,
            ORDER_TYPE: orderType,
          },
        },
        select: { SEQ_GENERATED: true },
      })

      if (!existing) {
        throw new Error(
          `Plan detail not found: planId=${planId}, model=${modelName}, orderType=${orderType}`,
        )
      }

      return { success: true, updatedAt: now }
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
          gte: parseISODateStartUtc(from),
          lte: parseISODateEndUtc(to),
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
