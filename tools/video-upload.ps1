# video-upload.ps1 - builds one zip for Claude for one video, so nobody has to search the folders.
# Usage: video-upload.ps1 -Name video-NN (any name of letters, digits, _ and -). Writes <Upload>\video-NN-yyyyMMdd-HHmmss.zip.
# In the zip, side by side and unchanged: the newest handoff-*.md with the video, the newest frames-* of
# the video (its ok images, notes.md, frames.csv), the newest moments.md of the video, and card-format.md.
# Sure matching: a handoff has the exact heading "## <video file>", frames.csv has the video in its video
# column with status ok, moments.md has the video in its title line. Newest is the time in the name, not
# the file date. Frames and moments are optional. No handoff is a STOP.
# Default is a dry run: prints only, writes nothing, makes no folder. With -Run it creates the upload folder
# if needed, writes <zip>.part, renames it to the zip, then opens the folder with the zip selected.
# Paths (Out, Upload) come from config-lib.ps1, which must be next to this script.
# Never overwrites, never deletes, never changes a source. STOP if the zip exists or a .part is left over.
# ASCII only, works on Windows PowerShell 5.1.
param(
    [string]$Name,
    [switch]$Run
)
$ErrorActionPreference = 'Stop'

$cfgLib = Join-Path $PSScriptRoot 'config-lib.ps1'
if (-not (Test-Path -LiteralPath $cfgLib -PathType Leaf)) { Write-Host "STOP: helper file missing next to the script: $cfgLib" -ForegroundColor Red; exit 1 }
. $cfgLib
try { $cfg = Get-VideoConfig } catch { Write-Host $_.Exception.Message -ForegroundColor Red; exit 1 }
$outDir = $cfg.Out
$uploadDir = $cfg.Upload
$formatPath = Join-Path $PSScriptRoot 'card-format.md'

function Stop-Tool([string]$msg) { Write-Host "STOP: $msg" -ForegroundColor Red; exit 1 }

# Items of out whose name matches, newest first: the name holds the time, so it sorts by time.
function Get-Stamped([string]$rx) {
    return @(Get-ChildItem -LiteralPath $outDir | Where-Object { $_.Name -cmatch $rx } | Sort-Object Name -Descending)
}

if ($Name -cnotmatch '^[A-Za-z0-9][A-Za-z0-9_-]*\z') { Stop-Tool "Use -Name with a video name only, like video-05 or demo-01 (no path, no extension): $Name" }
if (-not (Test-Path -LiteralPath $outDir -PathType Container)) { Stop-Tool "Folder not found: $outDir. Make the folders first (README, section 5)." }
if (-not (Test-Path -LiteralPath $formatPath -PathType Leaf)) { Stop-Tool "card-format.md missing next to the script: $formatPath" }

# Handoff: the newest one with the exact heading, not a video named under Skipped videos.
$headingRx = '^## ' + [regex]::Escape($Name) + '\.[A-Za-z0-9]+$'
$handoff = $null
$video = ''
$lines = @()
foreach ($f in (Get-Stamped '^handoff-[0-9]{8}-[0-9]{6}\.md$')) {
    $lines = @(Get-Content -LiteralPath $f.FullName -Encoding UTF8)
    $hits = @($lines | Where-Object { $_ -cmatch $headingRx })
    if ($hits.Count -eq 0) { continue }
    if ($hits.Count -gt 1) { Stop-Tool "more than one heading for $Name in $($f.Name): $($hits -join ', ')" }
    $handoff = $f
    $video = $hits[0].Substring(3)
    break
}
if (-not $handoff) { Stop-Tool "no handoff-*.md has a heading for $Name in $outDir" }
$others = @($lines | Where-Object { $_ -match '^## .+\.[A-Za-z0-9]+$' -and $_ -cne ('## ' + $video) } | ForEach-Object { $_.Substring(3) })

$items = New-Object System.Collections.Generic.List[string]
$items.Add($handoff.FullName)
$items.Add($formatPath)

# Frames: the newest folder whose frames.csv has an ok row for the video. The rows pick the images,
# so nothing else in the folder gets in.
$framesDir = $null
$imageCount = 0
foreach ($d in (Get-Stamped '^frames-[0-9]{8}-[0-9]{6}$')) {
    $csv = Join-Path $d.FullName 'frames.csv'
    if (-not (Test-Path -LiteralPath $csv -PathType Leaf)) { continue }
    $rows = @(Import-Csv -LiteralPath $csv -Encoding UTF8)
    $good = @($rows | Where-Object { $_.video -ceq $video -and $_.status -ceq 'ok' })
    if ($good.Count -eq 0) { continue }
    $framesDir = $d
    $imageCount = $good.Count
    foreach ($r in $good) {
        $img = Join-Path $d.FullName ([string]$r.file)
        if (-not (Test-Path -LiteralPath $img -PathType Leaf)) { Stop-Tool "image in frames.csv is missing: $img" }
        $items.Add($img)
    }
    $items.Add($csv)
    $notes = Join-Path $d.FullName 'notes.md'
    if (Test-Path -LiteralPath $notes -PathType Leaf) { $items.Add($notes) }
    else { Write-Host "WARNING: no notes.md in $($d.Name)" -ForegroundColor Yellow }
    $mixed = @($rows | Where-Object { $_.video -cne $video } | ForEach-Object { $_.video } | Sort-Object -Unique)
    if ($mixed.Count -gt 0) { Write-Host "WARNING: $($d.Name) also has $($mixed -join ', '): their images stay out, frames.csv and notes.md stay whole" -ForegroundColor Yellow }
    break
}

# Moments: the newest moments.md whose title line names the video.
$titleRx = '^# Video moments: ' + [regex]::Escape($video) + '\s'
$momentsDir = $null
foreach ($d in (Get-Stamped '^moments-[0-9]{8}-[0-9]{6}$')) {
    $md = Join-Path $d.FullName 'moments.md'
    if (-not (Test-Path -LiteralPath $md -PathType Leaf)) { continue }
    $title = ([string](Get-Content -LiteralPath $md -Encoding UTF8 -TotalCount 1)).TrimStart([char]0xFEFF)
    if ($title -cmatch $titleRx) {
        $momentsDir = $d
        $items.Add($md)
        break
    }
}

$zipPath = Join-Path $uploadDir ('{0}-{1}.zip' -f $Name, (Get-Date -Format 'yyyyMMdd-HHmmss'))
$partPath = $zipPath + '.part'
if (Test-Path -LiteralPath $zipPath) { Stop-Tool "zip already exists, nothing written: $zipPath" }
if (Test-Path -LiteralPath $uploadDir -PathType Container) {
    $left = @(Get-ChildItem -LiteralPath $uploadDir -File -Filter '*.part' | ForEach-Object { $_.Name })
    if ($left.Count -gt 0) { Stop-Tool ".part left from a run that failed, look at it first: $($left -join ', ')" }
}

Write-Host "Video: $video"
Write-Host "Handoff: $($handoff.Name)"
if ($others.Count -gt 0) { Write-Host "WARNING: also in this handoff: $($others -join ', ')" -ForegroundColor Yellow }
if ($framesDir) { Write-Host "Frames: $($framesDir.Name)  images: $imageCount" } else { Write-Host 'Frames: none for this video' }
if ($momentsDir) { Write-Host "Moments: $($momentsDir.Name)  moments.md only, its images stay out" } else { Write-Host 'Moments: none for this video' }
Write-Host "Files in the zip: $($items.Count)"
$total = 0
foreach ($p in $items) {
    $total += (Get-Item -LiteralPath $p).Length
    Write-Host ('  ' + [System.IO.Path]::GetFileName($p))
}
Write-Host ('Size before the zip: {0} KB' -f [math]::Ceiling($total / 1024))

if (-not $Run) {
    if (-not (Test-Path -LiteralPath $uploadDir -PathType Container)) { Write-Host "Would create folder: $uploadDir" }
    Write-Host "Would write: $zipPath"
    Write-Host 'Dry run - nothing written.' -ForegroundColor Cyan
    exit 0
}

if (-not (Test-Path -LiteralPath $uploadDir -PathType Container)) { New-Item -ItemType Directory -Path $uploadDir | Out-Null }
Add-Type -AssemblyName System.IO.Compression, System.IO.Compression.FileSystem
$zip = [System.IO.Compression.ZipFile]::Open($partPath, [System.IO.Compression.ZipArchiveMode]::Create)
try {
    foreach ($p in $items) {
        [void][System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip, $p, [System.IO.Path]::GetFileName($p))
    }
}
finally { $zip.Dispose() }
Rename-Item -LiteralPath $partPath -NewName ([System.IO.Path]::GetFileName($zipPath))
Write-Host "Written: $zipPath" -ForegroundColor Green
Start-Process -FilePath 'explorer.exe' -ArgumentList ('/select,"' + $zipPath + '"')
