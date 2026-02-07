// src/services/printHistory.service.ts

import prisma from '@/prisma'
import { cache } from '@/utils/cache'
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
 * Format DateTime ke string "YYYY-MM-DD HH:mm:ss.SSS"
 */
const formatDateTime = (date: Date | null | undefined): string => {
  if (!date) return ''
  return date.toISOString().replace('T', ' ').replace('Z', '').slice(0, 23)
}

/**
 * Format Date ke string "YYYY-MM-DD"
 */
const formatDate = (date: Date | null | undefined): string => {
  if (!date) return ''
  return date.toISOString().split('T')[0]
}

/**
 * Format record dari TB_H_PRINT_LOG ke PrintHistory (FE format)
 */
const formatPrintHistory = (record: any) => {
  return {
    // 🔸 FID (Int) → konversi ke string (karena FE pakai string ID)
    id: record.FID.toString(),

    // 🔸 PRINT_QRCODE sebagai batteryPackId
    batteryPackId: record.PRINT_QRCODE || `FID-${record.FID}`,

    // 🔸 PROD_DATE → productionDate
    productionDate: formatDate(record.PROD_DATE),

    // 🔸 FSHIFT → map ke 'DAY'/'NIGHT'
    shift: mapShift(record.FSHIFT),

    // 🔸 DATETIME_MODIFIED sebagai timePrint (asumsi: waktu terakhir di-print/ubah)
    timePrint:
      formatDateTime(record.DATETIME_MODIFIED) ||
      formatDateTime(record.DATETIME_RECEIVED),

    // 🔸 FMODEL_BATTERY
    modelBattery: record.FMODEL_BATTERY,
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
        return records.map(formatPrintHistory)
      },
      CACHE_CONFIG.TTL,
    )
  },

  async reprint(id: string) {
    const fid = parseInt(id, 10)
    if (isNaN(fid)) throw new Error('Invalid ID')

    const record = await prisma.tB_H_PRINT_LOG.findUnique({
      where: { FID: fid },
    })

    if (!record) throw new Error('Print log not found')

    if (!record.PRINT_QRCODE) {
      throw new Error('PRINT_QRCODE is required for re-print')
    }

    // Insert data ke TB_R_PRINT_LABEL
    await prisma.tB_R_PRINT_LABEL.create({
      data: {
        FPRINT_QRCODE: record.PRINT_QRCODE,
        FMODEL_BATTERY: record.FMODEL_BATTERY,
        FDATETIME_MODIFIED: new Date(),
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
