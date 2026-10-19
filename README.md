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
region, bucket, optional key prefix, and a public URL template such as `https://snap.tky.io/{key}`.
Credentials are stored in your login keychain. Save and Test Connection saves the form, then
uploads a small probe object, fetches it through the public URL without credentials, and deletes it.

Object keys are random, 6 characters by default (4 to 32). The app checks that a key is unused
before uploading. By default no ACL header is sent; turn on "Send public-read ACL" only if your
bucket relies on object ACLs rather than a bucket policy or CDN.

After a capture the file is saved locally first, then uploaded; the public URL replaces the
clipboard contents when the upload finishes. Failed uploads stay in the menu's Recent Captures
list with a retry action.

## Documents

- Design: `docs/superpowers/specs/2026-10-19-tidyshot-screenshot-design.md`
- Plans: `docs/superpowers/plans/`
- Phase 1 manual test checklist: `docs/testing/phase-1-manual-checklist.md`
- Phase 2 manual test checklist: `docs/testing/phase-2-manual-checklist.md`
