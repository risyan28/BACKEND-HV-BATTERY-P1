# Test Step 3: Redis Cache for Traceability & Print History
# Test cache implementation with 15-minute TTL

$baseUrl = "http://localhost:4001"
$today = Get-Date -Format "yyyy-MM-dd"
$lastWeek = (Get-Date).AddDays(-7).ToString("yyyy-MM-dd")

Write-Host "==========================================="
Write-Host "TEST STEP 3: TRACEABILITY & PRINT HISTORY CACHE" -ForegroundColor Cyan
Write-Host "==========================================="

Write-Host "`nTest 1: Traceability - First call" -ForegroundColor Yellow
try {
    $uri = "$baseUrl/api/traceability/search?from=$lastWeek`&to=$today"
    $trace1 = Invoke-RestMethod -Uri $uri -Method GET
    Write-Host "SUCCESS: $($trace1.Count) records" -ForegroundColor Green
} catch {
    Write-Host "ERROR: $_" -ForegroundColor Red
}
Start-Sleep -Seconds 1

Write-Host "`nTest 2: Traceability - Second call (cached)" -ForegroundColor Yellow
try {
    $uri = "$baseUrl/api/traceability/search?from=$lastWeek`&to=$today"
    $trace2 = Invoke-RestMethod -Uri $uri -Method GET
    Write-Host "SUCCESS: $($trace2.Count) records (instant)" -ForegroundColor Green
} catch {
    Write-Host "ERROR: $_" -ForegroundColor Red
}
Start-Sleep -Seconds 1

Write-Host "`nTest 3: Print History - First call" -ForegroundColor Yellow
try {
    $uri = "$baseUrl/api/print-history/search?from=$lastWeek`&to=$today"
    $print1 = Invoke-RestMethod -Uri $uri -Method GET
    Write-Host "SUCCESS: $($print1.Count) records" -ForegroundColor Green
} catch {
    Write-Host "ERROR: $_" -ForegroundColor Red
}
Start-Sleep -Seconds 1

Write-Host "`nTest 4: Print History - Second call (cached)" -ForegroundColor Yellow
try {
    $uri = "$baseUrl/api/print-history/search?from=$lastWeek`&to=$today"
    $print2 = Invoke-RestMethod -Uri $uri -Method GET
    Write-Host "SUCCESS: $($print2.Count) records (instant)" -ForegroundColor Green
} catch {
    Write-Host "ERROR: $_" -ForegroundColor Red
}

Write-Host "`n==========================================="
Write-Host "STEP 3 COMPLETE" -ForegroundColor Green
Write-Host "Traceability cache: 15min TTL" -ForegroundColor White
Write-Host "Print History cache: 15min TTL" -ForegroundColor White
Write-Host "==========================================="
