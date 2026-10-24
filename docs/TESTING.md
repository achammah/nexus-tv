# Testing

| Type | File | Runner | What fails it |
|---|---|---|---|
| Build (simulator) | project.yml | `xcodebuild … -destination 'generic/platform=tvOS Simulator' build` | any compile/link error |
| Build (device, unsigned) | project.yml | `xcodebuild … -destination 'generic/platform=tvOS' CODE_SIGNING_ALLOWED=NO build` | any compile/link error for arm64 tvOS |
| Remote journeys | Tests/tvOSUITests/RemoteJourneyTests.swift | `scripts/uitest.sh` | focus does not land where asserted; Resume missing after watching; menu tab not hidden/reordered/reset |
| Visual review | shots/remote/*.png | read by a person after each run | layout or focus look differs from the Frame app |

Journeys (build 3): 1 Home rows, hero Left/Right, long-press menu, favourite first in its country row with a star, "All Belgium channels" tile, header hidden while scrolled · 2 Move one tile (Move first in the menu, lift + wiggle, left/right, drop) · 3 Film: loading card, live scrub, control bar, audio picker, back to the detail with Resume, Continue watching · 4 Series: Next episode, one Continue watching entry per series · 5 Live guide: favourite by long press, play, zap · 6 Search: system text field (iPhone keyboard), letter grid typing · 8 Search covers added lists · 7 Settings: Edit order, add a list, account form refuses an empty login, Clear lists.

The journeys use the live provider: results depend on what the provider serves that day.

## Build 4 additions

| Type | File | Runner | What fails it |
|---|---|---|---|
| Speed (key-driven, no UI test) | scripts/perfkeys.sh + scripts/perf.py | `APP=<.app> scripts/perfkeys.sh` | main-thread time per focus move, hitches, launch-to-Home marks (app run with `-NXMetrics YES`) |
| Speed (UI test, tab switches) | Tests/tvOSUITests/PerfTests.swift | `scripts/perf.sh` | time from a tab press to the tab mark |
| Network cut | scripts/netcut.sh + scripts/flaky_proxy.py | `CUT=3 scripts/netcut.sh live|film` | no `player.trouble` / `player.reconnect` / `player.playing` sequence, or the playback clock does not move again |
| Build 4 journeys | Tests/tvOSUITests/Build4Tests.swift | `scripts/uitest.sh` | native search: no other-language results or no focusable result; other countries: no "Channels · other countries" row for "rtl"; Settings: Lists shows under 1,000 categories, the Films tab does not narrow it, select does not toggle ✓, a starred channel of another country is missing from "More favourites"; tracks: the next episode does not start with the chosen subtitle (checked in metrics.log) |

`-NXMetrics YES` writes `Library/Caches/metrics.log` in the app container: per second frames, hitches, main-thread busy time and view-body counts; events (launch, tab, ready, player.*).
UI tests use `idle()` (a run-loop wait) instead of `sleep()`: a blocking sleep over 10 s gets the test runner killed by the scene watchdog in Release runs.

## Build 6: first launch with no account

| Type | File | Runner | What fails it |
|---|---|---|---|
| First launch | Tests/tvOSUITests/AAOnboardingTests.swift (runs first) | `scripts/uitest.sh` | no "Add your IPTV account" screen after `-NXResetAccounts YES` (debug builds only), a Cancel button on it, a wrong login accepted, the screen still up after a valid login, no Home rows, no "Preparing search" line |
| No account in the app | the post-build phase "No account or catalogue inside the app" in project.yml | every build | an incremental build would keep files removed from the project; the phase deletes `DefaultAccount.plist` and `search_all.json` from the product and warns |

Captures that show a typed login go to `build/private-*.png`, never to `shots/`.

## Build 9: player parity and online subtitles

| Type | File | Runner | What fails it |
|---|---|---|---|
| Player parity | Tests/tvOSUITests/PlayerParityTests.swift | `scripts/uitest.sh` | text on the control bar; Next episode not reached by Up or not above the bar; no next-episode card 40 s before the end, no countdown, Select or Menu wrong, card shown twice; resumed episode without Next episode; audio menu without formats; remembered audio not current on replay |
| Audio switch | Tests/tvOSUITests/AudioTrackTests.swift | `scripts/uitest.sh` | the picked track is not the current one when the menu reopens, or the clock stops |
| Online subtitles | Tests/tvOSUITests/OSubTests.swift | `OSUB_ACCOUNT_FILE=<file> scripts/uitest.sh` | sign-in not shown; no online results in the CC menu; a pick not marked current; the next episode without the remembered online subtitle |
| Navigation | Tests/tvOSUITests/NavAuditTests.swift, SearchFocusTests.swift | `scripts/uitest.sh` | Up from any tile does not reach the tab bar; Menu from content does not; Up from search results does not reach the keyboard |

`OSUB_ACCOUNT_FILE` holds an OpenSubtitles test account on 3 lines (API key, username, password), kept outside the repo; the log masker hides its values. Each run of OSubTests uses about two downloads.
