# mpv-getsub-lua

A full remake of VLC's **VLSub** for **mpv** and mpv-based players — **Haruna**, Celluloid, and friends.

Search and download subtitles from **OpenSubtitles (REST v1)** directly inside the player: OSDb movie-hash + filename search, multi-language, an in-player result picker, and both app-key and personal-account auth (use your own OpenSubtitles quota to avoid the shared app-key rate limits).

Pure Lua + `curl` — **no external Lua dependencies** (no luasocket, no luafilesystem), so it runs in a stock mpv scripting environment.

---

## Features

- 🔍 **Two search modes** — OSDb movie hash (first+last 64 KiB of the file) and cleaned filename/title, with season/episode support.
- 🎬 **Works in plain mpv** (drop into `scripts/`) **and Haruna** (one-line installer, no fork).
- 🧩 **Pluggable providers** — OpenSubtitles (REST v1), **Subdl** (API v2), and **Podnapisi** (no key needed; experimental — the site was unreachable during development, so it's untested live). The provider interface makes others easy to add.
- 👤 **Your own OpenSubtitles account** — optional login switches downloads to your personal quota instead of the app's shared limits.
- 🖱️ **Result picker** — native **uosc** menu when uosc is installed, with an ASS-overlay fallback (↑/↓ or j/k, PgUp/PgDn, `Enter`, `Esc`); or `auto_select` for hands-free best-match.
- 💾 Saves next to the video as `<name>.<lang>.<ext>` and `sub-add`s it immediately.

## Requirements

- mpv ≥ 0.33 (tested on 0.40) — or a libmpv player such as Haruna
- `curl` and `dd` on `PATH` (used for HTTP and the file hash)
- A free **OpenSubtitles consumer API key** → https://www.opensubtitles.com/en/consumers

## Install — plain mpv

```bash
git clone https://github.com/crnisamuraj/mpv-getsub-lua
mkdir -p ~/.config/mpv/scripts
ln -s "$PWD/mpv-getsub-lua/mpv-getsub-lua" ~/.config/mpv/scripts/mpv-getsub-lua
```

(mpv loads `main.lua` from the symlinked folder; the sibling `modules/` and `providers/` are found via `package.path`.)

## Install — Haruna

```bash
./scripts/install-haruna.sh
```

This registers a Haruna **custom command** that runs `load-script …/main.lua` at startup, plus a `shortcut` command bound to `n`. Haruna has no plugin system, but its custom commands run arbitrary mpv input commands, and mpv can load Lua scripts at runtime — this is the bridge. Verified end-to-end in real Haruna.

Options: `--key <key>` to change the trigger, `--no-startup` to only bind the key, `--uninstall` to remove.

## Install — Celluloid

```bash
./scripts/install-celluloid.sh
```

Celluloid natively auto-loads every file in `~/.config/celluloid/scripts/` (its plugin mechanism), so the installer just drops a thin wrapper there. Copy your config to `~/.config/celluloid/script-opts/mpv-getsub-lua.conf`. `--uninstall` removes the wrapper.

## Configure

Create `~/.config/mpv/script-opts/mpv-getsub-lua.conf` (see `docs/CONFIG.example.conf`):

```ini
provider=opensubtitles
languages=en,sr,hr
api_key=YOUR_CONSUMER_API_KEY
# optional — your own account, uses your personal download quota
username=
password=
save_to=video
auto_select=no
osd_duration_ms=8000
```

| Option | Default | Meaning |
|---|---|---|
| `provider` | `opensubtitles` | subtitle provider to use |
| `languages` | `en` | comma-separated ISO-639 codes, in preference order |
| `api_key` | — | OpenSubtitles consumer key identifying this app |
| `subdl_api_key` | — | Subdl API key (used when `provider=subdl`) |
| `username` / `password` | — | optional account login; downloads count against your own quota |
| `save_to` | `video` | `video` = next to the media file, or an absolute directory |
| `auto_select` | `no` | `yes` = download the single best match without showing the picker |
| `osd_duration_ms` | `8000` | how long the picker stays on screen |

## Usage

- Open a video and press **`n`** (or run `script-message search`).
- If multiple results: pick with ↑/↓ + `Enter`; `Esc` cancels.
- With `auto_select=yes` the best match downloads automatically.

## Development

Headless end-to-end test against libmpv (no GUI needed):

```bash
./scripts/test.sh /path/to/video.mkv
```

Layout:

- `mpv-getsub-lua/main.lua` — entry point (what mpv loads)
- `mpv-getsub-lua/modules/` — config, OSDb hash, HTTP, picker UI
- `mpv-getsub-lua/providers/` — pluggable subtitle providers
- `scripts/` — installers + test harness

## License

[MIT](LICENSE)
