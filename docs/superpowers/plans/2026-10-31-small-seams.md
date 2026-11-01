# TidyShot Small Seams (CT-3), Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Three small seams on `AppEnvironment`: the Clop optimiser and its running check (`CLOP`), the card's Save As… panel (`SAVEAS`) and the recording log sink (`LOG`). 34 tests are added, and 46 of the 49 lines these seams reach get their marks (28 in full, 18 in part); 3 are deferred. The suite goes from `Test run with 2318 tests in 193 suites passed` to `Test run with 2352 tests in 195 suites passed`. Nothing a user sees changes.

**Architecture:** `docs/superpowers/specs/2026-10-31-tidyshot-small-seams-design.md` ("the design") is the specification. Its catalogue `docs/superpowers/notes/2026-10-31-small-seams/tests-small.md` gives every test, and `lines-small.md` beside it every line. When this plan and either disagree, "Plan decisions" at the end says why.
- **Task 1, `CLOP`:** a protocol `ClopOptimising` that `ClopOptimiser` conforms to, `clopOptimiser` and `isClopRunning` on the environment, `FakeClop`, 18 tests.
- **Task 2, `SAVEAS`:** `chooseSaveAsURL` on the environment with the panel in its live closure, `FakeSaveAsChooser`, `FakeDestination.download(key:to:)` recording and writing, 11 tests.
- **Task 3, `LOG`:** `recordingLog` on the environment for the coordinator's and `RecordingRecovery.scan`'s lines, the world's `recordingLines`, 5 tests.
- **Task 4, close-out:** the marks, seams.md, `docs/testing/small-seams-manual-checklist.md` and the design's built notes.

**Tech Stack:** Swift 6 language mode with default `MainActor` isolation and `NonisolatedNonsendingByDefault`, Swift Testing, AppKit, XcodeGen 2.46, Python 3 for Task 4's scripts.

**Tried before writing:** each task's writer applied its own steps to a copy of the tree at f991760 and ran them; then the four tasks were applied in order, exactly as written, to one fresh copy with a `git init` base. Every anchor matched once and every step applied. The full suite read `2336 tests in 194 suites` after Task 1, `2347 in 195` after Task 2, `2352 in 195` after Task 3 and again after Task 4; the Release build succeeded after each seam task with only the two tool lines; each task's new and changed suites passed 5 iterations, and all nine touched suites together passed 5 iterations after Task 4 (112 tests). Task 4's marks script printed `46 lines marked, 1 deferred line's mark extended` and its seams.md script `seams.md: 42 seams, Lines 410, Alone 182, Completes 279`. The final nine `TidyShot/` files were byte-identical to the design review's, +94 −52.

Work happens on the branch `small-seams` (from `main` at 30d3c15; the design at f991760, docs only). This plan is committed on `small-seams` before Task 1, so the clean-tree checks below see a clean tree. Line numbers are f991760's; once a task has grown a file, find the place by the quoted text.

## Global Constraints

- **The phase's hard constraints** (context, with "never commit" adapted: every task commits, nothing is pushed):
  - Production changes are limited to the three seams: the optimiser and the running check, the card's Save As panel,
    and the recording log sink, each as its construction or call moves behind `AppEnvironment`. No behaviour change a
    user could see. No `private` member opened for tests. No other seam. Whether `LOG` also threads through
    `RecordingRecovery.begin` and `RecordingExtras.init` is the design's call; say what each choice unlocks.
  - No test touches `AppSettings.shared`, `NSPasteboard.general`, the Keychain, `UNUserNotificationCenter`,
    `NSWorkspace`, `NSRunningApplication`, `NSScreen.screens`, the `tmp/` statics, a window ordered front, a panel shown,
    the screen, a camera, a microphone, a sound, the real Clop app or the network. Constructing an `NSWindow` that is
    never ordered front is allowed (the view suites do it).
  - Held fakes are cancellable and single-entry; no direct await on the behaviour under test (`eventually`, `TaskWatch`);
    a held task is cancelled in a `defer` and gated with `TaskWatch`.
  - Own temp folders and defaults suite per test; no `.serialized`.
  - `HistoryStore` prunes on the real `Date()`.
  - The tests' `MovieSamples` decoder is untouched.
  - Credentials only in the Keychain; never log or print credentials or signatures.
  - No GPL code read or copied (macshot, the Clop app, gifsicle, ffmpeg, gifski). The Clop XPC protocol TidyShot speaks
    is already in `TidyShot/Upload/ClopOptimiser.swift`; read that, not Clop.
  - Never record the mic or camera; never lose a recording; never change system settings, TCC or the bucket.
  - Agents never run anything that records the screen, opens the camera or mic, plays sound, launches or talks to the
    real Clop app, or talks to a real bucket.
  - Commits and PRs carry no attribution lines and no session URL. Agents never push.
  - Plain prose, no mannered phrasing; file:line references for every claim about the code.
- **From the design's section 5, "Rules for the tests":**
  From CT-2 section 5, still binding: `TidyShot/` changes only as section 2 says, and no `private` member opens; a test that would need more is reported, not forced. No test touches `AppSettings.shared`, `NSPasteboard.general`, the Keychain, `UNUserNotificationCenter`, `NSWorkspace`, `NSRunningApplication`, `NSScreen.screens`, the `tmp/` statics, a window ordered front, a panel shown, the screen, a camera, a microphone, a sound, the real Clop app or the network. History is loaded with `history.load()`, never `start()` (Coord:294-300). `HistoryStore` prunes on the real `Date()`, so records keep timestamps near now. Held fakes are cancellable and single-entry; nothing awaits the behaviour under test directly (`eventually`, UploadQueueTests.swift:39-48; `TaskWatch`, Fakes:418-431). A held task is cancelled or released in a `defer` declared right after `defer { world.removeAll() }`. Nothing an edit starts outlives its test: `settledEdit` for SAVEAS 9 and 10 and CLOP T17. A relaunch is a second `world.makeCoordinator()`, after which the first is not called. Each test owns its world and defaults suite; suites are `@Suite(.timeLimit(.minutes(1)))` with no `.serialized`. No effect is committed in an editor test (`RedactionRenderer.shared`). The tests' `MovieSamples` decoder is untouched.
  
  This phase's own rules:
  - **The world's Clop work directory.** `FakeClop` writes only in `world.clop.workDirectory` (`<root>/tmp/Clop`), never the container's `ClopApp.workDirectory` (CO:272). Recordings are sparse pending movies; the fake never reads one. A test that keeps Clop's movie for a resume sets `world.date` later than the record's file, or the kept copy reads as outdated (`MultipartPlan.keptCopyIsOutdated`). A failed file removal is made with a 0o555 folder restored in a `defer` that runs before `removeAll()` (as CoordinatorDeleteTests.swift:290-291).
  - **The held chooser.** One held panel at a time. For an image the coordinator's task cannot be cancelled by the test, so the `defer` answer is what ends it. A Cancel step proves "nothing written or posted" through the next step's whole comparison of `world.notifier.calls`. A suggestion with no save-folder file is compared only under a template without `{time}`, `{date}` or `{datetime}`: the coordinator's `FileNamer` reads `Date()` (RA:321-329, FileNamer.swift:21), so the default template's seconds can tick between its read and the test's (tests-small.md SAVEAS.2).
  - **The log sink.** Two lists, each asserted whole. `beginRecording` runs the real `RecordingController` over `FakeRecordingDriver` and adds no line, because the recorder keeps `RecordingLog.note`. A Settings ask that must not prompt runs as its own gated task, so a prompt that comes after all fails in two seconds.
- **The suite command.** Run the full suite with:
  ```bash
  xcodegen generate && xcodebuild test -project TidyShot.xcodeproj -scheme TidyShot -destination 'platform=macOS' -derivedDataPath .build 2>&1 | grep -E "Test run with|error:|TEST"
  ```
  and one suite with `-only-testing:TidyShotTests/<Suite>` added before `2>&1`. Baseline `Test run with 2318 tests in 193 suites passed` (30d3c15, f991760). The Release build:
  ```bash
  xcodegen generate && xcodebuild -project TidyShot.xcodeproj -scheme TidyShot -configuration Release -derivedDataPath .build-rel build 2>&1 | grep -E "error:|warning:|BUILD"
  ```
  prints `** BUILD SUCCEEDED **` and no compiler or linker `error:` or `warning:`. Known noise, not failures: two `History file could not be read or decoded` lines, `com.apple.linkd.autoShortcut`, about 40 `MDB_MAP_FULL` lines, the `iOSSimulator: … sharedServiceContextForDeveloperDir:error:` line, and in Release the `appintentsmetadataprocessor … warning: Metadata extraction skipped` line. A full run that fails only on `UploadQueueTests.aSidecarUnwritableDuringThePartsFailsTheJobBeforeComplete` is rerun once (D47).
- **Counting.** `xcodebuild` counts each `@Test` function once, whatever its arguments; each new test file is one suite.
- **Commits.** After every task, with the task's message, no attribution lines and no session URL. Never push, never switch branches. No task runs the app; the hand checks are Tim's.

---

### Task 1: Clop through `AppEnvironment`, `FakeClop`, and the 18 Clop tests [integration]

**Files:**
- Modify `TidyShot/Upload/ClopOptimiser.swift`: `protocol ClopOptimising` and `extension ClopOptimiser: ClopOptimising {}`
  after the end of `ClopOptimiser` (:253) and before `ClopApp`'s doc comment (:255) (design 2.1).
- Modify `TidyShot/App/AppEnvironment.swift`: `clopOptimiser` and `isClopRunning` after `freeBytes` (:32), before
  `confirm`'s doc (:33); `live()`'s doc comment (:48-52) gains Clop and the sentence about the optimiser (design 2.4,
  the Clop part of it: design 2.4 gives only the final text after all three tasks, so this task adds Clop's words and Tasks 2 and 3 extend them); the two live values after `freeBytes:` (:73), before `confirm:` (:74) (design 2.1).
- Modify `TidyShot/App/AppCoordinator.swift`: the stored `clopOptimiser` (:158-160) becomes a `let` of the protocol
  type, set in `init` after `clipboard = environment.clipboard` (:274) (design 2.1).
- Modify `TidyShot/App/AppCoordinator+Upload.swift`: `clopIsRunning()`'s guard (:426) asks
  `environment.isClopRunning()` (design 2.1). The line count of the file does not change.
- Create `TidyShotTests/Support/ClopFakes.swift` (design 3.1, whole; the review's built file byte for byte).
- Modify `TidyShotTests/Support/CoordinatorWorld.swift`: the header comment (:11-18) names Clop; `let clop: FakeClop`
  after `let editors = FakeEditors()` (:44); `clop = FakeClop(…)` in `init` after
  `self.temporaryDirectory = temporaryDirectory` (:73); `let clop = clop` after `let editors = editors` (:112) and the
  two arguments after `freeBytes:` (:125) in `var environment` (design 3.4, the Clop part of it).
- Create `TidyShotTests/CoordinatorClopTests.swift` (catalogue CLOP.3, T1 to T15).
- Modify `TidyShotTests/CoordinatorTrimTests.swift`: T16 before the closing `}` of `struct CoordinatorTrimTests`
  (:133), after `aCaptureBeingTrimmedRefusesDeleteAndUploadTrimmed` (catalogue CLOP.4).
- Modify `TidyShotTests/CoordinatorEditorUploadTests.swift`: T17 before the closing `}` of
  `struct CoordinatorEditorUploadTests` (:939), after `uploadOfAnUploadOnlyCaptureRemovesItsDragCopyAndEveryReadGivesTheEdit`
  (catalogue CLOP.4).
- Modify `TidyShotTests/CoordinatorSaveTests.swift`: T18 after `aGIFsSizeIsTheMovedFilesSize` (ends :374), before
  `recordingNoticesNeverNameTheSender`'s doc comment (:376) (catalogue CLOP.4).
- Not in this task: `TidyShotTests/CoordinatorWorldTests.swift` (design 3.4's two Clop checks there are added by Task 2, which owns that file), and
  every `SAVEAS` and `LOG` region of the shared files (design 2.4).

**Interfaces:**
- Consumes (at f991760; the code there is 30d3c15's):
  - Production, unchanged by this task: `nonisolated struct ClopOptimiser: Sendable` with
    `func optimisedPNG(_ data: Data) async -> ClopOutcome` (TidyShot/Upload/ClopOptimiser.swift:92) and
    `@concurrent func optimisedVideo(at source: URL, duration: TimeInterval, scope: URL?) async -> ClopVideoOutcome`
    (:108-109); `nonisolated enum ClopOutcome: Equatable, Sendable { case optimised(Data, oldBytes: Int, newBytes: Int); case original(ClopSkipReason) }` (:37-40);
    `nonisolated enum ClopVideoOutcome: Equatable, Sendable { case optimised(URL, oldBytes: Int64, newBytes: Int64); case original(ClopSkipReason) }` (:44-47);
    `nonisolated enum ClopSkipReason: Equatable, Sendable` with `case notRunning`, `case failed(String)`,
    `case converted`, `case notSmaller` and `var summary: String` (:8-35); `static func runningBundleID() -> String?`
    (:267) and `static func makeOptimiser() -> ClopOptimiser` (:278) on `nonisolated enum ClopApp`.
  - The coordinator: `func retryUpload(recordID: UUID)` (AppCoordinator+Upload.swift:462),
    `func destinationDidChange()` (:78), `func makeDestination() -> UploadTarget?` (:39),
    `var isUploading: Bool` (:21), `func deleteCapture(recordID: UUID) async` (AppCoordinator+Delete.swift:15),
    `func uploadTrimmed(recordID: UUID)` (AppCoordinator+Trim.swift:379), `func openEditor(recordID: UUID)`
    (AppCoordinator+Editor.swift:15),
    `func finishSave(_ record: CaptureRecord, image: CGImage?, scale: CGFloat, captureDisplayID: CGDirectDisplayID, notConfiguredWarning: String?, showsCard: Bool, upload destination: UploadTarget?, payload: () throws -> UploadPayload, notification: SaveNotification, awaitsThumbnail: Bool = false) async`
    (AppCoordinator+Save.swift:201-204); on `AppCoordinator` (AppCoordinator.swift): `let history: HistoryStore` (:18),
    `let pendingFiles: PendingFileStore` (:21), `let multipartFiles: MultipartStore` (:23),
    `@ObservationIgnored var queue: UploadLane?` (:153), `@ObservationIgnored var drainingQueues: [UploadLane]` (:157),
    `@ObservationIgnored var optimisingIDs: [UUID: UUID]` (:165), `@ObservationIgnored var clopWaitsPerLane: [ObjectIdentifier: Int]` (:168),
    `var optimizingVideoIDs: Set<UUID>` (:171), `@ObservationIgnored var fileUploadIDs: Set<UUID>` (:181),
    `var uploadingIDs: Set<UUID>` (:192); `var isIdle: Bool` on `UploadQueue` (TidyShot/Upload/UploadQueue.swift:109).
  - Values: `func write(_ data: Data, id: UUID, ext: String) throws -> URL` and `let directory: URL` on
    `PendingFileStore` (TidyShot/Output/PendingFileStore.swift:21, :9); `let directory: URL` and
    `func keptCopyURL(for id: UUID, ext: String) -> URL` on `MultipartStore` (TidyShot/Upload/MultipartStore.swift:10, :27);
    `init(threshold: Int64, partSize: Int64, inFlight: Int)`, `static let standard` (threshold 104_857_600) and
    `static let maxPartSize: Int64 = 67_108_864` on `MultipartPlan` (TidyShot/Upload/MultipartPlan.swift:13, :20, :23);
    `var currentCounter: Int` and `var optimiseWithClop: Bool` on `AppSettings` (TidyShot/Settings/AppSettings.swift:461, :150);
    `static func fileFailureMessage(reason: String) -> String` (`"Couldn't delete the file: \(reason)"`) and
    `static let fileFailureText` on `CaptureDeletion` (TidyShot/History/CaptureDeletion.swift:131, :14);
    `static let failedReplaceRecordingMessage` on `EditorUploadPlan` (TidyShot/Editor/Persistence/EditorUploadPlan.swift:33);
    `var uploadedURL: URL?`, `var uploadedKey: String?`, `var isFailed: Bool`, `var isUploading: Bool` on `CaptureRecord`
    (TidyShot/History/CaptureRecord.swift:185, :191, :262, :267) and its memberwise `init(id:timestamp:fileURL:fileIsTemporary:…)` (:114-120).
  - The harness: `CoordinatorWorld` (`static let config` :20, `let temporaryDirectory: URL` :30, `let settings` :33,
    `notifier` :39, `cards` :40, `clipboard` :41, `confirm` :42, `editors` :44, `clock` :46, `factory` :47,
    `var multipartPlan` :50, `var location: ObjectLocation` :93, `var date: Date` :95, `var logLines: [String]` :106,
    `func makeCoordinator() -> AppCoordinator` :139, `func removeAll()` :149, `@discardableResult func storeSaveFolder() throws -> URL` :159,
    `static func writeSparseFile(at url: URL, byteCount: Int64) throws` :167 (it makes the folder),
    `static func pngData(width: Int, height: Int) throws -> Data` :188);
    `func eventually(_ condition: () async -> Bool) async throws` (TidyShotTests/UploadQueueTests.swift:42, 2 s);
    in TidyShotTests/Support/CoordinatorFakes.swift: `final class SingleWaiter<Value: Sendable>` with
    `init(cancelled: Value, secondEntry: String)`, `var isWaiting: Bool`, `func wait() async -> Value`,
    `func resume(_ value: Value)` (:377-408), `final class TaskWatch` with `init<Success: Sendable>(_ task: Task<Success, Never>)`
    and `private(set) var hasReturned` (:422-430), `FakeCards` (`enum Call` with `case optimizing(UUID, Bool)` :70,
    `private(set) var calls` :86, `func updates(for id: UUID) -> [CaptureRecord.UploadState]` :138,
    `var closes: [QuickAccessCloseReason]` :146), `FakeConfirm` (`private(set) var asked: [DeleteConfirmation]`,
    `var answers: [Bool]`, Yes when empty, :201-214), `FakeNotifier.errors` (:23), `FakeClipboard.copies` (:167),
    `FakeDestinationFactory.standard` and `add(_:at:)` (:232, :236);
    `FakeDestination` (TidyShotTests/Support/FakeDestination.swift: `init(_ state: State = State())` :136 and its
    `state: Mutex<State>` fields `failuresRemaining`, `failure`, `uploads`, `uploadAttempts`, `attemptKeys`,
    `fileUploads`, `attemptFiles`, `creates`, `partFailures`, `completes`, `aborts`, `deletedKeys`, :8-125);
    `FakeEditor.draw()` and `@discardableResult func upload(asNew: Bool = false) async -> EditorUploadOutcome`
    (TidyShotTests/Support/EditorFakes.swift:103, :141).
  - Suite helpers that already exist: in `CoordinatorTrimTests`, `var destination` (:16) and
    `func addTrimmedUpload(to coordinator: AppCoordinator, byteCount: Int64 = 3, key: String = "s/REC.mp4") throws -> CaptureRecord` (:20-34);
    in `CoordinatorEditorUploadTests`, `let key = "s/SHOT.png"` (:11), `var destination` (:17), `var link: URL` (:18),
    `func openedEditor(_ id: UUID) async throws -> FakeEditor` (:23),
    `func reopenedEditor(_ id: UUID, after first: FakeEditor) async throws -> FakeEditor` (:28),
    `func settledEdit(_ coordinator: AppCoordinator, _ id: UUID) async throws` (:34),
    `func addSavedImage(to coordinator: AppCoordinator, in folder: URL, name: String = "Shot.png", uploadState: CaptureRecord.UploadState = .none, objectLocation: ObjectLocation? = nil, uploadIsStale: Bool = false, timestamp: Date = Date(), scale: CGFloat = 1) throws -> (record: CaptureRecord, original: Data)` (:39-51),
    `func isUploaded(_ coordinator: AppCoordinator, _ id: UUID) -> Bool` (:83);
    in `CoordinatorSaveTests`, `func makeRecording(_ kind: MediaKind = .video, bytes: Int = 3) throws -> Recording` (:23),
    `func save(_ coordinator: AppCoordinator, _ recording: Recording, _ intent: CaptureIntent, …) async -> CaptureRecord?` (:32-42),
    `func isIn(_ url: URL?, _ folder: URL) -> Bool` (:55).
- Produces, production (Tasks 2 and 3 add their members around these, design 2.4):
  ```swift
  // TidyShot/Upload/ClopOptimiser.swift
  protocol ClopOptimising {
      func optimisedPNG(_ data: Data) async -> ClopOutcome
      func optimisedVideo(at source: URL, duration: TimeInterval, scope: URL?) async -> ClopVideoOutcome
  }
  extension ClopOptimiser: ClopOptimising {}
  // AppEnvironment, after freeBytes
  var clopOptimiser: any ClopOptimising
  var isClopRunning: @MainActor () -> Bool
  // AppCoordinator
  let clopOptimiser: any ClopOptimising   // was `let clopOptimiser = ClopApp.makeOptimiser()`
  ```
- Produces, `ClopFakes.swift` (main-actor under the test target's default isolation): `final class FakeClop: ClopOptimising`
  with `nonisolated enum Answer: Equatable, Sendable { case smaller(Data); case smallerMovie(byteCount: Int64); case original(ClopSkipReason); case hold }`,
  `nonisolated enum Request: Equatable, Sendable { case png(Data); case video(URL, duration: TimeInterval) }`,
  `static let cancelledAnswer: Answer`, `static let unscripted: ClopSkipReason`, `let workDirectory: URL`,
  `var isRunning = true`, `private(set) var runningChecks: Int`, `private(set) var requests: [Request]`,
  `var answers: [Answer]`, `init(workDirectory: URL)`, `var isHolding: Bool`, `func checkRunning() -> Bool`,
  `func release(_ answer: Answer)`, `var workFiles: [String]`, and the two protocol methods.
- Produces, the world: `CoordinatorWorld.clop: FakeClop` (`let`, over `<root>/tmp/Clop`), the environment's
  `clopOptimiser: clop` and `isClopRunning: { clop.checkRunning() }`.
- Produces, `CoordinatorClopTests`' helpers (this suite only): `let threshold = MultipartPlan.standard.threshold`,
  `var destination: FakeDestination`, `func addPendingImage(to:) throws -> CaptureRecord`,
  `func addSavedImage(to:in:) throws -> CaptureRecord`, `func addPendingRecording(to:byteCount:) throws -> CaptureRecord`,
  `func addGIF(to:) throws -> CaptureRecord`, `func useCounterTemplate()`, `func isUploaded(_:_:) -> Bool`,
  `func exists(_:) -> Bool`, `func lastOptimizing(_:) -> Bool?`.

**Tests** (catalogue section 3, `docs/superpowers/notes/2026-10-31-small-seams/tests-small.md`):
1. `turningClopOffDuringAnOptimisationKeepsThatUploadOptimisedAndNotTheNext`: CLOP.3 T1, tests-small.md:204; M.
2. `aClopThatIsNotRunningOrSkipsUploadsTheOriginalWithOneLine(reason:line:)`: CLOP.3 T2, :225; S; four arguments.
3. `deletingARecordingWhileClopHoldsItCancelsAtOnceAndLeavesNoMovieOrCounterGap`: CLOP.3 T3, :242; L (with the third recording).
4. `changingUploadSettingsWhileClopHoldsAnUploadFinishesItAtItsOwnDestination`: CLOP.3 T4, :260; M.
5. `aRecordingOverThePartThresholdKeepsClopsMovieAndARetryResumesWithoutClop`: CLOP.3 T5, :272; M.
6. `threeUploadsWithAnImageHeldInClopTakeCountersInStartOrder`: CLOP.3 T6, :285; M.
7. `aCaptureWhoseUploadFailsAfterClopKeepsItsPendingFileAtTheCapturedSize`: CLOP.3 T7, :298; M.
8. `deletingAnImageWhileClopHoldsItCancelsAtOnceAndNothingUploads`: CLOP.3 T8, :311; S.
9. `aDeleteDeclinedAtTheSecondAlertWhileClopHoldsLeavesTheCardCancelledAndARetryUploadsOnce`: CLOP.3 T9, :322; L.
10. `aRetryBeforeClopsFirstAnswerUploadsOnceFromTheSecondAttempt`: CLOP.3 T10, :339; L.
11. `aFailedRecordingUploadAfterClopLeavesNoMovieAndARetryAsksClopAgainFromTheOriginal`: CLOP.3 T11, :351; M.
12. `aRecordingUploadsItsOriginalWithoutOptimizingWhenClopIsOffOrNotRunning(setting:running:)`: CLOP.3 T12, :363; S; two arguments.
13. `aGIFUploadsAsMadeWithOneClopLinePerLaunch`: CLOP.3 T13, :373; M.
14. `anMP4RecordingGoesThroughClopShowingOptimizingAndUploadsClopsMovie`: CLOP.3 T14, :384; S.
15. `aClopMovieThatCannotBeKeptForResumeLogsItAndSendsTheThrowawayCopy`: CLOP.3 T15, :394; M.
16. `anUploadTrimmedWithClopWhoseFileChangedAsksClopAgainAndSendsTheSecondTrim` (`CoordinatorTrimTests`): CLOP.4 T16, :406; L.
17. `anEditorUploadAndUploadAsNewEachSendClopsBytesAndTheLinkKeepsItsKey` (`CoordinatorEditorUploadTests`): CLOP.4 T17, :421; M.
18. `anMP4sSizeIsTheMovedFilesSize` (`CoordinatorSaveTests`): CLOP.4 T18, :435; S.
- 18 tests (S 5, M 9, L 4), 2 parameterized (T2, T12), each counted once. One new suite file.
- Focused runs: `-only-testing:TidyShotTests/CoordinatorClopTests` prints `Test run with 15 tests in 1 suite passed`;
  the three existing suites together print `Test run with 30 tests in 3 suites passed` (`CoordinatorTrimTests` 4 + 1,
  `CoordinatorEditorUploadTests` 14 + 1, `CoordinatorSaveTests` 9 + 1).
- Full suite: `Test run with 2336 tests in 194 suites passed` (2318 + 18; one new suite).
- Also: `git diff --stat 30d3c15 -- TidyShot/` lists exactly `TidyShot/App/AppCoordinator+Upload.swift`,
  `TidyShot/App/AppCoordinator.swift`, `TidyShot/App/AppEnvironment.swift` and `TidyShot/Upload/ClopOptimiser.swift`,
  and ends `4 files changed, 23 insertions(+), 7 deletions(-)`. The Release build prints `** BUILD SUCCEEDED **` and
  no `error:` or `warning:` line beyond the two tool lines the Global Constraints name.

**Commit:** `refactor: Clop through AppEnvironment.clopOptimiser and isClopRunning, FakeClop, the 18 Clop tests`

**Tried before writing:** every block below was applied as written to a copy of the tree at f991760 (each "Replace"
anchor asserted once in its file, each new file absent). There `xcodegen generate` and the four suites together ran
`Test run with 45 tests in 4 suites passed`, then 10 iterations of the same with `-test-iterations 10
-run-tests-until-failure` passed, the full suite ran `Test run with 2336 tests in 194 suites passed after 49.290
seconds` with only the known noise, the Release build printed `** BUILD SUCCEEDED **` with only the two tool lines,
no compiler `warning:` came from a `.swift` file, and `git diff --stat` read `4 files changed, 23 insertions(+),
7 deletions(-)` for `TidyShot/` and `10 files changed, 972 insertions(+), 10 deletions(-)` in all.

**Steps:**

- [ ] Check the starting point. From the repository root:
  ```bash
  git branch --show-current
  git status --short -- TidyShot TidyShotTests
  git diff --stat 30d3c15 -- TidyShot/ TidyShotTests/
  ls TidyShotTests/Support/ClopFakes.swift TidyShotTests/CoordinatorClopTests.swift
  ```
  Expected: `small-seams`, then nothing, then nothing (the branch has changed only docs since `main`), then two
  `No such file or directory` lines.

#### The seam (design 2.1)

- [ ] In `TidyShot/Upload/ClopOptimiser.swift`, add the protocol and the empty conformance after the end of
  `ClopOptimiser` (:251-253) and before `ClopApp`'s doc comment (:255). Replace:
  ```swift
          return CGSize(width: width, height: height)
      }
  }

  /// Finding Clop (spec 2.7). TidyShot never launches it: a Clop that is not running means the
  ```
  with:
  ```swift
          return CGSize(width: width, height: height)
      }
  }

  /// What the coordinator asks of Clop (small seams design 2.1): `AppEnvironment.clopOptimiser`.
  /// `ClopOptimiser` is the app's; the suite's is `FakeClop`.
  protocol ClopOptimising {
      func optimisedPNG(_ data: Data) async -> ClopOutcome
      func optimisedVideo(at source: URL, duration: TimeInterval, scope: URL?) async -> ClopVideoOutcome
  }
  extension ClopOptimiser: ClopOptimising {}

  /// Finding Clop (spec 2.7). TidyShot never launches it: a Clop that is not running means the
  ```
  `ClopOptimiser` already has both methods with these exact signatures (:92, :108-109); the struct is `nonisolated`
  and `Sendable` (:53), and the protocol is main-actor under the project's default isolation (project.yml:30). The
  existential is stored in a `let` on the main-actor coordinator and never sent (design 2.1, Isolation).

- [ ] In `TidyShot/App/AppEnvironment.swift`, add the two members after `freeBytes` (:31-33). Replace:
  ```swift
      /// Free space on the volume of a URL, nil when it cannot be read.
      var freeBytes: @Sendable (URL) -> Int64?
      /// Delete's two alerts: true for Delete or Remove.
  ```
  with:
  ```swift
      /// Free space on the volume of a URL, nil when it cannot be read.
      var freeBytes: @Sendable (URL) -> Int64?
      /// Clop's optimiser (spec 2.7): a PNG or a recording rewritten smaller, or why the original uploads.
      var clopOptimiser: any ClopOptimising
      /// Whether a Clop build runs now, asked once per upload's Clop decision.
      var isClopRunning: @MainActor () -> Bool
      /// Delete's two alerts: true for Delete or Remove.
  ```

- [ ] In the same file, `live()`'s doc comment (:48-52) names Clop and says the optimiser is built here (see Plan
  decisions; Tasks 2 and 3 extend this text). Replace:
  ```swift
      /// What the app runs on: the user's Application Support folder (the temporary folder when it
      /// cannot be had), the shared settings, the Keychain, the notification centre, the card stack,
      /// the general pasteboard, S3, the alerts, the shutter sound, the editor window, the wall clock
      /// and `NSLog`. The collaborators are built in the order the coordinator's stored properties
      /// built them.
  ```
  with:
  ```swift
      /// What the app runs on: the user's Application Support folder (the temporary folder when it
      /// cannot be had), the shared settings, the Keychain, the notification centre, the card stack,
      /// the general pasteboard, S3, Clop, the alerts, the shutter sound, the editor window, the wall
      /// clock and `NSLog`. The collaborators are built in the order the coordinator's stored
      /// properties built them; Clop's optimiser, a value that reaches nothing until a request, is
      /// built here.
  ```

- [ ] In the same file, add the live values after `freeBytes:` (:73-74). They build what the coordinator's stored
  property built (`ClopApp.makeOptimiser()`, ClopOptimiser.swift:278-283) and run the expression `clopIsRunning()`
  ran (AppCoordinator+Upload.swift:426). Replace:
  ```swift
              freeBytes: { RecordingLimits.freeBytes(at: $0) },
              confirm: { await AppEnvironment.confirmLive($0) },
  ```
  with:
  ```swift
              freeBytes: { RecordingLimits.freeBytes(at: $0) },
              clopOptimiser: ClopApp.makeOptimiser(),
              isClopRunning: { ClopApp.runningBundleID() != nil },
              confirm: { await AppEnvironment.confirmLive($0) },
  ```

- [ ] In `TidyShot/App/AppCoordinator.swift`, the stored optimiser becomes the environment's (:158-160). Replace:
  ```swift
      /// Optimize images and videos with Clop (spec 2.7): one optimiser, sending to whichever Clop
      /// build runs.
      let clopOptimiser = ClopApp.makeOptimiser()
  ```
  with:
  ```swift
      /// Optimize images and videos with Clop (spec 2.7): the environment's optimiser, which in the
      /// app sends to whichever Clop build runs.
      let clopOptimiser: any ClopOptimising
  ```

- [ ] In the same file, set it in `init` right after the clipboard (:274-275). Replace:
  ```swift
          clipboard = environment.clipboard
          let url = environment.historyFileURL
  ```
  with:
  ```swift
          clipboard = environment.clipboard
          clopOptimiser = environment.clopOptimiser
          let url = environment.historyFileURL
  ```
  The property keeps its name, so `optimisedForUpload`'s two reads (AppCoordinator+Upload.swift:441, :448) are
  untouched; nothing else reads it.

- [ ] In `TidyShot/App/AppCoordinator+Upload.swift`, the running check goes through the environment (:425-426).
  Replace:
  ```swift
      private func clopIsRunning() -> Bool {
          guard ClopApp.runningBundleID() != nil else {
  ```
  with:
  ```swift
      private func clopIsRunning() -> Bool {
          guard environment.isClopRunning() else {
  ```
  The log line after it (`Clop: \(ClopSkipReason.notRunning.summary), uploading the original`, :427) is unchanged.

- [ ] Check the production change:
  ```bash
  grep -rn "ClopApp\.\|clopOptimiser\b" TidyShot/App/
  git diff --stat 30d3c15 -- TidyShot/
  ```
  Expected, the grep, exactly these eight lines:
  ```
  TidyShot/App/AppCoordinator.swift:160:    let clopOptimiser: any ClopOptimising
  TidyShot/App/AppCoordinator.swift:275:        clopOptimiser = environment.clopOptimiser
  TidyShot/App/AppCoordinator.swift:299:        try? FileManager.default.removeItem(at: ClopApp.workDirectory)
  TidyShot/App/AppEnvironment.swift:34:    var clopOptimiser: any ClopOptimising
  TidyShot/App/AppEnvironment.swift:79:            clopOptimiser: ClopApp.makeOptimiser(),
  TidyShot/App/AppEnvironment.swift:80:            isClopRunning: { ClopApp.runningBundleID() != nil },
  TidyShot/App/AppCoordinator+Upload.swift:441:            switch await clopOptimiser.optimisedPNG(data) {
  TidyShot/App/AppCoordinator+Upload.swift:448:            switch await clopOptimiser.optimisedVideo(at: url, duration: duration, scope: scope) {
  ```
  (`start()`'s sweep of `ClopApp.workDirectory` stays, `TMPDIRS`), and the diffstat ends
  `4 files changed, 23 insertions(+), 7 deletions(-)`. The project does not build until the world passes the two new
  arguments (next section); do not build yet.

#### The fake and the world (design 3.1, 3.4)

- [ ] Create `TidyShotTests/Support/ClopFakes.swift` with exactly this content (design 3.1; the review's built file).
  It uses `SingleWaiter` (CoordinatorFakes.swift:377-416) and `CoordinatorWorld.writeSparseFile(at:byteCount:)`
  (CoordinatorWorld.swift:167-175, which makes the work folder on the first movie). `Answer` and `Request` are
  `nonisolated` and `Sendable` because `SingleWaiter` carries an `Answer`:
  ```swift
  import Foundation
  import Testing
  @testable import TidyShot
  /// Clop in the suite (small seams design 3.1): `environment.clopOptimiser` and `isClopRunning` in one.
  /// Each request is recorded, then answered from `answers` in order. A request with no answer left, or an
  /// answer of the other kind, records an issue and is answered `.original(unscripted)`. A second hold
  /// while one is held records an issue and is answered `cancelledAnswer` at once. Nothing here reaches
  /// Clop, its port, `NSRunningApplication` or the serial queues.
  final class FakeClop: ClopOptimising {
      /// What one request answers. `Sendable` because `SingleWaiter` carries it.
      nonisolated enum Answer: Equatable, Sendable {
          case smaller(Data)  // an image: these bytes, fewer than the request's
          /// A recording: a sparse movie of this many bytes in `workDirectory`, owned by the caller.
          case smallerMovie(byteCount: Int64)
          case original(ClopSkipReason)
          case hold  // waits for `release(_:)`
      }
      nonisolated enum Request: Equatable, Sendable {
          case png(Data)
          case video(URL, duration: TimeInterval)
      }
      static let cancelledAnswer = Answer.original(.failed("FakeClop's held request was cancelled"))
      static let unscripted = ClopSkipReason.failed("FakeClop had no answer for this request")
      let workDirectory: URL
      var isRunning = true
      private(set) var runningChecks = 0
      private(set) var requests: [Request] = []
      var answers: [Answer] = []
      private let held = SingleWaiter(cancelled: FakeClop.cancelledAnswer,
                                      secondEntry: "FakeClop held a second request while one was held")
      init(workDirectory: URL) { self.workDirectory = workDirectory }
      var isHolding: Bool { held.isWaiting }
      func checkRunning() -> Bool {
          runningChecks += 1
          return isRunning
      }
      /// Answers the held request; a no-op when none is held, so a test's `defer` can call it.
      func release(_ answer: Answer) { held.resume(answer) }
      var workFiles: [String] {
          (try? FileManager.default.contentsOfDirectory(atPath: workDirectory.path(percentEncoded: false))) ?? []
      }
      func optimisedPNG(_ data: Data) async -> ClopOutcome {
          requests.append(.png(data))
          switch await nextAnswer() {
          case .smaller(let bytes):
              if bytes.count >= data.count {
                  Issue.record("FakeClop's smaller PNG is \(bytes.count) bytes, the request \(data.count)")
              }
              return .optimised(bytes, oldBytes: data.count, newBytes: bytes.count)
          case .original(let reason):
              return .original(reason)
          case .smallerMovie, .hold:
              Issue.record("FakeClop was given a movie answer for a PNG")
              return .original(Self.unscripted)
          }
      }
      func optimisedVideo(at source: URL, duration: TimeInterval, scope: URL?) async -> ClopVideoOutcome {
          requests.append(.video(source, duration: duration))
          // Read before any hold: `ClopOptimiser` copies the source before it sends the request.
          let oldBytes = Int64((try? source.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
          switch await nextAnswer() {
          case .smallerMovie(let byteCount):
              if byteCount >= oldBytes {
                  Issue.record("FakeClop's smaller movie is \(byteCount) bytes, the source \(oldBytes)")
              }
              let movie = workDirectory.appending(path: "\(UUID().uuidString).mp4", directoryHint: .notDirectory)
              do {
                  try CoordinatorWorld.writeSparseFile(at: movie, byteCount: byteCount)
              } catch {
                  Issue.record(error)
                  return .original(Self.unscripted)
              }
              return .optimised(movie, oldBytes: oldBytes, newBytes: byteCount)
          case .original(let reason):
              return .original(reason)
          case .smaller, .hold:
              Issue.record("FakeClop was given a PNG answer for a movie")
              return .original(Self.unscripted)
          }
      }
      private func nextAnswer() async -> Answer {
          guard !answers.isEmpty else {
              Issue.record("FakeClop was asked with no answer scripted")
              return .original(Self.unscripted)
          }
          let answer = answers.removeFirst()
          guard answer == .hold else { return answer }
          let released = await held.wait()
          guard released != .hold else {
              Issue.record("FakeClop's held request was released with .hold")
              return Self.cancelledAnswer
          }
          return released
      }
  }
  ```

- [ ] In `TidyShotTests/Support/CoordinatorWorld.swift`, the header comment (:11-18) names Clop only; Tasks 2 and 3 add the Save As panel and the two logs. Replace:
  ```swift
  /// after the test, settings and a save location over it, credentials in memory, the fakes, the editors
  /// the coordinator opens (`editors`; no window is built), a clock the test moves, a date it sets, free
  /// space it sets, a log it reads and a destination factory. Build it in the suite's `init`, make the
  /// coordinator with `makeCoordinator()`, and `defer { world.removeAll() }` first thing in each test.
  ```
  with:
  ```swift
  /// after the test, settings and a save location over it, credentials in memory, the fakes, the editors
  /// the coordinator opens (`editors`; no window is built), Clop (`clop`, over `<root>/tmp/Clop`), a clock
  /// the test moves, a date it sets, free space it sets, a log it reads and a destination factory. Build it
  /// in the suite's `init`, make the coordinator with `makeCoordinator()`, and `defer { world.removeAll() }`
  /// first thing in each test.
  ```

- [ ] In the same file, add the fake after the editors (:43-44). Replace:
  ```swift
      /// Every editor the coordinator opened (`environment.makeEditor`); no window is built.
      let editors = FakeEditors()
  ```
  with:
  ```swift
      /// Every editor the coordinator opened (`environment.makeEditor`); no window is built.
      let editors = FakeEditors()
      /// Clop's optimiser and running check (`environment.clopOptimiser`, `isClopRunning`), working in
      /// `<root>/tmp/Clop`: running, with no answers scripted.
      let clop: FakeClop
  ```

- [ ] In the same file, build it in `init` over the world's own `tmp`, so it is `<root>/tmp/Clop` and `removeAll()`
  removes it (:73). Replace:
  ```swift
          self.temporaryDirectory = temporaryDirectory
          let suiteName = "io.tky.tidyshot.tests.CoordinatorWorld-\(name)-\(UUID().uuidString)"
  ```
  with:
  ```swift
          self.temporaryDirectory = temporaryDirectory
          clop = FakeClop(workDirectory: temporaryDirectory.appending(path: "Clop", directoryHint: .isDirectory))
          let suiteName = "io.tky.tidyshot.tests.CoordinatorWorld-\(name)-\(UUID().uuidString)"
  ```

- [ ] In the same file, in `var environment`, capture it after the editors (:112-113). Replace:
  ```swift
          let editors = editors
          return AppEnvironment(
  ```
  with:
  ```swift
          let editors = editors
          let clop = clop
          return AppEnvironment(
  ```

- [ ] In the same file, pass it after `freeBytes:` (:125-126), in `AppEnvironment`'s member order. Replace:
  ```swift
              freeBytes: { url in state.freeBytes(at: url) },
              confirm: { question in await confirm.confirm(question) },
  ```
  with:
  ```swift
              freeBytes: { url in state.freeBytes(at: url) },
              clopOptimiser: clop,
              isClopRunning: { clop.checkRunning() },
              confirm: { question in await confirm.confirm(question) },
  ```
  `AppEnvironment` is built at exactly two sites, `live()` and here (design 2.4); both now pass the two arguments.

#### `CoordinatorClopTests` (catalogue CLOP.2, CLOP.3)

- [ ] Create `TidyShotTests/CoordinatorClopTests.swift` with exactly this content. The suite turns Clop on and sets a
  small lane plan in `init` (CLOP.2); every test opens with `defer { world.removeAll() }`, and a test that scripts
  `.hold` declares `defer { world.clop.release(FakeClop.cancelledAnswer) }` right after it, so a failing test ends the
  held request first. A Delete during a hold runs in its own `Task`, cancelled in a `defer` and gated with `TaskWatch`.
  T9 and T10 make the save folder read-only after the record is added and restore it in a `defer` declared after the
  other two, so it runs first (the pattern of CoordinatorDeleteTests.swift:290-291); T15 does the same for
  `multipart/`. Doc comments name each line by catalogue key and current line, and for a part line what stays and whose
  (`lines-small.md`):
  ```swift
  import Foundation
  import Testing
  @testable import TidyShot

  /// Clop on a built coordinator (small seams design, CLOP): the image and recording decisions, what is
  /// sent, the `Clop:` lines, and Delete, a Retry, a settings change and the toggle while Clop holds a
  /// request. Clop is the world's `FakeClop`; its work folder is `<root>/tmp/Clop`. A test that scripts
  /// `.hold` releases it in a `defer` placed after `removeAll()`'s and gates on `clopWaitsPerLane` emptying
  /// before its last checks, so the start task has ended.
  @Suite(.timeLimit(.minutes(1)))
  struct CoordinatorClopTests {
      let world: CoordinatorWorld
      /// `MultipartPlan.standard.threshold` (100 MiB): Clop's movie at this size or more is kept for resume,
      /// whatever the lane's plan (+Upload:274).
      let threshold = MultipartPlan.standard.threshold

      init() throws {
          world = try CoordinatorWorld()
          world.multipartPlan = MultipartPlan(threshold: 1_048_576, partSize: 262_144, inFlight: 3)
          world.settings.optimiseWithClop = true
      }

      var destination: FakeDestination { world.factory.standard }

      /// An upload-only screenshot in `pending/`, failed, added to history.
      func addPendingImage(to coordinator: AppCoordinator) throws -> CaptureRecord {
          let id = UUID()
          let png = try CoordinatorWorld.pngData(width: 4, height: 2)
          let url = try coordinator.pendingFiles.write(png, id: id, ext: "png")
          let record = CaptureRecord(id: id, fileURL: url, fileIsTemporary: true, pixelWidth: 4, pixelHeight: 2,
                                     appName: nil, uploadState: .failed(message: "Upload was interrupted."),
                                     byteCount: png.count)
          coordinator.history.add(record)
          return record
      }

      /// A screenshot saved as `Saved <id>.png` in `folder`, failed, added to history.
      func addSavedImage(to coordinator: AppCoordinator, in folder: URL) throws -> CaptureRecord {
          let id = UUID()
          let png = try CoordinatorWorld.pngData(width: 4, height: 2)
          let url = folder.appending(path: "Saved \(id.uuidString).png")
          try png.write(to: url)
          let record = CaptureRecord(id: id, fileURL: url, fileIsTemporary: false, pixelWidth: 4, pixelHeight: 2,
                                     appName: nil, uploadState: .failed(message: "Upload was interrupted."),
                                     byteCount: png.count)
          coordinator.history.add(record)
          return record
      }

      /// A 10 s recording whose sparse file of `byteCount` bytes is `pending/<id>.mp4`, failed, added to history.
      func addPendingRecording(to coordinator: AppCoordinator, byteCount: Int64) throws -> CaptureRecord {
          let id = UUID()
          let url = coordinator.pendingFiles.directory.appending(path: "\(id.uuidString).mp4")
          try CoordinatorWorld.writeSparseFile(at: url, byteCount: byteCount)
          let record = CaptureRecord(id: id, fileURL: url, fileIsTemporary: true, pixelWidth: 1600, pixelHeight: 1000,
                                     appName: nil, uploadState: .failed(message: "Upload was interrupted."),
                                     mediaKind: .video, durationSeconds: 10, byteCount: Int(byteCount))
          coordinator.history.add(record)
          return record
      }

      /// A 10 s GIF of 3 sparse bytes, `pending/<id>.gif`, failed, added to history.
      func addGIF(to coordinator: AppCoordinator) throws -> CaptureRecord {
          let id = UUID()
          let url = coordinator.pendingFiles.directory.appending(path: "\(id.uuidString).gif")
          try CoordinatorWorld.writeSparseFile(at: url, byteCount: 3)
          let record = CaptureRecord(id: id, fileURL: url, fileIsTemporary: true, pixelWidth: 1600, pixelHeight: 1000,
                                     appName: nil, uploadState: .failed(message: "Upload was interrupted."),
                                     mediaKind: .gif, durationSeconds: 10, byteCount: 3)
          coordinator.history.add(record)
          return record
      }

      /// Keys `s/<counter>.<ext>`, so the order counters are drawn in shows.
      func useCounterTemplate() {
          var config = CoordinatorWorld.config
          config.keyTemplate = "s/{counter}"
          world.settings.s3Config = config
      }

      func isUploaded(_ coordinator: AppCoordinator, _ id: UUID) -> Bool {
          coordinator.history.record(id: id)?.uploadedURL != nil
      }

      func exists(_ url: URL) -> Bool {
          FileManager.default.fileExists(atPath: url.path(percentEncoded: false))
      }

      /// The last `Optimizing…` flag the card was given for `id`, or nil when it was given none.
      func lastOptimizing(_ id: UUID) -> Bool? {
          for call in world.cards.calls.reversed() {
              if case .optimizing(let callID, let flag) = call, callID == id { return flag }
          }
          return nil
      }

      /// phase-7-clop:21 (:23), in part; phase-7-clop:45 (:47); small-tweaks:14 (:17); the hold leg of
      /// phase-7-clop:29 (:31) and the Retry leg of phase-7-clop:28 (:30). With Clop on and running, a Retry's PNG
      /// goes to Clop, the pending file stays as captured while it waits, and Clop's bytes are sent and become the
      /// row's size. Turned off during that request, the running upload still sends Clop's bytes; the next asks
      /// nothing and sends the original. Stays: phase-7-clop:21, closing Settings with no Save and `defaults read`
      /// of the real domain, by hand (the persistence is `AppSettingsTests.optimiseWithClopDefaultsOffAndPersists`).
      @Test func turningClopOffDuringAnOptimisationKeepsThatUploadOptimisedAndNotTheNext() async throws {
          defer { world.removeAll() }
          defer { world.clop.release(FakeClop.cancelledAnswer) }
          let smaller = Data("clop".utf8)
          world.clop.answers = [.hold]
          let coordinator = world.makeCoordinator()
          let first = try addPendingImage(to: coordinator)
          let pending = try #require(first.fileURL)
          let original = try Data(contentsOf: pending)

          coordinator.retryUpload(recordID: first.id)
          try await eventually { world.clop.isHolding }
          #expect(world.clop.requests == [.png(original)])
          #expect(world.clop.runningChecks == 1)
          #expect(try Data(contentsOf: pending) == original)
          #expect(coordinator.history.record(id: first.id)?.uploadState == .uploading(fraction: 0))
          #expect(destination.state.withLock { $0.uploadAttempts } == 0)

          world.settings.optimiseWithClop = false
          world.clop.release(.smaller(smaller))
          try await eventually { isUploaded(coordinator, first.id) }
          try await eventually { coordinator.clopWaitsPerLane.isEmpty }
          #expect(destination.state.withLock { $0.uploads.map(\.data) } == [smaller])
          #expect(coordinator.history.record(id: first.id)?.byteCount == smaller.count)
          #expect(!world.logLines.contains { $0.hasPrefix("Clop:") })

          let second = try addPendingImage(to: coordinator)
          let secondOriginal = try Data(contentsOf: try #require(second.fileURL))
          coordinator.retryUpload(recordID: second.id)
          try await eventually { isUploaded(coordinator, second.id) }
          #expect(world.clop.requests.count == 1)
          #expect(world.clop.runningChecks == 1)
          #expect(destination.state.withLock { $0.uploads.map(\.data) } == [smaller, secondOriginal])
          #expect(coordinator.history.record(id: second.id)?.byteCount == secondOriginal.count)
      }

      /// phase-7-clop:31 (:33), phase-7-clop:35 (:37), phase-7-clop:36 (:38), phase-7-clop:37 (:39). Clop not running
      /// asks nothing; a result Clop could not shrink, a converted file and a failed request each upload the original.
      /// Each logs one `Clop:` line and posts no error. TidyShot never launches Clop: `ClopApp` has no launch call. What
      /// makes real Clop answer each way (a white fill, Clop's convert setting, the free-tier cap) is the lines' set-up;
      /// the optimiser's own checks are `ClopOptimiserTests`.
      @Test(arguments: [
          (ClopSkipReason.notRunning, "Clop: Clop is not running, uploading the original"),
          (.notSmaller, "Clop: the result is not smaller, uploading the original"),
          (.converted, "Clop: Clop converted the file to another format, uploading the original"),
          (.failed("Clop's port is unavailable"), "Clop: Clop's port is unavailable, uploading the original"),
      ])
      func aClopThatIsNotRunningOrSkipsUploadsTheOriginalWithOneLine(reason: ClopSkipReason, line: String) async throws {
          defer { world.removeAll() }
          if reason == .notRunning {
              world.clop.isRunning = false
          } else {
              world.clop.answers = [.original(reason)]
          }
          let coordinator = world.makeCoordinator()
          let record = try addPendingImage(to: coordinator)
          let original = try Data(contentsOf: try #require(record.fileURL))

          coordinator.retryUpload(recordID: record.id)
          try await eventually { isUploaded(coordinator, record.id) }

          #expect(world.clop.runningChecks == 1)
          #expect(world.clop.requests == (reason == .notRunning ? [] : [.png(original)]))
          #expect(world.logLines.filter { $0.hasPrefix("Clop:") } == [line])
          #expect(destination.state.withLock { $0.uploads.map(\.data) } == [original])
          #expect(world.notifier.errors.isEmpty)
          #expect(coordinator.history.record(id: record.id)?.byteCount == original.count)
      }

      /// recording-r1:271 (:285), its second sentence (the first is
      /// `CoordinatorDeleteTests.deleteDuringAnUploadCancelsItThenDeletesTheReservedKey`); recording-r1:330 (:376); the
      /// Delete leg of recording-r1:296 (:328), in part. Delete while Clop holds a recording's request: the card leaves
      /// `Optimizing…` and Delete finishes before Clop answers; Clop's late movie is removed, so `tmp/Clop` is empty,
      /// nothing uploads and no counter is drawn. The next two recordings take the next two counters, and `tmp/Clop` is
      /// empty after each optimised upload. Stays: recording-r1:296, the real container's `tmp/Clop` and the launch
      /// sweep of it (`TMPDIRS`).
      @Test func deletingARecordingWhileClopHoldsItCancelsAtOnceAndLeavesNoMovieOrCounterGap() async throws {
          defer { world.removeAll() }
          defer { world.clop.release(FakeClop.cancelledAnswer) }
          useCounterTemplate()
          world.clop.answers = [.hold, .smallerMovie(byteCount: 2), .smallerMovie(byteCount: 2)]
          let coordinator = world.makeCoordinator()
          let deleted = try addPendingRecording(to: coordinator, byteCount: 3)
          let next = try addPendingRecording(to: coordinator, byteCount: 3)
          let third = try addPendingRecording(to: coordinator, byteCount: 3)
          let file = try #require(deleted.fileURL)
          let counter = world.settings.currentCounter

          coordinator.retryUpload(recordID: deleted.id)
          try await eventually { world.clop.isHolding }
          #expect(world.clop.requests == [.video(file, duration: 10)])
          #expect(coordinator.optimizingVideoIDs == [deleted.id])
          #expect(world.cards.calls.contains(.optimizing(deleted.id, true)))

          let delete = Task { await coordinator.deleteCapture(recordID: deleted.id) }
          defer { delete.cancel() }
          let deleteWatch = TaskWatch(delete)
          try await eventually { deleteWatch.hasReturned }
          #expect(world.clop.isHolding)
          #expect(world.confirm.asked.count == 1)
          #expect(coordinator.history.record(id: deleted.id) == nil)
          #expect(!exists(file))
          #expect(coordinator.optimizingVideoIDs.isEmpty)
          #expect(coordinator.uploadingIDs.isEmpty)
          #expect(coordinator.fileUploadIDs.isEmpty)
          #expect(lastOptimizing(deleted.id) == false)

          world.clop.release(.smallerMovie(byteCount: 2))
          try await eventually { coordinator.clopWaitsPerLane.isEmpty }
          try await eventually { world.clop.workFiles.isEmpty }
          #expect(destination.state.withLock { $0.uploadAttempts } == 0)
          #expect(world.settings.currentCounter == counter)

          coordinator.retryUpload(recordID: next.id)
          try await eventually { isUploaded(coordinator, next.id) }
          #expect(world.clop.requests.count == 2)
          #expect(coordinator.history.record(id: next.id)?.uploadedKey == "s/\(counter + 1).mp4")
          #expect(coordinator.history.record(id: next.id)?.byteCount == 2)
          #expect(world.settings.currentCounter == counter + 1)
          try await eventually { world.clop.workFiles.isEmpty }

          coordinator.retryUpload(recordID: third.id)
          try await eventually { isUploaded(coordinator, third.id) }
          #expect(world.clop.requests.count == 3)
          #expect(coordinator.history.record(id: third.id)?.uploadedKey == "s/\(counter + 2).mp4")
          #expect(world.settings.currentCounter == counter + 2)
          try await eventually { world.clop.workFiles.isEmpty }
      }

      /// phase-7-clop:44 (:46). Upload settings saved while Clop holds a PNG: the replaced lane is kept while the upload
      /// waits for Clop, the upload then finishes at the destination it started with and its URL is copied, the next
      /// capture goes to the new destination, and the old lane drains. The 65,536 px capture is the set-up the held
      /// request stands for.
      @Test func changingUploadSettingsWhileClopHoldsAnUploadFinishesItAtItsOwnDestination() async throws {
          defer { world.removeAll() }
          defer { world.clop.release(FakeClop.cancelledAnswer) }
          let smaller = Data("clop".utf8)
          world.clop.answers = [.hold, .smaller(smaller)]
          let coordinator = world.makeCoordinator()
          let first = try addPendingImage(to: coordinator)
          coordinator.retryUpload(recordID: first.id)
          try await eventually { world.clop.isHolding }

          var moved = CoordinatorWorld.config
          moved.bucket = "other.tky.io"
          moved.publicURLTemplate = "https://other.tky.io/{key}"
          let other = FakeDestination()
          world.factory.add(other, at: ObjectLocation(config: moved))
          world.settings.s3Config = moved
          coordinator.destinationDidChange()
          #expect(coordinator.queue == nil)
          #expect(coordinator.drainingQueues.count == 1)
          try await world.clock.run(for: .seconds(1))
          #expect(coordinator.drainingQueues.count == 1)

          world.clop.release(.smaller(smaller))
          try await eventually { isUploaded(coordinator, first.id) }
          let firstURL = try #require(coordinator.history.record(id: first.id)?.uploadedURL)
          #expect(coordinator.history.record(id: first.id)?.objectLocation == world.location)
          #expect(destination.state.withLock { $0.uploads.map(\.data) } == [smaller])
          #expect(world.clipboard.copies.last == .url(firstURL))

          let second = try addPendingImage(to: coordinator)
          coordinator.retryUpload(recordID: second.id)
          try await eventually { isUploaded(coordinator, second.id) }
          #expect(coordinator.history.record(id: second.id)?.objectLocation == ObjectLocation(config: moved))
          #expect(other.state.withLock { $0.uploads.map(\.data) } == [smaller])
          #expect(destination.state.withLock { $0.uploadAttempts } == 1)
          try await world.clock.run(until: { coordinator.drainingQueues.isEmpty })
          #expect(coordinator.clopWaitsPerLane.isEmpty)
      }

      /// recording-r4:255 (:269), its first sentence; recording-r4:323 (:372); small-tweaks:15 (:18), the kept-copy
      /// variant of the optimised size. Clop's movie at the 100 MiB threshold is kept in `multipart/<id>.mp4`, not left
      /// in `tmp/Clop`; the upload fails part way; Retry resumes from the kept copy without asking Clop, the row takes
      /// Clop's size, and the copy is gone after the upload.
      @Test func aRecordingOverThePartThresholdKeepsClopsMovieAndARetryResumesWithoutClop() async throws {
          defer { world.removeAll() }
          // Two parts for Clop's movie; the stored upload starts after the record's file was written.
          world.multipartPlan = MultipartPlan(threshold: 1_048_576, partSize: MultipartPlan.maxPartSize, inFlight: 1)
          world.date = Date(timeIntervalSinceNow: 3600)
          destination.state.withLock { $0.partFailures = [2: [.httpStatus(403, body: "AccessDenied: Access Denied")]] }
          world.clop.answers = [.smallerMovie(byteCount: threshold)]
          let coordinator = world.makeCoordinator()
          let record = try addPendingRecording(to: coordinator, byteCount: 2 * threshold)
          let keptCopy = coordinator.multipartFiles.keptCopyURL(for: record.id, ext: "mp4")

          coordinator.retryUpload(recordID: record.id)
          try await eventually {
              coordinator.history.record(id: record.id)?.uploadState
                  == .failed(message: "Part 2 of 2: Server returned HTTP 403: AccessDenied: Access Denied")
          }
          #expect(exists(keptCopy))
          #expect(world.clop.workFiles.isEmpty)
          #expect(coordinator.history.record(id: record.id)?.multipart?.sourcePath == keptCopy.path(percentEncoded: false))
          #expect(coordinator.history.record(id: record.id)?.multipart?.byteCount == threshold)

          coordinator.retryUpload(recordID: record.id)
          try await eventually { isUploaded(coordinator, record.id) }
          #expect(world.clop.requests.count == 1)
          #expect(world.clop.runningChecks == 1)
          #expect(world.logLines.contains("Upload: \(keptCopy.lastPathComponent) resumes at 1 of 2 parts"))
          #expect(destination.state.withLock { $0.creates.count } == 1)
          #expect(coordinator.history.record(id: record.id)?.byteCount == Int(threshold))
          try await eventually { !exists(keptCopy) }
      }

      /// phase-7-clop:32 (:34). Three uploads in a row with `{counter}` in the key template take counters in the order
      /// they started (the counter advanced by 3 at once), though Clop holds the second while the other two upload; the
      /// second then uploads under its own counter. The large scrolling capture is the set-up the held request stands
      /// for, and the world's `currentCounter` is what `defaults read … captureCounter` reads.
      @Test func threeUploadsWithAnImageHeldInClopTakeCountersInStartOrder() async throws {
          defer { world.removeAll() }
          defer { world.clop.release(FakeClop.cancelledAnswer) }
          useCounterTemplate()
          world.clop.answers = [.smaller(Data("a".utf8)), .hold, .smaller(Data("c".utf8))]
          let coordinator = world.makeCoordinator()
          let a = try addPendingImage(to: coordinator)
          let b = try addPendingImage(to: coordinator)
          let c = try addPendingImage(to: coordinator)
          let n = world.settings.currentCounter

          coordinator.retryUpload(recordID: a.id)
          coordinator.retryUpload(recordID: b.id)
          coordinator.retryUpload(recordID: c.id)
          #expect(world.settings.currentCounter == n + 3)
          #expect(world.clop.runningChecks == 3)

          try await eventually { world.clop.isHolding }
          try await eventually { isUploaded(coordinator, a.id) && isUploaded(coordinator, c.id) }
          #expect(coordinator.history.record(id: a.id)?.uploadedKey == "s/\(n + 1).png")
          #expect(coordinator.history.record(id: c.id)?.uploadedKey == "s/\(n + 3).png")
          #expect(coordinator.history.record(id: b.id)?.uploadState == .uploading(fraction: 0))
          #expect(Set(destination.state.withLock { $0.attemptKeys }) == ["s/\(n + 1).png", "s/\(n + 3).png"])

          world.clop.release(.smaller(Data("b".utf8)))
          try await eventually { isUploaded(coordinator, b.id) }
          try await eventually { coordinator.clopWaitsPerLane.isEmpty }
          #expect(coordinator.history.record(id: b.id)?.uploadedKey == "s/\(n + 2).png")
          #expect(world.clop.requests.count == 3)
          #expect(destination.state.withLock { $0.uploads.count } == 3)
          #expect(world.settings.currentCounter == n + 3)
      }

      /// phase-7-clop:29 (:31). An upload-only capture's upload through Clop fails: while Clop works, `pending/<id>.png`
      /// is the captured PNG, and after the failure it is still there at the captured size, not Clop's, and the record
      /// keeps the captured size. The success leg, the object optimised, is
      /// `turningClopOffDuringAnOptimisationKeepsThatUploadOptimisedAndNotTheNext`. Entered at `finishSave`, the tail
      /// `save(_:intent:)` shares, since a `CaptureResult` needs an `SCDisplay` or `SCWindow`.
      @Test func aCaptureWhoseUploadFailsAfterClopKeepsItsPendingFileAtTheCapturedSize() async throws {
          defer { world.removeAll() }
          defer { world.clop.release(FakeClop.cancelledAnswer) }
          let coordinator = world.makeCoordinator()
          let id = UUID()
          let png = try CoordinatorWorld.pngData(width: 4, height: 2)
          let file = try coordinator.pendingFiles.write(png, id: id, ext: "png")
          let record = CaptureRecord(id: id, fileURL: file, fileIsTemporary: true, pixelWidth: 4, pixelHeight: 2,
                                     appName: nil, uploadState: .uploading(fraction: 0), byteCount: png.count)
          world.clop.answers = [.hold]
          destination.state.withLock {
              $0.failuresRemaining = 1
              $0.failure = .httpStatus(403, body: "AccessDenied: Access Denied")
          }
          let clopBytes = Data("clop".utf8)

          await coordinator.finishSave(record, image: nil, scale: 1, captureDisplayID: 1, notConfiguredWarning: nil,
                                       showsCard: false, upload: coordinator.makeDestination(), payload: { .data(png) },
                                       notification: .none)
          try await eventually { world.clop.isHolding }
          #expect(world.clop.requests == [.png(png)])
          #expect(try Data(contentsOf: file) == png)
          #expect(coordinator.history.record(id: id)?.fileURL == file)
          #expect(coordinator.history.record(id: id)?.fileIsTemporary == true)
          #expect(coordinator.history.record(id: id)?.byteCount == png.count)
          #expect(destination.state.withLock { $0.uploadAttempts } == 0)

          world.clop.release(.smaller(clopBytes))
          try await eventually { coordinator.history.record(id: id)?.isFailed == true }
          try await eventually { coordinator.clopWaitsPerLane.isEmpty }
          #expect(coordinator.history.record(id: id)?.uploadState
              == .failed(message: "Server returned HTTP 403: AccessDenied: Access Denied"))
          #expect(destination.state.withLock { $0.uploadAttempts } == 1)
          #expect(destination.state.withLock { $0.uploads }.isEmpty)
          #expect(exists(file))
          #expect(try Data(contentsOf: file) == png)
          #expect(coordinator.history.record(id: id)?.byteCount == png.count)
          #expect(world.notifier.errors.last?.title == "Upload failed")
      }

      /// phase-7-clop:41 (:43). Delete while Clop holds an image's request cancels at once: the alert is asked, the
      /// capture leaves history, its pending file goes and the card closes before Clop answers, and Clop's late answer
      /// uploads nothing. The 65,536 px capture is the set-up the held request stands for.
      @Test func deletingAnImageWhileClopHoldsItCancelsAtOnceAndNothingUploads() async throws {
          defer { world.removeAll() }
          defer { world.clop.release(FakeClop.cancelledAnswer) }
          world.clop.answers = [.hold]
          let coordinator = world.makeCoordinator()
          let record = try addPendingImage(to: coordinator)
          let pending = try #require(record.fileURL)

          coordinator.retryUpload(recordID: record.id)
          try await eventually { world.clop.isHolding }
          let uploading = try #require(coordinator.history.record(id: record.id))
          let delete = Task { await coordinator.deleteCapture(recordID: record.id) }
          defer { delete.cancel() }
          let deleteWatch = TaskWatch(delete)
          try await eventually { deleteWatch.hasReturned }

          #expect(world.clop.isHolding)
          #expect(world.confirm.asked == [.delete(uploading)])
          #expect(coordinator.history.record(id: record.id) == nil)
          #expect(!exists(pending))
          #expect(coordinator.optimisingIDs[record.id] == nil)
          #expect(coordinator.uploadingIDs.isEmpty)
          #expect(world.cards.closes == [.deleted])

          world.clop.release(.smaller(Data("x".utf8)))
          try await eventually { coordinator.clopWaitsPerLane.isEmpty }
          #expect(destination.state.withLock { $0.uploadAttempts } == 0)
          #expect(await coordinator.queue?.queue.isIdle == true)
          #expect(!coordinator.isUploading)
      }

      /// phase-7-clop:42 (:44). Delete while Clop holds a save-folder capture whose file cannot be removed: the second
      /// alert, declined, keeps the record, which reads `Upload cancelled.` on the card, and Clop's late answer uploads
      /// nothing. Retry then uploads once, one new object under a new counter; Delete again with Remove accepted drops
      /// the record, deletes that object and leaves the file. The failed removal is a read-only save folder, standing
      /// for the line's save-folder change in Settings > General.
      @Test func aDeleteDeclinedAtTheSecondAlertWhileClopHoldsLeavesTheCardCancelledAndARetryUploadsOnce() async throws {
          defer { world.removeAll() }
          defer { world.clop.release(FakeClop.cancelledAnswer) }
          useCounterTemplate()
          let second = Data("second".utf8)
          world.clop.answers = [.hold, .smaller(second)]
          world.confirm.answers = [true, false]
          let folder = try world.storeSaveFolder()
          let coordinator = world.makeCoordinator()
          let record = try addSavedImage(to: coordinator, in: folder)
          let file = try #require(record.fileURL)
          let n = world.settings.currentCounter
          // Reads still work; the removal throws, which is what brings the second alert (+Delete:76-88).
          let folderPath = folder.path(percentEncoded: false)
          try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: folderPath)
          defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: folderPath) }

          coordinator.retryUpload(recordID: record.id)
          try await eventually { world.clop.isHolding }
          let delete = Task { await coordinator.deleteCapture(recordID: record.id) }
          defer { delete.cancel() }
          let deleteWatch = TaskWatch(delete)
          try await eventually { deleteWatch.hasReturned }
          try #require(world.confirm.asked.count == 2)
          if case .removeFromHistory(let message, let informativeText) = world.confirm.asked[1] {
              #expect(message.hasPrefix(CaptureDeletion.fileFailureMessage(reason: "")))
              #expect(informativeText == CaptureDeletion.fileFailureText)
          } else {
              Issue.record("The second alert is \(world.confirm.asked[1]), not Remove from history")
          }
          #expect(coordinator.history.record(id: record.id)?.uploadState == .failed(message: "Upload cancelled."))
          #expect(world.cards.updates(for: record.id).last == .failed(message: "Upload cancelled."))
          #expect(exists(file))
          #expect(coordinator.uploadingIDs.isEmpty)
          #expect(world.clop.isHolding)

          world.clop.release(.smaller(Data("first".utf8)))
          try await eventually { coordinator.clopWaitsPerLane.isEmpty }
          #expect(destination.state.withLock { $0.uploadAttempts } == 0)

          coordinator.retryUpload(recordID: record.id)
          try await eventually { isUploaded(coordinator, record.id) }
          #expect(destination.state.withLock { $0.uploads.map(\.data) } == [second])
          #expect(destination.state.withLock { $0.attemptKeys } == ["s/\(n + 2).png"])
          #expect(coordinator.history.record(id: record.id)?.uploadedKey == "s/\(n + 2).png")
          #expect(destination.state.withLock { $0.uploadAttempts } == 1)

          world.confirm.answers = [true, true]
          let again = Task { await coordinator.deleteCapture(recordID: record.id) }
          defer { again.cancel() }
          let againWatch = TaskWatch(again)
          try await eventually { againWatch.hasReturned }
          #expect(world.confirm.asked.count == 4)
          #expect(coordinator.history.record(id: record.id) == nil)
          #expect(exists(file))
          #expect(destination.state.withLock { $0.deletedKeys } == ["s/\(n + 2).png"])
      }

      /// phase-7-clop:43 (:45). With the file removal failing as in
      /// `aDeleteDeclinedAtTheSecondAlertWhileClopHoldsLeavesTheCardCancelledAndARetryUploadsOnce`, Delete is declined
      /// at the second alert and Retry comes while Clop still holds the first attempt: exactly one object is uploaded,
      /// from the second attempt under its own new counter, and the first attempt's late answer sends nothing.
      @Test func aRetryBeforeClopsFirstAnswerUploadsOnceFromTheSecondAttempt() async throws {
          defer { world.removeAll() }
          defer { world.clop.release(FakeClop.cancelledAnswer) }
          useCounterTemplate()
          let second = Data("second".utf8)
          world.clop.answers = [.hold, .smaller(second)]
          world.confirm.answers = [true, false]
          let folder = try world.storeSaveFolder()
          let coordinator = world.makeCoordinator()
          let record = try addSavedImage(to: coordinator, in: folder)
          let file = try #require(record.fileURL)
          let n = world.settings.currentCounter
          let folderPath = folder.path(percentEncoded: false)
          try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: folderPath)
          defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: folderPath) }

          coordinator.retryUpload(recordID: record.id)
          try await eventually { world.clop.isHolding }
          let delete = Task { await coordinator.deleteCapture(recordID: record.id) }
          defer { delete.cancel() }
          let deleteWatch = TaskWatch(delete)
          try await eventually { deleteWatch.hasReturned }
          #expect(world.confirm.asked.count == 2)
          #expect(coordinator.history.record(id: record.id)?.uploadState == .failed(message: "Upload cancelled."))
          #expect(exists(file))
          #expect(world.clop.isHolding)

          coordinator.retryUpload(recordID: record.id)
          try await eventually { isUploaded(coordinator, record.id) }
          #expect(world.clop.requests.count == 2)
          #expect(world.clop.isHolding)
          #expect(destination.state.withLock { $0.uploads.map(\.data) } == [second])
          #expect(destination.state.withLock { $0.attemptKeys } == ["s/\(n + 2).png"])
          #expect(coordinator.history.record(id: record.id)?.uploadedKey == "s/\(n + 2).png")

          world.clop.release(.smaller(Data("first".utf8)))
          try await eventually { coordinator.clopWaitsPerLane.isEmpty }
          #expect(destination.state.withLock { $0.uploadAttempts } == 1)
          #expect(destination.state.withLock { $0.uploads.map(\.data) } == [second])
          #expect(world.clipboard.copies.count == 1)
          #expect(coordinator.history.record(id: record.id)?.uploadedKey == "s/\(n + 2).png")
      }

      /// recording-r1:296 (:328), in part: after a failed upload. A recording's upload of Clop's movie fails: `tmp/Clop`
      /// is empty afterwards and the record's file is untouched; Retry asks Clop again from the original, not from the
      /// first movie, sends the new movie, and `tmp/Clop` is empty after that optimised upload too. The Delete leg is
      /// `deletingARecordingWhileClopHoldsItCancelsAtOnceAndLeavesNoMovieOrCounterGap`. Stays: the real container's
      /// `tmp/Clop` and the launch sweep of it at `start()` (`TMPDIRS`).
      @Test func aFailedRecordingUploadAfterClopLeavesNoMovieAndARetryAsksClopAgainFromTheOriginal() async throws {
          defer { world.removeAll() }
          world.clop.answers = [.smallerMovie(byteCount: 2), .smallerMovie(byteCount: 2)]
          destination.state.withLock {
              $0.failuresRemaining = 1
              $0.failure = .httpStatus(403, body: "AccessDenied: Access Denied")
          }
          let coordinator = world.makeCoordinator()
          let record = try addPendingRecording(to: coordinator, byteCount: 3)
          let file = try #require(record.fileURL)

          coordinator.retryUpload(recordID: record.id)
          try await eventually {
              coordinator.history.record(id: record.id)?.uploadState
                  == .failed(message: "Server returned HTTP 403: AccessDenied: Access Denied")
          }
          try await eventually { world.clop.workFiles.isEmpty }
          #expect(world.clop.requests == [.video(file, duration: 10)])
          let failedAttempts = destination.state.withLock { $0.attemptFiles }
          #expect(failedAttempts.count == 1)
          #expect(failedAttempts.first?.deletingLastPathComponent().lastPathComponent == "Clop")
          #expect(exists(file))

          coordinator.retryUpload(recordID: record.id)
          try await eventually { isUploaded(coordinator, record.id) }
          try await eventually { world.clop.workFiles.isEmpty }
          #expect(world.clop.requests == [.video(file, duration: 10), .video(file, duration: 10)])
          #expect(world.clop.runningChecks == 2)
          #expect(destination.state.withLock { $0.fileUploads.count } == 1)
          let attempts = destination.state.withLock { $0.attemptFiles }
          #expect(attempts.count == 2)
          #expect(attempts.first != attempts.last)
          #expect(coordinator.history.record(id: record.id)?.byteCount == 2)
      }

      /// recording-r1:297 (:329). A recording with Clop off, and with Clop on but not running, uploads its own file: Clop
      /// is never asked, the card never says `Optimizing…`, and only the not-running case logs its `Clop:` line. No
      /// error is posted, and TidyShot never launches Clop (`ClopApp` has no launch call).
      @Test(arguments: [(false, true), (true, false)])
      func aRecordingUploadsItsOriginalWithoutOptimizingWhenClopIsOffOrNotRunning(setting: Bool,
                                                                                   running: Bool) async throws {
          defer { world.removeAll() }
          world.settings.optimiseWithClop = setting
          world.clop.isRunning = running
          let coordinator = world.makeCoordinator()
          let record = try addPendingRecording(to: coordinator, byteCount: 3)
          let pending = try #require(record.fileURL)

          coordinator.retryUpload(recordID: record.id)
          try await eventually { isUploaded(coordinator, record.id) }

          #expect(world.clop.requests.isEmpty)
          #expect(world.clop.runningChecks == (setting ? 1 : 0))
          #expect(world.logLines.filter { $0.hasPrefix("Clop:") }
              == (setting ? ["Clop: Clop is not running, uploading the original"] : []))
          #expect(!world.cards.calls.contains(.optimizing(record.id, true)))
          #expect(coordinator.optimizingVideoIDs.isEmpty)
          let sent = destination.state.withLock { $0.fileUploads.map(\.url.lastPathComponent) }
          #expect(sent == [pending.lastPathComponent])
          #expect(world.notifier.errors.isEmpty)
      }

      /// recording-r2:275 (:291), in part: the GIF half. With Clop on, a GIF uploads its own file as `image/gif`, never
      /// asks whether Clop runs and never shows `Optimizing…`; `Clop: GIFs are not sent to Clop` is logged once per
      /// launch (once for two GIFs, once more after a relaunch) and never with Clop off. Stays: `cmp` of the bucket's
      /// object against the saved file and `grep` of the real `tidyshot.err`, by hand. The MP4 half is
      /// `anMP4RecordingGoesThroughClopShowingOptimizingAndUploadsClopsMovie`; the kind rule is
      /// `CaptureRecordTests.onlyAGIFIsNotSentToClop`.
      @Test func aGIFUploadsAsMadeWithOneClopLinePerLaunch() async throws {
          defer { world.removeAll() }
          let line = "Clop: GIFs are not sent to Clop"
          let first = world.makeCoordinator()
          let gif1 = try addGIF(to: first)
          let pending1 = try #require(gif1.fileURL)

          first.retryUpload(recordID: gif1.id)
          try await eventually { isUploaded(first, gif1.id) }
          #expect(world.logLines.filter { $0 == line }.count == 1)
          #expect(destination.state.withLock { $0.fileUploads.map(\.contentType) } == ["image/gif"])
          let sent = destination.state.withLock { $0.fileUploads.map(\.url.lastPathComponent) }
          #expect(sent == [pending1.lastPathComponent])
          #expect(!world.cards.calls.contains(.optimizing(gif1.id, true)))
          #expect(world.clop.runningChecks == 0)
          #expect(world.clop.requests.isEmpty)

          let gif2 = try addGIF(to: first)
          first.retryUpload(recordID: gif2.id)
          try await eventually { isUploaded(first, gif2.id) }
          #expect(world.logLines.filter { $0 == line }.count == 1)

          // The relaunch: a second coordinator over the same world; the first is not called again.
          let second = world.makeCoordinator()
          let gif3 = try addGIF(to: second)
          second.retryUpload(recordID: gif3.id)
          try await eventually { isUploaded(second, gif3.id) }
          #expect(world.logLines.filter { $0 == line }.count == 2)

          world.settings.optimiseWithClop = false
          let third = world.makeCoordinator()
          let gif4 = try addGIF(to: third)
          third.retryUpload(recordID: gif4.id)
          try await eventually { isUploaded(third, gif4.id) }
          #expect(world.logLines.filter { $0 == line }.count == 2)
          #expect(destination.state.withLock { $0.fileUploads.count } == 4)
          #expect(world.clop.runningChecks == 0)
          #expect(world.clop.requests.isEmpty)
      }

      /// recording-r2:275 (:291), in part: the MP4 half; small-tweaks:15 (:18), the optimised size. With Clop on and
      /// running, an MP4 recording shows `Optimizing…` while Clop works, then uploads Clop's movie, not its own file, and
      /// the row takes the movie's size; `tmp/Clop` is empty afterwards. Stays: recording-r2:275, `cmp` against the
      /// bucket's object and `grep` of the real stderr, by hand; real Clop making the object smaller is the line's
      /// set-up.
      @Test func anMP4RecordingGoesThroughClopShowingOptimizingAndUploadsClopsMovie() async throws {
          defer { world.removeAll() }
          defer { world.clop.release(FakeClop.cancelledAnswer) }
          world.clop.answers = [.hold]
          let coordinator = world.makeCoordinator()
          let record = try addPendingRecording(to: coordinator, byteCount: 3)
          let pending = try #require(record.fileURL)

          coordinator.retryUpload(recordID: record.id)
          try await eventually { world.clop.isHolding }
          #expect(coordinator.optimizingVideoIDs == [record.id])
          #expect(world.cards.calls.contains(.optimizing(record.id, true)))
          #expect(coordinator.history.record(id: record.id)?.uploadState == .uploading(fraction: 0))
          #expect(destination.state.withLock { $0.uploadAttempts } == 0)

          world.clop.release(.smallerMovie(byteCount: 2))
          try await eventually { isUploaded(coordinator, record.id) }
          #expect(coordinator.optimizingVideoIDs.isEmpty)
          #expect(lastOptimizing(record.id) == false)
          let sent = destination.state.withLock { $0.fileUploads.map(\.url) }
          #expect(sent.count == 1)
          #expect(sent.first?.pathExtension == "mp4")
          #expect(sent.first?.lastPathComponent != pending.lastPathComponent)
          #expect(sent.first?.deletingLastPathComponent().lastPathComponent == "Clop")
          #expect(coordinator.history.record(id: record.id)?.byteCount == 2)
          try await eventually { world.clop.workFiles.isEmpty }
      }

      /// recording-r4:255 (:269), its second sentence. Clop's movie at the keep threshold cannot be moved into a
      /// read-only `multipart/`: `Upload: Clop's copy could not be kept for resume: <error>` is logged, the job sends
      /// the throwaway copy from `tmp/Clop` in one PUT, nothing is kept, and `tmp/Clop` is empty afterwards. The first
      /// sentence is `aRecordingOverThePartThresholdKeepsClopsMovieAndARetryResumesWithoutClop`.
      @Test func aClopMovieThatCannotBeKeptForResumeLogsItAndSendsTheThrowawayCopy() async throws {
          defer { world.removeAll() }
          // A lane threshold above Clop's movie, so the job is one PUT and writes no sidecar.
          world.multipartPlan = MultipartPlan(threshold: 1_073_741_824, partSize: 16_777_216, inFlight: 1)
          world.clop.answers = [.smallerMovie(byteCount: threshold)]
          let coordinator = world.makeCoordinator()
          let record = try addPendingRecording(to: coordinator, byteCount: 2 * threshold)
          let keptCopy = coordinator.multipartFiles.keptCopyURL(for: record.id, ext: "mp4")
          let multipart = coordinator.multipartFiles.directory
          try FileManager.default.createDirectory(at: multipart, withIntermediateDirectories: true)
          let multipartPath = multipart.path(percentEncoded: false)
          try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: multipartPath)
          defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: multipartPath) }

          coordinator.retryUpload(recordID: record.id)
          try await eventually { isUploaded(coordinator, record.id) }

          let prefix = "Upload: Clop's copy could not be kept for resume: "
          let line = try #require(world.logLines.first { $0.hasPrefix(prefix) })
          #expect(line.count > prefix.count)
          let sent = destination.state.withLock { $0.fileUploads.map(\.url) }
          #expect(sent.count == 1)
          #expect(sent.first?.deletingLastPathComponent().lastPathComponent == "Clop")
          #expect(destination.state.withLock { $0.creates }.isEmpty)
          #expect(!exists(keptCopy))
          #expect(coordinator.history.record(id: record.id)?.byteCount == Int(threshold))
          #expect(coordinator.history.record(id: record.id)?.multipart == nil)
          try await eventually { world.clop.workFiles.isEmpty }
      }
  }
  ```

#### The three tests in existing suites (catalogue CLOP.4)

- [ ] In `TidyShotTests/CoordinatorTrimTests.swift`, add T16 before the closing `}` of `struct CoordinatorTrimTests`,
  after `aCaptureBeingTrimmedRefusesDeleteAndUploadTrimmed`. Replace the end of the file (:130-133):
  ```swift
          #expect(coordinator.history.record(id: trimmed.id) == trimmed)
          #expect(world.factory.askedConfigs.isEmpty)
      }
  }
  ```
  with:
  ```swift
          #expect(coordinator.history.record(id: trimmed.id) == trimmed)
          #expect(world.factory.askedConfigs.isEmpty)
      }

      /// recording-r4:253 (:267), in part. With Clop on, `Upload Trimmed` of a trimmed recording over 100 MiB sends
      /// Clop's movie in parts and keeps it in `multipart/` for resume; the PUT fails part way and the link is kept. The
      /// file is trimmed again (written after the stored upload started), and the next `Upload Trimmed` logs `source
      /// changed, starting again`, asks Clop again from the file rather than resuming the kept copy, aborts the stored
      /// upload and completes a new one at the link's key with the second movie's size. Stays: the link playing the
      /// second trim, not the first (CloudFront), by hand. The kept copy's own rule is
      /// `CoordinatorUploadTests.anOutdatedKeptClopCopyCountsAsAChangedSource`.
      @Test func anUploadTrimmedWithClopWhoseFileChangedAsksClopAgainAndSendsTheSecondTrim() async throws {
          defer { world.removeAll() }
          let threshold = MultipartPlan.standard.threshold
          let plusMiB = threshold + 1_048_576
          world.multipartPlan = MultipartPlan(threshold: 1_048_576, partSize: MultipartPlan.maxPartSize, inFlight: 1)
          // The stored upload starts an hour after the trimmed file was written, so its kept copy is current.
          world.date = Date(timeIntervalSinceNow: 3600)
          world.settings.optimiseWithClop = true
          destination.state.withLock { $0.partFailures = [2: [.httpStatus(403, body: "AccessDenied: Access Denied")]] }
          world.clop.answers = [.smallerMovie(byteCount: threshold), .smallerMovie(byteCount: plusMiB)]
          let coordinator = world.makeCoordinator()
          let trimmed = try addTrimmedUpload(to: coordinator, byteCount: 2 * threshold)
          let file = try #require(trimmed.fileURL)
          let keptCopy = coordinator.multipartFiles.keptCopyURL(for: trimmed.id, ext: "mp4")
          let keptCopyPath = keptCopy.path(percentEncoded: false)

          coordinator.uploadTrimmed(recordID: trimmed.id)
          try await eventually {
              world.notifier.calls.contains(.error(title: "Not uploaded",
                                                   message: EditorUploadPlan.failedReplaceRecordingMessage))
          }
          #expect(world.clop.requests == [.video(file, duration: 10)])
          #expect(FileManager.default.fileExists(atPath: keptCopyPath))
          let failed = try #require(coordinator.history.record(id: trimmed.id))
          #expect(failed.multipart?.sourcePath == keptCopyPath)
          #expect(failed.multipart?.byteCount == threshold)
          #expect(failed.uploadState == trimmed.uploadState)
          #expect(failed.uploadIsStale)
          #expect(world.logLines.contains(
              "Upload failed, the earlier link is kept: Part 2 of 2: Server returned HTTP 403: AccessDenied: Access Denied"))

          // Trimmed again: the file is now newer than the stored upload, so the kept copy holds the earlier trim.
          try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSinceNow: 7200)],
                                                ofItemAtPath: file.path(percentEncoded: false))
          coordinator.uploadTrimmed(recordID: trimmed.id)
          try await eventually { coordinator.history.record(id: trimmed.id)?.uploadIsStale == false }

          #expect(world.logLines.contains("Upload: \(file.lastPathComponent) source changed, starting again"))
          #expect(!world.logLines.contains { $0.contains("resumes at") })
          #expect(world.clop.requests == [.video(file, duration: 10), .video(file, duration: 10)])
          #expect(Set(destination.state.withLock { $0.aborts.map(\.uploadID) }) == ["upload-1"])
          #expect(destination.state.withLock { $0.creates.count } == 2)
          #expect(destination.state.withLock { $0.completes.map(\.uploadID) } == ["upload-2"])
          #expect(coordinator.history.record(id: trimmed.id)?.byteCount == Int(plusMiB))
          #expect(coordinator.history.record(id: trimmed.id)?.uploadedKey == "s/REC.mp4")
          try await eventually { !FileManager.default.fileExists(atPath: keptCopyPath) }
      }
  }
  ```
  The 200 MiB source is sparse; its parts are read and digested by `FakeDestination.uploadPart` (FakeDestination.swift:309-349),
  about 200 MiB in all over the two runs. `world.date` an hour ahead is the stored upload's `startedAt`, so the first kept
  copy is current; the touched modification date two hours ahead makes it outdated (`MultipartPlan.keptCopyIsOutdated`,
  MultipartPlan.swift:98-102), and the second run starts over (`.source`, logged as `source changed`, :138).

- [ ] In `TidyShotTests/CoordinatorEditorUploadTests.swift`, add T17 before the closing `}` of
  `struct CoordinatorEditorUploadTests`, after `uploadOfAnUploadOnlyCaptureRemovesItsDragCopyAndEveryReadGivesTheEdit`.
  Replace the end of the file (:936-939):
  ```swift
          #expect(destination.state.withLock { $0.dataDownloadKeys }.isEmpty)
          try await settledEdit(coordinator, id)
      }
  }
  ```
  with:
  ```swift
          #expect(destination.state.withLock { $0.dataDownloadKeys }.isEmpty)
          try await settledEdit(coordinator, id)
      }

      /// phase-7-clop:28 (:30), its editor half (the Retry half is
      /// `CoordinatorClopTests.turningClopOffDuringAnOptimisationKeepsThatUploadOptimisedAndNotTheNext`). With Clop on
      /// and running, the editor's Upload over a save-folder capture's link sends Clop's bytes for the edited file over
      /// the link's own key with `Cache-Control: no-cache`, and the link stays; Upload as New of a second edit sends
      /// Clop's bytes for that file under a new key with no `Cache-Control`. Each request is the file the editor wrote.
      /// Real Clop making each object smaller than the file is line 26.
      @Test func anEditorUploadAndUploadAsNewEachSendClopsBytesAndTheLinkKeepsItsKey() async throws {
          defer { world.removeAll() }
          let folder = try world.storeSaveFolder()
          world.settings.optimiseWithClop = true
          world.clop.answers = [.smaller(Data("r1".utf8)), .smaller(Data("n1".utf8))]
          let coordinator = world.makeCoordinator()
          let (record, _) = try addSavedImage(to: coordinator, in: folder, uploadState: .uploaded(url: link, key: key),
                                              objectLocation: world.location)
          let id = record.id
          let file = try #require(record.fileURL)

          coordinator.openEditor(recordID: id)
          let first = try await openedEditor(id)
          first.draw()
          let replaced = await first.upload()
          #expect(replaced == EditorUploadOutcome(wroteLocally: true, enqueued: true))
          try await eventually { coordinator.history.record(id: id)?.isUploading == false }
          let firstFile = try Data(contentsOf: file)
          try await settledEdit(coordinator, id)
          #expect(world.clop.requests == [.png(firstFile)])
          let replace = try #require(destination.state.withLock { $0.uploads }.first)
          #expect(replace.key == key)
          #expect(replace.data == Data("r1".utf8))
          #expect(replace.cacheControl == "no-cache")
          #expect(coordinator.history.record(id: id)?.uploadState == .uploaded(url: link, key: key))

          world.date = world.date.addingTimeInterval(1)
          coordinator.openEditor(recordID: id)
          let second = try await reopenedEditor(id, after: first)
          second.draw()
          let asNew = await second.upload(asNew: true)
          #expect(asNew == EditorUploadOutcome(wroteLocally: true, enqueued: true))
          try await eventually {
              isUploaded(coordinator, id) && destination.state.withLock { $0.deletedKeys } == [key]
          }
          let secondFile = try Data(contentsOf: file)
          try await settledEdit(coordinator, id)
          #expect(world.clop.requests == [.png(firstFile), .png(secondFile)])
          #expect(world.clop.runningChecks == 2)
          let uploads = destination.state.withLock { $0.uploads }
          try #require(uploads.count == 2)
          #expect(uploads[1].key != key)
          #expect(uploads[1].data == Data("n1".utf8))
          #expect(uploads[1].cacheControl == nil)
      }
  }
  ```
  Both edits reach `applyLocalEdit`, so each ends with `settledEdit`, and `world.date` moves on a second before the
  second edit so its thumbnail gets a new name (design 5). The Upload as New's old key is deleted by
  `deleteSupersededObjects`, which the gate waits for.

- [ ] In `TidyShotTests/CoordinatorSaveTests.swift`, add T18 after `aGIFsSizeIsTheMovedFilesSize` (:372-376).
Replace:
  ```swift
          #expect(record.byteCount == 1_234)
      }

      /// recording-r4 :313 (gap 6). A recording's notices never name the URL command's sender: not its stop notice,
  ```
  with:
  ```swift
          #expect(record.byteCount == 1_234)
      }

      /// small-tweaks:15 (:18), the save half (the optimised size is
      /// `CoordinatorClopTests.anMP4RecordingGoesThroughClopShowingOptimizingAndUploadsClopsMovie`). An MP4's size is
      /// the file's own after its move into the save folder; the row's text from the size is
      /// `RecentCaptureFormattingTests.detailIsTheTimeAndTheSize`.
      @Test func anMP4sSizeIsTheMovedFilesSize() async throws {
          defer { world.removeAll() }
          let folder = try world.storeSaveFolder()
          let coordinator = world.makeCoordinator()
          let recording = try makeRecording(.video, bytes: 1_234)

          let record = try #require(await save(coordinator, recording, CaptureIntent(action: .save)))

          let file = try #require(record.fileURL)
          #expect(isIn(file, folder))
          #expect(file.pathExtension == "mp4")
          #expect(record.mediaKind == .video)
          let size = try FileManager.default.attributesOfItem(atPath: file.path(percentEncoded: false))[.size] as? Int
          #expect(record.byteCount == size)
          #expect(record.byteCount == 1_234)
      }

      /// recording-r4 :313 (gap 6). A recording's notices never name the URL command's sender: not its stop notice,
  ```

#### Runs, the Release build and the commit

- [ ] Run the new suite alone:
  ```bash
  xcodegen generate && xcodebuild test -project TidyShot.xcodeproj -scheme TidyShot -destination 'platform=macOS' -derivedDataPath .build -only-testing:TidyShotTests/CoordinatorClopTests 2>&1 | grep -E "Test run with|error:|TEST"
  ```
  Expected: `✔ Test run with 15 tests in 1 suite passed after …` and `** TEST SUCCEEDED **`. The `error:` lines that
  print are the known noise only (`com.apple.linkd.autoShortcut`, `MDB_MAP_FULL`, and the `iOSSimulator: …
  sharedServiceContextForDeveloperDir:error:` line where CoreSimulator is out of date).

- [ ] Run the three existing suites the task adds to:
  ```bash
  xcodebuild test -project TidyShot.xcodeproj -scheme TidyShot -destination 'platform=macOS' -derivedDataPath .build -only-testing:TidyShotTests/CoordinatorTrimTests -only-testing:TidyShotTests/CoordinatorEditorUploadTests -only-testing:TidyShotTests/CoordinatorSaveTests 2>&1 | grep -E "Test run with|error:|TEST"
  ```
  Expected: `✔ Test run with 30 tests in 3 suites passed after …` and `** TEST SUCCEEDED **`, with the same noise only.

- [ ] Run the full suite:
  ```bash
  xcodegen generate && xcodebuild test -project TidyShot.xcodeproj -scheme TidyShot -destination 'platform=macOS' -derivedDataPath .build 2>&1 | grep -E "Test run with|error:|TEST"
  ```
  Expected: `✔ Test run with 2336 tests in 194 suites passed after …` and `** TEST SUCCEEDED **`. The `error:` lines are
  noise only: `History file could not be read or decoded, setting it aside` twice, `com.apple.linkd.autoShortcut`,
  about 40 `mdb_txn_commit error: MDB_MAP_FULL`, and the `iOSSimulator` line. The run takes 45 s to 130 s. A run that
  fails only on `UploadQueueTests.aSidecarUnwritableDuringThePartsFailsTheJobBeforeComplete` is run once more; any
  other failure is reported, not forced.

- [ ] Run the Release build:
  ```bash
  xcodegen generate && xcodebuild -project TidyShot.xcodeproj -scheme TidyShot -configuration Release -derivedDataPath .build-rel build 2>&1 | grep -E "error:|warning:|BUILD"
  ```
  Expected: `** BUILD SUCCEEDED **`, and no `error:` or `warning:` line from the compiler or the linker. Two tool lines
  may print and are not the change's: `xcodebuild[…] iOSSimulator: [SimServiceContext sharedServiceContextForDeveloperDir:error:] returned nil …`
  and `appintentsmetadataprocessor[…] warning: Metadata extraction skipped, no AppIntents.framework dependency found`.
  Any other line, for example a concurrency warning about `ClopOptimising` in `ClopOptimiser.swift` or
  `AppEnvironment.swift`, is a failure: stop and report it.

- [ ] Assert what changed:
  ```bash
  git diff --stat 30d3c15 -- TidyShot/
  git status --short
  ```
  Expected: the diffstat lists exactly the four files above and ends `4 files changed, 23 insertions(+), 7 deletions(-)`.
  `git status --short` lists ` M TidyShot/App/AppCoordinator+Upload.swift`, ` M TidyShot/App/AppCoordinator.swift`,
  ` M TidyShot/App/AppEnvironment.swift`, ` M TidyShot/Upload/ClopOptimiser.swift`,
  ` M TidyShotTests/CoordinatorEditorUploadTests.swift`, ` M TidyShotTests/CoordinatorSaveTests.swift`,
  ` M TidyShotTests/CoordinatorTrimTests.swift`, ` M TidyShotTests/Support/CoordinatorWorld.swift`,
  `?? TidyShotTests/CoordinatorClopTests.swift` and `?? TidyShotTests/Support/ClopFakes.swift`, and nothing else
  (`TidyShot.xcodeproj`, `.build/` and `.build-rel/` are git-ignored).

- [ ] Commit:
  ```bash
  git add TidyShot/App/AppCoordinator+Upload.swift TidyShot/App/AppCoordinator.swift TidyShot/App/AppEnvironment.swift TidyShot/Upload/ClopOptimiser.swift TidyShotTests/CoordinatorClopTests.swift TidyShotTests/CoordinatorEditorUploadTests.swift TidyShotTests/CoordinatorSaveTests.swift TidyShotTests/CoordinatorTrimTests.swift TidyShotTests/Support/ClopFakes.swift TidyShotTests/Support/CoordinatorWorld.swift
  git commit -m "refactor: Clop through AppEnvironment.clopOptimiser and isClopRunning, FakeClop, the 18 Clop tests"
  ```
  Expected: `10 files changed, 972 insertions(+), 10 deletions(-)`, with `create mode 100644` for the two new files.
  No attribution lines and no session URL in the message; do not push. The report says no hand check was run.

### Task 2: The card's Save As… panel through `AppEnvironment.chooseSaveAsURL`, its fake, eleven Save As tests [integration]

**Files:**
- Modify `TidyShot/App/AppEnvironment.swift`: the member `chooseSaveAsURL` between `makeEditor` (:38-40 at f991760) and `now` (:41); its live value between the `makeEditor:` closure (:76-84) and `now:` (:85); a new `private static func chooseSaveAsURLLive(_:)` before `confirmLive`'s doc comment (:90); `live()`'s doc comment (:48-52 at f991760, as Task 1 leaves it) gains "the card's Save As… panel" (design 2.2, 2.4). Task 1 has added `clopOptimiser` and `isClopRunning` after `freeBytes` and their live values after `freeBytes:`; this task does not touch them.
- Modify `TidyShot/App/AppCoordinator+RecordActions.swift`: `askSaveAsTarget`'s doc comment and its panel lines (:191-201) (design 2.2). Nothing else in the file changes; it keeps `import AppKit` (`NSWorkspace` at :60, :71, :275).
- Modify `TidyShotTests/Support/CoordinatorFakes.swift`: `final class FakeSaveAsChooser` after `FakeConfirm` (whose closing `}` is :221), before `FakeDestinationFactory`'s doc comment (:223) (design 3.2).
- Modify `TidyShotTests/Support/FakeDestination.swift`: `State.fileDownloads` after `dataDownloadFailures` (:106-107); `download(key:to:)` (:171) records and writes (design 3.2).
- Modify `TidyShotTests/Support/CoordinatorWorld.swift`: the type's doc comment (:11-15 at f991760, as Task 1 leaves it) names the card's Save As… panel; `let saveAsChooser = FakeSaveAsChooser()` before the clock's doc comment (:45), so after Task 1's `clop`; `let saveAsChooser = saveAsChooser` before `return AppEnvironment(` (:113); `chooseSaveAsURL:` after the `makeEditor:` closure (:128-131) and before `now:` (:132) (design 3.4).
- Modify `TidyShotTests/CoordinatorWorldTests.swift`: `#expect(world.clop.runningChecks == 0)`, `#expect(world.clop.requests.isEmpty)` and `#expect(world.saveAsChooser.asked.isEmpty)` after `#expect(world.logLines.isEmpty)` (:31) (design 3.4).
- Create `TidyShotTests/CoordinatorSaveAsTests.swift` (catalogue SAVEAS.2 and SAVEAS.3, whole).
- Modify `TidyShotTests/CoordinatorEditorSaveTests.swift`: test 9 after `saveOverTheFileRemovesTheDragCopyAndEveryReadGivesTheEdit` (its closing `}` at :533), before the doc comment of `saveAsOnAnUploadOnlyCaptureWritesThePNGAndUploadsNothing` (:535) (catalogue SAVEAS.5).
- Modify `TidyShotTests/CoordinatorEditorUploadTests.swift`: test 10 right after `uploadOfAnUploadOnlyCaptureRemovesItsDragCopyAndEveryReadGivesTheEdit` (its closing `}` at :938 at f991760), whatever follows it after Task 1 (catalogue SAVEAS.5).

**Interfaces:**
- Consumes, production (at f991760):
  - `func saveAs(recordID: UUID)` (`AppCoordinator+RecordActions.swift:111`): returns at once; the work runs through `afterMenuTracking` (:280-284) in an unstored `Task` (:116, :118).
  - `func saveVideoCopy(recordID: UUID) async` (:130), internal; it awaits `downloadingDragIDs[recordID]` (:132-134).
  - `private func askSaveAsTarget(recordID: UUID) async -> (record: CaptureRecord, url: URL)?` (:195), stays private; its record check (:196) and re-read with `log("Save As: \(recordID) was deleted while the panel was open")` (:202-205) stay.
  - `func saveAsSuggestion(recordID: UUID) -> EditorNaming.SaveAsSuggestion` (:321), unchanged.
  - `func imageData(of record: CaptureRecord, downloadTitle: String = "Copying image…") async throws -> Data` (:215); `func downloadSource(of record: CaptureRecord, title: String?) throws -> (key: String, destination: any Destination)` (:263); `private func performSaveAs(to url: URL, _ write: () async throws -> Void) async -> Bool` (:303).
  - `nonisolated enum EditorNaming` with `struct SaveAsSuggestion: Equatable, Sendable { var fileName: String; var directory: URL?; var mediaKind: MediaKind = .image }` (`TidyShot/Editor/Persistence/EditorNaming.swift:5-13`) and `@MainActor static func savePanel(for suggestion: SaveAsSuggestion) -> NSSavePanel` (:39-40).
  - `AppCoordinator`: `let environment: AppEnvironment` (AppCoordinator.swift:14), `var lastCaptureURL: URL?` (:81), `@ObservationIgnored var closedOverlays = ClosedOverlays()` (:143), `let pendingFiles: PendingFileStore` (:21), `let dragFiles: DragFileStore` (:25); `func retryUpload(recordID: UUID)` (+Upload.swift:462); `func prepareDragFile(recordID: UUID)` (+DragOut.swift:14); `func downloadDragFile(recordID: UUID)` (+DragOut.swift:98); `func openEditor(recordID: UUID)` (+Editor.swift:15).
  - `HistoryStore`: `func add(_ record: CaptureRecord)` (:66), `func record(id: UUID) -> CaptureRecord?` (:87), `func remove(id: UUID)` (:122). `PendingFileStore.write(_ data: Data, id: UUID, ext: String) throws -> URL` (:21). `DragFileStore.folder(for id: UUID) -> URL` (:24), `stagedFile(id: UUID) -> URL?` (:39). `ClosedOverlays.ids: [UUID]` (`private(set)`, ClosedOverlays.swift:8).
  - `CaptureRecord.init(id: UUID = UUID(), timestamp: Date = Date(), fileURL: URL?, fileIsTemporary: Bool = false, thumbnailFileName: String? = nil, pixelWidth: Int, pixelHeight: Int, appName: String?, uploadState: UploadState = .none, objectLocation: ObjectLocation? = nil, …, mediaKind: MediaKind = .image, durationSeconds: Double? = nil, byteCount: Int? = nil, …)` (CaptureRecord.swift:114-120); `var uploadedKey: String?` (:191), `var isTimeBased: Bool` (:243), `var isUploading: Bool` (:267).
  - `AppSettings`: `var showNotification: Bool` (:93), `var fileNameTemplate: String` (:98), `var currentCounter: Int` (:461), `func nextCounter() -> Int` (:466, not `@discardableResult`).
- Consumes, the harness (at f991760; Task 1 adds `clop` to the world and does not change these): `CoordinatorWorld` (`root` :26, `historyFileURL` :28, `settings` :33, `saveLocation` :34, `notifier` :39, `cards` :40, `clipboard` :41, `editors` :44, `clock` :46, `factory` :47, `location` :93, `logLines` :106, `makeCoordinator()` :139, `removeAll()` :149, `@discardableResult func storeSaveFolder() throws -> URL` :158-159, `static func pngData(width: Int, height: Int) throws -> Data` :188); `func eventually(_ condition: () async -> Bool) async throws` (UploadQueueTests.swift:42; 200 polls of 10 ms); `final class SingleWaiter<Value: Sendable>` with `init(cancelled: Value, secondEntry: String)`, `var isWaiting: Bool`, `func wait() async -> Value`, `func resume(_ value: Value)` (CoordinatorFakes.swift:377-416); `final class TaskWatch` with `init<Success: Sendable>(_ task: Task<Success, Never>)` and `private(set) var hasReturned: Bool` (:422-431); `FakeNotifier.Call` (`case saved(title: String, file: String)`, `case error(title: String, message: String, subtitle: String? = nil)`, `case notice(title: String, body: String, subtitle: String? = nil)`, :9-18) and `private(set) var calls: [Call]` (:20); `FakeCards` (`private(set) var calls: [Call]` :86, `var showing: Set<UUID>` :88, `func close(recordID: UUID, reason: QuickAccessCloseReason)` :111-115, `func dragFiles(for id: UUID) -> [URL?]` :130, `var closes: [QuickAccessCloseReason]` :146); `FakeClipboard.copies` (:167); `FakeDestinationFactory.standard` (:232), `askedConfigs` (:241); `FakeDestination.State` (`holdingUploadsRemaining` :26, `heldUploads` :28, `downloadOutcome: DownloadOutcome` :91, `downloads: [(key: String, resumeData: Data?)]` :94, `holdsDownloads` :97, `downloadedData` :104, `dataDownloadKeys` :105, `dataDownloadFailures: [any Error & Sendable]` :107), `func releaseDownloads()` (:204), `func releaseUploads(throwing error: (any Error)? = nil)` (:256); `FakeScrollClock.run(for duration: Duration) async throws` (ScrollSessionFakes.swift:119); `FakeEditor` (`func draw()`, `@discardableResult func save() async -> Bool`, `@discardableResult func upload(asNew: Bool = false) async -> EditorUploadOutcome`, EditorFakes.swift:103-150); `EditorPixels.isBlue(png: Data) throws -> Bool` (EditorPixels.swift:86); the CT-2 suites' own helpers, unchanged: in `CoordinatorEditorSaveTests` `destination` (:18), `openedEditor(_:)` (:25), `settledEdit(_:_:)` (:37), `addSavedImage(to:in:name:uploadState:objectLocation:uploadIsStale:timestamp:scale:) throws -> (record: CaptureRecord, original: Data)` (:44-55), `desktop(_:) throws -> URL` (:71), `exists(_:)` (:102); in `CoordinatorEditorUploadTests` `destination` (:17), `publicURL(_:)` (:21), `openedEditor(_:)` (:23), `settledEdit(_:_:)` (:34), `addPendingImage(to:) throws -> CaptureRecord` (:54), `desktop(_:)` (:65), `pendingURL(_:_:) -> URL` (:71).
- Produces, production:
  ```swift
  // AppEnvironment, after makeEditor
  /// A card's Save As… panel: a place for the suggestion, or nil for Cancel.
  var chooseSaveAsURL: @MainActor (EditorNaming.SaveAsSuggestion) async -> URL?
  // live(): chooseSaveAsURL: { await AppEnvironment.chooseSaveAsURLLive($0) },
  private static func chooseSaveAsURLLive(_ suggestion: EditorNaming.SaveAsSuggestion) async -> URL?
  ```
  `AppEnvironment` takes it as a labelled memberwise argument, in member order between `makeEditor:` and `now:`, at its two construction sites, `live()` and `CoordinatorWorld.environment`. Task 3 adds `recordingLog` after `log`, last.
- Produces, the harness (Task 3 and Task 4 rely on these names):
  ```swift
  final class FakeSaveAsChooser {
      private(set) var asked: [EditorNaming.SaveAsSuggestion]
      var answers: [URL?]          // nil is Cancel; Cancel when empty
      var holds: Bool
      var isWaiting: Bool { get }
      func choose(_ suggestion: EditorNaming.SaveAsSuggestion) async -> URL?
      func answer(_ url: URL?)
  }
  // CoordinatorWorld
  let saveAsChooser: FakeSaveAsChooser
  // FakeDestination.State
  var fileDownloads: [(key: String, file: URL)]
  ```
  `FakeDestination.download(key: String, to destination: URL) async throws` keeps its signature; it now appends `(key, destination)` to `fileDownloads` and writes `downloadedData` to the file atomically.
- Produces, `CoordinatorSaveAsTests`' helpers (file-local): `let key = "s/SHOT.png"`, `let videoKey = "s/2026/rec.mp4"`, `var destination: FakeDestination`, `var chooser: FakeSaveAsChooser`, `func publicURL(_ key: String) -> URL`, `func exists(_ url: URL) -> Bool`, `func desktop(_ name: String) throws -> URL`, `func notices(after count: Int) -> [FakeNotifier.Call]`, `var postedDownloading: Bool`, `func addSavedImage(to coordinator: AppCoordinator, in folder: URL, name: String = "Shot.png", width: Int = 4) throws -> (record: CaptureRecord, original: Data)`, `func addPendingImage(to coordinator: AppCoordinator, width: Int = 4) throws -> CaptureRecord`, `func addUploadOnly(to coordinator: AppCoordinator, bytes: Data) -> CaptureRecord`, `func uploadWithItsCardShowing(_ coordinator: AppCoordinator) async throws -> (record: CaptureRecord, key: String, png: Data)`, `func addUploadedRecording(to coordinator: AppCoordinator, kind: MediaKind = .video) -> CaptureRecord`.

**Tests** (catalogue `docs/superpowers/notes/2026-10-31-small-seams/tests-small.md`, section 4):
1. `saveAsOfASavedImageCopiesItsBytesAndChangesNothingElse`: SAVEAS.3, tests-small.md:582; effort M.
2. `anUploadOnlyCapturesSaveAsSuggestsTheTemplateNameAndCopiesItsPendingFile`: SAVEAS.3, tests-small.md:628; effort M.
3. `anUploadOnlyCardsSaveAsWritesTheDragCopyOrDownloadsAfterThePanel`: SAVEAS.3, tests-small.md:660; effort L.
4. `aRecordingsSaveAsDuringItsDragOutDownloadWaitsAndCopiesTheLandedFile`: SAVEAS.3, tests-small.md:700; effort M.
5. `aSaveAsPanelHeldThroughTheCardsAutoCloseStillSaves`: SAVEAS.3, tests-small.md:725; effort M.
6. `saveAsFromAnyCardWritesThatCardsCapture`: SAVEAS.3, tests-small.md:749; effort S.
7. `anUploadOnlyVideosSaveAsDownloadsToTheChosenFile`: SAVEAS.3, tests-small.md:765; effort S.
8. `aGIFsSaveAsWritesTheGIFOverAnExistingFileToo`: SAVEAS.3, tests-small.md:784; effort S.
9. `aSaveAsWhoseCaptureIsDeletedWhileThePanelIsUpWritesNothingAndLogsIt` (E1, no line): SAVEAS.3, tests-small.md:807; effort S.
10. `saveAsAfterASaveOverTheFileWritesTheEditNotTheOriginal` (SAVEAS 9, in `CoordinatorEditorSaveTests`): SAVEAS.5, tests-small.md:845; effort M.
11. `saveAsAfterAnEditorUploadOfAnUploadOnlyCaptureWritesTheEditDuringAndAfterThePut` (SAVEAS 10, in `CoordinatorEditorUploadTests`): SAVEAS.5, tests-small.md:862; effort M.
- 11 tests (S 4, M 6, L 1), none parameterized; one new suite file. `CoordinatorWorldTests.aCoordinatorOverTheWorldKeepsToTheWorld` gains one check, not a test.
- Focused run, the four suites this task touches: `Test run with 44 tests in 4 suites passed` (`CoordinatorSaveAsTests` 9, `CoordinatorEditorSaveTests` 17 + 1, `CoordinatorEditorUploadTests` 14 + Task 1's T17 + 1, `CoordinatorWorldTests` 1).
- Full suite: `Test run with 2347 tests in 195 suites passed` (Task 1's 2336 in 194, plus 11 tests and 1 suite).
- Also: `git diff --stat HEAD -- TidyShot/` (against Task 1's commit) lists exactly `TidyShot/App/AppCoordinator+RecordActions.swift` and `TidyShot/App/AppEnvironment.swift`, and `git diff --numstat HEAD -- TidyShot/App/AppCoordinator+RecordActions.swift` reads `6	9`. The Release build prints `** BUILD SUCCEEDED **` and no `error:` or `warning:` line beyond the two tool lines the Global Constraints name.

**Commit:** `refactor: the card's Save As panel through AppEnvironment.chooseSaveAsURL, its fake, eleven Save As tests`

**Steps:**

- [ ] Check the starting point. From the repository root:
  ```bash
  git branch --show-current
  git status --short -- TidyShot TidyShotTests
  grep -c "isClopRunning" TidyShot/App/AppEnvironment.swift
  grep -c "chooseSaveAsURL\|FakeSaveAsChooser\|saveAsChooser\|fileDownloads" TidyShot/App/AppEnvironment.swift TidyShotTests/Support/CoordinatorFakes.swift TidyShotTests/Support/CoordinatorWorld.swift TidyShotTests/Support/FakeDestination.swift
  test -e TidyShotTests/CoordinatorSaveAsTests.swift && echo exists || echo absent
  ```
  Expected: `small-seams`; nothing (Task 1 is committed); `2` (Task 1's member and live value); each of the four files `:0`; `absent`.

- [ ] Check that every anchor this task replaces occurs once:
  ```bash
  grep -c "_ onClose: @escaping @MainActor (any EditorPresenting) -> Void) -> any EditorPresenting" TidyShot/App/AppEnvironment.swift
  grep -c "controller.onClose = { closed in onClose(closed) }" TidyShot/App/AppEnvironment.swift
  grep -c "/// Delete's alerts as \`AppCoordinator+Delete.swift\` ran them." TidyShot/App/AppEnvironment.swift
  grep -c "/// What the app runs on:" TidyShot/App/AppEnvironment.swift
  grep -c "let panel = EditorNaming.savePanel(for: saveAsSuggestion(recordID: recordID))" TidyShot/App/AppCoordinator+RecordActions.swift
  grep -c "/// Answers the held question; later ones come from \`answers\`." TidyShotTests/Support/CoordinatorFakes.swift
  grep -c "var dataDownloadFailures: \[any Error & Sendable\] = \[\]" TidyShotTests/Support/FakeDestination.swift
  grep -c "func download(key: String, to destination: URL) async throws {}" TidyShotTests/Support/FakeDestination.swift
  grep -c "/// The coordinator's clock, and its self-timer's." TidyShotTests/Support/CoordinatorWorld.swift
  grep -c "        return AppEnvironment(" TidyShotTests/Support/CoordinatorWorld.swift
  grep -c "                             onClose: onClose)" TidyShotTests/Support/CoordinatorWorld.swift
  grep -c "/// A coordinator's world in the suite (harness design 2.4):" TidyShotTests/Support/CoordinatorWorld.swift
  grep -c "#expect(world.logLines.isEmpty)" TidyShotTests/CoordinatorWorldTests.swift
  grep -c "/// phase-4a:97 (:146), in part." TidyShotTests/CoordinatorEditorSaveTests.swift
  grep -c "let again = try #require(world.editors.editor(for: id))" TidyShotTests/CoordinatorEditorUploadTests.swift
  ```
  Expected: `1` fifteen times. Any other count means an earlier task left the region differently: stop and report it.

#### The seam (design 2.2)

- [ ] In `TidyShot/App/AppEnvironment.swift`, add the member after `makeEditor`. Replace:
  ```swift
                                  _ onClose: @escaping @MainActor (any EditorPresenting) -> Void) -> any EditorPresenting
      var now: @Sendable () -> Date
  ```
  with:
  ```swift
                                  _ onClose: @escaping @MainActor (any EditorPresenting) -> Void) -> any EditorPresenting
      /// A card's Save As… panel: a place for the suggestion, or nil for Cancel.
      var chooseSaveAsURL: @MainActor (EditorNaming.SaveAsSuggestion) async -> URL?
      var now: @Sendable () -> Date
  ```

- [ ] In the same file, add the live value after the `makeEditor:` closure in `live()`. Replace:
  ```swift
                  controller.onClose = { closed in onClose(closed) }
                  return controller
              },
              now: { Date() },
  ```
  with:
  ```swift
                  controller.onClose = { closed in onClose(closed) }
                  return controller
              },
              chooseSaveAsURL: { await AppEnvironment.chooseSaveAsURLLive($0) },
              now: { Date() },
  ```

- [ ] In the same file, add the live body after `live()` and before `confirmLive`. Replace:
  ```swift
      /// Delete's alerts as `AppCoordinator+Delete.swift` ran them.
  ```
  with:
  ```swift
      /// The card's Save As… panel as `askSaveAsTarget` ran it: the panel for the suggestion
      /// (`EditorNaming.savePanel(for:)`), the app activated, then the panel as a window (`begin()`,
      /// not a sheet). Nil when it was cancelled.
      private static func chooseSaveAsURLLive(_ suggestion: EditorNaming.SaveAsSuggestion) async -> URL? {
          let panel = EditorNaming.savePanel(for: suggestion)
          // Reached from a non-activating card while another app is active; a plain activate() can
          // be refused and the panel would open behind that app (as in SaveLocation.chooseFolder).
          NSApplication.shared.activate(ignoringOtherApps: true)
          guard await panel.begin() == .OK else { return nil }
          return panel.url
      }

      /// Delete's alerts as `AppCoordinator+Delete.swift` ran them.
  ```
  The body is RA:197-201 moved: the same panel from the same suggestion, the same activation, `panel.url` read only after `.OK`. `AppEnvironment.swift` already imports AppKit (:1).

- [ ] In `TidyShot/App/AppCoordinator+RecordActions.swift`, replace `askSaveAsTarget`'s doc comment and its panel lines (:191-201):
  ```swift
      /// A card's Save As… panel, for an image and for a recording: activates the app and asks for a
      /// place with the record's suggestion (`EditorNaming.savePanel(for:)`). Then the record is read
      /// again, since the upload may have finished, or the capture been deleted, while the panel was
      /// open. Nil when the panel was cancelled or the capture is gone.
      private func askSaveAsTarget(recordID: UUID) async -> (record: CaptureRecord, url: URL)? {
          guard history.record(id: recordID) != nil else { return nil }
          let panel = EditorNaming.savePanel(for: saveAsSuggestion(recordID: recordID))
          // Reached from a non-activating card while another app is active; a plain activate() can
          // be refused and the panel would open behind that app (as in SaveLocation.chooseFolder).
          NSApplication.shared.activate(ignoringOtherApps: true)
          guard await panel.begin() == .OK, let url = panel.url else { return nil }
  ```
  with:
  ```swift
      /// A card's Save As… panel, for an image and for a recording: asks for a place with the record's
      /// suggestion (`environment.chooseSaveAsURL`, which activates the app and shows
      /// `EditorNaming.savePanel(for:)`). Then the record is read again, since the upload may have
      /// finished, or the capture been deleted, while the panel was open. Nil when the panel was
      /// cancelled or the capture is gone.
      private func askSaveAsTarget(recordID: UUID) async -> (record: CaptureRecord, url: URL)? {
          guard history.record(id: recordID) != nil else { return nil }
          guard let url = await environment.chooseSaveAsURL(saveAsSuggestion(recordID: recordID)) else { return nil }
  ```
  The re-read and its log line that follow (:202-206) are unchanged.

#### The fakes and the world (design 3.2, 3.4)

- [ ] In `TidyShotTests/Support/CoordinatorFakes.swift`, add the chooser after `FakeConfirm`. Replace:
  ```swift
      /// Answers the held question; later ones come from `answers`.
      func answer(_ yes: Bool) {
          holds = false
          held.resume(yes)
      }
  }
  ```
  with:
  ```swift
      /// Answers the held question; later ones come from `answers`.
      func answer(_ yes: Bool) {
          holds = false
          held.resume(yes)
      }
  }

  /// A card's Save As… panel in the suite (`environment.chooseSaveAsURL`): no panel is built and the app
  /// is never activated. Every suggestion is kept, in order; each is answered from `answers` (a URL, or
  /// nil for Cancel; Cancel when they run out), or held until `answer(_:)` while `holds` is set. A held
  /// panel whose task is cancelled answers Cancel; a second panel while one is held records an issue.
  final class FakeSaveAsChooser {
      private(set) var asked: [EditorNaming.SaveAsSuggestion] = []
      var answers: [URL?] = []
      var holds = false
      private let held = SingleWaiter<URL?>(cancelled: nil,
                                            secondEntry: "FakeSaveAsChooser was asked again while a panel was held")

      var isWaiting: Bool { held.isWaiting }

      func choose(_ suggestion: EditorNaming.SaveAsSuggestion) async -> URL? {
          asked.append(suggestion)
          guard holds else { return answers.isEmpty ? nil : answers.removeFirst() }
          return await held.wait()
      }

      /// Answers the held panel (nil: Cancel); later ones come from `answers`.
      func answer(_ url: URL?) {
          holds = false
          held.resume(url)
      }
  }
  ```

- [ ] In `TidyShotTests/Support/FakeDestination.swift`, add the field. Replace:
  ```swift
          /// Errors for `download(key:)`, one per call, in order; then it returns `downloadedData`.
          var dataDownloadFailures: [any Error & Sendable] = []
  ```
  with:
  ```swift
          /// Errors for `download(key:)`, one per call, in order; then it returns `downloadedData`.
          var dataDownloadFailures: [any Error & Sendable] = []
          /// Each `download(key:to:)` (a recording's Save As…, Trim): its key and file, in order.
          var fileDownloads: [(key: String, file: URL)] = []
  ```

- [ ] In the same file, make `download(key:to:)` record and write. Replace:
  ```swift
      func download(key: String, to destination: URL) async throws {}
  ```
  with:
  ```swift
      func download(key: String, to destination: URL) async throws {
          let data = state.withLock { state -> Data in
              state.fileDownloads.append((key, destination))
              return state.downloadedData
          }
          try data.write(to: destination, options: .atomic)
      }
  ```
  Its callers are `saveVideoCopy` (RA:150-152) and Trim's download (`AppCoordinator+Trim.swift:68`), which no test reaches.

- [ ] In `TidyShotTests/Support/CoordinatorWorld.swift`, add the chooser after Task 1's `clop`. Replace:
  ```swift
      /// The coordinator's clock, and its self-timer's.
      let clock = FakeScrollClock()
  ```
  with:
  ```swift
      /// The card's Save As… panel (`environment.chooseSaveAsURL`); no panel is built.
      let saveAsChooser = FakeSaveAsChooser()
      /// The coordinator's clock, and its self-timer's.
      let clock = FakeScrollClock()
  ```

- [ ] In the same file, bind the local in `environment`. Replace:
  ```swift
          return AppEnvironment(
              historyFileURL: historyFileURL,
  ```
  with:
  ```swift
          let saveAsChooser = saveAsChooser
          return AppEnvironment(
              historyFileURL: historyFileURL,
  ```

- [ ] In the same file, pass it after the `makeEditor:` closure. Replace:
  ```swift
                               onClose: onClose)
              },
              now: { state.date },
  ```
  with:
  ```swift
                               onClose: onClose)
              },
              chooseSaveAsURL: { suggestion in await saveAsChooser.choose(suggestion) },
              now: { state.date },
  ```

- [ ] Reword the two doc comments that Task 1 also reworded: `live()`'s (design 2.4) and the world's type doc (design 3.4). Task 1's wording is replaced whole, between fixed bounds, so this step does not depend on how Task 1 wrapped it. From the repository root:
  ```bash
  python3 - <<'PY'
  from pathlib import Path

  def replace_block(path, start, end, new):
      p = Path(path)
      text = p.read_text()
      assert text.count(start) == 1, (path, "start", text.count(start))
      assert text.count(end) == 1, (path, "end", text.count(end))
      i = text.index(start)
      j = text.index(end)
      assert i < j, (path, "order")
      old = text[i:j]
      assert "Save As" not in old, (path, "already reworded", old)
      p.write_text(text[:i] + new + text[j:])
      print(f"{path}: replaced {old.count(chr(10))} lines with {new.count(chr(10))}")
      print(old, end="")

  replace_block(
      "TidyShot/App/AppEnvironment.swift",
      "    /// What the app runs on: the user's Application Support folder",
      "    static func live() -> AppEnvironment {\n",
      "    /// What the app runs on: the user's Application Support folder (the temporary folder when it\n"
      "    /// cannot be had), the shared settings, the Keychain, the notification centre, the card stack,\n"
      "    /// the general pasteboard, S3, Clop, the alerts, the shutter sound, the editor window, the card's\n"
      "    /// Save As… panel, the wall clock and `NSLog`. The collaborators are built in the order the\n"
      "    /// coordinator's stored properties built them; Clop's optimiser, a value that reaches nothing\n"
      "    /// until a request, is built here.\n")

  replace_block(
      "TidyShotTests/Support/CoordinatorWorld.swift",
      "/// A coordinator's world in the suite (harness design 2.4):",
      "/// Nothing here reaches the system, except",
      "/// A coordinator's world in the suite (harness design 2.4): temp folders, a `UserDefaults` suite named\n"
      "/// after the test, settings and a save location over it, credentials in memory, the fakes, the editors\n"
      "/// the coordinator opens (`editors`; no window is built), Clop (`clop`, over `<root>/tmp/Clop`), the card's\n"
      "/// Save As… panel (`saveAsChooser`; none is built), a clock the test moves, a date it sets, free space it\n"
      "/// sets, a log it reads and a destination factory. Build it in the suite's `init`, make the coordinator\n"
      "/// with `makeCoordinator()`, and `defer { world.removeAll() }` first thing in each test.\n")
  PY
  ```
  Expected: `TidyShot/App/AppEnvironment.swift: replaced <n> lines with 6`, then Task 1's block as it stood, then `TidyShotTests/Support/CoordinatorWorld.swift: replaced <m> lines with 6`, then Task 1's block. No `AssertionError`. Then `grep -c "Save As… panel" TidyShot/App/AppEnvironment.swift TidyShotTests/Support/CoordinatorWorld.swift` prints `TidyShot/App/AppEnvironment.swift:3` (this doc, the member's and `chooseSaveAsURLLive`'s) and `TidyShotTests/Support/CoordinatorWorld.swift:2` (the type doc and the `saveAsChooser` doc).

- [ ] In `TidyShotTests/CoordinatorWorldTests.swift`, building a coordinator asks the panel nothing. Replace:
  ```swift
          #expect(world.logLines.isEmpty)
  ```
  with:
  ```swift
          #expect(world.logLines.isEmpty)
          #expect(world.clop.runningChecks == 0)
          #expect(world.clop.requests.isEmpty)
          #expect(world.saveAsChooser.asked.isEmpty)
  ```
  The two `world.clop` checks are design 3.4's for Task 1's fake; Task 1 left them to this task, which owns the file.

- [ ] Build once to catch a mistake before the tests: `xcodegen generate && xcodebuild build-for-testing -project TidyShot.xcodeproj -scheme TidyShot -destination 'platform=macOS' -derivedDataPath .build 2>&1 | grep -E "error:|warning:|BUILD"`. Expected: `** TEST BUILD SUCCEEDED **`, and no `error:` or `warning:` line in `TidyShot/` or `TidyShotTests/` (the tool lines the Global Constraints name may print).

#### The new suite (catalogue SAVEAS.2, SAVEAS.3)

- [ ] Create `TidyShotTests/CoordinatorSaveAsTests.swift`:
  ```swift
  import Foundation
  import Testing
  @testable import TidyShot

  /// A card's Save As… on a built coordinator (`saveAs(recordID:)` and `saveVideoCopy(recordID:)`): what the panel is
  /// asked, what is written where, and what is posted. The panel is `environment.chooseSaveAsURL`, here
  /// `world.saveAsChooser`; no panel is built and the app is never activated. `saveAs` runs its work in a task it does
  /// not return (`afterMenuTracking`), so a test gates on what it asks, writes or posts (`eventually`); a recording's
  /// `saveVideoCopy` runs in the test's own task, watched with `TaskWatch` and cancelled in a `defer`. A held panel is
  /// answered Cancel in a `defer` declared right after the world's, which is what ends it if the test throws.
  @Suite(.timeLimit(.minutes(1)))
  struct CoordinatorSaveAsTests {
      let world: CoordinatorWorld
      let key = "s/SHOT.png"
      let videoKey = "s/2026/rec.mp4"

      init() throws {
          world = try CoordinatorWorld()
      }

      var destination: FakeDestination { world.factory.standard }
      var chooser: FakeSaveAsChooser { world.saveAsChooser }

      /// The public URL of a key (`FakeDestination.publicURL(for:)`).
      func publicURL(_ key: String) -> URL { URL(string: "https://snap.tky.io/\(key)")! }

      func exists(_ url: URL) -> Bool { FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) }

      /// `<root>/Desktop/<name>`, its folder made: the URL a save panel would return.
      func desktop(_ name: String) throws -> URL {
          let folder = world.root.appending(path: "Desktop", directoryHint: .isDirectory)
          try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
          return folder.appending(path: name)
      }

      /// The notifier's calls after the first `count`.
      func notices(after count: Int) -> [FakeNotifier.Call] {
          Array(world.notifier.calls.dropFirst(count))
      }

      /// Whether any notice so far said `Downloading <key>`.
      var postedDownloading: Bool {
          world.notifier.calls.contains {
              if case .notice(_, let body, _) = $0 { return body.hasPrefix("Downloading ") } else { return false }
          }
      }

      /// A PNG of `width` by 2 pixels named `name` in `folder`, never uploaded, added to history.
      func addSavedImage(to coordinator: AppCoordinator, in folder: URL, name: String = "Shot.png",
                         width: Int = 4) throws -> (record: CaptureRecord, original: Data) {
          let original = try CoordinatorWorld.pngData(width: width, height: 2)
          let file = folder.appending(path: name)
          try original.write(to: file)
          let record = CaptureRecord(fileURL: file, pixelWidth: width, pixelHeight: 2, appName: nil,
                                     byteCount: original.count)
          coordinator.history.add(record)
          return (record, original)
      }

      /// A PNG of `width` by 2 pixels in `pending/` whose upload failed (`Retry  Save As…`), added to history.
      func addPendingImage(to coordinator: AppCoordinator, width: Int = 4) throws -> CaptureRecord {
          let id = UUID()
          let png = try CoordinatorWorld.pngData(width: width, height: 2)
          let url = try coordinator.pendingFiles.write(png, id: id, ext: "png")
          let record = CaptureRecord(id: id, fileURL: url, fileIsTemporary: true, pixelWidth: width, pixelHeight: 2,
                                     appName: nil, uploadState: .failed(message: "Upload was interrupted."),
                                     byteCount: png.count)
          coordinator.history.add(record)
          return record
      }

      /// An uploaded upload-only image under `key` with no local file and no drag copy, at the world's
      /// location; its download gives `bytes`.
      func addUploadOnly(to coordinator: AppCoordinator, bytes: Data) -> CaptureRecord {
          destination.state.withLock { $0.downloadedData = bytes }
          let record = CaptureRecord(fileURL: nil, pixelWidth: 6, pixelHeight: 2, appName: nil,
                                     uploadState: .uploaded(url: publicURL(key), key: key), objectLocation: world.location)
          coordinator.history.add(record)
          return record
      }

      /// An upload-only capture uploaded while its card shows: the pending file has moved to `Drag/<id>/` and the
      /// record has no `fileURL` (`keepForDragOut`). The record as it is now, its key and its bytes.
      func uploadWithItsCardShowing(_ coordinator: AppCoordinator) async throws
          -> (record: CaptureRecord, key: String, png: Data) {
          let record = try addPendingImage(to: coordinator)
          let id = record.id
          let png = try Data(contentsOf: try #require(record.fileURL))
          world.cards.showing.insert(id)
          coordinator.retryUpload(recordID: id)
          try await eventually { coordinator.history.record(id: id)?.uploadedKey != nil }
          let current = try #require(coordinator.history.record(id: id))
          #expect(current.fileURL == nil)
          #expect(coordinator.dragFiles.stagedFile(id: id) != nil)
          return (current, try #require(current.uploadedKey), png)
      }

      /// An uploaded recording of `kind` under `videoKey` with no local file, at the world's location (the record
      /// `CoordinatorDragOutTests.showingUploadedRecording` builds).
      func addUploadedRecording(to coordinator: AppCoordinator, kind: MediaKind = .video) -> CaptureRecord {
          let record = CaptureRecord(fileURL: nil, pixelWidth: 1600, pixelHeight: 1000, appName: nil,
                                     uploadState: .uploaded(url: publicURL(videoKey), key: videoKey),
                                     objectLocation: world.location, mediaKind: kind, durationSeconds: 10,
                                     byteCount: 1_000)
          coordinator.history.add(record)
          return record
      }

      /// phase-6a:170 (:189), in part; phase-6a:174 (:193), full; coordinator-split:44 (:48), in part, the pin menu's
      /// `Save As…` item (the suggestion and Cancel); recording-r1:340 (:397) and recording-r2:670 (:750), full, the
      /// Save As… verb (the other verbs are the existing tests tests-small.md SAVEAS.4 names).
      /// Save As… on a capture in the save folder suggests its own name, PNG, in the save folder; Cancel writes, posts
      /// and logs nothing. Saved elsewhere, the copy is the original's bytes (no re-encode) and `Saved` names it;
      /// saved over the original, the original is unchanged; with notifications off the file is still written and
      /// nothing is posted. The card, the record and its link, Recent Captures, `history.json`, Reveal Last Capture
      /// and the clipboard are as they were. `saveAs(recordID:)` is what the pin's menu item calls too.
      /// Stays: phase-6a:170, `shasum`, the click on `Saved` revealing the copy (the notifier's) and the panel's
      /// Replace prompt (AppKit's), by hand with no seam. coordinator-split:44, the pin over the spot, its second
      /// click, `Close Pinned Screenshots` and reaching the item through the pin's menu (`PINS`, `SCREENS`), and the
      /// panel itself.
      @Test func saveAsOfASavedImageCopiesItsBytesAndChangesNothingElse() async throws {
          defer { world.removeAll() }
          let folder = try world.storeSaveFolder()
          let coordinator = world.makeCoordinator()
          let (record, original) = try addSavedImage(to: coordinator, in: folder)
          let id = record.id
          let file = try #require(record.fileURL)
          world.cards.showing.insert(id)
          coordinator.lastCaptureURL = file
          let records = coordinator.history.records
          let historyFile = try Data(contentsOf: world.historyFileURL)
          let cardCalls = world.cards.calls
          let copy = try desktop("Copy.png")
          let quiet = try desktop("Quiet.png")
          chooser.answers = [nil, copy, file, quiet]

          coordinator.saveAs(recordID: id)
          try await eventually { chooser.asked.count == 1 }
          let suggestion = try #require(chooser.asked.first)
          #expect(suggestion.fileName == "Shot.png")
          #expect(suggestion.directory == world.saveLocation.currentURL)
          #expect(suggestion.mediaKind == .image)
          #expect(world.notifier.calls.isEmpty)
          #expect(world.logLines.isEmpty)

          coordinator.saveAs(recordID: id)
          try await eventually { world.notifier.calls == [.saved(title: "Saved", file: "Copy.png")] }
          #expect(try Data(contentsOf: copy) == original)

          coordinator.saveAs(recordID: id)
          try await eventually { world.notifier.calls.count == 2 }
          #expect(world.notifier.calls.last == .saved(title: "Saved", file: "Shot.png"))
          #expect(try Data(contentsOf: file) == original)

          // Last, so no earlier save is still to read the setting.
          world.settings.showNotification = false
          coordinator.saveAs(recordID: id)
          try await eventually { exists(quiet) }
          #expect(try Data(contentsOf: quiet) == original)

          #expect(chooser.asked == Array(repeating: suggestion, count: 4))
          #expect(world.notifier.calls.count == 2)
          #expect(coordinator.history.records == records)
          #expect(try Data(contentsOf: world.historyFileURL) == historyFile)
          #expect(world.cards.calls == cardCalls)
          #expect(world.cards.showing == [id])
          #expect(coordinator.lastCaptureURL == file)
          #expect(world.clipboard.copies.isEmpty)
          #expect(world.logLines.isEmpty)
      }

      /// phase-6a:171 (:190), in part. An upload-only capture's suggestion is the file name template's name with the
      /// counter as it stands, none drawn, and no folder when none is set (the panel opens where it last was). After a
      /// failed upload (`Retry  Save As…`) the copy is the pending file, `pending/<id>.png`; while its retry's upload
      /// is held (`Uploading…`) the copy is the pending file too, nothing is downloaded, and the upload goes on.
      /// Stays: where the panel last was (the panel's own, AppKit's), by hand with no seam. The suggestion with a save
      /// folder is `EditorNamingTests.uploadOnlyCaptureWithoutAKeySuggestsTheTemplateName` and
      /// `.counterUsesTheCurrentValue`.
      @Test func anUploadOnlyCapturesSaveAsSuggestsTheTemplateNameAndCopiesItsPendingFile() async throws {
          defer { world.removeAll() }
          defer { destination.releaseUploads() }
          world.settings.fileNameTemplate = "shot-{counter}"
          _ = world.settings.nextCounter()
          _ = world.settings.nextCounter()
          let coordinator = world.makeCoordinator()
          let record = try addPendingImage(to: coordinator)
          let id = record.id
          let png = try Data(contentsOf: try #require(record.fileURL))
          let failed = try desktop("Failed.png")
          let uploading = try desktop("Uploading.png")
          chooser.answers = [failed, uploading]

          coordinator.saveAs(recordID: id)
          try await eventually { world.notifier.calls == [.saved(title: "Saved", file: "Failed.png")] }
          #expect(chooser.asked == [EditorNaming.SaveAsSuggestion(fileName: "shot-2.png", directory: nil,
                                                                   mediaKind: .image)])
          #expect(world.settings.currentCounter == 2)
          #expect(try Data(contentsOf: failed) == png)

          destination.state.withLock { $0.holdingUploadsRemaining = 1 }
          coordinator.retryUpload(recordID: id)
          try await eventually { destination.state.withLock { $0.heldUploads.count } == 1 }
          #expect(coordinator.history.record(id: id)?.isUploading == true)
          coordinator.saveAs(recordID: id)
          try await eventually { world.notifier.calls.contains(.saved(title: "Saved", file: "Uploading.png")) }
          let counter = world.settings.currentCounter
          #expect(chooser.asked.last == EditorNaming.SaveAsSuggestion(fileName: "shot-\(counter).png", directory: nil,
                                                                       mediaKind: .image))
          #expect(try Data(contentsOf: uploading) == png)
          #expect(coordinator.history.record(id: id)?.isUploading == true)
          #expect(destination.state.withLock { $0.dataDownloadKeys }.isEmpty)

          destination.releaseUploads()
          try await eventually { coordinator.history.record(id: id)?.uploadedKey != nil }
      }

      /// phase-6a:172 (:191), in part; phase-6a:198 (:220), in part, the Save As… part of "need no download".
      /// After an upload-only capture's upload on a card that showed through it, Save As… writes the card's kept drag
      /// copy, with no GET and no `Downloading` notice. On an upload-only card with no drag copy (a restored card
      /// before its quiet download has landed) the panel comes first and nothing is posted or fetched while it is up;
      /// after Save `Saving a copy…` with `Downloading <key>` is posted, the object is written and `Saved` follows.
      /// Offline, the failure is posted as `Not saved`, nothing is written and nothing is logged.
      /// Stays: phase-6a:172, the restore itself (`SCREENS`: `restoreClosedOverlay` reads `overlayScreen`), `curl`
      /// against the bucket and the slow profile, by hand. phase-6a:198, Slack reading the file in that minute, by hand
      /// with no seam; its Copy Image, Annotate and 60 s clean-up are CT-2's tests.
      @Test func anUploadOnlyCardsSaveAsWritesTheDragCopyOrDownloadsAfterThePanel() async throws {
          defer { world.removeAll() }
          defer { chooser.answer(nil) }
          let coordinator = world.makeCoordinator()
          let (kept, _, png) = try await uploadWithItsCardShowing(coordinator)
          let fromDrag = try desktop("Kept.png")
          chooser.answers = [fromDrag]

          coordinator.saveAs(recordID: kept.id)
          try await eventually { world.notifier.calls.contains(.saved(title: "Saved", file: "Kept.png")) }
          #expect(try Data(contentsOf: fromDrag) == png)
          #expect(destination.state.withLock { $0.dataDownloadKeys }.isEmpty)
          #expect(!postedDownloading)

          let object = try CoordinatorWorld.pngData(width: 6, height: 2)
          // A fixed template: the default one's {time} could tick between the coordinator's read and ours.
          world.settings.fileNameTemplate = "shot-{counter}"
          let restored = addUploadOnly(to: coordinator, bytes: object)
          world.cards.showing.insert(restored.id)
          let downloaded = try desktop("Restored.png")
          chooser.holds = true
          let beforePanel = world.notifier.calls.count

          coordinator.saveAs(recordID: restored.id)
          try await eventually { chooser.isWaiting }
          #expect(chooser.asked.last == EditorNaming.SaveAsSuggestion(
              fileName: "shot-\(world.settings.currentCounter).png", directory: nil, mediaKind: .image))
          #expect(notices(after: beforePanel).isEmpty)
          #expect(destination.state.withLock { $0.dataDownloadKeys }.isEmpty)
          chooser.answer(downloaded)
          try await eventually { notices(after: beforePanel).count == 2 }
          #expect(notices(after: beforePanel) == [.notice(title: "Saving a copy…", body: "Downloading \(key)"),
                                                 .saved(title: "Saved", file: "Restored.png")])
          #expect(try Data(contentsOf: downloaded) == object)
          #expect(destination.state.withLock { $0.dataDownloadKeys } == [key])

          let offline = URLError(.notConnectedToInternet)
          destination.state.withLock { $0.dataDownloadFailures = [offline] }
          let notSaved = try desktop("Offline.png")
          chooser.answers = [notSaved]
          let beforeOffline = world.notifier.calls.count
          coordinator.saveAs(recordID: restored.id)
          try await eventually { notices(after: beforeOffline).count == 2 }
          #expect(notices(after: beforeOffline) == [.notice(title: "Saving a copy…", body: "Downloading \(key)"),
                                                   .error(title: "Not saved", message: offline.localizedDescription)])
          #expect(!exists(notSaved))
          #expect(destination.state.withLock { $0.dataDownloadKeys } == [key, key])
          #expect(chooser.asked.count == 3)
          #expect(world.logLines.isEmpty)
      }

      /// recording-r4:277 (:294), full. Save As… on an uploaded recording while its drag-out download runs: after the
      /// panel it waits for the download, then copies the landed file to the chosen place. One GET in all, the drag-out
      /// download's, no `download(key:to:)` and no `download(key:)`; `Saved` names the copy and nothing says
      /// `Downloading`. The suggestion is an MP4's.
      /// Stays: nothing the line checks; "one GET in the log" is the fake's `downloads` count here.
      @Test func aRecordingsSaveAsDuringItsDragOutDownloadWaitsAndCopiesTheLandedFile() async throws {
          defer { world.removeAll() }
          defer { destination.releaseDownloads() }
          let coordinator = world.makeCoordinator()
          let record = addUploadedRecording(to: coordinator)
          let id = record.id
          world.cards.showing.insert(id)
          destination.state.withLock {
              $0.holdsDownloads = true
              $0.downloadOutcome = .lands(bytes: 1_000)
          }
          coordinator.downloadDragFile(recordID: id)
          try await eventually { destination.state.withLock { $0.downloads.count } == 1 }
          let target = try desktop("Copy.mp4")
          chooser.answers = [target]

          let save = Task { await coordinator.saveVideoCopy(recordID: id) }
          defer { save.cancel() }
          let watch = TaskWatch(save)
          try await eventually { chooser.asked.count == 1 }
          let suggestion = try #require(chooser.asked.first)
          #expect(suggestion.mediaKind == .video)
          #expect(suggestion.fileName.hasSuffix(".mp4"))
          #expect(!watch.hasReturned)
          #expect(!exists(target))

          destination.releaseDownloads()
          try await eventually { watch.hasReturned }
          let landed = try #require(coordinator.dragFiles.stagedFile(id: id))
          #expect(try Data(contentsOf: target) == Data(contentsOf: landed))
          #expect(try Data(contentsOf: target) == Data(count: 1_000))
          #expect(destination.state.withLock { $0.downloads.count } == 1)
          #expect(destination.state.withLock { $0.fileDownloads.isEmpty })
          #expect(destination.state.withLock { $0.dataDownloadKeys }.isEmpty)
          #expect(world.notifier.calls == [.saved(title: "Saved", file: "Copy.mp4")])
      }

      /// phase-6a:175 (:194), in part. The panel held open while the card's auto-close runs out and the drag folder's
      /// minute passes: the card closes as `.autoClose` (restorable), its drag copy goes, the panel is still up, and
      /// when it is answered the capture is saved: an upload-only capture whose drag copy is gone by then, so it is
      /// downloaded (`Saving a copy…`, `Downloading <key>`) and `Saved` follows. One panel in all.
      /// Stays: the card's own timer (`QuickAccessController.scheduleClose`, which `FakeCards.close` stands for) and
      /// the panel window staying usable as the card goes (AppKit's), by hand with no seam.
      @Test func aSaveAsPanelHeldThroughTheCardsAutoCloseStillSaves() async throws {
          defer { world.removeAll() }
          defer { chooser.answer(nil) }
          let coordinator = world.makeCoordinator()
          let (record, k, _) = try await uploadWithItsCardShowing(coordinator)
          let id = record.id
          let object = Data("object".utf8)
          destination.state.withLock { $0.downloadedData = object }
          let target = try desktop("Copy.png")
          chooser.holds = true

          coordinator.saveAs(recordID: id)
          try await eventually { chooser.isWaiting }
          world.cards.close(recordID: id, reason: .autoClose)
          #expect(world.cards.closes == [.autoClose])
          #expect(coordinator.closedOverlays.ids.contains(id))
          try await world.clock.run(for: .seconds(60))
          try await eventually { !exists(coordinator.dragFiles.folder(for: id)) }
          #expect(chooser.isWaiting)
          let beforeAnswer = world.notifier.calls.count

          chooser.answer(target)
          try await eventually { notices(after: beforeAnswer).count == 2 }
          #expect(notices(after: beforeAnswer) == [.notice(title: "Saving a copy…", body: "Downloading \(k)"),
                                                  .saved(title: "Saved", file: "Copy.png")])
          #expect(try Data(contentsOf: target) == object)
          #expect(destination.state.withLock { $0.dataDownloadKeys } == [k])
          #expect(chooser.asked.count == 1)
      }

      /// phase-6a:176 (:195), in part. Save As… from a card in the middle of the stack, and from the oldest (a showing
      /// card stands for a restored one: Save As does not look at the card), writes that card's capture and asks with
      /// that card's suggestion.
      /// Stays: the restore itself (`SCREENS`); the button and the context menu both calling `onSaveAs`
      /// (QuickAccessView.swift:101, :138), by eye.
      @Test func saveAsFromAnyCardWritesThatCardsCapture() async throws {
          defer { world.removeAll() }
          let folder = try world.storeSaveFolder()
          let coordinator = world.makeCoordinator()
          let oldest = try addSavedImage(to: coordinator, in: folder, name: "Oldest.png", width: 4)
          let middle = try addSavedImage(to: coordinator, in: folder, name: "Middle.png", width: 5)
          let newest = try addSavedImage(to: coordinator, in: folder, name: "Newest.png", width: 6)
          world.cards.showing = [oldest.record.id, middle.record.id, newest.record.id]
          let fromMiddle = try desktop("FromMiddle.png")
          let fromOldest = try desktop("FromOldest.png")
          chooser.answers = [fromMiddle, fromOldest]

          coordinator.saveAs(recordID: middle.record.id)
          try await eventually { world.notifier.calls.count == 1 }
          coordinator.saveAs(recordID: oldest.record.id)
          try await eventually { world.notifier.calls.count == 2 }

          #expect(chooser.asked.map(\.fileName) == ["Middle.png", "Oldest.png"])
          #expect(try Data(contentsOf: fromMiddle) == middle.original)
          #expect(try Data(contentsOf: fromOldest) == oldest.original)
          #expect(world.notifier.calls == [.saved(title: "Saved", file: "FromMiddle.png"),
                                           .saved(title: "Saved", file: "FromOldest.png")])
      }

      /// recording-r1:313 (:353), in part, its last sentence. Save As… on an uploaded upload-only video whose drag folder
      /// is gone downloads the object to the chosen file (`download(key:to:)`) after `Saving a copy…` with
      /// `Downloading <key>`, then posts `Saved`; no drag-out download starts.
      /// Stays: restoring the card starting no download (`SCREENS`), and Activity Monitor, by hand; a drag downloading
      /// first is `CoordinatorDragOutTests`.
      @Test func anUploadOnlyVideosSaveAsDownloadsToTheChosenFile() async throws {
          defer { world.removeAll() }
          let coordinator = world.makeCoordinator()
          let record = addUploadedRecording(to: coordinator)
          world.cards.showing.insert(record.id)
          let movie = Data(repeating: 7, count: 32)
          destination.state.withLock { $0.downloadedData = movie }
          let target = try desktop("Chosen.mp4")
          chooser.answers = [target]

          let save = Task { await coordinator.saveVideoCopy(recordID: record.id) }
          defer { save.cancel() }
          let watch = TaskWatch(save)
          try await eventually { watch.hasReturned }

          #expect(try Data(contentsOf: target) == movie)
          #expect(destination.state.withLock { $0.fileDownloads.map(\.key) } == [videoKey])
          #expect(destination.state.withLock { $0.fileDownloads.map(\.file) } == [target])
          #expect(destination.state.withLock { $0.downloads }.isEmpty)
          #expect(world.notifier.calls == [.notice(title: "Saving a copy…", body: "Downloading \(videoKey)"),
                                           .saved(title: "Saved", file: "Chosen.mp4")])
      }

      /// recording-r2:264 (:278), in part, the Save As… part. A GIF's Save As… asks for a `.gif` (the panel's one type
      /// follows the suggestion's kind) and copies the local GIF to the chosen file, over an existing one too, and the
      /// source stays as it was.
      /// Stays: the thumbnail click opening the GIF (`WORKSPACE`); `/Volumes/RecOff`, the hover preview and dragging
      /// into Finder and Slack, by hand. The panel's `com.compuserve.gif` is `EditorNamingTests.aGIFPanelAllowsGIFOnly`;
      /// the menu contents are `QuickAccessModelTests.aGIFHasNoImageActionsCopiesItsFileAndHasTheGIFBadge`.
      @Test func aGIFsSaveAsWritesTheGIFOverAnExistingFileToo() async throws {
          defer { world.removeAll() }
          let folder = try world.storeSaveFolder()
          let coordinator = world.makeCoordinator()
          let gif = Data("GIF89a-bytes".utf8)
          let file = folder.appending(path: "Recording.gif")
          try gif.write(to: file)
          let record = CaptureRecord(fileURL: file, pixelWidth: 640, pixelHeight: 400, appName: nil, mediaKind: .gif,
                                     durationSeconds: 4, byteCount: gif.count)
          coordinator.history.add(record)
          let fresh = try desktop("Fresh.gif")
          let existing = try desktop("Existing.gif")
          try Data("old".utf8).write(to: existing)
          chooser.answers = [fresh, existing]

          for _ in 0..<2 {
              let save = Task { await coordinator.saveVideoCopy(recordID: record.id) }
              defer { save.cancel() }
              let watch = TaskWatch(save)
              try await eventually { watch.hasReturned }
          }

          #expect(chooser.asked.map(\.mediaKind) == [.gif, .gif])
          #expect(chooser.asked.map(\.fileName) == ["Recording.gif", "Recording.gif"])
          #expect(try Data(contentsOf: fresh) == gif)
          #expect(try Data(contentsOf: existing) == gif)
          #expect(try Data(contentsOf: file) == gif)
          #expect(world.notifier.calls == [.saved(title: "Saved", file: "Fresh.gif"),
                                           .saved(title: "Saved", file: "Existing.gif")])
          #expect(destination.state.withLock { $0.fileDownloads }.isEmpty)
      }

      /// No checklist line (catalogue SAVEAS E1): the one branch of `askSaveAsTarget` nothing else reaches, the record
      /// read again after the panel (RA:202-205), which the seam leaves in the coordinator. A capture deleted while its
      /// panel is up is not written, nothing is posted, and the coordinator logs why.
      @Test func aSaveAsWhoseCaptureIsDeletedWhileThePanelIsUpWritesNothingAndLogsIt() async throws {
          defer { world.removeAll() }
          defer { chooser.answer(nil) }
          let folder = try world.storeSaveFolder()
          let coordinator = world.makeCoordinator()
          let (record, _) = try addSavedImage(to: coordinator, in: folder)
          let id = record.id
          let gone = try desktop("Gone.png")
          chooser.holds = true

          coordinator.saveAs(recordID: id)
          try await eventually { chooser.isWaiting }
          coordinator.history.remove(id: id)
          chooser.answer(gone)
          try await eventually { world.logLines == ["Save As: \(id) was deleted while the panel was open"] }
          #expect(!exists(gone))
          #expect(world.notifier.calls.isEmpty)
      }
  }
  ```
  Gating, as SAVEAS.2 has it: no test awaits `saveAs`, which gives no handle; each `saveVideoCopy` runs in the test's own `Task`, cancelled in a `defer` registered right after it is made and gated by `TaskWatch`. The three held panels (tests 3, 5 and E1) declare `defer { chooser.answer(nil) }` right after the world's `defer`, and never hold two at once. Test 2's held PUT and test 4's held download are released in a `defer` declared right after the world's. Writes go under `<root>/Desktop/` and `<root>/Saved/`.

#### Save As… after an edit (catalogue SAVEAS.5)

- [ ] In `TidyShotTests/CoordinatorEditorSaveTests.swift`, add test 9 after CT-2's `saveOverTheFileRemovesTheDragCopyAndEveryReadGivesTheEdit`. Replace:
  ```swift
          #expect(destination.state.withLock { $0.dataDownloadKeys }.isEmpty)
          #expect(world.factory.askedConfigs.isEmpty)
          try await settledEdit(coordinator, id)
      }

      /// phase-4a:97 (:146), in part.
  ```
  with:
  ```swift
          #expect(destination.state.withLock { $0.dataDownloadKeys }.isEmpty)
          #expect(world.factory.askedConfigs.isEmpty)
          try await settledEdit(coordinator, id)
      }

      /// phase-6a:199 (:224), in part, the card's Save As… after an edit saved over the file (the line's last
      /// sentence; with `CoordinatorEditorUploadTests.saveAsAfterAnEditorUploadOfAnUploadOnlyCaptureWritesTheEditDuringAndAfterThePut`
      /// and CT-2's two tests). After the edit is saved over the save-folder file, which removes the capture's drag copy,
      /// Save As… (`saveAs(recordID:)`, the panel `world.saveAsChooser`) suggests the capture's own name and writes the
      /// edited image to the chosen file, never the one before the edit, read from the file and not from the bucket.
      /// Stays: the drop, by hand; reaching Save As… after the edit, which only a pin offers (`PINS`; Recent Captures
      /// has no Save As…, RecentCapturesMenu.swift:110-121).
      @Test func saveAsAfterASaveOverTheFileWritesTheEditNotTheOriginal() async throws {
          defer { world.removeAll() }
          let folder = try world.storeSaveFolder()
          let coordinator = world.makeCoordinator()
          let (record, original) = try addSavedImage(to: coordinator, in: folder)
          let id = record.id
          world.cards.showing.insert(id)
          coordinator.prepareDragFile(recordID: id)
          try await eventually { world.cards.dragFiles(for: id).last.flatMap { $0 } != nil }
          let staged = try #require(world.cards.dragFiles(for: id).last.flatMap { $0 })
          #expect(try Data(contentsOf: staged) == original)
          let copy = try desktop("Edited.png")
          world.saveAsChooser.answers = [copy]

          coordinator.openEditor(recordID: id)
          let editor = try await openedEditor(id)
          editor.draw()
          #expect(await editor.save())
          #expect(!exists(coordinator.dragFiles.folder(for: id)))

          coordinator.saveAs(recordID: id)
          try await eventually { world.notifier.calls.contains(.saved(title: "Saved", file: "Edited.png")) }
          #expect(world.saveAsChooser.asked.map(\.fileName) == ["Shot.png"])
          #expect(try EditorPixels.isBlue(png: Data(contentsOf: copy)))
          #expect(try Data(contentsOf: copy) != original)
          #expect(destination.state.withLock { $0.dataDownloadKeys }.isEmpty)
          #expect(world.factory.askedConfigs.isEmpty)
          try await settledEdit(coordinator, id)
      }

      /// phase-4a:97 (:146), in part.
  ```

- [ ] In `TidyShotTests/CoordinatorEditorUploadTests.swift`, add test 10 right after CT-2's `uploadOfAnUploadOnlyCaptureRemovesItsDragCopyAndEveryReadGivesTheEdit`. Replace:
  ```swift
          let again = try #require(world.editors.editor(for: id))
          #expect(EditorPixels.isBlue(again.model.base))
          #expect(destination.state.withLock { $0.dataDownloadKeys }.isEmpty)
          try await settledEdit(coordinator, id)
      }
  ```
  with:
  ```swift
          let again = try #require(world.editors.editor(for: id))
          #expect(EditorPixels.isBlue(again.model.base))
          #expect(destination.state.withLock { $0.dataDownloadKeys }.isEmpty)
          try await settledEdit(coordinator, id)
      }

      /// phase-6a:199 (:224), in part, the card's Save As… after an editor upload of an upload-only capture (with
      /// `CoordinatorEditorSaveTests.saveAsAfterASaveOverTheFileWritesTheEditNotTheOriginal` and CT-2's two tests).
      /// While the editor's PUT is held, Save As… writes the edit from the pending file; after it, from the drag copy
      /// the finished upload kept. Neither reads the bucket or posts `Downloading`.
      /// Stays: the drop, by hand; reaching Save As… after the edit, which only a pin offers (`PINS`). Annotate closes
      /// the card for good, so the test puts the record back in `FakeCards.showing` for the upload's end to keep a drag
      /// copy, as CT-2's test does.
      @Test func saveAsAfterAnEditorUploadOfAnUploadOnlyCaptureWritesTheEditDuringAndAfterThePut() async throws {
          defer { world.removeAll() }
          defer { destination.releaseUploads() }
          let coordinator = world.makeCoordinator()
          let record = try addPendingImage(to: coordinator)
          let id = record.id
          world.cards.showing.insert(id)
          coordinator.retryUpload(recordID: id)
          try await eventually { coordinator.history.record(id: id)?.uploadedKey != nil }
          let k = try #require(coordinator.history.record(id: id)?.uploadedKey)
          #expect(coordinator.dragFiles.stagedFile(id: id) != nil)
          destination.state.withLock { $0.holdingUploadsRemaining = 1 }
          let during = try desktop("During.png")
          let after = try desktop("After.png")
          world.saveAsChooser.answers = [during, after]

          coordinator.openEditor(recordID: id)
          let editor = try await openedEditor(id)
          editor.draw()
          let outcome = await editor.upload()
          #expect(outcome == EditorUploadOutcome(wroteLocally: true, enqueued: true))
          world.cards.showing.insert(id)
          try await eventually { destination.state.withLock { $0.heldUploads.count } == 1 }
          #expect(coordinator.history.record(id: id)?.fileURL == pendingURL(coordinator, id))

          coordinator.saveAs(recordID: id)
          try await eventually { world.notifier.calls.contains(.saved(title: "Saved", file: "During.png")) }
          #expect(try EditorPixels.isBlue(png: Data(contentsOf: during)))

          destination.releaseUploads()
          try await eventually { coordinator.history.record(id: id)?.uploadState == .uploaded(url: publicURL(k), key: k) }
          #expect(coordinator.history.record(id: id)?.fileURL == nil)
          #expect(coordinator.dragFiles.stagedFile(id: id) != nil)
          coordinator.saveAs(recordID: id)
          try await eventually { world.notifier.calls.contains(.saved(title: "Saved", file: "After.png")) }
          #expect(try EditorPixels.isBlue(png: Data(contentsOf: after)))
          #expect(destination.state.withLock { $0.dataDownloadKeys }.isEmpty)
          let downloading = world.notifier.calls.contains { call in
              guard case .notice(_, let body, _) = call else { return false }
              return body.hasPrefix("Downloading ")
          }
          #expect(!downloading)
          try await settledEdit(coordinator, id)
      }
  ```
  The anchor is the end of CT-2's test, so test 10 lands right after it whether the suite's closing `}` or Task 1's T17 follows. Both tests reach `applyLocalEdit` and end with `settledEdit`; neither commits an effect.

#### Runs, the Release build and the commit

- [ ] Run the four suites this task touches:
  ```bash
  xcodegen generate && xcodebuild test -project TidyShot.xcodeproj -scheme TidyShot -destination 'platform=macOS' -derivedDataPath .build -only-testing:TidyShotTests/CoordinatorSaveAsTests -only-testing:TidyShotTests/CoordinatorEditorSaveTests -only-testing:TidyShotTests/CoordinatorEditorUploadTests -only-testing:TidyShotTests/CoordinatorWorldTests 2>&1 | grep -E "Test run with|error:|TEST"
  ```
  Expected: `✔ Test run with 44 tests in 4 suites passed after …` (9 + 18 + 16 + 1) and `** TEST SUCCEEDED **`. The `error:` lines that print are the known noise the Global Constraints name, not failures.

- [ ] Run the full suite:
  ```bash
  xcodegen generate && xcodebuild test -project TidyShot.xcodeproj -scheme TidyShot -destination 'platform=macOS' -derivedDataPath .build 2>&1 | grep -E "Test run with|error:|TEST"
  ```
  Expected: `✔ Test run with 2347 tests in 195 suites passed after …` and `** TEST SUCCEEDED **`, with only the known noise lines. A run that fails only on `UploadQueueTests.aSidecarUnwritableDuringThePartsFailsTheJobBeforeComplete` is rerun once; it must then pass.

- [ ] Run the Release build:
  ```bash
  xcodegen generate && xcodebuild -project TidyShot.xcodeproj -scheme TidyShot -configuration Release -derivedDataPath .build-rel build 2>&1 | grep -E "error:|warning:|BUILD"
  ```
  Expected: `** BUILD SUCCEEDED **`, and no `error:` or `warning:` line from the compiler or the linker beyond the two tool lines the Global Constraints name (`iOSSimulator: … sharedServiceContextForDeveloperDir:error:` and `appintentsmetadataprocessor … warning:`). Any other line, for example a concurrency warning in `AppEnvironment.swift`, is a failure: stop and report it.

- [ ] Assert this task's production diff is the seam's two files, and the system calls left the coordinator:
  ```bash
  git diff --stat HEAD -- TidyShot/
  git diff --numstat HEAD -- TidyShot/App/AppCoordinator+RecordActions.swift
  grep -c "panel.begin()\|NSApplication.shared.activate" TidyShot/App/AppCoordinator+RecordActions.swift
  grep -c "chooseSaveAsURL" TidyShot/App/AppEnvironment.swift TidyShot/App/AppCoordinator+RecordActions.swift TidyShotTests/Support/CoordinatorWorld.swift
  git status --short
  ```
  Expected: the diffstat lists exactly `TidyShot/App/AppCoordinator+RecordActions.swift` and `TidyShot/App/AppEnvironment.swift` (`2 files changed`); `6	9	TidyShot/App/AppCoordinator+RecordActions.swift`; `0`; `TidyShot/App/AppEnvironment.swift:3` (the member, the live value, `chooseSaveAsURLLive`), `TidyShot/App/AppCoordinator+RecordActions.swift:2` (the doc and the call), `TidyShotTests/Support/CoordinatorWorld.swift:2` (the argument and the `saveAsChooser` doc). `git status --short` lists ` M TidyShot/App/AppCoordinator+RecordActions.swift`, ` M TidyShot/App/AppEnvironment.swift`, ` M TidyShotTests/CoordinatorEditorSaveTests.swift`, ` M TidyShotTests/CoordinatorEditorUploadTests.swift`, ` M TidyShotTests/CoordinatorWorldTests.swift`, ` M TidyShotTests/Support/CoordinatorFakes.swift`, ` M TidyShotTests/Support/CoordinatorWorld.swift`, ` M TidyShotTests/Support/FakeDestination.swift` and `?? TidyShotTests/CoordinatorSaveAsTests.swift`, and nothing else.

- [ ] Commit:
  ```bash
  git add TidyShot/App/AppCoordinator+RecordActions.swift TidyShot/App/AppEnvironment.swift TidyShotTests/CoordinatorEditorSaveTests.swift TidyShotTests/CoordinatorEditorUploadTests.swift TidyShotTests/CoordinatorWorldTests.swift TidyShotTests/Support/CoordinatorFakes.swift TidyShotTests/Support/CoordinatorWorld.swift TidyShotTests/Support/FakeDestination.swift TidyShotTests/CoordinatorSaveAsTests.swift
  git commit -m "refactor: the card's Save As panel through AppEnvironment.chooseSaveAsURL, its fake, eleven Save As tests"
  ```
  No attribution lines and no session URL in the message; do not push. The report says no hand check was run.

### Task 3: The recording log sink, `AppEnvironment.recordingLog`, and its five tests [integration]

The `LOG` seam (design 2.3, 3.3, 3.4, 3.5 point 3): the coordinator's 24 `Recording:` lines and `RecordingRecovery.scan`'s
removal line go to `AppEnvironment.recordingLog`, live `{ RecordingLog.note($0) }`, so the suite reads them as
`world.recordingLines`. Then the catalogue's five LOG tests (tests-small.md LOG.3, LOG.4), the world check (LOG.5) and the
two stale comments (LOG.6). Every file:line below is at f991760 unless it says otherwise; where Task 1 or Task 2 has
changed a shared file, the step quotes the text as they leave it (design 2.4: `recordingLog` is the last member and the
last argument; only `live()`'s doc sentence and the world's type doc are reworded by all three tasks, and this task, the
last, leaves them in their final form).

**Files:**
- Modify `TidyShot/App/AppEnvironment.swift`: the `log` member's doc and a new `recordingLog` member after it, last
  (:45-46); the `recordingLog:` live argument after `log:`, last (:87); `live()`'s doc comment (:48-52 at f991760,
  reworded by Tasks 1 and 2) rewritten whole to design 2.4's final text.
- Modify `TidyShot/Recording/ScreenRecordingDriver.swift`: one doc line on `RecordingLog` after :90.
- Modify `TidyShot/App/AppCoordinator.swift`: the forwarder `recordingLog(_:)` after `log(_:)` (:289-292); `start()`
  hands `scan` the sink through `begin`'s `scanning:` (:320-322). Task 1's edits (:158-160, :274) are elsewhere.
- Modify `TidyShot/App/AppCoordinator+Recording.swift`: the 16 main-actor `RecordingLog.note(` calls (:109, :114, :160,
  :165, :180, :183, :189, :191, :273, :293, :339, :358, :365, :411, :468, :590) become `recordingLog(`; `saveRecording`
  passes the sink into the detached `placeRecording` (:793, :799); `placeRecording` takes `note:` (:866-876) and its two
  calls (:884, :892) become `note(`.
- Modify `TidyShot/App/AppCoordinator+Recovery.swift`: the 4 calls (:127, :129, :143, :161) become `recordingLog(`.
- Modify `TidyShot/App/AppCoordinator+Upload.swift`: the 2 calls (:378, :395) become `recordingLog(`. Task 1's edit
  (:426) is elsewhere.
- Modify `TidyShot/Recording/RecordingRecovery.swift`: `scan`'s doc and signature (:20-22), its two calls (:34, :36),
  `begin`'s doc (:105-106). `sweepMuteFolder` (:137) keeps `RecordingLog.note` (design 2.3, call 2).
- Modify `TidyShotTests/Support/CoordinatorFakes.swift`: `CoordinatorWorldState` (:254-289 at f991760, about 26 lines
  lower after Task 2's `FakeSaveAsChooser`): its doc, `Values.recordingLines`, the getter and `appendRecording(_:)`.
- Modify `TidyShotTests/Support/CoordinatorWorld.swift`: the type doc (:11-15 at f991760, reworded by Tasks 1 and 2)
  rewritten whole to its final text; `recordingLines` after `logLines` (:106); `recordingLog:` after `log:`, last (:134).
- Modify `TidyShotTests/CoordinatorWorldTests.swift`: one `#expect` after `#expect(world.logLines.isEmpty)` (:31).
- Modify `TidyShotTests/CoordinatorRecordingTests.swift`: the comments of tests 48 (:53) and 50 (:90); four tests
  appended before the closing `}` of `struct CoordinatorRecordingTests` (:379).
- Modify `TidyShotTests/RecordingRecoveryTests.swift`: one test inserted before `anMP4BesideAPartialGIFIsFoundAndTheGIFRemoved`
  (its doc comment at :66).

**Interfaces:**
- Consumes, production at f991760:
  ```swift
  // AppEnvironment.swift:45-46, :53
  var log: @Sendable (String) -> Void
  static func live() -> AppEnvironment
  // ScreenRecordingDriver.swift:91-97
  nonisolated enum RecordingLog { static func note(_ message: String) }
  // RecordingRecovery.swift:21-22, :107-109 (nonisolated enum RecordingRecovery)
  @concurrent static func scan(_ directory: URL) async -> [Found]
  static func begin(recordingDirectory: URL, muteDirectory: URL,
                    scanning: (URL) async -> [Found] = { await RecordingRecovery.scan($0) })
      async -> (muteFiles: [URL], found: [Found])
  // AppCoordinator.swift
  func log(_ message: String)                                                  // :290
  func start()                                                                 // :294
  func finishRecordingForQuit() async                                          // :489
  @discardableResult func withCaptureLock(coversDesktop: Bool, _ body: () async -> Void) async -> Bool   // :563-564
  private(set) var isCapturing = false                                         // :79
  @ObservationIgnored var recordingCountIn = false { … }                       // :91
  @ObservationIgnored var recordingStartCancelled = false                      // :99
  @ObservationIgnored var urlRecordingStartPending = false                     // :104
  @ObservationIgnored var askingPermission: PermissionPrompt?                  // :109
  @ObservationIgnored var recordingSavesInFlight = 0                           // :113
  nonisolated enum PermissionPrompt: Equatable, Sendable { case microphone, camera; var name: String }   // :584-595
  // AppCoordinator+Recording.swift
  var recordingPhase: RecordingPhase                                           // :9
  func requestAccessFromSettings(_ prompt: PermissionPrompt) async             // :103
  func recordScreen() async                                                    // :145
  func startRecording(intent: CaptureIntent, preselect: ScreenRect?)           // :156
  func stopRecordingCommand(sender: String?)                                   // :175
  func recordFullscreen() async                                                // :244
  nonisolated private static func placeRecording(_ source: URL, kind: MediaKind, id: UUID,
                                                 folder: (url: URL, baseName: String)?, noFolderReason: String?,
                                                 pending: PendingFileStore,
                                                 recoveryURL: URL) -> (result: RecordingFileResult, url: URL)   // :873-876
  // RecordingController.swift: private(set) var isRunning (:128), var isEnding: Bool (:131), func stop() (:238)
  // URLCommandHandler.swift
  init(settings: AppSettings, target: any URLCommandTarget, screens: @escaping () -> Screens,
       post: @escaping (URLCommandNotice) -> Void)                              // :74-75
  func handle(_ url: URL, sender: String?) async                               // :83
  func ready() async                                                           // :98
  struct Screens { var displays: [URLCommandGeometry.Display]; var pointerIndex: Int? }   // :54-59
  nonisolated struct URLCommandNotice: Equatable, Sendable { var title: String; var subtitle: String?; var body: String }   // :42-46
  // CaptureIntent.swift:22
  init(action: AfterCaptureAction, copyOnly: Bool = false, then: Then = .none, sender: String? = nil)
  // MicrophoneChoice.swift:58
  static let systemDefaultValue = "default"
  ```
- Consumes, the suite at f991760: `func eventually(_ condition: () async -> Bool) async throws` (UploadQueueTests.swift:42,
  `@MainActor`); `nonisolated final class LogLines: Sendable { let lines = Mutex<[String]>([]) }` (UploadQueueTests.swift:21-23);
  `final class HeldCameraDevices: CameraDevices` and `final class HeldMicrophoneDevices: MicrophoneDevices`
  (CoordinatorFakes.swift:306, :332: `private(set) var requestCount`, `var isAsking: Bool`, `func answer(_ granted: Bool)`);
  `final class TestGate` (:358: `var isWaiting: Bool`, `func wait() async`, `func open()`); `final class TaskWatch`
  (:422: `init<Success: Sendable>(_ task: Task<Success, Never>)`, `private(set) var hasReturned`); `SingleWaiter` (:377,
  single-entry, cancellable, sequential waits allowed since `resume` clears the waiter, :411-415);
  `FakeNotifier.Call.waited(Duration)` (:17) and `calls` (:20); `nonisolated final class CoordinatorWorldState: Sendable`
  (:256, `private struct Values`, `private let values = Mutex(Values())`, `var lines`, `func append(_ line: String)`);
  `FakeMicrophoneDevices.init(devices: [MicrophoneDevice] = [], defaultInput: MicrophoneDevice? = nil, access:
  MicrophoneAccess = .authorized, grants: Bool = true)` and `requestCount` (RecordingFakes.swift:422-425);
  `FakeRecordingDriver.stopCount` (RecordingFakes.swift:48); `VideoFixtures.makeMP4(at:width:height:seconds:audio:…)`
  (VideoFixtures.swift:48-49, `@concurrent`, `async throws`); `CoordinatorWorld` (`makeCoordinator()`, `removeAll()`,
  `settings`, `notifier`, `driver`, `microphones`, `cameras`, `logLines` :106, `state` :48); `CoordinatorRecordingTests`'
  own `beginRecording(on:) async -> Task<RecordingOutcome, Never>` (:31) and `beginCountdown(on:) async throws ->
  Task<SelfTimerOutcome, Never>` (:43); `RecordingRecoveryTests.dir` (:10, made in `init`, :12-15).
- Produces, production:
  ```swift
  // AppEnvironment, the last member; live: { RecordingLog.note($0) }
  var recordingLog: @Sendable (String) -> Void
  // AppCoordinator, after log(_:)
  func recordingLog(_ message: String)
  // RecordingRecovery
  @concurrent static func scan(_ directory: URL,
                               note: @Sendable (String) -> Void = { RecordingLog.note($0) }) async -> [Found]
  // AppCoordinator+Recording, stays private
  nonisolated private static func placeRecording(_ source: URL, kind: MediaKind, id: UUID,
                                                 folder: (url: URL, baseName: String)?, noFolderReason: String?,
                                                 pending: PendingFileStore, recoveryURL: URL,
                                                 note: @Sendable (String) -> Void) -> (result: RecordingFileResult, url: URL)
  ```
- Produces, the suite: `CoordinatorWorldState.recordingLines: [String]` (getter) and `func appendRecording(_ line: String)`;
  `CoordinatorWorld.recordingLines: [String]` (getter, `state.recordingLines`); the world's environment passes
  `recordingLog: { line in state.appendRecording(line) }` as its last argument. Task 4's marks name the five tests below.

**Tests:**
1. `stopRecordingLogsWhatItDidInEachPhase`: catalogue LOG.3 (CoordinatorRecordingTests.swift, existing); effort M.
2. `aStartLogsEachPromptsAnswerAndASecondPressWhileOneIsUp`: catalogue LOG.3; effort M.
3. `aSettingsPromptLogsItsAnswerOrWhyItWaits`: catalogue LOG.3; effort L.
4. `aSecondURLStartBeforeTheFirstTakesTheLockIsLogged`: catalogue LOG.3; effort M.
5. `aLeftoverThatDoesNotPlayIsRemovedAndLogged`: catalogue LOG.4 (RecordingRecoveryTests.swift, existing); effort S.
- 5 tests (S 1, M 3, L 1), 0 parameterized, 0 new suite files. Also the world check of LOG.5 and the two comment edits of
  LOG.6, which are not tests.
- Focused run, `-only-testing:` `CoordinatorRecordingTests`, `RecordingRecoveryTests` and `CoordinatorWorldTests`:
  `Test run with 39 tests in 3 suites passed` (12 + 4, 21 + 1, and 1).
- Full suite: `Test run with 2352 tests in 195 suites passed` (2347 in 195 after Task 2, plus these 5).
- Also: the production diff of this task is the seven files above; the Release build prints `** BUILD SUCCEEDED **`
  and no `error:` or `warning:` line beyond the two tool lines the Global Constraints name.

**Commit:** `refactor: the coordinator's Recording: lines through AppEnvironment.recordingLog, scan's note, five log tests`

**Steps:**

- [ ] Check the starting point. From the repository root:
  ```bash
  git branch --show-current
  git status --short -- TidyShot TidyShotTests
  git log --oneline f991760..HEAD | wc -l
  grep -c "recordingLog" TidyShot/App/AppEnvironment.swift TidyShotTests/Support/CoordinatorWorld.swift
  grep -c "chooseSaveAsURL\|clopOptimiser" TidyShot/App/AppEnvironment.swift
  ```
  Expected: `small-seams`; nothing; `2` (Task 1's and Task 2's commits; `wc` may pad it with spaces); `TidyShot/App/AppEnvironment.swift:0` and
  `TidyShotTests/Support/CoordinatorWorld.swift:0`; a number above 0 (Tasks 1 and 2 have landed). If the first count is
  not 2 or the last is 0, stop and report: this task's edits assume Tasks 1 and 2 are committed.

#### The seam (design 2.3)

- [ ] In `TidyShot/App/AppEnvironment.swift`, add the member, its live value and the final `live()` doc. Run from the
  repository root (the doc comment is rewritten whole because Tasks 1 and 2 each reworded it; design 2.4 gives the
  text the last task leaves):
  ```bash
  python3 - <<'PY'
  from pathlib import Path

  path = Path("TidyShot/App/AppEnvironment.swift")
  text = path.read_text()

  def replace_once(text, old, new):
      assert text.count(old) == 1, f"expected one occurrence of {old!r}, found {text.count(old)}"
      return text.replace(old, new)

  text = replace_once(text,
      "    /// Every coordinator log line (`RecordingLog.note` keeps its own).\n"
      "    var log: @Sendable (String) -> Void\n",
      "    /// Every coordinator log line but the `Recording:` ones.\n"
      "    var log: @Sendable (String) -> Void\n"
      "    /// The coordinator's `Recording:` lines, and the launch scan's (`RecordingRecovery.scan`);\n"
      "    /// `RecordingLog.note` in the app.\n"
      "    var recordingLog: @Sendable (String) -> Void\n")

  text = replace_once(text,
      "            log: { NSLog(\"%@\", $0) })\n",
      "            log: { NSLog(\"%@\", $0) },\n"
      "            recordingLog: { RecordingLog.note($0) })\n")

  # live()'s doc comment, whatever Tasks 1 and 2 left: every line from its first to `static func live()`.
  lines = text.split("\n")
  first = [i for i, line in enumerate(lines) if line.startswith("    /// What the app runs on:")]
  live = [i for i, line in enumerate(lines) if line == "    static func live() -> AppEnvironment {"]
  assert len(first) == 1 and len(live) == 1 and first[0] < live[0], (first, live)
  assert all(line.startswith("    ///") for line in lines[first[0]:live[0]]), lines[first[0]:live[0]]
  lines[first[0]:live[0]] = [
      "    /// What the app runs on: the user's Application Support folder (the temporary folder when it",
      "    /// cannot be had), the shared settings, the Keychain, the notification centre, the card stack,",
      "    /// the general pasteboard, S3, Clop, the alerts, the shutter sound, the editor window, the card's",
      "    /// Save As… panel, the wall clock, `NSLog` and `RecordingLog`. The collaborators are built in the",
      "    /// order the coordinator's stored properties built them; Clop's optimiser, a value that reaches",
      "    /// nothing until a request, is built here.",
  ]
  path.write_text("\n".join(lines))
  print("AppEnvironment.swift: recordingLog added")
  PY
  ```
  Expected: `AppEnvironment.swift: recordingLog added`, and no `AssertionError`. The two anchors are untouched by Tasks 1
  and 2: Task 1 adds `clopOptimiser`/`isClopRunning` after `freeBytes` and Task 2 `chooseSaveAsURL` after `makeEditor`,
  so `log` stays the last member and `log:` the last argument (design 2.4). After it the file reads, from `var clock`:
  ```swift
      var clock: any ScrollClock
      /// Every coordinator log line but the `Recording:` ones.
      var log: @Sendable (String) -> Void
      /// The coordinator's `Recording:` lines, and the launch scan's (`RecordingRecovery.scan`);
      /// `RecordingLog.note` in the app.
      var recordingLog: @Sendable (String) -> Void

      /// What the app runs on: the user's Application Support folder (the temporary folder when it
      /// cannot be had), the shared settings, the Keychain, the notification centre, the card stack,
      /// the general pasteboard, S3, Clop, the alerts, the shutter sound, the editor window, the card's
      /// Save As… panel, the wall clock, `NSLog` and `RecordingLog`. The collaborators are built in the
      /// order the coordinator's stored properties built them; Clop's optimiser, a value that reaches
      /// nothing until a request, is built here.
      static func live() -> AppEnvironment {
  ```
  and the call in `live()` ends:
  ```swift
              now: { Date() },
              clock: SystemScrollClock(),
              log: { NSLog("%@", $0) },
              recordingLog: { RecordingLog.note($0) })
  ```
  The two sinks stay apart on purpose: `RecordingLog` writes `.public` through `Logger` (ScreenRecordingDriver.swift:88-95),
  `log` goes to `NSLog`, whose text shows as `<private>` (design 2.3).

- [ ] In `TidyShot/Recording/ScreenRecordingDriver.swift`, add one doc line to `RecordingLog` (:88-91). Replace:
  ```swift
  /// `/usr/bin/log show --last 10m --style compact --predicate 'process == "TidyShot"' | grep "Recording:"`.
  nonisolated enum RecordingLog {
  ```
  with:
  ```swift
  /// `/usr/bin/log show --last 10m --style compact --predicate 'process == "TidyShot"' | grep "Recording:"`.
  /// The coordinator reaches it through `AppEnvironment.recordingLog`.
  nonisolated enum RecordingLog {
  ```

- [ ] In `TidyShot/App/AppCoordinator.swift`, add the forwarder after `log(_:)` (:289-292). Replace:
  ```swift
      func log(_ message: String) {
          environment.log(message)
      }
  ```
  with:
  ```swift
      func log(_ message: String) {
          environment.log(message)
      }

      /// A `Recording:` line, through the environment (`RecordingLog.note` in the app).
      func recordingLog(_ message: String) {
          environment.recordingLog(message)
      }
  ```
  It is synchronous, so each line is written on the same thread, in the same order, as before (design 2.3).

- [ ] In the same file, `start()` hands the launch scan the sink through `begin`'s existing `scanning:` parameter
  (:320-322). Replace:
  ```swift
          Task {
              let leftRecordings = await RecordingRecovery.begin(recordingDirectory: Recording.directory,
                                                                 muteDirectory: MuteLog.directory)
  ```
  with:
  ```swift
          let note = environment.recordingLog
          Task {
              let leftRecordings = await RecordingRecovery.begin(recordingDirectory: Recording.directory,
                                                                 muteDirectory: MuteLog.directory,
                                                                 scanning: { await RecordingRecovery.scan($0, note: note) })
  ```

- [ ] The 24 coordinator call sites. In `+Recording`, the two inside the detached `placeRecording` (`nonisolated
  private static`, run in `Task.detached`, :796-801) take the sink as a parameter, which `saveRecording` reads on the
  main actor; the other 16 there, the 4 in `+Recovery` and the 2 in `+Upload` call the forwarder. Every line's string is
  unchanged; only the callee changes. Run from the repository root:
  ```bash
  python3 - <<'PY'
  from pathlib import Path

  def replace_once(text, old, new):
      assert text.count(old) == 1, f"expected one occurrence of {old!r}, found {text.count(old)}"
      return text.replace(old, new)

  # +Recording: the two detached sites in placeRecording take `note`, its caller passes the
  # environment's sink, and the 16 main-actor sites call the coordinator's forwarder.
  path = Path("TidyShot/App/AppCoordinator+Recording.swift")
  text = path.read_text()
  assert text.count("RecordingLog.note(") == 18, text.count("RecordingLog.note(")
  text = replace_once(text,
      "        let (kind, recoveryURL) = (recording.mediaKind, recording.recoveryURL)\n",
      "        let (kind, recoveryURL, note) = (recording.mediaKind, recording.recoveryURL, environment.recordingLog)\n")
  text = replace_once(text,
      "                                                    recoveryURL: recoveryURL)\n",
      "                                                    recoveryURL: recoveryURL, note: note)\n")
  text = replace_once(text,
      "    /// and the path of `recoveryURL`, the file the launch check recovers). Never reads the file.\n"
      "    nonisolated private static func placeRecording(_ source: URL, kind: MediaKind, id: UUID,\n"
      "                                                   folder: (url: URL, baseName: String)?, noFolderReason: String?,\n"
      "                                                   pending: PendingFileStore,\n"
      "                                                   recoveryURL: URL) -> (result: RecordingFileResult, url: URL) {\n",
      "    /// and the path of `recoveryURL`, the file the launch check recovers). Never reads the file.\n"
      "    /// A failed move is logged with `note`, the environment's `recordingLog`.\n"
      "    nonisolated private static func placeRecording(_ source: URL, kind: MediaKind, id: UUID,\n"
      "                                                   folder: (url: URL, baseName: String)?, noFolderReason: String?,\n"
      "                                                   pending: PendingFileStore, recoveryURL: URL,\n"
      "                                                   note: @Sendable (String) -> Void) -> (result: RecordingFileResult, url: URL) {\n")
  text = replace_once(text,
      "                RecordingLog.note(\"Recording: \\(source.lastPathComponent) could not be moved into the save folder: \\(error.localizedDescription)\")\n",
      "                note(\"Recording: \\(source.lastPathComponent) could not be moved into the save folder: \\(error.localizedDescription)\")\n")
  text = replace_once(text,
      "            RecordingLog.note(\"Recording: \\(source.lastPathComponent) could not be moved to pending: \\(error.localizedDescription)\")\n",
      "            note(\"Recording: \\(source.lastPathComponent) could not be moved to pending: \\(error.localizedDescription)\")\n")
  assert text.count("RecordingLog.note(") == 16, text.count("RecordingLog.note(")
  text = text.replace("RecordingLog.note(", "recordingLog(")
  path.write_text(text)
  print("+Recording: 16 forwarder calls, 2 note calls")

  # +Recovery (4) and +Upload (2): every call becomes the forwarder's, the text unchanged.
  for name, count in [("TidyShot/App/AppCoordinator+Recovery.swift", 4), ("TidyShot/App/AppCoordinator+Upload.swift", 2)]:
      path = Path(name)
      text = path.read_text()
      assert text.count("RecordingLog.note(") == count, (name, text.count("RecordingLog.note("))
      path.write_text(text.replace("RecordingLog.note(", "recordingLog("))
      print(f"{path.name}: {count} forwarder calls")
  PY
  ```
  Expected:
  ```
  +Recording: 16 forwarder calls, 2 note calls
  AppCoordinator+Recovery.swift: 4 forwarder calls
  AppCoordinator+Upload.swift: 2 forwarder calls
  ```
  and no `AssertionError`. Task 1's `+Upload` edit (`clopIsRunning`, :426) has no `RecordingLog.note`, so the count of 2
  holds after it. After the script, `placeRecording` reads (:866-880):
  ```swift
      /// and the path of `recoveryURL`, the file the launch check recovers). Never reads the file.
      /// A failed move is logged with `note`, the environment's `recordingLog`.
      nonisolated private static func placeRecording(_ source: URL, kind: MediaKind, id: UUID,
                                                     folder: (url: URL, baseName: String)?, noFolderReason: String?,
                                                     pending: PendingFileStore, recoveryURL: URL,
                                                     note: @Sendable (String) -> Void) -> (result: RecordingFileResult, url: URL) {
  ```
  and its caller in `saveRecording`:
  ```swift
          let (kind, recoveryURL, note) = (recording.mediaKind, recording.recoveryURL, environment.recordingLog)
          // The size is the file's after its move, read from its attributes under the save folder's
          // scope when it went there: a GIF's own, or the MP4's after a failed conversion.
          let (result, fileURL, byteCount) = await Task.detached(priority: .userInitiated) {
              let (result, url) = Self.placeRecording(source, kind: kind, id: id, folder: target,
                                                      noFolderReason: noFolderReason, pending: pending,
                                                      recoveryURL: recoveryURL, note: note)
  ```
  For example `+Recording:191` is now
  `recordingLog("Recording: stop-recording from \(name) did nothing, no recording is running")`.

- [ ] In `TidyShot/Recording/RecordingRecovery.swift`, `scan` takes the sink, defaulting to `RecordingLog.note` so every
  existing `scan(dir)` call compiles unchanged (:17-22). Replace:
  ```swift
      /// rule's 0.5 s is kept too.
      @concurrent
      static func scan(_ directory: URL) async -> [Found] {
  ```
  with:
  ```swift
      /// rule's 0.5 s is kept too. A removal is logged with `note`.
      @concurrent
      static func scan(_ directory: URL,
                       note: @Sendable (String) -> Void = { RecordingLog.note($0) }) async -> [Found] {
  ```

- [ ] In the same file, its two lines (:32-36). Replace:
  ```swift
                  do {
                      try FileManager.default.removeItem(at: url)
                      RecordingLog.note("Recording: \(url.lastPathComponent) could not be played, removed")
                  } catch {
                      RecordingLog.note("Recording: \(url.lastPathComponent) could not be played or removed: \(error.localizedDescription)")
                  }
  ```
  with:
  ```swift
                  do {
                      try FileManager.default.removeItem(at: url)
                      note("Recording: \(url.lastPathComponent) could not be played, removed")
                  } catch {
                      note("Recording: \(url.lastPathComponent) could not be played or removed: \(error.localizedDescription)")
                  }
  ```

- [ ] In the same file, `begin`'s doc (:103-106). Replace:
  ```swift
      /// is never in the list `sweepMuteFolder` goes through (Decided 2026-10-24, 6). `scanning` is
      /// `scan`, injected by tests.
  ```
  with:
  ```swift
      /// is never in the list `sweepMuteFolder` goes through (Decided 2026-10-24, 6). `scanning` is
      /// `scan`: the coordinator passes it with its `recordingLog`, and tests inject their own.
  ```
  `begin`'s signature and default are unchanged; `sweepMuteFolder`'s line (:137) keeps `RecordingLog.note`.

- [ ] Check the call sites:
  ```bash
  grep -c "RecordingLog.note" TidyShot/App/AppCoordinator+Recording.swift TidyShot/App/AppCoordinator+Recovery.swift TidyShot/App/AppCoordinator+Upload.swift TidyShot/Recording/RecordingRecovery.swift
  grep -c "recordingLog(" TidyShot/App/AppCoordinator+Recording.swift TidyShot/App/AppCoordinator+Recovery.swift TidyShot/App/AppCoordinator+Upload.swift
  grep -c 'note("Recording:' TidyShot/App/AppCoordinator+Recording.swift TidyShot/Recording/RecordingRecovery.swift
  ```
  Expected, in order: `…+Recording.swift:0`, `…+Recovery.swift:0`, `…+Upload.swift:0`, `…RecordingRecovery.swift:2`
  (`scan`'s default and the mute sweep, design 2.3); then `16`, `4`, `2`; then `…+Recording.swift:2`,
  `…RecordingRecovery.swift:3` (the two `note(` calls and `RecordingLog.note("Recording:` at :137, which the pattern
  also matches). The recorder's, the driver's, `GIFMaker`'s, `RecordingExtras`' and the mute sweep's lines still call
  `RecordingLog.note` directly.

#### The sink in the suite (design 3.3, 3.4)

- [ ] In `TidyShotTests/Support/CoordinatorFakes.swift`, `CoordinatorWorldState`'s doc (:254-255 at f991760). Replace:
  ```swift
  /// The world's values that the coordinator's `@Sendable` closures read and write: the date, the
  /// free space and the log. Locked, as a closure may run off the main actor.
  ```
  with:
  ```swift
  /// The world's values that the coordinator's `@Sendable` closures read and write: the date, the
  /// free space and the two logs. Locked, as a closure may run off the main actor.
  ```

- [ ] In the same file, the second list in `Values` (:261-262). Replace:
  ```swift
          var lines: [String] = []
      }
  ```
  with:
  ```swift
          var lines: [String] = []
          var recordingLines: [String] = []
      }
  ```

- [ ] In the same file, its getter (:277). Replace:
  ```swift
      var lines: [String] { values.withLock { $0.lines } }
  ```
  with:
  ```swift
      var lines: [String] { values.withLock { $0.lines } }
      var recordingLines: [String] { values.withLock { $0.recordingLines } }
  ```

- [ ] In the same file, its append (:286-288). Replace:
  ```swift
      func append(_ line: String) {
          values.withLock { $0.lines.append(line) }
      }
  ```
  with:
  ```swift
      func append(_ line: String) {
          values.withLock { $0.lines.append(line) }
      }

      func appendRecording(_ line: String) {
          values.withLock { $0.recordingLines.append(line) }
      }
  ```
  The class stays `nonisolated final class CoordinatorWorldState: Sendable`: the sink is `@Sendable` and `placeRecording`
  and `scan` call it off the main actor.

- [ ] In `TidyShotTests/Support/CoordinatorWorld.swift`, the world reads the second log (:106). Replace:
  ```swift
      var logLines: [String] { state.lines }
  ```
  with:
  ```swift
      var logLines: [String] { state.lines }
      /// The `Recording:` lines (`environment.recordingLog`), in order.
      var recordingLines: [String] { state.recordingLines }
  ```

- [ ] In the same file, the environment's last argument (:134). Replace:
  ```swift
              log: { line in state.append(line) })
  ```
  with:
  ```swift
              log: { line in state.append(line) },
              recordingLog: { line in state.appendRecording(line) })
  ```
  `state` is already bound to a local before the struct is built (:110).

- [ ] In the same file, the type doc names the two logs (and, as Tasks 1 and 2 added them, Clop and the Save As… panel);
  the line from `/// Nothing here reaches the system` on stays. Run from the repository root:
  ```bash
  python3 - <<'PY'
  from pathlib import Path

  # The world's type doc, whatever Tasks 1 and 2 left: every line from its first to the line before
  # `/// Nothing here reaches the system`, which stays.
  path = Path("TidyShotTests/Support/CoordinatorWorld.swift")
  lines = path.read_text().split("\n")
  first = [i for i, line in enumerate(lines) if line.startswith("/// A coordinator's world in the suite")]
  last = [i for i, line in enumerate(lines) if line.startswith("/// Nothing here reaches the system")]
  assert len(first) == 1 and len(last) == 1 and first[0] < last[0], (first, last)
  assert all(line.startswith("///") for line in lines[first[0]:last[0]]), lines[first[0]:last[0]]
  lines[first[0]:last[0]] = [
      "/// A coordinator's world in the suite (harness design 2.4): temp folders, a `UserDefaults` suite named",
      "/// after the test, settings and a save location over it, credentials in memory, the fakes, the editors",
      "/// the coordinator opens (`editors`; no window is built), Clop (`clop`, over `<root>/tmp/Clop`), the card's",
      "/// Save As… panel (`saveAsChooser`; none is built), a clock the test moves, a date it sets, free space it",
      "/// sets, the two logs it reads (`logLines`, `recordingLines`) and a destination factory. Build it in the",
      "/// suite's `init`, make the coordinator with `makeCoordinator()`, and `defer { world.removeAll() }` first",
      "/// thing in each test.",
  ]
  path.write_text("\n".join(lines))
  print("CoordinatorWorld.swift: type doc names the two logs")
  PY
  ```
  Expected: `CoordinatorWorld.swift: type doc names the two logs`, and no `AssertionError`.

- [ ] In `TidyShotTests/CoordinatorWorldTests.swift`, `aCoordinatorOverTheWorldKeepsToTheWorld` (:31): building a
  coordinator writes no `Recording:` line (design 3.4; a check, not a test). Replace:
  ```swift
          #expect(world.logLines.isEmpty)
  ```
  with:
  ```swift
          #expect(world.logLines.isEmpty)
          #expect(world.recordingLines.isEmpty)
  ```
  Task 2 added its three checks after the same line; this one goes first, directly after it, which is the order the
  design gives (`recordingLines`, `clop.runningChecks`, `clop.requests`, `saveAsChooser.asked`).

#### The tests (catalogue LOG.3 to LOG.6)

- [ ] In `TidyShotTests/CoordinatorRecordingTests.swift`, test 48's comment (:51-53), once the line is pinned (LOG.6).
  Replace:
  ```swift
      /// itself, so this does not tell the `.nothing` branch from a stray `recorder.stop()` (D24).
  ```
  with:
  ```swift
      /// itself, so the state does not tell the `.nothing` branch from a stray `recorder.stop()` (D24); the line does
      /// (`stopRecordingLogsWhatItDidInEachPhase`).
  ```

- [ ] In the same file, test 50's comment (:88-90). Replace:
  ```swift
      /// itself, so this does not see the coordinator's `isEnding` check; its log line is Tim's (D24).
  ```
  with:
  ```swift
      /// itself, so the state does not see the coordinator's `isEnding` check (D24); its log line does
      /// (`stopRecordingLogsWhatItDidInEachPhase`).
  ```
  Neither test's body changes.

- [ ] In the same file, append the four tests before the closing `}` of `struct CoordinatorRecordingTests`. Replace
  the end of the file (:374-379):
  ```swift
          try await eventually { first.hasReturned }
          #expect(!coordinator.isCapturing)
          #expect(coordinator.askingPermission == nil)
          #expect(world.notifier.calls == [.waited(.seconds(1))])
      }
  }
  ```
  with:
  ```swift
          try await eventually { first.hasReturned }
          #expect(!coordinator.isCapturing)
          #expect(coordinator.askingPermission == nil)
          #expect(world.notifier.calls == [.waited(.seconds(1))])
      }

      // MARK: The `Recording:` lines (small seams design, LOG)
      // The `Recording:` lines the coordinator writes, read from `world.recordingLines`, the environment's
      // `recordingLog`. Nothing here records; starts end at their prompt.

      /// coordinator-harness:27 (:27), full; recording-r4:347 (:422), full. `stop-recording`'s line in each phase: nothing
      /// to stop while idle, during a selection (the capture lock held, the phase still idle) and while a recording is
      /// saved; the count-in cancelled; the recording stopped; and a second one during the stop wait finds the recording
      /// ending (`recorder.isEnding`) and does nothing. The `did nothing` lines are the coordinator's own two branches,
      /// which the state alone cannot tell from the recorder's (D24). Nothing stays by hand.
      @Test func stopRecordingLogsWhatItDidInEachPhase() async throws {
          defer { world.removeAll() }
          let coordinator = world.makeCoordinator()

          coordinator.stopRecordingCommand(sender: "Raycast")

          // The lock held as during Record Screen's area selection: the phase is still idle.
          let gate = TestGate()
          let lock = Task { await coordinator.withCaptureLock(coversDesktop: false) { await gate.wait() } }
          defer { lock.cancel() }
          try await eventually { gate.isWaiting }
          coordinator.stopRecordingCommand(sender: "Keyboard Maestro")
          #expect(coordinator.isCapturing)
          gate.open()
          let lockEnded = TaskWatch(lock)
          try await eventually { lockEnded.hasReturned }

          coordinator.recordingSavesInFlight = 1
          coordinator.stopRecordingCommand(sender: nil)
          coordinator.recordingSavesInFlight = 0

          coordinator.recordingCountIn = true
          let countdown = try await beginCountdown(on: coordinator)
          defer { countdown.cancel() }
          coordinator.stopRecordingCommand(sender: "Raycast")
          let ended = TaskWatch(countdown)
          try await eventually { ended.hasReturned }
          #expect(coordinator.recordingStartCancelled)
          coordinator.recordingCountIn = false

          let run = await beginRecording(on: coordinator)
          defer { run.cancel() }
          coordinator.stopRecordingCommand(sender: "Raycast")
          #expect(coordinator.recorder.isEnding)
          coordinator.stopRecordingCommand(sender: "Raycast")
          let runEnded = TaskWatch(run)
          try await eventually { runEnded.hasReturned }

          #expect(world.recordingLines == [
              "Recording: stop-recording from Raycast did nothing, no recording is running",
              "Recording: stop-recording from Keyboard Maestro did nothing, no recording is running",
              "Recording: stop-recording from an unknown app did nothing, no recording is running",
              "Recording: stop-recording from Raycast cancelled the count-in",
              "Recording: stop-recording from Raycast stopped the recording",
              "Recording: stop-recording from Raycast did nothing, no recording is running",
          ])
          #expect(world.driver.stopCount == 1)
          #expect(!coordinator.recorder.isRunning)
          #expect(world.notifier.calls.isEmpty)
          #expect(world.logLines.isEmpty)
      }

      /// recording-r3:156 (:161), full; recording-r3:419 (:457), in part (a start's lines: the order, each answer's text,
      /// the ignored press). With the microphone and the camera both undecided, a start asks for the microphone, then the
      /// camera, and logs each answer; a second Record press while the camera prompt is up does nothing and logs why. A
      /// quit while it is up ends the start once it is answered, before the capture lock, so nothing makes
      /// `tmp/Recording`. Stays, of :457: the prompts on screen (by hand, Tim's) and the URL handler's own
      /// `URL command from … dropped, the camera prompt is open` line (URLCommandHandler.swift:155, `NSLog`; `URLLOG`'s).
      @Test func aStartLogsEachPromptsAnswerAndASecondPressWhileOneIsUp() async throws {
          defer { world.removeAll() }
          world.settings.recordingMicrophone = MicrophoneChoice.systemDefaultValue
          world.settings.recordingWebcamBubble = true
          world.settings.hideDesktopIconsWhileCapturing = false
          let microphones = HeldMicrophoneDevices()
          let cameras = HeldCameraDevices()
          world.microphones = microphones
          world.cameras = cameras
          let coordinator = world.makeCoordinator()

          let start = Task { await coordinator.recordFullscreen() }
          defer { start.cancel() }
          let started = TaskWatch(start)
          try await eventually { microphones.isAsking }
          #expect(cameras.requestCount == 0)
          microphones.answer(true)
          try await eventually { cameras.isAsking }
          #expect(coordinator.askingPermission == .camera)

          let second = TaskWatch(Task { await coordinator.recordScreen() })
          try await eventually { second.hasReturned }
          #expect(microphones.requestCount == 1)
          #expect(cameras.requestCount == 1)

          // Gated as the GIF test's quit is (D31): the deferred answer frees the start either way.
          do {
              defer { cameras.answer(false) }
              let quit = TaskWatch(Task { await coordinator.finishRecordingForQuit() })
              try await eventually { quit.hasReturned }
          }
          try await eventually { started.hasReturned }

          #expect(world.recordingLines == [
              "Recording: microphone access allowed at the prompt",
              "Recording: start ignored, the camera prompt is open",
              "Recording: camera access refused at the prompt",
          ])
          #expect(!coordinator.isCapturing)
          #expect(coordinator.askingPermission == nil)
          #expect(world.notifier.calls == [.waited(.seconds(1))])
          #expect(world.logLines.isEmpty)
      }

      /// recording-r3:162 (:167), in part; recording-r4:214 (:218), in part; recording-r3:419 (:457), in part (the Settings
      /// prompt's lines: both answers, and `deferred` with its reason). Settings' prompt logs its answer when it asks, and
      /// why it waits when it does not: a recording being saved (a GIF converting), a capture holding the lock, a
      /// recording running inside the lock as the app runs one, or another prompt open. Only the first two asks prompt.
      /// Stays: of :167, the microphone pick in Settings reaching the coordinator, and of :218, the `Show webcam bubble`
      /// toggle reaching it, each a view's call on `AppCoordinator.shared` (CaptureSettingsView.swift:222, :253), by
      /// hand (Tim's), no seam; :218's GIF conversion is set up as `.saving`. Of :457, as the start test says: the prompts
      /// on screen (by hand) and the handler's `dropped` line (`URLLOG`'s).
      @Test func aSettingsPromptLogsItsAnswerOrWhyItWaits() async throws {
          defer { world.removeAll() }
          let cameras = HeldCameraDevices()
          world.cameras = cameras
          let microphones = FakeMicrophoneDevices(access: .notDetermined)
          world.microphones = microphones
          let coordinator = world.makeCoordinator()
          // An ask that must not prompt runs as its own task, gated: one that prompted after all would wait for an
          // answer that never comes (or is a second entry, an issue), so the test fails in two seconds.
          func askWithoutAPrompt(_ prompt: PermissionPrompt) async throws {
              let ask = TaskWatch(Task { await coordinator.requestAccessFromSettings(prompt) })
              try await eventually { ask.hasReturned }
          }

          let refusedAsk = Task { await coordinator.requestAccessFromSettings(.camera) }
          defer { refusedAsk.cancel() }
          let refused = TaskWatch(refusedAsk)
          try await eventually { cameras.isAsking }
          #expect(coordinator.askingPermission == .camera)
          cameras.answer(false)
          try await eventually { refused.hasReturned }

          let allowedAsk = Task { await coordinator.requestAccessFromSettings(.camera) }
          defer { allowedAsk.cancel() }
          let allowed = TaskWatch(allowedAsk)
          try await eventually { cameras.isAsking }
          #expect(coordinator.askingPermission == .camera)
          cameras.answer(true)
          try await eventually { allowed.hasReturned }

          coordinator.recordingSavesInFlight = 1
          #expect(coordinator.recordingPhase == .saving)
          try await askWithoutAPrompt(.camera)
          coordinator.recordingSavesInFlight = 0

          // The lock held, as a selection holds it, and still held through the recording below, as the app holds it
          // for the whole of one.
          let gate = TestGate()
          let lock = Task { await coordinator.withCaptureLock(coversDesktop: false) { await gate.wait() } }
          defer { lock.cancel() }
          let lockEnded = TaskWatch(lock)
          try await eventually { gate.isWaiting }
          try await askWithoutAPrompt(.camera)

          let run = await beginRecording(on: coordinator)
          defer { run.cancel() }
          #expect(coordinator.recordingPhase == .recording)
          #expect(coordinator.isCapturing)
          try await askWithoutAPrompt(.microphone)
          try await askWithoutAPrompt(.camera)
          coordinator.recorder.stop()
          let runEnded = TaskWatch(run)
          try await eventually { runEnded.hasReturned }
          gate.open()
          try await eventually { lockEnded.hasReturned }

          coordinator.askingPermission = .microphone
          try await askWithoutAPrompt(.camera)
          coordinator.askingPermission = nil

          #expect(world.recordingLines == [
              "Recording: camera access refused at the Settings prompt",
              "Recording: camera access allowed at the Settings prompt",
              "Recording: camera prompt from Settings deferred, a recording is being saved",
              "Recording: camera prompt from Settings deferred, a capture is running",
              "Recording: microphone prompt from Settings deferred, a capture is running",
              "Recording: camera prompt from Settings deferred, a capture is running",
              "Recording: camera prompt from Settings deferred, the microphone prompt is open",
          ])
          #expect(cameras.requestCount == 2)
          #expect(microphones.requestCount == 0)
          #expect(coordinator.askingPermission == nil)
          #expect(world.logLines.isEmpty)
      }

      /// recording-r4:366 (:456), full; recording-r4:192 (:193), in part (the coordinator's text, which the line accepts).
      /// Two `record-screen` URLs back to back through the handler: the first starts and parks at the camera prompt,
      /// before the lock; the second comes before that start runs, finds `urlRecordingStartPending` and is logged;
      /// nothing posts. One sent once the app quits is logged too. Stays, of :193: the one selection on screen, the
      /// drawn UI, by hand (Tim's), no seam.
      @Test func aSecondURLStartBeforeTheFirstTakesTheLockIsLogged() async throws {
          defer { world.removeAll() }
          world.settings.recordingWebcamBubble = true
          world.settings.hideDesktopIconsWhileCapturing = false
          let cameras = HeldCameraDevices()
          world.cameras = cameras
          let coordinator = world.makeCoordinator()
          let handler = URLCommandHandler(settings: world.settings, target: coordinator,
                                          screens: { URLCommandHandler.Screens(displays: [], pointerIndex: nil) },
                                          post: { notice in Issue.record("The URL handler posted \(notice.body)") })
          await handler.ready()
          let url = try #require(URL(string: "tidyshot://record-screen"))

          // One task, so nothing runs between the two: a `record-screen` reaches `startRecording` with no
          // suspension, and the first one's start task runs only after both.
          let sends = Task {
              await handler.handle(url, sender: "Keyboard Maestro")
              await handler.handle(url, sender: "Keyboard Maestro")
          }
          defer { sends.cancel() }
          let sent = TaskWatch(sends)
          try await eventually { sent.hasReturned }
          try await eventually { cameras.isAsking }
          #expect(coordinator.urlRecordingStartPending)
          #expect(cameras.requestCount == 1)
          #expect(world.notifier.calls.isEmpty)

          // Gated as the GIF test's quit is (D31).
          do {
              defer { cameras.answer(false) }
              let quit = TaskWatch(Task { await coordinator.finishRecordingForQuit() })
              try await eventually { quit.hasReturned }
          }
          try await eventually { !coordinator.urlRecordingStartPending }
          coordinator.startRecording(intent: CaptureIntent(action: .save), preselect: nil)

          #expect(world.recordingLines == [
              "Recording: URL start ignored, a recording is starting",
              "Recording: camera access refused at the prompt",
              "Recording: URL start ignored, the app is quitting",
          ])
          #expect(cameras.requestCount == 1)
          #expect(!coordinator.isCapturing)
          #expect(world.notifier.calls == [.waited(.seconds(1))])
          #expect(world.logLines.isEmpty)
      }
  }
  ```
  What holds for all four (LOG.2): each list is asserted whole with `==`, and `world.logLines.isEmpty` beside it, since
  none of these paths calls the coordinator's own `log(_:)`; the recorder's own lines (it keeps `RecordingLog.note`) never
  appear. No test passes `recordingCanStart` (+Recording:354-378, the live `tmp/Recording`): every start parks at a held
  prompt and is ended by a quit in the D31 form, with the answer deferred so it frees the start either way. Every held
  task is cancelled in a `defer` right after it is made and gated with `TaskWatch` and `eventually`; nothing awaits a
  held call. An ask that must not prompt runs as its own gated task, so one that prompted after all fails in two seconds
  (`SingleWaiter`'s second entry is an issue). In `aSettingsPromptLogsItsAnswerOrWhyItWaits` the two prompting asks are
  sequential on one `HeldCameraDevices` (single-entry, not single-use: `resume` clears the waiter, CoordinatorFakes.swift:411-415),
  and the recording runs inside the held capture lock as `record()` runs inside `withCaptureLock` in the app
  (+Recording:211-233), so its reason is `isCapturing`'s (+Recording:93), not the fallback at :107-108. The second URL
  in `aSecondURLStartBeforeTheFirstTakesTheLockIsLogged` reaches the coordinator's line, not the handler's `dropped`
  line: `run` has no suspension between its `captureRefusal` read and `target.startRecording` for a `record-screen`
  without a rect (URLCommandHandler.swift:154-160), both `handle` calls run in one task, and `captureRefusal` does not
  read `urlRecordingStartPending` (AppCoordinator.swift:542-554).

- [ ] In `TidyShotTests/RecordingRecoveryTests.swift`, insert the test before `anMP4BesideAPartialGIFIsFoundAndTheGIFRemoved`.
  Replace:
  ```swift
      /// A crash during a GIF's conversion leaves the MP4 and a partial GIF: the MP4 is recovered
  ```
  with:
  ```swift
      /// recording-r1:263 (:277), full: the relaunch and the junk file are the set-up. A leftover that does not play
      /// (`echo junk > "$C/tmp/Recording/x.mp4"`) is removed and logged by its name through `scan`'s `note`; a
      /// playable file beside it is found, kept and not logged. That `start()` hands `scan` the environment's
      /// `recordingLog` is read from the code, not driven (`TMPDIRS`, `LAUNCH`); nothing of the line stays by hand.
      @Test func aLeftoverThatDoesNotPlayIsRemovedAndLogged() async throws {
          defer { try? FileManager.default.removeItem(at: dir) }
          let junk = dir.appending(path: "x.mp4")
          try Data("junk\n".utf8).write(to: junk)
          let playable = dir.appending(path: "\(UUID().uuidString).mp4")
          try await VideoFixtures.makeMP4(at: playable, width: 320, height: 200, seconds: 1, audio: false)
          let lines = LogLines()

          let found = await RecordingRecovery.scan(dir, note: { line in lines.lines.withLock { $0.append(line) } })

          #expect(found.map(\.url.lastPathComponent) == [playable.lastPathComponent])
          #expect(!FileManager.default.fileExists(atPath: junk.path(percentEncoded: false)))
          #expect(FileManager.default.fileExists(atPath: playable.path(percentEncoded: false)))
          #expect(lines.lines.withLock { $0 } == ["Recording: x.mp4 could not be played, removed"])
      }

      /// A crash during a GIF's conversion leaves the MP4 and a partial GIF: the MP4 is recovered
  ```
  The suite has no world: `dir` is its own fresh folder (:12-15), removed in the test's `defer`; `LogLines` collects
  through `note:`. No coordinator, no `tmp/Recording`, no `start()`.

#### Runs, the Release build and the commit

- [ ] Run the three suites this task touches:
  ```bash
  xcodegen generate && xcodebuild test -project TidyShot.xcodeproj -scheme TidyShot -destination 'platform=macOS' -derivedDataPath .build -only-testing:TidyShotTests/CoordinatorRecordingTests -only-testing:TidyShotTests/RecordingRecoveryTests -only-testing:TidyShotTests/CoordinatorWorldTests 2>&1 | grep -E "Test run with|error:|TEST"
  ```
  Expected: `✔ Test run with 39 tests in 3 suites passed after …` (`CoordinatorRecordingTests` 12 + 4,
  `RecordingRecoveryTests` 21 + 1, `CoordinatorWorldTests` 1) and `** TEST SUCCEEDED **`. The `error:` lines that print
  are the known noise only (the `iOSSimulator: … sharedServiceContextForDeveloperDir:error:` line and
  `com.apple.linkd.autoShortcut`).

- [ ] Run the full suite:
  ```bash
  xcodegen generate && xcodebuild test -project TidyShot.xcodeproj -scheme TidyShot -destination 'platform=macOS' -derivedDataPath .build 2>&1 | grep -E "Test run with|error:|TEST"
  ```
  Expected: `✔ Test run with 2352 tests in 195 suites passed after …` and `** TEST SUCCEEDED **`, with only the known
  noise lines (`History file could not be read or decoded, setting it aside` twice, `com.apple.linkd.autoShortcut`,
  about 40 `mdb_txn_commit error: MDB_MAP_FULL`, the `iOSSimulator: …` line). A run that fails only on
  `UploadQueueTests.aSidecarUnwritableDuringThePartsFailsTheJobBeforeComplete` is rerun once and must then pass.

- [ ] Run the Release build:
  ```bash
  xcodegen generate && xcodebuild -project TidyShot.xcodeproj -scheme TidyShot -configuration Release -derivedDataPath .build-rel build 2>&1 | grep -E "error:|warning:|BUILD"
  ```
  Expected: `** BUILD SUCCEEDED **`, and no `error:` or `warning:` line beyond the two tool lines (`iOSSimulator: …
  sharedServiceContextForDeveloperDir:error:` and `appintentsmetadataprocessor[…] warning: Metadata extraction skipped,
  no AppIntents.framework dependency found`). Any other line, for example a Swift concurrency warning about the
  `@Sendable` sink in `AppCoordinator+Recording.swift` or `RecordingRecovery.swift`, is a failure: stop and report it.

- [ ] Check the diff:
  ```bash
  git diff --numstat
  git diff --numstat f991760 -- TidyShot/App/AppEnvironment.swift TidyShotTests/Support/CoordinatorWorld.swift
  git diff --stat f991760 -- TidyShot/ | tail -1
  git status --short
  ```
  Expected: the first lists exactly these twelve files, ten of them with these counts (the other two depend on how
  Tasks 1 and 2 worded the two doc comments this task rewrites, and are checked by the second command):
  ```
  23	22	TidyShot/App/AppCoordinator+Recording.swift
  4	4	TidyShot/App/AppCoordinator+Recovery.swift
  2	2	TidyShot/App/AppCoordinator+Upload.swift
  8	1	TidyShot/App/AppCoordinator.swift
  …	…	TidyShot/App/AppEnvironment.swift
  6	5	TidyShot/Recording/RecordingRecovery.swift
  1	0	TidyShot/Recording/ScreenRecordingDriver.swift
  250	2	TidyShotTests/CoordinatorRecordingTests.swift
  1	0	TidyShotTests/CoordinatorWorldTests.swift
  20	0	TidyShotTests/RecordingRecoveryTests.swift
  7	1	TidyShotTests/Support/CoordinatorFakes.swift
  …	…	TidyShotTests/Support/CoordinatorWorld.swift
  ```
  The second prints `31	5	TidyShot/App/AppEnvironment.swift` and `20	4	TidyShotTests/Support/CoordinatorWorld.swift`
  (the three seams together, as the design's built tree has them). The third ends
  `9 files changed, 94 insertions(+), 52 deletions(-)` (design 2.4). `git status --short` lists the twelve files as
  ` M` and nothing else. If a count differs, compare the file with this task's steps and with Tasks 1 and 2's and report
  the difference; do not edit to make a number match.

- [ ] Commit:
  ```bash
  git add TidyShot/App/AppEnvironment.swift TidyShot/App/AppCoordinator.swift TidyShot/App/AppCoordinator+Recording.swift TidyShot/App/AppCoordinator+Recovery.swift TidyShot/App/AppCoordinator+Upload.swift TidyShot/Recording/RecordingRecovery.swift TidyShot/Recording/ScreenRecordingDriver.swift TidyShotTests/Support/CoordinatorFakes.swift TidyShotTests/Support/CoordinatorWorld.swift TidyShotTests/CoordinatorWorldTests.swift TidyShotTests/CoordinatorRecordingTests.swift TidyShotTests/RecordingRecoveryTests.swift
  git commit -m "refactor: the coordinator's Recording: lines through AppEnvironment.recordingLog, scan's note, five log tests"
  ```
  No attribution lines and no session URL in the message; do not push. The report says no hand check was run (design
  section 9, check 3, is Tim's).

### Task 4: The marks, seams.md, the hand-check checklist, the built notes [mechanical]

**Files:**
- Modify the nine checklists that hold a marked line, with the count of lines marked in each: `docs/testing/coordinator-harness-manual-checklist.md` (1), `coordinator-split-manual-checklist.md` (1), `phase-6a-manual-checklist.md` (8), `phase-7-clop-manual-checklist.md` (13), `recording-r1-manual-checklist.md` (7), `recording-r2-manual-checklist.md` (3), `recording-r3-manual-checklist.md` (3), `recording-r4-manual-checklist.md` (8), `small-tweaks-manual-checklist.md` (2): 46 lines, 28 full and 18 part (catalogue `tests-small.md` section 7.2). 41 are marked for the first time and 5 carry a mark already that the script rewrites in place (coordinator-split:44, phase-6a:198 and :199, recording-r4:253 and :255). A sixth existing mark, recording-r4:217 (deferred, in `recording-r4-manual-checklist.md`), gains its by-hand part, so the script edits 47 items in all. recording-r3:416 and :436 (deferred to `EXTRAS`) stay unmarked.
- Modify `docs/superpowers/notes/2026-10-30-checklist-sweep/seams.md` (design 11 items 1 to 3; its rules at :9-12, its table, its sections, the multi-seam section at :898 and the three-or-fewer section at :948).
- Create `docs/testing/small-seams-manual-checklist.md` (design 9's three checks, in the form of `docs/testing/editor-seam-manual-checklist.md`).
- Modify `docs/superpowers/specs/2026-10-31-tidyshot-small-seams-design.md` (section 12 gains one paragraph: the branch's suite line and Release result).

**Interfaces:**
- Consumes (Tasks 1 to 3): the new tests the marks name, each as `func <name>(` in `TidyShotTests/<Suite>.swift` (the marks script's check, as CT-2's Task 8): `CoordinatorClopTests` (all 15; `aClopThatIsNotRunningOrSkipsUploadsTheOriginalWithOneLine(reason: ClopSkipReason, line: String)` and `aRecordingUploadsItsOriginalWithoutOptimizingWhenClopIsOffOrNotRunning(setting:running:)` are parameterized and are named without their labels), `CoordinatorTrimTests.anUploadTrimmedWithClopWhoseFileChangedAsksClopAgainAndSendsTheSecondTrim`, `CoordinatorEditorUploadTests.anEditorUploadAndUploadAsNewEachSendClopsBytesAndTheLinkKeepsItsKey` and `.saveAsAfterAnEditorUploadOfAnUploadOnlyCaptureWritesTheEditDuringAndAfterThePut`, `CoordinatorSaveTests.anMP4sSizeIsTheMovedFilesSize`, `CoordinatorEditorSaveTests.saveAsAfterASaveOverTheFileWritesTheEditNotTheOriginal`, `CoordinatorSaveAsTests` (the 8 line tests; E1 covers no line and is not named), `CoordinatorRecordingTests` (4) and `RecordingRecoveryTests.aLeftoverThatDoesNotPlayIsRemovedAndLogged`. The marks name 33 of the 34 new tests (SAVEAS E1 covers no line).
- Consumes (existing, `func <name>(` checked at f991760): `AppSettingsTests.optimiseWithClopDefaultsOffAndPersists` (AppSettingsTests.swift:240), `ClopOptimiserTests.notSmallerReportedByClopReturnsNotSmaller` (:128), `.anotherPathReturnsConverted` (:148), `.throwingTransportReturnsFailed` (:116), `CoordinatorDeleteTests.deleteDuringAnUploadCancelsItThenDeletesTheReservedKey(onAReplacedLane: Bool)` (:368), `CoordinatorUploadTests.anOutdatedKeptClopCopyCountsAsAChangedSource` (:214), `.anUploadedResumeClearsItsStateSidecarAndKeptCopy` (:263), `.anUploadedUploadOnlyImageMovesToItsDragFolderOnlyWithACard(cardShowing: Bool)` (:290), `.aFailedUploadOnlyImageKeepsItsPendingFileAndSizeUntilARetrySendsIt` (:534), `RecentCaptureFormattingTests.detailIsTheTimeAndTheSize` (:229), `CoordinatorEditorTests.annotateFromACardOrRecentCapturesLeavesNothingToRestore` (:514), `.anUploadedUploadOnlyCardsCopyImageAndAnnotateReadTheDragCopy` (:617), `CoordinatorRecordActionsTests.copyImageReadsTheFileOrDownloadsTheObject(source: Source)` (:75), `CoordinatorEditorSaveTests.saveOverTheFileRemovesTheDragCopyAndEveryReadGivesTheEdit` (:494), `CoordinatorEditorUploadTests.uploadOfAnUploadOnlyCaptureRemovesItsDragCopyAndEveryReadGivesTheEdit` (:875), `EditorNamingTests.uploadOnlyCaptureWithoutAKeySuggestsTheTemplateName` (:63), `.counterUsesTheCurrentValue` (:48), `.aGIFPanelAllowsGIFOnly` (:163), `QuickAccessModelTests.aGIFHasNoImageActionsCopiesItsFileAndHasTheGIFBadge` (:93), `CoordinatorDragOutTests.aDragOfAShowingUploadedRecordingStartsOneDownload` (:81), `CoordinatorSaveTests.aCaptureWithTheOverlayOffShowsNoCardAndStillUploads` (:79), `CaptureRecordTests.mediaKindTypes` (:618), `UploadQueueTests.uploadsAndReportsPublicURL` (:63), `ShortcutsTests.aStartAsksForTheMicrophoneThenTheCamera` (:110) and `CoordinatorRecordingTests.recordingProceedsOnlyWhenStartedNotQuittingAndNotCancelled` (:129).
- Produces: nothing a later task uses.

**Tests:** none added; the suite is unchanged. The tests' doc comments, which name their checklist lines by key and current line and say for an in-part line what stays and whose (`lines-small.md`), are Tasks 1 to 3's. This task's marks say the same in their `by hand:` text, taken from the catalogue's merged marks.
- The marks script, in the form of CT-2's Task 8 (`docs/superpowers/plans/2026-10-30-editor-seam.md`, Task 8, Step 2): a `MARKS` table keyed by checklist and anchor text, one match per anchor asserted (first with `grep -c -F`), every named test found, none of the 41 first-time lines already marked, the 5 existing marks read back exactly as they stand before they are replaced, 28 full and 18 part. It prints `46 lines marked, 1 deferred line's mark extended`.
- The seams.md script asserts: 42 seams; 279 B lines; Lines 410, Alone 182, Completes 279; 97 lines need two or more seams; 15 seams unlock three or fewer; the first three seams complete 78 lines and the first ten 150; the rows `CAPSRC` 34 / 8 / 8 (fourth), `CLOP` 23 / 22 / 22 (fifth), `SAVEAS` 14 / 7 / 8 (sixth), `SCREENS` 14 / 6 / 10 (eighth), `TMPDIRS` 13 / 7 / 8 (ninth), `LOG` 12 / 7 / 8 (tenth), `PINS` 10 / 5 / 9, `URLLOG` 4 / 2 / 4 (27th, ahead of `CHROMEMAP`) as Lines / Alone / Completes, every other row unchanged; 6 new seam slots (design 11 item 2).
- Full suite, unchanged: `Test run with 2352 tests in 195 suites passed`. The Release build at the end: `** BUILD SUCCEEDED **`, no `error:` or `warning:` line beyond the two tool lines the Global Constraints name. `git diff --stat main -- project.yml` prints nothing, and `git diff --name-only main -- TidyShot/` lists the nine files Tasks 1 to 3 changed.

**Commit:** `docs: small seams marks, seams.md, the hand-check checklist and close-out`

**Steps:**

No test is added, and nothing under `TidyShot/` or `TidyShotTests/` changes. The plan indents its code blocks by two
spaces; a script or heredoc is written without that indent. Every step runs from the repository root
on `small-seams` after Task 3's commit. The marks go on the checklist text as it is at f991760 (Tasks 1 to 3 change no
document), found by text; the seams.md edit works from seams.md's own lists and the design's section 11. The three
scripts are written to `/private/tmp/claude-501/ct3plan-task4/` so that each can be run twice (the marks script on its
anchors first, the seams script on a copy first). No step runs the app; the hand checks are Tim's.

- [ ] **Step 1: Check the starting point.**
  ```bash
  git status --short; git log -1 --format=%s; git diff --stat f991760 -- docs/testing docs/superpowers/notes docs/superpowers/specs project.yml
  mkdir -p /private/tmp/claude-501/ct3plan-task4
  ```
  Expected: `git status --short` prints nothing; the subject is Task 3's commit message; the diff prints nothing. If the
  diff lists a file, stop and ask: the scripts below assert f991760's text of these files.

- [ ] **Step 2: Write the marks script and check its anchors.** One entry per marked line: the checklist, the
  catalogue key's line number at e011d2f (as `lines-small.md` names it), an anchor (the start of the item's text,
  checked to occur on exactly one line of its checklist at f991760), and the mark. A mark is the catalogue's merged
  mark (`tests-small.md` CLOP.5 for CLOP, the "Merged mark" lines of SAVEAS.3 and SAVEAS.4 and the merged mark of
  SAVEAS.5 for SAVEAS, LOG.8 for LOG): `(suite: Suite.test, …)` for a full line and `(suite, in part: Suite.test, …;
  by hand: <what stays>)` for a part line, whose by-hand text names the other seam in parentheses where there is one.
  The script places a mark as CT-2's Task 8 did: at the end of the item's last line, wrapped at 120 columns with
  two-space continuation lines, or on new continuation lines when that line is longer than 120, with a closing
  `______` kept last. For the 5 lines that carry a mark already and for recording-r4:217 it first cuts the existing
  note, after asserting that it reads exactly as the table says, and then places the new one, so each of the six
  carries one `(suite` note afterwards. It asserts that each anchor matches one line and that line starts an item,
  that every test a mark names is `func <name>(` in `TidyShotTests/<Suite>.swift`, that none of the 41 first-time
  lines carries a mark or an `(obsolete: ` note already, that recording-r3:416 and :436 stay unmarked, and that there
  are 28 full and 18 part marks in the nine checklists' counts.
  ```bash
  cat > /private/tmp/claude-501/ct3plan-task4/marks.py <<'EOF'
  import re
  import subprocess
  import sys
  from pathlib import Path

  ROOT = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(".")

  # (checklist, catalogue key's line at e011d2f, text that occurs once in the checklist at f991760, mark).
  # Each mark is the merged mark of tests-small.md (CLOP.5, the SAVEAS entries and SAVEAS.4, LOG.8), design section 6.
  MARKS = [
      ('phase-7-clop', 21, 'The toggle takes effect without Save: turn it on, close',
       '(suite, in part: CoordinatorClopTests.turningClopOffDuringAnOptimisationKeepsThatUploadOptimisedAndNotTheNext, AppSettingsTests.optimiseWithClopDefaultsOffAndPersists; by hand: closing Settings with no Save and `defaults read` of the real domain)'),
      ('phase-7-clop', 28, 'Editor Upload (same link), the same-key replace, Upload as New',
       '(suite: CoordinatorEditorUploadTests.anEditorUploadAndUploadAsNewEachSendClopsBytesAndTheLinkKeepsItsKey, CoordinatorClopTests.turningClopOffDuringAnOptimisationKeepsThatUploadOptimisedAndNotTheNext)'),
      ('phase-7-clop', 29, 'Upload-only mode (After capture: `Upload only, keep no local file`): the object',
       '(suite: CoordinatorClopTests.aCaptureWhoseUploadFailsAfterClopKeepsItsPendingFileAtTheCapturedSize, .turningClopOffDuringAnOptimisationKeepsThatUploadOptimisedAndNotTheNext)'),
      ('phase-7-clop', 31, 'A capture that Clop cannot shrink (upload a plain white fill',
       '(suite: CoordinatorClopTests.aClopThatIsNotRunningOrSkipsUploadsTheOriginalWithOneLine, ClopOptimiserTests.notSmallerReportedByClopReturnsNotSmaller)'),
      ('phase-7-clop', 32, 'A key template with `{counter}`: three captures in a row get',
       '(suite: CoordinatorClopTests.threeUploadsWithAnImageHeldInClopTakeCountersInStartOrder)'),
      ('phase-7-clop', 35, 'Quit Clop, toggle on, capture: the original uploads',
       '(suite: CoordinatorClopTests.aClopThatIsNotRunningOrSkipsUploadsTheOriginalWithOneLine)'),
      ('phase-7-clop', 36, 'Clop set to convert PNG to another format (Clop > Settings',
       '(suite: CoordinatorClopTests.aClopThatIsNotRunningOrSkipsUploadsTheOriginalWithOneLine, ClopOptimiserTests.anotherPathReturnsConverted)'),
      ('phase-7-clop', 37, 'Free-tier Clop past its cap, if you can reach it',
       '(suite: CoordinatorClopTests.aClopThatIsNotRunningOrSkipsUploadsTheOriginalWithOneLine, ClopOptimiserTests.throwingTransportReturnsFailed)'),
      ('phase-7-clop', 41, 'Delete while Clop is optimising a large scrolling capture',
       '(suite: CoordinatorClopTests.deletingAnImageWhileClopHoldsItCancelsAtOnceAndNothingUploads)'),
      ('phase-7-clop', 42, 'The same Delete where the record is kept: make the file removal',
       '(suite: CoordinatorClopTests.aDeleteDeclinedAtTheSecondAlertWhileClopHoldsLeavesTheCardCancelledAndARetryUploadsOnce)'),
      ('phase-7-clop', 43, 'With the file removal made to fail as above, Delete, decline',
       '(suite: CoordinatorClopTests.aRetryBeforeClopsFirstAnswerUploadsOnceFromTheSecondAttempt)'),
      ('phase-7-clop', 44, 'Change upload settings during optimisation: start the 65,536',
       '(suite: CoordinatorClopTests.changingUploadSettingsWhileClopHoldsAnUploadFinishesItAtItsOwnDestination)'),
      ('phase-7-clop', 45, 'Toggle the setting off while an optimisation runs',
       '(suite: CoordinatorClopTests.turningClopOffDuringAnOptimisationKeepsThatUploadOptimisedAndNotTheNext)'),
      ('recording-r1', 271, 'Delete (and confirm) during the upload cancels it and removes',
       '(suite: CoordinatorDeleteTests.deleteDuringAnUploadCancelsItThenDeletesTheReservedKey, CoordinatorClopTests.deletingARecordingWhileClopHoldsItCancelsAtOnceAndLeavesNoMovieOrCounterGap)'),
      ('recording-r1', 296, 'Cleanup. `ls $C/tmp/Clop` is empty after an optimised upload',
       "(suite, in part: CoordinatorClopTests.aFailedRecordingUploadAfterClopLeavesNoMovieAndARetryAsksClopAgainFromTheOriginal, .deletingARecordingWhileClopHoldsItCancelsAtOnceAndLeavesNoMovieOrCounterGap; by hand: the real container's tmp/Clop and the launch sweep of it (`TMPDIRS`))"),
      ('recording-r1', 297, 'Clop off: the original uploads and the card never says `Optimizing…`',
       '(suite: CoordinatorClopTests.aRecordingUploadsItsOriginalWithoutOptimizingWhenClopIsOffOrNotRunning)'),
      ('recording-r1', 330, "3. Counter: for a recording's upload, `{counter}` is drawn after the 625 GB",
       '(suite: CoordinatorClopTests.deletingARecordingWhileClopHoldsItCancelsAtOnceAndLeavesNoMovieOrCounterGap)'),
      ('recording-r2', 275, 'Clop on and running, then a GIF: it uploads as made.',
       '(suite, in part: CoordinatorClopTests.aGIFUploadsAsMadeWithOneClopLinePerLaunch, .anMP4RecordingGoesThroughClopShowingOptimizingAndUploadsClopsMovie; by hand: `cmp` against the bucket object and the real stderr)'),
      ('recording-r4', 253, 'Clop on, `Upload Trimmed` on a trimmed file over 100 MiB',
       '(suite, in part: CoordinatorUploadTests.anOutdatedKeptClopCopyCountsAsAChangedSource, CoordinatorTrimTests.anUploadTrimmedWithClopWhoseFileChangedAsksClopAgainAndSendsTheSecondTrim; by hand: the link playing the second trim)'),
      ('recording-r4', 255, 'A Clop result kept in `multipart/<id>.mp4` is used by Retry',
       '(suite: CoordinatorClopTests.aRecordingOverThePartThresholdKeepsClopsMovieAndARetryResumesWithoutClop, .aClopMovieThatCannotBeKeptForResumeLogsItAndSendsTheThrowawayCopy, CoordinatorUploadTests.anUploadedResumeClearsItsStateSidecarAndKeptCopy)'),
      ('recording-r4', 323, "16. Clop's result is kept in `multipart/<id>.mp4`",
       '(suite: CoordinatorClopTests.aRecordingOverThePartThresholdKeepsClopsMovieAndARetryResumesWithoutClop, CoordinatorUploadTests.anUploadedResumeClearsItsStateSidecarAndKeptCopy)'),
      ('small-tweaks', 14, 'Upload a capture with Clop on: after the upload, the row shows',
       '(suite: CoordinatorClopTests.turningClopOffDuringAnOptimisationKeepsThatUploadOptimisedAndNotTheNext)'),
      ('small-tweaks', 15, 'A recording row shows its size after it saves, and the optimised',
       '(suite: CoordinatorClopTests.anMP4RecordingGoesThroughClopShowingOptimizingAndUploadsClopsMovie, CoordinatorSaveTests.anMP4sSizeIsTheMovedFilesSize, RecentCaptureFormattingTests.detailIsTheTimeAndTheSize)'),
      ('coordinator-split', 44, "Pin, then the pin menu's three items [`+Pins`, `+R",
       "(suite, in part: CoordinatorEditorTests.annotateFromACardOrRecentCapturesLeavesNothingToRestore, CoordinatorRecordActionsTests.copyImageReadsTheFileOrDownloadsTheObject, CoordinatorSaveAsTests.saveAsOfASavedImageCopiesItsBytesAndChangesNothingElse (the Save As… item's suggestion and Cancel, through `saveAs(recordID:)`, which the pin's menu calls); by hand: the pin, its second click and `Close Pinned Screenshots` (`PINS`, `SCREENS`), reaching Save As… through the pin's menu (`PINS`), and the panel itself; the pin menu's Annotate is the card's `openEditorAfterMenuTracking`)"),
      ('phase-6a', 170, 'Save to the Desktop: `shasum -a 256` of the copy equals',
       '(suite, in part: CoordinatorSaveAsTests.saveAsOfASavedImageCopiesItsBytesAndChangesNothingElse; by hand: `shasum`, the click on `Saved` revealing the copy, the panel\'s Replace prompt)'),
      ('phase-6a', 171, "For an upload-only capture the suggestion is the file name template's name",
       '(suite, in part: CoordinatorSaveAsTests.anUploadOnlyCapturesSaveAsSuggestsTheTemplateNameAndCopiesItsPendingFile, EditorNamingTests.uploadOnlyCaptureWithoutAKeySuggestsTheTemplateName, .counterUsesTheCurrentValue; by hand: where the panel last was)'),
      ('phase-6a', 172, 'After the upload, on a card that showed through it: the panel opens',
       '(suite, in part: CoordinatorSaveAsTests.anUploadOnlyCardsSaveAsWritesTheDragCopyOrDownloadsAfterThePanel; by hand: restoring the card (`SCREENS`), `curl` against the bucket, the slow profile)'),
      ('phase-6a', 174, 'Save As… changes nothing about the capture: the card, its link',
       '(suite: CoordinatorSaveAsTests.saveAsOfASavedImageCopiesItsBytesAndChangesNothingElse)'),
      ('phase-6a', 175, "Open the panel and wait for the card's auto-close to run out",
       "(suite, in part: CoordinatorSaveAsTests.aSaveAsPanelHeldThroughTheCardsAutoCloseStillSaves; by hand: the card's real auto-close timer, the panel window staying usable)"),
      ('phase-6a', 176, 'Use Save As… from the button and from the context menu, from a restored',
       '(suite, in part: CoordinatorSaveAsTests.saveAsFromAnyCardWritesThatCardsCapture; by hand: restoring the card (`SCREENS`), the button and the menu item both calling `onSaveAs`)'),
      ('phase-6a', 198, 'Upload only, after the upload: the card is still on screen',
       '(suite, in part: CoordinatorEditorTests.anUploadedUploadOnlyCardsCopyImageAndAnnotateReadTheDragCopy, CoordinatorUploadTests.anUploadedUploadOnlyImageMovesToItsDragFolderOnlyWithACard, CoordinatorSaveAsTests.anUploadOnlyCardsSaveAsWritesTheDragCopyOrDownloadsAfterThePanel; by hand: Slack reading the file)'),
      ('phase-6a', 199, "An edited capture's drag copy is replaced. Upload-only mode",
       "(suite, in part: CoordinatorEditorSaveTests.saveOverTheFileRemovesTheDragCopyAndEveryReadGivesTheEdit, CoordinatorEditorUploadTests.uploadOfAnUploadOnlyCaptureRemovesItsDragCopyAndEveryReadGivesTheEdit, CoordinatorEditorSaveTests.saveAsAfterASaveOverTheFileWritesTheEditNotTheOriginal, CoordinatorEditorUploadTests.saveAsAfterAnEditorUploadOfAnUploadOnlyCaptureWritesTheEditDuringAndAfterThePut; by hand: the drop, and reaching Save As… after the edit, which only a pin offers (`PINS`); the line's \"from the card\" cannot happen after an Annotate, which closes the card for good, and in upload-only mode ⌘S is Save As…, so the tests read through Recent Captures and remove the drag copy with ⌘U there and ⌘S over a saved file)"),
      ('recording-r1', 313, "Restoring an uploaded upload-only video's card after its drag folder is gone",
       '(suite, in part: CoordinatorSaveAsTests.anUploadOnlyVideosSaveAsDownloadsToTheChosenFile, the Save As… sentence, CoordinatorDragOutTests.aDragOfAShowingUploadedRecordingStartsOneDownload, the drag sentence; by hand: restoring the card starting no download (`SCREENS`), Activity Monitor)'),
      ('recording-r1', 340, "A screenshot's save, upload, Retry, Delete, Save As… and Copy Image are as before; a PNG still gets `.png` and `image/png`.",
       '(suite: CoordinatorSaveAsTests.saveAsOfASavedImageCopiesItsBytesAndChangesNothingElse, CoordinatorSaveTests.aCaptureWithTheOverlayOffShowsNoCardAndStillUploads, CoordinatorDeleteTests.deleteDuringAnUploadCancelsItThenDeletesTheReservedKey, CoordinatorRecordActionsTests.copyImageReadsTheFileOrDownloadsTheObject, CaptureRecordTests.mediaKindTypes, UploadQueueTests.uploadsAndReportsPublicURL, CoordinatorUploadTests.aFailedUploadOnlyImageKeepsItsPendingFileAndSizeUntilARetrySendsIt)'),
      ('recording-r2', 264, "A GIF's card and row. The card has the poster with a `GIF` badge",
       '(suite, in part: CoordinatorSaveAsTests.aGIFsSaveAsWritesTheGIFOverAnExistingFileToo, EditorNamingTests.aGIFPanelAllowsGIFOnly, QuickAccessModelTests.aGIFHasNoImageActionsCopiesItsFileAndHasTheGIFBadge; by hand: the thumbnail click (`WORKSPACE`), `/Volumes/RecOff`, the hover preview, dragging into Finder and Slack)'),
      ('recording-r2', 670, "A screenshot's save, upload, Retry, Delete, Save As… and Copy Image are as before; a PNG still gets",
       '(suite: CoordinatorSaveAsTests.saveAsOfASavedImageCopiesItsBytesAndChangesNothingElse, CoordinatorSaveTests.aCaptureWithTheOverlayOffShowsNoCardAndStillUploads, CoordinatorDeleteTests.deleteDuringAnUploadCancelsItThenDeletesTheReservedKey, CoordinatorRecordActionsTests.copyImageReadsTheFileOrDownloadsTheObject, CaptureRecordTests.mediaKindTypes, UploadQueueTests.uploadsAndReportsPublicURL, CoordinatorUploadTests.aFailedUploadOnlyImageKeepsItsPendingFileAndSizeUntilARetrySendsIt)'),
      ('recording-r4', 277, 'Save As… during the download waits and then saves the landed file',
       '(suite: CoordinatorSaveAsTests.aRecordingsSaveAsDuringItsDragOutDownloadWaitsAndCopiesTheLandedFile)'),
      ('coordinator-harness', 27, "4. `stop-recording`'s log lines in each phase",
       '(suite: CoordinatorRecordingTests.stopRecordingLogsWhatItDidInEachPhase)'),
      ('recording-r1', 263, 'A leftover that does not play (`echo junk > "$C/tmp/Recording/x.mp4"`',
       '(suite: RecordingRecoveryTests.aLeftoverThatDoesNotPlayIsRemovedAndLogged; the relaunch and the junk file are the set-up)'),
      ('recording-r3', 156, 'With the camera prompt up: a second Record press does nothing',
       '(suite: CoordinatorRecordingTests.aStartLogsEachPromptsAnswerAndASecondPressWhileOneIsUp)'),
      ('recording-r3', 162, 'The microphone pick during a recording behaves as the bubble toggle',
       '(suite, in part: CoordinatorRecordingTests.aSettingsPromptLogsItsAnswerOrWhyItWaits; by hand: the microphone pick in Settings reaching the coordinator, a view\'s call on AppCoordinator.shared (CaptureSettingsView.swift:222))'),
      ('recording-r3', 419, "9. The prompts' order and log lines are as the Camera prompt section says.",
       '(suite, in part: CoordinatorRecordingTests.aStartLogsEachPromptsAnswerAndASecondPressWhileOneIsUp, .aSettingsPromptLogsItsAnswerOrWhyItWaits, ShortcutsTests.aStartAsksForTheMicrophoneThenTheCamera; by hand: the prompts on screen and the URL command\'s own dropped line (`URLLOG`))'),
      ('recording-r4', 192, 'Two `record-screen` URLs back to back (one Keyboard Maestro macro)',
       "(suite, in part: CoordinatorRecordingTests.aSecondURLStartBeforeTheFirstTakesTheLockIsLogged (the coordinator's text, which the line accepts); by hand: the one selection on screen)"),
      ('recording-r4', 214, 'Turn `Show webcam bubble` on in Settings while a GIF converts',
       '(suite, in part: CoordinatorRecordingTests.aSettingsPromptLogsItsAnswerOrWhyItWaits; by hand: the Show webcam bubble toggle reaching the coordinator, a view\'s call on AppCoordinator.shared (CaptureSettingsView.swift:253); the GIF conversion is set up as .saving)'),
      ('recording-r4', 347, '5. `RecordingController.isEnding`, so a second `stop-recording`',
       '(suite: CoordinatorRecordingTests.stopRecordingLogsWhatItDidInEachPhase)'),
      ('recording-r4', 366, '18. `urlRecordingStartPending` makes a second `record-screen` handled',
       '(suite: CoordinatorRecordingTests.aSecondURLStartBeforeTheFirstTakesTheLockIsLogged)'),
  ]

  # The one deferred line that already carries a mark, which gains its by-hand part (design 6; tests-small.md LOG.7).
  EXTENDED_DEFERRED = ('recording-r4', 217, 'The record shortcut during the settle delay with `Count down before recording` off',
                       '(suite, the rule: CoordinatorRecordingTests.recordingProceedsOnlyWhenStartedNotQuittingAndNotCancelled; by hand: the log line, in private record() past the capture lock (`TMPDIRS`, `CAPSRC`))')

  # The marks each of the six lines carries before this task, as the checklists read now (joined with single spaces).
  EXISTING = {
      ('coordinator-split', 44): "(suite, in part: CoordinatorEditorTests.annotateFromACardOrRecentCapturesLeavesNothingToRestore, CoordinatorRecordActionsTests.copyImageReadsTheFileOrDownloadsTheObject; by hand: the pin, its second click and `Close Pinned Screenshots` (`PINS`, `SCREENS`), and the pin's Save As… panel (`SAVEAS`); the pin menu's Annotate is the card's `openEditorAfterMenuTracking`)",
      ('phase-6a', 198): "(suite, in part: CoordinatorEditorTests.anUploadedUploadOnlyCardsCopyImageAndAnnotateReadTheDragCopy, CoordinatorUploadTests.anUploadedUploadOnlyImageMovesToItsDragFolderOnlyWithACard; by hand: the card's Save As… panel (`SAVEAS`), and Slack reading the file)",
      ('phase-6a', 199): "(suite, in part: CoordinatorEditorSaveTests.saveOverTheFileRemovesTheDragCopyAndEveryReadGivesTheEdit, CoordinatorEditorUploadTests.uploadOfAnUploadOnlyCaptureRemovesItsDragCopyAndEveryReadGivesTheEdit; by hand: the card's Save As… panel (`SAVEAS`), and the drop; the line's \"from the card\" cannot happen after an Annotate, which closes the card for good, and in upload-only mode ⌘S is Save As…, so the tests read through Recent Captures and remove the drag copy with ⌘U there and ⌘S over a saved file)",
      ('recording-r4', 253): "(suite, in part: CoordinatorUploadTests.anOutdatedKeptClopCopyCountsAsAChangedSource)",
      ('recording-r4', 255): "(suite, in part: CoordinatorUploadTests.anUploadedResumeClearsItsStateSidecarAndKeptCopy)",
      ('recording-r4', 217): "(suite, the rule: CoordinatorRecordingTests.recordingProceedsOnlyWhenStartedNotQuittingAndNotCancelled)",
  }

  # The 3 deferred lines of the 49 (recording-r4:217 is the one above); the other two stay unmarked, before and after.
  DEFERRED = [
      ('recording-r3', 416, "7. The recording's clock times the camera's log lines"),
      ('recording-r3', 436, 'D. `Recording: camera could not be started: <reason>` is logged'),
  ]

  PER_FILE = {"coordinator-harness": 1, "coordinator-split": 1, "phase-6a": 8, "phase-7-clop": 13, "recording-r1": 7,
              "recording-r2": 3, "recording-r3": 3, "recording-r4": 8, "small-tweaks": 2}
  WIDTH = 120


  def tests_named(mark):
      """Every (Suite, test) the mark names, the `.test` shorthand expanded to the suite before it."""
      names, suite = [], None
      for m in re.finditer(r"(?:\b([A-Z][A-Za-z0-9]*Tests)\.([a-z][A-Za-z0-9]*)\b)|(?:, \.([a-z][A-Za-z0-9]*)\b)", mark):
          if m.group(1):
              suite = m.group(1)
              names.append((suite, m.group(2)))
          else:
              names.append((suite, m.group(3)))
      return names


  def wrap(first, words):
      """`first` with `words` appended, wrapped at WIDTH with two-space continuation lines."""
      lines, current = [], first
      for word in words:
          if current.strip() and len(current) + 1 + len(word) > WIDTH:
              lines.append(current)
              current = "  " + word
          else:
              current = current + " " + word if current.strip() else "  " + word
      lines.append(current)
      return lines


  def place(item, mark):
      """The item's lines with `mark` at the end of its last line: appended when that line is at most WIDTH long,
      otherwise on new continuation lines; a closing `______` stays last."""
      words = mark.split(" ")
      item = list(item)
      if item[-1].endswith(" ______"):
          item[-1] = item[-1][: -len(" ______")]
          words.append("______")
      last = item[-1]
      if len(last) <= WIDTH:
          return item[:-1] + wrap(last, words)
      return item + wrap("", words)


  def strip_mark(item, old):
      """The item without its existing mark; asserts the mark read as `old` (whitespace joined to single spaces)."""
      start = next(i for i, l in enumerate(item) if "(suite" in l)
      before, mark = item[start].split("(suite", 1)
      mark = "(suite" + mark
      tail = [l.strip() for l in item[start + 1:]]
      joined = " ".join([mark.strip()] + tail)
      ended = joined.endswith(" ______")
      joined = joined[: -len(" ______")] if ended else joined
      assert joined == old, f"existing mark differs: {joined!r}"
      kept = item[:start] + ([before.rstrip()] if before.strip() else [])
      if ended:
          kept[-1] += " ______"
      return kept


  def item_at(lines, anchor, where):
      """The one line holding `anchor`, and the end of its item (its two-space continuation lines)."""
      hits = [i for i, l in enumerate(lines) if anchor in l]
      assert len(hits) == 1, f"{where} matches {len(hits)} lines"
      start = hits[0]
      assert lines[start].startswith("- [ ] "), f"{where} is not an item's first line"
      end = start + 1
      while end < len(lines) and lines[end].startswith("  ") and not lines[end].lstrip().startswith("- ["):
          end += 1
      return start, end


  if len(sys.argv) > 2 and sys.argv[2] == "anchors":
      # `grep -c -F` of each anchor in its checklist: every line must print 1.
      bad = 0
      for checklist, line, anchor in [(m[0], m[1], m[2]) for m in MARKS] + [EXTENDED_DEFERRED[:3]] + DEFERRED:
          path = ROOT / "docs" / "testing" / f"{checklist}-manual-checklist.md"
          count = int(subprocess.run(["grep", "-c", "-F", "--", anchor, str(path)], capture_output=True, text=True).stdout)
          bad += count != 1
          print(f"{checklist}:{line} {count}")
      assert bad == 0, f"{bad} anchors do not occur once"
      print("49 anchors, each on one line")
      sys.exit(0)

  assert len(MARKS) == 46 and len({(m[0], m[1]) for m in MARKS}) == 46, len(MARKS)
  assert sum(1 for m in MARKS if m[3].startswith("(suite: ")) == 28, "full marks"
  assert sum(1 for m in MARKS if m[3].startswith("(suite, in part: ")) == 18, "part marks"
  assert all(m[3].startswith(("(suite: ", "(suite, in part: ")) and m[3].endswith(")") for m in MARKS)
  assert all(("; by hand: " in m[3]) == m[3].startswith("(suite, in part: ") for m in MARKS), "a part mark's by-hand text"
  extended = {(m[0], m[1]) for m in MARKS} & set(EXISTING)
  assert len(extended) == 5 and (EXTENDED_DEFERRED[0], EXTENDED_DEFERRED[1]) in EXISTING, extended
  for checklist, count in PER_FILE.items():
      assert sum(1 for m in MARKS if m[0] == checklist) == count, checklist

  missing = []
  for _, _, _, mark in MARKS + [EXTENDED_DEFERRED]:
      for suite, name in tests_named(mark):
          source = ROOT / "TidyShotTests" / f"{suite}.swift"
          if not source.exists() or f"func {name}(" not in source.read_text():
              missing.append(f"{suite}.{name}")
  assert not missing, f"tests not found: {sorted(set(missing))}"

  marked = 0
  for checklist in PER_FILE:
      path = ROOT / "docs" / "testing" / f"{checklist}-manual-checklist.md"
      lines = path.read_text().split("\n")
      spans = []
      todo = [(m[1], m[2], m[3]) for m in MARKS if m[0] == checklist]
      if checklist == EXTENDED_DEFERRED[0]:
          todo.append(EXTENDED_DEFERRED[1:])
      for line, anchor, mark in todo:
          start, end = item_at(lines, anchor, f"{checklist}:{line}")
          item = lines[start:end]
          joined = " ".join(item)
          if (checklist, line) in EXISTING:
              assert joined.count("(suite") == 1 and "(obsolete: " not in joined, f"{checklist}:{line}"
              item = strip_mark(item, EXISTING[(checklist, line)])
          else:
              assert "(suite" not in joined and "(obsolete: " not in joined, f"{checklist}:{line} is already marked"
          placed = place(item, mark)
          assert " ".join(placed).count("(suite") == 1, f"{checklist}:{line} must carry exactly one note"
          spans.append((start, end, placed))
      starts = [s for s, _, _ in spans]
      assert len(set(starts)) == len(starts), f"{checklist}: two marks on one item"
      for start, end, item in sorted(spans, reverse=True):
          assert all(len(l) <= WIDTH for l in item[1:]) and (len(item[0]) <= WIDTH or lines[start].startswith(item[0])), (checklist, [len(l) for l in item], item[0][:60])
          lines[start:end] = item
          marked += 1
      for _, line, anchor in (d for d in DEFERRED if d[0] == checklist):
          start, end = item_at(lines, anchor, f"{checklist}:{line} (deferred)")
          assert "(suite" not in " ".join(lines[start:end]), f"{checklist}:{line} is deferred and must stay unmarked"
      path.write_text("\n".join(lines))
  assert marked == 47
  print("46 lines marked, 1 deferred line's mark extended")
  EOF
  python3 /private/tmp/claude-501/ct3plan-task4/marks.py . anchors | tail -2
  ```
  Expected: the last two lines are `recording-r3:436 1` and `49 anchors, each on one line` (every line of the full
  output ends in ` 1`). A `tests not found:` assertion in Step 3 means a task before this one left a test out or
  named it otherwise; stop and report it rather than editing the mark.

- [ ] **Step 3: Mark the 46 lines.**
  ```bash
  python3 /private/tmp/claude-501/ct3plan-task4/marks.py .
  ```
  Expected: `46 lines marked, 1 deferred line's mark extended`.

- [ ] **Step 4: Check the marks.**
  ```bash
  git diff --stat -- docs/testing
  ```
  Expected, exactly (the bars' lengths depend on the terminal; the counts do not):
  ```
   docs/testing/coordinator-harness-manual-checklist.md |  3 +-
   docs/testing/coordinator-split-manual-checklist.md   |  8 +-
   docs/testing/phase-6a-manual-checklist.md            | 27 ++-
   docs/testing/phase-7-clop-manual-checklist.md        | 22 +-
   docs/testing/recording-r1-manual-checklist.md        | 21 +-
   docs/testing/recording-r2-manual-checklist.md        | 16 +-
   docs/testing/recording-r3-manual-checklist.md        | 11 +-
   docs/testing/recording-r4-manual-checklist.md        | 34 ++-
   docs/testing/small-tweaks-manual-checklist.md        |  7 +-
   9 files changed, 120 insertions(+), 29 deletions(-)
  ```
  The script asserted that every continuation line it wrote is at most 120 characters. The deletions are the item lines
  a mark was appended to and the six existing marks rewritten. Read `git diff -- docs/testing/phase-6a-manual-checklist.md`
  and `git diff -- docs/testing/recording-r4-manual-checklist.md` and confirm that no line outside a marked item
  changed, that phase-6a:198 and :199 and recording-r4:253 and :255 each carry one note, that phase-6a:199's by-hand
  text names `PINS` and no longer `SAVEAS`, and that recording-r4:255's note reads `(suite: …` and not `(suite, in part: …`.

- [ ] **Step 5: Edit seams.md as the design's section 11 says.** The script reads seams.md's table and its 42 seam
  sections (each line list, with its "(also …)" note and free-text notes), checks that they reproduce the table's
  Lines, Alone and Completes (404, 186, 279), and then: (item 1) gives each of the 49 lines its verdict
  (`; CT-3: full`, `; CT-3: in part`, `; CT-3: deferred`) under its seam (`CLOP`, `SAVEAS` or `LOG`), turns
  phase-7-clop:28's free-text note into "the editor half through `EDITOR` (landed in CT-2)", rewords the Shape lines
  of sections 5 and 8 (and `CLOP`'s Live line) to what was built, and adds a `CT-3` note bullet to each of the three
  sections and one sentence to the header's Source paragraph; (item 2) adds the 6 joins (`SCREENS` phase-6a:172 and
  :176, `PINS` phase-6a:199, `URLLOG` recording-r3:419, `TMPDIRS` and `CAPSRC` recording-r4:217), each noted "also
  `<home seam>`, in part since CT-3" (or "deferred in CT-3") under the row it joins; (item 3) recounts by seams.md's
  rules (:9-12), sorts the table and the sections by Lines with equal Lines in the old table order, renumbers them,
  regenerates the "(also …)" note of the 5 lines whose seams changed, rewrites the summary's counts, and regenerates
  the multi-seam and three-or-fewer sections in their existing form (each line's text cut at 39 and 47 characters,
  which reproduces all 93 multi-seam entries and every unchanged three-or-fewer entry as they are; the script asserts
  both). The design's section 11 gives the rows and positions the script asserts; the tie rule is the one that
  reproduces them (`SCREENS` eighth, `URLLOG` 27th, the first ten complete 150), where CT-2's sort by Alone would put
  `SCREENS` seventh and `URLLOG` 26th. Run it on a copy first.
  ```bash
  cat > /private/tmp/claude-501/ct3plan-task4/seams.py <<'EOF'
  import re
  import sys
  from pathlib import Path

  ROOT = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(".")
  PATH = ROOT / "docs" / "superpowers" / "notes" / "2026-10-30-checklist-sweep" / "seams.md"

  # Design section 11 and lines-small.md: each of the 49 lines, its seam and its CT-3 verdict.
  VERDICT = {}
  for seam, verdict, keys in [
      ("CLOP", "full", """phase-7-clop:28 phase-7-clop:29 phase-7-clop:31 phase-7-clop:32 phase-7-clop:35 phase-7-clop:36
          phase-7-clop:37 phase-7-clop:41 phase-7-clop:42 phase-7-clop:43 phase-7-clop:44 phase-7-clop:45
          recording-r1:271 recording-r1:297 recording-r1:330 recording-r4:255 recording-r4:323 small-tweaks:14
          small-tweaks:15"""),
      ("CLOP", "in part", "phase-7-clop:21 recording-r1:296 recording-r2:275 recording-r4:253"),
      ("SAVEAS", "full", "phase-6a:174 recording-r1:340 recording-r2:670 recording-r4:277"),
      ("SAVEAS", "in part", """coordinator-split:44 phase-6a:170 phase-6a:171 phase-6a:172 phase-6a:175 phase-6a:176
          phase-6a:198 phase-6a:199 recording-r1:313 recording-r2:264"""),
      ("LOG", "full", """coordinator-harness:27 recording-r1:263 recording-r3:156 recording-r4:347 recording-r4:366"""),
      ("LOG", "in part", "recording-r3:162 recording-r3:419 recording-r4:192 recording-r4:214"),
      ("LOG", "deferred", "recording-r3:416 recording-r3:436 recording-r4:217"),
  ]:
      for k in keys.split():
          VERDICT[k] = (seam, verdict)
  assert len(VERDICT) == 49, len(VERDICT)
  assert sum(1 for v in VERDICT.values() if v[1] == "full") == 28
  assert sum(1 for v in VERDICT.values() if v[1] == "in part") == 18
  assert sum(1 for v in VERDICT.values() if v[1] == "deferred") == 3

  # Item 2: each part or deferred line joins the rows its mark names that do not list it yet (6 slots).
  JOINS = {
      "SCREENS": ["phase-6a:172", "phase-6a:176"],
      "PINS": ["phase-6a:199"],
      "URLLOG": ["recording-r3:419"],
      "TMPDIRS": ["recording-r4:217"],
      "CAPSRC": ["recording-r4:217"],
  }
  # The earlier CT-2 note that stays on a SAVEAS entry whose "(also ...)" is rebuilt.
  OLD_ANNOTATION = {("phase-6a:199", "EDITOR"): "in part since CT-2"}
  # Item 1: the one free-text note that changes (phase-7-clop:28).
  NOTE_OLD = "; the editor-driven half would also need EDITOR; startUpload(fixedKey:) stands in"
  NOTE_NEW = "; the editor half through `EDITOR` (landed in CT-2)"

  SECTION_NOTES = {
      "CLOP": ("- CT-3: Built on `small-seams` (`docs/superpowers/specs/2026-10-31-tidyshot-small-seams-design.md`). "
               "Each line below carries its CT-3 verdict; a line marked in part also sits under every other seam its "
               "mark names, noted there as \"also `CLOP`, in part since CT-3\"."),
      "SAVEAS": ("- CT-3: Built on `small-seams` (`docs/superpowers/specs/2026-10-31-tidyshot-small-seams-design.md`). "
                 "Each line below carries its CT-3 verdict; a line marked in part also sits under every other seam its "
                 "mark names, noted there as \"also `SAVEAS`, in part since CT-3\"."),
      "LOG": ("- CT-3: Built on `small-seams` (`docs/superpowers/specs/2026-10-31-tidyshot-small-seams-design.md`). "
              "Each line below carries its CT-3 verdict; a line marked in part or deferred also sits under every other "
              "seam its mark names, noted there as \"also `LOG`, in part since CT-3\" or \"deferred in CT-3\"."),
  }
  # Item 1: the Shape and Live lines of sections 5 and 8 say what was built (design 2.1 and 2.3).
  BULLETS_OLD = {
      "CLOP": [
          ("- Shape: Two members on `AppEnvironment`: the `ClopOptimiser` itself (its `init(workDirectory:transport:)`, "
           "ClopOptimiser.swift:75, already takes a transport) and `clopRunningBundleID: () -> String?`.",
           "- Shape: Built in CT-3 (design 2.1): two members on `AppEnvironment`, `clopOptimiser: any ClopOptimising` and "
           "`isClopRunning: @MainActor () -> Bool`. `ClopOptimising` is a protocol of the two calls the coordinator makes "
           "(`optimisedPNG`, `optimisedVideo`), and `ClopOptimiser` conforms to it unchanged. A fake transport under the "
           "concrete optimiser was rejected: a hold there blocks a thread on the optimiser's two shared static queues "
           "and has no cancellation. The running check is a `Bool` because the coordinator reads the bundle id only as "
           "nil or not."),
          ("- Live: `ClopApp.makeOptimiser()` and `ClopApp.runningBundleID()`.",
           "- Live: `ClopApp.makeOptimiser()` and `{ ClopApp.runningBundleID() != nil }`."),
      ],
      "LOG": [
          ("- Shape: A closure on `AppEnvironment` (`recordingLog: @Sendable (String) -> Void`) that the coordinator uses "
           "for its own calls and passes to `RecordingRecovery.begin` and `RecordingExtras.init` for theirs; the world "
           "collects it with `logLines`. A settable static sink is simpler but would mix lines across parallel suites.",
           "- Shape: Built in CT-3 (design 2.3): a closure on `AppEnvironment` (`recordingLog: @Sendable (String) -> "
           "Void`) that the coordinator uses for its own 24 calls and hands to `RecordingRecovery.scan` through "
           "`begin`'s `scanning:` parameter; the world collects it as `recordingLines`, beside `logLines`, because "
           "`RecordingLog` writes `.public` and `log` does not. `RecordingExtras.init` and the mute sweep are not "
           "threaded (`EXTRAS`). A settable static sink would mix lines across parallel suites."),
      ],
  }
  SOURCE_OLD = "The table, the counts and the last sections were redone by the rules in the summary."
  SOURCE_NEW = (SOURCE_OLD + " CT-3 (`docs/superpowers/specs/2026-10-31-tidyshot-small-seams-design.md`, section 11) then "
                "built `CLOP`, `SAVEAS` and `LOG`: each of their 49 lines carries its CT-3 verdict (28 full, 18 in part, "
                "3 deferred), and the part and deferred lines also sit under the other seams their marks name (6 new "
                "seam slots). The table, the counts and the last sections were redone again by the same rules, with seams "
                "of equal Lines kept in their old table order.")
  SUMMARY = [
      ("- 186 lines need one seam; 93 need two or more (listed in their own section).",
       "- 182 lines need one seam; 97 need two or more (listed in their own section)."),
      ("- 16 seams unlock three or fewer lines each.", "- 15 seams unlock three or fewer lines each."),
      ("Lines sums to 404 (186 one-seam lines, plus 218 seam slots held by the 93 lines that need two or more); Alone sums "
       "to 186; Completes sums to 279, every B line once. Read down the Completes column for a running total: the first "
       "three seams cover 78 lines, the first ten 152.",
       "Lines sums to 410 (182 one-seam lines, plus 228 seam slots held by the 97 lines that need two or more); Alone sums "
       "to 182; Completes sums to 279, every B line once. Read down the Completes column for a running total: the first "
       "three seams cover 78 lines, the first ten 150."),
  ]
  # Design 11 item 3, Lines / Alone / Completes, and the places it gives.
  ROWS = {"CAPSRC": (34, 8, 8), "SAVEAS": (14, 7, 8), "SCREENS": (14, 6, 10), "TMPDIRS": (13, 7, 8), "LOG": (12, 7, 8),
          "PINS": (10, 5, 9), "URLLOG": (4, 2, 4), "CLOP": (23, 22, 22)}
  PLACES = {"EDITOR": 1, "EDPLACE": 2, "TARGET": 3, "CAPSRC": 4, "CLOP": 5, "SAVEAS": 6, "SCREENS": 8, "TMPDIRS": 9,
            "LOG": 10, "URLLOG": 27, "CHROMEMAP": 28}

  # A line's entry: its text, cut with "…" (or whole when short), then "(also …)" and notes after "; ".
  ENTRY = re.compile(r"^- `([a-z0-9-]+:\d+)` (.*?…)( \(also [^)]*\))?((?:; .*)?)$")
  WHOLE = re.compile(r"^- `([a-z0-9-]+:\d+)` (.*?)( \(also [^)]*\))?()$")


  def parse(line):
      return ENTRY.match(line) or WHOLE.match(line)


  def order_key(key):
      stem, line = key.rsplit(":", 1)
      return (stem, int(line))


  def cut(text, width):
      """A line's text for the last two sections: no backticks, cut at a space within `width` characters."""
      text = text.replace("`", "")
      text = text[:-1] if text.endswith("…") else text
      if len(text) <= width:
          return text.rstrip(" ,;:.")
      head = text[: width + 1]
      return head[: head.rfind(" ")].rstrip(" ,;:.")


  text = PATH.read_text()
  for old in [s[0] for s in SUMMARY] + [SOURCE_OLD, NOTE_OLD] + [b[0] for v in BULLETS_OLD.values() for b in v]:
      assert text.count(old) == 1, f"seams.md is not as at f991760: {old[:60]}"

  # Parse the table, the sections and their line lists.
  head, rest = text.split("\n## The seams, by lines unlocked\n\n", 1)
  body, tail = rest.split("\n## Lines that need two or more seams at once\n", 1)
  multi_old, tail = tail.split("\n## Seams that unlock three or fewer lines\n", 1)
  three_old, tail = tail.split("\n## A lines that name a seam\n", 1)
  rows = re.findall(r"^\| (\d+) \| ([^|]+) \| `([A-Z]+)` \| (\d+) \| (\d+) \| (\d+) \| (\w+) \|$", head, re.M)
  assert len(rows) == 42
  old_order = [r[2] for r in rows]
  names = {r[2]: r[1] for r in rows}
  effort = {r[2]: r[6] for r in rows}
  table_old = {r[2]: tuple(int(x) for x in r[3:6]) for r in rows}
  sections, entries, after_list = {}, {}, {}
  for block in re.split(r"\n(?=### \d+\. )", body.strip("\n")):
      first, *lines = block.split("\n")
      key = re.match(r"^### \d+\. .+ \(`([A-Z]+)`\): \d+ lines, \d+ alone$", first).group(1)
      split = lines.index(next(l for l in lines if re.match(r"^Lines \(\d+\):$", l)))
      bullets = [l for l in lines[:split] if l]
      listed = [parse(l) for l in lines[split + 1:] if l.startswith("- `")]
      last = max(i for i, l in enumerate(lines) if l.startswith("- `"))
      after_list[key] = lines[last + 1:]
      while after_list[key] and after_list[key][-1] == "":
          after_list[key].pop()
      assert all(l.startswith("- ") and not l.startswith("- `") for l in bullets), key
      assert all(l == "" or l.startswith("- `") for l in lines[split + 1:last + 1]), key
      for l in lines:
          if l.startswith("- `"):
              m = parse(l)
              assert m and "".join(m.group(i) or "" for i in (2, 3, 4)) == l.split("` ", 1)[1], l
      sections[key] = bullets
      entries[key] = {m.group(1): (m.group(2), m.group(3) or "", m.group(4)) for m in listed}
      count = int(re.search(r"^Lines \((\d+)\):$", block, re.M).group(1))
      assert count == len(listed), key
  seams = {key: list(e) for key, e in entries.items()}


  def counts(seams, order):
      need = {}
      for seam, keys in seams.items():
          for k in keys:
              need.setdefault(k, set()).add(seam)
      place = {s: i for i, s in enumerate(order)}
      out = {}
      for s in order:
          out[s] = (len(seams[s]), sum(1 for k in seams[s] if need[k] == {s}),
                    sum(1 for k in seams[s] if max(need[k], key=place.get) == s))
      return out, need


  before, need_before = counts(seams, old_order)
  assert before == table_old, "the table matches its lists"
  assert [sum(v[i] for v in before.values()) for i in range(3)] == [404, 186, 279]
  for k, (seam, _) in VERDICT.items():
      assert k in seams[seam], (seam, k)
  assert sum(len(seams[s]) for s in ("CLOP", "SAVEAS", "LOG")) == 49
  assert all(sum(1 for k in seams[s] if VERDICT[k][0] == s) == len(seams[s]) for s in ("CLOP", "SAVEAS", "LOG"))

  # Item 2: the joins.
  slots = 0
  for seam, keys in JOINS.items():
      for k in keys:
          assert VERDICT[k][1] in ("in part", "deferred") and k not in seams[seam], (seam, k)
          seams[seam].append(k)
          slots += 1
      seams[seam].sort(key=order_key)
  assert slots == 6, slots
  changed = {k for keys in JOINS.values() for k in keys}
  assert len(changed) == 5, changed

  # Item 3: the counts, the table sorted by Lines, equal Lines in the old table order.
  first, _ = counts(seams, list(seams))
  order = sorted(seams, key=lambda s: (-first[s][0], old_order.index(s)))
  after, need = counts(seams, order)
  assert len(order) == 42 and len(need) == 279
  assert [sum(v[i] for v in after.values()) for i in range(3)] == [410, 182, 279]
  assert sum(1 for k in need if len(need[k]) > 1) == 97
  assert sum(1 for s in order if after[s][0] <= 3) == 15
  running = [sum(after[s][2] for s in order[:n]) for n in (3, 10)]
  assert running == [78, 150], running
  for seam, row in ROWS.items():
      assert after[seam] == row, (seam, after[seam], row)
  for seam, place in PLACES.items():
      assert order.index(seam) + 1 == place, (seam, order.index(seam) + 1)
  assert all(after[s] == before[s] for s in before if s not in ROWS), "only design 11's rows change"
  assert [s for s in order if s in ("SAVEAS", "RECCHROME", "SCREENS")] == ["SAVEAS", "RECCHROME", "SCREENS"]

  # The text each line shows, from its first entry.
  shown = {}
  for seam in entries:
      for k, (t, _, _) in entries[seam].items():
          shown.setdefault(k, t)


  def also(k, seam):
      """`(also …)` for a changed line under `seam`: the other seams in table order; the line's home seam (CT-3) is
      named first with how it stands when `seam` is a seam the line joined; an earlier annotation stays."""
      others = [s for s in order if s in need[k] and s != seam]
      home, verdict = VERDICT[k]
      if seam != home and seam in {s for s, ks in JOINS.items() if k in ks}:
          note = "deferred in CT-3" if verdict == "deferred" else "in part since CT-3"
          rest = [f"`{s}`" for s in others if s != home]
          return f" (also `{home}`, {note}" + ("; and " + ", ".join(rest) if rest else "") + ")"
      for o in others:
          if (k, o) in OLD_ANNOTATION:
              rest = [f"`{s}`" for s in others if s != o]
              return f" (also `{o}`, {OLD_ANNOTATION[(k, o)]}" + ("; and " + ", ".join(rest) if rest else "") + ")"
      return " (also " + ", ".join(f"`{s}`" for s in others) + ")"


  def entry(seam, k):
      t, also_text, notes = entries.get(seam, {}).get(k, (shown[k], "", ""))
      if k in changed:
          also_text = also(k, seam)
      if VERDICT.get(k, (None,))[0] == seam:
          notes = notes.replace(NOTE_OLD, NOTE_NEW)
          notes += f"; CT-3: {VERDICT[k][1]}"
      return f"- `{k}` {t}{also_text}{notes}"


  out = []
  for n, seam in enumerate(order, 1):
      lines_, alone, _ = after[seam]
      bullets = list(sections[seam])
      for old, new in BULLETS_OLD.get(seam, []):
          assert bullets.count(old) == 1, (seam, old[:50])
          bullets[bullets.index(old)] = new
      if seam in SECTION_NOTES:
          bullets.append(SECTION_NOTES[seam])
      block = [f"### {n}. {names[seam]} (`{seam}`): {lines_} lines, {alone} alone", ""] + bullets
      block += ["", f"Lines ({lines_}):", ""] + [entry(seam, k) for k in seams[seam]]
      block += after_list.get(seam, [])
      out.append("\n".join(block))
  body_new = "\n\n".join(out) + "\n"

  table = ["| # | Seam | Key | Lines | Alone | Completes | Effort |", "|---|---|---|---|---|---|---|"]
  table += [f"| {n} | {names[s]} | `{s}` | {after[s][0]} | {after[s][1]} | {after[s][2]} | {effort[s]} |"
            for n, s in enumerate(order, 1)]
  table_old_text = "\n".join(l for l in head.split("\n") if l.startswith("|"))
  head_new = head.replace(table_old_text, "\n".join(table))
  for old, new in SUMMARY + [(SOURCE_OLD, SOURCE_NEW)]:
      head_new = head_new.replace(old, new)

  place = {s: i for i, s in enumerate(order)}
  groups = {}
  for k in need:
      if len(need[k]) > 1:
          groups.setdefault(tuple(sorted(need[k], key=place.get)), []).append(k)
  old_multi = dict(re.findall(r"`([a-z0-9-]+:\d+)` (.*?)…(?=; `|$)", multi_old, re.M))
  assert len(old_multi) == 93
  for k, t in old_multi.items():
      assert cut(shown[k], 39) == t, (k, t)
  multi = ["", f"{sum(len(v) for v in groups.values())} lines. Grouped by the seams they need.", ""]
  for g in sorted(groups, key=lambda g: (-len(groups[g]), [place[s] for s in g])):
      keys = sorted(groups[g], key=order_key)
      multi.append("- " + " + ".join(f"`{s}`" for s in g) + f" ({len(keys)}): "
                   + "; ".join(f"`{k}` {cut(shown[k], 39)}…" for k in keys))
  three = [""]
  for s in order:
      if after[s][0] <= 3:
          keys = seams[s]
          plain = [f"`{k}` {cut(shown[k], 47)}…" + (" (also " + ", ".join(
              f"`{o}`" for o in order if o in need[k] and o != s) + ")" if len(need[k]) > 1 else "") for k in keys]
          word = "line" if len(keys) == 1 else "lines"
          three.append(f"- {names[s]} (`{s}`, effort {effort[s]}), {len(keys)} {word}: " + "; ".join(plain))
  old_three = re.findall(r"^- (.+) \(`([A-Z]+)`, effort \w+\), \d+ lines?: (.*)$", three_old, re.M)
  assert len(old_three) == 16
  for name, s, line in old_three:
      if s == "URLLOG":
          continue
      assert line in "\n".join(three), (s, line)

  text_new = (head_new + "\n## The seams, by lines unlocked\n\n" + body_new
              + "\n## Lines that need two or more seams at once\n" + "\n".join(multi) + "\n"
              + "\n## Seams that unlock three or fewer lines\n" + "\n".join(three) + "\n"
              + "\n## A lines that name a seam\n" + tail)
  PATH.write_text(text_new)
  print(f"seams.md: {len(order)} seams, Lines {sum(v[0] for v in after.values())}, "
        f"Alone {sum(v[1] for v in after.values())}, Completes {sum(v[2] for v in after.values())}, "
        f"{slots} new slots, {sum(1 for k in need if len(need[k]) > 1)} lines need two or more seams, "
        f"{sum(1 for s in order if after[s][0] <= 3)} seams unlock three or fewer")
  EOF
  C=/private/tmp/claude-501/ct3plan-task4/copy
  rm -rf "$C" && mkdir -p "$C/docs/superpowers/notes/2026-10-30-checklist-sweep"
  cp docs/superpowers/notes/2026-10-30-checklist-sweep/seams.md "$C/docs/superpowers/notes/2026-10-30-checklist-sweep/"
  python3 /private/tmp/claude-501/ct3plan-task4/seams.py "$C"
  ```
  Expected: `seams.md: 42 seams, Lines 410, Alone 182, Completes 279, 6 new slots, 97 lines need two or more seams, 15 seams unlock three or fewer`.
  Then on the repository and with the checks:
  ```bash
  python3 /private/tmp/claude-501/ct3plan-task4/seams.py .
  git diff --stat -- docs/superpowers/notes/2026-10-30-checklist-sweep/seams.md | tail -1
  grep -c "; CT-3: " docs/superpowers/notes/2026-10-30-checklist-sweep/seams.md
  grep -n "^### [0-9]*\. .*(\`\(CAPSRC\|CLOP\|SAVEAS\|SCREENS\|TMPDIRS\|LOG\|PINS\|URLLOG\|CHROMEMAP\)\`)" docs/superpowers/notes/2026-10-30-checklist-sweep/seams.md
  ```
  Expected: the same `seams.md: 42 seams, …` line; ` 1 file changed, 126 insertions(+), 116 deletions(-)`; `49`; and
  ```
  240:### 4. Capture source (engine and selector) (`CAPSRC`): 34 lines, 8 alone
  285:### 5. Clop optimiser and running check (`CLOP`): 23 lines, 22 alone
  319:### 6. Card Save As panel (`SAVEAS`): 14 lines, 7 alone
  369:### 8. Screen list for the card stack and pins (`SCREENS`): 14 lines, 6 alone
  393:### 9. tmp/ directory statics (`TMPDIRS`): 13 lines, 7 alone
  418:### 10. RecordingLog sink (`LOG`): 12 lines, 7 alone
  483:### 13. Headless pins (`PINS`): 10 lines, 5 alone
  718:### 27. URL command log closure (`URLLOG`): 4 lines, 2 alone
  732:### 28. Recording chrome's not-filmed mapping (`CHROMEMAP`): 3 lines, 3 alone
  ```
  Read the diff of the multi-seam section: `SAVEAS` + `SCREENS` goes from 1 line to 3, `LOG` + `URLLOG` from 1 to 2 and
  `EDITOR` + `SAVEAS` from 2 to 1, and two groups are new, `EDITOR` + `SAVEAS` + `PINS` (phase-6a:199) and
  `CAPSRC` + `TMPDIRS` + `LOG` (recording-r4:217). `URLLOG` leaves the three-or-fewer section.

- [ ] **Step 6: Write the hand-check checklist.** Create `docs/testing/small-seams-manual-checklist.md`, in the form
  of `docs/testing/editor-seam-manual-checklist.md` (when to run it, the checks, the design's calls and the plan's
  decisions to confirm or overrule, observations), with the design's section 9 checks as 1 to 3 and section 10's eleven
  calls:
  ```bash
  cat > docs/testing/small-seams-manual-checklist.md <<'EOF'
  # Small seams manual checklist

  Run after the small seams phase (`docs/superpowers/specs/2026-10-31-tidyshot-small-seams-design.md`), and after any
  later change to `AppEnvironment.clopOptimiser`, `isClopRunning`, `chooseSaveAsURL` or `recordingLog` and their live
  values, to `askSaveAsTarget`, or to a `Recording:` log line. The suite now runs Clop through `world.clop`, the card's
  Save As… panel through `world.saveAsChooser` and the coordinator's `Recording:` lines into `world.recordingLines`, and
  the phase-7-clop, recording-r1 to r4, phase-6a, coordinator-split, coordinator-harness and small-tweaks checklists mark
  46 more lines `(suite …)`, 28 in full and 18 in part. The three live values never run in the suite
  (`AppEnvironment.live()` builds `AppSettings.shared`, the Keychain store and the notifier), so what is left here is the
  real Clop, the real panel and the real log: that each does what it did before the seam.

  ## Checks

  - [ ] 1. The real Clop path. With Clop running and `Optimize with Clop` on, a capture's upload shows `Optimizing…` and
    the row shows the smaller size; an MP4 recording does the same. Quit Clop and capture: the original uploads, the log
    has `Clop: Clop is not running, uploading the original`, and Clop is not launched.
  - [ ] 2. The real panel. Save As… on a card while another app is frontmost: the panel opens in front of it, with the
    capture's name in the save folder. Cancel writes nothing; Save writes the copy and posts `Saved`. Save As… on an
    upload-only recording's card downloads to the chosen file.
  - [ ] 3. The real log. `stop-recording` with nothing running, then
    `log show --last 5m --style compact --predicate 'process == "TidyShot"' | grep "Recording:"`: one `did nothing, no
    recording is running` line, public, not `<private>`. Then `echo junk > "$C/tmp/Recording/x.mp4"`, relaunch, and the
    same command shows `Recording: x.mp4 could not be played, removed`.

  ## The design's calls, to confirm or overrule

  The design lists them in section 10. Write `confirm` or `overrule` and why; an overrule goes in its built notes.
  - [ ] 1. `CLOP` is a protocol, `ClopOptimising`, on the environment, not the concrete optimiser over a fake transport,
    and `isClopRunning` is `() -> Bool`, not `() -> String?`. Overrule only to exercise the optimiser's file checks in
    coordinator tests; `ClopOptimiserTests` already does. ______
  - [ ] 2. `LOG` is the coordinator plus `RecordingRecovery.scan`. The mute sweep is not threaded and `RecordingExtras` is
    left to `EXTRAS`. Two log members, `log` and `recordingLog`, for the privacy split at the call site. ______
  - [ ] 3. `FakeDestination.download(key:to:)` records and writes. A later Trim test through
    `downloadAndPresentTrimWindow` would then get a file under the real `tmp/`, which is `TMPDIRS`' business. ______
  - [ ] 4. SAVEAS 9 and 10 are new tests on CT-2's helpers, not in-place extensions of CT-2's tests. In place, the suite
    line would be 2350, not 2352. ______
  - [ ] 5. `aSaveAsWhoseCaptureIsDeletedWhileThePanelIsUpWritesNothingAndLogsIt` is included: the deleted-while-open
    branch of `askSaveAsTarget`, which covers no line. ______
  - [ ] 6. recording-r1:340 and recording-r2:670 are full: Save As… is the new test, and each other verb has an existing
    test. If a verb has none for a screenshot, the line becomes part. ______
  - [ ] 7. recording-r1:263 is full, on the reading that the relaunch and the junk file are set-up; `start()` handing
    `scan` the sink is read from the code, not driven (`TMPDIRS`, `LAUNCH`). ______
  - [ ] 8. coordinator-harness:27's wording stays, although the mark makes its "the suite pins the state, not the
    `RecordingLog` text" history. ______
  - [ ] 9. phase-6a:169 and :173 are reached by SAVEAS test 1 but are not among the 49 lines; they stay unmarked. ______
  - [ ] 10. CLOP T7 enters at `finishSave`, not `save(_:intent:)`, which no test can call (`CaptureTarget` holds an
    `SCDisplay` or `SCWindow`). ______
  - [ ] 11. seams.md keeps equal-Lines seams in their old table order, and recording-r4:192 joins no seam: its by-hand
    part, the one selection on screen, is the drawn UI. The order of the three tasks (CLOP, SAVEAS, LOG) is free. ______

  ## The plan's decisions, to confirm or overrule

  The plan lists them at its end (`docs/superpowers/plans/2026-10-31-small-seams.md`, Plan decisions). None changes what
  a user could see, and none changes a number the design gives:
  - [ ] The marks and seams.md follow the design's section 11 and the catalogue's mark tables; where the plan words a mark
    otherwise (recording-r1:313 names its drag test, recording-r4:192 keeps the catalogue's note inside the test list),
    the decision says so. ______

  ## Observations
  Write into the design's built notes: anything above that failed, and each call and decision confirmed or overruled.
  EOF
  python3 -c 'import sys; print([n for n, l in enumerate(open(sys.argv[1]), 1) if len(l.rstrip("\n")) > 120])' docs/testing/small-seams-manual-checklist.md
  ```
  Expected: `[]` (no line over 120 characters).

- [ ] **Step 7: Run the full suite and the Release build.**
  ```bash
  xcodegen generate && xcodebuild test -project TidyShot.xcodeproj -scheme TidyShot -destination 'platform=macOS' -derivedDataPath .build 2>&1 | grep -E "Test run with|error:|TEST"
  ```
  Expected: `Test run with 2352 tests in 195 suites passed` and `** TEST SUCCEEDED **`, with only the known noise
  (Global Constraints; a run that fails only on `UploadQueueTests.aSidecarUnwritableDuringThePartsFailsTheJobBeforeComplete`
  is rerun once). Nothing in this task touches the code, so a different count means an earlier task's tree changed;
  stop and report it.
  ```bash
  xcodegen generate && xcodebuild -project TidyShot.xcodeproj -scheme TidyShot -configuration Release -derivedDataPath .build-rel build 2>&1 | grep -E "error:|warning:|BUILD"
  ```
  Expected: `** BUILD SUCCEEDED **` and no `error:` or `warning:` line from the compiler or the linker; the two tool lines
  the Global Constraints name (`iOSSimulator: … sharedServiceContextForDeveloperDir:error:` and the
  `appintentsmetadataprocessor` `warning: Metadata extraction skipped`) may print and are not failures.
  ```bash
  git diff --stat main -- project.yml; git diff --name-only main -- TidyShot/
  ```
  Expected: nothing for `project.yml`, then exactly
  ```
  TidyShot/App/AppCoordinator+RecordActions.swift
  TidyShot/App/AppCoordinator+Recording.swift
  TidyShot/App/AppCoordinator+Recovery.swift
  TidyShot/App/AppCoordinator+Upload.swift
  TidyShot/App/AppCoordinator.swift
  TidyShot/App/AppEnvironment.swift
  TidyShot/Recording/RecordingRecovery.swift
  TidyShot/Recording/ScreenRecordingDriver.swift
  TidyShot/Upload/ClopOptimiser.swift
  ```
  (Tasks 1 to 3's nine files; `git diff --shortstat main -- TidyShot/` reads about `9 files changed, 94 insertions(+),
  52 deletions(-)`, the design's section 12 figure, give or take the blank line after the new protocol.)

- [ ] **Step 8: The built notes.** The design's section 12 gains one paragraph with the branch's suite line, the
  Release result, the marks made and the seams.md edit. If Step 7's suite line differs from `Test run with 2352 tests
  in 195 suites passed`, set `SUITE` to the line it printed before running this.
  ```bash
  cat > /private/tmp/claude-501/ct3plan-task4/design.py <<'EOF'
  import sys
  from pathlib import Path

  ROOT = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(".")
  SUITE = "Test run with 2352 tests in 195 suites passed"   # the full suite line of this task's run

  design = ROOT / "docs/superpowers/specs/2026-10-31-tidyshot-small-seams-design.md"
  text = design.read_text()
  old = "CT-2's test keeps its direct read, or the suite line is 2350, not 2352.\n"
  new = old + (
      "\nBuilt on `small-seams` from the plan `docs/superpowers/plans/2026-10-31-small-seams.md`: the full suite "
      f"`{SUITE}` (the baseline's 2318 tests in 193 suites, and 34 tests in two new suite files and six existing "
      "ones) and the Release build `** BUILD SUCCEEDED **` with no `error:` or `warning:` line from the compiler or "
      "the linker. 46 lines carry new or extended marks, 28 in full and 18 in part; recording-r4:217's earlier mark "
      "gained its by-hand part, and recording-r3:416 and :436 stay unmarked. seams.md has section 11's edit: 42 seams, "
      "Lines 410, Alone 182, Completes 279, 6 new seam slots, 97 lines that need two or more seams and 15 seams that "
      "unlock three or fewer; seams of equal Lines keep their old table order, so `SCREENS` is eighth, `URLLOG` 27th "
      "and the first ten seams complete 150 lines. The hand checks of section 9 are "
      "`docs/testing/small-seams-manual-checklist.md`, for Tim.\n")
  assert text.count(old) == 1 and text.endswith(old)
  design.write_text(text.replace(old, new))
  print("design section 12 edited")
  EOF
  python3 /private/tmp/claude-501/ct3plan-task4/design.py .
  ```
  Expected: `design section 12 edited`.

- [ ] **Step 9: Check the whole change.**
  ```bash
  git status --short
  ```
  Expected, in any order, exactly these 12 paths: ` M` for
  `docs/superpowers/notes/2026-10-30-checklist-sweep/seams.md`,
  `docs/superpowers/specs/2026-10-31-tidyshot-small-seams-design.md`,
  `docs/testing/coordinator-harness-manual-checklist.md`, `docs/testing/coordinator-split-manual-checklist.md`,
  `docs/testing/phase-6a-manual-checklist.md`, `docs/testing/phase-7-clop-manual-checklist.md`,
  `docs/testing/recording-r1-manual-checklist.md`, `docs/testing/recording-r2-manual-checklist.md`,
  `docs/testing/recording-r3-manual-checklist.md`, `docs/testing/recording-r4-manual-checklist.md` and
  `docs/testing/small-tweaks-manual-checklist.md`, and `??` for `docs/testing/small-seams-manual-checklist.md`.
  Nothing under `TidyShot/`, `TidyShotTests/` or `project.yml`.

- [ ] **Step 10: Commit.**
  ```bash
  git add docs/testing/coordinator-harness-manual-checklist.md docs/testing/coordinator-split-manual-checklist.md docs/testing/phase-6a-manual-checklist.md docs/testing/phase-7-clop-manual-checklist.md docs/testing/recording-r1-manual-checklist.md docs/testing/recording-r2-manual-checklist.md docs/testing/recording-r3-manual-checklist.md docs/testing/recording-r4-manual-checklist.md docs/testing/small-tweaks-manual-checklist.md docs/testing/small-seams-manual-checklist.md docs/superpowers/notes/2026-10-30-checklist-sweep/seams.md docs/superpowers/specs/2026-10-31-tidyshot-small-seams-design.md
  git commit -m "docs: small seams marks, seams.md, the hand-check checklist and close-out"
  ```
  Expected: `12 files changed, 308 insertions(+), 145 deletions(-)` and
  `create mode 100644 docs/testing/small-seams-manual-checklist.md`. No attribution lines, no session URL; do not
  push. The task's report says that no hand check was run (they are Tim's, in the new checklist).

## Test totals

| After | Tests added | Suite line after |
|---|---|---|
| Baseline | | `Test run with 2318 tests in 193 suites passed` |
| Task 1 (CLOP) | 18 (`CoordinatorClopTests` 15 new, `CoordinatorTrimTests` 1, `CoordinatorEditorUploadTests` 1, `CoordinatorSaveTests` 1) | `Test run with 2336 tests in 194 suites passed` |
| Task 2 (SAVEAS) | 11 (`CoordinatorSaveAsTests` 9 new, `CoordinatorEditorSaveTests` 1, `CoordinatorEditorUploadTests` 1) | `Test run with 2347 tests in 195 suites passed` |
| Task 3 (LOG) | 5 (`CoordinatorRecordingTests` 4, `RecordingRecoveryTests` 1) | `Test run with 2352 tests in 195 suites passed` |
| Task 4 | 0 | `Test run with 2352 tests in 195 suites passed` |

## Plan decisions

1. **Four tasks, as the brief fixes them.** One per seam in the order CLOP, SAVEAS, LOG (design call 11 leaves the order free), then the close-out. Each seam task changes production and runs the Release build.
2. **Test bodies come from the catalogue.** The review's built tree is a reference; where it and `tests-small.md` differ the catalogue wins (design section 12). Each departure is a decision below.
3. **Task 2 adds design 3.4's two Clop checks to `CoordinatorWorldTests`.** Task 1 leaves that file to Task 2, which owns it; the plan's facts check found no task added them and this fixes it.
4. **Task 1.** live()'s doc comment takes an in-between wording in Task 1 (adds 'Clop' after S3 and the clause 'Clop's optimiser, a value that reaches nothing until a request, is built here'), since design 2.4 gives only the final text after all three tasks; Tasks 2 and 3 extend this wording.
5. **Task 1.** CoordinatorWorld's header comment likewise takes an in-between wording that adds only 'Clop (`clop`, over `<root>/tmp/Clop`)'; the Save As panel and 'the two logs' are left for Tasks 2 and 3 (design 3.4 gives the final text).
6. **Task 1.** The design 3.4 checks in CoordinatorWorldTests (`world.clop.runningChecks == 0`, `world.clop.requests.isEmpty`) are not in Task 1, because the brief gives CoordinatorWorldTests to Task 2; they change no test count.
7. **Task 1.** T1 to T5 keep the built bodies, but T5 uses the suite's new `threshold` property (MultipartPlan.standard.threshold) in place of the built local `keptBytes`; the values are the same.
8. **Task 1.** T7 and T8 are lifted from the facts review's scratch tree (the built CoordinatorClopTests.swift); their bodies match the catalogue, and only their doc comments are rewritten.
9. **Task 1.** Every built doc comment is rewritten to the catalogue's Covers lines in key-and-current-line form, plus what stays and whose from lines-small.md; for example, the built T1's 'phase-7-clop :31 (in part)' becomes the hold leg of the full line phase-7-clop:29 (:31), and T7 and T8 lose their 'Review:' prefixes.
10. **Task 1.** T3 adds all three recordings (deleted, next, third) up front, and adds the catalogue's assertions the built test lacked: the card's last Optimizing flag is false, and the third recording takes counter + 2.
11. **Task 1.** CoordinatorClopTests gains three helpers the catalogue does not list (`useCounterTemplate()`, `lastOptimizing(_:)`, and the `threshold` constant) next to the catalogue's addPendingImage, addSavedImage, addPendingRecording, addGIF, isUploaded and exists.
12. **Task 1.** T12 takes only its two named arguments, `(setting:running:)`, and works out the expected Clop line and runningChecks from `setting`, instead of passing the catalogue's four-value rows.
13. **Task 1.** T9 checks the second alert's message prefix as `CaptureDeletion.fileFailureMessage(reason: "")` rather than the literal "Couldn't delete the file: "; the text is the same.
14. **Task 1.** T17 builds the uploaded save-folder record through addSavedImage's own `uploadState:` and `objectLocation:` parameters rather than a later `history.update`, and compares `world.clop.requests` whole instead of by index.
15. **Task 1.** T16 checks files with FileManager inline because CoordinatorTrimTests has no `exists` helper, and asserts that no `resumes at` line was logged (the catalogue's 'not a resume').
16. **Task 1.** T13 also asserts at the end that 4 file uploads were made and that Clop was never asked or checked, beyond the catalogue's per-step log counts.
17. **Task 2.** `live()`'s doc comment and `CoordinatorWorld`'s type doc are replaced whole by a bounded Python script, not an exact-text replace, because Task 1's wording of both is not fixed by the design. The text after Task 2 is given in the step: Env reads '...S3, Clop, the alerts, the shutter sound, the editor window, the card's Save As… panel, the wall clock and `NSLog`...'; World reads '...Clop (`clop`, over `<root>/tmp/Clop`), the card's Save As… panel (`saveAsChooser`; none is built), a clock... a log it reads...'.
18. **Task 2.** `FakeDestination.download(key:to:)` follows design 3.2 and leaves out the built tree's `fileDownloadFailures` script, which no test uses.
19. **Task 2.** `FakeSaveAsChooser` carries design 3.2's doc comment, not the built tree's longer one.
20. **Task 2.** SAVEAS 10 puts the record back in `world.cards.showing` after the editor's upload, as CT-2's test does; the catalogue leaves this step out. Annotate closes the card, and with no card showing the PUT's end removes the pending file and keeps no drag copy, so the 'after' read would download.
21. **Task 2.** SAVEAS 2 and 10 declare `defer { destination.releaseUploads() }`, and SAVEAS 4 declares `defer { destination.releaseDownloads() }`, right after the world's `defer`, per SAVEAS.2's rule. The built tests and CT-2's test declare them mid-test.
22. **Task 2.** SAVEAS E1 stores the save folder before `makeCoordinator()`, following the world's rule; the built test stored it after.
23. **Task 2.** SAVEAS 9 adds an expectation that the suggestion is `Shot.png`, and SAVEAS 10 adds expectations that `fileURL` is the pending file while the PUT is held and that a drag copy is staged after it. Neither is in the catalogue.
24. **Task 2.** SAVEAS 9 and 10 are inserted right after the CT-2 tests they extend, not at the end of their suites, so test 10's anchor (the end of `uploadOfAnUploadOnlyCaptureRemovesItsDragCopyAndEveryReadGivesTheEdit`) stays clear of wherever Task 1 puts T17.
25. **Task 2.** The commit message writes 'Save As' without the ellipsis, which keeps the shell command plain ASCII.
26. **Task 3.** live()'s doc comment in AppEnvironment.swift and CoordinatorWorld's type doc are rewritten whole by an asserted script, with design 2.4's final text and the built tree's text, whatever Tasks 1 and 2 left, instead of a quoted text replace, because their intermediate wording is not fixed by the design.
27. **Task 3.** The 24 coordinator call sites are changed by one Python script that asserts the counts (18 in +Recording, of which 2 become note( and 16 recordingLog(; 4 in +Recovery; 2 in +Upload) instead of 24 quoted replaces; each string is unchanged byte for byte, as design 2.3 says.
28. **Task 3.** The diff check gives Task 3's own numstat exactly for ten files; AppEnvironment.swift and CoordinatorWorld.swift are checked against f991760 instead (31/5 and 20/4, as the built tree has them), and so are the nine production files (+94 -52), because the per-task counts depend on the sibling tasks' doc wording.
29. **Task 3.** LOG.10 point 1 is settled the catalogue's way: the selection step in stopRecordingLogsWhatItDidInEachPhase and the refuse-first ask plus lock-held recording in aSettingsPromptLogsItsAnswerOrWhyItWaits are kept (they ran green, 25 iterations, in a scratch tree), so neither falls back to the designer's form.
30. **Task 3.** aSettingsPromptLogsItsAnswerOrWhyItWaits adds two asserts the catalogue does not list: #expect(coordinator.askingPermission == .camera) on the second (Allow) ask and #expect(coordinator.isCapturing) during the lock-held recording (the built form asserted the opposite, !isCapturing, for its lock-free run).
31. **Task 3.** world.logLines.isEmpty is asserted in all four coordinator tests as LOG.2 and the entries say, where the built tree had it only in stopRecordingLogsWhatItDidInEachPhase.
32. **Task 3.** Test doc comments name lines as `key (:current line)` (for example `recording-r3:162 (:167), in part`) with what stays and whose, following the catalogue's convention rather than the built tree's `recording-r3 :167` form.
33. **Task 3.** The catalogue's LOG.3 header text goes under the MARK as a two-line comment, since the MARK line itself is a short title.
34. **Task 3.** Each held task's cancel defer is declared right after the task is made, as the catalogue's own sequences and the existing CT-1 and CT-2 tests do (it cannot come before the task exists); it still runs before world.removeAll().
35. **Task 4.** Equal-Lines seams keep their old table order in seams.md (sort by Lines, then old position), not CT-2's sort by Lines, Alone, key, because only that reproduces section 11's rows and positions (SCREENS eighth, URLLOG 27th, the first ten complete 150); CT-2's rule gives seventh, 26th and also 150.
36. **Task 4.** The three scripts are written to /private/tmp/claude-501/ct3plan-task4/ and run from there, not piped through `python3 -` as in CT-2's Task 8, so the marks script can run its `grep -c -F` anchor check first and the seams script can run on a copy first with the same code.
37. **Task 4.** Marks are literal strings copied from the catalogue's merged marks, and the script finds the tests a mark names with a regex (Suite.test, then `, .test` shorthand), not CT-2's comma parser, because several marks hold parenthetical notes with commas.
38. **Task 4.** recording-r1:313's mark names CoordinatorDragOutTests.aDragOfAShowingUploadedRecordingStartsOneDownload as its drag test, since the catalogue says to name the drag tests from its note and that is the test pinning 'a drag from that card downloads the file first'.
39. **Task 4.** recording-r4:192's mark keeps the catalogue's phrase 'the coordinator's text, which the line accepts' as a parenthetical after the test name instead of as a bare list element.
40. **Task 4.** The count '46 marked' is 41 first-time marks plus the 5 rewritten existing marks; recording-r4:217 (a deferred line in the design's count) is a separate 47th edit and the script prints it apart.
41. **Task 4.** seams.md also gains a `CT-3:` note bullet in each of the CLOP, SAVEAS and LOG sections and one sentence in the header's Source paragraph (as CT-2 did for EDITOR), and CLOP's Live line is reworded to the built `{ ClopApp.runningBundleID() != nil }`, beyond the Shape lines section 11 names.
42. **Task 4.** A joined entry is noted 'also `<home seam>`, in part since CT-3' ('deferred in CT-3' for recording-r4:217) under the row it joins, and the home entry of phase-6a:199 keeps its CT-2 annotation as '(also `EDITOR`, in part since CT-2; and `PINS`)'.
43. **Task 4.** Step 7 checks the nine changed TidyShot files with `git diff --name-only main -- TidyShot/` and gives the design's +94 -52 only as 'about', because the merged tree is stated to differ by one blank line and the built diff cannot be applied here.
44. **Task 4.** tests-small.md and lines-small.md get no header edit (CT-2's Task 8 edited its notes' headers), because the brief lists only marks, seams.md, the checklist and the design's section 12.
45. **Task 4.** The 'Fake extensions' line for phase-6a:172 in seams.md is left as it is; whether the new FakeDestination now closes that gap is Task 2's finding.
46. **The held tasks in Task 3's prompt tests** (`askWithoutAPrompt`, the `second` and `quit` tasks) are gated with `TaskWatch` but not cancelled in a `defer`, as the existing D31 form in `CoordinatorRecordingTests` is (CoordinatorRecordingTests.swift:331-336, :366-371 at f991760). In a passing run none is held; in a failing one the camera ask stays parked until the process ends.
47. **The flaky upload-queue test.** `UploadQueueTests.aSidecarUnwritableDuringThePartsFailsTheJobBeforeComplete` fails about one full run in six on the baseline. A full run that fails only on it, or only in `RecordingTrimTests`' three fixture tests seen once in the planning runs, is rerun once and both lines reported; neither is changed.
