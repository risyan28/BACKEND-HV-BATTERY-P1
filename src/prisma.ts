import { PrismaMssql } from '@prisma/adapter-mssql'
import { PrismaClient } from '@prisma/client'

function isIpv4Host(host: string): boolean {
  const m = host.match(/^(\d{1,3})(?:\.(\d{1,3})){3}$/)
  if (!m) return false
  const parts = host.split('.').map((n) => Number(n))
  return (
    parts.length === 4 &&
    parts.every((n) => Number.isInteger(n) && n >= 0 && n <= 255)
  )
}

function extractSqlServerHost(input: string): string | null {
  const s = input.trim()
  const prefix = 'sqlserver://'
  if (!s.toLowerCase().startsWith(prefix)) return null

  const after = s.slice(prefix.length)
  const hostPortAndMaybeCreds = after.split(';', 1)[0] ?? ''
  const hostPort = hostPortAndMaybeCreds.includes('@')
    ? (hostPortAndMaybeCreds.split('@').pop() ?? '')
    : hostPortAndMaybeCreds

  // host:port
  const host = hostPort.split(':', 1)[0] ?? ''
  return host.trim() || null
}

function normalizeDatabaseUrl(url: string): string {
  const trimmed = url.trim()
  if (!trimmed) return trimmed

  // If user already set encrypt=..., respect it.
  if (/;encrypt\s*=\s*/i.test(trimmed)) return trimmed

  const host = extractSqlServerHost(trimmed)
  if (!host) return trimmed

  // Node emits DEP0123 when TLS ServerName is an IP.
  // In dev, if connecting via IP and encrypt isn't specified, default to encrypt=false.
  if (!isIpv4Host(host)) return trimmed

  const needsSemicolon = !trimmed.endsWith(';')
  return `${trimmed}${needsSemicolon ? ';' : ''}encrypt=false;`
}

const adapter = new PrismaMssql(normalizeDatabaseUrl(process.env.DATABASE_URL!))
const prisma = new PrismaClient({ adapter })
export default prisma
