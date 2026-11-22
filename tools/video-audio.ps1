# video-audio.ps1 - stage 3 of the video pipeline: pull the audio out of each good video.
# Reads the newest <Out>\lengths*.csv (from video-length.ps1). Paths and ffmpeg come from config-lib.ps1.
# Works only on rows with status=ok and has_audio=yes. Every other row is a SKIP.
# For each video in <Inbox> it writes <Work>\<video name>.wav
# (16000 Hz, mono, pcm_s16le, no video): the format whisper needs.
# ffmpeg writes to <video name>.wav.part first and the script renames it only on success.
# Default is a dry run: prints only. Add -Run to write the wav files and audio.csv in out
# (columns: file,wav,status). If audio.csv exists, it writes audio-yyyyMMdd-HHmmss.csv instead.
# Never overwrites. Never changes, moves or deletes a video. Writes only in work and out.
# ASCII only, works on Windows PowerShell 5.1.
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
$workDir = $cfg.Work
$outDir = $cfg.Out
try { $ffmpeg = Get-FfmpegTool 'ffmpeg' $cfg } catch { Write-Host $_.Exception.Message -ForegroundColor Red; exit 1 }
$timeoutMs = 600000

if (-not (Test-Path -LiteralPath $ffmpeg -PathType Leaf)) { throw "ffmpeg not found: $ffmpeg" }
foreach ($d in @($inbox, $workDir, $outDir)) {
    if (-not (Test-Path -LiteralPath $d -PathType Container)) { Stop-Tool "Folder not found: $d. Make the folders first (README, section 5)." }
}

$listFile = Get-ChildItem -LiteralPath $outDir -File -Filter 'lengths*.csv' | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if (-not $listFile) { Stop-Tool "No lengths list in $outDir yet. Run option 1 in the menu (or video-length.ps1 -Run) first." }
Write-Host "List: $($listFile.Name)"

# Runs ffmpeg for one file. Returns $true only if ffmpeg exited with 0 in time. Never throws.
function Invoke-AudioExtract([string]$src, [string]$dest) {
    try {
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = $ffmpeg
        $psi.Arguments = '-hide_banner -nostdin -n -v error -i "' + $src + '" -vn -ac 1 -ar 16000 -c:a pcm_s16le -f wav "' + $dest + '"'
        $psi.UseShellExecute = $false
        $psi.CreateNoWindow = $true
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true
        $proc = [System.Diagnostics.Process]::Start($psi)
        $errTask = $proc.StandardError.ReadToEndAsync()
        [void]$proc.StandardOutput.ReadToEnd()
        if (-not $proc.WaitForExit($timeoutMs)) { $proc.Kill(); return $false }
        [void]$errTask.Result
        return ($proc.ExitCode -eq 0)
    }
    catch {
        return $false
    }
}

$lines = New-Object System.Collections.Generic.List[string]
$lines.Add('file,wav,status')

$done = 0
$exists = 0
$errors = 0
$skipped = 0
$rows = @(Import-Csv -LiteralPath $listFile.FullName -Encoding UTF8)
foreach ($r in $rows) {
    $name = ([string]$r.file).Trim()
    $quoted = '"' + $name.Replace('"', '""') + '"'
    if ([string]::IsNullOrWhiteSpace($name) -or $name -match '[\\/:]' -or $name -match '\.\.') {
        Write-Host "SKIP name not allowed: ${name}"
        $lines.Add($quoted + ',"","rejected"'); $skipped++; continue
    }
    if ([string]$r.status -ne 'ok') {
        Write-Host "SKIP status $($r.status): ${name}"
        $lines.Add($quoted + ',"","skipped"'); $skipped++; continue
    }
    if ([string]$r.has_audio -ne 'yes') {
        Write-Host "SKIP no audio: ${name}"
        $lines.Add($quoted + ',"","skipped"'); $skipped++; continue
    }
    $src = Join-Path $inbox $name
    if (-not (Test-Path -LiteralPath $src -PathType Leaf)) {
        Write-Host "SKIP not in inbox: ${name}"
        $lines.Add($quoted + ',"","rejected"'); $skipped++; continue
    }
    $wavName = $name + '.wav'
    $wav = Join-Path $workDir $wavName
    $part = $wav + '.part'
    $wavQuoted = '"' + $wavName.Replace('"', '""') + '"'
    if (Test-Path -LiteralPath $wav) {
        Write-Host "SKIP exists: ${wavName}"
        $lines.Add($quoted + ',' + $wavQuoted + ',"exists"'); $exists++; continue
    }
    if (Test-Path -LiteralPath $part) {
        Write-Host "SKIP part file left from a failed run: ${wavName}.part" -ForegroundColor Yellow
        $lines.Add($quoted + ',"","error"'); $errors++; continue
    }
    if (-not $Run) {
        Write-Host "WOULD EXTRACT: ${name} -> work\${wavName}"
        $lines.Add($quoted + ',' + $wavQuoted + ',"ok"'); $done++; continue
    }
    if ((Invoke-AudioExtract $src $part) -and (Test-Path -LiteralPath $part -PathType Leaf)) {
        Rename-Item -LiteralPath $part -NewName $wavName
        Write-Host "EXTRACTED: ${name} -> work\${wavName}" -ForegroundColor Green
        $lines.Add($quoted + ',' + $wavQuoted + ',"ok"'); $done++
    }
    else {
        Write-Host "ERROR ffmpeg failed: ${name}" -ForegroundColor Yellow
        $lines.Add($quoted + ',"","error"'); $errors++
    }
}
Write-Host "Done. OK: $done  Exists: $exists  Error: $errors  Skipped: $skipped"

$audioPath = Join-Path $outDir 'audio.csv'
if (Test-Path -LiteralPath $audioPath) {
    $audioPath = Join-Path $outDir ('audio-{0}.csv' -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
}
if (Test-Path -LiteralPath $audioPath) {
    Write-Host "STOP: name already exists, list not written: $audioPath" -ForegroundColor Red
    exit 1
}

if ($Run) {
    Set-Content -LiteralPath $audioPath -Value $lines.ToArray() -Encoding UTF8
    Write-Host "List written: $audioPath" -ForegroundColor Green
}
else {
    Write-Host "Would write: $audioPath"
    Write-Host 'Dry run - nothing written.' -ForegroundColor Cyan
}
