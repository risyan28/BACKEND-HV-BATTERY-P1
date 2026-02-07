// src/services/traceability.service.ts

import prisma from '@/prisma'
import * as fs from 'fs'
import * as path from 'path'

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
   * Get traceability data by production date range
   * Note: Nama kolom dari TB_H_PRINT_LOG diberi suffix "_PrintLog"
   * misal: PROD_DATE → PROD_DATE_PrintLog
   */
  async getByDateRange(from: string, to: string) {
    try {
      // Cek apakah view exists
      const viewCheck = await prisma.$queryRawUnsafe<any[]>(`
        SELECT COUNT(*) as cnt
        FROM INFORMATION_SCHEMA.VIEWS
        WHERE TABLE_NAME = 'VW_TRACEABILITY_PIS'
      `)

      if (!viewCheck[0]?.cnt || viewCheck[0].cnt === 0) {
        throw new Error(
          'View VW_TRACEABILITY_PIS does not exist. Please run: EXEC sp_RefreshBatteryTraceabilityView;'
        )
      }

      // Query ke view VW_TRACEABILITY_PIS
      // Gunakan SELECT * karena struktur kolom dinamis (pivot tightening)
      console.log('🔍 Querying VW_TRACEABILITY_PIS...')
      console.log(`   Date Range: ${from} to ${to}`)
      
      const result = await prisma.$queryRawUnsafe<any[]>(`
        SELECT *
        FROM VW_TRACEABILITY_PIS
        WHERE PROD_DATE_PrintLog IS NOT NULL
          AND CAST(PROD_DATE_PrintLog AS DATE) BETWEEN @p1 AND @p2
        ORDER BY UNLOADING_TIME DESC, PACK_ID
      `, from, to)

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
          'View structure issue. Please refresh the view by running: EXEC sp_RefreshBatteryTraceabilityView;'
        )
      }
      
      throw new Error('Failed to fetch traceability data: ' + error.message)
    }
  },
}
