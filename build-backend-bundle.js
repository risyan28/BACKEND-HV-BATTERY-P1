// build-backend-bundle.js
const fs = require('fs')
const crypto = require('crypto')
const path = require('path')
const { execSync } = require('child_process')
const os = require('os')

const ROOT = process.cwd()
const DIST = path.join(ROOT, 'dist')
const PACKAGE_JSON = path.join(ROOT, 'package.json')
const PRISMA_DIR = path.join(ROOT, 'prisma')
const ENV_FILE = path.join(ROOT, '.env') // Ganti ke .env.production jika kamu punya
const MANIFEST_FILE = path.join(ROOT, 'backend-runtime.bundle-state.json')
const MODE = process.argv.includes('--slim') ? 'slim' : 'full'
const TARGET = path.join(
  ROOT,
  MODE === 'slim' ? 'backend-runtime-update' : 'backend-runtime',
) // Nama folder output
const ZIP_FILE = path.join(
  ROOT,
  MODE === 'slim' ? 'backend-runtime-update.zip' : 'backend-runtime.zip',
) // Nama file zip output
const ARCHIVE_FILE =
  MODE === 'slim' && os.platform() !== 'win32'
    ? ZIP_FILE.replace(/\.zip$/, '.tar.gz')
    : ZIP_FILE

function run(cmd, cwd = ROOT) {
  console.log(`> ${cmd}`)
  execSync(cmd, { stdio: 'inherit', cwd, shell: true }) // Gunakan shell agar perintah windows seperti xcopy berfungsi
}

function copyRecursive(src, dest) {
  const exists = fs.existsSync(src)
  if (!exists) {
    console.log(`⚠️ Source path does not exist: ${src}`)
    return
  }

  const stats = fs.statSync(src)
  const isDirectory = stats.isDirectory()

  if (isDirectory) {
    if (!fs.existsSync(dest)) {
      fs.mkdirSync(dest, { recursive: true })
    }
    fs.readdirSync(src).forEach((childItemName) => {
      copyRecursive(
        path.join(src, childItemName),
        path.join(dest, childItemName),
      )
    })
  } else {
    fs.copyFileSync(src, dest)
  }
}

function hashFile(filePath) {
  if (!fs.existsSync(filePath)) return `missing:${filePath}`

  const hash = crypto.createHash('sha256')
  hash.update(fs.readFileSync(filePath))
  return hash.digest('hex')
}

function hashDirectory(dirPath) {
  if (!fs.existsSync(dirPath)) return `missing:${dirPath}`

  const hash = crypto.createHash('sha256')

  function walk(currentPath) {
    const stats = fs.statSync(currentPath)
    if (stats.isDirectory()) {
      const children = fs.readdirSync(currentPath).sort()
      hash.update(`dir:${path.relative(ROOT, currentPath)}`)
      for (const child of children) {
        walk(path.join(currentPath, child))
      }
      return
    }

    hash.update(`file:${path.relative(ROOT, currentPath)}`)
    hash.update(fs.readFileSync(currentPath))
  }

  walk(dirPath)
  return hash.digest('hex')
}

function readManifest() {
  if (!fs.existsSync(MANIFEST_FILE)) return null

  try {
    return JSON.parse(fs.readFileSync(MANIFEST_FILE, 'utf8'))
  } catch {
    return null
  }
}

function writeManifest(manifest) {
  fs.writeFileSync(MANIFEST_FILE, JSON.stringify(manifest, null, 2))
}

function getBundleSignature() {
  return crypto
    .createHash('sha256')
    .update(hashFile(PACKAGE_JSON))
    .update(hashFile(path.join(ROOT, 'package-lock.json')))
    .update(hashDirectory(PRISMA_DIR))
    .digest('hex')
}

console.log('📦 Starting Backend Runtime Bundle Creation...\n')
console.log(`   Mode: ${MODE.toUpperCase()}`)

const currentBundleSignature = getBundleSignature()
const previousManifest = readManifest()

if (
  MODE === 'slim' &&
  (!previousManifest ||
    previousManifest.bundleSignature !== currentBundleSignature)
) {
  console.error(
    '\n⚠️  Slim bundle rejected: package.json, package-lock.json, or prisma/ changed since the last full bundle.',
  )
  console.error('   Run: npm run bundle:be:full')
  process.exit(1)
}

try {
  // 1. Pastikan dist/ dan prisma/ siap
  console.log('🔍 Step 1: Ensuring build artifacts are up-to-date...')
  run('npm run build') // Jalankan build

  // 2. Bersihkan folder target lama jika ada
  console.log('\n🧹 Step 2: Cleaning up previous build...')
  if (fs.existsSync(TARGET)) {
    fs.rmSync(TARGET, { recursive: true, force: true })
    console.log(`   Removed old ${TARGET}`)
  }
  fs.mkdirSync(TARGET, { recursive: true })
  console.log(`   Created fresh ${TARGET}`)

  // 3. Copy dist/, prisma/, package.json, .env
  console.log('\n📂 Step 3: Copying necessary files...')

  console.log('   - Copying dist/')
  copyRecursive(DIST, path.join(TARGET, 'dist'))

  if (fs.existsSync(PRISMA_DIR)) {
    console.log('   - Copying prisma/')
    copyRecursive(PRISMA_DIR, path.join(TARGET, 'prisma'))
  } else {
    console.warn('   ⚠️ Prisma directory not found, skipping.')
  }

  console.log('   - Copying package.json')
  fs.copyFileSync(PACKAGE_JSON, path.join(TARGET, 'package.json'))

  const PRISMA_CONFIG = path.join(ROOT, 'prisma.config.ts')
  if (fs.existsSync(PRISMA_CONFIG)) {
    console.log('   - Copying prisma.config.ts')
    fs.copyFileSync(PRISMA_CONFIG, path.join(TARGET, 'prisma.config.ts'))
  } else {
    console.warn('   ⚠️ prisma.config.ts not found, skipping.')
  }

  if (fs.existsSync(ENV_FILE)) {
    console.log('   - Copying .env')
    fs.copyFileSync(ENV_FILE, path.join(TARGET, '.env'))
  } else {
    console.warn(
      '   ⚠️ .env file not found in root, skipping. Remember to set environment variables on the server.',
    )
  }

  // 4. Install production dependencies hanya untuk full bootstrap bundle
  if (MODE === 'full') {
    console.log(
      '\n📦 Step 4: Installing production dependencies in runtime folder...',
    )
    run('npm install --omit=dev', TARGET) // Install di dalam folder target
    run('npx prisma generate', TARGET) // Generate Prisma Client di dalam folder target
  } else {
    console.log('\n⚡ Step 4: Slim mode - skipping node_modules install')
  }

  // 5. Create deployment guide
  console.log('\n📝 Step 5: Creating deployment guide...')
  const deployGuide = `# Backend Deployment Guide

## Cara Deploy ke Server Offline

### 1. Extract File
\`\`\`bash
# Extract ZIP file
unzip backend-runtime.zip
# atau
tar -xzf backend-runtime.tar.gz
\`\`\`

### 2. Masuk ke Folder
\`\`\`bash
cd backend-runtime
\`\`\`

### 3. Setup Environment Variables
Edit file .env sesuai dengan konfigurasi server production:

\`\`\`env
# Database
DATABASE_URL="sqlserver://localhost:1433;database=DB_TMMIN1_KRW_PIS_HV_BATTERY;user=sa;password=YOUR_PASSWORD;encrypt=false;trustServerCertificate=true"

# Server
PORT=4001
NODE_ENV=production

# Optional Features
REDIS_ENABLED=false  # Set true if Redis available
SENTRY_ENABLED=false
OTEL_ENABLED=false
\`\`\`

### 4. Database Migration (Jika Perlu)
\`\`\`bash
# Jika ada schema changes
npx prisma migrate deploy
\`\`\`

### 5. Start Server

#### Option A: Direct Run
\`\`\`bash
node dist/index.js
\`\`\`

#### Option B: PM2 (Recommended)
\`\`\`bash
# Install PM2 globally (one-time)
npm install -g pm2

# Start server
pm2 start dist/index.js --name "hv-battery-backend" --time

# Auto-start on server reboot
pm2 startup
pm2 save

# View logs
pm2 logs hv-battery-backend

# Monitor
pm2 monit
\`\`\`

#### Option C: Windows Service (dengan node-windows)
\`\`\`bash
npm install -g node-windows
# Then use install-windows-service.js script if needed
\`\`\`

### 6. Verify Server Running
\`\`\`bash
# Check if port 4001 is listening
netstat -ano | findstr :4001

# Test health endpoint
curl http://localhost:4001/api/health
\`\`\`

## Troubleshooting

### Port Already in Use
\`\`\`bash
# Windows
netstat -ano | findstr :4001
# Kill process: taskkill /PID <PID> /F

# Linux
lsof -i :4001
# Kill process: kill -9 <PID>
\`\`\`

### Database Connection Failed
1. Check SQL Server is running
2. Verify DATABASE_URL in .env
3. Check firewall allows port 1433
4. Test connection: sqlcmd -S localhost -U sa -P password

### Prisma Client Error
\`\`\`bash
# Regenerate Prisma client
npx prisma generate
\`\`\`

## PM2 Commands Cheatsheet

\`\`\`bash
pm2 list                        # List all processes
pm2 stop hv-battery-backend     # Stop process
pm2 restart hv-battery-backend  # Restart process
pm2 delete hv-battery-backend   # Remove from PM2
pm2 logs hv-battery-backend     # View logs
pm2 logs --lines 100            # Last 100 lines
pm2 flush                       # Clear all logs
\`\`\`

## Server Requirements

- Node.js: v18.0.0 or higher (recommended: v24.13.0)
- SQL Server: 2017 or higher
- RAM: Minimum 512MB, Recommended 1GB+
- Disk: Minimum 500MB for app + node_modules

## Optional: Redis Setup (for caching)

\`\`\`bash
# Windows: Download Redis from https://github.com/microsoftarchive/redis/releases
# Linux:
sudo apt-get install redis-server
sudo systemctl start redis

# Update .env
REDIS_ENABLED=true
REDIS_HOST=localhost
REDIS_PORT=6379
\`\`\`

## Build Info
- Bundle created: ${new Date().toISOString()}
- Node version: ${process.version}
- Platform: ${os.platform()} ${os.arch()}
`

  fs.writeFileSync(path.join(TARGET, 'DEPLOYMENT.md'), deployGuide)
  console.log('   Created DEPLOYMENT.md')

  // 6. Create start scripts for Windows
  console.log('\n🔧 Step 6: Creating start scripts...')

  const startBat = `@echo off
title HV Battery Backend Server
echo Starting HV Battery Backend Server...
node dist/index.js
pause
`
  fs.writeFileSync(path.join(TARGET, 'start.bat'), startBat)
  console.log('   Created start.bat (Windows quick start)')

  const pm2Start = `@echo off
echo ============================================
echo PM2 AUTO-START SETUP
echo ============================================
echo.
echo NOTE: PM2 must be installed first!
echo Run: npm install -g pm2 (one-time setup)
echo.
echo Starting server with PM2...
call pm2 start dist/index.js --name "hv-battery-backend" --time
echo.
echo Configuring auto-start on server reboot...
call pm2 startup
call pm2 save
echo.
echo ============================================
echo SUCCESS! Server is running with PM2
echo ============================================
echo.
echo Useful commands:
echo   pm2 logs hv-battery-backend    - View logs
echo   pm2 monit                      - Monitor resources
echo   pm2 restart hv-battery-backend - Restart server
echo   pm2 stop hv-battery-backend    - Stop server
echo   pm2 list                       - List all processes
echo.
pause
`
  fs.writeFileSync(path.join(TARGET, 'start-pm2.bat'), pm2Start)
  console.log('   Created start-pm2.bat (PM2 auto-start)')

  const installPm2 = `@echo off
echo ============================================
echo PM2 ONE-TIME INSTALLATION
echo ============================================
echo.
echo This script will install PM2 globally
echo You only need to run this ONCE per server
echo.
echo NOTE: Requires internet connection!
echo.
pause
echo.
echo Installing PM2...
call npm install -g pm2
echo.
echo ============================================
echo PM2 INSTALLED SUCCESSFULLY
echo ============================================
echo.
echo Next step: Run start-pm2.bat to start server
echo.
pause
`
  fs.writeFileSync(path.join(TARGET, 'install-pm2.bat'), installPm2)
  console.log('   Created install-pm2.bat (One-time PM2 installation)')

  // 7. Create ZIP archive only for slim overlay bundles
  if (MODE === 'slim') {
    console.log('\n🗜️  Step 7: Creating ZIP archive...')
    let zipCmd
    if (os.platform() === 'win32') {
      zipCmd = `powershell -Command "Compress-Archive -Path '${TARGET}\\*' -DestinationPath '${ARCHIVE_FILE}' -Force"`
    } else {
      zipCmd = `tar -czf ${ARCHIVE_FILE} -C ${path.dirname(TARGET)} ${path.basename(TARGET)}`
    }
    run(zipCmd, ROOT)
    console.log(`   ✅ Created: ${path.basename(ARCHIVE_FILE)}`)
  }

  console.log('\n✅ Success!')
  console.log(`   - Backend runtime bundle ready: ${TARGET}`)
  if (MODE === 'slim') {
    console.log(`   - ZIP archive ready: ${ARCHIVE_FILE}`)
    console.log(`   - Ready as overlay update for existing runtime`)
  } else {
    console.log(`   - Ready for manual deployment (copy folder directly)`)
    writeManifest({
      bundleType: 'full',
      createdAt: new Date().toISOString(),
      bundleSignature: currentBundleSignature,
    })
  }
  console.log('\n📋 Next Steps:')
  if (MODE === 'slim') {
    console.log(`   1. Extract ZIP into existing backend-runtime folder`)
    console.log(`   2. Keep node_modules from the base runtime install`)
    console.log(`   3. Restart PM2 / service`)
    console.log(`   4. Run Prisma migrate only if schema changed`)
  } else {
    console.log(
      `   1. Copy entire '${path.basename(TARGET)}' folder to production server`,
    )
    console.log(`   2. Navigate: cd backend-runtime`)
    console.log(`   3. Edit .env for production settings`)
    console.log(`   4. Start server:`)
    console.log(`      - Windows: Double-click start-pm2.bat (recommended)`)
    console.log(`      - Or: node dist/index.js`)
    console.log(`   5. Read DEPLOYMENT.md for detailed instructions`)
  }
} catch (error) {
  console.error('\n❌ An error occurred during the build process:')
  console.error(error.message)
  process.exit(1)
}
