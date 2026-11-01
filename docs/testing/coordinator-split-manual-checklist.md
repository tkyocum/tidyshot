# Coordinator split manual test checklist

Run after any change to `TidyShot/App/AppCoordinator*.swift`: the coordinator is split into eleven files
(`AppCoordinator.swift` and ten `AppCoordinator+<Area>.swift` extensions, design
`docs/superpowers/specs/2026-10-23-coordinator-split-design.md`), and no test creates an `AppCoordinator`.
The suite (1272 tests in 131 suites), the pure-move check and the access count carry the argument that
no body changed; they say nothing about the wiring. Everything here needs the running app: the
observation behind the status icon, the callbacks wired in `init`, the capture lock and the paths
between the files. Each item exercises one file's wiring, named in brackets. The checklists for
phases 1 to 7c and recording R1 still cover each feature in depth.

Setup: a fresh **Debug** build (the build the tests use) with Screen Recording granted to it (it is
signed ad hoc, so every rebuild needs a new grant; note how it is signed in `Config/Local.xcconfig`):
```bash
xcodegen generate
xcodebuild -project TidyShot.xcodeproj -scheme TidyShot -configuration Debug -derivedDataPath .build build
open .build/Build/Products/Debug/TidyShot.app
```
Quit any other copy of TidyShot first, since two copies both take the shortcuts. "Show notification"
and "Play sound" on in Settings > General; `Allow URL commands (tidyshot://)` and `Allow URL commands
that capture without a selection` on; a save folder chosen; an upload destination that works
(Settings > Upload); Clop installed and running (for the recording item). Two items need an upload
that lasts a few seconds: use Network Link Conditioner on a slow profile, or a Capture Fullscreen on
a large display. Scrolling capture is slow in a Debug build (the README says to run Release for it),
so scroll slowly; the wiring is the same.

Two shell helpers, used below:
```bash
D="$HOME/Library/Containers/io.tky.tidyshot/Data/Library/Application Support/TidyShot"   # history.json, pending/, thumbnails/
t() { open "tidyshot://$1"; }
```
The after-capture action is Settings > General > `After capture`; each item says which one it needs.

## Launch and image capture
- [ ] Launch with Hide Desktop Icons on [root: `start`, `covers`]. Menu > `Hide Desktop Icons`: the icons and widgets go and the item has a checkmark. Quit TidyShot and open the Debug build again: within a second the desktop is covered again, the item has its checkmark, the menu bar icon is the camera viewfinder, no other window opens, `Reveal Last Capture` is greyed, and ⌃⇧4 opens the selection overlay (the shortcuts are registered). Leave Hide Desktop Icons on; the URL item near the end turns it off.
- [ ] Capture Area: the file, the card and the clipboard [`+Capture`, `+Save`, `+Overlay`]. After capture `Save and copy image`. ⌃⇧4 and drag an area: the shutter plays, `Screenshot saved` posts, a PNG is in the save folder (`sips -g pixelWidth` reads the area's width times the display scale), the clipboard holds the image (Preview > File > New from Clipboard), and a card with the thumbnail and `Saved` shows at the corner. Recent Captures lists the capture, and `Reveal Last Capture` is enabled and selects the file in Finder.
  (suite, in part: CoordinatorCaptureSaveTests.aSaveAndCopyImageCaptureSavesCopiesAndAsksForNoDestination; by hand: ⌃⇧4
  drag and pixel width (`CAPSRC`), card with thumbnail and `Saved` (`SCREENS`), `Reveal Last Capture` (`WORKSPACE`), the
  audible shutter)
- [ ] All-in-One Timer and Scrolling [`+Capture`]. ⌃⇧1, drag a rect, click Timer: the countdown runs on the rect and then the capture is saved, with neither the countdown nor a card in it. While it counts down the menu's capture items are disabled; afterwards they are enabled again. ⌃⇧1 again, drag a rect at least 100 pt tall, click Scrolling: the scrolling panel opens on that rect; Start, scroll slowly, Done: a tall PNG is saved and its card shows. Start a scrolling session once more and Cancel it: nothing is saved and the capture items are enabled again.
- [ ] Capture Text [`+Capture`]. ⌃⇧7 and select a paragraph of text: `pbpaste` prints it, `Text copied` posts, and no file, card or Recent Captures row appears.

## Upload, editor, pins and delete
- [ ] An upload-only capture [`+Upload`, `+DragOut`, the observation path]. After capture `Upload only, keep no local file`; make the upload slow (see Setup). Capture an area. While it uploads the menu bar icon is the up-arrow circle (also with the menu open) and it goes back to the camera when the upload ends. The card goes to `URL copied`, the clipboard holds the URL, and the URL shows the capture. Nothing is in the save folder and `$D/pending/` has no file for it. Drag the card out onto an open Finder folder: a PNG named after the object key (for example `aSIS7.png`) lands there and opens as the capture, and the card closes.
- [ ] Retry Failed Uploads with no destination: one notification [`+Upload`]. Settings > Upload > `Forget Credentials`; After capture `Upload only, keep no local file`. Capture twice: one `Upload not configured` notification in all (`Set up a destination in Settings > Upload, then retry from Recent Captures. The image is on the clipboard.`), not one per capture; both cards say `Upload failed`; the menu gains `Retry Failed Uploads`. Choose it: one `Upload not configured` notification, `Set up a destination in Settings > Upload, then retry.`, not one per record. Enter the credentials in Settings > Upload and Save, then choose `Retry Failed Uploads` again: both rows upload and the menu item goes.
  (suite, in part: CoordinatorCaptureSaveTests.withNoDestinationTwoCapturesCopyTheImageAndPostOneNotice,
  CoordinatorUploadTests.retryFailedUploadsSaysOnceWithoutCredentialsAndEnqueuesWithThem; by hand: cards saying `Upload
  failed` (`SCREENS`), the menu item (`STATUSMENU`))
- [ ] Annotate the newest card, Save, then Upload [`+Editor`]. After capture `Save and copy image`. Capture an area and click the card's Annotate (the pencil) at once: the editor opens without a pause. Draw a stroke: the close button shows the unsaved dot. ⌘S: the dot clears, the file in the save folder shows the stroke (Quick Look) and nothing uploads. ⌘U: the editor closes, the row uploads, the URL replaces the clipboard, and the URL shows the stroke.
  (suite, in part:
  CoordinatorEditorUploadTests.annotateTheNewestCardSaveThenUploadWritesTheFileThenUploadsAndCopiesTheURL; by hand: the
  unsaved dot and the window closing (`EDPLACE`), and the URL in the real bucket; the URL showing the stroke is the PUT
  body)
- [ ] Pin, then the pin menu's three items [`+Pins`, `+RecordActions`]. Capture an area and click the card's pin (`Pin to screen`): a pin opens over the spot the area came from. Click the card's pin again: the same pin comes forward and no second one opens. The menu now has `Close Pinned Screenshots`. Right-click the pin: `Copy Image` puts the image on the clipboard and posts `Image copied`; `Save As…` opens a panel that suggests the capture's own name (Cancel it); `Annotate` opens the editor. Choose `Close Pinned Screenshots`: the pin closes and the menu item goes.
  (suite, in part: CoordinatorEditorTests.annotateFromACardOrRecentCapturesLeavesNothingToRestore,
  CoordinatorRecordActionsTests.copyImageReadsTheFileOrDownloadsTheObject,
  CoordinatorSaveAsTests.saveAsOfASavedImageCopiesItsBytesAndChangesNothingElse (the Save As… item's suggestion and
  Cancel, through `saveAs(recordID:)`, which the pin's menu calls); by hand: the pin, its second click and `Close Pinned
  Screenshots` (`PINS`, `SCREENS`), reaching Save As… through the pin's menu (`PINS`), and the panel itself; the pin
  menu's Annotate is the card's `openEditorAfterMenuTracking`)
- [ ] Delete during an upload [`+Delete`, `cancelUpload`]. After capture `Upload and copy URL`; make the upload slow. Capture an area and, while the card shows progress, click its trash (tooltip `Cancel the upload and delete this capture`). Cancel in the alert changes nothing and the upload goes on. Click the trash again and choose Delete: the card closes, the menu bar icon goes back to the camera, the row leaves Recent Captures, the file leaves the save folder, the thumbnail leaves `$D/thumbnails/`, no object for it is left in the bucket (list its prefix), and no `Not deleted` notification posts.
  (suite: CoordinatorDeleteTests.deleteDuringAnUploadCancelsItThenDeletesTheReservedKey)
- [ ] Restore Closed Overlay [`+Overlay`, and `init`'s `overlay.onDidClose`]. Quit and open TidyShot: `Restore Closed Overlay` is greyed (no card has closed this launch). Take two captures and close both cards with their close buttons: the item is enabled. Choose it: the newest closed card comes back at the corner of the stack with its thumbnail and status. Choose it again: the other one comes back. The item is greyed again.

## Retention
- [ ] Retention pruning of a pinned upload-only capture that has uploaded [`init`'s `history.didPrune`, `+Delete`'s `removeFiles(ofPruned:)`, `+Pins`]. A Recent Captures row has no Pin and a pin ends with the app, so the capture is aged with the clock and not with `history.json`. After capture `Upload only, keep no local file`; capture an area and wait for `URL copied`. In `$D/history.json` find the first record's `thumbnailFileName` and check the file is in `$D/thumbnails/`. Click the card's pin. Settings > Overlay > `Keep history for 1 days`. In System Settings > General > Date & Time turn off `Set time and date automatically` and move the date two days ahead (or leave TidyShot running for a day). Set After capture to `Save and copy image` and take a new capture: the old record leaves Recent Captures, its pin closes, its thumbnail leaves `$D/thumbnails/`, and `$D/pending/` has no file for it (an uploaded upload-only capture's temporary file is already gone, and retention keeps every capture whose temporary file is its only copy). Turn `Set time and date automatically` back on and set `Keep history for` back to 30 days.

## Recording and quit
- [ ] Record Screen with Clop on [`+Recording`, `+Upload`, `+RecordActions`]. Settings > General > Optimization > `Optimize images and videos with Clop` on, Clop running; After capture `Upload and copy URL`. ⌃⇧8, drag an area, wait out the count-in, record about 10 s with something moving, press Stop. The card shows the poster, says `Optimizing…`, uploads and says `URL copied`; the Recent Captures row says `Optimizing…` while Clop runs. Right-click the card, Copy File, and paste into a Finder folder (⌘V): an MP4 that plays. Set the Clop setting back if you had it off.
- [ ] Quit during a recording [`+Recording`, quit]. After capture `Save and copy image`. Start a recording, wait 10 s and choose Quit TidyShot: it quits within a few seconds, with no hang, no prompt, no card and no notification. The MP4 is in the save folder. Open TidyShot again: the recording is the top row of Recent Captures and it plays.
- [ ] Quit with an unsaved editor [`+Editor`, quit]. Capture an area, Annotate, draw a stroke and choose Quit TidyShot. The editor comes forward with its sheet (`Do you want to save the changes made to …?` with Save, Cancel and Don’t Save). Cancel: TidyShot stays open and the editor still has the stroke and its unsaved dot. Quit again and choose Don’t Save: TidyShot quits.

## URL commands and the status icon
- [ ] A `tidyshot://capture-area` URL with a rect, and `tidyshot://toggle-desktop-icons` [root, `URLCommandTarget`]. After capture `Save and copy image`. `t 'capture-area?x=0&y=0&width=300&height=200'` captures the bottom-left corner of the display under the pointer with no overlay: a PNG whose `sips -g pixelWidth -g pixelHeight` reads 300 x 200 times the display scale, and a card. `t toggle-desktop-icons`: the covers go and the menu item loses its checkmark. Run it again: the covers return and the checkmark is back. Choose `Hide Desktop Icons` in the menu to end with it off.
- [ ] `record.circle` in the menu bar while recording [the observation path]. After capture `Save and copy image`. Start a recording (⌃⇧8, or Record Fullscreen from the menu): the menu bar icon is the record circle, the menu's first item is `Stop Recording  ⌃⇧8`, `Record Screen` and `Record Fullscreen` are gone and every capture item is disabled. Press Stop: the icon goes back to the camera and the capture items are enabled.

## Put back
- [ ] After capture to your usual choice, `Keep history for` 30 days, `Set time and date automatically` on, `Optimize images and videos with Clop` and the credentials as you keep them, `Hide Desktop Icons` off. Delete the test captures you do not want to keep.
