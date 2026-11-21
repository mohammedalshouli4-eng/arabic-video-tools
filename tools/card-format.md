# Library card format

Note for Claude: after each beginner guide, make one card for the video, as a file the user can download.
Name the file after the video without its extension, for example video-08.md. The user saves it with video-card-save.ps1, which rejects a card that does not follow this format.

## Rules

- The seven fields come first, one per line, as `key: value`. Keys are in English and lowercase.
- video: the full video file name, and its name without the extension must match the card file name.
- date: the day the card was made, as yyyy-MM-dd.
- length: the video length as mm:ss, from the Duration line in the handoff file.
- topics: short words separated by commas.
- tools: the tools the video names, separated by commas, or none.
- verdict: apply, maybe or skip in lowercase English, then " - ", then the reason in one sentence (Arabic is fine).
- links: other videos with a related idea, separated by commas, or none.
- After the fields: the section `## Summary` with a few lines, then the section `## Ideas`.
- Each idea is one line: `- [mm:ss] the idea | "the original sentence from the video"`. There must be at least one.
- Keep the original sentence as it was said, so the idea can be traced back to the video.

## Example (made up, only to show the shape)

```
video: video-08.mp4
date: 2026-11-04
length: 01:12
topics: wsl, claude-code, windows
tools: WSL, Claude Code
verdict: maybe - مفيد بس لازم نجرّبه على الجهاز أول
links: video-04, video-06

## Summary
الفيديو بيشرح كيف تجهّز WSL على ويندوز عشان تشغّل Claude Code.

## Ideas
- [00:13] تثبيت WSL بأمر واحد | "wsl --install"
```
