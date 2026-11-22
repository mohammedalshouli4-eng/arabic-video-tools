# video-length.ps1 - stage 2 of the video pipeline: read the length of each listed video.
# Reads the newest <Out>\videos*.csv (from video-list.ps1). Paths and ffprobe come from config-lib.ps1.
# For each video in <Inbox> it runs ffprobe (read only) and gets
# the duration in seconds and whether it has audio. A failed ffprobe gives status=error.
# Default is a dry run: prints only. Add -Run to write lengths.csv in out
# (columns: file,duration_sec,has_audio,status). If lengths.csv exists, it writes
# lengths-yyyyMMdd-HHmmss.csv instead. Never overwrites.
# Never changes, moves or deletes a video. ASCII only, works on Windows PowerShell 5.1.
param(
    [switch]$Run
)
$ErrorActionPreference = 'Stop'
function Stop-Tool([string]$msg) { Write-Host "STOP: $msg" -ForegroundColor Red; exit 1 }

$cfgLib = Join-Path $PSScriptRoot 'config-lib.ps1'
if (-not (Test-Path -LiteralPath $cfgLib -PathType Leaf)) { Write-Host "STOP: helper file missing next to the script: $cfgLib" -ForegroundColor Red; exit 1 }
. $cfgLib
try { $cfg = Get-VideoConfig } catch { Write-Host $_.Exception.Message -ForegroundColor Red; exit 1 }
$inbox = $cfg.Inbox
$outDir = $cfg.Out
try { $ffprobe = Get-FfmpegTool 'ffprobe' $cfg } catch { Write-Host $_.Exception.Message -ForegroundColor Red; exit 1 }
$maxSec = 900
$culture = [System.Globalization.CultureInfo]::InvariantCulture

if (-not (Test-Path -LiteralPath $ffprobe -PathType Leaf)) { throw "ffprobe not found: $ffprobe" }
if (-not (Test-Path -LiteralPath $inbox -PathType Container)) { Stop-Tool "Inbox folder not found: $inbox. Make the folders first (README, section 5)." }
if (-not (Test-Path -LiteralPath $outDir -PathType Container)) { Stop-Tool "Out folder not found: $outDir. Make the folders first (README, section 5)." }

$listFile = Get-ChildItem -LiteralPath $outDir -File -Filter 'videos*.csv' | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if (-not $listFile) { Stop-Tool "No video list in $outDir yet. Run option 1 in the menu (or video-list.ps1 -Run) first." }
Write-Host "List: $($listFile.Name)"

# Runs ffprobe on one file and returns @{ ok; duration; audio }. Never throws.
function Get-VideoInfo([string]$path) {
    $result = @{ ok = $false; duration = ''; audio = '' }
    try {
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = $ffprobe
        $psi.Arguments = '-v error -show_entries format=duration:stream=codec_type -of json "' + $path + '"'
        $psi.UseShellExecute = $false
        $psi.CreateNoWindow = $true
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true
        $proc = [System.Diagnostics.Process]::Start($psi)
        $errTask = $proc.StandardError.ReadToEndAsync()
        $out = $proc.StandardOutput.ReadToEnd()
        if (-not $proc.WaitForExit(60000)) { $proc.Kill(); return $result }
        [void]$errTask.Result
        if ($proc.ExitCode -ne 0) { return $result }
        $json = $out | ConvertFrom-Json
        $dur = [string]$json.format.duration
        if ([string]::IsNullOrWhiteSpace($dur)) { return $result }
        $seconds = [double]::Parse($dur, $culture)
        $hasAudio = @($json.streams | Where-Object { $_.codec_type -eq 'audio' }).Count -gt 0
        $result.ok = $true
        $result.duration = ([math]::Round($seconds, 2)).ToString('0.00', $culture)
        $result.audio = $(if ($hasAudio) { 'yes' } else { 'no' })
        return $result
    }
    catch {
        return $result
    }
}

$lines = New-Object System.Collections.Generic.List[string]
$lines.Add('file,duration_sec,has_audio,status')

$ok = 0
$tooLong = 0
$errors = 0
$rejected = 0
$rows = @(Import-Csv -LiteralPath $listFile.FullName -Encoding UTF8)
foreach ($r in $rows) {
    $name = ([string]$r.file).Trim()
    $quoted = '"' + $name.Replace('"', '""') + '"'
    if ([string]::IsNullOrWhiteSpace($name) -or $name -match '[\\/:]' -or $name -match '\.\.') {
        Write-Host "REJECTED name not allowed: ${name}"
        $lines.Add($quoted + ',"","","rejected"'); $rejected++; continue
    }
    $src = Join-Path $inbox $name
    if (-not (Test-Path -LiteralPath $src -PathType Leaf)) {
        Write-Host "REJECTED not in inbox: ${name}"
        $lines.Add($quoted + ',"","","rejected"'); $rejected++; continue
    }
    $info = Get-VideoInfo $src
    if (-not $info.ok) {
        Write-Host "ERROR ffprobe could not read: ${name}" -ForegroundColor Yellow
        $lines.Add($quoted + ',"","","error"'); $errors++; continue
    }
    $status = 'ok'
    if ([double]::Parse($info.duration, $culture) -gt $maxSec) { $status = 'too_long'; $tooLong++ } else { $ok++ }
    Write-Host "${status}: ${name} ($($info.duration) sec, audio: $($info.audio))"
    $lines.Add($quoted + ',"' + $info.duration + '","' + $info.audio + '","' + $status + '"')
}
Write-Host "Done. OK: $ok  Too long: $tooLong  Error: $errors  Rejected: $rejected"

$lengthsPath = Join-Path $outDir 'lengths.csv'
if (Test-Path -LiteralPath $lengthsPath) {
    $lengthsPath = Join-Path $outDir ('lengths-{0}.csv' -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
}
if (Test-Path -LiteralPath $lengthsPath) {
    Write-Host "STOP: name already exists, nothing written: $lengthsPath" -ForegroundColor Red
    exit 1
}

if ($Run) {
    Set-Content -LiteralPath $lengthsPath -Value $lines.ToArray() -Encoding UTF8
    Write-Host "Lengths written: $lengthsPath" -ForegroundColor Green
}
else {
    Write-Host "Would write: $lengthsPath"
    Write-Host 'Dry run - nothing written.' -ForegroundColor Cyan
}
