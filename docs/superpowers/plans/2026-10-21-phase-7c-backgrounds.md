# TidyShot Phase 7c: Backgrounds, Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The editor's Background tool puts a capture on a gradient, solid colour, desktop picture or custom image, with padding, rounded corners, a shadow and an aspect ratio. A Capture-tab setting does the same to every window capture.

**Architecture:** Spec section 2.11 of `docs/superpowers/specs/2026-10-19-tidyshot-screenshot-design.md` is the full specification: types, defaults, strings, constants, the layout rule, the compositing steps and the tests. When this plan and 2.11 disagree, 2.11 wins.
- **Core.** The pure `BackgroundLayout` and the CoreGraphics `BackgroundCompositor` are shared by the editor export and the window-capture path. `BackgroundOptionsView` (SwiftUI) edits a `BackgroundStyle` in both places.
- **Fill images.** The desktop picture comes from 7b's `WallpaperSource`, and the one custom image lives in the container.
- **Probe.** The working CoreGraphics code is `docs/superpowers/research/phase-7c-probes/comp.swift`.

**Tech Stack:** Swift 6 language mode with default `MainActor` isolation and `NonisolatedNonsendingByDefault`, CoreGraphics, ImageIO, AppKit (`NSOpenPanel`, `NSPopover`, CALayer), SwiftUI, ScreenCaptureKit (through `WallpaperSource`), Swift Testing, XcodeGen 2.46.

Work happens on the branch `phase-7c-background`, cut from `phase-7b-text-icons` at ed867f2. The spec commit is cd8d6f7.

## Global Constraints

- **Earlier constraints still apply.**
  - Minimum macOS 26.0, Swift 6 with MainActor by default, App Sandbox, credentials only in the Keychain.
  - One save, upload and delete path in `AppCoordinator`.
  - The editor never writes files or the pasteboard itself.
  - KeyboardShortcuts is the only Swift package. No GPL code is read or copied.
- **No new entitlement and no new package.** The custom image is read through `NSOpenPanel`'s user-selected access.
- **Off the main actor.** Compositing and fill rendering run off the main actor: detached `.userInitiated` tasks or `@concurrent` functions. Nothing is rendered inside `draw(_:)`. The model stores no CGColor, NSColor or CGImage; it stores `RGBA` and enums only.
- **A capture is never lost.** A window capture whose background fails keeps the plain image. An editor export whose background fails fails like any export and leaves the editor dirty.
- **Exact strings, defaults, ranges, presets and limits** come from spec 2.11.
- **Tests** use Swift Testing, run with:
  ```bash
  xcodegen generate && xcodebuild test -project TidyShot.xcodeproj -scheme TidyShot -destination 'platform=macOS' -derivedDataPath .build 2>&1 | grep -E "Test run with|error:|TEST"
  ```
  The baseline is `Test run with 897 tests in 104 suites passed`. The Release build is `xcodebuild -project TidyShot.xcodeproj -scheme TidyShot -configuration Release -derivedDataPath .build-rel build`.
- **Commits.** Commit after every task with a conventional message and no attribution lines, and never push.

### Task 1: Background style, layout and compositor

**Files:**
- Create in `TidyShot/Background/`: `BackgroundStyle.swift`, `BackgroundPresets.swift`, `BackgroundLayout.swift`, `BackgroundCompositor.swift`.
- Create tests: `TidyShotTests/BackgroundStyleTests.swift`, `BackgroundPresetsTests.swift`, `BackgroundLayoutTests.swift`, `BackgroundCompositorTests.swift`.

**Produces** (all `nonisolated`, `Sendable`):
- `struct BackgroundStyle: Codable, Equatable` with `fill`, `padding`, `cornerRadius`, `shadow` and `aspect`, and the defaults from 2.11.
- `enum BackgroundFill: Codable, Equatable { case gradient(Int), solid(RGBA), desktopPicture, customImage }`.
- `enum BackgroundAspect: String, Codable, CaseIterable { case auto, square, fourThree, threeTwo, sixteenTen, sixteenNine }`, with `title` and `ratio: CGFloat?`.
- `struct GradientPreset: Equatable { let name: String; let first: RGBA; let second: RGBA }` and `enum BackgroundPresets { static let gradients: [GradientPreset] }`.
- `struct BackgroundLayout: Equatable { let canvasSize: CGSize; let contentRect: CGRect; let radius: CGFloat; static let maximumContentSide = 16_384; static func make(contentSize: CGSize, style: BackgroundStyle, scale: CGFloat) -> BackgroundLayout? }`.
- `enum BackgroundCompositor { static func compose(_ content: CGImage, style: BackgroundStyle, scale: CGFloat, fillImage: CGImage?) -> CGImage? }`.

**Steps:**
- [ ] Write the four test suites listed in 2.11.
  - `BackgroundStyleTests` covers the `AnnotationDocument` item only after Task 3. Leave that one test for Task 3.
- [ ] See them fail to compile.
- [ ] Implement the four files exactly as 2.11 gives the presets, the layout rule and the three compositing steps.
- [ ] Run the full suite.
- [ ] Commit: `feat: background styles, layout and compositing`.

### Task 2: Fill images, style editor and window captures

**Files:**
- Create in `TidyShot/Background/`: `BackgroundFillSource.swift`, `CustomBackgroundStore.swift`, `BackgroundOptionsView.swift`, `BackgroundStyleSheet.swift`.
- Create the test `TidyShotTests/CustomBackgroundStoreTests.swift`.
- Modify `TidyShot/Settings/AppSettings.swift`, `TidyShot/Settings/CaptureSettingsView.swift`, `TidyShot/App/AppCoordinator.swift` (`save(_:intent:)`) and `TidyShotTests/AppSettingsTests.swift`.

**Consumes:** Task 1's types, and 7b's `WallpaperSource`.

**Produces:**
- `CustomBackgroundStore`:
  - `init(directory: URL)`, with `static let shared` over the container's `Application Support/TidyShot/Backgrounds`;
  - `func store(contentsOf url: URL) throws`;
  - `func image() -> CGImage?`;
  - `var hasImage: Bool`;
  - `static let maximumSide = 6_000`.
- `BackgroundFillSource.fillImage(for fill: BackgroundFill, displayID: CGDirectDisplayID?) async -> CGImage?`. It returns nil for gradients and solid colours.
- `BackgroundOptionsView(style: Binding<BackgroundStyle>, onCommit: () -> Void)`.
- `AppSettings.windowBackground: Bool` and `AppSettings.backgroundStyle: BackgroundStyle`.

**Steps:**
- [ ] Write the `CustomBackgroundStoreTests` and the `AppSettingsTests` additions from 2.11, and see them fail.
- [ ] Implement the store and the fill source.
- [ ] Implement `BackgroundOptionsView`: the swatch grid, sliders, toggle and picker, with the strings in 2.11.
  - `Choose Image…` runs an `NSOpenPanel` and stores the file.
  - A decode failure posts `Not a usable image` through the app's notifier. Give the view a closure for this, so it does not reach into `AppCoordinator` directly.
- [ ] Implement `BackgroundStyleSheet`, and add the Capture tab rows.
- [ ] In `save(_:intent:)`, when the target is `.window` and `windowBackground` is on:
  - resolve the fill image for the window's display;
  - compose detached;
  - replace the image used for everything after (encode, clipboard, thumbnail, card, upload).

  Do it before the `copyOnly` branch, so `action=copy` gets it too. A nil result keeps the plain image and logs as 2.11 says.
- [ ] Run the full suite.
- [ ] Hand check in the Debug build: a window capture with each kind of fill. Note in the report if it could not be done.
- [ ] Commit: `feat: backgrounds for window captures`.

### Task 3: Editor Background tool

**Files:**
- Modify:
  - `TidyShot/Editor/Model/AnnotationDocument.swift`;
  - `TidyShot/Editor/Session/EditorModel.swift` (the `background` commit helper and `renderExport`);
  - `TidyShot/Editor/Window/EditorToolbar.swift`, `EditorWindowController.swift`, `BaseImageView.swift`, `CanvasView.swift`.
- Tests: add to `BackgroundStyleTests` (the old-document decode) and to an existing EditorModel export suite, or a new `EditorBackgroundExportTests.swift`.

**Consumes:** Tasks 1 and 2: the layout, the compositor, the fill source, `BackgroundOptionsView` and `AppSettings.backgroundStyle`.

**Steps:**
- [ ] Write the failing tests:
  - an old document without the key decodes with `background == nil`;
  - an export with a solid background has the layout's canvas size and the fill colour in a corner;
  - an export with a crop and a background frames the crop;
  - toggling the background and a style change are each one undo step.
- [ ] Implement the model change and the export:
  - flatten as now;
  - then resolve the fill image for the display under the editor window. The window controller passes the display id into the export, so the model stays AppKit-free.
  - then compose off the main actor;
  - a nil compose makes the export fail. The coordinator's existing failure paths then post `Not saved` or `Not uploaded`; add the body `The background could not be drawn.` where the export failure is reported.
- [ ] Toolbar item and popover, as 2.11 gives them. Re-measure the minimum width so no item overflows.
- [ ] Preview, as 2.11 gives it:
  - the background, shadow and mask layers in `BaseImageView`, placed by the transform;
  - the fill rendered off the main actor at most 2,048 px on its long side;
  - `CanvasView` clips its drawings to the rounded content rect;
  - fit covers the whole canvas;
  - the preview is hidden while the Crop tool is active.
- [ ] Run the full suite.
- [ ] Hand check: toggle, swatches, sliders (one undo step per drag), the aspect ratios, zoom to fit, crop then background, then export through Copy and Save As….
- [ ] Commit: `feat: editor Background tool`.

### Task 4: Checklist, README and spec close-out

**Files:** Create `docs/testing/phase-7c-manual-checklist.md`. Modify `README.md` (a "Backgrounds" section, the Capture tab row, and a Documents line) and spec 2.11 (Built notes).

**Steps:**
- [ ] Grep the finished code for every string 2.11 gives, and fix any drift.
- [ ] Write the checklist, covering:
  - each fill kind, in the editor and on window captures;
  - the desktop picture on a second display;
  - a custom image: large, portrait, and an undecodable file;
  - padding 0 and 160, radius 0 and 40, shadow on and off;
  - each aspect ratio with a landscape and a portrait capture;
  - the 16,384 px limit with a scrolling capture;
  - undo;
  - crop then background;
  - Copy, Save, Save As… and Upload;
  - `action=copy`;
  - a window capture with Include window shadow on;
  - no overflow in the editor toolbar at minimum width.
- [ ] Write the README text, and amend the spec with what was built differently.
- [ ] Run the full suite and the Release build once.
- [ ] Commit: `docs: Phase 7c checklist, README and spec close-out`.

## Test totals

| After | Total |
|---|---|
| Baseline | 897 tests in 104 suites |
| Task 1 | baseline plus 4 new suites |
| Task 2 | Task 1 plus `CustomBackgroundStoreTests` (1 new suite) and the settings tests |
| Task 3 | Task 2 plus the editor background tests |
| Task 4 | unchanged |
