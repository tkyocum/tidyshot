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
folder) exist only in Debug builds.

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
| Capture area | ⌃⇧4 |
| Capture window | ⌃⇧2 |
| Capture fullscreen | ⌃⇧3 |
| Capture scrolling | ⌃⇧5 |
| Capture previous area | ⌃⇧6 |
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

Settings > Capture has three options. *Freeze screen while selecting* shows a still picture of the
screen while you drag an area and cuts the capture from it, so menus, tooltips and video stay as
they were when you pressed the shortcut; window mode and scrolling capture are live. *Show cursor in
screenshots* puts the pointer into fullscreen and previous-area captures, and into area captures
only with freeze on; TidyShot never captures its own crosshair. *Include window shadow* keeps the
system shadow around a window capture; the corners are transparent either way.

Capture Previous Area (⌃⇧6) captures the rectangle of your last area capture (or scrolling capture)
again, with no selection. It says so when there is no previous area or its display is gone.

## Quick Access overlay

Each capture shows a card in a corner of the screen. Several cards stack, newest at the corner, up
to the number set in Settings > Overlay. Settings > Overlay also chooses the display they appear
on: the capture's display (default), the pointer's, or the main display. The cards are not in any
capture.

A card shows the upload status and has Annotate and Delete buttons, `Save As…` and `Copy URL` or
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
