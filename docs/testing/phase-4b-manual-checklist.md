# Phase 4b manual test checklist

Run after any change to the editor's tools, the canvas, the toolbar, crop, text, the keyboard
handling or the accessibility elements. Automated tests cover the model and undo, the geometry
(hit testing, smoothing, text layout, crop), the shortcut table, the flattener's pixels for every
tool and the toolbar width arithmetic; everything here needs real windows and eyes. The 4a
checklist (`phase-4a-manual-checklist.md`) still covers redaction, Save, Save As…, Copy, Upload,
caches, availability and closing; run it too after a change to those paths.

Setup: fresh build, Screen Recording granted, save folder set to Desktop, a working destination
saved in Settings > Upload, "Show notification" on in Settings > General, "Show Quick Access
overlay after capture" on in Settings > Overlay, Network Link Conditioner installed. Take these
captures first, so every section has something to draw on:
- a Terminal window with a few lines of dark text on a white background (a TextEdit window works)
  and a few lines of made-up secret (`echo SECRET-TOKEN-0123456789`), saved with "Save and copy
  image";
- the same kind of capture with "Upload and copy URL", and one with "Upload only, keep no local
  file" that has finished uploading;
- a second, different window capture with "Save and copy image", for the two-editor items;
- a window capture (`⌃⇧2`) with transparent rounded corners.

`history.json` is in `~/Library/Containers/io.tky.tidyshot/Data/Library/Application Support/TidyShot/`.
Where an item checks a link with `curl`, use a link no browser has opened. Draw only on made-up
data.

## Toolbar and keys
- [x] The toolbar shows twelve tools, in order: Select, Redact, Pixelate, Blur, Rectangle, Arrow, Ellipse, Line, Pencil, Highlighter, Text and Crop, then the colour button, the options button, the zoom pop-up, Copy, Save and Upload. Each tool's tooltip names its letter: `Select (V)`, `Redact (D)`, `Pixelate (X)`, `Blur (B)`, `Rectangle (R)`, `Arrow (A)`, `Ellipse (E)`, `Line (L)`, `Pencil (P)`, `Highlighter (H)`, `Text (T)`, `Crop (C)`.
  (obsolete: Phase 4c made it fourteen tools, with Spotlight after Blur and Counter after Text, and Phase 7c added a
  Background button after Options; the Phase 4a toolbar line now lists the current toolbar)
- [ ] Narrow the window as far as it goes, with a small capture and then with a long file name in the title (rename a capture to 60 characters first): all fourteen tools, the colour, options and Background buttons, the zoom pop-up, Copy, Save and Upload still show, with no » overflow chevron at the right. The title truncates before any item does. Widen the window and the layout returns.
- [ ] Repeat the narrowest-window check with the window full screen and back, and on a second display if one is attached.
- [ ] With the canvas focused, each letter (either case) picks its tool and the toolbar follows. Typing a letter while a text is being edited types the letter and does not change the tool. A letter pressed in the middle of a drag does nothing.
  (suite, in part: CanvasViewEventTests.aLetterPressedDuringADragKeepsTheTool, KeyRoutingTests.lettersSelectTools,
  .editingTextSuppressesLetters, EditorToolTests.toolForKeyIsCaseInsensitive; by hand: the toolbar following the tool)
- [ ] Choose a tool, then press `V`: Select is active and the drawing tool's cursor is gone.

## Ellipse and Line
- [ ] Ellipse (`E`): a drag draws an ellipse inscribed in the dragged box, red and 4 pt by default, the stroke inside the box. Shift draws a circle and Option draws from the centre; pressing or releasing either mid-drag changes the shape without moving the mouse. Escape mid-drag drops it. A click without a drag adds nothing. The new ellipse is selected, with 8 handles.
  (suite: EditorModelTests.makeAnnotationUsesToolSettingsInImagePixels, .selectAllAndCancelOnlyChangeSelection,
  EditorPaletteTests.standardDefaultsAreRedBlackFourEightTen, EditorFlattenerTests.ellipseStrokePixels,
  CanvasToolTests.ellipseShiftMakesCircleAndLineSnapsTo45, .optionDrawsFromCentre, .shiftViaFlagsChangedSquares,
  .commitOnMouseUpOnly, .tinyDragDiscarded, HitTesterTests.ellipseHitOnRingNotCentre)
- [ ] Select an ellipse: a click on its ring picks it; a click in the middle of an empty ellipse does not, and picks whatever is under it (a blur or the background). Dragging a handle resizes it, and Shift keeps it a circle.
  (suite: HitTesterTests.ellipseHitOnRingNotCentre, .effectSelectableOutsideDrawing, CanvasToolTests.handleDragResizes)
- [ ] Line (`L`): the drag start and end are the line's ends, with round caps and no arrowhead. Shift snaps to 45 degrees. The new line is selected with 2 handles; dragging a handle moves that end.
  (suite: EditorFlattenerTests.lineStrokePixels, CanvasToolTests.ellipseShiftMakesCircleAndLineSnapsTo45,
  .newShapeSelected, HitTesterTests.lineHitWithinWidth)
- [ ] Keys `1` to `6` set 2, 3, 4, 6, 8 and 12 pt on the selected ellipse or line and on the tool. A swatch from the colour button recolours the selection.
  (suite: EditorModelTests.widthAndColourApplyToTheSelectedShapeAndItsTool, KeyRoutingTests.digitsOneToSixPickWidths)
- [ ] Save, and open the PNG in Preview at actual size: the ellipse and the line match the editor in position, width and colour, and their edges are smooth.

## Pencil and Highlighter
- [ ] Pencil (`P`): a freehand drag draws a smooth line in the stroke colour and width, with no visible corners at fit zoom and at 400%. A fast scribble stays smooth and keeps up with the mouse. One stroke is one ⌘Z.
- [ ] A click, or a stroke that never gets 2 pt from where it started, adds nothing and never crashes. Escape mid-stroke drops it.
  (suite: CanvasToolTests.tinyOrCancelledStrokeLeavesNothing, EditorModelTests.strokeToolsKeepTheirOwnColourAndWidth)
- [ ] Select a stroke: a click within a few pixels of the line picks it, and a click inside a loop of the stroke does not. A drag moves the whole stroke; it has no handles, only a dashed outline. Delete removes it.
  (suite, in part: HitTesterTests.strokeHitWithinWidth, AnnotationDocumentTests.strokesMoveRecolourAndRoundTrip,
  CanvasToolTests.moveCommitsOnceWithDelta, SelectionOutlineTests.earlierKindsAreUnchanged,
  EditorModelTests.deleteSelectionCommitsOnce; the dashed outline's look stays by hand)
- [ ] Highlighter (`H`): a drag draws a wide yellow stroke, 12 pt, translucent (45% opacity). Draw it over the white page and over the dark text of the Terminal or TextEdit capture: the text under it stays fully readable and dark; the highlighter never lightens black text.
- [ ] Draw two highlighter strokes that cross: the crossing is darker than either stroke. One stroke that crosses itself is not darker where it crosses. A highlighter stroke over a dark Terminal background darkens it slightly and never turns it light.
- [ ] With the Highlighter active, a swatch from the colour button changes the highlighter's colour and the stroke stays translucent; the Pencil's colour is unchanged. Keys `1` to `6` change the Highlighter's width, not the Pencil's.
  (suite: EditorModelTests.strokeToolsKeepTheirOwnColourAndWidth, KeyRoutingTests.digitsOneToSixPickWidths)
- [ ] The preview follows the effects under it: draw a Blur over a line of text, then a highlighter stroke across the blur. With Select, drag the blur to a new place, resize it, and change its radius in the options popover: the area under the highlighter shows the blurred pixels throughout and afterwards, with no stale pixels left where the blur used to be. ⌘Z of the blur shows the unblurred text under the highlighter. Repeat with a Pixelate and with a Redact.
- [ ] The edges of a highlighter stroke in the editor have no lighter or darker halo compared with the middle, at fit zoom and at 400%, over a blur and over plain text.
- [ ] Save and open the PNG in Preview at 400%: the highlighter over the text and over the blur matches the editor (yellow over white, dark text unchanged), and the pencil line is smooth, not stepped.

## Text
- [ ] Text (`T`): a click on the canvas places a text box whose first line is centred on the click and starts editing, with a visible insertion point, in the stroke colour at 20 pt; typing appears at the size you will get in the export. Return (or Enter, or Tab) commits. The new text is selected, with a dashed outline. A drag with Text places nothing.
- [ ] Shift-Return (or ⌥Return) inserts a newline and Return then commits. Escape (or ⌘.) cancels: a new text disappears, and an edit of existing text restores the earlier string. Clicking elsewhere on the canvas commits, and that click does nothing else. Committing an empty text adds nothing.
- [ ] Keys `1` to `6`, with the Text tool active and not editing, set the size to 12, 16, 20, 28, 40 and 56 pt on the tool and on a selected text (one ⌘Z step per burst of digits, named `Text Size`). While editing, the digits type digits.
  (suite: KeyRoutingTests.digitsPickTextSizesForTextTool, EditorModelTests.reEditReplacesInPlaceAndBlankDeletes)
- [ ] The colour button recolours the selected text and the Text tool, and the text being typed. Choose a colour, place a text: it uses that colour.
  (suite: EditorModelTests.colourAppliesToTheSelectedTextAndTheTextBeingTyped, .textEditCommitsOnceWithoutEditorUndo)
- [ ] Click committed text with Text, or double-click it with Select: editing starts with the caret at the end of the existing string, at the same position and size. Change it and press Return: the text changes in place.
  (suite: CanvasViewEventTests.reEditingATextPutsTheCaretAtTheEndInTheTextsFrame,
  CanvasToolTests.textToolClickPlacesOrReEditsText, EditorModelTests.reEditReplacesInPlaceAndBlankDeletes)
- [ ] While editing, ⌘A selects the text in the box and not every annotation. ⌘C copies the selected characters; paste them into TextEdit to check, and the editor shows no `Image copied` notification. ⌘X cuts the characters. ⌘V pastes characters at the caret. ⌘D does not duplicate anything while editing.
- [ ] Undo while editing: type three words, ⌘Z removes typing step by step (the characters only), ⇧⌘Z restores them. No annotation is added or removed by those keys. The unsaved dot appears as soon as the typed text would change the capture, before it is committed.
- [ ] Undo after committing: draw a rectangle, place a text, commit it. ⌘Z removes the whole text in one step (`Add Text`, not letter by letter); ⌘Z again removes the rectangle; ⇧⌘Z twice brings both back. Edit an existing text and commit: ⌘Z restores the earlier string in one step (`Edit Text`). Clear a re-edited text and press Return: it is deleted, and ⌘Z brings it back.
  (suite: EditorModelTests.textEditCommitsOnceWithoutEditorUndo, .reEditReplacesInPlaceAndBlankDeletes,
  .twoCommitsTwoUndos)
- [ ] While editing, Save (⌘S), Save As… (⇧⌘S), Copy Image (⇧⌘C), Upload (⌘U), the zoom commands and ⌘W commit the text first: ⌘S writes a PNG that contains the text, and ⌘W with an uncommitted change shows the unsaved-changes sheet. Picking another tool in the toolbar commits; a tool letter types the letter.
- [ ] Select a committed text: a drag moves it, Delete removes it, `←` nudges it one pixel. The selection shows a dashed box that encloses the text and no handles.
  (suite: CanvasToolTests.aSelectedTextMovesAndDeletesAndHasNoHandles, KeyRoutingTests.nudgeOneOrTenPixels,
  SelectionOutlineTests.earlierKindsAreUnchanged)
- [ ] Parity with the export at 100% and 200%: type a text of two lines at 20 pt and a third line at 40 pt. Set the zoom pop-up to 100 %, take a ⌃⇧4 capture of the text in the editor, then ⌘S and open the saved PNG in Preview at actual size. Line breaks, glyph shapes and the text's width match to within a point. Repeat with the zoom pop-up at 200 %: the editor shows the same text twice as large, and the saved PNG is unchanged.
- [ ] Text over a redaction or a blur: the text draws above the effect, and a blur never blurs the text.
- [ ] A text near the right edge of the capture, partly outside it: the editor and the saved PNG both clip it at the image edge.

## Crop
- [ ] Crop (`C`): the selection goes, and the crop starts at the whole capture (or at the applied crop) with 8 handles and a readout of its size as W × H in image pixels (a Retina capture shows twice the points). Dragging a handle changes the rectangle and the readout, and the area outside it dims; dragging inside moves it (Shift locks the axis); dragging outside draws a new one (Shift squares, Option from the centre). It never extends outside the image.
- [ ] The unsaved dot appears once the draft differs from the applied crop. Return applies the crop as one `Crop` step and returns to the tool used before Crop; the canvas shows only the cropped area, fitted, and the rest of the window is plain window background. ⌘Z removes the crop in one step (⇧⌘Z applies it again). Escape while cropping drops the draft, leaves the capture as it was (an earlier crop stays), and returns to the earlier tool.
- [ ] ⌘Z while cropping keeps the draft in step: apply a crop with Return, press `C` (the draft starts at that crop), drag a handle to change it, then ⌘Z. The crop is undone and the draft goes back to the whole capture (the readout shows the full size). ⇧⌘Z moves the draft to the redone crop. Return then applies what the readout shows and does not bring an undone crop back. An undo that leaves the crop alone keeps the draft: draw a rectangle, press `C`, drag out a draft, then ⌘Z. The rectangle goes, and the draft and the readout stay as they were (⇧⌘Z brings the rectangle back, again without touching the draft).
  (suite: EditorModelTests.undoRestoresUncropped, .undoOfAnUnrelatedStepKeepsTheCropDraft,
  CropGeometryTests.readoutCountsExportedPixels)
- [ ] Draw a rectangle that straddles the crop's edge (draw it before cropping), then crop: the saved PNG contains only the part inside the crop.
  (suite: CropGeometryTests.flattenedSizeEqualsCrop)
- [ ] Saved pixel size: on a saved capture, crop to a readout of, say, 800 x 400, Return, ⌘S. `sips -g pixelWidth -g pixelHeight -g dpiWidth <file>` reports 800 x 400 (the readout, not the original size), and `dpiWidth` is 144 on the 2x display (72 on a 1x display). Quick Look shows only the cropped picture, and no new file appears.
  (suite: CoordinatorEditorSaveTests.saveWithACropWritesTheCroppedSizeAtTheCapturesScaleAndReopensCropped,
  EditorModelTests.undoRestoresUncropped, EditorFlattenerTests.pngRoundTripKeepsScaleTwo)
- [ ] Thumbnail: open the Recent Captures menu. The row's thumbnail shows the cropped picture with its new proportions, and the hover preview shows the cropped image. The row's pixel size in `history.json` (`pixelWidth`, `pixelHeight`) equals the crop.
- [ ] Reopen the cropped capture with Annotate: the editor opens the cropped file at its new size, with no crop pending, and Crop starts from the whole picture again.
  (suite: CoordinatorEditorSaveTests.saveWithACropWritesTheCroppedSizeAtTheCapturesScaleAndReopensCropped,
  EditorModelTests.undoRestoresUncropped)
- [ ] Uploaded pixel size: on a capture uploaded with "Upload and copy URL", crop, then the Upload button. When the upload finishes, `curl -s <url> -o /tmp/crop.png && sips -g pixelWidth -g pixelHeight /tmp/crop.png` reports the cropped size, the file in the save folder is cropped too, and `history.json` has the cropped `pixelWidth` and `pixelHeight`. The link is the same as before.
  (suite: CoordinatorEditorUploadTests.uploadWritesTheFileFirstThenReplacesTheLinksObject)
- [ ] Upload-only capture that finished uploading: crop, ⌘U. The link then serves the cropped size. (suite:
  CoordinatorEditorUploadTests.uploadOfAnUploadOnlyCaptureWritesPendingThenReplacesItsKey)
- [ ] Save As… (⇧⌘S) with a crop: the new PNG has the cropped pixel size, and the capture's own file is unchanged.
  (suite: CoordinatorEditorSaveTests.saveAsWithACropWritesACroppedCopyAndLeavesTheCaptureAlone)
- [ ] Copy (⌘C with nothing selected) with a crop: Preview, File > New from Clipboard, shows the cropped image at point size.
  (suite: CoordinatorEditorSaveTests.copyWithACropPutsTheCroppedImageAtPointSizeAndSaysImageCopied)
- [ ] Crop a redacted capture so that the redaction is partly outside: the saved PNG has no trace of the cropped-away part, and the part inside is still solid.
  (suite: RedactionExportTests.croppedExportKeepsRedactionAndHasCropSize)
- [ ] Crop of the window capture with transparent corners, keeping a corner: the corner stays transparent in the saved PNG.
  (suite: EditorFlattenerTests.aCropKeepingATransparentCornerKeepsItClear)
- [ ] A crop dragged back to the whole image and applied adds no undo step and saves at the original size. A draft cannot be made smaller than the tiny-drag size (2 pt), and nothing crashes trying.
  (suite: CanvasToolTests.aCropDraftStopsAtTheTinyDragSize, EditorModelTests.escapeCancelsCropAndAnotherToolApplies,
  CropGeometryTests.emptyCropIsNil)
- [ ] With a crop pending, pick another tool: the crop is applied as one `Crop` step. (suite:
  EditorModelTests.escapeCancelsCropAndAnotherToolApplies)
- [ ] With a crop applied, input stops at the crop's edge. Rectangle: drag from inside the crop out into the covered area and release: the rectangle ends exactly on the crop's edge. Drag from the covered area into the crop: it starts on the crop's edge (Redact, Pixelate, Blur, Rectangle, Arrow, Ellipse, Line, Pencil and Highlighter alike). A click in the covered area with Text does nothing: no text box, no editing.
  (suite: CanvasViewEventTests.drawingUnderAnAppliedCropStopsAtItsEdge, CropGeometryTests.pressOutsideAnAppliedCrop)
- [ ] With a crop applied, an annotation that lies wholly outside the crop cannot be picked by clicking where it would be: a click in the covered area with Select deselects and picks nothing, even when an annotation straddles the crop's edge nearby (it can still be picked by clicking its visible part inside the crop). The one exception is a handle: select an annotation that reaches into the crop and has a handle in the covered area, then press on that handle and drag; it resizes, and the pointer stays held at the crop's edge once it leaves the crop. Move one annotation partly out of the crop (Select with the arrow keys): the part outside is hidden on the canvas and absent from the saved PNG.
- [ ] With a crop applied, ⌘A selects the front-most annotation that reaches into the crop, skipping any that lie wholly outside it. With every annotation outside the crop, ⌘A selects nothing. Without a crop ⌘A is unchanged.
  (suite: EditorModelTests.selectAllWithEveryAnnotationOutsideTheCropSelectsNothing,
  .selectAllSkipsAnnotationsOutsideTheCrop, .selectAllAndCancelOnlyChangeSelection)

## Duplicate, copy and paste
- [ ] ⌘D on a selected rectangle makes a copy 10 pt down and to the right of the original and selects the copy; ⌘D again steps once more from the copy. One ⌘Z removes one copy (`Duplicate Rectangle`). ⌘D with nothing selected beeps and adds nothing.
- [ ] ⌘D works on every kind: ellipse, line, pencil stroke, highlighter stroke, text, arrow, and an effect (a blur or a redaction; the copy of a redaction is a redaction).
  (suite: EditorModelTests.duplicateCopiesEveryKindOffsetAndNamed, .duplicateIsOneUndoStep)
- [ ] Option-drag a rectangle with Select: the original stays where it was and a copy is dragged; one ⌘Z removes the copy and the original does not move. Option is live: pressing it after the mouse went down turns the move into a copy, and releasing it mid-drag moves the original instead and leaves no copy. An Option-click without a drag changes nothing.
  (suite: CanvasToolTests.optionDragDuplicates, .optionReleasedMidDragMoves)
- [ ] Copy and paste in one editor: select an ellipse, ⌘C, ⌘V. A second ellipse appears 10 pt down and to the right and is selected; ⌘V again adds another one more step away. One ⌘Z per paste, named `Paste Ellipse`. Pasting into TextEdit pastes nothing, and ⌘C of an object shows no notification.
- [ ] Between two editors: open the two captures from Setup in two editor windows. Select a text in the first, ⌘C, switch to the second window, ⌘V: the text appears in the second capture, selected, with the same string, size in points and colour (also when one capture is 1x and the other 2x). The first editor is unchanged. The second editor shows the unsaved dot, the first does not. Repeat with a pencil stroke and a redaction. A pasted annotation that would lie wholly outside the second capture lands in its centre. With a crop applied in the second capture, it lands in the centre of the crop (the visible part), not of the whole capture, so it is never pasted out of sight.
  (suite: CanvasViewEventTests.anObjectCopiedInOneCanvasPastesIntoAnotherAtItsPointSize,
  AnnotationClipTests.offImageObjectIsCentredThenCascades, EditorModelTests.pasteIntoAnotherEditorKeepsPointSize)
- [ ] ⌘C with nothing selected still copies the flattened image (`Image copied`; Preview > New from Clipboard shows it). With an object selected, ⌘C copies the object and ⇧⌘C and the toolbar's Copy button still copy the image.
  (suite, in part: CoordinatorEditorSaveTests.copyWithACropPutsTheCroppedImageAtPointSizeAndSaysImageCopied; by hand:
  which command reaches the copy, ⌘C with and without a selection, ⇧⌘C and the toolbar button (`EDPLACE`); Preview is
  the `pngs` decode)
- [ ] ⌘V with nothing on the clipboard to paste, or with an image or text on it, beeps and adds nothing. ⌘V while Crop is active beeps. ⌘X with an object selected does nothing to the object.
- [ ] While editing text, ⌘V and ⌘X act on the text, as in the Text section, and ⌘D duplicates nothing.

## Space-drag pan
- [ ] Zoom to 200% so the picture is bigger than the window. Hold Space and drag with Select, then with Rectangle, Pencil, Text and Crop: the picture pans under the pointer (an open hand, closed while dragging), nothing is drawn, nothing moves and no annotation is selected or created. Release Space and the tool works again.
- [ ] Space-drag pans as freely as scrolling does (neither stops at the picture's edge); ⌘0 fits the picture again. Scrolling and the trackpad still pan as before. A Space press never beeps, and holding it (key repeat) beeps neither.
- [ ] Press and release Space in the middle of a Rectangle drag: the drag goes on drawing, the editor is never left stuck in pan mode, and the next drag draws a rectangle again. Release Space mid-pan: the pan goes on until the mouse button is released. Hold Space, ⌘-Tab away and back, then click: the tool works.
  (suite, in part: CanvasViewEventTests.spacePansOnlyBetweenDragsAndNeverMovesACropDraft; by hand: the ⌘-Tab itself,
  which reaches `endSpacePan` through the window's resign-key)
- [ ] While editing text, Space types a space. With a crop pending (not yet applied), Space-drag pans and does not move the crop.
  (suite: CanvasViewEventTests.spacePansOnlyBetweenDragsAndNeverMovesACropDraft, KeyRoutingTests.spaceIsThePanKey)
- [ ] Space-drag at Fit moves the picture off centre and the fit no longer follows window resizes, as after a scroll; ⌘0 fits again.
  (suite: CanvasFitTests.aSpaceDragStopsTheFitOnResizeAndFitToViewBringsItBack)

## Annotate from Recent Captures, with the 4b tools
The row's Annotate button was built in 4a; these confirm it with the new tools.
- [ ] Saved capture, never uploaded: Annotate on its row opens the editor. Place a text and an ellipse, crop, ⌘S: the same file now shows all three (cropped, with the text and ellipse inside).
  (suite: CoordinatorEditorSaveTests.saveWithTextEllipseAndCropWritesAllThreeIntoTheSameFile)
- [ ] Capture uploaded with "Upload and copy URL": Annotate on its row, highlight a line, ⌘U. The editor closes at once, and the link shows the highlight.
  (suite, in part: CoordinatorEditorUploadTests.uploadWritesTheFileFirstThenReplacesTheLinksObject; by hand: the editor
  closing at once (`EDPLACE`); the link showing the highlight is the PUT body)
- [ ] Upload-only capture whose upload failed: opens from `pending/<UUID>.png`; add a pencil stroke, ⌘S writes the pending file, Retry Failed Uploads uploads it with the stroke.
  (suite: CoordinatorEditorSaveTests.saveOnAFailedUploadOnlyCaptureRewritesPendingAndRetryUploadsTheEdit,
  EditorInputTests.pendingFileForUploadOnlyPending, EditorSaveTargetTests.pendingFileIsPendingTarget)
- [ ] Upload-only capture that finished uploading: Annotate downloads the object and opens `Capture <time>`; add text, crop and ⌘U. The link serves the cropped image with the text.
  (suite: CoordinatorEditorUploadTests.uploadOfAnUploadOnlyCaptureWritesPendingThenReplacesItsKey)
- [ ] Settings > Overlay, turn "Show Quick Access overlay after capture" off. Capture in each after-capture mode and press Annotate on the new row: the editor opens every time, and a 4b tool works in it. Turn the overlay back on.

## Reopening a stale upload-only record
- [ ] Enter a wrong secret access key in Settings > Upload and press Save. On an upload-only capture that finished uploading, Annotate, add text, crop to a readout you note, ⌘U. The editor closes, and after the retries a notification says `Upload failed. The link still shows the earlier image.` Quit TidyShot and relaunch.
  (suite, in part:
  CoordinatorEditorUploadTests.aFailedReplaceOfAnUploadOnlyCaptureKeepsPendingAcrossARelaunchUntilTheNextUpload,
  CoordinatorUploadTests.aFailedUploadMarksTheRecordOrReturnsItToItsLink; by hand: the editor closing (`EDPLACE`), and
  the real quit and relaunch, for which the test builds a second coordinator; the test pins one attempt, since a 403 is
  not retried, and the notice titled `Not uploaded` with the line's text as its body)
- [ ] The row still copies the old URL. Annotate on the row reopens the edit with the text and at the cropped size, with the subtitle `The uploaded copy still shows the original. Upload to replace it.` (the pending file holds the cropped, edited bytes).
  (suite, in part:
  CoordinatorEditorUploadTests.aFailedReplaceOfAnUploadOnlyCaptureKeepsPendingAcrossARelaunchUntilTheNextUpload; by
  hand: the subtitle as shown (`EDPLACE`))
- [ ] Enter the right key and press ⌘U: the same URL now serves the cropped image with the text, `pending/<UUID>.png` is gone, and the row's pixel size in `history.json` is the cropped size.
  (suite: CoordinatorEditorUploadTests.aFailedReplaceOfAnUploadOnlyCaptureKeepsPendingAcrossARelaunchUntilTheNextUpload)

## Selection, undo and export across the tools
- [ ] ⌘A selects the front-most annotation (drawings before effects), whichever tool made it: an ellipse, line, stroke or text included. Delete removes it; one ⌘Z brings it back. While Crop is active ⌘A selects nothing.
  (suite: EditorModelTests.selectAllAndCancelOnlyChangeSelection, .selectAllFallsBackToASpotlight,
  .deleteSelectionCommitsOnce, .undoRestoresUncropped)
- [ ] Draw one of each tool (Redact, Pixelate, Blur, Rectangle, Arrow, Ellipse, Line, Pencil, Highlighter, Text): ten ⌘Z remove them newest first and ten ⇧⌘Z bring them back in order. Crop is a separate undo step.
  (suite: EditorModelTests.oneOfEachToolUndoesNewestFirstAndRedoesInOrder)
- [ ] A click picks the topmost annotation: an arrow over an ellipse picks the arrow; a click inside an unfilled ellipse or rectangle picks what is underneath.
  (suite: HitTesterTests.topmostPrefersDrawingOverEffectBeneath, .effectSelectableOutsideDrawing,
  .ellipseHitOnRingNotCentre, CanvasToolTests.selectPicksTopmost)
- [ ] A pencil stroke or highlighter drawn over a blur or a redaction stays above it, and the blur/redaction is never changed by a drawing above it.
- [ ] ⌘S, and in Preview at 400%: every tool matches the editor at the same zoom in position, width, colour and opacity. Pixels outside every annotation equal the original.
- [ ] A 5K capture (`⌃⇧3` on the 2x display, 5120 by 2820 pixels): draw with Pencil and Highlighter across the picture at fit zoom and at 400%. Drawing follows the mouse without stutter, and Save finishes in about a second.

## VoiceOver
Turn VoiceOver on (⌘F5). Draw an ellipse, a line, a stroke, a highlight, a text with the string `Hello` and a redaction in an editor first.
- [ ] VO-arrow around the window: the toolbar tools are read by name and the current tool as selected; the colour button, the options button, the zoom pop-up, Copy, Save and Upload are read by name.
- [ ] VO-arrow into the canvas: it reads `Annotation canvas` (a layout area). Inside it, each annotation is its own element, in painting order (every effect first, then every drawing, each in creation order), labelled with its kind and a number counted per kind (`Redact 1`, `Ellipse 1`, `Line 1`, `Pencil 1`, `Highlighter 1`, `Text 1`; a second arrow is `Arrow 2`), and a text's value is its string (`Hello`). The VoiceOver cursor box around each element matches the shape on screen, also after zooming and panning.
- [ ] Move, resize or delete an annotation with the mouse: the elements follow at once, with no stale element left and no element for a deleted annotation. A newly drawn annotation appears in its place in painting order: a drawing last, an effect after the other effects.
  (suite: CanvasAccessibilityTests.canvasElementsFollowMovesResizesDeletesAndAdds,
  .itemsFollowPaintingOrderAndNumberEachKind)
- [ ] The selected annotation is reported as selected. Selecting another with the mouse moves that state. (suite:
  CanvasAccessibilityTests.anAccessibilityPressSelectsAndTheCanvasActsOnTheSelection)
- [ ] With a crop applied, VoiceOver lists only the annotations that reach into the crop (the same rule as ⌘A), numbered among the listed ones, and skips those wholly outside it; they stay in the document, and undoing the crop, or applying a crop that reaches them, lists them; while the Crop tool is open the list still follows the applied crop. VO-Space on any element while Crop is active does nothing.
  (suite, in part: CanvasAccessibilityTests.anAccessibilityPressIsRefusedWithTheCropToolOrDuringADrag,
  .cropHidesAnnotationsOutsideIt; by hand: the list while the Crop tool is open over an applied crop)
- [ ] VO-Space on an element selects that annotation; Delete, the arrow keys, ⌘C and ⌘D then act on it. (suite:
  CanvasAccessibilityTests.anAccessibilityPressSelectsAndTheCanvasActsOnTheSelection)
- [ ] Turn VoiceOver off. The editor behaves as before (typing and drawing feel the same).
