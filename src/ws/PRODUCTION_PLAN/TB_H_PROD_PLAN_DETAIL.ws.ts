// src/ws/PRODUCTION_PLAN/TB_H_PROD_PLAN_DETAIL.ws.ts

import { createCTPolling } from '@/ws/poller.ws'
import { formatDate, formatDateTime } from '@/utils/date'

type ProdPlanDetailRow = {
  FID: number
  PROD_DATE: string | null
  SHIFT: string
  MODEL_NAME: string
  ORDER_TYPE: string
  QTY_PLAN: number
  QTY_ACTUAL: number
  CREATED_AT: string | null
  UPDATED_AT: string | null
}

type ProdPlanDetailWsPayload =
  | {
      kind: 'snapshot'
      updatedAt: string | null
      fromProdDate: string | null
      rows: ProdPlanDetailRow[]
    }
  | {
      kind: 'delta'
      updatedAt: string | null
      changedCount: number
      rows: ProdPlanDetailRow[]
    }

function mapRow(r: any): ProdPlanDetailRow {
  return {
    FID: Number(r.FID),
    PROD_DATE: formatDate(r.PROD_DATE) ?? null,
    SHIFT: String(r.SHIFT ?? ''),
    MODEL_NAME: String(r.MODEL_NAME ?? ''),
    ORDER_TYPE: String(r.ORDER_TYPE ?? ''),
    QTY_PLAN: Number(r.QTY_PLAN ?? 0),
    QTY_ACTUAL: Number(r.QTY_ACTUAL ?? 0),
    CREATED_AT: formatDateTime(r.CREATED_AT) ?? null,
    UPDATED_AT: formatDateTime(r.UPDATED_AT) ?? null,
  }
}

async function fetchSnapshot(pool: any): Promise<ProdPlanDetailWsPayload> {
  // Keep payload bounded: enough for current UI use (history default -30 days).
  const res = await pool.query(`
    DECLARE @fromDate date = DATEADD(day, -31, CAST(GETDATE() AS date));

    SELECT
      FID,
      PROD_DATE,
      SHIFT,
      MODEL_NAME,
      ORDER_TYPE,
      QTY_PLAN,
      QTY_ACTUAL,
      CREATED_AT,
      UPDATED_AT
    FROM dbo.TB_H_PROD_PLAN_DETAIL
    WHERE PROD_DATE >= @fromDate
    ORDER BY PROD_DATE DESC, SHIFT ASC, MODEL_NAME ASC, ORDER_TYPE ASC;
  `)

  const rows = (res.recordset ?? []).map(mapRow)
  return {
    kind: 'snapshot',
    updatedAt: formatDateTime(new Date()),
    fromProdDate: formatDate(new Date(Date.now() - 31 * 24 * 60 * 60 * 1000)),
    rows,
  }
}

async function fetchDelta(
  pool: any,
  changes: any[],
): Promise<ProdPlanDetailWsPayload> {
  const ids = Array.from(
    new Set(
      (changes ?? [])
        .map((c) => Number(c.FID))
        .filter((n) => Number.isFinite(n) && n > 0),
    ),
  )

  if (ids.length === 0) {
    return {
      kind: 'delta',
      updatedAt: formatDateTime(new Date()),
      changedCount: 0,
      rows: [],
    }
  }

  const res = await pool.query(`
    SELECT
      FID,
      PROD_DATE,
      SHIFT,
      MODEL_NAME,
      ORDER_TYPE,
      QTY_PLAN,
      QTY_ACTUAL,
      CREATED_AT,
      UPDATED_AT
    FROM dbo.TB_H_PROD_PLAN_DETAIL
    WHERE FID IN (${ids.join(',')});
  `)

  return {
    kind: 'delta',
    updatedAt: formatDateTime(new Date()),
    changedCount: ids.length,
    rows: (res.recordset ?? []).map(mapRow),
  }
}

export const prodPlanDetailPolling = createCTPolling({
  tableName: 'TB_H_PROD_PLAN_DETAIL',
  eventName: 'prod-plan-detail:update',
  pollingLogic: fetchSnapshot,
  pollingLogicOnChanges: fetchDelta,
})
