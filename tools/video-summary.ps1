# video-summary.ps1 - makes a short vertical summary video (1080x1920) of one library card with Hyperframes.
# Usage: video-summary.ps1 -Name video-07 [-Ideas 1,4,6] [-Run]
# Reads <Library>\<name>.md, fills summary-template.html (title, up to 3 ideas, verdict; 3 seconds each),
# with no model: the code only puts the card text into fixed places. -Ideas picks ideas by number (default:
# the first 3). Long text is cut with an ellipsis (and the template shows at most 3 lines).
# Hyperframes comes from HyperframesDir in the settings (config-lib.ps1). It runs only with its six environment
# values (no telemetry, no update check, no skills, its config and cache in HyperframesDir), for that one run.
# STOP if HyperframesDir is empty, hyperframes.cmd or GSAP is missing, or Chrome is not in hf-cache (no download).
# Default is a dry run: prints the card, the ideas, the verdict, the length and the tools, writes nothing.
# With -Run it writes <Out>\summary-yyyyMMdd-HHmmss\project (index.html and vendor\gsap.min.js), checks the
# html has no http, renders <name>-summary.mp4 next to project, then opens the folder with the video selected.
# Never overwrites, never deletes, never runs npm or npx. Needs card-lib.ps1, config-lib.ps1, summary-lib.ps1
# and summary-template.html next to this script. ASCII only, works on Windows PowerShell 5.1.
param(
    [string]$Name,
    [string]$Ideas = '',
    [switch]$Run
)
$ErrorActionPreference = 'Stop'

function Stop-Tool([string]$msg) { Write-Host "STOP: $msg" -ForegroundColor Red; exit 1 }

foreach ($lib in @('card-lib.ps1', 'config-lib.ps1', 'summary-lib.ps1')) {
    $libPath = Join-Path $PSScriptRoot $lib
    if (-not (Test-Path -LiteralPath $libPath -PathType Leaf)) { Stop-Tool "helper file missing next to the script: $libPath" }
    . $libPath
}
$templatePath = Join-Path $PSScriptRoot 'summary-template.html'
if (-not (Test-Path -LiteralPath $templatePath -PathType Leaf)) { Stop-Tool "helper file missing next to the script: $templatePath" }
try { $cfg = Get-VideoConfig } catch { Write-Host $_.Exception.Message -ForegroundColor Red; exit 1 }
$maxTopic = 60
$maxIdea = 70
$maxReason = 90
$timeoutMs = 1800000

# The card.
if ($Name -match '\.(md|mp4)$') { $Name = $Name -replace '\.(md|mp4)$', '' }
if (-not (Test-CardName $Name)) { Stop-Tool "Use -Name with a card name only, like video-07 (no path): $Name" }
$cardPath = Join-Path $cfg.Library ($Name + '.md')
if (-not (Test-Path -LiteralPath $cardPath -PathType Leaf)) { Stop-Tool "card not found: $cardPath" }
$card = Read-Card $cardPath
$problems = Test-Card $card $Name
if ($problems.Count -gt 0) {
    foreach ($p in $problems) { Write-Host "PROBLEM: $p" -ForegroundColor Yellow }
    Stop-Tool "the card does not follow card-format.md: $cardPath"
}

# Hyperframes, Chrome and GSAP must already be on this machine: nothing is downloaded.
if (-not $cfg.HyperframesDir) { Stop-Tool 'HyperframesDir is empty. Set it in video-config.local.psd1 to the folder where hyperframes is installed.' }
if (-not (Test-Path -LiteralPath $cfg.HyperframesCmd -PathType Leaf)) { Stop-Tool "hyperframes.cmd not found: $($cfg.HyperframesCmd)" }
$chrome = Join-Path $cfg.HyperframesCache 'chrome'
if (-not (Test-Path -LiteralPath $chrome -PathType Container)) { Stop-Tool "Chrome is not in hf-cache (a render would download it): $chrome" }
$vendorNpm = Join-Path $cfg.HyperframesDir 'node_modules\hyperframes\dist\vendor\npm'
$gsapDir = $null
if (Test-Path -LiteralPath $vendorNpm -PathType Container) { $gsapDir = Get-ChildItem -LiteralPath $vendorNpm -Directory -Filter 'gsap@*' | Sort-Object Name -Descending | Select-Object -First 1 }
if (-not $gsapDir) { Stop-Tool "GSAP not found in: $vendorNpm" }
$gsap = Join-Path $gsapDir.FullName 'dist\gsap.min.js'
if (-not (Test-Path -LiteralPath $gsap -PathType Leaf)) { Stop-Tool "GSAP not found: $gsap" }

# The ideas: by -Ideas numbers, else the first 3.
$all = Get-CardIdeas $card
$picks = @(1..([math]::Min(3, $all.Count)))
if ($Ideas.Trim()) {
    $picks = @($Ideas -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' })
    foreach ($n in $picks) { if ($n -notmatch '^[0-9]+$' -or [int]$n -lt 1 -or [int]$n -gt $all.Count) { Stop-Tool "This card has $($all.Count) ideas. Choose numbers from 1 to $($all.Count): $Ideas" } }
    if ($picks.Count -gt 3) { Stop-Tool "Choose at most 3 ideas, like 1,2: $Ideas" }
}
$ideaTexts = New-Object System.Collections.Generic.List[string]
foreach ($n in $picks) {
    $cut = Limit-Text $all[[int]$n - 1] $maxIdea
    if ($cut.cut) { Write-Host "WARNING: idea $n is cut to $maxIdea characters" -ForegroundColor Yellow }
    $ideaTexts.Add($cut.text)
}
$topic = (Limit-Text (Get-SummaryLine $card) $maxTopic).text
if (-not $topic) { $topic = [string]$card.fields['topics'] }
$verdict = Get-VerdictParts ([string]$card.fields['verdict'])
$reason = Limit-Text $verdict.reason $maxReason
if ($reason.cut) { Write-Host "WARNING: the verdict reason is cut to $maxReason characters" -ForegroundColor Yellow }
$seconds = 3 * (2 + $ideaTexts.Count)

Write-Host "Card: $cardPath"
Write-Host "Topic: $topic"
for ($i = 0; $i -lt $ideaTexts.Count; $i++) { Write-Host "Idea $($picks[$i]) of $($all.Count): $($ideaTexts[$i])" }
Write-Host "Verdict: $($verdict.key) ($($verdict.word)) - $($reason.text)"
Write-Host "Length: $seconds s (1080x1920)"
Write-Host "Hyperframes: $($cfg.HyperframesCmd) (found)"
Write-Host "Chrome: $chrome (found)"
Write-Host "GSAP: $gsap (found)"

$sumDir = Join-Path $cfg.Out ('summary-{0}' -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
if (Test-Path -LiteralPath $sumDir) { Stop-Tool "folder already exists, nothing written: $sumDir" }
$project = Join-Path $sumDir 'project'
$video = Join-Path $sumDir ($Name + '-summary.mp4')
if (-not $Run) {
    Write-Host "Would write: $project and $video"
    Write-Host 'Dry run - nothing written.' -ForegroundColor Cyan
    exit 0
}

# The html is built and checked before anything is written.
$html = New-SummaryHtml ([System.IO.File]::ReadAllText($templatePath, [System.Text.Encoding]::UTF8)) $Name $topic $ideaTexts.ToArray() $verdict.word $reason.text
if ($html -match 'http') { Stop-Tool 'the summary html has http in it, nothing written' }
New-Item -ItemType Directory -Path (Join-Path $project 'vendor') | Out-Null
Copy-Item -LiteralPath $gsap -Destination (Join-Path $project 'vendor\gsap.min.js')
[System.IO.File]::WriteAllText((Join-Path $project 'index.html'), $html, (New-Object System.Text.UTF8Encoding($false)))

Write-Host 'Rendering with Hyperframes (this can take a while)...'
$watch = [System.Diagnostics.Stopwatch]::StartNew()
$job = Invoke-Hyperframes $cfg.HyperframesCmd ('render "' + $project + '" --output "' + $video + '"') $project (Get-HyperframesEnv $cfg) $timeoutMs
if (-not $job.ok -or -not (Test-Path -LiteralPath $video -PathType Leaf)) {
    foreach ($l in @(($job.out -split "`r?`n") | Where-Object { $_.Trim() } | Select-Object -Last 8)) { Write-Host "  hyperframes: $l" -ForegroundColor Yellow }
    Stop-Tool "render failed. What was written is left in: $sumDir"
}
Write-Host ('Render took {0:0.0} s' -f $watch.Elapsed.TotalSeconds)
Write-Host "Written: $video" -ForegroundColor Green
Start-Process -FilePath 'explorer.exe' -ArgumentList ('/select,"' + $video + '"')
