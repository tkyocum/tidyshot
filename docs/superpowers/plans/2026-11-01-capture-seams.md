# TidyShot Capture Seams (CT-4), Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The two capture seams: a value origin the save path reads instead of ScreenCaptureKit's objects (`TARGET`), and the capture source and selector behind `AppEnvironment` (`CAPSRC`, built on it). 28 tests are added and one existing test gains a step; 44 of the 68 lines these seams reach get their marks (23 in full, 21 in part) and 24 are deferred. The suite goes from `Test run with 2352 tests in 195 suites passed` to `Test run with 2380 tests in 197 suites passed`. Nothing a user sees changes.

**Architecture:** `docs/superpowers/specs/2026-11-01-tidyshot-capture-seams-design.md` ("the design") is the specification. Its catalogue `docs/superpowers/notes/2026-11-01-capture-seams/tests-capture.md` gives every test, and `lines-capture.md` beside it every line. When this plan and either disagree, "Plan decisions" at the end says why.
- **Task 1, `TARGET`:** `CaptureOrigin`, `CaptureTarget.origin`, the internal `save(_:from:intent:)` that `save(_:intent:)` forwards to, `CaptureSamples`, the new `CoordinatorCaptureSaveTests` with T1 to T10.
- **Task 2, `TARGET`:** T11 to T21 in the same suite. No production change.
- **Task 3, `CAPSRC`:** value `CaptureDisplay`, `CaptureWindow` and `ScreenContent`, the `CaptureSource` and `CaptureSelecting` protocols on the environment with `CaptureEngine` and `SelectionController` conforming, `FakeCaptureSource` and `FakeSelector`, the new `CoordinatorCaptureSourceTests` with C1 to C7, and C8 as a step in `CoordinatorRecordingTests`.
- **Task 4, close-out:** the marks, seams.md, `docs/testing/capture-seams-manual-checklist.md` and the design's built notes.

**Tech Stack:** Swift 6 language mode with default `MainActor` isolation and `NonisolatedNonsendingByDefault`, Swift Testing, AppKit, ScreenCaptureKit, XcodeGen 2.46, Python 3 for Task 4's scripts.

**Tried before writing:** each task's writer applied its own steps to a copy of the tree at 705bce0 and ran them; then the four tasks were applied in order, exactly as written, to one fresh copy with a `git init` base. Every anchor matched once and every step applied. The full suite read `2362 tests in 196 suites` after Task 1, `2373 in 196` after Task 2, `2380 in 197` after Task 3 and again after Task 4; the Release build succeeded after Tasks 1, 3 and 4 with only the two tool lines; each task's new and changed suites passed 5 iterations. Task 4's marks script printed `44 lines marked (40 for the first time, 4 extended), 1 deferred line's mark reworded` and its seams.md script `seams.md: 42 seams, Lines 440, Alone 173, Completes 279`. After that run Task 2's two duplicate helpers were dropped (decision 5) and the save suite rerun green.

Work happens on the branch `capture-seams` (from `main` at 5c2cc33; the design at 705bce0, docs only). This plan is committed on `capture-seams` before Task 1, so the clean-tree checks below see a clean tree. Line numbers are 705bce0's; once a task has grown a file, find the place by the quoted text.

## Global Constraints

- **The phase's hard constraints** (context, with "never commit" adapted: every task commits, nothing is pushed):
  - Production changes are limited to the two seams: the value capture target the save path reads, and the capture
    source (engine and selector) behind `AppEnvironment`. No behaviour change a user could see: the same pixels, files,
    names, clipboard, notices, history and log lines. No `private` member opened for tests. No other seam (`SCROLL`,
    `STAGE`, `RECCHROME`, `COVERS`, `SELINT` stay out). Whether `CAPSRC` is worth its diff for the lines it unlocks on
    its own is a call the design makes openly for Tim.
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
  From CT-3 section 5, still binding: `TidyShot/` changes only as section 2 says, and no `private` member opens; a test that would need more is reported, not forced. No test touches `AppSettings.shared`, `NSPasteboard.general`, the Keychain, `UNUserNotificationCenter`, `NSWorkspace`, `NSRunningApplication`, `NSScreen.screens`, the `tmp/` statics, a window ordered front, a panel shown, the screen, a camera, a microphone, a sound, the real Clop app or the network. History is loaded with `history.load()`, never `start()`. `HistoryStore` prunes on the real `Date()`. Held fakes are cancellable and single-entry; a held call is never awaited directly: the test runs it in a `Task` and gates it with `eventually`, UploadQueueTests.swift:42 and `TaskWatch`, Fakes:454, while a call nothing holds is awaited directly; a held task is cancelled or released in a `defer` declared right after `defer { world.removeAll() }`. Each test owns its world and defaults suite; suites are `@Suite(.timeLimit(.minutes(1)))` with no `.serialized`, built in `init() throws` with `world.settings.showOverlay = false` (a card's screen reads `NSScreen`, +Overlay.swift:9, :55-62). The tests' `MovieSamples` decoder is untouched.
  
  This phase's own rules (tests-capture.md TARGET.2 and CAPSRC.2 give the values):
  - **An explicit intent everywhere.** The forwarder's and every entry point's default `.standard` reads `AppSettings.shared` (CaptureIntent.swift:42-44); the `TARGET` tests call the three-argument entry, which has none. A save stores a folder first (`world.storeSaveFolder()`, World:175-180) or is copy-only or `.uploadOnly`, so `ensureFolder` never builds an `NSOpenPanel` (SaveLocation.swift:30-44).
  - **Names and the clock.** `writeFile`'s `FileNamer` reads `Date()` (+Save:251): a test that reads a name sets the template `Shot`; a test with two saves and no template asserts distinct names only.
  - **The thumbnail.** `finishSave` starts an unawaited thumbnail write under `<root>/thumbnails/` (+Save:288-310), so every test that saves a record ends with `eventually` on the record's `thumbnailFileName`.
  - **Out of reach, not driven.** `.pin` (`PINS`, +Pins.swift:31), a `.desktopPicture` or `.customImage` fill (`BGFILL`, BackgroundFillSource.swift:12-13), a save with no stored folder (`FOLDER`), any path into `runSelfTimer` (`STAGE`, +Capture:297-307), `recordingCanStart` (`TMPDIRS`, +Recording:213, :249, :354), All-in-One's `.fullscreen` (`NSCursor.arrow.set()`, +Capture:54), `covers` with `hideDesktopIconsWhileCapturing` on (`COVERS`). `scrollCapture.run` is never reached: a test-built display has no `live` object, so `runScrolling` stops at its guard after the 100 pt check and the store.
  - **The held overlay.** `world.selector.holds = true`, `defer { world.selector.answer(nil) }`, the entry in a `Task` with `defer { task.cancel() }` and a `TaskWatch`, `eventually { world.selector.isWaiting }`, assert, answer, `eventually { watch.hasReturned }`. Never two held at once.
  - **Window display ids.** A window target's id is `CGGetDisplaysWithPoint` on the host (CE:94-99): no test asserts on it.
  - **C4 runs the real `TextRecognizer`** on a 40 x 20 red image (+Capture:273), as `TextRecognizerTests` already do in the same run (call 5).
- **The suite command.** Run the full suite with:
  ```bash
  xcodegen generate && xcodebuild test -project TidyShot.xcodeproj -scheme TidyShot -destination 'platform=macOS' -derivedDataPath .build 2>&1 | grep -E "Test run with|error:|TEST"
  ```
  and one suite with `-only-testing:TidyShotTests/<Suite>` added before `2>&1`. Baseline `Test run with 2352 tests in 195 suites passed` (5c2cc33, 705bce0). The Release build:
  ```bash
  xcodegen generate && xcodebuild -project TidyShot.xcodeproj -scheme TidyShot -configuration Release -derivedDataPath .build-rel build 2>&1 | grep -E "error:|warning:|BUILD"
  ```
  prints `** BUILD SUCCEEDED **` and no compiler or linker `error:` or `warning:`. Known noise, not failures: two `History file could not be read or decoded` lines, `com.apple.linkd.autoShortcut`, about 40 `MDB_MAP_FULL` lines, the `iOSSimulator: … sharedServiceContextForDeveloperDir:error:` line, and in Release the `appintentsmetadataprocessor … warning: Metadata extraction skipped` line. A full run that fails only on `UploadQueueTests.aSidecarUnwritableDuringThePartsFailsTheJobBeforeComplete` or `RecordingTrimTests.aKeyframeIntervalFixtureHasASyncSampleEveryInterval(reorders:)` is rerun once (decision 6).
- **Counting.** `xcodebuild` counts each `@Test` function once, whatever its arguments; each new test file is one suite.
- **Commits.** After every task, with the task's message, no attribution lines and no session URL. Never push, never switch branches. No task runs the app; the hand checks are Tim's.

---

### Task 1: The save path over a value origin (`CaptureOrigin`, `save(_:from:intent:)`), `CaptureSamples`, and T1 to T10 [integration]

**Files:**
- Modify `TidyShot/Capture/CaptureTarget.swift`: the `areaRect` extension (:35-41) is replaced by `CaptureTarget.origin`,
  and `CaptureOrigin` follows it, before `struct CaptureOptions` (:43) (design 2.1). Only section 2.1's part of this file:
  the three SC-typed cases (:4-9) and `CaptureError` (:66-74) are Task 3's and stay as they are.
- Modify `TidyShot/App/AppCoordinator+Save.swift`: `save(_:intent:)` (:15-25) becomes the forwarder and the new
  `save(_:from:intent:)` takes its body; the two target reads after `persist` (:62, :64); `withWindowBackground` (:81-86,
  :94-97); `copyOnly`'s head (:111-112) (design 2.1). `persist` (:140) and everything after it is unchanged and moves
  down 6 lines.
- Create `TidyShotTests/Support/CaptureSamples.swift` (design 3.1, whole; the review's built file byte for byte).
- Create `TidyShotTests/CoordinatorCaptureSaveTests.swift`: the suite, its helpers (catalogue TARGET.2 rule 9) and T1 to
  T10 (catalogue TARGET.3). Task 2 adds T11 to T21 before its closing `}`.
- Not in this task: `CoordinatorWorld.swift` (unchanged by `TARGET`, design 3.1), `AppEnvironment.swift`, every
  `CAPSRC` region (design 2.2), and `docs/testing/` (Task 4 marks the lines).

**Interfaces:**
- Consumes (at 705bce0; `TidyShot/` and `TidyShotTests/` there are 5c2cc33's):
  - Production, changed by this task: `func save(_ result: CaptureResult, intent: CaptureIntent = .standard) async -> CaptureRecord?`
    (TidyShot/App/AppCoordinator+Save.swift:16, `@discardableResult`), its seven callers in AppCoordinator+Capture.swift
    (:11, :70, :137, :159, :178, :218, :337) untouched; `private func withWindowBackground(_ result: CaptureResult) async -> CaptureResult`
    (:81); `private func copyOnly(_ result: CaptureResult, sender: String?) async` (:111); `var areaRect: CGRect?` on
    `CaptureTarget` (TidyShot/Capture/CaptureTarget.swift:38, read only at +Save:64).
  - Production, unchanged: `private func persist(png: Data, image: ScaledImage, action: AfterCaptureAction, destination: UploadTarget?, alreadyOnClipboard: Bool, captureDisplayID: CGDirectDisplayID) async -> CaptureRecord?`
    (+Save:140-141); `var displayID: CGDirectDisplayID` on `CaptureTarget` (CaptureTarget.swift:14-20; a window's is
    `CaptureEngine.displayID(containing:)`); `struct CaptureResult { let image: CGImage; let scale: CGFloat; let target: CaptureTarget }`
    (:59-64); `nonisolated struct ScaledImage: Sendable { let image: CGImage; let scale: CGFloat }` and
    `var scaled: ScaledImage` on `CaptureResult` (TidyShot/Output/ScaledImage.swift:6-10, :14);
    `nonisolated struct CaptureIntent: Equatable, Sendable` with `init(action: AfterCaptureAction, copyOnly: Bool = false, then: Then = .none, sender: String? = nil)`,
    `init(urlAction: URLCommand.Action?, setting: AfterCaptureAction, sender: String? = nil)` and
    `@MainActor static var standard` (TidyShot/Capture/CaptureIntent.swift:5, :22, :30, :42-44);
    `nonisolated enum AfterCaptureAction: String, CaseIterable, Identifiable, Sendable { case upload, uploadOnly, save }`
    (TidyShot/Settings/AppSettings.swift:4-24); `enum Action` on `URLCommand` with `case upload, save, copy, annotate, pin`
    (TidyShot/URLScheme/URLCommand.swift:48-49); on `AppCoordinator` (TidyShot/App/AppCoordinator.swift):
    `let history: HistoryStore` (:18), `let pendingFiles: PendingFileStore` (:21), `let dragFiles: DragFileStore` (:25),
    `var lastCaptureURL: URL?` (:81), `@ObservationIgnored var latestCapture: (id: UUID, image: ScaledImage)?` (:133),
    `@ObservationIgnored var latestCaptureArea: (id: UUID, rect: CGRect)?` (:136),
    `@ObservationIgnored var clipboardOwner: EditorClipboard.Owner?` (:257);
    `struct Owner: Equatable, Sendable { let recordID: UUID; let changeCount: Int }` in `EditorClipboard`
    (TidyShot/Editor/Persistence/EditorClipboard.swift:9-12); on `HistoryStore` (TidyShot/History/HistoryStore.swift):
    `private(set) var records: [CaptureRecord]` (:11), `func load()` (:40), `func record(id: UUID) -> CaptureRecord?` (:87),
    `var failedRecords: [CaptureRecord]` (:127); on `CaptureRecord` (TidyShot/History/CaptureRecord.swift):
    `enum UploadState: Codable, Equatable, Sendable { case none; case uploading(fraction: Double); case uploaded(url: URL, key: String); case failed(message: String) }` (:49-54),
    `let id: UUID` (:56), `var fileURL: URL?` (:60), `var fileIsTemporary: Bool` (:63), `var thumbnailFileName: String?` (:66),
    `var pixelWidth: Int` (:67), `var pixelHeight: Int` (:68), `var uploadState: UploadState` (:70), `var byteCount: Int?` (:105),
    `var uploadedURL: URL?` (:185), `var uploadedKey: String?` (:191), `var isFailed: Bool` (:262);
    on `AppSettings`: `copyImageToClipboard` (:92), `showNotification` (:93), `playSound` (:94), `fileNameTemplate` (:98),
    `alsoCopyImageWhenUploading` (:100), `showOverlay` (:101), `windowBackground` (:161), `backgroundStyle: BackgroundStyle` (:164),
    `var currentCounter: Int` (:461); `private(set) var currentURL: URL?` and `func store(_ url: URL) throws` on `SaveLocation`
    (TidyShot/Output/SaveLocation.swift:12, :23); `let directory: URL` on `PendingFileStore`
    (TidyShot/Output/PendingFileStore.swift:9; `write(_:id:ext:)` writes `<directory>/<id>.<ext>`, :21-26);
    `func folder(for id: UUID) -> URL` on `DragFileStore` (TidyShot/Output/DragFileStore.swift:24);
    `init(fill: BackgroundFill = .gradient(0), padding: Double = 48, cornerRadius: Double = 12, shadow: Bool = true, aspect: BackgroundAspect = .auto)`
    on `BackgroundStyle` (TidyShot/Background/BackgroundStyle.swift:15-16); `static let gradients: [GradientPreset]` on
    `BackgroundPresets`, index 1 `Ocean` (TidyShot/Background/BackgroundPresets.swift:16, :18);
    `nonisolated enum UploadError: LocalizedError, Equatable, Sendable` with `case httpStatus(Int, body: String)` and
    `case noHTTPResponse`, described `Server returned HTTP <status>: <body>` and `No HTTP response.`, and
    `case notConfigured`, `No upload destination is configured.` (TidyShot/Upload/Destination.swift:155, :186-192);
    `static let defaultAccount = "default"` on `KeychainCredentialStore` (TidyShot/Upload/KeychainCredentialStore.swift:28)
    and `func delete(account: String) throws` on `InMemoryCredentialStore` (:80).
  - The harness (unchanged): `CoordinatorWorld` (TidyShotTests/Support/CoordinatorWorld.swift: `let root: URL` :28,
    `let settings` :35, `let saveLocation` :36, `let credentials: InMemoryCredentialStore` :38, `let notifier` :41,
    `let cards` :42, `let clipboard` :43, `let editors` :46, `let factory` :54, `private(set) var shutterCount` :58,
    `var logLines: [String]` :114, `func makeCoordinator() -> AppCoordinator` :155, `func removeAll()` :165,
    `@discardableResult func storeSaveFolder() throws -> URL` :175-180, returning `<root>/Saved/`);
    `func eventually(_ condition: () async -> Bool) async throws` (TidyShotTests/UploadQueueTests.swift:42, 2 s);
    in TidyShotTests/Support/CoordinatorFakes.swift: `FakeNotifier.Call` with `case saved(title: String, file: String)`,
    `case uploaded(url: URL, copied: Bool)`, `case error(title: String, message: String, subtitle: String? = nil)` and
    `case notice(title: String, body: String, subtitle: String? = nil)` (:9-18), `private(set) var calls` (:20),
    `var errors: [(title: String, message: String)]` (:23); `FakeCards` with `private(set) var calls: [Call]` (:86),
    `var showing: Set<UUID>` (:88), `func dragFiles(for id: UUID) -> [URL?]` (:130),
    `func updates(for id: UUID) -> [CaptureRecord.UploadState]` (:138); `FakeClipboard` with `enum Copy` (`.pngAndTIFF`,
    `.url(URL)` among them, :157-165), `private(set) var copies: [Copy]` (:167), `private(set) var pngs: [Data]` (:169);
    `FakeDestinationFactory.standard` (:258) and `var askedConfigs: [S3DestinationConfig]` (:267);
    `FakeDestination` (TidyShotTests/Support/FakeDestination.swift: `let state: Mutex<State>` :136 with
    `failuresRemaining` :12, `failure: UploadError` :13, `uploads: [(key: String, data: Data, contentType: String, cacheControl: String?)]` :15,
    `uploadAttempts` :17, `holdingUploadsRemaining` :26, `heldUploads` :28;
    `func releaseUploads(throwing error: (any Error)? = nil)` :264; `publicURL(for:)` is `https://snap.tky.io/<key>` :282-284);
    `EditorPixels` (TidyShotTests/Support/EditorPixels.swift: `static func image(width: Int, height: Int, white: Bool = false) throws -> CGImage` :9,
    `static func decoded(_ png: Data) throws -> (image: CGImage, scale: CGFloat)` :22,
    `static func pixel(_ png: Data, x: Int, y: Int) throws -> [Int]` :50, `@MainActor static func worldRed() throws -> [Int]` :71);
    `func editor(for id: UUID) -> FakeEditor?` on `FakeEditors` (TidyShotTests/Support/EditorFakes.swift:162).
- Produces, production (Task 3 compiles `CaptureTarget.origin` unchanged over its value types, design 2.3):
  ```swift
  // TidyShot/Capture/CaptureTarget.swift
  extension CaptureTarget {
      var origin: CaptureOrigin { get }   // main-actor: a window's display id calls CaptureEngine.displayID(containing:)
  }
  nonisolated struct CaptureOrigin: Equatable, Sendable {
      enum Kind: Equatable, Sendable { case display, area(CGRect), window }
      var kind: Kind
      var displayID: CGDirectDisplayID
      var areaRect: CGRect? { get }
      var isWindow: Bool { get }
  }
  // TidyShot/App/AppCoordinator+Save.swift (CaptureTarget.areaRect is gone; its one reader now reads the origin's)
  @discardableResult
  func save(_ result: CaptureResult, intent: CaptureIntent = .standard) async -> CaptureRecord?   // forwards
  @discardableResult
  func save(_ captured: ScaledImage, from origin: CaptureOrigin, intent: CaptureIntent) async -> CaptureRecord?
  private func withWindowBackground(_ image: ScaledImage, from origin: CaptureOrigin) async -> ScaledImage
  private func copyOnly(_ image: ScaledImage, sender: String?) async
  ```
- Produces, `CaptureSamples.swift`: `nonisolated enum CaptureSamples` with `static let displayID: CGDirectDisplayID = 1`,
  `static func image(width: Int, height: Int, scale: CGFloat = 2, white: Bool = false) throws -> ScaledImage`,
  `static let display: CaptureOrigin`, `static let window: CaptureOrigin`,
  `static func area(_ rect: CGRect = CGRect(x: 100, y: 80, width: 200, height: 150)) -> CaptureOrigin`,
  `static func fileNames(in folder: URL) -> [String]`.
- Produces, `CoordinatorCaptureSaveTests` (Task 2 adds its tests to this struct and uses these): `let world: CoordinatorWorld`;
  the private helpers `var destination: FakeDestination`,
  `@discardableResult func save(_ coordinator: AppCoordinator, _ image: ScaledImage, _ origin: CaptureOrigin, _ intent: CaptureIntent) async -> CaptureRecord?`,
  `func isUploaded(_ coordinator: AppCoordinator, _ id: UUID) -> Bool`, `func thumbnailLanded(_ coordinator: AppCoordinator, _ id: UUID) -> Bool`,
  `func exists(_ url: URL?) -> Bool`, `func fileSize(_ url: URL) throws -> Int?`,
  `func openedEditor(_ id: UUID) async throws -> FakeEditor` (Task 2's T13 and T17 use it); the nested
  `nonisolated enum UploadFailureCause: Sendable { case denied, offline }` with `error`, `attempts`, `message`.

**Tests** (catalogue section 3, `docs/superpowers/notes/2026-11-01-capture-seams/tests-capture.md`, TARGET.3):
1. `capturesUnderOneTemplateTakeTheNextFreeNameAlsoAfterARelaunch`: T1, tests-capture.md:297; M.
2. `withAlsoCopyImageTheImageIsOnTheClipboardUntilTheUploadEndsThenTheLink`: T2, :317; M; the upload held.
3. `aWindowCaptureOnOceanIsComposedInTheFileTheClipboardAndTheUpload`: T3, :341; M.
4. `copyOnlyPutsTheImageOnTheClipboardAndNothingElse(showNotification:)`: T4, :362; M; two arguments.
5. `aSaveAndCopyImageCaptureSavesCopiesAndAsksForNoDestination(intent:)`: T5, :381; M; two arguments.
6. `theNextCaptureLandsInTheNewlyStoredFolder`: T6, :405; S.
7. `uploadAndCopyURLLeavesTheClipboardEmptyUntilTheLink`: T7, :416; S; the upload held.
8. `withNoDestinationTwoCapturesCopyTheImageAndPostOneNotice(action:)`: T8, :431; M; two arguments.
9. `aFailingUploadKeepsTheFileAndFailsTheRecord(cause:alsoCopy:)`: T9, :467; M; three arguments.
10. `anUploadOnlyCaptureKeepsOnlyAPendingFileUntilItsUploaded(origin:cardShows:)`: T10, :489; M; four arguments; the upload held.
- 10 tests (S 2, M 8), 5 parameterized (T4, T5, T8, T9, T10), each counted once. One new suite file.
- Focused run: `-only-testing:TidyShotTests/CoordinatorCaptureSaveTests` prints `Test run with 10 tests in 1 suite passed`.
- Full suite: `Test run with 2362 tests in 196 suites passed` (2352 + 10; one new suite).
- Also: `git diff --stat 705bce0 -- TidyShot/` lists exactly `TidyShot/App/AppCoordinator+Save.swift` and
  `TidyShot/Capture/CaptureTarget.swift` and ends `2 files changed, 42 insertions(+), 18 deletions(-)`. The Release
  build prints `** BUILD SUCCEEDED **` and no `error:` or `warning:` line beyond the two tool lines the Global
  Constraints name.

**Commit:** `refactor: the capture save path over a CaptureOrigin value, CaptureSamples, the first ten save tests`

**Tried before writing:** every block below was applied as written to a copy of the tree at 705bce0 (`git archive` into
a scratch folder with a `git init` base; each "Replace" anchor asserted once in its file, each new file absent). There
`xcodegen generate` and the new suite ran `Test run with 10 tests in 1 suite passed after 0.435 seconds` on the first
compile, with no compiler `warning:` from a changed or new file; 5 iterations (`-test-iterations 5
-run-tests-until-failure`) passed; the full suite ran `Test run with 2362 tests in 196 suites passed after 62.254
seconds` with only the known noise; the Release build printed `** BUILD SUCCEEDED **` with only the two tool lines; and
`git diff --stat` read `2 files changed, 42 insertions(+), 18 deletions(-)` for `TidyShot/` and `4 files changed, 558
insertions(+), 18 deletions(-)` in all. The `+Save` file that results is byte-identical to the design review's built
file (`.superpowers/sdd/ct4/built/TidyShot/App/AppCoordinator+Save.swift`).

**Steps:**

- [ ] Check the starting point. From the repository root:
  ```bash
  git branch --show-current
  git status --short -- TidyShot TidyShotTests
  git diff --stat 705bce0 -- TidyShot/ TidyShotTests/
  ls TidyShotTests/Support/CaptureSamples.swift TidyShotTests/CoordinatorCaptureSaveTests.swift
  grep -rn "areaRect\|result\.target\|withWindowBackground(\|copyOnly(" TidyShot/
  ```
  Expected: `capture-seams`, then nothing, then nothing (the branch has changed only docs since `main`), then two
  `No such file or directory` lines, then exactly these eleven lines:
  ```
  TidyShot/Capture/CaptureTarget.swift:38:    var areaRect: CGRect? {
  TidyShot/App/AppCoordinator+Save.swift:12:    /// `copyOnly(_:sender:)`; `then` opens the editor or a pin on the new record. A window capture
  TidyShot/App/AppCoordinator+Save.swift:18:        let result = await withWindowBackground(result)
  TidyShot/App/AppCoordinator+Save.swift:20:            await copyOnly(result, sender: intent.sender)
  TidyShot/App/AppCoordinator+Save.swift:62:                                         captureDisplayID: result.target.displayID) else { return nil }
  TidyShot/App/AppCoordinator+Save.swift:64:        latestCaptureArea = result.target.areaRect.map { (id: record.id, rect: $0) }
  TidyShot/App/AppCoordinator+Save.swift:81:    private func withWindowBackground(_ result: CaptureResult) async -> CaptureResult {
  TidyShot/App/AppCoordinator+Save.swift:82:        guard settings.windowBackground, case .window = result.target else { return result }
  TidyShot/App/AppCoordinator+Save.swift:86:        let fillImage = await BackgroundFillSource.fillImage(for: style.fill, displayID: result.target.displayID)
  TidyShot/App/AppCoordinator+Save.swift:97:        return CaptureResult(image: composed, scale: scale, target: result.target)
  TidyShot/App/AppCoordinator+Save.swift:111:    private func copyOnly(_ result: CaptureResult, sender: String?) async {
  ```
  Any other line is a reader of `areaRect`, the result's target or the two private steps that the design did not
  count: stop and report it.

#### The seam (design 2.1)

- [ ] In `TidyShot/Capture/CaptureTarget.swift`, replace the `areaRect` extension (:35-41) with `origin`, and add
  `CaptureOrigin` after it, before `struct CaptureOptions` (:43). `areaRect` moves onto the value, which is its only
  reader's (+Save:64). Replace:
  ```swift
  extension CaptureTarget {
      /// The rect of an area capture (CoreGraphics global points), nil for a display or a window.
      /// A pin of the newest capture opens over it.
      var areaRect: CGRect? {
          if case .area(let rect, _) = self { rect } else { nil }
      }
  }
  ```
  with:
  ```swift
  extension CaptureTarget {
      /// What the save path reads of this target (`AppCoordinator.save(_:from:intent:)`).
      var origin: CaptureOrigin {
          switch self {
          case .display: CaptureOrigin(kind: .display, displayID: displayID)
          case .area(let rect, _): CaptureOrigin(kind: .area(rect), displayID: displayID)
          case .window: CaptureOrigin(kind: .window, displayID: displayID)
          }
      }
  }

  /// Where a capture came from, as the save path reads it: a display, an area or a window, and the
  /// display it came from. A value, not the ScreenCaptureKit objects, so the suite can build one
  /// (seams.md section 3, `TARGET`); `CaptureTarget.origin` makes it from a live target.
  nonisolated struct CaptureOrigin: Equatable, Sendable {
      /// An area carries its rect, in CoreGraphics global points.
      enum Kind: Equatable, Sendable { case display, area(CGRect), window }
      var kind: Kind
      /// `CaptureTarget.displayID`: the card's screen under `Show on` and the desktop picture's display.
      var displayID: CGDirectDisplayID
      /// The rect of an area capture, nil for a display or a window. A pin of the newest capture opens over it.
      var areaRect: CGRect? { if case .area(let rect) = kind { rect } else { nil } }
      /// Only a window capture goes on the Capture tab's background.
      var isWindow: Bool { kind == .window }
  }
  ```
  `CaptureOrigin` is a `nonisolated struct` with a nested `Equatable, Sendable` enum, the shape of `CaptureIntent` and
  its `Then` (CaptureIntent.swift:5-12). `origin` stays main-actor: `.window`'s `displayID` calls the main-actor
  `CaptureEngine.displayID(containing:)` (CaptureTarget.swift:18).

- [ ] In `TidyShot/App/AppCoordinator+Save.swift`, `save(_:intent:)` becomes the forwarder and its body moves into
  `save(_:from:intent:)` (:16-26). The forwarder reads `result.scaled` once, where the body read it after the background
  step; the statement sequence below is otherwise the same. Replace:
  ```swift
      func save(_ result: CaptureResult, intent: CaptureIntent = .standard) async -> CaptureRecord? {
          // Before the copy-only branch, so `action=copy` gets the background too.
          let result = await withWindowBackground(result)
          if intent.copyOnly {
              await copyOnly(result, sender: intent.sender)
              return nil
          }
          latestCapture = nil
          latestCaptureArea = nil
          let image = result.scaled
          let action = intent.action
  ```
  with:
  ```swift
      func save(_ result: CaptureResult, intent: CaptureIntent = .standard) async -> CaptureRecord? {
          await save(result.scaled, from: result.target.origin, intent: intent)
      }

      /// `save(_:intent:)` over the image and what the save path reads of its target (`CaptureOrigin`).
      /// The suite calls it with an origin it builds (seams.md section 3, `TARGET`). The intent has no
      /// default, so nothing here reads `AppSettings.shared`.
      @discardableResult
      func save(_ captured: ScaledImage, from origin: CaptureOrigin, intent: CaptureIntent) async -> CaptureRecord? {
          // Before the copy-only branch, so `action=copy` gets the background too.
          let image = await withWindowBackground(captured, from: origin)
          if intent.copyOnly {
              await copyOnly(image, sender: intent.sender)
              return nil
          }
          latestCapture = nil
          latestCaptureArea = nil
          let action = intent.action
  ```
  The `@discardableResult` and the doc comment above the forwarder (:5-15) stay.

- [ ] In the same file, the two reads after `persist` take the origin (:62, :64). Replace:
  ```swift
                                           captureDisplayID: result.target.displayID) else { return nil }
          // Before anything below, so a pin of this record opens over the spot it came from.
          latestCaptureArea = result.target.areaRect.map { (id: record.id, rect: $0) }
  ```
  with:
  ```swift
                                           captureDisplayID: origin.displayID) else { return nil }
          // Before anything below, so a pin of this record opens over the spot it came from.
          latestCaptureArea = origin.areaRect.map { (id: record.id, rect: $0) }
  ```

- [ ] In the same file, the background step takes and returns the image (:81-86). Replace:
  ```swift
      private func withWindowBackground(_ result: CaptureResult) async -> CaptureResult {
          guard settings.windowBackground, case .window = result.target else { return result }
          let style = settings.backgroundStyle
          let content = result.image
          let scale = result.scale
          let fillImage = await BackgroundFillSource.fillImage(for: style.fill, displayID: result.target.displayID)
  ```
  with:
  ```swift
      private func withWindowBackground(_ image: ScaledImage, from origin: CaptureOrigin) async -> ScaledImage {
          guard settings.windowBackground, origin.isWindow else { return image }
          let style = settings.backgroundStyle
          let content = image.image
          let scale = image.scale
          let fillImage = await BackgroundFillSource.fillImage(for: style.fill, displayID: origin.displayID)
  ```

- [ ] In the same file, its two returns (:94-97). Replace:
  ```swift
              log("Background: \(reason), keeping the window capture")
              return result
          }
          return CaptureResult(image: composed, scale: scale, target: result.target)
  ```
  with:
  ```swift
              log("Background: \(reason), keeping the window capture")
              return image
          }
          return ScaledImage(image: composed, scale: scale)
  ```
  The detached compose between them (:87-93) is unchanged: it takes the same `CGImage`, `CGFloat`, style and fill.

- [ ] In the same file, `copyOnly` takes the image (:111-112). Replace:
  ```swift
      private func copyOnly(_ result: CaptureResult, sender: String?) async {
          let image = result.scaled
  ```
  with:
  ```swift
      private func copyOnly(_ image: ScaledImage, sender: String?) async {
  ```
  Its body already reads `image.image` and `image.scale` (:113-131).

- [ ] Check the production change:
  ```bash
  grep -rn "areaRect\|result\.target\|withWindowBackground(\|copyOnly(" TidyShot/
  git diff --stat 705bce0 -- TidyShot/
  ```
  Expected, the grep, exactly these eight lines:
  ```
  TidyShot/Capture/CaptureTarget.swift:56:    var areaRect: CGRect? { if case .area(let rect) = kind { rect } else { nil } }
  TidyShot/App/AppCoordinator+Save.swift:12:    /// `copyOnly(_:sender:)`; `then` opens the editor or a pin on the new record. A window capture
  TidyShot/App/AppCoordinator+Save.swift:17:        await save(result.scaled, from: result.target.origin, intent: intent)
  TidyShot/App/AppCoordinator+Save.swift:26:        let image = await withWindowBackground(captured, from: origin)
  TidyShot/App/AppCoordinator+Save.swift:28:            await copyOnly(image, sender: intent.sender)
  TidyShot/App/AppCoordinator+Save.swift:71:        latestCaptureArea = origin.areaRect.map { (id: record.id, rect: $0) }
  TidyShot/App/AppCoordinator+Save.swift:88:    private func withWindowBackground(_ image: ScaledImage, from origin: CaptureOrigin) async -> ScaledImage {
  TidyShot/App/AppCoordinator+Save.swift:118:    private func copyOnly(_ image: ScaledImage, sender: String?) async {
  ```
  and the diffstat lists the two files and ends `2 files changed, 42 insertions(+), 18 deletions(-)`. The app target
  builds now; the tests come next.

#### The support and the suite (design 3.1, catalogue TARGET.2 and TARGET.3)

- [ ] Create `TidyShotTests/Support/CaptureSamples.swift` with exactly this content (design 3.1; the review's built
  file). It builds no ScreenCaptureKit object: the image is `EditorPixels.image` (EditorPixels.swift:9-16) at a scale,
  and the display id is the suite's own number. `CoordinatorWorld` is unchanged:
  ```swift
  import CoreGraphics
  import Foundation
  import Testing
  @testable import TidyShot
  /// Captures as the save path takes them (`AppCoordinator.save(_:from:intent:)`): an image of a pixel size at a scale,
  /// and where it came from. No ScreenCaptureKit object is made; the display id is the suite's own number.
  nonisolated enum CaptureSamples {
      static let displayID: CGDirectDisplayID = 1
      /// A red capture of `width` by `height` pixels at `scale`, white when `white`.
      static func image(width: Int, height: Int, scale: CGFloat = 2, white: Bool = false) throws -> ScaledImage { ScaledImage(image: try EditorPixels.image(width: width, height: height, white: white), scale: scale) }
      static let display = CaptureOrigin(kind: .display, displayID: displayID)
      static let window = CaptureOrigin(kind: .window, displayID: displayID)
      static func area(_ rect: CGRect = CGRect(x: 100, y: 80, width: 200, height: 150)) -> CaptureOrigin { CaptureOrigin(kind: .area(rect), displayID: displayID) }
      /// The names of the files directly in `folder`, sorted; none when it does not exist.
      static func fileNames(in folder: URL) -> [String] { ((try? FileManager.default.contentsOfDirectory(atPath: folder.path(percentEncoded: false))) ?? []).sorted() }
  }
  ```

- [ ] Create `TidyShotTests/CoordinatorCaptureSaveTests.swift` with exactly this content. T1 and T2 are the design
  review's built tests (`.superpowers/sdd/ct4/built/TidyShotTests/CoordinatorCaptureSaveTests.swift`) with their doc
  comments filled in; T3 to T10 are written from the catalogue. The rules (TARGET.2) as the bodies apply them: every
  test opens with `defer { world.removeAll() }`; a test that holds the upload (T2, T7, T10) declares
  `defer { destination.releaseUploads() }` right after it, so it runs first, gates on `heldUploads.count == 1`, and
  gates again on the link after the release; every save passes an explicit intent and stores a folder first, T4's
  copy-only save too (its check is no file in that folder); a test that reads a name sets the template `Shot` (`FileNamer` reads `Date()`, +Save:251); and every
  test that saves a record ends with `eventually` on each record's `thumbnailFileName` (rule 8; T4 makes none). Doc
  comments name each line by catalogue key and current line, and for an in-part line what stays and whose
  (`lines-capture.md`):
  ```swift
  import CoreGraphics
  import Foundation
  import Testing
  @testable import TidyShot

  /// The capture save path on a built coordinator over a value origin (capture seams design 2.1, `TARGET`):
  /// `save(_:from:intent:)` and what it runs, `persist`, `writeFile`, `writePendingFile`, `copyOnly` and
  /// `withWindowBackground`. Images and origins come from `CaptureSamples`; no ScreenCaptureKit object is made.
  /// Every save passes an explicit intent (the forwarder's `.standard` reads `AppSettings.shared`) and stores a
  /// folder first unless it is upload-only, so no folder panel is built, even by a copy-only save that regresses. Overlay is off, since a
  /// card on screen reads the screens. A test that saves a record waits for its thumbnail before it ends, so a
  /// late write cannot recreate a folder in the removed root. The one held fake is the destination's upload,
  /// released in a `defer` declared right after `removeAll()`'s.
  @Suite(.timeLimit(.minutes(1)))
  struct CoordinatorCaptureSaveTests {
      let world: CoordinatorWorld

      init() throws {
          world = try CoordinatorWorld()
          world.settings.showOverlay = false
      }

      private var destination: FakeDestination { world.factory.standard }

      @discardableResult
      private func save(_ coordinator: AppCoordinator, _ image: ScaledImage, _ origin: CaptureOrigin,
                        _ intent: CaptureIntent) async -> CaptureRecord? {
          await coordinator.save(image, from: origin, intent: intent)
      }

      private func isUploaded(_ coordinator: AppCoordinator, _ id: UUID) -> Bool {
          coordinator.history.record(id: id)?.uploadedURL != nil
      }

      private func thumbnailLanded(_ coordinator: AppCoordinator, _ id: UUID) -> Bool {
          coordinator.history.record(id: id)?.thumbnailFileName != nil
      }

      private func exists(_ url: URL?) -> Bool {
          guard let url else { return false }
          return FileManager.default.fileExists(atPath: url.path(percentEncoded: false))
      }

      private func fileSize(_ url: URL) throws -> Int? {
          try FileManager.default.attributesOfItem(atPath: url.path(percentEncoded: false))[.size] as? Int
      }

      private func openedEditor(_ id: UUID) async throws -> FakeEditor {
          try await eventually { world.editors.editor(for: id) != nil }
          return try #require(world.editors.editor(for: id))
      }

      /// T1, phase-1:36 (:38), full. Three captures under the template `Shot`, two on one coordinator and one on a
      /// second over the same folder and history (a relaunch), are `Shot.png`, `Shot 2.png` and `Shot 3.png` in the
      /// chosen folder, each with its `Screenshot saved`. The template's date tokens are `FileNamerTests`'.
      @Test func capturesUnderOneTemplateTakeTheNextFreeNameAlsoAfterARelaunch() async throws {
          defer { world.removeAll() }
          let folder = try world.storeSaveFolder()
          world.settings.fileNameTemplate = "Shot"
          let counter = world.settings.currentCounter
          let intent = CaptureIntent(action: .save)
          let first = world.makeCoordinator()
          let a = try #require(await save(first, try CaptureSamples.image(width: 40, height: 30), CaptureSamples.area(), intent))
          let b = try #require(await save(first, try CaptureSamples.image(width: 40, height: 30), CaptureSamples.area(), intent))
          let second = world.makeCoordinator()
          second.history.load()
          let c = try #require(await save(second, try CaptureSamples.image(width: 40, height: 30), CaptureSamples.area(), intent))

          #expect(a.fileURL?.lastPathComponent == "Shot.png")
          #expect(b.fileURL?.lastPathComponent == "Shot 2.png")
          #expect(c.fileURL?.lastPathComponent == "Shot 3.png")
          #expect(world.settings.currentCounter == counter)
          #expect(CaptureSamples.fileNames(in: folder) == ["Shot 2.png", "Shot 3.png", "Shot.png"])
          #expect(world.notifier.calls == [.saved(title: "Screenshot saved", file: "Shot.png"),
                                           .saved(title: "Screenshot saved", file: "Shot 2.png"),
                                           .saved(title: "Screenshot saved", file: "Shot 3.png")])
          #expect(first.lastCaptureURL == b.fileURL)
          #expect(second.lastCaptureURL == c.fileURL)
          #expect(second.history.records.count == 3)
          #expect(world.logLines.isEmpty)
          try await eventually { thumbnailLanded(first, a.id) && thumbnailLanded(first, b.id) && thumbnailLanded(second, c.id) }
      }

      /// T2, phase-2:30 (:47) and phase-3:49 (:90), full; phase-4a:120 (:215), in part: the capture's own clipboard
      /// copy and owner, which the editor's upload then replaces. With Also copy image on, the image is on the
      /// clipboard while the upload is held, then the link replaces it. What stays of phase-4a:120 is the editor
      /// closing at once (`EDPLACE`).
      @Test func withAlsoCopyImageTheImageIsOnTheClipboardUntilTheUploadEndsThenTheLink() async throws {
          defer { world.removeAll() }
          defer { destination.releaseUploads() }
          let folder = try world.storeSaveFolder()
          world.settings.fileNameTemplate = "Shot"
          world.settings.alsoCopyImageWhenUploading = true
          destination.state.withLock { $0.holdingUploadsRemaining = 1 }
          let coordinator = world.makeCoordinator()
          let record = try #require(await save(coordinator, try CaptureSamples.image(width: 40, height: 30),
                                               CaptureSamples.display, CaptureIntent(action: .upload)))
          try await eventually { destination.state.withLock { $0.heldUploads.count } == 1 }

          let file = folder.appending(path: "Shot.png")
          #expect(coordinator.history.record(id: record.id)?.uploadState == .uploading(fraction: 0))
          #expect(world.clipboard.copies == [.pngAndTIFF])
          #expect(coordinator.clipboardOwner == EditorClipboard.Owner(recordID: record.id, changeCount: 1))
          #expect(destination.state.withLock { $0.uploads }.isEmpty)
          #expect(record.fileURL == file)
          #expect(record.fileIsTemporary == false)
          #expect(world.shutterCount == 1)
          #expect(world.notifier.calls.isEmpty)
          #expect(world.factory.askedConfigs.count == 1)

          destination.releaseUploads()
          try await eventually { isUploaded(coordinator, record.id) }
          let link = try #require(coordinator.history.record(id: record.id)?.uploadedURL)
          #expect(world.clipboard.copies == [.pngAndTIFF, .url(link)])
          #expect(link.absoluteString.hasPrefix("https://snap.tky.io/"))
          #expect(coordinator.history.record(id: record.id)?.uploadedKey?.hasSuffix(".png") == true)
          #expect(world.notifier.calls == [.uploaded(url: link, copied: true)])
          let uploads = destination.state.withLock { $0.uploads }
          #expect(uploads.count == 1)
          #expect(uploads.first?.data == (try Data(contentsOf: file)))
          #expect(uploads.first?.contentType == "image/png")
          #expect(coordinator.history.record(id: record.id)?.byteCount == uploads.first?.data.count)
          let decoded = try EditorPixels.decoded(try #require(world.clipboard.pngs.first))
          #expect(decoded.image.width == 40)
          #expect(decoded.image.height == 30)
          #expect(decoded.scale == 2)
          try await eventually { thumbnailLanded(coordinator, record.id) }
      }

      /// T3, phase-7c:179 (:233), in part. A 400 x 300 px window capture at scale 2 with Add background on and the
      /// Ocean gradient (padding 48 pt, so 96 px a side) is 592 x 492 px in the file, on the clipboard, in the
      /// upload and in the record, with the window in the middle and the gradient at the corner, and logs nothing.
      /// What stays is the card's thumbnail drawn on screen (`SCREENS`); `sips` is this test's decode.
      @Test func aWindowCaptureOnOceanIsComposedInTheFileTheClipboardAndTheUpload() async throws {
          defer { world.removeAll() }
          let folder = try world.storeSaveFolder()
          world.settings.fileNameTemplate = "Shot"
          world.settings.windowBackground = true
          world.settings.backgroundStyle = BackgroundStyle(fill: .gradient(1), padding: 48)
          world.settings.alsoCopyImageWhenUploading = true
          #expect(BackgroundPresets.gradients[1].name == "Ocean")
          let coordinator = world.makeCoordinator()
          let record = try #require(await save(coordinator, try CaptureSamples.image(width: 400, height: 300),
                                               CaptureSamples.window, CaptureIntent(action: .upload)))
          try await eventually { isUploaded(coordinator, record.id) }

          let link = try #require(coordinator.history.record(id: record.id)?.uploadedURL)
          let file = folder.appending(path: "Shot.png")
          #expect(record.fileURL == file)
          let saved = try Data(contentsOf: file)
          let uploads = destination.state.withLock { $0.uploads }
          try #require(uploads.count == 1)
          let copied = try #require(world.clipboard.pngs.first)
          for png in [saved, copied, uploads[0].data] {
              let decoded = try EditorPixels.decoded(png)
              #expect(decoded.image.width == 592)
              #expect(decoded.image.height == 492)
              #expect(decoded.scale == 2)
          }
          #expect(record.pixelWidth == 592)
          #expect(record.pixelHeight == 492)
          let red = try EditorPixels.worldRed()
          #expect(try EditorPixels.pixel(saved, x: 296, y: 246) == red)
          let corner = try EditorPixels.pixel(saved, x: 1, y: 1)
          #expect(corner != red)
          #expect(corner[3] == 255)
          #expect(coordinator.history.record(id: record.id)?.byteCount == uploads[0].data.count)
          #expect(try fileSize(file) == uploads[0].data.count)
          #expect(world.logLines.isEmpty)
          #expect(world.clipboard.copies == [.pngAndTIFF, .url(link)])
          try await eventually { thumbnailLanded(coordinator, record.id) }
      }

      /// T4, phase-6b:117 (:143), full. `action=copy` puts the image on the clipboard and nothing else: no file in the
      /// save folder or `pending`, no card, no record, no upload; the shutter follows Play sound; `Image copied`
      /// names the pixel size and `From <sender>`, and with Show notification off nothing posts. The newest card's
      /// capture and clipboard owner stay, so its Annotate still opens its own capture. The shutter heard stays by
      /// hand for good.
      @Test(arguments: [true, false])
      func copyOnlyPutsTheImageOnTheClipboardAndNothingElse(showNotification: Bool) async throws {
          defer { world.removeAll() }
          let folder = try world.storeSaveFolder()
          world.settings.showNotification = showNotification
          let coordinator = world.makeCoordinator()
          let previous = UUID()
          coordinator.latestCapture = (id: previous, image: try CaptureSamples.image(width: 4, height: 2))
          let owner = EditorClipboard.Owner(recordID: previous, changeCount: 0)
          coordinator.clipboardOwner = owner

          let record = await save(coordinator, try CaptureSamples.image(width: 400, height: 300), CaptureSamples.area(),
                                  CaptureIntent(action: .save, copyOnly: true, sender: "Shortcuts"))

          #expect(record == nil)
          #expect(world.clipboard.copies == [.pngAndTIFF])
          let decoded = try EditorPixels.decoded(try #require(world.clipboard.pngs.first))
          #expect(decoded.image.width == 400)
          #expect(decoded.image.height == 300)
          #expect(world.shutterCount == 1)
          if showNotification {
              #expect(world.notifier.calls == [.notice(title: "Image copied", body: "400 × 300 px", subtitle: "From Shortcuts")])
          } else {
              #expect(world.notifier.calls.isEmpty)
          }
          #expect(coordinator.history.records.isEmpty)
          #expect(CaptureSamples.fileNames(in: folder).isEmpty)
          #expect(CaptureSamples.fileNames(in: coordinator.pendingFiles.directory).isEmpty)
          #expect(world.cards.calls.isEmpty)
          #expect(world.factory.askedConfigs.isEmpty)
          #expect(coordinator.latestCapture?.id == previous)
          #expect(coordinator.clipboardOwner == owner)
          #expect(world.logLines.isEmpty)
      }

      /// T5. coordinator-split:36 (:36), in part; phase-2:32 (:51), phase-6b:116 (:142, the second argument) and
      /// small-tweaks:13 (:16), full. An area capture under `Save and copy image`, and `action=save` under
      /// `Upload only`, saves `Shot.png` in the folder, copies the same PNG, asks for no destination, posts
      /// `Screenshot saved`, enables Reveal Last Capture (`lastCaptureURL`), keeps the area for a pin, and records
      /// the file's own size with no upload state. What stays of coordinator-split:36: the ⌃⇧4 drag and the area's
      /// width times the display scale (`CAPSRC`), the card with its thumbnail and `Saved` (`SCREENS`), `Reveal Last
      /// Capture` selecting the file in Finder (`WORKSPACE`), and the audible shutter (by hand for good).
      /// small-tweaks:13's row text is `RecentCaptureFormattingTests`'; Finder's figure on screen stays by hand.
      @Test(arguments: [CaptureIntent(action: .save), CaptureIntent(urlAction: .save, setting: .uploadOnly)])
      func aSaveAndCopyImageCaptureSavesCopiesAndAsksForNoDestination(intent: CaptureIntent) async throws {
          defer { world.removeAll() }
          let folder = try world.storeSaveFolder()
          world.settings.fileNameTemplate = "Shot"
          let coordinator = world.makeCoordinator()
          let rect = CGRect(x: 100, y: 80, width: 200, height: 150)

          let record = try #require(await save(coordinator, try CaptureSamples.image(width: 40, height: 30),
                                               CaptureSamples.area(rect), intent))

          let file = folder.appending(path: "Shot.png")
          #expect(CaptureSamples.fileNames(in: folder) == ["Shot.png"])
          #expect(record.fileURL == file)
          #expect(record.fileIsTemporary == false)
          let saved = try Data(contentsOf: file)
          let decoded = try EditorPixels.decoded(saved)
          #expect(decoded.image.width == 40)
          #expect(decoded.image.height == 30)
          #expect(decoded.scale == 2)
          #expect(world.clipboard.copies == [.pngAndTIFF])
          #expect(world.clipboard.pngs == [saved])
          #expect(world.factory.askedConfigs.isEmpty)
          #expect(record.uploadState == .none)
          #expect(world.shutterCount == 1)
          #expect(world.notifier.calls == [.saved(title: "Screenshot saved", file: "Shot.png")])
          #expect(coordinator.lastCaptureURL == record.fileURL)
          #expect(coordinator.latestCaptureArea?.id == record.id)
          #expect(coordinator.latestCaptureArea?.rect == rect)
          #expect(coordinator.clipboardOwner == EditorClipboard.Owner(recordID: record.id, changeCount: 1))
          #expect(try fileSize(file) == record.byteCount)
          #expect(record.byteCount == saved.count)
          #expect(coordinator.history.records.map(\.id) == [record.id])
          #expect(coordinator.latestCapture?.id == nil)
          #expect(world.logLines.isEmpty)
          try await eventually { thumbnailLanded(coordinator, record.id) }
      }

      /// T6, phase-1:45 (:48), full. A folder stored between two captures (where Settings > General's Choose… lands,
      /// `SaveLocation.store`) takes the next capture; the first stays in the old folder. The Choose… panel itself
      /// stays by hand (`SaveLocationStoreTests` pins the store).
      @Test func theNextCaptureLandsInTheNewlyStoredFolder() async throws {
          defer { world.removeAll() }
          let a = try world.storeSaveFolder()
          let b = world.root.appending(path: "B", directoryHint: .isDirectory)
          try FileManager.default.createDirectory(at: b, withIntermediateDirectories: true)
          world.settings.fileNameTemplate = "Shot"
          let coordinator = world.makeCoordinator()
          let intent = CaptureIntent(action: .save)

          let first = try #require(await save(coordinator, try CaptureSamples.image(width: 40, height: 30),
                                              CaptureSamples.display, intent))
          try world.saveLocation.store(b)
          let second = try #require(await save(coordinator, try CaptureSamples.image(width: 40, height: 30),
                                               CaptureSamples.display, intent))

          #expect(first.fileURL == a.appending(path: "Shot.png"))
          #expect(second.fileURL == b.appending(path: "Shot.png"))
          #expect(CaptureSamples.fileNames(in: a) == ["Shot.png"])
          #expect(CaptureSamples.fileNames(in: b) == ["Shot.png"])
          #expect(world.saveLocation.currentURL?.standardizedFileURL == b.standardizedFileURL)
          try await eventually { thumbnailLanded(coordinator, first.id) && thumbnailLanded(coordinator, second.id) }
      }

      /// T7, phase-2:25 (:40), in part. `Upload and copy URL` with Also copy image off leaves the clipboard empty and
      /// posts nothing while the upload is held, then puts the link there alone; the file is saved too. What stays:
      /// the link pasted into Slack opening a working page (the real bucket, by hand for good) and the overlay's
      /// checkmark (`SCREENS`); the URL's shape is `S3DestinationConfigTests`' and `ObjectKeyNamerTests`'.
      @Test func uploadAndCopyURLLeavesTheClipboardEmptyUntilTheLink() async throws {
          defer { world.removeAll() }
          defer { destination.releaseUploads() }
          let folder = try world.storeSaveFolder()
          world.settings.fileNameTemplate = "Shot"
          destination.state.withLock { $0.holdingUploadsRemaining = 1 }
          let coordinator = world.makeCoordinator()
          let record = try #require(await save(coordinator, try CaptureSamples.image(width: 40, height: 30),
                                               CaptureSamples.display, CaptureIntent(action: .upload)))
          try await eventually { destination.state.withLock { $0.heldUploads.count } == 1 }

          #expect(world.clipboard.copies.isEmpty)
          #expect(coordinator.clipboardOwner == nil)
          #expect(world.notifier.calls.isEmpty)

          destination.releaseUploads()
          try await eventually { isUploaded(coordinator, record.id) }
          let link = try #require(coordinator.history.record(id: record.id)?.uploadedURL)
          let file = folder.appending(path: "Shot.png")
          #expect(world.clipboard.copies == [.url(link)])
          #expect(world.notifier.calls == [.uploaded(url: link, copied: true)])
          #expect(record.fileURL == file)
          #expect(exists(file))
          try await eventually { thumbnailLanded(coordinator, record.id) }
      }

      /// T8. coordinator-split:42 (:42), in part (`.uploadOnly`); phase-2:33 (:52), in part (`.upload`); phase-3:48
      /// (:89), full (`.uploadOnly`, with T21 for the retry); phase-4a:119 (:210), in part (`.upload`: the capture's
      /// own clipboard copy and owner). With no credentials two captures ask for no destination, copy the image each
      /// time and post one `Upload not configured` in all. `Upload and copy URL` saves both files with no upload
      /// state; `Upload only` keeps both in `pending` as failed. What stays: the cards saying `Upload failed`
      /// (`SCREENS`) and the menu's `Retry Failed Uploads` (`STATUSMENU`) for coordinator-split:42, whose Retry half
      /// is `CoordinatorUploadTests.retryFailedUploadsSaysOnceWithoutCredentialsAndEnqueuesWithThem`; Settings >
      /// Upload's empty fields and no keychain error (`UPLOADFORM`) for phase-2:33; the editor staying open
      /// (`EDPLACE`) for phase-4a:119.
      @Test(arguments: [AfterCaptureAction.upload, .uploadOnly])
      func withNoDestinationTwoCapturesCopyTheImageAndPostOneNotice(action: AfterCaptureAction) async throws {
          defer { world.removeAll() }
          try world.credentials.delete(account: KeychainCredentialStore.defaultAccount)
          let folder = try world.storeSaveFolder()
          world.settings.fileNameTemplate = "Shot"
          let coordinator = world.makeCoordinator()
          let intent = CaptureIntent(action: action)

          let first = try #require(await save(coordinator, try CaptureSamples.image(width: 40, height: 30),
                                              CaptureSamples.display, intent))
          let second = try #require(await save(coordinator, try CaptureSamples.image(width: 40, height: 30),
                                               CaptureSamples.display, intent))

          #expect(world.factory.askedConfigs.isEmpty)
          #expect(world.clipboard.copies == [.pngAndTIFF, .pngAndTIFF])
          #expect(coordinator.clipboardOwner == EditorClipboard.Owner(recordID: second.id, changeCount: 2))
          #expect(world.notifier.errors.filter { $0.title == "Upload not configured" }.count == 1)
          #expect(world.shutterCount == 2)
          #expect(world.logLines.isEmpty)
          switch action {
          case .upload:
              #expect(first.uploadState == .none)
              #expect(second.uploadState == .none)
              #expect(CaptureSamples.fileNames(in: folder) == ["Shot 2.png", "Shot.png"])
              #expect(world.notifier.calls == [
                  .error(title: "Upload not configured",
                         message: "Set up a destination in Settings > Upload. The capture was saved and the image is on the clipboard."),
                  .saved(title: "Screenshot saved", file: "Shot.png"),
                  .saved(title: "Screenshot saved", file: "Shot 2.png")])
              #expect(coordinator.history.failedRecords.isEmpty)
          case .uploadOnly:
              for record in [first, second] {
                  #expect(record.uploadState == .failed(message: "No upload destination is configured."))
                  #expect(record.fileIsTemporary)
                  #expect(record.fileURL == coordinator.pendingFiles.directory.appending(path: "\(record.id.uuidString).png"))
                  #expect(exists(record.fileURL))
                  #expect(world.cards.updates(for: record.id).isEmpty)
              }
              #expect(CaptureSamples.fileNames(in: folder).isEmpty)
              #expect(world.notifier.calls == [
                  .error(title: "Upload not configured",
                         message: "Set up a destination in Settings > Upload, then retry from Recent Captures. The image is on the clipboard.")])
              #expect(coordinator.history.failedRecords.count == 2)
          case .save:
              Issue.record("T8 drives the two upload actions only")
          }
          try await eventually { thumbnailLanded(coordinator, first.id) && thumbnailLanded(coordinator, second.id) }
      }

      /// T9's two failures: a refused upload (403, not retried) and an offline one (no HTTP response, three attempts),
      /// the stand-in for Wi-Fi off.
      nonisolated enum UploadFailureCause: Sendable {
          case denied
          case offline

          var error: UploadError {
              switch self {
              case .denied: .httpStatus(403, body: "AccessDenied: Access Denied")
              case .offline: .noHTTPResponse
              }
          }

          var attempts: Int {
              switch self {
              case .denied: 1
              case .offline: 3
              }
          }

          var message: String {
              switch self {
              case .denied: "Server returned HTTP 403: AccessDenied: Access Denied"
              case .offline: "No HTTP response."
              }
          }
      }

      /// T9, phase-2:48 (:77), in part. An upload that fails keeps the saved file, fails the record with the error's
      /// text, tells the card and posts `Upload failed`, and leaves nothing on the clipboard unless Also copy image is
      /// on. What stays: the card drawn with Retry (`SCREENS`; the `.failed` update is pinned) and Wi-Fi off for real
      /// (by hand for good; the offline cause stands in). The row's `Upload failed` is
      /// `RecentCaptureFormattingTests.detailIsTheTimeTheSizeAndEachUploadState`'.
      @Test(arguments: [(UploadFailureCause.denied, false), (.denied, true), (.offline, false)])
      func aFailingUploadKeepsTheFileAndFailsTheRecord(cause: UploadFailureCause, alsoCopy: Bool) async throws {
          defer { world.removeAll() }
          let folder = try world.storeSaveFolder()
          world.settings.fileNameTemplate = "Shot"
          world.settings.alsoCopyImageWhenUploading = alsoCopy
          destination.state.withLock {
              $0.failuresRemaining = cause.attempts
              $0.failure = cause.error
          }
          let coordinator = world.makeCoordinator()

          let record = try #require(await save(coordinator, try CaptureSamples.image(width: 40, height: 30),
                                               CaptureSamples.display, CaptureIntent(action: .upload)))
          try await eventually { coordinator.history.record(id: record.id)?.isFailed == true }

          let file = folder.appending(path: "Shot.png")
          let stored = try #require(coordinator.history.record(id: record.id))
          #expect(stored.uploadState == .failed(message: cause.message))
          #expect(destination.state.withLock { $0.uploadAttempts } == cause.attempts)
          #expect(world.notifier.calls == [.error(title: "Upload failed", message: cause.message)])
          #expect(world.cards.updates(for: record.id).last == .failed(message: cause.message))
          #expect(exists(file))
          #expect(record.fileURL == file)
          #expect(stored.fileURL == file)
          #expect(world.clipboard.copies == (alsoCopy ? [.pngAndTIFF] : []))
          #expect(coordinator.history.failedRecords.map(\.id) == [record.id])
          try await eventually { thumbnailLanded(coordinator, record.id) }
      }

      /// T10. phase-5:179 (:191) and small-tweaks:16 (:22), full with T21 (the failed upload and the retry);
      /// phase-6b:66 (:81), in part. An upload-only capture of any origin writes nothing in the save folder, keeps
      /// `pending/<id>.png` at its PNG's size while the upload is held, then drops the file and takes the uploaded
      /// size, with the link alone on the clipboard. With a card showing, the file moves to the card's drag folder
      /// under the key's name instead of being deleted. What stays of phase-6b:66: the Quick Access stack and Recent
      /// Captures on screen (`SCREENS`), and that All-in-One builds these captures (`CAPSRC`).
      @Test(arguments: [(CaptureSamples.display, false), (CaptureSamples.window, false), (CaptureSamples.area(), false),
                        (CaptureSamples.area(), true)])
      func anUploadOnlyCaptureKeepsOnlyAPendingFileUntilItsUploaded(origin: CaptureOrigin, cardShows: Bool) async throws {
          defer { world.removeAll() }
          defer { destination.releaseUploads() }
          let folder = try world.storeSaveFolder()
          destination.state.withLock { $0.holdingUploadsRemaining = 1 }
          let coordinator = world.makeCoordinator()

          let record = try #require(await save(coordinator, try CaptureSamples.image(width: 40, height: 30), origin,
                                               CaptureIntent(action: .uploadOnly)))
          try await eventually { destination.state.withLock { $0.heldUploads.count } == 1 }

          let pending = coordinator.pendingFiles.directory.appending(path: "\(record.id.uuidString).png")
          #expect(CaptureSamples.fileNames(in: folder).isEmpty)
          #expect(record.fileURL == pending)
          #expect(exists(pending))
          #expect(record.fileIsTemporary)
          #expect(try fileSize(pending) == record.byteCount)
          #expect(coordinator.history.record(id: record.id)?.uploadState == .uploading(fraction: 0))
          #expect(world.clipboard.copies.isEmpty)
          #expect(world.notifier.calls.isEmpty)
          #expect(coordinator.lastCaptureURL == nil)
          #expect(coordinator.latestCaptureArea?.id == origin.areaRect.map { _ in record.id })
          #expect(coordinator.latestCaptureArea?.rect == origin.areaRect)

          if cardShows {
              world.cards.showing.insert(record.id)
          }
          destination.releaseUploads()
          try await eventually { isUploaded(coordinator, record.id) }

          let uploaded = try #require(coordinator.history.record(id: record.id))
          let link = try #require(uploaded.uploadedURL)
          let key = try #require(uploaded.uploadedKey)
          let uploads = destination.state.withLock { $0.uploads }
          try #require(uploads.count == 1)
          #expect(!exists(pending))
          #expect(CaptureSamples.fileNames(in: coordinator.pendingFiles.directory).isEmpty)
          #expect(uploaded.fileURL == nil)
          #expect(!uploaded.fileIsTemporary)
          #expect(uploaded.byteCount == uploads[0].data.count)
          #expect(world.clipboard.copies == [.url(link)])
          #expect(world.notifier.calls == [.uploaded(url: link, copied: true)])
          if cardShows {
              let name = try #require(key.split(separator: "/").last.map(String.init))
              let kept = coordinator.dragFiles.folder(for: record.id).appending(path: name)
              #expect(exists(kept))
              let decoded = try EditorPixels.decoded(try Data(contentsOf: kept))
              #expect(decoded.image.width == 40)
              #expect(decoded.image.height == 30)
              #expect(world.cards.dragFiles(for: record.id).last == .some(kept))
          } else {
              #expect(world.cards.dragFiles(for: record.id).isEmpty)
          }
          try await eventually { thumbnailLanded(coordinator, record.id) }
      }
  }
  ```
  What the bodies rely on, all at 705bce0: with no credentials `makeDestination()` returns nil before the factory is
  asked (+Upload:40), so T8 sees `askedConfigs` empty and the warning once per coordinator (+Upload:26-31), posted in
  `finishSave` before the shutter and `Screenshot saved` (+Save:205-207, :229-230); an `Upload and copy URL` with no
  destination leaves the record `.none` and `Upload only` leaves it `.failed` (+Save:161-169); a 403 is not retried and
  `noHTTPResponse` is, three attempts with the world's `uploadSleep` of `{ _ in }` (Destination.swift:176-183,
  UploadQueue.swift:193, RetryPolicy.swift:10); `markFailed` pushes the record to the card and posts `Upload failed`
  (+Upload:586-591); with no card showing the uploaded pending file is removed, and with one it moves to
  `Drag/<id>/<the key's last component>` and is handed to the card (+Upload:651-655, +DragOut:232-247,
  DragFileName.swift:11-24, DragFileStore.swift:103-109, :132-147); the size becomes the sent bytes (+Upload:666-667);
  the composed canvas is the layout's (BackgroundLayout.swift:20-47: 400 + 2 x 96 by 300 + 2 x 96).

#### Runs, the Release build and the commit

- [ ] Run the new suite alone:
  ```bash
  xcodegen generate && xcodebuild test -project TidyShot.xcodeproj -scheme TidyShot -destination 'platform=macOS' -derivedDataPath .build -only-testing:TidyShotTests/CoordinatorCaptureSaveTests 2>&1 | grep -E "Test run with|error:|TEST"
  ```
  Expected: `✔ Test run with 10 tests in 1 suite passed after …` and `** TEST SUCCEEDED **`. The `error:` lines that
  print are the known noise only (`com.apple.linkd.autoShortcut`, and the `iOSSimulator: …
  sharedServiceContextForDeveloperDir:error:` line where CoreSimulator is out of date). A compile error in the test
  file is fixed in the test file; a fix that would change `TidyShot/` beyond the steps above stops the task, which
  reports it (design 12).

- [ ] Run it five times, so a race in the held upload or the thumbnail wait shows now:
  ```bash
  xcodebuild test -project TidyShot.xcodeproj -scheme TidyShot -destination 'platform=macOS' -derivedDataPath .build -only-testing:TidyShotTests/CoordinatorCaptureSaveTests -test-iterations 5 -run-tests-until-failure 2>&1 | grep -E "Test run with|TEST"
  ```
  Expected: `✔ Test run with 10 tests in 1 suite passed after …` and `** TEST SUCCEEDED **`.

- [ ] Run the full suite:
  ```bash
  xcodegen generate && xcodebuild test -project TidyShot.xcodeproj -scheme TidyShot -destination 'platform=macOS' -derivedDataPath .build 2>&1 | grep -E "Test run with|error:|TEST"
  ```
  Expected: `✔ Test run with 2362 tests in 196 suites passed after …` and `** TEST SUCCEEDED **`. The `error:` lines are
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
  Any other line, for example a concurrency warning about `CaptureOrigin` in `CaptureTarget.swift` or
  `AppCoordinator+Save.swift`, is a failure: stop and report it.

- [ ] Assert what changed:
  ```bash
  git diff --stat 705bce0 -- TidyShot/
  git status --short
  ```
  Expected: the diffstat lists exactly the two files above and ends `2 files changed, 42 insertions(+), 18 deletions(-)`.
  `git status --short` lists ` M TidyShot/App/AppCoordinator+Save.swift`, ` M TidyShot/Capture/CaptureTarget.swift`,
  `?? TidyShotTests/CoordinatorCaptureSaveTests.swift` and `?? TidyShotTests/Support/CaptureSamples.swift`, and nothing
  else (`TidyShot.xcodeproj`, `.build/` and `.build-rel/` are git-ignored).

- [ ] Commit:
  ```bash
  git add TidyShot/App/AppCoordinator+Save.swift TidyShot/Capture/CaptureTarget.swift TidyShotTests/CoordinatorCaptureSaveTests.swift TidyShotTests/Support/CaptureSamples.swift
  git commit -m "refactor: the capture save path over a CaptureOrigin value, CaptureSamples, the first ten save tests"
  ```
  Expected: `4 files changed, 558 insertions(+), 18 deletions(-)`, with `create mode 100644` for the two new files.
  No attribution lines and no session URL in the message; do not push. The report says no hand check was run.

---

### Task 2: The other eleven TARGET tests, T11 to T21, in CoordinatorCaptureSaveTests [integration]

**Files:**
- Modify `TidyShotTests/CoordinatorCaptureSaveTests.swift` (Task 1's file, T1 to T10): add the helpers, the `Canvas`
  cases and the eleven tests T11 to T21 at the end of `struct CoordinatorCaptureSaveTests`, after T10
  (catalogue TARGET.3, tests-capture.md:517-668).
- Not in this task: any file under `TidyShot/` (no production change), `TidyShotTests/Support/CaptureSamples.swift`
  and `CoordinatorWorld.swift` (Task 1 leaves them as these tests need them), and every `docs/testing/` mark (Task 4).

**Interfaces:**
- Consumes (at 705bce0 and as Task 1 leaves the tree; `+Save` line numbers are 705bce0's, Task 1 moves
  `withWindowBackground` and `copyOnly` down 7 and `persist` down 6):
  - Production, unchanged by this task: Task 1's `@discardableResult func save(_ captured: ScaledImage, from origin: CaptureOrigin, intent: CaptureIntent) async -> CaptureRecord?`
    (`AppCoordinator+Save.swift`, after the forwarder `save(_:intent:)` at :16) and
    `nonisolated struct CaptureOrigin: Equatable, Sendable` with `enum Kind { case display, area(CGRect), window }`,
    `var kind`, `var displayID: CGDirectDisplayID`, `var areaRect: CGRect?`, `var isWindow: Bool`
    (`TidyShot/Capture/CaptureTarget.swift`); `nonisolated struct CaptureIntent: Equatable, Sendable` with
    `init(action: AfterCaptureAction, copyOnly: Bool = false, then: Then = .none, sender: String? = nil)` (CaptureIntent.swift:23)
    and `init(urlAction: URLCommand.Action?, setting: AfterCaptureAction, sender: String? = nil)` (:31), `Then` being
    `.none`, `.annotate`, `.pin`; `nonisolated enum AfterCaptureAction: String, CaseIterable, Identifiable, Sendable`
    with `.upload`, `.uploadOnly`, `.save` (AppSettings.swift:4-11); `func retryFailedUploads()` (AppCoordinator+Upload.swift:496);
    `let history: HistoryStore` (AppCoordinator.swift:18), `let pendingFiles: PendingFileStore` (:21) with
    `let directory: URL` (PendingFileStore.swift:9); `func record(id: UUID) -> CaptureRecord?` (HistoryStore.swift:87),
    `var failedRecords: [CaptureRecord]` (:127), `func load()` (:40);
    on `CaptureRecord` `var fileURL: URL?` (:60), `var fileIsTemporary: Bool` (:63), `var pixelWidth: Int`, `var pixelHeight: Int` (:67-68),
    `var byteCount: Int?` (:105), `var uploadedURL: URL?` (:185), `var isFailed: Bool` (:262), `uploadState` with
    `.failed(message:)`; `BackgroundLayout.make(contentSize: CGSize, style: BackgroundStyle, scale: CGFloat) -> BackgroundLayout?`
    and `let canvasSize: CGSize` (BackgroundLayout.swift:20-47); `BackgroundStyle.init(fill:padding:cornerRadius:shadow:aspect:)`
    with defaults 48, 12, true, `.auto` (BackgroundStyle.swift:14-21); `BackgroundFill.gradient(Int)`;
    `BackgroundPresets.gradients[1].name == "Ocean"` (BackgroundPresets.swift:18); on `AppSettings` `windowBackground`
    (:161), `backgroundStyle` (:164), `fileNameTemplate` (:98), `showOverlay` (:101).
  - The harness: `CoordinatorWorld` (`let notifier` :41, `cards` :42, `clipboard` :43, `editors` :46, `factory` :54,
    `var logLines: [String]` :114, `func makeCoordinator() -> AppCoordinator` :155, `func removeAll()` :165,
    `@discardableResult func storeSaveFolder() throws -> URL` :175, `var settings`); `FakeNotifier.Call`
    (`.saved(title:file:)`, `.uploaded(url:copied:)`, `.error(title:message:subtitle: = nil)`, `.notice(title:body:subtitle: = nil)`,
    CoordinatorFakes.swift:9-18); `FakeCards.calls` with `.close(UUID, QuickAccessCloseReason)`; `FakeClipboard.copies`
    (`.pngAndTIFF`, `.url(URL)`, :167) and `pngs: [Data]` (:169); `FakeEditors.built: [FakeEditor]` and
    `func editor(for id: UUID) -> FakeEditor?` (EditorFakes.swift:152-163), `FakeEditor.model`, `.title`, `.representedURL`;
    `EditorModel.base: CGImage` (EditorModel.swift:91), `document`, `hasUnsavedChanges`; `FakeDestination.state`
    (`Mutex<State>`: `uploads: [(key:data:contentType:cacheControl:)]`, `uploadAttempts`, `failuresRemaining`,
    `failure: UploadError`, FakeDestination.swift:13-22, :31); `FakeDestinationFactory.askedConfigs` (CoordinatorFakes.swift:267);
    `TaskWatch.init<Success: Sendable>(_ task: Task<Success, Never>)` and `hasReturned` (:454-457);
    `func eventually(_ condition: () async -> Bool) async throws` (UploadQueueTests.swift:42, 2 s);
    `EditorPixels.decoded(_:) -> (image: CGImage, scale: CGFloat)`, `pixel(_ image: CGImage, x:y:) -> [Int]`,
    `@MainActor worldRed() throws -> [Int]` (EditorPixels.swift); `CaptureSamples.image(width:height:scale:white:)`,
    `.display`, `.window`, `.area(_:)`, `.fileNames(in:)` (Task 1's `CaptureSamples.swift`).
  - Task 1's suite members, used as they are: `let world: CoordinatorWorld` (built in `init() throws` with
    `world.settings.showOverlay = false`), `private var destination: FakeDestination`, `private func save(_ coordinator: AppCoordinator, _ image: ScaledImage, _ origin: CaptureOrigin, _ intent: CaptureIntent) async -> CaptureRecord?`,
    `private func isUploaded(_ coordinator: AppCoordinator, _ id: UUID) -> Bool`,
    `private func thumbnailLanded(_ coordinator: AppCoordinator, _ id: UUID) -> Bool`, `private func exists(_ url: URL?) -> Bool`,
    `private func openedEditor(_ id: UUID) async throws -> FakeEditor` (Task 1 adds the last two for these tests).
- Produces, in `CoordinatorCaptureSaveTests` (all `private` or nested, nothing outside the file reads them):
  - `private func pngAt(_ url: URL?) throws -> (image: CGImage, scale: CGFloat)`
  - `private func turnOceanBackgroundOn()`
  - `nonisolated enum Canvas: CaseIterable, Sendable` with `var content`, `var style: BackgroundStyle`, `var canvas`
  - the eleven tests below.
  These helpers have their own names because Task 1's writer owns `exists`, `openedEditor` and `fileSize` if its tests
  need them; Step 1 checks that no name here is taken.

**Tests** (catalogue section 3, `docs/superpowers/notes/2026-11-01-capture-seams/tests-capture.md`; lines by
`lines-capture.md` key and current line):
11. `actionUploadSavesUploadsAndCopiesTheLinkUnderEitherSetting(setting:)`: T11, tests-capture.md:517; S; two arguments; phase-6b:115 (:141) in full.
12. `aTallCaptureKeepsItsFullPixelSizeInHistory`: T12, :531; S; phase-5:202 (:218) in full.
13. `annotateRunsTheActionThenOpensTheEditorOnTheNewCapture`: T13, :543; M; phase-6b:118 (:144) in part, the `action=pin` half stays (`PINS`).
14. `areaAndFullscreenCapturesKeepThePlainImageWithTheBackgroundOn(origin:)`: T14, :559; S; two arguments; phase-7c:182 (:236) in part, which origin each entry builds stays (`CAPSRC`, `SCROLL`).
15. `aWindowCanvasFollowsTheStyle(canvas:)`: T15, :571; M; twelve arguments; phase-7c:184 (:238) and phase-7c:185 (:239) in full.
16. `withTheBackgroundOffEveryCaptureIsPlainAtOnce`: T16, :596; S; phase-7c:186 (:240) and phase-7c:197 (:254) in full.
17. `aComposedWindowCaptureOpensInTheEditorComposed`: T17, :607; M; phase-7c:187 (:241) in part, the popover's switch stays (`BGPOP`, `EDPLACE`).
18. `copyAndUploadOfAWindowCarryTheComposedImage`: T18, :620; M; phase-7c:188 (:244) in full.
19. `aWindowTooLargeForABackgroundIsSavedPlainWithOneLine`: T19, :632; S; phase-7c:189 (:245) in part, `no bitmap could be made` stays by code reading.
20. `twoWindowCapturesAtOnceAreEachComposedInTheirOwnFile`: T20, :644; L; phase-7c:190 (:246) in full.
21. `anUploadOnlyCaptureThatFailsKeepsItsPendingFileUntilARetrySucceeds`: T21, :656; L; phase-5:179 (:191), phase-3:48 (:89) and small-tweaks:16 (:22), each in full with T8 or T10.
- 11 tests (S 4, M 5, L 2), 3 parameterized (T11, T14, T15), each counted once. No new suite file.
- Focused run: `-only-testing:TidyShotTests/CoordinatorCaptureSaveTests` prints `Test run with 21 tests in 1 suite passed`
  (T1 to T10 and these eleven).
- Full suite: `Test run with 2373 tests in 196 suites passed` (2362 + 11; no new suite).
- No production change: `git diff --stat HEAD -- TidyShot/` is empty before the commit, so there is no Release build.

**Commit:** `test: the TARGET save tests T11 to T21, upload action, tall capture, annotate, window backgrounds and a failed upload-only retry`

**Tried before writing:** the block below was applied as written to a scratch copy of the tree (705bce0 with the design
review's built files, `.superpowers/sdd/ct4/built/`, which carry both seams and `CoordinatorCaptureSaveTests` with T1 and T2
only), after the file's last test. It compiled with no warning from the file, the suite ran
`Test run with 13 tests in 1 suite passed` (T1, T2 and these eleven) and 10 iterations of it passed
(`-test-iterations 10 -run-tests-until-failure`). With `CaptureOrigin.isWindow` forced to `false` in that copy, T15 failed
for every composed canvas (the other window tests fail the same way); the copy was restored. The whole scratch suite
read `Test run with 2367 tests in 197 suites passed`. Its first full run failed once, on
`RecordingTrimTests.aKeyframeIntervalFixtureHasASyncSampleEveryInterval(reorders:)` (`syncTimes == [0, 2, 4]`, a fixture test no
CT-4 file touches) and passed on the second; see "Plan decisions" in the merge.

**Steps:**

- [ ] Check the starting point. From the repository root:
  ```bash
  git branch --show-current
  git status --short -- TidyShot TidyShotTests
  git log -1 --format=%s
  grep -c '@Test' TidyShotTests/CoordinatorCaptureSaveTests.swift
  grep -c '^}' TidyShotTests/CoordinatorCaptureSaveTests.swift
  grep -n 'func pngAt\|func turnOceanBackgroundOn\|enum Canvas' TidyShotTests/CoordinatorCaptureSaveTests.swift
  grep -n 'func save(\|func isUploaded(\|func thumbnailLanded(\|var destination\|func exists(\|func openedEditor(' TidyShotTests/CoordinatorCaptureSaveTests.swift
  ```
  Expected: `capture-seams`; nothing; Task 1's commit message; `10`; `1`; nothing (a name already taken means Task 1's
  file differs from the plan: stop and report); then the six Task 1 members, each once.

- [ ] In `TidyShotTests/CoordinatorCaptureSaveTests.swift`, add the helpers, `Canvas` and T11 to T21 after T10. The file ends
  with the last test's closing brace and the struct's, the only line that starts with `}`. Replace these two lines
  (they occur once at that point, which the `grep -c '^}'` above checked):
  ```swift
      }
  }
  ```
  with the line `    }`, then this text exactly (it begins with a blank line; the two spaces of the list indent are not part of it), then the line `}`:
  ```swift

      // MARK: Window backgrounds, Annotate and the upload actions (T11 to T21)

      /// The PNG at `url`, decoded: its pixels and the scale its DPI gives.
      private func pngAt(_ url: URL?) throws -> (image: CGImage, scale: CGFloat) {
          try EditorPixels.decoded(try Data(contentsOf: try #require(url)))
      }

      /// The Capture tab's background on, with the Ocean gradient at the default 48 pt padding.
      private func turnOceanBackgroundOn() {
          #expect(BackgroundPresets.gradients[1].name == "Ocean")
          world.settings.windowBackground = true
          world.settings.backgroundStyle = BackgroundStyle(fill: .gradient(1), padding: 48)
      }

      /// T11, phase-6b:115 (:141). `action=upload` under each After capture setting: with `Save and copy image` the capture
      /// is saved and uploaded and the clipboard holds the link alone (Also copy image is off); with `Upload only, keep
      /// no local file` nothing lands in the save folder and the pending file is gone once the upload ends. The capture
      /// is a window's, with the background off, so the intent's mapping is shown to hold there too. Stays: the URL
      /// parsing and the `t` command (`CaptureIntentTests.uploadUploadsUnderEverySetting`, the URL command suites).
      @Test(arguments: [AfterCaptureAction.save, .uploadOnly])
      func actionUploadSavesUploadsAndCopiesTheLinkUnderEitherSetting(setting: AfterCaptureAction) async throws {
          defer { world.removeAll() }
          let folder = try world.storeSaveFolder()
          world.settings.fileNameTemplate = "Shot"
          let coordinator = world.makeCoordinator()
          let record = try #require(await save(coordinator, try CaptureSamples.image(width: 40, height: 30),
                                               CaptureSamples.window, CaptureIntent(urlAction: .upload, setting: setting)))
          try await eventually { isUploaded(coordinator, record.id) }

          let stored = try #require(coordinator.history.record(id: record.id))
          let link = try #require(stored.uploadedURL)
          let uploads = destination.state.withLock { $0.uploads }
          #expect(uploads.count == 1)
          #expect(world.clipboard.copies == [.url(link)])
          #expect(world.notifier.calls == [.uploaded(url: link, copied: true)])
          #expect(world.factory.askedConfigs.count == 1)
          if setting == .save {
              let file = folder.appending(path: "Shot.png")
              #expect(record.fileURL == file)
              #expect(stored.fileURL == file)
              #expect(exists(file))
              #expect(CaptureSamples.fileNames(in: folder) == ["Shot.png"])
          } else {
              #expect(record.fileIsTemporary)
              #expect(stored.fileURL == nil)
              #expect(CaptureSamples.fileNames(in: folder) == [])
              #expect(CaptureSamples.fileNames(in: coordinator.pendingFiles.directory) == [])
          }
          try await eventually { thumbnailLanded(coordinator, record.id) }
      }

      /// T12, phase-5:202 (:218). A stitched capture's size is the whole image's: an 8 by 20,000 px capture (a scrolling
      /// result is an area) keeps both numbers in the record, in `history.json` after a relaunch, and in the file, and
      /// the image is copied once (above 16,384 px there is no TIFF; `FakeClipboard` records both forms as `.pngAndTIFF`). Stays: the row's subtitle, which
      /// `RecentCaptureFormattingTests` already pins.
      @Test func aTallCaptureKeepsItsFullPixelSizeInHistory() async throws {
          defer { world.removeAll() }
          try world.storeSaveFolder()
          let coordinator = world.makeCoordinator()
          let record = try #require(await save(coordinator, try CaptureSamples.image(width: 8, height: 20_000),
                                               CaptureSamples.area(), CaptureIntent(action: .save)))
          try await eventually { thumbnailLanded(coordinator, record.id) }

          #expect(record.pixelWidth == 8)
          #expect(record.pixelHeight == 20_000)
          #expect(coordinator.history.record(id: record.id)?.pixelWidth == 8)
          #expect(coordinator.history.record(id: record.id)?.pixelHeight == 20_000)
          let relaunched = world.makeCoordinator()
          relaunched.history.load()
          #expect(relaunched.history.record(id: record.id)?.pixelWidth == 8)
          #expect(relaunched.history.record(id: record.id)?.pixelHeight == 20_000)
          let file = try pngAt(record.fileURL)
          #expect(file.image.width == 8)
          #expect(file.image.height == 20_000)
          #expect(world.clipboard.copies == [.pngAndTIFF])
          #expect(world.logLines.isEmpty)
      }

      /// T13, phase-6b:118 (:144), in part (it extends the CT-2 mark). `action=annotate`: the after-capture action runs (the
      /// file is saved and `Screenshot saved` posts), then the editor opens on the new capture and its card closes as
      /// `.editorOpened`. Stays: the `action=pin` half, a pin opening with the card staying (`PINS`).
      @Test func annotateRunsTheActionThenOpensTheEditorOnTheNewCapture() async throws {
          defer { world.removeAll() }
          let folder = try world.storeSaveFolder()
          world.settings.fileNameTemplate = "Shot"
          let coordinator = world.makeCoordinator()
          let record = try #require(await save(coordinator, try CaptureSamples.image(width: 40, height: 30),
                                               CaptureSamples.area(), CaptureIntent(action: .save, then: .annotate)))
          let editor = try await openedEditor(record.id)

          #expect(exists(folder.appending(path: "Shot.png")))
          #expect(world.notifier.calls == [.saved(title: "Screenshot saved", file: "Shot.png")])
          #expect(editor.representedURL == record.fileURL)
          #expect(editor.title == "Shot.png")
          #expect(editor.model.base.width == 40)
          #expect(editor.model.base.height == 30)
          #expect(world.cards.calls.contains(.close(record.id, .editorOpened)))
          #expect(world.editors.built.count == 1)
          try await eventually { thumbnailLanded(coordinator, record.id) }
      }

      /// T14, phase-7c:182 (:236), in part. With Add background to window captures on, an area and a fullscreen capture are
      /// saved as they are: the file, the record and the clipboard keep the capture's size and scale, and its first
      /// pixel is the capture's own, with no fill. Stays: which origin Previous Area, a scrolling capture and an
      /// All-in-One drag build (`CAPSRC`, and `SCROLL` for the scrolling capture); the rule that an area or a
      /// display origin is plain is pinned here.
      @Test(arguments: [CaptureSamples.display, CaptureSamples.area()])
      func areaAndFullscreenCapturesKeepThePlainImageWithTheBackgroundOn(origin: CaptureOrigin) async throws {
          defer { world.removeAll() }
          try world.storeSaveFolder()
          turnOceanBackgroundOn()
          let coordinator = world.makeCoordinator()
          let record = try #require(await save(coordinator, try CaptureSamples.image(width: 400, height: 300), origin,
                                               CaptureIntent(action: .save)))
          try await eventually { thumbnailLanded(coordinator, record.id) }

          let file = try pngAt(record.fileURL)
          #expect(file.image.width == 400)
          #expect(file.image.height == 300)
          #expect(file.scale == 2)
          #expect(EditorPixels.pixel(file.image, x: 1, y: 1) == (try EditorPixels.worldRed()))
          #expect(record.pixelWidth == 400)
          #expect(record.pixelHeight == 300)
          let copied = try EditorPixels.decoded(try #require(world.clipboard.pngs.first))
          #expect(copied.image.width == 400)
          #expect(copied.image.height == 300)
          #expect(copied.scale == 2)
          #expect(world.logLines.isEmpty)
      }

      /// The Capture tab's canvases for T15: the window's pixels at scale 2, the style, and the canvas size the
      /// layout gives (`BackgroundLayout.make`: padding times the scale on each side, then the aspect ratio grows the
      /// short side and rounds up; a portrait capture takes the ratio's terms the other way round).
      nonisolated enum Canvas: CaseIterable, Sendable {
          case padding0, padding160, radius0, radius40, shadowOff, square, fourThree, threeTwo, sixteenTen
          case sixteenNine, portrait, auto

          var content: (width: Int, height: Int) { self == .portrait ? (300, 400) : (400, 300) }

          var style: BackgroundStyle {
              let ocean = BackgroundFill.gradient(1)
              return switch self {
              case .padding0: BackgroundStyle(fill: ocean, padding: 0)
              case .padding160: BackgroundStyle(fill: ocean, padding: 160)
              case .radius0: BackgroundStyle(fill: ocean, padding: 48, cornerRadius: 0)
              case .radius40: BackgroundStyle(fill: ocean, padding: 48, cornerRadius: 40)
              case .shadowOff: BackgroundStyle(fill: ocean, padding: 48, shadow: false)
              case .square: BackgroundStyle(fill: ocean, padding: 48, aspect: .square)
              case .fourThree: BackgroundStyle(fill: ocean, padding: 48, aspect: .fourThree)
              case .threeTwo: BackgroundStyle(fill: ocean, padding: 48, aspect: .threeTwo)
              case .sixteenTen: BackgroundStyle(fill: ocean, padding: 48, aspect: .sixteenTen)
              case .sixteenNine, .portrait: BackgroundStyle(fill: ocean, padding: 48, aspect: .sixteenNine)
              case .auto: BackgroundStyle(fill: ocean, padding: 48, aspect: .auto)
              }
          }

          var canvas: (width: Int, height: Int) {
              switch self {
              case .padding0: (400, 300)
              case .padding160: (1040, 940)
              case .radius0, .radius40, .shadowOff, .auto: (592, 492)
              case .square: (592, 592)
              case .fourThree: (656, 492)
              case .threeTwo: (738, 492)
              case .sixteenTen: (788, 492)
              case .sixteenNine: (875, 492)
              case .portrait: (492, 875)
              }
          }
      }

      /// T15, phase-7c:184 (:238) and phase-7c:185 (:239). A window capture with padding 0 and 160, corner radius 0 and 40,
      /// shadow off and each aspect ratio is saved at the size the arithmetic gives, in the file and in the record, at
      /// the capture's scale; a portrait window with 16:9 gets a portrait canvas. Stays: how radius and shadow look
      /// (`BackgroundCompositorTests`) and the arithmetic itself (`BackgroundLayoutTests`,
      /// `.portraitContentInvertsTheRatio`).
      @Test(arguments: Canvas.allCases)
      func aWindowCanvasFollowsTheStyle(canvas: Canvas) async throws {
          defer { world.removeAll() }
          try world.storeSaveFolder()
          world.settings.windowBackground = true
          world.settings.backgroundStyle = canvas.style
          let coordinator = world.makeCoordinator()
          let content = canvas.content
          let record = try #require(await save(coordinator,
                                               try CaptureSamples.image(width: content.width, height: content.height),
                                               CaptureSamples.window, CaptureIntent(action: .save)))
          try await eventually { thumbnailLanded(coordinator, record.id) }

          let expected = CGSize(width: canvas.canvas.width, height: canvas.canvas.height)
          let layout = try #require(BackgroundLayout.make(contentSize: CGSize(width: content.width, height: content.height),
                                                          style: canvas.style, scale: 2))
          #expect(layout.canvasSize == expected)
          let file = try pngAt(record.fileURL)
          #expect(file.image.width == canvas.canvas.width)
          #expect(file.image.height == canvas.canvas.height)
          #expect(file.scale == 2)
          #expect(record.pixelWidth == canvas.canvas.width)
          #expect(record.pixelHeight == canvas.canvas.height)
          #expect(coordinator.history.record(id: record.id)?.pixelWidth == canvas.canvas.width)
          #expect(coordinator.history.record(id: record.id)?.pixelHeight == canvas.canvas.height)
          #expect(world.logLines.isEmpty)
      }

      /// T16, phase-7c:186 (:240) and phase-7c:197 (:254). The setting is read at each save: on, a window capture is
      /// composed (592 by 492); turned off, the next window capture and an area capture are plain (400 by 300, the
      /// capture's own first pixel) at once, with no relaunch between. Stays: the editor's own background switch and an
      /// edit's Save (`EditorBackgroundExportTests.noBackgroundExportsTheCaptureAsBefore`).
      @Test func withTheBackgroundOffEveryCaptureIsPlainAtOnce() async throws {
          defer { world.removeAll() }
          try world.storeSaveFolder()
          world.settings.fileNameTemplate = "Shot"
          turnOceanBackgroundOn()
          let coordinator = world.makeCoordinator()
          let intent = CaptureIntent(action: .save)
          let composed = try #require(await save(coordinator, try CaptureSamples.image(width: 400, height: 300),
                                                 CaptureSamples.window, intent))
          world.settings.windowBackground = false
          let plainWindow = try #require(await save(coordinator, try CaptureSamples.image(width: 400, height: 300),
                                                    CaptureSamples.window, intent))
          let plainArea = try #require(await save(coordinator, try CaptureSamples.image(width: 400, height: 300),
                                                  CaptureSamples.area(), intent))
          try await eventually {
              thumbnailLanded(coordinator, composed.id) && thumbnailLanded(coordinator, plainWindow.id)
                  && thumbnailLanded(coordinator, plainArea.id)
          }

          #expect(composed.fileURL?.lastPathComponent == "Shot.png")
          #expect(plainWindow.fileURL?.lastPathComponent == "Shot 2.png")
          #expect(plainArea.fileURL?.lastPathComponent == "Shot 3.png")
          let first = try pngAt(composed.fileURL)
          #expect(first.image.width == 592)
          #expect(first.image.height == 492)
          for plain in [plainWindow, plainArea] {
              let file = try pngAt(plain.fileURL)
              #expect(file.image.width == 400)
              #expect(file.image.height == 300)
              #expect(EditorPixels.pixel(file.image, x: 1, y: 1) == (try EditorPixels.worldRed()))
              #expect(plain.pixelWidth == 400)
              #expect(plain.pixelHeight == 300)
          }
          #expect(composed.pixelWidth == 592)
          #expect(composed.pixelHeight == 492)
          #expect(world.logLines.isEmpty)
      }

      /// T17, phase-7c:187 (:241), in part (it extends the CT-2 mark). A window capture with the background on, opened in the
      /// editor with Annotate: the editor's image is the composed one (592 by 492, the capture in the middle and the
      /// fill at the corner) and its document carries no background, which is what the popover's switch reads. Stays:
      /// the popover's switch as its binding shows it (`BGPOP`) and drawn in the window (`EDPLACE`); the editor half is
      /// `CoordinatorEditorTests.aComposedWindowCaptureOpensFlatWithNoBackground`.
      @Test func aComposedWindowCaptureOpensInTheEditorComposed() async throws {
          defer { world.removeAll() }
          try world.storeSaveFolder()
          world.settings.fileNameTemplate = "Shot"
          turnOceanBackgroundOn()
          let coordinator = world.makeCoordinator()
          let record = try #require(await save(coordinator, try CaptureSamples.image(width: 400, height: 300),
                                               CaptureSamples.window, CaptureIntent(action: .save, then: .annotate)))
          let editor = try await openedEditor(record.id)

          let model = editor.model
          #expect(model.base.width == 592)
          #expect(model.base.height == 492)
          #expect(EditorPixels.pixel(model.base, x: 296, y: 246) == (try EditorPixels.worldRed()))
          #expect(EditorPixels.pixel(model.base, x: 1, y: 1) != (try EditorPixels.worldRed()))
          #expect(model.document == AnnotationDocument())
          #expect(model.document.background == nil)
          #expect(!model.hasUnsavedChanges)
          try await eventually { thumbnailLanded(coordinator, record.id) }
      }

      /// T18, phase-7c:188 (:244). `action=copy` on a window with the background on puts the composed image on the clipboard
      /// and nothing else: no file, no card, no history row and no destination asked for, and `Image copied` names the
      /// composed size. `action=upload` then sends the composed image: the upload, the file and the record are all
      /// 592 by 492. Stays: the URL parsing (already covered) and the window click, which is the user's selection.
      @Test func copyAndUploadOfAWindowCarryTheComposedImage() async throws {
          defer { world.removeAll() }
          turnOceanBackgroundOn()
          let coordinator = world.makeCoordinator()

          let copied = await save(coordinator, try CaptureSamples.image(width: 400, height: 300), CaptureSamples.window,
                                  CaptureIntent(action: .save, copyOnly: true))
          #expect(copied == nil)
          let png = try EditorPixels.decoded(try #require(world.clipboard.pngs.first))
          #expect(png.image.width == 592)
          #expect(png.image.height == 492)
          #expect(world.clipboard.copies == [.pngAndTIFF])
          #expect(world.notifier.calls == [.notice(title: "Image copied", body: "592 × 492 px", subtitle: nil)])
          #expect(coordinator.history.records.isEmpty)
          #expect(CaptureSamples.fileNames(in: coordinator.pendingFiles.directory) == [])
          #expect(world.cards.calls.isEmpty)
          #expect(world.factory.askedConfigs.isEmpty)

          let folder = try world.storeSaveFolder()
          #expect(CaptureSamples.fileNames(in: folder) == [])
          let record = try #require(await save(coordinator, try CaptureSamples.image(width: 400, height: 300),
                                               CaptureSamples.window, CaptureIntent(urlAction: .upload, setting: .save)))
          try await eventually { isUploaded(coordinator, record.id) }
          let link = try #require(coordinator.history.record(id: record.id)?.uploadedURL)
          let uploads = destination.state.withLock { $0.uploads }
          #expect(uploads.count == 1)
          let sent = try EditorPixels.decoded(try #require(uploads.first?.data))
          #expect(sent.image.width == 592)
          #expect(sent.image.height == 492)
          #expect(sent.scale == 2)
          let file = try pngAt(record.fileURL)
          #expect(file.image.width == 592)
          #expect(file.image.height == 492)
          #expect(record.pixelWidth == 592)
          #expect(record.pixelHeight == 492)
          #expect(world.clipboard.copies.last == .url(link))
          try await eventually { thumbnailLanded(coordinator, record.id) }
      }

      /// T19, phase-7c:189 (:245), in part. A window too large for a background (16,385 px, one over the limit) is saved
      /// as it is: one `Background: the window is too large for a background, keeping the window capture` line, the
      /// `Screenshot saved` notice and no error, the file and the record at the capture's own size. Stays: `no bitmap
      /// could be made`, which no input forces while the layout fits, so it is checked by code reading as the line says.
      @Test func aWindowTooLargeForABackgroundIsSavedPlainWithOneLine() async throws {
          defer { world.removeAll() }
          try world.storeSaveFolder()
          world.settings.fileNameTemplate = "Shot"
          turnOceanBackgroundOn()
          let coordinator = world.makeCoordinator()
          let record = try #require(await save(coordinator, try CaptureSamples.image(width: 16_385, height: 2, scale: 1),
                                               CaptureSamples.window, CaptureIntent(action: .save)))
          try await eventually { thumbnailLanded(coordinator, record.id) }

          #expect(world.logLines == ["Background: the window is too large for a background, keeping the window capture"])
          #expect(world.notifier.calls == [.saved(title: "Screenshot saved", file: "Shot.png")])
          let file = try pngAt(record.fileURL)
          #expect(file.image.width == 16_385)
          #expect(file.image.height == 2)
          #expect(record.pixelWidth == 16_385)
          #expect(record.pixelHeight == 2)
          #expect(world.clipboard.copies == [.pngAndTIFF])
      }

      /// T20, phase-7c:190 (:246). Two window captures started together, the second before the first has finished: both get
      /// the background, each in its own file (`Shot.png` and `Shot 2.png`, in either order), and the files do not mix:
      /// the red 400 by 300 capture is 592 by 492 with red in the middle, the white 200 by 100 capture is 392 by 292
      /// with white in the middle. Stays: the second capture's card not yet showing (`SCREENS`).
      @Test func twoWindowCapturesAtOnceAreEachComposedInTheirOwnFile() async throws {
          defer { world.removeAll() }
          try world.storeSaveFolder()
          world.settings.fileNameTemplate = "Shot"
          turnOceanBackgroundOn()
          let coordinator = world.makeCoordinator()
          let red = try CaptureSamples.image(width: 400, height: 300)
          let white = try CaptureSamples.image(width: 200, height: 100, white: true)
          let intent = CaptureIntent(action: .save)
          let redSave = Task { await save(coordinator, red, CaptureSamples.window, intent) }
          let whiteSave = Task { await save(coordinator, white, CaptureSamples.window, intent) }
          defer {
              redSave.cancel()
              whiteSave.cancel()
          }
          let redWatch = TaskWatch(redSave)
          let whiteWatch = TaskWatch(whiteSave)
          try await eventually { redWatch.hasReturned && whiteWatch.hasReturned }
          let redRecord = try #require(await redSave.value)
          let whiteRecord = try #require(await whiteSave.value)
          try await eventually { thumbnailLanded(coordinator, redRecord.id) && thumbnailLanded(coordinator, whiteRecord.id) }

          #expect(redRecord.id != whiteRecord.id)
          let names = [redRecord, whiteRecord].map { $0.fileURL?.lastPathComponent }
          #expect(Set(names) == ["Shot.png", "Shot 2.png"])
          let redFile = try pngAt(redRecord.fileURL)
          #expect(redFile.image.width == 592)
          #expect(redFile.image.height == 492)
          #expect(EditorPixels.pixel(redFile.image, x: 296, y: 246) == (try EditorPixels.worldRed()))
          let whiteFile = try pngAt(whiteRecord.fileURL)
          #expect(whiteFile.image.width == 392)
          #expect(whiteFile.image.height == 292)
          #expect(EditorPixels.pixel(whiteFile.image, x: 196, y: 146) == [255, 255, 255, 255])
          #expect(redRecord.pixelWidth == 592)
          #expect(redRecord.pixelHeight == 492)
          #expect(whiteRecord.pixelWidth == 392)
          #expect(whiteRecord.pixelHeight == 292)
          #expect(world.notifier.calls.count == 2)
          #expect(world.notifier.calls.allSatisfy { if case .saved = $0 { true } else { false } })
          #expect(world.logLines.isEmpty)
      }

      /// T21, phase-5:179 (:191), its Wi-Fi-off clause (T10 has the rest); phase-3:48 (:89), its Retry leg (T8 has the
      /// rest); small-tweaks:16 (:22), the size kept until the retry (T10 has the first half). An upload-only capture
      /// whose upload fails keeps `pending/<id>.png` at the PNG's size, with nothing in the save folder, nothing on the
      /// clipboard and one `Upload failed` notice; Retry Failed Uploads sends those same bytes, the pending file is
      /// removed, the row takes the uploaded size and the link is copied. Stays: Wi-Fi off for real (a failing
      /// destination stands in); the Retry half of phase-3:48 is also
      /// `CoordinatorUploadTests.retryFailedUploadsSaysOnceWithoutCredentialsAndEnqueuesWithThem`.
      @Test func anUploadOnlyCaptureThatFailsKeepsItsPendingFileUntilARetrySucceeds() async throws {
          defer { world.removeAll() }
          let folder = try world.storeSaveFolder()
          let message = "Server returned HTTP 403: AccessDenied: Access Denied"
          destination.state.withLock {
              $0.failuresRemaining = 1
              $0.failure = .httpStatus(403, body: "AccessDenied: Access Denied")
          }
          let coordinator = world.makeCoordinator()
          let record = try #require(await save(coordinator, try CaptureSamples.image(width: 40, height: 30),
                                               CaptureSamples.area(), CaptureIntent(action: .uploadOnly)))
          try await eventually { coordinator.history.record(id: record.id)?.isFailed == true }

          let failed = try #require(coordinator.history.record(id: record.id))
          #expect(failed.uploadState == .failed(message: message))
          let pending = try #require(failed.fileURL)
          #expect(failed.fileIsTemporary)
          #expect(exists(pending))
          let kept = try Data(contentsOf: pending)
          #expect(failed.byteCount == kept.count)
          #expect(CaptureSamples.fileNames(in: coordinator.pendingFiles.directory) == [pending.lastPathComponent])
          #expect(CaptureSamples.fileNames(in: folder) == [])
          #expect(world.notifier.calls == [.error(title: "Upload failed", message: message)])
          #expect(world.clipboard.copies.isEmpty)
          #expect(coordinator.history.failedRecords.map(\.id) == [record.id])
          #expect(destination.state.withLock { $0.uploadAttempts } == 1)

          coordinator.retryFailedUploads()
          try await eventually { isUploaded(coordinator, record.id) }

          let uploaded = try #require(coordinator.history.record(id: record.id))
          let link = try #require(uploaded.uploadedURL)
          let uploads = destination.state.withLock { $0.uploads }
          #expect(destination.state.withLock { $0.uploadAttempts } == 2)
          #expect(uploads.count == 1)
          #expect(uploads.first?.data == kept)
          #expect(CaptureSamples.fileNames(in: coordinator.pendingFiles.directory) == [])
          #expect(uploaded.fileURL == nil)
          #expect(uploaded.byteCount == uploads.first?.data.count)
          #expect(world.clipboard.copies == [.url(link)])
          #expect(world.notifier.calls.last == .uploaded(url: link, copied: true))
          try await eventually { thumbnailLanded(coordinator, record.id) }
      }
  ```

- [ ] Run the suite alone:
  ```bash
  xcodegen generate && xcodebuild test -project TidyShot.xcodeproj -scheme TidyShot -destination 'platform=macOS' -derivedDataPath .build -only-testing:TidyShotTests/CoordinatorCaptureSaveTests 2>&1 | grep -E "Test run with|error:|TEST"
  ```
  Expected: `✔ Test run with 21 tests in 1 suite passed after …` and `** TEST SUCCEEDED **`. The `error:` lines that print are
  the known noise only (`com.apple.linkd.autoShortcut`, `MDB_MAP_FULL`, the `iOSSimulator` line). A compile error here is
  an argument-label or isolation mistake in the block: fix the block, not the production code, and report it. A test that
  fails on an assertion is reported with its expected and actual values, not loosened.

- [ ] Run the suite 5 times over, for ordering and timing:
  ```bash
  xcodebuild test -project TidyShot.xcodeproj -scheme TidyShot -destination 'platform=macOS' -derivedDataPath .build -only-testing:TidyShotTests/CoordinatorCaptureSaveTests -test-iterations 5 -run-tests-until-failure 2>&1 | grep -E "Test run with|error:|TEST"
  ```
  Expected: `✔ Test run with 21 tests in 1 suite passed after …` and `** TEST SUCCEEDED **`, noise only.

- [ ] Run the full suite:
  ```bash
  xcodegen generate && xcodebuild test -project TidyShot.xcodeproj -scheme TidyShot -destination 'platform=macOS' -derivedDataPath .build 2>&1 | grep -E "Test run with|error:|TEST"
  ```
  Expected: `✔ Test run with 2373 tests in 196 suites passed after …` and `** TEST SUCCEEDED **`, with the noise the Global
  Constraints list. A run that fails only on `UploadQueueTests.aSidecarUnwritableDuringThePartsFailsTheJobBeforeComplete`
  or on `RecordingTrimTests.aKeyframeIntervalFixtureHasASyncSampleEveryInterval(reorders:)` is run once more; any other
  failure is reported, not forced.

- [ ] Assert what changed:
  ```bash
  git diff --stat HEAD -- TidyShot/
  git status --short
  ```
  Expected: the first prints nothing; the second lists ` M TidyShotTests/CoordinatorCaptureSaveTests.swift` and nothing else
  (`TidyShot.xcodeproj`, `.build/` and `.build-rel/` are git-ignored).

- [ ] Commit:
  ```bash
  git add TidyShotTests/CoordinatorCaptureSaveTests.swift
  git commit -m "test: the TARGET save tests T11 to T21, upload action, tall capture, annotate, window backgrounds and a failed upload-only retry"
  ```
  Expected: `1 file changed`, about 436 insertions. No attribution lines and no session URL in the message; do not push.
  The report says no hand check was run.

---

### Task 3: The capture source and the selector through `AppEnvironment`, the fakes, C1 to C7 and C8 [integration]

The `CAPSRC` seam (design 2.2): the ScreenCaptureKit objects become values that carry the object as a `live`
handle (`CaptureDisplay`, `CaptureWindow`, `ScreenContent`); `CaptureTarget`, `Selection` and `AllInOneChoice` carry
the values; `AppEnvironment.captureSource: any CaptureSource` and `AppEnvironment.selector: any CaptureSelecting`
replace the coordinator's own content read, capture, card lookup, pointer read, permission read and lazy
`SelectionController`. `CaptureEngine` and `SelectionController` conform; `live()` builds one `CaptureEngine()` for
both. The suite gets `FakeCaptureSource` (`world.source`) and `FakeSelector` (`world.selector`) (design 3.2, 3.3), the
new suite `CoordinatorCaptureSourceTests` with C1 to C7 (catalogue CAPSRC.4) and C8 as a step in an existing
`CoordinatorRecordingTests` test (CAPSRC.5). C9 is not built (design call 3). This task is separable: if Tim defers
`CAPSRC` (design call 1), it is dropped with its marks in Task 4.

This task runs after Task 1 and Task 2. Of the files Task 1 changed, only `TidyShot/Capture/CaptureTarget.swift` is
edited here, in lines Task 1 did not touch (design 2.3): Task 1 replaced the `areaRect` extension with
`CaptureTarget.origin` and `CaptureOrigin` and left `:1-9` and `CaptureError` as they were. `CaptureTarget.origin`
compiles unchanged over the values, which carry `displayID` and `frame` under the same names. Nothing here touches
`AppCoordinator+Save.swift`, `CaptureSamples.swift` or `CoordinatorCaptureSaveTests.swift`.

**Files:**
- Modify `TidyShot/Capture/CaptureTarget.swift`: the SC-typed `CaptureTarget` (:4-9 at 705bce0, unchanged by Task 1)
  becomes `CaptureDisplay`, `CaptureWindow` and an `Equatable` `CaptureTarget` over them; `CaptureError` (:66-74 at
  705bce0, below `CaptureOrigin` since Task 1) gains `case notListed` (design 2.2).
- Create `TidyShot/Capture/CaptureSource.swift`: `ScreenContent` and `protocol CaptureSource` (design 2.2, whole; the
  review's built file byte for byte).
- Modify `TidyShot/Capture/CaptureEngine.swift`: `capture` (:13-14) takes `[CaptureWindow]`, each case (:23-24,
  :27-28, :32-33) unwraps its `live` object; after `displayID(containing:)` (:94-100) the moved
  `display(under:in:)` and `extension CaptureEngine: CaptureSource`.
- Modify `TidyShot/Selection/Selection.swift`: `Selection`'s cases (:22-25) and `protocol CaptureSelecting` after it.
- Modify `TidyShot/Selection/AllInOneChoice.swift`: the five cases (:9-16).
- Modify `TidyShot/Capture/PreviousArea.swift`: the `Display` doc comment (:25).
- Modify `TidyShot/Selection/SelectionController.swift`: `cachedOverlayWindows` (:19), `select` (:36-40),
  `selectAllInOne` (:49-52), `finishAllInOne` (:187), `clippedToDisplay` (:227-231), the two `engine.capture`
  calls (:242, :283), `overlayWindows()` (:260, :268), `finishPick` (:338), and the conformance after the class's end
  (:368).
- Modify `TidyShot/App/AppEnvironment.swift`: `captureSource` and `selector` after `clipboard` (:24); `live()`'s doc
  comment (:57-62); `let engine = CaptureEngine()` after the overlay (:68); the two live values after `clipboard:`
  (:79).
- Modify `TidyShot/App/AppCoordinator.swift`: the lazy `selector` (:32) becomes two `let`s of the protocol types, set
  in `init` after `clopOptimiser = environment.clopOptimiser` (:275); `loadContent` (:519-524) reads the source.
- Modify `TidyShot/App/AppCoordinator+Capture.swift`: the pointer read (:9), the `select` calls (:102, :187, :206,
  :232), `runScrolling` (:117, :127-128), `areaResult` (:342), `selectedAreaResult` (:349), `frozenResult` (:359),
  `capture` (:377, :381), `cardWindows` (:391-395) and the removed `display(under:in:)` (:397-402).
- Modify `TidyShot/App/AppCoordinator+Recording.swift`: Record Screen's `select` (:215), Record Fullscreen's pointer
  read (:254), `connectedDisplay` (:596) and `recordingDisplay` (:604); bodies unchanged.
- Create `TidyShotTests/Support/CaptureSourceFakes.swift` (design 3.2, less the five members design section 12 names;
  see Plan decisions).
- Modify `TidyShotTests/Support/CoordinatorWorld.swift`: the type doc (:13-17), `source` and `selector` after
  `let clipboard = FakeClipboard()` (:43), the two environment arguments after `clipboard: clipboard,` (:133)
  (design 3.3).
- Modify `TidyShotTests/CoordinatorWorldTests.swift`: four checks after `#expect(world.saveAsChooser.asked.isEmpty)`
  (:35) (design 3.3).
- Modify `TidyShotTests/CoordinatorCaptureTests.swift`: the suite doc (:5-7), the comment at :34 and one check after
  `#expect(world.clipboard.copies.isEmpty)` (:46) (design 3.3).
- Create `TidyShotTests/CoordinatorCaptureSourceTests.swift` (catalogue CAPSRC.4, C1 to C7).
- Modify `TidyShotTests/CoordinatorRecordingTests.swift`:
  `aSecondRecordPressWhileTheMicrophonePromptIsUpAsksNothingAndAQuitStartsNothing` (:349-380) gets C8's step after
  :364, a log check after :368 and two at its end, and its doc comment (:349-352) names the line and what stays
  (catalogue CAPSRC.5).
- Not in this task: C9 (`SelectionViewArmingTests`), and every mark (Task 4).

**Interfaces:**
- Consumes (at 705bce0, with Task 1's `CaptureTarget.swift` and `AppCoordinator+Save.swift`):
  - Production, unchanged by this task: `final class CaptureEngine` with
    `func shareableContent() async throws -> SCShareableContent` (TidyShot/Capture/CaptureEngine.swift:7),
    `static func scale(forDisplayID id: CGDirectDisplayID) -> CGFloat` (:80),
    `static func displayID(containing cgRect: CGRect) -> CGDirectDisplayID` (:94);
    `static func windows(numbers wanted: Set<CGWindowID>, engine: CaptureEngine) async -> [SCWindow]` on
    `OverlayWindowLookup` (TidyShot/Selection/OverlayWindowLookup.swift:10);
    `init(engine: CaptureEngine, settings: AppSettings, cardWindowNumbers: @escaping () -> Set<CGWindowID> = { [] })`,
    `func frozenCapture(for displayID: CGDirectDisplayID) -> FrozenSnapshot?` (:251) and `func dismiss()` on
    `SelectionController` (TidyShot/Selection/SelectionController.swift:28);
    `var cgFrame: CGRect` and `var displayID: CGDirectDisplayID` on `CaptureTarget` (TidyShot/Capture/CaptureTarget.swift:26, :14);
    `struct CaptureResult { let image: CGImage; let scale: CGFloat; let target: CaptureTarget }` (:59-64);
    `struct CaptureOptions: Equatable` with the memberwise `init(showsCursor:windowShadow:)` (:43-47);
    `nonisolated struct FrozenSnapshot: Sendable { let displayID: CGDirectDisplayID; let image: CGImage; let scale: CGFloat }`
    (TidyShot/Capture/FreezeCrop.swift:5-9);
    `static func pixelSize(points: CGSize, scale: CGFloat) -> (width: Int, height: Int)` on `Geometry`
    (TidyShot/Capture/Geometry.swift:24);
    `nonisolated struct StoredRect: Codable, Equatable, Sendable` with `init(_ rect: CGRect)` and `var cgRect: CGRect`
    (TidyShot/Capture/PreviousArea.swift:6, :12, :19);
    `nonisolated struct ScreenRect: Equatable, Sendable { var rect: CGRect; var displayID: CGDirectDisplayID }`
    (TidyShot/URLScheme/URLCommandGeometry.swift:5-8);
    `init(action: AfterCaptureAction, copyOnly: Bool = false, then: Then = .none, sender: String? = nil)` on
    `CaptureIntent` (TidyShot/Capture/CaptureIntent.swift:22).
  - The coordinator's entry points (TidyShot/App/AppCoordinator+Capture.swift):
    `func captureFullscreen(intent: CaptureIntent = .standard) async` (:6),
    `func captureArea(intent: CaptureIntent = .standard) async` (:15),
    `func captureWindow(intent: CaptureIntent = .standard) async` (:19),
    `func captureAllInOne(intent: CaptureIntent = .standard, preselect: ScreenRect? = nil, fromURLCommand: Bool = false) async` (:29-30),
    `func captureScrolling(intent: CaptureIntent = .standard, preselect: ScreenRect? = nil) async` (:80),
    `func capturePreviousArea(intent: CaptureIntent = .standard) async` (:146),
    `func captureArea(at area: ScreenRect, intent: CaptureIntent) async` (:167),
    `func captureSelfTimer(intent: CaptureIntent = .standard) async` (:184),
    `func captureText() async` (:227); on `AppCoordinator` (TidyShot/App/AppCoordinator.swift):
    `let engine = CaptureEngine()` (:15, kept), `lazy var scrollCapture` (:33), `private(set) var isCapturing` (:79),
    `var askingPermission: PermissionPrompt?` (:109), `var capturesRefused: Bool` (:542),
    `var captureRefusal: CaptureRefusal?` (:561), `let history: HistoryStore` (:18);
    `func recordFullscreen() async` (TidyShot/App/AppCoordinator+Recording.swift:244),
    `func recordScreen() async` (:145), `func finishRecordingForQuit() async` (AppCoordinator.swift:497);
    `var isRunning: Bool` on `ScrollCaptureController` (TidyShot/Scrolling/ScrollCaptureController.swift:27).
  - The URL handler (TidyShot/URLScheme/URLCommandHandler.swift):
    `init(settings: AppSettings, target: any URLCommandTarget, screens: @escaping () -> Screens, post: @escaping (URLCommandNotice) -> Void)` (:74-75),
    `func handle(_ url: URL, sender: String?) async` (:83), `func ready() async` (:98),
    `struct Screens { var displays: [URLCommandGeometry.Display]; var pointerIndex: Int? }` (:54-59).
  - The harness: `CoordinatorWorld` (`let settings` :35, `let notifier` :41, `let cards` :42, `let clipboard` :43,
    `private(set) var shutterCount` :58, `var microphones` :64, `var logLines` :114, `var recordingLines` :116,
    `var environment: AppEnvironment` :118, `func makeCoordinator() -> AppCoordinator` :155, `func removeAll()` :165,
    `static func image(width: Int, height: Int) throws -> CGImage` :194, a red image);
    in TidyShotTests/Support/CoordinatorFakes.swift: `FakeNotifier.Call` with
    `case error(title: String, message: String, subtitle: String? = nil)` and
    `case notice(title: String, body: String, subtitle: String? = nil)` (:9-18), `private(set) var calls` (:20);
    `FakeCards.calls` (:86) and `var windowNumbers: Set<CGWindowID> { [] }` (:91);
    `FakeClipboard.copies` (:167) and `private(set) var pngs: [Data]` (:169);
    `final class HeldMicrophoneDevices` with `requestCount` (:366), `isAsking` (:370), `func answer(_ granted: Bool)` (:381);
    `final class SingleWaiter<Value: Sendable>` with `init(cancelled: Value, secondEntry: String)`, `var isWaiting: Bool`,
    `func wait() async -> Value` and `func resume(_ value: Value)` (:409-449);
    `final class TaskWatch` with `init<Success: Sendable>(_ task: Task<Success, Never>)` and `private(set) var hasReturned` (:454-463);
    `func eventually(_ condition: () async -> Bool) async throws` (TidyShotTests/UploadQueueTests.swift:42, 2 s);
    `static func decoded(_ png: Data) throws -> (image: CGImage, scale: CGFloat)` on `EditorPixels`
    (TidyShotTests/Support/EditorPixels.swift:22).
- Produces, production:
  ```swift
  // TidyShot/Capture/CaptureTarget.swift
  struct CaptureDisplay: Equatable {
      let displayID: CGDirectDisplayID; let frame: CGRect; let live: SCDisplay?
      init(displayID: CGDirectDisplayID, frame: CGRect)   // live nil
      init(_ display: SCDisplay)
  }
  struct CaptureWindow: Equatable {
      let windowID: CGWindowID; let frame: CGRect; let live: SCWindow?
      init(windowID: CGWindowID, frame: CGRect)           // live nil
      init(_ window: SCWindow)
  }
  enum CaptureTarget: Equatable { case display(CaptureDisplay); case area(rect: CGRect, display: CaptureDisplay); case window(CaptureWindow) }
  enum CaptureError: LocalizedError { case noImage; case notListed }
  // TidyShot/Capture/CaptureSource.swift
  struct ScreenContent {
      let displays: [CaptureDisplay]; let windows: [CaptureWindow]; let live: SCShareableContent?
      init(displays: [CaptureDisplay], windows: [CaptureWindow])   // live nil
      init(_ content: SCShareableContent)
  }
  protocol CaptureSource: AnyObject {
      func screenContent() async throws -> ScreenContent
      func capture(_ target: CaptureTarget, options: CaptureOptions, excludingWindows: [CaptureWindow]) async throws -> CaptureResult
      func windows(numbers: Set<CGWindowID>) async -> [CaptureWindow]
      func displayUnderPointer(in displays: [CaptureDisplay]) -> CaptureDisplay?
      var isScreenRecordingGranted: Bool { get }
  }
  // TidyShot/Selection/Selection.swift
  enum Selection { case area(rect: CGRect, display: CaptureDisplay); case window(CaptureWindow) }
  protocol CaptureSelecting: AnyObject {
      func select(mode: SelectionMode, content: ScreenContent, freeze: CaptureOptions?, preselect: CGRect?) async -> Selection?
      func selectAllInOne(content: ScreenContent, freeze: CaptureOptions?, preselect: CGRect?, armed: Bool) async -> AllInOneChoice?
      func frozenCapture(for displayID: CGDirectDisplayID) -> FrozenSnapshot?
      func overlayWindows() async -> [CaptureWindow]
      func dismiss()
  }
  // TidyShot/Selection/AllInOneChoice.swift: the five cases take CaptureDisplay and CaptureWindow
  // CaptureEngine
  func capture(_ target: CaptureTarget, options: CaptureOptions, excludingWindows: [CaptureWindow] = []) async throws -> CaptureResult
  static func display(under appKitPoint: CGPoint, in displays: [CaptureDisplay]) -> CaptureDisplay?   // moved from AppCoordinator
  extension CaptureEngine: CaptureSource
  extension SelectionController: CaptureSelecting {}
  // AppEnvironment, after clipboard
  var captureSource: any CaptureSource
  var selector: any CaptureSelecting
  // AppCoordinator
  let selector: any CaptureSelecting          // was the lazy SelectionController
  let captureSource: any CaptureSource
  func loadContent(failureTitle: String = "Capture failed") async -> ScreenContent?
  func capture(_ target: CaptureTarget, excludingWindows: [CaptureWindow] = [], duringSelection: Bool = false) async -> CaptureResult?
  ```
  `AppCoordinator.display(under:in:)` is removed (it moves to `CaptureEngine`).
- Produces, `CaptureSourceFakes.swift` (main-actor under the test target's default isolation):
  `nonisolated struct FakeCaptureError: LocalizedError, Sendable` (`"The fake source failed."`);
  `final class FakeCaptureSource: CaptureSource` with `struct Capture: Equatable { let target: CaptureTarget; let options: CaptureOptions; let excludedWindowIDs: [CGWindowID] }`,
  `static let display` (id 1, frame (0, 0, 1440, 900)), `var content: ScreenContent` (that display, no windows),
  `var contentFailures: [any Error]`, `var captureFailure: (any Error)?`, `private(set) var contentReads: Int`,
  `private(set) var captures: [Capture]`, `private(set) var windowLookups: [Set<CGWindowID>]`,
  `let isScreenRecordingGranted = true`, and the protocol's five members (a capture answers a red image of the
  target's `cgFrame` size at scale 1; the display under the pointer is the first);
  `final class FakeSelector: CaptureSelecting` with `struct Select: Equatable { let mode: SelectionMode; let freeze: CaptureOptions?; let preselect: CGRect? }`,
  `struct AllInOne: Equatable { let freeze: CaptureOptions?; let preselect: CGRect?; let armed: Bool }`,
  `private(set) var selects: [Select]`, `allInOnes: [AllInOne]`, `frozenAsked: [CGDirectDisplayID]`,
  `overlayLookups: Int`, `dismissCount: Int`, `var selections: [Selection?]`, `var choices: [AllInOneChoice?]`,
  `var holds: Bool`, `var isWaiting: Bool`, `func answer(_ selection: Selection?)`, and the protocol's five members.
- Produces, the world: `CoordinatorWorld.source: FakeCaptureSource` and `CoordinatorWorld.selector: FakeSelector`
  (`let`s), the environment's `captureSource: source` and `selector: selector`.

**Tests** (catalogue section 4, `docs/superpowers/notes/2026-11-01-capture-seams/tests-capture.md`):
1. `capturePreviousAreaWithNoUsableStoredAreaIsRefusedAndCapturesNothing(stored:)`: CAPSRC.4 C1, tests-capture.md:857; S; two arguments.
2. `allInOneOpensOnThePreviousAreaArmedOrAURLRectDisarmedAndEscapeStoresNothing`: CAPSRC.4 C2, :884; S.
3. `aHeldSelectionOpensOneWindowAndDropsEveryOtherURLCaptureCommandWithoutReadingOrPosting`: CAPSRC.4 C3, :912; M (held).
4. `capturePreviousAreaAfterCaptureTextCapturesTheEarlierImageArea`: CAPSRC.4 C4, :941; M (the real text recognizer).
5. `aFailedContentReadIsLoggedAndPostedAndAsksNothingMore`: CAPSRC.4 C5, :972; S (the harness, no line).
6. `aScrollingAreaUnder100PointsIsRefusedAndTheNextShortcutWorks`: CAPSRC.4 C6, :984; S.
7. `windowAndFullscreenCapturesLeaveThePreviousAreaAndAScrollingDragStoresIt`: CAPSRC.4 C7, :1006; M.
- C8, a step in `CoordinatorRecordingTests.aSecondRecordPressWhileTheMicrophonePromptIsUpAsksNothingAndAQuitStartsNothing`:
  CAPSRC.5 C8, :1054; S; no new function.
- 7 tests (S 4, M 3), one parameterized (C1), each counted once. One new suite file.
- Focused runs: `-only-testing:TidyShotTests/CoordinatorCaptureSourceTests` prints
  `Test run with 7 tests in 1 suite passed`; the new suite with the three existing suites this task edits prints
  `Test run with 25 tests in 4 suites passed` (`CoordinatorCaptureSourceTests` 7, `CoordinatorWorldTests` 1,
  `CoordinatorCaptureTests` 1, `CoordinatorRecordingTests` 16).
- Full suite: `Test run with 2380 tests in 197 suites passed` (2373 in 196 after Task 2, plus 7 tests and one suite).
- Also: `git diff --stat HEAD -- TidyShot/` lists the ten modified production files and ends
  `10 files changed, 126 insertions(+), 64 deletions(-)`, and `TidyShot/Capture/CaptureSource.swift` is new (21
  lines): `CAPSRC` alone is +147 −64 in eleven files. The Release build prints `** BUILD SUCCEEDED **` and no `error:`
  or `warning:` line beyond the tool lines the Global Constraints name.

**Commit:** `refactor: the capture source and the selection overlay through AppEnvironment (CAPSRC), the fakes, seven capture source tests and the microphone prompt's capture step`

**Tried before writing:** this task's text was applied as written, by a script that parsed it and asserted each
"Replace" anchor once in its file and each new file absent, to a copy of the tree at 705bce0 with Task 1's
production change (`CaptureTarget.origin`, `CaptureOrigin`, the `+Save` diff of design 2.1) applied first. There
`** TEST BUILD SUCCEEDED **` came with no Swift warning; the four suites ran `Test run with 25 tests in 4 suites
passed`, then passed 10 iterations with `-test-iterations 10 -run-tests-until-failure`; the new suite alone ran
`Test run with 7 tests in 1 suite passed`; the full suite (without Tasks 1 and 2's tests) ran `Test run with 2359
tests in 196 suites passed after 59.460 seconds` with only the known noise; the Release build printed
`** BUILD SUCCEEDED **` with only the two tool lines. The eleven production files are byte-identical to the design
review's built files except `AppEnvironment.swift`'s `live()` doc comment, which the review did not apply (design
section 12) and this task does. The commit read `17 files changed, 599 insertions(+), 75 deletions(-)`.

**Steps:**

- [ ] Check the starting point. From the repository root:
  ```bash
  git branch --show-current
  git status --short -- TidyShot TidyShotTests
  grep -c "var origin: CaptureOrigin" TidyShot/Capture/CaptureTarget.swift
  ls TidyShot/Capture/CaptureSource.swift TidyShotTests/Support/CaptureSourceFakes.swift TidyShotTests/CoordinatorCaptureSourceTests.swift
  ```
  Expected: `capture-seams`, then nothing (Task 2 is committed), then `1` (Task 1's `origin` is in), then three
  `No such file or directory` lines.

#### The value types and the source (design 2.2)

- [ ] In `TidyShot/Capture/CaptureTarget.swift`, the three SC-typed cases become values that keep the object as
  `live` (:4-9; Task 1 left these lines as they were). Replace:
  ```swift
  /// What to capture. Rects are in CoreGraphics global points (top-left origin).
  enum CaptureTarget {
      case display(SCDisplay)
      case area(rect: CGRect, display: SCDisplay)
      case window(SCWindow)
  }
  ```
  with:
  ```swift
  /// A display a capture can use: its id and frame, and the SC display it was read from (`live`, nil for one a test built).
  struct CaptureDisplay: Equatable {
      let displayID: CGDirectDisplayID
      let frame: CGRect
      let live: SCDisplay?
      init(displayID: CGDirectDisplayID, frame: CGRect) { self.displayID = displayID; self.frame = frame; live = nil }
      init(_ display: SCDisplay) { displayID = display.displayID; frame = display.frame; live = display }
  }
  /// A window a capture can use: its window number and frame, and the ScreenCaptureKit window (`live`).
  struct CaptureWindow: Equatable {
      let windowID: CGWindowID
      let frame: CGRect
      let live: SCWindow?
      init(windowID: CGWindowID, frame: CGRect) { self.windowID = windowID; self.frame = frame; live = nil }
      init(_ window: SCWindow) { windowID = window.windowID; frame = window.frame; live = window }
  }
  /// What to capture. Rects are in CoreGraphics global points (top-left origin).
  enum CaptureTarget: Equatable {
      case display(CaptureDisplay)
      case area(rect: CGRect, display: CaptureDisplay)
      case window(CaptureWindow)
  }
  ```
  `CaptureTarget` gains `Equatable`, synthesized over the values (`live` compares with `NSObject`'s `==`). The
  `displayID` and `cgFrame` extensions and Task 1's `origin` read `displayID`, `frame` and `windowID`, which the
  values carry, and compile unchanged.

- [ ] In the same file, `CaptureError` (at the end of the file, below Task 1's `CaptureOrigin`) gains the case a
  test-built display or window throws if it ever reached the engine. Replace:
  ```swift
      case noImage

      var errorDescription: String? {
          switch self {
          case .noImage: "ScreenCaptureKit returned no image."
  ```
  with:
  ```swift
      case noImage
      case notListed

      var errorDescription: String? {
          switch self {
          case .noImage: "ScreenCaptureKit returned no image."
          case .notListed: "The display or window is not one ScreenCaptureKit listed."
  ```
  Unreachable in the app: every value the app builds comes from a content read and carries its `live` object.

- [ ] Create `TidyShot/Capture/CaptureSource.swift` with exactly this content (design 2.2; the review's built file):
  ```swift
  import CoreGraphics
  import ScreenCaptureKit
  /// The displays and windows on screen as values, in ScreenCaptureKit's order; `live` is the content
  /// they were read from (the overlay's window picker uses it), nil for content a test built.
  struct ScreenContent {
      let displays: [CaptureDisplay]
      let windows: [CaptureWindow]
      let live: SCShareableContent?
      init(displays: [CaptureDisplay], windows: [CaptureWindow]) { self.displays = displays; self.windows = windows; live = nil }
      init(_ content: SCShareableContent) {
          displays = content.displays.map(CaptureDisplay.init); windows = content.windows.map(CaptureWindow.init); live = content
      }
  }
  /// What the capture flows read of the screen. `CaptureEngine` in the app; `FakeCaptureSource` in the suite.
  protocol CaptureSource: AnyObject {
      func screenContent() async throws -> ScreenContent
      func capture(_ target: CaptureTarget, options: CaptureOptions, excludingWindows: [CaptureWindow]) async throws -> CaptureResult
      func windows(numbers: Set<CGWindowID>) async -> [CaptureWindow]  // retried briefly; whatever was found
      func displayUnderPointer(in displays: [CaptureDisplay]) -> CaptureDisplay?
      var isScreenRecordingGranted: Bool { get }
  }
  ```

- [ ] In `TidyShot/Capture/CaptureEngine.swift`, `capture` takes the values and hands ScreenCaptureKit their `live`
  objects (:13-14). Replace:
  ```swift
      func capture(_ target: CaptureTarget, options: CaptureOptions, excludingWindows: [SCWindow] = []) async throws -> CaptureResult {
          let config = SCScreenshotConfiguration()
  ```
  with:
  ```swift
      func capture(_ target: CaptureTarget, options: CaptureOptions, excludingWindows: [CaptureWindow] = []) async throws -> CaptureResult {
          let excludingWindows = excludingWindows.compactMap(\.live)
          let config = SCScreenshotConfiguration()
  ```
  Then each case unwraps its object before the filter (:23-24, :27-28, :32-33). Replace:
  ```swift
          case .display(let display):
              filter = SCContentFilter(display: display, excludingWindows: excludingWindows)
  ```
  with:
  ```swift
          case .display(let display):
              guard let source = display.live else { throw CaptureError.notListed }
              filter = SCContentFilter(display: source, excludingWindows: excludingWindows)
  ```
  Replace:
  ```swift
          case .area(let rect, let display):
              filter = SCContentFilter(display: display, excludingWindows: excludingWindows)
  ```
  with:
  ```swift
          case .area(let rect, let display):
              guard let source = display.live else { throw CaptureError.notListed }
              filter = SCContentFilter(display: source, excludingWindows: excludingWindows)
  ```
  Replace:
  ```swift
          case .window(let window):
              filter = SCContentFilter(desktopIndependentWindow: window)
  ```
  with:
  ```swift
          case .window(let window):
              guard let source = window.live else { throw CaptureError.notListed }
              filter = SCContentFilter(desktopIndependentWindow: source)
  ```
  The frame, the display id and the window id are read from the value, copies of the object's taken when it was
  wrapped, so the same filter, scale, source rect and pixel size reach `SCScreenshotManager` as before.

- [ ] In the same file, after `displayID(containing:)` (:94-100), the pointer rule moves here from
  `AppCoordinator+Capture.swift:397-402` with the same body, and the engine conforms (design 2.2). Replace:
  ```swift
          return count > 0 ? id : CGMainDisplayID()
      }
  }
  ```
  with:
  ```swift
          return count > 0 ? id : CGMainDisplayID()
      }

      /// The display under an AppKit-global point, falling back to the first display.
      static func display(under appKitPoint: CGPoint, in displays: [CaptureDisplay]) -> CaptureDisplay? {
          let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
          let cgPoint = Geometry.cgPoint(fromAppKit: appKitPoint, primaryHeight: primaryHeight)
          return displays.first { $0.frame.contains(cgPoint) } ?? displays.first
      }
  }

  extension CaptureEngine: CaptureSource {
      func screenContent() async throws -> ScreenContent { ScreenContent(try await shareableContent()) }
      func windows(numbers: Set<CGWindowID>) async -> [CaptureWindow] {
          await OverlayWindowLookup.windows(numbers: numbers, engine: self).map(CaptureWindow.init)
      }
      func displayUnderPointer(in displays: [CaptureDisplay]) -> CaptureDisplay? {
          Self.display(under: NSEvent.mouseLocation, in: displays)
      }
      var isScreenRecordingGranted: Bool { ScreenCapturePermission.isGranted }
  }
  ```
  `NSEvent`, `NSScreen` and `ScreenCapturePermission` are reached through the file's `import AppKit` (:1) and the
  module; nothing else in the file changes.

- [ ] In `TidyShot/Selection/Selection.swift`, `Selection` carries the values and the protocol follows it (:21-25).
  Replace:
  ```swift
  enum Selection {
      case area(rect: CGRect, display: SCDisplay)
      case window(SCWindow)
  }
  ```
  with:
  ```swift
  enum Selection {
      case area(rect: CGRect, display: CaptureDisplay)
      case window(CaptureWindow)
  }

  /// The selection overlay as the capture flows use it. `SelectionController` in the app; `FakeSelector` in the suite.
  protocol CaptureSelecting: AnyObject {
      func select(mode: SelectionMode, content: ScreenContent, freeze: CaptureOptions?, preselect: CGRect?) async -> Selection?
      func selectAllInOne(content: ScreenContent, freeze: CaptureOptions?, preselect: CGRect?, armed: Bool) async -> AllInOneChoice?
      func frozenCapture(for displayID: CGDirectDisplayID) -> FrozenSnapshot?
      func overlayWindows() async -> [CaptureWindow]
      func dismiss()
  }
  ```

- [ ] In `TidyShot/Selection/AllInOneChoice.swift`, the five cases carry the values (:9-16). Replace:
  ```swift
      case area(rect: CGRect, display: SCDisplay)
      /// The window whose frame a click took, captured from its own surface.
      case window(SCWindow)
      /// The display the rect is on.
      case fullscreen(SCDisplay)
      case scrolling(rect: CGRect, display: SCDisplay)
      /// The Self-Timer countdown over the rect (Task 3).
      case timer(rect: CGRect, display: SCDisplay)
  ```
  with:
  ```swift
      case area(rect: CGRect, display: CaptureDisplay)
      /// The window whose frame a click took, captured from its own surface.
      case window(CaptureWindow)
      /// The display the rect is on.
      case fullscreen(CaptureDisplay)
      case scrolling(rect: CGRect, display: CaptureDisplay)
      /// The Self-Timer countdown over the rect (Task 3).
      case timer(rect: CGRect, display: CaptureDisplay)
  ```

- [ ] In `TidyShot/Capture/PreviousArea.swift`, the `Display` doc names what the coordinator builds it from (:25).
  Replace:
  ```swift
      /// A connected display as the decision needs it. The coordinator builds these from `SCDisplay`.
  ```
  with:
  ```swift
      /// A connected display as the decision needs it. The coordinator builds these from `CaptureDisplay`.
  ```

#### The selector (design 2.2)

- [ ] In `TidyShot/Selection/SelectionController.swift`, the cache holds values (:19). Replace:
  ```swift
      private var cachedOverlayWindows: [SCWindow]?
  ```
  with:
  ```swift
      private var cachedOverlayWindows: [CaptureWindow]?
  ```
  `select` (:36-40) and `selectAllInOne` (:49-52) take `ScreenContent` and present its `live` content, as before.
  Replace:
  ```swift
      func select(mode: SelectionMode, content: SCShareableContent, freeze: CaptureOptions? = nil,
                  preselect: CGRect? = nil) async -> Selection? {
          // All-in-One resolves through `selectAllInOne`.
          guard isIdle, mode != .allInOne, !NSScreen.screens.isEmpty else { return nil }
          await present(mode: mode, content: content, freeze: freeze, preselect: preselect, armed: true)
  ```
  with:
  ```swift
      func select(mode: SelectionMode, content: ScreenContent, freeze: CaptureOptions? = nil,
                  preselect: CGRect? = nil) async -> Selection? {
          // All-in-One resolves through `selectAllInOne`.
          guard isIdle, mode != .allInOne, !NSScreen.screens.isEmpty, let live = content.live else { return nil }
          await present(mode: mode, content: live, freeze: freeze, preselect: preselect, armed: true)
  ```
  Replace:
  ```swift
      func selectAllInOne(content: SCShareableContent, freeze: CaptureOptions? = nil,
                          preselect: CGRect? = nil, armed: Bool = true) async -> AllInOneChoice? {
          guard isIdle, !NSScreen.screens.isEmpty else { return nil }
          await present(mode: .allInOne, content: content, freeze: freeze, preselect: preselect, armed: armed)
  ```
  with:
  ```swift
      func selectAllInOne(content: ScreenContent, freeze: CaptureOptions? = nil,
                          preselect: CGRect? = nil, armed: Bool = true) async -> AllInOneChoice? {
          guard isIdle, !NSScreen.screens.isEmpty, let live = content.live else { return nil }
          await present(mode: .allInOne, content: live, freeze: freeze, preselect: preselect, armed: armed)
  ```
  The value is wrapped where the overlay hands a window or a display out: All-in-One's Window button (:187), the
  clipped area (:227-231), the two `engine.capture` calls of the freeze and loupe snapshots (:242, :283) and the
  picked window (:338). Replace:
  ```swift
              if let pickedWindow { resumeAllInOne(.window(pickedWindow)) }
  ```
  with:
  ```swift
              if let pickedWindow { resumeAllInOne(.window(CaptureWindow(pickedWindow))) }
  ```
  Replace:
  ```swift
      private func clippedToDisplay(_ cgRect: CGRect) -> (CGRect, SCDisplay)? {
          let centre = CGPoint(x: cgRect.midX, y: cgRect.midY)
          guard let display = displays.first(where: { $0.frame.contains(centre) }) ?? displays.first else { return nil }
          let clipped = cgRect.intersection(display.frame)
          return clipped.isEmpty ? nil : (clipped, display)
  ```
  with:
  ```swift
      private func clippedToDisplay(_ cgRect: CGRect) -> (CGRect, CaptureDisplay)? {
          let centre = CGPoint(x: cgRect.midX, y: cgRect.midY)
          guard let display = displays.first(where: { $0.frame.contains(centre) }) ?? displays.first else { return nil }
          let clipped = cgRect.intersection(display.frame)
          return clipped.isEmpty ? nil : (clipped, CaptureDisplay(display))
  ```
  Replace:
  ```swift
              guard let result = try? await engine.capture(.display(display), options: options,
  ```
  with:
  ```swift
              guard let result = try? await engine.capture(.display(CaptureDisplay(display)), options: options,
  ```
  Replace:
  ```swift
              guard let result = try? await engine.capture(.display(display),
                                                           options: CaptureOptions(showsCursor: false),
  ```
  with:
  ```swift
              guard let result = try? await engine.capture(.display(CaptureDisplay(display)),
                                                           options: CaptureOptions(showsCursor: false),
  ```
  Replace:
  ```swift
              finish(.window(window))
  ```
  with:
  ```swift
              finish(.window(CaptureWindow(window)))
  ```
  `overlayWindows()` answers values (:260, :268). Replace:
  ```swift
      func overlayWindows() async -> [SCWindow] {
  ```
  with:
  ```swift
      func overlayWindows() async -> [CaptureWindow] {
  ```
  Replace:
  ```swift
          let found = await OverlayWindowLookup.windows(numbers: wanted, engine: engine)
  ```
  with:
  ```swift
          let found = await OverlayWindowLookup.windows(numbers: wanted, engine: engine).map(CaptureWindow.init)
  ```
  The conformance goes after the class's closing brace (:368), the end of the file. Replace:
  ```swift
          continuation.resume(returning: selection)
      }
  }
  ```
  with:
  ```swift
          continuation.resume(returning: selection)
      }
  }

  extension SelectionController: CaptureSelecting {}
  ```
  `present`, `WindowPicker`, `hoveredWindow`, `pickedWindow` and `displays` stay SC-typed: the overlay keeps the
  objects it was presented with and wraps only what it hands out. Its defaults (`freeze: nil`, `preselect: nil`,
  `armed: true`) stay; the protocol has none, so every call through it names them.

#### The environment and the coordinator (design 2.2)

- [ ] In `TidyShot/App/AppEnvironment.swift`, add the two members after `clipboard` (:24). Replace:
  ```swift
      var clipboard: any Clipboard
      /// A destination for a configuration, signed with credentials read now.
  ```
  with:
  ```swift
      var clipboard: any Clipboard
      /// The displays and windows, a capture, the cards as windows, the display under the pointer, the grant.
      var captureSource: any CaptureSource
      /// The selection overlay: an area or a window, All-in-One's choice, the freeze snapshots.
      var selector: any CaptureSelecting
      /// A destination for a configuration, signed with credentials read now.
  ```

- [ ] In the same file, `live()`'s doc comment (:57-62) names ScreenCaptureKit and the overlay, and says the overlay
  is built here (design 2.2; the review did not apply this rewrite, so it is not in its built file). Replace:
  ```swift
      /// What the app runs on: the user's Application Support folder (the temporary folder when it
      /// cannot be had), the shared settings, the Keychain, the notification centre, the card stack,
      /// the general pasteboard, S3, Clop, the alerts, the shutter sound, the editor window, the card's
      /// Save As… panel, the wall clock, `NSLog` and `RecordingLog`. The collaborators are built in the
      /// order the coordinator's stored properties built them; Clop's optimiser, a value that reaches
      /// nothing until a request, is built here.
  ```
  with:
  ```swift
      /// What the app runs on: the user's Application Support folder (the temporary folder when it
      /// cannot be had), the shared settings, the Keychain, the notification centre, the card stack,
      /// the general pasteboard, ScreenCaptureKit and the selection overlay over it, S3, Clop, the
      /// alerts, the shutter sound, the editor window, the card's Save As… panel, the wall clock,
      /// `NSLog` and `RecordingLog`. The collaborators are built in the order the coordinator's stored
      /// properties built them; Clop's optimiser and the selection overlay, which store what they are
      /// given and reach nothing until asked, are built here.
  ```

- [ ] In the same file, build one engine after the card stack (:68) and hand it to the source and the overlay (after
  `clipboard:`, :79). Replace:
  ```swift
          let overlay = QuickAccessController(settings: settings)
          let historyFileURL = (try? HistoryStore.defaultFileURL())
  ```
  with:
  ```swift
          let overlay = QuickAccessController(settings: settings)
          let engine = CaptureEngine()
          let historyFileURL = (try? HistoryStore.defaultFileURL())
  ```
  Replace:
  ```swift
              clipboard: SystemClipboard(),
              makeDestination: { config, credentials in S3Destination(config: config, credentials: credentials) },
  ```
  with:
  ```swift
              clipboard: SystemClipboard(),
              captureSource: engine,
              // Every capture leaves out the cards on screen, as the coordinator's own selector did.
              selector: SelectionController(engine: engine, settings: settings,
                                            cardWindowNumbers: { [overlay] in overlay.windowNumbers }),
              makeDestination: { config, credentials in S3Destination(config: config, credentials: credentials) },
  ```
  `SelectionController.init` only stores what it is given (SelectionController.swift:28-32), so building it here
  instead of on the first capture shows nothing; the `[overlay]` capture reads the same `QuickAccessController` the
  coordinator's `overlay` is (AppCoordinator.swift:273), as `[weak self] in self?.overlay.windowNumbers` did. The
  engine is stateless (CaptureEngine.swift:5); the coordinator keeps its own `engine` (:15) for the scrolling
  session and the recording driver.

- [ ] In `TidyShot/App/AppCoordinator.swift`, the lazy selector becomes the environment's, beside the source (:32).
  Replace:
  ```swift
      @ObservationIgnored lazy var selector = SelectionController(engine: engine, settings: settings, cardWindowNumbers: { [weak self] in self?.overlay.windowNumbers ?? [] })
  ```
  with:
  ```swift
      /// The selection overlay, from the environment (CT-4).
      let selector: any CaptureSelecting
      /// What every capture and recording start reads of the screen, from the environment (CT-4).
      /// `engine` stays for the scrolling session and the recording driver.
      let captureSource: any CaptureSource
  ```
  Set both in `init` after Clop's optimiser (:275). Replace:
  ```swift
          clopOptimiser = environment.clopOptimiser
          let url = environment.historyFileURL
  ```
  with:
  ```swift
          clopOptimiser = environment.clopOptimiser
          selector = environment.selector
          captureSource = environment.captureSource
          let url = environment.historyFileURL
  ```
  `loadContent` reads the source (:519-524); its log line, its notice and the permission window are unchanged.
  Replace:
  ```swift
      func loadContent(failureTitle: String = "Capture failed") async -> SCShareableContent? {
          do {
              return try await engine.shareableContent()
          } catch {
              log("Shareable content failed: \(error.localizedDescription)")
              if ScreenCapturePermission.isGranted {
  ```
  with:
  ```swift
      func loadContent(failureTitle: String = "Capture failed") async -> ScreenContent? {
          do {
              return try await captureSource.screenContent()
          } catch {
              log("Shareable content failed: \(error.localizedDescription)")
              if captureSource.isScreenRecordingGranted {
  ```

- [ ] In `TidyShot/App/AppCoordinator+Capture.swift`, Capture Fullscreen asks the source for the display under the
  pointer (:9). Replace:
  ```swift
              guard let display = Self.display(under: NSEvent.mouseLocation, in: content.displays) else { return }
  ```
  with:
  ```swift
              guard let display = captureSource.displayUnderPointer(in: content.displays) else { return }
  ```
  The four `select` calls that leaned on the defaults name `freeze` and `preselect` (:102, :187, :206, :232; nil is
  what the defaults passed, SelectionController.swift:36-37). Replace:
  ```swift
              guard let selection = await selector.select(mode: .scrolling, content: content) else { return }
  ```
  with:
  ```swift
              guard let selection = await selector.select(mode: .scrolling, content: content, freeze: nil, preselect: nil) else { return }
  ```
  Replace:
  ```swift
              guard let selection = await selector.select(mode: .selfTimer, content: content) else { return }
  ```
  with:
  ```swift
              guard let selection = await selector.select(mode: .selfTimer, content: content, freeze: nil, preselect: nil) else { return }
  ```
  Replace:
  ```swift
              guard let selection = await selector.select(mode: mode, content: content, freeze: freeze) else { return }
  ```
  with:
  ```swift
              guard let selection = await selector.select(mode: mode, content: content, freeze: freeze, preselect: nil) else { return }
  ```
  Replace:
  ```swift
              guard let selection = await selector.select(mode: .area, content: content, freeze: freeze) else { return }
  ```
  with:
  ```swift
              guard let selection = await selector.select(mode: .area, content: content, freeze: freeze, preselect: nil) else { return }
  ```
  `runScrolling` takes the value and hands the session its `live` display (:117, :127-128); a display a test built
  stops here, after the 100 pt check and the store. Replace:
  ```swift
      private func runScrolling(rect: CGRect, display: SCDisplay, intent: CaptureIntent,
  ```
  with:
  ```swift
      private func runScrolling(rect: CGRect, display: CaptureDisplay, intent: CaptureIntent,
  ```
  Replace:
  ```swift
          selector.dismiss()
          let outcome = await scrollCapture.run(rect: rect, display: display, makesPanelKey: !preselected,
  ```
  with:
  ```swift
          selector.dismiss()
          // The session films the ScreenCaptureKit display; a display a test built has none and ends here.
          guard let liveDisplay = display.live else { return }
          let outcome = await scrollCapture.run(rect: rect, display: liveDisplay, makesPanelKey: !preselected,
  ```
  The three area helpers take the value (:342, :349, :359). Replace:
  ```swift
      private func areaResult(rect: CGRect, display: SCDisplay) async -> CaptureResult? {
  ```
  with:
  ```swift
      private func areaResult(rect: CGRect, display: CaptureDisplay) async -> CaptureResult? {
  ```
  Replace:
  ```swift
      private func selectedAreaResult(rect: CGRect, display: SCDisplay) async -> CaptureResult? {
  ```
  with:
  ```swift
      private func selectedAreaResult(rect: CGRect, display: CaptureDisplay) async -> CaptureResult? {
  ```
  Replace:
  ```swift
      private func frozenResult(for rect: CGRect, display: SCDisplay) -> CaptureResult? {
  ```
  with:
  ```swift
      private func frozenResult(for rect: CGRect, display: CaptureDisplay) -> CaptureResult? {
  ```
  `capture` takes values and runs the source (:377, :381). Replace:
  ```swift
      func capture(_ target: CaptureTarget, excludingWindows: [SCWindow] = [],
  ```
  with:
  ```swift
      func capture(_ target: CaptureTarget, excludingWindows: [CaptureWindow] = [],
  ```
  Replace:
  ```swift
              return try await engine.capture(target, options: options, excludingWindows: excludingWindows)
  ```
  with:
  ```swift
              return try await captureSource.capture(target, options: options, excludingWindows: excludingWindows)
  ```
  `cardWindows` asks the source, and `display(under:in:)` leaves the file (:391-402; it is now
  `CaptureEngine.display(under:in:)`). Replace:
  ```swift
      private func cardWindows() async -> [SCWindow] {
          let numbers = overlay.windowNumbers
          guard !numbers.isEmpty else { return [] }
          return await OverlayWindowLookup.windows(numbers: numbers, engine: engine)
      }

      /// The SCDisplay under an AppKit-global point, falling back to the first display.
      static func display(under appKitPoint: CGPoint, in displays: [SCDisplay]) -> SCDisplay? {
          let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
          let cgPoint = Geometry.cgPoint(fromAppKit: appKitPoint, primaryHeight: primaryHeight)
          return displays.first { $0.frame.contains(cgPoint) } ?? displays.first
      }
  }
  ```
  with:
  ```swift
      private func cardWindows() async -> [CaptureWindow] {
          let numbers = overlay.windowNumbers
          guard !numbers.isEmpty else { return [] }
          return await captureSource.windows(numbers: numbers)
      }
  }
  ```
  `runScrolling`'s `save(CaptureResult(... target: .area(rect: rect, display: display)))` (:137-138),
  `captureAfterCountdown`'s re-read by id (:313-338) and `runSelfTimer` (:297-307) compile unchanged over the values.

- [ ] In `TidyShot/App/AppCoordinator+Recording.swift`, Record Screen names `freeze` (:215), Record Fullscreen asks
  the source for the pointer's display (:254), and the two helpers take the values (:596, :604; bodies unchanged).
  Replace:
  ```swift
              guard let selection = await selector.select(mode: .recording, content: content,
  ```
  with:
  ```swift
              guard let selection = await selector.select(mode: .recording, content: content, freeze: nil,
  ```
  Replace:
  ```swift
                    let display = Self.display(under: NSEvent.mouseLocation, in: content.displays) else {
  ```
  with:
  ```swift
                    let display = captureSource.displayUnderPointer(in: content.displays) else {
  ```
  Replace:
  ```swift
      private func connectedDisplay(_ id: CGDirectDisplayID, in content: SCShareableContent) -> SCDisplay? {
  ```
  with:
  ```swift
      private func connectedDisplay(_ id: CGDirectDisplayID, in content: ScreenContent) -> CaptureDisplay? {
  ```
  Replace:
  ```swift
      private static func recordingDisplay(_ display: SCDisplay) -> RecordingDisplay {
  ```
  with:
  ```swift
      private static func recordingDisplay(_ display: CaptureDisplay) -> RecordingDisplay {
  ```
  `recordingHandOff` (:484-582) compiles unchanged: it reads `displayID`, `frame` and `windowID` and rebuilds targets
  from `content.displays.first(where:)` and `content.windows.first(where:)`, which now yield the values.

- [ ] Check the production change:
  ```bash
  grep -rn "SCDisplay\|SCWindow\|SCShareableContent\|engine\.\|display(under\|lazy var selector" TidyShot/App/
  git diff --stat HEAD -- TidyShot/
  ```
  Expected, the grep, exactly these two lines (two doc comments that name the engine and an `SCWindow` in prose):
  ```
  TidyShot/App/AppCoordinator+Capture.swift:313:    /// countdown, and an `SCWindow` from before would size the image from its old frame. The
  TidyShot/App/AppCoordinator+Capture.swift:376:    /// Runs the engine. On failure posts a notification and returns nil. `duringSelection` is
  ```
  and the diffstat lists `AppCoordinator+Capture.swift` (37), `AppCoordinator+Recording.swift` (8),
  `AppCoordinator.swift` (14), `AppEnvironment.swift` (18), `CaptureEngine.swift` (30), `CaptureTarget.swift` (26),
  `PreviousArea.swift` (2), `AllInOneChoice.swift` (10), `Selection.swift` (13) and `SelectionController.swift` (32),
  ending `10 files changed, 126 insertions(+), 64 deletions(-)` (the new `CaptureSource.swift` is untracked). The
  test target does not build until the world passes the two new arguments (next section); do not build yet.

#### The fakes and the world (design 3.2, 3.3)

- [ ] Create `TidyShotTests/Support/CaptureSourceFakes.swift` with exactly this content. It is design 3.2 less the
  five members design section 12 says to leave out unless a test needs one, and none of C1 to C8 does:
  `FakeSelector.answerAllInOne(_:)` with its held All-in-One branch, `FakeSelector.overlays`,
  `FakeSelector.frozen`, `FakeCaptureSource.scale` and `FakeCaptureSource.pointerDisplayID` (see Plan decisions).
  `SingleWaiter` (CoordinatorFakes.swift:409) needs `Value: Sendable`, hence the `Bool` and the answer kept beside it;
  `CoordinatorWorld.image(width:height:)` (CoordinatorWorld.swift:194) makes the red image:
  ```swift
  import CoreGraphics
  import Foundation
  import Testing
  @testable import TidyShot

  nonisolated struct FakeCaptureError: LocalizedError, Sendable { var errorDescription: String? { "The fake source failed." } }
  /// The capture source in the suite: ScreenCaptureKit, the screen and the pointer are never reached. Each read gives
  /// `content` unless `contentFailures` has an error left; a capture is recorded, then throws `captureFailure` or answers
  /// a red image of the target's `cgFrame` size at scale 1. The display under the pointer is the first one, and Screen
  /// Recording is always granted.
  final class FakeCaptureSource: CaptureSource {
      struct Capture: Equatable { let target: CaptureTarget; let options: CaptureOptions; let excludedWindowIDs: [CGWindowID] }
      static let display = CaptureDisplay(displayID: 1, frame: CGRect(x: 0, y: 0, width: 1440, height: 900))
      var content = ScreenContent(displays: [FakeCaptureSource.display], windows: [])
      var contentFailures: [any Error] = [], captureFailure: (any Error)?
      private(set) var contentReads = 0, captures: [Capture] = [], windowLookups: [Set<CGWindowID>] = []
      let isScreenRecordingGranted = true
      func screenContent() async throws -> ScreenContent {
          contentReads += 1; if !contentFailures.isEmpty { throw contentFailures.removeFirst() }; return content
      }
      func capture(_ target: CaptureTarget, options: CaptureOptions, excludingWindows: [CaptureWindow]) async throws -> CaptureResult {
          captures.append(Capture(target: target, options: options, excludedWindowIDs: excludingWindows.map(\.windowID)))
          if let captureFailure { throw captureFailure }
          let size = Geometry.pixelSize(points: target.cgFrame.size, scale: 1)
          return CaptureResult(image: try CoordinatorWorld.image(width: max(size.width, 1), height: max(size.height, 1)), scale: 1, target: target)
      }
      func windows(numbers: Set<CGWindowID>) async -> [CaptureWindow] { windowLookups.append(numbers); return content.windows.filter { numbers.contains($0.windowID) } }
      func displayUnderPointer(in displays: [CaptureDisplay]) -> CaptureDisplay? { displays.first }
  }
  /// The selection overlay in the suite: no window is built and the screen is never read. Every ask is kept; each answers
  /// the next of `selections` or `choices` (nil, or none left, is Escape). While `holds` is set, `select` waits for
  /// `answer(_:)`; a held overlay whose task is cancelled answers Escape, and a second while one is held records an issue.
  /// No freeze snapshot and no overlay window exist.
  final class FakeSelector: CaptureSelecting {
      struct Select: Equatable { let mode: SelectionMode; let freeze: CaptureOptions?; let preselect: CGRect? }
      struct AllInOne: Equatable { let freeze: CaptureOptions?; let preselect: CGRect?; let armed: Bool }
      private(set) var selects: [Select] = [], allInOnes: [AllInOne] = [], frozenAsked: [CGDirectDisplayID] = []
      private(set) var overlayLookups = 0, dismissCount = 0
      var selections: [Selection?] = [], choices: [AllInOneChoice?] = [], holds = false
      private var heldSelection: Selection?
      private let held = SingleWaiter(cancelled: false, secondEntry: "FakeSelector was asked again while an overlay was held")
      var isWaiting: Bool { held.isWaiting }
      func select(mode: SelectionMode, content: ScreenContent, freeze: CaptureOptions?, preselect: CGRect?) async -> Selection? {
          selects.append(Select(mode: mode, freeze: freeze, preselect: preselect))
          guard holds else { return selections.isEmpty ? nil : selections.removeFirst() }
          guard await held.wait() else { return nil }
          defer { heldSelection = nil }; return heldSelection
      }
      func selectAllInOne(content: ScreenContent, freeze: CaptureOptions?, preselect: CGRect?, armed: Bool) async -> AllInOneChoice? {
          allInOnes.append(AllInOne(freeze: freeze, preselect: preselect, armed: armed))
          return choices.isEmpty ? nil : choices.removeFirst()
      }
      /// Answers the held `select`; with none held it only clears `holds`, so a test's `defer` can call it.
      func answer(_ selection: Selection?) { holds = false; heldSelection = selection; held.resume(true) }
      func frozenCapture(for displayID: CGDirectDisplayID) -> FrozenSnapshot? { frozenAsked.append(displayID); return nil }
      func overlayWindows() async -> [CaptureWindow] { overlayLookups += 1; return [] }
      func dismiss() { dismissCount += 1 }
  }
  ```

- [ ] In `TidyShotTests/Support/CoordinatorWorld.swift`, the type doc names the two (:13-17). Replace:
  ```swift
  /// the coordinator opens (`editors`; no window is built), Clop (`clop`, over `<root>/tmp/Clop`), the card's
  /// Save As… panel (`saveAsChooser`; none is built), a clock the test moves, a date it sets, free space it
  /// sets, the two logs it reads (`logLines`, `recordingLines`) and a destination factory. Build it in the
  /// suite's `init`, make the coordinator with `makeCoordinator()`, and `defer { world.removeAll() }` first
  /// thing in each test.
  ```
  with:
  ```swift
  /// the coordinator opens (`editors`; no window is built), Clop (`clop`, over `<root>/tmp/Clop`), the card's
  /// Save As… panel (`saveAsChooser`; none is built), the capture source and the selection overlay (`source`,
  /// `selector`; no window is built and ScreenCaptureKit is never read), a clock the test moves, a date it
  /// sets, free space it sets, the two logs it reads (`logLines`, `recordingLines`) and a destination factory.
  /// Build it in the suite's `init`, make the coordinator with `makeCoordinator()`, and
  /// `defer { world.removeAll() }` first thing in each test.
  ```
  Add them after the clipboard (:43). Replace:
  ```swift
      let clipboard = FakeClipboard()
      let confirm = FakeConfirm()
  ```
  with:
  ```swift
      let clipboard = FakeClipboard()
      /// The capture source (`environment.captureSource`): ScreenCaptureKit is never read.
      let source = FakeCaptureSource()
      /// The selection overlay (`environment.selector`); no window is built.
      let selector = FakeSelector()
      let confirm = FakeConfirm()
  ```
  Pass them after `clipboard: clipboard,` (:133), in the order of `AppEnvironment`'s members. Replace:
  ```swift
              clipboard: clipboard,
              makeDestination: { config, credentials in factory.make(config, credentials) },
  ```
  with:
  ```swift
              clipboard: clipboard,
              captureSource: source,
              selector: selector,
              makeDestination: { config, credentials in factory.make(config, credentials) },
  ```
  `environment` is read once per `makeCoordinator()`; the fakes are the world's `let`s, so a test reads them after
  the coordinator is built, as it reads `notifier` and `clipboard`.

- [ ] In `TidyShotTests/CoordinatorWorldTests.swift`, `aCoordinatorOverTheWorldKeepsToTheWorld` checks that building
  a coordinator reads nothing and asks nothing (after :35, design 3.3; a check, not a test). Replace:
  ```swift
          #expect(world.saveAsChooser.asked.isEmpty)
  ```
  with:
  ```swift
          #expect(world.saveAsChooser.asked.isEmpty)
          #expect(world.source.contentReads == 0)
          #expect(world.source.captures.isEmpty)
          #expect(world.selector.selects.isEmpty)
          #expect(world.selector.allInOnes.isEmpty)
  ```

- [ ] In `TidyShotTests/CoordinatorCaptureTests.swift`, the lock test counts the content reads (design 3.3; a check,
  not a test). The suite doc (:5-7) said a capture past the lock would read content the suite never reaches; with the
  fake it would read the fake's, so the doc says the count is checked. Replace:
  ```swift
  /// The capture lock on a built coordinator (`withCaptureLock`): a capture command while another capture holds
  /// it returns at once. A capture the lock let through would read the shareable content, which the suite never
  /// reaches.
  ```
  with:
  ```swift
  /// The capture lock on a built coordinator (`withCaptureLock`): a capture command while another capture holds
  /// it returns at once and reads no content (`world.source.contentReads`, the fake capture source).
  ```
  The comment at :34 said the same of the gate. Replace:
  ```swift
          // Gated with `eventually`: a lock that let the capture through would wait on the content read.
  ```
  with:
  ```swift
          // Gated with `eventually`: a lock that let the capture through would read the fake content and ask the overlay.
  ```
  The check goes after the last no-effect check (:46). Replace:
  ```swift
          #expect(world.clipboard.copies.isEmpty)
          #expect(coordinator.isCapturing)
  ```
  with:
  ```swift
          #expect(world.clipboard.copies.isEmpty)
          #expect(world.source.contentReads == 0)
          #expect(coordinator.isCapturing)
  ```

- [ ] Build the test target, to see the production change and the fakes compile before the tests are added:
  ```bash
  xcodegen generate && xcodebuild build-for-testing -project TidyShot.xcodeproj -scheme TidyShot -destination 'platform=macOS' -derivedDataPath .build 2>&1 | grep -E "error:|warning: .*\.swift|TEST BUILD"
  ```
  Expected: `** TEST BUILD SUCCEEDED **` and no `error:` or Swift `warning:` line (the `iOSSimulator` tool line may
  print; it is noise). A compile error in a `TidyShot/` file is a failure of the design's diff: stop and report it,
  do not widen the change (design 2.2, Isolation).

#### The tests (catalogue CAPSRC.4, CAPSRC.5)

- [ ] Create `TidyShotTests/CoordinatorCaptureSourceTests.swift` with exactly this content (C1 to C7, in catalogue
  order). C3 and C5 are the review's built tests with their doc comments filled in. The values each assertion reads
  are in the catalogue entry beside the test; the ones the code decides, with their file:line at 705bce0: `Capture an
  area first.` and `The previous area is not on a connected display.` under `No previous area`
  (AppCoordinator+Capture.swift:152, :154); `selectAllInOne`'s `preselect: preselect?.rect ?? settings.lastAreaRect?.cgRect`
  and `armed: !fromURLCommand` (:37-39); the URL handler's drop while `isCapturing` (URLCommandHandler.swift:154-157,
  AppCoordinator.swift:557); `captureText`'s `selectedAreaResult`, which stores nothing (:235, :349-355), and
  `frozenResult`'s ask with freeze off (:360); `Shareable content failed: ` and `Could not list screens and windows: `
  (AppCoordinator.swift:523, :525); `Select an area at least 100 points tall.` under `Scrolling capture` and the
  `>=` check (AppCoordinator+Capture.swift:119-121); the store after a captured URL rect (:175-177); `Capture failed: `
  (:383) and `notifyError`'s default title `Capture failed` (Notifier.swift:180); `Image copied` with
  `"<w> × <h> px"` and the shutter (AppCoordinator+Save.swift, `copyOnly`). Settings read at their defaults in a fresh
  world: `showsCursor`, `windowShadow`, `freezeScreen`, `windowBackground` and `hideDesktopIconsWhileCapturing` off,
  `playSound` and `showNotification` on, URL commands on and `urlCommandsAllowSilent` off (AppSettings.swift:267-310):
  ```swift
  import CoreGraphics
  import Foundation
  import Testing
  @testable import TidyShot

  /// The capture entry points over the fake capture source and selection overlay (capture seams design 2.2, `CAPSRC`:
  /// `world.source`, `world.selector`). Nothing reads ScreenCaptureKit, the screen or the pointer, and no overlay window
  /// is built. Every entry gets an explicit intent (the default `.standard` reads `AppSettings.shared`), and a capture
  /// that reaches a save is copy-only, so no save folder is asked for and no record is made. A test-built display has
  /// no ScreenCaptureKit object, so a scrolling capture stops after the 100 pt check and the store, before the session.
  @Suite(.timeLimit(.minutes(1)))
  struct CoordinatorCaptureSourceTests {
      let world: CoordinatorWorld

      init() throws {
          world = try CoordinatorWorld()
          // A card's screen is read from `NSScreen`.
          world.settings.showOverlay = false
      }

      nonisolated enum StoredArea: CaseIterable, Sendable {
          case none
          case offItsDisplay
      }

      /// phase-6a:209 (:254), full; phase-6a:214 (:260), full. With no stored area, or one that leaves under a point on
      /// its display (the line's own strip: x -0.4, 1.2 pt wide, its centre on display 1's left edge and 0.8 pt of it on
      /// the display), ⌃⇧6 posts its refusal under `No previous area` and captures nothing, asks no overlay and leaves
      /// the stored value as it was. The two resolutions are `PreviousAreaTests.noRectResolvesToNone` and
      /// `.aRectLeavingUnderOnePointOnItsDisplayIsOffScreen`; the stored value across a relaunch is
      /// `AppSettingsTests.lastAreaRectRoundTripsThroughASecondInstanceAndClears`. The `defaults` commands and the quit
      /// and reopen are replaced by the setting.
      @Test(arguments: StoredArea.allCases)
      func capturePreviousAreaWithNoUsableStoredAreaIsRefusedAndCapturesNothing(stored: StoredArea) async throws {
          defer { world.removeAll() }
          let rect: StoredRect?
          let message: String
          switch stored {
          case .none:
              rect = nil
              message = "Capture an area first."
          case .offItsDisplay:
              rect = StoredRect(CGRect(x: -0.4, y: 100, width: 1.2, height: 200))
              message = "The previous area is not on a connected display."
          }
          world.settings.lastAreaRect = rect
          let coordinator = world.makeCoordinator()

          await coordinator.capturePreviousArea(intent: CaptureIntent(action: .save))

          #expect(world.notifier.calls == [.error(title: "No previous area", message: message)])
          #expect(world.source.contentReads == 1)
          #expect(world.source.captures.isEmpty)
          #expect(world.source.windowLookups.isEmpty)
          #expect(world.selector.selects.isEmpty)
          #expect(world.selector.allInOnes.isEmpty)
          #expect(world.clipboard.copies.isEmpty)
          #expect(coordinator.history.records.isEmpty)
          #expect(world.shutterCount == 0)
          #expect(world.cards.calls.isEmpty)
          #expect(world.logLines.isEmpty)
          #expect(world.settings.lastAreaRect == rect)
          #expect(!coordinator.isCapturing)
      }

      /// phase-6b:62 (:77), in part; phase-6b:104 (:122), in part; phase-6b:105 (:123), in part. ⌃⇧1 opens All-in-One
      /// on the stored area armed; `t 'all-in-one?x=0&y=0&width=500&height=400'` opens it on the URL's rect disarmed, and
      /// `t all-in-one` on the stored area disarmed; Escape in each leaves the stored area unchanged. Stays: the rect
      /// shown selected and adjustable, and none when its display is unplugged (`SelectionController.placePreselected`,
      /// `SELINT`'s); arming by a W change or the lock toggle, and Return typed in another app as the overlay appears
      /// (by hand). The restore rule is `SelectionAdjustTests.restoreKeepsARectOnItsDisplay` and
      /// `.restoreRefusesARectOffEveryDisplay`; the URL's routing and rect are
      /// `URLCommandHandlerTests.everyCommandReachesItsCaptureFunction` and
      /// `URLCommandGeometryTests.theOriginIsTheBottomLeftOfTheMainDisplay`; a disarmed rect's keys are
      /// `SelectionViewArmingTests`.
      @Test func allInOneOpensOnThePreviousAreaArmedOrAURLRectDisarmedAndEscapeStoresNothing() async throws {
          defer { world.removeAll() }
          let previous = CGRect(x: 100, y: 120, width: 300, height: 200)
          // Where the URL's x 0, y 0, 500 x 400 lands on the 900 pt high display: y = 900 - 0 - 400.
          let urlRect = CGRect(x: 0, y: 500, width: 500, height: 400)
          let intent = CaptureIntent(action: .save)
          world.settings.lastAreaRect = StoredRect(previous)
          let coordinator = world.makeCoordinator()

          await coordinator.captureAllInOne(intent: intent)
          await coordinator.captureAllInOne(intent: intent, preselect: ScreenRect(rect: urlRect, displayID: 1),
                                            fromURLCommand: true)
          await coordinator.captureAllInOne(intent: intent, preselect: nil, fromURLCommand: true)

          #expect(world.selector.allInOnes == [
              FakeSelector.AllInOne(freeze: nil, preselect: previous, armed: true),
              FakeSelector.AllInOne(freeze: nil, preselect: urlRect, armed: false),
              FakeSelector.AllInOne(freeze: nil, preselect: previous, armed: false),
          ])
          #expect(world.settings.lastAreaRect == StoredRect(previous))
          #expect(world.selector.dismissCount == 0)
          #expect(world.source.contentReads == 3)
          #expect(world.source.captures.isEmpty)
          #expect(world.selector.selects.isEmpty)
          #expect(world.notifier.calls.isEmpty)
          #expect(!coordinator.isCapturing)
      }

      /// phase-6b:160 (:211), full; phase-6b:159 (:210), in part (the open selection). With one `capture-window` URL's
      /// selection held open, two more `capture-window` URLs and `capture-fullscreen`, `capture-area` and
      /// `capture-scrolling` are dropped: one overlay was asked, nothing more is read, captured or posted, and no
      /// scrolling session starts. Stays: while a self-timer counts (`STAGE`'s), and during a scrolling session before
      /// and after Start (`SCROLL`'s). The dropped line's text is
      /// `URLCommandHandlerTests.theLogSaysWhyACaptureCommandWasDropped` and the drop with the refusal faked is
      /// `.captureCommandsAreDroppedWhileCapturesAreRefused`. The selection is held.
      @Test func aHeldSelectionOpensOneWindowAndDropsEveryOtherURLCaptureCommandWithoutReadingOrPosting() async throws {
          defer { world.removeAll() }
          defer { world.selector.answer(nil) }
          // `capture-fullscreen` captures without a selection, which the gate refuses unless this is on.
          world.settings.urlCommandsAllowSilent = true
          world.selector.holds = true
          let coordinator = world.makeCoordinator()
          let handler = URLCommandHandler(settings: world.settings, target: coordinator,
                                          screens: { URLCommandHandler.Screens(displays: [], pointerIndex: nil) },
                                          post: { notice in Issue.record("posted \(notice.body)") })
          await handler.ready()
          let window = try #require(URL(string: "tidyshot://capture-window"))
          let first = Task { await handler.handle(window, sender: "Terminal") }
          defer { first.cancel() }
          let firstWatch = TaskWatch(first)
          try await eventually { world.selector.isWaiting }

          let others = ["capture-window", "capture-window", "capture-fullscreen", "capture-area", "capture-scrolling"]
          var watches: [TaskWatch] = []
          for name in others {
              let url = try #require(URL(string: "tidyshot://\(name)"))
              watches.append(TaskWatch(Task { await handler.handle(url, sender: "Terminal") }))
          }
          try await eventually { watches.allSatisfy(\.hasReturned) }

          #expect(world.selector.selects == [FakeSelector.Select(mode: .window, freeze: nil, preselect: nil)])
          #expect(world.selector.allInOnes.isEmpty)
          #expect(world.source.contentReads == 1)
          #expect(world.source.captures.isEmpty)
          #expect(world.notifier.calls.isEmpty)
          #expect(coordinator.isCapturing)
          #expect(!firstWatch.hasReturned)
          #expect(!coordinator.scrollCapture.isRunning)

          world.selector.answer(nil)
          try await eventually { firstWatch.hasReturned }
          #expect(!coordinator.isCapturing)
          #expect(world.source.captures.isEmpty)
          #expect(world.selector.selects.count == 1)
          #expect(world.selector.dismissCount == 0)
      }

      /// phase-7b:81 (:87), full. Capture Text takes its area without storing it, so ⌃⇧6 after it captures the earlier
      /// image area (300 x 200, on the clipboard), not the 40 x 20 text selection. The text recognizer runs for real on
      /// the fake's red image and finds nothing; its notice is not read here.
      @Test func capturePreviousAreaAfterCaptureTextCapturesTheEarlierImageArea() async throws {
          defer { world.removeAll() }
          let earlier = CGRect(x: 100, y: 100, width: 300, height: 200)
          let textArea = CGRect(x: 600, y: 400, width: 40, height: 20)
          let options = CaptureOptions(showsCursor: false, windowShadow: false)
          world.settings.lastAreaRect = StoredRect(earlier)
          world.selector.selections = [.area(rect: textArea, display: FakeCaptureSource.display)]
          let coordinator = world.makeCoordinator()

          await coordinator.captureText()

          let textCapture = FakeCaptureSource.Capture(target: .area(rect: textArea, display: FakeCaptureSource.display),
                                                      options: options, excludedWindowIDs: [])
          #expect(world.settings.lastAreaRect == StoredRect(earlier))
          #expect(world.selector.selects == [FakeSelector.Select(mode: .area, freeze: nil, preselect: nil)])
          #expect(world.selector.frozenAsked == [1])
          #expect(world.selector.overlayLookups == 1)
          #expect(world.selector.dismissCount == 1)
          #expect(world.source.captures == [textCapture])

          await coordinator.capturePreviousArea(intent: CaptureIntent(action: .save, copyOnly: true))

          #expect(world.settings.lastAreaRect == StoredRect(earlier))
          #expect(world.source.contentReads == 2)
          #expect(world.source.captures == [
              textCapture,
              FakeCaptureSource.Capture(target: .area(rect: earlier, display: FakeCaptureSource.display),
                                        options: options, excludedWindowIDs: []),
          ])
          #expect(world.clipboard.pngs.count == 1)
          let png = try #require(world.clipboard.pngs.first)
          let decoded = try EditorPixels.decoded(png)
          #expect(decoded.image.width == 300)
          #expect(decoded.image.height == 200)
          #expect(decoded.scale == 1)
      }

      /// The harness, no checklist line: a content read that fails with Screen Recording granted is logged and posted
      /// under `Capture failed`, and the capture asks no overlay. The permission window's branch is not reached (the
      /// fake's grant is always on).
      @Test func aFailedContentReadIsLoggedAndPostedAndAsksNothingMore() async throws {
          defer { world.removeAll() }
          world.source.contentFailures = [FakeCaptureError()]
          let coordinator = world.makeCoordinator()
          await coordinator.captureArea(intent: CaptureIntent(action: .save))
          #expect(world.logLines == ["Shareable content failed: The fake source failed."])
          #expect(world.notifier.calls == [.error(title: "Capture failed",
                                                  message: "Could not list screens and windows: The fake source failed.")])
          #expect(world.selector.selects.isEmpty)
          #expect(world.source.captures.isEmpty)
          #expect(world.source.contentReads == 1)
          #expect(!coordinator.isCapturing)
      }

      /// phase-5:78 (:78), in part; phase-6a:211 (:256), in part (a refused scrolling area does not replace the stored
      /// one). A 400 x 60 pt scrolling drag is refused with `Select an area at least 100 points tall.` under
      /// `Scrolling capture`, no session starts and the previous area stays; the next ⌃⇧5 gets an overlay again, and a
      /// URL command's 60 pt rect is refused the same way. Stays: the session on an accepted area (`SCROLL`'s), the drag
      /// in the overlay (by hand), and of phase-6a:211 a window click becoming the scrolling area (`SELINT`'s).
      @Test func aScrollingAreaUnder100PointsIsRefusedAndTheNextShortcutWorks() async throws {
          defer { world.removeAll() }
          let stored = StoredRect(CGRect(x: 10, y: 20, width: 300, height: 200))
          let drag = CGRect(x: 100, y: 100, width: 400, height: 60)
          let intent = CaptureIntent(action: .save)
          world.settings.lastAreaRect = stored
          world.selector.selections = [.area(rect: drag, display: FakeCaptureSource.display),
                                       .area(rect: drag, display: FakeCaptureSource.display)]
          let coordinator = world.makeCoordinator()

          await coordinator.captureScrolling(intent: intent)
          await coordinator.captureScrolling(intent: intent)
          await coordinator.captureScrolling(intent: intent, preselect: ScreenRect(rect: drag, displayID: 1))

          let refusal = FakeNotifier.Call.error(title: "Scrolling capture",
                                                message: "Select an area at least 100 points tall.")
          #expect(world.notifier.calls == [refusal, refusal, refusal])
          let scrolling = FakeSelector.Select(mode: .scrolling, freeze: nil, preselect: nil)
          #expect(world.selector.selects == [scrolling, scrolling])
          #expect(world.selector.dismissCount == 3)
          #expect(world.source.contentReads == 3)
          #expect(world.settings.lastAreaRect == stored)
          #expect(world.source.captures.isEmpty)
          #expect(!coordinator.isCapturing)
          #expect(!coordinator.scrollCapture.isRunning)
      }

      /// phase-6a:211 (:256), in part; phase-6b:127 (:162), in part; phase-5:78 (:78), in part (an area exactly 100 pt
      /// tall is accepted). A window capture and a fullscreen capture leave the previous area; a `capture-area` URL rect
      /// replaces it once captured, and ⌃⇧6 captures it again; a URL rect whose capture fails does not; a 100 pt tall
      /// scrolling drag replaces it. Stays: the scrolling session on the accepted area, and a `capture-scrolling` rect
      /// stored only once the stitched image is saved (`SCROLL`'s); a window click becoming the scrolling area
      /// (`SELINT`'s); the drag in the overlay (by hand). The relaunch is
      /// `AppSettingsTests.lastAreaRectRoundTripsThroughASecondInstanceAndClears`.
      @Test func windowAndFullscreenCapturesLeaveThePreviousAreaAndAScrollingDragStoresIt() async throws {
          defer { world.removeAll() }
          let stored = StoredRect(CGRect(x: 10, y: 20, width: 300, height: 200))
          let window = CaptureWindow(windowID: 7, frame: CGRect(x: 200, y: 150, width: 300, height: 200))
          let urlArea = ScreenRect(rect: CGRect(x: 50, y: 60, width: 200, height: 120), displayID: 1)
          let failedArea = ScreenRect(rect: CGRect(x: 400, y: 300, width: 200, height: 120), displayID: 1)
          let drag = CGRect(x: 100, y: 100, width: 400, height: 100)
          // Copy-only: no save folder, no record.
          let copy = CaptureIntent(action: .save, copyOnly: true)
          let options = CaptureOptions(showsCursor: false, windowShadow: false)
          world.settings.lastAreaRect = stored
          world.selector.selections = [.window(window)]
          let coordinator = world.makeCoordinator()

          // 1. Capture Window: the window, nothing excluded; the previous area stays.
          await coordinator.captureWindow(intent: copy)
          #expect(world.source.captures == [FakeCaptureSource.Capture(target: .window(window), options: options,
                                                                      excludedWindowIDs: [])])
          #expect(world.selector.selects == [FakeSelector.Select(mode: .window, freeze: nil, preselect: nil)])
          #expect(world.settings.lastAreaRect == stored)
          #expect(world.clipboard.pngs.count == 1)
          let windowPNG = try EditorPixels.decoded(try #require(world.clipboard.pngs.first))
          #expect(windowPNG.image.width == 300)
          #expect(windowPNG.image.height == 200)
          #expect(windowPNG.scale == 1)
          #expect(world.notifier.calls.last == .notice(title: "Image copied", body: "300 × 200 px", subtitle: nil))
          #expect(world.shutterCount == 1)
          #expect(world.selector.dismissCount == 1)

          // 2. Capture Fullscreen: the display under the pointer; the previous area stays.
          await coordinator.captureFullscreen(intent: copy)
          #expect(world.source.captures.count == 2)
          #expect(world.source.captures.last == FakeCaptureSource.Capture(target: .display(FakeCaptureSource.display),
                                                                          options: options, excludedWindowIDs: []))
          #expect(world.settings.lastAreaRect == stored)
          #expect(world.notifier.calls.last == .notice(title: "Image copied", body: "1440 × 900 px", subtitle: nil))
          #expect(world.shutterCount == 2)

          // 3. A `capture-area` URL rect: captured, then stored.
          await coordinator.captureArea(at: urlArea, intent: copy)
          #expect(world.source.captures.count == 3)
          #expect(world.source.captures.last == FakeCaptureSource.Capture(
              target: .area(rect: urlArea.rect, display: FakeCaptureSource.display), options: options,
              excludedWindowIDs: []))
          #expect(world.settings.lastAreaRect == StoredRect(urlArea.rect))
          #expect(world.notifier.calls.last == .notice(title: "Image copied", body: "200 × 120 px", subtitle: nil))

          // 4. ⌃⇧6 captures the URL rect again.
          await coordinator.capturePreviousArea(intent: copy)
          #expect(world.source.captures.count == 4)
          #expect(world.source.captures.last == FakeCaptureSource.Capture(
              target: .area(rect: urlArea.rect, display: FakeCaptureSource.display), options: options,
              excludedWindowIDs: []))
          #expect(world.settings.lastAreaRect == StoredRect(urlArea.rect))
          #expect(world.notifier.calls.last == .notice(title: "Image copied", body: "200 × 120 px", subtitle: nil))
          #expect(world.shutterCount == 4)

          // 5. A URL rect whose capture fails is not stored.
          world.source.captureFailure = FakeCaptureError()
          await coordinator.captureArea(at: failedArea, intent: copy)
          #expect(world.source.captures.count == 5)
          #expect(world.source.captures.last?.target == .area(rect: failedArea.rect, display: FakeCaptureSource.display))
          #expect(world.settings.lastAreaRect == StoredRect(urlArea.rect))
          #expect(world.logLines == ["Capture failed: The fake source failed."])
          #expect(world.notifier.calls.last == .error(title: "Capture failed", message: "The fake source failed."))
          #expect(world.shutterCount == 4)
          world.source.captureFailure = nil

          // 6. A scrolling drag exactly 100 pt tall passes the check and is stored before the session.
          world.selector.selections = [.area(rect: drag, display: FakeCaptureSource.display)]
          await coordinator.captureScrolling(intent: CaptureIntent(action: .save))
          #expect(world.settings.lastAreaRect == StoredRect(drag))
          #expect(world.selector.selects.last == FakeSelector.Select(mode: .scrolling, freeze: nil, preselect: nil))
          #expect(world.selector.dismissCount == 2)
          #expect(!coordinator.isCapturing)
          #expect(!coordinator.scrollCapture.isRunning)
          #expect(world.source.captures.count == 5)

          #expect(world.notifier.calls == [
              .notice(title: "Image copied", body: "300 × 200 px", subtitle: nil),
              .notice(title: "Image copied", body: "1440 × 900 px", subtitle: nil),
              .notice(title: "Image copied", body: "200 × 120 px", subtitle: nil),
              .notice(title: "Image copied", body: "200 × 120 px", subtitle: nil),
              .error(title: "Capture failed", message: "The fake source failed."),
          ])
      }
  }
  ```
  No test reaches `runSelfTimer`, `recordingCanStart`, All-in-One's `.fullscreen` choice or `covers`: C2 answers
  Escape, `captureFullscreen` in C7 runs with `hideDesktopIconsWhileCapturing` off, and the scrolling captures stop at
  the test-built display's missing `live` object. C4 runs the real `TextRecognizer` on a 40 x 20 red image
  (AppCoordinator+Capture.swift:273), as `TextRecognizerTests` do in the same run; the first request after a restart
  can take about 24 s, inside the one-minute limit (design call 5).

- [ ] In `TidyShotTests/CoordinatorRecordingTests.swift`, C8 (catalogue CAPSRC.5). The test's doc comment
  (:349-352) names its line by key and current line, and what stays and whose. Replace:
  ```swift
      /// recording-r2 :351, the held prompt's part (a B line, left unmarked, D15). With the microphone prompt up, a
      /// second record press asks nothing, every capture is refused for the prompt, and a quit before the answer
      /// starts nothing. The disabled menu items, the dropped URL command's log line and the recording that
      /// starts after the answer stay with the line's seams.
  ```
  with:
  ```swift
      /// recording-r2:351 (:386), in part. With the microphone prompt up, a second record press asks nothing and logs
      /// `Recording: start ignored, the microphone prompt is open`; each of the eight capture entries (⌃⇧1 to ⌃⇧7 and
      /// the self-timer) is refused for the prompt and reads no content, asks no overlay and captures nothing (C8, over
      /// the fake capture source and selector); a quit before the answer starts nothing. Stays: the status menu's
      /// capture items shown disabled (`STATUSMENU`'s), and the recording that starts as usual after the answer
      /// (`TMPDIRS`' and `RECCHROME`'s). The URL command's dropped line is
      /// `URLCommandHandlerTests.theLogSaysWhyACaptureCommandWasDropped`.
  ```
  The step goes after the refusal checks (:362-364) and before the second press (:366): the eight capture entries,
  each with an explicit intent, one at a time as a gated task. The start is held at the prompt before the lock
  (AppCoordinator+Recording.swift:211, :248), so `isCapturing` is false and each entry is refused by
  `withCaptureLock` (AppCoordinator.swift:573; `captureScrolling` first reads `scrollCapture.isRunning`, false). After
  the second press, its `Recording:` line (AppCoordinator+Recording.swift:293). Replace:
  ```swift
          #expect(coordinator.captureRefusal == .permissionPrompt(.microphone))

          let second = TaskWatch(Task { await coordinator.recordScreen() })
          try await eventually { second.hasReturned }
          #expect(microphones.requestCount == 1)
  ```
  with:
  ```swift
          #expect(coordinator.captureRefusal == .permissionPrompt(.microphone))

          // C8: every capture entry, one at a time, refused at the lock for the prompt.
          let intent = CaptureIntent(action: .save)
          let entries: [@MainActor () async -> Void] = [
              { await coordinator.captureAllInOne(intent: intent) },
              { await coordinator.captureWindow(intent: intent) },
              { await coordinator.captureFullscreen(intent: intent) },
              { await coordinator.captureArea(intent: intent) },
              { await coordinator.captureScrolling(intent: intent) },
              { await coordinator.capturePreviousArea(intent: intent) },
              { await coordinator.captureText() },
              { await coordinator.captureSelfTimer(intent: intent) },
          ]
          for entry in entries {
              let refused = TaskWatch(Task { await entry() })
              try await eventually { refused.hasReturned }
          }
          #expect(world.source.contentReads == 0)
          #expect(world.source.captures.isEmpty)
          #expect(world.source.windowLookups.isEmpty)
          #expect(world.selector.selects.isEmpty)
          #expect(world.selector.allInOnes.isEmpty)
          #expect(world.selector.dismissCount == 0)
          #expect(world.notifier.calls.isEmpty)
          #expect(world.cards.calls.isEmpty)
          #expect(world.clipboard.copies.isEmpty)
          #expect(coordinator.history.records.isEmpty)
          #expect(world.shutterCount == 0)
          #expect(coordinator.askingPermission == .microphone)
          #expect(!coordinator.isCapturing)

          let second = TaskWatch(Task { await coordinator.recordScreen() })
          try await eventually { second.hasReturned }
          #expect(microphones.requestCount == 1)
          #expect(world.recordingLines == ["Recording: start ignored, the microphone prompt is open"])
  ```
  At the end, the prompt's answer line (:339, `granted` false) and no coordinator log line. Replace:
  ```swift
          #expect(coordinator.askingPermission == nil)
          #expect(world.notifier.calls == [.waited(.seconds(1))])
      }

      // MARK: The `Recording:` lines (small seams design, LOG)
  ```
  with:
  ```swift
          #expect(coordinator.askingPermission == nil)
          #expect(world.notifier.calls == [.waited(.seconds(1))])
          #expect(world.recordingLines == ["Recording: start ignored, the microphone prompt is open",
                                           "Recording: microphone access refused at the prompt"])
          #expect(world.logLines.isEmpty)
      }

      // MARK: The `Recording:` lines (small seams design, LOG)
  ```
  The quit block is unchanged and still ends the start before the lock (`if isQuitting { return nil }`,
  AppCoordinator+Recording.swift:340), so nothing makes `tmp/Recording`.

#### Runs, the Release build and the commit

- [ ] Run the new suite alone:
  ```bash
  xcodegen generate && xcodebuild test -project TidyShot.xcodeproj -scheme TidyShot -destination 'platform=macOS' -derivedDataPath .build -only-testing:TidyShotTests/CoordinatorCaptureSourceTests 2>&1 | grep -E "Test run with|error:|TEST"
  ```
  Expected: `✔ Test run with 7 tests in 1 suite passed after …` and `** TEST SUCCEEDED **`. The `error:` lines that
  print are the known noise only (`com.apple.linkd.autoShortcut`, `MDB_MAP_FULL`, and the `iOSSimulator: …
  sharedServiceContextForDeveloperDir:error:` line where CoreSimulator is out of date).

- [ ] Run the new suite with the three existing suites the task edits:
  ```bash
  xcodebuild test -project TidyShot.xcodeproj -scheme TidyShot -destination 'platform=macOS' -derivedDataPath .build -only-testing:TidyShotTests/CoordinatorCaptureSourceTests -only-testing:TidyShotTests/CoordinatorWorldTests -only-testing:TidyShotTests/CoordinatorCaptureTests -only-testing:TidyShotTests/CoordinatorRecordingTests 2>&1 | grep -E "Test run with|error:|TEST"
  ```
  Expected: `✔ Test run with 25 tests in 4 suites passed after …` and `** TEST SUCCEEDED **`, with the same noise only.

- [ ] Run the full suite:
  ```bash
  xcodegen generate && xcodebuild test -project TidyShot.xcodeproj -scheme TidyShot -destination 'platform=macOS' -derivedDataPath .build 2>&1 | grep -E "Test run with|error:|TEST"
  ```
  Expected: `✔ Test run with 2380 tests in 197 suites passed after …` and `** TEST SUCCEEDED **`. The `error:` lines
  are noise only: `History file could not be read or decoded, setting it aside` twice, `com.apple.linkd.autoShortcut`,
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
  Any other line, for example a concurrency warning about `CaptureSource`, `CaptureSelecting` or the `[overlay]`
  capture in `AppEnvironment.swift`, is a failure: stop and report it.

- [ ] Assert what changed:
  ```bash
  git status --short
  ```
  Expected, exactly: ` M TidyShot/App/AppCoordinator+Capture.swift`, ` M TidyShot/App/AppCoordinator+Recording.swift`,
  ` M TidyShot/App/AppCoordinator.swift`, ` M TidyShot/App/AppEnvironment.swift`,
  ` M TidyShot/Capture/CaptureEngine.swift`, ` M TidyShot/Capture/CaptureTarget.swift`,
  ` M TidyShot/Capture/PreviousArea.swift`, ` M TidyShot/Selection/AllInOneChoice.swift`,
  ` M TidyShot/Selection/Selection.swift`, ` M TidyShot/Selection/SelectionController.swift`,
  ` M TidyShotTests/CoordinatorCaptureTests.swift`, ` M TidyShotTests/CoordinatorRecordingTests.swift`,
  ` M TidyShotTests/CoordinatorWorldTests.swift`, ` M TidyShotTests/Support/CoordinatorWorld.swift`,
  `?? TidyShot/Capture/CaptureSource.swift`, `?? TidyShotTests/CoordinatorCaptureSourceTests.swift` and
  `?? TidyShotTests/Support/CaptureSourceFakes.swift`, and nothing else (`TidyShot.xcodeproj`, `.build/` and
  `.build-rel/` are git-ignored).

- [ ] Commit:
  ```bash
  git add TidyShot/App/AppCoordinator+Capture.swift TidyShot/App/AppCoordinator+Recording.swift TidyShot/App/AppCoordinator.swift TidyShot/App/AppEnvironment.swift TidyShot/Capture/CaptureEngine.swift TidyShot/Capture/CaptureSource.swift TidyShot/Capture/CaptureTarget.swift TidyShot/Capture/PreviousArea.swift TidyShot/Selection/AllInOneChoice.swift TidyShot/Selection/Selection.swift TidyShot/Selection/SelectionController.swift TidyShotTests/CoordinatorCaptureSourceTests.swift TidyShotTests/CoordinatorCaptureTests.swift TidyShotTests/CoordinatorRecordingTests.swift TidyShotTests/CoordinatorWorldTests.swift TidyShotTests/Support/CaptureSourceFakes.swift TidyShotTests/Support/CoordinatorWorld.swift
  git commit -m "refactor: the capture source and the selection overlay through AppEnvironment (CAPSRC), the fakes, seven capture source tests and the microphone prompt's capture step"
  ```
  Expected: `17 files changed, 599 insertions(+), 75 deletions(-)`, with `create mode 100644` for the three new files.
  No attribution lines and no session URL in the message; do not push. The report says no hand check was run (design
  section 9, check 2 is Tim's).

---

### Task 4: The marks, seams.md, the hand-check checklist, the built notes [mechanical]

**Files:**
- Modify the thirteen checklists that hold a marked line, with the count of lines marked in each: `docs/testing/coordinator-split-manual-checklist.md` (2), `phase-1-manual-checklist.md` (2), `phase-2-manual-checklist.md` (5), `phase-3-manual-checklist.md` (2), `phase-4a-manual-checklist.md` (2), `phase-5-manual-checklist.md` (3), `phase-6a-manual-checklist.md` (3), `phase-6b-manual-checklist.md` (11), `phase-7b-manual-checklist.md` (1), `phase-7c-manual-checklist.md` (10), `recording-r2-manual-checklist.md` (1), `small-tweaks-manual-checklist.md` (2) and `recording-r4-manual-checklist.md` (no new mark; recording-r4:217's earlier mark is reworded): 44 lines marked, 23 full and 21 part (catalogue `tests-capture.md` TARGET.4 and CAPSRC.6). 40 are marked for the first time and 4 carry a CT-2 in-part mark already that the script extends in place (phase-4a:119 and :120, phase-6b:118, phase-7c:187). The script edits 45 items in all. The other 23 deferred lines stay unmarked, recording-r2:653 ticked `[x]` as it is.
- Modify `docs/superpowers/notes/2026-10-30-checklist-sweep/seams.md` (design 11 items 1 to 3; its rules at :9-12, its table, its sections, the multi-seam section at :907 and the three-or-fewer section at :959).
- Create `docs/testing/capture-seams-manual-checklist.md` (design 9's two checks and section 10's eleven calls, in the form of `docs/testing/small-seams-manual-checklist.md`).
- Modify `docs/superpowers/specs/2026-11-01-tidyshot-capture-seams-design.md` (section 12 gains one paragraph: the branch's suite line and Release result).

**Interfaces:**
- Consumes: the tests Tasks 1 to 3 add, by name, because the marks name them and the marks script asserts each as `func <name>(` in `TidyShotTests/<Suite>.swift`. `CoordinatorCaptureSaveTests` (Tasks 1 and 2): T1 `capturesUnderOneTemplateTakeTheNextFreeNameAlsoAfterARelaunch()`; T2 `withAlsoCopyImageTheImageIsOnTheClipboardUntilTheUploadEndsThenTheLink()`; T3 `aWindowCaptureOnOceanIsComposedInTheFileTheClipboardAndTheUpload()`; T4 `copyOnlyPutsTheImageOnTheClipboardAndNothingElse(showNotification:)`; T5 `aSaveAndCopyImageCaptureSavesCopiesAndAsksForNoDestination(intent:)`; T6 `theNextCaptureLandsInTheNewlyStoredFolder()`; T7 `uploadAndCopyURLLeavesTheClipboardEmptyUntilTheLink()`; T8 `withNoDestinationTwoCapturesCopyTheImageAndPostOneNotice(action:)`; T9 `aFailingUploadKeepsTheFileAndFailsTheRecord(cause:alsoCopy:)`; T10 `anUploadOnlyCaptureKeepsOnlyAPendingFileUntilItsUploaded(origin:cardShows:)`; T11 `actionUploadSavesUploadsAndCopiesTheLinkUnderEitherSetting(setting:)`; T12 `aTallCaptureKeepsItsFullPixelSizeInHistory()`; T13 `annotateRunsTheActionThenOpensTheEditorOnTheNewCapture()`; T14 `areaAndFullscreenCapturesKeepThePlainImageWithTheBackgroundOn(origin:)`; T15 `aWindowCanvasFollowsTheStyle(canvas:)`; T16 `withTheBackgroundOffEveryCaptureIsPlainAtOnce()`; T17 `aComposedWindowCaptureOpensInTheEditorComposed()`; T18 `copyAndUploadOfAWindowCarryTheComposedImage()`; T19 `aWindowTooLargeForABackgroundIsSavedPlainWithOneLine()`; T20 `twoWindowCapturesAtOnceAreEachComposedInTheirOwnFile()`; T21 `anUploadOnlyCaptureThatFailsKeepsItsPendingFileUntilARetrySucceeds()`. `CoordinatorCaptureSourceTests` (Task 3; C5 and C8 are named by no line): C1 `capturePreviousAreaWithNoUsableStoredAreaIsRefusedAndCapturesNothing(stored:)`; C2 `allInOneOpensOnThePreviousAreaArmedOrAURLRectDisarmedAndEscapeStoresNothing()`; C3 `aHeldSelectionOpensOneWindowAndDropsEveryOtherURLCaptureCommandWithoutReadingOrPosting()`; C4 `capturePreviousAreaAfterCaptureTextCapturesTheEarlierImageArea()`; C6 `aScrollingAreaUnder100PointsIsRefusedAndTheNextShortcutWorks()`; C7 `windowAndFullscreenCapturesLeaveThePreviousAreaAndAScrollingDragStoresIt()`. The existing tests the marks name are read at 705bce0 and need nothing from Tasks 1 to 3; the one Task 3 edits is C8's host, `CoordinatorRecordingTests.swift`: `@Test func aSecondRecordPressWhileTheMicrophonePromptIsUpAsksNothingAndAQuitStartsNothing() async throws` (CRT:353), which recording-r2:351's mark names. The Release build and the suite are of the tree Tasks 1 to 3 leave.
- Produces: nothing a later task uses.

**Tests:** none added; the suite is unchanged. The tests' doc comments, which name their checklist lines by key and current line and say for an in-part line what stays and whose (`lines-capture.md`), are Tasks 1 to 3's. This task's marks say the same in their `by hand:` text, taken from the catalogue's merged marks.
- The marks script, in the form of the CT-3 plan's Task 4 marks script: a `MARKS` table keyed by checklist and anchor text, one match per anchor asserted (first with `grep -c -F`), every named test found (a bare suite name, as phase-7c:184 has, by its `struct`), none of the 40 first-time lines already marked, the 5 existing marks read back exactly as they stand before they are replaced, 23 full and 21 part, and the 23 deferred lines still unmarked. It prints `44 lines marked (40 for the first time, 4 extended), 1 deferred line's mark reworded`.
- The seams.md script asserts: 42 seams; 279 B lines; Lines 440, Alone 173, Completes 279; 106 lines need two or more seams; 15 seams unlock three or fewer; the first three seams complete 55 lines and the first ten 146; the rows `CAPSRC` 37 / 5 / 5 (third), `TARGET` 34 / 20 / 22 (fourth), `TMPDIRS` 30 / 7 / 8 (fifth), `CLOP` 23 / 22 / 23 (sixth), `SCREENS` 19 / 6 / 11 (seventh), `SAVEAS` 14 / 7 / 11 (eighth), `RECCHROME` 14 / 0 / 8 (ninth), `LOG` 12 / 7 / 8 (tenth), `STATUSMENU` 9 / 5 / 9, `SCROLL` 8 / 2 / 7 (17th), `SELINT` 6 / 3 / 6 (24th) as Lines / Alone / Completes, every other row unchanged; 30 new seam slots (design 11 item 2).
- Full suite, unchanged by this task: `Test run with 2380 tests in 197 suites passed`. The Release build at the end: `** BUILD SUCCEEDED **`, no `error:` or `warning:` line beyond the two tool lines the Global Constraints name. `git diff --stat main -- project.yml` prints nothing, `git diff --name-only main -- TidyShot/` lists the twelve files Tasks 1 and 3 changed.

**Commit:** `docs: capture seams marks, seams.md, the hand-check checklist and close-out`

**Steps:**

No test is added, and nothing under `TidyShot/` or `TidyShotTests/` changes. The plan indents its code blocks by two
spaces; a script or heredoc is written without that indent. Every step runs from the repository root
on `capture-seams` after Task 3's commit. The marks go on the checklist text as it is at 705bce0 (Tasks 1 to 3 change no
document), found by text; the seams.md edit works from seams.md's own lists and the design's section 11. The four
scripts are written to `/private/tmp/claude-501/ct4plan-task4/` so that each can be run twice (the marks script on its
anchors first, the seams script on a copy first). No step runs the app; the hand checks are Tim's.

- [ ] **Step 1: Check the starting point.**
  ```bash
  git status --short; git log -1 --format=%s; git diff --stat 705bce0 -- docs project.yml
  mkdir -p /private/tmp/claude-501/ct4plan-task4
  ```
  Expected: `git status --short` prints nothing; the subject is Task 3's commit message; the diff prints nothing. If the
  diff lists a file, stop and ask: the scripts below assert 705bce0's text of these files.

- [ ] **Step 2: Write the marks script and check its anchors.** One entry per marked line: the checklist, the
  catalogue key's line number (as `lines-capture.md` names it), an anchor (the start of the item's text, 40 characters
  long, checked to occur on exactly one line of its checklist at 705bce0), and the mark. A mark is the catalogue's
  merged mark (`tests-capture.md` TARGET.4 and CAPSRC.6, with `T<n>` and `CCS` spelled out as
  `CoordinatorCaptureSaveTests.<name>` and `CoordinatorCaptureSourceTests.<name>`): `(suite: Suite.test, …)` for a
  full line and `(suite, in part: Suite.test, …; by hand: <what stays>)` for a part line, whose by-hand text names the
  other seam in parentheses where there is one. phase-6b:105 is the catalogue's form without C9, which is not built.
  The script places a mark as CT-3's Task 4 did: at the end of the item's last line, wrapped at 120 columns with
  two-space continuation lines, or on new continuation lines when that line is longer than 120, with a closing
  `______` kept last. For the 4 lines that carry a CT-2 mark already and for recording-r4:217 it first cuts the existing
  note, after asserting that it reads exactly as the table says, and then places the new one, so each of the five
  carries one `(suite` note afterwards. It asserts that each anchor matches one line and that line starts an item,
  that every test a mark names is `func <name>(` in `TidyShotTests/<Suite>.swift`, that none of the 40 first-time
  lines carries a mark or an `(obsolete: ` note already, that the 23 other deferred lines stay unmarked, and that there
  are 23 full and 21 part marks in the thirteen checklists' counts.
  ```bash
  cat > /private/tmp/claude-501/ct4plan-task4/marks.py <<'EOF'
  import re
  import subprocess
  import sys
  from pathlib import Path

  ROOT = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(".")

  # (checklist, catalogue key's line, text that occurs once in the checklist at 705bce0, mark).
  # The marks are tests-capture.md TARGET.4 and CAPSRC.6 (design section 6), `T<n>` and `CCS` spelled out.
  MARKS = [
      ('coordinator-split', 36, 'Capture Area: the file, the card and the',
       '(suite, in part: CoordinatorCaptureSaveTests.aSaveAndCopyImageCaptureSavesCopiesAndAsksForNoDestination; by hand: ⌃⇧4 drag and pixel width (`CAPSRC`), card with thumbnail and `Saved` (`SCREENS`), `Reveal Last Capture` (`WORKSPACE`), the audible shutter)'),
      ('coordinator-split', 42, 'Retry Failed Uploads with no destination',
       '(suite, in part: CoordinatorCaptureSaveTests.withNoDestinationTwoCapturesCopyTheImageAndPostOneNotice, CoordinatorUploadTests.retryFailedUploadsSaysOnceWithoutCredentialsAndEnqueuesWithThem; by hand: cards saying `Upload failed` (`SCREENS`), the menu item (`STATUSMENU`))'),
      ('phase-1', 36, 'File lands in the chosen folder with the',
       '(suite: CoordinatorCaptureSaveTests.capturesUnderOneTemplateTakeTheNextFreeNameAlsoAfterARelaunch, FileNamerTests.uniqueURLAppendsCounterWhenFileExists)'),
      ('phase-1', 45, 'Choose… changes the folder and the next ',
       '(suite: CoordinatorCaptureSaveTests.theNextCaptureLandsInTheNewlyStoredFolder, SaveLocationStoreTests.storingAFolderMakesItCurrentThenTellsTheHook)'),
      ('phase-2', 25, 'After-capture action "Upload and copy UR',
       '(suite, in part: CoordinatorCaptureSaveTests.uploadAndCopyURLLeavesTheClipboardEmptyUntilTheLink, S3DestinationConfigTests.publicURLFromTemplate, ObjectKeyNamerTests.defaultTemplateIsSixRandomCharactersPlusExtension; by hand: the link in Slack (real bucket), the overlay checkmark (`SCREENS`))'),
      ('phase-2', 30, 'With "Also copy image" on: immediately a',
       '(suite: CoordinatorCaptureSaveTests.withAlsoCopyImageTheImageIsOnTheClipboardUntilTheUploadEndsThenTheLink)'),
      ('phase-2', 32, 'After-capture action "Save and copy imag',
       '(suite: CoordinatorCaptureSaveTests.aSaveAndCopyImageCaptureSavesCopiesAndAsksForNoDestination)'),
      ('phase-2', 33, 'Delete the "TidyShot S3 credentials" ite',
       "(suite, in part: CoordinatorCaptureSaveTests.withNoDestinationTwoCapturesCopyTheImageAndPostOneNotice, CoordinatorUploadTests.notConfiguredIsPostedOncePerCoordinator; by hand: Settings > Upload's empty fields (`UPLOADFORM`))"),
      ('phase-2', 48, 'Turn Wi-Fi off, capture: the file is sav',
       '(suite, in part: CoordinatorCaptureSaveTests.aFailingUploadKeepsTheFileAndFailsTheRecord, RecentCaptureFormattingTests.detailIsTheTimeTheSizeAndEachUploadState; by hand: the card drawn with Retry (`SCREENS`), Wi-Fi off for real)'),
      ('phase-3', 48, 'Forget Credentials, then capture in uplo',
       '(suite: CoordinatorCaptureSaveTests.withNoDestinationTwoCapturesCopyTheImageAndPostOneNotice, CoordinatorCaptureSaveTests.anUploadOnlyCaptureThatFailsKeepsItsPendingFileUntilARetrySucceeds, CoordinatorUploadTests.retryFailedUploadsSaysOnceWithoutCredentialsAndEnqueuesWithThem)'),
      ('phase-3', 49, '"Also copy image" on: paste gives the im',
       '(suite: CoordinatorCaptureSaveTests.withAlsoCopyImageTheImageIsOnTheClipboardUntilTheUploadEndsThenTheLink)'),
      ('phase-4a', 119, '"Upload and copy URL" with no destinatio',
       '(suite, in part: CoordinatorEditorUploadTests.withNoDestinationSaveTakesTheClipboardAndUploadIsRefused, EditorUploadPlanTests.uploadOutcomeClosesWhenEnqueued, CoordinatorCaptureSaveTests.withNoDestinationTwoCapturesCopyTheImageAndPostOneNotice; by hand: the editor staying open (`EDPLACE`))'),
      ('phase-4a', 120, '"Upload and copy URL" with "Also copy im',
       '(suite, in part: CoordinatorEditorUploadTests.anUploadAfterTheCapturesOwnClosesAtOnceAndEndsWithTheLinkCopied, CoordinatorCaptureSaveTests.withAlsoCopyImageTheImageIsOnTheClipboardUntilTheUploadEndsThenTheLink; by hand: the editor closing (`EDPLACE`))'),
      ('phase-5', 179, '"Upload only, keep no local file": nothi',
       '(suite: CoordinatorCaptureSaveTests.anUploadOnlyCaptureKeepsOnlyAPendingFileUntilItsUploaded, CoordinatorCaptureSaveTests.anUploadOnlyCaptureThatFailsKeepsItsPendingFileUntilARetrySucceeds)'),
      ('phase-5', 202, '`history.json` has the full `pixelWidth`',
       '(suite: CoordinatorCaptureSaveTests.aTallCaptureKeepsItsFullPixelSizeInHistory)'),
      ('phase-6b', 66, 'All-in-One captures behave like any othe',
       '(suite, in part: CoordinatorCaptureSaveTests.anUploadOnlyCaptureKeepsOnlyAPendingFileUntilItsUploaded; by hand: Quick Access stack and Recent Captures on screen (`SCREENS`), All-in-One building the captures (`CAPSRC`))'),
      ('phase-6b', 115, '`action=upload` with General set to `Sav',
       '(suite: CoordinatorCaptureSaveTests.actionUploadSavesUploadsAndCopiesTheLinkUnderEitherSetting, CaptureIntentTests.uploadUploadsUnderEverySetting)'),
      ('phase-6b', 116, '`action=save` under `Upload only`: saved',
       '(suite: CoordinatorCaptureSaveTests.aSaveAndCopyImageCaptureSavesCopiesAndAsksForNoDestination, CaptureIntentTests.saveIsSaveAndCopyImageUnderEverySetting)'),
      ('phase-6b', 117, '`action=copy`: the image is on the clipb',
       '(suite: CoordinatorCaptureSaveTests.copyOnlyPutsTheImageOnTheClipboardAndNothingElse, CaptureIntentTests.copyPutsTheImageOnTheClipboardOnly)'),
      ('phase-6b', 118, '`action=annotate`: the after-capture act',
       '(suite, in part: CoordinatorEditorUploadTests.annotateTheNewestCardSaveThenUploadWritesTheFileThenUploadsAndCopiesTheURL, CaptureIntentTests.annotateRunsTheAfterCaptureActionThenOpensTheEditor, .pinRunsTheAfterCaptureActionThenPins, CoordinatorCaptureSaveTests.annotateRunsTheActionThenOpensTheEditorOnTheNewCapture; by hand: the `action=pin` half (`PINS`))'),
      ('phase-7c', 179, 'Capture Window (⌃⇧2) on a normal window:',
       "(suite, in part: CoordinatorCaptureSaveTests.aWindowCaptureOnOceanIsComposedInTheFileTheClipboardAndTheUpload; by hand: the card's thumbnail (`SCREENS`))"),
      ('phase-7c', 182, 'Not included: Capture Area (⌃⇧4), Captur',
       '(suite, in part: CoordinatorCaptureSaveTests.areaAndFullscreenCapturesKeepThePlainImageWithTheBackgroundOn; by hand: which origin Previous Area, a scrolling capture and an All-in-One drag build (`CAPSRC`, `SCROLL`))'),
      ('phase-7c', 184, 'Padding 0, 160, Corner Radius 0, 40, Sha',
       '(suite: CoordinatorCaptureSaveTests.aWindowCanvasFollowsTheStyle, BackgroundLayoutTests)'),
      ('phase-7c', 185, 'A portrait window (narrower than tall) w',
       '(suite: CoordinatorCaptureSaveTests.aWindowCanvasFollowsTheStyle, BackgroundLayoutTests.portraitContentInvertsTheRatio)'),
      ('phase-7c', 186, 'The setting off: a window capture is the',
       '(suite: CoordinatorCaptureSaveTests.withTheBackgroundOffEveryCaptureIsPlainAtOnce)'),
      ('phase-7c', 187, 'Open the window capture in the editor (t',
       "(suite, in part: CoordinatorEditorTests.aComposedWindowCaptureOpensFlatWithNoBackground, CoordinatorCaptureSaveTests.aComposedWindowCaptureOpensInTheEditorComposed; by hand: the popover's switch (`BGPOP`), drawn in the window (`EDPLACE`))"),
      ('phase-7c', 188, "`action=copy`: `t 'capture-window?action",
       '(suite: CoordinatorCaptureSaveTests.copyAndUploadOfAWindowCarryTheComposedImage)'),
      ('phase-7c', 189, 'A window larger than the limit cannot be',
       '(suite, in part: CoordinatorCaptureSaveTests.aWindowTooLargeForABackgroundIsSavedPlainWithOneLine; by hand: `no bitmap could be made`, by code reading)'),
      ('phase-7c', 190, 'Two window captures in quick succession ',
       '(suite: CoordinatorCaptureSaveTests.twoWindowCapturesAtOnceAreEachComposedInTheirOwnFile)'),
      ('phase-7c', 197, "With the setting off and the editor's ba",
       '(suite: CoordinatorCaptureSaveTests.withTheBackgroundOffEveryCaptureIsPlainAtOnce, EditorBackgroundExportTests.noBackgroundExportsTheCaptureAsBefore)'),
      ('small-tweaks', 13, 'A screenshot row reads `<time> · <size>`',
       '(suite: CoordinatorCaptureSaveTests.aSaveAndCopyImageCaptureSavesCopiesAndAsksForNoDestination, RecentCaptureFormattingTests.detailIsTheTimeAndTheSize, .partsAreSeparatedByAMiddleDot, .sizeTextInUSEnglish, CoordinatorUploadTests.aStoredUploadWhoseSourceMatchesResumes)'),
      ('small-tweaks', 16, 'An upload-only capture shows a size befo',
       '(suite: CoordinatorCaptureSaveTests.anUploadOnlyCaptureKeepsOnlyAPendingFileUntilItsUploaded, CoordinatorCaptureSaveTests.anUploadOnlyCaptureThatFailsKeepsItsPendingFileUntilARetrySucceeds)'),
      ('phase-5', 78, 'Drag an area 400 pt wide and 60 pt tall:',
       '(suite, in part: CoordinatorCaptureSourceTests.aScrollingAreaUnder100PointsIsRefusedAndTheNextShortcutWorks, CoordinatorCaptureSourceTests.windowAndFullscreenCapturesLeaveThePreviousAreaAndAScrollingDragStoresIt (a 100 pt drag passes the check); by hand: the session starting on the accepted area (`SCROLL`), the drag in the overlay)'),
      ('phase-6a', 209, 'With no stored area (`defaults delete io',
       '(suite: CoordinatorCaptureSourceTests.capturePreviousAreaWithNoUsableStoredAreaIsRefusedAndCapturesNothing, PreviousAreaTests.noRectResolvesToNone, AppSettingsTests.lastAreaRectRoundTripsThroughASecondInstanceAndClears)'),
      ('phase-6a', 211, 'The rect survives a relaunch. A window c',
       "(suite, in part: CoordinatorCaptureSourceTests.windowAndFullscreenCapturesLeaveThePreviousAreaAndAScrollingDragStoresIt, CoordinatorCaptureSourceTests.aScrollingAreaUnder100PointsIsRefusedAndTheNextShortcutWorks, AppSettingsTests.lastAreaRectRoundTripsThroughASecondInstanceAndClears; by hand: a scrolling session on the accepted area (`SCROLL`), a window click becoming the scrolling area (the overlay's own, `SELINT`))"),
      ('phase-6a', 214, 'An area that leaves less than 1 point on',
       '(suite: CoordinatorCaptureSourceTests.capturePreviousAreaWithNoUsableStoredAreaIsRefusedAndCapturesNothing, PreviousAreaTests.aRectLeavingUnderOnePointOnItsDisplayIsOffScreen)'),
      ('phase-6b', 62, 'A stored area on a connected display: ⌃⇧',
       '(suite, in part: CoordinatorCaptureSourceTests.allInOneOpensOnThePreviousAreaArmedOrAURLRectDisarmedAndEscapeStoresNothing, SelectionAdjustTests.restoreKeepsARectOnItsDisplay, .restoreRefusesARectOffEveryDisplay; by hand: the rect shown selected and adjustable, and none when its display is unplugged (SelectionController.placePreselected, `SELINT`))'),
      ('phase-6b', 104, '`t all-in-one`: All-in-One with the last',
       '(suite, in part: CoordinatorCaptureSourceTests.allInOneOpensOnThePreviousAreaArmedOrAURLRectDisarmedAndEscapeStoresNothing, URLCommandHandlerTests.everyCommandReachesItsCaptureFunction, URLCommandGeometryTests.theOriginIsTheBottomLeftOfTheMainDisplay; by hand: the rect shown adjustable on the overlay (`SELINT`))'),
      ('phase-6b', 105, 'A URL-opened All-in-One needs a touch be',
       '(suite, in part: CoordinatorCaptureSourceTests.allInOneOpensOnThePreviousAreaArmedOrAURLRectDisarmedAndEscapeStoresNothing, SelectionViewArmingTests.aDisarmedRectIgnoresReturnUntilAPress, .aDisarmedRectStillNudgesAndCancels, .aDoubleClickCapturesOnlyWhenArmedBeforeIt, .aNewRectIsArmed, URLCommandHandlerTests.everyCommandReachesItsCaptureFunction; by hand: arming by a W change or the lock toggle, and Return typed in another app as the overlay appears)'),
      ('phase-6b', 127, 'A `capture-area` URL rect becomes the pr',
       '(suite, in part: CoordinatorCaptureSourceTests.windowAndFullscreenCapturesLeaveThePreviousAreaAndAScrollingDragStoresIt; by hand: a capture-scrolling rect becoming the previous area only once the stitched image is saved (`SCROLL`))'),
      ('phase-6b', 159, 'While a selection is open (⌃⇧4, not rele',
       '(suite, in part: CoordinatorCaptureSourceTests.aHeldSelectionOpensOneWindowAndDropsEveryOtherURLCaptureCommandWithoutReadingOrPosting, URLCommandHandlerTests.captureCommandsAreDroppedWhileCapturesAreRefused, .theLogSaysWhyACaptureCommandWasDropped; by hand: while a self-timer counts (`STAGE`), and during a scrolling session before and after Start (`SCROLL`))'),
      ('phase-6b', 160, '`for i in 1 2 3; do t capture-window; do',
       '(suite: CoordinatorCaptureSourceTests.aHeldSelectionOpensOneWindowAndDropsEveryOtherURLCaptureCommandWithoutReadingOrPosting, URLCommandHandlerTests.captureCommandsAreDroppedWhileCapturesAreRefused)'),
      ('phase-7b', 81, '⌃⇧6 after a Capture Text captures the pr',
       '(suite: CoordinatorCaptureSourceTests.capturePreviousAreaAfterCaptureTextCapturesTheEarlierImageArea)'),
      ('recording-r2', 351, 'With the prompt up: a second Record pres',
       "(suite, in part: CoordinatorRecordingTests.aSecondRecordPressWhileTheMicrophonePromptIsUpAsksNothingAndAQuitStartsNothing, URLCommandHandlerTests.theLogSaysWhyACaptureCommandWasDropped; by hand: the status menu's capture items shown disabled (`STATUSMENU`), and the recording that starts as usual after the answer (`TMPDIRS`, `RECCHROME`))"),
  ]

  # The one deferred line that already carries a mark, which is reworded with no test (design 6; tests-capture.md CAPSRC.1).
  REWORDED = ('recording-r4', 217, 'The record shortcut during the settle de',
              "(suite, the rule: CoordinatorRecordingTests.recordingProceedsOnlyWhenStartedNotQuittingAndNotCancelled; by hand: the log line, in private `record()` past the capture lock (`TMPDIRS`, and the hand-off's `NSScreen` read, +Recording.swift:496, which only `STAGE`'s screen lookup names))")

  # The marks the five lines carry before this task, as the checklists read now (joined with single spaces).
  EXISTING = {
      ('phase-4a', 119): "(suite, in part: CoordinatorEditorUploadTests.withNoDestinationSaveTakesTheClipboardAndUploadIsRefused, EditorUploadPlanTests.uploadOutcomeClosesWhenEnqueued; by hand: the editor staying open (`EDPLACE`); the capture's own clipboard copy and owner are set up as `AppCoordinator+Save.swift:32-34` and `:57-67` leave them with no destination, and no test drives that step today (`TARGET`))",
      ('phase-4a', 120): "(suite, in part: CoordinatorEditorUploadTests.anUploadAfterTheCapturesOwnClosesAtOnceAndEndsWithTheLinkCopied; by hand: the editor closing (`EDPLACE`); the capture's own clipboard copy and owner are set up as `AppCoordinator+Save.swift:30-31` and `:57-67` leave them, and no test drives that step today (`TARGET`))",
      ('phase-6b', 118): '(suite, in part: CoordinatorEditorUploadTests.annotateTheNewestCardSaveThenUploadWritesTheFileThenUploadsAndCopiesTheURL, CaptureIntentTests.annotateRunsTheAfterCaptureActionThenOpensTheEditor, .pinRunsTheAfterCaptureActionThenPins; by hand: reaching `save(_:intent:)` (`TARGET`) and the `action=pin` half (`PINS`); the test pins the editor opening on the new capture and its card closing)',
      ('phase-7c', 187): "(suite, in part: CoordinatorEditorTests.aComposedWindowCaptureOpensFlatWithNoBackground; by hand: producing the window capture (`TARGET`), and the popover's switch as its binding shows it (`BGPOP`) and drawn in the window (`EDPLACE`))",
      ('recording-r4', 217): '(suite, the rule: CoordinatorRecordingTests.recordingProceedsOnlyWhenStartedNotQuittingAndNotCancelled; by hand: the log line, in private record() past the capture lock (`TMPDIRS`, `CAPSRC`))',
  }
  EXTENDED = {("phase-4a", 119), ("phase-4a", 120), ("phase-6b", 118), ("phase-7c", 187)}

  # The 23 deferred lines that stay unmarked, before and after (recording-r2:653 is ticked [x] and stays so).
  DEFERRED = [
      ('phase-1', 39, 'Cancelling the folder chooser leaves the'),
      ('phase-7c', 117, 'A window capture with the setting on and'),
      ('phase-5', 182, 'Nothing is written or uploaded before Do'),
      ('phase-6b', 75, 'While the countdown runs, ⌃⇧4, the Self-'),
      ('phase-6b', 77, '`3 seconds` and `10 seconds` in Settings'),
      ('phase-6b', 79, 'A self-timer area becomes the previous a'),
      ('phase-7b', 96, 'Not covered: Capture Scrolling (⌃⇧5) and'),
      ('recording-r1', 102, 'Stop each way, one recording each, which'),
      ('recording-r1', 105, 'An area smaller than 32 x 32 pt posts `S'),
      ('recording-r1', 122, 'A window recording with Hide desktop ico'),
      ('recording-r1', 124, 'The covers are gone after Stop, after Ca'),
      ('recording-r1', 196, 'Closing the window during the count-in, '),
      ('recording-r2', 231, 'Two GIF recordings converting at once. R'),
      ('recording-r2', 236, '`Stop Making GIF` with one conversion do'),
      ('recording-r2', 238, 'Quit during a conversion. Start a 60 s G'),
      ('recording-r2', 390, 'A GIF save that ends during a second rec'),
      ('recording-r2', 397, 'The same with the GIF saved during the s'),
      ('recording-r2', 402, 'The same with an upload that finishes du'),
      ('recording-r2', 407, 'Quit during the second recording of the '),
      ('recording-r2', 409, 'A quick quit, where nothing else holds t'),
      ('recording-r2', 605, '1. Settings are read at the start: the h'),
      ('recording-r2', 653, 'E. A post-Stop notice during a later rec'),
      ('recording-r3', 276, 'A failed content read: not forceable by '),
  ]

  PER_FILE = {"coordinator-split": 2, "phase-1": 2, "phase-2": 5, "phase-3": 2, "phase-4a": 2, "phase-5": 3,
              "phase-6a": 3, "phase-6b": 11, "phase-7b": 1, "phase-7c": 10, "recording-r2": 1, "small-tweaks": 2,
              "recording-r4": 0}
  WIDTH = 120


  def tests_named(mark):
      """Every (Suite, test) the mark names, the `.test` shorthand expanded to the suite before it; a bare suite is (Suite, None)."""
      names, suite = [], None
      for m in re.finditer(r"(?:(?<![\w.])([A-Z][A-Za-z0-9]*Tests)(?:\.([a-z][A-Za-z0-9]*)\b)?)|(?:, \.([a-z][A-Za-z0-9]*)\b)", mark):
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
      assert lines[start].startswith(("- [ ] ", "- [x] ")), f"{where} is not an item's first line"
      end = start + 1
      while end < len(lines) and lines[end].startswith("  ") and not lines[end].lstrip().startswith("- ["):
          end += 1
      return start, end


  def checklist_path(checklist):
      return ROOT / "docs" / "testing" / f"{checklist}-manual-checklist.md"


  if len(sys.argv) > 2 and sys.argv[2] == "anchors":
      # `grep -c -F` of each anchor in its checklist: every line must print 1.
      bad = 0
      every = [(m[0], m[1], m[2]) for m in MARKS] + [REWORDED[:3]] + DEFERRED
      for checklist, line, anchor in every:
          count = int(subprocess.run(["grep", "-c", "-F", "--", anchor, str(checklist_path(checklist))],
                                     capture_output=True, text=True).stdout)
          bad += count != 1
          print(f"{checklist}:{line} {count}")
      assert bad == 0, f"{bad} anchors do not occur once"
      print(f"{len(every)} anchors, each on one line")
      sys.exit(0)

  assert len(MARKS) == 44 and len({(m[0], m[1]) for m in MARKS}) == 44, len(MARKS)
  assert sum(1 for m in MARKS if m[3].startswith("(suite: ")) == 23, "full marks"
  assert sum(1 for m in MARKS if m[3].startswith("(suite, in part: ")) == 21, "part marks"
  assert all(m[3].startswith(("(suite: ", "(suite, in part: ")) and m[3].endswith(")") for m in MARKS)
  assert all(("; by hand: " in m[3]) == m[3].startswith("(suite, in part: ") for m in MARKS), "a part mark's by-hand text"
  assert {(m[0], m[1]) for m in MARKS} & set(EXISTING) == EXTENDED and (REWORDED[0], REWORDED[1]) in EXISTING
  assert REWORDED[3].startswith("(suite, the rule: ") and "; by hand: " in REWORDED[3]
  assert len(DEFERRED) == 23
  for checklist, count in PER_FILE.items():
      assert sum(1 for m in MARKS if m[0] == checklist) == count, checklist

  missing = []
  for _, _, _, mark in MARKS + [REWORDED]:
      for suite, name in tests_named(mark):
          source = ROOT / "TidyShotTests" / f"{suite}.swift"
          text = source.read_text() if source.exists() else ""
          if not source.exists() or (name and f"func {name}(" not in text) or (not name and f"struct {suite}" not in text):
              missing.append(f"{suite}.{name}")
  assert not missing, f"tests not found: {sorted(set(missing))}"

  marked = 0
  for checklist in sorted(set(PER_FILE) | {d[0] for d in DEFERRED}):
      path = checklist_path(checklist)
      lines = path.read_text().split("\n")
      spans = []
      todo = [(m[1], m[2], m[3]) for m in MARKS if m[0] == checklist]
      if checklist == REWORDED[0]:
          todo.append(REWORDED[1:])
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
      if spans:
          path.write_text("\n".join(lines))
  assert marked == 45
  print("44 lines marked (40 for the first time, 4 extended), 1 deferred line's mark reworded")
  EOF
  python3 /private/tmp/claude-501/ct4plan-task4/marks.py . anchors | tail -2
  ```
  Expected: the last two lines are `recording-r3:276 1` and `68 anchors, each on one line` (every line of the full
  output ends in ` 1`). A `tests not found:` assertion in Step 3 means a task before this one left a test out or
  named it otherwise; stop and report it rather than editing the mark.

- [ ] **Step 3: Mark the 44 lines.**
  ```bash
  python3 /private/tmp/claude-501/ct4plan-task4/marks.py .
  ```
  Expected: `44 lines marked (40 for the first time, 4 extended), 1 deferred line's mark reworded`.

- [ ] **Step 4: Check the marks.**
  ```bash
  git diff --numstat -- docs/testing
  ```
  Expected, exactly (added, deleted, file):
  ```
  6	0	docs/testing/coordinator-split-manual-checklist.md
  5	1	docs/testing/phase-1-manual-checklist.md
  11	0	docs/testing/phase-2-manual-checklist.md
  5	1	docs/testing/phase-3-manual-checklist.md
  6	6	docs/testing/phase-4a-manual-checklist.md
  6	0	docs/testing/phase-5-manual-checklist.md
  9	0	docs/testing/phase-6a-manual-checklist.md
  36	4	docs/testing/phase-6b-manual-checklist.md
  2	1	docs/testing/phase-7b-manual-checklist.md
  18	4	docs/testing/phase-7c-manual-checklist.md
  4	1	docs/testing/recording-r2-manual-checklist.md
  2	1	docs/testing/recording-r4-manual-checklist.md
  6	1	docs/testing/small-tweaks-manual-checklist.md
  ```
  (13 files, 116 added and 20 deleted.) The script asserted that every continuation line it wrote is at most 120
  characters. The deletions are the item lines a mark was appended to and the five existing marks rewritten. Read
  `git diff -- docs/testing/phase-4a-manual-checklist.md`, `docs/testing/phase-6b-manual-checklist.md`,
  `docs/testing/phase-7c-manual-checklist.md` and `docs/testing/recording-r4-manual-checklist.md` and confirm that no
  line outside a marked item changed, that phase-4a:119 and :120, phase-6b:118, phase-7c:187 and recording-r4:217 each
  carry one note, that none of the first four names `TARGET` in its by-hand text any more, and that recording-r4:217's
  note still reads `(suite, the rule: …` and now names the hand-off's `NSScreen` read.

- [ ] **Step 5: Edit seams.md as the design's section 11 says.** The script reads seams.md's table and its 42 seam
  sections (each line list, with its "(also …)" note and free-text notes), checks that they reproduce the table's
  Lines, Alone and Completes (410, 182, 279), and then: (item 1) gives each of the 68 lines its verdict
  (`; CT-4: full`, `; CT-4: in part`, `; CT-4: deferred`) under its seam (`TARGET` or `CAPSRC`), rewords the Shape and
  Live lines of sections 3 and 4 to what was built (design 2.1 and 2.2), adds the note "needs `TMPDIRS` first (CT-4)"
  to recording-r1:105, a `CT-4` note bullet to each of the two sections and one sentence to the header's Source
  paragraph; (item 2) adds the 30 joins (the 14 part-line joins `SCREENS` 5, `STATUSMENU` 1, `CAPSRC` 3, `SCROLL` 2,
  `SELINT` 2 and `TMPDIRS` recording-r2:351, and the 16 deferred recording lines under `TMPDIRS`), each noted "also
  `<home seam>`, in part since CT-4" (or "deferred in CT-4") under the row it joins; (item 3) recounts by seams.md's
  rules (:9-12), sorts the table and the sections by Lines with equal Lines in the old table order, renumbers them,
  regenerates the "(also …)" note of the 27 lines whose seams changed, rewrites the summary's counts, and regenerates
  the multi-seam and three-or-fewer sections in their existing form (each line's text cut at 39 and 47 characters,
  which reproduces all 97 multi-seam entries and every three-or-fewer entry as they are; the script asserts both). The
  design's section 11 gives the rows and positions the script asserts; the tie rule is CT-3's (sort by Lines, then
  old table position), which reproduces them. Run it on a copy first.
  ```bash
  cat > /private/tmp/claude-501/ct4plan-task4/seams.py <<'EOF'
  import re
  import sys
  from pathlib import Path

  ROOT = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(".")
  PATH = ROOT / "docs" / "superpowers" / "notes" / "2026-10-30-checklist-sweep" / "seams.md"

  # Design section 11 and lines-capture.md: each of the 68 lines, its seam and its CT-4 verdict.
  VERDICT = {}
  for seam, verdict, keys in [
      ("TARGET", "full", """phase-1:36 phase-1:45 phase-2:30 phase-2:32 phase-3:48 phase-3:49 phase-5:179 phase-5:202
            phase-6b:115 phase-6b:116 phase-6b:117 phase-7c:184 phase-7c:185 phase-7c:186 phase-7c:188
            phase-7c:190 phase-7c:197 small-tweaks:13 small-tweaks:16"""),
      ("TARGET", "in part", """coordinator-split:36 coordinator-split:42 phase-2:25 phase-2:33 phase-2:48 phase-4a:119 phase-4a:120
            phase-6b:66 phase-6b:118 phase-7c:179 phase-7c:182 phase-7c:187 phase-7c:189"""),
      ("TARGET", "deferred", """phase-1:39 phase-7c:117"""),
      ("CAPSRC", "full", """phase-6a:209 phase-6a:214 phase-6b:160 phase-7b:81"""),
      ("CAPSRC", "in part", """phase-5:78 phase-6a:211 phase-6b:62 phase-6b:104 phase-6b:105 phase-6b:127 phase-6b:159
            recording-r2:351"""),
      ("CAPSRC", "deferred", """phase-5:182 phase-6b:75 phase-6b:77 phase-6b:79 phase-7b:96 recording-r1:102 recording-r1:105
            recording-r1:122 recording-r1:124 recording-r1:196 recording-r2:231 recording-r2:236
            recording-r2:238 recording-r2:390 recording-r2:397 recording-r2:402 recording-r2:407
            recording-r2:409 recording-r2:605 recording-r2:653 recording-r3:276 recording-r4:217"""),
  ]:
      for k in keys.split():
          VERDICT[k] = (seam, verdict)
  assert len(VERDICT) == 68, len(VERDICT)
  assert sum(1 for v in VERDICT.values() if v[1] == "full") == 23
  assert sum(1 for v in VERDICT.values() if v[1] == "in part") == 21
  assert sum(1 for v in VERDICT.values() if v[1] == "deferred") == 24

  # Item 2: each part line joins the rows its mark names that do not list it yet (14 slots), and each deferred
  # recording line that is not under TMPDIRS yet joins it (16 slots, call 8).
  DEFERRED_TO_TMPDIRS = """recording-r1:102 recording-r1:105 recording-r1:122 recording-r1:124 recording-r1:196 recording-r2:231
      recording-r2:236 recording-r2:238 recording-r2:390 recording-r2:397 recording-r2:402 recording-r2:407 recording-r2:409
      recording-r2:605 recording-r2:653 recording-r3:276""".split()
  JOINS = {
      "SCREENS": ["coordinator-split:42", "phase-2:25", "phase-2:48", "phase-6b:66", "phase-7c:179"],
      "STATUSMENU": ["coordinator-split:42"],
      "CAPSRC": ["coordinator-split:36", "phase-6b:66", "phase-7c:182"],
      "SCROLL": ["phase-6b:127", "phase-7c:182"],
      "SELINT": ["phase-6a:211", "phase-6b:104"],
      "TMPDIRS": ["recording-r2:351"] + DEFERRED_TO_TMPDIRS,
  }
  # A line's own note after its CT-4 verdict is added (design section 11 item 1).
  EXTRA_NOTE = {"recording-r1:105": "; needs `TMPDIRS` first (CT-4)"}

  BASE = "`docs/superpowers/specs/2026-11-01-tidyshot-capture-seams-design.md`"
  SECTION_NOTES = {
      "TARGET": ("- CT-4: Built on `capture-seams` (" + BASE + "). Each line below carries its CT-4 verdict; a line "
                 "marked in part also sits under every other seam its mark names, noted there as \"also `TARGET`, in "
                 "part since CT-4\"."),
      "CAPSRC": ("- CT-4: Built on `capture-seams` (" + BASE + "). Each line below carries its CT-4 verdict; a line "
                 "marked in part or deferred also sits under every other seam its mark names, and a deferred recording "
                 "line under `TMPDIRS`, its first blocker, noted there as \"also `CAPSRC`, in part since CT-4\" or "
                 "\"deferred in CT-4\"."),
  }
  # Item 1: the Shape and Live lines of sections 3 and 4 say what was built (design 2.1 and 2.2).
  BULLETS_OLD = {
      "TARGET": [
          ("- Shape: A value type that replaces the SC* objects: display id and frame, optional area rect, window id and "
           "frame. Cheaper form for the save lines alone: an internal `save(image:scale:source:intent:)` over a small "
           "value (displayID, areaRect, isWindow) that `save(_:intent:)` forwards to.",
           "- Shape: Built in CT-4 (design 2.1), in the cheaper save-only form: a `nonisolated` value `CaptureOrigin` (the "
           "kind, with an area's rect, and the display id) and an internal `save(_:from:intent:)` over the image and that "
           "origin, which `save(_:intent:)` forwards to. No `AppEnvironment` member and no fake. A value target the engine "
           "resolves back by id was rejected: it would add a second content read per capture or state on a stateless "
           "engine, and edit every maker of a target; that is `CAPSRC`'s diff."),
          ("- Live: `CaptureEngine` resolves the value back to the `SCDisplay`/`SCWindow` by id in the content it already "
           "read when it captures; `save` keeps working on the three fields it reads now.",
           "- Live: `CaptureTarget.origin`, built from the live target in the forwarder; `CaptureEngine.capture`, "
           "`CaptureTarget`, `CaptureResult` and the seven callers of `save(_:intent:)` are untouched."),
      ],
      "CAPSRC": [
          ("- Shape: Two protocols on `AppEnvironment`: a content source whose `shareableContent()` returns value "
           "displays and windows and whose `capture(target:)` returns an image, and a selector whose "
           "`select(mode:content:freeze:)` returns a value `Selection`.",
           "- Shape: Built in CT-4 (design 2.2): the ScreenCaptureKit objects become values that carry the object as a "
           "`live` handle (`CaptureDisplay`, `CaptureWindow`, `ScreenContent`), and two protocols go on "
           "`AppEnvironment`: `captureSource: any CaptureSource` (the content read, a capture, the card windows by "
           "number, the display under the pointer, the grant) and `selector: any CaptureSelecting` (`select`, "
           "`selectAllInOne`, `frozenCapture`, `overlayWindows`, `dismiss`). Resolving a value back by id instead of the "
           "handle was rejected: it would add a second content read per capture."),
          ("- Live: `CaptureEngine` and `SelectionController` conform; the live content source wraps `SCShareableContent` "
           "and keeps the SC objects behind the ids.",
           "- Live: `CaptureEngine` and `SelectionController` conform; `AppEnvironment.live()` builds one `CaptureEngine()` "
           "for the source and the selector, and the selector's card windows come from the Quick Access controller. The "
           "coordinator keeps its own `engine` for the scrolling session and the recording driver."),
      ],
  }
  SOURCE_OLD = ("The table, the counts and the last sections were redone again by the same rules, with seams of equal "
                "Lines kept in their old table order.")
  SOURCE_NEW = (SOURCE_OLD + " CT-4 (" + BASE + ", section 11) then built `TARGET` and `CAPSRC`: each of their 68 lines "
                "carries its CT-4 verdict (23 full, 21 in part, 24 deferred), and the part lines also sit under the other "
                "seams their marks name (14 new seam slots) and the deferred recording lines under `TMPDIRS`, their first "
                "blocker (16 more). The table, the counts and the last sections were redone once more by the same rules.")
  SUMMARY = [
      ("- 182 lines need one seam; 97 need two or more (listed in their own section).",
       "- 173 lines need one seam; 106 need two or more (listed in their own section)."),
      ("Lines sums to 410 (182 one-seam lines, plus 228 seam slots held by the 97 lines that need two or more); Alone sums "
       "to 182; Completes sums to 279, every B line once. Read down the Completes column for a running total: the first "
       "three seams cover 78 lines, the first ten 150.",
       "Lines sums to 440 (173 one-seam lines, plus 267 seam slots held by the 106 lines that need two or more); Alone sums "
       "to 173; Completes sums to 279, every B line once. Read down the Completes column for a running total: the first "
       "three seams cover 55 lines, the first ten 146."),
  ]
  # Design 11 item 3, Lines / Alone / Completes, and the places it gives.
  ROWS = {"CAPSRC": (37, 5, 5), "TARGET": (34, 20, 22), "TMPDIRS": (30, 7, 8), "CLOP": (23, 22, 23),
          "SCREENS": (19, 6, 11), "SAVEAS": (14, 7, 11), "RECCHROME": (14, 0, 8), "STATUSMENU": (9, 5, 9),
          "SCROLL": (8, 2, 7), "SELINT": (6, 3, 6), "LOG": (12, 7, 8)}
  PLACES = {"EDITOR": 1, "EDPLACE": 2, "CAPSRC": 3, "TARGET": 4, "TMPDIRS": 5, "CLOP": 6, "SCREENS": 7, "SAVEAS": 8,
            "RECCHROME": 9, "LOG": 10, "SCROLL": 17, "SELINT": 24}

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
  for old in [s[0] for s in SUMMARY] + [SOURCE_OLD] + [b[0] for v in BULLETS_OLD.values() for b in v]:
      assert text.count(old) == 1, f"seams.md is not as at 705bce0: {old[:60]}"

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
  assert [sum(v[i] for v in before.values()) for i in range(3)] == [410, 182, 279]
  for k, (seam, _) in VERDICT.items():
      assert k in seams[seam], (seam, k)
  assert sum(len(seams[s]) for s in ("TARGET", "CAPSRC")) == 68
  assert all(sum(1 for k in seams[s] if VERDICT[k][0] == s) == len(seams[s]) for s in ("TARGET", "CAPSRC"))

  # Item 2: the joins.
  slots = 0
  for seam, keys in JOINS.items():
      for k in keys:
          assert VERDICT[k][1] in ("in part", "deferred") and k not in seams[seam], (seam, k)
          seams[seam].append(k)
          slots += 1
      seams[seam].sort(key=order_key)
  assert slots == 30, slots
  assert sum(len(v) for s, v in JOINS.items() if s != "TMPDIRS") + 1 == 14 and len(DEFERRED_TO_TMPDIRS) == 16
  changed = {k for keys in JOINS.values() for k in keys}
  assert len(changed) == 27, len(changed)
  for seam in entries:
      for k in changed & set(entries[seam]):
          assert "since CT-" not in entries[seam][k][1] and "in CT-" not in entries[seam][k][1], (seam, k)

  # Item 3: the counts, the table sorted by Lines, equal Lines in the old table order.
  first, _ = counts(seams, list(seams))
  order = sorted(seams, key=lambda s: (-first[s][0], old_order.index(s)))
  after, need = counts(seams, order)
  assert len(order) == 42 and len(need) == 279
  assert [sum(v[i] for v in after.values()) for i in range(3)] == [440, 173, 279]
  assert sum(1 for k in need if len(need[k]) > 1) == 106
  assert sum(1 for s in order if after[s][0] <= 3) == 15
  running = [sum(after[s][2] for s in order[:n]) for n in (3, 10)]
  assert running == [55, 146], running
  for seam, row in ROWS.items():
      assert after[seam] == row, (seam, after[seam], row)
  for seam, place in PLACES.items():
      assert order.index(seam) + 1 == place, (seam, order.index(seam) + 1)
  assert all(after[s] == before[s] for s in before if s not in ROWS), "only design 11's rows change"

  # The text each line shows, from its first entry.
  shown = {}
  for seam in entries:
      for k, (t, _, _) in entries[seam].items():
          shown.setdefault(k, t)


  def also(k, seam):
      """`(also …)` for a changed line under `seam`: the other seams in table order; the line's home seam (CT-4) is
      named first with how it stands when `seam` is a seam the line joined."""
      others = [s for s in order if s in need[k] and s != seam]
      home, verdict = VERDICT[k]
      if seam != home and seam in {s for s, ks in JOINS.items() if k in ks}:
          note = "deferred in CT-4" if verdict == "deferred" else "in part since CT-4"
          rest = [f"`{s}`" for s in others if s != home]
          return f" (also `{home}`, {note}" + ("; and " + ", ".join(rest) if rest else "") + ")"
      return " (also " + ", ".join(f"`{s}`" for s in others) + ")"


  def entry(seam, k):
      t, also_text, notes = entries.get(seam, {}).get(k, (shown[k], "", ""))
      if k in changed:
          also_text = also(k, seam)
      if VERDICT.get(k, (None,))[0] == seam:
          notes += EXTRA_NOTE.get(k, "")
          notes += f"; CT-4: {VERDICT[k][1]}"
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
  assert len(old_multi) == 97
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
  assert len(old_three) == 15
  for name, s, line in old_three:
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
  C=/private/tmp/claude-501/ct4plan-task4/copy
  rm -rf "$C" && mkdir -p "$C/docs/superpowers/notes/2026-10-30-checklist-sweep"
  cp docs/superpowers/notes/2026-10-30-checklist-sweep/seams.md "$C/docs/superpowers/notes/2026-10-30-checklist-sweep/"
  python3 /private/tmp/claude-501/ct4plan-task4/seams.py "$C"
  ```
  Expected: `seams.md: 42 seams, Lines 440, Alone 173, Completes 279, 30 new slots, 106 lines need two or more seams, 15 seams unlock three or fewer`.
  Then on the repository and with the checks:
  ```bash
  python3 /private/tmp/claude-501/ct4plan-task4/seams.py .
  git diff --stat -- docs/superpowers/notes/2026-10-30-checklist-sweep/seams.md | tail -1
  grep -c "; CT-4: " docs/superpowers/notes/2026-10-30-checklist-sweep/seams.md
  grep -n "^### [0-9]*\. .*(\`\(CAPSRC\|TARGET\|TMPDIRS\|CLOP\|SCREENS\|SAVEAS\|RECCHROME\|LOG\|STATUSMENU\|SCROLL\|SELINT\)\`)" docs/superpowers/notes/2026-10-30-checklist-sweep/seams.md
  ```
  Expected: the same `seams.md: 42 seams, …` line; ` 1 file changed, 274 insertions(+), 235 deletions(-)`; `68`; and
  ```
  196:### 3. Capture source (engine and selector) (`CAPSRC`): 37 lines, 5 alone
  245:### 4. Value capture target (`TARGET`): 34 lines, 20 alone
  290:### 5. tmp/ directory statics (`TMPDIRS`): 30 lines, 7 alone
  332:### 6. Clop optimiser and running check (`CLOP`): 23 lines, 22 alone
  366:### 7. Screen list for the card stack and pins (`SCREENS`): 19 lines, 6 alone
  395:### 8. Card Save As panel (`SAVEAS`): 14 lines, 7 alone
  420:### 9. Recording chrome factory (`RECCHROME`): 14 lines, 0 alone
  445:### 10. RecordingLog sink (`LOG`): 12 lines, 7 alone
  569:### 16. Status menu model (`STATUSMENU`): 9 lines, 5 alone
  588:### 17. Scrolling capture behind a protocol (`SCROLL`): 8 lines, 2 alone
  704:### 24. Selection overlay internals (`SELINT`): 6 lines, 3 alone
  ```
  Read the diff of the multi-seam section: `CAPSRC` + `RECCHROME` (8 lines) becomes `CAPSRC` + `TMPDIRS` + `RECCHROME`
  (8), `TARGET` + `SCREENS` is new with 3 (phase-2:25, phase-2:48, phase-7c:179), `CAPSRC` + `SELINT` goes from 1 line
  to 2, `SAVEAS` + `SCREENS` is now written `SCREENS` + `SAVEAS` (3, table order), and the section's count reads 106
  lines. The three-or-fewer section does not change.

- [ ] **Step 6: Write the hand-check checklist.** Create `docs/testing/capture-seams-manual-checklist.md`, in the form
  of `docs/testing/small-seams-manual-checklist.md` (when to run it, the checks, the design's calls and the plan's
  decisions to confirm or overrule, observations), with the design's section 9 checks as 1 and 2 and section 10's
  eleven calls:
  ```bash
  cat > docs/testing/capture-seams-manual-checklist.md <<'EOF'
  # Capture seams manual checklist

  Run after the capture seams phase (`docs/superpowers/specs/2026-11-01-tidyshot-capture-seams-design.md`), and after any
  later change to `CaptureTarget.origin`, `CaptureOrigin`, `AppCoordinator.save(_:from:intent:)`, `CaptureDisplay`,
  `CaptureWindow`, `ScreenContent`, or `AppEnvironment.captureSource` and `selector` and their live values. The suite now
  drives the save path with an origin it builds (`CaptureSamples`) and the content read and the selection through
  `world.source` and `world.selector`, and the coordinator-split, phase-1 to phase-7c, recording-r2, recording-r4 and
  small-tweaks checklists mark 44 more lines `(suite …)`, 23 in full and 21 in part. The live values never run in the
  suite (`AppEnvironment.live()` builds `AppSettings.shared`, the Keychain store and the notifier), so what is left here
  is the real capture and the real overlay: that each does what it did before the seams.

  ## Checks

  - [ ] 1. The real capture of each kind. With `Save and copy image`, ⌃⇧3, ⌃⇧4 (drag an area) and ⌃⇧2 (click a window)
    each leave one PNG in the save folder at the right size (`sips -g pixelWidth -g pixelHeight`: the display, the area
    or the window times the display scale), post `Screenshot saved`, put the image on the clipboard and show a card on
    the capture's display. With `Add background to window captures` on, the window capture is composed and the other two
    are not. ⌃⇧6 recaptures the area. `t 'capture-window?action=copy'` and a click on a window: the image only, and
    `Image copied`. A pin of the newest area capture opens over it.
  - [ ] 2. The real selection. ⌃⇧1, ⌃⇧4 and ⌃⇧5 open the overlay on every display with the cards left out of the
    picture; Escape captures nothing; a window click in All-in-One captures that window; a scrolling capture starts its
    session; Record Screen's overlay and the recording start as before. With Screen Recording turned off for TidyShot (in
    System Settings, and back on after), a capture shows the permission window.

  ## The design's calls, to confirm or overrule

  The design lists them in section 10. Write `confirm` or `overrule` and why; an overrule goes in its built notes.
  - [ ] 1. `CAPSRC` is built in this phase, as the second task, although by its own lines it is not worth its diff (4 full
    and 8 part lines of 34). Overrule to defer it: its tests, fakes, marks and seams.md joins then go, and `TARGET`
    stands alone at 2373 tests in 196 suites. ______
  - [ ] 2. `TARGET` is the internal `save(_:from:intent:)` over `CaptureOrigin`, not a value target the engine resolves
    by id, nor a `CaptureResult` carrying the origin. ______
  - [ ] 3. C9 (a width change or the lock toggle arming a disarmed rect, in `SelectionViewArmingTests`) is not built;
    phase-6b:105 keeps arming by a width change or the lock toggle by hand. ______
  - [ ] 4. `CaptureDisplay` and `CaptureWindow` carry the ScreenCaptureKit object as a `live` handle. The cost is
    `CaptureError.notListed` and one guard in `runScrolling`, both unreachable in the app. ______
  - [ ] 5. C4 runs the real `TextRecognizer`; the first request after a restart can take about 24 s, inside the
    one-minute limit. The alternative is deferring phase-7b:81 to `COPYTEXT`. ______
  - [ ] 6. recording-r2:351 is in part, not deferred: C8 adds its "captures are blocked while the prompt is up" clause to
    the existing held-prompt test. ______
  - [ ] 7. recording-r1:105 needs `TMPDIRS`, not nothing: both halves of the line come after `recordingCanStart`. ______
  - [ ] 8. The 16 deferred recording lines join `TMPDIRS` in seams.md, noted "also `TMPDIRS`, deferred in CT-4". Not
    joining leaves `TMPDIRS` at 14 lines and understates what it unlocks. ______
  - [ ] 9. phase-2:32 and small-tweaks:13 name a `Saved` word the row no longer shows; their text stays and the marks
    cover what is still true. ______
  - [ ] 10. coordinator-split:36, phase-6b:66 and phase-7c:182 keep naming `CAPSRC` for the origin each entry point
    builds, although `CAPSRC` landed here: no test drives those entry points into a save. ______
  - [ ] 11. T10's `cardShows` leg, T9's `cause` and T21 go beyond the twenty tests the first review asked for. ______

  ## The plan's decisions, to confirm or overrule

  The plan lists them at its end (`docs/superpowers/plans/2026-11-01-capture-seams.md`, Plan decisions). None changes
  what a user could see, and none changes a number the design gives:
  - [ ] The marks and seams.md follow the design's section 11 and the catalogue's mark tables; where the plan words a mark
    or an entry otherwise (the four extended marks take the catalogue's wording whole, phase-6b:105 is the form without
    C9), the decision says so. ______

  ## Observations
  Write into the design's built notes: anything above that failed, and each call and decision confirmed or overruled.
  EOF
  python3 -c 'import sys; print([n for n, l in enumerate(open(sys.argv[1]), 1) if len(l.rstrip("\n")) > 120])' docs/testing/capture-seams-manual-checklist.md
  ```
  Expected: `[]` (no line over 120 characters).

- [ ] **Step 7: Run the full suite and the Release build.**
  ```bash
  xcodegen generate && xcodebuild test -project TidyShot.xcodeproj -scheme TidyShot -destination 'platform=macOS' -derivedDataPath .build 2>&1 | grep -E "Test run with|error:|TEST"
  ```
  Expected: `Test run with 2380 tests in 197 suites passed` and `** TEST SUCCEEDED **`, with only the known noise
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
  git diff --stat main -- project.yml; git diff --name-only main -- TidyShot/; git diff --name-only main -- TidyShotTests/
  ```
  Expected: nothing for `project.yml`, then exactly
  ```
  TidyShot/App/AppCoordinator+Capture.swift
  TidyShot/App/AppCoordinator+Recording.swift
  TidyShot/App/AppCoordinator+Save.swift
  TidyShot/App/AppCoordinator.swift
  TidyShot/App/AppEnvironment.swift
  TidyShot/Capture/CaptureEngine.swift
  TidyShot/Capture/CaptureSource.swift
  TidyShot/Capture/CaptureTarget.swift
  TidyShot/Capture/PreviousArea.swift
  TidyShot/Selection/AllInOneChoice.swift
  TidyShot/Selection/Selection.swift
  TidyShot/Selection/SelectionController.swift
  ```
  (Tasks 1 and 3's twelve files; `git diff --shortstat main -- TidyShot/` reads `12 files changed, 189
  insertions(+), 82 deletions(-)` (Task 1's 42 and 18, Task 3's 147 and 64, as the plan's facts run measured).) The last command lists the test files Tasks 1 to 3 changed, which should be
  ```
  TidyShotTests/CoordinatorCaptureSaveTests.swift
  TidyShotTests/CoordinatorCaptureSourceTests.swift
  TidyShotTests/CoordinatorCaptureTests.swift
  TidyShotTests/CoordinatorRecordingTests.swift
  TidyShotTests/CoordinatorWorldTests.swift
  TidyShotTests/Support/CaptureSamples.swift
  TidyShotTests/Support/CaptureSourceFakes.swift
  TidyShotTests/Support/CoordinatorWorld.swift
  ```
  A difference there is Tasks 1 to 3's to explain in the report; it is not this task's to fix.

- [ ] **Step 8: The built notes.** The design's section 12 gains one paragraph with the branch's suite line, the
  Release result, the marks made and the seams.md edit. If Step 7's suite line differs from `Test run with 2380 tests
  in 197 suites passed`, set `SUITE` to the line it printed before running this.
  ```bash
  cat > /private/tmp/claude-501/ct4plan-task4/design.py <<'EOF'
  import sys
  from pathlib import Path

  ROOT = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(".")
  SUITE = "Test run with 2380 tests in 197 suites passed"   # the full suite line of this task's run

  design = ROOT / "docs/superpowers/specs/2026-11-01-tidyshot-capture-seams-design.md"
  text = design.read_text()
  old = ("The close-out adds the branch's suite line and Release build, the marks made, the seams.md edit and "
         "`docs/testing/capture-seams-manual-checklist.md`.\n")
  new = old + (
      "\nBuilt on `capture-seams` from the plan `docs/superpowers/plans/2026-11-01-capture-seams.md`: the full suite "
      f"`{SUITE}` (the baseline's 2352 tests in 195 suites, and 28 tests in two new suite files; C8 is a step in an "
      "existing test and C9 was not built) and the Release build `** BUILD SUCCEEDED **` with no `error:` or "
      "`warning:` line from the compiler or the linker. 44 lines carry new or extended marks, 23 in full and 21 in part "
      "(40 first marks, and the CT-2 marks of phase-4a:119, phase-4a:120, phase-6b:118 and phase-7c:187 extended); "
      "recording-r4:217's mark was reworded with no test, and the other 23 deferred lines stay unmarked. seams.md has "
      "section 11's edit: 42 seams, Lines 440, Alone 173, Completes 279, 30 new seam slots (14 from part lines, 16 from "
      "deferred recording lines joining `TMPDIRS`), 106 lines that need two or more seams and 15 seams that unlock three "
      "or fewer; `CAPSRC` is third, `TARGET` fourth and `TMPDIRS` fifth, and the first ten seams complete 146 lines. "
      "The hand checks of section 9 are `docs/testing/capture-seams-manual-checklist.md`, for Tim.\n")
  assert text.count(old) == 1 and text.endswith(old)
  design.write_text(text.replace(old, new))
  print("design section 12 edited")
  EOF
  python3 /private/tmp/claude-501/ct4plan-task4/design.py .
  ```
  Expected: `design section 12 edited`.

- [ ] **Step 9: Check the whole change.**
  ```bash
  git status --short
  ```
  Expected, in any order, exactly these 16 paths: ` M` for
  `docs/superpowers/notes/2026-10-30-checklist-sweep/seams.md`,
  `docs/superpowers/specs/2026-11-01-tidyshot-capture-seams-design.md`,
  `docs/testing/coordinator-split-manual-checklist.md`, `docs/testing/phase-1-manual-checklist.md`,
  `docs/testing/phase-2-manual-checklist.md`, `docs/testing/phase-3-manual-checklist.md`,
  `docs/testing/phase-4a-manual-checklist.md`, `docs/testing/phase-5-manual-checklist.md`,
  `docs/testing/phase-6a-manual-checklist.md`, `docs/testing/phase-6b-manual-checklist.md`,
  `docs/testing/phase-7b-manual-checklist.md`, `docs/testing/phase-7c-manual-checklist.md`,
  `docs/testing/recording-r2-manual-checklist.md`, `docs/testing/recording-r4-manual-checklist.md` and
  `docs/testing/small-tweaks-manual-checklist.md`, and `??` for `docs/testing/capture-seams-manual-checklist.md`.
  Nothing under `TidyShot/`, `TidyShotTests/` or `project.yml`.

- [ ] **Step 10: Commit.**
  ```bash
  git add docs/testing/coordinator-split-manual-checklist.md docs/testing/phase-1-manual-checklist.md docs/testing/phase-2-manual-checklist.md docs/testing/phase-3-manual-checklist.md docs/testing/phase-4a-manual-checklist.md docs/testing/phase-5-manual-checklist.md docs/testing/phase-6a-manual-checklist.md docs/testing/phase-6b-manual-checklist.md docs/testing/phase-7b-manual-checklist.md docs/testing/phase-7c-manual-checklist.md docs/testing/recording-r2-manual-checklist.md docs/testing/recording-r4-manual-checklist.md docs/testing/small-tweaks-manual-checklist.md docs/testing/capture-seams-manual-checklist.md docs/superpowers/notes/2026-10-30-checklist-sweep/seams.md docs/superpowers/specs/2026-11-01-tidyshot-capture-seams-design.md
  git commit -m "docs: capture seams marks, seams.md, the hand-check checklist and close-out"
  ```
  Expected: `16 files changed, 451 insertions(+), 255 deletions(-)` and
  `create mode 100644 docs/testing/capture-seams-manual-checklist.md`. No attribution lines, no session URL; do not
  push. The task's report says that no hand check was run (they are Tim's, in the new checklist).

## Test totals

| After | Tests added | Suite line after |
|---|---|---|
| Baseline | | `Test run with 2352 tests in 195 suites passed` |
| Task 1 (`TARGET`) | 10 (`CoordinatorCaptureSaveTests`, new) | `Test run with 2362 tests in 196 suites passed` |
| Task 2 (`TARGET`) | 11 (`CoordinatorCaptureSaveTests`) | `Test run with 2373 tests in 196 suites passed` |
| Task 3 (`CAPSRC`) | 7 (`CoordinatorCaptureSourceTests`, new) and a step in one `CoordinatorRecordingTests` test | `Test run with 2380 tests in 197 suites passed` |
| Task 4 | 0 | `Test run with 2380 tests in 197 suites passed` |

## Plan decisions

1. **Four tasks, as the brief fixes them.** `TARGET` first, split in two (the seam with T1 to T10, then T11 to T21) so each task stays reviewable; then `CAPSRC`, separable, built on `TARGET`; then the close-out. Tasks 1 and 3 change production and run the Release build.
2. **Test bodies come from the catalogue.** The review's built tree is a reference; where it and `tests-capture.md` differ the catalogue wins (design section 12). Each departure is a decision below.
3. **`CAPSRC` is built (design call 1, the design's recommendation).** If Tim defers it, Task 3 is dropped and Task 4 is rewritten, not flagged: its 12 `CAPSRC` marks, the recording-r4:217 rewording, the `CAPSRC` verdicts and joins in the seams.md script and the checklist's second check go, and the suite line is `2373 in 196` with 32 lines marked.
4. **C9 is not built (design call 3, its default).** phase-6b:105 keeps its by-hand arming clause.
5. **Helpers shared across Tasks 1 and 2.** Task 1 adds `exists(_:)` and `openedEditor(_:)`; Task 2 uses them and adds only `pngAt`, `turnOceanBackgroundOn` and `Canvas`. (The plan's facts run found Task 2 had its own copies under other names; the copies were dropped and the renamed suite was rerun: `Test run with 21 tests in 1 suite passed`.)
6. **A second known flaky test.** `RecordingTrimTests.aKeyframeIntervalFixtureHasASyncSampleEveryInterval(reorders:)` failed once in a planning run (as it did once in CT-3's planning) and passed on rerun; a full run that fails only on it is rerun once, like the `UploadQueueTests` one. It touches no CT-4 file.
7. **Task 1.** The suite's helpers go beyond catalogue TARGET.2 rule 9: thumbnailLanded(_:_:) is taken from the built file for rule 8's thumbnail wait, and openedEditor(_:) is added now although only Task 2's T13 and T17 use it, so Task 2 only appends tests.
8. **Task 1.** T9's cause argument is a nested `nonisolated enum UploadFailureCause: Sendable { case denied, offline }` holding each case's UploadError, attempt count and message, so the three argument tuples stay Sendable values.
9. **Task 1.** T8 stores a save folder for both arguments, not only `.upload`, so the `.uploadOnly` leg can check that Saved stays empty, and its switch over AfterCaptureAction records an issue for `.save`, which the test never passes.
10. **Task 1.** T10's no-card legs also check that no drag file is handed to the card, and both T3 and T10 require exactly one upload before indexing into it; these are extra checks beyond the catalogue's lists.
11. **Task 1.** T6 compares each record's fileURL directly with `<folder>/Shot.png` (the same equality the built T2 passes with) and also checks that the new folder holds only Shot.png.
12. **Task 1.** T4 sets latestCapture to a 4 x 2 sample image for the made-up previous id, where the catalogue allows any ScaledImage.
13. **Task 1.** The plan says persist moves down 6 lines, not the 9 that design 2.1 says: that is what the built and tested +Save file shows (persist goes from :140 to :146).
14. **Task 2.** T15's parameter is labelled canvas (not case, a keyword) and its twelve arguments are a nested nonisolated CaseIterable enum Canvas carrying the content size, the BackgroundStyle and the expected canvas, the suite idiom, with the catalogue's twelve names and sizes unchanged (recomputed from BackgroundLayout.make).
15. **Task 2.** T14 keeps origin: as the parameter and takes the CaptureOrigin values CaptureSamples.display and CaptureSamples.area() directly as arguments, as the catalogue gives them.
16. **Task 2.** T18 asserts the Saved folder is empty after storeSaveFolder() and before the second save, because with no folder stored at step (1) the Saved folder does not yet exist; the pending folder is checked at step (1).
17. **Task 2.** T11, T12, T21 read the stored record from history (not the value save returned) wherever the catalogue says record.fileURL == nil or byteCount, since the returned record is the pre-upload copy.
18. **Task 2.** T19 waits for the thumbnail before asserting logLines equals the one Background line, so a thumbnail failure line would show; it passed in the scratch run, retiring the TARGET.5 risk.
19. **Task 2.** Every test whose size or pixel assertion needs the Ocean background goes through one helper turnOceanBackgroundOn() that also ties the literal gradient index 1 to the name Ocean, as T3 does; T15 sets its own style per case without that helper.
20. **Task 2.** T17 additionally asserts the composed corner pixel (1, 1) is not the world's red, and T16 asserts the composed first file is 592 by 492, as cheap checks that the right capture is in each file.
21. **Task 2.** The block is inserted by replacing the file's last two lines (a 4-space closing brace and the struct's column-0 brace), anchored by a grep -c '^}' of 1, because Task 1's last test text is not known to this task; the Edit anchor is therefore the end of the file, not T10's text.
22. **Task 2.** No Release build step, since this task has no production change; the step instead asserts git diff --stat HEAD -- TidyShot/ is empty.
23. **Task 3.** CaptureSourceFakes.swift leaves out the five members design section 12 names (FakeSelector.answerAllInOne(_:) with its held All-in-One branch and heldChoice, FakeSelector.overlays, FakeSelector.frozen, FakeCaptureSource.scale, FakeCaptureSource.pointerDisplayID), because no test in C1 to C8 needs them: a capture answers at scale 1, the display under the pointer is the first, frozenCapture answers nil, overlayWindows answers [], and selectAllInOne answers from choices and is never held, so the type docs say so.
24. **Task 3.** AppEnvironment.live()'s doc comment is rewritten as design 2.2 asks (ScreenCaptureKit and the selection overlay after the general pasteboard; the overlay built there with Clop's optimiser); the review's built file lacks this rewrite, so AppEnvironment.swift is the one production file that differs from the built copy.
25. **Task 3.** CoordinatorWorld's type doc (lines 13-17) is rewrapped so the added phrase about source and selector stays within 120 columns; the review's built world left the type doc unchanged.
26. **Task 3.** CoordinatorCaptureTests' inline comment at line 34 ('would wait on the content read') is reworded alongside the suite doc design 3.3 names, because with the fake source a capture past the lock would read the fake content rather than wait.
27. **Task 3.** C8's eight capture entries run from an array of @MainActor closures, each in its own TaskWatch-gated Task, rather than eight written-out blocks; CoordinatorRecordingTests then counts 16 tests and the four touched suites 25.
28. **Task 3.** C8's doc comment replaces the existing 'recording-r2 :351, the held prompt's part (a B line, left unmarked, D15)' wording with the key and current line (recording-r2:351 (:386), in part) and what stays and whose (STATUSMENU; TMPDIRS and RECCHROME).
29. **Task 3.** C2's and C7's catalogue values are used exactly, and C7 checks each step's capture with captures.count and captures.last rather than captures[n] indexing, so a short array fails an expectation instead of trapping.
30. **Task 3.** A build-for-testing step comes after the fakes and the world edits and before the new tests, so a compile error in the design's diff is caught and reported before any test is written (design 2.2's stop-and-report rule).
31. **Task 4.** phase-6b:105's mark is the catalogue's form without C9, because C9 is not built: its suite list keeps the four existing SelectionViewArmingTests and its by-hand text keeps 'arming by a W change or the lock toggle, and Return typed in another app'.
32. **Task 4.** The four CT-2 marks that CT-4 extends (phase-4a:119, phase-4a:120, phase-6b:118, phase-7c:187) take TARGET.4's wording whole rather than the old note edited word by word, so phase-4a:119 and :120 lose the AppCoordinator+Save.swift line-number prose, phase-6b:118 loses 'the test pins the editor opening on the new capture and its card closing', and phase-7c:187's by-hand text becomes 'the popover's switch (`BGPOP`), drawn in the window (`EDPLACE`)'.
33. **Task 4.** Marks spell every suite in full (T<n> as CoordinatorCaptureSaveTests.<name>, CCS as CoordinatorCaptureSourceTests) and use the `.name` shorthand only where the catalogue's own list did, and a bare suite name (phase-7c:184's BackgroundLayoutTests) is kept as the catalogue has it and checked by its `struct` instead of being replaced by a chosen test.
34. **Task 4.** recording-r4:217's reworded mark is the design's text verbatim, including '+Recording.swift:496', which still reads line 496 in the built tree after CAPSRC (the NSScreen.screens read has not moved).
35. **Task 4.** Anchors are the first 40 characters of each item's text, chosen by running them against the checklists at 705bce0 (each occurs once), and the script's anchors mode also checks the 23 deferred lines, so 68 anchors in all.
36. **Task 4.** The marks script also visits the checklists that hold only deferred lines (recording-r1, recording-r3), which the CT-3 script's loop skipped, so their 'stay unmarked' assertion actually runs.
37. **Task 4.** seams.md's equal-Lines tie rule is CT-3's (sort by Lines, then old table position), which reproduces every row and place in section 11 (CAPSRC third, TARGET fourth, TMPDIRS fifth, SCROLL 17th, SELINT 24th).
38. **Task 4.** A joined entry is noted 'also `<home seam>`, in part since CT-4' ('deferred in CT-4' for the 16 recording lines) under the row it joins, and every row that lists one of the 27 changed lines has its '(also ...)' regenerated in the new table order, so CAPSRC now precedes TARGET, SCREENS and WORKSPACE in coordinator-split:36's note.
39. **Task 4.** recording-r1:105's home entry reads '(also `TMPDIRS`); needs `TMPDIRS` first (CT-4); CT-4: deferred', putting section 11's required note before the verdict suffix.
40. **Task 4.** Multi-seam groups name their seams in the new table order, so the design's 'CAPSRC + RECCHROME + TMPDIRS' reads `CAPSRC` + `TMPDIRS` + `RECCHROME` (8 lines) and `SAVEAS` + `SCREENS` reads `SCREENS` + `SAVEAS` (3); `TARGET` + `SCREENS` is new with 3 and `CAPSRC` + `SELINT` goes from 1 to 2, as section 11 says.
41. **Task 4.** seams.md also gains a `CT-4` note bullet in the TARGET and CAPSRC sections, one sentence in the header's Source paragraph, and rewritten Shape and Live bullets for sections 3 and 4 (design 2.1 and 2.2 in short), beyond the one line section 11 names for recording-r1:105, as CT-3 did for its three seams.
42. **Task 4.** The seams.md summary keeps its sentence that CAPSRC, SELINT and SCROLLCTL are built on TARGET, although the table now lists CAPSRC third and TARGET fourth, because the counts section 11 gives are computed in that table order.
43. **Task 4.** The checklist carries the design's two section-9 checks and all eleven section-10 calls; call 3 says C9 is not built and call 1 says CAPSRC is built here and what overruling it would drop.
44. **Task 4.** Step 7 adds a check of `git diff --name-only main -- TidyShotTests/` against the eight files the spec says Tasks 1 to 3 touch, and says a difference is those tasks' to explain, not this task's to fix; the production list is the twelve files of spec 12.
45. **Task 4.** The spec paragraph is appended after section 12's last sentence by a script that asserts the file ends with that sentence, and it records that C8 is a step in an existing test and C9 was not built.
46. **Task 4.** The marks step prints '44 lines marked (40 for the first time, 4 extended), 1 deferred line's mark reworded', and the commit expectation is '16 files changed, 451 insertions(+), 255 deletions(-)', both taken from a run of the extracted scripts against a copy of the 705bce0 docs.
47. **Task 4's diffstat.** Step 7's `TidyShot/` shortstat is the facts run's `12 files changed, 189 insertions(+), 82 deletions(-)` (Task 1 42/18, Task 3 147/64); the design's +184 −78 was the review tree, which lacked the `live()` doc rewrite and the world's rewrap.
48. **Task 1.** T4 stores a save folder before its copy-only save and checks that folder holds no file, where the catalogue (T4's input, 'no folder stored', and its `currentURL` nil check) and design rule 2 ('or is copy-only') save with none. With no folder stored, a regression that drops the copy-only branch or moves it after `persist` would reach `ensureFolder` and build a folder panel rather than fail; with one stored it writes a file there and fails at once. The stricter form is D9's, applied to T4; the suite doc drops the copy-only exemption to match.
