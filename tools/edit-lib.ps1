# edit-lib.ps1 - helper functions for video-cut.ps1 and video-subs.ps1, read with a dot (. edit-lib.ps1).
# Only functions: it runs nothing on its own. ASCII only, works on Windows PowerShell 5.1.
# Times are seconds as [double]. Numbers for ffmpeg and srt use the invariant culture.

# Runs ffmpeg and waits up to $timeoutMs. Returns @{ ok; err }: ok only if it exited with 0 in time.
# err is all ffmpeg wrote to stderr (the input info and silencedetect lines are there). Never throws.
function Invoke-Ffmpeg([string]$exe, [string]$arguments, [int]$timeoutMs) {
    $result = @{ ok = $false; err = '' }
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
        [void]$proc.StandardOutput.ReadToEnd()
        if (-not $proc.WaitForExit($timeoutMs)) { $proc.Kill(); return $result }
        $result.err = [string]$errTask.Result
        $result.ok = ($proc.ExitCode -eq 0)
        return $result
    }
    catch {
        return $result
    }
}

# The video in inbox, else in done. Returns its full path, or '' if it is in neither.
function Find-Video([string]$name, [string]$inbox, [string]$doneDir) {
    foreach ($d in @($inbox, $doneDir)) {
        $p = Join-Path $d $name
        if (Test-Path -LiteralPath $p -PathType Leaf) { return $p }
    }
    return ''
}

# The input length in seconds from the "Duration:" line of ffmpeg stderr, or -1 if it is not there.
function Get-Duration([string]$err) {
    $m = [regex]::Match($err, 'Duration:\s*(\d+):(\d\d):(\d\d(?:\.\d+)?)')
    if (-not $m.Success) { return -1.0 }
    return [int]$m.Groups[1].Value * 3600 + [int]$m.Groups[2].Value * 60 + [double]::Parse($m.Groups[3].Value, [System.Globalization.CultureInfo]::InvariantCulture)
}

# Silences from the silencedetect lines of ffmpeg stderr, as @{ s; e }. A silence still open at the end ends at $duration.
function Get-Silences([string]$err, [double]$duration) {
    $culture = [System.Globalization.CultureInfo]::InvariantCulture
    $list = New-Object System.Collections.Generic.List[object]
    $start = -1.0
    foreach ($m in [regex]::Matches($err, 'silence_(start|end):\s*(-?[0-9.]+(?:e[-+]?[0-9]+)?)')) {
        $t = [double]::Parse($m.Groups[2].Value, $culture)
        if ($m.Groups[1].Value -eq 'start') { $start = [math]::Max(0.0, $t) }
        elseif ($start -ge 0) { $list.Add([pscustomobject]@{ s = $start; e = [math]::Min($t, $duration) }); $start = -1.0 }
    }
    if ($start -ge 0 -and $start -lt $duration) { $list.Add([pscustomobject]@{ s = $start; e = $duration }) }
    return , $list.ToArray()
}

# The parts to keep: everything but the silences. $pad seconds of each silence stay next to the speech.
# A silence that starts within 0.25 s of the start goes whole from 0, and one that ends within 0.25 s of
# the end goes whole to the end (pad only on the speech side). Parts shorter than 0.05 seconds are dropped.
function Get-KeepSegments([object[]]$silences, [double]$duration, [double]$pad) {
    $keeps = New-Object System.Collections.Generic.List[object]
    $cursor = 0.0
    foreach ($si in ($silences | Sort-Object s)) {
        $a = $si.s + $pad
        $b = $si.e - $pad
        if ($si.s -le 0.25) { $a = 0.0 }
        if ($si.e -ge $duration - 0.25) { $b = $duration }
        if ($b - $a -lt 0.05) { continue }
        if ($a - $cursor -ge 0.05) { $keeps.Add([pscustomobject]@{ s = $cursor; e = $a }) }
        $cursor = [math]::Max($cursor, $b)
    }
    if ($duration - $cursor -ge 0.05) { $keeps.Add([pscustomobject]@{ s = $cursor; e = $duration }) }
    return , $keeps.ToArray()
}

# Moves a time of the original video to the cut video. A time inside a removed part goes to the place
# of that cut in the new video (the end of the part before it, which is also the start of the part after it).
function Convert-Time([double]$t, [object[]]$keeps) {
    $offset = 0.0
    foreach ($k in $keeps) {
        if ($t -lt $k.s) { return $offset }
        if ($t -le $k.e) { return $offset + ($t - $k.s) }
        $offset += $k.e - $k.s
    }
    return $offset
}

# Seconds as an srt time: hh:mm:ss,mmm.
function Format-SrtTime([double]$sec) {
    $ms = [long][math]::Round($sec * 1000)
    return '{0:00}:{1:00}:{2:00},{3:000}' -f [math]::Floor($ms / 3600000), [math]::Floor(($ms % 3600000) / 60000), [math]::Floor(($ms % 60000) / 1000), ($ms % 1000)
}

# Splits each sentence longer than $maxWords words (split on spaces, so Arabic works too) into pieces of up to
# $maxWords words. The sentence time is shared by the letters of each piece, one piece right after the other.
# $maxWords 0 or less keeps every sentence whole. Entries are @{ start; end; text }, like Get-FrameEntries.
function Split-SrtEntries([object[]]$entries, [int]$maxWords) {
    $out = New-Object System.Collections.Generic.List[object]
    foreach ($en in $entries) {
        $words = @(([string]$en.text) -split '\s+' | Where-Object { $_ -ne '' })
        if ($maxWords -le 0 -or $words.Count -le $maxWords) { $out.Add($en); continue }
        $chunks = New-Object System.Collections.Generic.List[string]
        for ($i = 0; $i -lt $words.Count; $i += $maxWords) {
            $chunks.Add(($words[$i..([math]::Min($i + $maxWords, $words.Count) - 1)] -join ' '))
        }
        $letters = 0
        foreach ($c in $chunks) { $letters += $c.Replace(' ', '').Length }
        $t = [double]$en.start
        for ($i = 0; $i -lt $chunks.Count; $i++) {
            $e = $t + ($en.end - $en.start) * $chunks[$i].Replace(' ', '').Length / [math]::Max(1, $letters)
            if ($i -eq $chunks.Count - 1) { $e = [double]$en.end }
            $out.Add([pscustomobject]@{ start = $t; end = $e; text = $chunks[$i] })
            $t = $e
        }
    }
    return , $out.ToArray()
}

# The srt for the cut video, from Get-FrameEntries entries: @{ lines; dropped }. A sentence left with
# less than 0.05 seconds (it was all inside a removed part) is dropped, and its text goes to dropped.
function Get-CutSrt([object[]]$entries, [object[]]$keeps) {
    $lines = New-Object System.Collections.Generic.List[string]
    $dropped = New-Object System.Collections.Generic.List[string]
    $n = 0
    foreach ($en in $entries) {
        $a = Convert-Time $en.start $keeps
        $b = Convert-Time $en.end $keeps
        if ($b - $a -lt 0.05) { $dropped.Add($en.text); continue }
        $n++
        foreach ($t in @([string]$n, ((Format-SrtTime $a) + ' --> ' + (Format-SrtTime $b)), $en.text, '')) { $lines.Add($t) }
    }
    return @{ lines = $lines.ToArray(); dropped = $dropped.ToArray() }
}
