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
`{day}` `{time}` `{datetime}` `{hostname}` `{app}` `{counter}` `{random}` `{random:N}`; letters,
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

The menu's Recent Captures… item opens a gallery of thumbnails, newest first. Hover for a larger
preview, click to copy the URL (or the file when it was never uploaded), and use the context menu
to retry a failed upload, reveal the file, or delete the capture, which removes the object from
the bucket it was uploaded to, the local file, the thumbnail and the history entry after one
confirmation. The confirmation also offers Remove from History Only, which drops just the entry
and keeps the object and the file. The Quick Access overlay has the same Delete; while an upload
is still running it cancels it first.
Thumbnails live in `~/Library/Containers/io.tky.tidyshot/Data/Library/Application Support/TidyShot/thumbnails`.

## Documents

- Design: `docs/superpowers/specs/2026-10-19-tidyshot-screenshot-design.md`
- Plans: `docs/superpowers/plans/`
- Phase 1 manual test checklist: `docs/testing/phase-1-manual-checklist.md`
- Phase 2 manual test checklist: `docs/testing/phase-2-manual-checklist.md`
- Phase 3 manual test checklist: `docs/testing/phase-3-manual-checklist.md`
