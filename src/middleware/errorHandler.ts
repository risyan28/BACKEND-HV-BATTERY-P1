// src/middleware/errorHandler.ts
import { Request, Response, NextFunction } from 'express'
import { ZodError } from 'zod'
import { Prisma } from '@prisma/client'

/**
 * Custom error class for application-specific errors
 */
export class AppError extends Error {
  constructor(
    public statusCode: number,
    public message: string,
    public isOperational = true,
  ) {
    super(message)
    Object.setPrototypeOf(this, AppError.prototype)
  }
}

/**
 * Centralized error handling middleware
 *
 * Handles:
 * - Zod validation errors (400)
 * - Prisma errors (400/500)
 * - Application errors (custom status)
 * - Unexpected errors (500)
 */
export function errorHandler(
  err: Error,
  req: Request,
  res: Response,
  next: NextFunction,
) {
  console.error('❌ [ERROR]', {
    message: err.message,
    stack: process.env.NODE_ENV === 'development' ? err.stack : undefined,
    path: req.path,
    method: req.method,
  })

  // Zod validation errors
  if (err instanceof ZodError) {
    return res.status(400).json({
      success: false,
      error: 'Validation Error',
      details: err.issues.map((e) => ({
        field: e.path.join('.'),
        message: e.message,
      })),
    })
  }

  // Prisma errors
  if (err instanceof Prisma.PrismaClientKnownRequestError) {
    // P2002: Unique constraint violation
    if (err.code === 'P2002') {
      return res.status(400).json({
        success: false,
        error: 'Duplicate Entry',
        message: 'A record with this value already exists',
      })
    }

    // P2025: Record not found
    if (err.code === 'P2025') {
      return res.status(404).json({
        success: false,
        error: 'Not Found',
        message: 'The requested record does not exist',
      })
    }

    // Other Prisma errors
    return res.status(400).json({
      success: false,
      error: 'Database Error',
      message: err.message,
    })
  }

  // Prisma validation errors
  if (err instanceof Prisma.PrismaClientValidationError) {
    return res.status(400).json({
      success: false,
      error: 'Invalid Data',
      message: 'The provided data is invalid',
    })
  }

  // Application errors
  if (err instanceof AppError) {
    return res.status(err.statusCode).json({
      success: false,
      error: err.message,
    })
  }

  // Default error (unexpected)
  res.status(500).json({
    success: false,
    error: 'Internal Server Error',
    message:
      process.env.NODE_ENV === 'development'
        ? err.message
        : 'Something went wrong',
  })
}

/**
 * Async handler wrapper to catch errors in async route handlers
 */
export function asyncHandler(
  fn: (req: Request, res: Response, next: NextFunction) => Promise<any>,
) {
  return (req: Request, res: Response, next: NextFunction) => {
    Promise.resolve(fn(req, res, next)).catch(next)
  }
}
