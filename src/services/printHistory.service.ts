// src/services/printHistory.service.ts

import prisma from '@/prisma'

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
  async getByDateRange(from: string, to: string) {
    const fromDate = new Date(from)
    const toDate = new Date(to)
    toDate.setDate(toDate.getDate() + 1) // include whole "to" day

    const records = await prisma.tB_H_PRINT_LOG.findMany({
      where: {
        PROD_DATE: {
          gte: fromDate,
          lt: toDate,
        },
      },
      orderBy: { DATETIME_MODIFIED: 'desc' },
    })
    return records.map(formatPrintHistory)
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

    // 🖨️ Trigger re-print (pakai PRINT_QRCODE sebagai data utama)
    console.log(
      `🖨️ Re-print QR: ${record.PRINT_QRCODE} model: ${
        record.FMODEL_BATTERY || 'unknown'
      }`
    )
    return { success: true, message: 'Re-print triggered' }
  },
}
