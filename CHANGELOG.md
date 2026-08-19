# Changelog

All notable changes to ClaudeMeter are documented here.
Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [1.0.0] — 2026-08-19

First release. Menu bar app showing Claude subscription usage on macOS 13+.

### Added
- Menu bar item with six switchable designs (`Doppelbalken`, `Nur die Zahl`, `Doppelring`,
  `Reset-Countdown`, `Segmente`, `Zahlenpaar`), each pairing a menu bar glyph with its own panel
  layout. Selectable in settings with a live preview.
- Tolerant parser for `/api/oauth/usage` handling both the flat schema and the structured
  `limits[]` array, including the hybrid form the API actually returns.
- Read-only credential resolution from four sources: `CLAUDEMETER_TOKEN`, an own keychain entry,
  Claude Code's keychain entry, and `~/.claude/.credentials.json`.
- Polling every 5 minutes with 30 s timer tolerance, immediate refresh on panel open (throttled to
  60 s) and on wake from sleep, and no requests at all while asleep.
- 429 backoff ladder 5 → 10 → 20 → 30 minutes; single 401 retry after re-resolving the token.
- Stale-data handling: the last good snapshot stays visible with its age plus a plain-language error.
- Settings for menu bar colour (template rendering by default), showing model-scoped weekly limits,
  and launch at login via `SMAppService`.
- `claudemeter-doctor` CLI that walks the token → request → parse path and reports each stage
  without ever printing the token.
- `AssetGen` tool that renders the README screenshots and `AppIcon.icns` from the shipping views.
- `scripts/bundle.sh` producing a signed, Dock-less `.app` (`LSUIElement`).
- 49 unit tests covering both schemas, hostile payloads, UTC→local conversion, label width
  stability and keychain candidate selection.

### Fixed during development
- **Keychain query returned nothing.** `kSecReturnData` combined with `kSecMatchLimitAll` fails with
  `errSecParam` (-50) on macOS. Replaced with a two-pass query: enumerate service names by
  attribute, then read each candidate individually.
- **Wrong keychain entry could be selected.** Sibling entries named `Claude Code-credentials-<guid>`
  hold MCP server logins under an `mcpOAuth` key, not the subscription credential. Candidates are
  now filtered to payloads containing `claudeAiOauth` and ranked by validity, exact service name and
  expiry.

### Notes
- The data source is undocumented and unofficial. See [`docs/DATA-SOURCE.md`](docs/DATA-SOURCE.md).
