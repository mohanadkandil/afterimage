# Validation — 2026-09-11

Tested on this Mac: Apple Silicon, macOS 26.6, Apple Clang 17, CMake 4.4.3, system SQLite 3.43.2. The deployment target is macOS 14; older supported OS releases have not been exercised locally.

## Passed

- Release build, C++20 core and Objective-C++ desktop executable.
- C++ archive tests: insertion/reopen, literal FTS escaping, AND queries, application/time filtering, retention, settings validation and persistence, concurrent app-style reads/CLI-style writes, image/index deletion, change-gate decisions.
- Native CLI integration: real Apple Vision OCR on a labeled test image; exact token retrieval (`seahorse742`), OCR box bounds, search misses, app/time/offset filters, JPEG export, overwrite refusal, malformed input handling, deletion and image removal.
- Actual WKWebView desktop checks using isolated archives: native message bridge, image loading through the custom scheme, OCR search and highlights, navigation between two images, settings, evidence panel and no document overflow.
- Empty archive desktop check: empty state and capture disabled on launch.
- JavaScript syntax and shell-script syntax checks.
- Local ad-hoc code signing.

The automated release test suites completed in 1.26 seconds on the final verification run. This is test runtime, **not a capture/search performance benchmark**. A separate one-image experiment using a user-supplied screenshot produced 122 OCR boxes and retrieved the image for the term `Clang`; that screenshot is not bundled in the repository.

Native UI results: [populated](ui-populated-check.json), [empty](ui-empty-check.json). The saved [first-launch view](first-launch.png) and [search/evidence view](search-evidence.png) are screenshots of the actual native app. The latter uses the clearly labeled test fixture, not invented recorded activity.

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
