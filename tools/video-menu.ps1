# video-menu.ps1 - one numbered menu for the video tools, so each tool is one number away.
# Usage: video-menu.ps1 [-Run]. Without -Run (MODE DRY) it asks the same questions but only prints
# "DRY: <command>", and never runs a tool or moves a file. With -Run (MODE RUN) it really runs them.
# Each tool runs in its own process: powershell -ExecutionPolicy Bypass -File "<tool>" <arguments>, so a
# tool that ends with exit never closes the menu. The full command is printed before it runs.
# Names as each tool's param block wants them: video-frames, video-moments, video-cut and video-subs get
# video-NN.mp4; video-upload, video-card-save and video-summary get video-NN; video-run takes no name.
# Option 9 moves one video from inbox to done with Move-Item (no -Force), and stops if done has that name.
# Never deletes, never overwrites, never changes the tools. Needs menu-lib.ps1 and config-lib.ps1 next to it.
# ASCII only, works on Windows PowerShell 5.1.
param(
    [switch]$Run
)
$ErrorActionPreference = 'Stop'

$libPath = Join-Path $PSScriptRoot 'menu-lib.ps1'
if (-not (Test-Path -LiteralPath $libPath -PathType Leaf)) { Write-Host "STOP: helper file missing next to the script: $libPath" -ForegroundColor Red; exit 1 }
. $libPath
$cfgLib = Join-Path $PSScriptRoot 'config-lib.ps1'
if (-not (Test-Path -LiteralPath $cfgLib -PathType Leaf)) { Write-Host "STOP: helper file missing next to the script: $cfgLib" -ForegroundColor Red; exit 1 }
. $cfgLib
try { $cfg = Get-VideoConfig } catch { Write-Host $_.Exception.Message -ForegroundColor Red; exit 1 }

# The same folders the tools use, from the settings (config-lib.ps1).
$inbox = $cfg.Inbox
$doneDir = $cfg.Done
$live = [bool]$Run
$mode = 'MODE DRY (nothing runs, commands are only printed)'
$modeColor = 'Cyan'
if ($live) { $mode = 'MODE RUN'; $modeColor = 'Green' }
$menu = @(
    '1  Full pipeline on inbox (video-run)', '2  Frames for a video (video-frames)', '3  Moments (video-moments)',
    '4  Zip for upload (video-upload)', '5  Save a card (video-card-save)', '6  Pack cards (video-card-pack)',
    '7  Remove silences (video-cut)', '8  Burn captions (video-subs)', '9  Move a video from inbox to done',
    '10 Summary video (video-summary)', '0  Exit'
)
function Get-Tool([string]$file) { return (Join-Path $PSScriptRoot $file) }
# Option number -> tool file. An option whose file is not next to the menu is hidden. 9 and 0 always show.
# The numbers never change between versions, even with gaps.
$tools = @{ '1' = 'video-run.ps1'; '2' = 'video-frames.ps1'; '3' = 'video-moments.ps1'; '4' = 'video-upload.ps1'
    '5' = 'video-card-save.ps1'; '6' = 'video-card-pack.ps1'; '7' = 'video-cut.ps1'; '8' = 'video-subs.ps1'; '10' = 'video-summary.ps1' }
function Test-Option([string]$n) { return (-not $tools.ContainsKey($n)) -or (Test-Path -LiteralPath (Get-Tool $tools[$n]) -PathType Leaf) }
function Write-Hidden([string]$n) { Write-Host "Option $n is not in this version." -ForegroundColor Yellow }
$askName = 'Video name, like video-07 or 7 (0 = back)'
# A number typed at the end-of-tool pause is kept here and used as the next choice.
$pending = ''

while ($true) {
    Write-Host $mode -ForegroundColor $modeColor
    foreach ($m in $menu) { if (Test-Option ($m -split ' ')[0]) { Write-Host "  $m" } }
    if ($pending) { $choice = $pending; $pending = ''; Write-Host "Choose a number: $choice" }
    else { $choice = ([string](Read-Host 'Choose a number')).Trim() }
    if ($choice -eq '0') { break }
    if ($choice -notmatch '^([1-9]|10)$') { Write-Host 'Choose a number from 0 to 10.' -ForegroundColor Yellow; Write-Host ''; continue }
    if (-not (Test-Option $choice)) { Write-Hidden $choice; Write-Host ''; continue }
    # A name answer of 0 sets $back: nothing runs and the menu comes back without the Enter pause.
    $back = $false
    try {
        switch ($choice) {
            '1' { Invoke-ToolFlow (Get-Tool 'video-run.ps1') @() $live }
            '2' {
                $b = Read-VideoBase 'Video name, like video-07 or 7 (Enter = all videos in the newest text list, 0 = back)' $true
                if ($null -eq $b) { $back = $true; break }
                $a = @()
                if ($b) { $a = @('-Name', "$b.mp4") }
                Invoke-ToolFlow (Get-Tool 'video-frames.ps1') $a $live
            }
            '3' {
                $b = Read-VideoBase $askName $false
                if ($null -eq $b) { $back = $true; break }
                Invoke-ToolFlow (Get-Tool 'video-moments.ps1') @('-Name', "$b.mp4") $live
            }
            '4' {
                $b = Read-VideoBase $askName $false
                if ($null -eq $b) { $back = $true; break }
                Invoke-ToolFlow (Get-Tool 'video-upload.ps1') @('-Name', $b) $live
            }
            '5' {
                $b = Read-VideoBase 'Card name, like video-07 or 7 (0 = back)' $false
                if ($null -eq $b) { $back = $true; break }
                Invoke-ToolFlow (Get-Tool 'video-card-save.ps1') @('-Name', $b) $live
            }
            '6' {
                $a = Read-PackArgs
                if ($null -eq $a) { Write-Host 'Nothing run.' } else { Invoke-ToolFlow (Get-Tool 'video-card-pack.ps1') $a $live }
            }
            '7' {
                $b = Read-VideoBase $askName $false
                if ($null -eq $b) { $back = $true; break }
                Invoke-ToolFlow (Get-Tool 'video-cut.ps1') @('-Name', "$b.mp4") $live
            }
            '8' {
                $b = Read-VideoBase $askName $false
                if ($null -eq $b) { $back = $true; break }
                $a = @('-Name', "$b.mp4")
                if ((Test-Option '7') -and (Read-YesNo 'On the cut video (newest out\cut-*)?' $true)) { $a += '-Cut' }
                if (Read-YesNo 'Arabic captions (-Lang ar)?' $false) { $a += @('-Lang', 'ar') }
                $a += @('-Position', (Read-Position))
                Invoke-ToolFlow (Get-Tool 'video-subs.ps1') $a $live
            }
            '9' { Move-InboxToDone $inbox $doneDir $live }
            '10' {
                $b = Read-VideoBase $askName $false
                if ($null -eq $b) { $back = $true; break }
                $a = @('-Name', $b)
                $ids = ConvertTo-PlainText ([string](Read-Host 'Ideas, like 1,4,6 (Enter = first 3)'))
                if ($ids -and $ids -notmatch '^[0-9, ]+$') { Write-Host "Ideas take numbers like 1,4,6. Nothing run: $ids" -ForegroundColor Yellow; break }
                if ($ids) { $a += @('-Ideas', ($ids -replace '\s', '')) }
                Invoke-ToolFlow (Get-Tool 'video-summary.ps1') $a $live
            }
        }
    }
    catch {
        Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red
    }
    if (-not $back) {
        $next = ConvertTo-PlainText ([string](Read-Host 'Press Enter for the menu, or type a number'))
        if ($next -match '^([0-9]|10)$') { if (Test-Option $next) { $pending = $next } else { Write-Hidden $next } }
    }
    Write-Host ''
}
Write-Host 'Bye.'
