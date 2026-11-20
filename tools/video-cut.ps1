# video-cut.ps1 - removes the silent parts of one video, with ffmpeg only (no AI). The original is never changed.
# Usage: video-cut.ps1 -Name video-07.mp4 [-NoiseDb -35] [-MinSilence 0.6] [-Run]
# The video is looked up in <Inbox>, then in <Done>. Its srt is <Work>\<video name>.srt (paths from config-lib.ps1).
# ffmpeg silencedetect finds the silences: quieter than -NoiseDb dB for at least -MinSilence seconds.
# Each silence goes, except 0.15 seconds at each side of it, so the words keep their start and end.
# A silence within 0.25 s of the start or the end of the video goes whole (0.15 kept only next to speech).
# The cut re-encodes the video (trim, atrim and concat), so it is exact and not on keyframes.
# Writes a new folder out\cut-yyyyMMdd-HHmmss (STOP if it exists) with the cut video (same name), its new
# srt (times moved to the cut video; a sentence left with no time is dropped) and cut.csv (the parts kept).
# No srt: WARNING, the video is still cut. No audio: STOP. No silence to remove: STOP "nothing to cut".
# More than half removed: WARNING. Needs frames-lib.ps1, edit-lib.ps1 and config-lib.ps1 next to this script.
# Default is a dry run: prints the silences, what goes and the new length, writes nothing. With -Run it writes
# the video to .part, renames it, writes the srt and cut.csv, then opens the folder with the video selected.
# Never overwrites, never deletes. ASCII only, works on Windows PowerShell 5.1.
param(
    [string]$Name,
    [double]$NoiseDb = -35,
    [double]$MinSilence = 0.6,
    [switch]$Run
)
$ErrorActionPreference = 'Stop'

$culture = [System.Globalization.CultureInfo]::InvariantCulture
$pad = 0.15
$maxParts = 200

function Stop-Tool([string]$msg) { Write-Host "STOP: $msg" -ForegroundColor Red; exit 1 }
function Format-Sec([double]$s) { return $s.ToString('0.00', $culture) }

foreach ($lib in @('frames-lib.ps1', 'edit-lib.ps1', 'config-lib.ps1')) {
    $libPath = Join-Path $PSScriptRoot $lib
    if (-not (Test-Path -LiteralPath $libPath -PathType Leaf)) { Stop-Tool "helper file missing next to the script: $libPath" }
    . $libPath
}
try { $cfg = Get-VideoConfig } catch { Write-Host $_.Exception.Message -ForegroundColor Red; exit 1 }
$inbox = $cfg.Inbox
$doneDir = $cfg.Done
$workDir = $cfg.Work
$outDir = $cfg.Out
try { $ffmpeg = Get-FfmpegTool 'ffmpeg' $cfg } catch { Write-Host $_.Exception.Message -ForegroundColor Red; exit 1 }

if (-not (Test-NameAllowed $Name)) { throw "Use -Name with a video file name only, like video-07.mp4: $Name" }
if ($NoiseDb -lt -90 -or $NoiseDb -gt -10) { throw "-NoiseDb must be between -90 and -10: $NoiseDb" }
if ($MinSilence -le 2 * $pad -or $MinSilence -gt 30) { throw "-MinSilence must be more than $(2 * $pad) and at most 30: $MinSilence" }
if (-not (Test-Path -LiteralPath $ffmpeg -PathType Leaf)) { throw "ffmpeg not found: $ffmpeg" }
foreach ($d in @($workDir, $outDir)) { if (-not (Test-Path -LiteralPath $d -PathType Container)) { throw "Folder not found: $d" } }

$src = Find-Video $Name $inbox $doneDir
if (-not $src) { Stop-Tool "video not in inbox or done: $Name" }
$srt = Join-Path $workDir ($Name + '.srt')
$hasSrt = Test-Path -LiteralPath $srt -PathType Leaf
Write-Host "Video: $src"
if ($hasSrt) { Write-Host "Srt: $srt" } else { Write-Host "WARNING: no srt in work, the video is cut without a new srt: $srt" -ForegroundColor Yellow }

# Silences: ffmpeg reads the audio only and writes nothing (-f null).
$filter = 'silencedetect=noise=' + $NoiseDb.ToString('0.##', $culture) + 'dB:d=' + $MinSilence.ToString('0.###', $culture)
$probe = Invoke-Ffmpeg $ffmpeg ('-hide_banner -nostdin -nostats -i "' + $src + '" -vn -af ' + $filter + ' -f null -') 600000
if (-not $probe.err) { Stop-Tool "ffmpeg did not run or ran out of time on $Name" }
if ($probe.err -notmatch 'Stream #\d+:\d+.*: Audio:') { Stop-Tool "no audio in this video, nothing to listen to: $Name" }
if (-not $probe.ok) { Stop-Tool "ffmpeg silencedetect failed on $Name" }
$duration = Get-Duration $probe.err
if ($duration -le 0) { Stop-Tool "could not read the length of $Name" }
$silences = Get-Silences $probe.err $duration
$keeps = Get-KeepSegments $silences $duration $pad
$newLength = 0.0
foreach ($k in $keeps) { $newLength += $k.e - $k.s }
$removed = $duration - $newLength

Write-Host ('Length: ' + (Format-Sec $duration) + ' s  noise: ' + $NoiseDb + ' dB  min silence: ' + $MinSilence + ' s  pad: ' + $pad + ' s')
foreach ($si in $silences) { Write-Host ('  silence ' + (Format-Sec $si.s) + ' - ' + (Format-Sec $si.e) + '  (' + (Format-Sec ($si.e - $si.s)) + ' s)') }
Write-Host ('Silences: ' + $silences.Count + '  removed: ' + (Format-Sec $removed) + ' s  new length: ' + (Format-Sec $newLength) + ' s  parts kept: ' + $keeps.Count)
if ($keeps.Count -eq 0) { Stop-Tool "the whole video is silent at $NoiseDb dB, nothing written" }
if ($removed -lt 0.05) { Stop-Tool 'nothing to cut: no silence long enough, nothing written' }
if ($keeps.Count -gt $maxParts) { Stop-Tool "too many parts ($($keeps.Count)), try a bigger -MinSilence" }
if ($removed -gt $duration / 2) { Write-Host 'WARNING: more than half of the video goes. The sound may be quiet: try a lower -NoiseDb, like -45.' -ForegroundColor Yellow }

$cutSrt = $null
if ($hasSrt) {
    $cutSrt = Get-CutSrt (Get-FrameEntries $srt) $keeps
    Write-Host "New srt sentences: $([math]::Floor($cutSrt.lines.Count / 4))"
    foreach ($t in $cutSrt.dropped) { Write-Host "  dropped (all inside a removed part): $t" -ForegroundColor Yellow }
}

$cutDir = Join-Path $outDir ('cut-{0}' -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
if (Test-Path -LiteralPath $cutDir) { Stop-Tool "folder already exists, nothing written: $cutDir" }
$dest = Join-Path $cutDir $Name
if (-not $Run) {
    Write-Host "Would write: $dest (with its srt and cut.csv)"
    Write-Host 'Dry run - nothing written.' -ForegroundColor Cyan
    exit 0
}

# The cut: one trim and atrim per kept part, then concat. Video to x264, audio to aac.
$fc = New-Object System.Text.StringBuilder
$pairs = ''
for ($i = 0; $i -lt $keeps.Count; $i++) {
    $range = 'start=' + $keeps[$i].s.ToString('0.000', $culture) + ':end=' + $keeps[$i].e.ToString('0.000', $culture)
    [void]$fc.Append("[0:v]trim=$range,setpts=PTS-STARTPTS[v$i];[0:a]atrim=$range,asetpts=PTS-STARTPTS[a$i];")
    $pairs += "[v$i][a$i]"
}
[void]$fc.Append($pairs + 'concat=n=' + $keeps.Count + ':v=1:a=1[v][a]')
New-Item -ItemType Directory -Path $cutDir | Out-Null
$part = $dest + '.part'
Write-Host 'Cutting (re-encode, this can take a while)...'
$job = Invoke-Ffmpeg $ffmpeg ('-hide_banner -nostdin -nostats -n -i "' + $src + '" -filter_complex "' + $fc.ToString() + '" -map "[v]" -map "[a]" -c:v libx264 -crf 20 -preset medium -pix_fmt yuv420p -c:a aac -b:a 160k -movflags +faststart -f mp4 "' + $part + '"') 3600000
if (-not $job.ok -or -not (Test-Path -LiteralPath $part -PathType Leaf)) { Stop-Tool "ffmpeg cut failed. The .part file, if any, is left in: $cutDir" }
Rename-Item -LiteralPath $part -NewName $Name

if ($hasSrt) { Set-Content -LiteralPath (Join-Path $cutDir ($Name + '.srt')) -Value $cutSrt.lines -Encoding UTF8 }
$csv = New-Object System.Collections.Generic.List[string]
$csv.Add('part,start,end,new_start')
$at = 0.0
for ($i = 0; $i -lt $keeps.Count; $i++) {
    $csv.Add(('{0},"{1}","{2}","{3}"' -f ($i + 1), $keeps[$i].s.ToString('0.000', $culture), $keeps[$i].e.ToString('0.000', $culture), $at.ToString('0.000', $culture)))
    $at += $keeps[$i].e - $keeps[$i].s
}
Set-Content -LiteralPath (Join-Path $cutDir 'cut.csv') -Value $csv.ToArray() -Encoding UTF8
Write-Host "Written: $dest" -ForegroundColor Green
Start-Process -FilePath 'explorer.exe' -ArgumentList ('/select,"' + $dest + '"')
