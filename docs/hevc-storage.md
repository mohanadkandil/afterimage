# HEVC storage: implementation and measured results

Measured on this Apple Silicon Mac on 12 September 2026. The 182-frame archive is a desktop-work sample, not a long-duration controlled recording. MB/GB are decimal; MiB is binary.

## Result

| Archive | Bytes excluding generated preview cache |
|---|---:|
| Original JPEG archive | 67.71 MB |
| Previous lossless deduplication build | 56.46 MB |
| New Balanced HEVC build | **13.39 MB** |

The Balanced archive consists of **9.52 MB of video** and approximately **3.87 MB of database/metadata**, in seven chunks. All 182 timestamps, source information, OCR text and boxes remain unchanged. Every frame was decoded and checked for the correct dimensions. Search result IDs match the previous build across four queries (179, 71, 94 and 11 matches).

At one saved moment every two seconds and the same average bytes per moment, eight active hours project to **1.06 GB** of recordings plus metadata. This is an estimate, not a measured daily total. Changed content, resolution, text density, idle time, quality choice and deletion patterns affect it. Preview cache, pending captures and retained external backups are separate. This is not a claim about months of use or battery life.

## Architecture

1. ScreenCaptureKit sampling and the existing change gate select frames. Vision OCR runs before video compression, preserving searchable text independently of any later image compression.
2. New Balanced/Sharper captures stage as lossless PNGs, avoiding an intermediate JPEG generation. JPEG-only mode remains available. Pending files are independently durable and can be recovered after interruption.
3. C++ batches at most 30 frames, closing earlier at approximately 32 MiB of input data or a dimension boundary. The threshold may be exceeded by one large input image. Short final batches are processed on pause and next launch; abrupt termination leaves pending files recoverable.
4. AVAssetWriter encodes HEVC MP4 using quality 0.80 for Balanced or 0.90 for Sharper, no frame reordering, and a maximum ten-frame keyframe interval. The one-second codec timestamp is an ordinal; actual recording times remain in SQLite.
5. Boundary frames are decoded before publication. Media is flushed to disk, renamed, then referenced in a SQLite transaction. Original stills are unlinked only after commit. A failure preserves them; a completed chunk that would be larger than its inputs is not substituted.
6. SwiftUI resolves frames asynchronously through the native bridge. AVAssetImageGenerator requests the exact ordinal with zero time tolerance. Preview files are capped at eight images / approximately 32 MiB (a single oversized image is an exception), and the decoded NSCache retains its advisory 64 MiB cost limit. Obsolete queued main-frame requests are skipped.
7. Normal packing considers pending rows; it does not scan all history on every capture. Startup/manual maintenance reconciles leftovers against committed metadata. Settings shows recordings, preview cache, database and any temporary files separately.

No ffmpeg executable is needed by the app. It was used only for an initial experiment and Coast file inspection. The implementation uses Apple's native media frameworks; see [Apple's HEIF and HEVC session material](https://devstreaming-cdn.apple.com/videos/wwdc/2017/511tj33587vdhds/511/511_working_with_heif_and_hevc.pdf). Exact seeking is implemented against the SDK's AVAssetImageGenerator API.

## Quality tradeoff

All three versions below were encoded from the same existing JPEG archive. This measures migration quality; future PNG-staged captures avoid that initial JPEG generation.

| HEVC quality | Video | Archive + metadata | Median pixel PSNR | OCR token recall, mean / minimum |
|---|---:|---:|---:|---:|
| 0.75 | 7.32 MB | 11.20 MB | 44.0 dB | 97.1% / 92.5% |
| 0.80 | 9.52 MB | 13.39 MB | 45.5 dB | 97.0% / 91.3% |
| 0.90 | 17.96 MB | 21.83 MB | 48.1 dB | 97.1% / 90.8% |

PSNR compares decoded RGB pixels with the original JPEG and is not a guarantee of perceived quality. The eight-screenshot OCR comparison uses distinct tokens recognized by Apple Vision from original JPEGs as its reference; it is not ground truth. OCR changes are not strictly monotonic with encoder quality. Original searchable OCR is kept unchanged for all frames. **HEVC is lossy**; this build does not promise pixel-identical migration. Sharper trades additional storage for lower pixel error. Keep JPEG images disables compaction of pending/new captures but does not restore previously compressed recordings.

## Performance

- Balanced compaction of 182 existing frames: **3.59 s wall time**, **2.51 s combined process CPU time**, **108.8 MiB peak RSS**. This is a CLI compaction measurement, not whole-app recording memory or battery consumption.
- Twenty CLI searches across the full archive: median **30.94 ms before**, **31.26 ms after**. Result sets are identical; speed is effectively unchanged.
- Exporting every decoded frame to PNG: median **222 ms**, p95 **264 ms**, including process launch, cold decode, preview publication and PNG export. This is not UI wheel-event latency. In-memory images avoid that cold path.
- No sustained screen-recording CPU, energy or long-session UI RSS claim is made. Background compression complements, rather than removes, OCR cost.

## Deletion and recovery

Deleting an entire expired chunk removes it without decoding. Deleting part of a chunk materializes surviving frames as lossless PNGs, then removes the old video, so deleted pixels do not remain hidden in that file. Those survivors are excluded from future automatic lossy recompression. **This can increase storage for that one chunk**; repeated selective deletions can reduce the compression benefit. The tradeoff preserves survivor pixels rather than silently applying repeated lossy encodes. External backups retain their own history until removed separately.

The new tests cover native HEVC automatic batching, index ordering, export, reopen, injected encoding failure, orphan cleanup, deleting a frame while preserving survivor pixels, whole-chunk retention, existing FTS behavior, and legacy schema migration. SwiftUI smoke checks cover empty/populated and regular/compact windows, search, image loading, storage counts and timeline wheel/trackpad handlers. Boundary publication is checked in production; every frame of the measured archive was checked separately before live migration.

## Reproduce

Work on a copy of an archive:

```sh
LITT_HOME=/path/to/copy litt compact
LITT_HOME=/path/to/copy litt stats
LITT_HOME=/path/to/copy litt export FRAME_ID /tmp/frame.png
./scripts/build.sh
python3 tests/native_ui.py
```

`compact` returns before/after statistics; running it again does not re-encode existing chunks. `optimize` still performs exact sharing for pending images. [Machine-readable measurements](hevc-measurements.json) include all three quality settings and the integrity/search results.

## What we actually know about Coast

The installed Coast skill describes roughly two-second sampling. Local inspection found HEVC video chunks and about 10.16 GB of video within a 20.61 GB archive; the rest was mostly its database. Its CLI reported approximately 158 recorded hours. That supports investigating inter-frame compression, not claims about its exact encoder settings, OCR engine, embeddings or database layout. [Coast's public site](https://coast.app/) describes the local-memory product but does not establish those internals. Its aggregate bytes per frame are not a same-content benchmark against this implementation.
