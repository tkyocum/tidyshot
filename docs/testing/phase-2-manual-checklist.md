# Phase 2 manual test checklist

Run after any change to Upload, History, Overlay, or AppCoordinator. Automated tests cover
signing (AWS test suite plus the S3 worked examples), URL building, key naming, the queue,
the keychain store, and history persistence; everything here needs a real bucket and eyes.

Setup: fresh build, Screen Recording granted, save folder set to Desktop, a bucket you can
write to, its public URL base (for example `https://snap.tky.io/`), and an access key pair.

## Upload settings
- [ ] Settings > Upload: Save with an empty endpoint shows "Endpoint must be an http or https URL…" in red. (suite, in
  part: S3DestinationConfigTests.validation; the shown text and the red stay by hand: no test reads the error's message)
- [ ] Fill in endpoint, region, bucket, public URL `https://snap.tky.io/{key}`, access key ID and secret; Save shows "Saved."
- [ ] Quit and relaunch: the fields are filled in again, including the secret (read back from the keychain). (suite, in
  part: AppSettingsTests.s3ConfigRoundTripsThroughDefaults, KeychainCredentialStoreTests.keychainStoreRoundTrips; the
  form filling its fields at relaunch stays by hand)
- [ ] Enter a session token, Save, quit and relaunch: the token field is filled in again; clear it and Save: after relaunch it stays empty.
  (suite, in part: KeychainCredentialStoreTests.keychainStoreRoundTrips; the form turning a cleared field into no token
  stays by hand)
- [ ] Paste a bucket name with a trailing space, Save: the field shows the trimmed name and uploads work. (suite, in
  part: S3DestinationConfigTests.paddedFieldsAreTrimmedNotRejected; the field showing the trimmed name and a real upload
  stay by hand)
- [ ] `defaults read io.tky.tidyshot` does not contain the access key ID or secret.
- [ ] Keychain Access (login keychain) shows an item "TidyShot S3 credentials" with account `default`.
- [ ] Save and Test Connection with correct settings reports "Upload and public read both work." and the probe object is gone from the bucket afterwards.
  (suite, in part: ConnectionTesterTests.readableWhenPutSucceedsAndPublicGetReturnsBody,
  .readableSummaryDoesNotEchoTheProbeURL; the real bucket removing the probe stays by hand)
- [ ] Save and Test Connection with a key that may PUT but not DELETE reports the outcome plus "Probe object … could not be deleted; remove it by hand." in red.
- [ ] Save and Test Connection with a wrong secret reports "Upload failed: Server returned HTTP 403…". (suite, in part:
  ConnectionTesterTests.uploadFailedWhenPutIsRejected; the `Upload failed: ` summary text and a real 403 stay by hand)
- [ ] Save and Test Connection with a public URL template pointing at a domain that does not serve the bucket reports "Upload worked, but the public URL returned HTTP …".
  (suite, in part: ConnectionTesterTests.notPublicWhenGetIsForbidden, .wrongBodyOn200IsNotReadable,
  .unexpectedStatusOnPublicGetIsReportedDistinctly; the test reads only `HTTP 403` in the summary, so the rest of the
  text and a real wrong domain stay by hand)
- [x] Random name length stepper stops at 4 and 32; the example key updates as the prefix and length change. (obsolete:
  the stepper and the prefix field are gone; the key template and `{random:N}` (1 to 64) replaced them, and the 4 to 32
  clamp survives only in the Phase 2 migration)

## Capture and upload (⌃⇧3, ⌃⇧4, ⌃⇧2)
- [ ] After-capture action "Upload and copy URL": capture, wait for the overlay checkmark, paste into Slack or Notes: a working `https://snap.tky.io/XXXXXX.png` link appears, nothing else.
- [ ] From releasing the mouse to a pasteable link takes about two seconds on a normal connection.
- [ ] The menu bar icon shows an up-arrow circle while uploading and returns to the viewfinder afterwards.
- [ ] Notification "Uploaded, URL copied" appears; clicking it opens the URL in the browser.
- [ ] The uploaded object is a PNG with 144 DPI on a Retina display (download it and check with Preview > Tools > Show Inspector).
  (suite, in part: ImageEncoderTests.retinaScaleWrites144DPI; that the uploaded object is that PNG from a real Retina
  capture stays by hand)
- [ ] With "Also copy image" on: immediately after capture, paste gives the image; after the upload finishes, paste gives the URL.
- [ ] With "Send public-read ACL" on, uploads still succeed on a bucket that allows ACLs, and the object is public.
  (suite, in part: S3DestinationTests.aclHeaderIsSentAndSignedWhenEnabled, .fileUploadSignsCacheControlAndACL; the real
  bucket accepting the ACL and the object being public stay by hand)
- [ ] After-capture action "Save and copy image": no upload happens, paste gives the image, and the Recent Captures row shows the time and size with no upload state.
- [ ] Delete the "TidyShot S3 credentials" item in Keychain Access, relaunch, leave the action on "Upload and copy URL", capture twice: one "Upload not configured" notification only, and paste gives the image both times. Settings > Upload then shows empty credential fields and no red keychain error.
- [x] Set key prefix `shots`: new objects land under `shots/` and the URL is `https://snap.tky.io/shots/XXXXXX.png`.
  (obsolete: the key prefix is gone; the template `shots/{random:6}` does this now, and a Phase 2 prefix migrates into a
  template)
- [ ] Path-style on against MinIO (`http://localhost:9000`, region `us-east-1`): upload succeeds. (suite, in part:
  S3DestinationConfigTests.pathStyleURLWithPortForMinIO, S3DestinationTests.headUsesPathStyleAndPortedHost; a real MinIO
  accepting the upload stays by hand)

## Overlay
- [ ] Panel appears in the chosen corner of the display under the mouse, 16 pt from the edges, without taking focus from the frontmost app.
- [ ] Progress ring moves during a large (fullscreen Retina) upload, then shows the checkmark and URL. (suite:
  CoordinatorUploadTests.anUploadShowsItsFractionOnTheCardThenUploaded, QuickAccessModelTests.uploadingShowsTheFraction,
  .uploadedSaysWhetherTheLinkWasCopied)
- [ ] "Copy URL" puts the URL on the clipboard again after something else was copied. (suite:
  CoordinatorRecordActionsTests.copyLinkOrFileCopiesTheLinkEachTimeOrTheSavedFile)
- [ ] Clicking the thumbnail reveals the file in Finder.
- [ ] Auto-close happens 5 s after the upload finishes; with the pointer over the card when the time runs out, the 5 s
  start again; after the pointer leaves, the card closes when the current 5 s run out.
- [ ] Auto-close 0 keeps the panel until the X is clicked.
- [ ] Settings > Overlay off: no panel, uploads still work. (suite:
  CoordinatorSaveTests.aCaptureWithTheOverlayOffShowsNoCardAndStillUploads)
- [x] A second capture replaces the panel with the new capture. (obsolete: with the default settings cards stack newest
  first since Phase 6a; a new capture replaces the old one only with `Show up to 1 overlay`)

## Failures and history
- [ ] Turn Wi-Fi off, capture: the file is saved, the overlay shows "Upload failed" with Retry, a notification appears, Recent Captures shows the item as `Failed`, nothing is on the clipboard unless "Also copy image" is on.
- [ ] Turn Wi-Fi on, click Retry in the overlay: the upload succeeds and the URL is copied. (suite:
  CoordinatorUploadTests.aScreenshotsURLReplacesTheClipboardEvenAfterACopyElsewhere)
- [ ] Recent Captures > Retry Failed Uploads retries every `Failed` item. (suite:
  CoordinatorUploadTests.retryFailedUploadsSaysOnceWithoutCredentialsAndEnqueuesWithThem,
  UploadRefusalTests.retryFailedUploadsLeavesOutMarkedAndDeletingRecords)
- [ ] Clicking an uploaded Recent Captures row copies its URL; clicking a row that was never uploaded copies the file
  (paste in Finder makes a copy). (suite:
  CoordinatorRecordActionsTests.copyLinkOrFileCopiesTheLinkEachTimeOrTheSavedFile)
- [ ] Recent Captures rows show only the object or file name, the relative time, the size and the upload state in words,
  no emoji. (suite: RecentCaptureFormattingTests.nameIsTheObjectOrTheFileName,
  .detailIsTheRelativeTimeAndAnUnsettledState, .detailIsTheTimeAndTheSize, .detailIsTheTimeTheSizeAndEachUploadState)
- [ ] Quit while an upload is in flight (slow connection or large capture), relaunch: the item shows as `Failed` (history.json has "Upload was interrupted.") and Retry works.
  (suite: HistoryStoreTests.uploadingRecordsBecomeFailedOnLoadAndPersist,
  CoordinatorUploadTests.anUploadedUploadOnlyImageMovesToItsDragFolderOnlyWithACard)
- [ ] Wrong secret: the overlay shows "Upload failed … HTTP 403" after one attempt, no retries in the log. (suite:
  UploadQueueTests.doesNotRetryClientErrors, CoordinatorUploadTests.aFailedUploadMarksTheRecordOrReturnsItToItsLink,
  QuickAccessModelTests.failedShowsTheMessage)
- [ ] `~/Library/Containers/io.tky.tidyshot/Data/Library/Application Support/TidyShot/history.json` lists the captures newest first.
  (suite: HistoryStoreTests.addPersistsAndReloadsNewestFirst)
- [ ] Quit, replace history.json with the text `not json`, relaunch: Recent Captures is empty, and `history.json.corrupt-<number>` next to it still holds `not json` after the next capture.
  (suite: HistoryStoreTests.corruptFileIsSetAsideNotOverwritten)
- [ ] With captures older than a day in history, set retention to 1 day and take a capture without relaunching: the older items are gone from Recent Captures, their files are still on disk.
  (suite: CoordinatorDeleteTests.retentionDropsOldRowsAndTheirThumbnailsButKeepsSaveFolderFilesAndUnsentUploads,
  HistoryStoreTests.prunesRecordsOlderThanRetention)
