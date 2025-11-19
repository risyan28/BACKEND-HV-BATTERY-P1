// src/utils/startupLogger.ts
import os from 'os'

export function logStartupInfo(port: number) {
  console.log(`🚀 [HTTP] Server running at http://localhost:${port}`)

  const localIPs = getLocalIPs()
  if (localIPs.length > 0) {
    console.log(`🌐 [LAN]  Accessible via HTTP:`)
    localIPs.forEach((ip) => console.log(`         http://${ip}:${port}`))

    console.log(`🔌 [WS]   WebSocket URLs:`)
    localIPs.forEach((ip) => console.log(`         ws://${ip}:${port}`))
  } else {
    console.log(`🌐 [LAN]  Could not detect local IP`)
  }
}

function getLocalIPs(): string[] {
  const interfaces = os.networkInterfaces()
  const ips: string[] = []

  for (const name of Object.keys(interfaces)) {
    const nets = interfaces[name]
    if (!nets) continue
    for (const net of nets) {
      if (net.family === 'IPv4' && !net.internal) {
        ips.push(net.address)
      }
    }
  }
  return ips
}
