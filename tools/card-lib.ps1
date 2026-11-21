# card-lib.ps1 - helper functions for the library card tools, read with a dot (. card-lib.ps1).
# Only functions: it runs nothing on its own. ASCII only, works on Windows PowerShell 5.1.
# A card is UTF-8, with or without a BOM, because its text can be Arabic. See card-format.md.

# A card name only: no path, no .., just letters, digits, dot, dash and underscore.
function Test-CardName([string]$n) {
    if ([string]::IsNullOrWhiteSpace($n)) { return $false }
    if ($n -match '\.\.') { return $false }
    return ($n -match '^[A-Za-z0-9][A-Za-z0-9._-]*\z')
}

# Reads a card: fields are the "key: value" lines before the first ## heading, and sections
# are the non-empty lines under each ## heading. Keys and heading names are kept in lowercase.
function Read-Card([string]$path) {
    $fields = @{}
    $sections = @{}
    $current = ''
    foreach ($raw in @(Get-Content -LiteralPath $path -Encoding UTF8)) {
        $line = $raw.Trim().TrimStart([char]0xFEFF)
        if ($line -match '^##\s+(.+)$') {
            $current = $Matches[1].Trim().ToLower()
            $sections[$current] = New-Object System.Collections.Generic.List[string]
            continue
        }
        if ($current) {
            if ($line -ne '') { $sections[$current].Add($line) }
            continue
        }
        if ($line -match '^([A-Za-z]+):\s*(.*)$') { $fields[$Matches[1].ToLower()] = $Matches[2].Trim() }
    }
    return [pscustomobject]@{ fields = $fields; sections = $sections }
}

# Checks a card against card-format.md. Returns the list of problems: empty means a good card.
function Test-Card($card, [string]$name) {
    $problems = New-Object System.Collections.Generic.List[string]
    $f = $card.fields
    foreach ($key in @('video', 'date', 'length', 'topics', 'tools', 'verdict', 'links')) {
        if ([string]::IsNullOrWhiteSpace($f[$key])) { $problems.Add("field missing or empty: $key") }
    }
    if ($f['video'] -and ($f['video'] -match '[\\/:]' -or [System.IO.Path]::GetFileNameWithoutExtension($f['video']) -ne $name)) {
        $problems.Add("video does not match the card name ${name}: $($f['video'])")
    }
    $culture = [System.Globalization.CultureInfo]::InvariantCulture
    $day = [datetime]::MinValue
    if ($f['date'] -and -not [datetime]::TryParseExact([string]$f['date'], 'yyyy-MM-dd', $culture, [System.Globalization.DateTimeStyles]::None, [ref]$day)) {
        $problems.Add("date is not yyyy-MM-dd: $($f['date'])")
    }
    if ($f['length'] -and $f['length'] -notmatch '^[0-9]{2}:[0-5][0-9]$') { $problems.Add("length is not mm:ss: $($f['length'])") }
    if ($f['verdict'] -and $f['verdict'] -cnotmatch '^(apply|maybe|skip)\s+-\s+\S') { $problems.Add("verdict is not apply, maybe or skip, then - and a reason: $($f['verdict'])") }
    if (-not $card.sections.ContainsKey('summary') -or $card.sections['summary'].Count -eq 0) { $problems.Add('section missing or empty: ## Summary') }
    $ideas = @()
    if ($card.sections.ContainsKey('ideas')) { $ideas = @($card.sections['ideas'] | Where-Object { $_ -match '^- \[[0-9]{2}:[0-5][0-9]\] \S' }) }
    if ($ideas.Count -eq 0) { $problems.Add('section ## Ideas needs at least one line like: - [mm:ss] the idea') }
    return , $problems.ToArray()
}
