# video-run.ps1 - runs the five stages of the video pipeline one after the other:
# video-list, video-length, video-audio, video-text, video-handoff (all next to this script).
# With -Run each stage runs with -Run. After each stage it checks: no error thrown, exit code 0,
# and a new output file (written after the stage started) with at least one good row.
# If a check fails it stops right there and says which stage and why. Rows with other
# statuses (error, too_long, skipped ...) do not stop it: they are counted in the summary.
# Without -Run it only checks the tools and folders and runs video-list as a dry run, because
# stages 2 to 5 read the newest lists in out and a dry run would show old lists.
# Never moves a video to done: the user does that by hand after checking the handoff file.
# Writes nothing itself: only the stages write. ASCII only, works on Windows PowerShell 5.1.
param(
    [switch]$Run
)
$ErrorActionPreference = 'Stop'

# Paths, ffmpeg, ffprobe and the model come from config-lib.ps1 (next to this script).
$cfgLib = Join-Path $PSScriptRoot 'config-lib.ps1'
if (-not (Test-Path -LiteralPath $cfgLib -PathType Leaf)) { Write-Host "STOP: helper file missing next to the script: $cfgLib" -ForegroundColor Red; exit 1 }
. $cfgLib
try { $cfg = Get-VideoConfig } catch { Write-Host $_.Exception.Message -ForegroundColor Red; exit 1 }
$outDir = $cfg.Out
try { $ffmpeg = Get-FfmpegTool 'ffmpeg' $cfg; $ffprobe = Get-FfmpegTool 'ffprobe' $cfg } catch { Write-Host $_.Exception.Message -ForegroundColor Red; exit 1 }
$model = $cfg.WhisperModel
# good = the statuses that count as a good row. Empty = any row is good. $null = not a csv.
$stages = @(
    [pscustomobject]@{ n = 1; name = 'list'; script = 'video-list.ps1'; filter = 'videos*.csv'; good = @() },
    [pscustomobject]@{ n = 2; name = 'length'; script = 'video-length.ps1'; filter = 'lengths*.csv'; good = @('ok') },
    [pscustomobject]@{ n = 3; name = 'audio'; script = 'video-audio.ps1'; filter = 'audio*.csv'; good = @('ok', 'exists') },
    [pscustomobject]@{ n = 4; name = 'text'; script = 'video-text.ps1'; filter = 'text*.csv'; good = @('ok', 'exists') },
    [pscustomobject]@{ n = 5; name = 'handoff'; script = 'video-handoff.ps1'; filter = 'handoff-*.md'; good = $null }
)

$missing = @()
foreach ($s in $stages) { $p = Join-Path $PSScriptRoot $s.script; if (-not (Test-Path -LiteralPath $p -PathType Leaf)) { $missing += $p } }
foreach ($f in @($ffmpeg, $ffprobe, $model)) { if (-not (Test-Path -LiteralPath $f -PathType Leaf)) { $missing += $f } }
foreach ($d in @($cfg.Inbox, $cfg.Work, $outDir)) { if (-not (Test-Path -LiteralPath $d -PathType Container)) { $missing += $d } }
if ($missing.Count -gt 0) { foreach ($m in $missing) { Write-Host "STOP: missing $m" -ForegroundColor Red }; exit 1 }
Write-Host 'Check: the five scripts, ffmpeg, ffprobe, the model and the folders are found.'

# Runs one stage in this PowerShell. Returns '' if it ended well, or the reason it failed.
function Invoke-Stage($s, [bool]$withRun) {
    $path = Join-Path $PSScriptRoot $s.script
    $global:LASTEXITCODE = 0
    try {
        if ($withRun) { & $path -Run | Out-Host } else { & $path | Out-Host }
    }
    catch {
        return 'error: ' + $_.Exception.Message
    }
    if ($LASTEXITCODE -ne 0) { return 'the stage stopped (exit code ' + $LASTEXITCODE + ')' }
    return ''
}

# The newest output file of a stage, only if it was written after $since. $null otherwise.
function Get-NewOutput($s, [datetime]$since) {
    $f = Get-ChildItem -LiteralPath $outDir -File -Filter $s.filter | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if ($f -and $f.LastWriteTime -ge $since) { return $f }
    return $null
}

if (-not $Run) {
    Write-Host ''
    Write-Host 'Stage 1 list (dry run):' -ForegroundColor Cyan
    $why = Invoke-Stage $stages[0] $false
    if ($why) { Write-Host "STOP at Stage 1 list: $why" -ForegroundColor Red; exit 1 }
    Write-Host 'Stages 2 to 5 run only with -Run: each one reads the list the stage before it writes.'
    exit 0
}

$summary = New-Object System.Collections.Generic.List[string]
$handoff = ''
$failed = $false
foreach ($s in $stages) {
    $label = 'Stage ' + $s.n + ' ' + $s.name
    if ($failed) { $summary.Add($label + ': not run'); continue }
    Write-Host ''
    Write-Host "${label}:" -ForegroundColor Cyan
    $since = Get-Date
    $why = Invoke-Stage $s $true
    $file = $null
    $note = ''
    if (-not $why) {
        $file = Get-NewOutput $s $since
        if (-not $file) { $why = 'no new ' + $s.filter + ' in ' + $outDir }
    }
    if (-not $why -and $null -ne $s.good) {
        $rows = @(Import-Csv -LiteralPath $file.FullName -Encoding UTF8)
        $other = @()
        if ($s.good.Count -eq 0) { $goodRows = $rows.Count }
        else {
            $goodRows = @($rows | Where-Object { $s.good -contains [string]$_.status }).Count
            $other = @($rows | Where-Object { $s.good -notcontains [string]$_.status } | Group-Object status | ForEach-Object { $_.Name + ' ' + $_.Count })
        }
        if ($goodRows -eq 0) { $why = 'no good row in ' + $file.Name }
        $note = '  good: ' + $goodRows
        if ($other.Count -gt 0) { $note += '  other: ' + ($other -join ', ') }
    }
    if ($why) {
        Write-Host "STOP at ${label}: $why" -ForegroundColor Red
        $summary.Add($label + ': FAILED - ' + $why)
        $failed = $true
        continue
    }
    $summary.Add($label + ': OK  ' + $file.Name + $note)
    if ($s.name -eq 'handoff') { $handoff = $file.FullName }
}

Write-Host ''
Write-Host 'Summary:' -ForegroundColor Cyan
foreach ($l in $summary) { Write-Host "  $l" }
if ($handoff) {
    Write-Host "Handoff: $handoff" -ForegroundColor Green
    Write-Host 'Check it, then move the videos from inbox to done by hand.'
}
if ($failed) { exit 1 }
