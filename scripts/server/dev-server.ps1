# dev-server.ps1
# Smart dev server starter - kills port if in use, then starts dev mode

$PORT = 4001
$MAX_RETRIES = 3
$RETRY_DELAY = 2

Write-Host "==========================================="
Write-Host "DEV MODE - SMART STARTER" -ForegroundColor Cyan
Write-Host "==========================================="

function Stop-ProcessOnPort {
    param([int]$Port)
    
    Write-Host "`nChecking if port $Port is in use..." -ForegroundColor Yellow
    
    try {
        # Use netstat for more reliable PID detection
        $netstatOutput = netstat -ano | Select-String ":$Port\s" | Select-String "LISTENING"
        
        if ($netstatOutput) {
            $killed = $false
            
            foreach ($line in $netstatOutput) {
                # Extract PID from netstat output (last column)
                if ($line -match '\s+(\d+)\s*$') {
                    $processId = [int]$matches[1]
                    
                    # Skip system processes (PID 0, 4)
                    if ($processId -eq 0 -or $processId -eq 4) {
                        Write-Host "  Skipping system process (PID: $processId)" -ForegroundColor Gray
                        continue
                    }
                    
                    try {
                        $processInfo = Get-Process -Id $processId -ErrorAction SilentlyContinue
                        if ($processInfo) {
                            Write-Host "  Found process: $($processInfo.ProcessName) (PID: $processId)" -ForegroundColor Red
                            Write-Host "  Killing process..." -ForegroundColor Yellow
                            Stop-Process -Id $processId -Force -ErrorAction Stop
                            Write-Host "  Process killed successfully" -ForegroundColor Green
                            $killed = $true
                        }
                    } catch {
                        Write-Host "  Warning: Could not kill process $processId - $_" -ForegroundColor Yellow
                    }
                }
            }
            
            # Wait for port to be released (longer wait after kill)
            if ($killed) {
                Write-Host "  Waiting for port to be released..." -ForegroundColor Yellow
                Start-Sleep -Seconds 2
            }
            
            # Verify port is free using netstat again
            $stillInUse = netstat -ano | Select-String ":$Port\s" | Select-String "LISTENING"
            if ($stillInUse) {
                Write-Host "  Warning: Port still in use" -ForegroundColor Red
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
        
        # Fallback: try one more time with longer wait
        Write-Host "  Retrying with extended wait..." -ForegroundColor Yellow
        Start-Sleep -Seconds 3
        
        $check = netstat -ano | Select-String ":$Port\s" | Select-String "LISTENING"
        if (-not $check) {
            Write-Host "  Port is now free after extended wait" -ForegroundColor Green
            return $true
        }
        
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
    
    $portFree = Stop-ProcessOnPort -Port $PORT
    
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
Write-Host "STARTING DEV SERVER" -ForegroundColor Green
Write-Host "==========================================="
Write-Host "TypeScript watch + Auto-restart enabled" -ForegroundColor Cyan
Write-Host "Press Ctrl+C to stop" -ForegroundColor Gray
Write-Host ""

# Run dev mode (TypeScript watch + nodemon)
npx concurrently "tsc --watch" "nodemon"
