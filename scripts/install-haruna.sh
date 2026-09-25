#!/usr/bin/env bash
# Install mpv-getsub-lua for Haruna by registering a Haruna "custom command"
# that injects the script at startup. Haruna has no plugin system, but its
# custom commands run arbitrary mpv input commands, and mpv supports loading
# Lua scripts at runtime via `load-script` — this is the bridge.
#
# Creates/updates: ~/.config/haruna/custom-commands.conf
#
# Usage:
#   ./scripts/install-haruna.sh [--key n] [--no-startup] [--uninstall]
set -euo pipefail
cd "$(dirname "$0")/.."

SCRIPT_DIR="$(cd mpv-getsub-lua && pwd)"
MAIN_LUA="$SCRIPT_DIR/main.lua"
CC_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/haruna/custom-commands.conf"
GROUP="mpv-getsub-lua"
KEY="n"
STARTUP=1
UNINSTALL=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --key) KEY="$2"; shift 2 ;;
        --no-startup) STARTUP=0; shift ;;
        --uninstall) UNINSTALL=1; shift ;;
        *) echo "unknown arg: $1" >&2; exit 2 ;;
    esac
done

mkdir -p "$(dirname "$CC_FILE")"
[[ -f "$CC_FILE" ]] || touch "$CC_FILE"

# Remove any existing mpv-getsub-lua group (used for both uninstall and reinstall).
python3 - "$CC_FILE" "$GROUP" <<'PY'
import sys, configparser, os
path, group = sys.argv[1], sys.argv[2]
cp = configparser.RawConfigParser()
cp.optionxform = str  # preserve case of keys
cp.read(path)
if cp.has_section(group):
    cp.remove_section(group)
    with open(path, "w") as f:
        cp.write(f, space_around_delimiters=False)
PY

if [[ "$UNINSTALL" -eq 1 ]]; then
    echo "Removed [$GROUP] from $CC_FILE"
    exit 0
fi

if [[ ! -f "$MAIN_LUA" ]]; then
    echo "main.lua not found at $MAIN_LUA" >&2
    exit 1
fi

# Haruna reads custom commands as KConfig groups: [commandId] with
#   Command / OsdMessage / Type / SetOnStartup / Order
# Type "startup" runs the mpv command at application startup; "shortcut" binds
# a key. We register BOTH: startup (auto-load) and shortcut (manual trigger).
python3 - "$CC_FILE" "$GROUP" "$MAIN_LUA" "$KEY" "$STARTUP" <<'PY'
import sys, configparser
path, group, main_lua, key, startup = sys.argv[1:6]
cp = configparser.RawConfigParser()
cp.optionxform = str
cp.read(path)

# startup entry: inject the script when Haruna starts
g_start = group
cp[g_start] = {
    "Command": f"load-script {main_lua}",
    "OsdMessage": "mpv-getsub-lua loaded",
    "Type": "startup",
    "SetOnStartup": "true" if startup == "1" else "false",
    "Order": "0",
}
# shortcut entry: manual trigger (re-run search via script-message)
g_key = group + "-search"
cp[g_key] = {
    "Command": "script-message search",
    "OsdMessage": "Searching subtitles…",
    "Type": "shortcut",
    "SetOnStartup": "true",
    "Order": "1",
}
with open(path, "w") as f:
    cp.write(f, space_around_delimiters=False)
print(f"Wrote [{g_start}] and [{g_key}] to {path}")
PY

echo
echo "Installed for Haruna."
echo "  script : $MAIN_LUA"
echo "  config : $CC_FILE"
echo
echo "Next:"
echo "  1. (Re)start Haruna — the script auto-loads at startup."
echo "  2. Open a video, press '$KEY' (or Haruna > Settings > Custom Commands to change)."
echo "  3. Make sure your OpenSubtitles key is in ~/.config/mpv/script-opts/mpv-getsub-lua.conf"
