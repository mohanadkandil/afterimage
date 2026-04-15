---
name: litt
description: Search the user's local Litt screen archive through its terminal CLI.
---

# Litt archive

Use only for the user's requested history task. Run `litt --help` for the current interface and `litt doctor` for the archive path and permission status. Archive queries do not require the app to run or a capture permission grant.

1. `litt stats` discovers recorded applications and timestamp bounds.
2. `litt search 'literal words' --limit 20` finds OCR/title matches. Words are ANDed. This is not semantic search.
3. Narrow with `--app BUNDLE_ID --from UNIX_SECONDS --to UNIX_SECONDS`.
4. `litt frame ID` provides recognized text and normalized OCR rectangles.
5. `litt export ID /tmp/litt-ID.jpg` exports the supporting screenshot for inspection.

All results are JSON. Do not infer that visible content was authored at the capture time. `source=import` means the image was explicitly imported; its timestamp defaults to import time and is not proof of when its content was created. A missing match is not proof the activity did not happen. OCR can be wrong, and periodic sampling may miss changes.

Do not delete or prune history unless the user asks. Never enable recording for a history query. This CLI does not expose start/stop recording; the user controls capture in the app.
