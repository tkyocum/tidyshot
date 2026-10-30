# Phase 4c manual test checklist

Run after any change to the editor's Spotlight or Counter tool, `AnnotationDrawing`'s overlay or counter drawing,
`EditorFlattener`, `CanvasView.draw(_:)` or its repaints, the options popover, the Colour item's enabling, the
toolbar width or the canvas accessibility elements. Automated tests cover the model and its Codable form,
the tool letters, symbols and tips, the key routing, the hit, select-all and accessibility orders, the
flattener's pixels for the overlay (every dim, the ellipse, the union, transparency, alpha 128, an
opaque base against a plain composite, a hole across a strip seam of a 4 x 40,000 capture, and the crop
and background cases), the canvas's drawing order into a bitmap (the highlighter across the dim edge, and
a transparent corner left at alpha 0), the pure helpers `displayedSpotlights(in:transient:)` and
`allowsPartialRepaint(since:)`, the counter numbering (Add, ⌘D, the ⌥-drag copy and ⌘V), the paste cascade,
the clamp, the digit colour for every swatch, a rendered counter's fill, ring and centred number, the
options' enable rules and undo steps, the two editor defaults, and the measured toolbar width. Nothing
automated reaches `CanvasView.draw(_:)` on screen or the partial repaints, a real pointer, VoiceOver itself,
Preview or the pasteboard; everything here needs real windows and eyes. The 4a and 4b checklists still cover
the rest of the editor, and the 7c one backgrounds; run them too after a change to those paths.

Setup: a fresh **Release** build (`xcodebuild -project TidyShot.xcodeproj -scheme TidyShot -configuration Release
-derivedDataPath .build-rel build`), Screen Recording granted, a save folder set to Desktop, "Show Quick Access
overlay after capture" on, a working destination in Settings > Upload, "Show notification" on in Settings >
General, a Retina display and, for the small-counter check, a 1x capture (from a non-Retina display, or from a
display switched to a low-resolution mode). Note how the build is signed (`Config/Local.xcconfig`). Start from the
defaults, then relaunch: `for k in editorSpotlightEllipse editorCounterDiameterPoints; do defaults delete
io.tky.tidyshot $k; done`. Read them with `defaults read io.tky.tidyshot <key>`; a missing key means the default
(`editorSpotlightEllipse` false, `editorCounterDiameterPoints` 32).

Take these captures first.
- A Terminal or TextEdit window with a few lines of dark text on white, saved with "Save and copy image" (the
  main capture; a second like it, for the two-editor items; and three or four more like it, the scratch captures).
- One more like it taken with After capture set to "Upload and copy URL" (Settings > General; set it back to "Save
  and copy image" afterwards): the uploaded capture. Upload as New needs a link (⌥⌘U beeps on a capture never
  uploaded), and this capture has one before anything is drawn on it.
- A window capture (⌃⇧2) of a window with rounded corners, with Include window shadow off, and another with it on.
- A capture of busy content (a web page with photos and text) with a bright and a dark half, at 1x if you can.
- A scrolling capture of `tall.html` below, of the page area only, started at the top of the page and scrolled to
  the end, about 10,000 pt (20,000 px on a 2x display; check with `sips -g pixelHeight`). Its strip seam, where
  `EditorFlattener` starts the second strip, is at pixel row 16,384 of the image: 8,192 pt from the top of the
  capture on a 2x display. Each `row N` is exactly 100 pt tall, its 1 pt rule included, so the labels give places on
  the page. A capture rarely starts exactly at the page's top, so the tall section finds the seam's row in the
  capture itself.

```bash
mkdir -p ~/Desktop/p4c && cd ~/Desktop/p4c
python3 - <<'PY'
rows = "".join(f'<div style="box-sizing:border-box;height:100px;border-bottom:1px solid #999;font:20px sans-serif">row {i}</div>' for i in range(100))
open("tall.html", "w").write(f'<!doctype html><meta charset="utf-8"><title>tall</title><body style="margin:0">{rows}</body>')
PY
cat > px.swift <<'SWIFT'
import CoreGraphics
import Foundation
import ImageIO

// Prints the pixel at x,y (top-left origin) of an image, converted to sRGB, as premultiplied RGBA
// from 0 to 255: swift px.swift file.png x y [x y ...]
let args = CommandLine.arguments
guard args.count >= 4, args.count % 2 == 0,
      let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: args[1]) as CFURL, nil),
      let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
      let context = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0,
                              space: CGColorSpace(name: CGColorSpace.sRGB)!,
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
    print("usage: swift px.swift file.png x y [x y ...]"); exit(1)
}
print("\(image.width) x \(image.height) px")
context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
let bytes = context.data!.assumingMemoryBound(to: UInt8.self)
var index = 2
while index + 1 < args.count {
    let (xText, yText) = (args[index], args[index + 1])
    index += 2
    guard let x = Int(xText), let y = Int(yText), (0..<image.width).contains(x), (0..<image.height).contains(y) else {
        print("(\(xText), \(yText)): not a pixel of this image"); continue
    }
    let i = y * context.bytesPerRow + x * 4
    print("(\(x), \(y)): \(bytes[i]) \(bytes[i + 1]) \(bytes[i + 2]) \(bytes[i + 3])")
}
SWIFT
```
`swift px.swift file.png x y` prints a pixel as premultiplied RGBA from 0 to 255, converted to sRGB: a Display P3
capture reads a little differently from the bytes in its file, and the comparisons below hold because every file is
converted alike. A point outside the image prints `not a pixel of this image`; `sips -g pixelWidth -g pixelHeight`
gives a file's size. Where an item says to compare with the canvas, open the saved file in Preview at View > Actual
Size, put it beside the editor at ⌘1 (the capture's natural scale) and look at the same place. Draw only on made-up
data.

Save (⌘S) and Upload write the edit over the capture's own file, and the capture then reopens flat with the marks
in it. So the pixel comparisons below use Save As…, which leaves the capture alone, and read the original from a
copy: before editing them, copy the main, the two window and the tall captures' files from the save folder into
`~/Desktop/p4c` as `main-original.png`, `window-original.png` (shadow off), `shadow-original.png` (shadow on) and
`tall-original.png`. Use ⌘S and Upload only where an item says so, and then on a scratch capture or as that item
says.

## Toolbar and keys
- [ ] The toolbar shows fourteen tools, in order: Select, Redact, Pixelate, Blur, Spotlight, Rectangle, Arrow, Ellipse, Line, Pencil, Highlighter, Text, Counter and Crop, then Colour, Options, Background, the zoom pop-up, Copy, Save and Upload. The new tools' tool tips read `Spotlight (S)` and `Counter (N)`; the symbols are `light.max` and `1.circle`. The Options button's tool tip reads `Tool options`.
- [ ] With the canvas focused, `S` (either case) picks Spotlight and `N` picks Counter, and the toolbar's segment follows. ⌘S still saves (it does not pick Spotlight; try it on a scratch capture). `N` with a text being edited types the letter.
- [ ] The 14-tool toolbar shows every item, with no » overflow chevron, on a 1280 pt wide display (System Settings > Displays, a scaled mode that is 1280 pt wide) with a long title (rename a capture to 60 characters first): open the editor, then drag its left or right edge in as far as it will go. The window never gets narrower than its toolbar, and opens no wider than 90 % of the display (1152 pt). A probe in the test host measured the minimum as 1134 pt (the tools control alone 493 pt) with every item showing down to 1096 pt; write down what you see.
- [ ] Repeat the narrowest-window check full screen and back, and on a second display if one is attached.

## Spotlight: drawing and the live dim
- [ ] On a capture with no spotlight, press `S` and drag. The whole image dims at once, to half, outside a hole that follows the pointer. The cursor is the crosshair. Nothing dashed is drawn into the picture itself; see the outlines below.
- [ ] Release: one spotlight is added, selected, with a dashed outline and eight handles. The tool stays Spotlight. A second drag adds a second hole in the same dim, and where two holes overlap their union is undimmed.
  (suite, in part: CanvasToolTests.spotlightDragCommitsAddSpotlight, HitTesterTests.spotlightHandlesResizeItsRect,
  SpotlightRenderingTests.overlappingSpotlightsLeaveTheirUnionUndimmed; the dashed outline's look stays by hand)
- [ ] Press Escape mid-drag, on a capture with no other spotlight: the dim goes entirely, at once, and releasing the mouse adds nothing.
- [ ] Begin a drag, shrink it below the minimum size (a tiny box, as for Rectangle): the dim goes. Grow it back: the dim returns. Release at the tiny size: nothing is added.
- [ ] Shift squares the box and, with Ellipse chosen in Options, makes a circle. Pressing and releasing Shift mid-drag changes the hole without moving the mouse.
  (suite: CanvasToolTests.shiftViaFlagsChangedSquares, .spotlightDragCommitsAddSpotlight,
  EditorModelTests.aNewSpotlightTakesTheShapeDefault)
- [ ] Press Option mid-drag: Option draws from the centre, as with Rectangle. (suite:
  CanvasToolTests.optionDrawsFromCentre, .spotlightDragCommitsAddSpotlight)
- [ ] With Shape set to Ellipse in the Options popover (Spotlight active), a drag cuts an ellipse. Its bounding box's corners stay dimmed.
  (suite: EditorModelTests.aNewSpotlightTakesTheShapeDefault, SpotlightRenderingTests.outsideIsDimmedAndInsideIsNot)
- [ ] The dim is black at the chosen opacity over the whole picture, hole excepted: at 50 % white reads about half grey. Dark text is dimmed, not bleached.
  (suite: SpotlightRenderingTests.eachDimDarkensByItsAmount, .outsideIsDimmedAndInsideIsNot)
- [ ] Select and move a rectangle spotlight and then an ellipse one: the hole follows the pointer and the dim updates live, with no stale edge left where it was. Resize each with a handle, including the corner handles, and with Shift on a corner. Undo each.
- [ ] Select a spotlight and press an arrow key, then Shift-arrow: the hole moves by 1 and by 10 pixels. (suite:
  KeyRoutingTests.nudgeOneOrTenPixels, EditorModelTests.coalescedNudgesAreOneStep,
  AnnotationDocumentTests.spotlightAndCounterBoundsAndMove)

## Spotlight outlines
- [ ] With two or three spotlights in the document and nothing selected, press `S`: every dashed outline (white under black dashes, 1 pt) appears at once, the ellipse's following its ellipse. Press `V`: they all go at once. Press `S`, then pick Rectangle from the toolbar: they go. `S`, then `R`, `A` and `T` with the keys: they go each time. Then `S` again: they return.
- [ ] While the Crop tool shows its chrome, no spotlight outline is drawn. Return to Spotlight: they are back.
- [ ] Check the outlines at 50 %, 100 % and 400 % zoom: crisp 1 pt dashes at every zoom, hugging the hole's edge, with no thick or doubled lines and no stale outline left after a zoom or a pan.
- [ ] A selected spotlight shows its own dashed outline and eight handles (also with the Select tool). The Spotlight tool's outlines and the selection outline do not leave the other tool's marks behind after Escape or a click on empty space.
- [ ] The outlines are chrome: Save As… with a spotlight selected and open the file in Preview. They are not in the file, and neither is the selection.
  (suite: SpotlightRenderingTests.anOpaqueBaseMatchesANormalComposite)

## Over the dim
- [ ] Draw a highlighter stroke across the dim's edge, half over the dimmed area and half in a hole. Save As… and compare at 100 %: the canvas shows the same darkness under the stroke as the file, both in the dimmed part and in the hole, with no lighter fringe along the stroke's edge.
- [ ] Draw an arrow, a text and a counter over the dimmed area: all three stay bright in the editor and in a Save As… file (the overlay is painted under the drawings).
- [ ] Draw a Redact, a Blur and a Pixelate in the dimmed area and one in a hole: they are dimmed with the picture where outside a hole, and unchanged where inside. Move the effect and the spotlight in turn: no stale pixels.
- [ ] Select an arrow, a text, a counter and a blur that lie inside a spotlight, one at a time, by clicking on each (made before and after the spotlight): the click picks the drawing, never the spotlight. A text inside a spotlight is edited again by the Text tool's click and by Select's double-click.
  (suite: HitTesterTests.anArrowInsideASpotlightIsHitFirst, .aRedactionInsideASpotlightIsHit,
  AnnotationDocumentTests.spotlightsAreAThirdList, CanvasToolTests.textInsideASpotlightIsReEdited)
- [ ] A click on bare image inside a spotlight picks the spotlight (so it does not deselect; Escape does). A click just outside its edge picks it too (within the 8 pt hit tolerance); one 12 or more points outside picks nothing. At ⌘1, for an ellipse spotlight at least 200 pt wide and high, a click in its bounding box's dim corner region, more than 8 pt from the corner and more than 8 pt outside the ellipse (about halfway between them), picks nothing. A click within 8 pt of the corner lands on the corner handle, which every spotlight has, so it selects the spotlight (and a drag from there resizes it).
  (suite, in part: HitTesterTests.bareImageInsideASpotlightHitsItsBody, .anEllipseSpotlightIsHitInsideItsEllipseOnly,
  .spotlightHandlesResizeItsRect, .handlesBeforeBody, EditorModelTests.selectAllAndCancelOnlyChangeSelection; the
  closing "a drag from there resizes it" does not hold for an unselected spotlight: `SelectTool.mouseDown` resizes only
  from the selection's handles, so that drag moves it. Fix the line to say "once selected", or check by hand)
- [ ] ⌘A with an arrow made before a spotlight selects the arrow; with only a spotlight in the document it selects the spotlight.
  (suite: EditorModelTests.selectAllFallsBackToASpotlight)

## Crop and Background
- [ ] With a crop applied, the dim covers the picture before the crop, and the crop is applied last: Save As… gives a file the size of the crop, with the dim still in it.
  (suite: SpotlightRenderingTests.theCropIsAppliedAfterTheOverlay)
- [ ] Turn on a Background (7c) with a crop and a spotlight: the dim stops at the rounded content rect, in the editor and in a Save As… file. The padding, the fill and the rounded-off corners are never dimmed and match the export. A spotlight hole does not change that.
- [ ] A window capture with transparent rounded corners and a spotlight, with and without a Background: no dark corners on the canvas; a Save As… file's corners stay transparent (`swift px.swift file.png 0 0` reads `0 0 0 0` on an exported corner, with no background).
- [ ] Spotlight a window capture taken with Include window shadow on and again with it off: the export's (Save As…) corners and the shadow margin stay transparent (a margin pixel in the export keeps the alpha it had in the original capture, `px.swift` on the export and on `window-original.png` or `shadow-original.png`, not an opaque black), and the canvas shows no dark corners or dark margin. A partly transparent shadow pixel may look a little darker on the canvas than in the file; write down whether it shows.
- [ ] A redaction that is still rendering over a transparent corner may show its placeholder undimmed for a moment. Write down if you see it, and that it is dimmed once the tile arrives.

## Options and Colour
- [ ] Open Options with the Select tool and nothing selected: `Shape`, `Dim` and `Size` are all dimmed. `Line width` is enabled and the blur radius and pixel block follow their old rules.
  (suite, in part: EditorModelTests.shapeAndDimEnableRules, .sizeEnableRule; `Line width` enabled and the blur radius
  and pixel block rules are the view's `.disabled` modifiers, which no test reads, so they stay by hand)
- [ ] With Spotlight as the tool and no spotlight in the document: `Shape` is enabled (Rectangle, Ellipse); `Dim` is dimmed and reads 50 %. Draw the first spotlight: `Dim` is enabled (30 %, 50 %, 70 %). With Select, press Escape to deselect it, then pick Arrow: both are dimmed again. With Select, click the spotlight: both enable.
  (suite: EditorModelTests.shapeAndDimEnableRules, AnnotationDocumentTests.documentWithoutSpotlightDimReadsHalf,
  EditorPaletteTests.standardDefaultsAreRedBlackFourEightTen)
- [ ] `Dim`: pick 70 %, then 50 %, then 30 % in a row: the whole image's dim follows each; Edit shows one `Undo Spotlight Dim` for the run, and ⌘Z returns to the dim before the first click, 50 % (a visible change from 30 %). Picking the value already in effect adds no undo step (on the main capture, draw the first spotlight, Save As… (⇧⌘S) to `~/Desktop/p4c/clean.png`, then pick 50 %: the editor stays clean, with no edited mark in the title).
  (suite, in part: EditorModelTests.aRunOfDimClicksIsOneStep, .shapeAndDimOnASelectedSpotlightAreOneStepEach,
  .dimWithoutASpotlightOrUnchangedAddsNoStep; the title's edited mark following the model stays by hand)
- [ ] `Dim` with no spotlight in the document (delete them all, then open Options with the Spotlight tool): it stays dimmed and adds no step, however you click.
  (suite: EditorModelTests.dimWithoutASpotlightOrUnchangedAddsNoStep, .shapeAndDimEnableRules)
- [ ] `Shape`: with a spotlight selected, picking Ellipse turns it into an ellipse, `Undo Spotlight Shape`, and also makes new spotlights ellipses. With nothing selected it changes only the default and adds no undo step. Note that right after drawing a spotlight it is selected, so picking Shape then changes that spotlight too; write down whether that surprises you.
  (suite, in part: EditorModelTests.shapeAndDimOnASelectedSpotlightAreOneStepEach,
  .shapeWithNothingSelectedChangesOnlyTheDefault; whether the reshape after drawing surprises you stays yours to write)
- [ ] `Size`: enabled for Counter as the tool or with a counter selected, and dimmed otherwise. `Small`, `Medium`, `Large`.
  (suite, in part: EditorModelTests.sizeEnableRule, EditorPaletteTests.standardDefaultsAreRedBlackFourEightTen; the
  `Small`, `Medium`, `Large` labels are not asserted and stay by hand)
- [ ] `Line width` is always enabled. With a spotlight or a counter selected it changes only the default (the selected one does not change), and no undo step is added.
- [ ] The Colour button is dimmed for Spotlight with nothing selected, and while a spotlight is selected, so the palette cannot quietly change the stroke colour. It is enabled with Select and a counter selected, with Arrow and with Crop. It is enabled with Spotlight as the tool and a counter selected.
  (suite: EditorModelTests.colorAppliesRule, .aSelectedCounterShowsAndTakesTheColour)
- [ ] Options popover layout: every label (`Line width`, `Blur radius`, `Pixel block`, `Shape`, `Dim`, `Size`) shows on one line, right-aligned, with Spotlight, Counter and other tools active, and after drawing and selecting a spotlight and changing Dim. (Fixed 2026-10-23: `Line width` wrapped one letter per line once a spotlight was drawn.)
  (suite, in part: ToolOptionsViewTests.everyToolKeepsOneLinePerRow, .aSelectedSpotlightKeepsOneLinePerRow,
  .thePopoverIsWideEnoughForItsWidestRow; the labels' right alignment stays by hand)

## Counter
- [ ] `N` picks Counter; the cursor is the crosshair. A click places a filled circle in the current stroke colour (red by default) with a white ring and a white number `1`, centred on the click. The new counter is selected and shows the dashed outline round its circle's bounding square, and no handles. The tool stays Counter.
  (suite, in part: CanvasToolTests.counterClickAndDragPlaceAtThePress,
  EditorModelTests.aNewCounterTakesTheSizeAndColourDefaults, CounterTests.renderedCounterIsFilledAndRinged,
  .renderedNumberIsCentred, HitTesterTests.counterBodyIsItsCircle; the dashed outline round the bounding square stays by
  hand)
- [ ] A drag with Counter places at the press, not where the pointer ended, as one `Add Counter`. The counter does not follow the pointer. Escape during the press places nothing.
  (suite: CanvasToolTests.counterClickAndDragPlaceAtThePress, .escapeDuringACounterPressPlacesNothing)
- [ ] Place counters 2, 3 and 4. With Select, delete counter 2: counters 1, 3 and 4 keep their numbers. Place another with Counter: it reads 5. Undo (`Undo Add Counter`) and place again: 5 again.
  (suite: CounterTests.nextNumberIsOneMoreThanTheLargest, .duplicateOptionDragAndPasteEachTakeTheNextNumber,
  CanvasToolTests.counterClickAndDragPlaceAtThePress)
- [ ] Place a counter within a few points of each edge of the image: the whole circle lies inside the image, ring included, flush to the edge. With a crop applied, the same at the crop's edge. A press outside an applied crop places nothing and starts no selection.
  (suite: CounterTests.centreClampsInsideTheBounds, .renderedCounterIsFilledAndRinged,
  EditorModelTests.aNewCounterTakesTheSizeAndColourDefaults, CropGeometryTests.pressOutsideAnAppliedCrop)
- [ ] Select a counter with Select: a click inside its circle picks it (within the 8 pt hit tolerance outside works too), and the outline moves to it. Click another counter: the outline moves, and the first one's goes. Click empty image: the selection and the outline clear. Drag a counter: it moves, `Undo Move Counter`. It has no resize handles. Nudge with the arrow keys: `Undo Move`.
  (suite: HitTesterTests.counterBodyIsItsCircle, CanvasToolTests.selectPicksTopmost, .clickEmptyDeselects,
  .moveCommitsOnceWithDelta, .optionReleasedMidDragShowsTheCounterWithItsOwnNumber,
  EditorModelTests.coalescedNudgesAreOneStep)
- [ ] The digits contrast with the fill: switch through the palette and place a counter in each colour. White digits on Black, Red, Blue, Purple and Pink; black digits on Orange, Yellow, Green, Teal and White. Pick a custom light grey in the colour panel: black digits. The number is centred across and down the circle.
  (suite: CounterTests.numberColourContrastsWithEverySwatch, .renderedNumberIsCentred)
- [ ] With a counter selected, the Colour button's swatch shows its colour; a swatch from the palette recolours it (`Undo Color`) and the digits flip to suit. Counters placed afterwards use that colour (the stroke colour changed with it).
- [ ] Size: `Small`, `Medium`, `Large` set 24, 32 and 44 pt, times the capture scale (48, 64 and 88 px at 2x). With a counter selected, picking a Size resizes it about its centre as one step, `Undo Counter Size`, and sets the default for the next counters. Picking Size with nothing selected only changes the default.
  (suite: EditorModelTests.sizeOnASelectedCounterIsOneStepAboutItsCentre, .sizeWithNothingSelectedChangesOnlyTheDefault,
  .aNewCounterTakesTheSizeAndColourDefaults, EditorPaletteTests.standardDefaultsAreRedBlackFourEightTen)
- [ ] Small counters on a 1x capture (24 px) over busy content are legible and their ring shows, on every colour. A counter in White has no visible edge on a white background: only its black digit shows; write down whether that is a problem.
- [ ] Two and three digit numbers fit: on a fresh capture with no counters (the next number follows the document's highest), with Counter, click again and again in one spot, about a hundred times. Each click stacks a new counter, numbered one more, on top of the last, so the top one shows each number in turn. Stop at `10`, `42` and `100` to look: each sits inside the circle, `100` smaller than the others. (A held ⌘D is no shortcut: each copy sits 10 pt further down and right than the last, so a hundred of them walk off the image.)
  (suite: CounterTests.numbersFitTheCircle, .nextNumberIsOneMoreThanTheLargest)
- [ ] Save As… and compare at 100 %: each counter matches the canvas in position, colour, ring and digit.

## Duplicate, copy and paste
- [ ] Counters 1 and 2 on the capture. Select counter 1 and press ⌘D: the copy is numbered 3 (`Undo Duplicate Counter`). An ⌥-drag of counter 2 with Select (counter 1 now lies mostly under its copy) shows the copy numbered 4 while you drag, and commits it as 4, leaving counter 2 as it was. ⌘C and ⌘V: the paste is numbered 5, selected (`Undo Paste Counter`). No number is ever repeated.
  (suite: CounterTests.duplicateOptionDragAndPasteEachTakeTheNextNumber)
- [ ] Undo the paste, the ⌥-drag copy and the ⌘D copy in turn: the numbers return to 1 and 2. Redo restores each copy with its number. Undo the three again and place a counter: it is 3.
- [ ] Start an ⌥-drag of counter 2 with Select and release Option before the mouse: the copy goes, and counter 2 itself follows the pointer, still numbered 2. Releasing the mouse moves it as one `Undo Move Counter` and uses no number: the next counter placed is 4.
  (suite: CanvasToolTests.optionReleasedMidDragShowsTheCounterWithItsOwnNumber, .optionReleasedMidDragMoves,
  CounterTests.nextNumberIsOneMoreThanTheLargest)
- [ ] Three pastes of one counter (⌘C once, ⌘V three times): they land 10, 20 and 30 pt down and to the right of the original, as counters with the next three numbers, not stacked on the original.
  (suite: CounterTests.threePastesOfOneCounterCascade)
- [ ] ⌘C a counter in one editor and ⌘V it twice in another editor open on a capture at a different scale (a 2x capture into a 1x one, and the other way): new numbers (the next ones in the target), a cascade, and the same point size as the source (a 64 px counter at 2x is 32 px at 1x).
- [ ] The same for a spotlight: ⌘D, ⌥-drag and ⌘C, ⌘V give `Duplicate Spotlight` and `Paste Spotlight`; a second paste lands one step further. A document with two spotlights has two holes in one dim.

## Undo and redo of every new step name
Each is one Edit > Undo entry named as below; ⌘Z restores the picture, ⇧⌘Z reapplies it, and the title shows the edited mark after each.
- [ ] `Add Spotlight`, `Move Spotlight`, `Resize Spotlight`, `Duplicate Spotlight` (⌘D, and an ⌥-drag), `Paste Spotlight`.
- [ ] `Spotlight Shape`, `Spotlight Dim` (a run of clicks is one step) and `Counter Size`. (suite:
  EditorModelTests.shapeAndDimOnASelectedSpotlightAreOneStepEach, .aRunOfDimClicksIsOneStep,
  .sizeOnASelectedCounterIsOneStepAboutItsCentre)
- [ ] `Add Counter`, `Move Counter`, `Duplicate Counter` (⌘D, and an ⌥-drag), `Paste Counter`. (suite:
  CanvasToolTests.counterClickAndDragPlaceAtThePress, .optionReleasedMidDragShowsTheCounterWithItsOwnNumber,
  CounterTests.duplicateOptionDragAndPasteEachTakeTheNextNumber, EditorModelTests.undoRestoresSnapshotAndRedoReapplies)
- [ ] The existing names still apply: `Color` for a counter's colour, `Move` for an arrow-key nudge, `Delete` for removing either kind.
  (suite: EditorModelTests.aSelectedCounterShowsAndTakesTheColour, .coalescedNudgesAreOneStep,
  .deleteSelectionCommitsOnce)
- [ ] After undoing a Delete of a counter the number it had returns; after undoing an Add the next number is the one it was.
  (suite: EditorModelTests.deleteSelectionCommitsOnce, CounterTests.duplicateOptionDragAndPasteEachTakeTheNextNumber)

## Copy, Save, Save As… and Upload
With a spotlight (rectangle and ellipse, Dim 70 %) and a few counters, an arrow and a text over the dimmed area, on a scratch capture (Save and Upload write over it). Do Copy, Save, Save As… and Upload once each, in this order and in the one editor, without closing it between them: Save leaves the marks live in the open editor, and Upload closes it. Compare each result with the canvas at 100 %; Upload's with the Save As… file, since the canvas is gone by then.
- [ ] Copy (⇧⌘C, or ⌘C with nothing selected): paste into Preview > File > New from Clipboard. The dim, the holes, the counters (fill, ring, number) and the arrow match the canvas; the arrow, text and counters are bright over the dim.
- [ ] Save (⌘S): the file in the save folder matches. The editor stays open, and a click on a spotlight or a counter still selects it.
- [ ] Save As… (⇧⌘S) to `~/Desktop/p4c/saveas.png` matches, and leaves the capture and its record unchanged.
- [ ] Upload (⌘U): the editor closes. The uploaded object, opened from the link, matches `saveas.png`.
- [ ] Once the upload has finished, reopen the capture with Annotate on its Recent Captures row: it opens as a flat image with the marks in its pixels, and no spotlight or counter left to select.
- [ ] Upload as New (⌥⌘U), on the uploaded capture (see the setup), not on the one just uploaded, which now reopens flat: open it in the editor and draw the same marks. Save As… to `~/Desktop/p4c/asnew.png` and compare it with the canvas, then press ⌥⌘U: the editor closes, the clipboard gets a new link, and the object it opens matches `asnew.png`.
- [ ] With a Background on, a crop and the spotlight, on a second scratch capture: Copy, Save, Save As… and Upload, in the same order (Upload last), each give the dim inside the content only, with the fill and the padding undimmed.
- [ ] Pixels outside the effects, the drawings and the dim equal the capture: close any editor on the main capture without saving and open it again (it was never saved over; `main-original.png` holds it), draw a single small spotlight, Save As… to `~/Desktop/p4c/dim50.png`, and check with `px.swift` that a pixel inside its hole equals the same pixel of `main-original.png`, and one outside is about half of it at 50 %.
  (suite: SpotlightRenderingTests.outsideIsDimmedAndInsideIsNot, EditorFlattenerTests.bytesOutsideEffectsEqualBase,
  .displayP3BaseKeepsColourSpace)
- [ ] In the same editor, pick 30 % and Save As… `dim30.png`, then 70 % and Save As… `dim70.png`: one pixel of white outside the hole reads about 179 and about 77 on a white page (`dim50.png` reads about 128), against 255 in `main-original.png`.
  (suite: SpotlightRenderingTests.eachDimDarkensByItsAmount)

## A tall capture across a strip seam
First find the seam in the capture. It is pixel row 16,384 whatever the page shows there, and its row on the page
depends on where the capture started. This cuts a band 400 px tall from the capture with the seam across its
middle, 200 px down:

```bash
cd ~/Desktop/p4c && sips -c 400 800 --cropOffset 16184 0 tall-original.png --out seam.png && open seam.png
```
Note the `row N` that middle line falls in, and where in that row. (A capture that started exactly at the page's
top has it in `row 81`, 8 pt above the top of `row 82`.)
- [ ] Open the scrolling capture of `tall.html` (over 16,384 px) in the editor, at ⌘1. Scroll to the seam's row, and draw a rectangle spotlight over the left half of the page from the top of the row above it to the bottom of the row below it, so its hole straddles the seam by at least 100 pt each way and the right half stays dimmed. Place a counter on the seam too, in the dimmed right half and away from where you will read pixels.
- [ ] Save As… and check the file with `px.swift` at y = 16,383 and 16,384, the last row of the first strip and the first of the second: at an x in the right half of the page clear of the counter (outside the hole), and at an x in the hole, clear of the counter. Read the same four pixels of `tall-original.png`. Outside the hole each reads about half the original's (about 128 where the original reads 255, at a 50 % dim), so the two rows read alike wherever the original's do; inside the hole each equals the original. In Preview at 100 % and 400 % there is no line at the seam that `seam.png` does not show.
  (suite, in part: SpotlightRenderingTests.aTallCaptureIsDimmedTheSameAcrossTheStripSeams,
  EditorFlattenerTests.aTallBaseIsCopiedExactlyAcrossTheStripSeams; Preview at 400 % and a counter across the seam stay
  by hand)
- [ ] Copy, Save and then Upload do the same (Upload last, since it closes the editor; check the saved file, and the pasted image in Preview). The save does not run out of memory or take noticeably longer than a capture of the same height without a spotlight; write down the time.
- [ ] Zoom the editor's canvas to the seam and pan across it: the canvas shows the dim continuous across it too.

## Defaults and the document
- [ ] Shape and Size survive a relaunch. Choose Ellipse and Large, then check `defaults read io.tky.tidyshot editorSpotlightEllipse` (`1`) and `editorCounterDiameterPoints` (`44`). Quit and relaunch TidyShot, open any capture in the editor: Spotlight draws ellipses, the Shape row shows Ellipse when the Spotlight tool is active, a new counter is 44 pt (88 px at 2x), and the Size row shows Large with the Counter tool.
- [ ] Hand-write a bad size: `defaults write io.tky.tidyshot editorCounterDiameterPoints -float 40`, relaunch: the Size row reads Medium and new counters are 32 pt. Then `defaults delete` the two keys again.
  (suite, in part: AppSettingsTests.aStoredCounterSizeOutsideTheStopsReadsAs32; the Size row's `Medium` label is not
  asserted, as on line 139, and stays by hand)
- [ ] Dim does not carry into a new capture. Set 70 % on one capture's spotlight, then open another capture (or close the editor and open the same capture again): its first spotlight dims to 50 %, and `Dim` reads 50 % until a spotlight is there. Two editors open at once keep their own Dim.
- [ ] On a scratch capture, close an editor that has unsaved spotlights and counters: the usual unsaved-changes sheet appears, as for other annotations. After Save, reopening the capture gives a flat image: there is no layer to edit (the editable project format is not built).

## VoiceOver
- [ ] With VoiceOver on (⌘F5), move into the canvas. The elements read in painting order: effects, spotlights, then drawings, each in creation order, so an arrow made before a spotlight is read after it. Spotlights read `Spotlight 1`, `Spotlight 2`, numbered per kind in that order.
  (suite: CanvasAccessibilityTests.spotlightsReadBetweenEffectsAndDrawings)
- [ ] A counter reads `Counter <its number>` with no value: `Counter 1`, `Counter 2`, `Counter 3`. Delete counter 2, then read again: `Counter 1`, then `Counter 3`, matching the picture.
  (suite: CanvasAccessibilityTests.countersReadTheirOwnNumbers)
- [ ] AXPress on an element selects it (not while a drag runs or Crop is active). With a crop applied, only annotations that reach into the crop are listed.

## Regression
- [ ] The 4b checklist's toolbar, Ellipse, Line, Pencil, Highlighter, Text, Crop and accessibility sections still pass, with the extra two tools in the toolbar.
- [ ] A scratch capture with no spotlight and no counter saves, copies and uploads exactly as before: same file, no dim, no change in size.
  (suite: SpotlightRenderingTests.noSpotlightDimsNothing, EditorFlattenerTests.outputSizeEqualsBase,
  .bytesOutsideEffectsEqualBase)
- [ ] An older capture, made before 4c, opens in the editor, edits and exports as before.
- [ ] Redact, Blur and Pixelate still work, and a Highlighter over a Blur still follows the blur live (4b).
- [ ] 7c: a Background on a capture still composes, and the editor's Background popover still opens from the toolbar.
- [ ] Switching tools in quick succession (`S`, `N`, `V`, `R`) neither flickers a stale outline nor leaves a selection chrome behind.

## Observations
Write these into the "Phase 4c (built)" notes of spec 2.12:
- Whether the 14-tool toolbar fits at 1280 pt with a long title, and the narrowest width the window allowed.
- Whether stale outlines or a stale dim ever appeared after S, V, Escape or a tool change (the partial repaint).
- Whether the canvas matched the saved file under the highlighter, and how a window shadow's partly transparent edge looked on the canvas against the file.
- How the saved image compared with the canvas for the counters (ring, digits) and for the dim.
- Whether picking Shape or Size right after drawing a spotlight or placing a counter (which changes the selected one too) surprised you.
- Whether a White counter's missing edge on a light capture matters.
- The time a Save As… takes on the tall capture with a spotlight, against the same capture without.
- Anything above that failed.
