# Phase 7b manual test checklist

Run after any change to `TidyShot/Text/`, `TidyShot/Desktop/`, Capture Text or `withCaptureLock` in
`AppCoordinator`, `TidyShot/URLScheme/`, `Notifier`, or the Capture and Shortcuts tabs. Automated
tests cover the text joining, the clipboard and notification decision, Vision on a generated image,
the wallpaper matcher, the cover reasons and plan, the URL parser, gate and routing for the four new
commands, and the new settings keys and shortcut; everything here needs real displays, real
wallpapers, Spaces, sleep and eyes. The Phase 6a and 6b checklists still cover freeze, the overlay,
All-in-One, the self-timer and the URL scheme; run them too after a change to those paths.

Setup: a fresh **Release** build (`xcodebuild -project TidyShot.xcodeproj -scheme TidyShot
-configuration Release -derivedDataPath .build-rel build`), Screen Recording granted, "Show
notification" and "Play sound" on in Settings > General, Allow URL commands on, a desktop with a few
icons and at least one widget (right-click the desktop > Edit Widgets), two Spaces with different
wallpapers, one of them a dynamic wallpaper, and a second display if you have one (ideally at a
different scale). Note how the build is signed (`Config/Local.xcconfig`).

Make the test page and a shell helper once.
```bash
mkdir -p ~/Desktop/p7b && cd ~/Desktop/p7b
cat > qr.swift <<'SWIFT'
import CoreImage
import CoreImage.CIFilterBuiltins
import ImageIO
import UniformTypeIdentifiers

let payloads = ["qr-url": "https://snap.tky.io/2BkqQ.png", "qr-text": "TidyShot test 42",
                "qr-js": "javascript:alert(1)"]
for (name, payload) in payloads {
    let filter = CIFilter.qrCodeGenerator()
    filter.message = Data(payload.utf8)
    let image = filter.outputImage!.transformed(by: CGAffineTransform(scaleX: 8, y: 8))
    let cgImage = CIContext().createCGImage(image, from: image.extent)!
    let file = URL(fileURLWithPath: "\(name).png") as CFURL
    let destination = CGImageDestinationCreateWithURL(file, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, cgImage, nil)
    CGImageDestinationFinalize(destination)
}
SWIFT
swift qr.swift
cat > text.html <<'HTML'
<!doctype html><meta charset="utf-8"><title>TidyShot text</title>
<style>body{font:18px -apple-system,sans-serif;margin:40px;max-width:1000px}
.cols{column-count:2;column-gap:80px}img{width:160px;image-rendering:pixelated;margin:0 40px 0 0}
section{margin:0 0 60px}</style>
<section id="paragraphs"><p>The first paragraph has café, naïve and Ünïcödé in it, a price of $1,284.50 and the order QX-993.
It runs over more than one line in the browser window.</p>
<p>The second paragraph is short.</p></section>
<section id="columns" class="cols"><p>Left column, first line. The left column keeps going for a few more words so it wraps.</p>
<p>Right column, first line. The right column keeps going for a few more words so it wraps.</p></section>
<section id="scripts"><p lang="ja">日本語の文字認識テストです。</p><p lang="ru">Проверка распознавания русского текста.</p></section>
<section id="caption"><img src="qr-url.png"><div>Scan me</div></section>
<section id="two"><img src="qr-url.png"><img src="qr-text.png"></section>
<section id="plain"><img src="qr-text.png"><img src="qr-js.png" style="margin-left:200px"></section>
<section id="empty" style="height:200px;background:#eee"></section>
HTML
t() { open "tidyshot://$1"; }   # in the shell you test from: t capture-text
```
`text.html` opens with `open -a Safari ~/Desktop/p7b/text.html`. `pbpaste` prints the clipboard.
Settings are read with `defaults read io.tky.tidyshot <key>`. The log is
`log show --last 5m --predicate 'process == "TidyShot"'`.

## Settings and strings
- [ ] Settings > Capture lists, after `Include window shadow` and its caption, `Hide desktop icons while capturing` (off) with the caption `Covers desktop icons and widgets with the desktop picture during area, window, fullscreen, previous-area, All-in-One and self-timer captures.`, then the `Self-timer` picker. (Fresh values: `for k in hideDesktopIconsWhileCapturing desktopIconsHidden; do defaults delete io.tky.tidyshot $k; done`, then relaunch.)
- [ ] Settings > Shortcuts lists `Capture text:` (⌃⇧7) after `Self-timer:` and before `Restore closed overlay:`.
- [ ] The menu bar menu reads `All-in-One  ⌃⇧1`, `Capture Area  ⌃⇧4`, `Capture Window  ⌃⇧2`, `Capture Fullscreen  ⌃⇧3`, `Capture Scrolling  ⌃⇧5`, `Capture Previous Area  ⌃⇧6`, `Self-Timer`, `Capture Text  ⌃⇧7`; a separator; Recent Captures, `Restore Closed Overlay`, Retry Failed Uploads (only after a failure), Reveal Last Capture, `Hide Desktop Icons`; a separator; the pin items when they apply, Settings…, Quit TidyShot. `Capture Text` is disabled while a capture, a countdown or a scrolling session runs; `Hide Desktop Icons` never is.
- [ ] Turn both on (the toggle, and the menu item), quit and reopen: `defaults read io.tky.tidyshot hideDesktopIconsWhileCapturing` and `desktopIconsHidden` read `1`, the toggle is on, the menu item has its checkmark and the desktop is covered again within a second of launch. Turn both off.

## Capture Text
Copy some text first, so you can tell when the clipboard changes.
- [ ] ⌃⇧7 opens Capture Area's overlay (crosshair, loupe). Select both paragraphs: `pbpaste` prints them, one line per line on screen, with `café`, `naïve`, `$1,284.50` and `QX-993` right. The shutter sound plays and `Text copied` shows the first line as its body. No file in the save folder, no card, no Recent Captures row, no upload, and the after-capture action plays no part (try it under `Upload only` and `Save and copy image`).
- [ ] Two columns: select both. The left column's lines come before the right column's; a line of one column is never joined to the same line of the other. Write down what came back if it is not that.
- [ ] Non-Latin script: select the Japanese and the Russian lines. Write down what came back (automatic language detection, no language setting).
- [ ] A QR code with a caption: select the code and `Scan me` together. The clipboard is exactly `https://snap.tky.io/2BkqQ.png` (no caption), the title is `QR code copied` and the body the link. Click the notification: the link opens in the default browser. Select `Scan me` alone: `Text copied`, the caption.
- [ ] Two QR codes: select both. The clipboard is the two payloads, one per line, in the order Vision gives them (write it down); the title is `2 codes copied`; clicking the notification opens nothing.
- [ ] A non-URL payload: select `TidyShot test 42`'s code alone: `QR code copied`, body `TidyShot test 42`, a click opens nothing. Select the `javascript:` code alone: `QR code copied`, body `javascript:alert(1)`, `javascript:alert(1)` on the clipboard, and a click opens nothing.
- [ ] An empty area (the grey box, or a plain part of the desktop): `No text found` with `TidyShot found no text or QR code in the selection.`, posted even with Show notification off; the clipboard is unchanged and no sound plays.
- [ ] Show notification off, Play sound off: a paragraph is copied with no notification and no sound.
- [ ] Freeze screen on: open Safari's History menu, press ⌃⇧7 and select the menu's items. The menu text is copied (the frozen picture is read). Freeze off: the same menu closes when the overlay opens.
- [ ] A click without a drag: press ⌃⇧7 and click a TextEdit window with a few lines in it, without dragging. The overlay closes and nothing is copied, as in Capture Area.
  (suite, in part: SelectionOutcomeTests.areaModeCancelsOnAClickOrATinyDrag; `captureText()` stopping before `copyText`
  on a cancelled selection is a code read, and the overlay closing stays by hand)
- [ ] ⌃⇧6 after a Capture Text captures the previous image area, not the text selection.
- [ ] URL command, no rect: `t capture-text` opens the selection with the silent toggle off; the result is the same as ⌃⇧7. `t 'capture-text?action=upload'` behaves the same (action is ignored).
  (suite: URLCommandHandlerTests.commandsThatWaitForTheUserRunWithSilentCapturesOff,
  .everyCommandReachesItsCaptureFunction, URLCommandTests.parametersACommandDoesNotTakeAreIgnored,
  .everyCaptureButCaptureTextTakesAnAction)
- [ ] URL command, with a rect: with the silent toggle off, `t 'capture-text?x=0&y=0&width=600&height=300'` posts `capture-text from <sender> captures without a selection. Allow it in Settings > General > URL commands.` and leaves the clipboard alone. With it on, the rect (bottom-left of the display under the pointer; put text there) is read at once, with no overlay and no pointer in the image. `&display=2` reads the second display.
- [ ] While a selection is open (⌃⇧4 held), `t capture-text` does nothing (`dropped, a capture is running` in the log).
  (suite, in part: URLCommandHandlerTests.captureCommandsAreDroppedWhileCapturesAreRefused,
  .theLogSaysWhyACaptureCommandWasDropped, ShortcutsTests.aRefusedCaptureNamesTheRecordingThenTheLockThenThePrompt; the
  `dropped, a capture is running` line goes to NSLog, which no test reads, so the log stays by hand)
- [ ] Cold first run: restart the Mac, start TidyShot, ⌃⇧7 a paragraph. Write down how long until `Text copied` (the probe saw 24 s). While it waits, ⌃⇧4 works: the capture lock is not held during recognition. A second ⌃⇧7 afterwards takes a fraction of a second.

## Hide desktop icons while capturing
Settings > Capture > `Hide desktop icons while capturing` on. Watch the desktop icons and the widget.
- [ ] Capture Area (⌃⇧4): the icons and widget disappear (the desktop picture is in their place) before the overlay appears, stay hidden while you select, and come back after the capture. The image shows the desktop picture where the icons were. Escape instead of selecting: they come back too.
- [ ] Capture Window (⌃⇧2): the same; clicking on the bare desktop selects no window (the covers are not windows the picker offers).
- [ ] Capture Fullscreen (⌃⇧3): the image has no icons and no widget; they reappear after.
- [ ] Capture Previous Area (⌃⇧6) over the icons: no icons in the image.
- [ ] All-in-One (⌃⇧1): covered for the whole run, through Capture, Window, Fullscreen and Timer (the countdown included). The Scrolling button uncovers the desktop before the scrolling session opens.
- [ ] Self-Timer: covered from the selection through the countdown to the capture. Escape during the countdown uncovers.
- [ ] URL commands that start these (`t 'capture-area?x=0&y=0&width=600&height=400'` with the silent toggle on, `t capture-window`, `t all-in-one`) cover too.
- [ ] Not covered: Capture Scrolling (⌃⇧5) and Capture Text (⌃⇧7) leave the icons showing.
- [ ] Freeze screen on, then off: with freeze on, the frozen picture already has no icons (the covers are up before the snapshot); with it off, the live capture has none.
- [ ] Two displays: both displays' icons and widgets are covered during a capture, each with its own picture, and both come back after.
- [ ] Widgets: every widget on the desktop is hidden while covered, including one at the top-left and one near the menu bar.
- [ ] Delay: write down roughly how long the covers take to appear after the shortcut (the design expects about 150 ms: a 100 ms capture and a 50 ms wait).
- [ ] The toggle off: no capture covers anything.

## Hide Desktop Icons until turned off
- [ ] Menu > `Hide Desktop Icons`: the icons and widgets disappear on every display and the item has a checkmark. Choose it again: they come back, no checkmark.
- [ ] With it on, take each capture kind: the covers stay after the capture ends. With `Hide desktop icons while capturing` also on, the end of a capture does not uncover the desktop.
  (suite, in part: DesktopCoverReasonsTests.theEndOfACaptureLeavesPersistent, .captureAndPersistentTogether;
  `DesktopCoverController.hide` acting on the reasons, and the covers staying after each capture kind, stay by hand)
- [ ] With it on, start a Self-Timer countdown with `Hide desktop icons while capturing` on, then `t show-desktop-icons` during the countdown: the covers stay until the capture is taken, then go.
  (suite, in part: DesktopCoverReasonsTests.persistentOffDuringACaptureKeepsTheCoversUntilTheCaptureEnds,
  URLCommandHandlerTests.captureCommandsAreDroppedWhileCapturesAreRefused; the controller acting on the reasons during a
  real countdown stays by hand)
- [ ] Space switch: switch to the Space with the other wallpaper. The cover follows (it is on every Space) and shows the new Space's picture within a moment (it may show the old one for about 100 ms). Switch back.
- [ ] Wallpaper change: change the wallpaper in System Settings. Write down when the cover shows the new picture. It is captured again on a Space switch, a display change, wake and every 10 minutes, not on the change itself, so switching Space and back shows the new one.
- [ ] Dynamic wallpaper: leave it on over a change of the picture (or 10 minutes); the cover keeps up.
- [ ] Sleep and wake: sleep the Mac (Apple menu > Sleep), wake it: the covers are still there with the right picture, and the icons do not show.
- [ ] Displays: plug in or unplug the second display, or change its resolution: each connected display is covered at its new frame, and an unplugged display's cover is gone.
- [ ] Relaunch: quit TidyShot: the icons come back at once. Open it: the desktop is covered again and the item has its checkmark.
- [ ] Full-screen apps and Mission Control: the cover does not show over a full-screen app's Space contents, does not appear as a window in Mission Control or ⌘-Tab, and windows dragged over it behave normally.

## Clicks on the covered desktop
With `Hide Desktop Icons` on.
- [ ] Click, double-click and drag where an icon is: nothing opens, moves or is selected. Right-click: no desktop menu. Click the bare picture: the desktop is not revealed (the macOS "click wallpaper to reveal desktop" does not happen) and TidyShot does not become the active app (the menu bar keeps the frontmost app's name).
- [ ] Clicking a window above the cover works as usual; dragging a file from Finder onto the covered desktop does not drop it there (write down what happens).

## URL commands
- [ ] `t hide-desktop-icons`: covered, the menu item checked. `t show-desktop-icons`: uncovered, unchecked. `t toggle-desktop-icons` twice: covered, then uncovered. `defaults read io.tky.tidyshot desktopIconsHidden` follows each.
- [ ] With the silent toggle off, all three run (they capture nothing). With Allow URL commands off, each posts `URL commands are off. Turn them on in Settings > General.` and changes nothing.
  (suite: URLCommandGateTests.theDesktopIconCommandsNeedOnlyURLCommandsOn,
  URLCommandHandlerTests.withURLCommandsOffEveryURLIsRefusedAlike, .commandsThatWaitForTheUserRunWithSilentCapturesOff)
- [ ] `t 'hide-desktop-icons?action=upload&x=1'`: parameters are ignored; it runs. (suite:
  URLCommandTests.theDesktopIconCommandsParseAndIgnoreParameters,
  URLCommandHandlerTests.everyCommandReachesItsCaptureFunction)
- [ ] While a selection is open (⌃⇧4 held), `t toggle-desktop-icons` still runs. (suite:
  URLCommandHandlerTests.captureCommandsAreDroppedWhileCapturesAreRefused)

## The failure notification
- [ ] Without Screen Recording: quit TidyShot, `tccutil reset ScreenCapture io.tky.tidyshot`, open TidyShot (the permission window shows), close the permission window, then choose `Hide Desktop Icons`: the permission window shows again, no `Desktop icons still showing` is posted, and the icons stay. Choose it off and on again: nothing more in this launch. Relaunch, turn on `Hide desktop icons while capturing` and press ⌃⇧3: the permission window shows, nothing is captured, and no `Desktop icons still showing` is posted. Grant Screen Recording again afterwards (and relaunch).
- [ ] The notification itself (`Desktop icons still showing` with `TidyShot could not read the desktop picture.`, once per launch) has no practical way to force with Screen Recording granted, because every display has a wallpaper window. It is checked by code reading: `DesktopCoverPlan` reports a display with no cover and no wallpaper, and the coordinator's `reportFailure` posts it when Screen Recording is granted. Write down any other way you used.

## Regression
- [ ] With both desktop-icon options off, ⌃⇧1 to ⌃⇧6, the self-timer, the overlay, pins and URL commands behave as in the Phase 6b checklist.
- [ ] Quit with covers showing: nothing is left on screen and the icons come back.

## Observations
Write these into the "Phase 7b (built)" notes of spec 2.10:
- The cold first-run time of Capture Text, and what the two columns and the non-Latin lines came back as.
- How long the covers take to appear, and when a wallpaper change reached the cover.
- How the failure notification was checked.
- Anything above that failed.
