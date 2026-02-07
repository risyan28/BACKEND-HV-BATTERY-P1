import { Router } from 'express'
import { sequenceController } from '@/controllers/sequence.controller'

const router = Router()

/**
 * @swagger
 * /api/sequences:
 *   get:
 *     summary: Get all battery sequences
 *     description: Retrieve sequences categorized by status (queue, complete, parked)
 *     tags: [Sequences]
 *     responses:
 *       200:
 *         description: Successfully retrieved sequences
 *         content:
 *           application/json:
 *             schema:
 *               type: object
 *               properties:
 *                 queue:
 *                   type: array
 *                   items:
 *                     $ref: '#/components/schemas/Sequence'
 *                 complete:
 *                   type: array
 *                   items:
 *                     $ref: '#/components/schemas/Sequence'
 *                 parked:
 *                   type: array
 *                   items:
 *                     $ref: '#/components/schemas/Sequence'
 *       500:
 *         $ref: '#/components/responses/InternalServerError'
 */
router.get('/', sequenceController.getSequences)

/**
 * @swagger
 * /api/sequences:
 *   post:
 *     summary: Create new battery sequence
 *     description: Add a new sequence to the queue
 *     tags: [Sequences]
 *     requestBody:
 *       required: true
 *       content:
 *         application/json:
 *           schema:
 *             type: object
 *             required:
 *               - NO_RANGKA
 *               - TYPE_BATTERY
 *             properties:
 *               NO_RANGKA:
 *                 type: string
 *               TYPE_BATTERY:
 *                 type: string
 *               PROD_DATE:
 *                 type: string
 *                 format: date
 *     responses:
 *       201:
 *         description: Sequence created successfully
 *       400:
 *         $ref: '#/components/responses/ValidationError'
 *       500:
 *         $ref: '#/components/responses/InternalServerError'
 */
router.post('/', sequenceController.createSequence)

/**
 * @swagger
 * /api/sequences/{id}:
 *   put:
 *     summary: Update battery sequence
 *     description: Update sequence details by ID
 *     tags: [Sequences]
 *     parameters:
 *       - in: path
 *         name: id
 *         required: true
 *         schema:
 *           type: integer
 *     requestBody:
 *       required: true
 *       content:
 *         application/json:
 *           schema:
 *             type: object
 *     responses:
 *       200:
 *         description: Sequence updated successfully
 *       404:
 *         description: Sequence not found
 *       500:
 *         $ref: '#/components/responses/InternalServerError'
 */
router.put('/:id', sequenceController.updateSequence)

/**
 * @swagger
 * /api/sequences/{id}/move-up:
 *   patch:
 *     summary: Move sequence up in queue
 *     description: Increase sequence priority by moving it up
 *     tags: [Sequences]
 *     parameters:
 *       - in: path
 *         name: id
 *         required: true
 *         schema:
 *           type: integer
 *     responses:
 *       200:
 *         description: Sequence moved up successfully
 *       404:
 *         description: Sequence not found
 *       500:
 *         $ref: '#/components/responses/InternalServerError'
 */
router.patch('/:id/move-up', sequenceController.moveSequenceUp)

/**
 * @swagger
 * /api/sequences/{id}/move-down:
 *   patch:
 *     summary: Move sequence down in queue
 *     description: Decrease sequence priority by moving it down
 *     tags: [Sequences]
 *     parameters:
 *       - in: path
 *         name: id
 *         required: true
 *         schema:
 *           type: integer
 *     responses:
 *       200:
 *         description: Sequence moved down successfully
 *       404:
 *         description: Sequence not found
 *       500:
 *         $ref: '#/components/responses/InternalServerError'
 */
router.patch('/:id/move-down', sequenceController.moveSequenceDown)

/**
 * @swagger
 * /api/sequences/{id}/park:
 *   patch:
 *     summary: Park sequence
 *     description: Move sequence to parked status
 *     tags: [Sequences]
 *     parameters:
 *       - in: path
 *         name: id
 *         required: true
 *         schema:
 *           type: integer
 *     responses:
 *       200:
 *         description: Sequence parked successfully
 *       404:
 *         description: Sequence not found
 *       500:
 *         $ref: '#/components/responses/InternalServerError'
 */
router.patch('/:id/park', sequenceController.parkSequence)

/**
 * @swagger
 * /api/sequences/{id}/insert:
 *   patch:
 *     summary: Insert sequence back to queue
 *     description: Move parked sequence back to active queue
 *     tags: [Sequences]
 *     parameters:
 *       - in: path
 *         name: id
 *         required: true
 *         schema:
 *           type: integer
 *     requestBody:
 *       required: true
 *       content:
 *         application/json:
 *           schema:
 *             type: object
 *             properties:
 *               position:
 *                 type: integer
 *                 description: Target position in queue
 *     responses:
 *       200:
 *         description: Sequence inserted successfully
 *       404:
 *         description: Sequence not found
 *       500:
 *         $ref: '#/components/responses/InternalServerError'
 */
router.patch('/:id/insert', sequenceController.insertSequence)

/**
 * @swagger
 * /api/sequences/{id}/parked:
 *   delete:
 *     summary: Remove from parked
 *     description: Permanently remove sequence from parked list
 *     tags: [Sequences]
 *     parameters:
 *       - in: path
 *         name: id
 *         required: true
 *         schema:
 *           type: integer
 *     responses:
 *       200:
 *         description: Sequence removed successfully
 *       404:
 *         description: Sequence not found
 *       500:
 *         $ref: '#/components/responses/InternalServerError'
 */
router.delete('/:id/parked', sequenceController.removeFromParked)

export default router
