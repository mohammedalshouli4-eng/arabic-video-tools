# video-text.ps1 - stage 4 of the video pipeline: turn each wav into text with the whisper filter of ffmpeg.
# Reads the newest <Out>\audio*.csv (from video-audio.ps1). Paths, ffmpeg and the model come from config-lib.ps1.
# Works only on rows with status=ok or status=exists. Every other row is a SKIP.
# For each <Work>\<video name>.wav it writes work\<video name>.srt
# (language=auto, queue=20, format=srt). ffmpeg writes <video name>.srt.part first and the
# script renames it only if ffmpeg succeeded and the file is not empty.
# The whisper filter breaks on C: in a path, so ffmpeg runs in <Videos> with relative paths.
# Default is a dry run: prints only. Add -Run to write the srt files and text.csv in out
# (columns: file,srt,status). If text.csv exists, it writes text-yyyyMMdd-HHmmss.csv instead.
# Never overwrites. Never touches videos or wav files. Writes only in work and out.
# Does not fix or clean the text. ASCII only, works on Windows PowerShell 5.1.
param(
    [switch]$Run
)
$ErrorActionPreference = 'Stop'

$cfgLib = Join-Path $PSScriptRoot 'config-lib.ps1'
if (-not (Test-Path -LiteralPath $cfgLib -PathType Leaf)) { Write-Host "STOP: helper file missing next to the script: $cfgLib" -ForegroundColor Red; exit 1 }
. $cfgLib
try { $cfg = Get-VideoConfig } catch { Write-Host $_.Exception.Message -ForegroundColor Red; exit 1 }
$baseDir = $cfg.Videos
$workDir = $cfg.Work
$outDir = $cfg.Out
try { $ffmpeg = Get-FfmpegTool 'ffmpeg' $cfg } catch { Write-Host $_.Exception.Message -ForegroundColor Red; exit 1 }
$model = $cfg.WhisperModel
$modelRel = $cfg.WhisperModelRel
$timeoutMs = 1200000

if (-not (Test-Path -LiteralPath $ffmpeg -PathType Leaf)) { throw "ffmpeg not found: $ffmpeg" }
if (-not (Test-Path -LiteralPath $model -PathType Leaf)) { throw "Whisper model not found: $model" }
foreach ($d in @($baseDir, $workDir, $outDir)) {
    if (-not (Test-Path -LiteralPath $d -PathType Container)) { throw "Folder not found: $d" }
}

$listFile = Get-ChildItem -LiteralPath $outDir -File -Filter 'audio*.csv' | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if (-not $listFile) { throw "No audio*.csv in $outDir. Run video-audio.ps1 -Run first." }
Write-Host "List: $($listFile.Name)"

# Runs ffmpeg with the whisper filter for one wav. Paths are relative to <Videos>.
# Returns $true only if ffmpeg exited with 0 in time. Never throws.
function Invoke-Whisper([string]$wavRel, [string]$destRel) {
    try {
        $filter = 'whisper=model=' + $modelRel + ':language=auto:queue=20:destination=' + $destRel + ':format=srt'
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = $ffmpeg
        $psi.WorkingDirectory = $baseDir
        $psi.Arguments = '-hide_banner -nostdin -v error -i "' + $wavRel + '" -af "' + $filter + '" -f null -'
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
$lines.Add('file,srt,status')

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
    # Characters with a meaning inside an ffmpeg filter string.
    if ($name -match "[',;=\[\]%]") {
        Write-Host "SKIP name has a filter character (' , ; = [ ] %): ${name}"
        $lines.Add($quoted + ',"","rejected"'); $skipped++; continue
    }
    $status = [string]$r.status
    if ($status -ne 'ok' -and $status -ne 'exists') {
        Write-Host "SKIP status ${status}: ${name}"
        $lines.Add($quoted + ',"","skipped"'); $skipped++; continue
    }
    $wavName = $name + '.wav'
    if (-not (Test-Path -LiteralPath (Join-Path $workDir $wavName) -PathType Leaf)) {
        Write-Host "SKIP wav not in work: ${wavName}"
        $lines.Add($quoted + ',"","rejected"'); $skipped++; continue
    }
    $srtName = $name + '.srt'
    $srt = Join-Path $workDir $srtName
    $part = $srt + '.part'
    $srtQuoted = '"' + $srtName.Replace('"', '""') + '"'
    if (Test-Path -LiteralPath $srt) {
        Write-Host "SKIP exists: ${srtName}"
        $lines.Add($quoted + ',' + $srtQuoted + ',"exists"'); $exists++; continue
    }
    if (Test-Path -LiteralPath $part) {
        Write-Host "SKIP part file left from a failed run: ${srtName}.part" -ForegroundColor Yellow
        $lines.Add($quoted + ',"","error"'); $errors++; continue
    }
    if (-not $Run) {
        Write-Host "WOULD TRANSCRIBE: work\${wavName} -> work\${srtName}"
        $lines.Add($quoted + ',' + $srtQuoted + ',"ok"'); $done++; continue
    }
    $okRun = Invoke-Whisper ('work/' + $wavName) ('work/' + $srtName + '.part')
    if ($okRun -and (Test-Path -LiteralPath $part -PathType Leaf) -and (Get-Item -LiteralPath $part).Length -gt 0) {
        Rename-Item -LiteralPath $part -NewName $srtName
        Write-Host "TRANSCRIBED: work\${wavName} -> work\${srtName}" -ForegroundColor Green
        $lines.Add($quoted + ',' + $srtQuoted + ',"ok"'); $done++
    }
    else {
        Write-Host "ERROR whisper failed or empty text: ${name}" -ForegroundColor Yellow
        $lines.Add($quoted + ',"","error"'); $errors++
    }
}
Write-Host "Done. OK: $done  Exists: $exists  Error: $errors  Skipped: $skipped"

$textPath = Join-Path $outDir 'text.csv'
if (Test-Path -LiteralPath $textPath) {
    $textPath = Join-Path $outDir ('text-{0}.csv' -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
}
if (Test-Path -LiteralPath $textPath) {
    Write-Host "STOP: name already exists, list not written: $textPath" -ForegroundColor Red
    exit 1
}

if ($Run) {
    Set-Content -LiteralPath $textPath -Value $lines.ToArray() -Encoding UTF8
    Write-Host "List written: $textPath" -ForegroundColor Green
}
else {
    Write-Host "Would write: $textPath"
    Write-Host 'Dry run - nothing written.' -ForegroundColor Cyan
}
