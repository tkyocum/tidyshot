# Recording R4 manual test checklist

Run after any change to `URLCommand`, `URLCommandHandler` or `URLCommandGate` (`record-screen`,
`stop-recording`), `SelectionController`, `SelectionView` or `SelectionOutcome` (the preset rect),
`AppCoordinator` (`+Recording`'s `startRecording`, `stopRecordingCommand`, `startRecordScreen` and
`recordingStartCancelled`; `+Upload`'s resume decision, Clop copy, events and Retry; `+Delete`'s aborts; `+DragOut`'s
download; `+Overlay` and `+RecordActions`), `MultipartPlan`, `MultipartStore`, `MultipartRequests`,
`MultipartXML`, `S3Destination+Multipart`, `S3Destination+Download`, `UploadQueue` (the multipart pass), the
quick-access card's drag source and download status, or the README's Large uploads paragraph. Automated
tests cover the pure decisions (the URL kinds, actions and gate, the refusal and phase rules, the preset
click, the plan, the resume and start-step rules, the requests and XML scans, the sidecar store and sweep, the
six S3 calls against an in-memory multipart bucket, the queue over a fake destination, the download over a
stub, the download rule, the card's status and the row's detail). Everything here needs a real bucket, a real
screen, Screen Recording, real mouse events or eyes. No test sends a request to a real bucket, records the
screen or drags a file. The R1, R2 and R3 checklists (`recording-r1-manual-checklist.md`,
`recording-r2-manual-checklist.md`, `recording-r3-manual-checklist.md`) still cover starting, stopping, GIF,
the microphone, mute, Trim, the bubble and quitting; run them too after a change to those.

Several steps are probes (M1, D1): they run a small program that talks to the bucket, and ask you to write down
what the bucket did. Fill each blank, then copy the results into the R4 design's Probes section
(`docs/superpowers/specs/2026-10-27-tidyshot-screen-recording-r4-design.md`) with the date and the Mac, and mark
the item done in its R4 built notes.

## Gates (read this first)

Both probes ran on 2026-10-29 (the R4 design's Probes, Results), and no step is held.

- **G1, multipart against the real bucket (M1).** Passed for the calls: Create, UploadPart, Complete, Abort and
  ListParts all answered as expected with Tim's key, no call was refused, Complete's 200 carried no `<Error>`, and
  the HEAD showed `Cache-Control: no-cache` (Tim's lane sends no ACL). The README's `Large uploads` paragraph now
  lists the IAM actions and says the drag-out download needs `s3:GetObject`. M1's `footprint` was over the design's
  limits: 171 MB peak at 16 MiB parts (limit 120 MB) and 495 MB at 64 MiB parts (limit 250 MB). That goes back to
  Tim, and the merge waits on his decision; the upload path is unchanged.
- **G2, resume data for a failed drag-out download (D1).** Passed: resume data came back, the resume after 2 s
  continued at 0.5004 with a 206, and the late resume at 16 minutes was refused with 403 `RequestTimeTooSkewed`.
  Task 16's "Resume a failed download" step is built: a failed download keeps its `downloadTaskResumeData` with the
  time its request was signed, the next drag passes it back while less than 14 minutes have passed and starts again
  with a new signature after that, and a resumed download logs `Drag-out download for <id> resumed at <fraction>`.
- **The hand checks** in every section below have not run. The Release build has no Screen Recording grant, and a
  grant is Tim's to give.

## Setup

A fresh **Release** build (`xcodebuild -project TidyShot.xcodeproj -scheme TidyShot -configuration Release
-derivedDataPath .build-rel build`), signed ad hoc, so every rebuild needs a new Screen Recording grant (see
`Config/Local.xcconfig`). Give it Screen Recording in System Settings > Privacy & Security. Only one TidyShot may
run at a time.

**Tim's IAM policy.** The key in Settings > Upload must allow, on `snap.tky.io`:
- `s3:PutObject` (Create, UploadPart and Complete) and `s3:DeleteObject` (Delete), as before;
- `s3:AbortMultipartUpload` (Delete and a start over abort the stored upload);
- `s3:ListMultipartUploadParts` (a resume whose part list was lost);
- `s3:GetObject` (Copy Image, and the drag-out download's signed GET).

M1 (2026-10-29) found none of them missing. The README's `Large uploads` paragraph lists them.

**The lifecycle rule.** Tim says the bucket already has the `AbortIncompleteMultipartUpload` rule; that is not
verified. Check it with `aws s3api get-bucket-lifecycle-configuration --bucket snap.tky.io`. If the rule is
absent, add it by the README's get, merge and put steps (`Large uploads`): `put-bucket-lifecycle-configuration`
replaces the whole configuration, so the merged list must hold the old rules too, and `lifecycle.json` holds only
`Rules` (the put refuses the get's `TransitionDefaultMinimumObjectSize` in the file). It must be on before the
multipart hand checks. Write down what the get printed: ______

**The recordings.** One of about 300 MB and one of about 6 GB, each recorded or already in history (a long
fullscreen recording at a high frame rate reaches 6 GB). Upload-only is Tim's mode (Settings > General > After
capture). Run every multipart check with Clop off, then once with Clop on (Settings > General > Optimization, and Clop
running).

**Reading `footprint`** while an upload runs: `footprint TidyShot | head -12`. The `Footprint:` line is the memory
now; `phys_footprint_peak` under `Auxiliary data` is the most used so far. Judge the peak against 120 MB at 16 MiB
parts.

**Reading the log:**
```bash
/usr/bin/log show --last 10m --style compact --predicate 'process == "TidyShot"' | grep -E "URL command|Recording:|Upload:|Drag-out"
```
Call it "the log" below. `URL command` is in the pattern because the handler's lines have no `Recording:` prefix. The R4 lines are:
- `URL command from <sender>: <url>` and `URL command from <sender> dropped, <reason>: <url>` with the reasons `a capture is running`, `a recording is starting`, `a recording is running`, `the microphone prompt is open`, `the camera prompt is open` and `a queued capture command ran first`;
- `Recording: URL start ignored, the app is quitting`, `Recording: URL start ignored, a recording is starting`, `Recording: not started, the count-in was cancelled`;
- `Recording: stop-recording from <sender> stopped the recording`, `… cancelled the count-in`, `… did nothing, no recording is running`;
- `Recording: <microphone|camera> prompt from Settings deferred, <reason>` with the reasons `a capture is running`, `a recording is being saved` and `the <name> prompt is open`;
- `Recording: <name> is too large to upload (over 625 GB)`;
- `Upload: <name> multipart, <n> parts of <m> MiB, upload id <id>`, `… create failed: <error>`, `… resumes at <done> of <n> parts`, `… part list missing, listing parts`, `… part list unavailable, starting again`, `… part list rejected, listing parts`, `… part <k> failed, retry <try>: <error>`, `… multipart completed`, `… multipart aborted`, `… multipart abort failed: <error>`, `… source changed, starting again`, `… destination changed, starting again`, `… key changed, starting again`, `… key taken, starting again`, `… upload id gone, starting again`, and `Upload: Clop's copy could not be kept for resume: <error>`;
- `Drag-out download for <id> failed: <error>`, `… cancelled`, `… refused, not enough disk space`.

The upload id appears in the log only in the `multipart, …` line, never in a notice; check that on every log you
read. No credential, signature or session token appears anywhere.

**Where the files are:**
```bash
C="$HOME/Library/Containers/io.tky.tidyshot/Data"
ls -la "$C/Library/Application Support/TidyShot/multipart"   # <recordID>.json sidecars and <recordID>.mp4 kept copies
ls -laR "$C/tmp/Drag"                                         # <recordID>/<name> drag copies, and .downloads/
```

## M1, multipart against `snap.tky.io` (settles G1)

Build and run from the repository root. M1 uploads and deletes objects under `<prefix>/r4-probe-<random>` in the
bucket. It reads `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY` and an optional `AWS_SESSION_TOKEN` from the shell, uses
them for this run only and writes them nowhere.
```bash
xcrun swiftc -O -target arm64-apple-macos26.0 -o /tmp/r4-multipart \
  docs/superpowers/research/recording-probes/r4-multipart.swift TidyShot/Upload/S3Signer.swift \
  TidyShot/Upload/AWSCredentials.swift TidyShot/Upload/MultipartRequests.swift TidyShot/Upload/MultipartXML.swift
/tmp/r4-multipart snap.tky.io <region> <endpoint> <prefix> [acl]
```
`acl` (the literal word) when TidyShot's lane sends `x-amz-acl: public-read`. At the halfway pause of each 2 GiB
upload it prints `halfway, pid <pid>: run footprint <pid> now`; in a second Terminal run `footprint <pid>` during the
20 s. Date and Mac: ______

- [ ] 1. Create (`Content-Type: video/mp4`, `Cache-Control: no-cache`, and the ACL if sent): status ______, time ______ ms.
- [ ] 2. Three parts (5, 5 and 1 MiB, three at a time): statuses ______, ETags present ______.
- [ ] 3. ListParts: status ______; it lists three parts with sizes and ETags: ______. (A 403 means
  `s3:ListMultipartUploadParts` is missing; write the `<Code>`: ______.)
- [ ] 4. Complete (`content-type: application/xml`): status ______. The whole body, because a 200 can carry `<Error>`:
  ______. Plain `CompleteMultipartUploadResult` expected.
- [ ] 5. HEAD of the key: `Content-Length` ______ (11 MiB = 11534336 expected), `Cache-Control` ______ (`no-cache`
  expected). With `acl`, the object is public: ______.
- [ ] 6. DELETE: status ______.
- [ ] 7. The second upload: Abort status ______ (204), ListParts on the aborted id ______ (404 `NoSuchUpload`), Complete on
  it ______ (404). (An Abort 403 means `s3:AbortMultipartUpload` is missing; write the `<Code>`: ______.)
- [ ] 8. The 2 GiB sparse file in 16 MiB parts, three in flight: every status 2xx ______. `footprint` at the halfway
  pause: `Footprint:` ______ MB. `phys_footprint_peak` at the end: ______ MB (under 120 MB expected).
- [ ] 9. The same file in 64 MiB parts: every status 2xx ______. `Footprint:` ______ MB, peak ______ MB (under 250 MB
  expected).
- [ ] The probe left no object behind (the console, or `aws s3 ls s3://snap.tky.io/<prefix>/`) and no incomplete upload
  (`aws s3api list-multipart-uploads --bucket snap.tky.io`, if the key may list): ______.

Result for G1: ______ (passed, or what goes back to Tim). Run on 2026-10-29: every call passed; the footprint was
over both limits and went back to Tim (the R4 design's Probes, Results).

## D1, a signed download with progress and resume (settles G2)

Run on an uploaded recording of at least 100 MB that you name. It takes about 17 minutes. It reads the same
environment variables as M1.
```bash
xcrun swiftc -O -target arm64-apple-macos26.0 -o /tmp/r4-download \
  docs/superpowers/research/recording-probes/r4-download.swift TidyShot/Upload/S3Signer.swift \
  TidyShot/Upload/AWSCredentials.swift TidyShot/Upload/MultipartRequests.swift TidyShot/Upload/MultipartXML.swift
/tmp/r4-download snap.tky.io <region> <endpoint> <key>
```
Date and Mac: ______

- [ ] 1. Progress callbacks arrive and the fraction moves (`didWriteData` as a fraction with its time): ______.
- [ ] 2. At 50 % it cancels with resume data: resume data came back ______, size ______ bytes.
- [ ] 3. After 2 s the resume carries on from about 50 %: first fraction after the resume ______, status ______ (206
  expected), final file size ______ against the first response's `Content-Length` ______.
- [ ] 4. The late resume (16 minutes after signing): status ______ (403 expected, the signature having expired). If the
  probe says it could not find or put back the partial file, or step 4 failed with no status, write it down as
  inconclusive, not as a refusal: ______.

Result for G2: ______ (resume data works and the late resume is refused: build the held step; no resume data or a
resume that does not continue: drop it). Run on 2026-10-29: passed, and the step is built (the R4 design's Probes,
Results).

## U1, the URL commands by hand

These record the screen. Terminal first, then Raycast and Keyboard Maestro. The second URL switch (Settings > General)
may be off for all of them; the first must be on.
- [ ] `open 'tidyshot://record-screen'` shows the selection (crosshair, loupe, window highlight), then the count-in
  when `Count down before recording` is on, then the bar. Stop saves as the Record Screen shortcut does. From
  Terminal ______, Raycast ______, Keyboard Maestro ______.
- [ ] `open 'tidyshot://record-screen?action=save'` and `?action=upload` end as the setting says: `save` saves the
  file with no upload, `upload` uploads (upload-only when that is the after-capture setting). `?action=copy`,
  `annotate` and `pin` post `Unknown action “copy” for record-screen. Use upload or save.` (title `TidyShot URL
  command`) and start nothing. `?action=bogus` posts `Unknown action “bogus”. Use upload, save, copy, annotate or
  pin.`
- [ ] `open 'tidyshot://record-screen?x=200&y=200&width=640&height=400'` (bottom-left origin) shows the rect cut out
  of the dimming with its stroke and size label, on the display that holds its centre; with `&display=2` on the
  second display. Return and Enter do nothing. A click inside it (no drag) records that rect after the count-in. A
  drag anywhere draws a new area and records that. A click outside it on a highlighted window records that window.
  Escape cancels. The rect is not remembered as the previous area (Capture Previous Area is unchanged).
- [ ] `?x=…&width=20&height=20` (under 32 by 32 pt, or clipped to it by the display's edge) posts `The area must be at
  least 32 by 32 points to record.` and shows no selection.
- [ ] The Record Screen shortcut with no preset is unchanged: no rect, the same selection.
- [ ] `open 'tidyshot://stop-recording'` during the selection does nothing (the selection stays; Escape cancels it);
  the log says `… did nothing, no recording is running`. During the count-in with `Count down before recording` on:
  the count-in is cancelled, nothing records, the log says `… cancelled the count-in`. During the count-in with it
  off: send `stop-recording` within the settle delay (a Keyboard Maestro macro that sends `record-screen` with a rect,
  clicks it, and sends `stop-recording`): nothing records, and the log says `Recording: not started, the count-in was
  cancelled`. During the recording: it stops, `Recording stopped` posts and the file is saved and uploaded by the
  intent the start was given. During the save (a GIF converting, or a mute ladder): nothing happens. With nothing
  recording: nothing happens and no notice posts. A second `stop-recording` during the stop wait logs `did nothing`.
  Selection ______, count-in on ______, count-in off ______, recording ______, saving ______, idle ______.
- [ ] `record-screen` during a recording is dropped, logged `URL command from <sender> dropped, a recording is
  running`, and the recording goes on. During the count-in: `… a recording is starting`, and the count-in goes on.
  During a screenshot's selection (Capture Area, not yet clicked): `… a capture is running`, and the selection
  stays. During a microphone or camera prompt: `… the microphone prompt is open`. While a GIF converts (saving) it
  starts a new recording, as the shortcut does.
- [ ] Two `record-screen` URLs back to back (one Keyboard Maestro macro): one selection, no notice, and the second is
  logged (`Recording: URL start ignored, a recording is starting` or the handler's `dropped` line).
- [ ] The first microphone or camera prompt (reset with `tccutil reset Microphone io.tky.tidyshot` and `tccutil reset
  Camera io.tky.tidyshot`, which are Tim's) shows on a URL start, before the selection, and never in a video. With
  access already granted the start uses it with no prompt, and the recording takes the microphone and the webcam
  bubble as Settings has them.
- [ ] Quit TidyShot, then `open 'tidyshot://record-screen'`: the app launches and shows the selection once the launch
  has finished (a cold launch). A cold launch from a burst of `record-screen` then `stop-recording` (a macro that sends
  both): the start runs, the stop logs `did nothing` at once, and the selection stays.
- [ ] With the first URL switch off, both commands post `URL commands are off. Turn them on in Settings > General.`

## The preset rect (Task 4)

Covered by the U1 rect step; repeat on the second display and with a window under the rect.
- [ ] The rect shows with its stroke and size on the right display; the crosshair and loupe work elsewhere on that
  display; the window highlight is not drawn while the cursor is inside the rect.
- [ ] Return and Enter do nothing. A click inside records it after the count-in. A drag (even one that starts inside)
  replaces it on screen and records the dragged area on release. A click outside on a window records the window.
  Escape cancels.

## The Settings prompt's deferral reason (Task 3)

- [ ] Turn `Show webcam bubble` on in Settings while a GIF converts (the camera access undecided; reset with `tccutil
  reset Camera io.tky.tidyshot`, Tim's): the log says `Recording: camera prompt from Settings deferred, a recording
  is being saved`. During a recording it still says `… a capture is running`.
- [ ] The record shortcut during the settle delay with `Count down before recording` off records nothing and logs
  `Recording: not started, the count-in was cancelled`.

## Multipart upload (Tasks 12 and 13; after G1)

Each with the 300 MB and the 6 GB recording, upload-only, Clop off, then Clop on, to `snap.tky.io`. Read the log and
`footprint` as in Setup.
- [ ] The ring moves. `footprint`'s peak stays under 120 MB (6 GB, three parts in flight): ______ MB. The link plays
  through CloudFront. The key template drew one name (the key in the console is the one the card copied).
  The log has one `multipart, <n> parts of 16 MiB` line and a `multipart completed`. `multipart/` holds the sidecar
  while it runs, and neither the sidecar nor a kept copy after `.uploaded`.
- [ ] A recording under 100 MiB (one byte under is not practical; a short one) still uploads as one PUT: no `multipart,`
  line.
- [ ] Wi-Fi off for 30 seconds mid-upload: the upload resumes with no visible restart (the log may show `part <k>
  failed, retry <try>`).
- [ ] Wi-Fi off for two minutes: the upload fails with `Part <k> of <n>: …` on the card and in the row. Retry resumes at
  the done fraction, with the bar at that fraction at once, and the log says `resumes at <done> of <n> parts`.
- [ ] Quit mid-upload and relaunch: the record shows `Upload was interrupted.`; Retry Failed Uploads resumes (the
  log's `resumes at` line), and nothing resumes by itself at launch. `kill -9` mid-upload, relaunch, Retry resumes.
- [ ] Delete mid-upload aborts it (the AWS console, or `aws s3api list-multipart-uploads --bucket snap.tky.io`, lists no
  incomplete upload for the key) and the key is gone. `multipart/` holds nothing for the record.
- [ ] Delete of a failed multipart upload aborts it; its confirmation counts the object (`Removes it from object
  storage and from history.`).
- [ ] Remove `s3:AbortMultipartUpload` from the key (Tim's IAM change, put back afterwards): Delete shows the second
  alert with the 403's reason and `The object stays in the bucket.`; Remove drops the record and its files, and the
  incomplete upload is left to the lifecycle rule.
- [ ] Retry a failed multipart upload after Settings > Upload names another bucket: the log says `destination changed,
  starting again`, the new bucket gets the upload, and the old bucket lists no incomplete upload for the key.
- [ ] Retry after the recording's file changed (a trim, or a Save As over it): `source changed, starting again`, and the
  old upload is aborted first.
- [ ] A start over whose new file is under 100 MiB (trim a failed large recording to under 100 MiB, or let Clop shrink
  it, then Retry): the log has `multipart aborted` before the single PUT, and the console lists no incomplete upload
  for the key. (Fixed in the branch: the queue's single-PUT path aborts `abortFirst`; the record's `multipart` stays
  until `.uploaded` clears it.)
- [ ] `Upload Trimmed` on a 300 MB trimmed file replaces the link in parts; a failure (Wi-Fi off) keeps the old link
  and marks it stale, and a later `Upload Trimmed` resumes when the trimmed file still matches.
- [ ] Clop on, `Upload Trimmed` on a trimmed file over 100 MiB, fail it (Wi-Fi off for two minutes), trim again, then
  `Upload Trimmed`: the log shows `source changed, starting again` and the link plays the second trim, not the first.
- [ ] A Clop result kept in `multipart/<id>.mp4` is used by Retry (no second Clop run, `resumes at`) and is gone after
  the upload. A Clop copy that could not be kept logs `Clop's copy could not be kept for resume: <error>` and the job
  sends from the throwaway copy.
- [ ] Pruning removes the sidecar and the kept copy and aborts nothing. Set After capture to `Upload and copy URL`, fail
  a large upload (Wi-Fi off), quit, set the record's `timestamp` in `history.json` to two days ago, relaunch, set
  Overlay > `Keep history for 1 days` and take a new capture: the record leaves Recent Captures, and `multipart/`
  holds nothing for it. Put the retention back.
- [ ] The files in `multipart/` of a record with no state, or a state older than 7 days, are removed at launch (put an
  unrelated `<uuid>.json` there, relaunch); a file whose name does not start with a UUID is left alone.
- [ ] The lifecycle rule is on the bucket (Setup).
- [ ] A recording over 625 GB is not reachable by recording; the pure rule is tested. Nothing to run.

## Drag-out of an uploaded recording with no local file (Task 16)

With a restored card (Restore Closed Overlay, or an old record) for an uploaded recording with no local file and an
empty drag folder (`tmp/Drag`), and a copy of the same recording that is longer than a few seconds to download.
- [ ] A drag of the card shows `Downloading…` with a ring, the card stays open past its auto-close, the file lands
  under the key's name in `tmp/Drag/<id>/`, and the next drag drops into Finder and Slack whole (the same bytes as the
  bucket's object).
- [ ] A drag held through a short download starts the session when the file lands.
- [ ] A click on the thumbnail opens the link and downloads nothing. Neither a restored card's appearance nor Restore
  Closed Overlay downloads a video.
- [ ] Save As… during the download waits and then saves the landed file (one GET in the log, not two).
- [ ] Close during the download cancels it: `Drag-out download for <id> cancelled` in the log, and `tmp/Drag/<id>` and
  `.downloads/` hold nothing.
- [ ] Delete during the download cancels it and removes the folder.
- [ ] The row in Recent Captures reads `Downloading` meanwhile, and its normal detail afterwards.
- [ ] Wi-Fi off during the download shows `Download failed` with the error as its tool tip and no Retry button; the
  folder is empty and nothing posts. A drag soon after, with Wi-Fi back, resumes: the log shows `Drag-out download
  for <id> resumed at <fraction>` near where it stopped, not 0. A drag 14 minutes or more after the first request
  was signed starts again from 0, with no `resumed at` line.
- [ ] A recording marked `Sound not muted` starts no download on a drag.
- [ ] A disk-check refusal shows `Download failed` with `Your disk is almost full.` as its tool tip and logs `refused,
  not enough disk space`. (A small APFS volume as the container's is a hand set-up; read the log if none is at hand.)
- [ ] A GIF with no local file downloads too.
- [ ] A downloaded drag copy is not a local file: Copy File still needs one, and Trim downloads its own copy.
- [ ] After the card closes, the 60 s clean-up removes the downloaded copy; a restored card downloads again.

## Regression

- [ ] ⌃⇧1 to ⌃⇧7 and the R1 checklist's 6a, 6b and 7b checks behave as before. The R1 checklist's lines that R4
  changed (the 625 GB refusal, the drag of an uploaded recording) now point here.
- [ ] A screenshot capture, its upload and its Retry behave as before (single PUT; `Uploading…` ring at the byte
  fraction).
- [ ] The existing URL commands (`capture-area` with and without a rect, `capture-window`, `toggle-desktop-icons`)
  behave as before, including the second switch's four commands.
- [ ] An R3 recording with the bubble and click highlights, a GIF and a Trim behave as in their checklists.
- [ ] Quit TidyShot with nothing recording or uploading: it quits at once.

## The design's 29 calls, to confirm or overrule

The R4 design lists them at its end (`## The design's calls`). Write `confirm` or `overrule` and why; an overrule goes
in the design's built notes.
- [ ] 1. `record-screen` keeps CleanShot's name and parameters; `stop-recording` is TidyShot's own, with no alias. ______
- [ ] 2. `record-screen` takes `action=upload|save` only. ______
- [ ] 3. A rect under 32 by 32 pt is refused with `The area must be at least 32 by 32 points to record.` ______
- [ ] 4. A rect is preselected and only a click inside it records; no key does; the first switch is enough. ______
- [ ] 5. `startRecording` returns once the start is under way. ______
- [ ] 6. Recording notices do not name the URL's sender. ______
- [ ] 7. `CaptureRefusal` gains `.recordingStarting` and `.recordingRunning`, with their log reasons. ______
- [ ] 8. A `record-screen` during `.saving` starts a new recording. ______
- [ ] 9. `stop-recording` cancels a count-in, and a cancelled count-in never records. ______
- [ ] 10. `stop-recording` with nothing to stop posts no notice. ______
- [ ] 11. Multipart from 100 MiB, for every `.file` payload. ______
- [ ] 12. Parts of 16 MiB, raised from 156.25 GiB, capped at 64 MiB; 625 GiB refused. ______
- [ ] 13. Three parts in flight per job. ______
- [ ] 14. Parts are read into `Data` and sent with `upload(for:from:)`. ______
- [ ] 15. Each request retries on its own; a multipart job is not retried as a whole; at most two restarts. ______
- [ ] 16. Clop's result is kept in `multipart/<id>.mp4`, and a Retry whose source still matches resumes from it without
  Clop. ______
- [ ] 17. The card and row show no part count, only the byte fraction. ______
- [ ] 18. No upload resumes by itself at launch. ______
- [ ] 19. The launch sweep aborts nothing and drops the state files of a state older than 7 days. ______
- [ ] 20. Pruning aborts nothing; the lifecycle rule covers it. ______
- [ ] 21. No ListMultipartUploads sweep; the lifecycle rule is the backstop. ______
- [ ] 22. The drag-out download starts at the drag threshold, not on the press, and has no menu item. ______
- [ ] 23. A GIF with no local file downloads as a video does. ______
- [ ] 24. The download uses the signed GET, not the public URL. ______
- [ ] 25. The row's detail reads `Downloading` during it. ______
- [ ] 26. No Cancel button; closing the card cancels. ______
- [ ] 27. `Download failed` has no Retry button; the next drag retries. ______
- [ ] 28. A failed download's resume data is used for 14 minutes after signing (G2). ______
- [ ] 29. A download is refused unless the disk has the file's size plus 1 GB free. ______

## The eighteen gaps, to confirm or overrule

The plan filled these where the design was silent, or changed a form while keeping the behaviour; the R4 built notes
say how each stands. Write `confirm` or `overrule` and why.
- [ ] 1. `MultipartPart` lives in `MultipartXML.swift`, so the probes' build line holds it. Internal. ______
- [ ] 2. `MultipartRequests` builds no path; the app and the probes each take their own. Internal. ______
- [ ] 3. The job carries its source (`UploadJob.multipartSource`); the queue never needs the lane's location. Internal. ______
- [ ] 4. The queue logs through an injected closure. Internal. ______
- [ ] 5. `RecordingController.isEnding`, so a second `stop-recording` during the stop wait logs `did nothing`. Check: U1's
  second stop. ______
- [ ] 6. `recordingStartCancelled` is reset in `recordingCountIn`'s `didSet`. Internal. ______
- [ ] 7. The download has its own delegate (`DragDownloadDelegate`). Internal. ______
- [ ] 8. `multipartFiles` is a collaborator beside `pendingFiles`. Internal. ______
- [ ] 9. A resumed template job that must draw a new key names it with a counter of 0. Tim's template has no
  `{counter}`. ______
- [ ] 10. The preset click reaches `SelectionOutcome.resolve` as `clickInPreset: CGRect?`. Internal. ______
- [ ] 11. The card's drag view asks for the download once per press. Check: Wi-Fi off, hold the drag: one request. ______
- [ ] 12. The card's download state is `QuickAccessModel.dragDownload`; `Download failed` uses
  `exclamationmark.triangle.fill` in red, as `Upload failed` does. ______
- [ ] 13. `S3Destination`'s `httpResponse`, `failure`, `excerpt` (and `errorBody`) are internal. Internal. ______
- [ ] 14. `MultipartAbortResult` (`.aborted` for 204, `.notFound` for 404). Internal. ______
- [ ] 15. `DragFileStore.landingURL()` makes `Drag/.downloads/<uuid>`. Internal. ______
- [ ] 16. Resume data travels in the error with `signedAt` read before the first call (G2). ______
- [ ] 17. The drag-out download's form differs from the design's wording: the card's status lives on its model and is set
  directly, not pushed in `pushCardFlags`; two files the design's list does not name; the call is
  `download(key:to:expectedBytes:resumeData:progress:)`. Check: the card shows and clears `Downloading…`
  correctly. ______
- [ ] 18. `urlRecordingStartPending` makes a second `record-screen` handled before the first has taken the lock a logged
  drop. Check: U1's back-to-back step. ______

Calls the build made that neither the design nor the gaps settled (each easy to overrule):
- [ ] A. A multipart sidecar that cannot be written fails the job (the design's invariant that Complete never goes out
  unless the sidecar says so), instead of a best-effort log line. ______
- [ ] B. A kept Clop copy outdated by a later trim of the record's own file starts the upload over (`source changed`). ______
- [ ] C. A start over whose new file is under 100 MiB aborts the stored upload before its single PUT. ______
- [ ] D. A second `partsRejected` in a job restarts with no reason line of its own. ______
- [ ] E. A resume sends no `.started` until it knows its done fraction. ______
- [ ] F. Every abort of a start over or a restart is one try, not a retry loop. ______
- [ ] G. Delete's second Abort failing fails Delete (the second alert) like the first. ______
- [ ] H. Part reads retry from the same bytes held in memory, not reread. ______

## Observations
Write these into the R4 design's Probes section and built notes:
- M1's and D1's numbers, dates and the Mac, and which IAM actions turned out missing.
- What `aws s3api get-bucket-lifecycle-configuration` printed, and whether the rule was already there.
- `footprint` (current and peak) for a 300 MB and a 6 GB upload at 16 MiB parts.
- How long a 6 GB upload took, and what Wi-Fi off for 30 s and for two minutes looked like.
- Which sender names the URL commands logged for Terminal, Raycast and Keyboard Maestro.
- Anything above that failed, and each call and gap confirmed or overruled.
