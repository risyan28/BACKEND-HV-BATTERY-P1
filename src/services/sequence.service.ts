import prisma from '@/prisma'
import { formatDate, formatDateTime } from '@/utils/date'
import { log } from 'console'
import { SEQUENCE_STATUS, QUERY_LIMITS } from '@/config/constants'
import { loggers } from '@/utils/logger'
import type { SequenceStrategy } from '@/utils/strategyStore'

/**
 * FSTATUS Mapping (from constants):
 * 0 = QUEUE (belum diprint)
 * 1 = PRINTED (sudah diprint, standby di proses)
 * 2 = COMPLETE (workpiece keluar dari pos)
 * 3 = PARKED (manual parked)
 */
export const sequenceService = {
  /**
   * Always fetch latest sequence snapshot from DB.
   * No Redis cache here to keep operator UI truly realtime.
   */
  async getSequences(options?: { fresh?: boolean }) {
    if (options?.fresh) {
      loggers.db.debug('Fresh sequence fetch requested')
    }

    loggers.db.debug('Fetching sequences from database')

    const [current, queue, completed, parked] = await prisma.$transaction([
      // 1. Current (top 1)
      prisma.tB_R_SEQUENCE_BATTERY.findFirst({
        where: {
          OR: [
            { FSTATUS: SEQUENCE_STATUS.QUEUE },
            {
              FSTATUS: SEQUENCE_STATUS.PRINTED,
              FTIME_PRINTED: { not: null },
            },
          ],
        },
        orderBy: { FID_ADJUST: 'asc' },
      }),

      // 2. Queue (limit from constants, exclude current nanti)
      prisma.tB_R_SEQUENCE_BATTERY.findMany({
        where: { FSTATUS: SEQUENCE_STATUS.QUEUE },
        orderBy: { FID_ADJUST: 'asc' },
        take: QUERY_LIMITS.MAX_QUEUE_SIZE,
      }),

      // 3. Completed (limit from constants)
      prisma.tB_R_SEQUENCE_BATTERY.findMany({
        where: { FSTATUS: SEQUENCE_STATUS.COMPLETE },
        orderBy: { FID_ADJUST: 'asc' },
        take: QUERY_LIMITS.MAX_COMPLETED_SIZE,
      }),

      // 4. Parked (all)
      prisma.tB_R_SEQUENCE_BATTERY.findMany({
        where: { FSTATUS: SEQUENCE_STATUS.PARKED },
        orderBy: { FID_ADJUST: 'asc' },
      }),
    ])

    const mappingRows = await prisma.$queryRaw<
      Array<{
        FTYPE_BATTERY: string | null
        FMODEL_BATTERY: string | null
        ORDER_TYPE: string | null
      }>
    >`
      SELECT
        FTYPE_BATTERY,
        FMODEL_BATTERY,
        ORDER_TYPE
      FROM TB_M_BATTERY_MAPPING
      WHERE ORDER_TYPE IS NOT NULL
        AND LTRIM(RTRIM(ORDER_TYPE)) <> ''
    `

    const orderTypeMap = new Map<string, string>()
    for (const row of mappingRows) {
      if (!row.FTYPE_BATTERY || !row.FMODEL_BATTERY || !row.ORDER_TYPE) continue
      orderTypeMap.set(
        `${row.FTYPE_BATTERY}|${row.FMODEL_BATTERY}`,
        row.ORDER_TYPE,
      )
    }

    const mapData = (s: NonNullable<typeof current>) => ({
      ...s,
      ORDER_TYPE:
        (s as any).ORDER_TYPE && String((s as any).ORDER_TYPE).trim() !== ''
          ? (s as any).ORDER_TYPE
          : (orderTypeMap.get(`${s.FTYPE_BATTERY}|${s.FMODEL_BATTERY}`) ??
            null),
      FSEQ_DATE: formatDate(s.FSEQ_DATE),

      FTIME_RECEIVED: formatDateTime(s.FTIME_RECEIVED),
      FTIME_PRINTED: formatDateTime(s.FTIME_PRINTED),
      FTIME_COMPLETED: formatDateTime(s.FTIME_COMPLETED),
      FALC_DATA:
        s.FALC_DATA && s.FALC_DATA.trim() !== '' ? 'ALC' : 'INJECT MANUAL',
    })

    // Filter queue: exclude current jika ada
    const filteredQueue = current
      ? queue.filter((s: { FID: number }) => s.FID !== current.FID)
      : queue

    // Log TIME RECEIVED ALC and TIME PRINT LABEL for current sequence
    if (current) {
      loggers.db.debug(
        {
          timeReceivedALC: formatDateTime(current.FTIME_RECEIVED),
          fid: current.FID,
          seqNo: current.FSEQ_NO,
        },
        'TIME RECEIVED ALC',
      )
      loggers.db.debug(
        {
          timePrintLabel: formatDateTime(current.FTIME_PRINTED),
          fid: current.FID,
          seqNo: current.FSEQ_NO,
        },
        'TIME PRINT LABEL',
      )
    }

    return {
      current: current ? mapData(current) : null,
      queue: filteredQueue.map(mapData),
      completed: completed.map(mapData),
      parked: parked.map(mapData),
    }
  },

  async applyStrategyToDb(strategy: SequenceStrategy) {
    await prisma.$executeRaw`
      EXEC dbo.SP_APPLY_SEQUENCE_STRATEGY
        @Mode = ${strategy.mode},
        @PriorityType = ${strategy.priorityType},
        @RatioPrimary = ${strategy.ratioPrimary},
        @RatioSecondary = ${strategy.ratioSecondary},
        @RatioTertiary = ${strategy.ratioTertiary},
        @RatioAssy = ${strategy.ratioValues.ASSY},
        @RatioCkd = ${strategy.ratioValues.CKD},
        @RatioServicePart = ${strategy.ratioValues['SERVICE PART']}
    `
  },

  async createSequence(data: {
    FTYPE_BATTERY: string
    FMODEL_BATTERY: string
    ORDER_TYPE: 'ASSY' | 'CKD' | 'SERVICE PART'
    QTY: number
  }) {
    const qty = Number.isFinite(data.QTY) ? Math.max(1, data.QTY) : 1
    const orderTypeLabel = `INJECT MAN - ${data.ORDER_TYPE}`

    // Requirement: ONLY update FTARGET; sequence generation is handled by DB trigger
    // (TB_R_TARGET_PROD_AFTER_UPDATE) based on FTARGET delta.
    const updated = await prisma.$executeRaw`
      UPDATE TB_R_TARGET_PROD
      SET
        FTARGET = ISNULL(FTARGET, 0) + ${qty},
        ORDER_TYPE = ${orderTypeLabel},
        FPROD_DATE = CAST(GETDATE() AS DATE),
        FDATETIME_MODIFIED = GETDATE()
      WHERE FTYPE_BATTERY = ${data.FTYPE_BATTERY}
        AND FMODEL_BATTERY = ${data.FMODEL_BATTERY}
    `

    const updatedCount = Number(updated)
    if (Number.isFinite(updatedCount) && updatedCount === 0) {
      throw new Error('Target production not found')
    }

    return this.getSequences({ fresh: true })
  },

  async updateSequence(fid: number, updates: any) {
    const result = await prisma.tB_R_SEQUENCE_BATTERY.update({
      where: { FID: fid },
      data: updates,
    })

    return result
  },

  // --- Utility Function ---

  async moveSequenceUp(fid: number) {
    const sequence = await prisma.tB_R_SEQUENCE_BATTERY.findUnique({
      where: { FID: fid },
    })
    if (!sequence || sequence.FID_ADJUST == null)
      throw new Error('Sequence not found or not adjustable')

    const prev = await prisma.tB_R_SEQUENCE_BATTERY.findFirst({
      where: {
        FSTATUS: SEQUENCE_STATUS.QUEUE,
        FID_ADJUST: { lt: sequence.FID_ADJUST },
      },
      orderBy: { FID_ADJUST: 'desc' },
    })
    if (!prev) return this.getSequences({ fresh: true }) // udah paling atas

    await prisma.$transaction([
      prisma.tB_R_SEQUENCE_BATTERY.update({
        where: { FID: sequence.FID },
        data: { FID_ADJUST: prev.FID_ADJUST },
      }),
      prisma.tB_R_SEQUENCE_BATTERY.update({
        where: { FID: prev.FID },
        data: { FID_ADJUST: sequence.FID_ADJUST },
      }),
    ])

    return this.getSequences({ fresh: true })
  },

  async moveSequenceDown(fid: number) {
    console.log('👉 API /sequences/move-down', fid)
    const sequence = await prisma.tB_R_SEQUENCE_BATTERY.findUnique({
      where: { FID: fid },
    })
    if (!sequence || sequence.FID_ADJUST == null)
      throw new Error('Sequence not found or not adjustable')

    const next = await prisma.tB_R_SEQUENCE_BATTERY.findFirst({
      where: {
        FSTATUS: SEQUENCE_STATUS.QUEUE,
        FID_ADJUST: { gt: sequence.FID_ADJUST },
      },
      orderBy: { FID_ADJUST: 'asc' },
    })
    if (!next) return this.getSequences({ fresh: true }) // udah paling bawah

    await prisma.$transaction([
      prisma.tB_R_SEQUENCE_BATTERY.update({
        where: { FID: sequence.FID },
        data: { FID_ADJUST: next.FID_ADJUST },
      }),
      prisma.tB_R_SEQUENCE_BATTERY.update({
        where: { FID: next.FID },
        data: { FID_ADJUST: sequence.FID_ADJUST },
      }),
    ])

    return this.getSequences({ fresh: true })
  },

  async parkSequence(fid: number) {
    await prisma.tB_R_SEQUENCE_BATTERY.update({
      where: { FID: fid },
      data: { FSTATUS: SEQUENCE_STATUS.PARKED },
    })

    return this.getSequences({ fresh: true })
  },

  async insertSequence(
    fid: number,
    opts: { anchorId?: number; position?: 'beginning' | 'end' },
  ) {
    const { anchorId, position } = opts

    // 🔹 Ambil sequence yang mau diinsert
    const seq = await prisma.tB_R_SEQUENCE_BATTERY.findUnique({
      where: { FID: fid },
    })
    if (!seq) throw new Error('Sequence not found')

    // 🔹 Ambil queue aktif (status QUEUE)
    const queue = await prisma.tB_R_SEQUENCE_BATTERY.findMany({
      where: { FSTATUS: SEQUENCE_STATUS.QUEUE },
      orderBy: { FID_ADJUST: 'asc' },
    })

    let insertAdjust: number

    if (!queue.length) {
      // ✅ Queue kosong → mulai dari 1
      insertAdjust = 1
    } else if (position === 'beginning') {
      // ✅ Insert di depan
      const minAdjust = queue[0].FID_ADJUST ?? 0

      // Geser semua dulu ke +1
      await prisma.tB_R_SEQUENCE_BATTERY.updateMany({
        where: {
          FSTATUS: SEQUENCE_STATUS.QUEUE,
          FID_ADJUST: { gte: minAdjust },
        },
        data: { FID_ADJUST: { increment: 1 } },
      })

      insertAdjust = minAdjust
    } else if (position === 'end') {
      // ✅ Insert di akhir
      const lastItem = queue[queue.length - 1]
      insertAdjust = (lastItem.FID_ADJUST ?? 0) + 1
    } else if (anchorId) {
      // ✅ Insert setelah anchorId
      const anchorSeq = await prisma.tB_R_SEQUENCE_BATTERY.findUnique({
        where: { FID: anchorId },
      })
      if (!anchorSeq) throw new Error('Anchor sequence not found')

      const anchorAdjust = anchorSeq.FID_ADJUST ?? 0

      // Geser semua setelah anchor
      await prisma.tB_R_SEQUENCE_BATTERY.updateMany({
        where: {
          FSTATUS: SEQUENCE_STATUS.QUEUE,
          FID_ADJUST: { gt: anchorAdjust },
        },
        data: { FID_ADJUST: { increment: 1 } },
      })

      insertAdjust = anchorAdjust + 1
    } else {
      throw new Error('Must provide either anchorId or position')
    }

    // 🔹 Update sequence target jadi aktif & set posisi baru
    await prisma.tB_R_SEQUENCE_BATTERY.update({
      where: { FID: fid },
      data: {
        FSTATUS: SEQUENCE_STATUS.QUEUE,
        FID_ADJUST: insertAdjust,
      },
    })

    // 🔹 Return queue terbaru
    return this.getSequences({ fresh: true })
  },

  async removeFromParked(fid: number) {
    await prisma.tB_R_SEQUENCE_BATTERY.delete({
      where: { FID: fid },
    })

    return this.getSequences({ fresh: true })
  },
}
