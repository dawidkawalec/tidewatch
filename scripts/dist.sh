#!/usr/bin/env bash
# Public build of Tidewatch: Release build, Developer ID signature with a secure timestamp,
# notarization of the app, stapling, then a signed, notarized and stapled DMG.
#
#   scripts/dist.sh <version>            e.g. scripts/dist.sh 0.2.0
#   DRY_RUN=1 scripts/dist.sh <version>  everything except notarization (nothing leaves this Mac)
#
# Needs: a "Developer ID Application" certificate in the login Keychain and the notarytool
# keychain profile NOTARY_PROFILE (default captylo-notary, shared with Captylo). Output:
# dist/<version>/Tidewatch.app and dist/<version>/Tidewatch-<version>.dmg (git-ignored).
# Run only with the owner's go-ahead: notarization uploads the build to Apple.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
IDENTITY="${DIST_IDENTITY:-Developer ID Application}"
NOTARY_PROFILE="${NOTARY_PROFILE:-captylo-notary}"
DRY_RUN="${DRY_RUN:-0}"

step() { printf '\n==> %s\n' "$*"; }
die() { printf '\ndist.sh: %s\n' "$*" >&2; exit 1; }

[ $# -eq 1 ] || die "usage: [DRY_RUN=1] scripts/dist.sh <version>"
VERSION="$1"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "the version must look like 1.2.3, got \"$VERSION\""

step "Checking the repository"
[ "$(git branch --show-current)" = main ] || die "public builds are cut from main"
[ -z "$(git status --porcelain)" ] || [ "$DRY_RUN" = 1 ] || die "the working tree has uncommitted changes"
MARKETING_VERSION="$(sed -n 's/^ *MARKETING_VERSION: *"\{0,1\}\([^"]*\)"\{0,1\} *$/\1/p' project.yml | head -1)"
[ "$MARKETING_VERSION" = "$VERSION" ] || die "project.yml says MARKETING_VERSION \"$MARKETING_VERSION\", not \"$VERSION\""
security find-identity -p codesigning -v | grep -q "$IDENTITY" || die "no \"$IDENTITY\" certificate in the Keychain"

# Sparkle (docs/release.md): every public build carries the feed key and gets a signed appcast item.
SPARKLE_BIN="$ROOT/.local-build/SourcePackages/artifacts/sparkle/Sparkle/bin"
SPARKLE_ACCOUNT="${SPARKLE_ACCOUNT:-tidewatch}"
# The key file (the owner's backup, outside git) signs without a Keychain prompt; without it the
# Keychain account is used.
SPARKLE_KEY_FILE="${SPARKLE_KEY_FILE:-$HOME/.claude/secrets/tidewatch-sparkle-ed25519.key}"
if [ -f "$SPARKLE_KEY_FILE" ]; then SIGN_KEY=(--ed-key-file "$SPARKLE_KEY_FILE"); else SIGN_KEY=(--account "$SPARKLE_ACCOUNT"); fi
PUBLIC_KEY="$(sed -n 's/^ *SPARKLE_PUBLIC_ED_KEY: *"\{0,1\}\([^"]*\)"\{0,1\} *$/\1/p' project.yml | head -1)"
NOTES_MD="$ROOT/dist/$VERSION/notes.md"
if [ "$DRY_RUN" != 1 ]; then
    [ "$PUBLIC_KEY" != REPLACE_ME ] || die "SPARKLE_PUBLIC_ED_KEY in project.yml is the placeholder (generate_keys --account $SPARKLE_ACCOUNT, docs/release.md)"
    [ -x "$SPARKLE_BIN/sign_update" ] || die "no $SPARKLE_BIN/sign_update (run make build once so SwiftPM fetches Sparkle)"
    [ -f "$NOTES_MD" ] || die "write ${NOTES_MD#"$ROOT"/} first: it becomes the update notes page and the GitHub release"
    # A signature from any other key would be published and then refused by every installed copy.
    if [ -f "$SPARKLE_KEY_FILE" ]; then
        FILE_PUBLIC="$(swift -e 'import CryptoKit; import Foundation; let s = try! String(contentsOfFile: CommandLine.arguments[1], encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines); print(try! Curve25519.Signing.PrivateKey(rawRepresentation: Data(base64Encoded: s)!).publicKey.rawRepresentation.base64EncodedString())' "$SPARKLE_KEY_FILE" 2>/dev/null | tail -1)"
        [ "$FILE_PUBLIC" = "$PUBLIC_KEY" ] || die "the Sparkle key file does not match SPARKLE_PUBLIC_ED_KEY in project.yml"
    fi
fi

OUT="$ROOT/dist/$VERSION"
APP="$OUT/Tidewatch.app"
DMG="$OUT/Tidewatch-$VERSION.dmg"
BUILD="$(git rev-list --count HEAD)"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/tidewatch-dist.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
# Keep notes.md (written by hand before the build), rebuild everything else.
[ -f "$NOTES_MD" ] && cp "$NOTES_MD" "$WORK/notes.md"
rm -rf "$OUT"
mkdir -p "$OUT"
[ -f "$WORK/notes.md" ] && cp "$WORK/notes.md" "$NOTES_MD"

step "Release build"
xcodegen generate >/dev/null
set -o pipefail
xcodebuild -project Tidewatch.xcodeproj -scheme Tidewatch -derivedDataPath "$ROOT/.local-build" \
    -configuration Release CODE_SIGN_IDENTITY="-" CURRENT_PROJECT_VERSION="$BUILD" build 2>&1 |
    grep -E "error:|BUILD (SUCCEEDED|FAILED)"
ditto "$ROOT/.local-build/Build/Products/Release/Tidewatch.app" "$APP"
xattr -cr "$APP"

step "Signing with $IDENTITY"
SIGN_TIMESTAMP=1 scripts/sign-app.sh "$APP" "$IDENTITY"
codesign -dv "$APP" 2>&1 | grep -E "Authority=Developer ID|TeamIdentifier|flags"

notarize() {
    if [ "$DRY_RUN" = 1 ]; then
        echo "DRY RUN: skipping notarization of $1"
        return
    fi
    xcrun notarytool submit "$1" --keychain-profile "$NOTARY_PROFILE" --wait | tee "$WORK/notary.log"
    grep -q "status: Accepted" "$WORK/notary.log" || die "notarization of $1 was not accepted (see the log above)"
}

step "Notarizing the app"
ditto -c -k --keepParent "$APP" "$WORK/Tidewatch.zip"
notarize "$WORK/Tidewatch.zip"
[ "$DRY_RUN" = 1 ] || xcrun stapler staple "$APP"

step "Building the DMG"
STAGE="$WORK/dmg"
mkdir -p "$STAGE"
ditto "$APP" "$STAGE/Tidewatch.app"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "Tidewatch" -srcfolder "$STAGE" -ov -format UDZO -fs HFS+ "$DMG" >/dev/null
hdiutil verify "$DMG" >/dev/null
codesign --force --timestamp --sign "$IDENTITY" "$DMG"

step "Notarizing the DMG"
notarize "$DMG"
if [ "$DRY_RUN" != 1 ]; then
    xcrun stapler staple "$DMG"
    spctl --assess --type open --context context:primary-signature -v "$DMG"
    spctl --assess --type execute -v "$APP"
fi

step "Appcast item and release notes"
BASE_URL="https://kawalec.pl/tidewatch"
DOWNLOAD_URL="$BASE_URL/download/Tidewatch-$VERSION.dmg"
NOTES_URL="$BASE_URL/updates/notes/$VERSION.html"
if [ "$DRY_RUN" = 1 ]; then
    # A dry run never touches site/updates: its item lands in dist/ with a fake signature.
    APPCAST="$OUT/appcast.xml"
    NOTES_HTML="$OUT/notes.html"
    [ -f "$ROOT/site/updates/appcast.xml" ] && cp "$ROOT/site/updates/appcast.xml" "$APPCAST"
    python3 scripts/appcast.py item "$APPCAST" --version "$VERSION" --build "$BUILD" --url "$DOWNLOAD_URL" \
        --signature DRY-RUN-UNSIGNED --length "$(stat -f%z "$DMG")" --notes "$NOTES_URL" --min-os 14.4
else
    APPCAST="$ROOT/site/updates/appcast.xml"
    NOTES_HTML="$ROOT/site/updates/notes/$VERSION.html"
    SIGN_LINE="$("$SPARKLE_BIN/sign_update" "${SIGN_KEY[@]}" "$DMG")" ||
        die "sign_update failed: no Sparkle key file ($SPARKLE_KEY_FILE) and none in the Keychain (account $SPARKLE_ACCOUNT)?"
    SIGNATURE="$(sed -n 's/.*edSignature="\([^"]*\)".*/\1/p' <<<"$SIGN_LINE")"
    "$SPARKLE_BIN/sign_update" "${SIGN_KEY[@]}" --verify "$DMG" "$SIGNATURE" >/dev/null ||
        die "the fresh Sparkle signature does not verify"
    python3 scripts/appcast.py item "$APPCAST" --version "$VERSION" --build "$BUILD" --url "$DOWNLOAD_URL" \
        --sign-update "$SIGN_LINE" --notes "$NOTES_URL" --min-os 14.4
fi
[ -f "$NOTES_MD" ] && python3 scripts/appcast.py notes "$NOTES_MD" "$NOTES_HTML" --version "$VERSION"

step "Done"
echo "Build: $BUILD"
echo "App: $APP"
echo "DMG: $DMG ($(du -h "$DMG" | cut -f1 | xargs))"
echo "SHA-256: $(shasum -a 256 "$DMG" | cut -d' ' -f1)"
[ "$DRY_RUN" = 1 ] || echo "Next: commit site/updates (appcast and notes), push, then make publish VERSION=$VERSION"
