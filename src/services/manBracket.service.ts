// src/services/manBracket.service.ts

import prisma from '@/prisma'
import { toJakartaDbDate } from '@/utils/date'

const TRANSMIT_DEV_NAME = 'PLC_HV_BATT.STATION MAN BRACKET'
const TRANSMIT_REG_NAME = 'INTERLOCK'
const TRANSMIT_ID = 10

const WTG_LINENAME = process.env.WTG_LINENAME || 'ADAPTIVE'

const extractPackPartBattery = (barcode: string): string | null => {
  const normalized = String(barcode ?? '')
    .trim()
    .toUpperCase()
  // Example: "---PE--F70401DG4H0000002" -> "F7040"
  const match = normalized.match(/[A-Z]\d{4}/)
  return match?.[0] ?? null
}

const toDbDateOnly = (input?: string | Date | null): Date => {
  const dt = !input
    ? toJakartaDbDate()
    : typeof input === 'string'
      ? toJakartaDbDate(input)
      : input

  return new Date(
    Date.UTC(dt.getUTCFullYear(), dt.getUTCMonth(), dt.getUTCDate()),
  )
}

export const manBracketService = {
  /**
   * Write interlock transmit value to T_TRANSMIT table
   */
  writeInterlockTransmit: async (value: 0 | 1) => {
    await prisma.$executeRaw`
      INSERT INTO [DB_MYOPC_CLIENT_PIS_HV_BATTERY_P1].[dbo].[T_TRANSMIT] (
        DEV_NAME,
        REG_NAME,
        REG_VALUE,
        TTL,
        TR_TIME,
        ID
      ) VALUES (
        ${TRANSMIT_DEV_NAME},
        ${TRANSMIT_REG_NAME},
        ${value},
        ${0},
        GETDATE(),
        ${TRANSMIT_ID}
      )
    `
  },

  /**
   * Start Man Bracket Process
   */
  startProcess: async (
    barcode: string,
    destination: string,
    startTime?: string,
  ) => {
    const barcodeTrimmed = String(barcode ?? '').trim()
    const packPartBattery = extractPackPartBattery(barcodeTrimmed)
    const startTimeDb = toJakartaDbDate(startTime)

    const [printLogRows, wtgRegRows, modelRows] = await Promise.all([
      prisma.$queryRaw<{ PROD_DATE: Date | null }[]>`
        SELECT TOP 1 PROD_DATE
        FROM dbo.TB_H_PRINT_LOG
        WHERE UPPER(LTRIM(RTRIM(ISNULL(PRINT_QRCODE, '')))) = UPPER(LTRIM(RTRIM(${barcodeTrimmed})))
        ORDER BY DATETIME_MODIFIED DESC, FID DESC
      `,
      prisma.$queryRaw<{ REG_NAME: string; REG_VALUE: string | null }[]>`
        SELECT REG_NAME, REG_VALUE
        FROM [DB_TMMIN1_KRW_WTG_HV_BATTERY].[dbo].[TB_WTG_REG]
        WHERE LINENAME = ${WTG_LINENAME}
          AND REG_NAME IN ('SHIFT_LABEL', 'SHIFT_DATE')
      `,
      packPartBattery
        ? prisma.$queryRaw<{ FMODEL_BATTERY: string | null }[]>`
            SELECT TOP 1 m.FMODEL_BATTERY
            FROM dbo.TB_M_BATTERY_MAPPING m
            WHERE LTRIM(RTRIM(ISNULL(m.FPACK_PART_BATTERY, ''))) = ${packPartBattery}
              AND UPPER(LTRIM(RTRIM(ISNULL(m.ORDER_TYPE, '')))) = UPPER(${destination})
              AND m.FMODEL_BATTERY IS NOT NULL
              AND LTRIM(RTRIM(m.FMODEL_BATTERY)) <> ''
          `
        : Promise.resolve([]),
    ])

    const regByName = new Map(
      (wtgRegRows ?? []).map((r) => [String(r.REG_NAME), r.REG_VALUE ?? null]),
    )
    const shiftLabel = regByName.get('SHIFT_LABEL') ?? null
    const shiftDateStr = regByName.get('SHIFT_DATE') ?? null
    const modelBattery = modelRows?.[0]?.FMODEL_BATTERY ?? null

    // PROD_DATE must follow WTG logical shift date (SHIFT_DATE).
    // Fallbacks are kept to avoid NULL when WTG ticker/reg is unavailable.
    const prodDateFromShift = shiftDateStr ? toDbDateOnly(shiftDateStr) : null
    const prodDateFromPrintLog = printLogRows?.[0]?.PROD_DATE
      ? toDbDateOnly(printLogRows[0].PROD_DATE)
      : null
    const prodDate =
      prodDateFromShift ?? prodDateFromPrintLog ?? toDbDateOnly(startTimeDb)

    return prisma.tB_R_MAN_BRACKET.create({
      data: {
        BARCODE: barcodeTrimmed,
        DESTINATION: destination,
        FMODEL_BATTERY: modelBattery,
        PROD_DATE: prodDate,
        SHIFT: shiftLabel,
        START_TIME: startTimeDb,
        COMPLETED_TIME: null,
        FVALUE: 0,
      },
    })
  },

  /**
   * Complete Man Bracket Process Data
   */
  completeProcess: async (recordId: number, completedTime?: string) => {
    return prisma.tB_R_MAN_BRACKET.update({
      where: { FID: Number(recordId) },
      data: {
        COMPLETED_TIME: toJakartaDbDate(completedTime),
        FVALUE: 1,
      },
    })
  },

  /**
   * Reset Man Bracket Process Data
   */
  resetProcess: async (recordId: number) => {
    return prisma.tB_R_MAN_BRACKET.delete({
      where: { FID: Number(recordId) },
    })
  },

  /**
   * Get Man Bracket Records
   */
  getRecords: async (
    limit: number = 50,
    offset: number = 0,
    destination?: string,
    fvalue?: number,
  ) => {
    const whereClause: any = {}
    if (destination) whereClause.DESTINATION = destination
    if (fvalue !== undefined) whereClause.FVALUE = Number(fvalue)

    const parsedFvalue = fvalue !== undefined ? Number(fvalue) : undefined
    const orderByClause =
      parsedFvalue === 1
        ? [{ COMPLETED_TIME: 'asc' as const }, { FID: 'asc' as const }]
        : [{ START_TIME: 'desc' as const }, { FID: 'desc' as const }]

    const records = await prisma.tB_R_MAN_BRACKET.findMany({
      where: whereClause,
      orderBy: orderByClause,
      take: Math.min(Number(limit), 100),
      skip: Number(offset),
    })

    const total = await prisma.tB_R_MAN_BRACKET.count({
      where: whereClause,
    })

    return { records, total }
  },

  /**
   * Get Single Man Bracket Record
   */
  getRecord: async (id: number) => {
    return prisma.tB_R_MAN_BRACKET.findUnique({
      where: { FID: Number(id) },
    })
  },

  /**
   * Get Statistics
   */
  getStats: async (startDate?: string, endDate?: string) => {
    const whereClause: any = {}
    if (startDate || endDate) {
      whereClause.START_TIME = {}
      if (startDate) {
        whereClause.START_TIME.gte = new Date(startDate as string)
      }
      if (endDate) {
        whereClause.START_TIME.lte = new Date(endDate as string)
      }
    }

    const stats = await prisma.tB_R_MAN_BRACKET.groupBy({
      by: ['DESTINATION', 'FVALUE'],
      where: whereClause,
      _count: {
        FID: true,
      },
    })

    const totalRecords = await prisma.tB_R_MAN_BRACKET.count({
      where: whereClause,
    })

    return { total: totalRecords, byDestination: stats }
  },

  /**
   * Get Active Destination Config (for AUTO mode)
   */
  getDestinationConfig: async () => {
    const config = await prisma.tB_R_MAN_BRACKET_INTERLOCK.findUnique({
      where: { FID: 1 },
    })

    return config?.DESTINATION ?? 'ASSY'
  },

  /**
   * Set Password for specific FID
   */
  setDestinationConfig: async (fid: number, password: string) => {
    const existing = await prisma.tB_R_MAN_BRACKET_INTERLOCK.findUnique({
      where: { FID: Number(fid) },
    })

    if (existing) {
      // Update existing
      await prisma.tB_R_MAN_BRACKET_INTERLOCK.update({
        where: { FID: Number(fid) },
        data: {
          DESTINATION: password,
          FUPDATE: toJakartaDbDate(),
        },
      })
    } else {
      // Create new
      await prisma.tB_R_MAN_BRACKET_INTERLOCK.create({
        data: {
          FID: Number(fid),
          DESTINATION: password,
          FUPDATE: toJakartaDbDate(),
        },
      })
    }

    return { fid, password }
  },

  /**
   * Validate and toggle interlock mode (password-protected)
   */
  setInterlockMode: async (
    interlockOn: boolean,
    password: string,
    fid?: number,
  ) => {
    // Validation password is fixed to FID 2 (CKD) from DESTINATION column.
    const targetFid = 2

    // Lookup password from DESTINATION column by FID
    const config = await prisma.tB_R_MAN_BRACKET_INTERLOCK.findUnique({
      where: { FID: targetFid },
    })

    if (!config) {
      throw new Error(`Configuration not found for FID ${targetFid}`)
    }

    const storedPassword = config.DESTINATION?.trim() || ''
    const submitPassword = password.trim()

    if (storedPassword !== submitPassword) {
      throw new Error('Invalid password')
    }

    // Write interlock transmit and return success
    await manBracketService.writeInterlockTransmit(interlockOn ? 1 : 0)

    return { success: true, interlockOn }
  },
}
