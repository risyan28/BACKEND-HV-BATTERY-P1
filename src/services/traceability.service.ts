// src/services/traceability.service.ts

import prisma from '@/prisma'
import * as fs from 'fs'
import * as path from 'path'
import { cache } from '@/utils/cache'
import { loggers } from '@/utils/logger'

/**
 * Cache configuration for traceability
 * Longer TTL because historical data rarely changes
 */
const CACHE_CONFIG = {
  KEY_PREFIX: 'traceability:',
  TTL: 900, // 15 minutes - historical data
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

export const traceabilityService = {
  /**
   * ✅ PHASE 3: Redis cache implemented + Pagination
   * Cache key: traceability:{from}:{to}:{page}:{limit}
   * TTL: 15 minutes (historical data rarely changes)
   * Get traceability data by production date range with pagination
   * Note: Nama kolom dari TB_H_PRINT_LOG diberi suffix "_PrintLog"
   * misal: PROD_DATE → PROD_DATE_PrintLog
   */
  async getByDateRange(
    from: string,
    to: string,
    page: number = 1,
    limit: number = 1000,
  ) {
    const cacheKey = `${CACHE_CONFIG.KEY_PREFIX}${from}:${to}:${page}:${limit}`

    return cache.getOrSet(
      cacheKey,
      async () => {
        loggers.db.debug(
          { from, to, page, limit },
          'Fetching traceability from database (cache miss)',
        )
        try {
          // Cek apakah view exists
          const viewCheck = await prisma.$queryRawUnsafe<any[]>(`
            SELECT COUNT(*) as cnt
            FROM INFORMATION_SCHEMA.VIEWS
            WHERE TABLE_NAME = 'VW_TRACEABILITY_PIS'
          `)

          if (!viewCheck[0]?.cnt || viewCheck[0].cnt === 0) {
            throw new Error(
              'View VW_TRACEABILITY_PIS does not exist. Please run: EXEC sp_RefreshBatteryTraceabilityView;',
            )
          }

          // Calculate pagination
          const offset = (page - 1) * limit

          // Query ke view VW_TRACEABILITY_PIS with pagination
          // Gunakan SELECT * karena struktur kolom dinamis (pivot tightening)
          console.log('🔍 Querying VW_TRACEABILITY_PIS...')
          console.log(`   Date Range: ${from} to ${to}`)
          console.log(
            `   Pagination: page=${page}, limit=${limit}, offset=${offset}`,
          )

          const result = await prisma.$queryRawUnsafe<any[]>(
            `
            SELECT *
            FROM VW_TRACEABILITY_PIS
            WHERE PROD_DATE_PrintLog IS NOT NULL
              AND CAST(PROD_DATE_PrintLog AS DATE) BETWEEN @p1 AND @p2
            ORDER BY UNLOADING_TIME DESC, PACK_ID
            OFFSET @p3 ROWS
            FETCH NEXT @p4 ROWS ONLY
          `,
            from,
            to,
            offset,
            limit,
          )
          console.log(`✅ Query successful! Found ${result.length} records`)

          // Save ALL records to JSON file (pure database response)
          //   if (result.length > 0) {
          //     const outputPath = path.join(__dirname, '../../traceability-sample-response.json')

          //     fs.writeFileSync(outputPath, JSON.stringify(result, null, 2), 'utf-8')
          //     console.log(`\n📄 All ${result.length} records saved to: ${outputPath}`)
          //     console.log(`   Total columns per record: ${Object.keys(result[0]).length}\n`)
          //   }

          // Return raw result (kolom sudah dalam format yang benar dari view)
          return result
        } catch (error: any) {
          console.error('❌ Error fetching traceability data:', error)

          // Berikan error message yang lebih helpful
          if (error.message.includes('Invalid column name')) {
            throw new Error(
              'View structure issue. Please refresh the view by running: EXEC sp_RefreshBatteryTraceabilityView;',
            )
          }

          throw new Error('Failed to fetch traceability data: ' + error.message)
        }
      },
      CACHE_CONFIG.TTL,
    )
  },
}
