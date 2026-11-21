# moments-lib.ps1 - helper functions for video-moments.ps1, read with a dot (. moments-lib.ps1).
# Only functions: it runs nothing on its own. ASCII only, works on Windows PowerShell 5.1.

# Runs ffmpeg or ffprobe. Returns its output, or $null if it failed or ran out of time. Never throws.
function Invoke-Tool([string]$exe, [string]$arguments, [int]$timeoutMs) {
    try {
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = $exe
        $psi.Arguments = $arguments
        $psi.UseShellExecute = $false
        $psi.CreateNoWindow = $true
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true
        $proc = [System.Diagnostics.Process]::Start($psi)
        $errTask = $proc.StandardError.ReadToEndAsync()
        $outText = $proc.StandardOutput.ReadToEnd()
        if (-not $proc.WaitForExit($timeoutMs)) { $proc.Kill(); return $null }
        [void]$errTask.Result
        if ($proc.ExitCode -ne 0) { return $null }
        return [string]$outText
    }
    catch {
        return $null
    }
}

# Drops the hidden direction marks Notepad may keep around Arabic text, and turns Arabic digits into 0-9.
function Get-Clean([string]$s) {
    foreach ($v in @(0x61C, 0x200E, 0x200F, 0x202A, 0x202B, 0x202C, 0x202D, 0x202E, 0x2066, 0x2067, 0x2068, 0x2069)) { $s = $s.Replace([string][char]$v, '') }
    for ($i = 0; $i -lt 10; $i++) {
        $s = $s.Replace([string][char](0x660 + $i), [string]$i).Replace([string][char](0x6F0 + $i), [string]$i)
    }
    return $s.Trim()
}

# MM:SS or HH:MM:SS to seconds. Returns -1 if not understood.
function Get-TimeSec([string]$t) {
    $m = [regex]::Match((Get-Clean $t), '^(?:([0-9]{1,2}):)?([0-9]{1,2}):([0-9]{2})$')
    if (-not $m.Success) { return -1 }
    $h = 0
    if ($m.Groups[1].Success) { $h = [int]$m.Groups[1].Value }
    $mi = [int]$m.Groups[2].Value
    $s = [int]$m.Groups[3].Value
    if ($s -ge 60 -or ($m.Groups[1].Success -and $mi -ge 60)) { return -1 }
    return $h * 3600 + $mi * 60 + $s
}

# Seconds to mm-ss, or hh-mm-ss from one hour up. Used in frame names; replace - with : to show it.
function Get-Label([int]$s) {
    if ($s -ge 3600) { return '{0:00}-{1:00}-{2:00}' -f [math]::Floor($s / 3600), [math]::Floor(($s % 3600) / 60), ($s % 60) }
    return '{0:00}-{1:00}' -f [math]::Floor($s / 60), ($s % 60)
}

function Get-Seconds($m, [int]$first) {
    return [int]$m.Groups[$first].Value * 3600 + [int]$m.Groups[$first + 1].Value * 60 + [int]$m.Groups[$first + 2].Value + [double]('0.' + $m.Groups[$first + 3].Value)
}

# Each sentence of an srt file: start (s), end (e) and text (t).
function Get-SrtEntries([string]$path) {
    $rx = '(\d+):(\d\d):(\d\d)[,.](\d+)\s*-->\s*(\d+):(\d\d):(\d\d)[,.](\d+)'
    $list = New-Object System.Collections.Generic.List[object]
    $lines = @(Get-Content -LiteralPath $path -Encoding UTF8)
    for ($k = 0; $k -lt $lines.Count; $k++) {
        $m = [regex]::Match($lines[$k], $rx)
        if (-not $m.Success) { continue }
        $said = @()
        $j = $k + 1
        while ($j -lt $lines.Count -and $lines[$j].Trim() -ne '') { $said += $lines[$j].Trim(); $j++ }
        $list.Add([pscustomobject]@{ s = (Get-Seconds $m 1); e = (Get-Seconds $m 5); t = ($said -join ' ') })
    }
    return , $list.ToArray()
}

# The sentence said at $sec, or the nearest one up to $near seconds away (marked "(near)"), or "no speech".
function Get-Said([object[]]$entries, [double]$sec, [double]$near) {
    $best = $null
    $bestGap = $near + 1
    foreach ($e in $entries) {
        $gap = 0.0
        if ($sec -lt $e.s) { $gap = $e.s - $sec } elseif ($sec -gt $e.e) { $gap = $sec - $e.e }
        if ($gap -lt $bestGap) { $best = $e; $bestGap = $gap }
    }
    if ($null -eq $best -or $bestGap -gt $near) { return 'no speech' }
    if ($bestGap -gt 0) { return '(near) ' + $best.t }
    return $best.t
}

# The videos named $name in the first folder that has one. With an extension it must match the full name, without it the base name.
function Find-Video([string]$name, [string[]]$dirs, [string[]]$exts) {
    foreach ($d in $dirs) {
        if (-not (Test-Path -LiteralPath $d -PathType Container)) { continue }
        $found = @(Get-ChildItem -LiteralPath $d -File | Where-Object { ($exts -contains $_.Extension.ToLower()) -and ($_.Name -eq $name -or $_.BaseName -eq $name) })
        if ($found.Count -gt 0) { return , $found }
    }
    return , @()
}

# Each line of the moments file: time | request. Everything after the first | is the request.
# Empty lines and lines that start with # are skipped. A bad line keeps its reason in err.
function Read-Moments([string]$path, [double]$duration, [string]$durClock, [int]$max) {
    $list = New-Object System.Collections.Generic.List[object]
    $fileLines = ([string](Get-Content -LiteralPath $path -Encoding UTF8 -Raw)).TrimStart([char]0xFEFF) -split '\r?\n'
    $good = 0
    for ($k = 0; $k -lt $fileLines.Count; $k++) {
        $text = $fileLines[$k].Trim()
        if ($text -eq '' -or $text.StartsWith('#')) { continue }
        $parts = @($text -split '\|', 2)
        $err = ''
        $sec = -1
        $req = ''
        if ($parts.Count -lt 2) { $err = 'needs time | request' }
        else {
            $sec = Get-TimeSec $parts[0]
            $req = $parts[1].Trim()
            if ($sec -lt 0) { $err = 'time not understood' }
            elseif ($sec -ge $duration) { $err = 'time is past the end of the video (' + $durClock + ')' }
            elseif ($good -ge $max) { $err = 'more than ' + $max + ' moments' }
        }
        if (-not $err) { $good++ }
        $list.Add([pscustomobject]@{ line = $k + 1; raw = $text; sec = $sec; req = $req; err = $err; file = ''; said = '' })
    }
    return , $list.ToArray()
}

# moments.md lines: the title, the note file as it is, then one block per moment. $made says which frames worked.
function Get-MomentsMd([string]$title, [string]$notePath, [object[]]$moments, [hashtable]$made) {
    $md = New-Object System.Collections.Generic.List[string]
    $md.Add($title)
    $md.Add('')
    foreach ($t in @(Get-Content -LiteralPath $notePath -Encoding UTF8)) { $md.Add($t) }
    $md.Add('')
    $n = 0
    foreach ($mo in $moments) {
        $n++
        if ($mo.err) {
            foreach ($t in @(('## ' + $n + '. ERROR (line ' + $mo.line + ')'), ('- Reason: ' + $mo.err), ('- Line: ' + $mo.raw), '')) { $md.Add($t) }
            continue
        }
        $frame = $mo.file
        if (-not $made[$mo.file]) { $frame += ' (frame error, no image)' }
        $req = $mo.req
        if ($req -eq '') { $req = '(no request)' }
        foreach ($t in @(('## ' + $n + '. [' + (Get-Label $mo.sec).Replace('-', ':') + ']  ' + $frame), ('- Said: ' + $mo.said), ('- Request: ' + $req), '')) { $md.Add($t) }
    }
    return , $md.ToArray()
}
