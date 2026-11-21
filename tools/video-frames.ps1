# video-frames.ps1 - optional tool, not part of the main video pipeline: take still frames.
# With -Name it works on one video (a name like video-04.mp4, not a path). Without -Name it works
# on the videos in the newest <Out>\text*.csv (rows with status=ok or exists).
# The video is looked up in <Inbox>, then in <Done> (paths from config-lib.ps1). It is never moved.
# One frame per sentence block of work\<video name>.srt. A sentence less than 2 seconds after the
# block before it, or past 40 frames, joins that block. The frame is taken in the middle between the
# block start and the next block start (the last block: the middle of its start and its end), so the
# screen matches the words. If that fails, it tries once at the block start.
# Frame name: <video name without extension>_<mm-ss>.jpg (the block start), all in a new folder
# out\frames-yyyyMMdd-HHmmss (STOP if it exists), with frames.csv (video,time,file,status,shot_sec).
# It also writes notes.md there: one block per good frame with the sentence and empty lines to fill.
# Needs frames-lib.ps1 and config-lib.ps1 next to this script.
# Default is a dry run: prints only. Add -Run to write. Writes only in the new folder.
# ASCII only, works on Windows PowerShell 5.1.
param(
    [string]$Name,
    [switch]$Run
)
$ErrorActionPreference = 'Stop'

$libPath = Join-Path $PSScriptRoot 'frames-lib.ps1'
if (-not (Test-Path -LiteralPath $libPath -PathType Leaf)) { Write-Host "STOP: helper file missing next to the script: $libPath" -ForegroundColor Red; exit 1 }
. $libPath
$cfgLib = Join-Path $PSScriptRoot 'config-lib.ps1'
if (-not (Test-Path -LiteralPath $cfgLib -PathType Leaf)) { Write-Host "STOP: helper file missing next to the script: $cfgLib" -ForegroundColor Red; exit 1 }
. $cfgLib
try { $cfg = Get-VideoConfig } catch { Write-Host $_.Exception.Message -ForegroundColor Red; exit 1 }

$inbox = $cfg.Inbox
$doneDir = $cfg.Done
$workDir = $cfg.Work
$outDir = $cfg.Out
try { $ffmpeg = Get-FfmpegTool 'ffmpeg' $cfg } catch { Write-Host $_.Exception.Message -ForegroundColor Red; exit 1 }
$culture = [System.Globalization.CultureInfo]::InvariantCulture
$minGap = 2.0
$maxFrames = 40
$timeoutMs = 60000

if (-not (Test-Path -LiteralPath $ffmpeg -PathType Leaf)) { throw "ffmpeg not found: $ffmpeg" }
foreach ($d in @($workDir, $outDir)) {
    if (-not (Test-Path -LiteralPath $d -PathType Container)) { throw "Folder not found: $d" }
}

if ($Name) {
    if (-not (Test-NameAllowed $Name)) { throw "Name not allowed (a video name only, no path or filter characters): $Name" }
    $names = @($Name)
    Write-Host "Video: $Name"
}
else {
    $textList = Get-ChildItem -LiteralPath $outDir -File -Filter 'text*.csv' | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if (-not $textList) { throw "No text*.csv in $outDir. Run video-text.ps1 -Run first, or use -Name." }
    Write-Host "Text list: $($textList.Name)"
    $names = @(Import-Csv -LiteralPath $textList.FullName -Encoding UTF8 | Where-Object { $_.status -eq 'ok' -or $_.status -eq 'exists' } | ForEach-Object { ([string]$_.file).Trim() })
}

$framesDir = Join-Path $outDir ('frames-{0}' -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
if (Test-Path -LiteralPath $framesDir) {
    Write-Host "STOP: folder already exists, nothing written: $framesDir" -ForegroundColor Red
    exit 1
}
if ($Run) { New-Item -ItemType Directory -Path $framesDir | Out-Null }

$lines = New-Object System.Collections.Generic.List[string]
$lines.Add('video,time,file,status,shot_sec')
$notes = New-Object System.Collections.Generic.List[string]
foreach ($t in @("This is the user's notes file for the frames in this folder.", "Under each frame: the image name, the sentence that was said, and room for the user's note and question. The Explain line is left empty for Claude to fill with a simple explanation for a beginner.", 'Do what the user marked with x. If nothing is marked, ask the user first.', '', '## What I want from Claude (put x inside the brackets)', '- [ ] Link the ideas between videos', '- [ ] Organize the ideas by topic', '- [ ] Answer my questions and give notes', '- [ ] Explain each step for a beginner', '- Other:', '')) { $notes.Add($t) }
$planned = 0
$totalOk = 0
$totalErr = 0
foreach ($n in $names) {
    if (-not (Test-NameAllowed $n)) { Write-Host "SKIP name not allowed: ${n}"; continue }
    $srt = Join-Path $workDir ($n + '.srt')
    if (-not (Test-Path -LiteralPath $srt -PathType Leaf)) { Write-Host "SKIP srt not in work: ${n}.srt"; continue }
    $src = Join-Path $inbox $n
    $where = 'inbox'
    if (-not (Test-Path -LiteralPath $src -PathType Leaf)) { $src = Join-Path $doneDir $n; $where = 'done' }
    if (-not (Test-Path -LiteralPath $src -PathType Leaf)) { Write-Host "SKIP video not in inbox or done: ${n}"; continue }

    $entries = Get-FrameEntries $srt
    $picked = Select-Frames $entries $minGap $maxFrames
    $planned += $picked.Count
    $base = [System.IO.Path]::GetFileNameWithoutExtension($n)
    $labels = @($picked | ForEach-Object { $t = [int][math]::Floor($_.start); '{0:00}-{1:00}' -f [math]::Floor($t / 60), ($t % 60) })
    Write-Host "VIDEO: ${n} (found in ${where})  sentences: $($entries.Count)  frames: $($picked.Count)"
    Write-Host ('  times: ' + ($labels -join ' '))
    Write-Host ('  shots: ' + (@($picked | ForEach-Object { $_.shot.ToString('0.0', $culture) }) -join ' '))

    for ($i = 0; $i -lt $picked.Count; $i++) {
        $file = $base + '_' + $labels[$i] + '.jpg'
        $row = '"' + $n.Replace('"', '""') + '","' + $labels[$i] + '","' + $file.Replace('"', '""') + '"'
        if (-not $Run) { continue }
        $dest = Join-Path $framesDir $file
        $shot = $picked[$i].shot
        $ok = Save-Frame $ffmpeg $src $shot $dest $timeoutMs
        if (-not $ok -and -not (Test-Path -LiteralPath $dest)) {
            $shot = $picked[$i].start
            $ok = Save-Frame $ffmpeg $src $shot $dest $timeoutMs
            if ($ok) { Write-Host "RETRY at the block start worked: ${file}" -ForegroundColor Yellow }
        }
        $shotCell = ',"' + $shot.ToString('0.000', $culture) + '"'
        if ($ok) {
            $lines.Add($row + ',"ok"' + $shotCell); $totalOk++
            foreach ($t in @(('## ' + $file + '  [' + $labels[$i].Replace('-', ':') + ']'), ('- Said: ' + $picked[$i].text), '- My note:', '- My question:', '- Explain (for beginners, Claude fills this):', '')) { $notes.Add($t) }
        }
        else {
            Write-Host "ERROR frame failed: ${file}" -ForegroundColor Yellow
            $lines.Add($row + ',"error"' + $shotCell); $totalErr++
        }
    }
}

if ($Run) {
    Set-Content -LiteralPath (Join-Path $framesDir 'frames.csv') -Value $lines.ToArray() -Encoding UTF8
    $notesPath = Join-Path $framesDir 'notes.md'
    if (Test-Path -LiteralPath $notesPath) { Write-Host "notes.md already exists, not written: $notesPath" -ForegroundColor Yellow }
    else { Set-Content -LiteralPath $notesPath -Value $notes.ToArray() -Encoding UTF8 }
    Write-Host "Done. Frames OK: $totalOk  Error: $totalErr"
    Write-Host "Written: $framesDir" -ForegroundColor Green
}
else {
    Write-Host "Would write: $framesDir"
    Write-Host "Would write notes.md with $planned blocks."
    Write-Host 'Dry run - nothing written.' -ForegroundColor Cyan
}
