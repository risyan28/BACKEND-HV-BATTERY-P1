---
name: add-prisma-model
description: >
  Guide for adding a new Prisma model to this SQL Server database schema.
  Use this when asked to add a new table, database model, or Prisma schema entry.
---

# Add New Prisma Model — SQL Server Pattern

This project uses **Prisma ORM with SQL Server (mssql)**. The `datasource` is `sqlserver`.

---

## Step 1 — Add Model to `prisma/schema.prisma`

### Naming Conventions in This Project

| Category              | Prefix  | Example                 |
| --------------------- | ------- | ----------------------- |
| Master data           | `TB_M_` | `TB_M_BATTERY_MAPPING`  |
| Runtime/transactional | `TB_R_` | `TB_R_SEQUENCE_BATTERY` |
| Historical/log        | `TB_H_` | `TB_H_PRINT_LOG`        |

### SQL Server Field Type Mapping

| Purpose                     | Prisma type                         |
| --------------------------- | ----------------------------------- |
| Short code/key (< 50 chars) | `String @db.VarChar(N)`             |
| NLS / Unicode text          | `String @db.NVarChar(N)`            |
| Timestamp                   | `DateTime @db.DateTime`             |
| Date only                   | `DateTime @db.Date`                 |
| Decimal number              | `Decimal @db.Decimal(p, s)`         |
| Small flag/status           | `Int @db.TinyInt`                   |
| Auto-increment PK           | `Int @id @default(autoincrement())` |

### Example Model

```prisma
model TB_R_<FEATURE> {
  FID                Int       @id(map: "PK_TB_R_<FEATURE>") @default(autoincrement())
  FIELD_VARCHAR      String    @db.VarChar(50)
  FIELD_NVARCHAR     String?   @db.NVarChar(200)
  FIELD_INT          Int?
  FIELD_DATE         DateTime? @db.Date
  FDATETIME_MODIFIED DateTime? @default(now(), map: "DF_TB_R_<FEATURE>_FDATETIME_MODIFIED") @db.DateTime

  @@index([FIELD_VARCHAR], map: "IX_<FEATURE>_FIELD")
}
```

Rules:

- Primary key constraint name: `PK_<TABLE_NAME>`
- Default value constraint name: `DF_<TABLE_NAME>_<COLUMN_NAME>`
- Index name: `IX_<TABLE_NAME>_<COLUMN_ABBREVIATION>`
- All constraint/index names must use `map: "..."` explicitly (SQL Server requirement)
- Make nullable fields that may not always have data (`?`)
- `FDATETIME_MODIFIED` is standard for tracking last update — add to most tables

---

## Step 2 — Apply Schema to Database

```bash
# Option A: Push schema directly (dev/no-migration needed)
npm run db:push

# Option B: Create migration (preferred for production)
npm run migrate
# Then enter a migration name like: add_tb_r_feature
```

> Use `db:push` during development. Use `migrate` when this change needs to be tracked and deployed.

---

## Step 3 — Regenerate Prisma Client

After any schema change, Prisma Client must be regenerated:

```bash
npm run generate
```

This updates the TypeScript types so `prisma.tB_R_<feature>` is available.

---

## Step 4 — Create Zod Schema (for API validation)

In `src/schemas/<feature>.schema.ts`:

```ts
import { z } from 'zod'

export const create<Feature>Schema = z.object({
  FIELD_VARCHAR: z.string().min(1).max(50),
  FIELD_NVARCHAR: z.string().max(200).optional(),
  FIELD_INT: z.number().int().optional(),
  FIELD_DATE: z.string().datetime().optional(),
})
```

---

## Step 5 — Update Service

In `src/services/<feature>.service.ts`, use `prisma.tB_R_<feature>` (camelCase version of table name).

Prisma model name mapping:

- `TB_R_SEQUENCE_BATTERY` → `prisma.tB_R_SEQUENCE_BATTERY`
- `TB_M_INIT_QRCODE` → `prisma.tB_M_INIT_QRCODE`
- `TB_H_PRINT_LOG` → `prisma.tB_H_PRINT_LOG`

---

## Checklist

- [ ] Model added to `prisma/schema.prisma` with correct naming convention
- [ ] All constraint/index names use `map:` parameter
- [ ] `npm run db:push` or `npm run migrate` executed
- [ ] `npm run generate` executed to rebuild Prisma Client
- [ ] Zod schema created for input validation
- [ ] Service file created to use the new model
