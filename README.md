# TidyShot

A macOS menu bar screenshot tool. Capture an area, a window, a display, or content taller than the
screen; it is saved as a Retina-correct PNG, copied to the clipboard, and uploaded to your own
S3-compatible bucket with the URL on your clipboard.

Requires macOS 26 or later.

## Build

```bash
brew install xcodegen
xcodebuild -runFirstLaunch
xcodegen generate
xcodebuild -project TidyShot.xcodeproj -scheme TidyShot -configuration Release -derivedDataPath .build-rel build
open .build-rel/Build/Products/Release/TidyShot.app
```

Run the Release build: scrolling capture compares frames as they arrive, and an unoptimised Debug
build is about 40 times slower and cannot keep up. The tests use the Debug configuration. Scrolling
capture diagnostics (`ScrollDiag`, written to `scrolldiag.log` in the app container's temporary
folder) exist only in Debug builds. Release builds are signed without the `get-task-allow`
entitlement that ad-hoc signing would add, so no other process of your account can attach to
TidyShot and borrow its Screen Recording permission; Debug keeps it for the tests and the debugger.

Or open `TidyShot.xcodeproj` in Xcode after `xcodegen generate`.

## Test

```bash
xcodebuild -project TidyShot.xcodeproj -scheme TidyShot -destination 'platform=macOS' -derivedDataPath .build test
```

## Permissions

TidyShot needs Screen Recording permission (System Settings > Privacy & Security > Screen & System
Audio Recording). With ad-hoc signing (the default), macOS asks again after every rebuild. To avoid that,
sign in to Xcode with an Apple ID, then switch to Apple Development signing:

```bash
cp Config/Local.xcconfig.example Config/Local.xcconfig
```

Edit `Config/Local.xcconfig` to set `CODE_SIGN_IDENTITY = Apple Development` and your
`DEVELOPMENT_TEAM`, then run `xcodegen generate` again.

Auto-scroll in Scrolling capture needs a second, optional permission: Accessibility (the "post
event" privilege that lets TidyShot send scroll-wheel events), under the same Privacy & Security
pane. Without it you scroll yourself and everything else works. See Scrolling capture below; ad-hoc
rebuilds lose this grant like they lose Screen Recording.

## Default shortcuts

| Action | Shortcut |
|---|---|
| All-in-One | ⌃⇧1 |
| Capture area | ⌃⇧4 |
| Capture window | ⌃⇧2 |
| Capture fullscreen | ⌃⇧3 |
| Capture scrolling | ⌃⇧5 |
| Capture previous area | ⌃⇧6 |
| Self-timer | none; set one in Settings > Shortcuts |
| Capture text | ⌃⇧7 |
| Restore closed overlay | none; set one in Settings > Shortcuts |

Change them in Settings > Shortcuts.

## Scrolling capture

Capture Scrolling (⌃⇧5, or the menu bar item) captures content taller than the screen: a long web
page, a terminal's scrollback, a chat channel. Drag an area at least 100 points tall, or click a
window to take its frame. A dashed outline marks the area and a small panel shows a live preview of
the stitched image, its size in pixels and a status line. Nothing is saved or uploaded until you
click Done; Cancel or Escape (which works from any app while a session runs) throws everything away.

**Manual mode.** Click Start (or press Return, or ⌃⇧5 again), scroll down slowly yourself, and click
Done (Return, or ⌃⇧5 again) at the end. If you scroll so fast that two screens no longer overlap,
the panel says "Too fast. Scroll back up a little."; scroll back until it clears and go on. Scrolling
up a little is harmless. Done straight after Start saves the area as an ordinary capture.

**Auto-scroll.** With "Scroll automatically" checked, hold the pointer over the area after Start and
TidyShot sends the scroll-wheel events itself, waits for the page to settle, and finishes when two
screens in a row show no change (after a short wait for lazy loading). Move the pointer out of the
area to pause; TidyShot never moves it. If it loses its place three times, it hands over to manual
mode. Auto-scroll needs the Accessibility permission (the "post event" privilege). The Allow
Auto-Scroll… link in the panel opens a window that requests it and opens System Settings. The grant
is tied to the app's code signature, so with ad-hoc signing every rebuild loses it: remove TidyShot
from the Accessibility list, add it again, and quit and reopen TidyShot if it still reads as
unavailable. Apple Development signing (see Permissions) keeps it.

**What to expect.** A header or footer that stays put (a toolbar, a sticky nav bar, a composer) is
kept once, at the top or bottom, and a fixed sidebar is ignored. A floating element inside the area
(a chat button, a spinner) is stitched in each time it appears. A capture ends at 65,536 pixels
tall (32,768 points on a Retina display); at that point the panel says so and the capture finishes.
An endless feed therefore runs to that limit. At that height and about 3,000 pixels wide the image
takes about 800 MB of memory, and about 1.7 GB while an annotated copy is saved. Content with no distinctive rows (a long run of
identical lines or a blank stretch taller than the area) cannot be placed, so the "Too fast" line
shows until you scroll back. A window pick captures the window's frame from the display, so a window
that overlaps it is in the picture. The macOS screen-recording indicator shows while a session runs.

After Done the capture goes through the same path as any other: the after-capture action, the
Quick Access overlay with Annotate and Delete, Recent Captures and the upload. A very tall capture's
thumbnail shows the top of the page. Annotate works on captures up to the 65,536 pixel limit (the
editor shows a tall capture as stacked 16,384 pixel strips, the most one GPU texture holds on every
Mac). A capture taller or wider than 16,384 pixels goes on the clipboard as PNG only, without the
uncompressed TIFF copy, which at that size would take hundreds of megabytes more.
Horizontal scrolling is not supported.

## Capture options

Settings > Capture has five options. *Freeze screen while selecting* shows a still picture of the
screen while you drag an area and cuts the capture from it, so menus, tooltips and video stay as
they were when you pressed the shortcut; window mode and scrolling capture are live. *Show cursor in
screenshots* puts the pointer into fullscreen, previous-area, self-timer and URL captures, and into
area captures only with freeze on; TidyShot never captures its own crosshair. *Include window
shadow* keeps the system shadow around a window capture; the corners are transparent either way.
*Hide desktop icons while capturing* is described under Hide desktop icons below. *Self-timer* sets
the countdown to 3, 5 or 10 seconds.

Capture Previous Area (⌃⇧6) captures the rectangle of your last area capture (or scrolling capture)
again, with no selection. It says so when there is no previous area or its display is gone.

## Quick Access overlay

Each capture shows a card in a corner of the screen. Several cards stack, newest at the corner, up
to the number set in Settings > Overlay. Settings > Overlay also chooses the display they appear
on: the capture's display (default), the pointer's, or the main display. The cards are not in any
capture.

A card shows the upload status and has Annotate, Pin and Delete buttons, `Save As…` and `Copy URL` or
`Retry`, and a close badge when you point at it; a right-click or Control-click opens a menu with
every action, including Copy Image. Closing a card does not delete the capture: Restore Closed
Overlay in the menu (or its shortcut) brings back the ten most recently closed cards, newest first.
A card whose capture was deleted, or that was opened in the editor, is not restored.

Drag a card to drop the screenshot into Finder, Slack, a browser, Mail, Messages or Notes. What
you drop is a copy of the file kept in TidyShot's container until a minute after the card closes,
named like the link when the capture was uploaded; the original stays where it was. In upload-only
mode the file is kept for as long as the card shows, so you can drag it after the link is on the
clipboard. A card for an older upload-only capture downloads its file when it is restored, and can
be dragged once that has finished. Settings > Overlay has *Close after dragging out*.

## All-in-One

All-in-One (⌃⇧1) opens a selection that stays adjustable. Drag a rectangle, or click a window to
take its frame; then drag the handles to resize it, drag inside to move it, or nudge it with the
arrow keys (Shift for 10 points). The toolbar under the selection has width and height fields, an
aspect-ratio lock, and Capture, Window, Fullscreen, Scrolling, Timer and Cancel. Return or a
double-click inside captures the area; Escape cancels. It opens with your last area already
selected, when that is on a connected display.

## Self-timer

Self-Timer (in the menu; no default shortcut) lets you select an area or click a window, then counts
down 3, 5 or 10 seconds (Settings > Capture) before it captures, so you can open a menu or show a
tooltip first. Escape cancels from any app.

## Pin to screen

Pin a capture from its card (the pin button or the right-click menu) to keep a floating copy above
other windows, on every Space. Drag it to move it, drag an edge to resize it, and with the pin
clicked (one click gives it the keyboard): arrow keys move it (Shift for 10 points), ⌘+ and ⌘- zoom
(never past the screen), ⌘0 is actual size (fitted to the screen when the capture is larger), ⌘C
copies, Escape or ⌘W closes, and Option-scroll changes the opacity. Its right-click menu has Copy
Image, Save As…, Annotate, Opacity, Actual Size, Lock and Close. A locked pin lets clicks through to
the window beneath; *Unlock Pinned Screenshots* in the menu bar menu makes pins clickable again. Pins
close when you quit, and deleting a capture closes its pins.

## Capture Text

Capture Text (⌃⇧7) copies the text in an area instead of an image. Select an area as for Capture
Area (Freeze screen applies), or click a window; TidyShot reads it on the Mac with Apple's Vision
and puts the text on the clipboard, one line for each line on screen. When the area holds a QR code
(or another two-dimensional code: Micro QR, Aztec, Data Matrix or PDF417), the code's contents are
copied instead, so a "Scan me" caption does not end up in the link; select without the code to get
the text. Several codes are copied one per line. Nothing is saved, uploaded or added to Recent
Captures, and the after-capture action does not apply.

With Show notification on, a notification shows the first line, and when a single code holds a web
link, clicking it opens the link. When nothing is found the clipboard is left alone and *No text
found* says so. The first Capture Text after a restart can take about 25 seconds while macOS loads
its text model; later ones take a fraction of a second, and other captures are not held up meanwhile.

## Hide desktop icons

TidyShot can cover the desktop's icons and widgets with the desktop picture, without changing
Finder's settings. *Hide desktop icons while capturing* (Settings > Capture) covers them during
area, window, fullscreen, previous-area, All-in-One and self-timer captures, the countdown included,
and uncovers them when the capture ends; scrolling captures and Capture Text leave the desktop alone.
*Hide Desktop Icons* in the menu bar menu covers them until you choose it again, also across
launches, and has a checkmark while on.

The covers sit below every window, on every Space and display. The picture is read again on a Space
switch, a display change, wake and every 10 minutes, so a new wallpaper reaches the cover at the
next of these. Clicks on the covered desktop do nothing: icons cannot be opened or dragged, and
clicking the picture does not reveal the desktop. Captures show the desktop picture where the icons
were. When TidyShot cannot read a display's desktop picture, that display stays uncovered and *Desktop
icons still showing* is posted, once per launch.

## URL scheme

Raycast, Keyboard Maestro, Shortcuts and scripts can drive TidyShot with `tidyshot://` URLs:

```bash
open 'tidyshot://capture-area?action=upload'
```

The names follow CleanShot X's, so a CleanShot macro works after changing `cleanshot://` to
`tidyshot://`.

| Command | What it does | Parameters |
|---|---|---|
| `capture-area` | Select an area; with a rectangle, capture it at once | `action`, `x`, `y`, `width`, `height`, `display` |
| `capture-window` | Click a window | `action` |
| `capture-fullscreen` | Capture the display under the pointer | `action` |
| `capture-previous-area` | Capture your last area again | `action` |
| `all-in-one` | All-in-One; a rectangle is preselected (or the previous area), and Return or a double-click captures it only after you click in the overlay or use its toolbar | `action`, `x`, `y`, `width`, `height`, `display` |
| `self-timer` | Select, then count down | `action` |
| `capture-scrolling` (or `scrolling-capture`) | Scrolling capture; a rectangle skips the selection, and the capture waits until you click Start (Return in the frontmost app does not start it); unstarted for a minute, it cancels itself | `action`, `x`, `y`, `width`, `height`, `display` |
| `capture-text` | Capture Text; with a rectangle, read it at once. The text or code goes to the clipboard | `x`, `y`, `width`, `height`, `display` |
| `restore-recently-closed` | Restore Closed Overlay | none |
| `hide-desktop-icons` | Turn Hide Desktop Icons on | none |
| `show-desktop-icons` | Turn Hide Desktop Icons off | none |
| `toggle-desktop-icons` | Turn Hide Desktop Icons on or off | none |

`action` is `upload` (upload only when that is your after-capture setting, otherwise save, upload
and copy the URL), `save` (save and copy the image), `copy` (the image on the clipboard and nothing
else: no file, no history, no card, no upload), `annotate` (then open the editor) or `pin` (then pin
it). Without `action` the after-capture setting in Settings > General applies.

`x`, `y`, `width` and `height` are points from the bottom-left corner of the display, as in
CleanShot: all four or none, plain numbers such as `120` or `40.5`, width and height above 0. A
rectangle that runs off the display is clipped to it. `display` is 1 for the main display and 2, 3
and so on for the others in the order macOS lists them; without it, the display under the pointer.
Command and parameter names, and actions, may be in any case. Other parameters are ignored, and a
parameter the command takes, given twice, is an error.

**Security.** Any app on this Mac can open a `tidyshot://` URL, and a web page can once you let your
browser open TidyShot. Settings > General > URL commands has two switches. *Allow URL commands
(tidyshot://)* is on by default; off, every command is refused. *Allow URL commands that capture
without a selection* is off by default: it covers the commands that capture without your drag or
click (`capture-fullscreen`, `capture-previous-area`, and `capture-area` and `capture-text` with a
rectangle), which are otherwise refused with a notification naming the app that sent them. Turn it
on only for macros that need it (a Keyboard Maestro macro for a fullscreen shot, say): any app on
the Mac can then take a screenshot through TidyShot and read it from the clipboard. The name shown
is what the sending app calls itself. Every other command waits for your drag, click or Start, or
captures nothing, and commands never take a file path.

Errors (an unknown command or action, a bad rectangle, a missing display, a parameter given twice)
appear as notifications titled *TidyShot URL command*. A capture command that arrives while a
capture runs is ignored (restore and the desktop-icon commands still run), and of several URLs that
wait for TidyShot to launch only the first capture command runs. If `open tidyshot://…` starts an
old build, more than one TidyShot.app is registered: list them with
`/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -dump | grep -i tidyshot`
and remove the stale ones with `lsregister -u <path>`.

## Upload

Settings > Upload takes an S3-compatible endpoint (AWS S3, Cloudflare R2, Backblaze B2, MinIO),
region, bucket, a public URL template such as `https://snap.tky.io/{key}`, and an object key
template. Credentials are stored in your login keychain; Forget Credentials removes them again.
Save and Test Connection saves the form, then uploads a small probe object into the folder your
key template would use, fetches it through the public URL without credentials, and deletes it.

The key template defaults to `{random:6}` (`aSIS7x.png`). Tokens: `{date}` `{year}` `{month}`
`{day}` `{time}` `{datetime}` `{hostname}` `{counter}` `{random}` `{random:N}`; letters,
digits, `.`, `_`, `-` and `/` are allowed between tokens, and `/` makes folders, so
`shots/{year}/{month}/{hostname}-{random:8}` is valid. The same tokens work in the file name
template. The app checks that a key is unused before uploading; a template without `{random}` or
`{counter}` gets a warning, because captures can then produce the same key and only that check
keeps an upload from overwriting an earlier object. By default no
ACL header is sent; turn on "Send public-read ACL" only if your bucket relies on object ACLs
rather than a bucket policy or CDN.

After capture, "Upload and copy URL" saves the file locally first, then uploads it; the public
URL replaces the clipboard contents when the upload finishes. "Upload only, keep no local file"
writes the PNG inside TidyShot's container instead, uploads it, copies the URL and deletes the
file; a failed upload keeps it until a retry succeeds or the capture is deleted.

### Optimise with Clop

If [Clop](https://lowtechguys.com/clop) (direct or Setapp build) is installed, Settings > General >
Images has "Optimize images with Clop". With it on and Clop running, every upload (a capture,
upload-only, the editor's Upload, replace and Upload as New, and every Retry) is first rewritten by
Clop as a smaller PNG, which is lossy (256 colours); 144 DPI is kept. The setting takes effect without
Save. Clop works on a throwaway copy: the saved file, the pending file and the editor's file stay as
captured, and a retry optimises the original again. TidyShot never launches Clop. If Clop is not
running, fails, converts the format or cannot shrink the image, the original uploads, with one
`Clop: <reason>, uploading the original` line in the log and no error. Delete during optimisation
cancels the upload ("Upload cancelled."). Clop keeps its own copy of each image in its cache.
Talking to Clop needs one sandbox exception (`com.apple.security.temporary-exception.mach-lookup.global-name`
for Clop's two port names), added to the four entitlements TidyShot already had. That exception would
need App Review approval for a Mac App Store build; Developer ID builds are unaffected. The client is
adapted from ClopSDK (MIT); see `ThirdPartyNotices.md`.

## Recent Captures

Hover Recent Captures in the menu bar menu for the newest 15 captures, each with a thumbnail, its
name and how long ago it was taken. Click a row to copy its URL (or the file when it was never
uploaded). The row's buttons open the capture in the editor (see Annotate), copy the URL, copy the
image (downloaded from the bucket with a signed request when no local file is left), or delete the
capture. Hover a thumbnail to see a larger preview of the capture beside the menu.

Delete asks once, "Delete this capture?", then removes the object from the bucket it was uploaded
to, the local file, the thumbnail and the history entry. If the delete fails (no network, no
credentials, or the bucket refuses it), a second alert offers to remove the capture from history
anyway and leave the object where it is. If the local file cannot be removed from the save folder
(for example after another save folder was chosen), a similar alert offers to remove the capture
from history and keep the file where it is.
The Quick Access overlay has the same Delete; while an upload is still running it cancels it
first. Retry Failed Uploads appears in the menu whenever an upload has failed.
Thumbnails live in `~/Library/Containers/io.tky.tidyshot/Data/Library/Application Support/TidyShot/thumbnails`.

## Annotate

The pencil button on the Quick Access overlay opens the capture in the editor. Each Recent Captures
row has the same button, which also works with the overlay turned off; a capture with no local
file left is downloaded from the bucket first.

Tools and their keys: Select `V`, Redact `D`, Pixelate `X`, Blur `B`, Rectangle `R`, Arrow `A`,
Ellipse `E`, Line `L`, Pencil `P`, Highlighter `H`, Text `T`, Crop `C`. Shift squares a box (a
circle for Ellipse) and snaps an arrow or a line to 45 degrees; Option draws a box from its centre.
Keys `1` to `6` set the line width to 2, 3, 4, 6, 8 or 12 points, or, with Text, the text size to
12, 16, 20, 28, 40 or 56 points. With Select, the arrow keys move the selection by one pixel (ten
with Shift), Delete removes it and Escape deselects. The colour and options buttons in the toolbar
set the colour, line width, blur radius and pixel size for the tool and the selection, and the
editor remembers them. At the right of the toolbar are Copy, Save (the downward arrow) and Upload
(the cloud). The window is never narrower than its toolbar, so every button stays in view.

Pencil draws a smoothed freehand line. Highlighter draws a wide yellow stroke at 45% opacity that
darkens what it covers, so dark text stays readable under it. Text: click to place a text and
type; Return commits, Shift-Return starts a new line, Escape cancels and clicking elsewhere
commits. Click committed text with Text, or double-click it with Select, to edit it again. While
you edit, ⌘C, ⌘X, ⌘V, ⌘A and ⌘Z act on the text, and one ⌘Z after committing undoes the whole
text. Crop: press `C`, drag the eight handles or drag out a new rectangle (the readout shows its
size in pixels), and press Return to apply or Escape to cancel; picking another tool applies it.
A crop is undoable and applies last, so Save, Save As…, Copy and Upload all produce the cropped
image, the capture's recorded size and thumbnail follow it, and nothing outside the crop is in the
saved or uploaded file. Under an applied crop the covered area is not clickable: Select deselects
there, Text ignores the press and the drawing tools start at the crop's edge. A paste lands inside
the crop, and VoiceOver lists only the annotations that reach into it.

⌘D duplicates the selection 10 points down and to the right, and with Select, dragging it with
Option held drags a copy. ⌘C copies the selected object and ⌘V pastes it, in the same editor or
another one, at the same size in points; with nothing selected ⌘C still copies the image. Hold
Space and drag to pan. Each annotation is an accessibility element, so VoiceOver can read the
canvas.

| Action | Shortcut |
|---|---|
| Save (over the file, or Save As… with no file) | ⌘S |
| Save As… | ⇧⌘S |
| Copy image (⌘C copies the selected object instead) | ⌘C or ⇧⌘C |
| Upload (same link) and close | ⌘U |
| Upload as New | ⌥⌘U |
| Undo, redo | ⌘Z, ⇧⌘Z |
| Duplicate the selection | ⌘D |
| Paste an object copied with ⌘C | ⌘V |
| Close | ⌘W |
| Zoom to fit, actual size | ⌘0, ⌘1 |
| Zoom in, out | ⌘=, ⌘- |
| Select all | ⌘A |

Pinch or ⌘-scroll to zoom around the pointer; scroll, or hold Space and drag, to pan.

Only Redact is safe for passwords, tokens and keys. Pixelate and Blur hide text at a glance, but
public tools can partly recover pixelated or blurred text. A blur or pixelate drawn over a
redaction blurs the solid fill, never what is under it.

Save writes the edit over the capture's file: the file in the save folder, or the temporary file
of an upload-only capture whose upload has not succeeded. For a capture with no local file left
(an upload-only capture that finished uploading), or whose file is outside the current save folder,
Save opens a save panel instead, as Save As… does. Save never uploads; on an uploaded capture the
window then says the uploaded copy still shows the original. Save As… saves the edited image as a
PNG wherever you choose, named after the capture's file (or by the file name template); it makes no
new capture, uploads nothing and leaves the capture as it was. It works even while the capture
uploads or after it was deleted. Copy puts the edited image on the clipboard.

Upload sends the edit at once and closes the editor; the link is on the clipboard as soon as the
upload finishes. If the upload cannot start (no destination set up, or the capture is busy), the
editor stays open and a notification says why. If it fails later, the capture keeps the edited
file, and Annotate on its Recent Captures row opens it again. A capture whose file is outside the
current save folder keeps its edit in TidyShot's own pending folder, as an upload-only capture
does, and the original file stays where it is.

Upload also saves the edit over the local file first, as Save would, so the file and the uploaded
object match; a file outside the current save folder is left as it was, and the edit is kept in
TidyShot's pending folder instead. On a capture that is
already uploaded it replaces the object under the same key: the link you shared
keeps working and shows the edit. It makes a new link instead when Settings > Upload now points at
another endpoint, region or bucket, or when another capture shares the link; a capture uploaded
before Phase 3 always gets a new link and its old object stays in the bucket. Upload as New always
makes a new link and deletes the old object once the new one is up. An old object that could not be
deleted stays listed on the capture, and deleting the capture removes it.

Replacing does not clear caches. If the link was opened before the replace, a CDN such as
CloudFront, and the browser that opened it, can keep showing the original until their cache time
runs out, and a bucket with versioning keeps the original as an older version. So redact before
you paste the link anywhere. If an unredacted link was already opened, use Upload as New: the old
object is deleted, but a CDN can still serve its copy until it expires, so also invalidate the path
in the CDN, and delete the old version in a versioned bucket. The first replace after each launch
posts a reminder.

When the clipboard still holds the image TidyShot put there for a capture, Save, Save As… and
Upload replace it with the edited image; Upload then puts the link there as usual. Anything you
copied since is left alone. A clipboard manager may still keep the original in its history; clear
it there.

Closing an editor with unsaved changes, or quitting TidyShot, asks whether to save them. Save
there does what ⌘S does; while the capture uploads or is being deleted it reads Save As….
Cancelling the save panel keeps the editor open.

## Documents

- Design: `docs/superpowers/specs/2026-10-19-tidyshot-screenshot-design.md`
- Plans: `docs/superpowers/plans/`
- Phase 1 manual test checklist: `docs/testing/phase-1-manual-checklist.md`
- Phase 2 manual test checklist: `docs/testing/phase-2-manual-checklist.md`
- Phase 3 manual test checklist: `docs/testing/phase-3-manual-checklist.md`
- Phase 3.1 manual test checklist: `docs/testing/phase-3-1-manual-checklist.md`
- Phase 4a manual test checklist: `docs/testing/phase-4a-manual-checklist.md`
- Phase 4b manual test checklist: `docs/testing/phase-4b-manual-checklist.md`
- Phase 5 manual test checklist: `docs/testing/phase-5-manual-checklist.md`
- Phase 6a manual test checklist: `docs/testing/phase-6a-manual-checklist.md`
- Phase 6b manual test checklist: `docs/testing/phase-6b-manual-checklist.md`
- Phase 7 (Clop) manual test checklist: `docs/testing/phase-7-clop-manual-checklist.md`
- Phase 7b (Capture Text, Hide desktop icons) manual test checklist: `docs/testing/phase-7b-manual-checklist.md`
