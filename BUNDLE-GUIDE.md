# Backend Bundle - Offline Deployment Guide

## Apa itu Bundle?

Bundle adalah package lengkap backend yang sudah include:

- ✅ Compiled JavaScript code (dist/)
- ✅ Production dependencies (node_modules/)
- ✅ Prisma schema & client
- ✅ Environment configuration (.env)
- ✅ Deployment scripts

**Keuntungan**: Bisa deploy ke server yang **OFFLINE** (tidak ada internet)

## Cara Membuat Bundle

### 1. Build Bundle

```bash
npm run bundle:be
```

Script ini akan:

1. Build TypeScript → JavaScript
2. Copy semua file yang dibutuhkan
3. Install production dependencies (tanpa devDependencies)
4. Generate Prisma client
5. Buat deployment guide + start scripts
6. Compress jadi ZIP file

### 2. Output

Setelah selesai, akan ada:

- **Folder**: `backend-runtime/` - Ready to deploy
- **ZIP**: `backend-runtime.zip` - Untuk transfer ke server

### 3. File Size

Typical size: ~150-250 MB (include node_modules)

## Cara Deploy ke Server Offline

### Step 1: Transfer File

Copy `backend-runtime.zip` ke server production (via USB, network share, dll)

### Step 2: Extract

```bash
# Windows
# Right-click > Extract All
# atau PowerShell:
Expand-Archive -Path backend-runtime.zip -DestinationPath .

# Linux
unzip backend-runtime.zip
```

### Step 3: Configure Environment

Edit file `.env` di dalam folder `backend-runtime/`:

```env
# Database Connection
DATABASE_URL="sqlserver://YOUR_SERVER:1433;database=DB_NAME;user=sa;password=YOUR_PASSWORD;encrypt=false;trustServerCertificate=true"

# Server Settings
PORT=4001
NODE_ENV=production

# Optional Features (set false jika tidak ada infrastruktur)
REDIS_ENABLED=false
SENTRY_ENABLED=false
OTEL_ENABLED=false
```

### Step 4: Start Server

#### Windows - Easy Mode (Double Click)

1. **start-pm2.bat** (Recommended)
   - Auto-install PM2
   - Auto-start server
   - Auto-restart on crash
   - Logs tersimpan
2. **start.bat** (Simple)
   - Direct start dengan Node.js
   - Tidak auto-restart
   - Window harus tetap terbuka

#### Manual Start

```bash
# Production mode
node dist/index.js

# With PM2 (recommended)
npm install -g pm2
pm2 start dist/index.js --name "hv-battery-backend" --time
pm2 save
```

### Step 5: Verify

```bash
# Check server running
curl http://localhost:4001/api/health

# Or browser
http://localhost:4001/api/health

# Expected response
{
  "status": "healthy",
  "database": "connected",
  "timestamp": "2026-02-07T..."
}
```

## Server Requirements

### Minimum:

- **OS**: Windows Server 2016+ / Linux (Ubuntu 20.04+)
- **Node.js**: v18.0.0+
- **SQL Server**: 2017+ (running & accessible)
- **RAM**: 512MB
- **Disk**: 500MB free

### Recommended:

- **OS**: Windows Server 2022 / Ubuntu 22.04
- **Node.js**: v24.13.0 (LTS)
- **SQL Server**: 2019+
- **RAM**: 2GB+
- **Disk**: 2GB+ free

### Optional (untuk performance):

- **Redis**: v7.0+ (for caching)
- **PM2**: Latest (for process management)

## Troubleshooting

### ❌ Port 4001 sudah dipakai

```bash
# Windows
netstat -ano | findstr :4001
# Lihat PID, lalu kill:
taskkill /PID <PID> /F

# Linux
lsof -i :4001
kill -9 <PID>
```

### ❌ Database connection failed

1. Check SQL Server running: `sqlcmd -S localhost -U sa -P password`
2. Check firewall port 1433 terbuka
3. Verify DATABASE_URL di .env
4. Test manual connection

### ❌ Prisma Client error

```bash
# Regenerate Prisma client
npx prisma generate
```

### ❌ Missing dependencies error

Bundle seharusnya sudah include semua dependencies. Kalau masih error:

```bash
npm install --omit=dev
npx prisma generate
```

## PM2 Management (Recommended)

### Install PM2

```bash
npm install -g pm2
```

### Basic Commands

```bash
# Start
pm2 start dist/index.js --name "hv-battery-backend" --time

# Status
pm2 list

# Logs
pm2 logs hv-battery-backend
pm2 logs --lines 100  # Last 100 lines

# Restart
pm2 restart hv-battery-backend

# Stop
pm2 stop hv-battery-backend

# Delete
pm2 delete hv-battery-backend

# Monitor
pm2 monit

# Auto-start on boot
pm2 startup
pm2 save
```

## Update Deployment

Kalau ada update code:

1. Build bundle baru: `npm run bundle:be`
2. Stop server lama: `pm2 stop hv-battery-backend`
3. Backup folder lama
4. Extract bundle baru
5. Copy .env dari backup (agar config tidak hilang)
6. Start server: `pm2 start dist/index.js --name "hv-battery-backend"`
7. Verify: `curl http://localhost:4001/api/health`

## Production Checklist

- [ ] Node.js v18+ installed
- [ ] SQL Server accessible
- [ ] Port 4001 available
- [ ] .env configured correctly
- [ ] Database schema up-to-date (prisma migrate deploy)
- [ ] Server has enough RAM (min 512MB)
- [ ] Firewall allows port 4001
- [ ] PM2 installed (optional but recommended)
- [ ] Backup strategy implemented
- [ ] Monitoring setup (logs, health checks)

## File Structure

```
backend-runtime/
├── dist/                    # Compiled JavaScript
├── node_modules/            # Production dependencies
├── prisma/                  # Database schema
│   └── schema.prisma
├── package.json            # Node.js metadata
├── .env                    # Environment config (EDIT THIS!)
├── DEPLOYMENT.md           # Detailed deployment guide
├── start.bat               # Windows quick start
└── start-pm2.bat           # PM2 auto-start script
```

## Security Notes

⚠️ **IMPORTANT**:

- Jangan commit `.env` ke Git
- Ganti default database password
- Set `NODE_ENV=production`
- Disable debug mode
- Review firewall rules

## Performance Tips

1. **Enable Redis** (if available):

   ```env
   REDIS_ENABLED=true
   REDIS_HOST=localhost
   REDIS_PORT=6379
   ```

   Result: 83% faster cache hits

2. **Database Indexes**: Already created in Phase 3
   Result: 98% faster queries

3. **Use PM2 cluster mode** (multi-core):
   ```bash
   pm2 start dist/index.js -i max --name "hv-battery-backend"
   ```

## Support

Kalau ada masalah deployment:

1. Check logs: `pm2 logs hv-battery-backend`
2. Read DEPLOYMENT.md di folder backend-runtime
3. Verify server requirements
4. Test database connection manually

---

**Bundle Version**: Auto-generated on `npm run bundle:be`
**Target Environment**: Production / Offline Servers
**Maintenance**: Update bundle setiap kali ada code changes
