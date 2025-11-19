import { Router } from 'express'
import { sequenceController } from '@/controllers/sequence.controller'

const router = Router()

router.get('/', sequenceController.getSequences)
router.post('/', sequenceController.createSequence)
router.put('/:id', sequenceController.updateSequence)

router.patch('/:id/move-up', sequenceController.moveSequenceUp)
router.patch('/:id/move-down', sequenceController.moveSequenceDown)
router.patch('/:id/park', sequenceController.parkSequence)
router.patch('/:id/insert', sequenceController.insertSequence)
router.delete('/:id/parked', sequenceController.removeFromParked)

export default router
