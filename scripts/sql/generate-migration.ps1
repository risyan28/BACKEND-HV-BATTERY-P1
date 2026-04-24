# ============================================================
# generate-migration.ps1
# Reads current local DB definitions and generates a safe
# migration script to apply on the server.
# Object list is auto-discovered from local DB — no hardcoding needed.
# Usage:
#   .\generate-migration.ps1
#   .\generate-migration.ps1 -LocalServer "srv1,1433" -RemoteServer "srv2,1433" -Database "MyDB" -User "sa" -Password "pass"
# ============================================================
param(
    [string]$LocalServer  = "localhost,1433",
    [string]$RemoteServer = "192.168.250.2,1433",
    [string]$Database     = "DB_TMMIN1_KRW_PIS_HV_BATTERY",
    [string]$User         = "sa",
    [string]$Password     = "aas"
)

$outFile = Join-Path $PSScriptRoot ("migrate-to-server-" + (Get-Date -Format 'yyyy-MM-dd') + ".sql")

# System diagram objects to always exclude
$excludeNames = @(
    'fn_diagramobjects','sp_alterdiagram','sp_creatediagram',
    'sp_dropdiagram','sp_helpdiagramdefinition','sp_helpdiagrams',
    'sp_renamediagram','sp_upgraddiagrams'
)

function Invoke-SqlFile {
    param($Server, $Query)
    $f = "$env:TEMP\__genmig_q.sql"
    $Query | Out-File $f -Encoding ASCII
    $result = sqlcmd -S $Server -d $Database -U $User -P $Password -i $f -s "|" -y 0 -No 2>$null
    Remove-Item $f -ErrorAction SilentlyContinue
    return $result
}

function Get-ObjDef {
    param($ObjName)
    $q = "SET NOCOUNT ON; SELECT OBJECT_DEFINITION(OBJECT_ID('dbo.$ObjName'))"
    $f = "$env:TEMP\__genmig_def.sql"
    $q | Out-File $f -Encoding ASCII
    $raw = (sqlcmd -S $LocalServer -d $Database -U $User -P $Password -i $f -y 0 -No 2>$null) -join "`n"
    Remove-Item $f -ErrorAction SilentlyContinue
    return $raw.Trim()
}

function Convert-ToCreateOrAlter {
    param([string]$def)
    $def = $def -replace '(?i)CREATE\s+(PROCEDURE|PROC)\b', 'CREATE OR ALTER PROCEDURE'
    $def = $def -replace '(?i)CREATE\s+TRIGGER\b',          'CREATE OR ALTER TRIGGER'
    $def = $def -replace '(?i)CREATE\s+FUNCTION\b',         'CREATE OR ALTER FUNCTION'
    return $def
}

# ----------------------------------------------------------------
# Auto-discover: get all objects from local, compare with server
# ----------------------------------------------------------------
$listQuery = "SELECT name, type FROM sys.objects WHERE type IN ('P','FN','IF','TF','TR') AND is_ms_shipped = 0 ORDER BY type, name"

$localLines  = Invoke-SqlFile -Server $LocalServer  -Query $listQuery
$serverLines = Invoke-SqlFile -Server $RemoteServer -Query $listQuery

function Parse-ObjList {
    param($Lines)
    $Lines | Where-Object { $_ -match '\|' } | ForEach-Object {
        $parts = $_ -split '\|'
        [PSCustomObject]@{ name = $parts[0].Trim(); type = $parts[1].Trim() }
    } | Where-Object { $excludeNames -notcontains $_.name }
}

$localObjs  = Parse-ObjList $localLines
$serverObjs = Parse-ObjList $serverLines
$serverNames = $serverObjs | Select-Object -ExpandProperty name

# Separate by type for ordered output
$funcList = ($localObjs | Where-Object { $_.type -in @('FN','IF','TF') }).name
$procList = ($localObjs | Where-Object { $_.type -eq 'P' }).name
$trigList = ($localObjs | Where-Object { $_.type -eq 'TR' }).name

Write-Host "Auto-discovered objects:" -ForegroundColor Cyan
Write-Host "  Functions  ($($funcList.Count)): $($funcList -join ', ')"
Write-Host "  Procedures ($($procList.Count)): $($procList -join ', ')"
Write-Host "  Triggers   ($($trigList.Count)): $($trigList -join ', ')"
Write-Host ""

# ----------------------------------------------------------------
# Build migration SQL
# ----------------------------------------------------------------
$sb = [System.Text.StringBuilder]::new()

$null = $sb.AppendLine("-- ============================================================")
$null = $sb.AppendLine("-- MIGRATION SCRIPT: LOCAL -> SERVER ($RemoteServer)")
$null = $sb.AppendLine("-- Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm')")
$null = $sb.AppendLine("-- DB: $Database")
$null = $sb.AppendLine("-- !! DATA IS NEVER MODIFIED. Safe to run multiple times. !!")
$null = $sb.AppendLine("-- ============================================================")
$null = $sb.AppendLine("")
$null = $sb.AppendLine("USE [$Database];")
$null = $sb.AppendLine("GO")
$null = $sb.AppendLine("SET NOCOUNT ON;")
$null = $sb.AppendLine("GO")
$null = $sb.AppendLine("")

foreach ($section in @(
    @{ label = "STEP 1: Functions";           list = $funcList },
    @{ label = "STEP 2: Stored Procedures";   list = $procList },
    @{ label = "STEP 3: Triggers";            list = $trigList }
)) {
    if ($section.list.Count -eq 0) { continue }
    $null = $sb.AppendLine("PRINT '=== $($section.label) ==='")
    $null = $sb.AppendLine("GO")
    foreach ($obj in $section.list) {
        $null = $sb.AppendLine("-- $obj")
        $def = Get-ObjDef $obj
        $def = Convert-ToCreateOrAlter $def
        $null = $sb.AppendLine($def)
        $null = $sb.AppendLine("GO")
        $null = $sb.AppendLine("PRINT '+ $obj : created/updated';")
        $null = $sb.AppendLine("GO")
        $null = $sb.AppendLine("")
    }
}

$null = $sb.AppendLine("PRINT '=============================='")
$null = $sb.AppendLine("PRINT 'MIGRATION COMPLETED SUCCESSFULLY'")
$null = $sb.AppendLine("PRINT '=============================='")
$null = $sb.AppendLine("GO")

$sb.ToString() | Out-File $outFile -Encoding UTF8
Write-Host "Migration script saved: $outFile" -ForegroundColor Green
