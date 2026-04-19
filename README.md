# Litt

A native AppKit screen-memory app for macOS, with a C++20 archive engine and a CLI for agents. Find something you saw, open the screenshot, and browse the moments around it.

Litt samples the selected display (the main display by default), reads visible text with Apple's on-device Vision framework, and stores searchable screenshots on your Mac. Recording is off on launch. There are no accounts, network services, API keys, or bundled activity records.

## Build and run

Requires **macOS 14 or newer**, Apple Command Line Tools, CMake 3.20+, and Python 3 for the integration test. The system SQLite library must include FTS5 (macOS does).

```sh
./scripts/build.sh
./litt
```

Install the app and terminal launcher:

```sh
./scripts/install.sh
# App: ~/Applications/Litt.app
# CLI: ~/.local/bin/litt
```

Click **Start recording**. On first use, grant Litt access in **System Settings → Privacy & Security → Screen & System Audio Recording**, then restart the app. Switch to another application; Litt deliberately does not capture while its own interface is focused. Permission is never required for importing screenshots or searching the archive.

The app is locally ad-hoc signed. A Developer ID signature and notarization are not included. This build is intended for local use; rebuilding or changing its installed location may require macOS permission to be granted again.

## Using the app

![Litt first launch](docs/first-launch.png)

- Search visible text or window titles. Search terms are literal words combined with AND, not a query language. Results are chronological, not AI-generated answers.
- Choose a date and application. **Earlier / Newer** page through the entire matching archive in batches of 200.
- Select a result to see the screenshot and highlighted OCR boxes. Open **Details** for the recognized text, source, dimensions and timestamp.
- Scrub the application timeline or use the arrow keys. Space plays saved moments at a fixed step rate; it is **not a continuous video or real-time reenactment**. Gaps remain visible.
- Zoom, export an image, or delete an individual moment.
- Import PNG/JPEG screenshots to test the pipeline without recording. Imports are explicitly labeled and dated at import time. The CLI can set a supplied capture timestamp.
- Set the capture interval, history retention and excluded app bundle IDs in Settings. Delete all history there, or reveal the archive in Finder.

The macOS menu bar indicates whether recording is enabled and provides pause/resume. Closing the main window pauses recording; the menu-bar app remains available. Recording also pauses on screen sleep, system sleep or session deactivation. It does not automatically resume after those events.

## What gets captured

The default sampling interval is **2 seconds** (configurable from 1–30 seconds). Each candidate is compared with the last saved image through a C++ change gate:

1. App or window-title changes save a fresh sample.
2. A 160×90 grayscale comparison selects frames with sufficient visual change.
3. Unchanged screens receive a checkpoint after 30 seconds.
4. Only one capture/OCR job can be in flight, so slow OCR causes skipped sampling opportunities rather than an unbounded queue.
5. Excluded application windows are filtered from the capture. If an excluded app is focused, capture waits entirely. Litt always excludes itself.
6. OCR runs off the UI thread. Before saving, the app checks that recording is still enabled, the capture generation is current, and the focused app is not excluded.

This is periodic capture with change-based saving, not a guarantee that every screen change is preserved. Small changes may be missed. OCR can misread text; inspect the screenshot for evidence. Capture includes visible content from other non-excluded windows on that display. Browser private tabs and sensitive content are not automatically detected; exclude the browser or pause recording as appropriate.

No microphone or audio is captured. The current release does not capture accessibility trees, browser URLs, multiple displays simultaneously, or semantic embeddings. It provides full-text search, not chat.

## Terminal interface

All commands return JSON and work without the app running. The CLI uses the same C++ archive and SQLite database as the desktop app; it does not scrape the UI.

```sh
litt --help
litt doctor
litt stats
litt list --limit 20
litt search 'sensor calibration' --app com.apple.Safari
litt search 'localization' --from 1789084800 --to 1789171200
litt frame 12
litt import ~/Desktop/screenshot.png
litt export 12 ~/Desktop/moment.jpg
litt delete 12
litt prune 14
```

`--from` is inclusive and `--to` exclusive; both accept Unix seconds. Frame timestamps are stored in Unix seconds and displayed in the Mac's local timezone. `list` and `search` accept `--app`, `--from`, `--to`, `--limit` (maximum 1000) and `--offset`. CLI export refuses to overwrite an existing file. Failures return a nonzero exit status and a JSON error on stderr.

Use `LITT_HOME=/path/to/archive` for an isolated archive. The default is `~/Library/Application Support/Litt`. The database uses WAL mode and a busy timeout for concurrent app/CLI access. Directory permissions are restricted to the current user. Data is not independently encrypted by Litt; OS disk encryption is separate.

The agent usage guide is [docs/AGENT-SKILL.md](docs/AGENT-SKILL.md).

## Engineering

| Component | Implementation |
|---|---|
| Archive, filters, FTS queries, preferences, retention | C++20 + SQLite FTS5 |
| Change selection | C++ grayscale comparison and timestamp/context checkpoints |
| Capture | ScreenCaptureKit through Objective-C++ |
| Text extraction | Apple Vision; normalized OCR rectangles retained |
| Desktop shell | AppKit controls, scroll views, sheets and popovers in Objective-C++ |
| App/engine bridge | In-process Objective-C++ callbacks; no HTTP server |
| Screenshot delivery | Native NSImage rendering from the local archive |
| CLI | Same native executable and C++ engine |

Clang, SQLite, Vision and ScreenCaptureKit supply foundational capabilities; this project implements their integration, archive behavior, change gate, query workflow and UI. It does not claim a new OCR model or search algorithm.

See [architecture and decisions](docs/ARCHITECTURE.md) and [validation](docs/VALIDATION.md).

## Tests and package

```sh
./scripts/build.sh                 # C++ tests + native OCR/CLI integration
./scripts/package.sh               # dist/Litt-macOS.zip
python3 tests/native_ui.py          # AppKit checks; logged-in Mac required
```

The C++ core can also be built and tested on Linux. Native capture, OCR and the app require macOS. CI definitions are included; a workflow file is not evidence that hosted CI has run.

Keyboard shortcuts: **⌘F** or **/** focuses search; **← / →** browses moments; **Space** toggles playback; **⌘,** opens Settings. The app follows the system light/dark appearance.

The generated document in `tests/fixture.png` is explicitly labeled test content and is never inserted into the user's archive automatically. To exercise the native UI with an isolated archive:

```sh
export LITT_HOME="$(mktemp -d)"
./litt import tests/fixture.png
./build/Litt.app/Contents/MacOS/Litt --ui-smoke /tmp/litt-ui
# JSON check results and a native AppKit screenshot:
# /tmp/litt-ui.json and /tmp/litt-ui.png
```

`--ui-smoke` opens a test window, exercises actual AppKit controls and C++ archive operations, writes results, then exits. It never starts recording. [scripts/draw-assets.swift](scripts/draw-assets.swift) regenerates the icon and OCR fixture.

## License

MIT. The vendored nlohmann/json header retains its own MIT license. See [THIRD_PARTY.md](THIRD_PARTY.md).
