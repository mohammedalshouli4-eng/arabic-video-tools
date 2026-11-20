# video-subs.ps1 - burns the srt text onto one video, with ffmpeg and libass only (no AI). The original is never changed.
# Usage: video-subs.ps1 -Name video-06.mp4 [-Cut] [-Lang ar] [-Position bottom] [-FontSize 12] [-MarginV 30] [-MaxWords 4] [-Run]
# Without -Cut: the video from <Inbox> (else <Done>), and its srt from <Work>\<video name>.srt.
# With -Cut: the video and its srt from the newest out\cut-* folder that has this video (made by video-cut.ps1).
# -Lang ar (two small letters a-z) burns <video name>.ar.srt from the same place instead, like an Arabic
# translation for an English video. If that file is not there: STOP, with the exact path it looked for.
# Only with -Lang ar: a missing .ar.srt falls back to the normal srt in the same place, with a yellow WARNING.
# The text: Arial, centered, white with a dark outline. -Position bottom (default), middle or top sets the
# libass Alignment (2, 10 or 6, the old SSA numbers that force_style reads). -FontSize is in subtitle units, where the video height is 288 units, so 12
# is about 4 percent of the height: readable on a vertical video.
# -MarginV is the space from the bottom (or from the top with -Position top), in the same units. Default 30.
# With -Position middle it has no effect.
# -MaxWords splits each sentence into short pieces of up to that many words, timed by their letters (0 keeps
# whole sentences). The split srt is written next to the new video and burned; the source srt is not changed.
# With -Lang ar each text line of that written srt is wrapped in RLE ... PDF, so the whole line is right to left.
# ffmpeg runs from <Videos> with a relative srt path, because the subtitles filter breaks on a drive letter.
# Names with filter characters are refused (Test-NameAllowed). No srt, or an srt with no sentence: STOP.
# Writes a new folder out\subs-yyyyMMdd-HHmmss (STOP if it exists) with the video (same name), re-encoded
# like video-cut (x264 crf 20, aac). Needs frames-lib.ps1, edit-lib.ps1 and config-lib.ps1 next to this script.
# Paths (Videos, Inbox, Done, Out) come from config-lib.ps1; work and out are folders inside Videos.
# Default is a dry run: prints the video, the srt, the sentence count and the output, writes nothing.
# With -Run it writes to .part, renames it, then opens the folder with the video selected.
# Never overwrites, never deletes. ASCII only, works on Windows PowerShell 5.1.
param(
    [string]$Name,
    [switch]$Cut,
    [string]$Lang = '',
    [string]$Position = 'bottom',
    [int]$FontSize = 12,
    [int]$MarginV = 30,
    [int]$MaxWords = 4,
    [switch]$Run
)
$ErrorActionPreference = 'Stop'

function Stop-Tool([string]$msg) { Write-Host "STOP: $msg" -ForegroundColor Red; exit 1 }

foreach ($lib in @('frames-lib.ps1', 'edit-lib.ps1', 'config-lib.ps1')) {
    $libPath = Join-Path $PSScriptRoot $lib
    if (-not (Test-Path -LiteralPath $libPath -PathType Leaf)) { Stop-Tool "helper file missing next to the script: $libPath" }
    . $libPath
}
try { $cfg = Get-VideoConfig } catch { Write-Host $_.Exception.Message -ForegroundColor Red; exit 1 }
$videosDir = $cfg.Videos
$inbox = $cfg.Inbox
$doneDir = $cfg.Done
$outDir = $cfg.Out
try { $ffmpeg = Get-FfmpegTool 'ffmpeg' $cfg } catch { Write-Host $_.Exception.Message -ForegroundColor Red; exit 1 }

if (-not (Test-NameAllowed $Name)) { throw "Use -Name with a video file name only, like video-06.mp4: $Name" }
if ($Lang -and $Lang -cnotmatch '^[a-z]{2}\z') { throw "-Lang must be two small letters a-z, like ar: $Lang" }
$srtEnd = '.srt'
if ($Lang) { $srtEnd = '.' + $Lang + '.srt' }
if ($FontSize -lt 6 -or $FontSize -gt 40) { throw "-FontSize must be between 6 and 40: $FontSize" }
if ($MarginV -lt 0 -or $MarginV -gt 200) { throw "-MarginV must be between 0 and 200: $MarginV" }
if ($Position -cnotmatch '^(bottom|middle|top)\z') { throw "-Position must be bottom, middle or top: $Position" }
$alignment = @{ bottom = 2; middle = 10; top = 6 }[$Position]
if ($MaxWords -lt 0 -or $MaxWords -gt 20) { throw "-MaxWords must be between 0 and 20 (0 keeps whole sentences): $MaxWords" }
if (-not (Test-Path -LiteralPath $ffmpeg -PathType Leaf)) { throw "ffmpeg not found: $ffmpeg" }
if (-not (Test-Path -LiteralPath $outDir -PathType Container)) { throw "Folder not found: $outDir" }

# The srt path is kept relative to <Videos>, with forward slashes, for the subtitles filter.
if ($Cut) {
    $cutDir = Get-ChildItem -LiteralPath $outDir -Directory | Where-Object { $_.Name -cmatch '^cut-[0-9]{8}-[0-9]{6}$' -and (Test-Path -LiteralPath (Join-Path $_.FullName $Name) -PathType Leaf) } | Sort-Object Name -Descending | Select-Object -First 1
    if (-not $cutDir) { Stop-Tool "no out\cut-* folder has $Name. Run video-cut.ps1 -Run first." }
    $src = Join-Path $cutDir.FullName $Name
    $srtRel = 'out/' + $cutDir.Name + '/' + $Name + $srtEnd
}
else {
    $src = Find-Video $Name $inbox $doneDir
    if (-not $src) { Stop-Tool "video not in inbox or done: $Name" }
    $srtRel = 'work/' + $Name + $srtEnd
}
$srt = Join-Path $videosDir ($srtRel.Replace('/', '\'))
if ($Lang -eq 'ar' -and -not (Test-Path -LiteralPath $srt -PathType Leaf)) {
    $plainRel = $srtRel.Substring(0, $srtRel.Length - $srtEnd.Length) + '.srt'
    $plain = Join-Path $videosDir ($plainRel.Replace('/', '\'))
    if (Test-Path -LiteralPath $plain -PathType Leaf) { Write-Host 'WARNING: no .ar.srt, using the normal srt as Arabic.' -ForegroundColor Yellow; $srtRel = $plainRel; $srt = $plain }
}
if (-not (Test-Path -LiteralPath $srt -PathType Leaf)) { Stop-Tool "no srt, nothing to burn. It must be here: $srt" }
$entries = Get-FrameEntries $srt
if ($entries.Count -eq 0) { Stop-Tool "the srt has no sentence: $srt" }
Write-Host "Video: $src"
$pieces = Split-SrtEntries $entries $MaxWords
$langText = 'same as the video'
if ($Lang) { $langText = $Lang }
Write-Host "Srt: $srt  lang: $langText  sentences: $($entries.Count)  pieces: $($pieces.Count)"
$marginText = "margin $MarginV"
if ($Position -eq 'middle') { $marginText = 'margin not used' }
Write-Host "Style: Arial, size $FontSize, $Position center, $marginText, max words $MaxWords"

$subsDir = Join-Path $outDir ('subs-{0}' -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
if (Test-Path -LiteralPath $subsDir) { Stop-Tool "folder already exists, nothing written: $subsDir" }
$dest = Join-Path $subsDir $Name
if (-not $Run) {
    Write-Host "Would write: $dest"
    Write-Host 'Dry run - nothing written.' -ForegroundColor Cyan
    exit 0
}

$style = 'FontName=Arial,FontSize=' + $FontSize + ',Alignment=' + $alignment + ',MarginV=' + $MarginV + ',BorderStyle=1,Outline=2,Shadow=0'
$vf = "subtitles=filename='" + $srtRel + "':force_style='" + $style + "'"
New-Item -ItemType Directory -Path $subsDir | Out-Null
if ($Lang -eq 'ar') {
    # Each text line is wrapped in RLE (U+202B) ... PDF (U+202C): libass lays a line out from the left, and this
    # makes the whole line right to left, English words and the last dot or comma included. Never added twice.
    # The check must be Ordinal: the normal (culture) StartsWith ignores these marks and always says they are there.
    $rle = [string][char]0x202B
    $pdf = [string][char]0x202C
    $pieces = @($pieces | ForEach-Object {
        $t = [string]$_.text
        if (-not $t.StartsWith($rle, [System.StringComparison]::Ordinal)) { $t = $rle + $t }
        if (-not $t.EndsWith($pdf, [System.StringComparison]::Ordinal)) { $t = $t + $pdf }
        [pscustomobject]@{ start = $_.start; end = $_.end; text = $t }
    })
}
if ($MaxWords -gt 0 -or $Lang -eq 'ar') {
    # Get-CutSrt with one part over all time keeps the times as they are: it only writes the srt lines.
    $split = Get-CutSrt $pieces @([pscustomobject]@{ s = 0.0; e = [double]::MaxValue })
    if ($split.dropped.Count -gt 0) { Write-Host "WARNING: $($split.dropped.Count) pieces under 0.05 s left out" -ForegroundColor Yellow }
    Set-Content -LiteralPath ($dest + $srtEnd) -Value $split.lines -Encoding UTF8
    $srtRel = 'out/' + (Split-Path -Leaf $subsDir) + '/' + $Name + $srtEnd
    $vf = "subtitles=filename='" + $srtRel + "':force_style='" + $style + "'"
}
$part = $dest + '.part'
Write-Host 'Burning the text (re-encode, this can take a while)...'
# ffmpeg starts in the current folder of this process, so it is set to <Videos> for the run only.
$here = [System.IO.Directory]::GetCurrentDirectory()
[System.IO.Directory]::SetCurrentDirectory($videosDir)
try {
    $job = Invoke-Ffmpeg $ffmpeg ('-hide_banner -nostdin -nostats -n -i "' + $src + '" -vf "' + $vf + '" -map 0:v:0 -map 0:a:0? -c:v libx264 -crf 20 -preset medium -pix_fmt yuv420p -c:a aac -b:a 160k -movflags +faststart -f mp4 "' + $part + '"') 3600000
}
finally { [System.IO.Directory]::SetCurrentDirectory($here) }
if (-not $job.ok -or -not (Test-Path -LiteralPath $part -PathType Leaf)) {
    foreach ($l in @(($job.err -split "`r?`n") | Where-Object { $_.Trim() } | Select-Object -Last 5)) { Write-Host "  ffmpeg: $l" -ForegroundColor Yellow }
    Stop-Tool "ffmpeg failed. The .part file, if any, is left in: $subsDir"
}
Rename-Item -LiteralPath $part -NewName $Name
Write-Host "Written: $dest" -ForegroundColor Green
Start-Process -FilePath 'explorer.exe' -ArgumentList ('/select,"' + $dest + '"')
