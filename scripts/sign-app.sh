#!/usr/bin/env bash
# Sign Tidewatch.app inside-out with one identity, hardened runtime on (order from Captylo's sign-app.sh).
#   scripts/sign-app.sh <app> <identity|-> [keychain]
# SIGN_TIMESTAMP=1 adds Apple's secure timestamp (required for notarization, scripts/dist.sh).
#
# Under hardened runtime, library validation only loads frameworks signed by the same team, so every
# nested piece carries the app's signature. A nested item is signed before the bundle that holds it:
#   1. inside each framework version: XPC services, helper apps, helper executables
#      (Sparkle's Downloader.xpc, Installer.xpc, Updater.app, Autoupdate)
#   2. each framework in Contents/Frameworks
#   3. the hook helper, then the app with its entitlements
# XPC services keep the entitlements Sparkle shipped them with; other helpers get none.
# SIGN_ENTITLEMENTS=<file> replaces the app's entitlements: `make sign` passes a copy with
# disable-library-validation, because the self-signed "Captylo Dev" identity has no Team ID and
# library validation would refuse Sparkle. Public builds (scripts/dist.sh) never use it.
set -euo pipefail
APP="${1%/}"
ID="$2"
KEYCHAIN="${3:-}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ENTITLEMENTS="${SIGN_ENTITLEMENTS:-$ROOT/Tidewatch/Tidewatch.entitlements}"
timestamp=--timestamp=none
[[ "${SIGN_TIMESTAMP:-0}" == 1 ]] && timestamp=--timestamp
args=(--force --options runtime "$timestamp" --sign "$ID")
[[ -n "$KEYCHAIN" ]] && args+=(--keychain "$KEYCHAIN")

is_macho() { [[ -f "$1" && ! -L "$1" ]] && file -b "$1" | grep -q 'Mach-O'; }

shopt -s nullglob
for framework in "$APP"/Contents/Frameworks/*.framework; do
    name="$(basename "$framework" .framework)"
    for version in "$framework"/Versions/*; do
        [[ -L "$version" ]] && continue
        for xpc in "$version"/XPCServices/*.xpc; do codesign "${args[@]}" --preserve-metadata=entitlements "$xpc"; done
        for helper in "$version"/*.app; do codesign "${args[@]}" "$helper"; done
        for item in "$version"/*; do
            [[ "$(basename "$item")" == "$name" ]] && continue
            if is_macho "$item"; then codesign "${args[@]}" "$item"; fi
        done
    done
    codesign "${args[@]}" "$framework"
done

codesign "${args[@]}" "$APP/Contents/MacOS/tidewatch-hook"
codesign "${args[@]}" --entitlements "$ENTITLEMENTS" "$APP"
codesign --verify --deep --strict "$APP"
