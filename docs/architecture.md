# Architecture

Status: built (MVP, 2026-10-10), installed and accepted end to end against real Claude Code sessions in VS Code. The full design is in [specs/2026-10-10-tidewatch-design.md](specs/2026-10-10-tidewatch-design.md); this file tracks the current state of the code and the decisions behind it.

## Modules

| Module | Where | Job |
|---|---|---|
| `TidewatchCore` | `Packages/TidewatchCore/` | Session model, hook event decoding, reducer `(SessionState?, HookEvent) -> SessionState`, `displayStatus` time rules, activity labels, ordering, window grouping and row names, Claude Code's registry and transcript title parsing (`ClaudeRegistry`), merge of both sources (`SessionMerge`). Foundation only, fully unit-tested |
| `tidewatch-hook` | `TidewatchHook/` | Reads one hook event from stdin, reduces it into `sessions/<session_id>.json` under `flock`, writes tmp + rename, exits 0 |
| App: sessions | `Tidewatch/Sessions/` | Folder watcher (DispatchSource, 100 ms debounce), `SessionStore` (`@Observable`, sessions grouped by window), acknowledged sessions, `ClaudeSystem` (registry, process table, `TranscriptReader`) |
| App: updates | `Tidewatch/App/AppUpdater*.swift` | Sparkle wrapper and the testable configuration rules (feed, key, public build) |
| App: integration | `Tidewatch/Integration/` | `HookInstaller` (settings.json), `HelperInstaller` (stable helper copy), `SessionOpener` (VS Code / terminal), `SoundPlayer`, process liveness |
| App: UI | `Tidewatch/UI/` | Glass tokens from Captylo, the widget `NSPanel`, lamp column, session panel, design preview (static targets and the scripted `widget-demo` cycle) |
| Download page | `site/` | Static page for kawalec.pl/tidewatch (with the Sparkle appcast in `site/updates/`), built and deployed by `scripts/site.sh`; its looping videos are recorded from `widget-demo` by `scripts/record-demo.sh` |

## Data flow

```
Claude Code hook event (stdin JSON)
  -> ~/Library/Application Support/Tidewatch/bin/tidewatch-hook
  -> ~/Library/Application Support/Tidewatch/sessions/<id>.json
  -> folder watcher -> SessionStore -> lamp column / session panel, sounds
~/.claude/sessions/<pid>.json (Claude Code's list of running processes, read every reload)
  -> SessionMerge: adds open tabs without hook events, the window's folder as the name
~/.claude/projects/<folder>/<id>.jsonl (only the last 256 KB, only the title lines)
  -> conversation started? and its title
parent pid of the claude process = the VS Code window (extension host) -> groups
click on a row -> open folder in VS Code -> vscode://anthropic.claude-code/open?session=<id>
```

## Decisions

| Decision | Why |
|---|---|
| Hooks for status, not transcript parsing | Transcript JSONL is internal and unstable; only hooks give a reliable "needs approval" signal. The transcript is read only for the conversation's title and to tell an empty tab from a conversation |
| Every open tab, grouped by VS Code window (owner's call, 2026-10-11) | Hooks alone missed tabs that fired no event since Tidewatch started, and a lamp took its name from the agent's latest `cd`. Claude Code's own registry (`~/.claude/sessions/<pid>.json`: session, start folder, busy/waiting/idle) lists every process; the process's parent is its window. Undocumented, so it is read tolerantly and a failure falls back to the hooks. Empty tabs stay hidden. A window with several tabs gets a header and a gap in the column; one tab per window looks like before |
| Restart from the widget and the menu bar | A shell waits for the old process to quit, then `open`s the bundle again; no helper app needed |
| One state file per session (not a socket) | State survives app restarts, the app can be off, easy to inspect and debug |
| Synchronous hooks with a 5 s timeout | Keeps event order and `SessionEnd`; the native helper costs a few ms |
| Stable helper copy in Application Support | Moving or updating the app never breaks the command path stored in `settings.json` |
| The app never writes session files | One writer, no lock contention; "acknowledged" lives in `UserDefaults` |
| Glass code copied from Captylo, not shared as a package | Captylo is a separate GPLv3 repo; the owner authored it and releases the trimmed copy here under Tidewatch's MIT license |
| Open source under MIT (2026-10-11) | The owner's call; fixtures, previews and docs use invented project names and `/Users/demo` paths, never real client sessions |
| Native Liquid Glass with adaptive type, following the system appearance; gem lamps; soft lift shadow and a hairline | The owner picked it (2026-10-10) over the dark smoked MVP glass and a bead variant, compared on photo, light-document and dark-editor backdrops. Fixed white type had lost contrast over white documents; adaptive `.primary`/`.secondary` stays readable on any background |
| Light glass: a window-server blur (`WindowBlur`, `CGSSetWindowBackgroundBlurRadius`) under a tinted fill, sheen and rim; the settings window ("Settings…" in the menu bar, the widget's context menu and the gear in the panel header) has sliders for blur (0-20 pt, default 8) and tint (0-60 %, default 25), appearance (system / light / dark: dark glass over dark pages on a light system), a text-contrast halo and the "Awaiting review" fade (5 / 10 / 30 min / never); the widget stays expanded while it is in front; no Liquid Glass (2026-10-11) | The owner wants to read what is behind the widget. Liquid Glass (even `Glass.clear`) and every system material blur at a fixed, large radius; `.opacity` or `alphaValue` on them drops the blur entirely, and the `CABackdropLayer` of a behind-window `NSVisualEffectView` is not what draws the blur. The window server's per-window radius blurs only behind visible pixels, so the canvas around the glass stays clear. Private call, looked up with `dlsym`: if it disappears the glass has no blur, nothing breaks. The orange status text is a deeper orange in light mode to stay readable |
| Pointer tracked by a 150 ms poll of `NSEvent.mouseLocation` plus a tracking area | The panel is never key, so SwiftUI `onHover` is unreliable; lamp and row hit tests come from `WidgetMetrics` |
| Disconnect drops event arrays left empty | For Claude Code an empty hook array equals a missing key; no extra state needed |
| A played sound is logged at `notice` level | The only way to verify sounds from outside; `info` is not persisted by the unified log |
| Download page on kawalec.pl, not its own domain | One static folder on the VPS served at kawalec.pl/tidewatch/ through one Caddy snippet (`deploy/Caddyfile.tidewatch.snippet`); craftweb.pl/tidewatch redirects there; the DMGs sit outside the page folder behind a `Tidewatch.dmg` symlink, as in Captylo |
| Sparkle updates, a daily check (owner's call, 2026-10-10) | Same setup as Captylo (2.9.4, EdDSA appcast, inside-out signing). The app's only network access: `kawalec.pl/tidewatch/updates/appcast.xml` once a day, nothing about the user or sessions. Off in development builds (build number 1) and in the preview and test host |
| Page videos recorded from the app, not mocked | `widget-demo` plays a periodic, drift-free 12 s cycle that ends on its first frame, so a one-period cut loops seamlessly and always shows the real glass and motion |
| Page fonts self-hosted (Funnel Display, Mozilla Text, as on kawalec.pl) | The page makes no third-party requests and sets no cookies |

## Dependencies

- **Sparkle 2.9.4** (MIT, SwiftPM, `project.yml`): software updates. Pinned with `exactVersion`, the same version as Captylo.
- XcodeGen is a build tool only. `ffmpeg` and `cwebp` (Homebrew) are needed only to record the page videos.
