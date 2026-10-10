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
5. `make publish VERSION=x.y.z` - GitHub release `vx.y.z` with the DMG on the private repo.

## Installing a release

Open the DMG, drag Tidewatch to Applications, start it, then **Connect to Claude Code** in the menu bar. Gatekeeper opens it without warnings because the app and the DMG are notarized and stapled.

## Not here yet

- No auto-update (Sparkle) and no public download page: the owner installs from the private GitHub release.
