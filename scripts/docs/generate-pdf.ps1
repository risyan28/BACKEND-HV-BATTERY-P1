<# 
.SYNOPSIS
    Automatic PDF Generator using Microsoft Edge (headless)
.DESCRIPTION
    Converts HTML to PDF using Edge's built-in print-to-PDF functionality
#>

param(
    [string]$HtmlFile = "backend_runtime_maintenance_guide.html",
    [string]$OutputPdf = "backend_runtime_maintenance_guide.pdf"
)

Write-Host "Converting HTML to PDF using Microsoft Edge..." -ForegroundColor Cyan
Write-Host ""

# Get full paths
$htmlPath = Join-Path $PSScriptRoot $HtmlFile
$pdfPath = Join-Path $PSScriptRoot $OutputPdf

if (-not (Test-Path $htmlPath)) {
    Write-Host "HTML file not found: $htmlPath" -ForegroundColor Red
    exit 1
}

# Find Microsoft Edge executable
$edgePaths = @(
    "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe",
    "${env:ProgramFiles}\Microsoft\Edge\Application\msedge.exe",
    "${env:LOCALAPPDATA}\Microsoft\Edge\Application\msedge.exe"
)

$edgeExe = $null
foreach ($path in $edgePaths) {
    if (Test-Path $path) {
        $edgeExe = $path
        break
    }
}

if (-not $edgeExe) {
    Write-Host "Microsoft Edge not found!" -ForegroundColor Red
    Write-Host "Fallback: Open HTML in browser and use Ctrl+P to Save as PDF" -ForegroundColor Yellow
    exit 1
}

Write-Host "Found Edge: $edgeExe" -ForegroundColor Green

# Convert to PDF using Edge headless mode
try {
    $arguments = @(
        "--headless"
        "--disable-gpu"
        "--run-all-compositor-stages-before-draw"
        "--print-to-pdf=`"$pdfPath`""
        "`"$htmlPath`""
    )
    
    Write-Host "Converting..." -ForegroundColor Yellow
    
    & $edgeExe $arguments 2>$null
    
    # Wait for file to be created
    $timeout = 10
    $elapsed = 0
    while (-not (Test-Path $pdfPath) -and $elapsed -lt $timeout) {
        Start-Sleep -Milliseconds 500
        $elapsed++
    }
    
    if (Test-Path $pdfPath) {
        $fileSize = (Get-Item $pdfPath).Length
        $fileSizeKB = [math]::Round($fileSize / 1KB, 2)
        
        Write-Host ""
        Write-Host "PDF generated successfully!" -ForegroundColor Green
        Write-Host "File: $OutputPdf" -ForegroundColor Cyan
        Write-Host "Size: $fileSizeKB KB" -ForegroundColor Cyan
        Write-Host ""
    } else {
        Write-Host "PDF generation failed (timeout)" -ForegroundColor Red
        Write-Host "Manual fallback: Open HTML in browser, Ctrl+P" -ForegroundColor Yellow
    }
    
} catch {
    Write-Host "Error: $_" -ForegroundColor Red
    Write-Host "Manual fallback: Open HTML in browser, Ctrl+P" -ForegroundColor Yellow
}

