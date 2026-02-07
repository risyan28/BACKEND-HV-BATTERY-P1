# Test Step 5: Pagination
# Test pagination parameters for traceability and print history

$baseUrl = "http://localhost:4001"
$today = Get-Date -Format "yyyy-MM-dd"
$lastWeek = (Get-Date).AddDays(-7).ToString("yyyy-MM-dd")

Write-Host "==========================================="
Write-Host "STEP 5: PAGINATION TESTING" -ForegroundColor Cyan
Write-Host "==========================================="

Write-Host "`nTest 1: Traceability - Default pagination" -ForegroundColor Yellow
try {
    $uri = "$baseUrl/api/traceability/search?from=$lastWeek`&to=$today"
    $data1 = Invoke-RestMethod -Uri $uri -Method GET
    Write-Host "SUCCESS: $($data1.Count) records (default: page=1, limit=1000)" -ForegroundColor Green
} catch {
    Write-Host "ERROR: $_" -ForegroundColor Red
}

Write-Host "`nTest 2: Traceability - Custom pagination (page=1, limit=5)" -ForegroundColor Yellow
try {
    $uri = "$baseUrl/api/traceability/search?from=$lastWeek`&to=$today`&page=1`&limit=5"
    $data2 = Invoke-RestMethod -Uri $uri -Method GET
    Write-Host "SUCCESS: $($data2.Count) records (should be max 5)" -ForegroundColor Green
} catch {
    Write-Host "ERROR: $_" -ForegroundColor Red
}

Write-Host "`nTest 3: Print History - Default pagination" -ForegroundColor Yellow
try {
    $uri = "$baseUrl/api/print-history/search?from=$lastWeek`&to=$today"
    $data3 = Invoke-RestMethod -Uri $uri -Method GET
    Write-Host "SUCCESS: $($data3.Count) records (default: page=1, limit=100)" -ForegroundColor Green
} catch {
    Write-Host "ERROR: $_" -ForegroundColor Red
}

Write-Host "`nTest 4: Print History - Custom pagination (page=1, limit=3)" -ForegroundColor Yellow
try {
    $uri = "$baseUrl/api/print-history/search?from=$lastWeek`&to=$today`&page=1`&limit=3"
    $data4 = Invoke-RestMethod -Uri $uri -Method GET
    Write-Host "SUCCESS: $($data4.Count) records (should be max 3)" -ForegroundColor Green
} catch {
    Write-Host "ERROR: $_" -ForegroundColor Red
}

Write-Host "`nTest 5: Sequences - Still working without pagination" -ForegroundColor Yellow
try {
    $uri = "$baseUrl/api/sequences"
    $data5 = Invoke-RestMethod -Uri $uri -Method GET
    Write-Host "SUCCESS: queue=$($data5.queue.Count), completed=$($data5.completed.Count), parked=$($data5.parked.Count)" -ForegroundColor Green
} catch {
    Write-Host "ERROR: $_" -ForegroundColor Red
}

Write-Host "`n==========================================="
Write-Host "STEP 5 COMPLETE" -ForegroundColor Green
Write-Host "Pagination limits:" -ForegroundColor White
Write-Host "  - Traceability: max 10,000 per page" -ForegroundColor White
Write-Host "  - Print History: max 10,000 per page" -ForegroundColor White
Write-Host "  - Sequences: No pagination (uses QUERY_LIMITS)" -ForegroundColor White
Write-Host "==========================================="
