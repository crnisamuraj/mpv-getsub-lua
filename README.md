# mpv-getsub-lua

A full remake of VLC's **VLSub** for **mpv** and **mpv-based players** (Haruna, Celluloid, etc.).

Search and download subtitles from OpenSubtitles (REST v1) directly from the player, with an in-player OSD result picker, multi-language support, and both movie-hash and filename search.

**Status:** early scaffold / WIP.

## Goals
- Works in plain **mpv** (drop into `~/.config/mpv/scripts/`)
- Works in **Haruna** via a one-time custom command or an IPC injector
- Multiple providers (OpenSubtitles REST, Subdl, …)
- Your own OpenSubtitles account login to avoid shared API-key rate limits

## Layout
- `mpv-getsub-lua/main.lua` — the mpv script entrypoint (this file is what mpv loads)
- `mpv-getsub-lua/modules/` — config, OSD hash, picker UI, client orchestration
- `mpv-getsub-lua/providers/` — pluggable subtitle providers
- `scripts/` — installer, Haruna injector, dev test harness

## Quick test (headless, no GUI needed)
```bash
./scripts/test.sh /path/to/video.mkv
```
