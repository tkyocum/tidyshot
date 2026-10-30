# TidyShot Coordinator Harness and Close-out, Design

Date 2026-10-29. Branch `coordinator-harness`, cut from `main` at 6a52a7c (R4 merged). Line numbers are from that commit. The research behind this design was done in `.superpowers/sdd/harness/` (local scratch, not in the repository); this document restates everything it uses from it. The coordinator split design (`2026-10-23-coordinator-split-design.md`) describes the file layout this builds on; the recording designs (R1 to R4) and the screenshot design hold the rules the tests below pin.

## 1. Goal

Every phase so far has said the same thing about `AppCoordinator`: its rules are tested only through pure `static` helpers, and the wiring (which collaborator is called, in what order, with what, and what state is left) goes to Tim's checklist. The R4 design names six such paths outright ("Untested by design", line 468); the earlier phases imply about twenty more. No test constructs an `AppCoordinator`, because `init()` takes nothing and builds the real history file, the real notification center, the real card stack and the real Keychain store.

This phase has three parts:

1. **A harness.** `AppCoordinator` takes its world as a parameter, so a test builds one over temp folders, a fresh `UserDefaults` suite, an in-memory credential store, a fake card stack, a fake notifier, a fake clipboard, a fake destination and a captured log. The R4 paths, and the cheapest of the earlier ones, become tests. Behaviour does not change: the live world builds exactly what `init()` builds today.
2. **The `pending/` launch step.** R1 left "a launch sweep of `pending/` for files no record names" unbuilt. It is built as a recovery, not a deletion: an orphan gets a record, as a leftover recording in `tmp/Recording` does today.
3. **Close-out of what the R4 reviews left.** `UploadQueue.swift` splits into three files; the `multipart aborted` line tells a 204 from a 404; the coordinator's log lines stop interpolating into `NSLog`'s format string; a cancel during the single-PUT abort gets its test; and two small queue findings are fixed.

Nothing here needs a probe, a camera, a microphone, the screen or the bucket. Tim's hand checks for this phase are short (section 8).

## 2. The harness

### 2.1 `AppEnvironment`

A struct in `TidyShot/App/AppEnvironment.swift`, the shape `RecordingEnvironment` already has (a struct of values and closures with a `.live` builder). `AppCoordinator.init(environment: AppEnvironment = .live())` replaces `init()`; `static let shared = AppCoordinator()` keeps the default **(the design's call)**. Its members, and what each replaces:

| member | type | today | live value |
|---|---|---|---|
| `historyFileURL` | `URL` | `HistoryStore.defaultFileURL()` with the tmp fallback (AppCoordinator.swift:263-264) | the same |
| `temporaryDirectory` | `URL` | `FileManager.default.temporaryDirectory` (:269, and `DragDownloadRule.partialFile`'s default) | the same |
| `settings` | `AppSettings` | `AppSettings.shared` (:14, :26, :265) | `AppSettings.shared` |
| `saveLocation` | `SaveLocation` | `SaveLocation()` (:13) | `SaveLocation()` |
| `credentialStore` | `any CredentialStore` | `KeychainCredentialStore()` (:23) | the same |
| `notifier` | `any Notifying` | `Notifier()` (:24) | `Notifier()` |
| `overlay` | `any QuickAccessCards` | `QuickAccessController(settings:)` (:26) | the same, with `settings` |
| `clipboard` | `any Clipboard` | `Pasteboard.*` and `NSPasteboard.general.changeCount` | `SystemClipboard()` |
| `makeDestination` | `@Sendable (S3DestinationConfig, AWSCredentials) -> any Destination` | `S3Destination(config:credentials:)` at five sites | the same |
| `multipartPlan` | `MultipartPlan` | `UploadQueue`'s default `plan` in `makeLane` | `.standard` |
| `uploadSleep` | `UploadQueue.Sleeper` | `UploadQueue`'s default `sleep` (the lane's backoff) | `{ try await Task.sleep(for: $0) }` |
| `freeBytes` | `@Sendable (URL) -> Int64?` | `RecordingLimits.freeBytes(at:)` (+DragOut:103, +Recording, +Trim) | the same |
| `confirm` | `@MainActor (DeleteConfirmation) async -> Bool` | `confirmDelete` and `confirmRemoveFromHistory` (+Delete:230, :249) | the two `NSAlert` bodies, moved |
| `playShutter` | `@MainActor () -> Void` | `SoundPlayer.playShutter()` (+Save:127, :209, +Capture:287) | the same |
| `now` | `@Sendable () -> Date` | `Date()` (+DragOut:123, +Editor:212, +RecordActions:322, +Trim:307, AppCoordinator.swift:290) | `{ Date() }` |
| `clock` | `any ScrollClock` | `Task.sleep` (+DragOut:262, +Upload:78, +Recording:509, AppCoordinator.swift:466) | `SystemScrollClock()` |
| `log` | `@Sendable (String) -> Void` | `NSLog(...)` in every coordinator file | `{ NSLog("%@", $0) }` |

The coordinator keeps its stored properties and their names (`history`, `overlay`, `notifier`, `settings`, `saveLocation`, `credentialStore`, `dragFiles`, …), built from the environment in `init`, so the extension files change only where they touched a global directly. `thumbnails`, `pendingFiles` and `multipartFiles` stay derived from `historyFileURL` as today; `dragFiles` from `temporaryDirectory`. `engine`, `permissionWindow`, `clopOptimiser`, `selector`, `scrollCapture`, `urlCommands`, `selfTimer`, `recorder`, `microphones`, `cameras`, `covers`, `pins` are unchanged: their inits touch nothing, and the lazies are already assignable from a test (`recorder`, `microphones`, `cameras`, `selfTimer` have fakes).

What is not in the environment, on purpose: `NSWorkspace` (open, reveal; +RecordActions, +Capture), the Save As panel, `saveLocation.chooseFolder`, `ScreenCapturePermission.isGranted`, `NSScreen`, `KeyboardShortcuts`, `ProcessInfo` activities, `RecordingLog.note`, and the directory statics `ClopApp.workDirectory`, `RecordingTrim.directory`, `Recording.directory`, `MuteLog.directory`. No test in this phase drives a path that reaches them, except `ProcessInfo` (harmless) and `RecordingLog` (a log the tests cannot read; those rules are asserted on state). They are listed in Deferred as the seams a later phase adds when it needs them.

### 2.2 The three protocols

Each names the members the coordinator calls today, no more, and the concrete type conforms unchanged:

- **`Notifying`** (`TidyShot/Output/Notifier.swift`): `setUp()`, `notifySaved(fileURL:title:)`, `notifyUploaded(url:copied:)`, `notifyError(_:title:subtitle:revealing:)`, `notify(title:body:subtitle:openURL:)`, `holdNotices()`, `releaseHeldNotices() -> Int`, `waitForReleasedNotices(upTo:) async`. The default arguments move to protocol extensions so call sites do not change.
- **`QuickAccessCards`** (`TidyShot/Overlay/QuickAccessController.swift`): `windowNumbers`, `shownIDs`, `screen`, `onDidClose` (settable), `isShowing(recordID:)`, `show(record:thumbnail:screen:autoCloseSeconds:actions:)`, `update(record:)`, `setOptimizing`, `setDownloading`, `setLinkWasCopied`, `setTrimState`, `setThumbnail`, `setDragFile`, `close(recordID:reason:)`. `QuickAccessController.Actions` stays where it is.
- **`Clipboard`** (`TidyShot/Output/Pasteboard.swift`): `changeCount`, `setString(_:)`, and the `Pasteboard` statics the coordinator calls (`copy(image:pngData:scale:)`, `copy(pngData:tiffData:)`, `copy(tiffData:)`, `copy(fileURL:)`, `copy(url:)`, `copy(annotationClip:)`, `annotationClipData()`), each returning the change count as today. `SystemClipboard` forwards to the `Pasteboard` enum and `NSPasteboard.general`; the pure helpers (`includesTIFF`, `companionTIFF`, `tiffData`) stay static.

`DeleteConfirmation` is an enum: `.delete(CaptureRecord)` and `.removeFromHistory(message: String, informativeText: String)`. The live `confirm` runs the two alert bodies as they are, `RunLoop.main.perform` included.

`Destination` (the protocol the queue already uses) gains the two members the coordinator calls on `S3Destination` outside it: `download(key:) async throws -> Data` and `download(key:to:expectedBytes:resumeData:progress:) async throws`. `S3Destination` already has both. The coordinator's signatures that carry `S3Destination` (`makeDestination() -> S3Destination?`, `startUpload(... destination:)`, `startPlannedUpload`, `retry`, `makeLane`, `persist`, `downloadSource`) become `any Destination`; `makeLane` reads the config from the `ObjectLocation` it is given instead of `destination.config`, so `startUpload` takes `(destination: any Destination, location: ObjectLocation, keyTemplate: String)` from `makeDestination()`, which returns the triple **(the design's call)**. Nothing else about uploads changes.

### 2.3 Logging

Every `NSLog` in `TidyShot/App/AppCoordinator*.swift` becomes `log(...)` on the environment (the coordinator exposes it as `func log(_ message: String)`). The live sink is `NSLog("%@", message)`, which is also the fix for the R4 review's "two NSLog lines that interpolate error text": every coordinator line now goes through `%@`, so an error message containing `%` can no longer be read as a format. `RecordingLog.note` is left as it is (it is a `Logger` with its own category, used by the driver and the controller too); the tests of the recording commands assert state, not those lines.

### 2.4 What a test can now do

In `TidyShotTests/Support/CoordinatorFakes.swift`:

- `FakeNotifier: Notifying` records every call as a value (`.error(title, message)`, `.uploaded(url, copied)`, `.held`, `.released`, `.waited(limit)`), on the main actor.
- `FakeCards: QuickAccessCards` records calls (`.show(id)`, `.update(id)`, `.downloading(id, status)`, `.dragFile(id, url)`, `.close(id, reason)`, …) and holds a settable `showing: Set<UUID>` so `isShowing` and `shownIDs` answer what the test wants; `screen` is nil; `windowNumbers` empty.
- `FakeClipboard: Clipboard` holds a `changeCount` the test can bump and records what was copied.
- `FakeDestination` moves from `UploadQueueTests.swift` to `Support/FakeDestination.swift` unchanged, and gains: a scripted `download(key:to:expectedBytes:resumeData:progress:)` (writes a file of a given size at `to`, reports a list of fractions, or throws a scripted error, or sleeps until cancelled; records `resumeData` and the key), a scripted `download(key:)`, and `blockingAbortsRemaining` (an Abort that sleeps until cancelled, the `blockingUploadsRemaining` pattern) for the cancel-during-abort test.
- `CoordinatorWorld`: builds the temp folders (`<tmp>/CoordinatorWorld-<uuid>/` with `history.json`'s folder and a `tmp/` for `temporaryDirectory`), a `UserDefaults` suite named after the test, `AppSettings(defaults:)`, `SaveLocation(defaults:)`, an `InMemoryCredentialStore` with credentials stored, the fakes above, `FakeScrollClock` as `clock`, a settable `date` for `now`, a `[String]` log, a factory that hands out one `FakeDestination` (or a scripted one per config) and records the configs asked for, and `freeBytes` as a settable number. `makeCoordinator()` returns an `AppCoordinator(environment:)` over them; `removeAll()` deletes the folders. The suite's `init` builds a world and each test `defer`s the removal, the idiom `DragDownloadTests` uses.
- The recorder: a test that needs a running recording assigns `coordinator.recorder = RecordingController(environment: RecordingTestWorld().environment, makeDriver: { FakeRecordingDriver(...) })` before anything touches the lazy, and `coordinator.microphones`/`cameras` the existing fakes.

Waiting: the coordinator's unstored `Task`s (the drag-out download, `startUpload`'s wait task, the queue's events) are observed with the existing `eventually {}` on state (`history`, the fake's calls, the id sets). The drag-out download's task is stored in `downloadingDragIDs`, so its value can be awaited directly. Sleeps go through `clock`, so `destinationDidChange`'s 500 ms poll and the drag clean-up's 60 s wait are driven by `advance(by:)`.

Access: no `private` member is opened for the tests. `handle(_:at:)` is driven through the real `UploadQueue` over the fake destination; `finishDragDownload` through `downloadDragFile`; `record()` is not driven at all (section 5). `isQuitting` is reached through `finishRecordingForQuit()`.

Parallelism: Swift Testing runs suites concurrently. Each coordinator has its own folders, defaults suite and fakes, and never touches `AppSettings.shared`, `NSPasteboard.general`, the Keychain, a window or the notification center, so the new suites run beside the rest with no `.serialized`.

## 3. The tests this phase writes

Each suite is `struct <Name>: ` in `TidyShotTests/`, named as the catalogue below. A rule's source is the phase that wrote the hand check; the R4 checklist lines a test replaces are in section 8. The pure helpers these paths use (`DragDownloadRule`, `MultipartPlan`, `RecordingSavePlan`, the `AppCoordinator` statics) keep their own tests.

### 3.1 `CoordinatorDragOutTests` (R4 Drag-out download; the design's `finishDragDownload` three-way choice and resume wiring)

1. A drag of an uploaded recording with no local file whose card shows starts one download: the destination's `download` is called with the record's key and nil resume data, `downloadingVideoIDs` holds the id, and the card got `.running(0)`.
2. With no card showing the record, nothing starts (`DragDownloadRule.starts` is tested on its own; this pins the coordinator's `isShowing` read).
3. With `freeBytes` under the record's size plus the margin, the card gets `.failed(RecordingLimits.diskFullText)`, the log has `Drag-out download for <id> refused, not enough disk space`, and nothing starts.
4. With no credentials stored, the card gets `.failed(<notConfigured text>)` and the log `Drag-out download for <id> failed: …`.
5. Success: the file is adopted at `Drag/<id>/<DragFileName.name>`, the card got `.running(…)` fractions then nil then `setDragFile(url)`, the task's value is that url, and both id sets are empty.
6. A cancel while the transfer runs (`cancelDragDownload`, or `overlayDidClose(id, .user)`), when the fake then completes with success: the landed file is removed, the card's status is nil, the log has `Drag-out download for <id> cancelled`, no drag file is set.
7. A `removeDragFolder` during the transfer (the generation bumped) gives the same outcome.
8. A failure with a `URLError` carrying `NSURLSessionDownloadTaskResumeData`: the card gets `.failed(<description>)`, the log `… failed: …`, and `dragDownloadResume[id]` holds that data with `signedAt` equal to the world's `date` at the start.
9. A failure without resume data (an `UploadError.httpStatus`) keeps nothing.
10. A failure after a cancel: status nil, `cancelled` logged, nothing kept.
11. The next drag within the window (`date` advanced 839 s) passes the kept data to `download`, keeps the first `signedAt`, logs `Drag-out download for <id> resumed at <fraction>` once on the first fraction, and shows every fraction.
12. The next drag past the window (`date` advanced 840 s) passes nil, signs afresh (`signedAt` is the new `date`), logs no `resumed at`, and the partial file the kept data names (a `CFNetworkDownload_*` file the test writes in the world's `temporaryDirectory`) is removed.
13. `cancelDragDownload` with kept resume data removes the partial file, drops the entry and clears the card's status.
14. A fraction that arrives after the download ended does not put the ring back (the fake reports a late fraction after completing; the card's last status is nil).
15. `removeRecord` cancels a running download and the record's drag folder is gone.
16. A second drag while one runs starts no second `download` (one call on the destination).

### 3.2 `CoordinatorUploadTests` (R4 Multipart, Resume; the `.started` fraction; R1 clipboard rule; Phase 3 cancel and draining)

Setup: a recording in a temp save folder (sparse, over a 1 MiB test threshold via `MultipartPlan(threshold:partSize:inFlight:)` handed to `makeLane` through the environment's `multipartPlan`, as `UploadQueueTests` does) or a record with a stored `multipart` state, `optimiseWithClop` off, a `MultipartStore` in the world's folder with a sidecar where the test needs one.

17. A stored multipart upload whose source still matches (same size and modification date) resumes: the destination sees no Create, ListParts is not needed (the sidecar lists the parts), the missing parts are sent, Complete is called; no counter is drawn (`settings.currentCounter` unchanged); `sentByteCounts[id]` is the state's `byteCount`.
18. When the resume's `.started(fraction:)` arrives, `history.record(id).uploadState` is `.uploading(fraction: <done fraction>)` and the card got `update(record:)` with that fraction (the R4 design's "the bar at that fraction at once").
19. A `.started(attempt: 2)` (a screenshot's single PUT that the fake fails once, `RetryPolicy` with one retry, `sleep` injected) logs `Upload retry 2 for <id>`.
20. A stored upload at another location: the log has `Upload: <name> destination changed, starting again`, the factory was asked for the old location's config and that destination got two `abort`s (a 204 is repeated, test 38), and the new job carries no `abortFirst` (the new destination sees Create before any `abort`).
21. A source whose size changed: `Upload: <name> source changed, starting again`, and the new destination sees `abort` for the stored id before `create`.
22. A fixed key different from the stored key: `key changed, starting again`.
23. A kept Clop copy in `multipart/` whose record file is newer than `startedAt` counts as changed (`keptCopyIsOutdated`): `source changed`.
24. `.uploaded` for a recording whose clipboard count is unchanged since the save (`videoClipboardCounts[id] == clipboard.changeCount`): `clipboard.copy(url:)` was called, `notifyUploaded(copied: true)`, `linkNotCopiedIDs` does not hold the id. With the count moved on: no copy, `notifyUploaded(copied: false)`, `linkNotCopiedIDs` holds it.
25. `.uploaded` clears `record.multipart`, removes the sidecar and the kept copy from `multipart/`, and stores `byteCount` as the sent size.
26. `.uploaded` for an upload-only image with a card showing moves `pending/<id>.png` to `Drag/<id>/<key name>` and hands it to the card; with no card, the pending file is removed and `fileURL` is nil.
27. `.failed` with no prior link marks the record `.failed(message)` and posts `Upload failed` with the error; with a `priorUpload` the record returns to the earlier link, `uploadIsStale` stays, and the notice is `Not uploaded` with `Upload failed. The link still shows the earlier image.`
28. `cancelUpload` of a record in the resume/size wait (`optimisingIDs` holds it): the token is gone, the record reads `Upload cancelled.`, the queue got no cancel.
29. `cancelUpload` of a queued job: the lane's cancel runs, the record's `pendingObjectKey` is the reserved key, `fileUploadIDs` is empty.
30. `destinationDidChange` moves the lane to `drainingQueues` and drops it once idle and no Clop wait remains (the clock advanced through the 500 ms poll).
31. `retryUpload` of a trimming record posts `Not uploaded` with `This capture is being trimmed.` and reads no destination; of a record already uploading, nothing.
32. `retryFailedUploads` with two failed records and no credentials posts one `Upload not configured`; with credentials, both are enqueued.
33. `warnUploadNotConfiguredOnce` posts once per coordinator.
34. `startUpload` of a refused record (marked sound) logs `Upload: refused for <name>: …` and changes nothing.

### 3.3 `CoordinatorDeleteTests` (R4 Delete and `abortUploads`; Phase 3 delete order; prune)

35. `abortUploads([])` returns nil and asks the factory for nothing.
36. A Keychain read that throws returns `Could not read S3 credentials from the keychain: …` and logs `Upload: <name> multipart abort failed: …`.
37. No stored credentials returns `No credentials are saved in Settings > Upload.` with the same log.
38. A 204 (`.aborted`) is followed by one more Abort of the same id, and the log has `Upload: <name> multipart aborted`.
39. A 404 (`.notFound`) is not followed by a second Abort, the log has `Upload: <name> multipart upload already gone` (section 6), and the result is nil.
40. A throw returns its description at once; a later ref is not tried.
41. Each ref is aborted at the location it was created in: the factory saw each ref's config, not the current Upload settings.
42. `deleteCapture` of an uploaded record with `confirmBeforeDeleting` on asks `.delete(record)` once; a second `deleteCapture` while the first waits asks nothing; `deletingIDs` is empty after.
43. An abort failure asks `.removeFromHistory(message:informativeText:)` with the reason and `The object stays in the bucket.`; a No keeps the record and deletes no object; a Yes removes the record and its pending file.
44. A record whose key another record shares: the object is kept, `Not deleted from storage` posts, the record goes.
45. A pending file that cannot be removed (the folder made read-only, the `PendingFileStoreTests` idiom) keeps the record and posts `Not deleted`.
46. `removeFiles(ofPruned:)` removes the thumbnail, the pending file, the sidecar and kept copy, closes no card (the code never did; D12) and asks the factory for no destination.
47. `removeRecord` clears `optimizingVideoIDs`, `fileUploadIDs`, `videoClipboardCounts`, `linkNotCopiedIDs`, `copyFileCounts` and `dragDownloadResume` for the id.

### 3.4 `CoordinatorRecordingTests` (R4 `stop-recording` and `record-screen`; R3 Settings prompts; R1 quit)

48. `stopRecordingCommand` while idle or saving (`recordingSavesInFlight` 1) changes nothing: no flag, no `recorder.stop()`, no notice.
49. During a count-in (`recordingCountIn` true) it sets `recordingStartCancelled` and cancels the self-timer (a `SelfTimerController` over a `FakeScrollClock`, mid-countdown).
50. During a recording (a `RecordingController` over `FakeRecordingDriver` running a request) it calls `stop()`: the driver's `stopCount` is 1; a second command while `isEnding` adds none.
51. `recordingStartCancelled` resets when `recordingCountIn` goes from false to true, and stays when it goes true to true.
52. The pure `AppCoordinator.recordingProceeds(started:isQuitting:cancelled:)` (extracted from +Recording:399-405): `.start` when started and neither flag; `.stop(logsCancel: true)` when started, not quitting and cancelled; `.stop(logsCancel: false)` otherwise. `record()` reads it; its own body is unchanged otherwise.
53. `startRecording(intent:preselect:)` during a count-in, a recording, or with a prompt open returns without setting `urlRecordingStartPending`; with the flag already set it returns and sets nothing else; while quitting it returns. (The successful start reaches ScreenCaptureKit and is not driven; the flag's clearing stays a hand check, section 8.)
54. `requestAccessFromSettings(.camera)` while idle with the camera `.notDetermined` asks the fake cameras once, with `askingPermission == .camera` while the ask is held and nil after; while a capture holds the lock it does not ask; while the microphone prompt is open it does not ask.
55. While a prompt is held open, `captureRefusal` is `.permissionPrompt` and `capturesRefused` is true; after the answer both clear.
56. `finishRecordingForQuit` sets `isQuitting`, cancels the self-timer, calls `recorder.quit()`, `saveLocation.cancelFolderChoice()`, and `notifier.waitForReleasedNotices(upTo:)` once the phase is idle.

Fifty-six tests. `endNoticeHold`'s `posted <n> notifications` line is not among them: it is `private`, its hold rule (`NoticeHold`) has its own tests, and no private member opens for a test **(the design's call)**. Each test's doc comment names the design section and, where there is one, the checklist line it replaces.

## 4. The `pending/` launch step

### 4.1 What is there today

`pending/` (`PendingFileStore`, next to `history.json`) holds every file TidyShot keeps for itself: an upload-only screenshot's PNG, a recording with no save folder or whose folder move failed, a trim's new file, an edited image kept with `keepsUnuploadedEdit`, and a recovered recording. Every file is `<record id>.<png|mp4|gif>`. Six writers, all with the record's id as the file's stem; three of them (a recording's save, a trim's write, launch recovery) have a window across a hop to the main actor in which the file is in place and no record names it. A `kill -9` in that window, or between a screenshot's write and `history.add`, leaves a file nothing names (R1, The tmp file, line 217: "nothing finds it"). Phase 3 decided against a deleting sweep (plan line 140): an empty history after a corrupt file was set aside would delete captures never uploaded. `HistoryStore.load()` gives no signal that it set a file aside.

### 4.2 The rule

An orphan is adopted, never deleted **(the design's call)**. The rule is the one `recoverRecordings` applies to `tmp/Recording`:

- **Listing.** `PendingFileStore.list() -> [URL]` (new; a missing folder lists nothing; hidden files skipped). `start()` lists `pending/` synchronously, right after `history.load()` and before any `Task` starts, and hands that list to the recovery task. A file written after the list is never considered, so the writers that run after `start()` returns (a capture, `recoverRecordings` itself, a URL command) cannot race it, the pattern `RecordingRecovery.begin` and `MultipartStore.sweep` use.
- **Deciding.** `PendingRecovery.orphans(listed: [URL], recordIDs: Set<UUID>) -> [PendingRecovery.Found]` (`TidyShot/Output/PendingRecovery.swift`, `nonisolated enum`, pure): a listed file whose name is `<UUID>.<ext>` with `ext` one of `MediaKind`'s extensions and whose UUID is no record's id. Any other name is left alone. The check is by record id, not by `fileURL`, so a trim's window (the record exists, `fileURL` not yet set) and an edit kept under its own record are both kept, and a record's `fileURL` spelling never matters.
- **Adopting.** `adoptPendingFiles(_ listed:)` in `TidyShot/App/AppCoordinator+Recovery.swift` (new; `recoverRecordings` moves there from +Recording, byte for byte, with the split design's argument). It re-reads `history.records` at adoption time and re-applies `orphans` (a record added since drops the file from the set), then for each orphan, in name order:
  - A `.png`: decoded off the main actor (`CGImageSource`, as `loadImage` does); the record is `CaptureRecord(id:, timestamp: the file's creation date, fileURL:, fileIsTemporary: true, pixelWidth:, pixelHeight:, appName: nil, uploadState: .none, byteCount:)`; `history.add`; `makeThumbnail(from:for:)`. A file that does not decode is removed and logged `Recovery: <name> could not be read, removed`.
  - A `.gif`: read with ImageIO (its size, first frame and the sum of its frames' delays as `durationSeconds`), since AVFoundation does not open a GIF and `VideoValidation` would find every one unplayable; the record `recoverRecordings` builds, with `mediaKind: .gif`; `history.add`; the first frame as its thumbnail. One that does not decode is removed and logged the same way.
  - A `.mp4`: `VideoValidation.inspect` as `recoverRecordings` uses it; playable gets the record `recoverRecordings` builds (`mediaKind` from the extension, `durationSeconds`, `byteCount`, no `unmutedIntervals`: a file in `pending/` has been through its mute step already, if it had one), `history.add`, the poster thumbnail. Unplayable is removed and logged the same way.
  - A zero-byte file of any kind is removed and logged `Recovery: <name> is empty, removed`. A removal that fails logs `Recovery: <name> <reason>, and could not be removed: <error>` (`<reason>` is `is empty` or `could not be read`) and leaves the file.
  - Each adopted file logs `Recovery: <name> recovered` and posts `Recovered a capture` / `Recovered a recording` with R1's body (`<file name>, <m:ss>. Find it in Recent Captures.`; for an image, `<file name>. Find it in Recent Captures.`), through `notifyError` as R1's recovery does, no card.
- **Order at launch.** `start()` runs one task: `RecordingRecovery.begin` (list `tmp/Mute`, scan `tmp/Recording`) first, at launch as before, then `adoptPendingFiles(listed)`, then `recoverRecordings(begun)` with the scan's result. The two recoveries never interleave, and `pending/` is adopted before any scanned file moves into it or is checked against the records. The scan runs at launch, before adopting, because adopting reads each orphan off the main actor and can take seconds while shortcuts are already registered: a scan that ran after it would list a recording started in that window and remove it as unplayable mid-write (D27). Nothing else in `start()` moves.
- **The adopted record.** `.none`, `fileIsTemporary: true`, so `HistoryStore.pruned` keeps it (`isPendingOnly`) until the user acts: Annotate, Save As, Delete on its row; a video's Trim; an image's upload from the editor. This is what R1 gives a recovered recording, and the same stance (a file on disk is the only copy; TidyShot keeps it and says so).

### 4.3 Tests

`PendingRecoveryTests` (pure): a `<UUID>.png` with no record is an orphan; `.mp4` and `.gif` too; a file whose UUID is a record's id is kept; a name that is not `<UUID>.<ext>` (a `.atomic` temp sibling, a hidden file, `<UUID>.txt`) is left; the result is in name order. `PendingFileStoreTests` gains `list` (a missing folder, an empty folder, hidden files skipped). `CoordinatorRecoveryTests` (harness): an orphan PNG is adopted with a record of its pixel size and byte count, a thumbnail and a notice; an orphan MP4 (a `VideoFixtures` movie) is adopted with its duration; a zero-byte file is removed; a file whose record was added after the listing is left alone (add the record between listing and adopting); a file not in the listing is left alone; a file that does not decode is removed and logged; an empty history adopts every orphan and deletes nothing.

## 5. Close-out

### 5.1 `UploadQueue.swift` split

`UploadQueue.swift` (762 lines) splits into three files, as `S3Destination` is split, with no body changes and no renames; the split design's section 2 argument applies (a moved body sees a subset of what it saw; a missed widening is a compile error). The pure-move check from that design's section 5 is run on the family against `git show 6a52a7c:TidyShot/Upload/UploadQueue.swift`.

- `UploadQueue.swift` (about 290 lines): the header, the typealiases, `SecurityScope`, `ProgressThrottle`, `CancelResult`, `JobOutcome`, the stored state and `init`, `isIdle`, `enqueue`, `cancel`, `drain`, `process`, `fileName`, `uploadFile`, and the shared helpers `abortUpload`, `withRetries`, `throttledProgress`, `deliverCancelled`, `objectKey`, `reserveKey`, `ProgressGate`.
- `UploadQueue+Multipart.swift` (about 210): `MultipartStep`, `Restart`, `MultipartTarget`, `MultipartPass`, `processMultipart`, `createUpload`, `resumeUpload`, `reserveAgain`, `mebibytes`.
- `UploadQueue+Parts.swift` (about 225): `PartFailure`, `partList`, `listParts`, `sendParts`, `complete`, `readPart`, `PartSender`, `MultipartProgress`.

Twenty-four members widen from `private` to internal: the stored `destination`, `filePolicy`, `scope`, `sleep`, `plan`, `now`, `log`, `events`, `cancelledIDs`, `reservedKeys`; the types `JobOutcome`, `Restart`, `MultipartTarget`, `MultipartPass`; the methods `processMultipart`, `abortUpload`, `deliverCancelled`, `throttledProgress`, `objectKey`, `reserveKey`, `withRetries`, `partList`, `sendParts`, `complete`. `keyNamer`, `policy`, `store`, `pending`, `isDraining`, `current`, `MultipartStep`, `PartFailure`, `PartSender`, `createUpload`, `resumeUpload`, `reserveAgain`, `mebibytes`, `listParts`, `uploadFile`, `fileName`, `process`, `drain` stay private. `UploadQueueTests.swift` does not change (it uses the public API, `SecurityScope`, `ProgressThrottle`, `readPart` and `MultipartProgress` only).

### 5.2 The abort log

`Upload: <name> multipart aborted` is logged today for a 204 and for a 404 alike, in `UploadQueue.abortUpload` and in `abortUploads`. Both now read the `MultipartAbortResult`: `.aborted` logs `multipart aborted`; `.notFound` logs `Upload: <name> multipart upload already gone` **(the design's call on the wording; R4 wrote none)**. `UploadQueueTests` gains the 404 case for the single-PUT and the multipart `abortFirst` (`FakeDestination.abortResult = .notFound`); test 39 covers the coordinator.

### 5.3 The cancel during the single-PUT abort

`UploadQueueTests` gains `aCancelDuringTheSinglePutAbortDeliversCancelled`: a job with `abortFirst`, the fake's Abort blocking (`blockingAbortsRemaining`), `cancel(recordID:)` lands during it; the only event is `.cancelled(id, reservedKey: nil)`, no `.started`, no upload, no `create`, the log is empty (a cancelled Abort logs nothing), the queue is idle. A second test with a holding Abort released after the cancel checks that `multipart aborted` is logged and `.cancelled` still follows. The multipart path's equivalent (`processMultipart`'s `abortFirst` then `checkCancellation`) gets the same pair.

### 5.4 Two queue findings

- `sendParts`: after a cancel, `group.next()` can return a part that finished at the same moment and the loop then adds another, whose `PartSender.send` reads up to 64 MiB before noticing. `send` starts with `try Task.checkCancellation()` **(the design's call)**; a test cancels between two parts and checks the fake saw no further `part n` and the read count did not grow.
- `createUpload`: when Create succeeds and the first `writeSidecar` throws, the upload id is neither stored nor aborted and is left to the bucket's lifecycle rule (R4 review items 114 and 122). One best-effort `abortUpload` runs in that branch before the job fails **(the design's call)**; a test with a store that fails its first write sees `create` then `abort` and the job `.failed`.
- `PartSender`'s stored properties become `let` (nothing mutates them).

### 5.5 The remaining R4 minor

`MultipartStore.swift:113`'s `NSLog` becomes the `NSLog("%@", ...)` form. The other 20 interpolating `NSLog` lines outside the coordinator (`AppSettings`, `HistoryStore`, `Notifier`, `SaveLocation`, `DragFileStore`, the editor) are the codebase's long-standing form and are left; a `%` in an error message there is unlikely, but an interpolated `%@` or `%s` makes `NSLog` read an argument that was never passed, which is undefined behaviour, so a crash is possible, not only a garbled log line.

## 6. Settings, entitlements, packages

None change. No new setting, no `project.yml` change, no entitlement.

## 7. Tests summary

New: `CoordinatorDragOutTests` (16), `CoordinatorUploadTests` (18), `CoordinatorDeleteTests` (13), `CoordinatorRecordingTests` (9), `CoordinatorRecoveryTests` (7), `PendingRecoveryTests` (5), two in `PendingFileStoreTests`, about eight in `UploadQueueTests` (the 404 log, the cancel-during-abort pair for each path, the cancelled `sendParts`, the sidecar-write abort). Support: `CoordinatorFakes.swift`, `CoordinatorWorld.swift`, `FakeDestination.swift` (moved and extended). The suite's noise lines are unchanged. `MovieSamples` is untouched.

## 8. Hand checks (short)

`docs/testing/coordinator-harness-manual-checklist.md`, written at close-out:

1. The app launches, takes a screenshot, uploads it, records a short area and uploads that: nothing visible changed.
2. `pending/` adoption: with the app quit, copy any PNG into `~/Library/Containers/io.tky.tidyshot/Data/Library/Application Support/TidyShot/pending/` as `<a new UUID>.png`, launch: `Recovered a capture` posts, the row is in Recent Captures with the right size, Annotate opens it, Delete removes it and the file. Same with a short MP4 as `<UUID>.mp4`: `Recovered a recording` with its duration.
3. A `record-screen` URL still starts a selection and `urlRecordingStartPending` clears (a second `record-screen` right after the selection closes starts another): the one R4 line the harness leaves (test 53).
4. The log lines of `stop-recording` in each phase (R4 checklist 178-186) stay as they were: the harness pins the state, not the `RecordingLog` text.

And the R4 checklist lines the suite now covers are marked `(suite)` with the test's name, so Tim's remaining R4 run is shorter: lines 224-227, 230-263, 271-291 and the calls A to F, except the real bucket, CloudFront, `footprint`, the Wi-Fi toggle, the AWS console and the Clop run. The calls G and H stay with Tim: G's second Abort must fail after a first that answered 204, which needs a per-call `FakeDestination` script the harness does not add, and H's rereads need a read counter `readPart` does not have.

## 9. The design's calls (for Tim to overrule)

1. `AppEnvironment` as one struct with a `.live()` builder and `init(environment:)`; `shared` unchanged (2.1).
2. The three protocols `Notifying`, `QuickAccessCards`, `Clipboard`, and `DeleteConfirmation` for the two alerts; the live types conform unchanged (2.2).
3. `Destination` gains the two download members; the coordinator's upload signatures take `any Destination` plus the location and key template (2.2).
4. Every coordinator `NSLog` goes through the environment's `log`, live `NSLog("%@", …)`; `RecordingLog.note` stays (2.3).
5. No `private` member is opened for tests; `record()` is not driven; `recordingProceeds` is extracted as a pure static (2.4, 3.4).
6. The fifty-six tests of section 3 are this phase's set; the rest of the catalogue (editor bridge, pins, restore, Copy File, trim guards, `start()`'s sweeps) waits for a phase that needs it (Deferred).
7. `pending/` orphans are adopted, never deleted; the check is by record id; listing is synchronous in `start()` before any task; one recovery task, the `tmp/Recording` scan first, then `pending/` (4.2, D27).
8. An adopted image or recording gets `.none` and `fileIsTemporary: true`, as a recovered recording does (4.2).
9. The three-file queue split with 24 widenings (5.1).
10. `multipart upload already gone` for a 404 (5.2).
11. `PartSender.send` checks cancellation first; `createUpload` aborts the fresh id when the first sidecar write fails (5.4).
12. The 20 interpolating `NSLog` lines outside the coordinator stay (5.5); a `%` in an interpolated error text is undefined behaviour in `NSLog`'s format, so a crash is possible, not only a garbled line.

## 10. Deferred

Seams not added this phase (added when a test needs them): `NSWorkspace` (open, reveal), the Save As panel, `saveLocation.chooseFolder`, `ScreenCapturePermission`, `NSScreen`, `RecordingLog`, `engine.shareableContent`, the editor and Trim window controllers, `PinController`, `DesktopCoverController`, Clop's optimiser, the `tmp/` directory statics, and `ProcessInfo` activities (a test's recording upload takes the real `Uploading a recording` activity while `fileUploadIDs` is not empty). Rules in the catalogue not tested this phase: the editor bridge, pins, Close and Restore, drag staging and Copy File, the trim gates and pass, GIF conversion bookkeeping, `showOverlay`, `saveRecording` and `finishSave` end to end, `start()`'s sweeps beyond `pending/`, `recordingPrompts` at a real start, the status icon. A `Cancel` on a downloading card and `If-None-Match` on Complete stay deferred from R4.

## 11. Built notes

Built on `coordinator-harness` from the plan `docs/superpowers/plans/2026-10-29-coordinator-harness.md`. The suite
reads `2169 tests in 181 suites` (R4's 2090 in 174, plus `CoordinatorWorldTests` 1, `CoordinatorDragOutTests` 16,
`CoordinatorUploadTests` 18, `CoordinatorDeleteTests` 13, `CoordinatorRecordingTests` 9, `PendingRecoveryTests` 5,
`CoordinatorRecoveryTests` 7, two in `PendingFileStoreTests` and eight in `UploadQueueTests`); the last run,
after the close-out, read `2169 tests in 181 suites passed`.

What was built differently from this design, each with its reason, is the plan's "Plan decisions" list,
numbered D1 to D27; Tim's checklist (`docs/testing/coordinator-harness-manual-checklist.md`) asks him to confirm
the four that change what a user could see or the design's order (D11, D12, D14, D27). Sections 2.1, 2.2, 3.2
(tests 19, 20, 27), 3.3 (test 46), 4.2, 8, 9 (call 7) and 10 above now read as built; what they said before:
- 2.1 had no `multipartPlan` or `uploadSleep` rows (D4: the lanes' plan and backoff, so test 19's retry does not wait).
- 2.2 gave `notifyError(_:title:subtitle:openURL:)`; `Notifier.notifyError` takes `revealing:` (D1).
- Test 19 failed the first part once; a part's retry sends no `.started`, so it is a single PUT's (D15).
- Test 20 said one `abort`; `abortUploads` repeats a 204 (D13, test 38).
- Test 27 had the titles crossed: `Upload failed` is the no-link case, `Not uploaded` the case over a link (D14).
- Test 46 said pruning closes the card with `.deleted`; `removeFiles(ofPruned:)` never closed it (D12).
- 4.2 read a `.gif` with `VideoValidation`, which would remove every GIF; it is read with ImageIO (D11). It named no
  line for an empty file or a failed removal; `Recovery: <name> is empty, removed` and `Recovery: <name> <reason>, and
  could not be removed: <error>` are logged (D11).
- 4.2 ran `adoptPendingFiles` before the `tmp/Recording` scan; the scan runs first, at launch, so a recording started
  while adopting runs is never listed and removed mid-write (D27). `recoverRecordings` takes `begin`'s result.
- 9's call 7 read "one recovery task, `pending/` first"; it now reads "the `tmp/Recording` scan first, then
  `pending/`" to match 4.2 (D27).
- 8 said the suite covers the calls A to H; it covers A to F. G (a second Abort failing after a 204) needs a
  per-call Abort script `FakeDestination` does not have, and H needs a read counter `readPart` does not have (D18),
  so both stay in Tim's R4 run.
- 10 did not name `ProcessInfo` activities among the seams not added; a test's recording upload takes the real
  `Uploading a recording` activity.

The other departures, in short: `Clipboard` also has `hasAnnotationClip` (D2); the triple `makeDestination()`
returns is `AppCoordinator.UploadTarget`, and `persist` and `finishSave` take `UploadTarget?` (D3); the Upload
tab's connection test takes the target, so `ConnectionTester.run` takes `any Destination` and the key template
(D19). `FakeDestination`'s download holds until released, ignoring a cancel, instead of sleeping until cancelled
(2.4; D7). Test 28 cannot see "the queue got no cancel" (a queue cancel of a job it does not hold changes nothing),
so it checks the lane was never given the job (D23). Test 56 cannot see `saveLocation.cancelFolderChoice()`: with no
folder panel open it does nothing, and the panel is Deferred (D22). 5.3's multipart pair expects `.started` before
`.cancelled`, the multipart path's order (`.started` goes before its `abortFirst`; D23). 5.4's `sendParts` test
checks no `part n` after the cancel, not a read count (`readPart` has no counter; D18). Tests 48 and 50 cannot tell
the coordinator's own do-nothing branches from the recorder's, which drops a stop with no run and a repeated stop
itself, so they pin no notice and one recorder stop, and the `did nothing` log lines stay Tim's (D24). The upload
tests keep every recording in `pending/` rather than a temp save folder (D25). `FakeDestination`'s download, part and
Abort holds share one `HeldReleases`, and `FakeConfirm`, `HeldCameraDevices` and `TestGate` one `SingleWaiter` (D26). The suite also has
`CoordinatorWorldTests` (one test of the harness itself), and README names the `pending/` recovery (D21).
After the split, `UploadQueue.swift` is 326 lines (5.1 estimated about 290; 324 after the split, two more after Task 15), `UploadQueue+Multipart.swift`
222 and `UploadQueue+Parts.swift` 232 (215 and 230 after the split). The full run prints about 40
`mdb_txn_commit error: MDB_MAP_FULL` lines from a system cache in the test host; they predate the branch and are
not a failure.

Hand checks: section 8, in the checklist above, not yet run. The R4 checklist's covered items are marked
`(suite: …)`.
