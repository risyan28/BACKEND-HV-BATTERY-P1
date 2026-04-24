# ============================================================
# compare-schema.ps1
# Compares local DB schema vs server DB schema
# Outputs: missing tables, missing columns, triggers & procs diff
# ============================================================

param(
    [string]$LocalServer  = "localhost,1433",
    [string]$RemoteServer = "192.168.250.2,1433",
    [string]$Database     = "DB_TMMIN1_KRW_PIS_HV_BATTERY",
    [string]$User         = "sa",
    [string]$Password     = "aas"
)

$ErrorActionPreference = "Stop"
$tmpDir = $env:TEMP

function Run-SqlcmdQuery {
    param($Server, $SqlFile, $Output)
    sqlcmd -S $Server -d $Database -U $User -P $Password -i $SqlFile -s "|" -W -h -1 -No 2>$null | Out-File $Output -Encoding UTF8
}

# ----------------------------------------------------------------
# 1. Column / Table schema
# ----------------------------------------------------------------
$colSql = @"
SELECT
    t.name AS tbl,
    c.name AS col,
    tp.name AS dtype,
    CASE tp.name
        WHEN 'nvarchar' THEN c.max_length / 2
        WHEN 'nchar'    THEN c.max_length / 2
        WHEN 'varchar'  THEN c.max_length
        WHEN 'char'     THEN c.max_length
        ELSE c.max_length
    END AS max_len,
    c.precision AS prec,
    c.scale,
    c.is_nullable
FROM sys.tables t
JOIN sys.columns c ON t.object_id = c.object_id
JOIN sys.types tp ON c.user_type_id = tp.user_type_id
WHERE t.is_ms_shipped = 0
ORDER BY t.name, c.column_id
"@
$colSql | Out-File "$tmpDir\__col_query.sql" -Encoding ASCII

Run-SqlcmdQuery -Server $LocalServer   -SqlFile "$tmpDir\__col_query.sql" -Output "$tmpDir\local_cols.txt"
Run-SqlcmdQuery -Server $RemoteServer  -SqlFile "$tmpDir\__col_query.sql" -Output "$tmpDir\server_cols.txt"

# ----------------------------------------------------------------
# 2. Parse into hashtables
# ----------------------------------------------------------------
function Parse-ColFile {
    param($Path)
    $ht = @{}
    Get-Content $Path | Where-Object { $_ -match '\|' } | ForEach-Object {
        $p = $_ -split '\|'
        if ($p.Count -ge 7) {
            $key = "$($p[0].Trim())|$($p[1].Trim())"
            $ht[$key] = [PSCustomObject]@{
                tbl      = $p[0].Trim()
                col      = $p[1].Trim()
                dtype    = $p[2].Trim()
                max_len  = $p[3].Trim()
                prec     = $p[4].Trim()
                scale    = $p[5].Trim()
                nullable = $p[6].Trim()
            }
        }
    }
    return $ht
}

$localCols  = Parse-ColFile "$tmpDir\local_cols.txt"
$serverCols = Parse-ColFile "$tmpDir\server_cols.txt"

Write-Host "Local: $($localCols.Count) columns | Server: $($serverCols.Count) columns"

# Missing tables
$localTables  = $localCols.Values  | Select-Object -ExpandProperty tbl -Unique | Sort-Object
$serverTables = $serverCols.Values | Select-Object -ExpandProperty tbl -Unique | Sort-Object
$missingTables = $localTables | Where-Object { $serverTables -notcontains $_ }
$extraTables   = $serverTables | Where-Object { $localTables -notcontains $_ }

# Missing columns
$missingCols = $localCols.Keys | Where-Object { -not $serverCols.ContainsKey($_) } | Sort-Object
$extraCols   = $serverCols.Keys | Where-Object { -not $localCols.ContainsKey($_) } | Sort-Object

Write-Host ""
Write-Host "=== TABLES IN LOCAL BUT MISSING ON SERVER ($($missingTables.Count)) ===" -ForegroundColor Red
$missingTables | ForEach-Object { Write-Host "  $_" }

Write-Host ""
Write-Host "=== COLUMNS MISSING ON SERVER ($($missingCols.Count)) ===" -ForegroundColor Red
$missingCols | ForEach-Object {
    $d = $localCols[$_]
    Write-Host "  [$($d.tbl)].$($d.col)  $($d.dtype)(len=$($d.max_len),p=$($d.prec),s=$($d.scale)) nullable=$($d.nullable)"
}

Write-Host ""
Write-Host "=== EXTRA COLS ON SERVER NOT IN LOCAL ($($extraCols.Count)) ===" -ForegroundColor Yellow
$extraCols | ForEach-Object {
    $d = $serverCols[$_]
    Write-Host "  [$($d.tbl)].$($d.col)  $($d.dtype)"
}

# ----------------------------------------------------------------
# 3. Triggers comparison
# ----------------------------------------------------------------
$trgSql = "SELECT name, OBJECT_NAME(parent_id) AS tbl FROM sys.triggers WHERE is_ms_shipped=0 AND parent_id > 0 ORDER BY name"
$trgSql | Out-File "$tmpDir\__trg_query.sql" -Encoding ASCII
Run-SqlcmdQuery -Server $LocalServer  -SqlFile "$tmpDir\__trg_query.sql" -Output "$tmpDir\local_trg.txt"
Run-SqlcmdQuery -Server $RemoteServer -SqlFile "$tmpDir\__trg_query.sql" -Output "$tmpDir\server_trg.txt"

$localTrg  = Get-Content "$tmpDir\local_trg.txt"  | Where-Object { $_ -match '\|' } | ForEach-Object { ($_ -split '\|')[0].Trim() }
$serverTrg = Get-Content "$tmpDir\server_trg.txt" | Where-Object { $_ -match '\|' } | ForEach-Object { ($_ -split '\|')[0].Trim() }

$missingTrg = $localTrg  | Where-Object { $serverTrg -notcontains $_ }
$extraTrg   = $serverTrg | Where-Object { $localTrg  -notcontains $_ }

Write-Host ""
Write-Host "=== TRIGGERS IN LOCAL BUT MISSING ON SERVER ($($missingTrg.Count)) ===" -ForegroundColor Red
$missingTrg | ForEach-Object { Write-Host "  $_" }
Write-Host "=== EXTRA TRIGGERS ON SERVER ($($extraTrg.Count)) ===" -ForegroundColor Yellow
$extraTrg | ForEach-Object { Write-Host "  $_" }

# ----------------------------------------------------------------
# 4. Stored Proc / Functions comparison
# ----------------------------------------------------------------
$procSql = "SELECT name, type_desc FROM sys.objects WHERE type IN ('P','FN','IF','TF') AND is_ms_shipped=0 ORDER BY name"
$procSql | Out-File "$tmpDir\__proc_query.sql" -Encoding ASCII
Run-SqlcmdQuery -Server $LocalServer  -SqlFile "$tmpDir\__proc_query.sql" -Output "$tmpDir\local_proc.txt"
Run-SqlcmdQuery -Server $RemoteServer -SqlFile "$tmpDir\__proc_query.sql" -Output "$tmpDir\server_proc.txt"

$localProc  = Get-Content "$tmpDir\local_proc.txt"  | Where-Object { $_ -match '\|' } | ForEach-Object { ($_ -split '\|')[0].Trim() }
$serverProc = Get-Content "$tmpDir\server_proc.txt" | Where-Object { $_ -match '\|' } | ForEach-Object { ($_ -split '\|')[0].Trim() }

$missingProc = $localProc  | Where-Object { $serverProc -notcontains $_ }
$extraProc   = $serverProc | Where-Object { $localProc  -notcontains $_ }

Write-Host ""
Write-Host "=== PROCS/FUNCTIONS IN LOCAL BUT MISSING ON SERVER ($($missingProc.Count)) ===" -ForegroundColor Red
$missingProc | ForEach-Object { Write-Host "  $_" }
Write-Host "=== EXTRA PROCS ON SERVER ($($extraProc.Count)) ===" -ForegroundColor Yellow
$extraProc | ForEach-Object { Write-Host "  $_" }

# ----------------------------------------------------------------
# 5. Get trigger definitions from local for those missing on server
# ----------------------------------------------------------------
Write-Host ""
Write-Host "=== Full trigger list (local) ===" -ForegroundColor Cyan
$localTrg | ForEach-Object { Write-Host "  $_" }
Write-Host ""
Write-Host "=== Full proc/function list (local) ===" -ForegroundColor Cyan
$localProc | ForEach-Object { Write-Host "  $_" }
