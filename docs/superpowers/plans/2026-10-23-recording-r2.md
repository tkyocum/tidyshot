# TidyShot Screen Recording R2, Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A `Format` setting records GIFs as well as MP4s, written by TidyShot's own GIF89a encoder. An MP4 recording can take the microphone, with a mute button whose muted stretches are silent in the saved and uploaded file. `Trim…` cuts an MP4 recording from its card or its Recent Captures row, and what it cuts is gone from the file. No recording is lost, and no sound the user muted is saved, uploaded or copied.

**Architecture:** `docs/superpowers/specs/2026-10-23-tidyshot-screen-recording-r2-design.md` is the full specification: behaviour, types, strings, constants, settings keys and tests. R1's design (`2026-10-21-tidyshot-screen-recording-design.md`) holds wherever R2's does not change it. When this plan and the R2 design disagree, the design wins; stop and ask if it is unclear.
- **Pure decisions.** `RecordingSettingsLayout`, `MicrophoneChoice`, `MicrophoneLatency.lag`, `RecordingMute.segments`, `RecordingNoticeOrder`, `GIFProgressMenu`, `RecordingTrim`'s range, source, sheet and write plans, and the extended `RecordingSavePlan` and `EditorAvailability` decide everything that can be decided without a screen, a microphone or a file, and are tested that way.
- **The GIF encoder.** `TidyShot/Recording/GIF/` is plain Swift with no AVFoundation, ImageIO or file system except `GIFFileSink`. Every part is tested by decoding its bytes with `CGImageSource`. `GIFMaker` reads the MP4 and drives it.
- **Steps outside the coordinator.** No test creates an `AppCoordinator`, so each new save-time step is a value with its parts injected: `GIFConversion` (make, save, remove), `RecordingMute.resolve` (the privacy ladder), `RecordingRecovery.prepare` (the launch check's GIF and mute rules) and `MuteLogWriter` (the write). The coordinator builds the live ones and stays a thin caller.
- **The coordinator split** (`2026-10-23-coordinator-split-design.md`, section 6) places R2's coordinator code: GIF, the microphone, the mute ladder and recovery in `AppCoordinator+Recording.swift`, upload changes in `+Upload`, card wiring in `+Overlay`, the file-action gates in `+RecordActions` and `+DragOut`, and Trim in a new `AppCoordinator+Trim.swift`, with its refusal and window closing in `+Delete` and the widened `replaceThumbnail` (`+Editor`) and `downloadSource` (`+RecordActions`). Section 6's own GIF summary is stale; Task 9 updates it.
- **Probes.** `docs/superpowers/research/recording-probes/` holds working code once Before Task 1 has copied it in: `gif-encoder-spike/gifspike.swift` (TidyShot's own, written from the GIF89a format; start the encoder from it), `mute-rewrite.swift` (the rewrite; `mute-empty-edit.swift` is the rejected empty edit), `trim.swift`, `mic.swift`, `mute-offset.swift` and `mute-offset-mic.swift`. The design's "Still to probe" items are gates or hand checks in Tasks 3, 4, 6 and 7.
- **Gates.** A gate that trips holds only the steps named here. The rest of its task and the later tasks go on, held steps stay unchecked until the design is amended and Tim says to go on, and the branch is not offered for merge while a step is held.
  - Task 3's encoder probe holds nothing: results Tim finds poor go to him (the selective ordered dither), and the defaults stay.
  - Task 4's sandboxed-capture gate holds "Wire the start", "Post the note last" and the microphone hand checks. Its pure parts, `LiveMicrophoneDevices`, the configuration and driver fields, the loss reason and the Settings row land with their tests. Task 5 goes on unchanged. Task 6 goes on with system audio: the mute button shows for `capturesAudio`, "Wire the lag" passes `MicrophoneLatency.noMicrophone` (no device is resolved), and its device read lands with Task 4's start path; the input-latency probe runs unsandboxed and still runs; Task 6's hand checks with a microphone wait.
  - Task 6's latency gate holds no code: the design's constants stay, and an input outside its lag goes to Tim and into the PR.
  - Task 7's trim gate holds `startsOnSyncSample`, `export`, `exportForSave`, `TrimWindowController` and `AppCoordinator+Trim.swift` apart from its stored state and `trimMenuState(for:)`. The pure parts, `recordLocalTrim`, the `EditorAvailability`, `CaptureDeletion` and `EditorUploadPlan` additions, the marker's gates (with `trimmingIDs` always empty), `handle(_:at:)` and the `tmp/Trim` sweep land. Task 8 goes on with the card's and row's `Trim…` and `Upload Trimmed` hidden (`trimState` at its default) and their wiring and hand checks held.
  - Task 9 runs after every held step has landed, or records in the Built notes any that Tim chooses to ship without.

**Tech Stack:** Swift 6 language mode with default `MainActor` isolation and `NonisolatedNonsendingByDefault`, AVFoundation (`AVAssetReader`, `AVAssetWriter`, `AVAssetExportSession`, `AVSampleCursor`, `AVCaptureDevice`), VideoToolbox (`VTCreateCGImageFromCVPixelBuffer`), CoreGraphics, CoreAudio (device latency properties), ScreenCaptureKit (`captureMicrophone`), AVKit (`AVPlayerView` trimming), AppKit (`NSAlert` sheets, `NSProgressIndicator`), SwiftUI Settings, ImageIO in tests only (`CGImageSource`), Swift Testing, XcodeGen 2.46.

Work happens on the branch `recording-r2`, cut from `small-tweaks` at f84204a. `small-tweaks` is stacked on `coordinator-split` and adds `CaptureRecord.byteCount` and the sizes in Recent Captures (spec 2.13). The R2 design and its probes are committed with this plan (Before Task 1). Line numbers are at f84204a; once an earlier task has moved a member, find it by name.

## Global Constraints

- **Earlier constraints still apply.**
  - Minimum macOS 26.0, Swift 6 with MainActor by default and `NonisolatedNonsendingByDefault`, App Sandbox, credentials only in the Keychain.
  - One save, upload and delete path. A GIF, a muted recording and a trimmed one go through `saveRecording`, `startUpload` and `deleteCapture` as R1's recordings do, and no new caller of `save` or `finishSave` appears.
  - KeyboardShortcuts is the only Swift package. No GPL code is read or copied: gifsicle, ffmpeg and gifski are off limits as sources, and the encoder is written from the GIF89a format and textbook algorithms.
- **One new entitlement and no new package.** `com.apple.security.device.audio-input` and the `NSMicrophoneUsageDescription` string, both through `project.yml`, are the only additions (Task 4). Nothing else in the entitlements or the Info.plist changes.
- **The coordinator split's conventions.**
  - New stored state goes in the class body in `AppCoordinator.swift`, under its area's group, with a `//` line naming any other file that writes it.
  - New members start `private` in their area's file. This plan widens two, each a reviewed one-word change listed in the PR: `replaceThumbnail` (`+Editor`) and `downloadSource` (`+RecordActions`), both for Trim.
  - New entry points for code outside the family: `gifProgressItems` and `stopMakingGIFs()` (StatusMenuController); `trimCapture(recordID:)`, `uploadTrimmed(recordID:)`, `trimMenuState(for:)` and, for a marked row, `openCapture(recordID:)` (RecentCapturesMenu). Nothing outside the family reads `trimmingIDs` or `deletingIDs`: `trimMenuState(for:)` answers for them.
- **Off the main actor.** `@concurrent` for `GIFMaker.make`, `RecordingMute.apply` and `stripAudio`, and `RecordingTrim.export`, `exportForSave` and `startsOnSyncSample`. Detached tasks for synchronous file work: the replace over the original, Trim's put, the pending move and removals. The GIF encoder's parts are `nonisolated` structs that run inside `GIFMaker`. The controller, the panel, the chrome, the Trim window and the settings are MainActor.
- **A recording is never lost.**
  - Every path from the recorder's `.keep` ends in exactly one `saveRecording` call: GIF success, failure, `Stop Making GIF` and quit, and each of the mute ladder's three outcomes.
  - `tmp/Recording/<id>.mp4` is removed only after the GIF's record exists. The mute rewrite and Trim reach the original only through `replaceItemAt` or `FileReplacement`, which leave it in place when they fail.
  - Every step that writes a copy removes it on any throw or cancel before it returns.
- **Muted sound never leaves.** A file whose muting failed (`unmutedIntervals`) never reaches the save folder, the upload, the clipboard or a drag, also after a crash or a kill, within the two limits Tim accepted (design, Privacy rule).
- **Nothing loads a video or a GIF into memory.** A GIF uploads from its file (a `.file` payload), and `GIFMaker` holds at most the current and the next decoded sample.
- **Exact strings, defaults, limits, menu titles and settings keys** come from the design.
- **Tests** use Swift Testing and never need Screen Recording, microphone access, a real Clop or the network. Movies come from `VideoFixtures`; the stream, the chrome, the devices, the access status, the free space and the mute log's write are faked. Run with:
  ```bash
  xcodegen generate && xcodebuild test -project TidyShot.xcodeproj -scheme TidyShot -destination 'platform=macOS' -derivedDataPath .build 2>&1 | grep -E "Test run with|error:|TEST"
  ```
  The baseline is the baseline small-tweaks leaves, about 1290 tests. The Release build is `xcodebuild -project TidyShot.xcodeproj -scheme TidyShot -configuration Release -derivedDataPath .build-rel build`.
- **Hand checks** need Screen Recording granted to the build and, from Task 4, microphone access. Builds are signed ad hoc (`Config/Local.xcconfig`), so every rebuild needs new grants, and only Tim grants them. Never open or change privacy settings and never run `tccutil`; the checklist gives those steps to Tim. When a hand check cannot run, say so in the report.
- **Commits.** Commit after every task with a conventional message and no attribution lines, and never push.

## Gaps this plan fills

The design leaves these open. Each is this plan's call. Task 9 records them in the design's Built notes, and the PR flags them.
1. **Settings are read at the start.** The hand-off reads the format, `GIF frame rate` and `GIF size` into `RecordingOptions`. They travel as `RecordingRequest.gif` and `Recording.gif`, so a change in Settings during a recording or its conversion does not reach it.
2. **Notices after Stop.** `RecordingNoticeOrder.afterStop(save:stop:microphone:quitMode:) -> [RecordingNotice]` gives `save`, `stop` and `microphone` in that order, skipping nils, and nothing in quit mode.
   - `save` is a notice of the save step that replaces `Recording saved`, as `Recording stopped` already does: `GIF not made` and `Sound removed`. So both always post in normal mode, whatever Show notification says.
   - `Sound not muted` is `RecordingSavePlan`'s own `.notice`, which `finishSave` posts before the list.
   - `saveRecording` posts the list after `finishSave`, or after the plan's notice on `.leftInTmp`, with `Recording stopped` revealing the final file. `endRecording` posts it for `.nothing`.
3. **`Recording.recoveryURL`** is the file the launch check recovers when the save leaves its file in `tmp/Recording`: `fileURL` for an MP4, the MP4 for a GIF. `placeRecording`'s `.leftInTmp` path names it, so `Not saved to a folder` names the MP4.
4. **Testable steps.**
   - `GIFConversion` (`TidyShot/Recording/GIFConversion.swift`) runs a conversion with `make`, `save`, `removeFile`, `freeBytes` and `isQuitting` injected.
   - `RecordingRecovery.prepare` decides each found file with the ladder injected: removed as already saved as a GIF, or recovered with its ladder's outcome. `RecordingRecovery.sweepMuteFolder` removes what the loop left in `tmp/Mute`.
   - `RecordingMute.resolve` also takes the rewrite's `output` URL and the file's `duration`, to close an open interval and make the segments, and returns the segments with the outcome.
5. **The GIF menu items** come first in the status menu, after `Stop Recording` when one runs, then a separator. The percentage is rounded down, so 100 % never shows while a conversion runs.
6. **Microphone devices** come through `MicrophoneDevices` (list, default, access, request), live on `AVCaptureDevice` and faked in tests. `MicrophoneChoice` takes plain `MicrophoneDevice` values and a `MicrophoneAccess`.
7. **Microphone loss mid-recording.** `RecordingEnvironment.microphoneLossReason: (String) -> String?` gives the replacement `Recording stopped` body for the recorded device id (`The microphone was disconnected.` or `Microphone access is off for TidyShot.`), or nil. The controller asks it on `.outputFailed` and `.streamStopped`.
8. **The mute log.** `MuteLog.directory` is the container's `tmp/Mute`, created by the first write. `MuteLog.url(for:)` is `tmp/Mute/<id>.json`. The controller makes the recording's `MuteLogWriter` at the first toggle, so a recording never muted has none.
9. **Trim.**
   - The download posts `Downloading <key>` under the title `Opening the recording…`, as the editor's download posts under `Opening the capture…`.
   - `Trim…`, the sheet and `Upload Trimmed` read `hasUploadDestination`: `settings.s3Config?.isComplete == true`, which never reads the keychain. Save and Upload and Upload Trimmed then call `makeDestination()`; with no credentials they post `Upload not configured` / `Set up a destination in Settings > Upload, then upload again.` and write nothing.
   - The method is decided on the source before the mute step (design, Method, amended to say so). A muted copy's video samples are the source's, so the answer is the same, and the `Trimming…` sheet can cover the mute step as the design asks.
   - A quit does not wait for a Trim pass. The export is abandoned with the app and `tmp/Trim` is cleared at the next launch; a put under way is `replaceItemAt`, which swaps the whole file or nothing.
   - The class body gets `// MARK: Trim state (AppCoordinator+Trim.swift)`: `trimWindows`, `trimPasses` and `trimmingIDs`, with a `//` line saying `+Upload` and `+Delete` read the marker and `+Delete` closes windows.
10. **Rows.**
    - A Recent Captures row has no Retry. The design's "Retry (card and row)" is the card's Retry and the menu's Retry Failed Uploads, which both go through `retryUpload` and `retry`.
    - A video row gains `scissors` (`Trim…`) after Copy File and, when shown, `arrow.up.circle` (`Upload Trimmed`) after it. The size gives way first when the detail is too wide (2.13).
    - A row marked `Sound not muted` opens the file on a click (`openCapture`), as Copy File is left out.
11. **Sizes (spec 2.13).**
    - A GIF's `byteCount` is the GIF's size after its move: `saveRecording` already reads the moved file's size, and the GIF is that file. After a failed conversion it reads the MP4's the same way.
    - A muted recording is rewritten in `tmp/Recording` before `saveRecording` moves it, and a recovered one before its move to `pending/`, so both sizes are the rewritten file's.
    - Trim reads the size of `tmp/Trim/<id>-trimmed.mp4` before the put moves it, and `finishTrimWrite(id:duration:byteCount:)` sets it with the duration. `.uploaded` then sets the bytes sent, as for any upload. A failed Save and Upload keeps the trimmed file's size, as a failed editor Upload keeps the edited file's.
12. **`saveRecording`'s new parameters** follow R1's Gap 2: `saveNotice:` (Gap 2), `microphoneNote:` and `unmutedIntervals:` (the ladder's `.notMuted` segments). Each defaults to none, so R1's callers compile.

### Before Task 1: the design, the plan and the probes

The plan PR's one commit (`docs: recording R2 design, plan and probes`). The probes live today only in the session's scratch folder, `/private/tmp/claude-501/-Users-tim-git-tidyshot/9a2da3be-945b-4f0e-b67d-e80f9e2ec325/scratchpad` (below, `<scratch>`); the spike's own `RESULTS.md` says it is not in the repo.

- [ ] Copy the design to `docs/superpowers/specs/2026-10-23-tidyshot-screen-recording-r2-design.md` and this plan to `docs/superpowers/plans/2026-10-23-recording-r2.md`.
- [ ] Copy the probe sources into `docs/superpowers/research/recording-probes/`, renamed to the names the design and this plan use:
  - `<scratch>/r2/probes/`: `togif.swift`, `trim.swift`, `mic.swift` and `mic2.swift` as they are, and `mute.swift` as `mute-empty-edit.swift` (the rejected empty edit, not the rewrite);
  - `<scratch>/r2/chk/fix/mute2.swift` as `mute-rewrite.swift` (the rewrite `apply` starts from). It copies the audio with `CMBlockBufferCreateContiguous` and flags 0, which can hand back the reader's own memory when the source is already contiguous; `apply` passes `kCMBlockBufferAlwaysCopyDataFlag`, so it never zeroes the reader's buffer;
  - `<scratch>/r2/priv-offset/`: `offset.swift` as `mute-offset.swift` (video and system audio), `offset-mic2.swift` as `mute-offset-mic.swift` (the microphone; arguments `<output> <microphone UID> <output device UID|default>`), `onsets2.py` as `mute-offset-onsets.py`, and `devs.swift` as `audio-devices.swift` (inputs and their CoreAudio properties);
  - `<scratch>/r2review-tools/` into `r2-review/`: `gifmem.swift` to `gifmem4.swift` (ImageIO's GIF memory), `genbench.swift` and `order.swift` (frame reading), `gifasset.swift`, `rewrite.swift` and `elst.py`;
  - `<scratch>/r2/gif-spike/` into `gif-encoder-spike/`: `gifspike.swift`, `ablate.sh`, `measure.sh`, `xdecode.py` and `RESULTS.md`. Not the binary, `abl/`, `final/`, `merge/` or `out/` (over 1 GB of outputs), and not the input recordings.
- [ ] Make the copies runnable from the repo:
  - `measure.sh` and `ablate.sh` take a work folder outside the repository as their first argument, in place of the hard-coded scratch path: it holds `window.mp4`, `p-area.mp4` and `p-4096.mp4`, the built `gifspike`, and the outputs (`final/`, `abl/`);
  - `RESULTS.md`'s first line says where the spike now lives and that its inputs and outputs are not committed;
  - the folder's `README.md` gains an R2 section: one line per file with what it probes and its arguments, built with the existing `xcrun swiftc` line and `-o` outside the repository.
- [ ] Check: `git grep -n -e "/private/tmp" -e scratchpad -- docs/superpowers/research/recording-probes` prints nothing, and each Swift probe compiles with the README's line.
- [ ] Commit.

### Task 1: Kinds, record fields, settings and pure helpers

**Files:**
- Create in `TidyShot/Recording/`:
  - `RecordingFormat.swift`: `RecordingFormat`, `GIFSettings`, `RecordingSettingsLayout`;
  - `MuteInterval.swift`.
- Modify:
  - `TidyShot/History/CaptureRecord.swift`: `MediaKind` (:5-36), `durationSeconds` (:89), `init` (:97-121), `CodingKeys` (:123-129), `init(from:)` (:137-157) and `isVideo` (:190);
  - every `isVideo` site (`git grep -n isVideo -- TidyShot TidyShotTests`): `+DragOut`, `+Editor`, `+Save`, `+Pins`, `+Upload`, `+RecordActions`, `RecentCaptureFormatting`, `ThumbnailProvider`, `RecentCaptureRow`, `QuickAccessView`, `QuickAccessCardDragSource`, `EditorInput`, and the tests;
  - `TidyShot/Editor/Persistence/EditorNaming.swift` (:29);
  - `TidyShot/App/AppCoordinator+Recording.swift`: `placeRecording` (:394-416);
  - `TidyShot/App/AppCoordinator+Upload.swift`: `startUpload` (:95-191), `refuseOversizedUpload` (:217-261) and `uploadPayload(for:)` (:362-377);
  - `TidyShot/App/AppCoordinator.swift`: the Upload state group (:112-157);
  - `TidyShot/Settings/AppSettings.swift`: `Keys` (:31-75), the Recording properties (:153-173), `register` (:198-240) and the reads (:241-290);
  - `TidyShot/Settings/CaptureSettingsView.swift`: `Section("Recording")` (:37-53);
  - `TidyShot/Recording/RecordingClock.swift`, `RecordingLimits.swift`, and `RecordingPanelView.swift` (:27).
- Tests:
  - create `TidyShotTests/RecordingSettingsLayoutTests.swift`;
  - add to `CaptureRecordTests`, `AppSettingsTests`, `RecordingClockTests`, `RecordingLimitsTests`, `EditorInputTests`, `EditorNamingTests`, `UploadPayloadTests`, `ThumbnailProviderTests` and `DragFileNameTests`.

**Produces** (all `nonisolated` and `Sendable` but the settings):
- `MediaKind.gif`: `gif`, `image/gif`, `UTType.gif`, and `var isSentToClop: Bool`, false for `.gif` only. An unknown raw value still reads as `.video`.
- `CaptureRecord`:
  - `var durationSeconds: Double?`, a `var` now;
  - `var unmutedIntervals: [MuteInterval]` (`decodeIfPresent`, default `[]`); non-empty is the `Sound not muted` mark;
  - `var isTimeBased: Bool` (`mediaKind != .image`), which replaces `isVideo`;
  - `var uploadBlockedReason: String?`: `soundNotMutedBody` when `unmutedIntervals` is non-empty, else nil;
  - `static let soundNotMutedTitle = "Sound not muted"` and `soundNotMutedBody` (`Muting failed. The recording is kept in TidyShot and not uploaded. Trim it to fix the sound, or delete it.`).
- `struct MuteInterval: Codable, Equatable { var start: TimeInterval; var end: TimeInterval? }`. A nil `end` is an open interval, as a mute log stores its last press.
- `RecordingFormat.swift`:
  - `enum RecordingFormat: String, Codable { case mp4, gif }`;
  - `struct GIFSettings: Equatable { var fps: Int; var maxSide: Int }`, where `maxSide` 0 is `Full size`; `var effectiveMaxSide: Int` is `RecordingConfiguration.maximumSide` for 0;
  - `struct RecordingSettingsLayout: Equatable`: `init(format:)`, `showsFrameRate`, `showsGIFRows`, `audioRowsEnabled`, `showsGIFCaption`, and `static let gifCaption` and `fullSizeCaption`.
- `AppSettings`:
  - `recordingFormat` (`.mp4`); `gifFrameRate` (15, one of `gifFrameRates = [10, 15, 20]`); `gifMaxSide` (1280, one of `gifMaxSides = [800, 1280, 0]`); `recordingMicrophone` and `recordingMicrophoneName` (empty). Each has the design's fallback.
  - `var gifSettings: GIFSettings`.
- `RecordingClock`: `static let gifSoftLimit: TimeInterval = 30`; `isPastSoftLimit(_ seconds: TimeInterval, format: RecordingFormat) -> Bool` replaces `isPastSoftLimit(_:)`.
- `RecordingLimits.hasRoom(for byteCount: Int64, freeBytes: Int64?) -> Bool`: true when `freeBytes` is at least `byteCount` plus `runningFreeBytes` (1 GB), or nil.
- `AppCoordinator.loggedGIFNotSentToClop`, in the Upload state group.

**Steps:**
- [ ] Write the tests and see them fail:
  - `CaptureRecordTests`: every item under Tests in the design, an open interval in the `unmutedIntervals` round trip, and `byteCount` still round-tripping beside them.
  - `AppSettingsTests`: the five keys default and persist; a stored `gifFrameRate` of 12 reads as 15, a `gifMaxSide` of 640 as 1280, and a `recordingFormat` of `webm` as `.mp4`.
  - `RecordingSettingsLayoutTests` from the design.
  - `RecordingClockTests`: `softLimitIsFiveMinutes` goes; GIF is past its limit at 30 s and not at 29.9 s, MP4 at 300 s and not at 299.9 s.
  - `RecordingLimitsTests`: the size plus exactly 1 GB has room and one byte less does not; nil has room; `hasRoom(for: 0, freeBytes: 999_999_999)` is false.
  - `EditorInputTests` and `EditorNamingTests` from the design.
  - `UploadPayloadTests`: `UploadPayload.video(for:saveFolder:fileExists:)` gives `.file` for a `.gif` record in `pending/` and in the save folder. It stands for the design's `uploadPayload(for:)` test, as the coordinator method cannot run in tests and sends `.gif` there.
  - `ThumbnailProviderTests` from the design.
  - `DragFileNameTests`: a `.gif` key keeps its name and gets no `.png`; with no key the name is the suggestion's, ending in `.gif`.
- [ ] Implement `MediaKind` and the record's fields. `recordLocalEdit` is unchanged.
- [ ] Rename `isVideo` to `isTimeBased` everywhere, mechanically, with no other change on those lines. Afterwards `git grep -n "isVideo" -- TidyShot TidyShotTests` prints nothing.
- [ ] Change the four sites that do not read `isVideo` (design, Kind):
  - `EditorNaming.saveAsSuggestion` uses `kind != .image ? recordingNamer : namer`;
  - `placeRecording` takes the extension from a new `kind` parameter (`saveRecording` passes `.video` until Task 3), and `refuseOversizedUpload` from `record.mediaKind`;
  - `uploadPayload(for:)` sends `.video` and `.gif` to `UploadPayload.video`;
  - `startUpload` computes `optimises` as `kind.isSentToClop && settings.optimiseWithClop && clopIsRunning()`. A `.gif` with `optimiseWithClop` on logs `Clop: GIFs are not sent to Clop` once per launch (`loggedGIFNotSentToClop`) and never calls `clopIsRunning()`.
- [ ] Implement `RecordingFormat`, `GIFSettings`, `RecordingSettingsLayout`, the settings keys, `RecordingClock` and `RecordingLimits.hasRoom`. `RecordingPanelView` calls `isPastSoftLimit(_:format: .mp4)` until Task 3 gives the panel its format.
- [ ] Change `Section("Recording")` as the design's Settings summary orders it, reading only `RecordingSettingsLayout`:
  - `Format` (`MP4`, `GIF`) first;
  - for GIF only, `GIF frame rate` (`10 fps`, `15 fps`, `20 fps`) and `GIF size` (`800 px`, `1280 px`, `Full size`), with `Full size GIFs can be very large.` under it;
  - `Frame rate` hidden for GIF; `Resolution` and its caption as now;
  - `Record system audio`, disabled for GIF, with `GIFs have no sound. Sound settings apply to MP4 recordings.` under it until Task 4 puts `Microphone` between them;
  - `Show cursor in recordings` and `Count down before recording`.
- [ ] Run the full suite.
- [ ] Commit: `feat: GIF kind, R2 recording settings and pure helpers`.

### Task 2: The GIF encoder

**Files:**
- Create in `TidyShot/Recording/GIF/`:
  - `GIFPalette.swift`: `GIFColour`, `GIFPalette`, `GIFPaletteBuilder`;
  - `GIFFrameDiffer.swift`: `GIFFrameDiffer`, `GIFFrameChange`;
  - `GIFLZWWriter.swift`;
  - `GIFSink.swift`: `GIFSink`, `GIFDataSink`, `GIFFileSink`, `GIFMakerError`;
  - `GIFEncoder.swift`: `GIFEncoder`, `GIFEncoderSummary`, `GIFTiming`.
- Create tests:
  - `TidyShotTests/Support/GIFBlocks.swift`;
  - `TidyShotTests/GIFPaletteBuilderTests.swift`, `GIFFrameDifferTests.swift`, `GIFLZWWriterTests.swift`, `GIFEncoderTests.swift`, `GIFFileSinkTests.swift`.

**Consumes:** Task 1's `RecordingLimits.hasRoom`.

**Produces** (all `nonisolated`; the design's Encoding gives each behaviour):
- `struct GIFColour: Hashable, Sendable { var r, g, b: UInt8 }`.
- `struct GIFPalette: Equatable, Sendable`: `colours` (1 to 255), `transparentIndex`, `tableBits`, `nearest(_:)`, and `var tableBytes: [UInt8]`, the `2^tableBits` entries padded with black.
- `struct GIFPaletteBuilder`: `init(minimumBoxSpread: Double = 2, refinementPasses: Int = 4)`, `mutating func add(rgba: UnsafeBufferPointer<UInt8>)`, `func build() -> GIFPalette`.
- `struct GIFFrameDiffer`: `init(width:height:palette:hysteresis: Int = 4)`, `private(set) var shown: [UInt8]`, `mutating func next(rgba:) -> GIFFrameChange?`.
- `struct GIFFrameChange: Equatable { var rect: GIFRect; var changedOnly: [UInt8]; var opaque: [UInt8] }`, with `struct GIFRect: Equatable { var x, y, width, height: Int }`.
- `struct GIFLZWWriter`: `mutating func encode(_ indices: UnsafeBufferPointer<UInt8>, minimumCodeSize: Int, into output: inout [UInt8])`.
- `protocol GIFSink`: `count`, `write(_:)`, `overwrite(_:at:)`, `close()`.
  - `struct GIFDataSink: GIFSink`, with `bytes: [UInt8]`.
  - `struct GIFFileSink: GIFSink`: `init(url: URL, freeBytes: @escaping @Sendable () -> Int64?) throws`; `static let bufferBytes = 1 << 20` and `spaceCheckBytes = 32 << 20`.
- `enum GIFMakerError: LocalizedError, Equatable { case notEnoughSpace, couldNotWrite }`, described as `Not enough disk space to make the GIF.` and `The GIF could not be written. The disk may be full.`
- `struct GIFEncoder<Sink: GIFSink>`: `init(sink:width:height:fps:palette:hysteresis:) throws`, `mutating func add(rgba:at:) throws`, `mutating func finish(frameCount:) throws -> GIFEncoderSummary`.
- `struct GIFEncoderSummary: Equatable, Sendable { var gifFrameCount, transparentFrameCount, opaqueFrameCount, byteCount: Int }`.
- `enum GIFTiming { static let maximumDelay = 65_535; static func centiseconds(through e: Int, fps: Int) -> Int }`.

**Steps:**
- [ ] Write `GIFBlocks` from the GIF89a format, reading no decoder's source:
  - `parse(_ bytes: [UInt8]) throws -> GIFFile`: the logical screen size, the global table flag and size, the NETSCAPE2.0 loop count, and per frame its graphic control extension (disposal, transparency flag, transparent index, delay), its image descriptor (rect, local table flag, interlace flag), its minimum code size and every sub-block length; then whether the trailer ends the file;
  - `oneFrame(palette:width:height:imageData:) -> [UInt8]`: header, logical screen, global table, one image descriptor at (0, 0), the writer's block and the trailer, with no `GIFEncoder`;
  - `decodedFrames(_ data: Data) -> [[GIFColour]]`, through `CGImageSourceCreateWithData`, each frame drawn into 8-bit sRGB RGBA; `delays(_ data: Data) -> [Int]` in centiseconds from the unclamped delay (`kCGImagePropertyGIFUnclampedDelayTime`); and `clampedDelays(_ data: Data) -> [Int]` in centiseconds from the clamped one (`kCGImagePropertyGIFDelayTime`), for the design's test that the two agree. Both round seconds × 100 to the nearest whole centisecond.
- [ ] Write the design's `GIFPaletteBuilderTests`, `GIFFrameDifferTests`, `GIFLZWWriterTests`, `GIFEncoderTests` and `GIFFileSinkTests`, and see them fail. Add to `GIFEncoderTests`: no frame is interlaced, and the summary's transparent and opaque counts add up to its frame count.
- [ ] Implement the palette, the differ, the LZW writer, the sinks and the encoder as the design's Encoding gives them. Start from the spike's `gifspike.swift`, which is TidyShot's own and already uses the design's constants (spread floor 2, hysteresis 4, 255 colours, the clear at 4096, the width rule).
  - The differ's nearest-colour cache has 64K direct-mapped entries keyed on the 24-bit colour, and never changes a result.
  - The encoder reuses its two LZW buffers and the change's two rectangles across frames, and writes the smaller of the transparent and opaque encodings, the transparent one on a tie.
  - `GIFFileSink` buffers 1 MB, writes with `write(2)`, patches a delay in its buffer or with `pwrite`, and reads `freeBytes` after every 32 MB written. Under 1 GB (`hasRoom(for: 0, freeBytes:)` false) throws `.notEnoughSpace`; a failed `open`, `write` or `pwrite` throws `.couldNotWrite`. It never removes its file: its caller does.
- [ ] Run the full suite.
- [ ] Commit: `feat: TidyShot's own GIF89a encoder`.

### Task 3: GIF recordings

**Files:**
- Create in `TidyShot/Recording/`: `GIFMaker.swift` (`GIFMaker`, `GIFResult`), `GIFConversion.swift` (`GIFConversion`, `GIFProgress`), `GIFProgressMenu.swift`, `RecordingNoticeOrder.swift`, `RecordingPanelLayout.swift`.
- Modify:
  - `RecordingConfiguration.swift`: `RecordingOptions` (:27-32) and `make` (:61-89);
  - `Recording.swift`: the new fields and `gifURL(for:)`;
  - `RecordingController.swift`: `RecordingRequest` (:7-12), the chrome's `show` in `run` (:148) and the `.keep` in `finish` (:355-361);
  - `RecordingChrome.swift`: the protocol's `show` (:9) and `RecordingScreenChrome` (:31-68);
  - `RecordingPanelView.swift`, and `RecordingPanel.swift` (:10), whose first frame no longer reads `RecordingPanelView.size`;
  - `RecordingRecovery.swift`;
  - `TidyShot/Settings/AppSettings.swift`: `recordingOptions` (:170-173);
  - `TidyShot/App/AppCoordinator.swift`: the Recording state group (:69-89), and `finishRecordingForQuit` (:385-393);
  - `TidyShot/App/AppCoordinator+Recording.swift`: `recordingHandOff` (:150-206), `recoverRecordings` (:237-270), `endRecording` (:272-284), `saveRecording` (:298-379) and `placeRecording`;
  - `TidyShot/App/StatusMenuController.swift`: `rebuild` (:75-127) and the actions (:150-169);
  - tests support: `VideoFixtures.makeMP4` (:21) and `FakeRecordingChrome` in `RecordingFakes.swift` (:109-176).
- Tests:
  - create `GIFMakerTests`, `GIFConversionTests`, `GIFProgressMenuTests`, `RecordingNoticeOrderTests` and `RecordingPanelLayoutTests`;
  - add to `RecordingConfigurationTests`, `RecordingControllerTests` and `RecordingRecoveryTests`.

**Consumes:** Task 1's `RecordingFormat`, `GIFSettings`, `MediaKind.gif`, `isPastSoftLimit(_:format:)` and `hasRoom`; Task 2's encoder and `GIFMakerError`.

**Produces:**
- `RecordingOptions` gains `format: RecordingFormat = .mp4` and `gif: GIFSettings = GIFSettings(fps: 15, maxSide: 1280)`, which `AppSettings.recordingOptions` fills.
- `RecordingConfiguration`:
  - `static let gifFramesPerSecond = 30`;
  - for `.gif`, `make` gives 30 fps and `capturesAudio` false whatever the options say, and the size from `Resolution` as for an MP4.
- `RecordingRequest.gif: GIFSettings?`, nil for an MP4, which the controller copies onto the kept `Recording`.
- `Recording` gains `var mediaKind: MediaKind = .video`, `var recoveryURL: URL` (defaulting to `fileURL`, Gap 3) and `var gif: GIFSettings? = nil`, and `static func gifURL(for id: UUID) -> URL` (`tmp/Recording/<id>.gif`).
- `GIFMaker`:
  - `struct GIFResult: Equatable, Sendable { var pixelWidth, pixelHeight, outputFrameCount, gifFrameCount: Int; var duration: TimeInterval; var byteCount: Int }`;
  - `@concurrent static func make(from mp4: URL, to gif: URL, fps: Int, maxSide: Int, freeBytes: @escaping @Sendable () -> Int64?, progress: @escaping @Sendable (Double) -> Void) async throws -> GIFResult`;
  - pure: `outputFrameCount(duration:fps:) -> Int`, `paletteSampleIndices(frameCount:) -> [Int]` and `outputSize(width:height:maxSide:) -> (width: Int, height: Int)`.
- `GIFConversion` (Gap 4):
  - `struct GIFProgress: Equatable, Sendable { var fraction: Double; var frameCount: Int }`;
  - `struct GIFConversion { var freeBytes: () -> Int64?; var make: (URL, URL, GIFSettings, @escaping @Sendable (Double) -> Void) async throws -> GIFResult; var save: (Recording, RecordingNotice?, RecordingSaveMode) async -> CaptureRecord?; var removeFile: (URL) -> Void; var isQuitting: () -> Bool }`;
  - `func run(_ mp4: Recording, settings: GIFSettings, onProgress: @escaping (GIFProgress) -> Void) async`;
  - `static func notMade(_ reason: String) -> RecordingNotice` (`GIF not made` / `<reason> The recording was saved as an MP4.`) and `static let stoppedReason = "Stopped."`.
- `GIFProgressMenu.items(_ conversions: [GIFProgress]) -> (progress: String, stop: String)?`, nil for none.
- `RecordingNoticeOrder.afterStop(save:stop:microphone:quitMode:) -> [RecordingNotice]` (Gap 2).
- `RecordingPanelLayout`:
  - `enum Bar: Equatable, Sendable { case plain, mute, gif }` and `static func bar(showsMute: Bool, isGIF: Bool) -> Bar`;
  - `static func size(of bar: Bar) -> CGSize`: 172 × 44, 208 × 44 and 208 × 44;
  - each bar's frames: `timeFrame`, `tagFrame` (GIF), `muteFrame` (mute), `stopFrame` and `cancelFrame`;
  - `static let timeFont`: 15 pt medium with monospaced digits.
- `RecordingChrome.show(onStop:onCancel:bar:)`. `RecordingScreenChrome` keeps its placement and lays the panel out at `show`, at the bar's size.
- `RecordingRecovery.isSavedAsGIF(_ found: Found, records: [CaptureRecord]) -> Bool`.
- `AppCoordinator`:
  - `gifConversions: [UUID: (task: Task<Void, Never>, progress: GIFProgress)]`, in the Recording state group;
  - `var gifProgressItems: (progress: String, stop: String)?` and `func stopMakingGIFs()`;
  - `saveRecording(_:intent:stopNotice:mode:saveNotice:)` (Gap 12).
- `VideoFixtures.makeMP4` gains `pattern: Int? = nil` (the line's column) and `frameTimes: [Double]? = nil`.

**Steps:**
- [ ] Extend `VideoFixtures` (design, Tests): `pattern` draws white frames with a 2 px black vertical line at the given even column; `frameTimes` writes frame `n` at the given time, with R1's level rule, for gaps and low source rates. R1's callers compile unchanged.
- [ ] Write the tests and see them fail:
  - `GIFMakerTests`, `GIFConversionTests` and `GIFProgressMenuTests` from the design.
  - `GIFMakerTests` also covers the pure parts: `outputFrameCount` is 150 for 10.0 s and 151 for 10.01 s at 15 fps, and 1 for 0 s; `paletteSampleIndices` gives 32 distinct indices from 0 to `F − 1` for `F` = 155, and `0..<F` for `F` ≤ 32; `outputSize` puts the long side at `maxSide` and rounds the other to whole pixels, never upscales, and keeps a source of up to 4096 px for `Full size` (`effectiveMaxSide`).
  - `RecordingNoticeOrderTests` from the design: the function is pure and takes the microphone note already, although nothing passes one until Task 4.
  - `RecordingPanelLayoutTests`: the 172 and GIF bars (the mute bar joins in Task 6), each with `9:59:59`: no frame leaves the bar, no two frames overlap, and the time's width measured in `timeFont` fits `timeFrame`.
  - `RecordingConfigurationTests`: a GIF recording never captures audio and records at 30 fps, with `systemAudio` on and 60 fps in the options.
  - `RecordingControllerTests`: `.keep` carries the request's `gif`; the chrome is shown with `.gif` for a GIF request and `.plain` otherwise.
  - `RecordingRecoveryTests`: `<id>.mp4` and a partial `<id>.gif` side by side; `isSavedAsGIF` holds only for an id with a `.gif` record.
- [ ] Implement `GIFMaker` as Conversion in the design gives it:
  - frame count and mapping: output frame `i` at `i / fps` shows the latest source frame at or before it;
  - two passes, each with its own `AVAssetReader` and BGRA track output, `alwaysCopiesSampleData` false, holding at most the current and the next sample;
  - pass 1 scales the palette samples into a `GIFPaletteBuilder`, skips a sample that shows the same source frame as the previous one, and cancels the reader after the last;
  - pass 2 skips held frames entirely and hands every other one to `GIFEncoder.add(rgba:at:)`;
  - each used frame becomes a `CGImage` with `VTCreateCGImageFromCVPixelBuffer` and is drawn into one reused 8-bit sRGB RGBA bitmap (`premultipliedLast`, big-endian, `.copy`, `.high`);
  - progress: 0 to 0.15 in pass 1 and 0.15 to 1 in pass 2, through `UploadQueue.ProgressThrottle`, never decreasing and once at 1;
  - `try Task.checkCancellation()` before each output frame; any throw closes the sink and removes `<id>.gif`; a failed reader or a missing first frame throws;
  - the SDK: use `AVAssetReader.outputProvider` if it is available on macOS 26.0, otherwise `copyNextSampleBuffer` and `add(_:)`, accepting the macOS 27 deprecation warnings. Task 9 notes which.
- [ ] Implement `GIFConversion.run` (design, Conversion, While it runs, On success, On failure, On quit). Each path calls `save` exactly once:
  1. With `isQuitting()`, save the MP4 in quit mode.
  2. Without room for 1 GB in `tmp/Recording` (`hasRoom(for: 0, freeBytes: freeBytes())`), save the MP4 with `notMade` of `GIFMakerError.notEnoughSpace`'s description, and never call `make`.
  3. `make` into `Recording.gifURL(for: id)`, passing progress on as `GIFProgress` with the output frame count.
  4. On success, save a `Recording` with the GIF's URL, its pixel size and duration, the MP4's poster, `mediaKind: .gif` and `recoveryURL` the MP4. A record back means the GIF left `tmp/Recording`: remove the MP4. No record (`.leftInTmp`): remove the GIF and keep the MP4.
  5. On a throw, remove the GIF. With `isQuitting()`, save the MP4 in quit mode; a `CancellationError` gives `notMade(stoppedReason)`; any other error `notMade` with its description.
- [ ] Implement `GIFProgressMenu`, `RecordingNoticeOrder` and `RecordingPanelLayout`, then the panel: the `GIF` tag before the time in the mute button's width, the time orange from `isPastSoftLimit(_:format:)`, every element at its layout frame.
- [ ] Wire the recording: `RecordingConfiguration.make` for GIF; the hand-off fills `RecordingRequest.gif` from `settings.recordingOptions` (Gap 1); the controller shows the chrome with `RecordingPanelLayout.bar(showsMute: false, isGIF: request.gif != nil)` and copies `gif` onto the kept `Recording`.
- [ ] Wire the save (design, Conversion; Gaps 2 and 3):
  - `endRecording`'s `.keep` with `recording.gif` runs a live `GIFConversion` in a task kept in `gifConversions[id]`, and awaits it. Progress hops to the main actor into the entry; the entry goes when `run` returns. The recording is already counted in `recordingSavesInFlight`, so the phase stays `.saving` and a new recording may start. `isRecording` clears at the hand-off as in R1.
  - `saveRecording` gains `saveNotice:`. It takes the record's kind and `placeRecording`'s extension from `recording.mediaKind`, gives `.leftInTmp` the path of `recording.recoveryURL`, suppresses `Recording saved` when `saveNotice` or `stopNotice` is set, and posts `afterStop(save: saveNotice, stop: stopNotice, microphone: nil, quitMode:)` after `finishSave`, `stop` revealing the final file.
  - `endRecording`'s `.nothing` posts `afterStop(save: nil, stop: notice, microphone: nil, quitMode: isQuitting)`.
  - The size needs no new code (Gap 11): `saveRecording` reads the moved file's size, the GIF's for a GIF and the MP4's after a failed conversion.
- [ ] `stopMakingGIFs()` cancels every entry's task. `finishRecordingForQuit` calls it right after setting `isQuitting`, so a conversion under way saves its MP4 in quit mode and one not yet begun skips `make`. Its wait for `.idle` is unchanged, so a quit never waits for a conversion.
- [ ] Status menu (Gap 5): `rebuild` reads `gifProgressItems` as the menu opens; the disabled `Making GIF… <n> %` (or `Making 2 GIFs… <n> %`) and `Stop Making GIF` (or `Stop Making GIFs`) come first, after Stop Recording when one runs, then a separator. Stop calls `stopMakingGIFs()`.
- [ ] Recovery: in `recoverRecordings`, before the move, a found file for which `isSavedAsGIF` holds is removed with the log line `Recording: <name> was saved as a GIF, removed`, instead of recovered. The scan already removes a partial `.gif` as unplayable.
- [ ] Run the full suite.
- [ ] Hand check in the Debug build, writing the results into the design's Probes section:
  - a GIF recording at each frame rate and size: sharpness zoomed on text, size and timing against the spike's, and a mostly static recording's size and frame count against a moving one's; the 30 s warning; the `GIF` tag and the time in the 208 pt bar;
  - `Making GIF… <n> %` moving through the palette pass, `Stop Making GIF`, two conversions at once, a quit during a conversion, and `kill -9` during one, then relaunch;
  - the encoder probe from Still to probe, with the spike's `measure.sh` (given a work folder outside the repository): a dark-mode recording, a low-contrast UI, a wide-gamut or HDR source and a wallpaper gradient, for size, MAE, a zoomed look and banding. Posterisation or banding Tim finds poor goes back to him (the selective ordered dither); the defaults do not change;
  - peak memory with `footprint TidyShot` during a conversion at the defaults and at `Full size`, for 10 s and 60 s;
  - Tim opens the spike's `final/*.gif` (which `measure.sh` remakes in its work folder) and an app-made GIF in Chrome and Firefox: they play, loop and hold their delays.
- [ ] Commit: `feat: GIF recordings`.

### Task 4: The microphone

**Files:**
- Create in `TidyShot/Recording/`: `MicrophoneChoice.swift`, `MicrophoneDevices.swift`.
- Modify:
  - `project.yml`: `targets.TidyShot.entitlements.properties` and `info.properties`;
  - `RecordingConfiguration.swift`: `RecordingOptions`, `RecordingConfiguration` (:36-49) and `make`;
  - `ScreenRecordingDriver.swift`: `streamConfiguration` (:114-131);
  - `RecordingController.swift`: `RecordingEnvironment` (:23-78) and `handle` (:239-265);
  - `RecordingSpike.swift`: a microphone option;
  - `TidyShot/Settings/CaptureSettingsView.swift`: the `Microphone` row;
  - `TidyShot/App/AppCoordinator.swift`: the Collaborators (`microphones`) and the Recording state group (`isAskingMicrophone`);
  - `TidyShot/App/AppCoordinator+Recording.swift`: `recordScreen` (:33-59), `recordFullscreen` (:64-79), `recordShortcutStarts` (:89-99), `recordingCanStart` (:103-121), `record` (:128-141), `recordingHandOff`, `endRecording` and `saveRecording`;
  - tests support: the test environment in `RecordingFakes.swift`.
- Tests: create `MicrophoneChoiceTests`; add to `RecordingConfigurationTests` and `RecordingControllerTests`.

**Consumes:** Task 1's two microphone keys, `RecordingFormat` and `RecordingSettingsLayout`; Task 3's `RecordingOptions` and `RecordingNoticeOrder`.

**Produces:**
- `struct MicrophoneDevice: Equatable, Sendable { var uniqueID: String; var name: String }`.
- `enum MicrophoneAccess: Equatable, Sendable { case authorized, denied, restricted, notDetermined }`.
- `MicrophoneChoice` (pure):
  - `enum Stored: Equatable { case off, systemDefault, device(id: String, name: String) }`, with `init(value:name:)` from `recordingMicrophone` and `recordingMicrophoneName`;
  - `struct Resolution: Equatable { var device: MicrophoneDevice?; var note: RecordingNotice? }` and `static func resolve(stored: Stored, devices: [MicrophoneDevice], defaultDevice: MicrophoneDevice?, access: MicrophoneAccess) -> Resolution`;
  - `struct Entry: Equatable { var tag: String; var title: String }` and `static func entries(stored: Stored, devices: [MicrophoneDevice]) -> [Entry]`: `Off`, `System Default`, each device, then a missing stored device as `<name> (not connected)` or `Unknown microphone (not connected)`;
  - `static func showsAccessNote(stored: Stored, access: MicrophoneAccess) -> Bool`;
  - `static func forRecording(_ stored: Stored, format: RecordingFormat) -> Stored`: `.off` for `.gif`, `stored` for `.mp4` (design, At the start: GIF and `Off` skip the prompt, `resolve`, the latency read and the note);
  - `static func asksForAccess(_ stored: Stored, format: RecordingFormat, access: MicrophoneAccess) -> Bool`: true only when `forRecording` is not `.off` and `access` is `.notDetermined`;
  - the design's strings, and `privacySettingsURL` (`x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone`).
- `protocol MicrophoneDevices: AnyObject { func list() -> [MicrophoneDevice]; func defaultDevice() -> MicrophoneDevice?; func access() -> MicrophoneAccess; func requestAccess() async -> Bool }`, and `final class LiveMicrophoneDevices` on `DiscoverySession([.microphone, .external], .audio)`, `AVCaptureDevice.default(for: .audio)`, `authorizationStatus(for: .audio)` and `requestAccess(for: .audio)`, with `static let changeNotifications` (`wasConnectedNotification`, `wasDisconnectedNotification`).
- `RecordingOptions.microphoneID: String?`; `RecordingConfiguration.captureMicrophone: Bool` and `microphoneDeviceID: String?`, never set for GIF.
- `RecordingEnvironment.microphoneLossReason: (String) -> String?` (Gap 7).
- `AppCoordinator`: `lazy var microphones: any MicrophoneDevices` and `isAskingMicrophone: Bool`.
- `saveRecording` gains `microphoneNote:` (Gap 12).
- DEBUG: `RecordingSpike` reads `-RecordingSpikeMicrophone <uniqueID|default>`.

**Steps:**
- [ ] Add to `project.yml` the entitlement `com.apple.security.device.audio-input: true` and the Info.plist key `NSMicrophoneUsageDescription: TidyShot records your microphone in screen recordings when you turn it on.` Asking for access without the usage string ends the process, so they come before any code that asks.
- [ ] Run the sandboxed spike (design, Still to probe). With `-RecordingSpikeMicrophone`, `RecordingSpike` asks for access when the status is `notDetermined`, logs the status before and after, and records with `captureMicrophone` on and `microphoneCaptureDeviceID` set (`default` is the default input's `uniqueID`).
  - Build Debug and run `open .build/Build/Products/Debug/TidyShot.app --args -RecordingSpike YES -RecordingSpikeMicrophone default`, speaking during the 3 s.
  - Expected: the first prompt names TidyShot with the usage string, and the file has one `soun` track that holds the speech.
  - Without Screen Recording or microphone access for this build, report that and go on with the pure parts. The controller asks Tim to grant them and run the command.
  - Write the result into the design's Probes. **Gate:** if the sandboxed capture differs from the unsandboxed probes (no prompt, no `soun` track, an error), report it; the steps the header's Gates name wait until the design is amended, and the rest of this task goes on.
- [ ] Write the tests and see them fail:
  - `MicrophoneChoiceTests`: the design's list, with `.notDetermined` then granted given to `resolve` as `.authorized`, as the start path reads the access again after the prompt; and `entries` for a present and a missing stored device, `showsAccessNote` for each access with and without a microphone set.
  - `MicrophoneChoiceTests`, the GIF start: `forRecording` gives `.off` for `.gif` from a present device, a missing device and `default`, and the stored value for `.mp4`; `resolve` over a GIF's `forRecording` with a missing stored device and access `.denied`, and again with no input at all, gives no device and no note; `asksForAccess` is false for `.gif` with `.notDetermined`, false for `Off`, and true for an MP4 with a microphone set and `.notDetermined`.
  - `RecordingConfigurationTests`: a `microphoneID` gives `captureMicrophone` and that ID; none gives neither; a GIF gives neither.
  - `RecordingControllerTests`: with `microphoneLossReason` answering `The microphone was disconnected.` for the recorded ID, an `outputFailed` and a `streamStopped` each end with that body; answering nil, with R1's.
- [ ] Implement `MicrophoneChoice`, `LiveMicrophoneDevices`, the configuration, the driver's `captureMicrophone` and `microphoneCaptureDeviceID`, and the controller's loss reason. The live `microphoneLossReason` gives `The microphone was disconnected.` when the ID is missing from `microphones.list()`, and `Microphone access is off for TidyShot.` when access is not `.authorized`.
- [ ] Add the `Microphone` row between `Record system audio` and the GIF caption (design, Setting and Permission):
  - a `Picker` over `MicrophoneChoice.entries`, refreshed when the tab appears and on the two device notifications; a pick writes the name, and the name is refreshed whenever the list sees the stored device;
  - a pick while access is `notDetermined` calls `requestAccess`; a refusal, or a pick while access is denied, goes back to `Off`;
  - with `showsAccessNote`, `Microphone access is off for TidyShot.` and `Privacy Settings…`, which opens `privacySettingsURL`; the access is read again on `NSWindow.didBecomeKeyNotification` for the Settings window;
  - disabled for GIF, as `Record system audio` is.
- [ ] Wire the start (design, At the start):
  - `recordShortcutStarts` returns false while `isAskingMicrophone`, logging `Recording: start ignored, the microphone prompt is open`.
  - Both record functions read the stored choice once, as `MicrophoneChoice.forRecording(Stored(value:name:), format: settings.recordingFormat)`. For a GIF, and for `Off`, that is `.off`: no prompt, no `resolve`, no latency read (Task 6) and no note, whatever the access or the devices.
  - Right after `recordShortcutStarts`, when `asksForAccess` holds, both record functions set `isAskingMicrophone`, await `requestAccess`, clear it, and return if `isQuitting`. Nothing else is held while the prompt is up.
  - Under the lock, beside the disk check in `recordingCanStart` and before the selection overlay or the count-in, when the choice is not `.off`, the access is read again and `MicrophoneChoice.resolve` runs over `microphones.list()` and `defaultDevice()`. Nothing there awaits. With `.off` the `Resolution` is no device and no note.
  - The `Resolution` goes through `record` and the hand-off into `RecordingOptions.microphoneID`, and its note comes back out beside the outcome.
- [ ] Post the note last (design, The note posts after Stop): `endRecording` passes it as `microphone` to `afterStop`, through `saveRecording(… microphoneNote:)` for `.keep`, and directly for `.nothing`, whenever `recorder.run` ran.
- [ ] Run the full suite.
- [ ] Build Release and check it:
  - `codesign -d --entitlements - .build-rel/Build/Products/Release/TidyShot.app 2>&1 | grep -c "device.audio-input"` prints 1;
  - `/usr/libexec/PlistBuddy -c "Print :NSMicrophoneUsageDescription" .build-rel/Build/Products/Release/TidyShot.app/Contents/Info.plist` prints the string;
  - `strings .build-rel/Build/Products/Release/TidyShot.app/Contents/MacOS/TidyShot | grep -c RecordingSpikeMicrophone` prints 0.
- [ ] Hand check in the Debug build (design, Settings and Microphone hand checks), writing the mid-recording results into the design's Probes:
  - each input, access granted and denied;
  - after a rebuild with a microphone set, for Record Screen and Record Fullscreen: the prompt shows before the selection overlay or the count-in, Allow records with the microphone, and a Deny records without it with the note after Stop and after the save's own notification; with the prompt up, a second Record press does nothing (logged), a screenshot shortcut works, and Quit quits without recording;
  - a GIF recording with a microphone set, once with access denied and once with the input unplugged: no prompt, and no microphone note after Stop;
  - the chosen input unplugged before recording gives `Recorded with <default input name>`; the RODE AI-1 plugged and unplugged with the tab open; `Privacy Settings…` and the note clearing once Tim allows access;
  - access turned off by Tim, and the input unplugged, each during a recording: what ScreenCaptureKit does, whether the file plays, and whether it is saved with `Recording stopped` and the right body.
- [ ] Commit: `feat: record the microphone`.

### Task 5: Muting a recording's file

**Files:**
- Create in `TidyShot/Recording/`: `RecordingMute.swift`, `MuteLog.swift`.
- Modify:
  - `RecordingSavePlan.swift`: `target(for:)` (:69-71) and `make` (:78-134);
  - `Recording.swift`: `muteIntervals` and `lag`;
  - `RecordingRecovery.swift`;
  - `TidyShot/App/AppCoordinator+Recording.swift`: `endRecording`, `saveRecording` and `recoverRecordings`;
  - `TidyShot/App/AppCoordinator+Upload.swift`: `startUpload` (:95), `retryFailedUploads` (:318) and `retry` (:333);
  - `TidyShot/App/AppCoordinator+RecordActions.swift`: `copyLinkOrFile` (:8), `copyFile` (:25) and `saveAs` (:104);
  - `TidyShot/App/AppCoordinator+DragOut.swift`: `prepareDragFile` (:13);
  - tests support: `VideoFixtures.makeMP4`.
- Tests: create `RecordingMuteTests` and `UploadRefusalTests`; add to `RecordingSavePlanTests` and `RecordingRecoveryTests`.

**Consumes:** Task 1's `MuteInterval`, `unmutedIntervals`, `uploadBlockedReason` and `hasRoom`; Task 3's `saveNotice:`, `RecordingNoticeOrder` and `isSavedAsGIF`.

**Produces:**
- `MuteLog.swift`:
  - `struct MuteLog: Codable, Equatable, Sendable { var intervals: [MuteInterval]; var lag: TimeInterval; var sequence: Int }`;
  - `static var directory: URL` (`tmp/Mute`, which reading it does not create) and `static func url(for id: UUID) -> URL` (Gap 8);
  - `static func write(_ log: MuteLog, to url: URL) throws`, atomic, creating the folder;
  - `enum Read: Equatable { case none, unreadable, log(MuteLog) }` and `static func read(_ url: URL) -> Read`.
- `RecordingMute`:
  - `static let lead: TimeInterval = 0.1` and `defaultLag: TimeInterval = 0.3`;
  - `static func segments(duration: TimeInterval, intervals: [MuteInterval], lead: TimeInterval, lag: TimeInterval) -> [MuteInterval]`, which closes an open interval at `duration`, widens, merges and clamps, and drops none;
  - `@concurrent static func apply(_ source: URL, intervals: [MuteInterval], to output: URL) async throws`;
  - `@concurrent static func stripAudio(_ source: URL, to output: URL) async throws`;
  - `static func replaceOriginal(_ original: URL, with output: URL) throws` (design, A failed replace);
  - `static func rewriteURL(for id: UUID) -> URL` (`tmp/Mute/<id>.mp4`);
  - `enum Outcome: Equatable, Sendable { case muted, soundRemoved, notMuted }` and `struct Resolution: Equatable, Sendable { var outcome: Outcome; var segments: [MuteInterval] }`;
  - `static func resolve(file: URL, output: URL, duration: TimeInterval, intervals: [MuteInterval], lag: TimeInterval, hasRoom: (URL) -> Bool, apply: (URL, [MuteInterval], URL) async throws -> Void, stripAudio: (URL, URL) async throws -> Void, replace: (URL, URL) throws -> Void) async -> Resolution` (Gap 4);
  - `static let soundRemovedNotice` (`Sound removed` / `Muting failed, so the recording has no sound.`);
  - `struct Steps: Sendable { var apply: @Sendable (URL, [MuteInterval], URL) async throws -> Void; var stripAudio: @Sendable (URL, URL) async throws -> Void; var replace: @Sendable (URL, URL) throws -> Void }` and `static var live: Steps`: `apply`, `stripAudio` and `replaceOriginal`, which in DEBUG builds the `-MuteFailure` wrapper makes throw. The end of a recording and recovery both pass `Steps.live` to `resolve`, so neither can build its ladder from unwrapped steps;
  - DEBUG only: `enum MuteFailure { case apply, both }`, read from `-MuteFailure`, and the wrapper `Steps.live` applies.
- `RecordingSavePlan`:
  - `target(for:unmutedIntervals:)`, `.pending` whenever the intervals are non-empty;
  - `make(action:hasDestination:result:copyImage:alsoCopyImage:quitMode:unmutedIntervals: [MuteInterval] = [])`;
  - `static let soundNotMutedNotice` (`CaptureRecord.soundNotMutedTitle` and `soundNotMutedBody`).
- `RecordingRecovery`:
  - `enum Prepared: Equatable { case savedAsGIF; case recover(unmutedIntervals: [MuteInterval], bodySuffix: String?, removesLogAfterRecord: Bool) }`;
  - `static func prepare(_ found: Found, records: [CaptureRecord], muteDirectory: URL, resolve: (URL, TimeInterval, [MuteInterval], TimeInterval) async -> RecordingMute.Resolution) async -> Prepared`, which folds in Task 3's `isSavedAsGIF`;
  - `static func sweepMuteFolder(_ muteDirectory: URL, recordingDirectory: URL)`;
  - `mutedSuffix`, `soundRemovedSuffix` and `notMutedSuffix`: `The muted parts were silenced.`, `It was saved without sound.` and `Its sound is not muted, so it was not uploaded.`
- `Recording` gains `var muteIntervals: [MuteInterval] = []` and `var lag: TimeInterval = RecordingMute.defaultLag`.
- `saveRecording` gains `unmutedIntervals:` (Gap 12).
- `AppCoordinator` (`+Upload`): `nonisolated static func uploadRefusal(for record: CaptureRecord) -> String?` and `nonisolated static func failedRecordsToRetry(_ records: [CaptureRecord], deletingIDs: Set<UUID>) -> [CaptureRecord]`.
- `VideoFixtures.makeMP4` gains `tone: [ClosedRange<Double>]? = nil`: a 1 kHz sine at −6 dBFS within the ranges and silence elsewhere.

**Steps:**
- [ ] Extend `VideoFixtures` with `tone`. `audio: true` with no `tone` stays silent.
- [ ] Write the tests and see them fail:
  - `RecordingMuteTests`: the design's items for `segments`, `apply`, the tone 0.13 s past an interval's end, a file with no audio track (its video comes through unchanged and it still has no audio), `apply` on its own output, the log, `resolve`, the folder that refuses writes and the cancel, a folder that does not exist yet (`apply` and `stripAudio` create it), and the one `<id>.mp4` after the replace. The controller and writer items are Task 6's. `resolve`'s tests inject the steps over temporary files.
  - `RecordingSavePlanTests`: the design's two items.
  - `RecordingRecoveryTests`: the design's log items, through `prepare` with an injected ladder and through `sweepMuteFolder`; `prepare` gives `.savedAsGIF` for an id with a `.gif` record.
  - `UploadRefusalTests`: `uploadRefusal` is the mark's text for a marked record and nil otherwise; `failedRecordsToRetry` leaves out a marked record and a deleting one.
- [ ] Implement `MuteLog` and `segments`.
- [ ] Implement `apply` from the probe `mute-rewrite.swift` (design, After the end): video sample buffers pass through (reader and writer `outputSettings` nil, `sourceFormatHint` from the track's format description, `transform` from its `preferredTransform`); audio is read as 16-bit interleaved LPCM, the samples inside a segment are zeroed on a copy of the buffer (`CMBlockBufferCreateContiguous` with `kCMBlockBufferAlwaysCopyDataFlag`, unlike the probe), and it is written as AAC at the source's sample rate and channel count at 128 kbps. Never `insertEmptyTimeRange` or an audio mix. It creates `output`'s folder when it is missing (`tmp/Mute` exists only once a log write has succeeded; `tmp/Trim` is removed at launch), removes any file at `output` first, and removes its partial output on any throw or cancel. The SDK choice is Task 3's.
- [ ] Implement `stripAudio` (a composition of the video track alone, exported with passthrough; it creates `output`'s folder when missing, and removes its partial output on any throw or cancel), `replaceOriginal` (same-volume `replaceItemAt`; when it throws and the original is missing, the output is renamed into place and the step counts as done) and `resolve`:
  1. Without room in `tmp/Mute` for the file's size plus 1 GB: `.notMuted`, with `Recording: mute skipped, not enough disk space` logged, and neither step called.
  2. `apply` into `output`, then `replace`: `.muted`.
  3. A failed `apply` or `replace`: log `Recording: mute failed: <description>`, remove `output`, then `stripAudio` into it and `replace`: `.soundRemoved`.
  4. A failed step there: `.notMuted`.
  5. `output` is removed on every exit.
- [ ] Implement the save plan changes.
- [ ] Wire the end (design, After the end, Privacy rule). In `endRecording`, for a `.keep` MP4 with non-empty `recording.muteIntervals`, before `saveRecording`, run `resolve` with `RecordingMute.Steps.live` (wrapped by `-MuteFailure` in DEBUG), `rewriteURL(for:)`, the recording's duration and lag, and `hasRoom` on `tmp/Mute`, which creates the folder first so its volume's free space is read rather than counted as enough. The recording is already counted in `recordingSavesInFlight`, so the quit hold covers it, in quit mode too.
  - `.muted`: remove the log, then save.
  - `.soundRemoved`: remove the log, then save with `saveNotice: soundRemovedNotice`. In quit mode nothing posts (`afterStop` gives nothing), and `resolve`'s log line is the only trace.
  - `.notMuted`: save with `unmutedIntervals:` the segments, and remove the log once the record exists; with no record (`.leftInTmp`) it stays for the next launch.
  - `saveRecording` passes the intervals to `target(for:unmutedIntervals:)`, so no folder panel opens and the file goes straight to `pending/`, and to `make`, and sets them on the record.
- [ ] Wire recovery (design, Relaunch). `recoverRecordings` builds `prepare`'s `resolve` closure from the same `RecordingMute.Steps.live` as the end, so `-MuteFailure` reaches recovery too (Task 6's `kill -9` check relaunches with `-MuteFailure both`), with `rewriteURL(for: found.id)` and the same `hasRoom`. Each found file goes through `prepare` before its move: `.savedAsGIF` removes it with Task 3's log line; `.recover` moves it, makes the record with `unmutedIntervals`, adds the suffix to `Recovered a recording`'s body, and removes the log after `history.add` when asked. After the loop, `sweepMuteFolder`. The size is read after the move (Gap 11).
- [ ] Add the gates (design, Privacy rule):
  - `uploadRefusal` at the top of `retry(recordID:destination:)`, posting `Not uploaded` with it;
  - `uploadRefusal` in `startUpload` right after `guard let record = history.record(id:)` and before `uploadingIDs` changes, as the design places it. It is a backstop: it logs `Upload: refused for <file name>: <reason>` with `NSLog` and returns, posting nothing and changing no state, because each caller a user drives (`retry`, and Task 7's `uploadTrimmed`) has refused with its own notice first and `retryFailedUploads` skips silently;
  - `failedRecordsToRetry` in `retryFailedUploads`, which skips a marked record with no notice;
  - `copyFile`, `copyLinkOrFile`'s file branch, `saveAs` and `prepareDragFile` do nothing for a marked record. Task 8 leaves the matching buttons out of the card and the row.
- [ ] Run the full suite.
- [ ] Build Release and check that the fault injection is not in it: `strings .build-rel/Build/Products/Release/TidyShot.app/Contents/MacOS/TidyShot | grep -c MuteFailure` prints 0.
- [ ] Commit: `feat: mute rewrite, the privacy ladder and recovery`.

Nothing records a mute until Task 6, so this task's hand checks run there.

### Task 6: The mute button

**Files:**
- Create in `TidyShot/Recording/`: `MicrophoneLatency.swift`, `MuteLogWriter.swift`.
- Modify:
  - `RecordingController.swift`: `RecordingRequest`, `RecordingEnvironment`, `run`, `reset` (:211-224), `handle`, `end` (:312-322) and `finish` (:333-366);
  - `RecordingChrome.swift`, `RecordingPanel.swift` (:9-28), `RecordingPanelView.swift` and `RecordingPanelLayout.swift`;
  - `RecordingConfiguration.swift`: `showsMuteButton`;
  - `TidyShot/App/AppCoordinator+Recording.swift`: `recordingCanStart` and `recordingHandOff`;
  - tests support: `RecordingFakes.swift` (`FakeRecordingChrome.pressMute()`, the test environment's writer).
- Tests: create `MicrophoneLatencyTests` and `MuteLogWriterTests`; add to `RecordingControllerTests`, `RecordingPanelLayoutTests` and `RecordingConfigurationTests`.

**Consumes:** Task 3's `RecordingPanelLayout`; Task 4's resolved device; Task 5's `MuteLog`, `RecordingMute.defaultLag` and the ladder.

**Produces:**
- `MicrophoneLatency`:
  - `enum Transport: Equatable, Sendable { case bluetooth, other }`;
  - `static func lag(reported: TimeInterval?, transport: Transport?) -> TimeInterval`: `max(0.3, 2 × reported + 0.05)`, and at least 0.6 for Bluetooth or a nil `reported`;
  - `static let noMicrophone: TimeInterval = 0.3`;
  - `static func read(deviceUID: String) -> (reported: TimeInterval?, transport: Transport?)` from CoreAudio (design, Lag).
- `final class MuteLogWriter: Sendable`:
  - `init(url: URL, write: @escaping @Sendable (MuteLog, URL) throws -> Void = MuteLog.write)`;
  - `func yield(_ log: MuteLog)`, synchronous, into an `AsyncStream` with `.bufferingNewest(1)`;
  - `func finish() async`, which finishes the stream and awaits the consumer.
- `RecordingRequest` gains `lag: TimeInterval` and `muteLogURL: URL`; `RecordingEnvironment` gains `makeMuteLogWriter: (URL) -> MuteLogWriter`.
- `RecordingController`: `private(set) var isMuted` and `func toggleMute()`. The kept `Recording` carries `muteIntervals` and `lag`.
- `RecordingConfiguration.showsMuteButton` (`capturesAudio || captureMicrophone`).
- `RecordingChrome`: `show(onStop:onCancel:onMute:bar:)` and `setMuted(_:)`; `RecordingPanelLayout`'s `.mute` bar.

**Steps:**
- [ ] Run the input-latency probe (design, Still to probe). Extend `mute-offset-mic.swift` (copied in before Task 1) to print, for the input it records from, the four CoreAudio latency properties, the nominal sample rate, the transport type and the lag `MicrophoneLatency.lag` would give. Tim runs it with AirPods and the Brio 500, and with the iPhone input and a USB input to compare. Write each input's measured offset, reported latency and lag into the design's Probes. **Gate:** an input whose measured offset falls outside its lag goes back to Tim; this plan does not change the constants, and the rest of this task goes on (header, Gates).
- [ ] Write the tests and see them fail: `MicrophoneLatencyTests`, `MuteLogWriterTests` and the `RecordingControllerTests` mute items from the design. Add:
  - `RecordingControllerTests`: a discarding Cancel and the end rule's removal each remove the mute log after the writer has finished; the kept recording's `lag` is the request's; an MP4 with sound shows `.mute`, one without `.plain`, and a GIF `.gif`;
  - `RecordingPanelLayoutTests`: the mute bar, as the other two;
  - `RecordingConfigurationTests`: the mute button shows only for `capturesAudio || captureMicrophone`.
- [ ] Implement `MicrophoneLatency`. `read` finds the device by UID (`kAudioHardwarePropertyTranslateUIDToDevice`), then reads on the input scope `kAudioDevicePropertyLatency`, `kAudioDevicePropertySafetyOffset` and `kAudioDevicePropertyBufferFrameSize`, plus the first input stream's `kAudioStreamPropertyLatency`, over `kAudioDevicePropertyNominalSampleRate`; `kAudioDevicePropertyTransportType` Bluetooth or Bluetooth LE is `.bluetooth`. Any failed read gives nil.
- [ ] Implement `MuteLogWriter`: one consumer task off the main actor takes the logs one at a time, skips one whose `sequence` is not above the last written, writes atomically, and logs a failed write.
- [ ] Implement the controller's mute (design, State, Mute log):
  - intervals on the controller's clock from `recordingStarted`; a press before the first frame opens at 0; a press once the recording is ending is ignored; the state and the list reset in `reset`;
  - each toggle yields `MuteLog(intervals:lag:sequence:)` to the writer, which the first toggle makes (Gap 8), then calls `chrome.setMuted`;
  - every end closes an open interval at `elapsedAtEnd` and awaits `writer.finish()` before `finish` returns or touches the log; a discard then removes the log;
  - the kept `Recording` gets the closed intervals and the request's lag.
- [ ] Add the button (design, Mute, Bar, Tool tips): between the time and Stop, `speaker.wave.2.fill` or `speaker.slash.fill`, tool tips `Mute the sound` / `Unmute the sound`, accessibility labels `Mute` / `Unmute`, disabled with Stop. `RecordingPanel.init` sets `allowsToolTipsWhenApplicationIsInactive = true` beside `hidesOnDeactivate = false`. The controller picks the bar with `RecordingPanelLayout.bar(showsMute: configuration.showsMuteButton, isGIF:)`.
- [ ] Wire the lag (design, Lag): beside `resolve`, the coordinator reads `MicrophoneLatency.read(deviceUID:)` for the resolved device and takes `lag(reported:transport:)`. With no resolved device, which includes every GIF and `Off` start (Task 4 runs no `resolve` for them), it reads no CoreAudio property and takes `noMicrophone`. It logs `Recording: mute lag <s> s (<device name, or no microphone>)`, and passes it in `RecordingRequest.lag` with `muteLogURL: MuteLog.url(for: id)`.
- [ ] Run the full suite.
- [ ] Hand check in the Debug build (design, the Microphone hand checks' mute items, and Task 5's), writing the results into the design:
  - mute on and off with the microphone and with system audio, pressed in the first second, and Stop while muted; with Clop on, the link played in Safari and Chrome; with Clop off, the saved file in QuickTime and in VLC or IINA. The muted stretches are silent, sound after them is in sync, and the audio ends with the video;
  - the iPhone input, a USB input and AirPods: the logged lag, which matches the probe's lag for that input (so the sandboxed app reads the CoreAudio properties; 0.6 s for a wired input means it does not), and a word started within 0.2 s of each click is silent;
  - `-MuteFailure apply`: `Sound removed`, and the file has no audio track;
  - `-MuteFailure both`, for Save with a folder set, Save with none, Upload and Upload only: no folder panel, the file in `pending/` and not in the save folder, nothing uploads, the clipboard unchanged, `Sound not muted` posts, Retry Failed Uploads skips it, and a relaunch keeps the mark (the card and row text come in Task 8);
  - `kill -9` during a muted recording, then a relaunch with `-MuteFailure both`: the recovered record's notice says it was not uploaded;
  - `kill -9` (a) during a recording while muted, (b) just after Stop, (c) during the rewrite: after each relaunch the muted stretch is silent and one record appears;
  - the button hidden for GIF and for an MP4 with no sound; with another app frontmost, the mute and Cancel tool tips show and are not in the video.
- [ ] Commit: `feat: mute during a recording`.

### Task 7: Trim

**Files:**
- Create:
  - `TidyShot/Recording/RecordingTrim.swift`;
  - `TidyShot/Trim/TrimWindowController.swift`;
  - `TidyShot/App/AppCoordinator+Trim.swift`.
- Modify:
  - `TidyShot/History/CaptureRecord.swift`: `recordLocalTrim(duration:at:)` beside `recordLocalEdit` (:179);
  - `TidyShot/Editor/Persistence/EditorSaveTarget.swift`: `EditorAvailability` (:109-139);
  - `TidyShot/Editor/Persistence/EditorUploadPlan.swift`: `failedReplaceMessage` (:31);
  - `TidyShot/History/CaptureDeletion.swift`;
  - `TidyShot/App/AppCoordinator.swift`: the Trim state group (Gap 9), and `start()` (:214-240);
  - `TidyShot/App/AppCoordinator+Upload.swift`: `uploadRefusal`, `failedRecordsToRetry`, `startUpload`, `retryUpload` (:306), `retry`, `retryFailedUploads`, and `handle(_:at:)`'s `.uploaded` and `.failed` (:439-505);
  - `TidyShot/App/AppCoordinator+Delete.swift`: `deleteCapture` (:14), `removeRecord` (:134-155) and `removeFiles(ofPruned:)` (:213-235);
  - `TidyShot/App/AppCoordinator+Editor.swift`: `replaceThumbnail` (:249), widened;
  - `TidyShot/App/AppCoordinator+RecordActions.swift`: `downloadSource` (:251), widened;
  - tests support: `VideoFixtures.makeMP4`.
- Tests: create `RecordingTrimTests`; add to `CaptureRecordTests`, `EditorUploadPlanTests` and `UploadRefusalTests`.

**Consumes:** Task 1's mutable `durationSeconds` and `hasRoom`; Task 5's `RecordingMute.apply`, `unmutedIntervals` and `uploadRefusal`.

**Produces:**
- `RecordingTrim`, its pure parts `nonisolated`:
  - `static var directory: URL` (`tmp/Trim`), `downloadURL(for:)` (`<id>.mp4`), `trimmedURL(for:)` (`<id>-trimmed.mp4`) and `mutedURL(for:)` (`<id>-muted.mp4`);
  - `static let minimumDuration: TimeInterval = 0.5`, `notTrimmedTitle`, `tooShortText` and `notEnoughSpaceText`;
  - `static func range(start: CMTime, end: CMTime, duration: CMTime) -> Result<CMTimeRange, TrimRefusal>`, where an invalid time is the file's start or end;
  - `enum Source: Equatable { case pendingFile(URL), saveFolderFile(URL, folder: URL), download(key: String, location: ObjectLocation), unavailable(String) }` and `static func source(for record: CaptureRecord, saveFolder: URL?) -> Source`, in `EditorInput.source`'s order and with its texts;
  - `enum SheetButton: Equatable { case save, saveAndUpload, cancel }`, `struct Sheet: Equatable { var buttons: [SheetButton]; var linkSentence: String? }` and `static func sheet(plan: EditorSaveTarget.Plan, hasDestination: Bool, hasLink: Bool) -> Sheet?` (the design's table; nil for its last row), with `static func informativeText(kept: TimeInterval, of total: TimeInterval, sheet: Sheet) -> String`;
  - `static func showsTrim(_ record: CaptureRecord) -> Bool` (`mediaKind == .video`) and `static func canTrim(_ record: CaptureRecord, saveFolder: URL?, hasDestination: Bool, isDeleting: Bool, isTrimming: Bool) -> Bool`;
  - `struct MenuState: Equatable { var showsTrim, canTrim, showsUploadTrimmed, canUploadTrimmed, isTrimming: Bool }` and `static func menuState(_ record: CaptureRecord, saveFolder: URL?, hasDestination: Bool, isDeleting: Bool, isTrimming: Bool) -> MenuState`. `Upload Trimmed` shows for a `.video` with `uploadIsStale`, a local file and a destination, and is disabled while the record uploads, is deleted or is trimmed;
  - `enum WritePlan: Equatable { case refuse(String), saveTarget(EditorSaveTarget.Plan), newPendingFile }` and `static func writePlan(_ button: SheetButton, record: CaptureRecord?, saveFolder: URL?, isDeleting: Bool) -> WritePlan`, which asks `EditorAvailability.refusal` with `isTrimming: false` (the marker is the pass's own), then `EditorSaveTarget.plan` and `uploadWrite`;
  - `enum AfterPut: Equatable { case finish, removePendingFile(URL), keepFile }` and `static func afterPut(_ plan: WritePlan, fileURL: URL, recordExists: Bool) -> AfterPut`;
  - `enum TrimMethod: Equatable, Sendable { case passthrough, reencode }`;
  - `@concurrent static func startsOnSyncSample(_ url: URL, at start: CMTime) async throws -> Bool`;
  - `@concurrent static func export(_ source: URL, range: CMTimeRange, method: TrimMethod, to output: URL, progress: @escaping @Sendable (Double) -> Void) async throws`;
  - `@concurrent static func exportForSave(_ source: URL, id: UUID, range: CMTimeRange, method: TrimMethod, unmutedIntervals: [MuteInterval], directory: URL = RecordingTrim.directory, freeBytes: @escaping @Sendable () -> Int64?, progress: @escaping @Sendable (Double) -> Void) async throws -> URL`: it creates `directory` when it is missing, then the disk check, the mute step and the export, returning `<id>-trimmed.mp4` in `directory` with no `-muted.mp4` left. `directory` is for tests.
- `TrimWindowController`: `init(recordID:fileURL:)`; `onRange: (CMTime, CMTime) -> Void` and `onClose: () -> Void`; `func askToSave(message:informativeText:buttons:) async -> SheetButton`; `func showProgress(onStop:)`, `setProgress(_:)`, `setStopEnabled(_:)` and `hideProgress()`; `func close()`.
- `CaptureRecord.recordLocalTrim(duration: Double, at editedAt: Date)`.
- `EditorAvailability.refusal(for:record:saveFolder:isDeleting:isTrimming: Bool = false)` and `trimmingRefusal = "This capture is being trimmed."`; every current caller compiles unchanged.
- `CaptureDeletion.trimmingRefusal = "This capture is being trimmed. Delete it when the trim finishes."`
- `EditorUploadPlan.failedReplaceRecordingMessage` (`Upload failed. The link still shows the earlier recording.`) and `static func failedReplaceMessage(for kind: MediaKind) -> String`.
- `AppCoordinator`:
  - `trimWindows: [UUID: TrimWindowController]`, `trimPasses: [UUID: Task<Void, Never>]` and `trimmingIDs: Set<UUID>`;
  - `func trimCapture(recordID:)`, `func uploadTrimmed(recordID:)` and `var hasUploadDestination: Bool` (Gap 9);
  - `func trimMenuState(for record: CaptureRecord) -> RecordingTrim.MenuState`, from the save folder, `hasUploadDestination`, `deletingIDs` and `trimmingIDs`, for the card and the row;
  - private `finishTrimWrite(id:duration:byteCount:)` (Gap 11);
  - `uploadRefusal(for:isTrimming: Bool = false)` and `failedRecordsToRetry(_:deletingIDs:trimmingIDs: Set<UUID> = [])`, changed in place from Task 5's. The defaults keep Task 5's `UploadRefusalTests` and any caller compiling unchanged, as `EditorAvailability.refusal`'s does; every coordinator caller passes the new argument explicitly (the marker's gates below).
- `VideoFixtures.makeMP4` gains `keyframeInterval: Int? = nil`.

**Steps:**
- [ ] Run the trim probe (design, Still to probe). Write `docs/superpowers/research/recording-probes/trim-reencode.swift`, building with the README's `xcrun swiftc` line and `-o` outside the repository. Given a recording and a start time, it prints the video track's sync sample times from `AVSampleCursor`, runs a passthrough and a `HighestQuality` export from that start with each one's time, size and `fractionCompleted` readings, counts the output's video samples before the start in decode order, and counts the audio sample frames before the start a passthrough keeps in the file (the audio track's samples in decode order, which ignores the edit list, against the start). Tim records 60 s at 2560×1664 and at 4096×2304 with the app; the controller asks him to run it and to check text sharpness and `ffmpeg -ignore_editlist`. Write the results into the design's Probes. **Gate:** it trips if `AVSampleCursor` reports no sync samples on those files, the progress does not move, a re-encode is larger than its source (the disk check assumes it is not), or a passthrough from a sync sample keeps more than 2,048 audio sample frames before the start (two AAC packets, the design's bound for Decided 3). Report it; the steps the header's Gates name wait until the design is amended, and the rest of this task goes on.
- [ ] Extend `VideoFixtures` with `keyframeInterval` (`AVVideoMaxKeyFrameIntervalKey`, `AVVideoAllowFrameReorderingKey` false).
- [ ] Write the design's `RecordingTrimTests` and see them fail. Add:
  - `writePlan`: `This capture was deleted.`, `This capture is being deleted.` and `This capture is still uploading.` refuse; Save and Upload with `.unavailable` gives `.newPendingFile`; a record that starts uploading after the window opened is refused;
  - `afterPut`: a pruned record's pending file is removed and a save-folder file kept, and a live record finishes;
  - `showsTrim` and `canTrim`: `.video` only; false while uploading, deleting or trimming, with `.unavailable`, and with neither a Save target nor a destination;
  - `menuState`: `Upload Trimmed` shows only for a stale `.video` with a local file and a destination, and is disabled while uploading, deleting or trimming;
  - `informativeText`: `Keeps 0:12 of 1:04. The rest is cut from the file.`, then the sheet's sentence;
  - `CaptureRecordTests`: `recordLocalTrim` sets the duration and `editedAt`, and leaves the pixel size and `uploadIsStale`;
  - `EditorUploadPlanTests`: `failedReplaceMessage(for:)` for `.image` and `.video`;
  - `UploadRefusalTests`: with `isTrimming`, `uploadRefusal` is `This capture is being trimmed.` and `failedRecordsToRetry` leaves the record out; Task 5's tests run unchanged on the defaults.
  - `RecordingTrimTests`: `export` into a folder that does not exist yet creates it; `exportForSave` with a `directory` that does not exist yet creates it and succeeds, with and without `unmutedIntervals` (the design's missing `tmp/Trim` item).
- [ ] Implement the pure parts, `recordLocalTrim`, and the `EditorAvailability`, `CaptureDeletion` and `EditorUploadPlan` additions.
- [ ] Implement `startsOnSyncSample`, `export` and `exportForSave` (design, Export, Method, Progress, Disk space):
  - `startsOnSyncSample` is true when the cursor at the start shows that time and `sampleIsFullSync`; a track that cannot provide cursors gives false;
  - `export` is an `AVAssetExportSession` with `timeRange`, run with `export(to:as:)`: `AVAssetExportPresetPassthrough` or `AVAssetExportPresetHighestQuality`. Progress comes from `states(updateInterval: 0.1)`, never decreases and is called once at 1; a passthrough reports only 1. It creates `output`'s folder when missing, as `AVAssetExportSession` does not. Cancellation stops the export and removes its partial output;
  - `exportForSave` first creates `directory` when it is missing: `start()` removes `tmp/Trim` at launch, and a pending or save-folder source never downloads, so nothing else has made it. Then it checks for the source's size, twice that with the mute step, plus 1 GB in `directory`, else throws with `Not enough disk space.` before writing; for a marked record it runs `RecordingMute.apply` into `-muted.mp4` first and trims that; it removes `-muted.mp4` before it returns or throws.
- [ ] Implement `TrimWindowController` (design, Window, The sheet, Trimming sheet): one window per record; an `AVPlayerView` with `controlsStyle = .inline` on an `AVPlayer` of the file; `beginTrimming` once the item is `readyToPlay` and `canBeginTrimming`. `.okButton` gives `reversePlaybackEndTime` and `forwardPlaybackEndTime`; the bar's `Cancel` closes. The save sheet is an `NSAlert` sheet whose first button takes Return and whose last, `Cancel`, takes Escape. The `Trimming…` sheet has a determinate `NSProgressIndicator` and `Stop`. The close button is disabled while a sheet is up.
- [ ] Implement `AppCoordinator+Trim.swift` (design, Where, Source file, Write-time checks, Save, Save and Upload, Stale link, Failure, Cleanup):
  - **Open.** `trimCapture` brings an open window forward. Otherwise it reads `RecordingTrim.source`: a pending file directly; a save-folder file under the folder's scope, held while the window is open; or a download to `tmp/Trim/<id>.mp4` through `downloadSource(of:title: "Opening the recording…")` and `download(key:to:)`, in a detached task that creates `tmp/Trim` first. A failed download posts `Not trimmed` / the error.
  - **The range.** `RecordingTrim.range`; one too short posts `Not trimmed` / `The trimmed recording would be too short.` and closes. Then the sheet from the live record, `EditorSaveTarget.plan` and `hasUploadDestination`.
  - **The pass.** `writePlan` on the live record, and for Save and Upload `makeDestination()` (Gap 9); `trimmingIDs.insert`; the method from `startsOnSyncSample` on the source (Gap 9); for `.reencode`, the `Trimming…` sheet; `exportForSave` in a task kept in `trimPasses[id]`, which `Stop` cancels; `writePlan` again right before the put; for a record with a link, `uploadIsStale` set; then the put, `afterPut` and `finishTrimWrite`.
  - **The put.** `.saveTarget` puts `-trimmed.mp4` with `FileReplacement.put(at:) { try FileManager.default.moveItem(at: trimmed, to: $0) }` in a detached task, under the save folder's scope for a save-folder file and none for `pending/<id>.mp4`. `.newPendingFile` moves it to `pending/<id>.mp4` with `pendingFiles.moveIn` and points the record there with `fileIsTemporary` true. The size is read before the move (Gap 11). `Stop` is disabled from the put on. A failed put clears the `uploadIsStale` this pass set, leaves the record and its file, and posts `Not trimmed` / the error, `Disk Full` for a full disk.
  - **`finishTrimWrite(id:duration:byteCount:)`.** `recordLocalTrim` and `byteCount` in one update; the thumbnail from `PosterFrame.image(of:)` of the new file through `replaceThumbnail`; `unmutedIntervals` emptied; the drag copy dropped with `removeDragFolder(id)` and `overlay.setDragFile(nil, for: id)`; the card refreshed.
  - **Save and Upload**, after the write: `videoClipboardCounts[id]` set to the current change count; `EditorUploadPlan.plan(… asNew: false)` against the lane's location; `startingUpload`; `trimmingIDs` cleared right before `startUpload(… fixedKey:)` with `uploadPayload(for:)`, in the same main-actor turn, so `startUpload`'s trimming check passes and nothing can start in between.
  - **`uploadTrimmed`** runs the same upload half, refused with `uploadRefusal`, `EditorAvailability.refusal(for: .upload, …)`, no local file or no destination.
  - **Every exit** clears `trimmingIDs` and closes the window. Closing it, for any reason, removes `tmp/Trim/<id>*`, after the pass when one runs, and releases the folder's scope.
- [ ] Add the marker's gates (design, Write-time checks): `uploadRefusal(for:isTrimming:)` and `failedRecordsToRetry(… trimmingIDs:)` read `trimmingIDs` in `retryUpload`, `retry`, `retryFailedUploads` and `startUpload`, each passing it explicitly. `retryUpload` refuses before `makeDestination()`, so a refused record is never marked failed, and `retry` checks again; whichever refuses posts `Not uploaded` with the text, once. `startUpload` keeps Task 5's silent backstop; `deleteCapture` refuses before its alert with `Not deleted` / `CaptureDeletion.trimmingRefusal`; `removeRecord` and `removeFiles(ofPruned:)` close the record's Trim window, which cancels a pass before its put.
- [ ] Change `handle(_:at:)`: `.failed` posts `failedReplaceMessage(for: record.mediaKind)`, and `.uploaded` posts the once-per-launch cache note on the first same-key replace in either clipboard branch.
- [ ] `start()` removes `tmp/Trim` beside the `tmp/Clop` sweep.
- [ ] Run the full suite.
- [ ] Commit: `feat: Trim`.

Trim's hand checks run in Task 8, once the card and the row reach it.

### Task 8: Cards, rows and menus

**Files:**
- Modify:
  - `TidyShot/Overlay/QuickAccessView.swift`: `menuItems` (:88-110), `buttonRow` (:111-126), `thumbnail` (:127-157), `statusContent` (:191-258) and `VideoBadge` (:259);
  - `TidyShot/Overlay/QuickAccessModel.swift`, and `QuickAccessController.swift`: `Actions` (:31-56) and `makeCard` (:188-218);
  - `TidyShot/RecentCaptures/RecentCaptureFormatting.swift`, `RecentCaptureRow.swift`, `RecentCaptureMenuItemView.swift` (:19-34) and `RecentCapturesMenu.swift`: `rebuild` (:40-65) and `makeActions` (:108-119);
  - `TidyShot/App/AppCoordinator+Overlay.swift`: `overlayActions` (:25-40) and `pushCardFlags` (:101-104);
  - `TidyShot/App/AppCoordinator+Trim.swift`: refresh the card wherever `trimmingIDs` changes.
- Tests: add to `RecentCaptureFormattingTests` and `QuickAccessModelTests`.

**Consumes:** Tasks 1, 5 and 7.

**Produces:**
- `QuickAccessStatus` gains `.linkNotUpdated(URL)` and `.soundNotMuted`.
- `QuickAccessModel`: `var trimState: RecordingTrim.MenuState` (default all false); `onTrim` and `onUploadTrimmed`; `canCopyFile` and `canSaveAs` false for a marked record.
- `QuickAccessController`: `Actions.trim` and `Actions.uploadTrimmed`; `setTrimState(_:for:)`.
- `RecentCaptureActions` gains `trim`, `uploadTrimmed` and `open`; `RecentCaptureMenuItemView` and `RecentCaptureRow` take a `RecordingTrim.MenuState`.
- `RecentCaptureFormatting`:
  - `enum RecordingBadge { case play, gif }` and `badge(for:) -> RecordingBadge?`, nil for an image;
  - the detail's state part gains `Link not updated` (an uploaded `.video` with `uploadIsStale`) and `Sound not muted` (a marked record), in `detail` and `detailWithoutSize`;
  - `canCopyFile` false for a marked record, and `rowClickOpens(_:)` true for one (Gap 10).

**Steps:**
- [ ] Write the design's `RecentCaptureFormattingTests` and `QuickAccessModelTests` items and see them fail. Add: a GIF's badge is `.gif` and a video's `.play`; `Link not updated` and `Sound not muted` come before the size gives way (`detailWithoutSize` keeps them); Retry, `Upload Trimmed` and Delete are disabled while trimming.
- [ ] Implement the formatting and the model's flags.
- [ ] Change the card (design, Kind, Stale link, Privacy rule):
  - the poster with a `GIF` badge and the duration for a GIF;
  - `Trim…` in the menu when `trimState.showsTrim`, enabled by `canTrim`; `Upload Trimmed` when `showsUploadTrimmed`, enabled by `canUploadTrimmed`;
  - `Link not updated` on the status line; `Sound not muted` for a marked record, which offers the thumbnail's Open, `Trim…` and Delete only, with no Copy File, Save As… or drag-out;
  - Retry, `Upload Trimmed` and Delete disabled while trimming, as while uploading.
- [ ] Change the row (Gap 10): the `GIF` badge; `scissors` for `Trim…` and `arrow.up.circle` for `Upload Trimmed`, with their enabled states; the detail; a marked record's click opens the file through `openCapture`.
- [ ] Wire the coordinator: `overlayActions` gains `trim` and `uploadTrimmed`, each after menu tracking; `pushCardFlags` pushes `trimMenuState(for:)`, so every change to `trimmingIDs` or `deletingIDs` that refreshes the card updates it; `RecentCapturesMenu.rebuild` asks `trimMenuState(for:)` per row, as it reads `optimizingVideoIDs`, and its `open` action calls `openCapture` after the menus close.
- [ ] Run the full suite.
- [ ] Hand check in the Debug build (design, the GIF list's last item and the Trim list):
  - a GIF's card, row and menus show no Annotate, Pin or Copy Image; a thumbnail click opens it and it plays; Save As… writes a `.gif`; a card press downloads nothing; the hover preview shows the stored thumbnail; a finished upload's URL does not replace a clipboard the user changed;
  - every Trim item in the design: Save, Save and Upload, an upload-only record that needs the download, both Cancels, a start between keyframes with `Trimming…` and `Stop`, an end-only trim, the sheet's text and buttons for each row of the table, `Link not updated` and `Upload Trimmed`, a save folder on another volume in the sandboxed build after a relaunch, Retry and Delete during an open window and during a slow put, closing an upload-only record's window, drag-out after Save and Upload, and a `Sound not muted` record trimmed to clear its mark. If the sandbox refuses the other volume's replacement folder, stage the file in the save folder itself under its scope and `replaceItemAt` from there, as the design says, and note it for Task 9.
- [ ] Commit: `feat: GIF, Trim and the sound mark in cards and Recent Captures`.

### Task 9: Checklist, README and design close-out

**Files:**
- Create `docs/testing/recording-r2-manual-checklist.md`.
- Modify:
  - `README.md`: the Screen recording section (Format and GIF, the microphone and mute, Trim), "Optimise with Clop" (GIFs are not sent to Clop), and Documents lines for the R2 design and the checklist;
  - the R2 design: Built notes, and the probe results Tasks 3, 4, 6 and 7 could not record;
  - `docs/superpowers/specs/2026-10-19-tidyshot-screenshot-design.md`: 2.13's "a Trim when R2 adds it" as built, and section 5's file map with `AppCoordinator+Trim.swift`;
  - `docs/superpowers/specs/2026-10-23-coordinator-split-design.md`, section 6: the summary's GIF clause ("ImageIO, then Clop") becomes TidyShot's own encoder with no Clop; the GIF bullet's "`optimisedForUpload` picks Clop's path" becomes "a GIF never goes to Clop (`isSentToClop`)"; the Trim bullet adds the marker's gates in `+Upload`, Delete's refusal in `+Delete`, and `downloadSource` (`+RecordActions`) beside `replaceThumbnail` as the two members widened; a mute bullet is added for the ladder and recovery in `+Recording` and the `Sound not muted` gates in `+Upload`, `+RecordActions` and `+DragOut`; each change marked as R2's.

**Steps:**
- [ ] Grep the finished code for every string the design gives, and fix any drift.
- [ ] Run the coordinator split's surface check (its plan's Task 7 command) with `replaceThumbnail` and `downloadSource` added to the widened list; it prints nothing. Code outside `TidyShot/App/AppCoordinator*.swift` uses only the surface the split lists and the new entry points under Global Constraints.
- [ ] Write the checklist in the form of `recording-r1-manual-checklist.md`: setup, a Release build, the grants Tim gives, and the defaults to delete (`recordingFormat`, `gifFrameRate`, `gifMaxSide`, `recordingMicrophone`, `recordingMicrophoneName`). It covers every hand check in the design (GIF, Settings, Microphone, Trim), the encoder, trim and latency probes left open, and every gap above, to confirm or overrule. Each probe step gives its command, a blank for the result and the log line: `/usr/bin/log show --last 10m --style compact --predicate 'process == "TidyShot"' | grep "Recording:"`.
- [ ] Write the README text and the Built notes: what was built differently, the twelve gaps, the two widened members, the `outputProvider` choice, and the Still to probe items still open, which the PR lists.
- [ ] Run the full suite and the Release build once. `codesign -d --entitlements - .build-rel/Build/Products/Release/TidyShot.app` lists exactly R1's entitlements plus `com.apple.security.device.audio-input`.
- [ ] Commit: `docs: recording R2 checklist, README and design close-out`.

## Test totals

| After | Total |
|---|---|
| Baseline | the baseline small-tweaks leaves, about 1290 tests |
| Task 1 | baseline plus `RecordingSettingsLayoutTests` (1 new suite) and the `CaptureRecordTests`, `AppSettingsTests`, `RecordingClockTests`, `RecordingLimitsTests`, `EditorInputTests`, `EditorNamingTests`, `UploadPayloadTests`, `ThumbnailProviderTests` and `DragFileNameTests` additions |
| Task 2 | Task 1 plus `GIFPaletteBuilderTests`, `GIFFrameDifferTests`, `GIFLZWWriterTests`, `GIFEncoderTests` and `GIFFileSinkTests` (5 new suites) |
| Task 3 | Task 2 plus `GIFMakerTests`, `GIFConversionTests`, `GIFProgressMenuTests`, `RecordingNoticeOrderTests` and `RecordingPanelLayoutTests` (5 new suites) and the `RecordingConfigurationTests`, `RecordingControllerTests` and `RecordingRecoveryTests` additions |
| Task 4 | Task 3 plus `MicrophoneChoiceTests` (1 new suite) and the `RecordingConfigurationTests` and `RecordingControllerTests` additions |
| Task 5 | Task 4 plus `RecordingMuteTests` and `UploadRefusalTests` (2 new suites) and the `RecordingSavePlanTests` and `RecordingRecoveryTests` additions |
| Task 6 | Task 5 plus `MicrophoneLatencyTests` and `MuteLogWriterTests` (2 new suites) and the `RecordingControllerTests`, `RecordingPanelLayoutTests` and `RecordingConfigurationTests` additions |
| Task 7 | Task 6 plus `RecordingTrimTests` (1 new suite) and the `CaptureRecordTests`, `EditorUploadPlanTests` and `UploadRefusalTests` additions |
| Task 8 | Task 7 plus the `RecentCaptureFormattingTests` and `QuickAccessModelTests` additions |
| Task 9 | unchanged: the baseline's suites plus 17 |
