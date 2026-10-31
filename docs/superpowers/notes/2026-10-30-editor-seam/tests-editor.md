# CT-2 test catalogue: the editor seam

The tests the editor seam (`EDITOR`) gives the 73 lines of `lines-editor.md` (in this folder), in the form of
`docs/superpowers/notes/2026-10-30-checklist-sweep/tests-A.md`: each test names its suite file, its entry point, the
record it opens, the fakes that observe it, what it asserts, its effort and every checklist line it covers. The seam,
the fakes and the rules tests follow are the design's (`EditorPresenting`, `AppEnvironment.makeEditor`, `FakeEditor` and
`FakeEditors` in `TidyShotTests/Support/EditorFakes.swift`, `world.editors`, `FakeClipboard.pngs`;
`docs/superpowers/specs/2026-10-30-tidyshot-editor-seam-design.md`, "the design", sections 2, 3 and 5). This catalogue merges three that were written per checklist group (phase-4a; phase-4b and phase-4c;
coordinator-split, phase-6a, phase-6b, phase-7c and small-tweaks). Section 2.6 lists what the merge changed. Every line
number in the code is at a079a6f (branch `editor-seam`); checklist lines are named by catalogue key with the current line
in brackets, as `lines-editor.md` does. No Swift bodies; each entry gives every value a body needs.

Abbreviations: `+Editor` = `TidyShot/App/AppCoordinator+Editor.swift`, and `+Upload`, `+Delete`, `+Save`, `+Overlay`,
`+RecordActions`, `+DragOut`, `+Pins` likewise for the other `AppCoordinator+*.swift` files; `Coord` =
`TidyShot/App/AppCoordinator.swift`; `EWC` = `TidyShot/Editor/Window/EditorWindowController.swift`; `Model` =
`TidyShot/Editor/Session/EditorModel.swift`; `EST` (also `Target`) = `TidyShot/Editor/Persistence/EditorSaveTarget.swift`;
`EUP` (also `Plan`) = `TidyShot/Editor/Persistence/EditorUploadPlan.swift`; `EI` =
`TidyShot/Editor/Persistence/EditorInput.swift`; `EN` = `TidyShot/Editor/Persistence/EditorNaming.swift`; `EC` =
`TidyShot/Editor/Persistence/EditorClipboard.swift`; `CR` = `TidyShot/History/CaptureRecord.swift`; `HS` =
`TidyShot/History/HistoryStore.swift`; `TS` = `TidyShot/History/ThumbnailStore.swift`; `SL` =
`TidyShot/Output/SaveLocation.swift`; `UQ` = `TidyShot/Upload/UploadQueue.swift`; `Dest` =
`TidyShot/Upload/Destination.swift`; `World` = `TidyShotTests/Support/CoordinatorWorld.swift`; `Fakes` =
`TidyShotTests/Support/CoordinatorFakes.swift`; `FD` = `TidyShotTests/Support/FakeDestination.swift`; `EF` =
`TidyShotTests/Support/EditorFakes.swift` as the design's section 3.1 gives it (new; cited by member, not line).

## 1. Summary

46 tests: 17 in the new `CoordinatorEditorSaveTests`, 14 in the new `CoordinatorEditorUploadTests`, 14 added to the
existing `CoordinatorEditorTests`, 1 added to the existing `CoordinatorOverlayTests`. Five of them are the minimal
design's tests 1 to 5, already built and green in its scratch tree; each is written out below as the other entries are.
One of those five (test 2) takes a different edit here (section 2.6), and test 5 gains a `TaskWatch` gate. Of the 73
lines: full 25, part 40, deferred 8, obsolete or already covered 0 (section 9). phase-4a:39 and phase-6a:164 are part
here, not full as in the judge's draft (design call 13). The design's review built every entry here, with the review's
fixes, in a scratch tree, and all of them passed (design section 12); the `CoordinatorOverlayTests` entry was built in a scratch
suite with its own `destination`, so its placement in that suite and the `destination` property it adds (2.2) are the plan's.

| Line (key, current line) | Test | Suite | Verdict |
|---|---|---|---|
| coordinator-split:43 (:43) | `annotateTheNewestCardSaveThenUploadWritesTheFileThenUploadsAndCopiesTheURL` | CoordinatorEditorUploadTests | part |
| coordinator-split:44 (:44) | `annotateFromACardOrRecentCapturesLeavesNothingToRestore` (the pin menu's Annotate) | CoordinatorEditorTests | part |
| phase-4a:37 (:39) | `anEditorOpenedDuringAHeldUploadHearsUploadingAndGetsSaveAndUploadBack` | CoordinatorEditorTests | part |
| phase-4a:39 (:43) | `annotateOnACaptureWhoseEditorIsOpenBringsItForwardAndBuildsNoSecond` | CoordinatorEditorTests | part (the window coming forward, by hand) |
| phase-4a:49 (:59) | `anUploadedUploadOnlyCaptureOpensFromItsObjectAndOfflineOpensNone` | CoordinatorEditorTests | full |
| phase-4a:52 (:65) | `withTheOverlayOffEveryAfterCaptureModeStillOpensTheEditor(mode:)` | CoordinatorEditorTests | full |
| phase-4a:56 (:70) | none this phase | (`EditorWindowControllerTests`, `EDPLACE`) | deferred |
| phase-4a:58 (:72) | none this phase | (`EditorWindowControllerTests`, `EDPLACE`) | deferred |
| phase-4a:88 (:137) | none this phase | (`EditorWindowControllerTests`, `EDPLACE`) | deferred |
| phase-4a:94 (:143) | `saveWritesOverTheSaveFolderFileAndUploadsNothing` | CoordinatorEditorSaveTests | part |
| phase-4a:95 (:144) | `saveOverAnUploadedCaptureRewritesTheFileOnlyAndMarksItsLinkStale(link:)`, `.afterPhase3` | CoordinatorEditorSaveTests | part |
| phase-4a:96 (:145) | the same, `.beforePhase3` | CoordinatorEditorSaveTests | part |
| phase-4a:97 (:146) | `saveAsOnAnUploadOnlyCaptureWritesThePNGAndUploadsNothing` | CoordinatorEditorSaveTests | part |
| phase-4a:98 (:147) | `saveOnAFailedUploadOnlyCaptureRewritesPendingAndRetryUploadsTheEdit` | CoordinatorEditorSaveTests | full |
| phase-4a:99 (:148) | `saveOverALockedFileSaysNotSavedAndPutsTheEditOnTheClipboard` | CoordinatorEditorSaveTests | part |
| phase-4a:102 (:151) | `saveAsElsewhereWritesA144DPICopyAndLeavesTheCaptureAlone` | CoordinatorEditorSaveTests | part |
| phase-4a:106 (:157) | `saveAsOntoItsOwnFileIsASave(uploaded:)` | CoordinatorEditorSaveTests | part |
| phase-4a:107 (:158) | none this phase | (`EDPLACE` and `BEEP`) | deferred |
| phase-4a:112 (:165) | `copyWithShowNotificationOffPostsNothing` | CoordinatorEditorSaveTests | full |
| phase-4a:115 (:168) | `aSaveOrSaveAsTakesTheClipboardOnlyWhileItHoldsTheCapture(write:userCopied:)`, `(.save, false)` | CoordinatorEditorSaveTests | full |
| phase-4a:116 (:169) | the same, `(.saveAs, false)` | CoordinatorEditorSaveTests | full |
| phase-4a:117 (:170) | the same, `(.saveAs, true)` | CoordinatorEditorSaveTests | full |
| phase-4a:118 (:171) | the same, `(.save, true)` | CoordinatorEditorSaveTests | full |
| phase-4a:119 (:172) | `withNoDestinationSaveTakesTheClipboardAndUploadIsRefused` | CoordinatorEditorUploadTests | part |
| phase-4a:120 (:173) | `anUploadAfterTheCapturesOwnClosesAtOnceAndEndsWithTheLinkCopied` | CoordinatorEditorUploadTests | part |
| phase-4a:123 (:176) | `uploadWritesTheFileFirstThenReplacesTheLinksObject` | CoordinatorEditorUploadTests | part |
| phase-4a:124 (:177) | `uploadOfAnUploadOnlyCaptureWritesPendingThenReplacesItsKey` | CoordinatorEditorUploadTests | part |
| phase-4a:127 (:185) | `uploadAsNewWithoutALinkIsRefusedAndUploadMakesTheFirstLink` | CoordinatorEditorUploadTests | part |
| phase-4a:129 (:189) | `uploadOfAPrePhase3CaptureMakesANewLinkAndDeletesNothing` | CoordinatorEditorUploadTests | full |
| phase-4a:130 (:190) | `uploadAfterTheDestinationChangedGoesToTheNewBucketAndDeletesTheOldObject` | CoordinatorEditorUploadTests | full |
| phase-4a:131 (:191) | `aFailedReplaceKeepsTheLinkAndTheEditAndTheRightKeyReplacesIt` | CoordinatorEditorUploadTests | part |
| phase-4a:132 (:192) | `aFailedReplaceAfterAFolderChangeKeepsTheEditInPendingUntilTheNextUpload` | CoordinatorEditorUploadTests | part (line text at odds with the code, section 8) |
| phase-4a:133 (:193) | `aFailedReplaceOfAnUploadOnlyCaptureKeepsPendingAcrossARelaunchUntilTheNextUpload` | CoordinatorEditorUploadTests | part |
| phase-4a:145 (:212) | `anEditorOpenedDuringAHeldUploadHearsUploadingAndGetsSaveAndUploadBack` | CoordinatorEditorTests | part |
| phase-4a:146 (:213) | `aDeleteAskedThenCancelledThenConfirmedReachesTheOpenEditor`; `anEditorOpenedWhileADeleteAsksHearsItAndRefusesSave` | CoordinatorEditorTests | part |
| phase-4a:147 (:214) | the same two | CoordinatorEditorTests | part |
| phase-4a:148 (:215) | `aNewSaveFolderReachesTheOpenEditorAndUploadGoesThroughPending` | CoordinatorEditorUploadTests | part |
| phase-4a:151 (:218) | none this phase | (`EditorWindowControllerTests`, `EDPLACE`) | deferred |
| phase-4a:155 (:223) | `quitAsksEachChangedEditorCancelStopsItDontSaveLetsItGo` | CoordinatorEditorTests | part |
| phase-4a:162 (:231) | `aPrunedCaptureTellsItsOpenEditorItWasDeleted` | CoordinatorEditorTests | part |
| phase-4b:71 (:99) | `saveWithACropWritesTheCroppedSizeAtTheCapturesScaleAndReopensCropped(scale:)` | CoordinatorEditorSaveTests | full |
| phase-4b:73 (:101) | the same | CoordinatorEditorSaveTests | full |
| phase-4b:74 (:102) | `uploadWritesTheFileFirstThenReplacesTheLinksObject` | CoordinatorEditorUploadTests | full |
| phase-4b:75 (:103) | `uploadOfAnUploadOnlyCaptureWritesPendingThenReplacesItsKey` | CoordinatorEditorUploadTests | full |
| phase-4b:76 (:104) | `saveAsWithACropWritesACroppedCopyAndLeavesTheCaptureAlone` | CoordinatorEditorSaveTests | full |
| phase-4b:77 (:105) | `copyWithACropPutsTheCroppedImageAtPointSizeAndSaysImageCopied` | CoordinatorEditorSaveTests | full |
| phase-4b:92 (:132) | the same | CoordinatorEditorSaveTests | part (the window's key routing) |
| phase-4b:105 (:149) | `saveWithTextEllipseAndCropWritesAllThreeIntoTheSameFile` | CoordinatorEditorSaveTests | full |
| phase-4b:106 (:150) | `uploadWritesTheFileFirstThenReplacesTheLinksObject` | CoordinatorEditorUploadTests | part (closing at once) |
| phase-4b:107 (:151) | `saveOnAFailedUploadOnlyCaptureRewritesPendingAndRetryUploadsTheEdit` | CoordinatorEditorSaveTests | full |
| phase-4b:108 (:152) | `uploadOfAnUploadOnlyCaptureWritesPendingThenReplacesItsKey` | CoordinatorEditorUploadTests | full |
| phase-4b:112 (:156) | `aFailedReplaceOfAnUploadOnlyCaptureKeepsPendingAcrossARelaunchUntilTheNextUpload` | CoordinatorEditorUploadTests | part (the window closing) |
| phase-4b:113 (:157) | the same | CoordinatorEditorUploadTests | part (the subtitle as shown) |
| phase-4b:114 (:158) | the same | CoordinatorEditorUploadTests | full |
| phase-4c:94 (:94) | none this phase | (`EditorWindowControllerTests`, `EDPLACE`) | deferred |
| phase-4c:95 (:95) | none this phase | (`EditorWindowControllerTests`, `EDPLACE`) | deferred |
| phase-4c:179 (:245) | `anUploadedCaptureReopensFlatWithItsMarksInThePixels` | CoordinatorEditorUploadTests | full |
| phase-4c:201 (:273) | `anEditorOpensWithTheStoredSpotlightShapeAndCounterSize` | CoordinatorEditorTests | part (`EDDEFAULTS`, hand) |
| phase-4c:214 (:296) | `aCaptureFromBefore4cOpensEditsAndSavesAsBefore` | CoordinatorEditorTests | full |
| phase-6a:131 (:133) | `annotateFromACardOrRecentCapturesLeavesNothingToRestore` | CoordinatorEditorTests | part |
| phase-6a:152 (:155) | `annotateFromACardOrRecentCapturesLeavesNothingToRestore` | CoordinatorEditorTests | full |
| phase-6a:158 (:161) | `annotateFromACardOrRecentCapturesLeavesNothingToRestore` (the editor cases); `aCardWhoseDeleteIsUnderWayIsNotRestorable` (the delete under way) | CoordinatorEditorTests; CoordinatorOverlayTests | full |
| phase-6a:164 (:172) | `aRestoredCardsAnnotateOpensFromTheFileOrTheBucket(restored:)` | CoordinatorEditorTests | part (the restore itself, `SCREENS`) |
| phase-6a:198 (:210) | `anUploadedUploadOnlyCardsCopyImageAndAnnotateReadTheDragCopy` | CoordinatorEditorTests | part |
| phase-6a:199 (:211) | `saveOverTheFileRemovesTheDragCopyAndEveryReadGivesTheEdit` (the "Save and copy image" half); `uploadOfAnUploadOnlyCaptureRemovesItsDragCopyAndEveryReadGivesTheEdit` (the upload-only half) | CoordinatorEditorSaveTests; CoordinatorEditorUploadTests | part |
| phase-6b:118 (:144) | `annotateTheNewestCardSaveThenUploadWritesTheFileThenUploadsAndCopiesTheURL` (its open leg) | CoordinatorEditorUploadTests | part |
| phase-7c:72 (:73) | none this phase | (`EditorWindowControllerTests`, `EDPLACE`) | deferred |
| phase-7c:169 (:212) | `copyWithABackgroundPutsTheComposedCanvasOnTheClipboard` | CoordinatorEditorSaveTests | part |
| phase-7c:170 (:213) | `saveWithABackgroundWritesTheComposedCanvasAndReopensFlat` (the composed canvas, size, thumbnail); `saveWritesOverTheSaveFolderFileAndUploadsNothing` (the save-over path with no background) | CoordinatorEditorSaveTests | part |
| phase-7c:171 (:214) | `saveWithABackgroundWritesTheComposedCanvasAndReopensFlat` | CoordinatorEditorSaveTests | part |
| phase-7c:172 (:215) | `saveAsWithABackgroundWritesTheComposedImageAndLeavesTheCaptureAlone` | CoordinatorEditorSaveTests | part |
| phase-7c:187 (:230) | `aComposedWindowCaptureOpensFlatWithNoBackground(composed:)` | CoordinatorEditorTests | part |
| small-tweaks:18 (:21) | `annotateTheNewestCardSaveThenUploadWritesTheFileThenUploadsAndCopiesTheURL` (both halves); `saveWritesOverTheSaveFolderFileAndUploadsNothing` (the Save half, from an editor opened on the file) | CoordinatorEditorUploadTests; CoordinatorEditorSaveTests | full |

Already covered or obsolete: none of the 73. No test today reaches an open editor or its actions (a case-sensitive grep
of `TidyShotTests` for `editors`, `pushEditorState`, `openEditor`, `reviewEditorsBeforeQuit` finds only
CoordinatorEditorTests.swift:83, :90 and a comment at CanvasViewEventTests.swift:50; QuitHoldTests calls only
`holdsQuit(hasUnsavedEditors:)`, QuitHoldTests.swift:8-17); none of the 73 carries a `(suite...)` mark or an
`(obsolete: ...)` note at a079a6f (`lines-editor.md`, its header); each line's text was found unchanged at the current
line number listed. The pure rules the lines also name (the availability table, the upload plan, the clipboard rule, the naming, the
intent order, the restore list) are already pinned by `EditorSaveTargetTests`, `EditorUploadPlanTests`,
`EditorClipboardTests`, `EditorNamingTests`, `QuitHoldTests`, `CaptureIntentTests` and `ClosedOverlaysTests`; those names
go in the marks beside the new tests, as `lines-editor.md` lists them per line.

## 2. What holds for every test here

- Each suite is `@Suite(.timeLimit(.minutes(1)))`, owns a `CoordinatorWorld` built in `init() throws`, and each test
  starts with `defer { world.removeAll() }` (World:141-144). No `.serialized`. Save-folder cases call
  `world.storeSaveFolder()` (World:150-156, `<root>/Saved/`) before `world.makeCoordinator()`; a second folder is
  `<root>/Other/`, created and then `world.saveLocation.store(_:)` (SL:23-28 sets `currentURL` to the URL given,
  unresolved, so a test compares URLs as made). The minimal design's tests 1 and 2 wrote over a bookmarked folder's file
  through `SaveLocation.overwriteScoped` and passed, so the old D25 worry (a security-scoped bookmark untried in the
  harness) is settled (design section 5).
- The editor is a `FakeEditor` (EF): `world.editors.editor(for: id)` is the newest one built for the record;
  `coordinator.editors[id]` is the registry (Coord:259 after the seam). A test plays the user with `draw()`, `save()`,
  `saveAs(to:)`, `copy()`, `upload(asNew:)`, `close()` and `export()`, or edits `editor.model` directly, and reads
  `calls`, `pushes`, `presentCount`, `isClosed`, `title`, `representedURL`. These awaits return on their own
  (`actions.upload` returns once enqueued, +Editor:377-378), which the design (3.4) and CT-1 accept; held work is
  observed with `eventually` (UploadQueueTests.swift:42-48) and released, with `defer { destination.releaseUploads() }`
  (FD:256-264) so a failing test cannot leave a PUT parked; a task that waits on a held fake (the quit review over a
  held sheet, a delete over a held confirm) is gated by `TaskWatch` (Fakes:420-429) and cancelled in a `defer`
  registered right after it is made (after `defer { world.removeAll() }`, so it runs first): cancelling it is what makes
  `SingleWaiter` answer Cancel or No (Fakes:393-400) when a test fails before it answers. A test that held a PUT also
  releases it and waits for `isUploading == false` before it returns.
- Nothing an edit starts outlives its test. A test whose action reached `applyLocalEdit` (a Save over the file or
  `pending/`, an Upload's local write) ends with `try await settledEdit(coordinator, id)` (2.2), which waits until the
  record names the edit's thumbnail; the thumbnail task (+Editor:217, :249-275) saves history when it lands and would
  recreate the world's folders after `removeAll()` (ThumbnailStore.swift:44-45, HistoryStore.swift:199-215). A second
  edit of one record in one test first runs `world.date = world.date.addingTimeInterval(1)`, so its thumbnail has a new
  name to wait for. A test that compares a whole record after a Save or an Upload calls `settledEdit` first, or the
  comparison races the task. A Save that fails before the write (a refusal, a locked file) starts no thumbnail task.
- A relaunch is a second `world.makeCoordinator()` then `history.load()`. Before it the first coordinator is quiescent
  (no upload running, the edit's thumbnail named); after it the test calls nothing on the first coordinator and does not
  run `world.clock`: the first still holds its folder observation, drag clean-ups and `HistoryStore` over the same
  `history.json` (+Editor:137-152, +DragOut:261-276, HistoryStore.swift:66-70).
- `world.clipboard.pngs` (design 3.2: `FakeClipboard` keeps the PNG of every `.image` and `.pngAndTIFF` copy) stands
  for what Preview's New from Clipboard would read.
- A record's timestamp is the real `Date()` (CR:114 default) unless a test sets one; `HistoryStore` prunes on the real
  `Date()` (HS:23, Coord:278). `environment.now()` is `world.date` = `Date(timeIntervalSinceReferenceDate: 800_000_000)`
  (Fakes, `CoordinatorWorldState`), so every edit's `editedAt` is that date and the edited thumbnail's name is
  `coordinator.thumbnails.fileName(for: id, editedAt: world.date)`, that is `"<UUID>-1778307200000.png"` (TS:28-32:
  milliseconds since 1970 of 800 000 000 s after 2001-01-01).
- Uploads: the world's destination is `world.factory.standard`; its `publicURL(for:)` is `https://snap.tky.io/<key>`
  (FD:274-276; the world's `publicURLTemplate`, World:20). The world's key template is `ObjectKeyNamer.defaultTemplate` =
  `"{random:6}"` (ObjectKeyNamer.swift:11; S3DestinationConfig.swift:32), so a template key never equals `s/SHOT.png`.
  Credentials and `s3Config` are the world's (World:78-81, :86), so `makeDestination()` returns a target
  (+Upload:39-45). `uploadSleep` is a no-op (World:120). A 403 is not retried and a 5xx or 429 is (Dest:177-183,
  UQ:193), at most 3 attempts for data (RetryPolicy.swift:10). Clop is off by default, so a PNG goes to the lane as data
  (+Upload:186-194).
- Backgrounds are solid only, so `BackgroundFillSource.fillImage` returns nil and reads no wallpaper or custom image
  (BackgroundFillSource.swift:10-14; a custom image would read `CustomBackgroundStore.shared`, :12-13). No test sets a
  background through the popover's switch, which would read `AppSettings.shared.backgroundStyle`
  (BackgroundPopoverView.swift:36-38). Nothing sets a colour or a size on a window (there is none), so
  `AppSettings.shared` is not reached. `RedactionRenderer.shared` is process-wide and these are the first tests to reach
  it (`RedactionRendererTests` makes its own, RedactionRendererTests.swift:74): `presentEditor`'s warm-up and the last
  close's cache clear (+Editor:88, :474). No test observes it, because no test commits an effect (redact, blur,
  pixelate), the only annotations the tile cache asks it for (Annotation.swift:101-105). That is a rule, not a
  preference.
- No test calls `restoreClosedOverlay()` unless `canRestoreClosedOverlay` was first required false: with nothing
  restorable it returns at `popRestorable` (+Overlay:88-90) before `overlayScreen`, which reads `NSScreen.screens`
  (+Overlay:56; `FakeCards.screen` is nil, Fakes `FakeCards`). `hasRestorable` and `popRestorable` use the same predicate
  (ClosedOverlays.swift:32-41), so the guard is exact.
- History is loaded without `start()`: the relaunch and the pre-4c test call `history.load()` on a coordinator built by
  `makeCoordinator()`; `start()` would remove `ClopApp.workDirectory` and `RecordingTrim.directory`
  (AppCoordinator.swift:294-300), which are `tmp/` statics.

### 2.1 Support: what the design adds, and one new file

From the design, not added here: the seam (design 2: `environment.makeEditor`, the registry `[UUID: any
EditorPresenting]`); `TidyShotTests/Support/EditorFakes.swift` (design 3.1: `FakeEditor`, its `Push` with `record`,
`saveFolder`, `isDeleting`, `available`, `status`, `saveCommand`, its `Call` and `CloseAnswer`, and `FakeEditors` with
`built` and `editor(for:)`); `world.editors` (design 3.3); `FakeClipboard.pngs` (design 3.2). `FakeDestination.dataDownloadFailures` (FD:107) exists since
CT-1, so phase-4a:49 needs no fake change.

New: `TidyShotTests/Support/EditorPixels.swift`, a `nonisolated enum EditorPixels` (test target only; not a fake, not a
seam, not a suite). Entries below write its members bare; bodies call them as `EditorPixels.<name>`.

- `image(width: Int, height: Int, white: Bool = false) throws -> CGImage` (`png`'s helper; no test calls it directly): as `CoordinatorWorld.image` (World:170-177:
  `CGContext(data: nil, width:, height:, bitsPerComponent: 8, bytesPerRow: 0, space: sRGB, bitmapInfo:
  premultipliedLast)`), filled with `CGColor(red: 1, green: 0, blue: 0, alpha: 1)` or the same initializer's white, as
  World:174 fills. That initializer makes a Generic RGB colour, so the world's red, and this red, read back through
  `pixel` as `[255, 38, 0, 255]`, not `[255, 0, 0, 255]`; white reads `[255, 255, 255, 255]`.
- `@MainActor static func worldRed() throws -> [Int]`: `pixel(try CoordinatorWorld.image(width: 1, height: 1), x: 0,
  y: 0)`, the world's red as it reads back. A test that says "the capture's red" compares with this
  (`pixel(base, x:, y:) == (try worldRed())`). Main-actor because `CoordinatorWorld.image` is.
- `png(width: Int, height: Int, scale: CGFloat, white: Bool = false) throws -> Data`: `ImageEncoder.pngData(from:
  image(...), scale: scale)` (TidyShot/Output/ImageEncoder.swift:21-36 writes DPI `72 * scale`). `CoordinatorWorld.pngData`
  (World:180-182) is scale 1 and red only, which is why this exists.
- `decoded(_ png: Data) throws -> (image: CGImage, scale: CGFloat)`: `try #require(ImageEncoder.decode(png))`
  (ImageEncoder.swift:42-48; scale is DPI / 72 rounded).
- `dpiWidth(of png: Data) -> Double?`: `CGImageSourceCreateWithData`, then `CGImageSourceCopyPropertiesAtIndex(source, 0,
  nil)[kCGImagePropertyDPIWidth] as? Double` (as ImageEncoderTests.swift:32-39 reads it). PNG stores pixels per metre, so
  144 reads back a fraction off (ImageEncoder.swift:39-40); compare with `abs(dpi - 72 * scale) < 0.5`.
- `rgba(_ image: CGImage) -> [UInt8]`: the image drawn into an sRGB premultipliedLast context of its own size with
  `bytesPerRow: width * 4`, bytes top row first, as `FreezeCropTests.rgba` (TidyShotTests/FreezeCropTests.swift:116-123)
  reads one pixel. Equality of two `rgba` arrays is "the same pixels". The flattener draws into the base's sRGB space
  (TidyShot/Editor/Rendering/EditorFlattener.swift:79-88) and every pixel is opaque, so the PNG round trip is lossless;
  if a run shows a one-step difference, compare per channel within 1 instead (say so in the test's comment).
- `pixel(_ image: CGImage, x: Int, y: Int) -> [Int]` and `pixel(_ png: Data, x:, y:)` (decodes first): `[r, g, b, a]` at
  (x, y) from the top left (FreezeCropTests.swift:116-123). It reads what `EditorFlattenerTests.Bitmap`
  (EditorFlattenerTests.swift:49-70) reads after a redraw into premultipliedLast; fill pixels of a solid background are
  checked exactly, as `EditorBackgroundExportTests.solidBackgroundExportHasTheLayoutsSizeAndFill` does for the same
  compositor (EditorBackgroundExportTests.swift:51-53).
- `changedPixels(_ image: CGImage, in rect: CGRect, from rgb: [Int]) -> Int`: the pixels of `rect` (integral, clipped to
  the image) whose r, g or b differs from `rgb` by more than 16. Used for "the text is in the pixels".
- `isBlue(_ pixel: [Int]) -> Bool`: red < 40, green < 40, blue > 200. `isBlue(_ image: CGImage)` and `isBlue(png: Data)`:
  the image drawn into a 1 by 1 sRGB premultipliedLast context, then the same rule on that pixel. `FakeEditor.draw()`
  commits a box over the whole capture (`RGBA(red: 0, green: 0, blue: 1)`, line width the longer side, EF), the world's
  PNGs are red (World:170-182), so blue means the edit.

### 2.2 Suite helpers (members of each suite that uses them, as the existing suites keep their own `addPendingImage`, CoordinatorUploadTests.swift:40-51, CoordinatorDeleteTests.swift:54-64)

- `key = "s/SHOT.png"`, `link = URL(string: "https://snap.tky.io/s/SHOT.png")!`, `destination = world.factory.standard`
  (as CoordinatorEditorTests.swift:11-18; the suite skeleton is CoordinatorEditorTests.swift:8-18).
- `publicURL(_ key: String) -> URL`: `https://snap.tky.io/<key>`, the URL of a template key.
- `openedEditor(_ id: UUID) async throws -> FakeEditor`: `try await eventually { world.editors.editor(for: id) != nil }`,
  then `try #require(world.editors.editor(for: id))`.
- `reopenedEditor(_ id: UUID, after first: FakeEditor) async throws -> FakeEditor`: `try await eventually {
  world.editors.editor(for: id).map { $0 !== first } ?? false }`, then `#require`. `FakeEditors.editor(for:)` returns the
  newest (design 3.1).
- `settledEdit(_ coordinator: AppCoordinator, _ id: UUID) async throws`: `try await eventually {
  coordinator.history.record(id: id)?.thumbnailFileName == coordinator.thumbnails.fileName(for: id, editedAt:
  world.date) }` (section 2's rule).
- `addSavedImage(to coordinator:, in folder:, name: String = "Shot.png", uploadState: = .none, objectLocation: = nil,
  uploadIsStale: = false, timestamp: Date = Date(), scale: CGFloat = 1) throws -> (record: CaptureRecord, original: Data)`:
  writes `ImageEncoder.pngData(from: CoordinatorWorld.image(width: 4, height: 2), scale: scale)` to `folder/name`, adds
  `CaptureRecord(timestamp:, fileURL: folder/name, pixelWidth: 4, pixelHeight: 2, appName: nil, uploadState:,
  objectLocation:, uploadIsStale:, byteCount: original.count)` with `coordinator.history.add`, and returns both. At its
  defaults it is the `addSavedFile(to:in:)` of the part-C catalogue.
- `addPendingImage(to coordinator:) throws -> CaptureRecord`: as CoordinatorUploadTests.swift:40-51 with its defaults:
  `pending/<id>.png` from `CoordinatorWorld.pngData(width: 4, height: 2)`, `fileIsTemporary: true`,
  `.failed(message: "Upload was interrupted.")`, `byteCount: png.count`.
- `addUploadOnly(to coordinator:) throws -> CaptureRecord`: `destination.state.withLock { $0.downloadedData = try
  CoordinatorWorld.pngData(width: 4, height: 2) }` (set the PNG before the lock), then adds `CaptureRecord(fileURL: nil,
  pixelWidth: 4, pixelHeight: 2, appName: nil, uploadState: .uploaded(url: link, key: key), objectLocation:
  world.location)`. `EditorInput.source` gives `.download` (EI:51-61).
- `desktop(_ name: String) throws -> URL`: `<root>/Desktop/<name>`, its folder created (the URL a save panel would return).
- `pendingURL(_ coordinator:, _ id:) -> URL`: `coordinator.pendingFiles.directory.appending(path: "\(id.uuidString).png")`
  (PendingFileStore.swift:21-23).
- `isUploaded(_ coordinator:, _ id:) -> Bool` (as CoordinatorUploadTests.swift:76-79).
- `exists(_ url: URL) -> Bool` (as CoordinatorDragOutTests.swift:64-66).
- `title(of record:) -> String`: `"Capture \(record.timestamp.formatted(date: .omitted, time: .shortened))"`, the title
  `presentEditor` gives a record with no save-folder file (+Editor:77-79).
- `crop(_ model: EditorModel, to rect: CGRect, apply: Bool)`: `model.tool = .crop` (sets `cropDraft` to the applied crop or
  the whole capture, Model:131-135), `model.cropDraft = rect`, and when `apply` (Return) `model.applyCrop()`
  (Model:375-379). Without `apply` the draft is left pending, and the action's own export applies it first, as EWC:303
  does (`FakeEditor.export()` follows it).
- `addText(_ model: EditorModel, _ string: String, at point: CGPoint) -> TextBox`: `model.beginTextEditing(at: point,
  existing: nil)`, `model.updateEditingText(string)`, `model.commitTextEditing()` (Model:453-496; one `Add Text` commit
  through `commitNewShape`, TidyShot/Editor/Tools/ToolFactory.swift:25-30), then return the document's `.text` box. New
  text is `textSizePoints` 20 (EditorPalette.swift:27) times the scale, in `strokeColor`, which the world's registered
  defaults make `EditorPalette.defaultStroke` = rgb(255, 59, 48) (EditorPalette.swift:6, :19, :93-97).
- Shapes go in through the tools' own constructors and commit, so the defaults apply as on the canvas:
  `model.commitNewShape(model.makeAnnotation(tool, from:, to:)!)` (Model:241-286) or
  `model.commitNewShape(model.makeStroke(tool, points:)!)` (Model:288-299). The default line width is 4 pt
  (EditorPalette.swift:95), so 8 px at 2x; the highlighter is `EditorPalette.defaultHighlight` (yellow rgb(255, 204, 0) at
  alpha 0.45, multiplied, EditorPalette.swift:8, :30-34) at 12 pt.
- `expected`: after the action, `try #require(await editor.export()).image`. The fake keeps the model after a close, and
  the action's export already applied any draft, so this re-renders the same document (EWC:301-317). Computing it after
  the action keeps the action's own export the one that applied a pending crop.
- `green = RGBA(red: 0, green: 1, blue: 0)`; `background = BackgroundStyle(fill: .solid(green), padding: 8, cornerRadius:
  0, shadow: false, aspect: .auto)`. Over the world's 4 by 2 capture at scale 1, `BackgroundLayout.make` gives
  `canvasSize` 20 by 18 and `contentRect` (8, 8, 4, 2) (BackgroundLayout.swift:21-50: pad = 8 x 1, width 4 + 16, height
  2 + 16, `.auto` has no terms, BackgroundStyle.swift:69-71). So fill pixels (0, 0), (7, 7), (12, 10), (19, 17) are
  `[0, 255, 0, 255]`, and content pixels (8, 8) to (11, 9) are the capture's.

| Helper | CoordinatorEditorSaveTests | CoordinatorEditorUploadTests | CoordinatorEditorTests |
|---|---|---|---|
| `key`, `link`, `destination`, `publicURL`, `openedEditor` | yes | yes | yes |
| `reopenedEditor`, `settledEdit` | yes | yes | yes |
| `addSavedImage`, `addPendingImage`, `desktop`, `pendingURL` | yes | yes | yes |
| `addUploadOnly`, `isUploaded`, `title(of:)` | yes | yes | yes |
| `exists` | yes | yes | no |
| `crop`, `addText`, `expected` | yes | yes | yes |
| `green`, `background` | yes | no | yes |

`CoordinatorOverlayTests` needs only `destination`, added to it as `var destination: FakeDestination { world.factory.standard }` (the suite has only `world` today, CoordinatorOverlayTests.swift:6-13).

### 2.3 What an editor hears first, by record (the first `recordDidChange`, +Editor:86, +Editor:126-129)

Read from `EditorAvailability.actions`/`.status` (EST:121-156) and `EditorSaveCommand.forSave` (EST:78-84). `all` is
`Set(EditorAction.allCases)` = save, saveAs, copy, upload, uploadAsNew (EST:65-67).

| Record | `available` | `status` | `saveCommand` |
|---|---|---|---|
| save-folder file, never uploaded | `all` minus `.uploadAsNew` (`notUploadedRefusal`, EST:142) | nil | `.writeOver` |
| save-folder file, uploaded, not stale | `all` | nil | `.writeOver` |
| save-folder file, uploaded, stale | `all` | `EditorSaveTarget.uploadedCopyStaleNotice` = `The uploaded copy still shows the original. Upload to replace it.` (EST:19) | `.writeOver` |
| `pending/` file, failed, no link | `all` minus `.uploadAsNew` | nil | `.writeOver` |
| no file, uploaded (upload only) | `all` | `EditorSaveTarget.noFileReason` = `This capture has no local file to save over.` (EST:16) | `.saveAs` |
| any, uploading | `[.copy, .saveAs]` | `Uploading…` (EST:112) | as the file |
| any, deleting | `[.copy, .saveAs]` | `Deleting…` (EST:111) | as the file |
| nil (deleted or pruned) | `[.copy, .saveAs]` | `This capture was deleted. Copy and Save As still work.` (EST:110) | `.saveAs` |
| save-folder file outside the current folder, not stale | `all` minus `.uploadAsNew` when never uploaded | `The file is outside the current save folder, so it is not saved over.` (EST:18) | `.saveAs` |

### 2.4 What "part (glue)" means here

The fake applies the controller's rules for marking saved (`exportAndDeliver`, EWC:288-296), closing after an upload
(`performUpload`, EWC:268-283) and the subtitle (`recordDidChange`, EWC:165-176) through the same pure functions, and
commits a text being typed first as the window does, but the controller's own lines do not run (design 5). Where a line
names the unsaved dot, the subtitle as shown, a greyed item, the window's key routing, the window's refusal of a shortcut
or the window closing, that check stays with `EDPLACE` (design call 1), whose controller tests are `edplace-design.md`
section 8 (committed beside this note at close-out, design call 10). The window coming forward is `present()`'s body,
which no seam lets the suite run, so it stays by hand. Each entry names what stays.

### 2.5 Marks

`(suite: Suite.test)` for full, `(suite, in part: …; by hand: <what>)` for part, as CT-1 (design 5), with each entry's
"By hand / other seam" as the by-hand text, naming the other seam where there is one (`EDPLACE` for the window's glue,
`SAVEAS`, `EDSAVEAS`, `CLOSESHEET`, `BEEP`, `QASTACK`, `PINS`, `SCREENS`, `TARGET`, `EDDEFAULTS`, `BGPOP`,
`APPDELEGATE`). The deferred lines stay unmarked and are listed under `EDPLACE` in seams.md; each part line joins the
seams.md row of every seam its mark names (design section 11). The design's section 6 gives three wording rules: a
stand-in is named ("Quick Look is the decode"), not called by hand; a mark citing a write-time refusal says the window's
"do nothing" is its validation's (`EDPLACE`); and a capture step set up by the test is said to be set up.

### 2.6 What the merge changed

- Four pairs pinned the same rule and are one test each, listing every line of both:
  - `saveOnAFailedUploadOnlyCaptureRewritesPendingAndRetryUploadsTheEdit` (phase-4a group, S) and
    `aPendingCapturesSaveRewritesItsPendingFileAndRetryUploadsTheStroke` (phase-4b group, M): Save of a failed
    upload-only capture rewrites `pending/<id>.png` and Retry PUTs those bytes. Kept the first name, the second's record
    and pencil stroke; M.
  - `uploadWritesTheFileFirstThenReplacesTheLinksObject` (phase-4a group, the minimal design's test 2) and
    `uploadReplacesTheLinksObjectWithTheCroppedHighlightedEdit` (phase-4b group): Upload over a save-folder capture with
    a link writes the file, then replaces the link's object. Kept the first name and every assertion of the built test;
    its whole-capture `draw()` becomes the second's highlight and pending crop on a white base, because a box over the
    whole picture hides the highlight. M.
  - `uploadOfAnUploadOnlyCaptureWritesPendingThenReplacesItsKey` (phase-4a group) and
    `anUploadOnlyCaptureOpensFromItsObjectAndUploadReplacesItCroppedWithTheText` (phase-4b group): Upload of an uploaded
    upload-only capture goes through a new pending file, then replaces the key. Kept the first name, the second's record,
    text and crop. M.
  - `aFailedReplaceOfAnUploadOnlyCaptureKeepsPendingUntilTheNextUpload` (phase-4a group, M) and
    `aFailedReplaceKeepsTheLinkAndTheEditAcrossARelaunchAndTheNextUploadReplacesIt` (phase-4b group, L): a failed replace
    of an upload-only capture keeps the link and the edit in `pending/`, and the next Upload replaces the key. Named
    `aFailedReplaceOfAnUploadOnlyCaptureKeepsPendingAcrossARelaunchUntilTheNextUpload`; the second's sequence with the
    first's reopen asserts. L.
- Renamed for the suites' naming (the existing `annotateOnAMovedPrePhase3FileSaysCouldNotOpenAndOpensNoEditor`, and
  `save…`/`saveAs…`/`copy…`/`upload…` openings for the action under test): `annotatingACaptureWhoseEditorIsOpen…` to
  `annotateOnACaptureWhoseEditorIsOpenBringsItForwardAndBuildsNoSecond`; `aSavedCapturesTextEllipseAndCropAllLandInTheSameFile`
  to `saveWithTextEllipseAndCropWritesAllThreeIntoTheSameFile`; `saveAsWithACropWritesACroppedCopyAndLeavesTheOwnFileAlone`
  to `saveAsWithACropWritesACroppedCopyAndLeavesTheCaptureAlone`; `saveAsWithABackgroundWritesTheComposedImageAndLeavesTheRecord`
  to `saveAsWithABackgroundWritesTheComposedImageAndLeavesTheCaptureAlone`; `aSaveWithABackgroundWritesTheComposedCanvasAndReopensFlat`
  to `saveWithABackgroundWritesTheComposedCanvasAndReopensFlat`; `anEditorSaveOverTheFileRemovesTheDragCopyAndEveryReadGivesTheEdit`
  to `saveOverTheFileRemovesTheDragCopyAndEveryReadGivesTheEdit`; `anEditorUploadOfAnUploadOnlyCaptureRemovesItsDragCopyAndEveryReadGivesTheEdit`
  to `uploadOfAnUploadOnlyCaptureRemovesItsDragCopyAndEveryReadGivesTheEdit`. Every name is unique in `TidyShotTests`
  and `TidyShot` (grep at a079a6f).
- One pixel helper: the phase-4a group's `isBlue`, the part-C group's `bitmap(...)[x, y]` over
  `EditorFlattenerTests.Bitmap` and the phase-4b group's `EditorPixels` are one `EditorPixels` in `Support/` (2.1), as the
  phase-4b catalogue asked. The part-C group's `addSavedFile`, `link(_:)` and `captureTitle(_:)` are `addSavedImage`,
  `publicURL(_:)` (a method named `link` would clash with the `link` property) and `title(of:)`.
- Lines covered by tests from two groups, both kept: phase-7c:170 and small-tweaks:18 (also pinned in part by
  `saveWritesOverTheSaveFolderFileAndUploadsNothing`), each saying which part it pins (section 1 and the entries).
- Tests that overlap without pinning the same rule, kept apart and cross-referenced: the three Save As… tests (144 dpi,
  crop, background: the export differs, the "capture left alone" assertions repeat); the three Copy tests (notification
  off; crop and `Image copied`; background); the `uploadedUploadOnly` case of
  `aRestoredCardsAnnotateOpensFromTheFileOrTheBucket(restored:)` and the on-line half of
  `anUploadedUploadOnlyCaptureOpensFromItsObjectAndOfflineOpensNone` (same download, reached from the card's entry and
  from Recent Captures'); the first upload in `annotateTheNewestCard…` and in `uploadAsNewWithoutALink…` (the first
  also pins Save and the clipboard; the second pins ⌥⌘U's refusal).

## 3. CoordinatorEditorSaveTests.swift (new)

Header: "The editor's Save, Save As… and Copy through the editor seam: `openEditor` builds a `FakeEditor`, and each test
plays the user through the `EditorActions` the coordinator handed it. No window, sheet or panel is built."

### Save over the file

### `saveWritesOverTheSaveFolderFileAndUploadsNothing` (M, the minimal design's test 1, as built)
- Entry: `actions.save` → `editorSave` → `applyLocalEdit` (+Editor:157-221), `.saveFolderFile` through
  `SaveLocation.overwriteScoped` (SL:123-131).
- Source: save-folder file `Shot.png` with a thumbnail written by `coordinator.thumbnails.write(Data("png".utf8), id:)`,
  opened from the file: `storeSaveFolder()`; `original = CoordinatorWorld.pngData(width: 4, height: 2)` at
  `<Saved>/Shot.png`; `thumbnail = try coordinator.thumbnails.write(Data("png".utf8), id: id)`; `CaptureRecord(id:,
  fileURL: file, thumbnailFileName: thumbnail, pixelWidth: 4, pixelHeight: 2, appName: nil, byteCount:
  original.count)`.
- Sequence: `openEditor(recordID: id)`; `editor = openedEditor(id)`; the open asserts; `editor.draw()`;
  `#expect(coordinator.hasUnsavedEditors)`; `let saved = await editor.save()`; `written = Data(contentsOf: file)`;
  `try await eventually { record.thumbnailFileName != thumbnail }`; the rest.
- Asserts as built: `title == "Shot.png"`, `representedURL == file`, `presentCount == 1`, first push `saveCommand ==
  .writeOver` and `available == all` minus `.uploadAsNew`; `.close(id, .editorOpened)`; `hasUnsavedEditors` after
  `draw()`; `save()` true; the file differs from the original and is blue; the folder holds only `["Shot.png"]`;
  `byteCount == written.count` (+Editor:215); `eventually` the thumbnail name changes; `!hasUnsavedEditors`;
  `askedConfigs.isEmpty`, `uploadAttempts == 0`, no errors.
- Added when moved (exact values, no behaviour beyond the built test): `thumbnailFileName ==
  coordinator.thumbnails.fileName(for: id, editedAt: world.date)` (+Editor:212, :217, :251; section 2);
  `record.editedAt == world.date`; the old thumbnail file is gone (`!FileManager.default.fileExists(atPath:
  coordinator.thumbnails.url(forFileName: thumbnail).path(percentEncoded: false))`, +Editor:271-273); `uploadState ==
  .none` and `uploadIsStale == false` (CR:205-212: no link); the new thumbnail shows the edit: `isBlue(png:
  Data(contentsOf: coordinator.thumbnails.url(forFileName: record.thumbnailFileName!)))`. The wait on the thumbnail
  name leaves the test settled.
- By hand / other seam: the unsaved dot clearing (glue, `EDPLACE`). Quick Look is the file's decode (`isBlue`), and the
  new thumbnail's decode stands for the row's thumbnail; the menu drawing the row, by hand.
- Covers: phase-4a:94, in part. Also, in part: small-tweaks:18's Save half (`byteCount` after a Save from an editor
  opened on the file; `annotateTheNewestCard…` pins both halves from the retained image); phase-7c:170's save-over path
  with no background (the same file rewritten, the thumbnail renamed; `saveWithABackground…` pins the composed canvas
  and its size).

### `saveOverAnUploadedCaptureRewritesTheFileOnlyAndMarksItsLinkStale(link:)` (S)
- Arguments: `nonisolated enum Link: CaseIterable, Sendable { case afterPhase3, beforePhase3 }`, giving `objectLocation:
  world.location` or `nil`.
- Entry: `actions.save` → `applyLocalEdit`; `recordLocalEdit` (CR:205-212) sets `uploadIsStale` because `linkURL`
  (CR:199) is the uploaded URL whether or not the location is known.
- Source: save-folder (`addSavedImage(uploadState: .uploaded(url: link, key: key), objectLocation:)`), opened from the
  file (EI:57: the save-folder file comes before the object).
- Sequence: open, `draw()`, `save()`.
- Asserts: first push `status == nil`, `available == all`, `saveCommand == .writeOver`; `save()` true; the file is blue;
  folder contents `["Shot.png"]`; record `uploadIsStale == true`, `uploadState == .uploaded(url: link, key: key)`,
  `objectLocation` as given; last push `status == EditorSaveTarget.uploadedCopyStaleNotice`; `uploadAttempts == 0`,
  `destination.state.withLock { $0.uploads.isEmpty }` (the link still serves what it served), `askedConfigs.isEmpty`,
  `world.clipboard.copies.isEmpty` (no owner). Ends with `settledEdit`.
- By hand / other seam: the subtitle as shown (glue, `EDPLACE`). The link still showing the original is the absence of
  a PUT.
- Covers: phase-4a:95, in part (`afterPhase3`); phase-4a:96, in part (`beforePhase3`).

### `saveOverALockedFileSaysNotSavedAndPutsTheEditOnTheClipboard` (S)
- Entry: `actions.save` → `applyLocalEdit`, whose write throws → `keepFailedEditOnClipboard` (+Editor:204-206, :226-240).
- Source: save-folder (`addSavedImage`), opened from the file, then the file made immutable:
  `FileManager.default.setAttributes([.immutable: true], ofItemAtPath:)`, with `defer` clearing it (registered after
  `defer { world.removeAll() }`, so it runs first), as CoordinatorRecordActionsTests.swift:192-193. An atomic write over
  an immutable file fails there (CoordinatorRecordActionsTests.swift:195-200).
- Sequence: open, lock, `draw()`, `save()`.
- Asserts: `save()` false; `try Data(contentsOf: file) == original`; `let error = world.notifier.errors.last`,
  `error.title == "Not saved"`, `error.message.hasSuffix(" The edited image is on the clipboard.")` and the message is
  longer than that suffix (the reason comes first, +Editor:239); `world.clipboard.copies == [.image]` (+Editor:229-230,
  `copy(image:pngData:scale:)`); `isBlue(png: world.clipboard.pngs[0])`; `coordinator.clipboardOwner ==
  EditorClipboard.Owner(recordID: id, changeCount: 1)` (+Editor:238); the record unchanged (`editedAt == nil`,
  `thumbnailFileName` as added); `world.logLines.contains { $0.hasPrefix("Save over failed: ") }` (+Editor:227);
  `editor.model.hasUnsavedChanges` (glue: false marks nothing saved). The write throws before `replaceThumbnail`, so no
  task outlives the test.
- By hand / other seam: the dot staying (glue, `EDPLACE`); Finder's Locked is the immutable flag.
- Covers: phase-4a:99, in part.

### `saveOnAFailedUploadOnlyCaptureRewritesPendingAndRetryUploadsTheEdit` (M, merged)
- Entry: `save()` → `editorSave` → `applyLocalEdit` `.pendingFile` (+Editor:196-198); then
  `coordinator.retryFailedUploads()` (+Upload:496-507) → `retry` (+Upload:512-544) → `uploadPayload(for:)`
  (+Upload:547-552, reads the pending file at +Upload:551).
- Source: `pending/`, upload only, upload failed: `let png = try png(width: 200, height: 100, scale: 2, white: true)`;
  `pending = try coordinator.pendingFiles.write(png, id: id, ext: "png")` (PendingFileStore.swift:21-24,
  `pending/<id>.png`); `CaptureRecord(id:, fileURL: pending, fileIsTemporary: true, pixelWidth: 200, pixelHeight: 100,
  appName: nil, uploadState: .failed(message: "Upload was interrupted."), byteCount: png.count)`. Source `.pendingFile`
  (EI:52). The white base lets the stroke be found in the pixels; `addPendingImage`'s red 4 by 2 record takes the same
  paths.
- Fakes: none (the standard destination succeeds; `existingKeys` empty, so the template key's HEAD says free).
- Sequence: open; `editor = openedEditor(id)`; `editor.model.commitNewShape(editor.model.makeStroke(.pencil, points:
  [CGPoint(x: 20, y: 20), CGPoint(x: 100, y: 60), CGPoint(x: 180, y: 20)])!)`; `await editor.save()`; `expected`;
  `let written = try Data(contentsOf: pending)`; `coordinator.retryFailedUploads()`; `try await eventually {
  coordinator.history.record(id: id)?.uploadedKey != nil }`.
- Asserts:
  - Opened from the pending file: `editor.representedURL == nil`, `editor.title == title(of: record)` (+Editor:77-79);
    first push `saveCommand == .writeOver`, `status == nil`, `available == [.save, .saveAs, .copy, .upload]` (no link:
    `.uploadAsNew` refused, EST:142).
  - After Save: true; `written != png`; `rgba(decoded(written).image) == rgba(expected)`; `pixel(decoded, x: 100, y: 60)`
    is the stroke's red (`r > 200`, `g < 100`, `b < 100`) where the base is white; the pending folder holds only
    `"\(id.uuidString).png"` (`contentsOfDirectory(coordinator.pendingFiles.directory)`); the record still
    `.failed(message: "Upload was interrupted.")`, `fileURL == pending`, `uploadIsStale == false` (no link, CR:205-212, CR:209-211),
    `byteCount == written.count`; `destination.state.withLock { $0.uploadAttempts } == 0`.
  - After Retry: `uploads.count == 1`, `uploads[0].data == written`, `uploads[0].contentType == "image/png"`; the record
    `uploadState == .uploaded(url: publicURL(k), key: k)` with `k = uploads[0].key` (FD:274-276), `fileURL == nil`
    (+Upload:652-654, +Upload:654, +Upload:669-671; no card shows, so the file is removed, not adopted, +DragOut:233); the pending file gone;
    `world.clipboard.copies == [.url(publicURL(k))]` (+Upload:699; no owner); `world.notifier.calls.contains(.uploaded(url:
    publicURL(k), copied: true))` (+Upload:703, Notifier.swift:176-178). Ends with `settledEdit` (the Save's thumbnail).
- By hand: nothing. Wi-Fi off is the record's failed state; Wi-Fi on and the bucket are the fake.
- Covers: phase-4a:98, full; phase-4b:107, full.

### `saveWithACropWritesTheCroppedSizeAtTheCapturesScaleAndReopensCropped(scale:)` (M)
- Arguments: `[CGFloat(1), CGFloat(2)]` for the scale (the line's 1x and 2x displays).
- Entry: `coordinator.openEditor(recordID:)` (+Editor:15), the fake's `save()` (the editor's ⌘S `.writeOver`, EWC:247-250)
  into `actions.save` → `editorSave` (+Editor:157) → `applyLocalEdit` (+Editor:181); then `editor.close()`
  (`windowWillClose` → `editorDidClose`, +Editor:469-476) and `openEditor` again.
- Source: a saved capture, never uploaded, in the save folder: `let folder = try world.storeSaveFolder()` before
  `makeCoordinator()`; `let png = try png(width: 1000, height: 600, scale: scale)`; `file = folder.appending(path:
  "Shot.png")`, `png.write(to: file)`; `CaptureRecord(id: id, fileURL: file, pixelWidth: 1000, pixelHeight: 600, appName:
  nil, byteCount: png.count)`, `coordinator.history.add(record)`. Source `.saveFolderFile` (EI:51-53), so the load runs
  in a task.
- Fakes: none scripted.
- Sequence: open; `editor = try await openedEditor(id)`; `crop(editor.model, to: CGRect(x: 100, y: 100, width: 800,
  height: 400), apply: false)`, check the readout, then `editor.model.applyCrop()` (Return); `let saved = await
  editor.save()`; `expected`; `editor.close()`; `coordinator.openEditor(recordID: id)`; `reopened = try await
  reopenedEditor(id, after: editor)`; `reopened.model.tool = .crop`.
- Asserts:
  - First push: `saveCommand == .writeOver` (EST:78-84), `available == all` minus `.uploadAsNew` (no link, EST:142),
    `status == nil` (EST:149-156).
  - The readout before Return: `CropGeometry.readout(for: try #require(editor.model.cropDraft)) == "800 × 400"`
    (TidyShot/Editor/Geometry/CropGeometry.swift:47-49); after Return `editor.model.document.crop == CGRect(x: 100, y: 100,
    width: 800, height: 400)` and `editor.model.tool == .redact` (the tool before Crop; the model opens with Redact,
    Model:126).
  - `saved == true`.
  - The file: `let written = try Data(contentsOf: file)`; `decoded(written)` has `image.width == 800`, `image.height ==
    400`, `scale == scale` (the line's `sips` pixel size); `abs(dpiWidth(of: written)! - 72 * scale) < 0.5` (144 at 2x,
    72 at 1x; ImageEncoder.swift:26); `rgba(decoded.image) == rgba(expected)` (Quick Look shows only the cropped
    picture).
  - No new file: `FileManager.default.contentsOfDirectory(atPath: folder.path(percentEncoded: false)) == ["Shot.png"]`.
  - The record: `pixelWidth == 800`, `pixelHeight == 400` (`recordLocalEdit`, CR:205-212, from +Editor:213-216),
    `byteCount == written.count` (+Editor:215).
  - Nothing uploaded: `world.factory.askedConfigs.isEmpty`, `uploadAttempts == 0`; `world.notifier.errors.isEmpty`.
  - After the close: `coordinator.editors[id] == nil` (+Editor:471-472).
  - The reopen (phase-4b:73): `world.editors.built.count == 2`; `reopened.model.base.width == 800`, `.height == 400`,
    `reopened.model.scale == scale`; `reopened.model.document == AnnotationDocument(annotations: [])` (no crop, nothing to
    select); `!reopened.model.hasUnsavedChanges` and, before setting the tool, `reopened.model.cropDraft == nil` (no crop
    pending, Model:101-105); after `tool = .crop`, `reopened.model.cropDraft == CGRect(x: 0, y: 0, width: 800, height:
    400)` (Crop starts from the whole picture, Model:131-135); `reopened.title == "Shot.png"` (+Editor:77-78).
  Ends with `settledEdit`.
- By hand: nothing. `sips` is the decode and the DPI read; Quick Look is the pixel comparison; the Retina display is the
  scale argument.
- Covers: phase-4b:71, full; phase-4b:73, full. It also reads the pixel size of phase-4b :100 (the thumbnail line), which
  is not among the 73 and is not marked from here.

### `saveWithTextEllipseAndCropWritesAllThreeIntoTheSameFile` (M)
- Entry: `openEditor(recordID:)`, the row's Annotate (RecentCapturesMenu.swift:113, `afterMenusClose { $0.openEditor
  (recordID: id) }`; the row and `afterMenusClose` are menu UI, the test starts at `openEditor`); then `save()`.
- Source: as above, `png(width: 400, height: 200, scale: 2, white: true)` at `<Saved>/Shot.png`, `CaptureRecord(id:,
  fileURL: file, pixelWidth: 400, pixelHeight: 200, appName: nil, byteCount: png.count)`.
- Fakes: none.
- Sequence: open; `editor = openedEditor(id)`; `let box = addText(editor.model, "Hello", at: CGPoint(x: 110, y: 70))`;
  `editor.model.commitNewShape(editor.model.makeAnnotation(.ellipse, from: CGPoint(x: 220, y: 40), to: CGPoint(x: 340,
  y: 140))!)`; `crop(editor.model, to: CGRect(x: 40, y: 20, width: 320, height: 160), apply: true)`; `await
  editor.save()`; `expected`.
- Asserts:
  - `editor.title == "Shot.png"`, `editor.representedURL == file` (+Editor:77-78).
  - `editor.model.document.annotations.count == 2` before the save (a text and an ellipse).
  - Saved `== true`; the same file: decoded `width == 320`, `height == 160`, `scale == 2`; `rgba(decoded) ==
    rgba(expected)`; listing `== ["Shot.png"]`.
  - The ellipse in the pixels: `pixel(decoded, x: 240, y: 24)` is the stroke colour, `r > 200`, `g < 100`, `b < 100` (the
    ellipse's top at image (280, 40 + 8 / 2), Rendering/AnnotationDrawing.swift:333-345 strokes inset by half of the 8 px
    width; minus the crop origin (40, 20)).
  - The text in the pixels: `changedPixels(decoded, in: TextLayout.frame(for: box).offsetBy(dx: -40, dy: -20), from:
    [255, 255, 255]) > 0` (TidyShot/Editor/Geometry/TextLayout.swift:68-75).
  - The record `pixelWidth == 320`, `pixelHeight == 160`; nothing uploaded (`askedConfigs.isEmpty`). Ends with
    `settledEdit`.
- By hand: nothing (the row's button is menu UI that calls `openEditor`).
- Covers: phase-4b:105, full.

### `saveWithABackgroundWritesTheComposedCanvasAndReopensFlat` (M)
- Entry: `openEditor(recordID:)`, `editor.model.setBackground(_:)` (Model:424-427), `editor.save()`; then
  `editor.close()` and `openEditor` again.
- Source: save folder: `world.storeSaveFolder()`, `addSavedImage(to:in:)`, plus `thumbnailFileName: try
  coordinator.thumbnails.write(Data("png".utf8), id: id)` (`"<id>.png"`, TS:20, :39-41) on the record.
- Fakes: none.
- Sequence and asserts:
  1. Open; `editor.draw()`; `editor.model.setBackground(background)`; `#expect(await editor.save())`.
  2. The file is the composed image ("open it"): decoded `width == 20`, `height == 18`; `pixel(file, x: 0, y: 0) ==
     [0, 255, 0, 255]`, the same at (7, 7) and (19, 17); `isBlue(pixel(file, x: 8, y: 8))`, `isBlue(pixel(file, x: 11,
     y: 9))`; `ImageEncoder.decode(...)?.scale == 1`. The fake's `export()` ran `model.renderExport()`, which composes on
     the background (Model:684-708), as EWC:301-317 does.
  3. The editor is clean: `!editor.model.hasUnsavedChanges` (glue: the fake's `markSaved`, EWC:288-296).
  4. The record follows: `pixelWidth == 20`, `pixelHeight == 18` (+Editor:213-216, CR:205-208); `byteCount ==
     Data(contentsOf: fileURL).count`; `editedAt == world.date`.
  5. The thumbnail: `try await eventually { coordinator.history.record(id: id)?.thumbnailFileName ==
     coordinator.thumbnails.fileName(for: id, editedAt: world.date) }`, which is `"<id>-1778307200000.png"` (TS:28-32;
     section 2). The old `"<id>.png"` is gone (+Editor:271-273). The new thumbnail decodes 20 by 18 (ThumbnailMaker never
     upscales, ThumbnailMaker.swift:15-18, :57-66) with `(0, 0) == [0, 255, 0, 255]` and a blue (8, 8): it shows the
     background.
  6. phase-7c:171: `editor.close()`; `coordinator.editors[id] == nil`; `coordinator.openEditor(recordID: id)`;
     `reopenedEditor`. Its model: `base.width == 20`, `base.height == 18`; `pixel(model.base, x: 0, y: 0) == [0, 255, 0,
     255]`, `isBlue(pixel(model.base, x: 8, y: 8))` (it opens as the composed image, flat); `model.document ==
     AnnotationDocument()`; `model.document.background == nil`, which is exactly the popover switch's getter
     (BackgroundPopoverView.swift:36-37), so the switch is off; `!model.hasUnsavedChanges`.
  7. phase-7c:171, "turning it on adds a second background around the first": `second.model.setBackground(background)`;
     `let export = try #require(await second.export())`; `export.image.width == 36`, `export.image.height == 34`
     (20 + 16, 18 + 16); `pixel(export.image, x: 0, y: 0)` and `(8, 8)` are `[0, 255, 0, 255]` (the new fill, then the
     first background's fill inside it); `isBlue(pixel(export.image, x: 16, y: 16))` (the capture, 8 + 8 in).
- By hand / other seam: phase-7c:170: the editor's clean state as the window shows it (glue, `EDPLACE`); Recent Captures
  drawing the thumbnail by hand. phase-7c:171: the popover's switch turned on, whose setter reads
  `AppSettings.shared.backgroundStyle` (`BGPOP`, BackgroundPopoverView.swift:36-38), and the switch drawn in the window
  (`EDPLACE`); "Write down whether that is what you expect" is Tim's call.
- Covers: phase-7c:170, in part (the composed canvas, the record's size, the thumbnail); phase-7c:171, in part.

### `saveOverTheFileRemovesTheDragCopyAndEveryReadGivesTheEdit` (M)
- Entry: `prepareDragFile(recordID:)` (a press on the card, +DragOut:14), `openEditor(recordID:)`, the editor's `save()`
  (+Editor:157-174 → `applyLocalEdit`, +Editor:181-221), then `imageData(of:)`, `copyImage(recordID:)`,
  `prepareDragFile` and `openEditor` again.
- Source: save folder: `world.storeSaveFolder()`, `addSavedImage(to:in:)` (`Shot.png`, red), `world.cards.showing.insert(id)`.
- Fakes: none.
- Sequence and asserts:
  1. `coordinator.prepareDragFile(recordID: id)`; `try await eventually { world.cards.dragFiles(for: id).last.flatMap {
     $0 } != nil }`; the staged file's bytes `== original` (copied under the folder's scope, +DragOut:28-33).
  2. `coordinator.openEditor(recordID: id)`; `openedEditor(id)`; `world.cards.calls.contains(.close(id, .editorOpened))`.
  3. `editor.draw()`; `#expect(await editor.save())`. At once: `!exists(coordinator.dragFiles.folder(for: id))`,
     `coordinator.dragFiles.stagedFile(id: id) == nil`, `world.cards.dragFiles(for: id).last == .some(nil)`
     (+Editor:210-211); `isBlue(png: Data(contentsOf: file))`.
  4. Every read gives the edit: `isBlue(png: try await coordinator.imageData(of: current))` (the file under the scope,
     +RecordActions:228-229); `await coordinator.copyImage(recordID: id)`, `isBlue(png: world.clipboard.pngs.last!)`;
     `world.cards.showing.insert(id)`, `coordinator.prepareDragFile(recordID: id)`, `eventually` a new non-nil drag file,
     its bytes `== Data(contentsOf: file)` ("the dragged file has the arrow too"); `editor.close()`,
     `coordinator.editors[id] == nil`, `coordinator.openEditor(recordID: id)`, `eventually { world.editors.built.count ==
     2 }`, the new editor's base is blue; `destination.state.withLock { $0.dataDownloadKeys }.isEmpty`;
     `world.factory.askedConfigs.isEmpty`. Ends with `settledEdit`.
- By hand / other seam: the card's Save As… panel (`SAVEAS`; only the read after it is here); the drop into another app
  by hand.
- Covers: phase-6a:199, in part (the "Save and copy image" half: the line's last sentence and its ⌘S). The upload-only
  half is `uploadOfAnUploadOnlyCaptureRemovesItsDragCopyAndEveryReadGivesTheEdit` (section 4).

### Save As…

### `saveAsOnAnUploadOnlyCaptureWritesThePNGAndUploadsNothing` (M)
- Entry: `actions.saveAsSuggestion()` (+Editor:104-107 → `saveAsSuggestion(recordID:)`, +RecordActions:321-331) and
  `actions.saveAs` → `editorSaveAs` (+Editor:283-304) → `writeSaveAsCopy` (+RecordActions:291-313).
- Source: download (`addUploadOnly`); a stored save folder (the suggestion's folder).
- Setup: `world.settings.fileNameTemplate = "shot-{counter}"` and `_ = world.settings.nextCounter()` before
  `makeCoordinator`, so the template name is `shot-1` (AppSettings.swift:461-470; EN:22-34 uses `currentCounter`, draws
  none).
- Sequence: open (download), `draw()`, read the suggestion, `saveAs(to: folder.appending(path: "shot-1.png"))`.
- Asserts: first push `available.contains(.save)` (Save is on), `saveCommand == .saveAs` (no file to write over, so ⌘S
  runs Save As…, EST:78-84), `status == EditorSaveTarget.noFileReason`; the suggestion `==
  EditorNaming.SaveAsSuggestion(fileName: "shot-1.png", directory: folder, mediaKind: .image)`; `saveAs` true;
  `isBlue(png:)` of `folder/shot-1.png`; `world.notifier.calls.contains(.saved(title: "Saved", file: "shot-1.png"))`;
  `!editor.model.hasUnsavedChanges` (glue); `coordinator.history.records.count == 1` and the record equals the one added
  (Save As touches no record, +Editor:277-282); `uploadAttempts == 0`; `world.clipboard.copies.isEmpty` (no new link);
  `world.settings.currentCounter == 1` (no counter drawn).
- By hand / other seam: the sheet opening with that name in that folder (`EDSAVEAS`); "Save is on" as the toolbar shows
  it and the dot (glue, `EDPLACE`; the push's `available` is the rule).
- Covers: phase-4a:97, in part.

### `saveAsElsewhereWritesA144DPICopyAndLeavesTheCaptureAlone` (M)
- Entry: `actions.saveAsSuggestion()`, `actions.saveAs` → `editorSaveAs` → `writeSaveAsCopy`.
- Source: save-folder (`addSavedImage(scale: 2)`: the PNG written at scale 2, so `loadImage` decodes scale 2 from its
  144 dpi, ImageEncoder.swift:42-48, as a 2x display's capture is).
- Sequence: open, `draw()`, read the suggestion, `saveAs(to: desktop("Edited.png"))`.
- Asserts: `editor.model.scale == 2`; the suggestion `== EditorNaming.SaveAsSuggestion(fileName: "Shot.png", directory:
  folder, mediaKind: .image)` (EN:26-27); `saveAs` true; the Desktop file is blue and `abs(dpiWidth(of:)! - 144) < 0.5`
  (as ImageEncoderTests.swift:32-39 reads it); `try Data(contentsOf: file) == original`;
  `coordinator.history.records.count == 1` and the record equals the one added; `world.cards.calls == [.close(id,
  .editorOpened)]` (the only card call on these paths, +Editor:91; `writeSaveAsCopy` touches no card);
  `world.shutterCount == 0`; `world.factory.askedConfigs.isEmpty`; `uploadAttempts == 0`; `.saved(title: "Saved", file:
  "Edited.png")`; `world.editors.built.count == 1` and the record's `fileURL` unchanged (the title comes from it,
  +Editor:77-79); `!editor.model.hasUnsavedChanges` (glue).
- By hand / other seam: the panel and the choice of folder and name (`EDSAVEAS`); the dot (glue, `EDPLACE`). `sips` is
  the DPI read.
- Covers: phase-4a:102, in part.

### `saveAsOntoItsOwnFileIsASave(uploaded:)` (S)
- Arguments: `[false, true]`: a saved never-uploaded capture, or one uploaded with `.uploaded(url: link, key: key)` at
  `world.location`.
- Entry: `actions.saveAs(image, file)` → `EditorSaveTarget.saveAsWritesOverOwnFile` (EST:50-56) true → `editorSave`
  (+Editor:286-290).
- Source: save-folder, opened from the file.
- Sequence: open, `draw()`, `saveAs(to: file)` (the record's own URL, as the panel returns it after Replace).
- Asserts: `saveAs` true; the file is blue; folder contents `["Shot.png"]`; `eventually { thumbnailFileName ==
  coordinator.thumbnails.fileName(for: id, editedAt: world.date) }`; `record.editedAt == world.date`; no `.saved` call in
  `world.notifier.calls` (Save posts none; the Save As path would, +RecordActions:309-311); uploaded: `uploadIsStale ==
  true` and last push `status == EditorSaveTarget.uploadedCopyStaleNotice`; never uploaded: `uploadIsStale == false` and
  last push `status == nil`; `uploadAttempts == 0`.
- By hand / other seam: the Replace confirmation (`EDSAVEAS`); the subtitle as shown (glue, `EDPLACE`).
- Covers: phase-4a:106, in part.

### `saveAsWithACropWritesACroppedCopyAndLeavesTheCaptureAlone` (S)
- Entry: `saveAs(to:)` → `actions.saveAs` → `editorSaveAs` (+Editor:283-304): not the own file
  (`EditorSaveTarget.saveAsWritesOverOwnFile` false, EST:50-56), encode, `writeSaveAsCopy` (+RecordActions:291-297).
- Source: saved, never uploaded: `png(width: 200, height: 100, scale: 2)` at `<Saved>/Shot.png`, `CaptureRecord(id:,
  fileURL: file, pixelWidth: 200, pixelHeight: 100, appName: nil, byteCount: png.count)`; keep `original = png` and
  `record`.
- Fakes: `url = desktop("Crop.png")` (`<root>/Desktop/Crop.png`), the URL the panel would return.
- Sequence: open; `editor = openedEditor(id)`; `crop(editor.model, to: CGRect(x: 40, y: 20, width: 120, height: 60),
  apply: false)` (⇧⌘S with the draft open; the export applies it, EWC:303); `let saved = await editor.saveAs(to: url)`;
  `expected`.
- Asserts: `saved == true`; the new PNG decoded `width == 120`, `height == 60`, `scale == 2`, `rgba == rgba(expected)`;
  the own file `try Data(contentsOf: file) == original`, listing of `folder` `== ["Shot.png"]`; the record unchanged,
  `coordinator.history.record(id: id) == record` (Save As touches no record, +Editor:277-282);
  `world.notifier.calls.contains(.saved(title: "Saved", file: "Crop.png"))` (+RecordActions:311-312, Show notification on
  by default, AppSettings.swift:269); `world.clipboard.copies.isEmpty` (no owner, so the clipboard rule does nothing,
  +Editor:437-438); `world.factory.askedConfigs.isEmpty`.
- By hand: nothing the line checks; the panel and ⇧⌘S's routing are `EDSAVEAS`'s and are not what the line names.
- Covers: phase-4b:76, full.

### `saveAsWithABackgroundWritesTheComposedImageAndLeavesTheCaptureAlone` (S)
- Entry: `editor.saveAs(to:)` → `actions.saveAs` → `editorSaveAs` (+Editor:283-304) → `writeSaveAsCopy`
  (+RecordActions:291-297).
- Source: save folder, as `saveWithABackground…`, with the thumbnail.
- Sequence: open; `draw()`; `setBackground(background)`; `let before = coordinator.history.record(id: id)`; `let target =
  desktop("Composed.png")`; `#expect(await editor.saveAs(to: target))`.
- Asserts: the file is the composed image: decodes 20 by 18, `(0, 0) == [0, 255, 0, 255]`, blue (8, 8); the capture and
  its record unchanged: `coordinator.history.record(id: id) == before`, `Data(contentsOf: fileURL) == original`, the save
  folder lists only `["Shot.png"]`, the thumbnail is still `"<id>.png"`; `world.notifier.calls.contains(.saved(title:
  "Saved", file: "Composed.png"))` (+RecordActions:311-313, Fakes `FakeNotifier.notifySaved`); `world.clipboard.copies
  .isEmpty` (no owner, +Editor:437-438); `world.factory.askedConfigs.isEmpty`.
- By hand / other seam: ⇧⌘S's panel (`EDSAVEAS`, EWC:259-264).
- Covers: phase-7c:172, in part.

### Copy and the clipboard rule

### `copyWithShowNotificationOffPostsNothing` (S, the minimal design's test 3, as built)
- Entry: `actions.copy` → `editorCopy` (+Editor:451-466).
- Source: retained (`latestCapture`) over a record with no file: `world.settings.showNotification = false` before
  `makeCoordinator()`; `CaptureRecord(fileURL: nil, pixelWidth: 4, pixelHeight: 2, appName: nil)` added;
  `coordinator.latestCapture = (id: record.id, image: ScaledImage(image: try CoordinatorWorld.image(width: 4, height:
  2), scale: 1))`.
- Sequence: `openEditor(recordID:)`; `editor = try #require(world.editors.editor(for: record.id))` with no await;
  `editor.draw()`; `await editor.copy()`.
- Asserts as built: opens at once (`openingEditorIDs.isEmpty`); `copies == [.pngAndTIFF]`; `clipboardOwner ==
  Owner(recordID: id, changeCount: world.clipboard.changeCount)`; `world.notifier.calls.isEmpty`; the editor stays changed
  and open. Added when moved: `isBlue(png: world.clipboard.pngs[0])`.
- By hand: nothing.
- Covers: phase-4a:112, full.

### `copyWithACropPutsTheCroppedImageAtPointSizeAndSaysImageCopied` (S)
- Entry: `copy()` → `actions.copy` → `editorCopy` (+Editor:451-466); then `actions.objectClipboard.copy` (+Editor:114).
- Source: saved, never uploaded: `png(width: 200, height: 100, scale: 2)` at `<Saved>/Shot.png`, as
  `saveAsWithACrop…`. `world.settings.showNotification` stays at its default `true` (AppSettings.swift:269).
- Fakes: none; reads `world.clipboard.pngs`.
- Sequence: open; `editor = openedEditor(id)`; `editor.model.commitNewShape(editor.model.makeAnnotation(.rectangle,
  from: CGPoint(x: 50, y: 30), to: CGPoint(x: 110, y: 70))!)`; `editor.model.selection = nil` (⌘C "with nothing
  selected"; `commitNewShape` selects the new shape, ToolFactory.swift:29); `crop(..., CGRect(x: 40, y: 20, width: 120,
  height: 60), apply: false)`; `await editor.copy()`; `expected`; then `editor.actions.objectClipboard.copy(Data("clip".utf8))`
  (what ⌘C does with an object selected, EWC:75, :7-12).
- Asserts, read after `copy()` and before the object copy (or, read once both have run, `copies.first == .pngAndTIFF`
  and `copies == [.pngAndTIFF, .annotationClip(Data("clip".utf8))]`, as the built test does):
  - `world.clipboard.copies == [.pngAndTIFF]`; `pngs.count == 1`; `decoded(pngs[0])` has `width == 120`, `height == 60`,
    `scale == 2`, and `abs(dpiWidth(of: pngs[0])! - 144) < 0.5` (Preview's point size is 60 by 30); `rgba(decoded) ==
    rgba(expected)`.
  - `coordinator.clipboardOwner == EditorClipboard.Owner(recordID: id, changeCount: 1)` (+Editor:457-458; the fake's first
    write returns 1, Fakes:186-191).
  - `world.notifier.calls == [.notice(title: "Image copied", body: "Shot.png")]` (+Editor:459-461: no key, so the file's
    name).
  - The file and the record unchanged: `Data(contentsOf: file) == png`, `history.record(id: id) == record`;
    `!editor.isClosed`.
  - After the object copy: `world.clipboard.copies == [.pngAndTIFF, .annotationClip(Data("clip".utf8))]` (Fakes:179-182);
    `pngs.count` still 1; `clipboardOwner` still
    `Owner(recordID: id, changeCount: 1)` (an object copy leaves it alone, +Editor:112-114); no new notifier call
    (`world.notifier.calls.count == 1`).
- By hand / other seam, phase-4b:92: which command reaches `actions.copy`: ⌘C with nothing selected
  (`CanvasView.responds(to: copy:)` false, so the window's `copy(_:)`), ⇧⌘C and the toolbar's Copy button
  (`copyImage(_:)`, EWC:207-215), and ⌘C copying the object when one is selected. Full when `EDPLACE` lets a test build
  the controller (`edplace-design.md` section 8).
- Covers: phase-4b:77, full; phase-4b:92, in part.

### `copyWithABackgroundPutsTheComposedCanvasOnTheClipboard` (S)
- Entry: `editor.copy()` → `actions.copy` → `editorCopy` (+Editor:451-466).
- Source: save folder (`addSavedImage`, `Shot.png`).
- Sequence: open; `draw()`; `setBackground(background)`; `await editor.copy()`.
- Asserts: `world.clipboard.copies == [.pngAndTIFF]`, `pngs.count == 1` (`clipboard.copy(pngData:tiffData:)`,
  +Editor:457); the PNG is the composed image (Preview's New from Clipboard reads the PNG): decodes 20 by 18 at scale 1,
  fill `[0, 255, 0, 255]` at (0, 0) and (19, 17), blue (8, 8) and (11, 9); `coordinator.clipboardOwner ==
  EditorClipboard.Owner(recordID: id, changeCount: world.clipboard.changeCount)` (+Editor:458);
  `world.notifier.calls.contains(.notice(title: "Image copied", body: "Shot.png"))` (+Editor:459-462; no key, so the file
  name); `editor.model.hasUnsavedChanges` still (Copy never marks saved, EWC:211; glue).
- By hand / other seam: ⇧⌘C, ⌘C with nothing selected (⌘C with a selection copies the object) and the toolbar button
  reaching `copyImage(_:)` (EWC:207-215): the controller's routing, full with `EDPLACE` (`edplace-design.md` section 8,
  `copyImageHandsTheActionsTheComposedImage`). Preview is the `pngs` decode.
- Covers: phase-7c:169, in part.

### `aSaveOrSaveAsTakesTheClipboardOnlyWhileItHoldsTheCapture(write:userCopied:)` (S)
- Arguments: `nonisolated enum Write: CaseIterable, Sendable { case save, saveAs }` × `[false, true]` (4 cases).
- Entry: `replaceClipboardIfStillOriginal` (+Editor:436-446) after `applyLocalEdit` (`.save`, +Editor:218) or after
  `writeSaveAsCopy` (`.saveAs`, +Editor:302).
- Source: retained over a save-folder record ("Save and copy image", copy image on: Annotate right after the capture).
- Setup, as the capture leaves the clipboard (+Save:28-37, :58, :65-67): `let count = world.clipboard.copy(pngData:
  original, tiffData: nil)` (1), `coordinator.clipboardOwner = EditorClipboard.Owner(recordID: id, changeCount: count)`;
  with `userCopied`, then `world.clipboard.setString("From TextEdit")` (TextEdit's copy: count 2). The capture's own
  copy is set up, not driven: it is in `save(_:intent:)`, which needs a `CaptureResult` (`TARGET`), and no test pins it
  today; the doc comment and the marks say so (design 6). The ownership rule the copy feeds is
  `EditorClipboardTests`' (EC:15-18).
- Sequence: open (retained), `draw()`, then `save()` or `saveAs(to: desktop("Shot.png"))`; `written` is the save-folder
  file's bytes or the Desktop file's.
- Asserts, `userCopied == false`: `copies == [.pngAndTIFF, .pngAndTIFF]`; `world.clipboard.pngs[1] == written` and
  `isBlue(png:)` of it; `clipboardOwner == Owner(recordID: id, changeCount: 2)`.
- Asserts, `userCopied == true`: `copies == [.pngAndTIFF, .string("From TextEdit")]`; `pngs.count == 1`;
  `clipboardOwner == Owner(recordID: id, changeCount: 1)`; `world.clipboard.changeCount == 2` (EC:15-18: a moved count is
  not the owner's).
- Both: the write itself happened (`written` is blue). `.save` cases end with `settledEdit`.
- By hand: nothing the line checks; Preview's New from Clipboard is the `pngs` decode, the Desktop is the URL passed
  in, and the capture step is set up (above).
- Covers: phase-4a:115, full `(.save, false)`; phase-4a:116, full `(.saveAs, false)`; phase-4a:117, full `(.saveAs,
  true)`; phase-4a:118, full `(.save, true)`.

## 4. CoordinatorEditorUploadTests.swift (new)

Header: "The editor's Upload through the editor seam: the local write first, then the live lane over the link's own key or
a new one; the window's close is the fake's (`closesWindow`), the controller's `performUpload` does not run." Each upload
test reads a template key `k` from `destination.state.withLock { $0.uploads.last!.key }` and its URL as `publicURL(k)`
(FD:274-276).

### Upload over a link, and the first upload

### `uploadWritesTheFileFirstThenReplacesTheLinksObject` (M, merged; the minimal design's test 2, with its edit changed)
- Entry: `upload()` → `actions.upload(image, false)` → `editorUpload` (+Editor:312-379): `uploadWrite` `.saveTarget`
  (EST:40-45) → `applyLocalEdit` over the save-folder file (`SaveLocation.overwriteScoped`, +Editor:192-195) →
  `EditorUploadPlan.plan` `.replace(key:)` (EUP:65-86, rule 7; EUP:85) → `startPlannedUpload` (+Upload:102-112) →
  `startUpload` with the fixed key and `Cache-Control: no-cache` (+Upload:170-172).
- Source: "uploaded with Upload and copy URL", its file kept in the save folder: `storeSaveFolder()`; `png = png(width:
  200, height: 100, scale: 2, white: true)` at `<Saved>/Shot.png`; `CaptureRecord(id:, fileURL: file, pixelWidth: 200,
  pixelHeight: 100, appName: nil, uploadState: .uploaded(url: link, key: key), objectLocation: world.location)` (as
  CoordinatorEditorTests.swift:50-53).
- Fakes: `destination.state.withLock { $0.holdingUploadsRemaining = 1 }` (FD:22-26) and `defer {
  destination.releaseUploads() }`.
- Sequence: open; `editor = openedEditor(id)`; `editor.model.commitNewShape(editor.model.makeStroke(.highlighter, points:
  [CGPoint(x: 50, y: 50), CGPoint(x: 150, y: 50)])!)`; `crop(..., CGRect(x: 40, y: 20, width: 120, height: 60), apply:
  false)` (phase-4b:74: "crop, then the Upload button", no Return); `let outcome = await editor.upload()`; `try await
  eventually { destination.state.withLock { $0.heldUploads.count } == 1 }`; checks while held; `expected`;
  `destination.releaseUploads()`; `try await eventually { coordinator.history.record(id: id)?.isUploading == false }`.
- Asserts:
  - First push: `status == nil`, `available == all`, `saveCommand == .writeOver`.
  - `outcome == EditorUploadOutcome(wroteLocally: true, enqueued: true)` (+Editor:378); `editor.isClosed`;
    `coordinator.editors[id] == nil` (the close reached `editorDidClose`); the model clean (glue).
  - While held (the file is written first): one held PUT; `decoded(Data(contentsOf: file))` is 120 by 60 at scale 2 with
    `rgba == rgba(expected)`; the record `pixelWidth == 120`, `pixelHeight == 60`, `priorUpload == PriorUpload(url:
    link, key: key, location: world.location, isReplace: true)` (EUP:116-121), `isUploading`; the editor heard it before
    it closed: `editor.pushes.last?.status == EditorAvailability.uploadingStatus` (`Uploading…`, EST:112) and `available
    == [.copy, .saveAs]` (+Upload:103-104 → `refreshOverlay` → `pushEditorState`, +Overlay:107-113);
    `world.cards.updates(for: id).contains(.uploading(fraction: 0))` (the row shows the upload running, +Upload:110 →
    +Overlay:108-110); `world.clipboard.copies.isEmpty`.
  - After the PUT: `uploads.map(\.key) == [key]` (the same link); `uploads[0].cacheControl == "no-cache"`;
    `uploads[0].data == Data(contentsOf: file)` (the bytes written); `decoded(uploads[0].data)` is 120 by 60, scale 2
    (phase-4b:74's `curl` and `sips`); the highlight in the object: `pixel(decoded, x: 60, y: 30)` has `b < 180` (the
    stroke at image (100, 50) less the crop origin; yellow at 0.45 multiplied over white leaves blue about 140,
    EditorPalette.swift:8, :30-32) and `pixel(decoded, x: 60, y: 2) == [255, 255, 255, 255]` (outside the 24 px stroke).
  - The record: `uploadState == .uploaded(url: link, key: key)`, `uploadIsStale == false`, `priorUpload == nil`
    (EUP:153-158), `pixelWidth == 120`, `pixelHeight == 60` (phase-4b:74's `history.json`).
  - `world.clipboard.copies == [.url(link)]` (+Upload:699; no owner, so the local write left the clipboard alone);
    `world.notifier.calls.contains(.notice(title: "Uploaded, URL copied", body: EditorUploadPlan.cacheNote))` (the first
    same-key replace of a launch, EUP:36, EUP:207-213, +Upload:685-702, the notice at +Upload:688-701); `destination.state.withLock { $0.deletedKeys
    }.isEmpty`. Ends with `settledEdit`.
- By hand / other seam: "the editor closes at once with no unsaved-changes sheet": the fake applied
  `closesWindow(documentUnchanged:)` (EUP:233-235); the controller's `window?.close()` (EWC:275-276) did not run (glue,
  `EDPLACE`). The link showing the redaction is the PUT body under the link's key.
- Covers: phase-4a:123, in part; phase-4b:74, full; phase-4b:106, in part.

### `uploadOfAnUploadOnlyCaptureWritesPendingThenReplacesItsKey` (M, merged)
- Entry: `openEditor` on an uploaded upload-only record: `.download` (EI:55-57) → `loadImage` (+Editor:48-65) →
  `imageData(of:)` → `downloadImage` (+RecordActions:215-255) → `FakeDestination.download(key:)` (FD:173-181); then
  `upload()`: `EditorSaveTarget.uploadWrite` `.newPendingFile` (EST:34-37, :40-45) → `pending/<id>.png`, the record
  switched to it (+Editor:336-356) → `applyLocalEdit` `.pendingFile` → `.replace(key:)`.
- Source: `CaptureRecord(id:, fileURL: nil, pixelWidth: 200, pixelHeight: 100, appName: nil, uploadState:
  .uploaded(url: link, key: key), objectLocation: world.location)`. No local file.
- Fakes: `destination.state.withLock { $0.downloadedData = try png(width: 200, height: 100, scale: 2, white: true);
  $0.holdingUploadsRemaining = 1 }` (set the PNG before the lock); `defer { destination.releaseUploads() }`.
- Sequence: open; `editor = openedEditor(id)`; `let box = addText(editor.model, "Edit", at: CGPoint(x: 80, y: 50))`;
  `crop(..., CGRect(x: 40, y: 20, width: 120, height: 60), apply: false)`; `outcome = await editor.upload()`; `eventually
  { heldUploads.count == 1 }`; checks while held, reading the pending file's bytes; `expected`; release; `eventually {
  record?.isUploading == false }`.
- Asserts:
  - The download: `destination.state.withLock { $0.dataDownloadKeys } == [key]`;
    `world.notifier.calls.contains(.notice(title: "Opening the capture…", body: "Downloading \(key)"))` (+Editor:48,
    +RecordActions:263-268).
  - The window: `editor.title == title(of: record)`, `editor.representedURL == nil` (+Editor:77-79);
    `editor.model.base.width == 200`, `.scale == 2`.
  - First push: `status == EditorSaveTarget.noFileReason` (EST:16, :22, :154), `saveCommand == .saveAs`, `available ==
    all`.
  - `outcome == EditorUploadOutcome(wroteLocally: true, enqueued: true)`; `editor.isClosed`; `editors[id] == nil`.
  - While held: the record `fileURL == pendingURL(coordinator, id)`, `fileIsTemporary == true`, `uploadIsStale == true`
    (CR:205-212, the link), `isUploading`; that file decodes to `rgba(expected)` at 120 by 60; `copies.isEmpty`.
  - After: `uploads.map(\.key) == [key]`, `uploads[0].cacheControl == "no-cache"`, `uploads[0].data` equals the pending
    bytes read while held; `decoded(uploads[0].data)` is 120 by 60 at scale 2 with `rgba == rgba(expected)`; the text in
    the object: `changedPixels(decoded, in: TextLayout.frame(for: box).offsetBy(dx: -40, dy: -20), from: [255, 255, 255])
    > 0`.
  - The record: `uploadState == .uploaded(url: link, key: key)`, `fileURL == nil`, `fileIsTemporary == false`
    (+Upload:652-654, :669-672; no card shows, +DragOut:233), the pending file gone, `uploadIsStale == false`
    (EUP:153-158), `pixelWidth == 120`, `pixelHeight == 60`.
  - `world.clipboard.copies == [.url(link)]`; `.notice(title: "Uploaded, URL copied", body: EditorUploadPlan.cacheNote)`
    posted. Ends with `settledEdit`.
- By hand / other seam: phase-4a:124's window closing (glue, `EDPLACE`); "the link serves" and "shows the redaction" are
  the PUT body under the same key.
- Covers: phase-4a:124, in part; phase-4b:75, full; phase-4b:108, full.

### `annotateTheNewestCardSaveThenUploadWritesTheFileThenUploadsAndCopiesTheURL` (L)
- Entry: `coordinator.openEditor(recordID:)` (+Editor:15), the call `.annotate` makes after a capture (+Save:68-70) and the
  card's Annotate makes after menu tracking (+Overlay:27, +Editor:68-70); then the editor's `save()` and `upload()` (the
  `EditorActions` closures, +Editor:100, :117-119).
- Source: retained, with a save-folder file, as a new "Save and copy image" capture leaves it: `let folder = try
  world.storeSaveFolder()`, then the coordinator; `addSavedImage(to:in: folder)` (`Shot.png`, red 4 by 2, `uploadState
  .none`); `world.cards.showing.insert(id)` (the card is up); `coordinator.latestCapture = (id: id, image:
  ScaledImage(image: try CoordinatorWorld.image(width: 4, height: 2), scale: 1))`, as `showOverlay(... retainsImage:
  true)` sets it (+Overlay:15-17; the test form is CoordinatorDeleteTests.swift:346-347); the clipboard as the capture's
  save left it: `let count = world.clipboard.copy(pngData: original, tiffData: nil)` and `coordinator.clipboardOwner =
  EditorClipboard.Owner(recordID: id, changeCount: count)` (+Save:57, :65-67). The capture itself is set up, not driven;
  it is the entry to the flow the line checks, so no seam is named for it (design 6).
- Fakes: none beyond the world.
- Sequence and asserts:
  1. `coordinator.openEditor(recordID: id)`, no await. Then at once (the `.retained` branch is synchronous,
     +Editor:22-24): `world.editors.editor(for: id)` is non-nil (required) and `coordinator.openingEditorIDs.isEmpty`
     ("opens without a pause": no load task, +Editor:25-29 not taken); `editor.model.base === image` (the retained
     `CGImage`, Model:174-176), `editor.model.scale == 1`; `editor.title == "Shot.png"`, `editor.representedURL == file`
     (+Editor:77-79); `editor.presentCount == 1`; `editor.pushes.first?.record == coordinator.history.record(id: id)`,
     `saveCommand == .writeOver` (EST:21-27, :78-84), `available == all` minus `.uploadAsNew` (no link, EST:142);
     `world.cards.calls.contains(.close(id, .editorOpened))` (+Editor:91) and `world.cards.showing.isEmpty`;
     `coordinator.latestCapture == nil` (the card's close reported through `onDidClose`, Fakes `FakeCards.close`,
     Coord:284, and `overlayDidClose` dropped the retained image, +Overlay:68, +Pins:75-79);
     `!coordinator.closedOverlays.ids.contains(id)` (+Editor:93; `.editorOpened` not restorable,
     QuickAccessController.swift:19-24); `destination.state.withLock { $0.dataDownloadKeys }.isEmpty`.
  2. `editor.draw()`; `#expect(coordinator.hasUnsavedEditors)` (+Editor:7-9; stand-in for the unsaved dot).
  3. `let saved = await editor.save()`: `saved == true`; `let written = try Data(contentsOf: file)`; `written !=
     original`; `isBlue(pixel(written, x: 0, y: 0))` and `isBlue(pixel(written, x: 3, y: 1))` (the file shows the edit;
     Quick Look stand-in); `FileManager.default.contentsOfDirectory(atPath: folder.path(percentEncoded: false)) ==
     ["Shot.png"]` (same file, no new one; `SaveLocation.overwriteScoped`, +Editor:192-195); nothing uploads:
     `world.factory.askedConfigs.isEmpty`, `uploadAttempts == 0`, `uploadState == .none`; small-tweaks:18, Save half:
     `byteCount == written.count` (+Editor:215); `!coordinator.hasUnsavedEditors` (the fake applied `markSaved` as
     `exportAndDeliver` does, EWC:288-296; glue); the clipboard rule replaced the capture's image with the edit:
     `world.clipboard.copies == [.pngAndTIFF, .pngAndTIFF]` and `world.clipboard.pngs.last == written` (+Editor:218,
     :436-446); `world.notifier.errors.isEmpty`.
  4. `world.date = world.date.addingTimeInterval(1)` (a second edit of the record, section 2), then `let outcome = await
     editor.upload()`: `outcome == EditorUploadOutcome(wroteLocally: true, enqueued: true)`
     (+Editor:378); `editor.isClosed` and `coordinator.editors[id] == nil` (the fake closed itself through
     `closesWindow(documentUnchanged: true)`, EUP:233-235, as EWC:275-276 does; the callback dropped it,
     +Editor:469-476); `world.factory.askedConfigs == [CoordinatorWorld.config]`.
  5. `try await eventually { coordinator.history.record(id: id)?.uploadedKey != nil }`, then: `let uploads =
     destination.state.withLock { $0.uploads }`; `uploads.count == 1`; `uploads[0].data == (try Data(contentsOf: file))`
     (the upload's local write rewrote the same bytes first, +Editor:333-335; the PUT body stands for the object the link
     serves); `isBlue(pixel(uploads[0].data, x: 0, y: 0))`; `uploads[0].cacheControl == nil` (a new object, not a
     replace: a never-uploaded record gives `.newObject(supersede: nil, notice: nil)`, EUP:69-71); `let url =
     publicURL(uploads[0].key)`; `uploadState == .uploaded(url: url, key: uploads[0].key)`; the URL replaced the
     clipboard: `world.clipboard.copies == [.pngAndTIFF, .pngAndTIFF, .pngAndTIFF, .url(url)]` (the third is the
     upload's local write applying the clipboard rule again, +Editor:218; the URL is `.uploaded`'s for a screenshot,
     +Upload:680-683, :697-699); `world.notifier.calls.contains(.uploaded(url: url, copied: true))` (+Upload:700-704,
     `notifyUploaded(url:)` is `copied: true`, Notifier.swift:174-177; Show notification defaults on,
     AppSettings.swift:269); small-tweaks:18, Upload half: `byteCount == uploads[0].data.count` (`.uploaded` stores the
     sent size, +Upload:666-668, counted at +Upload:192). Ends with `settledEdit`.
- By hand / other seam: coordinator-split:43: the close button's unsaved dot (`isDocumentEdited`, EWC:136-143) and the
  window closing (EWC:276) are the controller's glue, full with `EDPLACE`; the URL showing the stroke is the PUT body,
  and the real bucket stays by hand. phase-6b:118: reaching `save(_:intent:)` and the after-capture action running first (`TARGET`; the order is D,
  `CaptureIntentTests.annotateRunsTheAfterCaptureActionThenOpensTheEditor`), and the `action=pin` half (`PINS`).
- Note for small-tweaks:18: with Clop off the two sizes are the same number by construction (+Editor:215 and +Upload:192
  both count the one `png` from +Editor:323-325). That `.uploaded` writes the sent size over a different stored size is
  pinned by `CoordinatorUploadTests.aStoredUploadWhoseSourceMatchesResumes` and
  `anUploadedResumeClearsItsStateSidecarAndKeptCopy` (CoordinatorUploadTests.swift:88-111, :263-280), where the record
  starts at 1 byte. The line asks only that the row show the uploaded size after the upload, which this test reads; the
  row's text is `RecentCaptureFormatting.sizeText(record.byteCount)` (RecentCaptureFormatting.swift:56, :63-67), pinned by
  `RecentCaptureFormattingTests`. Full.
- Covers: coordinator-split:43, in part; small-tweaks:18, full (both halves; `saveWritesOverTheSaveFolderFile…` also pins
  the Save half from an editor opened on the file); phase-6b:118, in part (the annotate half's last step).

### `anUploadAfterTheCapturesOwnClosesAtOnceAndEndsWithTheLinkCopied` (M)
- Entry: the capture's own upload through `startUpload` (+Upload:138), then `actions.upload` → `.replace(key:)`.
- Setup ("Also copy image" on, `alsoCopyImageWhenUploading`, +Save:30-31): save-folder record with `uploadState:
  .uploading(fraction: 0)`; `world.clipboard.copy(pngData: original, tiffData: nil)` (1) and the owner at 1;
  `startUpload(recordID: id, payload: .data(original), destination: try #require(coordinator.makeDestination()))`;
  `eventually { isUploaded }`; `k1`, `url1` from the record; then `latestCapture` set (the card's retained image). The
  capture's copy is set up as +Save:30-31, :57-67 leave it (`TARGET`, design 6).
- Fakes: `holdingUploadsRemaining = 1` set after the first upload, `defer { destination.releaseUploads() }`.
- Sequence: open (retained), `draw()`, `upload()`; `eventually { heldUploads.count == 1 }`; release; `eventually {
  isUploaded }`.
- Asserts: after the first upload `copies == [.pngAndTIFF, .url(url1)]`; the editor's outcome `(true, true)`;
  `editor.isClosed` and `coordinator.editors[id] == nil` while the PUT is held (at once); while held `copies ==
  [.pngAndTIFF, .url(url1)]` (the local write leaves the URL: the count moved past the owner's, EC:15-18); after the
  release `copies == [.pngAndTIFF, .url(url1), .url(url1)]`, `uploadState == .uploaded(url: url1, key: k1)`,
  `uploads.map(\.key) == [k1, k1]`, `isBlue(png: uploads.last!.data)`. Ends with `settledEdit`.
- By hand / other seam: the window closing (glue, `EDPLACE`).
- Covers: phase-4a:120, in part.

### `withNoDestinationSaveTakesTheClipboardAndUploadIsRefused` (S)
- Entry: `actions.save` (the clipboard rule) and `actions.upload` → `makeDestination()` nil (+Upload:39-45) → `Upload not
  configured` (+Editor:317-320).
- Setup: `try world.credentials.delete(account: KeychainCredentialStore.defaultAccount)` (Forget Credentials; the store
  then loads nil, so `loadCredentials` returns nil without the once-per-launch warning, +Upload:49-67). The capture as
  "Upload and copy URL" leaves it with no destination: save-folder record with `uploadState: .none` (+Save:164-168), the
  image on the clipboard and owned (`copyImageNow = true` with no destination, +Save:32-34): `world.clipboard.copy(pngData:
  original, tiffData: nil)` and the owner at count 1 (set up, not driven: `TARGET`, design 6).
- Source: retained over that record.
- Sequence: open, `draw()`, `save()`, `try await settledEdit(coordinator, id)` (the Save's thumbnail task names its file
  at a later turn, +Editor:217, :249-275, and the `upload()` below suspends several times before it is refused, so a
  record read without this wait can differ from the one read at the end), then read `saved = Data(contentsOf: file)`
  and the record, `draw()` again, `upload()`.
- Asserts: `save()` true; `copies == [.pngAndTIFF, .pngAndTIFF]` and `pngs[1] == saved` (the redacted image); `upload()`
  `== .refused`; `world.notifier.errors.last` is `("Upload not configured", AppCoordinator.uploadNotConfiguredBody)` =
  `Set up a destination in Settings > Upload, then upload again.` (+Upload:34); `Data(contentsOf: file) == saved` and the
  record equals the one read after the save (nothing written, +Editor:316); `copies.count == 2`;
  `world.factory.askedConfigs.isEmpty`; `!editor.isClosed`, `coordinator.editors[id] === editor`,
  `editor.model.hasUnsavedChanges` (`.refused` neither marks saved nor closes, EUP:224-235).
- By hand / other seam: the window staying open (glue, `EDPLACE`).
- Covers: phase-4a:119, in part.

### `uploadAsNewWithoutALinkIsRefusedAndUploadMakesTheFirstLink` (M)
- Entry: `actions.upload(image, true)` → `refuseUpload(.uploadAsNew)` (+Editor:315, :382-388); then `actions.upload(image,
  false)` → `.newObject(supersede: nil, notice: nil)` (EUP:69-71).
- Source: save-folder, never uploaded, opened from the file.
- Sequence: open, `draw()`, `upload(asNew: true)`, `upload()`, `eventually { isUploaded }`.
- Asserts: first push `available == all` minus `.uploadAsNew`; `upload(asNew: true)` `== .refused`, errors.last `("Not
  uploaded", "This capture has no link yet. Use Upload.")` (EST:116), the file unchanged, `!editor.isClosed`,
  `uploadAttempts == 0`; `upload()` `(true, true)`, `editor.isClosed`; the file is blue (written first); record
  `uploadState == .uploaded(url: publicURL(k), key: k)`, `objectLocation == world.location`, `uploadIsStale == false`;
  `uploads.count == 1`; `copies == [.url(publicURL(k))]`; `world.notifier.calls.contains(.uploaded(url: publicURL(k),
  copied: true))` (+Upload:702-704, Notifier.swift:176-178); no `New link` notice. Ends with `settledEdit`.
- By hand / other seam: ⌥⌘U refused by the window's validation (`EDPLACE`; EWC:426-427 through `EditorWindow.send`,
  EditorWindow.swift:41-48) and its beep (`BEEP`, EditorWindow.swift:45); this test pins the coordinator's write-time
  refusal behind the gate (+Editor:315, :382-388), which posts the notice the window's beep never lets happen. Closing
  (glue, `EDPLACE`).
- Covers: phase-4a:127, in part.

### `uploadOfAPrePhase3CaptureMakesANewLinkAndDeletesNothing` (S)
- Entry: `actions.upload` → `.newObject(supersede: nil, notice: legacyNotice)` (EUP:72-74) → `notify(title: "New link",
  body:)` (+Editor:369-370).
- Source: save-folder file of a record `.uploaded(url: link, key: key)` with `objectLocation: nil`.
- Sequence: open, `draw()`, `upload()`, `eventually { coordinator.history.record(id: id)?.uploadedKey.map { $0 != key }
  == true }` (the record is `.uploading` until then).
- Asserts: `world.notifier.calls.contains(.notice(title: "New link", body: "The earlier upload stays in the bucket."))`
  (EUP:29); `k != key`; `uploadState == .uploaded(url: publicURL(k), key: k)`, `objectLocation == world.location`;
  `priorUpload == nil` and `supersededObjects.isEmpty` (EUP:108-130: a link with no location keeps no prior);
  `destination.state.withLock { $0.deletedKeys.isEmpty }` (nothing to supersede, so the old object stays: `curl -I` would
  still give 200); `copies.last == .url(publicURL(k))`. Ends with `settledEdit`.
- By hand: nothing (`curl -I` is the empty DELETE list).
- Covers: phase-4a:129, full.

### `uploadAfterTheDestinationChangedGoesToTheNewBucketAndDeletesTheOldObject` (M)
- Entry: `actions.upload` → `.newObject(supersede: ObjectRef(key: key, location: world.location), notice:
  destinationChangedNotice)` (EUP:78-81), then `deleteSupersededObjects(of:)` (+Editor:396-427) at the old location
  (+Upload:707).
- Source: save-folder file of a record `.uploaded(url: link, key: key)` at `world.location`, opened from the file.
- Setup after the open: `let second = S3DestinationConfig(endpoint: "https://s3.us-west-2.amazonaws.com", region:
  "us-west-2", bucket: "second.tky.io", publicURLTemplate: "https://second.tky.io/{key}")`; `let other =
  FakeDestination()`; `world.factory.add(other, at: ObjectLocation(config: second))` (Fakes, `FakeDestinationFactory`;
  CoordinatorDeleteTests.swift:176); `world.settings.s3Config = second`; `coordinator.destinationDidChange()` (+Upload:78).
- Sequence: `draw()`, `upload()`, `eventually { other.state.withLock { $0.uploads.count } == 1 }`, `eventually {
  destination.state.withLock { $0.deletedKeys } == [key] }`, `eventually { record.supersededObjects.isEmpty }`.
- Asserts: `world.notifier.calls.contains(.notice(title: "New link", body: "The destination changed, so this uploads as a
  new link."))` (EUP:27); the new key `k` (from `other.uploads.last!.key`) `!= key`; record `uploadState ==
  .uploaded(url: publicURL(k), key: k)` (the fake's URL shape, FD:274-276), `objectLocation == ObjectLocation(config:
  second)`, `priorUpload == nil`; `destination.state.withLock { $0.uploads.isEmpty }`; `other.state.withLock {
  $0.deletedKeys.isEmpty }`; `world.factory.askedLocations.contains(world.location)` (the DELETE signed for the old
  bucket). Ends with `settledEdit`.
- By hand: nothing (the second bucket is the second fake).
- Covers: phase-4a:130, full.

### `anUploadedCaptureReopensFlatWithItsMarksInThePixels` (M)
- Entry: `upload()` on a saved, never-uploaded capture (`.saveTarget`, then `.newObject(supersede: nil, notice: nil)`,
  EUP:69-71) and, once `.uploaded`, `openEditor` again (`.saveFolderFile`).
- Source: `storeSaveFolder()`; `png(width: 200, height: 100, scale: 2, white: true)` at `<Saved>/Shot.png`;
  `CaptureRecord(id:, fileURL: file, pixelWidth: 200, pixelHeight: 100, appName: nil, byteCount: png.count)`.
- Fakes: none.
- Sequence: open; `editor = openedEditor(id)`; `editor.model.commitNewShape(editor.model.makeAnnotation(.spotlight, from:
  CGPoint(x: 20, y: 20), to: CGPoint(x: 80, y: 60))!)`; `let counter = editor.model.makeAnnotation(.counter, from:
  CGPoint(x: 150, y: 50), to: CGPoint(x: 150, y: 50))!`, `commitNewShape(counter)`; `outcome = await editor.upload()`;
  `expected`; `try await eventually { coordinator.history.record(id: id)?.uploadedKey != nil &&
  coordinator.history.record(id: id)?.isUploading == false }`; `coordinator.openEditor(recordID: id)`; `reopened =
  reopenedEditor(id, after: editor)`.
- Asserts:
  - Before the upload: `editor.model.document.spotlights.count == 1` and one `.counter` with `number == 1`, `diameter ==
    64` (32 pt × 2, Model:279-284, EditorPalette.swift:39-40), `center == CGPoint(x: 150, y: 50)`
    (TidyShot/Editor/Geometry/CounterLayout.swift:38-44).
  - `outcome == EditorUploadOutcome(wroteLocally: true, enqueued: true)`, `editor.isClosed`.
  - `uploads.count == 1`, `uploads[0].data == Data(contentsOf: file)` (Save and Upload wrote the same bytes);
    `record.uploadedKey == uploads[0].key`.
  - The reopen: `reopened.model.document.annotations.isEmpty` (no spotlight or counter left to select);
    `rgba(reopened.model.base) == rgba(expected)` (the marks are in the pixels); with the default dim 0.5
    (AnnotationDocument.swift:21-23): `pixel(reopened.model.base, x: 50, y: 40) == [255, 255, 255, 255]` (inside the
    hole), each of r, g, b of `pixel(..., x: 100, y: 90)` in `120...135` (dimmed white), and `pixel(..., x: 130, y: 50)`
    the counter's fill (`r > 230`, `g < 90`, `b < 90`; rgb(255, 59, 48) drawn above the dim,
    AnnotationDrawing.swift:284-298, 20 px left of the centre, clear of the 3 px ring and the digit).
  - Ends with `settledEdit`.
- By hand: nothing; the Recent Captures row's Annotate is `afterMenusClose { $0.openEditor }`
  (RecentCapturesMenu.swift:113).
- Covers: phase-4c:179, full.

### Failed replaces and the folder change

### `aFailedReplaceKeepsTheLinkAndTheEditAndTheRightKeyReplacesIt` (M)
- Entry: `actions.upload` → `.replace(key:)`; the lane's `.failed` with a `priorUpload` → `applyingFailure` (EUP:165-183;
  +Upload:708-719); `copyLinkOrFile(recordID:)` (+RecordActions:9-20); a second `openEditor` and upload.
- Source: save-folder file of a record `.uploaded(url: link, key: key)` at `world.location`.
- Fakes: `destination.state.withLock { $0.failuresRemaining = 1; $0.failure = .httpStatus(403, body:
  "SignatureDoesNotMatch: The request signature we calculated does not match the signature you provided.") }` (what a
  wrong secret gives; FD:12-13, :214-222).
- Sequence: open, `draw()`, `upload()`; `eventually` on the error below; `copyLinkOrFile(recordID: id)`; `openEditor(id)`,
  `reopened = reopenedEditor(id, after: editor)`; `world.date = world.date.addingTimeInterval(1)` (a second edit,
  section 2); `reopened.upload()` (no new drawing: "the right key, ⌘U"); `eventually { record.uploadIsStale == false }`;
  `settledEdit`.
- Asserts:
  - The first upload: `(true, true)`, `editor.isClosed`; `world.notifier.calls.contains(.error(title: "Not uploaded",
    message: "Upload failed. The link still shows the earlier image."))` (EUP:31, +Upload:719);
    `destination.state.withLock { $0.attemptKeys } == [key]` (one attempt: a 403 is not retried, Dest:177-181); record
    `uploadState == .uploaded(url: link, key: key)`, `objectLocation == world.location`, `uploadIsStale == true`,
    `priorUpload == nil`; the file is blue (written before the PUT).
  - The row: `copies == [.url(link)]` after `copyLinkOrFile`.
  - The reopen: `world.editors.built.count == 2`, `reopened !== editor`; `isBlue(reopened.model.base)` (the file holds the
    edit); first push `status == EditorSaveTarget.uploadedCopyStaleNotice`.
  - The right key: `(true, true)`; `uploadState == .uploaded(url: link, key: key)` (the same URL); `uploads.map(\.key) ==
    [key]`, `attemptKeys == [key, key]`; `isBlue(png: uploads.last!.data)`; `copies == [.url(link), .url(link)]`;
    `.notice(title: "Uploaded, URL copied", body: EditorUploadPlan.cacheNote)` posted once.
- By hand / other seam: closing and the subtitle as shown (glue, `EDPLACE`). The link is the PUT body. The notification's
  title is `Not uploaded`; the line quotes its body (harness D14).
- Covers: phase-4a:131, in part.

### `aFailedReplaceOfAnUploadOnlyCaptureKeepsPendingAcrossARelaunchUntilTheNextUpload` (L, merged)
- Entry: as `uploadOfAnUploadOnlyCaptureWritesPendingThenReplacesItsKey` for the open and the first upload; the failure
  through `handle(.failed)` with a `priorUpload` (+Upload:708-719, `applyingFailure`, EUP:165-183); a second coordinator
  over the same world for the relaunch (`world.makeCoordinator()` then `history.load()`, as
  CoordinatorOverlayTests.swift:25-26 and CoordinatorUploadTests.swift:745-746; `start()` is not called, section 2);
  `copyLinkOrFile(recordID:)` (+RecordActions:9-20); `openEditor` from the pending file; `upload()` again.
- Source: the upload-only, uploaded record (`fileURL: nil`, `.uploaded(url: link, key: key)`, `objectLocation:
  world.location`), 200 by 100.
- Fakes: `destination.state.withLock { $0.downloadedData = png(width: 200, height: 100, scale: 2, white: true);
  $0.failuresRemaining = 10; $0.failure = .httpStatus(403, body: "SignatureDoesNotMatch") }` (the wrong secret, FD:12-13,
  :214-221). Later `failuresRemaining = 0` (the right key).
- Sequence:
  1. (phase-4b:112) `coordinator.destinationDidChange()` (Settings > Upload's Save, +Upload:78-94; no queue yet, so only
     the cards' Trim refresh); open; `editor = openedEditor(id)`; `box = addText(editor.model, "Edit", at: CGPoint(x: 80,
     y: 50))`; `crop(..., CGRect(x: 40, y: 20, width: 120, height: 60), apply: false)`; note the readout; `outcome = await
     editor.upload()`; `expected`; `try await eventually { world.notifier.calls.contains(.error(title: "Not uploaded",
     message: EditorUploadPlan.failedReplaceMessage)) }`; `try await eventually { coordinator.history.record(id:
     id)?.thumbnailFileName != nil }` (the edit's thumbnail task, +Editor:249-275, has written history before the
     relaunch reads it).
  2. (relaunch) `try #require(coordinator.history.record(id: id)?.isUploading == false)` (the first coordinator is
     quiescent, section 2: no upload running, its thumbnail named in step 1); `let relaunched =
     world.makeCoordinator(); relaunched.history.load()`. Nothing below calls `coordinator` or runs `world.clock`.
  3. (phase-4b:113, phase-4a:133's reopen) `relaunched.copyLinkOrFile(recordID: id)`; `relaunched.openEditor(recordID:
     id)`; `reopened = try await reopenedEditor(id, after: editor)`.
  4. (phase-4b:114, phase-4a:133's right key) `world.date = world.date.addingTimeInterval(1)` (a second edit);
     `destination.state.withLock { $0.failuresRemaining = 0 }`; `relaunched.destinationDidChange()`; `outcome2 = await
     reopened.upload()`; `try await eventually { relaunched.history.record(id: id)?.isUploading == false &&
     relaunched.history.record(id: id)?.fileURL == nil }`; at the end `settledEdit(relaunched, id)`.
- Asserts:
  - 1: `CropGeometry.readout(for: editor.model.cropDraft!) == "120 × 60"` before the upload; `outcome ==
    EditorUploadOutcome(wroteLocally: true, enqueued: true)`, `editor.isClosed`, `coordinator.editors[id] == nil` (the
    line's "the editor closes"); one attempt only: `uploadAttempts == 1`, `attemptKeys == [key]`, `uploads.isEmpty` (a 403
    is not retried, Dest:177-180, UQ:193; section 8); the notice is `.error(title: "Not uploaded", message: "Upload
    failed. The link still shows the earlier image.")` (EUP:31, +Upload:719), and no `errors` entry has the title `Upload
    failed` (that is `markFailed`'s, +Upload:586-591, for a record with no link); the record: `uploadState ==
    .uploaded(url: link, key: key)`, `objectLocation == world.location`, `priorUpload == nil`, `uploadIsStale == true`,
    `fileIsTemporary == true`, `fileURL == pendingURL(coordinator, id)`, `keepsUnuploadedEdit == true` (CR:260),
    `pixelWidth == 120`, `pixelHeight == 60`; the pending file decodes to `rgba(expected)`.
  - 2: `relaunched.history.record(id: id)` has the same `uploadState`, `fileURL`, `fileIsTemporary`, `uploadIsStale`.
  - 3: `world.clipboard.copies == [.url(link)]` (the row still copies the old URL: `linkURL`, CR:199);
    `world.editors.built.count == 2`; `reopened.title == title(of: record)`, `reopened.representedURL == nil`;
    `reopened.model.base.width == 120`, `.height == 60`, `.scale == 2`, `rgba(reopened.model.base) == rgba(expected)` (the
    edit with the text, at the cropped size); `reopened.model.document == AnnotationDocument(annotations: [])`;
    `dataDownloadKeys == [key]` (only the first open downloaded; the reopen read the pending file, EI:52); first push
    `status == EditorSaveTarget.uploadedCopyStaleNotice` (`The uploaded copy still shows the original. Upload to replace
    it.`, EST:19, :58-61, :153), `available == all`, `saveCommand == .writeOver`.
  - 4: `outcome2 == EditorUploadOutcome(wroteLocally: true, enqueued: true)`, `reopened.isClosed`; `uploads.map(\.key) ==
    [key]` (the same URL), `uploads[0].cacheControl == "no-cache"`, `decoded(uploads[0].data)` 120 by 60 at scale 2 with
    `rgba == rgba(expected)` and `changedPixels(..., TextLayout.frame(for: box).offsetBy(dx: -40, dy: -20), from: [255,
    255, 255]) > 0`; the pending file gone; the record `uploadState == .uploaded(url: link, key: key)`, `fileURL == nil`,
    `uploadIsStale == false`, `pixelWidth == 120`, `pixelHeight == 60`, `byteCount == uploads[0].data.count`
    (+Editor:215, +Upload:666-668); `world.clipboard.copies == [.url(link), .url(link)]` (the row's copy, then the
    upload's; no owner); the relaunched coordinator's first replace posts `.notice(title: "Uploaded, URL copied", body:
    EditorUploadPlan.cacheNote)` (`postedCacheNote` is per coordinator, AppCoordinator.swift:188).
- By hand / other seam: phase-4b:112's and phase-4a:133's window closing (the fake's `closesWindow`, EWC:275-276 not run;
  `EDPLACE`) and the real quit; phase-4b:113's and phase-4a:133's subtitle as the window shows it (EWC:172-175 sets
  `window.subtitle` from the same `EditorAvailability.status` the push reads; `EDPLACE`). Entering the key in Settings
  writes the Keychain, which no test touches; the scripted 403 stands for it. The link is the PUT body.
- Note: phase-4a:133's reopen happens in the same app session and phase-4b:113's after a relaunch; this test reopens on
  the relaunched coordinator, which reads the history file the first one wrote, so it pins the stored state as well as
  the reopen.
- Covers: phase-4a:133, in part; phase-4b:112, in part; phase-4b:113, in part; phase-4b:114, full.

### `aFailedReplaceAfterAFolderChangeKeepsTheEditInPendingUntilTheNextUpload` (L)
- Entry: as `aFailedReplaceKeepsTheLink…`, through `.newPendingFile` because the file is outside the current folder
  (EST:21-27, :40-45).
- Setup: `folderA = world.storeSaveFolder()`; `folderB = <root>/Other/`, created; a record `.uploaded(url: link, key:
  key)` at `world.location` with its file `folderA/Old.png` (`addSavedImage(in: folderA, name: "Old.png", …)`);
  `destination.state.withLock { $0.downloadedData = original }` too; then `try world.saveLocation.store(folderB)`
  (Choose… another folder) before the open.
- Source: `EditorInput.source` is `.download` (outside B, EI:52-57); `imageData(of:)` tries the local file first
  (+RecordActions:224-236), which the test host can read, so the test asserts only the decoded size (4 by 2), not which
  path served it.
- Fakes: the 403 as above, once.
- Sequence: open, `draw()`, `upload()`; `eventually` on `Not uploaded`; `retryFailedUploads()`; then `openEditor(id)`,
  `reopened = reopenedEditor(id, after: editor)`, `world.date = world.date.addingTimeInterval(1)` (a second edit),
  `reopened.upload()`, `eventually { record.uploadIsStale == false }`; then `world.saveLocation.store(folderA)` (choose
  the original again); `settledEdit`.
- Asserts:
  - After the failure: `Data(contentsOf: folderA/Old.png) == original` (the old folder's file is not rewritten);
    `isBlue(png:)` of `pendingURL(coordinator, id)`; record `fileURL == pendingURL`, `fileIsTemporary`, `uploadIsStale`,
    `keepsUnuploadedEdit` (CR:260), `uploadState == .uploaded(url: link, key: key)`.
  - Retry Failed Uploads: `coordinator.history.failedRecords.isEmpty` (the reason it does nothing, HS:127-129) and,
    read synchronously right after `retryFailedUploads()`, `record.isUploading == false` and `uploadState ==
    .uploaded(url: link, key: key)` (a retry would have flipped both at once, through `startingRetry` and
    `startUpload`, +Upload:496-505, :534-541), and the pending file still there (section 8). A count of PUT attempts
    read there would pass even if Retry had started one, since the PUT comes later in the lane.
  - The next upload: the reopened editor's model is blue (read from `pending/`, EI:52); its first push `status ==
    uploadedCopyStaleNotice`; outcome `(true, true)`; `uploadState == .uploaded(url: link, key: key)`; `uploads.map(\.key)
    == [key]`, its data blue; the pending file gone, `fileURL == nil`; `folderA/Old.png` still `original`.
- By hand / other seam: closing (glue, `EDPLACE`). The line's own last step needs Tim's call (section 8).
- Covers: phase-4a:132, in part.

### `aNewSaveFolderReachesTheOpenEditorAndUploadGoesThroughPending` (L)
- Entry: `observeSaveFolderForEditors` (+Editor:137-152; started only by `presentEditor`, +Editor:87) on
  `world.saveLocation.store(_:)`; `actions.save` refused by `applyLocalEdit`'s plan (+Editor:191, :199-202);
  `actions.upload` `.newPendingFile`; a second editor after the folder is chosen again.
- Setup: `folderA = world.storeSaveFolder()`, `folderB = <root>/Other/` created; `addSavedImage(in: folderA)` (never
  uploaded); a second capture `addSavedImage(in: folderA, name: "Other.png")`.
- Fakes: `holdingUploadsRemaining = 1`, `defer { destination.releaseUploads() }`.
- Sequence: open the first; `try world.saveLocation.store(folderB)`; `eventually { editor.pushes.last?.saveFolder ==
  folderB }`; `draw()`; `save()`; `upload()`; `eventually { heldUploads.count == 1 }`; release; `eventually { isUploaded
  }`; `try world.saveLocation.store(folderA)`; open the second, `second = openedEditor(otherID)`, `second.draw()`,
  `second.save()`.
- Asserts:
  - Before: first push `saveCommand == .writeOver`, `status == nil`.
  - At the folder change, without any other call: last push `status == EditorSaveTarget.outsideFolderReason` = `The file
    is outside the current save folder, so it is not saved over.`, `saveCommand == .saveAs` (⌘S would open the panel),
    `available.contains(.save)`.
  - A Save that reaches the coordinator anyway: `save()` false, errors.last `("Not saved",
    EditorSaveTarget.outsideFolderReason)`, `folderA/Shot.png == original`.
  - ⌘U: `(true, true)`, `editor.isClosed`; while held `folderA/Shot.png == original`, `pendingURL` exists and is blue,
    record `fileURL == pendingURL`, `fileIsTemporary`; after the release the pending file is gone, `fileURL == nil`,
    `uploadState == .uploaded(url: publicURL(k), key: k)`, `folderA/Shot.png == original`.
  - Back in folder A: the second editor's first push `saveCommand == .writeOver`, `status == nil`; `second.save()` true;
    `folderA/Other.png` is blue; no new `Not saved` error. Ends with `settledEdit` for both records.
- By hand / other seam: ⌘S's panel and its Cancel (`EDSAVEAS`); ⌘W's Save opening the panel (`CLOSESHEET` and
  `EDSAVEAS`); the subtitle as shown and closing (glue, `EDPLACE`).
- Covers: phase-4a:148, in part.

### The drag copy

### `uploadOfAnUploadOnlyCaptureRemovesItsDragCopyAndEveryReadGivesTheEdit` (L)
- Entry: `coordinator.openEditor(recordID:)` (the card's Annotate, after the upload) and the editor's `upload()`
  (+Editor:312-379); then `coordinator.imageData(of:)` (+RecordActions:215-238), `copyImage(recordID:)`
  (+RecordActions:88-106), `prepareDragFile(recordID:)` (+DragOut:14-64) and `openEditor` again.
- Source: download, read from the drag copy: `addPendingImage(to:)` (red 4 by 2), `world.cards.showing.insert(id)`,
  `coordinator.retryUpload(recordID: id)` (+Upload:462-474), `try await eventually { coordinator.history.record(id:
  id)?.uploadedKey != nil }`. That leaves `fileURL == nil` and the pending file moved to `Drag/<id>/<key's last
  component>` (+Upload:651-654, +DragOut:232-246), as
  `CoordinatorUploadTests.anUploadedUploadOnlyImageMovesToItsDragFolderOnlyWithACard` asserts
  (CoordinatorUploadTests.swift:290-313). `let k = record.uploadedKey`.
- Fakes: after the first upload, `destination.state.withLock { $0.holdingUploadsRemaining = 1 }` and `defer {
  destination.releaseUploads() }` (FD:26, :256-264).
- Sequence and asserts:
  1. `coordinator.openEditor(recordID: id)`; `openedEditor(id)`. `destination.state.withLock { $0.dataDownloadKeys
     }.isEmpty` (the load read the drag copy, +RecordActions:233-236).
  2. `editor.draw()`; `let outcome = await editor.upload()`: `outcome == EditorUploadOutcome(wroteLocally: true, enqueued:
     true)`; `editor.isClosed`. The drag folder is gone at once: `!exists(coordinator.dragFiles.folder(for: id))`,
     `coordinator.dragFiles.stagedFile(id: id) == nil`, `world.cards.dragFiles(for: id).last == .some(nil)`
     (`applyLocalEdit`, +Editor:210-211 → `removeDragFolder`, +DragOut:289-295). The edit has a pending file: `let
     pending = pendingURL(coordinator, id)`; `record.fileURL == pending`, `record.fileIsTemporary`, `isBlue(png:
     Data(contentsOf: pending))` (`.newPendingFile`, EST:40-45, +Editor:336-357); `record.uploadIsStale` (the link still
     shows the original, CR:205-212); `record.editedAt == world.date` (+Editor:212-214); `record.isUploading`.
  3. `try await eventually { destination.state.withLock { $0.heldUploads.count } == 1 }`. While the PUT is held: Save
     As…'s read (after its panel, +RecordActions:183): `isBlue(png: try await coordinator.imageData(of: current,
     downloadTitle: "Saving a copy…"))` (reads `pending`, +RecordActions:224-228); Copy Image: `await
     coordinator.copyImage(recordID: id)`, `isBlue(png: world.clipboard.pngs.last!)`, `world.clipboard.copies.last ==
     .pngAndTIFF`; a drag press: `world.cards.showing.insert(id)` (see the note below), `coordinator.prepareDragFile(recordID:
     id)`, `try await eventually { world.cards.dragFiles(for: id).last.flatMap { $0 } != nil }`, the staged file's bytes
     are blue (`stage` copies `pending`, +DragOut:28-33); `destination.state.withLock { $0.dataDownloadKeys }.isEmpty`
     throughout.
  4. `destination.releaseUploads()`; `try await eventually { coordinator.history.record(id: id)?.uploadState ==
     .uploaded(url: publicURL(k), key: k) }`: `destination.state.withLock { $0.uploads.map(\.key) } == [k, k]`; the
     second's `cacheControl == "no-cache"` (a replace over the link's key, EUP:85, +Upload:166-172); its data is blue;
     `record.fileURL == nil`; `!record.uploadIsStale` (`applyingSuccess`, EUP:153-157); the kept drag copy is the edit:
     `isBlue(png: Data(contentsOf: coordinator.dragFiles.stagedFile(id: id)!))` (the pending file moved in again while
     the card shows, +Upload:651-654).
  5. Annotate again: `coordinator.openEditor(recordID: id)`; `try await eventually { world.editors.built.filter {
     $0.model.recordID == id }.count == 2 }`; the new editor's `isBlue(model.base)`; `dataDownloadKeys.isEmpty` still.
     Copy Image again gives a blue `pngs.last`. Ends with `settledEdit`.
- By hand / other seam: the card's Save As… panel (`SAVEAS`; only the read after it is here); the drop itself into another
  app by hand.
- Note on the line's text (for Tim): after any Annotate the card is closed with `.editorOpened` (+Editor:91, unconditional),
  which is not restorable (QuickAccessController.swift:19-24). So "from the card" and "press on the card, which stages the
  edit again" cannot happen after the edit as written; only Recent Captures can. The test puts the record back in
  `FakeCards.showing` to pin what `prepareDragFile` reads for any card that shows it. The line could drop the card in its
  third sentence.
- Covers: phase-6a:199, in part (the upload-only half; the save-folder half is
  `saveOverTheFileRemovesTheDragCopyAndEveryReadGivesTheEdit`, section 3).

## 5. CoordinatorEditorTests.swift (existing)

Header (CoordinatorEditorTests.swift:5-7) reworded as the design's section 4 says: presenting goes through
`environment.makeEditor` and `world.editors`. The two existing tests (`loadImageReadsTheLocalFileOrDownloadsTheObject`,
`annotateOnAMovedPrePhase3FileSaysCouldNotOpenAndOpensNoEditor`) stay.

### Opening

### `annotateOnACaptureWhoseEditorIsOpenBringsItForwardAndBuildsNoSecond` (S)
- Entry: `coordinator.openEditor(recordID:)` (+Editor:15) three times.
- Source: `pending/` (`addPendingImage`), the load task (+Editor:25-29).
- Sequence: `openEditor(id)`; `openEditor(id)` at once (no await between); then `openedEditor(id)`; then `openEditor(id)`
  again.
- Asserts:
  - After the first two calls, before any await: `coordinator.openingEditorIDs == [id]` and `world.editors.built.isEmpty`
    (the second call returns at the `openingEditorIDs` guard, +Editor:20).
  - After the open: `world.editors.built.count == 1`, `editor.presentCount == 1`, `coordinator.editors[id] === editor`,
    `coordinator.openingEditorIDs.isEmpty` (+Editor:38).
  - After the third call: `world.editors.built.count == 1`, `editor.presentCount == 2`, `editor.calls.last == .present`
    (+Editor:16-18 returns before anything else), `editor.pushes.count == 1` (no second push), and
    `world.cards.calls.filter { $0 == .close(id, .editorOpened) }.count == 1` (the card close runs only in
    `presentEditor`, +Editor:91).
- By hand: the window coming forward. That is `present()`'s own body, the controller's activation with its
  `orderFrontRegardless` fallback for the non-activating overlay (EWC:145-159), which the fake records and does not run.
  No later seam reaches it, since ordering a window front is barred in the suite; it stays by hand for good (design 9,
  hand check 1). The test pins the coordinator's half: `present()` called again, no second editor.
- Covers: phase-4a:39, in part.

### `anUploadedUploadOnlyCaptureOpensFromItsObjectAndOfflineOpensNone` (S)
- Entry: `openEditor(recordID:)`, `.download` branch, through `loadImage` (+Editor:48-65) and `imageData(of:)`
  (+RecordActions:215-238) to `downloadImage`/`downloadSource` (+RecordActions:253-271).
- Source: download (`addUploadOnly`, with `downloadedData` set to `CoordinatorWorld.pngData(width: 6, height: 3)` so the
  size tells the object apart).
- Fakes: `FakeDestination.dataDownloadFailures` (FD:107), `FakeNotifier`.
- Sequence: set `destination.state.withLock { $0.dataDownloadFailures = [URLError(.notConnectedToInternet)] }`;
  `openEditor(id)`; `eventually` on the error below; `eventually { coordinator.openingEditorIDs.isEmpty }`; then
  `openEditor(id)` again (the script is used up) and `openedEditor(id)`.
- Asserts, Wi-Fi off: `world.notifier.calls.contains(.error(title: "Could not open the capture", message:
  URLError(.notConnectedToInternet).localizedDescription))` (+Editor:61-63, the error's own description, so the test
  builds the expected text from the same value); `world.editors.built.isEmpty`; `coordinator.editors.isEmpty`.
- Asserts, on line: `editor.presentCount == 1` and `world.cards.calls.contains(.close(id, .editorOpened))` (the editor
  opened: both run only in `presentEditor`, +Editor:89-93); `editor.title == title(of: record)`; `editor.representedURL
  == nil` (+Editor:77);
  `editor.model.base.width == 6`, `.height == 3`, `editor.model.scale == 1`; `destination.state.withLock {
  $0.dataDownloadKeys } == [key, key]`; `world.notifier.calls.filter { $0 == .notice(title: "Opening the capture…", body:
  "Downloading s/SHOT.png") }.count == 2` (+Editor:48 default title, +RecordActions:265-267, `showNotification` on by
  default, AppSettings.swift:269); first push `saveCommand == .saveAs`, `status == EditorSaveTarget.noFileReason`,
  `available == all` (section 2.3).
- By hand: nothing (Wi-Fi is the scripted failure).
- Covers: phase-4a:49, full. The `uploadedUploadOnly` case of `aRestoredCardsAnnotateOpensFromTheFileOrTheBucket` repeats
  the on-line half through the card's entry.

### `withTheOverlayOffEveryAfterCaptureModeStillOpensTheEditor(mode:)` (M)
- Arguments: `AfterCaptureAction.allCases` = `.upload`, `.uploadOnly`, `.save` (AppSettings.swift:4-23).
- Entry: `coordinator.finishSave(_:image:scale:captureDisplayID:notConfiguredWarning:showsCard:upload:payload:notification:)`
  (+Save:201-225, internal; CoordinatorSaveTests.swift:90 drives it), the tail `persist` runs for each mode, then
  `openEditor`.
- Source: save-folder file for `.upload` and `.save` (`world.storeSaveFolder()`, `folder/Shot.png`); `pending/<id>.png`
  for `.uploadOnly`; the record each mode's `persist` builds (+Save:161-174): `fileIsTemporary: mode == .uploadOnly`,
  `uploadState: mode.uploads ? .uploading(fraction: 0) : .none`, `byteCount: png.count`.
- Fakes: `world.settings.showOverlay = false` (set in the test before `makeCoordinator`); for the two upload modes
  `holdingUploadsRemaining = 1` and `defer { destination.releaseUploads() }`, so `.uploadOnly` is "still uploading" when
  Annotate runs.
- Sequence: `finishSave(record, image: CoordinatorWorld.image(width: 4, height: 2), scale: 1, captureDisplayID: 1,
  notConfiguredWarning: nil, showsCard: true, upload: mode.uploads ? coordinator.makeDestination() : nil, payload: {
  .data(png) }, notification: .none)`; for upload modes `eventually { destination.state.withLock { $0.heldUploads.count }
  == 1 }`; `openEditor(id)`; `openedEditor(id)`.
- Asserts:
  - No card: `!world.cards.calls.contains(.show(id))` and `coordinator.latestCapture == nil` (the `showOverlay` guard,
    +Overlay:9, returns before the screens are read, so nothing is retained, +Overlay:15-17).
  - The editor: `editor.model.base.width == 4`, `.height == 2`; `editor.title == (mode == .uploadOnly ? title(of: record) :
    "Shot.png")`; `editor.representedURL == (mode == .uploadOnly ? nil : folder/Shot.png)`;
    `world.cards.calls.contains(.close(id, .editorOpened))`.
  - While uploading (`.upload`, `.uploadOnly`): first push `status == "Uploading…"`, `available == [.copy, .saveAs]`;
    `.save`: first push `status == nil`, `available == all` minus `.uploadAsNew`.
  - At the end, so nothing outlives the test (section 2): `destination.releaseUploads()`, `eventually { record.isUploading
    == false }`, and `eventually { record.thumbnailFileName != nil }` (`finishSave`'s own thumbnail, +Save:288-309).
- By hand: nothing the line checks. The captures are records set up as each mode's `persist` leaves them
  (+Save:161-174), since `save(_:)` needs a `CaptureResult` (an `SCDisplay`); the capture itself is `TARGET`'s.
- Covers: phase-4a:52, full.

### `anEditorOpensWithTheStoredSpotlightShapeAndCounterSize` (S)
- Entry: `openEditor(recordID:)` on the retained capture (`.retained`, synchronous, +Editor:22-24), so `presentEditor`
  builds the model with `settings.editorDefaults` (+Editor:80; AppSettings.swift:244-252).
- Source: `CaptureRecord(fileURL: nil, pixelWidth: 200, pixelHeight: 100, appName: nil)`; `coordinator.latestCapture =
  (id: record.id, image: ScaledImage(image: try CoordinatorWorld.image(width: 200, height: 100), scale: 2))` (as
  CoordinatorDeleteTests.swift:346-347).
- Fakes: before `makeCoordinator()`, `world.settings.editorSpotlightEllipse = true` and
  `world.settings.editorCounterDiameterPoints = 44` (AppSettings.swift:124-128: each writes its key to the world's suite).
- Sequence: `coordinator.openEditor(recordID: record.id)`; `editor = try #require(world.editors.editor(for: record.id))` at
  once; read the model; `model.tool = .spotlight`; read; `model.tool = .counter`; read.
- Asserts:
  - The keys as `defaults read` shows them: `world.defaults.bool(forKey: "editorSpotlightEllipse") == true`,
    `world.defaults.double(forKey: "editorCounterDiameterPoints") == 44` (AppSettings.swift:54-55); a second
    `AppSettings(defaults: world.defaults)` reads `editorDefaults.spotlightEllipse == true` and `.counterDiameterPoints ==
    44` (the relaunch's read; the round trip itself is `AppSettingsTests.editorDefaultsRoundTripThroughSecondInstance`,
    AppSettingsTests.swift:95).
  - `coordinator.openingEditorIDs.isEmpty` right after the call; `editor.model.spotlightEllipse == true`,
    `editor.model.counterDiameterPoints == 44`.
  - With Spotlight: `model.spotlightShapeApplies`, `model.activeSpotlightEllipse == true` (Model:612-624, what the Shape row
    shows); `model.makeAnnotation(.spotlight, from: CGPoint(x: 10, y: 10), to: CGPoint(x: 60, y:
    40))?.spotlightShape?.isEllipse == true`.
  - With Counter: `model.counterSizeApplies`, `model.activeCounterDiameterPoints == 44` (Model:636-645, the Size row);
    `model.makeAnnotation(.counter, from: CGPoint(x: 100, y: 50), to: CGPoint(x: 100, y: 50))?.counterMark?.diameter ==
    88` (44 pt at 2x, Model:281).
- By hand / other seam: choosing Ellipse and Large in the options popover, which writes `AppSettings.shared` through
  `EditorToolbar.storeChangedDefaults` (TidyShot/Editor/Window/EditorToolbar.swift:164-175): `EDDEFAULTS`. The Shape and
  Size rows as drawn, the real `defaults read`, and the real quit and relaunch stay by hand.
- Covers: phase-4c:201, in part.

### `aCaptureFromBefore4cOpensEditsAndSavesAsBefore` (M)
- Entry: `history.load()` of a history file in the pre-4c shape (HS:40-63), then `openEditor` (`.saveFolderFile`), edits,
  `save()`.
- Source: what the build before 4c wrote. 4c (merge 3737262) changed no record key; the keys its parent wrote end at
  `mediaKind, durationSeconds` (`git show 3737262^1:TidyShot/History/CaptureRecord.swift`, CodingKeys :116-121);
  `byteCount` (small-tweaks, 4572809), `unmutedIntervals` (R2, d3c8be8) and `multipart` (R4, 9ba432e) came later. The
  file: `storeSaveFolder()`, `png = png(width: 200, height: 100, scale: 2)` at `<Saved>/Old.png`; JSON written to
  `world.historyFileURL` before `coordinator.history.load()`: `[{"appName": "Safari", "fileIsTemporary": false,
  "fileURL": "<file.absoluteString>", "id": "<id.uuidString>", "mediaKind": "image", "pixelHeight": 100, "pixelWidth":
  200, "supersededObjects": [], "timestamp": "<ISO 8601 with fractional seconds of Date() - 3600>", "uploadIsStale":
  false, "uploadState": {"none": {}}}]` (the shape of CaptureRecordTests.swift:20-37 and :375-385; dates as HS:162-175;
  a time an hour before the real `Date()`, since retention prunes on it). The world's defaults suite has no
  `editorSpotlightEllipse` or `editorCounterDiameterPoints` key, as before 4c.
- Fakes: none.
- Sequence: write the JSON; `coordinator.history.load()`; open; `editor = openedEditor(id)`;
  `commitNewShape(makeAnnotation(.rectangle, from: CGPoint(x: 20, y: 20), to: CGPoint(x: 90, y: 70))!)` (a 4a tool);
  `commitNewShape(makeAnnotation(.spotlight, from: CGPoint(x: 110, y: 20), to: CGPoint(x: 180, y: 80))!)` (a 4c tool on the
  old capture); `await editor.save()`; `expected`.
- Asserts:
  - The record decoded with the later defaults: `byteCount == nil`, `mediaKind == .image`, `unmutedIntervals == []`,
    `multipart == nil` (CR:150-182); `world.defaults.persistentDomain(forName: world.suiteName)?["editorSpotlightEllipse"]
    == nil`.
  - The model: `base.width == 200`, `.height == 100`, `scale == 2`, `spotlightEllipse == false`, `counterDiameterPoints ==
    32` (the registered defaults, AppSettings.swift:285-286, EditorPalette.swift:96-97).
  - Saved `== true`; `decoded(Data(contentsOf: file))` 200 by 100 at scale 2 (no change in size), `rgba == rgba(expected)`,
    `abs(dpiWidth - 144) < 0.5`; `pixel(decoded, x: 20, y: 40)` is the rectangle's stroke, rgb(255, 59, 48): `r > 200`,
    `g < 100`, `20 < b < 100`. The stroke sits inside the rect (AnnotationDrawing.swift:228-231) over the dimmed base:
    (20, 40) is outside the spotlight's hole, and the flattener draws the spotlight's overlay under the drawings
    (EditorFlattener.swift:56-69), so the base there is about 127 red and the stroke stays bright. `r` tells the stroke
    from the dimmed base, and `b` from the undimmed world red `[255, 38, 0]`, so the check holds even if the spotlight
    moves. `pixel(decoded, x: 100, y: 90)` is the dimmed base (`r` in `120...135`); listing `== ["Old.png"]`; the
    record's `byteCount` now `== written.count` (+Editor:215). Ends with `settledEdit`.
- By hand: nothing.
- Covers: phase-4c:214, full.

### `aComposedWindowCaptureOpensFlatWithNoBackground(composed:)` (S)
- Arguments: `nonisolated enum Composed: CaseIterable, Sendable { case retained, savedFile }`: the new window capture's
  card (its image retained) and an older card or Recent Captures (its file).
- Entry: `openEditor(recordID:)`.
- Source: `let composed = try #require(BackgroundCompositor.compose(CoordinatorWorld.image(width: 4, height: 2), style:
  background, scale: 1, fillImage: nil))` (BackgroundCompositor.swift:16-17), which is what `withWindowBackground` hands
  the save (+Save:81-98). `world.storeSaveFolder()`; its PNG (`ImageEncoder.pngData(from: composed, scale: 1)`) written to
  `<folder>/Window.png`; `CaptureRecord(fileURL: file, pixelWidth: 20, pixelHeight: 18, appName: nil)`. `retained`: also
  `coordinator.latestCapture = (id: id, image: ScaledImage(image: composed, scale: 1))` (the `.retained` branch, EI:43).
- Sequence: the call; for `retained` the editor at once (`openingEditorIDs.isEmpty`), for `savedFile` through `openedEditor`.
- Asserts: `base.width == 20`, `base.height == 18`; `pixel(base, x: 0, y: 0) == [0, 255, 0, 255]` and `pixel(base, x: 8, y:
  8) == (try worldRed())` (the background baked in; the capture's red reads `[255, 38, 0, 255]`, 2.1); `retained`: `model.base === composed`; `model.document ==
  AnnotationDocument()`, `model.document.background == nil` (the switch's getter, BackgroundPopoverView.swift:36-37:
  off); `!model.hasUnsavedChanges`.
- By hand / other seam: producing the window capture with its background (`TARGET`: `save(_:intent:)` and
  `withWindowBackground` need a `CaptureResult` a test cannot build, CaptureTarget.swift:5); the popover's switch as its
  binding shows it (`BGPOP`) and drawn in the window (`EDPLACE`); `model.document.background == nil` is the rule the
  switch's getter reads.
- Covers: phase-7c:187, in part.

### The card

### `annotateFromACardOrRecentCapturesLeavesNothingToRestore` (M)
- Entry: `coordinator.deleteCapture(recordID:)` (+Delete:14), `coordinator.openEditorAfterMenuTracking(recordID:)`
  (+Editor:68-70, which the card's Annotate calls, +Overlay:27, and the pin menu's Annotate calls, +Pins:68-72), and
  `coordinator.openEditor(recordID:)` (what Recent Captures' Annotate calls once its menus close,
  RecentCapturesMenu.swift:113).
- Source: pending, four times: `a`, `b`, `c`, `d` by `addPendingImage(to:)`. Each card shows: `world.cards.showing =
  [a.id, b.id, c.id]`; `d` comes later.
- Fakes: `FakeConfirm` with no answers (Yes, Fakes `FakeConfirm.confirm`), Ask before deleting on by default.
- Sequence and asserts:
  1. Delete the middle card's capture and Annotate another: `await coordinator.deleteCapture(recordID: b.id)` (a failed,
     never-uploaded capture: no stored upload and no object, so no storage call; its pending file and record go,
     +Delete:72-74, :190-212); `coordinator.openEditorAfterMenuTracking(recordID: c.id)`; `openedEditor(c.id)`.
     - `world.cards.closes == [.deleted, .editorOpened]` and the two closes are `.close(b.id, .deleted)` (+Delete:204)
       and `.close(c.id, .editorOpened)` (+Editor:91): each closes. `world.cards.showing == [a.id]`.
     - Neither is restorable: `coordinator.closedOverlays.ids.isEmpty` (`.deleted` and `.editorOpened` take an id off the
       list, ClosedOverlays.swift:11-14, QuickAccessController.swift:19-24); `!coordinator.canRestoreClosedOverlay`, which
       is the menu item's state (StatusMenuController.swift:115). This is phase-6a:152 and phase-6a:158's first two
       sentences.
     - The editor opened: `world.editors.editor(for: c.id)?.presentCount == 1` (coordinator-split:44's Annotate, the
       same call the pin menu makes).
  2. Open the editor from Recent Captures on a capture whose card is already closed: `d` by `addPendingImage`,
     `world.cards.showing.insert(d.id)`, `world.cards.close(recordID: d.id, reason: .user)`; then
     `coordinator.closedOverlays.ids == [d.id]` and `coordinator.canRestoreClosedOverlay` (a user close is restorable).
     `coordinator.openEditor(recordID: d.id)`; `openedEditor(d.id)`. Then `coordinator.closedOverlays.ids.isEmpty` and
     `!coordinator.canRestoreClosedOverlay` (+Editor:92-93).
- By hand / other seam: phase-6a:131: the gap in the stack closing (the stack's layout, `QASTACK`). coordinator-split:44:
  the pin over the spot, the second click bringing the same pin forward, the menu's `Close Pinned Screenshots` item
  (`PINS`, `SCREENS`), the pin's Save As… panel (`SAVEAS`); its Copy Image is `copyImage(recordID:)`, already pinned by
  `CoordinatorRecordActionsTests.copyImageReadsTheFileOrDownloadsTheObject` (CoordinatorRecordActionsTests.swift:74-75),
  which the mark can name. phase-6a:152: nothing.
- Covers: phase-6a:152, full; phase-6a:158, full with `aCardWhoseDeleteIsUnderWayIsNotRestorable` (this test pins the two
  editor cases and the first sentence); phase-6a:131, in part; coordinator-split:44, in part (the pin menu's Annotate).

### `aRestoredCardsAnnotateOpensFromTheFileOrTheBucket(restored:)` (M)
- Arguments: `nonisolated enum Restored: CaseIterable, Sendable { case savedFile, pendingFile, uploadedUploadOnly,
  uploadedUploadOnlyStaged }`.
- Entry: `coordinator.openEditorAfterMenuTracking(recordID:)` with no retained image.
- Source: `world.storeSaveFolder()` for every case. `savedFile`: `addSavedImage` (`Shot.png`, 4 by 2). `pendingFile`:
  `addPendingImage`. `uploadedUploadOnly`: `CaptureRecord(fileURL: nil, pixelWidth: 6, pixelHeight: 3, appName: nil,
  uploadState: .uploaded(url: link, key: key), objectLocation: world.location)` with `destination.state.withLock {
  $0.downloadedData = try CoordinatorWorld.pngData(width: 6, height: 3) }` (as CoordinatorEditorTests.swift:39-40).
  `uploadedUploadOnlyStaged`: the same record, and after the card shows, the restore's last step:
  `coordinator.prepareDragFile(recordID: id)` (+Overlay:101), then `try await eventually { world.cards.dragFiles(for:
  id).last.flatMap { $0 } != nil }` (the quiet download landed in the drag folder, +DragOut:69-89). The card shows
  (`world.cards.showing.insert(id)`); `latestCapture` stays nil.
- What stands for a restored card, and what does not: `restoreClosedOverlay` cannot be driven (it reads
  `NSScreen.screens` through `overlayScreen`, +Overlay:94, :55-61), so no restore runs and the line is in part. A
  restored card's Annotate is the same `openEditorAfterMenuTracking` (+Overlay:97-98 builds it with `overlayActions()`,
  +Overlay:21-38), restoring sets no `latestCapture` (+Overlay:87-102), and its one other step that changes what
  Annotate reads, the quiet download of an uploaded upload-only capture into its drag folder (+Overlay:101 →
  +DragOut:61, :69-89), is run here by `prepareDragFile` in the `Staged` case. So `uploadedUploadOnly` is a restored
  card's Annotate before the quiet download lands (from the bucket), and `uploadedUploadOnlyStaged` after (from the drag
  copy, which came from the bucket).
- Sequence: the call; `openedEditor(id)`; `try await eventually { coordinator.openingEditorIDs.isEmpty }`.
- Asserts:
  - `savedFile`: `title == "Shot.png"`, `representedURL == file`, base 4 by 2, `dataDownloadKeys.isEmpty`.
  - `pendingFile`: `title == title(of: record)`, `representedURL == nil` (a pending file is not shown, +Editor:75-77), base
    4 by 2, `dataDownloadKeys.isEmpty`.
  - `uploadedUploadOnly`: `title == title(of: record)`, `representedURL == nil`, base 6 by 3, `dataDownloadKeys ==
    ["s/SHOT.png"]`, and `world.notifier.calls.contains(.notice(title: "Opening the capture…", body: "Downloading
    s/SHOT.png"))` (+Editor:48, +RecordActions:263-269).
  - `uploadedUploadOnlyStaged`: `title == title(of: record)`, `representedURL == nil`, base 6 by 3, `dataDownloadKeys ==
    ["s/SHOT.png"]` (the quiet GET only; Annotate read the drag copy, +RecordActions:233-236), and no `.notice` whose
    body starts with `"Downloading "` (the quiet GET posts none, `title: nil`, +RecordActions:263-269).
  - Every case: `pixel(base, x: 0, y: 0) == (try worldRed())`; `editor.model.scale == 1`; `presentCount == 1`;
    `pushes.first?.record == coordinator.history.record(id: id)`; `world.cards.calls.contains(.close(id,
    .editorOpened))`; `!coordinator.closedOverlays.ids.contains(id)`; `world.notifier.errors.isEmpty`.
- By hand / other seam: the restore itself (`SCREENS`, seams.md row 10, which replaces `restoreClosedOverlay`'s screen
  read). The quiet download's own naming is pinned by
  `CoordinatorDragOutTests.aRestoredUploadOnlyCardsQuietDownloadIsNamedForItsKey` (CoordinatorDragOutTests.swift:557),
  and the restore list by `ClosedOverlaysTests`; the mark can name both.
- Covers: phase-6a:164, in part.

### `anUploadedUploadOnlyCardsCopyImageAndAnnotateReadTheDragCopy` (M)
- Entry: `copyImage(recordID:)`, `imageData(of:downloadTitle:)` (Save As…'s read), then
  `openEditorAfterMenuTracking(recordID:)`; then the clean-up on `world.clock`.
- Source: download, read from the drag copy: `addPendingImage`, `world.cards.showing.insert(id)`, `retryUpload(recordID:)`,
  `eventually` uploaded (as `anUploadedUploadOnlyImageMovesToItsDragFolderOnlyWithACard`,
  CoordinatorUploadTests.swift:290-313). `let k` the key, `let png` the pending bytes.
- Fakes: `world.clock` (Fakes `FakeScrollClock`, ScrollSessionFakes.swift:61-128).
- Sequence and asserts:
  1. Before: `record.fileURL == nil`; `Data(contentsOf: coordinator.dragFiles.stagedFile(id: id)!) == png`;
     `world.clipboard.copies == [.url(publicURL(k))]`.
  2. `await coordinator.copyImage(recordID: id)`: `world.clipboard.copies == [.url(publicURL(k)), .pngAndTIFF]`,
     `world.clipboard.pngs == [png]`; `world.notifier.calls.contains(.notice(title: "Image copied", body: k))`
     (+RecordActions:98-101).
  3. `try await coordinator.imageData(of: record, downloadTitle: "Saving a copy…") == png` (the read `saveCopy` makes after
     its panel, +RecordActions:183).
  4. `coordinator.openEditorAfterMenuTracking(recordID: id)`; `openedEditor(id)`; `pixel(model.base, x: 0, y: 0) == (try
     worldRed())`, base 4 by 2; `world.cards.calls.contains(.close(id, .editorOpened))`.
  5. No download at any step: `destination.state.withLock { $0.dataDownloadKeys }.isEmpty`, and no `FakeNotifier.Call` is
     a `.notice` whose body starts with `"Downloading "` (`downloadSource` posts that, +RecordActions:267-269; the drag
     copy is read first, +RecordActions:233-236).
  6. "60 seconds after the card closes": the Annotate closed it (`overlayDidClose` → `scheduleDragCleanup`,
     +Overlay:67-76). `try await world.clock.run(for: .seconds(60))`; `try await eventually {
     !exists(coordinator.dragFiles.folder(for: id)) }` (+DragOut:6, :261-276), as CoordinatorDragOutTests.swift:599-601
     does for a recording's copy.
- By hand / other seam: the card's Save As… panel (`SAVEAS`: `askSaveAsTarget` builds `EditorNaming.savePanel` and awaits
  it before any read, +RecordActions:195-201); Slack reading the file during the minute, by hand. Already D, and named in
  the mark: the drag folder taking the pending file's place and `fileURL` gone (`history.json` and Recent Captures' "no
  local file") are `CoordinatorUploadTests.anUploadedUploadOnlyImageMovesToItsDragFolderOnlyWithACard`
  (CoordinatorUploadTests.swift:290-313).
- Covers: phase-6a:198, in part.

### What the editor hears while things happen

### `anEditorOpenedDuringAHeldUploadHearsUploadingAndGetsSaveAndUploadBack` (M)
- Entry: `coordinator.startUpload(recordID:payload:destination:)` (+Upload:138, as save's tail starts it, +Save:217-223),
  then `openEditor` on the retained image, then the editor's actions; `.uploaded` reaches the editor through
  `refreshOverlay` (+Overlay:107-112).
- Source: retained (`coordinator.latestCapture = (id: id, image: ScaledImage(image: CoordinatorWorld.image(width: 4,
  height: 2), scale: 1))`, as CoordinatorDeleteTests.swift:346-347) over a save-folder record (`addSavedImage` with
  `uploadState: .uploading(fraction: 0)`, as `persist` makes it for "Upload and copy URL", +Save:161-163).
- Fakes: `holdingUploadsRemaining = 1` (FD:26), `defer { destination.releaseUploads() }`; `FakeNotifier`, `FakeClipboard`.
- Sequence: `startUpload(recordID: id, payload: .data(original), destination: try #require(coordinator.makeDestination()))`;
  `eventually { heldUploads.count == 1 }`; `openEditor(id)` and, with no await, `editor = try #require(world.editors.editor(for:
  id))`; `editor.draw()`; `await editor.save()`; `await editor.upload()`; `await editor.upload(asNew: true)`; `await
  editor.saveAs(to: desktop("Copy.png"))`; `await editor.copy()`; `destination.releaseUploads()`; `eventually {
  isUploaded(coordinator, id) }`.
- Asserts:
  - At once: `coordinator.openingEditorIDs.isEmpty` right after the call (the `.retained` branch, +Editor:22-24).
  - First push: `status == EditorAvailability.uploadingStatus` (`Uploading…`), `available == [.copy, .saveAs]` (EST:132-145:
    uploading refuses save, upload, uploadAsNew), `saveCommand == .writeOver`, `isDeleting == false`.
  - The write-time checks the window's validation stands in front of (+Editor:158-163, :315, :382-388): `save()` is false
    and `world.notifier.errors.last` is `("Not saved", "This capture is still uploading.")` (EST:115); `upload()` and
    `upload(asNew: true)` are each `.refused` with `("Not uploaded", "This capture is still uploading.")`; `try
    Data(contentsOf: file) == original`; `!editor.isClosed`; `destination.state.withLock { $0.attemptKeys.count } == 1`.
  - ⇧⌘S's write: `saveAs(to:)` is true; `isBlue(png: Data(contentsOf: desktop("Copy.png")))`;
    `world.notifier.calls.contains(.saved(title: "Saved", file: "Copy.png"))` (+RecordActions:291-313).
  - ⌘C: after `copy()`, `world.clipboard.copies == [.pngAndTIFF]` (the Save As before it found no owner, EC:15-18),
    `isBlue(png: world.clipboard.pngs[0])`, `world.notifier.calls.contains(.notice(title: "Image copied", body:
    "Shot.png"))` (+Editor:459-461: no key yet while uploading, so the file name).
  - After the release: last push `status == nil`, `available == all`, `saveCommand == .writeOver`;
    `world.clipboard.copies == [.pngAndTIFF, .url(uploadedURL)]` where `uploadedURL` is the record's `uploadedURL`
    (+Upload:698-699).
- By hand / other seam: the subtitle as shown and the greyed toolbar items (`EDPLACE`; `edplace-design.md` section 8,
  `aPushGreysSaveAndUploadInTheToolbarAndCopyStaysOn`); ⌘S, ⌘U, ⌥⌘U refused by the window's validation (`EDPLACE`;
  EWC:426-427 through `EditorWindow.send`, EditorWindow.swift:41-48) and their beeps (`BEEP`, EditorWindow.swift:45).
  This test pins the coordinator's write-time refusal behind that gate (+Editor:158-163, :315, :382-388), which posts a
  `Not saved` or `Not uploaded` notice; the line's "do nothing" is the gate's, and the mark says so (design 6). ⌘C/⇧⌘C
  routing to `copyImage` (`EDPLACE`); ⇧⌘S's panel (`EDSAVEAS`); the slow profile is the hold.
- Covers: phase-4a:37, in part; phase-4a:145, in part.

### `aDeleteAskedThenCancelledThenConfirmedReachesTheOpenEditor` (M)
- Entry: `coordinator.deleteCapture(recordID:)` (+Delete:15) twice with an editor open; its `refreshOverlay` before the
  alert and in the `defer` (+Delete:22-30), and `removeRecord`'s push (+Delete:210).
- Source: save-folder (`addSavedImage(uploadState: .uploaded(url: link, key: key), objectLocation: world.location,
  uploadIsStale: true)`), opened with `openEditor` and `openedEditor`, so "what it was" is a subtitle.
- Fakes: `world.confirm.holds = true` for the first delete (Fakes, `FakeConfirm`, `SingleWaiter`), answers empty (Yes) for
  the second; `FakeDestination.deletedKeys`; `TaskWatch`.
- Sequence: open; `editor.draw()`; `let first = Task { await coordinator.deleteCapture(recordID: id) }`, `defer {
  first.cancel() }`, `let watch = TaskWatch(first)`; `eventually { world.confirm.isWaiting }`; `await editor.save()`; `world.confirm.answer(false)`;
  `eventually { watch.hasReturned }`; `await first.value`; then `await coordinator.deleteCapture(recordID: id)` (not held:
  `holds` is false after `answer`, Fakes `FakeConfirm.answer`); `await editor.copy()`; `await editor.saveAs(to:
  desktop("Deleted.png"))`.
- Asserts:
  - Before: first push `status == EditorSaveTarget.uploadedCopyStaleNotice`, `available == all`.
  - Alert open: last push `isDeleting == true`, `status == "Deleting…"`, `available == [.copy, .saveAs]`. A Save sent then
    is refused at write time: `save()` false, errors.last `("Not saved", "This capture is being deleted.")` (EST:114,
    +Editor:158-163); file unchanged; `editor.model.hasUnsavedChanges`.
  - After Cancel: last push `isDeleting == false`, `status == EditorSaveTarget.uploadedCopyStaleNotice`, `available ==
    all`; `coordinator.history.record(id: id) != nil`; `world.confirm.asked.count == 1`; `deletedKeys.isEmpty`.
  - After the confirmed delete: `coordinator.history.record(id: id) == nil`; `deletedKeys == [key]`; last push `record ==
    nil`, `status == EditorAvailability.deletedStatus`, `available == [.copy, .saveAs]`, `saveCommand == .saveAs`;
    `coordinator.editors[id] === editor` and `!editor.isClosed` (Delete pushes, +Delete:210; nothing in +Delete closes
    an editor).
  - ⌘C after the delete: `copies == [.pngAndTIFF]` and `world.notifier.calls.contains(.notice(title: "Image copied", body:
    ""))` (+Editor:460-461, no record). ⇧⌘S's write: `saveAs` true, `isBlue(png:)` of `desktop("Deleted.png")`,
    `.saved(title: "Saved", file: "Deleted.png")`, and `copies == [.pngAndTIFF, .pngAndTIFF]` (the copy made the record
    own the clipboard, so the Save As replaces it, +Editor:302, :436-446).
- By hand / other seam, per line. phase-4a:146: greying and the subtitle as shown (`EDPLACE`); ⌘S refused by the
  window's validation (`EDPLACE`) and its beep (`BEEP`, EditorWindow.swift:45); the `save()` here pins the
  coordinator's write-time refusal behind the gate (+Editor:158-163), as in the test above. phase-4a:147: the subtitle as
  shown and greying (`EDPLACE`); ⌘C reaching `copyImage` (`EDPLACE`, EWC:202-215; `copy()` here is the action it
  calls); ⇧⌘S's panel (`EDSAVEAS`).
- Covers: phase-4a:146, in part; phase-4a:147, in part.

### `anEditorOpenedWhileADeleteAsksHearsItAndRefusesSave` (S, the minimal design's test 5, as built, with the `TaskWatch` gate)
- Entry: `coordinator.deleteCapture(recordID:)` (+Delete:15) held at its confirm, then `openEditor` on the same record;
  `pushEditorState` reads `deletingIDs` (+Delete:21) on the first push.
- Source: pending (`addPendingImage`); `pending = record.fileURL`, `original = Data(contentsOf: pending)`.
- Fakes: `world.confirm.holds = true` before `makeCoordinator()` (Fakes `FakeConfirm`, `SingleWaiter`); `TaskWatch`.
- Sequence: `let delete = Task { await coordinator.deleteCapture(recordID: record.id) }`; `defer { delete.cancel() }`;
  `let watch = TaskWatch(delete)`; `try await eventually { world.confirm.isWaiting }`; `coordinator.openEditor(recordID:
  record.id)`; `editor = try await openedEditor(record.id)`; the open asserts; `editor.draw()`; `let saved = await
  editor.save()` (a Save sent before the push arrived; the window refuses it once the push lands); `world.confirm.answer(true)`;
  `try await eventually { watch.hasReturned }`; `await delete.value`; the delete asserts; `await editor.copy()`.
  The built body awaited `delete.value` straight after the answer; the gate is what context.md and the design's
  section 5 require (a regression that kept the delete from returning would otherwise hang the run, Fakes:416-429).
- Asserts:
  - Opened during the alert: `editor.representedURL == nil`, `editor.title.hasPrefix("Capture ")`; first push
    `isDeleting`, `status == EditorAvailability.deletingStatus` (`Deleting…`), `available == [.copy, .saveAs]`.
  - The Save: `saved == false`; `world.notifier.errors.last` is `("Not saved", EditorAvailability.deletingRefusal)`
    (+Editor:158-163); `Data(contentsOf: pending) == original`; `editor.model.hasUnsavedChanges`.
  - After Yes: `coordinator.history.record(id: record.id) == nil`; last push `record == nil`, `status ==
    EditorAvailability.deletedStatus`, `available == [.copy, .saveAs]`; `coordinator.editors[record.id] === editor`.
  - Copy after the delete: `world.clipboard.copies == [.pngAndTIFF]`.
- By hand / other seam: as the test above, per line.
- Covers: phase-4a:146, in part (the opened-during-the-alert order); phase-4a:147, in part.

### `aPrunedCaptureTellsItsOpenEditorItWasDeleted` (M)
- Entry: `coordinator.history.add(_:)` (HS:66-84) with retention 1 day; `didPrune` → `removeFiles(ofPruned:)` →
  `pushEditorState` (Coord:283, +Delete:242-264).
- Source: save-folder (`addSavedImage(timestamp: Date(timeIntervalSinceNow: -2 * 86_400))`; the default retention, 30 days,
  keeps it at its own add, AppSettings.swift:281).
- Sequence: open; `world.settings.historyRetentionDays = 1`; `coordinator.history.add(CaptureRecord(fileURL: nil,
  pixelWidth: 4, pixelHeight: 2, appName: nil))`; `editor.draw()`; `await editor.saveAs(to: desktop("Pruned.png"))`.
- Asserts: right after the add, with no await: `coordinator.history.record(id: id) == nil`; last push `record == nil`,
  `status == EditorAvailability.deletedStatus`, `available == [.copy, .saveAs]`, `saveCommand == .saveAs`; the save-folder
  file still exists (pruning leaves save-folder files, +Delete:237-241); `coordinator.editors[id] === editor`. ⇧⌘S's
  write: `saveAs` true, `isBlue(png:)` of the Desktop file, `.saved(title: "Saved", file: "Pruned.png")`.
- By hand / other seam: the subtitle as shown and the greying (`EDPLACE`); ⇧⌘S's panel (`EDSAVEAS`). The relaunch in the
  line is only how the hand check gets an old record; the test starts with one.
- Covers: phase-4a:162, in part.

### The quit review

### `quitAsksEachChangedEditorCancelStopsItDontSaveLetsItGo` (S, the minimal design's test 4, as built)
- Entry: `coordinator.reviewEditorsBeforeQuit()` (Coord:470-477) and `quitNeedsHold` (Coord:462-464).
- Source: two pending captures (`addPendingImage`), `changed` and `clean`, both opened; `original` the changed one's
  pending bytes.
- Fakes: `FakeEditor.holdsCloseSheet`, `answer(.cancel)`, `closeAnswers = [.dontSave]`; `TaskWatch`.
- Sequence: open both; `editor`, `other` by `openedEditor`; `editor.draw()`; `editor.holdsCloseSheet = true`; `let first =
  Task { await coordinator.reviewEditorsBeforeQuit() }`, `defer { first.cancel() }`, `let firstWatch = TaskWatch(first)`;
  `try await eventually { editor.isAsking }`; `editor.answer(.cancel)`; `try await eventually { firstWatch.hasReturned }`;
  `let proceeded = await first.value`; then `editor.closeAnswers = [.dontSave]`; `let second = Task { ... }`, `defer {
  second.cancel() }`, `let secondWatch = TaskWatch(second)`; `try await eventually { secondWatch.hasReturned }`; `let
  quits = await second.value`.
- Asserts as built: `!quitNeedsHold` while clean, `quitNeedsHold` after `draw()`; the held review shows
  `Array(editor.calls.suffix(2)) == [.present, .askToSave]`; Cancel returns false (`!proceeded`), the editor stays
  registered (`coordinator.editors[changed.id] === editor`) and changed, the clean editor is never asked
  (`!other.calls.contains(.askToSave)`); Don't Save returns true, `askToSave` twice in all, the pending file
  byte-identical, the editor still changed and not closed (the review only answers; it closes nothing, Coord:470-477).
- By hand / other seam: the sheet itself (`CLOSESHEET`); the real quit's reply (`AppDelegate.applicationShouldTerminate`,
  AppDelegate.swift:69-84: `APPDELEGATE`, seams.md row 31).
- Covers: phase-4a:155, in part.

## 6. CoordinatorOverlayTests.swift (existing)

### `aCardWhoseDeleteIsUnderWayIsNotRestorable` (M)
- Entry: `coordinator.deleteCapture(recordID:)` in a `Task`, then `canRestoreClosedOverlay` (+Overlay:79-81) and
  `restoreClosedOverlay()` (+Overlay:87-90), the shortcut's call (Coord:428-430). No editor: this is phase-6a:158's A
  part, which no test reaches today (only CoordinatorOverlayTests.swift:16-30 reads `canRestoreClosedOverlay`).
- Source: pending recording with a stored multipart upload, as `CoordinatorDeleteTests.anAbortFailureAsksToRemoveFromHistory`
  builds it (CoordinatorDeleteTests.swift:240-244): a 3-byte sparse `pending/<id>.mp4`, `.failed(message: "Upload was
  interrupted.")`, `mediaKind: .video`, `durationSeconds: 10`, `multipart: MultipartUploadState(uploadID: "stored-1", key:
  "s/STORED.mp4", location: world.location, partSize: 262_144, byteCount: 3, sourceModified: Date(), sourcePath:
  "/nowhere/Recording.mp4", startedAt: Date())`. Its card shows and the user closes it: `world.cards.showing.insert(id)`,
  `world.cards.close(recordID: id, reason: .user)`.
- Fakes: `destination` is `world.factory.standard` (the suite's new `destination` property, 2.2):
  `destination.state.withLock { $0.holdingAbortsRemaining = 1 }`, `defer { destination.releaseAborts() }`
  (FD:364-385). The confirm answers Yes (no answers). The held Abort is "the confirmation accepted, an upload being
  cancelled and the storage call still running": Delete aborts the stored upload before any `DELETE` (+Delete:40-48,
  CaptureDeletion.aborts, CaptureDeletion.swift:76-78).
- Sequence and asserts:
  1. Before: `coordinator.closedOverlays.ids == [id]`, `coordinator.canRestoreClosedOverlay`.
  2. `let delete = Task { await coordinator.deleteCapture(recordID: id) }`, `defer { delete.cancel() }`, `let watch =
     TaskWatch(delete)`; `try await
     eventually { destination.state.withLock { $0.aborts.count } == 1 }`. Then `world.confirm.asked == [.delete(record)]`
     (the confirmation was accepted, +Delete:30-32); `coordinator.deletingIDs.contains(id)` (+Delete:21, cleared only in
     the `defer`, :26-29); `!coordinator.canRestoreClosedOverlay`: the menu item stays disabled
     (StatusMenuController.swift:115; shown ids are `overlay.shownIDs ∪ deletingIDs`, +Overlay:80); `try
     #require(!coordinator.canRestoreClosedOverlay)`, then `await coordinator.restoreClosedOverlay()`: the shortcut does
     nothing, `world.cards.calls` has no `.show` (+Overlay:88-90) and `coordinator.closedOverlays.ids == [id]`
     (`popRestorable` keeps an id that exists and is shown, ClosedOverlays.swift:32-36).
  3. `destination.releaseAborts()`; `try await eventually { watch.hasReturned }`; `await delete.value`. Then
     `coordinator.history.record(id: id) == nil`, `world.cards.calls.contains(.close(id, .deleted))`,
     `!coordinator.canRestoreClosedOverlay` (the id has no record, ClosedOverlays.swift:33).
- By hand: nothing; Network Link Conditioner's `100% Loss` is the held Abort.
- Covers: phase-6a:158, full with `annotateFromACardOrRecentCapturesLeavesNothingToRestore` (this test pins the
  delete-under-way sentences).

## 7. Deferred: no test this phase

Each needs the real controller, and a controller cannot be built under context.md's constraints until its screen read
(EWC:119-133: `NSScreen.screens`, `NSEvent.mouseLocation` and `NSScreen.main` at :123) and its NSWorkspace observer
(EWC:103-106) sit behind `EditorWindowPlacement` (`EDPLACE`, design call 1). `EditorPresenting` exposes none of this
(design 2.1) and the `FakeEditor` has no toolbar, so this seam unlocks no part of these lines.
`EditorToolbarTests.makeEditor` (EditorToolbarTests.swift:54-66) builds one today against that constraint (design
section 5). The constructed design has built and run the tests for seven of them (`edplace-design.md` section 8,
`TidyShotTests/EditorWindowControllerTests.swift`, `Test run with 2283 tests in 193 suites`).

| Line | What it checks | Whose code | Test waiting in `edplace-design.md` section 8 | Seam |
|---|---|---|---|---|
| phase-4a:56 (:70) | toolbar order, the three tooltips, no menus | EditorToolbar.swift:98-104 on the window | `theToolbarShowsTheToolsThenColourOptionsBackgroundZoomCopySaveAndUpload` | `EDPLACE` |
| phase-4a:58 (:72) | the tools segment following a key | EditorToolbar.swift:131-150 | `letterKeysPickToolsAndTheToolbarSegmentFollows` | `EDPLACE` |
| phase-4a:88 (:137) | ⌘1, ⌘0, ⌘=, ⌘-, the zoom pop-up | EWC:404-422 and the toolbar | `zoomCommandsAndThePopUpsItemsSetTheZoom` | `EDPLACE` |
| phase-4a:151 (:218) | ⌘W on a clean editor closes at once | `windowShouldClose`, EWC:444-453 | `closingAnEditorWithNoChangesClosesItAtOnce` | `EDPLACE` |
| phase-4a:107 (:158) | edited during ⌘U: beep, stays open, newer edit unsaved | `performUpload`, EWC:268-283 (beep :280) | none | `EDPLACE` and `BEEP` (seams.md row 32, widened, design call 12) |
| phase-4c:94 (:94) | item order after the tools, the Options tip `Tool options` | EditorToolbar.swift:31 `itemIdentifiers`, :89 | `theToolbarShowsTheToolsThenColourOptionsBackgroundZoomCopySaveAndUpload` | `EDPLACE` |
| phase-4c:95 (:95) | the tools segment following a key-picked tool | `EditorToolbar.observeToolbarState`/`reflectTool`, EditorToolbar.swift:132-153 | `letterKeysPickToolsAndTheToolbarSegmentFollows` | `EDPLACE` |
| phase-7c:72 (:73) | the `Background` item, its tip and `rectangle.inset.filled` symbol, after Options | `toolbar(_:itemForItemIdentifier:willBeInsertedIntoToolbar:)`, EditorToolbar.swift:80-94; `private static let itemIdentifiers`, :31-33 | `theToolbarShowsTheToolsThenColourOptionsBackgroundZoomCopySaveAndUpload` | `EDPLACE` |

For phase-4a:107 nothing on the coordinator's side differs from an ordinary upload: `editorUpload` returns `(true, true)`
whatever the editor does meanwhile (+Editor:378), and the fake's `upload(asNew:)` would only replay its own copy of
`performUpload`'s rule, which `EditorUploadPlanTests.uploadOutcomeClosesWhenEnqueued` already pins as a pure rule. So no
part mark is honest before `EDPLACE`.

The rest of phase-4c:94 and :95 is D already: `EditorToolTests.fourteenToolsInToolbarOrder` (EditorToolTests.swift:19),
`everyToolHasSymbolAndTooltipWithLetter`, `EditorToolbarTests.everyToolSegmentHasItsToolTip`,
`KeyRoutingTests.sAndNPickSpotlightAndCounter` (KeyRoutingTests.swift:41), `editingTextSuppressesLetters`,
`shortcutTableMatchesExpectedChords`. In the `EDPLACE` phase :94 is full and :95 is part (the letter reaching the
`NSTextView` while editing is AppKit, by hand).

## 8. Where a line and the code disagree, and findings for the plan

- **phase-4a:132 (:192), its last step.** The line says that after the failed ⌘U, "Enter the right key, Retry Failed
  Uploads: the link shows the redacted image, not the original, and `pending/<UUID>.png` is gone". At a079a6f Retry
  Failed Uploads does nothing for this capture. The capture is an uploaded one (a never-uploaded file outside the current
  folder cannot be opened: `EditorInput.fileSource` answers `.unavailable(outsideSaveFolderText)`, EI:52-60, and Annotate
  is off for it, RecentCaptureFormatting.swift:133), so its ⌘U is a replace with a `priorUpload` (EUP:85, :116-121). The
  failure then returns the record to `.uploaded` at its link with `priorUpload` cleared (EUP:165-183, +Upload:708-719),
  not to `.failed`. `retryFailedUploads` retries only `history.failedRecords` (+Upload:496-507), which is
  `records.filter(\.isFailed)` (HS:127-129). `EditorUploadPlanTests.failedUploadOnlyReplaceKeepsEditedPendingFileAndMarksStale`
  (EditorUploadPlanTests.swift:214-235) says the same in its last line: "The next Upload from the editor replaces the
  object." The recovery that works is ⌘U again from a reopened editor, as phase-4a:133 says. The test pins both (Retry
  does nothing; the next upload replaces the key and removes the pending file). The line's wording is Tim's call: reword
  the last step to "Annotate on the row, ⌘U" or leave it; the mark should say the Retry step is not what recovers it. The
  judge's draft (its 9.5) said "retry … re-PUTs the key", which holds only for an interrupted replace
  (`retryOfInterruptedReplaceReusesKey`, EditorUploadPlanTests.swift:115-123, a record left `.failed` with
  `priorUpload.isReplace` by a quit).
- **phase-4a:131 (:191) and phase-4b:112 (:156), "after the retries".** A wrong secret access key gets S3's 403
  (`SignatureDoesNotMatch`), and a 4xx other than 429 is not retried (`UploadError.isRetryable`, Dest:177-181; the loop,
  UQ:193). There is one attempt and the notice follows it; the tests assert `attemptKeys == [key]` and `uploadAttempts ==
  1`. A 5xx would be retried up to 3 times (RetryPolicy.swift:10). The lines still read true for what the user sees; the
  wording could drop "after the retries", Tim's call.
- **The failure notice's title.** phase-4a:131 and phase-4b:112 quote the body `Upload failed. The link still shows the
  earlier image.`, which is `EditorUploadPlan.failedReplaceMessage` (EUP:31) exactly; the title is `Not uploaded`
  (+Upload:719), as harness D14 records. The upload-only test pins both and that no `Upload failed` title is posted.
- **phase-6a:199 (:211), "from the card".** After any Annotate the card is closed with `.editorOpened` (+Editor:91), not
  restorable (QuickAccessController.swift:19-24), so the third sentence's card cannot be pressed after the edit; only
  Recent Captures can. And in upload-only mode ⌘S is Save As…: an uploaded upload-only capture has no file, so
  `EditorSaveTarget.plan` is `.unavailable(noFileReason)` (EST:22), `saveCommand` is `.saveAs` (EST:78-84) and
  `performSave` opens the panel (EWC:247-254); `editorSaveAs` writes a copy elsewhere and never calls `removeDragFolder`
  (+Editor:283-304), which is right, since the capture did not change. So in the line's first sentence only ⌘U removes
  the drag folder; its "⌘S" holds for the last sentence (an edit saved over the file). Tim's call on the wording.
- **phase-7c:171 (:214).** Annotate while the first editor is still open brings that editor forward (+Editor:16-18) with
  its background still on; the line's flat reopen holds once the editor was closed. The test closes it first.
- **A name.** `EditorSaveTarget.uploadedCopyNotice(for:)` is a function (EST:59-61); the string `The uploaded copy still
  shows the original. Upload to replace it.` is the constant `EditorSaveTarget.uploadedCopyStaleNotice` (EST:19). The
  tests use the constant.
- **Two coordinators over one world.** The first coordinator's edit thumbnail task (+Editor:249-275) saves history when it
  finishes. The relaunch test waits for `thumbnailFileName != nil` and requires `isUploading == false` before the second
  coordinator loads, so the file it reads is final, and after the relaunch it calls nothing on the first coordinator and
  runs no `world.clock` (section 2's rule), so nothing writes the file from the first coordinator afterwards.
- **phase-6a:164 (:172).** No test can restore a card (the restore reads `NSScreen.screens`), so the line is part; the
  test's `uploadedUploadOnlyStaged` case runs the restore's quiet download first and shows Annotate then reads the drag
  copy, not the bucket, with no `Downloading` notice. The line's "from the bucket" holds for the copy's source; Tim's
  call whether to say so.

## 9. Suite files and totals

| Suite file | New or existing | Tests added | Of them the minimal design's built tests | Effort (S / M / L) |
|---|---|---|---|---|
| `TidyShotTests/CoordinatorEditorSaveTests.swift` | new | 17 | 2 (tests 1, 3) | 9 / 8 / 0 |
| `TidyShotTests/CoordinatorEditorUploadTests.swift` | new | 14 | 1 (test 2, edit changed) | 2 / 7 / 5 |
| `TidyShotTests/CoordinatorEditorTests.swift` | existing (2 tests today, header reworded) | 14 | 2 (tests 4, 5) | 6 / 8 / 0 |
| `TidyShotTests/CoordinatorOverlayTests.swift` | existing | 1 | 0 | 0 / 1 / 0 |
| `TidyShotTests/Support/EditorFakes.swift` | new support (design 3.1), no suite | 0 | built | |
| `TidyShotTests/Support/EditorPixels.swift` | new support (2.1), no suite | 0 | built by the review | |
| `TidyShotTests/Support/CoordinatorFakes.swift`, `CoordinatorWorld.swift` | existing support (design 3.2, 3.3) | 0 | built | |
| **All** | | **46** | 5 | 17 / 24 / 5 |

Totals:

- Tests: 46 new `@Test` functions (seven of them parameterized: `saveOverAnUploadedCapture…(link:)`,
  `saveAsOntoItsOwnFileIsASave(uploaded:)`, `aSaveOrSaveAsTakesTheClipboard…(write:userCopied:)`,
  `saveWithACrop…(scale:)`, `withTheOverlayOff…(mode:)`, `aRestoredCardsAnnotate…(restored:)`,
  `aComposedWindowCaptureOpensFlat…(composed:)`, each counted once). Before the merge the three catalogues had 50; four
  pairs became one test each.
- Lines: 73. Full 25. In part 40. Deferred 8: seven to `EDPLACE` (phase-4a:56, :58, :88, :151, phase-4c:94, :95,
  phase-7c:72) and one to `EDPLACE` and `BEEP` (phase-4a:107). Obsolete 0; already covered 0.
- Of the 40 in part, what stays: only the controller's own glue (`EDPLACE`) plus checks by hand that no seam reaches, 17
  (coordinator-split:43, phase-4a:37, :94, :95, :96, :99, :123, :124, :131, :132, :133, phase-4b:92, :106, :112, :113,
  phase-7c:169, :170); that glue and the capture's own clipboard copy, set up and not driven (`EDPLACE`, `TARGET`), 2
  (phase-4a:119, :120); a panel, a sheet, a beep or the quit's reply, with or without the glue (`EDSAVEAS`,
  `CLOSESHEET`, `BEEP`, `APPDELEGATE`), 11 (phase-4a:97, :102, :106, :127, :145, :146, :147, :148, :155, :162,
  phase-7c:172); another seam's (`PINS`, `SCREENS`, `SAVEAS`, `QASTACK`, `TARGET`, `EDDEFAULTS`, with `BGPOP` and
  `EDPLACE` for phase-7c:187), 8 (coordinator-split:44, phase-4c:201, phase-6a:131, :164, :198, :199, phase-6b:118,
  phase-7c:187); the popover's switch (`BGPOP`, `EDPLACE`) and Tim's call, 1 (phase-7c:171); the window coming forward,
  by hand with no seam, 1 (phase-4a:39).
- Part lines whose leftover includes `EDPLACE`: the 17 glue-only lines, the 2 with `TARGET`, 9 of the 11 panel, sheet and
  beep lines (all but phase-4a:155 and phase-7c:172), phase-7c:171 and phase-7c:187, so 30; with the 8 deferred, `EDPLACE`'s seams.md row
  holds 38 (design section 11).
- Effort: S 17, M 24, L 5.

Expected suite line after the phase: baseline `Test run with 2272 tests in 191 suites passed` at a079a6f; plus 46 tests
(each new `@Test` function once) and 2 suites (the two new files; `EditorFakes.swift` and `EditorPixels.swift` hold no
tests, and the two existing suites already count): `Test run with 2318 tests in 193 suites passed`.
