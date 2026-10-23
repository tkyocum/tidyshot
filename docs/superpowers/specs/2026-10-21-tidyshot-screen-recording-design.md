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

**Stop order.** `record-stop-order.swift` (modes `area` and `full`) logged when `stopCapture()` returned against `recordingOutputDidFinishRecording`, and tried to open the file in between.
- On a 1200×800 px area, the finish callback arrived 9 ms before `stopCapture()` returned.
- On a 5120×2880 px fullscreen, `stopCapture()` returned 290 ms before the finish callback. In that gap `AVURLAsset` could not open the file (`Cannot Open`). After the callback it read 4.18 s, with `soun` and a 5120×2880 `vide` track.
- `recordedDuration` read 3.0 s and 4.0 s at the stop, against file durations of 3.05 s and 4.18 s.
- So the stop waits for the finish callback (see Stopping), and `Recording.duration` comes from the file.

**Large output.** `SCRecordingOutput` encoded H.264 at 5120×2880 without error, and the file plays (`record-stop-order.swift`, mode `full`).
- Clop did not take it. It returned an empty reply (`[]`) in about 1 s, with or without `removeAudio: false`, and left the file unchanged (`clop-raw-reply.swift`).
- A 4096×2304 recording of the same screen went from 12.7 MB to 3.8 MB, 70% smaller, in 1.7 s.
- So Output size caps the longer side at 4096 px. The cap is for Clop and for players that cannot take larger H.264, not for the encoder.

**Kill.** A recording killed with `kill -9` 5 s in left a playable MP4 of 5.23 s, with `soun` and `vide` tracks (`record-stop-order.swift`, mode `kill`). A crash or a forced quit leaves a recoverable file, and the launch check recovers it (see Relaunch after a crash).

**Clop with audio.** A 1200×800 recording with an AAC track went from 370 KB to 323 KB and kept its audio track (`vide` and `soun`), with `removeAudio` unset.
- Clop's own "Remove audio on optimised videos" preference is not set in Tim's defaults, so this does not show whether `removeAudio: false` overrides it. Video requests send it anyway, and the audio-track check stays (see Clop).
- The 79% figure above is for a silent file.

**Sandbox.** Every probe above ran unsandboxed. A spike in the sandboxed Debug app (`RecordingSpike`, launched with `-RecordingSpike YES`) recorded 3 s of an 800×500 pt area centred on the 2x main display, with system audio, through `SCRecordingOutput` to the container's `tmp/Recording`. It matched the unsandboxed probes, with no new entitlement.
- Two runs gave 3.20 s and 3.11 s files, 0.70 MB and 1.81 MB. Each had a 1600×1000 H.264 (`avc1`) `vide` track at about 29 fps and an AAC `soun` track, and played.
- Both `soun` tracks carry sound, not silence (peaks of 4,322 and 11,734 of 32,767), so system audio reaches the file under the sandbox.
- The output started 26 ms after `startCapture`. The finish callback arrived 14 ms after the stop was requested.
- `NSLog`'s text shows only as `<private>` in `log show`, so the spike logs through `Logger` with public text. The app's `Recording:` lines need the same, or `log show | grep "Recording:"` finds nothing.
- With only a recording output on the stream, ScreenCaptureKit logs `stream output NOT found. Dropping frame` at error level for every sample (246 lines in 3 s). The file is unaffected.

**Still to probe.** These are hand checks in the R1 checklist, with `record-window.swift` and `record-stop-order.swift watch` (see the probes README). The rules below hold whatever they show.
- **Window changes.** `record-window.swift` prints every callback and `recordedDuration`, and once a second whether the window is listed and on screen. Resize, move, minimise, hide (⌘H), change Space and close the window. Also record whether a window recording with `capturesAudio` carries other apps' sound.
- **Sleep and lock.** Run `record-stop-order.swift watch` through each of: ⌃⌘Q, a hot-corner display sleep, a system sleep, a lid close and a fast user switch. Record what `didStopWithError`, `didFailWithError` and the frame status report, and whether the file plays. Also record whether a finish or a fail follows each `didStopWithError`, and how soon: without one, the stop wait runs its full 15 s (Stopping).

## R1 behaviour

**Decided for Tim to review.** Claude settled these; the PR flags them.
1. A screen lock (⌃⌘Q) does not stop a recording. System sleep and a user switch do (Sleep and user switch).
2. A recorded window that is minimised, hidden or moved to another Space keeps recording. Only a closed window ends it (Window recordings).
3. After a video upload, the URL replaces the clipboard only if the clipboard has not changed since the save. Otherwise the clipboard is left alone, and a click on the `Uploaded` notification copies the link (Clipboard after the upload).
4. A video with a local file gets `Copy File` on its card and its Recent Captures row. For a pending file it references a drag-folder copy, so the reference outlives the upload (Quick Access card).

### Starting

- **Status menu.**
  - `Record Screen  ⌃⇧8` comes after `Capture Text`. It opens the selection overlay in a new `SelectionMode.recording`, which behaves exactly as `.selfTimer`: a drag records an area and a click records the highlighted window.
  - `Record Fullscreen` follows it, with no default shortcut. It records the display under the pointer.
  - Both are disabled while a capture runs, like every capture item.
- **Shortcuts tab.** It gets `Record screen:` (⌃⇧8) and `Record fullscreen:` (none) after `Capture text:`. The shortcut names are `recordScreen` and `recordFullscreen`.
- **Areas.** An area is clamped to its display. An area under 32×32 pt is refused with `Select a larger area to record.` An area recording does not become the previous area (`lastAreaRect`), as Capture Text does not: the previous area is for image captures.
- **Count-in.** With `Count down before recording` on (Capture tab, default on), the self-timer badge counts 3, 2, 1 over the area or window, or centred on the display with no frame for fullscreen, using `SelfTimerController` and its stage. During the count-in, Escape (`cancelCapture`), `recordScreen` and `recordFullscreen` each cancel it.
- **Hand-off.** Every area or window start does these steps in order, with the count-in on or off:
  1. `selector.dismiss()` removes the selection overlay.
  2. `NSApplication.shared.deactivate()` runs, as in `runSelfTimer`. The user's app is then frontmost and its keys and menus work. The panel never takes key, so TidyShot does not need to be active.
  3. The count-in runs, if it is on.
  4. `SelfTimerController.settleDelay` (100 ms) passes. With the count-in on, `SelfTimerController.run` supplies it.
  5. The shareable content is read again, and the display or window is found by id, as `captureAfterCountdown` does.
     - A missing window posts `The window is no longer on screen.` and a missing display posts `The display is no longer connected.`, both titled `Screen recording`. Nothing starts and the lock is released.
     - A window's size comes from its fresh frame.

  Record Fullscreen skips steps 1 and 2.
- **Lock.** The capture lock (`withCaptureLock`) is held from the selection to the end of the recording, as the scrolling capture holds it. Hide desktop icons while capturing applies (`coversDesktop: true`).
  - **Area and fullscreen recordings.** The covers stay up for the whole recording and appear in it. That is the setting's purpose: without them the icons show for the whole length. While the covers are up, the desktop takes no clicks; windows above it work as usual.
    - Capture Scrolling is not covered because `ScrollFrameSource.makeFilter` excludes the whole app, covers included (2.10 built notes). A recording keeps the covers in the picture (see Excluded windows).
  - **Window recordings.** The covers add nothing, because `desktopIndependentWindow` shows only the window. Once the selection returns a window, `recordScreen` calls `covers.hide(for: .capture)` before the count-in, as All-in-One's Scrolling case does. The lock's own hide is then a no-op, and a persistent Hide Desktop Icons keeps its covers.

### While recording

- **Stream.**
  - An area records the display filter in Excluded windows, with `sourceRect`.
  - Fullscreen records the display with the same exclusions.
  - A window records `SCContentFilter(desktopIndependentWindow:)`.
- **Excluded windows.**
  - **Order.** The count-in stage closes. The frame (area recordings only) and the panel are ordered front. Shareable content is fetched, the filter is made, then `startCapture` runs.
  - **Filter.** Area and fullscreen recordings use `SCContentFilter(display:excludingApplications: [own], exceptingWindows: covers)`.
    - `own` is the `SCRunningApplication` with `processID == getpid()`, as in `ScrollFrameSource.makeFilter`.
    - `covers` are the desktop cover panels on that display, found by window number through `OverlayWindowLookup`. `DesktopCoverController` gains `windowNumbers` for this.
  - **What stays out.** Every other TidyShot window, including windows opened during the recording: the status menu, Recent Captures and its preview, Settings, a card brought back by Restore Closed Overlay, pins and editors. Neither the filter nor the configuration is updated during a recording.
  - **Late covers.** A cover made after the start is excluded, so the icons show on that display. This happens when a display is connected, or when Hide Desktop Icons is turned on mid-recording. Accepted.
  - **Fallback.** If `own` is missing from the shareable list, exclude the frame, the panel and the cards by window number, as `ScrollFrameSource` does, and log that windows opened later will show.
    - If that lookup cannot find the panel, or the frame of an area recording, the start fails with `Recording failed` / `TidyShot could not hide its own windows.`
    - If it cannot find every cover, the start goes ahead.
- **Output size.** The source size in points, times the display's backing scale with `Retina` (default) or times 1 with `Standard`.
  - If either side is then over 4096 px, scale both down by one factor so the longer side is 4096. A 5120×2880 display records at 4096×2304. `SCRecordingOutput` encodes 5120×2880, but Clop returns an empty reply for it and leaves it unoptimised, and many players cannot play H.264 that large (see Probes). HEVC is not used, because Clop and other receivers may not take `hvc1`.
  - Round each side down to even pixels. If that changes the aspect (an odd point size at `Standard`), shrink `sourceRect` by the same amount, centred, so nothing is letterboxed.
- **Frame rate.** `minimumFrameInterval` is 1/30 s by default, or 1/60 s.
- **Cursor and audio.** `showsCursor` follows `Show cursor in recordings` (default on). `capturesAudio` follows `Record system audio` (default off), and `excludesCurrentProcessAudio` is true.
- **Output.** `SCRecordingOutputConfiguration` writes `outputFileType = .mp4`, `videoCodecType = .h264` to the container's `tmp/Recording/<id>.mp4`, where `<id>` is the `Recording`'s id.
- **Window recordings.**
  - **Size.** The window's `frame` times the scale (the shadow-off branch of `CaptureEngine.windowGeometry`), with `ignoreShadowsSingleWindow = true`. Never size from `contentRect`, which includes the shadow.
  - H.264 has no alpha, so `Include window shadow` and `Add background to window captures` do not apply.
  - `scalesToFit = true` and `preservesAspectRatio` true. A window resized during the recording is scaled to fit the starting size and letterboxed, never stretched.
  - **Window loss.** On each clock tick, the window is looked up by id with `CGWindowListCopyWindowInfo(.optionIncludingWindow, id)`.
    - If it is gone, the recording ends with `Recording stopped` / `The recorded window closed.`
    - A window that is listed but off screen (minimised, hidden, on another Space) keeps recording.
  - `streamDidBecomeInactive` and `streamDidBecomeActive` are logged only. Window loss is polled because which window changes send them has not been probed.
- **Frame.** The scrolling capture's dashed `ScrollAreaFrameWindow` outlines an area recording. Window and fullscreen recordings have no frame, because a window can move or resize and the frame is fixed. The count-in stage still frames the window for its 3 s.
- **Control panel.** `RecordingPanel` is a non-activating, borderless, floating `NSPanel` on all Spaces that never becomes key. It is placed by `ScrollPanelGeometry` from the area, or from the window's starting frame, and does not follow the window. For fullscreen it goes at the bottom centre of the display's visible frame (`ScrollPanelGeometry.bottomCentre(panelSize:visibleFrame:)`). It can be dragged by its background (`isMovableByWindowBackground`); it is excluded from the video, so moving it changes nothing there.
  - It shows the elapsed time as `0:00`, or `1:02:03` past an hour, counted from `recordingOutputDidStartRecording` and updated each second. The time turns orange from 5:00, the soft limit, with no hard stop.
  - It has a `Stop` button (`stop.fill`) and a `Cancel` button (`xmark`, tool tip `Discard the recording`).
    - Cancel first ends the recording, with the stop wait, so the alert is never recorded.
    - Under 5 s of recording, it discards at once.
    - From 5 s, it asks `Discard this recording?` / `<m:ss> of recording will be deleted.`, with `Save` (default, Return) and `Discard` (destructive, no key equivalent). `Save` carries on as Stop.
    - The lock and the covers stay until the alert is answered.
- **Status item.**
  - `AppCoordinator` gets an observed `private(set) var isRecording`, true from the stream start until the file is handed on or removed. `updateIcon` reads it alongside `isUploading`, and `record.circle` wins over `arrow.up.circle`.
  - The menu's first item is `Stop Recording  ⌃⇧8`. `Record Screen` and `Record Fullscreen` are not shown during a recording, and every other capture item is disabled.
  - `Quit TidyShot` stays enabled (see Quit, log out and restart).
- **Stopping.** The `recordScreen` shortcut, the `recordFullscreen` shortcut, the panel's Stop and the menu item all stop the recording. The shortcuts reach the controller before the capture lock, as `captureScrolling` does with `advance()`.
  - **Two steps.** The controller first arms a one-shot waiter on the output's `recordingOutputDidFinishRecording(_:)` and `recordingOutput(_:didFailWithError:)`, then calls `stopCapture()`.
    - The waiter is armed first because the finish callback can arrive before `stopCapture()` returns: 9 ms before, in the area probe.
    - The file is not finished when `stopCapture()` returns: in the 5K probe it could not be opened for the 290 ms until the callback.
  - **When the wait ends.** It is settled: once `stopCapture()` has returned or thrown and the output has finished or failed, or at the 15 s timeout.
    - `stream(_:didStopWithError:)` ends the recording, as any error does, but never the wait: reading the MP4 while the output is still finishing it would find it unplayable, and the end rule would delete it.
    - The cost: a stream error that no finish or fail follows keeps Stop disabled, the lock and the covers for at most 15 s. Whether ScreenCaptureKit sends one is a Sleep and lock probe (Still to probe).
  - **The timeout.** 15 s of time awake from the `stopCapture()` call. It runs on the suspending clock, which stops while the Mac sleeps, so a Mac that sleeps before the finish does not time out on wake and delete a file the output has not finished. The timeout only matters on a failure, and it never deletes a playable file.
  - **Nothing touches the file before the wait ends.** Nothing reads, validates, takes a poster from, moves, copies, uploads or deletes it. Cancel waits the same way.
  - **What stays up.** The lock, the covers, `record.circle` and the panel (with Stop disabled) stay until the file is handed to `saveRecording` or removed.
  - **Stop during start.** A Stop or Cancel that arrives while the content is fetched, or while `startCapture` is suspended, wins. The controller stops the stream it has just started and removes the file, as `ScrollFrameSource.start()` does.
  - **First end wins.** Any of these ends the recording: Stop, Cancel, a shortcut, the disk check, sleep, a user switch, a lost window, an `SCStream` or output error, a quit. Whichever comes first wins and later callbacks are ignored, so the file is saved and notified once. So are callbacks and a late `stopCapture()` return from an earlier recording whose stop outlived its wait.
  - **Duration.** `Recording.duration` is the finished file's `AVURLAsset` duration, not wall time or `recordedDuration`. In the probe `recordedDuration` ran short: 3.0 s for a 3.05 s file, 4.0 s for a 4.18 s one.
- **Escape.** It is not taken during the recording, because the user's own apps need it. Only the count-in enables it.
- **End rule.** `RecordingEnd.decide` (pure) runs after the wait on every end, using `VideoValidation`'s result and the kind of end.
  - **Discarding Cancel.** A Cancel that discards (under 5 s, or `Discard` in the alert) removes the file whatever the result, and nothing posts. `decide` takes the Cancel as an input. `Save` in the alert is a Stop.
  - **Playable track of at least 0.5 s.** The file is kept and saved.
    - After the user's Stop, it is saved as in After stopping, even if the wait timed out.
    - After any other end (an error, a timeout, the disk check, sleep, a closed window), the notification is `Recording stopped` with the reason.
  - **Otherwise.** The file is removed. The notification is `Recording failed`, with `The recording is too short.` after a Stop, or the error's description otherwise.
  - **Start failure.** If `startCapture` throws, or the output fails before the first frame, the result is `Recording failed` with the description and no file. The lock, panel, frame, covers and icon are released as for any other end.
- **Free space.** Read as `volumeAvailableCapacityForImportantUsageKey` of `tmp/Recording`.
  - Under 2 GB at the start: nothing records, and `Your disk is almost full.` posts (title `Screen recording`).
  - During the recording it is checked every 5 s. Under 1 GB, the recording ends with `Recording stopped` / `Your disk is almost full.`
- **Keep awake.** From the stream start to the end of the recording, the controller holds `ProcessInfo.processInfo.beginActivity(options: [.userInitiated, .idleDisplaySleepDisabled], reason: "Recording the screen")`. It ends where the lock is released.
- **Sleep and user switch.**
  - `NSWorkspace.willSleepNotification` ends the recording with `Recording stopped` / `Your Mac went to sleep.`
  - `sessionDidResignActiveNotification` ends it with `Recording stopped` / `Another user took over the screen.`
  - A screen lock (⌃⌘Q) does not stop the recording: stopping on lock could end a long unattended recording. A display sleep is not handled specially either. The probe and the checklist record what ScreenCaptureKit does in both.
- **Quit, log out and restart.** All three go through `applicationShouldTerminate`. While a count-in, a recording, or a recording save up to `history.add` is under way, it returns `.terminateLater`, then:
  1. `reviewEditorsBeforeQuit()` runs first, because it can cancel the quit. A cancelled quit leaves the recording running.
  2. A count-in is cancelled, and nothing is recorded.
  3. A recording stops as Stop does, with the wait and the end rule.
  4. `saveRecording` runs in quit mode:
     - no folder prompt: with no folder, or with the folder panel still open, the file goes to `pending/`;
     - no Clop, no upload, no card and no notification;
     - an uploading action is written as `.failed(message: "Upload was interrupted.")`, rather than starting an upload the quit would cut off;
     - the poster and the thumbnail are written before the reply.
  5. `reply(toApplicationShouldTerminate: true)`, sent once.

  `Quit TidyShot` stays enabled: it is a stop-and-save. A graceful stop gives a complete file and a record, which a kill does not.
- **Relaunch after a crash.** `AppCoordinator.start()` checks `tmp/Recording` next to the `Drag` and `tmp/Clop` sweeps.
  - A file `VideoValidation` finds playable moves to `pending/<id>.mp4` with a record (`fileIsTemporary` true, `.none`), and `Recovered a recording` posts.
  - Any other file is removed with the log line `Recording: <name> could not be played, removed`.
  - Leftover files are checked, not swept. A killed recording plays (see Probes), and a crash between the finish callback and the record would otherwise lose a good recording.

### After stopping

`saveRecording(_ recording: Recording, intent:)` is a new funnel beside `save(_:intent:)`. `Recording` holds:
- the id: a `UUID` minted at the start, which names `tmp/Recording/<id>.mp4` and becomes the record's id;
- the file URL and the start time;
- the pixel size, duration and poster frame, all read from the finished file;
- the display ID.

`persist` is split. Writing the file stays per kind: a PNG write for screenshots, a video move for recordings. A shared tail serves both funnels so they cannot drift. It does the not-configured warning, the shutter, the record, the thumbnail, the overlay, the upload and the notification.

`saveRecording` follows the after-capture action:

| Action | Where the file goes | Upload | Clipboard |
|---|---|---|---|
| `.save` | moved into the save folder under the security scope, named by the recording template, `.mp4` | none | a file reference, when `Copy image to clipboard` is on |
| `.upload` | moved into the save folder | uploaded from the save-folder file | the URL when the upload finishes, if the clipboard is unchanged; a file reference meanwhile, when `Also copy image…` is on |
| `.uploadOnly` | moved to `pending/<id>.mp4` | uploaded from the pending file | the URL when the upload finishes, if the clipboard is unchanged |

- **No destination.** This means no complete S3 config, or a failed Keychain read. The same `warnUploadNotConfiguredOnce` gate as screenshots applies.
  - **`.upload`.** Saved exactly as `.save`, with `.none`. A file reference goes on the clipboard whatever the copy settings say, as screenshots get the image. `Recording saved` follows Show notification. The warning is `Upload not configured`: `Set up a destination in Settings > Upload. The recording was saved and is on the clipboard as a file.`
  - **`.uploadOnly`.** The file goes to `pending/<id>.mp4` with `.failed(notConfigured)`. Nothing goes on the clipboard, because a reference into `pending/` dangles once a retry succeeds. `Recording saved` does not post. The warning is `Set up a destination in Settings > Upload, then retry from Recent Captures. TidyShot keeps the recording until then.`
  - These replace `persist`'s `The image is on the clipboard` strings for videos.
- **Clipboard after the upload.** For a video, the URL replaces the clipboard only if `NSPasteboard.general.changeCount` is still the count TidyShot left after the save: the count after its file reference, or the count it found if it put nothing there.
  - The count is kept in memory per record id. With none, as after a relaunch, the clipboard counts as changed.
  - Otherwise the clipboard is left alone. The notification is `Uploaded`, with the URL as the body and the subtitle `Click to copy the link.` A click copies the URL and does not open it. It follows Show notification, as `Uploaded, URL copied` does, and the card says `Uploaded`, not `URL copied`.
  - Screenshots keep today's behaviour: the URL always replaces the clipboard.
- **Naming.** The file name comes from `recordingFileNameTemplate`, a new General-tab field `Recording file name`, default `Recording {date} at {time}`. It uses the same token engine and counter as screenshots. The extension is `mp4` and the content type `video/mp4`, for both the file and the object key. The file name, the object key's date and the record's timestamp all use the time the recording started. An empty `Recording file name` falls back to `Recording`, so `FileNamer` takes the fallback name as a parameter.
- **Where the file lands.**
  - **Folder prompt.** With no save folder set, `.save` and `.upload` ask for one, as screenshots do. If the user cancels, the reason is `No folder was chosen.` and the file takes the pending path below. `.uploadOnly` goes to `pending/` anyway and does not ask at the save (only the size refusal can, see Size). Quit mode never asks.
  - **The move.** The move into the save folder is `nonisolated static SaveLocation.moveInScoped(_:baseName:ext:folder:)`. It runs detached, under the folder's scope, with `FileNamer.uniqueURL` made `nonisolated`. A save folder on another volume makes the move a full copy.
  - **When it fails.** Any failure sends the file to `pending/<id>.mp4` (`PendingFileStore.moveIn(_:id:ext:)`, a rename inside the container), and the record keeps it. Failures include: no folder chosen, a folder gone since launch, a permission or write error, a full volume.
  - **The fallback record.**
    - `fileIsTemporary` is true whatever the action, so Delete, drag-out and reads take the pending path, and Reveal is off.
    - `isPendingOnly` keeps the record until it is deleted.
    - `.save` gets `.none`, never `.failed`, which `retryFailedUploads` would upload.
    - `.upload` behaves as `.uploadOnly` from here on, the clipboard included. After a successful upload, only the uploaded object remains.
    - `lastCaptureURL` is not set to a pending file.
  - **The notification** always posts. Title `Not saved to a folder`. The body is the reason (`No folder was chosen.` or the error's description), then `TidyShot keeps the recording. Use Save As… on its card.` For `.upload`, the second sentence is `The recording uploads without a local copy.`
  - **The tmp file.** It is never removed before a record points at the new place. If even the rename fails, it stays in `tmp/Recording` and the notification gives its path. The launch check recovers it.
- **Record.** It has `mediaKind: .video` and `durationSeconds`, and its pixel size is the video's. The poster frame becomes the thumbnail through `makeThumbnail(from:for:)`. `showOverlay` gets the poster for the card, but `latestCapture` is never set for a video. `lastCaptureURL` is set as for a screenshot.
- **Feedback.**
  - Play sound plays the shutter when the recording stops.
  - Notifications:
    - `Recording saved` (file name; a click reveals the file) posts for `.save`, and for `.upload` with no destination. It follows Show notification. `Uploaded, URL copied` stays as today when the URL replaced the clipboard; otherwise `Uploaded` posts (see Clipboard after the upload).
    - `Recording stopped`, `Recording failed`, `Not saved to a folder`, `Recovered a recording` and the refusals always post, as `notifyError` does.
    - `Recording stopped` carries the file's path so a click reveals it, and it replaces `Recording saved`.
    - Refusals are titled `Screen recording`. `Screenshot saved` and `Capture failed` are never used for a video.
- **Clop.** With `Optimize images and videos with Clop` on and Clop running, the upload sends Clop's result. The setting's key stays `optimiseWithClop`.
  - **Queue.** `optimisedVideo` runs on its own serial queue, `io.tky.tidyshot.clop-video`. This amends 2.7: Clop now sees at most one image request and one video request at a time.
    - A shared queue would hold every screenshot's Clop step and upload for about a quarter of a recording's length, and for up to `60 + 3 × duration` s if Clop stalls.
    - If Clop answers one port request at a time, an image request sent during a video times out after 32 s and the original screenshot uploads. That is the accepted worst case.
  - **Work file.** `tmp/Clop/<UUID>.mp4`, made with `FileManager.copyItem` in a detached task. It is a clone on the same volume. When the source is in the save folder, the copy holds the folder's scope.
    - Clop is skipped when the `tmp` volume has less free space than the file's size plus 1 GB. The log line is `Clop: not enough free space, uploading the original`.
  - **Request.**
    - Video requests send `removeAudio: false`; images still omit it.
    - The receive timeout is `60 + 3 × duration` seconds. To carry it, the transport becomes `@Sendable (URL, TimeInterval) throws -> ClopResponse`, and `ClopApp.makeOptimiser` builds `ClopClient(bundleID:receiveTimeout:)`. Images pass 30.
  - **Accepted** only when all of these hold:
    - the reply's path is the work file;
    - `convertedFrom` is nil;
    - the file opens with `AVURLAsset`;
    - it has one video track of the same natural size;
    - it has at least as many audio tracks as the work file had;
    - its duration is within 0.5 s;
    - it is smaller.

    The duration, size and audio-track count are read from the work file before the request, because Clop rewrites it in place. They never come from `Recording`.
  - Otherwise the original uploads and one line is logged: `Clop: <reason>, uploading the original`. One such reason is `the result lost its audio`.
    - An empty reply (`[]`) means Clop skipped the file, as it did for a 5120×2880 H.264 file. `ClopClient` throws `badReply` for it, and the original uploads.
  - **Ownership.** `optimisedVideo(at:duration:) async -> ClopVideoOutcome` returns `.optimised(URL, oldBytes:newBytes:)` or `.original(ClopSkipReason)`.
    - On every `.original`, the optimiser removes the work file, and any converted sibling, before it returns.
    - On `.optimised`, the coordinator owns the file (`clopResults[recordID]`), and the queue's own retries re-send it.
    - The coordinator removes it at the top of `handle(_:at:)` on `.uploaded`, `.failed` and `.cancelled`, before any early return.
    - It also removes it in `startUpload`'s task when the token no longer matches (a Delete or a newer retry while Clop ran), or when the record is gone.
    - A user Retry runs Clop again from the original. The launch sweep of `tmp/Clop` stays as the backstop.
  - **Status.** While a video waits for Clop, its card and its row say `Optimizing…`. This comes from a transient observable set of record ids, not a persisted `UploadState`.
    - A Delete during Clop marks the record cancelled at once.
    - The video queue stays busy until Clop replies, then the result is removed.
  - The save-folder or pending file stays as recorded. A video waiting for Clop counts in `clopWaitsPerLane`.

### Uploading a file

- **Payload.** `UploadJob` carries `enum UploadPayload: Sendable { case data(Data), file(URL, scope: URL?) }` in place of `data`. Screenshots keep `.data`; recordings use `.file`.
  - `scope` is `saveLocation.currentURL` for a file inside the save folder (`SaveLocation.contains(_:inFolder:)`). It is nil for files in `pending/`, `tmp/Recording` and `tmp/Clop`, the same rule `prepareDragFile` uses.
- **Access.** The save folder's scope is held only per call, and a folder resolved from its bookmark after a relaunch cannot be read without it.
  - `UploadQueue.process` starts `scope` before each `destination.upload(fileAt:…)` attempt and stops it when the call returns or throws. One hold covers the hash and the streamed PUT. A job waiting in the queue or in backoff holds nothing.
  - A file that cannot be opened inside the hold fails with `UploadError.fileUnreadable(<name>)`, which is not retried.
- **Destination.** `Destination` gets `upload(fileAt url: URL, key:contentType:cacheControl:progress:)` and `download(key:to:)`. In `S3Destination` it:
  - hashes the file with `@concurrent static func sha256Hex(fileAt:) async throws -> String` in `S3Signer`:
    - 4 MB reads into one reusable buffer and an incremental `SHA256`, with `try Task.checkCancellation()` before each read;
    - so the hash never runs on the `UploadQueue` actor, and a Delete during the hash ends the job with `.cancelled`;
  - signs with that hash, through a `signedRequest` variant that takes a precomputed payload hash;
  - sends with `session.upload(for:fromFile:delegate:)`. URLSession sets `Content-Length` itself for a file body; it is neither set by hand nor signed;
  - downloads with `download(key:to:)`: `session.download(for:delegate:)` with the signed GET, redirects refused.
    - On 2xx, it moves the temporary file into place, replacing any existing file, since the save panel already confirmed that.
    - Otherwise, it reads the small error body from the temporary file for the usual error, then deletes the file.
    - It never returns `Data`.
- **Type and extension.** `startUpload(recordID:payload:destination:fixedKey:)` takes the content type and the extension from `record.mediaKind` in both branches: `image/png`/`png` or `video/mp4`/`mp4`.
- **Retries.** `uploadPayload(for:) throws -> UploadPayload` replaces `readLocalFile(of:)`. Both Retry and the upload after `saveRecording` use it.
  - An image is read into `.data` as today.
  - A video returns `.file(url, scope:)` after two checks: the file exists, and a save-folder file is inside the current folder. If either fails, it throws `UploadError.fileUnreadable`, as today.
  - A `.file` job uses `RetryPolicy(maxAttempts: 6, baseDelay: .seconds(2), maxDelay: .seconds(30))`. That is about 60 s of waits, enough for Wi-Fi to return after wake. `.data` keeps `.default`, and `UploadQueue` picks the policy from the payload.
  - `UploadError.isRetryable` treats these URLError codes as not retryable: `.fileDoesNotExist`, `.noPermissionsToReadFile`, `.cannotOpenFile` and `.fileIsDirectory`.
  - A failed file upload restarts from byte 0 until R2.
  - Nothing loads a video into memory: not the upload, a retry, Copy URL, Reveal, drag-out, Save As…, a restore, or the thumbnail.
- **Staying awake.** The coordinator holds one `beginActivity(options: .userInitiated, reason: "Uploading a recording")`.
  - It starts at a recording's Clop request, or at the enqueue when Clop is off.
  - It lasts until no `.file` job is waiting for Clop, queued or in flight.
  - Every terminal path ends it: `.uploaded`, `.failed`, `.cancelled`, Delete, and removal from history.
  - It stops idle sleep and App Nap. It does not stop a lid close.
- **Size.** A single PUT is used up to 5 GiB (5,368,709,120 bytes).
  - The check runs once, in `startUpload`, just before the enqueue, on the file actually sent. That is Clop's result when Clop's result was accepted.
  - Over the limit, no job is enqueued and no key is drawn. `Not uploaded` / `The recording is larger than 5 GB, too large to upload in one piece.` always posts.
  - The record is never `.failed`, because the refusal is permanent and `.failed` would keep offering Retry and Retry Failed Uploads, running Clop again each time:
    - `.upload` gets `.none`;
    - `.uploadOnly` moves into the save folder (`moveInScoped`, asking for a folder if none is set) with `fileIsTemporary` false and `.none`. With no folder chosen, it follows Where the file lands.
  - A provider with a lower limit answers 400 `EntityTooLarge` through the existing path. Multipart is R2.
- **Queue.** The upload queue stays serial, so a video upload delays the next screenshot's upload; the Clop step does not (see Clop, Queue). R2 may give videos their own lane.
- **Progress.** Events are throttled to at most 10 per second.

### Videos in the rest of the app

Image-only actions are left out for `mediaKind == .video`, not disabled. `RecentCaptureFormatting.showsImageActions` and the card model do this.
- **Left out:** Annotate, Pin and Copy Image, on cards, rows and menus.
- **Added:** `Copy File`, for a video with a local file (see Quick Access card and Recent Captures).
- **Ignored:** `saveRecording` ignores `intent.then` and `intent.copyOnly`. No R1 path sets them for a recording.

What changes for videos:
- **`EditorInput.source`** returns `.unavailable("Videos cannot be annotated.")` for a video, as a safety net.
- **Quick Access card:**
  - **Thumbnail.** The poster with a `play.fill` badge and the duration (`0:42`) in the corner.
  - **Thumbnail click.** It opens the file in the default app (QuickTime) when there is a local file, or the URL when there is only an upload. For a video this replaces Reveal-on-click (tool tip `Open`); Reveal stays in the card menu.
  - **Save As…** is `saveVideoCopy`, never `imageData(of:)`. It offers `.mpeg4Movie` and runs detached.
    - It copies, in order of preference: the local file under its scope, the drag copy, or `S3Destination.download(key:to:)` with the usual `Downloading <key>` notification.
    - It replaces an existing destination with `FileManager.replaceItemAt`.
  - **Drag-out with a local file.** A video stages its file, but `stage` reuses an existing drag copy that has the same name, size and modification date. Only one stage per record runs at a time.
    - So a press, including the click that opens the file, copies a large file across volumes once.
    - The drag copy is reused rather than dragging the save-folder file itself, which would break 2.9's rule that drag-out hands out a container copy.
    - Images keep replacing their copy on every press, because an edit rewrites the file.
  - **Drag-out with no local file.** A video with no local file and no drag copy is never prefetched: `prefetchDragFile` returns early for videos.
    - Neither Restore Closed Overlay nor a press starts a download, and the card cannot be dragged. That is R2.
    - A press is also the click that opens the video, and a silent download of hundreds of MB on a click would surprise the user.
  - **Copy File.** A video with a local file, in the save folder or `pending/`, has `Copy File` in the card menu. It puts a file reference on the clipboard (`Pasteboard.copy(fileURL:)`).
    - For a pending file, the reference is to a copy staged in the drag folder (the same stage and reuse as drag-out), so it does not dangle once the upload removes the pending file.
  - **Temporary file.** A card for a temporary file with `.none` shows `Kept in TidyShot` and `Not in your save folder. Use Save As… to keep a copy.`, not the green `Saved` and `<uuid>.mp4`.
  - **Lifetime.** The card stays until the upload ends, as today.
- **Recent Captures:**
  - rows show the poster with the badge;
  - the hover preview shows the stored 320 px thumbnail at its own size, and never reads the video file. No larger poster is stored;
  - a `Copy File` button (`doc.on.doc`) takes Copy Image's place, enabled when the video has a local file, and does what the card's Copy File does;
  - a row click copies the link or the file as today. A video's file goes through Copy File, so a pending file is referenced through its drag copy.
- **`ThumbnailProvider`** never reads a video file. A video with no stored thumbnail shows the `film` symbol. Cards and rows show `film` for such a video, not `photo`.
- **`DragFileName`** keeps the key's own extension and adds `.png` only to images. The fallback name is the `EditorNaming` suggestion, whose extension comes from `mediaKind`.
- **`EditorNaming`.** For a video, the suggestion is the record's own save-folder file name, otherwise `recordingFileNameTemplate` plus `.mp4` (`{counter}` behaves as for screenshots). The panel allows `.mpeg4Movie` only.
- **`mediaKind`** decodes with `decodeIfPresent`. A missing value reads as `.image`, and an unknown raw value reads as `.video`. That way a newer kind never makes `HistoryStore.load` set the whole history aside.
- **Retention and delete** treat the video like any capture file. Deleting removes the save-folder file, the pending file and the uploaded object, as for screenshots.
- **Captions** that say PNG or image get media-neutral wording where they cover both:
  - General's upload-only caption becomes `The file is kept inside TidyShot only until the upload succeeds…`;
  - Upload's key caption becomes `The file's extension (.png or .mp4) is added.`;
  - the Clop toggle becomes `Optimize images and videos with Clop`;
  - General's `Images` section becomes `Optimization`. Its caption becomes `Clop greatly reduces file size. It keeps its own copy of each image and video it optimizes, so long recordings also take space in Clop's cache.`;
  - `Copy image to clipboard` and `Also copy image (the URL replaces it when the upload finishes)` get the caption `For recordings, the file is copied.`;
  - the save-folder panel says `Choose where TidyShot saves screenshots and recordings.`;
  - the Capture tab's Hide desktop icons caption becomes `Covers desktop icons and widgets with the desktop picture during area, window, fullscreen, previous-area, All-in-One and self-timer captures, and area and fullscreen recordings. While covered, the desktop does not take clicks.` 2.10's scope paragraph gets the same addition.

### Settings (R1)

- **Capture tab, new `Section("Recording")` after the Self-timer picker:**
  - `Frame rate` (`30 fps`, default, or `60 fps`);
  - `Resolution` (`Retina`, default, or `Standard`), with the caption `Retina is capped at 4096 px on the longer side.`;
  - `Record system audio` (off);
  - `Show cursor in recordings` (on);
  - `Count down before recording` (on).
- **General tab:** `Recording file name` under `File name`.
- **Shortcuts tab:** the two recorders.
- **New `AppSettings` keys:** `recordingFrameRate` (30), `recordingRetina` (true), `recordingSystemAudio` (false), `recordingShowsCursor` (true), `recordingCountdown` (true), `recordingFileNameTemplate` (`Recording {date} at {time}`). A stored `recordingFrameRate` other than 30 or 60 reads as 30. `optimiseWithClop` keeps its key; only its label changes.

No new entitlement. System audio needs none, and the microphone is R2.

### Architecture (R1)

**New files.**
- `TidyShot/Recording/`:
  - `RecordingController.swift`: the session; it owns the stream, output, panel, frame, timer and disk check, and ends with a `RecordingOutcome`.
  - `RecordingConfiguration.swift`: pure. It turns a `RecordingSource` (a display id and rect, or a window id and frame) into the stream configuration, the output size (with the 4096 cap) and a `RecordingFilterPlan`: `.area(displayID, sourceRect)`, `.display(displayID)` or `.window(windowID)`. The controller turns the plan into an `SCContentFilter` from fresh shareable content.
  - `RecordingPanel.swift` and `RecordingPanelView.swift`.
  - `RecordingClock.swift`: pure elapsed-time formatting and the 5:00 soft limit.
  - `Recording.swift`: the value handed to `saveRecording`.
  - `PosterFrame.swift`: `AVAssetImageGenerator`, `@concurrent`.
  - `VideoValidation.swift`: an `@concurrent` asset check used by the Clop path, the end rule and the launch check.
  - `RecordingEnd.swift`: pure. The keep-or-discard decision and the notice for every end.
  - `RecordingLimits.swift`: pure. The free-space thresholds (2 GB at start, 1 GB during), the 5 s Cancel threshold and the 5 GiB upload limit.
  - `RecordingSavePlan.swift`: pure. Maps action, destination and folder outcome to where the file goes, the upload, the clipboard and the notification. It covers the table, No destination, Clipboard after the upload, Where the file lands, the size refusal and quit mode.
- `TidyShot/Upload/UploadPayload.swift`, plus a file-hashing helper in `S3Signer` (`sha256Hex(fileAt:)`, incremental).

**Edits.**
- `UploadJob`; `UploadQueue` (holds the scope per attempt, picks the policy by payload); `RetryPolicy` (the file policy); `UploadError` (file URL errors not retryable).
- `Destination` and `S3Destination` (file upload, `download(key:to:)`), and `S3Signer` (`@concurrent` file hash, a precomputed-hash variant of `signedRequest`).
- `ClopOptimiser` (`optimisedVideo(at:duration:)`, the video queue, the timeout in the transport), `ClopClient` (`removeAudio`), `ClopApp.makeOptimiser`.
- `CaptureRecord` (`mediaKind`, `durationSeconds`, with defaults so old history decodes).
- `AppDelegate`: the terminate hold.
- `AppCoordinator`:
  - `recordScreen` and `recordFullscreen`;
  - `saveRecording`, sharing a tail with `persist`;
  - observed `isRecording`, and the quit path;
  - the `tmp/Recording` launch check;
  - `startUpload` taking a payload, with type and extension from `mediaKind`;
  - `uploadPayload(for:)` replacing `readLocalFile`;
  - Clop result ownership, the upload activity and the 5 GiB check;
  - the clipboard check after a video upload;
  - `saveVideoCopy` and `copyFile(recordID:)`;
  - the video branches in `prepareDragFile` and `prefetchDragFile`;
  - media checks on every image action.
- `SelectionMode.recording`, `StatusMenuController` (items, recording state, icon), `Shortcuts`, `ShortcutsSettingsView`, `CaptureSettingsView`, `GeneralSettingsView`, `UploadSettingsView`, `AppSettings`.
- `QuickAccessView` (`Kept in TidyShot`, `Optimizing…`, `Uploaded`, `Copy File`) and `QuickAccessModel`, `RecentCaptureRow` and `RecentCaptureFormatting`, `ThumbnailProvider`, `DragFileName`, `EditorInput`, `SaveLocation` (`moveInScoped`, the panel message), `PendingFileStore` (`moveIn(_:id:ext:)`), `EditorNaming`, `DragFileStore` (video reuse), `DesktopCoverController` (`windowNumbers`), `ScrollPanelGeometry` (`bottomCentre`), `FileNamer` (`uniqueURL` nonisolated, a fallback-name parameter), `Notifier` (recording titles, a path on `Recording stopped`, an `Uploaded` notification whose click copies the URL).

**Concurrency.** The 2.6 rule holds. These run off the main actor: hashing (`@concurrent`, so not on the `UploadQueue` actor either), poster frames, asset checks, Clop and its work copy, the move into the save folder or `pending/`, Save As… copies and downloads, and a video's drag stage. The controller, panel and settings are MainActor. `SCRecordingOutputDelegate` and `SCStreamDelegate` callbacks hop to the main actor.

### Tests (R1, Swift Testing)

- `RecordingConfigurationTests`: area to `sourceRect` and pixel size at 2x Retina and Standard (even rounding); the `RecordingFilterPlan` for each source; a window sized from `frame` × scale, with `ignoreShadowsSingleWindow` and `scalesToFit` true; the 4096 cap (5120×2880 → 4096×2304, 4112×2658 → 4096×2646, 2304×5120 → 1842×4096, while 4096×4096, 3456×2234 and Standard 2560×1440 stay unchanged); an odd point size at Standard shrinking `sourceRect`; 30 and 60 fps intervals; cursor and audio from the settings; the area minimum.
- `RecordingClockTests`: `0:00`, `0:59`, `1:00`, `59:59`, `1:00:00`; the soft limit at 300 s.
- `RecordingEndTests`:
  - a playable 10 s file is saved;
  - a 0.3 s file is discarded as too short;
  - an unplayable file is discarded;
  - a playable file after an error is saved as `Recording stopped`;
  - a timeout with a playable file is saved;
  - a discarding Cancel removes a playable file and posts nothing; `Save` in the alert saves as a Stop.
- `RecordingControllerTests`, with a fake stream and output:
  - the finish callback arrives before `stopCapture()` returns, after it, and never (the timeout);
  - no file access happens before the wait ends;
  - a Stop during `startCapture` stops the new stream;
  - the first end wins;
  - a stream error, first or after another end, waits for the output's finish;
  - a Mac asleep for longer than the timeout before the finish keeps the file, and the timeout counts time awake only;
  - a late finish or stop return from an earlier run, whose stop outlived its wait, changes nothing in the next run;
  - the activity starts and ends on every exit.
- `RecordingLimitsTests`: refused at the start under 2 GB; stopped under 1 GB; no Cancel alert at 4.9 s, an alert at 5 s; the 5 GiB boundary.
- `RecordingSavePlanTests`:
  - every table row;
  - no destination for `.upload` and `.uploadOnly`;
  - the fallback for `.save` and `.upload` (`fileIsTemporary` true, never `.failed`);
  - over-limit `.upload` and `.uploadOnly`;
  - quit mode;
  - after the upload, the URL replaces the clipboard only when the change count is still the saved one; a changed or missing count leaves it and gives `Uploaded`.
- The quit-hold decision is a pure function next to `hasUnsavedEditors`, tested for idle, count-in, recording and saving.
- `UploadPayloadTests` and additions to `UploadQueueTests`:
  - a `.file` job uploads through `upload(fileAt:)` with the given type and extension;
  - a retry re-sends from the file;
  - the key gets `.mp4`;
  - a `.file` job's scope starts and stops once per attempt, including failing attempts and retries; a nil scope starts nothing;
  - a `.file` job retries six times with an injected sleeper, while `.data` gives up after 3;
  - a cancel during the hash delivers `.cancelled`.
- `S3SignerTests`:
  - the file hash equals the one-shot hash for 0 bytes, 1 byte, exactly 4 MB, and 4 MB + 1;
  - the signed request for a file carries that hash; cancelling stops the hash before the rest of the file is read.
- `S3DestinationTests`: a file upload through a URLProtocol stub sends the file's bytes; a download to a file; a non-2xx response leaves no file; an existing file is replaced.
- `ClopOptimiserTests` (video, with a fake transport and generated MP4 fixtures from `AVAssetWriter`):
  - accepted;
  - a different path refused;
  - converted refused;
  - a different size refused;
  - a duration off by more than 0.5 s refused;
  - not smaller refused;
  - not playable refused;
  - the timeout from the duration;
  - audio dropped is refused; audio kept is accepted; no audio on either side is accepted;
  - the work file is gone after each `.original` and present after `.optimised`;
  - a blocked video transport does not delay an image request;
  - the transport receives the timeout;
  - the existing fakes move to the two-argument transport.
- `ClopClientTests`: a video request encodes `removeAudio: false`; image requests still omit it; an empty reply (`[]`) throws `badReply`.
- `CaptureRecordTests`: old JSON without `mediaKind` decodes as `.image`; an unknown `mediaKind` decodes as `.video`; a video record round-trips.
- `RecentCaptureFormattingTests`, `EditorInputTests` and `QuickAccessModelTests`: no Annotate, Pin or Copy Image for a video; `.unavailable` for a video; Copy File for a video with a local file, none without; a temporary `.none` record shows `Kept in TidyShot`.
- `DragFileNameTests`: an `.mp4` key keeps its name; the fallback uses the record's extension.
- `EditorNamingTests`: a video suggestion with a save-folder file, and one without.
- `DragFileStoreTests`: a video stage reuses a matching copy; an image stage still replaces it.
- `ThumbnailProviderTests`: a video record never reads its file.
- `ScrollPanelGeometryTests`: the bottom centre.
- `AppSettingsTests`: the six keys.
- `VideoValidationTests`: with generated fixtures.
- The usual additions: `ShortcutsTests.recordScreenIsControlShiftEight`, and a `.recording` case in `SelectionOutcomeTests`.

The hand checks go in `docs/testing/recording-r1-manual-checklist.md`. They include:
- **Relaunch.** Relaunch first, then record with `Save and upload` to a save folder off the startup volume, and Retry a failed upload. A same-launch test passes even without the scope fix.
- **Quitting.**
  - Quit from the menu, log out, and quit with the folder panel open after Stop, each during a `.save` recording and an `.upload` recording.
  - `kill -9` mid-recording and again between Stop and the save, then relaunch. Each time `Recovered a recording` posts and the file plays.
- **Count-in off.** Record a Safari window: its title bar is active in the first frame, and typing reaches Safari.
- **Exclusions.** During a fullscreen recording, open the status menu, Settings and Recent Captures, restore a card, and stop from the menu. None of them appears in the file.
- **Window changes.**
  - Resize larger and smaller, move, move to another display, minimise, hide, switch Space and close. Minimise, hide and another Space keep recording; close ends it with `Recording stopped`.
  - Close or move the window during the count-in.
- **Large output.** Fullscreen Retina on the 5K display records at 4096×2304, plays, and Clop optimises it.
- **Covers.** With Hide desktop icons on, the icons are hidden in an area recording, and the bare desktop takes clicks during a window recording.
- **Cancel.** Under 5 s; over 5 s with Save; over 5 s with Discard; Return in the alert saves.
- **Display sleep.** Set it to 1 minute and record for 3 minutes: the display stays on.
- **Sleep, lock and switch.** System sleep, ⌃⌘Q, a lid close and a fast user switch, each during a recording. Sleep and a switch stop and save; a lock keeps recording. After a system sleep or a lid close, the file is saved on wake and plays. Note whether each stop ended at once or after the 15 s timeout (`Recording: the stop wait timed out`).
- **Upload resilience.**
  - A long upload left idle past the sleep timer finishes.
  - Wi-Fi off for 10 s mid-upload recovers without `Upload failed`.
  - Sleep and wake mid-upload.
- **Clipboard after the upload.** Copy some text during a long `.uploadOnly` upload: the text stays, `Uploaded` posts with `Click to copy the link.`, and a click copies the link without opening it. With nothing copied in between, the URL replaces the clipboard.
- **Copy File.** Copy File on a pending video while it uploads, then paste in Finder after the upload: the file pastes.
- **Clop queue.** While Clop optimises a video, take a screenshot. Record whether it uploads at once, times out and uploads the original, or waits.
- **Clop audio.** With `Record system audio` on, Clop on, and Clop's remove-audio setting on, the uploaded file still has sound.
- **Clop cleanup.** `tmp/Clop` is empty after an optimised upload, after a failed upload, and after a Delete during optimisation.
- **Restore.** Restoring an uploaded upload-only video after its drag folder is gone starts no download, and Save As… downloads to a file.
- **No destination.** `.upload` and `.uploadOnly` recordings: the clipboard and the warning text.

## R2 and R3 (not designed)

- **R2:**
  - microphone (entitlement `com.apple.security.device.audio-input`, `NSMicrophoneUsageDescription`, a TCC prompt);
  - GIF export;
  - trim before upload;
  - Pause;
  - S3 multipart for files over 5 GB, with resumable uploads;
  - a separate upload lane for videos;
  - drag-out of an uploaded video with no local file, as a file download with progress;
  - URL commands `record-screen` and `stop-recording`.
- **R3:** click highlights, keystroke overlay, webcam bubble.
