// src/ws/setup.ts
import { Server } from 'http'
import { initConnectionHandler } from './connectionHandler'
import { sequencePolling } from './SEQUENCE_BATTERY/TB_R_SEQUENCE_BATTERY.ws'
import { andonSummaryPolling } from './ANDON/andonSummaryPolling.ws'
import { andonCallPolling } from './ANDON/andonCallPolling.ws'
import { posStatusPolling } from './ANDON/posStatusPolling.ws'
import { downtimePolling } from './ANDON/downtimePolling.ws'
import { manBracketPolling } from './MAN_BRACKET/TB_R_MAN_BRACKET.ws'
import { prodPlanDetailPolling } from './PRODUCTION_PLAN/TB_H_PROD_PLAN_DETAIL.ws'

export function setupWebSocket(httpServer: Server) {
  initConnectionHandler(httpServer, [
    {
      name: 'sequences',
      module: sequencePolling,
      eventName: 'sequences:update',
    },
    {
      name: 'summary',
      module: andonSummaryPolling,
      eventName: 'summary:update',
    },
    { name: 'calls', module: andonCallPolling, eventName: 'calls:update' },
    {
      name: 'processes',
      module: posStatusPolling,
      eventName: 'processes:update',
    },
    { name: 'downtime', module: downtimePolling, eventName: 'downtime:update' },
    {
      name: 'man-bracket',
      module: manBracketPolling,
      eventName: 'man-bracket:update',
    },
    {
      name: 'prod-plan-detail',
      module: prodPlanDetailPolling,
      eventName: 'prod-plan-detail:update',
    },
  ])
}
