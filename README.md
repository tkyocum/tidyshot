# TidyShot

A macOS menu bar screenshot tool. Capture an area, a window, or a display; it is saved as a
Retina-correct PNG, copied to the clipboard, and uploaded to your own S3-compatible bucket
with the URL on your clipboard.

Requires macOS 26 or later.

## Build

```bash
brew install xcodegen
xcodebuild -runFirstLaunch
xcodegen generate
xcodebuild -project TidyShot.xcodeproj -scheme TidyShot -configuration Debug -derivedDataPath .build build
open .build/Build/Products/Debug/TidyShot.app
```

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

## Default shortcuts

| Action | Shortcut |
|---|---|
| Capture area | ⌃⇧4 |
| Capture window | ⌃⇧2 |
| Capture fullscreen | ⌃⇧3 |

Change them in Settings > Shortcuts.

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

Tools and their keys: Select `V`, Redact `D`, Pixelate `X`, Blur `B`, Rectangle `R`, Arrow `A`.
Shift squares a box and snaps an arrow to 45 degrees; Option draws a box from its centre. Keys `1`
to `6` set the line width to 2, 3, 4, 6, 8 or 12 points. With Select, the arrow keys move the
selection by one pixel (ten with Shift), Delete removes it and Escape deselects. The colour and
options buttons in the toolbar set the colour, line width, blur radius and pixel size for the tool
and the selection, and the editor remembers them. At the right of the toolbar are Copy, Save (the
downward arrow) and Upload (the cloud). The window is never narrower than its toolbar, so every
button stays in view.

| Action | Shortcut |
|---|---|
| Save (over the file, or Save As… with no file) | ⌘S |
| Save As… | ⇧⌘S |
| Copy image | ⌘C or ⇧⌘C |
| Upload (same link) and close | ⌘U |
| Upload as New | ⌥⌘U |
| Undo, redo | ⌘Z, ⇧⌘Z |
| Close | ⌘W |
| Zoom to fit, actual size | ⌘0, ⌘1 |
| Zoom in, out | ⌘=, ⌘- |
| Select all | ⌘A |

Pinch or ⌘-scroll to zoom around the pointer; scroll to pan.

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
current save folder still uploads but keeps its editor open with the edit unsaved.

Upload also saves the edit over the local file first, as Save would, so the file and the uploaded
object match; a file outside the current save folder is left as it was. On a capture that is
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

When the clipboard still holds the image TidyShot put there for a capture, Save and Upload
replace it with the edited image; Upload then puts the link there as usual. Anything you
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
