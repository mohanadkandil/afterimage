# Validation — 2026-09-11

Tested on this Mac: Apple Silicon, macOS 26.6, Apple Clang 17, CMake 4.4.3, system SQLite 3.43.2. The deployment target is macOS 14; older supported OS releases have not been exercised locally.

## Passed

- Release C++20 / Objective-C++ engine with a Swift 6 SwiftUI library; WebKit and web UI resources removed.
- C++ archive suite: persistence, FTS escaping, filters, retention, concurrent access and change detection.
- Native CLI integration: real Vision OCR, exact-token retrieval, JPEG export, malformed imports and deletion.
- App-icon resolution verified against installed Finder and an unavailable bundle ID; neutral fallback verified.
- Native SwiftUI smoke checks using isolated archives: image rendering, OCR search/highlights, search misses, app names/filtering, date filtering, previous/next navigation, scrubbing, zoom, evidence and settings sheet.
- Empty/populated layouts inspected at regular and compact window sizes. Light and dark appearances inspected using native view snapshots.
- Core and native OCR/CLI suites pass. Their sub-second runtime is not a capture/search performance benchmark.

Results: [populated](ui-populated-check.json), [empty](ui-empty-check.json), [compact populated](ui-compact-populated-check.json), [compact empty](ui-compact-empty-check.json). Screenshots show the actual SwiftUI app with a labeled test fixture, never fabricated user activity. The UI smoke entry point exercises the SwiftUI view model through its native bridge; it does not establish full manual mouse/keyboard coverage or a measured animation frame rate.

## Remaining UI validation

- Extended archives, many app transitions, sustained playback and responsiveness under heavy capture load need longer testing.
- Native file dialogs and destructive confirmation paths have been implemented; automated coverage checks the underlying CLI operations, not every dialog interaction.
- No global summon hotkey, timeline scale zoom, or macOS HUD desktop dimming is implemented. Image zoom and in-window keyboard navigation are available.

## Pending permission-dependent validation

The installed app's `litt doctor` reports `screenRecordingPermission: false`. Therefore **live ScreenCaptureKit capture, live app exclusion behavior, and lock/sleep cancellation have not been verified end to end on this Mac**. The external macOS harness also lacks screen-recording permission; native app snapshots were used for UI verification instead.

To finish the live check:

1. Open `~/Applications/Litt.app` and click Start recording.
2. Grant its Screen Recording permission in macOS and restart the app.
3. Start recording and switch to a document containing a distinctive phrase.
4. Change the document, wait for another capture, pause from the menu bar, and search the phrase.
5. Confirm results use `source=capture`, match the visible images and link to the expected OCR boxes.
6. Exclude that app; verify no additional frames are saved while it is focused. Test background-window exclusion as well.
7. Pause while a capture is processing; verify it does not subsequently write a frame. Repeat with sleep/session lock.
8. Run a longer capture to measure CPU, memory, archive growth and processing latency before making performance claims.

No hosted CI run, notarization, external distribution, or push to GitHub was performed.

Glass and motion refinement: the local Swift 6.1/macOS 15.5 SDK build uses native regularMaterial with a subtle highlight. The Swift 6.2+/macOS 26 glassEffect branch is not compiled or verified by this toolchain. Thumbnail transitions and press/hover feedback respect Reduce Motion; surfaces become opaque with Reduce Transparency. Core, OCR CLI, and populated/empty SwiftUI smoke checks passed; animation timing has not been instrumented.
