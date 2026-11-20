# menu-lib.ps1 - helper functions for video-menu.ps1, read with a dot (. menu-lib.ps1).
# Only functions: it runs nothing on its own. ASCII only, works on Windows PowerShell 5.1.

# Asks a y/n question. Enter gives $default. Any other answer asks again.
function Read-YesNo([string]$question, [bool]$default) {
    $hint = '(y/N)'
    if ($default) { $hint = '(Y/n)' }
    while ($true) {
        $a = ([string](Read-Host "$question $hint")).Trim().ToLower()
        if ($a -eq '') { return $default }
        if ($a -eq 'y' -or $a -eq 'yes') { return $true }
        if ($a -eq 'n' -or $a -eq 'no') { return $false }
        Write-Host 'Please answer y or n.' -ForegroundColor Yellow
    }
}

# Drops hidden direction marks and BOM, and turns Arabic digits (an Arabic keyboard types 7 as U+0667)
# into 0-9. String.Replace is Ordinal, so the hidden marks are really found.
function ConvertTo-PlainText([string]$s) {
    foreach ($v in @(0x61C, 0x200E, 0x200F, 0x202A, 0x202B, 0x202C, 0x202D, 0x202E, 0x2066, 0x2067, 0x2068, 0x2069, 0xFEFF)) { $s = $s.Replace([string][char]$v, '') }
    for ($i = 0; $i -lt 10; $i++) { $s = $s.Replace([string][char](0x660 + $i), [string]$i).Replace([string][char](0x6F0 + $i), [string]$i) }
    return $s.Trim()
}

# Asks for a video name and returns its base in small letters, like video-07 (no extension). Accepts 7, 07,
# video-07, video-07.mp4 or video-07.md. Only letters, digits, _ and - are kept, so nothing odd reaches a
# command. 0 returns $null: back to the menu. With $allowEmpty, Enter returns ''.
function Read-VideoBase([string]$question, [bool]$allowEmpty) {
    while ($true) {
        $a = ConvertTo-PlainText ([string](Read-Host $question))
        if ($a -eq '0') { return $null }
        if ($a -eq '' -and $allowEmpty) { return '' }
        if ($a -match '^[0-9]{1,3}$') { $a = 'video-{0:D2}' -f [int]$a }
        $a = ($a -replace '\.(mp4|md)$', '').ToLower()
        if ($a -cmatch '^[a-z0-9][a-z0-9_-]*\z') { return $a }
        Write-Host 'Use a name like video-07 (or just 7), or 0 to go back.' -ForegroundColor Yellow
    }
}

# Asks b, m or t (Enter = b) and returns bottom, middle or top for video-subs -Position.
function Read-Position {
    $map = @{ '' = 'bottom'; 'b' = 'bottom'; 'm' = 'middle'; 't' = 'top' }
    while ($true) {
        $a = ([string](Read-Host 'Position: b = bottom, m = middle, t = top (Enter = b)')).Trim().ToLower()
        if ($map.ContainsKey($a)) { return $map[$a] }
        Write-Host 'Answer b, m or t.' -ForegroundColor Yellow
    }
}

# Asks -Names and -Topic for video-card-pack. Both optional: Enter on both = all cards.
# Returns the argument list, or $null if a value has characters a card name or topic never has.
function Read-PackArgs {
    $out = @()
    $names = ConvertTo-PlainText ([string](Read-Host 'Names, like video-05,video-08 (Enter = no names)'))
    if ($names) {
        foreach ($n in ($names -split ',')) {
            if ($n.Trim() -cnotmatch '^[A-Za-z0-9][A-Za-z0-9_-]*(\.md)?\z') { Write-Host "Not a card name: $n" -ForegroundColor Yellow; return $null }
        }
        $out += @('-Names', ($names -replace '\s', ''))
    }
    $topic = ConvertTo-PlainText ([string](Read-Host 'Topic, like wsl (Enter = no topic)'))
    if ($topic) {
        if ($topic -cnotmatch '^[A-Za-z0-9_-]+\z') { Write-Host "Not a topic: $topic" -ForegroundColor Yellow; return $null }
        $out += @('-Topic', $topic)
    }
    return , $out
}

# The command as it is shown: powershell -ExecutionPolicy Bypass -File "<tool>" <arguments>.
function Format-ToolCommand([string]$tool, [string[]]$toolArgs) {
    return ('powershell -ExecutionPolicy Bypass -File "' + $tool + '" ' + (@($toolArgs) -join ' ')).TrimEnd()
}

# Runs one tool in its own powershell process, so a tool that ends with exit never closes the menu.
# In DRY mode ($live false) it only prints the command.
function Invoke-ToolOnce([string]$tool, [string[]]$toolArgs, [bool]$live) {
    $text = Format-ToolCommand $tool $toolArgs
    if (-not $live) { Write-Host "DRY: $text" -ForegroundColor Cyan; return }
    Write-Host "RUN: $text" -ForegroundColor Green
    & powershell.exe -ExecutionPolicy Bypass -File $tool @toolArgs
    Write-Host "Tool finished, exit code: $LASTEXITCODE"
}

# Trial first? (Enter = n). n: runs the tool with -Run. y: runs it without -Run, then asks
# Run now? (Enter = n) and runs it with -Run only on y. A trial that ends with an exit code other
# than 0 stops here, without the question. In DRY mode nothing ran, so there is no exit code to check.
function Invoke-ToolFlow([string]$tool, [string[]]$toolArgs, [bool]$live) {
    $base = @($toolArgs)
    if (Read-YesNo 'Trial first?' $false) {
        Invoke-ToolOnce $tool $base $live
        if ($live -and $LASTEXITCODE -ne 0) { Write-Host "Trial failed (exit code $LASTEXITCODE), not running." -ForegroundColor Yellow; return }
        if (-not (Read-YesNo 'Run now?' $false)) { return }
    }
    Invoke-ToolOnce $tool ($base + @('-Run')) $live
}

# Option 9: lists the files in inbox with numbers, asks for one, asks again, then moves it to done
# with Move-Item (no -Force). Stops if done already has that name. In DRY mode it only prints the Move-Item.
function Move-InboxToDone([string]$inbox, [string]$doneDir, [bool]$live) {
    $files = @(Get-ChildItem -LiteralPath $inbox -File | Sort-Object Name)
    if ($files.Count -eq 0) { Write-Host "inbox is empty: $inbox"; return }
    for ($i = 0; $i -lt $files.Count; $i++) { Write-Host ('  {0}) {1}' -f ($i + 1), $files[$i].Name) }
    $pick = ([string](Read-Host 'Number (Enter = back)')).Trim()
    if ($pick -notmatch '^[0-9]{1,4}$' -or [int]$pick -lt 1 -or [int]$pick -gt $files.Count) { Write-Host 'Nothing moved.'; return }
    $f = $files[[int]$pick - 1]
    $dest = Join-Path $doneDir $f.Name
    if (Test-Path -LiteralPath $dest) { Write-Host "STOP: done already has $($f.Name). Nothing moved." -ForegroundColor Red; return }
    if (-not (Read-YesNo "Move $($f.Name) to done?" $false)) { Write-Host 'Nothing moved.'; return }
    $text = 'Move-Item -LiteralPath "' + $f.FullName + '" -Destination "' + $dest + '"'
    if (-not $live) { Write-Host "DRY: $text" -ForegroundColor Cyan; return }
    Move-Item -LiteralPath $f.FullName -Destination $dest
    Write-Host "Moved: $($f.Name) -> $doneDir" -ForegroundColor Green
}
