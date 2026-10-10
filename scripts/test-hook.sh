#!/usr/bin/env bash
# End-to-end check of the built hook helper against a temp data folder (TIDEWATCH_DATA_DIR).
# Run after a Debug build (make test runs it).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BIN="${HOOK_BIN:-$ROOT/.local-build/Build/Products/Debug/tidewatch-hook}"
[[ -x "$BIN" ]] || { echo "test-hook: no helper at $BIN (run make build)" >&2; exit 1; }

DIR="$(mktemp -d)"
trap 'rm -rf "$DIR"' EXIT
export TIDEWATCH_DATA_DIR="$DIR"
F="$DIR/sessions/s-1.json"

send() { printf '%s' "$1" | "$BIN"; }
status() { python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["status"])' "$F" 2>/dev/null || echo missing; }
fail() { echo "test-hook: FAIL - $1" >&2; exit 1; }
base='"session_id":"s-1","cwd":"/Users/demo/my project"'

send "{$base,\"hook_event_name\":\"SessionStart\",\"source\":\"startup\"}"
[[ "$(status)" == idle ]] || fail "SessionStart should be idle"
send "{$base,\"hook_event_name\":\"UserPromptSubmit\",\"prompt\":\"x\"}"
[[ "$(status)" == working ]] || fail "UserPromptSubmit should be working"
send "{$base,\"hook_event_name\":\"PermissionRequest\",\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"npm install\"}}"
[[ "$(status)" == needsApproval ]] || fail "PermissionRequest should need approval"
send "{$base,\"hook_event_name\":\"PostToolUse\",\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"npm install\"},\"tool_response\":{\"stdout\":\"ok\"}}"
[[ "$(status)" == working ]] || fail "matching PostToolUse should clear the approval"
send "{$base,\"hook_event_name\":\"Stop\",\"background_tasks\":[]}"
[[ "$(status)" == awaitingReview ]] || fail "Stop should await review"

send 'not json at all'
[[ "$(status)" == awaitingReview ]] || fail "garbage must not change the state"
out="$(printf 'garbage' | "$BIN")"
[[ -z "$out" ]] || fail "the helper printed to stdout"
printf 'garbage' | "$BIN" || fail "the helper exited non-zero"

send '{"session_id":"../evil","cwd":"/tmp","hook_event_name":"Stop"}'
[[ ! -e "$DIR/evil.json" ]] || fail "path traversal wrote outside sessions/"

for _ in $(seq 1 20); do
    send "{$base,\"hook_event_name\":\"PreToolUse\",\"tool_name\":\"Read\",\"tool_input\":{\"file_path\":\"/a\"}}" &
done
wait
python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$F" || fail "parallel writes corrupted the file"

start=$(python3 -c 'import time; print(time.time())')
for _ in $(seq 1 50); do
    send "{$base,\"hook_event_name\":\"PostToolUse\",\"tool_name\":\"Read\",\"tool_input\":{\"file_path\":\"/a\"}}"
done
end=$(python3 -c 'import time; print(time.time())')
avg=$(python3 -c "print(round(($end - $start) / 50 * 1000, 1))")
echo "test-hook: average ${avg} ms per event"
python3 -c "import sys; sys.exit(0 if $avg < 50 else 1)" || fail "helper too slow (${avg} ms per event, budget 50)"

send "{$base,\"hook_event_name\":\"SessionEnd\",\"reason\":\"other\"}"
[[ ! -e "$F" ]] || fail "SessionEnd should delete the file"

echo "test-hook: OK"
