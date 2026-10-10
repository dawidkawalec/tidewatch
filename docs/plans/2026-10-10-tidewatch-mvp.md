# Tidewatch MVP Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A native macOS widget that shows every running Claude Code session as a glass status lamp on the right screen edge, expands into a session list on hover, plays sounds on "needs approval" / "finished", and opens the right VS Code window and Claude tab on click.

**Architecture:** A pure Swift package (`TidewatchCore`) holds the session model, hook event decoding, the reducer and the locked file store. A tiny command line helper (`tidewatch-hook`), called by Claude Code hooks, reduces each event into `~/Library/Application Support/Tidewatch/sessions/<id>.json`. The SwiftUI + AppKit app watches that folder and renders a non-activating `NSPanel` in Captylo's Dusk Glass.

**Tech Stack:** Swift 6 (strict concurrency), SwiftUI + AppKit, XcodeGen 2.46, Xcode 26, Swift Testing, macOS 14.4+, arm64. No third-party dependencies.

**Spec:** [docs/specs/2026-10-10-tidewatch-design.md](../specs/2026-10-10-tidewatch-design.md). Read it before any task.

## Global Constraints

- Bundle id `pl.craftweb.tidewatch`; product `Tidewatch.app`; helper product `tidewatch-hook`; log subsystem `pl.craftweb.tidewatch`.
- Data folder `~/Library/Application Support/Tidewatch/` (`sessions/`, `bin/tidewatch-hook`); `TIDEWATCH_DATA_DIR` overrides it (tests, previews).
- macOS 14.4+, arm64 only, not sandboxed, hardened runtime on. Swift 6 language mode, `SWIFT_STRICT_CONCURRENCY=complete`, no default MainActor isolation: UI types are `@MainActor`.
- No third-party dependencies. Fonts: Manrope + Inter copied from Captylo (SIL OFL).
- UI text in English, as in the mockups. No long dashes anywhere (UI, docs, comments, commit messages): use "-".
- The helper never prints to stdout, never touches the network, always exits 0.
- The widget panel never activates the app: `orderFrontRegardless()`, no `NSApp.activate`, no `makeKey`.
- No ad-hoc colors or materials in views: tokens in `Tidewatch/UI/Glass/`.
- Fixtures never contain real prompts, private paths or secrets (use `/Users/demo/...`).
- **Commits only when the owner says "commituj"** (owner's rule). Tasks end with a checkpoint, not a commit. Commit messages, when asked: imperative, no attribution lines, no AI mentions.
- Done for any task: `make build` and `make test` pass (from Task 1 on).

## Review Focus

1. **Malformed or unexpected hook payloads** (garbage stdin, `tool_input` of another shape, huge `tool_response`, unknown event names): the helper exits 0 quickly and leaves the state file untouched. Pinned in Task 2 (decoding) and Task 6 (`scripts/test-hook.sh`).
2. **A session id with path characters** (`../evil`): nothing is written outside `sessions/`. Pinned in Task 6 (`SessionFileStoreTests.rejectsPathTraversal`, `test-hook.sh`).
3. **Parallel tool calls while an approval is pending**: a `PostToolUse` of a different tool must not clear `needsApproval`; the matching one must. Pinned in Task 4 (`SessionReducerTests.unrelatedPostKeepsApproval`).
4. **Other hooks in `settings.json`** (the owner's own hooks, empty arrays, booleans, symlinked file): connect and disconnect keep them exactly; invalid JSON is never overwritten. Pinned in Task 7 (`HookInstallerTests`).
5. **App restart with leftover files of dead or stale sessions**: they are removed and no sound plays at launch. Pinned in Task 8 (`SessionStoreTests`) and Task 11 (`SoundPlayerTests.silentRightAfterLaunch`).

---

## File Structure

```
project.yml                     XcodeGen source (app, helper, tests)
Makefile                        gen / build / test / release / sign / install / run
.gitignore                      (exists)
AGENTS.md, CLAUDE.md, README.md
Packages/TidewatchCore/
  Package.swift
  Sources/TidewatchCore/
    SessionStatus.swift         SessionStatus, SessionActivity, SessionHost
    SessionState.swift          the per-session state file model
    SessionCoding.swift         JSON encoder/decoder with ISO 8601 dates
    HookEvent.swift             tolerant decoding of one hook payload
    ActivityClassifier.swift    tool -> activity, test command detection
    ApprovalDetail.swift        short detail + signature of a tool call
    SessionReducer.swift        (SessionState?, HookEvent) -> outcome
    DisplayRules.swift          time rules, ordering, labels, names, elapsed
    HostDetector.swift          vscode / terminal from the environment
    DataPaths.swift             data folder, sessions folder, helper path
    SessionFileStore.swift      flock + atomic write, loadAll, remove
  Tests/TidewatchCoreTests/     one test file per source file above
TidewatchHook/main.swift        the helper
Tidewatch/
  App/                          TidewatchApp, AppDelegate, AppState, AppSettings, LaunchMode, Log
  Sessions/                     SessionStore, SessionFolderWatcher, AcknowledgedStore, ProcessLiveness
  Integration/                  HookInstaller, HelperInstaller, SessionOpener, SoundPlayer, LaunchAtLogin
  UI/Glass/                     GlassTokens, WidgetGlass, GlassContainer, Color+Hex
  UI/Widget/                    WidgetMetrics, WidgetModel, WidgetPanel, WidgetPanelController, WidgetRootView,
                                WidgetActions, LampColumn, StatusLamp, StatusPalette, SessionPanelView,
                                SessionRow, EmptyStateView
  UI/MenuBar/MenuBarContent.swift
  UI/Preview/DesignPreview.swift
  Resources/Fonts/              Inter-*.ttf, Manrope-*.ttf, OFL-*.txt
TidewatchTests/                 app-side tests
scripts/                        test-hook.sh, snap.sh, sign-app.sh
docs/design/backdrops/dusk.jpg  backdrop for preview screenshots (from Captylo)
```

---

### Task 1: Project scaffold that builds and tests

**Files:**
- Create: `project.yml`, `Makefile`, `Packages/TidewatchCore/Package.swift`, `Packages/TidewatchCore/Sources/TidewatchCore/SessionStatus.swift`, `Packages/TidewatchCore/Tests/TidewatchCoreTests/SessionStatusTests.swift`, `TidewatchHook/main.swift` (stub), `Tidewatch/App/TidewatchApp.swift`, `Tidewatch/App/AppDelegate.swift`, `Tidewatch/App/LaunchMode.swift`, `Tidewatch/App/Log.swift`, `TidewatchTests/LaunchModeTests.swift`, `Tidewatch/Resources/Fonts/*` (copied)

**Interfaces:**
- Produces: `SessionStatus`, `SessionActivity`, `SessionHost` (public, in `TidewatchCore`); `LaunchMode.current(arguments:environment:) -> LaunchMode`; `Log.app/sessions/ui/hooks`; `make gen/build/test/test-core`.

- [ ] **Step 1: Swift package with the status enums**

`Packages/TidewatchCore/Package.swift`:

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TidewatchCore",
    platforms: [.macOS("14.4")],
    products: [
        .library(name: "TidewatchCore", targets: ["TidewatchCore"]),
    ],
    targets: [
        .target(name: "TidewatchCore"),
        .testTarget(name: "TidewatchCoreTests", dependencies: ["TidewatchCore"]),
    ]
)
```

`Packages/TidewatchCore/Sources/TidewatchCore/SessionStatus.swift`:

```swift
/// What a session is doing, as the lamps show it.
public enum SessionStatus: String, Codable, Sendable, CaseIterable {
    case working
    case needsApproval
    case awaitingReview
    case idle
}

/// What a working session is busy with. Drives the status line ("Running tests…").
public enum SessionActivity: String, Codable, Sendable, CaseIterable {
    case thinking
    case runningTests
    case runningCommands
    case coding
    case readingCode
    case researching
    case runningAgents
    case usingTools
    case compacting
    case working
}

/// Where the session runs, which decides what a click opens.
public enum SessionHost: String, Codable, Sendable {
    case vscode
    case terminal
}
```

`Packages/TidewatchCore/Tests/TidewatchCoreTests/SessionStatusTests.swift`:

```swift
import Testing
@testable import TidewatchCore

struct SessionStatusTests {
    @Test func rawValuesAreStableForTheStateFile() {
        #expect(SessionStatus.needsApproval.rawValue == "needsApproval")
        #expect(SessionStatus.awaitingReview.rawValue == "awaitingReview")
        #expect(SessionHost.vscode.rawValue == "vscode")
    }
}
```

- [ ] **Step 2: Run the package tests**

Run: `swift test --package-path Packages/TidewatchCore`
Expected: `Test run with 1 test passed`.

- [ ] **Step 3: XcodeGen project**

`project.yml`:

```yaml
name: Tidewatch
options:
  bundleIdPrefix: pl.craftweb
  deploymentTarget:
    macOS: "14.4"
  xcodeVersion: "26.0"
  developmentLanguage: en
  createIntermediateGroups: true
  groupSortPosition: top
  minimumXcodeGenVersion: "2.40.0"

packages:
  TidewatchCore:
    path: Packages/TidewatchCore

settings:
  base:
    SWIFT_VERSION: "6.0"
    SWIFT_STRICT_CONCURRENCY: complete
    MARKETING_VERSION: "0.1.0"
    CURRENT_PROJECT_VERSION: "1"
    DEVELOPMENT_TEAM: ""
    CODE_SIGN_STYLE: Manual
    CODE_SIGN_IDENTITY: "-"
    ENABLE_HARDENED_RUNTIME: YES
    ENABLE_APP_SANDBOX: NO
    ENABLE_USER_SCRIPT_SANDBOXING: YES
    DEAD_CODE_STRIPPING: YES
    ARCHS: arm64
  configs:
    Debug:
      SWIFT_OPTIMIZATION_LEVEL: "-Onone"
      SWIFT_ACTIVE_COMPILATION_CONDITIONS: DEBUG
    Release:
      SWIFT_OPTIMIZATION_LEVEL: "-O"
      SWIFT_COMPILATION_MODE: wholemodule

targets:
  Tidewatch:
    type: application
    platform: macOS
    sources:
      - path: Tidewatch
    dependencies:
      - package: TidewatchCore
      # The hook helper ships next to the app executable (Contents/MacOS/tidewatch-hook);
      # HelperInstaller copies it to Application Support at launch.
      - target: TidewatchHook
        embed: true
        codeSign: false
        copy:
          destination: executables
    entitlements:
      path: Tidewatch/Tidewatch.entitlements
      properties:
        com.apple.security.app-sandbox: false
    info:
      path: Tidewatch/Info.plist
      properties:
        CFBundleName: Tidewatch
        CFBundleDisplayName: Tidewatch
        CFBundleShortVersionString: $(MARKETING_VERSION)
        CFBundleVersion: $(CURRENT_PROJECT_VERSION)
        CFBundleDevelopmentRegion: en
        LSMinimumSystemVersion: $(MACOSX_DEPLOYMENT_TARGET)
        LSUIElement: true
        LSApplicationCategoryType: public.app-category.developer-tools
        NSHumanReadableCopyright: "Copyright 2026 Dawid Kawalec"
        # Bundled Manrope + Inter (Resources/Fonts, SIL OFL), registered at launch.
        ATSApplicationFontsPath: "."
    settings:
      base:
        PRODUCT_NAME: Tidewatch
        PRODUCT_MODULE_NAME: Tidewatch
        PRODUCT_BUNDLE_IDENTIFIER: pl.craftweb.tidewatch
        GENERATE_INFOPLIST_FILE: NO
        COMBINE_HIDPI_IMAGES: YES

  TidewatchHook:
    type: tool
    platform: macOS
    sources:
      - path: TidewatchHook
    dependencies:
      - package: TidewatchCore
    settings:
      base:
        PRODUCT_NAME: tidewatch-hook
        PRODUCT_BUNDLE_IDENTIFIER: pl.craftweb.tidewatch.hook
        SKIP_INSTALL: YES

  TidewatchTests:
    type: bundle.unit-test
    platform: macOS
    sources:
      - path: TidewatchTests
    dependencies:
      - target: Tidewatch
      - package: TidewatchCore
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: pl.craftweb.tidewatch.tests
        GENERATE_INFOPLIST_FILE: YES
        TEST_HOST: "$(BUILT_PRODUCTS_DIR)/Tidewatch.app/Contents/MacOS/Tidewatch"
        BUNDLE_LOADER: "$(TEST_HOST)"

schemes:
  Tidewatch:
    build:
      targets:
        Tidewatch: all
        TidewatchTests: [test]
    run:
      config: Debug
    test:
      config: Debug
      targets:
        - TidewatchTests
    archive:
      config: Release
```

- [ ] **Step 4: Makefile**

```make
SHELL := /bin/bash
PROJECT := Tidewatch.xcodeproj
SCHEME := Tidewatch
DERIVED := $(CURDIR)/.local-build
APP_NAME := Tidewatch.app
XCODEBUILD := xcodebuild -project $(PROJECT) -scheme $(SCHEME) -derivedDataPath "$(DERIVED)" -skipPackagePluginValidation -skipMacroValidation
XCPRETTY := grep -E 'error:|warning: .*(Tidewatch|TidewatchHook|TidewatchCore)|BUILD (SUCCEEDED|FAILED)|TEST (SUCCEEDED|FAILED)|✘|Test run with'

.PHONY: gen build test test-core test-hook release sign install run clean

gen:
	xcodegen generate

build: gen
	set -o pipefail; $(XCODEBUILD) -configuration Debug CODE_SIGN_IDENTITY="-" build 2>&1 | $(XCPRETTY)

test-core:
	set -o pipefail; swift test --package-path Packages/TidewatchCore 2>&1 | tail -n 3

test: gen test-core
	set -o pipefail; $(XCODEBUILD) -configuration Debug CODE_SIGN_IDENTITY="-" test 2>&1 | $(XCPRETTY)
	@if [ -x scripts/test-hook.sh ]; then scripts/test-hook.sh; fi

run:
	@if [ -d "/Applications/$(APP_NAME)" ]; then open "/Applications/$(APP_NAME)"; \
	else open "$(DERIVED)/Build/Products/Debug/$(APP_NAME)"; fi

clean:
	rm -rf "$(DERIVED)" Packages/TidewatchCore/.build
```

(Release, sign and install targets come in Task 13.)

- [ ] **Step 5: Helper stub, app stub, launch mode, log**

`TidewatchHook/main.swift`:

```swift
import Foundation

// Replaced in Task 6. Never prints, always exits 0.
exit(0)
```

`Tidewatch/App/Log.swift`:

```swift
import os

enum Log {
    static let app = Logger(subsystem: "pl.craftweb.tidewatch", category: "app")
    static let sessions = Logger(subsystem: "pl.craftweb.tidewatch", category: "sessions")
    static let ui = Logger(subsystem: "pl.craftweb.tidewatch", category: "ui")
    static let hooks = Logger(subsystem: "pl.craftweb.tidewatch", category: "hooks")
}
```

`Tidewatch/App/LaunchMode.swift`:

```swift
import Foundation

/// How the process was started. Tests and the design preview never touch the real data folder,
/// the real settings.json or the real widget.
enum LaunchMode: Equatable {
    case normal
    case designPreview(String)
    case tests

    static func current(
        arguments: [String] = CommandLine.arguments,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> LaunchMode {
        if environment["XCTestConfigurationFilePath"] != nil || environment["XCTestBundlePath"] != nil {
            return .tests
        }
        if let index = arguments.firstIndex(of: "--design-preview") {
            let next = arguments.index(after: index)
            return .designPreview(next < arguments.endIndex ? arguments[next].lowercased() : "")
        }
        return .normal
    }
}
```

`Tidewatch/App/AppDelegate.swift` (grows in Task 11):

```swift
import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let mode = LaunchMode.current()

    func applicationDidFinishLaunching(_ notification: Notification) {
        Log.app.info("launched")
    }
}
```

`Tidewatch/App/TidewatchApp.swift` (grows in Task 11):

```swift
import SwiftUI

@main
struct TidewatchApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            Button("Quit Tidewatch") { NSApp.terminate(nil) }
                .keyboardShortcut("q")
        } label: {
            Image(systemName: "smallcircle.filled.circle")
        }
        .menuBarExtraStyle(.menu)
    }
}
```

- [ ] **Step 6: Copy the fonts**

Run: `mkdir -p Tidewatch/Resources/Fonts && cp <captylo-repo>/Captylo/Resources/Fonts/{Inter-Regular,Inter-Medium,Inter-SemiBold,Manrope-SemiBold,Manrope-Bold}.ttf <captylo-repo>/Captylo/Resources/Fonts/OFL-*.txt Tidewatch/Resources/Fonts/`

- [ ] **Step 7: Write the failing LaunchMode test**

`TidewatchTests/LaunchModeTests.swift`:

```swift
import Testing
@testable import Tidewatch

struct LaunchModeTests {
    @Test func testHostEnvironmentMeansTests() {
        #expect(LaunchMode.current(arguments: ["Tidewatch"], environment: ["XCTestConfigurationFilePath": "/x"]) == .tests)
    }

    @Test func designPreviewTakesTheNextArgument() {
        #expect(LaunchMode.current(arguments: ["Tidewatch", "--design-preview", "Widget-Expanded"], environment: [:]) == .designPreview("widget-expanded"))
        #expect(LaunchMode.current(arguments: ["Tidewatch", "--design-preview"], environment: [:]) == .designPreview(""))
    }

    @Test func plainLaunchIsNormal() {
        #expect(LaunchMode.current(arguments: ["Tidewatch"], environment: [:]) == .normal)
    }
}
```

- [ ] **Step 8: Build and test everything**

Run: `make build && make test`
Expected: `BUILD SUCCEEDED`, the package test passes, `TEST SUCCEEDED` with 3 app tests. Then check the helper is embedded:
Run: `ls .local-build/Build/Products/Debug/Tidewatch.app/Contents/MacOS/`
Expected: `Tidewatch` and `tidewatch-hook`. If `tidewatch-hook` is missing, replace the `copy:` dependency with a `postBuildScripts` entry on the app target that runs `cp "$BUILT_PRODUCTS_DIR/tidewatch-hook" "$TARGET_BUILD_DIR/$EXECUTABLE_FOLDER_PATH/"` (with `inputFiles: [$(BUILT_PRODUCTS_DIR)/tidewatch-hook]` and `outputFiles: [$(TARGET_BUILD_DIR)/$(EXECUTABLE_FOLDER_PATH)/tidewatch-hook]` so user script sandboxing allows it), keep `- target: TidewatchHook` with `embed: false`, and re-run.

- [ ] **Step 9: Checkpoint**

`git status` shows only the new scaffold files (no `.xcodeproj`, no `.local-build`). No commit (owner's rule).

---

### Task 2: Session state model and hook event decoding

**Files:**
- Create: `Packages/TidewatchCore/Sources/TidewatchCore/SessionState.swift`, `SessionCoding.swift`, `HookEvent.swift`
- Test: `Packages/TidewatchCore/Tests/TidewatchCoreTests/SessionStateTests.swift`, `HookEventTests.swift`

**Interfaces:**
- Consumes: `SessionStatus`, `SessionActivity`, `SessionHost` (Task 1).
- Produces:
  - `public struct SessionState: Codable, Sendable, Equatable, Identifiable` with `schema: Int`, `sessionId: String`, `cwd: String`, `title: String?`, `host: SessionHost`, `terminalApp: String?`, `pid: Int32?`, `status: SessionStatus`, `activity: SessionActivity`, `tool: String?`, `detail: String?`, `pendingApproval: String?`, `approvalResolvedAt: Date?`, `backgroundTasks: Int`, `statusSince: Date`, `firstSeen: Date`, `lastEvent: Date`, `id: String`, `project: String`, `init(sessionId:cwd:host:terminalApp:pid:now:)`.
  - `public enum SessionCoding { static func encoder() -> JSONEncoder; static func decoder() -> JSONDecoder }`.
  - `public struct HookEvent: Sendable, Equatable` with `kind: Kind?`, `rawName`, `sessionId`, `cwd`, `toolName`, `command`, `filePath`, `url`, `notificationType`, `message`, `sessionTitle`, `runningBackgroundTasks: Int`; `HookEvent.Kind` cases `sessionStart, sessionEnd, userPromptSubmit, preToolUse, postToolUse, postToolUseFailure, permissionRequest, notification, stop, subagentStart, preCompact`; `static func decode(_ data: Data) throws -> HookEvent`; memberwise test init `init(kind:sessionId:cwd:toolName:command:filePath:url:notificationType:message:sessionTitle:runningBackgroundTasks:)`.

- [ ] **Step 1: Write the failing tests**

`SessionStateTests.swift`:

```swift
import Foundation
import Testing
@testable import TidewatchCore

struct SessionStateTests {
    private let now = Date(timeIntervalSince1970: 1_791_620_000)

    @Test func roundTripsThroughTheStateFileFormat() throws {
        var state = SessionState(sessionId: "s-1", cwd: "/Users/demo/app", host: .vscode, terminalApp: nil, pid: 4242, now: now)
        state.status = .needsApproval
        state.tool = "Bash"
        state.detail = "npm install"
        state.backgroundTasks = 2
        state.lastEvent = now.addingTimeInterval(30)
        let data = try SessionCoding.encoder().encode(state)
        let decoded = try SessionCoding.decoder().decode(SessionState.self, from: data)
        #expect(decoded == state)
        let text = String(decoding: data, as: UTF8.self)
        #expect(text.contains("\"statusSince\" : \"2026-"))
        #expect(text.contains("\"cwd\" : \"/Users/demo/app\""))
    }

    @Test func newSessionStartsIdle() {
        let state = SessionState(sessionId: "s-1", cwd: "/Users/demo/app", host: .terminal, terminalApp: "iTerm.app", pid: nil, now: now)
        #expect(state.status == .idle)
        #expect(state.firstSeen == now)
        #expect(state.statusSince == now)
        #expect(state.lastEvent == now)
        #expect(state.backgroundTasks == 0)
        #expect(state.schema == SessionState.currentSchema)
    }

    @Test func projectIsTheFolderNameEvenWithSpaces() {
        let state = SessionState(sessionId: "s", cwd: "/Users/demo/anna wisniewska", host: .vscode, terminalApp: nil, pid: nil, now: now)
        #expect(state.project == "anna wisniewska")
        #expect(state.id == "s")
    }

    @Test func decodingIgnoresUnknownFields() throws {
        var state = SessionState(sessionId: "s", cwd: "/Users/demo/app", host: .vscode, terminalApp: nil, pid: nil, now: now)
        state.title = "Fix login"
        var object = try JSONSerialization.jsonObject(with: SessionCoding.encoder().encode(state)) as! [String: Any]
        object["futureField"] = ["x": 1]
        let data = try JSONSerialization.data(withJSONObject: object)
        #expect(try SessionCoding.decoder().decode(SessionState.self, from: data) == state)
    }
}
```

`HookEventTests.swift`:

```swift
import Foundation
import Testing
@testable import TidewatchCore

struct HookEventTests {
    private func decode(_ json: String) throws -> HookEvent {
        try HookEvent.decode(Data(json.utf8))
    }

    @Test func decodesPreToolUseWithBashCommand() throws {
        let event = try decode(#"{"session_id":"s1","transcript_path":"/x.jsonl","cwd":"/Users/demo/app","permission_mode":"auto","effort":{"level":"high"},"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"npm test","description":"Run tests"},"tool_use_id":"t1"}"#)
        #expect(event.kind == .preToolUse)
        #expect(event.rawName == "PreToolUse")
        #expect(event.sessionId == "s1")
        #expect(event.cwd == "/Users/demo/app")
        #expect(event.toolName == "Bash")
        #expect(event.command == "npm test")
        #expect(event.filePath == nil)
    }

    @Test func decodesFilePathAndSkipsToolResponse() throws {
        let event = try decode(#"{"session_id":"s1","cwd":"/Users/demo/app","hook_event_name":"PostToolUse","tool_name":"Edit","tool_input":{"file_path":"/Users/demo/app/src/a.swift","old_string":"a","new_string":"b"},"tool_response":{"filePath":"/x","structuredPatch":[{"lines":["-a","+b"]}]},"duration_ms":4}"#)
        #expect(event.kind == .postToolUse)
        #expect(event.filePath == "/Users/demo/app/src/a.swift")
    }

    @Test func countsOnlyRunningBackgroundTasks() throws {
        let event = try decode(#"{"session_id":"s1","cwd":"/a","hook_event_name":"Stop","stop_hook_active":false,"background_tasks":[{"id":"a","type":"shell","status":"running"},{"id":"b","status":"completed"},{"id":"c","status":"running"}]}"#)
        #expect(event.kind == .stop)
        #expect(event.runningBackgroundTasks == 2)
    }

    @Test func decodesNotificationTypeAndMessage() throws {
        let event = try decode(#"{"session_id":"s1","cwd":"/a","hook_event_name":"Notification","message":"Claude needs your permission to use Bash","notification_type":"permission_prompt"}"#)
        #expect(event.kind == .notification)
        #expect(event.notificationType == "permission_prompt")
        #expect(event.message == "Claude needs your permission to use Bash")
    }

    @Test func decodesSessionTitle() throws {
        let event = try decode(#"{"session_id":"s1","cwd":"/a","hook_event_name":"SessionStart","source":"startup","session_title":"Fix login form"}"#)
        #expect(event.kind == .sessionStart)
        #expect(event.sessionTitle == "Fix login form")
    }

    @Test func unknownEventNameHasNoKind() throws {
        let event = try decode(#"{"session_id":"s1","cwd":"/a","hook_event_name":"FileChanged"}"#)
        #expect(event.kind == nil)
        #expect(event.rawName == "FileChanged")
    }

    @Test func toolInputOfAnotherShapeIsTolerated() throws {
        let numeric = try decode(#"{"session_id":"s1","cwd":"/a","hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":42}}"#)
        #expect(numeric.command == nil)
        let string = try decode(#"{"session_id":"s1","cwd":"/a","hook_event_name":"PreToolUse","tool_name":"X","tool_input":"raw"}"#)
        #expect(string.toolName == "X")
    }

    @Test func missingCwdBecomesEmpty() throws {
        let event = try decode(#"{"session_id":"s1","hook_event_name":"Stop"}"#)
        #expect(event.cwd == "")
    }

    @Test func missingSessionIdOrGarbageThrows() {
        #expect(throws: (any Error).self) { try decode(#"{"hook_event_name":"Stop"}"#) }
        #expect(throws: (any Error).self) { try decode("not json") }
        #expect(throws: (any Error).self) { try decode("") }
    }
}
```

- [ ] **Step 2: Run to see them fail**

Run: `swift test --package-path Packages/TidewatchCore`
Expected: compile errors (`SessionState`, `SessionCoding`, `HookEvent` not found).

- [ ] **Step 3: Implement**

`SessionState.swift`:

```swift
import Foundation

/// One session's current state: the content of `sessions/<sessionId>.json`. Written only by the
/// hook helper (through `SessionFileStore`), read by the app.
public struct SessionState: Codable, Sendable, Equatable, Identifiable {
    public static let currentSchema = 1

    public var schema: Int
    public var sessionId: String
    public var cwd: String
    public var title: String?
    public var host: SessionHost
    /// `TERM_PROGRAM` of a terminal session ("iTerm.app", "Apple_Terminal", ...).
    public var terminalApp: String?
    /// The Claude Code process (the helper's parent), used to drop crashed sessions.
    public var pid: Int32?
    public var status: SessionStatus
    public var activity: SessionActivity
    public var tool: String?
    public var detail: String?
    /// `ApprovalDetail.signature` of the tool call waiting for approval.
    public var pendingApproval: String?
    /// When the last approval was resolved; a late `Notification permission_prompt` is ignored.
    public var approvalResolvedAt: Date?
    /// Running background tasks reported by the last `Stop`.
    public var backgroundTasks: Int
    /// Changes only when `status` changes.
    public var statusSince: Date
    public var firstSeen: Date
    /// Changes on every event.
    public var lastEvent: Date

    public var id: String { sessionId }

    /// The project folder's name ("captylo-app"), the row title.
    public var project: String {
        let name = URL(fileURLWithPath: cwd).lastPathComponent
        return name.isEmpty ? cwd : name
    }

    public init(sessionId: String, cwd: String, host: SessionHost, terminalApp: String?, pid: Int32?, now: Date) {
        schema = Self.currentSchema
        self.sessionId = sessionId
        self.cwd = cwd
        title = nil
        self.host = host
        self.terminalApp = terminalApp
        self.pid = pid
        status = .idle
        activity = .working
        tool = nil
        detail = nil
        pendingApproval = nil
        approvalResolvedAt = nil
        backgroundTasks = 0
        statusSince = now
        firstSeen = now
        lastEvent = now
    }
}
```

`SessionCoding.swift`:

```swift
import Foundation

/// The state file format: pretty JSON, sorted keys, ISO 8601 dates with milliseconds.
public enum SessionCoding {
    public static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(date.formatted(Date.ISO8601FormatStyle(includingFractionalSeconds: true)))
        }
        return encoder
    }

    public static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let text = try container.decode(String.self)
            if let date = try? Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse(text) {
                return date
            }
            if let date = try? Date.ISO8601FormatStyle().parse(text) {
                return date
            }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Not an ISO 8601 date: \(text)")
        }
        return decoder
    }
}
```

`HookEvent.swift`:

```swift
import Foundation

/// One Claude Code hook payload, decoded tolerantly: only the fields Tidewatch uses, and a
/// `tool_input` of an unexpected shape never fails the whole event.
public struct HookEvent: Sendable, Equatable {
    public enum Kind: String, Sendable, CaseIterable {
        case sessionStart = "SessionStart"
        case sessionEnd = "SessionEnd"
        case userPromptSubmit = "UserPromptSubmit"
        case preToolUse = "PreToolUse"
        case postToolUse = "PostToolUse"
        case postToolUseFailure = "PostToolUseFailure"
        case permissionRequest = "PermissionRequest"
        case notification = "Notification"
        case stop = "Stop"
        case subagentStart = "SubagentStart"
        case preCompact = "PreCompact"
    }

    /// nil for events Tidewatch does not handle.
    public var kind: Kind?
    public var rawName: String
    public var sessionId: String
    public var cwd: String
    public var toolName: String?
    public var command: String?
    public var filePath: String?
    public var url: String?
    public var notificationType: String?
    public var message: String?
    public var sessionTitle: String?
    public var runningBackgroundTasks: Int

    public init(
        kind: Kind,
        sessionId: String,
        cwd: String,
        toolName: String? = nil,
        command: String? = nil,
        filePath: String? = nil,
        url: String? = nil,
        notificationType: String? = nil,
        message: String? = nil,
        sessionTitle: String? = nil,
        runningBackgroundTasks: Int = 0
    ) {
        self.kind = kind
        rawName = kind.rawValue
        self.sessionId = sessionId
        self.cwd = cwd
        self.toolName = toolName
        self.command = command
        self.filePath = filePath
        self.url = url
        self.notificationType = notificationType
        self.message = message
        self.sessionTitle = sessionTitle
        self.runningBackgroundTasks = runningBackgroundTasks
    }

    public static func decode(_ data: Data) throws -> HookEvent {
        try JSONDecoder().decode(Payload.self, from: data).event
    }
}

extension HookEvent {
    private struct Payload: Decodable {
        var event: HookEvent

        private enum Keys: String, CodingKey {
            case sessionId = "session_id"
            case cwd
            case name = "hook_event_name"
            case toolName = "tool_name"
            case toolInput = "tool_input"
            case notificationType = "notification_type"
            case message
            case sessionTitle = "session_title"
            case backgroundTasks = "background_tasks"
        }

        private enum ToolKeys: String, CodingKey {
            case command
            case filePath = "file_path"
            case notebookPath = "notebook_path"
            case url
        }

        private struct BackgroundTask: Decodable {
            var status: String?
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: Keys.self)
            let name = try container.decode(String.self, forKey: .name)
            let sessionId = try container.decode(String.self, forKey: .sessionId)
            let tool = try? container.nestedContainer(keyedBy: ToolKeys.self, forKey: .toolInput)
            let tasks = (try? container.decodeIfPresent([BackgroundTask].self, forKey: .backgroundTasks)) ?? []

            var event = HookEvent(
                kind: .stop,
                sessionId: sessionId,
                cwd: (try? container.decodeIfPresent(String.self, forKey: .cwd)) ?? "",
                toolName: try? container.decodeIfPresent(String.self, forKey: .toolName),
                command: try? tool?.decodeIfPresent(String.self, forKey: .command),
                filePath: (try? tool?.decodeIfPresent(String.self, forKey: .filePath))
                    ?? (try? tool?.decodeIfPresent(String.self, forKey: .notebookPath)),
                url: try? tool?.decodeIfPresent(String.self, forKey: .url),
                notificationType: try? container.decodeIfPresent(String.self, forKey: .notificationType),
                message: try? container.decodeIfPresent(String.self, forKey: .message),
                sessionTitle: try? container.decodeIfPresent(String.self, forKey: .sessionTitle),
                runningBackgroundTasks: tasks.filter { $0.status == "running" }.count
            )
            event.kind = Kind(rawValue: name)
            event.rawName = name
            self.event = event
        }
    }
}
```

Note: `try?` flattens optionals (SE-0230), so `try? x.decodeIfPresent(String.self, ...)` is `String?`.

- [ ] **Step 4: Run the tests**

Run: `swift test --package-path Packages/TidewatchCore`
Expected: all tests pass.

- [ ] **Step 5: Checkpoint**

`make test` passes. No commit.

---

### Task 3: Activity labels and approval details

**Files:**
- Create: `Packages/TidewatchCore/Sources/TidewatchCore/ActivityClassifier.swift`, `ApprovalDetail.swift`
- Test: `ActivityClassifierTests.swift`, `ApprovalDetailTests.swift`

**Interfaces:**
- Consumes: `HookEvent`, `SessionActivity`.
- Produces: `ActivityClassifier.activity(forTool: String, command: String?) -> SessionActivity`, `ActivityClassifier.isTestCommand(_:) -> Bool`, `ApprovalDetail.describe(_ event: HookEvent) -> String?`, `ApprovalDetail.signature(_ event: HookEvent) -> String`.

- [ ] **Step 1: Write the failing tests**

`ActivityClassifierTests.swift`:

```swift
import Testing
@testable import TidewatchCore

struct ActivityClassifierTests {
    @Test(arguments: [
        "npm test", "npm run test", "pnpm test -- --watch=false", "yarn test", "bun test",
        "make test", "swift test --package-path Packages/Core", "cargo test", "go test ./...",
        "xcodebuild -scheme App -destination 'platform=macOS' test", "npx vitest run", "pytest -q",
        "jest src", "npx playwright test", "cd app && npm test",
    ])
    func recognisesTestCommands(_ command: String) {
        #expect(ActivityClassifier.isTestCommand(command))
        #expect(ActivityClassifier.activity(forTool: "Bash", command: command) == .runningTests)
    }

    @Test(arguments: [
        "touch /tmp/test.txt", "cat src/test/a.swift", "go build && ls test", "git commit -m 'add tests'",
        "npm install", "ls -la",
    ])
    func otherCommandsAreJustCommands(_ command: String) {
        #expect(!ActivityClassifier.isTestCommand(command))
        #expect(ActivityClassifier.activity(forTool: "Bash", command: command) == .runningCommands)
    }

    @Test func mapsToolsToActivities() {
        #expect(ActivityClassifier.activity(forTool: "Edit", command: nil) == .coding)
        #expect(ActivityClassifier.activity(forTool: "Write", command: nil) == .coding)
        #expect(ActivityClassifier.activity(forTool: "MultiEdit", command: nil) == .coding)
        #expect(ActivityClassifier.activity(forTool: "NotebookEdit", command: nil) == .coding)
        #expect(ActivityClassifier.activity(forTool: "Read", command: nil) == .readingCode)
        #expect(ActivityClassifier.activity(forTool: "Grep", command: nil) == .readingCode)
        #expect(ActivityClassifier.activity(forTool: "Glob", command: nil) == .readingCode)
        #expect(ActivityClassifier.activity(forTool: "WebSearch", command: nil) == .researching)
        #expect(ActivityClassifier.activity(forTool: "WebFetch", command: nil) == .researching)
        #expect(ActivityClassifier.activity(forTool: "Task", command: nil) == .runningAgents)
        #expect(ActivityClassifier.activity(forTool: "Agent", command: nil) == .runningAgents)
        #expect(ActivityClassifier.activity(forTool: "mcp__plane__list_projects", command: nil) == .usingTools)
        #expect(ActivityClassifier.activity(forTool: "TodoWrite", command: nil) == .working)
        #expect(ActivityClassifier.activity(forTool: "Bash", command: nil) == .runningCommands)
    }
}
```

`ApprovalDetailTests.swift`:

```swift
import Testing
@testable import TidewatchCore

struct ApprovalDetailTests {
    private func event(_ tool: String, command: String? = nil, filePath: String? = nil, url: String? = nil) -> HookEvent {
        HookEvent(kind: .permissionRequest, sessionId: "s", cwd: "/Users/demo/app", toolName: tool, command: command, filePath: filePath, url: url)
    }

    @Test func bashShowsTheFirstLineShortened() {
        #expect(ApprovalDetail.describe(event("Bash", command: "npm install\nnpm test")) == "npm install")
        let long = String(repeating: "a", count: 100)
        let detail = ApprovalDetail.describe(event("Bash", command: long))
        #expect(detail?.count == 60)
        #expect(detail?.hasSuffix("…") == true)
    }

    @Test func fileToolsShowTheFileName() {
        #expect(ApprovalDetail.describe(event("Edit", filePath: "/Users/demo/app/src/Hero.tsx")) == "Hero.tsx")
        #expect(ApprovalDetail.describe(event("Write", filePath: "/Users/demo/app/README.md")) == "README.md")
    }

    @Test func webFetchShowsTheHost() {
        #expect(ApprovalDetail.describe(event("WebFetch", url: "https://docs.example.com/a/b")) == "docs.example.com")
    }

    @Test func questionsAndMissingInputHaveNoDetail() {
        #expect(ApprovalDetail.describe(event("AskUserQuestion")) == nil)
        #expect(ApprovalDetail.describe(event("Bash")) == nil)
        #expect(ApprovalDetail.describe(HookEvent(kind: .permissionRequest, sessionId: "s", cwd: "/a")) == nil)
    }

    @Test func mcpToolsShowTheToolPart() {
        #expect(ApprovalDetail.describe(event("mcp__plane__create_work_item")) == "create_work_item")
        #expect(ApprovalDetail.describe(event("TodoWrite")) == "TodoWrite")
    }

    @Test func signatureMatchesTheSameCallOnly() {
        #expect(ApprovalDetail.signature(event("Bash", command: "npm install")) == ApprovalDetail.signature(HookEvent(kind: .postToolUse, sessionId: "s", cwd: "/a", toolName: "Bash", command: "npm install")))
        #expect(ApprovalDetail.signature(event("Bash", command: "npm install")) != ApprovalDetail.signature(event("Bash", command: "npm test")))
        #expect(ApprovalDetail.signature(event("Read", filePath: "/a")) != ApprovalDetail.signature(event("Edit", filePath: "/a")))
    }
}
```

- [ ] **Step 2: Run to see them fail**

Run: `swift test --package-path Packages/TidewatchCore`
Expected: compile errors (`ActivityClassifier`, `ApprovalDetail` not found).

- [ ] **Step 3: Implement**

`ActivityClassifier.swift`:

```swift
import Foundation

/// What a tool call means for the status line.
public enum ActivityClassifier {
    public static func activity(forTool tool: String, command: String?) -> SessionActivity {
        switch tool {
        case "Bash", "BashOutput":
            if let command, isTestCommand(command) { return .runningTests }
            return .runningCommands
        case "Edit", "Write", "MultiEdit", "NotebookEdit":
            return .coding
        case "Read", "Grep", "Glob", "LS":
            return .readingCode
        case "WebSearch", "WebFetch":
            return .researching
        case "Task", "Agent":
            return .runningAgents
        default:
            return tool.hasPrefix("mcp__") ? .usingTools : .working
        }
    }

    /// True for commands that run a test suite (`npm test`, `swift test`, `pytest`, ...), not for
    /// commands that only mention a "test" path.
    public static func isTestCommand(_ command: String) -> Bool {
        let range = NSRange(command.startIndex..., in: command)
        return testPattern.firstMatch(in: command, range: range) != nil
    }

    nonisolated(unsafe) private static let testPattern = try! NSRegularExpression(
        pattern: #"(?:^|[\s;&|(])(?:(?:npm|pnpm|yarn|bun)\s+(?:run\s+)?test\b|(?:make|swift|cargo|go|deno|flutter|mix|dotnet)\s+test\b|xcodebuild\b[^;&|\n]*\stest\b|(?:npx\s+)?(?:jest|vitest|pytest|phpunit|rspec|mocha)\b|playwright\s+test\b)"#,
        options: [.caseInsensitive]
    )
}
```

`ApprovalDetail.swift`:

```swift
import Foundation

/// Short, human detail of a tool call waiting for approval, and a signature that identifies the
/// same call in a later `PostToolUse` (the `PermissionRequest` payload has no `tool_use_id`).
public enum ApprovalDetail {
    public static let maxLength = 60

    public static func describe(_ event: HookEvent) -> String? {
        guard let tool = event.toolName else { return nil }
        switch tool {
        case "AskUserQuestion":
            return nil
        case "Bash":
            return event.command.map { shorten(firstLine($0)) }
        case "Edit", "Write", "MultiEdit", "NotebookEdit", "Read":
            return event.filePath.map { URL(fileURLWithPath: $0).lastPathComponent }
        case "WebFetch":
            return event.url.flatMap { URL(string: $0)?.host() }
        default:
            if tool.hasPrefix("mcp__"), let last = tool.components(separatedBy: "__").last {
                return last
            }
            return tool
        }
    }

    public static func signature(_ event: HookEvent) -> String {
        "\(event.toolName ?? "")|\(event.command ?? event.filePath ?? event.url ?? "")"
    }

    static func firstLine(_ text: String) -> String {
        let line = text.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: true).first.map(String.init) ?? ""
        return line.trimmingCharacters(in: .whitespaces)
    }

    static func shorten(_ text: String) -> String {
        text.count <= maxLength ? text : String(text.prefix(maxLength - 1)) + "…"
    }
}
```

- [ ] **Step 4: Run the tests**

Run: `swift test --package-path Packages/TidewatchCore`
Expected: all pass. If a test-command case fails, fix the regex, not the test list.

- [ ] **Step 5: Checkpoint**

`make test` passes.

---

### Task 4: The reducer

**Files:**
- Create: `Packages/TidewatchCore/Sources/TidewatchCore/SessionReducer.swift`
- Test: `SessionReducerTests.swift`

**Interfaces:**
- Consumes: `SessionState`, `HookEvent`, `ActivityClassifier`, `ApprovalDetail`.
- Produces: `public struct EventContext: Sendable, Equatable { now: Date; host: SessionHost; terminalApp: String?; pid: Int32? }` with a public memberwise init; `public enum ReduceOutcome: Sendable, Equatable { case write(SessionState), delete, ignore }`; `SessionReducer.reduce(_ current: SessionState?, _ event: HookEvent, context: EventContext) -> ReduceOutcome`; `SessionReducer.lateNotificationWindow: TimeInterval` (10).

- [ ] **Step 1: Write the failing tests**

`SessionReducerTests.swift`:

```swift
import Foundation
import Testing
@testable import TidewatchCore

struct SessionReducerTests {
    private let t0 = Date(timeIntervalSince1970: 1_791_620_000)

    private func context(_ seconds: TimeInterval = 0, host: SessionHost = .vscode, pid: Int32? = 100) -> EventContext {
        EventContext(now: t0.addingTimeInterval(seconds), host: host, terminalApp: nil, pid: pid)
    }

    private func event(_ kind: HookEvent.Kind, tool: String? = nil, command: String? = nil, filePath: String? = nil,
                       notificationType: String? = nil, title: String? = nil, background: Int = 0) -> HookEvent {
        HookEvent(kind: kind, sessionId: "s-1", cwd: "/Users/demo/app", toolName: tool, command: command, filePath: filePath,
                  notificationType: notificationType, sessionTitle: title, runningBackgroundTasks: background)
    }

    /// Applies events in order, `seconds` apart, and returns the last written state.
    private func run(_ events: [HookEvent], start: SessionState? = nil, step: TimeInterval = 1) -> SessionState? {
        var state = start
        for (index, e) in events.enumerated() {
            switch SessionReducer.reduce(state, e, context: context(Double(index) * step)) {
            case .write(let next): state = next
            case .delete: state = nil
            case .ignore: break
            }
        }
        return state
    }

    @Test func sessionStartCreatesAnIdleSession() throws {
        let state = try #require(run([event(.sessionStart, title: "Fix login")]))
        #expect(state.status == .idle)
        #expect(state.title == "Fix login")
        #expect(state.pid == 100)
        #expect(state.host == .vscode)
        #expect(state.firstSeen == t0)
    }

    @Test func promptMakesItWorkAndThinking() throws {
        let state = try #require(run([event(.sessionStart), event(.userPromptSubmit)]))
        #expect(state.status == .working)
        #expect(state.activity == .thinking)
        #expect(state.statusSince == t0.addingTimeInterval(1))
    }

    @Test func toolUseSetsActivityAndKeepsStatusSince() throws {
        let state = try #require(run([event(.userPromptSubmit), event(.preToolUse, tool: "Bash", command: "npm test"), event(.postToolUse, tool: "Bash", command: "npm test")]))
        #expect(state.status == .working)
        #expect(state.activity == .runningTests)
        #expect(state.statusSince == t0)
        #expect(state.lastEvent == t0.addingTimeInterval(2))
    }

    @Test func eventsWithoutSessionStartStillCreateTheSession() throws {
        let state = try #require(run([event(.preToolUse, tool: "Edit", filePath: "/Users/demo/app/a.swift")]))
        #expect(state.status == .working)
        #expect(state.activity == .coding)
    }

    @Test func permissionRequestNeedsApprovalWithDetail() throws {
        let state = try #require(run([event(.userPromptSubmit), event(.preToolUse, tool: "Bash", command: "npm install"), event(.permissionRequest, tool: "Bash", command: "npm install")]))
        #expect(state.status == .needsApproval)
        #expect(state.tool == "Bash")
        #expect(state.detail == "npm install")
        #expect(state.pendingApproval == "Bash|npm install")
    }

    @Test func matchingPostClearsApproval() throws {
        let state = try #require(run([event(.permissionRequest, tool: "Bash", command: "npm install"), event(.postToolUse, tool: "Bash", command: "npm install")]))
        #expect(state.status == .working)
        #expect(state.pendingApproval == nil)
        #expect(state.approvalResolvedAt == t0.addingTimeInterval(1))
    }

    @Test func failedMatchingPostClearsApprovalToo() throws {
        let state = try #require(run([event(.permissionRequest, tool: "Bash", command: "rm x"), event(.postToolUseFailure, tool: "Bash", command: "rm x")]))
        #expect(state.status == .working)
    }

    @Test func unrelatedPostKeepsApproval() throws {
        let state = try #require(run([
            event(.preToolUse, tool: "Read", filePath: "/a"),
            event(.permissionRequest, tool: "Bash", command: "npm install"),
            event(.postToolUse, tool: "Read", filePath: "/a"),
            event(.preToolUse, tool: "Grep"),
        ]))
        #expect(state.status == .needsApproval)
        #expect(state.detail == "npm install")
        #expect(state.activity == .readingCode)
    }

    @Test func askUserQuestionIsAnApprovalThatTheAnswerClears() throws {
        let waiting = try #require(run([event(.permissionRequest, tool: "AskUserQuestion")]))
        #expect(waiting.status == .needsApproval)
        #expect(waiting.tool == "AskUserQuestion")
        #expect(waiting.detail == nil)
        let answered = try #require(run([event(.postToolUse, tool: "AskUserQuestion")], start: waiting))
        #expect(answered.status == .working)
    }

    @Test func notificationFallbackSetsApprovalWhenPermissionRequestDidNotFire() throws {
        let state = try #require(run([event(.userPromptSubmit), event(.notification, notificationType: "permission_prompt")]))
        #expect(state.status == .needsApproval)
        #expect(state.pendingApproval == nil)
        let cleared = try #require(run([event(.postToolUse, tool: "Bash", command: "x")], start: state))
        #expect(cleared.status == .working)
    }

    @Test func lateNotificationAfterResolvedApprovalIsIgnored() throws {
        let resolved = try #require(run([event(.permissionRequest, tool: "Bash", command: "a"), event(.postToolUse, tool: "Bash", command: "a")]))
        // 5 s after the resolution: inside the window.
        guard case .write(let late) = SessionReducer.reduce(resolved, event(.notification, notificationType: "permission_prompt"), context: context(6)) else {
            Issue.record("expected a write"); return
        }
        #expect(late.status == .working)
        // 30 s later: a new, real prompt.
        guard case .write(let real) = SessionReducer.reduce(resolved, event(.notification, notificationType: "permission_prompt"), context: context(31)) else {
            Issue.record("expected a write"); return
        }
        #expect(real.status == .needsApproval)
    }

    @Test func otherNotificationsAreIgnored() {
        #expect(SessionReducer.reduce(nil, event(.notification, notificationType: "idle_prompt"), context: context()) == .ignore)
    }

    @Test func stopAwaitsReviewAndCountsBackgroundTasks() throws {
        let state = try #require(run([event(.userPromptSubmit), event(.permissionRequest, tool: "Bash", command: "a"), event(.stop, background: 2)]))
        #expect(state.status == .awaitingReview)
        #expect(state.backgroundTasks == 2)
        #expect(state.pendingApproval == nil)
        #expect(state.tool == nil)
        #expect(state.detail == nil)
    }

    @Test func subagentAndCompactKeepItWorking() throws {
        let agents = try #require(run([event(.userPromptSubmit), event(.subagentStart)]))
        #expect(agents.activity == .runningAgents)
        let compacting = try #require(run([event(.userPromptSubmit), event(.preCompact)]))
        #expect(compacting.activity == .compacting)
        #expect(compacting.status == .working)
    }

    @Test func resumedSessionKeepsItsStatus() throws {
        let working = try #require(run([event(.userPromptSubmit)]))
        let resumed = try #require(run([event(.sessionStart)], start: working))
        #expect(resumed.status == .working)
    }

    @Test func sessionEndDeletes() {
        #expect(SessionReducer.reduce(nil, event(.sessionEnd), context: context()) == .delete)
    }

    @Test func unknownEventIsIgnored() {
        var e = event(.stop)
        e.kind = nil
        #expect(SessionReducer.reduce(nil, e, context: context()) == .ignore)
    }

    @Test func cwdAndPidFollowTheLatestEvent() throws {
        let first = try #require(run([event(.userPromptSubmit)]))
        var moved = event(.preToolUse, tool: "Read")
        moved.cwd = "/Users/demo/other"
        guard case .write(let state) = SessionReducer.reduce(first, moved, context: EventContext(now: t0, host: .terminal, terminalApp: "iTerm.app", pid: 200)) else {
            Issue.record("expected a write"); return
        }
        #expect(state.cwd == "/Users/demo/other")
        #expect(state.pid == 200)
        #expect(state.host == .terminal)
        #expect(state.terminalApp == "iTerm.app")
    }

    @Test func emptyTitleNeverOverwritesARealOne() throws {
        let titled = try #require(run([event(.sessionStart, title: "Fix login")]))
        let again = try #require(run([event(.sessionStart, title: "  ")], start: titled))
        #expect(again.title == "Fix login")
    }
}
```

- [ ] **Step 2: Run to see them fail**

Run: `swift test --package-path Packages/TidewatchCore`
Expected: compile errors (`SessionReducer`, `EventContext`, `ReduceOutcome` not found).

- [ ] **Step 3: Implement**

`SessionReducer.swift`:

```swift
import Foundation

/// Facts about the hook process that are not in the payload.
public struct EventContext: Sendable, Equatable {
    public var now: Date
    public var host: SessionHost
    public var terminalApp: String?
    public var pid: Int32?

    public init(now: Date, host: SessionHost, terminalApp: String?, pid: Int32?) {
        self.now = now
        self.host = host
        self.terminalApp = terminalApp
        self.pid = pid
    }
}

public enum ReduceOutcome: Sendable, Equatable {
    case write(SessionState)
    case delete
    case ignore
}

/// Turns one hook event into the session's next state (spec section 4.1).
public enum SessionReducer {
    /// How long after an approval was resolved a `Notification permission_prompt` is treated as
    /// the late echo of that approval, not as a new one.
    public static let lateNotificationWindow: TimeInterval = 10

    public static func reduce(_ current: SessionState?, _ event: HookEvent, context: EventContext) -> ReduceOutcome {
        guard let kind = event.kind else { return .ignore }
        if kind == .sessionEnd { return .delete }
        if kind == .notification, event.notificationType != "permission_prompt" { return .ignore }

        let now = context.now
        var state = current ?? SessionState(
            sessionId: event.sessionId,
            cwd: event.cwd,
            host: context.host,
            terminalApp: context.terminalApp,
            pid: context.pid,
            now: now
        )
        if !event.cwd.isEmpty { state.cwd = event.cwd }
        state.host = context.host
        state.terminalApp = context.terminalApp
        if let pid = context.pid { state.pid = pid }
        state.lastEvent = now
        if let title = event.sessionTitle?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
            state.title = title
        }

        switch kind {
        case .sessionStart:
            // A new session starts idle (from init); a resumed or compacted one keeps its status.
            break

        case .userPromptSubmit:
            clearApproval(&state, now: now)
            setStatus(&state, .working, now: now)
            state.activity = .thinking
            state.tool = nil
            state.detail = nil

        case .preToolUse:
            state.activity = ActivityClassifier.activity(forTool: event.toolName ?? "", command: event.command)
            if state.status != .needsApproval {
                setStatus(&state, .working, now: now)
                state.tool = event.toolName
                state.detail = ApprovalDetail.describe(event)
            }

        case .postToolUse, .postToolUseFailure:
            if state.status == .needsApproval {
                // Only the call that waited clears the approval: parallel tool calls keep running.
                let matches = state.pendingApproval == nil || state.pendingApproval == ApprovalDetail.signature(event)
                guard matches else { break }
                clearApproval(&state, now: now)
            }
            setStatus(&state, .working, now: now)

        case .permissionRequest:
            state.pendingApproval = ApprovalDetail.signature(event)
            state.tool = event.toolName
            state.detail = ApprovalDetail.describe(event)
            setStatus(&state, .needsApproval, now: now)

        case .notification:
            if state.status == .needsApproval { break }
            if let resolved = state.approvalResolvedAt, now.timeIntervalSince(resolved) < lateNotificationWindow { break }
            state.tool = nil
            state.detail = nil
            setStatus(&state, .needsApproval, now: now)

        case .stop:
            clearApproval(&state, now: now)
            state.backgroundTasks = event.runningBackgroundTasks
            state.tool = nil
            state.detail = nil
            setStatus(&state, .awaitingReview, now: now)

        case .subagentStart:
            state.activity = .runningAgents
            if state.status != .needsApproval { setStatus(&state, .working, now: now) }

        case .preCompact:
            state.activity = .compacting
            if state.status != .needsApproval { setStatus(&state, .working, now: now) }

        case .sessionEnd:
            return .delete
        }
        return .write(state)
    }

    private static func setStatus(_ state: inout SessionState, _ status: SessionStatus, now: Date) {
        guard state.status != status else { return }
        state.status = status
        state.statusSince = now
    }

    private static func clearApproval(_ state: inout SessionState, now: Date) {
        if state.status == .needsApproval || state.pendingApproval != nil {
            state.approvalResolvedAt = now
        }
        state.pendingApproval = nil
    }
}
```

- [ ] **Step 4: Run the tests**

Run: `swift test --package-path Packages/TidewatchCore`
Expected: all pass.

- [ ] **Step 5: Checkpoint**

`make test` passes.

---

### Task 5: Display rules

**Files:**
- Create: `Packages/TidewatchCore/Sources/TidewatchCore/DisplayRules.swift`
- Test: `DisplayRulesTests.swift`

**Interfaces:**
- Consumes: `SessionState`, `SessionStatus`, `SessionActivity`.
- Produces: `DisplayRules.reviewToIdle` (600), `DisplayRules.staleAfter` (21600), `displayStatus(_:now:acknowledgedAt:) -> SessionStatus`, `isStale(_:now:) -> Bool`, `ordered(_:) -> [SessionState]`, `statusLine(_:status:) -> String`, `activityLabel(_:) -> String`, `elapsed(since:now:) -> String`, `names(for:) -> [String: String]`.

- [ ] **Step 1: Write the failing tests**

`DisplayRulesTests.swift`:

```swift
import Foundation
import Testing
@testable import TidewatchCore

struct DisplayRulesTests {
    private let t0 = Date(timeIntervalSince1970: 1_791_620_000)

    private func session(_ id: String, _ cwd: String = "/Users/demo/app", status: SessionStatus = .working, firstSeen: TimeInterval = 0, title: String? = nil) -> SessionState {
        var s = SessionState(sessionId: id, cwd: cwd, host: .vscode, terminalApp: nil, pid: nil, now: t0.addingTimeInterval(firstSeen))
        s.status = status
        s.title = title
        return s
    }

    @Test func awaitingReviewTurnsIdleAfterTenMinutes() {
        var s = session("a", status: .awaitingReview)
        s.statusSince = t0
        #expect(DisplayRules.displayStatus(s, now: t0.addingTimeInterval(599), acknowledgedAt: nil) == .awaitingReview)
        #expect(DisplayRules.displayStatus(s, now: t0.addingTimeInterval(601), acknowledgedAt: nil) == .idle)
    }

    @Test func acknowledgedAwaitingReviewIsIdleUntilTheNextEvent() {
        var s = session("a", status: .awaitingReview)
        s.lastEvent = t0
        #expect(DisplayRules.displayStatus(s, now: t0, acknowledgedAt: t0) == .idle)
        s.lastEvent = t0.addingTimeInterval(5)
        #expect(DisplayRules.displayStatus(s, now: t0.addingTimeInterval(5), acknowledgedAt: t0) == .awaitingReview)
    }

    @Test func acknowledgementNeverHidesApprovalOrWork() {
        let approval = session("a", status: .needsApproval)
        #expect(DisplayRules.displayStatus(approval, now: t0.addingTimeInterval(3600), acknowledgedAt: t0.addingTimeInterval(3600)) == .needsApproval)
        let working = session("b", status: .working)
        #expect(DisplayRules.displayStatus(working, now: t0.addingTimeInterval(3600), acknowledgedAt: t0.addingTimeInterval(3600)) == .working)
    }

    @Test func staleAfterSixHoursWithoutEvents() {
        let s = session("a")
        #expect(!DisplayRules.isStale(s, now: t0.addingTimeInterval(6 * 3600 - 1)))
        #expect(DisplayRules.isStale(s, now: t0.addingTimeInterval(6 * 3600 + 1)))
    }

    @Test func orderIsStableByFirstSeenThenId() {
        let list = [session("c", firstSeen: 20), session("b", firstSeen: 10), session("a", firstSeen: 10)]
        #expect(DisplayRules.ordered(list).map(\.sessionId) == ["a", "b", "c"])
    }

    @Test func statusLines() {
        var s = session("a", status: .working)
        s.activity = .runningTests
        #expect(DisplayRules.statusLine(s, status: .working) == "Running tests…")
        s.activity = .thinking
        #expect(DisplayRules.statusLine(s, status: .working) == "Working…")
        s.tool = "Bash"
        s.detail = "npm install"
        #expect(DisplayRules.statusLine(s, status: .needsApproval) == "Needs approval · npm install")
        s.tool = "AskUserQuestion"
        s.detail = nil
        #expect(DisplayRules.statusLine(s, status: .needsApproval) == "Needs your answer")
        s.backgroundTasks = 0
        #expect(DisplayRules.statusLine(s, status: .awaitingReview) == "Awaiting review")
        s.backgroundTasks = 1
        #expect(DisplayRules.statusLine(s, status: .awaitingReview) == "Awaiting review · 1 background task")
        s.backgroundTasks = 3
        #expect(DisplayRules.statusLine(s, status: .awaitingReview) == "Awaiting review · 3 background tasks")
        #expect(DisplayRules.statusLine(s, status: .idle) == "Idle")
    }

    @Test func everyActivityHasALabel() {
        for activity in SessionActivity.allCases {
            #expect(DisplayRules.activityLabel(activity).hasSuffix("…"))
        }
        #expect(DisplayRules.activityLabel(.compacting) == "Compacting…")
    }

    @Test func elapsedIsCompact() {
        #expect(DisplayRules.elapsed(since: t0, now: t0.addingTimeInterval(20)) == "now")
        #expect(DisplayRules.elapsed(since: t0, now: t0.addingTimeInterval(125)) == "2m")
        #expect(DisplayRules.elapsed(since: t0, now: t0.addingTimeInterval(3 * 3600 + 5)) == "3h")
        #expect(DisplayRules.elapsed(since: t0, now: t0.addingTimeInterval(2 * 86_400)) == "2d")
        #expect(DisplayRules.elapsed(since: t0.addingTimeInterval(30), now: t0) == "now")
    }

    @Test func namesTellSessionsInOneFolderApart() {
        let names = DisplayRules.names(for: [
            session("a", "/Users/demo/app", firstSeen: 1, title: "Fix login"),
            session("b", "/Users/demo/app", firstSeen: 2),
            session("c", "/Users/demo/site", firstSeen: 3),
        ])
        #expect(names["a"] == "app · Fix login")
        #expect(names["b"] == "app #2")
        #expect(names["c"] == "site")
    }
}
```

- [ ] **Step 2: Run to see them fail**

Run: `swift test --package-path Packages/TidewatchCore`
Expected: compile errors (`DisplayRules` not found).

- [ ] **Step 3: Implement**

`DisplayRules.swift`:

```swift
import Foundation

/// How a session state is shown at a given moment (spec 4.2 to 4.4). Pure: every function takes
/// `now`, so a render never depends on a timer having fired.
public enum DisplayRules {
    /// "Awaiting review" fades to "Idle" after this long.
    public static let reviewToIdle: TimeInterval = 10 * 60
    /// A session with no event for this long is dropped (crash without `SessionEnd`).
    public static let staleAfter: TimeInterval = 6 * 60 * 60

    public static func displayStatus(_ state: SessionState, now: Date, acknowledgedAt: Date?) -> SessionStatus {
        guard state.status == .awaitingReview else { return state.status }
        if let acknowledgedAt, acknowledgedAt >= state.lastEvent { return .idle }
        if now.timeIntervalSince(state.statusSince) > reviewToIdle { return .idle }
        return .awaitingReview
    }

    public static func isStale(_ state: SessionState, now: Date) -> Bool {
        now.timeIntervalSince(state.lastEvent) > staleAfter
    }

    /// Stable order: lamps never jump when a status changes.
    public static func ordered(_ sessions: [SessionState]) -> [SessionState] {
        sessions.sorted { ($0.firstSeen, $0.sessionId) < ($1.firstSeen, $1.sessionId) }
    }

    public static func statusLine(_ state: SessionState, status: SessionStatus) -> String {
        switch status {
        case .working:
            return activityLabel(state.activity)
        case .needsApproval:
            let base = state.tool == "AskUserQuestion" ? "Needs your answer" : "Needs approval"
            if let detail = state.detail, !detail.isEmpty { return "\(base) · \(detail)" }
            return base
        case .awaitingReview:
            switch state.backgroundTasks {
            case 0: return "Awaiting review"
            case 1: return "Awaiting review · 1 background task"
            default: return "Awaiting review · \(state.backgroundTasks) background tasks"
            }
        case .idle:
            return "Idle"
        }
    }

    public static func activityLabel(_ activity: SessionActivity) -> String {
        switch activity {
        case .runningTests: return "Running tests…"
        case .runningCommands: return "Running commands…"
        case .coding: return "Coding…"
        case .readingCode: return "Reading code…"
        case .researching: return "Researching…"
        case .runningAgents: return "Running agents…"
        case .usingTools: return "Using tools…"
        case .compacting: return "Compacting…"
        case .thinking, .working: return "Working…"
        }
    }

    /// "now", "2m", "3h", "2d".
    public static func elapsed(since start: Date, now: Date) -> String {
        let seconds = max(0, now.timeIntervalSince(start))
        if seconds < 60 { return "now" }
        if seconds < 3600 { return "\(Int(seconds / 60))m" }
        if seconds < 86_400 { return "\(Int(seconds / 3600))h" }
        return "\(Int(seconds / 86_400))d"
    }

    /// Row titles keyed by session id: the folder name, plus the title (or "#n") when several
    /// sessions share a folder.
    public static func names(for sessions: [SessionState]) -> [String: String] {
        let sorted = ordered(sessions)
        var counts: [String: Int] = [:]
        for session in sorted { counts[session.project, default: 0] += 1 }
        var seen: [String: Int] = [:]
        var names: [String: String] = [:]
        for session in sorted {
            guard counts[session.project, default: 0] > 1 else {
                names[session.id] = session.project
                continue
            }
            seen[session.project, default: 0] += 1
            if let title = session.title {
                names[session.id] = "\(session.project) · \(title)"
            } else {
                names[session.id] = "\(session.project) #\(seen[session.project, default: 1])"
            }
        }
        return names
    }
}
```

- [ ] **Step 4: Run the tests**

Run: `swift test --package-path Packages/TidewatchCore`
Expected: all pass.

- [ ] **Step 5: Checkpoint**

`make test` passes.

---

### Task 6: File store, paths, host detection and the real helper

**Files:**
- Create: `Packages/TidewatchCore/Sources/TidewatchCore/HostDetector.swift`, `DataPaths.swift`, `SessionFileStore.swift`, `scripts/test-hook.sh`
- Modify: `TidewatchHook/main.swift` (replace the stub)
- Test: `HostDetectorTests.swift`, `DataPathsTests.swift`, `SessionFileStoreTests.swift`

**Interfaces:**
- Consumes: `SessionReducer`, `SessionCoding`, `HookEvent`, `EventContext`.
- Produces: `HostDetector.host(_ env: [String: String]) -> SessionHost`, `HostDetector.terminalApp(_:) -> String?`; `DataPaths.root(environment:)`, `DataPaths.sessions(environment:)`, `DataPaths.helper(environment:)` (all `-> URL`, `environment` defaults to the process environment); `public struct SessionFileStore: Sendable` with `directory: URL`, `init(directory:)`, `static isValidSessionId(_:) -> Bool`, `fileURL(for:) -> URL`, `apply(_:context:) throws -> ReduceOutcome` (discardable), `read(_ url: URL) -> SessionState?`, `write(_:to:) throws`, `loadAll() -> [SessionState]`, `remove(sessionId:)`; `SessionFileStoreError.invalidSessionId(String)`, `.lockFailed(Int32)`.

- [ ] **Step 1: Write the failing tests**

`HostDetectorTests.swift`:

```swift
import Testing
@testable import TidewatchCore

struct HostDetectorTests {
    @Test func vscodeExtensionAndIntegratedTerminalAreVSCode() {
        #expect(HostDetector.host(["CLAUDE_CODE_ENTRYPOINT": "claude-vscode", "VSCODE_PID": "733"]) == .vscode)
        #expect(HostDetector.host(["CLAUDE_CODE_ENTRYPOINT": "cli", "TERM_PROGRAM": "vscode"]) == .vscode)
    }

    @Test func everythingElseIsATerminal() {
        #expect(HostDetector.host(["CLAUDE_CODE_ENTRYPOINT": "cli", "TERM_PROGRAM": "iTerm.app"]) == .terminal)
        #expect(HostDetector.host([:]) == .terminal)
        #expect(HostDetector.terminalApp(["TERM_PROGRAM": "ghostty"]) == "ghostty")
        #expect(HostDetector.terminalApp(["TERM_PROGRAM": ""]) == nil)
    }
}
```

`DataPathsTests.swift`:

```swift
import Foundation
import Testing
@testable import TidewatchCore

struct DataPathsTests {
    @Test func defaultsToApplicationSupport() {
        let root = DataPaths.root(environment: [:])
        #expect(root.path.hasSuffix("/Library/Application Support/Tidewatch"))
        #expect(DataPaths.sessions(environment: [:]).path.hasSuffix("/Tidewatch/sessions"))
        #expect(DataPaths.helper(environment: [:]).path.hasSuffix("/Tidewatch/bin/tidewatch-hook"))
    }

    @Test func environmentOverridesTheRoot() {
        let env = ["TIDEWATCH_DATA_DIR": "/tmp/tw-test"]
        #expect(DataPaths.root(environment: env).path == "/tmp/tw-test")
        #expect(DataPaths.sessions(environment: env).path == "/tmp/tw-test/sessions")
    }
}
```

`SessionFileStoreTests.swift`:

```swift
import Foundation
import Testing
@testable import TidewatchCore

struct SessionFileStoreTests {
    private let t0 = Date(timeIntervalSince1970: 1_791_620_000)

    private func makeStore() -> SessionFileStore {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("tw-store-\(UUID().uuidString)/sessions", isDirectory: true)
        return SessionFileStore(directory: dir)
    }

    private func context(_ s: TimeInterval = 0) -> EventContext {
        EventContext(now: t0.addingTimeInterval(s), host: .vscode, terminalApp: nil, pid: 42)
    }

    private func event(_ kind: HookEvent.Kind, id: String = "s-1") -> HookEvent {
        HookEvent(kind: kind, sessionId: id, cwd: "/Users/demo/app")
    }

    @Test func applyWritesAndUpdatesTheFile() throws {
        let store = makeStore()
        try store.apply(event(.sessionStart), context: context())
        try store.apply(event(.userPromptSubmit), context: context(1))
        let state = try #require(store.read(store.fileURL(for: "s-1")))
        #expect(state.status == .working)
        #expect(state.firstSeen == t0)
        #expect(store.loadAll().map(\.sessionId) == ["s-1"])
    }

    @Test func sessionEndDeletesFileAndLock() throws {
        let store = makeStore()
        try store.apply(event(.sessionStart), context: context())
        try store.apply(event(.sessionEnd), context: context(1))
        let files = try FileManager.default.contentsOfDirectory(atPath: store.directory.path)
        #expect(files.isEmpty)
    }

    @Test func rejectsPathTraversal() throws {
        let store = makeStore()
        #expect(throws: SessionFileStoreError.invalidSessionId("../evil")) {
            try store.apply(event(.stop, id: "../evil"), context: context())
        }
        #expect(!FileManager.default.fileExists(atPath: store.directory.deletingLastPathComponent().appendingPathComponent("evil.json").path))
        #expect(!SessionFileStore.isValidSessionId(""))
        #expect(!SessionFileStore.isValidSessionId("a/b"))
        #expect(SessionFileStore.isValidSessionId("2c7f6edd-2153-4800-a181-b41e70f4f557"))
    }

    @Test func ignoredEventsWriteNothing() throws {
        let store = makeStore()
        var unknown = event(.stop)
        unknown.kind = nil
        #expect(try store.apply(unknown, context: context()) == .ignore)
        #expect(store.loadAll().isEmpty)
    }

    @Test func loadAllSkipsCorruptAndForeignFiles() throws {
        let store = makeStore()
        try store.apply(event(.sessionStart, id: "good"), context: context())
        try Data("{ half".utf8).write(to: store.directory.appendingPathComponent("bad.json"))
        try Data("x".utf8).write(to: store.directory.appendingPathComponent("notes.txt"))
        #expect(store.loadAll().map(\.sessionId) == ["good"])
    }

    @Test func removeDeletesOneSession() throws {
        let store = makeStore()
        try store.apply(event(.sessionStart, id: "a"), context: context())
        try store.apply(event(.sessionStart, id: "b"), context: context())
        store.remove(sessionId: "a")
        #expect(store.loadAll().map(\.sessionId) == ["b"])
    }

    @Test func concurrentAppliesLeaveAValidFile() throws {
        let store = makeStore()
        try store.apply(event(.sessionStart), context: context())
        DispatchQueue.concurrentPerform(iterations: 64) { index in
            let kind: HookEvent.Kind = index.isMultiple(of: 2) ? .preToolUse : .postToolUse
            try? store.apply(HookEvent(kind: kind, sessionId: "s-1", cwd: "/Users/demo/app", toolName: "Read", filePath: "/a"), context: context(Double(index)))
        }
        let state = try #require(store.read(store.fileURL(for: "s-1")))
        #expect(state.status == .working)
    }
}
```

- [ ] **Step 2: Run to see them fail**

Run: `swift test --package-path Packages/TidewatchCore`
Expected: compile errors (`HostDetector`, `DataPaths`, `SessionFileStore` not found).

- [ ] **Step 3: Implement**

`HostDetector.swift`:

```swift
/// Where a session runs, from the hook process environment (verified in the spike: the VS Code
/// extension sets `CLAUDE_CODE_ENTRYPOINT=claude-vscode`).
public enum HostDetector {
    public static func host(_ environment: [String: String]) -> SessionHost {
        if environment["CLAUDE_CODE_ENTRYPOINT"] == "claude-vscode" || environment["TERM_PROGRAM"] == "vscode" {
            return .vscode
        }
        return .terminal
    }

    public static func terminalApp(_ environment: [String: String]) -> String? {
        guard let value = environment["TERM_PROGRAM"], !value.isEmpty else { return nil }
        return value
    }
}
```

`DataPaths.swift`:

```swift
import Foundation

/// `~/Library/Application Support/Tidewatch/`, or `TIDEWATCH_DATA_DIR` (tests, previews).
public enum DataPaths {
    public static func root(environment: [String: String] = ProcessInfo.processInfo.environment) -> URL {
        if let custom = environment["TIDEWATCH_DATA_DIR"], !custom.isEmpty {
            return URL(fileURLWithPath: custom, isDirectory: true)
        }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Tidewatch", isDirectory: true)
    }

    public static func sessions(environment: [String: String] = ProcessInfo.processInfo.environment) -> URL {
        root(environment: environment).appendingPathComponent("sessions", isDirectory: true)
    }

    /// The stable helper copy the hooks in settings.json point to.
    public static func helper(environment: [String: String] = ProcessInfo.processInfo.environment) -> URL {
        root(environment: environment).appendingPathComponent("bin", isDirectory: true).appendingPathComponent("tidewatch-hook")
    }
}
```

`SessionFileStore.swift`:

```swift
import Foundation

public enum SessionFileStoreError: Error, Equatable {
    case invalidSessionId(String)
    case lockFailed(Int32)
}

/// The sessions folder. Each event is applied under an exclusive `flock` on `<id>.lock` and
/// written with an atomic replace, so parallel hook processes never interleave and a reader
/// never sees half a file.
public struct SessionFileStore: Sendable {
    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    /// Claude Code session ids are UUIDs; anything with other characters is refused so an id can
    /// never point outside the folder.
    public static func isValidSessionId(_ id: String) -> Bool {
        !id.isEmpty && id.count <= 128 && id.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }
    }

    public func fileURL(for sessionId: String) -> URL {
        directory.appendingPathComponent("\(sessionId).json")
    }

    private func lockURL(for sessionId: String) -> URL {
        directory.appendingPathComponent("\(sessionId).lock")
    }

    @discardableResult
    public func apply(_ event: HookEvent, context: EventContext) throws -> ReduceOutcome {
        guard Self.isValidSessionId(event.sessionId) else {
            throw SessionFileStoreError.invalidSessionId(event.sessionId)
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let descriptor = open(lockURL(for: event.sessionId).path, O_CREAT | O_RDWR | O_CLOEXEC, 0o600)
        guard descriptor >= 0 else { throw SessionFileStoreError.lockFailed(errno) }
        defer { close(descriptor) }
        guard flock(descriptor, LOCK_EX) == 0 else { throw SessionFileStoreError.lockFailed(errno) }
        defer { flock(descriptor, LOCK_UN) }

        let url = fileURL(for: event.sessionId)
        let outcome = SessionReducer.reduce(read(url), event, context: context)
        switch outcome {
        case .write(let state):
            try write(state, to: url)
        case .delete:
            try? FileManager.default.removeItem(at: url)
            try? FileManager.default.removeItem(at: lockURL(for: event.sessionId))
        case .ignore:
            break
        }
        return outcome
    }

    public func read(_ url: URL) -> SessionState? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? SessionCoding.decoder().decode(SessionState.self, from: data)
    }

    public func write(_ state: SessionState, to url: URL) throws {
        let data = try SessionCoding.encoder().encode(state)
        try data.write(to: url, options: .atomic)
    }

    /// Every readable session file; unreadable or foreign files are skipped.
    public func loadAll() -> [SessionState] {
        guard let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else {
            return []
        }
        return files.filter { $0.pathExtension == "json" }.compactMap(read)
    }

    public func remove(sessionId: String) {
        guard Self.isValidSessionId(sessionId) else { return }
        try? FileManager.default.removeItem(at: fileURL(for: sessionId))
        try? FileManager.default.removeItem(at: lockURL(for: sessionId))
    }
}
```

- [ ] **Step 4: Run the package tests**

Run: `swift test --package-path Packages/TidewatchCore`
Expected: all pass.

- [ ] **Step 5: The real helper**

Replace `TidewatchHook/main.swift`:

```swift
import Foundation
import os
import TidewatchCore

// Called by Claude Code hooks with one event JSON on stdin (spec 6.1). Never prints, never
// touches the network and always exits 0, so it can never block or change Claude's behaviour.
let log = Logger(subsystem: "pl.craftweb.tidewatch", category: "hook")
let environment = ProcessInfo.processInfo.environment
let input = FileHandle.standardInput.readDataToEndOfFile()

do {
    let event = try HookEvent.decode(input)
    let context = EventContext(
        now: Date(),
        host: HostDetector.host(environment),
        terminalApp: HostDetector.terminalApp(environment),
        // The hook command is a direct child of the Claude Code process (spike 6.3).
        pid: getppid()
    )
    try SessionFileStore(directory: DataPaths.sessions(environment: environment)).apply(event, context: context)
} catch {
    log.error("hook event skipped: \(String(describing: error), privacy: .public)")
}
exit(0)
```

- [ ] **Step 6: End-to-end helper script**

`scripts/test-hook.sh` (then `chmod +x scripts/test-hook.sh`):

```bash
#!/usr/bin/env bash
# End-to-end check of the built hook helper against a temp data folder (TIDEWATCH_DATA_DIR).
# Run after a Debug build (make test runs it).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BIN="${HOOK_BIN:-$ROOT/.local-build/Build/Products/Debug/tidewatch-hook}"
[[ -x "$BIN" ]] || { echo "test-hook: no helper at $BIN (run make build)" >&2; exit 1; }

DIR="$(mktemp -d)"
trap 'rm -rf "$DIR"' EXIT
export TIDEWATCH_DATA_DIR="$DIR"
F="$DIR/sessions/s-1.json"

send() { printf '%s' "$1" | "$BIN"; }
status() { python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["status"])' "$F" 2>/dev/null || echo missing; }
fail() { echo "test-hook: FAIL - $1" >&2; exit 1; }
base='"session_id":"s-1","cwd":"/Users/demo/my project"'

send "{$base,\"hook_event_name\":\"SessionStart\",\"source\":\"startup\"}"
[[ "$(status)" == idle ]] || fail "SessionStart should be idle"
send "{$base,\"hook_event_name\":\"UserPromptSubmit\",\"prompt\":\"x\"}"
[[ "$(status)" == working ]] || fail "UserPromptSubmit should be working"
send "{$base,\"hook_event_name\":\"PermissionRequest\",\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"npm install\"}}"
[[ "$(status)" == needsApproval ]] || fail "PermissionRequest should need approval"
send "{$base,\"hook_event_name\":\"PostToolUse\",\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"npm install\"},\"tool_response\":{\"stdout\":\"ok\"}}"
[[ "$(status)" == working ]] || fail "matching PostToolUse should clear the approval"
send "{$base,\"hook_event_name\":\"Stop\",\"background_tasks\":[]}"
[[ "$(status)" == awaitingReview ]] || fail "Stop should await review"

send 'not json at all'
[[ "$(status)" == awaitingReview ]] || fail "garbage must not change the state"
out="$(printf 'garbage' | "$BIN")"
[[ -z "$out" ]] || fail "the helper printed to stdout"
printf 'garbage' | "$BIN" || fail "the helper exited non-zero"

send '{"session_id":"../evil","cwd":"/tmp","hook_event_name":"Stop"}'
[[ ! -e "$DIR/evil.json" ]] || fail "path traversal wrote outside sessions/"

for _ in $(seq 1 20); do
    send "{$base,\"hook_event_name\":\"PreToolUse\",\"tool_name\":\"Read\",\"tool_input\":{\"file_path\":\"/a\"}}" &
done
wait
python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$F" || fail "parallel writes corrupted the file"

start=$(python3 -c 'import time; print(time.time())')
for _ in $(seq 1 50); do
    send "{$base,\"hook_event_name\":\"PostToolUse\",\"tool_name\":\"Read\",\"tool_input\":{\"file_path\":\"/a\"}}"
done
end=$(python3 -c 'import time; print(time.time())')
avg=$(python3 -c "print(round(($end - $start) / 50 * 1000, 1))")
echo "test-hook: average ${avg} ms per event"
python3 -c "import sys; sys.exit(0 if $avg < 50 else 1)" || fail "helper too slow (${avg} ms per event, budget 50)"

send "{$base,\"hook_event_name\":\"SessionEnd\",\"reason\":\"other\"}"
[[ ! -e "$F" ]] || fail "SessionEnd should delete the file"

echo "test-hook: OK"
```

- [ ] **Step 7: Run everything**

Run: `make build && make test`
Expected: package tests pass, `TEST SUCCEEDED`, `test-hook: average N ms per event` (expect well under 20) and `test-hook: OK`.

- [ ] **Step 8: Checkpoint**

`make test` passes.

---

### Task 7: HookInstaller and HelperInstaller

**Files:**
- Create: `Tidewatch/Integration/HookInstaller.swift`, `Tidewatch/Integration/HelperInstaller.swift`
- Test: `TidewatchTests/HookInstallerTests.swift`, `TidewatchTests/HelperInstallerTests.swift`

**Interfaces:**
- Consumes: `DataPaths` (Task 6).
- Produces: `HookInstaller.marker`, `HookInstaller.events: [(name: String, matcher: String?)]`, `command(helperPath:) -> String`, `installing(into:helperPath:) -> [String: Any]`, `removing(from:) -> [String: Any]`, `isTidewatchGroup(_:) -> Bool`, `isInstalled(_:helperPath:) -> Bool`, `readSettings(at:) throws -> [String: Any]`, `writeSettings(_:to:) throws`, `connect(settingsURL:helperPath:) throws`, `disconnect(settingsURL:) throws`, `defaultSettingsURL() -> URL`; `HookInstallerError.invalidJSON`; `HelperInstaller.bundledHelper(in:) -> URL?`, `HelperInstaller.refresh(from:to:) throws -> Bool` (discardable); `HelperInstallerError.missingBundledHelper`.

- [ ] **Step 1: Write the failing tests**

`TidewatchTests/HookInstallerTests.swift`:

```swift
import Foundation
import Testing
@testable import Tidewatch

struct HookInstallerTests {
    private let helper = "/Users/demo/Library/Application Support/Tidewatch/bin/tidewatch-hook"

    private func tempURL(_ name: String = "settings.json") -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("tw-hooks-\(UUID().uuidString)").appendingPathComponent(name)
    }

    private func json(_ text: String) -> [String: Any] {
        try! JSONSerialization.jsonObject(with: Data(text.utf8)) as! [String: Any]
    }

    @Test func installsEveryEventWithQuotedCommandAndTimeout() throws {
        let result = HookInstaller.installing(into: [:], helperPath: helper)
        let hooks = try #require(result["hooks"] as? [String: Any])
        #expect(Set(hooks.keys) == Set(HookInstaller.events.map(\.name)))
        let pre = try #require((hooks["PreToolUse"] as? [Any])?.first as? [String: Any])
        #expect(pre["matcher"] as? String == "*")
        let entry = try #require((pre["hooks"] as? [Any])?.first as? [String: Any])
        #expect(entry["type"] as? String == "command")
        #expect(entry["command"] as? String == "\"\(helper)\"")
        #expect(entry["timeout"] as? Int == 5)
        let stop = try #require((hooks["Stop"] as? [Any])?.first as? [String: Any])
        #expect(stop["matcher"] == nil)
        #expect(HookInstaller.isInstalled(result, helperPath: helper))
    }

    @Test func keepsOtherKeysAndOtherHooks() throws {
        let settings = json(#"{"effortLevel":"high","remoteControlAtStartup":true,"hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"/usr/local/bin/guard"}]}],"Stop":[]}}"#)
        let installed = HookInstaller.installing(into: settings, helperPath: helper)
        #expect(installed["effortLevel"] as? String == "high")
        #expect(installed["remoteControlAtStartup"] as? Bool == true)
        let pre = try #require((installed["hooks"] as? [String: Any])?["PreToolUse"] as? [Any])
        #expect(pre.count == 2)
        #expect(!HookInstaller.isTidewatchGroup(pre[0]))
        #expect(HookInstaller.isTidewatchGroup(pre[1]))

        let removed = HookInstaller.removing(from: installed)
        let hooks = try #require(removed["hooks"] as? [String: Any])
        #expect((hooks["PreToolUse"] as? [Any])?.count == 1)
        #expect((hooks["Stop"] as? [Any])?.isEmpty == true)
        #expect(hooks["SessionStart"] == nil)
        #expect(!HookInstaller.isInstalled(removed, helperPath: helper))
    }

    @Test func installingTwiceDoesNotDuplicate() throws {
        let twice = HookInstaller.installing(into: HookInstaller.installing(into: [:], helperPath: helper), helperPath: helper)
        let stop = try #require((twice["hooks"] as? [String: Any])?["Stop"] as? [Any])
        #expect(stop.count == 1)
    }

    @Test func reinstallingWithANewPathReplacesTheOldEntries() throws {
        let old = HookInstaller.installing(into: [:], helperPath: "/Old/Tidewatch/bin/tidewatch-hook")
        let new = HookInstaller.installing(into: old, helperPath: helper)
        #expect(HookInstaller.isInstalled(new, helperPath: helper))
        #expect(!HookInstaller.isInstalled(new, helperPath: "/Old/Tidewatch/bin/tidewatch-hook"))
        #expect(((new["hooks"] as? [String: Any])?["Stop"] as? [Any])?.count == 1)
    }

    @Test func removingFromSettingsWithoutTidewatchChangesNothing() {
        let settings = json(#"{"hooks":{"Stop":[]},"a":1}"#)
        let removed = HookInstaller.removing(from: settings)
        #expect(NSDictionary(dictionary: removed).isEqual(to: settings))
    }

    @Test func connectCreatesAMissingFile() throws {
        let url = tempURL()
        try HookInstaller.connect(settingsURL: url, helperPath: helper)
        #expect(HookInstaller.isInstalled(try HookInstaller.readSettings(at: url), helperPath: helper))
        #expect(!FileManager.default.fileExists(atPath: url.path + ".tidewatch-backup"))
    }

    @Test func connectBacksUpAndPreservesTheFile() throws {
        let url = tempURL()
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let original = #"{"enabledPlugins":{"x@y":true},"permissions":{"allow":["Bash(ls)"]}}"#
        try Data(original.utf8).write(to: url)
        try HookInstaller.connect(settingsURL: url, helperPath: helper)
        let backup = try String(contentsOf: URL(fileURLWithPath: url.path + ".tidewatch-backup"), encoding: .utf8)
        #expect(backup == original)
        let settings = try HookInstaller.readSettings(at: url)
        #expect((settings["enabledPlugins"] as? [String: Any])?["x@y"] as? Bool == true)
        #expect(((settings["permissions"] as? [String: Any])?["allow"] as? [String]) == ["Bash(ls)"])
        let text = try String(contentsOf: url, encoding: .utf8)
        #expect(text.contains("\"x@y\" : true"))

        try HookInstaller.disconnect(settingsURL: url)
        #expect(try HookInstaller.readSettings(at: url)["hooks"] == nil)
    }

    @Test func invalidJSONIsNeverOverwritten() throws {
        let url = tempURL()
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("{ broken".utf8).write(to: url)
        #expect(throws: HookInstallerError.invalidJSON) {
            try HookInstaller.connect(settingsURL: url, helperPath: helper)
        }
        #expect(try String(contentsOf: url, encoding: .utf8) == "{ broken")
    }

    @Test func writesThroughASymlinkedSettingsFile() throws {
        let real = tempURL("real-settings.json")
        try FileManager.default.createDirectory(at: real.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: real)
        let link = real.deletingLastPathComponent().appendingPathComponent("settings.json")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)
        try HookInstaller.connect(settingsURL: link, helperPath: helper)
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: link.path) == real.path)
        #expect(HookInstaller.isInstalled(try HookInstaller.readSettings(at: real), helperPath: helper))
    }

    @Test func emptyFileCountsAsEmptySettings() throws {
        let url = tempURL()
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("  \n".utf8).write(to: url)
        #expect(try HookInstaller.readSettings(at: url).isEmpty)
    }
}
```

`TidewatchTests/HelperInstallerTests.swift`:

```swift
import Foundation
import Testing
@testable import Tidewatch

struct HelperInstallerTests {
    private func makeSource(_ content: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("tw-src-\(UUID().uuidString)")
        try Data(content.utf8).write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        return url
    }

    @Test func copiesOnceThenOnlyWhenChanged() throws {
        let destination = FileManager.default.temporaryDirectory.appendingPathComponent("tw-dst-\(UUID().uuidString)/bin/tidewatch-hook")
        let source = try makeSource("v1")
        #expect(try HelperInstaller.refresh(from: source, to: destination))
        #expect(FileManager.default.isExecutableFile(atPath: destination.path))
        #expect(try !HelperInstaller.refresh(from: source, to: destination))
        let updated = try makeSource("v2")
        #expect(try HelperInstaller.refresh(from: updated, to: destination))
        #expect(try String(contentsOf: destination, encoding: .utf8) == "v2")
    }

    @Test func missingSourceThrows() {
        #expect(throws: HelperInstallerError.missingBundledHelper) {
            try HelperInstaller.refresh(from: nil, to: URL(fileURLWithPath: "/tmp/x"))
        }
    }

    @Test func bundledHelperSitsNextToTheExecutable() throws {
        let helper = try #require(HelperInstaller.bundledHelper())
        #expect(helper.lastPathComponent == "tidewatch-hook")
        #expect(helper.deletingLastPathComponent().lastPathComponent == "MacOS")
    }
}
```

- [ ] **Step 2: Run to see them fail**

Run: `make test`
Expected: build fails in `TidewatchTests` (`HookInstaller`, `HelperInstaller` not found).

- [ ] **Step 3: Implement**

`Tidewatch/Integration/HookInstaller.swift`:

```swift
import Foundation

enum HookInstallerError: Error, LocalizedError, Equatable {
    case invalidJSON

    var errorDescription: String? {
        "~/.claude/settings.json is not valid JSON, so Tidewatch left it untouched."
    }
}

/// Adds and removes Tidewatch's own hook entries in Claude Code's user settings (spec 6.1).
/// Entries are recognised by the helper path; every other key and hook stays as it is.
enum HookInstaller {
    static let marker = "/Tidewatch/bin/tidewatch-hook"
    static let timeout = 5
    static let events: [(name: String, matcher: String?)] = [
        ("SessionStart", nil),
        ("SessionEnd", nil),
        ("UserPromptSubmit", nil),
        ("PreToolUse", "*"),
        ("PostToolUse", "*"),
        ("PostToolUseFailure", "*"),
        ("PermissionRequest", "*"),
        ("Notification", nil),
        ("Stop", nil),
        ("SubagentStart", nil),
        ("PreCompact", nil),
    ]

    static func command(helperPath: String) -> String {
        "\"\(helperPath)\""
    }

    static func defaultSettingsURL() -> URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/settings.json")
    }

    // MARK: Pure

    static func installing(into settings: [String: Any], helperPath: String) -> [String: Any] {
        var result = removing(from: settings)
        var hooks = result["hooks"] as? [String: Any] ?? [:]
        for event in events {
            var groups = hooks[event.name] as? [Any] ?? []
            var group: [String: Any] = [
                "hooks": [["type": "command", "command": command(helperPath: helperPath), "timeout": timeout]],
            ]
            if let matcher = event.matcher { group["matcher"] = matcher }
            groups.append(group)
            hooks[event.name] = groups
        }
        result["hooks"] = hooks
        return result
    }

    static func removing(from settings: [String: Any]) -> [String: Any] {
        guard var hooks = settings["hooks"] as? [String: Any] else { return settings }
        var changed = false
        for (name, value) in hooks {
            guard let groups = value as? [Any] else { continue }
            let kept = groups.filter { !isTidewatchGroup($0) }
            guard kept.count != groups.count else { continue }
            changed = true
            if kept.isEmpty { hooks.removeValue(forKey: name) } else { hooks[name] = kept }
        }
        guard changed else { return settings }
        var result = settings
        if hooks.isEmpty { result.removeValue(forKey: "hooks") } else { result["hooks"] = hooks }
        return result
    }

    /// A matcher group whose every command is the Tidewatch helper.
    static func isTidewatchGroup(_ group: Any) -> Bool {
        guard let group = group as? [String: Any], let entries = group["hooks"] as? [Any], !entries.isEmpty else {
            return false
        }
        return entries.allSatisfy { ((($0 as? [String: Any])?["command"]) as? String)?.contains(marker) == true }
    }

    static func isInstalled(_ settings: [String: Any], helperPath: String) -> Bool {
        guard let hooks = settings["hooks"] as? [String: Any] else { return false }
        let expected = command(helperPath: helperPath)
        return events.allSatisfy { event in
            (hooks[event.name] as? [Any] ?? []).contains { group in
                guard isTidewatchGroup(group), let entries = (group as? [String: Any])?["hooks"] as? [Any] else { return false }
                return entries.contains { (($0 as? [String: Any])?["command"] as? String) == expected }
            }
        }
    }

    // MARK: File

    static func readSettings(at url: URL) throws -> [String: Any] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [:] }
        let data = try Data(contentsOf: url)
        if data.allSatisfy({ $0 == 0x20 || $0 == 0x0A || $0 == 0x0D || $0 == 0x09 }) { return [:] }
        guard let object = try? JSONSerialization.jsonObject(with: data), let settings = object as? [String: Any] else {
            throw HookInstallerError.invalidJSON
        }
        return settings
    }

    /// Backs the current file up to `settings.json.tidewatch-backup`, then writes atomically. A
    /// symlinked settings file is written at its target, so the link survives.
    static func writeSettings(_ settings: [String: Any], to url: URL) throws {
        let fileManager = FileManager.default
        let target = url.resolvingSymlinksInPath()
        if fileManager.fileExists(atPath: target.path) {
            let backup = URL(fileURLWithPath: url.path + ".tidewatch-backup")
            try? fileManager.removeItem(at: backup)
            try fileManager.copyItem(at: target, to: backup)
        } else {
            try fileManager.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        }
        let data = try JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        try data.write(to: target, options: .atomic)
    }

    static func connect(settingsURL: URL, helperPath: String) throws {
        let current = try readSettings(at: settingsURL)
        try writeSettings(installing(into: current, helperPath: helperPath), to: settingsURL)
    }

    static func disconnect(settingsURL: URL) throws {
        let current = try readSettings(at: settingsURL)
        let next = removing(from: current)
        guard !NSDictionary(dictionary: next).isEqual(to: current) else { return }
        try writeSettings(next, to: settingsURL)
    }
}
```

`Tidewatch/Integration/HelperInstaller.swift`:

```swift
import Foundation

enum HelperInstallerError: Error, Equatable {
    case missingBundledHelper
}

/// Keeps a stable copy of the hook helper in Application Support, so the command path stored in
/// settings.json survives moving or updating the app (spec 3).
enum HelperInstaller {
    /// `Tidewatch.app/Contents/MacOS/tidewatch-hook`.
    static func bundledHelper(in bundle: Bundle = .main) -> URL? {
        bundle.executableURL?.deletingLastPathComponent().appendingPathComponent("tidewatch-hook")
    }

    /// Copies `source` to `destination` when they differ. Returns true when it copied.
    @discardableResult
    static func refresh(from source: URL?, to destination: URL) throws -> Bool {
        let fileManager = FileManager.default
        guard let source, fileManager.isExecutableFile(atPath: source.path) else {
            throw HelperInstallerError.missingBundledHelper
        }
        if fileManager.contentsEqual(atPath: source.path, andPath: destination.path) { return false }
        let folder = destination.deletingLastPathComponent()
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        let temporary = folder.appendingPathComponent(".tidewatch-hook.\(UUID().uuidString)")
        try fileManager.copyItem(at: source, to: temporary)
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: temporary.path)
        // rename(2) replaces the old copy atomically: a hook running right now sees either one.
        guard rename(temporary.path, destination.path) == 0 else {
            try? fileManager.removeItem(at: temporary)
            throw CocoaError(.fileWriteUnknown)
        }
        return true
    }
}
```

Note: `bundledHelperSitsNextToTheExecutable` runs inside the test host, whose `Bundle.main` is `Tidewatch.app`.

- [ ] **Step 4: Run the tests**

Run: `make test`
Expected: all pass.

- [ ] **Step 5: Checkpoint**

`make test` passes.

---

### Task 8: SessionStore, folder watcher, acknowledgements, liveness

**Files:**
- Create: `Tidewatch/Sessions/SessionStore.swift`, `Tidewatch/Sessions/SessionFolderWatcher.swift`, `Tidewatch/Sessions/AcknowledgedStore.swift`, `Tidewatch/Sessions/ProcessLiveness.swift`
- Test: `TidewatchTests/SessionStoreTests.swift`

**Interfaces:**
- Consumes: `SessionFileStore`, `DisplayRules`, `SessionState`, `SessionStatus` (Core); `Log` (Task 1).
- Produces:
  - `struct DisplayedSession: Identifiable, Equatable, Sendable { let state: SessionState; let status: SessionStatus; let name: String; var id: String }`
  - `struct SessionTransition: Equatable, Sendable { let sessionId: String; let from: SessionStatus?; let to: SessionStatus }`
  - `@MainActor @Observable final class SessionStore` with `private(set) var sessions: [DisplayedSession]`, `var onTransition: ((SessionTransition) -> Void)?`, `init(fileStore:acknowledged:isAlive:clock:)`, `start()`, `reload()`, `acknowledge(_ session: DisplayedSession)`, `fileStore: SessionFileStore` (read-only).
  - `@MainActor final class AcknowledgedStore` with `init(defaults:)`, `acknowledgedAt(_:) -> Date?`, `set(_:for:)`, `prune(keeping:)`.
  - `ProcessLiveness.isAlive(_ pid: Int32) -> Bool`.

- [ ] **Step 1: Write the failing tests**

`TidewatchTests/SessionStoreTests.swift`:

```swift
import Foundation
import Testing
import TidewatchCore
@testable import Tidewatch

@MainActor
struct SessionStoreTests {
    final class Clock: @unchecked Sendable {
        var now = Date(timeIntervalSince1970: 1_791_620_000)
    }

    final class Liveness: @unchecked Sendable {
        var alive: Set<Int32> = []
    }

    private let clock = Clock()
    private let liveness = Liveness()
    private let files: SessionFileStore
    private let defaults: UserDefaults

    init() {
        files = SessionFileStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent("tw-sessions-\(UUID().uuidString)", isDirectory: true))
        try? FileManager.default.createDirectory(at: files.directory, withIntermediateDirectories: true)
        defaults = UserDefaults(suiteName: "tw-tests-\(UUID().uuidString)")!
    }

    private func makeStore() -> SessionStore {
        let clock = clock
        let liveness = liveness
        return SessionStore(
            fileStore: files,
            acknowledged: AcknowledgedStore(defaults: defaults),
            isAlive: { liveness.alive.contains($0) },
            clock: { clock.now }
        )
    }

    private func put(_ id: String, _ status: SessionStatus, cwd: String = "/Users/demo/app", pid: Int32? = nil, firstSeen: TimeInterval = 0, lastEvent: TimeInterval = 0) throws {
        var state = SessionState(sessionId: id, cwd: cwd, host: .vscode, terminalApp: nil, pid: pid, now: clock.now.addingTimeInterval(firstSeen))
        state.status = status
        state.statusSince = clock.now.addingTimeInterval(lastEvent)
        state.lastEvent = clock.now.addingTimeInterval(lastEvent)
        try files.write(state, to: files.fileURL(for: id))
    }

    @Test func loadsSessionsInStableOrderWithNames() throws {
        try put("b", .working, cwd: "/Users/demo/site", firstSeen: 10)
        try put("a", .needsApproval, cwd: "/Users/demo/app", firstSeen: 5)
        let store = makeStore()
        store.reload()
        #expect(store.sessions.map(\.id) == ["a", "b"])
        #expect(store.sessions.map(\.name) == ["app", "site"])
        #expect(store.sessions.map(\.status) == [.needsApproval, .working])
    }

    @Test func dropsDeadProcessesAndDeletesTheirFiles() throws {
        liveness.alive = [100]
        try put("alive", .working, pid: 100)
        try put("dead", .working, pid: 200)
        try put("unknown-pid", .working, pid: nil)
        let store = makeStore()
        store.reload()
        #expect(Set(store.sessions.map(\.id)) == ["alive", "unknown-pid"])
        #expect(!FileManager.default.fileExists(atPath: files.fileURL(for: "dead").path))
    }

    @Test func dropsStaleSessions() throws {
        try put("old", .idle, lastEvent: -7 * 3600)
        try put("fresh", .idle, lastEvent: -60)
        let store = makeStore()
        store.reload()
        #expect(store.sessions.map(\.id) == ["fresh"])
        #expect(!FileManager.default.fileExists(atPath: files.fileURL(for: "old").path))
    }

    @Test func noTransitionsOnTheFirstLoadThenOnePerChange() throws {
        try put("a", .working)
        let store = makeStore()
        var transitions: [SessionTransition] = []
        store.onTransition = { transitions.append($0) }
        store.reload()
        #expect(transitions.isEmpty)

        try put("a", .needsApproval)
        try put("b", .awaitingReview, firstSeen: 1)
        store.reload()
        #expect(transitions == [
            SessionTransition(sessionId: "a", from: .working, to: .needsApproval),
            SessionTransition(sessionId: "b", from: nil, to: .awaitingReview),
        ])

        store.reload()
        #expect(transitions.count == 2)
    }

    @Test func acknowledgingAwaitingReviewShowsIdleWithoutATransitionCue() throws {
        try put("a", .awaitingReview)
        let store = makeStore()
        store.reload()
        let session = try #require(store.sessions.first)
        #expect(session.status == .awaitingReview)
        store.acknowledge(session)
        #expect(store.sessions.first?.status == .idle)
    }

    @Test func awaitingReviewFadesToIdleWithTime() throws {
        try put("a", .awaitingReview)
        let store = makeStore()
        store.reload()
        clock.now = clock.now.addingTimeInterval(11 * 60)
        store.reload()
        #expect(store.sessions.first?.status == .idle)
    }

    @Test func acknowledgementsSurviveAStoreRestart() throws {
        try put("a", .awaitingReview)
        let first = makeStore()
        first.reload()
        first.acknowledge(try #require(first.sessions.first))
        let second = makeStore()
        second.reload()
        #expect(second.sessions.first?.status == .idle)
    }

    @Test func livenessOfThisProcessIsTrue() {
        #expect(ProcessLiveness.isAlive(getpid()))
        #expect(!ProcessLiveness.isAlive(0))
        #expect(!ProcessLiveness.isAlive(-1))
    }
}
```

- [ ] **Step 2: Run to see them fail**

Run: `make test`
Expected: build fails (`SessionStore`, `AcknowledgedStore`, `ProcessLiveness` not found).

- [ ] **Step 3: Implement**

`Tidewatch/Sessions/ProcessLiveness.swift`:

```swift
import Darwin

enum ProcessLiveness {
    /// True when a process with this pid exists (EPERM: it exists but belongs to someone else).
    @Sendable
    static func isAlive(_ pid: Int32) -> Bool {
        guard pid > 0 else { return false }
        return kill(pid, 0) == 0 || errno == EPERM
    }
}
```

`Tidewatch/Sessions/AcknowledgedStore.swift`:

```swift
import Foundation

/// Sessions the user opened from Tidewatch, with the `lastEvent` they had at that moment: an
/// "Awaiting review" session shows idle until its next event. Kept in UserDefaults, so the app
/// never writes the helper's session files. Stored as reference-date seconds (exact Double).
@MainActor
final class AcknowledgedStore {
    private static let key = "sessions.acknowledged"
    private let defaults: UserDefaults
    private var values: [String: Double]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        values = defaults.dictionary(forKey: Self.key) as? [String: Double] ?? [:]
    }

    func acknowledgedAt(_ sessionId: String) -> Date? {
        values[sessionId].map(Date.init(timeIntervalSinceReferenceDate:))
    }

    func set(_ date: Date, for sessionId: String) {
        values[sessionId] = date.timeIntervalSinceReferenceDate
        defaults.set(values, forKey: Self.key)
    }

    func prune(keeping ids: Set<String>) {
        let kept = values.filter { ids.contains($0.key) }
        guard kept.count != values.count else { return }
        values = kept
        defaults.set(values, forKey: Self.key)
    }
}
```

`Tidewatch/Sessions/SessionFolderWatcher.swift`:

```swift
import Foundation

/// Watches the sessions folder (a file added, replaced or removed) and calls `onChange` on the
/// main actor, debounced, so a burst of hook writes causes one reload. Lives as long as the app.
@MainActor
final class SessionFolderWatcher {
    static let debounce: DispatchTimeInterval = .milliseconds(100)

    private let source: DispatchSourceFileSystemObject
    private let onChange: @MainActor () -> Void
    private var pending: DispatchWorkItem?

    init?(directory: URL, onChange: @escaping @MainActor () -> Void) {
        let descriptor = open(directory.path, O_EVTONLY)
        guard descriptor >= 0 else { return nil }
        self.onChange = onChange
        source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor, eventMask: [.write, .delete, .rename], queue: .main)
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.schedule() }
        }
        source.setCancelHandler { close(descriptor) }
        source.resume()
    }

    private func schedule() {
        pending?.cancel()
        let item = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.onChange() }
        }
        pending = item
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.debounce, execute: item)
    }
}
```

`Tidewatch/Sessions/SessionStore.swift`:

```swift
import Foundation
import Observation
import TidewatchCore

/// A session as the widget shows it right now.
struct DisplayedSession: Identifiable, Equatable, Sendable {
    let state: SessionState
    let status: SessionStatus
    let name: String
    var id: String { state.sessionId }
}

/// A shown status that changed between two reloads (sounds).
struct SessionTransition: Equatable, Sendable {
    let sessionId: String
    let from: SessionStatus?
    let to: SessionStatus
}

/// The sessions folder as the widget sees it: loads the files, drops ended sessions, applies the
/// display rules and reports status changes. Reloads on folder changes and every 15 s (time rules,
/// liveness).
@MainActor
@Observable
final class SessionStore {
    static let refreshInterval: Duration = .seconds(15)

    private(set) var sessions: [DisplayedSession] = []
    @ObservationIgnored var onTransition: ((SessionTransition) -> Void)?
    @ObservationIgnored let fileStore: SessionFileStore
    @ObservationIgnored private let acknowledged: AcknowledgedStore
    @ObservationIgnored private let isAlive: @Sendable (Int32) -> Bool
    @ObservationIgnored private let clock: @Sendable () -> Date
    @ObservationIgnored private var watcher: SessionFolderWatcher?
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var lastStatuses: [String: SessionStatus] = [:]
    @ObservationIgnored private var hasLoaded = false

    init(
        fileStore: SessionFileStore,
        acknowledged: AcknowledgedStore,
        isAlive: @escaping @Sendable (Int32) -> Bool = ProcessLiveness.isAlive,
        clock: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.fileStore = fileStore
        self.acknowledged = acknowledged
        self.isAlive = isAlive
        self.clock = clock
    }

    func start() {
        try? FileManager.default.createDirectory(at: fileStore.directory, withIntermediateDirectories: true)
        reload()
        watcher = SessionFolderWatcher(directory: fileStore.directory) { [weak self] in
            self?.reload()
        }
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.refreshInterval)
                self?.reload()
            }
        }
    }

    func reload() {
        let now = clock()
        var live: [SessionState] = []
        for state in fileStore.loadAll() {
            let dead = state.pid.map { !isAlive($0) } ?? false
            if dead || DisplayRules.isStale(state, now: now) {
                fileStore.remove(sessionId: state.sessionId)
                Log.sessions.info("dropped an ended session (\(dead ? "process gone" : "stale", privacy: .public))")
                continue
            }
            live.append(state)
        }

        let ordered = DisplayRules.ordered(live)
        let names = DisplayRules.names(for: ordered)
        let displayed = ordered.map { state in
            DisplayedSession(
                state: state,
                status: DisplayRules.displayStatus(state, now: now, acknowledgedAt: acknowledged.acknowledgedAt(state.sessionId)),
                name: names[state.sessionId] ?? state.project
            )
        }

        var statuses: [String: SessionStatus] = [:]
        for session in displayed {
            statuses[session.id] = session.status
            if hasLoaded, lastStatuses[session.id] != session.status {
                onTransition?(SessionTransition(sessionId: session.id, from: lastStatuses[session.id], to: session.status))
            }
        }
        lastStatuses = statuses
        hasLoaded = true
        acknowledged.prune(keeping: Set(statuses.keys))
        if displayed != sessions { sessions = displayed }
    }

    /// The user opened this session from the widget.
    func acknowledge(_ session: DisplayedSession) {
        acknowledged.set(session.state.lastEvent, for: session.id)
        reload()
    }
}
```

- [ ] **Step 4: Run the tests**

Run: `make test`
Expected: all pass.

- [ ] **Step 5: Checkpoint**

`make test` passes.

---

### Task 9: Glass tokens, the widget panel and the lamp column

**Files:**
- Create: `Tidewatch/UI/Glass/Color+Hex.swift`, `Tidewatch/UI/Glass/GlassTokens.swift`, `Tidewatch/UI/Glass/WidgetGlass.swift`, `Tidewatch/UI/Glass/GlassContainer.swift`, `Tidewatch/UI/Widget/WidgetMetrics.swift`, `Tidewatch/UI/Widget/WidgetModel.swift`, `Tidewatch/UI/Widget/WidgetActions.swift`, `Tidewatch/UI/Widget/StatusPalette.swift`, `Tidewatch/UI/Widget/StatusLamp.swift`, `Tidewatch/UI/Widget/LampColumn.swift`, `Tidewatch/UI/Widget/WidgetPanel.swift`, `Tidewatch/UI/Widget/WidgetPanelController.swift`, `Tidewatch/UI/Widget/WidgetRootView.swift`
- Test: `TidewatchTests/WidgetMetricsTests.swift`

**Interfaces:**
- Consumes: `SessionStore`, `DisplayedSession` (Task 8); `SessionStatus` (Core).
- Produces:
  - `struct WidgetMetrics: Equatable, Sendable` (statics listed in the code; `init(sessionCount:)`, `columnRect`, `panelRect`, `visibleLamps`, `hasOverflow`, `visibleRows`, `lampCenter(_:)`, `lampIndex(at:)`, `rowRect(_:)`, `rowIndex(at:)`, `hoverRect(expanded:)`, `static canvasOrigin(in:)`).
  - `@MainActor @Observable final class WidgetModel { var isExpanded; var isExpansionPinned; var hoveredIndex: Int? }`.
  - `struct WidgetActions { open, showInFinder, connect }` (+ `@MainActor static var preview`).
  - `@MainActor final class WidgetPanelController` with `init(store:settings:actions:)`, `show(pinnedExpanded:)`, `collapse()`, `windowNumber: Int`, `frame: NSRect`.
  - `GlassColor.attention`, `GlassColor.idleLamp`, `GlassColor.vscode`, `GlassFont`, `GlassMotion`, `GlassTokens`, `.widgetGlass(_:in:namespace:)`, `GlassContainer`.
  - `WidgetRootView` takes `settings: AppSettings`, so this task also creates the minimal `Tidewatch/App/AppSettings.swift` (it is used again in Task 11).

- [ ] **Step 1: Write the failing metrics test**

`TidewatchTests/WidgetMetricsTests.swift`:

```swift
import CoreGraphics
import Testing
@testable import Tidewatch

struct WidgetMetricsTests {
    @Test func columnHugsTheRightEdgeAndIsCentred() {
        let m = WidgetMetrics(sessionCount: 5)
        #expect(m.columnRect.maxX == WidgetMetrics.canvas.width - WidgetMetrics.edgeGap)
        #expect(m.columnRect.width == WidgetMetrics.columnWidth)
        #expect(abs(m.columnRect.midY - WidgetMetrics.canvas.height / 2) <= 1)
        #expect(m.columnRect.height == 5 * WidgetMetrics.lampPitch + 2 * WidgetMetrics.columnPadding)
    }

    @Test func emptyShowsOneLampAndOverflowAddsTheChevron() {
        #expect(WidgetMetrics(sessionCount: 0).visibleLamps == 1)
        let many = WidgetMetrics(sessionCount: 9)
        #expect(many.visibleLamps == WidgetMetrics.maxLamps)
        #expect(many.hasOverflow)
        #expect(many.columnRect.height == CGFloat(WidgetMetrics.maxLamps) * WidgetMetrics.lampPitch + 2 * WidgetMetrics.columnPadding + WidgetMetrics.chevronHeight)
    }

    @Test func lampHitTestingMatchesLampCentres() {
        let m = WidgetMetrics(sessionCount: 4)
        for index in 0..<4 {
            #expect(m.lampIndex(at: m.lampCenter(index)) == index)
        }
        #expect(m.lampIndex(at: CGPoint(x: 0, y: 0)) == nil)
        #expect(WidgetMetrics(sessionCount: 0).lampIndex(at: WidgetMetrics(sessionCount: 0).lampCenter(0)) == nil)
    }

    @Test func panelSitsLeftOfTheColumnAndRowsHitTest() {
        let m = WidgetMetrics(sessionCount: 3)
        #expect(m.panelRect.maxX == m.columnRect.minX - WidgetMetrics.panelGap)
        #expect(m.panelRect.width == WidgetMetrics.panelWidth)
        #expect(m.panelRect.height == WidgetMetrics.headerHeight + 3 * WidgetMetrics.rowHeight + WidgetMetrics.panelBottomPadding)
        #expect(m.panelRect.minX >= 0)
        for index in 0..<3 {
            let rect = m.rowRect(index)
            #expect(m.rowIndex(at: CGPoint(x: rect.midX, y: rect.midY)) == index)
        }
        #expect(m.rowIndex(at: CGPoint(x: m.panelRect.midX, y: m.panelRect.maxY - 5)) == nil)
    }

    @Test func scrollingListHasNoRowHitTesting() {
        let m = WidgetMetrics(sessionCount: WidgetMetrics.maxVisibleRows + 1)
        let rect = m.rowRect(0)
        #expect(m.rowIndex(at: CGPoint(x: rect.midX, y: rect.midY)) == nil)
        #expect(m.panelRect.maxY <= WidgetMetrics.canvas.height)
    }

    @Test func hoverAreaGrowsWhenExpanded() {
        let m = WidgetMetrics(sessionCount: 2)
        #expect(m.hoverRect(expanded: false).contains(m.lampCenter(0)))
        #expect(!m.hoverRect(expanded: false).contains(CGPoint(x: m.panelRect.midX, y: m.panelRect.midY)))
        #expect(m.hoverRect(expanded: true).contains(CGPoint(x: m.panelRect.midX, y: m.panelRect.midY)))
        // The gap between panel and column keeps the panel open.
        #expect(m.hoverRect(expanded: true).contains(CGPoint(x: m.panelRect.maxX + WidgetMetrics.panelGap / 2, y: m.columnRect.midY)))
    }

    @Test func canvasIsGluedToTheRightOfTheVisibleFrame() {
        let frame = CGRect(x: 0, y: 0, width: 1728, height: 1080)
        let origin = WidgetMetrics.canvasOrigin(in: frame)
        #expect(origin.x == 1728 - WidgetMetrics.canvas.width)
        #expect(origin.y == (540 - WidgetMetrics.canvas.height / 2).rounded())
    }
}
```

- [ ] **Step 2: Run to see it fail**

Run: `make test`
Expected: build fails (`WidgetMetrics` not found).

- [ ] **Step 3: Glass tokens (trimmed copy of Captylo's)**

`Tidewatch/UI/Glass/Color+Hex.swift`:

```swift
import SwiftUI

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}

/// Deep Tide brand colours (Captylo's `VTColor`, the ones Tidewatch uses).
enum BrandColor {
    static let abyss = Color(hex: 0x10272C)
    static let petrol = Color(hex: 0x214A52)
    static let tide = Color(hex: 0x2F8F88)
}
```

`Tidewatch/UI/Glass/GlassTokens.swift`:

```swift
import SwiftUI

// Dusk Glass tokens, trimmed from Captylo's GlassTokens.swift (<captylo-repo>,
// docs/design/dusk-glass.md). Views never hard-code radii, opacities, colours or fonts.

enum GlassTokens {
    enum Radius {
        static let panel: CGFloat = 28
        static let row: CGFloat = 12
    }

    enum Size {
        static let rimWidth: CGFloat = 1
    }

    enum Opacity {
        /// White fill over the material on the macOS 14/15 path.
        static let fallbackFill: Double = 0.12
        /// Badge and button fills inside the panel.
        static let control: Double = 0.14
        /// Hovered row.
        static let rowHover: Double = 0.08
        static let shadow: Double = 0.28
    }

    enum Shadow {
        static let panelRadius: CGFloat = 30
        static let panelY: CGFloat = 14
    }

    /// The widget's glass, tuned against docs/design mockups (dark smoked glass, white type).
    enum Widget {
        /// White wash inside the glass.
        static let wash: Double = 0.06
        /// Abyss smoke inside the glass.
        static let smoke: Double = 0.35
        /// Tint of macOS 26 regular glass.
        static let tint: Double = 0.10
    }

    /// `TIDEWATCH_GLASS_FALLBACK=1` draws the macOS 14/15 material path on macOS 26 (to check it).
    static let forcesFallback: Bool = ProcessInfo.processInfo.environment["TIDEWATCH_GLASS_FALLBACK"] == "1"
}

enum GlassColor {
    static let textPrimary = Color.white.opacity(0.95)
    static let textSecondary = Color.white.opacity(0.70)
    static let textTertiary = Color.white.opacity(0.50)
    static let separator = Color.white.opacity(0.12)
    /// Working lamp (Captylo's success green).
    static let success = Color(hex: 0x4CD68A)
    /// Needs approval / awaiting review lamp and text (new in Tidewatch, the mockups' orange).
    static let attention = Color(hex: 0xFF9F43)
    static let idleLamp = Color.white.opacity(0.35)
    /// The VS Code glyph in the rows.
    static let vscode = Color(hex: 0x3BA0F0)
    /// Reduce Transparency fill.
    static let solidPanel = Color(hex: 0x1C3A40)

    /// Rim stroke: luminous top edge fading toward the bottom.
    static func rim(top: Double = 0.62, bottom: Double = 0.14) -> LinearGradient {
        LinearGradient(
            colors: [Color.white.opacity(top), Color.white.opacity(bottom), Color.white.opacity(bottom * 1.6)],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}

/// Manrope for titles and numbers, Inter for UI (bundled, SIL OFL, `ATSApplicationFontsPath`).
enum GlassFont {
    enum Face: String {
        case manropeSemiBold = "Manrope-SemiBold"
        case manropeBold = "Manrope-Bold"
        case interRegular = "Inter-Regular"
        case interMedium = "Inter-Medium"
        case interSemiBold = "Inter-SemiBold"
    }

    static func face(_ face: Face, _ size: CGFloat) -> Font {
        .custom(face.rawValue, fixedSize: size)
    }

    static var sectionTitle: Font { face(.manropeSemiBold, 15) }
    static var rowTitle: Font { face(.interMedium, 14) }
    static var rowSubtitle: Font { face(.interRegular, 12) }
    static var rowValue: Font { face(.interRegular, 13).monospacedDigit() }
    static var badge: Font { face(.interSemiBold, 11).monospacedDigit() }
    static var button: Font { face(.interSemiBold, 13) }
}

enum GlassMotion {
    static var spring: Animation { .spring(response: 0.38, dampingFraction: 0.85) }
    static var reduced: Animation { .easeInOut(duration: 0.18) }
}
```

`Tidewatch/UI/Glass/WidgetGlass.swift`:

```swift
import SwiftUI

/// The widget's glass (column and panel), from Captylo's RecorderGlass + GlassSurface, trimmed.
/// macOS 26: regular Liquid Glass with a light tint and `glassEffectID`, so the column and the
/// panel morph inside `GlassContainer`. macOS 14/15: material + white fill + smoke + rim.
/// Reduce Transparency: solid fill with the same rim.
@MainActor
struct WidgetGlass<S: InsettableShape>: ViewModifier {
    let shape: S
    let id: String
    let namespace: Namespace.ID
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        if reduceTransparency {
            content
                .background { shape.fill(GlassColor.solidPanel) }
                .overlay { rim }
        } else if #available(macOS 26.0, *), !GlassTokens.forcesFallback {
            content
                .clipShape(shape)
                .background {
                    shape.fill(BrandColor.abyss.opacity(GlassTokens.Widget.smoke))
                        .overlay { shape.fill(Color.white.opacity(GlassTokens.Widget.wash)) }
                        .allowsHitTesting(false)
                }
                .glassEffect(Glass.regular.tint(Color.white.opacity(GlassTokens.Widget.tint)), in: shape)
                .glassEffectID(id, in: namespace)
                .overlay { rim }
        } else {
            content
                .background {
                    shape.fill(.ultraThinMaterial)
                        .overlay { shape.fill(Color.white.opacity(GlassTokens.Opacity.fallbackFill)) }
                        .overlay { shape.fill(BrandColor.abyss.opacity(GlassTokens.Widget.smoke)) }
                        .shadow(color: .black.opacity(GlassTokens.Opacity.shadow), radius: GlassTokens.Shadow.panelRadius, y: GlassTokens.Shadow.panelY)
                }
                .overlay { rim }
        }
    }

    private var rim: some View {
        shape
            .strokeBorder(GlassColor.rim(top: 0.6, bottom: 0.2), lineWidth: GlassTokens.Size.rimWidth)
            .allowsHitTesting(false)
    }
}

extension View {
    func widgetGlass<S: InsettableShape>(_ id: String, in shape: S, namespace: Namespace.ID) -> some View {
        modifier(WidgetGlass(shape: shape, id: id, namespace: namespace))
    }
}
```

`Tidewatch/UI/Glass/GlassContainer.swift`:

```swift
import SwiftUI

/// `GlassEffectContainer` on macOS 26 (glass shapes morph into each other), plain content below.
struct GlassContainer<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        if #available(macOS 26.0, *), !GlassTokens.forcesFallback {
            GlassEffectContainer(spacing: 2) { content }
        } else {
            content
        }
    }
}
```

- [ ] **Step 4: Metrics, model, actions, palette**

`Tidewatch/UI/Widget/WidgetMetrics.swift`:

```swift
import CoreGraphics

/// Geometry of the widget canvas in points, origin bottom left (AppKit). The SwiftUI layout and
/// the hover hit tests both read it, so they always agree.
struct WidgetMetrics: Equatable, Sendable {
    static let canvas = CGSize(width: 340, height: 600)
    static let edgeGap: CGFloat = 8
    static let columnWidth: CGFloat = 36
    static let columnPadding: CGFloat = 9
    static let lampPitch: CGFloat = 22
    static let lampSize: CGFloat = 10
    static let chevronHeight: CGFloat = 16
    static let maxLamps = 6
    static let panelGap: CGFloat = 10
    static let panelWidth: CGFloat = 280
    static let headerHeight: CGFloat = 52
    static let rowHeight: CGFloat = 50
    static let panelBottomPadding: CGFloat = 8
    static let maxVisibleRows = 8
    static let emptyStateHeight: CGFloat = 96
    static let hoverSlop: CGFloat = 8
    static let expandDelay: Duration = .milliseconds(280)
    static let collapseDelay: Duration = .milliseconds(450)
    static let pointerPoll: Duration = .milliseconds(150)

    let sessionCount: Int

    /// No sessions still shows one dim lamp.
    var visibleLamps: Int { min(max(sessionCount, 1), Self.maxLamps) }
    var hasOverflow: Bool { sessionCount > Self.maxLamps }
    var visibleRows: Int { min(sessionCount, Self.maxVisibleRows) }

    var columnRect: CGRect {
        let height = CGFloat(visibleLamps) * Self.lampPitch + 2 * Self.columnPadding + (hasOverflow ? Self.chevronHeight : 0)
        return CGRect(
            x: Self.canvas.width - Self.edgeGap - Self.columnWidth,
            y: ((Self.canvas.height - height) / 2).rounded(),
            width: Self.columnWidth,
            height: height
        )
    }

    var panelRect: CGRect {
        let body = sessionCount == 0 ? Self.emptyStateHeight : CGFloat(visibleRows) * Self.rowHeight
        let height = Self.headerHeight + body + Self.panelBottomPadding
        return CGRect(
            x: columnRect.minX - Self.panelGap - Self.panelWidth,
            y: ((Self.canvas.height - height) / 2).rounded(),
            width: Self.panelWidth,
            height: height
        )
    }

    func lampCenter(_ index: Int) -> CGPoint {
        let top = columnRect.maxY - Self.columnPadding
        return CGPoint(x: columnRect.midX, y: top - (CGFloat(index) + 0.5) * Self.lampPitch)
    }

    func lampIndex(at point: CGPoint) -> Int? {
        guard sessionCount > 0, columnRect.contains(point) else { return nil }
        let top = columnRect.maxY - Self.columnPadding
        let index = Int(((top - point.y) / Self.lampPitch).rounded(.down))
        return (0..<min(sessionCount, Self.maxLamps)).contains(index) ? index : nil
    }

    func rowRect(_ index: Int) -> CGRect {
        let top = panelRect.maxY - Self.headerHeight
        return CGRect(x: panelRect.minX, y: top - CGFloat(index + 1) * Self.rowHeight, width: panelRect.width, height: Self.rowHeight)
    }

    /// Row under the point; nil when the list scrolls (rows no longer sit at fixed places).
    func rowIndex(at point: CGPoint) -> Int? {
        guard sessionCount <= Self.maxVisibleRows else { return nil }
        return (0..<sessionCount).first { rowRect($0).contains(point) }
    }

    /// While expanded, the bounding box of column + panel, so crossing the gap keeps it open.
    func hoverRect(expanded: Bool) -> CGRect {
        let base = expanded ? columnRect.union(panelRect) : columnRect
        return base.insetBy(dx: -Self.hoverSlop, dy: -Self.hoverSlop)
    }

    /// Canvas origin: glued to the right edge of the visible frame, centred vertically.
    static func canvasOrigin(in visibleFrame: CGRect) -> CGPoint {
        CGPoint(x: visibleFrame.maxX - canvas.width, y: (visibleFrame.midY - canvas.height / 2).rounded())
    }
}
```

`Tidewatch/UI/Widget/WidgetModel.swift`:

```swift
import Observation

@MainActor
@Observable
final class WidgetModel {
    var isExpanded = false
    /// Design preview: stays expanded, hover is ignored.
    var isExpansionPinned = false
    /// Lamp or row under the pointer (the same index in both).
    var hoveredIndex: Int?
}
```

`Tidewatch/UI/Widget/WidgetActions.swift`:

```swift
/// What the widget can ask the app to do.
struct WidgetActions {
    var open: @MainActor (DisplayedSession) -> Void
    var showInFinder: @MainActor (DisplayedSession) -> Void
    var connect: @MainActor () -> Void

    @MainActor static var preview: WidgetActions {
        WidgetActions(open: { _ in }, showInFinder: { _ in }, connect: {})
    }
}
```

`Tidewatch/UI/Widget/StatusPalette.swift`:

```swift
import SwiftUI
import TidewatchCore

enum StatusPalette {
    /// nil = the dim lamp shown when there are no sessions.
    static func lamp(_ status: SessionStatus?) -> Color {
        switch status {
        case .working: return GlassColor.success
        case .needsApproval, .awaitingReview: return GlassColor.attention
        case .idle: return GlassColor.idleLamp
        case nil: return GlassColor.idleLamp.opacity(0.6)
        }
    }

    static func text(_ status: SessionStatus) -> Color {
        switch status {
        case .needsApproval: return GlassColor.attention
        case .idle: return GlassColor.textTertiary
        case .working, .awaitingReview: return GlassColor.textSecondary
        }
    }

    static func glows(_ status: SessionStatus?) -> Bool {
        status == .working || status == .needsApproval || status == .awaitingReview
    }
}
```

- [ ] **Step 5: Lamps and column**

`Tidewatch/UI/Widget/StatusLamp.swift`:

```swift
import SwiftUI
import TidewatchCore

/// One glass status lamp. Working lamps pulse softly (off with Reduce Motion).
@MainActor
struct StatusLamp: View {
    let status: SessionStatus?
    var highlighted = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let color = StatusPalette.lamp(status)
        Circle()
            .fill(color)
            .frame(width: WidgetMetrics.lampSize, height: WidgetMetrics.lampSize)
            .overlay { Circle().strokeBorder(Color.white.opacity(0.35), lineWidth: 0.5) }
            .shadow(color: StatusPalette.glows(status) ? color.opacity(0.75) : .clear, radius: highlighted ? 6 : 4)
            .background {
                if status == .working, !reduceMotion {
                    PhaseAnimator([false, true]) { grown in
                        Circle()
                            .fill(color.opacity(grown ? 0 : 0.45))
                            .frame(width: WidgetMetrics.lampSize, height: WidgetMetrics.lampSize)
                            .scaleEffect(grown ? 2.2 : 1)
                    } animation: { grown in
                        grown ? .easeOut(duration: 1.8) : nil
                    }
                }
            }
            .scaleEffect(highlighted ? 1.25 : 1)
            .animation(reduceMotion ? nil : GlassMotion.spring, value: highlighted)
    }
}
```

`Tidewatch/UI/Widget/LampColumn.swift`:

```swift
import SwiftUI

@MainActor
struct LampColumn: View {
    let sessions: [DisplayedSession]
    let hoveredIndex: Int?
    let metrics: WidgetMetrics

    var body: some View {
        VStack(spacing: 0) {
            if sessions.isEmpty {
                StatusLamp(status: nil)
                    .frame(height: WidgetMetrics.lampPitch)
            } else {
                ForEach(Array(sessions.prefix(WidgetMetrics.maxLamps).enumerated()), id: \.element.id) { index, session in
                    StatusLamp(status: session.status, highlighted: hoveredIndex == index)
                        .frame(height: WidgetMetrics.lampPitch)
                }
            }
            if metrics.hasOverflow {
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(GlassColor.textSecondary)
                    .frame(height: WidgetMetrics.chevronHeight)
            }
        }
        .padding(.vertical, WidgetMetrics.columnPadding)
        .frame(width: WidgetMetrics.columnWidth)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(sessions.count == 1 ? "1 Claude Code session" : "\(sessions.count) Claude Code sessions")
    }
}
```

- [ ] **Step 6: Panel, root view, controller**

`Tidewatch/App/AppSettings.swift` (needed by the root view; Task 11 uses it as is):

```swift
import Foundation
import Observation

@MainActor
@Observable
final class AppSettings {
    private enum Keys {
        static let sounds = "sounds.enabled"
        static let connected = "hooks.connected"
    }

    @ObservationIgnored private let defaults: UserDefaults

    var soundsEnabled: Bool {
        didSet { defaults.set(soundsEnabled, forKey: Keys.sounds) }
    }

    /// The user connected Tidewatch to Claude Code at least once (repair on launch).
    var hooksConnected: Bool {
        didSet { defaults.set(hooksConnected, forKey: Keys.connected) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        soundsEnabled = defaults.object(forKey: Keys.sounds) as? Bool ?? true
        hooksConnected = defaults.bool(forKey: Keys.connected)
    }
}
```

`Tidewatch/UI/Widget/WidgetPanel.swift`:

```swift
import AppKit
import SwiftUI

/// Borderless, non-activating floating panel that never becomes key or main (Captylo's
/// RecorderPanel). Transparent canvas pixels let clicks through to the windows below.
final class WidgetPanel: NSPanel {
    init() {
        super.init(
            contentRect: NSRect(origin: .zero, size: WidgetMetrics.canvas),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        hidesOnDeactivate = false
        canHide = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        animationBehavior = .utilityWindow
        isMovable = false
        isMovableByWindowBackground = false
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isReleasedWhenClosed = false
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Hosting view with a tracking area that works while the app is inactive, and first-click
/// support so rows react without activating Tidewatch.
final class WidgetHostingView: NSHostingView<WidgetRootView> {
    var onPointer: (@MainActor () -> Void)?
    private var hoverArea: NSTrackingArea?

    required init(rootView: WidgetRootView) {
        super.init(rootView: rootView)
        sizingOptions = []
        wantsLayer = true
        layer?.backgroundColor = .clear
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverArea { removeTrackingArea(hoverArea) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(area)
        hoverArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        onPointer?()
    }

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        onPointer?()
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        onPointer?()
    }
}
```

`Tidewatch/UI/Widget/WidgetRootView.swift`:

```swift
import SwiftUI

/// The whole canvas: the lamp column and, while expanded, the session panel, both placed from
/// `WidgetMetrics` (top-left SwiftUI coordinates = canvas height - AppKit y).
@MainActor
struct WidgetRootView: View {
    let store: SessionStore
    let model: WidgetModel
    let settings: AppSettings
    let actions: WidgetActions
    @Namespace private var glass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let metrics = WidgetMetrics(sessionCount: store.sessions.count)
        let height = WidgetMetrics.canvas.height
        GlassContainer {
            ZStack(alignment: .topLeading) {
                Color.clear
                if model.isExpanded {
                    SessionPanelView(sessions: store.sessions, hoveredIndex: model.hoveredIndex, isConnected: settings.hooksConnected, actions: actions)
                        .frame(width: metrics.panelRect.width, height: metrics.panelRect.height)
                        .widgetGlass("panel", in: RoundedRectangle(cornerRadius: GlassTokens.Radius.panel, style: .continuous), namespace: glass)
                        .position(x: metrics.panelRect.midX, y: height - metrics.panelRect.midY)
                        .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.94, anchor: .trailing)))
                }
                LampColumn(sessions: store.sessions, hoveredIndex: model.hoveredIndex, metrics: metrics)
                    .frame(width: metrics.columnRect.width, height: metrics.columnRect.height)
                    .widgetGlass("column", in: Capsule(style: .continuous), namespace: glass)
                    .position(x: metrics.columnRect.midX, y: height - metrics.columnRect.midY)
            }
            .frame(width: WidgetMetrics.canvas.width, height: height)
        }
        .environment(\.appearsActive, true)
        .environment(\.controlActiveState, .key)
        .preferredColorScheme(.dark)
        .ignoresSafeArea()
    }
}
```

`SessionPanelView` comes in Task 10. To keep this task building, create `Tidewatch/UI/Widget/SessionPanelView.swift` now with a placeholder body that Task 10 replaces:

```swift
import SwiftUI

@MainActor
struct SessionPanelView: View {
    let sessions: [DisplayedSession]
    let hoveredIndex: Int?
    let isConnected: Bool
    let actions: WidgetActions

    var body: some View {
        // Replaced in Task 10.
        Color.clear
    }
}
```

`Tidewatch/UI/Widget/WidgetPanelController.swift`:

```swift
import AppKit
import SwiftUI

/// Owns the widget panel: glues it to the right edge of the menu bar screen, expands it on hover
/// (Captylo's dwell and grace delays) and tracks which lamp or row is under the pointer. Never
/// activates the app.
@MainActor
final class WidgetPanelController {
    let model: WidgetModel
    private let store: SessionStore
    private let panel = WidgetPanel()
    private let hostingView: WidgetHostingView
    private var pointerTask: Task<Void, Never>?
    private var hoverTask: Task<Void, Never>?
    private var hoverTarget: Bool?
    private var screenObserver: NSObjectProtocol?

    var windowNumber: Int { panel.windowNumber }
    var frame: NSRect { panel.frame }

    init(store: SessionStore, settings: AppSettings, actions: WidgetActions, model: WidgetModel = WidgetModel()) {
        self.store = store
        self.model = model
        hostingView = WidgetHostingView(rootView: WidgetRootView(store: store, model: model, settings: settings, actions: actions))
        panel.contentView = hostingView
        hostingView.onPointer = { [weak self] in self?.evaluatePointer() }
    }

    func show(pinnedExpanded: Bool = false) {
        model.isExpansionPinned = pinnedExpanded
        model.isExpanded = pinnedExpanded
        reposition()
        panel.orderFrontRegardless()
        screenObserver = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.reposition() }
        }
        startPointerWatch()
        Log.ui.debug("widget shown")
    }

    /// Closes the panel at once (after a click on a row).
    func collapse() {
        guard !model.isExpansionPinned else { return }
        hoverTask?.cancel()
        hoverTask = nil
        hoverTarget = nil
        setExpanded(false)
    }

    private func reposition() {
        guard let screen = NSScreen.screens.first else { return }
        panel.setFrameOrigin(WidgetMetrics.canvasOrigin(in: screen.visibleFrame))
    }

    // MARK: Pointer

    /// The tracking area answers at once; the 150 ms poll covers what it cannot see (the pointer
    /// resting over transparent canvas pixels, which belong to the window below).
    private func startPointerWatch() {
        pointerTask?.cancel()
        pointerTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: WidgetMetrics.pointerPoll)
                self?.evaluatePointer()
            }
        }
    }

    private func evaluatePointer() {
        let metrics = WidgetMetrics(sessionCount: store.sessions.count)
        let point = canvasPoint(NSEvent.mouseLocation)
        let hovered = metrics.lampIndex(at: point) ?? (model.isExpanded ? metrics.rowIndex(at: point) : nil)
        if hovered != model.hoveredIndex { model.hoveredIndex = hovered }

        guard !model.isExpansionPinned else { return }
        let wanted = metrics.hoverRect(expanded: model.isExpanded).contains(point)
        guard wanted != model.isExpanded else {
            hoverTask?.cancel()
            hoverTask = nil
            hoverTarget = nil
            return
        }
        guard hoverTarget != wanted else { return }
        hoverTarget = wanted
        hoverTask?.cancel()
        let delay = wanted ? WidgetMetrics.expandDelay : WidgetMetrics.collapseDelay
        hoverTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self else { return }
            self.hoverTask = nil
            self.hoverTarget = nil
            let metrics = WidgetMetrics(sessionCount: self.store.sessions.count)
            guard metrics.hoverRect(expanded: self.model.isExpanded).contains(self.canvasPoint(NSEvent.mouseLocation)) == wanted else { return }
            self.setExpanded(wanted)
        }
    }

    private func setExpanded(_ expanded: Bool) {
        guard model.isExpanded != expanded else { return }
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        withAnimation(reduceMotion ? GlassMotion.reduced : GlassMotion.spring) {
            model.isExpanded = expanded
        }
    }

    /// Screen point to canvas coordinates (origin bottom left).
    private func canvasPoint(_ screenPoint: NSPoint) -> CGPoint {
        CGPoint(x: screenPoint.x - panel.frame.minX, y: screenPoint.y - panel.frame.minY)
    }
}
```

- [ ] **Step 7: Run tests and build**

Run: `make test`
Expected: all pass, including `WidgetMetricsTests`.

- [ ] **Step 8: Checkpoint**

`make build` and `make test` pass. The widget is not shown yet (wired in Task 11).

---

### Task 10: Session panel, rows, empty state and opening sessions

**Files:**
- Create: `Tidewatch/UI/Widget/SessionRow.swift`, `Tidewatch/UI/Widget/EmptyStateView.swift`, `Tidewatch/Integration/SessionOpener.swift`
- Modify: `Tidewatch/UI/Widget/SessionPanelView.swift` (replace the placeholder)
- Test: `TidewatchTests/SessionOpenerTests.swift`

**Interfaces:**
- Consumes: `DisplayedSession`, `WidgetActions`, `WidgetMetrics`, `StatusLamp`, `StatusPalette`, glass tokens (Task 9); `DisplayRules` (Core).
- Produces: `SessionOpener.open(_ state: SessionState)`, `SessionOpener.showInFinder(_ state: SessionState)`, `SessionOpener.sessionURL(_ sessionId: String) -> URL?`, `SessionOpener.terminalBundleId(_ termProgram: String?) -> String?`, `SessionOpener.vscodeBundleId`, `SessionOpener.uriDelay: Duration`.

- [ ] **Step 1: Write the failing opener test**

`TidewatchTests/SessionOpenerTests.swift`:

```swift
import Testing
@testable import Tidewatch

@MainActor
struct SessionOpenerTests {
    @Test func buildsTheClaudeExtensionSessionURL() {
        #expect(SessionOpener.sessionURL("2c7f6edd-2153-4800-a181-b41e70f4f557")?.absoluteString == "vscode://anthropic.claude-code/open?session=2c7f6edd-2153-4800-a181-b41e70f4f557")
    }

    @Test func mapsTerminalPrograms() {
        #expect(SessionOpener.terminalBundleId("Apple_Terminal") == "com.apple.Terminal")
        #expect(SessionOpener.terminalBundleId("iTerm.app") == "com.googlecode.iterm2")
        #expect(SessionOpener.terminalBundleId("ghostty") == "com.mitchellh.ghostty")
        #expect(SessionOpener.terminalBundleId("WarpTerminal") == "dev.warp.Warp-Stable")
        #expect(SessionOpener.terminalBundleId(nil) == nil)
        #expect(SessionOpener.terminalBundleId("unknown") == nil)
    }

    @Test func waitsBeforeTheSessionURL() {
        #expect(SessionOpener.uriDelay == .milliseconds(400))
        #expect(SessionOpener.vscodeBundleId == "com.microsoft.VSCode")
    }
}
```

- [ ] **Step 2: Run to see it fail**

Run: `make test`
Expected: build fails (`SessionOpener` not found).

- [ ] **Step 3: Implement the opener**

`Tidewatch/Integration/SessionOpener.swift`:

```swift
import AppKit
import TidewatchCore

/// Brings a session to the front (spec 5.3, verified in the spike): open the project folder in
/// VS Code (focuses the window that has it), then the Claude extension's session URL (focuses
/// that session's tab). Terminal sessions activate their terminal app.
@MainActor
enum SessionOpener {
    static let vscodeBundleId = "com.microsoft.VSCode"
    static let uriDelay: Duration = .milliseconds(400)

    static func open(_ state: SessionState) {
        let folder = URL(fileURLWithPath: state.cwd, isDirectory: true)
        let workspace = NSWorkspace.shared
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true

        if state.host == .vscode, let vscode = workspace.urlForApplication(withBundleIdentifier: vscodeBundleId) {
            workspace.open([folder], withApplicationAt: vscode, configuration: configuration) { _, error in
                if let error { Log.ui.error("open folder in VS Code failed: \(error.localizedDescription, privacy: .public)") }
            }
            let sessionId = state.sessionId
            Task { @MainActor in
                try? await Task.sleep(for: uriDelay)
                if let url = sessionURL(sessionId) { workspace.open(url) }
            }
            return
        }
        if let bundleId = terminalBundleId(state.terminalApp), let app = workspace.urlForApplication(withBundleIdentifier: bundleId) {
            workspace.openApplication(at: app, configuration: configuration) { _, _ in }
            return
        }
        showInFinder(state)
    }

    static func showInFinder(_ state: SessionState) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: state.cwd, isDirectory: true)])
    }

    nonisolated static func sessionURL(_ sessionId: String) -> URL? {
        var components = URLComponents()
        components.scheme = "vscode"
        components.host = "anthropic.claude-code"
        components.path = "/open"
        components.queryItems = [URLQueryItem(name: "session", value: sessionId)]
        return components.url
    }

    nonisolated static func terminalBundleId(_ termProgram: String?) -> String? {
        switch termProgram {
        case "Apple_Terminal": return "com.apple.Terminal"
        case "iTerm.app": return "com.googlecode.iterm2"
        case "ghostty": return "com.mitchellh.ghostty"
        case "WarpTerminal": return "dev.warp.Warp-Stable"
        default: return nil
        }
    }
}
```

The test suite is `@MainActor` because the constants live on a `@MainActor` type.

- [ ] **Step 4: Panel, rows, empty state**

Replace `Tidewatch/UI/Widget/SessionPanelView.swift`:

```swift
import SwiftUI

/// The expanded panel (mockups: "AI Agents" + count, one row per session).
@MainActor
struct SessionPanelView: View {
    let sessions: [DisplayedSession]
    let hoveredIndex: Int?
    let isConnected: Bool
    let actions: WidgetActions

    var body: some View {
        VStack(spacing: 0) {
            header
                .frame(height: WidgetMetrics.headerHeight)
            if sessions.isEmpty {
                EmptyStateView(isConnected: isConnected, connect: actions.connect)
                    .frame(height: WidgetMetrics.emptyStateHeight)
            } else {
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    ScrollView(.vertical) {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(sessions.enumerated()), id: \.element.id) { index, session in
                                SessionRow(session: session, now: context.date, highlighted: hoveredIndex == index, actions: actions)
                                    .frame(height: WidgetMetrics.rowHeight)
                            }
                        }
                    }
                    .scrollDisabled(sessions.count <= WidgetMetrics.maxVisibleRows)
                    .scrollIndicators(.never)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.bottom, WidgetMetrics.panelBottomPadding)
    }

    private var header: some View {
        HStack {
            Text("AI Agents")
                .font(GlassFont.sectionTitle)
                .foregroundStyle(GlassColor.textPrimary)
            Spacer()
            Text("\(sessions.count)")
                .font(GlassFont.badge)
                .foregroundStyle(GlassColor.textPrimary)
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background { Capsule().fill(Color.white.opacity(GlassTokens.Opacity.control)) }
                .overlay { Capsule().strokeBorder(GlassColor.rim(top: 0.32, bottom: 0.06), lineWidth: GlassTokens.Size.rimWidth) }
        }
        .padding(.horizontal, 12)
    }
}
```

`Tidewatch/UI/Widget/SessionRow.swift`:

```swift
import SwiftUI
import TidewatchCore

@MainActor
struct SessionRow: View {
    let session: DisplayedSession
    let now: Date
    let highlighted: Bool
    let actions: WidgetActions

    var body: some View {
        let statusLine = DisplayRules.statusLine(session.state, status: session.status)
        Button {
            actions.open(session)
        } label: {
            HStack(spacing: 12) {
                StatusLamp(status: session.status)
                VStack(alignment: .leading, spacing: 2) {
                    Text(session.name)
                        .font(GlassFont.rowTitle)
                        .foregroundStyle(GlassColor.textPrimary)
                        .lineLimit(1)
                    Text(statusLine)
                        .font(GlassFont.rowSubtitle)
                        .foregroundStyle(StatusPalette.text(session.status))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                Spacer(minLength: 8)
                Text(DisplayRules.elapsed(since: session.state.statusSince, now: now))
                    .font(GlassFont.rowValue)
                    .foregroundStyle(GlassColor.textTertiary)
                Image(systemName: session.state.host == .vscode ? "chevron.left.forwardslash.chevron.right" : "terminal")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(session.state.host == .vscode ? GlassColor.vscode : GlassColor.textSecondary)
                    .frame(width: 18)
            }
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: GlassTokens.Radius.row, style: .continuous)
                    .fill(Color.white.opacity(highlighted ? GlassTokens.Opacity.rowHover : 0))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Show in Finder") { actions.showInFinder(session) }
        }
        .accessibilityLabel("\(session.name), \(statusLine)")
    }
}
```

`Tidewatch/UI/Widget/EmptyStateView.swift`:

```swift
import SwiftUI

@MainActor
struct EmptyStateView: View {
    let isConnected: Bool
    let connect: @MainActor () -> Void

    var body: some View {
        VStack(spacing: 8) {
            if isConnected {
                Text("No sessions yet")
                    .font(GlassFont.rowTitle)
                    .foregroundStyle(GlassColor.textSecondary)
                Text("Start Claude Code and it shows up here.")
                    .font(GlassFont.rowSubtitle)
                    .foregroundStyle(GlassColor.textTertiary)
            } else {
                Text("Not connected to Claude Code")
                    .font(GlassFont.rowTitle)
                    .foregroundStyle(GlassColor.textSecondary)
                Button("Connect to Claude Code") { connect() }
                    .buttonStyle(.plain)
                    .font(GlassFont.button)
                    .foregroundStyle(GlassColor.textPrimary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background { Capsule().fill(BrandColor.tide.opacity(0.85)) }
                    .overlay { Capsule().strokeBorder(GlassColor.rim(top: 0.4, bottom: 0.1), lineWidth: GlassTokens.Size.rimWidth) }
            }
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
```

- [ ] **Step 5: Run tests and build**

Run: `make test`
Expected: all pass.

- [ ] **Step 6: Checkpoint**

`make build` and `make test` pass.

---

### Task 11: Sounds, app wiring and the menu bar

**Files:**
- Create: `Tidewatch/Integration/SoundPlayer.swift`, `Tidewatch/Integration/LaunchAtLogin.swift`, `Tidewatch/App/AppState.swift`, `Tidewatch/UI/MenuBar/MenuBarContent.swift`
- Modify: `Tidewatch/App/AppDelegate.swift`, `Tidewatch/App/TidewatchApp.swift`
- Test: `TidewatchTests/SoundPlayerTests.swift`, `TidewatchTests/AppSettingsTests.swift`

**Interfaces:**
- Consumes: everything above. `DesignPreview.run(target:)` is created in Task 12; in this task `AppState.start()` handles `.designPreview` by logging and returning, and Task 12 replaces that one line.
- Produces: `SoundPlayer(clock:play:)`, `SoundPlayer.Cue { approval, done }`, `SoundPlayer.cue(for:) -> Cue?`, `handle(_:enabled:) -> Bool`; `LaunchAtLogin.isEnabled`, `LaunchAtLogin.set(_:) throws`; `AppState(mode:defaults:)` with `settings`, `store`, `hookError`, `launchAtLogin`, `start()`, `connectHooks()`, `disconnectHooks()`, `setLaunchAtLogin(_:)`.

- [ ] **Step 1: Write the failing tests**

`TidewatchTests/SoundPlayerTests.swift`:

```swift
import Foundation
import Testing
import TidewatchCore
@testable import Tidewatch

@MainActor
struct SoundPlayerTests {
    final class Recorder {
        var now = Date(timeIntervalSince1970: 1_791_620_000)
        var played: [SoundPlayer.Cue] = []
    }

    private func make(_ recorder: Recorder) -> SoundPlayer {
        SoundPlayer(clock: { recorder.now }, play: { recorder.played.append($0) })
    }

    private func transition(_ to: SessionStatus) -> SessionTransition {
        SessionTransition(sessionId: "a", from: .working, to: to)
    }

    @Test func mapsTransitionsToCues() {
        #expect(SoundPlayer.cue(for: transition(.needsApproval)) == .approval)
        #expect(SoundPlayer.cue(for: transition(.awaitingReview)) == .done)
        #expect(SoundPlayer.cue(for: transition(.working)) == nil)
        #expect(SoundPlayer.cue(for: transition(.idle)) == nil)
    }

    @Test func silentRightAfterLaunch() {
        let recorder = Recorder()
        let player = make(recorder)
        recorder.now = recorder.now.addingTimeInterval(1)
        #expect(!player.handle(transition(.needsApproval), enabled: true))
        recorder.now = recorder.now.addingTimeInterval(3)
        #expect(player.handle(transition(.needsApproval), enabled: true))
        #expect(recorder.played == [.approval])
    }

    @Test func atMostOneSoundEveryTwoSeconds() {
        let recorder = Recorder()
        let player = make(recorder)
        recorder.now = recorder.now.addingTimeInterval(10)
        #expect(player.handle(transition(.needsApproval), enabled: true))
        recorder.now = recorder.now.addingTimeInterval(1)
        #expect(!player.handle(transition(.awaitingReview), enabled: true))
        recorder.now = recorder.now.addingTimeInterval(1.5)
        #expect(player.handle(transition(.awaitingReview), enabled: true))
        #expect(recorder.played == [.approval, .done])
    }

    @Test func disabledPlaysNothing() {
        let recorder = Recorder()
        let player = make(recorder)
        recorder.now = recorder.now.addingTimeInterval(10)
        #expect(!player.handle(transition(.needsApproval), enabled: false))
        #expect(recorder.played.isEmpty)
    }
}
```

`TidewatchTests/AppSettingsTests.swift`:

```swift
import Foundation
import Testing
@testable import Tidewatch

@MainActor
struct AppSettingsTests {
    @Test func soundsDefaultOnAndPersist() {
        let defaults = UserDefaults(suiteName: "tw-settings-\(UUID().uuidString)")!
        let settings = AppSettings(defaults: defaults)
        #expect(settings.soundsEnabled)
        #expect(!settings.hooksConnected)
        settings.soundsEnabled = false
        settings.hooksConnected = true
        let reloaded = AppSettings(defaults: defaults)
        #expect(!reloaded.soundsEnabled)
        #expect(reloaded.hooksConnected)
    }
}
```

- [ ] **Step 2: Run to see them fail**

Run: `make test`
Expected: build fails (`SoundPlayer` not found).

- [ ] **Step 3: Implement sounds and login item**

`Tidewatch/Integration/SoundPlayer.swift`:

```swift
import AppKit

/// Plays a cue when a session starts waiting for approval or finishes its turn (spec 5.5):
/// silent for 3 s after launch, at most one sound per 2 s.
@MainActor
final class SoundPlayer {
    enum Cue: Equatable {
        case approval
        case done

        var soundName: String {
            switch self {
            case .approval: return "Glass"
            case .done: return "Tink"
            }
        }
    }

    static let minimumGap: TimeInterval = 2
    static let launchSilence: TimeInterval = 3

    private let clock: () -> Date
    private let play: (Cue) -> Void
    private let startedAt: Date
    private var lastPlayed: Date?

    init(clock: @escaping () -> Date = { Date() }, play: @escaping (Cue) -> Void = { NSSound(named: NSSound.Name($0.soundName))?.play() }) {
        self.clock = clock
        self.play = play
        startedAt = clock()
    }

    static func cue(for transition: SessionTransition) -> Cue? {
        switch transition.to {
        case .needsApproval: return .approval
        case .awaitingReview: return .done
        case .working, .idle: return nil
        }
    }

    @discardableResult
    func handle(_ transition: SessionTransition, enabled: Bool) -> Bool {
        guard enabled, let cue = Self.cue(for: transition) else { return false }
        let now = clock()
        guard now.timeIntervalSince(startedAt) >= Self.launchSilence else { return false }
        if let lastPlayed, now.timeIntervalSince(lastPlayed) < Self.minimumGap { return false }
        lastPlayed = now
        play(cue)
        return true
    }
}
```

`Tidewatch/Integration/LaunchAtLogin.swift`:

```swift
import ServiceManagement

enum LaunchAtLogin {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    static func set(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}
```

- [ ] **Step 4: AppState, delegate, menu bar**

`Tidewatch/App/AppState.swift`:

```swift
import AppKit
import Observation
import TidewatchCore

/// The running app: settings, the session store, the widget, hooks and sounds.
@MainActor
@Observable
final class AppState {
    let mode: LaunchMode
    let settings: AppSettings
    let store: SessionStore
    private(set) var hookError: String?
    private(set) var launchAtLogin = LaunchAtLogin.isEnabled
    @ObservationIgnored private var widget: WidgetPanelController?
    @ObservationIgnored private let sounds = SoundPlayer()
    @ObservationIgnored private let settingsURL = HookInstaller.defaultSettingsURL()
    @ObservationIgnored private let helperURL = DataPaths.helper()

    init(mode: LaunchMode, defaults: UserDefaults = .standard) {
        self.mode = mode
        settings = AppSettings(defaults: defaults)
        store = SessionStore(fileStore: SessionFileStore(directory: DataPaths.sessions()), acknowledged: AcknowledgedStore(defaults: defaults))
    }

    func start() {
        switch mode {
        case .tests:
            return
        case .designPreview(let target):
            Log.app.info("design preview \(target, privacy: .public) (Task 12)")
        case .normal:
            refreshHelper()
            repairHooksIfNeeded()
            store.onTransition = { [weak self] transition in
                guard let self else { return }
                self.sounds.handle(transition, enabled: self.settings.soundsEnabled)
            }
            store.start()
            let controller = WidgetPanelController(store: store, settings: settings, actions: actions)
            controller.show()
            widget = controller
        }
    }

    var actions: WidgetActions {
        WidgetActions(
            open: { [weak self] session in
                self?.store.acknowledge(session)
                self?.widget?.collapse()
                SessionOpener.open(session.state)
            },
            showInFinder: { session in
                SessionOpener.showInFinder(session.state)
            },
            connect: { [weak self] in
                self?.connectHooks()
            }
        )
    }

    // MARK: Hooks

    func connectHooks() {
        do {
            try HelperInstaller.refresh(from: HelperInstaller.bundledHelper(), to: helperURL)
            try HookInstaller.connect(settingsURL: settingsURL, helperPath: helperURL.path)
            settings.hooksConnected = true
            hookError = nil
            Log.hooks.info("connected")
        } catch {
            hookError = error.localizedDescription
            Log.hooks.error("connect failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func disconnectHooks() {
        do {
            try HookInstaller.disconnect(settingsURL: settingsURL)
            settings.hooksConnected = false
            hookError = nil
            Log.hooks.info("disconnected")
        } catch {
            hookError = error.localizedDescription
            Log.hooks.error("disconnect failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func refreshHelper() {
        do {
            try HelperInstaller.refresh(from: HelperInstaller.bundledHelper(), to: helperURL)
        } catch {
            Log.hooks.error("helper refresh failed: \(String(describing: error), privacy: .public)")
        }
    }

    /// Spec 6.1: after a move or an update, point the hooks at the current helper again.
    private func repairHooksIfNeeded() {
        guard settings.hooksConnected,
              let current = try? HookInstaller.readSettings(at: settingsURL),
              !HookInstaller.isInstalled(current, helperPath: helperURL.path) else { return }
        Log.hooks.info("repairing hook entries")
        connectHooks()
    }

    // MARK: Login item

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            try LaunchAtLogin.set(enabled)
        } catch {
            Log.app.error("launch at login failed: \(error.localizedDescription, privacy: .public)")
        }
        launchAtLogin = LaunchAtLogin.isEnabled
    }
}
```

Replace `Tidewatch/App/AppDelegate.swift`:

```swift
import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let state = AppState(mode: LaunchMode.current())

    func applicationDidFinishLaunching(_ notification: Notification) {
        state.start()
    }
}
```

`Tidewatch/UI/MenuBar/MenuBarContent.swift`:

```swift
import SwiftUI

@MainActor
struct MenuBarContent: View {
    let state: AppState

    var body: some View {
        if state.settings.hooksConnected {
            Text("Connected to Claude Code")
            Button("Disconnect") { state.disconnectHooks() }
        } else {
            Button("Connect to Claude Code") { state.connectHooks() }
        }
        if let error = state.hookError {
            Text(error)
        }
        Divider()
        Toggle("Sounds", isOn: Bindable(state.settings).soundsEnabled)
        Toggle("Launch at Login", isOn: Binding(get: { state.launchAtLogin }, set: { state.setLaunchAtLogin($0) }))
        Divider()
        Text("Tip: the first click asks VS Code to allow the Claude link once. Tick \"Do not ask me again\".")
        Divider()
        Button("Quit Tidewatch") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}
```

Replace `Tidewatch/App/TidewatchApp.swift`:

```swift
import SwiftUI

@main
struct TidewatchApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuBarContent(state: appDelegate.state)
        } label: {
            Image(systemName: "smallcircle.filled.circle")
        }
        .menuBarExtraStyle(.menu)
    }
}
```

- [ ] **Step 5: Run tests and build**

Run: `make test`
Expected: all pass.

- [ ] **Step 6: Smoke run against a temp data folder**

Run: `TIDEWATCH_DATA_DIR=$(mktemp -d) .local-build/Build/Products/Debug/Tidewatch.app/Contents/MacOS/Tidewatch & sleep 3; screencapture -x /tmp/tw-smoke.png; kill %1`
Expected: the screenshot shows one dim lamp in a glass capsule at the right edge of the main screen. (The menu bar item is there too; the real settings.json is not touched unless "Connect" is clicked.) Look at the screenshot with the Read tool.

- [ ] **Step 7: Checkpoint**

`make build` and `make test` pass.

---

### Task 12: Design preview and visual check against the mockups

**Files:**
- Create: `Tidewatch/UI/Preview/DesignPreview.swift`, `scripts/snap.sh`, `docs/design/backdrops/dusk.jpg` (copied)
- Modify: `Tidewatch/App/AppState.swift` (the `.designPreview` case)

**Interfaces:**
- Consumes: `SessionStore`, `SessionFileStore`, `WidgetPanelController`, `AppSettings`, `WidgetActions.preview`.
- Produces: `DesignPreview.Target` (`widget-collapsed`, `widget-expanded`, `widget-empty`, `widget-overflow`, `widget-disconnected`), `DesignPreview.run(target:)`, `DesignPreview.sessions(for:now:) -> [SessionState]`; `scripts/snap.sh <target> <out.png>`.

- [ ] **Step 1: Preview data and runner**

`Tidewatch/UI/Preview/DesignPreview.swift`:

```swift
import AppKit
import TidewatchCore

/// `--design-preview <target>`: the widget on invented sessions (the names from the mockups), in
/// a temp folder, with its own defaults. Never touches the real data folder or settings.json.
/// Prints `WINDOW_ID=` and `WINDOW_FRAME=x,y,w,h` (top-left screen coordinates) for snap.sh.
@MainActor
enum DesignPreview {
    enum Target: String, CaseIterable {
        case collapsed = "widget-collapsed"
        case expanded = "widget-expanded"
        case empty = "widget-empty"
        case overflow = "widget-overflow"
        case disconnected = "widget-disconnected"
    }

    private static var retained: [AnyObject] = []

    static func sessions(for target: Target, now: Date) -> [SessionState] {
        func make(_ order: Int, _ name: String, _ status: SessionStatus, _ activity: SessionActivity = .working, minutes: Double, tool: String? = nil, detail: String? = nil) -> SessionState {
            var state = SessionState(sessionId: "preview-\(order)", cwd: "/Users/demo/\(name)", host: .vscode, terminalApp: nil, pid: nil, now: now)
            state.status = status
            state.activity = activity
            state.tool = tool
            state.detail = detail
            state.statusSince = now.addingTimeInterval(-minutes * 60)
            state.lastEvent = now.addingTimeInterval(-min(minutes, 5) * 60)
            state.firstSeen = now.addingTimeInterval(-Double(100 - order) * 60)
            return state
        }
        let five = [
            make(1, "Captylo", .working, .coding, minutes: 2),
            make(2, "Zorko", .needsApproval, minutes: 5, tool: "Bash", detail: "npm install"),
            make(3, "Omnira", .working, .runningTests, minutes: 12),
            make(4, "Craftweb", .idle, minutes: 60),
            make(5, "Blog AI", .working, .researching, minutes: 3),
        ]
        switch target {
        case .collapsed, .expanded:
            return five
        case .empty, .disconnected:
            return []
        case .overflow:
            return five + [
                make(6, "Snapfeed", .awaitingReview, minutes: 1),
                make(7, "Atlas", .working, .readingCode, minutes: 4),
                make(8, "Harbor", .idle, minutes: 90),
                make(9, "Lumen", .working, .runningAgents, minutes: 7),
            ]
        }
    }

    static func run(target raw: String) {
        guard let target = Target(rawValue: raw) else {
            print("Unknown design preview target '\(raw)'. Targets: \(Target.allCases.map(\.rawValue).joined(separator: " "))")
            fflush(stdout)
            NSApp.terminate(nil)
            return
        }
        let now = Date()
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("tidewatch-preview-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let files = SessionFileStore(directory: folder)
        for state in sessions(for: target, now: now) {
            try? files.write(state, to: files.fileURL(for: state.sessionId))
        }
        let suite = "tidewatch-preview"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let store = SessionStore(fileStore: files, acknowledged: AcknowledgedStore(defaults: defaults), isAlive: { _ in true }, clock: { now })
        store.reload()
        let settings = AppSettings(defaults: defaults)
        settings.hooksConnected = target != .disconnected

        guard let screen = NSScreen.screens.first else { return }
        let origin = WidgetMetrics.canvasOrigin(in: screen.visibleFrame)
        let frame = NSRect(origin: origin, size: WidgetMetrics.canvas)
        if let path = ProcessInfo.processInfo.environment["TIDEWATCH_PREVIEW_BACKDROP"], let image = NSImage(contentsOfFile: path) {
            let backdrop = NSWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
            backdrop.level = .floating
            let view = NSImageView(image: image)
            view.imageScaling = .scaleAxesIndependently
            backdrop.contentView = view
            backdrop.orderFrontRegardless()
            retained.append(backdrop)
        }

        let controller = WidgetPanelController(store: store, settings: settings, actions: .preview)
        controller.show(pinnedExpanded: target != .collapsed)
        retained.append(contentsOf: [store, controller, settings])

        let shown = controller.frame
        print("WINDOW_ID=\(controller.windowNumber)")
        print("WINDOW_FRAME=\(Int(shown.minX)),\(Int(screen.frame.height - shown.maxY)),\(Int(shown.width)),\(Int(shown.height))")
        fflush(stdout)
    }
}
```

In `AppState.start()`, replace the `.designPreview` line with:

```swift
        case .designPreview(let target):
            DesignPreview.run(target: target)
```

- [ ] **Step 2: snap.sh and the backdrop**

Run: `mkdir -p docs/design/backdrops && cp <captylo-repo>/docs/design/backdrops/dusk-wallpaper.jpg docs/design/backdrops/dusk.jpg`

`scripts/snap.sh` (then `chmod +x scripts/snap.sh`):

```bash
#!/usr/bin/env bash
# Screenshot a Tidewatch design preview target (invented sessions, nothing real is touched).
#
#   scripts/snap.sh <target> <out.png>
#   targets: widget-collapsed widget-expanded widget-empty widget-overflow widget-disconnected
#
# SNAP_BACKDROP=<image>   image right behind the widget (default docs/design/backdrops/dusk.jpg)
# SNAP_SETTLE=<seconds>   wait after the window appears (default 1.5)
# TIDEWATCH_GLASS_FALLBACK=1 is passed through (macOS 14/15 glass on macOS 26).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BIN="${TIDEWATCH_BIN:-$ROOT/.local-build/Build/Products/Debug/Tidewatch.app/Contents/MacOS/Tidewatch}"
SETTLE="${SNAP_SETTLE:-1.5}"
BACKDROP="${SNAP_BACKDROP:-$ROOT/docs/design/backdrops/dusk.jpg}"

[[ $# -eq 2 ]] || { echo "usage: scripts/snap.sh <target> <out.png>" >&2; exit 2; }
[[ -x "$BIN" ]] || { echo "snap: no binary at $BIN (run make build)" >&2; exit 1; }

log="$(mktemp -t tidewatch-snap)"
TIDEWATCH_PREVIEW_BACKDROP="$BACKDROP" "$BIN" --design-preview "$1" >"$log" 2>/dev/null &
pid=$!
trap 'kill "$pid" 2>/dev/null || true; wait "$pid" 2>/dev/null || true; rm -f "$log"' EXIT

frame=""
for _ in $(seq 1 100); do
    frame="$(sed -n 's/^WINDOW_FRAME=\([0-9,-]*\)$/\1/p' "$log" | head -n 1)"
    [[ -n "$frame" ]] && break
    kill -0 "$pid" 2>/dev/null || { echo "snap: preview exited:" >&2; cat "$log" >&2; exit 1; }
    sleep 0.1
done
[[ -n "$frame" ]] || { echo "snap: no WINDOW_FRAME within 10 s" >&2; exit 1; }

sleep "$SETTLE"
mkdir -p "$(dirname "$2")"
rm -f "$2"
screencapture -x -R"$frame" "$2"
[[ -s "$2" ]] || { echo "snap: screencapture wrote nothing (Screen Recording permission?)" >&2; exit 1; }
echo "$2"
```

- [ ] **Step 3: Capture every target**

Run: `make build && for t in widget-collapsed widget-expanded widget-empty widget-overflow widget-disconnected; do scripts/snap.sh $t .local-build/snaps/$t.png; done && TIDEWATCH_GLASS_FALLBACK=1 scripts/snap.sh widget-expanded .local-build/snaps/widget-expanded-fallback.png`
Expected: six PNGs.

- [ ] **Step 4: Compare with the mockups and tune**

Open each PNG (Read tool) next to `docs/design/01-overview-expanded-detail.png` and `docs/design/02-states-and-sizes.png`. Check: dark smoked glass with a bright top rim, white Inter type, orange "Needs approval" text, green working lamps with a soft halo, gray idle lamp, the count badge, the chevron in the overflow column, rows 50 pt tall with the elapsed time and the blue code glyph. Tune only token values (`GlassTokens.Widget.wash/smoke/tint`, `GlassColor.attention`, `WidgetMetrics` sizes) and re-capture until it matches. Write down the final values in the spec section 5 if they changed.

- [ ] **Step 5: Checkpoint**

`make build` and `make test` pass; the PNGs match the mockups' look.

---

### Task 13: Release build, install, real end-to-end acceptance, docs

**Files:**
- Create: `scripts/sign-app.sh`, `README.md`
- Modify: `Makefile` (release, sign, install), `docs/architecture.md` (status: built), `AGENTS.md` (only if commands changed)

**Interfaces:**
- Consumes: the whole app.
- Produces: `make release`, `make sign APP_PATH=...`, `make install`; an installed, connected Tidewatch.

- [ ] **Step 1: Signing script**

`scripts/sign-app.sh` (then `chmod +x scripts/sign-app.sh`):

```bash
#!/usr/bin/env bash
# Sign Tidewatch.app inside-out (the embedded helper first) with hardened runtime.
#   scripts/sign-app.sh <app> <identity|-> [keychain]
set -euo pipefail
APP="$1"
ID="$2"
KEYCHAIN="${3:-}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
args=(--force --options runtime --timestamp=none --sign "$ID")
[[ -n "$KEYCHAIN" ]] && args+=(--keychain "$KEYCHAIN")
codesign "${args[@]}" "$APP/Contents/MacOS/tidewatch-hook"
codesign "${args[@]}" --entitlements "$ROOT/Tidewatch/Tidewatch.entitlements" "$APP"
codesign --verify --strict "$APP"
```

- [ ] **Step 2: Makefile release targets**

Append to `Makefile`:

```make
# Stable local signing identity shared with Captylo (scripts/setup-signing.sh in Captylo).
# Without it builds are signed ad-hoc. The signing keychain joins the search list only for the
# codesign call and the previous list comes back right after (also on failure).
SIGN_NAME := Captylo Dev
SIGN_KEYCHAIN := $(HOME)/Library/Keychains/captylo-dev.keychain-db
SIGN_PASSWORD_FILE := $(HOME)/.claude/secrets/captylo-dev-keychain.key

release: gen
	set -o pipefail; $(XCODEBUILD) -configuration Release CODE_SIGN_IDENTITY="-" build 2>&1 | $(XCPRETTY)
	@rm -rf "$(HOME)/Downloads/$(APP_NAME)"
	@ditto "$(DERIVED)/Build/Products/Release/$(APP_NAME)" "$(HOME)/Downloads/$(APP_NAME)"
	@xattr -cr "$(HOME)/Downloads/$(APP_NAME)"
	@$(MAKE) --no-print-directory sign APP_PATH="$(HOME)/Downloads/$(APP_NAME)"
	@echo "Release build copied to ~/Downloads/$(APP_NAME)"

sign:
	@if security find-identity -p codesigning "$(SIGN_KEYCHAIN)" 2>/dev/null | grep -q '"$(SIGN_NAME)"'; then \
		security unlock-keychain -p "$$(cat "$(SIGN_PASSWORD_FILE)")" "$(SIGN_KEYCHAIN)"; \
		ORIGINAL="$$(security list-keychains -d user | tr -d '"' | xargs)"; \
		trap 'security list-keychains -d user -s $$ORIGINAL' EXIT; \
		security list-keychains -d user -s $$ORIGINAL "$(SIGN_KEYCHAIN)"; \
		scripts/sign-app.sh "$(APP_PATH)" "$(SIGN_NAME)" "$(SIGN_KEYCHAIN)" && echo "Signed with $(SIGN_NAME)"; \
	else \
		echo "No '$(SIGN_NAME)' identity; signing ad-hoc"; \
		scripts/sign-app.sh "$(APP_PATH)" -; \
	fi

install: release
	@pkill -x Tidewatch || true
	@rm -rf "/Applications/$(APP_NAME)"
	@ditto "$(HOME)/Downloads/$(APP_NAME)" "/Applications/$(APP_NAME)"
	@echo "Installed to /Applications/$(APP_NAME)"
```

- [ ] **Step 3: Build, install, launch**

Run: `make install && open /Applications/Tidewatch.app`
Expected: `Signed with Captylo Dev` (or ad-hoc), the lamp column on the right edge.

- [ ] **Step 4: Connect for real (owner approved the hook change in the spike; this replaces the spike hook)**

First make sure the temporary spike hook is gone from `~/.claude/settings.json` (it is removed at the end of the spike). Then click "Connect to Claude Code" in the menu bar item (drive it with `osascript` System Events if needed). Check:
Run: `python3 -c "import json; h=json.load(open('$HOME/.claude/settings.json'))['hooks']; print(sorted(h)); print(h['Stop'])"` and `ls -la ~/Library/Application\ Support/Tidewatch/bin/`
Expected: the 11 events, each with the quoted helper path and `timeout: 5`; the helper copy exists and is executable; `~/.claude/settings.json.tidewatch-backup` exists.

- [ ] **Step 5: Real end-to-end acceptance (spec section 1)**

With real Claude Code sessions in VS Code (the owner's running sessions produce live traffic; this session itself is one):
1. Within a few seconds the lamps match the sessions in `~/Library/Application Support/Tidewatch/sessions/` (Read one file to confirm `host: vscode`, a `pid`, the right `cwd`).
2. A session doing tool calls shows green with a pulse; after a `Stop` it shows orange "Awaiting review" and the "Tink" sound plays.
3. A permission prompt or a question (`AskUserQuestion`) shows orange "Needs approval" / "Needs your answer" within about a second, with the "Glass" sound. If no prompt happens naturally, ask the owner once to trigger one.
4. Hover the column: the panel opens after ~0.3 s, the row under the pointer highlights, the lamp of that row grows; moving away closes it after ~0.45 s.
5. Click a row of a VS Code session while another VS Code window is in front: the right window and the Claude tab come forward (check with `osascript -e 'tell application "System Events" to get name of front window of process "Code"'`); the row turns idle if it was "Awaiting review".
6. Right click a row: "Show in Finder" opens the folder.
7. Click on the transparent area left of the column (where the panel would be): the click reaches the window below.
8. Quit and relaunch Tidewatch: the list comes back at once, no sound plays at launch.
9. "Disconnect" removes exactly the Tidewatch entries (diff against the backup), "Connect" adds them back.
Take a screenshot of the expanded widget over real windows for the report.

- [ ] **Step 6: Docs**

- `README.md`: what Tidewatch is, requirements (macOS 14.4+, Xcode 26, XcodeGen), `make install`, "Connect to Claude Code", the one-time VS Code "Do not ask me again" dialog, workspace trust (hooks wait for the trust dialog), troubleshooting (`log stream --predicate 'subsystem == "pl.craftweb.tidewatch"'`, the backup file), privacy (everything local, no network).
- `docs/architecture.md`: status line "Built (MVP)", any decision that changed during implementation.
- Run the `update-docs-before-commit` skill before the owner's "commituj".

- [ ] **Step 7: Final checkpoint**

`make build`, `make test` pass; acceptance list 1-9 done with evidence (screenshots, command output). Report to the owner and propose commit messages (owner's rule).
