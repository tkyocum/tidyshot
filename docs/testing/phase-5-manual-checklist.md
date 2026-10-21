# Phase 5 manual test checklist

Run after any change to `TidyShot/Scrolling/`, the Capture Scrolling entry points (the selection
overlay's scrolling mode, the shortcut, the menu item), `AppCoordinator.save(_:)`, `ThumbnailMaker`
or the post-event permission. Automated tests cover the overlap finder and the stitcher on synthetic
pages, every decision (settling, end detection, step plan, status lines, panel placement, selection
outcome), the engine's pixels through the PNG encoder, the session with a fake frame source, the
thumbnail crop and the new setting; everything here needs the real stream, real windows, real
apps, real scroll events, the real permission and eyes. The 4a and 4b checklists still cover the
overlay's buttons, Annotate, Save, Upload and caches; run them too after a change to those paths.

Setup: fresh build, Screen Recording granted, save folder set to Desktop, a working destination
saved in Settings > Upload, "Show notification" on in Settings > General, "Show Quick Access
overlay after capture" on in Settings > Overlay, Network Link Conditioner installed, and TidyShot
**not** in the Accessibility list of System Settings > Privacy & Security (remove it with the minus
button), so the first sections run without the post-event permission. Note how the build is signed
(`Config/Local.xcconfig`: ad-hoc or Apple Development); the permission section depends on it.
Capture only made-up data: a capture may be uploaded and the link may be shared.

Make the test page once. It has a sticky header, a fixed footer, a fixed spinner, 120 numbered
sections of distinct colour and text (about 21,000 pt tall), and two modes: `#lazy` appends 20
sections 400 ms after the end is reached, and `#jump` scrolls 1.6 screens on every wheel event, so
each auto-scroll step is too big.
```bash
mkdir -p ~/Desktop/p5 && cd ~/Desktop/p5
{
cat <<'HTML'
<!doctype html><meta charset="utf-8"><title>Long test page</title>
<style>
body{font:18px/1.5 -apple-system,sans-serif;margin:0;padding-bottom:60px}
header{position:sticky;top:0;z-index:2;background:#1d4ed8;color:#fff;padding:14px 24px;font-weight:600}
footer{position:fixed;bottom:0;left:0;right:0;z-index:2;background:#111;color:#fff;padding:12px 24px}
section{padding:20px 24px;border-bottom:1px solid #ccc}
section div{height:70px;margin-top:8px;border-radius:6px}
.spin{position:fixed;top:90px;right:60px;z-index:1;width:30px;height:30px;border:5px solid #999;border-top-color:#000;border-radius:50%;animation:s 1s linear infinite}
@keyframes s{to{transform:rotate(360deg)}}
</style>
<header>Long test page: sticky header</header>
<div class="spin"></div>
HTML
for i in $(seq 1 120); do
  printf '<section><b>Section %03d</b><br>Each section has its own number, colour and text, so no two screens look alike. Item %03d.<div style="background:hsl(%d,70%%,60%%)"></div></section>\n' $i $i $(( (i*37) % 360 ))
done
cat <<'HTML'
<footer>Footer: this site uses cookies (fixed)</footer>
<script>
if(location.hash==='#lazy'){var loaded=false;addEventListener('scroll',function(){if(!loaded&&innerHeight+scrollY>=document.body.scrollHeight-5){loaded=true;setTimeout(function(){for(var i=1;i<=20;i++){var s=document.createElement('section');s.innerHTML='<b>Late section '+i+'</b><br>Loaded after the page reached its end.<div style="background:hsl('+(i*17)+',70%,60%)"></div>';document.body.insertBefore(s,document.querySelector('footer'))}},400)}})}
if(location.hash==='#jump'){addEventListener('wheel',function(e){e.preventDefault();scrollBy(0,innerHeight*1.6)},{passive:false})}
</script>
HTML
} > long.html
grep -v 'class="spin"' long.html > long-still.html
```
`long-still.html` has no spinner, so it holds still for the pixel comparison. Open them with
`open -a Safari ~/Desktop/p5/long.html` (add `"file://$HOME/Desktop/p5/long.html#lazy"` for the other
modes). Also have ready:
- a Terminal window about 900 by 700 pt with `seq -f "line %05g  the quick brown fox jumps over the lazy dog" 1 3000` run in it (every row differs by its number);
- a chat with 300 or more messages: a private Slack channel or a conversation with yourself in Messages, with a header that stays put (never a real conversation);
- Settings > Overlay and Settings > General as in the 4b setup, and the Terminal's cursor blinking (the default);
- optional: a second display, ideally at a different scale, and Chrome.

`history.json` is in `~/Library/Containers/io.tky.tidyshot/Data/Library/Application Support/TidyShot/`;
thumbnails are in its `thumbnails` folder. Where an item says "compare with a one-shot", the one-shot is
a `⌃⇧4` capture of the same region made with the pointer outside it.

## Starting a capture
- [ ] The menu bar menu lists `Capture Scrolling  ⌃⇧5` after Capture Fullscreen. Settings > Shortcuts has a `Capture scrolling:` row with ⌃⇧5; change it to another combination, confirm the menu and the new keys work and ⌃⇧5 does not, then reset it. There is no recorder row for Escape.
- [ ] ⌃⇧5 opens the selection overlay with the crosshair, the loupe and the dimension readout of Capture Area, and hovering a window highlights it, as in Capture Window. Escape cancels the overlay and nothing else appears.
- [ ] Drag an area about 700 by 500 pt: the overlay closes and two things appear, a dashed outline just outside the area (white line, black halo, visible over both light and dark content) and a panel. Click a window instead (no drag): the window's whole frame becomes the area.
- [ ] Drag an area 400 pt wide and 60 pt tall: no session starts and a notification titled `Scrolling capture` says `Select an area at least 100 points tall.` The next ⌃⇧5 works. An area exactly 100 pt tall is accepted.
- [ ] A click on a window that is partly off the screen, or taller than the screen, takes the part on its display. Nothing crashes.
- [ ] While a session is open (panel on screen), the menu's Capture Area, Capture Window, Capture Fullscreen and Capture Scrolling items are disabled and ⌃⇧4, ⌃⇧2 and ⌃⇧3 do nothing; ⌃⇧5 acts as Start, then as Done. All of them work as before after Done or Cancel.

## The panel and the frame
- [ ] The panel is 240 pt wide and sits 12 pt to the right of the area. Make the area touch the right edge of the screen: the panel moves 12 pt to the left of it. Make the area fill the screen's width: the panel sits inside the area's bottom-right corner, 12 pt from its edges. In every case it stays on the screen of the area, and under the menu bar and the Dock.
- [ ] The panel shows, top to bottom: the preview, the size readout, the status line, the **Scroll automatically** checkbox and the buttons **Cancel** and **Start**. Before Start the status line reads `Click Start, then scroll down slowly.` (checkbox off or on without the grant: see the permission section for the checkbox).
- [ ] An area only 100 to 200 pt tall: the panel is still at least 220 pt tall (the controls need that much; it may be taller than the area), nothing in it is clipped, and it stays on the screen. With a tall area the panel grows with the preview and stops at 560 pt or the area's height, whichever is smaller; the preview keeps showing the newest rows.
- [ ] The panel is key and TidyShot stays the active app, so Return presses Start (then Done) and Escape cancels. Safari's window therefore looks inactive while the panel is up; that is expected. After Start the trackpad and the mouse wheel still scroll Safari under the pointer without a click first, and the capture follows.
- [ ] Neither the panel nor the dashed frame is in the stitched image, even when the panel sits inside the area (see the last item of the previous section) and when the Quick Access overlay of an earlier capture is on screen over the area. Take such a capture and look for them.
- [ ] The dashed frame never takes a click or a scroll: with the pointer over its outline, scrolling still moves the page below.
- [ ] The screen-recording indicator appears in the menu bar after Start and is gone after Done and after Cancel.

## Manual mode on a long web page (Safari)
Open `long-still.html` in Safari at the top, with the window about 1100 by 800 pt. Take a `⌃⇧4` one-shot of the page area (not the toolbar) first and keep it. Drag the same area for ⌃⇧5.
- [ ] Click Start, scroll down slowly with the trackpad (about a screen every two seconds), watch, and click Done at the end of the page. The panel's preview grows from the bottom, showing the newest rows; the readout counts up with comma separators (`2,200 × 7,340 px` style) and its digits do not jitter; the status line reads `Scroll down slowly. Click Done at the end.`
- [ ] The saved capture is one tall PNG of the whole page: sections 001 to 120 in order, none missing or repeated, no seams, no doubled rows at the joins. The sticky header is there once, at the top; the fixed footer is there once, at the end (if the area covers them).
- [ ] Pixel check against the one-shot: `sips -c <h> <w> --cropOffset 0 0 <stitched.png> --out /tmp/top.png`, using the one-shot's pixel height and width, then `sips -s format bmp /tmp/top.png --out /tmp/a.bmp && sips -s format bmp <one-shot.png> --out /tmp/b.bmp && cmp /tmp/a.bmp /tmp/b.bmp && echo SAME`. Expected `SAME`: the first screen of the stitched image equals a one-shot of the same region. `sips -g profile -g dpiWidth -g pixelWidth` reports the same profile and `dpiWidth` as the one-shot (144 on a 2x display, 72 on a 1x display).
- [ ] Scroll with the trackpad, a mouse wheel and the Space and Page Down keys (about a screen at a time): all work. Scroll up a little in the middle of the capture, then on down: the page is still contiguous and nothing is repeated. Also do it right at the start (scroll down a few lines, back up past where you began, then down again): the sticky header is still there once, with no gap or doubled rows under it, because rows are committed from where the output stops, not from the header's height.
- [ ] Click Start and Done at once without scrolling: a single-frame capture of the area, like an ordinary area capture. Pressing ⌃⇧5 again acts as Start, and then as Done.
- [ ] Open `long.html` (with the spinner) and capture it. The spinner does not break the match. Look at its trace: the spinner is fixed on the screen inside the band, so it appears once per screen of content, in whatever rotation it had. This is the documented behaviour for fixed overlays; write down what you see (how many, where) for the spec.
- [ ] The overlay scrollbar appears and moves while scrolling. The stitch is not thrown off by it; write down whether fragments of the scrollbar thumb show along the right edge of the result.
- [ ] Safari with the window as the pick: click the Safari window instead of dragging an area. The toolbar and tab bar are at the top of the result exactly once, the page follows, and the corners behind the window's rounded corners show what lay behind them (the desktop), not transparency. Pick the same window with another window overlapping part of it: the overlapping window is in the capture where it covers, which is expected (the capture is of the display).
- [ ] Repeat the capture in Chrome, if installed: same page, same result. Write down what Chrome does with the fixed spinner and footer compared with Safari.

## The too-fast line
- [ ] Safari at the top, Start, scroll a little, then press End (the whole page jumps far past the area's height): the status line becomes `Too fast. Scroll back up a little.` and the preview stops growing. Press Home, then scroll down slowly: the line clears at the first matched movement and the capture goes on. Done: the result is still contiguous; the content jumped over is missing only if you never scrolled back to it (it is not in the result then).
- [ ] A hard trackpad flick (a 3000 pt fling) does the same: the line shows while the page is too far from the last accepted screen and clears after you scroll back into overlap. A slow flick that you let coast never shows the line.
- [ ] Done while the line shows saves what was stitched before the loss, at the right size, with no half-written rows at the end.

## Manual mode on Terminal scrollback
Terminal with the `seq` output run, scrolled up to about line 1500.
- [ ] Drag the Terminal's text area, Start, scroll down slowly to the prompt, Done. The result shows consecutive numbered lines to the prompt. Check them with Live Text: open the PNG in Preview, ⌘A, ⌘C, then `pbpaste | grep -o 'line [0-9]\{5\}' | sed 's/line //' | awk 'NR>1 && $1!=p+1 {print "gap or repeat at " $1} {p=$1}'`. Expected: no output (every line appears once, in order). A few Live Text misreads are not failures; note them.
- [ ] The Terminal's blinking cursor at the prompt row does not confuse the match. The last rows of the result show the prompt once.
- [ ] Output in place: in a new Terminal window that is not yet full, select its text area, Start, hold still and run `for i in 1 2 3 4 5; do sleep 1; echo "output $i"; done` (type it before Start, press Return after). Each new line appears without the window scrolling: the status line stays `Scroll down slowly. Click Done at the end.` and never reads `Too fast. Scroll back up a little.`
- [ ] Click the Terminal window instead of dragging: the title bar and window edges stay at the top of the result once (a static header), the lines follow.
- [ ] A narrow scrolling column inside a wide area: drag a selection about 900 pt wide over the Terminal window plus empty desktop or a wide window, so the lines occupy only the left tenth of the area and the rest is static. Start, scroll down slowly through 500 lines, Done. The lines must still stitch in order (the `awk` check passes). The changing part is a small share of the area, but a stripe cell whose content appears at another row counts as a scroll, not as animation, so it must not read as still. Write down any run where the preview stops growing while you scroll.
- [ ] Run `yes "same line" | head -200` and capture a stretch of it taller than the area. Expected: the content is identical row after row, so TidyShot cannot place the screens: the too-fast line shows when you scroll there, and Done saves what came before. This is the documented limit (content with no distinctive rows); write down what happens. Where the content repeats with a period (for example `seq 1 3 | sed 's/^/x/'` looped a few hundred times), a candidate shift ties on votes and the finder prefers the smaller shift, then the forward one, so a scroll down is never read as a scroll up: write down whether the result repeats or skips a period.

## Manual mode in a chat window
The chat from the setup, scrolled so a few hundred messages lie below the view.
- [ ] Click the chat window as the pick (header, message list and composer in one frame), Start, scroll down slowly to the newest message, Done. The window header is at the top once and the composer at the bottom once; no message is repeated or missing; day separators and avatars line up across the joins.
- [ ] A sticky date label that floats over the messages and changes while you scroll: write down whether it is stitched in once per screen (as with the spinner) or not at all.
- [ ] Drag only the message list instead (no header, no composer): the result is messages only, with no static rows at the ends.
- [ ] A blinking caret in the composer, presence dots and a static avatar badge do not break the match.
- [ ] A chat's bouncing typing dots (the three animated dots of "someone is typing", from another device or a second account) while you scroll slowly. Known risk: the dots are a small element whose pieces move between rows, so the finder may read them as a small scroll of a narrow column. Write down what happens: nothing visible, a hiccup in the preview height (the readout jumping by a few pixels), a doubled row near the dots, or the status line going to `Too fast. Scroll back up a little.` Then hold still for ten seconds with the dots bouncing and note whether the readout grows while you are not scrolling (it must not).
- [ ] A narrow scrolling column in a wide selection: drag the whole chat window plus a wide margin of desktop (or a split view in which only a narrow list scrolls), then scroll the list. The list is stitched in order and the static area around it does not stop the match; the preview grows while you scroll.
- [ ] Messages loading in at the bottom while you capture (send a few from another device): the capture stays contiguous or shows the too-fast line and recovers; it never crashes.
- [ ] A new message that appears without the list scrolling (a short conversation that does not fill the window yet, or a message sent while you hold still): the status line stays `Scroll down slowly. Click Done at the end.`, never `Too fast. Scroll back up a little.`, and the readout does not grow. Then scroll on: the capture continues.

## The height cap
`long.html` is about 21,000 pt tall, so a Retina capture reaches 16,384 px (8,192 pt) before the end. On a 1x display the cap is 16,384 pt.
- [ ] Capture from the top of `long.html` with a 1000 pt tall area and keep scrolling. When the height reaches the cap the status line reads `Reached the 16,384 pixel limit.`, the session ends by itself and `Stitching…` may flash. No Done click is needed. Write down whether the result appears without your input.
- [ ] `sips -g pixelHeight -g pixelWidth <file>` reports a height of exactly 16384 and the area's width in pixels. The content stops at a row, not in the middle of a half-written one: the last section is simply cut by the bottom edge.
- [ ] The menu bar menu opens without delay while the cap capture is encoding after Done (the encode is off the main actor), and the overlay appears within a few seconds. Write down the time from Done to the overlay.
- [ ] Memory: Activity Monitor shows TidyShot using well under 1 GB at the cap, and back near its idle size a few seconds after the overlay appears.
- [ ] A capture that ends just below the cap by Done, and one that ends exactly at it, both save and open.

## Escape and Cancel
- [ ] Before Start, Escape closes the panel and the frame and nothing is saved. Before Start, **Cancel** does the same.
- [ ] After Start with Safari frontmost, Escape cancels at once: the panel, the frame and the indicator go, nothing is written to the save folder, no row appears in Recent Captures, no upload starts, `history.json` is unchanged, and the Quick Access overlay does not appear.
- [ ] Same with **Cancel**, after scrolling a few screens: nothing is saved, and a new ⌃⇧5 starts a fresh session with an empty preview.
- [ ] Escape is not swallowed outside a session. After Done or Cancel, type some text in Safari's address bar and press Escape: the address reverts, as it does without TidyShot running. Escape also works normally in a Terminal running `vim` and in a full-screen video.
- [ ] Escape is not swallowed during the selection overlay either way: it cancels the overlay and the next Escape in another app behaves normally.
- [ ] Stopping while the stream starts never leaves a capture running: click **Start** and press Escape (or click **Cancel**) at once, ten times in a row, as fast as you can; also Start then ⌃⇧5 then Escape. Each time the panel and frame go, nothing is saved and the screen-recording indicator in the menu bar is gone a moment later and stays gone (watch it for a few seconds after the last attempt; Activity Monitor shows no sustained TidyShot CPU). Then start a normal capture to check a new session works.
- [ ] Click **Done** in the panel while another app is frontmost: it finishes the capture and the overlay appears; the other app stays frontmost.

## Window versus area
- [ ] Capture the same Safari window twice, once by clicking it and once by dragging a rectangle over exactly the same frame. The widths in pixels match, the contents match, and both images come out the same way, window chrome included; no transparent corners in either (the capture is of the display).
- [ ] An area inside a page with a pane on the left and a pane on the right (Finder's list view with its sidebar, or Notes): put the pointer over the pane to scroll. The pane that scrolls is stitched; the fixed sidebar columns are copied from the screen, and the result has no seam where the sidebar meets the list.
- [ ] A window on a display other than the main one: the capture is of that display (not the main one), at that display's scale.
- [ ] Mixed scales (needs two displays): repeat the Safari capture on a 1x display. The PNG is in points (width in pixels equals the area's width in points), `dpiWidth` is 72, and the first screen equals a one-shot taken there.

## Auto-scroll and the post-event permission
Run this section after the manual ones. TidyShot is still not in the Accessibility list.
- [ ] Open a session. **Scroll automatically** is off and disabled, and an **Allow Auto-Scroll…** link sits under it. Start still works and behaves as manual mode, with the manual status lines. Cancel.
- [ ] The link opens a window titled `Accessibility access for auto-scroll` with a scroll icon (the window's own title bar reads `TidyShot`), the body text about posting scroll-wheel events (`Without it, you scroll and TidyShot captures as you go.`), the buttons **Request Access** (default) and **Open System Settings**, and the caption `If auto-scroll stays unavailable after you allow it, quit and reopen TidyShot.` The menu bar menu has no item for this permission.
- [ ] **Request Access** shows the system prompt. **Open System Settings** opens Privacy & Security > Accessibility. Add or switch on TidyShot there. Within about a second the window shows `Access granted. Auto-scroll is ready.` in green in place of the two buttons, without reopening it.
- [ ] With a session open before Start when the grant happens, the panel notices within about a second: the checkbox turns on and enabled, the link goes, and the status line reads `Click Start, then hold the pointer over the area.` A new session shows the same.
- [ ] Uncheck the checkbox, finish the session, open another: it is still off. Check it again for the next items.
- [ ] Delivery, first of all: with the grant held, Start with the pointer over the area moves the page. If no wheel event reaches the app, skip the rest of this section, write it down and report it: Task 6's fallback applies (auto-scroll stays off, the checkbox shows off and disabled with `Auto-scroll is unavailable: macOS did not deliver TidyShot's scroll events.` under it instead of the link, and every manual item above is unaffected). If the fallback is already in the build, check exactly that and that manual mode works.
- [ ] Safari, `long.html` at the top, area dragged over the page: Start with the pointer outside the area: the status line reads `Paused. Move the pointer over the area to continue.` and nothing scrolls. Move the pointer into the area: the line reads `Scrolling… Move the pointer away to pause.` and the page scrolls by itself, first by about half the area, then by about 0.6 of the part between any sticky header and footer, with a short settle between steps. Move the pointer out: it pauses within a fraction of a second, and TidyShot never moves the pointer; moved out while a step is under way, the rest of that step is not posted (the page stops at once). Move it back in: it resumes.
- [ ] Let it run to the end of the page: after two unchanged screens (with a short wait before the second) the line reads `Reached the end.` and, after a moment, the capture finishes by itself and the overlay appears. The result is the whole page in order, the footer once at the end, no repeat of the last screen, the same checks as the manual page capture. Write down the time per screen.
- [ ] `long.html#lazy`: auto-scroll reaches the bottom, waits, the 20 late sections load, and the capture goes on through them to a second end. The result includes `Late section 20`. If the late sections never load, scroll by hand to the bottom once to check the page.
- [ ] `long.html#jump`: every wheel event jumps the page 1.6 screens down, so each step loses the match. After each loss TidyShot posts a step back and halves the next one (the page jumps again, since this page turns every wheel event into a jump down); after three losses in a row the line reads `Auto-scroll lost its place. Scroll back up a little, or click Done.` and no more events are posted. Continue by hand with the keyboard (this page turns the wheel into jumps): press Home, then hold the Down arrow; the line changes to `Scroll down slowly. Click Done at the end.` at the first matched movement and the capture continues in manual mode. Done saves what was stitched.
- [ ] Natural scrolling: run the Safari auto-scroll capture with System Settings > Trackpad > Scroll & Zoom > Natural scrolling on, then off (and a mouse set to the opposite). Both finish at the end of the page. Start once from halfway down and once from the very top. From halfway, if the first step moves the page up, TidyShot flips the direction once and carries on. From the top, if the first step pushes against the top and nothing moves, TidyShot tries the other direction once and runs down to the end; it does not end on the first screen. Write down which setting caused either, if any.
- [ ] Terminal scrollback and the chat from the earlier sections: auto-scroll with the pointer over the area scrolls them to the end and the result matches the manual one (the `awk` check passes for Terminal).
- [ ] A page with the pointer over a pane that does not scroll (a toolbar, a sidebar): wheel events go to the view under the pointer, so nothing scrolls. TidyShot tries the other direction once, waits 700 ms, tries again, then shows `Reached the end.` and saves the first screen alone. Write down what the result is.
- [ ] Panel over the area: make the area wide enough that the panel sits inside it, not beside it (select most of the screen). Start in auto mode with the pointer resting on the panel: the status line reads `Paused. Move the pointer over the area to continue.` and the panel's preview does not move, no event reaches TidyShot's own window. Move the pointer onto the content outside the panel: scrolling starts. Move it back over the panel, also in the middle of a step: it pauses at once, and the panel's preview never scrolls (no wheel event reaches it).
- [ ] Revoke while it runs: start an auto-scroll capture, remove TidyShot from the Accessibility list. The next step hands over to manual (the hand-over line); no event is posted afterwards, and the capture finishes by hand.
- [ ] Re-granting after an ad-hoc rebuild: rebuild and relaunch the app (ad-hoc signing). Open a session: the checkbox is off and disabled again, even though System Settings may still show TidyShot switched on (a stale entry). Remove TidyShot from the list with the minus button, press **Request Access** in the permission window, switch it on: the window shows `Access granted. Auto-scroll is ready.` and auto-scroll delivers events again. Screen Recording needs the same re-grant after an ad-hoc rebuild. With Apple Development signing, a rebuild keeps both: write down which signing you tested.
- [ ] Afterwards, quit and reopen TidyShot with the grant in place: the checkbox is on, as the caption on the permission window says to do when it stays unavailable.

## The result: overlay, save and upload
Use the three after-capture actions in turn (Settings > General), each with a Safari capture of `long.html` of two or three screens.
- [ ] "Save and copy image": the overlay appears with the top of the page in its 96 by 72 well. The PNG is in the save folder, named by the file name template; `sips -g pixelWidth -g pixelHeight -g dpiWidth` reports the stitched size and 144 (or 72 on a 1x display). Preview > File > New from Clipboard shows the whole tall image, and pasting into Notes works.
- [ ] "Upload and copy URL": the overlay shows the upload; when it finishes the URL is on the clipboard. `curl -s <url> -o /tmp/tall.png && sips -g pixelWidth -g pixelHeight /tmp/tall.png` reports the same size as the file; `history.json` has that `pixelWidth` and `pixelHeight` (the full size, not the thumbnail's).
- [ ] "Upload only, keep no local file": nothing appears in the save folder, the upload finishes, the URL is on the clipboard and the temporary file is deleted. With Wi-Fi off, the upload fails and `pending/<UUID>.png` keeps the tall PNG until Retry Failed Uploads succeeds.
- [ ] With Network Link Conditioner on a slow profile, a tall capture's upload shows progress on the overlay and the overlay's Delete during the upload cancels it and removes what was written.
- [ ] The overlay's Delete on a stitched capture, after one confirmation: the file, the history row, the thumbnail and (when uploaded) the object are gone.
- [ ] Nothing is written or uploaded before Done: during a session, the save folder, `history.json` and the bucket do not change, in all three actions.
- [ ] The overlay appears, and the other captures work, while a previous tall capture is still encoding or uploading.
- [ ] A stream that stops by itself (optional, needs a second display): start a capture on the second display, scroll a few screens, then unplug that display or put it to sleep. A notification titled `Scrolling capture stopped` says `The capture stopped early: <reason> TidyShot saved what it had.` (the reason is `The screen recording stream stopped.` when ScreenCaptureKit gives none) and the rows stitched so far, up to the last screen before the stop, are saved like any capture. Stopped before the first frame arrived: `Scrolling capture failed` with the reason only, and nothing saved.

## Annotate a stitched capture
- [ ] The pencil button on the overlay opens the editor on a stitched capture of three screens. The picture shows complete at Fit, and ⌘1 (actual size) and ⌘0 (fit) work; scrolling and Space-drag pan along the whole height.
- [ ] Draw a redaction near the top, a text in the middle and an arrow near the bottom; the strokes sit on the content under the pointer at every height. Crop to the middle third: the saved size is the crop's. ⌘S writes the file; the unsaved dot behaves as for any capture.
- [ ] ⌘U on an uploaded stitched capture replaces the object under the same link; `curl` shows the edit at the full height.
- [ ] Annotate on the capture at the cap (the 16,384 px one): the editor opens and shows the picture, with no blank or black canvas, at Fit and at 100%. Scroll to the very bottom at 100% and draw a rectangle there; ⌘S saves it. Write down whether the pan and the drawing keep up (this is the check behind the 16,384 px cap).
- [ ] Recent Captures: the Annotate button on the row of a stitched capture opens the editor as above; "Upload only" captures that finished uploading download the object first and open it.

## Thumbnails of tall images
- [ ] A capture taller than three times its width (drag an area 300 pt wide and 400 pt tall, scroll through three screens): the overlay's well and the Recent Captures thumbnail show the **top** of the page, filling the well, not a thin sliver of the whole page. In the `thumbnails` folder `sips -g pixelWidth -g pixelHeight` on its file reports a height of 320 and a width of about 213 (2:3).
- [ ] The Recent Captures hover preview of the same row shows the top of the page too, sharper than the thumbnail: it is made from the file and cut to the top the same way.
- [ ] Thumbnail made from the file: quit TidyShot, delete the capture's file from the `thumbnails` folder, relaunch and open Recent Captures. The row's new thumbnail (made from the PNG through ImageIO) shows the **top** of the page, about 213 by 320, not a sliver.
- [ ] A capture only 2.5 times as tall as it is wide (area 400 by 1000 pt, Start and Done at once): no crop; the thumbnail is the whole capture, about 128 by 320.
- [ ] A normal area, window and fullscreen capture still produce the thumbnails they did before (compare with an earlier row).
- [ ] `history.json` has the full `pixelWidth` and `pixelHeight` for each stitched row, and the row's subtitle shows the full size.

## Other apps and conditions
Capture each from a start of the content to its end by hand, then by auto-scroll, and write down the result (OK, or what went wrong).
- [ ] Notes with a long note; Finder in list view with a few hundred items (select the list, not the sidebar); Xcode's source editor on a long file; Slack's long channel, as above; Chrome, as above.
- [ ] Dark mode, system-wide: the dashed frame is visible over dark content and the panel is legible. Switch the appearance mid-session: nothing breaks.
- [ ] A site with a sticky header and a cookie footer: header once at the top, footer once at the end, in Safari and in Chrome.
- [ ] Natural scrolling on and off, both modes (see the permission section).
- [ ] Two displays at mixed scales: see the window-versus-area section.
- [ ] Reduce Motion on, and Increase Contrast on: the panel is usable, and a capture still completes.

## VoiceOver
Turn VoiceOver on (⌘F5) and open a session.
- [ ] VO-arrow around the panel: the preview, the size readout, the status line, the checkbox, **Cancel**, **Start** and then **Done** are each read by name or value, and the status line is read again when it changes. The Return and Escape keys work with the VoiceOver cursor in the panel.
- [ ] Turn VoiceOver off. Everything above behaves as before.

## Regression
- [ ] Capture Area, Capture Window and Capture Fullscreen after a scrolling capture: normal, with the Quick Access overlay, uploads and thumbnails as before; a window capture with transparent corners keeps them.
- [ ] Quit TidyShot during a session (⌘Q from the menu): the panel and frame go, the indicator goes, and no file is written.
