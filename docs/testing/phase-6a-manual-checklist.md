# Phase 6a manual test checklist

Run after any change to `TidyShot/Overlay/`, the freeze path in `TidyShot/Selection/`, the capture
options in `TidyShot/Capture/`, `DragFileStore`, Save As… from the card, Capture Previous Area, or
the capture functions of `AppCoordinator`. Automated tests cover the capture options and the cursor
rule, the stack layout, the display choice, the closed-overlay list, the drag file names and the
drag file store, the freeze crop, the previous-area decision, the new settings keys and the
shortcuts; everything here needs real windows, real receivers, real displays and eyes. The 4a and 4b
checklists still cover the editor and the Phase 5 checklist the scrolling session; run them too
after a change to those paths.

Setup: a fresh **Release** build (`xcodebuild -project TidyShot.xcodeproj -scheme TidyShot
-configuration Release -derivedDataPath .build-rel build`), Screen Recording granted, save folder
set to Desktop, a working destination saved in Settings > Upload, "Show notification" on in
Settings > General, "Show Quick Access overlay after capture" on in Settings > Overlay, Network
Link Conditioner installed (profiles `100% Loss` and a slow one), and a second display if you have
one, ideally at a different scale. Capture only made-up data: a capture may be uploaded and the link
may be shared. Note how the build is signed (`Config/Local.xcconfig`).

Make the test pages once.
```bash
mkdir -p ~/Desktop/p6 && cd ~/Desktop/p6
cat > freeze.html <<'HTML'
<!doctype html><meta charset="utf-8"><title>Freeze test</title>
<style>body{font:28px -apple-system,sans-serif;margin:40px}#t{font:700 120px ui-monospace,monospace}#b{width:120px;height:120px;background:#e11;animation:r 2s linear infinite}@keyframes r{to{transform:rotate(360deg)}}</style>
<div id="t">0</div><div id="b"></div>
<p><span title="Tooltip text for the freeze check">Hover here for a tooltip</span></p>
<script>setInterval(function(){document.getElementById('t').textContent=(performance.now()/1000).toFixed(2)},16)</script>
HTML
cat > drop.html <<'HTML'
<!doctype html><meta charset="utf-8"><title>Drop test</title>
<style>body{font:18px -apple-system,sans-serif;margin:40px}#z{border:3px dashed #888;padding:60px;border-radius:12px;text-align:center}#z.over{background:#cde}</style>
<div id="z">Drop a file here</div><p><input type="file" id="f"></p><pre id="o"></pre>
<script>
var z=document.getElementById('z'),o=document.getElementById('o');
function show(files){o.textContent=Array.from(files).map(function(f){return f.name+'  '+f.type+'  '+f.size+' bytes'}).join('\n')||'(no files)'}
['dragenter','dragover'].forEach(function(n){z.addEventListener(n,function(e){e.preventDefault();z.classList.add('over')})});
['dragleave','drop'].forEach(function(n){z.addEventListener(n,function(e){e.preventDefault();z.classList.remove('over')})});
z.addEventListener('drop',function(e){show(e.dataTransfer.files)});
document.getElementById('f').addEventListener('change',function(e){show(e.target.files)});
</script>
HTML
cat > alpha.swift <<'SWIFT'
import AppKit
guard CommandLine.arguments.count > 1, let image = NSImage(contentsOfFile: CommandLine.arguments[1]),
      let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { fatalError("usage: alpha file.png") }
let rep = NSBitmapImageRep(cgImage: cg)
func alpha(_ x: Int, _ y: Int) -> Int { Int(((rep.colorAt(x: x, y: y)?.alphaComponent ?? 0) * 255).rounded()) }
let w = rep.pixelsWide, h = rep.pixelsHigh
print("size \(w) x \(h)")
print("corners", alpha(0, 0), alpha(w - 1, 0), alpha(0, h - 1), alpha(w - 1, h - 1), " middle", alpha(w / 2, h / 2))
print("alpha up the middle column from the bottom row, every 8 px:",
      stride(from: h - 1, through: max(0, h - 160), by: -8).map { alpha(w / 2, $0) })
SWIFT
swiftc -O alpha.swift -o alpha
```
`freeze.html` shows a counter in seconds that ticks every 16 ms, a spinning square and a tooltip.
`drop.html` lists the name, type and size of every file the browser receives; open either with
`open -a Safari ~/Desktop/p6/drop.html` (Chrome the same way). `alpha file.png` prints the PNG's
size and the alpha at the corners, the middle and up the middle column.

Receivers for the drag-out section, all signed in with made-up content: Finder, Slack (a private
channel or a conversation with yourself), Chrome and Safari (Gmail compose windows and `drop.html`),
Mail (a compose window addressed to yourself, never sent), Messages (a conversation with yourself)
and Notes. Quit other apps that take drops.

`history.json` is in `~/Library/Containers/io.tky.tidyshot/Data/Library/Application Support/TidyShot/`;
`thumbnails` and `pending` are next to it. The drag copies are in
`~/Library/Containers/io.tky.tidyshot/Data/tmp/Drag/<record id>/`. Settings are read with
`defaults read io.tky.tidyshot <key>`.

## Settings and strings
- [ ] Settings > Capture lists, in this order, `Freeze screen while selecting` with the caption `Area selections show a still image of the screen and the capture is cut from it, so menus, tooltips and video stay as they were when you pressed the shortcut.`, `Show cursor in screenshots` with the caption `Fullscreen, previous-area, self-timer and URL captures show the pointer where it is. Area captures show it only with Freeze screen on. TidyShot never captures its own crosshair.`, and `Include window shadow` with the caption `Window captures keep transparent rounded corners either way.` The first and third are off on a fresh install. (Reset them without touching the save folder or the destination: `for k in freezeScreen windowShadow showsCursor overlayDisplay overlayMaxCards overlayCloseAfterDrag lastAreaRect; do defaults delete io.tky.tidyshot $k; done`, then relaunch.)
- [ ] Settings > Overlay lists the existing toggle, Position and Auto-close, then `Show on` (a picker: `Display of the capture` selected, `Display with the pointer`, `Main display`), `Show up to 5 overlays` (a stepper from 1 to 8; at 1 it reads `Show up to 1 overlay`), `Close after dragging out` (on), then history retention. With the overlay toggle off the new rows that depend on it are disabled like Position.
- [ ] Settings > Shortcuts lists `Capture area:`, `Capture window:`, `Capture fullscreen:`, `Capture scrolling:`, `All-in-One:` (⌃⇧1), `Capture previous area:` (⌃⇧6), `Self-timer:` (empty), `Capture text:` (⌃⇧7), `Record screen:` (⌃⇧8), `Record fullscreen:` (empty) and `Restore closed overlay:` (empty). Change `Capture previous area:` to another combination, confirm the new keys work and ⌃⇧6 does not, then reset it. Set a combination for `Restore closed overlay:` for the restore section and clear it at the end.
- [ ] The menu bar menu lists `All-in-One  ⌃⇧1`, `Capture Area  ⌃⇧4`, `Capture Window  ⌃⇧2`, `Capture Fullscreen  ⌃⇧3`, `Capture Scrolling  ⌃⇧5`, `Capture Previous Area  ⌃⇧6`, `Self-Timer`, `Capture Text  ⌃⇧7`, `Record Screen  ⌃⇧8`, `Record Fullscreen`; a separator; Recent Captures (with a chevron), `Restore Closed Overlay`, Retry Failed Uploads (only with a failed upload), Reveal Last Capture, `Hide Desktop Icons`; a separator; `Unlock Pinned Screenshots` and `Close Pinned Screenshots` when they apply, Settings… `⌘,`, Quit TidyShot `⌘Q`. The capture items, Record items included, are disabled while a capture, a countdown, a scrolling session or a microphone or camera prompt runs; Restore Closed Overlay and Hide Desktop Icons are not.
- [ ] Settings persist: change each of the five settings (`Show on` to `Main display`, `Show up to` 3, `Close after dragging out` off, freeze on, shadow on), quit and reopen, and check the panes still show them. `defaults read io.tky.tidyshot <key>` reads `main`, `3`, `0`, `1`, `1` for `overlayDisplay`, `overlayMaxCards`, `overlayCloseAfterDrag`, `freezeScreen` and `windowShadow` (one key per call; a key never changed does not exist yet, which is the default). Set them back afterwards.
  (suite: AppSettingsTests.overlayStackSettingsDefaultAndPersist, .overlayCloseAfterDragDefaultsOnAndPersists,
  .freezeScreenDefaultsOffAndPersists, .windowShadowDefaultsOffAndPersists)

## The cursor (bug fix)
Before this phase, with `Show cursor in screenshots` on, an area or window capture contained TidyShot's own crosshair at the mouse-up point. Test with it on, then off, with `Freeze screen while selecting` off.
- [ ] On: ⌃⇧4 over a plain region, drag from the top left to the bottom right, release. Zoom into the bottom-right corner of the saved image: no crosshair and no arrow. Repeat dragging to the other three corners. The saved image has no pointer at all.
- [ ] On: ⌃⇧2, click a window: no crosshair and no arrow in the image, with the pointer inside the window.
- [ ] On: ⌃⇧3 with the pointer resting on a recognisable spot (a text field): the arrow or I-beam is in the image at that spot. Off: it is not.
- [ ] On: ⌃⇧6 (after an area capture) with the pointer inside the stored area: the pointer is in the image. Off: it is not. The selection overlay's dimming, loupe and size label are never in any image.

## Cards stay out of captures (bug fix)
Take three captures so three cards stand in the corner, and repeat at each of the four corners (Settings > Overlay > Position) and on the second display.
- [ ] ⌃⇧3 (fullscreen) with three cards showing: no card is in the image. Where they stood, the windows or desktop under them show.
- [ ] ⌃⇧4 over the stack: select an area that covers the cards. The image has no card in it, and the loupe shows the screen without the cards. The cards come back, unmoved, afterwards.
- [ ] ⌃⇧2 on a window that lies partly behind a card: the image is the window alone.
- [ ] ⌃⇧6 with cards over the stored area: no card in the image.
- [ ] Press ⌃⇧3 twice a second apart: the second image has no card even though the first capture's card was still sliding in.
- [ ] With `Freeze screen while selecting` on and three cards showing, press ⌃⇧4: the frozen picture under the dimming shows what lies under the cards, with no card-shaped ghost. Escape: the cards are still there.
- [ ] An open editor window, the menu bar and the Dock are still in a fullscreen capture (only the cards are left out).
- [ ] A scrolling capture over an area with a card on it has no card in the image (the Phase 5 item still holds).
- [ ] ⌃⇧3 with no card showing feels as quick as before this phase.

## Window shadow (probe 1)
The build uses the system shadow (`ignoreShadows = false`, the size from the filter's `contentRect` times `pointPixelScale`). The probe checks that this holds; if the probe or an item below fails, the synthetic shadow written at the end of Task 1 is built as a follow-up.
- [ ] The probe: open a Finder window and a Slack window, then, in a terminal with the Screen Recording grant, from the repository: `mkdir -p .build && swiftc -parse-as-library -O probes/window-shadow/probe.swift -o .build/window-shadow-probe && .build/window-shadow-probe com.apple.finder com.tinyspeck.slackmacgap`. For each app: a header line and four capture lines. Open the `shadow-filter` and `noshadow-default` PNGs it names. Pass, for both windows: the shadowed image is larger than frame x scale on every side (about 20 pt or more at the bottom); its corner alphas are 0 and the last row's alpha is 0 or small while the alpha 20 pt above it is above 0; the window's title bar and traffic lights are the same pixel size in both PNGs. Write the printed lines, pass or fail, `pointPixelScale` and the macOS build under probe 1 in `docs/superpowers/research/phase-6-research.md`.
- [ ] Off (default): ⌃⇧2 on a Finder window and a Slack window. `alpha` reports corners 0 and a middle of 255; the pixel size equals the window's size in points times the display scale, as before this phase; the image has transparent rounded corners and no shadow.
- [ ] On: the same two windows. The image is larger than the window by the shadow, the window's text is at 1:1 (no softness), `alpha` reports corners 0 and a middle of 255, and the alpha up the bottom of the middle column runs from 0 at the last row up through partial values to 255 inside the window. Write down both sizes and the first lines of `alpha`'s output.
- [ ] Take a system shot of the same window (⌘⇧4, Space, click the window; the system keeps the shadow) and compare: window content, the shadow's extent and softness, and its offset agree. Write down the difference.
- [ ] On a window at the edge of the screen, a window partly off screen, a window on the second display at the other scale, and in dark mode and light mode: the shadow is whole, nothing is clipped at the image edge, and the scale is right on each display.
- [ ] The overlay's thumbnail, Annotate (the editor shows the transparent surround), Save from the editor, pasting from the clipboard into Notes over a dark background, and an upload (open the uploaded PNG) keep the alpha.
- [ ] Switching the setting takes effect on the next capture without a restart. Area, fullscreen and scrolling captures are unaffected by it.

## Freeze screen (probe 3)
Open `freeze.html` in Safari and play a video in another window.
- [ ] Off: ⌃⇧4 behaves as before; the counter keeps running under the dimming.
- [ ] On: press ⌃⇧4. The counter, the spinning square and the video stop at once (the screen is a still picture), the crosshair and loupe work, and the readout shows the right size. Wait 3 seconds, then drag over the counter and release. The saved image shows the counter at the value it had when you pressed the shortcut, not 3 seconds later.
- [ ] A menu: open Safari's File menu in the menu bar and press ⌃⇧4. With freeze on, the open menu is in the frozen picture and in a capture of it; with freeze off it is not. The same with a tooltip (hold the pointer over the tooltip text, press the shortcut with the tooltip showing).
- [ ] Cursor: with `Show cursor in screenshots` on, the pointer is in the frozen picture where it was when you pressed the shortcut and stays there while the crosshair moves; a capture that includes that spot contains it, one that does not has none. With it off, no pointer is in the picture or the capture. The crosshair is never in a capture.
- [ ] Edges: with freeze on, drag to the very right and bottom edges of the display: the file has the size the label read, with no off-by-one and no failure notification.
- [ ] Same pixels: close every window that changes (the counter page, video). Capture the same rectangle twice with the pointer outside it, once with freeze on and once off, `Show cursor` off: `sips -s format bmp a.png --out a.bmp && sips -s format bmp b.png --out b.bmp && cmp a.bmp b.bmp && echo SAME` prints `SAME`, and both have the same pixel size. Repeat with a rectangle at odd point positions on a Retina display.
- [ ] Two displays at different scales: pressing ⌃⇧4 freezes both at once. Select on the second display (and on one with a negative origin, if the arrangement has one): the crop is at that display's scale, correct in size and position, with the same checks as above. A drag that crosses displays clips to the display under its centre.
- [ ] Drawing: dragging a selection on the largest display tracks the mouse without lag, frozen as live. If it lags, write it down: the layer-backed backdrop of Task 2, Step 6 is then a follow-up.
- [ ] A frozen capture goes through upload-only mode, the card, Annotate and Recent Captures like any area capture.
- [ ] Window mode (⌃⇧2) and Capture Scrolling (⌃⇧5) show no frozen picture; the window highlight follows live content. Capture Previous Area has no selection, so freeze does not apply.
- [ ] Escape and a click without a drag leave nothing frozen on screen afterwards, and the next capture is live again.
- [ ] Latency: film the screen and keyboard with a phone in slow motion (240 fps), press ⌃⇧4 ten times with freeze off and ten with it on, and count the frames from the key going down to the first frame of the dimmed overlay. Write down the median for one display and, with a second display, for two, here and under probe 3 in `docs/superpowers/research/phase-6-research.md`. The snapshots are taken one display after the other, so two displays cost two round trips. The spec's limit is about 150 ms at two displays; above it, report it (the snapshots would move to a stream started at the hotkey, or freeze would become area-only on the pointer's display first).

## The stack
Settings > Overlay > Show up to 5 overlays, auto-close 60 s so the cards stay while you look.
- [ ] Position top right: take five captures. The newest card is at the corner, each older one is one card height plus 10 pt below it, and the cards slide into place with an animation. A sixth capture pushes the oldest off; it is gone from the screen. Repeat for top left, bottom left and bottom right (older cards go up from a bottom corner).
- [ ] `Show up to` 1: a new capture replaces the card, as before this phase. 8: eight cards stand, and on a small or scaled-down display the stack stops at what fits between the menu bar and the Dock (set the display to a low resolution to see it).
- [ ] Auto-close 5 s: every card closes by its own timer, the oldest first. Holding the pointer over one card pauses only that card's countdown; it restarts when the pointer leaves. Auto-close "never" keeps all cards.
- [ ] A card that slides away from a still pointer closes. Auto-close 10 s, take two captures, rest the pointer on the older card (the countdown waits), take a third capture so the older card slides down from under the pointer, and keep the pointer still: when its countdown next runs out the card closes, although no hover-exit event came. The card that now stands under the still pointer is the one that waits.
- [ ] Lowering `Show up to N overlays` takes effect at the next layout, not when the stepper moves: with five cards showing, set it to 2 and look: all five stay. Then take a capture, or close any card: the stack is cut to the newest two cards at that moment, and the cards that go close as pushed out and can be restored. Raising the limit again brings no card back by itself.
- [ ] While the pointer is over a card, let another card close: the cards under the pointer do not move out from under it until the pointer leaves, then the stack settles. Close the newest card with its badge and keep the pointer still: the others slide up only after the pointer leaves the stack.
- [ ] Delete a card in the middle of the stack and Annotate another: each closes and the gap closes. (suite, in part:
  CoordinatorEditorTests.annotateFromACardOrRecentCapturesLeavesNothingToRestore; by hand: the gap in the stack closing
  (`QASTACK`))
- [ ] Upload-only mode, a capture uploading in one card and an older card settled: the uploading card stays until its URL is copied, then counts down; the settled one closes on its own timer.
- [ ] A card cannot be moved: pressing on its background and dragging does not move the panel (it starts a drag-out, see below).
- [ ] The stack is on every Space and over a full-screen app: take a capture in a full-screen Safari window and the stack shows there.
- [ ] Dock and menu bar: with the Dock at the bottom, at the side, hidden and shown, the stack stays inside the visible frame, 16 pt from the corner's edges.

## Which display (needs a second display)
- [ ] `Display of the capture` (default): ⌃⇧6 on an area stored on the second display, with the pointer on the first: the card appears on the second display. A fullscreen capture (⌃⇧3) puts it on the display under the pointer, which is the display captured. A window capture puts it on the display under the window's centre (drag a window so its centre is on the second display, with most of it visible on the first). A scrolling capture puts it on the area's display.
- [ ] `Display with the pointer`: the same ⌃⇧6 puts the card on the first display, where the pointer is. `Main display`: the card is on the main display whatever the capture or the pointer.
- [ ] The whole stack lives on one screen: with three cards on the first display, a capture shown on the second moves all four there, with an animation. Cards never split across displays.
- [ ] Unplug (or put to sleep) the display that holds the stack: the stack moves to the main display and nothing crashes. Plug it in again, change the resolution and the arrangement in System Settings > Displays with a stack showing: the stack stays on screen in its corner.
- [ ] Cards are 340 by 104 points on a 1x and on a 2x display.

## The card
- [ ] Hover a card: a round close badge (an `xmark` on a material circle, help `Close`) appears at its top-left corner and is gone when the pointer leaves. The right column holds Annotate (`pencil.tip.crop.circle`, help `Annotate`) and Delete (a trash can; help `Delete this capture`, or `Cancel the upload and delete this capture` while uploading) with Pin (`pin`, help `Pin to screen`) between Annotate and Delete.
- [ ] The status column's buttons: `Copy URL` and `Save As…` once the upload has finished; `Retry` and `Save As…` after a failure (Wi-Fi off, then a capture); `Save As…` alone while the upload runs and after a plain "Save and copy image" save.
- [ ] After a failure the status line shows `Upload failed` and the message on one line, cut short if it is long. Point at the card (the status text, the margin, the right column's gap; not a button, and not the thumbnail of a card with a save-folder file, whose tooltip is `Reveal in Finder`) and wait: the tooltip shows the full message. It is the card's tooltip, not the text's. A card that has not failed shows no tooltip there.
- [ ] With another app (Safari) frontmost, right-click a card: the menu appears although the card's panel is non-activating. It lists `Copy URL` (greyed while uploading and without a link), `Copy Image`, `Save As…`, `Annotate`, `Pin to Screen`, `Reveal in Finder` (only when the capture has a file in the save folder), a separator, `Close`, `Delete…`. Each item does what its name says; `Delete…` brings the confirmation alert to the front, Cancel leaves the card, and OK deletes everywhere, as the trash button does.
- [ ] Right-click and Control-click open the card's context menu wherever you press: the thumbnail, the status text, the empty margin, the gap between the Annotate and Delete buttons, and the spot under the close badge (point at the card first so the badge shows). Both open the same menu, with another app frontmost, and neither starts a drag, closes the card or reveals a file (Control-click on the thumbnail must not reveal). If either fails to open the menu on some spot, write down where: the fix is a `hitTest(_:)` override in `QuickAccessCardDragSource` (the `QuickAccessCardDragView` in `TidyShot/Overlay/QuickAccessCardDragSource.swift`) that lets right-clicks and Control-clicks through to the SwiftUI context menu. It is a follow-up, not built in 6a. The `NSHostingView` menu fallback of Task 4 is not built either.
- [ ] A click on the thumbnail reveals a save-folder file in Finder; on an upload-only card with no file it does nothing and nothing breaks. A click on a button does not start a drag.
- [ ] Copy Image, from the context menu, with each kind of capture: a saved file; an uploaded capture that kept its file; an upload-only capture whose file is gone (a signed download runs; `Copying image…` is posted). Preview > File > New from Clipboard shows the same image, with the same pixel size as the file.
  (suite: CoordinatorRecordActionsTests.copyImageReadsTheFileOrDownloadsTheObject)
- [ ] Annotate from a card opens the editor and closes the card (not restorable, see below). (suite:
  CoordinatorEditorTests.annotateFromACardOrRecentCapturesLeavesNothingToRestore,
  ClosedOverlaysTests.onlyUserAutoPushedAndDraggedClosesAreRestorable)

## Close and restore
Bind `Restore closed overlay:` to a combination for this section.
- [ ] Close a card with the badge, with the context menu `Close`, by auto-close, by pushing it out with a sixth capture, and by dragging it out. Each time `Restore Closed Overlay` in the menu is enabled and the shortcut brings back that card at the corner, with the record's current state (a link that arrived since, a failed upload) and its thumbnail, and with the normal auto-close. With a shortcut recorded, the menu item reads `Restore Closed Overlay  <shortcut>`.
- [ ] With the stack on the second display, restore: the card joins that stack. With no card showing, restore puts the card on the pointer's display (`Display of the capture` and `Display with the pointer`) or the main display (`Main display`).
- [ ] Delete a capture from its card, and open the editor from another card: neither can be restored. When only those were closed, `Restore Closed Overlay` is disabled. A card whose delete is under way (the confirmation accepted, an upload being cancelled and the storage `DELETE` still running; Network Link Conditioner on `100% Loss` slows it) is not restorable in that window either: the menu item stays disabled and the shortcut does nothing. Open the editor from Recent Captures on a capture whose card is already closed: its card is no longer restorable.
  (suite: CoordinatorEditorTests.annotateFromACardOrRecentCapturesLeavesNothingToRestore,
  CoordinatorOverlayTests.aCardWhoseDeleteIsUnderWayIsNotRestorable)
- [ ] Close four cards one after the other and restore four times: they come back newest-closed first. A fifth restore does nothing and the menu item is disabled.
  (suite, in part: ClosedOverlaysTests.repeatedRestoresWalkBack, .hasRestorableMatchesPop; the coordinator's
  `restoreClosedOverlay` showing the card and the menu item's enabled state stay by hand, behind the screen seam)
- [ ] Restore walks back through the closed list even when the stack is full. Set `Show up to` 2 and take four captures A, B, C, D: C and D show, A and B are closed (pushed out). Restore: B comes back and C, the oldest card, closes to make room. Restore again: A comes back, then the cards pushed out by the restores follow (C, then D), and a card on screen is never the one restored. Each restore adds one card at the corner and, at a full stack, closes one at the far end, which can be restored later.
- [ ] The list holds ten: set `Show up to` 1 and take twelve captures (each closes the one before as pushed out), so the first and second are closed but only the ten newest closed stay on the list. Restore ten times: ten different cards come back, newest closed first, and the first capture's card is not among them. (The restores keep going round the cards they push out; that is the walk-back above, not a bug.)
- [ ] A card showing is not restored a second time: with the newest closed record's card already on screen, restore skips it and brings back the next one.
  (suite, in part: ClosedOverlaysTests.popSkipsDeletedAndShownIds; the coordinator passing the shown cards to it, and
  the restore itself, stay by hand)
- [ ] Delete a closed card's capture from Recent Captures: restore skips it. (suite, in part:
  ClosedOverlaysTests.popSkipsDeletedAndShownIds; the coordinator's record check and the restore itself stay by hand)
- [ ] A restored card's Annotate opens the editor from the file or, for an uploaded upload-only capture, from the bucket (the same as the Annotate button in Recent Captures).
  (suite, in part: CoordinatorEditorTests.aRestoredCardsAnnotateOpensFromTheFileOrTheBucket,
  CoordinatorDragOutTests.aRestoredUploadOnlyCardsQuietDownloadIsNamedForItsKey; by hand: the restore itself, which
  reads the screens (`SCREENS`); the test opens a showing card with no retained image, as a restored one is, and for the
  uploaded upload-only capture before and after the restore's quiet download)
- [ ] Quit and reopen: the list is empty and the menu item is disabled. Recent Captures still holds everything. (suite:
  CoordinatorOverlayTests.aRelaunchForgetsClosedCardsButKeepsTheirRecords)

## Save As… and Copy Image from the card
Keep another app (Safari) frontmost while you click the card.
- [ ] Click `Save As…` on a card of a capture that has a file in the save folder. TidyShot comes forward with an ordinary save panel (a window, not attached to the card), PNG is the only type, and the name and folder are the capture's own file in the save folder. Open the editor on the same capture and press ⇧⌘S: the suggestion is the same.
- [ ] Save to the Desktop: `shasum -a 256` of the copy equals that of the original (no re-encode); `Saved` with the copy's name is posted (when notifications are on; nothing is posted when they are off, and the file is still written), and a click on it reveals the copy. Pick the original file instead and confirm Replace: the file is unchanged byte for byte.
- [ ] For an upload-only capture the suggestion is the file name template's name with the current counter (none is drawn), in the save folder when one is set, otherwise where the panel last was. While `Uploading…` shows, the copy equals the pending file (`pending/<id>.png`); after a failed upload (`Retry  Save As…`) it writes the pending file too.
- [ ] After the upload, on a card that showed through it: the panel opens, and the copy is written from the card's kept drag copy, with no `Downloading` notification; it equals `curl -s <url> | shasum -a 256`. On a restored upload-only card before its quiet download has landed (Network Link Conditioner on a slow profile): the panel opens first, then after Save `Saving a copy…` with `Downloading <key>` is posted while the download runs, then `Saved`. With Wi-Fi off the failure is posted as `Not saved` and nothing crashes.
- [ ] Save into a folder other than the save folder (Documents): it works under the sandbox. Cancel the panel: nothing is written and nothing is posted.
- [ ] Save As… changes nothing about the capture: the card, its link, Recent Captures, `history.json`, Reveal Last Capture and the clipboard are as before.
- [ ] Open the panel and wait for the card's auto-close to run out: the panel keeps working and saves the capture.
- [ ] Use Save As… from the button and from the context menu, from a restored card, and from a card in the middle of the stack: each saves that card's capture.
- [ ] After the panel closes, clicking back into Safari works as usual; a second card's buttons still work without activating TidyShot.
- [ ] Editor regression: Annotate a capture, draw an arrow, ⇧⌘S: the sheet suggests the same name as before, the edited copy is written, `Saved` appears, and with the capture's image still on the clipboard the clipboard now holds the edit.

## Drag-out (probe 2)
- [ ] During a drag, `ls -R ~/Library/Containers/io.tky.tidyshot/Data/tmp/Drag` shows `<record id>/<name>.png` and `shasum -a 256` of it equals the source file's. The original in the save folder is untouched and stays where it was after every drop below.
- [ ] A drag starts from the thumbnail, the status text, the link text and the empty margin of a card, shows the card's thumbnail as the drag image, and offers copy only (the green plus, never a move). A press on a button, the badge or the right column does not start a drag. A click without moving still works everywhere. Hold a drag over another app longer than the auto-close time: the card does not close under it.
- [ ] Names: an uploaded capture's file is named like the end of its URL (`aSIS7.png` for `.../aSIS7.png`), so it matches the link on the clipboard; with the key template `shots/{random:6}` it is the last part only. A capture that was never uploaded is named like its Save As… suggestion. The key's name is kept after a restore too: close an uploaded upload-only card, restore it, wait for the quiet download, press on the card and `ls` its `Drag/<record id>` folder: the one file carries the key name (`aSIS7.png`), as does the file the receiver shows, not a name left from an earlier copy.
  (suite: CoordinatorDragOutTests.aRestoredUploadOnlyCardsQuietDownloadIsNamedForItsKey,
  DragFileNameTests.uploadedKeyNamesTheFile, .nestedKeyGivesItsLastComponent,
  .withoutAKeyTheSaveAsSuggestionNamesTheFile)
- [ ] Receivers. Use "Upload and copy URL" and wait for the upload to finish, then drag the card onto each receiver. Fill in the table: accepted (yes/no), the name the receiver shows, whether the image arrives whole (same pixel size), and whether a prompt about data from another app appears.

  | Receiver | Accepted | Name shown | Whole | Prompt |
  |---|---|---|---|---|
  | Finder (Desktop and a folder window) | | | | |
  | Slack (message box, then send) | | | | |
  | Chrome (Gmail compose and `drop.html`) | | | | |
  | Safari (Gmail compose and `drop.html`) | | | | |
  | Mail (compose body and attachment area) | | | | |
  | Messages (the conversation with yourself) | | | | |
  | Notes (note body) | | | | |

  Finder copies the file, never moves it. Dropping on the Trash does not delete or move the original. Copy the table under probe 2 in `docs/superpowers/research/phase-6-research.md`. If any receiver refuses the file URL or shows the prompt, write down which: the file-promise fallback (Task 6, Step 9; a provider that also writes the file URL) is then built as a follow-up, not in 6a.
- [ ] Modes, with Finder and Slack: "Save and copy image" (drag at once); "Upload and copy URL" before the upload ends (Network Link Conditioner on a slow profile) and after; "Upload only, keep no local file" before the upload ends and after it (the URL is on the clipboard, the file in `pending` is gone). Each time the dropped file is the capture, whole.
- [ ] Upload only, after the upload: the card is still on screen, and dragging it still works, from a file in the `Drag` folder that took the place of the pending file. `history.json` shows the record as before (no `fileURL`), and Recent Captures shows no local file. Copy Image, Save As… and Annotate on that card need no download (no `Downloading` notification). 60 seconds after the card closes `ls ~/Library/Containers/io.tky.tidyshot/Data/tmp/Drag` no longer lists the record's folder (Slack may still read the file in those seconds).
  (suite, in part: CoordinatorEditorTests.anUploadedUploadOnlyCardsCopyImageAndAnnotateReadTheDragCopy,
  CoordinatorUploadTests.anUploadedUploadOnlyImageMovesToItsDragFolderOnlyWithACard; by hand: the card's Save As… panel
  (`SAVEAS`), and Slack reading the file)
- [ ] An edited capture's drag copy is replaced. Upload-only mode, wait for the upload (the card shows `URL copied` and a drag file is kept), then press Annotate, draw an arrow, and save the edit (⌘S, or ⌘U to upload it): the capture's `Drag/<record id>` folder is gone at once. Then, from the card or Recent Captures: Copy Image, Save As… and Annotate show the edited image (arrow included), never the one before the edit; a drag started after the edit (press on the card, which stages the edit again) drops the edited image. Do the same with "Save and copy image" and an edit saved over the file: the dragged file has the arrow too.
  (suite, in part: CoordinatorEditorSaveTests.saveOverTheFileRemovesTheDragCopyAndEveryReadGivesTheEdit,
  CoordinatorEditorUploadTests.uploadOfAnUploadOnlyCaptureRemovesItsDragCopyAndEveryReadGivesTheEdit; by hand: the
  card's Save As… panel (`SAVEAS`), and the drop; the line's "from the card" cannot happen after an Annotate, which
  closes the card for good, and in upload-only mode ⌘S is Save As…, so the tests read through Recent Captures and remove
  the drag copy with ⌘U there and ⌘S over a saved file)
- [ ] Start a drag during a slow upload, hold the card in the air until the upload finishes, then drop: the file still arrives whole.
- [ ] A restored card with no local file (upload-only, restored after closing): it starts a quiet download when it appears (no notification). Network Link Conditioner on a slow profile: dragging before the download ends does nothing and the card stays; after it ends, dragging works. With Wi-Fi off the restore still works and dragging does nothing. A restored card with a save-folder file drags at once.
- [ ] A save folder on an external disk, if one is at hand: drag a fresh capture; the drag starts once the copy is made, and the receiver gets the file whole.
- [ ] `Close after dragging out` on: a drop onto a receiver closes the card, which is restorable and drags again once restored. A drag cancelled with Escape, or released over nothing, leaves the card. Off: the card stays after a drop.
- [ ] Drag the same card to two receivers one after the other: both get the file. Drag a card from the middle of the stack: it is that card's capture.
- [ ] Delete the capture whose card was dragged from: its `Drag/<record id>` folder is gone at once. Put a stray folder in `Drag` (`mkdir -p ~/Library/Containers/io.tky.tidyshot/Data/tmp/Drag/stale && touch ~/Library/Containers/io.tky.tidyshot/Data/tmp/Drag/stale/x`), quit and reopen: the `Drag` folder is empty.
- [ ] Drag the 65,536 px capture of the Phase 5 checklist: the drag starts at once (a clone, not a copy) and Finder receives it whole.

## Capture Previous Area
- [ ] With no stored area (`defaults delete io.tky.tidyshot lastAreaRect`, then quit and reopen TidyShot) ⌃⇧6 posts `Capture an area first.` titled `No previous area`, and nothing is captured.
- [ ] Capture an area with ⌃⇧4, then press ⌃⇧6: no dimmed overlay appears, a second capture of the same region is saved, and both files have the same pixel size. A third press repeats it.
- [ ] The rect survives a relaunch. A window capture and a fullscreen capture do not change it. A Capture Scrolling area (at least 100 pt tall, window or drag) replaces it; a refused scrolling area (under 100 pt) does not.
- [ ] On a two-display setup: capture an area on the second display, press ⌃⇧6 (it captures there, at that display's scale), unplug the display and press ⌃⇧6: `The previous area is not on a connected display.` titled `No previous area`. Plug it in again: ⌃⇧6 works again, so the stored rect was not shrunk.
- [ ] A stored area that lies partly beyond a display's edge after a resolution change is clipped to the display and captured.
  (suite: PreviousAreaTests.aRectPartlyOffItsDisplayIsClippedToIt, .aRectBetweenTwoDisplaysGoesToTheOneHoldingItsCentre)
- [ ] An area that leaves less than 1 point on its display is reported as not on a connected display, not captured at zero size: with TidyShot quit, `defaults write io.tky.tidyshot lastAreaRect -data "$(printf '{"x":-0.4,"y":100,"width":1.2,"height":200}' | xxd -p | tr -d '\n')"` (a strip whose centre is on the main display's left edge, with 0.8 pt of it on the display; this needs the main display's left edge at x 0), reopen and press ⌃⇧6: `The previous area is not on a connected display.` titled `No previous area`, and no capture. Then `defaults delete io.tky.tidyshot lastAreaRect` again.
- [ ] The menu item is disabled while a capture or a scrolling session runs, and ⌃⇧6 does nothing then. (suite, in part:
  CoordinatorCaptureTests.aCaptureWhileTheLockIsHeldReturnsAtOnceAndPostsNothing,
  ShortcutsTests.aCaptureIsRefusedWhileAnotherRunsOrAPromptIsOpen; by hand: the menu item shown disabled)
- [ ] Freeze does not apply: with freeze on, ⌃⇧6 still captures live (put the counter page under the stored area and check the counter in the image is not frozen from earlier).

## VoiceOver
Turn VoiceOver on (⌘F5) with a card showing.
- [ ] VO-arrow through a card: the thumbnail, the status, `Copy URL`/`Retry`, `Save As…`, `Annotate` and `Delete` are each read by name. The close badge exists only while the pointer is over the card, so VoiceOver does not reach it as an element; `Close` is instead an action of the card itself (VO-Command-Space on the card, or the actions rotor) next to the context menu's actions. Write down what VoiceOver offers: if `Close` or the menu actions are missing, say so.
- [ ] Turn VoiceOver off. Everything above behaves as before.

## Regression
- [ ] Capture Area, Capture Window and Capture Fullscreen: normal saves, uploads and thumbnails; a window capture keeps its transparent corners; the overlay's Annotate and Delete work; Recent Captures rows, Retry Failed Uploads and Reveal Last Capture are as before.
- [ ] A scrolling capture (Phase 5): the panel, Start, Done and the result work; the card appears on the area's display and is not in the image.
- [ ] Upload-only mode, end to end: capture, URL on the clipboard, drag the card, Save As…, Annotate, Delete. No file is left in `pending` or `Drag` after Delete.
- [ ] Quit TidyShot with cards showing: the cards go and nothing is left on screen. Relaunch: no card, and the menu item `Restore Closed Overlay` is disabled.

## Probe results
Write these under the probes in `docs/superpowers/research/phase-6-research.md` and into the "Phase 6a (built)" paragraph of spec 2.9 (which lists them as still to be written down):
- Window shadow: the probe's lines, pass or fail; sizes; the comparison with the system shot.
- Drag-out receivers: the table above; any prompt; any refusal (which makes the file-promise fallback a follow-up).
- Freeze latency: the medians for off and on, one display and two.
- Timings and observations the items above ask for.
