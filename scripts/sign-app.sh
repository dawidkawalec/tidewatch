#!/usr/bin/env bash
# Sign Tidewatch.app inside-out (the embedded helper first) with hardened runtime.
#   scripts/sign-app.sh <app> <identity|-> [keychain]
set -euo pipefail
APP="$1"
ID="$2"
KEYCHAIN="${3:-}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
args=(--force --options runtime --timestamp=none --sign "$ID")
[[ -n "$KEYCHAIN" ]] && args+=(--keychain "$KEYCHAIN")
codesign "${args[@]}" "$APP/Contents/MacOS/tidewatch-hook"
codesign "${args[@]}" --entitlements "$ROOT/Tidewatch/Tidewatch.entitlements" "$APP"
codesign --verify --strict "$APP"
