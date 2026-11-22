# video-list.ps1 - stage 1 of the video pipeline: list the videos the user saved.
# Reads only the file names in <Inbox> (no subfolders). Never opens a file.
# Default is a dry run: prints the list and writes nothing. Add -Run to write the list.
# With -Run it writes <Out>\videos.csv (columns: file,size_mb).
# If videos.csv already exists, it writes videos-yyyyMMdd-HHmmss.csv instead. Never overwrites.
# Paths come from config-lib.ps1 (next to this script): no path comes from the command line.
# Never moves, never deletes, never writes outside out. ASCII only, works on Windows PowerShell 5.1.
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

if (-not (Test-Path -LiteralPath $inbox -PathType Container)) { Stop-Tool "Inbox folder not found: $inbox. Make the folders first (README, section 5)." }
if (-not (Test-Path -LiteralPath $outDir -PathType Container)) { Stop-Tool "Out folder not found: $outDir. Make the folders first (README, section 5)." }

$videoExt = @('.mp4', '.mov', '.mkv', '.webm', '.m4v', '.avi')
$inProgressExt = @('.crdownload', '.part', '.partial', '.download', '.tmp')
$culture = [System.Globalization.CultureInfo]::InvariantCulture

$lines = New-Object System.Collections.Generic.List[string]
$lines.Add('file,size_mb')

$videos = 0
$skipped = 0
$files = @(Get-ChildItem -LiteralPath $inbox -File -Force | Sort-Object Name)
foreach ($f in $files) {
    $name = $f.Name
    $ext = $f.Extension.ToLowerInvariant()
    $hiddenOrSystem = ($f.Attributes -band ([System.IO.FileAttributes]::Hidden -bor [System.IO.FileAttributes]::System)) -ne 0
    if ($hiddenOrSystem) {
        Write-Host "SKIP hidden or system: ${name}"; $skipped++; continue
    }
    if ($inProgressExt -contains $ext) {
        Write-Host "SKIP in progress: ${name}"; $skipped++; continue
    }
    if ($videoExt -notcontains $ext) {
        Write-Host "SKIP not a video: ${name}"; $skipped++; continue
    }
    $sizeMb = ([math]::Round($f.Length / 1MB, 2)).ToString('0.00', $culture)
    $lines.Add('"' + $name.Replace('"', '""') + '","' + $sizeMb + '"')
    Write-Host "VIDEO: ${name} (${sizeMb} MB)"
    $videos++
}
Write-Host "Done. Videos: $videos  Skipped: $skipped"

$listPath = Join-Path $outDir 'videos.csv'
if (Test-Path -LiteralPath $listPath) {
    $listName = 'videos-{0}.csv' -f (Get-Date -Format 'yyyyMMdd-HHmmss')
    $listPath = Join-Path $outDir $listName
}
if (Test-Path -LiteralPath $listPath) {
    Write-Host "STOP: name already exists, nothing written: $listPath" -ForegroundColor Red
    exit 1
}

if ($Run) {
    Set-Content -LiteralPath $listPath -Value $lines.ToArray() -Encoding UTF8
    Write-Host "List written: $listPath" -ForegroundColor Green
}
else {
    Write-Host "Would write: $listPath"
    Write-Host 'Dry run - nothing written.' -ForegroundColor Cyan
}
