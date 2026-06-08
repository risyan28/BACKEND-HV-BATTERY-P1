/**
 * ACTIVE_DAYS Bitmask Converter
 * 
 * Bitmask values:
 * 1 = Minggu (Sunday)
 * 2 = Senin (Monday)
 * 4 = Selasa (Tuesday)
 * 8 = Rabu (Wednesday)
 * 16 = Kamis (Thursday)
 * 32 = Jumat (Friday)
 * 64 = Sabtu (Saturday)
 * 
 * Examples:
 * 32 -> "Jumat"
 * 62 -> "Senin-Jumat"
 * 127 -> "Setiap Hari"
 * 30 -> "Senin-Kamis"
 */

export interface DayInfo {
  value: number
  name: string
  abbr: string
  order: number
}

const DAYS: DayInfo[] = [
  { value: 1, name: 'Minggu', abbr: 'Min', order: 0 },
  { value: 2, name: 'Senin', abbr: 'Sen', order: 1 },
  { value: 4, name: 'Selasa', abbr: 'Sel', order: 2 },
  { value: 8, name: 'Rabu', abbr: 'Rab', order: 3 },
  { value: 16, name: 'Kamis', abbr: 'Kam', order: 4 },
  { value: 32, name: 'Jumat', abbr: 'Jum', order: 5 },
  { value: 64, name: 'Sabtu', abbr: 'Sab', order: 6 },
]

/**
 * Convert ACTIVE_DAYS bitmask to readable day names
 * @param activeDays - Bitmask integer (0-127)
 * @param format - 'full' (default) or 'abbr' (abbreviated)
 * @returns Readable day string
 */
export function getActiveDaysReadable(
  activeDays: number,
  format: 'full' | 'abbr' = 'full'
): string {
  // All days active
  if (activeDays === 127) {
    return 'Setiap Hari'
  }

  // No days active
  if (activeDays === 0) {
    return 'Tidak Ada'
  }

  // Common ranges
  if (activeDays === 62) return 'Senin-Jumat' // Mon-Fri
  if (activeDays === 30) return 'Senin-Kamis' // Mon-Thu
  if (activeDays === 14) return 'Selasa-Rabu' // Tue-Wed
  if (activeDays === 96) return 'Jumat-Sabtu' // Fri-Sat
  if (activeDays === 65) return 'Minggu & Sabtu' // Sun & Sat

  // Get active days
  const activeDaysList = DAYS.filter((day) => (activeDays & day.value) === day.value)

  if (activeDaysList.length === 0) {
    return 'Tidak Ada'
  }

  // Check for continuous range
  const sortedDays = activeDaysList.sort((a, b) => a.order - b.order)
  const isContinuous = sortedDays.every((day, idx) => {
    if (idx === 0) return true
    const prevDayOrder = sortedDays[idx - 1].order
    return day.order === prevDayOrder + 1
  })

  if (isContinuous && sortedDays.length > 1) {
    const first = sortedDays[0].name
    const last = sortedDays[sortedDays.length - 1].name
    return `${first}-${last}`
  }

  // Return comma-separated list
  const names = sortedDays.map((day) =>
    format === 'abbr' ? day.abbr : day.name
  )
  return names.join(', ')
}

/**
 * Get array of active day objects
 */
export function getActiveDays(activeDays: number): DayInfo[] {
  return DAYS.filter((day) => (activeDays & day.value) === day.value).sort(
    (a, b) => a.order - b.order
  )
}

/**
 * Convert day name(s) to ACTIVE_DAYS bitmask
 * @param dayNames - Single day name, array of names, or range string (e.g., "Senin-Jumat")
 * @returns Bitmask integer
 */
export function getDaysMask(
  dayNames: string | string[]
): number {
  let mask = 0

  if (typeof dayNames === 'string') {
    // Handle range: "Senin-Jumat"
    if (dayNames.includes('-')) {
      const [start, end] = dayNames.split('-').map((s) => s.trim())
      const startDay = DAYS.find((d) => d.name === start)
      const endDay = DAYS.find((d) => d.name === end)

      if (startDay && endDay) {
        for (let i = startDay.order; i <= endDay.order; i++) {
          const day = DAYS.find((d) => d.order === i)
          if (day) mask |= day.value
        }
      }
    } else if (dayNames === 'Setiap Hari') {
      mask = 127
    } else {
      // Single day
      const day = DAYS.find((d) => d.name === dayNames)
      if (day) mask = day.value
    }
  } else {
    // Array of day names
    dayNames.forEach((name) => {
      const day = DAYS.find((d) => d.name === name)
      if (day) mask |= day.value
    })
  }

  return mask
}

// Export for testing/debugging
export const DEBUG = {
  DAYS,
  testConversions: () => {
    const testValues = [0, 1, 2, 4, 8, 16, 32, 64, 30, 62, 96, 127]
    console.log('ACTIVE_DAYS Conversions:')
    testValues.forEach((val) => {
      console.log(`${val.toString().padEnd(3)} -> ${getActiveDaysReadable(val)}`)
    })
  },
}
