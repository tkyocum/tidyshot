# Phase 6 research notes (2026-10-21)

No GPL source was read (macshot, Clop). CleanShot X is used only through its public pages.

## CleanShot X, public docs

- URL scheme API, https://cleanshot.com/docs/api: commands `all-in-one` (x, y, width, height, display), `capture-area` (x, y, width, height, display, action), `capture-previous-area` (action), `capture-fullscreen` (action), `capture-window` (action), `self-timer` (action), `scrolling-capture` (x, y, width, height, display, start, autoscroll), `pin` (filepath), `record-screen`, `capture-text`, `open-annotate` (filepath), `open-from-clipboard`, desktop-icon commands, `add-quick-access-overlay` (filepath, required), `open-history`, `restore-recently-closed`, `open-settings` (tab). `action` values: copy, save, annotate, upload, pin. `display` 1 = main display, default the display under the cursor. Coordinates: "Point (0,0) is located in the lower left corner of the screen." The page has no security notes and no confirmation step: opening a link "will launch the app and execute the command."
- Features page, https://cleanshot.com/features: Quick Access Overlay lets you drag and drop files to other apps, copy, save or annotate, "Restore recently closed overlay", supports multiple displays, swipe gestures, position and size settings, auto-close, temporarily hiding overlays. All-in-One: one shortcut for all modes, "specify size and lock the aspect ratio", saves the last selection. Freeze screen for moving content. Self-timer. Window shots: transparent background with "Enable/Disable shadow", or a background with padding. Pinned screenshots: always on top, size and opacity, "Lock Mode" to click through, arrow keys to position.
- Changelog, https://cleanshot.com/changelog (via search result summaries): 4.7.5 improved closing several overlays one by one and marks the newest; 4.8.4 Option-click copy keeps the overlay open. The stacking layout itself is not documented; the design's stack (newest at the corner) is TidyShot's own choice.

## Platform

- `SCScreenshotConfiguration` (MacOSX27.0.sdk, SCScreenshotManager.h): `width`, `height` (default "the width/height of the content being captured"), `showsCursor` (default visible), `sourceRect`, `destinationRect`, `ignoreShadows` ("ignore framing on windows (will ignore shadows)"), `ignoreClipping`, `includeChildWindows` (default on), `displayIntent`, `dynamicRange`, `contentType`, `fileURL`.
- `SCContentFilter` (SCStream.h): `contentRect` ("Size and location of content in points") and `pointPixelScale`, macOS 14+. Used for shadow sizing; whether `contentRect` includes the shadow is undocumented, hence the probe below.
- `NSCursor.currentSystemCursor` is deprecated ("Use ScreenCaptureKit ... showsCursor"), so drawing the real pointer into a live capture ourselves is not pursued (decision 7).
- Drag and drop grants: the CVE-2026-28910 write-up (https://mysk.blog/2026/05/19/cve-2026-28910/) states that "dropping a file onto an app grants that app access to it", including for protected locations, via the `com.apple.macl` attribute for non-sandboxed receivers; Apple's 26.4 fix restricted Archive Utility, not drag and drop itself. Supports handing a container file URL to receivers. Container-protection background: https://eclecticlight.co/2024/08/05/what-are-all-those-containers/ and https://www.sentinelone.com/de/blog/macos-14-sonoma-toughening-up-macos-for-the-enterprise/ (Sonoma asks before one app reads another's container; the drop grant is the user-intent path).
- File promises: Apple, https://developer.apple.com/documentation/appkit/supporting-drag-and-drop-through-file-promises (Photos sends and receives promises; the sample subclasses `NSFilePromiseProvider` to add types). WebKit receives promises (https://bugs.webkit.org/show_bug.cgi?id=165204). Chromium/Electron receiving promises: no source found either way; the checklist settles it for Slack and Chrome.
- URL events: no entitlement is needed to receive `kAEGetURL` in a sandboxed app; registration is `CFBundleURLTypes` in Info.plist (generated from `project.yml` `info.properties`). Sender PID via `keySenderPIDAttr` on the Apple event.

## Codebase facts the design relies on (main at a1dde71, branch phase-6-polish)

- `QuickAccessController` holds one panel; `show` closes the previous one; the panel is placed on the screen under the pointer; `isMovableByWindowBackground = true`.
- `captureFullscreen()` passes no `excludingWindows`, so a visible card is captured; area captures exclude only the selection windows.
- `runSelection` captures after mouse-up while the overlay is still up, with `showsCursor` from settings, so Show cursor captures the crosshair (SelectionView sets `NSCursor.crosshair` via cursor rects).
- `SelectionController.takeSnapshots()` runs after the overlay is shown, with `showsCursor: false`, excluding overlay windows by number.
- `.uploaded` removes an upload-only capture's pending file and sets `fileURL = nil`.
- `CaptureEngine` window captures: `desktopIndependentWindow`, `ignoreShadows = true`, size from `window.frame` and the display under the frame's centre.
- `EditorNaming.saveAsSuggestion` already gives a name for any record, including upload-only ones.
- Settings tabs today: General, Shortcuts, Capture (one toggle), Upload, Overlay (overlay plus history retention). No Advanced tab.
- Shortcuts ⌃⇧2 to ⌃⇧5 are taken; ⌃⇧1 and ⌃⇧6 are free in the app.

## Probes to run (not run for this draft)

No probe was run here: each needs a Screen Recording grant for the probe binary, or a GUI session.

1. **Window shadow** (Task 1, before code). A small sandboxed CLI or test host signed like TidyShot: for a Finder window and a Slack window, `SCContentFilter(desktopIndependentWindow:)`, print `contentRect`, `pointPixelScale`, `window.frame`; capture with `ignoreShadows = true` and `false`, once with width/height unset and once from `contentRect * pointPixelScale`; write PNGs and report each size and the alpha of the four corner pixels and of a pixel 20 pt below the window. Pass: the shadowed image is larger than the frame by the shadow, unscaled, with the window at 1:1. Fail: synthetic `WindowShadow`.
2. **Drag-out receivers** (Task 6, checklist). Finder, Slack, Chrome (a Gmail compose or a file input), Safari, Mail, Messages, Notes; source files from `tmp/Drag` in the container; with the app sandboxed and Release-signed. Record which accept the file URL and whether any shows the "data from other apps" prompt.
3. **Freeze latency** (Task 2). Time from hotkey to overlay visible with freeze off and on, one and two displays (`os_signpost` or NSLog timestamps).
4. **Scheme ownership** (Task 13). `/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -dump | grep -i -B2 -A8 tidyshot` after building Debug and Release; confirm which bundle `open tidyshot://restore-recently-closed` launches.
