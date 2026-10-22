# TidyShot Screen Recording R1, Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Record Screen (⌃⇧8) records an area or a window, and Record Fullscreen records the display under the pointer, to an H.264 `.mp4` with optional system audio. A recording is saved, uploaded, optimised with Clop and listed like a screenshot, and it survives a quit, a log out and a crash.

**Architecture:** `docs/superpowers/specs/2026-10-21-tidyshot-screen-recording-design.md` is the full specification: behaviour, types, strings, constants, settings keys and tests. When this plan and the design disagree, the design wins; stop and ask if it is unclear.
- **Pure decisions.** `RecordingConfiguration`, `RecordingClock`, `RecordingLimits`, `RecordingEnd` and `RecordingSavePlan` decide everything that can be decided without a screen, and are tested that way.
- **The session.** `RecordingController` runs one recording through a `RecordingStreamDriver` (`SCStream` with `SCRecordingOutput` in the app, a fake in tests) and a `RecordingChrome` (the panel and the dashed frame). It owns the stop wait, the timer, the disk check, window loss, sleep and the keep-awake activity, and ends with a `RecordingOutcome`.
- **Saving.** `AppCoordinator.saveRecording` sits beside `save(_:intent:)` and shares `persist`'s tail. A recording is moved, never loaded: the upload streams it from disk with a streamed SigV4 hash, and Clop gets its own queue.
- **Probes.** `docs/superpowers/research/recording-probes/` holds working code. `record-area.swift` and `record-stop-order.swift` are the recording and stop-order references; start from them. `image-assumptions.md` maps every place the app assumes an image, with file:line.

**Tech Stack:** Swift 6 language mode with default `MainActor` isolation and `NonisolatedNonsendingByDefault`, ScreenCaptureKit (`SCStream`, `SCRecordingOutput`, `SCContentFilter`), AVFoundation (`AVURLAsset`, `AVAssetImageGenerator`, and `AVAssetWriter` in tests), CryptoKit (incremental `SHA256`), URLSession (`upload(for:fromFile:)`, `download(for:)`), AppKit (`NSPanel`, `NSAlert`, `NSWorkspace` notifications, `ProcessInfo.beginActivity`), SwiftUI Settings, KeyboardShortcuts, Swift Testing, XcodeGen 2.46.

Work happens on the branch `recording-r1`, cut from `phase-7c-background` at e9ae0cf. The design was first committed at 01588a5; the settled R1 text is committed with this plan.

## Global Constraints

- **Earlier constraints still apply.**
  - Minimum macOS 26.0, Swift 6 with MainActor by default, App Sandbox, credentials only in the Keychain.
  - One save, upload and delete path in `AppCoordinator`: `saveRecording` shares `persist`'s tail, and every video upload, retry and delete goes through the existing paths.
  - KeyboardShortcuts is the only Swift package. No GPL code is read or copied.
- **No new entitlement and no new package.** System audio needs none; the microphone is R2.
- **Off the main actor.** Use `@concurrent` for async work off the main actor, and detached tasks for synchronous file work, as the codebase does. Off the main actor: hashing (`@concurrent`, so never on the `UploadQueue` actor), poster frames, asset checks, Clop and its work copy, the move into the save folder or `pending/`, Save As… copies and downloads, and a video's drag stage. The controller, the panel, the chrome and the settings are MainActor; `SCStreamDelegate` and `SCRecordingOutputDelegate` callbacks hop to the main actor.
- **A capture is never lost.**
  - Nothing reads, validates, takes a poster from, moves, copies, uploads or deletes the recording before the stop wait ends.
  - Only the end rule (`RecordingEnd.decide`) or a discarding Cancel removes a recording. The `tmp/Recording` file stays until a record points at its new place.
  - Every failure to reach the save folder falls back to `pending/`. Clop and the upload never touch the original.
- **Nothing loads a video into memory:** not the upload, a retry, Copy URL, Reveal, drag-out, Save As…, a restore or the thumbnail.
- **Exact strings, defaults, limits, menu titles, shortcut defaults and settings keys** come from the design.
- **Tests** use Swift Testing, run with:
  ```bash
  xcodegen generate && xcodebuild test -project TidyShot.xcodeproj -scheme TidyShot -destination 'platform=macOS' -derivedDataPath .build 2>&1 | grep -E "Test run with|error:|TEST"
  ```
  The baseline is `Test run with 961 tests in 111 suites passed`. The Release build is `xcodebuild -project TidyShot.xcodeproj -scheme TidyShot -configuration Release -derivedDataPath .build-rel build`.
- **Hand checks** need Screen Recording granted to the build. Builds are signed ad hoc (`Config/Local.xcconfig`), so every rebuild needs a new grant, and only Tim grants it. Never open or change privacy settings. When a hand check cannot run, say so in the report.
- **Commits.** Commit after every task with a conventional message and no attribution lines, and never push.

## Gaps this plan fills

The design leaves these open. Each is this plan's call. Task 9 records them in the design's Built notes, and the PR flags them.
1. **Free space.**
   - `tmp/Recording` is created (`Recording.makeDirectory()`) just before the 2 GB start check, and `freeBytes(at:)` reads the nearest folder that exists, so a fresh container is checked too. A folder that cannot be created fails the start with `Recording failed` and the error's description.
   - An unreadable free-space value counts as enough, with a log line.
   - The 2 GB start check runs before the selection overlay, so a full disk refuses before the user selects.
2. **Extra parameters.**
   - `saveRecording(_:intent:stopNotice:mode:)` carries the stop reason and quit mode beside `intent`.
   - `optimisedVideo(at:duration:scope:)` takes the save folder's scope, which the work copy needs.
3. **Counter.** For a `.file` upload, `{counter}` is drawn after the 5 GiB check, just before the enqueue, so a refused upload draws no key.
4. **Fallbacks.**
   - `.upload` with no destination falls back exactly as `.save`: `.none`, with the forced file reference.
   - A `.save` fallback keeps the table's clipboard rule, so the reference points at the pending file.
   - Over the 5 GiB limit, where the file is decides, not the action: a pending file moves into the save folder and a save-folder file stays. A `.upload` fallback therefore moves as `.uploadOnly` does.
5. **Quit mode** skips only what the design lists: the folder prompt, Clop, the upload, the card, the notifications and the not-configured warning. The clipboard rule and the shutter still apply.
6. **Strings the design does not give.**
   - When even the rename fails, `Not saved to a folder` reads `<reason> The recording is still at <path>.`
   - `Recovered a recording` reads `<file name>, <m:ss>. Find it in Recent Captures.` and shows no card. The record's timestamp is the file's creation date. The id is the file name's UUID when it parses and is not in history, otherwise a new one.
7. **Copy File's drag copy outlives the upload and the card.**
   - On `.uploaded`, a video whose drag folder already holds a staged copy keeps that copy and removes the pending file, instead of adopting it. `adopt` would delete the copy a Copy File reference points at.
   - `scheduleDragCleanup` skips a record while the clipboard still holds its Copy File reference. The change count matches, so the launch sweep removes it later.
8. **Panel geometry.** The panel is a 172 × 44 pt bar. `bottomCentre` sits `ScrollPanelGeometry.gap` above the bottom of the visible frame.
9. **Start races.**
   - The quit hold's count-in phase covers the whole hand-off, with the count-in on or off: from the selection's return to `recorder.run`.
   - A quit during the hand-off, before `recorder.run`, records nothing.
   - A window or display that goes between hand-off step 5 and the driver's own content read fails the start: `Recording failed` / `The window is no longer on screen.` or `The display is no longer connected.`

### Task 1: Sandbox spike and recording foundations

**Files:**
- Create in `TidyShot/Recording/`:
  - `RecordingSpike.swift`, all of it inside `#if DEBUG`;
  - `RecordingConfiguration.swift`, `RecordingClock.swift`, `RecordingLimits.swift`, `RecordingEnd.swift`, `RecordingSavePlan.swift`, `Recording.swift`, `VideoValidation.swift`.
- Modify:
  - `TidyShot/History/CaptureRecord.swift`: `init` (:52-72), `CodingKeys` (:74-78) and `init(from:)` (:84-101);
  - `TidyShot/App/AppDelegate.swift`: `applicationDidFinishLaunching` (:40-44), the DEBUG trigger;
  - the design's Probes section, with the spike's result;
  - `docs/superpowers/research/recording-probes/record-window.swift`, `record-stop-order.swift` and the folder's `README.md`, for Task 9's window-change and sleep hand checks.
- Create tests:
  - `TidyShotTests/Support/VideoFixtures.swift`;
  - `TidyShotTests/RecordingConfigurationTests.swift`, `RecordingClockTests.swift`, `RecordingEndTests.swift`, `RecordingLimitsTests.swift`, `RecordingSavePlanTests.swift`, `VideoValidationTests.swift`;
  - additions to `CaptureRecordTests`.

**Produces** (all `nonisolated`, `Sendable`):
- `enum MediaKind: String, Codable { case image, video }`.
  - It has `fileExtension` (`png`, `mp4`), `contentType` (`image/png`, `video/mp4`) and `utType` (`.png`, `.mpeg4Movie`).
  - Its `init(from:)` reads an unknown raw value as `.video`.
- `CaptureRecord.mediaKind: MediaKind` (default `.image`, `decodeIfPresent`), `durationSeconds: Double?` and `var isVideo: Bool`.
- `RecordingConfiguration.swift`:
  - `struct RecordingDisplay: Equatable { var id: CGDirectDisplayID; var frame: CGRect; var scale: CGFloat }`. The frame is in CoreGraphics global points.
  - `enum RecordingSource: Equatable { case area(CGRect, on: RecordingDisplay); case display(RecordingDisplay); case window(id: CGWindowID, frame: CGRect, scale: CGFloat) }`.
  - `enum RecordingFilterPlan: Equatable { case area(displayID: CGDirectDisplayID, sourceRect: CGRect); case display(displayID: CGDirectDisplayID); case window(windowID: CGWindowID) }`. `sourceRect` is display-local points.
  - `struct RecordingOptions: Equatable { var framesPerSecond: Int; var retina: Bool; var systemAudio: Bool; var showsCursor: Bool }`.
  - `struct RecordingConfiguration: Equatable`:
    - `filter: RecordingFilterPlan`, `pixelWidth`, `pixelHeight` and `framesPerSecond`;
    - `showsCursor`, `capturesAudio`, `excludesCurrentProcessAudio` (always true), `ignoresShadowsSingleWindow`, `scalesToFit` and `preservesAspectRatio`;
    - `static let maximumSide = 4096` and `static let minimumAreaSide: CGFloat = 32`;
    - `static func make(_ source: RecordingSource, options: RecordingOptions) -> RecordingConfiguration`;
    - `static func outputSize(points: CGSize, scale: CGFloat) -> (width: Int, height: Int)`, which applies the cap and the even rounding;
    - `static func isLargeEnough(_ rect: CGRect) -> Bool`.
- `enum RecordingClock { static let softLimit: TimeInterval = 300; static func format(_ seconds: TimeInterval) -> String; static func isPastSoftLimit(_ seconds: TimeInterval) -> Bool }`.
- `enum RecordingLimits`:
  - `startFreeBytes` (2 GB) and `runningFreeBytes` (1 GB), both `Int64`;
  - `diskCheckInterval: Duration = .seconds(5)`, `cancelConfirmationSeconds: TimeInterval = 5`, `minimumDuration: TimeInterval = 0.5`, `stopTimeout: Duration = .seconds(15)`;
  - `singleUploadBytes: Int64 = 5_368_709_120` and `diskFullText = "Your disk is almost full."`;
  - `static func refusesStart(freeBytes: Int64?) -> Bool`, `stopsRecording(freeBytes: Int64?) -> Bool`, `asksBeforeDiscarding(elapsed: TimeInterval) -> Bool` and `fitsSingleUpload(byteCount: Int64) -> Bool`;
  - `static func freeBytes(at url: URL) -> Int64?`, read from `volumeAvailableCapacityForImportantUsageKey` of `url`, or of its nearest existing ancestor when `url` does not exist yet. It is nil only when that read fails (Gap 1).
- `RecordingEnd.swift`:
  - `struct RecordingNotice: Equatable { var title: String; var body: String }`.
  - `enum RecordingEndKind: Equatable { case stop, discardingCancel, diskFull, sleep, userSwitch, windowClosed, failed(String) }`. Each has its `Recording stopped` reason from the design.
  - `enum RecordingEndDecision: Equatable { case keep(notice: RecordingNotice?); case remove(notice: RecordingNotice?) }`.
  - `enum RecordingEnd`:
    - `stoppedTitle`, `failedTitle`, `refusalTitle` (`Screen recording`), `tooShortText`, `discardQuestion` and `static func discardDetail(elapsed:) -> String`;
    - `static func decide(_ kind: RecordingEndKind, facts: VideoFacts, waitTimedOut: Bool) -> RecordingEndDecision`;
    - `static func startFailure(_ description: String) -> RecordingNotice`.
- `RecordingSavePlan.swift`:
  - `enum RecordingFileTarget: Equatable { case saveFolder, pending }`.
  - `enum RecordingFileResult: Equatable { case saveFolder; case pending; case fallback(reason: String); case leftInTmp(reason: String, path: String) }`.
  - `enum RecordingSaveNotification: Equatable { case none; case saved; case notice(RecordingNotice) }`.
  - `struct RecordingSavePlan: Equatable`:
    - `makesRecord`, `fileIsTemporary`, `uploadState: CaptureRecord.UploadState`, `uploads`, `copiesFileReference`, `setsLastCaptureURL`, `showsCard`, `notification` and `notConfiguredWarning: String?`;
    - `static func target(for action: AfterCaptureAction) -> RecordingFileTarget`;
    - `static func make(action: AfterCaptureAction, hasDestination: Bool, result: RecordingFileResult, copyImage: Bool, alsoCopyImage: Bool, quitMode: Bool) -> RecordingSavePlan`;
    - `static func replacesClipboard(savedChangeCount: Int?, currentChangeCount: Int) -> Bool`;
    - `static let noFolderReason = "No folder was chosen."`, `static let oversizedNotice: RecordingNotice` (`Not uploaded`) and `static func notSavedToFolder(reason: String, uploads: Bool) -> RecordingNotice`.
  - The size refusal (Size in the design, Gap 4):
    - `struct RecordingOversizePlan: Equatable { var fileIsTemporary: Bool; var uploadState: CaptureRecord.UploadState; var notices: [RecordingNotice] }`;
    - `static func oversizedMoves(fileIsTemporary: Bool) -> Bool`: a pending file moves into the save folder, and a save-folder file stays;
    - `static func oversized(fileIsTemporary: Bool, move: RecordingFileResult?) -> RecordingOversizePlan`. `move` is nil when nothing moves, `.saveFolder` after the move, and `.fallback(reason:)` when no folder was chosen or the move failed, the file staying in `pending/`. The state is always `.none`. The notices are `oversizedNotice`, then, after a fallback, `notSavedToFolder(reason:uploads: false)`.
- `struct Recording`:
  - `id: UUID`, `fileURL: URL`, `startedAt: Date`, `pixelWidth`, `pixelHeight`, `duration: TimeInterval`, `poster: CGImage?` and `displayID: CGDirectDisplayID`;
  - `static var directory: URL`, the container's `tmp/Recording`, which reading it does not create;
  - `static func makeDirectory() throws`, which creates it with its parents; an existing folder is fine. The spike and Task 6's start call it before anything writes there or reads its free space;
  - `static func fileURL(for id: UUID) -> URL`.
- `VideoValidation.swift`:
  - `struct VideoFacts: Equatable { var isPlayable: Bool; var duration: TimeInterval; var naturalSize: CGSize?; var videoTracks: Int; var audioTracks: Int; var byteCount: Int64; var meetsMinimum: Bool }`. `meetsMinimum` means playable, at least one video track and at least 0.5 s.
  - `enum VideoValidation { @concurrent static func inspect(_ url: URL) async -> VideoFacts }`. A missing or unreadable file gives a not-playable value with zero tracks.
- DEBUG only: `enum RecordingSpike { static func run() async }`, run when the app launches with `-RecordingSpike YES`.
- Tests: `enum VideoFixtures { static func makeMP4(at: URL, width: Int, height: Int, seconds: Double, audio: Bool) async throws; static func makeGarbage(at: URL) throws }`. The movie is H.264 at 10 fps from `AVAssetWriter`, with a silent AAC track when `audio` is true.

**Steps:**
- [ ] Write `VideoFixtures` and `VideoValidationTests`, and see them fail:
  - a 2 s 320×200 file with audio reads playable, 2 s ± 0.1, 320×200, with one video track and one audio track;
  - the same without audio has no audio track;
  - a garbage file and a missing file read as not playable, with no tracks;
  - a 0.3 s file is playable but does not meet the minimum.
- [ ] Implement `VideoValidation`.
- [ ] Write the spike from `record-area.swift` and `record-stop-order.swift`:
  - an 800×500 pt area centred on the main display, at Retina size and 30 fps, with `capturesAudio` and `excludesCurrentProcessAudio` on;
  - `Recording.makeDirectory()`, then `SCRecordingOutput` writing `.mp4` with `.h264` to `Recording.fileURL(for: UUID())`;
  - a stop after 3 s, with the waiter armed before `stopCapture()`;
  - then `VideoValidation.inspect`, logged as one line, `Recording spike: <path>, <w>×<h>, vide×<n> soun×<m>, <s> s, <bytes> bytes` (or the error), and posted as a notification;
  - finally the file moves to `tmp/RecordingSpike/`, created first, so Task 7's launch check never adopts it.

  The trigger goes in `applicationDidFinishLaunching` under `#if DEBUG`: `UserDefaults.standard.bool(forKey: "RecordingSpike")`.
- [ ] Build Debug and run the spike: `open .build/Build/Products/Debug/TidyShot.app --args -RecordingSpike YES`.
  - Play a sound meanwhile: `for i in 1 2 3; do afplay /System/Library/Sounds/Submarine.aiff; done`.
  - Read the result with `/usr/bin/log show --last 2m --style compact --predicate 'process == "TidyShot"' | grep "Recording spike"`.
  - Expected on a 2x display: 1600×1000, `vide` and `soun`, about 3 s.
  - Without Screen Recording for this build, report that and go on with the next steps. The controller asks Tim to grant it and run the command.
- [ ] Write the result into the design's Probes section: the Sandbox bullet moves out of Still to probe.
  - **Gate.** If the spike differs from the unsandboxed probes (no file, an error, no `soun` track, or another natural size), finish this task and report. Task 4 waits until the design is amended.
  - The window-change and sleep probes stay hand checks, in Task 9's checklist.
- [ ] Extend two probes for those hand checks. Neither runs here, but each must compile with the README's `xcrun swiftc` line, its `-o` pointing outside the repository.
  - `record-window.swift`:
    - its arguments become `<output> [seconds] [audio] [window <id>]`: the length (default 10 s), `capturesAudio` with `excludesCurrentProcessAudio`, and another app's window by id instead of its own;
    - its own window gets `.resizable`, `.miniaturizable` and `.closable`;
    - the delegate is also the stream's `SCStreamDelegate`, and prints every callback of both protocols with a timestamp and `recordedDuration`;
    - once a second it prints `recordedDuration`, and whether `CGWindowListCopyWindowInfo(.optionIncludingWindow, id)` lists the window, with its `kCGWindowIsOnscreen`;
    - after the stop and the finish callback, it prints the file's duration, tracks and natural size, as `record-stop-order.swift`'s `describe` does.
  - `record-stop-order.swift` gets a mode `watch [seconds]` (default 180):
    - the `area` mode's rect, with audio;
    - an `SCStreamOutput` for `.screen` that prints each change of `SCFrameStatus`, read from the sample buffer's `SCStreamFrameInfo.status`, with a timestamp;
    - every callback printed as above, `streamDidBecomeActive` and `streamDidBecomeInactive` included;
    - at the end, or after a stream error, it stops if still running, waits for the finish callback and prints `describe`.
  - The README describes both.
- [ ] Write `RecordingConfigurationTests`, `RecordingClockTests`, `RecordingEndTests`, `RecordingLimitsTests`, `RecordingSavePlanTests` and the `CaptureRecordTests` additions listed under Tests (R1) in the design. Add:
  - `RecordingConfigurationTests`: an area larger than its display is clamped to it.
  - `RecordingEndTests`:
    - every kind's reason text;
    - an unplayable file after the disk check gives `Recording failed` / `Your disk is almost full.`;
    - `startFailure` gives `Recording failed` with the description.
  - `RecordingLimitsTests`: a nil free-space value neither refuses nor stops; exactly 2 GB starts; exactly 5,368,709,120 bytes fits; `freeBytes(at:)` of a missing folder inside a temporary directory is not nil.
  - `RecordingSavePlanTests`:
    - the warnings' exact strings;
    - Gaps 4 and 5 (the fallbacks);
    - `.fallback(reason: noFolderReason)` for `.save` and `.upload` gives `Not saved to a folder` with the body starting `No folder was chosen.`;
    - over the limit: a `.upload` save-folder file stays, with `.none` and only `Not uploaded`; a moved `.uploadOnly` file gets `fileIsTemporary` false and `.none`; a `.uploadOnly` file with no folder chosen, or a failed move, stays temporary with `.none` and both notices; a `.upload` fallback moves as `.uploadOnly` does;
    - `leftInTmp` makes no record and gives the Gap 6 text;
    - quit mode for each action, with and without a destination.
  - `CaptureRecordTests`: `MediaKind`'s extension, content type and UTType.
- [ ] See them fail to compile.
- [ ] Implement the files exactly as the design gives the cap, the even rounding, the `sourceRect` shrink, the end rule, the save table, No destination, Where the file lands, Clipboard after the upload, the size refusal and quit mode.
- [ ] Run the full suite.
- [ ] Build Release and check that the spike is not in it: `strings .build-rel/Build/Products/Release/TidyShot.app/Contents/MacOS/TidyShot | grep -c "Recording spike"` prints 0.
- [ ] Commit: `feat: recording foundations and sandbox spike`.

### Task 2: Uploading from a file

**Files:**
- Create `TidyShot/Upload/UploadPayload.swift`.
- Modify:
  - `TidyShot/Upload/Destination.swift`: the protocol (:5-21), `UploadJob` (:30-74) and `UploadError.isRetryable` (:99-106, :121-125);
  - `TidyShot/Upload/UploadQueue.swift`: `init` (:47-58) and `process` (:103-147);
  - `TidyShot/Upload/RetryPolicy.swift`;
  - `TidyShot/Upload/S3Destination.swift`: `upload` (:56-74), `download` (:87-95), and `signedRequest` (:103-127);
  - `TidyShot/Upload/S3Signer.swift`, beside `sha256Hex(_:)` (:180);
  - `TidyShot/App/AppCoordinator.swift`: `startUpload` (:1015-1069), `retry` (:1120-1142), `readLocalFile` (:1146-1149), and the `startUpload` calls at :787, :1138, :1140, :2268 and :2270.
- Tests:
  - create `TidyShotTests/UploadPayloadTests.swift`;
  - add to `UploadQueueTests`, whose `FakeDestination` gains the two new methods and a scope fake that counts starts and stops;
  - add to `S3SignerTests`, `S3DestinationTests` and `RetryPolicyTests`.

**Consumes:** Task 1's `MediaKind` and `CaptureRecord.mediaKind`.

**Produces:**
- `UploadPayload`:
  - `enum UploadPayload: Sendable, Equatable { case data(Data), file(URL, scope: URL?) }`;
  - `static func scope(for fileURL: URL, isTemporary: Bool, saveFolder: URL?) -> URL?`, the `prepareDragFile` rule;
  - `static func video(for record: CaptureRecord, saveFolder: URL?, fileExists: (URL, URL?) -> Bool) throws -> UploadPayload`. It throws `UploadError.fileUnreadable`.
- `UploadJob`:
  - `let payload: UploadPayload`;
  - `init(id:payload:contentType:fileExtension:naming:)` and `init(id:payload:contentType:fileExtension:fixedKey:cacheControl:)`;
  - the two `data:` inits stay as conveniences that make a `.data` payload, so the existing call sites compile.
- `Destination`:
  - `func upload(fileAt url: URL, key: String, contentType: String, cacheControl: String?, progress: @escaping @Sendable (Double) -> Void) async throws`;
  - `func download(key: String, to destination: URL) async throws`.
- `RetryPolicy.file`: `RetryPolicy(maxAttempts: 6, baseDelay: .seconds(2), maxDelay: .seconds(30))`.
- `UploadQueue`:
  - `struct SecurityScope: Sendable { var start: @Sendable (URL) -> Bool; var stop: @Sendable (URL) -> Void; static let live }`;
  - `UploadQueue.init(destination:keyNamer:policy:filePolicy:scope:sleep:events:)`, with `filePolicy` defaulting to `.file` and `scope` to `.live`;
  - `struct ProgressThrottle { static let interval: Duration = .milliseconds(100); mutating func admits(_ fraction: Double, at instant: ContinuousClock.Instant) -> Bool }`. It admits the first fraction, then one per interval, and always a fraction of 1.
- `S3Signer`:
  - `static let fileHashChunkSize = 4 * 1024 * 1024`;
  - `@concurrent static func sha256Hex(fileAt url: URL) async throws -> String`.
- `S3Destination.signedRequest(method:key:payloadHash:extraHeaders:) throws -> URLRequest`. The existing `body:` variant calls it.
- `AppCoordinator`:
  - `startUpload(recordID:payload:destination:fixedKey:)`;
  - `func uploadPayload(for record: CaptureRecord) throws -> UploadPayload`, which replaces `readLocalFile(of:)`.

**Steps:**
- [ ] Write the tests and see them fail:
  - Every `UploadPayloadTests`, `UploadQueueTests`, `S3SignerTests` and `S3DestinationTests` item under Tests (R1). In `UploadPayloadTests`:
    - a save-folder file's scope is the folder;
    - `pending/`, `tmp/Recording` and `tmp/Clop` files have none;
    - a missing file throws, and so does a save-folder video outside the current folder or with no folder.
  - `ProgressThrottle`: 0.1, 0.2 and 0.3 within 100 ms admit only 0.1; 1.0 always passes; a fraction 100 ms later passes.
  - The upload error and retry rules:
    - each of the four file `URLError` codes is not retryable;
    - an unreadable file inside the hold fails at once with `fileUnreadable(<name>)`;
    - `RetryPolicy.file`'s waits are 2, 4, 8, 16 and 30 s.
- [ ] Implement `UploadPayload`, the `UploadJob` and `Destination` changes, `RetryPolicy.file` and the `isRetryable` codes.
- [ ] Implement `sha256Hex(fileAt:)` as the design gives it:
  - `FileHandle` reads into one reusable 4 MiB buffer and feeds an incremental `SHA256`;
  - `try Task.checkCancellation()` runs before each read.
- [ ] Implement `S3Destination` as Destination in the design gives it:
  - `upload(fileAt:)` hashes, signs with the hash, and sends with `session.upload(for:fromFile:delegate:)`, never setting or signing `Content-Length`.
  - `download(key:to:)` does `session.download(for:delegate:)` with redirects refused.
    - On 2xx, it moves the temporary file into place, with `FileManager.replaceItemAt` when a file is there.
    - Otherwise, it reads the small error body from the temporary file for the usual error, then deletes it. It never returns `Data`.
- [ ] Implement the `UploadQueue` changes:
  - the policy comes from the payload;
  - a `.file` attempt starts `scope` before `upload(fileAt:)` and stops it when the call returns or throws;
  - `FileManager.isReadableFile` is checked inside the hold;
  - progress goes through `ProgressThrottle`.
- [ ] Change `AppCoordinator` to the payload:
  - `startUpload` takes the content type and the extension from `record.mediaKind` in both branches (:1034, :1039);
  - Clop still runs only for `.data` payloads;
  - `uploadPayload(for:)` reads an image into `.data` as `readLocalFile` did;
  - for a video, it calls `UploadPayload.video` with an existence check that holds the folder's scope;
  - `retry` and every caller go through it.
- [ ] Run the full suite.
- [ ] Commit: `feat: upload from a file with a streamed hash`.

### Task 3: Clop for videos

**Files:**
- Modify:
  - `TidyShot/Upload/ClopClient.swift`: `optimise` (:67-84);
  - `TidyShot/Upload/ClopOptimiser.swift`: `ClopSkipReason` (:8-25), the transport (:42), the queue (:52), `optimisedPNG` (:56-65) and `ClopApp.makeOptimiser` (:152-157);
  - `TidyShot/App/AppCoordinator.swift`:
    - the properties beside `optimisingIDs` (:73-76);
    - `startUpload`'s Clop branch (:1042-1068);
    - the top of `handle(_:at:)` (:1538);
    - `cancelUpload` (:1408-1423), `removeRecord` (:1429-1442) and `removeFiles(ofPruned:)` (:1504-1517).
- Tests: add to `ClopOptimiserTests`, moving its fakes to the two-argument transport, and to `ClopClientTests`.

**Consumes:** Task 1's `VideoValidation` and `VideoFixtures`, and Task 2's `UploadPayload`.

**Produces:**
- `ClopClient`:
  - `static func request(for url: URL, id: String) -> ClopRequest` sets `removeAudio: false` for an `.mp4` and leaves it nil otherwise;
  - `optimise(_:)` uses it.
- `ClopOptimiser`:
  - `init(workDirectory:transport:freeBytes:)`, where `transport: @Sendable (URL, TimeInterval) throws -> ClopResponse` and `freeBytes` defaults to `RecordingLimits.freeBytes(at:)`;
  - `static let imageTimeout: TimeInterval = 30`, `static func videoTimeout(duration: TimeInterval) -> TimeInterval` (60 + 3 × duration) and `static let videoHeadroomBytes: Int64` (1 GB);
  - `func optimisedVideo(at source: URL, duration: TimeInterval, scope: URL?) async -> ClopVideoOutcome`, on its own queue `io.tky.tidyshot.clop-video`.
- `enum ClopVideoOutcome: Equatable, Sendable { case optimised(URL, oldBytes: Int64, newBytes: Int64); case original(ClopSkipReason) }`.
- `ClopSkipReason` gains:
  - `.notEnoughSpace` (`not enough free space`);
  - `.lostAudio` (`the result lost its audio`);
  - `.notPlayable` (`the result does not play`);
  - `.differentVideo` (`the result is not one video track of the same size`);
  - `.durationChanged` (`the result's duration changed`).
- `AppCoordinator`:
  - `private(set) var optimizingVideoIDs: Set<UUID>`, observed;
  - `clopResults: [UUID: URL]`;
  - `fileUploadIDs: Set<UUID>` and the `Uploading a recording` activity.

**Steps:**
- [ ] Write the `ClopOptimiserTests` and `ClopClientTests` items under Tests (R1), using `VideoFixtures`. The fake Clop rewrites the work file in place: a smaller copy, another size, another length, no audio, or garbage. Add:
  - not enough free space returns `.original(.notEnoughSpace)` without calling the transport;
  - the work copy is a separate file, and the source is unchanged afterwards.
- [ ] See them fail.
- [ ] Change `ClopClient` and `ClopApp.makeOptimiser`:
  - the request comes from `request(for:id:)`;
  - `makeOptimiser` builds `ClopClient(bundleID:receiveTimeout:)` from the transport's timeout;
  - images pass `imageTimeout`.
- [ ] Implement `optimisedVideo` in the design's order:
  1. Check free space: the file's size plus 1 GB on the `tmp` volume.
  2. Make the work copy `tmp/Clop/<UUID>.mp4` with `FileManager.copyItem` off the main actor, holding `scope` when given.
  3. Read the work file's duration, natural size and audio-track count with `VideoValidation`.
  4. Send the request on the video queue with `videoTimeout`.
  5. Check, in order: the path, `convertedFrom`, playable, one video track of the same size, at least as many audio tracks, the duration within 0.5 s, and a smaller file.

  On every `.original`, remove the work file and any converted sibling before returning.
- [ ] In `AppCoordinator.startUpload`, a `.file` payload with Clop on and running:
  - takes a token in `optimisingIDs` and counts in `clopWaitsPerLane`, as images do;
  - goes into `optimizingVideoIDs` while it waits, and starts the activity;
  - leaves `optimizingVideoIDs` when Clop answers, and at once on `cancelUpload`, `removeRecord` and `removeFiles(ofPruned:)`.

  Pushing the set to the card is Task 8's. When Clop answers:
  - On `.optimised`, the coordinator owns the file (`clopResults[recordID]`), and the job uploads it as `.file(url, scope: nil)`.
  - A token that no longer matches, or a record that is gone, removes Clop's result.
  - `handle(_:at:)` removes `clopResults[id]` first on `.uploaded`, `.failed` and `.cancelled`, before any early return.
  - A Retry starts again from the original through `uploadPayload(for:)`.
- [ ] Implement the activity from Staying awake in the design.
  - It is one `ProcessInfo.processInfo.beginActivity(options: .userInitiated, reason: "Uploading a recording")`.
  - It is held while `fileUploadIDs` is not empty: from the Clop request, or from the enqueue when Clop is off.
  - Every terminal path takes the id out: `handle(_:at:)`'s three terminal events, `cancelUpload`, `removeRecord` and `removeFiles(ofPruned:)`.
- [ ] Run the full suite.
- [ ] Commit: `feat: Clop for recordings`.

### Task 4: Recording controller, panel and count-in stage

**Files:**
- Create in `TidyShot/Recording/`:
  - `RecordingController.swift`;
  - `ScreenRecordingDriver.swift`, which holds `SCStream`, `SCRecordingOutput` and the filter;
  - `RecordingChrome.swift`, with the protocol and `RecordingScreenChrome`;
  - `RecordingPanel.swift`, `RecordingPanelView.swift` and `PosterFrame.swift`.
- Modify:
  - `TidyShot/Scrolling/ScrollPanelGeometry.swift`, adding `bottomCentre`;
  - `TidyShot/Desktop/DesktopCoverController.swift`, adding `windowNumbers`;
  - `TidyShot/SelfTimer/SelfTimerPanel.swift`: `SelfTimerScreenStage` (:57-96) gains `showsFrame`.
- Tests:
  - create `TidyShotTests/Support/RecordingFakes.swift`, `TidyShotTests/RecordingControllerTests.swift` and `PosterFrameTests.swift`;
  - add to `ScrollPanelGeometryTests`.

**Consumes:** Task 1's `RecordingConfiguration`, `RecordingClock`, `RecordingLimits`, `RecordingEnd`, `Recording` and `VideoValidation`, and the existing `ScrollClock` and `FakeScrollClock`.

**Produces:**
- The driver:
  - `protocol RecordingStreamDriver: AnyObject { func start(_ configuration: RecordingConfiguration, outputURL: URL, exclusions: RecordingExclusions, events: @escaping (RecordingStreamEvent) -> Void) async throws; func stop() async throws }`. `events` is called on the main actor.
  - `enum RecordingStreamEvent: Equatable, Sendable { case recordingStarted, recordingFinished, outputFailed(String), streamStopped(String), streamInactive, streamActive }`.
  - `struct RecordingExclusions { var chromeWindows: Set<CGWindowID>; var cardWindows: Set<CGWindowID>; var coverWindows: Set<CGWindowID> }`.
  - `final class ScreenRecordingDriver: RecordingStreamDriver`, `init(engine: CaptureEngine)`.
  - `enum RecordingStartError: LocalizedError { case cannotHideOwnWindows, windowGone, displayGone }`, with `TidyShot could not hide its own windows.`, `The window is no longer on screen.` and `The display is no longer connected.`.
    - The driver reads shareable content again at the start (Excluded windows, Order). A window or display gone since Task 6's hand-off step 5 throws `windowGone` or `displayGone`, and the controller reports it through `RecordingEnd.startFailure` as `Recording failed` (Gap 9).
    - Task 6's step 5 is the `Screen recording` refusal for the same loss before anything starts. For a recording, only these two paths post either string.
- The chrome:
  - `protocol RecordingChrome: AnyObject`:
    - `var windowNumbers: Set<CGWindowID> { get }`;
    - `func show(onStop: @escaping () -> Void, onCancel: @escaping () -> Void)`;
    - `func update(elapsed: TimeInterval)` and `func setStopEnabled(_ enabled: Bool)`;
    - `func askToDiscard(elapsed: TimeInterval) async -> Bool`, true for Discard;
    - `func close()`.
  - `enum RecordingChromePlacement { case area(CGRect, visibleFrame: CGRect); case window(CGRect, visibleFrame: CGRect); case fullscreen(visibleFrame: CGRect) }`, in AppKit global points.
  - `final class RecordingScreenChrome: RecordingChrome`, `init(placement:)`. It shows the frame for `.area` only.
  - `RecordingPanelView.size = CGSize(width: 172, height: 44)`.
- The controller:
  - `struct RecordingRequest { let id: UUID; let configuration: RecordingConfiguration; let displayID: CGDirectDisplayID; let outputURL: URL }`. The folder of `outputURL` already exists (Task 6 creates it); the controller and the driver create nothing.
  - `enum RecordingOutcome { case keep(Recording, notice: RecordingNotice?); case nothing(notice: RecordingNotice?) }`.
  - `struct RecordingEnvironment`:
    - `clock: any ScrollClock` and `now: () -> Date`;
    - `freeBytes: (URL) -> Int64?` and `windowIsListed: (CGWindowID) -> Bool`;
    - `cardWindowNumbers: () -> Set<CGWindowID>` and `coverWindowNumbers: (CGDirectDisplayID) -> Set<CGWindowID>`;
    - `beginActivity: () -> any NSObjectProtocol` and `endActivity: (any NSObjectProtocol) -> Void`;
    - `inspect: (URL) async -> VideoFacts`, `poster: (URL) async -> CGImage?` and `removeFile: (URL) -> Void`;
    - `workspaceCenter: NotificationCenter`;
    - `static func live(cardWindowNumbers:coverWindowNumbers:) -> RecordingEnvironment`.
  - `final class RecordingController`:
    - `init(environment: RecordingEnvironment, makeDriver: @escaping () -> any RecordingStreamDriver)`;
    - `var isRunning: Bool`;
    - `func run(_ request: RecordingRequest, chrome: any RecordingChrome, onStarted: @escaping () -> Void) async -> RecordingOutcome`;
    - `func stop()`, `func cancel()` and `func close()`.
- `enum PosterFrame { static let maxSide = 800; @concurrent static func image(of url: URL) async -> CGImage? }`.
- `ScrollPanelGeometry.bottomCentre(panelSize: CGSize, visibleFrame: CGRect) -> CGRect`.
- `DesktopCoverController.windowNumbers: [CGDirectDisplayID: CGWindowID]`.
- `SelfTimerScreenStage(subject:screenFrame:showsFrame: Bool = true)`.

**Steps:**
- [ ] Write `RecordingFakes`:
  - `FakeRecordingDriver`:
    - its `start` can be held until released, and can fail;
    - its `stop` sends `recordingFinished` before it returns, after it returns, or never;
    - it can send any event, and it counts `start` and `stop`.
  - `FakeRecordingChrome` records its calls and answers `askToDiscard` as scripted.
  - A test environment on `FakeScrollClock` that logs every file access (inspect, poster, remove) and each activity begin and end, with its own `NotificationCenter`.
- [ ] Write the `RecordingControllerTests` items under Tests (R1), and add:
  - `willSleepNotification` ends a recording with `Your Mac went to sleep.`;
  - `sessionDidResignActiveNotification` ends it with `Another user took over the screen.`;
  - a window no longer listed ends it with `The recorded window closed.` at the next tick;
  - under 1 GB at a 5 s tick ends it with `Your disk is almost full.`;
  - Cancel at 4.9 s removes the file without asking; at 5 s it asks, and `Save` keeps the file as a Stop does, while `Discard` removes it and posts nothing;
  - `outputFailed` before `recordingStarted` gives `Recording failed` and no file;
  - elapsed starts at `recordingStarted`, and `startedAt` is that moment;
  - Stop is disabled once an end arrives, and a second Stop does nothing.
- [ ] Write `PosterFrameTests` (a 640×400 fixture's poster is 640×400, a 1600×1000 one's is 800×500) and the `bottomCentre` test.
- [ ] See them fail.
- [ ] Implement:
  - `PosterFrame`: `AVAssetImageGenerator.image(at: .zero)` with `maximumSize` 800;
  - `bottomCentre`: x at the visible frame's mid-x minus half the width, rounded; y at the visible frame's minY plus `gap`;
  - `windowNumbers`;
  - the `showsFrame` flag.
- [ ] Implement `ScreenRecordingDriver` as Stream and Excluded windows in the design give it:
  - The filter comes from fresh shareable content.
    - Area and fullscreen: `SCContentFilter(display:excludingApplications: [own], exceptingWindows: covers)`, with the covers found through `OverlayWindowLookup`.
    - If `own` is missing, exclude the chrome and the cards by window number, and log that windows opened later will show. A chrome window that cannot be found throws `cannotHideOwnWindows`. A cover that cannot be found does not stop the start.
    - Window: `SCContentFilter(desktopIndependentWindow:)` for the window found by id.
    - A window missing from the fresh content throws `windowGone`, and a display missing from it throws `displayGone`.
  - The stream configuration comes from `RecordingConfiguration`, and `SCRecordingOutputConfiguration` writes `.mp4` with `.h264`.
  - Every delegate callback logs one line where it arrives, then hops to the main actor as a `RecordingStreamEvent`.
    - The line is `Recording: <callback>[: <error>], recordedDuration <s> s`, read from the driver's output.
    - It covers `recordingOutputDidStartRecording`, `recordingOutputDidFinishRecording`, `recordingOutput(_:didFailWithError:)`, `stream(_:didStopWithError:)`, `streamDidBecomeInactive` and `streamDidBecomeActive`.
    - Task 9's window-change and sleep hand checks read these lines from the app.
- [ ] Implement `RecordingController` as While recording, Stopping and End rule in the design give it:
  - **Start.** Show the chrome, then start the driver. A Stop or Cancel during the start wins: stop the new stream and remove the file.
  - **During.**
    - Begin the activity at `recordingStarted`.
    - Tick once a second on the clock: elapsed, the soft limit, the window poll, and the disk check every 5 s.
    - Observe sleep and the user switch on `workspaceCenter`.
    - `streamInactive` and `streamActive` end nothing; the driver's log lines are their only trace.
  - **Ending.**
    - The first end wins.
    - Disable Stop, arm the waiter, then call `driver.stop()`. Wait for the first of the three callbacks, or for `stopTimeout`.
    - Cancel runs the same wait, then asks from 5 s.
    - Then `inspect`, `RecordingEnd.decide`, and, for a kept file, `poster`.
  - **`close()`** closes the chrome, ends the activity and removes the observers.
- [ ] Implement `RecordingPanel`, `RecordingPanelView` and `RecordingScreenChrome`:
  - The panel is a non-activating, borderless, floating `NSPanel` on all Spaces. It never becomes key and is movable by its background.
  - The view shows the elapsed time in monospaced digits, orange from 5:00, with Stop (`stop.fill`) and Cancel (`xmark`, help `Discard the recording`).
  - The discard alert has `Save` (the default, Return) and `Discard` (destructive, no key equivalent). It runs in the default run-loop mode with the app activated, as `confirmRemoveFromHistory` does.
  - Placement: the area, or the window's starting frame, through `ScrollPanelGeometry.frame`; `bottomCentre` for fullscreen. The dashed `ScrollAreaFrameWindow` is for an area only.
- [ ] Run the full suite.
- [ ] Commit: `feat: recording controller, panel and count-in stage`.

### Task 5: Saving a recording

**Files:**
- Modify:
  - `TidyShot/App/AppCoordinator.swift`:
    - `persist` (:746-793), split into the PNG write and a shared tail;
    - a new `saveRecording`;
    - `showOverlay` (:873-884) and `makeThumbnail` (:850-871);
    - the `.uploaded` case of `handle(_:at:)` (:1552-1595);
    - the `.file` path of `startUpload`.
  - `TidyShot/Output/SaveLocation.swift`, adding `moveInScoped`;
  - `TidyShot/Output/PendingFileStore.swift`, adding `moveIn`;
  - `TidyShot/Output/FileNamer.swift`: `name(counter:)` (:23-28) and `uniqueURL` (:49-57);
  - `TidyShot/Output/Notifier.swift`;
  - `TidyShot/Settings/AppSettings.swift`: `Keys` (:31-65), `register` (:155-184) and the property reads.
- Tests:
  - create `TidyShotTests/SaveLocationMoveTests.swift`;
  - add to `PendingFileStoreTests`, `FileNamerTests` and `AppSettingsTests`.

**Consumes:** Task 1's `RecordingSavePlan`, `Recording` and `RecordingLimits`, Task 2's `uploadPayload(for:)`, and Task 3's Clop branch.

**Produces:**
- `AppCoordinator`:
  - `func saveRecording(_ recording: Recording, intent: CaptureIntent = .standard, stopNotice: RecordingNotice? = nil, mode: RecordingSaveMode = .normal) async -> CaptureRecord?` and `enum RecordingSaveMode { case normal, quit }`;
  - `private(set) var linkNotCopiedIDs: Set<UUID>`: videos whose URL did not replace the clipboard, for Task 8's card;
  - `videoClipboardCounts: [UUID: Int]`.
- `SaveLocation.moveInScoped(_ source: URL, baseName: String, ext: String, folder: URL) throws -> URL` (`nonisolated static`).
- `PendingFileStore.moveIn(_ source: URL, id: UUID, ext: String) throws -> URL`.
- `FileNamer`:
  - `init(template:fallbackName:now:randomString:hostname:)`, with `fallbackName` defaulting to `Screenshot`;
  - `static let recordingDefaultTemplate = "Recording {date} at {time}"`;
  - `nonisolated static func uniqueURL(...)`.
- `Notifier`:
  - `notifyError(_:title:subtitle:revealing: URL? = nil)`: a click reveals the file;
  - `notifyUploaded(url:copied: Bool = true)`: with `copied` false, the title is `Uploaded`, the subtitle `Click to copy the link.`, and a click copies the URL without opening it.
- `AppSettings`:
  - `recordingFrameRate`, `recordingRetina`, `recordingSystemAudio`, `recordingShowsCursor`, `recordingCountdown` and `recordingFileNameTemplate`, with the design's defaults;
  - `static let recordingFrameRates = [30, 60]`;
  - `var recordingOptions: RecordingOptions`.

**Steps:**
- [ ] Write the tests and see them fail:
  - `SaveLocationMoveTests`: the file moves in under its name, a clash gets ` 2`, the source is gone afterwards, and a missing source throws and leaves the folder empty;
  - `PendingFileStoreTests`: `moveIn` makes `pending/<id>.mp4`, creating the folder;
  - `FileNamerTests`: an empty recording template gives `Recording`, the screenshot fallback is unchanged, and `uniqueURL` runs from a detached task;
  - `AppSettingsTests`: the six keys from the design default and persist, and a stored frame rate of 45 reads as 30.
- [ ] Implement `moveInScoped` (`FileManager.moveItem`, which copies across volumes), `moveIn`, the `FileNamer` changes, the two `Notifier` changes and the settings keys.
- [ ] Split `persist`:
  - The PNG write stays in `persist`.
  - A shared `finishSave` tail does the not-configured warning, the shutter, `history.add`, the thumbnail, the overlay, the upload and the notification, for both funnels.
  - `showOverlay` gains `retainsImage`, false for a video, so `latestCapture` is never set for one.
  - `makeThumbnail` gets an awaitable form for quit mode.
- [ ] Implement `saveRecording` as After stopping in the design gives it, with `RecordingSavePlan` deciding:
  1. Name the file with `recordingFileNameTemplate`, the fallback `Recording`, `now: { recording.startedAt }`, and the counter as for screenshots.
  2. The target is `RecordingSavePlan.target(for:)`.
     - For `.saveFolder` with no save folder set, `.save` and `.upload` ask through `chooseFolder`, except in quit mode.
     - A cancelled prompt, or quit mode with no folder, skips `moveInScoped`. The file goes straight to `pendingFiles.moveIn`, and the result is `.fallback(reason: RecordingSavePlan.noFolderReason)` (`No folder was chosen.`).
  3. Move detached:
     - to the save folder, `moveInScoped` gives `.saveFolder`; if it fails, `pendingFiles.moveIn` gives `.fallback(reason:)` with the error's description;
     - to `pending/`, `pendingFiles.moveIn` gives `.pending`;
     - if `pendingFiles.moveIn` fails on any of these paths, the result is `leftInTmp`.
  4. Make the plan.
  5. Copy the file reference. Store `videoClipboardCounts[id]`: the count after the reference, or the count found when none was copied.
  6. Make the record: `id`, `timestamp: startedAt`, the video's pixel size, `mediaKind: .video` and `durationSeconds`.
  7. Run `finishSave` with the poster as the thumbnail and the card image. The upload is `uploadPayload(for:)`.
  8. Post `stopNotice` with `revealing:` at the final file. It replaces `Recording saved`.

  `intent.then` and `intent.copyOnly` are ignored. `lastCaptureURL` is set only for a save-folder file. In quit mode the thumbnail is written before the call returns.
- [ ] In `handle(_:at:)`'s `.uploaded` case, a video replaces the clipboard only when `RecordingSavePlan.replacesClipboard` holds.
  - When it does, post `Uploaded, URL copied` as today.
  - When it does not, put the id in `linkNotCopiedIDs` and call `notifyUploaded(url:copied: false)`. Pushing the set to the card is Task 8's.
  - Both follow Show notification.
  - Screenshots are unchanged.
- [ ] Add the size check to `startUpload`'s `.file` path, after Clop, on the file actually sent, under its scope, detached. Over `singleUploadBytes`, `RecordingSavePlan` decides and the coordinator carries it out:
  - nothing is enqueued, and no key or counter is drawn (Gap 3);
  - the activity and `clopResults` are cleaned up;
  - when `RecordingSavePlan.oversizedMoves(fileIsTemporary:)` holds, the pending file moves detached through `moveInScoped`, asking for a folder if none is set. A cancelled prompt gives `.fallback(reason: RecordingSavePlan.noFolderReason)`, and a failed move gives `.fallback(reason:)` with the error's description; either way the file stays in `pending/`;
  - the record takes `fileIsTemporary` and `uploadState` (always `.none`) from `RecordingSavePlan.oversized(fileIsTemporary:move:)`, and a moved file its new `fileURL`;
  - the plan's `notices` always post, `Not uploaded` first.
- [ ] Run the full suite.
- [ ] Commit: `feat: save recordings`.

### Task 6: Record Screen and Record Fullscreen

**Files:**
- Modify:
  - `TidyShot/Selection/Selection.swift`: `SelectionMode` (:4-16);
  - `TidyShot/App/Shortcuts.swift`;
  - `TidyShot/App/AppCoordinator.swift`:
    - the controllers beside `selfTimer` (:41);
    - `registerShortcuts` (:186-222);
    - the new `recordScreen`, `recordFullscreen` and `stopRecording`, beside `captureSelfTimer` (:402-414);
    - Task 5's `saveRecording`, for the count of saves before `history.add`;
  - `TidyShot/App/StatusMenuController.swift`: `updateIcon` (:41-51), `rebuild` (:66-110) and the actions (:127-147);
  - `TidyShot/Settings/ShortcutsSettingsView.swift`, `CaptureSettingsView.swift` (:21-35) and `GeneralSettingsView.swift` (:24-55);
  - `TidyShot/Settings/UploadSettingsView.swift` (:62);
  - `TidyShot/Output/SaveLocation.swift` (:30).
- Tests: add to `ShortcutsTests` and `SelectionOutcomeTests`.

**Consumes:** Tasks 1, 4 and 5.

**Produces:**
- `KeyboardShortcuts.Name.recordScreen`, `Self("recordScreen", initial: .init(.eight, modifiers: [.control, .shift]))`, and `KeyboardShortcuts.Name.recordFullscreen`, `Self("recordFullscreen")`.
- `SelectionMode.recording`.
- `enum RecordingPhase: Equatable, Sendable { case idle, countIn, recording, saving }`.
- `enum RecordingShortcutAction: Equatable, Sendable { case start, cancelCountIn, stop }`.
- `AppCoordinator`:
  - `func recordScreen() async`, `func recordFullscreen() async` and `func stopRecording()`;
  - `static func recordingShortcutAction(for phase: RecordingPhase) -> RecordingShortcutAction` (pure): `.countIn` cancels, `.recording` stops, and `.idle` and `.saving` start;
  - `private(set) var isRecording: Bool`, observed;
  - `private var recordingCountIn: Bool`, the count-in flag. It is true from the selection's return (for fullscreen, from the free-space check) until `recorder.run` is called or the start gives up. It covers the count-in, the settle delay and the fresh content read, with the count-in on or off (Gap 9). `selfTimer.isRunning` cannot serve: it stays true until `run`'s capture closure returns;
  - `recordingSavesInFlight: Int`, the recordings between the recorder's `.keep` and `history.add`;
  - `var recordingPhase: RecordingPhase`: `.countIn` while `recordingCountIn`, else `.recording` while `recorder.isRunning` (from `run`'s call to its return), else `.saving` while `recordingSavesInFlight > 0`, else `.idle`.

**Steps:**
- [ ] Write the tests and see them fail:
  - `ShortcutsTests.recordScreenIsControlShiftEight`: no shared key or default with any other name, and `recordFullscreen` has none;
  - `ShortcutsTests`: `recordingShortcutAction` for each phase;
  - the `.recording` case in `SelectionOutcomeTests`.
- [ ] Add the shortcut names and `SelectionMode.recording`, which behaves as `.selfTimer`.
- [ ] Implement `recordScreen` as Starting in the design gives it:
  - **Re-entry.** `recordScreen` and `recordFullscreen` both begin with `recordingShortcutAction(for: recordingPhase)`, before the lock, as `captureScrolling` does with `advance()`.
    - `.cancelCountIn` calls `selfTimer.cancel()` and returns; `.stop` calls `recorder.stop()` and returns.
    - So either shortcut cancels a count-in and stops a recording, whichever of the two started it.
  - **Lock.** `withCaptureLock(coversDesktop: true)`:
    - `Recording.makeDirectory()`; a failure posts `RecordingEnd.startFailure` with the error's description, and nothing starts (Gap 1);
    - `RecordingLimits.freeBytes(at: Recording.directory)` under `startFreeBytes` refuses with `Your disk is almost full.`, titled `Screen recording` (Gap 1);
    - select with `.recording`;
    - an area under 32×32 pt is refused with `Select a larger area to record.`, and no area becomes `lastAreaRect`;
    - a window calls `covers.hide(for: .capture)`.
  - **Hand-off.** `recordingCountIn` goes true when the selection returns, and false when `recorder.run` is called or the start gives up.
    1. `selector.dismiss()`.
    2. `NSApplication.shared.deactivate()`.
    3. The count-in, when `recordingCountdown` is on: `selfTimer.run(seconds: 3, stage:)` with an empty capture closure.
       - The recording starts after `run` returns `.finished`, never inside the closure, so `selfTimer.isRunning` is false while recording.
       - `.cancelled` ends the start, with nothing recorded and the lock released.
    4. `SelfTimerController.settleDelay`, which `run` supplies when the count-in is on.
    5. Fresh shareable content, with the display or window found by id, as `captureAfterCountdown` does:
       - a missing window posts `The window is no longer on screen.`, and a missing display posts `The display is no longer connected.`, both titled `Screen recording` (`RecordingEnd.refusalTitle`), never `Recording failed`;
       - nothing starts, and the lock is released;
       - a window's size comes from its fresh frame.

    Every refusal is titled `Screen recording`. The driver's own content read at the start is a second check, reported as a start failure (Task 4, Gap 9).
  - **Recording.** Build the `RecordingSource` with the fresh frame, `RecordingConfiguration.make` with `settings.recordingOptions`, the chrome placement, and `recorder.run`. `onStarted` sets `isRecording`.
  - **After.**
    - When `run` returns `.keep`, `recordingSavesInFlight` goes up by one before `recorder.close()`, so the phase never reads `.idle` between the recording and `history.add`.
    - `recorder.close()` runs inside the lock. `isRecording` goes false when the file is handed on or removed.
    - `saveRecording` runs after the lock, as `captureText` runs its work. A `.nothing` notice posts.
- [ ] In `saveRecording`, take `recordingSavesInFlight` down by one, exactly once: right after `history.add`, or in quit mode once the thumbnail is written, or on a return before `history.add` (`leftInTmp`). The two record functions are its only callers.
- [ ] Implement `recordFullscreen`: the same re-entry, lock and checks, for the display under the pointer, without steps 1 and 2. `recordingCountIn` goes true after the free-space check. Its count-in is centred with `showsFrame: false`, and the panel goes to `bottomCentre`.
- [ ] Wire `registerShortcuts`: `recordScreen` and `recordFullscreen` each call their function, whose re-entry check gives both the same cancel and stop. Escape stays as it is: the count-in stage arms it, and the recording never does.
- [ ] Change the status menu:
  - `Record Screen` and `Record Fullscreen` come after `Capture Text`, through `captureItem`.
  - During a recording, `Stop Recording  ⌃⇧8` is the first item, the two Record items are not shown, and every other capture item is disabled.
  - `updateIcon` tracks `isRecording` too: `record.circle` wins over `arrow.up.circle`, with the accessibility description `TidyShot, recording`.
- [ ] Change the settings as Settings (R1) and Captions in the design give them:
  - the Capture tab's `Section("Recording")` after the Self-timer picker;
  - `Recording file name` under `File name`;
  - the two recorders after `Capture text:`;
  - every caption change, the `Optimization` section and the save panel's message.
- [ ] Run the full suite.
- [ ] Hand check in the Debug build:
  - record an area, a window and fullscreen with each after-capture action;
  - stop from the panel, each of the two shortcuts and the menu, whichever started the recording;
  - cancel a count-in with Escape and with each shortcut;
  - Cancel under and over 5 s;
  - count-in on and off;
  - the menu and the icon during a recording.
- [ ] Commit: `feat: Record Screen and Record Fullscreen`.

### Task 7: Quit, log out and relaunch

**Files:**
- Create `TidyShot/Recording/RecordingRecovery.swift`.
- Modify:
  - `TidyShot/App/AppDelegate.swift`: `applicationShouldTerminate` (:53-60);
  - `TidyShot/App/AppCoordinator.swift`:
    - `start()` (:140-157);
    - the quit hold beside `hasUnsavedEditors` (:1789-1791);
    - a new `finishRecordingForQuit()` beside `reviewEditorsBeforeQuit` (:2376-2383);
    - the hand-off in Task 6's `recordScreen` and `recordFullscreen`, which reads `isQuitting` before `recorder.run`;
    - `saveRecording`'s quit checks;
  - `TidyShot/Output/SaveLocation.swift`: `chooseFolder` (:24-43).
- Create tests: `TidyShotTests/QuitHoldTests.swift` and `RecordingRecoveryTests.swift`.

**Consumes:** Tasks 1, 5 and 6.

**Produces:**
- `AppCoordinator`:
  - `static func holdsQuit(hasUnsavedEditors: Bool, recording: RecordingPhase) -> Bool` (pure) and `var quitNeedsHold: Bool`;
  - `func finishRecordingForQuit() async`;
  - `isQuitting`.
- `SaveLocation.cancelFolderChoice()`: closes an open `chooseFolder` panel, which then returns nil.
- `enum RecordingRecovery { struct Found: Equatable, Sendable { let url: URL; let id: UUID?; let facts: VideoFacts; let created: Date }; @concurrent static func scan(_ directory: URL) async -> [Found] }`.
  - It returns the playable files.
  - It removes every other file with the log line `Recording: <name> could not be played, removed`.

**Steps:**
- [ ] Write the tests and see them fail:
  - `QuitHoldTests`: idle with no unsaved editor does not hold; unsaved editors, a count-in, a recording and a save each hold.
  - `RecordingRecoveryTests`:
    - a playable fixture is found with its facts;
    - a garbage file is removed;
    - a missing or empty directory finds nothing;
    - `<UUID>.mp4` gives that id, and another name gives nil.
- [ ] Implement `holdsQuit`.
- [ ] Change `applicationShouldTerminate`. When `quitNeedsHold`, it returns `.terminateLater` and then:
  1. `reviewEditorsBeforeQuit()`; a cancel replies false and the recording runs on.
  2. `finishRecordingForQuit()`.
  3. `reply(toApplicationShouldTerminate: true)`, once.
- [ ] Implement `finishRecordingForQuit` as Quit, log out and restart in the design gives it:
  1. Set `isQuitting`.
  2. Cancel a count-in (`selfTimer.cancel()`). The hand-off reads `isQuitting` just before `recorder.run` and gives up, so a quit after the count-in, or with it off, records nothing (Gap 9).
  3. Stop a recording as Stop does.
  4. `cancelFolderChoice()`.
  5. Wait until `recordingPhase` is `.idle`, checking every 50 ms. Task 6's `recordingCountIn`, `recorder.isRunning` and `recordingSavesInFlight` make the phase.

  `saveRecording` reads `mode == .quit || isQuitting` after each await, so a save already under way finishes in quit mode, and its count drops only once the thumbnail is written.
- [ ] Implement `RecordingRecovery`, and the launch check in `start()` after `history.load()`. For each file found:
  - move it to `pending/<id>.mp4` with `moveIn`;
  - add a record: `fileIsTemporary` true, `.none`, `.video`, its duration and pixel size, and the Gap 6 timestamp and id;
  - write its poster as the thumbnail;
  - post `Recovered a recording` with the Gap 6 body.

  A failed move leaves the file for the next launch, with a log line.
- [ ] Run the full suite.
- [ ] Hand check:
  - quit from the menu during a `.save` recording and an `.upload` recording;
  - `kill -9` mid-recording, then relaunch.
- [ ] Commit: `feat: keep recordings across quit and crashes`.

### Task 8: Videos in cards, Recent Captures, drag-out and Save As…

**Files:**
- Modify:
  - `TidyShot/Overlay/QuickAccessView.swift`: the side buttons (:19-36), `menuItems` (:83-96), `buttonRow` (:99-112), `thumbnail` (:115-137) and `statusContent` (:157-194);
  - `QuickAccessModel.swift`, `QuickAccessController.swift` (`Actions` :33-52, beside `update` :144 and `setDragFile` :157) and `DragFileName.swift` (:13-23);
  - `TidyShot/RecentCaptures/RecentCaptureRow.swift`, `RecentCaptureFormatting.swift`, `RecentCaptureMenuItemView.swift` (:19-30), `RecentCapturesMenu.swift` (`makeActions` :107-114) and `ThumbnailProvider.swift` (`thumbnail(for:)` :51-93, `preview(for:)` :100-125);
  - `TidyShot/Output/DragFileStore.swift`: `stage` (:52-66), beside `adopt` (:70);
  - `TidyShot/Editor/Persistence/EditorInput.swift` (:37-48) and `EditorNaming.swift` (:6-42);
  - `TidyShot/App/AppCoordinator.swift`:
    - `overlayActions` (:887-899), `copyLinkOrFile` (:1153-1160), `copyImage` (:1175), `saveAs` and `saveCopy` (:1197-1226) and `imageData` (:1234);
    - `prepareDragFile` (:1656-1701), `prefetchDragFile` (:1705), `keepForDragOut` (:1730-1744) and `scheduleDragCleanup` (:1755-1764);
    - `pin` (:1856), `loadImage` (:1830) and `saveAsSuggestion` (:2187-2191);
    - the card's two flags: `showOverlay` (:873-884), `restoreClosedOverlay` (:932-946) and `refreshOverlay(for:)` (:1530-1535);
    - where the two sets change: `startUpload`'s Clop branch (:1042-1068) and the `.uploaded`, `.failed` and `.cancelled` cases of `handle(_:at:)` (:1538-1625), from Tasks 3 and 5;
    - where an id leaves them: `cancelUpload` (:1408-1423), `removeRecord` (:1429-1442) and `removeFiles(ofPruned:)` (:1504-1517).
- Tests:
  - create `TidyShotTests/QuickAccessModelTests.swift`;
  - add to `RecentCaptureFormattingTests`, `EditorInputTests`, `DragFileNameTests`, `EditorNamingTests`, `DragFileStoreTests` and `ThumbnailProviderTests`.

**Consumes:** Task 1's `MediaKind` and `RecordingClock`, Task 2's `download(key:to:)`, Task 3's `optimizingVideoIDs`, and Task 5's `linkNotCopiedIDs` and `recordingFileNameTemplate`.

**Produces:**
- `QuickAccessModel`:
  - `var isOptimizing` and `var linkWasCopied` (default true);
  - `var showsImageActions`, `var canCopyFile` and `var status: QuickAccessStatus`;
  - `onOpen` and `onCopyFile`.
- `enum QuickAccessStatus: Equatable { case saved(String), kept, uploading(Double), optimizing, urlCopied(URL), uploaded(URL), failed(String) }`.
- `QuickAccessController`:
  - `Actions.open` and `Actions.copyFile`;
  - `setOptimizing(_:for:)` and `setLinkWasCopied(_:for:)`.
- `RecentCaptureFormatting`:
  - `showsImageActions(_:)` and `canCopyFile(_:)`;
  - `detail(for:now:locale:isOptimizing:)`, which appends `· Optimizing…`;
  - `canCopyImage` and `canAnnotate` are false for a video.
- `RecentCaptureActions.copyFile`.
- `EditorInput.videoText = "Videos cannot be annotated."`.
- `EditorNaming`:
  - `SaveAsSuggestion.mediaKind`;
  - `saveAsSuggestion(for:saveFolder:namer:recordingNamer:currentCounter:)`;
  - `savePanel(for:)` allows `.mpeg4Movie` only for a video.
- `DragFileStore.stage(id:name:from:scope:reusingMatch: Bool = false)`.
- `AppCoordinator`:
  - `openCapture(recordID:)`, `copyFile(recordID:) async` and `saveVideoCopy(recordID:) async`;
  - `stagingVideoIDs` and `copyFileCounts: [UUID: Int]`.

**Steps:**
- [ ] Write the tests under Tests (R1) for these suites, and add:
  - `QuickAccessModelTests`: each `status` case, including `optimizing` and `uploaded` for a video whose link was not copied;
  - `RecentCaptureFormattingTests`: the `Optimizing…` detail;
  - `ThumbnailProviderTests`: a video's preview returns its stored thumbnail, and a video without one gives nil, with the file reader never called;
  - `DragFileStoreTests`: a source whose size or modification date changed is copied again.

  See them fail.
- [ ] Implement the pure parts:
  - `EditorInput` checks for a video first;
  - `DragFileName` adds `.png` only to images;
  - `EditorNaming`;
  - `stage`'s reuse: same name, size and modification date;
  - the formatting;
  - `QuickAccessModel.status`;
  - `ThumbnailProvider` never reads a video file.
- [ ] Change the card for a video as Quick Access card in the design gives it:
  - **Thumbnail.** The poster has a `play.fill` badge and the duration from `RecordingClock.format`; with no thumbnail, it shows `film`. A click opens the file (holding the folder's scope for a save-folder file), or opens the URL. Its tool tip is `Open`.
  - **Actions.** No Annotate, Pin or Copy Image. `Copy File` appears with a local file. Reveal stays in the menu.
  - **Status.** `Kept in TidyShot` / `Not in your save folder. Use Save As… to keep a copy.`, `Optimizing…`, and `Uploaded`.
  - **Flags.** This task owns pushing `optimizingVideoIDs` and `linkNotCopiedIDs` to the card:
    - `refreshOverlay(for:)` pushes both, `setOptimizing(optimizingVideoIDs.contains(id), for:)` and `setLinkWasCopied(!linkNotCopiedIDs.contains(id), for:)`;
    - `showOverlay` and `restoreClosedOverlay` push both right after `overlay.show`, so a new or restored card starts in the right state;
    - every change to either set calls `refreshOverlay(for:)`: the insert into and removal from `optimizingVideoIDs` in `startUpload`'s Clop branch and in `cancelUpload`, the removal at the top of `handle(_:at:)`'s three terminal events, and the insert into `linkNotCopiedIDs` in its `.uploaded` case;
    - `removeRecord` and `removeFiles(ofPruned:)` also drop the id from `linkNotCopiedIDs`. Their card is closed or gone, so nothing is pushed.
- [ ] Change the Recent Captures rows for a video:
  - the poster with the badge, or `film`;
  - no Annotate;
  - `Copy File` (`doc.on.doc`) in Copy Image's place, enabled with a local file;
  - the detail from `isOptimizing`;
  - a row click on a video with no link goes through `copyFile`.
- [ ] Add the media checks to `copyImage`, `pin`, `loadImage` and `imageData`, so no image path runs for a video.
- [ ] `saveAs` sends a video to `saveVideoCopy`:
  - the panel allows `.mpeg4Movie` only;
  - the copy runs detached, from the local file under its scope, else the drag copy, else `download(key:to:)` with `Downloading <key>` posted;
  - it replaces an existing file with `FileManager.replaceItemAt`;
  - `Saved` or `Not saved` posts as for an image.
- [ ] Change drag-out for videos:
  - `prepareDragFile` stages with `reusingMatch: true`, one stage per record at a time (`stagingVideoIDs`);
  - `prefetchDragFile` returns early for a video;
  - `keepForDragOut` keeps an existing staged copy (Gap 7).
- [ ] Implement `copyFile`:
  - a save-folder file goes on the clipboard as itself;
  - a pending file goes on as a staged drag copy (same stage and reuse);
  - the change count goes into `copyFileCounts`;
  - `scheduleDragCleanup` skips the record while that count is still the clipboard's (Gap 7).
- [ ] Run the full suite.
- [ ] Hand check:
  - a video card and row in each state;
  - open, drag out, Save As… over an existing file, and Copy File then paste in Finder;
  - Annotate is absent everywhere.
- [ ] Commit: `feat: recordings in cards and Recent Captures`.

### Task 9: Checklist, README and design close-out

**Files:**
- Create `docs/testing/recording-r1-manual-checklist.md`.
- Modify:
  - `README.md`: a "Screen recording" section, rows in Default shortcuts, Clop for videos in "Optimise with Clop", and Documents lines for the recording design and the checklist;
  - the recording design: Built notes, the spike's result if Task 1 could not record it, and the window-change and sleep probe results once Tim has run them;
  - spec 2.10's scope paragraph in `docs/superpowers/specs/2026-10-19-tidyshot-screenshot-design.md`: area and fullscreen recordings.

**Steps:**
- [ ] Grep the finished code for every string the design gives, and fix any drift.
- [ ] Write the checklist in the form of `phase-7c-manual-checklist.md`: setup, a Release build, and the defaults to delete. It covers every hand check in the design:
  - relaunch first, then a `Save and upload` recording to a save folder off the startup volume, and Retry a failed upload;
  - quitting, logging out and quitting with the folder panel open, each during a `.save` and an `.upload` recording; `kill -9` mid-recording and between Stop and the save;
  - count-in off with a Safari window;
  - exclusions during a fullscreen recording;
  - window changes:
    - `record-window.swift` on its own window and on another app's window by id: resize larger and smaller, move, move to another display, minimise, hide (⌘H), switch Space and close, writing down for each change the callbacks, `recordedDuration`, and whether the window is listed and on screen;
    - `record-window.swift` with `audio` while another app plays a sound (`afplay`), writing down whether the file has a `soun` track and whether that sound is in it;
    - the same changes in the app, writing down its `Recording:` lines: minimise, hide and another Space keep recording, and close ends it with `Recording stopped`;
    - closing or moving the window during the count-in;
  - large output on the 5K display;
  - covers;
  - Cancel;
  - display sleep;
  - sleep, lock and switch:
    - `record-stop-order.swift watch` through ⌃⌘Q, a hot-corner display sleep, a system sleep, a lid close and a fast user switch, writing down what `didStopWithError`, `didFailWithError` and the frame status reported, and whether the file plays;
    - each in the app, writing down its `Recording:` lines: sleep and a switch stop and save, and a lock keeps recording;
  - upload resilience;
  - the clipboard after the upload;
  - Copy File, including a paste more than a minute after the card closed (Gap 7);
  - the Clop queue, Clop audio and Clop cleanup;
  - Restore;
  - no destination;
  - and every gap above, to confirm or overrule.

  Each probe step gives its command (the probes README's build line), a blank for the result, and the line that reads the app's log: `/usr/bin/log show --last 10m --style compact --predicate 'process == "TidyShot"' | grep "Recording:"`.
- [ ] Write the README text, and add Built notes to the design: what was built differently, and the nine gaps.
- [ ] When Tim has run the window-change and sleep probes, write what they showed into the design's Probes section and take those bullets out of Still to probe. Until then, the PR lists them as open.
- [ ] Run the full suite and the Release build once.
- [ ] Commit: `docs: recording R1 checklist, README and design close-out`.

## Test totals

| After | Total |
|---|---|
| Baseline | 961 tests in 111 suites |
| Task 1 | baseline plus 6 new suites (`RecordingConfigurationTests`, `RecordingClockTests`, `RecordingEndTests`, `RecordingLimitsTests`, `RecordingSavePlanTests`, `VideoValidationTests`) and the `CaptureRecordTests` additions |
| Task 2 | Task 1 plus `UploadPayloadTests` (1 new suite) and the `UploadQueueTests`, `S3SignerTests`, `S3DestinationTests` and `RetryPolicyTests` additions |
| Task 3 | Task 2 plus the `ClopOptimiserTests` and `ClopClientTests` additions |
| Task 4 | Task 3 plus `RecordingControllerTests` and `PosterFrameTests` (2 new suites) and the `ScrollPanelGeometryTests` addition |
| Task 5 | Task 4 plus `SaveLocationMoveTests` (1 new suite) and the `PendingFileStoreTests`, `FileNamerTests` and `AppSettingsTests` additions |
| Task 6 | Task 5 plus the `ShortcutsTests` and `SelectionOutcomeTests` additions |
| Task 7 | Task 6 plus `QuitHoldTests` and `RecordingRecoveryTests` (2 new suites) |
| Task 8 | Task 7 plus `QuickAccessModelTests` (1 new suite) and the `RecentCaptureFormattingTests`, `EditorInputTests`, `DragFileNameTests`, `EditorNamingTests`, `DragFileStoreTests` and `ThumbnailProviderTests` additions |
| Task 9 | unchanged, 124 suites |
