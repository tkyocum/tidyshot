# CT-3 small-seam lines (49)

The 49 manual checklist lines that no test could drive until the Clop optimiser and its running check (`CLOP`), the card's Save As… panel (`SAVEAS`) or the recording log sink (`LOG`) were behind a seam (seams.md, `docs/superpowers/notes/2026-10-30-checklist-sweep/seams.md` sections 5, 6 and 8, lines 284-340 and 366-387), with what this phase tests of each. The key is the catalogue key (checklist file stem and the line number at e011d2f); the current line is the line in `docs/testing/<stem>-manual-checklist.md` at 30d3c15, where `lines-small.md` in the scratch folder found each by its text. The tests are in `tests-small.md` in this folder; the `Test` column of the tables below names them (a test is cited by its short name; the full names are the headings there). The 49 are distinct: the multi-seam section (seams.md lines 898-947) names CLOP, SAVEAS or LOG in 9 of them, all already in the three lists.

"Current mark" is the `(suite...)` note the checklist carries at 30d3c15; no line carries an `(obsolete: ...)` note. "Other seams" is what the catalogue evidence or the multi-seam list names beyond the seam the line is filed under; `EDITOR` landed in CT-2 and is marked (landed). Paths like `+Upload.swift:189` are `TidyShot/App/AppCoordinator+Upload.swift`; `+Recording.swift`, `+RecordActions.swift` likewise.

## Counts

| Seam | Lines | Only this seam (seams.md) | Only this seam (now) | Full | In part | Deferred (to) | Obsolete or already covered | Marks extended |
|---|---|---|---|---|---|---|---|---|
| CLOP | 23 | 22 | 22 | 19 | 4 | 0 | 0 | 2 earlier (recording-r4:253, :255) |
| SAVEAS | 14 | 9 | 11 | 4 | 10 | 0 | 0 | 3 CT-2 (coordinator-split:44, phase-6a:198, :199) |
| LOG | 12 | 9 | 7 | 5 | 4 | 3 (`EXTRAS` 2, `TMPDIRS` and `CAPSRC` 1) | 0 | 1 earlier (recording-r4:217, the by-hand part) |
| All | 49 | 40 | 40 | 28 | 18 | 3 | 0 | 3 CT-2, 3 earlier |

Why "only this seam (now)" moves: `EDITOR` landing makes `phase-6a:198` and `:199` need `SAVEAS` alone (SAVEAS 9 to 11); `recording-r4:217` needs `TMPDIRS` and `CAPSRC` for the line it names, and `recording-r3:419` names `URLLOG`, so LOG's 9 becomes 7 (the 7 are the 5 full plus `recording-r3:162` and `recording-r4:214`, whose part is a view's call on `AppCoordinator.shared`, not a seam). `recording-r1:263` is counted alone on the reading that `RecordingRecovery.scan` takes the sink and the relaunch is set-up.

## Overview

| Key | Seam | Current line | Other seams | Current mark | This phase | Test |
|---|---|---|---|---|---|---|
| `phase-7-clop:21` | CLOP | phase-7-clop:23 | none | none | part | T1 `turningClopOffDuringAnOptimisationKeepsThatUploadOptimisedAndNotTheNext` |
| `phase-7-clop:28` | CLOP | phase-7-clop:30 | EDITOR (landed) | none | full | T17 `anEditorUploadAndUploadAsNewEachSendClopsBytesAndTheLinkKeepsItsKey`; Retry leg: T1 |
| `phase-7-clop:29` | CLOP | phase-7-clop:31 | none | none | full | T7 `aCaptureWhoseUploadFailsAfterClopKeepsItsPendingFileAtTheCapturedSize`; hold leg also T1 |
| `phase-7-clop:31` | CLOP | phase-7-clop:33 | none | none | full | T2 `aClopThatIsNotRunningOrSkipsUploadsTheOriginalWithOneLine(reason:line:)`, `.notSmaller` |
| `phase-7-clop:32` | CLOP | phase-7-clop:34 | none | none | full | T6 `threeUploadsWithAnImageHeldInClopTakeCountersInStartOrder` |
| `phase-7-clop:35` | CLOP | phase-7-clop:37 | none | none | full | T2, `.notRunning` |
| `phase-7-clop:36` | CLOP | phase-7-clop:38 | none | none | full | T2, `.converted` |
| `phase-7-clop:37` | CLOP | phase-7-clop:39 | none | none | full | T2, `.failed("Clop's port is unavailable")` |
| `phase-7-clop:41` | CLOP | phase-7-clop:43 | none | none | full | T8 `deletingAnImageWhileClopHoldsItCancelsAtOnceAndNothingUploads` |
| `phase-7-clop:42` | CLOP | phase-7-clop:44 | none | none | full | T9 `aDeleteDeclinedAtTheSecondAlertWhileClopHoldsLeavesTheCardCancelledAndARetryUploadsOnce` |
| `phase-7-clop:43` | CLOP | phase-7-clop:45 | none | none | full | T10 `aRetryBeforeClopsFirstAnswerUploadsOnceFromTheSecondAttempt` |
| `phase-7-clop:44` | CLOP | phase-7-clop:46 | none | none | full | T4 `changingUploadSettingsWhileClopHoldsAnUploadFinishesItAtItsOwnDestination` |
| `phase-7-clop:45` | CLOP | phase-7-clop:47 | none | none | full | T1 |
| `recording-r1:271` | CLOP | recording-r1:285 | none | none | full | T3 `deletingARecordingWhileClopHoldsItCancelsAtOnceAndLeavesNoMovieOrCounterGap`; sentence 1 already D |
| `recording-r1:296` | CLOP | recording-r1:328 | TMPDIRS | none | part | T3 (Delete leg), T11 `aFailedRecordingUploadAfterClopLeavesNoMovieAndARetryAsksClopAgainFromTheOriginal` |
| `recording-r1:297` | CLOP | recording-r1:329 | none | none | full | T12 `aRecordingUploadsItsOriginalWithoutOptimizingWhenClopIsOffOrNotRunning(setting:running:)` |
| `recording-r1:330` | CLOP | recording-r1:376 | none | none | full | T3 (no gap, consecutive keys) |
| `recording-r2:275` | CLOP | recording-r2:291 | none | none | part | T13 `aGIFUploadsAsMadeWithOneClopLinePerLaunch`, T14 `anMP4RecordingGoesThroughClopShowingOptimizingAndUploadsClopsMovie` |
| `recording-r4:253` | CLOP | recording-r4:267 | none | earlier mark, extended | part | T16 `anUploadTrimmedWithClopWhoseFileChangedAsksClopAgainAndSendsTheSecondTrim` |
| `recording-r4:255` | CLOP | recording-r4:269 | none | earlier mark, extended | full | T5 `aRecordingOverThePartThresholdKeepsClopsMovieAndARetryResumesWithoutClop`; T15 `aClopMovieThatCannotBeKeptForResumeLogsItAndSendsTheThrowawayCopy` |
| `recording-r4:323` | CLOP | recording-r4:372 | none | none | full | T5 |
| `small-tweaks:14` | CLOP | small-tweaks:17 | none | none | full | T1 |
| `small-tweaks:15` | CLOP | small-tweaks:18 | none | none | full | T14 (optimised size), T5 (kept variant); save half T18 `anMP4sSizeIsTheMovedFilesSize` |
| `coordinator-split:44` | SAVEAS | coordinator-split:48 | PINS, SCREENS, EDITOR (landed) | CT-2 mark, extended | part | 1 `saveAsOfASavedImageCopiesItsBytesAndChangesNothingElse` |
| `phase-6a:170` | SAVEAS | phase-6a:189 | none | none | part | 1 |
| `phase-6a:171` | SAVEAS | phase-6a:190 | none | none | part | 2 `anUploadOnlyCapturesSaveAsSuggestsTheTemplateNameAndCopiesItsPendingFile` |
| `phase-6a:172` | SAVEAS | phase-6a:191 | none | none | part | 3 `anUploadOnlyCardsSaveAsWritesTheDragCopyOrDownloadsAfterThePanel` |
| `phase-6a:174` | SAVEAS | phase-6a:193 | none | none | full | 1 |
| `phase-6a:175` | SAVEAS | phase-6a:194 | none | none | part | 5 `aSaveAsPanelHeldThroughTheCardsAutoCloseStillSaves` |
| `phase-6a:176` | SAVEAS | phase-6a:195 | none | none | part | 6 `saveAsFromAnyCardWritesThatCardsCapture` |
| `phase-6a:198` | SAVEAS | phase-6a:220 | EDITOR (landed) | CT-2 mark, extended | part | 3 (its first part) |
| `phase-6a:199` | SAVEAS | phase-6a:224 | EDITOR (landed) | CT-2 mark, extended | part | 9 `saveAsAfterASaveOverTheFileWritesTheEditNotTheOriginal`, 10 `saveAsAfterAnEditorUploadOfAnUploadOnlyCaptureWritesTheEditDuringAndAfterThePut` |
| `recording-r1:313` | SAVEAS | recording-r1:353 | SCREENS | none | part | 7 `anUploadOnlyVideosSaveAsDownloadsToTheChosenFile` |
| `recording-r1:340` | SAVEAS | recording-r1:397 | none | none | full | 1 (Save As…); the other verbs are existing tests, section 4 |
| `recording-r2:264` | SAVEAS | recording-r2:278 | WORKSPACE | none | part | 8 `aGIFsSaveAsWritesTheGIFOverAnExistingFileToo` |
| `recording-r2:670` | SAVEAS | recording-r2:750 | none | none | full | 1; as recording-r1:340 |
| `recording-r4:277` | SAVEAS | recording-r4:294 | none | none | full | 4 `aRecordingsSaveAsDuringItsDragOutDownloadWaitsAndCopiesTheLandedFile` |
| `coordinator-harness:27` | LOG | coordinator-harness:27 | none | none | full | `stopRecordingLogsWhatItDidInEachPhase` |
| `recording-r1:263` | LOG | recording-r1:277 | none | none | full | `aLeftoverThatDoesNotPlayIsRemovedAndLogged` |
| `recording-r3:156` | LOG | recording-r3:161 | none | none | full | `aStartLogsEachPromptsAnswerAndASecondPressWhileOneIsUp` |
| `recording-r3:162` | LOG | recording-r3:167 | none | none | part | `aSettingsPromptLogsItsAnswerOrWhyItWaits` |
| `recording-r3:416` | LOG | recording-r3:452 | EXTRAS | none | deferred | none this phase |
| `recording-r3:419` | LOG | recording-r3:457 | none | none | part | `aStartLogsEachPromptsAnswerAndASecondPressWhileOneIsUp` and `aSettingsPromptLogsItsAnswerOrWhyItWaits` |
| `recording-r3:436` | LOG | recording-r3:482 | EXTRAS | none | deferred | none this phase |
| `recording-r4:192` | LOG | recording-r4:193 | URLLOG | none | part | `aSecondURLStartBeforeTheFirstTakesTheLockIsLogged` |
| `recording-r4:214` | LOG | recording-r4:218 | none | none | part | `aSettingsPromptLogsItsAnswerOrWhyItWaits` |
| `recording-r4:217` | LOG | recording-r4:221 | none | earlier mark, extended | deferred | none this phase |
| `recording-r4:347` | LOG | recording-r4:422 | none | none | full | `stopRecordingLogsWhatItDidInEachPhase` |
| `recording-r4:366` | LOG | recording-r4:456 | none | none | full | `aSecondURLStartBeforeTheFirstTakesTheLockIsLogged` |

## CLOP: the Clop optimiser and the running check (seams.md section 5)

### `phase-7-clop:21` (line 23)

> The toggle takes effect without Save: turn it on, close Settings with no Save, and `defaults read io.tky.tidyshot optimiseWithClop` reads `1`; the next upload is optimised. Turn it off again and the next upload is not.

- Seams: None.
- Current mark: none
- This phase: part (Settings close, `defaults read`). T1 `turningClopOffDuringAnOptimisationKeepsThatUploadOptimisedAndNotTheNext` (CoordinatorClopTests).
- Stays: closing Settings without Save, `defaults read` of the real domain: by hand (C)

### `phase-7-clop:28` (line 30)

> Editor Upload (same link), the same-key replace, Upload as New and Retry of a failed upload (turn the network off, capture, turn it on, Retry) are each optimised: each object is smaller than the file the editor saved or the capture was.

- Seams: EDITOR, for the editor-driven half. EDITOR landed in CT-2: FakeEditor.upload calls actions.upload (TidyShotTests/Support/EditorFakes.swift:143), which reaches the private editorUpload (AppCoordinator+Editor.swift:311). The seam note had startUpload(fixedKey:) stand in for it before EDITOR existed.
- Current mark: none
- This phase: full. T17 `anEditorUploadAndUploadAsNewEachSendClopsBytesAndTheLinkKeepsItsKey`; Retry leg: T1 (CoordinatorEditorUploadTests; CoordinatorClopTests).
- Stays: real Clop making each smaller is line 26 (C), not this line

### `phase-7-clop:29` (line 31)

> Upload-only mode (After capture: `Upload only, keep no local file`): the object is optimised; while it uploads `pending/<id>.png` in the container is full size, and after a failed upload (network off) the kept file is still the captured size, not Clop's.

- Seams: None.
- Current mark: none
- This phase: full. T7 `aCaptureWhoseUploadFailsAfterClopKeepsItsPendingFileAtTheCapturedSize`; hold leg also T1 (CoordinatorClopTests).
- Stays: nothing the line checks.

### `phase-7-clop:31` (line 33)

> A capture that Clop cannot shrink (upload a plain white fill, or the same optimised file twice) uploads the original with `Clop: the result is not smaller, uploading the original` in the log and no error notification.

- Seams: None.
- Current mark: none
- This phase: full. T2 `aClopThatIsNotRunningOrSkipsUploadsTheOriginalWithOneLine(reason:line:)`, `.notSmaller` (CoordinatorClopTests).
- Stays: whether real Clop fails on a white fill: outside the claim

### `phase-7-clop:32` (line 34)

> A key template with `{counter}`: three captures in a row get counters in the order the uploads started (`defaults read io.tky.tidyshot captureCounter` advanced by 3), even when the second is a large scrolling capture that Clop takes seconds over.

- Seams: None.
- Current mark: none
- This phase: full. T6 `threeUploadsWithAnImageHeldInClopTakeCountersInStartOrder` (CoordinatorClopTests).
- Stays: nothing the line checks.

### `phase-7-clop:35` (line 37)

> Quit Clop, toggle on, capture: the original uploads, the log shows `Clop: Clop is not running, uploading the original`, no notification, and TidyShot does not launch Clop.

- Seams: None.
- Current mark: none
- This phase: full. T2, `.notRunning` (CoordinatorClopTests).
- Stays: nothing the line checks.

### `phase-7-clop:36` (line 38)

> Clop set to convert PNG to another format (Clop > Settings > Images): the original PNG uploads, with `Clop: Clop converted the file to another format, uploading the original`. Set it back.

- Seams: None.
- Current mark: none
- This phase: full. T2, `.converted` (CoordinatorClopTests).
- Stays: Clop's own setting: how to provoke it

### `phase-7-clop:37` (line 39)

> Free-tier Clop past its cap, if you can reach it: uploads still succeed, unoptimised, with a `Clop:` line.

- Seams: None.
- Current mark: none
- This phase: full. T2, `.failed("Clop's port is unavailable")` (CoordinatorClopTests).
- Stays: the real cap: C

### `phase-7-clop:41` (line 43)

> Delete while Clop is optimising a large scrolling capture: retry the 65,536 px capture from Recent Captures with Clop running, and choose Delete on its card during the first seconds, while it shows 0 %, then accept `Delete this capture?`. The capture leaves Recent Captures and nothing uploads afterwards (check the bucket after a minute: no new object for it).

- Seams: None.
- Current mark: none
- This phase: full. T8 `deletingAnImageWhileClopHoldsItCancelsAtOnceAndNothingUploads` (CoordinatorClopTests).
- Stays: none; the hold stands for the 65,536 px capture

### `phase-7-clop:42` (line 44)

> The same Delete where the record is kept: make the file removal fail (change the save folder in Settings > General so the capture's file lies outside it), start the retry, Delete during the first seconds, and decline the second alert. The card reads `Upload cancelled.`; Retry then uploads once, with one new object in the bucket, not two. Then Delete again and accept the second alert's Remove.

- Seams: None.
- Current mark: none
- This phase: full. T9 `aDeleteDeclinedAtTheSecondAlertWhileClopHoldsLeavesTheCardCancelledAndARetryUploadsOnce` (CoordinatorClopTests).
- Stays: none; the save-folder change is the manual stand-in

### `phase-7-clop:43` (line 45)

> With the file removal made to fail as above, Delete, decline the second alert, then Retry before Clop's first call returns (a 65,536 px capture gives you seconds): exactly one object is uploaded, and it comes from the second attempt (its key is the new one; the first attempt's bytes never reach the bucket).

- Seams: None.
- Current mark: none
- This phase: full. T10 `aRetryBeforeClopsFirstAnswerUploadsOnceFromTheSecondAttempt` (CoordinatorClopTests).
- Stays: nothing the line checks.

### `phase-7-clop:44` (line 46)

> Change upload settings during optimisation: start the 65,536 px upload with Clop running, and in Settings > Upload change the bucket (or the key template) and Save while the card shows 0 %. The first upload completes against the destination it started with, and its URL is copied; a capture taken afterwards goes to the new destination. Nothing hangs and no job is dropped.

- Seams: None.
- Current mark: none
- This phase: full. T4 `changingUploadSettingsWhileClopHoldsAnUploadFinishesItAtItsOwnDestination` (CoordinatorClopTests).
- Stays: none; the tab's Save is `destinationDidChange()`

### `phase-7-clop:45` (line 47)

> Toggle the setting off while an optimisation runs: the running upload still completes optimised; the next one is not.

- Seams: None.
- Current mark: none
- This phase: full. T1 (CoordinatorClopTests).
- Stays: nothing the line checks.

### `recording-r1:271` (line 285)

> Delete (and confirm) during the upload cancels it and removes the file, the record and any object already uploaded. Delete during `Optimizing…` cancels at once, and `tmp/Clop` is empty afterwards.

- Seams: None.
- Current mark: none
- This phase: full. T3 `deletingARecordingWhileClopHoldsItCancelsAtOnceAndLeavesNoMovieOrCounterGap`; sentence 1 already D (CoordinatorClopTests; CoordinatorDeleteTests).
- Stays: nothing the line checks.

### `recording-r1:296` (line 328)

> Cleanup. `ls $C/tmp/Clop` is empty after an optimised upload, after a failed upload (Wi-Fi off, wait for `Failed`), and after a Delete during optimisation. A Retry runs Clop again from the original.

- Seams: TMPDIRS, per the catalogue and the multi-seam list (CLOP + TMPDIRS): the catalogue puts ClopApp.workDirectory (a static, ClopOptimiser.swift:272) among the tmp/ directory statics. In the code it is read at AppCoordinator.swift:298 (start() removes it at launch) and as the default for ClopApp.makeOptimiser (ClopOptimiser.swift:279); nothing else reads it.
- Current mark: none
- This phase: part (`TMPDIRS`: the container's real folder, the launch sweep). T3 (Delete leg), T11 `aFailedRecordingUploadAfterClopLeavesNoMovieAndARetryAsksClopAgainFromTheOriginal` (CoordinatorClopTests).
- Stays: the container's `tmp/Clop` and the launch sweep (AppCoordinator.swift:298): `TMPDIRS`

### `recording-r1:297` (line 329)

> Clop off: the original uploads and the card never says `Optimizing…`. Clop not running (quit it): the original uploads, TidyShot does not launch Clop, and the `Clop:` line reads `Clop: Clop is not running, uploading the original`.

- Seams: None.
- Current mark: none
- This phase: full. T12 `aRecordingUploadsItsOriginalWithoutOptimizingWhenClopIsOffOrNotRunning(setting:running:)` (CoordinatorClopTests).
- Stays: nothing the line checks.

### `recording-r1:330` (line 376)

> 3. Counter: for a recording's upload, `{counter}` is drawn after the 625 GB check (R4; was 5 GiB), just before the enqueue. With `{counter}` in the key template, two recordings uploaded in a row get consecutive keys, and a recording deleted during `Optimizing…` leaves no gap (a refused upload would not either; that cannot be reached by hand). ______

- Seams: None.
- Current mark: none
- This phase: full. T3 (no gap, consecutive keys) (CoordinatorClopTests).
- Stays: nothing the line checks.

### `recording-r2:275` (line 291)

> Clop on and running, then a GIF: it uploads as made. The card never says `Optimizing…`; the uploaded object is byte-identical to the saved file (`curl -s -o $W/up.gif "<url>"; cmp $W/up.gif "<saved .gif>"`); and `grep 'Clop: GIFs are not sent to Clop' ~/Desktop/rec-r2/tidyshot.err` finds one line, and still one after a second GIF upload in the same launch; after a relaunch, one more. An MP4 recording still goes through Clop (`Optimizing…`, a smaller object). With Clop off the GIF line is never logged.

- Seams: None.
- Current mark: none
- This phase: part (`cmp` against the bucket, `grep` of the real stderr). T13 `aGIFUploadsAsMadeWithOneClopLinePerLaunch`, T14 `anMP4RecordingGoesThroughClopShowingOptimizingAndUploadsClopsMovie` (CoordinatorClopTests).
- Stays: `cmp` against the bucket, `grep` of the real stderr: by hand

### `recording-r4:253` (line 267)

> Clop on, `Upload Trimmed` on a trimmed file over 100 MiB, fail it (Wi-Fi off for two minutes), trim again, then `Upload Trimmed`: the log shows `source changed, starting again` and the link plays the second trim, not the first.

- Seams: None.
- Current mark: (suite, in part: CoordinatorUploadTests.anOutdatedKeptClopCopyCountsAsAChangedSource)
- This phase: part (the link playing the second trim). T16 `anUploadTrimmedWithClopWhoseFileChangedAsksClopAgainAndSendsTheSecondTrim` (CoordinatorTrimTests).
- Stays: the link playing the second trim: CloudFront, by hand
- Mark: extends the earlier mark (see `tests-small.md`, the seam's marks section).

### `recording-r4:255` (line 269)

> A Clop result kept in `multipart/<id>.mp4` is used by Retry (no second Clop run, `resumes at`) and is gone after the upload. A Clop copy that could not be kept logs `Clop's copy could not be kept for resume: <error>` and the job sends from the throwaway copy.

- Seams: None.
- Current mark: (suite, in part: CoordinatorUploadTests.anUploadedResumeClearsItsStateSidecarAndKeptCopy)
- This phase: full. T5 `aRecordingOverThePartThresholdKeepsClopsMovieAndARetryResumesWithoutClop`; T15 `aClopMovieThatCannotBeKeptForResumeLogsItAndSendsTheThrowawayCopy` (CoordinatorClopTests).
- Stays: nothing the line checks.
- Mark: extends the earlier mark (see `tests-small.md`, the seam's marks section).

### `recording-r4:323` (line 372)

> 16. Clop's result is kept in `multipart/<id>.mp4`, and a Retry whose source still matches resumes from it without Clop. ______

- Seams: None.
- Current mark: none
- This phase: full. T5 (CoordinatorClopTests).
- Stays: nothing the line checks.

### `small-tweaks:14` (line 17)

> Upload a capture with Clop on: after the upload, the row shows the smaller, optimised size.

- Seams: None.
- Current mark: none
- This phase: full. T1 (CoordinatorClopTests).
- Stays: nothing the line checks.

### `small-tweaks:15` (line 18)

> A recording row shows its size after it saves, and the optimised size after an upload with Clop on.

- Seams: None.
- Current mark: none
- This phase: full. T14 (optimised size), T5 (kept variant); save half T18 `anMP4sSizeIsTheMovedFilesSize` (CoordinatorClopTests; CoordinatorSaveTests); the row's text from the size, `RecentCaptureFormattingTests.detailIsTheTimeAndTheSize` (existing).
- Stays: nothing the line checks.

## SAVEAS: the card's Save As… panel (section 6)

### `coordinator-split:44` (line 48)

> Pin, then the pin menu's three items [`+Pins`, `+RecordActions`]. Capture an area and click the card's pin (`Pin to screen`): a pin opens over the spot the area came from. Click the card's pin again: the same pin comes forward and no second one opens. The menu now has `Close Pinned Screenshots`. Right-click the pin: `Copy Image` puts the image on the clipboard and posts `Image copied`; `Save As…` opens a panel that suggests the capture's own name (Cancel it); `Annotate` opens the editor. Choose `Close Pinned Screenshots`: the pin closes and the menu item goes.

- Seams: PINS (PinController is concrete; pinActions is private, AppCoordinator+Pins.swift), SCREENS (pinScreen reads NSScreen.screens, AppCoordinator.swift:58) and EDITOR (the pin menu's Annotate; landed in CT-2).
- Current mark: (suite, in part: CoordinatorEditorTests.annotateFromACardOrRecentCapturesLeavesNothingToRestore, CoordinatorRecordActionsTests.copyImageReadsTheFileOrDownloadsTheObject; by hand: the pin, its second click and `Close Pinned Screenshots` (`PINS`, `SCREENS`), and the pin's Save As… panel (`SAVEAS`); the pin menu's Annotate is the card's `openEditorAfterMenuTracking`)
- This phase: part (extends CT-2 mark). 1 `saveAsOfASavedImageCopiesItsBytesAndChangesNothingElse` (CoordinatorSaveAsTests).
- Stays: the pin over the spot, the second click, `Close Pinned Screenshots`, reaching the item through the pin's menu: `PINS`, `SCREENS`
- Mark: extends the CT-2 mark with the tests above; `SAVEAS` leaves its by-hand list.

### `phase-6a:170` (line 189)

> Save to the Desktop: `shasum -a 256` of the copy equals that of the original (no re-encode); `Saved` with the copy's name is posted (when notifications are on; nothing is posted when they are off, and the file is still written), and a click on it reveals the copy. Pick the original file instead and confirm Replace: the file is unchanged byte for byte.

- Seams: None.
- Current mark: none
- This phase: part. 1 (CoordinatorSaveAsTests).
- Stays: the click on `Saved` revealing the copy (the notifier's) and the panel's Replace prompt (AppKit): by hand, no seam

### `phase-6a:171` (line 190)

> For an upload-only capture the suggestion is the file name template's name with the current counter (none is drawn), in the save folder when one is set, otherwise where the panel last was. While `Uploading…` shows, the copy equals the pending file (`pending/<id>.png`); after a failed upload (`Retry  Save As…`) it writes the pending file too.

- Seams: None.
- Current mark: none
- This phase: part. 2 `anUploadOnlyCapturesSaveAsSuggestsTheTemplateNameAndCopiesItsPendingFile` (CoordinatorSaveAsTests).
- Stays: "where the panel last was": the panel's, by hand

### `phase-6a:172` (line 191)

> After the upload, on a card that showed through it: the panel opens, and the copy is written from the card's kept drag copy, with no `Downloading` notification; it equals `curl -s <url> | shasum -a 256`. On a restored upload-only card before its quiet download has landed (Network Link Conditioner on a slow profile): the panel opens first, then after Save `Saving a copy…` with `Downloading <key>` is posted while the download runs, then `Saved`. With Wi-Fi off the failure is posted as `Not saved` and nothing crashes.

- Seams: None, as a seam. The catalogue also names a harness gap that is not a seam: FakeDestination.download(key:) cannot throw yet (effort M).
- Current mark: none
- This phase: part. 3 `anUploadOnlyCardsSaveAsWritesTheDragCopyOrDownloadsAfterThePanel` (CoordinatorSaveAsTests).
- Stays: the restore itself (`SCREENS`); `curl` and the slow profile by hand

### `phase-6a:174` (line 193)

> Save As… changes nothing about the capture: the card, its link, Recent Captures, `history.json`, Reveal Last Capture and the clipboard are as before.

- Seams: None.
- Current mark: none
- This phase: full. 1 (CoordinatorSaveAsTests).
- Stays: nothing the line checks.

### `phase-6a:175` (line 194)

> Open the panel and wait for the card's auto-close to run out: the panel keeps working and saves the capture.

- Seams: None.
- Current mark: none
- This phase: part. 5 `aSaveAsPanelHeldThroughTheCardsAutoCloseStillSaves` (CoordinatorSaveAsTests).
- Stays: the card's real timer (`QuickAccessController.scheduleClose`), which `FakeCards.close` stands for: by hand, no seam

### `phase-6a:176` (line 195)

> Use Save As… from the button and from the context menu, from a restored card, and from a card in the middle of the stack: each saves that card's capture.

- Seams: None.
- Current mark: none
- This phase: part. 6 `saveAsFromAnyCardWritesThatCardsCapture` (CoordinatorSaveAsTests).
- Stays: the restore (`SCREENS`); button vs menu both `model.onSaveAs()` (QuickAccessView.swift:101, :138): by eye

### `phase-6a:198` (line 220)

> Upload only, after the upload: the card is still on screen, and dragging it still works, from a file in the `Drag` folder that took the place of the pending file. `history.json` shows the record as before (no `fileURL`), and Recent Captures shows no local file. Copy Image, Save As… and Annotate on that card need no download (no `Downloading` notification). 60 seconds after the card closes `ls ~/Library/Containers/io.tky.tidyshot/Data/tmp/Drag` no longer lists the record's folder (Slack may still read the file in those seconds).

- Seams: EDITOR (landed in CT-2; the mark already cites its tests).
- Current mark: (suite, in part: CoordinatorEditorTests.anUploadedUploadOnlyCardsCopyImageAndAnnotateReadTheDragCopy, CoordinatorUploadTests.anUploadedUploadOnlyImageMovesToItsDragFolderOnlyWithACard; by hand: the card's Save As… panel (`SAVEAS`), and Slack reading the file)
- This phase: part (extends CT-2 mark). 3 (its first part) (CoordinatorSaveAsTests).
- Stays: Slack reading the file in that minute: by hand
- Mark: extends the CT-2 mark with the tests above; `SAVEAS` leaves its by-hand list.

### `phase-6a:199` (line 224)

> An edited capture's drag copy is replaced. Upload-only mode, wait for the upload (the card shows `URL copied` and a drag file is kept), then press Annotate, draw an arrow, and save the edit (⌘S, or ⌘U to upload it): the capture's `Drag/<record id>` folder is gone at once. Then, from the card or Recent Captures: Copy Image, Save As… and Annotate show the edited image (arrow included), never the one before the edit; a drag started after the edit (press on the card, which stages the edit again) drops the edited image. Do the same with "Save and copy image" and an edit saved over the file: the dragged file has the arrow too.

- Seams: EDITOR (landed in CT-2; the mark already cites its tests).
- Current mark: (suite, in part: CoordinatorEditorSaveTests.saveOverTheFileRemovesTheDragCopyAndEveryReadGivesTheEdit, CoordinatorEditorUploadTests.uploadOfAnUploadOnlyCaptureRemovesItsDragCopyAndEveryReadGivesTheEdit; by hand: the card's Save As… panel (`SAVEAS`), and the drop; the line's "from the card" cannot happen after an Annotate, which closes the card for good, and in upload-only mode ⌘S is Save As…, so the tests read through Recent Captures and remove the drag copy with ⌘U there and ⌘S over a saved file)
- This phase: part (extends CT-2 mark). 9 `saveAsAfterASaveOverTheFileWritesTheEditNotTheOriginal`, 10 `saveAsAfterAnEditorUploadOfAnUploadOnlyCaptureWritesTheEditDuringAndAfterThePut` (CoordinatorEditorSaveTests, CoordinatorEditorUploadTests).
- Stays: the drop: by hand; reaching Save As… after the edit, which only a pin offers (Recent Captures has none, RecentCapturesMenu.swift:110-121): `PINS`
- Mark: extends the CT-2 mark with the tests above; `SAVEAS` leaves its by-hand list.

### `recording-r1:313` (line 353)

> Restoring an uploaded upload-only video's card after its drag folder is gone (wait a minute past the card closing, or delete `tmp/Drag`) starts no download (check Activity Monitor/Network for a transfer). R4 changed the rest (was: the card cannot be dragged): a drag from that card downloads the file first (see `recording-r4-manual-checklist.md`). Save As… on that card downloads to the file you choose.

- Seams: SCREENS: restoreClosedOverlay reads overlayScreen (NSScreen, AppCoordinator+Overlay.swift:55), needed for the first half (restore starts no download).
- Current mark: none
- This phase: part. 7 `anUploadOnlyVideosSaveAsDownloadsToTheChosenFile` (CoordinatorSaveAsTests).
- Stays: the restore starting no download (`SCREENS`); a drag downloading first is D (`CoordinatorDragOutTests`)

### `recording-r1:340` (line 397)

> A screenshot's save, upload, Retry, Delete, Save As… and Copy Image are as before; a PNG still gets `.png` and `image/png`.

- Seams: None.
- Current mark: none
- This phase: full. 1 (Save As…); the other verbs are existing tests, section 4 (CoordinatorSaveAsTests).
- Stays: none for Save As…

### `recording-r2:264` (line 278)

> A GIF's card and row. The card has the poster with a `GIF` badge and the duration; its menu and the row show no Annotate, Pin to Screen or Copy Image; they have `Copy File` (with a local file), `Save As…`, `Reveal in Finder`, `Close` and `Delete…`. A thumbnail click opens the GIF in the default app and it plays. `Save As…` offers `com.compuserve.gif` and writes a `.gif` (over an existing file too, and on `/Volumes/RecOff`). A card press for a drag stages the `.gif` and downloads nothing. The hover preview in Recent Captures shows the stored thumbnail at its own size. Drag the card into Finder and Slack: the `.gif` arrives under its name.

- Seams: WORKSPACE: the thumbnail click opens the GIF in the default app (openCapture, AppCoordinator+RecordActions.swift:51-71, NSWorkspace).
- Current mark: none
- This phase: part. 8 `aGIFsSaveAsWritesTheGIFOverAnExistingFileToo` (CoordinatorSaveAsTests).
- Stays: the thumbnail click (`WORKSPACE`); `/Volumes/RecOff`, the hover preview, dragging into Finder and Slack: by hand. `com.compuserve.gif` is D (`EditorNamingTests.aGIFPanelAllowsGIFOnly`); the menu contents D; the press staging the `.gif` is A

### `recording-r2:670` (line 750)

> A screenshot's save, upload, Retry, Delete, Save As… and Copy Image are as before; a PNG still gets `.png` and `image/png`.

- Seams: None.
- Current mark: none
- This phase: full. 1; as recording-r1:340 (CoordinatorSaveAsTests).
- Stays: none for Save As…

### `recording-r4:277` (line 294)

> Save As… during the download waits and then saves the landed file (one GET in the log, not two).

- Seams: None.
- Current mark: none
- This phase: full. 4 `aRecordingsSaveAsDuringItsDragOutDownloadWaitsAndCopiesTheLandedFile` (CoordinatorSaveAsTests).
- Stays: "in the log" is the app's GET count; the fake's stands for it

## LOG: the `RecordingLog.note` sink (section 8)

### `coordinator-harness:27` (line 27)

> 4. `stop-recording`'s log lines in each phase (R4 checklist :178-186) read as they did: the suite pins the state, not the `RecordingLog` text, and tests 48 and 50 cannot tell the coordinator's own do-nothing branches from the recorder's (plan D24), so the `did nothing` lines are the check.

- Seams: None.
- Current mark: none
- This phase: full. `stopRecordingLogsWhatItDidInEachPhase` (CoordinatorRecordingTests).
- Stays: nothing

### `recording-r1:263` (line 277)

> A leftover that does not play (`echo junk > "$C/tmp/Recording/x.mp4"`, then relaunch) is removed with `Recording: x.mp4 could not be played, removed`.

- Seams: None in the seam list (counted as alone), but the call is outside the coordinator: RecordingRecovery.scan (TidyShot/Recording/RecordingRecovery.swift:34, :36), reached through RecordingRecovery.begin (called at AppCoordinator.swift:321). It needs the sink threaded into RecordingRecovery, the M part of the seam.
- Current mark: none
- This phase: full. `aLeftoverThatDoesNotPlayIsRemovedAndLogged` (RecordingRecoveryTests).
- Stays: nothing checked; that `start()` hands `scan` the environment's sink is read from the code, since `start()` is not driven (`TMPDIRS`, `LAUNCH`)

### `recording-r3:156` (line 161)

> With the camera prompt up: a second Record press does nothing and logs `Recording: start ignored, the camera prompt is open`. A start refused by the lock after its prompt cannot be forced by hand (`ShortcutsTests` pin its notice and rule).

- Seams: None.
- Current mark: none
- This phase: full. `aStartLogsEachPromptsAnswerAndASecondPressWhileOneIsUp` (CoordinatorRecordingTests).
- Stays: nothing; the lock refusal after a prompt the line leaves to `ShortcutsTests`

### `recording-r3:162` (line 167)

> The microphone pick during a recording behaves as the bubble toggle does: no prompt, `Recording: microphone prompt from Settings deferred, a capture is running` in the log.

- Seams: None.
- Current mark: none
- This phase: part. `aSettingsPromptLogsItsAnswerOrWhyItWaits` (CoordinatorRecordingTests).
- Stays: the microphone pick in Settings reaching the coordinator (CaptureSettingsView.swift:213-224, a view's call on `AppCoordinator.shared`): by hand, no seam

### `recording-r3:416` (line 452)

> 7. The recording's clock times the camera's log lines and the loss note. ______

- Seams: EXTRAS: the camera lines come from RecordingExtras (RecordingExtras.swift:221 `camera lost at`, :235 `camera back at`), which builds a real CameraSession and orders real windows front (RecordingExtras.swift:86-115, :196); the factories seam (EXTRAS) is needed to feed .lost/.back reports. LOG for those lines also needs the sink threaded through RecordingExtras.init (the M part).
- Current mark: none
- This phase: deferred. none this phase (`EXTRAS`).
- Stays: `EXTRAS` (a fake session's `.lost`/`.back`, RecordingExtras.swift:221, :235), with the sink through `RecordingExtras.init` that `EXTRAS` adds

### `recording-r3:419` (line 457)

> 9. The prompts' order and log lines are as the Camera prompt section says. ______

- Seams: None.
- Current mark: none
- This phase: part. `aStartLogsEachPromptsAnswerAndASecondPressWhileOneIsUp` and `aSettingsPromptLogsItsAnswerOrWhyItWaits` (CoordinatorRecordingTests).
- Stays: `URLLOG`: the section's `URL command from … dropped, the camera prompt is open` line (URLCommandHandler.swift:155, `NSLog`); the prompt on screen: by hand

### `recording-r3:436` (line 482)

> D. `Recording: camera could not be started: <reason>` is logged, a line the design's list does not have (Task 12). ______

- Seams: EXTRAS: the line comes from RecordingExtras.received on a .couldNotStart(reason) report (RecordingExtras.swift:215); EXTRAS supplies the fake session, and LOG must be threaded through RecordingExtras.init.
- Current mark: none
- This phase: deferred. none this phase (`EXTRAS`).
- Stays: `EXTRAS` (a fake session's `.couldNotStart`, RecordingExtras.swift:215)

### `recording-r4:192` (line 193)

> Two `record-screen` URLs back to back (one Keyboard Maestro macro): one selection, no notice, and the second is logged (`Recording: URL start ignored, a recording is starting` or the handler's `dropped` line).

- Seams: URLLOG: the handler's own `dropped` NSLog (URLCommandHandler) is a separate closure; the line accepts either text.
- Current mark: none
- This phase: part. `aSecondURLStartBeforeTheFirstTakesTheLockIsLogged` (CoordinatorRecordingTests).
- Stays: the one selection on screen, the drawn UI, by hand; it joins no seam (spec call 11)

### `recording-r4:214` (line 218)

> Turn `Show webcam bubble` on in Settings while a GIF converts (the camera access undecided; reset with `tccutil reset Camera io.tky.tidyshot`, Tim's): the log says `Recording: camera prompt from Settings deferred, a recording is being saved`. During a recording it still says `… a capture is running`.

- Seams: None.
- Current mark: none
- This phase: part. `aSettingsPromptLogsItsAnswerOrWhyItWaits` (CoordinatorRecordingTests).
- Stays: the `Show webcam bubble` toggle in Settings reaching the coordinator (CaptureSettingsView.swift:248-256): by hand; the GIF conversion is set-up (`.saving` is set directly)

### `recording-r4:217` (line 221)

> The record shortcut during the settle delay with `Count down before recording` off records nothing and logs `Recording: not started, the count-in was cancelled`.

- Seams: None.
- Current mark: (suite, the rule: CoordinatorRecordingTests.recordingProceedsOnlyWhenStartedNotQuittingAndNotCancelled)
- This phase: deferred. none this phase (`TMPDIRS`, `CAPSRC`).
- Stays: the line is in private `record()` (+Recording.swift:411), past `recordingCanStart` (`Recording.makeDirectory()`, the live `tmp/Recording`: `TMPDIRS`) and `loadContent`/`selector.select` (`CAPSRC`); the sink is in place for it. Its mark (the rule) stays
- Mark: extends the earlier mark (see `tests-small.md`, the seam's marks section).

### `recording-r4:347` (line 422)

> 5. `RecordingController.isEnding`, so a second `stop-recording` during the stop wait logs `did nothing`. Check: U1's second stop. ______

- Seams: None.
- Current mark: none
- This phase: full. `stopRecordingLogsWhatItDidInEachPhase` (CoordinatorRecordingTests).
- Stays: nothing

### `recording-r4:366` (line 456)

> 18. `urlRecordingStartPending` makes a second `record-screen` handled before the first has taken the lock a logged drop. Check: U1's back-to-back step. ______

- Seams: None.
- Current mark: none
- This phase: full. `aSecondURLStartBeforeTheFirstTakesTheLockIsLogged` (CoordinatorRecordingTests).
- Stays: nothing
