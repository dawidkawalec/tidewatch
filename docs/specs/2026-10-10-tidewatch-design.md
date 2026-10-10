# Tidewatch - design spec (MVP)

Date: 2026-10-10. Status: approved by the owner; spike results folded in (6.3).

## 1. Goal

A tiny native macOS widget that shows the state of every running Claude Code session as a column of glass status lamps glued to the right edge of the screen. One glance tells which agent works, which one waits for approval and which one is done. One click brings the right VS Code window and the right Claude Code tab to the front.

**For whom:** the owner (Dawid), who runs several Claude Code sessions in parallel, mostly in the Claude Code VS Code extension.

**Success criteria**

1. A session that asks for permission turns its lamp orange within ~1 s (6 s worst case, see 4.3) and plays a sound.
2. A session that finishes its turn turns orange ("Awaiting review") and plays a different sound.
3. Clicking a session row focuses the VS Code window of that project and opens that session's tab.
4. The widget never steals focus, never slows Claude Code down and survives its own restart without losing the session list.
5. It looks like Captylo (Dusk Glass in Deep Tide) and like the reference mockups.

**Out of scope for the MVP:** Codex and other agents, stopping an agent, starting a new session ("+"), keyboard shortcuts, a hover card for a single lamp, Sparkle updates, notarized public builds, a settings window.

## 2. Decisions (from the conversation)

| Topic | Decision |
|---|---|
| Repo | Separate private GitHub repo `session-widget`; app name **Tidewatch** |
| Platform | Native: Swift 6, SwiftUI + AppKit, XcodeGen, macOS 14.4+, arm64 |
| Design | Captylo's Dusk Glass (tokens and glass surface copied from the Captylo repo, owner is the author) |
| Agents | Claude Code only (VS Code extension first, CLI works too) |
| Status source | Claude Code hooks in `~/.claude/settings.json` |
| Transport | Option A: the hook helper writes one state file per session, the app watches the folder |
| Interaction | Hover over the column = full session list; click a row = switch to its VS Code window; right click = Show in Finder |
| Position | Right screen edge, vertically centered, always visible |
| Sounds | Yes, one for "needs approval", one for "finished" |
| Shortcuts | None |
| UI language | English, as in the mockups ("AI Agents", "Needs approval"); one language, no string catalog in the MVP |

## 3. Architecture

Three parts in one repo:

| Part | Kind | Job | Depends on |
|---|---|---|---|
| `TidewatchCore` | Swift package (library) | Session model, hook event decoding, the reducer `(SessionState?, HookEvent) -> SessionState`, display rules (status at a given time, labels, ordering), and `SessionFileStore` (locked, atomic read/write of the session files, shared by the helper and the app) | Foundation only |
| `tidewatch-hook` | Command line tool, embedded in `Tidewatch.app/Contents/MacOS/` | Reads one hook event from stdin, applies the reducer to `sessions/<session_id>.json` through `SessionFileStore`, exits 0 | `TidewatchCore` |
| `Tidewatch.app` | SwiftUI + AppKit app (`LSUIElement`, menu bar extra) | Watches the sessions folder, renders the lamps and the panel, plays sounds, opens VS Code, installs the hooks | `TidewatchCore` |

Data folder: `~/Library/Application Support/Tidewatch/`
- `sessions/<session_id>.json` - current state of one session
- `bin/tidewatch-hook` - stable copy of the helper. The app refreshes it on every launch, so moving or updating the app never breaks the hook path in `settings.json`.

### 3.1 Data flow

```
Claude Code (VS Code ext / CLI)
  -> hook event JSON on stdin
  -> ~/Library/Application Support/Tidewatch/bin/tidewatch-hook
       flock sessions/<id>.json, read, reduce, write tmp, rename
  -> sessions/<id>.json
  -> Tidewatch.app: DispatchSource folder watch (debounced 100 ms) -> SessionStore (@Observable)
  -> SwiftUI: LampColumn / SessionPanel, SoundPlayer on status transitions
```

### 3.2 Session state file

```json
{
  "schema": 1,
  "sessionId": "abc-123",
  "cwd": "/Users/demo/captylo-app",
  "project": "captylo-app",
  "title": "Fix login form",
  "host": "vscode",
  "pid": 41234,
  "status": "working",
  "activity": "runningTests",
  "detail": "npm test",
  "statusSince": "2026-10-10T09:41:00Z",
  "firstSeen": "2026-10-10T09:12:00Z",
  "lastEvent": "2026-10-10T09:41:03Z"
}
```

- `host`: `vscode` when `CLAUDE_CODE_ENTRYPOINT` is `claude-vscode` (confirmed by the spike; `VSCODE_PID` is set too), else `terminal` with the terminal app from `TERM_PROGRAM`. The CLI in VS Code's own terminal is `terminal` with `terminalApp = "vscode"`: a click opens its folder in VS Code but never the extension's session URL, which would resume the live session a second time.
- `pid`: the Claude Code process = the helper's parent (`getppid()`). The spike showed the hook command runs as a direct child of the native `claude` binary, with no shell in between. Lets the app drop a crashed session at once; the TTL in 4.2 stays as a fallback.
- `backgroundTasks`: count of running entries in `Stop.background_tasks` (shown as a hint, see 4.1).
- Unknown fields are ignored and missing optional fields are fine, so the schema can grow.

## 4. Statuses

### 4.1 Event mapping (reducer, in `TidewatchCore`)

| Hook event | New status | Activity / detail |
|---|---|---|
| `SessionStart` | `idle` | title from `session_title` when present |
| `UserPromptSubmit` | `working` | `thinking` |
| `PreToolUse` | `working` | from the tool, see 4.4 |
| `PostToolUse`, `PostToolUseFailure` | `working` (clears `needsApproval`) | keeps the activity |
| `SubagentStart`, `PreCompact` | `working` | `runningAgents` / `compacting` |
| `PermissionRequest` | `needsApproval` | tool name + short command or file name; for `AskUserQuestion` the label is "Needs your answer" (the spike showed Claude's questions also come through `PermissionRequest`) |
| `Notification` with `notification_type = permission_prompt` | `needsApproval` (fallback if `PermissionRequest` did not fire) | message |
| `Notification` with `idle_prompt` | `working` becomes `idle`; other statuses unchanged | Esc mid-turn fires no `Stop`, so Claude waiting for input (~60 s) is the only sign the turn ended (final review) |
| `Stop` | `awaitingReview` | `backgroundTasks` = running entries in `background_tasks`; the row adds "· 1 background task" |
| `SessionEnd` | file deleted by the helper | |

`statusSince` changes only when the status changes, not on every heartbeat. `lastEvent` changes on every event.

### 4.2 Time rules (app side, pure function `displayStatus(state, now, acknowledged)`)

| Rule | Result |
|---|---|
| `awaitingReview` and the user clicked the session in Tidewatch after `lastEvent` | `idle` |
| `awaitingReview` for more than 10 min | `idle` |
| `pid` known and the process is gone | session removed |
| `pid` known, process alive, no event for 48 h | session removed (guard against a recycled pid) |
| `pid` unknown, no event for 6 h | session removed |

A denied permission has no hook, so `needsApproval` clears only on the next event from that session (a new prompt, a tool event or Stop). Accepted for the MVP.

"Acknowledged" lives in the app's memory plus `UserDefaults` (`sessionId -> lastEvent at click`). The app never writes to the session files, so the helper is the only writer.

### 4.3 Colors and lamps

| Status | Lamp | Text | Sound |
|---|---|---|---|
| `working` | green #4CD68A, slow pulse (opacity and halo, ~2 s cycle) | white 70 %, activity label | none |
| `needsApproval` | orange (new token `GlassColor.attention`, ~#FF9F43, tuned against the mockups), still | orange | "approval" sound |
| `awaitingReview` | orange, still | white 70 % "Awaiting review" | "done" sound |
| `idle` | white 35 %, still | white 50 % "Idle" | none |

Timing (measured in the spike, VS Code extension): `PermissionRequest` fires immediately; `Notification permission_prompt` follows about 6 s later and only confirms the state.

### 4.4 Activity labels

| Tool | Label |
|---|---|
| `Bash` with a test-like command (`test`, `jest`, `vitest`, `pytest`, `xcodebuild test`, `make test`, `swift test`) | Running tests… |
| `Bash`, other | Running commands… |
| `Edit`, `Write`, `MultiEdit`, `NotebookEdit` | Coding… |
| `Read`, `Grep`, `Glob`, `LS` | Reading code… |
| `WebSearch`, `WebFetch` | Researching… |
| `Task` / `Agent` | Running agents… |
| `mcp__*` | Using tools… |
| (`PreCompact`) | Compacting… |
| anything else, or `thinking` | Working… |

## 5. Window and UI

### 5.1 Lamp column (collapsed)

- `NSPanel`, the same recipe as Captylo's `RecorderPanel`: `[.borderless, .nonactivatingPanel, .fullSizeContentView]`, `level = .floating`, `collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]`, `hidesOnDeactivate = false`, clear background, `canBecomeKey = false`, shown with `orderFrontRegardless()`. Never activates the app.
- On the screen with the menu bar, glued to its right edge with an 8 pt gap, vertically centered on the visible frame. Follows screen changes (`NSApplication.didChangeScreenParametersNotification`).
- Capsule of dark widget glass, 36 pt wide. Lamps are 12 pt in diameter with a 26 pt pitch (tuned in the design preview against the mockups).
- Stable order: by `firstSeen`. The color stands out, the position never jumps.
- More than 6 sessions: the first 6 lamps and a chevron below them.
- No sessions: one dim lamp, so it is clear the app runs.

### 5.2 Session panel (expanded)

- Opens after 280 ms of hover and closes 450 ms after the pointer leaves the column and the panel (Captylo's `RecorderMetrics`). Captylo's spring (`response 0.38, damping 0.85`). Glass morph between the shapes on macOS 26, scale + opacity on 14/15, cross-fade only under Reduce Motion.
- Sits left of the column, 280 pt wide, 28 pt corner radius, vertically centred on it. No notch: two glass shapes do not join cleanly on macOS 14/15, and the 10 pt gap reads as one widget.
- Header: "AI Agents" (Manrope SemiBold 15) and a count badge.
- Row (46 pt min height): lamp, project name (Inter 14, white 95 %), status line (Inter 12), time in the current status (`2m`, `1h`, monospaced digits), VS Code glyph (or the terminal glyph for terminal sessions). Hovered row: white 8 % fill. Hovering a lamp in the column highlights its row.
- Two sessions in the same folder: the second line shows the session title to tell them apart.
- More than 8 rows: the list scrolls.
- Click on a row: open the session (5.3), mark it acknowledged, close the panel.
- Right click: context menu with "Show in Finder".

### 5.3 Opening a session

1. VS Code session: `NSWorkspace.shared.open([cwdURL], withApplicationAt: <VS Code app URL>)`. This brings the window that already has the folder open to the front, or opens one.
2. After 400 ms: open `vscode://anthropic.claude-code/open?session=<sessionId>`. This focuses that session's Claude Code tab, or resumes it if it is closed.
3. Verified in the spike with 7 VS Code windows open, another window focused and a file as the active editor: the right window and the right Claude tab came to the front in 0.9 s.
4. The first time, VS Code asks "Allow 'Claude Code for VS Code' extension to open this URI?" once. Ticking "Do not ask me again for this extension" makes every later click direct. The README and the first-run hint say so.
5. Terminal session: activate the app from `host` (Terminal, iTerm, Ghostty, Warp), no tab targeting in the MVP.
6. VS Code is looked up by bundle id `com.microsoft.VSCode`. If it is missing, the click opens the session folder in Finder.

### 5.4 Menu bar extra

A small glass lamp icon. Items: "Connect to Claude Code" (or "Connected" with "Disconnect"), "Sounds" toggle, "Launch at login" toggle (`SMAppService.mainApp`), "Quit".

### 5.5 Sounds

- System sounds through `NSSound`: approval = "Glass", done = "Tink" (easy to change in one place).
- Played on a status transition only, at most one sound per 2 s. Silent for the first 3 s after launch, so reloading existing state does not ring.
- Off when the "Sounds" toggle is off.

## 6. Hook installation and the spike

### 6.1 HookInstaller

- "Connect to Claude Code" adds Tidewatch entries to `~/.claude/settings.json` under `hooks` for: `SessionStart`, `SessionEnd`, `UserPromptSubmit`, `PreToolUse`, `PostToolUse`, `PostToolUseFailure`, `PermissionRequest`, `Notification`, `Stop`, `SubagentStart`, `PreCompact`. Tool events use the matcher `*`.
- Each entry: `{"type": "command", "command": "\"<data>/bin/tidewatch-hook\"", "timeout": 5}`. The command path identifies Tidewatch entries, so "Disconnect" removes exactly those and nothing else.
- **Synchronous, not async:** order matters (`PreToolUse` must not land after `PostToolUse`), and async hooks are killed at teardown, which would lose `SessionEnd`. The helper is a native binary that does one small locked write and exits 0, so the cost per event is a few milliseconds. The spike measures it. The helper never prints to stdout, never touches the network and exits 0 even on its own errors, so it cannot block or change Claude's behavior.
- Before writing, a backup goes to `~/.claude/settings.json.tidewatch-backup`. Other keys and other hooks are kept as they are. Key order and formatting may change (JSON is re-serialized pretty-printed).
- On every launch the app checks that the entries point to the current helper path and repairs them if needed (only when the user has connected before).
- Workspace trust: user-scope hooks wait until a workspace's trust dialog is accepted. This goes in the README's troubleshooting.

### 6.2 Spike (first task of the implementation, ~30 min, throwaway)

A temporary logging hook (one shell line appending stdin plus selected env vars to a log file) in the owner's `~/.claude/settings.json`, after the owner's explicit go-ahead. Checks:

1. Does `PermissionRequest` fire in the VS Code extension, and how late does `Notification permission_prompt` come?
2. Which env vars tell the VS Code extension from the CLI (`CLAUDE_CODE_ENTRYPOINT`, `TERM_PROGRAM`, `VSCODE_*`)?
3. Is `session_title` present on `SessionStart`?
4. What is the helper's process ancestry (to find the Claude Code `pid`)?
5. With two VS Code windows open, does open-folder + `vscode://anthropic.claude-code/open?session=` land on the right window and tab?

The results update this spec (sections 3.2, 4.1, 5.3) before the code that depends on them is written. The temporary hook is removed at the end of the spike.

### 6.3 Spike results (2026-10-10)

Run on the owner's Mac against real VS Code extension sessions (Claude Code 2.1.296 in the extension):

| Question | Answer |
|---|---|
| 1. `PermissionRequest` in VS Code | Fires immediately. `Notification permission_prompt` follows ~6 s later. `PostToolUse` arrives right after the user answers. `AskUserQuestion` goes through `PermissionRequest` too |
| 2. Host detection | `CLAUDE_CODE_ENTRYPOINT=claude-vscode`, `VSCODE_PID` set, `TERM_PROGRAM` empty |
| 3. `session_title` on `SessionStart` | Not observed yet (no session started during the spike). The folder name is the label; the title is an optional extra |
| 4. Process ancestry | Hook command's parent = native `claude` binary, then VS Code's extension host, then VS Code. `getppid()` is the Claude pid |
| 5. Window + tab focus | Works, 0.9 s, see 5.3. One-time VS Code consent dialog for the extension's URIs |
| Extra | Hooks reload live after editing `settings.json`, no restart. Parallel sessions write at the same moment (interleaved log lines), so the helper's `flock` is required. Traffic is heavy: ~430 `PreToolUse` events in ~30 min across 2 sessions, so the helper must stay a few ms per event. `Stop` carries `background_tasks`. The "Claude Status" app on this Mac uses the same hook pattern (sync, timeout 5) and coexists |

Payloads saved during the spike contain real prompts from other projects: they are deleted after the spike, and fixtures are hand-written from their shape.

## 7. Code layout

```
project.yml, Makefile, AGENTS.md, CLAUDE.md, README.md
Packages/TidewatchCore/        Sources/TidewatchCore/*.swift, Tests/TidewatchCoreTests/*.swift
TidewatchHook/main.swift       the helper
Tidewatch/App/                 TidewatchApp, AppState, MenuBarContent
Tidewatch/Sessions/            SessionStore, SessionFolderWatcher, AcknowledgedStore
Tidewatch/Integration/         HookInstaller, HelperInstaller, SessionOpener, SoundPlayer, ProcessLiveness
Tidewatch/UI/Glass/            GlassTokens, GlassSurface (from Captylo, trimmed to what is used)
Tidewatch/UI/Widget/           WidgetPanel, WidgetPanelController, LampColumn, StatusLamp, SessionPanel, SessionRow
Tidewatch/UI/Preview/          design preview targets with fake sessions
Tidewatch/Resources/           Fonts (Manrope, Inter), Assets (AppIcon, MenuBarIcon, VS Code glyph)
TidewatchTests/                app-side tests (HookInstaller, SessionStore)
scripts/                       snap.sh (design preview screenshot), sign-app.sh
```

## 8. Error handling

| Case | Behavior |
|---|---|
| Helper cannot parse stdin or write the file | exits 0, logs one line to `os_log` (subsystem `pl.craftweb.tidewatch`), Claude continues |
| Corrupt or half-written state file | impossible by design (write to tmp + rename). An unreadable file is skipped and logged, never crashes the app |
| `settings.json` missing | created with only the `hooks` key |
| `settings.json` is invalid JSON | installer refuses, shows an alert, changes nothing |
| VS Code not installed | rows still open the folder in Finder on click |
| App not running | the helper keeps writing files, so the app shows the right state when it starts |
| Clock or sleep jumps | durations are computed from timestamps at render time, never from timers |

## 9. Testing

- **Swift Testing, `TidewatchCore`:** reducer for every event in 4.1 including out-of-order and repeated events, `displayStatus` time rules, activity labels (4.4), session ordering, duplicate project names, decoding real hook payloads saved by the spike as fixtures (scrubbed of private paths and prompts).
- **Swift Testing, app:** `HookInstaller` against fixture `settings.json` files (empty, missing, existing hooks of other tools, already connected, invalid JSON, disconnect removes only Tidewatch entries), `SessionStore` loading a fixture folder.
- **Helper end to end:** a test pipes fixture events into the built binary with a temp data folder (`TIDEWATCH_DATA_DIR`) and checks the resulting file.
- **UI:** design preview with fake sessions in every status (`--design-preview <target>`), screenshots through `scripts/snap.sh`, compared with the mockups. Not unit-tested.
- **Manual acceptance:** the success criteria in section 1, run against real Claude Code sessions in VS Code.
- Done means: `make gen`, `make build`, `make test` all pass.

## 10. Distribution (MVP)

`make release` builds Release, copies `Tidewatch.app` to `~/Downloads`, signs it with the local "Captylo Dev" identity (same keychain recipe as Captylo) or ad-hoc. `make install` copies it to `/Applications`. Developer ID, notarization and Sparkle come later, if ever needed.
