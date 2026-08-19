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

- **429 backoff never escalated.** `refreshNow()` reset the ladder unconditionally, and both the
  panel-open refresh and wake-from-sleep route through it. A user checking the panel every minute
  held the app at the 5-minute rung indefinitely. The ladder now resets on HTTP 200 only (runbook
  §7), and the panel-open refresh defers to an active backoff instead of the 60 s floor.
- **Sleep reported a fabricated network error.** Cancelling the in-flight request on
  `willSleepNotification` surfaced as `Netzwerkfehler: Vorgang abgebrochen`. Fetches are now
  generation-tagged, so an abandoned request cannot publish a result.
- **Acceptance criterion 3 was unmet in three layouts.** The reset point must appear as a wall-clock
  time *and* as remaining runtime. The Doppelring panel (the default) and the Countdown session block
  showed only the clock time; `ExtraWindowRow` showed only the countdown. All now show both.
- **Menu bar label jumped width.** The no-data placeholder used EN DASH (7.002 pt) instead of a
  digit-width glyph (7.559 pt), so the label shifted when the first values arrived; and the
  Zahlenpaar style grew from five cells to six at 100 %, because the padding helper cannot truncate.
  Both now use FIGURE DASH / FIGURE SPACE with a three-cell budget per value.
- **Token source 2 rejected the token it exists for.** The user's own keychain entry
  (`de.sagorski.claudemeter.token`, for a `claude setup-token` token) required a `claudeAiOauth`
  wrapper, so a bare token string stored with `security add-generic-password -w` was skipped
  silently — while the equivalent environment variable accepted it. Bare tokens are now accepted,
  with a shape check so a random blob is never sent to the API as a credential.
- **Time zone was frozen at launch.** `Calendar.current` is a snapshot; a long-running menu bar app
  that travels across zones kept rendering reset times in the old zone. Switched to
  `Calendar.autoupdatingCurrent`.
- **Countdown glyph was unreadable in colour mode on light menu bars.** White text sat on a
  semi-transparent mid-tone pill (~1.7:1 contrast). The pill now supplies its own dark ground.
- **Zahlenpaar panel rows broke on long labels.** The 74 pt label column had no line limit, so
  `Woche · Sonnet` wrapped and knocked the row out of alignment. Now 84 pt with tail truncation.
- **Settings preview disagreed with the real label.** It truncated instead of rounding, showing
  56 % where the menu bar showed 57 %.

### Notes
- The data source is undocumented and unofficial. See [`docs/DATA-SOURCE.md`](docs/DATA-SOURCE.md).
