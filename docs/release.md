# Release

How a public (installable) Tidewatch build is cut and how installed copies update themselves (Sparkle, as in Captylo). Owner's go-ahead first: notarization uploads the build to Apple, `publish` changes the live page and creates a GitHub release.

## One-time setup (already done on the owner's Mac)

- "Developer ID Application" certificate in the login Keychain (Team `RA8ASXBMDZ`, shared with Captylo).
- notarytool keychain profile `captylo-notary` (shared with Captylo): `xcrun notarytool history --keychain-profile captylo-notary` must succeed.
- Sparkle EdDSA key, Keychain account `tidewatch` (separate from Captylo's key). Public half in `SPARKLE_PUBLIC_ED_KEY` in `project.yml`. Backup: `~/.claude/secrets/tidewatch-sparkle-ed25519.key` (chmod 600, never in git). Print the public key: `.local-build/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_keys --account tidewatch -p`. Restore on a new Mac: `generate_keys --account tidewatch -f <backup>`. `make dist` signs with the backup file when it exists (no Keychain prompt) and falls back to the Keychain account.

## Cutting a release

1. Bump `MARKETING_VERSION` in `project.yml`, commit and push to `main`. The build number (`CFBundleVersion`, what Sparkle compares) is the commit count at build time, so it only grows on `main`. Never rewrite `main`'s history.
2. Write `dist/x.y.z/notes.md` in English (headings, paragraphs, `- ` lists, `**bold**`, `` `code` ``, links). It becomes the update notes page and the GitHub release.
3. Optional: `make dist-dry VERSION=x.y.z` - Developer ID signature and DMG, no notarization; its appcast item (fake signature) lands in `dist/x.y.z/`, `site/updates/` is not touched.
4. `make dist VERSION=x.y.z` (clean tree on `main`) - signs inside-out (Sparkle's XPC services, Updater.app and Autoupdate first), notarizes and staples the app and the DMG, checks both with `spctl`, signs the DMG with `sign_update --account tidewatch` and writes `site/updates/appcast.xml` and `site/updates/notes/x.y.z.html`.
5. Commit `site/updates/` and push.
6. `make site VERSION=x.y.z` - optional local preview at http://localhost:8787/tidewatch/.
7. `make publish VERSION=x.y.z` - `scripts/site.sh deploy` refuses unless the appcast item is newest, signed and matches the DMG size (`appcast.py check`), uploads `Tidewatch-x.y.z.dmg`, repoints `Tidewatch.dmg`, syncs the page with `updates/`, then checks the page, both DMG URLs and the live appcast; then the GitHub release `vx.y.z`. `make deploy-site VERSION=x.y.z` does only the page and the DMG.
8. Check: on an installed older copy, **Check for Updates…** offers the new version.

## Updates (Sparkle)

- Feed: https://kawalec.pl/tidewatch/updates/appcast.xml (`SUFeedURL`), checked once a day (`SUEnableAutomaticChecks`, `SUScheduledCheckInterval` 86400) and from **Check for Updates…** in the menu bar.
- The updater runs only in a public build: a real public key and a build number other than 1 (`AppUpdaterConfiguration`). `make build`, `make release` and the test host never check.
- Local builds signed with "Captylo Dev" get `disable-library-validation` (`make sign`), because a self-signed identity has no Team ID and library validation would refuse Sparkle. Public builds keep library validation.
- Appcast tools: `scripts/appcast.py` (`item`, `notes`, `check`), tests `python3 -m unittest discover -s scripts -p 'test_*.py'` (part of `make test`).
- Losing the private key means no installed copy accepts a new version; the only way out is a new key in a build installed by hand. Keep the backup.

## Download page

- Public URL: https://kawalec.pl/tidewatch/. `craftweb.pl/tidewatch*` redirects there (301). DMG: `/tidewatch/download/Tidewatch.dmg` (newest) and `/tidewatch/download/Tidewatch-x.y.z.dmg` (what the appcast points at).
- Source: `site/` (static HTML, CSS, JS, `updates/`). `scripts/site.sh build` fills `__VERSION__`, `__DMG_SIZE__` and `__DMG_SHA256__` from `dist/<version>/` into `dist/site/`.
- Server (from git-ignored `deploy/local.env`, template `deploy/local.env.example`): the page in `/var/www/tidewatch` (synced with `--delete`), DMGs in `/var/www/tidewatch-downloads`.
- Caddy: snippet `tidewatch_site` under `handle_path /tidewatch/*` in the kawalec.pl block, the redirect in `craftweb_site`; reference copy in `deploy/Caddyfile.tidewatch.snippet`. Back up the live Caddyfile, edit it in place (keep the inode: the container bind-mounts the single file) and run `caddy validate` before a reload.
- kawalec.pl lists the product under **My products** (`#products`, repo `dawidkawalec/kawalec_all`, `websie-lp/index.html`).
- Videos: `scripts/record-demo.sh site/assets/video/demo-<name>` records the `widget-demo` preview (needs `make build`, ffmpeg, cwebp, Screen Recording permission). Re-record after visible UI changes: dusk (default backdrop), `SNAP_APPEARANCE=dark SNAP_BACKDROP=docs/design/backdrops/dark-editor.png` and `SNAP_APPEARANCE=light SNAP_BACKDROP=docs/design/backdrops/light-document.png`. The hero's synced captions (`data-at` in `site/index.html`) follow `DesignPreview.Demo.steps` minus 0.3 s. The cut is found in the recording itself (`scripts/demo_phase.py` looks for the list welling out at the demo's expand step), because screencapture's start-up delay varies. Quit the real Tidewatch while recording: its widget sits on the same screen edge.

## Installing a release

Open the DMG, drag Tidewatch to Applications, start it, then **Connect to Claude Code** in the menu bar. Gatekeeper opens it without warnings because the app and the DMG are notarized and stapled. From 0.3.0 on, updates arrive through Sparkle.
