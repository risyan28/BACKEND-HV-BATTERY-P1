// src/services/traceability.service.ts

import prisma from '@/prisma'
import { cache } from '@/utils/cache'
import { formatDate } from '@/utils/date'
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
 * Normalize date-only value to string "YYYY-MM-DD".
 * - If DB returns string, keep prefix (no timezone shifting).
 * - If DB returns Date, format consistently for UI.
 */
const normalizeDateOnly = (value: any): string => {
  if (!value) return ''
  if (typeof value === 'string') return value.substring(0, 10)
  if (value instanceof Date) return formatDate(value) || ''
  return String(value).substring(0, 10)
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
          // Calculate pagination
          const offset = (page - 1) * limit

          console.log('🔍 Querying VW_TRACEABILITY_PIS...')
          console.log(`   Date Range: ${from} to ${to}`)
          console.log(
            `   Pagination: page=${page}, limit=${limit}, offset=${offset}`,
          )

          const querySQL = `
            SELECT *
            FROM VW_TRACEABILITY_PIS WITH (NOLOCK)
            WHERE PROD_DATE IS NOT NULL
              AND PROD_DATE BETWEEN @p1 AND @p2
            ORDER BY PROD_DATE DESC, PACK_ID
            OFFSET @p3 ROWS
            FETCH NEXT @p4 ROWS ONLY
            OPTION (RECOMPILE)
          `

          let result = await prisma.$queryRawUnsafe<any[]>(
            querySQL,
            from,
            to,
            offset,
            limit,
          )
          console.log(`✅ Query successful! Found ${result.length} records`)

          // Format date/datetime columns
          return result.map((row) => {
            const formatted: any = { ...row }

            // Format date-only columns (YYYY-MM-DD)
            const dateOnlyColumns = [
              'PROD_DATE',
              'TMMIN_Cell_Measurement_date_Module',
              'Supplier_Cell_Measurement_date_Module',
            ]

            dateOnlyColumns.forEach((col) => {
              if (formatted[col]) {
                formatted[col] = normalizeDateOnly(formatted[col])
              }
            })

            return formatted
          })
        } catch (error: any) {
          console.error(
            '❌ Error fetching traceability data:',
            error.code || error.message,
          )

          // Auto-refresh view jika ada "Invalid column name" (P2010) lalu retry
          if (
            error.code === 'P2010' ||
            (error.message && error.message.includes('Invalid column name'))
          ) {
            console.warn(
              '⚠️  View structure stale — auto-refreshing VW_TRACEABILITY_PIS...',
            )
            try {
              await prisma.$executeRawUnsafe(
                'EXEC sp_RefreshBatteryTraceabilityView;',
              )
              console.log('✅ View refreshed — retrying query...')

              const offset = (page - 1) * limit
              const retryResult = await prisma.$queryRawUnsafe<any[]>(
                `
                SELECT *
                FROM VW_TRACEABILITY_PIS
                WHERE PROD_DATE IS NOT NULL
                  AND PROD_DATE BETWEEN @p1 AND @p2
                ORDER BY PROD_DATE DESC, PACK_ID
                OFFSET @p3 ROWS
                FETCH NEXT @p4 ROWS ONLY
              `,
                from,
                to,
                offset,
                limit,
              )
              console.log(
                `✅ Retry successful! Found ${retryResult.length} records`,
              )

              // Format date/datetime columns (same as main query)
              return retryResult.map((row) => {
                const formatted: any = { ...row }

                const dateOnlyColumns = [
                  'PROD_DATE',
                  'TMMIN_Cell_Measurement_date_Module',
                  'Supplier_Cell_Measurement_date_Module',
                ]

                dateOnlyColumns.forEach((col) => {
                  if (formatted[col]) {
                    formatted[col] = normalizeDateOnly(formatted[col])
                  }
                })

                return formatted
              })
            } catch (refreshError: any) {
              console.error(
                '❌ View refresh or retry failed:',
                refreshError.message,
              )
              throw new Error(
                'View refresh failed. Please run manually: EXEC sp_RefreshBatteryTraceabilityView; — ' +
                  refreshError.message,
              )
            }
          }

          throw new Error('Failed to fetch traceability data: ' + error.message)
        }
      },
      CACHE_CONFIG.TTL,
    )
  },
}
