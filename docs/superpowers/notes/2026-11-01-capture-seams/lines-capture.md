# CT-4 lines unlocked by TARGET and CAPSRC, and what this phase does with them

At 5c2cc33 (`capture-seams`, clean). Trimmed from `.superpowers/sdd/ct4/lines-capture.md` (scratch) to what a reader of the phase needs: each line with its place in the checklist today, its text, its mark, the other seams it names, what the tests of this phase cover (`tests-capture.md` in this folder; `T1` to `T21` are TARGET's, `C1` to `C9` CAPSRC's) and what stays. Lines are found by text: the checklists in `docs/testing/` have moved since the catalogue was made. Sources: `docs/superpowers/notes/2026-10-30-checklist-sweep/seams.md` sections 3 and 4 and its multi-seam section. Landed seams: EDITOR (CT-2); CLOP, SAVEAS, LOG (CT-3).

## Counts

| Seam | Lines | Full | In part | Deferred | Earlier mark extended or reworded | Already marked before |
|---|---|---|---|---|---|---|
| TARGET | 34 | 19 | 13 | 2 | 4 | 4 |
| CAPSRC | 34 | 4 | 8 | 22 | 1 | 1 |
| **All** | **68** | **23** | **21** | **24** | **5** | **5** |

No line carries an `(obsolete: ...)` mark and none is obsolete or wholly covered by an existing test. Two TARGET lines carry text that is partly out of date (phase-2:32 and small-tweaks:13 name a `Saved` word the row no longer shows); the tests cover what is still true. One line is ticked `[x]`: recording-r2:653 (no suite mark, none added). The earlier marks are four TARGET ones that tests extend (phase-4a:119, phase-4a:120, phase-6b:118, phase-7c:187) and one CAPSRC one that is reworded with no test (recording-r4:217).

## Table

| Key | Seam | Current line | Other seams | Current mark | This phase |
|---|---|---|---|---|---|
| coordinator-split:36 | TARGET | coordinator-split:36 | SCREENS, WORKSPACE | none | part |
| coordinator-split:42 | TARGET | coordinator-split:42 | none | none | part |
| phase-1:36 | TARGET | phase-1:38 | none | none | full |
| phase-1:39 | TARGET | phase-1:41 | FOLDER | none | deferred (`FOLDER`) |
| phase-1:45 | TARGET | phase-1:48 | none | none | full |
| phase-2:25 | TARGET | phase-2:40 | none | none | part |
| phase-2:30 | TARGET | phase-2:47 | none | none | full |
| phase-2:32 | TARGET | phase-2:51 | none | none | full |
| phase-2:33 | TARGET | phase-2:52 | UPLOADFORM | none | part |
| phase-2:48 | TARGET | phase-2:77 | none | none | part |
| phase-3:48 | TARGET | phase-3:89 | none | none | full |
| phase-3:49 | TARGET | phase-3:90 | none | none | full |
| phase-4a:119 | TARGET | phase-4a:210 | EDITOR, EDPLACE | in part | part (extends the CT-2 mark) |
| phase-4a:120 | TARGET | phase-4a:215 | EDITOR, EDPLACE | in part | part (extends the CT-2 mark) |
| phase-5:179 | TARGET | phase-5:191 | none | none | full |
| phase-5:202 | TARGET | phase-5:218 | none | none | full |
| phase-6b:66 | TARGET | phase-6b:81 | none | none | part |
| phase-6b:115 | TARGET | phase-6b:141 | none | none | full |
| phase-6b:116 | TARGET | phase-6b:142 | none | none | full |
| phase-6b:117 | TARGET | phase-6b:143 | none | none | full |
| phase-6b:118 | TARGET | phase-6b:144 | EDITOR, PINS | in part | part (extends the CT-2 mark) |
| phase-7c:117 | TARGET | phase-7c:133 | BGFILL | none | deferred (`BGFILL`) |
| phase-7c:179 | TARGET | phase-7c:233 | none | none | part |
| phase-7c:182 | TARGET | phase-7c:236 | none | none | part |
| phase-7c:184 | TARGET | phase-7c:238 | none | none | full |
| phase-7c:185 | TARGET | phase-7c:239 | none | none | full |
| phase-7c:186 | TARGET | phase-7c:240 | none | none | full |
| phase-7c:187 | TARGET | phase-7c:241 | BGPOP, EDITOR, EDPLACE | in part | part (extends the CT-2 mark) |
| phase-7c:188 | TARGET | phase-7c:244 | none | none | full |
| phase-7c:189 | TARGET | phase-7c:245 | none | none | part |
| phase-7c:190 | TARGET | phase-7c:246 | none | none | full |
| phase-7c:197 | TARGET | phase-7c:254 | none | none | full |
| small-tweaks:13 | TARGET | small-tweaks:16 | none | none | full |
| small-tweaks:16 | TARGET | small-tweaks:22 | none | none | full |
| phase-5:78 | CAPSRC | phase-5:78 | SCROLL | none | part |
| phase-5:182 | CAPSRC | phase-5:195 | SCROLL | none | deferred (`SCROLL`) |
| phase-6a:209 | CAPSRC | phase-6a:254 | none | none | full |
| phase-6a:211 | CAPSRC | phase-6a:256 | SCROLL | none | part |
| phase-6a:214 | CAPSRC | phase-6a:260 | none | none | full |
| phase-6b:62 | CAPSRC | phase-6b:77 | SELINT | none | part |
| phase-6b:75 | CAPSRC | phase-6b:91 | STAGE, STATUSMENU | none | deferred (`STAGE`) |
| phase-6b:77 | CAPSRC | phase-6b:93 | STAGE | none | deferred (`STAGE`) |
| phase-6b:79 | CAPSRC | phase-6b:95 | STAGE | none | deferred (`STAGE`) |
| phase-6b:104 | CAPSRC | phase-6b:122 | none | none | part |
| phase-6b:105 | CAPSRC | phase-6b:123 | none | none | part |
| phase-6b:127 | CAPSRC | phase-6b:162 | none | none | part |
| phase-6b:159 | CAPSRC | phase-6b:210 | SCROLL, STAGE | none | part |
| phase-6b:160 | CAPSRC | phase-6b:211 | none | none | full |
| phase-7b:81 | CAPSRC | phase-7b:87 | none | none | full |
| phase-7b:96 | CAPSRC | phase-7b:108 | COVERS | none | deferred (`COVERS`) |
| recording-r1:102 | CAPSRC | recording-r1:105 | EXTRAS, RECCHROME | none | deferred (`TMPDIRS`) |
| recording-r1:105 | CAPSRC | recording-r1:108 | none | none | deferred (`TMPDIRS`) |
| recording-r1:122 | CAPSRC | recording-r1:125 | COVERS | none | deferred (`TMPDIRS`) |
| recording-r1:124 | CAPSRC | recording-r1:129 | COVERS, EXTRAS, RECCHROME, STAGE | none | deferred (`TMPDIRS`) |
| recording-r1:196 | CAPSRC | recording-r1:207 | RECCHROME, STAGE | none | deferred (`TMPDIRS`) |
| recording-r2:231 | CAPSRC | recording-r2:241 | RECCHROME | none | deferred (`TMPDIRS`) |
| recording-r2:236 | CAPSRC | recording-r2:246 | RECCHROME | none | deferred (`TMPDIRS`) |
| recording-r2:238 | CAPSRC | recording-r2:248 | RECCHROME | none | deferred (`TMPDIRS`) |
| recording-r2:351 | CAPSRC | recording-r2:386 | RECCHROME, STATUSMENU | none | part |
| recording-r2:390 | CAPSRC | recording-r2:436 | RECCHROME | none | deferred (`TMPDIRS`) |
| recording-r2:397 | CAPSRC | recording-r2:443 | RECCHROME, STAGE | none | deferred (`TMPDIRS`) |
| recording-r2:402 | CAPSRC | recording-r2:448 | RECCHROME | none | deferred (`TMPDIRS`) |
| recording-r2:407 | CAPSRC | recording-r2:455 | RECCHROME | none | deferred (`TMPDIRS`) |
| recording-r2:409 | CAPSRC | recording-r2:457 | RECCHROME, STAGE | none | deferred (`TMPDIRS`) |
| recording-r2:605 | CAPSRC | recording-r2:669 | RECCHROME | none | deferred (`TMPDIRS`) |
| recording-r2:653 | CAPSRC | recording-r2:734 | RECCHROME | none | deferred (`TMPDIRS`) |
| recording-r3:276 | CAPSRC | recording-r3:285 | EXTRAS | none | deferred (`TMPDIRS`) |
| recording-r4:217 | CAPSRC | recording-r4:226 | LOG, TMPDIRS | suite, the rule | deferred (`TMPDIRS`) and the hand-off's `NSScreen` read |

## Lines

## TARGET

### coordinator-split:36  (TARGET)
- Current line: `docs/testing/coordinator-split-manual-checklist.md:36`
- Text: [ ] Capture Area: the file, the card and the clipboard [`+Capture`, `+Save`, `+Overlay`]. After capture `Save and copy image`. ⌃⇧4 and drag an area: the shutter plays, `Screenshot saved` posts, a PNG is in the save folder (`sips -g pixelWidth` reads the area's width times the display scale), the clipboard holds the image (Preview > File > New from Clipboard), and a card with the thumbnail and `Saved` shows at the corner. Recent Captures lists the capture, and `Reveal Last Capture` is enabled and selects the file in Finder.
- Current mark: none
- Other seams: SCREENS, WORKSPACE; landed: none; not landed: SCREENS, WORKSPACE
- This phase: part. Tests: T5.
- What stays: the card with thumbnail and `Saved` (`SCREENS`); `Reveal Last Capture` in Finder (`WORKSPACE`; `lastCaptureURL` is pinned); the ⌃⇧4 drag and the area width times the display scale (`CAPSRC`); the audible shutter (by hand for good).

### coordinator-split:42  (TARGET)
- Current line: `docs/testing/coordinator-split-manual-checklist.md:42`
- Text: [ ] Retry Failed Uploads with no destination: one notification [`+Upload`]. Settings > Upload > `Forget Credentials`; After capture `Upload only, keep no local file`. Capture twice: one `Upload not configured` notification in all (`Set up a destination in Settings > Upload, then retry from Recent Captures. The image is on the clipboard.`), not one per capture; both cards say `Upload failed`; the menu gains `Retry Failed Uploads`. Choose it: one `Upload not configured` notification, `Set up a destination in Settings > Upload, then retry.`, not one per record. Enter the credentials in Settings > Upload and Save, then choose `Retry Failed Uploads` again: both rows upload and the menu item goes.
- Current mark: none
- Other seams: none; landed: none; not landed: none
- This phase: part. Tests: T8 (`.uploadOnly`); the Retry half is already covered by CoordinatorUploadTests.retryFailedUploadsSaysOnceWithoutCredentialsAndEnqueuesWithThem.
- What stays: the cards saying `Upload failed` (`SCREENS`; the `.failed` update is pinned); the menu item (`STATUSMENU`; `failedRecords` is pinned).
- Note: The checklist says both cards say `Upload failed` with `Upload and copy URL`; the code gives upload state `.none` for that action (no failed card, no retry item). Only `Upload only, keep no local file` fails the record. T8 drives both settings.

### phase-1:36  (TARGET)
- Current line: `docs/testing/phase-1-manual-checklist.md:38`
- Text: [ ] File lands in the chosen folder with the template name; same-second captures get " 2", also after a relaunch.
- Current mark: none
- Other seams: none; landed: none; not landed: none
- This phase: full. Tests: T1.

### phase-1:39  (TARGET)
- Current line: `docs/testing/phase-1-manual-checklist.md:41`
- Text: [ ] Cancelling the folder chooser leaves the image on the clipboard and shows a "Not saved" notification.
- Current mark: none
- Other seams: FOLDER; landed: none; not landed: FOLDER
- This phase: deferred (`FOLDER`). Tests: none.
- What stays: the no-folder branch (AppCoordinator+Save.swift:244-247) is reached only through `chooseFolder`'s `NSOpenPanel` (SaveLocation.swift:30-44).

### phase-1:45  (TARGET)
- Current line: `docs/testing/phase-1-manual-checklist.md:48`
- Text: [ ] Choose… changes the folder and the next capture lands there.
- Current mark: none
- Other seams: none; landed: none; not landed: none
- This phase: full. Tests: T6.
- What stays: Choose…'s panel stands in as `saveLocation.store` (SaveLocationStoreTests pins the store).

### phase-2:25  (TARGET)
- Current line: `docs/testing/phase-2-manual-checklist.md:40`
- Text: [ ] After-capture action "Upload and copy URL": capture, wait for the overlay checkmark, paste into Slack or Notes: a working `https://snap.tky.io/XXXXXX.png` link appears, nothing else.
- Current mark: none
- Other seams: none; landed: none; not landed: none
- This phase: part. Tests: T7.
- What stays: the link pasted into Slack (the real bucket, by hand for good); the URL shape is already covered; the overlay checkmark (`SCREENS`).

### phase-2:30  (TARGET)
- Current line: `docs/testing/phase-2-manual-checklist.md:47`
- Text: [ ] With "Also copy image" on: immediately after capture, paste gives the image; after the upload finishes, paste gives the URL.
- Current mark: none
- Other seams: none; landed: none; not landed: none
- This phase: full. Tests: T2.

### phase-2:32  (TARGET)
- Current line: `docs/testing/phase-2-manual-checklist.md:51`
- Text: [ ] After-capture action "Save and copy image": no upload happens, paste gives the image, and the Recent Captures row shows the time and size with no upload state.
- Current mark: none
- Other seams: none; landed: none; not landed: none
- This phase: full. Tests: T5.
- What stays: the row text is already covered (RecentCaptureFormattingTests).
- Note: The Recent Captures row no longer shows a `Saved` word (partly obsolete text; no obsolete mark).

### phase-2:33  (TARGET)
- Current line: `docs/testing/phase-2-manual-checklist.md:52`
- Text: [ ] Delete the "TidyShot S3 credentials" item in Keychain Access, relaunch, leave the action on "Upload and copy URL", capture twice: one "Upload not configured" notification only, and paste gives the image both times. Settings > Upload then shows empty credential fields and no red keychain error.
- Current mark: none
- Other seams: UPLOADFORM; landed: none; not landed: UPLOADFORM
- This phase: part. Tests: T8 (`.upload`).
- What stays: Settings > Upload's empty fields and no keychain error (`UPLOADFORM`).

### phase-2:48  (TARGET)
- Current line: `docs/testing/phase-2-manual-checklist.md:77`
- Text: [ ] Turn Wi-Fi off, capture: the file is saved, the overlay shows "Upload failed" with Retry, a notification appears, Recent Captures shows the item as `Failed`, nothing is on the clipboard unless "Also copy image" is on.
- Current mark: none
- Other seams: none; landed: none; not landed: none
- This phase: part. Tests: T9.
- What stays: the card drawn with Retry (`SCREENS`; the `.failed` card update is pinned); Wi-Fi off for real (by hand for good; a failing destination stands in).

### phase-3:48  (TARGET)
- Current line: `docs/testing/phase-3-manual-checklist.md:89`
- Text: [ ] Forget Credentials, then capture in upload-only: one "Upload not configured" notification, the image is on the clipboard, the row is Failed and the pending file stays; re-enter credentials, Retry Failed Uploads: Uploaded.
- Current mark: none
- Other seams: none; landed: none; not landed: none
- This phase: full. Tests: T8 (`.uploadOnly`), T21 (retry leg).
- What stays: the Retry half is also covered by CoordinatorUploadTests.retryFailedUploadsSaysOnceWithoutCredentialsAndEnqueuesWithThem.

### phase-3:49  (TARGET)
- Current line: `docs/testing/phase-3-manual-checklist.md:90`
- Text: [ ] "Also copy image" on: paste gives the image until the upload finishes, then the URL.
- Current mark: none
- Other seams: none; landed: none; not landed: none
- This phase: full. Tests: T2.

### phase-4a:119  (TARGET)
- Current line: `docs/testing/phase-4a-manual-checklist.md:210`
- Text: [ ] "Upload and copy URL" with no destination (Forget Credentials in Settings > Upload): capture (the image goes to the clipboard), Annotate, Redact, ⌘S: the clipboard holds the redacted image. ⌘U posts `Upload not configured`, changes nothing, and the editor stays open. Enter the credentials again.
- Current mark: (suite, in part: CoordinatorEditorUploadTests.withNoDestinationSaveTakesTheClipboardAndUploadIsRefused, EditorUploadPlanTests.uploadOutcomeClosesWhenEnqueued; by hand: the editor staying open (`EDPLACE`); the capture's own clipboard copy and owner are set up as `AppCoordinator+Save.swift:32-34` and `:57-67` leave them with no destination, and no test drives that step today (`TARGET`))
- Other seams: EDITOR, EDPLACE; landed: EDITOR; not landed: EDPLACE
- This phase: part (extends the CT-2 mark). Tests: T8 (`.upload`).
- What stays: the editor staying open (`EDPLACE`).

### phase-4a:120  (TARGET)
- Current line: `docs/testing/phase-4a-manual-checklist.md:215`
- Text: [ ] "Upload and copy URL" with "Also copy image" on: capture, Annotate, Redact, ⌘U. The editor closes at once; when the upload finishes the clipboard holds the URL.
- Current mark: (suite, in part: CoordinatorEditorUploadTests.anUploadAfterTheCapturesOwnClosesAtOnceAndEndsWithTheLinkCopied; by hand: the editor closing (`EDPLACE`); the capture's own clipboard copy and owner are set up as `AppCoordinator+Save.swift:30-31` and `:57-67` leave them, and no test drives that step today (`TARGET`))
- Other seams: EDITOR, EDPLACE; landed: EDITOR; not landed: EDPLACE
- This phase: part (extends the CT-2 mark). Tests: T2.
- What stays: the editor closing (`EDPLACE`).

### phase-5:179  (TARGET)
- Current line: `docs/testing/phase-5-manual-checklist.md:191`
- Text: [ ] "Upload only, keep no local file": nothing appears in the save folder, the upload finishes, the URL is on the clipboard and the temporary file is deleted. With Wi-Fi off, the upload fails and `pending/<UUID>.png` keeps the tall PNG until Retry Failed Uploads succeeds.
- Current mark: none
- Other seams: none; landed: none; not landed: none
- This phase: full. Tests: T10, T21.
- What stays: Wi-Fi off for real (by hand for good; a failing destination stands in).

### phase-5:202  (TARGET)
- Current line: `docs/testing/phase-5-manual-checklist.md:218`
- Text: [ ] `history.json` has the full `pixelWidth` and `pixelHeight` for each stitched row, and the row's subtitle shows the full size.
- Current mark: none
- Other seams: none; landed: none; not landed: none
- This phase: full. Tests: T12.
- What stays: the row subtitle is already covered.

### phase-6b:66  (TARGET)
- Current line: `docs/testing/phase-6b-manual-checklist.md:81`
- Text: [ ] All-in-One captures behave like any other in upload-only mode, in the Quick Access stack and in Recent Captures.
- Current mark: none
- Other seams: none; landed: none; not landed: none
- This phase: part. Tests: T10.
- What stays: the Quick Access stack (`SCREENS`); that All-in-One builds those origins (`CAPSRC`).

### phase-6b:115  (TARGET)
- Current line: `docs/testing/phase-6b-manual-checklist.md:141`
- Text: [ ] `action=upload` with General set to `Save and copy image`: saved, uploaded, URL on the clipboard. With `Upload only, keep no local file`: uploaded with no file in the save folder.
- Current mark: none
- Other seams: none; landed: none; not landed: none
- This phase: full. Tests: T11.

### phase-6b:116  (TARGET)
- Current line: `docs/testing/phase-6b-manual-checklist.md:142`
- Text: [ ] `action=save` under `Upload only`: saved in the save folder, the image copied (with General's copy toggle on), no upload.
- Current mark: none
- Other seams: none; landed: none; not landed: none
- This phase: full. Tests: T5 (second argument).

### phase-6b:117  (TARGET)
- Current line: `docs/testing/phase-6b-manual-checklist.md:143`
- Text: [ ] `action=copy`: the image is on the clipboard (Preview > New from Clipboard), and nothing else: no file in the save folder or `pending`, no card, no Recent Captures row, no upload; the shutter sound plays (with Play sound on); `Image copied` shows the pixel size with the subtitle `From <sender>`. With Show notification off, no notification. The newest card's Annotate still opens its own capture.
- Current mark: none
- Other seams: none; landed: none; not landed: none
- This phase: full. Tests: T4.
- What stays: the sound heard (by hand for good); "the newest card's Annotate still opens its own capture" is `latestCapture` kept, pinned.

### phase-6b:118  (TARGET)
- Current line: `docs/testing/phase-6b-manual-checklist.md:144`
- Text: [ ] `action=annotate`: the after-capture action runs, then the editor opens on the new capture and its card closes. `action=pin`: the action runs, then a pin opens and the card stays.
- Current mark: (suite, in part: CoordinatorEditorUploadTests.annotateTheNewestCardSaveThenUploadWritesTheFileThenUploadsAndCopiesTheURL, CaptureIntentTests.annotateRunsTheAfterCaptureActionThenOpensTheEditor, .pinRunsTheAfterCaptureActionThenPins; by hand: reaching `save(_:intent:)` (`TARGET`) and the `action=pin` half (`PINS`); the test pins the editor opening on the new capture and its card closing)
- Other seams: EDITOR, PINS; landed: EDITOR; not landed: PINS
- This phase: part (extends the CT-2 mark). Tests: T13.
- What stays: the `action=pin` half (`PINS`).

### phase-7c:117  (TARGET)
- Current line: `docs/testing/phase-7c-manual-checklist.md:133`
- Text: [ ] A window capture with the setting on and Custom Image, then a window capture after choosing another image: each uses the image current at that moment.
- Current mark: none
- Other seams: BGFILL; landed: none; not landed: BGFILL
- This phase: deferred (`BGFILL`). Tests: none.
- What stays: the custom image is `CustomBackgroundStore.shared` (BackgroundFillSource.swift:13).

### phase-7c:179  (TARGET)
- Current line: `docs/testing/phase-7c-manual-checklist.md:233`
- Text: [ ] Capture Window (⌃⇧2) on a normal window: the saved file, the card's thumbnail, the clipboard image and the upload all show the window on the Ocean background. `sips` reads the file at the window's size plus 2 x 96 px on each axis.
- Current mark: none
- Other seams: none; landed: none; not landed: none
- This phase: part. Tests: T3.
- What stays: the card's thumbnail on screen (`SCREENS`); `sips` is the test's decode.

### phase-7c:182  (TARGET)
- Current line: `docs/testing/phase-7c-manual-checklist.md:236`
- Text: [ ] Not included: Capture Area (⌃⇧4), Capture Fullscreen (⌃⇧3), Capture Previous Area (⌃⇧6) and a scrolling capture have no background, with the setting on. A window picked in All-in-One by a drag (an area) has none either.
- Current mark: none
- Other seams: none; landed: none; not landed: none
- This phase: part. Tests: T14.
- What stays: which origin each entry builds (`CAPSRC`; scrolling's `SCROLL`); the save rule is pinned.

### phase-7c:184  (TARGET)
- Current line: `docs/testing/phase-7c-manual-checklist.md:238`
- Text: [ ] Padding 0, 160, Corner Radius 0, 40, Shadow off, and each Aspect Ratio on a window capture: the sizes follow the arithmetic above.
- Current mark: none
- Other seams: none; landed: none; not landed: none
- This phase: full. Tests: T15.

### phase-7c:185  (TARGET)
- Current line: `docs/testing/phase-7c-manual-checklist.md:239`
- Text: [ ] A portrait window (narrower than tall) with 16:9: the canvas is portrait (inverted ratio).
- Current mark: none
- Other seams: none; landed: none; not landed: none
- This phase: full. Tests: T15 (portrait case).

### phase-7c:186  (TARGET)
- Current line: `docs/testing/phase-7c-manual-checklist.md:240`
- Text: [ ] The setting off: a window capture is the plain window again, at once (no relaunch).
- Current mark: none
- Other seams: none; landed: none; not landed: none
- This phase: full. Tests: T16.

### phase-7c:187  (TARGET)
- Current line: `docs/testing/phase-7c-manual-checklist.md:241`
- Text: [ ] Open the window capture in the editor (the card's Annotate): it opens as the composed image with the background baked in, and the popover's switch is off.
- Current mark: (suite, in part: CoordinatorEditorTests.aComposedWindowCaptureOpensFlatWithNoBackground; by hand: producing the window capture (`TARGET`), and the popover's switch as its binding shows it (`BGPOP`) and drawn in the window (`EDPLACE`))
- Other seams: BGPOP, EDITOR, EDPLACE; landed: EDITOR; not landed: BGPOP, EDPLACE
- This phase: part (extends the CT-2 mark). Tests: T17.
- What stays: the popover's switch as its binding shows it (`BGPOP`), drawn in the window (`EDPLACE`).

### phase-7c:188  (TARGET)
- Current line: `docs/testing/phase-7c-manual-checklist.md:244`
- Text: [ ] `action=copy`: `t 'capture-window?action=copy'`, click a window: the clipboard image is the window on the background, with no file, no card and no history row. `t 'capture-window?action=upload'` uploads the composed image. Paste to check.
- Current mark: none
- Other seams: none; landed: none; not landed: none
- This phase: full. Tests: T18.
- What stays: URL parsing is already covered; the window click is the user's selection, as the line's own `t` call is.

### phase-7c:189  (TARGET)
- Current line: `docs/testing/phase-7c-manual-checklist.md:245`
- Text: [ ] A window larger than the limit cannot be made, so `Background: the window is too large for a background, keeping the window capture` and `Background: no bitmap could be made, keeping the window capture` have no practical way to force. They are checked by code reading: `withWindowBackground` logs one of the two and returns the plain result, with no notification. Write down any other way you used.
- Current mark: none
- Other seams: none; landed: none; not landed: none
- This phase: part. Tests: T19.
- What stays: `no bitmap could be made`: no input forces `compose` to fail while the layout fits; by code reading, as the line says.

### phase-7c:190  (TARGET)
- Current line: `docs/testing/phase-7c-manual-checklist.md:246`
- Text: [ ] Two window captures in quick succession (the second before the first's card shows): both get the background, and the saved files do not mix.
- Current mark: none
- Other seams: none; landed: none; not landed: none
- This phase: full. Tests: T20.

### phase-7c:197  (TARGET)
- Current line: `docs/testing/phase-7c-manual-checklist.md:254`
- Text: [ ] With the setting off and the editor's background off, a window capture, an area capture and an edit's Save are as before: the same sizes, no padding.
- Current mark: none
- Other seams: none; landed: none; not landed: none
- This phase: full. Tests: T16 (the edit half is EditorBackgroundExportTests.noBackgroundExportsTheCaptureAsBefore).

### small-tweaks:13  (TARGET)
- Current line: `docs/testing/small-tweaks-manual-checklist.md:16`
- Text: [ ] A screenshot row reads `<time> · <size>`, for example `2 minutes ago · 412 KB`. The middle dot has a space either side. The size matches Finder's for the file, or the uploaded object's size.
- Current mark: none
- Other seams: none; landed: none; not landed: none
- This phase: full. Tests: T5.
- What stays: Finder on screen (by hand for good); the unit rule is already covered.
- Note: The `Saved` word is gone from the row (partly obsolete text; no obsolete mark).

### small-tweaks:16  (TARGET)
- Current line: `docs/testing/small-tweaks-manual-checklist.md:22`
- Text: [ ] An upload-only capture shows a size before and after its upload.
- Current mark: none
- Other seams: none; landed: none; not landed: none
- This phase: full. Tests: T10, T21.

## CAPSRC

### phase-5:78  (CAPSRC)
- Current line: `docs/testing/phase-5-manual-checklist.md:78`
- Text: [ ] Drag an area 400 pt wide and 60 pt tall: no session starts and a notification titled `Scrolling capture` says `Select an area at least 100 points tall.` The next ⌃⇧5 works. An area exactly 100 pt tall is accepted.
- Current mark: none
- Other seams: SCROLL; landed: none; not landed: SCROLL
- This phase: part. Tests: C6, C7.
- What stays: the session starting on an accepted 100 pt area (`SCROLL`); the drag in the overlay (by hand for good).

### phase-5:182  (CAPSRC)
- Current line: `docs/testing/phase-5-manual-checklist.md:195`
- Text: [ ] Nothing is written or uploaded before Done: during a session, the save folder, `history.json` and the bucket do not change, in all three actions.
- Current mark: none
- Other seams: SCROLL; landed: none; not landed: SCROLL
- This phase: deferred (`SCROLL`). Tests: none.
- What stays: the held session outcome (AppCoordinator+Capture.swift:128-139).

### phase-6a:209  (CAPSRC)
- Current line: `docs/testing/phase-6a-manual-checklist.md:254`
- Text: [ ] With no stored area (`defaults delete io.tky.tidyshot lastAreaRect`, then quit and reopen TidyShot) ⌃⇧6 posts `Capture an area first.` titled `No previous area`, and nothing is captured.
- Current mark: none
- Other seams: none; landed: none; not landed: none
- This phase: full. Tests: C1.

### phase-6a:211  (CAPSRC)
- Current line: `docs/testing/phase-6a-manual-checklist.md:256`
- Text: [ ] The rect survives a relaunch. A window capture and a fullscreen capture do not change it. A Capture Scrolling area (at least 100 pt tall, window or drag) replaces it; a refused scrolling area (under 100 pt) does not.
- Current mark: none
- Other seams: SCROLL; landed: none; not landed: SCROLL
- This phase: part. Tests: C7, C6.
- What stays: a scrolling session on the accepted area (`SCROLL`); a window click becoming the scrolling area is the overlay's own (`SELINT`); the relaunch is already covered.

### phase-6a:214  (CAPSRC)
- Current line: `docs/testing/phase-6a-manual-checklist.md:260`
- Text: [ ] An area that leaves less than 1 point on its display is reported as not on a connected display, not captured at zero size: with TidyShot quit, `defaults write io.tky.tidyshot lastAreaRect -data "$(printf '{"x":-0.4,"y":100,"width":1.2,"height":200}' | xxd -p | tr -d '\n')"` (a strip whose centre is on the main display's left edge, with 0.8 pt of it on the display; this needs the main display's left edge at x 0), reopen and press ⌃⇧6: `The previous area is not on a connected display.` titled `No previous area`, and no capture. Then `defaults delete io.tky.tidyshot lastAreaRect` again.
- Current mark: none
- Other seams: none; landed: none; not landed: none
- This phase: full. Tests: C1.

### phase-6b:62  (CAPSRC)
- Current line: `docs/testing/phase-6b-manual-checklist.md:77`
- Text: [ ] A stored area on a connected display: ⌃⇧1 opens with it selected and adjustable. Store an area on the second display, unplug it, press ⌃⇧1: it opens with no rect.
- Current mark: none
- Other seams: SELINT; landed: none; not landed: SELINT
- This phase: part. Tests: C2.
- What stays: selected and adjustable, and no rect when its display is gone (`placePreselected`, `SELINT`); the restore rule is already covered.
- Note: The second sentence (store an area on the second display, unplug it) is not reached by the coordinator: `captureAllInOne` passes the stored rect whatever the displays are (AppCoordinator+Capture.swift:38) and the overlay drops it. It stays `SELINT`'s.

### phase-6b:75  (CAPSRC)
- Current line: `docs/testing/phase-6b-manual-checklist.md:91`
- Text: [ ] While the countdown runs, ⌃⇧4, the Self-Timer shortcut and the other shortcuts do nothing and the menu's capture items are disabled; the countdown is not disturbed.
- Current mark: none
- Other seams: STAGE, STATUSMENU; landed: none; not landed: STAGE, STATUSMENU
- This phase: deferred (`STAGE`). Tests: none.
- What stays: `runSelfTimer` (AppCoordinator+Capture.swift:297-307) needs `SelfTimerScreenStage`; the menu's disabled items are `STATUSMENU`.

### phase-6b:77  (CAPSRC)
- Current line: `docs/testing/phase-6b-manual-checklist.md:93`
- Text: [ ] `3 seconds` and `10 seconds` in Settings > Capture count from 3 and 10. All-in-One's Timer button uses the same setting, and its tooltip follows it.
- Current mark: none
- Other seams: STAGE; landed: none; not landed: STAGE
- This phase: deferred (`STAGE`). Tests: none.
- What stays: `selfTimer.run(seconds:stage:)` (AppCoordinator+Capture.swift:304) is behind the same stage; the tooltip is already covered.

### phase-6b:79  (CAPSRC)
- Current line: `docs/testing/phase-6b-manual-checklist.md:95`
- Text: [ ] A self-timer area becomes the previous area (⌃⇧6 captures it again); a window does not.
- Current mark: none
- Other seams: STAGE; landed: none; not landed: STAGE
- This phase: deferred (`STAGE`). Tests: none.
- What stays: the store at AppCoordinator+Capture.swift:190 is followed by `runSelfTimer` with no stop.

### phase-6b:104  (CAPSRC)
- Current line: `docs/testing/phase-6b-manual-checklist.md:122`
- Text: [ ] `t all-in-one`: All-in-One with the last area preselected. `t 'all-in-one?x=0&y=0&width=500&height=400'`: All-in-One with that rect preselected at the bottom-left of the display under the pointer, adjustable; Escape leaves the stored previous area unchanged.
- Current mark: none
- Other seams: none; landed: none; not landed: none
- This phase: part. Tests: C2.
- What stays: the rect shown adjustable (`placePreselected`, `SELINT`); the rect's geometry is already covered.

### phase-6b:105  (CAPSRC)
- Current line: `docs/testing/phase-6b-manual-checklist.md:123`
- Text: [ ] A URL-opened All-in-One needs a touch before a key captures: run `sleep 3; open 'tidyshot://all-in-one?action=copy&x=0&y=0&width=500&height=400'` in Terminal and keep pressing Return in a TextEdit window as the overlay appears: nothing is captured (no shutter, the clipboard unchanged), the arrows still move the rect and Escape still cancels. Again, then click once inside the rect (or change W, or toggle the lock): Return now captures. A double-click inside the rect as the first touch arms without capturing; a second double-click captures. The same with `t all-in-one` (no rect, previous area preselected). ⌃⇧1 and the menu's All-in-One on the previous area capture on Return at once, as before.
- Current mark: none
- Other seams: none; landed: none; not landed: none
- This phase: part. Tests: C2 (C9 if Tim takes it).
- What stays: Return typed in another app as the overlay appears (by hand for good); arming by a width change or the lock toggle is C9, if taken.

### phase-6b:127  (CAPSRC)
- Current line: `docs/testing/phase-6b-manual-checklist.md:162`
- Text: [ ] A `capture-area` URL rect becomes the previous area: ⌃⇧6 captures it again. A `capture-scrolling` rect becomes it only once the stitched image is saved (see URL scheme: commands).
- Current mark: none
- Other seams: none; landed: none; not landed: none
- This phase: part. Tests: C7.
- What stays: the `capture-scrolling` half, stored only once the stitched image is saved (`SCROLL`).

### phase-6b:159  (CAPSRC)
- Current line: `docs/testing/phase-6b-manual-checklist.md:210`
- Text: [ ] While a selection is open (⌃⇧4, not released), while a self-timer counts, and during a scrolling session before and after Start: `t capture-fullscreen`, `t capture-area` and `t capture-scrolling` do nothing and post nothing (the log reads `dropped, a capture is running`); the scrolling session neither starts nor finishes. `t restore-recently-closed` still restores a card.
- Current mark: none
- Other seams: SCROLL, STAGE; landed: none; not landed: SCROLL, STAGE
- This phase: part. Tests: C3.
- What stays: a self-timer counting (`STAGE`); a scrolling session before and after Start (`SCROLL`); the log text is already covered.

### phase-6b:160  (CAPSRC)
- Current line: `docs/testing/phase-6b-manual-checklist.md:211`
- Text: [ ] `for i in 1 2 3; do t capture-window; done`: one window selection opens; the other two are dropped.
- Current mark: none
- Other seams: none; landed: none; not landed: none
- This phase: full. Tests: C3.

### phase-7b:81  (CAPSRC)
- Current line: `docs/testing/phase-7b-manual-checklist.md:87`
- Text: [ ] ⌃⇧6 after a Capture Text captures the previous image area, not the text selection.
- Current mark: none
- Other seams: none; landed: none; not landed: none
- This phase: full. Tests: C4.

### phase-7b:96  (CAPSRC)
- Current line: `docs/testing/phase-7b-manual-checklist.md:108`
- Text: [ ] Not covered: Capture Scrolling (⌃⇧5) and Capture Text (⌃⇧7) leave the icons showing.
- Current mark: none
- Other seams: COVERS; landed: none; not landed: COVERS
- This phase: deferred (`COVERS`). Tests: none.
- What stays: a covers fake is needed to see that no `show(for: .capture)` happens.

### recording-r1:102  (CAPSRC)
- Current line: `docs/testing/recording-r1-manual-checklist.md:105`
- Text: [ ] Stop each way, one recording each, whichever way it was started: the panel's Stop, ⌃⇧8, Record Fullscreen's shortcut (set one in Settings > Shortcuts first; the reset loop clears it), and `Stop Recording` in the menu. Each ends the recording once, plays the shutter, and saves one file and one card.
- Current mark: none
- Other seams: EXTRAS, RECCHROME; landed: none; not landed: EXTRAS, RECCHROME
- This phase: deferred (`TMPDIRS`). Tests: none.
- What stays: after `TMPDIRS`: `EXTRAS`, `RECCHROME`, `STAGE`.

### recording-r1:105  (CAPSRC)
- Current line: `docs/testing/recording-r1-manual-checklist.md:108`
- Text: [ ] An area smaller than 32 x 32 pt posts `Select a larger area to record.` (titled `Screen recording`) and records nothing. An area recording does not become the Previous Area: ⌃⇧6 still uses the earlier image capture's rect.
- Current mark: none
- Other seams: none; landed: none; not landed: none
- This phase: deferred (`TMPDIRS`). Tests: none.
- What stays: `TMPDIRS` with CAPSRC finishes this line; nothing else is needed.
- Note: seams.md lists this line with no other seam; both halves come after `recordingCanStart` (the container's real `tmp/Recording`), so it is `TMPDIRS` first.

### recording-r1:122  (CAPSRC)
- Current line: `docs/testing/recording-r1-manual-checklist.md:125`
- Text: [ ] A window recording with Hide desktop icons while capturing on and the persistent `Hide Desktop Icons` menu item off: the covers go as soon as the selection returns the window, and the bare desktop takes clicks during the recording (the window is the only thing in the picture, so the covers would add nothing).
- Current mark: none
- Other seams: COVERS; landed: none; not landed: COVERS
- This phase: deferred (`TMPDIRS`). Tests: none.
- What stays: after `TMPDIRS`: `COVERS`, `RECCHROME`.

### recording-r1:124  (CAPSRC)
- Current line: `docs/testing/recording-r1-manual-checklist.md:129`
- Text: [ ] The covers are gone after Stop, after Cancel and after a cancelled count-in, with the persistent item off.
- Current mark: none
- Other seams: COVERS, EXTRAS, RECCHROME, STAGE; landed: none; not landed: COVERS, EXTRAS, RECCHROME, STAGE
- This phase: deferred (`TMPDIRS`). Tests: none.
- What stays: after `TMPDIRS`: `COVERS`, `EXTRAS`, `RECCHROME`, `STAGE`.

### recording-r1:196  (CAPSRC)
- Current line: `docs/testing/recording-r1-manual-checklist.md:207`
- Text: [ ] Closing the window during the count-in, and moving it: closing it before the fresh content read posts `Screen recording` / `The window is no longer on screen.` and records nothing, with the lock and covers released. Moving it during the count-in records it at its new place (the size comes from its fresh frame). Write down what happened: ______
- Current mark: none
- Other seams: RECCHROME, STAGE; landed: none; not landed: RECCHROME, STAGE
- This phase: deferred (`TMPDIRS`). Tests: none.
- What stays: after `TMPDIRS`: `STAGE` for a count-in (or count-in off with the world clock held), `RECCHROME` for the moved window's request.

### recording-r2:231  (CAPSRC)
- Current line: `docs/testing/recording-r2-manual-checklist.md:241`
- Text: [ ] Two GIF recordings converting at once. Record two 30 s GIFs back to back (Stop the second as soon as the first is converting). The menu shows `Making 2 GIFs… <n> %` and `Stop Making GIFs`, with `n` weighted by frame count. Press `Stop Making GIFs` while both run: each recording is saved as an MP4 with its own `GIF not made` notification (`Stopped. The recording was saved as an MP4.`), two records appear, and `tmp/Recording` has no `.gif` left.
- Current mark: none
- Other seams: RECCHROME; landed: none; not landed: RECCHROME
- This phase: deferred (`TMPDIRS`). Tests: none.
- What stays: after `TMPDIRS`: `RECCHROME`; `EXTRAS` unless the target is a window; `STAGE` unless the count-in is off.

### recording-r2:236  (CAPSRC)
- Current line: `docs/testing/recording-r2-manual-checklist.md:246`
- Text: [ ] `Stop Making GIF` with one conversion does the same for that recording. Pressing it after the menu shows `99 %` (the GIF is written and being saved) does nothing: the GIF is saved.
- Current mark: none
- Other seams: RECCHROME; landed: none; not landed: RECCHROME
- This phase: deferred (`TMPDIRS`). Tests: none.
- What stays: after `TMPDIRS`: `RECCHROME`; `EXTRAS` unless the target is a window; `STAGE` unless the count-in is off.

### recording-r2:238  (CAPSRC)
- Current line: `docs/testing/recording-r2-manual-checklist.md:248`
- Text: [ ] Quit during a conversion. Start a 60 s GIF's conversion and quit from the menu: TidyShot quits without waiting for the conversion, the recording is in the save folder (or `pending`) as an MP4 with a record, no notification posts, and no `.gif` is left in `tmp/Recording`.
- Current mark: none
- Other seams: RECCHROME; landed: none; not landed: RECCHROME
- This phase: deferred (`TMPDIRS`). Tests: none.
- What stays: after `TMPDIRS`: `RECCHROME`; `EXTRAS` unless the target is a window; `STAGE` unless the count-in is off.

### recording-r2:351  (CAPSRC)
- Current line: `docs/testing/recording-r2-manual-checklist.md:386`
- Text: [ ] With the prompt up: a second Record press does nothing and logs `Recording: start ignored, the microphone prompt is open`; Quit quits without starting a recording. Captures are blocked while it is up (call I, settled: the design's Decided 2026-10-24, 9): each capture shortcut (⌃⇧1 to ⌃⇧7, and the self-timer's if one is set) does nothing, no selection overlay or countdown shows, and no capture appears; the status menu's capture items, Record Screen and Record Fullscreen among them, are shown disabled; `open "tidyshot://capture-area"` (URL commands on) does nothing, and the log has `URL command from … dropped, the microphone prompt is open: tidyshot://capture-area` (not `a capture is running`). Answer the prompt: the recording starts as usual (the selection overlay or the count-in), and every capture works again once it ends. Write down anything that did start: ______
- Current mark: none
- Other seams: RECCHROME, STATUSMENU; landed: none; not landed: RECCHROME, STATUSMENU
- This phase: part. Tests: C8.
- What stays: the status menu's capture items shown disabled (`STATUSMENU`); the recording that starts after the answer (`TMPDIRS`, `RECCHROME`); the URL command's dropped line text is already covered.
- Note: The design judge deferred this line (`STATUSMENU`, `TMPDIRS`, `RECCHROME`); this catalogue makes it part, because the "captures are blocked while the prompt is up" clause is observable with the fake source and selector.

### recording-r2:390  (CAPSRC)
- Current line: `docs/testing/recording-r2-manual-checklist.md:436`
- Text: [ ] A GIF save that ends during a second recording, with Show notification on. Record a GIF of 30 s or more and Stop; while `Making GIF…` shows, switch `Format` to MP4 and start Record Fullscreen with `Record system audio` on, and keep it running until the menu's GIF items are gone (the GIF is saved). No banner shows while it records. Stop: the GIF's `Recording saved` (or `GIF not made`) posts at once, then the second recording's own notices after its save. The log has `Recording: posted 1 notification held during the recording` (`posted <n> notifications` for more). Play the second recording: no banner is in its picture, and no notification sound in its audio. Write down the order the banners came in: ______
- Current mark: none
- Other seams: RECCHROME; landed: none; not landed: RECCHROME
- This phase: deferred (`TMPDIRS`). Tests: none.
- What stays: after `TMPDIRS`: `RECCHROME`; `EXTRAS` unless the target is a window; `STAGE` unless the count-in is off.

### recording-r2:397  (CAPSRC)
- Current line: `docs/testing/recording-r2-manual-checklist.md:443`
- Text: [ ] The same with the GIF saved during the second recording's count-in (`Count down before recording` on): start the second recording when `Making GIF…` nears 100 %. No banner shows during the count-in or the recording, the GIF's notice posts at Stop, and the recording's first seconds have no banner in their picture and no notification sound. Again with the count-in cancelled (the record shortcut during it): the held notice posts as it is cancelled, and the log has the `posted` line.
- Current mark: none
- Other seams: RECCHROME, STAGE; landed: none; not landed: RECCHROME, STAGE
- This phase: deferred (`TMPDIRS`). Tests: none.
- What stays: as the other recording-r2 lines, and `STAGE`: the count-in is the scenario.

### recording-r2:402  (CAPSRC)
- Current line: `docs/testing/recording-r2-manual-checklist.md:448`
- Text: [ ] The same with an upload that finishes during a recording: an MP4 recording with `Upload and copy URL`, then a second recording started while its card says `Uploading`. `Uploaded, URL copied` posts after the second recording's Stop, not during it.
- Current mark: none
- Other seams: RECCHROME; landed: none; not landed: RECCHROME
- This phase: deferred (`TMPDIRS`). Tests: none.
- What stays: after `TMPDIRS`: `RECCHROME`; `EXTRAS` unless the target is a window; `STAGE` unless the count-in is off.

### recording-r2:407  (CAPSRC)
- Current line: `docs/testing/recording-r2-manual-checklist.md:455`
- Text: [ ] Quit during the second recording of the first check: the held GIF notice posts as the recording ends, before TidyShot quits, and the second recording's own notices do not (quit mode).
- Current mark: none
- Other seams: RECCHROME; landed: none; not landed: RECCHROME
- This phase: deferred (`TMPDIRS`). Tests: none.
- What stays: after `TMPDIRS`: `RECCHROME`; `EXTRAS` unless the target is a window; `STAGE` unless the count-in is off.

### recording-r2:409  (CAPSRC)
- Current line: `docs/testing/recording-r2-manual-checklist.md:457`
- Text: [ ] A quick quit, where nothing else holds the quit. Start the second recording while the first's GIF converts, timed as in the count-in check so the GIF is saved during the count-in, then quit within 0.5 s of the recording's start (or during the count-in). The recording is too short to keep, so the quit waits on no save and TidyShot quits at once, yet the GIF's `Recording saved` still posts (look in Notification Centre if its banner has gone), and the log has the `posted` line. A quit that comes while the GIF still converts stops it and saves the MP4 in quit mode, with no notice: try again. Write down whether it posted: ______
- Current mark: none
- Other seams: RECCHROME, STAGE; landed: none; not landed: RECCHROME, STAGE
- This phase: deferred (`TMPDIRS`). Tests: none.
- What stays: as the other recording-r2 lines, and `STAGE`: the count-in is the scenario.

### recording-r2:605  (CAPSRC)
- Current line: `docs/testing/recording-r2-manual-checklist.md:669`
- Text: [ ] 1. Settings are read at the start: the hand-off reads the format, `GIF frame rate` and `GIF size`, so changing them in Settings during a recording or its conversion does not reach it. Check: start a GIF recording, switch `Format` to MP4 in Settings while it runs, Stop: it is still a GIF. ______
- Current mark: none
- Other seams: RECCHROME; landed: none; not landed: RECCHROME
- This phase: deferred (`TMPDIRS`). Tests: none.
- What stays: after `TMPDIRS`: `RECCHROME`; `EXTRAS` unless the target is a window; `STAGE` unless the count-in is off.

### recording-r2:653  (CAPSRC)
- Current line: `docs/testing/recording-r2-manual-checklist.md:734`
- Text: [x] E. A post-Stop notice during a later recording: every notification waits while a recording counts in or runs and posts after its Stop. Built (Notices during a recording, above). (Tim, 2026-10-24)
- Current mark: none
- Other seams: RECCHROME; landed: none; not landed: RECCHROME
- This phase: deferred (`TMPDIRS`). Tests: none.
- What stays: after `TMPDIRS`: `RECCHROME`; `EXTRAS` unless the target is a window; `STAGE` unless the count-in is off.
- Note: Ticked `[x]` and stays ticked; no mark change.

### recording-r3:276  (CAPSRC)
- Current line: `docs/testing/recording-r3-manual-checklist.md:285`
- Text: [ ] A failed content read: not forceable by hand; the code path is the `defer` that every exit shares. Skip and write `skipped`: ______
- Current mark: none
- Other seams: EXTRAS; landed: none; not landed: EXTRAS
- This phase: deferred (`TMPDIRS`). Tests: none.
- What stays: after `TMPDIRS`: `EXTRAS` (the `defer { extras?.close() }`), unless the target is a window; CAPSRC supplies the failing second read.

### recording-r4:217  (CAPSRC)
- Current line: `docs/testing/recording-r4-manual-checklist.md:226`
- Text: [ ] The record shortcut during the settle delay with `Count down before recording` off records nothing and logs `Recording: not started, the count-in was cancelled`.
- Current mark: (suite, the rule: CoordinatorRecordingTests.recordingProceedsOnlyWhenStartedNotQuittingAndNotCancelled; by hand: the log line, in private record() past the capture lock (`TMPDIRS`, `CAPSRC`))
- Other seams: LOG, TMPDIRS; landed: LOG; not landed: TMPDIRS
- This phase: deferred (`TMPDIRS`) and the hand-off's `NSScreen` read. Tests: none.
- What stays: the log line, in private `record()` past the capture lock: `TMPDIRS`, and the hand-off's `NSScreen.screens` read (AppCoordinator+Recording.swift:496).
- Note: The CT-1 and CT-3 mark is reworded: the earlier notes said `TMPDIRS` and `CAPSRC` finish it; they do not.
