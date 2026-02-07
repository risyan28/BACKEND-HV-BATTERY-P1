import prisma from '@/prisma'
import { formatDate, formatDateTime } from '@/utils/date'
import { log } from 'console'
import { SEQUENCE_STATUS, QUERY_LIMITS } from '@/config/constants'
import { cache } from '@/utils/cache'
import { loggers } from '@/utils/logger'

/**
 * Cache configuration for sequences
 */
const CACHE_CONFIG = {
  KEY: 'sequences:all',
  TTL: 30, // 30 seconds - short TTL because of frequent polling
}

/**
 * Helper: Invalidate sequences cache
 */
const invalidateCache = async () => {
  await cache.del(CACHE_CONFIG.KEY)
  loggers.cache.debug({ key: CACHE_CONFIG.KEY }, 'Cache invalidated')
}

/**
 * FSTATUS Mapping (from constants):
 * 0 = QUEUE (belum diprint)
 * 1 = PRINTED (sudah diprint, standby di proses)
 * 2 = COMPLETE (workpiece keluar dari pos)
 * 3 = PARKED (manual parked)
 */
export const sequenceService = {
  /**
   * ✅ PHASE 3: Redis cache implemented
   * Cache key: sequences:all
   * TTL: 30 seconds
   * Invalidated on: all mutations
   */
  async getSequences() {
    return cache.getOrSet(
      CACHE_CONFIG.KEY,
      async () => {
        loggers.db.debug('Fetching sequences from database (cache miss)')

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
      CACHE_CONFIG.TTL,
    )
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

    // ✅ Using $executeRaw instead of $executeRawUnsafe to prevent SQL injection
    const newTargetValue = (target.FTARGET ?? 0) + 1
    await prisma.$executeRaw`
      UPDATE TB_R_TARGET_PROD
      SET 
        FTARGET = ${newTargetValue},
        FSEQ_K0 = NULL,
        FBODY_NO_K0 = NULL,
        FID_RECEIVER = NULL,
        FALC_DATA = NULL,
        FDATETIME_MODIFIED = GETDATE()
      WHERE FID = ${target.FID}
    `

    // ✅ Invalidate cache after mutation
    await invalidateCache()

    return this.getSequences()
  },

  async updateSequence(fid: number, updates: any) {
    const result = await prisma.tB_R_SEQUENCE_BATTERY.update({
      where: { FID: fid },
      data: updates,
    })

    // ✅ Invalidate cache after mutation
    await invalidateCache()

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

    // ✅ Invalidate cache after mutation
    await invalidateCache()

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
      where: {
        FSTATUS: SEQUENCE_STATUS.QUEUE,
        FID_ADJUST: { gt: sequence.FID_ADJUST },
      },
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

    // ✅ Invalidate cache after mutation
    await invalidateCache()

    return this.getSequences()
  },

  async parkSequence(fid: number) {
    await prisma.tB_R_SEQUENCE_BATTERY.update({
      where: { FID: fid },
      data: { FSTATUS: SEQUENCE_STATUS.PARKED },
    })

    // ✅ Invalidate cache after mutation
    await invalidateCache()

    return this.getSequences()
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

    // ✅ Invalidate cache after mutation
    await invalidateCache()

    // 🔹 Return queue terbaru
    return this.getSequences()
  },

  async removeFromParked(fid: number) {
    await prisma.tB_R_SEQUENCE_BATTERY.delete({
      where: { FID: fid },
    })

    // ✅ Invalidate cache after mutation
    await invalidateCache()

    return this.getSequences()
  },
}
