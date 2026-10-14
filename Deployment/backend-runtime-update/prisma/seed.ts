import { PrismaMssql } from '@prisma/adapter-mssql'
import { PrismaClient } from '@prisma/client'
import dotenv from 'dotenv'

dotenv.config({ path: require('path').resolve(__dirname, '..', '.env') })

const url = process.env.DATABASE_URL
if (!url) throw new Error('DATABASE_URL not set')
const adapter = new PrismaMssql(url)
const prisma = new PrismaClient({ adapter })

async function main() {
  console.log('Seeding TB_R_SCAN_MAN_BRACKET...')

  // Create table if not exists (mirrors the Prisma model definition)
  await prisma.$executeRawUnsafe(`
    IF NOT EXISTS (SELECT * FROM sysobjects WHERE name='TB_R_SCAN_MAN_BRACKET' AND xtype='U')
    CREATE TABLE TB_R_SCAN_MAN_BRACKET (
      FID        INT          NOT NULL IDENTITY(1,1) PRIMARY KEY,
      BARCODE    VARCHAR(100) NULL,
      FLAG       INT          NULL DEFAULT 0,
      CREATED_AT DATETIME     NULL DEFAULT GETDATE(),
      UPDATED_AT DATETIME     NULL DEFAULT GETDATE()
    )
  `)

  // Single batch: SET IDENTITY_INSERT ON → INSERT → OFF (same session)
  await prisma.$executeRawUnsafe(`
    SET IDENTITY_INSERT TB_R_SCAN_MAN_BRACKET ON
    IF NOT EXISTS (SELECT 1 FROM TB_R_SCAN_MAN_BRACKET WHERE FID = 1)
      INSERT INTO TB_R_SCAN_MAN_BRACKET (FID, BARCODE, FLAG) VALUES (1, '', 0)
    SET IDENTITY_INSERT TB_R_SCAN_MAN_BRACKET OFF
  `)

    type Row = { FID: number; BARCODE: string | null; FLAG: number | null }
  const row = await prisma.$queryRawUnsafe<Array<Row>>(`SELECT FID, BARCODE, FLAG FROM TB_R_SCAN_MAN_BRACKET WHERE FID = 1`)
  console.log('Verified:', row[0])
}

main()
  .catch((e) => {
    console.error('Seed failed:', e)
    process.exit(1)
  })
  .finally(async () => {
    await prisma.$disconnect()
  })
