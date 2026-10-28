# TidyShot screen recording R4: design (2026-10-27)

R4 finishes the screen recording list. R1's design is `docs/superpowers/specs/2026-10-21-tidyshot-screen-recording-design.md`, R2's is `docs/superpowers/specs/2026-10-23-tidyshot-screen-recording-r2-design.md` and R3's is `docs/superpowers/specs/2026-10-24-tidyshot-screen-recording-r3-design.md`; everything there still holds unless this document changes it. R1 to R3's decisions stand.

Where the coordinator code goes follows the coordinator split's convention (`docs/superpowers/specs/2026-10-23-coordinator-split-design.md`: each area's code in its own extension file, stored state in the class body under its area's group). The split design does not place R4's members, so this design does:
- `AppCoordinator+Recording.swift`: the URL entry points, the start-cancel flag's checks and the Settings deferral reason.
- `+Upload.swift`: multipart's events, the resume decision, the Clop copy and Retry.
- `+Delete.swift`: multipart's abort on Delete, and the cancel of a drag-out download on Delete.
- `+DragOut.swift`: the drag-out download.
- `+RecordActions.swift`: Save As… waits for a running download.
- `+Overlay.swift`: the card's download status, the cancel in `overlayDidClose`, and the status in `pushCardFlags` and the refresh.
- New stored state goes in the class body in `AppCoordinator.swift`, under its area's group. `downloadingDragIDs` is written from `+DragOut`, `+Overlay` and `+Delete`, so its declaration carries the convention's `//` line naming the other writers.

The research behind this design was done in `.superpowers/sdd/r4/`, which is local scratch and not in the repository. This document restates everything it uses from it.

**The scope (`.superpowers/sdd/r4/decisions.md`, the controller's call, for Tim to overrule).**
1. **URL commands `record-screen` and `stop-recording`**, behind the same setting and gates as the capture commands. `record-screen` acts like the Record Screen shortcut's start. It never starts a recording silently: Screen Recording, the microphone and the camera keep their consent rules, and the selection shows unless a parameter names the area.
2. **S3 multipart upload with resume** for large recordings, with TidyShot's own SigV4 signing and no new package. Today a recording over 5 GiB is not uploaded.
3. **Drag-out of an uploaded video with no local file** as a download with progress into the drag folder, under 2.9's container-copy rule.
4. **Small:** a Settings prompt deferred while a GIF is being saved logs `a capture is running`, which is false. It gets a true reason.

The stale-upload question (an edit saved locally leaves the pre-edit capture uploaded) stays open: nothing is built for it. No pause and no separate upload lane (R2, Left out).

Every choice below that the scope does not settle is marked **(the design's call)**, and the list at the end collects them so Tim can overrule any one. Type names, log wording and constants that are implementation details are not marked.

## Probes (sources go in `docs/superpowers/research/recording-probes/`, listed in its README under R4)

Each network probe talks to Tim's bucket, so each is Tim's to run. No probe records the screen or opens the camera or the microphone. The two network probes read `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY` and an optional `AWS_SESSION_TOKEN` from the environment of the shell that runs them. They use them for that run only and never write them anywhere.

Build each from the repository root with:

`xcrun swiftc -O -target arm64-apple-macos26.0 -o /tmp/<name> docs/superpowers/research/recording-probes/<name>.swift TidyShot/Upload/S3Signer.swift TidyShot/Upload/AWSCredentials.swift TidyShot/Upload/MultipartRequests.swift TidyShot/Upload/MultipartXML.swift`

This is a build of more than one file, and `swiftc` then accepts top-level code only in a file named `main.swift`. So each R4 probe is an `@main enum` with `static func main() async` and no top-level statement (amended 2026-10-27 after the plan review; the R3 probes are single-file builds and use top-level code). `S3Signer.swift` and `AWSCredentials.swift` type-check together with no other app file (checked on 2026-10-27 against a stub main). `MultipartRequests.swift` and `MultipartXML.swift` are new, `nonisolated`, and import only Foundation (and CryptoKit for the hash), so they keep that property. The app and the probes build every multipart request from `MultipartRequests`, so M1 sends the app's own Create, UploadPart, Complete, Abort and ListParts, headers included. The probes take the endpoint, region and bucket as arguments and do not use `S3DestinationConfig`. The plan task that writes the two files also type-checks this line with a stub main; that check touches no network. Results go in this section, with the date and the Mac, as R2's and R3's did.

- **M1, multipart against `snap.tky.io`** (`r4-multipart.swift <bucket> <region> <endpoint> <prefix> [acl]`, with `acl` when Tim's lane sends `x-amz-acl: public-read`; a real upload, Tim's to run). Under `<prefix>/r4-probe-<random>` it prints each request's status and the time it took. In order:
  1. CreateMultipartUpload with `Content-Type: video/mp4` and `Cache-Control: no-cache`, and `x-amz-acl: public-read` only when Tim's lane sends it.
  2. Two UploadParts of 5 MiB each (parts 1 and 2, payload signed with its SHA-256) and one of 1 MiB (part 3), three at a time.
  3. ListParts.
  4. CompleteMultipartUpload with the three ETags and `content-type: application/xml`. It prints the whole body, since a 200 can carry `<Error>`.
  5. HEAD of the key. It prints `Content-Length` (11 MiB expected) and `Cache-Control` (`no-cache` expected).
  6. DELETE.
  7. A second upload with one part, then AbortMultipartUpload on it, then ListParts on the aborted id (404 `NoSuchUpload` expected), then a Complete on the aborted id (404 expected).
  8. A 2 GiB sparse file (`FileHandle.truncate`) uploaded in 16 MiB parts, 3 in flight. Tim reads `footprint <pid>` at the halfway mark. Then it is deleted.
  9. The same 2 GiB file in 64 MiB parts, 3 in flight, with `footprint` read again at the halfway mark. Then it is deleted.

  Expected: every status in the 2xx range, except the 404s named. ListParts lists the three parts with their sizes and ETags. The HEAD size matches. The footprint stays under 120 MB at 16 MiB parts and under 250 MB at 64 MiB parts. A 403 on ListParts or on Abort is written down with the body's `<Code>`: it means Tim's IAM policy lacks `s3:ListMultipartUploadParts` or `s3:AbortMultipartUpload` (G1).
- **D1, a signed download with progress and resume** (`r4-download.swift <bucket> <region> <endpoint> <key>`, on an uploaded recording of at least 100 MB that Tim names; M1 deletes its own objects in the same run). It uses an ephemeral `URLSession` with no URL cache, configured as `S3Destination.uncachedSession` is, so G2 tests the app's configuration. In order:
  1. It downloads through `URLSessionDownloadTask` with a task delegate and prints each `didWriteData` as a fraction with its time.
  2. At 50 % it calls `cancel(byProducingResumeData:)` and prints whether resume data came back and how large it is.
  3. It waits 2 s, resumes with `downloadTask(withResumeData:)`, and prints the first fraction after the resume and the final status.
  4. It waits until 16 minutes have passed since the request was signed, resumes again from the same resume data, and prints the status (403 expected, the signature having expired).

  Expected: progress callbacks arrive and move; the first resume carries on from about 50 % with a 206; the file's size equals `Content-Length`; the late resume is refused (G2).
- **U1, the URL commands by hand** (no probe source; the checklist). These record the screen, so they are Tim's hand checks, not probes:
  - `open 'tidyshot://record-screen'` from Terminal, from Raycast and from Keyboard Maestro.
  - `open 'tidyshot://stop-recording'` during the selection, the count-in, the recording and the save.
  - `record-screen` with a rect.
  - `record-screen` during a recording and during a screenshot's selection.
  - A cold launch from `tidyshot://record-screen`.
- **Setup step, not a probe.** Tim adds a lifecycle rule to `snap.tky.io`: `AbortIncompleteMultipartUpload` with `DaysAfterInitiation` 7 and an empty prefix. `put-bucket-lifecycle-configuration` replaces the bucket's whole lifecycle configuration, so he first runs `aws s3api get-bucket-lifecycle-configuration --bucket snap.tky.io`, adds the rule to the rules it returns (none, if it answers `NoSuchLifecycleConfiguration`), puts the merged list, and runs the get again to check it (Multipart, Orphaned uploads; the README gives the rule's JSON and these steps).

**Results (2026-10-28).** No probe has run, so there is nothing to record yet. Each needs Tim's shell and key or his hands, and the checklist (`docs/testing/recording-r4-manual-checklist.md`) has a blank for each answer. Copy the answers here with the date and the Mac when they come in.
- **M1:** not run. G1 is open. Blanks: each step's status and time; ListParts and Abort statuses (a 403 with its `<Code>`); Complete's whole body; the HEAD's `Content-Length` and `Cache-Control`; `footprint` (current and peak) at 16 MiB and at 64 MiB parts.
- **D1:** not run. G2 is open. Blanks: whether resume data came back and its size; the first fraction after the resume and its status; the file size against `Content-Length`; the late resume's status (or inconclusive).
- **U1:** not run (the hand checks, not a probe).
- **Setup, the lifecycle rule:** Tim says the bucket already has the `AbortIncompleteMultipartUpload` rule. That is unverified: `aws s3api get-bucket-lifecycle-configuration --bucket snap.tky.io` has not been run by anyone.

**Gates.** The pure code (Tests), the URL commands and the whole drag-out download build on no probe. These parts wait:
- **G1, multipart against the real bucket** waits on M1. Everything builds and is tested against the local stub first. Before the PR merges, M1 confirms with Tim's key and the dotted path-style bucket:
  - that Create, UploadPart, Complete and Abort work, and that ListParts does;
  - that Create's `Cache-Control` and ACL headers reach the object;
  - that a Complete answers with a plain 200.

  If ListParts is 403, the lost-sidecar fallback (Multipart, Resume) becomes "abort and start again" and the README says why. If Abort is 403, the README's policy gains `s3:AbortMultipartUpload` and Tim adds it before the merge; the app's Delete is not changed to swallow the 403. A Complete whose 200 carries `<Error>`, or a footprint over 120 MB at 16 MiB parts or over 250 MB at 64 MiB parts, goes back to Tim.
- **G2, resume data for a failed drag-out download** waits on D1. The download itself and its progress do not: the delegate path is Apple's documented one. If D1 shows no resume data or a resume that does not continue, the failure path drops the resume step and starts again (Drag-out, Failure), with no other change.

## URL commands `record-screen` and `stop-recording`

- **Names and where they hook in.**
  - `URLCommand.Kind` gains `.recordScreen = "record-screen"` and `.stopRecording = "stop-recording"`, after `.captureText` and before `.restoreRecentlyClosed`.
  - `record-screen` is CleanShot's name, with CleanShot's parameters (`x`, `y`, `width`, `height`, `display`, CleanShot 4.7 and later) and CleanShot's meaning for the rect: it opens the recording tool at that place. A CleanShot macro ports by changing the scheme. CleanShot has no stop command (its API page lists only `record-screen` under Screen Recording), so `stop-recording` is TidyShot's own name and has no alias **(the design's call)**.
  - `URLCommandTarget` gains `startRecording(intent: CaptureIntent, preselect: ScreenRect?)` and `stopRecordingCommand(sender: String?)`. Neither is `async` and neither returns a value. `AppCoordinator` implements them in `+Recording.swift`, and `URLTargetRecorder` in the tests records them. The handler's switch routes `.recordScreen` to the first (with the resolved placement, or nil) and `.stopRecording` to the second, with the cleaned sender.
  - `startRecording` checks `recordingStartsFromURL` (below), then starts the recording in its own `Task` and returns. The handler's `run` therefore returns once the start is under way, not when the recording ends **(the design's call)**. After launch each URL already runs in its own task, so nothing changes there. In `ready()`, which runs the queued URLs one after another, a `stop-recording` queued behind a `record-screen` runs at once instead of waiting for the recording to end. It then finds the prompts or the selection open, does nothing, and logs that; a stop sent before anything was recorded has nothing to stop.
- **Kind rules.** `record-screen` is a capture (`isCapture` true): the capture drop applies to it, it counts as the first capture command of a launch burst, and it takes `action` and the area (`takesArea` true). `capturesWithoutSelection` is false for it with or without a rect, since a rect only preselects. `stop-recording` captures nothing (`isCapture` false, `takesAction` false, `takesArea` false), so it is never dropped behind the lock, never sets `captureRan` in `ready()`, and runs whenever URL commands are on. The `capturesNothing` list in `URLCommandTests` gains it.
- **Parameters of `record-screen`.**
  - `action`: `upload` or `save`, with the meaning `CaptureIntent(urlAction:setting:)` gives them (`upload` is upload-only when that is the after-capture setting). `copy`, `annotate` and `pin` are refused at parse time **(the design's call)**: a recording ignores `copyOnly` and `then` (R1, `saveRecording`), and a sender asking for `copy` would otherwise expect the movie on the clipboard and get a save. `URLCommand.Kind.actions` lists what each kind takes (every action for the screenshot kinds, `[.upload, .save]` for `record-screen`), and `parse` checks the value against it. `URLCommandError` gains `unknownActionForKind(value: String, command: String)`, with the message `Unknown action “<value>” for <command>. Use upload or save.` The existing `unknownAction(String)` (`Unknown action “<v>”. Use upload, save, copy, annotate or pin.`) stays for a value that is no action at all; `unknownActionForKind` is for a real action the command does not take. Without `action` the after-capture setting applies, as for every capture.
  - `x`, `y`, `width`, `height` and `display`, under 2.9's rules: all four or none, bottom-left origin, `display` 1-based and used only with the rect, resolved by `URLCommandGeometry.resolve` and clipped to the display. The rect is preselected in the recording selection (Selection with a rectangle, below). The handler refuses a resolved rect under 32×32 pt before it reaches the target, with the `TidyShot URL command` notice `The area must be at least 32 by 32 points to record.` **(the design's call)**, so a rect that could never record is not shown. The rect is not written to `lastAreaRect`: a recording's area is never the previous area (R1).
  - Nothing else: no `display` alone (it is ignored with no rect, as for every command), no window, no duration, no format and no microphone switch. `record-fullscreen` is not in R4 (Deferred).
- **Selection with a rectangle** **(the design's call)**. As in CleanShot, the rect opens the recording tool at that place. It does not record at once:
  - `SelectionController.select(mode:content:freeze:preselect:)` gains `preselect: CGRect?` (CoreGraphics global points), used only in `.recording` mode. The view on the display that holds the rect's centre shows it as `presetRect`: cut out of the dimming, with its stroke and its size label. Elsewhere the crosshair, the loupe and the window highlight work as today. The highlight is not drawn inside the rect.
  - A click inside the rect (a press and a release with no drag) records it. A drag anywhere draws a new area and records it on release, as today. A click outside the rect on a highlighted window records that window. Escape cancels.
  - No key records the rect: Return and Enter do nothing. The overlay takes the key from whatever app the user is typing in, so a key typed there as it appears cannot start a recording. This keeps 2.9's disarmed rule with no arming step.
  - `SelectionOutcome.resolve(mode:dragRect:hasHighlight:clickInPreset:)` gains the preset click: a click in the preset gives `.area(presetRect)` before the window rule. It stays pure and tested.
  - The result is an ordinary `.area(rect, display)` selection, so the size check, the count-in, the bubble, the rings and the bar are those of a dragged area.

  This replaces recording at once behind the second switch. A ported CleanShot macro gets CleanShot's behaviour, the selection stays the consent, and `record-screen` needs only the first switch.
- **Gate.** Off refuses both with `URL commands are off. Turn them on in Settings > General.`. On, `record-screen` runs with or without a rect: the selection shows, so the user's drag or click is the consent, as for `capture-area` without a rect. `stop-recording` needs only the first switch too. The second switch's caption does not change.
- **Consent.** A URL start goes through the same code as the shortcut's start, so nothing is skipped:
  - `recordingPrompts()` shows the microphone and camera prompts when access is undecided, and the system's Screen Recording prompt appears as today when the app has no grant.
  - `recordingCanStart` checks the disk and resolves the input and the camera under the lock.
  - The count-in runs when `Count down before recording` is on, and the bar, Stop and Cancel work as for any recording.
  - Access already granted is used without a prompt, as for the shortcut. Once the user clicks, the recording takes the stored microphone and the webcam bubble as Settings has them. The README's Security paragraph says so.
- **What `record-screen` does in each phase.** `recordScreen()` today toggles (`recordShortcutStarts`: a count-in is cancelled, a recording stopped). The URL command must only start, so the start is split out. `recordScreen()` keeps the toggle and then calls the new `startRecordScreen(intent:preselect:)`. `startRecording(intent:preselect:)` calls it directly after a start-only check, `recordingStartsFromURL(phase:askingPermission:isQuitting:)` (pure). The lock's drop in the handler runs first, so most phases never reach that check:
  - **idle**: starts. The prompts, then the selection (`selector.select(mode: .recording, …, preselect:)`), then the count-in and the recording, as the shortcut. The intent's action decides the save and the upload. `intent.sender` travels, but recording notices do not name it, as today **(the design's call)**.
  - **selecting** (a recording's or a screenshot's selection is open, the lock held): dropped by the handler, logged `URL command from <sender> dropped, a capture is running: <url>`, no notice, as every capture command is today.
  - **count-in**: dropped, logged `… dropped, a recording is starting: <url>`. It does not cancel the count-in.
  - **recording**: dropped, logged `… dropped, a recording is running: <url>`. It does not stop the recording.
  - **saving** (a GIF converting, a mute ladder or a save running; the lock is free): starts a new recording, as the shortcut does **(the design's call)**.
  - **a prompt open** (`askingPermission`): dropped, `… dropped, the <microphone|camera> prompt is open: <url>`, as today.
  - **quitting**: nothing starts, and `Recording: URL start ignored, the app is quitting` is logged.
  - For the two new reasons, `CaptureRefusal` gains `.recordingStarting` and `.recordingRunning` **(the design's call)**: today every drop during a recording says `a capture is running`, which is true but less useful in a log. `captureRefusal(isCapturing:askingPermission:recordingPhase:)` checks in this order: `.countIn` gives `.recordingStarting`; `.recording` gives `.recordingRunning`; then the lock gives `.captureRunning` (also in `.idle` and `.saving`, as for a screenshot taken while a GIF converts); then an open prompt gives `.permissionPrompt`; otherwise nil. `refusesCapture` and the status menu are unchanged. `dropReason` maps the two new cases to the strings above.
- **What `stop-recording` does in each phase**, from the pure `recordingStopCommandAction(for phase:) -> RecordingStopCommandAction` (`.stop`, `.cancelCountIn`, `.nothing`). `stopRecordingCommand(sender:)` takes the action and logs the outcome through `RecordingLog`, naming the sender (`an unknown app` when nil). There is no outcome type: the handler logs only its own `URL command from <sender>: <url>` line, and the coordinator writes the `Recording:` line.
  - **recording**: `recorder.stop()`. The recording ends as the bar's Stop ends it: the file is kept, saved and uploaded by the intent its start was given, and `Recording stopped` and the notes post as today. Logged `Recording: stop-recording from <sender> stopped the recording`.
  - **count-in**: sets `recordingStartCancelled` and calls `selfTimer.cancel()` **(the design's call)**. The sender asked for no recording. Logged `Recording: stop-recording from <sender> cancelled the count-in`. `selfTimer.cancel()` alone is not enough: the `.countIn` phase covers the whole hand-off, and only `selfTimer.run` reacts to it. With `Count down before recording` off, a stop during the settle delay, or one during the fresh content read after the countdown, would otherwise be lost and the recording would start. So:
    - `recordingStartCancelled` is new stored state in the Recording group. It is reset to false when `recordingCountIn` turns from false to true (in `record()`, or earlier in Record Fullscreen's display read).
    - `record()` reads it together with `isQuitting` after the hand-off returns and just before `recorder.run`, with no suspension between. When it is set, nothing starts, the extras close, the notice hold ends, and `Recording: not started, the count-in was cancelled` is logged.
    - The record shortcut's `.cancelCountIn` sets it too, so the shortcut's cancel has the same guarantee.
  - **idle, selecting, saving, or a prompt open**: nothing. A recording's open selection stays (Escape cancels it); a GIF conversion goes on (`Stop Making GIF` is the status menu's). Logged `Recording: stop-recording from <sender> did nothing, no recording is running`. No notice **(the design's call)**: a macro that stops defensively should not post a banner each time.
  - A second `stop-recording` during the stop wait is a no-op (`RecordingController.end` guards on `isRunning` and the earlier cause), logged as nothing running.
  - `stop-recording` is not a toggle: it never starts anything.
- **Log lines**, in order for a run: the handler's `URL command from <sender>: <url>` (`NSLog`, as today), then the recording's own `Recording:` lines (`RecordingLog`, `io.tky.tidyshot`, `Recording`), and for `stop-recording` the coordinator's outcome line above.
- **Notices.** No new notice except the two refusals above (`Unknown action … for record-screen`, `The area must be at least 32 by 32 points to record.`), both titled `TidyShot URL command` with `From <sender>` as the subtitle when known. The hold (R2, Decided 2026-10-24, 8) applies: a notice asked for during a URL-started recording waits for Stop.
- **README.**
  - The URL scheme table gains two rows. `record-screen`: `Record Screen: select an area or click a window. A rectangle is shown in the selection, and a click inside it records it (no key does). action is upload or save`, with `action`, `x`, `y`, `width`, `height`, `display`. `stop-recording`: `Stop the recording, or cancel its count-in; nothing otherwise`, with none.
  - The action paragraph adds that `record-screen` takes only `upload` and `save`.
  - The Security paragraph says that `record-screen` always shows the selection, with a rectangle too, so it needs only the first switch; that once you click, the recording takes the microphone and the webcam bubble as Settings has them; and that it asks for microphone and camera access first when macOS has not asked yet, as the shortcut does.
  - The Errors paragraph adds an action a command does not take and, for `record-screen`, an area under 32 by 32 points.

## Multipart upload

- **When.** `MultipartPlan.uses(payload:byteCount:)` is true for a `.file` payload (an MP4 or a GIF) of 100 MiB or more **(the design's call)**. It is read on the bytes actually sent (Clop's result when it was accepted), where `fitsSingleUpload` is read today. Screenshots and files under 100 MiB keep the single PUT. The threshold is below 5 GiB because a 3 GiB file that fails at 90 % today starts over on each of its six attempts, after hashing the whole file before it sends a byte. With parts, a failure costs one part. The cost is that most recordings take the new path, so it is tested against the stub (Tests) and against Tim's bucket (M1). A size that cannot be read counts as a single PUT, as today, and the queue then reports the file unreadable.
- **Parts.** `MultipartPlan.partSize(for byteCount:)` **(the design's call)**:
  - 16 MiB.
  - Raised to `ceil(byteCount / 10,000)`, rounded up to a whole MiB, when 16 MiB would need more than 10,000 parts (from 156.25 GiB).
  - Capped at 64 MiB.

  Every part but the last is the same size (Cloudflare R2 requires it). The last has no minimum. The part size is fixed at Create and stored, never recomputed. A file over 10,000 × 64 MiB = 625 GiB is refused: `RecordingSavePlan.oversizedNotice` becomes `Not uploaded` / `The recording is larger than 625 GB, too large to upload.`, and the refusal keeps R1's handling (`.none`, never `.failed`; a pending file moves into the save folder, a save-folder file stays). `RecordingLimits.singleUploadBytes` and `fitsSingleUpload` are replaced by `MultipartPlan.maxBytes` and `MultipartPlan.fits(byteCount:)`. `refuseOversizedUpload`'s log line becomes `Recording: <name> is too large to upload (over 625 GB)`, and code comments that say "in one piece" are updated. No real recording reaches the limit (R1's disk limits stop a recording long before), but the plan returns a result for every size.
- **Concurrency.** The queue stays serial across jobs. Within a multipart job, 3 parts are in flight at a time (`MultipartPlan.inFlight`, a constant, not a setting) **(the design's call)**, in a `TaskGroup` that starts the next part as one finishes, in part order. Memory holds at most 3 parts plus their hashing: about 48 MiB at 16 MiB parts and about 192 MiB at the 64 MiB cap, before any copy URLSession makes. These are estimates; M1 measures both sizes.
- **Reading a part.** Each part is read into `Data` with a `FileHandle` (`seek(toOffset:)`, `read(upToCount:)`) in a `@concurrent` function, hashed with SHA-256, signed with that hash and sent with `session.upload(for:from:delegate:)` **(the design's call)**. The two alternatives were a temporary file per part, which copies the whole recording through the disk again, and a streamed request, which has no async form and needs `needNewBodyStream` to resend. The bytes hashed are the bytes sent, so S3 rejects a part corrupted in transit. The rule against loading a recording into memory still holds for the file as a whole. The save folder's security scope is held for the whole attempt, as `uploadFile` holds it for a single PUT today. A short read (the file shrank) throws `UploadError.fileUnreadable`.
- **Signing and requests.**
  - `MultipartRequests` (new, pure, shared with M1) builds each call's method, path, decoded query pairs, headers and body. `S3Destination` gains `signedRequest(method:key:query:payloadHash:extraHeaders:)` and `S3DestinationConfig.objectURL(for:query:)`, both fed from that one list of decoded `(name, value)` pairs, so the URL's query and the canonical query cannot disagree. The existing overloads pass an empty list. `S3Signer.sign` already canonicalises `request.query`; what is new is a non-empty query on `S3Destination`'s requests, so the signer itself does not change.
  - `x-amz-content-sha256` is the payload's hash, never `UNSIGNED-PAYLOAD` (a bucket policy may deny it). No `Content-MD5` and no `x-amz-checksum-*`.
  - The six calls, path-style for Tim's dotted bucket:
    - `createMultipartUpload(key:contentType:cacheControl:) -> String`: `POST /<bucket>/<key>?uploads` with an empty body. The `content-type`, `cache-control` (when given) and `x-amz-acl: public-read` (when `sendPublicReadACL`) headers are signed, as `putHeaders` does. The `<UploadId>` is read from the body.
    - `uploadPart(key:uploadID:number:data:progress:) -> String`: `PUT /<bucket>/<key>?partNumber=<n>&uploadId=<id>`. The `ETag` response header is the result. A 404 whose body code is `NoSuchUpload` throws `UploadError.noSuchUpload`.
    - `completeMultipartUpload(key:uploadID:parts:)`: `POST /<bucket>/<key>?uploadId=<id>` with a signed `content-type: application/xml` and the body `<CompleteMultipartUpload><Part><PartNumber/><ETag/></Part>…</CompleteMultipartUpload>`, parts in ascending order, built from TidyShot's own records (the sidecar), never from a ListParts answer except as the rebuild below allows. The explicit type matters: URLSession adds `application/x-www-form-urlencoded` to a POST with a body and no type, and AWS refuses that type on Complete. A 200 whose body holds `<Error>` throws `UploadError.completeError(code:body:)`. A 404 `NoSuchUpload` throws `.noSuchUpload`. A 400 `InvalidPart` or `InvalidPartOrder` throws `.partsRejected(body:)`. `EntityTooSmall` and every other 4xx is `httpStatus`, not retryable.
    - `abortMultipartUpload(key:uploadID:)`: `DELETE /<bucket>/<key>?uploadId=<id>`. 204 and 404 both count as done, and the call tells which it got.
    - `listParts(key:uploadID:) -> [MultipartPart]`: `GET /<bucket>/<key>?uploadId=<id>&part-number-marker=<m>`, paged until `IsTruncated` is false, giving number, ETag and size. A 404 `NoSuchUpload` throws `.noSuchUpload`.
    - `objectSize(key:) -> Int64?`: HEAD, 200 with `Content-Length`, nil on 403 and 404.
  - The XML readers (`UploadId`, `Error`, `Part` lists) in `MultipartXML` are small element scans in the style of `excerpt`'s `elementText`. Every error body still goes through `excerpt`, whose 200-character cap stays load-bearing.
  - `UploadError` gains three cases, and `isRetryable` changes with them:
    - `.noSuchUpload`: `The upload was no longer known to the server.` Not retryable by `isRetryable`; the queue catches it before that rule and handles it apart (Resume).
    - `.partsRejected(body: String)`: `The server rejected the upload's part list: <body>`. Not retryable by `isRetryable`; the queue handles it apart (Resume).
    - `.completeError(code: String, body: String)`: `The server could not complete the upload: <body>`. Retryable when `code` is `InternalError`, `SlowDown` or `ServiceUnavailable`, as a 5xx or a 429 would be; not retryable for any other code.
    - The existing cases keep their rule: `httpStatus` retries at 500 and above and at 429, `noHTTPResponse` retries, the rest do not.
  - The `Destination` protocol gains the six calls, and `FakeDestination` scripts them.
- **What is persisted, and where.**
  - **On the record**: `CaptureRecord.multipart: MultipartUploadState?` (`decodeIfPresent`, so old history decodes). It is written once, in the same main-actor turn the queue reports Create (`UploadEvent.multipartStarted(id:state:)`, delivered before any part is sent). It holds `uploadID`, `key`, `location: ObjectLocation`, `partSize`, `byteCount` (the source's size), `sourceModified`, `sourcePath: String` (the file the upload sends: the kept Clop copy, or the record's own file) and `startedAt`. So Delete always knows what to abort and what key to remove, after a quit or a crash too.
    - `MultipartUploadState` has its own `Codable` that writes `sourceModified` as a `Double`, its `timeIntervalSinceReferenceDate`, not as a `Date`. `HistoryStore` encodes `Date`s as ISO 8601 with milliseconds, which would cut an APFS modification date and make every resume after a relaunch fail the source check. JSON round-trips a `Double` exactly.
  - **In a sidecar**: `Application Support/TidyShot/multipart/<recordID>.json` (`MultipartStore`, a `nonisolated` `Sendable` struct in `TidyShot/Upload/`, built beside `PendingFileStore` in `AppCoordinator.init`), `{uploadID, completeSent, parts: [{number, etag, size}]}`. The queue rewrites it atomically after each part completes, and sets `completeSent` before the first Complete for that id goes out. The record is not rewritten per part: `HistoryStore.save` rewrites all of `history.json` on every update, and a 50 GiB file has 3,200 parts. A sidecar whose `uploadID` differs from the state's counts as missing.
  - **Clop's copy.** Clop's result lives in `tmp/Clop`, which launch removes. When multipart applies to a fresh upload and the source is Clop's result, `startUpload` moves it to `multipart/<recordID>.mp4` before the enqueue, stores that path in `sourcePath`, and the job sends it from there **(the design's call)**. The alternative, a fresh Clop run on Retry, would throw the progress away and optimise again. The moved copy is no longer in `clopResults`, so `handle(_:at:)` does not delete it on `.failed` or `.cancelled`. It is removed only by the rules here: on `.uploaded`, on Delete, when the state is dropped (a start over's new state replaces it and sends another file, for example with Clop off now; the coordinator removes the old copy when that state's `multipartStarted` arrives), and by the launch sweep. A move that fails logs `Upload: Clop's copy could not be kept for resume: <error>`, the result stays in `clopResults`, and the job sends from `tmp/Clop` as today, with no resume across a relaunch.
  - **Cleared** on `.uploaded`: the record's `multipart`, the sidecar and the kept copy go. They are kept on `.failed` and `.cancelled`.
  - **Launch sweep**, after `history.load` **(the design's call)**. It aborts nothing: no network at launch, as no upload resumes by itself. It removes:
    - files in `multipart/` whose id has no record, or whose record has no `multipart` state;
    - the sidecar and the kept copy of a state whose `startedAt` is more than 7 days old. The lifecycle rule has aborted that id, or will. The record's `multipart` stays, so Delete still knows the key; the next upload start finds the source or the sidecar gone and starts again.
- **Progress.** `UploadProgressDelegate` gains a byte callback (`onBytesSent(delta:)`), and one `ProgressGate` serves the whole job. The fraction is the bytes of completed parts plus the bytes the in-flight parts have sent, over the file's size. The single PUT keeps its fraction callback. `UploadEvent.started` becomes `.started(id:attempt:fraction:)`: a resumed multipart job starts at its done fraction, and a single PUT or a fresh upload at 0. `handle` sets the bar to the event's fraction on every `.started`, not only when `attempt > 1`, so a Retry that resumes shows its done fraction at once. The card keeps `Uploading…` with its ring at the byte fraction, and the row's detail keeps `Uploading`. Neither names parts **(the design's call)**. The `Uploading a recording` activity (idle sleep held off) is unchanged.
- **Failure and retry** **(the design's call)**.
  - **Requests retry on their own.** In a multipart job, each request retries under `RetryPolicy.file` (6 tries, 2 to 30 s) with the `isRetryable` rule above: the key's HEAD, Create, each UploadPart, ListParts, Complete and `objectSize`. The other parts in flight carry on while one part waits.
  - **The job is not retried as a whole.** `UploadQueue.process`'s job-level loop gives a multipart job one pass. When a request runs out of tries, or meets an error that is not retryable and not handled apart below, the group is cancelled and the job ends `.failed(id:message:)`. A part's failure reads `Part <k> of <n>: <error>` (for example `Part 12 of 200: Server returned HTTP 503.`). Any other request's failure is its error as today. The record is `.failed` with that message, and `Retry` resumes (below). The upload id, the parts done and the kept copy all stay, so the failed job's work is not lost. Without this rule a failure would cost up to 6 × 6 tries.
  - **Restarts.** A restart drops the stored upload (best effort abort when the id may still exist), creates a new one, and begins a new attempt: `.started` with `attempt` one higher and fraction 0. `attempt` counts restarts and nothing else. The causes are listed under Resume. A job makes at most 2 restarts; a third cause fails the job with that cause's error, so a server that keeps answering `NoSuchUpload` cannot loop.
  - Single-PUT jobs keep today's loop: up to 6 attempts of HEAD then PUT.
- **Resume.**
  - **Every start passes the state.** `startUpload` is the one funnel for every upload start: Retry (card and row), Retry Failed Uploads, `Upload Trimmed`, Save and Upload, the editor's upload and the save's first upload. A relaunch's `HistoryStore.load` already turns `.uploading` into `.failed("Upload was interrupted.")`, and now keeps `multipart`. When the record has `multipart` state, `startUpload` decides before Clop runs and before any counter is drawn, through the pure `MultipartPlan.resumeDecision(stored:location:fixedKey:source:)`:
    - `source` is the file the stored state names (`sourcePath`) with its size and modification date, read in the same detached task that reads `byteCount(of:)`, holding the save folder's scope.
    - It resumes when the stored `location` equals the lane's, the stored `key` equals the fixed key for a fixed-key job (any stored key for a template job), and `source` exists with the stored size and modification date.
    - Otherwise it starts over, with its reason (`location`, `key` or `source`).
    - `MultipartPlan.startStep(decision:)` turns the decision into what `startUpload` does: whether Clop runs, whether a counter is drawn, which file is sent, and what is aborted first. Both are pure.
  - **On a resume** the job sends `sourcePath`, the file whose attributes were checked. Clop does not run **(the design's call)**: a resume must send the same bytes as the parts already sent, whether `sourcePath` is a kept Clop copy or the record's own file (Clop was off or not running the first time). The job carries `UploadJob.resume(state)` and the stored key, and no counter is drawn. No upload resumes by itself at launch, as today **(the design's call)**: a relaunch on a different network should not start sending gigabytes unasked.
  - **On a start over** `startUpload` runs as today (Clop when it applies, the counter when the template has one), and the job carries `abortFirst: MultipartRef` for the stored upload. The queue aborts it (best effort) through the lane's destination. After a destination change that destination is the new bucket, so for `location` the job carries no `abortFirst`: the coordinator aborts the stored upload as Delete does, through a destination built from the stored location with the credentials stored now, best effort and not awaited by the upload (amended 2026-10-27 after the plan review). The queue logs `Upload: <name> source changed, starting again`, `… destination changed, starting again` or `… key changed, starting again`, and the coordinator drops the old state when the new Create's `multipartStarted` arrives. A new Clop result never meets the old upload's parts: it fails the source check, or Clop does not run at all.
  - **In the queue, a resumed job:**
    - For a template key, HEADs the stored key first (`objectSize`). Absent: the key is still free, go on. Present with the stored `byteCount`: an earlier Complete landed before a quit or a crash, so the job counts as uploaded. Present with another size: another capture took the key while this upload waited, so the job aborts the stored id, draws a new key and restarts. A fixed key gets no HEAD, as today.
    - Reads the sidecar. When it is missing, unreadable or for another upload id, `listParts` rebuilds it, logged `Upload: <name> part list missing, listing parts`. A part the server lists with the stored part size (or, for the last part, the remaining size) is trusted; any other is sent again. If ListParts fails with a 403 (a key without `s3:ListMultipartUploadParts`), or with any error left after its retries, the job restarts, logged `Upload: <name> part list unavailable, starting again` (G1).
    - Sends only the parts the sidecar does not list, 3 at a time, and completes. Progress starts at the done fraction. Logged `Upload: <name> resumes at <done> of <n> parts`.
  - **`noSuchUpload` from a part or from ListParts, or from a Complete when the sidecar's `completeSent` is false** (the lifecycle rule or a provider removed the id): the state is dropped, logged `Upload: <name> upload id gone, starting again`, and the job restarts under the same key (a template key is HEADed again first).
  - **`noSuchUpload` from a Complete when `completeSent` is true** (an earlier Complete for this id may have succeeded and its response been lost, in this run or before a quit): `objectSize(key:)`. A size equal to `byteCount` counts as uploaded. Anything else restarts, as above.
  - **`partsRejected` from Complete** (`InvalidPart` or `InvalidPartOrder`, for example a stale sidecar): the first time in a job, `listParts` rebuilds the list, any part that is missing or whose ETag or size differs is sent again, and Complete is sent again, logged `Upload: <name> part list rejected, listing parts`. A second time in the same job, the job restarts.
- **Key.** As today, a template job reserves its key with HEAD before Create. A fixed key (the editor's replace, Trim's Save and Upload and `Upload Trimmed`) gets no HEAD and Creates at that key, where the old object keeps serving until Complete replaces it in one step. `Cache-Control: no-cache` for a replace goes on Create. A multipart template key stays reserved for as long as its upload waits (days, for a failed upload retried later), and HEAD cannot see it until Complete. The HEAD on a resume (above) closes that gap: a key another capture took meanwhile is never overwritten. `If-None-Match: *` on Complete is left out (support outside AWS is unconfirmed).
- **Trim's `Upload Trimmed` and Save and Upload on a large file** take the same path. `startUpload(fixedKey:)` plans multipart on the trimmed file's size, and the record's `priorUpload` is kept as today. A failure returns the record to `.uploaded` at the old link with `uploadIsStale` and `multipart` kept, so a later `Upload Trimmed` resumes the replace when the trimmed file still matches. The link shows the full recording until Complete.
- **Cancel and Delete.**
  - `UploadQueue.cancel(recordID:)` cancels the group. Each part task stops at its next check or its request's cancellation, and `cancel` waits for all of them before `.cancelled` is delivered. `.cancelled(id:reservedKey:)` is unchanged, and the record keeps `multipart` from Create.
  - `CaptureDeletion.aborts(for:) -> [MultipartRef]` lists the record's upload id with its key and location. `deleteCapture` aborts it, through `abortMultipartUpload` signed with the credentials stored now at the stored location, before `deleteObjects` removes the keys as today. When the Abort answers 204, Delete sends a second Abort: AWS says a part in progress may still land after an Abort, and the second one removes it (it answers 404 when nothing was left). 204 and 404 count as done. Any other failure takes the existing path, the second alert with `CaptureDeletion.storageFailureMessage`, so a capture whose upload cannot be aborted is never stuck.
  - `CaptureDeletion.objects(for:)` also lists `multipart.key` at `multipart.location`, deduplicated with the other keys and filtered by `sharedKeys` as they are. An object a Complete made before a quit, a crash or a cancel is then removed even when the record is `.failed`. A DELETE of a key that does not exist is harmless. `confirmationText` counts that key, so a failed upload's Delete says it also removes the uploaded object.
  - Delete also removes the sidecar and the kept copy.
  - `removeFiles(ofPruned:)` removes the sidecar and the kept copy and aborts nothing **(the design's call)**: pruning runs at launch, and the lifecycle rule removes the upload. `deleteOrphanedObject` runs on `.uploaded`, after Complete, so it has no upload to abort.
- **Orphaned uploads.** The app aborts only upload ids it stored. There is no ListMultipartUploads sweep **(the design's call)**: Tim's upload-only key likely lacks `s3:ListBucketMultipartUploads`, and a bucket-wide sweep could abort another client's upload. These are the lifecycle rule's (`AbortIncompleteMultipartUpload` after 7 days on the whole bucket, a setup step in the README; Probes):
  - an upload whose Create succeeded on the server while the app crashed, or was cancelled or deleted, before Create's event landed;
  - an upload whose record was pruned, or deleted while the app was not running;
  - a part that landed after both of Delete's Aborts.

  Cloudflare R2 aborts incomplete uploads after 7 days by default. A resume after the rule fired gets `NoSuchUpload` and starts again.
- **S3-compatible providers.** Equal-size parts, a signed payload per part and no checksum work on AWS, R2, Backblaze B2 and MinIO. R2 ignores `x-amz-acl` on Create, which changes nothing. A provider with a lower object limit answers `EntityTooLarge` at Complete through the existing failure path.
- **Logged.** `<name>` is the file name being sent, or the record id when there is no file (as `fileURL?.lastPathComponent ?? id` today).
  - `Upload: <name> multipart, <n> parts of <m> MiB, upload id <id>` at Create.
  - `Upload: <name> create failed: <error>`.
  - `Upload: <name> resumes at <done> of <n> parts`.
  - `Upload: <name> part list missing, listing parts`; `Upload: <name> part list unavailable, starting again`; `Upload: <name> part list rejected, listing parts`.
  - `Upload: <name> part <k> failed, retry <try>: <error>`.
  - `Upload: <name> multipart completed`.
  - `Upload: <name> multipart aborted`; `Upload: <name> multipart abort failed: <error>`.
  - `Upload: <name> source changed, starting again`; `Upload: <name> destination changed, starting again`; `Upload: <name> key changed, starting again`; `Upload: <name> key taken, starting again`; `Upload: <name> upload id gone, starting again`.
  - The upload id appears in the log only in the Create line. It never appears in a notice.
- **README.**
  - The Screen recording section's sentences on the single PUT (lines 358-360: "in one PUT of up to 5 GiB", "multipart is planned", "a Retry starts again from the first byte") become: a recording of 100 MiB or more uploads in 16 MiB parts, three at a time; a failed part is sent again; a failed or interrupted upload resumes from the parts already sent when you retry, also after a relaunch, unless it waited more than 7 days, when it starts from zero; a recording over 625 GB is kept and *Not uploaded* says why.
  - Line 373, "A recording that was uploaded and has no local file cannot be dragged", becomes: dragging it downloads it first, with progress on the card (Drag-out).
  - Lines 387-388 ("Pause, uploads over 5 GiB, a separate upload lane for videos, dragging an uploaded video that has no local copy, and URL commands for recording are planned") become: pause and a separate upload lane for videos are left out.
  - The Upload section gains a `Large uploads` paragraph: the IAM actions an upload-only key needs for multipart (`s3:PutObject`, which covers Create, UploadPart and Complete; `s3:AbortMultipartUpload`; `s3:ListMultipartUploadParts` for a resume whose part list was lost), that the drag-out download is a signed GET and needs `s3:GetObject`, as Copy Image does; and the lifecycle rule as JSON with the get, merge and put steps from Probes, with why: an upload never finished is billed until it is aborted, TidyShot aborts the ones it knows about, and the rule aborts the rest.
- **Checklists.** In `docs/testing/recording-r1-manual-checklist.md`: line 272 (the 5 GiB refusal) is replaced by R4's 625 GB refusal; lines 308 and 313 ("cannot be dragged") point to R4's drag-out download; lines 330 and 331 (the 5 GiB check before the counter, and "over 5 GiB") read the 625 GB check. Each changed line names R4 so the history stays readable.

## Drag-out download

- **When it starts.** A time-based record (an MP4 or a GIF **(the design's call)**: the scope says video, and a GIF with no local file has the same gap) with no local file and an empty drag folder, uploaded, not marked `Sound not muted`. Today its card has no drag file and nothing downloads. In R4 the download starts when a drag on the card passes the 3 pt threshold with no `dragFileURL` (`QuickAccessCardDragSource.mouseDragged`, through a new `model.onDownloadForDrag`), not on the press **(the design's call)**. A press is also the click that opens the video (R1), so R1's reason stands, and the user has to move the card to ask for the file. Neither a restored card's appearance nor Restore Closed Overlay downloads a video (`prefetchDragFile` keeps its early return for `isTimeBased`). There is no menu item for it **(the design's call)**.
- **The download.** `AppCoordinator.downloadDragFile(recordID:)` in `+DragOut.swift`, under `downloadingDragIDs: [UUID: Task<URL?, Never>]` (new stored state beside `stagingVideoIDs`), one per record. It uses the signed GET from `downloadSource(of:title: nil)` **(the design's call)** over the public URL: one auth path, the one Save As… and Trim's download use, and a private bucket works. Copy Image already depends on `s3:GetObject`.
  - The new `S3Destination.download(key:to:progress:)` is built on `session.downloadTask(with:)` with a task delegate (`UploadProgressDelegate` gains `didWriteData`, reporting `totalBytesWritten / totalBytesExpectedToWrite` through the same throttle), bridged with a continuation. The delegate path is the stated choice because it is Apple's documented way to get download progress.
  - URLSession removes its temporary file when `didFinishDownloadingTo` returns. So the delegate, inside that callback, moves the file at once to a path it owns, `Drag/.downloads/<uuid>` (outside every record's folder, on the same volume). It then reads the status there. On a non-2xx it reads the error body from that file and removes it. Only then does it resume the continuation.
  - Back on the main actor, the coordinator checks the drag generation. When it still matches, the file is renamed into `Drag/<id>/<name>` with `DragFileStore.adopt(id:name:moving:)`, under the name `DragFileName.name(for:suggestion:)` gives, as every drag file. When it does not match, the file is removed.
  - The expected size is `Content-Length`, and `byteCount` when the response has none. Redirects are refused and a non-2xx is the usual `UploadError`, as in `download(key:to:)`.
- **Progress.** The card's status becomes `QuickAccessStatus.downloading(Double)`, drawn like `.uploading`: the small circular ring with the text `Downloading…` and the file label under it. The coordinator pushes it through `QuickAccessController.setDownloading(_:for:)`, as it pushes `isOptimizing`. The status is the coordinator's flag, not a record field, because the record does not change. The row's detail reads `Downloading` while the task runs (`downloadingVideoIDs` in `RecentCaptureFormatting.detail`, as `isOptimizing` reads) **(the design's call)**. The auto-close countdown treats a running download as it treats `isDraggingOut`: the card stays while it downloads.
- **The hand-off.** When the file lands, `overlay.setDragFile(url, for:)`. If the button is still held, the existing wait in `mouseDragged` starts the session on the next mouse-dragged event; otherwise the next drag carries the file at once. No receiver ever sees a partial file: URLSession's temporary file is never on the pasteboard, and the move is a rename. This is 2.9's rule: the drag hands over a file URL to a copy in the container, and the session starts only once the file exists. The 60 s clean-up after the card closes and the removal on Delete apply to the downloaded copy as to any drag file. A card restored after the clean-up downloads again.
- **A press, a second drag and Save As… during a download.** A press runs `prepareDragFile` → `stageVideoDragFile`, which, with a download running, awaits it and hands its result to the card instead of reading the empty folder. A second drag past the threshold during the download starts nothing (`downloadingDragIDs` has the id) and waits as the first did. Save As… (`saveVideoCopy`) awaits a running download, then copies the landed file, so it does not start a second GET. With no download running it behaves as today.
- **Cancel.** Closing the card, for any reason, cancels the download (`overlayDidClose` cancels `downloadingDragIDs[id]` before `scheduleDragCleanup`), and so do Delete and the clean-up's `removeDragFolder`. A `dragGenerations` bump makes a download that finishes anyway drop its file, as `prefetchDragFile` does. There is no Cancel button on the card **(the design's call)**: the card's Close badge is the cancel. URLSession removes its own temporary file on cancel. Logged `Drag-out download for <id> cancelled`.
- **Failure.** The card shows `Download failed` (`QuickAccessStatus.downloadFailed(String)`, the error as the status's tool tip) with no Retry button **(the design's call)**: the next drag past the threshold tries again, and the drag is how the user asks for the file. The drag folder stays empty, and nothing posts, as the image prefetch posts none.
  - The failed task's `NSURLSessionDownloadTaskResumeData`, when it has any, is kept in memory with the time the request was signed: `dragDownloadResume: [UUID: (data: Data, signedAt: Date)]`. Resume data replays the original request with its `x-amz-date`, and S3 accepts that signature for 15 minutes from signing. So a retry resumes with `downloadTask(withResumeData:)` only while less than 14 minutes have passed since `signedAt`; after that, or with none, it starts again with a new signature **(the design's call)** (G2). A download that runs longer than 14 minutes therefore never resumes.
  - Resume data is dropped on Delete and when the card closes. Logged `Drag-out download for <id> failed: <error>`, as today's prefetch logs.
- **Disk space** **(the design's call)**. Before it starts, `RecordingLimits.hasRoom(for: byteCount, freeBytes: freeBytes(at: Drag/))` must hold (the file's size plus 1 GB, the margin a recording keeps). Otherwise the card shows `Download failed` with `Your disk is almost full.` (`RecordingLimits.diskFullText`) as its tool tip, nothing is requested, and `Drag-out download for <id> refused, not enough disk space` is logged. An unreadable value, or a record with no `byteCount`, counts as enough, as elsewhere. The temporary file and `Drag/` are on the container's volume, so the move needs no second allowance. A disk that fills during the download fails the task, which is a failure as above.
- **Open, Copy File, Trim.** Unchanged: a thumbnail click opens the link, Copy File still needs a local file (a downloaded drag copy is not a local file; it is in `tmp`), and Trim downloads its own copy into `tmp/Trim` as today.

## The Settings prompt's deferral reason

`requestAccessFromSettings` logs why a prompt was deferred. Today the reason is `the <name> prompt is open` when a prompt is open and otherwise `a capture is running`. With only a save in flight (`recordingPhase == .saving`, `isCapturing` false, no prompt), as while a GIF converts, that is false. The pure `settingsPromptDeferralReason(phase:isCapturing:askingPermission:) -> String?` gives, in order:
- `the <microphone|camera> prompt is open` when a prompt is open;
- `a capture is running` when `isCapturing` (a count-in and a recording always hold the lock, so this stays their reason);
- `a recording is being saved` for `.saving`;
- nil otherwise. That is the case where `settingsPromptStep` asks, so the caller never logs it.

The log line is `Recording: <microphone|camera> prompt from Settings deferred, <reason>`. Nothing else changes, and the R3 checklist's line for the toggle during a recording stays true.

## Settings summary (R4)

- **No new setting, key or entitlement.** The General tab's captions do not change. `project.yml` does not change.
- **Record changes:** `CaptureRecord.multipart: MultipartUploadState?` (nil; `decodeIfPresent`). `UploadError.noSuchUpload`, `.partsRejected(body:)` and `.completeError(code:body:)`. `UploadEvent.started` gains `fraction`; `UploadEvent.multipartStarted(id:state:)`. `CaptureRefusal.recordingStarting` and `.recordingRunning`. `URLCommandError.unknownActionForKind(value:command:)`. `QuickAccessStatus.downloading(Double)` and `.downloadFailed(String)`.
- **New stored state** (`AppCoordinator.swift`). Drag-out group: `downloadingDragIDs: [UUID: Task<URL?, Never>]`, `dragDownloadResume: [UUID: (data: Data, signedAt: Date)]`, `downloadingVideoIDs: Set<UUID>` (for the rows; cleared with the task). Recording group: `recordingStartCancelled: Bool`. Multipart adds none: the record and the sidecar hold its state.
- **New folders:** `Application Support/TidyShot/multipart/` (sidecars and kept Clop copies) and `tmp/Drag/.downloads/` (a landed download before its rename).
- **Constants:** threshold 100 MiB, part 16 MiB to 64 MiB, 10,000 parts, 3 in flight, 625 GiB refusal, 2 restarts per job, state files dropped after 7 days; resume data used up to 14 minutes after signing.
- **Removed:** `RecordingLimits.singleUploadBytes`, `fitsSingleUpload`, and the 5 GB text.
- **No new package.** Foundation's URLSession, CryptoKit and TidyShot's signer cover multipart and the download. No GPL code is read or copied.
- **Files.**
  - New: `TidyShot/Upload/MultipartPlan.swift` (pure), `MultipartUploadState.swift` (the record's state, `MultipartPart`, `MultipartRef`), `MultipartStore.swift` (the sidecar), `MultipartRequests.swift` (pure, shared with M1), `MultipartXML.swift` (the element scans, shared with M1), `S3Destination+Multipart.swift`; `TidyShotTests/StubURLProtocol.swift` (moved out of `S3DestinationTests.swift` so the multipart and download suites share it).
  - Changed: `Destination`, `S3Destination`, `S3DestinationConfig`, `UploadQueue`, `UploadProgressDelegate`, `UploadError`, `UploadEvent`, `UploadJob`, `RecordingLimits`, `RecordingSavePlan`, `CaptureRecord`, `CaptureDeletion`, `URLCommand`, `URLCommandHandler`, `CaptureRefusal`, `SelectionController`, `SelectionView`, `SelectionOutcome`, `QuickAccessModel`, `QuickAccessView`, `QuickAccessController`, `QuickAccessCardDragSource`, `RecentCaptureFormatting`, `AppCoordinator.swift`, `+Recording`, `+Upload`, `+Delete`, `+DragOut`, `+RecordActions`, `+Overlay`; the README and the R1 checklist lines named under Multipart, Checklists.
  - Used unchanged: `S3Signer` (it already canonicalises the query), `URLCommandGate` (`capturesWithoutSelection` carries the rule), `DragFileStore` (`adopt` is reused), `GeneralSettingsView`.

## Tests (Swift Testing)

Each suite pins pure decisions. The real bucket, the drags and the URL launches are hand checks in `docs/testing/recording-r4-manual-checklist.md`, which the plan's last task writes at close-out, as R3's was. Test files for multipart stay at a few hundred MiB at most and are made sparse with `FileHandle.truncate(atOffset:)`. The plan's threshold and part size are injectable (`MultipartPlan(threshold:partSize:inFlight:)`), so most queue tests use a 1 MiB threshold and 256 KiB parts, and the stub enforces the 5 MiB minimum only in the test that checks `EntityTooSmall`.

- `URLCommandTests`: `record-screen` and `stop-recording` parse; `record-screen` takes `action`, the rect and `display`, and `stop-recording` takes none and ignores them; `action=upload` and `save` parse, and `copy`, `annotate` and `pin` give `.unknownActionForKind` with `Unknown action “copy” for record-screen. Use upload or save.`, while `action=bogus` still gives `.unknownAction`; `record-screen` is never `capturesWithoutSelection`, with or without a rect, and neither is `stop-recording`; the `capturesNothing` list holds `stop-recording`; `isCapture`, `takesAction` and `takesArea` for both over `allCases`.
- `URLCommandGateTests`: `everyCommand` grows from 16 to 19, and the commands that need the second switch stay the four of today; `record-screen` with and without a rect and `stop-recording` run with the first switch alone; off refuses both.
- `URLCommandHandlerTests`: `record-screen` reaches `startRecording(intent:preselect: nil)` with the intent's action, and with a rect `startRecording(intent:preselect:)` with the resolved `ScreenRect`; a rect under 32×32 pt (after clipping) posts `The area must be at least 32 by 32 points to record.` and reaches nothing; `record-screen` is dropped for each refusal (`.captureRunning`, `.recordingStarting`, `.recordingRunning`, `.permissionPrompt`) and after a queued capture command ran first, with `dropReason` giving `a capture is running`, `a recording is starting`, `a recording is running`, `the microphone prompt is open` and `a queued capture command ran first`; `stop-recording` reaches `stopRecordingCommand(sender:)` with the cleaned sender under every refusal; in a launch burst, `record-screen` then `stop-recording` reach the target in that order, and the stop is not held behind the start (the recorder's `startRecording` returns at once, as the real one does).
- `SelectionOutcomeTests`: in `.recording` mode, a click in the preset gives `.area(preset)` even over a highlighted window; a click outside it with a highlight gives `.window`; a drag gives its own rect; with no preset nothing changes.
- `ShortcutsTests`: `recordingStartsFromURL(phase:askingPermission:isQuitting:)` starts in `.idle` and `.saving` only, never with a prompt open or while quitting; `recordingStopCommandAction(for:)` is `.stop` for `.recording`, `.cancelCountIn` for `.countIn`, `.nothing` for `.idle` and `.saving`; `captureRefusal(isCapturing:askingPermission:recordingPhase:)` gives `.recordingStarting` for `.countIn`, `.recordingRunning` for `.recording`, `.captureRunning` for a lock held in `.idle` and in `.saving`, the prompt when only a prompt is open, and nil otherwise; `settingsPromptDeferralReason` gives the prompt's text first, `a capture is running` with the lock held, `a recording is being saved` for `.saving` alone, and nil when nothing defers.
- `MultipartPlanTests` (pure): `uses` is false under 100 MiB and for `.data`, true at 100 MiB; `partSize` is 16 MiB up to 156.25 GiB, `ceil(size / 10,000)` rounded up to a MiB above it (17 MiB at 160 GiB), 64 MiB at 625 GiB, nil above; `partCount` and each part's byte range, the last part shorter; `fits` at the 625 GiB boundary; `resumeDecision` resumes when location, key, size and date match, and starts over on each mismatch with its reason; a fixed-key job with a different stored key starts over; `fraction(doneBytes:inFlightBytes:total:)` never exceeds 1.
- `MultipartXMLTests` and `MultipartRequestsTests` (both new): `UploadId` from a Create body; an `Error` with `Code` and `Message` from a 200 Complete body and none from a plain one; a ListParts page with `IsTruncated` and `NextPartNumberMarker`; the Complete body written in ascending order with the ETags quoted as received; Complete's headers carry `content-type: application/xml`; Create's carry `content-type`, `cache-control` when given, and `x-amz-acl` only with `sendPublicReadACL`.
- `UploadErrorTests` (new): `noSuchUpload` and `partsRejected` are not retryable and their descriptions are pinned; `completeError` is retryable for `InternalError`, `SlowDown` and `ServiceUnavailable` and not for `EntityTooLarge` or any other code; the existing cases keep their rule.
- `S3SignerTests`: canonical requests for `POST ?uploads` (query `uploads=`), `PUT ?partNumber=7&uploadId=…` (sorted, encoded) and `POST ?uploadId=…`, path-style with the dotted bucket, against hand-computed vectors; `objectURL(for:query:)` and the canonical query agree on every pair.
- `S3DestinationTests` with `StubMultipartBucket`, an in-memory multipart S3 behind `StubURLProtocol` that parses the method and the query:
  - Create returns an id and stores the signed `content-type`, `cache-control` and ACL headers.
  - A part is stored with an ETag and overwrites an earlier part of the same number.
  - Complete fails with 400 when its `Content-Type` is missing or `application/x-www-form-urlencoded`, as AWS does. It checks ascending order, every ETag (`InvalidPart` on a wrong one) and `EntityTooSmall` (in the one test with the 5 MiB minimum on). It can answer a scripted 200 with `<Error>`, which throws `completeError` with its code.
  - Abort gives 204 then 404, both accepted, and the call reports which.
  - ListParts pages at a scripted page size.
  - `NoSuchUpload` on a part, on ListParts, on Complete and on Abort.
  - `objectSize` on a present and a missing key.
  - A redirect is refused.
  - Each request's `x-amz-content-sha256` equals the SHA-256 of its body (`bodyBytes(of:)`).
- `UploadQueueTests` with `FakeDestination` extended with the six calls:
  - A `.file` job at the threshold goes multipart, one under it single PUT.
  - Parts are sent 3 at a time at most (the fake counts the overlap) and in order.
  - A part that fails retries alone under the policy while the others go on. A part out of tries fails the job with `Part <k> of <n>: <error>` after one pass (no job-level retry), and leaves the sidecar with the parts done.
  - Create, ListParts and Complete each retry under the policy, and a Create out of tries fails the job.
  - A cancel during parts waits for every part task and delivers one `.cancelled` with the reserved key.
  - `multipartStarted` is delivered before the first part, and the sidecar is rewritten after each part, with the upload id.
  - A resume sends only the missing parts, starts at the done fraction and completes.
  - A resume whose sidecar is missing, or holds another upload id, lists parts and trusts those of the stored size.
  - A resume of a template job HEADs the stored key: absent goes on, present at `byteCount` counts as uploaded, present at another size aborts, draws a new key and restarts.
  - `noSuchUpload` on a part restarts under the same key with `attempt` 2. `noSuchUpload` on every Create's first part fails the job after 2 restarts.
  - `noSuchUpload` on a Complete with `completeSent` true asks `objectSize` and counts a matching size as uploaded.
  - A Complete 200 with a retryable `<Error>` retries and then completes; one with `EntityTooLarge` fails the job.
  - `partsRejected` lists parts, resends the ones that differ and completes; a second one in the job restarts.
  - A job with `abortFirst` aborts it before its Create.
  - A template key is reserved once per upload id; the fraction counts in-flight bytes.
- `UploadStartTests` (new; `MultipartPlan.startStep(decision:)`, the pure rule `startUpload` follows after `resumeDecision`: whether Clop runs, whether a counter is drawn, which file is sent and what is aborted first): a stored state whose source matches resumes from `sourcePath`, skips Clop and draws no counter; a state whose source differs starts over with Clop as today and carries `abortFirst`; a state at another location starts over and leaves its abort to the coordinator; a resume after a first attempt with Clop off sends the record's file even with Clop running now, so a Clop result is never spliced onto the original's parts.
- `RecordingSavePlanTests`: the new notice text, `.none`, and R1's move rules unchanged. The 625 GiB boundary is `MultipartPlanTests`' `fits` test. `UploadRefusalTests` does not change: `uploadRefusal(for:isTrimming:)` has no size rule. `RecordingLimitsTests` loses the 5 GiB test.
- `CaptureRecordTests` and `CaptureDeletionTests`:
  - `multipart` round-trips, and old history decodes it nil.
  - A record whose state has a `sourceModified` with sub-millisecond digits is saved and loaded through `HistoryStore`, and `resumeDecision` on the loaded state against the same file attributes resumes.
  - `aborts(for:)` lists the stored upload id with its key and location, and nothing without state.
  - `objects(for:)` lists `multipart.key` for a `.failed` record with state, once when it equals `uploadedKey`, and `confirmationText` counts it.
  - `HistoryStore.load` keeps `multipart` when it marks an interrupted upload failed.
- `MultipartStoreTests`: write, read, a missing or corrupt sidecar reads nil, atomic replace, remove; keeping Clop's copy moves it into `multipart/<id>.mp4`; the launch sweep removes entries with no record or no state, removes the files of a state older than 7 days and keeps its record field, and keeps the rest.
- `EditorUploadPlanTests`: a failed multipart replace returns the record to `.uploaded` at the old link with `uploadIsStale` and `multipart` kept.
- `DragDownloadTests` with `StubURLProtocol`, the download routed into a temporary `Drag` folder: a body delivered in several chunks with `Content-Length` reports increasing fractions and lands under the key's name; the landed file is moved out of URLSession's temporary location before the delegate callback returns; a transport failure mid-body leaves the folder empty and reports the error; a 403 reports its excerpt; a cancel leaves the folder empty; a response with no `Content-Length` uses `byteCount`; a resume request carries a `Range` header (the stub records it).
- `DragDownloadRuleTests` (pure): a download starts only for a time-based record with no local file, an empty folder, an upload, no `Sound not muted` mark and none running; the disk check at `byteCount + 1 GB` with nil counted as enough; resume data signed less than 14 minutes ago is used and older is dropped; the auto-close rule waits during a download as during a drag.
- `QuickAccessModelTests` and `RecentCaptureFormattingTests`: `.downloading` draws the ring with `Downloading…`; `.downloadFailed` reads `Download failed` with the error as its tool tip and offers no Retry; the row's detail reads `Downloading` while the id is downloading, else as today.
- `AppSettingsTests`: nothing new.

The coordinator is not built in tests, so two rules are hand checks: `handle` setting the bar to `.started`'s fraction, and `recordingStartCancelled` stopping a start during the settle delay.

**Hand checks** include:
- **URL commands.**
  - `open 'tidyshot://record-screen'` shows the selection, the count-in and the bar; `action=save` and `action=upload` end as the setting says.
  - A rect with the second switch off shows in the selection; Return does nothing; a click inside it records it after the count-in; a drag replaces it; Escape cancels.
  - `stop-recording` during the count-in cancels it and nothing records, with `Count down before recording` on and off (off: send it within the settle delay, for example from a Keyboard Maestro macro that sends `record-screen` with a rect, clicks, and sends `stop-recording`); during the recording it stops it with `Recording stopped`; otherwise it logs `did nothing`.
  - `record-screen` during a recording and during a screenshot's selection is dropped with its log reason.
  - The first microphone or camera prompt (reset with `tccutil`) shows on a URL start before the selection and never in a video.
  - A cold launch from `tidyshot://record-screen`, and a cold launch from a burst of `record-screen` then `stop-recording`, whose stop logs `did nothing` at once.
  - Both commands from Raycast and Keyboard Maestro.
- **Multipart**, with a 300 MB and a 6 GB recording (upload-only, Clop off, then Clop on), to `snap.tky.io`:
  - The ring moves, `footprint` stays under 120 MB, the link plays through CloudFront, and the key template drew one name.
  - Wi-Fi off for 30 seconds mid-upload resumes without a visible restart.
  - Wi-Fi off for two minutes fails with `Part <k> of <n>: …`, and Retry resumes at the done fraction, with the bar at that fraction at once.
  - Quit mid-upload, relaunch, Retry Failed Uploads resumes (the log's `resumes at` line). `kill -9` mid-upload, relaunch, Retry resumes.
  - Delete mid-upload aborts (the AWS console lists no incomplete upload) and the key is gone. Delete of a failed upload aborts and its confirmation counts the object.
  - `Upload Trimmed` on a 300 MB trimmed file replaces the link in parts, and a failure keeps the old link.
  - A Clop result kept in `multipart/` is used by Retry and gone after the upload.
  - The lifecycle rule is on the bucket.
- **Drag-out**, with a restored card for an uploaded recording with no local file:
  - A drag starts `Downloading…`, the card stays open past its auto-close, the file lands, and the next drag drops into Finder and Slack whole.
  - A drag held through a short download starts the session when it lands.
  - Save As… during the download waits and saves.
  - Close during the download cancels it and the folder is empty. Delete during the download.
  - Wi-Fi off during it shows `Download failed`, and a drag soon after resumes (the log's fraction continues).
  - A disk check refusal shows `Your disk is almost full.` (a small APFS volume as the container's is a hand set-up; or read the log).
  - A GIF with no local file downloads too.
- **Settings:** turning `Show webcam bubble` on while a GIF converts logs `… deferred, a recording is being saved`.

## Deferred

`record-fullscreen` and a `display`-only `record-screen`; a `window` parameter; `format`, `microphone` and `duration` parameters; a key that records a preselected rect; a Cancel button or a `Download for Dragging` menu item on the card; a public-URL download; a ListMultipartUploads sweep; `If-None-Match` and `x-amz-mp-object-size` on Complete; the stale-upload question.

## The design's calls (for Tim to overrule)

1. `record-screen` keeps CleanShot's name and parameters. `stop-recording` is TidyShot's own name with no alias, as CleanShot has no stop command (URL commands, Names).
2. `record-screen` takes `action=upload|save` only, refusing `copy`, `annotate` and `pin` with `Unknown action “<value>” for record-screen. Use upload or save.` (Parameters).
3. A rect under 32×32 pt is refused by the handler with `The area must be at least 32 by 32 points to record.` (Parameters).
4. A rect is preselected in the recording selection, as in CleanShot, and only a click inside it records it; no key does, and it needs only the first switch. It does not record at once behind the second switch (Selection with a rectangle).
5. `startRecording` returns once the start is under way, so the handler and a launch burst never wait on a recording (Names).
6. Recording notices do not name the URL's sender (What `record-screen` does, idle).
7. `CaptureRefusal` gains `.recordingStarting` and `.recordingRunning`, and dropped commands log `a recording is starting` and `a recording is running` (What `record-screen` does).
8. A `record-screen` during `.saving` starts a new recording, as the shortcut does (What `record-screen` does, saving).
9. `stop-recording` cancels a count-in, and a cancelled count-in never records, through `recordingStartCancelled` (What `stop-recording` does).
10. `stop-recording` with nothing to stop posts no notice and only logs (What `stop-recording` does).
11. Multipart from 100 MiB, for every `.file` payload (Multipart, When).
12. Parts of 16 MiB, raised to `ceil(size / 10,000)` from 156.25 GiB, capped at 64 MiB; 625 GiB refused with `The recording is larger than 625 GB, too large to upload.` (Parts).
13. 3 parts in flight per job, a constant (Concurrency).
14. Parts are read into `Data` and sent with `upload(for:from:)`, not through temporary files or a stream (Reading a part).
15. Each request retries on its own; a multipart job is not retried as a whole; at most 2 restarts per job (Failure and retry).
16. Clop's result is kept in `multipart/<id>.mp4` for a resume, and a Retry whose stored source still matches resumes from it without running Clop (What is persisted; Resume).
17. The card and row show no part count, only the byte fraction (Progress).
18. No upload resumes by itself at launch; Retry and Retry Failed Uploads resume (Resume).
19. The launch sweep aborts nothing, and removes the sidecar and the kept copy of a state older than 7 days (What is persisted).
20. Pruning aborts nothing; the lifecycle rule covers it (Cancel and Delete).
21. No ListMultipartUploads sweep; the lifecycle rule is the backstop, as a README setup step (Orphaned uploads).
22. The drag-out download starts at the drag threshold, not on the press, and has no menu item (Drag-out, When it starts).
23. A GIF with no local file downloads as a video does (When it starts).
24. The download uses the signed GET, not the public URL (The download).
25. The row's detail reads `Downloading` during it (Progress).
26. No Cancel button: closing the card cancels the download (Cancel).
27. `Download failed` has no Retry button; the next drag retries (Failure).
28. A failed download's resume data is used while less than 14 minutes have passed since the request was signed, then dropped (Failure).
29. A download is refused unless the disk has the file's size plus 1 GB free (Disk space).

## R4 built notes (2026-10-28)

Built on `recording-r4`, cut from `main` at 5bd11c3 (R3 merged). The design and plan (7f2095e, bd32310, 5f091fb, 605b398), then one commit or more per task: Task 1 8916fc3, e3a6cae and 177de74; Task 2 1649d6a; Task 3 dc3a9cb; Task 4 7a2b0e1; Task 5 c236055; Task 6 a0fa539; Task 7 9ba432e; Task 8 b61659f; Task 9 cc67ade; Task 10 681a104 and b092475; Task 11 b142026; Task 12 20040b5 and dde2805; Task 13 b9f4e1f; Task 14 c6549e7 and 546b052; Task 15 ef5f0dc; Task 16 932f5ab; Task 17 6b4f553 and 0da6fd4; then this close-out. Nothing is pushed.

- **Gates.** Both are open, because neither probe has run (Probes, Results).
  - **G1 (M1)** holds the IAM sentences of the README's `Large uploads` paragraph, which says only that the key's multipart permissions are pending the check against the real bucket, and the merge. The `s3:GetObject` sentence for the drag-out download does not depend on M1 and goes in with them.
  - **G2 (D1)** holds Task 16's "Resume a failed download" step, which is not built: `dragDownloadResume` and its drops on close and Delete are in place, but nothing writes or reads it. Every failed download starts again with a fresh signed GET, which is the design's fallback if D1 fails.
  - No held step was shipped without. If Tim chooses to, this section says which.
- **Suite and build.** `Test run with 2088 tests in 174 suites passed` (the baseline's 1877 in 166, plus 211 tests in 8 new suites: `MultipartXMLTests`, `MultipartRequestsTests`, `MultipartPlanTests`, `UploadStartTests`, `MultipartStoreTests`, `UploadErrorTests`, `DragDownloadTests`, `DragDownloadRuleTests`). The Release build succeeds. `git diff --stat main -- project.yml` prints nothing, so the generated Info.plist and entitlements are unchanged.
- **Strings.** Every string, log line and error description the design gives was grepped in the finished code. None had drifted. The log lines that carry a reason are built from `MultipartStartOverReason.logText` (`source changed`, `destination changed`, `key changed`) and the queue's `Restart` reasons (`key taken`, `upload id gone`, `part list unavailable`), so a grep for the whole line finds the pieces, not one literal.
- **Surface check.** The coordinator split's Task 7 command, with `startRecording` and `stopRecordingCommand` added to its member list, prints nothing. One outside read is new and is not a write: `RecentCapturesMenu` reads `coordinator.downloadingVideoIDs`, as it reads `optimizingVideoIDs`.

### The eighteen gaps the plan filled

Each stands as built; the checklist asks Tim to confirm or overrule each.
1. `MultipartPart` lives in `MultipartXML.swift`, not `MultipartUploadState.swift`, so the probes' build line holds the type `MultipartRequests.complete` takes.
2. `MultipartRequests` builds no path: each call gives its method, decoded query pairs, extra headers and body. The app takes the path from `S3DestinationConfig.objectPath(for:)` and the probes from their own `/<bucket>/<key>`.
3. The job carries its source: `UploadJob.multipartSource` (location, path, size, modification date), set by the coordinator for every `.file` job whose size and date it read. The queue never needs the lane's location.
4. The queue logs through an injected closure (`log: @Sendable (String) -> Void`, `NSLog` in the app), so tests read its `Upload:` lines.
5. `RecordingController.isEnding`, so a second `stop-recording` during the stop wait logs `did nothing, no recording is running`. It is `isRunning && cause != nil`, not bare `cause != nil`, because `cause` is only cleared at the next run's reset.
6. `recordingStartCancelled` is reset in `recordingCountIn`'s `didSet`, on a change from false to true.
7. The download has its own delegate, `DragDownloadDelegate`, in `S3Destination+Download.swift`. `ProgressGate` is internal so both delegates use it.
8. `AppCoordinator.multipartFiles: MultipartStore` is a collaborator beside `pendingFiles`, made in `init`. It holds no state.
9. A resumed template job that must draw a new key names it from `TemplateContext(date: record.timestamp)`, whose counter is 0. Tim's template has no `{counter}`.
10. The preset click reaches `SelectionOutcome.resolve` as `clickInPreset: CGRect?`, the preset rect when the press and the release were both inside it.
11. The card's drag view asks for the download once per press (`askedForDownload`, reset on `mouseDown`).
12. The card's download state is `QuickAccessModel.dragDownload: DragDownloadStatus?` (`.running(Double)`, `.failed(String)`), set by `QuickAccessController.setDownloading(_:for:)`. `Download failed` uses `exclamationmark.triangle.fill` in red, as `Upload failed` does.
13. `S3Destination`'s `httpResponse`, `failure` and `excerpt` are internal, and so is `errorBody(at:)` (Task 14 found it needed the same change). Their bodies and the SECURITY comment did not change.
14. `MultipartAbortResult` (`.aborted` for 204, `.notFound` for 404) is what `abortMultipartUpload` returns.
15. `DragFileStore.landingURL()` makes `Drag/.downloads/` and returns `Drag/.downloads/<uuid>`. `sweep()` already removes it with the rest of `Drag`.
16. Resume data travels in the error: a failed download throws its `URLError`, and the coordinator keeps `downloadTaskResumeData` with `signedAt`, read as `Date()` just before the first `download` call. Not built (G2 held).
17. The drag-out download's form differs from the design's wording, with the same behaviour:
    - The card's status lives on its model (Gap 12), and `downloadDragFile` sets it with `setDownloading(_:for:)` directly. `pushCardFlags` and the refresh do not push it, as the design's opening list and Progress say: `overlay.update(record:)` leaves the model's flags alone, and a close cancels the download, so there is nothing to restore.
    - Two files the design's Files list does not name: `S3Destination+Download.swift` and `Overlay/DragDownloadRule.swift`.
    - The call is `download(key:to:expectedBytes:resumeData:progress:)`, not `download(key:to:progress:)`.
18. `urlRecordingStartPending` in the Recording group: `startRecording` sets it before its `Task` and `startRecordScreen` clears it when the lock's body runs or refuses. A second `record-screen` handled in that gap logs `Recording: URL start ignored, a recording is starting`, so it is a logged drop and not a lost race at the lock.

### What was built differently from this design, task by task

- **Probes (Task 1).** M1's halfway pause holds three parts read into memory just before they are sent, so the `Footprint:` reading shows three parts held and `phys_footprint_peak` is the number judged against 120 and 250 MB (177de74). D1 copies the partial file the resume data names before step 3 and puts it back before step 4, because step 3 uses it up; when it cannot, it says a status-less step 4 is inconclusive. The plist layout it reads on macOS 26 is unverified. M1 aborts and stops when Complete or ListParts throws (e3a6cae). `MultipartRequests.Call` has an `init` that derives `payloadHash` from `body`, so no call carries a hash that does not match. `partsPage` returns `NextPartNumberMarker` as the body has it, and a caller checks `isTruncated` before using it.
- **Kinds and errors (Task 2).** `Kind.actions` is `[]` for a kind that takes no action. `parse` checks `Action(rawValue:)` first (`.unknownAction`), then `kind.actions` (`.unknownActionForKind`).
- **Phase rules (Task 3).** The two-argument `captureRefusal` is gone. `Recording: not started, the count-in was cancelled` logs when the flag stops a start the hand-off allowed; a countdown cancelled inside `selfTimer.run` returns nil silently, as before, and the URL stop's own line covers it.
- **Preset rect (Task 4).** `placePreset` does not call `makeKey`: the key window stays the one under the mouse and Escape works on any overlay view. The preset is not drawn during a drag, so the drag replaces it on screen. When the cursor is outside the preset over a window that overlaps it, the highlight is drawn after the preset and can cover part of its stroke.
- **URL commands (Task 5).** The 32 pt message is a `static let` on the handler (`recordingAreaTooSmallMessage`). `startRecording` logs only the quitting refusal; the others are the handler's drop lines.
- **Plan (Task 6).** `resumeDecision` checks location, then key, then source, so a destination change wins and only `.location` sends the abort to the coordinator. At exactly 156.25 GiB the part size stays 16 MiB.
- **Record (Task 7).** A trim does not clear a stale `multipart`; the resume's source check rejects a changed file (see Task 12's fix).
- **Store (Task 8).** A file whose name does not start with a record id is never removed by `sweep` or `remove`. `keepClopCopy` throws first when its source is gone, so an earlier copy is not removed for nothing.
- **S3 calls (Task 9).** `listParts` ends on a truncated page whose marker does not move, so a misbehaving server cannot loop it. A 404 that is not `NoSuchUpload` is an ordinary failure, and Abort maps any 404 to `.notFound`. The test bucket recomputes the SigV4 signature from the URL's decoded query, so a query that differs from the signed one fails. The stub's `MalformedXML` code for a Complete with the wrong content type is a guess at what AWS returns; only the 400 matters to the app.
- **Queue (Tasks 10 and 11).**
  - A sidecar that cannot be written fails the job, at all three writes (b092475), so Complete never goes out unless the sidecar says `completeSent`. A first write that fails leaves the upload id out of the record, and the lifecycle rule removes it.
  - `<try>` in `part <k> failed, retry <try>` is the attempt about to be made (2 for the first retry).
  - A part is read once and the same bytes are resent on a retry.
  - A resume sends no `.started` until it knows its done fraction: a template resume whose key already holds the upload ends with `.uploaded` and no `.started`, and one that restarts before its first part sends `.started(attempt: 2, fraction: 0)` with no attempt-1 event.
  - A second `partsRejected` in a job restarts with no reason line of its own.
  - Every abort of a start over or a restart is one try, not a retry loop.
  - A rebuilt sidecar has `completeSent: false`.
  - `UploadQueue.swift` is now about 750 lines. A split into `UploadQueue+Multipart.swift` would be mechanical and was not made.
- **Coordinator (Task 12).**
  - The kept Clop copy moves on the main actor (a rename), so nothing waits between the token being cleared and the enqueue.
  - `byteCount(of:)` returns the size and the modification date from one `resourceValues` read.
  - `fitsSingleUpload` became `fitsUpload`, which is `MultipartPlan.fits(byteCount:)` for a `.file` payload with a known size.
  - Fix (dde2805): a kept Clop copy outdated by a later trim of the record's own file starts the upload over. `MultipartPlan.keptCopyIsOutdated(stored:keptCopyFolder:recordFileModified:)` is true when `sourcePath` is inside the kept-copy folder and the record's file changed after `startedAt`; `startUpload` then passes a nil source to `resumeDecision`. Without it, a resume would complete the first trim's bytes over a second trim. The Resume section's sentence "A new Clop result never meets the old upload's parts" is true, and this covers a kept copy that outlives a change to the record's file.
- **Delete (Task 13).** A failing second Abort fails Delete like the first, and the second alert reuses `The object stays in the bucket.` for an Abort failure, though what stays is an incomplete upload.
- **Download (Task 14).** `DragDownloadDelegate` keeps a phase (`waiting`, `started`, `completed`, `resumed`), so a task cancelled before its continuation is handed over still resumes it (546b052). `download` starts with `try Task.checkCancellation()`, so an already-cancelled caller gets `CancellationError` and a cancel mid-transfer gets `URLError(.cancelled)`; the coordinator tells them apart by `Task.isCancelled`. Progress is also reported for a non-2xx body, so a fraction can reach 1 just before the call throws.
- **Card and row (Task 15).** `isDownloadingForDrag` is true only for `.running`, so a failed download does not hold the card open. `.downloadFailed` shows the file label under it and the message as the tool tip.
- **Drag-out (Task 16).**
  - `cancelDragDownload` leaves `downloadingDragIDs[id]` in place; the task's own end clears it, so a second download cannot start while a cancelled one winds down.
  - The progress hop sets `.running(f)` only while `downloadingVideoIDs` holds the id.
  - A `landingURL()` throw is handled like a source error: `Download failed` and the `failed:` log line.
  - A small race stays: a press's slow empty-folder read that finishes after a download has landed can reset the card's drag file to nil; the next press fixes it.
- **Single-PUT start over (Task 17, 6b4f553).** The concern from Tasks 12 and 13: a start over whose new file is under 100 MiB goes as one PUT, and the queue's single-PUT path never read `abortFirst`, so the stored upload was left to the lifecycle rule. Ruled a bug, because the design has the queue abort `abortFirst` on a start over without limiting that to multipart jobs. The single-PUT path now aborts it once before its retry loop, with the multipart path's `abortUpload` and log lines; a cancel during it delivers `.cancelled`; a failed abort is logged and the job goes on. The record's `multipart` stays until `.uploaded` clears it. Delete aborts it meanwhile (a second Abort on an already-aborted id answers 404, accepted), and a Retry before then decides start over again and aborts again with a 404.
- **README (Task 17).** The URL scheme, Security, Errors, Screen recording and Large uploads text is as the design says, except the IAM sentences (G1). The drop sentence also names the new reasons. `Large uploads` gives the lifecycle rule's JSON and the get, merge and put steps.

### Probe results

None yet (Probes, Results). The checklist has the blanks.

### Still open (the PR lists these)

- **G1 and G2** (above). The branch is not offered for merge while a step is held.
- **M1 and D1** are Tim's to run; **U1** and every hand check in `docs/testing/recording-r4-manual-checklist.md` have not run. The Release build has no Screen Recording grant, and a grant is Tim's to give.
- **The lifecycle rule** on `snap.tky.io`: Tim says it is there; nobody has checked.
- **Tim's IAM policy** against the actions the checklist's Setup lists; M1 shows which are missing.
- **The design's 29 calls and the eighteen gaps**: the checklist asks Tim to confirm or overrule each.
- **Reviewer notes** from each task's review (216 minors, in the local scratch `.superpowers/sdd/r4/minors-all.json`, not in the repository) go to the whole-branch review. The ones the task reports name as left alone are above (Tasks 10, 11, 13, 14, 16).
- **Untested by design:** the coordinator (`finishDragDownload`'s three-way choice, `abortUploads`, `startUpload`'s resume wiring, `handle` setting the bar to `.started`'s fraction, `recordingStartCancelled` stopping a start during the settle delay). The hand checks are the only verification.
