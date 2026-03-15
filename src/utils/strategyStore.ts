// src/utils/strategyStore.ts
// In-memory singleton that holds the current sequence strategy.
// Shared by the REST controller (write) and the WS poller (read).
// Survives as long as the Node process is alive; resets to 'normal' on restart.

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
  get(): SequenceStrategy {
    return { ..._strategy }
  },

  set(strategy: Partial<SequenceStrategy>): SequenceStrategy {
    _strategy = { ..._strategy, ...strategy }
    return { ..._strategy }
  },

  reset(): SequenceStrategy {
    _strategy = { ...DEFAULT_STRATEGY }
    return { ..._strategy }
  },
}
