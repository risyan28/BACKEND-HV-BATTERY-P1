---
name: add-api-endpoint
description: >
  Guide for adding a new REST API endpoint to this Express + TypeScript backend.
  Use this when asked to add a new route, controller, service, or API endpoint.
---

# Add New API Endpoint — Step-by-Step Pattern

This project uses: **Express.js + TypeScript + Prisma (SQL Server) + Zod validation + Swagger JSDoc**

Folder structure convention:

```
src/
  schemas/     ← Zod input validation schemas
  services/    ← Prisma DB logic
  controllers/ ← Request/response handlers (use asyncHandler)
  routes/      ← Express Router + Swagger JSDoc comments
  app.ts       ← Register new router here
```

---

## Step 1 — Define Zod Schema (`src/schemas/<feature>.schema.ts`)

```ts
import { z } from 'zod'

export const create<Feature>Schema = z.object({
  FIELD_NAME: z.string().min(1),
  SOME_NUMBER: z.number().int().positive(),
})

export const update<Feature>Schema = create<Feature>Schema.partial()

export const <feature>IdParamSchema = z.object({
  id: z.coerce.number().int().positive(),
})
```

Rules:

- Always use `z.coerce.number()` for numeric URL params
- Use `.partial()` for update schemas unless all fields are required
- Keep schemas in their own file, never inline in controller

---

## Step 2 — Create Service (`src/services/<feature>.service.ts`)

```ts
import prisma from '@/prisma'
import { loggers } from '@/utils/logger'

export const <feature>Service = {
  async getAll() {
    return prisma.tB_R_<TABLE>.findMany({
      orderBy: { FID: 'asc' },
    })
  },

  async create(data: { FIELD_NAME: string; SOME_NUMBER: number }) {
    return prisma.tB_R_<TABLE>.create({ data })
  },

  async update(id: number, data: Partial<{ FIELD_NAME: string }>) {
    return prisma.tB_R_<TABLE>.update({
      where: { FID: id },
      data,
    })
  },

  async delete(id: number) {
    return prisma.tB_R_<TABLE>.delete({ where: { FID: id } })
  },
}
```

Rules:

- Always import `prisma` from `@/prisma` (singleton)
- Table/model names in Prisma match `TB_R_*` or `TB_H_*` naming convention
- Use `prisma.$transaction([...])` when you need multiple queries atomically
- Log important operations via `loggers.db.debug(...)` or `loggers.api.info(...)`

---

## Step 3 — Create Controller (`src/controllers/<feature>.controller.ts`)

```ts
import { Request, Response } from 'express'
import { <feature>Service } from '@/services/<feature>.service'
import { asyncHandler } from '@/middleware/errorHandler'
import {
  create<Feature>Schema,
  update<Feature>Schema,
  <feature>IdParamSchema,
} from '@/schemas/<feature>.schema'

export const <feature>Controller = {
  getAll: asyncHandler(async (req: Request, res: Response) => {
    const data = await <feature>Service.getAll()
    res.json(data)
  }),

  create: asyncHandler(async (req: Request, res: Response) => {
    const validatedData = create<Feature>Schema.parse(req.body)
    const data = await <feature>Service.create(validatedData)
    res.json(data)
  }),

  update: asyncHandler(async (req: Request, res: Response) => {
    const { id } = <feature>IdParamSchema.parse(req.params)
    const validatedData = update<Feature>Schema.parse(req.body)
    const data = await <feature>Service.update(id, validatedData)
    res.json(data)
  }),

  delete: asyncHandler(async (req: Request, res: Response) => {
    const { id } = <feature>IdParamSchema.parse(req.params)
    await <feature>Service.delete(id)
    res.json({ success: true })
  }),
}
```

Rules:

- ALWAYS wrap handlers with `asyncHandler` — never use try/catch manually
- ALWAYS validate with `.parse()` before using req.body or req.params
- Never import Prisma directly in a controller — only via the service layer

---

## Step 4 — Create Router (`src/routes/<feature>.routes.ts`)

```ts
import { Router } from 'express'
import { <feature>Controller } from '@/controllers/<feature>.controller'

const router = Router()

/**
 * @swagger
 * /api/<features>:
 *   get:
 *     summary: Get all <features>
 *     tags: [<Features>]
 *     responses:
 *       200:
 *         description: OK
 *       500:
 *         $ref: '#/components/responses/InternalServerError'
 */
router.get('/', <feature>Controller.getAll)

/**
 * @swagger
 * /api/<features>:
 *   post:
 *     summary: Create a new <feature>
 *     tags: [<Features>]
 *     requestBody:
 *       required: true
 *       content:
 *         application/json:
 *           schema:
 *             $ref: '#/components/schemas/<Feature>'
 *     responses:
 *       200:
 *         description: Created
 *       400:
 *         $ref: '#/components/responses/ValidationError'
 */
router.post('/', <feature>Controller.create)

router.put('/:id', <feature>Controller.update)
router.delete('/:id', <feature>Controller.delete)

export default router
```

---

## Step 5 — Register Router in `src/app.ts`

Find the section where existing routes are registered and add:

```ts
import <feature>Router from '@/routes/<feature>.routes'
// ...
app.use('/api/<features>', <feature>Router)
```

---

## Checklist

- [ ] Schema file created in `src/schemas/`
- [ ] Service file created in `src/services/` (only Prisma logic)
- [ ] Controller file created in `src/controllers/` (only asyncHandler wrappers)
- [ ] Route file created in `src/routes/` with Swagger JSDoc
- [ ] Route registered in `src/app.ts`
- [ ] All req.body / req.params validated with Zod `.parse()`
- [ ] No try/catch in controllers — use asyncHandler
