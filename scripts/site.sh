#!/usr/bin/env bash
# The download page (site/), served at kawalec.pl/tidewatch/ and craftweb.pl/tidewatch/ (docs/release.md).
#
#   scripts/site.sh build   <version>   site/ -> dist/site/ with version, DMG size and SHA-256 filled in
#   scripts/site.sh preview <version>   build, then serve it at http://localhost:8787/tidewatch/
#   scripts/site.sh deploy  <version>   build, upload the DMG, repoint Tidewatch.dmg, sync the page, check the live URLs
#
# deploy reads deploy/local.env (git-ignored, see deploy/local.env.example) and changes production:
# owner's go-ahead first.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CMD="${1:-}"
VERSION="${2:-}"
[[ -n "$CMD" && -n "$VERSION" ]] || { echo "usage: scripts/site.sh build|preview|deploy <version>" >&2; exit 2; }

DMG="$ROOT/dist/$VERSION/Tidewatch-$VERSION.dmg"
OUT="$ROOT/dist/site"

build() {
    [[ -f "$DMG" ]] || { echo "site: no $DMG (run make dist VERSION=$VERSION first)" >&2; exit 1; }
    local bytes size sha
    bytes="$(stat -f %z "$DMG")"
    size="$(awk -v b="$bytes" 'BEGIN { printf "%.1f MB", b / 1000000 }')"
    sha="$(shasum -a 256 "$DMG" | cut -d' ' -f1)"
    rm -rf "$OUT"
    mkdir -p "$OUT"
    rsync -a --exclude .DS_Store "$ROOT/site/" "$OUT/"
    sed -i '' -e "s/__VERSION__/$VERSION/g" -e "s/__DMG_SIZE__/$size/g" -e "s/__DMG_SHA256__/$sha/g" "$OUT/index.html"
    if grep -q '__[A-Z0-9_]*__' "$OUT/index.html"; then
        echo "site: unfilled placeholder in index.html" >&2
        exit 1
    fi
    echo "site: built $OUT (Tidewatch $VERSION, $size)"
}

preview() {
    build
    local serve
    serve="$(mktemp -d -t tidewatch-site)"
    ln -s "$OUT" "$serve/tidewatch"
    mkdir -p "$OUT/download"
    ln -sf "$DMG" "$OUT/download/Tidewatch.dmg"
    echo "site: http://localhost:8787/tidewatch/ (Ctrl+C to stop)"
    cd "$serve" && exec python3 -m http.server 8787 --bind 127.0.0.1
}

deploy() {
    local env="$ROOT/deploy/local.env"
    [[ -f "$env" ]] || { echo "site: no deploy/local.env (copy deploy/local.env.example)" >&2; exit 1; }
    # shellcheck source=/dev/null
    source "$env"
    : "${PUBLISH_HOST:?}" "${PUBLISH_SITE_ROOT:?}" "${PUBLISH_DOWNLOADS:?}" "${PUBLISH_URLS:?}"
    build
    local name bytes
    name="$(basename "$DMG")"
    bytes="$(stat -f %z "$DMG")"

    ssh "$PUBLISH_HOST" "mkdir -p '$PUBLISH_SITE_ROOT' '$PUBLISH_DOWNLOADS'"
    # DMGs live outside the page folder, so the --delete sync below never touches them.
    # macOS ships openrsync (no --chmod): permissions are set on the server.
    rsync -a "$DMG" "$PUBLISH_HOST:$PUBLISH_DOWNLOADS/$name"
    rsync -a --delete "$OUT/" "$PUBLISH_HOST:$PUBLISH_SITE_ROOT/"
    ssh "$PUBLISH_HOST" "cd '$PUBLISH_DOWNLOADS' && ln -sfn '$name' Tidewatch.dmg && chmod -R u=rwX,go=rX '$PUBLISH_DOWNLOADS' '$PUBLISH_SITE_ROOT'"

    local base failed=0 page length
    for base in $PUBLISH_URLS; do
        page="$(curl -fsSL "$base/")" || { echo "FAIL $base/ (no page)"; failed=1; continue; }
        if grep -q "Version $VERSION" <<<"$page"; then echo "ok   $base/ shows $VERSION"; else echo "FAIL $base/ does not show $VERSION"; failed=1; fi
        length="$(curl -fsSIL "$base/download/Tidewatch.dmg" | tr -d '\r' | awk 'tolower($1) == "content-length:" { n = $2 } END { print n }')"
        if [[ "$length" == "$bytes" ]]; then echo "ok   $base/download/Tidewatch.dmg ($bytes bytes)"; else echo "FAIL $base/download/Tidewatch.dmg (got '${length:-nothing}', want $bytes)"; failed=1; fi
    done
    [[ $failed -eq 0 ]] || { echo "site: deployed, but a check failed" >&2; exit 1; }
    echo "site: Tidewatch $VERSION is live"
}

case "$CMD" in
    build) build ;;
    preview) preview ;;
    deploy) deploy ;;
    *) echo "usage: scripts/site.sh build|preview|deploy <version>" >&2; exit 2 ;;
esac
