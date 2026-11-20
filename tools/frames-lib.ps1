# frames-lib.ps1 - helper functions for video-frames.ps1, read with a dot (. frames-lib.ps1).
# Only functions: it runs nothing on its own. ASCII only, works on Windows PowerShell 5.1.

# A video name only: no path, no .., no characters with a meaning inside an ffmpeg filter.
function Test-NameAllowed([string]$n) {
    if ([string]::IsNullOrWhiteSpace($n)) { return $false }
    if ($n -match '[\\/:]' -or $n -match '\.\.') { return $false }
    if ($n -match "[',;=\[\]%]") { return $false }
    return $true
}

# Runs ffmpeg for one frame at $sec. Returns $true only if ffmpeg exited with 0 in time
# and $dest is a file that is not empty. Never throws. -n: never writes over a file.
function Save-Frame([string]$ffmpeg, [string]$src, [double]$sec, [string]$dest, [int]$timeoutMs) {
    try {
        $culture = [System.Globalization.CultureInfo]::InvariantCulture
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = $ffmpeg
        $psi.Arguments = '-hide_banner -nostdin -n -v error -ss ' + $sec.ToString('0.000', $culture) + ' -i "' + $src + '" -frames:v 1 -update 1 -q:v 4 "' + $dest + '"'
        $psi.UseShellExecute = $false
        $psi.CreateNoWindow = $true
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true
        $proc = [System.Diagnostics.Process]::Start($psi)
        $errTask = $proc.StandardError.ReadToEndAsync()
        [void]$proc.StandardOutput.ReadToEnd()
        if (-not $proc.WaitForExit($timeoutMs)) { $proc.Kill(); return $false }
        [void]$errTask.Result
        if ($proc.ExitCode -ne 0) { return $false }
        return ((Test-Path -LiteralPath $dest -PathType Leaf) -and (Get-Item -LiteralPath $dest).Length -gt 0)
    }
    catch {
        return $false
    }
}

# Each sentence of an srt file: start and end in seconds, and its text (the lines after the time line, up to a blank line).
function Get-FrameEntries([string]$srt) {
    $rx = '(\d+):(\d\d):(\d\d)[,.](\d+)\s*-->\s*(\d+):(\d\d):(\d\d)[,.](\d+)'
    $entries = New-Object System.Collections.Generic.List[object]
    $srtLines = @(Get-Content -LiteralPath $srt -Encoding UTF8)
    for ($k = 0; $k -lt $srtLines.Count; $k++) {
        $m = [regex]::Match($srtLines[$k], $rx)
        if (-not $m.Success) { continue }
        $said = @(); $j = $k + 1
        while ($j -lt $srtLines.Count -and $srtLines[$j].Trim() -ne '') { $said += $srtLines[$j].Trim(); $j++ }
        $start = [int]$m.Groups[1].Value * 3600 + [int]$m.Groups[2].Value * 60 + [int]$m.Groups[3].Value + [double]('0.' + $m.Groups[4].Value)
        $end = [int]$m.Groups[5].Value * 3600 + [int]$m.Groups[6].Value * 60 + [int]$m.Groups[7].Value + [double]('0.' + $m.Groups[8].Value)
        $entries.Add([pscustomobject]@{ start = $start; end = $end; text = ($said -join ' ') })
    }
    return , $entries.ToArray()
}

# Picks the frames. A sentence less than $minGap seconds after the last picked one, or past $max frames,
# joins the last picked block (its text is added, its end moves on). Each block keeps start (for the name
# and notes.md) and gets shot: the middle between its start and the start of the next block. The last
# block: the middle between its start and the end of the last sentence that joined it.
function Select-Frames([object[]]$entries, [double]$minGap, [int]$max) {
    $picked = New-Object System.Collections.Generic.List[object]
    foreach ($e in ($entries | Sort-Object start)) {
        $last = $picked.Count - 1
        if ($last -ge 0 -and ($picked.Count -ge $max -or $e.start - $picked[$last].start -lt $minGap)) {
            $picked[$last].text = ($picked[$last].text + ' ' + $e.text).Trim()
            if ($e.end -gt $picked[$last].end) { $picked[$last].end = $e.end }
            continue
        }
        $picked.Add([pscustomobject]@{ start = $e.start; end = $e.end; shot = 0.0; text = $e.text })
    }
    for ($i = 0; $i -lt $picked.Count; $i++) {
        $next = $picked[$i].end
        if ($i + 1 -lt $picked.Count) { $next = $picked[$i + 1].start }
        $picked[$i].shot = ($picked[$i].start + $next) / 2
    }
    return , $picked.ToArray()
}
