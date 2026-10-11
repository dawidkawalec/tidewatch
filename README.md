# Tidewatch

A tiny macOS widget that shows every running Claude Code session as a glass status lamp on the right edge of the screen.

- 🟢 working (soft pulse), 🟠 needs approval / your answer, 🟠 awaiting review (Claude finished its turn), ⚪ idle
- Hover the column to see the list: project, status, time in that status
- Click a row: the right VS Code window and the session's Claude tab come to the front
- Sounds when a session needs approval ("Glass") and when it finishes a turn ("Tink")

Everything stays on your Mac: Claude Code hooks write small state files to `~/Library/Application Support/Tidewatch/sessions/`, and the widget reads them. The only network access is a daily update check (Sparkle) against https://kawalec.pl/tidewatch/updates/appcast.xml; **Check for Updates…** in the menu bar runs it by hand.

## Requirements

- macOS 14.4 or newer, Apple silicon
- Xcode 26 and XcodeGen (`brew install xcodegen`) to build
- Claude Code (VS Code extension or CLI)

## Install

Download Tidewatch from https://kawalec.pl/tidewatch/ (or the repo's GitHub Releases), open the DMG and drag Tidewatch to Applications (signed with Developer ID and notarized, so it opens without warnings). Or build it yourself:

```bash
make install            # Release build, signed, copied to /Applications
open /Applications/Tidewatch.app
```

Then open the lamp icon in the menu bar and choose **Connect to Claude Code**. This adds Tidewatch's hook entries to `~/.claude/settings.json` (a backup goes to `~/.claude/settings.json.tidewatch-backup`; other settings and hooks are kept). **Disconnect** removes exactly those entries.

The first time you click a session, VS Code asks "Allow 'Claude Code for VS Code' extension to open this URI?". Tick **Do not ask me again for this extension** and every later click goes straight to the session.

## Troubleshooting

- **A session does not show up.** Claude Code runs user hooks only after the workspace trust dialog is accepted. Open the folder in Claude Code once and accept it.
- **Nothing changes at all.** Check that the hooks are there: `grep tidewatch-hook ~/.claude/settings.json`. Reconnect from the menu if needed.
- **Logs:** `/usr/bin/log stream --predicate 'subsystem == "pl.craftweb.tidewatch"'` (in zsh, plain `log` is a shell builtin).
- **Undo everything:** Disconnect in the menu, quit Tidewatch, delete `/Applications/Tidewatch.app` and `~/Library/Application Support/Tidewatch/`.

## Development

```bash
make build    # Debug build
make test     # core package tests, app tests, hook helper end to end
scripts/snap.sh widget-expanded out.png   # screenshot a design preview with invented sessions
```

See [AGENTS.md](AGENTS.md) and [docs/](docs/) for the architecture, the spec and the coding standards.

## License

MIT, see [LICENSE](LICENSE). The bundled Inter and Manrope fonts are under the SIL Open Font License (`Tidewatch/Resources/Fonts/OFL-*.txt`); Sparkle is MIT. Tidewatch is not affiliated with Anthropic.
