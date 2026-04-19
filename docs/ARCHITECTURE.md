# Architecture

```text
AppKit controls / menu bar
          │
          ▼
ScreenCaptureKit candidate screenshot (configured interval)
          │
          ▼
Serial processing queue → C++ ChangeGate → Vision OCR + JPEG encoding
          │
          ▼
Main-thread generation / recording / exclusion check
          │
          ▼
C++ Store ── SQLite WAL + FTS5 ── frames/<id>.jpg
    │                                │
    ├── native JSON CLI              │
    └── AppKit view controller ── NSImage canvas + native controls
```

The executable has two entry modes: native AppKit when launched without arguments and CLI for archive operations. `NativeUI.mm` owns system search/date controls, the image canvas, timeline, filmstrip, settings sheets and evidence popover. It invokes the application controller through in-process Objective-C++ callbacks. The controller reuses the C++ archive and capture engine. There is no WebKit dependency, HTML/CSS/JavaScript UI, web bridge or HTTP server. OCR text is displayed as plain text in an NSTextView.

`Store` owns a SQLite connection with prepared statements and an in-process recursive mutex. Other processes use separate WAL connections. FTS5 external-content triggers track insertions and deletions. Image files have generated numeric IDs rather than input filenames. Imports decode through ImageIO, extract OCR through Vision, then use the same archive path as capture.

A capture generation token invalidates pending work after pause or settings changes. Final writes occur on the main thread after processing, so pause and save decisions are serialized. ChangeGate is used on the serial worker; resets are queued on the same worker. Only one screen job is pending at a time.

Retirement of frames runs on launch, hourly, and after saving preferences. Deletes remove the FTS entry and image. File deletion failure is reported; this is not a forensic secure-erasure guarantee. The DB and image filesystem are separate: abrupt power failure can leave an orphan file or a missing image. There is no cloud backup or remote synchronization.

The timeline summarizes the loaded page of saved observations. Bands extend to the next saved sample, capped at 30 seconds so longer gaps remain visible. Those bands are not measured attention or interaction time. Search uses literal AND terms and chronological ordering; OCR boxes provide screenshot-linked matches.

## Boundaries

- One display per capture; main display by default. No multi-monitor stitching.
- ScreenCaptureKit and Vision are macOS dependencies; the storage/search core is portable C++.
- The CLI bypasses the GUI and operates directly on the local archive. No app-control socket is exposed.
- No domain extraction, accessibility recording, embeddings, autonomous actions or generative answers in v0.1.
- App title metadata comes from the first available on-screen layer-zero window owned by the frontmost app; multi-window ordering can be imperfect.
- Grayscale downsampling deliberately trades precise change detection for low overhead. The 30-second checkpoint limits long gaps on otherwise unchanged screens, but is not a guarantee against OCR misses.
