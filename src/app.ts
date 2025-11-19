import express from 'express'
import cors from 'cors'
import sequenceRoutes from '@/routes/sequence.routes'
import healthRoutes from '@/routes/health.routes'

const app = express()
app.use(cors())
app.use(express.json())

app.use('/api/sequences', sequenceRoutes)
app.use('/api/health', healthRoutes)
export default app
