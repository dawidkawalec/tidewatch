# Tidewatch

Native macOS widget: a column of glass status lamps on the right screen edge that shows every running Claude Code session (working, needs approval, awaiting review, idle) and opens the right VS Code window on click.

**Identity**: bundle `pl.craftweb.tidewatch`, product `Tidewatch.app`, data in `~/Library/Application Support/Tidewatch/`, log subsystem `pl.craftweb.tidewatch`, macOS 14.4+, arm64 only. Private repo `dawidkawalec/session-widget`, Plane project `TIDEWATCH`. Design language copied from Captylo (`<captylo-repo>`).

## Stack

- **App**: Swift 6 (strict concurrency), SwiftUI + AppKit panel, menu bar extra → `Tidewatch/`
- **Core logic**: Swift package (session model, hook reducer, display rules) → `Packages/TidewatchCore/`
- **Hook helper**: command line tool called by Claude Code hooks, writes `sessions/<id>.json` → `TidewatchHook/`
- **Project**: XcodeGen `project.yml` → generated `Tidewatch.xcodeproj` (git-ignored, never hand-edit)
- **Tests**: Swift Testing → `Packages/TidewatchCore/Tests/`, `TidewatchTests/`

## Commands

```bash
make gen      # xcodegen generate (after adding/removing files)
make build    # Debug build into .local-build/
make test     # unit tests (core package + app)
make release  # Release build to ~/Downloads, signed with "Captylo Dev" (or ad-hoc)
make install  # release + copy to /Applications
scripts/snap.sh <target> <out.png>   # screenshot a design preview target (fake sessions)
```

## Docs

- [docs/specs/2026-10-10-tidewatch-design.md](docs/specs/2026-10-10-tidewatch-design.md) - MVP spec: statuses, event mapping, UI, hook install, spike
- [docs/architecture.md](docs/architecture.md) - modules, data flow, decisions
- [docs/coding-standards.md](docs/coding-standards.md) - Swift 6 rules, UI tokens, tests, git

## Critical Rules

- The helper is the only writer of session files; it writes atomically under a file lock, never prints to stdout, never touches the network and always exits 0. It must never block or change Claude Code's behavior.
- `HookInstaller` touches only Tidewatch's own entries in `~/.claude/settings.json` (identified by the helper path), always backs the file up first and refuses invalid JSON.
- The widget panel never activates the app or takes focus (`orderFrontRegardless()`, no `NSApp.activate`, no `makeKey`).
- No ad-hoc colors, materials or `glassEffect` in views: use `UI/Glass` tokens and `widgetGlass`. Check UI with `scripts/snap.sh` against the mockups in `docs/design/`.
- A change is done only when `make build` and `make test` pass. No new dependencies without a note in `docs/architecture.md`.
- No long dashes in any text (UI, docs, commits): use "-". No secrets, real prompts or private paths in fixtures.
