# TidyShot

A macOS menu bar screenshot tool. Capture an area, a window, or a display; it is saved as a
Retina-correct PNG, copied to the clipboard, and (in a later phase) uploaded to your own S3 bucket
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

## Documents

- Design: `docs/superpowers/specs/2026-10-19-tidyshot-screenshot-design.md`
- Plans: `docs/superpowers/plans/`
- Manual test checklist: `docs/testing/phase-1-manual-checklist.md`
