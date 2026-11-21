# video-card-save.ps1 - saves one library card: checks it, then moves it to the library.
# Usage: video-card-save.ps1 -Name video-08 (the card name, with or without .md).
# The card comes from <Downloads>\<name>.md and goes to <Library>\<name>.md (paths from config-lib.ps1).
# No path comes from the command line. Needs card-lib.ps1 and config-lib.ps1 next to this script.
# It prints every problem at once. A card with a problem is not moved. See card-format.md.
# Default is a dry run: prints only. Add -Run to move. With -Run it creates the library folder if needed.
# Never overwrites a card (STOP if it is already in the library), never deletes.
# The internet mark (Zone.Identifier) of a downloaded card: a dry run only says yes or no; -Run unblocks the moved card.
# ASCII only, works on Windows PowerShell 5.1.
param(
    [string]$Name,
    [switch]$Run
)
$ErrorActionPreference = 'Stop'

$libPath = Join-Path $PSScriptRoot 'card-lib.ps1'
if (-not (Test-Path -LiteralPath $libPath -PathType Leaf)) { Write-Host "STOP: helper file missing next to the script: $libPath" -ForegroundColor Red; exit 1 }
. $libPath
$cfgLib = Join-Path $PSScriptRoot 'config-lib.ps1'
if (-not (Test-Path -LiteralPath $cfgLib -PathType Leaf)) { Write-Host "STOP: helper file missing next to the script: $cfgLib" -ForegroundColor Red; exit 1 }
. $cfgLib
try { $cfg = Get-VideoConfig } catch { Write-Host $_.Exception.Message -ForegroundColor Red; exit 1 }

$downloads = $cfg.Downloads
$library = $cfg.Library
$inbox = $cfg.Inbox
$doneDir = $cfg.Done

if ($Name -match '\.md$') { $Name = $Name.Substring(0, $Name.Length - 3) }
if (-not (Test-CardName $Name)) { throw "Use -Name with a card name only (no path): $Name" }
$src = Join-Path $downloads ($Name + '.md')
$dest = Join-Path $library ($Name + '.md')

if (-not (Test-Path -LiteralPath $src -PathType Leaf)) {
    Write-Host "STOP: card not found: $src" -ForegroundColor Red
    $similar = @(Get-ChildItem -LiteralPath $downloads -File -Filter ($Name + '*.md') | ForEach-Object { $_.Name })
    if ($similar.Count -gt 0) { Write-Host "Similar names in Downloads: $($similar -join ', ')" -ForegroundColor Yellow }
    exit 1
}
if (Test-Path -LiteralPath $dest) { Write-Host "STOP: card already in the library, nothing moved: $dest" -ForegroundColor Red; exit 1 }

$card = Read-Card $src
$problems = Test-Card $card $Name
if ($problems.Count -gt 0) {
    foreach ($p in $problems) { Write-Host "PROBLEM: $p" -ForegroundColor Yellow }
    Write-Host "STOP: $($problems.Count) problems, nothing moved: $src" -ForegroundColor Red
    exit 1
}
Write-Host "Card OK: $($card.fields['video'])  length: $($card.fields['length'])  ideas: $($card.sections['ideas'].Count)"

$video = [string]$card.fields['video']
if (-not (Test-Path -LiteralPath (Join-Path $inbox $video)) -and -not (Test-Path -LiteralPath (Join-Path $doneDir $video))) {
    Write-Host "WARNING: video not in inbox or done: $video" -ForegroundColor Yellow
}

if (-not $Run) {
    if (-not (Test-Path -LiteralPath $library -PathType Container)) { Write-Host "Would create folder: $library" }
    $mark = 'no'
    if (Get-Item -LiteralPath $src -Stream 'Zone.Identifier' -ErrorAction SilentlyContinue) { $mark = 'yes' }
    Write-Host "Internet mark: $mark"
    Write-Host "Would move: $src -> $dest"
    Write-Host 'Dry run - nothing written.' -ForegroundColor Cyan
    exit 0
}
if (-not (Test-Path -LiteralPath $library -PathType Container)) { New-Item -ItemType Directory -Path $library | Out-Null }
Move-Item -LiteralPath $src -Destination $dest
Write-Host "Moved: $src -> $dest" -ForegroundColor Green
if (Get-Item -LiteralPath $dest -Stream 'Zone.Identifier' -ErrorAction SilentlyContinue) {
    Unblock-File -LiteralPath $dest
    Write-Host "Unblocked: $dest"
}
else { Write-Host 'No internet mark' }
