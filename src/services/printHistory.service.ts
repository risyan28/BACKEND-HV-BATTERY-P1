// src/services/printHistory.service.ts

import prisma from '@/prisma'
import { cache } from '@/utils/cache'
import { formatDate, formatDateTime, toJakartaDbDate } from '@/utils/date'
import { loggers } from '@/utils/logger'

/**
 * Cache configuration for print history
 */
const CACHE_CONFIG = {
  KEY_PREFIX: 'printHistory:',
  TTL: 900, // 15 minutes - historical data
}

/**
 * Helper: Invalidate print history cache
 */
const invalidateCache = async () => {
  // Clear all print history cache entries
  await cache.delPattern(`${CACHE_CONFIG.KEY_PREFIX}*`)
  loggers.cache.debug(
    { pattern: `${CACHE_CONFIG.KEY_PREFIX}*` },
    'Print history cache invalidated',
  )
}

/**
 * Konversi nilai shift dari DB ke format FE ('DAY' | 'NIGHT')
 */
const mapShift = (dbShift: string | null | undefined): 'DAY' | 'NIGHT' => {
  if (!dbShift) return 'DAY' // default

  // Sesuaikan dengan logika shift di sistem kamu
  if (dbShift === '1' || dbShift === 'P' || dbShift === 'DAY') return 'DAY'
  if (dbShift === '2' || dbShift === 'M' || dbShift === 'NIGHT') return 'NIGHT'

  return 'DAY' // fallback
}

/**
 * Format record dari TB_H_PRINT_LOG ke PrintHistory (FE format)
 */
const formatPrintHistory = (
  record: any,
  firstPrintFidByQr: Record<string, number>,
  reprintSequenceByFid: Record<number, number>,
) => {
  const printDateTimeSource =
    record.DATETIME_MODIFIED ?? record.DATETIME_RECEIVED ?? null

  const qr = record.PRINT_QRCODE ? String(record.PRINT_QRCODE) : ''
  const firstFid = qr ? firstPrintFidByQr[qr] : undefined
  const printType =
    firstFid && record.FID === firstFid ? 'ORIGINAL' : 'RE-PRINT'
  const reprintSequence = reprintSequenceByFid[record.FID] ?? 0

  return {
    // 🔸 FID (Int) → keep as number (FE expects number type)
    id: record.FID,

    // 🔸 PRINT_QRCODE sebagai battery_pack_id (snake_case for FE)
    battery_pack_id: record.PRINT_QRCODE || `FID-${record.FID}`,

    // 🔸 PROD_DATE → production_date (snake_case, ISO format)
    production_date: formatDate(record.PROD_DATE) || null,

    // 🔸 FSHIFT → map ke 'DAY'/'NIGHT'
    shift: mapShift(record.FSHIFT),

    // 🔸 DATETIME_MODIFIED sebagai print_datetime (snake_case, YYYY-MM-DD HH:mm:ss)
    print_datetime: formatDateTime(printDateTimeSource) || null,

    // 🔸 FMODEL_BATTERY sebagai model_battery (snake_case)
    model_battery: record.FMODEL_BATTERY,

    // 🔸 ORDER_TYPE (snake_case)
    order_type: record.ORDER_TYPE || null,

    // 🔸 Classification print original vs re-print
    print_type: printType,
    reprint_sequence: reprintSequence,
  }
}

export const printHistoryService = {
  /**
   * ✅ PHASE 3: Redis cache implemented + Pagination
   * Cache key: printHistory:{from}:{to}:{page}:{limit}
   * TTL: 15 minutes (historical data)
   * Invalidated on: reprint()
   */
  async getByDateRange(
    from: string,
    to: string,
    page: number = 1,
    limit: number = 100,
  ) {
    const cacheKey = `${CACHE_CONFIG.KEY_PREFIX}${from}:${to}:${page}:${limit}`

    return cache.getOrSet(
      cacheKey,
      async () => {
        loggers.db.debug(
          { from, to, page, limit },
          'Fetching print history from database (cache miss)',
        )
        const fromDate = new Date(from)
        const toDate = new Date(to)
        toDate.setDate(toDate.getDate() + 1) // include whole "to" day

        // Calculate pagination
        const skip = (page - 1) * limit

        const records = await prisma.tB_H_PRINT_LOG.findMany({
          where: {
            PROD_DATE: {
              gte: fromDate,
              lt: toDate,
            },
          },
          orderBy: { DATETIME_MODIFIED: 'desc' },
          skip: skip,
          take: limit,
        })

        const qrCodes = Array.from(
          new Set(
            records
              .map((record) => record.PRINT_QRCODE)
              .filter(
                (value): value is string =>
                  typeof value === 'string' && value.trim().length > 0,
              ),
          ),
        )

        const firstPrintGroups =
          qrCodes.length > 0
            ? await prisma.tB_H_PRINT_LOG.groupBy({
                by: ['PRINT_QRCODE'],
                where: {
                  PRINT_QRCODE: {
                    in: qrCodes,
                  },
                },
                _min: {
                  FID: true,
                },
              })
            : []

        const firstPrintFidByQr = firstPrintGroups.reduce<
          Record<string, number>
        >((acc, item) => {
          if (item.PRINT_QRCODE && item._min.FID) {
            acc[item.PRINT_QRCODE] = item._min.FID
          }
          return acc
        }, {})

        const historyRowsByQr =
          qrCodes.length > 0
            ? await prisma.tB_H_PRINT_LOG.findMany({
                where: {
                  PRINT_QRCODE: {
                    in: qrCodes,
                  },
                },
                select: {
                  FID: true,
                  PRINT_QRCODE: true,
                },
                orderBy: {
                  FID: 'asc',
                },
              })
            : []

        const reprintCounterByQr: Record<string, number> = {}
        const reprintSequenceByFid = historyRowsByQr.reduce<
          Record<number, number>
        >((acc, row) => {
          const qr = row.PRINT_QRCODE ?? ''
          const firstFid = qr ? firstPrintFidByQr[qr] : undefined

          if (!firstFid || row.FID === firstFid) {
            acc[row.FID] = 0
            return acc
          }

          reprintCounterByQr[qr] = (reprintCounterByQr[qr] ?? 0) + 1
          acc[row.FID] = reprintCounterByQr[qr]
          return acc
        }, {})

        return records.map((record) =>
          formatPrintHistory(record, firstPrintFidByQr, reprintSequenceByFid),
        )
      },
      CACHE_CONFIG.TTL,
    )
  },

  async reprint(id: string, productionDate?: string) {
    const fid = parseInt(id, 10)
    if (isNaN(fid)) throw new Error('Invalid ID')

    const record = await prisma.tB_H_PRINT_LOG.findUnique({
      where: { FID: fid },
    })

    if (!record) throw new Error('Print log not found')

    if (!record.PRINT_QRCODE) {
      throw new Error('PRINT_QRCODE is required for re-print')
    }

    const resolvedProdDate = productionDate
      ? toJakartaDbDate(`${productionDate} 00:00:00`)
      : (record.PROD_DATE ?? null)

    // Insert data ke TB_R_PRINT_LABEL
    await prisma.tB_R_PRINT_LABEL.create({
      data: {
        FPRINT_QRCODE: record.PRINT_QRCODE,
        FMODEL_BATTERY: record.FMODEL_BATTERY,
        FDATETIME_MODIFIED: toJakartaDbDate(),
        PROD_DATE: resolvedProdDate,
        ORDER_TYPE: record.ORDER_TYPE ?? null,
      },
    })

    // ✅ Invalidate cache after mutation
    await invalidateCache()

    // 🖨️ Trigger re-print (pakai PRINT_QRCODE sebagai data utama)
    console.log(
      `🖨️ Re-print QR: ${record.PRINT_QRCODE} model: ${
        record.FMODEL_BATTERY || 'unknown'
      }`,
    )
    return { success: true, message: 'Re-print triggered' }
  },
}
