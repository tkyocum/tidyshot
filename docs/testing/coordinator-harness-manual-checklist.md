# Coordinator harness manual checklist

Run after the coordinator harness phase (`docs/superpowers/specs/2026-10-29-tidyshot-coordinator-harness-design.md`),
and after any later change to `AppEnvironment`, the three protocols (`Notifying`, `QuickAccessCards`,
`Clipboard`), `AppCoordinator+Recovery.swift` or `PendingFileStore.list`. The suite now builds an
`AppCoordinator` over temp folders and fakes and covers the R4 lines the R4 checklist marks `(suite)`; what is
left here needs the real app: the live environment, the container's `pending/` folder, a URL command, and the log.

Read the log with
`/usr/bin/log show --last 10m --style compact --predicate 'process == "TidyShot"' | grep -E "Recovery:|Recording:|Upload:"`.

## Checks

- [ ] 1. The live world is unchanged. Launch a Release build; take a screenshot (⌃⇧4), let it upload, record a
  short area and let it upload: the cards, the notifications, the clipboard (the link replaces it), the shutter
  sound and the log read as before. Delete one of them with `Ask before deleting` on: the alert is the same.
- [ ] 2. `pending/` adoption. Quit TidyShot. Copy any PNG into
  `~/Library/Containers/io.tky.tidyshot/Data/Library/Application Support/TidyShot/pending/` as `<a new UUID>.png`
  (`uuidgen` gives one; keep it upper case). Launch: `Recovered a capture` posts with the file's name, the row is
  in Recent Captures with the image's size, the log says `Recovery: <name> recovered`, Annotate opens it, and
  Delete removes the row and the file. Repeat with a short MP4 as `<UUID>.mp4`: `Recovered a recording` with its
  length (`m:ss`). A zero-byte `<UUID>.png` is removed at launch with `Recovery: <name> is empty, removed`; a file
  named `notes.png` is left alone.
- [ ] 3. A `record-screen` URL still starts a selection, and `urlRecordingStartPending` clears: send
  `open 'tidyshot://record-screen'`, press Escape, then send it again: a second selection shows. (Test 53 covers
  every refusal; the successful start reaches ScreenCaptureKit.)
- [ ] 4. `stop-recording`'s log lines in each phase (R4 checklist :178-186) read as they did: the suite pins the
  state, not the `RecordingLog` text, and tests 48 and 50 cannot tell the coordinator's own do-nothing branches from
  the recorder's (plan D24), so the `did nothing` lines are the check. (suite:
  CoordinatorRecordingTests.stopRecordingLogsWhatItDidInEachPhase)
- [ ] 5. Both recoveries in one launch (plan D27). Start a recording, `kill -9` TidyShot mid-recording, copy an orphan
  `<UUID>.png` into `pending/` as in check 2, launch: `Recovered a capture` and `Recovered a recording` both post,
  the log has `Recovery: <name> recovered` and the recording's `Recording:` lines, and nothing is removed as
  unplayable. Start a recording within a few seconds of launch with several large orphans in `pending/` if you can:
  it is left alone (no test pins the order; `start()` touches the globals the harness keeps out).
- [ ] 6. The two log-only lines the suite cannot read (plan D20, D22). With `Count down before recording` off, press
  the record shortcut in the settle delay: the log says `Recording: not started, the count-in was cancelled`
  (R4 checklist :217). Quit while the Save Location's folder chooser is open: the panel closes and
  TidyShot quits (the suite cannot see `saveLocation.cancelFolderChoice()`).

## The design's calls, to confirm or overrule

The design lists them in section 9. Write `confirm` or `overrule` and why; an overrule goes in its built notes.
- [ ] 1. `AppEnvironment` as one struct with `.live()` and `init(environment:)`; `shared` unchanged. (suite, in part:
  CoordinatorWorldTests.aCoordinatorOverTheWorldKeepsToTheWorld; that `.live()` and `shared` are unchanged stays a code
  read) ______
- [ ] 2. `Notifying`, `QuickAccessCards`, `Clipboard` and `DeleteConfirmation`; the live types conform unchanged.
  (suite, in part: CoordinatorWorldTests.aCoordinatorOverTheWorldKeepsToTheWorld,
  CoordinatorDeleteTests.deleteAsksOnceAndASecondDeleteWhileItAsksAsksNothing; that the live types conform unchanged
  stays a code read) ______
- [ ] 3. `Destination` gains the two downloads; the coordinator's upload signatures carry the location and the key
  template with the destination. (suite, in part:
  CoordinatorDragOutTests.aDragOfAShowingUploadedRecordingStartsOneDownload,
  CoordinatorUploadTests.aFailedUploadMarksTheRecordOrReturnsItToItsLink,
  CoordinatorWorldTests.aCoordinatorOverTheWorldKeepsToTheWorld; `download(key:)` has no coordinator test, and the
  signatures are a code read) ______
- [ ] 4. Every coordinator log line through the environment, live `NSLog("%@", …)`; `RecordingLog.note` stays. (suite,
  in part: CoordinatorDeleteTests.anAbortThatFindsNothingIsNotRepeatedAndLogsItGone,
  CoordinatorRecoveryTests.aZeroByteFileIsRemoved; the live `NSLog("%@", …)` sink and `RecordingLog.note` staying are a
  code read) ______
- [ ] 5. No `private` member opened for tests; `record()` not driven; `recordingProceeds` extracted. (suite, in part:
  CoordinatorRecordingTests.recordingProceedsOnlyWhenStartedNotQuittingAndNotCancelled; no `private` member opened and
  `record()` not driven are a code read) ______
- [ ] 6. The fifty-six tests are this phase's set; the rest of the catalogue waits. ______
- [ ] 7. `pending/` orphans adopted, never deleted; by record id; listed in `start()` before any task; one task,
  the `tmp/Recording` scan first, then `pending/` (D27). ______
- [ ] 8. An adopted image or recording gets `.none` and `fileIsTemporary`. (suite:
  CoordinatorRecoveryTests.anOrphanPNGIsAdoptedWithItsSizeAThumbnailAndANotice, .anOrphanMP4IsAdoptedWithItsLength)
  ______
- [ ] 9. The three-file queue split with 24 widenings. ______
- [ ] 10. `multipart upload already gone` for a 404. (suite:
  CoordinatorDeleteTests.anAbortThatFindsNothingIsNotRepeatedAndLogsItGone,
  UploadQueueTests.aSinglePutJobsAbortThatFindsNothingIsLoggedAsGone,
  .aMultipartJobsAbortThatFindsNothingIsLoggedAsGone) ______
- [ ] 11. `PartSender.send` checks for a cancel first; `createUpload` aborts the fresh id when the first sidecar
  write fails. (suite: UploadQueueTests.aPartAddedAfterACancelSendsNothing,
  .aNewUploadWhoseFirstSidecarCannotBeWrittenIsAborted) ______
- [ ] 12. The 20 interpolating `NSLog` lines outside the coordinator stay (5.5). A `%` in an interpolated error text is
  undefined behaviour in NSLog's format, so a crash is possible, not only a garbled line. ______

## The plan's decisions, to confirm or overrule

The plan lists them at its end (`docs/superpowers/plans/2026-10-29-coordinator-harness.md`, Plan decisions). Most
are internal; these change what a user could see or what Tim decided before:
- [ ] D11. A GIF in `pending/` is read with ImageIO, not `VideoValidation` (which would find every GIF unplayable
  and remove it); an empty file logs `is empty, removed`. (suite:
  CoordinatorRecoveryTests.anEmptyHistoryAdoptsEveryOrphanAndDeletesNothing, .aZeroByteFileIsRemoved) ______
- [ ] D12. Test 46 pins that pruning closes no card (the design's line said it does; the code never did). Ruled
  before Task 7; write the ruling here. (suite: CoordinatorDeleteTests.pruningRemovesTheFilesAndAsksForNoDestination;
  the ruling itself is Tim's to write) ______
- [ ] D14. Test 27 follows the code's titles: `Upload failed` with the error for a capture with no link, `Not
  uploaded` with the replace's text for one with a link. (suite:
  CoordinatorUploadTests.aFailedUploadMarksTheRecordOrReturnsItToItsLink) ______
- [ ] D27. `start()`'s one task runs `RecordingRecovery.begin` (the `tmp/Recording` scan) first, then
  `adoptPendingFiles`, then `recoverRecordings`; the design's 4.2 had adoption first. The change keeps a recording
  started while adopting runs from being scanned and removed as unplayable. It is a change to the design's literal
  order, so it is yours to confirm. ______

## Observations
Write into the design's built notes: anything above that failed, and each call and decision confirmed or overruled.
