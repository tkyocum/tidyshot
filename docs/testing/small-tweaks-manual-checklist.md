# Manual checklist: Ask before deleting, and sizes in Recent Captures (spec 2.13)

Run this after any change to `AppCoordinator+Delete.swift`'s confirmation, `CaptureDeletion`, `RecentCaptureFormatting`, `RecentCaptureRow`, or where `CaptureRecord.byteCount` is set (save, editor Save and Upload, upload events, recording recovery, the launch backfill).

## Ask before deleting
- [ ] Settings > General shows `Ask before deleting` after `Play sound`, on, with the caption `Delete removes the file, the upload and the Recent Captures entry. When this is off, Delete acts at once.`
- [ ] With it on, Delete on a card and on a Recent Captures row each asks first. The card menu and the row read `Delete…`.
- [ ] Turn it off. Delete from a card and a row each act at once with no alert. The card menu and the row read `Delete`.
- [ ] With it off, make a remote delete fail: set a wrong secret key in Settings > Upload and save without testing, then delete an uploaded capture. The second alert (`Remove it from history anyway?`) still appears. Put the key back.
  (suite: CoordinatorDeleteTests.aDeleteThatCannotReachStorageAsksToRemoveFromHistory,
  .anAbortFailureAsksToRemoveFromHistory)
- [ ] Turn it back on for normal use, if you prefer. (suite:
  AppSettingsTests.confirmBeforeDeletingDefaultsToTrueAndPersists)

## Sizes in Recent Captures
- [ ] A screenshot row reads `<time> · <size>`, for example `2 minutes ago · 412 KB`. The middle dot has a space either side. The size matches Finder's for the file, or the uploaded object's size.
- [ ] Upload a capture with Clop on: after the upload, the row shows the smaller, optimised size.
- [ ] A recording row shows its size after it saves, and the optimised size after an upload with Clop on.
- [ ] An upload-only capture shows a size before and after its upload.
- [ ] While uploading, a row reads `<time> · <size> · Uploading`. If the menu is narrow, it may show `<time> · Uploading` instead; write down which you see.
- [ ] Edit a capture in the editor and Save: its row shows the edited file's size. Upload from the editor: after it finishes, the row shows the uploaded size.
  (suite: CoordinatorEditorUploadTests.annotateTheNewestCardSaveThenUploadWritesTheFileThenUploadsAndCopiesTheURL,
  CoordinatorEditorSaveTests.saveWritesOverTheSaveFolderFileAndUploadsNothing)
- [ ] Make an upload fail (no network): the row keeps its earlier size and reads `· Upload failed`. (suite:
  CoordinatorUploadTests.aFailedUploadOnlyImageKeepsItsPendingFileAndSizeUntilARetrySendsIt,
  RecentCaptureFormattingTests.detailIsTheTimeTheSizeAndEachUploadState)
- [ ] A capture saved before this change shows a size after relaunch if its file is in the save folder or kept in TidyShot. One that only exists as an upload shows no size.
