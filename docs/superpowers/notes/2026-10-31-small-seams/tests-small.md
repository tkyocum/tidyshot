# CT-3 test catalogue: the small seams (CLOP, SAVEAS, LOG)

The tests the three small seams give the 49 lines of `lines-small.md` (in this folder), in the form of
`docs/superpowers/notes/2026-10-30-editor-seam/tests-editor.md`: each test names its suite file, its entry point, the
record it opens, the fakes that observe it, what it asserts, its effort and every checklist line it covers. It merges
three catalogues that were written per seam (CLOP, SAVEAS, LOG) from the judge's decisions (`.superpowers/sdd/ct3/judge.md`,
scratch: the seams, the fakes and the rules each seam's tests follow; "the judge" below). The seams are
`AppEnvironment.clopOptimiser: any ClopOptimising` with `isClopRunning: @MainActor () -> Bool`, `AppEnvironment.chooseSaveAsURL`,
and `AppEnvironment.recordingLog` with `RecordingRecovery.scan(_:note:)`; the fakes are `FakeClop` (`TidyShotTests/Support/ClopFakes.swift`,
`world.clop`), `FakeSaveAsChooser` (`TidyShotTests/Support/CoordinatorFakes.swift`, `world.saveAsChooser`) and
`world.recordingLines`. None of it is in the tree at 30d3c15: every code reference below is at 30d3c15 (branch
`small-seams`, working tree clean), and a production line the seam moves is quoted where it stands today. Checklist lines
are named by catalogue key with the current line in brackets, as `lines-small.md` does. No Swift bodies; each entry gives
every value a body needs.

Reading the note: section 3 (CLOP), 4 (SAVEAS) and 5 (LOG) each keep their catalogue's own subsections, numbered
`CLOP.n`, `SAVEAS.n`, `LOG.n`; a bare "section n" inside a seam's text names that seam's subsection n. Within a seam the
tests are grouped under their suite file, the new suite file first. A test is cited by its name; the short ids are local
to a seam (`T1` to `T18` in CLOP, `1` to `10` and `E1` in SAVEAS, none in LOG). Each seam's introduction lists the
abbreviations its text uses; they do not clash (`+Upload`, `Coord`, `World`, `Fakes`, `FD` mean the same file everywhere).
## 1. Summary

34 tests: 15 in the new `CoordinatorClopTests`, 9 in the new `CoordinatorSaveAsTests`, 4 added to the existing
`CoordinatorRecordingTests`, 1 to `RecordingRecoveryTests`, 1 to `CoordinatorTrimTests`, 2 to `CoordinatorEditorUploadTests`
(one CLOP, one SAVEAS), 1 to `CoordinatorSaveTests`, 1 to `CoordinatorEditorSaveTests`. By seam: CLOP 18, SAVEAS 11 (ten
for lines, E1 for none), LOG 5. Two are parameterized and count once (CLOP T2 and T12). Of the 49 lines: full 28,
in part 18, deferred 3 (`recording-r3:416` and `:436` to `EXTRAS`, `recording-r4:217` to `TMPDIRS` and `CAPSRC`),
obsolete or already covered 0. Three CT-2 marks are extended (coordinator-split:44, phase-6a:198, phase-6a:199) and three
earlier ones (recording-r4:253, :255, :217). What ran: the designers built CLOP T1 to T5 (T3 is extended here with a third recording), SAVEAS 1 to 8 and LOG's five (two of them changed since, below) in scratch trees, and those 18 ran green together in the judge's merged tree (`Test run with 2336 tests in 195 suites passed`). Not run: CLOP T6 to T18, SAVEAS 9, 10 and E1 (16 tests, written from the code and the suites' idioms), the extension of T3, and the changes to LOG's `stopRecordingLogsWhatItDidInEachPhase` (a selection step) and `aSettingsPromptLogsItsAnswerOrWhyItWaits` (a refuse-first ask and a lock-held recording), which their entries describe. The expected suite line is in section 7.

### 1.1 CLOP (23 lines)

| Line (key, current line) | Test | Suite | Verdict |
|---|---|---|---|
| Line (key, current line) | Test | Suite | Verdict |
| phase-7-clop:21 (:23) | T1 `turningClopOffDuringAnOptimisationKeepsThatUploadOptimisedAndNotTheNext` | CoordinatorClopTests | part (Settings close, `defaults read`) |
| phase-7-clop:28 (:30) | T17 `anEditorUploadAndUploadAsNewEachSendClopsBytesAndTheLinkKeepsItsKey`; Retry leg: T1 | CoordinatorEditorUploadTests; CoordinatorClopTests | full |
| phase-7-clop:29 (:31) | T7 `aCaptureWhoseUploadFailsAfterClopKeepsItsPendingFileAtTheCapturedSize`; hold leg also T1 | CoordinatorClopTests | full |
| phase-7-clop:31 (:33) | T2 `aClopThatIsNotRunningOrSkipsUploadsTheOriginalWithOneLine(reason:line:)`, `.notSmaller` | CoordinatorClopTests | full |
| phase-7-clop:32 (:34) | T6 `threeUploadsWithAnImageHeldInClopTakeCountersInStartOrder` | CoordinatorClopTests | full |
| phase-7-clop:35 (:37) | T2, `.notRunning` | CoordinatorClopTests | full |
| phase-7-clop:36 (:38) | T2, `.converted` | CoordinatorClopTests | full |
| phase-7-clop:37 (:39) | T2, `.failed("Clop's port is unavailable")` | CoordinatorClopTests | full |
| phase-7-clop:41 (:43) | T8 `deletingAnImageWhileClopHoldsItCancelsAtOnceAndNothingUploads` | CoordinatorClopTests | full |
| phase-7-clop:42 (:44) | T9 `aDeleteDeclinedAtTheSecondAlertWhileClopHoldsLeavesTheCardCancelledAndARetryUploadsOnce` | CoordinatorClopTests | full |
| phase-7-clop:43 (:45) | T10 `aRetryBeforeClopsFirstAnswerUploadsOnceFromTheSecondAttempt` | CoordinatorClopTests | full |
| phase-7-clop:44 (:46) | T4 `changingUploadSettingsWhileClopHoldsAnUploadFinishesItAtItsOwnDestination` | CoordinatorClopTests | full |
| phase-7-clop:45 (:47) | T1 | CoordinatorClopTests | full |
| recording-r1:271 (:285) | T3 `deletingARecordingWhileClopHoldsItCancelsAtOnceAndLeavesNoMovieOrCounterGap`; sentence 1 already D | CoordinatorClopTests; CoordinatorDeleteTests | full |
| recording-r1:296 (:328) | T3 (Delete leg), T11 `aFailedRecordingUploadAfterClopLeavesNoMovieAndARetryAsksClopAgainFromTheOriginal` | CoordinatorClopTests | part (`TMPDIRS`: the container's real folder, the launch sweep) |
| recording-r1:297 (:329) | T12 `aRecordingUploadsItsOriginalWithoutOptimizingWhenClopIsOffOrNotRunning(setting:running:)` | CoordinatorClopTests | full |
| recording-r1:330 (:376) | T3 (no gap, consecutive keys) | CoordinatorClopTests | full |
| recording-r2:275 (:291) | T13 `aGIFUploadsAsMadeWithOneClopLinePerLaunch`, T14 `anMP4RecordingGoesThroughClopShowingOptimizingAndUploadsClopsMovie` | CoordinatorClopTests | part (`cmp` against the bucket, `grep` of the real stderr) |
| recording-r4:253 (:267) | T16 `anUploadTrimmedWithClopWhoseFileChangedAsksClopAgainAndSendsTheSecondTrim` | CoordinatorTrimTests | part (the link playing the second trim) |
| recording-r4:255 (:269) | T5 `aRecordingOverThePartThresholdKeepsClopsMovieAndARetryResumesWithoutClop`; T15 `aClopMovieThatCannotBeKeptForResumeLogsItAndSendsTheThrowawayCopy` | CoordinatorClopTests | full |
| recording-r4:323 (:372) | T5 | CoordinatorClopTests | full |
| small-tweaks:14 (:17) | T1 | CoordinatorClopTests | full |
| small-tweaks:15 (:18) | T14 (optimised size), T5 (kept variant); save half T18 `anMP4sSizeIsTheMovedFilesSize` | CoordinatorClopTests; CoordinatorSaveTests | full |

### 1.2 SAVEAS (14 lines)

| Line (key, current line) | Test | Suite | Verdict |
|---|---|---|---|
| Line (key, current line) | Test | Suite | Verdict |
| coordinator-split:44 (:48) | 1 `saveAsOfASavedImageCopiesItsBytesAndChangesNothingElse` | CoordinatorSaveAsTests | part (extends CT-2 mark) |
| phase-6a:170 (:189) | 1 | CoordinatorSaveAsTests | part |
| phase-6a:171 (:190) | 2 `anUploadOnlyCapturesSaveAsSuggestsTheTemplateNameAndCopiesItsPendingFile` | CoordinatorSaveAsTests | part |
| phase-6a:172 (:191) | 3 `anUploadOnlyCardsSaveAsWritesTheDragCopyOrDownloadsAfterThePanel` | CoordinatorSaveAsTests | part |
| phase-6a:174 (:193) | 1 | CoordinatorSaveAsTests | full |
| phase-6a:175 (:194) | 5 `aSaveAsPanelHeldThroughTheCardsAutoCloseStillSaves` | CoordinatorSaveAsTests | part |
| phase-6a:176 (:195) | 6 `saveAsFromAnyCardWritesThatCardsCapture` | CoordinatorSaveAsTests | part |
| phase-6a:198 (:220) | 3 (its first part) | CoordinatorSaveAsTests | part (extends CT-2 mark) |
| phase-6a:199 (:224) | 9 `saveAsAfterASaveOverTheFileWritesTheEditNotTheOriginal`, 10 `saveAsAfterAnEditorUploadOfAnUploadOnlyCaptureWritesTheEditDuringAndAfterThePut` | CoordinatorEditorSaveTests, CoordinatorEditorUploadTests | part (extends CT-2 mark) |
| recording-r1:313 (:353) | 7 `anUploadOnlyVideosSaveAsDownloadsToTheChosenFile` | CoordinatorSaveAsTests | part |
| recording-r1:340 (:397) | 1 (Save As…); the other verbs are existing tests, section 4 | CoordinatorSaveAsTests | full |
| recording-r2:264 (:278) | 8 `aGIFsSaveAsWritesTheGIFOverAnExistingFileToo` | CoordinatorSaveAsTests | part |
| recording-r2:670 (:750) | 1; as recording-r1:340 | CoordinatorSaveAsTests | full |
| recording-r4:277 (:294) | 4 `aRecordingsSaveAsDuringItsDragOutDownloadWaitsAndCopiesTheLandedFile` | CoordinatorSaveAsTests | full |

### 1.3 LOG (12 lines)

| Line (key, current line) | Test | Suite | Verdict |
|---|---|---|---|
| Line (key, current line) | Test | Suite | Verdict |
| coordinator-harness:27 (:27) | `stopRecordingLogsWhatItDidInEachPhase` | CoordinatorRecordingTests | full |
| recording-r1:263 (:277) | `aLeftoverThatDoesNotPlayIsRemovedAndLogged` | RecordingRecoveryTests | full |
| recording-r3:156 (:161) | `aStartLogsEachPromptsAnswerAndASecondPressWhileOneIsUp` | CoordinatorRecordingTests | full |
| recording-r3:162 (:167) | `aSettingsPromptLogsItsAnswerOrWhyItWaits` | CoordinatorRecordingTests | part |
| recording-r3:416 (:452) | none this phase | (`EXTRAS`) | deferred |
| recording-r3:419 (:457) | `aStartLogsEachPromptsAnswerAndASecondPressWhileOneIsUp` and `aSettingsPromptLogsItsAnswerOrWhyItWaits` | CoordinatorRecordingTests | part |
| recording-r3:436 (:482) | none this phase | (`EXTRAS`) | deferred |
| recording-r4:192 (:193) | `aSecondURLStartBeforeTheFirstTakesTheLockIsLogged` | CoordinatorRecordingTests | part |
| recording-r4:214 (:218) | `aSettingsPromptLogsItsAnswerOrWhyItWaits` | CoordinatorRecordingTests | part |
| recording-r4:217 (:221) | none this phase | (`TMPDIRS`, `CAPSRC`) | deferred |
| recording-r4:347 (:422) | `stopRecordingLogsWhatItDidInEachPhase` | CoordinatorRecordingTests | full |
| recording-r4:366 (:456) | `aSecondURLStartBeforeTheFirstTakesTheLockIsLogged` | CoordinatorRecordingTests | full |

## 2. What holds for every test here

Each seam's rules are in its own subsection 2 (`CLOP.2` from the judge's 1.5, `SAVEAS.2` from 2.5, `LOG.2` from 3.5). What
all of them share, from the phase's constraints (`.superpowers/sdd/ct3/context.md`):

- A suite is `@Suite(.timeLimit(.minutes(1)))`, owns a `CoordinatorWorld` built in `init() throws`, and each test opens with
  `defer { world.removeAll() }`. No `.serialized`. Own temp folders and defaults suite per test, never `AppSettings.shared`.
- No test touches the pasteboard, the Keychain, notifications, `NSWorkspace`, `NSRunningApplication`, `NSScreen.screens`,
  the `tmp/` statics, a window ordered front, a panel shown, the screen, a camera, a microphone, a sound, the real Clop app
  or the network.
- A held fake is cancellable and single-entry. The behaviour under test is never awaited directly: the test gates with
  `eventually` and `TaskWatch`, and cancels or releases a held task in a `defer` declared right after `defer { world.removeAll() }`
  (so it runs first). `HistoryStore` prunes on the real `Date()`.
- No test passes `recordingCanStart` (it makes the live `tmp/Recording`); every start parks at a prompt and a quit ends it
  (`LOG.2`).

### 2.1 What the merge changed

- Verdict counts. The CLOP catalogue's summary said "full 18, part 5" and "2336 in 194"; its own table has 19 full and 4
  part (phase-7-clop:21, recording-r1:296, recording-r2:275, recording-r4:253), which is the judge's count too. The totals here
  are counted from the three tables.
- No two entries were merged. No checklist line is in two seams' tables, and no two tests pin one rule: the pairs that look
  alike pin different paths. CLOP T2 (an image, the decision at +Upload:189) and T12 (a recording, the decision at +Upload:255)
  both read "Clop not running means the original uploads", but the two decisions are separate code. CLOP T3 (a recording
  deleted during a hold) and T8 (an image) differ in what they must also leave clean (the movie and the counter gap against the
  pending file and the card). T9 and T10 share a setup and differ in whether the Retry comes before or after the first answer.
  SAVEAS 4 and 7 are the recording's Save As with and without a drag-out download in flight. Where one line is covered by
  several tests, the line lists all of them (for example recording-r4:255 by T5 and T15, phase-6a:199 by SAVEAS 9 and 10 and
  the two CT-2 tests).
- Names. All 34 names were looked up in `TidyShotTests/` at 30d3c15: none exists, and no two are the same. They follow the
  suites' naming (a sentence in camelCase, parameterized tests with their argument labels).
- SAVEAS 9 and 10 are new tests on CT-2's helpers (the SAVEAS catalogue's choice), not the in-place extension of the CT-2 tests
  that the judge's call 6 and the designer's tests described. The merged marks are the same either way. The in-place form
  would add no test for those two lines (suite line 2350 instead of 2352) and edit `CoordinatorEditorSaveTests.saveOverTheFileRemovesTheDragCopyAndEveryReadGivesTheEdit`
  and `CoordinatorEditorUploadTests.uploadOfAnUploadOnlyCaptureRemovesItsDragCopyAndEveryReadGivesTheEdit` (and
  `CoordinatorEditorTests.anUploadedUploadOnlyCardsCopyImageAndAnnotateReadTheDragCopy` for phase-6a:198). Tim's call; the plan
  takes the new tests unless told otherwise.
- SAVEAS E1 (a Save As whose capture is deleted while the panel is up) covers no line. The judge recommends it (2.7) as the
  one branch of the changed function nothing else reaches; it is counted here (without it the suite line is 2351).
- CLOP T7 enters at `finishSave`, not `save(_:intent:)`, which no test can call (`CaptureTarget` holds an `SCDisplay` or `SCWindow`).
- recording-r1:340 and recording-r2:670 are full on the existing tests the SAVEAS catalogue names for the other verbs
  (`SAVEAS.4`); if one verb has no test for a screenshot they become part with the rest by hand.
## 3. CLOP: the Clop optimiser and the running check

The tests for the 23 CLOP lines of `lines-small.md`, in the form of `docs/superpowers/notes/2026-10-30-editor-seam/tests-editor.md`.
The seam, the fake and the rules are the judge's (`judge.md` section 1): `AppEnvironment.clopOptimiser: any ClopOptimising`,
`AppEnvironment.isClopRunning: @MainActor () -> Bool`, the main-actor `FakeClop` (`TidyShotTests/Support/ClopFakes.swift`, judge 1.3)
and `world.clop`. None of that is in the tree at 30d3c15 (the working tree is clean); the production lines cited below are at
30d3c15 and do not move under the seam (its one edit in `+Upload` swaps the expression on line 426 and keeps the line count).
No Swift bodies; each entry gives every value a body needs.

Abbreviations: `+Upload`, `+Delete`, `+Editor`, `+Trim`, `+Save`, `+Recording`, `+Overlay` = `TidyShot/App/AppCoordinator+<name>.swift`;
`Coord` = `TidyShot/App/AppCoordinator.swift`; `CO` = `TidyShot/Upload/ClopOptimiser.swift`; `MP` = `TidyShot/Upload/MultipartPlan.swift`;
`MS` = `TidyShot/Upload/MultipartStore.swift`; `EUP` = `TidyShot/Editor/Persistence/EditorUploadPlan.swift`; `CD` =
`TidyShot/History/CaptureDeletion.swift`; `SL` = `TidyShot/Output/SaveLocation.swift`; `World` = `TidyShotTests/Support/CoordinatorWorld.swift`;
`Fakes` = `TidyShotTests/Support/CoordinatorFakes.swift`; `FD` = `TidyShotTests/Support/FakeDestination.swift`; `EF` =
`TidyShotTests/Support/EditorFakes.swift`; `design` = `design-clop.md`. Checklist lines are named by catalogue key with the current line
in brackets, as `lines-small.md` does.

### CLOP.1 Lines already covered elsewhere

Obsolete or already covered: no line is obsolete (`lines-small.md`: none carries an `(obsolete: ...)` note). Parts already D, named in the
entries: phase-7-clop:21's persistence (`AppSettingsTests.optimiseWithClopDefaultsOffAndPersists`, AppSettingsTests.swift:240), the optimiser
halves of :31, :36, :37 (`ClopOptimiserTests.notSmallerReportedByClopReturnsNotSmaller` :128, `.aResultFileThatIsNotSmallerThanTheInputReturnsNotSmaller`
:137, `.anotherPathReturnsConverted` :148, `.convertedFromReturnsConverted` :173, `.aConvertedOutputBesideTheWorkFileIsRemoved` :158,
`.throwingTransportReturnsFailed` :116), recording-r1:271 sentence 1 (`CoordinatorDeleteTests.deleteDuringAnUploadCancelsItThenDeletesTheReservedKey`,
CoordinatorDeleteTests.swift:368), recording-r2:275's kind rule (`CaptureRecordTests.onlyAGIFIsNotSentToClop`, :438). No CLOP line carries a CT-2
mark; the two with marks (recording-r4:253, :255) carry earlier ones that name `CoordinatorUploadTests`, so each entry says what the merged mark
should read.

### CLOP.2 What holds for every test here

- Suites are `@Suite(.timeLimit(.minutes(1)))`, own a `CoordinatorWorld` built in `init() throws`, and each test opens with `defer { world.removeAll() }`
  (World:149-152). No `.serialized`. `CoordinatorClopTests.init` sets `world.multipartPlan = MultipartPlan(threshold: 1_048_576, partSize: 262_144,
  inFlight: 3)` and `world.settings.optimiseWithClop = true` (design section 5). The three tests in other suites (T16, T17, T18) set
  `world.settings.optimiseWithClop = true` themselves (T18 does not need it). `AppSettings.shared` is never touched; `world.settings` is the world's own
  defaults suite (World:33).
- Judge rules 1.5 apply as written. In short: every request has an `answers` element; a test that scripts `.hold` declares `defer {
  world.clop.release(FakeClop.cancelledAnswer) }` right after `defer { world.removeAll() }`, waits with `try await eventually { world.clop.isHolding }`
  (UploadQueueTests.swift:39-48, 2 s) and after its own `release(_:)` gates on `try await eventually { coordinator.clopWaitsPerLane.isEmpty }` (the
  start task's `defer`, +Upload:209-212; the task is not stored, :208). Delete during a hold runs in a `Task` with `defer { delete.cancel() }` and a
  `TaskWatch` (Fakes:418-431), gated by `eventually { deleteWatch.hasReturned }`, and the test then asserts `world.clop.isHolding` is still true:
  that is "cancels at once". The alerts are `world.confirm.answers` (Yes when empty, Fakes:196-221).
- Helpers each suite keeps for itself, as the existing suites do (none in `Support/`); in `CoordinatorClopTests`, as design section 5 gives them:
  `destination` (`world.factory.standard`); `addPendingImage(to:)` (`pending/<id>.png` of `CoordinatorWorld.pngData(width: 4, height: 2)`, `fileIsTemporary: true`,
  `.failed(message: "Upload was interrupted.")`, `byteCount: png.count`); `addPendingRecording(to:byteCount:)` (`pending/<id>.mp4`, sparse, 1600 by 1000, `mediaKind:
  .video`, `durationSeconds: 10`, same failed state, `byteCount: Int(byteCount)`); `isUploaded(_:_:)` (`history.record(id:)?.uploadedURL != nil`); `exists(_:)`.
  New here: `addSavedImage(to:in:)` (a real PNG `Saved <id>.png` in the given folder, `fileIsTemporary: false`, `.failed(message: "Upload was interrupted.")`,
  `byteCount: png.count`; the shape of `CoordinatorEditorUploadTests.addSavedImage`, CoordinatorEditorUploadTests.swift:46-57, which T17 uses directly) and
  `addGIF(to:)` (as `addPendingRecording` with `mediaKind: .gif`, `<id>.gif`, 3 bytes).
- Sparse files: `CoordinatorWorld.writeSparseFile(at:byteCount:)` (World:166-175). Sizes used: `threshold = MultipartPlan.standard.threshold` = 104_857_600
  (MP:20, "100 MiB"), `twice = 209_715_200`, `plusMiB = 105_906_176`. The kept-copy rule reads the static plan (+Upload:274), never `environment.multipartPlan`.
- A key template with a counter: `var config = CoordinatorWorld.config; config.keyTemplate = "s/{counter}"; world.settings.s3Config = config` (World:20-21,
  as design test 3). Keys are then `s/<n>.png` and `s/<n>.mp4`; `world.settings.currentCounter` (AppSettings.swift:461) is read before, and `nextCounter()`
  increments it (:466).
- `FakeDestination.publicURL(for:)` answers `https://snap.tky.io/<key>` for every destination (FD:274-276): tell destinations apart by the record's
  `objectLocation` and by which fake received the bytes.
- A failing PUT: `destination.state.withLock { $0.failuresRemaining = 1; $0.failure = .httpStatus(403, body: "AccessDenied: Access Denied") }`; a 403 is not
  retried (CoordinatorUploadTests.swift:536-552), and its record text is `Server returned HTTP 403: AccessDenied: Access Denied` for a data PUT and a file PUT
  alike (UploadQueue.swift:203, :209 take `error.localizedDescription`).
- A relaunch is a second `world.makeCoordinator()`; after it the test calls nothing on the first (tests-editor 2).
- Nothing outlives its test: a test whose upload reached `.uploaded` or `.failed` has waited for it; Clop's movie is removed detached (+Upload:418-422), so
  `try await eventually { world.clop.workFiles.isEmpty }` before the test returns where a movie was made.

### CLOP.3 CoordinatorClopTests.swift (new)

#### T1 `turningClopOffDuringAnOptimisationKeepsThatUploadOptimisedAndNotTheNext` (M, the design's test 1, built)

- Entry point: `coordinator.retryUpload(recordID:)` (+Upload:462-475) -> `retry` (:512) -> `startUpload` (:138), image decision at :189.
- Record: `addPendingImage` twice (one per retry), `.failed`, default key template (`{random:6}`, ObjectKeyNamer.defaultTemplate).
- Fakes and scripts: `world.clop.answers = [.hold]`; `smaller = Data("clop".utf8)` (4 bytes, fewer than the 4x2 PNG, so `FakeClop` accepts it); the second
  upload needs no answer. Rule 3 defers.
- Sequence: add `first`; `original = Data(contentsOf: pending)`; `retryUpload(first)`; `eventually isHolding`; assert; `world.settings.optimiseWithClop = false`;
  `world.clop.release(.smaller(smaller))`; `eventually isUploaded(first)`; `eventually clopWaitsPerLane.isEmpty`; assert; add `second`; `retryUpload(second)`;
  `eventually isUploaded(second)`; assert.
- Assertions, while held: `world.clop.requests == [.png(original)]` (+Upload:441); `world.clop.runningChecks == 1` (:189 -> :426); `Data(contentsOf: pending) ==
  original` (the file is never written, comment :197-198); the record is `.uploading(fraction: 0)` (:154); `destination.uploadAttempts == 0`. After the release:
  `destination.uploads.map(\.data) == [smaller]` (:442-443); `history.record(first.id)?.byteCount == smaller.count` (.uploaded sets `byteCount = sentBytes`, :666-668, from
  :290); `!world.logLines.contains { $0.hasPrefix("Clop:") }`. After the second: `world.clop.requests.count == 1`; `runningChecks == 1` (`&&` stops at the setting, :189);
  `uploads.map(\.data) == [smaller, secondOriginal]`; `history.record(second.id)?.byteCount == secondOriginal.count` (:192).
- By hand / seam: closing Settings without Save and `defaults read io.tky.tidyshot optimiseWithClop`; real Clop making a capture smaller.
- Effort M. Covers: phase-7-clop:21 (the effect on the next upload; part), :45 (full), small-tweaks:14 (full), phase-7-clop:29 (the hold leg: the pending file is
  full size while Clop runs), phase-7-clop:28 (the Retry leg).
- Mark, phase-7-clop:21: `(suite, in part: CoordinatorClopTests.turningClopOffDuringAnOptimisationKeepsThatUploadOptimisedAndNotTheNext,
  AppSettingsTests.optimiseWithClopDefaultsOffAndPersists; by hand: closing Settings with no Save, and `defaults read` of the real domain)`. phase-7-clop:45 and
  small-tweaks:14: see CLOP.5.

#### T2 `aClopThatIsNotRunningOrSkipsUploadsTheOriginalWithOneLine(reason:line:)` (S, the design's test 2, built; four arguments)

- Entry point: `retryUpload` on a pending PNG, as T1.
- Arguments (reason, the `Clop:` line):
  1. `.notRunning` -> `Clop: Clop is not running, uploading the original` (+Upload:427; `ClopSkipReason.notRunning.summary`, CO:24). Script: `world.clop.isRunning = false`, no answers.
  2. `.notSmaller` -> `Clop: the result is not smaller, uploading the original` (:456; CO:27). Script: `answers = [.original(.notSmaller)]`.
  3. `.converted` -> `Clop: Clop converted the file to another format, uploading the original` (CO:26). `answers = [.original(.converted)]`.
  4. `.failed("Clop's port is unavailable")` -> `Clop: Clop's port is unavailable, uploading the original` (CO:25 takes the detail; the live text is `describe(.portUnavailable)`, CO:229). `answers = [.original(.failed("Clop's port is unavailable"))]`.
- Assertions: `world.clop.runningChecks == 1`; `world.clop.requests == (reason == .notRunning ? [] : [.png(original)])`; `world.logLines.filter { $0.hasPrefix("Clop:") } ==
  [line]` (exactly one); `destination.uploads.map(\.data) == [original]`; `world.notifier.errors.isEmpty` (no notifier call in the Clop step, +Upload:433-435); `history.record(id)?.byteCount ==
  original.count` (:192, :290).
- By hand / seam: `TidyShot does not launch Clop` holds by code (`ClopApp` has no launch call, CO:257-284; `ClopClient` never opens an app); whether real Clop fails on a white fill, converts, or
  hits the free-tier cap (C); the optimiser rules (D, above).
- Effort S. Covers: phase-7-clop:31, :35, :36, :37 (all full).
- Mark: `(suite: CoordinatorClopTests.aClopThatIsNotRunningOrSkipsUploadsTheOriginalWithOneLine, ClopOptimiserTests.<the D test above>; by hand: none)`; for :31/:36/:37 the
  by-hand clause reads the line's own C part only if the line says so: the checklist text stays a check of real Clop, so `(suite: ...)` with the note `real Clop's behaviour is by hand` as `lines-small.md` records.

#### T3 `deletingARecordingWhileClopHoldsItCancelsAtOnceAndLeavesNoMovieOrCounterGap` (L, the design's test 3, built; extended here)

- Entry point: `retryUpload` of a pending recording, then `coordinator.deleteCapture(recordID:)` (+Delete:15).
- Record: three `addPendingRecording(byteCount: 3)` records (`deleted`, `next`, `third`), key template `s/{counter}`, `counter = world.settings.currentCounter` read first.
- Scripts: `world.clop.answers = [.hold, .smallerMovie(byteCount: 2), .smallerMovie(byteCount: 2)]`; the third is the extension (consecutive keys).
- Sequence: `retryUpload(deleted)`; `eventually isHolding`; assert; `delete = Task { await deleteCapture }` with `defer { delete.cancel() }`, `deleteWatch`; `eventually deleteWatch.hasReturned`; assert
  `isHolding` still true; `world.clop.release(.smallerMovie(byteCount: 2))`; `eventually clopWaitsPerLane.isEmpty`; `eventually workFiles.isEmpty`; assert; `retryUpload(next)`; `eventually isUploaded`; assert;
  `retryUpload(third)`; `eventually isUploaded`; assert.
- Assertions, while held: `requests == [.video(file, duration: 10)]` (+Upload:448); `coordinator.optimizingVideoIDs == [deleted.id]` (:257); `world.cards.calls.contains(.optimizing(deleted.id, true))` (:258 -> +Overlay:127).
  After Delete returns, Clop still holding: `world.confirm.asked.count == 1`; `history.record(deleted.id) == nil`; `!exists(file)` (+Delete:73, :95); `optimizingVideoIDs.isEmpty`, `uploadingIDs.isEmpty`, `fileUploadIDs.isEmpty` (cancelUpload
  :572-578, :567); the last `.optimizing` call for the id in `world.cards.calls` is `.optimizing(deleted.id, false)` (:573, :576 `refreshOverlay` -> `pushCardFlags`, +Overlay:127-129). After the release: `destination.uploadAttempts == 0`
  (`endUploadWait` false on the stale token, :307-309, and Clop's movie removed there, :308); `world.settings.currentCounter == counter` (a recording's counter is drawn in `makeJob`, :174, after :266);
  `workFiles.isEmpty`. `next`: `requests.count == 2`; `history.record(next.id)?.uploadedKey == "s/\(counter + 1).mp4"`; `byteCount == 2`; `currentCounter == counter + 1`; `workFiles.isEmpty` (eventually). `third`:
  `uploadedKey == "s/\(counter + 2).mp4"`, `currentCounter == counter + 2` (two recordings in a row get consecutive keys).
- By hand / seam: nothing for these lines; the 625 GB refusal that draws no counter (+Upload:263-271) is named in the line as unreachable by hand and is not asserted here (a sparse file over 671_088_640_000 bytes would reach it; not added).
- Effort L (three records, one hold, a Task). Covers: recording-r1:271 sentence 2 (full with the D sentence 1), recording-r1:296 (the Delete leg; part), recording-r1:330 (full).
- Mark: see CLOP.5, which is the mark source (spec section 6).

#### T4 `changingUploadSettingsWhileClopHoldsAnUploadFinishesItAtItsOwnDestination` (M, the design's test 4, built)

- Entry point: `retryUpload`, then `coordinator.destinationDidChange()` (+Upload:78-94; the Upload tab's Save calls it, UploadSettingsView.swift:151, :169).
- Record: two `addPendingImage` records. Scripts: `answers = [.hold, .smaller(smaller)]`, `smaller = Data("clop".utf8)`; a second destination `other = FakeDestination()` added with `world.factory.add(other, at: ObjectLocation(config: moved))`, `moved = CoordinatorWorld.config` with `bucket = "other.tky.io"` and
  `publicURLTemplate = "https://other.tky.io/{key}"`; `world.settings.s3Config = moved`.
- Assertions, with the request held: `coordinator.queue == nil` (:82); `drainingQueues.count == 1` (:83); after `try await world.clock.run(for: .seconds(1))` still `1` (the poll keeps the lane while `clopWaitsPerLane[old] != 0`, :89-90).
  After `release(.smaller(smaller))`: `isUploaded(first)`; `history.record(first.id)?.objectLocation == world.location`; `destination.uploads.map(\.data) == [smaller]`; `world.clipboard.copies.last == .url(firstURL)` (:699). The second upload: `objectLocation == ObjectLocation(config: moved)`;
  `other.uploads.map(\.data) == [smaller]`; `destination.uploadAttempts == 1`; `try await world.clock.run(until: { coordinator.drainingQueues.isEmpty })`; `coordinator.clopWaitsPerLane.isEmpty`.
- By hand / seam: the 65,536 px capture and the bucket check by hand; `CoordinatorUploadTests.aReplacedLaneDrainsUntilIdle` pins draining with a job in flight, this is the only test of the `clopWaitsPerLane` condition (:89).
- Effort M. Covers: phase-7-clop:44 (full).
- Mark: see CLOP.5, which is the mark source (spec section 6).

#### T5 `aRecordingOverThePartThresholdKeepsClopsMovieAndARetryResumesWithoutClop` (M, the design's test 5, built)

- Entry point: `retryUpload` twice on a pending recording.
- Record: `addPendingRecording(byteCount: 2 * threshold)` (209_715_200 sparse). World: `multipartPlan = MultipartPlan(threshold: 1_048_576, partSize: MultipartPlan.maxPartSize, inFlight: 1)`; `world.date = Date(timeIntervalSinceNow: 3600)` (so the kept copy is not outdated,
  MP:98-102; rule 7); `destination.state.withLock { $0.partFailures = [2: [.httpStatus(403, body: "AccessDenied: Access Denied")]] }`; `world.clop.answers = [.smallerMovie(byteCount: threshold)]`.
- Sequence: first `retryUpload`; `eventually` the record's state is `.failed(message: "Part 2 of 2: Server returned HTTP 403: AccessDenied: Access Denied")` (UploadQueue+Parts.swift:13); assert; second `retryUpload`; `eventually isUploaded`; assert; `eventually !exists(keptCopy)`.
- Assertions after the failure: `exists(keptCopy)` with `keptCopy = coordinator.multipartFiles.keptCopyURL(for: record.id, ext: "mp4")` (MS:27-29), moved there at +Upload:274-280; `world.clop.workFiles.isEmpty` (moved out of `tmp/Clop`);
  `record.multipart?.sourcePath == keptCopy.path(percentEncoded: false)`; `record.multipart?.byteCount == threshold`. After the resume: `world.clop.requests.count == 1`; `runningChecks == 1` (a resume has `runsClop` false, so `clopIsRunning` is not asked, :238-247, MP:110);
  `world.logLines.contains("Upload: \(keptCopy.lastPathComponent) resumes at 1 of 2 parts")` (UploadQueue+Multipart.swift:201); `destination.creates.count == 1`; `record.byteCount == Int(threshold)` (:245, :667); the kept copy is gone (`.uploaded` takes it, :638-639).
- By hand / seam: Wi-Fi off, a relaunch; the sidecar and kept copy after a relaunch are `MultipartStore` tests (D).
- Effort M. Covers: recording-r4:255 (first half), recording-r4:323 (full), small-tweaks:15 (the kept-copy variant of the optimised size).
- Mark: see CLOP.5, which is the mark source (spec section 6).

#### T6 `threeUploadsWithAnImageHeldInClopTakeCountersInStartOrder` (M)

- Entry point: three synchronous `coordinator.retryUpload(recordID:)` calls (the start tasks run FIFO on the main actor at the next suspension).
- Record: three `addPendingImage` records `a`, `b`, `c`. Template `s/{counter}`; `n = world.settings.currentCounter` read first. Scripts: `world.clop.answers = [.smaller(Data("a".utf8)), .hold, .smaller(Data("c".utf8))]`. Each request is answered in call order: a start task's first await after `optimisedPNG` is `Self.byteCount`, but `FakeClop.optimisedPNG`
  itself does not suspend for a non-hold answer, so the order of requests is a, b, c.
- Sequence: `retryUpload(a); retryUpload(b); retryUpload(c)` with no await between; assert the counters; `eventually isHolding`; `eventually isUploaded(a)` and `isUploaded(c)`; assert; release `.smaller(Data("b".utf8))`; `eventually isUploaded(b)`; `eventually clopWaitsPerLane.isEmpty`.
- Assertions, straight after the three calls: `world.settings.currentCounter == n + 3` (an image's counter is drawn at +Upload:168, before Clop, synchronously); `world.clop.runningChecks == 3`. While `b` holds: `history.record(a.id)?.uploadedKey == "s/\(n + 1).png"`,
  `history.record(c.id)?.uploadedKey == "s/\(n + 3).png"`, `history.record(b.id)?.uploadState == .uploading(fraction: 0)`, `Set(destination.attemptKeys) == ["s/\(n + 1).png", "s/\(n + 3).png"]` (a set, not an order: two enqueued jobs may interleave). After the release:
  `history.record(b.id)?.uploadedKey == "s/\(n + 2).png"`; `world.clop.requests.count == 3`; `destination.uploads.count == 3`; `world.settings.currentCounter == n + 3` (unchanged by the uploads).
- By hand / seam: the "large scrolling capture that takes seconds" is the hold; `defaults read ... captureCounter` is `currentCounter` on the world's suite.
- Effort M. Covers: phase-7-clop:32 (full).
- Mark: see CLOP.5, which is the mark source (spec section 6).

#### T7 `aCaptureWhoseUploadFailsAfterClopKeepsItsPendingFileAtTheCapturedSize` (M)

- Entry point: `coordinator.finishSave(_:image:scale:captureDisplayID:notConfiguredWarning:showsCard:upload:payload:notification:)` (+Save:201), as `CoordinatorSaveTests.aCaptureWithTheOverlayOffShowsNoCardAndStillUploads` does (CoordinatorSaveTests.swift:79-97); `save(_:intent:)` itself needs a `CaptureResult`, whose `CaptureTarget` holds an `SCDisplay` or `SCWindow` that no test can build (CaptureTarget.swift:5-9, :59-64).
- Record: `id = UUID()`; `png = CoordinatorWorld.pngData(width: 4, height: 2)`; `file = coordinator.pendingFiles.write(png, id: id, ext: "png")`; `CaptureRecord(id:, fileURL: file, fileIsTemporary: true, pixelWidth: 4, pixelHeight: 2, appName: nil, uploadState: .uploading(fraction: 0), byteCount: png.count)` (upload-only mode: `fileIsTemporary: action == .uploadOnly`, +Save:~150).
  Call: `finishSave(record, image: nil, scale: 1, captureDisplayID: 1, notConfiguredWarning: nil, showsCard: false, upload: coordinator.makeDestination(), payload: { .data(png) }, notification: .none)`. `image: nil` so no thumbnail task outlives the test (`image.map { makeThumbnail }`), `showsCard: false` so nothing reads the screens.
- Scripts: `world.clop.answers = [.hold]`; `destination.state.withLock { $0.failuresRemaining = 1; $0.failure = .httpStatus(403, body: "AccessDenied: Access Denied") }`; `clopBytes = Data("clop".utf8)`.
- Sequence: `await finishSave(...)` (it returns after `startUpload`, which does not wait for Clop); `eventually isHolding`; assert; `release(.smaller(clopBytes))`; `eventually` the record `.isFailed`; `eventually clopWaitsPerLane.isEmpty`; assert.
- Assertions, while held: `world.clop.requests == [.png(png)]`; `Data(contentsOf: file) == png`; `history.record(id)?.fileURL == file`; `fileIsTemporary == true`; `byteCount == png.count`; `destination.uploadAttempts == 0`. After the failure: `history.record(id)?.uploadState == .failed(message: "Server returned HTTP 403: AccessDenied: Access Denied")`;
  `destination.uploadAttempts == 1`; `destination.uploads.isEmpty`; `exists(file)` and `Data(contentsOf: file) == png` (still the captured size, not `clopBytes.count`); `history.record(id)?.byteCount == png.count` (the `.failed` event does not take `sentByteCounts` into the record, :597-603, :708-711); `world.notifier.errors.last?.title == "Upload failed"`.
- By hand / seam: network off and the container path.
- Effort M. Covers: phase-7-clop:29 (full; the success leg, the object optimised, is T1's same path).
- Mark: see CLOP.5, which is the mark source (spec section 6).

#### T8 `deletingAnImageWhileClopHoldsItCancelsAtOnceAndNothingUploads` (S)

- Entry point: `retryUpload`, then `deleteCapture(recordID:)` in a `Task` (rule 4).
- Record: `addPendingImage` (pending file, fileIsTemporary). Scripts: `answers = [.hold]`; `world.confirm.answers` empty (Yes). Rule 3 defers.
- Sequence: `retryUpload`; `eventually isHolding`; `uploading = history.record(id)`; delete Task; `eventually deleteWatch.hasReturned`; assert; `release(.smaller(Data("x".utf8)))`; `eventually clopWaitsPerLane.isEmpty`; assert.
- Assertions after Delete returns: `world.clop.isHolding`; `world.confirm.asked == [.delete(uploading)]` (+Delete:32); `history.record(id) == nil` (:95); `!exists(pending)` (:73); `coordinator.optimisingIDs[id] == nil`, `uploadingIDs.isEmpty` (+Upload:572-575); `world.cards.closes == [.deleted]` (+Delete:204). After the release: `destination.uploadAttempts == 0`
  (the answer is dropped at :307, an image's bytes with it); `coordinator.queue` has no job (`await coordinator.queue?.queue.isIdle == true`, as CoordinatorUploadTests.swift:~365); `!coordinator.isUploading`.
- By hand / seam: the 65,536 px capture and the bucket after a minute.
- Effort S. Covers: phase-7-clop:41 (full).
- Mark: see CLOP.5, which is the mark source (spec section 6).

#### T9 `aDeleteDeclinedAtTheSecondAlertWhileClopHoldsLeavesTheCardCancelledAndARetryUploadsOnce` (L)

- Entry point: `retryUpload`, `deleteCapture` (in a `Task`), `retryUpload` again, `deleteCapture` again.
- Record: a save-folder PNG, so that its removal fails the way the line's stand-in does (+Delete:76-88): `folder = try world.storeSaveFolder()` (World:159-164); a real PNG at `folder/Saved <id>.png` (`addSavedImage`, `fileIsTemporary: false`, `.failed(message: "Upload was interrupted.")`); then
  `FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: folder.path(percentEncoded: false))` with `defer { try? setAttributes([.posixPermissions: 0o755], ...) }` declared after `defer { world.removeAll() }` (so it runs first; the pattern is CoordinatorDeleteTests.swift:290-291). The retry only reads the file (`saveLocation.read`, SL:94-99,
  works in a 0o555 folder), Clop never writes it, and `SaveLocation.remove(at:)` then throws on `removeItem` (SL:149-161), which is the second alert's trigger. A pending file does not fit: its failed removal posts `Not deleted` with no second alert (+Delete:73).
  Template `s/{counter}`, `n = currentCounter`.
- Scripts: `world.clop.answers = [.hold, .smaller(second)]` with `second = Data("second".utf8)`; `world.confirm.answers = [true, false]`.
- Sequence: `retryUpload`; `eventually isHolding`; delete Task, `eventually deleteWatch.hasReturned`; assert; `release(.smaller(Data("first".utf8)))`; `eventually clopWaitsPerLane.isEmpty`; assert; `retryUpload`; `eventually isUploaded`; assert; `world.confirm.answers = [true, true]`; delete Task, `eventually deleteWatch.hasReturned`; assert.
- Assertions after the first Delete: `world.confirm.asked.count == 2`; `asked[1]` is `.removeFromHistory(message:informativeText:)` with `informativeText == CaptureDeletion.fileFailureText` (`"Remove it from history anyway? The file stays where it is."`, CD:15) and `message.hasPrefix("Couldn't delete the file: ")` (CD:131-133; the reason is the OS's text, so a prefix);
  `history.record(id)?.uploadState == .failed(message: "Upload cancelled.")` (+Upload:575); `world.cards.updates(for: id).last == .failed(message: "Upload cancelled.")` (:576); `exists(file)`; `uploadingIDs.isEmpty`; `world.clop.isHolding` (Delete did not wait). After the first release: `destination.uploadAttempts == 0`.
  After the Retry: `destination.uploads.map(\.data) == [second]`; `destination.attemptKeys == ["s/\(n + 2).png"]` (the first attempt drew `n + 1` at :168 and never uploaded); `history.record(id)?.uploadedKey == "s/\(n + 2).png"`; `destination.uploadAttempts == 1` (one new object, not two). After the second Delete: `asked.count == 4` (a Delete and a Remove again); `history.record(id) == nil`
  (`removeFromHistoryOnly`, +Delete:85, :177-184; a non-temporary file is left); `exists(file)` (stays where it is); `destination.deletedKeys == ["s/\(n + 2).png"]` (the object is deleted before the file step, :54-69).
- By hand / seam: the save-folder change in Settings > General is the manual stand-in for the failed removal; the test uses folder permissions.
- Effort L (permissions, two Deletes, a Retry). Covers: phase-7-clop:42 (full).
- Mark: see CLOP.5, which is the mark source (spec section 6).

#### T10 `aRetryBeforeClopsFirstAnswerUploadsOnceFromTheSecondAttempt` (L)

- Entry point: as T9, but the Retry comes while the first request still holds.
- Record, folder permissions, template, `n`: as T9. Scripts: `answers = [.hold, .smaller(second)]`; `world.confirm.answers = [true, false]`.
- Sequence: `retryUpload` (first); `eventually isHolding`; delete Task, `eventually deleteWatch.hasReturned`; assert; `retryUpload` (second); `eventually isUploaded`; assert; `release(.smaller(Data("first".utf8)))`; `eventually clopWaitsPerLane.isEmpty`; assert again.
- Assertions: after the Delete as T9 (`.failed(message: "Upload cancelled.")`, two alerts, record kept, `world.clop.isHolding`). After the Retry has uploaded, the first still held: `world.clop.requests.count == 2`; `destination.uploads.map(\.data) == [second]`; `destination.attemptKeys == ["s/\(n + 2).png"]`; `history.record(id)?.uploadedKey == "s/\(n + 2).png"` (the second attempt's own counter). After the first
  is released: nothing more: `destination.uploadAttempts == 1`, `uploads.map(\.data) == [second]` (the first start task sees `optimisingIDs[id] != its token`, :307, and returns), `world.clipboard.copies.count == 1`, `history.record(id)?.uploadedKey` unchanged. The fake answers the Retry's request before the first where the app's static queue answers the first first (CO:85);
  the token check drops the first either way, which is what the line is about.
- By hand / seam: the 65,536 px capture and the bucket.
- Effort L. Covers: phase-7-clop:43 (full).
- Mark: see CLOP.5, which is the mark source (spec section 6).

#### T11 `aFailedRecordingUploadAfterClopLeavesNoMovieAndARetryAsksClopAgainFromTheOriginal` (M)

- Entry point: `retryUpload` twice on a pending recording.
- Record: `addPendingRecording(byteCount: 3)` (under the lane's 1 MiB threshold, so a single PUT of Clop's movie, `upload(fileAt:)`). Scripts: `answers = [.smallerMovie(byteCount: 2), .smallerMovie(byteCount: 2)]`; `destination.state.withLock { $0.failuresRemaining = 1; $0.failure = .httpStatus(403, body: "AccessDenied: Access Denied") }`.
- Sequence: `retryUpload`; `eventually` the record is `.failed(message: "Server returned HTTP 403: AccessDenied: Access Denied")`; `eventually workFiles.isEmpty`; assert; `retryUpload`; `eventually isUploaded`; `eventually workFiles.isEmpty`; assert.
- Assertions after the failure: `world.clop.requests == [.video(file, duration: 10)]`; `world.clop.workFiles.isEmpty` (`.failed` takes `clopResults`, +Upload:600-602, and removes the movie detached, :418-422); `destination.attemptFiles.count == 1` and its parent folder is `Clop` (`attemptFiles[0].deletingLastPathComponent().lastPathComponent == "Clop"`);
  `exists(file)` (the record's file untouched). After the Retry: `requests == [.video(file, duration: 10), .video(file, duration: 10)]` (Clop is asked again from the original, never from the first movie); `runningChecks == 2`; `destination.fileUploads.count == 1`; `attemptFiles.count == 2` and `attemptFiles[0] != attemptFiles[1]`; `history.record(id)?.byteCount == 2`; `workFiles.isEmpty`.
  The after-an-optimised-upload case is the end of this sequence; the after-a-Delete case is T3.
- By hand / seam: `ls $C/tmp/Clop` in the real container, and the launch sweep of `ClopApp.workDirectory` at `start()` (Coord:297-298; no test calls `start()`): `TMPDIRS`.
- Effort M. Covers: recording-r1:296 (part).
- Mark: see CLOP.5, which is the mark source (spec section 6).

#### T12 `aRecordingUploadsItsOriginalWithoutOptimizingWhenClopIsOffOrNotRunning(setting:running:)` (S; two arguments)

- Entry point: `retryUpload` of a pending recording (`addPendingRecording(byteCount: 3)`); the decision is at +Upload:255.
- Arguments (optimiseWithClop, isRunning, expected Clop lines, runningChecks): `(false, true, [], 0)` (Clop off); `(true, false, ["Clop: Clop is not running, uploading the original"], 1)`. Scripts: `world.settings.optimiseWithClop = setting`; `world.clop.isRunning = running`; no answers.
- Assertions: `world.clop.requests.isEmpty`; `world.clop.runningChecks == runningChecks`; `world.logLines.filter { $0.hasPrefix("Clop:") }` equals the lines; `world.cards.calls.contains(.optimizing(id, true)) == false`; `coordinator.optimizingVideoIDs.isEmpty`; `destination.fileUploads.map(\.url.lastPathComponent) == [pending.lastPathComponent]`
  (the original, as CoordinatorSaveTests.swift:141 reads it); `world.notifier.errors.isEmpty`.
- By hand / seam: "TidyShot does not launch Clop": by code (no launch call).
- Effort S. Covers: recording-r1:297 (full; the Clop-off half was A without a seam, but no test existed, so it is asserted here too).
- Mark: see CLOP.5, which is the mark source (spec section 6).

#### T13 `aGIFUploadsAsMadeWithOneClopLinePerLaunch` (M)

- Entry point: `retryUpload` of pending GIFs; the line is logged at +Upload:184-187 (`loggedGIFNotSentToClop`, Coord:190), `isSentToClop` is false for a GIF (CaptureRecord.swift:36).
- Record: `addGIF(to:)` x4 (3 sparse bytes, `<id>.gif`, `mediaKind: .gif`, `durationSeconds: 10`). No answers: nothing may ask Clop.
- Sequence: coordinator A: `retryUpload(gif1)`, `eventually isUploaded`, assert; `retryUpload(gif2)`, `eventually isUploaded`, assert. Coordinator B (`world.makeCoordinator()` again, the relaunch; add `gif3` to B's history): `retryUpload(gif3)`, assert. Then `world.settings.optimiseWithClop = false`; coordinator C: add `gif4`, `retryUpload`, assert.
- Assertions: after gif1: `world.logLines.filter { $0 == "Clop: GIFs are not sent to Clop" }.count == 1`; `destination.fileUploads.map(\.contentType) == ["image/gif"]` (as CoordinatorSaveTests.swift:173); `destination.fileUploads.map(\.url.lastPathComponent) == [pending1.lastPathComponent]` (as made); no `.optimizing(gif1.id, true)`
  in `world.cards.calls`; `world.clop.runningChecks == 0` (a GIF never asks, :184-189, :255); `world.clop.requests.isEmpty`. After gif2 (same coordinator): count still 1. After gif3 (new coordinator): count 2. After gif4 with the setting off: count still 2 (the line needs `settings.optimiseWithClop`, :184).
- By hand / seam: `curl` and `cmp` of the bucket object against the saved file, and `grep` of the real `tidyshot.err` (the log reaches `NSLog` there).
- Effort M. Covers: recording-r2:275 (GIF half).
- Mark, recording-r2:275: `(suite, in part: CoordinatorClopTests.aGIFUploadsAsMadeWithOneClopLinePerLaunch, .anMP4RecordingGoesThroughClopShowingOptimizingAndUploadsClopsMovie, CaptureRecordTests.onlyAGIFIsNotSentToClop; by hand: cmp against the bucket's object, and the real stderr)`.

#### T14 `anMP4RecordingGoesThroughClopShowingOptimizingAndUploadsClopsMovie` (S)

- Entry point: `retryUpload` of a pending recording (`addPendingRecording(byteCount: 3)`).
- Scripts: `answers = [.hold]`, then `release(.smallerMovie(byteCount: 2))`. Rule 3 defers.
- Assertions, while held: `coordinator.optimizingVideoIDs == [id]` (+Upload:257); `world.cards.calls.contains(.optimizing(id, true))` (:258); the record is `.uploading(fraction: 0)`; `destination.uploadAttempts == 0`. After the release and `isUploaded`: `optimizingVideoIDs.isEmpty` (:312); the last `.optimizing` call for the id is `.optimizing(id, false)`;
  `destination.fileUploads.map(\.url.lastPathComponent)` has one `.mp4` name that is not the pending file's, and `fileUploads[0].url.deletingLastPathComponent().lastPathComponent == "Clop"` (:449-451); `history.record(id)?.byteCount == 2` (Clop's size, :290, :667); `eventually workFiles.isEmpty`.
- By hand / seam: "a smaller object" in the bucket against the saved file is real Clop (C).
- Effort S. Covers: recording-r2:275 (MP4 half), small-tweaks:15 (optimised size).
- Mark: see CLOP.5, which is the mark source (spec section 6).

#### T15 `aClopMovieThatCannotBeKeptForResumeLogsItAndSendsTheThrowawayCopy` (M)

- Entry point: `retryUpload` of a pending recording whose Clop movie is at the keep threshold.
- Record: `addPendingRecording(byteCount: 2 * threshold)`. World: `multipartPlan = MultipartPlan(threshold: 1_073_741_824, partSize: 16_777_216, inFlight: 1)` (above Clop's 104_857_600 bytes, so the job is one PUT and writes no sidecar into the read-only folder; the keep still reads the static `MultipartPlan.standard`, +Upload:274). Scripts: `answers = [.smallerMovie(byteCount: threshold)]`.
- Setup: `multipartDirectory = coordinator.multipartFiles.directory` (MS:11); create it (`createDirectory(withIntermediateDirectories: true)`); `setAttributes([.posixPermissions: 0o555], ...)` with the restoring `defer` after `removeAll()`'s. `keepClopCopy` then finds the folder, and `moveItem` into it fails (MS:48-56).
- Assertions: `eventually isUploaded`; `world.logLines.first { $0.hasPrefix("Upload: Clop's copy could not be kept for resume: ") }` exists and has text after the prefix (the OS error, +Upload:282; asserted as prefix plus non-empty rest, since the reason is `localizedDescription`); `destination.fileUploads.count == 1`; its url's folder is `Clop` (the throwaway copy was sent, :283, :449-451);
  `destination.creates.isEmpty` (a single PUT); `!exists(coordinator.multipartFiles.keptCopyURL(for: id, ext: "mp4"))`; `history.record(id)?.byteCount == Int(threshold)`; `history.record(id)?.multipart == nil`; `eventually workFiles.isEmpty` (`clopResults` removed on `.uploaded`, :600-602).
- By hand / seam: the actual error text.
- Effort M. Covers: recording-r4:255 (second half; full with T5).
- Mark, recording-r4:255: `(suite: CoordinatorClopTests.aRecordingOverThePartThresholdKeepsClopsMovieAndARetryResumesWithoutClop, .aClopMovieThatCannotBeKeptForResumeLogsItAndSendsTheThrowawayCopy, CoordinatorUploadTests.anUploadedResumeClearsItsStateSidecarAndKeptCopy)`. The earlier `in part` goes: both halves are asserted. The kept copy's resume after a relaunch is the D `MultipartStoreTests` and `CoordinatorUploadTests`.
### CLOP.4 Added to existing suites: CoordinatorTrimTests (T16), CoordinatorEditorUploadTests (T17), CoordinatorSaveTests (T18)

#### T16 `anUploadTrimmedWithClopWhoseFileChangedAsksClopAgainAndSendsTheSecondTrim` (L; CoordinatorTrimTests)

- Entry point: `coordinator.uploadTrimmed(recordID:)` (+Trim:379) -> `uploadTrimmedFile` (:420-446) -> `startPlannedUpload` (+Upload:102-111, `.replace(key:)` -> `startUpload(fixedKey:)`). The suite's `addTrimmedUpload(to:byteCount:key:)` (CoordinatorTrimTests.swift:20-34) makes the record: an uploaded recording in `pending/`, `uploadIsStale: true`, key `s/REC.mp4`, `durationSeconds: 10`.
- Record: `addTrimmedUpload(to: coordinator, byteCount: 2 * threshold)` (209_715_200 sparse). World: `multipartPlan = MultipartPlan(threshold: 1_048_576, partSize: MultipartPlan.maxPartSize, inFlight: 1)`; `world.date = Date(timeIntervalSinceNow: 3600)` (the upload's `startedAt`, an hour ahead of the file's real modification date);
  `world.settings.optimiseWithClop = true`; `destination.state.withLock { $0.partFailures = [2: [.httpStatus(403, body: "AccessDenied: Access Denied")]] }` (consumed by the first run); `world.clop.answers = [.smallerMovie(byteCount: threshold), .smallerMovie(byteCount: plusMiB)]`.
- Sequence: `uploadTrimmed`; `eventually` `world.notifier.calls.contains(.error(title: "Not uploaded", message: EditorUploadPlan.failedReplaceRecordingMessage))` (as CoordinatorTrimTests.swift:70-72); assert; the trim since: `setAttributes([.modificationDate: Date(timeIntervalSinceNow: 7200)], ofItemAtPath: file.path)`
  (a modification date after `startedAt`, so the kept copy reads as outdated); `uploadTrimmed` again; `eventually` `history.record(id)?.uploadIsStale == false`; assert; `eventually !exists(keptCopy)`.
- Assertions after the failure: `world.clop.requests == [.video(file, duration: 10)]`; `exists(keptCopy)` (`keptCopyURL(for:ext: "mp4")`, kept at +Upload:274-280); `record.multipart?.sourcePath == keptCopy.path(percentEncoded: false)`, `.byteCount == threshold`; `record.uploadState == .uploaded(url: <link>, key: "s/REC.mp4")` and `uploadIsStale` still true (EUP:165-183); `world.logLines.contains("Upload failed, the earlier link is kept: Part 2 of 2: Server returned HTTP 403: AccessDenied: Access Denied")` (+Upload:715).
  After the second: `world.logLines.contains("Upload: \(file.lastPathComponent) source changed, starting again")` (+Upload:222-237; `MultipartPlan.keptCopyIsOutdated`, MP:98-102); `world.clop.requests == [.video(file, duration: 10), .video(file, duration: 10)]` (a second Clop run, not a resume: no `resumes at` line); `Set(destination.aborts.map(\.uploadID)) == ["upload-1"]` (the stored upload is aborted first,
  `step.abortFirst`); `destination.creates.count == 2`; `destination.completes.map(\.uploadID) == ["upload-2"]`; `history.record(id)?.byteCount == Int(plusMiB)` (the second movie's size, so the second trim is what was sent); `history.record(id)?.uploadedKey == "s/REC.mp4"`; the kept copy is gone after `.uploaded`. The control (no touch, the same call resumes) is `CoordinatorTrimTests.uploadTrimmedReplacesInPartsKeepsTheLinkOnFailureAndResumes` for a file with no Clop, and T5 for a kept copy.
- By hand / seam: the link playing the second trim, not the first (CloudFront, C); Wi-Fi off for two minutes is the `partFailures` script.
- Effort L (200 MiB sparse, digested up to four times: 64, 36, 64, 37 MiB; the design measured about 1.7 s for its five including a similar pair).
- Covers: recording-r4:253 (part).
- Mark, recording-r4:253: `(suite, in part: CoordinatorUploadTests.anOutdatedKeptClopCopyCountsAsAChangedSource, CoordinatorTrimTests.anUploadTrimmedWithClopWhoseFileChangedAsksClopAgainAndSendsTheSecondTrim; by hand: the link playing the second trim, not the first)`. It keeps `in part`; the mark was `(suite, in part: CoordinatorUploadTests.anOutdatedKeptClopCopyCountsAsAChangedSource)`.

#### T17 `anEditorUploadAndUploadAsNewEachSendClopsBytesAndTheLinkKeepsItsKey` (M; CoordinatorEditorUploadTests)

- Entry point: `FakeEditor.upload(asNew:)` (EF:141-149) -> `actions.upload` -> `editorUpload` (+Editor:311-377) -> `startPlannedUpload` with `payload: .data(png)` (:376).
- Record: `try world.storeSaveFolder()`; `addSavedImage(to:in:)` of the suite (CoordinatorEditorUploadTests.swift:46-57) then `history.update` to the uploaded state: `uploadState: .uploaded(url: link, key: key)` with `key = "s/SHOT.png"`, `objectLocation: world.location` (the shape of `uploadWritesTheFileFirstThenReplacesTheLinksObject`, :107-110); `world.settings.optimiseWithClop = true`.
  Scripts: `world.clop.answers = [.smaller(Data("r1".utf8)), .smaller(Data("n1".utf8))]` (2 bytes each, fewer than the edited PNG).
- Sequence: `coordinator.openEditor(recordID: id)`; `editor = try await openedEditor(id)`; `editor.draw()`; `await editor.upload()`; `eventually` `history.record(id)?.isUploading == false`; `firstFile = Data(contentsOf: file)`; `try await settledEdit(coordinator, id)`; `world.date = world.date.addingTimeInterval(1)` (tests-editor 2: a second edit has a new thumbnail name);
  `coordinator.openEditor(recordID: id)`; `second = try await reopenedEditor(id, after: first)`; `editor.draw()`; `await second.upload(asNew: true)`; `eventually isUploaded` and `destination.deletedKeys == [key]`; `secondFile = Data(contentsOf: file)`; `settledEdit`.
- Assertions: first outcome `== EditorUploadOutcome(wroteLocally: true, enqueued: true)` (as :143); `world.clop.requests[0] == .png(firstFile)` (the PUT body equals the file, +Editor:307; CoordinatorEditorUploadTests.swift:176); `destination.uploads[0].key == "s/SHOT.png"`, `.data == Data("r1".utf8)`, `.cacheControl == "no-cache"`;
  `history.record(id)?.uploadState == .uploaded(url: link, key: key)` (the replace keeps the link, :178). Second: outcome likewise; `world.clop.requests[1] == .png(secondFile)`; `destination.uploads[1].key != "s/SHOT.png"`, `.data == Data("n1".utf8)`, `.cacheControl == nil` (a template job sends none, Destination.swift:92-93; plan `.newObject(supersede: old, notice: nil)`, EUP:82-84); `world.clop.requests.count == 2`; `world.clop.runningChecks == 2`.
  The Retry leg of the line (a failed capture's Retry is optimised) is T1 and T2's `retryUpload`.
- By hand / seam: turning the network off; real Clop making each object smaller (line 26, C).
- Effort M. Covers: phase-7-clop:28 (full, with T1).
- Mark: see CLOP.5, which is the mark source (spec section 6).

#### T18 `anMP4sSizeIsTheMovedFilesSize` (S; CoordinatorSaveTests)

- Entry point: `save(coordinator, recording, CaptureIntent(action: .save))` (CoordinatorSaveTests.swift:31-42), the sibling of `aGIFsSizeIsTheMovedFilesSize` (:359-373).
- Record: `try world.storeSaveFolder()`; `makeRecording(.video, bytes: 1_234)`. No Clop: this is the size-after-save half, which needs no seam (`FileSizes.byteCount(of:scope:)` after `placeRecording`, +Recording:798-801).
- Assertions: `isIn(record.fileURL, folder)`; `pathExtension == "mp4"`; `record.mediaKind == .video`; `record.byteCount == size` (the file's attribute) and `== 1_234`.
- By hand / seam: the row's text (`RecentCaptureFormatting`) is D; Finder's size.
- Effort S. Covers: small-tweaks:15 (the save half; full with T14).
- Mark: as T14.
### CLOP.5 Marks, as the merged checklists should read

Each mark follows `docs/testing/phase-6a-manual-checklist.md`'s form: `(suite[, in part]: Suite.test, ...; by hand: ...)`.

| Line | Mark |
|---|---|
| phase-7-clop:21 | `(suite, in part: CoordinatorClopTests.turningClopOffDuringAnOptimisationKeepsThatUploadOptimisedAndNotTheNext, AppSettingsTests.optimiseWithClopDefaultsOffAndPersists; by hand: closing Settings with no Save and `defaults read` of the real domain)` |
| phase-7-clop:28 | `(suite: CoordinatorEditorUploadTests.anEditorUploadAndUploadAsNewEachSendClopsBytesAndTheLinkKeepsItsKey, CoordinatorClopTests.turningClopOffDuringAnOptimisationKeepsThatUploadOptimisedAndNotTheNext)`; real Clop making each smaller is line 26 |
| phase-7-clop:29 | `(suite: CoordinatorClopTests.aCaptureWhoseUploadFailsAfterClopKeepsItsPendingFileAtTheCapturedSize, .turningClopOffDuringAnOptimisationKeepsThatUploadOptimisedAndNotTheNext)`; the container path and the network turned off are the line's set-up, not marked |
| phase-7-clop:31 | `(suite: CoordinatorClopTests.aClopThatIsNotRunningOrSkipsUploadsTheOriginalWithOneLine, ClopOptimiserTests.notSmallerReportedByClopReturnsNotSmaller)` |
| phase-7-clop:35 | `(suite: CoordinatorClopTests.aClopThatIsNotRunningOrSkipsUploadsTheOriginalWithOneLine)` |
| phase-7-clop:36 | `(suite: CoordinatorClopTests.aClopThatIsNotRunningOrSkipsUploadsTheOriginalWithOneLine, ClopOptimiserTests.anotherPathReturnsConverted)` |
| phase-7-clop:37 | `(suite: CoordinatorClopTests.aClopThatIsNotRunningOrSkipsUploadsTheOriginalWithOneLine, ClopOptimiserTests.throwingTransportReturnsFailed)`; full on the reading that the free-tier cap is set-up: the coordinator's branch for it is the `.failed` answer T2 drives |
| (note) | For :31, :35, :36 and :37, what makes real Clop answer each way (white fill, conversion, the free-tier cap) is the line's set-up, not marked. |
| phase-7-clop:32 | `(suite: CoordinatorClopTests.threeUploadsWithAnImageHeldInClopTakeCountersInStartOrder)` |
| phase-7-clop:41 | `(suite: CoordinatorClopTests.deletingAnImageWhileClopHoldsItCancelsAtOnceAndNothingUploads)`; the 65,536 px capture is the set-up that keeps Clop busy, which the held fake stands for |
| phase-7-clop:42, :43 | `(suite: CoordinatorClopTests.aDeleteDeclinedAtTheSecondAlertWhileClopHoldsLeavesTheCardCancelledAndARetryUploadsOnce)` / `(suite: CoordinatorClopTests.aRetryBeforeClopsFirstAnswerUploadsOnceFromTheSecondAttempt)`; the failed removal is made with folder permissions in the test |
| phase-7-clop:44 | `(suite: CoordinatorClopTests.changingUploadSettingsWhileClopHoldsAnUploadFinishesItAtItsOwnDestination)` |
| phase-7-clop:45, small-tweaks:14 | `(suite: CoordinatorClopTests.turningClopOffDuringAnOptimisationKeepsThatUploadOptimisedAndNotTheNext)` |
| recording-r1:271 | `(suite: CoordinatorDeleteTests.deleteDuringAnUploadCancelsItThenDeletesTheReservedKey, CoordinatorClopTests.deletingARecordingWhileClopHoldsItCancelsAtOnceAndLeavesNoMovieOrCounterGap)` |
| recording-r1:296 | `(suite, in part: CoordinatorClopTests.aFailedRecordingUploadAfterClopLeavesNoMovieAndARetryAsksClopAgainFromTheOriginal, .deletingARecordingWhileClopHoldsItCancelsAtOnceAndLeavesNoMovieOrCounterGap; by hand: the real container's tmp/Clop and the launch sweep of it (TMPDIRS))` |
| recording-r1:297 | `(suite: CoordinatorClopTests.aRecordingUploadsItsOriginalWithoutOptimizingWhenClopIsOffOrNotRunning)` |
| recording-r1:330 | `(suite: CoordinatorClopTests.deletingARecordingWhileClopHoldsItCancelsAtOnceAndLeavesNoMovieOrCounterGap)` |
| recording-r2:275 | `(suite, in part: CoordinatorClopTests.aGIFUploadsAsMadeWithOneClopLinePerLaunch, .anMP4RecordingGoesThroughClopShowingOptimizingAndUploadsClopsMovie; by hand: cmp against the bucket object and the real stderr)` |
| recording-r4:253 | `(suite, in part: CoordinatorUploadTests.anOutdatedKeptClopCopyCountsAsAChangedSource, CoordinatorTrimTests.anUploadTrimmedWithClopWhoseFileChangedAsksClopAgainAndSendsTheSecondTrim; by hand: the link playing the second trim)` (replaces the earlier mark) |
| recording-r4:255 | `(suite: CoordinatorClopTests.aRecordingOverThePartThresholdKeepsClopsMovieAndARetryResumesWithoutClop, .aClopMovieThatCannotBeKeptForResumeLogsItAndSendsTheThrowawayCopy, CoordinatorUploadTests.anUploadedResumeClearsItsStateSidecarAndKeptCopy)` (drops `in part`) |
| recording-r4:323 | `(suite: CoordinatorClopTests.aRecordingOverThePartThresholdKeepsClopsMovieAndARetryResumesWithoutClop, CoordinatorUploadTests.anUploadedResumeClearsItsStateSidecarAndKeptCopy)` |
| small-tweaks:15 | `(suite: CoordinatorClopTests.anMP4RecordingGoesThroughClopShowingOptimizingAndUploadsClopsMovie, CoordinatorSaveTests.anMP4sSizeIsTheMovedFilesSize, RecentCaptureFormattingTests.detailIsTheTimeAndTheSize)`; the last formats the row's size from `byteCount` (RecentCaptureFormattingTests.swift:229-235), so the row's text is in the suite; Finder's figure is only the line's yardstick |
### CLOP.6 Risks and notes for the plan

- Everything here relies on the judge's seam and `FakeClop` as written (judge 1.2-1.3); the tests T1-T5 were run against them in the design's scratch tree, T6-T18 were not. Their shapes are read from the code at 30d3c15 and from the existing suites' idioms; the points a first run may move are listed next.
- T6: relies on the three start tasks running in creation order on the main actor and `FakeClop` answering in call order. The assertions that depend on it are the per-record keys (counters are drawn synchronously, so they do not) and which record is the held one (the second). If the first run shows another order, script by record: the fake has no per-record scripting, so the fix is to `eventually { requests.count == 1 }` between the calls (retry `b` after `a`'s request, `c` after `b`'s hold).
- T9, T10, T15: the folder permission trick follows CoordinatorDeleteTests.swift:290-291. The folder is restored in a `defer` that runs before `removeAll()`. A save-folder `Saved` folder at 0o555 also blocks the thumbnail or any write there; the tests write nothing there after the permission change.
- T16: the 200 MiB sparse source is digested up to four times by `FakeDestination.partDigests`; if a run is slow, drop `twice` to 150 MiB (anything above `plusMiB` and a legal "smaller" source).
- T7 uses `finishSave`, not `save(_:intent:)`; the design and `lines-small.md` named `save`, which no test can call (`CaptureTarget` needs `SCDisplay`).
- T3 and T8-T10: a held request makes `world.removeAll()` unsafe if the `defer` release is missing; the rule-3 `defer` order (release declared after `removeAll`) is what keeps a failing test from hanging.
- The line recording-r1:330's parenthetical (a refused 625 GB upload draws no counter) is "cannot be reached by hand"; a test could reach it with a sparse file over 671_088_640_000 bytes (MP:35-37). It would also hit `refuseOversizedUpload`'s `RecordingLog.note` (+Upload:378), the `LOG` seam's. Not added; noted for the LOG catalogue.
- T1 asserts `!world.logLines.contains { $0.hasPrefix("Clop:") }` after an optimised upload: true because `optimisedForUpload` logs only on a skip (+Upload:456).

## 4. SAVEAS: the card's Save As… panel

The tests the SAVEAS seam gives the 14 lines of `lines-small.md` (section "SAVEAS"). Form of an entry: as
`docs/superpowers/notes/2026-10-30-editor-seam/tests-editor.md`. No Swift bodies; every value a body needs is given.
Code references are at 30d3c15 (`small-seams`, tree clean, the seam not yet applied). `RA` is
`TidyShot/App/AppCoordinator+RecordActions.swift`; `+DragOut`, `+Editor`, `+Upload`, `+Overlay` are
`TidyShot/App/AppCoordinator+*.swift`; `EN` is `TidyShot/Editor/Persistence/EditorNaming.swift`; `Fakes` is
`TidyShotTests/Support/CoordinatorFakes.swift`; `FD` is `TidyShotTests/Support/FakeDestination.swift`; `World` is
`TidyShotTests/Support/CoordinatorWorld.swift`. Line keys are catalogue keys with the current checklist line in
brackets.

The seam and the fake are the judge's (`judge.md` section 2): `AppEnvironment.chooseSaveAsURL: @MainActor
(EditorNaming.SaveAsSuggestion) async -> URL?`, the suite's `FakeSaveAsChooser`, `world.saveAsChooser`, and
`FakeDestination.download(key:to:)` made to record and write. The designer built and ran tests 1 to 8 below in
`saveas-tree`; their expected values are re-read here against the code, not taken from that run. Tests 9 and 10 and
extra E1 are new in this catalogue and were not run.

### SAVEAS.1 Neighbours and corrections

Where the remainder is another seam's: coordinator-split:44 (`PINS`, `SCREENS`), phase-6a:172 and :176 (`SCREENS`),
phase-6a:199 (`PINS`), recording-r1:313 (`SCREENS`), recording-r2:264 (`WORKSPACE`). By hand with no seam: phase-6a:170,
:171, :175, :198 (and the by-hand parts that ride with the first group).

Corrections to the inputs, none changing a verdict:
- `facts-saveas.md` section 1 says `saveAs(recordID:)` returns at RA:112 for a missing record. It does not: `history.
  record(id:)?.uploadBlockedReason == nil` is `nil == nil`, true, so the guard passes; the work is queued and ends at
  `askSaveAsTarget`'s first line (RA:196). The result (nothing happens) is the same, and no test here depends on it.
- The designer's judge text says three of the lines extend CT-2 marks. They are coordinator-split:44, phase-6a:198 and
  phase-6a:199, as here; recording-r4:277, recording-r1:313 and recording-r2:264 have no current mark.

### SAVEAS.2 What holds for every test here

Seam and support (judge section 2, restated as values):
- `FakeSaveAsChooser` (in `Fakes`, after `FakeConfirm`, :196-221): `asked: [EditorNaming.SaveAsSuggestion]`, `answers:
  [URL?]` (a URL saves there, nil is Cancel; **Cancel when the list is empty**), `holds` (the next panel waits),
  `isWaiting`, `answer(_:)` (clears `holds`, ends the wait; nil is Cancel). Built on `SingleWaiter<URL?>(cancelled: nil,
  secondEntry: "FakeSaveAsChooser was asked again while a panel was held")` (`SingleWaiter` is Fakes:373-416).
  `choose(_:)` appends to `asked` first, then answers or holds.
- `World` binds `let saveAsChooser = FakeSaveAsChooser()` to a local before the struct and passes `chooseSaveAsURL: {
  suggestion in await saveAsChooser.choose(suggestion) }` right after the `makeEditor` closure (World:128-131). `CoordinatorWorldTests.
  aCoordinatorOverTheWorldKeepsToTheWorld` gains `#expect(world.saveAsChooser.asked.isEmpty)`.
- `FD:171` `download(key:to:)` stops being `async throws {}`: it records `(key, file)` into a new `State.fileDownloads`,
  writes `downloadedData` (default `Data("object".
  utf8)`, FD:104) to the file. Tests 4 and 7 need it. Its only other caller is Trim (`+Trim.swift:68`), which no test
  reaches.
- What the seam replaces is RA:197-201 only: the `NSSavePanel` build, `NSApplication.shared.activate`, `panel.begin()`.
  The record check before (RA:196), the suggestion (RA:321-330, called at the closure's argument) and the re-read after
  with its log line (RA:202-205) stay in the coordinator and are under test.

Suite and helpers (new `TidyShotTests/CoordinatorSaveAsTests.swift`, because `CoordinatorRecordActionsTests`' header
says the panel "is never built here", CoordinatorRecordActionsTests.swift:5-7):
- `@Suite(.timeLimit(.minutes(1)))`, `struct CoordinatorSaveAsTests`, `let world`, `let key = "s/SHOT.png"`, `let
  videoKey = "s/2026/rec.mp4"`; `init() throws { world = try CoordinatorWorld() }`; every test opens with `defer {
  world.removeAll() }`. `destination` is `world.factory.standard`; `chooser` is `world.saveAsChooser`.
- `desktop(_ name:)` makes `<root>/Desktop/` and returns `<root>/Desktop/<name>` (as CoordinatorEditorTests.swift:72-76);
  `exists(_:)`; `publicURL(_ key:)` is `https://snap.tky.io/<key>` (`FakeDestination.publicURL(for:)`, FD:274-276);
  `notices(after:)` is `Array(world.notifier.calls.dropFirst(count))`; `postedDownloading` is any `.notice` whose body
  has prefix `Downloading `.
- Records (each adds to `coordinator.history`; `HistoryStore` prunes on the real `Date()`, so timestamps stay at
  their default of now): `addSavedImage(to:in:name:width:)` (a `width`-by-2 PNG from `CoordinatorWorld.pngData` written
  into the folder, `fileURL` the file, `byteCount` its size; returns the record and the bytes); `addPendingImage(to:
  width:)` (`pendingFiles.write(png, id:, ext: "png")`, `fileIsTemporary: true`, `uploadState: .failed(message: "Upload
  was interrupted.")`); `addUploadOnly(to:bytes:)` (`fileURL: nil`, 6-by-2, `.uploaded(url: publicURL(key), key: key)`,
  `objectLocation: world.location`, and `destination.state.withLock { $0.downloadedData = bytes }`);
  `uploadWithItsCardShowing(_:)` (pending record, `world.cards.showing.insert(id)`, `retryUpload`, `eventually {
  uploadedKey != nil }`, then asserts `fileURL == nil` and `dragFiles.stagedFile(id:) != nil`; returns the record, its
  key and the pending bytes); `addUploadedRecording(to:kind:)` (`fileURL: nil`, 1600 by 1000, `.uploaded(url:
  publicURL(videoKey), key: videoKey)`, `objectLocation: world.location`, `mediaKind: kind`, `durationSeconds: 10`,
  `byteCount: 1_000`; the same record `CoordinatorDragOutTests.showingUploadedRecording` builds, CoordinatorDragOutTests.
  swift:19-28).
- Gating (judge section 2.5 rules 2 to 4). `saveAs(recordID:)` returns at once and gives no handle: it goes through
  `afterMenuTracking` (RA:111-121, :280-284) and an unstored `Task`, so a test gates with `eventually` (polls 10 ms, 200
  times, `UploadQueueTests.swift:39-48`) on `chooser.asked.count`, the notifier's calls, or the file. `saveVideoCopy(
  recordID:)` is internal and async (RA:130): the test runs it in its own `Task`, registers `defer { task.cancel() }`
  and gates on `TaskWatch(task).hasReturned` (Fakes:418-431). A held panel: `chooser.holds = true`, `defer {
  chooser.answer(nil) }` right after the world's `defer`, `eventually { chooser.isWaiting }`, do what the test does
  while the panel is up, then `chooser.answer(url)`. Never two panels held at once. The image path's task cannot be
  cancelled by a test; the `defer` answer is what ends it if the test throws.
- A Cancel step proves "nothing written or posted" only through what comes after it: the next step compares the notifier
  whole (`calls == [.saved(...)]`), which a stray post from the cancelled save would break.
- A suggestion with no save-folder file is compared only under a template without `{time}`, `{date}` or `{datetime}`.
  The coordinator builds `FileNamer(template: settings.fileNameTemplate)` with no clock (RA:321-329), so its `now` is
  `Date()` (FileNamer.swift:21), and the default template `Screenshot {date} at {time}` (FileNamer.swift:6) has seconds
  (`HH.mm.ss`, TemplateExpander.swift:142): a test that recomputes the suggestion after the coordinator's read fails
  when a second ticks between them. Set `world.settings.fileNameTemplate = "shot-{counter}"` and compare a literal
  (tests 2 and 3), or use the record's timestamp (tests 4 and 8). The default template failed test 3 once in a full run.
- Notifier values: `Saved` is `notifier.notifySaved(fileURL: url, title: "Saved")` (RA:312), recorded by `FakeNotifier`
  as `.saved(title: "Saved", file: url.lastPathComponent)` (Fakes:33). `showNotification` defaults on (AppSettings.swift:
  269, :319). `Not saved` is `notifyError(error.localizedDescription, title: "Not saved")` (RA:185 for the read,
  RA:308 for the write), recorded as `.error(title: "Not saved", message: <reason>, subtitle: nil)` (Fakes:39). The
  download notice is `notify(title: "Saving a copy…", body: "Downloading \(key)")` (RA:267-269, `showNotification` on),
  recorded as `.notice(title: "Saving a copy…", body: "Downloading <key>", subtitle: nil)` (Fakes:43).

### SAVEAS.3 CoordinatorSaveAsTests.swift (new)

Header: "A card's Save As… on a built coordinator (`saveAs(recordID:)` and `saveVideoCopy(recordID:)`): what the panel is
asked, what is written where, and what is posted. The panel is `environment.chooseSaveAsURL`, here
`world.saveAsChooser`; no panel is built and the app is never activated."


#### 1 `saveAsOfASavedImageCopiesItsBytesAndChangesNothingElse` (M)
- Entry: `coordinator.saveAs(recordID: id)` four times (RA:111) -> `saveCopy` (RA:179) -> `askSaveAsTarget` (RA:195) ->
  `imageData(of:)` (RA:215) -> `writeSaveAsCopy` (RA:291). `saveAs(recordID:)` is what the pin's menu item calls too
  (`pinActions()`, `+Pins.swift:70`, `saveAs: { ... self?.saveAs(recordID: id) }`), and what a card's button and
  context menu reach through `model.onSaveAs` (`QuickAccessController.swift:224`, `+Overlay.swift:29`).
- Source: a save-folder PNG. `let folder = try world.storeSaveFolder()` before `makeCoordinator()` (World:159-164);
  `addSavedImage(to:in: folder)` gives `Shot.png`, 4 by 2, `original` its bytes. `world.cards.showing.insert(id)`;
  `coordinator.lastCaptureURL = file`. Before anything: `records = coordinator.history.records`, `historyFile = Data(
  contentsOf: world.historyFileURL)` (`HistoryStore.add` saves synchronously, HistoryStore.swift:60-70), `cardCalls =
  world.cards.calls`. Targets: `copy = desktop("Copy.png")`, `quiet = desktop("Quiet.png")`.
- Script: `chooser.answers = [nil, copy, file, quiet]`.
- Sequence and asserts:
  1. `saveAs`; `eventually { chooser.asked.count == 1 }`. The suggestion is `fileName == "Shot.png"` (EN:26-27, the
     record's own non-temporary name), `directory == world.saveLocation.currentURL` (EN:33, RA:325; the folder just
     stored), `mediaKind == .image` (EN:24). `world.notifier.calls.isEmpty` and `world.logLines.isEmpty` (Cancel: RA:201
     returns nil, RA:180 returns).
  2. `saveAs`; `eventually { world.notifier.calls == [.saved(title: "Saved", file: "Copy.png")] }`; `Data(contentsOf:
     copy) == original` (the file's bytes unchanged, no re-encode: `imageData` RA:229 then `png.write(to:options:
     .atomic)` RA:294).
  3. `saveAs` with the original's own URL as target; `eventually { world.notifier.calls.count == 2 }`; `calls.last ==
     .saved(title: "Saved", file: "Shot.png")`; `Data(contentsOf: file) == original`. (The card's Save As does not run
     the editor's own-file rule; it rewrites the same bytes atomically, RA:294.)
  4. Last, so no earlier save is still to read the setting: `world.settings.showNotification = false`; `saveAs`;
     `eventually { exists(quiet) }`; `Data(contentsOf: quiet) == original` (the file is written, RA:294, and `performSaveAs`
     posts nothing, RA:311).
  5. At the end: `chooser.asked == Array(repeating: suggestion, count: 4)`; `world.notifier.calls.count == 2`;
     `coordinator.history.records == records`; `Data(contentsOf: world.historyFileURL) == historyFile`; `world.cards.
     calls == cardCalls` and `world.cards.showing == [id]`; `coordinator.lastCaptureURL == file`; `world.clipboard.
     copies.isEmpty`; `world.logLines.isEmpty`. Nothing in `saveAs`, `saveCopy`, `askSaveAsTarget`, `imageData` or
     `performSaveAs` writes history, the clipboard, the card or `lastCaptureURL` (read: RA:111-331).
- By hand / other seam: the click on `Saved` revealing the copy (`Notifier`'s own); the panel's Replace prompt and its
  window and activation (AppKit); the pin over the spot, its second click, `Close Pinned Screenshots` and reaching the item
  through the pin's menu (`PINS`, `SCREENS`).
- Effort: M.
- Covers: phase-6a:170 in part; phase-6a:174 full; coordinator-split:44 in part (the suggestion is the capture's own
  name, Cancel changes nothing); recording-r1:340 and recording-r2:670 (the Save As… verb; section 4).
- Merged mark for coordinator-split:44 (CT-2's text gains a test and loses `SAVEAS` from the by-hand list): "(suite, in
  part: CoordinatorEditorTests.annotateFromACardOrRecentCapturesLeavesNothingToRestore, CoordinatorRecordActionsTests.
  copyImageReadsTheFileOrDownloadsTheObject, CoordinatorSaveAsTests.saveAsOfASavedImageCopiesItsBytesAndChangesNothingElse
  (the Save As… item's suggestion and Cancel, through `saveAs(recordID:)`, which the pin's menu calls); by hand: the pin,
  its second click and `Close Pinned Screenshots` (`PINS`, `SCREENS`), reaching Save As… through the pin's menu (`PINS`),
  and the panel itself; the pin menu's Annotate is the card's `openEditorAfterMenuTracking`)".
- Merged mark for phase-6a:170: "(suite, in part: CoordinatorSaveAsTests.saveAsOfASavedImageCopiesItsBytesAndChangesNothingElse;
  by hand: `shasum`, the click on `Saved` revealing the copy, the panel's Replace prompt)". For phase-6a:174: "(suite:
  CoordinatorSaveAsTests.saveAsOfASavedImageCopiesItsBytesAndChangesNothingElse)".

#### 2 `anUploadOnlyCapturesSaveAsSuggestsTheTemplateNameAndCopiesItsPendingFile` (M)
- Entry: `saveAs(recordID:)` twice, on a failed upload-only capture and during its retry.
- Source: a pending PNG, `addPendingImage(to:)` (4 by 2, `.failed`, `fileIsTemporary` true), no save folder (a fresh
  world's `saveLocation.currentURL` is nil, World:80). Before `makeCoordinator()`: `world.settings.fileNameTemplate =
  "shot-{counter}"`, `world.settings.nextCounter()` twice (counter 2, as `CoordinatorRecordActionsTests.
  saveAsSuggestionUsesTheCurrentCounterWithoutDrawingOne`, :160-173). `png = Data(contentsOf: record.fileURL)`.
- Script: `chooser.answers = [desktop("Failed.png"), desktop("Uploading.png")]`. For the second: `destination.state.withLock
  { $0.holdingUploadsRemaining = 1 }` and `defer { destination.releaseUploads() }` (FD:26, :231-264) registered after the
  world's `defer`.
- Sequence and asserts:
  1. `saveAs`; `eventually { world.notifier.calls == [.saved(title: "Saved", file: "Failed.png")] }`. `chooser.asked ==
     [EditorNaming.SaveAsSuggestion(fileName: "shot-2.png", directory: nil, mediaKind: .image)]` (EN:29-33: a temporary
     file is not the user's name, the template gives `shot-2.png` because it holds `{counter}`; directory nil leaves the
     panel where it last was). `world.settings.currentCounter == 2` (no counter drawn, RA:329). `Data(contentsOf:
     Failed.png) == png` (`imageData` reads a temporary file directly, RA:226-227).
  2. `coordinator.retryUpload(recordID: id)`; `eventually { destination.state.withLock { $0.heldUploads.count } == 1 }`;
     `history.record(id:)?.isUploading == true`.
  3. `saveAs`; `eventually { world.notifier.calls.contains(.saved(title: "Saved", file: "Uploading.png")) }`. The second
     suggestion is `shot-2.png` again (the default key template `{random:6}` lacks `{counter}`, so the retry drew none,
     +Upload.swift:167); the test reads `world.settings.currentCounter` rather than hard-coding it. `Data(contentsOf:
     Uploading.png) == png`; the record is still `isUploading`; `destination.state.withLock { $0.dataDownloadKeys }.
     isEmpty`.
  4. `destination.releaseUploads()`; `eventually { coordinator.history.record(id: id)?.uploadedKey != nil }` (the upload
     goes on to its end; no card shows, so the pending file is removed then, after the copy was made).
- By hand: "where the panel last was" is the panel's. With a save folder the suggestion's name rule is D
  (`EditorNamingTests.uploadOnlyCaptureWithoutAKeySuggestsTheTemplateName`, `.counterUsesTheCurrentValue`,
  `.noFolderLeavesTheDirectoryToThePanel`), and the folder wiring is seen in test 1 (`directory == currentURL`).
- Effort: M.
- Covers: phase-6a:171 in part. Merged mark: "(suite, in part: CoordinatorSaveAsTests.anUploadOnlyCapturesSaveAsSuggestsTheTemplateNameAndCopiesItsPendingFile,
  EditorNamingTests.uploadOnlyCaptureWithoutAKeySuggestsTheTemplateName, .counterUsesTheCurrentValue; by hand: where
  the panel last was)".

#### 3 `anUploadOnlyCardsSaveAsWritesTheDragCopyOrDownloadsAfterThePanel` (L, holds once)
- Entry: `saveAs(recordID:)` three times.
- Source, first: `uploadWithItsCardShowing(coordinator)`: a pending PNG uploaded with its card showing, so `keepForDragOut`
  (+DragOut.swift:232-247) moved the file to `Drag/<id>/<key name>` and the record has `fileURL == nil`
  (`CoordinatorUploadTests.anUploadedUploadOnlyImageMovesToItsDragFolderOnlyWithACard`). Second: `addUploadOnly(to:
  bytes: object)` with `object = CoordinatorWorld.pngData(width: 6, height: 2)`, no drag copy, `world.cards.showing.
  insert(id)` (a showing card stands for a restored one: Save As does not look at the card, RA:195-207).
- Script: `defer { chooser.answer(nil) }` after the world's `defer`. First `chooser.answers = [desktop("Kept.png")]`.
  Second `chooser.holds = true`. Third `destination.state.withLock { $0.dataDownloadFailures = [URLError(
  .notConnectedToInternet)] }` and `chooser.answers = [desktop("Offline.png")]`.
- Sequence and asserts:
  1. Drag copy: `saveAs(kept.id)`; `eventually { calls.contains(.saved(title: "Saved", file: "Kept.png")) }`;
     `Data(contentsOf: Kept.png) == png` (`imageData` finds no readable file, takes `drag.stagedFile`, RA:234);
     `dataDownloadKeys.isEmpty`; `!postedDownloading` (no GET, RA:237 not reached).
  2. No drag copy, held: `world.settings.fileNameTemplate = "shot-{counter}"` before `addUploadOnly` (SAVEAS.2's
     template rule); `beforePanel = world.notifier.calls.count`; `saveAs(restored.id)`; `eventually { chooser.
     isWaiting }`; `chooser.asked.last == EditorNaming.SaveAsSuggestion(fileName: "shot-\(world.settings.
     currentCounter).png", directory: nil, mediaKind: .image)` (no counter is drawn, as test 2); `notices(after:
     beforePanel).isEmpty` and `dataDownloadKeys.isEmpty` while the panel is up (the panel comes first, RA:197 before
     RA:183); `chooser.answer(desktop("Restored.png"))`; `eventually { notices(after: beforePanel).count == 2 }`;
     `notices(after: beforePanel) == [.notice(title: "Saving a copy…", body: "Downloading s/SHOT.png"), .saved(title:
     "Saved", file: "Restored.png")]` (RA:267-269, RA:312); `Data(contentsOf: Restored.png) == object`; `dataDownloadKeys
     == [key]`.
  3. Offline: `beforeOffline`; `saveAs(restored.id)`; `eventually { notices(after: beforeOffline).count == 2 }`;
     `notices(after: beforeOffline) == [.notice(title: "Saving a copy…", body: "Downloading s/SHOT.png"), .error(title:
     "Not saved", message: offline.localizedDescription)]` (the notice is posted by `downloadSource` before the GET
     throws, RA:267-269 then RA:184-185); `!exists(Offline.png)`; `dataDownloadKeys == [key, key]`; `chooser.asked.count
     == 3`; `world.logLines.isEmpty` (RA:185 logs nothing).
- By hand / other seam: the restore itself (`SCREENS`: `restoreClosedOverlay` reads `overlayScreen`, +Overlay.swift:55-62,
  :94); `curl` against the bucket and the slow profile (the fake's download stands for them).
- Effort: L (the setup, a hold, a failure script).
- Covers: phase-6a:172 in part; phase-6a:198 in part (the Save As… part of "need no download": step 1).
- Merged mark for phase-6a:172: "(suite, in part: CoordinatorSaveAsTests.anUploadOnlyCardsSaveAsWritesTheDragCopyOrDownloadsAfterThePanel;
  by hand: restoring the card (`SCREENS`), `curl` against the bucket, the slow profile)".
- Merged mark for phase-6a:198 (CT-2's text gains a test and loses `SAVEAS`): "(suite, in part: CoordinatorEditorTests.
  anUploadedUploadOnlyCardsCopyImageAndAnnotateReadTheDragCopy, CoordinatorUploadTests.anUploadedUploadOnlyImageMovesToItsDragFolderOnlyWithACard,
  CoordinatorSaveAsTests.anUploadOnlyCardsSaveAsWritesTheDragCopyOrDownloadsAfterThePanel; by hand: Slack reading the file)".
  CT-2's test keeps its direct `imageData(of:downloadTitle:)` read at CoordinatorEditorTests.swift:635 (it does cover
  the read); this test adds the panel and the write. The 60 s clean-up and Copy Image/Annotate stay CT-2's.

#### 4 `aRecordingsSaveAsDuringItsDragOutDownloadWaitsAndCopiesTheLandedFile` (M)
- Entry: `coordinator.saveVideoCopy(recordID: id)` in the test's own `Task` (RA:130; it is internal), after
  `downloadDragFile(recordID:)` (+DragOut.swift:98).
- Source: `addUploadedRecording(to:)` (`.video`, no local file, `byteCount` 1 000), `world.cards.showing.insert(id)`.
  `downloadDragFile` starts when the card shows and `DragDownloadRule.starts` holds (`isTimeBased`, no local file, key and
  location, not blocked, no drag file, not running: `DragDownloadRule.swift:13-17`) and has room (`hasRoom(byteCount: 1000,
  freeBytes: 100_000_000_000)`, `DragDownloadRule.swift:23-26`, World default `CoordinatorFakes.swift:258`).
- Script: `destination.state.withLock { $0.holdsDownloads = true; $0.downloadOutcome = .lands(bytes: 1_000) }`, `defer {
  destination.releaseDownloads() }` (FD:204-206); `chooser.answers = [desktop("Copy.mp4")]`.
- Sequence and asserts:
  1. `coordinator.downloadDragFile(recordID: id)`; `eventually { destination.state.withLock { $0.downloads.count } == 1 }`.
  2. `let save = Task { await coordinator.saveVideoCopy(recordID: id) }`; `defer { save.cancel() }`; `let watch =
     TaskWatch(save)`; `eventually { chooser.asked.count == 1 }`. The suggestion has `mediaKind == .video` and a
     `fileName` with suffix `.mp4` (EN:31, the recording template). `!watch.hasReturned` and `!exists(target)`: the
     answer is in, and `saveVideoCopy` waits on `downloadingDragIDs[recordID]` (RA:132-134).
  3. `destination.releaseDownloads()`; `eventually { watch.hasReturned }`. The download landed and was adopted into
     `Drag/<id>/` (+DragOut.swift:182); `coordinator.dragFiles.stagedFile(id:)` is non-nil; `copyVideo` copied it
     (RA:169, :172): `Data(contentsOf: target) == Data(contentsOf: landed) == Data(count: 1_000)`.
  4. One GET in all: `destination.state.withLock { $0.downloads.count } == 1`; `fileDownloads.isEmpty` (no
     `download(key:to:)`, RA:150); `dataDownloadKeys.isEmpty`. `world.notifier.calls == [.saved(title: "Saved", file:
     "Copy.mp4")]` (the drag-out download is quiet, +DragOut.swift:111 `title: nil`; RA:147-148 never ran).
- By hand: "in the log" is the app's GET count; the fake's `downloads` stands for it.
- Effort: M. Needs the `FakeDestination` change for `fileDownloads`.
- Covers: recording-r4:277 full. Merged mark: "(suite: CoordinatorSaveAsTests.aRecordingsSaveAsDuringItsDragOutDownloadWaitsAndCopiesTheLandedFile)".

#### 5 `aSaveAsPanelHeldThroughTheCardsAutoCloseStillSaves` (M, holds once)
- Entry: `saveAs(recordID:)` with the panel held; `world.cards.close(recordID:reason: .autoClose)` (Fakes:111-115)
  runs `overlayDidClose` (wired at AppCoordinator.swift:284; +Overlay.swift:67-76).
- Source: `uploadWithItsCardShowing(coordinator)` (as test 3), then `destination.state.withLock { $0.downloadedData =
  Data("object".utf8) }`. Target `desktop("Copy.png")`. `chooser.holds = true`; `defer { chooser.answer(nil) }`.
- Sequence and asserts:
  1. `saveAs`; `eventually { chooser.isWaiting }`.
  2. `world.cards.close(recordID: id, reason: .autoClose)`; `world.cards.closes == [.autoClose]`; `coordinator.
     closedOverlays.ids.contains(id)` (restorable, `ClosedOverlays.swift:11`). `try await world.clock.run(for:
     .seconds(60))` (`dragCleanupDelay` is 60 s, +DragOut.swift:6; the clean-up runs `removeDragFolder` because no
     card shows and no Copy File reference exists, +DragOut.swift:268-273); `eventually { !exists(coordinator.dragFiles.
     folder(for: id)) }`; `chooser.isWaiting` still true.
  3. `beforeAnswer = world.notifier.calls.count`; `chooser.answer(target)`; `eventually { notices(after: beforeAnswer).
     count == 2 }`; `notices(after: beforeAnswer) == [.notice(title: "Saving a copy…", body: "Downloading <key>"),
     .saved(title: "Saved", file: "Copy.png")]` where `<key>` is the record's `uploadedKey` (the drag copy is gone, so
     the capture is fetched, RA:234 finds nothing and RA:237 downloads); `Data(contentsOf: target) == Data("object".utf8)`;
     `dataDownloadKeys == [key]`; `chooser.asked.count == 1` (one panel in all).
- By hand / other seam: the card's real timer (`QuickAccessController.scheduleClose`, QuickAccessController.swift:354-376,
  which `FakeCards.close` stands for) and the panel window staying usable as the card goes. The save does not depend on
  the card (RA:202 checks only that the record exists).
- Effort: M.
- Covers: phase-6a:175 in part. Merged mark: "(suite, in part: CoordinatorSaveAsTests.aSaveAsPanelHeldThroughTheCardsAutoCloseStillSaves;
  by hand: the card's real auto-close timer, the panel window staying usable)".

#### 6 `saveAsFromAnyCardWritesThatCardsCapture` (S)
- Entry: `saveAs(recordID:)` on the middle of three showing records, then on the oldest.
- Source: save folder stored; `addSavedImage` three times with names `Oldest.png` (width 4), `Middle.png` (5), `Newest.png`
  (6), so the bytes differ; `world.cards.showing = [oldest, middle, newest]`.
- Script: `chooser.answers = [desktop("FromMiddle.png"), desktop("FromOldest.png")]`.
- Sequence and asserts: `saveAs(middle)`, `eventually { world.notifier.calls.count == 1 }`, `saveAs(oldest)`, `eventually
  { calls.count == 2 }`. `chooser.asked.map(\.fileName) == ["Middle.png", "Oldest.png"]` (EN:26-27); `Data(contentsOf:
  FromMiddle.png) == middle.original`, `Data(contentsOf: FromOldest.png) == oldest.original`; `world.notifier.calls ==
  [.saved(title: "Saved", file: "FromMiddle.png"), .saved(title: "Saved", file: "FromOldest.png")]`.
- By hand / other seam: the actual restore (`SCREENS`); button and context menu both call `model.onSaveAs()`
  (`QuickAccessView.swift:101`, `:138`), view wiring, by eye. `saveAs` is keyed by record and never reads the stack
  (RA:111-121), which is why a middle card is the same call.
- Effort: S.
- Covers: phase-6a:176 in part. Merged mark: "(suite, in part: CoordinatorSaveAsTests.saveAsFromAnyCardWritesThatCardsCapture;
  by hand: restoring the card (`SCREENS`), the button and the menu item both calling `onSaveAs`)".

#### 7 `anUploadOnlyVideosSaveAsDownloadsToTheChosenFile` (S)
- Entry: `saveVideoCopy(recordID:)` in the test's own `Task`.
- Source: `addUploadedRecording(to:)` (no local file, no drag folder), `world.cards.showing.insert(id)` (not needed by the
  code; harmless). `movie = Data(repeating: 7, count: 32)`; `destination.state.withLock { $0.downloadedData = movie }`.
- Script: `chooser.answers = [desktop("Chosen.mp4")]`.
- Sequence and asserts: `Task { await coordinator.saveVideoCopy(recordID:) }`, `defer { save.cancel() }`, `TaskWatch`,
  `eventually { watch.hasReturned }`. `copyVideo` finds neither a local file nor a drag copy and returns false (RA:166-171);
  then `downloadSource(of: uploadedFallback(for:), title: "Saving a copy…")` (RA:147-148) and `download(key:to:)`
  (RA:150-152). `Data(contentsOf: Chosen.mp4) == movie`; `destination.state.withLock { $0.fileDownloads.map(\.key) } ==
  ["s/2026/rec.mp4"]` and `.map(\.file) == [target]`; `$0.downloads.isEmpty` (no drag-out download); `world.notifier.calls
  == [.notice(title: "Saving a copy…", body: "Downloading s/2026/rec.mp4"), .saved(title: "Saved", file: "Chosen.mp4")]`.
- By hand / other seam: restoring the card starting no download (`SCREENS`); that a drag downloads first is D
  (`CoordinatorDragOutTests`).
- Effort: S. Needs the `FakeDestination` change.
- Covers: recording-r1:313 in part (its last sentence). Merged mark (the line has none now): "(suite, in part:
  CoordinatorSaveAsTests.anUploadOnlyVideosSaveAsDownloadsToTheChosenFile, the Save As… sentence; CoordinatorDragOutTests
  for the drag; by hand: restoring the card starting no download (`SCREENS`), Activity Monitor)". Name the drag tests from
  the catalogue's note when marking.

#### 8 `aGIFsSaveAsWritesTheGIFOverAnExistingFileToo` (S)
- Entry: `saveVideoCopy(recordID:)` twice (`saveAs` routes a GIF here, RA:115-116, `isTimeBased` is `mediaKind != .image`,
  CaptureRecord.swift:243).
- Source: save folder stored; `gif = Data("GIF89a-bytes".utf8)` written to `<Saved>/Recording.gif`; `CaptureRecord(fileURL:
  file, pixelWidth: 640, pixelHeight: 400, appName: nil, mediaKind: .gif, durationSeconds: 4, byteCount: gif.count)`.
  Targets: `fresh = desktop("Fresh.gif")`; `existing = desktop("Existing.gif")` holding `Data("old".utf8)`.
- Script: `chooser.answers = [fresh, existing]`.
- Sequence and asserts: two times, a `Task { await coordinator.saveVideoCopy(recordID:) }` with `defer { save.cancel() }`
  and `eventually { watch.hasReturned }`. `chooser.asked.map(\.mediaKind) == [.gif, .gif]`; `chooser.asked.map(\.fileName) ==
  ["Recording.gif", "Recording.gif"]` (EN:26-27); `Data(contentsOf: fresh) == gif`; `Data(contentsOf: existing) == gif`
  (replaced through `FileReplacement.put`, RA:172, FileReplacement.swift:13-22); the source file unchanged;
  `world.notifier.calls == [.saved(title: "Saved", file: "Fresh.gif"), .saved(title: "Saved", file: "Existing.gif")]`;
  `fileDownloads.isEmpty`.
- By hand / other seam: the thumbnail click (`WORKSPACE`, `openCapture`, RA:51-73); `/Volumes/RecOff`, the hover preview,
  dragging into Finder and Slack. `com.compuserve.gif` as the panel's one type is D
  (`EditorNamingTests.aGIFPanelAllowsGIFOnly`); the menu contents are D (`QuickAccessModelTests.
  aGIFHasNoImageActionsCopiesItsFileAndHasTheGIFBadge`, `RecentCaptureFormattingTests.aGIFHidesTheImageActionsCopiesItsFileAndHasTheGIFBadge`);
  the press staging the `.gif` with no download is A today (`prepareDragFile`, +DragOut.swift:14) and is not repeated.
- Effort: S.
- Covers: recording-r2:264 in part. Merged mark: "(suite, in part: CoordinatorSaveAsTests.aGIFsSaveAsWritesTheGIFOverAnExistingFileToo,
  EditorNamingTests.aGIFPanelAllowsGIFOnly, QuickAccessModelTests.aGIFHasNoImageActionsCopiesItsFileAndHasTheGIFBadge; by
  hand: the thumbnail click (`WORKSPACE`), `/Volumes/RecOff`, the hover preview, dragging into Finder and Slack)".

#### E1 `aSaveAsWhoseCaptureIsDeletedWhileThePanelIsUpWritesNothingAndLogsIt` (S, not a line)
- Why: the one branch of `askSaveAsTarget` nothing else reaches (RA:202-205), and the natural check the seam left the
  coordinator's own logic in place. Covers no checklist line; no mark.
- Entry: `saveAs(recordID:)` with the panel held. Source: `addSavedImage` in a stored save folder.
- Sequence and asserts: `chooser.holds = true`, `defer { chooser.answer(nil) }`; `saveAs`; `eventually { chooser.isWaiting }`;
  `coordinator.history.remove(id: id)` (HistoryStore.swift:122); `chooser.answer(desktop("Gone.png"))`; `eventually {
  world.logLines == ["Save As: \(id) was deleted while the panel was open"] }` (RA:203, `id` interpolated as a `UUID`);
  `!exists(Gone.png)`; `world.notifier.calls.isEmpty`.
- Effort: S. Not run.

### SAVEAS.4 recording-r1:340 and recording-r2:670: the verbs other than Save As…

Both lines are "A screenshot's save, upload, Retry, Delete, Save As… and Copy Image are as before; a PNG still gets `.png`
and `image/png`". Save As… is test 1 (a screenshot in the save folder; bytes and `Saved`). The other verbs are existing
tests, found by name at 30d3c15: save and upload with the overlay off `CoordinatorSaveTests.
aCaptureWithTheOverlayOffShowsNoCardAndStillUploads` (:79); Retry `CoordinatorUploadTests.aFailedUploadOnlyImageKeepsItsPendingFileAndSizeUntilARetrySendsIt` (:534); Delete `CoordinatorDeleteTests.deleteDuringAnUploadCancelsItThenDeletesTheReservedKey` (:368); Copy Image
`CoordinatorRecordActionsTests.copyImageReadsTheFileOrDownloadsTheObject` (:75); `.png` and `image/png`
`CaptureRecordTests.mediaKindTypes` (:618: `fileExtension == "png"`, `contentType == "image/png"`) and
`UploadQueueTests.uploadsAndReportsPublicURL` (:63). I confirmed these exist; I did not re-read each body for "as
before" on a screenshot, which is the catalogue's call (`catalogue.json` evidence names them). Verdict full for both, with
no new test beyond test 1.

Merged mark for both: "(suite: CoordinatorSaveAsTests.saveAsOfASavedImageCopiesItsBytesAndChangesNothingElse,
CoordinatorSaveTests.aCaptureWithTheOverlayOffShowsNoCardAndStillUploads, CoordinatorDeleteTests.deleteDuringAnUploadCancelsItThenDeletesTheReservedKey,
CoordinatorRecordActionsTests.copyImageReadsTheFileOrDownloadsTheObject, CaptureRecordTests.mediaKindTypes,
UploadQueueTests.uploadsAndReportsPublicURL, CoordinatorUploadTests.aFailedUploadOnlyImageKeepsItsPendingFileAndSizeUntilARetrySendsIt)".
The Retry test is the one that retries a screenshot (CoordinatorUploadTests.swift:534).

### SAVEAS.5 Added to existing suites: CoordinatorEditorSaveTests (test 9), CoordinatorEditorUploadTests (test 10)

CT-2's mark leaves to SAVEAS "the card's Save As… panel" and to others "the drop". The two CT-2 tests already read the
edit through `imageData(of:)` (CoordinatorEditorSaveTests.swift:518, CoordinatorEditorUploadTests.swift:910), which is
the read Save As… makes, so what is new is the panel answer and the written copy. The designer's way was to extend each
CT-2 test by five lines. This catalogue gives each a second, small test instead, on CT-2's own helpers
(`openedEditor`, `settledEdit`, `addSavedImage`/`addPendingImage`, `desktop`, `pendingURL`, `EditorPixels.isBlue`), so
the CT-2 tests keep the names the mark cites; extending them in place (adding `chooser.answers = [copy]`, `saveAs`, an
`eventually` on `.saved`, and `isBlue(Data(contentsOf: copy))`) is the cheaper equivalent and gives the same merged mark.

#### 9 `saveAsAfterASaveOverTheFileWritesTheEditNotTheOriginal` (M, in `CoordinatorEditorSaveTests`)
- Entry: `actions.save` through `FakeEditor.save()` (applyLocalEdit, +Editor.swift:180-221), then `coordinator.saveAs(
  recordID:)`.
- Source: a save-folder PNG, `storeSaveFolder()`, `addSavedImage(to:in:)`; `world.cards.showing.insert(id)`; `coordinator.
  prepareDragFile(recordID: id)`; `eventually { world.cards.dragFiles(for: id).last.flatMap { $0 } != nil }` and the staged
  file equals `original` (as CoordinatorEditorSaveTests.swift:499-503).
- Script: `chooser.answers = [desktop("Edited.png")]`.
- Sequence and asserts: `coordinator.openEditor(recordID: id)`; `openedEditor(id)`; `editor.draw()`; `#expect(await editor.
  save())`; `!exists(coordinator.dragFiles.folder(for: id))` (the edit removes the drag copy, +Editor.swift:209); `saveAs`;
  `eventually { world.notifier.calls.contains(.saved(title: "Saved", file: "Edited.png")) }`; `EditorPixels.isBlue(png:
  Data(contentsOf: Edited.png))` and `Data(contentsOf: Edited.png) != original`; `destination.state.withLock {
  $0.dataDownloadKeys }.isEmpty` and `world.factory.askedConfigs.isEmpty`; ends with `try await settledEdit(coordinator,
  id)`.
- By hand: the drop. Reaching Save As… after the edit, which only a pin offers (`PINS`; Recent Captures has none,
  `RecentCapturesMenu.swift:110-121`).
- Effort: M.

#### 10 `saveAsAfterAnEditorUploadOfAnUploadOnlyCaptureWritesTheEditDuringAndAfterThePut` (M, in `CoordinatorEditorUploadTests`)
- Entry: `actions.upload` through `FakeEditor.upload()`, then `coordinator.saveAs(recordID:)` twice.
- Source and setup: as CT-2's test at CoordinatorEditorUploadTests.swift:875: `addPendingImage`, `world.cards.showing.insert(id)`,
  `retryUpload`, `eventually { uploadedKey != nil }`, `holdingUploadsRemaining = 1` with `defer {
  destination.releaseUploads() }`, `openEditor`, `openedEditor(id)`, `editor.draw()`, `await editor.upload()` returning
  `EditorUploadOutcome(wroteLocally: true, enqueued: true)`.
- Script: `chooser.answers = [desktop("During.png"), desktop("After.png")]`.
- Sequence and asserts: `eventually { destination.state.withLock { $0.heldUploads.count } == 1 }`. `saveAs`; `eventually {
  calls.contains(.saved(title: "Saved", file: "During.png")) }`; `isBlue(Data(contentsOf: During.png))` (the record's
  `fileURL` is `pending/<id>.png`, temporary, read directly, RA:226-227). `destination.releaseUploads()`; `eventually {
  history.record(id: id)?.uploadState == .uploaded(url: publicURL(k), key: k) }`; `saveAs`; `eventually { calls.contains(
  .saved(title: "Saved", file: "After.png")) }`; `isBlue(Data(contentsOf: After.png))` (now `fileURL == nil`, the kept drag
  copy is read, RA:234). `dataDownloadKeys.isEmpty`; no `Downloading` notice. Ends with `settledEdit`.
- By hand: as test 9.
- Effort: M.

Merged mark for phase-6a:199 (CT-2's text gains the two tests; `SAVEAS` leaves the by-hand list, `PINS` enters it):
"(suite, in part: CoordinatorEditorSaveTests.saveOverTheFileRemovesTheDragCopyAndEveryReadGivesTheEdit,
CoordinatorEditorUploadTests.uploadOfAnUploadOnlyCaptureRemovesItsDragCopyAndEveryReadGivesTheEdit,
CoordinatorEditorSaveTests.saveAsAfterASaveOverTheFileWritesTheEditNotTheOriginal,
CoordinatorEditorUploadTests.saveAsAfterAnEditorUploadOfAnUploadOnlyCaptureWritesTheEditDuringAndAfterThePut; by hand: the
drop, and reaching Save As… after the edit, which only a pin offers (`PINS`); the line's "from the card" cannot happen
after an Annotate, which closes the card for good, and in upload-only mode ⌘S is Save As…, so the tests read through
Recent Captures and remove the drag copy with ⌘U there and ⌘S over a saved file)".

### SAVEAS.6 Per-line check

| Line | Every check in the line | In a test | Left |
|---|---|---|---|
| coordinator-split:44 | Save As… suggests the capture's own name, Cancel | 1 steps 1 and 5 | pin, second click, Close Pinned, the pin's menu (`PINS`, `SCREENS`) |
| phase-6a:170 | bytes equal; `Saved` with name; none when off, file still written; original as target unchanged | 1 steps 2 to 4 | `shasum`, the click revealing the copy, the Replace prompt |
| phase-6a:171 | template name with the counter, none drawn; no folder means panel's memory; pending file while `Uploading…` and after a failure | 2 | where the panel last was |
| phase-6a:172 | drag copy, no `Downloading`; panel first, then the notice and the write; offline `Not saved` | 3 | the restore (`SCREENS`), `curl`, slow profile |
| phase-6a:174 | card, link, Recent Captures, `history.json`, Reveal Last Capture, clipboard unchanged | 1 step 5 | none |
| phase-6a:175 | panel survives the auto-close and saves | 5 | the real timer, the window staying usable |
| phase-6a:176 | each card saves its own capture | 6 | the restore (`SCREENS`), button vs menu by eye |
| phase-6a:198 | Save As… needs no download | 3 step 1 | Slack reading the file |
| phase-6a:199 | Save As… shows the edit | 9, 10 | the drop; reaching it after the edit (`PINS`) |
| recording-r1:313 | Save As… downloads to the chosen file | 7 | the restore starts no download (`SCREENS`) |
| recording-r1:340 | Save As… as before | 1 | none for Save As… |
| recording-r2:264 | `.gif` suggestion; writes a `.gif`, over an existing file | 8 | thumbnail click (`WORKSPACE`), `/Volumes/RecOff`, preview, Finder/Slack |
| recording-r2:670 | as recording-r1:340 | 1 | none for Save As… |
| recording-r4:277 | waits, then saves the landed file; one GET | 4 | none |

Neighbouring lines the same tests reach (not in the 14, for the merge to mark or not): phase-6a:173 (:192) "Cancel the
panel: nothing is written and nothing is posted" is test 1 step 1 and its exact-equality follow-up (its sandbox half, a
write into Documents, stays by hand); phase-6a:169 (:188) keeps the window, the activation and PNG-only by hand, while
"name and folder are the capture's own file in the save folder" is test 1's suggestion check (the PNG-only type is D,
`EditorNamingTests.thePanelAllowsTheSuggestionsType`).

## 5. LOG: the recording log sink

The tests the `LOG` seam gives the 12 lines of `lines-small.md` (section "LOG"), in the form of
`docs/superpowers/notes/2026-10-30-editor-seam/tests-editor.md`. The seam is the judge's (`judge.md` 3.1 to 3.6, binding):
`AppEnvironment.recordingLog: @Sendable (String) -> Void` (live `{ RecordingLog.note($0) }`) after `log`; the coordinator's
24 `RecordingLog.note` calls go through a one-line forwarder `recordingLog(_:)` (the two inside detached `placeRecording`
take a `note:` parameter); `RecordingRecovery.scan(_:note:)` takes `note: @Sendable (String) -> Void = { RecordingLog.note($0) }`
and `start()` hands it through `begin`'s existing `scanning:` parameter; `sweepMuteFolder` and `RecordingExtras` are not
changed. The fake is no new type: `CoordinatorWorldState` keeps a second locked array and the world exposes
`world.recordingLines` (judge 3.3, 3.4); `RecordingRecoveryTests` collects with the existing `LogLines`
(`TidyShotTests/UploadQueueTests.swift:20-23`).

Every code reference is at 30d3c15 (branch `small-seams`, working tree clean, so the seam is not in the tree: the
`RecordingLog.note` calls are quoted at the lines they have today, and each becomes `recordingLog(...)` with the text
unchanged, judge 3.2). Checklist lines are named by catalogue key with the current line in brackets, as `lines-small.md`
does. No Swift bodies; each entry gives every value a body needs. Where a value was run in the designer's scratch tree
(`ct3log`, 25 iterations; and once in the judge's `ct3merged`), the entry says so; what this catalogue adds or changes
beyond those runs is marked "not run".

Abbreviations: `+Rec` = `TidyShot/App/AppCoordinator+Recording.swift`; `Coord` = `TidyShot/App/AppCoordinator.swift`;
`RR` = `TidyShot/Recording/RecordingRecovery.swift`; `RC` = `TidyShot/Recording/RecordingController.swift`; `URLH` =
`TidyShot/URLScheme/URLCommandHandler.swift`; `Fakes` = `TidyShotTests/Support/CoordinatorFakes.swift`; `World` =
`TidyShotTests/Support/CoordinatorWorld.swift`; `CRT` = `TidyShotTests/CoordinatorRecordingTests.swift`; `RRT` =
`TidyShotTests/RecordingRecoveryTests.swift`; `ST` = `TidyShotTests/ShortcutsTests.swift`.

### LOG.1 What the catalogue changed from the designer's tests

Effort: `aLeftoverThatDoesNotPlay...` S; `stopRecordingLogsWhatItDidInEachPhase` M; `aStartLogsEach...` M;
`aSecondURLStart...` M; `aSettingsPromptLogs...` L (the longest, three holds and a lock). Together about +230 lines of
tests, plus the stale-comment edit on two existing tests (section 6) and four `#expect`s' worth of world check (section 5).

Compared with the designer's five tests (`design-log.md` section 4), this catalogue changes two of them, both marked
"not run" in their entries: `stopRecordingLogsWhatItDidInEachPhase` gains a selection step (a held capture lock stands
for the selection the R4 text names); `aSettingsPromptLogsItsAnswerOrWhyItWaits` answers its first ask Refuse and asks
again to Allow (both texts of the Settings prompt's answer line), and its recording step holds the capture lock as the
app does. The other three are the designer's, unchanged.

### LOG.2 What holds for every test here

- The lines are read from `world.recordingLines` (new), whole and in order with `==`, never `contains`. `world.logLines`
  is asserted empty beside it in the coordinator tests, because none of these paths calls the coordinator's own `log(...)`
  (the only `log(` in `+Rec` is the forwarder's own declaration at Coord:290 and `loadContent`'s `Shareable content failed`
  at Coord:515, which none of these tests reaches; checked by `grep`). It shows the two logs do not mix. Run in `ct3log`.
- Only lines the coordinator (and `RecordingRecovery.scan`) writes are collected. The recorder's, the driver's,
  `GIFMaker`'s, `RecordingExtras`', `RecordingMute`'s and the rest still go to `RecordingLog.note` and never appear
  (judge 3.5 rule 2). So `beginRecording` (which runs the real `RecordingController` over `FakeRecordingDriver`) adds none.
- No test passes `recordingCanStart` (`+Rec:354-378`), which makes the live `tmp/Recording` (`Recording.makeDirectory()`,
  `TidyShot/Recording/Recording.swift:57-59`, over `FileManager.default.temporaryDirectory`). Every start parks at a
  prompt (`HeldMicrophoneDevices`, `HeldCameraDevices`, `Fakes:306-356`) and is ended by a quit before the capture lock,
  in the D31 form the existing tests use (CRT:315-378): `do { defer { cameras.answer(false) }; let quit =
  TaskWatch(Task { await coordinator.finishRecordingForQuit() }); try await eventually { quit.hasReturned } }`.
  `finishRecordingForQuit` (Coord:489-499) sets `isQuitting`, cancels the self-timer, calls `recorder.quit()` (a no-op
  when nothing runs, RC:298-303), loops while `recordingPhase != .idle` and then posts `waited(.seconds(1))` on the
  notifier (Coord:498, :504); so `world.notifier.calls == [.waited(.seconds(1))]` after it, as in CRT:279, :312, :377.
- Every held task is cancelled in a `defer` registered right after `defer { world.removeAll() }` and gated with
  `TaskWatch` and `eventually` (`Fakes:418-431`). A task that waits on a held fake is never awaited directly. A Settings
  ask that must not prompt runs as its own gated task (CRT:215-230's form), so an ask that prompted after all fails in two
  seconds (the second entry into `SingleWaiter` records an issue, `Fakes:373-416`).
- A prompt's name in a line is `PermissionPrompt.name`: `"microphone"` or `"camera"` (Coord:589-594; pinned by
  `ST:130` `eachPromptHasItsName`).
- Settings the start tests set, as the existing ones do: `world.settings.recordingMicrophone =
  MicrophoneChoice.systemDefaultValue` (only where a microphone prompt is wanted), `world.settings.recordingWebcamBubble =
  true`, `world.settings.hideDesktopIconsWhileCapturing = false` (its default is already false, AppSettings.swift:295; the
  existing tests set it for the reader). `world.settings` is the world's own `AppSettings` over its defaults suite, never
  `AppSettings.shared`.
- `HistoryStore` and the thumbnail machinery are not reached: no test here has a record.

### LOG.3 CoordinatorRecordingTests.swift (existing, four tests appended)

Header (the MARK's comment): "The `Recording:` lines the coordinator writes (small seams design, LOG): read from
`world.recordingLines`, the environment's `recordingLog`. Nothing here records; starts end at their prompt." The helpers
are the suite's own: `beginRecording(on:)` (CRT:31-40), `beginCountdown(on:)` (CRT:43-49), `areaRequest()` (CRT:15-25).

#### `stopRecordingLogsWhatItDidInEachPhase` (M)
- Entry: `coordinator.stopRecordingCommand(sender:)` (`+Rec:175-193`), the verb `stop-recording` reaches through
  `URLCommandTarget` (URLH:188). It switches on `recordingStopCommandAction(for: recordingPhase)` (`+Rec:45-51`):
  `.recording` → `.stop`, `.countIn` → `.cancelCountIn`, `.idle` and `.saving` → `.nothing`; `.stop` splits on
  `recorder.isEnding` (RC:131, `isRunning && cause != nil`). The phase is `recordingPhase` (`+Rec:9-14`): `recordingCountIn`
  first, then `recorder.isRunning`, then `recordingSavesInFlight > 0`, else `.idle`.
- Source: no record. The phases are set up with the suite's own helpers, as tests 48 to 50 do (CRT:56-105).
- Fakes: the world's `FakeRecordingDriver` and chrome (`world.driver`, `world.chrome`, `world.recording`) under the real
  `RecordingController`; a `FakeSelfTimerStage` inside `beginCountdown`; `TestGate` for the selection step. Nothing is
  scripted. `world.recordingLines` is empty at the start.
- Sequence (each stop is a synchronous call; `name` is `sender ?? "an unknown app"`, `+Rec:176`):
  1. Idle: `stopRecordingCommand(sender: "Raycast")`.
  2. Selection (added here, not run): `let gate = TestGate()`, `let lock = Task { await coordinator.withCaptureLock(coversDesktop:
     false) { await gate.wait() } }`, `defer { lock.cancel() }`, `try await eventually { gate.isWaiting }` (the capture lock is
     held and the phase is still `.idle`, as during Record Screen's area selection, `startRecordScreen` `+Rec:205-236`,
     where `recordingCountIn` becomes true only inside `record()`, `+Rec:397-398`); `stopRecordingCommand(sender: "Keyboard
     Maestro")`; `#expect(coordinator.isCapturing)`; `gate.open()`; `let lockEnded = TaskWatch(lock)`; `try await eventually
     { lockEnded.hasReturned }`. `withCaptureLock` is `Coord:564-576`; `hideDesktopIconsWhileCapturing` is false so
     `covers` is not touched.
  3. Saving: `coordinator.recordingSavesInFlight = 1`, `stopRecordingCommand(sender: nil)`, `recordingSavesInFlight = 0`.
  4. Count-in: `coordinator.recordingCountIn = true`, `let countdown = try await beginCountdown(on: coordinator)`,
     `defer { countdown.cancel() }`, `stopRecordingCommand(sender: "Raycast")`, `let ended = TaskWatch(countdown)`, `try
     await eventually { ended.hasReturned }`, then `coordinator.recordingCountIn = false`.
  5. Recording: `let run = await beginRecording(on: coordinator)`, `defer { run.cancel() }`; `stopRecordingCommand(sender:
     "Raycast")`; `#expect(coordinator.recorder.isEnding)`; `stopRecordingCommand(sender: "Raycast")` (the second, during
     the stop wait); `let runEnded = TaskWatch(run)`, `try await eventually { runEnded.hasReturned }`.
- Asserts:
  - `world.recordingLines == [` (with the step-2 line this is six; without it, the designer's five) `
    "Recording: stop-recording from Raycast did nothing, no recording is running",` (step 1, `+Rec:191`)
    `"Recording: stop-recording from Keyboard Maestro did nothing, no recording is running",` (step 2, `+Rec:191`)
    `"Recording: stop-recording from an unknown app did nothing, no recording is running",` (step 3, `+Rec:191`)
    `"Recording: stop-recording from Raycast cancelled the count-in",` (step 4, `+Rec:189`)
    `"Recording: stop-recording from Raycast stopped the recording",` (step 5 first stop, `+Rec:183`)
    `"Recording: stop-recording from Raycast did nothing, no recording is running"` (step 5 second stop, `+Rec:180`) `]`.
    The `did nothing` text of `+Rec:180` (the coordinator's `.stop` + `isEnding` branch) and of `+Rec:191` (`.nothing`) is
    one string; the two branches are told apart by the phase each line comes from, which is the order of the list.
  - State, as tests 48 to 50 pin it: `world.driver.stopCount == 1` (only step 5's first stop reached the recorder);
    `coordinator.recordingStartCancelled` is true after step 4 (`+Rec:187`; not reset by step 5, so not asserted at the
    end); `!coordinator.recorder.isRunning`; `world.notifier.calls.isEmpty`; `world.logLines.isEmpty`.
- By hand / other seam: none for the `did nothing` lines the checklist names. `recording-r4:217`'s count-in-off line
  (`Recording: not started, the count-in was cancelled`, `+Rec:411`), which the R4 text coordinator-harness check 4 points
  at (recording-r4 checklist :179-187) also names, is not this test's; it is in private `record()` (deferred, section 7).
  The hand set-up of the real macro (Keyboard Maestro sending `stop-recording`) is not a check.
- Covers: coordinator-harness:27, full; recording-r4:347, full.
- Run: the designer's five-line version, 25 iterations in `ct3log` and once in `ct3merged`. Step 2 and the sixth line are
  not run: the lock-held phase uses the same `TestGate` form as CRT:215-230 and `stopRecordingCommand` reads no lock, so
  the risk is small; if it needs cutting, the test is the designer's and the selection stays by hand for coordinator-harness:27
  (the line text says "in each phase", and the R4 text it points at lists selection first).

#### `aStartLogsEachPromptsAnswerAndASecondPressWhileOneIsUp` (M, held; the designer's)
- Entry: `coordinator.recordFullscreen()` (`+Rec:244-263`): `recordShortcutStarts()` (`+Rec:286-304`), then `recordingPrompts()`
  (`+Rec:317-346`), which asks the stored microphone's prompt and then the camera's (`startPrompts`, `+Rec:73-75`), logs each
  answer at `+Rec:339` and returns nil when `isQuitting` after an answer (`+Rec:340`). The second press is
  `coordinator.recordScreen()` (`+Rec:145-148`): `recordShortcutStarts()` → `.ignore` while `askingPermission` is set →
  `+Rec:293`.
- Source: no record.
- Fakes: `world.settings.recordingMicrophone = MicrophoneChoice.systemDefaultValue`; `recordingWebcamBubble = true`;
  `hideDesktopIconsWhileCapturing = false`; `let microphones = HeldMicrophoneDevices()` (access `.notDetermined`) and `let
  cameras = HeldCameraDevices()` (the same), `world.microphones = microphones`, `world.cameras = cameras`, both before
  `world.makeCoordinator()`. Both asks are needed: `MicrophoneChoice.asksForAccess(stored, format:, access:)` is true for the
  system default, mp4 and `.notDetermined`; `CameraChoice.asksForAccess(bubble: true, access: .notDetermined)` is true (same
  as CRT:288-295, :346-353 rely on).
- Sequence: `let start = Task { await coordinator.recordFullscreen() }`, `defer { start.cancel() }`, `let started =
  TaskWatch(start)`; `try await eventually { microphones.isAsking }`; `#expect(cameras.requestCount == 0)` (the microphone
  is first); `microphones.answer(true)`; `try await eventually { cameras.isAsking }`; `#expect(coordinator.askingPermission
  == .camera)`; `let second = TaskWatch(Task { await coordinator.recordScreen() })`; `try await eventually {
  second.hasReturned }`; `#expect(microphones.requestCount == 1)`; `#expect(cameras.requestCount == 1)`; then the quit in
  its D31 form with `defer { cameras.answer(false) }`; `try await eventually { started.hasReturned }`.
- Asserts:
  - `world.recordingLines == [` `"Recording: microphone access allowed at the prompt"` (`+Rec:339`, granted true),
    `"Recording: start ignored, the camera prompt is open"` (`+Rec:293`; the prompt is `askingPermission`, here `.camera`),
    `"Recording: camera access refused at the prompt"` (`+Rec:339`, granted false by the deferred `answer(false)`) `]`.
    The third is logged before the `isQuitting` return at `+Rec:340`, which is why a quit that came first still logs it.
  - `!coordinator.isCapturing` (the start never reached the lock); `coordinator.askingPermission == nil`;
    `world.notifier.calls == [.waited(.seconds(1))]`; `world.logLines.isEmpty`. Nothing makes `tmp/Recording`.
- By hand / other seam: for recording-r3:156, none: the line's second sentence (a start refused by the lock after its prompt)
  "cannot be forced by hand" and is `ST:219` `aRefusedStartPostsOnlyAfterAPrompt` (D); the `+Rec:273` line is reachable
  only past a prompt with the lock refused and is not claimed. For recording-r3:419 the prompt on screen, and the
  handler's `URL command from … dropped, the camera prompt is open` line (URLH:155, `NSLog`, no `Recording:` prefix, which
  the checklist text itself says), stay with `URLLOG`; the order is also `ST:110` `aStartAsksForTheMicrophoneThenTheCamera`
  (D) and the names `ST:130` (D).
- Covers: recording-r3:156, full; recording-r3:419, in part (the start's lines: order, answer text, ignored press).
- Run: yes, as above (25 iterations in `ct3log`, once in `ct3merged`).

#### `aSettingsPromptLogsItsAnswerOrWhyItWaits` (L, held; the designer's with two changes, not run)
- Entry: `coordinator.requestAccessFromSettings(_:)` (`+Rec:103-116`): `settingsPromptStep(phase:isCapturing:askingPermission:)`
  (`+Rec:81-84`) is `.ask` only for phase `.idle`, no lock, no prompt open, else `.wait`. `.wait` logs `+Rec:109` with the
  reason of `settingsPromptDeferralReason` (`+Rec:90-96`, in order: `the <name> prompt is open`; `a capture is running` when
  `isCapturing`; `a recording is being saved` for `.saving`; else nil, and the fallback `a capture is running` at
  `+Rec:107-108`). `.ask` sets `askingPermission`, awaits the system prompt and logs `+Rec:114`.
- Source: no record.
- Fakes: `let cameras = HeldCameraDevices()`, `world.cameras = cameras`; `let microphones =
  FakeMicrophoneDevices(access: .notDetermined)` (`TidyShotTests/Support/RecordingFakes.swift:417`), `world.microphones =
  microphones`; neither is configured by `world.settings`. A local `askWithoutAPrompt(_:)` runs `requestAccessFromSettings`
  as its own task and waits on its `TaskWatch` (an ask that prompts after all fails in two seconds).
- Sequence and asserts (the list is asserted once, at the end; the numbers are the list's):
  1. (changed, not run) A camera ask answered Refuse: `let ask = Task { await coordinator.requestAccessFromSettings(.camera)
     }`, `defer { ask.cancel() }`, `let asked = TaskWatch(ask)`; `try await eventually { cameras.isAsking }`;
     `#expect(coordinator.askingPermission == .camera)`; `cameras.answer(false)`; `try await eventually { asked.hasReturned }`.
     Line 1: `"Recording: camera access refused at the Settings prompt"` (`+Rec:114`).
  2. A second camera ask answered Allow, the same way (a fresh `Task`, `TaskWatch`, `defer`), `cameras.answer(true)`. Line 2:
     `"Recording: camera access allowed at the Settings prompt"` (`+Rec:114`). `HeldCameraDevices` takes sequential prompts
     (`SingleWaiter` is single-entry, not single-use); `#expect(cameras.requestCount == 2)` at the end.
  3. Saving: `coordinator.recordingSavesInFlight = 1`; `#expect(coordinator.recordingPhase == .saving)`; `try await
     askWithoutAPrompt(.camera)`; `recordingSavesInFlight = 0`. Line 3: `"Recording: camera prompt from Settings deferred, a
     recording is being saved"` (`+Rec:109` with the `.saving` reason, `+Rec:94`).
  4. The lock held (a capture, e.g. a selection): `let gate = TestGate()`, `let lock = Task { await
     coordinator.withCaptureLock(coversDesktop: false) { await gate.wait() } }`, `defer { lock.cancel() }`, `let lockEnded =
     TaskWatch(lock)`, `try await eventually { gate.isWaiting }`; `try await askWithoutAPrompt(.camera)`. Line 4: `"Recording:
     camera prompt from Settings deferred, a capture is running"` (`+Rec:93`, `isCapturing`). The lock stays held into step 5.
  5. (changed, not run) A recording, with the lock still held as the app holds it for the whole of a recording: `let run =
     await beginRecording(on: coordinator)`, `defer { run.cancel() }`; `#expect(coordinator.recordingPhase == .recording)`;
     `try await askWithoutAPrompt(.microphone)`; `try await askWithoutAPrompt(.camera)`; then `coordinator.recorder.stop()`,
     `let runEnded = TaskWatch(run)`, `try await eventually { runEnded.hasReturned }`, `gate.open()`, `try await eventually {
     lockEnded.hasReturned }`. Lines 5 and 6: `"Recording: microphone prompt from Settings deferred, a capture is running"` and
     `"Recording: camera prompt from Settings deferred, a capture is running"` (`+Rec:109`, reason `+Rec:93`). The designer
     ran the recorder alone, without the lock, which gives the same text through the fallback at `+Rec:107-108`; that branch
     is not reachable in the app (`record()` runs inside `withCaptureLock`, `+Rec:211-233`, and `recordFullscreen` the same,
     `+Rec:248-260`), and its comment says "Nil cannot come here" (`+Rec:106`), so the lock-held form is the faithful one and
     the fallback is not pinned.
  6. Another prompt open: `coordinator.askingPermission = .microphone`, `try await askWithoutAPrompt(.camera)`,
     `coordinator.askingPermission = nil`. Line 7: `"Recording: camera prompt from Settings deferred, the microphone prompt is
     open"` (`+Rec:92`).
  - Final: `world.recordingLines == [` the seven strings above in order `]`; `cameras.requestCount == 2`;
    `microphones.requestCount == 0`; `world.logLines.isEmpty`; `coordinator.askingPermission == nil` after step 6's reset.
- By hand / other seam: for recording-r3:162 and recording-r4:214, the view's own call: the microphone pick and the
  `Show webcam bubble` toggle reach the coordinator through `AppCoordinator.shared.requestAccessFromSettings(.microphone)`
  (`TidyShot/Settings/CaptureSettingsView.swift:222`) and `(.camera)` (`:253`); no seam covers a view's call on a shared
  instance, and the test calls the function the view calls. The GIF conversion (r4:214) is set-up: `.saving` is set
  directly, as `recordingSavesInFlight` is what a conversion holds (`+Rec:12`). `tccutil reset` is Tim's and is set-up.
  The reason strings are `ST:196` `aDeferredSettingsPromptGivesItsTrueReason` (D); the step rule `ST:119` (D).
- Covers: recording-r3:162, in part; recording-r4:214, in part; recording-r3:419, in part (the Settings prompt's lines:
  both answers, `deferred` with its reason).
- Run: the designer's version (no refuse-first ask, recorder-only step 5, six lines), 25 iterations in `ct3log` and once in
  `ct3merged`. The refuse-first ask and the lock-held recording are not run; both use fakes and helpers the run already
  exercised (`HeldCameraDevices` sequential asks are what CRT:215-230 and CRT:233-247 do in two separate tests; here two in
  one test, which `SingleWaiter` allows because `resume` clears the waiter, `Fakes:408-415`).

#### `aSecondURLStartBeforeTheFirstTakesTheLockIsLogged` (M, held; the designer's)
- Entry: `URLCommandHandler.handle(_:sender:)` (URLH:84-95, then `run`, URLH:136-199) over the coordinator as `URLCommandTarget`;
  for `tidyshot://record-screen` it calls `target.startRecording(intent:preselect:)` (URLH:188 → `+Rec:156-169`). That function
  logs `+Rec:160` when the app is quitting and `+Rec:165` when `urlRecordingStartPending` is already set, else sets the flag
  and spawns `Task { await startRecordScreen(...) }` (`+Rec:168-169`).
- Source: no record.
- Fakes: `world.settings.recordingWebcamBubble = true`; `hideDesktopIconsWhileCapturing = false`; `let cameras =
  HeldCameraDevices()`, `world.cameras = cameras` (no microphone prompt: the default microphone choice asks for none, as
  CRT:151-197 relies on); the handler is `URLCommandHandler(settings: world.settings, target: coordinator, screens: {
  URLCommandHandler.Screens(displays: [], pointerIndex: nil) }, post: { notice in Issue.record("The URL handler posted
  \(notice.body)") })`, then `await handler.ready()`. `world.settings.urlCommandsEnabled` is true by default
  (AppSettings.swift:290) and `record-screen` is not a command that captures without a selection
  (`URLCommand.capturesWithoutSelection`, URLCommand.swift:68-75, false for `.recordScreen`), so `URLCommandGate.decision`
  (URLCommandGate.swift:15-21) is `.run` regardless of `urlCommandsAllowSilent`. `let url = try #require(URL(string:
  "tidyshot://record-screen"))`.
- Sequence: `let sends = Task { await handler.handle(url, sender: "Keyboard Maestro"); await handler.handle(url, sender:
  "Keyboard Maestro") }`, `defer { sends.cancel() }`, `let sent = TaskWatch(sends)`; `try await eventually { sent.hasReturned }`;
  `try await eventually { cameras.isAsking }`; the checks while parked; the quit in its D31 form with `defer {
  cameras.answer(false) }`; `try await eventually { !coordinator.urlRecordingStartPending }`; then, after the quit,
  `coordinator.startRecording(intent: CaptureIntent(action: .save), preselect: nil)`.
  Why the second URL reaches the coordinator's line and not the handler's `dropped` line (URLH:154-157): `run` has no
  suspension between its `captureRefusal` read and `target.startRecording` for a `record-screen` without a rect (the
  `screens()` read is only under `if let area`, URLH:160); both `handle` calls run in one task, so the first start's `Task`
  cannot run between them; `captureRefusal` (Coord:542-551, :554) does not read `urlRecordingStartPending`, so it is nil for
  the second URL. If the handler ever gained a suspension before the call, the first list element below would fail; the test
  would not hang.
- Asserts:
  - While parked: `coordinator.urlRecordingStartPending`; `cameras.requestCount == 1` (one start reached a prompt: the line's
    "one selection" has no analogue before the lock; it is by hand); `world.notifier.calls.isEmpty` (no notice, which the
    line asks); no `post` from the handler (the closure records an issue).
  - After the quit and the post-quit URL: `world.recordingLines == [` `"Recording: URL start ignored, a recording is
    starting"` (`+Rec:165`, the second URL), `"Recording: camera access refused at the prompt"` (`+Rec:339`, the first start's
    prompt answered false by the deferred answer), `"Recording: URL start ignored, the app is quitting"` (`+Rec:160`, the
    post-quit URL; `recordingStartsFromURL` is false only because `isQuitting`, `+Rec:35-41`) `]`.
  - `cameras.requestCount == 1`; `!coordinator.isCapturing`; `world.notifier.calls == [.waited(.seconds(1))]`;
    `world.logLines.isEmpty` (the handler's own `NSLog` lines go to the system log, not to `environment.log`).
- By hand / other seam: for recording-r4:192, "one selection" on screen, the drawn UI, which joins no seam (spec call 11),
  and the Keyboard Maestro macro itself; the line accepts the
  coordinator's text or the handler's `dropped` line, so `URLLOG` is not needed for it. For recording-r4:366, none: the
  drop is also `CRT:151` `aURLStartIsRefusedInEveryPhaseThatDropsIt` (third block, D), without the text.
- Covers: recording-r4:366, full; recording-r4:192, in part.
- Run: yes (25 iterations in `ct3log`, once in `ct3merged`).

### LOG.4 RecordingRecoveryTests.swift (existing, one test inserted before `anMP4BesideAPartialGIFIsFoundAndTheGIFRemoved`)

#### `aLeftoverThatDoesNotPlayIsRemovedAndLogged` (S, the designer's)
- Entry: `RecordingRecovery.scan(_:note:)` (RR:22 after the change, `@concurrent static`). It sorts the folder by name (RR:27),
  inspects each regular file with `VideoValidation`, removes a file that is not playable or has no video track and calls
  `note("Recording: \(url.lastPathComponent) could not be played, removed")` (RR:34). The launch path to it is
  `start()` → `RecordingRecovery.begin(...scanning:)` (Coord:320-325 after the change passes `{ await RecordingRecovery.scan($0, note: note) }`
  with `note = environment.recordingLog`; `begin` is RR:107-112 and already takes `scanning:`).
- Source: the suite's own temp folder `dir` (`RRT:12-16`, a fresh UUID folder per test, removed in a `defer`); no
  `tmp/Recording`, no coordinator.
- Fakes: `LogLines` (`UploadQueueTests.swift:20-23`, a `Mutex<[String]>`) as `note:`, appended with `{ line in
  lines.lines.withLock { $0.append(line) } }`.
- Sequence: write `Data("junk\n".utf8)` to `dir/x.mp4` (the checklist's `echo junk > "$C/tmp/Recording/x.mp4"`); `let playable =
  dir.appending(path: "\(UUID().uuidString).mp4")`, `try await VideoFixtures.makeMP4(at: playable, width: 320, height: 200,
  seconds: 1, audio: false)` (as RRT:57-58); `let found = await RecordingRecovery.scan(dir, note: note)`.
- Asserts: `found.map(\.url.lastPathComponent) == [playable.lastPathComponent]`; `x.mp4` no longer exists; `playable` still
  exists; `lines.lines.withLock { $0 } == ["Recording: x.mp4 could not be played, removed"]` (only the junk file is logged: the
  playable file passes the guard at RR:31, and the removal succeeded so RR:36 is not reached).
- By hand / other seam: the relaunch (`start()` taking `tmp/Recording` and handing `scan` the environment's sink) is code,
  not driven: `start()` also touches `Recording.directory`, `MuteLog.directory`, `ClopApp.workDirectory` and
  `RecordingTrim.directory` (Coord:294-325; `TMPDIRS`, `LAUNCH`). In the app the default argument of `scan` is the same
  function the environment's live `recordingLog` is, so the text and the log are the same either way. The `could not be played
  or removed: <error>` line (RR:36) is not claimed; a test would need a folder the test makes read-only and the error text is
  the system's.
- Covers: recording-r1:263, full (the removal is also `RRT:50-64` `garbageIsRemovedAndAPlayableFileBesideItIsFound`, D).
- Run: yes (25 iterations in `ct3log`, once in `ct3merged`). Effort S.

### LOG.5 Support and the shared checks

Not tests; the values a plan task needs.
- `CoordinatorWorldState` (`Fakes:255-289`, `nonisolated final class ... Sendable`, a `Mutex<Values>`): `Values` gains
  `var recordingLines: [String] = []`; a getter `var recordingLines: [String]` and `func appendRecording(_ line: String)`; its
  doc says "the two logs". `World` (`World:106` is `logLines`): `var recordingLines: [String] { state.recordingLines }`, and
  `recordingLog: { line in state.appendRecording(line) }` as the last argument of the `AppEnvironment(...)` call at
  `World:113-134`, after `log:`. `AppEnvironment` has no memberwise `init` shortcut: the member is a positional argument at
  exactly two sites, `AppEnvironment.swift:61` (`live()`) and `World:113` (judge 0).
- `CoordinatorWorldTests.aCoordinatorOverTheWorldKeepsToTheWorld` (`CoordinatorWorldTests.swift:14-32`): after `#expect(world.logLines.isEmpty)`
  (`:31`) add `#expect(world.recordingLines.isEmpty)`: building a coordinator writes no `Recording:` line (`init` and the
  lazy members do not call the forwarder). Run in `ct3merged`.

### LOG.6 Existing tests that change

- `CRT:50-53` (test 48) and `CRT:87-90` (test 50): their comments say the state "does not tell the `.nothing` branch from a
  stray `recorder.stop()` (D24)" and "its log line is Tim's (D24)". Once `stopRecordingLogsWhatItDidInEachPhase` exists
  they are stale. The edit is the designer's (design-log.md, "The stale comments on tests 48 and 50"): test 48 ends "...so
  the state does not tell the `.nothing` branch from a stray `recorder.stop()` (D24); the line does
  (`stopRecordingLogsWhatItDidInEachPhase`)."; test 50 ends "...so the state does not see the coordinator's `isEnding`
  check (D24); its log line does (`stopRecordingLogsWhatItDidInEachPhase`)." Neither test's body changes.
- The checklist text of coordinator-harness:27 itself ("the suite pins the state, not the `RecordingLog` text, and tests 48
  and 50 cannot tell...") becomes untrue with the mark; the mark replaces the box, as for other full lines, and the sentence
  stays as history unless the plan prefers to reword it.

### LOG.7 Deferred lines

#### recording-r3:416 (:452) "The recording's clock times the camera's log lines and the loss note." Deferred (`EXTRAS`)
The lines are `Recording: camera lost at <time>: <name>` (`RecordingExtras.swift:221`) and `camera back at <time>` (`:235`), in
`received(_:)` (`:211`, private) and `cameraBack()` (`:232`, private), fed only by reports of a real `CameraSession`
built in `runCamera` (`:194-201`); the time is `elapsed()` (`:219`, `:233`), which `makeRecordingExtras` wires to
`recorder.elapsedTime` (`+Rec:443`; the clock itself is D: `RecordingControllerTests.swift:1120`
`elapsedTimeCountsFromTheFirstFrame`, `:1136` `elapsedTimeIsZeroAfterClose`). `RecordingExtras` has no log member (`init`,
`RecordingExtras.swift:60-71`), the judge's scope leaves it unchanged (3.1), and `makeRecordingExtras` is reached only from
private `record()` (`+Rec:398`), past the lock, `recordingCanStart` and `loadContent`. `LOG` gives a place to read the lines;
no test can produce a `.lost` or `.back` report without `EXTRAS`' fake session. What `EXTRAS` then adds: `log: @escaping
@Sendable (String) -> Void` on `init` (about 8 lines: stored, the four calls become `log(...)`, `makeRecordingExtras` passes
`environment.recordingLog`), and a test with a fake session reporting `.lost` then `.back` and an `elapsed` closure returning
two chosen times, expecting `"Recording: camera lost at <RecordingClock.format(t1)>: <name>"` then `"Recording: camera back at
<RecordingClock.format(t2)>"` and `cameraLoss == .stopped(at: t1, backAt: t2)`. Mark: none now.

#### recording-r3:436 (:482) "`Recording: camera could not be started: <reason>` is logged." Deferred (`EXTRAS`)
The line is `RecordingExtras.swift:215`, in `received(_:)` on a `.couldNotStart(reason)` report. No coordinator path reaches it
and the sink is not threaded through `RecordingExtras`; with `EXTRAS`' fake session reporting `.couldNotStart("<reason>")`,
`"Recording: camera could not be started: <reason>"`. Mark: none now. (The sweep's "RecordingExtras.swift:215-250 (camera
lines)" includes `:250`, the bubble size line, which is not a camera line and not claimed.)

#### recording-r4:217 (:221) "The record shortcut during the settle delay with `Count down before recording` off... logs `Recording: not started, the count-in was cancelled`." Deferred (`TMPDIRS`, `CAPSRC`)
The line is `+Rec:411`, in private `record(_:inputs:)` (`+Rec:397`), reached only after `recordingCanStart` (`+Rec:354-378`:
`Recording.makeDirectory()` makes the live container `tmp/Recording`, Recording.swift:57-59), `loadContent`
(Coord:511-523, `engine.shareableContent()`), `selector.select` (Record Screen) or `NSEvent.mouseLocation` plus a real
`SCDisplay` (Record Fullscreen), and then `recordingHandOff`, which reads `NSScreen.screens` (`+Rec:496`) and orders the
extras' windows front (`+Rec:501-507`, `extras?.show`). All are outside the allowed set. The sink is in place
for it: with `TMPDIRS` and `CAPSRC` a test would hold the content read, set `recordingStartCancelled` through the shortcut
(`recordShortcutStarts` `.cancelCountIn`, `+Rec:297-300`) and expect `"Recording: not started, the count-in was cancelled"`.
The pure rule stays pinned where the mark says: `CRT:129` `recordingProceedsOnlyWhenStartedNotQuittingAndNotCancelled`, and
the flag's reset `CRT:110` `theStartCancelResetsOnlyWhenACountInBegins`.
Merged mark: the existing note stays and gains the by-hand part: `(suite, the rule: CoordinatorRecordingTests.recordingProceedsOnlyWhenStartedNotQuittingAndNotCancelled; by hand: the log line, in private record() past the capture lock (TMPDIRS, CAPSRC))`.
The line is not otherwise reached: `stopRecordingLogsWhatItDidInEachPhase` step 4 cancels a count-in that was shown (count-in on),
which is `+Rec:189`, not `+Rec:411`.

### LOG.8 Marks

`(suite: Suite.test)` for full, `(suite, in part: ...; by hand: ...)` for part, as CT-1 and CT-2 (tests-editor.md 2.5). No
LOG line carries a CT-2 mark; recording-r4:217's CT-1 mark is the only existing one and is extended above. No line is
obsolete or already covered: `rg 'Recording: ' TidyShotTests` finds nothing, no test reads a `RecordingLog` line, and the
pure decisions behind the lines (`recordingProceeds`, `settingsPromptDeferralReason`, `recordingStopCommandAction`) are
pinned without their text (lines-small.md "What LOG alone unlocks"; facts-log.md section 5).

| Line | Merged mark |
|---|---|
| coordinator-harness:27 | `(suite: CoordinatorRecordingTests.stopRecordingLogsWhatItDidInEachPhase)` |
| recording-r1:263 | `(suite: RecordingRecoveryTests.aLeftoverThatDoesNotPlayIsRemovedAndLogged; the relaunch and the junk file are the set-up)` |
| recording-r3:156 | `(suite: CoordinatorRecordingTests.aStartLogsEachPromptsAnswerAndASecondPressWhileOneIsUp)` |
| recording-r3:162 | `(suite, in part: CoordinatorRecordingTests.aSettingsPromptLogsItsAnswerOrWhyItWaits; by hand: the microphone pick in Settings reaching the coordinator, a view's call on AppCoordinator.shared (CaptureSettingsView.swift:222))` |
| recording-r3:416 | none |
| recording-r3:419 | `(suite, in part: CoordinatorRecordingTests.aStartLogsEachPromptsAnswerAndASecondPressWhileOneIsUp, .aSettingsPromptLogsItsAnswerOrWhyItWaits, ShortcutsTests.aStartAsksForTheMicrophoneThenTheCamera; by hand: the prompts on screen and the URL command's own dropped line (URLLOG))` |
| recording-r3:436 | none |
| recording-r4:192 | `(suite, in part: CoordinatorRecordingTests.aSecondURLStartBeforeTheFirstTakesTheLockIsLogged, the coordinator's text, which the line accepts; by hand: the one selection on screen)` |
| recording-r4:214 | `(suite, in part: CoordinatorRecordingTests.aSettingsPromptLogsItsAnswerOrWhyItWaits; by hand: the Show webcam bubble toggle reaching the coordinator, a view's call on AppCoordinator.shared (CaptureSettingsView.swift:253); the GIF conversion is set up as .saving)` |
| recording-r4:217 | `(suite, the rule: CoordinatorRecordingTests.recordingProceedsOnlyWhenStartedNotQuittingAndNotCancelled; by hand: the log line, in private record() past the capture lock (TMPDIRS, CAPSRC))` |
| recording-r4:347 | `(suite: CoordinatorRecordingTests.stopRecordingLogsWhatItDidInEachPhase)` |
| recording-r4:366 | `(suite: CoordinatorRecordingTests.aSecondURLStartBeforeTheFirstTakesTheLockIsLogged)` |

seams.md section 8 (`docs/superpowers/notes/2026-10-30-checklist-sweep/seams.md:366-387`) reads "12 lines, 9 alone". Under this
catalogue the 12 are 5 full, 4 part, 3 deferred; 7 are unlocked by `LOG` alone (the 5 full, plus recording-r3:162 and recording-r4:214
whose part is a view call, not a seam); recording-r3:419 names `URLLOG` for the handler's line, recording-r4:192 is one selection short of full,
recording-r3:416 and :436 wait on `EXTRAS`, recording-r4:217 on `TMPDIRS` and `CAPSRC`. `EXTRAS` takes r3:416 and :436 to full when it adds the
`log:` parameter to `RecordingExtras.init`; `TMPDIRS` with `CAPSRC` takes r4:217.

### LOG.9 Lines the sink collects that no checklist line claims

Not claimed, not tested here: `+Rec:273` (the lock refusing a start after a prompt), `+Rec:358`/`:365` (`recordingCanStart`, live `tmp/`),
`+Rec:468` (`endNoticeHold`, reached only from `record()`), `+Rec:590` (`muteLag`), `+Rec:884`/`:892` (`placeRecording`'s moves, detached),
`+Upload:378`/`:395` (`refuseOversizedUpload`), `+Recovery:127`-`:161` (`recoverRecordings`, which no test calls), `RR:36` and `RR:137`.
`recordingLog` makes each collectable by a later phase; `recoverRecordings` would need `sweepMuteFolder` threaded too (judge 3.1, deferred with
its reason).

### LOG.10 Open points for the plan

1. Two changes to the designer's tests are not run (section 1): the selection step in `stopRecordingLogsWhatItDidInEachPhase` and the refuse-first
   ask plus the lock-held recording in `aSettingsPromptLogsItsAnswerOrWhyItWaits`. If either fails in the scratch run, revert it to the designer's
   form; the verdicts do not change (the selection stays by hand for coordinator-harness:27, which names "each phase" and points at the R4 text that
   lists it; the recording step falls back to the recorder-only form).
2. recording-r1:263 is full on the reading that the relaunch is set-up. If Tim reads `start()` handing `scan` the sink as part of the check, it is
   part with `LAUNCH`/`TMPDIRS` as the remainder; the entry says which.
3. The checklist text of coordinator-harness:27 ("the suite pins the state, not the `RecordingLog` text") is false once marked; reword or leave.

## 6. What the three seams share

From the judge's section 4. Each seam is one plan task and one commit on `small-seams` (its production diff, its support, its
tests, its marks in `docs/testing/` and its row in seams.md); the order is free, and CLOP, SAVEAS, LOG is the proposal.

- `TidyShot/App/AppEnvironment.swift`: three members in one declaration order that `live()` and `CoordinatorWorld.environment`
  pass positionally: `clopOptimiser` and `isClopRunning` after `freeBytes`, `chooseSaveAsURL` after `makeEditor`, `recordingLog`
  after `log`, last. Each seam adds its own member and its two arguments at its own place; only the `live()` doc sentence is
  reworded by all three.
- `TidyShotTests/Support/CoordinatorWorld.swift`: `clop` (over `<root>/tmp/Clop`, removed by `removeAll()`), `saveAsChooser` and
  `recordingLines`, each bound to a local before the struct is built.
- `TidyShotTests/Support/CoordinatorFakes.swift`: SAVEAS adds `FakeSaveAsChooser` after `FakeConfirm`; LOG adds a second locked
  array to `CoordinatorWorldState`. `TidyShotTests/Support/FakeDestination.swift`: SAVEAS makes `download(key:to:)` record and write (SAVEAS tests 4
  and 7 need it). `TidyShotTests/Support/ClopFakes.swift` is new (CLOP).
- `TidyShotTests/CoordinatorWorldTests.swift`, `aCoordinatorOverTheWorldKeepsToTheWorld`: four more `#expect`s, one per
  world member (`recordingLines.isEmpty`, `clop.runningChecks == 0`, `clop.requests.isEmpty`, `saveAsChooser.asked.isEmpty`).
  They are checks, not tests.
- Suites two seams write into: `CoordinatorEditorUploadTests` receives CLOP T17 and SAVEAS 10 (both use its helpers
  `addSavedImage`, `addPendingImage`, `openedEditor`, `settledEdit`); T17 needs `world.clop`, SAVEAS 10 needs
  `world.saveAsChooser`, so whichever task lands second adds its test to a file the first already touched.
- `refuseOversizedUpload` (+Upload:378, :395) is a `RecordingLog.note` caller that LOG's forwarder reaches and that CLOP's
  recording-r1:330 parenthetical (a refused 625 GB upload draws no counter) could drive with a sparse file over 671_088_640_000
  bytes; no test claims it (`LOG.9`, `CLOP.6`).
## 7. Suite files and totals

### 7.1 Suite files

| Suite file | New or existing | Tests added | Seam | Of them parameterized |
|---|---|---|---|---|
| `TidyShotTests/CoordinatorClopTests.swift` | new | 15 | CLOP | 2 (T2, T12) |
| `TidyShotTests/CoordinatorSaveAsTests.swift` | new | 9 (8 for lines, E1) | SAVEAS | 0 |
| `TidyShotTests/CoordinatorRecordingTests.swift` | existing | 4 | LOG | 0 |
| `TidyShotTests/RecordingRecoveryTests.swift` | existing | 1 | LOG | 0 |
| `TidyShotTests/CoordinatorTrimTests.swift` | existing | 1 (T16) | CLOP | 0 |
| `TidyShotTests/CoordinatorEditorUploadTests.swift` | existing | 2 (T17 CLOP, SAVEAS 10) | CLOP, SAVEAS | 0 |
| `TidyShotTests/CoordinatorSaveTests.swift` | existing | 1 (T18) | CLOP | 0 |
| `TidyShotTests/CoordinatorEditorSaveTests.swift` | existing | 1 (SAVEAS 9) | SAVEAS | 0 |
| `TidyShotTests/Support/ClopFakes.swift` | new support, no suite | 0 | CLOP | |
| `TidyShotTests/Support/CoordinatorFakes.swift`, `CoordinatorWorld.swift`, `FakeDestination.swift`, `CoordinatorWorldTests.swift` | existing support (section 6) | 0 | all | |
| **All** | | **34** | | |

### 7.2 Totals per seam

| Seam | Tests | Lines | Full | In part | Deferred (to) | Obsolete or already covered | CT-2 marks extended |
|---|---|---|---|---|---|---|---|
| CLOP | 18 | 23 | 19 | 4 | 0 | 0 | 0 (recording-r4:253 and :255 extend earlier marks) |
| SAVEAS | 11 (10 for lines, E1 for none) | 14 | 4 | 10 | 0 | 0 | 3 (coordinator-split:44, phase-6a:198, phase-6a:199) |
| LOG | 5 | 12 | 5 | 4 | 3 (`EXTRAS` 2: recording-r3:416, :436; `TMPDIRS` and `CAPSRC` 1: recording-r4:217) | 0 | 0 (recording-r4:217's earlier mark gains the by-hand part) |
| **All** | **34** | **49** | **28** | **18** | **3** | **0** | **3**, and 3 earlier marks |

- Full (28): CLOP 19 (phase-7-clop:28, :29, :31, :32, :35, :36, :37, :41, :42, :43, :44, :45; recording-r1:271, :297, :330;
  recording-r4:255, :323; small-tweaks:14, :15), SAVEAS 4 (phase-6a:174; recording-r1:340, recording-r2:670; recording-r4:277),
  LOG 5 (coordinator-harness:27; recording-r1:263; recording-r3:156; recording-r4:347, :366).
- In part (18), by what stays. Another seam's: 8 (SAVEAS: coordinator-split:44 `PINS` and `SCREENS`, phase-6a:172 and :176
  `SCREENS`, phase-6a:199 `PINS`, recording-r1:313 `SCREENS`, recording-r2:264 `WORKSPACE`; CLOP: recording-r1:296 `TMPDIRS`;
  LOG: recording-r3:419 `URLLOG`). By hand with no seam: 10 (CLOP: phase-7-clop:21, recording-r2:275, recording-r4:253; SAVEAS:
  phase-6a:170, :171, :175, :198; LOG: recording-r3:162, recording-r4:192, :214; recording-r4:192's leftover is the one selection
  on screen, the drawn UI, which joins no seam: spec call 11).
- Deferred (3) and why: recording-r3:416 and :436 need a fake camera session (`EXTRAS`) and the sink threaded through
  `RecordingExtras.init`; recording-r4:217's log line is in private `record()` past `recordingCanStart` and `loadContent`.
- seams.md counts that change: CLOP stays 23 lines, 22 alone; SAVEAS "9 alone" is 11 now that `EDITOR` landed, though 10 of
  its 14 end in part; LOG "12 lines, 9 alone" is 12 lines, 7 alone (recording-r4:217 needs `TMPDIRS` and `CAPSRC`, recording-r3:419
  names `URLLOG`).
- Effort (the entries give each test's): S 10, M 18, L 6. CLOP S 5 (T2, T8, T12, T14, T18), M 9, L 4 (T3, T9, T10, T16); SAVEAS S 4 (6, 7, 8, E1), M 6, L 1 (3); LOG S 1, M 3, L 1.

### 7.3 Expected suite line

Baseline at 30d3c15: `Test run with 2318 tests in 193 suites passed`. Plus 34 tests (each new `@Test` function once; CLOP T2 and T12 count
once each) and 2 suites (the two new files, `CoordinatorClopTests` and `CoordinatorSaveAsTests`; `ClopFakes.swift` holds no
tests and the other suites already count):

`Test run with 2352 tests in 195 suites passed`

The judge measured `2336 tests in 195 suites` for the designs' 18 tests (CLOP 5, SAVEAS 8, LOG 5); the other 16 add to it.
Without SAVEAS E1: 2351. With SAVEAS 9 and 10 as in-place extensions (section 2.1): 2350 (and 2349 with neither).
