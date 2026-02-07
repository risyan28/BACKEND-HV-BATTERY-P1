// src/schemas/traceability.schema.ts
import { z } from 'zod'

/**
 * Validation schemas for traceability-related requests
 */

const dateRegex = /^\d{4}-\d{2}-\d{2}$/

export const dateRangeQuerySchema = z
  .object({
    from: z
      .string()
      .regex(dateRegex, 'from must be in YYYY-MM-DD format')
      .refine((date) => !isNaN(Date.parse(date)), 'from must be a valid date'),
    to: z
      .string()
      .regex(dateRegex, 'to must be in YYYY-MM-DD format')
      .refine((date) => !isNaN(Date.parse(date)), 'to must be a valid date'),
    page: z
      .string()
      .optional()
      .transform((val) => (val ? parseInt(val, 10) : 1))
      .refine((val) => val > 0, 'page must be greater than 0'),
    limit: z
      .string()
      .optional()
      .transform((val) => (val ? parseInt(val, 10) : 1000))
      .refine(
        (val) => val > 0 && val <= 10000,
        'limit must be between 1 and 10000',
      ),
  })
  .refine((data) => new Date(data.from) <= new Date(data.to), {
    message: 'from date must be before or equal to to date',
    path: ['from'],
  })

// Type export
export type DateRangeQuery = z.infer<typeof dateRangeQuerySchema>
