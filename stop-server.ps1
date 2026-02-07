# stop-server.ps1
# Gracefully stops the server by killing process on port 4001

$PORT = 4001

Write-Host "==========================================="
Write-Host "STOPPING SERVER" -ForegroundColor Red
Write-Host "==========================================="

Write-Host "`nLooking for processes using port $PORT..." -ForegroundColor Yellow

try {
    $connections = Get-NetTCPConnection -LocalPort $PORT -ErrorAction SilentlyContinue
    
    if ($connections) {
        $processes = $connections | Select-Object -ExpandProperty OwningProcess -Unique
        
        Write-Host "Found $($processes.Count) process(es) to stop" -ForegroundColor Yellow
        
        foreach ($processId in $processes) {
            try {
                $processInfo = Get-Process -Id $processId -ErrorAction SilentlyContinue
                if ($processInfo) {
                    Write-Host "`nProcess: $($processInfo.ProcessName) (PID: $processId)" -ForegroundColor White
                    Write-Host "Stopping..." -ForegroundColor Yellow
                    Stop-Process -Id $processId -Force -ErrorAction Stop
                    Write-Host "Stopped successfully" -ForegroundColor Green
                }
            } catch {
                Write-Host "Warning: Could not stop process $processId - $_" -ForegroundColor Yellow
            }
        }
        
        # Wait for port to be released
        Start-Sleep -Seconds 1
        
        # Verify
        $stillRunning = Get-NetTCPConnection -LocalPort $PORT -ErrorAction SilentlyContinue
        if ($stillRunning) {
            Write-Host "`nWarning: Some processes may still be using port $PORT" -ForegroundColor Yellow
        } else {
            Write-Host "`nAll processes stopped. Port $PORT is free." -ForegroundColor Green
        }
    } else {
        Write-Host "No processes found using port $PORT" -ForegroundColor Green
    }
} catch {
    Write-Host "Error: $_" -ForegroundColor Red
    exit 1
}

Write-Host "`n==========================================="
Write-Host "DONE" -ForegroundColor Green
Write-Host "==========================================="
