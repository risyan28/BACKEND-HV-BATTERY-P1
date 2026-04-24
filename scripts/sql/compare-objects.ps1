# ============================================================
# compare-objects.ps1
# Compares trigger / SP / function definitions local vs server
# Object list is auto-discovered from local DB — no hardcoding needed.
# Usage:
#   .\compare-objects.ps1
#   .\compare-objects.ps1 -LocalServer "srv1,1433" -RemoteServer "srv2,1433" -Database "MyDB" -User "sa" -Password "pass"
# ============================================================
param(
    [string]$LocalServer  = "localhost,1433",
    [string]$RemoteServer = "192.168.250.2,1433",
    [string]$Database     = "DB_TMMIN1_KRW_PIS_HV_BATTERY",
    [string]$User         = "sa",
    [string]$Password     = "aas"
)
$ErrorActionPreference = "SilentlyContinue"

# System diagram SPs to always exclude
$excludeNames = @(
    'fn_diagramobjects','sp_alterdiagram','sp_creatediagram',
    'sp_dropdiagram','sp_helpdiagramdefinition','sp_helpdiagrams',
    'sp_renamediagram','sp_upgraddiagrams'
)

function Invoke-Sqlcmd-Query {
    param($Server, $Query)
    $f = "$env:TEMP\__cmp_query.sql"
    $Query | Out-File $f -Encoding ASCII
    $result = sqlcmd -S $Server -d $Database -U $User -P $Password -i $f -s "|" -y 0 -No 2>$null
    Remove-Item $f -ErrorAction SilentlyContinue
    return $result
}

function Get-ObjDef {
    param($Server, $ObjName)
    $q = "SET NOCOUNT ON; SELECT OBJECT_DEFINITION(OBJECT_ID('dbo.$ObjName'))"
    $f = "$env:TEMP\__objdef.sql"
    $q | Out-File $f -Encoding ASCII
    $result = sqlcmd -S $Server -d $Database -U $User -P $Password -i $f -s "|" -y 0 -No 2>$null
    Remove-Item $f -ErrorAction SilentlyContinue
    return ($result -join "`n").Trim()
}

# ----------------------------------------------------------------
# Auto-discover all user objects from LOCAL DB
# ----------------------------------------------------------------
$listQuery = "SELECT name FROM sys.objects WHERE type IN ('P','FN','IF','TF','TR') AND is_ms_shipped = 0 ORDER BY name"
$localObjLines  = Invoke-Sqlcmd-Query -Server $LocalServer  -Query $listQuery
$serverObjLines = Invoke-Sqlcmd-Query -Server $RemoteServer -Query $listQuery

$localObjects  = $localObjLines  | Where-Object { $_.Trim() -ne '' -and $_ -notmatch '^name' -and $_ -notmatch '^---' -and $_ -notmatch 'rows affected' } | ForEach-Object { $_.Trim() } | Where-Object { $excludeNames -notcontains $_ }
$serverObjects = $serverObjLines | Where-Object { $_.Trim() -ne '' -and $_ -notmatch '^name' -and $_ -notmatch '^---' -and $_ -notmatch 'rows affected' } | ForEach-Object { $_.Trim() } | Where-Object { $excludeNames -notcontains $_ }

Write-Host "Local objects  : $($localObjects.Count)" -ForegroundColor Cyan
Write-Host "Server objects : $($serverObjects.Count)" -ForegroundColor Cyan
Write-Host ""

$diffs   = @()
$missing = @()
$onlyOnServer = @()

# Objects on server but not in local
$onlyOnServer = $serverObjects | Where-Object { $localObjects -notcontains $_ }

# Compare all local objects
foreach ($obj in $localObjects) {
    $ld = Get-ObjDef -Server $LocalServer  -ObjName $obj
    $sd = Get-ObjDef -Server $RemoteServer -ObjName $obj

    if ([string]::IsNullOrWhiteSpace($sd) -or $sd -eq 'NULL') {
        $missing += $obj
        Write-Host "MISSING: $obj" -ForegroundColor Red
    } elseif ($ld -ne $sd) {
        $diffs += $obj
        Write-Host "DIFFERS: $obj" -ForegroundColor Yellow
    } else {
        Write-Host "    OK : $obj" -ForegroundColor Green
    }
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Missing on server  : $(if ($missing.Count) { $missing -join ', ' } else { '(none)' })"
Write-Host "Different content  : $(if ($diffs.Count)   { $diffs   -join ', ' } else { '(none)' })"
Write-Host "Only on server     : $(if ($onlyOnServer.Count) { $onlyOnServer -join ', ' } else { '(none)' })"
Write-Host "========================================" -ForegroundColor Cyan
