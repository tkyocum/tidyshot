# Phase 7b probes (2026-10-21)

Run with `xcrun swiftc -O -target arm64-apple-macos26.0 -o <name> <name>.swift && ./<name>`. Results are in spec 2.10.

- `ocr.swift`: Vision text and barcode recognition on a generated image, with timings.
- `cgl.swift`: desktop-level windows from `CGWindowListCopyWindowInfo` and the desktop picture URL (no permission needed).
- `wid.swift`: window ids of the desktop-level windows, for `screencapture -l`.
- `sck.swift`: the same windows as ScreenCaptureKit lists them (needs Screen Recording).
- `cover.swift`: captures the wallpaper window, shows a cover above the icons and widgets, and measures when a display capture sees it (needs Screen Recording).
