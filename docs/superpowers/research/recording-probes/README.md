# Recording probes (2026-10-22)

Run each with `xcrun swiftc -O -target arm64-apple-macos26.0 -o <name> <name>.swift && ./<name> <args>` from a shell that has Screen Recording permission, with `-o` pointing outside the repository (for example `-o /tmp/<name>` and `/tmp/<name> <args>`). Results are in the recording design document.

- `record-area.swift`: records an 800x500 pt area with system audio to an MP4 through `SCRecordingOutput` (needs an AppKit run loop).
- `record-window.swift`: records one window at its display's scale, as a window recording does (`ignoreShadowsSingleWindow`, `scalesToFit`, `preservesAspectRatio`). Arguments `<output> [seconds] [audio] [window <id>]`:
  - by default it draws a scrolling page in its own resizable, minimisable and closable window and records that for 10 s;
  - `seconds` sets the length, `audio` turns on `capturesAudio` with `excludesCurrentProcessAudio`, and `window <id>` records another app's window instead (the id from `CGWindowListCopyWindowInfo`, for example through a window-list tool);
  - it prints every `SCRecordingOutputDelegate` and `SCStreamDelegate` callback with a timestamp and `recordedDuration`, and once a second `recordedDuration` and whether `CGWindowListCopyWindowInfo(.optionIncludingWindow, id)` lists the window and its `kCGWindowIsOnscreen`;
  - it stops at the end, unless the stream stopped by itself, waits up to 15 s for the finish callback, and prints the file's duration, tracks and natural size.

  For the window-change checks: resize, move, move to another display, minimise, hide (⌘H), switch Space and close the window during the run, and write down what each prints. With `audio`, play a sound in another app (`afplay /System/Library/Sounds/Submarine.aiff`) and check whether the file has a `soun` track and that sound.
- `poster-frame.swift`: the first frame of an MP4 through `AVAssetImageGenerator`.
- `clop-video.swift`: sends a copy of an MP4 through TidyShot's `ClopClient` (compile it with `TidyShot/Upload/ClopClient.swift`) and describes the file before and after.
- `record-stop-order.swift`: modes `area` (stop order on a small area), `full` (fullscreen at 2x; edit the width and height for the 4096 cap), `kill` (`kill -9` five seconds in, then the file is checked by hand) and `watch`. Arguments `<mode> <output>`, and for `watch` an optional length in seconds (default 180). Prints when `stopCapture()` returns against `recordingOutputDidFinishRecording`, and whether the file opens.
  - `watch` records the `area` mode's rect with audio. It prints every stream and output callback with a timestamp and `recordedDuration` (`streamDidBecomeActive` and `streamDidBecomeInactive` included), and each change of the frames' `SCFrameStatus`. At the end, or after the stream stops by itself, it stops if still running, waits up to 15 s for the finish callback and prints the file's duration and tracks.
  - For the sleep and lock checks, run it through each of ⌃⌘Q, a hot-corner display sleep, a system sleep, a lid close and a fast user switch, and write down the callbacks, the frame statuses and whether the file plays.
- `clop-raw-reply.swift`: sends one file to Clop's port and prints the raw reply (an empty `[]` means Clop skipped it), with an optional `removeAudio` argument.
- `image-assumptions.md`: every place the app assumed a capture is an image, before R1.

The sandbox spike is not here: it runs inside the Debug app (`TidyShot/Recording/RecordingSpike.swift`), with `open .build/Build/Products/Debug/TidyShot.app --args -RecordingSpike YES`, and logs `Recording spike: …` (`/usr/bin/log show --last 2m --style compact --predicate 'process == "TidyShot"' | grep "Recording spike"`). The file goes to the container's `tmp/RecordingSpike`.
