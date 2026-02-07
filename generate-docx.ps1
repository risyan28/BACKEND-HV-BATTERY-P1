<# 
.SYNOPSIS
    Automatic DOCX Generator using Microsoft Word COM Automation
.DESCRIPTION
    Converts MHTML to DOCX using Microsoft Word
#>

param(
    [string]$MhtmlFile = "backend_runtime_maintenance_guide.mhtml",
    [string]$OutputDocx = "backend_runtime_maintenance_guide.docx"
)

Write-Host "Converting MHTML to DOCX using Microsoft Word..." -ForegroundColor Cyan
Write-Host ""

# Get full paths
$mhtmlPath = Join-Path $PSScriptRoot $MhtmlFile
$docxPath = Join-Path $PSScriptRoot $OutputDocx

if (-not (Test-Path $mhtmlPath)) {
    Write-Host "MHTML file not found: $mhtmlPath" -ForegroundColor Red
    exit 1
}

# Check if Word is installed
try {
    $word = New-Object -ComObject Word.Application
} catch {
    Write-Host "Microsoft Word not found!" -ForegroundColor Red
    Write-Host "Manual fallback: Open .mhtml file in Word and Save As .docx" -ForegroundColor Yellow
    exit 1
}

try {
    Write-Host "Found Microsoft Word" -ForegroundColor Green
    Write-Host "Converting..." -ForegroundColor Yellow
    
    # Make Word invisible
    $word.Visible = $false
    
    # Open MHTML file
    $doc = $word.Documents.Open($mhtmlPath)
    
    # Save as DOCX format (16 = wdFormatXMLDocument)
    $wdFormatDocx = 16
    $doc.SaveAs2($docxPath, $wdFormatDocx)
    
    # Close document
    $doc.Close()
    
    # Quit Word
    $word.Quit()
    
    # Release COM objects
    [System.Runtime.Interopservices.Marshal]::ReleaseComObject($doc) | Out-Null
    [System.Runtime.Interopservices.Marshal]::ReleaseComObject($word) | Out-Null
    [System.GC]::Collect()
    [System.GC]::WaitForPendingFinalizers()
    
    if (Test-Path $docxPath) {
        $fileSize = (Get-Item $docxPath).Length
        $fileSizeKB = [math]::Round($fileSize / 1KB, 2)
        
        Write-Host ""
        Write-Host "DOCX generated successfully!" -ForegroundColor Green
        Write-Host "File: $OutputDocx" -ForegroundColor Cyan
        Write-Host "Size: $fileSizeKB KB" -ForegroundColor Cyan
        Write-Host ""
    } else {
        Write-Host "DOCX generation failed" -ForegroundColor Red
    }
    
} catch {
    Write-Host "Error: $_" -ForegroundColor Red
    Write-Host "Manual fallback: Open .mhtml file in Word and Save As .docx" -ForegroundColor Yellow
    
    # Cleanup on error
    if ($word) {
        $word.Quit()
        [System.Runtime.Interopservices.Marshal]::ReleaseComObject($word) | Out-Null
    }
}
