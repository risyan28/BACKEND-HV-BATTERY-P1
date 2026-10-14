import { Router } from 'express'
import { getRfidMap, updateRfidMapValue, triggerRfidCommand } from '@/controllers/rfid.controller'

const router = Router()

router.get('/map', getRfidMap)
router.put('/map', updateRfidMapValue)
router.post('/command', triggerRfidCommand)

export { router as rfidRouter }
