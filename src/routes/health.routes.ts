import { Router, Request, Response } from 'express'
import { asyncHandler } from '@/middleware/errorHandler'
import prisma from '@/prisma'
import { getConnection } from '@/utils/db'

const router = Router()

/**
 * @swagger
 * /api/health:
 *   get:
 *     summary: Basic health check
 *     description: Returns server status, timestamp, and uptime
 *     tags: [Health]
 *     responses:
 *       200:
 *         description: Server is healthy
 *         content:
 *           application/json:
 *             schema:
 *               type: object
 *               properties:
 *                 status:
 *                   type: string
 *                   example: ok
 *                 timestamp:
 *                   type: string
 *                   format: date-time
 *                 uptime:
 *                   type: number
 *                   description: Server uptime in seconds
 */
router.get('/', (req: Request, res: Response) => {
  res.json({
    status: 'ok',
    timestamp: new Date().toISOString(),
    uptime: process.uptime(),
  })
})

/**
 * @swagger
 * /api/health/detailed:
 *   get:
 *     summary: Detailed health check
 *     description: Returns comprehensive health status including database connections and memory usage
 *     tags: [Health]
 *     responses:
 *       200:
 *         description: Detailed health information
 *         content:
 *           application/json:
 *             schema:
 *               type: object
 *               properties:
 *                 status:
 *                   type: string
 *                   example: healthy
 *                 timestamp:
 *                   type: string
 *                   format: date-time
 *                 uptime:
 *                   type: number
 *                 database:
 *                   type: object
 *                   properties:
 *                     prisma:
 *                       type: object
 *                       properties:
 *                         status:
 *                           type: string
 *                         responseTime:
 *                           type: number
 *                     mssql:
 *                       type: object
 *                       properties:
 *                         status:
 *                           type: string
 *                         responseTime:
 *                           type: number
 *                 memory:
 *                   type: object
 *       500:
 *         $ref: '#/components/responses/InternalServerError'
 */
router.get(
  '/detailed',
  asyncHandler(async (req: Request, res: Response) => {
    const startTime = Date.now()

    // Check Prisma connection
    let prismaStatus = 'unknown'
    let prismaResponseTime = 0
    try {
      const prismaStart = Date.now()
      await prisma.$queryRaw`SELECT 1`
      prismaResponseTime = Date.now() - prismaStart
      prismaStatus = 'healthy'
    } catch (err) {
      prismaStatus = 'unhealthy'
    }

    // Check MSSQL connection pool
    let mssqlStatus = 'unknown'
    let mssqlResponseTime = 0
    try {
      const mssqlStart = Date.now()
      const pool = await getConnection()
      await pool.request().query('SELECT 1')
      mssqlResponseTime = Date.now() - mssqlStart
      mssqlStatus = 'healthy'
    } catch (err) {
      mssqlStatus = 'unhealthy'
    }

    const totalTime = Date.now() - startTime
    const memoryUsage = process.memoryUsage()

    res.json({
      status:
        prismaStatus === 'healthy' && mssqlStatus === 'healthy'
          ? 'healthy'
          : 'degraded',
      timestamp: new Date().toISOString(),
      uptime: Math.floor(process.uptime()),
      checks: {
        prisma: {
          status: prismaStatus,
          responseTime: `${prismaResponseTime}ms`,
        },
        mssql: {
          status: mssqlStatus,
          responseTime: `${mssqlResponseTime}ms`,
        },
      },
      system: {
        nodeVersion: process.version,
        platform: process.platform,
        memory: {
          rss: `${Math.round(memoryUsage.rss / 1024 / 1024)}MB`,
          heapUsed: `${Math.round(memoryUsage.heapUsed / 1024 / 1024)}MB`,
          heapTotal: `${Math.round(memoryUsage.heapTotal / 1024 / 1024)}MB`,
        },
      },
      responseTime: `${totalTime}ms`,
    })
  }),
)

export default router
