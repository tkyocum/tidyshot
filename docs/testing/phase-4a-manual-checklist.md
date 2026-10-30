# Phase 4a manual test checklist

Run after any change to the crosshair, the editor, the Annotate buttons, or the save, copy, upload
or delete paths. Automated tests cover the editor model and undo, the geometry, the tile cache,
the decision tables for Save, Upload, the clipboard and the shortcuts, and the redaction export end
to end (`RedactionExportTests`); everything here needs real windows, a real bucket and eyes.

Phase 4b added six tools (Ellipse, Line, Pencil, Highlighter, Text, Crop). Where an item below lists
the six 4a tools, the toolbar and tool-letter items of `phase-4b-manual-checklist.md` list all
twelve; this checklist's other sections are unchanged.

Setup: fresh build, Screen Recording granted, save folder set to Desktop, a working destination
saved in Settings > Upload (served through CloudFront for the Caches section), "Show notification"
on in Settings > General, "Show Quick Access overlay after capture" on in Settings > Overlay, and
Network Link Conditioner installed. History holds at least:
- a capture saved without upload ("Save and copy image");
- a capture uploaded with "Upload and copy URL";
- an upload-only capture that finished uploading ("Upload only, keep no local file");
- an upload-only capture whose upload failed (Wi-Fi off while capturing), with `pending/<UUID>.png`;
- a capture uploaded with the Phase 2 build (before Phase 3), its file still in the save folder.

`pending/` and `history.json` are in
`~/Library/Containers/io.tky.tidyshot/Data/Library/Application Support/TidyShot/`. Redact only
made-up secrets (for example `echo SECRET-TOKEN-0123456789` in Terminal). Where an item checks a
link with `curl`, use a link no browser has opened unless the item says otherwise: CloudFront
keeps what it has served (see Caches).

## Crosshair and loupe
- [ ] `⌃⇧4` over a white window (a new TextEdit document): the crosshair and the loupe's cross are black with a thin white halo. Over a dark window (Terminal) both are white with a black halo. Moving between the windows switches both; the loupe's ring stays white.
- [ ] For the first moment, before the snapshot arrives, the crosshair is white with a black halo and no loupe is drawn.
- [ ] Drag a rectangle that ends over the white window: its border is black with a white halo. One that ends over the dark window: white with a black halo.
- [ ] Over a photo or a mid-grey area the crosshair stays readable. Escape cancels.

## Annotate from the overlay
- [x] The overlay's right column shows Annotate (a pencil in a circle, tooltip "Annotate") above Close and Delete. The overlay is the same size as before.
  (obsolete: Phase 6a moved Close to a hover badge at the top-left of the card and Phase 6b put Pin between Annotate and
  Delete; the Phase 6a checklist checks the column)
- [ ] "Save and copy image": capture, then Annotate. The overlay closes and the editor opens key and in front, at fit zoom, titled with the file name. It also comes to the front when Slack was frontmost.
- [ ] "Upload and copy URL", a large capture with Network Link Conditioner on a slow profile: Annotate while the overlay shows Uploading… opens the editor at once with the subtitle `Uploading…`. Save and Upload stay greyed until the upload finishes, then turn on.
- [ ] "Upload only, keep no local file": Annotate while uploading opens at once. Annotate after "URL copied" (the pending file is already gone) also opens at once, with no download.
  (suite, in part: EditorInputTests.retainedWinsForLatestCapture; the coordinator keeping `latestCapture` through an
  upload-only upload, so the record's id is the retained one, is not driven and stays by hand)
- [ ] Annotate a capture whose editor is already open (from its Recent Captures row): that window comes forward and no second window opens.
- [ ] Editors on two captures: the second opens 22 points down and to the right of the first, on screen. (suite, in
  part: EditorWindowGeometryTests.cascadeOffsetsAndStaysOnScreen; that it cascades from the front editor
  (`NSApp.orderedWindows`) stays by hand)

## Annotate from Recent Captures
Each row has four buttons: Annotate (the pencil, tooltip "Annotate"), Copy URL, Copy Image and
Delete. Annotate closes the menu first, then the editor opens key and in front, also when Slack was
frontmost.
- [ ] Saved capture, never uploaded: the editor opens from the file in the save folder.
- [ ] Capture uploaded with "Upload and copy URL": opens from the file in the save folder.
- [ ] Upload-only capture whose upload failed: opens from `pending/<UUID>.png`.
- [ ] Upload-only capture that finished uploading: after a moment (it downloads the object) the editor opens, titled `Capture <time>`. With Wi-Fi off: no window, and a `Could not open the capture` notification gives the reason.
- [ ] Capture from before Phase 3: opens from its file. Move the file out of the save folder and press Annotate: no window, and `Could not open the capture` with "The local file could not be read." Put the file back.
- [ ] Capture uploaded with "Upload and copy URL" whose file was renamed in Finder: the editor still opens, from the downloaded object. Rename the file back.
- [ ] Settings > Overlay, turn "Show Quick Access overlay after capture" off. Capture once in each after-capture mode: no overlay appears, and Annotate on the new row opens the editor each time (for "Upload only, keep no local file", also while it is still uploading). Turn the overlay back on.
- [ ] Stale retained image: with the overlay on, take capture A (leave its overlay open), then take capture B. Open the editor on A from its Recent Captures row: it shows A's pixels, not B's. Then delete a row whose overlay is still open: that overlay closes, and Annotate on a different row still opens the right capture.

## Tools
- [ ] The toolbar shows, in order: the tools (Select, Redact, Pixelate, Blur, Rectangle, Arrow), the colour button, the options button, the zoom pop-up, Copy, Save (a downward arrow) and a prominent Upload (a cloud with an up arrow). Copy, Save and Upload are plain buttons with no menus; their tooltips read `Copy the image (⌘C)`, `Save (⌘S)` and `Upload and copy the link (⌘U)`. Each tool's tooltip names its letter.
- [ ] Narrow the window as far as it goes, with a small capture and with a long file name in the title: every toolbar item still shows, with no » overflow chevron at the right.
- [ ] With the canvas focused, `V` `D` `X` `B` `R` `A` pick Select, Redact, Pixelate, Blur, Rectangle and Arrow, and the toolbar follows.
- [ ] Redact: a drag makes a black box. Shift makes a square and Option draws from the centre; pressing or releasing either mid-drag changes the box without moving the mouse. Escape mid-drag drops the box. A click without a drag adds nothing. The new box is selected.
  (suite: CanvasToolTests.transientUpdatesDuringDrag, .shiftViaFlagsChangedSquares, .optionDrawsFromCentre,
  .commitOnMouseUpOnly, .tinyDragDiscarded, .newShapeSelected, EditorModelTests.selectAllAndCancelOnlyChangeSelection,
  EditorPaletteTests.standardDefaultsAreRedBlackFourEightTen)
- [ ] Pixelate: a drag makes a mosaic of equal squares, 10 points by default. A second region over the same text, offset by a few pixels, has squares that line up with the first. The options slider (6 to 32 pt) changes a selected mosaic live.
- [ ] Blur: a drag blurs the area. The options slider (4 to 24 pt) changes a selected blur live. (suite:
  EditorModelTests.sliderBurstOnSelectedBlurIsOneStep, RedactionRendererTests.blurTileEqualsFullImageBlurCrop,
  EditorPaletteTests.standardDefaultsAreRedBlackFourEightTen)
- [ ] Rectangle: red and 4 pt by default, the stroke inside the dragged box. Keys `1` to `6` set 2, 3, 4, 6, 8 and 12 pt on the selection and on the tool.
- [ ] Arrow: the tail is where the drag starts and the head where it ends; Shift snaps it to 45 degrees. (suite:
  CanvasToolTests.arrowShiftSnaps45, ArrowGeometryTests.headSymmetricAboutShaft)
- [ ] Select: a click on an arrow drawn over a blur picks the arrow; a click on the blur away from the arrow picks the blur (dashed outline). A drag moves the selection and Shift locks the move to one axis. Boxes have 8 handles and arrows 2; dragging a handle resizes. A click on empty space deselects. Delete removes the selection. `←` moves it one image pixel, `⇧←` ten. Escape deselects and never closes the window.
  (suite, in part: CanvasToolTests.selectPicksTopmost, .moveCommitsOnceWithDelta, .shiftLocksMoveAxis,
  .handleDragResizes, .clickEmptyDeselects, HitTesterTests.resizedByEachOfEightHandles, .arrowEndpointHandlesMoveEnds,
  EditorModelTests.deleteSelectionCommitsOnce, .selectAllAndCancelOnlyChangeSelection,
  KeyRoutingTests.nudgeOneOrTenPixels; the dashed outline's look stays by hand)
- [ ] `⌘.` behaves like Escape: during a drag it abandons the drag, and otherwise it deselects. It never closes the window.
- [ ] The colour button shows the current colour as a filled circle. Its popover has ten swatches (black, red, orange, yellow, green, teal, blue, purple, pink, white) and a colour picker without opacity. A swatch recolours the selection and the active tool. With Redact active it sets the redact colour, and the shape colour stays.
- [ ] Choose blue and 8 pt, close the editor and open another: Rectangle starts blue at 8 pt. Quit and relaunch: still blue at 8 pt. Set red and 4 pt again.

## Redaction in the saved file
Do these on the 2x display and again on a 1x display (an external non-Retina display, or a
resolution without HiDPI); skip the 1x run if neither is available and say so.
- [ ] "Save and copy image": capture a Terminal window with three lines of made-up secret. Annotate, Redact the first line, Pixelate the second, Blur the third, ⌘S. Open the saved PNG in Preview and zoom in until single pixels show (about 400%): the redaction is solid black to its edges with no trace of text along its border, the mosaic is uniform squares, and the blur is unreadable.
  (suite, in part: RedactionExportTests.redactRegionHoldsOnlyFillAfterPNGRoundTrip,
  .pixelateRegionIsBlockUniformAndDiffersFromSource, .blurRegionDiffersFromSource; the suite runs at scale 2 only, so
  the 1x display run and judging the blur unreadable stay by hand)
- [ ] `sips -g pixelWidth -g pixelHeight -g dpiWidth <file>`: the same pixel size as before the edit, and `dpiWidth` 144 on the 2x display, 72 on the 1x display.
  (suite, in part: ImageEncoderTests.retinaScaleWrites144DPI, .standardScaleWrites72DPI,
  RedactionExportTests.outsideEffectsEqualBaseAndScaleIsTwo; that a real 1x capture saves at scale 1 stays by hand)
- [ ] Redact one word. Draw a Blur that covers half of the redaction and a second Blur that only touches its edge. ⌘S, and at 400% in the saved PNG both blurs show grey and black from the redaction but no letter shapes from under it.
  (suite: RedactionExportTests.blurOverRedactLeaksNoSourcePixel, RedactionRendererTests.blurOverEarlierRedactBlursBlack,
  .blurNextToRedactSamplesRedactInMargin)
- [ ] Move the redaction: the blur over it follows at once. (suite:
  RedactionTileCacheTests.movingEarlierEffectRerendersOverlappingLater)
- [ ] A window capture (`⌃⇧2`) with a redaction keeps its transparent rounded corners in the saved PNG. (suite:
  RedactionRendererTests.alphaZeroCornerStaysZero, EditorFlattenerTests.alphaZeroCornerKept)

## Undo
- [ ] Draw a redaction, a mosaic and a rectangle: ⌘Z three times removes them newest first, and ⇧⌘Z three times brings them back.
  (suite: EditorModelTests.twoCommitsTwoUndos, .undoRestoresSnapshotAndRedoReapplies,
  KeyRoutingTests.shortcutTableMatchesExpectedChords)
- [ ] Select the rectangle, press `→` ten times and `⇧↓` three times, then ⌘Z once: it is back where it started. ⇧⌘Z moves it again.
  (suite: EditorModelTests.coalescedNudgesAreOneStep, .undoRestoresSnapshotAndRedoReapplies,
  KeyRoutingTests.nudgeOneOrTenPixels)
- [ ] Nudge one shape, click another and nudge that: the first ⌘Z undoes only the second shape's nudges, the next ⌘Z the first shape's.
  (suite: EditorModelTests.differentCoalescingKeyStartsNewStep, .coalescedNudgesAreOneStep)
- [ ] Drag the radius slider of a selected blur for a few seconds: one ⌘Z restores the radius. (suite:
  EditorModelTests.sliderBurstOnSelectedBlurIsOneStep)
- [ ] Zoom in, change the tool, and with nothing selected change the colour, then ⌘Z: only the last edit is undone; zoom, tool and colour stay.
  (suite: EditorModelTests.selectionAndZoomNotUndone, .applyColorToSelectionIsUndoable)
- [ ] After an edit the close button shows the unsaved dot; undoing back to the opened state clears it. (suite, in part:
  EditorModelTests.hasUnsavedChangesFollowsMarkSavedAndUndo; the window's dot following the model stays by hand)

## Zoom on a 5K capture
- [ ] `⌃⇧3` on the 2x display (5120 by 2820 pixels on a 2560 by 1410 point screen), then Annotate: the window fits on the screen with the whole picture showing.
  (suite: EditorWindowGeometryTests.clampedToNinetyPercent, CanvasTransformTests.fittingNeverExceedsNaturalSize,
  .fittingCentres)
- [ ] ⌘1 shows the picture at its natural point size and ⌘0 fits it again. ⌘= and ⌘- zoom around the window centre. The zoom pop-up's Fit, 50 %, 100 %, 200 % and 400 % each work.
- [ ] Pinch and ⌘-scroll zoom around the pointer, and scrolling pans. Zoom stops at a limit each way and the picture never vanishes.
- [ ] At 400% pixels are hard-edged squares, redactions and mosaics are crisp, and panning shows no seams, stripes or blank tiles.
- [ ] Dragging out a blur at 400% and at fit follows the mouse without stutter.

## Save
- [ ] Saved capture: Redact, ⌘S. The same file in the save folder now shows the redaction (Quick Look), no new file appears, the unsaved dot clears, and the row's thumbnail shows the redaction the next time the menu opens. Nothing is uploaded.
- [ ] Capture uploaded with "Upload and copy URL": ⌘S rewrites the file only. The subtitle reads `The uploaded copy still shows the original. Upload to replace it.` and the link still shows the original.
- [ ] Capture from before Phase 3: ⌘S rewrites its file, with the same subtitle.
- [ ] Upload-only capture that finished uploading: Save is on. Redact, then the Save button (or ⌘S): a save panel opens as a sheet, named by the file name template plus `.png`, in the save folder. Save there: the PNG is written, a `Saved` notification names it, the unsaved dot clears, and nothing uploads (no new link on the clipboard, no new Recent Captures row).
- [ ] Upload-only capture whose upload failed: Redact, ⌘S rewrites `pending/<UUID>.png`. Wi-Fi on, Retry Failed Uploads: the link shows the redaction.
- [ ] Lock the saved file (Finder, Get Info, Locked), edit, ⌘S: a `Not saved` notification with the reason, the unsaved dot stays, and the edited image is on the clipboard. Unlock the file.

## Save As…
- [ ] Saved capture: edit, then ⇧⌘S. The save panel suggests the capture's own file name in the save folder. Choose the Desktop and another name: the PNG appears there with the edit, `sips -g dpiWidth` gives 144 on the 2x display, and the original file in the save folder is unchanged. No Recent Captures row is added, no overlay or shutter sound, nothing uploads, and the editor keeps its title. The unsaved dot clears.
- [ ] With Show notification on, the `Saved` notification names the file; clicking it reveals the file in Finder. With it off, nothing is posted.
- [ ] Cancel in the panel: nothing is written and the unsaved dot stays.
- [ ] Settings > General, set the file name template to `shot-{counter}`. On an upload-only capture that finished uploading, ⇧⌘S suggests `shot-<n>.png` with the counter as it stands; save it, then take a capture: its name uses the next number, so none was skipped. Set the template back.
- [ ] ⇧⌘S on a saved capture and save over its own file (confirm Replace): it behaves as ⌘S, so the row's thumbnail shows the edit, and on an uploaded capture the subtitle says the uploaded copy still shows the original.
- [ ] Edit, ⌘U, and keep drawing before the window closes (slow machine or large capture; may be hard to hit): if the drawing changed during the call, the editor beeps and stays open with the newer edit unsaved.
- [ ] In the panel, pick an existing PNG and confirm Replace: it is replaced. Pick a locked file (Finder, Get Info, Locked) and confirm Replace: a `Not saved` notification with the reason, and the unsaved dot stays. Unlock it.

## Copy
- [ ] ⌘C, ⇧⌘C and the toolbar's Copy button each post `Image copied`. Notes and Preview (File > New from Clipboard) paste the edited image at point size, not double. The window stays open.
- [ ] With "Show notification" off, Copy posts nothing. Turn it back on.

## Clipboard
- [ ] "Save and copy image" with "Copy image to clipboard" on: capture a made-up secret, Annotate, Redact, ⌘S. Preview, File > New from Clipboard: the redacted image.
- [ ] The same with ⇧⌘S in place of ⌘S, saving to the Desktop: the clipboard holds the redacted image.
- [ ] Capture, copy some text in TextEdit, then Annotate, Redact, ⇧⌘S: the clipboard still holds the text.
- [ ] Capture, copy some text in TextEdit, then Annotate, Redact, ⌘S: the clipboard still holds the text.
- [ ] "Upload and copy URL" with no destination (Forget Credentials in Settings > Upload): capture (the image goes to the clipboard), Annotate, Redact, ⌘S: the clipboard holds the redacted image. ⌘U posts `Upload not configured`, changes nothing, and the editor stays open. Enter the credentials again.
- [ ] "Upload and copy URL" with "Also copy image" on: capture, Annotate, Redact, ⌘U. The editor closes at once; when the upload finishes the clipboard holds the URL.

## Upload
- [ ] Capture uploaded with "Upload and copy URL": Redact, then the Upload button. The editor closes at once with no unsaved-changes sheet, and the row shows the upload running. When it finishes the clipboard holds the same URL as before, the link shows the redaction, and the file in the save folder shows it too.
- [ ] Upload-only capture that finished uploading: Redact, ⌘U. The editor closes, and when the upload finishes the link to paste is on the clipboard and shows the redaction.
- [ ] `curl -sI <url>` after that replace includes `cache-control: no-cache`; for a capture that was never replaced there is no `cache-control` line.
  (suite, in part: UploadQueueTests.fixedKeyPassesCacheControl, S3DestinationTests.cacheControlHeaderIsSignedWhenSet,
  .noCacheControlByDefault; `startUpload` building the replace with `no-cache` has no test, and what `curl` sees on the
  real bucket stays by hand)
- [ ] Another uploaded capture whose link was never opened: edit, then Upload as New (⌥⌘U; it has no button). The editor closes, a new URL on the clipboard shows the edit, `curl -I <old url>` gives 403 or 404, and the row's link button copies the new URL.
- [ ] Saved capture never uploaded: ⌥⌘U beeps. ⌘U uploads it for the first time, closes the editor and copies a new link.
- [ ] Interrupted replace keeps Upload as New: after the "Quit during a replace" item below, relaunch (the row shows "· Upload failed" and its link still copies). Annotate on that row: Upload as New stays enabled and ⌥⌘U uploads to a new key, copies the new link and deletes the old object (`curl -I <old url>` gives 403 or 404).
- [ ] Capture from before Phase 3: ⌘U shows the notice `The earlier upload stays in the bucket.` and makes a new link; `curl -I <old url>` still gives 200.
- [ ] Optional, with a second bucket: point Settings > Upload at it, then ⌘U on a capture uploaded to the first. The notice reads `The destination changed, so this uploads as a new link.`, the link is in the second bucket, and the old object is gone from the first. Point the settings back.
- [ ] Enter a wrong secret access key in Settings > Upload and press Save, then ⌘U on an uploaded capture: the editor closes. After the retries: a notification `Upload failed. The link still shows the earlier image.`, and the row still copies the old URL. Annotate on the row reopens the edited image, with the subtitle `The uploaded copy still shows the original. Upload to replace it.` Enter the right key, ⌘U: the same URL now shows the edit.
- [ ] Folder change with a bad key: Settings > General, Choose… another save folder. Open an older capture (saved in the old folder) from Recent Captures, Redact, then enter a wrong secret access key in Settings > Upload and press ⌘U. The editor closes. After the failure, `pending/<UUID>.png` holds the redacted image and the file in the old folder is unchanged. Enter the right key, Retry Failed Uploads: the link shows the redacted image, not the original, and `pending/<UUID>.png` is gone. Choose the original folder again.
- [ ] The same wrong key, ⌘U on an upload-only capture that finished uploading. The editor closes. After the failure `pending/<UUID>.png` exists and holds the edit. Annotate on the row reopens it with the edit, and the subtitle says the uploaded copy still shows the original. Right key, ⌘U: the same URL shows the edit and `pending/<UUID>.png` is gone.
- [ ] Quit during a replace: Network Link Conditioner on a slow profile (a custom profile with a few hundred Kbps uplink), ⌘U on a large uploaded capture (the editor closes), and while the row shows the upload running choose Quit TidyShot. Relaunch: the row shows "· Upload failed", and clicking the row or its link button still copies the old URL. Network Link Conditioner off, Retry Failed Uploads: the URL is unchanged and shows the edit.
- [ ] Slow profile again, ⌘U, then Delete on the row while the replace runs: Delete cancels the upload and removes the object (`curl -I <url>` gives 403 or 404).

## Caches
- [ ] Redact before sharing: capture a made-up secret with "Upload and copy URL", do not open or paste the URL, Annotate from the overlay, Redact, ⌘U. Then open the link in a browser: it shows the redaction.
- [ ] Replace after opening: capture, open the link in a browser (it shows the secret), Annotate from the row, Redact, ⌘U. Reloading the link may still show the original for a while, from the browser or CloudFront; `curl -sI <url>` shows `x-cache: Hit from cloudfront` and an `age` header while CloudFront serves its copy. This is the documented caveat, not a failure.
- [ ] Upload as New on that capture: the new link shows the redaction. The old link may still be served from CloudFront's copy until it expires, although the object is gone from the bucket.
- [ ] Only if the bucket has versioning: after a replace, `aws s3api list-object-versions --bucket <bucket> --prefix <key>` lists two versions, the original being the older one.
- [ ] The first successful replace after launch posts `Replaced. Copies opened before now may stay cached for a while.` A second replace in the same launch does not, and neither does Upload as New or a first upload. Quit and relaunch: the next replace posts it again.

## Availability while uploading, deleting, or after a folder change
- [ ] Slow profile, "Upload and copy URL": capture something large and press Annotate on the overlay while it uploads. The subtitle reads `Uploading…`, ⌘S, ⌘U and ⌥⌘U beep and do nothing, and Save and Upload are greyed in the toolbar; ⌘C and ⇧⌘C work and ⇧⌘S opens the save panel. When the upload finishes they turn on again.
- [ ] With an editor open, press Delete on its row and leave the alert open: the editor's Save and Upload grey out at once, the subtitle reads `Deleting…`, and ⌘S beeps. Cancel: they turn on again and the subtitle returns to what it was.
- [ ] Delete again and confirm: the subtitle reads `This capture was deleted. Copy and Save As still work.`, Save and Upload stay greyed, ⌘C copies, and ⇧⌘S opens the save panel and writes the PNG.
- [ ] Editor open on a capture in the save folder: Settings > General, Choose… another folder. The subtitle gives the reason at once, and ⌘S now opens the save panel instead of writing over the file (Cancel it). ⌘W's Save opens the save panel (Cancel it). ⌘U uploads the edit and closes the editor; the file in the old folder is not rewritten, and the edit is in `pending/<UUID>.png` until the upload finishes. Choose the original folder again; on another capture there, ⌘S writes over the file without a panel.

## Closing and quitting
- [ ] ⌘W on an editor with no changes closes it at once.
- [ ] With changes, ⌘W (or the close button) shows a sheet: `Do you want to save the changes made to “<title>”?`, `Your changes will be lost if you don’t save them.`, and Save, Cancel and Don’t Save. Cancel keeps the window. Don’t Save (or ⌘D) closes it and leaves the file as it was. Save writes the file and closes.
- [ ] On an upload-only capture that finished uploading, the first button reads Save; it opens the save panel, and the window closes once the PNG is written. Cancel in the panel keeps the window open with its changes.
- [ ] While the capture uploads (slow profile, Annotate on the overlay during the upload) or after its row's Delete, the first button reads Save As… and opens the save panel.
  (suite, in part: EditorSaveTargetTests.closeSheetSaveButton; the button opening the save panel stays by hand)
- [ ] Quit TidyShot from the menu with a changed editor: the sheet appears on it. Cancel: TidyShot keeps running and the editor stays open. Quit again, Don’t Save: TidyShot quits.
- [ ] Quit with only unchanged editors open: TidyShot quits at once. (suite:
  QuitHoldTests.idleWithNoUnsavedEditorDoesNotHold)
- [ ] The green button takes the editor full screen and back.

## History pruning (do this last)
This drops every capture older than a day from history; files in the save folder and objects in
the bucket stay.
- [ ] Quit, set one record's `timestamp` in `history.json` to two days ago, relaunch, and open that capture from its row. Settings > Overlay, set Keep history to 1 day, then take a new capture: the editor's subtitle reads `This capture was deleted. Copy and Save As still work.`, Save and Upload are greyed, and ⇧⌘S still opens the save panel. Set the retention back.
