# ================================
# Phase 1 - Comprehensive Testing Script
# ================================

Write-Host "`n>>> STARTING PHASE 1 COMPREHENSIVE TESTING`n" -ForegroundColor Cyan

$baseUrl = "http://localhost:4001"
$testResults = @()

function Test-Endpoint {
    param(
        [string]$Name,
        [string]$Method = "GET",
        [string]$Url,
        [object]$Body = $null,
        [int]$ExpectedStatus = 200
    )
    
    Write-Host "`n========================================" -ForegroundColor Gray
    Write-Host "TEST: $Name" -ForegroundColor Yellow
    Write-Host "========================================`n" -ForegroundColor Gray
    
    try {
        $params = @{
            Uri = $Url
            Method = $Method
            ContentType = "application/json"
            UseBasicParsing = $true
        }
        
        if ($Body) {
            $params.Body = ($Body | ConvertTo-Json)
        }
        
        $startTime = Get-Date
        $response = Invoke-RestMethod @params
        $endTime = Get-Date
        $duration = ($endTime - $startTime).TotalMilliseconds
        
        Write-Host "✅ PASS" -ForegroundColor Green
        Write-Host "   Status: 200 OK" -ForegroundColor Gray
        Write-Host "   Response Time: $([math]::Round($duration, 2))ms" -ForegroundColor Gray
        Write-Host "   Response:" -ForegroundColor Gray
        Write-Host ($response | ConvertTo-Json -Depth 5) -ForegroundColor White
        
        $testResults += @{
            Test = $Name
            Status = "PASS"
            Duration = $duration
        }
        
        return $response
        
    } catch {
        $statusCode = $_.Exception.Response.StatusCode.value__
        
        if ($statusCode -eq $ExpectedStatus) {
            Write-Host "✅ PASS (Expected Error)" -ForegroundColor Green
            Write-Host "   Status: $statusCode" -ForegroundColor Gray
            
            try {
                $reader = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream())
                $errorBody = $reader.ReadToEnd()
                Write-Host "   Error Response:" -ForegroundColor Gray
                Write-Host $errorBody -ForegroundColor White
            } catch {}
            
            $testResults += @{
                Test = $Name
                Status = "PASS (Expected Error)"
                Duration = 0
            }
        } else {
            Write-Host "❌ FAIL" -ForegroundColor Red
            Write-Host "   Error: $_" -ForegroundColor Red
            
            $testResults += @{
                Test = $Name
                Status = "FAIL"
                Duration = 0
            }
        }
    }
}

# ================================
# TEST 1: Basic Health Check
# ================================
Test-Endpoint -Name "Health Check (Basic)" `
    -Url "$baseUrl/api/health"

# ================================
# TEST 2: Detailed Health Check
# ================================
Test-Endpoint -Name "Health Check (Detailed)" `
    -Url "$baseUrl/api/health/detailed"

# ================================
# TEST 3: Get Sequences (Main Functionality)
# ================================
Test-Endpoint -Name "Get All Sequences" `
    -Url "$baseUrl/api/sequences"

# ================================
# TEST 4: Validation - Missing Required Fields
# ================================
Test-Endpoint -Name "Create Sequence (Invalid - Missing Fields)" `
    -Method "POST" `
    -Url "$baseUrl/api/sequences" `
    -Body @{} `
    -ExpectedStatus 400

# ================================
# TEST 5: Validation - Empty String
# ================================
Test-Endpoint -Name "Create Sequence (Invalid - Empty String)" `
    -Method "POST" `
    -Url "$baseUrl/api/sequences" `
    -Body @{
        FTYPE_BATTERY = ""
        FMODEL_BATTERY = ""
    } `
    -ExpectedStatus 400

# ================================
# TEST 6: Validation - Too Long String
# ================================
Test-Endpoint -Name "Create Sequence (Invalid - String Too Long)" `
    -Method "POST" `
    -Url "$baseUrl/api/sequences" `
    -Body @{
        FTYPE_BATTERY = "ABCDEFGHIJK" # > 10 chars
        FMODEL_BATTERY = "ABCDEFGHIJK12345678901" # > 20 chars
    } `
    -ExpectedStatus 400

# ================================
# TEST 7: Traceability - Invalid Date Format
# ================================
Test-Endpoint -Name "Traceability (Invalid - Wrong Date Format)" `
    -Url "$baseUrl/api/traceability/search?from=2024-1-1&to=2024-12-31" `
    -ExpectedStatus 400

# ================================
# TEST 8: Traceability - Valid Date Range
# ================================
Test-Endpoint -Name "Traceability (Valid Date Range)" `
    -Url "$baseUrl/api/traceability/search?from=2024-01-01&to=2024-01-31"

# ================================
# TEST 9: Print History
# ================================
Test-Endpoint -Name "Get Print History (Valid Date Range)" `
    -Url "$baseUrl/api/print-history/search?from=2024-01-01&to=2024-01-31"

# ================================
# SUMMARY
# ================================
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host ">>> TEST SUMMARY" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

$totalTests = $testResults.Count
$passedTests = ($testResults | Where-Object { $_.Status -like "PASS*" }).Count
$failedTests = $totalTests - $passedTests

Write-Host "Total Tests:  $totalTests" -ForegroundColor White
Write-Host "Passed:       $passedTests" -ForegroundColor Green
Write-Host "Failed:       $failedTests" -ForegroundColor $(if ($failedTests -eq 0) { "Green" } else { "Red" })
Write-Host "`n"

if ($failedTests -eq 0) {
    Write-Host ">>> ALL TESTS PASSED! Phase 1 is working perfectly!" -ForegroundColor Green
} else {
    Write-Host ">>> Some tests failed. Please review the output above." -ForegroundColor Yellow
}

Write-Host "`n========================================`n" -ForegroundColor Cyan
