# TidyShot screen recording: design (R1 settled 2026-10-22)

Section 6 of the screenshot design (`2026-10-19-tidyshot-screenshot-design.md`) said recording gets its own design document and reuses Uploader, Naming, History and Overlay. This is that document.
- **R1** is settled below and is built on the branch `recording-r1`, stacked on `phase-7c-background`.
- **R2 and R3** are listed at the end and are not designed yet.

Tim's direction (2026-10-22):
- Carry on.
- Videos go through Clop like screenshots.
- Defaults are Claude's call, flagged in the PR.

The map of every place the app assumes an image is in `docs/superpowers/research/recording-probes/image-assumptions.md`. File:line references below are from that map.

## Probes (2026-10-22, Tim's Mac, macOS 26, sources in `docs/superpowers/research/recording-probes/`)

**Recording.** `SCStream` plus `SCRecordingOutput` (macOS 15 and later) writes straight to an `.mp4`, with H.264 (`avc1`) or HEVC (`hvc1`).
- It must run with an AppKit run loop: a bare command-line probe trapped in ScreenCaptureKit, while an `NSApplication` probe ran.
- Start took 0.25 s.
- A 4 s, 800×500 pt area at 2x and 30 fps, with system audio, came out as 0.97 MB, with `soun` and `vide` tracks (`record-area.swift`).
- A 10 s recording of a scrolling text window at 2560×1664 px was 20.2 MB, about 15.6 Mbit/s (`record-window.swift`).

**Poster frame.** `AVAssetImageGenerator.image(at: .zero)` with `maximumSize` 800 took 117 ms (`poster-frame.swift`).

**Clop and video.** The existing port and request (`ClopClient.optimise`, with `hideFloatingResult`) took that 20.2 MB file to 4.2 MB, 79% smaller, in 2.4 s (`clop-video.swift`).
- The result kept the same path, codec (avc1), pixel size (2560×1664), frame rate (29.3 fps) and duration (10.33 s, then 10.35 s), with `convertedFrom` nil.
- The reply had `newWidthHeight` nil.
- That is about 4× faster than real time with Tim's Clop video setting (`videoCompression` fast, factor 50).
- Clop skips `com.apple.m4v-video` and `org.matroska.mkv`, so recordings are `.mp4`.

## R1 behaviour

### Starting

- **Status menu.**
  - `Record Screen  ⌃⇧8` comes after `Capture Text`. It opens the selection overlay in a new `SelectionMode.recording`, which behaves exactly as `.selfTimer`: a drag records an area and a click records the highlighted window.
  - `Record Fullscreen` follows it, with no default shortcut. It records the display under the pointer.
  - Both are disabled while a capture runs, like every capture item.
- **Shortcuts tab.** It gets `Record screen:` (⌃⇧8) and `Record fullscreen:` (none) after `Capture text:`. The shortcut names are `recordScreen` and `recordFullscreen`.
- **Areas.** An area is clamped to its display. An area under 32×32 pt is refused with `Select a larger area to record.`
- **Count-in.** With `Count down before recording` on (Capture tab, default on), the self-timer badge counts 3, 2, 1 over the area or window, using `SelfTimerController` and its stage. During the count-in, Escape (`cancelCapture`) cancels, as it does for the self-timer.
- **Lock.** The capture lock (`withCaptureLock`) is held from the selection to the end of the recording, as the scrolling capture holds it. Hide desktop icons while capturing applies (`coversDesktop: true`); the covers stay up for the whole recording and are included in it.

### While recording

- **Stream.**
  - An area records `SCContentFilter(display:excludingWindows:)` with `sourceRect`.
  - Fullscreen records the display with the same exclusions.
  - A window records `SCContentFilter(desktopIndependentWindow:)`.
- **Excluded windows.** These are TidyShot's frame window, control panel and Quick Access cards, by window number through `OverlayWindowLookup`. The desktop covers are not excluded.
- **Output size.** It is the source size in points times the display's backing scale with `Retina` (default), or times 1 with `Standard`, rounded to even pixels.
- **Frame rate.** `minimumFrameInterval` is 1/30 s by default, or 1/60 s.
- **Cursor and audio.** `showsCursor` follows `Show cursor in recordings` (default on). `capturesAudio` follows `Record system audio` (default off), and `excludesCurrentProcessAudio` is true.
- **Output.** `SCRecordingOutputConfiguration` writes `outputFileType = .mp4`, `videoCodecType = .h264` to the container's `tmp/Recording/<record id>.mp4`.
- **Frame.** The scrolling capture's dashed `ScrollAreaFrameWindow` outlines an area or window recording. A fullscreen recording has none.
- **Control panel.** `RecordingPanel` is a non-activating, borderless, floating `NSPanel` on all Spaces that never becomes key. It is placed by `ScrollPanelGeometry`, or at the bottom centre of the display for fullscreen.
  - It shows the elapsed time as `0:00`, or `1:02:03` past an hour, updated each second. The time turns orange from 5:00, the soft limit, with no hard stop.
  - It has a `Stop` button (`stop.fill`) and a `Cancel` button (`xmark`, with the tool tip `Discard the recording`).
- **Status item.** The icon becomes `record.circle`. The menu's first item is `Stop Recording  ⌃⇧8`, with every capture item disabled below it.
- **Stopping.** The `recordScreen` shortcut, the `recordFullscreen` shortcut, the panel's Stop and the menu item all stop the recording. The shortcuts reach the controller before the capture lock, as `captureScrolling` does with `advance()`.
- **Escape.** It is not taken during the recording, because the user's own apps need it. Only the count-in enables it.
- **Failures.**
  - `SCStream` stopping with an error, or `recordingOutput(_:didFailWithError:)`, ends the recording.
  - If the file has a playable video track longer than 0.5 s, it is kept and saved like a stopped recording, with the notification `Recording stopped` and the body as the error's description.
  - Otherwise the notification is `Recording failed` with the description, and the file is removed.
- **Free space.** When free space in the container volume falls under 1 GB during the recording (checked every 5 s), the recording stops itself and is saved, with `Recording stopped` and `Your disk is almost full.`

### After stopping

`saveRecording(_ recording: Recording, intent:)` is a new funnel beside `save(_:intent:)`. `Recording` holds the file URL, pixel size, duration, display ID and poster frame. It follows the after-capture action:

| Action | Where the file goes | Upload | Clipboard |
|---|---|---|---|
| `.save` | moved into the save folder under the security scope, named by the recording template, `.mp4` | none | a file reference, when the copy setting is on |
| `.upload` | moved into the save folder | uploaded from the save-folder file | the URL when the upload finishes; a file reference meanwhile, when Also copy is on |
| `.uploadOnly` | moved to `pending/<id>.mp4` | uploaded from the pending file | the URL when the upload finishes |

- **Naming.** The file name comes from `recordingFileNameTemplate`, a new General-tab field `Recording file name`, default `Recording {date} at {time}`. It uses the same token engine and counter as screenshots. The extension is `mp4` and the content type `video/mp4`, for both the file and the object key.
- **No folder.** With no save folder set, `.save` and `.upload` ask for one as screenshots do. If the user cancels, the recording goes to `pending/` and the record keeps it: the same "never lose a capture" rule.
- **Record.** It has `mediaKind: .video` and `durationSeconds`, and its pixel size is the video's. The poster frame becomes the thumbnail through `makeThumbnail(from:for:)`. `showOverlay` gets the poster for the card, but `latestCapture` is never set for a video. `lastCaptureURL` is set as for a screenshot.
- **Feedback.**
  - Play sound plays the shutter when the recording stops.
  - Notifications: `Recording saved`, with the file name, for `.save`; `Uploaded, URL copied` as today. A click reveals the file or opens the URL.
- **Clop.** With `Optimize images and videos with Clop` on (the renamed setting) and Clop running, the upload sends Clop's result.
  - A copy goes in the container's `tmp/Clop` as `<UUID>.mp4`.
  - The receive timeout is `60 + 3 × duration` seconds.
  - The result is accepted only when all of these hold: the reply's path is the work file; `convertedFrom` is nil; the file opens with `AVURLAsset` and has one video track of the same natural size; the duration is within 0.5 s of the original; and the file is smaller.
  - Otherwise the original uploads and one line is logged: `Clop: <reason>, uploading the original`.
  - The save-folder or pending file stays as recorded, as for screenshots. A video waiting for Clop counts in `clopWaitsPerLane` like an image.

### Uploading a file

- **Payload.** `UploadJob` carries `enum UploadPayload: Sendable { case data(Data), file(URL) }` instead of `data`. Screenshots keep `.data`; recordings use `.file`.
- **Destination.** `Destination` gets `upload(fileAt url: URL, key:contentType:cacheControl:progress:)`. In `S3Destination` it:
  - hashes the file with an incremental `SHA256` over 4 MB reads, off the main actor, so the signed `x-amz-content-sha256` is the real hash;
  - sends it with `session.upload(for:fromFile:delegate:)`;
  - sets `Content-Length` from the file's size.
- **Retries** re-send from the file. Nothing loads a video into memory: not upload, retry, Copy URL, Reveal, drag-out from a local file, Save As… from a local file, or the thumbnail.
- **Size.** A single PUT is used up to S3's 5 GB limit. A file over 5 GB is refused with `The recording is larger than 5 GB, too large to upload in one piece.` and stays local. Multipart is R2.
- **Queue.** The upload queue stays serial, so a video upload delays the next screenshot's upload. R2 may give videos their own lane.
- **Progress.** Events are throttled to at most 10 per second.

### Videos in the rest of the app

Image-only actions are hidden for `mediaKind == .video`, never offered and then failed:
- **Hidden:** Annotate, Pin, Copy Image.
- **Hidden on cards and rows:** the overlay's Copy Image and Annotate.
- **Refused:** `intent.then` (annotate or pin) and URL `action=annotate|pin`, which do not apply.

What changes for videos:
- **`EditorInput.source`** returns `.unavailable` for a video.
- **Quick Access card:**
  - the poster thumbnail with a `play.fill` badge and the duration (`0:42`) in the corner;
  - a click on the thumbnail opens the file in the default app (QuickTime) when there is a local file, or the URL when there is only an upload;
  - Save As… offers `.mpeg4Movie` and copies the file, or downloads it to the chosen URL with a file download, not into memory;
  - drag-out uses the file;
  - the card stays until the upload ends, as today.
- **Recent Captures:**
  - rows show the poster with the badge;
  - the hover preview shows the stored poster at its size, and never reads the video file;
  - a row click copies the link or the file as today.
- **`ThumbnailProvider`** never reads a video file. A video with no stored thumbnail shows the `film` symbol.
- **`DragFileName`** keeps the key's own extension and adds `.png` only to images. The fallback name uses the record's extension.
- **Retention and delete** treat the video like any capture file. Deleting removes the save-folder file, the pending file and the uploaded object, as for screenshots.
- **Captions** that say PNG or image get media-neutral wording where they cover both:
  - General's upload-only caption becomes `The file is kept inside TidyShot only until the upload succeeds…`;
  - Upload's key caption becomes `The file's extension (.png or .mp4) is added.`;
  - the Clop toggle becomes `Optimize images and videos with Clop`.

### Settings (R1)

- **Capture tab, new section `Recording`:**
  - `Frame rate` (`30 fps`, default, or `60 fps`);
  - `Resolution` (`Retina`, default, or `Standard`);
  - `Record system audio` (off);
  - `Show cursor in recordings` (on);
  - `Count down before recording` (on).
- **General tab:** `Recording file name` under `File name`.
- **Shortcuts tab:** the two recorders.
- **New `AppSettings` keys:** `recordingFrameRate` (30), `recordingRetina` (true), `recordingSystemAudio` (false), `recordingShowsCursor` (true), `recordingCountdown` (true), `recordingFileNameTemplate` (`Recording {date} at {time}`).

No new entitlement. System audio needs none, and the microphone is R2.

### Architecture (R1)

**New files.**
- `TidyShot/Recording/`:
  - `RecordingController.swift`: the session; it owns the stream, output, panel, frame, timer and disk check, and ends with a `RecordingOutcome`.
  - `RecordingConfiguration.swift`: pure; source to stream configuration, output size, filter choice.
  - `RecordingPanel.swift` and `RecordingPanelView.swift`.
  - `RecordingClock.swift`: pure elapsed-time formatting and the 5:00 soft limit.
  - `Recording.swift`: the value handed to `saveRecording`.
  - `PosterFrame.swift`: `AVAssetImageGenerator`, `@concurrent`.
  - `VideoValidation.swift`: an `@concurrent` asset check used by the Clop path and the failure path.
- `TidyShot/Upload/UploadPayload.swift`, plus a file-hashing helper in `S3Signer` (`sha256Hex(fileAt:)`, incremental).

**Edits.**
- `UploadJob`, `UploadQueue`, `Destination` and `S3Destination` (file upload), `ClopOptimiser` (`optimisedVideo(at:duration:)`).
- `CaptureRecord` (`mediaKind`, `durationSeconds`, with defaults so old history decodes).
- `AppCoordinator`: `recordScreen`, `recordFullscreen`, `saveRecording`, `startUpload` taking a payload, `readLocalFile` gone in favour of payloads, retry from the file, media checks on every image action.
- `SelectionMode.recording`, `StatusMenuController` (items, recording state, icon), `Shortcuts`, `ShortcutsSettingsView`, `CaptureSettingsView`, `GeneralSettingsView`, `UploadSettingsView`, `AppSettings`.
- `QuickAccessView` and `QuickAccessModel`, `RecentCaptureRow` and `RecentCaptureFormatting`, `ThumbnailProvider`, `DragFileName`, `EditorInput`, `SaveLocation` (move a file in, under the scope), `PendingFileStore` (move a file in).

**Concurrency.** The 2.6 rule holds: hashing, poster frames, asset checks and Clop run off the main actor; the controller, panel and settings are MainActor. `SCRecordingOutputDelegate` and `SCStreamDelegate` callbacks hop to the main actor.

### Tests (R1, Swift Testing)

- `RecordingConfigurationTests`: area to `sourceRect` and pixel size at 2x Retina and Standard (even rounding); window and fullscreen filters chosen; 30 and 60 fps intervals; cursor and audio from the settings; the area minimum.
- `RecordingClockTests`: `0:00`, `0:59`, `1:00`, `59:59`, `1:00:00`; the soft limit at 300 s.
- `UploadPayloadTests` and additions to `UploadQueueTests`:
  - a `.file` job uploads through `upload(fileAt:)` with the given type and extension;
  - a retry re-sends from the file;
  - the key gets `.mp4`.
- `S3SignerTests`:
  - the file hash equals the one-shot hash for 0 bytes, 1 byte, exactly 4 MB, and 4 MB + 1;
  - the signed request for a file carries that hash and the content length.
- `S3DestinationTests`: a file upload through a URLProtocol stub sends the file's bytes.
- `ClopOptimiserTests` (video, with a fake transport and generated MP4 fixtures from `AVAssetWriter`):
  - accepted;
  - a different path refused;
  - converted refused;
  - a different size refused;
  - a duration off by more than 0.5 s refused;
  - not smaller refused;
  - not playable refused;
  - the timeout from the duration.
- `CaptureRecordTests`: old JSON without `mediaKind` decodes as `.image`; a video record round-trips.
- `RecentCaptureFormattingTests`, `EditorInputTests` and `QuickAccessModelTests`: no Annotate, Pin or Copy Image for a video; `.unavailable` for a video.
- `DragFileNameTests`: an `.mp4` key keeps its name; the fallback uses the record's extension.
- `ThumbnailProviderTests`: a video record never reads its file.
- `AppSettingsTests`: the six keys.
- `VideoValidationTests`: with generated fixtures.

The hand checks go in `docs/testing/recording-r1-manual-checklist.md`.

## R2 and R3 (not designed)

- **R2:**
  - microphone (entitlement `com.apple.security.device.audio-input`, `NSMicrophoneUsageDescription`, a TCC prompt);
  - GIF export;
  - trim before upload;
  - Pause;
  - S3 multipart for files over 5 GB, with resumable uploads;
  - a separate upload lane for videos;
  - URL commands `record-screen` and `stop-recording`.
- **R3:** click highlights, keystroke overlay, webcam bubble.
