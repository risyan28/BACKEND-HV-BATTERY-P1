# start-server.ps1
# Smart server starter - checks and kills port 4001 if in use, then starts server

$PORT = 4001
$MAX_RETRIES = 3
$RETRY_DELAY = 2

Write-Host "==========================================="
Write-Host "SMART SERVER STARTER" -ForegroundColor Cyan
Write-Host "==========================================="

function Kill-ProcessOnPort {
    param([int]$Port)
    
    Write-Host "`nChecking if port $Port is in use..." -ForegroundColor Yellow
    
    try {
        $connections = Get-NetTCPConnection -LocalPort $Port -ErrorAction SilentlyContinue
        
        if ($connections) {
            $processes = $connections | Select-Object -ExpandProperty OwningProcess -Unique
            
            foreach ($processId in $processes) {
                try {
                    $processInfo = Get-Process -Id $processId -ErrorAction SilentlyContinue
                    if ($processInfo) {
                        Write-Host "  Found process: $($processInfo.ProcessName) (PID: $processId)" -ForegroundColor Red
                        Write-Host "  Killing process..." -ForegroundColor Yellow
                        Stop-Process -Id $processId -Force -ErrorAction Stop
                        Write-Host "  Process killed successfully" -ForegroundColor Green
                    }
                } catch {
                    Write-Host "  Warning: Could not kill process $processId - $_" -ForegroundColor Yellow
                }
            }
            
            # Wait a bit for port to be released
            Start-Sleep -Seconds 1
            
            # Verify port is free
            $stillInUse = Get-NetTCPConnection -LocalPort $Port -ErrorAction SilentlyContinue
            if ($stillInUse) {
                Write-Host "  Warning: Port still in use after killing process" -ForegroundColor Red
                return $false
            } else {
                Write-Host "  Port $Port is now free" -ForegroundColor Green
                return $true
            }
        } else {
            Write-Host "  Port $Port is free" -ForegroundColor Green
            return $true
        }
    } catch {
        Write-Host "  Error checking port: $_" -ForegroundColor Red
        return $false
    }
}

# Try to free the port
$attempt = 1
$portFree = $false

while ($attempt -le $MAX_RETRIES -and -not $portFree) {
    if ($attempt -gt 1) {
        Write-Host "`nRetry attempt $attempt of $MAX_RETRIES..." -ForegroundColor Yellow
    }
    
    $portFree = Kill-ProcessOnPort -Port $PORT
    
    if (-not $portFree) {
        if ($attempt -lt $MAX_RETRIES) {
            Write-Host "Waiting ${RETRY_DELAY}s before retry..." -ForegroundColor Yellow
            Start-Sleep -Seconds $RETRY_DELAY
        }
    }
    
    $attempt++
}

if (-not $portFree) {
    Write-Host "`nERROR: Could not free port $PORT after $MAX_RETRIES attempts" -ForegroundColor Red
    Write-Host "Please manually check and kill the process using port $PORT" -ForegroundColor Yellow
    Write-Host "Command: netstat -ano | findstr :$PORT" -ForegroundColor Gray
    exit 1
}

Write-Host "`n==========================================="
Write-Host "STARTING SERVER" -ForegroundColor Green
Write-Host "==========================================="

# Check if we should run in development or production mode
if ($args -contains "--dev" -or $args -contains "-d") {
    Write-Host "Starting in DEVELOPMENT mode (nodemon)..." -ForegroundColor Cyan
    npm run dev
} else {
    Write-Host "Starting in PRODUCTION mode..." -ForegroundColor Cyan
    node dist/index.js
}
