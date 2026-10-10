# Architecture

Status: built (MVP, 2026-10-10), installed and accepted end to end against real Claude Code sessions in VS Code. The full design is in [specs/2026-10-10-tidewatch-design.md](specs/2026-10-10-tidewatch-design.md); this file tracks the current state of the code and the decisions behind it.

## Modules

| Module | Where | Job |
|---|---|---|
| `TidewatchCore` | `Packages/TidewatchCore/` | Session model, hook event decoding, reducer `(SessionState?, HookEvent) -> SessionState`, `displayStatus` time rules, activity labels, ordering. Foundation only, fully unit-tested |
| `tidewatch-hook` | `TidewatchHook/` | Reads one hook event from stdin, reduces it into `sessions/<session_id>.json` under `flock`, writes tmp + rename, exits 0 |
| App: sessions | `Tidewatch/Sessions/` | Folder watcher (DispatchSource, 100 ms debounce), `SessionStore` (`@Observable`), acknowledged sessions |
| App: integration | `Tidewatch/Integration/` | `HookInstaller` (settings.json), `HelperInstaller` (stable helper copy), `SessionOpener` (VS Code / terminal), `SoundPlayer`, process liveness |
| App: UI | `Tidewatch/UI/` | Glass tokens from Captylo, the widget `NSPanel`, lamp column, session panel, design preview |

## Data flow

```
Claude Code hook event (stdin JSON)
  -> ~/Library/Application Support/Tidewatch/bin/tidewatch-hook
  -> ~/Library/Application Support/Tidewatch/sessions/<id>.json
  -> folder watcher -> SessionStore -> lamp column / session panel, sounds
click on a row -> open folder in VS Code -> vscode://anthropic.claude-code/open?session=<id>
```

## Decisions

| Decision | Why |
|---|---|
| Hooks, not transcript parsing | Transcript JSONL is internal and unstable; only hooks give a reliable "needs approval" signal |
| One state file per session (not a socket) | State survives app restarts, the app can be off, easy to inspect and debug |
| Synchronous hooks with a 5 s timeout | Keeps event order and `SessionEnd`; the native helper costs a few ms |
| Stable helper copy in Application Support | Moving or updating the app never breaks the command path stored in `settings.json` |
| The app never writes session files | One writer, no lock contention; "acknowledged" lives in `UserDefaults` |
| Glass code copied from Captylo, not shared as a package | Captylo is a separate public GPLv3 repo; the owner authored it, the copy is trimmed to what the widget uses |
| Native Liquid Glass (`Glass.regular`) with adaptive type, following the system appearance; gem lamps; soft lift shadow and a hairline | The owner picked it (2026-10-10) over the dark smoked MVP glass and a bead variant, compared on photo, light-document and dark-editor backdrops. Fixed white type had lost contrast over white documents; adaptive `.primary`/`.secondary` stays readable on any background |
| Pointer tracked by a 150 ms poll of `NSEvent.mouseLocation` plus a tracking area | The panel is never key, so SwiftUI `onHover` is unreliable; lamp and row hit tests come from `WidgetMetrics` |
| Disconnect drops event arrays left empty | For Claude Code an empty hook array equals a missing key; no extra state needed |
| A played sound is logged at `notice` level | The only way to verify sounds from outside; `info` is not persisted by the unified log |

## Dependencies

None beyond Apple frameworks. XcodeGen is a build tool only.
