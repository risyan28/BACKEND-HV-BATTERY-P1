import { createCTPolling } from '@/ws/poller.ws'
import { formatDateTime } from '@/utils/date'

function mapManBracketRecord(record: any) {
  return {
    FID: Number(record.FID),
    BARCODE: record.BARCODE ?? null,
    DESTINATION: record.DESTINATION ?? null,
    FMODEL_BATTERY: record.FMODEL_BATTERY ?? null,
    FVALUE: Number(record.FVALUE ?? 0),
    START_TIME: formatDateTime(record.START_TIME),
    COMPLETED_TIME: formatDateTime(record.COMPLETED_TIME),
  }
}

async function fetchSnapshot(pool: any) {
  const result = await pool.query(`
    SELECT TOP 200
      FID,
      BARCODE,
      DESTINATION,
      FMODEL_BATTERY,
      FVALUE,
      START_TIME,
      COMPLETED_TIME
    FROM TB_R_MAN_BRACKET
    ORDER BY START_TIME DESC, FID DESC
  `)

  return {
    records: result.recordset.map(mapManBracketRecord),
    updatedAt: formatDateTime(new Date()),
  }
}

export const manBracketPolling = createCTPolling({
  tableName: 'TB_R_MAN_BRACKET',
  eventName: 'man-bracket:update',
  pollingLogic: fetchSnapshot,
})
