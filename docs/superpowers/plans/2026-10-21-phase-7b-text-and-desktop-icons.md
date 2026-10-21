# TidyShot Phase 7b: Capture Text and Hide Desktop Icons, Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Capture Text (⌃⇧7) puts the text in a selected area on the clipboard, or a QR code's payload when there is one. Hide desktop icons covers the desktop's icons and widgets with the wallpaper, either while capturing or until turned off.

**Architecture:** Spec section 2.10 of `docs/superpowers/specs/2026-10-19-tidyshot-screenshot-design.md` is the full specification: behaviour, names, strings, constants, settings and tests. When this plan and 2.10 disagree, 2.10 wins; stop and ask if it is unclear.
- **Capture Text.** It reuses Capture Area's selection. A `@concurrent` `TextRecognizer` runs Vision. The pure `TextJoiner` and `TextCaptureOutcome` decide what goes on the clipboard and what the notification says.
- **Hide desktop icons.** `DesktopCoverController` shows one `DesktopCoverPanel` per display above Finder's icons and the widgets. Each panel shows that display's wallpaper window, captured with ScreenCaptureKit. The pure `DesktopCoverReasons` decides when the panels show, and the pure `WallpaperMatcher` decides which window is the wallpaper.
- **Probes.** The probes behind the constants are in `docs/superpowers/research/phase-7b-probes/`. `ocr.swift` and `cover.swift` show working Vision and cover code; start from them.

**Tech Stack:** Swift 6 language mode with default `MainActor` isolation and `NonisolatedNonsendingByDefault`, Vision (`RecognizeTextRequest`, `DetectBarcodesRequest`), ScreenCaptureKit (`SCScreenshotManager`, `SCContentFilter(desktopIndependentWindow:)`), AppKit (`NSPanel`, `NSPasteboard`, `NSWorkspace` notifications), SwiftUI Settings, KeyboardShortcuts, Swift Testing, XcodeGen 2.46.

Work happens on the branch `phase-7b-text-icons` from `main` at db2fa76, after the spec commit bb5b343.

## Global Constraints

- **Earlier constraints still apply.**
  - Minimum macOS 26.0, Swift 6 with MainActor by default, App Sandbox, credentials only in the Keychain.
  - One save, upload and delete path.
  - KeyboardShortcuts is the only Swift package.
  - No GPL code read or copied.
- **No new entitlement and no new package.** Vision and ScreenCaptureKit need nothing beyond the existing Screen Recording permission.
- **Off the main actor.** Vision requests and wallpaper captures run `@concurrent`. Panels, the controller, settings and the pasteboard are MainActor. Nothing blocks the main actor.
- **Capture Text has no capture side effects.** It never writes a file or a history record, shows a card, uploads, runs Clop, or reads the after-capture action. It changes the clipboard only when something was found.
- **Covers are not excluded from captures.** Captures show the wallpaper where the icons were. The cover panels never become key or main, and never activate TidyShot when clicked.
- **Exact strings, settings keys, constants, menu titles and shortcut defaults** come from spec 2.10.
- **Tests** use Swift Testing, run with:
  ```bash
  xcodegen generate && xcodebuild test -project TidyShot.xcodeproj -scheme TidyShot -destination 'platform=macOS' -derivedDataPath .build 2>&1 | grep -E "Test run with|error:|TEST"
  ```
  The baseline is `Test run with 840 tests in 98 suites passed`. Tim runs Release builds: `xcodebuild -project TidyShot.xcodeproj -scheme TidyShot -configuration Release -derivedDataPath .build-rel build`.
- **Commits.** Commit after every task with a conventional message and no attribution lines, and never push. The controller pushes and opens the PR after the whole-branch review.

### Task 1: Text recognition core

**Files:**
- Create in `TidyShot/Text/`: `TextScan.swift`, `TextJoiner.swift`, `TextCaptureOutcome.swift`, `TextRecognizer.swift`.
- Create tests: `TidyShotTests/TextJoinerTests.swift`, `TextCaptureOutcomeTests.swift`, `TextRecognizerTests.swift`.

**Produces** (all `nonisolated`, `Sendable`):
- `struct TextPiece: Equatable { var text: String; var box: CGRect }`. The box is normalised, origin at the bottom left.
- `enum CodeSymbology: Equatable { case qr, microQR, aztec, dataMatrix, pdf417 }`.
- `struct CodePiece: Equatable { var payload: String; var symbology: CodeSymbology; var box: CGRect }`.
- `struct TextScan: Equatable { var pieces: [TextPiece]; var codes: [CodePiece] }`.
- `enum TextJoiner { static func join(_ pieces: [TextPiece]) -> String }`.
- `struct TextCaptureOutcome: Equatable`:
  - `let clipboard: String?` (nil when nothing was found), `let title: String`, `let body: String`, `let openURL: URL?`;
  - `static func decide(_ scan: TextScan) -> TextCaptureOutcome`;
  - `static func preview(_ text: String) -> String` (first line, 80 characters, then `…`);
  - `static let previewLimit = 80`.
- `struct TextRecognizer { @concurrent func recognize(_ image: CGImage) async throws -> TextScan }`.

**Steps:**
- [ ] Write the tests listed under Tests in spec 2.10 for `TextJoiner`, `TextCaptureOutcome` and `TextRecognizer`.
  - Build `TextRecognizer`'s test image as `ocr.swift` does: CoreText text plus `CIFilter.qrCodeGenerator`, at 2x.
  - Give the recognizer suite `.timeLimit(.minutes(2))`.
  - Cover the join rule's two conditions at their boundaries: overlap exactly half, and a left edge exactly 0.01 left of the previous right edge.
- [ ] Run the tests and see them fail to compile.
- [ ] Implement the four files exactly as spec 2.10 states the request settings, symbologies, join rule, outcome rule and strings. The "no text" notification strings are the `nothing` outcome's `title` and `body`. `openURL` is set only for a single code payload that `URL(string:)` parses with scheme `http` or `https` and a non-empty host.
- [ ] Run the full suite. Expect the baseline plus this task's tests, in 3 new suites.
- [ ] Commit: `feat: text and QR recognition with Vision`.

### Task 2: Capture Text

**Files:** Modify:
- `TidyShot/App/Shortcuts.swift` (`captureText`, ⌃⇧7);
- `TidyShot/App/StatusMenuController.swift`;
- `TidyShot/Settings/ShortcutsSettingsView.swift`;
- `TidyShot/Output/Notifier.swift`;
- `TidyShot/App/AppCoordinator.swift`;
- `TidyShot/URLScheme/URLCommand.swift`, `URLCommandHandler.swift`;
- tests in `URLCommandTests.swift`, `URLCommandGateTests.swift`, `URLCommandHandlerTests.swift`.

**Consumes:** Task 1's types.

**Produces:**
- `AppCoordinator.captureText() async` and `captureText(at area: ScreenRect) async`. Both are added to `URLCommandTarget`.
- `URLCommand.Kind.captureText` (`"capture-text"`).
- `Notifier.notify(title:body:subtitle:openURL:)`. `openURL` defaults to nil, and a click opens it as `notifyUploaded`'s does.

**Steps:**
- [ ] Write the failing tests:
  - `capture-text` parses with and without a rect;
  - an `action` on it is ignored like any parameter the command does not take;
  - `capturesWithoutSelection` is true only with a rect, and the gate refuses that without `allowSilent`;
  - the handler routes both forms to the recorder and drops the command while a capture runs, as it does for the other captures.
- [ ] `URLCommand`:
  - `isCapture` currently also means "takes `action`". Split it: add `takesAction`, which is false for `captureText` and `restoreRecentlyClosed`, and use it in `parse`.
  - `captureText` is a capture (`isCapture` true, so the handler's busy check applies) and `takesArea` true.
- [ ] Shortcut, menu item and recorder, at the positions spec 2.10 gives. `registerShortcuts` calls `captureText()`.
- [ ] Coordinator.
  - **Selection under the lock.** `captureText()` takes the capture lock for the selection and the capture only:
    - `selector.select(mode: .area, content:freeze:)`, with Freeze screen as in `runSelection`;
    - an area gives the frozen crop (`frozenResult(for:display:)`), or else a live `.area` capture with `selector.overlayWindows()` excluded and `duringSelection: true`;
    - a window gives `capture(.window(window), duringSelection: true)`;
    - then `selector.dismiss()`.
  - **No previous area.** Do not call `areaResult`, which writes `lastAreaRect`. Factor the shared part out of it instead of copying it.
  - **`captureText(at:)`.** It captures the rect live with `cardWindows()` excluded, as `captureArea(at:intent:)` does, without writing `lastAreaRect`.
  - **After the lock is released**, both run `TextRecognizer().recognize(result.image)`, then apply the outcome:
    - when `clipboard` is non-nil: `NSPasteboard.general.clearContents()` and `setString`, `SoundPlayer.playShutter()` when Play sound is on, and the notification when Show notification is on;
    - when it is nil: `notifier.notifyError(body, title: title)`, always;
    - when Vision throws: `notifyError(error.localizedDescription, title: "Text not recognized")`.
- [ ] Run the full suite.
- [ ] Hand check in the Debug build: select a paragraph, then paste. Select a QR code on screen (generate one with `ocr.swift` or any QR site), then paste the link and click the notification.
- [ ] Commit: `feat: Capture Text copies the text or QR code in a selection`.

### Task 3: Desktop covers

**Files:**
- Create in `TidyShot/Desktop/`: `WallpaperMatcher.swift`, `DesktopCoverReasons.swift`, `WallpaperSource.swift`, `DesktopCoverPanel.swift`, `DesktopCoverController.swift`.
- Create tests: `TidyShotTests/WallpaperMatcherTests.swift`, `DesktopCoverReasonsTests.swift`.

**Produces:**
- Pure types (`nonisolated`, `Sendable`):
  - `struct WallpaperCandidate: Equatable { var windowID: CGWindowID; var bundleID: String?; var title: String?; var layer: Int; var frame: CGRect }`;
  - `enum WallpaperMatcher { static func match(_ candidates: [WallpaperCandidate], displayFrame: CGRect) -> CGWindowID? }`;
  - `struct DesktopCoverReasons: Equatable { enum Reason: Hashable, Sendable { case capture, persistent }; private(set) var active: Set<Reason>; mutating func insert(_:); mutating func remove(_:); var showsCovers: Bool }`.
- `WallpaperSource` (nonisolated, `Sendable`): `@concurrent func wallpapers() async -> [CGDirectDisplayID: CGImage]`. It:
  - reads `SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)`;
  - matches each display through `WallpaperMatcher`;
  - captures the matches concurrently, at the frame times the display's scale, without the pointer.

  A display that fails is left out of the result.
- `DesktopCoverController` (MainActor):
  - `init(source: WallpaperSource, reportFailure: @escaping @MainActor () -> Void)`;
  - `func show(for reason: DesktopCoverReasons.Reason) async`;
  - `func hide(for reason: DesktopCoverReasons.Reason)`;
  - `var isPersistent: Bool { get }`.

  `reportFailure` is called at most once per controller, when a display gets no wallpaper.

**Steps:**
- [ ] Write the `WallpaperMatcherTests` and `DesktopCoverReasonsTests` in spec 2.10 and see them fail.
- [ ] Implement the pure types.
- [ ] Implement `WallpaperSource`.
- [ ] Implement `DesktopCoverPanel`: the frame, level, behaviour and layer in spec 2.10. It takes mouse events and ignores them; `canBecomeKey` and `canBecomeMain` are false; the class is non-activating.
- [ ] Implement `DesktopCoverController`.
  - **`show`.** Add the reason. If the panels were not already showing, capture the wallpapers, build or update one panel per `NSScreen` that has an image, order them front, `CATransaction.flush()`, and sleep 50 ms. If they were already showing, return at once.
  - **`hide`.** Remove the reason, and order the panels out when `showsCovers` becomes false.
  - **Refresh while showing:**
    - observe `NSWorkspace.activeSpaceDidChangeNotification` and `NSWorkspace.didWakeNotification` (both on `NSWorkspace.shared.notificationCenter`), and `NSApplication.didChangeScreenParametersNotification`;
    - run a 10-minute repeating timer;
    - each refresh re-captures and swaps the layer contents, rebuilding panels for added or removed displays;
    - stop observing when hidden.
  - **Overlap.** A `show` that arrives while a capture is in flight shares it rather than starting a second.
- [ ] Run the full suite.
- [ ] Commit: `feat: desktop covers that hide icons and widgets behind the wallpaper`.

### Task 4: Hide desktop icons wiring, URL commands and docs

**Files:**
- Modify:
  - `TidyShot/Settings/AppSettings.swift` (`hideDesktopIconsWhileCapturing`, `desktopIconsHidden`);
  - `TidyShot/Settings/CaptureSettingsView.swift`;
  - `TidyShot/App/StatusMenuController.swift`;
  - `TidyShot/App/AppCoordinator.swift`;
  - `TidyShot/URLScheme/URLCommand.swift`, `URLCommandHandler.swift`;
  - tests in `AppSettingsTests.swift`, `URLCommandTests.swift`, `URLCommandGateTests.swift`, `URLCommandHandlerTests.swift`;
  - `README.md`, and spec 2.10 ("Built" notes).
- Create `docs/testing/phase-7b-manual-checklist.md`.

**Consumes:** Task 3's controller.

**Produces:**
- `AppCoordinator.setDesktopIconsHidden(_ hidden: Bool) async` and `toggleDesktopIconsHidden() async`. Both are added to `URLCommandTarget`.
- `URLCommand.Kind` cases `hideDesktopIcons`, `showDesktopIcons`, `toggleDesktopIcons`. Each has `isCapture` false and takes no parameters.

**Steps:**
- [ ] Write the failing tests:
  - the two settings' defaults and persistence;
  - the three commands parse, ignore parameters, and are not silent captures;
  - the gate runs them when URL commands are on and refuses them when off;
  - the handler routes them, and runs them even while a capture runs, as it does `restore-recently-closed`.
- [ ] Settings toggle and caption, and the menu item with its checkmark, as spec 2.10 gives them.
- [ ] Coordinator.
  - **Owner.** The coordinator owns one `DesktopCoverController`. Its `reportFailure` posts the spec's notification.
  - **Persistent covers.** `setDesktopIconsHidden` stores `desktopIconsHidden`, then calls `show(for: .persistent)` or `hide(for: .persistent)`. `start()` restores the stored state.
  - **During captures.** `withCaptureLock` gains a `coversDesktop: Bool` parameter.
    - It is true for Capture Area and Window (`runSelection`), Capture Fullscreen, All-in-One, Capture Previous Area, `captureArea(at:intent:)` and Self-Timer.
    - It is false for Capture Scrolling and Capture Text.
    - When it is true and `hideDesktopIconsWhileCapturing` is on, the lock calls `await covers.show(for: .capture)` before the body (before `loadContent`), and `covers.hide(for: .capture)` after it on every path.
- [ ] Run the full suite. Build Release once.
- [ ] Write `docs/testing/phase-7b-manual-checklist.md`, covering:
  - Capture Text: paragraphs, two columns, a non-Latin script, a QR with a caption, two QR codes, a non-URL payload, an empty area, Freeze screen on, a window click, the URL command with and without a rect, a 24 s cold first run after a restart;
  - covers during each capture kind, with Freeze screen on and off, on two displays if available;
  - widgets hidden;
  - the persistent toggle across a Space switch, a wallpaper change, sleep and wake, and a relaunch;
  - clicks on the covered desktop doing nothing;
  - the three URL commands;
  - the failure notification (hard to force; note how it was checked).
- [ ] Update the README:
  - "Capture Text" and "Hide desktop icons" sections;
  - the URL scheme table;
  - the Shortcuts list;
  - a Documents line for the checklist.
- [ ] Add spec 2.10 "Built" notes for anything built differently.
- [ ] Commit: `feat: hide desktop icons while capturing or until turned off`, then `docs: Phase 7b checklist, README and spec close-out`.

## Test totals

| After | Total |
|---|---|
| Baseline | 840 tests in 98 suites |
| Task 1 | baseline plus Task 1's tests (3 new suites) |
| Task 2 | Task 1 plus the URL command tests |
| Task 3 | Task 2 plus Task 3's tests (2 new suites) |
| Task 4 | Task 3 plus the settings and URL command tests |
