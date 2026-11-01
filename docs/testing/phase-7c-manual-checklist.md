# Phase 7c manual test checklist

Run after any change to `TidyShot/Background/`, the editor's Background tool (`BackgroundPopoverView`,
`BaseImageView`, `CanvasView`, `EditorModel.renderExport`), `AppCoordinator.save` or the Capture tab.
Automated tests cover the style's defaults and JSON, the twelve presets, the layout arithmetic, the
compositor's pixels, the custom image store, the two settings keys, the editor's export with a
background, its undo steps and the preview layers' frames; everything here needs real windows, real
displays, a real colour panel, the open panel and eyes. The Phase 4b checklist still covers the rest
of the editor, and the 6a and 6b checklists the capture paths; run them too after a change to those.

Setup: a fresh **Release** build (`xcodebuild -project TidyShot.xcodeproj -scheme TidyShot
-configuration Release -derivedDataPath .build-rel build`), Screen Recording granted, "Show
notification" and "Play sound" on in Settings > General, Allow URL commands on, an upload destination
that works, a Retina display and a second display if you have one (ideally with a different desktop
picture and scale). Note how the build is signed (`Config/Local.xcconfig`). Start from the defaults:
`for k in windowBackground backgroundStyle; do defaults delete io.tky.tidyshot $k; done`, then
relaunch.

Make the test images and a tall page once.
```bash
mkdir -p ~/Desktop/p7c && cd ~/Desktop/p7c
cat > images.swift <<'SWIFT'
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

// Four colour quadrants and a white cross at the centre, so aspect-fill's centring shows.
func write(_ name: String, width: Int, height: Int) {
    let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    let colours: [(CGFloat, CGFloat, CGFloat)] = [(0.9, 0.2, 0.2), (0.2, 0.7, 0.3), (0.2, 0.4, 0.9), (0.9, 0.8, 0.2)]
    for (index, colour) in colours.enumerated() {
        context.setFillColor(red: colour.0, green: colour.1, blue: colour.2, alpha: 1)
        context.fill(CGRect(x: (index % 2) * width / 2, y: (index / 2) * height / 2, width: width / 2, height: height / 2))
    }
    context.setFillColor(gray: 1, alpha: 1)
    context.fill(CGRect(x: width / 2 - 10, y: 0, width: 20, height: height))
    context.fill(CGRect(x: 0, y: height / 2 - 10, width: width, height: 20))
    let url = URL(fileURLWithPath: name) as CFURL
    let destination = CGImageDestinationCreateWithURL(url, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, context.makeImage()!, nil)
    CGImageDestinationFinalize(destination)
}
write("large.png", width: 12_000, height: 8_000)
write("portrait.png", width: 800, height: 2_400)
write("wide.png", width: 3_000, height: 300)
SWIFT
swift images.swift
echo 'this is not an image' > fake.png
python3 - <<'PY'
rows = "".join(f'<div style="height:100px;border-bottom:1px solid #999;font:20px sans-serif">row {i}</div>' for i in range(100))
open("tall.html", "w").write(f'<!doctype html><meta charset="utf-8"><title>tall</title><body style="margin:0">{rows}</body>')
PY
t() { open "tidyshot://$1"; }   # in the shell you test from: t capture-window
```
`tall.html` is 10,000 pt of rows (20,000 px on a 2x display): open it in Safari, and make the window
cover most of the screen. `sips -g pixelWidth -g pixelHeight <file>` prints a file's pixel size.
Settings are read with `defaults read io.tky.tidyshot <key>`. The log is
`log show --last 5m --predicate 'process == "TidyShot"'`. The custom image is
`~/Library/Containers/io.tky.tidyshot/Data/Library/Application Support/TidyShot/Backgrounds/custom.png`.

An exact capture size, for the arithmetic below: ⌃⇧1, type 1200 and 800 in the W and H fields, Capture.
That is 2400 x 1600 px on a 2x display, and its padded canvas at the default 48 pt is 2592 x 1792 px
(`pad` is 96 px each side). Open the capture in the editor with the pencil button. A portrait
capture of 800 x 1200 pt is 1600 x 2400 px, and its canvas is 1792 x 2592 px.

## Settings and strings
- [ ] Settings > Capture lists, after `Hide desktop icons while capturing` and its caption, the toggle `Add background to window captures` (off), the caption `Puts each window capture on the background below, as the editor's Background tool would.` and an `Edit Background…` button.
- [ ] `defaults read io.tky.tidyshot windowBackground` reads `0` (or does not exist) on a fresh install. Turn the toggle on: it reads `1`. Quit and reopen: the toggle is still on. Turn it off.
  (suite: AppSettingsTests.windowBackgroundDefaultsOffAndPersists)
- [ ] `Edit Background…` opens a sheet on the Settings window: the swatch grid, the `Padding` and `Corner Radius` sliders, `Shadow`, `Aspect Ratio`, and a `Done` button. The sheet opens with the default style: Sunset (swatch 1) ringed, Padding 48 pt, Corner Radius 12 pt, Shadow on, Aspect Ratio Auto.
- [ ] The toolbar in the editor has a `Background` button (the `rectangle.inset.filled` symbol) after Options, with the tool tip `Background`.

## The Settings sheet
- [ ] The `Done` button closes the sheet and leaves the Settings window open on the Capture tab. Return does the same (it is the default button). Reopen: the style is as you left it.
- [ ] `Done` also closes the sheet after you have opened the colour panel from the Solid Colour swatch, and after you have used `Choose Image…` (cancel the open panel too).
- [ ] Change the style in the sheet (swatch, both sliders, Shadow, Aspect Ratio), close it and read the style: `defaults read io.tky.tidyshot backgroundStyle` prints a data blob, not JSON, so use `defaults export io.tky.tidyshot - | plutil -extract backgroundStyle raw -o - - | base64 -d` (or, on the plist itself, `plutil -extract backgroundStyle raw -o - ~/Library/Containers/io.tky.tidyshot/Data/Library/Preferences/io.tky.tidyshot.plist | base64 -d`). It prints JSON that matches. Quit and reopen: the sheet shows the same style.
  (suite: AppSettingsTests.backgroundStyleIsStoredAsJSONAndRoundTrips)
- [ ] A slider moves live and every value shows in points (`48 pt`). Padding stops at 0 and 160, Corner Radius at 0 and 40.
- [ ] Hover each of the twelve gradient swatches: the tool tip is its name, in order Sunset, Ocean, Grape, Peach, Mint, Midnight, Sky, Flamingo, Forest, Lemon, Slate, Berry. Then come `Desktop Picture`, `Solid Colour` and `Custom Image`. Five swatches a row, fifteen in all. The chosen one has an accent ring, and only one at a time.
- [ ] The Aspect Ratio picker lists `Auto`, `1:1`, `4:3`, `3:2`, `16:10` and `16:9`. (suite:
  BackgroundStyleTests.aspectTitlesAndRatios)

## The editor's popover
Open any capture in the editor, click Background.
- [ ] The popover's first row is a `Background` switch, off, with the style editor below it dimmed. The style shown is the one from the Capture tab. The canvas has no background yet.
- [ ] Turn the switch on: the capture gets its padding, rounded corners, shadow and gradient at once, and Zoom to fit shows the whole canvas, not just the capture. Edit > `Undo Background` is available; undo removes it, redo brings it back.
- [ ] Turn the switch off: the capture is as it was, the style editor dims again. The Capture tab's style is unchanged (`defaults read io.tky.tidyshot backgroundStyle`): the editor's changes never write to it.
- [ ] Turn it on again after changing the Capture tab's style: it starts from the new style, not from the last one used in the editor.
- [ ] Opening another popover (Colour, Options) closes this one, and the other way round.
- [ ] Each fill in turn, with the popover open: all twelve gradients draw from the top-left corner to the bottom-right one (the first colour at the top-left). `Solid Colour` fills flat. The preview updates at once, with no flash of the old fill.

## Slider drags and undo
- [ ] Drag Padding from 48 to 120 pt in one drag, watching the preview follow the drag. Edit > Undo reads `Undo Background`; one ⌘Z returns to 48 pt (not to a value part way), and ⇧⌘Z goes back to 120 pt. Same for Corner Radius.
  (suite, in part: EditorBackgroundExportTests.toggleAndStyleChangeAreEachOneUndoStep; the slider handing its drag to
  the draft and its release to one commit is view wiring with no test, for Padding and Corner Radius alike, and stays by
  hand)
- [ ] A drag cut short by the popover closing: start a Padding drag, hold the button, press Escape or click outside the popover (if it closes under a held drag). The new padding is kept as one step: one ⌘Z undoes it. Write down what happened if the popover does not close under a held drag.
- [ ] A swatch click, the Shadow toggle and an Aspect Ratio change are each one step. Make one of each, then ⌘Z three times: they undo in reverse, one at a time.
  (suite: EditorBackgroundExportTests.aSwatchTheShadowAndAnAspectAreThreeStepsThatDirtyTheEditor)
- [ ] Solid colour: choose the Solid Colour swatch (one step), then drag in the colour panel through several colours. All the colour changes with nothing between them are one step: one ⌘Z returns to the fill before the first of them. Pick Padding, then another colour: that colour is a new step.
  (suite: EditorBackgroundExportTests.solidColourRunIsOneUndoStep)
- [ ] Undo then redo with the popover open: the popover's controls follow (the ring moves, the sliders move).
- [ ] After an undo that removes the background, the popover's switch is off.
- [ ] The editor is dirty after any of these (the title shows the edited mark) and clean after Save. (suite, in part:
  EditorBackgroundExportTests.aSwatchTheShadowAndAnAspectAreThreeStepsThatDirtyTheEditor; by hand: the title's edited
  mark)

## The colour panel
- [ ] With Solid Colour chosen, click its swatch (the colour well). The system colour panel opens. Drag in its wheel: the editor's preview follows live. Type a hex value in the panel's sliders tab: it follows.
- [ ] The panel keeps working from the popover. Write down whether the popover stays open while the panel is in front. Click the popover's other controls, then the well again: the panel still feeds the fill. Close the panel, reopen it from the well: it shows the fill's current colour.
- [ ] With the colour panel open, move the popover's Padding slider: both work.
- [ ] Undo after a colour change: the colour well and the preview go back together.
- [ ] Opacity: the panel has no opacity slider, and a colour is always opaque.

## Custom image
Settings > Capture > Edit Background…, or the editor's popover.
- [ ] Before any image is stored, the Custom Image swatch shows a `photo` symbol, tool tip `Choose Image…`. Clicking it opens an open panel that lists images. Cancel: nothing changes.
- [ ] Choose `large.png` (12,000 x 8,000). The fill becomes the custom image, aspect-filled and centred (the white cross is in the middle, the quadrants cut off at the sides or the top). The swatch shows a small picture of it and a small `Choose Image…` button appears under the grid. `custom.png` is in the folder above, and `sips -g pixelWidth custom.png` reads 6000 (scaled down to 6,000 px on the long side).
- [ ] Choose `portrait.png` (800 x 2,400): the fill shows its middle part, scaled up to cover the canvas. Write down how soft it looks on a large canvas.
- [ ] Choose `wide.png` (3,000 x 300) with a portrait capture: the cross sits in the middle. (suite:
  BackgroundCompositorTests.fillImageIsDrawnAspectFillAndCentred)
- [ ] An undecodable file: choose `fake.png`. A notification `Not a usable image` with `fake.png` as its body is posted (even with Show notification off), and nothing changes: the fill, the swatch and `custom.png` are as they were. Try it with no image stored yet: the swatch stays on the photo symbol.
- [ ] Re-choosing the custom image while it is the fill refreshes the preview. In the editor, with Custom Image the fill, choose a different file with `Choose Image…`: the preview shows the new picture at once, with no other change to the style. Do it again with the same file name after editing the file in place.
- [ ] Quit and reopen: the stored image is still the swatch, and still the fill. (suite:
  CustomBackgroundStoreTests.storesTheImageAsCustomPNGAndReadsItBack,
  AppSettingsTests.backgroundStyleIsStoredAsJSONAndRoundTrips)
- [ ] Delete `custom.png` in Finder while the style is Custom Image: the next export (or window capture) draws Sunset instead and nothing fails.
  (suite, in part: BackgroundCompositorTests.nilFillImageDrawsPresetZero,
  CustomBackgroundStoreTests.emptyUntilAnImageIsStored; an export or window capture reading the real store after the
  file is gone stays by hand)
- [ ] A window capture with the setting on and Custom Image, then a window capture after choosing another image: each uses the image current at that moment.

## Desktop picture
- [ ] In the editor, choose `Desktop Picture`: the fill is the picture of the display the editor window is on, aspect-filled. Export it (Save As…): the file has that picture behind the capture.
- [ ] Second display: drag the editor window to the other display. The preview's fill changes to that display's picture within a moment (more than one picture if the displays differ). Write down how long it takes. Export from there: the file has the second display's picture.
- [ ] With Hide Desktop Icons on (the menu item), the picture is still the plain wallpaper, with no icons or widgets.
- [ ] Window capture with the setting on and Desktop Picture: capture a window on the second display. The background is the second display's picture, not the main display's. Move the window across the boundary and capture it again: the display under the window's centre decides.
- [ ] Desktop-picture window capture timing: write down how long a window capture takes from the click to its card, with Desktop Picture compared with Sunset (a stopwatch, or a screen recording). The picture is captured again at each capture, so it costs a little more than a gradient.
- [ ] A dynamic or per-Space wallpaper: capture a window on the Space with the other picture. The background is that Space's picture.

## Padding, corner radius and shadow
With the 1200 x 800 pt landscape capture in the editor, then export with Save As… and check the file with `sips`.
- [ ] Padding 48: the file is 2592 x 1792 px. Padding 0: 2400 x 1600 px, the capture fills the canvas edge to edge. Padding 160: 3040 x 2240 px. On a 1x display the padding is in points one for one: a 1200 x 800 px capture gives 1296 x 896 at 48.
  (suite: BackgroundLayoutTests.paddingAtOneX, .paddingAtTwoX,
  EditorBackgroundExportTests.solidBackgroundExportHasTheLayoutsSizeAndFill)
- [ ] Corner Radius 0: the capture's corners are square. Corner Radius 40: they are clearly round (80 px in the file), and the fill shows in the corners. The default 12 is a soft round.
  (suite: BackgroundLayoutTests.radiusScalesWithTheCapture,
  BackgroundCompositorTests.roundedClipLeavesTheCornerToTheFill)
- [ ] A very small capture (about 40 x 40 pt) with Corner Radius 40: the radius is capped at half the shorter side, so the capture becomes a circle or pill, not an inverted shape.
  (suite: BackgroundLayoutTests.radiusIsCappedAtHalfTheShorterSide)
- [ ] Shadow on: a soft shadow under and slightly below the capture (offset 8 pt down, blur 24 pt, black at 35 %), visible on a light fill. Shadow off: none. With Padding 0 the shadow is cut off by the canvas edge.
  (suite, in part: BackgroundCompositorTests.shadowDarkensTheFillBelowTheContent, .shadowIsOffsetDownNotUp; the shadow's
  soft look and its cut-off at Padding 0 stay by hand)
- [ ] A window capture with transparent corners (Include window shadow off, the corners are transparent either way): the shadow follows the window's own round corners, and the fill shows through the transparent corners with no dark fringe.
- [ ] The saved file at Padding 48, radius 12: open in Preview and zoom to a corner: the edge is smooth (anti-aliased), with no hairline of the old image outside the round corner.

## Aspect ratio
For the 1200 x 800 pt capture (2400 x 1600 px), Padding 48 (a 2592 x 1792 px minimum canvas). Export each with Save As… and read the size.
- [ ] Auto: 2592 x 1792. (suite: BackgroundLayoutTests.autoKeepsTheMinimumCanvas, .paddingAtTwoX)
- [ ] 1:1: 2592 x 2592 (the height grows). 4:3: 2592 x 1944. 3:2: 2688 x 1792 (the width grows). 16:10: 2868 x 1792. 16:9: 3186 x 1792.
  (suite: BackgroundLayoutTests.eachRatioGrowsTheHeightOfWideContent, .contentNarrowerThanTheRatioGrowsTheWidth,
  .paddingCountsBeforeTheRatio)
- [ ] The capture is centred in each: equal space left and right, and above and below (to a pixel). (suite:
  BackgroundLayoutTests.oddSizesCentreWithTheOriginRoundedDown, .contentNarrowerThanTheRatioGrowsTheWidth)
- [ ] For the portrait capture (800 x 1200 pt, 1600 x 2400 px; minimum canvas 1792 x 2592), the ratio is inverted: 1:1 2592 x 2592, 4:3 1944 x 2592, 3:2 1792 x 2688, 16:10 1792 x 2868, 16:9 1792 x 3186.
  (suite: BackgroundLayoutTests.portraitContentInvertsTheRatio)
- [ ] A capture already wider than 16:9 (a wide strip, say 1600 x 200 pt): 16:9 grows its height, not its width. (suite:
  BackgroundLayoutTests.eachRatioGrowsTheHeightOfWideContent)
- [ ] The preview matches the export for every ratio: the canvas in the editor has the same proportions as the saved file, and the fill covers it all.
  (suite: EditorBackgroundExportTests.theShownCanvasHasTheExportsSizeForEveryAspect,
  .baseImageViewPlacesTheBackgroundLayers)
- [ ] Aspect Ratio changes while Zoom to fit is on: the canvas refits to the window. (suite:
  CanvasFitTests.theFitFramesTheBackgroundsCanvasAndRefitsOnAnAspectChange)

## The limit
- [ ] Scrolling capture of `tall.html` (⌃⇧5, Start, scroll, Done) to about 7,000 pt (14,000 px on a 2x display; check with `sips`), open in the editor: the Background popover's switch works, the preview is on, and Save As… writes the file with the padding added.
  (suite: EditorBackgroundExportTests.aBackgroundFitsTallContentAndACropUnderTheLimit)
- [ ] A second scrolling capture of about 9,000 pt (18,000 px): open it in the editor. The popover's switch is dimmed and off, with the caption `Backgrounds work on images up to 16,384 px.`; it cannot be turned on.
- [ ] Near the limit: scroll to a capture of between 16,000 and 16,384 px tall. The switch works, the export is the content plus the padding, and the preview shows the fill. Write down the time Save As… takes (the probe measured 442 ms for 3094 x 16000).
- [ ] Crop a 18,000 px capture to 10,000 px tall, then open the popover: the switch works now (the limit is on the content, the crop), and undoing the crop turns the background off or makes the export fail with `The background could not be drawn.`. Write down which happened.
  (suite: EditorBackgroundExportTests.aBackgroundFitsTallContentAndACropUnderTheLimit)

## The preview
- [ ] The editor preview's drop shadow. With Shadow on, the preview shows a shadow under the capture that matches the export's: same softness, same downward offset, same darkness, and rounded to the same corner. Save As… the file and open it in Preview beside the editor at the same size; compare. Zoom the editor in and out (⌘=, ⌘-, ⌘1): the shadow scales with the image. Shadow off: no shadow in the preview.
- [ ] The preview's rounded corners match the export's at Corner Radius 0, 12 and 40.
- [ ] The preview fill sits behind the capture and extends past it by the padding; the capture is not stretched. Annotations drawn near the capture's edge (a rectangle that touches it, a highlighter stroke that crosses it) are clipped to the round corners, and annotations never draw on the padding.
- [ ] Draw annotations with a background on: a redact, a blur, a pixelate, a text and an arrow. They land on the capture where you point, with the cursor on the capture, not offset by the padding. Select, move and resize one.
  (suite, in part: CanvasFitTests.aPointerOnTheCaptureMapsToItsPixelWithABackground; by hand: the redact, blur,
  pixelate, text and arrow, and the select, move and resize)
- [ ] Zoom to fit (⌘0) fits the whole canvas, and the canvas stays fitted while the window resizes. Actual size (⌘1) shows the canvas at the capture's natural scale. Pan with Space and drag.
  (suite: CanvasFitTests.theFitFramesTheBackgroundsCanvasAndRefitsOnAnAspectChange,
  .aSpaceDragStopsTheFitOnResizeAndFitToViewBringsItBack)
- [ ] Pick the Crop tool: the preview's background hides and the whole capture shows with the crop handles, as in 4b. Return applies the crop; the background frames the crop. Escape cancels: the background returns around the whole capture.
  (suite: EditorBackgroundExportTests.theCropToolHidesTheBackgroundAndCancelOrUndoReturnsItAroundTheWholeCapture,
  .shownBackgroundFramesTheCropInImagePixels)
- [ ] A drag of a Padding slider on a large capture (5120 x 2880 px) is smooth. Write down any lag.
- [ ] Dark mode and light mode: the popover and the sheet are legible in both.

## Crop then background
- [ ] Crop a capture to a part (Crop tool, Return), then turn the background on. The canvas frames the crop, not the whole capture, and nothing outside the crop shows. Save As…: the file is the crop plus padding (for a 1000 x 600 pt crop at 2x and padding 48: 2192 x 1392 px).
  (suite: EditorBackgroundExportTests.backgroundFramesTheCrop, .shownBackgroundFramesTheCropInImagePixels)
- [ ] Background first, then crop: the crop's handles work on the whole capture while the Crop tool is open; after applying, the background re-frames the crop. Undo the crop: back to the whole capture, with the background still on.
  (suite: EditorBackgroundExportTests.theCropToolHidesTheBackgroundAndCancelOrUndoReturnsItAroundTheWholeCapture,
  .shownBackgroundFramesTheCropInImagePixels)
- [ ] Aspect Ratio 16:9 with a crop: the ratio applies to the crop's size. (suite:
  EditorBackgroundExportTests.theShownCanvasHasTheExportsSizeForEveryAspect)

## Copy, Save, Save As… and Upload
With a background on, Padding 48, a visible fill.
- [ ] Copy (⇧⌘C, or ⌘C with nothing selected, since ⌘C with an annotation selected copies the object; or the toolbar button): paste into Preview > File > New from Clipboard. It is the composed image: the fill, the padding, the round corners and the shadow, with annotations.
  (suite, in part: CoordinatorEditorSaveTests.copyWithABackgroundPutsTheComposedCanvasOnTheClipboard; by hand: the
  window's routing of ⇧⌘C, ⌘C and the toolbar button to the copy (`EDPLACE`); Preview is the `pngs` decode)
- [ ] Save (⌘S) on a capture with a local file: the file in the save folder is the composed image (open it). The editor is clean afterwards. The capture's recorded size and thumbnail in Recent Captures follow: the thumbnail shows the background and the size is the canvas's.
  (suite, in part: CoordinatorEditorSaveTests.saveWithABackgroundWritesTheComposedCanvasAndReopensFlat,
  .saveWritesOverTheSaveFolderFileAndUploadsNothing; by hand: the clean state as the window shows it (`EDPLACE`) and the
  thumbnail as drawn)
- [ ] Annotate the saved capture again: it opens as the composed image, flat. The popover's switch is off, because the file is the image; turning it on adds a second background around the first. Write down whether that is what you expect.
  (suite, in part: CoordinatorEditorSaveTests.saveWithABackgroundWritesTheComposedCanvasAndReopensFlat; by hand: the
  popover's switch turned on, whose setter reads `AppSettings.shared` (`BGPOP`), and the switch drawn in the window
  (`EDPLACE`); whether a second background is expected is Tim's call; the test closes the first editor before the
  reopen, since an Annotate while it is open brings it forward with its background)
- [ ] Save As… (⇧⌘S): the file is the composed image; the capture and its record are unchanged. (suite, in part:
  CoordinatorEditorSaveTests.saveAsWithABackgroundWritesTheComposedImageAndLeavesTheCaptureAlone; by hand: the panel
  (`EDSAVEAS`))
- [ ] Upload (⌘U): the uploaded object, opened from the URL, is the composed image (not the original). Upload as New (⌥⌘U) the same. Clop on: the optimised object is the composed image as well.
- [ ] Each of these twice in a row after a change: no stale result (the second export has the second style).
- [ ] The background cannot be drawn: with a capture over 16,384 px, turn the background on is refused (above), so this failure is only reached by the undo path (see The limit). When it happens, Save and Save As… post `Not saved` with `The background could not be drawn.`, Upload posts `Not uploaded` with it, Copy posts `Could not copy image` with it, and the editor stays dirty. Write down what you saw, or that it could not be reached.

## Window captures
Settings > Capture > `Add background to window captures` on, with a style you can tell (Ocean, Padding 48, radius 12, Shadow on).
- [ ] Capture Window (⌃⇧2) on a normal window: the saved file, the card's thumbnail, the clipboard image and the upload all show the window on the Ocean background. `sips` reads the file at the window's size plus 2 x 96 px on each axis.
  (suite, in part: CoordinatorCaptureSaveTests.aWindowCaptureOnOceanIsComposedInTheFileTheClipboardAndTheUpload; by
  hand: the card's thumbnail (`SCREENS`))
- [ ] The same for All-in-One's Window button, a Self-Timer window capture and `t capture-window` (click a window).
- [ ] `Include window shadow` on: the system shadow around the window is part of the image; the background shows round it and the window's shadow stays soft, with no hard rectangle edge. Write down how it looks next to Include window shadow off (a shadow on a shadow).
- [ ] Not included: Capture Area (⌃⇧4), Capture Fullscreen (⌃⇧3), Capture Previous Area (⌃⇧6) and a scrolling capture have no background, with the setting on. A window picked in All-in-One by a drag (an area) has none either.
  (suite, in part: CoordinatorCaptureSaveTests.areaAndFullscreenCapturesKeepThePlainImageWithTheBackgroundOn; by hand:
  which origin Previous Area, a scrolling capture and an All-in-One drag build (`CAPSRC`, `SCROLL`))
- [ ] Each fill kind on a window capture: a gradient (done), Solid Colour (pick a colour in the sheet first), Desktop Picture (the window's display) and Custom Image. Each of the four shows in the file.
- [ ] Padding 0, 160, Corner Radius 0, 40, Shadow off, and each Aspect Ratio on a window capture: the sizes follow the arithmetic above.
  (suite: CoordinatorCaptureSaveTests.aWindowCanvasFollowsTheStyle, BackgroundLayoutTests)
- [ ] A portrait window (narrower than tall) with 16:9: the canvas is portrait (inverted ratio). (suite:
  CoordinatorCaptureSaveTests.aWindowCanvasFollowsTheStyle, BackgroundLayoutTests.portraitContentInvertsTheRatio)
- [ ] The setting off: a window capture is the plain window again, at once (no relaunch). (suite:
  CoordinatorCaptureSaveTests.withTheBackgroundOffEveryCaptureIsPlainAtOnce)
- [ ] Open the window capture in the editor (the card's Annotate): it opens as the composed image with the background baked in, and the popover's switch is off.
  (suite, in part: CoordinatorEditorTests.aComposedWindowCaptureOpensFlatWithNoBackground,
  CoordinatorCaptureSaveTests.aComposedWindowCaptureOpensInTheEditorComposed; by hand: the popover's switch (`BGPOP`),
  drawn in the window (`EDPLACE`))
- [ ] `action=copy`: `t 'capture-window?action=copy'`, click a window: the clipboard image is the window on the background, with no file, no card and no history row. `t 'capture-window?action=upload'` uploads the composed image. Paste to check.
  (suite: CoordinatorCaptureSaveTests.copyAndUploadOfAWindowCarryTheComposedImage)
- [ ] A window larger than the limit cannot be made, so `Background: the window is too large for a background, keeping the window capture` and `Background: no bitmap could be made, keeping the window capture` have no practical way to force. They are checked by code reading: `withWindowBackground` logs one of the two and returns the plain result, with no notification. Write down any other way you used.
  (suite, in part: CoordinatorCaptureSaveTests.aWindowTooLargeForABackgroundIsSavedPlainWithOneLine; by hand: `no bitmap
  could be made`, by code reading)
- [ ] Two window captures in quick succession (the second before the first's card shows): both get the background, and the saved files do not mix.
  (suite: CoordinatorCaptureSaveTests.twoWindowCapturesAtOnceAreEachComposedInTheirOwnFile)

## Toolbar width
- [ ] Open the editor and drag its left or right edge in as far as it will go. The toolbar shows every item, including `Background`, with no overflow chevron (`»`) at the right. Its minimum width is 1062 pt. On a 1280 pt wide display (or after switching to that resolution) the window opens no wider than 90 % of the display and still shows every item.
- [ ] A small capture (200 x 100 px) opens the editor at the toolbar's width, not narrower. (suite:
  EditorWindowGeometryTests.initialSizeUsesTheToolbarMinimum, EditorToolbarTests.measuredToolbarFitsASmallDisplay)

## Regression
- [ ] With the setting off and the editor's background off, a window capture, an area capture and an edit's Save are as before: the same sizes, no padding.
  (suite: CoordinatorCaptureSaveTests.withTheBackgroundOffEveryCaptureIsPlainAtOnce,
  EditorBackgroundExportTests.noBackgroundExportsTheCaptureAsBefore)
- [ ] Phase 7b: Capture Text and Hide desktop icons still work, and a window capture with Hide desktop icons on and the background setting on has the picture, not icons, in a desktop-picture fill.
- [ ] An old capture's editor, opened with no background ever set, looks as before (no extra layers, no change in Fit).
  (suite: CanvasFitTests.theFitFramesTheBackgroundsCanvasAndRefitsOnAnAspectChange,
  EditorBackgroundExportTests.noBackgroundExportsTheCaptureAsBefore, .baseImageViewPlacesTheBackgroundLayers)
- [ ] ⌃⇧1 to ⌃⇧6, the overlay, pins and URL commands behave as in the Phase 6b checklist.

## Observations
Write these into the "Phase 7c (built)" notes of spec 2.11:
- Whether the editor preview's shadow matched the export's (offset, softness, strength), and anything that differed.
- Whether the colour panel stayed usable from the popover, and whether the popover stayed open.
- How a held slider drag behaved when the popover closed.
- How long the preview took to follow the editor window to a second display.
- A desktop-picture window capture's time against a gradient's.
- How a window capture looks with Include window shadow on.
- The time Save As… takes on a capture near 16,384 px, and what undoing a crop on an over-limit capture did.
- Anything above that failed.
