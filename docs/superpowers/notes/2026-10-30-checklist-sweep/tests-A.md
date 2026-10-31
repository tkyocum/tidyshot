# Tests for the A lines (coverable now, no seam)

Source: `catalogue.json`, the 159 lines with category A, less the 15 this document and the reconciliation
move out of A and plus the 4 they move in (see "Reclassified" at the end): 148 A lines. Each test below names
its suite file, its entry point, the fakes that observe it, what it asserts, its effort and every checklist
line it covers. Lines are
`<checklist>:<line>`, where `<checklist>` is `docs/testing/<checklist>-manual-checklist.md`.

## How the paths were checked

Each entry point was opened and followed to its ends. A coordinator path counts as A when it reaches only
the `CoordinatorWorld` members (history and its folders, `settings`, `saveLocation`, the credential store,
`FakeNotifier`, `FakeCards`, `FakeClipboard`, `FakeConfirm`, the destination factory, the clock, the date,
`freeBytes`, the log) plus what the harness design already accepts: the `ProcessInfo` activity of a
recording upload and `RecordingLog.note` lines that are not read. A view or model path counts as A when it
builds its own objects, as the existing non-harness suites already do. A window or panel the test builds
and never orders front counts (`SelectionViewArmingTests`, `SelfTimerTests` and `ClickRingOverlayTests` do
this today). A path that reads `NSScreen.screens`, registers with `NSWorkspace`, uses the `tmp/` directory
statics or reaches a Deferred seam does not count, and its line is in "Reclassified" at the end.

Points that hold for many tests:

- `CaptureIntent.standard` reads `AppSettings.shared`. Every coordinator test passes an explicit
  `CaptureIntent(action:)`.
- The coordinator's `HistoryStore` is built without `environment.now` (AppCoordinator.swift init), so
  retention prunes against the real `Date()`. Old records need timestamps relative to `Date()`, not to
  `world.date`.
- Save-folder cases store a temp folder with `world.saveLocation.store(_:)`, the way
  `SaveLocationStoreTests` does. No coordinator test does this yet (harness built note D25), so the first
  test to do it is rated at least M.
- `optimiseWithClop` defaults to off in the world's defaults suite. No test here turns it on, so no path
  reaches `ClopApp.runningBundleID()` or `clopOptimiser`.
- `saveRecording` decrements `recordingSavesInFlight` on every return. Set it to 1 before each call.
- A `CanvasView` with no window snaps its transform with `NSScreen.main?.backingScaleFactor ?? 2`
  (CanvasView.swift:103), as `CanvasFitTests` already does. Assert relations (shown against fit, before
  against after), not exact transform values.
- Fake extensions, not seams: a throw script on `FakeDestination.download(key:)`, a failure script on
  `FakeDestination.delete(key:)`, a subtitle in `FakeNotifier.Call`, and a digest of each part's bytes in
  `FakeDestination`. Each test that needs one says so and is rated M.

## AppSettingsTests.swift (existing)

### `aSecondInstanceKeepsTheSaveFolderAndContinuesTheCounter` (S)
- Entry: `SaveLocation.init(defaults:)` (SaveLocation.swift:18, resolves the bookmark) and
  `AppSettings.nextCounter()` (AppSettings.swift:466), each built twice over one defaults suite.
- Asserts: after `store(tempFolder)` a second `SaveLocation` has `currentURL == tempFolder`; after two
  `nextCounter()` draws a second `AppSettings` draws the next value.
- Covers: phase-1:41 (relaunch keeps the folder and the counter).

### `recordingDefaultsAreRegisteredNotWritten` (S)
- Entry: `AppSettings(defaults:)` over a fresh suite (`register(defaults:)`, AppSettings.swift:266).
- Asserts: `defaults.persistentDomain(forName:)` holds none of `recordingFrameRate`, `recordingFormat`,
  `gifFrameRate`, `gifMaxSide`, `recordingWebcamBubble`, while each getter still reads its default.
- Covers: recording-r1:86 (R1 keys registered, not written), recording-r2:157 (R2 keys), recording-r3:110
  (R3 keys).

## CanvasAccessibilityTests.swift (existing)

These three build a `CanvasView` over an `EditorModel` with `FakeTileRenderer` (the `CanvasFitTests.makeCanvas`
setup), with no window.

### `canvasElementsFollowMovesResizesDeletesAndAdds` (S)
- Entry: `CanvasView.accessibilityChildren()` (CanvasView.swift:461) after `model.commit` of a move, a resize,
  a delete and a new annotation.
- Asserts: an element is reused by id across a move and a resize, none is left for the deleted id, and the
  new one sits at its painting-order index.
- Covers: phase-4b:128 (elements follow at once, none stale).

### `anAccessibilityPressSelectsAndTheCanvasActsOnTheSelection` (S)
- Entry: `AnnotationAccessibilityElement.accessibilityPerformPress()` into `CanvasView.selectFromAccessibility`
  (CanvasView.swift:494), then `deleteBackward(_:)`, `moveLeft(_:)`, `copy(_:)` with a recording
  `EditorObjectClipboard`, and `duplicate(_:)`.
- Asserts: the press returns true and sets `model.selection`; `accessibilitySelectedChildren()` and the
  element's `isAccessibilitySelected()` follow it, and move when another is selected; each action then
  acts on that annotation (removed, moved 1 px, one clip written, one copy made).
- Covers: phase-4b:129 (selected state reported), phase-4b:131 (VO-Space then Delete, arrows, ⌘C, ⌘D),
  phase-4c:209, in part (AXPress selects; the rest is in the next test and in the existing
  `cropHidesAnnotationsOutsideIt`).

### `anAccessibilityPressIsRefusedWithTheCropToolOrDuringADrag` (S)
- Entry: as above, with `model.tool = .crop`, and again after a synthesized `mouseDown` (sets
  `isTrackingMouse`).
- Asserts: `accessibilityPerformPress()` returns false and `model.selection` is unchanged in both cases.
- Covers: phase-4b:130, in part (no selection under Crop). The listing, the numbering among the listed ones
  and the full list after the crop is undone are already pinned by the existing
  `CanvasAccessibilityTests.cropHidesAnnotationsOutsideIt`, so the line's mark names both tests. What no test
  reads is the list while the Crop tool is open over an applied crop (obsolete-E's corrected text for this
  line); that stays by hand. phase-4c:209, in part (not while a drag runs or Crop is active). The line's
  second sentence is `cropHidesAnnotationsOutsideIt`, which reads `CanvasAccessibility.items`; the canvas
  view's own list with a crop and VoiceOver itself stay by hand.

## CanvasFitTests.swift (existing)

### `aSpaceDragStopsTheFitOnResizeAndFitToViewBringsItBack` (S)
- Entry: `CanvasView.keyDown` with a Space event, `mouseDown`/`mouseDragged`/`mouseUp` (CanvasView.swift:185-246),
  then the existing `afterResize` helper and `fitToView()` (:118).
- Asserts: after the Space-drag the shown transform differs from the fit after a resize; `fitToView()` makes
  them equal again.
- Covers: phase-4b:101 (Space-drag ends the fit, ⌘0 fits again).

### `theFitFramesTheBackgroundsCanvasAndRefitsOnAnAspectChange` (M)
- Entry: `CanvasView.fitToView()`, `setFrameSize` and `zoom(to:)` over a model with `setBackground` (solid
  fill), then `model.backgroundDraft` with another `aspect` and `commitBackgroundDraft()`; the refit is the
  view's observation (CanvasView.swift:564-566), awaited with `eventually {}`.
- Asserts: at Fit the shown canvas is `shownBackground.canvasRect` fitted to the bounds and stays fitted
  after a resize; `zoom(to: 1 / model.scale)` shows natural size; an aspect change refits; with no
  background the fit is the one the bare capture gets, as before.
- Covers: phase-7c:144 (aspect change refits), phase-7c:157 (Fit, resize, actual size), phase-7c:199 (no
  background, no change in Fit).

### `aPointerOnTheCaptureMapsToItsPixelWithABackground` (S)
- Entry: `fitToView()` with a background on, then `model.transform.imagePoint(_:)` of the view point where the
  capture's origin is drawn (the conversion `input(for:)` uses, CanvasView.swift:268).
- Asserts: that view point maps to image (0, 0), not to a point offset by the padding.
- Covers: phase-7c:156 (annotations land where you point with a background).

## CanvasToolTests.swift (existing)

### `aSelectedTextMovesAndDeletesAndHasNoHandles` (S)
- Entry: `makeTool(for: .select)` driven over `FakeCanvasEditing` with a `TextBox` (the
  `moveCommitsOnceWithDelta` pattern), `EditorModel.deleteSelection()`, and `HitTester.handles(for:)`
  (HitTester.swift:28).
- Asserts: a drag commits one move by the delta; delete removes the text; `handles(for: .text)` is empty.
- Covers: phase-4b:61 (a text moves, deletes, no handles).

### `aCropDraftStopsAtTheTinyDragSize` (S)
- Entry: `CropTool` handle drag over `FakeCanvasEditing` (CropTool.swift:62, the `DragGeometry.isLargeEnough`
  guards at :85 and :88).
- Asserts: a drag that would shrink the draft below the tiny-drag size leaves the last draft rect.
- Covers: phase-4b:80 (a draft cannot be made smaller than the tiny-drag size).

## CanvasViewEventTests.swift (new)

Synthesized `NSEvent`s sent to a windowless `CanvasView` over an `EditorModel` with `FakeTileRenderer`
(the `CanvasFitTests.makeCanvas` setup). None of these paths beeps unless a test takes the failure branch.

### `aLetterPressedDuringADragKeepsTheTool` (S)
- Entry: `CanvasView.mouseDown` then `keyDown` with "e" (CanvasView.swift:283, the `guard !isTrackingMouse`).
- Asserts: `model.tool` is unchanged; after `mouseUp` the same letter picks Ellipse.
- Covers: phase-4b:30, in part (a letter mid-drag does nothing). The toolbar following the tool needs the
  editor window and is not covered.

### `reEditingATextPutsTheCaretAtTheEndInTheTextsFrame` (S)
- Entry: `model.beginTextEditing(at:existing:)` on a committed text, then the view's refresh into
  `installTextView` (CanvasView.swift:740), read off the `NSTextView` subview.
- Asserts: `selectedRange` is at the string's end; the view's frame is `TextLayout.frame` through the
  transform.
- Covers: phase-4b:56 (caret at the end, same position and size).

### `drawingUnderAnAppliedCropStopsAtItsEdge` (M)
- Entry: `mouseDown`/`mouseDragged`/`mouseUp` over a model with an applied crop (`input(for:)`, CanvasView.swift:266).
- Asserts: a Rectangle dragged from inside the crop out past it commits a rectangle ending on the crop's
  edge; a Text press outside the crop starts no `textEditing`.
- Covers: phase-4b:82 (input stops at the crop's edge).

### `anObjectCopiedInOneCanvasPastesIntoAnotherAtItsPointSize` (M)
- Entry: two canvases (scale 1 and scale 2) sharing one in-memory `EditorObjectClipboard`; `copy(_:)` on the
  first and `paste(_:)` on the second (CanvasView.swift:426-445).
- Asserts: for a text, a pencil stroke and a redaction, the pasted one is selected with the same string,
  colour and point size (`fontSize` scaled by the scale ratio); the first model is unchanged and only the
  second has `hasUnsavedChanges`.
- Covers: phase-4b:91 (copy and paste between two editors).

### `spacePansOnlyBetweenDragsAndNeverMovesACropDraft` (M)
- Entry: `keyDown`/`keyUp` with Space and mouse events (CanvasView.swift:185-246, :283, :317), and
  `endSpacePan()` (:331), which `windowDidResignKey` calls.
- Asserts: a Space during a Rectangle drag sets no pan, the drag commits, the next drag draws again; a Space
  key-up mid-pan keeps panning until `mouseUp`; after `endSpacePan()` a click reaches the tool; with the Crop
  tool and a pending draft a Space-drag pans and leaves `model.cropDraft` unchanged.
- Covers: phase-4b:99, in part (Space mid-drag, release mid-pan, resign key; the ⌘-Tab itself is the
  window's one-line delegate and stays by hand), phase-4b:100 (Space-drag with a crop pending).

## ClickRingOverlayTests.swift (existing)

### `theRingGrowsEasingOutAndFadesLinearly` (S)
- Entry: `ClickRingOverlay.apply(.begin)` and `apply(.end)` (ClickRingOverlay.swift:52) on a never-shown
  overlay, as the suite does.
- Asserts: the grow animation's `timingFunction == CAMediaTimingFunction(name: .easeOut)` (:65); the fade's
  parts have no timing function (linear).
- Covers: recording-r3:440 (call F, ease-out grow, linear fade).

## ConnectionTesterTests.swift (existing)

### extend `uploadFailedWhenPutIsRejected` (S)
- Entry: `ConnectionTester.run` over `StubSession`; `ConnectionTestResult.summary` (ConnectionTester.swift:20).
- Asserts: add `summary.hasPrefix("Upload failed: ")`; the readable case's exact text is already pinned.
- Covers: phase-3-1:63 (the two summaries).

## CoordinatorCaptureTests.swift (new)

### `aCaptureWhileTheLockIsHeldReturnsAtOnceAndPostsNothing(entry:)` (S)
- Entry: `captureArea`, `captureWindow` and `capturePreviousArea` (AppCoordinator+Capture.swift:15, :19, :146),
  each into `withCaptureLock` (AppCoordinator.swift:564), while a `TestGate` holds the lock through
  `withCaptureLock(coversDesktop: false)`, as `CoordinatorRecordingTests.aSettingsPromptAsksOnlyWhenNothingElseRuns` does.
- Fakes: `FakeNotifier`, `FakeCards`, `FakeClipboard`.
- Asserts: each call returns (gated with `TaskWatch` and `eventually`, since a lock that failed would reach
  `engine.shareableContent`), with no notifier call, no card and no copy.
- Covers: phase-1:25 (the shortcut while the overlay is up does nothing), phase-6a:215 (⌃⇧6 does nothing
  while a capture runs).

## CoordinatorDeleteTests.swift (existing)

### `deleteDuringAnUploadCancelsItThenDeletesTheReservedKey(onAReplacedLane:)` (M)
- Entry: `deleteCapture(recordID:)` (AppCoordinator+Delete.swift:15) on an upload-only pending image with a
  thumbnail, its upload started by `retryUpload` (+Upload.swift:462) over `blockingUploadsRemaining = 1`;
  with `true`, `destinationDidChange()` (+Upload.swift:78) first moves the lane to `drainingQueues`.
- Fakes: `FakeConfirm` answers `[false, true]`, `FakeDestination` (`attemptKeys`, `deletedKeys`), `FakeCards`,
  `FakeScrollClock`.
- Asserts: after No, `confirm.asked == [.delete(record)]`, the record and its upload stay (`uploadingIDs`
  holds it) and `cards.closes` is empty; after Yes, `deletedKeys == attemptKeys`, the record, pending file
  and thumbnail are gone, `cards.closes == [.deleted]`, `isUploading` is false; on the replaced lane
  `clock.run(until: { drainingQueues.isEmpty })` ends.
- Covers: coordinator-split:45 (delete during an upload), phase-3:38 (trash during an upload), phase-3:39
  (on the replaced queue), phase-3:41 (Cancel keeps everything and the card stays).

### `deleteRemovesTheObjectTheFileTheThumbnailAndTheRow(kind:)` (M)
- Entry: `deleteCapture(recordID:)` on an uploaded record whose file is in a stored temp save folder, with a
  thumbnail written by `coordinator.thumbnails.write`. Arguments: an image with Ask before deleting on, a
  video with it off, a GIF with it on.
- Fakes: `FakeConfirm` (Yes), `FakeDestination.deletedKeys`, `world.factory.askedLocations`, `FakeCards`.
- Asserts: `confirm.asked` is `[.delete(record)]` with the setting on and empty with it off;
  `deletedKeys == [key]`; `askedLocations == [record.objectLocation]`; the file, the thumbnail and the record
  are gone; `cards.closes == [.deleted]`.
- Covers: phase-3:40 (object, row, file and thumbnail gone), phase-5:181 (a stitched capture after one
  confirmation), recording-r1:309 (a video, as for a screenshot), recording-r2:676 (a GIF).

### `aFailedUploadOnlyCaptureIsDeletedWithOneQuestionAndNoDelete` (S)
- Entry: `deleteCapture(recordID:)` on `CoordinatorUploadTests.addPendingImage`'s failed record (no key) with a
  thumbnail.
- Asserts: `confirm.asked == [.delete(record)]`; `deletedKeys` and `askedConfigs` empty; the record, the
  thumbnail and `pending/<id>.png` gone.
- Covers: phase-3-1:50 (a failed upload-only capture's Delete).

### `aDeleteThatCannotReachStorageAsksToRemoveFromHistory(confirmFirst:)` (S)
- Entry: `deleteCapture(recordID:)` on `addUploadedImage`'s record after
  `world.credentials.delete(account: KeychainCredentialStore.defaultAccount)`; `deleteObjects` returns the
  no-credentials reason (+Delete.swift:120-122).
- Asserts: with Ask before deleting on, `confirm.asked == [.delete(record), .removeFromHistory(message:
  CaptureDeletion.storageFailureMessage(reason: "No credentials are saved in Settings > Upload."),
  informativeText: CaptureDeletion.storageFailureText)]`; with it off, only the second; Yes removes the record.
- Covers: phase-3-1:52 (Forget Credentials, then Delete), small-tweaks:9 (setting off: only the second alert).

### `aRemoteDeleteFailureDuringAnUploadKeepsTheRecordUntilRemoveFromHistory` (M)
- Entry: `deleteCapture(recordID:)` on an upload-only pending image whose PUT is held after HEAD
  (`blockingUploadsRemaining = 1`), so `cancelUpload` (+Upload.swift:564) leaves `pendingObjectKey`.
- Fake extension: a failure script on `FakeDestination.delete(key:)` (FakeDestination.swift:255 never throws).
- Asserts: first Delete with answers `[true, false]`: the second alert carries the DELETE's reason, the record
  reads `Upload cancelled.` with `pendingObjectKey` set and its pending file kept; a second Delete with
  `[true, true]`: the record, the thumbnail and the pending file go.
- Covers: phase-3-1:51 (delete fails mid-upload, Cancel keeps it, Remove clears it).

### `aPrePhase3UploadedCaptureIsDeletedWithNoStorageRequest` (M)
- Entry: `deleteCapture(recordID:)` (+Delete.swift:15) on an uploaded record with `objectLocation` nil (a
  capture uploaded before Phase 3) whose file is in a stored temp save folder, with Ask before deleting on
  and `FakeConfirm` answering Yes. `CaptureDeletion.objects(for:)` lists no object for a record without a
  location (CaptureDeletion.swift:55-59).
- Fakes: `FakeConfirm`, `FakeDestination.deletedKeys`, `world.factory.askedLocations`.
- Asserts: `confirm.asked == [.delete(record)]`; `askedLocations` and `deletedKeys` are empty, so no DELETE is
  sent and the object stays; the file and the record are gone.
- Covers: phase-3:26 (the coordinator half: Delete removes the row and the file and leaves the object). The
  alert text is the line's D half, marked in marks-D; the line's one mark names both tests.

### `aDeleteAfterABucketChangeDeletesWhereTheObjectWent` (S)
- Entry: `deleteCapture(recordID:)` on an uploaded record whose `objectLocation` is `location("old.tky.io")`,
  with `world.factory.add(old, at: location("old.tky.io"))` and the Upload settings left at `world.location`,
  Ask before deleting off. `deleteObjects` builds its destination from the group's location, not from the
  current settings (+Delete.swift:111-123); `eachUploadIsAbortedWhereItWasCreated` is the pattern.
- Asserts: `old`'s `deletedKeys == [key]`; the current destination's `deletedKeys` is empty;
  `world.factory.askedLocations == [location("old.tky.io")]`; the record is gone.
- Covers: phase-3:31 (after a bucket change, Delete removes the object from the bucket it went to).

### `deleteDuringAReplaceCancelsItAndDeletesTheLinksKey` (M)
- Entry: `startPlannedUpload(recordID:plan: .replace(key), ...)` (+Upload.swift:102) held by
  `blockingUploadsRemaining = 1`, then `deleteCapture(recordID:)` with Ask before deleting off.
- Asserts: the job is cancelled in its lane; `deletedKeys` contains the link's key (the prior upload and the
  reserved key are the same key for a replace); the record is gone.
- Covers: phase-4a:135 (Delete during a replace).

### `deleteDuringAMultipartUploadAbortsItAndDeletesTheKey` (M)
- Entry: `deleteCapture(recordID:)` during a pending recording's multipart upload over the world's 1 MiB
  plan (the `CoordinatorUploadTests` setup), parts slowed with `partDelay`, Ask before deleting off.
- Asserts: the record's upload ends `.cancelled` with the reserved key; `upload-1` is aborted by
  `abortUploads` twice (the 204 repeat); `deletedKeys` holds the key; the record goes; `multipart/` has no
  sidecar for the id (eventually, since `removeMultipartFiles` is detached).
- Covers: recording-r4:236 (Delete mid-upload aborts it). The checklist line already carries
  `(suite, in part: UploadQueueTests.aCancelDuringThePartsWaitsForEveryPart, ...)`; this test's mark replaces it.

### `aSecondAbortThatFailsAsksToRemoveFromHistory` (S)
- Entry: `deleteCapture(recordID:)` on the `anAbortFailureAsksToRemoveFromHistory` record, with
  `FakeDestination.State.onCall` setting `abortFailures = [403]` on the first `"abort"` (FakeDestination.swift:51,
  read after that call's failure is drawn).
- Asserts: the first Abort answers `.aborted`, the second throws (+Delete.swift:158-159), and
  `confirm.asked` ends with `.removeFromHistory` carrying the 403's reason.
- Covers: recording-r4:377 (call G). Built note D18 said a per-call Abort script was missing; `onCall` is one.

### `retentionDropsOldRowsAndTheirThumbnailsButKeepsSaveFolderFilesAndUnsentUploads` (M)
- Entry: `history.add(_:)` with `world.settings.historyRetentionDays = 1`; the store's `didPrune` is wired to
  `removeFiles(ofPruned:)` (AppCoordinator.swift init, +Delete.swift:242).
- Setup: an old uploaded image and an old uploaded video, each with a thumbnail and a file in a stored temp
  save folder, and an old failed upload-only image with its pending file; timestamps two days before `Date()`.
- Asserts: after adding a new record, the two old rows and their thumbnails are gone and their save-folder
  files remain; the upload-only row and its pending file are kept; `askedConfigs` is empty.
- Covers: phase-2:57 (older items gone, files kept), phase-3:66 (thumbnails gone, save folder kept, upload-only
  kept), recording-r1:310 (a video's row and thumbnail go, its file stays).

### extend `removingARecordClearsItsBookkeeping` (S)
- Entry: as today, with `coordinator.latestCapture` set to the record's id first.
- Asserts: add `latestCapture == nil` and `cards.closes == [.deleted]`.
- Covers: phase-4a:53 (deleting a row closes its overlay and drops the retained image; which source the editor
  reads is D in `EditorInputTests`).

## CoordinatorDragOutTests.swift (existing)

### `aCopyFileStageOfAPendingVideoOutlivesItsUpload` (M)
- Entry: `copyFile(recordID:)` (+RecordActions.swift:29) on a pending video with its card showing, while
  `holdingUploadsRemaining = 1` holds its upload; then `releaseUploads()`. `keepForDragOut` (+DragOut.swift:232)
  returns false when a staged copy exists.
- Asserts: `clipboard.copies == [.fileURL(staged)]` with `staged` in `Drag/<id>`; after `.uploaded` the pending
  file is gone and `dragFiles.stagedFile(id:) == staged`.
- Covers: recording-r1:282 (Copy File survives the upload), recording-r1:334 (first half of gap 7).

### `theCleanUpWaitsWhileTheClipboardHoldsTheCopyFileReference` (M)
- Entry: `copyFile` with the card showing, then `world.cards.close(recordID:reason: .user)` into
  `overlayDidClose` (+Overlay.swift:67) and `scheduleDragCleanup` (+DragOut.swift:261), driven with
  `world.clock.run(for: .seconds(60))`.
- Asserts: two 60 s waits with `clipboard.changeCount` unchanged keep the copy; after bumping `changeCount`,
  the next 60 s removes `Drag/<id>`.
- Covers: recording-r1:283 (the clean-up waits again), recording-r1:334 (second half of gap 7).

### `aCopyFileWithNoCardSchedulesItsOwnCleanUp` (S)
- Entry: `copyFile` on a `.none`, `fileIsTemporary` video with no card showing (+RecordActions.swift:43-45).
- Asserts: the staged copy is on the clipboard; after bumping `changeCount` and 60 s on the clock it is gone,
  with no card close.
- Covers: recording-r1:284 (Copy File from the row), recording-r1:334 (no card schedules the same clean-up).

### `aCopyFileWithinTheMinuteReplacesTheCloseCleanUp` (S)
- Entry: a card close schedules a clean-up, then `copyFile` within the minute cancels it
  (`dragCleanups.removeValue`, +RecordActions.swift:37) and schedules its own.
- Asserts: 60 s after the close (clipboard unchanged) the copy is still staged.
- Covers: recording-r1:285 (Copy File within the minute).

### `aDragPressAfterCopyFileReusesTheStagedCopy` (S)
- Entry: with `{counter}` in `recordingFileNameTemplate`, `copyFile` on a pending video, then
  `prepareDragFile(recordID:)` (+DragOut.swift:14) with the card showing.
- Asserts: `cards.dragFiles(for:)` ends with the URL the clipboard holds; one file in `Drag/<id>`.
- Covers: recording-r1:289 (the staged copy is reused under its name).

### `aRestoredUploadOnlyCardsQuietDownloadIsNamedForItsKey` (M)
- Entry: `prepareDragFile(recordID:)` on a showing uploaded upload-only image with no file (key
  `shots/aSIS7.png`); `prefetchDragFile` downloads through `world.factory.standard`'s `download(key:)`.
- Asserts: `cards.dragFiles(for:)` ends with `Drag/<id>/aSIS7.png`; no notifier call; with a stale file
  already in the folder, a second prepare leaves one file, under the key's name.
- Covers: phase-6a:183 (the drag file carries the key's last component after a restore).

### `theCleanUpRemovesADownloadedCopyAndALaterDragDownloadsAgain` (S)
- Entry: `downloadDragFile(recordID:)` (+DragOut.swift:98) on a showing uploaded recording with no file, then
  `world.cards.close(recordID:reason: .user)` and 60 s on the clock; then `world.cards.showing.insert(id)` and
  `downloadDragFile` again.
- Asserts: `Drag/<id>` is gone after the wait; `FakeDestination.downloads` has a second entry.
- Covers: recording-r4:291 (the 60 s clean-up removes the downloaded copy; a restored card downloads again).
  The checklist line already carries `(suite, in part: DragCleanupTests.aCardShowingTheRecordLeavesTheFolder,
  ...)`; this test's mark replaces it.

### extend `aFailureWithResumeDataKeepsItWithTheSigningTime` (S)
- Entry: as today, with `holdsDownloads = true`; move `world.date` forward while the download is held, then
  release it into the failure.
- Asserts: `dragDownloadResume[id]?.signedAt` is the date at the start, not the moved one
  (+DragOut.swift:123, :198).
- Covers: recording-r4:361 (signedAt read before the first call). Today the date never moves, so the test
  cannot tell.

## CoordinatorEditorTests.swift (new)

### `loadImageReadsTheLocalFileOrDownloadsTheObject(record:)` (S)
- Entry: `loadImage(for:)` (AppCoordinator+Editor.swift:48) into `imageData(of:)` (+RecordActions.swift:215).
  Arguments: a saved, never-uploaded PNG in a stored temp save folder; an uploaded PNG whose file is there;
  an upload-only failed PNG in `pending/`; an uploaded PNG whose recorded file is missing, with
  `downloadedData` set to a PNG.
- Asserts: a decoded `ScaledImage` of the PNG's size each time; `dataDownloadKeys` empty for the first three
  and `[key]` for the last; no notifier error.
- Covers: phase-4a:46 (saved, from the file), phase-4a:47 (uploaded, from the file), phase-4a:48 (from
  `pending/`), phase-4a:51 (renamed file, from the object). Presenting the window stays with the editor seam.

### `annotateOnAMovedPrePhase3FileSaysCouldNotOpenAndOpensNoEditor` (S)
- Entry: `openEditor(recordID:)` (+Editor.swift:15) on an uploaded record with `objectLocation` nil whose
  `fileURL` names a missing file inside a stored temp save folder (the folder is needed, otherwise
  `EditorInput.fileSource` answers `.unavailable` with another text). The load fails in `uploadedFallback`
  (+RecordActions.swift:244-249), so `presentEditor` is never reached.
- Asserts: eventually `notifier.calls` has `.error(title: "Could not open the capture", message: "The local file
  could not be read.")`; `coordinator.editors` is empty and `openingEditorIDs` empties.
- Covers: phase-4a:50 (no window, the error).

## CoordinatorOverlayTests.swift (new)

### `aRelaunchForgetsClosedCardsButKeepsTheirRecords` (S)
- Entry: `overlayDidClose(_:reason: .user)` (+Overlay.swift:67) on one coordinator, then a second
  `world.makeCoordinator()` and `history.load()`; `canRestoreClosedOverlay` (+Overlay.swift:79).
- Asserts: the first coordinator's `canRestoreClosedOverlay` is true; the second's is false and its history
  holds every record.
- Covers: phase-6a:165 (after a relaunch the list is empty, Recent Captures keeps everything).

## CoordinatorRecordActionsTests.swift (new)

### `copyLinkOrFileCopiesTheLinkEachTimeOrTheSavedFile` (S)
- Entry: `copyLinkOrFile(recordID:)` (+RecordActions.swift:9), the card's copy and the row's click.
- Asserts: an uploaded record gives `.url(url)`, and again after `clipboard.changeCount` is bumped; a saved,
  never-uploaded image gives `.fileURL(file)`.
- Covers: phase-2:40 (Copy URL again after another copy), phase-2:51, in part (an Uploaded row copies its URL;
  a saved row now copies its file instead of revealing it, since Phase 3.1; obsolete-E's corrected text for
  the line is covered in full), phase-3-1:30, in part (what goes on the clipboard; the menu closing is real
  menu tracking, `RecentCapturesMenu.afterMenusClose`, and stays by hand), phase-3:23, in part (the same rule;
  the gallery cell is now the row, and the line duplicates the phase-3-1 row-click line and takes its mark).

### `copyImageReadsTheFileOrDownloadsTheObject(source:)` (M)
- Entry: `copyImage(recordID:)` (+RecordActions.swift:88). Arguments: a saved PNG in a stored temp folder; an
  uploaded PNG that kept its file; an upload-only PNG with no file, `downloadedData` set to a PNG.
- Asserts: `clipboard.copies == [.pngAndTIFF]` each time; for the third, `notifier.calls` is
  `[.notice("Copying image…", "Downloading <key>"), .notice("Image copied", <key>)]` and `dataDownloadKeys ==
  [key]`; for the first two no download and `Image copied` names the file. `FakeClipboard` drops the bytes,
  so the pixel size is not compared.
- Covers: phase-6a:151 (Copy Image for each kind), phase-3-1:33, in part (the upload-only notices and copy).

### `aCopyImageWhoseDownloadFailsSaysCouldNotCopyImage` (M)
- Entry: `copyImage(recordID:)` on an upload-only record with no file.
- Fake extension: a throw script on `FakeDestination.download(key:)` (FakeDestination.swift:165).
- Asserts: `.error(title: "Could not copy image", message: <the error's text>)`; `clipboard.copies` empty.
- Covers: phase-3-1:33 (the Wi-Fi-off half).

### `copyImageOfAMissingFileWithNoUsableUploadSaysTheFileCouldNotBeRead(record:)` (S)
- Entry: `copyImage(recordID:)` into `uploadedFallback` (+RecordActions.swift:244-249). Arguments: an uploaded
  record with `objectLocation` nil whose save-folder file is missing (before Phase 3); a never-uploaded record
  whose `fileURL` names a file not in the stored folder (renamed).
- Asserts: `.error(title: "Could not copy image", message: "The local file could not be read.")`; no copy.
- Covers: phase-3-1:34 (pre-Phase-3 capture, file gone), phase-3-1:35 (saved, never uploaded, renamed).

### `saveAsSuggestionUsesTheCurrentCounterWithoutDrawingOne` (S)
- Entry: `saveAsSuggestion(recordID:)` (+RecordActions.swift:321) with `fileNameTemplate = "shot-{counter}"`
  on an uploaded upload-only record.
- Asserts: `fileName == "shot-\(settings.currentCounter).png"`; `currentCounter` unchanged afterwards.
- Covers: phase-4a:105 (⇧⌘S suggests `shot-<n>.png` and the next capture's draw is not skipped).

### `saveAsReplacesAnExistingFileAndSaysNotSavedForALockedOne` (S)
- Entry: `writeSaveAsCopy(_:to:)` (+RecordActions.swift:291).
- Asserts: over an existing PNG it returns true and the file holds the new bytes; over a file with
  `.immutable` set it returns false and posts `.error(title: "Not saved", ...)`. The test clears the flag in a
  `defer`.
- Covers: phase-4a:108 (Replace works; a locked file gives `Not saved`). The panel's Replace prompt is the
  system's.

### `copyFilePutsASavedRecordingItselfAndNeedsALocalFile` (S)
- Entry: `copyFile(recordID:)` (+RecordActions.swift:29-34).
- Asserts: a recording in a stored temp folder (`fileIsTemporary` false) gives `[.fileURL(file)]`; an uploaded
  video with no `fileURL` copies nothing and stages nothing.
- Covers: recording-r1:287 (Copy File on a saved recording), recording-r4:290 (Copy File still needs a local
  file; the Trim half is D in `RecordingTrimTests`).

## CoordinatorRecordingTests.swift (existing)

### `aRecordPressDuringACaptureWithAccessUndecidedShowsNoPrompt` (S)
- Entry: `recordScreen()` (+Recording.swift:145) with `recordingMicrophone` set, MP4,
  `FakeMicrophoneDevices` at `.notDetermined`, while a `TestGate` holds `withCaptureLock(coversDesktop: false)`.
  `recordingPrompts` (:317) ends at `permissionPromptStep` `.end`.
- Asserts: the call returns (`TaskWatch`); `microphones.requestCount == 0`; `askingPermission` nil; no notifier
  call; `isCapturing` is still the gate's.
- Covers: recording-r2:364, in part (no prompt and nothing started while another capture runs). The second
  half, a press after the capture prompts, goes on into `recordingCanStart`, which makes the live
  `tmp/Recording` (`Recording.makeDirectory`); that half is B with the `tmp/` statics seam (`TMPDIRS` in
  seams.md, which lists it as the second half of an A line).

### `aGIFStartAsksForTheCameraAndNotTheMicrophone` (S)
- Entry: `recordFullscreen()` (+Recording.swift:244) with `recordingFormat = .gif`, a stored microphone,
  `FakeMicrophoneDevices` at `.notDetermined`, `recordingWebcamBubble` on, `HeldCameraDevices`,
  `hideDesktopIconsWhileCapturing` off.
- Asserts: eventually `cameras.isAsking`; `askingPermission == .camera`; `microphones.requestCount == 0`. To
  end it inside the harness, `finishRecordingForQuit()` then `cameras.answer(false)`: `recordingPrompts`
  returns nil on `isQuitting`, so the lock, `tmp/Recording` and `loadContent` are never reached.
- Covers: recording-r3:155 (a GIF start asks for the camera only).

### `aSecondRecordPressWhileTheMicrophonePromptIsUpAsksNothingAndAQuitStartsNothing` (M)
- Entry: `recordScreen()` (+Recording.swift:145) with `recordingMicrophone` set, MP4, `recordingWebcamBubble`
  and `hideDesktopIconsWhileCapturing` off, over a held microphone fake; then a second `recordScreen()`;
  then `finishRecordingForQuit()` (AppCoordinator.swift:489) and the prompt answered.
- Fake extension: `HeldMicrophoneDevices`, whose `requestAccess` waits until `answer(_:)`, the
  `HeldCameraDevices` pattern (CoordinatorFakes.swift:304). The world's `microphones` is a `let`
  `FakeMicrophoneDevices` today (CoordinatorWorld.swift:53), so it becomes an `any MicrophoneDevices` var, as
  `cameras` already is.
- Asserts: eventually the prompt is open and `askingPermission == .microphone`; `capturesRefused` is true and
  `captureRefusal == .permissionPrompt(.microphone)`; the second press returns at once (`TaskWatch`;
  `recordShortcutStarts` ignores it, +Recording.swift:286-293) and the request count stays 1; after the quit
  and the answer the first call returns, `recordingPrompts` having returned nil on `isQuitting` (:340), with
  `isCapturing` false and no notifier call.
- Part of a B line: recording-r2:351, the held-prompt part (a second press does nothing, captures are
  refused, Quit starts nothing). It is not counted in the A totals. The disabled menu items (`STATUSMENU`)
  and the recording starting as usual (`CAPSRC`, `RECCHROME`) stay with the line's seams, and the
  `start ignored` line is `RecordingLog`, which no test reads.

## CoordinatorRecoveryTests.swift (existing)

### extend `anOrphanMP4IsAdoptedWithItsLength` (S)
- Entry: `adoptPendingFiles(_:)` (AppCoordinator+Recovery.swift:13), as today.
- Asserts: add `record.fileIsTemporary` and `record.uploadState == .none`, as the PNG test asserts.
- Covers: coordinator-harness:52 (an adopted recording gets `.none` and `fileIsTemporary`; Tim's
  confirmation stays his).

## CoordinatorSaveTests.swift (new)

`finishSave` and `saveRecording` over the world. Each recording is a `Recording(id:fileURL:...)` whose file
(a `VideoFixtures` MP4 or a `GIFBlocks` GIF) sits in `world.temporaryDirectory`, with `showOverlay` off unless
a test says otherwise and an explicit intent.

### `aCaptureWithTheOverlayOffShowsNoCardAndStillUploads` (S)
- Entry: `finishSave(_:image:scale:captureDisplayID:notConfiguredWarning:showsCard: true, upload:
  makeDestination(), payload: { .data(png) }, notification:)` (AppCoordinator+Save.swift:201) with
  `settings.showOverlay = false`; `showOverlay` returns before `NSScreen` (+Overlay.swift:9).
- Asserts: no `.show` in `world.cards.calls`; the record reaches `.uploaded`.
- Covers: phase-2:44 (Overlay off: no panel, uploads still work).

### `anUploadOnlyRecordingThatCannotUploadWaitsInPendingUntilARetry(cause:)` (M)
- Entry: `saveRecording(_:intent: CaptureIntent(action: .uploadOnly), ...)` (+Recording.swift:759), then
  `retryUpload(recordID:)` (+Upload.swift:462). Arguments: no credentials (deleted before the save, stored
  again before the retry), and a destination failing every attempt (`failuresRemaining` over the retry
  policy's attempts) with the retry made by a second `world.makeCoordinator()` over the same history.
- Asserts: the file is in `pending/`, the record `.failed`, `clipboard.copies` empty, no `.saved` call; with no
  credentials, the not-configured warning; after the retry `.uploaded`, `fileUploads` has the file and
  `pending/` no longer holds it (+Upload.swift:652).
- Covers: recording-r1:94 (upload-only fails, a retry after a relaunch finishes), recording-r1:319 (upload-only
  with no destination waits in `pending`).

### `aRecordingsURLReplacesItsFileReferenceOnlyWhileTheClipboardHoldsIt(kind:clipboardMoved:)` (M)
- Entry: `saveRecording(_:intent: CaptureIntent(action: .upload), ...)` into a stored temp save folder,
  `holdingUploadsRemaining = 1`, then `releaseUploads()`; then `copyLinkOrFile(recordID:)`. Arguments: an MP4
  with `alsoCopyImageWhenUploading` on and the clipboard unchanged; a GIF with `changeCount` bumped while the
  upload is held.
- Asserts: MP4: `clipboard.copies == [.fileURL(file), .url(url)]` and `.uploaded(url:, copied: true)`. GIF: no
  `.url` copy, `.uploaded(url:, copied: false)`, `fileUploads[0].contentType == "image/gif"`, and
  `copyLinkOrFile` then copies the link.
- Covers: recording-r1:277 (file reference meanwhile, URL after), recording-r2:271 (a GIF's URL only when
  nothing was copied, `image/gif`, a click copies the link).

### `uploadWithNoDestinationSavesTheRecordingAndCopiesItsFile` (S)
- Entry: `saveRecording` with `.upload` and the credentials deleted, into a stored temp save folder.
- Asserts: the record is `.none` with its file in the folder; `clipboard.copies == [.fileURL(file)]`;
  `.saved(title: "Recording saved", ...)` and `.error(title: "Upload not configured", ...)`.
- Covers: recording-r1:318 (`Upload and copy URL` with no destination saves as `Save and copy image` would).

### `quitModeSkipsTheCardTheUploadAndTheNoticesForEveryAction` (M)
- Entry: `saveRecording(_:intent:mode: .quit)` for `.save`, `.copyOnly`, `.upload` and `.uploadOnly`, with
  `showOverlay` on (the card is skipped before the screen is read) and a stored temp folder.
- Asserts: per action, no `askedConfigs`, no `.show`, no notifier call, `shutterCount == 1`, and the plan's
  clipboard copy (`RecordingSavePlan.make(..., quitMode: true)`).
- Covers: recording-r1:332 (gap 5, quit mode).

### `aMarkedRecordingStaysInPendingForEveryActionAndNeverLeaves` (M)
- Entry: `saveRecording(..., unmutedIntervals: [one interval])` for `.save` with a stored folder, `.save` with
  none, `.upload` and `.uploadOnly`; then `retryFailedUploads()` and `prepareDragFile(recordID:)` with the card
  showing.
- Asserts: each file is in `pending/`; `askedConfigs` empty; clipboard unchanged; `.error(title: "Sound not
  muted", ...)`; the retry posts nothing and the drag stages nothing. With no folder, `ensureFolder` is never
  called (the plan's target is `pending/`), so no panel opens.
- Covers: recording-r2:312 (the Debug MuteFailure run's rules; the card's tooltip and the relaunch stay hand).

### `noticesAfterStopComeInOrderWhateverShowNotificationSays` (M)
- Entry: `saveRecording(..., stopNotice:, saveNotice:, microphoneNote:, cameraNote:, highlightsNote:)` with
  `.uploadOnly` and `settings.showNotification = false`; `postAfterStop` (+Recording.swift:849).
- Asserts: the error calls in order are the save notice (`GIF not made`), `Recording stopped`, the microphone,
  the camera and the highlights notes; `GIF not made` posts with Show notification off.
- Covers: recording-r2:608 (the fixed order, `GIF not made` always posts), recording-r3:367 (the order with a
  note and a microphone note).

### `aGIFsSizeIsTheMovedFilesSize` (S)
- Entry: `saveRecording` of a `.gif` Recording with `.save` into a stored temp folder (+Recording.swift:756-763).
- Asserts: `record.byteCount` equals the GIF's size read from the folder after the move.
- Covers: recording-r2:632, in part (the GIF's size; the muted and trimmed sizes are D in
  `VideoValidationTests` and `CaptureRecordTests`).

### `recordingNoticesNeverNameTheSender` (M)
- Entry: `saveRecording` with `CaptureIntent(action: .uploadOnly, sender: "Raycast")`, `stopNotice` set, then
  the upload finishing.
- Fake extension: `FakeNotifier.Call` gains the subtitle (`notifyError` drops it today).
- Asserts: no call's title, body or subtitle contains `Raycast`.
- Covers: recording-r4:313 (gap 6).

## CoordinatorTrimTests.swift (new)

`uploadTrimmed(recordID:)` (AppCoordinator+Trim.swift:379) reaches only the refusal rule, `makeDestination`,
`saveLocation.currentURL`, `uploadPayload` and `startPlannedUpload`. No Trim window is built.

### `uploadTrimmedClearsTheStaleNoteOnSuccessAndKeepsItOnFailure` (S)
- Entry: `uploadTrimmed(recordID:)` on an uploaded pending MP4 with `uploadIsStale`.
- Asserts: success: the same key is PUT, the record `.uploaded` with `uploadIsStale == false`; with
  `failuresRemaining` set: the record keeps its link with `uploadIsStale == true` and `.error(title: "Not
  uploaded", ...)`.
- Covers: recording-r2:456, in part (`Upload Trimmed` clears `Link not updated`, a failure leaves it; the sheet
  table is D).

### `uploadTrimmedReplacesInPartsKeepsTheLinkOnFailureAndResumes` (M)
- Entry: `uploadTrimmed(recordID:)` on an uploaded, stale recording over the 1 MiB plan.
- Asserts: Create at the link's key; with `partFailures` past the retries the record goes back to its link
  with `uploadIsStale` kept and `Not uploaded`; a second `uploadTrimmed` with the file unchanged resumes (no
  second `create`).
- Covers: recording-r4:251 (`Upload Trimmed` in parts, failure keeps the link). The checklist line already
  carries `(suite, in part: CoordinatorUploadTests.aFailedUploadMarksTheRecordOrReturnsItToItsLink, ...)`; this
  test's mark replaces it.

### `aFirstReplaceWhoseURLWasNotCopiedPostsTheCacheNoteAsUploaded` (S)
- Entry: `uploadTrimmed(recordID:)` on a stale uploaded MP4 (a same-key replace) held by
  `holdingUploadsRemaining = 1`; `changeCount` bumped; `releaseUploads()`. The title is chosen at
  +Upload.swift:690-693.
- Asserts: `.notice(title: "Uploaded", body: EditorUploadPlan.cacheNote)`; no `.url` copy.
- Covers: recording-r2:645 (call C).

### `aCaptureBeingTrimmedRefusesDeleteAndUploadTrimmed` (S)
- Entry: `coordinator.trimmingIDs.insert(id)`, then `deleteCapture(recordID:)` (+Delete.swift:18) and
  `uploadTrimmed(recordID:)`.
- Asserts: `.error(title: "Not deleted", message: CaptureDeletion.trimmingRefusal)` with no `confirm.asked`;
  `.error(title: "Not uploaded", message: "This capture is being trimmed.")`; the record stays.
- Covers: recording-r2:475 (Delete and Upload Trimmed refused while trimming; Retry is D).

## CoordinatorUploadTests.swift (existing)

### `anUploadShowsItsFractionOnTheCardThenUploaded` (S)
- Entry: `retryUpload(recordID:)` on `addPendingImage`'s record with `progressFractions` the queue's
  throttle passes; `refreshOverlay` (+Overlay.swift:107) pushes each state.
- Asserts: `world.cards.updates(for: id)` holds an `.uploading` fraction between 0 and 1, then `.uploaded`.
- Covers: phase-2:39 (the ring moves, then the checkmark; the drawing is D in `QuickAccessModelTests`).

### `aScreenshotsURLReplacesTheClipboardEvenAfterACopyElsewhere(clipboardMoved:)` (S)
- Entry: `retryUpload(recordID:)` on a failed pending image, with `changeCount` bumped or not; the screenshot
  branch is `!before.isTimeBased` in `handle(.uploaded)`.
- Asserts: `clipboard.copies == [.url(url)]` and `.uploaded(url:, copied: true)` in both cases.
- Covers: phase-2:49 (Retry: the upload succeeds and the URL is copied), recording-r1:279 (a screenshot's URL
  always replaces the clipboard).

### `aFailedUploadOnlyImageKeepsItsPendingFileAndSizeUntilARetrySendsIt` (S)
- Entry: `retryUpload` with `failuresRemaining` set, then `retryFailedUploads()` (+Upload.swift:496) with none.
- Asserts: after the failure the record is `.failed`, `byteCount` unchanged and `pending/<id>.png` present;
  after `retryFailedUploads` the record is `.uploaded` and the pending file gone.
- Covers: phase-3:46 (Upload failed keeps the pending file, Retry uploads it), small-tweaks:19 (the row keeps
  its size on a failure).

### `aRetryIsNamedForTheCapturesDateWithANewlyDrawnCounter` (M)
- Entry: `retryUpload` into `startUpload` (+Upload.swift:138, the key's `TemplateContext(date:
  record.timestamp, counter:)` at :175), with `s3Config.keyTemplate = "{date}/{counter}"`.
- Asserts: a failed image from days ago is PUT under that day's folder and `currentCounter` advanced; a
  record failed with not configured, retried once credentials exist, gets a counter other than 0.
- Covers: phase-3:59 (the capture's own date, a new counter).

### `aResumedTemplateJobWhoseKeyIsTakenRedrawsItWithCounterZero` (S)
- Entry: `retryUpload` of a recording with a stored template upload whose key is taken
  (`objectSizes[storedKey]` set), template `s/{counter}-{random:6}`.
- Asserts: the new key starts with `s/0-`; `currentCounter` unchanged (+Upload.swift:174).
- Covers: recording-r4:352 (call 9).

### `forgettingCredentialsMidUploadLetsThatUploadFinish` (M)
- Entry: `retryUpload` held by `holdingUploadsRemaining = 1`, then `world.credentials.delete(account:)` and
  `destinationDidChange()` (+Upload.swift:78), then `releaseUploads()`.
- Asserts: the record `.uploaded`; `clipboard.copies` ends with `.url(url)`; `uploadingIDs` empty;
  `clock.run(until: { drainingQueues.isEmpty })` ends.
- Covers: phase-3:63 (the running upload finishes, the icon returns; the icon reads `isUploading`).

### `uploadAsNewCopiesTheNewLinkAndDeletesTheOldObject(afterAnInterruptedReplace:)` (M)
- Entry: `startPlannedUpload(recordID:plan: .newObject(supersede: oldRef, notice: nil), ...)` (+Upload.swift:102);
  with `true`, the record is first saved `.uploading` with `priorUpload(isReplace: true)` and read back by a
  second coordinator's `history.load()`, and the plan comes from `EditorUploadPlan.plan(..., asNew: true)`.
- Asserts: a template key is uploaded; `clipboard.copies` ends with `.url(new)`; `uploadedKey` is the new key;
  eventually `deletedKeys` holds the old key.
- Covers: phase-4a:126 (Upload as New), phase-4a:128 (after an interrupted replace).

### `anInterruptedReplaceRetriesOverItsOwnKeyAfterARelaunch` (M)
- Entry: a record saved `.uploading` with `priorUpload(isReplace: true)`, `history.load()` on a second
  coordinator, then `retryFailedUploads()`; `EditorUploadPlan.retryPolicy` gives `.fixed(key)`.
- Asserts: `uploads.last` has the same key with `cacheControl == "no-cache"`; the record `.uploaded` with the
  same URL.
- Covers: phase-4a:134 (Quit during a replace).

### `onlyTheFirstReplaceOfALaunchPostsTheCacheNote` (M)
- Entry: `startPlannedUpload(.replace(key))` twice on one coordinator, then once on a second
  `makeCoordinator()`, with `showNotification` off; `postedCacheNote` (+Upload.swift:685-701).
- Asserts: `.notice(title: "Uploaded, URL copied", body: EditorUploadPlan.cacheNote)` on the first and the
  third only; a `.newObject` upload posts no cache note.
- Covers: phase-4a:142 (the cache note once per launch).

## CounterTests.swift (existing)

### `undoingCopiesReturnsTheNumbersAndRedoRestoresThem` (S)
- Entry: `EditorModel.duplicateSelection()`, `makeTool(for: .select)` ⌥-drag, `paste(_:)`, then
  `undoManager.undo()`/`redo()` and `makeAnnotation(.counter, ...)`, with the suite's helpers.
- Asserts: three undos give numbers `[1, 2]`; each redo restores its copy with its number; after three undos a
  new counter is 3.
- Covers: phase-4c:159 (undo and redo of the three copies).

### `aCounterPastedTwiceAcrossScalesTakesTheNextNumbersAtItsPointSize` (S)
- Entry: `objectClip()` on a 2x model, `AnnotationClip` encode and decode, `paste(_:)` twice into a 1x model
  that already has counters; and the other way.
- Asserts: the pasted numbers are the target's next two; the second is cascaded from the first; a 64 px
  counter at 2x is 32 px at 1x.
- Covers: phase-4c:162 (a counter pasted across scales).

## EditorBackgroundExportTests.swift (existing)

Solid fills only: a desktop-picture or custom-image fill reads the wallpaper or `CustomBackgroundStore.shared`.

### `aSwatchTheShadowAndAnAspectAreThreeStepsThatDirtyTheEditor` (S)
- Entry: `setBackground`, then the suite's `change` helper (`backgroundDraft` and `commitBackgroundDraft`,
  EditorModel.swift:433) for a swatch, the shadow toggle and an aspect; `markSaved()`.
- Asserts: `hasUnsavedChanges` after each; three undos take them back in reverse, one each; after
  `markSaved()` the model is clean.
- Covers: phase-7c:94 (three steps undone in reverse, Shadow not pinned today), phase-7c:98, in part (dirty
  after each, clean after Save; the window's edited mark needs the editor window).

### `theShownCanvasHasTheExportsSizeForEveryAspect` (S)
- Entry: `shownBackground.canvasRect` and `renderExport()` (EditorModel.swift:684) for every `BackgroundAspect`,
  without and with a crop.
- Asserts: the canvas rect's size equals the export's pixel size each time; with a crop and 16:9, the export
  is laid out from the crop's size (`backgroundContentRect`, :400).
- Covers: phase-7c:143 (the preview matches the export for every ratio), phase-7c:165 (16:9 with a crop).

### `aBackgroundFitsTallContentAndACropUnderTheLimit` (M)
- Entry: `backgroundFits(_:)`, `setBackground`, `applyCrop()`, `undoManager.undo()` and `renderExport()` on a
  narrow 14,000 px image and on an 18,000 px one cropped to 10,000 px.
- Asserts: 14,000 px fits and exports at content plus padding; 18,000 px does not fit, the 10,000 px crop
  does; after the undo the test records which of the two outcomes the line names happens (the background
  step goes first, or the export throws `.background`).
- Covers: phase-7c:147 (a tall scrolling capture), phase-7c:150 (the limit is on the crop).

### `theCropToolHidesTheBackgroundAndCancelOrUndoReturnsItAroundTheWholeCapture` (S)
- Entry: `model.tool = .crop`, `applyCrop()`, `cancelCrop()` (EditorModel.swift:383), and undo of an applied
  crop, with a background set first.
- Asserts: `shownBackground` is nil while the Crop tool is open; after `cancelCrop` it frames the whole
  capture; after undo of the crop it frames the whole capture with the background still on.
- Covers: phase-7c:158 (Escape restores the whole-capture background), phase-7c:164 (undo the crop).

## EditorFlattenerTests.swift (existing)

### `aCropKeepingATransparentCornerKeepsItClear` (S)
- Entry: `EditorFlattener.flatten` over the `alphaZeroCornerKept` fixture with a crop that keeps that corner.
- Asserts: the output's corner pixel has alpha 0.
- Covers: phase-4b:79 (a crop of a window capture keeps its transparent corner).

## EditorModelTests.swift (existing)

### `blockSizeAppliesToTheSelectedPixelateInOneStep` (S)
- Entry: `EditorModel.applyEffectParameter(.block, points:)` (EditorModel.swift:588) with a `.pixelate` region
  selected.
- Asserts: the region's block changes; one undo step.
- Covers: phase-4a:60 (Pixelate's square size on the selection).

### `widthAndColourApplyToTheSelectedShapeAndItsTool(kind:)` (S)
- Entry: `applyLineWidth(points:)` (:572) and `applyColor(_:)` (:558), over a selected rectangle, ellipse and
  line.
- Asserts: the shape's width is `points * scale` and `lineWidthPoints` follows; its colour changes and
  `strokeColor` follows; `undoActionName` per change.
- Covers: phase-4a:62 (Rectangle widths on the selection and the tool), phase-4b:37 (ellipse and line widths
  and colour).

### `colourAppliesToTheSelectedTextAndTheTextBeingTyped` (S)
- Entry: `applyColor(_:)` with a text selected, and during `beginTextEditing` (:566).
- Asserts: the selected text is recoloured and `strokeColor` follows; while editing, `textEditing.box.color`
  follows.
- Covers: phase-4b:55 (the colour button on a text and while typing).

### `selectAllWithEveryAnnotationOutsideTheCropSelectsNothing` (S)
- Entry: `selectAll()` (:360) with an applied crop and every annotation outside it.
- Asserts: `selection` stays nil.
- Covers: phase-4b:84 (the all-outside case).

### `duplicateCopiesEveryKindOffsetAndNamed(kind:)` (S)
- Entry: `duplicateSelection()` (:327) over ellipse, line, pencil, highlighter, text, arrow, blur and redact.
- Asserts: the copy has the same kind, is moved by `duplicateOffset` and the step is `Duplicate <title>`.
- Covers: phase-4b:88 (⌘D on every kind).

### `oneOfEachToolUndoesNewestFirstAndRedoesInOrder` (M)
- Entry: the real tools (`makeTool(for:)`, driven as in `CanvasToolTests`) with the `EditorModel` as their
  `CanvasEditing`, one commit per tool, then an `applyCrop()`.
- Asserts: undo removes the crop as its own step, then the ten annotations newest first; ten redos bring them
  back in order.
- Covers: phase-4b:118 (ten ⌘Z and ten ⇧⌘Z).

### `lineWidthWithASpotlightOrCounterSelectedChangesOnlyTheDefault` (S)
- Entry: `applyLineWidth(points:)` with a spotlight, then a counter, selected.
- Asserts: `lineWidthPoints` changes; `document` does not; `undoManager.canUndo` and `hasUnsavedChanges` are as
  before.
- Covers: phase-4c:140 (Line width changes only the default).

### extend `aSelectedCounterShowsAndTakesTheColour` (S)
- Entry: as today, then `makeAnnotation(.counter, ...)`.
- Asserts: add that the new counter's `counterMark.color` is the applied colour (`strokeColor` followed it,
  :558-565).
- Covers: phase-4c:151 (counters placed afterwards use that colour).

### `everySpotlightEditIsOneNamedUndoStep` (M)
- Entry: `makeTool(for: .spotlight)` and `.select` (move, resize, ⌥-drag), `duplicateSelection()` and
  `paste(_:)` twice, on a real model.
- Asserts: `undoActionName` is `Add Spotlight`, `Move Spotlight`, `Resize Spotlight`, `Duplicate Spotlight`
  (⌘D and ⌥-drag) and `Paste Spotlight`; the second paste lands one cascade step further; each undo and redo
  restores the document and `hasUnsavedChanges` follows.
- Covers: phase-4c:163 (Duplicate and Paste Spotlight, the second paste further), phase-4c:167 (the spotlight
  action names).

### `spotlightDimStaysWithItsModel` (S)
- Entry: two models from `makeModel`; `applySpotlightDim(0.7)` (:659) on one after a spotlight.
- Asserts: the other's `document.effectiveSpotlightDim` is 0.5.
- Covers: phase-4c:203 (Dim does not carry into another capture).

## GIFFileSinkTests.swift (existing)

### `couldNotReadSaysTheRecordingCouldNotBeRead` (S)
- Entry: `GIFMakerError.couldNotRead.localizedDescription` (GIFSink.swift:17) and `GIFConversion.notMade(_:)`
  (GIFConversion.swift:29).
- Asserts: the text is `The recording could not be read.`; `notMade` of it gives `GIF not made` / `The
  recording could not be read. The recording was saved as an MP4.`
- Covers: recording-r2:640 (call A).

## QuickAccessCardDragViewTests.swift (new)

### `theDragViewAsksForTheDownloadOncePerPressPastTheThreshold` (S)
- Entry: `QuickAccessCardDragView.mouseDown`/`mouseDragged` (QuickAccessCardDragSource.swift:53-83) with a
  `QuickAccessModel(record:thumbnail:)` whose `onPrepareDrag` and `onDownloadForDrag` count calls and whose
  `dragFileURL` is nil, so no dragging session starts. No window is needed: the view reads `locationInWindow`.
- Asserts: a press calls only `onPrepareDrag`; a 2 pt drag calls nothing; a 3 pt drag calls
  `onDownloadForDrag` once, and further drags do not; a new press asks again after its own 3 pt drag.
- Covers: recording-r4:330 (gap 22, the download starts at the threshold, not on the press),
  recording-r4:355 (gap 11, once per press).

## QuickAccessModelTests.swift (existing)

### `anUploadOnlyCardsThumbnailRevealsNothing` (S)
- Entry: `QuickAccessModel.canReveal` (QuickAccessModel.swift:101).
- Asserts: false for an upload-only image card with its pending file (temporary) and for one after the upload
  (no file).
- Covers: phase-3:42 (no Finder reveal on an upload-only capture).

## RecentCapturesMenuTests.swift (new)

### `anEmptyHistoryShowsOneDisabledNoCapturesYet` (S)
- Entry: `RecentCapturesMenu(coordinator: world.makeCoordinator(), closeMenus: {}, statusItemFrame: { nil })`
  and `rebuild()` (RecentCapturesMenu.swift:41). The menu is built, never opened; its `PreviewPanel` is built
  deferred and only hidden.
- Asserts: `menu.items` is one item titled `No captures yet` with `isEnabled == false`.
- Covers: phase-3-1:37 (an empty history's submenu).

## ScrollCaptureSessionTests.swift (existing)

### `doneWhileLostSavesWhatWasStitchedBeforeTheLoss` (S)
- Entry: `ScrollCaptureSession.done()` (ScrollCaptureSession.swift:186) over `FakeFrameSource` (the suite's
  `makeSession`): offsets 0 and 100, then 700, wait for `.manualLost`, then `done()`.
- Asserts: `.image` 500 px tall; `page.compare(reached: 100).mismatched == 0`.
- Covers: phase-5:106 (Done while the line shows saves what was stitched).

## SelectionViewTests.swift (new)

A `SelectionView` in a borderless `NSWindow` that is never shown, driven by synthesized events, as
`SelectionViewArmingTests.makeView` does. `onComplete` converts through that window, which is why it is there.

### `escapeCancelsAnAreaOrWindowSelection(mode:)` (S)
- Entry: `SelectionView.keyDown` (SelectionView.swift:207-245) with keyCode 53, `mode` `.area` and `.window`.
- Asserts: `onCancel` fires once.
- Covers: phase-1:19 (Escape before any click), phase-1:33 (Escape in window mode). The controller's dismiss
  needs `SelectionController.present` and is not reached.

### `aRecordingSelectionIgnoresReturnAndRecordsAClickInsideTheRect` (M)
- Entry: `mode = .recording` with `presetRect` set: `keyDown` with 36 and 76, then `mouseDown`/`mouseUp`
  inside, a drag starting inside, a click outside with `highlightedRect` set, and Escape (:146-204, :232-236).
- Asserts: Return and Enter fire neither `onComplete` nor `onCancel`; a click inside completes with the preset;
  the drag completes with the dragged rect; the outside click calls `onPickWindow`; Escape calls `onCancel`.
- Covers: recording-r4:208 (Return and Enter do nothing, click, drag, window, Escape), recording-r4:311 (gap 4,
  no key records).

### `aClickWithoutADragTakesTheHighlightedWindowAndADragDoesNot` (M)
- Entry: All-in-One `allInOneMouseDown`/`allInOneMouseUp` (:461, :509) with `highlightedRect` set.
- Asserts: a click sets `adjustRect` to the highlight fitted to bounds, `adjustRectIsWindow` true and
  `onAdjustRectSet(true)`; a handle drag and a nudge keep `adjustRectIsWindow`; a new drag sets it false; a
  click outside with another highlight takes that rect; with no highlight the rect stays and `onEmptyClick`
  does not fire.
- Covers: phase-6b:52 (click a window, Window stays enabled, a drag greys it).

### `aPressOutsideTheRectStartsANewOne` (S)
- Entry: `allInOneMouseDown` with no handle under the point (:467-470), then a drag and release; a drag past the
  bounds (:486).
- Asserts: `adjustRect` becomes the new dragged rect; the dragged point is clamped to the bounds.
- Covers: phase-6b:53 (drag outside starts a new rect; the handle geometry is D in `SelectionAdjustTests`).

### `commandKeysNeitherCaptureNorNudgeAndShiftArrowMovesTen` (S)
- Entry: All-in-One `keyDown` with `.command` (:212) on Return (36) and an arrow, and Shift-arrow.
- Asserts: no `onAllInOneAction` and `adjustRect` unchanged with Command; Shift-arrow moves it 10 pt.
- Covers: phase-6b:55 (Command-Return and Command-arrows; Shift-arrow 10 pt).

### `aTypedWidthResizesFromTheTopLeftWithoutCapturing` (M)
- Entry: `AllInOneToolbar.control(_:textView:doCommandBy: #selector(insertNewline(_:)))`
  (AllInOneToolbar.swift:102-121) on the view's toolbar, found among its subviews (the fields are private).
- Asserts: `adjustRect.width == 640` from the same top-left; a value past the room is clamped and the field then
  shows the real size; no `onAllInOneAction`; a following `keyDown` Return fires `.capture`;
  `widthField.nextKeyView === heightField`.
- Covers: phase-6b:56 (type into W, Return, clamping, Tab).

## SelfTimerTests.swift (existing)

### `theCountdownPanelAndTheScrollFrameLetClicksThrough` (S)
- Entry: `SelfTimerPanel(model:frame:)` (SelfTimerPanel.swift:35) and `ScrollAreaFrameWindow(area:)`
  (ScrollAreaFrameWindow.swift:13), built and never shown, as `theBadgeSitsAtTheScreenSaverLevel` does.
- Asserts: `ignoresMouseEvents` on both.
- Covers: phase-6b:72 (the countdown panel and frame are click-through).

## TemplateExpanderTests.swift (existing)

### `theTokenListNamesEveryToken` (S)
- Entry: `TemplateExpander.tokenList` (TemplateExpander.swift:66), which both captions interpolate.
- Asserts: equals `{date} {year} {month} {day} {time} {datetime} {hostname} {counter} {random} {random:8}`.
- Covers: phase-3-1:60 (the token captions in General and Upload).

## ThumbnailProviderTests.swift (existing)

### `aNamedThumbnailThatIsGoneIsMadeAgainFromTheFile` (S)
- Entry: `ThumbnailProvider.thumbnail(for:)` (ThumbnailProvider.swift:54) for a record whose
  `thumbnailFileName` names a file absent from the store, `readFile` returning a tall PNG.
- Asserts: a 213 x 320 image showing the top rows; a new file in the store.
- Covers: phase-5:199 (a deleted thumbnail is made again from the file).

## UploadQueueTests.swift (existing)

### `aPartRetrySendsTheBytesItFirstRead` (M)
- Entry: `UploadQueue` over `FakeDestination` (`makeMultipartQueue`) with `partFailures = [3: [503]]`; `onCall`
  overwrites part 3's byte range of the file on the first `"part 3"`. `PartSender.send` reads once, before
  `withRetries` (UploadQueue+Parts.swift:167-176).
- Fake extension: `FakeDestination` records a digest of each `uploadPart` call's data.
- Asserts: both part 3 calls carry the same digest, that of the original bytes.
- Covers: recording-r4:378 (call H). Built note D18 asked for a read counter; changing the file is the
  no-seam way to see it.

## URLCommandHandlerTests.swift (existing)

### `aDisplayWithoutARectOpensTheNormalSelection` (S)
- Entry: `URLCommandHandler.handle(_:sender:)` (URLCommandHandler.swift:83) with
  `tidyshot://capture-area?display=7`; a placement is made only with `command.area` (:157).
- Asserts: `target.calls == [.area(standard)]`; no notice.
- Covers: phase-6b:153 (display counts only with a rect; `display=abc` is D in `URLCommandTests`).

### `aGateRefusedCaptureDoesNotCountAsTheFirstQueuedOne` (S)
- Entry: as `onlyTheFirstQueuedCaptureCommandRuns`, with `urlCommandsAllowSilent` off: queue
  `capture-fullscreen` (refused by the gate, :146-149) then `capture-window`, then `ready()`.
- Asserts: `target.calls == [.window(standard)]`; one refusal notice.
- Covers: phase-6b:161 (a gate refusal ahead of the window selection does not stop it).

## Reclassified

Fourteen lines. The first thirteen build an `EditorWindowController`. Its init reads `NSScreen.screens` and
`NSEvent.mouseLocation` in `placeWindow` (EditorWindowController.swift:123, which indexes `NSScreen.screens[0]`
when no screen is under the pointer and there is no main screen) and registers an observer with
`NSWorkspace.shared.notificationCenter` (:103). Inserting one into `coordinator.editors` does not avoid that,
and the harness design lists the editor window controllers as a Deferred seam. Each needs the editor-window
seam (S1 in the reader notes, `EDITOR` in seams.md: a presenter protocol from `AppEnvironment`), and
seams.md lists all thirteen under `EDITOR`. The fourteenth, recording-r2:241, is listed there under
`TMPDIRS`.

| line | was | now | why |
|---|---|---|---|
| phase-4a:37 | A | B | Subtitle `Uploading…` and greyed Save/Upload read off a constructed controller fed by `pushEditorState`; the availability table is D. |
| phase-4a:56 | A | B | Toolbar order and tool tips read from `window.toolbar.items` of a constructed controller. obsolete-E's corrected toolbar text goes with the B line. |
| phase-4a:58 | A | B | The letters are D (`KeyRoutingTests.lettersSelectTools`); what is left is the toolbar's segment following, through `EditorToolbar.reflectTool` on the controller. |
| phase-4a:88 | A | B | ⌘1/⌘0/⌘=/⌘- are the controller's actions (`zoomToActualSize` and the others, :404-422) and the pop-up is its toolbar; the anchor and percentage maths is D. |
| phase-4a:107 | A | B | `closesWindow(documentUnchanged:)` is D; "the newer edit is not marked saved" and the beep are `performUpload` on the controller (:266-282). |
| phase-4a:145 | A | B | `validateUserInterfaceItem` and `available` on a constructed controller during a held upload. |
| phase-4a:146 | A | B | Subtitle `Deleting…` and availability on a constructed controller while `FakeConfirm` holds. |
| phase-4a:151 | A | B | `windowShouldClose` on a constructed controller. |
| phase-4a:162 | A | B | The pruned record's editor subtitle through `pushEditorState` into a constructed controller. |
| phase-4c:94 | A | B | Toolbar item order after the tools and the Options tip, from the constructed controller's toolbar. |
| phase-4c:95 | A | B | The keys are D (`KeyRoutingTests.sAndNPickSpotlightAndCounter`); the segment following is the controller's. |
| phase-7c:72 | A | B | The Background toolbar item, read from the constructed controller's toolbar. |
| phase-7c:169 | A | B | `copyImage(_:)` on a constructed controller handing `actions.copy` the composed image; `renderExport` with a background is pinned elsewhere. |
| recording-r2:241 | A | B | `recoverRecordings` reads the `tmp/` statics: `MuteLog.directory` in `RecordingRecovery.prepare`, `RecordingMute.rewriteURL`, and `Recording.directory` for the mute-folder sweep (AppCoordinator+Recovery.swift:117-170). The harness design lists those statics as Deferred; the reader's own note says a strict reading makes it B. Needs seam S7 (`TMPDIRS` in seams.md: the statics from `AppEnvironment.temporaryDirectory`). |

The reconciliation of the four documents (critic.md) moved five more lines across A's edge:

| line | was | now | why |
|---|---|---|---|
| phase-3-1:55 | A | D | The second-delete guard. `CoordinatorDeleteTests.deleteAsksOnceAndASecondDeleteWhileItAsksAsksNothing` holds the second Delete at the alert; the same `deletingIDs` guard (+Delete.swift:16, set at :22, cleared in the defer at :27-30) holds through the storage request, so the line is D, with phase-3:28. The new test this document had for it is withdrawn. The mark is in marks-D. |
| phase-3:23 | E | A | obsolete-E: the rule is unchanged on the submenu row. Covered in part by `copyLinkOrFileCopiesTheLinkEachTimeOrTheSavedFile`. It duplicates phase-3-1:30, stays in the phase-3 checklist and takes the same mark. |
| phase-3:26 | E | A | obsolete-E: the coordinator half (no DELETE for a record without a location, the row and file gone) is A, covered by `aPrePhase3UploadedCaptureIsDeletedWithNoStorageRequest`; the alert text is D, marked in marks-D. |
| phase-3:31 | E | A | obsolete-E: delete at the record's own location. Covered by `aDeleteAfterABucketChangeDeletesWhereTheObjectWent`. |
| phase-3-1:30 | C | A | One rule with phase-2:51 and phase-3:23: what goes on the clipboard is A. Covered in part by `copyLinkOrFileCopiesTheLinkEachTimeOrTheSavedFile`; the menu closing stays by hand. |

Lines kept as covered but only in part, with the rest named in the test: phase-2:51, phase-3:23, phase-3-1:30,
phase-4b:30, phase-4b:99, phase-4b:130, phase-4c:209, phase-7c:98, recording-r2:364, recording-r2:456,
recording-r2:632.

Lines split across several tests stay split, and each line's one mark names every test that covers part of
it: phase-3-1:33 (`copyImageReadsTheFileOrDownloadsTheObject` and `aCopyImageWhoseDownloadFailsSaysCouldNotCopyImage`),
phase-4c:209 (`anAccessibilityPressSelectsAndTheCanvasActsOnTheSelection`,
`anAccessibilityPressIsRefusedWithTheCropToolOrDuringADrag` and the existing `cropHidesAnnotationsOutsideIt`),
phase-4b:130 (`anAccessibilityPressIsRefusedWithTheCropToolOrDuringADrag` and the existing
`cropHidesAnnotationsOutsideIt`) and recording-r1:334 (`aCopyFileStageOfAPendingVideoOutlivesItsUpload`,
`theCleanUpWaitsWhileTheClipboardHoldsTheCopyFileReference` and `aCopyFileWithNoCardSchedulesItsOwnCleanUp`).

Three lines already carry an in-part mark in their checklist: recording-r4:236, recording-r4:251 and
recording-r4:291 (checklist lines 237, 252 and 291, where the mark sits on the continuation line). The new
test's mark replaces the old one on each.

One test covers part of a B line and is not counted below: the held-prompt part of recording-r2:351, in
`CoordinatorRecordingTests.aSecondRecordPressWhileTheMicrophonePromptIsUpAsksNothingAndAQuitStartsNothing`.

## Totals

- Distinct tests: 108, of which 5 extend an existing test (the `extend` entries) and 103 are new tests, in 33
  suite files (10 of them new files). One of the 108 covers only part of a B line.
- Lines covered: all 148 A lines, 137 in full and 11 in part.
- Lines reclassified out of A: 15 (14 to B, 1 to D). Into A: 4 (3 from E, 1 from C).
