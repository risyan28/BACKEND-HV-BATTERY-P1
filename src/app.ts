import express from 'express'
import cors from 'cors'
import PrintHistoryRoutes from '@/routes/printHistory.routes'
import sequenceRoutes from '@/routes/sequence.routes'
import healthRoutes from '@/routes/health.routes'
import traceabilityRoutes from '@/routes/traceability.routes'
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
app.use('/api/sequences', apiLimiter, sequenceRoutes)
app.use('/api/health', healthRoutes) // No rate limit for health checks
app.use('/api/print-history', apiLimiter, PrintHistoryRoutes)
app.use('/api/traceability', apiLimiter, traceabilityRoutes)

// ✅ Centralized error handler (Sentry v10 automatically handles errors before this)
app.use(errorHandler)

// ✅ Named export
export { app }
