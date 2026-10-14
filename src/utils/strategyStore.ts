// src/utils/strategyStore.ts
// Sequence strategy store.
//
// State is PERSISTED in TB_M_SEQUENCE_STRATEGY (single row, FID=1) so that a
// backend restart / deploy / crash does NOT silently reset the active strategy
// back to 'normal'. In-memory cache mirrors the DB row for fast reads.
//
// Lifecycle:
//   init()  -> called once at startup (index.ts) to load from DB
//   set()   -> write-through: updates memory AND DB atomically
//   get()   -> fast in-memory read (no DB hit per request)
//
// Shared by the REST controller (write) and the WS poller (read).

import prisma from '@/prisma'

export type StrategyOrderType = 'ASSY' | 'CKD' | 'SERVICE PART'

export type StrategyMode = 'normal' | 'priority' | 'ratio'

export interface SequenceStrategy {
  mode: StrategyMode
  priorityType: StrategyOrderType
  ratioPrimary: StrategyOrderType
  ratioSecondary: StrategyOrderType
  ratioTertiary: StrategyOrderType
  ratioValues: Record<StrategyOrderType, number>
}

const DEFAULT_STRATEGY: SequenceStrategy = {
  mode: 'normal',
  priorityType: 'ASSY',
  ratioPrimary: 'ASSY',
  ratioSecondary: 'CKD',
  ratioTertiary: 'SERVICE PART',
  ratioValues: { ASSY: 2, CKD: 1, 'SERVICE PART': 1 },
}

let _strategy: SequenceStrategy = { ...DEFAULT_STRATEGY }

export const strategyStore = {
  /**
   * Load the persisted strategy from TB_M_SEQUENCE_STRATEGY at startup.
   * If the table is empty (fresh install) we seed a default row so the
   * single-row invariant is always satisfied.
   */
  async init(): Promise<SequenceStrategy> {
    const row = await prisma.tB_M_SEQUENCE_STRATEGY.findUnique({
      where: { FID: 1 },
    })

    if (!row) {
      await prisma.tB_M_SEQUENCE_STRATEGY.create({
        data: {
          FID: 1,
          MODE: DEFAULT_STRATEGY.mode,
          PRIORITY_TYPE: DEFAULT_STRATEGY.priorityType,
          RATIO_PRIMARY: DEFAULT_STRATEGY.ratioPrimary,
          RATIO_SECONDARY: DEFAULT_STRATEGY.ratioSecondary,
          RATIO_TERTIARY: DEFAULT_STRATEGY.ratioTertiary,
          RATIO_ASSY: DEFAULT_STRATEGY.ratioValues.ASSY,
          RATIO_CKD: DEFAULT_STRATEGY.ratioValues.CKD,
          RATIO_SERVICE_PART: DEFAULT_STRATEGY.ratioValues['SERVICE PART'],
          UPDATED_BY: 'system',
        },
      })
      _strategy = { ...DEFAULT_STRATEGY }
      return { ..._strategy }
    }

    _strategy = {
      mode: (row.MODE as StrategyMode) ?? DEFAULT_STRATEGY.mode,
      priorityType:
        (row.PRIORITY_TYPE as StrategyOrderType) ?? DEFAULT_STRATEGY.priorityType,
      ratioPrimary:
        (row.RATIO_PRIMARY as StrategyOrderType) ??
        DEFAULT_STRATEGY.ratioPrimary,
      ratioSecondary:
        (row.RATIO_SECONDARY as StrategyOrderType) ??
        DEFAULT_STRATEGY.ratioSecondary,
      ratioTertiary:
        (row.RATIO_TERTIARY as StrategyOrderType) ??
        DEFAULT_STRATEGY.ratioTertiary,
      ratioValues: {
        ASSY: row.RATIO_ASSY ?? DEFAULT_STRATEGY.ratioValues.ASSY,
        CKD: row.RATIO_CKD ?? DEFAULT_STRATEGY.ratioValues.CKD,
        'SERVICE PART':
          row.RATIO_SERVICE_PART ?? DEFAULT_STRATEGY.ratioValues['SERVICE PART'],
      },
    }

    return { ..._strategy }
  },

  get(): SequenceStrategy {
    return { ..._strategy }
  },

  /**
   * Write-through: update the in-memory cache AND persist to DB in one call.
   * Survives backend restarts / deploys / crashes.
   */
  async set(strategy: Partial<SequenceStrategy>): Promise<SequenceStrategy> {
    _strategy = {
      ..._strategy,
      ...strategy,
      ratioValues: {
        ..._strategy.ratioValues,
        ...(strategy.ratioValues ?? {}),
      },
    }

    await prisma.tB_M_SEQUENCE_STRATEGY.upsert({
      where: { FID: 1 },
      update: {
        MODE: _strategy.mode,
        PRIORITY_TYPE: _strategy.priorityType,
        RATIO_PRIMARY: _strategy.ratioPrimary,
        RATIO_SECONDARY: _strategy.ratioSecondary,
        RATIO_TERTIARY: _strategy.ratioTertiary,
        RATIO_ASSY: _strategy.ratioValues.ASSY,
        RATIO_CKD: _strategy.ratioValues.CKD,
        RATIO_SERVICE_PART: _strategy.ratioValues['SERVICE PART'],
        UPDATED_AT: new Date(),
        UPDATED_BY: 'api',
      },
      create: {
        FID: 1,
        MODE: _strategy.mode,
        PRIORITY_TYPE: _strategy.priorityType,
        RATIO_PRIMARY: _strategy.ratioPrimary,
        RATIO_SECONDARY: _strategy.ratioSecondary,
        RATIO_TERTIARY: _strategy.ratioTertiary,
        RATIO_ASSY: _strategy.ratioValues.ASSY,
        RATIO_CKD: _strategy.ratioValues.CKD,
        RATIO_SERVICE_PART: _strategy.ratioValues['SERVICE PART'],
        UPDATED_BY: 'api',
      },
    })

    return { ..._strategy }
  },

  reset(): SequenceStrategy {
    _strategy = { ...DEFAULT_STRATEGY }
    return { ..._strategy }
  },
}
