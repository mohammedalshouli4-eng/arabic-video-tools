# Settings for the video tools. Copy this file to video-config.local.psd1 (next to it, not in git) and set
# only what differs on your machine. Read as data by config-lib.ps1, never run. Use full paths.
# An empty or missing value takes the default shown on its line.
@{
    Root         = ''   # empty = the nearest folder at or above the scripts that holds video-tools.root, else 3 folders up from the scripts
    Videos       = ''   # empty = <Root>\videos ; inbox, done, work, out, moments and models are under it
    Library      = ''   # empty = <Root>\library
    Upload       = ''   # empty = <Root>\upload
    Downloads    = ''   # empty = %USERPROFILE%\Downloads
    FfmpegBin    = ''   # empty or wrong = ffmpeg.exe and ffprobe.exe are looked for on PATH
    WhisperModel = ''   # empty = <Videos>\models\ggml-large-v3-turbo-q5_0.bin ; must be inside Videos
    HyperframesDir = '' # empty = no summary videos; else the folder where hyperframes was installed with npm (it holds node_modules, hf-config and hf-cache)
}
