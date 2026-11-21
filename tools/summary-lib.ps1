# summary-lib.ps1 - helper functions for video-summary.ps1, read with a dot (. summary-lib.ps1).
# Only functions: it runs nothing on its own. ASCII only, works on Windows PowerShell 5.1.
# Arabic text that the code itself needs (verdict words, Arabic digits, the Arabic comma) is built from numbers.

# Text for the HTML: & < > " are escaped, and each run of Latin letters, digits and signs (ChatGPT, video-07,
# Remotion 2.5) is wrapped in <bdi>, so it keeps its place inside the Arabic line.
function ConvertTo-SummaryHtml([string]$s) {
    $esc = { param([string]$t) $t.Replace('&', '&amp;').Replace('<', '&lt;').Replace('>', '&gt;').Replace('"', '&quot;') }
    $rx = '[A-Za-z0-9][A-Za-z0-9._+#/-]*(?: [A-Za-z0-9][A-Za-z0-9._+#/-]*)*'
    $sb = New-Object System.Text.StringBuilder
    $pos = 0
    foreach ($m in [regex]::Matches($s, $rx)) {
        [void]$sb.Append((& $esc $s.Substring($pos, $m.Index - $pos)))
        [void]$sb.Append('<bdi>' + (& $esc $m.Value) + '</bdi>')
        $pos = $m.Index + $m.Length
    }
    [void]$sb.Append((& $esc $s.Substring($pos)))
    return $sb.ToString()
}

# The ideas of a card (from Read-Card): the text of each "- [mm:ss] idea | quote" line, without the time and the quote.
function Get-CardIdeas($card) {
    $out = New-Object System.Collections.Generic.List[string]
    if ($card.sections.ContainsKey('ideas')) {
        foreach ($l in $card.sections['ideas']) {
            $m = [regex]::Match([string]$l, '^- \[[0-9]{2}:[0-5][0-9]\]\s+(.+?)\s*(\|.*)?$')
            if ($m.Success) { $out.Add($m.Groups[1].Value.Trim()) }
        }
    }
    return , $out.ToArray()
}

# The first sentence of the card summary: the first summary line, up to its first dot, colon or Arabic comma.
function Get-SummaryLine($card) {
    if (-not $card.sections.ContainsKey('summary') -or $card.sections['summary'].Count -eq 0) { return '' }
    $first = [string]$card.sections['summary'][0]
    $cut = $first.Length
    foreach ($stop in @('.', ':', [string][char]0x060C)) {
        $i = $first.IndexOf($stop, [System.StringComparison]::Ordinal)
        if ($i -gt 0 -and $i -lt $cut) { $cut = $i }
    }
    return $first.Substring(0, $cut).Trim()
}

# The verdict line "apply|maybe|skip - reason" as @{ key; word; reason }. word is the Arabic word for the screen:
# apply = tabbaq, maybe = yumkin, skip = takhatta. $null if the line does not follow card-format.md.
function Get-VerdictParts([string]$verdict) {
    $m = [regex]::Match($verdict, '^(apply|maybe|skip)\s+-\s+(.+)$')
    if (-not $m.Success) { return $null }
    $codes = @{ apply = @(0x637, 0x628, 0x651, 0x642); maybe = @(0x64A, 0x645, 0x643, 0x646); skip = @(0x62A, 0x62E, 0x637, 0x651, 0x649) }
    $word = -join ($codes[$m.Groups[1].Value] | ForEach-Object { [char]$_ })
    return [pscustomobject]@{ key = $m.Groups[1].Value; word = $word; reason = $m.Groups[2].Value.Trim() }
}

# Cuts a text to at most $max characters, at a space when it can, and ends it with an ellipsis. Returns @{ text; cut }.
function Limit-Text([string]$s, [int]$max) {
    if ($s.Length -le $max) { return [pscustomobject]@{ text = $s; cut = $false } }
    $at = $s.LastIndexOf(' ', $max)
    if ($at -lt [int]($max / 2)) { $at = $max }
    $text = $s.Substring(0, $at).TrimEnd(' ', ',', '.', ':', [char]0x060C) + [char]0x2026
    return [pscustomobject]@{ text = $text; cut = $true }
}

# The six environment values for a Hyperframes run: telemetry, update check and skills off, and its config and
# cache inside HyperframesDir. They are given to that one process only, never set on the machine.
function Get-HyperframesEnv($cfg) {
    return @{
        HYPERFRAMES_NO_TELEMETRY    = '1'
        DO_NOT_TRACK                = '1'
        HYPERFRAMES_NO_UPDATE_CHECK = '1'
        HYPERFRAMES_SKIP_SKILLS     = '1'
        HYPERFRAMES_CONFIG_DIR      = $cfg.HyperframesConfig
        HYPERFRAMES_CACHE_DIR       = $cfg.HyperframesCache
    }
}

# The summary HTML from the template text: the SCENE patterns are cut out, then repeated for the title, each idea
# and the verdict, 3 seconds each. $ideas are already cut to length. STOP if a pattern or a place is missing.
function New-SummaryHtml([string]$template, [string]$video, [string]$topic, [string[]]$ideas, [string]$word, [string]$reason) {
    $sceneRx = '(?s)<!--SCENE:(\w+)\r?\n(.*?)SCENE-->\r?\n?'
    $patterns = @{}
    foreach ($m in [regex]::Matches($template, $sceneRx)) { $patterns[$m.Groups[1].Value] = $m.Groups[2].Value }
    foreach ($k in @('title', 'idea', 'verdict')) { if (-not $patterns.ContainsKey($k)) { throw "STOP: the template has no SCENE:$k pattern" } }
    $html = [regex]::Replace($template, $sceneRx, '')
    $sb = New-Object System.Text.StringBuilder
    $at = 0
    [void]$sb.Append($patterns['title'].Replace('{{START}}', [string]$at).Replace('{{VIDEO}}', (ConvertTo-SummaryHtml $video)).Replace('{{TEXT}}', (ConvertTo-SummaryHtml $topic)))
    for ($i = 0; $i -lt $ideas.Count; $i++) {
        $at += 3
        [void]$sb.Append($patterns['idea'].Replace('{{START}}', [string]$at).Replace('{{NUM}}', [string][char](0x661 + $i)).Replace('{{TEXT}}', (ConvertTo-SummaryHtml $ideas[$i])))
    }
    $at += 3
    [void]$sb.Append($patterns['verdict'].Replace('{{START}}', [string]$at).Replace('{{WORD}}', $word).Replace('{{TEXT}}', (ConvertTo-SummaryHtml $reason)))
    $html = $html.Replace('{{SCENES}}', $sb.ToString().TrimEnd()).Replace('{{DURATION}}', [string]($at + 3))
    if ($html.Contains('{{')) { throw 'STOP: a place in double braces is left in the summary html' }
    return $html
}

# Runs hyperframes.cmd with the given arguments in $workDir, with $envVars added for this process only.
# Returns @{ ok; out }: ok only if it exited with 0 in time; out is all it printed. Never throws.
function Invoke-Hyperframes([string]$cmd, [string]$arguments, [string]$workDir, [hashtable]$envVars, [int]$timeoutMs) {
    $result = @{ ok = $false; out = '' }
    try {
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = $cmd
        $psi.Arguments = $arguments
        $psi.WorkingDirectory = $workDir
        $psi.UseShellExecute = $false
        $psi.CreateNoWindow = $true
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true
        foreach ($k in $envVars.Keys) { $psi.EnvironmentVariables[$k] = [string]$envVars[$k] }
        $proc = [System.Diagnostics.Process]::Start($psi)
        $outTask = $proc.StandardOutput.ReadToEndAsync()
        $errTask = $proc.StandardError.ReadToEndAsync()
        if (-not $proc.WaitForExit($timeoutMs)) { $proc.Kill(); return $result }
        $result.out = [string]$outTask.Result + [string]$errTask.Result
        $result.ok = ($proc.ExitCode -eq 0)
        return $result
    }
    catch {
        $result.out = $_.Exception.Message
        return $result
    }
}
