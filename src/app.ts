import express from 'express'
import cors from 'cors'
import { printHistoryRouter } from '@/routes/printHistory.routes'
import { sequenceRouter } from '@/routes/sequence.routes'
import { healthRouter } from '@/routes/health.routes'
import { traceabilityRouter } from '@/routes/traceability.routes'
import { logsRouter } from '@/routes/logs.routes'
import { productionPlanRouter } from '@/routes/productionPlan.routes'
import { manBracketRouter } from '@/routes/manBracket.routes'
import { errorHandler } from '@/middleware/errorHandler'
import { requestLogger } from '@/middleware/requestLogger'
import { apiLimiter } from '@/middleware/rateLimiter'
import { setupSwagger } from '@/config/swagger'
import { CORS_DEFAULTS } from '@/config/constants'

const app = express()

// ✅ CORS Configuration with whitelist
const allowedOrigins = process.env.ALLOWED_ORIGINS
  ? process.env.ALLOWED_ORIGINS.split(',').map((origin) => origin.trim())
  : ['*'] // Allow all in development by default

app.use(
  cors({
    origin: allowedOrigins.includes('*') ? '*' : allowedOrigins,
    credentials: true,
    maxAge: CORS_DEFAULTS.MAX_AGE,
  }),
)

app.use(express.json())

// ✅ Request logging with Pino
app.use(requestLogger)

// ✅ API Documentation (Swagger)
setupSwagger(app)

// Routes with rate limiting
app.use('/api/sequences', apiLimiter, sequenceRouter)
app.use('/api/health', healthRouter) // No rate limit for health checks
app.use('/api/print-history', apiLimiter, printHistoryRouter)
app.use('/api/traceability', apiLimiter, traceabilityRouter)
app.use('/api/production-plan', apiLimiter, productionPlanRouter)
app.use('/api/man-bracket', apiLimiter, manBracketRouter)
app.use('/api/logs', logsRouter) // No rate limit for FE logs

// ✅ Centralized error handler (Sentry v10 automatically handles errors before this)
app.use(errorHandler)

// ✅ Named export
export { app }
