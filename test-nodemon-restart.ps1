# test-nodemon-restart.ps1
# Tests that nodemon restarts work without EADDRINUSE errors

Write-Host "==========================================="
Write-Host "TESTING NODEMON RESTART" -ForegroundColor Cyan
Write-Host "==========================================="

Write-Host ""
Write-Host "MANUAL TEST INSTRUCTIONS:" -ForegroundColor Yellow
Write-Host ""
Write-Host "1. Run: npm run dev"
Write-Host "2. Wait for server to start"
Write-Host "3. Make a small change to any .ts file in src/"
Write-Host "4. Save the file"
Write-Host "5. Watch the terminal output"
Write-Host ""
Write-Host "EXPECTED BEHAVIOR:" -ForegroundColor Green
Write-Host "  - Server receives shutdown signal"
Write-Host "  - Graceful shutdown completes"
Write-Host "  - New server starts successfully"
Write-Host "  - NO EADDRINUSE error"
Write-Host ""
Write-Host "FAILURE INDICATOR:" -ForegroundColor Red
Write-Host "  - listen EADDRINUSE: address already in use"
Write-Host ""
Write-Host "FIXES APPLIED:" -ForegroundColor Cyan
Write-Host "  - Increased nodemon delay: 2500ms -> 3500ms"
Write-Host "  - Added 500ms port release delay in graceful shutdown"
Write-Host "  - Total buffer: 4000ms between restart cycles"
Write-Host ""
Write-Host "==========================================="
