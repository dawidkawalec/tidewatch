#!/usr/bin/env bash
# Screenshot a Tidewatch design preview target (invented sessions, nothing real is touched).
#
#   scripts/snap.sh <target> <out.png>
#   targets: widget-collapsed widget-expanded widget-empty widget-overflow widget-disconnected
#
# SNAP_BACKDROP=<image>   image right behind the widget (default docs/design/backdrops/dusk.jpg)
# SNAP_SETTLE=<seconds>   wait after the window appears (default 1.5)
# TIDEWATCH_GLASS_FALLBACK=1 is passed through (macOS 14/15 glass on macOS 26).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BIN="${TIDEWATCH_BIN:-$ROOT/.local-build/Build/Products/Debug/Tidewatch.app/Contents/MacOS/Tidewatch}"
SETTLE="${SNAP_SETTLE:-1.5}"
BACKDROP="${SNAP_BACKDROP:-$ROOT/docs/design/backdrops/dusk.jpg}"

[[ $# -eq 2 ]] || { echo "usage: scripts/snap.sh <target> <out.png>" >&2; exit 2; }
[[ -x "$BIN" ]] || { echo "snap: no binary at $BIN (run make build)" >&2; exit 1; }

log="$(mktemp -t tidewatch-snap)"
TIDEWATCH_PREVIEW_BACKDROP="$BACKDROP" "$BIN" --design-preview "$1" >"$log" 2>/dev/null &
pid=$!
trap 'kill "$pid" 2>/dev/null || true; wait "$pid" 2>/dev/null || true; rm -f "$log"' EXIT

frame=""
for _ in $(seq 1 100); do
    frame="$(sed -n 's/^WINDOW_FRAME=\([0-9,-]*\)$/\1/p' "$log" | head -n 1)"
    [[ -n "$frame" ]] && break
    kill -0 "$pid" 2>/dev/null || { echo "snap: preview exited:" >&2; cat "$log" >&2; exit 1; }
    sleep 0.1
done
[[ -n "$frame" ]] || { echo "snap: no WINDOW_FRAME within 10 s" >&2; exit 1; }

sleep "$SETTLE"
mkdir -p "$(dirname "$2")"
rm -f "$2"
screencapture -x -R"$frame" "$2"
[[ -s "$2" ]] || { echo "snap: screencapture wrote nothing (Screen Recording permission?)" >&2; exit 1; }
echo "$2"
