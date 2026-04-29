# Storage and performance measurements

Measured locally on 12 September 2026, Apple Silicon, macOS 26. The archive had 182 saved moments. Results are observations of this archive and workload, not a general performance guarantee. MB below means 1,000,000 bytes.

## Shipped change: exact image sharing

| Measurement | Before | After |
|---|---:|---:|
| Saved moments | 182 | 182 |
| Distinct image payloads | 182 | 146 |
| Image bytes | 63,891,601 | 52,596,561 |
| Archive bytes, including database | 67,717,371 | 56,459,091 |

The 36 redundant copies accounted for **11,295,040 bytes: 17.7% of image storage**. The database grew slightly for the deduplication index and per-frame fields. Archive totals include transient SQLite files at measurement time, so the displayed total can vary slightly after closing the database.

First tested on an independent archive copy: every image's SHA-256 and all original frame columns matched before and after. A second optimization was idempotent. The copy optimization took **375.6 ms**, including CLI startup. The same integrity checks passed when applied to the live archive. The original backup remains outside the archive; retaining it means these archive savings do not equal net disk space freed across all backups and test copies.

Sharing is automatic for newly saved identical JPEGs. Every timestamp and OCR record remains separate. There is no additional lossy encoding, resolution reduction or change to capture thresholds. Hash matches are verified byte-for-byte before linking. Files are treated as immutable; deletions unlink only the selected frame.

## Runtime experiment

Imported the same 1920×1080 screenshot eight times into a fresh archive for each executable (previous installed build, then new build). Each invocation includes process startup, image decoding, Vision OCR, JPEG encoding and archive insertion. Twenty CLI searches followed each run.

| Measurement | Previous build | New build |
|---|---:|---:|
| Median import duration | 791.8 ms | 781.4 ms |
| Median CLI search, 8-row archive | 10.9 ms | 8.4 ms |
| Image storage for 8 identical imports | 2,477,976 bytes | 309,747 bytes |

Import timing is essentially unchanged; the small differences and search timing can be affected by warm caches and scheduling. This demonstrates duplicate storage avoidance, not a statistically established speed improvement. OCR still runs for each accepted capture. Sustained recording CPU, energy, and long-session RSS were **not measured** in this run.

The SwiftUI image cache now has an estimated **64 MiB cost limit** plus a 16-entry limit. At 1920×1080, one four-byte-per-pixel decoded image costs about 7.9 MiB. NSCache limits are advisory and exclude other image representations and app memory; no total RAM reduction is claimed without profiling.

## Codec experiment — not enabled

Eight time-spaced screenshots, 24 re-encodes with ImageIO; OCR measured using Apple Vision accurate recognition. The inputs were already compressed JPEGs, not original raw captures. These are single passes, not statistically controlled microbenchmarks.

| Re-encoding | Smaller than input JPEG | Median encode | Median decode | OCR token recall, mean / minimum |
|---|---:|---:|---:|---:|
| HEIC 0.70 | 53.8% | 24.4 ms | 15.8 ms | 98.1% / 94.6% |
| HEIC 0.86 | 40.9% | 22.0 ms | 16.5 ms | 97.9% / 95.2% |
| JPEG 0.70 | 25.5% | 9.4 ms | 5.1 ms | 96.8% / 91.9% |

OCR recall means the fraction of distinct tokens from the original JPEG's OCR also recognized in the re-encoded image. It does not measure visual fidelity, newly hallucinated tokens, or ground-truth accuracy. HEIC was substantially smaller but slower to decode than the tested JPEG variant, and OCR differed on several samples. Codec quality numbers are not equivalent between formats. Existing JPEG quality remains 0.86; no archive images were re-encoded.

HEVC video chunks may compress repeated screens more effectively, but would require a different archive, random-access decoding and careful deletion/retention behavior. Coast's aggregate storage numbers are not a controlled comparison, so this report makes no claim that Afterimage matches its storage efficiency.

## Verification and reproduction

- Build and CTest: core archive/search/retention/concurrency, OCR CLI integration, legacy v1 storage migration, idempotency and deleting shared images.
- SwiftUI smoke checks: regular/compact, empty/populated, image loading, search, storage counts, onboarding gates and timeline mouse/trackpad handlers.
- `afterimage optimize` returns before/after statistics. Test against a copy using `AFTERIMAGE_HOME=/path/to/copy`.
- `scripts/benchmark-codecs.swift` accepts a JSON array of input image paths and an output JSON path. It does not modify input images or emit recognized text. Run with `xcrun swift scripts/benchmark-codecs.swift inputs.json results.json`.

[Machine-readable measurements](storage-optimization-results.json).
