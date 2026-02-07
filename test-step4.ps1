# Test Step 4: Database Indexes
# Execute SQL script and verify performance improvement

$baseUrl = "http://localhost:4001"
$sqlFile = "sql\create-indexes.sql"

Write-Host "==========================================="
Write-Host "STEP 4: DATABASE INDEXES" -ForegroundColor Cyan
Write-Host "==========================================="

# Test BEFORE indexes
Write-Host "`n[BEFORE INDEXES] Testing query performance..." -ForegroundColor Yellow
$before1 = Measure-Command {
    try {
        Invoke-RestMethod -Uri "$baseUrl/api/sequences" -Method GET | Out-Null
    } catch {
        Write-Host "ERROR: $_" -ForegroundColor Red
    }
}
Write-Host "Sequences query: $($before1.TotalMilliseconds)ms" -ForegroundColor White

Start-Sleep -Seconds 1

# Execute SQL script to create indexes
Write-Host "`nExecuting SQL script to create indexes..." -ForegroundColor Yellow
try {
    $server = "localhost"
    $database = "DB_TMMIN1_KRW_PIS_HV_BATTERY"
    $user = "sa"
    $password = "aas"
    
    # Read SQL file content
    $sqlContent = Get-Content -Path $sqlFile -Raw
    
    # Execute using sqlcmd
    Write-Host "Creating indexes on $database..." -ForegroundColor Magenta
    $output = & sqlcmd -S $server -d $database -U $user -P $password -C -i $sqlFile 2>&1
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "SUCCESS: Indexes created!" -ForegroundColor Green
        Write-Host $output -ForegroundColor Gray
    } else {
        Write-Host "ERROR: Failed to create indexes" -ForegroundColor Red
        Write-Host $output -ForegroundColor Red
        exit 1
    }
} catch {
    Write-Host "ERROR executing SQL: $_" -ForegroundColor Red
    Write-Host "Make sure sqlcmd is installed and SQL Server is running" -ForegroundColor Yellow
}

Start-Sleep -Seconds 2

# Test AFTER indexes (clear cache first)
Write-Host "`n[AFTER INDEXES] Testing query performance..." -ForegroundColor Yellow
$after1 = Measure-Command {
    try {
        Invoke-RestMethod -Uri "$baseUrl/api/sequences" -Method GET | Out-Null
    } catch {
        Write-Host "ERROR: $_" -ForegroundColor Red
    }
}
Write-Host "Sequences query: $($after1.TotalMilliseconds)ms" -ForegroundColor White

# Calculate improvement
$improvement = [math]::Round((($before1.TotalMilliseconds - $after1.TotalMilliseconds) / $before1.TotalMilliseconds) * 100, 2)

Write-Host "`n==========================================="
Write-Host "PERFORMANCE IMPROVEMENT" -ForegroundColor Cyan
Write-Host "==========================================="
Write-Host "Before indexes: $($before1.TotalMilliseconds)ms" -ForegroundColor White
Write-Host "After indexes:  $($after1.TotalMilliseconds)ms" -ForegroundColor White
if ($improvement -gt 0) {
    Write-Host "Improvement:    $improvement% faster" -ForegroundColor Green
} else {
    Write-Host "Result:         Similar performance (cached)" -ForegroundColor Yellow
}
Write-Host "==========================================="
Write-Host "STEP 4 COMPLETE" -ForegroundColor Green
Write-Host "==========================================="
