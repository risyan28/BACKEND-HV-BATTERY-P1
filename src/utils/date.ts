import dayjs from 'dayjs'
import utc from 'dayjs/plugin/utc'
import timezone from 'dayjs/plugin/timezone'

dayjs.extend(utc)
dayjs.extend(timezone)

export const formatDateTime = (date: Date | null): string | null => {
  if (!date) return null
  // DB stores WIB wall-clock time (no timezone). MSSQL driver often materializes
  // DATETIME as a JS Date assuming UTC. To display "as-is" (no +7 shift), format
  // using UTC fields.
  const y = date.getUTCFullYear()
  const m = String(date.getUTCMonth() + 1).padStart(2, '0')
  const d = String(date.getUTCDate()).padStart(2, '0')
  const hh = String(date.getUTCHours()).padStart(2, '0')
  const mm = String(date.getUTCMinutes()).padStart(2, '0')
  const ss = String(date.getUTCSeconds()).padStart(2, '0')
  return `${y}-${m}-${d} ${hh}:${mm}:${ss}`
}

export const formatDate = (date: Date | null): string | null => {
  if (!date) return null
  // Same reasoning as formatDateTime(): keep DB wall-clock date.
  const y = date.getUTCFullYear()
  const m = String(date.getUTCMonth() + 1).padStart(2, '0')
  const d = String(date.getUTCDate()).padStart(2, '0')
  return `${y}-${m}-${d}`
}

export const normalizeDbDateTimeString = (
  input: string | null | undefined,
): string | null => {
  if (!input) return null

  // Accept either "YYYY-MM-DD HH:mm:ss" or ISO-like strings and normalize.
  const s = String(input).trim()

  // "YYYY-MM-DD HH:mm:ss" (optionally with .SSS)
  const m = s.match(
    /^(\d{4}-\d{2}-\d{2})[ T](\d{2}:\d{2}:\d{2})(?:\.\d{1,3})?(?:Z|[+-]\d{2}:?\d{2})?$/,
  )
  if (m) return `${m[1]} ${m[2]}`

  // Fallback: best-effort prefix
  if (s.length >= 19 && (s[10] === 'T' || s[10] === ' ')) {
    return `${s.slice(0, 10)} ${s.slice(11, 19)}`
  }
  return s
}

export const toJakartaDbDate = (input?: string | Date | null): Date => {
  if (!input) {
    return dayjs().tz('Asia/Jakarta').utcOffset(0, true).toDate()
  }

  // If a string has no explicit timezone, treat it as Jakarta wall-clock.
  if (typeof input === 'string') {
    const s = input.trim()
    const hasExplicitZone = /([zZ]|[+-]\d{2}:?\d{2})$/.test(s)

    if (!hasExplicitZone) {
      const normalized = s.replace('T', ' ')
      const datePart = normalized.slice(0, 10)
      const timePart =
        normalized.length >= 19 ? normalized.slice(11, 19) : '00:00:00'
      const base = `${datePart} ${timePart}`

      const parsed = dayjs.tz(base, 'YYYY-MM-DD HH:mm:ss', 'Asia/Jakarta')
      return parsed.utcOffset(0, true).toDate()
    }

    // Zoned string (e.g., ISO with Z or +07:00): convert to Jakarta then keep local.
    return dayjs(s).tz('Asia/Jakarta').utcOffset(0, true).toDate()
  }

  // Date object: interpret as an instant, convert to Jakarta then keep local.
  return dayjs(input).tz('Asia/Jakarta').utcOffset(0, true).toDate()
}
