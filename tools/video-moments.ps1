# video-moments.ps1 - optional tool, not part of the main video pipeline: frames at moments the user picks.
# Usage: video-moments.ps1 -Name video-06 (or video-06.mp4). The video is looked up in
# <Inbox>, then in <Done> (paths from config-lib.ps1). It is never moved.
# Moments file: <Moments>\<video name without extension>.txt, written by hand,
# one line per moment: time | request (see moments-template.txt). A bad line is marked and the rest goes on.
# Needs moments-lib.ps1, config-lib.ps1, moments-note.md and moments-template.txt next to this script.
# Writes a new folder out\moments-yyyyMMdd-HHmmss with one frame per time and moments.md for Claude.
# Default is a dry run: prints only. Add -Run to write. Never deletes, never overwrites, never runs a request.
# ASCII only, works on Windows PowerShell 5.1.
param(
    [string]$Name,
    [switch]$Run
)
$ErrorActionPreference = 'Stop'
function Stop-Tool([string]$msg) { Write-Host "STOP: $msg" -ForegroundColor Red; exit 1 }

$libPath = Join-Path $PSScriptRoot 'moments-lib.ps1'
$notePath = Join-Path $PSScriptRoot 'moments-note.md'
$templatePath = Join-Path $PSScriptRoot 'moments-template.txt'
$cfgLib = Join-Path $PSScriptRoot 'config-lib.ps1'
foreach ($f in @($libPath, $notePath, $templatePath, $cfgLib)) {
    if (-not (Test-Path -LiteralPath $f -PathType Leaf)) { Write-Host "STOP: helper file missing next to the script: $f" -ForegroundColor Red; exit 1 }
}
. $libPath
. $cfgLib
try { $cfg = Get-VideoConfig } catch { Write-Host $_.Exception.Message -ForegroundColor Red; exit 1 }

$inbox = $cfg.Inbox
$doneDir = $cfg.Done
$workDir = $cfg.Work
$outDir = $cfg.Out
$momentsDir = $cfg.Moments
try { $ffmpeg = Get-FfmpegTool 'ffmpeg' $cfg; $ffprobe = Get-FfmpegTool 'ffprobe' $cfg } catch { Write-Host $_.Exception.Message -ForegroundColor Red; exit 1 }
$culture = [System.Globalization.CultureInfo]::InvariantCulture
$exts = @('.mp4', '.mov', '.mkv', '.webm', '.m4v', '.avi')
$near = 2.0
$maxMoments = 40
$timeoutMs = 60000

foreach ($f in @($ffmpeg, $ffprobe)) { if (-not (Test-Path -LiteralPath $f -PathType Leaf)) { throw "ffmpeg or ffprobe not found: $f" } }
foreach ($d in @($workDir, $outDir)) { if (-not (Test-Path -LiteralPath $d -PathType Container)) { Stop-Tool "Folder not found: $d. Make the folders first (README, section 5)." } }
if ([string]::IsNullOrWhiteSpace($Name) -or $Name -match '[\\/:]' -or $Name -match '\.\.' -or $Name -match "[',;=\[\]%]") {
    Stop-Tool "Use -Name with a video name only, like video-07 or video-07.mp4 (no path): $Name"
}

$found = Find-Video $Name @($inbox, $doneDir) $exts
if ($found.Count -eq 0) { Stop-Tool "Video not found in inbox or done: $Name. Check the name, like video-07." }
if ($found.Count -gt 1) {
    Write-Host "STOP: more than one video matches ${Name}: $(($found | ForEach-Object { $_.Name }) -join ', '). Use the full name." -ForegroundColor Red
    exit 1
}
$video = $found[0]
$base = $video.BaseName
Write-Host "Video: $($video.FullName)"

# No moments file yet: -Run copies the template there (and makes the folder if needed) and stops.
$momentsFile = Join-Path $momentsDir ($base + '.txt')
$needFolder = -not (Test-Path -LiteralPath $momentsDir -PathType Container)
if ($needFolder -or -not (Test-Path -LiteralPath $momentsFile -PathType Leaf)) {
    $what = 'template'
    if ($needFolder) { $what = 'folder and template' }
    if (-not $Run) { Write-Host "Would create ${what}: $momentsFile"; Write-Host 'Dry run - nothing written.' -ForegroundColor Cyan; exit 0 }
    if ($needFolder) { New-Item -ItemType Directory -Path $momentsDir | Out-Null }
    Copy-Item -LiteralPath $templatePath -Destination $momentsFile
    Write-Host "Created ${what}: $momentsFile" -ForegroundColor Green
    Write-Host 'Fill it in Notepad, one line per moment, save it, then run again.' -ForegroundColor Yellow
    exit 0
}

$durText = Invoke-Tool $ffprobe ('-v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "' + $video.FullName + '"') $timeoutMs
$duration = 0.0
if ($null -eq $durText -or -not [double]::TryParse($durText.Trim(), [System.Globalization.NumberStyles]::Float, $culture, [ref]$duration)) {
    Stop-Tool "Could not read the length of $($video.Name). Is it a real, finished video file?"
}
$durClock = (Get-Label ([int][math]::Floor($duration))).Replace('-', ':')

$moments = Read-Moments $momentsFile $duration $durClock $maxMoments
if ($moments.Count -eq 0) { Write-Host "STOP: no moments in $momentsFile" -ForegroundColor Red; exit 1 }
$good = @($moments | Where-Object { -not $_.err }).Count

$srt = Join-Path $workDir ($video.Name + '.srt')
$hasSrt = Test-Path -LiteralPath $srt -PathType Leaf
$entries = @()
if ($hasSrt) { $entries = Get-SrtEntries $srt }

$momDir = Join-Path $outDir ('moments-{0}' -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
if (Test-Path -LiteralPath $momDir) { Write-Host "STOP: folder already exists, nothing written: $momDir" -ForegroundColor Red; exit 1 }
if ($Run) { New-Item -ItemType Directory -Path $momDir | Out-Null }

# One frame per time. Two lines with the same time share one frame.
$made = @{}
foreach ($mo in $moments) {
    if ($mo.err) { Write-Host "ERROR line $($mo.line): $($mo.err)" -ForegroundColor Yellow; continue }
    $label = Get-Label $mo.sec
    $mo.file = $base + '_' + $label + '.jpg'
    $mo.said = 'no srt'
    if ($hasSrt) { $mo.said = Get-Said $entries $mo.sec $near }
    Write-Host "OK line $($mo.line) [$($label.Replace('-', ':'))] -> $($mo.file)"
    if (-not $Run -or $made.ContainsKey($mo.file)) { continue }
    $dest = Join-Path $momDir $mo.file
    $okRun = $null -ne (Invoke-Tool $ffmpeg ('-hide_banner -nostdin -n -v error -ss ' + $mo.sec + ' -i "' + $video.FullName + '" -frames:v 1 -update 1 -q:v 4 "' + $dest + '"') $timeoutMs)
    $made[$mo.file] = $okRun -and (Test-Path -LiteralPath $dest -PathType Leaf) -and (Get-Item -LiteralPath $dest).Length -gt 0
    if (-not $made[$mo.file]) { Write-Host "ERROR frame failed: $($mo.file)" -ForegroundColor Yellow }
}

$title = '# Video moments: ' + $video.Name + '  (' + (Get-Date -Format 'yyyy-MM-dd HH:mm') + ', duration ' + $durClock + ')'
$md = Get-MomentsMd $title $notePath $moments $made
if ($Run) {
    Set-Content -LiteralPath (Join-Path $momDir 'moments.md') -Value $md -Encoding UTF8
    Write-Host "Done. Moments OK: $good  Line errors: $($moments.Count - $good)  Frame errors: $(@($made.Values | Where-Object { -not $_ }).Count)"
    Write-Host "Written: $momDir" -ForegroundColor Green
}
else {
    $frames = @($moments | Where-Object { -not $_.err } | ForEach-Object { $_.file } | Select-Object -Unique).Count
    Write-Host "Would write: $momDir with $frames frames and moments.md with $($moments.Count) blocks."
    Write-Host 'Dry run - nothing written.' -ForegroundColor Cyan
}
