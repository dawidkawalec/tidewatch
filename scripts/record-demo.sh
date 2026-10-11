#!/usr/bin/env bash
# Record the widget-demo preview (invented sessions) into a seamless looping video for the download page.
#
#   scripts/record-demo.sh <out-basename>      writes <out-basename>.mp4 (H.264) and <out-basename>.webp (poster)
#
# SNAP_BACKDROP=<image>   image right behind the widget (default docs/design/backdrops/dusk.jpg)
# SNAP_APPEARANCE=dark|light   force the preview's appearance
# The demo repeats every DesignPreview.Demo.period seconds and steps are scheduled against its start,
# so any window of exactly one period loops without a seam. Needs Screen Recording permission.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BIN="${TIDEWATCH_BIN:-$ROOT/.local-build/Build/Products/Debug/Tidewatch.app/Contents/MacOS/Tidewatch}"
BACKDROP="${SNAP_BACKDROP:-$ROOT/docs/design/backdrops/dusk.jpg}"
PERIOD=12
EXPAND_AT=4.0   # DesignPreview.Demo.steps: the list wells out
SKIP=3         # seconds dropped at the start (the window appearing, first frames)
RECORD=$((SKIP + 2 * PERIOD + 1))

[[ $# -eq 1 ]] || { echo "usage: scripts/record-demo.sh <out-basename>" >&2; exit 2; }
[[ -x "$BIN" ]] || { echo "record: no binary at $BIN (run make build)" >&2; exit 1; }
command -v ffmpeg >/dev/null || { echo "record: ffmpeg is missing (brew install ffmpeg)" >&2; exit 1; }
command -v cwebp >/dev/null || { echo "record: cwebp is missing (brew install webp)" >&2; exit 1; }
OUT="$1"
mkdir -p "$(dirname "$OUT")"

log="$(mktemp -t tidewatch-demo)"
raw="$(mktemp -t tidewatch-demo).mov"
TIDEWATCH_PREVIEW_APPEARANCE="${SNAP_APPEARANCE:-}" TIDEWATCH_PREVIEW_BACKDROP="$BACKDROP" "$BIN" --design-preview widget-demo >"$log" 2>/dev/null &
pid=$!
trap 'kill "$pid" 2>/dev/null || true; wait "$pid" 2>/dev/null || true; rm -f "$log" "$raw"' EXIT

frame=""
for _ in $(seq 1 100); do
    frame="$(sed -n 's/^WINDOW_FRAME=\([0-9,-]*\)$/\1/p' "$log" | head -n 1)"
    [[ -n "$frame" ]] && break
    kill -0 "$pid" 2>/dev/null || { echo "record: preview exited:" >&2; cat "$log" >&2; exit 1; }
    sleep 0.1
done
[[ -n "$frame" ]] || { echo "record: no WINDOW_FRAME within 10 s" >&2; exit 1; }

period="$(sed -n 's/^DEMO_PERIOD=\(.*\)$/\1/p' "$log" | head -n 1)"
[[ "$period" == "$PERIOD" || "$period" == "$PERIOD.0" ]] || { echo "record: demo period is '$period', script expects $PERIOD" >&2; exit 1; }
# The video shows the pointer: park it in the top left corner, far from the widget.
swift -e 'import CoreGraphics; CGWarpMouseCursorPosition(CGPoint(x: 40, y: 40))' 2>/dev/null || true
screencapture -x -v -V "$RECORD" -R"$frame" "$raw"
[[ -s "$raw" ]] || { echo "record: screencapture wrote nothing (Screen Recording permission?)" >&2; exit 1; }

# Cut from 0.3 s into a cycle (the calm first frame). The cycle's phase is read from the video
# itself (the moment the list wells out, DesignPreview.Demo's expand step at 4.0 s):
# screencapture's start-up delay varies by more than a second.
cut="$(python3 "$ROOT/scripts/demo_phase.py" "$raw" --skip "$SKIP" --period "$PERIOD" --expand-at "$EXPAND_AT")"
ffmpeg -loglevel error -y -ss "$cut" -t "$PERIOD" -i "$raw" -an \
    -vf "fps=60,format=yuv420p" -c:v libx264 -preset slow -crf 22 -movflags +faststart "$OUT.mp4"
ffmpeg -loglevel error -y -i "$OUT.mp4" -frames:v 1 "$raw.png"
cwebp -quiet -q 84 "$raw.png" -o "$OUT.webp"
rm -f "$raw.png"
echo "$OUT.mp4 ($(du -h "$OUT.mp4" | cut -f1)), poster $OUT.webp"
