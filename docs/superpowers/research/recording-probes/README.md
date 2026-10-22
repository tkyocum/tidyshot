# Recording probes (2026-10-22)

Run each with `xcrun swiftc -O -target arm64-apple-macos26.0 -o <name> <name>.swift && ./<name> <args>` from a shell that has Screen Recording permission. Results are in the recording design document.

- `record-area.swift`: records an 800x500 pt area with system audio to an MP4 through `SCRecordingOutput` (needs an AppKit run loop).
- `record-window.swift`: draws a scrolling page in its own window and records only that window at Retina size.
- `poster-frame.swift`: the first frame of an MP4 through `AVAssetImageGenerator`.
- `clop-video.swift`: sends a copy of an MP4 through TidyShot's `ClopClient` (compile it with `TidyShot/Upload/ClopClient.swift`) and describes the file before and after.
- `image-assumptions.md`: every place the app assumed a capture is an image, before R1.
