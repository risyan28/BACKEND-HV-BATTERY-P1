# Server Management Scripts

## Quick Commands

### Production Mode

```bash
# Start server (with automatic port cleanup)
npm start

# Stop server
npm run stop

# Restart server (stop + start)
npm run restart

# Start directly (no auto cleanup)
npm run start:direct
```

### Development Mode

```bash
# Start with TypeScript watch + auto-restart
npm run dev

# Build TypeScript only
npm run build
```

### Server Management (Safe Mode - Auto Port Cleanup)

```bash
npm start
# or
.\start-server.ps1
```

**Features:**

- ✅ Checks if port 4001 is in use
- ✅ Automatically kills blocking processes
- ✅ Retries up to 3 times if needed
- ✅ Starts server in production mode

### Development Mode with Auto Cleanup

```bash
.\start-server.ps1 --dev
# or
.\start-server.ps1 -d
```

### Stop Server

```bash
npm run stop
# or
.\stop-server.ps1
```

**Features:**

- ✅ Finds all processes using port 4001
- ✅ Gracefully stops them
- ✅ Verifies port is free

### Manual Port Check

```bash
# Check what's using port 4001
netstat -ano | findstr :4001

# Kill process manually (replace PID)
Stop-Process -Id <PID> -Force
```

## Common Scenarios

### Scenario 1: "Port already in use" error

**Problem:** You stopped the server (Ctrl+C) but the port is still occupied

**Solution:**

```bash
npm run start:safe
```

This automatically cleans up the port before starting.

### Scenario 2: Development workflow

```bash
# First time
npm run build
npm run start:safe

# After code changes
npm run build
npm run start:safe
```

### Scenario 3: Force stop everything

```bash
npm run stop
```

### Scenario 4: Development mode (npm run dev)

**Problem:** Nodemon restarts cause EADDRINUSE errors

**Solution (Already Applied):**

- Nodemon delay increased to 3500ms (was 2500ms)
- Graceful shutdown adds 500ms port release delay
- Total buffer: ~4 seconds between restart cycles

**Usage:**

```bash
npm run dev  # TypeScript watch + auto-restart
# Make changes to .ts files
# Nodemon will auto-restart without port conflicts
```

**If you still see EADDRINUSE in dev mode:**

1. Stop dev server (Ctrl+C)
2. Run: `npm run stop` to clean up orphaned processes
3. Restart: `npm run dev`

## Script Details

### start-server.ps1

- **Purpose:** Smart server starter with automatic port cleanup
- **Port:** 4001 (configurable via `$PORT` variable)
- **Retries:** 3 attempts with 2-second delays
- **Modes:**
  - Production: `.\start-server.ps1` → runs `npm start`
  - Development: `.\start-server.ps1 --dev` → runs `npm run dev`

### stop-server.ps1

- **Purpose:** Clean server shutdown
- **Action:** Finds and kills all processes using port 4001
- **Verification:** Confirms port is free after stopping

## Troubleshooting

### PowerShell Execution Policy Error

```
.\start-server.ps1 : File cannot be loaded because running scripts is disabled
```

**Fix:**

```bash
# Temporary (current session only)
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass

# Permanent (requires admin)
Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned
```

### Port Still in Use After Multiple Attempts

```bash
# Check processes manually
Get-NetTCPConnection -LocalPort 4001 | Select-Object -ExpandProperty OwningProcess | Get-Process

# Force kill all Node processes (nuclear option)
Get-Process node | Stop-Process -Force
```

### Server Won't Start Even After Port Cleanup

```bash
# Check for errors in build
npm run build

# Verify .env file exists
ls .env

# Check database connection
# Make sure SQL Server is running
```

## Integration with Existing Scripts

All your existing npm scripts still work:

```bash
npm start          # Original start (no auto cleanup)
npm run start:safe # NEW - Safe start with auto cleanup
npm run dev        # Development mode (watch + nodemon)
npm run build      # TypeScript compilation
npm run stop       # NEW - Stop server gracefully
```

## Recommendation

**Always use `npm run start:safe`** instead of `npm start` to avoid port conflicts.

Update your workflow:

```bash
# Old way
npm run build
npm start  # May fail if port in use

# New way
npm run build
npm run start:safe  # Always works
```

## Technical Notes

- Scripts use `Get-NetTCPConnection` (Windows PowerShell)
- Compatible with Windows 10/11 and Windows Server
- No admin privileges required
- Safe to run multiple times (idempotent)
- Graceful shutdown detection via exit codes
