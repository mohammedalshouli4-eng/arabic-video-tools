# video-card-pack.ps1 - packs library cards into one file for Claude, to link the ideas between videos.
# Usage: video-card-pack.ps1 (all cards), -Names video-05,video-08 (chosen cards), -Topic wsl (cards whose
# topics list has this word, not case sensitive). -Names and -Topic together: a card must match both.
# Reads <Library>\*.md with card-lib.ps1. A card that fails the check (see card-format.md) goes to
# the Skipped cards section with its problems, and so does a chosen name that has no card.
# Writes <Out>\library-yyyyMMdd-HHmmss.md: card-note.md, an index table (video, topics,
# verdict), the cards whole, then Skipped cards. Cards are read and written as UTF-8 (they hold Arabic).
# Needs card-lib.ps1, config-lib.ps1 (Library and Out paths) and card-note.md next to this script.
# Default is a dry run: prints the cards that go in and the ones left out, writes nothing. With -Run it
# writes the file, then opens the folder with the file selected. STOP if the file exists or no good card matched.
# Never overwrites, never deletes, never changes a card. ASCII only, works on Windows PowerShell 5.1.
param(
    [string[]]$Names,
    [string]$Topic,
    [switch]$Run
)
$ErrorActionPreference = 'Stop'

$libPath = Join-Path $PSScriptRoot 'card-lib.ps1'
$cfgLib = Join-Path $PSScriptRoot 'config-lib.ps1'
$notePath = Join-Path $PSScriptRoot 'card-note.md'

function Stop-Tool([string]$msg) { Write-Host "STOP: $msg" -ForegroundColor Red; exit 1 }

if (-not (Test-Path -LiteralPath $libPath -PathType Leaf)) { Stop-Tool "helper file missing next to the script: $libPath" }
if (-not (Test-Path -LiteralPath $notePath -PathType Leaf)) { Stop-Tool "card-note.md missing next to the script: $notePath" }
if (-not (Test-Path -LiteralPath $cfgLib -PathType Leaf)) { Stop-Tool "helper file missing next to the script: $cfgLib" }
. $libPath
. $cfgLib
try { $cfg = Get-VideoConfig } catch { Write-Host $_.Exception.Message -ForegroundColor Red; exit 1 }
$library = $cfg.Library
$outDir = $cfg.Out
foreach ($d in @($library, $outDir)) {
    if (-not (Test-Path -LiteralPath $d -PathType Container)) { if ($d -eq $library) { Stop-Tool "no library folder yet: $library. Save a card first with option 5 (video-card-save -Run)." } else { Stop-Tool "Folder not found: $d" } }
}

# With powershell -File, -Names video-05,video-08 comes as one string, so it is split on commas here.
$chosen = @($Names | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' } | ForEach-Object { $_ -replace '\.md$', '' })
foreach ($n in $chosen) { if (-not (Test-CardName $n)) { throw "Use -Names with card names only (no path): $n" } }
$Topic = ([string]$Topic).Trim()

$cards = New-Object System.Collections.Generic.List[object]
$skipped = New-Object System.Collections.Generic.List[string]
$notMatched = New-Object System.Collections.Generic.List[string]
$files = @(Get-ChildItem -LiteralPath $library -File -Filter '*.md' | Sort-Object Name)
foreach ($n in $chosen) {
    if (-not ($files | Where-Object { $_.BaseName -eq $n })) { $skipped.Add("- ${n}.md: card not found in the library") }
}
foreach ($f in $files) {
    $name = $f.BaseName
    if ($chosen.Count -gt 0 -and $chosen -notcontains $name) { continue }
    if (-not (Test-CardName $name)) { $skipped.Add("- $($f.Name): name not allowed"); continue }
    $card = Read-Card $f.FullName
    if ($Topic) {
        $topics = @(([string]$card.fields['topics']) -split ',' | ForEach-Object { $_.Trim() })
        if ($topics -notcontains $Topic) { $notMatched.Add($f.Name); continue }
    }
    $problems = Test-Card $card $name
    if ($problems.Count -gt 0) { $skipped.Add("- $($f.Name): " + ($problems -join '; ')); continue }
    $cards.Add([pscustomobject]@{ file = $f; card = $card })
}

Write-Host "Library: $library  cards in: $($cards.Count)  skipped: $($skipped.Count)"
if ($Topic) { Write-Host "Topic: $Topic  not in this topic: $($notMatched.Count)" }
foreach ($c in $cards) { Write-Host "IN: $($c.file.Name)  topics: $($c.card.fields['topics'])" }
foreach ($s in $skipped) { Write-Host ('SKIP' + $s.Substring(1)) -ForegroundColor Yellow }
if ($cards.Count -eq 0) { Stop-Tool 'no good card matched, nothing written' }

$outPath = Join-Path $outDir ('library-{0}.md' -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
if (Test-Path -LiteralPath $outPath) { Stop-Tool "file already exists, nothing written: $outPath" }

# The file: card-note.md, the index, the cards whole, then Skipped cards.
$md = New-Object System.Collections.Generic.List[string]
foreach ($t in @(Get-Content -LiteralPath $notePath -Encoding UTF8)) { $md.Add($t.TrimStart([char]0xFEFF)) }
$filter = 'all cards'
if ($chosen.Count -gt 0) { $filter = 'names: ' + ($chosen -join ', ') }
if ($Topic) { $filter += ', topic: ' + $Topic }
foreach ($t in @('', '## Index', ('Made ' + (Get-Date -Format 'yyyy-MM-dd HH:mm') + ' from ' + $library + ', ' + $filter + '. Cards: ' + $cards.Count + ', skipped: ' + $skipped.Count + '.'), '', '| video | topics | verdict |', '| --- | --- | --- |')) { $md.Add($t) }
foreach ($c in $cards) {
    $cells = @('video', 'topics', 'verdict' | ForEach-Object { ([string]$c.card.fields[$_]).Replace('|', '\|') })
    $md.Add('| ' + ($cells -join ' | ') + ' |')
}
foreach ($c in $cards) {
    foreach ($t in @('', '---', '', ('# Card: ' + $c.file.Name), '')) { $md.Add($t) }
    foreach ($t in @(Get-Content -LiteralPath $c.file.FullName -Encoding UTF8)) { $md.Add($t.TrimStart([char]0xFEFF)) }
}
foreach ($t in @('', '---', '', '## Skipped cards')) { $md.Add($t) }
if ($skipped.Count -eq 0) { $md.Add('- none') } else { foreach ($s in $skipped) { $md.Add($s) } }

if (-not $Run) {
    Write-Host "Would write: $outPath  ($($md.Count) lines)"
    Write-Host 'Dry run - nothing written.' -ForegroundColor Cyan
    exit 0
}
Set-Content -LiteralPath $outPath -Value $md.ToArray() -Encoding UTF8
Write-Host "Written: $outPath" -ForegroundColor Green
Start-Process -FilePath 'explorer.exe' -ArgumentList ('/select,"' + $outPath + '"')
