# CT-2 editor-seam lines (73)

The 73 manual checklist lines that no test could drive until the annotation editor's window was behind a seam (seams.md, `docs/superpowers/notes/2026-10-30-checklist-sweep/seams.md` lines 61-144 and 829-870), with what this phase tests of each. The key is the catalogue key (checklist file stem and the line number at e011d2f); the current line is the line in `docs/testing/<stem>-manual-checklist.md` at a079a6f. The tests are in `tests-editor.md` in this folder.

Counts: full 25, part 40, deferred 8 (seven to `EDPLACE`, phase-4a:107 to `EDPLACE` and `BEEP`); obsolete or already covered 0. Seams: 65 lines need `EDITOR` alone, 13 of them moved from A by tests-A because they were read off a constructed `EditorWindowController`; 8 also need another seam (`coordinator-split:44` `PINS`, `SCREENS`, `SAVEAS`; `phase-4a:155` `CLOSESHEET`; `phase-4c:201` `EDDEFAULTS`; `phase-6a:131` `QASTACK`; `phase-6a:198` `SAVEAS`; `phase-6b:118` `TARGET`, `PINS`; `phase-7c:172` `EDSAVEAS`; `phase-7c:187` `TARGET`). None carried a mark or was checked at a079a6f. The "Seams" bullets below are seams.md's as it stands; what a part line leaves can also name `EDPLACE`, `EDSAVEAS`, `CLOSESHEET`, `BEEP`, `SAVEAS`, `SCREENS`, `BGPOP` or `APPDELEGATE` for a line seams.md lists under `EDITOR` alone, and the design's section 11 gives the seams.md change that records it. Of those, `phase-4a:119` and `:120` also name `TARGET` for the capture-time clipboard copy their tests set up and no test drives, and join its row at close-out (design 6 and 11); the full lines whose Stays name `TARGET` the same way (`phase-4a:52`, `:115` to `:118`) do not, since there it is the test's precondition, not a check the line makes. "Stays" names a test stand-in as such ("Quick Look is the decode"); "by hand" is kept for the real bucket, the drawn UI and the real quit and relaunch.

`EDPLACE` is the next seam: the editor window's screen read (EditorWindowController.swift:123) and its NSWorkspace observer (:103) behind `EditorWindowPlacement`, designed and built in `edplace-design.md` sections 2.1, 4 and 8 (committed beside this note; design call 10). Of the 13 moved lines, five get part cover now through the coordinator's pushes and copy (phase-4a:37, :145, :146, :162, phase-7c:169) and eight wait for `EDPLACE`. "Stays" names what a test here does not reach, and whose it is.

## Overview

| Key | Current line | Seams | This phase |
|---|---|---|---|
| `coordinator-split:43` | 43 | EDITOR | part |
| `coordinator-split:44` | 44 | EDITOR, also SAVEAS, SCREENS, PINS | part |
| `phase-4a:37` | 39 | EDITOR (moved from A) | part |
| `phase-4a:39` | 43 | EDITOR | part |
| `phase-4a:49` | 59 | EDITOR | full |
| `phase-4a:52` | 65 | EDITOR | full |
| `phase-4a:56` | 70 | EDITOR (moved from A) | deferred |
| `phase-4a:58` | 72 | EDITOR (moved from A) | deferred |
| `phase-4a:88` | 137 | EDITOR (moved from A) | deferred |
| `phase-4a:94` | 143 | EDITOR | part |
| `phase-4a:95` | 144 | EDITOR | part |
| `phase-4a:96` | 145 | EDITOR | part |
| `phase-4a:97` | 146 | EDITOR | part |
| `phase-4a:98` | 147 | EDITOR | full |
| `phase-4a:99` | 148 | EDITOR | part |
| `phase-4a:102` | 151 | EDITOR | part |
| `phase-4a:106` | 157 | EDITOR | part |
| `phase-4a:107` | 158 | EDITOR (moved from A) | deferred |
| `phase-4a:112` | 165 | EDITOR | full |
| `phase-4a:115` | 168 | EDITOR | full |
| `phase-4a:116` | 169 | EDITOR | full |
| `phase-4a:117` | 170 | EDITOR | full |
| `phase-4a:118` | 171 | EDITOR | full |
| `phase-4a:119` | 172 | EDITOR | part |
| `phase-4a:120` | 173 | EDITOR | part |
| `phase-4a:123` | 176 | EDITOR | part |
| `phase-4a:124` | 177 | EDITOR | part |
| `phase-4a:127` | 185 | EDITOR | part |
| `phase-4a:129` | 189 | EDITOR | full |
| `phase-4a:130` | 190 | EDITOR | full |
| `phase-4a:131` | 191 | EDITOR | part |
| `phase-4a:132` | 192 | EDITOR | part |
| `phase-4a:133` | 193 | EDITOR | part |
| `phase-4a:145` | 212 | EDITOR (moved from A) | part |
| `phase-4a:146` | 213 | EDITOR (moved from A) | part |
| `phase-4a:147` | 214 | EDITOR | part |
| `phase-4a:148` | 215 | EDITOR | part |
| `phase-4a:151` | 218 | EDITOR (moved from A) | deferred |
| `phase-4a:155` | 223 | EDITOR, also CLOSESHEET | part |
| `phase-4a:162` | 231 | EDITOR (moved from A) | part |
| `phase-4b:71` | 99 | EDITOR | full |
| `phase-4b:73` | 101 | EDITOR | full |
| `phase-4b:74` | 102 | EDITOR | full |
| `phase-4b:75` | 103 | EDITOR | full |
| `phase-4b:76` | 104 | EDITOR | full |
| `phase-4b:77` | 105 | EDITOR | full |
| `phase-4b:92` | 132 | EDITOR | part |
| `phase-4b:105` | 149 | EDITOR | full |
| `phase-4b:106` | 150 | EDITOR | part |
| `phase-4b:107` | 151 | EDITOR | full |
| `phase-4b:108` | 152 | EDITOR | full |
| `phase-4b:112` | 156 | EDITOR | part |
| `phase-4b:113` | 157 | EDITOR | part |
| `phase-4b:114` | 158 | EDITOR | full |
| `phase-4c:94` | 94 | EDITOR (moved from A) | deferred |
| `phase-4c:95` | 95 | EDITOR (moved from A) | deferred |
| `phase-4c:179` | 245 | EDITOR | full |
| `phase-4c:201` | 273 | EDITOR, also EDDEFAULTS | part |
| `phase-4c:214` | 296 | EDITOR | full |
| `phase-6a:131` | 133 | EDITOR, also QASTACK | part |
| `phase-6a:152` | 155 | EDITOR | full |
| `phase-6a:158` | 161 | EDITOR | full |
| `phase-6a:164` | 172 | EDITOR | part |
| `phase-6a:198` | 210 | EDITOR, also SAVEAS | part |
| `phase-6a:199` | 211 | EDITOR | part |
| `phase-6b:118` | 144 | EDITOR, also TARGET, PINS | part |
| `phase-7c:72` | 73 | EDITOR (moved from A) | deferred |
| `phase-7c:169` | 212 | EDITOR (moved from A) | part |
| `phase-7c:170` | 213 | EDITOR | part |
| `phase-7c:171` | 214 | EDITOR | part |
| `phase-7c:172` | 215 | EDITOR, also EDSAVEAS | part |
| `phase-7c:187` | 230 | EDITOR, also TARGET | part |
| `small-tweaks:18` | 21 | EDITOR | full |

## coordinator-split (`docs/testing/coordinator-split-manual-checklist.md`)

### `coordinator-split:43` (line 43)

> Annotate the newest card, Save, then Upload [`+Editor`]. After capture `Save and copy image`. Capture an area and click the card's Annotate (the pencil) at once: the editor opens without a pause. Draw a stroke: the close button shows the unsaved dot. ⌘S: the dot clears, the file in the save folder shows the stroke (Quick Look) and nothing uploads. ⌘U: the editor closes, the row uploads, the URL replaces the clipboard, and the URL shows the stroke.

- Seams: `EDITOR` alone.
- This phase: part. `CoordinatorEditorUploadTests.annotateTheNewestCardSaveThenUploadWritesTheFileThenUploadsAndCopiesTheURL`.
- Stays: the unsaved dot and the window closing (`EDPLACE`). The URL showing the stroke is the PUT body; the real bucket, by hand.

### `coordinator-split:44` (line 44)

> Pin, then the pin menu's three items [`+Pins`, `+RecordActions`]. Capture an area and click the card's pin (`Pin to screen`): a pin opens over the spot the area came from. Click the card's pin again: the same pin comes forward and no second one opens. The menu now has `Close Pinned Screenshots`. Right-click the pin: `Copy Image` puts the image on the clipboard and posts `Image copied`; `Save As…` opens a panel that suggests the capture's own name (Cancel it); `Annotate` opens the editor. Choose `Close Pinned Screenshots`: the pin closes and the menu item goes.

- Seams: `EDITOR`, also `SAVEAS`, `SCREENS`, `PINS`.
- This phase: part. `CoordinatorEditorTests.annotateFromACardOrRecentCapturesLeavesNothingToRestore` (the pin menu's Annotate reaches the same `openEditorAfterMenuTracking`).
- Stays: the pin, the second click, `Close Pinned Screenshots` (`PINS`, `SCREENS`); the pin's Save As… panel (`SAVEAS`). Copy Image is already pinned by `CoordinatorRecordActionsTests.copyImageReadsTheFileOrDownloadsTheObject`.

## phase-4a (`docs/testing/phase-4a-manual-checklist.md`)

### `phase-4a:37` (line 39)

> "Upload and copy URL", a large capture with Network Link Conditioner on a slow profile: Annotate while the overlay shows Uploading… opens the editor at once with the subtitle `Uploading…`. Save and Upload stay greyed until the upload finishes, then turn on.

- Seams: `EDITOR` (moved from A by tests-A: it was read off a constructed controller).
- This phase: part. `CoordinatorEditorTests.anEditorOpenedDuringAHeldUploadHearsUploadingAndGetsSaveAndUploadBack`.
- Stays: the subtitle as shown and the greyed toolbar (`EDPLACE`); the slow profile is the fake's hold.

### `phase-4a:39` (line 43)

> Annotate a capture whose editor is already open (from its Recent Captures row): that window comes forward and no second window opens.

- Seams: `EDITOR` alone.
- This phase: part. `CoordinatorEditorTests.annotateOnACaptureWhoseEditorIsOpenBringsItForwardAndBuildsNoSecond` (a second Annotate calls `present()` on the registered editor and builds none).
- Stays: the window coming forward, by hand. It is `present()`'s own body (EditorWindowController.swift:147-152), which the fake records and does not run; ordering a window front is barred in the suite, so no seam reaches it.

### `phase-4a:49` (line 59)

> Upload-only capture that finished uploading: after a moment (it downloads the object) the editor opens, titled `Capture <time>`. With Wi-Fi off: no window, and a `Could not open the capture` notification gives the reason.

- Seams: `EDITOR` alone.
- This phase: full. `CoordinatorEditorTests.anUploadedUploadOnlyCaptureOpensFromItsObjectAndOfflineOpensNone`.
- Stays: nothing (Wi-Fi off is a scripted download failure).

### `phase-4a:52` (line 65)

> Settings > Overlay, turn "Show Quick Access overlay after capture" off. Capture once in each after-capture mode: no overlay appears, and Annotate on the new row opens the editor each time (for "Upload only, keep no local file", also while it is still uploading). Turn the overlay back on.

- Seams: `EDITOR` alone.
- This phase: full. `CoordinatorEditorTests.withTheOverlayOffEveryAfterCaptureModeStillOpensTheEditor(mode:)`.
- Stays: nothing the line checks. The captures are records set up as each mode's `persist` leaves them (+Save:161-174); the capture itself is `TARGET`'s.

### `phase-4a:56` (line 70)

> The toolbar shows, in order: the fourteen tools (Select, Redact, Pixelate, Blur, Spotlight, Rectangle, Arrow, Ellipse, Line, Pencil, Highlighter, Text, Counter, Crop), the colour button, the options button, the Background button, the zoom pop-up, Copy, Save (a downward arrow) and a prominent Upload (a cloud with an up arrow). Copy, Save and Upload are plain buttons with no menus; their tooltips read `Copy the image (⌘C)`, `Save (⌘S)` and `Upload and copy the link (⌘U)`. Each tool's tooltip names its letter.

- Seams: `EDITOR` (moved from A by tests-A: it was read off a constructed controller); needs `EDPLACE` before any test.
- This phase: deferred, no test.
- Stays: all of it: the toolbar of a built controller (`EDPLACE`).

### `phase-4a:58` (line 72)

> With the canvas focused, `V` `D` `X` `B` `R` `A` pick Select, Redact, Pixelate, Blur, Rectangle and Arrow, and the toolbar follows.

- Seams: `EDITOR` (moved from A by tests-A: it was read off a constructed controller); needs `EDPLACE` before any test.
- This phase: deferred, no test.
- Stays: all of it: the tools segment following a key, on a built controller (`EDPLACE`).

### `phase-4a:88` (line 137)

> ⌘1 shows the picture at its natural point size and ⌘0 fits it again. ⌘= and ⌘- zoom around the window centre. The zoom pop-up's Fit, 50 %, 100 %, 200 % and 400 % each work.

- Seams: `EDITOR` (moved from A by tests-A: it was read off a constructed controller); needs `EDPLACE` before any test.
- This phase: deferred, no test.
- Stays: all of it: the zoom actions and pop-up of a built controller (`EDPLACE`).

### `phase-4a:94` (line 143)

> Saved capture: Redact, ⌘S. The same file in the save folder now shows the redaction (Quick Look), no new file appears, the unsaved dot clears, and the row's thumbnail shows the redaction the next time the menu opens. Nothing is uploaded.

- Seams: `EDITOR` alone.
- This phase: part. `CoordinatorEditorSaveTests.saveWritesOverTheSaveFolderFileAndUploadsNothing`.
- Stays: the unsaved dot clearing (`EDPLACE`); the menu drawing the row's thumbnail, by hand. Quick Look is the file's decode, and the new thumbnail's decode is the row's thumbnail.

### `phase-4a:95` (line 144)

> Capture uploaded with "Upload and copy URL": ⌘S rewrites the file only. The subtitle reads `The uploaded copy still shows the original. Upload to replace it.` and the link still shows the original.

- Seams: `EDITOR` alone.
- This phase: part. `CoordinatorEditorSaveTests.saveOverAnUploadedCaptureRewritesTheFileOnlyAndMarksItsLinkStale(link:)` (`.afterPhase3`).
- Stays: the subtitle as shown (`EDPLACE`). The link still showing the original is the absence of a PUT.

### `phase-4a:96` (line 145)

> Capture from before Phase 3: ⌘S rewrites its file, with the same subtitle.

- Seams: `EDITOR` alone.
- This phase: part. `CoordinatorEditorSaveTests.saveOverAnUploadedCaptureRewritesTheFileOnlyAndMarksItsLinkStale(link:)` (`.beforePhase3`).
- Stays: the subtitle as shown (`EDPLACE`).

### `phase-4a:97` (line 146)

> Upload-only capture that finished uploading: Save is on. Redact, then the Save button (or ⌘S): a save panel opens as a sheet, named by the file name template plus `.png`, in the save folder. Save there: the PNG is written, a `Saved` notification names it, the unsaved dot clears, and nothing uploads (no new link on the clipboard, no new Recent Captures row).

- Seams: `EDITOR` alone.
- This phase: part. `CoordinatorEditorSaveTests.saveAsOnAnUploadOnlyCaptureWritesThePNGAndUploadsNothing`.
- Stays: the sheet, its name and folder (`EDSAVEAS`); "Save is on" as the toolbar shows it, and the dot (`EDPLACE`). The first push's `available` is the rule.

### `phase-4a:98` (line 147)

> Upload-only capture whose upload failed: Redact, ⌘S rewrites `pending/<UUID>.png`. Wi-Fi on, Retry Failed Uploads: the link shows the redaction.

- Seams: `EDITOR` alone.
- This phase: full. `CoordinatorEditorSaveTests.saveOnAFailedUploadOnlyCaptureRewritesPendingAndRetryUploadsTheEdit`.
- Stays: nothing.

### `phase-4a:99` (line 148)

> Lock the saved file (Finder, Get Info, Locked), edit, ⌘S: a `Not saved` notification with the reason, the unsaved dot stays, and the edited image is on the clipboard. Unlock the file.

- Seams: `EDITOR` alone.
- This phase: part. `CoordinatorEditorSaveTests.saveOverALockedFileSaysNotSavedAndPutsTheEditOnTheClipboard`.
- Stays: the dot staying (`EDPLACE`); Finder's Locked is the immutable flag.

### `phase-4a:102` (line 151)

> Saved capture: edit, then ⇧⌘S. The save panel suggests the capture's own file name in the save folder. Choose the Desktop and another name: the PNG appears there with the edit, `sips -g dpiWidth` gives 144 on the 2x display, and the original file in the save folder is unchanged. No Recent Captures row is added, no overlay or shutter sound, nothing uploads, and the editor keeps its title. The unsaved dot clears.

- Seams: `EDITOR` alone.
- This phase: part. `CoordinatorEditorSaveTests.saveAsElsewhereWritesA144DPICopyAndLeavesTheCaptureAlone`.
- Stays: the panel's suggestion and the choice (`EDSAVEAS`); the dot (`EDPLACE`).

### `phase-4a:106` (line 157)

> ⇧⌘S on a saved capture and save over its own file (confirm Replace): it behaves as ⌘S, so the row's thumbnail shows the edit, and on an uploaded capture the subtitle says the uploaded copy still shows the original.

- Seams: `EDITOR` alone.
- This phase: part. `CoordinatorEditorSaveTests.saveAsOntoItsOwnFileIsASave(uploaded:)`.
- Stays: the Replace confirmation (`EDSAVEAS`); the subtitle (`EDPLACE`).

### `phase-4a:107` (line 158)

> Edit, ⌘U, and keep drawing before the window closes (slow machine or large capture; may be hard to hit): if the drawing changed during the call, the editor beeps and stays open with the newer edit unsaved.

- Seams: `EDITOR` (moved from A by tests-A: it was read off a constructed controller); needs `EDPLACE` and `BEEP` before any test.
- This phase: deferred, no test.
- Stays: all of it: the beep and staying open are `performUpload` on a built controller (`EDPLACE` and `BEEP`).

### `phase-4a:112` (line 165)

> With "Show notification" off, Copy posts nothing. Turn it back on.

- Seams: `EDITOR` alone.
- This phase: full. `CoordinatorEditorSaveTests.copyWithShowNotificationOffPostsNothing`.
- Stays: nothing.

### `phase-4a:115` (line 168)

> "Save and copy image" with "Copy image to clipboard" on: capture a made-up secret, Annotate, Redact, ⌘S. Preview, File > New from Clipboard: the redacted image.

- Seams: `EDITOR` alone.
- This phase: full. `CoordinatorEditorSaveTests.aSaveOrSaveAsTakesTheClipboardOnlyWhileItHoldsTheCapture(write:userCopied:)` (`.save, false`).
- Stays: nothing the line checks (Preview is the decode of the clipboard PNG). The capture's own copy and owner are set up as +Save:57-67 leaves them; that step is in `save(_:intent:)` (`TARGET`), and no test pins it today.

### `phase-4a:116` (line 169)

> The same with ⇧⌘S in place of ⌘S, saving to the Desktop: the clipboard holds the redacted image.

- Seams: `EDITOR` alone.
- This phase: full. `CoordinatorEditorSaveTests.aSaveOrSaveAsTakesTheClipboardOnlyWhileItHoldsTheCapture(write:userCopied:)` (`.saveAs, false`).
- Stays: nothing the line checks. The capture's own copy and owner are set up as +Save:57-67 leaves them (`TARGET`).

### `phase-4a:117` (line 170)

> Capture, copy some text in TextEdit, then Annotate, Redact, ⇧⌘S: the clipboard still holds the text.

- Seams: `EDITOR` alone.
- This phase: full. `CoordinatorEditorSaveTests.aSaveOrSaveAsTakesTheClipboardOnlyWhileItHoldsTheCapture(write:userCopied:)` (`.saveAs, true`).
- Stays: nothing the line checks. The capture's own copy and owner are set up as +Save:57-67 leaves them (`TARGET`).

### `phase-4a:118` (line 171)

> Capture, copy some text in TextEdit, then Annotate, Redact, ⌘S: the clipboard still holds the text.

- Seams: `EDITOR` alone.
- This phase: full. `CoordinatorEditorSaveTests.aSaveOrSaveAsTakesTheClipboardOnlyWhileItHoldsTheCapture(write:userCopied:)` (`.save, true`).
- Stays: nothing the line checks. The capture's own copy and owner are set up as +Save:57-67 leaves them (`TARGET`).

### `phase-4a:119` (line 172)

> "Upload and copy URL" with no destination (Forget Credentials in Settings > Upload): capture (the image goes to the clipboard), Annotate, Redact, ⌘S: the clipboard holds the redacted image. ⌘U posts `Upload not configured`, changes nothing, and the editor stays open. Enter the credentials again.

- Seams: `EDITOR` alone.
- This phase: part. `CoordinatorEditorUploadTests.withNoDestinationSaveTakesTheClipboardAndUploadIsRefused`.
- Stays: the window staying open (`EDPLACE`). The capture's own copy is set up as +Save:32-34, :57-67 leave it with no destination (`TARGET`).

### `phase-4a:120` (line 173)

> "Upload and copy URL" with "Also copy image" on: capture, Annotate, Redact, ⌘U. The editor closes at once; when the upload finishes the clipboard holds the URL.

- Seams: `EDITOR` alone.
- This phase: part. `CoordinatorEditorUploadTests.anUploadAfterTheCapturesOwnClosesAtOnceAndEndsWithTheLinkCopied`.
- Stays: the window closing (`EDPLACE`). The capture's own copy is set up as +Save:30-31, :57-67 leave it (`TARGET`).

### `phase-4a:123` (line 176)

> Capture uploaded with "Upload and copy URL": Redact, then the Upload button. The editor closes at once with no unsaved-changes sheet, and the row shows the upload running. When it finishes the clipboard holds the same URL as before, the link shows the redaction, and the file in the save folder shows it too.

- Seams: `EDITOR` alone.
- This phase: part. `CoordinatorEditorUploadTests.uploadWritesTheFileFirstThenReplacesTheLinksObject`.
- Stays: closing with no sheet (`EDPLACE`). The link showing the redaction is the PUT body under the link's key.

### `phase-4a:124` (line 177)

> Upload-only capture that finished uploading: Redact, ⌘U. The editor closes, and when the upload finishes the link to paste is on the clipboard and shows the redaction.

- Seams: `EDITOR` alone.
- This phase: part. `CoordinatorEditorUploadTests.uploadOfAnUploadOnlyCaptureWritesPendingThenReplacesItsKey`.
- Stays: the window closing (`EDPLACE`).

### `phase-4a:127` (line 185)

> Saved capture never uploaded: ⌥⌘U beeps. ⌘U uploads it for the first time, closes the editor and copies a new link.

- Seams: `EDITOR` alone.
- This phase: part. `CoordinatorEditorUploadTests.uploadAsNewWithoutALinkIsRefusedAndUploadMakesTheFirstLink`.
- Stays: ⌥⌘U refused by the window's validation (`EDPLACE`) and its beep (`BEEP`); closing (`EDPLACE`). The test pins the coordinator's write-time refusal behind that gate, which posts a notice the window's beep never lets happen.

### `phase-4a:129` (line 189)

> Capture from before Phase 3: ⌘U shows the notice `The earlier upload stays in the bucket.` and makes a new link; `curl -I <old url>` still gives 200.

- Seams: `EDITOR` alone.
- This phase: full. `CoordinatorEditorUploadTests.uploadOfAPrePhase3CaptureMakesANewLinkAndDeletesNothing`.
- Stays: nothing (`curl -I` is the empty DELETE list).

### `phase-4a:130` (line 190)

> Optional, with a second bucket: point Settings > Upload at it, then ⌘U on a capture uploaded to the first. The notice reads `The destination changed, so this uploads as a new link.`, the link is in the second bucket, and the old object is gone from the first. Point the settings back.

- Seams: `EDITOR` alone.
- This phase: full. `CoordinatorEditorUploadTests.uploadAfterTheDestinationChangedGoesToTheNewBucketAndDeletesTheOldObject`.
- Stays: nothing (the second bucket is a second fake).

### `phase-4a:131` (line 191)

> Enter a wrong secret access key in Settings > Upload and press Save, then ⌘U on an uploaded capture: the editor closes. After the retries: a notification `Upload failed. The link still shows the earlier image.`, and the row still copies the old URL. Annotate on the row reopens the edited image, with the subtitle `The uploaded copy still shows the original. Upload to replace it.` Enter the right key, ⌘U: the same URL now shows the edit.

- Seams: `EDITOR` alone.
- This phase: part. `CoordinatorEditorUploadTests.aFailedReplaceKeepsTheLinkAndTheEditAndTheRightKeyReplacesIt`.
- Stays: closing and the subtitle as shown (`EDPLACE`). The link is the PUT body. The notice's title is `Not uploaded` (harness D14); a 403 is not retried.

### `phase-4a:132` (line 192)

> Folder change with a bad key: Settings > General, Choose… another save folder. Open an older capture (saved in the old folder) from Recent Captures, Redact, then enter a wrong secret access key in Settings > Upload and press ⌘U. The editor closes. After the failure, `pending/<UUID>.png` holds the redacted image and the file in the old folder is unchanged. Enter the right key, Retry Failed Uploads: the link shows the redacted image, not the original, and `pending/<UUID>.png` is gone. Choose the original folder again.

- Seams: `EDITOR` alone.
- This phase: part. `CoordinatorEditorUploadTests.aFailedReplaceAfterAFolderChangeKeepsTheEditInPendingUntilTheNextUpload`.
- Stays: closing (`EDPLACE`). The line's last step is at odds with the code: Retry Failed Uploads does nothing for this capture; the next ⌘U recovers it (tests-editor.md section 8, Tim's call).

### `phase-4a:133` (line 193)

> The same wrong key, ⌘U on an upload-only capture that finished uploading. The editor closes. After the failure `pending/<UUID>.png` exists and holds the edit. Annotate on the row reopens it with the edit, and the subtitle says the uploaded copy still shows the original. Right key, ⌘U: the same URL shows the edit and `pending/<UUID>.png` is gone.

- Seams: `EDITOR` alone.
- This phase: part. `CoordinatorEditorUploadTests.aFailedReplaceOfAnUploadOnlyCaptureKeepsPendingAcrossARelaunchUntilTheNextUpload`.
- Stays: closing and the subtitle as shown (`EDPLACE`).

### `phase-4a:145` (line 212)

> Slow profile, "Upload and copy URL": capture something large and press Annotate on the overlay while it uploads. The subtitle reads `Uploading…`, ⌘S, ⌘U and ⌥⌘U beep and do nothing, and Save and Upload are greyed in the toolbar; ⌘C and ⇧⌘C work and ⇧⌘S opens the save panel. When the upload finishes they turn on again.

- Seams: `EDITOR` (moved from A by tests-A: it was read off a constructed controller).
- This phase: part. `CoordinatorEditorTests.anEditorOpenedDuringAHeldUploadHearsUploadingAndGetsSaveAndUploadBack`.
- Stays: the subtitle as shown, greying and ⌘C/⇧⌘C routing (`EDPLACE`); ⌘S, ⌘U and ⌥⌘U refused by the window's validation (`EDPLACE`) and their beeps (`BEEP`); ⇧⌘S's panel (`EDSAVEAS`). The test pins the coordinator's write-time refusal behind that gate, which posts a `Not saved` or `Not uploaded` notice; the line's "do nothing" is the gate's.

### `phase-4a:146` (line 213)

> With an editor open, press Delete on its row and leave the alert open: the editor's Save and Upload grey out at once, the subtitle reads `Deleting…`, and ⌘S beeps. Cancel: they turn on again and the subtitle returns to what it was.

- Seams: `EDITOR` (moved from A by tests-A: it was read off a constructed controller).
- This phase: part. `CoordinatorEditorTests.aDeleteAskedThenCancelledThenConfirmedReachesTheOpenEditor`; `CoordinatorEditorTests.anEditorOpenedWhileADeleteAsksHearsItAndRefusesSave`.
- Stays: greying and the subtitle as shown (`EDPLACE`); ⌘S refused by the window's validation (`EDPLACE`) and its beep (`BEEP`). The tests pin the coordinator's write-time refusal behind that gate.

### `phase-4a:147` (line 214)

> Delete again and confirm: the subtitle reads `This capture was deleted. Copy and Save As still work.`, Save and Upload stay greyed, ⌘C copies, and ⇧⌘S opens the save panel and writes the PNG.

- Seams: `EDITOR` alone.
- This phase: part. `CoordinatorEditorTests.aDeleteAskedThenCancelledThenConfirmedReachesTheOpenEditor`; `CoordinatorEditorTests.anEditorOpenedWhileADeleteAsksHearsItAndRefusesSave`.
- Stays: the subtitle as shown and greying (`EDPLACE`); ⌘C reaching `copyImage` (`EDPLACE`); ⇧⌘S's panel (`EDSAVEAS`).

### `phase-4a:148` (line 215)

> Editor open on a capture in the save folder: Settings > General, Choose… another folder. The subtitle gives the reason at once, and ⌘S now opens the save panel instead of writing over the file (Cancel it). ⌘W's Save opens the save panel (Cancel it). ⌘U uploads the edit and closes the editor; the file in the old folder is not rewritten, and the edit is in `pending/<UUID>.png` until the upload finishes. Choose the original folder again; on another capture there, ⌘S writes over the file without a panel.

- Seams: `EDITOR` alone.
- This phase: part. `CoordinatorEditorUploadTests.aNewSaveFolderReachesTheOpenEditorAndUploadGoesThroughPending`.
- Stays: ⌘S's panel (`EDSAVEAS`); ⌘W's Save (`CLOSESHEET` and `EDSAVEAS`); the subtitle and closing (`EDPLACE`).

### `phase-4a:151` (line 218)

> ⌘W on an editor with no changes closes it at once.

- Seams: `EDITOR` (moved from A by tests-A: it was read off a constructed controller); needs `EDPLACE` before any test.
- This phase: deferred, no test.
- Stays: all of it: `windowShouldClose` on a built controller (`EDPLACE`).

### `phase-4a:155` (line 223)

> Quit TidyShot from the menu with a changed editor: the sheet appears on it. Cancel: TidyShot keeps running and the editor stays open. Quit again, Don’t Save: TidyShot quits.

- Seams: `EDITOR`, also `CLOSESHEET`.
- This phase: part. `CoordinatorEditorTests.quitAsksEachChangedEditorCancelStopsItDontSaveLetsItGo`.
- Stays: the sheet itself (`CLOSESHEET`); the real quit's reply (`APPDELEGATE`).

### `phase-4a:162` (line 231)

> Quit, set one record's `timestamp` in `history.json` to two days ago, relaunch, and open that capture from its row. Settings > Overlay, set Keep history to 1 day, then take a new capture: the editor's subtitle reads `This capture was deleted. Copy and Save As still work.`, Save and Upload are greyed, and ⇧⌘S still opens the save panel. Set the retention back.

- Seams: `EDITOR` (moved from A by tests-A: it was read off a constructed controller).
- This phase: part. `CoordinatorEditorTests.aPrunedCaptureTellsItsOpenEditorItWasDeleted`.
- Stays: the subtitle and greying (`EDPLACE`); ⇧⌘S's panel (`EDSAVEAS`).

## phase-4b (`docs/testing/phase-4b-manual-checklist.md`)

### `phase-4b:71` (line 99)

> Saved pixel size: on a saved capture, crop to a readout of, say, 800 x 400, Return, ⌘S. `sips -g pixelWidth -g pixelHeight -g dpiWidth <file>` reports 800 x 400 (the readout, not the original size), and `dpiWidth` is 144 on the 2x display (72 on a 1x display). Quick Look shows only the cropped picture, and no new file appears.

- Seams: `EDITOR` alone.
- This phase: full. `CoordinatorEditorSaveTests.saveWithACropWritesTheCroppedSizeAtTheCapturesScaleAndReopensCropped(scale:)`.
- Stays: nothing (`sips` is the decode and the DPI read).

### `phase-4b:73` (line 101)

> Reopen the cropped capture with Annotate: the editor opens the cropped file at its new size, with no crop pending, and Crop starts from the whole picture again.

- Seams: `EDITOR` alone.
- This phase: full. `CoordinatorEditorSaveTests.saveWithACropWritesTheCroppedSizeAtTheCapturesScaleAndReopensCropped(scale:)`.
- Stays: nothing.

### `phase-4b:74` (line 102)

> Uploaded pixel size: on a capture uploaded with "Upload and copy URL", crop, then the Upload button. When the upload finishes, `curl -s <url> -o /tmp/crop.png && sips -g pixelWidth -g pixelHeight /tmp/crop.png` reports the cropped size, the file in the save folder is cropped too, and `history.json` has the cropped `pixelWidth` and `pixelHeight`. The link is the same as before.

- Seams: `EDITOR` alone.
- This phase: full. `CoordinatorEditorUploadTests.uploadWritesTheFileFirstThenReplacesTheLinksObject`.
- Stays: nothing (`curl` and `sips` are the PUT body's decode).

### `phase-4b:75` (line 103)

> Upload-only capture that finished uploading: crop, ⌘U. The link then serves the cropped size.

- Seams: `EDITOR` alone.
- This phase: full. `CoordinatorEditorUploadTests.uploadOfAnUploadOnlyCaptureWritesPendingThenReplacesItsKey`.
- Stays: nothing.

### `phase-4b:76` (line 104)

> Save As… (⇧⌘S) with a crop: the new PNG has the cropped pixel size, and the capture's own file is unchanged.

- Seams: `EDITOR` alone.
- This phase: full. `CoordinatorEditorSaveTests.saveAsWithACropWritesACroppedCopyAndLeavesTheCaptureAlone`.
- Stays: nothing the line checks.

### `phase-4b:77` (line 105)

> Copy (⌘C with nothing selected) with a crop: Preview, File > New from Clipboard, shows the cropped image at point size.

- Seams: `EDITOR` alone.
- This phase: full. `CoordinatorEditorSaveTests.copyWithACropPutsTheCroppedImageAtPointSizeAndSaysImageCopied`.
- Stays: nothing (Preview is the clipboard PNG's size and DPI).

### `phase-4b:92` (line 132)

> ⌘C with nothing selected still copies the flattened image (`Image copied`; Preview > New from Clipboard shows it). With an object selected, ⌘C copies the object and ⇧⌘C and the toolbar's Copy button still copy the image.

- Seams: `EDITOR` alone.
- This phase: part. `CoordinatorEditorSaveTests.copyWithACropPutsTheCroppedImageAtPointSizeAndSaysImageCopied`.
- Stays: which command reaches the copy: ⌘C with and without a selection, ⇧⌘C, the toolbar button (`EDPLACE`).

### `phase-4b:105` (line 149)

> Saved capture, never uploaded: Annotate on its row opens the editor. Place a text and an ellipse, crop, ⌘S: the same file now shows all three (cropped, with the text and ellipse inside).

- Seams: `EDITOR` alone.
- This phase: full. `CoordinatorEditorSaveTests.saveWithTextEllipseAndCropWritesAllThreeIntoTheSameFile`.
- Stays: nothing.

### `phase-4b:106` (line 150)

> Capture uploaded with "Upload and copy URL": Annotate on its row, highlight a line, ⌘U. The editor closes at once, and the link shows the highlight.

- Seams: `EDITOR` alone.
- This phase: part. `CoordinatorEditorUploadTests.uploadWritesTheFileFirstThenReplacesTheLinksObject`.
- Stays: closing at once (`EDPLACE`).

### `phase-4b:107` (line 151)

> Upload-only capture whose upload failed: opens from `pending/<UUID>.png`; add a pencil stroke, ⌘S writes the pending file, Retry Failed Uploads uploads it with the stroke.

- Seams: `EDITOR` alone.
- This phase: full. `CoordinatorEditorSaveTests.saveOnAFailedUploadOnlyCaptureRewritesPendingAndRetryUploadsTheEdit`.
- Stays: nothing.

### `phase-4b:108` (line 152)

> Upload-only capture that finished uploading: Annotate downloads the object and opens `Capture <time>`; add text, crop and ⌘U. The link serves the cropped image with the text.

- Seams: `EDITOR` alone.
- This phase: full. `CoordinatorEditorUploadTests.uploadOfAnUploadOnlyCaptureWritesPendingThenReplacesItsKey`.
- Stays: nothing.

### `phase-4b:112` (line 156)

> Enter a wrong secret access key in Settings > Upload and press Save. On an upload-only capture that finished uploading, Annotate, add text, crop to a readout you note, ⌘U. The editor closes, and after the retries a notification says `Upload failed. The link still shows the earlier image.` Quit TidyShot and relaunch.

- Seams: `EDITOR` alone.
- This phase: part. `CoordinatorEditorUploadTests.aFailedReplaceOfAnUploadOnlyCaptureKeepsPendingAcrossARelaunchUntilTheNextUpload`.
- Stays: the window closing (`EDPLACE`); the real quit and relaunch, by hand (a second coordinator stands for it). A 403 is not retried; the title is `Not uploaded`.

### `phase-4b:113` (line 157)

> The row still copies the old URL. Annotate on the row reopens the edit with the text and at the cropped size, with the subtitle `The uploaded copy still shows the original. Upload to replace it.` (the pending file holds the cropped, edited bytes).

- Seams: `EDITOR` alone.
- This phase: part. `CoordinatorEditorUploadTests.aFailedReplaceOfAnUploadOnlyCaptureKeepsPendingAcrossARelaunchUntilTheNextUpload`.
- Stays: the subtitle as shown (`EDPLACE`).

### `phase-4b:114` (line 158)

> Enter the right key and press ⌘U: the same URL now serves the cropped image with the text, `pending/<UUID>.png` is gone, and the row's pixel size in `history.json` is the cropped size.

- Seams: `EDITOR` alone.
- This phase: full. `CoordinatorEditorUploadTests.aFailedReplaceOfAnUploadOnlyCaptureKeepsPendingAcrossARelaunchUntilTheNextUpload`.
- Stays: nothing.

## phase-4c (`docs/testing/phase-4c-manual-checklist.md`)

### `phase-4c:94` (line 94)

> The toolbar shows fourteen tools, in order: Select, Redact, Pixelate, Blur, Spotlight, Rectangle, Arrow, Ellipse, Line, Pencil, Highlighter, Text, Counter and Crop, then Colour, Options, Background, the zoom pop-up, Copy, Save and Upload. The new tools' tool tips read `Spotlight (S)` and `Counter (N)`; the symbols are `light.max` and `1.circle`. The Options button's tool tip reads `Tool options`.

- Seams: `EDITOR` (moved from A by tests-A: it was read off a constructed controller); needs `EDPLACE` before any test.
- This phase: deferred, no test.
- Stays: all of it left open: the item order after the tools and the Options tip, on a built controller (`EDPLACE`); the rest is D.

### `phase-4c:95` (line 95)

> With the canvas focused, `S` (either case) picks Spotlight and `N` picks Counter, and the toolbar's segment follows. ⌘S still saves (it does not pick Spotlight; try it on a scratch capture). `N` with a text being edited types the letter.

- Seams: `EDITOR` (moved from A by tests-A: it was read off a constructed controller); needs `EDPLACE` before any test.
- This phase: deferred, no test.
- Stays: all of it left open: the segment following a key-picked tool, on a built controller (`EDPLACE`); the keys are D.

### `phase-4c:179` (line 245)

> Once the upload has finished, reopen the capture with Annotate on its Recent Captures row: it opens as a flat image with the marks in its pixels, and no spotlight or counter left to select.

- Seams: `EDITOR` alone.
- This phase: full. `CoordinatorEditorUploadTests.anUploadedCaptureReopensFlatWithItsMarksInThePixels`.
- Stays: nothing.

### `phase-4c:201` (line 273)

> Shape and Size survive a relaunch. Choose Ellipse and Large, then check `defaults read io.tky.tidyshot editorSpotlightEllipse` (`1`) and `editorCounterDiameterPoints` (`44`). Quit and relaunch TidyShot, open any capture in the editor: Spotlight draws ellipses, the Shape row shows Ellipse when the Spotlight tool is active, a new counter is 44 pt (88 px at 2x), and the Size row shows Large with the Counter tool.

- Seams: `EDITOR`, also `EDDEFAULTS`.
- This phase: part. `CoordinatorEditorTests.anEditorOpensWithTheStoredSpotlightShapeAndCounterSize`.
- Stays: choosing Ellipse and Large in the popover (`EDDEFAULTS`); the rows as drawn, `defaults read` and the relaunch, by hand.

### `phase-4c:214` (line 296)

> An older capture, made before 4c, opens in the editor, edits and exports as before.

- Seams: `EDITOR` alone.
- This phase: full. `CoordinatorEditorTests.aCaptureFromBefore4cOpensEditsAndSavesAsBefore`.
- Stays: nothing.

## phase-6a (`docs/testing/phase-6a-manual-checklist.md`)

### `phase-6a:131` (line 133)

> Delete a card in the middle of the stack and Annotate another: each closes and the gap closes.

- Seams: `EDITOR`, also `QASTACK`.
- This phase: part. `CoordinatorEditorTests.annotateFromACardOrRecentCapturesLeavesNothingToRestore`.
- Stays: the gap in the stack closing (`QASTACK`).

### `phase-6a:152` (line 155)

> Annotate from a card opens the editor and closes the card (not restorable, see below).

- Seams: `EDITOR` alone.
- This phase: full. `CoordinatorEditorTests.annotateFromACardOrRecentCapturesLeavesNothingToRestore`.
- Stays: nothing.

### `phase-6a:158` (line 161)

> Delete a capture from its card, and open the editor from another card: neither can be restored. When only those were closed, `Restore Closed Overlay` is disabled. A card whose delete is under way (the confirmation accepted, an upload being cancelled and the storage `DELETE` still running; Network Link Conditioner on `100% Loss` slows it) is not restorable in that window either: the menu item stays disabled and the shortcut does nothing. Open the editor from Recent Captures on a capture whose card is already closed: its card is no longer restorable.

- Seams: `EDITOR` alone.
- This phase: full. `CoordinatorEditorTests.annotateFromACardOrRecentCapturesLeavesNothingToRestore` (the editor cases); `CoordinatorOverlayTests.aCardWhoseDeleteIsUnderWayIsNotRestorable` (the delete under way).
- Stays: nothing (Network Link Conditioner is a held Abort).

### `phase-6a:164` (line 172)

> A restored card's Annotate opens the editor from the file or, for an uploaded upload-only capture, from the bucket (the same as the Annotate button in Recent Captures).

- Seams: `EDITOR` alone.
- This phase: part. `CoordinatorEditorTests.aRestoredCardsAnnotateOpensFromTheFileOrTheBucket(restored:)` (a showing card with no retained image, as a restored one is; for the uploaded upload-only case, before and after the restore's quiet download into the drag folder).
- Stays: the restore itself, which reads the screens (`SCREENS`). The quiet download's naming is `CoordinatorDragOutTests.aRestoredUploadOnlyCardsQuietDownloadIsNamedForItsKey`.

### `phase-6a:198` (line 210)

> Upload only, after the upload: the card is still on screen, and dragging it still works, from a file in the `Drag` folder that took the place of the pending file. `history.json` shows the record as before (no `fileURL`), and Recent Captures shows no local file. Copy Image, Save As… and Annotate on that card need no download (no `Downloading` notification). 60 seconds after the card closes `ls ~/Library/Containers/io.tky.tidyshot/Data/tmp/Drag` no longer lists the record's folder (Slack may still read the file in those seconds).

- Seams: `EDITOR`, also `SAVEAS`.
- This phase: part. `CoordinatorEditorTests.anUploadedUploadOnlyCardsCopyImageAndAnnotateReadTheDragCopy`.
- Stays: the card's Save As… panel (`SAVEAS`); Slack reading the file, by hand. The drag folder taking the pending file's place and no `fileURL` are already `CoordinatorUploadTests.anUploadedUploadOnlyImageMovesToItsDragFolderOnlyWithACard`.

### `phase-6a:199` (line 211)

> An edited capture's drag copy is replaced. Upload-only mode, wait for the upload (the card shows `URL copied` and a drag file is kept), then press Annotate, draw an arrow, and save the edit (⌘S, or ⌘U to upload it): the capture's `Drag/<record id>` folder is gone at once. Then, from the card or Recent Captures: Copy Image, Save As… and Annotate show the edited image (arrow included), never the one before the edit; a drag started after the edit (press on the card, which stages the edit again) drops the edited image. Do the same with "Save and copy image" and an edit saved over the file: the dragged file has the arrow too.

- Seams: `EDITOR` alone.
- This phase: part. `CoordinatorEditorSaveTests.saveOverTheFileRemovesTheDragCopyAndEveryReadGivesTheEdit` (the "Save and copy image" half); `CoordinatorEditorUploadTests.uploadOfAnUploadOnlyCaptureRemovesItsDragCopyAndEveryReadGivesTheEdit` (the upload-only half).
- Stays: the card's Save As… panel (`SAVEAS`); the drop, by hand. The line's "from the card" after an Annotate cannot happen as written (tests-editor.md section 8).

## phase-6b (`docs/testing/phase-6b-manual-checklist.md`)

### `phase-6b:118` (line 144)

> `action=annotate`: the after-capture action runs, then the editor opens on the new capture and its card closes. `action=pin`: the action runs, then a pin opens and the card stays.

- Seams: `EDITOR`, also `TARGET`, `PINS`.
- This phase: part. `CoordinatorEditorUploadTests.annotateTheNewestCardSaveThenUploadWritesTheFileThenUploadsAndCopiesTheURL` (its open leg).
- Stays: reaching `save(_:intent:)` (`TARGET`); the `action=pin` half (`PINS`).

## phase-7c (`docs/testing/phase-7c-manual-checklist.md`)

### `phase-7c:72` (line 73)

> The toolbar in the editor has a `Background` button (the `rectangle.inset.filled` symbol) after Options, with the tool tip `Background`.

- Seams: `EDITOR` (moved from A by tests-A: it was read off a constructed controller); needs `EDPLACE` before any test.
- This phase: deferred, no test.
- Stays: all of it: the Background toolbar item of a built controller (`EDPLACE`).

### `phase-7c:169` (line 212)

> Copy (⇧⌘C, or ⌘C with nothing selected, since ⌘C with an annotation selected copies the object; or the toolbar button): paste into Preview > File > New from Clipboard. It is the composed image: the fill, the padding, the round corners and the shadow, with annotations.

- Seams: `EDITOR` (moved from A by tests-A: it was read off a constructed controller).
- This phase: part. `CoordinatorEditorSaveTests.copyWithABackgroundPutsTheComposedCanvasOnTheClipboard`.
- Stays: the window's routing to `copyImage` (`EDPLACE`). Preview is the `pngs` decode.

### `phase-7c:170` (line 213)

> Save (⌘S) on a capture with a local file: the file in the save folder is the composed image (open it). The editor is clean afterwards. The capture's recorded size and thumbnail in Recent Captures follow: the thumbnail shows the background and the size is the canvas's.

- Seams: `EDITOR` alone.
- This phase: part. `CoordinatorEditorSaveTests.saveWithABackgroundWritesTheComposedCanvasAndReopensFlat` (the composed canvas, size, thumbnail); `CoordinatorEditorSaveTests.saveWritesOverTheSaveFolderFileAndUploadsNothing` (the save-over path with no background).
- Stays: the clean state as the window shows it (`EDPLACE`); the thumbnail as drawn, by hand.

### `phase-7c:171` (line 214)

> Annotate the saved capture again: it opens as the composed image, flat. The popover's switch is off, because the file is the image; turning it on adds a second background around the first. Write down whether that is what you expect.

- Seams: `EDITOR` alone.
- This phase: part. `CoordinatorEditorSaveTests.saveWithABackgroundWritesTheComposedCanvasAndReopensFlat`.
- Stays: the popover's switch turned on, whose setter reads `AppSettings.shared.backgroundStyle` (`BGPOP`), and the switch drawn in the window (`EDPLACE`); whether a second background is expected is Tim's call.

### `phase-7c:172` (line 215)

> Save As… (⇧⌘S): the file is the composed image; the capture and its record are unchanged.

- Seams: `EDITOR`, also `EDSAVEAS`.
- This phase: part. `CoordinatorEditorSaveTests.saveAsWithABackgroundWritesTheComposedImageAndLeavesTheCaptureAlone`.
- Stays: the panel (`EDSAVEAS`).

### `phase-7c:187` (line 230)

> Open the window capture in the editor (the card's Annotate): it opens as the composed image with the background baked in, and the popover's switch is off.

- Seams: `EDITOR`, also `TARGET`.
- This phase: part. `CoordinatorEditorTests.aComposedWindowCaptureOpensFlatWithNoBackground(composed:)`.
- Stays: producing the window capture (`TARGET`); the popover's switch as its binding shows it (`BGPOP`) and drawn in the window (`EDPLACE`).

## small-tweaks (`docs/testing/small-tweaks-manual-checklist.md`)

### `small-tweaks:18` (line 21)

> Edit a capture in the editor and Save: its row shows the edited file's size. Upload from the editor: after it finishes, the row shows the uploaded size.

- Seams: `EDITOR` alone.
- This phase: full. `CoordinatorEditorUploadTests.annotateTheNewestCardSaveThenUploadWritesTheFileThenUploadsAndCopiesTheURL` (both halves); `CoordinatorEditorSaveTests.saveWritesOverTheSaveFolderFileAndUploadsNothing` (the Save half).
- Stays: nothing.
