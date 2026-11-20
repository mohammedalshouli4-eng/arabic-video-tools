# config-lib.ps1 - reads the settings of the video tools, read with a dot (. config-lib.ps1).
# Only functions: it runs nothing on its own. ASCII only, works on Windows PowerShell 5.1.
# Settings file: video-config.local.psd1 next to this file (not in git; video-config.example.psd1 shows
# every key). It is read as data with Import-PowerShellDataFile, so it can never run code. A missing file
# is fine: every empty or missing value gets its default. A bad file or a bad value stops with STOP.

# All final paths as one object. -LocalPath reads another settings file (a file that is not there means
# defaults). -Override sets values after the file, for tests, for example @{ FfmpegBin = 'C:\nope' }.
# -RootMarker names the marker file for the default Root; a name that is nowhere tests the old rule.
# Defaults: Root = the nearest folder at or above this file that holds the marker file video-tools.root,
# else 3 folders up from this file. RootFrom says which: setting, marker or 3 folders up.
# Videos = <Root>\videos (inbox, done, work, out, moments and
# models under it), Library = <Root>\library, Upload = <Root>\upload, Downloads = %USERPROFILE%\Downloads,
# FfmpegBin = none (Get-FfmpegTool then looks on PATH), WhisperModel = <Videos>\models\ggml-large-v3-turbo-q5_0.bin.
# HyperframesDir = none: only video-summary needs it and stops by itself when it is empty. When it is set,
# HyperframesCmd, HyperframesConfig and HyperframesCache are node_modules\.bin\hyperframes.cmd, hf-config and hf-cache in it.
function Get-VideoConfig([string]$LocalPath = (Join-Path $PSScriptRoot 'video-config.local.psd1'), [hashtable]$Override = @{},
    [string]$RootMarker = 'video-tools.root') {
    $keys = @('Root', 'Videos', 'Library', 'Upload', 'Downloads', 'FfmpegBin', 'WhisperModel', 'HyperframesDir')
    $v = @{}
    foreach ($k in $keys) { $v[$k] = '' }
    $source = '(no local file, defaults)'
    if ($LocalPath -and (Test-Path -LiteralPath $LocalPath -PathType Leaf)) {
        try { $data = Import-PowerShellDataFile -LiteralPath $LocalPath }
        catch { throw "STOP: settings file is not valid: $LocalPath ($($_.Exception.Message))" }
        foreach ($k in $data.Keys) {
            if ($keys -notcontains $k) { throw "STOP: unknown setting '$k' in $LocalPath. Known: $($keys -join ', ')" }
            $v[$k] = [string]$data[$k]
        }
        $source = $LocalPath
    }
    foreach ($k in $Override.Keys) {
        if ($keys -notcontains $k) { throw "STOP: unknown setting '$k'. Known: $($keys -join ', ')" }
        $v[$k] = [string]$Override[$k]
    }

    # An empty value takes its default. A set value becomes a full path.
    $pick = {
        param([string]$value, [string]$default)
        if ($value.Trim()) { return [System.IO.Path]::GetFullPath($value.Trim()) }
        return $default
    }
    $auto = Find-VideoRoot $RootMarker
    $rootFrom = 'marker'
    if (-not $auto) { $auto = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)); $rootFrom = '3 folders up' }
    if ($v['Root'].Trim()) { $rootFrom = 'setting' }
    $root = & $pick $v['Root'] $auto
    $videos = & $pick $v['Videos'] (Join-Path $root 'videos')
    $model = & $pick $v['WhisperModel'] (Join-Path $videos 'models\ggml-large-v3-turbo-q5_0.bin')

    # The whisper filter breaks on C: in a path, so the model must be inside Videos and is used by a relative path.
    # Ordinal (ignoring case): a culture compare can skip characters.
    $prefix = $videos.TrimEnd('\') + '\'
    if (-not $model.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "STOP: WhisperModel must be inside Videos ($videos), because the whisper filter needs a relative path: $model"
    }
    $hf = & $pick $v['HyperframesDir'] ''
    $hfPaths = @('', '', '')
    if ($hf) { $hfPaths = @((Join-Path $hf 'node_modules\.bin\hyperframes.cmd'), (Join-Path $hf 'hf-config'), (Join-Path $hf 'hf-cache')) }

    return [pscustomobject]@{
        Source          = $source
        Root            = $root
        RootFrom        = $rootFrom
        Videos          = $videos
        Inbox           = (Join-Path $videos 'inbox')
        Done            = (Join-Path $videos 'done')
        Work            = (Join-Path $videos 'work')
        Out             = (Join-Path $videos 'out')
        Moments         = (Join-Path $videos 'moments')
        Models          = (Join-Path $videos 'models')
        Library         = (& $pick $v['Library'] (Join-Path $root 'library'))
        Upload          = (& $pick $v['Upload'] (Join-Path $root 'upload'))
        Downloads       = (& $pick $v['Downloads'] (Join-Path $env:USERPROFILE 'Downloads'))
        FfmpegBin       = (& $pick $v['FfmpegBin'] '')
        WhisperModel    = $model
        WhisperModelRel = $model.Substring($prefix.Length).Replace('\', '/')
        HyperframesDir  = $hf
        HyperframesCmd  = $hfPaths[0]
        HyperframesConfig = $hfPaths[1]
        HyperframesCache = $hfPaths[2]
    }
}

# The nearest folder at or above this file that holds the file $Marker, or '' when there is none.
function Find-VideoRoot([string]$Marker) {
    if (-not $Marker) { return '' }
    $dir = $PSScriptRoot
    while ($dir) {
        if (Test-Path -LiteralPath (Join-Path $dir $Marker) -PathType Leaf) { return $dir }
        $dir = Split-Path -Parent $dir
    }
    return ''
}

# The full path of ffmpeg.exe or ffprobe.exe ($Tool is ffmpeg or ffprobe). From FfmpegBin when the file is
# there. Else from PATH, with a yellow WARNING, because a PATH ffmpeg may lack the whisper or libass filters.
# Neither: STOP.
function Get-FfmpegTool([string]$Tool, $Config) {
    if ($Tool -cnotmatch '^(ffmpeg|ffprobe)\z') { throw "STOP: Get-FfmpegTool takes ffmpeg or ffprobe: $Tool" }
    $exe = $Tool + '.exe'
    if ($Config.FfmpegBin) {
        $p = Join-Path $Config.FfmpegBin $exe
        if (Test-Path -LiteralPath $p -PathType Leaf) { return $p }
        Write-Host "WARNING: FfmpegBin has no ${exe}: $($Config.FfmpegBin)" -ForegroundColor Yellow
    }
    $cmd = Get-Command -Name $exe -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($cmd) {
        Write-Host "WARNING: $exe comes from PATH: $($cmd.Source). Check it has the whisper and libass filters (ffmpeg -filters)." -ForegroundColor Yellow
        return $cmd.Source
    }
    throw "STOP: $exe not found. Set FfmpegBin in video-config.local.psd1 or add ffmpeg to PATH."
}
