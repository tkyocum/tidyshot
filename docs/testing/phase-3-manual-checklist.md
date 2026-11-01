# Phase 3 manual test checklist

Phase 3.1 replaced the gallery window with the Recent Captures submenu and the three-button delete
alert with a two-button one. Skip the Gallery section and the "Remove from History Only" items
below; `docs/testing/phase-3-1-manual-checklist.md` covers them now. Where an item below says the
gallery, use the Recent Captures submenu: retrying happens through Retry Failed Uploads in the menu
(or the overlay's Retry), the submenu row has no "No local file" text, and the delete alert texts
are the ones in the Phase 3.1 checklist.

Run after any change to Recent Captures, Overlay, History, Upload naming, or AppCoordinator. Automated
tests cover the template engine, key validation and migration, thumbnails and the two stores,
record migration, queue cancellation, deletion bookkeeping and the thumbnail provider; everything
here needs a real bucket and eyes.

Setup: fresh build, Screen Recording granted, save folder set to Desktop, a working destination
saved in Settings > Upload, after-capture action "Upload and copy URL", three or more captures in
history including at least one Phase 2 capture (made before this build).

## Gallery
- [x] The menu shows "Recent Captures…" and no submenu; with an empty history the window shows "No captures yet".
  (obsolete: Recent Captures is now a submenu that shows a greyed `No captures yet` when the history is empty; there is
  no gallery window)
- [x] The grid lists captures newest first with a thumbnail and a status capsule each; Phase 2 captures whose files exist get thumbnails on first display (`thumbnails/` gains files, `history.json` gains `thumbnailFileName`); a Phase 2 capture whose file was deleted shows the placeholder icon, and scrolling past it again does not make the gallery try again (no new `thumbnails/` file, no stutter).
  (obsolete: the gallery grid and status capsules are gone and Recent Captures rows replaced them; thumbnails on first
  display are checked in the Phase 3.1 checklist, and the missing-file case (no second try) is pinned by
  `ThumbnailProviderTests`)
- [x] Hovering a cell highlights it and the right-hand pane shows it larger with date, `W × H px`, app, URL or status, and file path.
  (obsolete: the floating preview panel on the Recent Captures rows replaced the right-hand pane when the gallery window
  was removed)
- [ ] Clicking an Uploaded cell copies the URL (paste into Notes); clicking a Saved cell copies the file (paste in Finder makes a copy).
  (suite, in part: CoordinatorRecordActionsTests.copyLinkOrFileCopiesTheLinkEachTimeOrTheSavedFile; by hand: the menu
  closing)
- [x] Context menu offers Copy URL or Copy File, Retry Upload (Failed only), Reveal in Finder (local file only), Delete….
  (obsolete: the row has link, photo and trash buttons instead of a context menu, and Retry moved to Retry Failed
  Uploads and the card's Retry)
- [x] Delete… on an uploaded capture: one alert, whose text names the object URL and the file, with the buttons "Delete", "Remove from History Only" and "Cancel"; Cancel changes nothing; Delete removes the row, `curl -I <url>` gives 403 or 404, the file is gone from the save folder, the thumbnail is gone from `thumbnails/`, and the preview pane no longer shows it.
  (obsolete: the three-button alert was withdrawn; Delete asks `Delete this capture?` with Delete and Cancel, and a
  failed removal opens a second Remove and Cancel alert, checked in the Phase 3.1 checklist)
- [ ] Delete… on a Phase 2 capture that was uploaded: the alert says the uploaded object stays in the bucket; Delete removes the row and the file, and `curl -I <url>` still gives 200.
  (suite: CaptureDeletionTests.confirmationTextSaysWhenTheObjectStays,
  CoordinatorDeleteTests.aPrePhase3UploadedCaptureIsDeletedWithNoStorageRequest)
- [x] Delete… while offline on an uploaded capture: notification "Not deleted" and the row stays; back online, Delete… works.
  (obsolete: a failed storage DELETE now opens a second alert, `Couldn't delete it from storage: <reason>`, with Remove
  and Cancel instead of a `Not deleted` notification, checked in the Phase 3.1 checklist)
- [ ] Network Link Conditioner at 100% packet loss, Delete… on an uploaded capture, choose Delete, then choose Delete… on the same capture again (gallery) and click its trash button (overlay) while the request hangs: no second alert appears.
  (suite: CoordinatorDeleteTests.deleteAsksOnceAndASecondDeleteWhileItAsksAsksNothing)
- [x] Forget Credentials, then Delete… on an uploaded capture: notification "Not deleted" telling you to save credentials or choose Remove from History Only, and the row stays; Delete… again and choose "Remove from History Only": the row and thumbnail go, the object (`curl -I <url>` gives 200) and the file in the save folder stay. Re-enter the credentials.
  (obsolete: with no credentials the second alert reads `Couldn't delete it from storage: No credentials are saved in
  Settings > Upload.`, and Remove from History Only is gone, checked in the Phase 3.1 checklist)
- [x] Make the local file undeletable (`chflags uchg <file>` on a Saved capture), Delete…: notification "Not deleted" naming the file and the reason, and the row stays; `chflags nouchg <file>`, Delete… works.
  (obsolete: a save-folder file that cannot be removed now opens the second alert `Couldn't delete the file: <reason>`,
  and `Not deleted` is posted only for a `pending/` file)
- [ ] Change the Upload tab's bucket and Save, then Delete a capture uploaded before the change (trash button on its row or card): the object is removed from the bucket it was uploaded to (`curl -I <old url>` gives 403 or 404), not looked for in the new one.
  (suite: CoordinatorDeleteTests.aDeleteAfterABucketChangeDeletesWhereTheObjectWent,
  CaptureDeletionTests.objectsIncludeSupersededAtTheirLocations)
- [ ] Key template `shared/{date}` and a key that cannot read objects (HEAD answers 403 for existing keys), two captures the same day: both rows point at the same key; Delete the first from its row: notification "Not deleted from storage" saying another capture shares this key, the row goes, and the second capture's URL still works.
  (suite, in part: CoordinatorDeleteTests.aSharedKeyKeepsTheObjectAndSaysSo, S3DestinationTests.headTreats403AsMissing;
  a real key that cannot read objects answering 403 for an existing key, so that two captures land on one key, stays by
  hand)
- [x] Retry Upload on a Failed capture with the network restored turns the capsule Uploaded and copies the URL.
  (obsolete: the per-item Retry Upload is gone; Retry Failed Uploads and the card's Retry replaced it, checked in the
  Phase 2 and Phase 3.1 checklists)
- [x] The window remembers its size and position across close and reopen; Escape and ⌘W close it. (obsolete: there is no
  gallery window, so there is no size or position to remember and nothing for Escape or ⌘W to close)
- [x] With the window open, a new capture appears at the top with its thumbnail and its capsule goes Uploading, then Uploaded.
  (obsolete: there is no gallery window; the Recent Captures submenu is rebuilt each time it opens)

## Overlay delete
- [ ] Trash button during an upload (fullscreen capture or Network Link Conditioner): the alert reads "Removes it from object storage, your save folder and history." ("Removes it from object storage and from history." for an upload-only capture); after Delete the overlay closes, the menu bar icon returns to the viewfinder, no object is in the bucket (list it, or GET the URL the overlay would have shown), no row, no file, no thumbnail.
  (suite: CoordinatorDeleteTests.deleteDuringAnUploadCancelsItThenDeletesTheReservedKey,
  CaptureDeletionTests.confirmationTextIsOneLine)
- [ ] Trash button during an upload, right after saving the Upload tab (so the upload runs on the replaced queue): the upload is still cancelled, and the menu bar icon returns to the viewfinder.
  (suite: CoordinatorDeleteTests.deleteDuringAnUploadCancelsItThenDeletesTheReservedKey)
- [ ] Trash button after the upload finished: object, row, file and thumbnail gone. (suite:
  CoordinatorDeleteTests.deleteRemovesTheObjectTheFileTheThumbnailAndTheRow)
- [ ] Cancel in the alert keeps everything and the overlay stays. (suite:
  CoordinatorDeleteTests.deleteDuringAnUploadCancelsItThenDeletesTheReservedKey,
  .deleteAsksOnceAndASecondDeleteWhileItAsksAsksNothing)
- [ ] Clicking the thumbnail of an upload-only capture does nothing (no Finder reveal). (suite:
  QuickAccessModelTests.anUploadOnlyCardsThumbnailRevealsNothing)

## Upload only
- [ ] Settings > General, "Upload only, keep no local file": the caption appears; with no save folder chosen, a capture shows no folder prompt, the overlay goes to "URL copied", pasting gives the URL, `pending/` is empty afterwards, the Recent Captures row shows the object name (`aSIS7x.png`) and its photo button still copies the image, "Reveal Last Capture" is disabled.
- [ ] Wi-Fi off, capture: overlay "Upload failed" with Retry, `pending/<UUID>.png` exists; Wi-Fi on, Retry Failed Uploads in the menu (or the overlay's Retry): Uploaded, and the pending file is gone.
  (suite: CoordinatorUploadTests.aFailedUploadOnlyImageKeepsItsPendingFileAndSizeUntilARetrySendsIt)
- [ ] Wi-Fi off, capture in upload-only, then set retention to 1 day and wait past it (or change the record's `timestamp` in `history.json` to two days ago before relaunching) and take another capture: the failed upload-only row and its `pending/` file are still there.
  (suite: HistoryStoreTests.pruningKeepsUploadOnlyCapturesThatWereNeverUploaded,
  CoordinatorDeleteTests.pruningRemovesTheFilesAndAsksForNoDestination)
- [ ] Forget Credentials, then capture in upload-only: one "Upload not configured" notification, the image is on the clipboard, the row is Failed and the pending file stays; re-enter credentials, Retry Failed Uploads: Uploaded.
  (suite: CoordinatorCaptureSaveTests.withNoDestinationTwoCapturesCopyTheImageAndPostOneNotice,
  CoordinatorCaptureSaveTests.anUploadOnlyCaptureThatFailsKeepsItsPendingFileUntilARetrySucceeds,
  CoordinatorUploadTests.retryFailedUploadsSaysOnceWithoutCredentialsAndEnqueuesWithThem)
- [ ] "Also copy image" on: paste gives the image until the upload finishes, then the URL. (suite:
  CoordinatorCaptureSaveTests.withAlsoCopyImageTheImageIsOnTheClipboardUntilTheUploadEndsThenTheLink)

## Key templates
- [ ] After updating from Phase 2 with prefix `shots` and length 8 saved, Settings > Upload shows `shots/{random:8}`; after Save, `defaults read ~/Library/Containers/io.tky.tidyshot/Data/Library/Preferences/io.tky.tidyshot.plist s3DestinationConfig` contains `keyTemplate` and no `keyPrefix` or `keyLength`.
  (suite, in part: S3DestinationConfigTests.phase2PrefixAndLengthMigrateToTemplate, .roundTripsThroughJSON,
  ObjectKeyNamerTests.migratedTemplateFromPhase2Settings; the Upload tab showing the template stays by hand, and the
  line's `defaults read` cannot show encoded data: use the `plutil … | base64 -D` form from the Phase 3.1 checklist)
- [ ] Template `shots/{year}/{month}/{hostname}-{random:8}`: the example updates as you type; Save; capture: the URL is `https://snap.tky.io/shots/2026/10/<hostname>-XXXXXXXX.png` with the hostname lowercased, without `.local`, and only `a-z`, `0-9`, `.` and `-` in it (an `_` in the Mac's host name shows as `-`).
- [ ] Template `{date}/{hostname}`: the orange warning appears and says the template has no {random} or {counter}, so captures can produce the same key and only the HEAD check keeps a capture from overwriting an earlier object; Save works; two captures on the same day: the second fails with "Could not find an unused object key after 5 tries." and keeps its file for retry.
- [ ] Settings > Upload with the warning showing: the tab is taller than the 800-point window and scrolls, and scrolling reaches everything down to the Save buttons.
- [ ] Template `my shots/{random}`: red message `" " is not allowed…`; Save shows "Key template: …" and does not save. Template `{foo}`: red `{foo} is not a token.`
- [ ] Save and Test Connection with a folder template: the result is exactly "Upload and public read both work."; afterwards the bucket has no `tidyshot-probe-*.txt` under that folder. With a key or bucket policy that allows writes only under that folder, the test still succeeds. (`ConnectionTesterTests` checks which folder the probe key goes into; do not watch the bucket listing during the test.)
- [ ] File name template `{year}-{month}-{day} {hostname}` names local files as expected; the default template still gives `Screenshot 2026-10-19 at 11.56.03.png`.
  (suite, in part: FileNamerTests.yearMonthDayAndHostnameTokens, .defaultTemplateMatchesSystemStyle; that a real save
  names its file from the template stays by hand)
- [ ] A retried failed upload lands under the capture's own date folder, not today's; with `{counter}` in the key template, the retry's key has a newly drawn counter value, and an upload-only capture taken before a destination existed gets a real counter (not 0) when it is retried.
  (suite: CoordinatorUploadTests.aRetryIsNamedForTheCapturesDateWithANewlyDrawnCounter)

## Forget credentials
- [ ] Forget Credentials: the three fields clear, the status reads "Credentials removed from the keychain…", Keychain Access no longer has "TidyShot S3 credentials"; a capture gives "Upload not configured"; re-enter and Save: uploads work again.
- [ ] Forget Credentials while an upload is running: that upload still finishes (Uploaded, URL copied) and the menu bar icon returns to the viewfinder.
  (suite: CoordinatorUploadTests.forgettingCredentialsMidUploadLetsThatUploadFinish)

## History hygiene
- [ ] Retention 1 day with older captures present, then capture: older rows disappear, their files in `thumbnails/` are gone, and their files in the save folder remain; a failed upload-only capture is kept with its `pending/` file however old it is.
  (suite: CoordinatorDeleteTests.retentionDropsOldRowsAndTheirThumbnailsButKeepsSaveFolderFilesAndUnsentUploads,
  HistoryStoreTests.pruningKeepsUploadOnlyCapturesThatWereNeverUploaded)
- [ ] Quit, replace `history.json` with `not json`, relaunch: `history.json.corrupt-<number>` exists and `thumbnails/` is untouched. With `pending/` empty, Recent Captures shows "No captures yet". With files in `pending/`, each readable one comes back as a row with a `Recovered a capture` (or `Recovered a recording`) notification, and only an empty or unreadable file is removed.
  (suite, in part: HistoryStoreTests.corruptFileIsSetAsideNotOverwritten, .corruptFileSetAsideSurvivesNameCollision,
  CoordinatorRecoveryTests.anEmptyHistoryAdoptsEveryOrphanAndDeletesNothing,
  .anOrphanPNGIsAdoptedWithItsSizeAThumbnailAndANotice, .aZeroByteFileIsRemoved; `start()` running the load and then the
  adoption at launch is not driven, and `thumbnails/` left untouched and the menu's `No captures yet` stay by hand)
