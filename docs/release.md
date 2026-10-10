# Release

How a public (installable) Tidewatch build is cut. Owner's go-ahead first: notarization uploads the build to Apple and `publish` creates a GitHub release.

## One-time setup (already done on the owner's Mac)

- "Developer ID Application" certificate in the login Keychain (Team `RA8ASXBMDZ`, shared with Captylo).
- notarytool keychain profile `captylo-notary` (shared with Captylo): `xcrun notarytool history --keychain-profile captylo-notary` must succeed.

## Cutting a release

1. Bump `MARKETING_VERSION` in `project.yml`, commit and push to `main`. The build number is the commit count.
2. `make dist-dry VERSION=x.y.z` - Developer ID signature and DMG, no notarization (nothing leaves the Mac).
3. `make dist VERSION=x.y.z` - signs, notarizes and staples the app, builds, signs, notarizes and staples the DMG, then checks both with `spctl`. Output: `dist/x.y.z/` (git-ignored).
4. Write `dist/x.y.z/notes.md` (what changed, how to install).
5. `make site VERSION=x.y.z` - local preview of the download page with this version at http://localhost:8787/tidewatch/.
6. `make publish VERSION=x.y.z` - uploads the DMG and the page (`scripts/site.sh deploy`, checks both live URLs), then creates the GitHub release `vx.y.z` with the DMG on the private repo. `make deploy-site VERSION=x.y.z` does only the page and the DMG.

## Download page

- Public URLs: https://kawalec.pl/tidewatch/ (canonical) and https://craftweb.pl/tidewatch/, the same folder. DMG: `<page>/download/Tidewatch.dmg`.
- Source: `site/` (static HTML, CSS, JS). `scripts/site.sh build` fills `__VERSION__`, `__DMG_SIZE__` and `__DMG_SHA256__` from `dist/<version>/` into `dist/site/`.
- Server (from git-ignored `deploy/local.env`, template `deploy/local.env.example`): the page in `/var/www/tidewatch` (synced with `--delete`), DMGs in `/var/www/tidewatch-downloads` with `Tidewatch.dmg` pointing at the newest one.
- Caddy: snippet `tidewatch_site` imported under `handle_path /tidewatch/*` in the kawalec.pl block and in the `craftweb_site` snippet; reference copy in `deploy/Caddyfile.tidewatch.snippet`. Back up the live Caddyfile and run `caddy validate` before a reload.
- Videos: `scripts/record-demo.sh site/assets/video/demo-<name>` records the `widget-demo` preview (needs `make build`, ffmpeg, cwebp, Screen Recording permission). Re-record after visible UI changes: dusk (default backdrop), `SNAP_APPEARANCE=dark SNAP_BACKDROP=docs/design/backdrops/dark-editor.png` and `SNAP_APPEARANCE=light SNAP_BACKDROP=docs/design/backdrops/light-document.png`. The hero's synced captions (`data-at` in `site/index.html`) follow `DesignPreview.Demo.steps` minus 0.3 s.

## Installing a release

Open the DMG, drag Tidewatch to Applications, start it, then **Connect to Claude Code** in the menu bar. Gatekeeper opens it without warnings because the app and the DMG are notarized and stapled.

## Not here yet

- No auto-update (Sparkle) yet.
