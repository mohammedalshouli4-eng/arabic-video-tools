# video-handoff.ps1 - stage 5 of the video pipeline: build one handoff file for Claude.
# Reads the newest <Out>\text*.csv (rows with status=ok or exists) and the newest
# lengths*.csv (for the duration of each video). Reads each srt in <Work> (paths from config-lib.ps1).
# Writes <Out>\handoff-yyyyMMdd-HHmmss.md: one heading per video, one line per
# sentence as [mm:ss] text. A line gets [?] when it ends more than 1 second after the video ends,
# or when the whole text is inside * *, [ ] or ( ), or when it has no letter or digit in any
# language. Nothing is removed or corrected.
# Default is a dry run: prints a summary only. Add -Run to write the file. Never overwrites.
# No ffmpeg, no model: pure code. Writes only in out. ASCII only, works on Windows PowerShell 5.1.
param(
    [switch]$Run
)
$ErrorActionPreference = 'Stop'

$cfgLib = Join-Path $PSScriptRoot 'config-lib.ps1'
if (-not (Test-Path -LiteralPath $cfgLib -PathType Leaf)) { Write-Host "STOP: helper file missing next to the script: $cfgLib" -ForegroundColor Red; exit 1 }
. $cfgLib
try { $cfg = Get-VideoConfig } catch { Write-Host $_.Exception.Message -ForegroundColor Red; exit 1 }
$workDir = $cfg.Work
$outDir = $cfg.Out
$culture = [System.Globalization.CultureInfo]::InvariantCulture
$timeRx = '(\d+):(\d\d):(\d\d)[,.](\d+)\s*-->\s*(\d+):(\d\d):(\d\d)[,.](\d+)'

foreach ($d in @($workDir, $outDir)) {
    if (-not (Test-Path -LiteralPath $d -PathType Container)) { throw "Folder not found: $d" }
}
$textList = Get-ChildItem -LiteralPath $outDir -File -Filter 'text*.csv' | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if (-not $textList) { throw "No text*.csv in $outDir. Run video-text.ps1 -Run first." }
$lengthList = Get-ChildItem -LiteralPath $outDir -File -Filter 'lengths*.csv' | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if (-not $lengthList) { throw "No lengths*.csv in $outDir. Run video-length.ps1 -Run first." }
Write-Host "Text list: $($textList.Name)"
Write-Host "Lengths list: $($lengthList.Name)"

$durations = @{}
foreach ($r in @(Import-Csv -LiteralPath $lengthList.FullName -Encoding UTF8)) {
    $d = 0.0
    if ([double]::TryParse([string]$r.duration_sec, [System.Globalization.NumberStyles]::Float, $culture, [ref]$d)) {
        $durations[([string]$r.file).Trim()] = $d
    }
}

function Get-Seconds($m, [int]$first) {
    return [int]$m.Groups[$first].Value * 3600 + [int]$m.Groups[$first + 1].Value * 60 + [int]$m.Groups[$first + 2].Value + [double]('0.' + $m.Groups[$first + 3].Value)
}
function Format-Clock([double]$sec) {
    $s = [int][math]::Floor($sec)
    return '{0:00}:{1:00}' -f [math]::Floor($s / 60), ($s % 60)
}

$md = New-Object System.Collections.Generic.List[string]
$md.Add('# Video handoff ' + (Get-Date -Format 'yyyy-MM-dd HH:mm'))
$md.Add('')
$md.Add('Note for Claude: the text below was made automatically by Whisper (speech to text), with no human check.')
$md.Add('English technical words may be misheard or written in Arabic letters (for example "cloud code" for Claude Code, "get" for git).')
$md.Add('Lines marked [?] are doubtful: they end after the video ends, they look like a sound label such as *phone rings*, or they have no letter or digit (like a lone ".").')
$md.Add('Nothing was removed or corrected.')
$md.Add('Do what the user marked with x. If nothing is marked, ask the user first.')
foreach ($t in @('', '## What I want from Claude (put x inside the brackets)', '- [ ] Link the ideas between videos', '- [ ] Organize the ideas by topic', '- [ ] Answer my questions and give notes', '- [ ] Explain each step for a beginner', '- Other:', '')) { $md.Add($t) }
$skippedLines = New-Object System.Collections.Generic.List[string]

$videos = 0
foreach ($r in @(Import-Csv -LiteralPath $textList.FullName -Encoding UTF8)) {
    $name = ([string]$r.file).Trim()
    if ([string]::IsNullOrWhiteSpace($name) -or $name -match '[\\/:]' -or $name -match '\.\.') {
        Write-Host "SKIP name not allowed: ${name}"; $skippedLines.Add("- ${name}: name not allowed"); continue
    }
    $status = [string]$r.status
    if ($status -ne 'ok' -and $status -ne 'exists') {
        Write-Host "SKIP status ${status}: ${name}"; $skippedLines.Add("- ${name}: status ${status}"); continue
    }
    $srt = Join-Path $workDir ($name + '.srt')
    if (-not (Test-Path -LiteralPath $srt -PathType Leaf)) {
        Write-Host "SKIP srt not in work: ${name}.srt"; $skippedLines.Add("- ${name}: srt not in work"); continue
    }
    $hasDuration = $durations.ContainsKey($name)
    $duration = 0.0
    if ($hasDuration) { $duration = $durations[$name] }

    $content = [string](Get-Content -LiteralPath $srt -Encoding UTF8 -Raw)
    $blocks = $content.TrimStart([char]0xFEFF) -split '\r?\n\s*\r?\n'
    $sentences = New-Object System.Collections.Generic.List[string]
    $marked = 0
    foreach ($b in $blocks) {
        $blines = @($b -split '\r?\n' | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' })
        $timeIndex = -1
        for ($i = 0; $i -lt $blines.Count; $i++) { if ($blines[$i] -match $timeRx) { $timeIndex = $i; break } }
        if ($timeIndex -lt 0 -or $timeIndex -ge $blines.Count - 1) { continue }
        $m = [regex]::Match($blines[$timeIndex], $timeRx)
        $start = Get-Seconds $m 1
        $end = Get-Seconds $m 5
        $text = ($blines[($timeIndex + 1)..($blines.Count - 1)] -join ' ').Trim()
        $doubt = ($hasDuration -and $end -gt $duration + 1) -or ($text -match '^\*.*\*$') -or ($text -match '^\[.*\]$') -or ($text -match '^\(.*\)$') -or ($text -notmatch '[\p{L}\p{N}]')
        $mark = ''
        if ($doubt) { $mark = '[?] '; $marked++ }
        $sentences.Add('- ' + $mark + '[' + (Format-Clock $start) + '] ' + $text)
    }

    $md.Add('')
    $md.Add('## ' + $name)
    if ($hasDuration) { $md.Add('Duration: ' + $duration.ToString('0.00', $culture) + ' sec (' + (Format-Clock $duration) + ')') }
    else { $md.Add('Duration: unknown') }
    $md.Add('')
    foreach ($s in $sentences) { $md.Add($s) }
    Write-Host "VIDEO: ${name}  sentences: $($sentences.Count)  marked [?]: ${marked}"
    $videos++
}

$md.Add('')
$md.Add('## Skipped videos')
if ($skippedLines.Count -eq 0) { $md.Add('- none') } else { foreach ($s in $skippedLines) { $md.Add($s) } }
Write-Host "Done. Videos: $videos  Skipped: $($skippedLines.Count)"

$handoffPath = Join-Path $outDir ('handoff-{0}.md' -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
if (Test-Path -LiteralPath $handoffPath) {
    Write-Host "STOP: name already exists, nothing written: $handoffPath" -ForegroundColor Red
    exit 1
}
if ($Run) {
    Set-Content -LiteralPath $handoffPath -Value $md.ToArray() -Encoding UTF8
    Write-Host "Handoff written: $handoffPath" -ForegroundColor Green
}
else {
    Write-Host "Would write: $handoffPath"
    Write-Host 'Dry run - nothing written.' -ForegroundColor Cyan
}
