import express from 'express'
import cors from 'cors'
import PrintHistoryRoutes from '@/routes/printHistory.routes'
import sequenceRoutes from '@/routes/sequence.routes'
import healthRoutes from '@/routes/health.routes'
import traceabilityRoutes from '@/routes/traceability.routes'

const app = express()
app.use(cors())
app.use(express.json())

app.use('/api/sequences', sequenceRoutes)
app.use('/api/health', healthRoutes)
app.use('/api/print-history', PrintHistoryRoutes)
app.use('/api/traceability', traceabilityRoutes)

// ✅ Named export
export { app }