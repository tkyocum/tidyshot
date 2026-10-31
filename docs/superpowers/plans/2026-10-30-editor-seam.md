# TidyShot Editor Seam (CT-2), Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The coordinator builds the annotation editor through one seam, the editor presenter factory (`EDITOR`): a class-bound protocol `EditorPresenting` that `EditorWindowController` conforms to unchanged, and a `@MainActor` factory closure `AppEnvironment.makeEditor`, so the suite reaches an open editor, its four actions and the quit review through a `FakeEditor`. 46 tests are added in four suite files (two new), and 65 of the 73 editor lines get their marks, 25 in full and 40 in part; the other 8 wait for `EDPLACE`. The suite goes from `Test run with 2272 tests in 191 suites passed` to `Test run with 2318 tests in 193 suites passed`. Nothing a user sees changes.

**Architecture:** `docs/superpowers/specs/2026-10-30-tidyshot-editor-seam-design.md` ("the design") is the specification. Its catalogue `docs/superpowers/notes/2026-10-30-editor-seam/tests-editor.md` ("the catalogue") gives every test's suite, entry point, record, fakes, sequence, assertions, effort and the lines it covers, and `docs/superpowers/notes/2026-10-30-editor-seam/lines-editor.md` gives each of the 73 lines with its key, current line, verdict and what stays. When this plan and either disagree, the plan's "Plan decisions" (at the end) says why; stop and ask if anything else is unclear.
- **The seam (Task 1):** design 2.1-2.4 on four `TidyShot/` files, +47/-15: `EditorPresenting` and the empty conformance in `EditorWindowController.swift`, `makeEditor` and its live closure in `AppEnvironment.swift`, the registry typed `[UUID: any EditorPresenting]` in `AppCoordinator.swift`, and `presentEditor` and `editorDidClose` going through the protocol in `AppCoordinator+Editor.swift`. `reviewEditorsBeforeQuit` is unchanged byte for byte.
- **Support (Task 1):** `FakeEditor` and `FakeEditors` in the new `TidyShotTests/Support/EditorFakes.swift` (design 3.1), `FakeClipboard.pngs` (design 3.2), `world.editors` and `makeEditor` in `CoordinatorWorld` (design 3.3), and the new `TidyShotTests/Support/EditorPixels.swift` (catalogue 2.1). None of them is a seam.
- **Coordinator suites (Tasks 1 to 7):** drive `AppCoordinator`'s internal entry points over `CoordinatorWorld`, open an editor with `openEditor(recordID:)`, play the user through the `FakeEditor`'s helpers, and observe with `eventually`, `TaskWatch` and the held fakes, as the harness suites do. Two new files, `CoordinatorEditorSaveTests` (Tasks 2 and 3) and `CoordinatorEditorUploadTests` (Tasks 4 and 5); two existing ones, `CoordinatorEditorTests` (Tasks 1, 6 and 7) and `CoordinatorOverlayTests` (Task 7).
- **Close-out (Task 8):** the 65 marks placed by a script that finds each line by its text, `seams.md` edited by a script as design 11 says, the hand-check checklist `docs/testing/editor-seam-manual-checklist.md` (design 9), and the built notes.

**Tech Stack:** Swift 6 language mode with default `MainActor` isolation and `NonisolatedNonsendingByDefault`, Swift Testing, AppKit, ImageIO (in `EditorPixels`, for the DPI read), XcodeGen 2.46, Python 3 for Task 8's scripts.

**Tried before writing:** The plan's review applied every step as written, in task order, to a copy of the repository at dd1231d with a `git init` base holding that tree, so the `git diff`, `git status` and commit steps ran as written: a script took each step's blocks from the plan, asserted each "Replace … with" anchor once in its file and each new file absent, and each task was committed with its message. Every step applied on the first try. The four `TidyShot/` files, `EditorFakes.swift`, `EditorPixels.swift` and `CoordinatorFakes.swift` came out byte-identical to the review's built tree, `CoordinatorWorld.swift` differed only in its header comment (D9), and 43 of the 46 bodies matched statement for statement, the other three as D26, D38, D39 and D40 say; `@Test` attributes went from 2272 (98 parameterized) to 2318 (105). Each run printed its task's expected line: Task 1 `Test run with 4 tests in 1 suite passed` and `Test run with 2274 tests in 191 suites passed`, the Release build `** BUILD SUCCEEDED **` with only D63's two tool lines, and `4 files changed, 47 insertions(+), 15 deletions(-)` for `TidyShot/`; Task 2, 8 and 2282 in 192; Task 3, 17 and 2291 in 192; Task 4, 9 and 2300 in 193; Task 5, 14 and 2305 in 193; Task 6, 12 and 2313 in 193; Task 7, 16 and 2 and 2318 in 193, with `2 files changed, 260 insertions(+)`; Task 8, `65 lines marked` (`8 files changed, 189 insertions(+), 10 deletions(-)`), the seams.md script's line with `376 insertions(+), 301 deletions(-)`, 73 `; CT-2: ` verdicts and the seven headings at the expected lines, `notes edited`, 2318 in 193 again, and the Release build `** BUILD SUCCEEDED **` with the `iOSSimulator` line only (an incremental build). The full runs took 46.6 s to 53.0 s, and their only other lines were the known noise (42 `MDB_MAP_FULL`, 7 `linkd.autoShortcut`, 2 `History file could not be read or decoded`, the `iOSSimulator` line). Each new suite then ran 5 iterations with `-test-iterations 5 -run-tests-until-failure` (`CoordinatorEditorSaveTests` 17 tests, `CoordinatorEditorUploadTests` 14, and `CoordinatorEditorTests` with `CoordinatorOverlayTests` 18 in 2 suites) with no failure. A second, separate application of the blocks built with `** TEST BUILD SUCCEEDED **` and no compiler warning and ran `Test run with 2318 tests in 193 suites passed`. The review's fixes after those runs rewrap five doc comment lines (same line count), add a width check to Tasks 2 to 5, and change the wrap and wording of Task 8's note texts; on a copy at Task 7's commit with the rewrapped comments, `CoordinatorEditorSaveTests` and `CoordinatorEditorUploadTests` together ran `Test run with 31 tests in 2 suites passed`, the width checks printed nothing, and Task 8's scripts as now written printed the same lines and committed `13 files changed, 636 insertions(+), 313 deletions(-)`.

Work happens on the branch `editor-seam` (from `main` at a079a6f; the design at dd1231d, which changed docs only). Line numbers below are the working tree's at dd1231d, which for every file under `TidyShot/` and `TidyShotTests/` are a079a6f's. Once a task has grown a file, find the place by the quoted text. This plan is committed on `editor-seam` before Task 1, as CT-1's plan was (8882bfd), so every check below that expects `git status --short` to print nothing, or only a task's own paths, sees a clean tree; that commit, and any other made before Task 1, changes nothing under `docs/testing`, `docs/superpowers/notes` or `docs/superpowers/specs`, since Task 8's Step 1 and its scripts assert dd1231d's text of those files (D71).

## Global Constraints

- **The phase's hard constraints, verbatim:**
  - Production changes are limited to the seam: the editor's construction and presentation, its registry on the
    coordinator, and what `reviewEditorsBeforeQuit` calls. No behaviour change a user could see. No `private` member
    opened for tests. No other seam.
  - No test touches `AppSettings.shared`, `NSPasteboard.general`, the Keychain, `UNUserNotificationCenter`,
    `NSWorkspace`, `NSScreen.screens`, the `tmp/` statics, a window ordered front, the screen, a camera, a microphone,
    a sound or the network. Constructing an `NSWindow` that is never ordered front is allowed (the view suites do it).
  - Held fakes are cancellable and single-entry; no direct await on the behaviour under test (`eventually`, `TaskWatch`).
  - Own temp folders and defaults suite per test; no `.serialized`.
  - `HistoryStore` prunes on the real `Date()`.
  - The tests' `MovieSamples` decoder is untouched.
  - Credentials only in the Keychain; never log or print credentials or signatures.
  - No GPL code read or copied (macshot, the Clop app, gifsicle, ffmpeg, gifski).
  - Never record the mic or camera; never lose a recording; never change system settings, TCC or the bucket.
  - Agents never run anything that records the screen, opens the camera or mic, plays sound, or talks to a real bucket.
  - Commits and PRs carry no attribution lines and no session URL. Agents never push. (Adapted: context.md's bullet
    ends "Agents never commit or push in this design phase"; in this plan every task commits, and nothing is pushed,
    D70.)
  - Plain prose, no mannered phrasing; file:line references for every claim about the code.
- **From the design's section 5, "Rules for the tests", verbatim:**
  - `TidyShot/` changes only as section 2 says. No `private` member opens. A test that would need more is reported, not forced, and its line goes to a later seam.
  - No test touches `AppSettings.shared`, `NSPasteboard.general`, the Keychain, `UNUserNotificationCenter`, `NSWorkspace`, `NSScreen.screens`, the `tmp/` statics, a window ordered front, the screen, a camera, a microphone, a sound or the network. `RedactionRenderer.shared` is process-wide. The warm-up on every open and the cache clear on the last close reach it (+Editor:88, :474; RedactionRenderer.swift:79-88), and CT-2's tests are the first in the suite to do so (`RedactionRendererTests` and `RedactionExportTests` each make their own renderer, RedactionRendererTests.swift:74, RedactionExportTests.swift:37). No test observes it: the actor runs one call at a time, a cleared cache leaves its context usable (RedactionRendererTests.swift:90-95), and the tile cache asks it only for effects (Annotation.swift:101-105). So **no test commits an effect** (redact, blur, pixelate); tests draw boxes, strokes, text, counters and spotlights. The warm-up tasks can outlive their tests and touch nothing a test reads. Every coordinator call that takes an intent gets an explicit `CaptureIntent(action:)`. History is loaded with `history.load()`, never `start()`: `start()` removes the `tmp/` statics (Coord:294-300). The coordinator's `HistoryStore` prunes against the real `Date()` (HistoryStore.swift:23, Coord:278), so retention tests stamp records relative to `Date()`. Backgrounds are solid only. A desktop picture or a custom image would read the wallpaper or `CustomBackgroundStore.shared` (TidyShot/Background/BackgroundFillSource.swift:10-14). No test calls `restoreClosedOverlay()` until `canRestoreClosedOverlay` has been required false, since a restore reads `NSScreen.screens` (+Overlay:56, :87-90).
  - Held fakes are cancellable and single-entry. No test awaits directly on a call whose only way out is the behaviour under test (`eventually`, UploadQueueTests.swift:42; `TaskWatch`), and that includes a delete whose confirm is held: the delete's task is gated by `TaskWatch` before `await delete.value`. A held PUT is released in a `defer`; a held sheet's or confirm's task is cancelled in a `defer` (3.4, step 3). A test that held a PUT also releases it and waits for `isUploading == false` before it returns, so `handle(.uploaded)` does not save history after `removeAll()`.
  - **Nothing an edit starts outlives its test.** An edit that reaches `applyLocalEdit` starts the thumbnail task (+Editor:217, :249-275), which saves history when it lands (HistoryStore.swift:199-215) and would recreate the world's folders after `removeAll()` (ThumbnailStore.swift:44-45). So a test whose action reached `applyLocalEdit` ends with the suite helper `settledEdit(coordinator, id)`, which waits until the record names `thumbnails.fileName(for: id, editedAt: world.date)`; a test's second edit of one record first moves `world.date` on by a second, so its thumbnail gets a new name to wait for. A test that compares a whole record after a Save or an Upload waits for that name first, or the comparison races the task. A `finishSave` test waits for the capture's own thumbnail (+Save:288-309) the same way.
  - **A relaunch** is a second `world.makeCoordinator()` and `history.load()` (never `start()`). Before it, the first coordinator is quiescent: no upload running, the edit's thumbnail named. After it, the test calls nothing on the first coordinator and does not run `world.clock`, since the first coordinator still holds its folder observation, its drag clean-ups and its own `HistoryStore` over the same `history.json` (+Editor:137-152, +DragOut:261-276, HistoryStore.swift:66-70).
  - Each test owns its `CoordinatorWorld`, with `defer { world.removeAll() }`. Suites are `@Suite(.timeLimit(.minutes(1)))`, with no `.serialized`. Save-folder cases call `world.storeSaveFolder()` (World:150-156) before `makeCoordinator()`. A second folder is `world.saveLocation.store(_:)` on `<root>/Other/`. The minimal design's built tests wrote over a bookmarked file this way, which settles harness D25.
  - **The fake editor.** Its helpers replay the controller's rules, and the controller's own lines do not run. A line that names the unsaved dot, the subtitle as shown, a greyed item, the window's key routing, the window's refusal of a shortcut or the window closing is therefore marked in part, with `EDPLACE` named for the rest. The window coming forward is `present()`'s own body (EWC:145-159), which the fake records and does not run; a line that names it is in part, and that part stays by hand for good, since ordering a window front is barred in the suite. **A constructed controller:** No test in this phase builds an `EditorWindowController`. Its init reads the screens (EWC:123) and registers with NSWorkspace (EWC:103). `EditorToolbarTests.makeEditor` (EditorToolbarTests.swift:54-66) already does both, and stays as it is until `EDPLACE` fixes it. No CT-2 test calls or copies `EditorToolbarTests.makeEditor`; it is a known exception owned by `EDPLACE`.
  - Test names are camelCase sentences; parameterized tests use `@Test(arguments:)`. The suite stays green after every task. The Release build is run at the end.
- **The plan's own rules:**
  - The suite command, the known noise, and the baseline `Test run with 2272 tests in 191 suites passed` at a079a6f and at dd1231d (dd1231d changed docs only).
  - Commit after every task with the task's message; no attribution lines, no session URL; never push; never switch branches. No task runs the app; the hand checks are Tim's, and each task's report says none were run.
  - Code blocks are complete: a new file's step gives the whole file; an addition to an existing file says exactly where it goes (quote the line before and after, or "before the closing `}` of `struct X`") and gives the whole block. No "as in Task N", no "similar to", no "add the remaining tests", no TODO. Types, helper names and signatures are the same in every task that uses them (the Interfaces lines carry them).
  - Where the catalogue and the built code differ, the built code wins if the suite's green run depended on it, and the difference is a Plan decision; where a built doc comment is at odds with `lines-editor.md`, `lines-editor.md` wins.
  - Plain prose. No mannered phrasing. file:line references at dd1231d for claims about the code.
- **The suite command.** Run the full suite with:
  ```bash
  xcodegen generate && xcodebuild test -project TidyShot.xcodeproj -scheme TidyShot -destination 'platform=macOS' -derivedDataPath .build 2>&1 | grep -E "Test run with|error:|TEST"
  ```
  and one suite with `-only-testing:TidyShotTests/<Suite>` added before `2>&1`. The baseline is `Test run with 2272 tests in 191 suites passed` (at a079a6f and dd1231d). The known noise lines are not failures: `History file could not be read or decoded, setting it aside` twice, `com.apple.linkd.autoShortcut`, about 40 `mdb_txn_commit error: MDB_MAP_FULL` lines, and on a machine whose CoreSimulator is older than Xcode's (this one) an `xcodebuild[…] iOSSimulator: [SimServiceContext sharedServiceContextForDeveloperDir:error:] returned nil … CoreSimulator is out of date …` line at the start of every `xcodebuild` run, which the `error:` filter lets through (D63). A passing run ends `** TEST SUCCEEDED **`. The suite takes 45 s to 130 s (about 126 s when coreaudiod stalls); a slow run is not a failure. The Release build is:
  ```bash
  xcodegen generate && xcodebuild -project TidyShot.xcodeproj -scheme TidyShot -configuration Release -derivedDataPath .build-rel build 2>&1 | grep -E "error:|warning:|BUILD"
  ```
  and it prints `** BUILD SUCCEEDED **` and no `error:` or `warning:` line from the compiler or the linker. Two tool lines may print and are not failures, since the tree at dd1231d prints them too (D63): the `iOSSimulator: … sharedServiceContextForDeveloperDir:error:` line above, and `appintentsmetadataprocessor[…] warning: Metadata extraction skipped, no AppIntents.framework dependency found`.
- **Counting.** `xcodebuild`'s line counts each `@Test` function once, whatever its arguments: the tree at dd1231d has exactly 2272 `@Test` attributes, 98 of them parameterized, and reads 2272 tests. Each new test file is one new suite. This plan adds 46 `@Test` functions (7 of them parameterized) and 2 suite files; `EditorFakes.swift` and `EditorPixels.swift` hold no tests.
- **The harness's rules hold.** A coordinator test builds its world in the suite's `init`, calls `defer { world.removeAll() }` first, passes an explicit `CaptureIntent(action:)` to every entry point that takes one, and never calls an entry point whose default argument is `.standard`. A test that would wait on a held fake gates the call with `TaskWatch` and `eventually`. Retention tests stamp records relative to `Date()`. Every coordinator suite keeps `settings.showOverlay` off whenever a save could show a card, because `showOverlay(for:)` reads `NSScreen.screens` once the setting is on.

---

### Task 1: The seam, the fakes, and two first tests [integration]

**Files:**
- Modify `TidyShot/Editor/Window/EditorWindowController.swift`: `protocol EditorPresenting` after `EditorActions` (its closing `}` at :32) and before the class's doc comment (:34); `extension EditorWindowController: EditorPresenting {}` after the file's last line (:521). Nothing else in the file changes (design 2.1).
- Modify `TidyShot/App/AppEnvironment.swift`: `makeEditor` between `playShutter` (:35) and `now` (:36); its live closure between `playShutter:` (:69) and `now:` (:70); `live()`'s doc comment (:43-46) adds "the editor window" (design 2.2).
- Modify `TidyShot/App/AppCoordinator.swift`: the registry's doc comment and type (:258-259) (design 2.3). `reviewEditorsBeforeQuit` (:466-477) is unchanged byte for byte (design 2.4).
- Modify `TidyShot/App/AppCoordinator+Editor.swift`: `presentEditor`'s doc comment (:72-73), its build and present (:81-85, :89); `editorDidClose` (:468-471) (design 2.3).
- Create `TidyShotTests/Support/EditorFakes.swift` (design 3.1, whole).
- Create `TidyShotTests/Support/EditorPixels.swift` (catalogue 2.1).
- Modify `TidyShotTests/Support/CoordinatorFakes.swift`: `FakeClipboard.pngs` after `copies` (:167), and the two image copies (:172-173) (design 3.2).
- Modify `TidyShotTests/Support/CoordinatorWorld.swift`: the header comment (:11-17) adds the editors; `let editors = FakeEditors()` after `let confirm = FakeConfirm()` (:41); `let editors = editors` after `let confirm = confirm` (:108); `makeEditor:` after `playShutter:` (:123) (design 3.3).
- Modify `TidyShotTests/CoordinatorEditorTests.swift`: `import CoreGraphics` with the imports (:1-3) (D8); the header (:5-7) reworded (design 4, catalogue 5); the suite's helpers after `var link: URL { … }` (:18), before `nonisolated enum Kept` (:20) (D4); the two tests before the closing `}` of `struct CoordinatorEditorTests` (:93).

**Interfaces:**
- Consumes (the harness as it is at dd1231d): `CoordinatorWorld` (`makeCoordinator()` :131, `removeAll()` :141, `storeSaveFolder()` :151, `static func image(width:height:) throws -> CGImage` :170, `static func pngData(width:height:) throws -> Data` :180, `factory.standard`, `notifier`, `cards`, `clipboard`, `confirm`, `date`, `location`, `saveLocation`, `settings`, `root`); `func eventually(_ condition: () async -> Bool) async throws` (UploadQueueTests.swift:42); `final class TaskWatch` (CoordinatorFakes.swift:420); `final class SingleWaiter<Value: Sendable>` (CoordinatorFakes.swift:375); `FakeDestination` (`state`, `releaseUploads()`, `releaseAborts()`); the existing `CoordinatorEditorTests` members `let key = "s/SHOT.png"` (:11), `var destination: FakeDestination { world.factory.standard }` (:17), `var link: URL { URL(string: "https://snap.tky.io/\(key)")! }` (:18), `nonisolated enum Kept` (:20).
- Produces, production (every later task relies on these):
  ```swift
  protocol EditorPresenting: AnyObject {
      var model: EditorModel { get }
      func present()
      func recordDidChange(_ record: CaptureRecord?, saveFolder: URL?, isDeleting: Bool)
      func askToSaveBeforeClosing() async -> Bool
  }
  extension EditorWindowController: EditorPresenting {}
  // AppEnvironment
  var makeEditor: @MainActor (_ model: EditorModel, _ actions: EditorActions, _ title: String,
                              _ representedURL: URL?,
                              _ onClose: @escaping @MainActor (any EditorPresenting) -> Void) -> any EditorPresenting
  // AppCoordinator
  @ObservationIgnored var editors: [UUID: any EditorPresenting] = [:]
  private func editorDidClose(_ editor: any EditorPresenting)   // stays private
  ```
- Produces, `EditorFakes.swift` (main-actor under the test target's default isolation):
  - `final class FakeEditor: EditorPresenting` with `struct Push: Equatable { var record: CaptureRecord?; var saveFolder: URL?; var isDeleting: Bool; var available: Set<EditorAction> { get }; var status: String? { get }; var saveCommand: EditorSaveCommand { get } }`, `enum Call: Equatable { case present, askToSave, recordDidChange(Push) }`, `nonisolated enum CloseAnswer: Equatable, Sendable { case save, dontSave, cancel; case saveAs(URL) }`; `let model: EditorModel`, `let actions: EditorActions`, `let title: String`, `let representedURL: URL?`, `private(set) var calls: [Call]`, `private(set) var isClosed: Bool`, `var closeAnswers: [CloseAnswer]`, `var holdsCloseSheet: Bool`, `init(model: EditorModel, actions: EditorActions, title: String, representedURL: URL?, onClose: @escaping @MainActor (any EditorPresenting) -> Void)`, `var presentCount: Int`, `var pushes: [Push]`, `var isAsking: Bool`, `func present()`, `func recordDidChange(_ record: CaptureRecord?, saveFolder: URL?, isDeleting: Bool)`, `func askToSaveBeforeClosing() async -> Bool`, `func answer(_ answer: CloseAnswer)`, `func close()`, `func draw()`, `func export() async -> (image: ScaledImage, document: AnnotationDocument)?`, `@discardableResult func save() async -> Bool`, `@discardableResult func saveAs(to url: URL) async -> Bool`, `func copy() async`, `@discardableResult func upload(asNew: Bool = false) async -> EditorUploadOutcome`.
  - `final class FakeEditors` with `private(set) var built: [FakeEditor]`, `func make(model: EditorModel, actions: EditorActions, title: String, representedURL: URL?, onClose: @escaping @MainActor (any EditorPresenting) -> Void) -> any EditorPresenting`, `func editor(for id: UUID) -> FakeEditor?` (the newest built for `id`).
  - The file is design 3.1's block exactly; the review's built tree holds the same file byte for byte.
- Produces, the world and the clipboard: `CoordinatorWorld.editors: FakeEditors` (`let`); `FakeClipboard.pngs: [Data]` (`private(set) var`), appended by `copy(image:pngData:scale:)` and `copy(pngData:tiffData:)` only.
- Produces, `EditorPixels.swift` (`nonisolated enum EditorPixels`, imports CoreGraphics, Foundation, ImageIO, Testing, `@testable import TidyShot`; as built):
  ```swift
  static func image(width: Int, height: Int, white: Bool = false) throws -> CGImage
  static func png(width: Int, height: Int, scale: CGFloat, white: Bool = false) throws -> Data
  static func decoded(_ png: Data) throws -> (image: CGImage, scale: CGFloat)
  static func dpiWidth(of png: Data) -> Double?
  static func rgba(_ image: CGImage) -> [UInt8]
  static func pixel(_ image: CGImage, x: Int, y: Int) -> [Int]
  static func pixel(_ png: Data, x: Int, y: Int) throws -> [Int]
  static func changedPixels(_ image: CGImage, in rect: CGRect, from rgb: [Int]) -> Int
  @MainActor static func worldRed() throws -> [Int]
  static func isBlue(_ pixel: [Int]) -> Bool
  static func isBlue(_ image: CGImage) -> Bool
  static func isBlue(png: Data) throws -> Bool
  ```
- Produces, `CoordinatorEditorTests`' helpers (`key`, `link`, `destination`, `all`, `publicURL`, `openedEditor`, `reopenedEditor`, `settledEdit`, `addSavedImage`, `addPendingImage`, `desktop`, `pendingURL`, `addUploadOnly`, `isUploaded`, `title(of:)`, `exists`, `crop`, `addText`, `green`, `background`), used by Tasks 6 and 7:
  ```swift
  let key = "s/SHOT.png"   // at dd1231d, CoordinatorEditorTests.swift:11, unchanged
  var link: URL { URL(string: "https://snap.tky.io/\(key)")! }   // at dd1231d, CoordinatorEditorTests.swift:18, unchanged
  var destination: FakeDestination { world.factory.standard }   // at dd1231d, CoordinatorEditorTests.swift:17, unchanged
  var all: Set<EditorAction> { Set(EditorAction.allCases) }
  func publicURL(_ key: String) -> URL
  func openedEditor(_ id: UUID) async throws -> FakeEditor
  func reopenedEditor(_ id: UUID, after first: FakeEditor) async throws -> FakeEditor
  func settledEdit(_ coordinator: AppCoordinator, _ id: UUID) async throws
  func addSavedImage(to coordinator: AppCoordinator, in folder: URL, name: String = "Shot.png", uploadState: CaptureRecord.UploadState = .none, objectLocation: ObjectLocation? = nil, uploadIsStale: Bool = false, timestamp: Date = Date(), scale: CGFloat = 1) throws -> (record: CaptureRecord, original: Data)
  func addPendingImage(to coordinator: AppCoordinator) throws -> CaptureRecord
  func desktop(_ name: String) throws -> URL
  func pendingURL(_ coordinator: AppCoordinator, _ id: UUID) -> URL
  func addUploadOnly(to coordinator: AppCoordinator) throws -> CaptureRecord
  func isUploaded(_ coordinator: AppCoordinator, _ id: UUID) -> Bool
  func title(of record: CaptureRecord) -> String
  func exists(_ url: URL) -> Bool
  func crop(_ model: EditorModel, to rect: CGRect, apply: Bool)
  func addText(_ model: EditorModel, _ string: String, at point: CGPoint) throws -> TextBox
  var green: RGBA { RGBA(red: 0, green: 1, blue: 0) }
  var background: BackgroundStyle { BackgroundStyle(fill: .solid(green), padding: 8, cornerRadius: 0, shadow: false, aspect: .auto) }
  ```

**Tests:**
1. `annotateOnACaptureWhoseEditorIsOpenBringsItForwardAndBuildsNoSecond`: catalogue section 5 (CoordinatorEditorTests.swift), "Opening", tests-editor.md:1267; effort S.
2. `quitAsksEachChangedEditorCancelStopsItDontSaveLetsItGo`: catalogue section 5 (CoordinatorEditorTests.swift), "The quit review", tests-editor.md:1643; effort S.
- 2 tests (S 2), 0 parameterized.
- Focused run, `-only-testing:TidyShotTests/CoordinatorEditorTests`: `Test run with 4 tests in 1 suite passed` (the 2 existing tests and these 2).
- Full suite: `Test run with 2274 tests in 191 suites passed`.
- Also: `git diff --stat a079a6f -- TidyShot/` lists exactly `TidyShot/App/AppCoordinator+Editor.swift`, `TidyShot/App/AppCoordinator.swift`, `TidyShot/App/AppEnvironment.swift` and `TidyShot/Editor/Window/EditorWindowController.swift`, and ends `4 files changed, 47 insertions(+), 15 deletions(-)` (as the review's built tree has it). The Release build prints `** BUILD SUCCEEDED **` and no `error:` or `warning:` line beyond the two tool lines the Global Constraints name (D63).

**Commit:** `refactor: the coordinator's editor through AppEnvironment.makeEditor, its fakes, two editor tests`

**Steps:**

- [ ] Check the starting point. From the repository root:
  ```bash
  git branch --show-current
  git status --short -- TidyShot TidyShotTests
  git diff --stat a079a6f -- TidyShot/ TidyShotTests/
  ```
  Expected: `editor-seam`, then nothing, then nothing (the branch has changed only docs since `main`).

#### The seam (design 2.1-2.4)

- [ ] In `TidyShot/Editor/Window/EditorWindowController.swift`, add the protocol after `EditorActions` (:18-32) and before the class's doc comment (:34). Replace these lines (:29-34):
  ```swift
      /// The Background popover's `Choose Image…` was given a file that does not decode.
      var unusableBackgroundImage: (_ fileName: String) -> Void
  }

  /// One annotation editor window for one capture record: the window, the two stacked views, the
  ```
  with:
  ```swift
      /// The Background popover's `Choose Image…` was given a file that does not decode.
      var unusableBackgroundImage: (_ fileName: String) -> Void
  }

  /// What the coordinator asks of an open annotation editor (the editor seam): `EditorWindowController`
  /// in the app, `FakeEditor` in the suite. Class-bound, so the registry keeps one object per record and
  /// `editorDidClose` and the quit review compare by identity (`===`). Construction, and the close
  /// callback, are `AppEnvironment.makeEditor`'s.
  protocol EditorPresenting: AnyObject {
      /// The editor's document; the coordinator reads `recordID` and `hasUnsavedChanges`.
      var model: EditorModel { get }
      /// Brings the editor forward (activates the app).
      func present()
      /// The coordinator's push (`pushEditorState`): the record as it is now (nil once deleted or
      /// pruned), the save folder, and whether a delete is running.
      func recordDidChange(_ record: CaptureRecord?, saveFolder: URL?, isDeleting: Bool)
      /// The unsaved-changes sheet, for the quit review. True when the editor may go.
      func askToSaveBeforeClosing() async -> Bool
  }

  /// One annotation editor window for one capture record: the window, the two stacked views, the
  ```
  The controller already has these four members with these exact signatures: `let model: EditorModel` (:37), `func present()` (:147), `func recordDidChange(_ record: CaptureRecord?, saveFolder: URL?, isDeleting: Bool)` (:165) and `func askToSaveBeforeClosing() async -> Bool` (:460).

- [ ] In the same file, add the conformance after the file's last line. Replace the end of the file (:517-521):
  ```swift
      /// Space's key-up goes elsewhere once the window is not key, so the pan key is let go here.
      func windowDidResignKey(_ notification: Notification) {
          canvasView.endSpacePan()
      }
  }
  ```
  with:
  ```swift
      /// Space's key-up goes elsewhere once the window is not key, so the pan key is let go here.
      func windowDidResignKey(_ notification: Notification) {
          canvasView.endSpacePan()
      }
  }

  extension EditorWindowController: EditorPresenting {}
  ```
  Nothing else in the file changes.

- [ ] In `TidyShot/App/AppEnvironment.swift`, add the factory between `playShutter` and `now` (:35-36). Replace:
  ```swift
      var playShutter: @MainActor () -> Void
      var now: @Sendable () -> Date
  ```
  with:
  ```swift
      var playShutter: @MainActor () -> Void
      /// Builds an annotation editor over the coordinator's model and actions, titled `title`, with
      /// `representedURL` as its proxy icon, not yet shown. `onClose` runs when its window closes.
      var makeEditor: @MainActor (_ model: EditorModel, _ actions: EditorActions, _ title: String,
                                  _ representedURL: URL?,
                                  _ onClose: @escaping @MainActor (any EditorPresenting) -> Void) -> any EditorPresenting
      var now: @Sendable () -> Date
  ```

- [ ] In the same file, `live()`'s doc comment (:43-46) adds the editor window to its list. Replace:
  ```swift
      /// What the app runs on: the user's Application Support folder (the temporary folder when it
      /// cannot be had), the shared settings, the Keychain, the notification centre, the card stack,
      /// the general pasteboard, S3, the alerts, the shutter sound, the wall clock and `NSLog`. The
      /// collaborators are built in the order the coordinator's stored properties built them.
  ```
  with:
  ```swift
      /// What the app runs on: the user's Application Support folder (the temporary folder when it
      /// cannot be had), the shared settings, the Keychain, the notification centre, the card stack,
      /// the general pasteboard, S3, the alerts, the shutter sound, the editor window, the wall clock
      /// and `NSLog`. The collaborators are built in the order the coordinator's stored properties
      /// built them.
  ```

- [ ] In the same file, add the live closure between `playShutter:` and `now:` (:69-70). Replace:
  ```swift
              playShutter: { SoundPlayer.playShutter() },
              now: { Date() },
  ```
  with:
  ```swift
              playShutter: { SoundPlayer.playShutter() },
              makeEditor: { model, actions, title, representedURL, onClose in
                  // The window as presentEditor built it: cascaded 22 pt from the frontmost editor,
                  // read now, before this one exists. Its close reaches the coordinator's callback.
                  let controller = EditorWindowController(model: model, actions: actions, title: title,
                                                          representedURL: representedURL,
                                                          cascadeFrom: NSApp.orderedWindows.first { $0 is EditorWindow })
                  controller.onClose = { closed in onClose(closed) }
                  return controller
              },
              now: { Date() },
  ```
  The file already imports AppKit (:1), so `NSApp` and `EditorWindow` resolve. The closure is `@MainActor`, not `@Sendable`: it builds an `NSWindowController` and is called only from `presentEditor`, as `confirm` and `playShutter` are (:34-35).

- [ ] In `TidyShot/App/AppCoordinator.swift`, retype the registry (:258-259). Replace:
  ```swift
      /// Open annotation editors, one per record.
      @ObservationIgnored var editors: [UUID: EditorWindowController] = [:]
  ```
  with:
  ```swift
      /// Open annotation editors, one per record: the window in the app, a fake in the suite.
      @ObservationIgnored var editors: [UUID: any EditorPresenting] = [:]
  ```
  `reviewEditorsBeforeQuit` (:466-477) is not edited: its loop variable `controller` is now `any EditorPresenting`, and `model`, `present()`, `askToSaveBeforeClosing()` and `===` all resolve on the protocol.

- [ ] In `TidyShot/App/AppCoordinator+Editor.swift`, reword `presentEditor`'s doc comment (:72-73). Replace:
  ```swift
      /// Builds the model and the window and shows them. `openEditor` and `loadAndPresentEditor`
      /// have checked that no editor is open for the record and that it still exists.
  ```
  with:
  ```swift
      /// Builds the model and, through `environment.makeEditor`, the editor (the window in the app, a
      /// fake in the suite), and shows them. `openEditor` and `loadAndPresentEditor` have checked
      /// that no editor is open for the record and that it still exists.
  ```

- [ ] In the same file, build and present through the factory (:81-89). Replace:
  ```swift
          let controller = EditorWindowController(model: model, actions: editorActions(for: record.id), title: title,
                                                  representedURL: fileURL,
                                                  cascadeFrom: NSApp.orderedWindows.first { $0 is EditorWindow })
          controller.onClose = { [weak self] closed in self?.editorDidClose(closed) }
          editors[record.id] = controller
          pushEditorState(for: record.id)
          observeSaveFolderForEditors()
          Task { await RedactionRenderer.shared.warmUp(with: image.image) }
          controller.present()
  ```
  with:
  ```swift
          let editor = environment.makeEditor(model, editorActions(for: record.id), title, fileURL,
                                              { [weak self] closed in self?.editorDidClose(closed) })
          editors[record.id] = editor
          pushEditorState(for: record.id)
          observeSaveFolderForEditors()
          Task { await RedactionRenderer.shared.warmUp(with: image.image) }
          editor.present()
  ```

- [ ] In the same file, `editorDidClose` takes the protocol (:468-471). Replace:
  ```swift
      /// Drops a closed editor. When the last one closes, the renderer frees its caches.
      private func editorDidClose(_ controller: EditorWindowController) {
          let id = controller.model.recordID
          guard editors[id] === controller else { return }
  ```
  with:
  ```swift
      /// Drops a closed editor. When the last one closes, the renderer frees its caches.
      private func editorDidClose(_ editor: any EditorPresenting) {
          let id = editor.model.recordID
          guard editors[id] === editor else { return }
  ```
  `presentEditor`, `editorActions(for:)` and `editorDidClose` stay `private`.

- [ ] Check the production change:
  ```bash
  git diff --stat a079a6f -- TidyShot/
  grep -rn "EditorWindowController" TidyShot/App/
  git diff a079a6f -- TidyShot/App/AppCoordinator.swift | grep -c '^@@'
  ```
  Expected:
  ```
   TidyShot/App/AppCoordinator+Editor.swift            | 21 ++++++++++-----------
   TidyShot/App/AppCoordinator.swift                   |  4 ++--
   TidyShot/App/AppEnvironment.swift                   | 19 +++++++++++++++++--
   TidyShot/Editor/Window/EditorWindowController.swift | 18 ++++++++++++++++++
   4 files changed, 47 insertions(+), 15 deletions(-)
  TidyShot/App/AppEnvironment.swift:79:                let controller = EditorWindowController(model: model, actions: actions, title: title,
  1
  ```
  (the diffstat's column widths may differ; the four paths and the last line are what count). The one hunk in `AppCoordinator.swift` is the registry's; `reviewEditorsBeforeQuit` is unchanged byte for byte.

#### The fakes and the support file (design 3.1-3.3, catalogue 2.1)

- [ ] Create `TidyShotTests/Support/EditorFakes.swift` (design 3.1, whole). It uses `SingleWaiter` (`init(cancelled: Value, secondEntry: String)`, `var isWaiting: Bool`, `func wait() async -> Value`, `func resume(_ value: Value)`, CoordinatorFakes.swift:374-414), `EditorAvailability.actions(record: CaptureRecord?, saveFolder: URL?, isDeleting: Bool) -> Set<EditorAction>` and `.status(record: CaptureRecord?, saveFolder: URL?, isDeleting: Bool) -> String?` (TidyShot/Editor/Persistence/EditorSaveTarget.swift:121, :149), `EditorSaveCommand.forSave(record: CaptureRecord?, saveFolder: URL?) -> EditorSaveCommand` and `.writeOver` (EditorSaveTarget.swift:78, :73), `EditorUploadOutcome`'s `marksSaved`, `closesWindow(documentUnchanged:)` and `.refused` (TidyShot/Editor/Persistence/EditorUploadPlan.swift:227, :233, :224), `EditorActions`' `save: (ScaledImage) async -> Bool`, `saveAs: (ScaledImage, URL) async -> Bool`, `copy: (ScaledImage) async -> Void` and `upload: (ScaledImage, _ asNew: Bool) async -> EditorUploadOutcome` (EditorWindowController.swift:19-26), `EditorModel`'s `commitTextEditing()` (EditorModel.swift:478), `applyCrop()` (:375), `commitBackgroundDraft()` (:433), `renderExport(displayID:) async throws(EditorExportFailure) -> ScaledImage` (:684), `markSaved()` (:516), `commit(_:actionName:coalescingKey:)` (:195), `base` (:91), `document` (:95) and `hasUnsavedChanges` (:101), and `AnnotationDocument.appending(_:)` (AnnotationDocument.swift:45):
  ```swift
  import Foundation
  import Testing
  @testable import TidyShot

  /// An open editor in the suite: the coordinator's model and actions, every call made on it, the close
  /// sheet's answers; no window. The helpers commit a text being typed first, as every document action
  /// and the sheet do (EditorWindowController.swift:188, :195, :208, :221, :228, :461), and apply results
  /// as the controller does (`exportAndDeliver` :288-296, `performUpload` :268-283); `close()` stands
  /// for `windowWillClose`.
  final class FakeEditor: EditorPresenting {
      /// One push, and what the controller derives from it (recordDidChange, :165-176).
      struct Push: Equatable {
          var record: CaptureRecord?
          var saveFolder: URL?
          var isDeleting: Bool
          var available: Set<EditorAction> {
              EditorAvailability.actions(record: record, saveFolder: saveFolder, isDeleting: isDeleting)
          }
          var status: String? {
              EditorAvailability.status(record: record, saveFolder: saveFolder, isDeleting: isDeleting)
          }
          var saveCommand: EditorSaveCommand { EditorSaveCommand.forSave(record: record, saveFolder: saveFolder) }
      }
      enum Call: Equatable { case present, askToSave, recordDidChange(Push) }
      /// A close sheet's answer. `Sendable` because `SingleWaiter` carries it.
      nonisolated enum CloseAnswer: Equatable, Sendable {
          case save, dontSave, cancel
          case saveAs(URL)
      }
      let model: EditorModel
      let actions: EditorActions
      let title: String
      let representedURL: URL?
      private let onClose: @MainActor (any EditorPresenting) -> Void
      private(set) var calls: [Call] = []
      private(set) var isClosed = false
      /// The close sheet's answers, in order; Cancel when they run out.
      var closeAnswers: [CloseAnswer] = []
      /// While set, the sheet stays up until `answer(_:)`. Its task cancelled (the test's `defer`) or a
      /// second sheet while one is up: Cancel.
      var holdsCloseSheet = false
      private let sheet = SingleWaiter(cancelled: CloseAnswer.cancel,
                                       secondEntry: "FakeEditor's close sheet was asked for again while it was up")
      init(model: EditorModel, actions: EditorActions, title: String, representedURL: URL?,
           onClose: @escaping @MainActor (any EditorPresenting) -> Void) {
          self.model = model
          self.actions = actions
          self.title = title
          self.representedURL = representedURL
          self.onClose = onClose
      }
      var presentCount: Int { calls.filter { $0 == .present }.count }
      var pushes: [Push] {
          calls.compactMap { call -> Push? in
              guard case .recordDidChange(let push) = call else { return nil }
              return push
          }
      }
      var isAsking: Bool { sheet.isWaiting }

      // MARK: EditorPresenting
      func present() { calls.append(.present) }
      func recordDidChange(_ record: CaptureRecord?, saveFolder: URL?, isDeleting: Bool) {
          calls.append(.recordDidChange(Push(record: record, saveFolder: saveFolder, isDeleting: isDeleting)))
      }
      /// As the live sheet (:460-492): true with nothing to save, else the answer carried out.
      func askToSaveBeforeClosing() async -> Bool {
          calls.append(.askToSave)
          model.commitTextEditing()
          guard model.hasUnsavedChanges else { return true }
          let answer: CloseAnswer
          if holdsCloseSheet {
              answer = await sheet.wait()
          } else {
              answer = closeAnswers.isEmpty ? .cancel : closeAnswers.removeFirst()
          }
          switch answer {
          case .save:
              // The live first button writes over only when the last push allows Save and ⌘S writes over
              // (:467-468, performSave :247-254); otherwise it is Save As…, or Save opening the panel.
              guard let push = pushes.last, push.available.contains(.save), push.saveCommand == .writeOver else {
                  Issue.record("FakeEditor's sheet was answered Save where the live first button opens the save panel")
                  return false
              }
              return await save()
          case .saveAs(let url): return await saveAs(to: url)
          case .dontSave: return true
          case .cancel: return false
          }
      }
      func answer(_ answer: CloseAnswer) {
          holdsCloseSheet = false
          sheet.resume(answer)
      }

      // MARK: The user
      /// The window closed: the coordinator's `onClose`, as `windowWillClose(_:)` calls it.
      func close() {
          isClosed = true
          onClose(self)
      }
      /// A blue box over the whole capture, committed as a tool does on mouseUp.
      func draw() {
          let size = CGSize(width: model.base.width, height: model.base.height)
          let box = ShapeBox(id: UUID(), rect: CGRect(origin: .zero, size: size), color: RGBA(red: 0, green: 0, blue: 1),
                             lineWidth: max(size.width, size.height))
          model.commit(model.document.appending(.rectangle(box)), actionName: "Add")
      }
      /// The export and its document: a text being typed committed, then a pending crop and background
      /// draft applied (:301-317).
      func export() async -> (image: ScaledImage, document: AnnotationDocument)? {
          model.commitTextEditing()
          model.applyCrop()
          model.commitBackgroundDraft()
          let document = model.document
          guard let image = try? await model.renderExport() else { return nil }
          return (image, document)
      }
      /// ⌘S writing over; skips the window's validation, so a test reaches the coordinator's own check.
      @discardableResult
      func save() async -> Bool {
          guard let (image, exported) = await export() else { return false }
          guard await actions.save(image) else { return false }
          if model.document == exported { model.markSaved() }
          return true
      }
      @discardableResult
      func saveAs(to url: URL) async -> Bool {
          guard let (image, exported) = await export() else { return false }
          guard await actions.saveAs(image, url) else { return false }
          if model.document == exported { model.markSaved() }
          return true
      }
      /// Copy (⌘C, ⇧⌘C): never marks saved.
      func copy() async {
          guard let (image, _) = await export() else { return }
          await actions.copy(image)
      }
      /// ⌘U, or ⌥⌘U with `asNew`: saved and closed as the outcome says, given whether anything changed.
      @discardableResult
      func upload(asNew: Bool = false) async -> EditorUploadOutcome {
          guard let (image, exported) = await export() else { return .refused }
          let outcome = await actions.upload(image, asNew)
          let unchanged = model.document == exported
          if outcome.marksSaved, unchanged { model.markSaved() }
          if outcome.closesWindow(documentUnchanged: unchanged) { close() }
          return outcome
      }
  }

  /// `environment.makeEditor` in the suite: every editor built, in order, kept after it closes.
  final class FakeEditors {
      private(set) var built: [FakeEditor] = []
      func make(model: EditorModel, actions: EditorActions, title: String, representedURL: URL?,
                onClose: @escaping @MainActor (any EditorPresenting) -> Void) -> any EditorPresenting {
          let editor = FakeEditor(model: model, actions: actions, title: title, representedURL: representedURL,
                                  onClose: onClose)
          built.append(editor)
          return editor
      }
      /// The newest editor built for `id`.
      func editor(for id: UUID) -> FakeEditor? {
          built.last { $0.model.recordID == id }
      }
  }
  ```
  The `EditorWindowController.swift` line numbers in its comments are the controller's at a079a6f, as design 3.1 gives them; after this task's 16-line protocol insertion each of those lines is 16 further down the file; the comments are kept as the design has them (D15).

- [ ] Create `TidyShotTests/Support/EditorPixels.swift` (catalogue 2.1, as built). It uses `ImageEncoder.pngData(from image: CGImage, scale: CGFloat) throws -> Data` (TidyShot/Output/ImageEncoder.swift:21), `ImageEncoder.decode(_ data: Data) -> (image: CGImage, scale: CGFloat)?` (:42) and `CoordinatorWorld.image(width:height:) throws -> CGImage` (CoordinatorWorld.swift:170):
  ```swift
  import CoreGraphics
  import Foundation
  import ImageIO
  import Testing
  @testable import TidyShot

  /// Pixel reads for the editor-seam tests (tests-editor.md 2.1). Test support only.
  nonisolated enum EditorPixels {
      static func image(width: Int, height: Int, white: Bool = false) throws -> CGImage {
          let context = try #require(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                               space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                               bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
          context.setFillColor(white ? CGColor(red: 1, green: 1, blue: 1, alpha: 1) : CGColor(red: 1, green: 0, blue: 0, alpha: 1))
          context.fill(CGRect(x: 0, y: 0, width: width, height: height))
          return try #require(context.makeImage())
      }

      static func png(width: Int, height: Int, scale: CGFloat, white: Bool = false) throws -> Data {
          try ImageEncoder.pngData(from: image(width: width, height: height, white: white), scale: scale)
      }

      static func decoded(_ png: Data) throws -> (image: CGImage, scale: CGFloat) {
          try #require(ImageEncoder.decode(png))
      }

      static func dpiWidth(of png: Data) -> Double? {
          guard let source = CGImageSourceCreateWithData(png as CFData, nil),
                let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else { return nil }
          return props[kCGImagePropertyDPIWidth] as? Double
      }

      static func rgba(_ image: CGImage) -> [UInt8] {
          let width = image.width, height = image.height
          var bytes = [UInt8](repeating: 0, count: width * height * 4)
          bytes.withUnsafeMutableBytes { buffer in
              let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
              context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
          }
          return bytes
      }

      static func pixel(_ image: CGImage, x: Int, y: Int) -> [Int] {
          let bytes = rgba(image)
          let base = (y * image.width + x) * 4
          return (0..<4).map { Int(bytes[base + $0]) }
      }

      static func pixel(_ png: Data, x: Int, y: Int) throws -> [Int] {
          pixel(try decoded(png).image, x: x, y: y)
      }

      static func changedPixels(_ image: CGImage, in rect: CGRect, from rgb: [Int]) -> Int {
          let bounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
          let area = rect.integral.intersection(bounds)
          guard !area.isNull, !area.isEmpty else { return 0 }
          let bytes = rgba(image)
          var count = 0
          for y in Int(area.minY)..<Int(area.maxY) {
              for x in Int(area.minX)..<Int(area.maxX) {
                  let base = (y * image.width + x) * 4
                  if (0..<3).contains(where: { abs(Int(bytes[base + $0]) - rgb[$0]) > 16 }) { count += 1 }
              }
          }
          return count
      }

      /// The world's red as it reads back: `CoordinatorWorld.image` fills with a Generic RGB red, so an sRGB
      /// read gives [255, 38, 0, 255], not [255, 0, 0, 255].
      @MainActor static func worldRed() throws -> [Int] { pixel(try CoordinatorWorld.image(width: 1, height: 1), x: 0, y: 0) }

      static func isBlue(_ pixel: [Int]) -> Bool { pixel[0] < 40 && pixel[1] < 40 && pixel[2] > 200 }

      static func isBlue(_ image: CGImage) -> Bool {
          var bytes = [UInt8](repeating: 0, count: 4)
          bytes.withUnsafeMutableBytes { buffer in
              let context = CGContext(data: buffer.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
              context.draw(image, in: CGRect(x: 0, y: 0, width: 1, height: 1))
          }
          return isBlue(bytes.map(Int.init))
      }

      static func isBlue(png: Data) throws -> Bool { isBlue(try decoded(png).image) }
  }
  ```

- [ ] In `TidyShotTests/Support/CoordinatorFakes.swift`, `FakeClipboard` keeps the PNG of every image copy (design 3.2). Replace (:167-173):
  ```swift
      private(set) var copies: [Copy] = []
      var changeCount = 0
      var annotationClip: Data?

      func setString(_ string: String) { write(.string(string)) }
      func copy(image: CGImage, pngData: Data, scale: CGFloat) -> Int { write(.image) }
      func copy(pngData: Data, tiffData: Data?) -> Int { write(.pngAndTIFF) }
  ```
  with:
  ```swift
      private(set) var copies: [Copy] = []
      /// The PNG of every `.image` and `.pngAndTIFF` copy, in order (what Preview's New from Clipboard reads).
      private(set) var pngs: [Data] = []
      var changeCount = 0
      var annotationClip: Data?

      func setString(_ string: String) { write(.string(string)) }
      func copy(image: CGImage, pngData: Data, scale: CGFloat) -> Int { pngs.append(pngData); return write(.image) }
      func copy(pngData: Data, tiffData: Data?) -> Int { pngs.append(pngData); return write(.pngAndTIFF) }
  ```
  No existing `copies ==` expectation changes: `copies` is appended exactly as before.

- [ ] In `TidyShotTests/Support/CoordinatorWorld.swift`, the header comment (:11-17) adds the editors (D9). Replace:
  ```swift
  /// A coordinator's world in the suite (harness design 2.4): temp folders, a `UserDefaults` suite named
  /// after the test, settings and a save location over it, credentials in memory, the fakes, a clock the
  /// test moves, a date it sets, free space it sets, a log it reads and a destination factory. Build it in
  /// the suite's `init`, make the coordinator with `makeCoordinator()`, and `defer { world.removeAll() }`
  /// first thing in each test. Nothing here reaches the system, except the `ProcessInfo` activity
  /// (`Uploading a recording`) the coordinator begins while `fileUploadIDs` is not empty: the design
  /// leaves `ProcessInfo` activities out of the environment (2.1, Deferred), and it ends when the set empties.
  ```
  with:
  ```swift
  /// A coordinator's world in the suite (harness design 2.4): temp folders, a `UserDefaults` suite named
  /// after the test, settings and a save location over it, credentials in memory, the fakes, the editors
  /// the coordinator opens (`editors`; no window is built), a clock the test moves, a date it sets, free
  /// space it sets, a log it reads and a destination factory. Build it in the suite's `init`, make the
  /// coordinator with `makeCoordinator()`, and `defer { world.removeAll() }` first thing in each test.
  /// Nothing here reaches the system, except the `ProcessInfo` activity (`Uploading a recording`) the
  /// coordinator begins while `fileUploadIDs` is not empty: the design leaves `ProcessInfo` activities out
  /// of the environment (2.1, Deferred), and it ends when the set empties.
  ```

- [ ] In the same file, add the editors after `let confirm = FakeConfirm()` (:41). Replace:
  ```swift
      let confirm = FakeConfirm()
      /// The coordinator's clock, and its self-timer's.
  ```
  with:
  ```swift
      let confirm = FakeConfirm()
      /// Every editor the coordinator opened (`environment.makeEditor`); no window is built.
      let editors = FakeEditors()
      /// The coordinator's clock, and its self-timer's.
  ```

- [ ] In the same file, in `var environment`, capture the editors after `let confirm = confirm` (:108). Replace:
  ```swift
          let confirm = confirm
          return AppEnvironment(
  ```
  with:
  ```swift
          let confirm = confirm
          let editors = editors
          return AppEnvironment(
  ```

- [ ] In the same file, pass the factory after `playShutter:` (:123). Replace:
  ```swift
              playShutter: { [weak self] in self?.shutterCount += 1 },
              now: { state.date },
  ```
  with:
  ```swift
              playShutter: { [weak self] in self?.shutterCount += 1 },
              makeEditor: { model, actions, title, representedURL, onClose in
                  editors.make(model: model, actions: actions, title: title, representedURL: representedURL,
                               onClose: onClose)
              },
              now: { state.date },
  ```
  `makeCoordinator()` and `removeAll()` need nothing: no fake owns a window. A second coordinator over the same world appends to the same `built` list, and `editor(for:)` returns the newest.

#### `CoordinatorEditorTests`: header, helpers and two tests

- [ ] In `TidyShotTests/CoordinatorEditorTests.swift`, add `import CoreGraphics` (D8) and reword the header (design 4, catalogue 5). Replace (:1-7):
  ```swift
  import Foundation
  import Testing
  @testable import TidyShot

  /// The editor's load on a built coordinator (`AppCoordinator+Editor`): `loadImage(for:)`, and an Annotate
  /// whose load fails. Presenting the window builds an `EditorWindowController`, which reads the screens;
  /// that is the editor seam's, and no test here reaches it.
  ```
  with:
  ```swift
  import CoreGraphics
  import Foundation
  import Testing
  @testable import TidyShot

  /// The editor bridge on a built coordinator (`AppCoordinator+Editor`): `loadImage(for:)`, an Annotate whose
  /// load fails, and an open editor: its opening, the card, what it hears while things happen, and the quit
  /// review. Presenting goes through `environment.makeEditor`, which here builds a `FakeEditor`
  /// (`world.editors`) and no window, so nothing in this suite reads the screens.
  ```

- [ ] In the same file, add the suite's helpers after `var link: URL { … }` (:18) and before `nonisolated enum Kept` (:20) (D4, D5). `key` (:11), `destination` (:17) and `link` (:18) are already there and do not change. Replace:
  ```swift
      var destination: FakeDestination { world.factory.standard }
      var link: URL { URL(string: "https://snap.tky.io/\(key)")! }

      nonisolated enum Kept: CaseIterable, Sendable {
  ```
  with:
  ```swift
      var destination: FakeDestination { world.factory.standard }
      var link: URL { URL(string: "https://snap.tky.io/\(key)")! }
      var all: Set<EditorAction> { Set(EditorAction.allCases) }
      var green: RGBA { RGBA(red: 0, green: 1, blue: 0) }
      var background: BackgroundStyle {
          BackgroundStyle(fill: .solid(green), padding: 8, cornerRadius: 0, shadow: false, aspect: .auto)
      }

      func publicURL(_ key: String) -> URL { URL(string: "https://snap.tky.io/\(key)")! }

      func openedEditor(_ id: UUID) async throws -> FakeEditor {
          try await eventually { world.editors.editor(for: id) != nil }
          return try #require(world.editors.editor(for: id))
      }

      func reopenedEditor(_ id: UUID, after first: FakeEditor) async throws -> FakeEditor {
          try await eventually { world.editors.editor(for: id).map { $0 !== first } ?? false }
          return try #require(world.editors.editor(for: id))
      }

      /// The last edit's thumbnail named on the record (`replaceThumbnail(for:from:editedAt:)` in
      /// `AppCoordinator+Editor`), so its task does not outlive the test.
      func settledEdit(_ coordinator: AppCoordinator, _ id: UUID) async throws {
          try await eventually {
              coordinator.history.record(id: id)?.thumbnailFileName == coordinator.thumbnails.fileName(for: id, editedAt: world.date)
          }
      }

      func addSavedImage(to coordinator: AppCoordinator, in folder: URL, name: String = "Shot.png",
                         uploadState: CaptureRecord.UploadState = .none, objectLocation: ObjectLocation? = nil,
                         uploadIsStale: Bool = false, timestamp: Date = Date(),
                         scale: CGFloat = 1) throws -> (record: CaptureRecord, original: Data) {
          let original = try ImageEncoder.pngData(from: CoordinatorWorld.image(width: 4, height: 2), scale: scale)
          let file = folder.appending(path: name)
          try original.write(to: file)
          let record = CaptureRecord(timestamp: timestamp, fileURL: file, pixelWidth: 4, pixelHeight: 2, appName: nil,
                                     uploadState: uploadState, objectLocation: objectLocation,
                                     uploadIsStale: uploadIsStale, byteCount: original.count)
          coordinator.history.add(record)
          return (record, original)
      }

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

      func desktop(_ name: String) throws -> URL {
          let folder = world.root.appending(path: "Desktop", directoryHint: .isDirectory)
          try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
          return folder.appending(path: name)
      }

      func pendingURL(_ coordinator: AppCoordinator, _ id: UUID) -> URL {
          coordinator.pendingFiles.directory.appending(path: "\(id.uuidString).png")
      }

      func addUploadOnly(to coordinator: AppCoordinator) throws -> CaptureRecord {
          let png = try CoordinatorWorld.pngData(width: 4, height: 2)
          destination.state.withLock { $0.downloadedData = png }
          let record = CaptureRecord(fileURL: nil, pixelWidth: 4, pixelHeight: 2, appName: nil,
                                     uploadState: .uploaded(url: link, key: key), objectLocation: world.location)
          coordinator.history.add(record)
          return record
      }

      func isUploaded(_ coordinator: AppCoordinator, _ id: UUID) -> Bool {
          if case .uploaded = coordinator.history.record(id: id)?.uploadState { return true }
          return false
      }

      func title(of record: CaptureRecord) -> String {
          "Capture \(record.timestamp.formatted(date: .omitted, time: .shortened))"
      }

      func exists(_ url: URL) -> Bool { FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) }

      func crop(_ model: EditorModel, to rect: CGRect, apply: Bool) {
          model.tool = .crop
          model.cropDraft = rect
          if apply { model.applyCrop() }
      }

      func addText(_ model: EditorModel, _ string: String, at point: CGPoint) throws -> TextBox {
          model.beginTextEditing(at: point, existing: nil)
          model.updateEditingText(string)
          model.commitTextEditing()
          for annotation in model.document.annotations {
              if case .text(let box) = annotation { return box }
          }
          throw CoordinatorWorldError.noFile
      }

      nonisolated enum Kept: CaseIterable, Sendable {
  ```
  The members they reach exist at dd1231d with these signatures: `CaptureRecord.init(id: UUID = UUID(), timestamp: Date = Date(), fileURL: URL?, fileIsTemporary: Bool = false, thumbnailFileName: String? = nil, pixelWidth: Int, pixelHeight: Int, appName: String?, uploadState: UploadState = .none, objectLocation: ObjectLocation? = nil, pendingObjectKey: String? = nil, editedAt: Date? = nil, uploadIsStale: Bool = false, supersededObjects: [ObjectRef] = [], priorUpload: PriorUpload? = nil, mediaKind: MediaKind = .image, durationSeconds: Double? = nil, byteCount: Int? = nil, unmutedIntervals: [MuteInterval] = [], multipart: MultipartUploadState? = nil)` (TidyShot/History/CaptureRecord.swift:114-119); `ImageEncoder.pngData(from:scale:)` (TidyShot/Output/ImageEncoder.swift:21); `ThumbnailStore.fileName(for id: UUID, editedAt: Date?) -> String` (TidyShot/History/ThumbnailStore.swift:28); `PendingFileStore.directory` (TidyShot/Output/PendingFileStore.swift:9); `EditorModel.tool` (EditorModel.swift:126), `cropDraft` (:119), `beginTextEditing(at:existing:)` (:453), `updateEditingText(_:)` (:469); `BackgroundStyle.init(fill:padding:cornerRadius:shadow:aspect:)` (TidyShot/Background/BackgroundStyle.swift:15-16); `CoordinatorWorldError.noFile` (CoordinatorWorld.swift:8). Tasks 6 and 7 call these helpers; this task's two tests use `openedEditor` and `addPendingImage`.

- [ ] In the same file, add the two tests before the closing `}` of `struct CoordinatorEditorTests` (:93), after `annotateOnAMovedPrePhase3FileSaysCouldNotOpenAndOpensNoEditor`. Replace the end of the file (:90-93):
  ```swift
          #expect(coordinator.editors.isEmpty)
          #expect(destination.state.withLock { $0.dataDownloadKeys.isEmpty })
      }
  }
  ```
  with:
  ```swift
          #expect(coordinator.editors.isEmpty)
          #expect(destination.state.withLock { $0.dataDownloadKeys.isEmpty })
      }

      /// phase-4a:39 (:43), in part. A second Annotate while the capture's image loads opens nothing more
      /// (`openingEditorIDs`); once the editor is open, Annotate on the same capture calls `present()` on the
      /// registered editor again, builds no second one, pushes no second state and closes the card only once.
      /// Stays: the window coming forward, by hand. It is `present()`'s own body in `EditorWindowController`,
      /// which the fake records and does not run; ordering a window front is barred in the suite, so no seam
      /// reaches it.
      @Test func annotateOnACaptureWhoseEditorIsOpenBringsItForwardAndBuildsNoSecond() async throws {
          defer { world.removeAll() }
          let coordinator = world.makeCoordinator()
          let record = try addPendingImage(to: coordinator)
          let id = record.id
          coordinator.openEditor(recordID: id)
          coordinator.openEditor(recordID: id)
          #expect(coordinator.openingEditorIDs == [id])
          #expect(world.editors.built.isEmpty)
          let editor = try await openedEditor(id)
          try await eventually { coordinator.openingEditorIDs.isEmpty }
          #expect(world.editors.built.count == 1)
          #expect(editor.presentCount == 1)
          #expect(coordinator.editors[id] === editor)
          coordinator.openEditor(recordID: id)
          #expect(world.editors.built.count == 1)
          #expect(editor.presentCount == 2)
          #expect(editor.calls.last == .present)
          #expect(editor.pushes.count == 1)
          #expect(world.cards.calls.filter { $0 == .close(id, .editorOpened) }.count == 1)
      }

      /// phase-4a:155 (:223), in part. The quit holds only while an editor has unsaved changes, and the quit
      /// review asks only the changed editor: it comes forward and shows its sheet. Cancel stops the quit and
      /// leaves the editor registered and changed; a second review answered Don't Save lets the quit go,
      /// leaves the pending file as it was and closes nothing. The clean editor is never asked.
      /// Stays: the sheet itself (`CLOSESHEET`); the real quit's reply (`APPDELEGATE`).
      @Test func quitAsksEachChangedEditorCancelStopsItDontSaveLetsItGo() async throws {
          defer { world.removeAll() }
          let coordinator = world.makeCoordinator()
          let changed = try addPendingImage(to: coordinator)
          let clean = try addPendingImage(to: coordinator)
          let pending = try #require(changed.fileURL)
          let original = try Data(contentsOf: pending)
          coordinator.openEditor(recordID: changed.id)
          coordinator.openEditor(recordID: clean.id)
          let editor = try await openedEditor(changed.id)
          let other = try await openedEditor(clean.id)
          #expect(!coordinator.quitNeedsHold)
          editor.draw()
          #expect(coordinator.quitNeedsHold)
          editor.holdsCloseSheet = true

          let first = Task { await coordinator.reviewEditorsBeforeQuit() }
          defer { first.cancel() }
          let firstWatch = TaskWatch(first)
          try await eventually { editor.isAsking }
          #expect(Array(editor.calls.suffix(2)) == [.present, .askToSave])
          editor.answer(.cancel)
          try await eventually { firstWatch.hasReturned }
          let proceeded = await first.value

          #expect(!proceeded)
          #expect(coordinator.editors[changed.id] === editor)
          #expect(editor.model.hasUnsavedChanges)
          #expect(!other.calls.contains(.askToSave))

          editor.closeAnswers = [.dontSave]
          let second = Task { await coordinator.reviewEditorsBeforeQuit() }
          defer { second.cancel() }
          let secondWatch = TaskWatch(second)
          try await eventually { secondWatch.hasReturned }
          let quits = await second.value

          #expect(quits)
          #expect(editor.calls.filter { $0 == .askToSave }.count == 2)
          #expect(try Data(contentsOf: pending) == original)
          #expect(editor.model.hasUnsavedChanges)
          #expect(!editor.isClosed)
          #expect(!other.calls.contains(.askToSave))
      }
  }
  ```
  Neither test's action reaches `applyLocalEdit` (no Save, no Upload; Don't Save writes nothing), so neither needs `settledEdit`. The quit test's held review is gated by `TaskWatch` (CoordinatorFakes.swift:420-429) and cancelled in a `defer` registered right after the task is made, so a failure before `answer(.cancel)` ends the held sheet as Cancel (`SingleWaiter`, CoordinatorFakes.swift:393-400). Both reach `presentEditor`'s warm-up of `RedactionRenderer.shared`; neither commits an effect (design 5).

#### Runs, the Release build and the commit

- [ ] Run the suite alone:
  ```bash
  xcodegen generate && xcodebuild test -project TidyShot.xcodeproj -scheme TidyShot -destination 'platform=macOS' -derivedDataPath .build -only-testing:TidyShotTests/CoordinatorEditorTests 2>&1 | grep -E "Test run with|error:|TEST"
  ```
  Expected: `✔ Test run with 4 tests in 1 suite passed after …` (the 2 existing tests and these 2) and `** TEST SUCCEEDED **`. The `error:` lines that print are noise, not failures: the known `com.apple.linkd.autoShortcut` and `mdb_txn_commit error: MDB_MAP_FULL` lines, and on a machine whose CoreSimulator is older than Xcode's, one `xcodebuild[…] iOSSimulator: [SimServiceContext sharedServiceContextForDeveloperDir:error:] returned nil … Simulator device support disabled.` line, which the baseline prints too.

- [ ] Run the full suite:
  ```bash
  xcodegen generate && xcodebuild test -project TidyShot.xcodeproj -scheme TidyShot -destination 'platform=macOS' -derivedDataPath .build 2>&1 | grep -E "Test run with|error:|TEST"
  ```
  Expected: `✔ Test run with 2274 tests in 191 suites passed after …` and `** TEST SUCCEEDED **`. The `error:` lines that print are noise only: `History file could not be read or decoded, setting it aside` twice, `com.apple.linkd.autoShortcut`, about 40 `mdb_txn_commit error: MDB_MAP_FULL`, and the `iOSSimulator: … sharedServiceContextForDeveloperDir:error:` line where CoreSimulator is out of date. The run takes 45 s to 130 s.

- [ ] Run the Release build (this is the only task that changes `TidyShot/`):
  ```bash
  xcodegen generate && xcodebuild -project TidyShot.xcodeproj -scheme TidyShot -configuration Release -derivedDataPath .build-rel build 2>&1 | grep -E "error:|warning:|BUILD"
  ```
  Expected: `** BUILD SUCCEEDED **`, and no `error:` or `warning:` line from the compiler or the linker. Two tool lines may print and are not the change's: `xcodebuild[…] iOSSimulator: [SimServiceContext sharedServiceContextForDeveloperDir:error:] returned nil …` (CoreSimulator older than Xcode) and `appintentsmetadataprocessor[…] warning: Metadata extraction skipped, no AppIntents.framework dependency found`; the unchanged tree at dd1231d prints the same two. Any other `error:` or `warning:` line, for example a Swift concurrency warning in `AppEnvironment.swift`, is a failure: stop and report it.

- [ ] Assert the production diff is the seam's four files only:
  ```bash
  git diff --stat a079a6f -- TidyShot/
  git status --short
  ```
  Expected: the diffstat lists exactly `TidyShot/App/AppCoordinator+Editor.swift`, `TidyShot/App/AppCoordinator.swift`, `TidyShot/App/AppEnvironment.swift` and `TidyShot/Editor/Window/EditorWindowController.swift`, and ends `4 files changed, 47 insertions(+), 15 deletions(-)`. `git status --short` lists those four as ` M`, ` M TidyShotTests/CoordinatorEditorTests.swift`, ` M TidyShotTests/Support/CoordinatorFakes.swift`, ` M TidyShotTests/Support/CoordinatorWorld.swift`, `?? TidyShotTests/Support/EditorFakes.swift` and `?? TidyShotTests/Support/EditorPixels.swift`, and nothing else (`TidyShot.xcodeproj`, `TidyShot/Info.plist`, `TidyShot/TidyShot.entitlements`, `.build/` and `.build-rel/` are git-ignored).

- [ ] Commit:
  ```bash
  git add TidyShot/App/AppCoordinator+Editor.swift TidyShot/App/AppCoordinator.swift TidyShot/App/AppEnvironment.swift TidyShot/Editor/Window/EditorWindowController.swift TidyShotTests/CoordinatorEditorTests.swift TidyShotTests/Support/CoordinatorFakes.swift TidyShotTests/Support/CoordinatorWorld.swift TidyShotTests/Support/EditorFakes.swift TidyShotTests/Support/EditorPixels.swift
  git commit -m "refactor: the coordinator's editor through AppEnvironment.makeEditor, its fakes, two editor tests"
  ```
  No attribution lines and no session URL in the message; do not push. The report says no hand check was run.

### Task 2: `CoordinatorEditorSaveTests`, Save over the file [integration]

**Files:**
- Create `TidyShotTests/CoordinatorEditorSaveTests.swift`: imports `CoreGraphics`, `Foundation`, `Testing`, `@testable import TidyShot`; the header the catalogue's section 3 gives; `@Suite(.timeLimit(.minutes(1))) struct CoordinatorEditorSaveTests` with `let world: CoordinatorWorld`, `init() throws { world = try CoordinatorWorld() }`, the suite's helpers (D4), then the tests.

**Interfaces:**
- Consumes (Task 1): `FakeEditor` (`draw()`, `save()`, `export()`, `close()`, `model`, `pushes` (with `Push`'s `record`, `saveFolder`, `isDeleting`, `available`, `status`, `saveCommand`), `presentCount`, `title`, `representedURL`), `world.editors` (`built`, `editor(for:)`), `world.clipboard.pngs`, `coordinator.editors`, `EditorPixels.changedPixels`, `.decoded`, `.dpiWidth`, `.isBlue`, `.pixel`, `.png`, `.rgba`; the harness as in Task 1's Consumes.
- Produces, the suite's helpers (`key`, `link`, `destination`, `all`, `publicURL`, `openedEditor`, `reopenedEditor`, `settledEdit`, `addSavedImage`, `addPendingImage`, `desktop`, `pendingURL`, `addUploadOnly`, `isUploaded`, `title(of:)`, `exists`, `crop`, `addText`, `expected`, `green`, `background`), used by Task 3:
  ```swift
  let key = "s/SHOT.png"
  var link: URL { URL(string: "https://snap.tky.io/\(key)")! }
  var destination: FakeDestination { world.factory.standard }
  var all: Set<EditorAction> { Set(EditorAction.allCases) }
  func publicURL(_ key: String) -> URL
  func openedEditor(_ id: UUID) async throws -> FakeEditor
  func reopenedEditor(_ id: UUID, after first: FakeEditor) async throws -> FakeEditor
  func settledEdit(_ coordinator: AppCoordinator, _ id: UUID) async throws
  func addSavedImage(to coordinator: AppCoordinator, in folder: URL, name: String = "Shot.png", uploadState: CaptureRecord.UploadState = .none, objectLocation: ObjectLocation? = nil, uploadIsStale: Bool = false, timestamp: Date = Date(), scale: CGFloat = 1) throws -> (record: CaptureRecord, original: Data)
  func addPendingImage(to coordinator: AppCoordinator) throws -> CaptureRecord
  func desktop(_ name: String) throws -> URL
  func pendingURL(_ coordinator: AppCoordinator, _ id: UUID) -> URL
  func addUploadOnly(to coordinator: AppCoordinator) throws -> CaptureRecord
  func isUploaded(_ coordinator: AppCoordinator, _ id: UUID) -> Bool
  func title(of record: CaptureRecord) -> String
  func exists(_ url: URL) -> Bool
  func crop(_ model: EditorModel, to rect: CGRect, apply: Bool)
  func addText(_ model: EditorModel, _ string: String, at point: CGPoint) throws -> TextBox
  func expected(_ editor: FakeEditor) async throws -> CGImage
  var green: RGBA { RGBA(red: 0, green: 1, blue: 0) }
  var background: BackgroundStyle { BackgroundStyle(fill: .solid(green), padding: 8, cornerRadius: 0, shadow: false, aspect: .auto) }
  ```
- Produces, the argument type `nonisolated enum Link: CaseIterable, Sendable { case afterPhase3, beforePhase3 }`, directly before `saveOverAnUploadedCaptureRewritesTheFileOnlyAndMarksItsLinkStale(link:)`.

**Tests:**
1. `saveWritesOverTheSaveFolderFileAndUploadsNothing`: catalogue section 3 (CoordinatorEditorSaveTests.swift), "Save over the file", tests-editor.md:386; effort M.
2. `saveOverAnUploadedCaptureRewritesTheFileOnlyAndMarksItsLinkStale(link:)`: catalogue section 3 (CoordinatorEditorSaveTests.swift), "Save over the file", tests-editor.md:416; effort S.
3. `saveOverALockedFileSaysNotSavedAndPutsTheEditOnTheClipboard`: catalogue section 3 (CoordinatorEditorSaveTests.swift), "Save over the file", tests-editor.md:433; effort S.
4. `saveOnAFailedUploadOnlyCaptureRewritesPendingAndRetryUploadsTheEdit`: catalogue section 3 (CoordinatorEditorSaveTests.swift), "Save over the file", tests-editor.md:451; effort M.
5. `saveWithACropWritesTheCroppedSizeAtTheCapturesScaleAndReopensCropped(scale:)`: catalogue section 3 (CoordinatorEditorSaveTests.swift), "Save over the file", tests-editor.md:483; effort M.
6. `saveWithTextEllipseAndCropWritesAllThreeIntoTheSameFile`: catalogue section 3 (CoordinatorEditorSaveTests.swift), "Save over the file", tests-editor.md:526; effort M.
7. `saveWithABackgroundWritesTheComposedCanvasAndReopensFlat`: catalogue section 3 (CoordinatorEditorSaveTests.swift), "Save over the file", tests-editor.md:551; effort M.
8. `saveOverTheFileRemovesTheDragCopyAndEveryReadGivesTheEdit`: catalogue section 3 (CoordinatorEditorSaveTests.swift), "Save over the file", tests-editor.md:586; effort M.
- 8 tests (S 2, M 6), 2 parameterized.
- Focused run, `-only-testing:TidyShotTests/CoordinatorEditorSaveTests`: `Test run with 8 tests in 1 suite passed`.
- Full suite: `Test run with 2282 tests in 192 suites passed`.

**Commit:** `test: the editor's Save over the file through the editor seam`

**Steps:**

- [ ] **Step 1: Check the starting point.** Task 1 is committed and the new file does not exist yet. Run:
  ```bash
  git log -1 --format=%s
  git status --short
  grep -n "let editors = FakeEditors()" TidyShotTests/Support/CoordinatorWorld.swift
  grep -n "private(set) var pngs: \[Data\]" TidyShotTests/Support/CoordinatorFakes.swift
  grep -n "^nonisolated enum EditorPixels" TidyShotTests/Support/EditorPixels.swift
  grep -n "^final class FakeEditor: EditorPresenting" TidyShotTests/Support/EditorFakes.swift
  test -e TidyShotTests/CoordinatorEditorSaveTests.swift && echo exists || echo absent
  ```
  Expected: the first line is `refactor: the coordinator's editor through AppEnvironment.makeEditor, its fakes, two editor tests`; `git status --short` prints nothing; each `grep` prints one line; the last line is `absent`. If any differs, stop and report: this task builds on Task 1 only.

- [ ] **Step 2: Know what the file calls.** Every name below exists with this signature; nothing in this task adds to or changes them. At dd1231d (line numbers are dd1231d's):
  - `func eventually(_ condition: () async -> Bool) async throws` (TidyShotTests/UploadQueueTests.swift:42; 200 tries 10 ms apart, then throws `EventuallyTimedOut`).
  - `CoordinatorWorld` (TidyShotTests/Support/CoordinatorWorld.swift): `init() throws`; `let root: URL` (:25); `let notifier = FakeNotifier()`, `let cards = FakeCards()`, `let clipboard = FakeClipboard()` (:38-40); `let factory = FakeDestinationFactory()` (:44); `var location: ObjectLocation` (:90); `var date: Date` (:92-95); `var logLines: [String]` (:103); `func makeCoordinator() -> AppCoordinator` (:131); `func removeAll()` (:141); `@discardableResult func storeSaveFolder() throws -> URL` (:150-151, `<root>/Saved/`); `static func image(width: Int, height: Int) throws -> CGImage` (:170, red); `static func pngData(width: Int, height: Int) throws -> Data` (:180, scale 1); `nonisolated enum CoordinatorWorldError: Error { case noDefaults; case noFile }` (:6-8).
  - Fakes (TidyShotTests/Support/CoordinatorFakes.swift): `FakeNotifier.calls: [Call]` (:20) with `case uploaded(url: URL, copied: Bool)` (:12) and `case notice(title: String, body: String, subtitle: String? = nil)` (:14); `FakeNotifier.errors: [(title: String, message: String)]` (:23); `FakeCards.calls: [Call]` (:86) with `case close(UUID, QuickAccessCloseReason)` (:76); `FakeCards.showing: Set<UUID>` (:88); `FakeCards.dragFiles(for id: UUID) -> [URL?]` (:130); `FakeClipboard.copies: [Copy]` (:167) with `case image`, `case pngAndTIFF`, `case url(URL)` (:157-162); `FakeDestinationFactory.askedConfigs: [S3DestinationConfig]` (:239). `QuickAccessCloseReason.editorOpened` (TidyShot/Overlay/QuickAccessController.swift:15).
  - `FakeDestination` (TidyShotTests/Support/FakeDestination.swift): `let state: Mutex<State>` (:134); `State.uploads: [(key: String, data: Data, contentType: String, cacheControl: String?)]` (:15), `State.uploadAttempts` (:17), `State.downloadedData` (:104), `State.dataDownloadKeys: [String]` (:105).
  - `AppCoordinator`: `let history: HistoryStore`, `let thumbnails: ThumbnailStore`, `let pendingFiles: PendingFileStore`, `let dragFiles: DragFileStore` (AppCoordinator.swift:18, :20, :21, :25); `@ObservationIgnored var clipboardOwner: EditorClipboard.Owner?` (:257); `editors` (:259, `[UUID: any EditorPresenting]` after Task 1); `var hasUnsavedEditors: Bool` (+Editor:7); `func openEditor(recordID: UUID)` (+Editor:15); `func retryFailedUploads()` (+Upload:496); `func prepareDragFile(recordID: UUID)` (+DragOut:14); `func copyImage(recordID: UUID) async` (+RecordActions:88); `func imageData(of record: CaptureRecord, downloadTitle: String = "Copying image…") async throws -> Data` (+RecordActions:215).
  - Stores: `HistoryStore.add(_ record: CaptureRecord)` (HistoryStore.swift:66), `record(id: UUID) -> CaptureRecord?` (:87); `ThumbnailStore.fileName(for id: UUID, editedAt: Date?) -> String` (ThumbnailStore.swift:28), `url(forFileName name: String) -> URL` (:34), `write(_ png: Data, id: UUID) throws -> String` (:39); `PendingFileStore.directory: URL` (PendingFileStore.swift:9), `write(_ data: Data, id: UUID, ext: String) throws -> URL` (:21); `DragFileStore.folder(for id: UUID) -> URL` (DragFileStore.swift:24), `stagedFile(id: UUID) -> URL?` (:39).
  - `CaptureRecord.init(id: UUID = UUID(), timestamp: Date = Date(), fileURL: URL?, fileIsTemporary: Bool = false, thumbnailFileName: String? = nil, pixelWidth: Int, pixelHeight: Int, appName: String?, uploadState: UploadState = .none, objectLocation: ObjectLocation? = nil, pendingObjectKey: String? = nil, editedAt: Date? = nil, uploadIsStale: Bool = false, …, byteCount: Int? = nil, …)` (CaptureRecord.swift:114-120); `UploadState.uploaded(url: URL, key: String)`, `.failed(message: String)` (:52-53); `var uploadedKey: String?` (:191).
  - `EditorModel` (TidyShot/Editor/Session/EditorModel.swift): `let base: CGImage` (:91), `let scale: CGFloat` (:93), `private(set) var document` (:95), `var hasUnsavedChanges: Bool` (:101), `var selection: UUID?` (:107), `var cropDraft: CGRect?` (:119), `var tool: EditorTool = .redact` (:126), `func makeAnnotation(_ tool: EditorTool, from start: CGPoint, to end: CGPoint) -> Annotation?` (:241), `func makeStroke(_ tool: EditorTool, points: [CGPoint]) -> Annotation?` (:288), `func applyCrop()` (:375), `func setBackground(_ style: BackgroundStyle?)` (:424), `func beginTextEditing(at point: CGPoint, existing id: UUID?)` (:453), `func updateEditingText(_ string: String)` (:469), `func commitTextEditing()` (:478); `func commitNewShape(_ shape: Annotation, actionName: String? = nil)` (TidyShot/Editor/Tools/ToolFactory.swift:25, `extension CanvasEditing`).
  - `ImageEncoder.pngData(from image: CGImage, scale: CGFloat) throws -> Data` (TidyShot/Output/ImageEncoder.swift:21); `ScaledImage.image: CGImage` (TidyShot/Output/ScaledImage.swift:7); `CropGeometry.readout(for rect: CGRect) -> String` (TidyShot/Editor/Geometry/CropGeometry.swift:47); `TextLayout.frame(for box: TextBox) -> CGRect` (TidyShot/Editor/Geometry/TextLayout.swift:68); `EditorSaveTarget.uploadedCopyStaleNotice` (TidyShot/Editor/Persistence/EditorSaveTarget.swift:19); `EditorClipboard.Owner(recordID: UUID, changeCount: Int)` (TidyShot/Editor/Persistence/EditorClipboard.swift:9-12).
  - From Task 1 (TidyShotTests/Support/EditorFakes.swift): `FakeEditor.model`, `.title`, `.representedURL`, `.presentCount`, `.pushes` (each `Push` with `available`, `status`, `saveCommand`), `func close()`, `func draw()` (a blue box over the whole capture), `func export() async -> (image: ScaledImage, document: AnnotationDocument)?`, `@discardableResult func save() async -> Bool`; `FakeEditors.built: [FakeEditor]`, `editor(for id: UUID) -> FakeEditor?` (the newest). `CoordinatorWorld.editors: FakeEditors`; `FakeClipboard.pngs: [Data]`. From Task 1's `EditorPixels.swift`: `png(width:height:scale:white:) throws -> Data`, `decoded(_:) throws -> (image: CGImage, scale: CGFloat)`, `dpiWidth(of:) -> Double?`, `rgba(_:) -> [UInt8]`, `pixel(_ image: CGImage, x:y:) -> [Int]`, `changedPixels(_:in:from:) -> Int`, `isBlue(_ pixel: [Int])`, `isBlue(_ image: CGImage)`, `isBlue(png: Data) throws`.

- [ ] **Step 3: Create `TidyShotTests/CoordinatorEditorSaveTests.swift`** with exactly this content (the header is the catalogue's section 3; the helpers are catalogue 2.2's for this suite with the built bodies, D4 and D5, between `init` and the first test in the 2.2 table's order, with `all` after `destination` as Task 2's Interfaces list them; the eight tests are catalogue section 3 "Save over the file" in its order, each body as built, each doc comment written from the entry's Covers and `lines-editor.md`, D10):
  ```swift
  import CoreGraphics
  import Foundation
  import Testing
  @testable import TidyShot

  /// The editor's Save, Save As… and Copy through the editor seam: `openEditor` builds a `FakeEditor`, and each
  /// test plays the user through the `EditorActions` the coordinator handed it. No window, sheet or panel is built.
  @Suite(.timeLimit(.minutes(1)))
  struct CoordinatorEditorSaveTests {
      let world: CoordinatorWorld

      init() throws {
          world = try CoordinatorWorld()
      }

      let key = "s/SHOT.png"
      var link: URL { URL(string: "https://snap.tky.io/\(key)")! }
      var destination: FakeDestination { world.factory.standard }
      var all: Set<EditorAction> { Set(EditorAction.allCases) }

      /// The public URL of a template key (the world's `publicURLTemplate`).
      func publicURL(_ key: String) -> URL { URL(string: "https://snap.tky.io/\(key)")! }

      /// The newest editor built for `id`, once `openEditor`'s load has built one.
      func openedEditor(_ id: UUID) async throws -> FakeEditor {
          try await eventually { world.editors.editor(for: id) != nil }
          return try #require(world.editors.editor(for: id))
      }

      /// The editor built for `id` after `first`, once a second `openEditor` has built it.
      func reopenedEditor(_ id: UUID, after first: FakeEditor) async throws -> FakeEditor {
          try await eventually { world.editors.editor(for: id).map { $0 !== first } ?? false }
          return try #require(world.editors.editor(for: id))
      }

      /// The last edit's thumbnail named on the record (+Editor:249-275), so its task does not outlive the test.
      func settledEdit(_ coordinator: AppCoordinator, _ id: UUID) async throws {
          try await eventually {
              coordinator.history.record(id: id)?.thumbnailFileName == coordinator.thumbnails.fileName(for: id, editedAt: world.date)
          }
      }

      /// A red 4 by 2 capture written to `folder/name` and added to history.
      func addSavedImage(to coordinator: AppCoordinator, in folder: URL, name: String = "Shot.png",
                         uploadState: CaptureRecord.UploadState = .none, objectLocation: ObjectLocation? = nil,
                         uploadIsStale: Bool = false, timestamp: Date = Date(),
                         scale: CGFloat = 1) throws -> (record: CaptureRecord, original: Data) {
          let original = try ImageEncoder.pngData(from: CoordinatorWorld.image(width: 4, height: 2), scale: scale)
          let file = folder.appending(path: name)
          try original.write(to: file)
          let record = CaptureRecord(timestamp: timestamp, fileURL: file, pixelWidth: 4, pixelHeight: 2, appName: nil,
                                     uploadState: uploadState, objectLocation: objectLocation,
                                     uploadIsStale: uploadIsStale, byteCount: original.count)
          coordinator.history.add(record)
          return (record, original)
      }

      /// An upload-only capture in `pending/` whose upload failed, added to history.
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

      /// `<root>/Desktop/<name>`, its folder made: the URL a save panel would return.
      func desktop(_ name: String) throws -> URL {
          let folder = world.root.appending(path: "Desktop", directoryHint: .isDirectory)
          try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
          return folder.appending(path: name)
      }

      /// The record's `pending/<id>.png` (PendingFileStore.swift:21-23).
      func pendingURL(_ coordinator: AppCoordinator, _ id: UUID) -> URL {
          coordinator.pendingFiles.directory.appending(path: "\(id.uuidString).png")
      }

      /// An uploaded capture with no local file, whose object downloads as a red 4 by 2 PNG.
      func addUploadOnly(to coordinator: AppCoordinator) throws -> CaptureRecord {
          let png = try CoordinatorWorld.pngData(width: 4, height: 2)
          destination.state.withLock { $0.downloadedData = png }
          let record = CaptureRecord(fileURL: nil, pixelWidth: 4, pixelHeight: 2, appName: nil,
                                     uploadState: .uploaded(url: link, key: key), objectLocation: world.location)
          coordinator.history.add(record)
          return record
      }

      func isUploaded(_ coordinator: AppCoordinator, _ id: UUID) -> Bool {
          if case .uploaded = coordinator.history.record(id: id)?.uploadState { return true }
          return false
      }

      /// The title `presentEditor` gives a record with no save-folder file (+Editor:77-79).
      func title(of record: CaptureRecord) -> String {
          "Capture \(record.timestamp.formatted(date: .omitted, time: .shortened))"
      }

      func exists(_ url: URL) -> Bool { FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) }

      /// The Crop tool with `rect` drawn; `apply` is Return. Without it the action's export applies the draft.
      func crop(_ model: EditorModel, to rect: CGRect, apply: Bool) {
          model.tool = .crop
          model.cropDraft = rect
          if apply { model.applyCrop() }
      }

      /// A text typed at `point` and committed, as the Text tool does; returns its box.
      func addText(_ model: EditorModel, _ string: String, at point: CGPoint) throws -> TextBox {
          model.beginTextEditing(at: point, existing: nil)
          model.updateEditingText(string)
          model.commitTextEditing()
          for annotation in model.document.annotations {
              if case .text(let box) = annotation { return box }
          }
          throw CoordinatorWorldError.noFile
      }

      /// The editor's document rendered again after the action, which already applied any pending crop.
      func expected(_ editor: FakeEditor) async throws -> CGImage {
          try #require(await editor.export()).image.image
      }

      var green: RGBA { RGBA(red: 0, green: 1, blue: 0) }
      var background: BackgroundStyle {
          BackgroundStyle(fill: .solid(green), padding: 8, cornerRadius: 0, shadow: false, aspect: .auto)
      }

      /// phase-4a:94 (:143), in part; small-tweaks:18 (:21), full with
      /// `CoordinatorEditorUploadTests.annotateTheNewestCardSaveThenUploadWritesTheFileThenUploadsAndCopiesTheURL`, this
      /// test its Save half; phase-7c:170 (:213), in part, the save-over path with no background.
      /// Save on a save-folder capture writes over that file and makes no other, records the written size, renames the
      /// thumbnail to the edit's and draws the edit into it, leaves the editors clean, and uploads nothing.
      /// Stays: phase-4a:94, the unsaved dot clearing (`EDPLACE`) and the menu drawing the row's thumbnail, by hand;
      /// Quick Look is the file's decode, and the new thumbnail's decode is the row's thumbnail. phase-7c:170, the clean
      /// state as the window shows it (`EDPLACE`) and the thumbnail as drawn, by hand.
      @Test func saveWritesOverTheSaveFolderFileAndUploadsNothing() async throws {
          defer { world.removeAll() }
          let folder = try world.storeSaveFolder()
          let coordinator = world.makeCoordinator()
          let original = try CoordinatorWorld.pngData(width: 4, height: 2)
          let file = folder.appending(path: "Shot.png")
          try original.write(to: file)
          let id = UUID()
          let thumbnail = try coordinator.thumbnails.write(Data("png".utf8), id: id)
          coordinator.history.add(CaptureRecord(id: id, fileURL: file, thumbnailFileName: thumbnail, pixelWidth: 4,
                                                pixelHeight: 2, appName: nil, byteCount: original.count))

          coordinator.openEditor(recordID: id)
          let editor = try await openedEditor(id)

          #expect(editor.title == "Shot.png")
          #expect(editor.representedURL == file)
          #expect(editor.presentCount == 1)
          #expect(editor.pushes.first?.saveCommand == .writeOver)
          #expect(editor.pushes.first?.available == all.subtracting([.uploadAsNew]))
          #expect(world.cards.calls.contains(.close(id, .editorOpened)))
          editor.draw()
          #expect(coordinator.hasUnsavedEditors)

          let saved = await editor.save()

          #expect(saved)
          let written = try Data(contentsOf: file)
          #expect(written != original)
          #expect(try EditorPixels.isBlue(png: written))
          #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path(percentEncoded: false)) == ["Shot.png"])
          #expect(coordinator.history.record(id: id)?.byteCount == written.count)
          try await eventually { coordinator.history.record(id: id)?.thumbnailFileName != thumbnail }
          #expect(!coordinator.hasUnsavedEditors)
          #expect(world.factory.askedConfigs.isEmpty)
          #expect(destination.state.withLock { $0.uploadAttempts } == 0)
          #expect(world.notifier.errors.isEmpty)
          let record = try #require(coordinator.history.record(id: id))
          #expect(record.thumbnailFileName == coordinator.thumbnails.fileName(for: id, editedAt: world.date))
          #expect(record.thumbnailFileName == "\(id.uuidString)-1778307200000.png")
          #expect(record.editedAt == world.date)
          #expect(!FileManager.default.fileExists(atPath: coordinator.thumbnails.url(forFileName: thumbnail)
              .path(percentEncoded: false)))
          #expect(record.uploadState == .none)
          #expect(record.uploadIsStale == false)
          // The new thumbnail shows the edit.
          let newThumbnail = try #require(record.thumbnailFileName)
          #expect(try EditorPixels.isBlue(png: Data(contentsOf: coordinator.thumbnails.url(forFileName: newThumbnail))))
      }

      /// An uploaded capture's link, made after Phase 3 (with an object location) or before it (without one).
      nonisolated enum Link: CaseIterable, Sendable { case afterPhase3, beforePhase3 }

      /// phase-4a:95 (:144), in part (`.afterPhase3`); phase-4a:96 (:145), in part (`.beforePhase3`).
      /// Save on an uploaded save-folder capture rewrites the file only: the record keeps its link and location and
      /// is marked stale, the editor hears the stale notice, and nothing is PUT or copied.
      /// Stays: phase-4a:95, the subtitle as shown (`EDPLACE`); the link still showing the original is the absence of a
      /// PUT. phase-4a:96, the subtitle as shown (`EDPLACE`).
      @Test(arguments: Link.allCases)
      func saveOverAnUploadedCaptureRewritesTheFileOnlyAndMarksItsLinkStale(link kind: Link) async throws {
          defer { world.removeAll() }
          let folder = try world.storeSaveFolder()
          let coordinator = world.makeCoordinator()
          let location = kind == .afterPhase3 ? world.location : nil
          let (record, _) = try addSavedImage(to: coordinator, in: folder, uploadState: .uploaded(url: link, key: key),
                                              objectLocation: location)
          coordinator.openEditor(recordID: record.id)
          let editor = try await openedEditor(record.id)
          let first = try #require(editor.pushes.first)
          #expect(first.status == nil)
          #expect(first.available == all)
          #expect(first.saveCommand == .writeOver)
          editor.draw()
          #expect(await editor.save())
          #expect(try EditorPixels.isBlue(png: Data(contentsOf: try #require(record.fileURL))))
          #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path(percentEncoded: false)) == ["Shot.png"])
          let after = try #require(coordinator.history.record(id: record.id))
          #expect(after.uploadIsStale == true)
          #expect(after.uploadState == .uploaded(url: link, key: key))
          #expect(after.objectLocation == location)
          #expect(editor.pushes.last?.status == EditorSaveTarget.uploadedCopyStaleNotice)
          #expect(destination.state.withLock { $0.uploadAttempts } == 0)
          #expect(destination.state.withLock { $0.uploads.isEmpty })
          #expect(world.factory.askedConfigs.isEmpty)
          #expect(world.clipboard.copies.isEmpty)
          try await settledEdit(coordinator, record.id)
      }

      /// phase-4a:99 (:148), in part.
      /// Save over a file whose write fails posts `Not saved` with the reason first, leaves the file and the record as
      /// they were, puts the edit on the clipboard with the editor as its owner, and marks nothing saved.
      /// Stays: the dot staying (`EDPLACE`); Finder's Locked is the immutable flag.
      @Test func saveOverALockedFileSaysNotSavedAndPutsTheEditOnTheClipboard() async throws {
          defer { world.removeAll() }
          let folder = try world.storeSaveFolder()
          let coordinator = world.makeCoordinator()
          let (record, original) = try addSavedImage(to: coordinator, in: folder)
          let file = try #require(record.fileURL)
          let id = record.id
          coordinator.openEditor(recordID: id)
          let editor = try await openedEditor(id)
          try FileManager.default.setAttributes([.immutable: true], ofItemAtPath: file.path(percentEncoded: false))
          defer { try? FileManager.default.setAttributes([.immutable: false], ofItemAtPath: file.path(percentEncoded: false)) }
          editor.draw()
          #expect(!(await editor.save()))
          #expect(try Data(contentsOf: file) == original)
          let error = try #require(world.notifier.errors.last)
          #expect(error.title == "Not saved")
          #expect(error.message.hasSuffix(" The edited image is on the clipboard."))
          #expect(error.message.count > " The edited image is on the clipboard.".count)
          #expect(world.clipboard.copies == [.image])
          #expect(try EditorPixels.isBlue(png: world.clipboard.pngs[0]))
          #expect(coordinator.clipboardOwner == EditorClipboard.Owner(recordID: id, changeCount: 1))
          #expect(coordinator.history.record(id: id)?.editedAt == nil)
          #expect(world.logLines.contains { $0.hasPrefix("Save over failed: ") })
          #expect(editor.model.hasUnsavedChanges)
      }

      /// phase-4a:98 (:147), full; phase-4b:107 (:151), full.
      /// Save on an upload-only capture whose upload failed rewrites `pending/<UUID>.png` in place with the stroke and
      /// uploads nothing; Retry Failed Uploads then PUTs exactly those bytes, the record takes the link, the pending file
      /// goes, and the link is copied and announced.
      /// Stays: nothing. Wi-Fi off is the record's failed state; Wi-Fi on and the bucket are the fake.
      @Test func saveOnAFailedUploadOnlyCaptureRewritesPendingAndRetryUploadsTheEdit() async throws {
          defer { world.removeAll() }
          let coordinator = world.makeCoordinator()
          let png = try EditorPixels.png(width: 200, height: 100, scale: 2, white: true)
          let id = UUID()
          let pending = try coordinator.pendingFiles.write(png, id: id, ext: "png")
          let record = CaptureRecord(id: id, fileURL: pending, fileIsTemporary: true, pixelWidth: 200, pixelHeight: 100,
                                     appName: nil, uploadState: .failed(message: "Upload was interrupted."), byteCount: png.count)
          coordinator.history.add(record)
          coordinator.openEditor(recordID: id)
          let editor = try await openedEditor(id)
          #expect(editor.representedURL == nil)
          #expect(editor.title == title(of: record))
          let first = try #require(editor.pushes.first)
          #expect(first.saveCommand == .writeOver)
          #expect(first.status == nil)
          #expect(first.available == [.save, .saveAs, .copy, .upload])
          editor.model.commitNewShape(try #require(editor.model.makeStroke(.pencil, points: [CGPoint(x: 20, y: 20),
                                       CGPoint(x: 100, y: 60), CGPoint(x: 180, y: 20)])))
          #expect(await editor.save())
          let expected = try #require(await editor.export()).image.image
          let written = try Data(contentsOf: pending)
          #expect(written != png)
          let decoded = try EditorPixels.decoded(written)
          #expect(EditorPixels.rgba(decoded.image) == EditorPixels.rgba(expected))
          let p = EditorPixels.pixel(decoded.image, x: 100, y: 60)
          #expect(p[0] > 200 && p[1] < 100 && p[2] < 100)
          #expect(try FileManager.default.contentsOfDirectory(atPath: coordinator.pendingFiles.directory.path(percentEncoded: false))
              == ["\(id.uuidString).png"])
          let saved = try #require(coordinator.history.record(id: id))
          #expect(saved.uploadState == .failed(message: "Upload was interrupted."))
          #expect(saved.fileURL == pending)
          #expect(saved.uploadIsStale == false)
          #expect(saved.byteCount == written.count)
          #expect(destination.state.withLock { $0.uploadAttempts } == 0)
          coordinator.retryFailedUploads()
          try await eventually { coordinator.history.record(id: id)?.uploadedKey != nil }
          let uploads = destination.state.withLock { $0.uploads }
          #expect(uploads.count == 1)
          #expect(uploads.first?.data == written)
          #expect(uploads.first?.contentType == "image/png")
          let k = try #require(uploads.first?.key)
          let done = try #require(coordinator.history.record(id: id))
          #expect(done.uploadState == .uploaded(url: publicURL(k), key: k))
          #expect(done.fileURL == nil)
          #expect(!exists(pending))
          #expect(world.clipboard.copies == [.url(publicURL(k))])
          #expect(world.notifier.calls.contains(.uploaded(url: publicURL(k), copied: true)))
          try await settledEdit(coordinator, id)
      }

      /// phase-4b:71 (:99), full; phase-4b:73 (:101), full.
      /// A crop read out as 800 × 400, applied with Return and saved, writes that pixel size into the same file at the
      /// capture's scale (DPI 72 × scale) with exactly the cropped picture, and the record takes the size; Annotate again
      /// opens the cropped file at its new size with no crop pending, and Crop starts from the whole picture.
      /// Stays: nothing. `sips` is the decode and the DPI read; Quick Look is the pixel comparison; the Retina display is
      /// the scale argument.
      @Test(arguments: [CGFloat(1), CGFloat(2)])
      func saveWithACropWritesTheCroppedSizeAtTheCapturesScaleAndReopensCropped(scale: CGFloat) async throws {
          defer { world.removeAll() }
          let folder = try world.storeSaveFolder()
          let coordinator = world.makeCoordinator()
          let png = try EditorPixels.png(width: 1000, height: 600, scale: scale)
          let file = folder.appending(path: "Shot.png")
          try png.write(to: file)
          let id = UUID()
          coordinator.history.add(CaptureRecord(id: id, fileURL: file, pixelWidth: 1000, pixelHeight: 600, appName: nil,
                                                byteCount: png.count))

          coordinator.openEditor(recordID: id)
          let editor = try await openedEditor(id)
          let first = try #require(editor.pushes.first)
          #expect(first.saveCommand == .writeOver)
          #expect(first.available == all.subtracting([.uploadAsNew]))
          #expect(first.status == nil)
          crop(editor.model, to: CGRect(x: 100, y: 100, width: 800, height: 400), apply: false)
          #expect(CropGeometry.readout(for: try #require(editor.model.cropDraft)) == "800 × 400")
          editor.model.applyCrop()
          #expect(editor.model.document.crop == CGRect(x: 100, y: 100, width: 800, height: 400))
          #expect(editor.model.tool == .redact)

          let saved = await editor.save()
          let expected = try await expected(editor)

          #expect(saved)
          let written = try Data(contentsOf: file)
          let decoded = try EditorPixels.decoded(written)
          #expect(decoded.image.width == 800)
          #expect(decoded.image.height == 400)
          #expect(decoded.scale == scale)
          #expect(abs(try #require(EditorPixels.dpiWidth(of: written)) - 72 * scale) < 0.5)
          #expect(EditorPixels.rgba(decoded.image) == EditorPixels.rgba(expected))
          #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path(percentEncoded: false)) == ["Shot.png"])
          let record = try #require(coordinator.history.record(id: id))
          #expect(record.pixelWidth == 800)
          #expect(record.pixelHeight == 400)
          #expect(record.byteCount == written.count)
          #expect(world.factory.askedConfigs.isEmpty)
          #expect(destination.state.withLock { $0.uploadAttempts } == 0)
          #expect(world.notifier.errors.isEmpty)

          editor.close()
          #expect(coordinator.editors[id] == nil)
          coordinator.openEditor(recordID: id)
          let reopened = try await reopenedEditor(id, after: editor)

          #expect(world.editors.built.count == 2)
          #expect(reopened.model.base.width == 800)
          #expect(reopened.model.base.height == 400)
          #expect(reopened.model.scale == scale)
          #expect(reopened.model.document == AnnotationDocument(annotations: []))
          #expect(!reopened.model.hasUnsavedChanges)
          #expect(reopened.model.cropDraft == nil)
          reopened.model.tool = .crop
          #expect(reopened.model.cropDraft == CGRect(x: 0, y: 0, width: 800, height: 400))
          #expect(reopened.title == "Shot.png")
          try await settledEdit(coordinator, id)
      }

      /// phase-4b:105 (:149), full.
      /// On a saved capture never uploaded, a text, an ellipse and a crop saved with ⌘S land in the same file: it is
      /// the cropped size at the capture's scale, its pixels are the editor's render, and the ellipse's stroke and the
      /// text are in them. The row's Annotate is menu UI that calls `openEditor`, where the test starts.
      /// Stays: nothing.
      @Test func saveWithTextEllipseAndCropWritesAllThreeIntoTheSameFile() async throws {
          defer { world.removeAll() }
          let folder = try world.storeSaveFolder()
          let coordinator = world.makeCoordinator()
          let png = try EditorPixels.png(width: 400, height: 200, scale: 2, white: true)
          let file = folder.appending(path: "Shot.png")
          try png.write(to: file)
          let record = CaptureRecord(fileURL: file, pixelWidth: 400, pixelHeight: 200, appName: nil, byteCount: png.count)
          coordinator.history.add(record)
          coordinator.openEditor(recordID: record.id)
          let editor = try await openedEditor(record.id)
          let box = try addText(editor.model, "Hello", at: CGPoint(x: 110, y: 70))
          editor.model.commitNewShape(try #require(editor.model.makeAnnotation(.ellipse, from: CGPoint(x: 220, y: 40),
                                                                              to: CGPoint(x: 340, y: 140))))
          #expect(editor.model.document.annotations.count == 2)
          crop(editor.model, to: CGRect(x: 40, y: 20, width: 320, height: 160), apply: true)
          #expect(editor.title == "Shot.png")
          #expect(editor.representedURL == file)
          #expect(await editor.save())
          let expected = try #require(await editor.export()).image.image
          let decoded = try EditorPixels.decoded(Data(contentsOf: file))
          #expect(decoded.image.width == 320)
          #expect(decoded.image.height == 160)
          #expect(decoded.scale == 2)
          #expect(EditorPixels.rgba(decoded.image) == EditorPixels.rgba(expected))
          let e = EditorPixels.pixel(decoded.image, x: 240, y: 24)
          #expect(e[0] > 200 && e[1] < 100 && e[2] < 100)
          #expect(EditorPixels.changedPixels(decoded.image, in: TextLayout.frame(for: box).offsetBy(dx: -40, dy: -20),
                                             from: [255, 255, 255]) > 0)
          #expect(coordinator.history.record(id: record.id)?.pixelWidth == 320)
          #expect(world.factory.askedConfigs.isEmpty)
          try await settledEdit(coordinator, record.id)
      }

      /// phase-7c:170 (:213), in part, the composed canvas, the record's size and the thumbnail; phase-7c:171 (:214), in
      /// part.
      /// Save with a background writes the composed canvas over the file, leaves the editor clean, gives the record the
      /// canvas's size, and draws the background into the renamed thumbnail; Annotate again opens that file flat, with no
      /// background on the document (the switch's getter reads off), and a background set again goes around the first.
      /// Stays: phase-7c:170, the clean state as the window shows it (`EDPLACE`) and the thumbnail as drawn, by hand.
      /// phase-7c:171, the popover's switch turned on, whose setter reads `AppSettings.shared.backgroundStyle` (`BGPOP`),
      /// and the switch drawn in the window (`EDPLACE`); whether a second background is expected is Tim's call.
      @Test func saveWithABackgroundWritesTheComposedCanvasAndReopensFlat() async throws {
          defer { world.removeAll() }
          let folder = try world.storeSaveFolder()
          let coordinator = world.makeCoordinator()
          let original = try ImageEncoder.pngData(from: CoordinatorWorld.image(width: 4, height: 2), scale: 1)
          let file = folder.appending(path: "Shot.png")
          try original.write(to: file)
          let id = UUID()
          let thumb = try coordinator.thumbnails.write(Data("png".utf8), id: id)
          #expect(thumb == "\(id.uuidString).png")
          coordinator.history.add(CaptureRecord(id: id, fileURL: file, thumbnailFileName: thumb, pixelWidth: 4, pixelHeight: 2,
                                                appName: nil, byteCount: original.count))
          coordinator.openEditor(recordID: id)
          let editor = try await openedEditor(id)
          editor.draw()
          editor.model.setBackground(background)
          #expect(await editor.save())
          let written = try Data(contentsOf: file)
          let decoded = try EditorPixels.decoded(written)
          #expect(decoded.image.width == 20)
          #expect(decoded.image.height == 18)
          #expect(decoded.scale == 1)
          for (x, y) in [(0, 0), (7, 7), (19, 17)] { #expect(EditorPixels.pixel(decoded.image, x: x, y: y) == [0, 255, 0, 255]) }
          #expect(EditorPixels.isBlue(EditorPixels.pixel(decoded.image, x: 8, y: 8)))
          #expect(EditorPixels.isBlue(EditorPixels.pixel(decoded.image, x: 11, y: 9)))
          #expect(!editor.model.hasUnsavedChanges)
          let rec = try #require(coordinator.history.record(id: id))
          #expect(rec.pixelWidth == 20)
          #expect(rec.pixelHeight == 18)
          #expect(rec.byteCount == written.count)
          #expect(rec.editedAt == world.date)
          try await eventually {
              coordinator.history.record(id: id)?.thumbnailFileName == coordinator.thumbnails.fileName(for: id, editedAt: world.date)
          }
          #expect(!exists(coordinator.thumbnails.url(forFileName: thumb)))
          let thumbURL = coordinator.thumbnails.url(forFileName: coordinator.thumbnails.fileName(for: id, editedAt: world.date))
          let t = try EditorPixels.decoded(Data(contentsOf: thumbURL))
          #expect(t.image.width == 20)
          #expect(t.image.height == 18)
          #expect(EditorPixels.pixel(t.image, x: 0, y: 0) == [0, 255, 0, 255])
          #expect(EditorPixels.isBlue(EditorPixels.pixel(t.image, x: 8, y: 8)))
          editor.close()
          #expect(coordinator.editors[id] == nil)
          coordinator.openEditor(recordID: id)
          let second = try await reopenedEditor(id, after: editor)
          #expect(second.model.base.width == 20)
          #expect(second.model.base.height == 18)
          #expect(EditorPixels.pixel(second.model.base, x: 0, y: 0) == [0, 255, 0, 255])
          #expect(EditorPixels.isBlue(EditorPixels.pixel(second.model.base, x: 8, y: 8)))
          #expect(second.model.document == AnnotationDocument())
          #expect(second.model.document.background == nil)
          #expect(!second.model.hasUnsavedChanges)
          second.model.setBackground(background)
          let export = try #require(await second.export())
          #expect(export.image.image.width == 36)
          #expect(export.image.image.height == 34)
          #expect(EditorPixels.pixel(export.image.image, x: 0, y: 0) == [0, 255, 0, 255])
          #expect(EditorPixels.pixel(export.image.image, x: 8, y: 8) == [0, 255, 0, 255])
          #expect(EditorPixels.isBlue(EditorPixels.pixel(export.image.image, x: 16, y: 16)))
      }

      /// phase-6a:199 (:211), in part, the "Save and copy image" half (the line's last sentence, with ⌘S); the other
      /// half is `CoordinatorEditorUploadTests.uploadOfAnUploadOnlyCaptureRemovesItsDragCopyAndEveryReadGivesTheEdit`.
      /// Save over the file removes the capture's `Drag/<record id>` folder and the card's drag file at once; after it
      /// the image read, Copy Image, a new press on the card (which stages the edit again) and Annotate all give the
      /// edit, read from the file and never from the bucket.
      /// Stays: the card's Save As… panel (`SAVEAS`); the drop, by hand. The line's "from the card" after an Annotate
      /// cannot happen as written, since Annotate closes the card (tests-editor.md section 8).
      @Test func saveOverTheFileRemovesTheDragCopyAndEveryReadGivesTheEdit() async throws {
          defer { world.removeAll() }
          let folder = try world.storeSaveFolder()
          let coordinator = world.makeCoordinator()
          let (record, original) = try addSavedImage(to: coordinator, in: folder)
          let id = record.id
          let file = try #require(record.fileURL)
          world.cards.showing.insert(id)
          coordinator.prepareDragFile(recordID: id)
          try await eventually { world.cards.dragFiles(for: id).last.flatMap { $0 } != nil }
          let staged = try #require(world.cards.dragFiles(for: id).last.flatMap { $0 })
          #expect(try Data(contentsOf: staged) == original)
          coordinator.openEditor(recordID: id)
          let editor = try await openedEditor(id)
          #expect(world.cards.calls.contains(.close(id, .editorOpened)))
          editor.draw()
          #expect(await editor.save())
          #expect(!exists(coordinator.dragFiles.folder(for: id)))
          #expect(coordinator.dragFiles.stagedFile(id: id) == nil)
          #expect(world.cards.dragFiles(for: id).last == .some(nil))
          #expect(try EditorPixels.isBlue(png: Data(contentsOf: file)))
          let current = try #require(coordinator.history.record(id: id))
          #expect(try EditorPixels.isBlue(png: await coordinator.imageData(of: current)))
          await coordinator.copyImage(recordID: id)
          #expect(try EditorPixels.isBlue(png: try #require(world.clipboard.pngs.last)))
          world.cards.showing.insert(id)
          let before = world.cards.dragFiles(for: id).count
          coordinator.prepareDragFile(recordID: id)
          try await eventually { world.cards.dragFiles(for: id).count > before && world.cards.dragFiles(for: id).last.flatMap { $0 } != nil }
          let again = try #require(world.cards.dragFiles(for: id).last.flatMap { $0 })
          #expect(try Data(contentsOf: again) == Data(contentsOf: file))
          editor.close()
          #expect(coordinator.editors[id] == nil)
          coordinator.openEditor(recordID: id)
          try await eventually { world.editors.built.count == 2 }
          #expect(EditorPixels.isBlue(try #require(world.editors.editor(for: id)).model.base))
          #expect(destination.state.withLock { $0.dataDownloadKeys }.isEmpty)
          #expect(world.factory.askedConfigs.isEmpty)
          try await settledEdit(coordinator, id)
      }
  }
  ```
  `project.yml` takes every file under `TidyShotTests/` (:92-93), so `xcodegen generate` adds this one; nothing else changes.

- [ ] **Step 4: Count the tests in the file.** Run:
  ```bash
  grep -c "@Test" TidyShotTests/CoordinatorEditorSaveTests.swift
  grep -c "@Test(arguments:" TidyShotTests/CoordinatorEditorSaveTests.swift
  python3 -I -c 'import sys; [print(f, n) for f in sys.argv[1:] for n, l in enumerate(open(f, encoding="utf-8"), 1) if "///" in l and len(l.rstrip("\n")) > 120]' TidyShotTests/CoordinatorEditorSaveTests.swift
  git status --short
  ```
  Expected: `8`, then `2`, then nothing from the width check (no doc comment line passes 120 characters, counted as
  characters; D75), then `?? TidyShotTests/CoordinatorEditorSaveTests.swift` alone.

- [ ] **Step 5: Run the suite alone.** Run:
  ```bash
  xcodegen generate && xcodebuild test -project TidyShot.xcodeproj -scheme TidyShot -destination 'platform=macOS' -derivedDataPath .build -only-testing:TidyShotTests/CoordinatorEditorSaveTests 2>&1 | grep -E "Test run with|error:|TEST"
  ```
  Expected: `✔ Test run with 8 tests in 1 suite passed after <n> seconds.` and `** TEST SUCCEEDED **`, with no `error:` line from a Swift file. The known noise can appear and is not a failure: `com.apple.linkd.autoShortcut`, `mdb_txn_commit error: MDB_MAP_FULL` lines, and on this machine an `xcodebuild` line `iOSSimulator: [SimServiceContext sharedServiceContextForDeveloperDir:error:] returned nil … CoreSimulator is out of date` (the grep's `error:` matches its text; it is not about the build). The plan's writer ran this file over Task 1's support files in a scratch tree and got `✔ Test run with 8 tests in 1 suite passed after 0.425 seconds.` If a test fails, do not change its assertions to make it pass: the bodies are the ones the design's review ran green in its built tree; report the failure with the test's output.

- [ ] **Step 6: Run the full suite.** Run:
  ```bash
  xcodegen generate && xcodebuild test -project TidyShot.xcodeproj -scheme TidyShot -destination 'platform=macOS' -derivedDataPath .build 2>&1 | grep -E "Test run with|error:|TEST"
  ```
  Expected: `✔ Test run with 2282 tests in 192 suites passed after <n> seconds.` and `** TEST SUCCEEDED **` (Task 1's 2274 in 191, plus these 8 tests and one suite). The known noise as in Step 5, and `History file could not be read or decoded, setting it aside` twice. The suite takes 45 s to 130 s; a slow run is not a failure. No Release build in this task: `TidyShot/` does not change.

- [ ] **Step 7: Commit.** Run:
  ```bash
  git add TidyShotTests/CoordinatorEditorSaveTests.swift
  git commit -m "test: the editor's Save over the file through the editor seam"
  git status --short
  git log -1 --stat --format=%s
  ```
  Expected: `git status --short` prints nothing; the log shows `test: the editor's Save over the file through the editor seam` and `1 file changed` with `TidyShotTests/CoordinatorEditorSaveTests.swift` only. No attribution lines, no session URL; do not push. The report says no hand check was run.

### Task 3: `CoordinatorEditorSaveTests`, Save As… and Copy [integration]

**Files:**
- Modify `TidyShotTests/CoordinatorEditorSaveTests.swift`: the nine tests appended before the closing `}` of `struct CoordinatorEditorSaveTests`, after Task 2's last test (`saveOverTheFileRemovesTheDragCopyAndEveryReadGivesTheEdit`).

**Interfaces:**
- Consumes (Task 1): `FakeEditor` (`draw()`, `save()`, `saveAs(to:)`, `copy()`, `export()`, `actions` (a check the window's validation would block calls `editor.actions.*` directly, design 3.4), `isClosed`, `model`, `pushes`), `world.editors` (`built`, `editor(for:)`), `world.clipboard.pngs`, `EditorPixels.decoded`, `.dpiWidth`, `.isBlue`, `.pixel`, `.png`, `.rgba`. (Task 2): every helper of `CoordinatorEditorSaveTests` with the signatures in Task 2's Produces.
- Produces, the argument type `nonisolated enum Write: CaseIterable, Sendable { case save, saveAs }`, directly before `aSaveOrSaveAsTakesTheClipboardOnlyWhileItHoldsTheCapture(write:userCopied:)`. Nothing later uses this suite.

**Tests:**
1. `saveAsOnAnUploadOnlyCaptureWritesThePNGAndUploadsNothing`: catalogue section 3 (CoordinatorEditorSaveTests.swift), "Save As…", tests-editor.md:613; effort M.
2. `saveAsElsewhereWritesA144DPICopyAndLeavesTheCaptureAlone`: catalogue section 3 (CoordinatorEditorSaveTests.swift), "Save As…", tests-editor.md:632; effort M.
3. `saveAsOntoItsOwnFileIsASave(uploaded:)`: catalogue section 3 (CoordinatorEditorSaveTests.swift), "Save As…", tests-editor.md:649; effort S.
4. `saveAsWithACropWritesACroppedCopyAndLeavesTheCaptureAlone`: catalogue section 3 (CoordinatorEditorSaveTests.swift), "Save As…", tests-editor.md:664; effort S.
5. `saveAsWithABackgroundWritesTheComposedImageAndLeavesTheCaptureAlone`: catalogue section 3 (CoordinatorEditorSaveTests.swift), "Save As…", tests-editor.md:683; effort S.
6. `copyWithShowNotificationOffPostsNothing`: catalogue section 3 (CoordinatorEditorSaveTests.swift), "Copy and the clipboard rule", tests-editor.md:699; effort S.
7. `copyWithACropPutsTheCroppedImageAtPointSizeAndSaysImageCopied`: catalogue section 3 (CoordinatorEditorSaveTests.swift), "Copy and the clipboard rule", tests-editor.md:713; effort S.
8. `copyWithABackgroundPutsTheComposedCanvasOnTheClipboard`: catalogue section 3 (CoordinatorEditorSaveTests.swift), "Copy and the clipboard rule", tests-editor.md:744; effort S.
9. `aSaveOrSaveAsTakesTheClipboardOnlyWhileItHoldsTheCapture(write:userCopied:)`: catalogue section 3 (CoordinatorEditorSaveTests.swift), "Copy and the clipboard rule", tests-editor.md:759; effort S.
- 9 tests (S 7, M 2), 2 parameterized.
- Focused run, `-only-testing:TidyShotTests/CoordinatorEditorSaveTests`: `Test run with 17 tests in 1 suite passed` (Task 2's 8 and these 9).
- Full suite: `Test run with 2291 tests in 192 suites passed`.

**Commit:** `test: the editor's Save As… and Copy through the editor seam`

**Steps:**

- [ ] **Step 1: Check the starting point.** Task 2 is committed and the tree is clean. From the repository root:

```bash
git status --short
git log -1 --format=%s
tail -3 TidyShotTests/CoordinatorEditorSaveTests.swift
grep -c '^    @Test' TidyShotTests/CoordinatorEditorSaveTests.swift
```

Expected: `git status --short` prints nothing; the subject is `test: the editor's Save over the file through the editor seam`;
the file ends with the last statement of Task 2's last test, `saveOverTheFileRemovesTheDragCopyAndEveryReadGivesTheEdit`
(as in the review's built tree), its closing brace, and the
closing brace of `struct CoordinatorEditorSaveTests`:

```swift
        try await settledEdit(coordinator, id)
    }
}
```

and the count is `8`. If the file ends otherwise, stop and report: the insertion point below is these three lines.

- [ ] **Step 2: Append the nine tests.** In `TidyShotTests/CoordinatorEditorSaveTests.swift`, the nine tests and the
argument type `Write` go after the closing `    }` of `saveOverTheFileRemovesTheDragCopyAndEveryReadGivesTheEdit` and
before the closing `}` of `struct CoordinatorEditorSaveTests`, with one blank line before the first doc comment. With the
Edit tool, replace the three lines quoted in Step 1 (they occur once: they are the file's last three lines) with the same
two first lines, a blank line, the block below, and the struct's `}`. That is, the file's end becomes
`        try await settledEdit(coordinator, id)`, `    }`, an empty line, the block, `}`.

The bodies are the ones in the review's built tree, statement for statement (D11), and so is `Write`. They use Task 2's helpers only
(`key`, `link`, `destination`, `openedEditor`, `settledEdit`, `addSavedImage`, `addUploadOnly`, `desktop`, `crop`,
`expected`, `background`) with the signatures in Task 2's Produces; nothing new is added to the suite but `Write`, which
sits directly before its test (D4). The doc comments are the plan's (D10). They call these members of the code at dd1231d,
quoted from it:

- `EditorActions` (EditorWindowController.swift:18-32): `var save: (ScaledImage) async -> Bool`,
  `var saveAs: (ScaledImage, URL) async -> Bool`, `var saveAsSuggestion: () -> EditorNaming.SaveAsSuggestion`,
  `var copy: (ScaledImage) async -> Void`, `var objectClipboard: EditorObjectClipboard` (whose `var copy: (Data) -> Void`,
  :7-12); the coordinator's closures at AppCoordinator+Editor.swift:100-116.
- `struct EditorNaming.SaveAsSuggestion: Equatable, Sendable { var fileName: String; var directory: URL?; var mediaKind:
  MediaKind = .image }` (EditorNaming.swift:6-13).
- `EditorSaveTarget.noFileReason` (EditorSaveTarget.swift:16), `EditorSaveTarget.uploadedCopyStaleNotice` (:19),
  `EditorSaveCommand.saveAs` (:76).
- `EditorClipboard.Owner(recordID: UUID, changeCount: Int)` (EditorClipboard.swift:9-12).
- On `AppCoordinator`: `var latestCapture: (id: UUID, image: ScaledImage)?` (AppCoordinator.swift:133),
  `var openingEditorIDs: Set<UUID>` (:253), `var clipboardOwner: EditorClipboard.Owner?` (:257); `history.records`
  (HistoryStore.swift:11), `history.record(id:)` (:87), `history.add(_:)`; `thumbnails.write(_ png: Data, id: UUID) throws
  -> String` (ThumbnailStore.swift:39), `thumbnails.fileName(for id: UUID, editedAt: Date?) -> String` (:28).
- `EditorModel`: `scale` (EditorModel.swift:93), `selection` (:107), `hasUnsavedChanges` (:101),
  `makeAnnotation(_ tool: EditorTool, from start: CGPoint, to end: CGPoint) -> Annotation?` (:241),
  `setBackground(_ style: BackgroundStyle?)` (:424), `commitNewShape(_ shape: Annotation, actionName: String? = nil)`
  (ToolFactory.swift:25).
- `ImageEncoder.pngData(from image: CGImage, scale: CGFloat) throws -> Data` (ImageEncoder.swift:21);
  `ScaledImage(image:scale:)` (ScaledImage.swift:6-10); `CaptureRecord.init(id:timestamp:fileURL:…:byteCount:…)`
  (CaptureRecord.swift:114-120).
- `AppSettings.fileNameTemplate` (AppSettings.swift:98), `showNotification` (:93), `currentCounter` (:461),
  `nextCounter() -> Int` (:466), through `world.settings`.
- The fakes: `FakeClipboard.copies`, `.changeCount`, `setString(_:)`, `copy(pngData:tiffData:) -> Int` and the cases
  `.pngAndTIFF`, `.string(_:)`, `.annotationClip(_:)` (CoordinatorFakes.swift:156-192), and `pngs` (Task 1);
  `FakeNotifier.Call.saved(title:file:)` and `.notice(title:body:subtitle:)` (CoordinatorFakes.swift:11, :14);
  `FakeCards.Call.close(UUID, QuickAccessCloseReason)` (:76); `world.factory.askedConfigs` (:239);
  `world.shutterCount` (CoordinatorWorld.swift:48); `world.editors.built`, `.editor(for:)` and `FakeEditor`'s `draw()`,
  `save()`, `saveAs(to:)`, `copy()`, `export()`, `actions`, `model`, `pushes`, `isClosed` (Task 1, design 3.1);
  `EditorPixels.decoded`, `.dpiWidth`, `.isBlue`, `.pixel`, `.png`, `.rgba` (Task 1).

```swift
    /// phase-4a:97 (:146), in part.
    /// An upload-only capture has no file to write over, so Save stays on and ⌘S runs Save As… (the first push's
    /// `saveCommand` is `.saveAs` and its status `EditorSaveTarget.noFileReason`, EST:16). The suggestion, read through
    /// `editor.actions.saveAsSuggestion()` as the panel reads it when it opens, is the file name template's name with
    /// the current counter in the save folder, and no counter is drawn (+RecordActions:321-330). Save As… writes the
    /// PNG, posts `Saved` and touches no record, so nothing uploads and no link goes on the clipboard
    /// (+Editor:283-304, +RecordActions:291-297).
    /// Stays: the sheet, its name and folder (`EDSAVEAS`); "Save is on" as the toolbar shows it, and the dot
    /// (`EDPLACE`). The first push's `available` is the rule.
    @Test func saveAsOnAnUploadOnlyCaptureWritesThePNGAndUploadsNothing() async throws {
        defer { world.removeAll() }
        let folder = try world.storeSaveFolder()
        world.settings.fileNameTemplate = "shot-{counter}"
        _ = world.settings.nextCounter()
        let coordinator = world.makeCoordinator()
        let record = try addUploadOnly(to: coordinator)
        coordinator.openEditor(recordID: record.id)
        let editor = try await openedEditor(record.id)
        editor.draw()
        let first = try #require(editor.pushes.first)
        #expect(first.available.contains(.save))
        #expect(first.saveCommand == .saveAs)
        #expect(first.status == EditorSaveTarget.noFileReason)
        let suggestion = editor.actions.saveAsSuggestion()
        #expect(suggestion == EditorNaming.SaveAsSuggestion(fileName: "shot-1.png", directory: folder, mediaKind: .image))
        let target = folder.appending(path: "shot-1.png")
        #expect(await editor.saveAs(to: target))
        #expect(try EditorPixels.isBlue(png: Data(contentsOf: target)))
        #expect(world.notifier.calls.contains(.saved(title: "Saved", file: "shot-1.png")))
        #expect(!editor.model.hasUnsavedChanges)
        #expect(coordinator.history.records.count == 1)
        #expect(coordinator.history.record(id: record.id) == record)
        #expect(destination.state.withLock { $0.uploadAttempts } == 0)
        #expect(world.clipboard.copies.isEmpty)
        #expect(world.settings.currentCounter == 1)
    }

    /// phase-4a:102 (:151), in part.
    /// Save As… elsewhere on a 2x capture writes the edit at 144 dpi (`sips` is the DPI read, here `dpiWidth`) and
    /// leaves the capture alone: its file and its record are unchanged, so the editor keeps its title; no record and no
    /// card are added, no shutter plays and nothing uploads (+Editor:283-304, +RecordActions:291-297). The suggestion,
    /// read through `editor.actions.saveAsSuggestion()` as the panel reads it, is the capture's own file name in the
    /// save folder (+RecordActions:321-330).
    /// Stays: the panel's suggestion and the choice (`EDSAVEAS`); the dot (`EDPLACE`).
    @Test func saveAsElsewhereWritesA144DPICopyAndLeavesTheCaptureAlone() async throws {
        defer { world.removeAll() }
        let folder = try world.storeSaveFolder()
        let coordinator = world.makeCoordinator()
        let (record, original) = try addSavedImage(to: coordinator, in: folder, scale: 2)
        let id = record.id
        coordinator.openEditor(recordID: id)
        let editor = try await openedEditor(id)
        #expect(editor.model.scale == 2)
        editor.draw()
        #expect(editor.actions.saveAsSuggestion() == EditorNaming.SaveAsSuggestion(fileName: "Shot.png", directory: folder,
                                                                                   mediaKind: .image))
        let target = try desktop("Edited.png")
        #expect(await editor.saveAs(to: target))
        let written = try Data(contentsOf: target)
        #expect(try EditorPixels.isBlue(png: written))
        #expect(abs(try #require(EditorPixels.dpiWidth(of: written)) - 144) < 0.5)
        #expect(try Data(contentsOf: try #require(record.fileURL)) == original)
        #expect(coordinator.history.records.count == 1)
        #expect(coordinator.history.record(id: id) == record)
        #expect(world.cards.calls == [.close(id, .editorOpened)])
        #expect(world.shutterCount == 0)
        #expect(world.factory.askedConfigs.isEmpty)
        #expect(destination.state.withLock { $0.uploadAttempts } == 0)
        #expect(world.notifier.calls.contains(.saved(title: "Saved", file: "Edited.png")))
        #expect(world.editors.built.count == 1)
        #expect(!editor.model.hasUnsavedChanges)
    }

    /// phase-4a:106 (:157), in part.
    /// Save As… onto the capture's own file is a Save (`EditorSaveTarget.saveAsWritesOverOwnFile`, EST:50-56;
    /// +Editor:286-290): the file holds the edit, the folder holds no second file, the thumbnail is named for the edit,
    /// `editedAt` is set and no `Saved` notice is posted, as after ⌘S. On an uploaded capture the record turns stale
    /// and the last push's status is `EditorSaveTarget.uploadedCopyStaleNotice`; on a never-uploaded one neither.
    /// Nothing uploads.
    /// Stays: the Replace confirmation (`EDSAVEAS`); the subtitle as shown (`EDPLACE`).
    @Test(arguments: [false, true])
    func saveAsOntoItsOwnFileIsASave(uploaded: Bool) async throws {
        defer { world.removeAll() }
        let folder = try world.storeSaveFolder()
        let coordinator = world.makeCoordinator()
        let (record, _) = try addSavedImage(to: coordinator, in: folder,
                                            uploadState: uploaded ? .uploaded(url: link, key: key) : .none,
                                            objectLocation: uploaded ? world.location : nil)
        let id = record.id
        let file = try #require(record.fileURL)
        coordinator.openEditor(recordID: id)
        let editor = try await openedEditor(id)
        editor.draw()
        #expect(await editor.saveAs(to: file))
        #expect(try EditorPixels.isBlue(png: Data(contentsOf: file)))
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path(percentEncoded: false)) == ["Shot.png"])
        try await eventually {
            coordinator.history.record(id: id)?.thumbnailFileName == coordinator.thumbnails.fileName(for: id, editedAt: world.date)
        }
        #expect(coordinator.history.record(id: id)?.editedAt == world.date)
        #expect(!world.notifier.calls.contains { if case .saved = $0 { return true } else { return false } })
        #expect(coordinator.history.record(id: id)?.uploadIsStale == uploaded)
        #expect(editor.pushes.last?.status == (uploaded ? EditorSaveTarget.uploadedCopyStaleNotice : nil))
        #expect(destination.state.withLock { $0.uploadAttempts } == 0)
    }

    /// phase-4b:76 (:104).
    /// Save As… with a crop draft still open writes a copy at the cropped pixel size and the capture's scale, pixel for
    /// pixel the export (which applies the draft first, as the window's export does, EWC:302-303), and leaves the
    /// capture's file, its folder and its record unchanged (+Editor:283-304, +RecordActions:291-297).
    @Test func saveAsWithACropWritesACroppedCopyAndLeavesTheCaptureAlone() async throws {
        defer { world.removeAll() }
        let folder = try world.storeSaveFolder()
        let coordinator = world.makeCoordinator()
        let png = try EditorPixels.png(width: 200, height: 100, scale: 2)
        let file = folder.appending(path: "Shot.png")
        try png.write(to: file)
        let record = CaptureRecord(fileURL: file, pixelWidth: 200, pixelHeight: 100, appName: nil, byteCount: png.count)
        coordinator.history.add(record)
        let url = try desktop("Crop.png")
        coordinator.openEditor(recordID: record.id)
        let editor = try await openedEditor(record.id)
        crop(editor.model, to: CGRect(x: 40, y: 20, width: 120, height: 60), apply: false)
        #expect(await editor.saveAs(to: url))
        let expected = try #require(await editor.export()).image.image
        let decoded = try EditorPixels.decoded(Data(contentsOf: url))
        #expect(decoded.image.width == 120)
        #expect(decoded.image.height == 60)
        #expect(decoded.scale == 2)
        #expect(EditorPixels.rgba(decoded.image) == EditorPixels.rgba(expected))
        #expect(try Data(contentsOf: file) == png)
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path(percentEncoded: false)) == ["Shot.png"])
        #expect(coordinator.history.record(id: record.id) == record)
        #expect(world.notifier.calls.contains(.saved(title: "Saved", file: "Crop.png")))
        #expect(world.clipboard.copies.isEmpty)
        #expect(world.factory.askedConfigs.isEmpty)
    }

    /// phase-7c:172 (:215), in part.
    /// Save As… with a solid background writes the composed image: the fill around the edit, 20 by 18 for a 4 by 2
    /// capture with padding 8. The capture is left alone: its record, its file, its folder and its thumbnail are
    /// unchanged, and with no clipboard owner the clipboard is untouched (+Editor:283-304, :436-446).
    /// Stays: the panel (`EDSAVEAS`).
    @Test func saveAsWithABackgroundWritesTheComposedImageAndLeavesTheCaptureAlone() async throws {
        defer { world.removeAll() }
        let folder = try world.storeSaveFolder()
        let coordinator = world.makeCoordinator()
        let original = try ImageEncoder.pngData(from: CoordinatorWorld.image(width: 4, height: 2), scale: 1)
        let file = folder.appending(path: "Shot.png")
        try original.write(to: file)
        let id = UUID()
        let thumb = try coordinator.thumbnails.write(Data("png".utf8), id: id)
        coordinator.history.add(CaptureRecord(id: id, fileURL: file, thumbnailFileName: thumb, pixelWidth: 4, pixelHeight: 2,
                                              appName: nil, byteCount: original.count))
        coordinator.openEditor(recordID: id)
        let editor = try await openedEditor(id)
        editor.draw()
        editor.model.setBackground(background)
        let before = coordinator.history.record(id: id)
        let target = try desktop("Composed.png")
        #expect(await editor.saveAs(to: target))
        let d = try EditorPixels.decoded(Data(contentsOf: target))
        #expect(d.image.width == 20 && d.image.height == 18)
        #expect(EditorPixels.pixel(d.image, x: 0, y: 0) == [0, 255, 0, 255])
        #expect(EditorPixels.isBlue(EditorPixels.pixel(d.image, x: 8, y: 8)))
        #expect(coordinator.history.record(id: id) == before)
        #expect(try Data(contentsOf: file) == original)
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path(percentEncoded: false)) == ["Shot.png"])
        #expect(coordinator.history.record(id: id)?.thumbnailFileName == "\(id.uuidString).png")
        #expect(world.notifier.calls.contains(.saved(title: "Saved", file: "Composed.png")))
        #expect(world.clipboard.copies.isEmpty)
        #expect(world.factory.askedConfigs.isEmpty)
    }

    /// phase-4a:112 (:165).
    /// With "Show notification" off, Copy puts the edit on the clipboard and owns it for the capture, and posts
    /// nothing (+Editor:451-466). The retained capture opens the editor at once, and the editor stays open and changed.
    @Test func copyWithShowNotificationOffPostsNothing() async throws {
        defer { world.removeAll() }
        world.settings.showNotification = false
        let coordinator = world.makeCoordinator()
        let record = CaptureRecord(fileURL: nil, pixelWidth: 4, pixelHeight: 2, appName: nil)
        coordinator.history.add(record)
        coordinator.latestCapture = (id: record.id, image: ScaledImage(image: try CoordinatorWorld.image(width: 4, height: 2), scale: 1))
        coordinator.openEditor(recordID: record.id)
        let editor = try #require(world.editors.editor(for: record.id))
        #expect(coordinator.openingEditorIDs.isEmpty)
        editor.draw()
        await editor.copy()
        #expect(world.clipboard.copies == [.pngAndTIFF])
        #expect(coordinator.clipboardOwner == EditorClipboard.Owner(recordID: record.id, changeCount: world.clipboard.changeCount))
        #expect(world.notifier.calls.isEmpty)
        #expect(editor.model.hasUnsavedChanges)
        #expect(!editor.isClosed)
        #expect(try EditorPixels.isBlue(png: world.clipboard.pngs[0]))
    }

    /// phase-4b:77 (:105); phase-4b:92 (:132), in part.
    /// Copy with nothing selected and a crop draft open puts the cropped image on the clipboard at the capture's
    /// scale, 144 dpi for a 2x capture, so its point size is half its pixels (Preview is the `pngs` decode). It says
    /// `Image copied` with the file's name, owns the clipboard, and leaves the file, the record and the window alone
    /// (+Editor:451-466). Then `editor.actions.objectClipboard.copy`, which the canvas's ⌘C calls with an object
    /// selected (EWC:75), copies the object and leaves the image's owner and the notices alone (+Editor:111-116).
    /// Stays: phase-4b:92, which command reaches the copy: ⌘C with and without a selection, ⇧⌘C, the toolbar button
    /// (`EDPLACE`).
    @Test func copyWithACropPutsTheCroppedImageAtPointSizeAndSaysImageCopied() async throws {
        defer { world.removeAll() }
        let folder = try world.storeSaveFolder()
        let coordinator = world.makeCoordinator()
        let png = try EditorPixels.png(width: 200, height: 100, scale: 2)
        let file = folder.appending(path: "Shot.png")
        try png.write(to: file)
        let record = CaptureRecord(fileURL: file, pixelWidth: 200, pixelHeight: 100, appName: nil, byteCount: png.count)
        let id = record.id
        coordinator.history.add(record)

        coordinator.openEditor(recordID: id)
        let editor = try await openedEditor(id)
        editor.model.commitNewShape(try #require(editor.model.makeAnnotation(.rectangle, from: CGPoint(x: 50, y: 30),
                                                                            to: CGPoint(x: 110, y: 70))))
        editor.model.selection = nil
        crop(editor.model, to: CGRect(x: 40, y: 20, width: 120, height: 60), apply: false)
        await editor.copy()
        let expected = try await expected(editor)
        editor.actions.objectClipboard.copy(Data("clip".utf8))

        #expect(world.clipboard.copies.first == .pngAndTIFF)
        #expect(world.clipboard.pngs.count == 1)
        let decoded = try EditorPixels.decoded(world.clipboard.pngs[0])
        #expect(decoded.image.width == 120)
        #expect(decoded.image.height == 60)
        #expect(decoded.scale == 2)
        #expect(abs(try #require(EditorPixels.dpiWidth(of: world.clipboard.pngs[0])) - 144) < 0.5)
        #expect(EditorPixels.rgba(decoded.image) == EditorPixels.rgba(expected))
        #expect(coordinator.clipboardOwner == EditorClipboard.Owner(recordID: id, changeCount: 1))
        #expect(world.notifier.calls == [.notice(title: "Image copied", body: "Shot.png")])
        #expect(try Data(contentsOf: file) == png)
        #expect(coordinator.history.record(id: id) == record)
        #expect(!editor.isClosed)
        #expect(world.clipboard.copies == [.pngAndTIFF, .annotationClip(Data("clip".utf8))])
        #expect(world.clipboard.copies.last == .annotationClip(Data("clip".utf8)))
        #expect(coordinator.clipboardOwner == EditorClipboard.Owner(recordID: id, changeCount: 1))
        #expect(world.notifier.calls.count == 1)
    }

    /// phase-7c:169 (:212), in part.
    /// Copy with a solid background puts the composed canvas on the clipboard (Preview is the `pngs` decode): 20 by 18
    /// at scale 1, the fill at both corners and the edit inside. It says `Image copied` with the file's name, owns the
    /// clipboard, and leaves the edit unsaved, since Copy never marks saved (+Editor:451-466).
    /// Stays: the window's routing to `copyImage` (`EDPLACE`).
    @Test func copyWithABackgroundPutsTheComposedCanvasOnTheClipboard() async throws {
        defer { world.removeAll() }
        let folder = try world.storeSaveFolder()
        let coordinator = world.makeCoordinator()
        let (record, _) = try addSavedImage(to: coordinator, in: folder)
        coordinator.openEditor(recordID: record.id)
        let editor = try await openedEditor(record.id)
        editor.draw()
        editor.model.setBackground(background)
        await editor.copy()
        #expect(world.clipboard.copies == [.pngAndTIFF])
        #expect(world.clipboard.pngs.count == 1)
        let d = try EditorPixels.decoded(world.clipboard.pngs[0])
        #expect(d.image.width == 20 && d.image.height == 18 && d.scale == 1)
        #expect(EditorPixels.pixel(d.image, x: 0, y: 0) == [0, 255, 0, 255])
        #expect(EditorPixels.pixel(d.image, x: 19, y: 17) == [0, 255, 0, 255])
        #expect(EditorPixels.isBlue(EditorPixels.pixel(d.image, x: 8, y: 8)))
        #expect(EditorPixels.isBlue(EditorPixels.pixel(d.image, x: 11, y: 9)))
        #expect(coordinator.clipboardOwner == EditorClipboard.Owner(recordID: record.id, changeCount: world.clipboard.changeCount))
        #expect(world.notifier.calls.contains(.notice(title: "Image copied", body: "Shot.png")))
        #expect(editor.model.hasUnsavedChanges)
    }

    nonisolated enum Write: CaseIterable, Sendable { case save, saveAs }

    /// phase-4a:115 (:168) `(.save, false)`; phase-4a:116 (:169) `(.saveAs, false)`; phase-4a:117 (:170)
    /// `(.saveAs, true)`; phase-4a:118 (:171) `(.save, true)`.
    /// The clipboard rule after Save and Save As…: while the clipboard still holds what TidyShot put there for the
    /// capture, the edit replaces it and TidyShot owns it at the new count; once something else was copied since
    /// (TextEdit's text), it is left alone (+Editor:218, :302, :436-446; the rule is `EditorClipboardTests`',
    /// EC:15-18). Preview is the `pngs` decode. The capture's own copy and owner are set up as +Save:57-67 leaves
    /// them; that step is in `save(_:intent:)` (`TARGET`), and no test pins it today.
    @Test(arguments: Write.allCases, [false, true])
    func aSaveOrSaveAsTakesTheClipboardOnlyWhileItHoldsTheCapture(write: Write, userCopied: Bool) async throws {
        defer { world.removeAll() }
        let folder = try world.storeSaveFolder()
        let coordinator = world.makeCoordinator()
        let (record, original) = try addSavedImage(to: coordinator, in: folder)
        let id = record.id
        coordinator.latestCapture = (id: id, image: ScaledImage(image: try CoordinatorWorld.image(width: 4, height: 2), scale: 1))
        let count = world.clipboard.copy(pngData: original, tiffData: nil)
        coordinator.clipboardOwner = EditorClipboard.Owner(recordID: id, changeCount: count)
        if userCopied { world.clipboard.setString("From TextEdit") }
        coordinator.openEditor(recordID: id)
        let editor = try #require(world.editors.editor(for: id))
        editor.draw()
        let writtenURL: URL
        switch write {
        case .save:
            #expect(await editor.save())
            writtenURL = try #require(record.fileURL)
        case .saveAs:
            writtenURL = try desktop("Shot.png")
            #expect(await editor.saveAs(to: writtenURL))
        }
        let written = try Data(contentsOf: writtenURL)
        #expect(try EditorPixels.isBlue(png: written))
        if userCopied {
            #expect(world.clipboard.copies == [.pngAndTIFF, .string("From TextEdit")])
            #expect(world.clipboard.pngs.count == 1)
            #expect(coordinator.clipboardOwner == EditorClipboard.Owner(recordID: id, changeCount: 1))
            #expect(world.clipboard.changeCount == 2)
        } else {
            #expect(world.clipboard.copies == [.pngAndTIFF, .pngAndTIFF])
            #expect(world.clipboard.pngs[1] == written)
            #expect(coordinator.clipboardOwner == EditorClipboard.Owner(recordID: id, changeCount: 2))
        }
        if write == .save { try await settledEdit(coordinator, id) }
    }
```

- [ ] **Step 3: Check the file.** From the repository root:

```bash
grep -c '^    @Test' TidyShotTests/CoordinatorEditorSaveTests.swift
grep -c 'nonisolated enum Write: CaseIterable, Sendable { case save, saveAs }' TidyShotTests/CoordinatorEditorSaveTests.swift
tail -3 TidyShotTests/CoordinatorEditorSaveTests.swift
python3 -I -c 'import sys; [print(f, n) for f in sys.argv[1:] for n, l in enumerate(open(f, encoding="utf-8"), 1) if "///" in l and len(l.rstrip("\n")) > 120]' TidyShotTests/CoordinatorEditorSaveTests.swift
git diff --stat
```

Expected: `17`; `1`; the file ends

```swift
        if write == .save { try await settledEdit(coordinator, id) }
    }
}
```

and `git diff --stat` prints ` TidyShotTests/CoordinatorEditorSaveTests.swift | 320 +++++…` and
` 1 file changed, 320 insertions(+)` (the blank line and the 319 lines of the block; nothing deleted). The width
check between them prints nothing (D75).

- [ ] **Step 4: Run the suite alone.**

```bash
xcodegen generate && xcodebuild test -project TidyShot.xcodeproj -scheme TidyShot -destination 'platform=macOS' -derivedDataPath .build -only-testing:TidyShotTests/CoordinatorEditorSaveTests 2>&1 | grep -E "Test run with|error:|TEST"
```

Expected:

```
✔ Test run with 17 tests in 1 suite passed after <n> seconds.
** TEST SUCCEEDED **
```

(Task 2's 8 and these 9; `xcodebuild` counts each parameterized test once, so `saveAsOntoItsOwnFileIsASave(uploaded:)` and
`aSaveOrSaveAsTakesTheClipboardOnlyWhileItHoldsTheCapture(write:userCopied:)` are one each.) The other lines the grep
lets through are the known noise, not failures: `com.apple.linkd.autoShortcut` (`Unable to get remoteObjectProxy, error:`
and `Unable to re-register with Process Instance Registry, error:`), `mdb_txn_commit error: MDB_MAP_FULL`, and on this
Mac one `iOSSimulator: [SimServiceContext sharedServiceContextForDeveloperDir:error:] returned nil … Simulator device
support disabled.` line. Any `error:` naming a `.swift` file, or a failed test, is a failure: fix the step that made it,
not the body (D11), and stop and report if a body itself fails.

- [ ] **Step 5: Run the full suite.**

```bash
xcodegen generate && xcodebuild test -project TidyShot.xcodeproj -scheme TidyShot -destination 'platform=macOS' -derivedDataPath .build 2>&1 | grep -E "Test run with|error:|TEST"
```

Expected:

```
✔ Test run with 2291 tests in 192 suites passed after <n> seconds.
** TEST SUCCEEDED **
```

with the known noise lines of Step 4 (and the two `History file could not be read or decoded, setting it aside` lines,
about 40 `MDB_MAP_FULL` lines). 2282 after Task 2, plus these 9; no new suite. The run takes 45 s to 130 s.

- [ ] **Step 6: Commit.** No other file has changed (`git status --short` prints only
` M TidyShotTests/CoordinatorEditorSaveTests.swift`). No attribution lines, no session URL, no push.

```bash
git add TidyShotTests/CoordinatorEditorSaveTests.swift
git commit -m "test: the editor's Save As… and Copy through the editor seam"
```

Expected: `[editor-seam <sha>] test: the editor's Save As… and Copy through the editor seam` and
` 1 file changed, 320 insertions(+)`.

- [ ] **Step 7: Report.** The focused line (`17 tests in 1 suite`), the full line (`2291 tests in 192 suites`), the commit's
short hash, and that no hand check was run (the hand checks are Tim's; nothing here runs the app).

### Task 4: `CoordinatorEditorUploadTests`, upload over a link and the first upload [integration]

**Files:**
- Create `TidyShotTests/CoordinatorEditorUploadTests.swift`: imports `CoreGraphics`, `Foundation`, `Testing`, `@testable import TidyShot`; the header the catalogue's section 4 gives (the built file's one-line header, :6, is the catalogue's first sentence only); `@Suite(.timeLimit(.minutes(1))) struct CoordinatorEditorUploadTests` with `let world: CoordinatorWorld`, `init() throws { world = try CoordinatorWorld() }`, the suite's helpers (D4), then the tests.

**Interfaces:**
- Consumes (Task 1): `FakeEditor` (`draw()`, `save()`, `upload(asNew:)`, `export()`, `isClosed`, `model`, `pushes`, `presentCount`, `title`, `representedURL`), `world.editors.editor(for:)`, `world.clipboard.pngs`, `EditorPixels.changedPixels`, `.decoded`, `.isBlue`, `.pixel`, `.png`, `.rgba`; the harness as in Task 1's Consumes, with `FakeDestination.State`'s `holdingUploadsRemaining`, `heldUploads` (released by `releaseUploads()`), `uploads`, `uploadAttempts`, `attemptKeys`, `deletedKeys`, `failure`, `failuresRemaining`, `dataDownloadKeys` and `downloadedData`.
- Produces, the suite's helpers (`key`, `link`, `destination`, `all`, `publicURL`, `openedEditor`, `reopenedEditor`, `settledEdit`, `addSavedImage`, `addPendingImage`, `desktop`, `pendingURL`, `addUploadOnly`, `isUploaded`, `title(of:)`, `exists`, `crop`, `addText`), used by Task 5:
  ```swift
  let key = "s/SHOT.png"
  var link: URL { URL(string: "https://snap.tky.io/\(key)")! }
  var destination: FakeDestination { world.factory.standard }
  var all: Set<EditorAction> { Set(EditorAction.allCases) }
  func publicURL(_ key: String) -> URL
  func openedEditor(_ id: UUID) async throws -> FakeEditor
  func reopenedEditor(_ id: UUID, after first: FakeEditor) async throws -> FakeEditor
  func settledEdit(_ coordinator: AppCoordinator, _ id: UUID) async throws
  func addSavedImage(to coordinator: AppCoordinator, in folder: URL, name: String = "Shot.png", uploadState: CaptureRecord.UploadState = .none, objectLocation: ObjectLocation? = nil, uploadIsStale: Bool = false, timestamp: Date = Date(), scale: CGFloat = 1) throws -> (record: CaptureRecord, original: Data)
  func addPendingImage(to coordinator: AppCoordinator) throws -> CaptureRecord
  func desktop(_ name: String) throws -> URL
  func pendingURL(_ coordinator: AppCoordinator, _ id: UUID) -> URL
  func addUploadOnly(to coordinator: AppCoordinator) throws -> CaptureRecord
  func isUploaded(_ coordinator: AppCoordinator, _ id: UUID) -> Bool
  func title(of record: CaptureRecord) -> String
  func exists(_ url: URL) -> Bool
  func crop(_ model: EditorModel, to rect: CGRect, apply: Bool)
  func addText(_ model: EditorModel, _ string: String, at point: CGPoint) throws -> TextBox
  ```

**Tests:**
1. `uploadWritesTheFileFirstThenReplacesTheLinksObject`: catalogue section 4 (CoordinatorEditorUploadTests.swift), "Upload over a link, and the first upload", tests-editor.md:792; effort M.
2. `uploadOfAnUploadOnlyCaptureWritesPendingThenReplacesItsKey`: catalogue section 4 (CoordinatorEditorUploadTests.swift), "Upload over a link, and the first upload", tests-editor.md:835; effort M.
3. `annotateTheNewestCardSaveThenUploadWritesTheFileThenUploadsAndCopiesTheURL`: catalogue section 4 (CoordinatorEditorUploadTests.swift), "Upload over a link, and the first upload", tests-editor.md:872; effort L.
4. `anUploadAfterTheCapturesOwnClosesAtOnceAndEndsWithTheLinkCopied`: catalogue section 4 (CoordinatorEditorUploadTests.swift), "Upload over a link, and the first upload", tests-editor.md:938; effort M.
5. `withNoDestinationSaveTakesTheClipboardAndUploadIsRefused`: catalogue section 4 (CoordinatorEditorUploadTests.swift), "Upload over a link, and the first upload", tests-editor.md:956; effort S.
6. `uploadAsNewWithoutALinkIsRefusedAndUploadMakesTheFirstLink`: catalogue section 4 (CoordinatorEditorUploadTests.swift), "Upload over a link, and the first upload", tests-editor.md:978; effort M.
7. `uploadOfAPrePhase3CaptureMakesANewLinkAndDeletesNothing`: catalogue section 4 (CoordinatorEditorUploadTests.swift), "Upload over a link, and the first upload", tests-editor.md:995; effort S.
8. `uploadAfterTheDestinationChangedGoesToTheNewBucketAndDeletesTheOldObject`: catalogue section 4 (CoordinatorEditorUploadTests.swift), "Upload over a link, and the first upload", tests-editor.md:1009; effort M.
9. `anUploadedCaptureReopensFlatWithItsMarksInThePixels`: catalogue section 4 (CoordinatorEditorUploadTests.swift), "Upload over a link, and the first upload", tests-editor.md:1029; effort M.
- 9 tests (S 2, M 6, L 1), 0 parameterized.
- Focused run, `-only-testing:TidyShotTests/CoordinatorEditorUploadTests`: `Test run with 9 tests in 1 suite passed`.
- Full suite: `Test run with 2300 tests in 193 suites passed`.

**Commit:** `test: the editor's Upload over a link and the first upload through the editor seam`

**Steps:**

- [ ] **Step 1: Check the starting point.** Task 3 is committed and the tree is clean, and the file this task creates does not exist yet:
  ```bash
  git status --short && git log --oneline -1 && ls TidyShotTests/CoordinatorEditorUploadTests.swift
  ```
  Expected: no `git status` lines; the last commit is Task 3's `test: the editor's Save As… and Copy through the editor seam`; `ls` prints `No such file or directory`. Task 1 has put in place everything this file uses, with these signatures (read them in the tree before writing):
  - `TidyShotTests/Support/EditorFakes.swift` (Task 1): `final class FakeEditor: EditorPresenting` with `let model: EditorModel`, `let title: String`, `let representedURL: URL?`, `private(set) var isClosed`, `var presentCount: Int`, `var pushes: [Push]` (`Push.record`, `.available: Set<EditorAction>`, `.status: String?`, `.saveCommand: EditorSaveCommand`), `func draw()`, `func export() async -> (image: ScaledImage, document: AnnotationDocument)?`, `@discardableResult func save() async -> Bool`, `@discardableResult func upload(asNew: Bool = false) async -> EditorUploadOutcome`; `final class FakeEditors` with `func editor(for id: UUID) -> FakeEditor?` (the newest built for `id`).
  - `TidyShotTests/Support/CoordinatorWorld.swift`: `let editors = FakeEditors()` (Task 1), `func makeCoordinator() -> AppCoordinator` (:131), `func removeAll()` (:141), `func storeSaveFolder() throws -> URL` (:151), `static func image(width: Int, height: Int) throws -> CGImage` (:170), `static func pngData(width: Int, height: Int) throws -> Data` (:180), `static let config` (:19), `let root: URL` (:25), `let credentials: InMemoryCredentialStore` (:35), `let notifier`, `cards`, `clipboard` (:38-40), `let factory` (:44), `var location: ObjectLocation` (:90), `var date: Date { get set }` (:92-95), `enum CoordinatorWorldError { case noFile }` (:6-8).
  - `TidyShotTests/Support/CoordinatorFakes.swift`: `FakeNotifier.Call` `.uploaded(url: URL, copied: Bool)` (:12), `.notice(title: String, body: String, subtitle: String? = nil)` (:14), `var errors: [(title: String, message: String)]` (:23); `FakeCards.Call.close(UUID, QuickAccessCloseReason)` (:76), `var showing: Set<UUID>` (:88), `func updates(for id: UUID) -> [CaptureRecord.UploadState]` (:138); `FakeClipboard.copy(pngData: Data, tiffData: Data?) -> Int` (:173); `FakeDestinationFactory.add(_ destination: FakeDestination, at location: ObjectLocation)` (:234), `askedConfigs` (:239), `askedLocations` (:240).
  - `TidyShotTests/Support/FakeDestination.swift`: `State.uploads: [(key: String, data: Data, contentType: String, cacheControl: String?)]` (:15), `uploadAttempts` (:17), `holdingUploadsRemaining` (:26), `heldUploads` (:28), `downloadedData` (:104), `dataDownloadKeys` (:105), `deletedKeys` (:109); `init(_ state: State = State())` (:136); `func releaseUploads(throwing error: (any Error)? = nil)` (:256).
  - `TidyShotTests/UploadQueueTests.swift:42`: `func eventually(_ condition: () async -> Bool) async throws`.
  - `TidyShotTests/Support/EditorPixels.swift` (Task 1): `png(width:height:scale:white:) throws -> Data`, `decoded(_:) throws -> (image: CGImage, scale: CGFloat)`, `rgba(_:) -> [UInt8]`, `pixel(_ image: CGImage, x:y:) -> [Int]`, `pixel(_ png: Data, x:y:) throws -> [Int]`, `changedPixels(_:in:from:) -> Int`, `isBlue(_ pixel: [Int]) -> Bool`, `isBlue(png: Data) throws -> Bool`.
  - Production at dd1231d: `AppCoordinator.openEditor(recordID: UUID)` (AppCoordinator+Editor.swift:15), `hasUnsavedEditors` (+Editor:7), `latestCapture: (id: UUID, image: ScaledImage)?` (AppCoordinator.swift:133), `openingEditorIDs: Set<UUID>` (:253), `clipboardOwner: EditorClipboard.Owner?` (:257), `editors: [UUID: any EditorPresenting]` (:259 after Task 1); `makeDestination() -> UploadTarget?` (AppCoordinator+Upload.swift:39), `destinationDidChange()` (+Upload:78), `startUpload(recordID: UUID, payload: UploadPayload, destination: UploadTarget, fixedKey: String? = nil)` (+Upload:138), `nonisolated static let uploadNotConfiguredBody` (+Upload:34); `PendingFileStore.write(_ data: Data, id: UUID, ext: String) throws -> URL` (TidyShot/Output/PendingFileStore.swift:21); `ThumbnailStore.fileName(for id: UUID, editedAt: Date?) -> String` (TidyShot/History/ThumbnailStore.swift:28); `ClosedOverlays.ids: [UUID]` (TidyShot/Overlay/ClosedOverlays.swift:8); `CaptureRecord.init(id:timestamp:fileURL:fileIsTemporary:thumbnailFileName:pixelWidth:pixelHeight:appName:uploadState:objectLocation:…:uploadIsStale:…:byteCount:…)` (TidyShot/History/CaptureRecord.swift:114-120), `uploadedURL` (:185), `uploadedKey` (:191), `isUploading` (:267), `struct PriorUpload { url, key, location, isReplace }` (:276-281); `EditorUploadOutcome(wroteLocally:enqueued:)` and `.refused` (TidyShot/Editor/Persistence/EditorUploadPlan.swift:217-224), `EditorUploadPlan.cacheNote` (:36); `EditorSaveTarget.noFileReason` (EditorSaveTarget.swift:16); `EditorAvailability.uploadingStatus` (EditorSaveTarget.swift:112); `KeychainCredentialStore.defaultAccount` (TidyShot/Upload/KeychainCredentialStore.swift:28) and `delete(account:)` (:80, the in-memory store); `TextLayout.frame(for box: TextBox) -> CGRect` (TidyShot/Editor/Geometry/TextLayout.swift:68); `Annotation.counterMark` (TidyShot/Editor/Model/Annotation.swift:121); `AnnotationDocument.spotlights` (AnnotationDocument.swift:30).

- [ ] **Step 2: Create `TidyShotTests/CoordinatorEditorUploadTests.swift`** with exactly this content (the suite's helpers in catalogue 2.2's order with `all` after `link` (D5), then the nine tests in the catalogue's order, section 4 "Upload over a link, and the first upload"):
  ```swift
  import CoreGraphics
  import Foundation
  import Testing
  @testable import TidyShot

  /// The editor's Upload through the editor seam: the local write first, then the live lane over the link's own key or
  /// a new one; the window's close is the fake's (`closesWindow`), the controller's `performUpload` does not run.
  @Suite(.timeLimit(.minutes(1)))
  struct CoordinatorEditorUploadTests {
      let world: CoordinatorWorld
      let key = "s/SHOT.png"

      init() throws {
          world = try CoordinatorWorld()
      }

      var destination: FakeDestination { world.factory.standard }
      var link: URL { URL(string: "https://snap.tky.io/\(key)")! }
      var all: Set<EditorAction> { Set(EditorAction.allCases) }

      func publicURL(_ key: String) -> URL { URL(string: "https://snap.tky.io/\(key)")! }

      func openedEditor(_ id: UUID) async throws -> FakeEditor {
          try await eventually { world.editors.editor(for: id) != nil }
          return try #require(world.editors.editor(for: id))
      }

      func reopenedEditor(_ id: UUID, after first: FakeEditor) async throws -> FakeEditor {
          try await eventually { world.editors.editor(for: id).map { $0 !== first } ?? false }
          return try #require(world.editors.editor(for: id))
      }

      /// The last edit's thumbnail named on the record (+Editor:249-275), so its task does not outlive the test.
      func settledEdit(_ coordinator: AppCoordinator, _ id: UUID) async throws {
          try await eventually {
              coordinator.history.record(id: id)?.thumbnailFileName == coordinator.thumbnails.fileName(for: id, editedAt: world.date)
          }
      }

      func addSavedImage(to coordinator: AppCoordinator, in folder: URL, name: String = "Shot.png",
                         uploadState: CaptureRecord.UploadState = .none, objectLocation: ObjectLocation? = nil,
                         uploadIsStale: Bool = false, timestamp: Date = Date(),
                         scale: CGFloat = 1) throws -> (record: CaptureRecord, original: Data) {
          let original = try ImageEncoder.pngData(from: CoordinatorWorld.image(width: 4, height: 2), scale: scale)
          let file = folder.appending(path: name)
          try original.write(to: file)
          let record = CaptureRecord(timestamp: timestamp, fileURL: file, pixelWidth: 4, pixelHeight: 2, appName: nil,
                                     uploadState: uploadState, objectLocation: objectLocation,
                                     uploadIsStale: uploadIsStale, byteCount: original.count)
          coordinator.history.add(record)
          return (record, original)
      }

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

      func desktop(_ name: String) throws -> URL {
          let folder = world.root.appending(path: "Desktop", directoryHint: .isDirectory)
          try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
          return folder.appending(path: name)
      }

      func pendingURL(_ coordinator: AppCoordinator, _ id: UUID) -> URL {
          coordinator.pendingFiles.directory.appending(path: "\(id.uuidString).png")
      }

      func addUploadOnly(to coordinator: AppCoordinator) throws -> CaptureRecord {
          let png = try CoordinatorWorld.pngData(width: 4, height: 2)
          destination.state.withLock { $0.downloadedData = png }
          let record = CaptureRecord(fileURL: nil, pixelWidth: 4, pixelHeight: 2, appName: nil,
                                     uploadState: .uploaded(url: link, key: key), objectLocation: world.location)
          coordinator.history.add(record)
          return record
      }

      func isUploaded(_ coordinator: AppCoordinator, _ id: UUID) -> Bool {
          if case .uploaded = coordinator.history.record(id: id)?.uploadState { return true }
          return false
      }

      func title(of record: CaptureRecord) -> String {
          "Capture \(record.timestamp.formatted(date: .omitted, time: .shortened))"
      }

      func exists(_ url: URL) -> Bool { FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) }

      func crop(_ model: EditorModel, to rect: CGRect, apply: Bool) {
          model.tool = .crop
          model.cropDraft = rect
          if apply { model.applyCrop() }
      }

      func addText(_ model: EditorModel, _ string: String, at point: CGPoint) throws -> TextBox {
          model.beginTextEditing(at: point, existing: nil)
          model.updateEditingText(string)
          model.commitTextEditing()
          for annotation in model.document.annotations {
              if case .text(let box) = annotation { return box }
          }
          throw CoordinatorWorldError.noFile
      }

      /// phase-4a:123 (:176), in part; phase-4b:74 (:102); phase-4b:106 (:150), in part. Upload on a save-folder
      /// capture with a link (a highlight and a pending crop on a white 200 by 100 base at 2x) writes the cropped edit
      /// over the file first, then PUTs those same bytes over the link's own key with `Cache-Control: no-cache`; while
      /// the PUT is held the editor hears `Uploading…` and the row shows the upload, the editor closes once the upload
      /// is enqueued, and the link replaces the clipboard with the cache notice. `curl` and `sips` are the PUT body's
      /// decode. Stays: phase-4a:123, closing with no unsaved-changes sheet (`EDPLACE`: the fake applies
      /// `closesWindow`, the controller's close does not run); the link showing the redaction is the PUT body under
      /// the link's key. phase-4b:106, closing at once (`EDPLACE`).
      @Test func uploadWritesTheFileFirstThenReplacesTheLinksObject() async throws {
          defer { world.removeAll() }
          let folder = try world.storeSaveFolder()
          destination.state.withLock { $0.holdingUploadsRemaining = 1 }
          defer { destination.releaseUploads() }
          let coordinator = world.makeCoordinator()
          let png = try EditorPixels.png(width: 200, height: 100, scale: 2, white: true)
          let file = folder.appending(path: "Shot.png")
          try png.write(to: file)
          let record = CaptureRecord(fileURL: file, pixelWidth: 200, pixelHeight: 100, appName: nil,
                                     uploadState: .uploaded(url: link, key: key), objectLocation: world.location)
          let id = record.id
          coordinator.history.add(record)

          coordinator.openEditor(recordID: id)
          let editor = try await openedEditor(id)
          let first = try #require(editor.pushes.first)
          #expect(first.status == nil)
          #expect(first.available == all)
          #expect(first.saveCommand == .writeOver)
          editor.model.commitNewShape(try #require(editor.model.makeStroke(.highlighter, points: [CGPoint(x: 50, y: 50),
                                                                                                CGPoint(x: 150, y: 50)])))
          crop(editor.model, to: CGRect(x: 40, y: 20, width: 120, height: 60), apply: false)

          let outcome = await editor.upload()

          #expect(outcome == EditorUploadOutcome(wroteLocally: true, enqueued: true))
          #expect(editor.isClosed)
          #expect(coordinator.editors[id] == nil)
          #expect(!editor.model.hasUnsavedChanges)
          try await eventually { destination.state.withLock { $0.heldUploads.count } == 1 }
          let expected = try #require(await editor.export()).image.image
          let written = try Data(contentsOf: file)
          let decodedFile = try EditorPixels.decoded(written)
          #expect(decodedFile.image.width == 120)
          #expect(decodedFile.image.height == 60)
          #expect(decodedFile.scale == 2)
          #expect(EditorPixels.rgba(decodedFile.image) == EditorPixels.rgba(expected))
          let held = try #require(coordinator.history.record(id: id))
          #expect(held.pixelWidth == 120)
          #expect(held.pixelHeight == 60)
          #expect(held.priorUpload == PriorUpload(url: link, key: key, location: world.location, isReplace: true))
          #expect(held.isUploading)
          #expect(editor.pushes.last?.status == EditorAvailability.uploadingStatus)
          #expect(editor.pushes.last?.available == [.copy, .saveAs])
          #expect(world.cards.updates(for: id).contains(.uploading(fraction: 0)))
          #expect(world.clipboard.copies.isEmpty)

          destination.releaseUploads()
          try await eventually { coordinator.history.record(id: id)?.isUploading == false }

          let uploads = destination.state.withLock { $0.uploads }
          #expect(uploads.map(\.key) == [key])
          #expect(uploads.first?.cacheControl == "no-cache")
          #expect(uploads.first?.data == (try Data(contentsOf: file)))
          let decoded = try EditorPixels.decoded(try #require(uploads.first?.data))
          #expect(decoded.image.width == 120)
          #expect(decoded.image.height == 60)
          #expect(decoded.scale == 2)
          #expect(EditorPixels.pixel(decoded.image, x: 60, y: 30)[2] < 180)
          #expect(EditorPixels.pixel(decoded.image, x: 60, y: 2) == [255, 255, 255, 255])
          let after = try #require(coordinator.history.record(id: id))
          #expect(after.uploadState == .uploaded(url: link, key: key))
          #expect(after.uploadIsStale == false)
          #expect(after.priorUpload == nil)
          #expect(after.pixelWidth == 120)
          #expect(after.pixelHeight == 60)
          #expect(world.clipboard.copies == [.url(link)])
          #expect(world.notifier.calls.contains(.notice(title: "Uploaded, URL copied", body: EditorUploadPlan.cacheNote)))
          #expect(destination.state.withLock { $0.deletedKeys }.isEmpty)
          try await settledEdit(coordinator, id)
      }

      /// phase-4a:124 (:177), in part; phase-4b:75 (:103); phase-4b:108 (:152). An uploaded upload-only capture opens
      /// from its downloaded object (`Opening the capture…`, titled as a capture with no file, first heard with no
      /// file to save over); Upload with a text box and a pending crop writes the edit to a new `pending/<id>.png`
      /// first, then PUTs those bytes over the link's own key with `Cache-Control: no-cache`, the text in the object.
      /// Once it lands the record is upload-only again with its pending file gone, and the link replaces the clipboard.
      /// The link serving and showing the redaction is the PUT body under the same key. Stays: phase-4a:124, the
      /// window closing (`EDPLACE`).
      @Test func uploadOfAnUploadOnlyCaptureWritesPendingThenReplacesItsKey() async throws {
          defer { world.removeAll() }
          let png = try EditorPixels.png(width: 200, height: 100, scale: 2, white: true)
          destination.state.withLock { $0.downloadedData = png; $0.holdingUploadsRemaining = 1 }
          defer { destination.releaseUploads() }
          let coordinator = world.makeCoordinator()
          let record = CaptureRecord(fileURL: nil, pixelWidth: 200, pixelHeight: 100, appName: nil,
                                     uploadState: .uploaded(url: link, key: key), objectLocation: world.location)
          let id = record.id
          coordinator.history.add(record)
          coordinator.openEditor(recordID: id)
          let editor = try await openedEditor(id)
          #expect(destination.state.withLock { $0.dataDownloadKeys } == [key])
          #expect(world.notifier.calls.contains(.notice(title: "Opening the capture…", body: "Downloading \(key)")))
          #expect(editor.title == title(of: record))
          #expect(editor.representedURL == nil)
          #expect(editor.model.base.width == 200 && editor.model.scale == 2)
          let first = try #require(editor.pushes.first)
          #expect(first.status == EditorSaveTarget.noFileReason)
          #expect(first.saveCommand == .saveAs)
          #expect(first.available == all)
          let box = try addText(editor.model, "Edit", at: CGPoint(x: 80, y: 50))
          crop(editor.model, to: CGRect(x: 40, y: 20, width: 120, height: 60), apply: false)
          let outcome = await editor.upload()
          #expect(outcome == EditorUploadOutcome(wroteLocally: true, enqueued: true))
          #expect(editor.isClosed)
          #expect(coordinator.editors[id] == nil)
          try await eventually { destination.state.withLock { $0.heldUploads.count } == 1 }
          let expected = try #require(await editor.export()).image.image
          let held = try #require(coordinator.history.record(id: id))
          #expect(held.fileURL == pendingURL(coordinator, id))
          #expect(held.fileIsTemporary == true)
          #expect(held.uploadIsStale == true)
          #expect(held.isUploading)
          let pendingBytes = try Data(contentsOf: pendingURL(coordinator, id))
          let pd = try EditorPixels.decoded(pendingBytes)
          #expect(pd.image.width == 120 && pd.image.height == 60)
          #expect(EditorPixels.rgba(pd.image) == EditorPixels.rgba(expected))
          #expect(world.clipboard.copies.isEmpty)
          destination.releaseUploads()
          try await eventually { coordinator.history.record(id: id)?.isUploading == false }
          let uploads = destination.state.withLock { $0.uploads }
          #expect(uploads.map(\.key) == [key])
          #expect(uploads.first?.cacheControl == "no-cache")
          #expect(uploads.first?.data == pendingBytes)
          let d = try EditorPixels.decoded(try #require(uploads.first?.data))
          #expect(d.image.width == 120 && d.image.height == 60 && d.scale == 2)
          #expect(EditorPixels.rgba(d.image) == EditorPixels.rgba(expected))
          #expect(EditorPixels.changedPixels(d.image, in: TextLayout.frame(for: box).offsetBy(dx: -40, dy: -20), from: [255, 255, 255]) > 0)
          let done = try #require(coordinator.history.record(id: id))
          #expect(done.uploadState == .uploaded(url: link, key: key))
          #expect(done.fileURL == nil)
          #expect(done.fileIsTemporary == false)
          #expect(!exists(pendingURL(coordinator, id)))
          #expect(done.uploadIsStale == false)
          #expect(done.pixelWidth == 120 && done.pixelHeight == 60)
          #expect(world.clipboard.copies == [.url(link)])
          #expect(world.notifier.calls.contains(.notice(title: "Uploaded, URL copied", body: EditorUploadPlan.cacheNote)))
          try await settledEdit(coordinator, id)
      }

      /// coordinator-split:43 (:43), in part; small-tweaks:18 (:21); phase-6b:118 (:144), in part. The capture is set up
      /// as a new "Save and copy image" capture leaves it (the file in the save folder, the card up, its image retained
      /// and on the clipboard); it is the entry to the flow, not a check. Annotate opens the editor at once from the
      /// retained image (no load), titled by the file, and closes the card for good. A box makes the editor unsaved
      /// (`hasUnsavedEditors` stands in for the unsaved dot); Save writes the same file with the box (its decoded pixels
      /// stand in for Quick Look), uploads nothing, records the file's size, clears the unsaved state and puts the edit
      /// on the clipboard in place of the capture's image. Upload then closes the editor, PUTs the file's bytes as a new
      /// object, copies its URL in place of the image and records the uploaded size. Stays: coordinator-split:43, the
      /// unsaved dot and the window closing (`EDPLACE`); the URL showing the stroke is the PUT body, and the real
      /// bucket, by hand. phase-6b:118, reaching `save(_:intent:)` with the after-capture action first (`TARGET`), and
      /// the `action=pin` half (`PINS`).
      @Test func annotateTheNewestCardSaveThenUploadWritesTheFileThenUploadsAndCopiesTheURL() async throws {
          defer { world.removeAll() }
          let folder = try world.storeSaveFolder()
          let coordinator = world.makeCoordinator()
          let (record, original) = try addSavedImage(to: coordinator, in: folder)
          let id = record.id
          let file = try #require(record.fileURL)
          world.cards.showing.insert(id)
          let image = try CoordinatorWorld.image(width: 4, height: 2)
          coordinator.latestCapture = (id: id, image: ScaledImage(image: image, scale: 1))
          let count = world.clipboard.copy(pngData: original, tiffData: nil)
          coordinator.clipboardOwner = EditorClipboard.Owner(recordID: id, changeCount: count)

          coordinator.openEditor(recordID: id)
          let editor = try #require(world.editors.editor(for: id))
          #expect(coordinator.openingEditorIDs.isEmpty)
          #expect(editor.model.base === image)
          #expect(editor.model.scale == 1)
          #expect(editor.title == "Shot.png")
          #expect(editor.representedURL == file)
          #expect(editor.presentCount == 1)
          #expect(editor.pushes.first?.record == coordinator.history.record(id: id))
          #expect(editor.pushes.first?.saveCommand == .writeOver)
          #expect(editor.pushes.first?.available == all.subtracting([.uploadAsNew]))
          #expect(world.cards.calls.contains(.close(id, .editorOpened)))
          #expect(world.cards.showing.isEmpty)
          #expect(coordinator.latestCapture == nil)
          #expect(!coordinator.closedOverlays.ids.contains(id))
          #expect(destination.state.withLock { $0.dataDownloadKeys }.isEmpty)

          editor.draw()
          #expect(coordinator.hasUnsavedEditors)
          #expect(await editor.save())
          let written = try Data(contentsOf: file)
          #expect(written != original)
          #expect(EditorPixels.isBlue(try EditorPixels.pixel(written, x: 0, y: 0)))
          #expect(EditorPixels.isBlue(try EditorPixels.pixel(written, x: 3, y: 1)))
          #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path(percentEncoded: false)) == ["Shot.png"])
          #expect(world.factory.askedConfigs.isEmpty)
          #expect(destination.state.withLock { $0.uploadAttempts } == 0)
          #expect(coordinator.history.record(id: id)?.uploadState == CaptureRecord.UploadState.none)
          #expect(coordinator.history.record(id: id)?.byteCount == written.count)
          #expect(!coordinator.hasUnsavedEditors)
          #expect(world.clipboard.copies == [.pngAndTIFF, .pngAndTIFF])
          #expect(world.clipboard.pngs.last == written)
          #expect(world.notifier.errors.isEmpty)

          world.date = world.date.addingTimeInterval(1)
          let outcome = await editor.upload()
          #expect(outcome == EditorUploadOutcome(wroteLocally: true, enqueued: true))
          #expect(editor.isClosed)
          #expect(coordinator.editors[id] == nil)
          #expect(world.factory.askedConfigs == [CoordinatorWorld.config])

          try await eventually { coordinator.history.record(id: id)?.uploadedKey != nil }
          let uploads = destination.state.withLock { $0.uploads }
          #expect(uploads.count == 1)
          #expect(uploads.first?.data == (try Data(contentsOf: file)))
          #expect(EditorPixels.isBlue(try EditorPixels.pixel(try #require(uploads.first?.data), x: 0, y: 0)))
          #expect(uploads.first?.cacheControl == nil)
          let url = publicURL(try #require(uploads.first?.key))
          #expect(coordinator.history.record(id: id)?.uploadState == .uploaded(url: url, key: try #require(uploads.first?.key)))
          #expect(world.clipboard.copies == [.pngAndTIFF, .pngAndTIFF, .pngAndTIFF, .url(url)])
          #expect(world.notifier.calls.contains(.uploaded(url: url, copied: true)))
          #expect(coordinator.history.record(id: id)?.byteCount == uploads.first?.data.count)
          try await settledEdit(coordinator, id)
      }

      /// phase-4a:120 (:173), in part. The capture's own upload is set up as "Also copy image" leaves it (the image
      /// copied and owned, then the upload landing and its URL copied); an editor opened from the card then uploads a
      /// box over the same key, closes while the PUT is held, leaves the clipboard's URL alone during the local write,
      /// and ends with the same link copied again. Stays: the window closing (`EDPLACE`); the capture's own copy is set
      /// up as +Save:30-31, :57-67 leave it (`TARGET`).
      @Test func anUploadAfterTheCapturesOwnClosesAtOnceAndEndsWithTheLinkCopied() async throws {
          defer { world.removeAll() }
          let folder = try world.storeSaveFolder()
          let coordinator = world.makeCoordinator()
          let (record, original) = try addSavedImage(to: coordinator, in: folder, uploadState: .uploading(fraction: 0))
          let id = record.id
          let count = world.clipboard.copy(pngData: original, tiffData: nil)
          coordinator.clipboardOwner = EditorClipboard.Owner(recordID: id, changeCount: count)
          coordinator.startUpload(recordID: id, payload: .data(original), destination: try #require(coordinator.makeDestination()))
          try await eventually { isUploaded(coordinator, id) }
          let k1 = try #require(coordinator.history.record(id: id)?.uploadedKey)
          let url1 = try #require(coordinator.history.record(id: id)?.uploadedURL)
          #expect(world.clipboard.copies == [.pngAndTIFF, .url(url1)])
          coordinator.latestCapture = (id: id, image: ScaledImage(image: try CoordinatorWorld.image(width: 4, height: 2), scale: 1))
          destination.state.withLock { $0.holdingUploadsRemaining = 1 }
          defer { destination.releaseUploads() }
          coordinator.openEditor(recordID: id)
          let editor = try #require(world.editors.editor(for: id))
          editor.draw()
          #expect(await editor.upload() == EditorUploadOutcome(wroteLocally: true, enqueued: true))
          try await eventually { destination.state.withLock { $0.heldUploads.count } == 1 }
          #expect(editor.isClosed)
          #expect(coordinator.editors[id] == nil)
          #expect(world.clipboard.copies == [.pngAndTIFF, .url(url1)])
          destination.releaseUploads()
          try await eventually { coordinator.history.record(id: id)?.isUploading == false }
          #expect(world.clipboard.copies == [.pngAndTIFF, .url(url1), .url(url1)])
          #expect(coordinator.history.record(id: id)?.uploadState == .uploaded(url: url1, key: k1))
          let uploads = destination.state.withLock { $0.uploads }
          #expect(uploads.map(\.key) == [k1, k1])
          #expect(try EditorPixels.isBlue(png: try #require(uploads.last?.data)))
          try await settledEdit(coordinator, id)
      }

      /// phase-4a:119 (:172), in part. The capture is set up as "Upload and copy URL" leaves it with no destination (the
      /// credentials forgotten, the file saved, the image copied and owned). Save takes the clipboard for the edit;
      /// Upload is refused with `Upload not configured` and writes nothing, copies nothing and asks for no
      /// destination, and the editor stays open and unsaved. Stays: the window staying open (`EDPLACE`); the capture's
      /// own copy is set up as +Save:32-34, :57-67 leave it with no destination (`TARGET`).
      @Test func withNoDestinationSaveTakesTheClipboardAndUploadIsRefused() async throws {
          defer { world.removeAll() }
          try world.credentials.delete(account: KeychainCredentialStore.defaultAccount)
          let folder = try world.storeSaveFolder()
          let coordinator = world.makeCoordinator()
          let (record, original) = try addSavedImage(to: coordinator, in: folder)
          let id = record.id
          let file = try #require(record.fileURL)
          let count = world.clipboard.copy(pngData: original, tiffData: nil)
          coordinator.clipboardOwner = EditorClipboard.Owner(recordID: id, changeCount: count)
          coordinator.latestCapture = (id: id, image: ScaledImage(image: try CoordinatorWorld.image(width: 4, height: 2), scale: 1))
          coordinator.openEditor(recordID: id)
          let editor = try #require(world.editors.editor(for: id))
          editor.draw()
          #expect(await editor.save())
          try await settledEdit(coordinator, id)
          let saved = try Data(contentsOf: file)
          let afterSave = coordinator.history.record(id: id)
          #expect(world.clipboard.copies == [.pngAndTIFF, .pngAndTIFF])
          #expect(world.clipboard.pngs[1] == saved)
          // A second box over the first, so the document is unsaved again before the Upload.
          editor.draw()
          #expect(await editor.upload() == .refused)
          #expect(world.notifier.errors.last?.title == "Upload not configured")
          #expect(world.notifier.errors.last?.message == AppCoordinator.uploadNotConfiguredBody)
          #expect(AppCoordinator.uploadNotConfiguredBody == "Set up a destination in Settings > Upload, then upload again.")
          #expect(try Data(contentsOf: file) == saved)
          #expect(coordinator.history.record(id: id) == afterSave)
          #expect(world.clipboard.copies.count == 2)
          #expect(world.factory.askedConfigs.isEmpty)
          #expect(!editor.isClosed)
          #expect(coordinator.editors[id] === editor)
          #expect(editor.model.hasUnsavedChanges)
      }

      /// phase-4a:127 (:185), in part. A save-folder capture that was never uploaded is first heard without Upload as
      /// New; `upload(asNew: true)` calls the editor's upload action past the window's validation, which would block
      /// ⌥⌘U (design 3.4), to reach the coordinator's write-time refusal: `Not uploaded`, nothing written, the editor
      /// open, no PUT. Upload then writes the file first and makes the capture's first link, copied, with no `New link`
      /// notice. Stays: ⌥⌘U refused by the window's validation, so it does nothing (`EDPLACE`), and its beep (`BEEP`);
      /// the window closing (`EDPLACE`). The refusal's notice is one the window's beep never lets happen.
      @Test func uploadAsNewWithoutALinkIsRefusedAndUploadMakesTheFirstLink() async throws {
          defer { world.removeAll() }
          let folder = try world.storeSaveFolder()
          let coordinator = world.makeCoordinator()
          let (record, original) = try addSavedImage(to: coordinator, in: folder)
          let id = record.id
          let file = try #require(record.fileURL)
          coordinator.openEditor(recordID: id)
          let editor = try await openedEditor(id)
          #expect(editor.pushes.first?.available == all.subtracting([.uploadAsNew]))
          editor.draw()
          #expect(await editor.upload(asNew: true) == .refused)
          #expect(world.notifier.errors.last?.title == "Not uploaded")
          #expect(world.notifier.errors.last?.message == "This capture has no link yet. Use Upload.")
          #expect(try Data(contentsOf: file) == original)
          #expect(!editor.isClosed)
          #expect(destination.state.withLock { $0.uploadAttempts } == 0)
          #expect(await editor.upload() == EditorUploadOutcome(wroteLocally: true, enqueued: true))
          #expect(editor.isClosed)
          #expect(try EditorPixels.isBlue(png: Data(contentsOf: file)))
          try await eventually { isUploaded(coordinator, id) }
          let k = try #require(coordinator.history.record(id: id)?.uploadedKey)
          let done = try #require(coordinator.history.record(id: id))
          #expect(done.uploadState == .uploaded(url: publicURL(k), key: k))
          #expect(done.objectLocation == world.location)
          #expect(done.uploadIsStale == false)
          #expect(destination.state.withLock { $0.uploads.count } == 1)
          #expect(world.clipboard.copies == [.url(publicURL(k))])
          #expect(world.notifier.calls.contains(.uploaded(url: publicURL(k), copied: true)))
          #expect(!world.notifier.calls.contains { if case .notice(let t, _, _) = $0 { return t == "New link" } else { return false } })
          try await settledEdit(coordinator, id)
      }

      /// phase-4a:129 (:189). Upload on a capture uploaded before phase 3 (a link with no object location) makes a new
      /// link under a new key with the `New link` notice that the earlier upload stays in the bucket, keeps no prior
      /// upload and nothing to supersede, deletes nothing and copies the new URL. `curl -I` on the old link is the empty
      /// DELETE list.
      @Test func uploadOfAPrePhase3CaptureMakesANewLinkAndDeletesNothing() async throws {
          defer { world.removeAll() }
          let folder = try world.storeSaveFolder()
          let coordinator = world.makeCoordinator()
          let (record, _) = try addSavedImage(to: coordinator, in: folder, uploadState: .uploaded(url: link, key: key))
          let id = record.id
          coordinator.openEditor(recordID: id)
          let editor = try await openedEditor(id)
          editor.draw()
          _ = await editor.upload()
          try await eventually { coordinator.history.record(id: id)?.uploadedKey.map { $0 != key } == true }
          #expect(world.notifier.calls.contains(.notice(title: "New link", body: "The earlier upload stays in the bucket.")))
          let k = try #require(coordinator.history.record(id: id)?.uploadedKey)
          #expect(k != key)
          let done = try #require(coordinator.history.record(id: id))
          #expect(done.uploadState == .uploaded(url: publicURL(k), key: k))
          #expect(done.objectLocation == world.location)
          #expect(done.priorUpload == nil)
          #expect(done.supersededObjects.isEmpty)
          #expect(destination.state.withLock { $0.deletedKeys.isEmpty })
          #expect(world.clipboard.copies.last == .url(publicURL(k)))
          try await settledEdit(coordinator, id)
      }

      /// phase-4a:130 (:190). With the destination changed while the editor is open, Upload goes to the new bucket as a
      /// new link with the `New link` notice that the destination changed, records the new location, and deletes the
      /// old object at the old bucket (signed for it), leaving nothing superseded. The second bucket is a second fake.
      @Test func uploadAfterTheDestinationChangedGoesToTheNewBucketAndDeletesTheOldObject() async throws {
          defer { world.removeAll() }
          let folder = try world.storeSaveFolder()
          let coordinator = world.makeCoordinator()
          let (record, _) = try addSavedImage(to: coordinator, in: folder, uploadState: .uploaded(url: link, key: key),
                                              objectLocation: world.location)
          let id = record.id
          coordinator.openEditor(recordID: id)
          let editor = try await openedEditor(id)
          let second = S3DestinationConfig(endpoint: "https://s3.us-west-2.amazonaws.com", region: "us-west-2",
                                           bucket: "second.tky.io", publicURLTemplate: "https://second.tky.io/{key}")
          let other = FakeDestination()
          world.factory.add(other, at: ObjectLocation(config: second))
          world.settings.s3Config = second
          coordinator.destinationDidChange()
          editor.draw()
          _ = await editor.upload()
          try await eventually { other.state.withLock { $0.uploads.count } == 1 }
          try await eventually { destination.state.withLock { $0.deletedKeys } == [key] }
          try await eventually { coordinator.history.record(id: id)?.supersededObjects.isEmpty == true }
          #expect(world.notifier.calls.contains(.notice(title: "New link", body: "The destination changed, so this uploads as a new link.")))
          let k = try #require(other.state.withLock { $0.uploads.last?.key })
          #expect(k != key)
          let done = try #require(coordinator.history.record(id: id))
          #expect(done.uploadState == .uploaded(url: publicURL(k), key: k))
          #expect(done.objectLocation == ObjectLocation(config: second))
          #expect(done.priorUpload == nil)
          #expect(destination.state.withLock { $0.uploads.isEmpty })
          #expect(other.state.withLock { $0.deletedKeys.isEmpty })
          #expect(world.factory.askedLocations.contains(world.location))
          try await settledEdit(coordinator, id)
      }

      /// phase-4c:179 (:245). A spotlight and a counter (number 1, 64 px at 2x) uploaded from a saved, never-uploaded
      /// capture are flattened into the file and the object, which carry the same bytes; reopened, the capture has no
      /// annotations left to select and its pixels are the export's: white inside the spotlight's hole, dimmed white
      /// outside it, and the counter's fill.
      @Test func anUploadedCaptureReopensFlatWithItsMarksInThePixels() async throws {
          defer { world.removeAll() }
          let folder = try world.storeSaveFolder()
          let coordinator = world.makeCoordinator()
          let png = try EditorPixels.png(width: 200, height: 100, scale: 2, white: true)
          let file = folder.appending(path: "Shot.png")
          try png.write(to: file)
          let record = CaptureRecord(fileURL: file, pixelWidth: 200, pixelHeight: 100, appName: nil, byteCount: png.count)
          let id = record.id
          coordinator.history.add(record)
          coordinator.openEditor(recordID: id)
          let editor = try await openedEditor(id)
          editor.model.commitNewShape(try #require(editor.model.makeAnnotation(.spotlight, from: CGPoint(x: 20, y: 20),
                                                                              to: CGPoint(x: 80, y: 60))))
          let counter = try #require(editor.model.makeAnnotation(.counter, from: CGPoint(x: 150, y: 50), to: CGPoint(x: 150, y: 50)))
          editor.model.commitNewShape(counter)
          #expect(editor.model.document.spotlights.count == 1)
          let mark = try #require(counter.counterMark)
          #expect(mark.number == 1)
          #expect(mark.diameter == 64)
          #expect(mark.center == CGPoint(x: 150, y: 50))
          let outcome = await editor.upload()
          let expected = try #require(await editor.export()).image.image
          try await eventually {
              coordinator.history.record(id: id)?.uploadedKey != nil && coordinator.history.record(id: id)?.isUploading == false
          }
          #expect(outcome == EditorUploadOutcome(wroteLocally: true, enqueued: true))
          #expect(editor.isClosed)
          let uploads = destination.state.withLock { $0.uploads }
          #expect(uploads.count == 1)
          #expect(uploads.first?.data == (try Data(contentsOf: file)))
          #expect(coordinator.history.record(id: id)?.uploadedKey == uploads.first?.key)
          coordinator.openEditor(recordID: id)
          let reopened = try await reopenedEditor(id, after: editor)
          #expect(reopened.model.document.annotations.isEmpty)
          #expect(EditorPixels.rgba(reopened.model.base) == EditorPixels.rgba(expected))
          #expect(EditorPixels.pixel(reopened.model.base, x: 50, y: 40) == [255, 255, 255, 255])
          let dim = EditorPixels.pixel(reopened.model.base, x: 100, y: 90)
          #expect(dim[0...2].allSatisfy { (120...135).contains($0) })
          let fill = EditorPixels.pixel(reopened.model.base, x: 130, y: 50)
          #expect(fill[0] > 230 && fill[1] < 90 && fill[2] < 90)
          try await settledEdit(coordinator, id)
      }
  }
  ```

- [ ] **Step 3: Check the file's shape.** Nine tests, each name once in the test target, and no helper this suite does not have:
  ```bash
  grep -c "@Test" TidyShotTests/CoordinatorEditorUploadTests.swift && for t in uploadWritesTheFileFirstThenReplacesTheLinksObject uploadOfAnUploadOnlyCaptureWritesPendingThenReplacesItsKey annotateTheNewestCardSaveThenUploadWritesTheFileThenUploadsAndCopiesTheURL anUploadAfterTheCapturesOwnClosesAtOnceAndEndsWithTheLinkCopied withNoDestinationSaveTakesTheClipboardAndUploadIsRefused uploadAsNewWithoutALinkIsRefusedAndUploadMakesTheFirstLink uploadOfAPrePhase3CaptureMakesANewLinkAndDeletesNothing uploadAfterTheDestinationChangedGoesToTheNewBucketAndDeletesTheOldObject anUploadedCaptureReopensFlatWithItsMarksInThePixels; do grep -rl "func $t(" TidyShotTests | wc -l | tr -d ' '; done | sort | uniq -c && grep -nE "var green|var background|func expected" TidyShotTests/CoordinatorEditorUploadTests.swift | wc -l | tr -d ' '
  python3 -I -c 'import sys; [print(f, n) for f in sys.argv[1:] for n, l in enumerate(open(f, encoding="utf-8"), 1) if "///" in l and len(l.rstrip("\n")) > 120]' TidyShotTests/CoordinatorEditorUploadTests.swift
  ```
  Expected, three lines: `9`, then `   9 1` (each of the nine names is in exactly one file), then `0`; the width
  check prints nothing (no doc comment line passes 120 characters, D75).

- [ ] **Step 4: Run the suite alone.**
  ```bash
  xcodegen generate && xcodebuild test -project TidyShot.xcodeproj -scheme TidyShot -destination 'platform=macOS' -derivedDataPath .build -only-testing:TidyShotTests/CoordinatorEditorUploadTests 2>&1 | grep -E "Test run with|error:|TEST"
  ```
  Expected: `✔ Test run with 9 tests in 1 suite passed after <n> seconds.` and `** TEST SUCCEEDED **`. Lines with `error:` that are the known noise (`com.apple.linkd.autoShortcut`, `mdb_txn_commit error: MDB_MAP_FULL`, `History file could not be read or decoded, setting it aside`, and the `iOSSimulator: … sharedServiceContextForDeveloperDir:error:` line, Global Constraints) are not failures; any other `error:` line, or a test failing, is. A failure here is the test or the helpers as typed: compare the file with Step 2 before anything else; do not change `TidyShot/`, the fakes or `EditorPixels`.

- [ ] **Step 5: Run the full suite.**
  ```bash
  xcodegen generate && xcodebuild test -project TidyShot.xcodeproj -scheme TidyShot -destination 'platform=macOS' -derivedDataPath .build 2>&1 | grep -E "Test run with|error:|TEST"
  ```
  Expected: `✔ Test run with 2300 tests in 193 suites passed after <n> seconds.` and `** TEST SUCCEEDED **`, with only the known noise lines besides (the run takes 45 s to 130 s). No hand check is run; the report says so.

- [ ] **Step 6: Commit.**
  ```bash
  git add TidyShotTests/CoordinatorEditorUploadTests.swift && git status --short && git commit -m "test: the editor's Upload over a link and the first upload through the editor seam" && git log --oneline -1
  ```
  Expected: `git status --short` prints only `A  TidyShotTests/CoordinatorEditorUploadTests.swift` (`TidyShot.xcodeproj` is generated and not tracked; if `git status` shows any other path, stop and report it), and the last line is the new commit with that message. No attribution lines, no session URL; do not push.

### Task 5: `CoordinatorEditorUploadTests`, failed replaces, the folder change and the drag copy [integration]

**Files:**
- Modify `TidyShotTests/CoordinatorEditorUploadTests.swift`: the five tests appended before the closing `}` of `struct CoordinatorEditorUploadTests`, after Task 4's last test (`anUploadedCaptureReopensFlatWithItsMarksInThePixels`).

**Interfaces:**
- Consumes (Task 1): `FakeEditor` (`draw()`, `save()`, `upload(asNew:)`, `export()`, `isClosed`, `model`, `pushes`, `title`, `representedURL`), `world.editors` (`built`, `editor(for:)`), `world.clipboard.pngs`, `EditorPixels.changedPixels`, `.decoded`, `.isBlue`, `.png`, `.rgba`. (Task 4): every helper of `CoordinatorEditorUploadTests` with the signatures in Task 4's Produces. The relaunch test builds a second coordinator over the same world (`world.makeCoordinator()` then `history.load()`, design 5).
- Produces: nothing later uses this suite.

**Tests:**
1. `aFailedReplaceKeepsTheLinkAndTheEditAndTheRightKeyReplacesIt`: catalogue section 4 (CoordinatorEditorUploadTests.swift), "Failed replaces and the folder change", tests-editor.md:1061; effort M.
2. `aFailedReplaceOfAnUploadOnlyCaptureKeepsPendingAcrossARelaunchUntilTheNextUpload`: catalogue section 4 (CoordinatorEditorUploadTests.swift), "Failed replaces and the folder change", tests-editor.md:1088; effort L.
3. `aFailedReplaceAfterAFolderChangeKeepsTheEditInPendingUntilTheNextUpload`: catalogue section 4 (CoordinatorEditorUploadTests.swift), "Failed replaces and the folder change", tests-editor.md:1151; effort L.
4. `aNewSaveFolderReachesTheOpenEditorAndUploadGoesThroughPending`: catalogue section 4 (CoordinatorEditorUploadTests.swift), "Failed replaces and the folder change", tests-editor.md:1181; effort L.
5. `uploadOfAnUploadOnlyCaptureRemovesItsDragCopyAndEveryReadGivesTheEdit`: catalogue section 4 (CoordinatorEditorUploadTests.swift), "The drag copy", tests-editor.md:1210; effort L.
- 5 tests (M 1, L 4), 0 parameterized.
- Focused run, `-only-testing:TidyShotTests/CoordinatorEditorUploadTests`: `Test run with 14 tests in 1 suite passed` (Task 4's 9 and these 5).
- Full suite: `Test run with 2305 tests in 193 suites passed`.

**Commit:** `test: the editor's failed replaces, the folder change and the drag copy through the editor seam`

**Steps:**

Every helper the five bodies call is one of Task 4's (`key`, `link`, `destination`, `all`, `publicURL`, `openedEditor`, `reopenedEditor`, `settledEdit`, `addSavedImage`, `addPendingImage`, `pendingURL`, `isUploaded`, `title(of:)`, `exists`, `crop`, `addText`, with the signatures in Task 4's Produces), so this task defines no helper and no nested type. The entry points and members they reach, at dd1231d: `AppCoordinator.openEditor(recordID: UUID)` (TidyShot/App/AppCoordinator+Editor.swift:15), `copyLinkOrFile(recordID: UUID)` (AppCoordinator+RecordActions.swift:9), `copyImage(recordID: UUID) async` (:88), `imageData(of record: CaptureRecord, downloadTitle: String = "Copying image…") async throws -> Data` (:215), `destinationDidChange()` (AppCoordinator+Upload.swift:78), `retryUpload(recordID: UUID)` (:462), `retryFailedUploads()` (:496), `prepareDragFile(recordID: UUID)` (AppCoordinator+DragOut.swift:14); `coordinator.pendingFiles` (`PendingFileStore(nextTo:)`, AppCoordinator.swift:21, :280, so two coordinators over one world share its `directory`), `coordinator.dragFiles.folder(for: UUID) -> URL` and `stagedFile(id: UUID) -> URL?` (DragFileStore.swift:24, :39), `history.load()` (HistoryStore.swift:40), `history.failedRecords` (:127); `CaptureRecord.editedAt`, `uploadIsStale`, `priorUpload`, `uploadedKey`, `keepsUnuploadedEdit` (CaptureRecord.swift:81, :84, :93, :191, :260); `EditorUploadPlan.failedReplaceMessage` and `cacheNote` (EditorUploadPlan.swift:31, :36), `EditorUploadOutcome(wroteLocally:enqueued:)` (:217-221), `EditorSaveTarget.outsideFolderReason` and `uploadedCopyStaleNotice` (EditorSaveTarget.swift:18-19), `CropGeometry.readout(for: CGRect) -> String` (CropGeometry.swift:47), `TextLayout.frame(for: TextBox) -> CGRect` (TextLayout.swift:68); the harness's `world.saveLocation.store(_ url: URL) throws` (TidyShot/Output/SaveLocation.swift:23), `world.storeSaveFolder() throws -> URL` (CoordinatorWorld.swift:151), `world.makeCoordinator()` (:131), `world.date` (:92), `world.location` (:90), `world.notifier.calls` and `.errors` with `.error(title:message:subtitle:)` and `.notice(title:body:subtitle:)` (CoordinatorFakes.swift:13-14, :20, :23), `world.cards.showing` and `dragFiles(for:) -> [URL?]` (:88, :130), `world.clipboard.copies` with `.pngAndTIFF` and `.url(URL)` (:159, :162, :167), `FakeDestination.State`'s `failuresRemaining`, `failure`, `uploads` (`key`, `data`, `contentType`, `cacheControl`), `attemptKeys`, `holdingUploadsRemaining`, `heldUploads`, `downloadedData`, `dataDownloadKeys` (FakeDestination.swift:12-13, :15, :19, :26, :28, :104-105) and `releaseUploads(throwing:)` (:256), `eventually(_:)` (UploadQueueTests.swift:42); and Task 1's `FakeEditor.draw()`, `save()`, `upload(asNew: Bool = false) -> EditorUploadOutcome`, `export()`, `isClosed`, `model`, `pushes`, `title`, `representedURL`, `world.editors.built` and `editor(for:)`, `world.clipboard.pngs`, `EditorPixels.isBlue(_:)`, `isBlue(png:)`, `decoded(_:)`, `rgba(_:)`, `changedPixels(_:in:from:)` (Task 1's `Support/EditorFakes.swift`, `Support/EditorPixels.swift` and `Support/CoordinatorFakes.swift`).

- [ ] **Step 1: Find the place.** In `TidyShotTests/CoordinatorEditorUploadTests.swift` as Task 4 leaves it, the file ends with the last lines of `anUploadedCaptureReopensFlatWithItsMarksInThePixels`, the `}` that closes it, and the `}` that closes `struct CoordinatorEditorUploadTests`:
  ```swift
          #expect(fill[0] > 230 && fill[1] < 90 && fill[2] < 90)
          try await settledEdit(coordinator, id)
      }
  }
  ```
  The five tests go between those two braces: after the line `    }` (the last line before the struct's closing brace), a blank line, then the block in Step 2, then the struct's `}` as the file's last line. Check the place is unique before editing:
  ```bash
  grep -c "fill\[0\] > 230 && fill\[1\] < 90 && fill\[2\] < 90" TidyShotTests/CoordinatorEditorUploadTests.swift
  tail -n 1 TidyShotTests/CoordinatorEditorUploadTests.swift
  ```
  Expected: `1`, then `}`.

- [ ] **Step 2: Append the five tests.** Replace the four lines quoted in Step 1 with the same four lines minus the last `}`, a blank line, this block, and `}`. The block, whole (the relaunch test follows design 5's relaunch rule: before the second coordinator it requires no upload running and waits for the edit's thumbnail by its exact name with `settledEdit`; after it, nothing calls `coordinator`, so the pending-file path is read through `relaunched`, and nothing runs `world.clock`):
  ```swift
      /// phase-4a:131 (:191), in part. A replace the bucket refuses with a 403 (what a wrong secret gives) closes the
      /// editor, is tried once (a 403 is not retried), and posts `Not uploaded` with the line's body; the record keeps
      /// its link and location, the file holds the edit, and the row still copies the old URL. Annotate reopens the edit
      /// with the stale-copy status, and the next Upload (the right key) replaces the same key and copies the same URL.
      /// Stays: closing and the subtitle as shown (`EDPLACE`). The link serving is the PUT body. The notice's title is
      /// `Not uploaded` (harness D14).
      @Test func aFailedReplaceKeepsTheLinkAndTheEditAndTheRightKeyReplacesIt() async throws {
          defer { world.removeAll() }
          let folder = try world.storeSaveFolder()
          destination.state.withLock {
              $0.failuresRemaining = 1
              $0.failure = .httpStatus(403, body: "SignatureDoesNotMatch: The request signature we calculated does not match the signature you provided.")
          }
          let coordinator = world.makeCoordinator()
          let (record, _) = try addSavedImage(to: coordinator, in: folder, uploadState: .uploaded(url: link, key: key),
                                              objectLocation: world.location)
          let id = record.id
          coordinator.openEditor(recordID: id)
          let editor = try await openedEditor(id)
          editor.draw()
          #expect(await editor.upload() == EditorUploadOutcome(wroteLocally: true, enqueued: true))
          #expect(editor.isClosed)
          try await eventually {
              world.notifier.calls.contains(.error(title: "Not uploaded", message: "Upload failed. The link still shows the earlier image."))
          }
          #expect(destination.state.withLock { $0.attemptKeys } == [key])
          let failed = try #require(coordinator.history.record(id: id))
          #expect(failed.uploadState == .uploaded(url: link, key: key))
          #expect(failed.objectLocation == world.location)
          #expect(failed.uploadIsStale == true)
          #expect(failed.priorUpload == nil)
          #expect(try EditorPixels.isBlue(png: Data(contentsOf: try #require(record.fileURL))))
          coordinator.copyLinkOrFile(recordID: id)
          #expect(world.clipboard.copies == [.url(link)])
          coordinator.openEditor(recordID: id)
          let reopened = try await reopenedEditor(id, after: editor)
          #expect(world.editors.built.count == 2)
          #expect(EditorPixels.isBlue(reopened.model.base))
          #expect(reopened.pushes.first?.status == EditorSaveTarget.uploadedCopyStaleNotice)
          world.date = world.date.addingTimeInterval(1)
          #expect(await reopened.upload() == EditorUploadOutcome(wroteLocally: true, enqueued: true))
          try await eventually { coordinator.history.record(id: id)?.uploadIsStale == false }
          #expect(coordinator.history.record(id: id)?.uploadState == .uploaded(url: link, key: key))
          #expect(destination.state.withLock { $0.uploads.map(\.key) } == [key])
          #expect(destination.state.withLock { $0.attemptKeys } == [key, key])
          #expect(try EditorPixels.isBlue(png: try #require(destination.state.withLock { $0.uploads.last?.data })))
          #expect(world.clipboard.copies == [.url(link), .url(link)])
          #expect(world.notifier.calls.filter { $0 == .notice(title: "Uploaded, URL copied", body: EditorUploadPlan.cacheNote) }.count == 1)
          try await settledEdit(coordinator, id)
      }

      /// phase-4a:133 (:193), in part; phase-4b:112 (:156), in part; phase-4b:113 (:157), in part; phase-4b:114 (:158).
      /// An upload-only capture's failed replace (a 403, tried once) closes the editor and keeps the edit, with its text
      /// and at the cropped size, in `pending/<UUID>.png`, while the record keeps its link. A relaunch (a second
      /// coordinator over the same `history.json`, design 5) reads that state back; the row copies the old URL, Annotate
      /// reopens the pending file's edit with the stale-copy status, and the next Upload replaces the same key, removes
      /// the pending file and leaves the cropped size on the record.
      /// Stays: phase-4a:133, closing and the subtitle as shown (`EDPLACE`). phase-4b:112, the window closing
      /// (`EDPLACE`); the real quit and relaunch, by hand (a second coordinator stands for it); a 403 is not retried and
      /// the title is `Not uploaded`. phase-4b:113, the subtitle as shown (`EDPLACE`).
      @Test func aFailedReplaceOfAnUploadOnlyCaptureKeepsPendingAcrossARelaunchUntilTheNextUpload() async throws {
          defer { world.removeAll() }
          let original = try EditorPixels.png(width: 200, height: 100, scale: 2, white: true)
          destination.state.withLock {
              $0.downloadedData = original
              $0.failuresRemaining = 10
              $0.failure = .httpStatus(403, body: "SignatureDoesNotMatch")
          }
          let coordinator = world.makeCoordinator()
          let record = CaptureRecord(fileURL: nil, pixelWidth: 200, pixelHeight: 100, appName: nil,
                                     uploadState: .uploaded(url: link, key: key), objectLocation: world.location)
          let id = record.id
          coordinator.history.add(record)

          // 1
          coordinator.destinationDidChange()
          coordinator.openEditor(recordID: id)
          let editor = try await openedEditor(id)
          let box = try addText(editor.model, "Edit", at: CGPoint(x: 80, y: 50))
          crop(editor.model, to: CGRect(x: 40, y: 20, width: 120, height: 60), apply: false)
          #expect(CropGeometry.readout(for: try #require(editor.model.cropDraft)) == "120 × 60")
          let outcome = await editor.upload()
          let expected = try #require(await editor.export()).image.image
          try await eventually {
              world.notifier.calls.contains(.error(title: "Not uploaded", message: EditorUploadPlan.failedReplaceMessage))
          }
          // The edit's thumbnail named (+Editor:217, :249-275): its history save lands before the relaunch reads it.
          try await settledEdit(coordinator, id)

          #expect(outcome == EditorUploadOutcome(wroteLocally: true, enqueued: true))
          #expect(editor.isClosed)
          #expect(coordinator.editors[id] == nil)
          #expect(destination.state.withLock { $0.uploadAttempts } == 1)
          #expect(destination.state.withLock { $0.attemptKeys } == [key])
          #expect(destination.state.withLock { $0.uploads.isEmpty })
          #expect(world.notifier.calls.contains(.error(title: "Not uploaded",
                                                       message: "Upload failed. The link still shows the earlier image.")))
          #expect(!world.notifier.errors.contains { $0.title == "Upload failed" })
          let failed = try #require(coordinator.history.record(id: id))
          #expect(failed.uploadState == .uploaded(url: link, key: key))
          #expect(failed.objectLocation == world.location)
          #expect(failed.priorUpload == nil)
          #expect(failed.uploadIsStale == true)
          #expect(failed.fileIsTemporary == true)
          #expect(failed.fileURL == pendingURL(coordinator, id))
          #expect(failed.keepsUnuploadedEdit == true)
          #expect(failed.pixelWidth == 120)
          #expect(failed.pixelHeight == 60)
          #expect(EditorPixels.rgba(try EditorPixels.decoded(Data(contentsOf: pendingURL(coordinator, id))).image)
              == EditorPixels.rgba(expected))

          // 2: the first coordinator is quiescent (no upload running, the edit's thumbnail named); nothing
          // below calls it or runs world.clock.
          try #require(coordinator.history.record(id: id)?.isUploading == false)
          let relaunched = world.makeCoordinator()
          relaunched.history.load()
          let loaded = try #require(relaunched.history.record(id: id))
          #expect(loaded.uploadState == failed.uploadState)
          #expect(loaded.fileURL == failed.fileURL)
          #expect(loaded.fileIsTemporary == failed.fileIsTemporary)
          #expect(loaded.uploadIsStale == failed.uploadIsStale)

          // 3
          relaunched.copyLinkOrFile(recordID: id)
          relaunched.openEditor(recordID: id)
          let reopened = try await reopenedEditor(id, after: editor)
          #expect(world.clipboard.copies == [.url(link)])
          #expect(world.editors.built.count == 2)
          #expect(reopened.title == title(of: record))
          #expect(reopened.representedURL == nil)
          #expect(reopened.model.base.width == 120)
          #expect(reopened.model.base.height == 60)
          #expect(reopened.model.scale == 2)
          #expect(EditorPixels.rgba(reopened.model.base) == EditorPixels.rgba(expected))
          #expect(reopened.model.document == AnnotationDocument(annotations: []))
          #expect(destination.state.withLock { $0.dataDownloadKeys } == [key])
          let reopenPush = try #require(reopened.pushes.first)
          #expect(reopenPush.status == EditorSaveTarget.uploadedCopyStaleNotice)
          #expect(reopenPush.available == all)
          #expect(reopenPush.saveCommand == .writeOver)

          // 4: a later edit, so its thumbnail gets a new name settledEdit can wait for.
          world.date = world.date.addingTimeInterval(1)
          destination.state.withLock { $0.failuresRemaining = 0 }
          relaunched.destinationDidChange()
          let outcome2 = await reopened.upload()
          try await eventually {
              relaunched.history.record(id: id)?.isUploading == false && relaunched.history.record(id: id)?.fileURL == nil
          }
          #expect(outcome2 == EditorUploadOutcome(wroteLocally: true, enqueued: true))
          #expect(reopened.isClosed)
          let uploads = destination.state.withLock { $0.uploads }
          #expect(uploads.map(\.key) == [key])
          #expect(uploads.first?.cacheControl == "no-cache")
          let decoded = try EditorPixels.decoded(try #require(uploads.first?.data))
          #expect(decoded.image.width == 120)
          #expect(decoded.image.height == 60)
          #expect(decoded.scale == 2)
          #expect(EditorPixels.rgba(decoded.image) == EditorPixels.rgba(expected))
          #expect(EditorPixels.changedPixels(decoded.image, in: TextLayout.frame(for: box).offsetBy(dx: -40, dy: -20),
                                             from: [255, 255, 255]) > 0)
          #expect(!FileManager.default.fileExists(atPath: pendingURL(relaunched, id).path(percentEncoded: false)))
          let done = try #require(relaunched.history.record(id: id))
          #expect(done.uploadState == .uploaded(url: link, key: key))
          #expect(done.fileURL == nil)
          #expect(done.uploadIsStale == false)
          #expect(done.pixelWidth == 120)
          #expect(done.pixelHeight == 60)
          #expect(done.byteCount == uploads.first?.data.count)
          #expect(world.clipboard.copies == [.url(link), .url(link)])
          #expect(world.notifier.calls.contains(.notice(title: "Uploaded, URL copied", body: EditorUploadPlan.cacheNote)))
          try await settledEdit(relaunched, id)
      }

      /// phase-4a:132 (:192), in part. With another save folder chosen, a failed replace (a 403) of a capture saved in
      /// the old folder leaves that file unchanged and keeps the edit in `pending/<UUID>.png`; Retry Failed Uploads does
      /// nothing for it (the record is not failed, it keeps its link), and the next Upload replaces the same key with the
      /// edit and removes the pending file. The edit is a drawn box, not a Redact: no test commits an effect (design 5).
      /// Stays: closing (`EDPLACE`). The line's last step is at odds with the code: Retry Failed Uploads does nothing for
      /// this capture; the next ⌘U recovers it (tests-editor.md section 8, Tim's call).
      @Test func aFailedReplaceAfterAFolderChangeKeepsTheEditInPendingUntilTheNextUpload() async throws {
          defer { world.removeAll() }
          let folderA = try world.storeSaveFolder()
          let folderB = world.root.appending(path: "Other", directoryHint: .isDirectory)
          try FileManager.default.createDirectory(at: folderB, withIntermediateDirectories: true)
          let coordinator = world.makeCoordinator()
          let (record, original) = try addSavedImage(to: coordinator, in: folderA, name: "Old.png",
                                                     uploadState: .uploaded(url: link, key: key),
                                                     objectLocation: world.location)
          let id = record.id
          destination.state.withLock {
              $0.downloadedData = original
              $0.failuresRemaining = 1
              $0.failure = .httpStatus(403, body: "SignatureDoesNotMatch")
          }
          try world.saveLocation.store(folderB)
          coordinator.openEditor(recordID: id)
          let editor = try await openedEditor(id)
          #expect(editor.model.base.width == 4)
          editor.draw()
          _ = await editor.upload()
          try await eventually { world.notifier.errors.contains { $0.title == "Not uploaded" } }
          let old = folderA.appending(path: "Old.png")
          #expect(try Data(contentsOf: old) == original)
          #expect(try EditorPixels.isBlue(png: Data(contentsOf: pendingURL(coordinator, id))))
          let failed = try #require(coordinator.history.record(id: id))
          #expect(failed.fileURL == pendingURL(coordinator, id))
          #expect(failed.fileIsTemporary)
          #expect(failed.uploadIsStale)
          #expect(failed.keepsUnuploadedEdit)
          #expect(failed.uploadState == .uploaded(url: link, key: key))
          #expect(coordinator.history.failedRecords.isEmpty)
          coordinator.retryFailedUploads()
          // Synchronous: a retry would have flipped both at once (startingRetry, startUpload).
          #expect(coordinator.history.record(id: id)?.isUploading == false)
          #expect(coordinator.history.record(id: id)?.uploadState == .uploaded(url: link, key: key))
          #expect(exists(pendingURL(coordinator, id)))
          coordinator.openEditor(recordID: id)
          let reopened = try await reopenedEditor(id, after: editor)
          #expect(EditorPixels.isBlue(reopened.model.base))
          #expect(reopened.pushes.first?.status == EditorSaveTarget.uploadedCopyStaleNotice)
          world.date = world.date.addingTimeInterval(1)
          #expect(await reopened.upload() == EditorUploadOutcome(wroteLocally: true, enqueued: true))
          try await eventually { coordinator.history.record(id: id)?.uploadIsStale == false }
          #expect(coordinator.history.record(id: id)?.uploadState == .uploaded(url: link, key: key))
          let uploads = destination.state.withLock { $0.uploads }
          #expect(uploads.map(\.key) == [key])
          #expect(try EditorPixels.isBlue(png: try #require(uploads.first?.data)))
          #expect(!exists(pendingURL(coordinator, id)))
          #expect(coordinator.history.record(id: id)?.fileURL == nil)
          try world.saveLocation.store(folderA)
          #expect(try Data(contentsOf: old) == original)
          try await settledEdit(coordinator, id)
      }

      /// phase-4a:148 (:215), in part. A new save folder reaches the open editor without any other call: its push gives
      /// `EditorSaveTarget.outsideFolderReason` and ⌘S as Save As…. A Save that reaches the coordinator anyway is refused
      /// with `Not saved` and leaves the file; the fake's `save()` skips the window's validation, so this is the
      /// coordinator's own check (design 3.4). Upload writes the edit to `pending/<UUID>.png` until the PUT lands, never
      /// to the old folder's file. With the first folder chosen again, another capture there is saved over its file.
      /// Stays: ⌘S's panel (`EDSAVEAS`); ⌘W's Save (`CLOSESHEET` and `EDSAVEAS`); the subtitle and closing (`EDPLACE`).
      @Test func aNewSaveFolderReachesTheOpenEditorAndUploadGoesThroughPending() async throws {
          defer { world.removeAll() }
          let folderA = try world.storeSaveFolder()
          let folderB = world.root.appending(path: "Other", directoryHint: .isDirectory)
          try FileManager.default.createDirectory(at: folderB, withIntermediateDirectories: true)
          destination.state.withLock { $0.holdingUploadsRemaining = 1 }
          defer { destination.releaseUploads() }
          let coordinator = world.makeCoordinator()
          let (record, original) = try addSavedImage(to: coordinator, in: folderA)
          let (other, _) = try addSavedImage(to: coordinator, in: folderA, name: "Other.png")
          let id = record.id
          coordinator.openEditor(recordID: id)
          let editor = try await openedEditor(id)
          #expect(editor.pushes.first?.saveCommand == .writeOver)
          #expect(editor.pushes.first?.status == nil)
          try world.saveLocation.store(folderB)
          try await eventually { editor.pushes.last?.saveFolder == folderB }
          let moved = try #require(editor.pushes.last)
          #expect(moved.status == EditorSaveTarget.outsideFolderReason)
          #expect(moved.saveCommand == .saveAs)
          #expect(moved.available.contains(.save))
          editor.draw()
          #expect(!(await editor.save()))
          #expect(world.notifier.errors.last?.title == "Not saved")
          #expect(world.notifier.errors.last?.message == EditorSaveTarget.outsideFolderReason)
          #expect(try Data(contentsOf: folderA.appending(path: "Shot.png")) == original)
          #expect(await editor.upload() == EditorUploadOutcome(wroteLocally: true, enqueued: true))
          #expect(editor.isClosed)
          try await eventually { destination.state.withLock { $0.heldUploads.count } == 1 }
          #expect(try Data(contentsOf: folderA.appending(path: "Shot.png")) == original)
          #expect(try EditorPixels.isBlue(png: Data(contentsOf: pendingURL(coordinator, id))))
          #expect(coordinator.history.record(id: id)?.fileURL == pendingURL(coordinator, id))
          #expect(coordinator.history.record(id: id)?.fileIsTemporary == true)
          destination.releaseUploads()
          try await eventually { isUploaded(coordinator, id) }
          #expect(!exists(pendingURL(coordinator, id)))
          #expect(coordinator.history.record(id: id)?.fileURL == nil)
          let k = try #require(coordinator.history.record(id: id)?.uploadedKey)
          #expect(coordinator.history.record(id: id)?.uploadState == .uploaded(url: publicURL(k), key: k))
          #expect(try Data(contentsOf: folderA.appending(path: "Shot.png")) == original)
          try world.saveLocation.store(folderA)
          let errorsBefore = world.notifier.errors.count
          coordinator.openEditor(recordID: other.id)
          let second = try await openedEditor(other.id)
          #expect(second.pushes.first?.saveCommand == .writeOver)
          #expect(second.pushes.first?.status == nil)
          second.draw()
          #expect(await second.save())
          #expect(try EditorPixels.isBlue(png: Data(contentsOf: folderA.appending(path: "Other.png"))))
          #expect(world.notifier.errors.count == errorsBefore)
          try await settledEdit(coordinator, id)
          try await settledEdit(coordinator, other.id)
      }

      /// phase-6a:199 (:211), in part: the upload-only half (the "Save and copy image" half is
      /// `CoordinatorEditorSaveTests.saveOverTheFileRemovesTheDragCopyAndEveryReadGivesTheEdit`). Upload from the editor
      /// on an upload-only capture with a kept drag copy removes `Drag/<record id>` at once. While the PUT is held,
      /// Save As…'s read, Copy Image and a new drag stage give the edit from the pending file; after it, the kept drag
      /// copy and a second Annotate give the edit, and nothing is downloaded. The edit is a drawn box standing for the
      /// arrow.
      /// Stays: the card's Save As… panel (`SAVEAS`); the drop, by hand. The line's "from the card" after an Annotate
      /// cannot happen as written (tests-editor.md section 8), so the test puts the record back in `FakeCards.showing`.
      @Test func uploadOfAnUploadOnlyCaptureRemovesItsDragCopyAndEveryReadGivesTheEdit() async throws {
          defer { world.removeAll() }
          let coordinator = world.makeCoordinator()
          let record = try addPendingImage(to: coordinator)
          let id = record.id
          world.cards.showing.insert(id)
          coordinator.retryUpload(recordID: id)
          try await eventually { coordinator.history.record(id: id)?.uploadedKey != nil }
          let k = try #require(coordinator.history.record(id: id)?.uploadedKey)
          #expect(coordinator.history.record(id: id)?.fileURL == nil)
          #expect(coordinator.dragFiles.stagedFile(id: id) != nil)
          destination.state.withLock { $0.holdingUploadsRemaining = 1 }
          defer { destination.releaseUploads() }

          coordinator.openEditor(recordID: id)
          let editor = try await openedEditor(id)
          #expect(destination.state.withLock { $0.dataDownloadKeys }.isEmpty)
          editor.draw()
          let outcome = await editor.upload()
          #expect(outcome == EditorUploadOutcome(wroteLocally: true, enqueued: true))
          #expect(editor.isClosed)
          #expect(!exists(coordinator.dragFiles.folder(for: id)))
          #expect(coordinator.dragFiles.stagedFile(id: id) == nil)
          #expect(world.cards.dragFiles(for: id).last == .some(nil))
          let pending = pendingURL(coordinator, id)
          let current = try #require(coordinator.history.record(id: id))
          #expect(current.fileURL == pending)
          #expect(current.fileIsTemporary)
          #expect(try EditorPixels.isBlue(png: Data(contentsOf: pending)))
          #expect(current.uploadIsStale)
          #expect(current.editedAt == world.date)
          #expect(current.isUploading)

          try await eventually { destination.state.withLock { $0.heldUploads.count } == 1 }
          let now = try #require(coordinator.history.record(id: id))
          #expect(try EditorPixels.isBlue(png: try await coordinator.imageData(of: now, downloadTitle: "Saving a copy…")))
          await coordinator.copyImage(recordID: id)
          #expect(try EditorPixels.isBlue(png: try #require(world.clipboard.pngs.last)))
          #expect(world.clipboard.copies.last == .pngAndTIFF)
          world.cards.showing.insert(id)
          coordinator.prepareDragFile(recordID: id)
          try await eventually { world.cards.dragFiles(for: id).last.flatMap { $0 } != nil }
          let staged = try #require(world.cards.dragFiles(for: id).last.flatMap { $0 })
          #expect(try EditorPixels.isBlue(png: Data(contentsOf: staged)))
          #expect(destination.state.withLock { $0.dataDownloadKeys }.isEmpty)

          destination.releaseUploads()
          try await eventually { coordinator.history.record(id: id)?.uploadState == .uploaded(url: publicURL(k), key: k) }
          let uploads = destination.state.withLock { $0.uploads }
          #expect(uploads.map(\.key) == [k, k])
          #expect(uploads.last?.cacheControl == "no-cache")
          #expect(try EditorPixels.isBlue(png: try #require(uploads.last?.data)))
          let done = try #require(coordinator.history.record(id: id))
          #expect(done.fileURL == nil)
          #expect(!done.uploadIsStale)
          #expect(try EditorPixels.isBlue(png: Data(contentsOf: try #require(coordinator.dragFiles.stagedFile(id: id)))))

          coordinator.openEditor(recordID: id)
          try await eventually { world.editors.built.filter { $0.model.recordID == id }.count == 2 }
          let again = try #require(world.editors.editor(for: id))
          #expect(EditorPixels.isBlue(again.model.base))
          #expect(destination.state.withLock { $0.dataDownloadKeys }.isEmpty)
          try await settledEdit(coordinator, id)
      }
  ```
  So the file ends:
  ```swift
          try await settledEdit(coordinator, id)
      }
  }
  ```
  (the last test's last statement, its `}`, and the struct's `}`), and the suite has 14 `@Test` functions:
  ```bash
  grep -c "@Test" TidyShotTests/CoordinatorEditorUploadTests.swift
  python3 -I -c 'import sys; [print(f, n) for f in sys.argv[1:] for n, l in enumerate(open(f, encoding="utf-8"), 1) if "///" in l and len(l.rstrip("\n")) > 120]' TidyShotTests/CoordinatorEditorUploadTests.swift
  ```
  Expected: `14`, and nothing from the width check (D75).

- [ ] **Step 3: Run the suite alone.**
  ```bash
  xcodegen generate && xcodebuild test -project TidyShot.xcodeproj -scheme TidyShot -destination 'platform=macOS' -derivedDataPath .build -only-testing:TidyShotTests/CoordinatorEditorUploadTests 2>&1 | grep -E "Test run with|error:|TEST"
  ```
  Expected: `✔ Test run with 14 tests in 1 suite passed after <n> seconds.` and `** TEST SUCCEEDED **`, with only the known noise besides (`com.apple.linkd.autoShortcut`, `mdb_txn_commit error: MDB_MAP_FULL`, and on this machine the `CoreSimulator is out of date` line `xcodebuild` prints at start). The five new tests alone ran green in a scratch tree at dd1231d with Task 1's files: `✔ Test run with 5 tests in 1 suite passed after 0.660 seconds.` If a test fails, read its `✘` lines (rerun without the `grep`) and report the failure with the test's output; do not change a body's assertions (D11, D68) or `TidyShot/`.

- [ ] **Step 4: Run the full suite.**
  ```bash
  xcodegen generate && xcodebuild test -project TidyShot.xcodeproj -scheme TidyShot -destination 'platform=macOS' -derivedDataPath .build 2>&1 | grep -E "Test run with|error:|TEST"
  ```
  Expected: `✔ Test run with 2305 tests in 193 suites passed after <n> seconds.` and `** TEST SUCCEEDED **`, with only the known noise (two `History file could not be read or decoded, setting it aside`, `com.apple.linkd.autoShortcut`, about 40 `MDB_MAP_FULL` lines). 45 s to 130 s is normal.

- [ ] **Step 5: Commit.**
  ```bash
  git status --short
  git add TidyShotTests/CoordinatorEditorUploadTests.swift
  git commit -m "test: the editor's failed replaces, the folder change and the drag copy through the editor seam"
  git show --stat --format=%s HEAD
  ```
  Expected: `git status --short` lists only ` M TidyShotTests/CoordinatorEditorUploadTests.swift`; the commit's stat is `TidyShotTests/CoordinatorEditorUploadTests.swift | 368 +` and `1 file changed, 368 insertions(+)`. No attribution lines, no session URL, no push. No hand check is run; the report says so.

### Task 6: `CoordinatorEditorTests`, opening and the card [integration]

**Files:**
- Modify `TidyShotTests/CoordinatorEditorTests.swift`: the eight tests appended before the closing `}` of `struct CoordinatorEditorTests`, after Task 1's `quitAsksEachChangedEditorCancelStopsItDontSaveLetsItGo` (D2), each argument type directly before its test.

**Interfaces:**
- Consumes (Task 1): `FakeEditor` (`save()`, `export()`, `model`, `pushes`, `presentCount`, `title`, `representedURL`), `world.editors` (`built`, `editor(for:)`), `world.clipboard.pngs`, `EditorPixels.decoded`, `.dpiWidth`, `.pixel`, `.png`, `.rgba`, `.worldRed()`; every helper of `CoordinatorEditorTests` with the signatures in Task 1's Produces; `coordinator.closedOverlays`, `canRestoreClosedOverlay` (no test calls `restoreClosedOverlay()` before requiring it false, design 5).
- Produces, the argument types `nonisolated enum Composed: CaseIterable, Sendable { case retained, savedFile }` and `nonisolated enum Restored: CaseIterable, Sendable { case savedFile, pendingFile, uploadedUploadOnly, uploadedUploadOnlyStaged }`, each directly before its test. `withTheOverlayOffEveryAfterCaptureModeStillOpensTheEditor(mode:)` takes `AfterCaptureAction.allCases` and needs no type of its own (D3).

**Tests:**
1. `anUploadedUploadOnlyCaptureOpensFromItsObjectAndOfflineOpensNone`: catalogue section 5 (CoordinatorEditorTests.swift), "Opening", tests-editor.md:1287; effort S.
2. `withTheOverlayOffEveryAfterCaptureModeStillOpensTheEditor(mode:)`: catalogue section 5 (CoordinatorEditorTests.swift), "Opening", tests-editor.md:1311; effort M.
3. `anEditorOpensWithTheStoredSpotlightShapeAndCounterSize`: catalogue section 5 (CoordinatorEditorTests.swift), "Opening", tests-editor.md:1340; effort S.
4. `aCaptureFromBefore4cOpensEditsAndSavesAsBefore`: catalogue section 5 (CoordinatorEditorTests.swift), "Opening", tests-editor.md:1369; effort M.
5. `aComposedWindowCaptureOpensFlatWithNoBackground(composed:)`: catalogue section 5 (CoordinatorEditorTests.swift), "Opening", tests-editor.md:1404; effort S.
6. `annotateFromACardOrRecentCapturesLeavesNothingToRestore`: catalogue section 5 (CoordinatorEditorTests.swift), "The card", tests-editor.md:1426; effort M.
7. `aRestoredCardsAnnotateOpensFromTheFileOrTheBucket(restored:)`: catalogue section 5 (CoordinatorEditorTests.swift), "The card", tests-editor.md:1459; effort M.
8. `anUploadedUploadOnlyCardsCopyImageAndAnnotateReadTheDragCopy`: catalogue section 5 (CoordinatorEditorTests.swift), "The card", tests-editor.md:1499; effort M.
- 8 tests (S 3, M 5), 3 parameterized.
- Focused run, `-only-testing:TidyShotTests/CoordinatorEditorTests`: `Test run with 12 tests in 1 suite passed` (the 2 existing, Task 1's 2 and these 8).
- Full suite: `Test run with 2313 tests in 193 suites passed`.

**Commit:** `test: the editor's opening and the card through the editor seam`

**Steps:**

- [ ] **Step 1: Check the starting point.** Task 5 is committed, and Task 1 left `CoordinatorEditorTests` with its helpers and its two tests last. Run:
  ```bash
  git log -1 --format=%s && tail -3 TidyShotTests/CoordinatorEditorTests.swift
  ```
  Expected output, exactly:
  ```
  test: the editor's failed replaces, the folder change and the drag copy through the editor seam
          #expect(!other.calls.contains(.askToSave))
      }
  }
  ```
  The last three lines are the end of Task 1's `quitAsksEachChangedEditorCancelStopsItDontSaveLetsItGo` and the closing `}` of `struct CoordinatorEditorTests`. Then check that every suite member the eight tests use is there once, with Task 1's signatures:
  ```bash
  for m in 'import CoreGraphics' 'let key = "s/SHOT.png"' 'var destination: FakeDestination' 'var link: URL' \
    'var all: Set<EditorAction>' 'var background: BackgroundStyle' 'func publicURL(_ key: String) -> URL' \
    'func openedEditor(_ id: UUID) async throws -> FakeEditor' 'func settledEdit(_ coordinator: AppCoordinator, _ id: UUID) async throws' \
    'func addSavedImage(to coordinator: AppCoordinator, in folder: URL' 'func addPendingImage(to coordinator: AppCoordinator) throws -> CaptureRecord' \
    'func title(of record: CaptureRecord) -> String' 'func exists(_ url: URL) -> Bool'; do
    printf '%s %s\n' "$(grep -cF -- "$m" TidyShotTests/CoordinatorEditorTests.swift)" "$m"; done
  ```
  Expected: 13 lines, each starting with `1`. If any count is not 1, stop and report: Task 1 is not as this task expects. The bodies also use, from Task 1: `EditorPixels.png(width:height:scale:white:)`, `.decoded(_:)`, `.rgba(_:)`, `.dpiWidth(of:)`, `.pixel(_:x:y:)` (the `CGImage` form) and `.worldRed()`; `world.editors.built` and `world.editors.editor(for:)`; `world.clipboard.pngs`; and the `FakeEditor` members `model`, `title`, `representedURL`, `presentCount`, `pushes` (`Push.record`, `.status`, `.available`, `.saveCommand`), `save()` and `export()`.

  The entry points and the harness members the bodies call, at dd1231d (this task changes none of them):
  - `AppCoordinator`: `func openEditor(recordID: UUID)` (TidyShot/App/AppCoordinator+Editor.swift:15); `func openEditorAfterMenuTracking(recordID: UUID)` (+Editor:68); `@ObservationIgnored var openingEditorIDs: Set<UUID> = []` (AppCoordinator.swift:253); `@ObservationIgnored var latestCapture: (id: UUID, image: ScaledImage)?` (:133); `@ObservationIgnored var closedOverlays = ClosedOverlays()` (:143), whose `private(set) var ids: [UUID]` is ClosedOverlays.swift:8; `var canRestoreClosedOverlay: Bool` (+Overlay:79); `let pendingFiles: PendingFileStore` (:21) with `func write(_ data: Data, id: UUID, ext: String) throws -> URL` (PendingFileStore.swift:21); `let dragFiles: DragFileStore` (:25) with `func stagedFile(id: UUID) -> URL?` (DragFileStore.swift:39) and `func folder(for id: UUID) -> URL` (:24); `func finishSave(_ record: CaptureRecord, image: CGImage?, scale: CGFloat, captureDisplayID: CGDirectDisplayID, notConfiguredWarning: String?, showsCard: Bool, upload destination: UploadTarget?, payload: () throws -> UploadPayload, notification: SaveNotification, awaitsThumbnail: Bool = false) async` (+Save:201-204; `SaveNotification.none` :186); `func makeDestination() -> UploadTarget?` (+Upload:39); `func deleteCapture(recordID: UUID) async` (+Delete:15); `func prepareDragFile(recordID: UUID)` (+DragOut:14); `func retryUpload(recordID: UUID)` (+Upload:462); `func copyImage(recordID: UUID) async` (+RecordActions:88); `func imageData(of record: CaptureRecord, downloadTitle: String = "Copying image…") async throws -> Data` (+RecordActions:215); `history.load()`, `history.add(_:)`, `history.record(id:)` (HistoryStore.swift:40, :66, :87).
  - `CaptureRecord.init(id: UUID = UUID(), timestamp: Date = Date(), fileURL: URL?, fileIsTemporary: Bool = false, thumbnailFileName: String? = nil, pixelWidth: Int, pixelHeight: Int, appName: String?, uploadState: UploadState = .none, objectLocation: ObjectLocation? = nil, …, byteCount: Int? = nil, unmutedIntervals: [MuteInterval] = [], multipart: MultipartUploadState? = nil)` (CaptureRecord.swift:114-120); `var uploadedKey: String?` (:191); `var isUploading: Bool` (:267).
  - `CoordinatorWorld`: `historyFileURL`, `suiteName`, `defaults`, `settings` (CoordinatorWorld.swift:27-32), `notifier`, `cards`, `clock` (:38-43), `location` (:90), `makeCoordinator()` (:131), `removeAll()` (:141), `storeSaveFolder()` (:151), `static func image(width: Int, height: Int) throws -> CGImage` (:170), `static func pngData(width: Int, height: Int) throws -> Data` (:180). `AppSettings`: `showOverlay` (AppSettings.swift:101), `editorSpotlightEllipse` (:124), `editorCounterDiameterPoints` (:126), `var editorDefaults: EditorDefaults` (:244), `init(defaults: UserDefaults = .standard)` (:264); `AfterCaptureAction.allCases` and `var uploads: Bool { self != .save }` (:4-23).
  - `FakeCards` (TidyShotTests/Support/CoordinatorFakes.swift:66-153): `calls`, `var showing: Set<UUID>`, `func close(recordID: UUID, reason: QuickAccessCloseReason)` (:111; a showing record's close goes to `onDidClose`, so the coordinator's restore list hears it), `func dragFiles(for id: UUID) -> [URL?]` (:130), `var closes: [QuickAccessCloseReason]` (:146). `FakeNotifier.Call.error(title:message:subtitle:)` and `.notice(title:body:subtitle:)`, the subtitle defaulted to nil (:13-14); `errors` (:23). `FakeDestination.State`: `holdingUploadsRemaining`, `heldUploads` (FakeDestination.swift:26-28), `downloadedData`, `dataDownloadKeys`, `dataDownloadFailures` (:104-107); `func releaseUploads(throwing error: (any Error)? = nil)` (:256). `FakeScrollClock.run(for duration: Duration) async throws` (ScrollSessionFakes.swift:119).
  - `EditorModel` (TidyShot/Editor/Session/EditorModel.swift): `base` (:91), `scale` (:93), `document` (:95), `hasUnsavedChanges` (:101), `tool` (:126), `spotlightEllipse` (:150), `counterDiameterPoints` (:152), `makeAnnotation(_:from:to:) -> Annotation?` (:241), `spotlightShapeApplies` (:612), `activeSpotlightEllipse` (:622), `counterSizeApplies` (:636), `activeCounterDiameterPoints` (:642); `commitNewShape(_:actionName:)` on `CanvasEditing` (TidyShot/Editor/Tools/ToolFactory.swift:25). `Annotation.spotlightShape` (Annotation.swift:116, `isEllipse` :20), `.counterMark` (:121, `diameter` :28); `AnnotationDocument.background` (AnnotationDocument.swift:15). `BackgroundCompositor.compose(_ content: CGImage, style: BackgroundStyle, scale: CGFloat, fillImage: CGImage?) -> CGImage?` (BackgroundCompositor.swift:16-17); `ImageEncoder.pngData(from image: CGImage, scale: CGFloat) throws -> Data` (ImageEncoder.swift:21); `EditorSaveTarget.noFileReason` (EditorSaveTarget.swift:16); `QuickAccessCloseReason.user`, `.deleted`, `.editorOpened` (QuickAccessController.swift:6, :13, :15).

- [ ] **Step 2: Append the eight tests.** In `TidyShotTests/CoordinatorEditorTests.swift`, the file's last three lines are the ones Step 1 printed:
  ```swift
          #expect(!other.calls.contains(.askToSave))
      }
  }
  ```
  Insert the block below between the `    }` that ends `quitAsksEachChangedEditorCancelStopsItDontSaveLetsItGo` and the final `}` that closes `struct CoordinatorEditorTests`. The block starts with a blank line; the two argument types, `Composed` and `Restored`, each sit directly before their test, as `Kept` does. The bodies are the ones in the review's built tree, statement for statement; the doc comments are this plan's.
  ```swift

      /// phase-4a:49 (:59). An uploaded upload-only capture has no local file, so Annotate downloads its object
      /// (`Opening the capture…`, `Downloading s/SHOT.png`) and opens the editor titled `Capture <time>`, with no file
      /// shown, Save as Save As… and the no-file subtitle. With the download failing as it does with Wi-Fi off, no
      /// editor is built and `Could not open the capture` gives the error's own description; the next Annotate
      /// downloads again and opens. The object is 6 by 3, so the size tells the source.
      @Test func anUploadedUploadOnlyCaptureOpensFromItsObjectAndOfflineOpensNone() async throws {
          defer { world.removeAll() }
          let coordinator = world.makeCoordinator()
          let record = CaptureRecord(fileURL: nil, pixelWidth: 6, pixelHeight: 3, appName: nil,
                                     uploadState: .uploaded(url: link, key: key), objectLocation: world.location)
          coordinator.history.add(record)
          let object = try CoordinatorWorld.pngData(width: 6, height: 3)
          destination.state.withLock {
              $0.downloadedData = object
              $0.dataDownloadFailures = [URLError(.notConnectedToInternet)]
          }
          coordinator.openEditor(recordID: record.id)
          try await eventually {
              world.notifier.calls.contains(.error(title: "Could not open the capture",
                                                   message: URLError(.notConnectedToInternet).localizedDescription))
          }
          try await eventually { coordinator.openingEditorIDs.isEmpty }
          #expect(world.editors.built.isEmpty)
          #expect(coordinator.editors.isEmpty)
          coordinator.openEditor(recordID: record.id)
          let editor = try await openedEditor(record.id)
          #expect(editor.presentCount == 1)
          #expect(world.cards.calls.contains(.close(record.id, .editorOpened)))
          #expect(editor.title == title(of: record))
          #expect(editor.representedURL == nil)
          #expect(editor.model.base.width == 6)
          #expect(editor.model.base.height == 3)
          #expect(editor.model.scale == 1)
          #expect(destination.state.withLock { $0.dataDownloadKeys } == [key, key])
          #expect(world.notifier.calls.filter { $0 == .notice(title: "Opening the capture…", body: "Downloading s/SHOT.png") }
              .count == 2)
          let first = try #require(editor.pushes.first)
          #expect(first.saveCommand == .saveAs)
          #expect(first.status == EditorSaveTarget.noFileReason)
          #expect(first.available == all)
      }

      /// phase-4a:52 (:65). With the overlay off, a capture in each after-capture mode shows no card and keeps no
      /// image, and Annotate on its record opens the editor: from the save-folder file for Upload and copy URL and
      /// Save and copy image, from `pending/<id>.png` for Upload only while its upload is still held, with
      /// `Uploading…` and only Copy and Save As… offered while either upload runs. Each capture is a record set up as
      /// its mode's `persist` leaves it (+Save:161-174) and handed to `finishSave`; the capture itself is `TARGET`'s.
      @Test(arguments: AfterCaptureAction.allCases)
      func withTheOverlayOffEveryAfterCaptureModeStillOpensTheEditor(mode: AfterCaptureAction) async throws {
          defer { world.removeAll() }
          world.settings.showOverlay = false
          let folder = try world.storeSaveFolder()
          if mode.uploads { destination.state.withLock { $0.holdingUploadsRemaining = 1 } }
          defer { destination.releaseUploads() }
          let coordinator = world.makeCoordinator()
          let png = try CoordinatorWorld.pngData(width: 4, height: 2)
          let id = UUID()
          let file: URL
          if mode == .uploadOnly {
              file = try coordinator.pendingFiles.write(png, id: id, ext: "png")
          } else {
              file = folder.appending(path: "Shot.png")
              try png.write(to: file)
          }
          let record = CaptureRecord(id: id, fileURL: file, fileIsTemporary: mode == .uploadOnly, pixelWidth: 4,
                                     pixelHeight: 2, appName: nil,
                                     uploadState: mode.uploads ? .uploading(fraction: 0) : .none, byteCount: png.count)
          await coordinator.finishSave(record, image: try CoordinatorWorld.image(width: 4, height: 2), scale: 1,
                                       captureDisplayID: 1, notConfiguredWarning: nil, showsCard: true,
                                       upload: mode.uploads ? coordinator.makeDestination() : nil,
                                       payload: { .data(png) }, notification: .none)
          if mode.uploads { try await eventually { destination.state.withLock { $0.heldUploads.count } == 1 } }
          coordinator.openEditor(recordID: id)
          let editor = try await openedEditor(id)
          #expect(!world.cards.calls.contains(.show(id)))
          #expect(coordinator.latestCapture == nil)
          #expect(editor.model.base.width == 4)
          #expect(editor.model.base.height == 2)
          #expect(editor.title == (mode == .uploadOnly ? title(of: record) : "Shot.png"))
          #expect(editor.representedURL == (mode == .uploadOnly ? nil : file))
          #expect(world.cards.calls.contains(.close(id, .editorOpened)))
          let first = try #require(editor.pushes.first)
          if mode.uploads {
              #expect(first.status == "Uploading…")
              #expect(first.available == [.copy, .saveAs])
          } else {
              #expect(first.status == nil)
              #expect(first.available == all.subtracting([.uploadAsNew]))
          }
          // Nothing outlives the test: the held PUT finished, the capture's thumbnail named.
          destination.releaseUploads()
          try await eventually { coordinator.history.record(id: id)?.isUploading == false }
          try await eventually { coordinator.history.record(id: id)?.thumbnailFileName != nil }
      }

      /// phase-4c:201 (:273), in part. Ellipse and Large as stored land in the world's defaults under
      /// `editorSpotlightEllipse` and `editorCounterDiameterPoints`, a second `AppSettings` over those defaults reads
      /// them back (the relaunch's read), and an editor opened on the retained capture starts with them: Spotlight
      /// draws an ellipse and the Shape row's value is Ellipse, a new counter is 44 pt (88 px at 2x) and the Size
      /// row's value is 44.
      /// Stays: choosing Ellipse and Large in the popover (`EDDEFAULTS`); the rows as drawn, `defaults read` and the
      /// relaunch, by hand.
      @Test func anEditorOpensWithTheStoredSpotlightShapeAndCounterSize() async throws {
          defer { world.removeAll() }
          world.settings.editorSpotlightEllipse = true
          world.settings.editorCounterDiameterPoints = 44
          let coordinator = world.makeCoordinator()
          let record = CaptureRecord(fileURL: nil, pixelWidth: 200, pixelHeight: 100, appName: nil)
          coordinator.history.add(record)
          coordinator.latestCapture = (id: record.id, image: ScaledImage(image: try CoordinatorWorld.image(width: 200, height: 100),
                                                                         scale: 2))
          coordinator.openEditor(recordID: record.id)
          let editor = try #require(world.editors.editor(for: record.id))
          #expect(world.defaults.bool(forKey: "editorSpotlightEllipse") == true)
          #expect(world.defaults.double(forKey: "editorCounterDiameterPoints") == 44)
          let second = AppSettings(defaults: world.defaults)
          #expect(second.editorDefaults.spotlightEllipse == true)
          #expect(second.editorDefaults.counterDiameterPoints == 44)
          #expect(coordinator.openingEditorIDs.isEmpty)
          let model = editor.model
          #expect(model.spotlightEllipse == true)
          #expect(model.counterDiameterPoints == 44)
          model.tool = .spotlight
          #expect(model.spotlightShapeApplies)
          #expect(model.activeSpotlightEllipse == true)
          #expect(model.makeAnnotation(.spotlight, from: CGPoint(x: 10, y: 10), to: CGPoint(x: 60, y: 40))?
              .spotlightShape?.isEllipse == true)
          model.tool = .counter
          #expect(model.counterSizeApplies)
          #expect(model.activeCounterDiameterPoints == 44)
          #expect(model.makeAnnotation(.counter, from: CGPoint(x: 100, y: 50), to: CGPoint(x: 100, y: 50))?
              .counterMark?.diameter == 88)
      }

      /// phase-4c:214 (:296). A record in the shape the build before 4c wrote (no `byteCount`, `unmutedIntervals` or
      /// `multipart`, and no 4c defaults keys) loads, opens at its size and scale with the registered Spotlight and
      /// Counter defaults, takes a rectangle (a 4a tool) and a spotlight (a 4c tool), and saves over its file as
      /// before: the same size at 144 dpi with the export's pixels, the stroke over the dimmed base, no other file in
      /// the folder, and the record's byte count brought up to date.
      @Test func aCaptureFromBefore4cOpensEditsAndSavesAsBefore() async throws {
          defer { world.removeAll() }
          let folder = try world.storeSaveFolder()
          let coordinator = world.makeCoordinator()
          let png = try EditorPixels.png(width: 200, height: 100, scale: 2)
          let file = folder.appending(path: "Old.png")
          try png.write(to: file)
          let id = UUID()
          let formatter = ISO8601DateFormatter()
          formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
          let stamp = formatter.string(from: Date(timeIntervalSinceNow: -3600))
          let json = """
          [{"appName": "Safari", "fileIsTemporary": false, "fileURL": "\(file.absoluteString)", "id": "\(id.uuidString)", \
          "mediaKind": "image", "pixelHeight": 100, "pixelWidth": 200, "supersededObjects": [], "timestamp": "\(stamp)", \
          "uploadIsStale": false, "uploadState": {"none": {}}}]
          """
          try Data(json.utf8).write(to: world.historyFileURL)
          coordinator.history.load()
          let record = try #require(coordinator.history.record(id: id))
          #expect(record.byteCount == nil)
          #expect(record.mediaKind == .image)
          #expect(record.unmutedIntervals == [])
          #expect(record.multipart == nil)
          #expect(world.defaults.persistentDomain(forName: world.suiteName)?["editorSpotlightEllipse"] == nil)
          coordinator.openEditor(recordID: id)
          let editor = try await openedEditor(id)
          let model = editor.model
          #expect(model.base.width == 200)
          #expect(model.base.height == 100)
          #expect(model.scale == 2)
          #expect(model.spotlightEllipse == false)
          #expect(model.counterDiameterPoints == 32)
          model.commitNewShape(try #require(model.makeAnnotation(.rectangle, from: CGPoint(x: 20, y: 20), to: CGPoint(x: 90, y: 70))))
          model.commitNewShape(try #require(model.makeAnnotation(.spotlight, from: CGPoint(x: 110, y: 20), to: CGPoint(x: 180, y: 80))))
          #expect(await editor.save())
          let expected = try #require(await editor.export()).image.image
          let written = try Data(contentsOf: file)
          let decoded = try EditorPixels.decoded(written)
          #expect(decoded.image.width == 200)
          #expect(decoded.image.height == 100)
          #expect(decoded.scale == 2)
          #expect(EditorPixels.rgba(decoded.image) == EditorPixels.rgba(expected))
          #expect(abs(try #require(EditorPixels.dpiWidth(of: written)) - 144) < 0.5)
          // The stroke rgb(255, 59, 48) over the base the spotlight dims: told from the dimmed base by r, and from
          // the undimmed world red [255, 38, 0] by b.
          let stroke = EditorPixels.pixel(decoded.image, x: 20, y: 40)
          #expect(stroke[0] > 200 && stroke[1] < 100 && stroke[2] > 20 && stroke[2] < 100)
          let dimmed = EditorPixels.pixel(decoded.image, x: 100, y: 90)
          #expect((120...135).contains(dimmed[0]))
          #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path(percentEncoded: false)) == ["Old.png"])
          #expect(coordinator.history.record(id: id)?.byteCount == written.count)
          try await settledEdit(coordinator, id)
      }

      nonisolated enum Composed: CaseIterable, Sendable { case retained, savedFile }

      /// phase-7c:187 (:230), in part. A window capture composed with a solid background opens flat, from the
      /// retained image (that same image) or from its file: the background is in the base's pixels, the document is
      /// empty with no background, which is what the popover's switch reads as off, and nothing is unsaved.
      /// Stays: producing the window capture (`TARGET`); the popover's switch as its binding shows it (`BGPOP`) and
      /// drawn in the window (`EDPLACE`).
      @Test(arguments: Composed.allCases)
      func aComposedWindowCaptureOpensFlatWithNoBackground(composed kind: Composed) async throws {
          defer { world.removeAll() }
          let folder = try world.storeSaveFolder()
          let coordinator = world.makeCoordinator()
          let composed = try #require(BackgroundCompositor.compose(CoordinatorWorld.image(width: 4, height: 2), style: background,
                                                                   scale: 1, fillImage: nil))
          let file = folder.appending(path: "Window.png")
          try ImageEncoder.pngData(from: composed, scale: 1).write(to: file)
          let record = CaptureRecord(fileURL: file, pixelWidth: 20, pixelHeight: 18, appName: nil)
          coordinator.history.add(record)
          if kind == .retained { coordinator.latestCapture = (id: record.id, image: ScaledImage(image: composed, scale: 1)) }
          coordinator.openEditor(recordID: record.id)
          let editor: FakeEditor
          if kind == .retained {
              #expect(coordinator.openingEditorIDs.isEmpty)
              editor = try #require(world.editors.editor(for: record.id))
              #expect(editor.model.base === composed)
          } else {
              editor = try await openedEditor(record.id)
          }
          let m = editor.model
          #expect(m.base.width == 20 && m.base.height == 18)
          #expect(EditorPixels.pixel(m.base, x: 0, y: 0) == [0, 255, 0, 255])
          #expect(EditorPixels.pixel(m.base, x: 8, y: 8) == (try EditorPixels.worldRed()))
          #expect(m.document == AnnotationDocument())
          #expect(m.document.background == nil)
          #expect(!m.hasUnsavedChanges)
      }

      /// phase-6a:131 (:133), in part; phase-6a:152 (:155); phase-6a:158 (:161), with
      /// `CoordinatorOverlayTests.aCardWhoseDeleteIsUnderWayIsNotRestorable`; coordinator-split:44 (:44), in part.
      /// Deleting the middle card's capture and Annotating another from its card (`openEditorAfterMenuTracking`, which
      /// the pin menu's Annotate also calls) closes each, `.deleted` and `.editorOpened`, and neither is restorable,
      /// so `Restore Closed Overlay` is disabled. A card the user closed is restorable until the editor opens on its
      /// capture from Recent Captures (`openEditor`); then it is not.
      /// Stays: phase-6a:131, the gap in the stack closing (`QASTACK`). coordinator-split:44, the pin, the second
      /// click and `Close Pinned Screenshots` (`PINS`, `SCREENS`), and the pin's Save As… panel (`SAVEAS`); its Copy
      /// Image is already `CoordinatorRecordActionsTests.copyImageReadsTheFileOrDownloadsTheObject`.
      @Test func annotateFromACardOrRecentCapturesLeavesNothingToRestore() async throws {
          defer { world.removeAll() }
          let coordinator = world.makeCoordinator()
          let a = try addPendingImage(to: coordinator)
          let b = try addPendingImage(to: coordinator)
          let c = try addPendingImage(to: coordinator)
          world.cards.showing = [a.id, b.id, c.id]
          await coordinator.deleteCapture(recordID: b.id)
          coordinator.openEditorAfterMenuTracking(recordID: c.id)
          _ = try await openedEditor(c.id)
          #expect(world.cards.closes == [.deleted, .editorOpened])
          #expect(world.cards.calls.contains(.close(b.id, .deleted)))
          #expect(world.cards.calls.contains(.close(c.id, .editorOpened)))
          #expect(world.cards.showing == [a.id])
          #expect(coordinator.closedOverlays.ids.isEmpty)
          #expect(!coordinator.canRestoreClosedOverlay)
          #expect(world.editors.editor(for: c.id)?.presentCount == 1)
          let d = try addPendingImage(to: coordinator)
          world.cards.showing.insert(d.id)
          world.cards.close(recordID: d.id, reason: .user)
          #expect(coordinator.closedOverlays.ids == [d.id])
          #expect(coordinator.canRestoreClosedOverlay)
          coordinator.openEditor(recordID: d.id)
          _ = try await openedEditor(d.id)
          #expect(coordinator.closedOverlays.ids.isEmpty)
          #expect(!coordinator.canRestoreClosedOverlay)
      }

      nonisolated enum Restored: CaseIterable, Sendable { case savedFile, pendingFile, uploadedUploadOnly, uploadedUploadOnlyStaged }

      /// phase-6a:164 (:172), in part. A showing card with no retained image stands for a restored one. Its Annotate
      /// (`openEditorAfterMenuTracking`) opens the editor from the save-folder file, from `pending/<id>.png`, or for
      /// an uploaded upload-only capture from the bucket (`Downloading s/SHOT.png`); once the restore's quiet download
      /// into the drag folder has landed (`prepareDragFile`, +Overlay:101), from that copy, with no second GET and no
      /// `Downloading` notice. The card closes as `.editorOpened` and is not on the restore list.
      /// Stays: the restore itself, which reads the screens (`SCREENS`). The quiet download's naming is
      /// `CoordinatorDragOutTests.aRestoredUploadOnlyCardsQuietDownloadIsNamedForItsKey`.
      @Test(arguments: Restored.allCases)
      func aRestoredCardsAnnotateOpensFromTheFileOrTheBucket(restored kind: Restored) async throws {
          defer { world.removeAll() }
          let folder = try world.storeSaveFolder()
          let coordinator = world.makeCoordinator()
          let record: CaptureRecord
          switch kind {
          case .savedFile: record = try addSavedImage(to: coordinator, in: folder).record
          case .pendingFile: record = try addPendingImage(to: coordinator)
          case .uploadedUploadOnly, .uploadedUploadOnlyStaged:
              let object = try CoordinatorWorld.pngData(width: 6, height: 3)
              destination.state.withLock { $0.downloadedData = object }
              record = CaptureRecord(fileURL: nil, pixelWidth: 6, pixelHeight: 3, appName: nil,
                                     uploadState: .uploaded(url: link, key: key), objectLocation: world.location)
              coordinator.history.add(record)
          }
          let id = record.id
          world.cards.showing.insert(id)
          if kind == .uploadedUploadOnlyStaged {
              // The restore's last step (+Overlay:101): the quiet download into the drag folder, landed.
              coordinator.prepareDragFile(recordID: id)
              try await eventually { world.cards.dragFiles(for: id).last.flatMap { $0 } != nil }
          }
          coordinator.openEditorAfterMenuTracking(recordID: id)
          let editor = try await openedEditor(id)
          try await eventually { coordinator.openingEditorIDs.isEmpty }
          switch kind {
          case .savedFile:
              #expect(editor.title == "Shot.png")
              #expect(editor.representedURL == record.fileURL)
              #expect(editor.model.base.width == 4)
              #expect(destination.state.withLock { $0.dataDownloadKeys }.isEmpty)
          case .pendingFile:
              #expect(editor.title == title(of: record))
              #expect(editor.representedURL == nil)
              #expect(editor.model.base.width == 4)
              #expect(destination.state.withLock { $0.dataDownloadKeys }.isEmpty)
          case .uploadedUploadOnly:
              #expect(editor.title == title(of: record))
              #expect(editor.representedURL == nil)
              #expect(editor.model.base.width == 6)
              #expect(destination.state.withLock { $0.dataDownloadKeys } == ["s/SHOT.png"])
              #expect(world.notifier.calls.contains(.notice(title: "Opening the capture…", body: "Downloading s/SHOT.png")))
          case .uploadedUploadOnlyStaged:
              #expect(editor.title == title(of: record))
              #expect(editor.representedURL == nil)
              #expect(editor.model.base.width == 6)
              #expect(destination.state.withLock { $0.dataDownloadKeys } == ["s/SHOT.png"])
              #expect(!world.notifier.calls.contains { if case .notice(_, let body, _) = $0 { return body.hasPrefix("Downloading ") } else { return false } })
          }
          #expect(EditorPixels.pixel(editor.model.base, x: 0, y: 0) == (try EditorPixels.worldRed()))
          #expect(editor.model.scale == 1)
          #expect(editor.presentCount == 1)
          #expect(editor.pushes.first?.record == coordinator.history.record(id: id))
          #expect(world.cards.calls.contains(.close(id, .editorOpened)))
          #expect(!coordinator.closedOverlays.ids.contains(id))
          #expect(world.notifier.errors.isEmpty)
      }

      /// phase-6a:198 (:210), in part. After an upload-only capture's upload, with its card showing, Copy Image, the
      /// read Save As… makes after its panel (`imageData(of:downloadTitle:)`) and Annotate all read the drag copy: the
      /// pending bytes, no GET and no `Downloading` notice. Annotate closes the card, and 60 seconds later on the
      /// world's clock the record's drag folder is gone.
      /// Stays: the card's Save As… panel (`SAVEAS`); Slack reading the file in that minute, by hand. The drag folder
      /// taking the pending file's place and no `fileURL` are already
      /// `CoordinatorUploadTests.anUploadedUploadOnlyImageMovesToItsDragFolderOnlyWithACard`.
      @Test func anUploadedUploadOnlyCardsCopyImageAndAnnotateReadTheDragCopy() async throws {
          defer { world.removeAll() }
          let coordinator = world.makeCoordinator()
          let record = try addPendingImage(to: coordinator)
          let id = record.id
          let png = try Data(contentsOf: try #require(record.fileURL))
          world.cards.showing.insert(id)
          coordinator.retryUpload(recordID: id)
          try await eventually { coordinator.history.record(id: id)?.uploadedKey != nil }
          let k = try #require(coordinator.history.record(id: id)?.uploadedKey)
          let current = try #require(coordinator.history.record(id: id))
          #expect(current.fileURL == nil)
          #expect(try Data(contentsOf: try #require(coordinator.dragFiles.stagedFile(id: id))) == png)
          #expect(world.clipboard.copies == [.url(publicURL(k))])
          await coordinator.copyImage(recordID: id)
          #expect(world.clipboard.copies == [.url(publicURL(k)), .pngAndTIFF])
          #expect(world.clipboard.pngs == [png])
          #expect(world.notifier.calls.contains(.notice(title: "Image copied", body: k)))
          #expect(try await coordinator.imageData(of: current, downloadTitle: "Saving a copy…") == png)
          coordinator.openEditorAfterMenuTracking(recordID: id)
          let editor = try await openedEditor(id)
          #expect(EditorPixels.pixel(editor.model.base, x: 0, y: 0) == (try EditorPixels.worldRed()))
          #expect(editor.model.base.width == 4)
          #expect(world.cards.calls.contains(.close(id, .editorOpened)))
          #expect(destination.state.withLock { $0.dataDownloadKeys }.isEmpty)
          #expect(!world.notifier.calls.contains { if case .notice(_, let body, _) = $0 { return body.hasPrefix("Downloading ") } else { return false } })
          try await world.clock.run(for: .seconds(60))
          try await eventually { !exists(coordinator.dragFiles.folder(for: id)) }
      }
  ```
  After the edit the file ends:
  ```swift
          try await world.clock.run(for: .seconds(60))
          try await eventually { !exists(coordinator.dragFiles.folder(for: id)) }
      }
  }
  ```

- [ ] **Step 3: Check the count and the barred calls.**
  ```bash
  grep -nE 'AppSettings\.shared|NSPasteboard|NSScreen|restoreClosedOverlay\(|\.serialized' TidyShotTests/CoordinatorEditorTests.swift; grep -c '@Test' TidyShotTests/CoordinatorEditorTests.swift
  ```
  Expected output, exactly `12`, with no grep match before it: the 2 existing tests, Task 1's 2 and these 8 (3 of them parameterized: `withTheOverlayOff…(mode:)`, `aComposedWindowCapture…(composed:)`, `aRestoredCardsAnnotate…(restored:)`).

- [ ] **Step 4: Run the suite alone.**
  ```bash
  xcodegen generate && xcodebuild test -project TidyShot.xcodeproj -scheme TidyShot -destination 'platform=macOS' -derivedDataPath .build -only-testing:TidyShotTests/CoordinatorEditorTests 2>&1 | grep -E "Test run with|error:|TEST"
  ```
  Expected: `✔ Test run with 12 tests in 1 suite passed after <n> seconds.` then `** TEST SUCCEEDED **`. Not failures: the `com.apple.linkd.autoShortcut` lines, a few `mdb_txn_commit error: MDB_MAP_FULL` lines, and one `xcodebuild` line ending `CoreSimulator is out of date. … Simulator device support disabled.`, which the `error:` pattern catches through `sharedServiceContextForDeveloperDir:error:` and which every run on this Mac prints. Any other `error:` line, or a `✘`, is a failure: stop and report it.

- [ ] **Step 5: Run the full suite.**
  ```bash
  xcodegen generate && xcodebuild test -project TidyShot.xcodeproj -scheme TidyShot -destination 'platform=macOS' -derivedDataPath .build 2>&1 | grep -E "Test run with|error:|TEST"
  ```
  Expected: `✔ Test run with 2313 tests in 193 suites passed after <n> seconds.` then `** TEST SUCCEEDED **`: Task 5's 2305 and these 8, and no new suite. The noise is the Global Constraints' list and the `CoreSimulator is out of date` line. The run takes 45 s to 130 s; a slow run is not a failure.

- [ ] **Step 6: Commit.**
  ```bash
  git add TidyShotTests/CoordinatorEditorTests.swift && git commit -m "test: the editor's opening and the card through the editor seam" && git show --stat --format=%s HEAD | tail -2
  ```
  Expected: the file line `TidyShotTests/CoordinatorEditorTests.swift | 372 +++…` (the bar's width depends on the terminal) and then ` 1 file changed, 372 insertions(+)`. No attribution lines, no session URL, no push. The task's report says no hand check was run.

### Task 7: `CoordinatorEditorTests`, what the editor hears; `CoordinatorOverlayTests` [integration]

**Files:**
- Modify `TidyShotTests/CoordinatorEditorTests.swift`: the four tests appended before the closing `}` of `struct CoordinatorEditorTests`, after Task 6's last test (`anUploadedUploadOnlyCardsCopyImageAndAnnotateReadTheDragCopy`).
- Modify `TidyShotTests/CoordinatorOverlayTests.swift`: `var destination: FakeDestination { world.factory.standard }` after `init() throws { … }` (:10-12) (catalogue 2.2, 6), and the test before the closing `}` of `struct CoordinatorOverlayTests` (:31).

**Interfaces:**
- Consumes (Task 1): `FakeEditor` (`draw()`, `save()`, `saveAs(to:)`, `copy()`, `upload(asNew:)`, `isClosed`, `model`, `pushes` (with `Push`'s `status`, `available`, `saveCommand`, `isDeleting`, `record`)), `world.editors.editor(for:)`, `world.clipboard.pngs`, `EditorPixels.isBlue(png:)`; every helper of `CoordinatorEditorTests` with the signatures in Task 1's Produces; `FakeConfirm` held (`world.confirm`), `TaskWatch`, `FakeDestination`'s held uploads (the four `CoordinatorEditorTests` bodies) and held aborts (`holdingAbortsRemaining`, `aborts`, `releaseAborts()`; the `CoordinatorOverlayTests` test only) (D67).
- Produces, in `CoordinatorOverlayTests`: `var destination: FakeDestination { world.factory.standard }`. Nothing later uses either suite.

**Tests:**
1. `anEditorOpenedDuringAHeldUploadHearsUploadingAndGetsSaveAndUploadBack`: catalogue section 5 (CoordinatorEditorTests.swift), "What the editor hears while things happen", tests-editor.md:1532; effort M.
2. `aDeleteAskedThenCancelledThenConfirmedReachesTheOpenEditor`: catalogue section 5 (CoordinatorEditorTests.swift), "What the editor hears while things happen", tests-editor.md:1569; effort M.
3. `anEditorOpenedWhileADeleteAsksHearsItAndRefusesSave`: catalogue section 5 (CoordinatorEditorTests.swift), "What the editor hears while things happen", tests-editor.md:1603; effort S.
4. `aPrunedCaptureTellsItsOpenEditorItWasDeleted`: catalogue section 5 (CoordinatorEditorTests.swift), "What the editor hears while things happen", tests-editor.md:1626; effort M.
5. `aCardWhoseDeleteIsUnderWayIsNotRestorable`: catalogue section 6 (CoordinatorOverlayTests.swift), (no subsection), tests-editor.md:1665; effort M.
- 5 tests (S 1, M 4), 0 parameterized.
- Focused run, `-only-testing:TidyShotTests/CoordinatorEditorTests`: `Test run with 16 tests in 1 suite passed` (the 2 existing, Task 1's 2, Task 6's 8 and these 4).
- Focused run, `-only-testing:TidyShotTests/CoordinatorOverlayTests`: `Test run with 2 tests in 1 suite passed` (the 1 existing test and this one).
- Full suite: `Test run with 2318 tests in 193 suites passed`.

**Commit:** `test: what an open editor hears while things happen, and a card whose delete is under way`

**Steps:**

- [ ] **Find the two places.** Task 6 leaves `TidyShotTests/CoordinatorEditorTests.swift` ending with its last test, `anUploadedUploadOnlyCardsCopyImageAndAnnotateReadTheDragCopy`, whose last two statements (as in the review's built tree) are followed by that test's closing brace and the closing `}` of `struct CoordinatorEditorTests`. `TidyShotTests/CoordinatorOverlayTests.swift` is as it is at dd1231d (31 lines; its `init() throws { … }` at :10-12, its one test at :14-30, the struct's closing `}` at :31). Check both:
  ```bash
  tail -4 TidyShotTests/CoordinatorEditorTests.swift; sed -n 8,13p TidyShotTests/CoordinatorOverlayTests.swift; tail -3 TidyShotTests/CoordinatorOverlayTests.swift
  ```
  Expected output:
  ```
          try await world.clock.run(for: .seconds(60))
          try await eventually { !exists(coordinator.dragFiles.folder(for: id)) }
      }
  }
      let world: CoordinatorWorld

      init() throws {
          world = try CoordinatorWorld()
      }

          #expect(relaunched.history.records.map(\.id) == [record.id])
      }
  }
  ```
  If either differs, stop and report: the anchors below are these lines.

- [ ] **Append the four tests to `CoordinatorEditorTests`.** They use the suite's own members and helpers as Task 1 adds them (`destination`, `all`, `openedEditor(_:)`, `addSavedImage(to:in:name:uploadState:objectLocation:uploadIsStale:timestamp:scale:)`, `addPendingImage(to:)`, `desktop(_:)`, `isUploaded(_:_:)`, `exists(_:)`, `key`, `link`), `FakeEditor` (`draw()`, `save()`, `saveAs(to:)`, `copy()`, `upload(asNew:)`, `pushes`, `isClosed`, `model`), `EditorPixels.isBlue(png:)`, and at dd1231d: `AppCoordinator.startUpload(recordID:payload:destination:fixedKey:)` (+Upload:138), `makeDestination() -> UploadTarget?` (+Upload:39), `openEditor(recordID:)` (+Editor:15), `openingEditorIDs` (Coord:253), `latestCapture: (id: UUID, image: ScaledImage)?` (Coord:133), `deleteCapture(recordID:) async` (+Delete:15), `history.add(_:)` (HistoryStore.swift:66), `history.record(id:)` (:87), `CaptureRecord.uploadedURL` (CaptureRecord.swift:185), `EditorAvailability.uploadingStatus`, `.deletingStatus`, `.deletedStatus`, `.deletingRefusal` (EditorSaveTarget.swift:110-115), `EditorSaveTarget.uploadedCopyStaleNotice` (:19), `EditorUploadOutcome.refused` (EditorUploadPlan.swift:224), `FakeConfirm` (`holds`, `isWaiting`, `answer(_:)`, `asked`; CoordinatorFakes.swift:199-219), `TaskWatch(_:)` and `hasReturned` (:420-429), `FakeNotifier.errors` and `calls` (:20-28), `FakeDestination.State`'s `holdingUploadsRemaining`, `heldUploads`, `attemptKeys` and `deletedKeys` (FakeDestination.swift:19-28, :109) and `FakeDestination.releaseUploads(throwing:)` (:256), `world.settings.historyRetentionDays` (AppSettings.swift:111). In `TidyShotTests/CoordinatorEditorTests.swift`, replace
  ```swift
          try await world.clock.run(for: .seconds(60))
          try await eventually { !exists(coordinator.dragFiles.folder(for: id)) }
      }
  }
  ```
  (the end of `anUploadedUploadOnlyCardsCopyImageAndAnnotateReadTheDragCopy` and of the struct) with
  ```swift
          try await world.clock.run(for: .seconds(60))
          try await eventually { !exists(coordinator.dragFiles.folder(for: id)) }
      }

      /// phase-4a:37 (:39), in part; phase-4a:145 (:212), in part. Annotate on the retained capture while its upload
      /// is held opens the editor at once, and its first push says `Uploading…` with only Copy and Save As… on. A
      /// Save, an Upload and an Upload as New sent then are refused at write time with `Not saved` or `Not uploaded`
      /// and `This capture is still uploading.`, and the file and the lane are left as they were; Save As… writes the
      /// edit and Copy puts it on the clipboard. When the upload lands, the last push clears the subtitle and turns
      /// every action on, and the link is copied. `save()` and `upload(asNew:)` call the editor's actions past the
      /// window's validation, to reach the coordinator's own check behind it (+Editor:158-163, :382-388; design 3.4).
      /// Stays: phase-4a:37, the subtitle as shown and the greyed toolbar (`EDPLACE`); the slow profile is the fake's
      /// hold. phase-4a:145, the subtitle as shown, greying and ⌘C/⇧⌘C routing (`EDPLACE`); ⌘S, ⌘U and ⌥⌘U refused
      /// by the window's validation (`EDPLACE`) and their beeps (`BEEP`); ⇧⌘S's panel (`EDSAVEAS`). The test pins
      /// the coordinator's write-time refusal behind that gate; the line's "do nothing" is the gate's.
      @Test func anEditorOpenedDuringAHeldUploadHearsUploadingAndGetsSaveAndUploadBack() async throws {
          defer { world.removeAll() }
          let folder = try world.storeSaveFolder()
          destination.state.withLock { $0.holdingUploadsRemaining = 1 }
          defer { destination.releaseUploads() }
          let coordinator = world.makeCoordinator()
          let original = try CoordinatorWorld.pngData(width: 4, height: 2)
          let file = folder.appending(path: "Shot.png")
          try original.write(to: file)
          let record = CaptureRecord(fileURL: file, pixelWidth: 4, pixelHeight: 2, appName: nil,
                                     uploadState: .uploading(fraction: 0), byteCount: original.count)
          let id = record.id
          coordinator.history.add(record)
          coordinator.latestCapture = (id: id, image: ScaledImage(image: try CoordinatorWorld.image(width: 4, height: 2),
                                                                  scale: 1))
          coordinator.startUpload(recordID: id, payload: .data(original),
                                  destination: try #require(coordinator.makeDestination()))
          try await eventually { destination.state.withLock { $0.heldUploads.count } == 1 }

          coordinator.openEditor(recordID: id)
          let editor = try #require(world.editors.editor(for: id))
          #expect(coordinator.openingEditorIDs.isEmpty)
          let first = try #require(editor.pushes.first)
          #expect(first.status == EditorAvailability.uploadingStatus)
          #expect(first.available == [.copy, .saveAs])
          #expect(first.saveCommand == .writeOver)
          #expect(first.isDeleting == false)
          editor.draw()

          #expect(!(await editor.save()))
          #expect(world.notifier.errors.last?.title == "Not saved")
          #expect(world.notifier.errors.last?.message == "This capture is still uploading.")
          #expect(await editor.upload() == .refused)
          #expect(world.notifier.errors.last?.title == "Not uploaded")
          #expect(world.notifier.errors.last?.message == "This capture is still uploading.")
          #expect(await editor.upload(asNew: true) == .refused)
          #expect(world.notifier.errors.last?.title == "Not uploaded")
          #expect(world.notifier.errors.last?.message == "This capture is still uploading.")
          #expect(try Data(contentsOf: file) == original)
          #expect(!editor.isClosed)
          #expect(destination.state.withLock { $0.attemptKeys.count } == 1)

          let copyURL = try desktop("Copy.png")
          #expect(await editor.saveAs(to: copyURL))
          #expect(try EditorPixels.isBlue(png: Data(contentsOf: copyURL)))
          #expect(world.notifier.calls.contains(.saved(title: "Saved", file: "Copy.png")))

          await editor.copy()
          #expect(world.clipboard.copies == [.pngAndTIFF])
          #expect(try EditorPixels.isBlue(png: world.clipboard.pngs[0]))
          #expect(world.notifier.calls.contains(.notice(title: "Image copied", body: "Shot.png")))

          destination.releaseUploads()
          try await eventually { isUploaded(coordinator, id) }
          let last = try #require(editor.pushes.last)
          #expect(last.status == nil)
          #expect(last.available == all)
          #expect(last.saveCommand == .writeOver)
          let uploadedURL = try #require(coordinator.history.record(id: id)?.uploadedURL)
          #expect(world.clipboard.copies == [.pngAndTIFF, .url(uploadedURL)])
      }

      /// phase-4a:146 (:213), in part; phase-4a:147 (:214), in part. With an editor open on a saved capture whose
      /// link is stale, a Delete whose alert is held pushes `Deleting…` with only Copy and Save As… on, and a Save
      /// sent then is refused at write time with `This capture is being deleted.`, the file and the edit kept.
      /// Cancel pushes the stale-link subtitle and every action back and deletes nothing. A second Delete, confirmed,
      /// removes the record and its object and pushes the deleted subtitle with only Copy and Save As… on, Save going
      /// to Save As…; the editor stays open and registered, Copy copies, and Save As… writes the edit. `save()` calls
      /// the editor's action past the window's validation, to reach the coordinator's check behind it
      /// (+Editor:158-163; design 3.4).
      /// Stays: phase-4a:146, greying and the subtitle as shown (`EDPLACE`); ⌘S refused by the window's validation
      /// (`EDPLACE`) and its beep (`BEEP`); the test pins the coordinator's write-time refusal behind that gate.
      /// phase-4a:147, the subtitle as shown and greying (`EDPLACE`); ⌘C reaching `copyImage` (`EDPLACE`); ⇧⌘S's
      /// panel (`EDSAVEAS`).
      @Test func aDeleteAskedThenCancelledThenConfirmedReachesTheOpenEditor() async throws {
          defer { world.removeAll() }
          let folder = try world.storeSaveFolder()
          world.confirm.holds = true
          let coordinator = world.makeCoordinator()
          let (record, original) = try addSavedImage(to: coordinator, in: folder, uploadState: .uploaded(url: link, key: key),
                                                     objectLocation: world.location, uploadIsStale: true)
          let id = record.id
          let file = try #require(record.fileURL)
          coordinator.openEditor(recordID: id)
          let editor = try await openedEditor(id)
          #expect(editor.pushes.first?.status == EditorSaveTarget.uploadedCopyStaleNotice)
          #expect(editor.pushes.first?.available == all)
          editor.draw()
          let first = Task { await coordinator.deleteCapture(recordID: id) }
          defer { first.cancel() }
          let watch = TaskWatch(first)
          try await eventually { world.confirm.isWaiting }
          let asking = try #require(editor.pushes.last)
          #expect(asking.isDeleting == true)
          #expect(asking.status == "Deleting…")
          #expect(asking.available == [.copy, .saveAs])
          #expect(!(await editor.save()))
          #expect(world.notifier.errors.last?.title == "Not saved")
          #expect(world.notifier.errors.last?.message == "This capture is being deleted.")
          #expect(try Data(contentsOf: file) == original)
          #expect(editor.model.hasUnsavedChanges)
          world.confirm.answer(false)
          try await eventually { watch.hasReturned }
          await first.value
          let cancelled = try #require(editor.pushes.last)
          #expect(cancelled.isDeleting == false)
          #expect(cancelled.status == EditorSaveTarget.uploadedCopyStaleNotice)
          #expect(cancelled.available == all)
          #expect(coordinator.history.record(id: id) != nil)
          #expect(world.confirm.asked.count == 1)
          #expect(destination.state.withLock { $0.deletedKeys }.isEmpty)
          await coordinator.deleteCapture(recordID: id)
          #expect(coordinator.history.record(id: id) == nil)
          #expect(destination.state.withLock { $0.deletedKeys } == [key])
          let gone = try #require(editor.pushes.last)
          #expect(gone.record == nil)
          #expect(gone.status == EditorAvailability.deletedStatus)
          #expect(gone.available == [.copy, .saveAs])
          #expect(gone.saveCommand == .saveAs)
          #expect(coordinator.editors[id] === editor)
          #expect(!editor.isClosed)
          await editor.copy()
          #expect(world.clipboard.copies == [.pngAndTIFF])
          #expect(world.notifier.calls.contains(.notice(title: "Image copied", body: "")))
          let target = try desktop("Deleted.png")
          #expect(await editor.saveAs(to: target))
          #expect(try EditorPixels.isBlue(png: Data(contentsOf: target)))
          #expect(world.notifier.calls.contains(.saved(title: "Saved", file: "Deleted.png")))
          #expect(world.clipboard.copies == [.pngAndTIFF, .pngAndTIFF])
      }

      /// phase-4a:146 (:213), in part (an editor opened while the alert is up); phase-4a:147 (:214), in part. An
      /// editor opened on a pending capture while its Delete's alert is held hears `Deleting…` in its first push, with
      /// only Copy and Save As… on, and a Save sent then is refused at write time, the pending file unchanged. Yes
      /// removes the record and pushes the deleted subtitle; the editor stays registered and Copy still copies.
      /// `save()` calls the editor's action past the window's validation, to reach the coordinator's check behind it
      /// (+Editor:158-163; design 3.4).
      /// Stays: phase-4a:146, greying and the subtitle as shown (`EDPLACE`); ⌘S refused by the window's validation
      /// (`EDPLACE`) and its beep (`BEEP`); the test pins the coordinator's write-time refusal behind that gate.
      /// phase-4a:147, the subtitle as shown and greying (`EDPLACE`); ⌘C reaching `copyImage` (`EDPLACE`); ⇧⌘S's
      /// panel (`EDSAVEAS`).
      @Test func anEditorOpenedWhileADeleteAsksHearsItAndRefusesSave() async throws {
          defer { world.removeAll() }
          world.confirm.holds = true
          let coordinator = world.makeCoordinator()
          let record = try addPendingImage(to: coordinator)
          let pending = try #require(record.fileURL)
          let original = try Data(contentsOf: pending)
          let delete = Task { await coordinator.deleteCapture(recordID: record.id) }
          defer { delete.cancel() }
          let watch = TaskWatch(delete)
          try await eventually { world.confirm.isWaiting }
          coordinator.openEditor(recordID: record.id)
          let editor = try await openedEditor(record.id)
          let opened = try #require(editor.pushes.first)
          #expect(opened.isDeleting)
          #expect(opened.status == EditorAvailability.deletingStatus)
          #expect(opened.available == [.copy, .saveAs])
          editor.draw()
          #expect(!(await editor.save()))
          #expect(world.notifier.errors.last?.message == EditorAvailability.deletingRefusal)
          #expect(try Data(contentsOf: pending) == original)
          world.confirm.answer(true)
          try await eventually { watch.hasReturned }
          await delete.value
          #expect(coordinator.history.record(id: record.id) == nil)
          #expect(editor.pushes.last?.record == nil)
          #expect(editor.pushes.last?.status == EditorAvailability.deletedStatus)
          #expect(coordinator.editors[record.id] === editor)
          await editor.copy()
          #expect(world.clipboard.copies == [.pngAndTIFF])
      }

      /// phase-4a:162 (:231), in part. A record past Keep history is pruned on the next add, and its open editor hears
      /// at once that it was deleted: the deleted subtitle, only Copy and Save As… on, Save going to Save As…. The
      /// save-folder file stays (pruning leaves it, +Delete:237-241), the editor stays registered, and Save As… writes
      /// the edit. The line's relaunch only gives the hand check an old record; the test starts with one, stamped
      /// relative to `Date()` since the store prunes on it.
      /// Stays: the subtitle and greying (`EDPLACE`); ⇧⌘S's panel (`EDSAVEAS`).
      @Test func aPrunedCaptureTellsItsOpenEditorItWasDeleted() async throws {
          defer { world.removeAll() }
          let folder = try world.storeSaveFolder()
          let coordinator = world.makeCoordinator()
          let (record, _) = try addSavedImage(to: coordinator, in: folder, timestamp: Date(timeIntervalSinceNow: -2 * 86_400))
          let id = record.id
          coordinator.openEditor(recordID: id)
          let editor = try await openedEditor(id)
          world.settings.historyRetentionDays = 1
          coordinator.history.add(CaptureRecord(fileURL: nil, pixelWidth: 4, pixelHeight: 2, appName: nil))
          #expect(coordinator.history.record(id: id) == nil)
          let last = try #require(editor.pushes.last)
          #expect(last.record == nil)
          #expect(last.status == EditorAvailability.deletedStatus)
          #expect(last.available == [.copy, .saveAs])
          #expect(last.saveCommand == .saveAs)
          #expect(exists(try #require(record.fileURL)))
          #expect(coordinator.editors[id] === editor)
          editor.draw()
          let target = try desktop("Pruned.png")
          #expect(await editor.saveAs(to: target))
          #expect(try EditorPixels.isBlue(png: Data(contentsOf: target)))
          #expect(world.notifier.calls.contains(.saved(title: "Saved", file: "Pruned.png")))
      }
  }
  ```
  The struct's closing `}` stays last. No new import is needed: the four bodies name no type outside `Foundation`, `Testing` and `TidyShot`.

- [ ] **Add `destination` to `CoordinatorOverlayTests`.** The test below holds the world's Abort through `world.factory.standard`, so the suite gets the property catalogue 2.2 gives it, in the place `CoordinatorEditorTests` keeps its own (after `init`, CoordinatorEditorTests.swift:13-17). In `TidyShotTests/CoordinatorOverlayTests.swift`, replace
  ```swift
      init() throws {
          world = try CoordinatorWorld()
      }

      /// phase-6a :165.
  ```
  with
  ```swift
      init() throws {
          world = try CoordinatorWorld()
      }

      var destination: FakeDestination { world.factory.standard }

      /// phase-6a :165.
  ```
  (Only the first five words of the existing test's doc comment, CoordinatorOverlayTests.swift:14, are in the anchor; the rest of that line and the test are untouched.)

- [ ] **Append `aCardWhoseDeleteIsUnderWayIsNotRestorable` to `CoordinatorOverlayTests`.** It uses, at dd1231d: `canRestoreClosedOverlay` (+Overlay:79-81), `restoreClosedOverlay() async` (+Overlay:87), `closedOverlays.ids` (Coord:143, ClosedOverlays.swift:8), `deletingIDs` (Coord:200), `pendingFiles.directory`, `CoordinatorWorld.writeSparseFile(at:byteCount:)` (CoordinatorWorld.swift:159), `world.location` (:90), `MultipartUploadState(uploadID:key:location:partSize:byteCount:sourceModified:sourcePath:startedAt:)` (as CoordinatorDeleteTests.swift:241-243), `CaptureRecord.init(id:timestamp:fileURL:fileIsTemporary:…:mediaKind:durationSeconds:byteCount:unmutedIntervals:multipart:)` (CaptureRecord.swift:114-120), `FakeCards.showing`, `close(recordID:reason:)`, `calls` with `.show(UUID)` and `.close(UUID, QuickAccessCloseReason)` (CoordinatorFakes.swift:66-117), `FakeConfirm.asked` and `DeleteConfirmation.delete(CaptureRecord)` (AppEnvironment.swift:6), `FakeDestination.State`'s `holdingAbortsRemaining` and `aborts` (FakeDestination.swift:122, :78) and `FakeDestination.releaseAborts()` (:383), and `TaskWatch`. The suite's file imports only `Foundation`, `Testing` and `TidyShot`, which is all it needs. In `TidyShotTests/CoordinatorOverlayTests.swift`, replace
  ```swift
          #expect(relaunched.history.records.map(\.id) == [record.id])
      }
  }
  ```
  with
  ```swift
          #expect(relaunched.history.records.map(\.id) == [record.id])
      }

      /// phase-6a:158 (:161), full with `CoordinatorEditorTests.annotateFromACardOrRecentCapturesLeavesNothingToRestore`
      /// (the editor cases); this test pins the delete under way. A closed card whose Delete was confirmed and is
      /// still aborting its stored upload (the Abort held) is not restorable: `canRestoreClosedOverlay` is false, so
      /// the menu item stays disabled (StatusMenuController.swift:115), and the shortcut's `restoreClosedOverlay()`
      /// shows nothing and keeps the id. Once the delete ends the record is gone and the card is closed as deleted.
      /// Network Link Conditioner's `100% Loss` is the held Abort.
      @Test func aCardWhoseDeleteIsUnderWayIsNotRestorable() async throws {
          defer { world.removeAll() }
          destination.state.withLock { $0.holdingAbortsRemaining = 1 }
          defer { destination.releaseAborts() }
          let coordinator = world.makeCoordinator()
          let id = UUID()
          let url = coordinator.pendingFiles.directory.appending(path: "\(id.uuidString).mp4")
          try CoordinatorWorld.writeSparseFile(at: url, byteCount: 3)
          let stored = MultipartUploadState(uploadID: "stored-1", key: "s/STORED.mp4", location: world.location,
                                            partSize: 262_144, byteCount: 3, sourceModified: Date(),
                                            sourcePath: "/nowhere/Recording.mp4", startedAt: Date())
          let record = CaptureRecord(id: id, fileURL: url, fileIsTemporary: true, pixelWidth: 1600, pixelHeight: 1000,
                                     appName: nil, uploadState: .failed(message: "Upload was interrupted."), mediaKind: .video,
                                     durationSeconds: 10, byteCount: 3, multipart: stored)
          coordinator.history.add(record)
          world.cards.showing.insert(id)
          world.cards.close(recordID: id, reason: .user)
          #expect(coordinator.closedOverlays.ids == [id])
          #expect(coordinator.canRestoreClosedOverlay)
          let delete = Task { await coordinator.deleteCapture(recordID: id) }
          defer { delete.cancel() }
          let watch = TaskWatch(delete)
          try await eventually { destination.state.withLock { $0.aborts.count } == 1 }
          #expect(world.confirm.asked == [.delete(record)])
          #expect(coordinator.deletingIDs.contains(id))
          try #require(!coordinator.canRestoreClosedOverlay)
          await coordinator.restoreClosedOverlay()
          #expect(!world.cards.calls.contains(.show(id)))
          #expect(coordinator.closedOverlays.ids == [id])
          destination.releaseAborts()
          try await eventually { watch.hasReturned }
          await delete.value
          #expect(coordinator.history.record(id: id) == nil)
          #expect(world.cards.calls.contains(.close(id, .deleted)))
          #expect(!coordinator.canRestoreClosedOverlay)
      }
  }
  ```
  `restoreClosedOverlay()` is called only after `try #require(!coordinator.canRestoreClosedOverlay)`, so it returns at `popRestorable` (+Overlay:88-90) and never reaches `overlayScreen`'s `NSScreen.screens` read (design 5). The held delete is gated by `TaskWatch` and cancelled in a `defer` registered right after it is made; the held Abort is released in a `defer` (design 3.4 step 3, design 5).

- [ ] **Check the names and the doc comments' line lengths.** Each new test is one `func <name>(` in its file, and no doc comment line in either file passes 120 characters (counted as characters, since `⌘`, `⇧`, `⌥` and `…` are several bytes each):
  ```bash
  for t in anEditorOpenedDuringAHeldUploadHearsUploadingAndGetsSaveAndUploadBack aDeleteAskedThenCancelledThenConfirmedReachesTheOpenEditor anEditorOpenedWhileADeleteAsksHearsItAndRefusesSave aPrunedCaptureTellsItsOpenEditorItWasDeleted; do grep -c "func $t(" TidyShotTests/CoordinatorEditorTests.swift; done; grep -c "func aCardWhoseDeleteIsUnderWayIsNotRestorable(" TidyShotTests/CoordinatorOverlayTests.swift
  python3 -I -c 'import sys; [print(f, n) for f in sys.argv[1:] for n, l in enumerate(open(f, encoding="utf-8"), 1) if "///" in l and len(l.rstrip("\n")) > 120]' TidyShotTests/CoordinatorEditorTests.swift TidyShotTests/CoordinatorOverlayTests.swift
  ```
  Expected output: `1` five times, and nothing from the second command. Three statements of the built bodies pass 120 characters as built (the two `addSavedImage(…)` calls and the `CaptureRecord(…)` line with `uploadState: .failed`); they are kept as built (D11).

- [ ] **Run the two suites alone.**
  ```bash
  xcodegen generate && xcodebuild test -project TidyShot.xcodeproj -scheme TidyShot -destination 'platform=macOS' -derivedDataPath .build -only-testing:TidyShotTests/CoordinatorEditorTests 2>&1 | grep -E "Test run with|error:|TEST"
  ```
  Expected: `✔ Test run with 16 tests in 1 suite passed after <n> seconds.` (the 2 existing, Task 1's 2, Task 6's 8 and these 4) and `** TEST SUCCEEDED **`, no `error:` line other than the known noise (Global Constraints).
  ```bash
  xcodegen generate && xcodebuild test -project TidyShot.xcodeproj -scheme TidyShot -destination 'platform=macOS' -derivedDataPath .build -only-testing:TidyShotTests/CoordinatorOverlayTests 2>&1 | grep -E "Test run with|error:|TEST"
  ```
  Expected: `✔ Test run with 2 tests in 1 suite passed after <n> seconds.` (`aRelaunchForgetsClosedCardsButKeepsTheirRecords` and this one) and `** TEST SUCCEEDED **`.
  A failure here is a fact to report, not a body to change: the five bodies passed in the review's built tree (its full run printed `✔ Test <name>() passed` for each). Check first that the file's helpers are Task 1's and that nothing from the scratch suites (`CoordinatorEditorExtraTests`, `CoordinatorEditorExtra2Tests`) was copied in.

- [ ] **Run the full suite.**
  ```bash
  xcodegen generate && xcodebuild test -project TidyShot.xcodeproj -scheme TidyShot -destination 'platform=macOS' -derivedDataPath .build 2>&1 | grep -E "Test run with|error:|TEST"
  ```
  Expected: `✔ Test run with 2318 tests in 193 suites passed after <n> seconds.` and `** TEST SUCCEEDED **`. The about 40 `mdb_txn_commit error: MDB_MAP_FULL` lines the filter also prints are the known noise, as are `History file could not be read or decoded, setting it aside` (twice) and `com.apple.linkd.autoShortcut` if they show; a run of 45 s to 130 s is normal.

- [ ] **Check the diff is the two test files.**
  ```bash
  git status --short; git diff --stat
  ```
  Expected: ` M TidyShotTests/CoordinatorEditorTests.swift` and ` M TidyShotTests/CoordinatorOverlayTests.swift` only, and `git diff --stat` ends `2 files changed, 260 insertions(+)` with no deletions (both edits only add lines; each replace keeps its anchor). Nothing under `TidyShot/`, `TidyShotTests/Support/` or `docs/` changes in this task. No hand check is run; the report says so.

- [ ] **Commit.**
  ```bash
  git add TidyShotTests/CoordinatorEditorTests.swift TidyShotTests/CoordinatorOverlayTests.swift
  git commit -m "test: what an open editor hears while things happen, and a card whose delete is under way"
  ```
  No attribution lines, no session URL; do not push.

### Task 8: The marks, seams.md, the hand-check checklist, the built notes [mechanical]

**Files:**
- Modify the eight checklists that hold a marked line, with the count of lines marked in each: `docs/testing/coordinator-split-manual-checklist.md` (2), `phase-4a-manual-checklist.md` (33), `phase-4b-manual-checklist.md` (14), `phase-4c-manual-checklist.md` (3), `phase-6a-manual-checklist.md` (6), `phase-6b-manual-checklist.md` (1), `phase-7c-manual-checklist.md` (5), `small-tweaks-manual-checklist.md` (1): 65 lines, 25 full and 40 part (catalogue 1). The 8 deferred lines (phase-4a:56, :58, :88, :107, :151; phase-4c:94, :95; phase-7c:72) stay unmarked.
- Modify `docs/superpowers/notes/2026-10-30-checklist-sweep/seams.md` (design 11 items 1-4; its rules at :9-12, its table, its sections, the multi-seam section at :829-870 and the three-or-fewer section at :871).
- Create `docs/testing/editor-seam-manual-checklist.md` (design 9's four checks, in the form of `docs/testing/coordinator-harness-manual-checklist.md`).
- Modify `docs/superpowers/specs/2026-10-30-tidyshot-editor-seam-design.md` (section 12 gains one line: the branch's suite line and Release result), `docs/superpowers/notes/2026-10-30-editor-seam/tests-editor.md` (its header's "The design's review built every entry here", :33, gains "built on `editor-seam`") and `docs/superpowers/notes/2026-10-30-editor-seam/lines-editor.md` (its header, :3-7; it has no sentence that says the review built the tests, so the writer adds one or records in a decision why not).

**Interfaces:**
- Consumes (Tasks 1 to 7): the 46 test names above, each as `func <name>(` in `TidyShotTests/<Suite>.swift` for its suite (the script's check, as CT-1's Task 12), and the existing tests the marks also name (`EditorSaveTargetTests`, `EditorUploadPlanTests`, `EditorClipboardTests`, `EditorNamingTests`, `QuitHoldTests`, `CaptureIntentTests`, `ClosedOverlaysTests` and the others `lines-editor.md` lists per line), checked the same way.
- Produces: nothing a later task uses.

**Tests:** none added.
- The marks script, in the form of CT-1's Task 12 (`docs/superpowers/plans/2026-10-30-checklist-tests.md:3848-4333`: a `MARKS` table keyed by checklist and anchor text, one match per anchor asserted, every named test found, no item marked twice, none of the 65 already marked), run as `python3 - . <<'EOF'` from the repository root, prints `65 lines marked`.
- The seams.md script asserts: 42 seams; 279 B lines; Lines 404, Alone 186, Completes 279; 93 lines need two or more seams; 16 seams unlock three or fewer; the first three seams complete 78 lines and the first ten 152; and the rows `EDITOR` 73 / 26 / 26, `EDPLACE` 38 / 0 / 24 (second in the table), `TARGET` 34 / 26 / 28 (third, D56), `SAVEAS` 14 / 9 / 11, `SCREENS` 12 / 6 / 8, `EDSAVEAS` 11 / 2 / 8 (twelfth), `BGPOP` 7 / 5 / 7, `BEEP` 5 / 1 / 5, `CLOSESHEET` 4 / 1 / 3, `APPDELEGATE` 2 / 1 / 2 (Lines / Alone / Completes, design 11 item 4, with D56's difference); 57 new seam slots (item 3).
- Full suite, unchanged: `Test run with 2318 tests in 193 suites passed`. The Release build at the end: `** BUILD SUCCEEDED **`, no `error:` or `warning:` line beyond the two tool lines the Global Constraints name. `git diff --stat main -- project.yml` prints nothing, and `git diff --stat main -- TidyShot/` lists Task 1's four files only.

**Commit:** `docs: editor seam marks, seams.md, the hand-check checklist and close-out`

**Steps:**

No test is added, and nothing under `TidyShot/` or `TidyShotTests/` changes. Every step runs from the repository root
on `editor-seam` after Task 7's commit. The marks go on the checklist text as it is at dd1231d (Tasks 1 to 7 change no
document), found by text (D14); the seams.md edit works from seams.md's own lists, the design's section 11 and the
catalogue's section 9. No step runs the app; the hand checks are Tim's.

- [ ] **Step 1: Check the starting point.**
  ```bash
  git status --short; git log -1 --format=%s; git diff --stat dd1231d -- docs/testing docs/superpowers/notes docs/superpowers/specs
  ```
  Expected: `git status --short` prints nothing; the subject is Task 7's,
  `test: what an open editor hears while things happen, and a card whose delete is under way`; the diff prints
  nothing. If the diff lists a file, stop and ask: both scripts below assert dd1231d's text of these files.

- [ ] **Step 2: Mark the 65 lines.** One entry per marked line: the checklist, the catalogue key's line number at
  e011d2f (as `lines-editor.md` names it), an anchor (the start of the item's text, 49 to 65 characters, each one
  checked with `grep -c -F` to occur on exactly one line of its checklist at dd1231d), and the mark. A mark is built
  from the test's Covers in `tests-editor.md` and the line's Stays in `lines-editor.md` under design 6's rules: a full
  line gets `(suite: Suite.test, …)`; a part line gets `(suite, in part: Suite.test, …; by hand: <what stays>)`, whose
  by-hand text names the other seam in parentheses where there is one, names a stand-in as such ("Quick Look is the
  file's decode", "Preview is the `pngs` decode", "the link … is the PUT body", "`sips` is the decode and the DPI
  read"), says for phase-4a:127, :145 and :146 that the test pins the coordinator's write-time check and that the
  window's "do nothing" is its validation's (`EDPLACE`), says for phase-4a:119 and :120 that the capture's own
  clipboard copy is set up as `AppCoordinator+Save.swift` leaves it and no test drives it today (`TARGET`), and says
  for the lines at odds with the code (phase-4a:131, :132, phase-4b:112, phase-6a:199, phase-7c:171; design call 9)
  what the test pins. Each mark also names the existing tests that pin a part of the line (D13 of CT-1, D54). The
  script places a mark as CT-1's Task 12 did: at the end of the item's last line, wrapped at 120 columns with
  two-space continuation lines, or on new continuation lines when that line is longer than 120. It asserts that each
  anchor matches one line and that line starts an item, that every test a mark names is `func <name>(` in
  `TidyShotTests/<Suite>.swift`, that no item is marked twice and none of the 65 carries a mark or an
  `(obsolete: ` note already, that there are 25 full and 40 part marks in the eight checklists' counts, and that the
  8 deferred lines stay unmarked.
  ```bash
  python3 - . <<'EOF'
  import re
  import sys
  from pathlib import Path

  ROOT = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(".")

  # (checklist, catalogue key's line at e011d2f, text that occurs once in the checklist at the branch head, mark).
  # Each mark is built from the test's Covers in tests-editor.md and the line's Stays in lines-editor.md (design 6).
  MARKS = [
      ('coordinator-split', 43, 'Annotate the newest card, Save, then Upload [`+Edi',
       '(suite, in part: CoordinatorEditorUploadTests.annotateTheNewestCardSaveThenUploadWritesTheFileThenUploadsAndCopiesTheURL; by hand: the unsaved dot and the window closing (`EDPLACE`), and the URL in the real bucket; the URL showing the stroke is the PUT body)'),
      ('coordinator-split', 44, "Pin, then the pin menu's three items [`+Pins`, `+R",
       "(suite, in part: CoordinatorEditorTests.annotateFromACardOrRecentCapturesLeavesNothingToRestore, CoordinatorRecordActionsTests.copyImageReadsTheFileOrDownloadsTheObject; by hand: the pin, its second click and `Close Pinned Screenshots` (`PINS`, `SCREENS`), and the pin's Save As… panel (`SAVEAS`); the pin menu's Annotate is the card's `openEditorAfterMenuTracking`)"),
      ('phase-4a', 37, '"Upload and copy URL", a large capture with Networ',
       "(suite, in part: CoordinatorEditorTests.anEditorOpenedDuringAHeldUploadHearsUploadingAndGetsSaveAndUploadBack, EditorSaveTargetTests.availabilityWhileUploadingIsCopyAndSaveAs; by hand: the subtitle as shown and the greyed toolbar (`EDPLACE`); the slow profile is the fake's held upload)"),
      ('phase-4a', 39, 'Annotate a capture whose editor is already open (f',
       "(suite, in part: CoordinatorEditorTests.annotateOnACaptureWhoseEditorIsOpenBringsItForwardAndBuildsNoSecond; by hand: the window coming forward, which is `present()`'s own body and no seam reaches; the test pins that a second Annotate calls `present()` on the open editor and builds none)"),
      ('phase-4a', 49, 'Upload-only capture that finished uploading: after',
       '(suite: CoordinatorEditorTests.anUploadedUploadOnlyCaptureOpensFromItsObjectAndOfflineOpensNone)'),
      ('phase-4a', 52, 'Settings > Overlay, turn "Show Quick Access overla',
       '(suite: CoordinatorEditorTests.withTheOverlayOffEveryAfterCaptureModeStillOpensTheEditor)'),
      ('phase-4a', 94, 'Saved capture: Redact, ⌘S. The same file in the sa',
       "(suite, in part: CoordinatorEditorSaveTests.saveWritesOverTheSaveFolderFileAndUploadsNothing; by hand: the unsaved dot clearing (`EDPLACE`) and the menu drawing the row's thumbnail; Quick Look is the file's decode, and the row's thumbnail is the new thumbnail's decode)"),
      ('phase-4a', 95, 'Capture uploaded with "Upload and copy URL": ⌘S re',
       '(suite, in part: CoordinatorEditorSaveTests.saveOverAnUploadedCaptureRewritesTheFileOnlyAndMarksItsLinkStale, CaptureRecordTests.localEditMarksStaleWhenThereIsALink, EditorSaveTargetTests.noticeOnlyWhenUploadIsStale; by hand: the subtitle as shown (`EDPLACE`); the link still showing the original is the absence of a PUT)'),
      ('phase-4a', 96, 'Capture from before Phase 3: ⌘S rewrites its file,',
       '(suite, in part: CoordinatorEditorSaveTests.saveOverAnUploadedCaptureRewritesTheFileOnlyAndMarksItsLinkStale, EditorSaveTargetTests.prePhaseThreeUploadedWithFileOverwrites; by hand: the subtitle as shown (`EDPLACE`))'),
      ('phase-4a', 97, 'Upload-only capture that finished uploading: Save',
       "(suite, in part: CoordinatorEditorSaveTests.saveAsOnAnUploadOnlyCaptureWritesThePNGAndUploadsNothing, EditorSaveTargetTests.saveCommandWritesOverOrOpensThePanel; by hand: the sheet with its name and folder (`EDSAVEAS`), and Save shown on and the unsaved dot (`EDPLACE`); Save being on is the first push's `available`)"),
      ('phase-4a', 98, 'Upload-only capture whose upload failed: Redact, ⌘',
       '(suite: CoordinatorEditorSaveTests.saveOnAFailedUploadOnlyCaptureRewritesPendingAndRetryUploadsTheEdit)'),
      ('phase-4a', 99, 'Lock the saved file (Finder, Get Info, Locked), ed',
       "(suite, in part: CoordinatorEditorSaveTests.saveOverALockedFileSaysNotSavedAndPutsTheEditOnTheClipboard; by hand: the unsaved dot staying (`EDPLACE`); Finder's Locked is the file's immutable flag)"),
      ('phase-4a', 102, 'Saved capture: edit, then ⇧⌘S. The save panel sugg',
       "(suite, in part: CoordinatorEditorSaveTests.saveAsElsewhereWritesA144DPICopyAndLeavesTheCaptureAlone, EditorNamingTests.saveFolderFileSuggestsItsOwnName, ImageEncoderTests.retinaScaleWrites144DPI; by hand: the panel's suggestion and the choice of the Desktop (`EDSAVEAS`), and the unsaved dot (`EDPLACE`); `sips` is the decode and the DPI read)"),
      ('phase-4a', 106, '⇧⌘S on a saved capture and save over its own file',
       '(suite, in part: CoordinatorEditorSaveTests.saveAsOntoItsOwnFileIsASave, EditorSaveTargetTests.saveAsOntoTheOwnFileIsASave; by hand: the Replace confirmation (`EDSAVEAS`) and the subtitle as shown (`EDPLACE`))'),
      ('phase-4a', 112, 'With "Show notification" off, Copy posts nothing.',
       '(suite: CoordinatorEditorSaveTests.copyWithShowNotificationOffPostsNothing)'),
      ('phase-4a', 115, '"Save and copy image" with "Copy image to clipboar',
       '(suite: CoordinatorEditorSaveTests.aSaveOrSaveAsTakesTheClipboardOnlyWhileItHoldsTheCapture, EditorClipboardTests.replacesWhenStillOriginal)'),
      ('phase-4a', 116, 'The same with ⇧⌘S in place of ⌘S, saving to the De',
       '(suite: CoordinatorEditorSaveTests.aSaveOrSaveAsTakesTheClipboardOnlyWhileItHoldsTheCapture, EditorClipboardTests.replacesWhenStillOriginal)'),
      ('phase-4a', 117, 'Capture, copy some text in TextEdit, then Annotate, Redact, ⇧⌘S:',
       '(suite: CoordinatorEditorSaveTests.aSaveOrSaveAsTakesTheClipboardOnlyWhileItHoldsTheCapture, EditorClipboardTests.leavesWhenUserCopiedSomethingElse)'),
      ('phase-4a', 118, 'Capture, copy some text in TextEdit, then Annotate, Redact, ⌘S: t',
       '(suite: CoordinatorEditorSaveTests.aSaveOrSaveAsTakesTheClipboardOnlyWhileItHoldsTheCapture, EditorClipboardTests.leavesWhenUserCopiedSomethingElse)'),
      ('phase-4a', 119, '"Upload and copy URL" with no destination (Forget',
       "(suite, in part: CoordinatorEditorUploadTests.withNoDestinationSaveTakesTheClipboardAndUploadIsRefused, EditorUploadPlanTests.uploadOutcomeClosesWhenEnqueued; by hand: the editor staying open (`EDPLACE`); the capture's own clipboard copy and owner are set up as `AppCoordinator+Save.swift:32-34` and `:57-67` leave them with no destination, and no test drives that step today (`TARGET`))"),
      ('phase-4a', 120, '"Upload and copy URL" with "Also copy image" on: c',
       "(suite, in part: CoordinatorEditorUploadTests.anUploadAfterTheCapturesOwnClosesAtOnceAndEndsWithTheLinkCopied; by hand: the editor closing (`EDPLACE`); the capture's own clipboard copy and owner are set up as `AppCoordinator+Save.swift:30-31` and `:57-67` leave them, and no test drives that step today (`TARGET`))"),
      ('phase-4a', 123, 'Capture uploaded with "Upload and copy URL": Redac',
       "(suite, in part: CoordinatorEditorUploadTests.uploadWritesTheFileFirstThenReplacesTheLinksObject, EditorUploadPlanTests.uploadOutcomeClosesWhenEnqueued, .sameLocationUnsharedIsReplace; by hand: the editor closing with no sheet (`EDPLACE`); the link showing the redaction is the PUT body under the link's key)"),
      ('phase-4a', 124, 'Upload-only capture that finished uploading: Redac',
       '(suite, in part: CoordinatorEditorUploadTests.uploadOfAnUploadOnlyCaptureWritesPendingThenReplacesItsKey, EditorSaveTargetTests.uploadOutsideTheSaveFolderGetsAPendingFile; by hand: the editor closing (`EDPLACE`); the link showing the redaction is the PUT body under its key)'),
      ('phase-4a', 127, 'Saved capture never uploaded: ⌥⌘U beeps. ⌘U upload',
       "(suite, in part: CoordinatorEditorUploadTests.uploadAsNewWithoutALinkIsRefusedAndUploadMakesTheFirstLink, EditorSaveTargetTests.uploadAsNewNeedsALink, .gateRefusesDisabledShortcut, EditorUploadPlanTests.neverUploadedIsNewObjectWithoutSupersede; by hand: ⌥⌘U refused by the window's validation (`EDPLACE`) with its beep (`BEEP`), and the editor closing (`EDPLACE`); the test pins the coordinator's write-time check behind that validation, which posts a notice, and the window's doing nothing is its validation's)"),
      ('phase-4a', 129, 'Capture from before Phase 3: ⌘U shows the notice `',
       '(suite: CoordinatorEditorUploadTests.uploadOfAPrePhase3CaptureMakesANewLinkAndDeletesNothing, EditorUploadPlanTests.prePhaseThreeIsNewObjectWithNotice)'),
      ('phase-4a', 130, 'Optional, with a second bucket: point Settings > U',
       '(suite: CoordinatorEditorUploadTests.uploadAfterTheDestinationChangedGoesToTheNewBucketAndDeletesTheOldObject, EditorUploadPlanTests.destinationChangedSupersedesAtOldLocationWithNotice)'),
      ('phase-4a', 131, 'Enter a wrong secret access key in Settings > Uplo',
       "(suite, in part: CoordinatorEditorUploadTests.aFailedReplaceKeepsTheLinkAndTheEditAndTheRightKeyReplacesIt, CoordinatorUploadTests.aFailedUploadMarksTheRecordOrReturnsItToItsLink, EditorUploadPlanTests.failureRestoresPriorUploadAndDropsSupersededRef, .sameLocationUnsharedIsReplace, EditorSaveTargetTests.noticeOnlyWhenUploadIsStale; by hand: the editor closing and the subtitle as shown (`EDPLACE`); the link is the PUT body; the test pins one attempt, since a 403 is not retried, and the notice titled `Not uploaded` with the line's text as its body)"),
      ('phase-4a', 132, 'Folder change with a bad key: Settings > General,',
       "(suite, in part: CoordinatorEditorUploadTests.aFailedReplaceAfterAFolderChangeKeepsTheEditInPendingUntilTheNextUpload, EditorSaveTargetTests.uploadOutsideTheSaveFolderGetsAPendingFile, EditorUploadPlanTests.failedUploadOnlyReplaceKeepsEditedPendingFileAndMarksStale; by hand: the editor closing (`EDPLACE`); the line's last step is at odds with the code: the test pins that Retry Failed Uploads does nothing for this capture, and that the next ⌘U replaces the link's object and removes `pending/<UUID>.png`)"),
      ('phase-4a', 133, 'The same wrong key, ⌘U on an upload-only capture t',
       '(suite, in part: CoordinatorEditorUploadTests.aFailedReplaceOfAnUploadOnlyCaptureKeepsPendingAcrossARelaunchUntilTheNextUpload, EditorUploadPlanTests.failedUploadOnlyReplaceKeepsEditedPendingFileAndMarksStale, HistoryStoreTests.staleUploadOnlyEditIsNeverPruned, EditorInputTests.pendingFileForUploadOnlyPending; by hand: the editor closing and the subtitle as shown (`EDPLACE`))'),
      ('phase-4a', 145, 'Slow profile, "Upload and copy URL": capture somet',
       '(suite, in part: CoordinatorEditorTests.anEditorOpenedDuringAHeldUploadHearsUploadingAndGetsSaveAndUploadBack, EditorSaveTargetTests.availabilityWhileUploadingIsCopyAndSaveAs, .gateRefusesDisabledShortcut; by hand: the subtitle as shown, the greyed items and ⌘C and ⇧⌘C reaching the copy (`EDPLACE`), ⌘S, ⌘U and ⌥⌘U refused by the window\'s validation (`EDPLACE`) with their beeps (`BEEP`), and ⇧⌘S\'s panel (`EDSAVEAS`); the test pins the coordinator\'s write-time check behind that validation, which posts `Not saved` or `Not uploaded`, and the line\'s "do nothing" is the validation\'s; the slow profile is the fake\'s held upload)'),
      ('phase-4a', 146, 'With an editor open, press Delete on its row and l',
       "(suite, in part: CoordinatorEditorTests.aDeleteAskedThenCancelledThenConfirmedReachesTheOpenEditor, .anEditorOpenedWhileADeleteAsksHearsItAndRefusesSave, EditorSaveTargetTests.statusSaysDeletingWhileDeleting, .availabilityWhileDeletingIsCopyAndSaveAs; by hand: the greyed items and the subtitle as shown (`EDPLACE`), and ⌘S refused by the window's validation (`EDPLACE`) with its beep (`BEEP`); the tests pin the coordinator's write-time check behind that validation, and the window's refusal is its validation's)"),
      ('phase-4a', 147, 'Delete again and confirm: the subtitle reads `This',
       "(suite, in part: CoordinatorEditorTests.aDeleteAskedThenCancelledThenConfirmedReachesTheOpenEditor, .anEditorOpenedWhileADeleteAsksHearsItAndRefusesSave, EditorSaveTargetTests.availabilityWhenDeletedIsCopyAndSaveAs; by hand: the subtitle as shown, the greyed items and ⌘C reaching the copy (`EDPLACE`), and ⇧⌘S's panel (`EDSAVEAS`))"),
      ('phase-4a', 148, 'Editor open on a capture in the save folder: Setti',
       "(suite, in part: CoordinatorEditorUploadTests.aNewSaveFolderReachesTheOpenEditorAndUploadGoesThroughPending, EditorSaveTargetTests.availabilityFollowsSaveFolderChange, .uploadOutsideTheSaveFolderGetsAPendingFile; by hand: ⌘S's panel (`EDSAVEAS`), ⌘W's Save (`CLOSESHEET`, `EDSAVEAS`), and the subtitle as shown and the editor closing (`EDPLACE`))"),
      ('phase-4a', 155, 'Quit TidyShot from the menu with a changed editor:',
       "(suite, in part: CoordinatorEditorTests.quitAsksEachChangedEditorCancelStopsItDontSaveLetsItGo, QuitHoldTests.unsavedEditorsHold; by hand: the sheet itself (`CLOSESHEET`) and the real quit's reply (`APPDELEGATE`))"),
      ('phase-4a', 162, "Quit, set one record's `timestamp` in `history.jso",
       "(suite, in part: CoordinatorEditorTests.aPrunedCaptureTellsItsOpenEditorItWasDeleted, EditorSaveTargetTests.availabilityWhenDeletedIsCopyAndSaveAs, HistoryStoreTests.prunesRecordsOlderThanRetention; by hand: the subtitle as shown and the greyed items (`EDPLACE`), and ⇧⌘S's panel (`EDSAVEAS`))"),
      ('phase-4b', 71, 'Saved pixel size: on a saved capture, crop to a re',
       '(suite: CoordinatorEditorSaveTests.saveWithACropWritesTheCroppedSizeAtTheCapturesScaleAndReopensCropped, EditorModelTests.undoRestoresUncropped, EditorFlattenerTests.pngRoundTripKeepsScaleTwo)'),
      ('phase-4b', 73, 'Reopen the cropped capture with Annotate: the edit',
       '(suite: CoordinatorEditorSaveTests.saveWithACropWritesTheCroppedSizeAtTheCapturesScaleAndReopensCropped, EditorModelTests.undoRestoresUncropped)'),
      ('phase-4b', 74, 'Uploaded pixel size: on a capture uploaded with "U',
       '(suite: CoordinatorEditorUploadTests.uploadWritesTheFileFirstThenReplacesTheLinksObject)'),
      ('phase-4b', 75, 'Upload-only capture that finished uploading: crop,',
       '(suite: CoordinatorEditorUploadTests.uploadOfAnUploadOnlyCaptureWritesPendingThenReplacesItsKey)'),
      ('phase-4b', 76, 'Save As… (⇧⌘S) with a crop: the new PNG has the cr',
       '(suite: CoordinatorEditorSaveTests.saveAsWithACropWritesACroppedCopyAndLeavesTheCaptureAlone)'),
      ('phase-4b', 77, 'Copy (⌘C with nothing selected) with a crop: Previ',
       '(suite: CoordinatorEditorSaveTests.copyWithACropPutsTheCroppedImageAtPointSizeAndSaysImageCopied)'),
      ('phase-4b', 92, '⌘C with nothing selected still copies the flattene',
       '(suite, in part: CoordinatorEditorSaveTests.copyWithACropPutsTheCroppedImageAtPointSizeAndSaysImageCopied; by hand: which command reaches the copy, ⌘C with and without a selection, ⇧⌘C and the toolbar button (`EDPLACE`); Preview is the `pngs` decode)'),
      ('phase-4b', 105, 'Saved capture, never uploaded: Annotate on its row',
       '(suite: CoordinatorEditorSaveTests.saveWithTextEllipseAndCropWritesAllThreeIntoTheSameFile)'),
      ('phase-4b', 106, 'Capture uploaded with "Upload and copy URL": Annot',
       '(suite, in part: CoordinatorEditorUploadTests.uploadWritesTheFileFirstThenReplacesTheLinksObject; by hand: the editor closing at once (`EDPLACE`); the link showing the highlight is the PUT body)'),
      ('phase-4b', 107, 'Upload-only capture whose upload failed: opens fro',
       '(suite: CoordinatorEditorSaveTests.saveOnAFailedUploadOnlyCaptureRewritesPendingAndRetryUploadsTheEdit, EditorInputTests.pendingFileForUploadOnlyPending, EditorSaveTargetTests.pendingFileIsPendingTarget)'),
      ('phase-4b', 108, 'Upload-only capture that finished uploading: Annot',
       '(suite: CoordinatorEditorUploadTests.uploadOfAnUploadOnlyCaptureWritesPendingThenReplacesItsKey)'),
      ('phase-4b', 112, 'Enter a wrong secret access key in Settings > Uplo',
       "(suite, in part: CoordinatorEditorUploadTests.aFailedReplaceOfAnUploadOnlyCaptureKeepsPendingAcrossARelaunchUntilTheNextUpload, CoordinatorUploadTests.aFailedUploadMarksTheRecordOrReturnsItToItsLink; by hand: the editor closing (`EDPLACE`), and the real quit and relaunch, for which the test builds a second coordinator; the test pins one attempt, since a 403 is not retried, and the notice titled `Not uploaded` with the line's text as its body)"),
      ('phase-4b', 113, 'The row still copies the old URL. Annotate on the',
       '(suite, in part: CoordinatorEditorUploadTests.aFailedReplaceOfAnUploadOnlyCaptureKeepsPendingAcrossARelaunchUntilTheNextUpload; by hand: the subtitle as shown (`EDPLACE`))'),
      ('phase-4b', 114, 'Enter the right key and press ⌘U: the same URL now',
       '(suite: CoordinatorEditorUploadTests.aFailedReplaceOfAnUploadOnlyCaptureKeepsPendingAcrossARelaunchUntilTheNextUpload)'),
      ('phase-4c', 179, 'Once the upload has finished, reopen the capture w',
       '(suite: CoordinatorEditorUploadTests.anUploadedCaptureReopensFlatWithItsMarksInThePixels)'),
      ('phase-4c', 201, 'Shape and Size survive a relaunch. Choose Ellipse',
       '(suite, in part: CoordinatorEditorTests.anEditorOpensWithTheStoredSpotlightShapeAndCounterSize, AppSettingsTests.editorDefaultsRoundTripThroughSecondInstance, .spotlightAndCounterDefaultsAreRegistered, EditorToolbarTests.currentDefaultsCarryEveryEditorDefault, EditorModelTests.aNewSpotlightTakesTheShapeDefault, .aNewCounterTakesTheSizeAndColourDefaults; by hand: choosing Ellipse and Large in the popover (`EDDEFAULTS`), the rows as drawn, `defaults read` and the relaunch)'),
      ('phase-4c', 214, 'An older capture, made before 4c, opens in the edi',
       '(suite: CoordinatorEditorTests.aCaptureFromBefore4cOpensEditsAndSavesAsBefore, AnnotationDocumentTests.documentWithoutSpotlightDimReadsHalf)'),
      ('phase-6a', 131, 'Delete a card in the middle of the stack and Annot',
       '(suite, in part: CoordinatorEditorTests.annotateFromACardOrRecentCapturesLeavesNothingToRestore; by hand: the gap in the stack closing (`QASTACK`))'),
      ('phase-6a', 152, 'Annotate from a card opens the editor and closes t',
       '(suite: CoordinatorEditorTests.annotateFromACardOrRecentCapturesLeavesNothingToRestore, ClosedOverlaysTests.onlyUserAutoPushedAndDraggedClosesAreRestorable)'),
      ('phase-6a', 158, 'Delete a capture from its card, and open the edito',
       '(suite: CoordinatorEditorTests.annotateFromACardOrRecentCapturesLeavesNothingToRestore, CoordinatorOverlayTests.aCardWhoseDeleteIsUnderWayIsNotRestorable)'),
      ('phase-6a', 164, "A restored card's Annotate opens the editor from t",
       "(suite, in part: CoordinatorEditorTests.aRestoredCardsAnnotateOpensFromTheFileOrTheBucket, CoordinatorDragOutTests.aRestoredUploadOnlyCardsQuietDownloadIsNamedForItsKey; by hand: the restore itself, which reads the screens (`SCREENS`); the test opens a showing card with no retained image, as a restored one is, and for the uploaded upload-only capture before and after the restore's quiet download)"),
      ('phase-6a', 198, 'Upload only, after the upload: the card is still o',
       "(suite, in part: CoordinatorEditorTests.anUploadedUploadOnlyCardsCopyImageAndAnnotateReadTheDragCopy, CoordinatorUploadTests.anUploadedUploadOnlyImageMovesToItsDragFolderOnlyWithACard; by hand: the card's Save As… panel (`SAVEAS`), and Slack reading the file)"),
      ('phase-6a', 199, "An edited capture's drag copy is replaced. Upload-",
       '(suite, in part: CoordinatorEditorSaveTests.saveOverTheFileRemovesTheDragCopyAndEveryReadGivesTheEdit, CoordinatorEditorUploadTests.uploadOfAnUploadOnlyCaptureRemovesItsDragCopyAndEveryReadGivesTheEdit; by hand: the card\'s Save As… panel (`SAVEAS`), and the drop; the line\'s "from the card" cannot happen after an Annotate, which closes the card for good, and in upload-only mode ⌘S is Save As…, so the tests read through Recent Captures and remove the drag copy with ⌘U there and ⌘S over a saved file)'),
      ('phase-6b', 118, '`action=annotate`: the after-capture action runs,',
       '(suite, in part: CoordinatorEditorUploadTests.annotateTheNewestCardSaveThenUploadWritesTheFileThenUploadsAndCopiesTheURL, CaptureIntentTests.annotateRunsTheAfterCaptureActionThenOpensTheEditor, .pinRunsTheAfterCaptureActionThenPins; by hand: reaching `save(_:intent:)` (`TARGET`) and the `action=pin` half (`PINS`); the test pins the editor opening on the new capture and its card closing)'),
      ('phase-7c', 169, 'Copy (⇧⌘C, or ⌘C with nothing selected, since ⌘C w',
       "(suite, in part: CoordinatorEditorSaveTests.copyWithABackgroundPutsTheComposedCanvasOnTheClipboard; by hand: the window's routing of ⇧⌘C, ⌘C and the toolbar button to the copy (`EDPLACE`); Preview is the `pngs` decode)"),
      ('phase-7c', 170, 'Save (⌘S) on a capture with a local file: the file',
       '(suite, in part: CoordinatorEditorSaveTests.saveWithABackgroundWritesTheComposedCanvasAndReopensFlat, .saveWritesOverTheSaveFolderFileAndUploadsNothing; by hand: the clean state as the window shows it (`EDPLACE`) and the thumbnail as drawn)'),
      ('phase-7c', 171, 'Annotate the saved capture again: it opens as the',
       "(suite, in part: CoordinatorEditorSaveTests.saveWithABackgroundWritesTheComposedCanvasAndReopensFlat; by hand: the popover's switch turned on, whose setter reads `AppSettings.shared` (`BGPOP`), and the switch drawn in the window (`EDPLACE`); whether a second background is expected is Tim's call; the test closes the first editor before the reopen, since an Annotate while it is open brings it forward with its background)"),
      ('phase-7c', 172, 'Save As… (⇧⌘S): the file is the composed image; th',
       '(suite, in part: CoordinatorEditorSaveTests.saveAsWithABackgroundWritesTheComposedImageAndLeavesTheCaptureAlone; by hand: the panel (`EDSAVEAS`))'),
      ('phase-7c', 187, "Open the window capture in the editor (the card's",
       "(suite, in part: CoordinatorEditorTests.aComposedWindowCaptureOpensFlatWithNoBackground; by hand: producing the window capture (`TARGET`), and the popover's switch as its binding shows it (`BGPOP`) and drawn in the window (`EDPLACE`))"),
      ('small-tweaks', 18, 'Edit a capture in the editor and Save: its row sho',
       '(suite: CoordinatorEditorUploadTests.annotateTheNewestCardSaveThenUploadWritesTheFileThenUploadsAndCopiesTheURL, CoordinatorEditorSaveTests.saveWritesOverTheSaveFolderFileAndUploadsNothing)'),
  ]

  # The 8 deferred lines (design 6, catalogue 7): no mark, before or after.
  DEFERRED = [
      ('phase-4a', 56, 'The toolbar shows, in order: the fourteen tools (S'),
      ('phase-4a', 58, 'With the canvas focused, `V` `D` `X` `B` `R` `A` p'),
      ('phase-4a', 88, '⌘1 shows the picture at its natural point size and'),
      ('phase-4a', 107, 'Edit, ⌘U, and keep drawing before the window close'),
      ('phase-4a', 151, '⌘W on an editor with no changes closes it at once.'),
      ('phase-4c', 94, 'The toolbar shows fourteen tools, in order: Select'),
      ('phase-4c', 95, 'With the canvas focused, `S` (either case) picks S'),
      ('phase-7c', 72, 'The toolbar in the editor has a `Background` butto'),
  ]

  PER_FILE = {"coordinator-split": 2, "phase-4a": 33, "phase-4b": 14, "phase-4c": 3, "phase-6a": 6, "phase-6b": 1,
              "phase-7c": 5, "small-tweaks": 1}
  WIDTH = 120


  def tests_named(mark):
      """Every Suite.test the mark names, the `.test` shorthand expanded."""
      body = re.sub(r"^\(suite(, in part)?: ", "", mark).split("; by hand")[0].rstrip(")")
      suite, names = None, []
      for part in (p.strip() for p in body.split(",")):
          if part.startswith("."):
              names.append((suite, part[1:]))
          else:
              suite, name = part.split(".", 1)
              names.append((suite, name))
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
      """The item's lines with `mark` at the end of its last line, as CT-1 placed its marks: appended when that line
      is at most WIDTH long, otherwise on new continuation lines; a closing `______` blank stays last."""
      words = mark.split(" ")
      item = list(item)
      if item[-1].endswith(" ______"):
          item[-1] = item[-1][: -len(" ______")]
          words.append("______")
      last = item[-1]
      if len(last) <= WIDTH:
          return item[:-1] + wrap(last, words)
      return item + wrap("", words)


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


  assert len(MARKS) == 65, len(MARKS)
  assert sum(1 for m in MARKS if m[3].startswith("(suite: ")) == 25, "full marks"
  assert sum(1 for m in MARKS if m[3].startswith("(suite, in part: ")) == 40, "part marks"
  assert all(m[3].startswith(("(suite: ", "(suite, in part: ")) and m[3].endswith(")") for m in MARKS)
  assert all(("; by hand: " in m[3]) == m[3].startswith("(suite, in part: ") for m in MARKS), "a part mark's by-hand text"
  keys = [(m[0], m[1]) for m in MARKS] + [(d[0], d[1]) for d in DEFERRED]
  assert len(DEFERRED) == 8 and len(set(keys)) == 73, "65 marked and 8 deferred, each once"
  for checklist, count in PER_FILE.items():
      assert sum(1 for m in MARKS if m[0] == checklist) == count, checklist

  missing = []
  for _, _, _, mark in MARKS:
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
      for _, line, anchor, mark in (m for m in MARKS if m[0] == checklist):
          start, end = item_at(lines, anchor, f"{checklist}:{line}")
          item = lines[start:end]
          assert "(suite" not in " ".join(item) and "(obsolete: " not in " ".join(item), \
              f"{checklist}:{line} is already marked"
          spans.append((start, end, place(item, mark)))
      starts = [s for s, _, _ in spans]
      assert len(set(starts)) == len(starts), f"{checklist}: two marks on one item"
      for start, end, item in sorted(spans, reverse=True):
          assert all(len(l) <= WIDTH for l in item[1:]) and (len(item[0]) <= WIDTH or item[0] == lines[start])
          lines[start:end] = item
          marked += 1
      for _, line, anchor in (d for d in DEFERRED if d[0] == checklist):
          start, end = item_at(lines, anchor, f"{checklist}:{line} (deferred)")
          assert "(suite" not in " ".join(lines[start:end]), f"{checklist}:{line} is deferred and must stay unmarked"
      path.write_text("\n".join(lines))
  print(f"{marked} lines marked")
  EOF
  ```
  Expected: `65 lines marked`. A `tests not found:` assertion means a task before this one left a test out or named it
  otherwise; stop and report it rather than editing the mark.

- [ ] **Step 3: Check the marks.**
  ```bash
  git diff --stat -- docs/testing
  ```
  Expected, exactly:
  ```
   docs/testing/coordinator-split-manual-checklist.md |   8 ++++++++
   docs/testing/phase-4a-manual-checklist.md          | 109 ++++++++++-
   docs/testing/phase-4b-manual-checklist.md          |  28 +++++-
   docs/testing/phase-4c-manual-checklist.md          |  10 +-
   docs/testing/phase-6a-manual-checklist.md          |  22 ++-
   docs/testing/phase-6b-manual-checklist.md          |   5 +
   docs/testing/phase-7c-manual-checklist.md          |  15 +-
   docs/testing/small-tweaks-manual-checklist.md      |   2 +
   8 files changed, 189 insertions(+), 10 deletions(-)
  ```
  (the bars' lengths depend on the terminal; the counts do not). The 10 deletions are the ten items whose mark begins
  on the item's own line, since it is short enough (phase-4a:96, :112, :116, :117, :118; phase-4b:75; phase-4c:214;
  phase-6a:131, :152; phase-7c:172); every other mark is on new continuation lines. Read
  `git diff -- docs/testing/phase-4a-manual-checklist.md` and confirm no line outside a marked item changed.

- [ ] **Step 4: Edit seams.md as the design's section 11 says.** The script reads seams.md's table and its 41 seam
  sections (each line list, with its "(also …)" note and free-text notes), checks that they reproduce the table's
  Lines, Alone and Completes (347, 225, 279), and then: (item 1) gives each of `EDITOR`'s 73 entries its verdict
  (`; CT-2: full`, `; CT-2: in part`, `; CT-2: deferred`) and a bullet saying so; (item 2) adds the `EDPLACE` row and
  section, "Editor window placement", effort S (D57), with its 38 lines, the 8 deferred and the 30 part lines whose
  marks name it (catalogue 9); (item 3) adds the 19 joins (`EDSAVEAS` 7, `CLOSESHEET` 1, `BEEP` 4, `SAVEAS` 1,
  `SCREENS` 1, `BGPOP` 2, `TARGET` 2, `APPDELEGATE` 1), each noted "also `EDITOR`, in part since CT-2", replaces the
  free-text notes on phase-4a:97 and :148 under `EDITOR` (seams.md:83, :107) by the rows they join, widens `BEEP`'s
  Replaces line (design call 12), and asserts 57 new slots; (item 4) recounts by seams.md's rules (:9-12), sorts the
  table and the sections by Lines (then Alone, then key, the order the table already follows), renumbers them,
  regenerates every "(also …)" note of the 41 lines whose seams changed, in table order, rewrites the summary's
  counts, and regenerates the multi-seam and three-or-fewer sections in their existing form (each line's text cut at
  39 and 47 characters, which reproduces all 54 multi-seam entries and every unchanged three-or-fewer entry as they
  are; the script asserts both). It asserts 42 seams, 279 B lines, Lines 404, Alone 186, Completes 279, 93 lines
  needing two or more seams, 16 seams unlocking three or fewer, the first three seams completing 78 lines and the
  first ten 152, the rows `EDITOR` 73 / 26 / 26, `EDPLACE` 38 / 0 / 24, `TARGET` 34 / 26 / 28, `SAVEAS` 14 / 9 / 11,
  `SCREENS` 12 / 6 / 8, `EDSAVEAS` 11 / 2 / 8, `BGPOP` 7 / 5 / 7, `BEEP` 5 / 1 / 5, `CLOSESHEET` 4 / 1 / 3,
  `APPDELEGATE` 2 / 1 / 2, every other row unchanged, and `EDPLACE` second, `TARGET` third and `EDSAVEAS` twelfth.
  The design's section 11 says `TARGET` is fourth and the first three seams complete 58; sorted by Lines, `TARGET`
  (34) comes before `CAPSRC` (33), so the script asserts third and 78 (D56).
  ```bash
  python3 - . <<'EOF'
  import re
  import sys
  from pathlib import Path

  ROOT = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(".")
  PATH = ROOT / "docs" / "superpowers" / "notes" / "2026-10-30-checklist-sweep" / "seams.md"

  # Design section 11 and lines-editor.md: each EDITOR line's CT-2 verdict.
  FULL = """phase-4a:49 phase-4a:52 phase-4a:98 phase-4a:112 phase-4a:115 phase-4a:116 phase-4a:117 phase-4a:118 phase-4a:129
      phase-4a:130 phase-4b:71 phase-4b:73 phase-4b:74 phase-4b:75 phase-4b:76 phase-4b:77 phase-4b:105 phase-4b:107
      phase-4b:108 phase-4b:114 phase-4c:179 phase-4c:214 phase-6a:152 phase-6a:158 small-tweaks:18""".split()
  DEFERRED = """phase-4a:56 phase-4a:58 phase-4a:88 phase-4a:107 phase-4a:151 phase-4c:94 phase-4c:95 phase-7c:72""".split()
  # Item 2: EDPLACE's 38 lines, the 8 deferred and the 30 part lines whose marks name it (catalogue section 9).
  EDPLACE_PART = """coordinator-split:43 phase-4a:37 phase-4a:94 phase-4a:95 phase-4a:96 phase-4a:97 phase-4a:99 phase-4a:102
      phase-4a:106 phase-4a:119 phase-4a:120 phase-4a:123 phase-4a:124 phase-4a:127 phase-4a:131 phase-4a:132
      phase-4a:133 phase-4a:145 phase-4a:146 phase-4a:147 phase-4a:148 phase-4a:162 phase-4b:92 phase-4b:106
      phase-4b:112 phase-4b:113 phase-7c:169 phase-7c:170 phase-7c:171 phase-7c:187""".split()
  # Item 3: the other rows the part lines join.
  JOINS = {
      "EDSAVEAS": "phase-4a:97 phase-4a:102 phase-4a:106 phase-4a:145 phase-4a:147 phase-4a:148 phase-4a:162".split(),
      "CLOSESHEET": ["phase-4a:148"],
      "BEEP": "phase-4a:107 phase-4a:127 phase-4a:145 phase-4a:146".split(),
      "SAVEAS": ["phase-6a:199"],
      "SCREENS": ["phase-6a:164"],
      "BGPOP": ["phase-7c:171", "phase-7c:187"],
      "TARGET": ["phase-4a:119", "phase-4a:120"],
      "APPDELEGATE": ["phase-4a:155"],
  }
  # Item 3: these free-text notes under EDITOR are replaced by the rows the lines join.
  REPLACED_NOTES = {
      "phase-4a:97": "; the sheet itself is EDSAVEAS; the write goes through actions.saveAs",
      "phase-4a:148": "; the Close sheet's Save opening the panel also needs EDSAVEAS and CLOSESHEET",
  }
  EDPLACE_ROW = ("Editor window placement", "S")
  EDPLACE_BULLETS = [
      "- Replaces: Inside `EditorWindowController` (TidyShot/Editor/Window/EditorWindowController.swift): the screen "
      "read in `placeWindow` (:123: `NSScreen.screens`, `NSEvent.mouseLocation`, `NSScreen.main`), the display under the "
      "window (`displayID`, :321-322), and the Space-change observer on `NSWorkspace.shared.notificationCenter` "
      "(:103-106, removed at :500). Until they move, no test can build a controller, so the window's own glue (the unsaved "
      "dot, the subtitle as shown, greyed items, key routing, the validation that refuses a shortcut, closing, the toolbar) "
      "runs in no test. `EditorToolbarTests.makeEditor` (TidyShotTests/EditorToolbarTests.swift:54-66) builds one today "
      "and is fixed with it.",
      "- Shape: An `EditorWindowPlacement` value (`visibleFrame`, `displayID`, `spaceChanges`) passed to "
      "`EditorWindowController.init`, `.live` by default; the suite passes a fixed frame, no display and a notification "
      "centre of its own.",
      "- Live: `.live` reads the screen under the mouse (else the main screen, else the first), the window's own screen, "
      "and `NSWorkspace.shared.notificationCenter`, as the controller does now.",
      "- Effort for the seam: S",
      "- Note: Designed and built in the CT-2 review: `docs/superpowers/notes/2026-10-30-editor-seam/edplace-design.md` "
      "sections 2.1, 4 and 8 (its diff, fakes and controller tests, `Test run with 2283 tests in 193 suites passed` in "
      "that scratch tree). CT-2 left these lines to it: the 8 it deferred whole and the 30 it marked in part, whose marks "
      "name `EDPLACE` (design section 11).",
  ]
  EDITOR_NOTE = ("- CT-2: Built on `editor-seam` (`docs/superpowers/specs/2026-10-30-tidyshot-editor-seam-design.md`). "
                 "Each line below carries its CT-2 verdict; a line marked in part also sits under every other seam its "
                 "mark names, noted there as \"also `EDITOR`, in part since CT-2\".")
  BEEP_OLD = ("- Replaces: `NSSound.beep()` in `EditorWindowController.export`'s failure path "
              "(TidyShot/Editor/Window/EditorWindowController.swift:314).\n"
              "- Shape: A `beep` closure on `EditorWindowController.init`.")
  BEEP_NEW = ("- Replaces: `NSSound.beep()` in the editor window (widened by CT-2, design call 12): `export`'s failure "
              "path (TidyShot/Editor/Window/EditorWindowController.swift:314), the beep while another document action "
              "runs (:236), `performUpload`'s when the drawing changed during the call (:280), "
              "`askToSaveBeforeClosing`'s (:464), and `EditorWindow.send`'s when the window's validation refuses a "
              "shortcut (TidyShot/Editor/Window/EditorWindow.swift:45). The refusal itself is the validation's "
              "(`EDPLACE`); `CanvasView`'s two beeps (CanvasView.swift:364, :439) stay.\n"
              "- Shape: A `beep` closure on `EditorWindowController.init`, handed to its `EditorWindow`.")
  SOURCE_OLD = "no line's Completes credit changed."
  SOURCE_NEW = ("no line's Completes credit changed. CT-2 (`docs/superpowers/specs/2026-10-30-tidyshot-editor-seam-design.md`, "
                "section 11) then built `EDITOR`: each of its 73 lines carries its CT-2 verdict, the new seam `EDPLACE` "
                "holds the 8 lines CT-2 deferred and the 30 it marked in part with the window's glue left, and the part "
                "lines also sit under the other seams their marks name (57 new seam slots). The table, the counts and the "
                "last sections were redone by the rules in the summary.")
  SUMMARY = [
      ("- 279 B lines (265 from the catalogue, 14 from tests-A), 41 distinct seams.",
       "- 279 B lines (265 from the catalogue, 14 from tests-A), 42 distinct seams."),
      ("- 225 lines need one seam; 54 need two or more (listed in their own section).",
       "- 186 lines need one seam; 93 need two or more (listed in their own section)."),
      ("- 18 seams unlock three or fewer lines each.", "- 16 seams unlock three or fewer lines each."),
      ("Lines sums to 347 (225 one-seam lines, plus 122 seam slots held by the 54 lines that need two or more); Alone sums "
       "to 225; Completes sums to 279, every B line once. Read down the Completes column for a running total: the first "
       "three seams cover 100 lines, the first ten 173.",
       "Lines sums to 404 (186 one-seam lines, plus 218 seam slots held by the 93 lines that need two or more); Alone sums "
       "to 186; Completes sums to 279, every B line once. Read down the Completes column for a running total: the first "
       "three seams cover 78 lines, the first ten 152."),
  ]
  # Design 11 item 4, Lines / Alone / Completes, and the places it gives.
  ROWS = {"EDITOR": (73, 26, 26), "EDPLACE": (38, 0, 24), "TARGET": (34, 26, 28), "SAVEAS": (14, 9, 11),
          "SCREENS": (12, 6, 8), "EDSAVEAS": (11, 2, 8), "BGPOP": (7, 5, 7), "BEEP": (5, 1, 5), "CLOSESHEET": (4, 1, 3),
          "APPDELEGATE": (2, 1, 2)}
  PLACES = {"EDITOR": 1, "EDPLACE": 2, "TARGET": 3, "EDSAVEAS": 12}

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
  for old, _ in SUMMARY + [(SOURCE_OLD, None), (BEEP_OLD, None)]:
      assert text.count(old) == 1, f"seams.md is not as at dd1231d: {old[:60]}"

  # Parse the table, the sections and their line lists.
  head, rest = text.split("\n## The seams, by lines unlocked\n\n", 1)
  body, tail = rest.split("\n## Lines that need two or more seams at once\n", 1)
  multi_old, tail = tail.split("\n## Seams that unlock three or fewer lines\n", 1)
  three_old, tail = tail.split("\n## A lines that name a seam\n", 1)
  rows = re.findall(r"^\| (\d+) \| ([^|]+) \| `([A-Z]+)` \| (\d+) \| (\d+) \| (\d+) \| (\w+) \|$", head, re.M)
  assert len(rows) == 41
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


  before, _ = counts(seams, [r[2] for r in rows])
  assert before == table_old, "the table matches its lists"
  assert [sum(v[i] for v in before.values()) for i in range(3)] == [347, 225, 279]

  # Items 2 and 3: the EDPLACE row and the joins.
  edplace = sorted(DEFERRED + EDPLACE_PART, key=order_key)
  assert len(edplace) == 38 and set(edplace) <= set(seams["EDITOR"])
  assert set(FULL) | set(DEFERRED) <= set(seams["EDITOR"]) and len(FULL) == 25
  seams["EDPLACE"] = edplace
  slots = len(edplace)
  for seam, keys in JOINS.items():
      for k in keys:
          assert k in seams["EDITOR"] and k not in seams[seam], (seam, k)
          seams[seam].append(k)
          slots += 1
      seams[seam].sort(key=order_key)
  assert slots == 57, slots
  names["EDPLACE"], effort["EDPLACE"] = EDPLACE_ROW

  # Item 4: the counts, the table sorted by Lines (then Alone, then key, as it was).
  first, _ = counts(seams, list(seams))
  order = sorted(seams, key=lambda s: (-first[s][0], -first[s][1], s))
  after, need = counts(seams, order)
  changed = {k for k in need if need[k] != {s for s in seams if s != "EDPLACE" and k in entries.get(s, {})}}
  assert len(order) == 42 and len(need) == 279 and len(changed) == 41
  assert [sum(v[i] for v in after.values()) for i in range(3)] == [404, 186, 279]
  assert sum(1 for k in need if len(need[k]) > 1) == 93
  assert sum(1 for s in order if after[s][0] <= 3) == 16
  running = [sum(after[s][2] for s in order[:n]) for n in (3, 10)]
  assert running == [78, 152], running
  for seam, row in ROWS.items():
      assert after[seam] == row, (seam, after[seam], row)
  for seam, place in PLACES.items():
      assert order.index(seam) + 1 == place, (seam, order.index(seam) + 1)
  assert all(after[s] == before[s] for s in before if s not in ROWS), "only design 11's rows change"

  # The text each line shows, from its first entry (EDITOR's for the 73).
  shown = {}
  for seam in entries:
      for k, (t, _, _) in entries[seam].items():
          shown.setdefault(k, t)


  def also(k, seam):
      others = [s for s in order if s in need[k] and s != seam]
      if not others:
          return ""
      if seam == "EDITOR" or k not in changed:
          return " (also " + ", ".join(f"`{s}`" for s in others) + ")"
      editor = "`EDITOR`, " + ("deferred in CT-2" if k in DEFERRED else "in part since CT-2")
      rest = [f"`{s}`" for s in others if s != "EDITOR"]
      return " (also " + editor + ("; and " + ", ".join(rest) if rest else "") + ")"


  def entry(seam, k):
      t, also_text, notes = entries.get(seam, {}).get(k, (shown[k], "", ""))
      if k in changed:
          also_text = also(k, seam)
      if seam == "EDITOR":
          notes = notes.replace(REPLACED_NOTES.get(k, "\0"), "")
          verdict = "full" if k in FULL else "deferred" if k in DEFERRED else "in part"
          notes += f"; CT-2: {verdict}"
      return f"- `{k}` {t}{also_text}{notes}"


  for k, note in REPLACED_NOTES.items():
      assert entries["EDITOR"][k][2] == note, k

  out = []
  for n, seam in enumerate(order, 1):
      lines_, alone, _ = after[seam]
      bullets = EDPLACE_BULLETS if seam == "EDPLACE" else sections[seam]
      if seam == "EDITOR":
          bullets = bullets + [EDITOR_NOTE]
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
  assert len(old_multi) == 54
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
  for name, s, line in old_three:
      if s in {"CLOSESHEET", "BEEP"}:
          continue
      assert line in "\n".join(three), (s, line)

  text_new = (head_new + "\n## The seams, by lines unlocked\n\n" + body_new
              + "\n## Lines that need two or more seams at once\n" + "\n".join(multi) + "\n"
              + "\n## Seams that unlock three or fewer lines\n" + "\n".join(three) + "\n"
              + "\n## A lines that name a seam\n" + tail)
  text_new = text_new.replace(BEEP_OLD, BEEP_NEW)
  assert text_new.count(BEEP_NEW) == 1
  PATH.write_text(text_new)
  print(f"seams.md: {len(order)} seams, Lines {sum(v[0] for v in after.values())}, "
        f"Alone {sum(v[1] for v in after.values())}, Completes {sum(v[2] for v in after.values())}, "
        f"{slots} new slots, {sum(1 for k in need if len(need[k]) > 1)} lines need two or more seams, "
        f"{sum(1 for s in order if after[s][0] <= 3)} seams unlock three or fewer")
  EOF
  ```
  Expected: `seams.md: 42 seams, Lines 404, Alone 186, Completes 279, 57 new slots, 93 lines need two or more seams, 16 seams unlock three or fewer`.
  Then:
  ```bash
  git diff --stat -- docs/superpowers/notes/2026-10-30-checklist-sweep/seams.md | tail -1
  grep -c "; CT-2: " docs/superpowers/notes/2026-10-30-checklist-sweep/seams.md
  grep -n "^### [0-9]*\. .*(\`\(EDITOR\|EDPLACE\|TARGET\|CAPSRC\|EDSAVEAS\|BEEP\|APPDELEGATE\)\`)" docs/superpowers/notes/2026-10-30-checklist-sweep/seams.md
  ```
  Expected: ` 1 file changed, 376 insertions(+), 301 deletions(-)`; `73`; and
  ```
  62:### 1. Editor presenter factory (`EDITOR`): 73 lines, 26 alone
  147:### 2. Editor window placement (`EDPLACE`): 38 lines, 0 alone
  196:### 3. Value capture target (`TARGET`): 34 lines, 26 alone
  240:### 4. Capture source (engine and selector) (`CAPSRC`): 33 lines, 8 alone
  455:### 12. Editor Save As sheet (`EDSAVEAS`): 11 lines, 2 alone
  666:### 24. Editor export beep (`BEEP`): 5 lines, 1 alone
  761:### 31. Quit reply decision (`APPDELEGATE`): 2 lines, 1 alone
  ```

- [ ] **Step 5: Write the hand-check checklist.** Create `docs/testing/editor-seam-manual-checklist.md`, in the form
  of `docs/testing/coordinator-harness-manual-checklist.md` (when to run it, the checks, the design's calls and the
  plan's decisions to confirm or overrule, observations), with the design's section 9 checks as 1 to 4:
  ```markdown
  # Editor seam manual checklist

  Run after the editor seam phase (`docs/superpowers/specs/2026-10-30-tidyshot-editor-seam-design.md`), and after any
  later change to `EditorPresenting`, `AppEnvironment.makeEditor` and its live closure, `presentEditor`,
  `editorDidClose` or `reviewEditorsBeforeQuit`. The suite now opens every editor through `world.editors`, a
  `FakeEditor` per open, and the coordinator-split, phase-4a, phase-4b, phase-4c, phase-6a, phase-6b, phase-7c and
  small-tweaks checklists mark 65 lines `(suite …)`, 25 in full and 40 in part. The live closure never runs in the suite
  (`AppEnvironment.live()` builds `AppSettings.shared`, the Keychain store and the notifier), so what is left here is
  the real editor window it builds: that it opens, saves, closes and asks at a quit as it did before the seam.

  ## Checks

  - [ ] 1. Annotate from a card and from a Recent Captures row each open the editor at the same size as before. The
    title is the file name for a save-folder capture (with its proxy icon) and `Capture <time>` otherwise. A second
    Annotate on another capture opens a window cascaded 22 pt from the first. Annotate on a capture whose editor is
    open brings that window forward, and no second window opens.
  - [ ] 2. Draw, then ⌘S: the save-folder file shows the edit and the unsaved dot clears. ⌘C posts `Image copied`.
    ⌘U closes the editor, the row uploads, and the link is copied.
  - [ ] 3. ⌘W on a changed editor shows the close sheet. Cancel keeps the editor open; Don't Save closes it. Annotate
    on the same capture then opens a fresh editor. ⌘W on a clean editor closes it at once.
  - [ ] 4. Quit with a changed editor: the sheet appears on it. Cancel keeps TidyShot running; quit again and Don't Save
    quits.

  ## The design's calls, to confirm or overrule

  The design lists them in section 10. Write `confirm` or `overrule` and why; an overrule goes in its built notes.
  - [ ] 1. One seam, `EDITOR`; the window's own screen read and workspace observer (`EditorWindowPlacement`) are a
    second seam, deferred as `EDPLACE`. ______
  - [ ] 2. The protocol is `EditorPresenting`, class-bound, with four members, after `EditorActions` in
    `EditorWindowController.swift`; the conformance is an empty extension at the end of the file. ______
  - [ ] 3. The factory is one `@MainActor` closure, `AppEnvironment.makeEditor`, taking the model, the actions, the
    title, the represented URL and the close callback, so the controller's `onClose` is untouched. ______
  - [ ] 4. The registry becomes `[UUID: any EditorPresenting]`; `reviewEditorsBeforeQuit` stays byte for byte. ______
  - [ ] 5. No presenter type: the fake's `Push` reads the same pure functions the controller does. ______
  - [ ] 6. `FakeEditor` and `FakeEditors` in `Support/EditorFakes.swift`, `world.editors`, `FakeClipboard.pngs` and
    `EditorPixels` are support, not seams. ______
  - [ ] 7. A line naming the window's glue (the dot, the subtitle as shown, greying, key routing, closing) is marked in
    part until `EDPLACE`. ______
  - [ ] 8. The suites: `CoordinatorEditorTests` for opening, pushes and the quit; the new `CoordinatorEditorSaveTests`
    and `CoordinatorEditorUploadTests` for the actions; one test in `CoordinatorOverlayTests` for phase-6a's delete
    sentences. ______
  - [ ] 9. Lines at odds with the code are not reworded; the tests pin the code and each mark says what it pins. Your
    call on the wording: phase-4a's folder change with a bad key (Retry Failed Uploads does nothing for a failed
    replace; the next ⌘U recovers it), "after the retries" in phase-4a's and phase-4b's wrong-key lines (a 403 is not
    retried) and the notice's title `Not uploaded`, phase-6a's "from the card" after an Annotate (the card is closed for
    good, and in upload-only mode ⌘S is Save As…), and phase-7c's flat reopen (only once the first editor has
    closed). ______
  - [ ] 10. The `EDPLACE` design is kept beside the design as
    `docs/superpowers/notes/2026-10-30-editor-seam/edplace-design.md`, and seams.md has its row. ______
  - [ ] 11. Five of the 13 lines read off a constructed controller are marked in part now, through the pushes and the
    coordinator's copy, with `EDPLACE` named for the rest. ______
  - [ ] 12. `BEEP` widens to every beep of the editor window and its `send`; the refusal itself stays the
    validation's (`EDPLACE`). ______
  - [ ] 13. Two lines the judge's draft had in full are in part: the window coming forward on a second Annotate (by hand
    for good) and a restored card's Annotate (the restore reads the screens, `SCREENS`). ______

  ## The plan's decisions, to confirm or overrule

  The plan lists them at its end (`docs/superpowers/plans/2026-10-30-editor-seam.md`, Plan decisions). None changes what
  a user could see. One gives a number other than the design's:
  - [ ] seams.md's table is sorted by Lines, so `TARGET` (34 lines) is third, ahead of `CAPSRC` (33), and the first
    three seams complete 78 lines; the design's section 11 says fourth and 58. Every row's numbers, the three sums and
    the first ten's 152 are the design's. ______

  ## Observations
  Write into the design's built notes: anything above that failed, and each call and decision confirmed or overruled.
  ```
  Then `awk 'length > 120' docs/testing/editor-seam-manual-checklist.md` prints nothing.

- [ ] **Step 6: Run the full suite and the Release build.**
  ```bash
  xcodegen generate && xcodebuild test -project TidyShot.xcodeproj -scheme TidyShot -destination 'platform=macOS' -derivedDataPath .build 2>&1 | grep -E "Test run with|error:|TEST"
  ```
  Expected: `Test run with 2318 tests in 193 suites passed` and `** TEST SUCCEEDED **`, with only the known noise
  (Global Constraints). Nothing in this task touches the code, so a different count means an earlier task's tree
  changed; stop and report it.
  ```bash
  xcodegen generate && xcodebuild -project TidyShot.xcodeproj -scheme TidyShot -configuration Release -derivedDataPath .build-rel build 2>&1 | grep -E "error:|warning:|BUILD"
  ```
  Expected: `** BUILD SUCCEEDED **` and no `error:` or `warning:` line from the compiler or the linker; the two tool lines
  the Global Constraints name (`iOSSimulator: … sharedServiceContextForDeveloperDir:error:` and the
  `appintentsmetadataprocessor` `warning: Metadata extraction skipped`) may print and are not failures (D63).
  ```bash
  git diff --stat main -- project.yml; git diff --stat main -- TidyShot/
  ```
  Expected: nothing for `project.yml`, then
  ```
   TidyShot/App/AppCoordinator+Editor.swift            | 21 ++++++++++-----------
   TidyShot/App/AppCoordinator.swift                   |  4 ++--
   TidyShot/App/AppEnvironment.swift                   | 19 +++++++++++++++++--
   TidyShot/Editor/Window/EditorWindowController.swift | 18 ++++++++++++++++++
   4 files changed, 47 insertions(+), 15 deletions(-)
  ```
  (Task 1's four files only, as the review's built tree has them).

- [ ] **Step 7: The built notes.** The design's section 12 gains one paragraph with the branch's suite line, the
  Release result, the marks made and the seams.md edit; `tests-editor.md`'s header sentence that says the review built
  every entry (:33-34) gains that the tests are built on `editor-seam`, and `lines-editor.md`'s header (:3), which has
  no such sentence, gains one (D61). If Step 6's suite line differs from `Test run with 2318 tests in 193 suites
  passed`, set `SUITE` to the line it printed before running this.
  ```bash
  python3 - <<'EOF'
  from pathlib import Path

  SUITE = "Test run with 2318 tests in 193 suites passed"   # the full suite line of this task's run
  design = Path("docs/superpowers/specs/2026-10-30-tidyshot-editor-seam-design.md")
  text = design.read_text()
  old = "A probe with the fake's two text commits removed failed with 5 issues.\n"
  new = old + (
      "\nBuilt on `editor-seam` from the plan `docs/superpowers/plans/2026-10-30-editor-seam.md`: the full suite "
      f"`{SUITE}` (the baseline's 2272 tests in 191 suites, and 46 tests in two new suite files and two existing "
      "ones) and the Release build "
      "`** BUILD SUCCEEDED **` with no `error:` or `warning:` line from the compiler or the linker. 65 lines carry "
      "marks, 25 in full and 40 in part, and "
      "the 8 deferred lines none. seams.md has section 11's edit, with one difference: sorted by Lines, `TARGET` (34) is "
      "third, ahead of `CAPSRC` (33), so the first three seams complete 78 lines, not 58; every row's numbers, the three "
      "sums and the first ten's 152 are as section 11 gives. The hand checks of section 9 are "
      "`docs/testing/editor-seam-manual-checklist.md`, for Tim.\n")
  assert text.count(old) == 1 and text.endswith(old)
  design.write_text(text.replace(old, new))

  tests = Path("docs/superpowers/notes/2026-10-30-editor-seam/tests-editor.md")
  text = tests.read_text()
  old = "and all of them passed (design section 12);"
  new = ("and all of them passed (design section 12), and they are built on `editor-seam`\n(plan "
         "`docs/superpowers/plans/2026-10-30-editor-seam.md`);")
  assert text.count(old) == 1
  tests.write_text(text.replace(old, new))

  lines = Path("docs/superpowers/notes/2026-10-30-editor-seam/lines-editor.md")
  text = lines.read_text()
  old = "The tests are in `tests-editor.md` in this folder.\n"
  new = ("The tests are in `tests-editor.md` in this folder; they are built on `editor-seam` (plan "
         "`docs/superpowers/plans/2026-10-30-editor-seam.md`), and the 65 lines they cover carry their marks, whose "
         "continuation lines put a checklist's later lines below the current lines given here.\n")
  assert text.count(old) == 1
  lines.write_text(text.replace(old, new))
  print("notes edited")
  EOF
  ```
  Expected: `notes edited`.

- [ ] **Step 8: Check the whole change.**
  ```bash
  git status --short
  ```
  Expected, in any order, exactly these 13 paths: ` M` for
  `docs/superpowers/notes/2026-10-30-checklist-sweep/seams.md`, `docs/superpowers/notes/2026-10-30-editor-seam/lines-editor.md`,
  `docs/superpowers/notes/2026-10-30-editor-seam/tests-editor.md`, `docs/superpowers/specs/2026-10-30-tidyshot-editor-seam-design.md`,
  `docs/testing/coordinator-split-manual-checklist.md`, `docs/testing/phase-4a-manual-checklist.md`,
  `docs/testing/phase-4b-manual-checklist.md`, `docs/testing/phase-4c-manual-checklist.md`,
  `docs/testing/phase-6a-manual-checklist.md`, `docs/testing/phase-6b-manual-checklist.md`,
  `docs/testing/phase-7c-manual-checklist.md` and `docs/testing/small-tweaks-manual-checklist.md`, and `??` for
  `docs/testing/editor-seam-manual-checklist.md`. Nothing under `TidyShot/`, `TidyShotTests/` or `project.yml`.

- [ ] **Step 9: Commit.**
  ```bash
  git add docs/testing/coordinator-split-manual-checklist.md docs/testing/phase-4a-manual-checklist.md docs/testing/phase-4b-manual-checklist.md docs/testing/phase-4c-manual-checklist.md docs/testing/phase-6a-manual-checklist.md docs/testing/phase-6b-manual-checklist.md docs/testing/phase-7c-manual-checklist.md docs/testing/small-tweaks-manual-checklist.md docs/testing/editor-seam-manual-checklist.md docs/superpowers/notes/2026-10-30-checklist-sweep/seams.md docs/superpowers/notes/2026-10-30-editor-seam/lines-editor.md docs/superpowers/notes/2026-10-30-editor-seam/tests-editor.md docs/superpowers/specs/2026-10-30-tidyshot-editor-seam-design.md
  git commit -m "docs: editor seam marks, seams.md, the hand-check checklist and close-out"
  ```
  Expected: `13 files changed, 636 insertions(+), 313 deletions(-)` and
  `create mode 100644 docs/testing/editor-seam-manual-checklist.md`. No attribution lines, no session URL; do not
  push. The task's report says that no hand check was run (they are Tim's, in the new checklist).

## Test totals

| After | Tests added | Effort | Focused run after | Suite line after |
|---|---|---|---|---|
| Baseline |  |  |  | `Test run with 2272 tests in 191 suites passed` (a079a6f, dd1231d) |
| Task 1 | 2 (`CoordinatorEditorTests` +2) | S 2 | `CoordinatorEditorTests` 4 | `Test run with 2274 tests in 191 suites passed` |
| Task 2 | 8 (`CoordinatorEditorSaveTests` 8, new) | S 2, M 6 (2 param.) | `CoordinatorEditorSaveTests` 8 | `Test run with 2282 tests in 192 suites passed` |
| Task 3 | 9 (`CoordinatorEditorSaveTests` +9: 5 Save As…, 4 Copy) | S 7, M 2 (2 param.) | `CoordinatorEditorSaveTests` 17 | `Test run with 2291 tests in 192 suites passed` |
| Task 4 | 9 (`CoordinatorEditorUploadTests` 9, new) | S 2, M 6, L 1 | `CoordinatorEditorUploadTests` 9 | `Test run with 2300 tests in 193 suites passed` |
| Task 5 | 5 (`CoordinatorEditorUploadTests` +5: 4 failed replaces and the folder change, 1 drag copy) | M 1, L 4 | `CoordinatorEditorUploadTests` 14 | `Test run with 2305 tests in 193 suites passed` |
| Task 6 | 8 (`CoordinatorEditorTests` +8: 5 opening, 3 card) | S 3, M 5 (3 param.) | `CoordinatorEditorTests` 12 | `Test run with 2313 tests in 193 suites passed` |
| Task 7 | 5 (`CoordinatorEditorTests` +4, `CoordinatorOverlayTests` +1) | S 1, M 4 | `CoordinatorEditorTests` 16, `CoordinatorOverlayTests` 2 | `Test run with 2318 tests in 193 suites passed` |
| Task 8 | 0 |  |  | `Test run with 2318 tests in 193 suites passed` |

46 tests in all, 2 + 8 + 9 + 9 + 5 + 8 + 5: per suite 17 (`CoordinatorEditorSaveTests`), 14 (`CoordinatorEditorUploadTests`), 14 (`CoordinatorEditorTests`), 1 (`CoordinatorOverlayTests`), as the catalogue's section 9 has them; effort S 17, M 24, L 5. Each count is test functions: a parameterized test is one, whatever its arguments. The design's review ran the same 46 in a scratch tree with two probes more, `Test run with 2320 tests in 195 suites passed`: 2272 + 46 + 2, in 191 + 4 (the two new suites and the two scratch suites); the probes and the scratch suites are not in this plan (D3).

## Plan decisions

Where the plan departs from the design or the catalogue, or settles a detail they leave open, with the reason. Items 1 to 14 frame the plan. Items 15 to 62 are the task writers' decisions, each named with its task, in task order. Items 63 to 69 are the assembly's, 70 to 75 the plan review's and 76 the execution's (Task 1): the noise lines, and where an Interfaces, Tests or run line was brought into line with the steps. Items 70 to 75 are the plan review's. Task 8 writes a summary into the design's section 12.

1. **Eight tasks, as the brief fixes them.** Task 1 is the only one that changes `TidyShot/`, so the Release build runs there and again at the end of Task 8. Each of Tasks 2 to 7 adds tests to one catalogue section or two, so a task never holds more than nine tests: Save over the file (8); Save As… and Copy (5 + 4); Upload over a link and the first upload (9); failed replaces and the folder change, and the drag copy (4 + 1); the remaining opening tests and the card (5 + 3); what the editor hears, and the overlay test (4 + 1). All 46 catalogue tests are placed, each once: the brief's split leaves none out, and the counts hold against the catalogue's section 9 and the built files (17 / 14 / 14 / 1, effort S 17, M 24, L 5, seven parameterized).
2. **The two first tests, in Task 1.** `annotateOnACaptureWhoseEditorIsOpenBringsItForwardAndBuildsNoSecond` and `quitAsksEachChangedEditorCancelStopsItDontSaveLetsItGo` land with the seam because between them they reach everything the coordinator touches through it: the build through `makeEditor`, the registry and its identity check, `present()` on open and again on a second Annotate, the first push, the card's close, `hasUnsavedChanges`, and the quit review's `present()` and `askToSaveBeforeClosing()` over a held sheet gated by `TaskWatch`, Cancel and then Don't Save. A seam that built the wrong object, dropped the registry entry or reordered the review fails one of them. The quit test is the catalogue's last `CoordinatorEditorTests` entry, so that file's order is the tasks' order (the 2 existing tests, Task 1's 2, Task 6's 8, Task 7's 4), not the catalogue's; the Save and Upload files keep the catalogue's order.
3. **What is left out of the built tree.** The review's built `CoordinatorEditorTests.swift` holds two probes, `quitReviewSaveAnswerWritesThePendingFile` and `probeATextBeingTypedIsSavedAndTheEditorIsClean`, which are the review's and not catalogue tests; so are its two scratch suites `CoordinatorEditorExtraTests` and `CoordinatorEditorExtra2Tests` as files (their 39 tests move to the catalogue's suites) and their "Review-only" headers. The built `CoordinatorEditorExtraTests` declares a `nonisolated enum Mode` that no test uses (`withTheOverlayOff…(mode:)` takes `AfterCaptureAction.allCases`); it is dropped. So the suite reads 2318 in 193, not the review's 2320 in 195. The brief says the built `CoordinatorEditorTests.swift` holds three catalogue tests; it holds two (`quitAsks…` and `anEditorOpenedDuringAHeldUpload…`), and `annotateOnACaptureWhoseEditorIsOpen…` is in the built `CoordinatorEditorExtra2Tests`. The totals are unchanged: 3 + 2 + 2 + 13 + 26 = 46.
4. **The helpers' homes.** Each suite keeps its own helpers, as `CoordinatorUploadTests` and `CoordinatorDeleteTests` keep their own `addPendingImage` (CoordinatorUploadTests.swift:40-51, CoordinatorDeleteTests.swift:54-64). Which helpers a suite has is the catalogue's 2.2 table, with D5's changes; each helper's body and signature is the built one (the copies in the review's built tree, in its two scratch suites and its Save, Upload and Editor files, are identical where they overlap). A suite's helpers land whole with its first task: `CoordinatorEditorTests`' in Task 1, `CoordinatorEditorSaveTests`' in Task 2, `CoordinatorEditorUploadTests`' in Task 4; `CoordinatorOverlayTests` gets only `destination`, in Task 7. In the two new files the helpers sit between `init` and the first test, in the 2.2 table's order. In `CoordinatorEditorTests` they go after the existing `var link` (:18) and before `nonisolated enum Kept` (:20), so the suite's members stay together above its tests; its `key`, `destination` and `link` (:11, :17, :18) are already there and do not change. An argument type sits directly before its test, as `Kept` does (:20-28).
5. **Where the built helpers differ from the catalogue's 2.2, the built ones are kept.** `var all: Set<EditorAction> { Set(EditorAction.allCases) }` is not in 2.2's list but every built suite has it and tests in all three call it (catalogue 2.3 names the set `all`), so all three suites get it. `exists(_:)` is "no" for `CoordinatorEditorTests` in 2.2's table, but two of its tests call it (`anUploadedUploadOnlyCardsCopyImageAndAnnotateReadTheDragCopy`, `aPrunedCaptureTellsItsOpenEditorItWasDeleted`), so it gets it. `addText` throws (it is called as `try addText(…)`), where 2.2 gives `-> TextBox`. `expected(_ editor: FakeEditor) async throws -> CGImage` is the function form of 2.2's `expected`; only two tests call it (`saveWithACropWritesTheCroppedSizeAtTheCapturesScaleAndReopensCropped(scale:)` and `copyWithACropPutsTheCroppedImageAtPointSizeAndSaysImageCopied`), and the other bodies take `try #require(await editor.export()).image` inline as built. 2.2 lists it for all three suites, but no test in the other two calls it, so it goes in `CoordinatorEditorSaveTests` alone, and no body changes. That rule is for `expected` only: every other helper 2.2 gives a suite is defined there even where none of its tests calls it (D22).
6. **`EditorPixels` as built.** Its members are catalogue 2.1's, with the built file's signatures; two of them throw where 2.1 does not say so: `pixel(_ png: Data, x: Int, y: Int) throws -> [Int]` and `isBlue(png: Data) throws -> Bool` (both decode first). `worldRed()` is `@MainActor` because `CoordinatorWorld.image` is.
7. **`EditorFakes.swift` is design 3.1's block exactly**; the built file is byte-identical to it. `FakeClipboard.pngs` and the `CoordinatorWorld` additions are design 3.2 and 3.3 as built.
8. **`CoordinatorEditorTests` imports `CoreGraphics`.** At dd1231d the file imports `Foundation`, `Testing` and `TidyShot` (:1-3). Task 1 adds `import CoreGraphics` with them: its own helpers name `CGFloat`, `CGRect` and `CGPoint` (`addSavedImage`, `crop`, `addText`), and so do Task 6's moved bodies (`anEditorOpensWithTheStoredSpotlightShapeAndCounterSize`, `aCaptureFromBefore4cOpensEditsAndSavesAsBefore`), as the two new files and the scratch suites import it. Foundation alone would supply those types (the review's built `CoordinatorEditorTests` used `CGPoint` without the import), so the import is for consistency with the other suites rather than required; the writers of Tasks 1 and 6 both confirmed it. No test file at dd1231d names `CGImage` without importing `CoreGraphics`, `AppKit`, `ImageIO` or `CoreImage`.
9. **Two doc-only edits the built tree does not have.** The review's built tree keeps `CoordinatorWorld.swift`'s header comment (:11-17) as it is, where design 3.3 says it adds the editors; and keeps `CoordinatorEditorTests.swift`'s header (:5-7), which still says no test reaches the editor's presenting, where design 4 and the catalogue's section 5 say it is reworded. The plan makes both edits. They are comments, so the built run stands for them.
10. **Every test's doc comment is the plan's.** The 39 tests from the scratch suites have none, and the 7 others carry the review's wording ("Built test 1 of design-minimal plus the catalogue's added asserts"; "Built test 4 of design-minimal") and name lines by the e011d2f number only. Each is written from the entry's Covers and `lines-editor.md`, in one form for every task: the lines first, each as its catalogue key with the current line in brackets and its verdict (`/// phase-4a:94 (:143), in part; small-tweaks:18 (:21).`), then the rule the test pins in a sentence or two, then for each in-part line `Stays:` with that line's Stays from `lines-editor.md`, naming the other seam (`EDPLACE`, `EDSAVEAS`, `CLOSESHEET`, `BEEP`, `SAVEAS`, `SCREENS`, `PINS`, `TARGET`, `QASTACK`, `EDDEFAULTS`, `BGPOP`, `APPDELEGATE`) or "by hand" with the three wording rules of design 6. A test that calls `editor.actions.*` directly to reach a check the window's validation would block says so (design 3.4).
11. **Test bodies are the built ones.** A body moved from a scratch suite keeps its statements; only helper names and the suite's own members may differ, and with D4 and D5 none does. Where a writer finds a body and its catalogue entry at odds, the body stands when the green run depended on it, and the difference is a decision under its task below.
12. **The overlay test's suite.** The catalogue's section 1 leaves the placement of `aCardWhoseDeleteIsUnderWayIsNotRestorable` and its `destination` property to the plan; it goes in `CoordinatorOverlayTests` (catalogue 6), whose only member today is `world` (CoordinatorOverlayTests.swift:6-13), with `destination` added as 2.2 gives it.
13. **Focused runs count each suite's existing tests.** `CoordinatorEditorTests` has 2 at dd1231d (`loadImageReadsTheLocalFileOrDownloadsTheObject(record:)` :35, `annotateOnAMovedPrePhase3FileSaysCouldNotOpenAndOpensNoEditor` :75) and `CoordinatorOverlayTests` 1 (`aRelaunchForgetsClosedCardsButKeepsTheirRecords` :16); the two new suites start empty.
14. **The marks go on the lines as they read at the branch head, found by text.** The checklists have moved since e011d2f (PR #28 and CT-1 added marks), so Task 8's script names each line by its catalogue key and an anchor that occurs once in its checklist, as CT-1's Task 12 did; the 8 deferred lines get no mark (design 6).
15. **Task 1: `EditorFakes.swift`'s line references.** The file is design 3.1's block exactly (D7), so its comments keep the `EditorWindowController.swift` line numbers at a079a6f (:165-176, :188-228, :247-254, :268-296, :301-317, :460-492), which sit 16 lines further down once this task inserts the protocol at :33.
16. **Task 1: the annotate test waits for the opening to end.** `annotateOnACaptureWhoseEditorIsOpenBringsItForwardAndBuildsNoSecond` keeps the built `try await eventually { coordinator.openingEditorIDs.isEmpty }` where the catalogue asserts it straight after the open (tests-editor.md:1276-1277); it asserts the same thing, since `loadAndPresentEditor`'s `defer` removes the ID right after `presentEditor` returns (AppCoordinator+Editor.swift:36).
17. **Task 1: the two tests' doc comments are new** in D10's form, written from `lines-editor.md` and the catalogue's Covers: the annotate test names phase-4a:39 (:43), in part, with that line's Stays, and the quit test names phase-4a:155 (:223), in part, with "Stays: the sheet itself (`CLOSESHEET`); the real quit's reply (`APPDELEGATE`)."
18. **Task 1: comments name members where the code moves in the same task.** The annotate test's Stays says "`present()`'s own body in `EditorWindowController`" where `lines-editor.md` cites EditorWindowController.swift:147-152, and `settledEdit`'s comment names `replaceThumbnail(for:from:editedAt:)`, since `presentEditor` shrinks in this task; no body changes.
19. **Task 1: `CoordinatorEditorTests`' helpers** go between `var link` (:18) and `nonisolated enum Kept` (:20), the properties `all`, `green` and `background` first and then the functions in catalogue 2.2's table order (`publicURL`, `openedEditor`, `reopenedEditor`, `settledEdit`, `addSavedImage`, `addPendingImage`, `desktop`, `pendingURL`, `addUploadOnly`, `isUploaded`, `title(of:)`, `exists`, `crop`, `addText`), with no `expected` (D5) and with the built bodies, which are the same in both scratch suites.
20. **Task 1: the headers.** The reworded `CoordinatorEditorTests` header describes the suite as it stands after Task 7 (opening, the card, what an open editor hears, the quit review), so Tasks 6 and 7 do not edit it again, and it keeps the old header's point that presenting goes through `environment.makeEditor`, which builds a `FakeEditor` and no window; `CoordinatorWorld`'s header adds "the editors the coordinator opens (`editors`; no window is built)" to its list (D9).
21. **Task 2: `key` sits with the helpers.** In the new file `let key = "s/SHOT.png"` sits after `init` with the other helpers, as D4 places them, where the built suites declare it before `init`; some helpers gain short doc comments, and every helper's body and signature is the built one.
22. **Tasks 2 and 4: a new suite gets every helper 2.2 gives it.** All of `CoordinatorEditorSaveTests`' helpers land in Task 2, including `desktop` and `addUploadOnly` (only Task 3's tests call them) and `addPendingImage`, `pendingURL` and `isUploaded` (no test in the suite calls them), and `CoordinatorEditorUploadTests` gets 2.2's Upload column plus `all`, without `green`, `background` or `expected`, and keeps `addPendingImage`, `desktop` and `addUploadOnly` though none of its 14 tests calls the last two; the files follow 2.2 and the Interfaces lines, D5's rule that a helper is defined only where a test calls it applies to `expected` alone, and Swift gives no unused-member warning, so neither the suite nor the Release build is affected.
23. **Task 2: the locked-file test keeps the built body.** `saveOverALockedFileSaysNotSavedAndPutsTheEditOnTheClipboard` checks only `editedAt == nil` on the record where the catalogue also asks that `thumbnailFileName` be unchanged, and registers the `defer` that clears the immutable flag right after the lock rather than right after `world.removeAll()`, where it still runs before `removeAll()`, as the catalogue requires.
24. **Task 2: the text, ellipse and crop test keeps the built body.** `saveWithTextEllipseAndCropWritesAllThreeIntoTheSameFile` checks the record's `pixelWidth == 320` but not `pixelHeight == 160`, nor that the folder holds only `["Shot.png"]`; the line stays full, since the decoded file's 320 by 160 size and its pixels match the editor's render.
25. **Task 2: the background Save test keeps the built body.** `saveWithABackgroundWritesTheComposedCanvasAndReopensFlat` writes its own red 4 by 2 PNG at scale 1 and its own record with a `<id>.png` thumbnail, where the catalogue says `addSavedImage` plus a thumbnail (`addSavedImage` has no thumbnail parameter), and waits for the edit's thumbnail name with an inline `eventually` rather than `settledEdit`, which is the same wait.
26. **Task 2: two doc comments replaced and widened.** The review's comments on `saveWritesOverTheSaveFolderFileAndUploadsNothing` and `saveWithACropWritesTheCroppedSize…(scale:)` are replaced in D10's form (the other six had none), and the first now also names small-tweaks:18 (:21), a full line whose Save half it pins (`CoordinatorEditorUploadTests.annotateTheNewestCard…` pins the rest), and phase-7c:170 (:213), in part, which Covers and `lines-editor.md` list and the review's comment left out.
27. **Task 3: bodies as built, comments replaced.** The nine bodies are the built ones and every doc comment is in D10's form; the one review comment, on `copyWithACropPutsTheCroppedImageAtPointSizeAndSaysImageCopied`, named only e011d2f numbers and no Stays, and now reads phase-4b:77 (:105); phase-4b:92 (:132), in part, with that line's Stays (`EDPLACE`).
28. **Task 3: the crop copy test reads every assert after both copies,** the alternative the catalogue allows (tests-editor.md:722-723), and keeps the built test's repeated `clipboardOwner == Owner(recordID: id, changeCount: 1)` and its `copies.first` and `copies.last` checks beside the whole-array check, redundant but in the green run.
29. **Task 3: `saveAsOntoItsOwnFileIsASave(uploaded:)` waits inline** with `eventually` on `thumbnailFileName == thumbnails.fileName(for: id, editedAt: world.date)`, as built, rather than through `settledEdit`, whose condition is the same.
30. **Task 3: the Save As crop test keeps the built form.** `saveAsWithACropWritesACroppedCopyAndLeavesTheCaptureAlone` keeps `#expect(await editor.saveAs(to: url))`, a record with the default id and an inline `let expected = try #require(await editor.export()).image.image`, where the catalogue has `let saved`, `CaptureRecord(id:, …)` and the `expected` helper; the local constant shadows the helper, which compiled and passed as built.
31. **Task 3: two catalogue asserts are met in another form** by the built code, which is kept: in `saveAsElsewhereWritesA144DPICopyAndLeavesTheCaptureAlone` "the record's fileURL unchanged" is covered by `coordinator.history.record(id: id) == record`, and in `aSaveOrSaveAsTakesTheClipboardOnlyWhileItHoldsTheCapture` with `userCopied == false` `isBlue(png:)` of `pngs[1]` is covered by `isBlue(png: written)` and `pngs[1] == written`.
32. **Task 3: calls that are not past the window's validation.** `editor.actions.saveAsSuggestion()` (two Save As tests) and `editor.actions.objectClipboard.copy` (the crop copy test) do not bypass the window's validation (design 3.4), so their doc comments say what each call stands for (what the panel reads when it opens; the canvas's ⌘C with an object selected, EditorWindowController.swift:75) instead of D10's sentence about such calls.
33. **Task 4: the header is the catalogue's section-4 header in full** ("…the window's close is the fake's (`closesWindow`), the controller's `performUpload` does not run."), not the built file's one-line first sentence; it is a comment, so the built run stands for it.
34. **Task 4: `uploadWritesTheFileFirstThenReplacesTheLinksObject` keeps the built order**: it checks the outcome, `isClosed`, the registry entry gone and the model clean right after `upload()` returns and takes `expected` as soon as the held PUT shows, before the held checks, where the catalogue lists `expected` after them, and builds its record without an explicit `id:`; the assertions are the same.
35. **Task 4: the second upload waits on `isUploading`.** `anUploadAfterTheCapturesOwnClosesAtOnceAndEndsWithTheLinkCopied` waits after the release with `eventually { record?.isUploading == false }`, not the catalogue's `eventually { isUploaded }`, because the record is already `.uploaded` from the capture's own upload, so only the `isUploading` wait sees the second PUT land (design 5's rule for a held PUT).
36. **Task 4: the counter is read from the annotation.** `anUploadedCaptureReopensFlatWithItsMarksInThePixels` reads the counter's number, diameter and centre from the made annotation's `counterMark` (Annotation.swift:121), not from the document's `.counter` as the catalogue words it; the values checked are the same.
37. **Task 4: a qualified `.none`.** `annotateTheNewestCard…` compares the upload state with `CaptureRecord.UploadState.none`, not the catalogue's bare `.none`, which against an Optional would mean `Optional.none`.
38. **Task 4: one inline comment reworded.** `withNoDestinationSaveTakesTheClipboardAndUploadIsRefused` keeps every built statement, but its one inline comment now reads "A second box over the first, so the document is unsaved again before the Upload." (the plain-prose rule).
39. **Task 5: after the relaunch, the pending path is read through `relaunched`.** The built `aFailedReplaceOfAnUploadOnlyCaptureKeepsPendingAcrossARelaunchUntilTheNextUpload` read it through the first coordinator, which design 5's relaunch rule bars; the path is the same file, since both coordinators build `PendingFileStore(nextTo:)` over the world's one `history.json` (AppCoordinator.swift:280).
40. **Task 5: the relaunch test waits with `settledEdit`** before the relaunch, where the built body and the catalogue waited for `thumbnailFileName != nil`, as design 5's rule says ("the edit's thumbnail named"); the record has no thumbnail before the edit and only `replaceThumbnail` names one, under `fileName(for: id, editedAt: environment.now())` (+Editor:212-217, :249-269), so the green run's wait already ended on that name, and the changed block passed in a scratch tree.
41. **Task 5: the drag-copy upload test stops at the second Annotate.** `uploadOfAnUploadOnlyCaptureRemovesItsDragCopyAndEveryReadGivesTheEdit` keeps the built body, which ends there where the catalogue's step 5 adds a second Copy Image giving a blue `pngs.last`; the Copy Image read is pinned once, while the PUT is held (step 3).
42. **Task 5: the folder-change test keeps the built checks**: `aFailedReplaceAfterAFolderChangeKeepsTheEditInPendingUntilTheNextUpload` checks only `editor.model.base.width == 4` where the catalogue asks for the decoded size 4 by 2, and leaves the first `upload()` outcome unasserted (`_ =`), which the catalogue's Asserts do not list either.
43. **Task 5: the five doc comments are new** in D10's form (the review's relaunch comment named only e011d2f numbers): those of `aFailedReplaceAfterAFolderChange…` and `uploadOfAnUploadOnlyCapture…RemovesItsDragCopy…` say the edit is a drawn box, not the line's Redact or arrow (design 5: no effect is committed), and that of `aNewSaveFolderReaches…` says the fake's `save()` skips the window's validation, so the refusal it pins is the coordinator's own check (design 3.4).
44. **Task 6: the upload-only open test builds its record inline.** `anUploadedUploadOnlyCaptureOpensFromItsObjectAndOfflineOpensNone` records a 6 by 3 capture with `downloadedData` and `dataDownloadFailures` set in one `withLock`, as built, where the catalogue (tests-editor.md:1290) says `addUploadOnly`, whose 4 by 2 record and object would not let the size tell the object apart.
45. **Task 6: the pre-4c test keeps the built unwraps.** `aCaptureFromBefore4cOpensEditsAndSavesAsBefore` unwraps its two annotations with `try #require(model.makeAnnotation(…))` where the catalogue writes `makeAnnotation(…)!` (tests-editor.md:1384-1385), and takes the export inline after the save, not through the catalogue's `expected` helper (D5).
46. **Task 6: the card's Copy Image reads the record after the upload.** `anUploadedUploadOnlyCardsCopyImageAndAnnotateReadTheDragCopy` passes `current`, the record as it reads after the upload with `fileURL == nil`, to `imageData(of:downloadTitle:)`, where the catalogue's step 3 (tests-editor.md:1512) says `record`, the pre-upload record with its pending `fileURL`; the step pins the read after the upload.
47. **Task 6: the eight doc comments are new** in D10's form, each line as key and current line checked against `docs/testing` at dd1231d (phase-4a:49 (:59), phase-4a:52 (:65), phase-4c:201 (:273), phase-4c:214 (:296), phase-7c:187 (:230), phase-6a:131 (:133), phase-6a:152 (:155), phase-6a:158 (:161), coordinator-split:44 (:44), phase-6a:164 (:172), phase-6a:198 (:210)), each in-part line's Stays as `lines-editor.md` gives it, and phase-4a:52, a full line, with its `TARGET` note in the comment's prose rather than as a Stays.
48. **Task 7: the held-upload test keeps the built body.** `anEditorOpenedDuringAHeldUploadHearsUploadingAndGetsSaveAndUploadBack` builds its save-folder record inline (`CaptureRecord(fileURL:…, uploadState: .uploading(fraction: 0), byteCount:)`, no `objectLocation`) instead of calling `addSavedImage(uploadState:)`, and ends on `eventually { isUploaded(coordinator, id) }` rather than design 5's `isUploading == false`, the same check, since `handle(.uploaded)` removes the id from `uploadingIDs` (+Upload:636) in the same synchronous call that sets `.uploaded` (+Upload:657).
49. **Task 7: the delete-asking test asserts what the built body asserts.** `anEditorOpenedWhileADeleteAsksHearsItAndRefusesSave` has no `editor.representedURL == nil`, no `title.hasPrefix("Capture ")`, no check of the refusal's `Not saved` title, no `hasUnsavedChanges` after the refused Save and no last-push `available == [.copy, .saveAs]` after Yes (tests-editor.md:1603); the green run was of the built body, and the refusal title and the unsaved state are asserted in `aDeleteAskedThenCancelledThenConfirmedReachesTheOpenEditor`.
50. **Task 7: the confirmed delete is awaited directly.** In `aDeleteAskedThenCancelledThenConfirmedReachesTheOpenEditor` the second delete's confirm is not held, since `FakeConfirm.answer(_:)` sets `holds = false` (CoordinatorFakes.swift:215-218), so design 5's `TaskWatch` gate applies to the first delete only, which is gated and cancelled in a `defer`.
51. **Task 7: the overlay test builds its pending recording inline,** as built, since `CoordinatorOverlayTests` has no `addPendingRecording` (that helper is `CoordinatorDeleteTests`') and catalogue 2.2 gives the suite only `destination`, which sits after `init` with a blank line on each side, as `CoordinatorEditorTests` keeps its own (CoordinatorEditorTests.swift:13-17); the suite's header comment (CoordinatorOverlayTests.swift:5) is unchanged.
52. **Task 7: doc comments in D10's form.** The review's comment on `anEditorOpenedDuringAHeldUpload…` is replaced and the other four bodies get new ones, each in-part line with its Stays from `lines-editor.md` (the phase-6a:158 test is full together with `annotateFromACardOrRecentCapturesLeavesNothingToRestore` and has none), and the three tests whose `save()` or `upload(asNew:)` reach a write-time refusal say the `FakeEditor` helper calls `editor.actions` past the window's validation (design 3.4).
53. **Task 7: three long statements stay as built** (D11): the two `addSavedImage(…)` calls and the `CaptureRecord(…, mediaKind: .video,` continuation line pass 120 characters, and the task's length check applies only to `///` lines and counts characters, not bytes.
54. **Task 8: the marks name the existing tests that pin a part of each line,** as CT-1's D13 did, taken from the checklist sweep's per-line evidence (its Split, Rule, Plan and Decision test names), because `lines-editor.md` names an existing test for only three lines (coordinator-split:44, phase-6a:164, :198); each name was checked to exist at dd1231d and the script checks it again, with three departures: `EditorClipboardTests.replacesWhenStillOriginal` and `.leavesWhenUserCopiedSomethingElse` also go on phase-4a:116 and :118, which pin the same rule as :115 and :117, `EditorToolbarTests.makeEditor` is left out as a helper, and `EditorUploadPlanTests.retryOfInterruptedReplaceReusesKey` is left off phase-4a:132, since the catalogue's section 8 (tests-editor.md:1745) says it holds only for an interrupted replace.
55. **Task 8: full marks are design 6's plain `(suite: …)` form** with no stand-in text; a stand-in ("Quick Look is the file's decode", "the link … is the PUT body", "`sips` is the decode and the DPI read", "Preview is the `pngs` decode") is named only in a part mark, after the by-hand items, and the test lists keep CT-1's `.test` shorthand without parameter labels, since the script checks `func <name>(`.
56. **Task 8: `TARGET` is third in seams.md's table.** The table is sorted by Lines (design 11, seams.md:9-12), so `TARGET` (34 lines) sorts ahead of `CAPSRC` (33) and the first three seams complete 26 + 24 + 28 = 78 lines, where design 11 item 4 says "fourth" and 58, which holds only with `CAPSRC` above `TARGET`; the script asserts third and 78, every row's Lines, Alone and Completes, the three sums (404, 186, 279), 93, 16 and the first ten's 152 are as the design gives, and the spec's section 12 line records the difference.
57. **Task 8: the `EDPLACE` row** is named "Editor window placement" (design 11 item 2) with effort S, a judgement from its size (one file and one init argument, as `CLOSESHEET` and `EDSAVEAS` are S), and its section's Replaces, Shape, Live and Note come from `edplace-design.md` 2.1, checked against EditorWindowController.swift at dd1231d (:103-106, :123, :321-322, :500) and EditorToolbarTests.swift:54-66.
58. **Task 8: seams.md's layout after the edit**: the sections are reordered and renumbered to match the re-sorted table; only the 41 lines whose seams changed get their "(also …)" notes regenerated, in table order, with the `EDITOR` item in another seam reading "`EDITOR`, in part since CT-2" (or "deferred in CT-2" for phase-4a:107 under `BEEP` and the 8 under `EDPLACE`) then "; and" and the rest; `EDITOR` entries end "; CT-2: full|in part|deferred" after their kept notes; `EDITOR`'s section gains one bullet explaining the verdicts; the `TMPDIRS` section's trailing prose is kept; the last two sections' line texts are cut at 39 and 47 characters, which reproduces every existing entry; and multi-seam groups are ordered by count, then by table position (the old section had one group out of that order, `TMPDIRS` + `MUTESTEPS`).
59. **Task 8: `BEEP` keeps its name and key** ("Editor export beep") while its Replaces and Shape lines widen to every editor-window beep (EditorWindowController.swift:236, :280, :314, :464; EditorWindow.swift:45; design call 12), since the design widens the row but does not rename it.
60. **Task 8: the marks script asserts more than CT-1's did**: 65 entries, 25 full and 40 part; the per-checklist counts of the Files list; that each anchor's line starts an item; no `(obsolete: ` note on a marked item; and that the 8 deferred lines, listed by anchor in a `DEFERRED` table, stay unmarked after the run; it runs as `python3 - . <<'EOF'` from the repository root.
61. **Task 8: the built notes.** `lines-editor.md`'s header has no sentence saying the review built the tests, so one is added at the end of its first paragraph (:3), saying the tests are built on `editor-seam` and that the marks' continuation lines push later checklist lines below the "current line" numbers it gives; `tests-editor.md`'s sentence at :33-34 gains "and they are built on `editor-seam` (plan …)"; and the spec's section 12 gains one paragraph with the suite line (a `SUITE` variable the implementer sets to the run's line if it differs), the Release result, the 65 marks and the seams.md edit with D56's difference.
62. **Task 8: the hand-check checklist** `docs/testing/editor-seam-manual-checklist.md` follows the coordinator-harness checklist's form (when to run it, design 9's four checks, the design's 13 calls of section 10 to confirm or overrule, and the plan's decisions), the calls carry no suite marks, and its decisions section names D56 by its content rather than its number.
63. **The known noise names two tool lines (Global Constraints; Tasks 1 to 8).** Every `xcodebuild` run on this machine prints `xcodebuild[…] iOSSimulator: [SimServiceContext sharedServiceContextForDeveloperDir:error:] returned nil … CoreSimulator is out of date …`, which the suite command's `error:` filter lets through, and a Release build may print `appintentsmetadataprocessor[…] warning: Metadata extraction skipped, no AppIntents.framework dependency found`; the tree at dd1231d prints both and so did the review's runs, so the Global Constraints' noise list and the Release check name them, every task's run step treats any other `error:` or `warning:` line as a failure, and Task 8's Release step says the same as Task 1's.
64. **The Produces lists of Tasks 1 and 4 drop `expected`.** Both named it among their suites' helpers while their signature blocks and D5 leave it out (only `CoordinatorEditorSaveTests` defines it), so the names lists now match the blocks and the steps, and no step changed.
65. **Task 4's runs expect `** TEST SUCCEEDED **`.** The task's two run steps said `** TEST EXECUTE SUCCEEDED **`, which is what `xcodebuild test-without-building` prints; `xcodebuild test`, the plan's command, ends `** TEST SUCCEEDED **` (the review's full runs), as every other task says.
66. **Task 8's Tests line follows D56**: it now says `TARGET` is third and the first three seams complete 78 lines, as the task's script asserts, where the skeleton had the design's "fourth" and 58.
67. **Task 7's Consumes line splits the held fakes**: the four `CoordinatorEditorTests` bodies hold an upload, and only the `CoordinatorOverlayTests` test holds an Abort (`holdingAbortsRemaining`, `aborts`, `releaseAborts()`).
68. **Task 5's failure advice follows D11**: a failing test is reported with its output and its assertions are not changed, where the writer's text said to fix the test against the catalogue entry.
69. **The plan cites no git-ignored file.** The Tests lists keep each test's catalogue heading and line and drop the built-source citation, the Interfaces blocks drop their built-file line comments, and the decisions and steps say "the review's built tree" with no path or line number. The anchors one task quotes from another (Task 3 from Task 2's last test, Task 5 from Task 4's, Task 6 from Task 1's helpers and last test, Task 7 from Task 6's last test) were checked against the plan's own code blocks and agree.
70. **The commit constraint is adapted.** context.md's hard constraint ends "Agents never commit or push in this design phase." That holds for the design phase; in this plan every task ends in a commit with its message (the plan's own rules), so the bullet under "verbatim" reads "Agents never push." and says it is adapted. Nothing is pushed and no branch is switched.
71. **The plan is committed before Task 1.** At dd1231d the plan is untracked (`?? docs/superpowers/plans/2026-10-30-editor-seam.md`), and Task 1's first check looks only at `TidyShot` and `TidyShotTests`, so the later checks that expect an empty or task-only `git status --short` (Tasks 1 to 5, 7 and 8) would print it and stop. The branch note now says the plan is committed on `editor-seam` first, as CT-1's was (8882bfd), and that no commit before Task 1 touches `docs/testing`, `docs/superpowers/notes` or `docs/superpowers/specs`, whose dd1231d text Task 8's Step 1 and scripts assert. The checks themselves are unchanged.
72. **Some upload tests read the uploaded key from the record.** The catalogue's section 4 rule (tests-editor.md:786-788) reads `k` from `destination.state.withLock { $0.uploads.last!.key }`; the built bodies of `anUploadAfterTheCapturesOwnClosesAtOnceAndEndsWithTheLinkCopied`, `uploadAsNewWithoutALinkIsRefusedAndUploadMakesTheFirstLink`, `uploadOfAPrePhase3CaptureMakesANewLinkAndDeletesNothing` (Task 4), `aNewSaveFolderReachesTheOpenEditorAndUploadGoesThroughPending`, `uploadOfAnUploadOnlyCaptureRemovesItsDragCopyAndEveryReadGivesTheEdit` (Task 5) and `anUploadedUploadOnlyCardsCopyImageAndAnnotateReadTheDragCopy` (Task 6) read it from `history.record(id:)?.uploadedKey`, and are kept (D11). That is enough because the record cannot name a key the PUT did not use: the upload queue PUTs under one `key` and sends that same `key` in `.uploaded(id:url:key:)` (UploadQueue.swift:175-187; the multipart path, UploadQueue+Multipart.swift:99), and `handle(.uploaded)` stores it unchanged (AppCoordinator+Upload.swift:635, :657). The record-to-PUT match is also asserted outright in `anUploadedCaptureReopensFlatWithItsMarksInThePixels` (`uploadedKey == uploads.first?.key`), and `annotateTheNewestCardSaveThenUploadWritesTheFileThenUploadsAndCopiesTheURL` and `saveOnAFailedUploadOnlyCaptureRewritesPendingAndRetryUploadsTheEdit` (Task 2) take `k` from `uploads.first?.key`.
73. **phase-4a:147 keeps its free-text note under `EDITOR`.** seams.md:106 notes "EDSAVEAS is an alternative to EDITOR for the Save As write", and design 11 item 3 adds :147 to `EDSAVEAS`'s row as a joint need, so after the edit the entry reads `(also EDPLACE, EDSAVEAS); EDSAVEAS is an alternative to EDITOR …; CT-2: in part`, which is at odds with the join. Design 11 item 3 replaces only the notes on phase-4a:97 and :148 (seams.md:83, :107), and the plan edits seams.md exactly as section 11 says, so `REPLACED_NOTES` stays as it is and the note is kept. Dropping it is a one-entry change to `REPLACED_NOTES` for a later edit of seams.md, which would change Task 8's seams.md diffstat.
74. **seams.md's `EDITOR` section keeps the sweep's Shape and Note bullets.** After Task 8 the section still says the proposed closure is `makeEditor(model, actions, title, representedURL)` with `onClose` on the protocol, and that save-folder cases need `saveLocation.store(tempURL)`, "which the harness has not tried (D25)". The built seam takes `onClose` as the factory's fifth argument (design 2.2, call 3), and the built tests settle D25 (design 5). Design 11 does not ask for those bullets to change, so the script leaves them and adds only the `CT-2:` bullet; the design is the record of what was built.
75. **Every suite's doc comments stay within 120 characters.** Task 7 checked its two files only, while five `///` lines in the Save and Upload files passed 120 characters (121 to 129). Those lines are rewrapped inside their paragraphs, so no block gains or loses a line and Task 3's `320 insertions(+)`, Task 5's `368` and Task 6's `372` are unchanged, and Tasks 2 to 5 now run the same width check as Task 7 on their files. Statements are not rewrapped (D53). The rewrapped files passed in a scratch tree (`Test run with 31 tests in 2 suites passed` for the two suites).
76. **Task 1 (execution): the two first tests are stronger than the brief's text, and the code stands.** Task 1's quality review found that both tests passed on their own regressions: `annotateOnACaptureWhoseEditorIsOpenBringsItForwardAndBuildsNoSecond` with a pending-file source leaves no trace of a second load when the `openingEditorIDs` guard (`AppCoordinator+Editor.swift`, `openEditor`) is dropped, and `quitAsksEachChangedEditorCancelStopsItDontSaveLetsItGo`'s `Array(editor.calls.suffix(2)) == [.present, .askToSave]` holds even when `reviewEditorsBeforeQuit` stops calling `present()`, since the open already recorded a `.present`. The fix rounds (62b01c4, fe0a799) changed the two bodies: the open test builds an upload-only capture with `addUploadOnly`, so a second open would download again, and asserts `destination.state.withLock { $0.dataDownloadKeys } == [key]`; the quit test records `let before = editor.calls.count` before the review and asserts `Array(editor.calls.dropFirst(before)) == [.present, .askToSave]`, and after the Don't Save review asserts `coordinator.editors[changed.id] === editor` and `coordinator.editors[clean.id] === other`. Mutation checks with the guard dropped, the review's `present()` dropped and a registry drop after Don't Save each fail the new assertions and were reverted. The code is kept over D11's "bodies are the built ones": D11 holds where the built body pins its line, and these two did not. The catalogue's entries (tests-editor.md sections 5 "Opening" and "The quit review") keep dd1231d's text until Task 8, whose Step 7 records in the design's section 12 that the two tests were built in this form; the marks are unchanged (phase-4a:39 and phase-4a:155 stay in part for the same reasons). A task's fix rounds commit as `fix: <what>` after the task's own commit; the brief's one commit is not squashed.

