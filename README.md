# TidyShot

A macOS menu bar screenshot tool. Capture an area, a window, or a display; it is saved as a
Retina-correct PNG, copied to the clipboard, and (in a later phase) uploaded to your own S3 bucket
with the URL on your clipboard.

Requires macOS 26 or later.

## Build

```bash
brew install xcodegen
xcodebuild -runFirstLaunch
cp Config/Local.xcconfig.example Config/Local.xcconfig
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
Audio Recording). With ad-hoc signing (the default in `Config/Local.xcconfig.example`), macOS asks
again after every rebuild. Sign in to Xcode with an Apple ID and set `DEVELOPMENT_TEAM` in
`Config/Local.xcconfig` to avoid that.

## Default shortcuts

| Action | Shortcut |
|---|---|
| Capture area (click a window to capture it) | ⌃⇧4 |
| Capture window | ⌃⇧2 |
| Capture fullscreen | ⌃⇧3 |

Change them in Settings > Shortcuts.

## Documents

- Design: `docs/superpowers/specs/2026-10-19-tidyshot-screenshot-design.md`
- Plans: `docs/superpowers/plans/`
- Manual test checklist: `docs/testing/phase-1-manual-checklist.md`
