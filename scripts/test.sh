#!/usr/bin/env bash
# Headless end-to-end test for mpv-getsub-lua using libmpv directly.
# Usage: ./scripts/test.sh /path/to/video.mkv
set -euo pipefail
cd "$(dirname "$0")/.."
VIDEO="${1:?pass a video file}"
SCRIPT_DIR="$(cd mpv-getsub-lua && pwd)"

VIDEO="$VIDEO" SCRIPT_DIR="$SCRIPT_DIR" python3 - <<'PY'
import ctypes, os, time
m = ctypes.CDLL("libmpv.so.2")
m.mpv_create.restype = ctypes.c_void_p
m.mpv_set_option_string.argtypes=[ctypes.c_void_p,ctypes.c_char_p,ctypes.c_char_p]
m.mpv_command_string.argtypes=[ctypes.c_void_p,ctypes.c_char_p]
m.mpv_initialize.argtypes=[ctypes.c_void_p]
ctx = m.mpv_create()
m.mpv_set_option_string(ctx,b"terminal",b"yes")
m.mpv_set_option_string(ctx,b"msg-level",b"all=info")
# enable config so script-opts/mpv-getsub-lua.conf is found, mirroring real usage
m.mpv_set_option_string(ctx,b"config",b"yes")
m.mpv_set_option_string(ctx,b"config-dir",os.path.expanduser("~/.config/mpv").encode())
m.mpv_set_option_string(ctx,b"vo",b"null")
m.mpv_initialize(ctx)
sd = os.environ["SCRIPT_DIR"]
m.mpv_command_string(ctx, f"load-script {sd}/main.lua".encode())
m.mpv_command_string(ctx, b"loadfile " + os.environ["VIDEO"].encode())
time.sleep(1.5)
# force single-result path deterministically by triggering the message
m.mpv_command_string(ctx, b"script-message search")
time.sleep(6)
PY
