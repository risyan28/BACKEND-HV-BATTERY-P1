import prisma from '@/prisma'
import { formatDate, formatDateTime } from '@/utils/date'
import { log } from 'console'

/**
 * FSTATUS Mapping:
 * 0 = QUEUE (belum diprint)
 * 1 = PRINTED (sudah diprint, standby di proses)
 * 2 = COMPLETE (workpiece keluar dari pos)
 * 3 = PARKED (manual parked)
 */
export const sequenceService = {
  async getSequences() {
    const [current, queue, completed, parked] = await prisma.$transaction([
      // 1. Current (top 1)
      prisma.tB_R_SEQUENCE_BATTERY.findFirst({
        where: {
          OR: [{ FSTATUS: 0 }, { FSTATUS: 1, FTIME_PRINTED: { not: null } }],
        },
        orderBy: { FID_ADJUST: 'asc' },
      }),

      // 2. Queue (limit 500, exclude current nanti)
      prisma.tB_R_SEQUENCE_BATTERY.findMany({
        where: { FSTATUS: 0 },
        orderBy: { FID_ADJUST: 'asc' },
        take: 500,
      }),

      // 3. Completed (limit 100)
      prisma.tB_R_SEQUENCE_BATTERY.findMany({
        where: { FSTATUS: 2 },
        orderBy: { FID_ADJUST: 'asc' },
        take: 100,
      }),

      // 4. Parked (all)
      prisma.tB_R_SEQUENCE_BATTERY.findMany({
        where: { FSTATUS: 3 },
        orderBy: { FID_ADJUST: 'asc' },
      }),
    ])

    const mapData = (s: NonNullable<typeof current>) => ({
      ...s,
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
    return {
      current: current ? mapData(current) : null,
      queue: filteredQueue.map(mapData),
      completed: completed.map(mapData),
      parked: parked.map(mapData),
    }
  },

  async createSequence(data: {
    FTYPE_BATTERY: string
    FMODEL_BATTERY: string
  }) {
    const target = await prisma.tB_R_TARGET_PROD.findFirst({
      where: {
        FTYPE_BATTERY: data.FTYPE_BATTERY,
        FMODEL_BATTERY: data.FMODEL_BATTERY,
      },
      orderBy: { FID: 'desc' }, // ambil record terakhir
    })

    if (!target) throw new Error('Target production not found')

    await prisma.$executeRawUnsafe(`
      UPDATE TB_R_TARGET_PROD
      SET 
        FTARGET = ${(target.FTARGET ?? 0) + 1},
        FSEQ_K0 = NULL,
        FBODY_NO_K0 = NULL,
        FID_RECEIVER = NULL,
        FALC_DATA = NULL,
        FDATETIME_MODIFIED = GETDATE()
      WHERE FID = ${target.FID}
    `)

    return this.getSequences()
  },

  async updateSequence(fid: number, updates: any) {
    return prisma.tB_R_SEQUENCE_BATTERY.update({
      where: { FID: fid },
      data: updates,
    })
  },

  // --- Utility Function ---

  async moveSequenceUp(fid: number) {
    const sequence = await prisma.tB_R_SEQUENCE_BATTERY.findUnique({
      where: { FID: fid },
    })
    if (!sequence || sequence.FID_ADJUST == null)
      throw new Error('Sequence not found or not adjustable')

    const prev = await prisma.tB_R_SEQUENCE_BATTERY.findFirst({
      where: { FSTATUS: 0, FID_ADJUST: { lt: sequence.FID_ADJUST } },
      orderBy: { FID_ADJUST: 'desc' },
    })
    if (!prev) return this.getSequences() // udah paling atas

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

    return this.getSequences()
  },

  async moveSequenceDown(fid: number) {
    console.log('👉 API /sequences/move-down', fid)
    const sequence = await prisma.tB_R_SEQUENCE_BATTERY.findUnique({
      where: { FID: fid },
    })
    if (!sequence || sequence.FID_ADJUST == null)
      throw new Error('Sequence not found or not adjustable')

    const next = await prisma.tB_R_SEQUENCE_BATTERY.findFirst({
      where: { FSTATUS: 0, FID_ADJUST: { gt: sequence.FID_ADJUST } },
      orderBy: { FID_ADJUST: 'asc' },
    })
    if (!next) return this.getSequences() // udah paling bawah

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

    return this.getSequences()
  },

  async parkSequence(fid: number) {
    await prisma.tB_R_SEQUENCE_BATTERY.update({
      where: { FID: fid },
      data: { FSTATUS: 3 },
    })
    return this.getSequences()
  },

  async insertSequence(
    fid: number,
    opts: { anchorId?: number; position?: 'beginning' | 'end' }
  ) {
    const { anchorId, position } = opts

    // 🔹 Ambil sequence yang mau diinsert
    const seq = await prisma.tB_R_SEQUENCE_BATTERY.findUnique({
      where: { FID: fid },
    })
    if (!seq) throw new Error('Sequence not found')

    // 🔹 Ambil queue aktif (status 0)
    const queue = await prisma.tB_R_SEQUENCE_BATTERY.findMany({
      where: { FSTATUS: 0 },
      orderBy: { FID_ADJUST: 'asc' },
    })

    let insertAdjust: number

    if (!queue.length) {
      // ✅ Queue kosong → mulai dari 1
      insertAdjust = 1
    } else if (position === 'beginning') {
      // ✅ Insert di depan
      const minAdjust = queue[1].FID_ADJUST ?? 0

      // Geser semua dulu ke +1
      await prisma.tB_R_SEQUENCE_BATTERY.updateMany({
        where: { FSTATUS: 0, FID_ADJUST: { gte: minAdjust } },
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
        where: { FSTATUS: 0, FID_ADJUST: { gt: anchorAdjust } },
        data: { FID_ADJUST: { increment: 1 } },
      })

      insertAdjust = anchorAdjust + 1
    } else {
      throw new Error('Invalid insert position')
    }

    // 🔹 Update sequence target jadi aktif & set posisi baru
    await prisma.tB_R_SEQUENCE_BATTERY.update({
      where: { FID: fid },
      data: {
        FSTATUS: 0,
        FID_ADJUST: insertAdjust,
      },
    })

    // 🔹 Return queue terbaru
    return this.getSequences()
  },

  async removeFromParked(fid: number) {
    await prisma.tB_R_SEQUENCE_BATTERY.delete({
      where: { FID: fid },
    })
    return this.getSequences()
  },
}
