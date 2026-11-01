# Phase 6b manual test checklist

Run after any change to All-in-One (`SelectionAdjust`, `AllInOneToolbar`, the All-in-One mode of
`SelectionView` and `SelectionController`), `TidyShot/SelfTimer/`, `TidyShot/Pin/`,
`TidyShot/URLScheme/`, `AppDelegate`'s URL handler, or the capture functions of `AppCoordinator`.
Automated tests cover the selection adjust geometry, the toolbar placement, the self-timer countdown,
the pin geometry, the URL parser, the URL rect geometry, the gate, the handler's queue and routing,
the capture intent, the new settings keys and the shortcuts; everything here needs real windows,
real displays, real senders and eyes. The Phase 6a checklist still covers the overlay, drag-out,
freeze and Capture Previous Area, the 4a and 4b checklists the editor and the Phase 5 checklist the
scrolling session; run them too after a change to those paths.

Setup: a fresh **Release** build (`xcodebuild -project TidyShot.xcodeproj -scheme TidyShot
-configuration Release -derivedDataPath .build-rel build`), Screen Recording granted, save folder
set to Desktop, a working destination saved in Settings > Upload, "Show notification" on in
Settings > General, "Show Quick Access overlay after capture" on in Settings > Overlay, a second
display if you have one (ideally at a different scale, arranged above or to the left of the main
one), Raycast and Keyboard Maestro if you use them (skip their rows otherwise), and the 65,536 px
capture of the Phase 5 checklist still in Recent Captures. The 6a test pages in `~/Desktop/p6` (make
them as `docs/testing/phase-6a-manual-checklist.md` says if they are gone). Capture only made-up
data: a capture may be uploaded and the link may be shared. Note how the build is signed
(`Config/Local.xcconfig`).

Make the link page and a shell helper once.
```bash
mkdir -p ~/Desktop/p6b && cd ~/Desktop/p6b
cat > links.html <<'HTML'
<!doctype html><meta charset="utf-8"><title>TidyShot links</title>
<style>body{font:18px -apple-system,sans-serif;margin:40px}a{display:block;margin:10px 0}</style>
<a href="tidyshot://capture-area?action=upload">capture-area, upload (needs your drag)</a>
<a href="tidyshot://capture-fullscreen?action=copy">capture-fullscreen, copy (silent)</a>
<a href="tidyshot://capture-area?x=0&amp;y=0&amp;width=300&amp;height=200&amp;action=copy">capture-area with a rect, copy (silent)</a>
<a href="tidyshot://restore-recently-closed">restore-recently-closed</a>
HTML
t() { open "tidyshot://$1"; }   # in the shell you test from: t 'capture-area?action=save'
```
`links.html` opens with `open -a Safari ~/Desktop/p6b/links.html` (Chrome the same way). `t` runs a
command from Terminal. The log of URL commands is
`log show --last 5m --predicate 'process == "TidyShot"' | grep "URL command"`. Settings are read
with `defaults read io.tky.tidyshot <key>`.

## Settings and strings
- [ ] Settings > General ends with a `URL commands` section: `Allow URL commands (tidyshot://)` (on), `Allow URL commands that capture without a selection` (off, greyed while the first is off), and the caption `capture-fullscreen, capture-previous-area, and capture-area or capture-text with x, y, width and height capture at once. Any app on this Mac, and any web page you let open TidyShot, can send them, and an allowed command lets the sending app read the result from the clipboard.` (Fresh values: `for k in urlCommandsEnabled urlCommandsAllowSilent allInOneAspectLock selfTimerSeconds; do defaults delete io.tky.tidyshot $k; done`, then relaunch.)
- [ ] Settings > Shortcuts lists, after the four capture recorders, `All-in-One:` (⌃⇧1), `Capture previous area:` (⌃⇧6), `Self-timer:` (empty), `Capture text:` (⌃⇧7), `Record screen:` (⌃⇧8), `Record fullscreen:` (empty) and `Restore closed overlay:` (empty). Record a combination for `Self-timer:` for the Self-Timer section and clear it at the end. Change `All-in-One:`, confirm the new keys work and ⌃⇧1 does not, then reset it.
- [ ] Settings > Capture has a `Self-timer` picker with `3 seconds`, `5 seconds` (selected) and `10 seconds`, after `Edit Background…`, at the end of the first section.
- [ ] The menu bar menu reads `All-in-One  ⌃⇧1`, `Capture Area  ⌃⇧4`, `Capture Window  ⌃⇧2`, `Capture Fullscreen  ⌃⇧3`, `Capture Scrolling  ⌃⇧5`, `Capture Previous Area  ⌃⇧6`, `Self-Timer`, `Capture Text  ⌃⇧7`, `Record Screen  ⌃⇧8`, `Record Fullscreen`; a separator; Recent Captures (with a chevron), `Restore Closed Overlay`, Retry Failed Uploads (only with a failed upload), Reveal Last Capture, `Hide Desktop Icons`; a separator; `Unlock Pinned Screenshots` and `Close Pinned Screenshots` when they apply, Settings… `⌘,`, Quit TidyShot `⌘Q`. Every capture item is disabled while a capture, a countdown or a scrolling session runs.
- [ ] Settings persist: set the aspect lock on (All-in-One toolbar), the timer to 10 seconds, and both URL toggles the other way, quit and reopen: `defaults read io.tky.tidyshot <key>` reads `1`, `10`, `0`, `1` for `allInOneAspectLock`, `selfTimerSeconds`, `urlCommandsEnabled`, `urlCommandsAllowSilent`, and the panes show the same. Set them back.
  (suite: AppSettingsTests.allInOneAspectLockDefaultsOffAndPersists, .selfTimerSecondsDefaultsToFiveAndPersists,
  .urlCommandSettingsRoundTripThroughASecondInstance)

## All-in-One
- [ ] No stored area (`defaults delete io.tky.tidyshot lastAreaRect`, relaunch): ⌃⇧1 opens like Capture Scrolling's selection: crosshair, loupe, and the window under the pointer highlighted.
- [ ] Drag a rectangle: eight handles appear and the toolbar sits centred under it, reading left to right `W` and `H` fields, the lock, a separator, Capture, Window (greyed), Fullscreen, Scrolling, Timer, Cancel. Each button's tooltip is 2.9's: `Lock aspect ratio`, `Capture area (Return)`, `Capture the window with transparent corners`, `Capture this display`, `Scrolling capture of this area`, `Capture this area after 5 seconds`, `Cancel (Escape)`.
- [ ] Click a window without dragging: the rect is the window's frame (clipped to its display) and Window is enabled; resizing, moving or nudging it keeps Window enabled. Drag a new rect: Window is greyed again. With a rect showing, click (no drag) outside it on another window: that window's frame becomes the rect; click outside on the bare desktop: the rect stays.
  (suite: SelectionViewTests.aClickWithoutADragTakesTheHighlightedWindowAndADragDoesNot,
  SelectionOutcomeTests.allInOneModeDragsAnAreaOrClicksAWindow)
- [ ] Drag each of the eight handles: the rect resizes only that handle's sides; it never flips, never gets smaller than 4 pt on a side and never leaves its display. Drag slowly across a half-point (a scaled display or a trackpad makes them): the edges you are not dragging do not move, not even by a point, and the moving edge lands on a whole point. Drag inside: it moves, clamped at every edge. Drag outside: a new rect starts.
  (suite: SelectionViewTests.aPressOutsideTheRectStartsANewOne, SelectionAdjustTests.eachHandleMovesOnlyItsEdges,
  .resizingStopsAtTheMinimumSide, .resizingIsClampedToTheBounds, .halfPointDragsKeepTheOppositeEdges,
  .insideMovesTheRectAndClampsAtEachEdge)
- [ ] The cursor is the resize cursor on each handle, an open hand inside (closed while moving), an arrow over the toolbar and the crosshair elsewhere. While a drag, resize or move runs the size label shows and the toolbar hides; it comes back at mouse-up.
- [ ] Arrow keys move the rect 1 pt, Shift-arrows 10 pt, clamped at the edges; the W and H fields keep their values. Command-Return and Command-arrows neither capture nor nudge.
  (suite: SelectionViewTests.commandKeysNeitherCaptureNorNudgeAndShiftArrowMovesTen,
  SelectionAdjustTests.arrowsNudgeByOneOrTenAndStopAtTheEdge, .nudgesStopAtTheBounds,
  SelectionViewArmingTests.aDisarmedRectStillNudgesAndCancels)
- [ ] Type 640 into `W` and press Return: the width becomes 640, growing from the top-left corner, clamped at the display edge; nothing is captured, and a second Return captures. A value larger than the room (or one that makes the rect poke out of the display) is clamped or moves the rect inside the display, and the field then shows the size the rect really has, not what you typed. The same for `H`. Tab moves between the two fields.
  (suite: SelectionViewTests.aTypedWidthResizesFromTheTopLeftWithoutCapturing,
  SelectionAdjustTests.typedSizeGrowsFromTheTopLeft, .typedSizeIsClampedAndMovedInside)
- [ ] Lock on (`lock` shown): a corner or edge drag keeps the ratio the rect had when the lock was turned on; typing W changes H and the other way. Lock off (`lock.open`) frees it. The lock is remembered across launches. With two displays, turn the lock on over one, then draw a rect on the other: the lock is still on there, and the toolbar's symbol agrees.
- [ ] Toolbar placement: a rect near the bottom of the display puts the toolbar above it; a rect that fills the display puts it inside its bottom edge; a rect at the left or right edge keeps the toolbar on screen; a rect at the top of a notched display never puts it under the notch or the menu bar.
  (suite, in part: AllInOneToolbarPlacementTests.belowTheSelectionAndCentred, .aboveWhenThereIsNoRoomBelow,
  .insideTheBottomEdgeWhenNeitherFits, .clampedToTheScreensSides; the notch inset read from a real screen's
  `safeAreaInsets` stays by hand)
- [ ] Capture (button, Return with no field editing, or a double-click inside): the area is saved by the after-capture action, the card appears, and ⌃⇧6 captures the same area again. The toolbar, handles and dimming are not in the image.
- [ ] Window: the clicked window with transparent corners (and the shadow, when `Include window shadow` is on). Fullscreen: the overlay goes first, then the rect's display is captured with no dimming, handles, toolbar or Quick Access card in it. Scrolling: the scrolling panel opens on the rect; a rect under 100 pt tall is refused with `Select an area at least 100 points tall.` Timer: the self-timer countdown runs on the rect, then captures it.
- [ ] Cancel and Escape (also with a field focused but not editing) close the overlay with nothing captured. While a field is being edited, Return applies the value (the field shows the real size afterwards, even when it was clamped) and Escape drops what you typed, shows the rect's real size again and leaves the field; neither captures or cancels, and a second Escape cancels. ⌘-Tab to another app and back: the overlay is still up (focus loss does not cancel, as in the other modes) and Escape cancels it.
- [ ] A stored area on a connected display: ⌃⇧1 opens with it selected and adjustable. Store an area on the second display, unplug it, press ⌃⇧1: it opens with no rect.
  (suite, in part:
  CoordinatorCaptureSourceTests.allInOneOpensOnThePreviousAreaArmedOrAURLRectDisarmedAndEscapeStoresNothing,
  SelectionAdjustTests.restoreKeepsARectOnItsDisplay, .restoreRefusesARectOffEveryDisplay; by hand: the rect shown
  selected and adjustable, and none when its display is unplugged (SelectionController.placePreselected, `SELINT`))
- [ ] Freeze on: the All-in-One overlay shows the frozen screen (open Safari's File menu first) and Capture cuts from it; Window, Fullscreen, Scrolling and Timer capture live.
- [ ] Show cursor on, freeze off: the All-in-One Capture and Window captures have no pointer and no crosshair; with freeze on the Capture pointer is where it was when ⌃⇧1 was pressed. Fullscreen shows the pointer as an arrow, never the crosshair.
- [ ] Two displays: the rect and the toolbar stay on the display the rect started on. Draw a rect on one display, then drag on the other: the selection moves there and the first display loses its rect and toolbar; Return captures on the display holding the rect.
- [ ] All-in-One captures behave like any other in upload-only mode, in the Quick Access stack and in Recent Captures.
  (suite, in part: CoordinatorCaptureSaveTests.anUploadOnlyCaptureKeepsOnlyAPendingFileUntilItsUploaded; by hand: Quick
  Access stack and Recent Captures on screen (`SCREENS`), All-in-One building the captures (`CAPSRC`))

## Self-Timer
- [ ] Menu `Self-Timer` (or its recorded shortcut): the overlay shows the crosshair, the loupe and the window highlight. Drag an area: the overlay goes, a 96 pt rounded square appears centred on the area with `5` in large monospaced digits and `Esc to cancel` under it, and a dashed frame marks the area. It counts 5, 4, 3, 2, 1, once a second; at zero both disappear and the capture is saved. Neither is in the image, nor is a Quick Access card. Escape in the selection overlay, before the countdown, still cancels the selection.
- [ ] Click a window instead: the countdown centres on the window and the result is a window capture with transparent corners. Move the window during the countdown: the capture follows it. Close it before zero: `The window is no longer on screen.` titled `Self-timer`, and no capture. Start a countdown on the second display and unplug it before zero: `The display is no longer connected.`, no capture.
- [ ] A menu: start a timer over Safari's menu bar area, then open the File menu during the countdown and hold it open: the image contains the open menu. The same with a tooltip (`~/Desktop/p6/freeze.html`). During the countdown the app you clicked before is frontmost (its name in the menu bar), and a menu opened from the keyboard there works: TidyShot gave up activation.
- [ ] The countdown panel and frame are click-through: clicking under them reaches the app beneath. (suite:
  SelfTimerTests.theCountdownPanelAndTheScrollFrameLetClicksThrough)
- [ ] The badge sits at the screen-saver level: pin a screenshot over the area first (the Pin section), start a self-timer on it, and the badge and the dashed frame are drawn over the pin; they also show over a full-screen app, the menu bar and the Dock.
- [ ] Escape, with Safari frontmost, cancels: both panels go and nothing is captured. After that Escape works normally in Safari (it is not swallowed). Escape still cancels a scrolling session (Phase 5).
- [ ] While the countdown runs, ⌃⇧4, the Self-Timer shortcut and the other shortcuts do nothing and the menu's capture items are disabled; the countdown is not disturbed.
- [ ] A rect near the top-right corner of the screen: the badge stays fully on screen. On a second display the badge and the frame are on that display.
- [ ] `3 seconds` and `10 seconds` in Settings > Capture count from 3 and 10. All-in-One's Timer button uses the same setting, and its tooltip follows it.
- [ ] Show cursor on: the pointer is in the self-timer capture where it is at zero. Freeze on: ignored, the capture is live.
- [ ] A self-timer area becomes the previous area (⌃⇧6 captures it again); a window does not.

## Pin to screen
- [ ] A card's right column is Annotate, Pin (`pin`, help `Pin to screen`), Delete; the context menu has `Pin to Screen` after `Annotate`. Pin an area capture: a borderless panel with a hairline border shows the image at its point size exactly over the spot it was captured from. The card stays, and the keyboard stays with the app you were typing in.
- [ ] Pin a window or fullscreen capture: centred on the pointer's screen, scaled down to fit 80 % of the visible frame when larger. Pin an older card in the stack: centred on the pointer's screen. Pin the same capture twice: the second click brings the first pin forward, no second pin opens. Pin from a restored card and from an upload-only capture after its upload: it loads from the file, the drag copy or the bucket, with `Pinning the capture…` posted while it downloads.
- [ ] A pinned window capture keeps its transparent corners, and the pin's shadow follows them.
- [ ] The pin floats above other apps' windows, on every Space, and over a full-screen app. A single click on the pin gives it the keyboard (the next arrow key moves it, with no second click) while TidyShot does not become the active app (the menu bar keeps the other app's name).
- [ ] Drag anywhere to move. Drag an edge or corner: it resizes with the aspect ratio fixed, never below 40 pt on a side.
- [ ] Click the pin, then: arrows move it 1 pt, Shift-arrows 10 pt; ⌘+ and ⌘- zoom by 10 % about the centre in whole points, never past the screen's visible frame and never below 40 pt on the shorter side; ⌘0 returns to actual size (a capture larger than the screen's visible frame comes back fitted to it, not cut off); ⌘C copies the image (Preview > New from Clipboard matches the capture's pixel size); Escape and ⌘W close it. Option-scroll changes opacity in steps of 5 %, never below 10 % or above 100 %.
- [ ] Right-click: `Copy Image`, `Save As…`, `Annotate`, `Opacity` (`100%`, `90%`, `75%`, `50%`, `25%`, the current one checked), `Actual Size`, `Lock`, a separator, `Close`. Each works (`Actual Size` is capped to the screen as ⌘0 is); Save As… is the card's (the same panel and suggestion).
- [ ] `Lock`: the border goes and clicks pass through to the app beneath. The status menu then lists `Unlock Pinned Screenshots` and `Close Pinned Screenshots` before Settings…; Unlock makes every pin clickable again; Close closes them all. With no pins neither item shows; with only unlocked pins only `Close Pinned Screenshots` shows.
- [ ] Pins are in captures: ⌃⇧3 with a pin showing contains the pin. A scrolling capture over a pin leaves it out.
- [ ] Delete the capture (card, Recent Captures): its pins close. Quit with pins showing: they go; relaunch: no pins.
- [ ] A capture pruned by retention closes its pins: set Overlay > `Keep history for 1 days`, pin a capture more than a day old (Recent Captures, one saved to the save folder), then take a new capture, which prunes the history: the old record leaves Recent Captures and its pin closes.
- [ ] Pin the 65,536 px capture: it shows as a whole fitted strip (not cut to its top), within a second or two; ⌘0 and `Actual Size` fit it to the screen's visible frame (its point size is taller than any screen), and ⌘+ stops there too; Activity Monitor's memory for TidyShot grows by tens of megabytes, not gigabytes.
- [ ] On a 2x display the pin at actual size is as sharp as the capture; zoomed out it stays smooth (trilinear). A pin dragged to the second display keeps its point size.

## URL scheme: which build owns it (probe 4)
- [ ] Quit TidyShot. List every registered copy: `LSR=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister; $LSR -dump | grep -i -B2 -A8 tidyshot | grep -E "path:|claimed schemes" | sort -u`. Write down the paths. Unregister each stale one (`$LSR -u <path>`, the Debug build in `.build`, DerivedData, old copies), register the Release build (`$LSR -f .build-rel/Build/Products/Release/TidyShot.app`), and list again: one path claims `tidyshot:`.
- [ ] `plutil -p .build-rel/Build/Products/Release/TidyShot.app/Contents/Info.plist | grep -A6 CFBundleURLTypes` shows `io.tky.tidyshot` and `tidyshot`; `codesign -d --entitlements - .build-rel/Build/Products/Release/TidyShot.app` shows the same four entitlements as before this phase (`app-sandbox`, `files.bookmarks.app-scope`, `files.user-selected.read-write`, `network.client`) and no `com.apple.security.get-task-allow`. A Debug build (`.build`) does carry `get-task-allow`; that is expected, and it is why you test URLs against the Release build.
- [ ] Cold launch: with TidyShot not running, `t 'capture-area?action=save'` starts the Release app (Activity Monitor > TidyShot > Open Files and Ports shows `.build-rel`) and, once it has started, opens the selection; the capture is saved. No Settings window and no other window opens.

## URL scheme: commands
URL commands on, the silent toggle on for this section.
- [ ] `t capture-area`: the selection opens; the capture follows the after-capture action. `t capture-window`: window mode. `t capture-fullscreen`: the display under the pointer, at once. `t capture-previous-area`: the last area again, at once.
  (suite, in part: URLCommandHandlerTests.everyCommandReachesItsCaptureFunction; what each capture then does (the
  selection, window mode, the display under the pointer, the previous area) is the hotkey path's and stays by hand)
- [ ] `t all-in-one`: All-in-One with the last area preselected. `t 'all-in-one?x=0&y=0&width=500&height=400'`: All-in-One with that rect preselected at the bottom-left of the display under the pointer, adjustable; Escape leaves the stored previous area unchanged.
  (suite, in part:
  CoordinatorCaptureSourceTests.allInOneOpensOnThePreviousAreaArmedOrAURLRectDisarmedAndEscapeStoresNothing,
  URLCommandHandlerTests.everyCommandReachesItsCaptureFunction,
  URLCommandGeometryTests.theOriginIsTheBottomLeftOfTheMainDisplay; by hand: the rect shown adjustable on the overlay
  (`SELINT`))
- [ ] A URL-opened All-in-One needs a touch before a key captures: run `sleep 3; open 'tidyshot://all-in-one?action=copy&x=0&y=0&width=500&height=400'` in Terminal and keep pressing Return in a TextEdit window as the overlay appears: nothing is captured (no shutter, the clipboard unchanged), the arrows still move the rect and Escape still cancels. Again, then click once inside the rect (or change W, or toggle the lock): Return now captures. A double-click inside the rect as the first touch arms without capturing; a second double-click captures. The same with `t all-in-one` (no rect, previous area preselected). ⌃⇧1 and the menu's All-in-One on the previous area capture on Return at once, as before.
  (suite, in part:
  CoordinatorCaptureSourceTests.allInOneOpensOnThePreviousAreaArmedOrAURLRectDisarmedAndEscapeStoresNothing,
  SelectionViewArmingTests.aDisarmedRectIgnoresReturnUntilAPress, .aDisarmedRectStillNudgesAndCancels,
  .aDoubleClickCapturesOnlyWhenArmedBeforeIt, .aNewRectIsArmed,
  URLCommandHandlerTests.everyCommandReachesItsCaptureFunction; by hand: arming by a W change or the lock toggle, and
  Return typed in another app as the overlay appears)
- [ ] `t self-timer`: the self-timer selection, then the countdown. (suite, in part:
  URLCommandHandlerTests.everyCommandReachesItsCaptureFunction; the self-timer selection and countdown stay by hand)
- [ ] `t capture-scrolling`: the scrolling selection. `t 'scrolling-capture?x=0&y=0&width=600&height=800'`: no selection; the dashed frame and the panel open on that rect, TidyShot is not made the active app and the panel does not take the keyboard, so a Return typed in the frontmost app does nothing; nothing is captured until you click Start (or press ⌃⇧5). Escape (global) cancels. Leave it unstarted: after 60 seconds the frame and the panel go by themselves, nothing is saved, and ⌃⇧4 works again. A session started within the minute is not cut short. A cancelled session leaves Previous Area as it was; a finished one sets it to the rect. A rect under 100 pt tall posts `Select an area at least 100 points tall.`
- [ ] `t restore-recently-closed`: the last closed card comes back, as the menu item does. (suite, in part:
  URLCommandHandlerTests.everyCommandReachesItsCaptureFunction, ClosedOverlaysTests.newestFirst,
  .popSkipsDeletedAndShownIds; the card coming back is `restoreClosedOverlay` behind the screen seam and stays by hand)
- [ ] The path forms work too: `open 'tidyshot:capture-window'` and `open 'tidyshot:///capture-window'`; and `t CAPTURE-WINDOW`.
  (suite: URLCommandTests.everyCommandParsesFromThePath, .theSchemeTheCommandAndTheNamesIgnoreCase)
- [ ] Hotkeys and menu items behave as before: the after-capture action, no extra notification, no subtitle. (suite, in
  part: CaptureIntentTests.standardIsTheGeneralSettingWithNothingAfter; that the hotkeys and the menu pass `.standard`
  is a code read, and the capture itself stays by hand)

## URL scheme: actions
Use `capture-window` (click a window each time).
- [ ] No `action`: the after-capture action in General. (suite:
  CaptureIntentTests.noActionIsTheAfterCaptureActionInGeneral,
  URLCommandHandlerTests.everyCommandReachesItsCaptureFunction)
- [ ] `action=upload` with General set to `Save and copy image`: saved, uploaded, URL on the clipboard. With `Upload only, keep no local file`: uploaded with no file in the save folder.
  (suite: CoordinatorCaptureSaveTests.actionUploadSavesUploadsAndCopiesTheLinkUnderEitherSetting,
  CaptureIntentTests.uploadUploadsUnderEverySetting)
- [ ] `action=save` under `Upload only`: saved in the save folder, the image copied (with General's copy toggle on), no upload.
  (suite: CoordinatorCaptureSaveTests.aSaveAndCopyImageCaptureSavesCopiesAndAsksForNoDestination,
  CaptureIntentTests.saveIsSaveAndCopyImageUnderEverySetting)
- [ ] `action=copy`: the image is on the clipboard (Preview > New from Clipboard), and nothing else: no file in the save folder or `pending`, no card, no Recent Captures row, no upload; the shutter sound plays (with Play sound on); `Image copied` shows the pixel size with the subtitle `From <sender>`. With Show notification off, no notification. The newest card's Annotate still opens its own capture.
  (suite: CoordinatorCaptureSaveTests.copyOnlyPutsTheImageOnTheClipboardAndNothingElse,
  CaptureIntentTests.copyPutsTheImageOnTheClipboardOnly)
- [ ] `action=annotate`: the after-capture action runs, then the editor opens on the new capture and its card closes. `action=pin`: the action runs, then a pin opens and the card stays.
  (suite, in part:
  CoordinatorEditorUploadTests.annotateTheNewestCardSaveThenUploadWritesTheFileThenUploadsAndCopiesTheURL,
  CaptureIntentTests.annotateRunsTheAfterCaptureActionThenOpensTheEditor, .pinRunsTheAfterCaptureActionThenPins,
  CoordinatorCaptureSaveTests.annotateRunsTheActionThenOpensTheEditorOnTheNewCapture; by hand: the `action=pin` half
  (`PINS`))
- [ ] `action=UPLOAD` works like `upload`. `action=print` posts `Unknown action “print”. Use upload, save, copy, annotate or pin.`
  (suite: URLCommandTests.everyActionParsesOnEveryCaptureCommand, .anUnknownOrEmptyActionIsAnError,
  .errorMessagesAreTheSpecStrings)

## URL scheme: rect coordinates
Silent toggle on. Coordinates are points from the display's bottom-left corner (as in CleanShot).
- [ ] `t 'capture-area?x=0&y=0&width=300&height=200'` captures the bottom-left corner of the display under the pointer (the Dock's end or the desktop corner); `sips -g pixelWidth -g pixelHeight` reads 300 x 200 times the display's scale.
- [ ] With the display's size in points W x H (System Settings > Displays, "looks like"), `x=W-300&y=H-200&width=300&height=200` captures the top-right corner with the menu bar clock.
- [ ] `&display=1` captures on the main display whatever the pointer; `&display=2` on the second (`NSScreen.screens` order), also when it is above or to the left of the main one. `&display=3` with two displays posts `There is no display 3.`
- [ ] A rect running past the display edge is clipped to it (`x=-100&y=-100&width=400&height=300` gives 300 x 200). A rect fully off the display (`x=99999&y=0&width=10&height=10`) posts `The area leaves less than a point on display 1.`
  (suite: URLCommandGeometryTests.aRectPartlyOffItsDisplayIsClipped, .aRectThatLeavesLessThanAPointIsOutside,
  URLCommandHandlerTests.errorsArePostedAndRunNothing)
- [ ] A `capture-area` URL rect becomes the previous area: ⌃⇧6 captures it again. A `capture-scrolling` rect becomes it only once the stitched image is saved (see URL scheme: commands).
  (suite, in part:
  CoordinatorCaptureSourceTests.windowAndFullscreenCapturesLeaveThePreviousAreaAndAScrollingDragStoresIt; by hand: a
  capture-scrolling rect becoming the previous area only once the stitched image is saved (`SCROLL`))
- [ ] Show cursor on: the pointer is in a URL rect capture when it lies inside the rect.

## URL scheme: security
- [ ] Silent toggle off (default): `t 'capture-fullscreen?action=copy'`, `t capture-previous-area` and `t 'capture-area?x=0&y=0&width=100&height=100&action=copy'` capture nothing and leave the clipboard as it was (copy some text first; `pbpaste` prints it before and after, and `osascript -e 'clipboard info'` lists no image type after). Each posts `TidyShot URL command` with `<command> from <sender> captures without a selection. Allow it in Settings > General > URL commands.` and the subtitle `From <sender>` (no ` from …` and no subtitle when the sender is unknown).
  (suite: URLCommandHandlerTests.silentCommandsAreRefusedByDefaultNamingTheSender,
  URLCommandGateTests.theRefusalNamesTheSenderWhenItIsKnown)
- [ ] Silent toggle off: `capture-area` without a rect, `capture-window`, `all-in-one` with and without a rect, `self-timer`, and `capture-scrolling` with and without a rect all still run, because each waits for your drag, click or Start.
  (suite: URLCommandGateTests.commandsThatWaitForTheUserRunWithTheSecondToggleOff,
  URLCommandHandlerTests.commandsThatWaitForTheUserRunWithSilentCapturesOff)
- [ ] Master toggle off: every command above, `restore-recently-closed`, and `t nonsense` post `URL commands are off. Turn them on in Settings > General.` and do nothing.
  (suite: URLCommandHandlerTests.withURLCommandsOffEveryURLIsRefusedAlike,
  URLCommandGateTests.withURLCommandsOffEveryCommandIsRefused)
- [ ] From Safari and Chrome, open `~/Desktop/p6b/links.html` and click each link: the browser asks whether to open TidyShot; after you allow it, the silent links are refused naming the browser, and the others run. Write down whether Chrome offers "Always allow".
- [ ] Raycast: a Quicklink to `tidyshot://capture-area?action=upload` runs. Keyboard Maestro: an Open URL action for `tidyshot://capture-fullscreen?action=copy` is refused with the toggle off and runs with it on. Shortcuts: an Open URLs action for `tidyshot://capture-window` runs.
- [ ] Fill in the sender each source produces (the notification's subtitle and the log line):

  | Source | Sender shown |
  |---|---|
  | Terminal (`open`) | |
  | Raycast | |
  | Keyboard Maestro | |
  | Shortcuts | |
  | Safari | |
  | Chrome | |

## URL scheme: hostile input
Both toggles on. Each line posts the error named and captures nothing; nothing crashes.
- [ ] `t 'capture-area?x=1e3&y=0&width=10&height=10'`, `width=nan`, `width=inf`, `width=0x10`, `width=+5`, `width=-5`, `width=0`, `x=99999999999999999999`, `x=100001`, and a missing `height`: `x, y, width and height must be given together, as numbers, with width and height above 0.`
  (suite: URLCommandTests.onlyPlainDecimalsAreNumbers, .widthAndHeightMustBeAboveZero,
  .hugeAndOverlongNumbersAreRefused, .theRectValuesComeTogetherOrNotAtAll, .errorMessagesAreTheSpecStrings)
- [ ] `t 'capture-area?action=upload&action=copy'` and `t 'capture-area?action=copy&ACTION=copy'`: `“action” is given more than once.`
  (suite: URLCommandTests.aRepeatedParameterIsAnError, .errorMessagesAreTheSpecStrings)
- [ ] `t 'capture-fullscreen?action=upload%26action%3Dcopy'`: `Unknown action “upload&action=copy”. …`, not a copy. `t 'capture%2Dwindow'` runs Capture Window (percent-encoding is decoded first, and the gate sees the decoded command: `t 'capture%2Dfullscreen'` is refused with the silent toggle off).
  (suite: URLCommandTests.percentEncodingIsDecodedBeforeMatching,
  URLCommandHandlerTests.silentCommandsAreRefusedByDefaultNamingTheSender)
- [ ] `t 'capture-area?action=%25@%25n%25s'`: `Unknown action “%@%n%s”. …`; the log shows `%@%n%s` as plain text. `t 'capture-area?action=%E2%80%AEdaolpu'`: the notification shows `daolpu` with no reversed text. A 200-character action is cut at 40 characters with `…`.
- [ ] `t 'capture-area?display=7'` with no rect opens the normal selection (display counts only with a rect); `t 'capture-area?display=abc'` posts `There is no display abc.`
  (suite: URLCommandHandlerTests.aDisplayWithoutARectOpensTheNormalSelection,
  URLCommandTests.theDisplayIsAWholeNumberFromOne)
- [ ] Unknown commands, including CleanShot's file-path ones: `t pin`, `t 'open-annotate?filepath=/etc/hosts'`, `t 'add-quick-access-overlay?filepath=/tmp/x.png'`, `t open-settings`: `Unknown command “…”.` No file is read (no sandbox prompt, nothing in the log about the path).
  (suite: URLCommandTests.anUnknownCommandIsAnError, .errorMessagesAreTheSpecStrings)
- [ ] Unknown parameters are ignored: `t 'capture-window?foo=1&filepath=/etc/hosts'` runs Capture Window. (suite:
  URLCommandTests.parametersACommandDoesNotTakeAreIgnored, .noActionLeavesItToTheAfterCaptureSetting)

## URL scheme: launch, queue and busy
- [ ] Cold launch with the silent toggle off: quit TidyShot, `t capture-fullscreen`: TidyShot starts, then posts the refusal; nothing is captured.
  (suite: URLCommandHandlerTests.urlsWaitUntilTheAppHasStartedThenRunInOrder)
- [ ] While a selection is open (⌃⇧4, not released), while a self-timer counts, and during a scrolling session before and after Start: `t capture-fullscreen`, `t capture-area` and `t capture-scrolling` do nothing and post nothing (the log reads `dropped, a capture is running`); the scrolling session neither starts nor finishes. `t restore-recently-closed` still restores a card.
  (suite, in part:
  CoordinatorCaptureSourceTests.aHeldSelectionOpensOneWindowAndDropsEveryOtherURLCaptureCommandWithoutReadingOrPosting,
  URLCommandHandlerTests.captureCommandsAreDroppedWhileCapturesAreRefused, .theLogSaysWhyACaptureCommandWasDropped; by
  hand: while a self-timer counts (`STAGE`), and during a scrolling session before and after Start (`SCROLL`))
- [ ] `for i in 1 2 3; do t capture-window; done`: one window selection opens; the other two are dropped. (suite:
  CoordinatorCaptureSourceTests.aHeldSelectionOpensOneWindowAndDropsEveryOtherURLCaptureCommandWithoutReadingOrPosting,
  URLCommandHandlerTests.captureCommandsAreDroppedWhileCapturesAreRefused)
- [ ] Several URLs waiting for a cold launch: quit TidyShot, then `open 'tidyshot://capture-window' 'tidyshot://capture-area' 'tidyshot://restore-recently-closed'`. TidyShot starts, one window selection opens (only the first capture command runs; the log reads `a queued capture command ran first` for the second), and the restore still happens. With the silent toggle off, a refused `capture-fullscreen` ahead of a `capture-window` does not stop the window selection from opening.
  (suite: URLCommandHandlerTests.aGateRefusedCaptureDoesNotCountAsTheFirstQueuedOne,
  .onlyTheFirstQueuedCaptureCommandRuns)

## VoiceOver
Turn VoiceOver on (⌘F5).
- [ ] In All-in-One, VO-arrow through the toolbar: the W and H fields, the lock and each button are read by name (their help text). Return and Escape still capture and cancel.
- [ ] A card's Pin button is read as `Pin to screen`. A pin's context-menu actions are listed in the VoiceOver actions menu.
- [ ] Turn VoiceOver off. Everything above behaves as before.

## Regression
- [ ] ⌃⇧2 to ⌃⇧6, the overlay, Save As…, drag-out, Restore Closed Overlay and Recent Captures behave as in the Phase 6a checklist's Regression section.
- [ ] Escape outside a capture, a countdown and a scrolling session reaches the frontmost app (Safari's find bar closes with Escape).
- [ ] Upload-only mode end to end through a URL command: `t 'capture-area?action=upload'`, select, URL on the clipboard, drag the card, pin it, Delete: the pin closes and nothing is left in `pending` or `Drag`.
- [ ] Quit TidyShot with pins, cards and a countdown showing: everything goes and nothing is left on screen.

## Probe results
Write these under probe 4 in `docs/superpowers/research/phase-6-research.md` and into the "Phase 6b (built)" paragraph of spec 2.9 (which lists them as still to be written down):
- Scheme ownership: the paths registered before cleaning, the one that owns `tidyshot:` after, and which bundle the cold launch started.
- The sender table above, and whether Chrome offered "Always allow".
- Anything that failed above, and timings and observations the items ask for (the 65,536 px pin's memory, All-in-One's Return and Escape with the fields).
