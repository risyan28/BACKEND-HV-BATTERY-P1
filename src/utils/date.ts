import dayjs from 'dayjs'
import utc from 'dayjs/plugin/utc'
import timezone from 'dayjs/plugin/timezone'

dayjs.extend(utc)
dayjs.extend(timezone)

export const formatDateTime = (date: Date | null): string | null => {
  if (!date) return null
  // Format: YYYY-MM-DD HH:MM:SS (Asia/Jakarta timezone)
  return dayjs(date).tz('Asia/Jakarta').format('YYYY-MM-DD HH:mm:ss')
}

export const formatDate = (date: Date | null): string | null => {
  if (!date) return null
  // Format: YYYY-MM-DD (Asia/Jakarta timezone)
  return dayjs(date).tz('Asia/Jakarta').format('YYYY-MM-DD')
}
