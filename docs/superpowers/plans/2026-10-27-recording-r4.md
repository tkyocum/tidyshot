# TidyShot Screen Recording R4, Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Two URL commands, `tidyshot://record-screen` and `tidyshot://stop-recording`, behind the same setting and gates as the capture commands. Multipart upload with resume for every recording or GIF of 100 MiB or more, in 16 MiB parts, three at a time, up to 625 GiB. Drag-out of an uploaded video or GIF that has no local file, as a signed download with progress on the card. And a true reason for a Settings prompt deferred while a recording is being saved.

**Architecture:** `docs/superpowers/specs/2026-10-27-tidyshot-screen-recording-r4-design.md` is the full specification: behaviour, types, strings, constants, log lines and tests. R1's design (`2026-10-21-tidyshot-screen-recording-design.md`), R2's (`2026-10-23-…-r2-design.md`) and R3's (`2026-10-24-…-r3-design.md`) hold wherever R4's does not change them. When this plan and the R4 design disagree, the design wins; stop and ask if it is unclear. The plan's own calls are listed under "Gaps this plan fills".
- **Pure decisions.** `URLCommand.Kind`'s rules and `actions`, `SelectionOutcome.resolve`'s preset click, the coordinator's static rules (`captureRefusal`, `recordingStartsFromURL`, `recordingStopCommandAction`, `settingsPromptDeferralReason`), `MultipartPlan` (threshold, part size, ranges, fraction, `resumeDecision`, `startStep`), `MultipartRequests`, `MultipartXML`, `CaptureDeletion.aborts(for:)`, the sidecar sweep's plan and `DragDownloadRule` decide everything that can be decided without a network, a screen or a drag, and are tested that way.
- **Thin shells.** `S3Destination+Multipart` and `S3Destination+Download` send what `MultipartRequests` and the signer build, and are tested against `StubURLProtocol` and a `StubMultipartBucket`. `UploadQueue` runs a multipart job over the `Destination` protocol and is tested with `FakeDestination`. The coordinator is not built in tests; its wiring is checked by hand.
- **The coordinator split** (`docs/superpowers/specs/2026-10-23-coordinator-split-design.md`) places R4's coordinator code as the design's opening list says: the URL entry points, the start-cancel flag and the deferral reason in `+Recording`; multipart's events, the resume decision, the Clop copy and Retry in `+Upload`; the aborts and the download's cancel on Delete in `+Delete`; the download in `+DragOut`; Save As…'s wait in `+RecordActions`; the card's download status and its cancel on close in `+Overlay`. New stored state goes in the class body in `AppCoordinator.swift` under its area's group.

**Tech Stack:** Swift 6 language mode with default `MainActor` isolation and `NonisolatedNonsendingByDefault`, Foundation (`URLSession` upload and download tasks with task delegates, `FileHandle`), CryptoKit (SHA-256), Swift concurrency (`TaskGroup`, `withTaskCancellationHandler`, `Mutex`), AppKit (the selection overlay, the card's drag view), SwiftUI (the card), Swift Testing, XcodeGen 2.46.

Work happens on the branch `recording-r4`, cut from `main` at 5bd11c3 (R3 merged). The R4 design is committed (7f2095e, bd32310); this plan is `docs: R4 plan`. Line numbers are at bd32310; once an earlier task has moved a member, find it by name.

## Probes Tim runs

Every probe is Tim's. M1 and D1 talk to his bucket; U1 records the screen. Nobody else runs them. The session running this plan asks Tim to run each one as soon as the task it waits on has landed, and writes his results into the design's Probes section with the date and the Mac. Build lines are the design's (Probes):

`xcrun swiftc -O -target arm64-apple-macos26.0 -o /tmp/<name> docs/superpowers/research/recording-probes/<name>.swift TidyShot/Upload/S3Signer.swift TidyShot/Upload/AWSCredentials.swift TidyShot/Upload/MultipartRequests.swift TidyShot/Upload/MultipartXML.swift`

Both network probes read `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY` and an optional `AWS_SESSION_TOKEN` from the shell's environment, use them for that run only and write them nowhere.

| Probe | What Tim runs | Touches | Ready after | Settles |
|---|---|---|---|---|
| M1 | `/tmp/r4-multipart snap.tky.io <region> <endpoint> <prefix>`, reading `footprint <pid>` at each halfway pause | the bucket (uploads, then deletes) | Task 1 | G1 |
| D1 | `/tmp/r4-download snap.tky.io <region> <endpoint> <key>` on an object of at least 100 MB | the bucket (reads) | Task 1 | G2 |
| U1 | the URL commands by hand (design, Probes, U1) | the screen | Task 5 | hand checks only |
| Setup | the lifecycle rule `AbortIncompleteMultipartUpload` after 7 days, by the README's get, merge and put steps | the bucket's configuration | Task 17 (the README text) | nothing; it must be on before the multipart hand checks |

## Gates

A gate that trips holds only the steps named here. The rest of its task and the later tasks go on, held steps stay unchecked until the design is amended and Tim says to go on, and the branch is not offered for merge while a step is held.
- **G1, multipart against the real bucket** (M1). Everything multipart builds and is tested against the stub first (Tasks 6 to 13). G1 holds two things: Task 17's step that writes the `Large uploads` paragraph's IAM sentences, and the offer to merge.
  - ListParts 403 (`s3:ListMultipartUploadParts` missing): the code already restarts the job when ListParts fails after its retries (Task 11). Task 17's paragraph then says that a resume whose part list was lost starts again with that key, and why.
  - Abort 403 (`s3:AbortMultipartUpload` missing): the README's policy keeps the action and Tim adds it to his key before the merge. Delete is not changed to swallow the 403.
  - A Complete whose 200 carries `<Error>`, `Cache-Control` or the ACL not reaching the object, or a `footprint` over 120 MB at 16 MiB parts or over 250 MB at 64 MiB parts goes back to Tim, with the merge held.
- **G2, resume data for a failed drag-out download** (D1). It holds Task 16's "Resume a failed download" step only. The download, its progress, its failure and the retry by a fresh signed GET land without it. If D1 shows no resume data, or a resume that does not continue with a 206, the held step is dropped and a failed download always starts again (design, Drag-out, Failure), with no other change.
- Task 18 runs after every held step has landed, or records in the Built notes any that Tim chooses to ship without.

## Global Constraints

- **Earlier constraints still apply.**
  - Minimum macOS 26.0, Swift 6 with MainActor by default and `NonisolatedNonsendingByDefault`, App Sandbox, XcodeGen, Swift Testing, ad-hoc signing, credentials only in the Keychain.
  - KeyboardShortcuts is the only Swift package. No new package, entitlement, Info.plist key or setting: `project.yml` does not change. No GPL code is read or copied: macshot, the Clop app, gifsicle, ffmpeg and gifski are off limits as sources. Multipart and the download are written from Apple's and AWS's documentation and TidyShot's own signer.
  - R1 to R3's decisions stand. The stale-upload question stays open: nothing is built for it. No pause and no separate upload lane.
- **Consent and privacy.**
  - `record-screen` never starts a recording without the user's drag or click in the selection. The microphone and camera prompts and the Screen Recording grant work as for the shortcut.
  - A recording marked `Sound not muted` is never uploaded, resumed, downloaded for a drag or dragged.
  - No upload id appears in a notice; the log names it only in the Create line. No credential, signature or session token is ever logged or put in a notice. Every error body still goes through `S3Destination.excerpt`, whose 200-character cap is load-bearing.
- **Never lose a recording.** Multipart never removes the record's own file. A kept Clop copy is removed only on `.uploaded`, on Delete, when its state is dropped and by the launch sweep. A refused upload (over 625 GiB) keeps R1's handling.
- **No network at launch.** No upload resumes by itself and the launch sweep aborts nothing.
- **Off the main actor.** Part reads and hashes run in `@concurrent` functions; the queue is an actor; the download's file move runs in its delegate callback. The pure types are `nonisolated` and `Sendable`.
- **The coordinator split's conventions.** New members start `private` in their area's file. `downloadingDragIDs` is written from `+DragOut`, `+Overlay` and `+Delete`, so its declaration carries the convention's `//` line naming the other writers. No new entry point for code outside the coordinator's family except what the URL handler reaches through `URLCommandTarget` (`startRecording(intent:preselect:)`, `stopRecordingCommand(sender:)`); Task 18's surface check lists them.
- **Exact strings, constants, log lines and type names** come from the design. Constants: threshold 100 MiB (104,857,600 bytes); part 16 MiB (16,777,216) to 64 MiB (67,108,864); at most 10,000 parts; 3 in flight; 625 GiB (671,088,640,000 bytes) refused; 2 restarts per job; state files dropped after 7 days; resume data used while less than 14 minutes have passed since signing.
- **Tests** use Swift Testing and never touch the network, the screen, a camera, a microphone or a real bucket. Multipart test files stay at a few hundred MiB at most and are sparse (`FileHandle.truncate(atOffset:)`). Run with:
  ```bash
  xcodegen generate && xcodebuild test -project TidyShot.xcodeproj -scheme TidyShot -destination 'platform=macOS' -derivedDataPath .build 2>&1 | grep -E "Test run with|error:|TEST"
  ```
  The baseline is the first run's line on this branch (R3's close-out recorded 1875 tests in 166 suites; review fixes after it may have added tests). When coreaudiod stalls on Tim's Mac the suite takes about 126 s instead of about 36 s; that is not a failure. The Release build is `xcodebuild -project TidyShot.xcodeproj -scheme TidyShot -configuration Release -derivedDataPath .build-rel build`.
- **Hand checks and probes are Tim's.** Implementers and reviewers do not run anything that records the screen, opens the camera or the microphone, plays sound, or talks to a real bucket, and never open or change privacy settings, run `tccutil`, or change the bucket's configuration. Probes are compiled, never run. Each task lists its hand checks; Task 18 puts them in the checklist, and each task's report says they were not run.
- **Commits.** Commit after every task with the message the task gives and no attribution lines. Never push and never switch branches.

## Gaps this plan fills

Each is this plan's call where the design is silent, or a change of form that keeps the design's behaviour. Task 18 records every gap in the design's Built notes, and the PR flags them.
1. **`MultipartPart` lives in `MultipartXML.swift`**, not `MultipartUploadState.swift`, so the probes' build line (the signer, the credentials, `MultipartRequests`, `MultipartXML`) holds the type `MultipartRequests.complete` takes and `MultipartXML.partsPage` returns. `MultipartUploadState.swift` holds the record's state, `MultipartRef` and `MultipartSidecar`.
2. **`MultipartRequests` builds no path.** Each call gives the method, the decoded query pairs, the extra headers and the body. The app takes the path from `S3DestinationConfig.objectPath(for:)` and the probes from their own path-style `/<bucket>/<key>`, as `S3DestinationConfig` is not in the probes' build.
3. **The job carries its source.** `UploadJob.multipartSource: MultipartSource?` (location, path, size, modification date) is set by the coordinator for every `.file` job whose size and date it read. The queue goes multipart when `plan.uses(payload:byteCount:)` holds for it, and builds `MultipartUploadState` from it, so the queue never needs the lane's location.
4. **The queue logs through an injected closure** (`log: @Sendable (String) -> Void`, `NSLog` in the app), so tests read its `Upload:` lines.
5. **`RecordingController.isEnding`** (`cause != nil`). `stopRecordingCommand` reads it, so a second `stop-recording` during the stop wait logs `did nothing, no recording is running`, as the design says, though the phase is still `.recording`.
6. **`recordingStartCancelled` is reset in `recordingCountIn`'s `didSet`**, on a change from false to true, which is exactly the design's "when `recordingCountIn` turns from false to true".
7. **The download has its own delegate**, `DragDownloadDelegate` in `S3Destination+Download.swift`, rather than `UploadProgressDelegate` gaining `didWriteData`: it holds the landing path and the continuation, which the upload delegate has no use for. It refuses redirects and throttles progress the same way. `ProgressGate` in `UploadQueue.swift` becomes internal so both use it.
8. **`AppCoordinator.multipartFiles: MultipartStore`** is a collaborator beside `pendingFiles`, made in `init` next to `history.json`. It is not state; the record and the sidecar hold the state.
9. **A resumed template job that must draw a new key** (the stored key was taken meanwhile) names it from `TemplateContext(date: record.timestamp)`, whose counter is 0, since a resume draws no counter. Tim's template has no `{counter}`.
10. **The preset click** reaches `SelectionOutcome.resolve` as `clickInPreset: CGRect?`: the preset rect when the press and the release were both inside it, nil otherwise.
11. **The card's drag view asks for the download once per press** (`askedForDownload`, reset on `mouseDown`), so a download that fails while the button is still held is not started again on every mouse-dragged event. The next press and drag retries.
12. **The card's download state** is `QuickAccessModel.dragDownload: DragDownloadStatus?` (`.running(Double)`, `.failed(String)`), set by `QuickAccessController.setDownloading(_:for:)`. `Download failed` uses `exclamationmark.triangle.fill` in red, as `Upload failed` does.
13. **`S3Destination`'s `httpResponse`, `failure` and `excerpt` become internal** (from `private`), so the two extension files use them. Their bodies and the SECURITY comment do not change.
14. **`MultipartAbortResult`** (`.aborted` for 204, `.notFound` for 404) is what `abortMultipartUpload` returns.
15. **`DragFileStore.landingURL()`** makes `Drag/.downloads/` and returns `Drag/.downloads/<uuid>`. `sweep()` already removes it at launch with the rest of `Drag`.
16. **Resume data travels in the error.** A failed download throws its `URLError`, whose `downloadTaskResumeData` the coordinator keeps with `signedAt`, the time the first request of that download was signed. A resume replays that request, so `signedAt` is kept across resumes and never moved forward.

---

### Task 1: Multipart requests, the XML scans and the R4 probes

**Files:**
- Create in `TidyShot/Upload/`: `MultipartRequests.swift`, `MultipartXML.swift`.
- Create in `docs/superpowers/research/recording-probes/`: `r4-multipart.swift`, `r4-download.swift`.
- Modify `docs/superpowers/research/recording-probes/README.md`: an `## R4 probes (2026-10-27)` section after R3's.
- Tests: create `TidyShotTests/MultipartXMLTests.swift` and `TidyShotTests/MultipartRequestsTests.swift`.

Both new app files are `nonisolated`, import only Foundation (`MultipartRequests` hashes with `S3Signer.sha256Hex(_:)`), and reference nothing but `S3Signer` and each other, so the probes' build line holds.

**Produces:**
- `nonisolated struct MultipartPart: Codable, Equatable, Hashable, Sendable { var number: Int; var etag: String; var size: Int64 }` (Gap 1). `etag` is kept as S3 sends it, quotes included (`"abc"`).
- `nonisolated enum MultipartXML`:
  - `struct ErrorBody: Equatable, Sendable { var code: String; var message: String? }`;
  - `struct PartsPage: Equatable, Sendable { var parts: [MultipartPart]; var isTruncated: Bool; var nextMarker: Int? }`;
  - `static func uploadID(in body: Data) -> String?`: the text of `<UploadId>`;
  - `static func error(in body: Data) -> ErrorBody?`: non-nil only when the body has an `<Error>` element with a non-empty `<Code>`;
  - `static func partsPage(in body: Data) -> PartsPage?`: every `<Part>` with `<PartNumber>`, `<ETag>` and `<Size>`, `<IsTruncated>` (`true` or `false`), `<NextPartNumberMarker>`; nil when the body is not a `ListPartsResult`;
  - `static func unescaped(_ text: String) -> String`: the five XML entities (`&quot;`, `&apos;`, `&lt;`, `&gt;`, `&amp;`, the last one last). S3 writes a listed ETag as `&quot;abc&quot;`; the scans return `"abc"`.
  - The scans find elements as `S3Destination.elementText` does (`<name>…</name>`, no nested markup), each `<Part>…</Part>` block scanned on its own. They never read any element but the ones named here.
- `nonisolated enum MultipartRequests`:
  - `struct Call: Sendable { var method: String; var query: [(name: String, value: String)]; var headers: [(name: String, value: String)]; var body: Data; var payloadHash: String }`. `query` holds decoded values. `headers` are the extra headers, all signed; `host` and `x-amz-content-sha256` are the caller's. `payloadHash` is `S3Signer.sha256Hex(body)`, never `UNSIGNED-PAYLOAD`.
  - `static func create(contentType: String, cacheControl: String?, publicRead: Bool) -> Call`: `POST`, query `[("uploads", "")]`, headers `content-type`, then `cache-control` when given, then `x-amz-acl: public-read` when `publicRead`, empty body.
  - `static func uploadPart(uploadID: String, number: Int, data: Data) -> Call`: `PUT`, query `[("partNumber", "<n>"), ("uploadId", id)]`, no extra headers, body `data`.
  - `static func complete(uploadID: String, parts: [MultipartPart]) -> Call`: `POST`, query `[("uploadId", id)]`, header `content-type: application/xml`, body `completeBody(parts)`.
  - `static func abort(uploadID: String) -> Call`: `DELETE`, query `[("uploadId", id)]`, empty body.
  - `static func listParts(uploadID: String, marker: Int?) -> Call`: `GET`, query `[("uploadId", id)]` plus `("part-number-marker", "<m>")` when `marker` is set, empty body.
  - `static func completeBody(_ parts: [MultipartPart]) -> Data`: `<CompleteMultipartUpload>` then, for each part sorted by `number` ascending, `<Part><PartNumber>n</PartNumber><ETag>etag</ETag></Part>`, then `</CompleteMultipartUpload>`, UTF-8, no XML declaration and no whitespace. The ETag is written as received, quotes included.

**Steps:**
- [ ] Write `MultipartXMLTests` and `MultipartRequestsTests` (design, Tests) and see them fail:
  - `uploadID` from AWS's documented `InitiateMultipartUploadResult` sample; nil from an empty body.
  - `error` gives `ErrorBody(code: "InternalError", message: "We encountered an internal error. Please try again.")` from a 200 Complete body holding `<Error>`, and nil from a plain `CompleteMultipartUploadResult`; `NoSuchUpload`, `InvalidPart` and `EntityTooSmall` bodies give their codes.
  - `partsPage` on a page of three parts with `&quot;` ETags, `<IsTruncated>true</IsTruncated>` and `<NextPartNumberMarker>3</NextPartNumberMarker>` gives three `MultipartPart`s with quoted ETags and sizes, `isTruncated` true and marker 3; a last page gives false and nil; a body with no `ListPartsResult` gives nil.
  - `unescaped("&quot;a&amp;lt;&quot;")` is `"a&lt;"`.
  - `completeBody` over parts 3, 1, 2 writes them 1, 2, 3, ETags with their quotes, exactly the documented element names.
  - `complete`'s headers are exactly `[("content-type", "application/xml")]`; `create`'s are `content-type`, then `cache-control` when given, and `x-amz-acl` only with `publicRead`; `create(… publicRead: false)` with no cache control has `content-type` only.
  - Each call's method and query as listed; `payloadHash` equals `S3Signer.sha256Hex(body)` for each, and is the empty hash for `create`, `abort` and `listParts`.
- [ ] Implement both files.
- [ ] Run the full suite.
- [ ] Write `r4-multipart.swift` (design, Probes, M1). Arguments `<bucket> <region> <endpoint> <prefix>`; credentials from the environment (`AWSCredentials(accessKeyID:secretAccessKey:sessionToken:)`). It builds each request from `MultipartRequests`, with the path-style path `/<bucket>/<prefix>/r4-probe-<random 6>`, the URL from the endpoint with `percentEncodedPath = S3Signer.uriEncode(path, keepSlash: true)` and `percentEncodedQuery = S3Signer.canonicalQuery(call.query)` (nil when empty), the headers `host` and `x-amz-content-sha256: call.payloadHash` added, signed with `S3Signer.sign`, on an ephemeral `URLSession` with no URL cache and a delegate that refuses redirects. It prints each request's method, status and milliseconds, and the steps in the design's order:
  1. Create with `Content-Type: video/mp4`, `Cache-Control: no-cache`, and `x-amz-acl: public-read` only with a fifth argument `acl`.
  2. Parts 1 and 2 of 5 MiB and part 3 of 1 MiB of random bytes, three at a time in a `TaskGroup`, each `ETag` printed.
  3. ListParts, printing number, ETag and size for each part.
  4. Complete with the three ETags; the whole response body printed.
  5. HEAD, printing `Content-Length` and `Cache-Control`.
  6. DELETE.
  7. A second Create, one part, Abort, ListParts on the aborted id, then a Complete on it; each body's `<Code>` printed.
  8. A 2 GiB sparse file in `NSTemporaryDirectory()` (`FileHandle.truncate(atOffset:)`) sent in 16 MiB parts, three in flight, each part read with `FileHandle` `seek(toOffset:)` and `read(upToCount:)` and hashed, as the app does. At half the parts it prints `halfway, pid <pid>: run footprint <pid> now` and waits 20 s. Then Complete and DELETE.
  9. The same in 64 MiB parts.
  Any non-2xx outside the expected 404s prints the excerpt's `<Code>` and `<Message>` only, never `<CanonicalRequest>` or `<StringToSign>`. The temporary file is removed at the end and on every exit.
- [ ] Write `r4-download.swift` (design, Probes, D1). Arguments `<bucket> <region> <endpoint> <key>`. A signed GET built as above, on a session configured as `S3Destination.uncachedSession` is (ephemeral, `urlCache = nil`), through `downloadTask(with:)` with a task delegate that prints each `didWriteData` as a fraction with the time. At 50 % it calls `cancel(byProducingResumeData:)` and prints whether data came back and its size; after 2 s it resumes with `downloadTask(withResumeData:)` and prints the first fraction, the status (206 expected) and the final file size against `Content-Length`; then it waits until 16 minutes after the signing time and resumes again from the same resume data, printing the status (403 expected). The file goes to `NSTemporaryDirectory()` and is removed at the end.
- [ ] The probes README's R4 section: the build line above, the two run lines with what each argument is, the environment variables, the setup step (the lifecycle rule; the README's get, merge and put steps arrive in Task 17), and how to read `footprint`.
- [ ] Check, without running anything: a stub `main.swift` in the scratch directory that names `MultipartRequests`, `MultipartXML`, `MultipartPart` and `S3Signer.sign` type-checks with `xcrun swiftc -typecheck -target arm64-apple-macos26.0 <stub> TidyShot/Upload/S3Signer.swift TidyShot/Upload/AWSCredentials.swift TidyShot/Upload/MultipartRequests.swift TidyShot/Upload/MultipartXML.swift`; both probes compile with the build line and `-o` into the scratch directory. Do not run them.
- [ ] Commit: `feat: multipart requests, XML scans and the R4 probes`.

Then the session asks Tim to run M1 and D1.

### Task 2: URL commands' kinds, actions and errors

**Files:**
- Modify `TidyShot/URLScheme/URLCommand.swift`: `Kind` (:6-36), `parse` (:102-106) and `URLCommandError` (:159-180).
- Tests: change `TidyShotTests/URLCommandTests.swift` (the `capturesNothing` list, :113-117) and `URLCommandGateTests.swift` (`everyCommand`'s count, :18).

**Produces:**
- `URLCommand.Kind.recordScreen = "record-screen"` and `.stopRecording = "stop-recording"`, after `.captureText` and before `.restoreRecentlyClosed`. No alias for either.
- `isCapture`: false for `.stopRecording` too. `takesAction` is unchanged (`isCapture && self != .captureText`), so `record-screen` takes `action` and `stop-recording` does not. `takesArea` gains `.recordScreen`.
- `var actions: [URLCommand.Action]`: every action for a kind that takes one, `[.upload, .save]` for `.recordScreen`, `[]` for the rest.
- `capturesWithoutSelection`: false for `.recordScreen` with or without a rect and for `.stopRecording`.
- `URLCommandError.unknownActionForKind(value: String, command: String)`, message `Unknown action “<value>” for <command>. Use upload or save.`, the value through `URLCommand.displayed`. `parse` checks `Action(rawValue:)` first (`.unknownAction` for a value that is no action), then `kind.actions.contains(action)` (`.unknownActionForKind(value: raw, command: kind.rawValue)`).

**Steps:**
- [ ] Write the design's `URLCommandTests` and `URLCommandGateTests` items and see them fail: both commands parse from the host and the path; `record-screen` takes `action`, the rect and `display`; `stop-recording` ignores every parameter; `action=upload` and `save` parse for `record-screen`; `copy`, `annotate` and `pin` give `.unknownActionForKind` with `Unknown action “copy” for record-screen. Use upload or save.`; `action=bogus` gives `.unknownAction`; `capturesWithoutSelection` is false for both, with and without a rect; `capturesNothing` holds `.stopRecording`; `isCapture`, `takesAction` and `takesArea` over `allCases`; `everyCommand.count == 19`, and the four commands that need the second switch are those of today; `record-screen` with and without a rect and `stop-recording` run with the first switch alone, and off refuses both with `URL commands are off. Turn them on in Settings > General.`.
- [ ] Implement. `URLCommandHandler.run`'s switch must stay exhaustive: until Task 5, `.recordScreen` and `.stopRecording` route to nothing (`break`), with a `// Task 5` comment that Task 5 removes.
- [ ] Run the full suite.
- [ ] Commit: `feat: record-screen and stop-recording URL kinds`.

### Task 3: The recording phase rules and the deferral reason

**Files:**
- Modify:
  - `TidyShot/URLScheme/URLCommandHandler.swift`: `CaptureRefusal` (:4-10) and `dropReason` (:103-110);
  - `TidyShot/App/AppCoordinator.swift`: `captureRefusal(isCapturing:askingPermission:)` and `var captureRefusal` (:476-487), and the Recording state group (:76-105);
  - `TidyShot/App/AppCoordinator+Recording.swift`: `requestAccessFromSettings` (:61-73), `recordShortcutStarts`'s `.cancelCountIn` (:194), `record` (:285-294), and the enums at the file's end (:861-897);
  - `TidyShot/Recording/RecordingController.swift`: `isEnding` beside `isRunning` (:128).
- Tests: change and extend `ShortcutsTests`, `URLCommandHandlerTests` (the refusal tests) and `RecordingControllerTests`.

**Produces:**
- `CaptureRefusal.recordingStarting` and `.recordingRunning`. `URLCommandHandler.dropReason` gives `a recording is starting` and `a recording is running` for them.
- `nonisolated static func captureRefusal(isCapturing: Bool, askingPermission: PermissionPrompt?, recordingPhase: RecordingPhase) -> CaptureRefusal?`, in the design's order: `.countIn` gives `.recordingStarting`; `.recording` gives `.recordingRunning`; then the lock gives `.captureRunning`; then a prompt gives `.permissionPrompt`; otherwise nil. The instance property passes `recordingPhase`. `refusesCapture` and `capturesRefused` do not change.
- `nonisolated static func recordingStartsFromURL(phase: RecordingPhase, askingPermission: PermissionPrompt?, isQuitting: Bool) -> Bool`: true only for `.idle` and `.saving` with no prompt open and not quitting.
- `nonisolated enum RecordingStopCommandAction: Equatable, Sendable { case stop, cancelCountIn, nothing }` beside `RecordingShortcutAction`, and `nonisolated static func recordingStopCommandAction(for phase: RecordingPhase) -> RecordingStopCommandAction`: `.recording` is `.stop`, `.countIn` is `.cancelCountIn`, `.idle` and `.saving` are `.nothing`.
- `nonisolated static func settingsPromptDeferralReason(phase: RecordingPhase, isCapturing: Bool, askingPermission: PermissionPrompt?) -> String?`: `the <name> prompt is open` when a prompt is open; else `a capture is running` when `isCapturing`; else `a recording is being saved` for `.saving`; else nil. `requestAccessFromSettings`'s `.wait` branch logs `Recording: <name> prompt from Settings deferred, <reason>` with it (nil cannot happen there, since `settingsPromptStep` would have said `.ask`; fall back to `a capture is running` only to keep the line).
- `@ObservationIgnored var recordingStartCancelled = false` in the Recording state group, with a doc comment from the design. `recordingCountIn` gains `didSet { if recordingCountIn, !oldValue { recordingStartCancelled = false } }` (Gap 6).
- `RecordingController.isEnding: Bool` (`cause != nil`) (Gap 5).

**Steps:**
- [ ] Write the tests and see them fail (design, Tests, `ShortcutsTests` and `URLCommandHandlerTests`):
  - `recordingStartsFromURL` over the four phases, with and without each prompt, and quitting;
  - `recordingStopCommandAction` for the four phases;
  - `captureRefusal`: `.recordingStarting` in `.countIn` (lock held), `.recordingRunning` in `.recording` (lock held), `.captureRunning` for a lock held in `.idle` and in `.saving`, `.permissionPrompt(.camera)` with only the camera prompt open, nil otherwise;
  - `settingsPromptDeferralReason`: the prompt's text first (also with the lock held and in `.saving`), `a capture is running` with the lock held, `a recording is being saved` for `.saving` alone, nil when nothing defers;
  - `dropReason` for `.recordingStarting` and `.recordingRunning`;
  - `RecordingControllerTests`: `isEnding` is false before `stop()` and while running, and true after `stop()` until the run returns.
- [ ] Implement. Every caller of the three-argument `captureRefusal` compiles: the instance property and the tests.
- [ ] In `record`: the guard after the hand-off reads `isQuitting` and `recordingStartCancelled` together, with no suspension between them and `recorder.run`. When `recordingStartCancelled` is set it logs `Recording: not started, the count-in was cancelled`, ends the notice hold and returns nil (the `defer` closes the extras). `recordShortcutStarts`' `.cancelCountIn` sets `recordingStartCancelled = true` before `selfTimer.cancel()`.
- [ ] Run the full suite.
- [ ] Hand checks (Tim's, for the checklist): turning `Show webcam bubble` on in Settings while a GIF converts logs `Recording: camera prompt from Settings deferred, a recording is being saved`; during a recording it still logs `… a capture is running`; the record shortcut during the settle delay with `Count down before recording` off records nothing and logs `not started, the count-in was cancelled`.
- [ ] Commit: `feat: recording phase rules for URL commands and a true deferral reason`.

### Task 4: The recording selection with a preset rect

**Files:**
- Modify:
  - `TidyShot/Selection/SelectionOutcome.swift`;
  - `TidyShot/Selection/SelectionController.swift`: `select` (:34-39), `present` (:55-106) and a `placePreset` beside `placePreselected` (:130);
  - `TidyShot/Selection/SelectionView.swift`: the stored state, `mouseDown` (:132-139), `mouseUp` (:160-182), `draw` (:212-262).
- Tests: add to `SelectionOutcomeTests`.

**Produces:**
- `static func resolve(mode: SelectionMode, dragRect: CGRect?, hasHighlight: Bool, clickInPreset: CGRect? = nil) -> SelectionOutcome` (Gap 10): a real drag (2 × 2 or more, any mode but `.window`) is `.area(dragRect)` as today; otherwise, in `.recording` mode, a non-nil `clickInPreset` is `.area(clickInPreset)`, before the window rule; then the highlight gives `.window`; else `.cancel`. Every other mode ignores `clickInPreset`.
- `SelectionController.select(mode: SelectionMode, content: SCShareableContent, freeze: CaptureOptions? = nil, preselect: CGRect? = nil) async -> Selection?`. `preselect` is in CoreGraphics global points and used only in `.recording` mode.
- `SelectionView.presetRect: CGRect?` (view coordinates).

**Steps:**
- [ ] Write the design's `SelectionOutcomeTests` and see them fail: in `.recording`, a click in the preset gives `.area(preset)` even with a highlight; a click outside it with a highlight gives `.window`; a drag gives its own rect even when it starts in the preset; with no preset nothing changes; `.area` and `.scrolling` ignore `clickInPreset`.
- [ ] Implement `resolve`.
- [ ] `SelectionController`: `select` passes `preselect` to `present`. In `.recording` mode with a preset, after the windows are made, `placePreset(_:)` converts the rect to AppKit points (`Geometry.appKitRect(fromCG:primaryHeight:)`), finds the window whose frame holds its centre, and sets that view's `presetRect` in view coordinates. Nothing is placed when no window holds the centre. All-in-One's path does not change.
- [ ] `SelectionView`:
  - `draw`: with a `presetRect` and no drag in progress, it is punched out of the dimming with the selection stroke and its size label (`drawSizeLabel`), before the highlight. The highlight is not drawn while the cursor is inside `presetRect`. The crosshair and the loupe are drawn as today.
  - `mouseDown` records whether the press is inside `presetRect`. `mouseUp` passes `clickInPreset: presetRect` when the press and the release were both inside it and there was no real drag, else nil.
  - Keys do not change: Escape cancels, Return and keypad Enter do nothing in `.recording` mode (they reach `super.keyDown`).
- [ ] Run the full suite.
- [ ] Hand checks (Tim's, for the checklist, once Task 5 wires it): the rect shows with its stroke and size on the right display; Return and Enter do nothing; a click inside records it after the count-in; a drag replaces it; a click outside on a window records the window; Escape cancels; the shortcut's Record Screen, with no preset, behaves as before.
- [ ] Commit: `feat: preset rect in the recording selection`.

### Task 5: The URL commands reach the recorder

**Files:**
- Modify:
  - `TidyShot/URLScheme/URLCommandHandler.swift`: `URLCommandTarget` (:14-30) and `run` (:145-187);
  - `TidyShot/App/AppCoordinator+Recording.swift`: `recordScreen` (:100-135) split, and the two new entry points.
- Tests: extend `URLCommandHandlerTests` and its `URLTargetRecorder` (:7-45).

**Consumes:** Task 2's kinds; Task 3's rules, `recordingStartCancelled` and `isEnding`; Task 4's `select(…preselect:)`.

**Produces:**
- `URLCommandTarget` gains `func startRecording(intent: CaptureIntent, preselect: ScreenRect?)` and `func stopRecordingCommand(sender: String?)`, neither `async`, neither returning a value.
- `URLCommandHandler.run`: after the rect is resolved, a `.recordScreen` placement whose rect fails `RecordingConfiguration.isLargeEnough` is refused with `The area must be at least 32 by 32 points to record.` and reaches nothing. Then `.recordScreen` calls `target.startRecording(intent: intent, preselect: placement)` and `.stopRecording` calls `target.stopRecordingCommand(sender: sender)` (the cleaned sender). `.stopRecording` is not a capture, so it is never dropped and never sets `captureRan` in `ready()`. The Task 2 `break` goes.
- `AppCoordinator` (in `+Recording`):
  - `func recordScreen() async`: `guard recordShortcutStarts() else { return }`, then `await startRecordScreen(intent: .standard, preselect: nil)`.
  - `private func startRecordScreen(intent: CaptureIntent, preselect: CGRect?) async`: today's body after the shortcut check, with `selector.select(mode: .recording, content: content, preselect: preselect)` and `endRecording(ended, intent: intent)`.
  - `func startRecording(intent: CaptureIntent, preselect: ScreenRect?)`: unless `recordingStartsFromURL(phase:askingPermission:isQuitting:)`, returns, logging `Recording: URL start ignored, the app is quitting` when quitting (the other refusals were logged by the handler's drop). Otherwise `Task { await startRecordScreen(intent: intent, preselect: preselect?.rect) }` and returns at once. The rect is never written to `lastAreaRect`.
  - `func stopRecordingCommand(sender: String?)`, with `name = sender ?? "an unknown app"`:
    - `.stop`: when `recorder.isEnding`, logs `Recording: stop-recording from <name> did nothing, no recording is running`; otherwise `recorder.stop()` and `Recording: stop-recording from <name> stopped the recording`.
    - `.cancelCountIn`: `recordingStartCancelled = true`, `selfTimer.cancel()`, `Recording: stop-recording from <name> cancelled the count-in`.
    - `.nothing`: `Recording: stop-recording from <name> did nothing, no recording is running`. No notice.
- `URLTargetRecorder.Call` gains `.startRecording(CaptureIntent, ScreenRect?)` and `.stopRecording(String?)`. Its `startRecording` appends and returns at once, as the real one does.

**Steps:**
- [ ] Write the design's `URLCommandHandlerTests` items and see them fail: `record-screen` reaches `startRecording(intent:preselect: nil)` with the intent's action (Tim's `.uploadOnly` for `action=upload`, `.save` for `save`); with a rect, the resolved `ScreenRect`; a rect under 32 × 32 pt after clipping posts `The area must be at least 32 by 32 points to record.` with `From Raycast` and reaches nothing; `record-screen` is dropped for `.captureRunning`, `.recordingStarting`, `.recordingRunning` and `.permissionPrompt(.microphone)`, and after a queued capture command ran first, logging the matching reason; `stop-recording` reaches `stopRecordingCommand(sender: "Raycast")` under every refusal, and with an unknown sender `nil`; in a launch burst, `record-screen` then `stop-recording` reach the target in that order, and the stop is not held behind the start; `capture-area` queued after `record-screen` in a burst is dropped as today.
- [ ] Implement the protocol, the handler and the coordinator's three functions.
- [ ] Run the full suite.
- [ ] Hand checks (Tim's, for the checklist; U1 and design, Hand checks, URL commands): `open 'tidyshot://record-screen'` from Terminal, Raycast and Keyboard Maestro shows the selection, the count-in and the bar, and `action=save` and `action=upload` end as the setting says; a rect with the second switch off shows in the selection (Task 4's checks); `stop-recording` during the selection, the count-in (with `Count down before recording` on, and off within the settle delay), the recording and the save; `record-screen` during a recording and during a screenshot's selection is dropped with its log reason; the first microphone or camera prompt (after Tim's `tccutil` reset) shows on a URL start before the selection; a cold launch from `tidyshot://record-screen`, and from a burst of `record-screen` then `stop-recording`, whose stop logs `did nothing`.
- [ ] Commit: `feat: record-screen and stop-recording URL commands`.

### Task 6: MultipartPlan and the stored multipart state

**Files:**
- Create in `TidyShot/Upload/`: `MultipartPlan.swift` (pure), `MultipartUploadState.swift`.
- Tests: create `TidyShotTests/MultipartPlanTests.swift` and `TidyShotTests/UploadStartTests.swift`.

**Consumes:** Task 1's `MultipartPart`; `ObjectLocation`, `UploadPayload`.

**Produces** (all `nonisolated` and `Sendable`):
- `struct MultipartPlan: Equatable`:
  - `init(threshold: Int64, partSize: Int64, inFlight: Int)` and `static let standard = MultipartPlan(threshold: 104_857_600, partSize: 16_777_216, inFlight: 3)`;
  - `static let maxPartSize: Int64 = 67_108_864`, `maxParts = 10_000`, `maxBytes: Int64 = 671_088_640_000`, `restartLimit = 2`, `stateLifetime: TimeInterval = 604_800`;
  - `static func fits(byteCount: Int64) -> Bool`: `byteCount <= maxBytes`;
  - `func uses(payload: UploadPayload, byteCount: Int64?) -> Bool`: true for `.file` with a known size at or above `threshold`; false for `.data` and for an unknown size;
  - `func partSize(for byteCount: Int64) -> Int64?`: the base part size; raised, when the base would need more than `maxParts` parts, to `ceil(byteCount / maxParts)` rounded up to a whole MiB; nil when that exceeds `maxPartSize`;
  - `static func partCount(byteCount: Int64, partSize: Int64) -> Int` and `static func range(ofPart number: Int, partSize: Int64, byteCount: Int64) -> Range<Int64>` (1-based; the last part shorter);
  - `static func fraction(doneBytes: Int64, inFlightBytes: Int64, total: Int64) -> Double`: in 0...1, 0 for a total of 0 or less;
  - `static func resumeDecision(stored: MultipartUploadState, location: ObjectLocation, fixedKey: String?, source: MultipartSourceAttributes?) -> MultipartResumeDecision`: `.startOver(reason: .location, …)` when the locations differ; `.key` when a fixed key differs from the stored key; `.source` when `source` is nil or its size or modification date differs; otherwise `.resume(stored)`. The abort ref is the stored id, key and location;
  - `static func startStep(decision: MultipartResumeDecision?) -> UploadStartStep`.
- `struct MultipartSourceAttributes: Equatable { var byteCount: Int64; var modified: Date }`.
- `enum MultipartStartOverReason: Equatable { case location, key, source }` with `var logText: String`: `destination changed`, `key changed`, `source changed`.
- `enum MultipartResumeDecision: Equatable { case resume(MultipartUploadState); case startOver(reason: MultipartStartOverReason, abort: MultipartRef) }`.
- `struct UploadStartStep: Equatable { var runsClop: Bool; var drawsCounter: Bool; var resume: MultipartUploadState?; var abortFirst: MultipartRef? }`. Nil decision: Clop as today, a counter as today, nothing else. `.resume`: no Clop, no counter, `resume` set (the job sends `resume.sourcePath`). `.startOver`: Clop and counter as today, `abortFirst` set.
- In `MultipartUploadState.swift`:
  - `struct MultipartRef: Codable, Hashable { var uploadID: String; var key: String; var location: ObjectLocation }`;
  - `struct MultipartUploadState: Codable, Equatable { var uploadID: String; var key: String; var location: ObjectLocation; var partSize: Int64; var byteCount: Int64; var sourceModified: Date; var sourcePath: String; var startedAt: Date; var ref: MultipartRef }`, with its own `init(from:)` and `encode(to:)` that write `sourceModified` as a `Double` (`timeIntervalSinceReferenceDate`) and read it back the same way; every other field as synthesized;
  - `struct MultipartSidecar: Codable, Equatable { var uploadID: String; var completeSent: Bool; var parts: [MultipartPart] }`;
  - `struct MultipartSource: Equatable { var location: ObjectLocation; var path: String; var byteCount: Int64; var modified: Date }` (Gap 3).

**Steps:**
- [ ] Write the design's `MultipartPlanTests` and `UploadStartTests` and see them fail:
  - `uses`: false at 100 MiB − 1 and for `.data` of any size and for a nil size; true at 100 MiB;
  - `partSize`: 16 MiB at 1 GiB and at 156.25 GiB (167,772,160,000 bytes); 17 MiB at 160 GiB; 64 MiB at 625 GiB; nil at 625 GiB + 1;
  - `partCount` and `range`: 100 MiB in 16 MiB parts is 7 parts, part 7 is `100663296..<104857600`; one byte over a whole part adds a 1-byte part;
  - `fits` at `maxBytes` and one over;
  - `fraction` never exceeds 1 and is 0 for a total of 0;
  - `resumeDecision` resumes when location, key, size and date match; starts over with `.location`, `.key` (fixed key) and `.source` (size, date, missing) on each mismatch; a template job resumes under any stored key;
  - `MultipartUploadState` round-trips through a `JSONEncoder` and `JSONDecoder` set to `.iso8601`, which keeps whole seconds only, and still holds a `sourceModified` with sub-millisecond digits exactly; its JSON holds `sourceModified` as a number (Task 7 repeats the check through `HistoryStore` itself);
  - `UploadStartTests` (design, Tests): a matching source resumes from `sourcePath`, runs no Clop and draws no counter; a changed source starts over with Clop and the counter as today and carries `abortFirst`; a resume whose first attempt ran with Clop off sends the record's file and runs no Clop, with Clop running now.
- [ ] Implement both files.
- [ ] Run the full suite.
- [ ] Commit: `feat: multipart plan and the stored upload state`.

### Task 7: The record's multipart state and Delete's lists

**Files:**
- Modify:
  - `TidyShot/History/CaptureRecord.swift`: the field (:105-108), `CodingKeys` (:138-145), `init(from:)` (:154-175) and the memberwise init the tests use;
  - `TidyShot/History/CaptureDeletion.swift`: `objects(for:)` (:53-67), `confirmationText` (:100-111), and `aborts(for:)`.
- Tests: add to `CaptureRecordTests`, `CaptureDeletionTests`, `HistoryStoreTests` and `EditorUploadPlanTests`.

**Consumes:** Task 6's `MultipartUploadState` and `MultipartRef`.

**Produces:**
- `CaptureRecord.multipart: MultipartUploadState?`, nil by default, `decodeIfPresent`, encoded only when set.
- `CaptureDeletion.aborts(for record: CaptureRecord) -> [MultipartRef]`: the stored state's ref, or none.
- `CaptureDeletion.objects(for:)` also lists `ObjectRef(key: multipart.key, location: multipart.location)`, deduplicated with the rest. `sharedKeys` and `confirmationText` read it through `objects(for:)`, so a failed upload's Delete says it removes the object from storage.

**Steps:**
- [ ] Write the design's tests and see them fail: `multipart` round-trips and old history decodes it nil; a record with a sub-millisecond `sourceModified` saved and loaded through `HistoryStore`, then `MultipartPlan.resumeDecision` against the same attributes, resumes; `HistoryStore.load` turns `.uploading` into `.failed("Upload was interrupted.")` and keeps `multipart`; `aborts(for:)` lists the ref and is empty without state; `objects(for:)` lists `multipart.key` for a `.failed` record, once when it equals the uploaded key, and `confirmationText` reads `Removes it from object storage and from history.` for a failed upload-only record with state; `EditorUploadPlan.applyingFailure` on a record with `priorUpload` and `multipart` returns it to `.uploaded` at the old link with `uploadIsStale` and `multipart` kept.
- [ ] Implement. `HistoryStore.load` needs no change if the field decodes; the test pins it.
- [ ] Run the full suite.
- [ ] Commit: `feat: multipart state on the record and in Delete's lists`.

### Task 8: The sidecar store, the kept Clop copy and the launch sweep

**Files:**
- Create `TidyShot/Upload/MultipartStore.swift`.
- Tests: create `TidyShotTests/MultipartStoreTests.swift`.

**Consumes:** Task 6's `MultipartSidecar`, `MultipartUploadState` and `MultipartPlan.stateLifetime`.

**Produces:** `nonisolated struct MultipartStore: Sendable`, next to `PendingFileStore`:
- `static let directoryName = "multipart"`; `let directory: URL`; `init(directory:)` and `init(nextTo historyFileURL: URL)`.
- `func sidecarURL(for id: UUID) -> URL` (`<id>.json`) and `func keptCopyURL(for id: UUID, ext: String) -> URL` (`<id>.<ext>`).
- `func readSidecar(id: UUID, uploadID: String) -> MultipartSidecar?`: nil when missing, unreadable, or for another upload id.
- `func writeSidecar(_ sidecar: MultipartSidecar, id: UUID) throws`: creates the folder, writes atomically.
- `func keepClopCopy(_ source: URL, id: UUID, ext: String) throws -> URL`: moves `source` to `keptCopyURL`, replacing a file there.
- `func remove(id: UUID)`: removes the sidecar and every `<id>.*` file; a missing file is not an error, another failure is logged.
- `static func sweepRemovals(fileIDs: Set<UUID>, states: [UUID: Date], now: Date) -> Set<UUID>` (pure): an id with no state (no record, or a record with no `multipart`), and an id whose `startedAt` is more than `stateLifetime` before `now`.
- `func sweep(states: [UUID: Date], now: Date)`: lists the folder's files, takes the id from each name's stem, and removes the files of `sweepRemovals`. It touches no record and no network.

**Steps:**
- [ ] Write the design's `MultipartStoreTests` and see them fail: write then read; a missing, a corrupt, and another id's sidecar read nil; a rewrite replaces atomically; `remove` clears the sidecar and the kept copy; `keepClopCopy` moves a file into `multipart/<id>.mp4` and leaves the source gone; `sweepRemovals` removes an id with no state and one older than 7 days and keeps one of 6 days; `sweep` on a folder with those three ids leaves only the third.
- [ ] Implement.
- [ ] Run the full suite.
- [ ] Commit: `feat: multipart sidecar store and launch sweep`.

### Task 9: The six S3 calls

**Files:**
- Create `TidyShot/Upload/S3Destination+Multipart.swift`; `TidyShotTests/StubURLProtocol.swift` (moved).
- Modify:
  - `TidyShot/Upload/Destination.swift`: the protocol (:5-27), `UploadError` (:109-152);
  - `TidyShot/Upload/S3Destination.swift`: `signedRequest` (:150-181), `httpResponse`, `failure`, `excerpt` (:183-214);
  - `TidyShot/Upload/S3DestinationConfig.swift`: `objectURL(for:)` (:138-151);
  - `TidyShot/Upload/UploadProgressDelegate.swift`;
  - `TidyShotTests/S3DestinationTests.swift` (the stub and `bodyBytes` move out, :1-80 and :318-330);
  - `TidyShotTests/UploadQueueTests.swift`: `FakeDestination` gains the six calls (Task 10 scripts them).
- Tests: create `TidyShotTests/UploadErrorTests.swift`; add to `S3SignerTests`, `S3DestinationConfigTests` and `S3DestinationTests` (`StubMultipartBucket` there).

**Consumes:** Task 1's `MultipartRequests`, `MultipartXML` and `MultipartPart`.

**Produces:**
- `UploadError` gains `.noSuchUpload` (`The upload was no longer known to the server.`), `.partsRejected(body: String)` (`The server rejected the upload's part list: <body>`) and `.completeError(code: String, body: String)` (`The server could not complete the upload: <body>`). `isRetryable`: `.noSuchUpload` and `.partsRejected` false; `.completeError` true for `InternalError`, `SlowDown`, `ServiceUnavailable` and false otherwise.
- `S3DestinationConfig.objectURL(for key: String, query: [(name: String, value: String)]) throws -> URL`: `percentEncodedQuery = S3Signer.canonicalQuery(query)`, nil when empty. `objectURL(for:)` calls it with `[]`.
- `S3Destination.signedRequest(method:key:query:payloadHash:extraHeaders:)`: both the URL and `S3Signer.Request.query` come from the one `query` list. The two existing overloads pass `[]`. `httpResponse`, `failure` and `excerpt` become internal (Gap 13).
- `UploadProgressDelegate.init(onProgress: @escaping @Sendable (Double) -> Void = { _ in }, onBytesSent: @escaping @Sendable (Int64) -> Void = { _ in })`; `didSendBodyData` also calls `onBytesSent(bytesSent)`.
- `nonisolated enum MultipartAbortResult: Equatable, Sendable { case aborted, notFound }` (Gap 14).
- `Destination` gains, implemented in `S3Destination+Multipart.swift` (each request from `MultipartRequests`, signed with the call's `payloadHash`, sent with `UploadProgressDelegate()` so redirects are refused):
  - `createMultipartUpload(key: String, contentType: String, cacheControl: String?) async throws -> String`: non-2xx is `failure`; a 2xx without `<UploadId>` is `.httpStatus(status, body: "no UploadId")`.
  - `uploadPart(key: String, uploadID: String, number: Int, data: Data, progress: @escaping @Sendable (Int64) -> Void) async throws -> String`: `session.upload(for:from:delegate:)`; the `ETag` header is the result (`.httpStatus(status, body: "no ETag")` when missing); 404 with code `NoSuchUpload` throws `.noSuchUpload`.
  - `completeMultipartUpload(key: String, uploadID: String, parts: [MultipartPart]) async throws`: 200 with `<Error>` throws `.completeError(code:body: excerpt)`; 404 `NoSuchUpload` throws `.noSuchUpload`; 400 `InvalidPart` or `InvalidPartOrder` throws `.partsRejected(body: excerpt)`; any other non-2xx is `failure` (`EntityTooSmall` and `EntityTooLarge` among them).
  - `abortMultipartUpload(key: String, uploadID: String) async throws -> MultipartAbortResult`: 204 (any 2xx) `.aborted`, 404 `.notFound`, else `failure`.
  - `listParts(key: String, uploadID: String) async throws -> [MultipartPart]`: paged with `nextMarker` until `isTruncated` is false; 404 `NoSuchUpload` throws `.noSuchUpload`; a page that does not parse is `.httpStatus(status, body: "unreadable part list")`.
  - `objectSize(key: String) async throws -> Int64?`: HEAD; 200 gives `Content-Length`; 403 and 404 give nil; else `failure`.
- `TidyShotTests/StubURLProtocol.swift`: `StubURLProtocol`, `StubSession` and `StubURLProtocol.bodyBytes(of:)`, moved unchanged; callers updated.
- `StubMultipartBucket` (in `S3DestinationTests.swift`): an in-memory multipart S3 behind `StubSession.make(headerHandler:)` that reads the method and the query, with `minimumPartSize: Int` (0 by default; 5 MiB in the `EntityTooSmall` test), `listPageSize`, scripted `completeAnswer` (for the 200-with-`<Error>` case) and a `missingUploads` set that answers `NoSuchUpload`.

**Steps:**
- [ ] Move the stub. Run the full suite: unchanged.
- [ ] Write the tests and see them fail:
  - `UploadErrorTests` (design, Tests): the three new descriptions pinned; `noSuchUpload` and `partsRejected` not retryable; `completeError` retryable for the three codes and not for `EntityTooLarge`; the existing cases keep their rule, including `UploadError.isRetryable(_:)` on `CancellationError` and `URLError(.cancelled)`.
  - `S3SignerTests`: canonical requests, path-style with the dotted bucket `snap.tky.io`, for `POST ?uploads` (canonical query `uploads=`), `PUT ?partNumber=7&uploadId=a/b~c` (`partNumber=7&uploadId=a%2Fb~c`, sorted) and `POST ?uploadId=…`, written out by hand in the test.
  - `S3DestinationConfigTests`: `objectURL(for:query:)`'s `percentEncodedQuery` equals `S3Signer.canonicalQuery` for each of the three, and `objectURL(for:)` has no query.
  - `S3DestinationTests` with `StubMultipartBucket` (design, Tests): Create returns an id and the bucket stored the signed `content-type`, `cache-control` and ACL headers; a part is stored with an ETag and replaces an earlier part of the same number; Complete fails 400 with no `Content-Type` and with `application/x-www-form-urlencoded`, checks order and ETags (`InvalidPart`), `EntityTooSmall` with the 5 MiB minimum on, and a scripted 200 with `<Error>` throws `completeError` with its code; Abort gives `.aborted` then `.notFound`; ListParts pages at a page size of 2 over 5 parts; `NoSuchUpload` on a part, ListParts, Complete and Abort (`.notFound` for Abort); `objectSize` on a present and a missing key; a 301 with `Location` is refused; every request's `x-amz-content-sha256` equals the SHA-256 of `StubURLProtocol.bodyBytes(of:)`; the request URL's query and the signed canonical query agree.
- [ ] Implement. `FakeDestination` gets the six calls with no scripting yet (Create returns `"upload-1"`, a part returns `"\"etag-<n>\""`, the rest succeed), so the suite compiles.
- [ ] Run the full suite.
- [ ] Commit: `feat: S3 multipart calls`.

### Task 10: The queue sends a multipart upload

**Files:**
- Modify:
  - `TidyShot/Upload/Destination.swift`: `UploadJob` (:37-95), `UploadEvent` (:97-107);
  - `TidyShot/Upload/UploadQueue.swift`: `init` (:77-91), `process` (:137-185), and new private members; `ProgressGate` (:247-253) becomes internal (Gap 7);
  - `TidyShot/App/AppCoordinator+Upload.swift`: `handle`'s `.started` pattern (:491-498) compiles with the new case (its behaviour changes in Task 12);
  - `TidyShotTests/UploadQueueTests.swift`: `FakeDestination`'s scripting and every `.started(id:attempt:)` expectation.
- Tests: add to `UploadQueueTests`.

**Consumes:** Task 6's plan and types; Task 8's `MultipartStore`; Task 9's calls and errors.

**Produces:**
- `UploadJob` gains `var multipartSource: MultipartSource? = nil`, `var resume: MultipartUploadState? = nil` and `var abortFirst: MultipartRef? = nil`. Existing initializers do not change.
- `UploadEvent.started(id: UUID, attempt: Int, fraction: Double)` (single PUT and a fresh multipart attempt: 0) and `UploadEvent.multipartStarted(id: UUID, state: MultipartUploadState)`.
- `UploadQueue.init(destination:keyNamer:policy:filePolicy:scope:sleep:plan: MultipartPlan = .standard, store: MultipartStore? = nil, now: @escaping @Sendable () -> Date = { Date() }, log: @escaping @Sendable (String) -> Void = { NSLog("%@", $0) }, events:)`. A multipart job needs a store; with none (a test that never goes multipart) the job uses the single PUT.
- `nonisolated @concurrent static func readPart(of url: URL, range: Range<Int64>) async throws -> Data` in `UploadQueue.swift`: `FileHandle` `seek(toOffset:)` and `read(upToCount:)`; fewer bytes than the range throws `UploadError.fileUnreadable(url.lastPathComponent)`.

**The multipart job** (design, Concurrency, Reading a part, Progress, Failure and retry, Key; this task builds the fresh upload, Task 11 the resume and the restarts):
- `process` sends a job multipart when `store != nil`, `job.multipartSource` is set and `plan.uses(payload: job.payload, byteCount: source.byteCount)`. Single-PUT jobs keep today's loop and send `.started(id:attempt:fraction: 0)`.
- One pass, holding the payload's scope for the whole attempt: `.started(attempt: 1, fraction: 0)`; the key (a template key reserved with HEAD, each HEAD retried under `filePolicy`; a fixed key as is), stored in `reservedKeys`; `partSize = plan.partSize(for: byteCount)` (nil cannot happen: the coordinator refused over 625 GiB; treat it as `.fileUnreadable`); Create, retried under `filePolicy`, logged on failure `Upload: <name> create failed: <error>`; the state from the source, the key, the id, the part size and `now()`; the sidecar written with no parts; `.multipartStarted(id:state:)` delivered before any part is sent; `Upload: <name> multipart, <n> parts of <m> MiB, upload id <id>` logged.
- The parts: a `withThrowingTaskGroup` that keeps at most `plan.inFlight` parts running and adds them in part order, one as each finishes. Each child reads its range with `readPart`, hashes and sends it through `uploadPart`, retrying under `filePolicy` with `UploadError.isRetryable`, sleeping with the injected `sleep`, and logging each retry `Upload: <name> part <k> failed, retry <try>: <error>`. The actor collects each finished part, rewrites the sidecar atomically, and adds the next part. A part out of tries, or with an error that is not retryable and not handled apart (Task 11), cancels the group, and the job ends `.failed(id:message: "Part <k> of <n>: <error>")`; the sidecar keeps the parts done.
- Progress: one `ProgressGate` per job and a locked byte count: the bytes of completed parts plus each in-flight part's bytes sent so far (reset when a part retries), through `MultipartPlan.fraction`, as `.progress` events.
- Complete: the sidecar's `completeSent` is set and written before the first Complete for the id; Complete is retried under `filePolicy` (a retryable `completeError` included). Then `Upload: <name> multipart completed`, `.uploaded(id:url:key:)` with `publicURL(for:)`.
- Cancel: `cancel(recordID:)` already cancels the job's task; the group's children are cancelled with it and awaited before the job returns, so `.cancelled(id:reservedKey:)` is delivered once, after every part has stopped. The record's state stays.
- `<name>` is `fileURL.lastPathComponent` of the payload, or the id.

**Steps:**
- [ ] Extend `FakeDestination`: Create returns `upload-1`, `upload-2`, … and records its key, content type and cache control; `uploadPart` records `(uploadID, number, size)`, counts the parts in flight and the highest overlap, can wait `partDelay` so parts overlap, and fails from a script keyed by part number (`[Int: [UploadError]]`, one error per attempt); Complete, Abort, ListParts and `objectSize` answer from scripts and record their calls.
- [ ] Update every `.started(id:attempt:)` in the tests to `.started(id:attempt:fraction: 0)`.
- [ ] Write the design's `UploadQueueTests` items for a fresh upload and see them fail, with `MultipartPlan(threshold: 1 MiB, partSize: 256 KiB, inFlight: 3)`, `.immediate`-style file policy and a store in a temporary folder:
  - a sparse `.file` job at the threshold goes multipart and one byte under it uses the single PUT;
  - parts are sent at most 3 at a time (the fake's overlap is 3 for a 2 MiB file) and started in part order;
  - a part that fails twice with 503 retries alone while the others finish, and the job completes; a part out of tries fails the job with `Part 3 of 8: Server returned HTTP 503.` after one pass, with no second `.started`, and the sidecar lists the parts done;
  - Create, ListParts (Task 11 uses it) and Complete each retry; a Create out of tries fails the job with its error and logs `create failed`;
  - a cancel during the parts waits for every part and delivers one `.cancelled` with the reserved key;
  - `multipartStarted` comes before the first `uploadPart`, the sidecar is rewritten after each part with the upload id, and `completeSent` is true before the first Complete;
  - a template key is HEADed once per upload id;
  - the fractions rise, count in-flight bytes, and end at 1;
  - a retryable `completeError` (`SlowDown`) retries and then completes; one with `EntityTooLarge` fails the job.
- [ ] Implement.
- [ ] Run the full suite.
- [ ] Commit: `feat: multipart upload in the queue`.

### Task 11: The queue resumes and restarts

**Files:**
- Modify `TidyShot/Upload/UploadQueue.swift`.
- Tests: add to `UploadQueueTests`.

**Consumes:** Task 10's multipart job.

**The resume and the restarts** (design, Failure and retry, Resume, Key):
- **`abortFirst`.** A job that carries it aborts it before anything else, best effort (any failure is logged `Upload: <name> multipart abort failed: <error>`, success `Upload: <name> multipart aborted`), then starts fresh.
- **A job with `resume`** uses the stored key, id and part size:
  - A template key is HEADed first with `objectSize` (retried): nil goes on; the stored `byteCount` counts as uploaded (`.uploaded` with the stored key, the sidecar and state left for the coordinator to clear); another size aborts the stored id (best effort), logs `Upload: <name> key taken, starting again`, and restarts with a new key drawn from the job's template context (Gap 9). A fixed key gets no HEAD.
  - The sidecar is read with the stored id. Missing, unreadable or another id: `Upload: <name> part list missing, listing parts`, then `listParts` (retried), trusting a part whose size is the part size (or, for the last part, the remaining size) and rewriting the sidecar. ListParts failing with a 403 or any error left after its retries restarts, logged `Upload: <name> part list unavailable, starting again`.
  - `.started(attempt: 1, fraction: <done bytes / byteCount>)`, `Upload: <name> resumes at <done> of <n> parts`, then only the missing parts, then Complete.
- **Restarts.** A restart aborts the stored id when it may still exist (best effort), creates a new upload under the same key (a template key is HEADed again first), and begins a new attempt: `.started` with `attempt` one higher and fraction 0, then a new `.multipartStarted`. `attempt` counts restarts only. A third cause fails the job with that cause's error.
- **`noSuchUpload`** from a part or from ListParts, or from Complete while the sidecar's `completeSent` is false: `Upload: <name> upload id gone, starting again`, and a restart under the same key.
- **`noSuchUpload` from Complete while `completeSent` is true:** `objectSize(key:)`. The stored `byteCount` counts as uploaded; anything else restarts.
- **`partsRejected` from Complete:** the first time in the job, `Upload: <name> part list rejected, listing parts`, `listParts`, every part that is missing or whose ETag or size differs from the sidecar is sent again, the sidecar is rewritten, and Complete is sent again. The second time in the job restarts.

**Steps:**
- [ ] Write the design's remaining `UploadQueueTests` items and see them fail:
  - a resume sends only the parts the sidecar lacks, starts at the done fraction and completes;
  - a resume whose sidecar is missing, or holds another upload id, lists parts, trusts those of the stored size and resends one listed at another size;
  - a resume of a template job HEADs the stored key: absent goes on; present at `byteCount` counts as uploaded with no part sent; present at another size aborts, draws a new key and restarts with `attempt` 2;
  - ListParts answering 403 restarts and logs `part list unavailable`;
  - `noSuchUpload` on a part restarts under the same key with `attempt` 2; `noSuchUpload` on the first part of every Create fails the job after 2 restarts with `The upload was no longer known to the server.`;
  - `noSuchUpload` on a Complete with `completeSent` true asks `objectSize` and counts a matching size as uploaded;
  - `partsRejected` lists parts, resends the ones that differ and completes; a second one in the job restarts;
  - a job with `abortFirst` aborts it before its Create;
  - each log line above appears once, in order.
- [ ] Implement.
- [ ] Run the full suite.
- [ ] Commit: `feat: resume and restart multipart uploads`.

### Task 12: The coordinator starts, resumes and finishes multipart uploads

**Files:**
- Modify:
  - `TidyShot/App/AppCoordinator.swift`: the Collaborators (`multipartFiles` beside `pendingFiles`, :18), `init` (:236-247) and `start` (:249-277);
  - `TidyShot/App/AppCoordinator+Upload.swift`: `makeLane` (:102-109), `startUpload` (:119-224), `byteCount(of:)` (:228-237), `fitsSingleUpload` (:242-245), `refuseOversizedUpload` (:252-295), `handle` (:473-597);
  - `TidyShot/Recording/RecordingLimits.swift` (:17-18, :44-46) and `TidyShot/Recording/RecordingSavePlan.swift` (:60-61);
  - code comments that say "in one piece" or "single-PUT limit".
- Tests: change `RecordingLimitsTests` (:47-48) and `RecordingSavePlanTests` (:284-286); add to `UploadRefusalTests`.

**Consumes:** Tasks 6 to 11.

**Produces and changes** (design, When, Parts, What is persisted, Progress, Resume, Trim):
- `let multipartFiles: MultipartStore` in the Collaborators, `MultipartStore(nextTo: url)` in `init` (Gap 8). `makeLane` passes `plan: .standard` and `store: multipartFiles`.
- `start()` runs the sweep right after `history.load()`, detached: the states are `[record.id: record.multipart.startedAt]` for records with state. No network.
- `RecordingLimits.singleUploadBytes` and `fitsSingleUpload` go; `fitsSingleUpload` in `+Upload` becomes `MultipartPlan.fits(byteCount:)` for a `.file` payload with a known size. `RecordingSavePlan.oversizedNotice` is `Not uploaded` / `The recording is larger than 625 GB, too large to upload.`; `refuseOversizedUpload` logs `Recording: <name> is too large to upload (over 625 GB)`; R1's handling (`.none`, the move rules) is unchanged.
- `startUpload`:
  - When the record has `multipart`, before Clop runs and before any counter is drawn, a detached task reads the stored `sourcePath`'s size and modification date, holding the save folder's scope when the path is inside it, and `MultipartPlan.resumeDecision(stored:location: lane.location, fixedKey:, source:)` decides; `startStep(decision:)` gives the step.
  - `.resume`: no Clop, no counter; the payload is `.file(URL(filePath: state.sourcePath), scope: UploadPayload.scope(for:isTemporary: false, saveFolder: saveLocation.currentURL))`; the job carries `resume` and its key policy (the fixed key, or the template with `TemplateContext(date: record.timestamp)`).
  - `.startOver`: `startUpload` logs `Upload: <name> <reason.logText>, starting again` (`source changed`, `destination changed` or `key changed`), then runs as today (Clop when it applies, the counter when the template has one), and the job carries `abortFirst`, which the queue aborts before its Create.
  - For every fresh `.file` job, the detached read that gives `sentBytes` also reads the sent file's modification date, and the job carries `MultipartSource(location: lane.location, path:, byteCount:, modified:)`.
  - **The Clop copy** (design, Clop's copy): when `MultipartPlan.standard.uses(payload: sent, byteCount:)` holds and the sent file is Clop's result, it is moved with `multipartFiles.keepClopCopy(_:id:ext:)` before the enqueue, the job sends it from there and `sourcePath` names it; it is not put in `clopResults`. A move that fails logs `Upload: Clop's copy could not be kept for resume: <error>`, keeps the result in `clopResults` and sends from `tmp/Clop`.
- `handle`:
  - `.started(id, attempt, fraction)`: the retry log when `attempt > 1`, and the bar set to `fraction` on every `.started` (`history.setProgress`), refreshing the overlay when it changed.
  - `.multipartStarted(id, state)`: `history.update(id:) { $0.multipart = state }`, replacing an older state.
  - `.uploaded`: also `record.multipart = nil` and `multipartFiles.remove(id:)`.
  - `.failed` and `.cancelled`: the state, the sidecar and the kept copy stay.
- No other caller changes: Retry, Retry Failed Uploads, `Upload Trimmed`, Save and Upload, the editor's upload and the save's first upload all go through `startUpload`.

**Steps:**
- [ ] Write the tests and see them fail: `RecordingSavePlanTests` pins the new notice; `UploadRefusalTests` (design, Tests): over 625 GiB is refused with `.none` and R1's move rules unchanged, 625 GiB itself fits; `RecordingLimitsTests` loses `singleUploadLimitIs5GiB`.
- [ ] Implement. Afterwards `git grep -n -e singleUploadBytes -e fitsSingleUpload -e "in one piece" -e "5 GB" -- TidyShot TidyShotTests` prints nothing.
- [ ] Run the full suite.
- [ ] Hand checks (Tim's, after G1, for the checklist; design, Hand checks, Multipart): a 300 MB and a 6 GB recording, upload-only, Clop off then on, to `snap.tky.io`: the ring moves, `footprint` stays under 120 MB, the link plays through CloudFront, the key template drew one name; Wi-Fi off for 30 s mid-upload resumes with no visible restart; Wi-Fi off for two minutes fails with `Part <k> of <n>: …`, and Retry resumes at the done fraction, the bar at that fraction at once; quit mid-upload, relaunch, Retry Failed Uploads resumes (`resumes at` in the log); `kill -9` mid-upload, relaunch, Retry resumes; `Upload Trimmed` on a 300 MB trimmed file replaces the link in parts, and a failure keeps the old link; a Clop result kept in `multipart/` is used by Retry and gone after the upload.
- [ ] Commit: `feat: start, resume and finish multipart uploads`.

### Task 13: Delete and prune with a multipart upload

**Files:**
- Modify `TidyShot/App/AppCoordinator+Delete.swift`: `deleteCapture` (:14-84), a new `abortUploads(_:)` beside `deleteObjects` (:99-122), `removeRecord` (:142-159), `removeFiles(ofPruned:)` (:221-243).

**Consumes:** Task 7's `aborts(for:)` and `objects(for:)`; Task 9's `abortMultipartUpload`; Task 12's `multipartFiles`.

**Produces** (design, Cancel and Delete):
- `func abortUploads(_ refs: [MultipartRef]) async -> String?`, the same shape as `deleteObjects`: credentials stored now, a destination per ref's location. For each ref: Abort; `.aborted` sends a second Abort (a part in progress may still land after an Abort); `.aborted` and `.notFound` both count as done; logged `Upload: <name> multipart aborted`, or `Upload: <name> multipart abort failed: <error>` and its reason returned. `<name>` is the record's file name, or its id when it has no file, as elsewhere; `abortUploads` takes it from the caller.
- `deleteCapture`, after `cancelUpload` and before the object groups: `abortUploads(CaptureDeletion.aborts(for: current))`. A reason takes the existing second alert with `CaptureDeletion.storageFailureMessage(reason:)`, so a capture whose upload cannot be aborted is never stuck. Then the groups delete as today, `multipart.key` among them.
- `removeRecord` and `removeFiles(ofPruned:)` call `multipartFiles.remove(id:)`. Pruning aborts nothing.

**Steps:**
- [ ] Implement. There is no coordinator test; `CaptureDeletionTests` (Task 7) cover the lists.
- [ ] Run the full suite.
- [ ] Hand checks (Tim's, after G1, for the checklist): Delete mid-upload aborts (the AWS console lists no incomplete upload for the key) and the key is gone; Delete of a failed upload aborts, and its confirmation says it removes the object from storage; with the key's `s3:AbortMultipartUpload` removed (Tim's IAM change, then put back), Delete shows the second alert with the 403's reason; the lifecycle rule is on the bucket.
- [ ] Commit: `feat: abort multipart uploads on Delete`.

### Task 14: The signed download with progress

**Files:**
- Create `TidyShot/Upload/S3Destination+Download.swift`.
- Modify:
  - `TidyShot/Output/DragFileStore.swift`: `landingURL()`;
  - `TidyShotTests/StubURLProtocol.swift`: chunked bodies, a failure mid-body, and response headers per request.
- Tests: create `TidyShotTests/DragDownloadTests.swift`; add to `DragFileStoreTests`.

**Consumes:** `ProgressGate` (internal since Task 10); `S3Destination.signedRequest`, `httpResponse`, `failure`, `excerpt`.

**Produces:**
- `DragFileStore.landingURL() throws -> URL` (Gap 15).
- `S3Destination.download(key: String, to landing: URL, expectedBytes: Int64?, resumeData: Data? = nil, progress: @escaping @Sendable (Double) -> Void) async throws`:
  - with no resume data, a signed GET as `download(key:to:)` signs it, through `session.downloadTask(with:)`; with resume data, `session.downloadTask(withResumeData:)`. Bridged with a checked continuation inside `withTaskCancellationHandler`, whose cancel cancels the URLSession task.
  - `DragDownloadDelegate` (Gap 7), set as the task's `delegate`: refuses redirects; `didWriteData` reports `totalBytesWritten / expected`, `expected` being `totalBytesExpectedToWrite` when known and `expectedBytes` otherwise, through a `ProgressGate`; `didFinishDownloadingTo` moves the file to `landing` at once (before it returns), then reads the response's status; on a non-2xx it reads the error body from `landing` (`errorBody`'s 64 KiB cap), removes `landing` and keeps `failure(http, bodyText: excerpt(…))`; `didCompleteWithError` resumes the continuation with the error (the `URLError`, carrying `downloadTaskResumeData`, unchanged, Gap 16), the kept failure, or success.
  - A cancel leaves nothing at `landing`; URLSession removes its own temporary file.

**Steps:**
- [ ] Extend `StubURLProtocol`'s `Entry` with `chunkSize: Int?` (the body is delivered in chunks of that size), `failAfterBytes: Int?` (after that many bytes the load fails with `URLError(.networkConnectionLost)`), and keep the per-request headers the handler returns. Existing tests do not change.
- [ ] Write the design's `DragDownloadTests` and see them fail, with the landing path in a temporary `Drag/.downloads`: a body delivered in 8 chunks with `Content-Length` reports rising fractions ending at 1, and the file at `landing` has the body; the file is at `landing` when the delegate's callback returns (the test's progress closure is not involved; check the path right after the call returns and that URLSession's temporary folder holds no leftover); a transport failure mid-body leaves no file and throws a `URLError`; a 403 throws `.httpStatus(403, body: "AccessDenied: Access Denied")` and leaves no file; a cancel of the calling task leaves no file and throws a cancellation; with no `Content-Length` the fractions use `expectedBytes`; a resumed request carries a `Range` header (the stub records it). If URLSession produces no resume data through a `URLProtocol` stub, that last test calls `download(… resumeData:)` with resume data built by a first cancelled download, and when there is none, it is replaced by a test that `resumeData` reaches `downloadTask(withResumeData:)` through a session seam; the task's report says which.
- [ ] Implement.
- [ ] Run the full suite.
- [ ] Commit: `feat: signed download with progress`.

### Task 15: The card and the row while a drag file downloads

**Files:**
- Create `TidyShot/Overlay/DragDownloadRule.swift` (pure).
- Modify:
  - `TidyShot/Overlay/QuickAccessModel.swift`: `QuickAccessStatus` (:5-22), the model's state (:27-44), callbacks (:64-67) and `status` (:121-137);
  - `TidyShot/Overlay/QuickAccessView.swift`: `cardToolTip` (:185-192), `statusContent` (:209-270);
  - `TidyShot/Overlay/QuickAccessController.swift`: `Actions` (:31-62), `setDownloading` beside `setOptimizing` (:167), `makeCard` (:205-221), `scheduleClose` (:342-362);
  - `TidyShot/Overlay/QuickAccessCardDragSource.swift`: `mouseDown` (:48-58), `mouseDragged` (:60-76);
  - `TidyShot/RecentCaptures/RecentCaptureFormatting.swift`: `detail`, `detailWithoutSize`, `detailParts` (:19-51);
  - `TidyShot/RecentCaptures/RecentCaptureMenuItemView.swift` (:17-29) and `RecentCapturesMenu.swift` (:56-57): pass `isDownloading`;
  - `TidyShot/App/AppCoordinator+Overlay.swift`: `overlayActions` (:21-37) gains the download action as a stub that Task 16 fills (`downloadForDrag: { _ in }`).
- Tests: create `TidyShotTests/DragDownloadRuleTests.swift`; add to `QuickAccessModelTests` and `RecentCaptureFormattingTests`.

**Produces:**
- `nonisolated enum DragDownloadRule`:
  - `static let resumeWindow: TimeInterval = 840` (14 minutes);
  - `static func starts(record: CaptureRecord, hasDragFile: Bool, isRunning: Bool) -> Bool`: a time-based record (MP4 or GIF) with no local file, uploaded (`uploadedKey` and `objectLocation` set), `uploadBlockedReason == nil`, no drag file, none running;
  - `static func hasRoom(byteCount: Int?, freeBytes: Int64?) -> Bool`: `RecordingLimits.hasRoom(for:freeBytes:)`, a nil `byteCount` counting as enough;
  - `static func usesResumeData(signedAt: Date, now: Date) -> Bool`: `now − signedAt < resumeWindow`;
  - `static func keepsCardOpen(isDraggingOut: Bool, isDownloading: Bool) -> Bool`.
- `QuickAccessStatus.downloading(Double)` and `.downloadFailed(String)`.
- `nonisolated enum DragDownloadStatus: Equatable { case running(Double), failed(String) }`; `QuickAccessModel.dragDownload: DragDownloadStatus?` (observed); `var isDownloadingForDrag: Bool`; `status` gives `.downloading` or `.downloadFailed` from it, after `soundNotMuted` and before the upload state (Gap 12). `@ObservationIgnored var onDownloadForDrag: () -> Void = {}`.
- `QuickAccessView`: `.downloading(f)` draws as `.uploading` with `Downloading…`; `.downloadFailed(message)` is `Label("Download failed", systemImage: "exclamationmark.triangle.fill")` in red with the file label under it, the message as `cardToolTip`. No Retry button: `buttonRow` reads `record.uploadState`, which stays `.uploaded`, so it shows Copy URL.
- `QuickAccessController.Actions.downloadForDrag: (UUID) -> Void`; `setDownloading(_ status: DragDownloadStatus?, for recordID: UUID)`; `scheduleClose` keeps the card while `DragDownloadRule.keepsCardOpen(isDraggingOut:isDownloading:)`.
- `QuickAccessCardDragView`: `mouseDown` clears `askedForDownload`; `mouseDragged`, past the threshold with no `dragFileURL`, calls `model.onDownloadForDrag()` once per press (Gap 11), then waits as today.
- `RecentCaptureFormatting.detail(for:now:locale:isOptimizing:isDownloading: Bool = false)` and `detailWithoutSize` the same: the state reads `Downloading` while `isDownloading`, whatever the upload state, after `Sound not muted`.

**Steps:**
- [ ] Write the design's `DragDownloadRuleTests`, `QuickAccessModelTests` and `RecentCaptureFormattingTests` items and see them fail: `starts` for an uploaded MP4 and GIF with no local file, and not for an image, a local file, a drag file, a running download, a `Sound not muted` record or a record that is not uploaded; `hasRoom` at `byteCount + 1 GB` exactly and one byte under, nil size and nil free space counting as enough; `usesResumeData` at 13:59 true and 14:00 false; `keepsCardOpen` for the four cases; `.downloading(0.4)` for a running download over an uploaded record; `.downloadFailed("Server returned HTTP 403.")`; `soundNotMuted` still wins; the row's detail reads `… · Downloading` while downloading and as today otherwise.
- [ ] Implement.
- [ ] Run the full suite.
- [ ] Commit: `feat: download status on the card and the row`.

### Task 16: The drag-out download

**Files:**
- Modify:
  - `TidyShot/App/AppCoordinator.swift`: the Drag-out state group (:197-217);
  - `TidyShot/App/AppCoordinator+DragOut.swift`: `downloadDragFile(recordID:)`, `cancelDragDownload(_:)`, `stageVideoDragFile` (:170-210), `removeDragFolder` (:152-157);
  - `TidyShot/App/AppCoordinator+Overlay.swift`: `overlayActions`' `downloadForDrag` and `overlayDidClose` (:65-73);
  - `TidyShot/App/AppCoordinator+RecordActions.swift`: `saveVideoCopy` (:128-148);
  - `TidyShot/App/AppCoordinator+Delete.swift`: `removeRecord`'s download cancel (through `removeDragFolder`).

**Consumes:** Task 14's download and `landingURL()`; Task 15's rule, statuses and actions.

**Produces** (design, Drag-out download):
- Drag-out state: `@ObservationIgnored var downloadingDragIDs: [UUID: Task<URL?, Never>] = [:]` beside `stagingVideoIDs`, with the line `// +Overlay's overlayDidClose and +Delete's removeRecord (through removeDragFolder) cancel downloadingDragIDs.`; `@ObservationIgnored var dragDownloadResume: [UUID: (data: Data, signedAt: Date)] = [:]`; `var downloadingVideoIDs: Set<UUID> = []` (observed, as `optimizingVideoIDs`).
- `func downloadDragFile(recordID: UUID)`, internal like `prepareDragFile`, since `+Overlay`'s `overlayActions` calls it:
  - returns unless `DragDownloadRule.starts(record:hasDragFile: dragFiles.stagedFile(id:) != nil, isRunning: downloadingDragIDs[recordID] != nil)` and the card shows the record;
  - disk: `DragDownloadRule.hasRoom(byteCount: record.byteCount, freeBytes: RecordingLimits.freeBytes(at: dragFiles.directory))`; otherwise `overlay.setDownloading(.failed(RecordingLimits.diskFullText), for:)`, `Drag-out download for <id> refused, not enough disk space`, nothing requested;
  - `downloadSource(of: record, title: nil)`; a throw sets `.failed(error.localizedDescription)` and logs `Drag-out download for <id> failed: <error>`;
  - the name from `DragFileName.name(for:suggestion:)`, the generation from `dragGenerations`, `landingURL()`, `downloadingVideoIDs.insert`, `setDownloading(.running(0))`, and a `Task` stored in `downloadingDragIDs` that calls `destination.download(key:to:expectedBytes:progress:)` from a detached task (its progress hops to the main actor and calls `setDownloading(.running(f))`);
  - on success, back on the main actor: when the generation still matches, `dragFiles.adopt(id:name:moving: landing)` and `overlay.setDragFile(url, for:)`; otherwise the landing file is removed and nil returned;
  - on failure: `Drag-out download for <id> failed: <error>`, `setDownloading(.failed(message))`, the folder left empty, nothing posted;
  - on cancel: `Drag-out download for <id> cancelled`, nothing set;
  - every end clears `downloadingDragIDs[id]` and `downloadingVideoIDs`; a success also clears the card's status with `setDownloading(nil, for:)`.
- `func cancelDragDownload(_ id: UUID)`, internal (`+Overlay` calls it): cancels the task, drops `dragDownloadResume[id]`, clears the status. `overlayDidClose` calls it before `scheduleDragCleanup`; `removeDragFolder` calls it (Delete and the clean-up).
- `stageVideoDragFile`: with a download running for the record, awaits it and hands its result to the card instead of reading the empty folder.
- `saveVideoCopy`: after the save panel, awaits a running download for the record before `copyVideo`, so it copies the landed file and starts no second GET. With none running, as today.
- The card's status lives on its model and `overlay.update(record:)` leaves it alone, so `pushCardFlags` does not push it.
- `prefetchDragFile` keeps its early return for `isTimeBased`: neither a restored card's appearance nor Restore Closed Overlay downloads a video.

**Steps:**
- [ ] Implement the above (no coordinator test; Tasks 14 and 15 cover the parts).
- [ ] **Resume a failed download** (held by G2): on failure, `(error as? URLError)?.downloadTaskResumeData` is kept in `dragDownloadResume[id]` with the `signedAt` of the download's first request (Gap 16). The next `downloadDragFile` passes it when `DragDownloadRule.usesResumeData(signedAt:now:)` holds and drops it otherwise, starting again with a new signature. Resume data is dropped on Delete and when the card closes.
- [ ] Run the full suite.
- [ ] Hand checks (Tim's, for the checklist; design, Hand checks, Drag-out), with a restored card for an uploaded recording with no local file: a drag shows `Downloading…`, the card stays past its auto-close, the file lands and the next drag drops into Finder and Slack whole; a drag held through a short download starts the session when it lands; Save As… during the download waits and saves; Close during the download cancels it and the folder is empty; Delete during it; Wi-Fi off during it shows `Download failed`, and a drag soon after resumes (the fractions continue in the log); a disk-check refusal shows `Your disk is almost full.` as the tool tip (read the log if no small volume is at hand); a GIF with no local file downloads too; the row reads `Downloading` meanwhile; a click on the thumbnail still opens the link and downloads nothing.
- [ ] Commit: `feat: drag out an uploaded recording by downloading it`.

### Task 17: README and the R1 checklist

**Files:**
- Modify:
  - `README.md`: the URL scheme table, its action, Security and Errors paragraphs; the Screen recording section (:358-360, :373, :387-388); the Upload section's new `Large uploads` paragraph;
  - `docs/testing/recording-r1-manual-checklist.md`: lines 272, 308, 313, 330 and 331;
  - `docs/superpowers/research/recording-probes/README.md`: the setup step now points to the README's steps.

**Steps:**
- [ ] The URL scheme (design, URL commands, README): two rows. `record-screen`: `Record Screen: select an area or click a window. A rectangle is shown in the selection, and a click inside it records it (no key does). action is upload or save`, parameters `action`, `x`, `y`, `width`, `height`, `display`. `stop-recording`: `Stop the recording, or cancel its count-in; nothing otherwise`, no parameters. The action paragraph: `record-screen` takes only `upload` and `save`. The Security paragraph: `record-screen` always shows the selection, with a rectangle too, so it needs only the first switch; once you click, the recording takes the microphone and the webcam bubble as Settings has them; it asks for microphone and camera access first when macOS has not asked yet, as the shortcut does. The Errors paragraph: an action a command does not take, and for `record-screen` an area under 32 by 32 points.
- [ ] Screen recording (design, Multipart, README): lines 358-360 become: a recording of 100 MiB or more uploads in 16 MiB parts, three at a time; a failed part is sent again; a failed or interrupted upload resumes from the parts already sent when you retry, also after a relaunch, unless it waited more than 7 days, when it starts from zero; a recording over 625 GB is kept and *Not uploaded* says why. Line 373: dragging an uploaded recording with no local file downloads it first, with progress on the card. Lines 387-388: pause and a separate upload lane for videos are left out.
- [ ] `Large uploads` (held by G1 for its IAM sentences): the actions an upload-only key needs (`s3:PutObject`, which covers Create, UploadPart and Complete; `s3:AbortMultipartUpload`; `s3:ListMultipartUploadParts` for a resume whose part list was lost), with M1's results; the lifecycle rule as JSON (`{"Rules":[{"ID":"abort-incomplete-multipart","Status":"Enabled","Filter":{"Prefix":""},"AbortIncompleteMultipartUpload":{"DaysAfterInitiation":7}}]}`) and the steps: `aws s3api get-bucket-lifecycle-configuration --bucket snap.tky.io`, add the rule to the rules it returns (none when it answers `NoSuchLifecycleConfiguration`), `aws s3api put-bucket-lifecycle-configuration --bucket snap.tky.io --lifecycle-configuration file://lifecycle.json` with the merged list, then the get again to check. Why: an upload never finished is billed until it is aborted; TidyShot aborts the ones it knows about; the rule aborts the rest. If M1 found ListParts 403, the paragraph says a resume whose part list was lost starts again, and why.
- [ ] The R1 checklist (design, Checklists): line 272 becomes R4's 625 GB refusal (`Not uploaded` / `The recording is larger than 625 GB, too large to upload.`); lines 308 and 313 point to R4's drag-out download (`recording-r4-manual-checklist.md`); lines 330 and 331 read the 625 GB check. Each changed line names R4.
- [ ] Commit: `docs: R4 README and the R1 checklist`.

### Task 18: Checklist and design close-out

**Files:**
- Create `docs/testing/recording-r4-manual-checklist.md`.
- Modify:
  - the R4 design: probe results the tasks could not record, and an "R4 built notes" section;
  - `docs/superpowers/specs/2026-10-23-coordinator-split-design.md`, section 6: an R4 bullet placing R4's members as the R4 design's opening list does, with `startRecording(intent:preselect:)` and `stopRecordingCommand(sender:)` as the URL handler's routes and `multipartFiles` as a collaborator.

**Steps:**
- [ ] Grep the finished code for every string the design gives (URL errors and notices, the `Recording:`, `Upload:` and `Drag-out download` log lines, `UploadError` descriptions, `Part <k> of <n>`, the 625 GB notice, `Downloading…`, `Download failed`, `Downloading`), and fix any drift.
- [ ] Run the coordinator split's surface check (its plan's Task 7 command) with `startRecording` and `stopRecordingCommand` added to the entry points; it prints nothing.
- [ ] Write the checklist in the form of `recording-r3-manual-checklist.md`: what it covers and when to run it; held gates first; setup (a Release build, Tim's IAM policy, the lifecycle rule, a 300 MB and a 6 GB recording, how to read `footprint` and the log with `/usr/bin/log show --last 10m --style compact --predicate 'process == "TidyShot"' | grep -E "Recording:|Upload:|Drag-out"`); M1 and D1 with their commands and a blank for each result; U1; every hand check in the design and in Tasks 3 to 5, 12, 13 and 16; and the design's 29 calls and this plan's 16 gaps to confirm or overrule.
- [ ] Write the Built notes: what was built differently, the sixteen gaps, the probe results, any held step Tim chose to ship without, and the items still open, which the PR lists.
- [ ] Run the full suite and the Release build once. `git diff --stat main -- project.yml TidyShot/Info.plist TidyShot/TidyShot.entitlements` prints nothing.
- [ ] Commit: `docs: recording R4 checklist and design close-out`.

## Test totals

| After | Total |
|---|---|
| Baseline | the first run's line on `recording-r4` |
| Task 1 | baseline plus `MultipartXMLTests` and `MultipartRequestsTests` (2 new suites) |
| Task 2 | Task 1 with `URLCommandTests` and `URLCommandGateTests` extended |
| Task 3 | Task 2 with `ShortcutsTests`, `URLCommandHandlerTests` and `RecordingControllerTests` extended |
| Task 4 | Task 3 plus the `SelectionOutcomeTests` additions |
| Task 5 | Task 4 plus the `URLCommandHandlerTests` additions |
| Task 6 | Task 5 plus `MultipartPlanTests` and `UploadStartTests` (2 new suites) |
| Task 7 | Task 6 plus the `CaptureRecordTests`, `CaptureDeletionTests`, `HistoryStoreTests` and `EditorUploadPlanTests` additions |
| Task 8 | Task 7 plus `MultipartStoreTests` (1 new suite) |
| Task 9 | Task 8 plus `UploadErrorTests` (1 new suite) and the `S3SignerTests`, `S3DestinationConfigTests` and `S3DestinationTests` additions |
| Task 10 | Task 9 plus the `UploadQueueTests` additions |
| Task 11 | Task 10 plus the `UploadQueueTests` additions |
| Task 12 | Task 11 with `RecordingSavePlanTests` and `UploadRefusalTests` changed and one `RecordingLimitsTests` test removed |
| Task 13 | unchanged |
| Task 14 | Task 13 plus `DragDownloadTests` (1 new suite) and the `DragFileStoreTests` addition |
| Task 15 | Task 14 plus `DragDownloadRuleTests` (1 new suite) and the `QuickAccessModelTests` and `RecentCaptureFormattingTests` additions |
| Task 16 | unchanged |
| Task 17 | unchanged |
| Task 18 | unchanged: the baseline's suites plus 8 |
