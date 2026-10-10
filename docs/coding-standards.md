# Coding standards

Taken from Captylo (`<captylo-repo>/docs/coding-standards.md`) and trimmed to what Tidewatch needs.

## Swift

- Swift 6 language mode, `SWIFT_STRICT_CONCURRENCY=complete`, no default actor isolation. SwiftUI views, AppKit wrappers and observable UI models are `@MainActor`.
- `TidewatchCore` is pure: value types, no AppKit, no global clock (functions take `now: Date`). The only file I/O lives in `SessionFileStore` (shared by the helper and the app).
- The folder watcher callback runs off the main thread; hand results to the main actor with `Task { @MainActor in ... }`.
- `os.Logger(subsystem: "pl.craftweb.tidewatch", category: ...)` through `Log`. No `print` in the app; the helper prints nothing at all.
- Errors are typed enums conforming to `LocalizedError`.
- One file per type, folder = module, file name = primary type.

## SwiftUI / AppKit

- Tokens live in `UI/Glass/GlassTokens.swift` (radii, paddings, opacities, `GlassColor`, `GlassFont` on Manrope + Inter, `GlassMotion`). No ad-hoc hex colors, materials or `glassEffect` in views: use `widgetGlass`.
- Glass never sits on glass: only the column capsule and the session panel are real glass; rows and badges are translucent fills with a rim.
- The widget panel never activates the app: `orderFrontRegardless()`, never `NSApp.activate` or `makeKey`.
- Springs `response 0.38, dampingFraction 0.85`. Honor `accessibilityReduceMotion` (cross-fades only, no pulse) and `accessibilityReduceTransparency` (solid fills).
- Durations ("2m", "1h") are computed from timestamps at render time inside `TimelineView`, never from timers that accumulate.
- Check UI changes with `scripts/snap.sh <target> <out.png>` and compare with the mockups in `docs/design/`.

## UI language

- English, as in the mockups. One language in the MVP, no string catalog.
- No long dashes in any text: use "-".

## Tests

- Swift Testing (`import Testing`). All of `TidewatchCore` is covered; `HookInstaller` and `SessionStore` are tested against fixtures; the helper gets an end-to-end test with `TIDEWATCH_DATA_DIR` pointing at a temp folder.
- Fixtures never contain real prompts, private paths or secrets.
- UI and hardware are not unit-tested; use the design preview.

## Git

- Commit messages: imperative subject <= 72 chars, body explains what and why. No attribution lines, no AI mentions.
- The generated `Tidewatch.xcodeproj` and `.local-build/` are ignored; `project.yml` is the source.
