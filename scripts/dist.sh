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

OUT="$ROOT/dist/$VERSION"
APP="$OUT/Tidewatch.app"
DMG="$OUT/Tidewatch-$VERSION.dmg"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/tidewatch-dist.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
rm -rf "$OUT"
mkdir -p "$OUT"

step "Release build"
xcodegen generate >/dev/null
set -o pipefail
xcodebuild -project Tidewatch.xcodeproj -scheme Tidewatch -derivedDataPath "$ROOT/.local-build" \
    -configuration Release CODE_SIGN_IDENTITY="-" CURRENT_PROJECT_VERSION="$(git rev-list --count HEAD)" build 2>&1 |
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

step "Done"
echo "App: $APP"
echo "DMG: $DMG ($(du -h "$DMG" | cut -f1 | xargs))"
echo "SHA-256: $(shasum -a 256 "$DMG" | cut -d' ' -f1)"
