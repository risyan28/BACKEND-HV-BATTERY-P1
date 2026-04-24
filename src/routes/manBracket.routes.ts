// src/routes/manBracket.routes.ts

import { Router } from 'express'
import { manBracketController } from '@/controllers/manBracket.controller'

const router = Router()

/**
 * @swagger
 * /api/man-bracket/start-process:
 *   post:
 *     summary: Start Man Bracket Process
 *     description: Insert a new man bracket process row when a label is scanned.
 *     tags: [Man Bracket]
 *     requestBody:
 *       required: true
 *       content:
 *         application/json:
 *           schema:
 *             type: object
 *             required:
 *               - barcode
 *               - destination
 *             properties:
 *               barcode:
 *                 type: string
 *                 example: "SM-LI-688D-0001234"
 *               destination:
 *                 type: string
 *                 enum: [ASSY, CKD]
 *               startTime:
 *                 type: string
 *                 format: date-time
 *     responses:
 *       201:
 *         description: Process started successfully
 */
router.post('/start-process', manBracketController.startProcess)

/**
 * @swagger
 * /api/man-bracket/reset-process:
 *   post:
 *     summary: Reset Man Bracket Process
 *     description: Delete the active in-progress man bracket process row.
 *     tags: [Man Bracket]
 *     requestBody:
 *       required: true
 *       content:
 *         application/json:
 *           schema:
 *             type: object
 *             required:
 *               - recordId
 *             properties:
 *               recordId:
 *                 type: integer
 *                 example: 1
 *     responses:
 *       200:
 *         description: Process reset successfully
 */
router.post('/reset-process', manBracketController.resetProcess)

/**
 * @swagger
 * /api/man-bracket/complete-process:
 *   post:
 *     summary: Complete Man Bracket Process
 *     description: Update an existing man bracket process row when processing is completed
 *     tags: [Man Bracket]
 *     requestBody:
 *       required: true
 *       content:
 *         application/json:
 *           schema:
 *             type: object
 *             required:
 *               - recordId
 *             properties:
 *               recordId:
 *                 type: integer
 *                 example: 1
 *               completedTime:
 *                 type: string
 *                 format: date-time
 *                 example: "2026-04-10T10:35:00Z"
 *     responses:
 *       200:
 *         description: Process completed successfully
 *         content:
 *           application/json:
 *             schema:
 *               type: object
 *               properties:
 *                 success:
 *                   type: boolean
 *                 message:
 *                   type: string
 *                 data:
 *                   type: object
 *       400:
 *         description: Missing required fields
 *       500:
 *         description: Server error
 */
router.post('/complete-process', manBracketController.completeProcess)

/**
 * @swagger
 * /api/man-bracket:
 *   get:
 *     summary: Get Man Bracket Records
 *     description: Retrieve man bracket process records with optional filters
 *     tags: [Man Bracket]
 *     parameters:
 *       - in: query
 *         name: limit
 *         schema:
 *           type: integer
 *           default: 50
 *         description: Number of records to return
 *       - in: query
 *         name: offset
 *         schema:
 *           type: integer
 *           default: 0
 *         description: Number of records to skip
 *       - in: query
 *         name: destination
 *         schema:
 *           type: string
 *         description: Filter by destination (ASSY, CKD)
 *       - in: query
 *         name: fvalue
 *         schema:
 *           type: integer
 *         description: Filter by process state (0 = in progress, 1 = completed)
 *     responses:
 *       200:
 *         description: Successfully retrieved records
 *         content:
 *           application/json:
 *             schema:
 *               type: object
 *               properties:
 *                 success:
 *                   type: boolean
 *                 data:
 *                   type: array
 *                 pagination:
 *                   type: object
 *       500:
 *         description: Server error
 */
router.get('/', manBracketController.getRecords)

/**
 * @swagger
 * /api/man-bracket/stats:
 *   get:
 *     summary: Get Man Bracket Statistics
 *     description: Get statistics of man bracket records grouped by destination and process state
 *     tags: [Man Bracket]
 *     parameters:
 *       - in: query
 *         name: startDate
 *         schema:
 *           type: string
 *           format: date-time
 *         description: Start date for filtering
 *       - in: query
 *         name: endDate
 *         schema:
 *           type: string
 *           format: date-time
 *         description: End date for filtering
 *     responses:
 *       200:
 *         description: Successfully retrieved statistics
 *       500:
 *         description: Server error
 */
router.get('/stats', manBracketController.getStats)

/**
 * @swagger
 * /api/man-bracket/{id}:
 *   get:
 *     summary: Get Single Man Bracket Record
 *     description: Retrieve a specific man bracket record by ID
 *     tags: [Man Bracket]
 *     parameters:
 *       - in: path
 *         name: id
 *         required: true
 *         schema:
 *           type: integer
 *         description: Record ID
 *     responses:
 *       200:
 *         description: Successfully retrieved record
 *       404:
 *         description: Record not found
 *       500:
 *         description: Server error
 */
/**
 * @swagger
 * /api/man-bracket/destination-config:
 *   get:
 *     summary: Get Active Destination Config (Auto mode)
 *     tags: [Man Bracket]
 *     responses:
 *       200:
 *         description: Active destination setting
 *         content:
 *           application/json:
 *             schema:
 *               type: object
 *               properties:
 *                 success:
 *                   type: boolean
 *                 destination:
 *                   type: string
 *                   enum: [ASSY, CKD]
 *   put:
 *     summary: Set Active Destination Config
 *     tags: [Man Bracket]
 *     requestBody:
 *       required: true
 *       content:
 *         application/json:
 *           schema:
 *             type: object
 *             required:
 *               - destination
 *             properties:
 *               destination:
 *                 type: string
 *                 enum: [ASSY, CKD]
 *     responses:
 *       200:
 *         description: Destination config updated
 *       400:
 *         description: Invalid destination value
 */
router.get('/destination-config', manBracketController.getDestinationConfig)
router.put('/destination-config', manBracketController.setDestinationConfig)

/**
 * @swagger
 * /api/man-bracket/interlock-mode:
 *   post:
 *     summary: Set Interlock Mode
 *     tags: [Man Bracket]
 *     requestBody:
 *       required: true
 *       content:
 *         application/json:
 *           schema:
 *             type: object
 *             required:
 *               - interlockOn
 *             properties:
 *               interlockOn:
 *                 type: boolean
 *                 example: true
 *     responses:
 *       200:
 *         description: Interlock transmit inserted successfully
 *       400:
 *         description: Invalid payload
 */
router.post('/interlock-mode', manBracketController.setInterlockMode)

router.get('/:id', manBracketController.getRecord)

export { router as manBracketRouter }
