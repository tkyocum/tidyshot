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

## R2 probes (2026-10-23)

Results are in the R2 design (`docs/superpowers/specs/2026-10-23-tidyshot-screen-recording-r2-design.md`, Probes). Build each with the `xcrun swiftc` line above and `-o` outside the repository (below, `$W` is a work folder outside it). The recordings they read and the outputs they write are not committed. A probe that records needs Screen Recording permission (and Microphone for `mic`, `mic2` and `mute-offset-mic`); run those from a shell that has it.

Muting and trimming:

- `mute-empty-edit.swift <src.mp4> <out.mp4> <muteStart> <muteEnd>`: the rejected mute. A passthrough `AVAssetExportSession` of a composition whose audio has an empty time range over the stretch; prints the output's segments and the audio's peak inside and outside the stretch. Readers that ignore the empty edit play earlier sound there.
- `mute-rewrite.swift <src.mp4> <out.mp4> <muteStart> <muteEnd>`: the mute that works. Video samples pass through untouched, the audio is decoded to 16-bit PCM, zeroed over the stretch in a copy and re-encoded to AAC, in one `AVAssetReader` and `AVAssetWriter` pass. It copies with `CMBlockBufferCreateContiguous` and flags 0, which can return the reader's own memory when the source is contiguous; TidyShot passes `kCMBlockBufferAlwaysCopyDataFlag`.
- `trim.swift <in.mp4> <start> <end>`: `AVAssetExportSession` passthrough and `HighestQuality` exports of the range, with each one's time, duration, tracks and size. It writes `trim-pass.mp4` and `trim-hq.mp4` into the current directory, so run it from `$W`.
- `trim-reencode.swift <in.mp4> <start> [output folder]`: the trim probe. Prints each track's edit list, the video track's sync samples from `AVSampleCursor`, and what a cursor reads at the start as given and through the edit. Then exports from the start to the end three ways, with passthrough, with `HighestQuality`, and with `HighestQuality` and a video composition of the asset's properties, and prints each one's time, size, `fractionCompleted` readings, video size, and what the output keeps before the start in decode order, which ignores the edit list: video samples, and audio packets and sample frames. It writes `trim-pass.mp4`, `trim-hq.mp4` and `trim-hq-composed.mp4` into the output folder (default the current directory), so give it `$W`.
- `r2-review/rewrite.swift <in> <out> <muteStart> <muteEnd>`: the review's first rewrite, with 32-bit float PCM zeroed in place in the reader's buffer. Superseded by `mute-rewrite.swift`.
- `r2-review/elst.py <file.mp4>`: prints `mvhd`, `mdhd`, `hdlr`, `elst`, `stss`, `stsz`, `stts` and `stsd` for each track, to read the edit lists of a muted or trimmed file.

Microphone and mute timing:

- `mic.swift <output.mp4>`: records an area for 6 s with system audio and the microphone through `SCRecordingOutput`, switching `captureMicrophone` off at 2 s and on at 4 s with `updateConfiguration`; prints the microphone permission, the microphones, and the file's tracks with their channels and time ranges.
- `mic2.swift <output.mp4> <both|mic>`: the same for 4 s without the switching, with system audio and the microphone (`both`) or the microphone alone (anything else).
- `mute-offset.swift <output.mp4>`: records a 300 x 300 pt area with system audio while a window flashes white and black and a 50 ms 1 kHz tone plays at 1, 2, 3 and 4 s after the main-actor hop that follows `recordingOutputDidStartRecording`; prints those times and writes `<output.mp4>.tone.wav`.
- `mute-offset-mic.swift <output.mp4> <microphone UID> <output device UID|default> [latency]`: the same through the microphone, with events at 6 to 9 s after the hop and the tone played on the given output device for the microphone to hear.
  - It first prints the input's CoreAudio latency, property by property (device latency, safety offset and buffer frame size on the input scope, the first input stream's latency, the nominal sample rate and the transport type), then what TidyShot's `MicrophoneLatency.read` gives and the mute lag `MicrophoneLatency.lag` makes of it. With `latency` as the fourth argument it stops there and records nothing, so it needs no permission.
  - It compiles with `TidyShot/Recording/MicrophoneLatency.swift`, and `swiftc` takes top-level code from more than one file only in `main.swift`, so build it from this folder as `mkdir -p $W/mic && cp mute-offset-mic.swift $W/mic/main.swift && xcrun swiftc -O -target arm64-apple-macos26.0 -o $W/mute-offset-mic $W/mic/main.swift ../../../../TidyShot/Recording/MicrophoneLatency.swift`.
- `mute-offset-onsets.py <file.mp4>`: reads the file's audio with `ffmpeg` and `ffprobe` and prints, for four events starting at second `K0` (environment variable, default 1; use 6 for `mute-offset-mic.swift`), when the tone first rises above the noise, to compare with the times the probe printed.
- `audio-devices.swift`: no arguments. Lists every CoreAudio device with its UID, input and output channel counts, input and output latency in frames and output buffer size, for the input-latency check.

GIF:

- `togif.swift <in.mp4> <out.gif> <fps> <maxSide>`: the ImageIO path: `AVAssetImageGenerator` frames, scaled with `interpolationQuality = .high`, added to a `CGImageDestination`. Prints frames, size, time and sizes, and writes `<out.gif>.mid.png`.
- `r2-review/gifmem.swift <frames> <fps> <out.gif>`: ImageIO's memory while it makes a GIF of `<frames>` synthetic 1280 x 832 frames whose colours change from frame to frame, with its default (global) colour table. Prints the footprint as frames are added and after `CGImageDestinationFinalize`, then the frame count and delays.
  - `gifmem2.swift` (same arguments): `kCGImagePropertyGIFHasGlobalColorMap` false, so each frame has its own table.
  - `gifmem3.swift`: the per-frame tables, with the blue channel fixed (0, then 1) in each half of the run instead of changing every frame.
  - `gifmem4.swift`: the default table with those fixed-blue frames.
- `r2-review/genbench.swift <in.mp4>`: reads every frame at 15 fps with `AVAssetImageGenerator.image(at:)` and with `images(for:)` and prints the time of each.
- `r2-review/order.swift <in.mp4>`: asks `images(for:)` for 150 frames at 15 fps and prints whether the results arrive in the order requested and the largest difference between actual and requested times.
- `r2-review/gifasset.swift <file>`: loads the file as an `AVURLAsset` and prints `isPlayable`, the duration and the tracks, to see how AVFoundation treats a GIF.
- `gif-encoder-spike/`: TidyShot's own encoder, written from the GIF89a format, with its `RESULTS.md`. Build `gifspike.swift` with the line above (`RESULTS.md` used `-swift-version 6 -default-isolation MainActor` and `gifspike` as the name) into `$W/gifspike`.
  - `gifspike encode <in.mp4> <out.gif> [--fps 15] [--max 1280] [--samples 32] [--colors 255] [--split sqrt|count] [--lloyd 4] [--minsigma 0] [--keep 0] [--trans auto|always|never] [--stats]`: our encoder; the design's defaults are `--minsigma 2 --keep 4`. It writes `<out.gif>.meta.json`, `.src.rgba` and `.exp.rgba` beside the GIF.
  - `gifspike imageio <in.mp4> <out.gif> [--fps 15] [--max 1280] [--global]`: the ImageIO baseline, with one global palette for `--global`; it writes the same `.meta.json` and `.src.rgba`.
  - `gifspike validate <out.gif> [--zoom 2] [--cw 300] [--ch 180] [--cx <x> --cy <y>] [--full]`: reads the files `encode` or `imageio` wrote beside the GIF, decodes it with `CGImageSource`, prints the frame count, delays and error figures as JSON (also `<out.gif>.validate.json`) and writes crop images.
  - `gifspike probe <in.mp4>...`: prints size, duration and video sample count.
  - `measure.sh <work folder>` and `ablate.sh <work folder>`: reproduce the tables in `RESULTS.md`. The folder holds `window.mp4`, `p-area.mp4`, `p-4096.mp4` and the built `gifspike`; they write `final/` and `abl/` in it.
  - `xdecode.py <out.gif>...`: decodes each GIF with the `ffmpeg` and `magick` binaries and compares the middle frame with the `.exp.rgba` that `encode` wrote.
