export const formatDateTime = (date: Date | null): string | null => {
  if (!date) return null
  const pad = (n: number) => String(n).padStart(2, '0')

  const yyyy = date.getUTCFullYear()
  const MM = pad(date.getUTCMonth() + 1)
  const dd = pad(date.getUTCDate())
  const HH = pad(date.getUTCHours())
  const mm = pad(date.getUTCMinutes())
  const ss = pad(date.getUTCSeconds())

  return `${yyyy}-${MM}-${dd} ${HH}:${mm}:${ss}`
}

export const formatDate = (date: Date | null): string | null => {
  if (!date) return null
  const pad = (n: number) => String(n).padStart(2, '0')

  const yyyy = date.getUTCFullYear()
  const MM = pad(date.getUTCMonth() + 1)
  const dd = pad(date.getUTCDate())

  return `${yyyy}-${MM}-${dd}`
}
