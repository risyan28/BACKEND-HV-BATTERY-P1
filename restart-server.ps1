# restart-server.ps1
# Restarts the server by stopping then starting it

$PORT = 4001

Write-Host "==========================================="
Write-Host "RESTARTING SERVER" -ForegroundColor Cyan
Write-Host "==========================================="

# Step 1: Stop existing server
Write-Host "`n[1/2] Stopping existing server..." -ForegroundColor Yellow

try {
    $connections = Get-NetTCPConnection -LocalPort $PORT -ErrorAction SilentlyContinue
    
    if ($connections) {
        $processes = $connections | Select-Object -ExpandProperty OwningProcess -Unique
        
        foreach ($processId in $processes) {
            try {
                $processInfo = Get-Process -Id $processId -ErrorAction SilentlyContinue
                if ($processInfo) {
                    Write-Host "  Stopping $($processInfo.ProcessName) (PID: $processId)..." -ForegroundColor Yellow
                    Stop-Process -Id $processId -Force -ErrorAction Stop
                    Write-Host "  Stopped successfully" -ForegroundColor Green
                }
            } catch {
                Write-Host "  Warning: Could not stop process $processId - $_" -ForegroundColor Yellow
            }
        }
        
        Start-Sleep -Seconds 1
        Write-Host "✅ Server stopped" -ForegroundColor Green
    } else {
        Write-Host "  No server running on port $PORT" -ForegroundColor Gray
    }
} catch {
    Write-Host "  Error: $_" -ForegroundColor Red
}

# Step 2: Start server
Write-Host "`n[2/2] Starting server..." -ForegroundColor Yellow

# Check if we should run in development or production mode
if ($args -contains "--dev" -or $args -contains "-d") {
    Write-Host "  Starting in DEVELOPMENT mode..." -ForegroundColor Cyan
    npm run dev
} else {
    Write-Host "  Starting in PRODUCTION mode..." -ForegroundColor Cyan
    node dist/index.js
}
