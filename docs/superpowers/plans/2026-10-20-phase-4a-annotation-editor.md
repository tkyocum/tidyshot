# TidyShot Phase 4a: Annotation Editor, Redaction First, Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the crosshair and the loupe cross readable on any background, then add an annotation editor that opens from the Quick Access overlay and from Recent Captures, with Select, Redact, Pixelate, Blur, Rectangle and Arrow, undo, a colour palette, line widths and zoom, and four actions routed through `AppCoordinator`: Save over, Save Copy, Copy, and Upload (same key) or Upload as New.

**Architecture:** AppKit owns the editor window, toolbar, canvas and events; SwiftUI appears only inside two popovers. A nonisolated, Codable `AnnotationDocument` in image pixels (top-left origin) is changed only through `EditorModel.commit`, which records whole-document snapshots in an `UndoManager`. Effects (redact, blur, pixelate) render as native-pixel tiles from one `RedactionRenderer` actor that owns the app's Metal `CIContext`, cached by `RedactionTileCache` under keys that include the effects beneath; drawings render through one nonisolated `AnnotationDrawing` used by both the canvas and the detached `EditorFlattener`, so the export equals the preview. The editor never writes files, the pasteboard or uploads: `AppCoordinator` stays the one save, upload and delete path, and every branch it takes comes from a tested helper in `Editor/Persistence/`.

**Tech Stack:** Swift 6 language mode with default `MainActor` isolation and `NonisolatedNonsendingByDefault`, AppKit (`NSWindow`, `NSToolbar` with `NSToolbarItemGroup` and `NSMenuToolbarItem`, `NSPopover`, layer-backed `NSView`, `UndoManager`, `NSUserInterfaceValidations`), SwiftUI (`NSHostingController` in popovers), Core Image (Metal-backed `CIContext`, `CIImage.applyingGaussianBlur`, `samplingNearest`), Core Graphics (bitmap `CGContext`), ImageIO, Swift Testing, XcodeGen 2.46.

Spec: `docs/superpowers/specs/2026-10-19-tidyshot-screenshot-design.md`, section 2.6 (all of it), the 2.5 "Loupe crosshair" paragraph, and section 6 (Phase 4). Section 2.6 is the authority for behaviour, names and exact strings; when this plan and 2.6 disagree, stop and ask.

Builds on Phase 3.1 (`docs/superpowers/plans/2026-10-19-phase-3-1-feedback.md`). Work happens on the branch `phase-4-annotation`, which holds `main` (429127a), the spec commits ab7956a and f4541da, and this plan. Confirm:

```bash
git switch phase-4-annotation
git merge-base --is-ancestor f4541da HEAD && echo SPEC_PRESENT
```
Expected: `Already on 'phase-4-annotation'` (or `Switched to branch 'phase-4-annotation'`) then `SPEC_PRESENT`.

## How code is specified in this plan

Each task gives the exact Swift interfaces it produces, complete Swift Testing test code, and complete code for pure helpers and algorithms (model, geometry, Core Image graphs, flattening, undo, decision tables). AppKit views, controllers and toolbar wiring are specified by structure, exact names, behaviour and hand checks, and the implementer writes that code. The tests and the interfaces are the contract: a reviewer rejects a task whose names, signatures, strings or test assertions differ from this plan or from spec 2.6.

## Global Constraints

- Every Phase 0 to 3.1 constraint still applies: minimum macOS `26.0`, Xcode 27.1 with the macOS 27.0 SDK, App Sandbox on with no new entitlements, Swift 6 language mode with `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` and `SWIFT_APPROACHABLE_CONCURRENCY = YES`, `KeyboardShortcuts` as the only package, credentials only in the Keychain, files in the save folder only through the security-scoped bookmark, thumbnails and upload-only files in the container next to `history.json`, one token engine for file names and object keys, keys named when the upload starts, HEAD before PUT for template keys, and no GPL-licensed code read or copied.
- New code lives in `TidyShot/Editor/` under `Model/`, `Geometry/`, `Rendering/`, `Session/`, `Tools/`, `Window/` and `Persistence/`, plus `TidyShot/Output/ScaledImage.swift`. New tests live in `TidyShotTests/` beside the existing ones. XcodeGen's recursive source paths pick new folders up; run `xcodegen generate` after adding files.
- One save path, one upload path, one delete path. The editor never writes files, never touches the pasteboard and never enqueues uploads; it calls `EditorActions` closures that `AppCoordinator` provides. The coordinator's editor methods live in `AppCoordinator.swift` under `// MARK: Editor`, because they call its `private` members.
- `ScaledImage` (`nonisolated struct ScaledImage: Sendable { let image: CGImage; let scale: CGFloat }`) is the only image type that crosses between the editor and the coordinator.
- Model geometry is in image pixels with a top-left origin (CGImage row 0). Line widths, blur radii and pixel blocks are stored in image pixels (points chosen in the UI times the capture scale at creation). The model never stores CGColor, CGPath, NSColor or CIFilter.
- Concurrency: any `nonisolated async` function that must run off the main actor is marked `@concurrent`. `RedactionRenderer` is an actor and owns the only `CIContext`; CIFilters are built inside each call. No GPU or Core Image work runs inside `draw(_:)`. Tests never block the main actor with a semaphore; fakes wait on an async gate.
- Exact user-visible strings (from spec 2.6), used verbatim:
  - Notification titles: `Not saved`, `Not uploaded`, `Could not open the capture`; bodies `Image copied`, `Upload failed. The link still shows the earlier image.`, `Replaced. Copies opened before now may stay cached for a while.` (posted once per app session, on the first successful same-key replace).
  - Window subtitles: `Uploading…`, `Deleting…`, `The uploaded copy still shows the original. Upload to replace it.`, `This capture was deleted. Copy and Save Copy still work.`
  - Upload notices: `The destination changed, so this uploads as a new link.`, `Another capture shares this link, so this uploads as a new link.`, `The earlier upload stays in the bucket.`
  - Close sheet: message `Do you want to save the changes made to “<title>”?`, informative text `Your changes will be lost if you don’t save them.`, buttons Save (or Save Copy… when Save is unavailable), Cancel, Don’t Save.
- Shortcuts: the 4a `EditorShortcut` table in spec 2.6 (⌘S, ⇧⌘S, ⌘C, ⇧⌘C, ⌘U, ⌥⌘U, ⌘Z, ⇧⌘Z, ⌘W, ⌘0, ⌘1, ⌘=, ⌘-, ⌘A); tool letters V, D, X, B, R, A; digits 1 to 6 for line widths 2, 3, 4, 6, 8, 12 pt. ⌘X has no row.
- The editor activates the app (`activate(ignoringOtherApps:)`, then `makeKeyAndOrderFront`, then `orderFrontRegardless` if still inactive). Menu and overlay actions that open it run after menu tracking ends (`afterMenusClose`).
- Tests use Swift Testing, run with:
  ```bash
  xcodegen generate && xcodebuild test -project TidyShot.xcodeproj -scheme TidyShot -destination 'platform=macOS' -derivedDataPath .build 2>&1 | grep -E "Test run with|error:|TEST"
  ```
  Baseline `Test run with 191 tests in 28 suites passed`; the totals after each task are in the table below.
- Commit after every task with a conventional commit message and no attribution lines. Never include a Claude Code session URL in a commit or PR. This plan never pushes or opens a PR: the last task stops after its commit, and the controller pushes and opens the PR after the whole-branch review.

## Test totals

| After | New tests | New suites | Total |
|---|---|---|---|
| Baseline | | | 191 tests in 28 suites |
| Task 1 | 1 | 0 | 192 tests in 28 suites |
| Task 2 | 20 | 3 | 212 tests in 31 suites |
| Task 3 | 19 | 4 | 231 tests in 35 suites |
| Task 4 | 24 | 4 | 255 tests in 39 suites |
| Task 5 | 10 | 1 | 265 tests in 40 suites |
| Task 6 | 8 | 1 | 273 tests in 41 suites |
| Task 7 | 11 | 1 | 284 tests in 42 suites |
| Task 8 | 20 | 2 | 304 tests in 44 suites |
| Task 9 | 12 | 1 | 316 tests in 45 suites |
| Task 10 | 0 | 0 | 316 tests in 45 suites |
| Task 11 | 2 | 0 | 318 tests in 45 suites |
| Task 12 | 7 | 2 | 325 tests in 47 suites |
| Task 13 | 23 | 2 | 348 tests in 49 suites |
| Task 14 | 22 | 0 | 370 tests in 49 suites |
| Task 15 | 18 | 1 | 388 tests in 50 suites |
| Task 16 | 11 | 1 | 399 tests in 51 suites |
| Task 17 | 0 | 0 | 399 tests in 51 suites |

The totals come from each task's declared tests. Task 17 checks them against a real run and corrects any row that differs.

---

### Task 1: Two-tone crosshair and loupe cross

**Files:**
- Modify: `TidyShot/Selection/Luminance.swift` (the `CrosshairStyle` doc comment and enum, lines 40-57)
- Modify: `TidyShot/Selection/SelectionView.swift` (`stroke(_:)` and its doc comment, lines 176-193; the loupe cross in `drawLoupe(at:)`, lines 261-268)
- Test: `TidyShotTests/LuminanceTests.swift` (one new test after `crosshairStyleThresholds`, which ends at line 70)

**Interfaces:**
- Consumes (existing code, no earlier task):
  - `nonisolated enum CrosshairStyle: Equatable, Sendable { case dark, light, outlined; init(luminance: Double?) }` (Luminance.swift:41-57).
  - `Luminance.sampleSide: CGFloat = 24` (Luminance.swift:7).
  - In `SelectionView` (all `private`): `var crosshairStyle: CrosshairStyle` (SelectionView.swift:27), `func stroke(_ path: NSBezierPath)` (179), `func style(at point: CGPoint?) -> CrosshairStyle` (197), `func drawLoupe(at point: CGPoint)` (225), which returns at line 226 while `snapshot` is nil.
- Produces (members of `CrosshairStyle`, nonisolated):
  - `var lineWhite: CGFloat { get }`: 0 for `.dark`, 1 for `.light` and `.outlined`.
  - `var haloWhite: CGFloat { get }`: 1 for `.dark`, 0 for `.light` and `.outlined`.
  - `static let lineAlpha: CGFloat = 1`
  - `static let haloAlpha: CGFloat = 0.7`
  - `SelectionView.stroke(_:)` draws every stroke two-tone: the halo at width `1 + 2 / backingScale` in `NSColor(white: haloWhite, alpha: CrosshairStyle.haloAlpha)`, then the line at width 1 in `NSColor(white: lineWhite, alpha: CrosshairStyle.lineAlpha)`. `drawLoupe(at:)` strokes its cross through `stroke(_:)`. No later task uses these.

- [ ] **Step 1: Write the failing test**

In `TidyShotTests/LuminanceTests.swift`, add after `crosshairStyleThresholds()` (after line 70, inside `struct LuminanceTests`):
```swift
    /// Each style is an opaque line over a halo in the opposite colour; `.outlined` has the
    /// colours of `.light`.
    @Test func crosshairStyleColours() {
        #expect(CrosshairStyle.dark.lineWhite == 0)
        #expect(CrosshairStyle.dark.haloWhite == 1)
        #expect(CrosshairStyle.light.lineWhite == 1)
        #expect(CrosshairStyle.light.haloWhite == 0)
        #expect(CrosshairStyle.outlined.lineWhite == 1)
        #expect(CrosshairStyle.outlined.haloWhite == 0)
        #expect(CrosshairStyle.lineAlpha == 1)
        #expect(CrosshairStyle.haloAlpha == 0.7)
    }
```

- [ ] **Step 2: Run the tests to verify they fail**

Run:
```bash
xcodegen generate && xcodebuild test -project TidyShot.xcodeproj -scheme TidyShot -destination 'platform=macOS' -derivedDataPath .build 2>&1 | grep -E "Test run with|error:|TEST"
```
Expected: compile errors, among them `value of type 'CrosshairStyle' has no member 'lineWhite'` and `type 'CrosshairStyle' has no member 'lineAlpha'`, then `** TEST FAILED **`. No `Test run with` line.

- [ ] **Step 3: Add the colour table to `CrosshairStyle`**

In `TidyShot/Selection/Luminance.swift`, replace lines 40-57 (from `/// The colour of the crosshair and the selection border` to the enum's closing brace) with:
```swift
/// The colours of the crosshair, the selection borders and the loupe's cross for what is under the
/// cursor. Each is drawn two-tone: an opaque 1 pt line over a halo one device pixel wider on each
/// side, in the opposite colour at 0.7 alpha, so it reads on any background.
nonisolated enum CrosshairStyle: Equatable, Sendable {
    /// Black line, white halo, on a light background.
    case dark
    /// White line, black halo, on a dark background.
    case light
    /// White line, black halo (the colours of `.light`), when no luminance is available: before the
    /// snapshot arrives, and when the sampled square lies wholly outside it.
    case outlined

    /// The line's alpha.
    static let lineAlpha: CGFloat = 1
    /// The halo's alpha.
    static let haloAlpha: CGFloat = 0.7

    init(luminance: Double?) {
        guard let luminance else {
            self = .outlined
            return
        }
        self = luminance > 0.5 ? .dark : .light
    }

    /// The line's grey level for `NSColor(white:alpha:)`: 0 is black, 1 is white.
    var lineWhite: CGFloat {
        switch self {
        case .dark: 0
        case .light, .outlined: 1
        }
    }

    /// The halo's grey level, the opposite of `lineWhite`.
    var haloWhite: CGFloat {
        switch self {
        case .dark: 1
        case .light, .outlined: 0
        }
    }
}
```

- [ ] **Step 4: Stroke two-tone, and stroke the loupe cross the same way**

In `TidyShot/Selection/SelectionView.swift`:

Replace lines 176-193:
```swift
    /// Strokes a 1 pt line in the current `crosshairStyle`: black on light backgrounds, white on
    /// dark ones, and before the snapshot arrives white over a line one pixel wider on each side
    /// in black.
    private func stroke(_ path: NSBezierPath) {
        switch crosshairStyle {
        case .dark:
            NSColor.black.withAlphaComponent(0.8).setStroke()
        case .light:
            NSColor.white.withAlphaComponent(0.8).setStroke()
        case .outlined:
            NSColor.black.withAlphaComponent(0.8).setStroke()
            path.lineWidth = 1 + 2 / (window?.backingScaleFactor ?? 2)
            path.stroke()
            NSColor.white.setStroke()
        }
        path.lineWidth = 1
        path.stroke()
    }
```
with:
```swift
    /// Strokes `path` two-tone in the current `crosshairStyle`. Used for the crosshair, the drag
    /// and completed rectangle borders, and the loupe's cross. First a halo one device pixel wider
    /// on each side in the halo colour at `CrosshairStyle.haloAlpha`, then the 1 pt line in the line
    /// colour at `CrosshairStyle.lineAlpha`: black over white on light backgrounds, white over
    /// black on dark ones and before the snapshot arrives. Each tone is one stroke of the whole
    /// path, so where lines cross the halo is not painted twice.
    private func stroke(_ path: NSBezierPath) {
        NSColor(white: crosshairStyle.haloWhite, alpha: CrosshairStyle.haloAlpha).setStroke()
        path.lineWidth = 1 + 2 / (window?.backingScaleFactor ?? 2)
        path.stroke()
        NSColor(white: crosshairStyle.lineWhite, alpha: CrosshairStyle.lineAlpha).setStroke()
        path.lineWidth = 1
        path.stroke()
    }
```

Replace lines 261-268 in `drawLoupe(at:)`:
```swift
        NSColor.white.withAlphaComponent(0.9).setStroke()
        let cross = NSBezierPath()
        cross.lineWidth = 1
        cross.move(to: CGPoint(x: destination.minX, y: destination.midY + 0.5))
        cross.line(to: CGPoint(x: destination.maxX, y: destination.midY + 0.5))
        cross.move(to: CGPoint(x: destination.midX + 0.5, y: destination.minY))
        cross.line(to: CGPoint(x: destination.midX + 0.5, y: destination.maxY))
        cross.stroke()
```
with:
```swift
        let cross = NSBezierPath()
        cross.move(to: CGPoint(x: destination.minX, y: destination.midY + 0.5))
        cross.line(to: CGPoint(x: destination.maxX, y: destination.midY + 0.5))
        cross.move(to: CGPoint(x: destination.midX + 0.5, y: destination.minY))
        cross.line(to: CGPoint(x: destination.midX + 0.5, y: destination.maxY))
        stroke(cross)
```

Leave the 2 pt white ring (lines 270-273) as it is. It is still drawn after the cross, so it covers the cross's ends. `style(at:)` already samples a 24 pt square (`Luminance.sampleSide`) that encloses the loupe's 16 pt region, so the loupe needs no sample of its own. The window highlight border (accent colour, 2 pt) does not go through `stroke(_:)` and is unchanged.

- [ ] **Step 5: Run the suite**

Run:
```bash
xcodegen generate && xcodebuild test -project TidyShot.xcodeproj -scheme TidyShot -destination 'platform=macOS' -derivedDataPath .build 2>&1 | grep -E "Test run with|error:|TEST"
```
Expected: no `error:` lines, `** TEST SUCCEEDED **`, and `Test run with 192 tests in 28 suites passed`.

Then:
```bash
grep -nE 'withAlphaComponent\(0\.(8|9)\)' TidyShot/Selection/SelectionView.swift; grep -c 'stroke(cross)' TidyShot/Selection/SelectionView.swift
```
Expected: no lines from the first grep, then `1`.

- [ ] **Step 6: Check by hand**

Run:
```bash
xcodebuild -project TidyShot.xcodeproj -scheme TidyShot -configuration Debug -derivedDataPath .build build -quiet && open .build/Build/Products/Debug/TidyShot.app
```
Open a white page (a new TextEdit document) beside a dark window (Terminal), press `⌃⇧4` and move the cursor between them. Expected:
- For the first moment, before the snapshot arrives, the crosshair is white with a thin black halo and there is no loupe.
- Over the white window the crosshair and the loupe cross are black with a white halo.
- Over the dark window they are white with a black halo, and moving between the windows switches them.
- Drag a rectangle that ends over the white window: its border is black with a white halo. Drag one that ends over the dark window: its border is white with a black halo.
- The loupe's ring stays white in both cases.

Escape cancels.

- [ ] **Step 7: Commit**

```bash
git add TidyShot/Selection/Luminance.swift TidyShot/Selection/SelectionView.swift TidyShotTests/LuminanceTests.swift
git commit -m "fix: two-tone crosshair and loupe cross"
```

---

### Task 2: Editor value model, tool table, palette and ScaledImage (TDD)

**Files:**
- Create: `TidyShot/Output/ScaledImage.swift`
- Create: `TidyShot/Editor/Model/RGBA.swift`
- Create: `TidyShot/Editor/Model/Annotation.swift` (`ShapeBox`, `Segment`, `Region`, `Annotation`)
- Create: `TidyShot/Editor/Model/AnnotationDocument.swift`
- Create: `TidyShot/Editor/Model/EditorTool.swift`
- Create: `TidyShot/Editor/Model/EditorPalette.swift` (`EditorPalette`, `RedactionDefaults`, `EditorDefaults`)
- Test: `TidyShotTests/AnnotationDocumentTests.swift`, `TidyShotTests/EditorToolTests.swift`, `TidyShotTests/EditorPaletteTests.swift`
- Modify: none.

**Interfaces:**
- Consumes: `struct CaptureResult { let image: CGImage; let scale: CGFloat; let target: CaptureTarget }` (TidyShot/Capture/CaptureTarget.swift:15-20). It is not marked `nonisolated`, so under `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` it is MainActor, and so is the `scaled` extension below.
- Produces (every type is `nonisolated`, so actors and detached tasks can use it; the model files import only CoreGraphics and Foundation):
  - `nonisolated struct ScaledImage: Sendable { let image: CGImage; let scale: CGFloat }` and `extension CaptureResult { var scaled: ScaledImage }`.
  - `nonisolated struct RGBA: Codable, Equatable, Sendable { var red, green, blue, alpha: Double; init(red: Double, green: Double, blue: Double, alpha: Double = 1); var cgColor: CGColor }`. Components are sRGB from 0 to 1. The JSON keys are `red`, `green`, `blue` and `alpha`. `cgColor` is made in sRGB on each call.
  - `nonisolated struct ShapeBox: Codable, Equatable, Sendable { let id: UUID; var rect: CGRect; var color: RGBA; var lineWidth: CGFloat }`, with the memberwise `init(id:rect:color:lineWidth:)`.
  - `nonisolated struct Segment: Codable, Equatable, Sendable { let id: UUID; var from: CGPoint; var to: CGPoint; var color: RGBA; var lineWidth: CGFloat }`, with `init(id:from:to:color:lineWidth:)`.
  - `nonisolated struct Region: Codable, Equatable, Sendable { let id: UUID; var rect: CGRect }`, with `init(id:rect:)`.
  - `nonisolated enum Annotation: Identifiable, Codable, Equatable, Sendable { case rectangle(ShapeBox), arrow(Segment), redact(Region, fill: RGBA), blur(Region, radius: CGFloat), pixelate(Region, block: CGFloat) }` with:
    - `var id: UUID`;
    - `var isEffect: Bool`, true for redact, blur and pixelate;
    - `var effectRect: CGRect?`, the region of an effect and nil for a drawing;
    - `var title: String`: `Rectangle`, `Arrow`, `Redact`, `Blur` or `Pixelate`, the title of the tool that makes it;
    - `func moved(by delta: CGVector) -> Annotation`, which shifts a rect's origin or both ends of a segment;
    - `func withColor(_ color: RGBA) -> Annotation`, which sets a shape's stroke or a redaction's fill, and returns blur and pixelate unchanged;
    - `func withLineWidth(_ width: CGFloat) -> Annotation`, for shapes only;
    - `func withEffectParameter(_ value: CGFloat) -> Annotation`, which sets a blur's radius or a pixelate's block, and returns everything else unchanged.
    All values are image pixels, top-left origin.
  - `nonisolated struct AnnotationDocument: Codable, Equatable, Sendable { var annotations: [Annotation] = [] }` with `init()`, `init(annotations:)`, `var effects: [Annotation]`, `var drawings: [Annotation]` (both in creation order), `func annotation(id: UUID) -> Annotation?`, `func appending(_ annotation: Annotation) -> AnnotationDocument`, `func removing(id: UUID) -> AnnotationDocument`, `func replacing(_ annotation: Annotation) -> AnnotationDocument` (keeps the position; unchanged for an unknown id) and `func moving(id: UUID, by delta: CGVector) -> AnnotationDocument` (unchanged for an unknown id).
  - `nonisolated enum EditorTool: String, CaseIterable, Sendable { case select, redact, pixelate, blur, rectangle, arrow }` with:
    - `var letter: Character`: V, D, X, B, R, A;
    - `var title: String`: Select, Redact, Pixelate, Blur, Rectangle, Arrow;
    - `var symbolName: String`;
    - `var tooltip: String`: `"<title> (<letter>)"`, for example `Redact (D)`;
    - `var isEffect: Bool`;
    - `static var toolbarOrder: [EditorTool]`: Select, Redact, Pixelate, Blur, Rectangle, Arrow;
    - `static func tool(forKey key: Character) -> EditorTool?`, which ignores case.
  - `nonisolated enum EditorPalette { static let swatches: [RGBA]; static let defaultStroke: RGBA; static let defaultRedact: RGBA; static let lineWidthsPoints: [CGFloat] }`. There are ten swatches: black, red, orange, yellow, green, teal, blue, purple, pink, white. The stroke default is red and the redact default is black. The widths are `[2, 3, 4, 6, 8, 12]`.
  - `nonisolated enum RedactionDefaults { static let blurRangePoints: ClosedRange<CGFloat> = 4...24; static let blockRangePoints: ClosedRange<CGFloat> = 6...32; static func blurRadius(points: CGFloat, scale: CGFloat) -> CGFloat; static func block(points: CGFloat, scale: CGFloat, region: CGRect) -> CGFloat }`. Both functions return image pixels.
    - `blurRadius` is `max(points, 4) * scale`.
    - `block` is `max(points, 6) * scale` rounded to whole pixels, then capped at the region's shorter side rounded down, and never below 1.
  - `nonisolated struct EditorDefaults: Equatable, Sendable { var strokeColor: RGBA; var redactColor: RGBA; var lineWidthPoints: CGFloat; var blurRadiusPoints: CGFloat; var blockPoints: CGFloat; static let standard: EditorDefaults }`. The memberwise init takes the fields in that order. `standard` is red, black, 4, 8 and 10.

`Segment` is a new top-level name. `TemplateExpander` has a nested `enum Segment` (TidyShot/Output/TemplateExpander.swift:60). Inside `TemplateExpander` the nested type wins, and no other file names it, so the two do not clash.

- [ ] **Step 1: Write the failing tests**

`TidyShotTests/AnnotationDocumentTests.swift`:
```swift
import CoreGraphics
import Foundation
import Testing
@testable import TidyShot

struct AnnotationDocumentTests {
    let boxID = UUID()
    let redactID = UUID()
    let arrowID = UUID()
    let blurID = UUID()
    let pixelateID = UUID()
    let red = EditorPalette.defaultStroke
    let black = EditorPalette.defaultRedact
    let blue = RGBA(red: 0, green: 0, blue: 1)

    // One fixture per kind, each with a fixed id, so a test can build the value it expects.
    func box(rect: CGRect = CGRect(x: 10, y: 20, width: 30, height: 40), color: RGBA? = nil,
             lineWidth: CGFloat = 8) -> Annotation {
        .rectangle(ShapeBox(id: boxID, rect: rect, color: color ?? red, lineWidth: lineWidth))
    }

    func arrow(from: CGPoint = CGPoint(x: 5, y: 5), to: CGPoint = CGPoint(x: 60, y: 45), color: RGBA? = nil,
               lineWidth: CGFloat = 8) -> Annotation {
        .arrow(Segment(id: arrowID, from: from, to: to, color: color ?? red, lineWidth: lineWidth))
    }

    func redact(rect: CGRect = CGRect(x: 0, y: 0, width: 50, height: 10), fill: RGBA? = nil) -> Annotation {
        .redact(Region(id: redactID, rect: rect), fill: fill ?? black)
    }

    func blur(rect: CGRect = CGRect(x: 20, y: 30, width: 40, height: 20), radius: CGFloat = 16) -> Annotation {
        .blur(Region(id: blurID, rect: rect), radius: radius)
    }

    func pixelate(rect: CGRect = CGRect(x: 40, y: 0, width: 24, height: 24), block: CGFloat = 12) -> Annotation {
        .pixelate(Region(id: pixelateID, rect: rect), block: block)
    }

    /// Drawings and effects interleaved, in creation order.
    var mixed: AnnotationDocument {
        AnnotationDocument(annotations: [box(), redact(), arrow(), blur(), pixelate()])
    }

    @Test func appendKeepsCreationOrder() {
        let empty = AnnotationDocument()
        let one = empty.appending(box())
        let two = one.appending(redact())
        #expect(empty.annotations.isEmpty)
        #expect(one.annotations == [box()])
        #expect(two.annotations.map(\.id) == [boxID, redactID])
    }

    @Test func effectsAndDrawingsSplitInOrder() {
        #expect(mixed.effects == [redact(), blur(), pixelate()])
        #expect(mixed.drawings == [box(), arrow()])
        #expect(mixed.annotations.map(\.isEffect) == [false, true, false, true, true])
    }

    @Test func removingAndReplacingById() {
        let removed = mixed.removing(id: arrowID)
        #expect(removed.annotations == [box(), redact(), blur(), pixelate()])
        #expect(removed.annotation(id: arrowID) == nil)
        #expect(mixed.annotation(id: blurID) == blur())
        #expect(mixed.removing(id: UUID()) == mixed)

        let replaced = mixed.replacing(box(color: blue))
        #expect(replaced.annotations == [box(color: blue), redact(), arrow(), blur(), pixelate()])

        let stranger = Annotation.redact(Region(id: UUID(), rect: .zero), fill: black)
        #expect(mixed.replacing(stranger) == mixed)
    }

    @Test func movingShiftsRectAndSegmentEndpoints() {
        let delta = CGVector(dx: 3, dy: -2)
        let moved = mixed.moving(id: boxID, by: delta).moving(id: arrowID, by: delta).moving(id: blurID, by: delta)
        #expect(moved.annotations == [
            box(rect: CGRect(x: 13, y: 18, width: 30, height: 40)),
            redact(),
            arrow(from: CGPoint(x: 8, y: 3), to: CGPoint(x: 63, y: 43)),
            blur(rect: CGRect(x: 23, y: 28, width: 40, height: 20)),
            pixelate(),
        ])
        #expect(redact().moved(by: delta) == redact(rect: CGRect(x: 3, y: -2, width: 50, height: 10)))
        #expect(pixelate().moved(by: delta) == pixelate(rect: CGRect(x: 43, y: -2, width: 24, height: 24)))
        #expect(mixed.moving(id: UUID(), by: delta) == mixed)
    }

    @Test func jsonRoundTrip() throws {
        let data = try JSONEncoder().encode(mixed)
        let decoded = try JSONDecoder().decode(AnnotationDocument.self, from: data)
        #expect(decoded == mixed)
        #expect(decoded.effects.map(\.id) == [redactID, blurID, pixelateID])
    }

    @Test func equalityIsValueBased() {
        #expect(mixed == AnnotationDocument(annotations: [box(), redact(), arrow(), blur(), pixelate()]))
        #expect(mixed != mixed.replacing(box(color: blue)))
        #expect(mixed != mixed.replacing(blur(radius: 17)))
        // The same values under another id are another annotation.
        let twin = Annotation.redact(Region(id: UUID(), rect: CGRect(x: 0, y: 0, width: 50, height: 10)), fill: black)
        #expect(twin != redact())
        // Creation order is drawing order, so it counts.
        #expect(AnnotationDocument(annotations: [box(), arrow()]) != AnnotationDocument(annotations: [arrow(), box()]))
    }

    /// Colour, line width and effect parameter each change only the kinds they mean something for.
    @Test func editsTouchOnlyTheKindsTheyApplyTo() {
        #expect(box().withColor(blue) == box(color: blue))
        #expect(arrow().withColor(blue) == arrow(color: blue))
        #expect(redact().withColor(blue) == redact(fill: blue))
        #expect(blur().withColor(blue) == blur())
        #expect(pixelate().withColor(blue) == pixelate())

        #expect(box().withLineWidth(24) == box(lineWidth: 24))
        #expect(arrow().withLineWidth(24) == arrow(lineWidth: 24))
        #expect(redact().withLineWidth(24) == redact())
        #expect(blur().withLineWidth(24) == blur())

        #expect(blur().withEffectParameter(30) == blur(radius: 30))
        #expect(pixelate().withEffectParameter(30) == pixelate(block: 30))
        #expect(redact().withEffectParameter(30) == redact())
        #expect(box().withEffectParameter(30) == box())

        #expect(box().effectRect == nil)
        #expect(arrow().effectRect == nil)
        #expect(redact().effectRect == CGRect(x: 0, y: 0, width: 50, height: 10))
        #expect(pixelate().effectRect == CGRect(x: 40, y: 0, width: 24, height: 24))
        #expect(mixed.annotations.map(\.title) == ["Rectangle", "Redact", "Arrow", "Blur", "Pixelate"])
        #expect(mixed.annotations.map(\.id) == [boxID, redactID, arrowID, blurID, pixelateID])
    }
}
```

`TidyShotTests/EditorToolTests.swift`. 4b adds tools to `EditorTool.swift` without touching this file, so the assertions that pin values filter to the 4a tools:
```swift
import AppKit
import Testing
@testable import TidyShot

struct EditorToolTests {
    /// The Phase 4a tools. 4b adds cases, so the assertions that pin values look only at these.
    let phase4a: [EditorTool] = [.select, .redact, .pixelate, .blur, .rectangle, .arrow]

    @Test func lettersAreUnique() {
        let letters = EditorTool.allCases.map(\.letter)
        #expect(Set(letters).count == letters.count)
        #expect(letters.allSatisfy { $0.isASCII && $0.isUppercase })
        #expect(phase4a.map(\.letter) == ["V", "D", "X", "B", "R", "A"])
    }

    @Test func toolForKeyIsCaseInsensitive() {
        for tool in EditorTool.allCases {
            #expect(EditorTool.tool(forKey: tool.letter) == tool)
            #expect(EditorTool.tool(forKey: Character(tool.letter.lowercased())) == tool)
        }
        #expect(EditorTool.tool(forKey: "d") == .redact)
        #expect(EditorTool.tool(forKey: "X") == .pixelate)
    }

    @Test func unknownKeyIsNil() {
        // "ß" upper-cases to two letters, so the lookup must compare strings, not build a Character.
        for key: Character in ["q", "Z", "1", " ", "ß", "\u{1B}"] {
            #expect(EditorTool.tool(forKey: key) == nil)
        }
    }

    @Test func everyToolHasSymbolAndTooltipWithLetter() {
        for tool in EditorTool.allCases {
            #expect(NSImage(systemSymbolName: tool.symbolName, accessibilityDescription: tool.title) != nil,
                    "\(tool.symbolName) is not an SF Symbol")
            #expect(tool.tooltip == "\(tool.title) (\(tool.letter))")
        }
        #expect(EditorTool.redact.tooltip == "Redact (D)")
        #expect(phase4a.map(\.title) == ["Select", "Redact", "Pixelate", "Blur", "Rectangle", "Arrow"])
    }

    @Test func effectToolsAreRedactPixelateBlur() {
        #expect(EditorTool.allCases.filter(\.isEffect) == [.redact, .pixelate, .blur])
    }

    @Test func toolbarOrderCoversEveryToolOnce() {
        let order = EditorTool.toolbarOrder
        #expect(order.count == EditorTool.allCases.count)
        #expect(Set(order) == Set(EditorTool.allCases))
        #expect(order.first == .select)
        // Redact leads the drawing tools because it is the only safe redaction. 4b inserts its
        // tools without reordering these.
        #expect(order.filter { phase4a.contains($0) } == phase4a)
    }
}
```

`TidyShotTests/EditorPaletteTests.swift`:
```swift
import CoreGraphics
import Foundation
import Testing
@testable import TidyShot

struct EditorPaletteTests {
    let large = CGRect(x: 0, y: 0, width: 1000, height: 1000)

    @Test func tenSwatchesUnique() {
        let swatches = EditorPalette.swatches
        #expect(swatches.count == 10)
        for (index, swatch) in swatches.enumerated() {
            #expect(!swatches[(index + 1)...].contains(swatch))
            #expect([swatch.red, swatch.green, swatch.blue].allSatisfy { (0...1).contains($0) })
            #expect(swatch.alpha == 1)
        }
        // Black first and white last, as in the popover.
        #expect(swatches.first == RGBA(red: 0, green: 0, blue: 0))
        #expect(swatches.last == RGBA(red: 1, green: 1, blue: 1))
        #expect(swatches.contains(EditorPalette.defaultStroke))
        #expect(swatches.contains(EditorPalette.defaultRedact))
    }

    @Test func standardDefaultsAreRedBlackFourEightTen() {
        let standard = EditorDefaults.standard
        #expect(standard == EditorDefaults(strokeColor: EditorPalette.defaultStroke,
                                           redactColor: EditorPalette.defaultRedact,
                                           lineWidthPoints: 4, blurRadiusPoints: 8, blockPoints: 10))
        #expect(EditorPalette.defaultRedact == RGBA(red: 0, green: 0, blue: 0))
        let red = EditorPalette.defaultStroke
        #expect(red.red == 1 && red.green < 0.3 && red.blue < 0.3)
        #expect(EditorPalette.lineWidthsPoints == [2, 3, 4, 6, 8, 12])
        #expect(EditorPalette.lineWidthsPoints.contains(standard.lineWidthPoints))
        #expect(RedactionDefaults.blurRangePoints == 4...24)
        #expect(RedactionDefaults.blurRangePoints.contains(standard.blurRadiusPoints))
        #expect(RedactionDefaults.blockRangePoints == 6...32)
        #expect(RedactionDefaults.blockRangePoints.contains(standard.blockPoints))
    }

    @Test func blurDefaultDoublesAtRetina() {
        #expect(RedactionDefaults.blurRadius(points: 8, scale: 1) == 8)
        #expect(RedactionDefaults.blurRadius(points: 8, scale: 2) == 16)
        #expect(RedactionDefaults.blurRadius(points: 24, scale: 2) == 48)
    }

    @Test func blurFloor() {
        #expect(RedactionDefaults.blurRadius(points: 2, scale: 2) == 8)
        #expect(RedactionDefaults.blurRadius(points: 0, scale: 1) == 4)
        #expect(RedactionDefaults.blurRadius(points: 4, scale: 2) == 8)
    }

    @Test func blockCappedAtRegionShorterSide() {
        #expect(RedactionDefaults.block(points: 10, scale: 2, region: CGRect(x: 10, y: 10, width: 300, height: 14)) == 14)
        // A fractional side rounds down, so the region still holds one whole block.
        #expect(RedactionDefaults.block(points: 10, scale: 2, region: CGRect(x: 0, y: 0, width: 14.6, height: 300)) == 14)
        // The cap wins over the floor in a thin region, but a block is never below one pixel.
        #expect(RedactionDefaults.block(points: 6, scale: 2, region: CGRect(x: 0, y: 0, width: 300, height: 5)) == 5)
        #expect(RedactionDefaults.block(points: 10, scale: 2, region: CGRect(x: 0, y: 0, width: 300, height: 0.5)) == 1)
        // A rect with a negative width is measured by its size.
        #expect(RedactionDefaults.block(points: 10, scale: 1, region: CGRect(x: 50, y: 50, width: -8, height: 40)) == 8)
    }

    @Test func blockFloor() {
        #expect(RedactionDefaults.block(points: 10, scale: 2, region: large) == 20)
        #expect(RedactionDefaults.block(points: 2, scale: 2, region: large) == 12)
        #expect(RedactionDefaults.block(points: 0, scale: 1, region: large) == 6)
        // Whole pixels, so the mosaic grid stays on pixel boundaries.
        #expect(RedactionDefaults.block(points: 7.4, scale: 2, region: large) == 15)
    }

    @Test func rgbaCodableRoundTrip() throws {
        let colour = RGBA(red: 0.25, green: 0.5, blue: 0.75, alpha: 0.5)
        let data = try JSONEncoder().encode(colour)
        #expect(try JSONDecoder().decode(RGBA.self, from: data) == colour)
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Double])
        #expect(object == ["red": 0.25, "green": 0.5, "blue": 0.75, "alpha": 0.5])
        // cgColor is made in sRGB from the same components.
        let cgColor = colour.cgColor
        #expect(cgColor.colorSpace?.name == CGColorSpace.sRGB)
        #expect(cgColor.components == [0.25, 0.5, 0.75, 0.5])
        #expect(RGBA(red: 1, green: 0, blue: 0).alpha == 1)
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run:
```bash
xcodegen generate && xcodebuild test -project TidyShot.xcodeproj -scheme TidyShot -destination 'platform=macOS' -derivedDataPath .build 2>&1 | grep -E "Test run with|error:|TEST"
```
Expected: compile errors in the three new test files, among them `cannot find type 'Annotation' in scope`, `cannot find 'EditorTool' in scope` and `cannot find 'EditorPalette' in scope`, then `** TEST FAILED **` and no `Test run with` line.

- [ ] **Step 3: Write ScaledImage and the model**

`TidyShot/Output/ScaledImage.swift`:
```swift
import CoreGraphics

/// A captured or decoded image with its backing scale. It is the only image type that crosses
/// between the annotation editor and `AppCoordinator`: `CaptureResult` cannot, because its
/// `CaptureTarget` is MainActor.
nonisolated struct ScaledImage: Sendable {
    let image: CGImage
    /// Pixels per point: the display's backing scale for a capture, or DPI / 72 for a decoded PNG.
    let scale: CGFloat
}

extension CaptureResult {
    /// The image and scale without the MainActor `target`.
    var scaled: ScaledImage { ScaledImage(image: image, scale: scale) }
}
```

`TidyShot/Editor/Model/RGBA.swift`:
```swift
import CoreGraphics

/// A colour in sRGB, each component from 0 to 1. The editor model stores this rather than a
/// CGColor or an NSColor, so documents stay Codable and Sendable.
nonisolated struct RGBA: Codable, Equatable, Sendable {
    var red: Double
    var green: Double
    var blue: Double
    var alpha: Double

    init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    /// The colour in the sRGB colour space, made on each call and never stored.
    var cgColor: CGColor {
        CGColor(srgbRed: CGFloat(red), green: CGFloat(green), blue: CGFloat(blue), alpha: CGFloat(alpha))
    }
}
```

`TidyShot/Editor/Model/Annotation.swift`:
```swift
import CoreGraphics
import Foundation

// All geometry is in image pixels with a top-left origin (CGImage row 0). Line widths, blur radii
// and pixel blocks are image pixels too: the points chosen in the UI times the capture scale.

/// A rectangle outline. The stroke sits inside `rect`.
nonisolated struct ShapeBox: Codable, Equatable, Sendable {
    let id: UUID
    var rect: CGRect
    var color: RGBA
    var lineWidth: CGFloat
}

/// A two-point shape: an arrow in 4a, a line in 4b. The tail is `from`, the head `to`.
nonisolated struct Segment: Codable, Equatable, Sendable {
    let id: UUID
    var from: CGPoint
    var to: CGPoint
    var color: RGBA
    var lineWidth: CGFloat
}

/// The area an effect covers.
nonisolated struct Region: Codable, Equatable, Sendable {
    let id: UUID
    var rect: CGRect
}

/// One edit on a capture. Effects (redact, blur, pixelate) belong to the base layer and render
/// beneath every drawing; drawings (rectangle, arrow) render above them.
nonisolated enum Annotation: Identifiable, Codable, Equatable, Sendable {
    case rectangle(ShapeBox)
    case arrow(Segment)
    case redact(Region, fill: RGBA)
    /// `radius` is the Gaussian sigma.
    case blur(Region, radius: CGFloat)
    case pixelate(Region, block: CGFloat)

    var id: UUID {
        switch self {
        case .rectangle(let box): box.id
        case .arrow(let segment): segment.id
        case .redact(let region, _), .blur(let region, _), .pixelate(let region, _): region.id
        }
    }

    var isEffect: Bool {
        switch self {
        case .rectangle, .arrow: false
        case .redact, .blur, .pixelate: true
        }
    }

    /// The region an effect covers; nil for a drawing.
    var effectRect: CGRect? {
        switch self {
        case .rectangle, .arrow: nil
        case .redact(let region, _), .blur(let region, _), .pixelate(let region, _): region.rect
        }
    }

    /// The name of the tool that makes this kind, for undo action names.
    var title: String {
        switch self {
        case .rectangle: "Rectangle"
        case .arrow: "Arrow"
        case .redact: "Redact"
        case .blur: "Blur"
        case .pixelate: "Pixelate"
        }
    }

    /// The same annotation shifted by `delta`: a rect's origin, or both ends of a segment.
    func moved(by delta: CGVector) -> Annotation {
        switch self {
        case .rectangle(var box):
            box.rect = box.rect.offsetBy(dx: delta.dx, dy: delta.dy)
            return .rectangle(box)
        case .arrow(var segment):
            segment.from = CGPoint(x: segment.from.x + delta.dx, y: segment.from.y + delta.dy)
            segment.to = CGPoint(x: segment.to.x + delta.dx, y: segment.to.y + delta.dy)
            return .arrow(segment)
        case .redact(var region, let fill):
            region.rect = region.rect.offsetBy(dx: delta.dx, dy: delta.dy)
            return .redact(region, fill: fill)
        case .blur(var region, let radius):
            region.rect = region.rect.offsetBy(dx: delta.dx, dy: delta.dy)
            return .blur(region, radius: radius)
        case .pixelate(var region, let block):
            region.rect = region.rect.offsetBy(dx: delta.dx, dy: delta.dy)
            return .pixelate(region, block: block)
        }
    }

    /// The stroke colour of a shape or the fill of a redaction. Blur and pixelate have no colour
    /// and come back unchanged.
    func withColor(_ color: RGBA) -> Annotation {
        switch self {
        case .rectangle(var box):
            box.color = color
            return .rectangle(box)
        case .arrow(var segment):
            segment.color = color
            return .arrow(segment)
        case .redact(let region, _):
            return .redact(region, fill: color)
        case .blur, .pixelate:
            return self
        }
    }

    /// The line width of a shape, in image pixels. Effects come back unchanged.
    func withLineWidth(_ width: CGFloat) -> Annotation {
        switch self {
        case .rectangle(var box):
            box.lineWidth = width
            return .rectangle(box)
        case .arrow(var segment):
            segment.lineWidth = width
            return .arrow(segment)
        case .redact, .blur, .pixelate:
            return self
        }
    }

    /// A blur's radius or a pixelate's block, in image pixels. Everything else comes back
    /// unchanged.
    func withEffectParameter(_ value: CGFloat) -> Annotation {
        switch self {
        case .blur(let region, _):
            return .blur(region, radius: value)
        case .pixelate(let region, _):
            return .pixelate(region, block: value)
        case .rectangle, .arrow, .redact:
            return self
        }
    }
}
```

`TidyShot/Editor/Model/AnnotationDocument.swift`:
```swift
import CoreGraphics
import Foundation

/// The edits on one capture, in creation order. The base image is not part of it: EditorModel
/// holds the CGImage next to the document and never changes it.
nonisolated struct AnnotationDocument: Codable, Equatable, Sendable {
    var annotations: [Annotation] = []

    /// Redact, blur and pixelate, in creation order. They render first, on the base layer.
    var effects: [Annotation] { annotations.filter(\.isEffect) }

    /// Every other annotation, in creation order, drawn above all effects.
    var drawings: [Annotation] { annotations.filter { !$0.isEffect } }

    func annotation(id: UUID) -> Annotation? {
        annotations.first { $0.id == id }
    }

    func appending(_ annotation: Annotation) -> AnnotationDocument {
        var copy = self
        copy.annotations.append(annotation)
        return copy
    }

    func removing(id: UUID) -> AnnotationDocument {
        var copy = self
        copy.annotations.removeAll { $0.id == id }
        return copy
    }

    /// Puts `annotation` where the annotation with its id sits, so the creation order is kept.
    /// Unchanged when no annotation has that id.
    func replacing(_ annotation: Annotation) -> AnnotationDocument {
        guard let index = annotations.firstIndex(where: { $0.id == annotation.id }) else { return self }
        var copy = self
        copy.annotations[index] = annotation
        return copy
    }

    /// Unchanged when no annotation has that id.
    func moving(id: UUID, by delta: CGVector) -> AnnotationDocument {
        guard let annotation = annotation(id: id) else { return self }
        return replacing(annotation.moved(by: delta))
    }
}
```

`TidyShot/Editor/Model/EditorTool.swift`. The symbol names were checked with `NSImage(systemSymbolName:accessibilityDescription:)`, and `everyToolHasSymbolAndTooltipWithLetter` keeps checking them:
```swift
/// The editor's tools. `toolbarOrder` is the only source for the toolbar's tools group, and
/// `makeTool(for:)` switches over every case with no default, so a new case is wired in both.
nonisolated enum EditorTool: String, CaseIterable, Sendable {
    case select, redact, pixelate, blur, rectangle, arrow

    /// The unmodified key that picks the tool, in upper case.
    var letter: Character {
        switch self {
        case .select: "V"
        case .redact: "D"
        case .pixelate: "X"
        case .blur: "B"
        case .rectangle: "R"
        case .arrow: "A"
        }
    }

    var title: String {
        switch self {
        case .select: "Select"
        case .redact: "Redact"
        case .pixelate: "Pixelate"
        case .blur: "Blur"
        case .rectangle: "Rectangle"
        case .arrow: "Arrow"
        }
    }

    /// The SF Symbol for the toolbar.
    var symbolName: String {
        switch self {
        case .select: "cursorarrow"
        case .redact: "rectangle.fill"
        case .pixelate: "checkerboard.rectangle"
        case .blur: "drop.halffull"
        case .rectangle: "rectangle"
        case .arrow: "arrow.up.right"
        }
    }

    /// The toolbar tooltip: the title and the key, for example "Redact (D)".
    var tooltip: String { "\(title) (\(letter))" }

    /// Redact, pixelate and blur make effects, which render beneath every drawing.
    var isEffect: Bool {
        switch self {
        case .redact, .pixelate, .blur: true
        case .select, .rectangle, .arrow: false
        }
    }

    /// Select, then Redact first among the drawing tools, because it is the only safe redaction.
    /// 4b inserts its tools here.
    static var toolbarOrder: [EditorTool] {
        [.select, .redact, .pixelate, .blur, .rectangle, .arrow]
    }

    /// The tool whose letter is `key`, in either case; nil for any other key.
    static func tool(forKey key: Character) -> EditorTool? {
        let typed = String(key).uppercased()
        return allCases.first { String($0.letter) == typed }
    }
}
```

`TidyShot/Editor/Model/EditorPalette.swift`. The swatches are fixed sRGB values: Apple's light-mode system colours, which the model cannot read from NSColor:
```swift
import CoreGraphics

/// The editor's fixed colours and line widths. Widths here are points; the model stores pixels.
nonisolated enum EditorPalette {
    private static let black = RGBA(red: 0, green: 0, blue: 0)
    private static let red = rgb(255, 59, 48)
    private static let orange = rgb(255, 149, 0)
    private static let yellow = rgb(255, 204, 0)
    private static let green = rgb(52, 199, 89)
    private static let teal = rgb(48, 176, 199)
    private static let blue = rgb(0, 122, 255)
    private static let purple = rgb(175, 82, 222)
    private static let pink = rgb(255, 45, 85)
    private static let white = RGBA(red: 1, green: 1, blue: 1)

    /// The colour popover's swatches, in order.
    static let swatches: [RGBA] = [black, red, orange, yellow, green, teal, blue, purple, pink, white]
    /// Rectangle and Arrow.
    static let defaultStroke = red
    /// Redact.
    static let defaultRedact = black
    /// The options popover's widths, also on keys 1 to 6.
    static let lineWidthsPoints: [CGFloat] = [2, 3, 4, 6, 8, 12]

    private static func rgb(_ red: Int, _ green: Int, _ blue: Int) -> RGBA {
        RGBA(red: Double(red) / 255, green: Double(green) / 255, blue: Double(blue) / 255)
    }
}

/// Blur radius and pixel block in image pixels, from the points chosen in the UI.
nonisolated enum RedactionDefaults {
    /// The blur slider's range, in points.
    static let blurRangePoints: ClosedRange<CGFloat> = 4...24
    /// The pixel block slider's range, in points.
    static let blockRangePoints: ClosedRange<CGFloat> = 6...32

    /// The Gaussian sigma: `points` times the capture scale, never below 4 pt.
    static func blurRadius(points: CGFloat, scale: CGFloat) -> CGFloat {
        max(points, blurRangePoints.lowerBound) * scale
    }

    /// The mosaic block in whole pixels, so the grid stays on pixel boundaries: `points` times the
    /// capture scale, never below 6 pt, then capped at the region's shorter side (rounded down) so
    /// the region holds at least one block. Never below 1.
    static func block(points: CGFloat, scale: CGFloat, region: CGRect) -> CGFloat {
        let wanted = (max(points, blockRangePoints.lowerBound) * scale).rounded()
        let rect = region.standardized
        let shorterSide = min(rect.width, rect.height).rounded(.down)
        return max(1, min(wanted, shorterSide))
    }
}

/// The colours and sizes a new editor starts with, in points. AppSettings persists them, and an
/// editor reads them once when it opens.
nonisolated struct EditorDefaults: Equatable, Sendable {
    var strokeColor: RGBA
    var redactColor: RGBA
    var lineWidthPoints: CGFloat
    var blurRadiusPoints: CGFloat
    var blockPoints: CGFloat

    static let standard = EditorDefaults(strokeColor: EditorPalette.defaultStroke,
                                         redactColor: EditorPalette.defaultRedact,
                                         lineWidthPoints: 4, blurRadiusPoints: 8, blockPoints: 10)
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run:
```bash
xcodegen generate && xcodebuild test -project TidyShot.xcodeproj -scheme TidyShot -destination 'platform=macOS' -derivedDataPath .build 2>&1 | grep -E "Test run with|error:|TEST"
```
Expected: no `error:` lines, `Test run with 212 tests in 31 suites passed`, then `** TEST SUCCEEDED **`. This task adds 20 tests and 3 suites.

Then confirm the model stays free of UI frameworks:
```bash
grep -lE "^import (AppKit|SwiftUI|CoreImage)" TidyShot/Editor/Model/*.swift TidyShot/Output/ScaledImage.swift
```
Expected: no output.

- [ ] **Step 5: Hand check**

None. This task has no UI.

- [ ] **Step 6: Commit**

```bash
git add TidyShot/Output/ScaledImage.swift TidyShot/Editor/Model/RGBA.swift TidyShot/Editor/Model/Annotation.swift TidyShot/Editor/Model/AnnotationDocument.swift TidyShot/Editor/Model/EditorTool.swift TidyShot/Editor/Model/EditorPalette.swift TidyShotTests/AnnotationDocumentTests.swift TidyShotTests/EditorToolTests.swift TidyShotTests/EditorPaletteTests.swift
git commit -m "feat: annotation editor value model and tool table"
```

---

### Task 3: Canvas transform and image-space geometry (TDD)

**Files:**
- Create: `TidyShot/Editor/Geometry/CanvasTransform.swift`
- Create: `TidyShot/Editor/Geometry/ImageRects.swift`
- Create: `TidyShot/Editor/Geometry/EffectGeometry.swift`
- Create: `TidyShot/Editor/Geometry/EditorWindowGeometry.swift`
- Test: `TidyShotTests/CanvasTransformTests.swift` (new)
- Test: `TidyShotTests/ImageRectsTests.swift` (new)
- Test: `TidyShotTests/EffectGeometryTests.swift` (new)
- Test: `TidyShotTests/EditorWindowGeometryTests.swift` (new)
- Modify: none. The `TidyShot/Editor/Geometry/` folder is new; the recursive `path: TidyShot` and `path: TidyShotTests` sources (project.yml:24, 66) pick it up after `xcodegen generate`.

**Interfaces:**
- Consumes:
  - From Task 2: `Annotation` with the cases `.rectangle(ShapeBox)`, `.arrow(Segment)`, `.redact(Region, fill: RGBA)`, `.blur(Region, radius: CGFloat)` and `.pixelate(Region, block: CGFloat)`; `Region(id: UUID, rect: CGRect)` and `ShapeBox(id:rect:color:lineWidth:)` (memberwise); `EditorPalette.defaultRedact` and `EditorPalette.defaultStroke` (tests only).
  - Existing: the top-left pixel convention of `Luminance.mean(of:in:)` (TidyShot/Selection/Luminance.swift:16) and `CGImage.cropping(to:)`. Nothing existing is modified.
- Produces (all `nonisolated`, no AppKit import):
  - `struct CanvasTransform: Equatable, Sendable { var zoom: CGFloat; var offset: CGPoint }` with the memberwise `init(zoom:offset:)` and:
    - `func viewPoint(_ point: CGPoint) -> CGPoint`, `func imagePoint(_ point: CGPoint) -> CGPoint`
    - `func viewRect(_ rect: CGRect) -> CGRect`, `func imageRect(_ rect: CGRect) -> CGRect`
    - `var affine: CGAffineTransform`
    - `static func fitting(imagePixelSize: CGSize, in viewSize: CGSize, inset: CGFloat, captureScale: CGFloat) -> CanvasTransform`
    - `func zoomed(by factor: CGFloat, around anchor: CGPoint, limits: ClosedRange<CGFloat>) -> CanvasTransform`
    - `func panned(by delta: CGPoint) -> CanvasTransform`
    - `func snapped(toBackingScale backingScale: CGFloat) -> CanvasTransform`
    - `static func zoomLimits(captureScale: CGFloat) -> ClosedRange<CGFloat>`
    - `func percent(captureScale: CGFloat) -> Int`
  - `enum ImageRects { static func integral(_ rect: CGRect, clippedTo size: CGSize) -> CGRect; static func bottomLeft(_ topLeft: CGRect, imageHeight: Int) -> CGRect; static func topLeft(_ bottomLeft: CGRect, imageHeight: Int) -> CGRect }`
  - `enum EffectGeometry { static let blurReachInSigmas: CGFloat; static func sampleRect(of effect: Annotation, imageSize: CGSize) -> CGRect; static func mosaicRect(_ rect: CGRect, block: CGFloat) -> CGRect }`
  - `enum EditorWindowGeometry { static let inset: CGFloat /* 24 */; static let minimumContentSize: CGSize /* 640 x 420 */; static let screenFraction: CGFloat /* 0.9 */; static func initialContentSize(imagePixels: CGSize, scale: CGFloat, chrome: CGSize, visibleFrame: CGRect) -> CGSize; static func cascaded(from previous: CGRect?, size: CGSize, visibleFrame: CGRect, offset: CGFloat = 22) -> CGRect }`

Rules later tasks rely on:
- View space is the flipped `BaseImageView` and `CanvasView` (points, origin top left): `view = image * zoom + offset`, and `zoom` is points per image pixel, so 100 % is `1 / captureScale`. `CanvasView.draw(_:)` concatenates `affine` (Task 10). `AnnotationDrawing.drawSelection` maps with `viewRect` and `viewPoint` (Task 7).
- Task 10 opens at `fitting(imagePixelSize:in:inset: EditorWindowGeometry.inset, captureScale:)` and then calls `snapped(toBackingScale:)`. ⌘= and ⌘- call `zoomed(by: 1.25 or 0.8, around: the view centre, limits: zoomLimits(captureScale:))`. Pinch and ⌘-scroll pass the cursor as the anchor. `chrome` is the window's frame size less its content size, measured after the toolbar is attached. `size` in `cascaded` is the frame size.
- `sampleRect` is integral and clipped to the image. Task 6 puts an earlier effect into `beneath` when `ImageRects.integral(earlier.effectRect!, clippedTo: imageSize)` intersects the later effect's `sampleRect` (adjacent pixels do not intersect).
- `mosaicRect` is in top-left pixels and not clipped. In Core Image's bottom-left space the grid is anchored at y = image height, so Task 5 translates `ImageRects.bottomLeft(mosaicRect(...))` to the origin before `transformed(by: 1/block, highQualityDownsample: true)`, and translates back after scaling up.

- [ ] **Step 1: Write the failing tests**

`TidyShotTests/CanvasTransformTests.swift`:
```swift
import CoreGraphics
import Testing
@testable import TidyShot

struct CanvasTransformTests {
    func close(_ a: CGPoint, _ b: CGPoint) -> Bool {
        abs(a.x - b.x) < 1e-9 && abs(a.y - b.y) < 1e-9
    }

    /// viewPoint and imagePoint invert each other, as do viewRect and imageRect; `affine` maps
    /// like viewPoint; a pan moves every view point by its delta.
    @Test func pointAndRectRoundTrip() {
        let odd = CanvasTransform(zoom: 0.37, offset: CGPoint(x: 13.5, y: -42.25))
        let point = CGPoint(x: 123.4, y: 56.7)
        #expect(close(odd.imagePoint(odd.viewPoint(point)), point))
        #expect(close(point.applying(odd.affine), odd.viewPoint(point)))

        let half = CanvasTransform(zoom: 0.5, offset: CGPoint(x: 24, y: 10))
        #expect(half.viewPoint(CGPoint(x: 100, y: 40)) == CGPoint(x: 74, y: 30))
        let rect = CGRect(x: 10, y: 20, width: 64, height: 48)
        #expect(half.viewRect(rect) == CGRect(x: 29, y: 20, width: 32, height: 24))
        #expect(half.imageRect(half.viewRect(rect)) == rect)
        #expect(rect.applying(half.affine) == half.viewRect(rect))
        #expect(half.panned(by: CGPoint(x: 5, y: -3)).viewPoint(CGPoint(x: 100, y: 40)) == CGPoint(x: 79, y: 27))
    }

    /// A capture smaller than the window opens at 100 %, however much room there is.
    @Test func fittingNeverExceedsNaturalSize() {
        let small = CGSize(width: 200, height: 100)
        let view = CGSize(width: 1200, height: 800)
        let retina = CanvasTransform.fitting(imagePixelSize: small, in: view, inset: 24, captureScale: 2)
        #expect(retina.zoom == 0.5)
        #expect(retina.percent(captureScale: 2) == 100)
        #expect(CanvasTransform.fitting(imagePixelSize: small, in: view, inset: 24, captureScale: 1).zoom == 1)
    }

    /// A capture larger than the window shrinks into the room inside the inset, limited by the
    /// tighter side, and its centre lands on the view's centre.
    @Test func fittingCentres() {
        let view = CGSize(width: 1048, height: 548)
        #expect(CanvasTransform.fitting(imagePixelSize: CGSize(width: 4000, height: 2000), in: view, inset: 24, captureScale: 2)
                == CanvasTransform(zoom: 0.25, offset: CGPoint(x: 24, y: 24)))
        let wide = CanvasTransform.fitting(imagePixelSize: CGSize(width: 4000, height: 1000), in: view, inset: 24, captureScale: 2)
        #expect(wide == CanvasTransform(zoom: 0.25, offset: CGPoint(x: 24, y: 149)))
        #expect(wide.viewPoint(CGPoint(x: 2000, y: 500)) == CGPoint(x: 524, y: 274))
        #expect(CanvasTransform.fitting(imagePixelSize: CGSize(width: 1000, height: 4000), in: view, inset: 24, captureScale: 2)
                == CanvasTransform(zoom: 0.125, offset: CGPoint(x: 461.5, y: 24)))
    }

    /// The image pixel under the anchor stays under it, zooming in and back out.
    @Test func zoomedKeepsAnchorFixed() {
        let limits = CanvasTransform.zoomLimits(captureScale: 2)
        let start = CanvasTransform(zoom: 0.5, offset: CGPoint(x: 30, y: 40))
        let anchor = CGPoint(x: 230, y: 140)
        #expect(start.imagePoint(anchor) == CGPoint(x: 400, y: 200))
        let zoomedIn = start.zoomed(by: 1.25, around: anchor, limits: limits)
        #expect(zoomedIn == CanvasTransform(zoom: 0.625, offset: CGPoint(x: -20, y: 15)))
        #expect(zoomedIn.viewPoint(CGPoint(x: 400, y: 200)) == anchor)
        let back = zoomedIn.zoomed(by: 0.8, around: anchor, limits: limits)
        #expect(abs(back.zoom - 0.5) < 1e-12)
        #expect(close(back.imagePoint(anchor), CGPoint(x: 400, y: 200)))
    }

    /// 10 % to 800 % of the natural size. A clamped zoom still keeps the anchor fixed, and a zoom
    /// that starts below the limit (a fitted, very tall capture) never jumps against the gesture.
    @Test func zoomClampsToLimits() {
        let limits = CanvasTransform.zoomLimits(captureScale: 2)
        #expect(limits == 0.05...4)
        #expect(CanvasTransform.zoomLimits(captureScale: 1) == 0.1...8)
        let start = CanvasTransform(zoom: 0.5, offset: .zero)
        let anchor = CGPoint(x: 100, y: 100)
        let most = start.zoomed(by: 100, around: anchor, limits: limits)
        #expect(most.zoom == 4)
        #expect(close(most.imagePoint(anchor), start.imagePoint(anchor)))
        #expect(start.zoomed(by: 0.001, around: anchor, limits: limits).zoom == 0.05)

        let tiny = CanvasTransform(zoom: 1.0 / 64, offset: CGPoint(x: 7, y: 9))
        #expect(tiny.zoomed(by: 0.8, around: anchor, limits: limits) == tiny)
        #expect(tiny.zoomed(by: 1.25, around: anchor, limits: limits).zoom == 1.25 / 64)
    }

    @Test func snappedOffsetsLandOnDevicePixels() {
        let transform = CanvasTransform(zoom: 0.3, offset: CGPoint(x: 10.3, y: 7.76))
        #expect(transform.snapped(toBackingScale: 2) == CanvasTransform(zoom: 0.3, offset: CGPoint(x: 10.5, y: 8)))
        #expect(transform.snapped(toBackingScale: 1) == CanvasTransform(zoom: 0.3, offset: CGPoint(x: 10, y: 8)))
        // Zoomed in, the offset is negative; it snaps the same way.
        let negative = CanvasTransform(zoom: 2, offset: CGPoint(x: -3.3, y: -0.2))
        #expect(negative.snapped(toBackingScale: 2) == CanvasTransform(zoom: 2, offset: CGPoint(x: -3.5, y: 0)))
    }

    /// 100 % is the natural point size: one image pixel per `1 / captureScale` points.
    @Test func percentIsRelativeToNaturalSize() {
        #expect(CanvasTransform(zoom: 0.5, offset: .zero).percent(captureScale: 2) == 100)
        #expect(CanvasTransform(zoom: 1, offset: .zero).percent(captureScale: 2) == 200)
        #expect(CanvasTransform(zoom: 1, offset: .zero).percent(captureScale: 1) == 100)
        #expect(CanvasTransform(zoom: 1.0 / 3, offset: .zero).percent(captureScale: 1) == 33)
        #expect(CanvasTransform(zoom: 0.25 * 0.8, offset: .zero).percent(captureScale: 2) == 40)
        let limits = CanvasTransform.zoomLimits(captureScale: 2)
        #expect(CanvasTransform(zoom: limits.lowerBound, offset: .zero).percent(captureScale: 2) == 10)
        #expect(CanvasTransform(zoom: limits.upperBound, offset: .zero).percent(captureScale: 2) == 800)
    }
}
```

`TidyShotTests/ImageRectsTests.swift`:
```swift
import CoreGraphics
import Testing
@testable import TidyShot

/// A 64 by 48 fixture: the sides differ, so a swapped axis or a flip about the wrong side shows.
struct ImageRectsTests {
    let width = 64
    let height = 48
    let size = CGSize(width: 64, height: 48)

    func context(data: UnsafeMutableRawPointer? = nil) -> CGContext {
        CGContext(data: data, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                  space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    }

    /// Black, with `rect` filled red in the context's own coordinates (origin bottom left).
    func image(redAt rect: CGRect) -> CGImage {
        let context = context()
        context.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(origin: .zero, size: size))
        context.setFillColor(CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1))
        context.fill(rect)
        return context.makeImage()!
    }

    /// The red channel by row and column, row 0 first: the top row, as CGImage stores it.
    func redChannel(_ image: CGImage) -> [[UInt8]] {
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        pixels.withUnsafeMutableBytes { buffer in
            context(data: buffer.baseAddress).draw(image, in: CGRect(origin: .zero, size: size))
        }
        return (0..<height).map { row in (0..<width).map { column in pixels[(row * width + column) * 4] } }
    }

    /// A model rect, filled through `bottomLeft` in a Core Graphics context, lands on exactly
    /// those CGImage rows and columns.
    @Test func bottomLeftFlipsRows() {
        let topLeft = CGRect(x: 4, y: 6, width: 10, height: 8)
        let converted = ImageRects.bottomLeft(topLeft, imageHeight: height)
        #expect(converted == CGRect(x: 4, y: 34, width: 10, height: 8))
        let red = redChannel(image(redAt: converted))
        #expect(red.indices.filter { red[$0][4] == 255 } == Array(6..<14))
        #expect(red[6].indices.filter { red[6][$0] == 255 } == Array(4..<14))
    }

    @Test func topLeftInvertsBottomLeft() {
        let rects = [CGRect(x: 4, y: 6, width: 10, height: 8), CGRect(origin: .zero, size: size),
                     CGRect(x: 60.5, y: 0.25, width: 3.5, height: 47.75), CGRect(x: 0, y: 47, width: 1, height: 1)]
        for rect in rects {
            #expect(ImageRects.topLeft(ImageRects.bottomLeft(rect, imageHeight: height), imageHeight: height) == rect)
        }
        // The last top-left row is the first bottom-left row, and the other way round.
        #expect(ImageRects.bottomLeft(CGRect(x: 0, y: 47, width: 64, height: 1), imageHeight: height)
                == CGRect(x: 0, y: 0, width: 64, height: 1))
        #expect(ImageRects.topLeft(CGRect(x: 2, y: 40, width: 5, height: 8), imageHeight: height)
                == CGRect(x: 2, y: 0, width: 5, height: 8))
    }

    @Test func integralRoundsOutAndClips() {
        #expect(ImageRects.integral(CGRect(x: 3.2, y: 4.7, width: 10.1, height: 5.6), clippedTo: size)
                == CGRect(x: 3, y: 4, width: 11, height: 7))
        #expect(ImageRects.integral(CGRect(x: 8, y: 9, width: 10, height: 12), clippedTo: size)
                == CGRect(x: 8, y: 9, width: 10, height: 12))
        #expect(ImageRects.integral(CGRect(x: -5.5, y: 40.2, width: 20, height: 20), clippedTo: size)
                == CGRect(x: 0, y: 40, width: 15, height: 8))
        // A rect dragged up and to the left has a negative size; it is standardised.
        #expect(ImageRects.integral(CGRect(x: 20, y: 30, width: -10, height: -5), clippedTo: size)
                == CGRect(x: 10, y: 25, width: 10, height: 5))
    }

    @Test func emptyWhenOutside() {
        #expect(ImageRects.integral(CGRect(x: 70, y: 10, width: 5, height: 5), clippedTo: size) == .zero)
        // Touching the right edge, or ending at row 0, covers no pixel.
        #expect(ImageRects.integral(CGRect(x: 64, y: 0, width: 4, height: 4), clippedTo: size) == .zero)
        #expect(ImageRects.integral(CGRect(x: 10, y: -8, width: 5, height: 8), clippedTo: size) == .zero)
        #expect(ImageRects.integral(CGRect(x: 10, y: 10, width: 0, height: 5), clippedTo: size) == .zero)
        #expect(ImageRects.integral(.null, clippedTo: size) == .zero)
    }
}
```

`TidyShotTests/EffectGeometryTests.swift`:
```swift
import CoreGraphics
import Foundation
import Testing
@testable import TidyShot

struct EffectGeometryTests {
    /// The 64 by 48 image the effects sit on.
    let size = CGSize(width: 64, height: 48)

    func region(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat) -> Region {
        Region(id: UUID(), rect: CGRect(x: x, y: y, width: width, height: height))
    }

    @Test func blurSampleRectGrowsByThreeSigma() {
        // Sigma 4 reads 12 px beyond the rect on every side.
        #expect(EffectGeometry.sampleRect(of: .blur(region(20, 15, 10, 8), radius: 4), imageSize: size)
                == CGRect(x: 8, y: 3, width: 34, height: 32))
        // Sigma 2.5 reads ceil(7.5) = 8 px.
        #expect(EffectGeometry.sampleRect(of: .blur(region(20, 15, 10, 8), radius: 2.5), imageSize: size)
                == CGRect(x: 12, y: 7, width: 26, height: 24))
        // Near a corner the margin is clipped to the image.
        #expect(EffectGeometry.sampleRect(of: .blur(region(2, 2, 10, 10), radius: 4), imageSize: size)
                == CGRect(x: 0, y: 0, width: 24, height: 24))
    }

    @Test func pixelateSampleRectIsBlockSnapped() {
        #expect(EffectGeometry.sampleRect(of: .pixelate(region(13, 7, 20, 10), block: 6), imageSize: size)
                == CGRect(x: 12, y: 6, width: 24, height: 12))
        // The last cells reach column 66; the sample stops at the image's edge.
        #expect(EffectGeometry.sampleRect(of: .pixelate(region(60, 44, 4, 4), block: 6), imageSize: size)
                == CGRect(x: 60, y: 42, width: 4, height: 6))
    }

    @Test func redactSampleRectIsItself() {
        let fill = EditorPalette.defaultRedact
        #expect(EffectGeometry.sampleRect(of: .redact(region(5, 6, 7, 8), fill: fill), imageSize: size)
                == CGRect(x: 5, y: 6, width: 7, height: 8))
        // Rounded out to the pixels its tile covers.
        #expect(EffectGeometry.sampleRect(of: .redact(region(5.5, 6, 7, 8.2), fill: fill), imageSize: size)
                == CGRect(x: 5, y: 6, width: 8, height: 9))
        // A drawing has no tile and samples nothing.
        let box = ShapeBox(id: UUID(), rect: CGRect(x: 5, y: 6, width: 7, height: 8), color: EditorPalette.defaultStroke, lineWidth: 8)
        #expect(EffectGeometry.sampleRect(of: .rectangle(box), imageSize: size) == .zero)
    }

    /// Cells sit on multiples of the block from the top-left pixel, wherever the region is.
    @Test func mosaicRectAnchoredToImageGrid() {
        #expect(EffectGeometry.mosaicRect(CGRect(x: 13, y: 7, width: 20, height: 10), block: 6)
                == CGRect(x: 12, y: 6, width: 24, height: 12))
        // Dragged 4 px right: the cells it still covers are the same cells.
        #expect(EffectGeometry.mosaicRect(CGRect(x: 17, y: 7, width: 20, height: 10), block: 6)
                == CGRect(x: 12, y: 6, width: 30, height: 12))
        // An aligned rect is unchanged, and fractional edges round out to whole cells.
        #expect(EffectGeometry.mosaicRect(CGRect(x: 12, y: 6, width: 24, height: 12), block: 6)
                == CGRect(x: 12, y: 6, width: 24, height: 12))
        #expect(EffectGeometry.mosaicRect(CGRect(x: 12.5, y: 6, width: 5, height: 0.5), block: 6)
                == CGRect(x: 12, y: 6, width: 6, height: 6))
        // Not clipped: the renderer decides the edge cells.
        #expect(EffectGeometry.mosaicRect(CGRect(x: 60, y: 44, width: 4, height: 4), block: 6)
                == CGRect(x: 60, y: 42, width: 6, height: 6))
    }
}
```

`TidyShotTests/EditorWindowGeometryTests.swift`:
```swift
import CoreGraphics
import Testing
@testable import TidyShot

struct EditorWindowGeometryTests {
    /// A 1920 by 1080 display below a 25 pt menu bar.
    let screen = CGRect(x: 0, y: 0, width: 1920, height: 1055)
    /// The title bar and unified toolbar: frame size minus content size.
    let chrome = CGSize(width: 0, height: 52)

    @Test func naturalSizePlusChromeWhenItFits() {
        // 1600 by 1000 pixels at 2x are 800 by 500 points, plus 24 pt on every side.
        #expect(EditorWindowGeometry.initialContentSize(imagePixels: CGSize(width: 1600, height: 1000), scale: 2,
                                                        chrome: chrome, visibleFrame: screen) == CGSize(width: 848, height: 548))
        #expect(EditorWindowGeometry.initialContentSize(imagePixels: CGSize(width: 1000, height: 700), scale: 1,
                                                        chrome: chrome, visibleFrame: screen) == CGSize(width: 1048, height: 748))
        // Half points round up, so the canvas still fits the image at 100 %.
        let odd = CGSize(width: 1601, height: 1001)
        let content = EditorWindowGeometry.initialContentSize(imagePixels: odd, scale: 2, chrome: chrome, visibleFrame: screen)
        #expect(content == CGSize(width: 849, height: 549))
        #expect(CanvasTransform.fitting(imagePixelSize: odd, in: content, inset: EditorWindowGeometry.inset, captureScale: 2).zoom == 0.5)
    }

    @Test func clampedToNinetyPercent() {
        // A 5K capture is 2560 by 1440 points: the frame is 90 % of the screen, 1728 by 949.5,
        // and the content is that less the chrome, rounded down.
        #expect(EditorWindowGeometry.initialContentSize(imagePixels: CGSize(width: 5120, height: 2880), scale: 2,
                                                        chrome: chrome, visibleFrame: screen) == CGSize(width: 1728, height: 897))
        // Only the side that does not fit is clamped, on a screen whose origin is elsewhere.
        let laptop = CGRect(x: 1920, y: 300, width: 1440, height: 875)
        #expect(EditorWindowGeometry.initialContentSize(imagePixels: CGSize(width: 3000, height: 800), scale: 2,
                                                        chrome: chrome, visibleFrame: laptop) == CGSize(width: 1296, height: 448))
    }

    @Test func minimumSize() {
        #expect(EditorWindowGeometry.initialContentSize(imagePixels: CGSize(width: 200, height: 100), scale: 2,
                                                        chrome: chrome, visibleFrame: screen) == CGSize(width: 640, height: 420))
        // A long thin capture: the long side at its natural size, the short side at the minimum.
        #expect(EditorWindowGeometry.initialContentSize(imagePixels: CGSize(width: 1200, height: 80), scale: 1,
                                                        chrome: chrome, visibleFrame: screen) == CGSize(width: 1248, height: 420))
        // On a screen too small for the minimum, the 90 % cap wins.
        #expect(EditorWindowGeometry.initialContentSize(imagePixels: CGSize(width: 200, height: 100), scale: 2, chrome: chrome,
                                                        visibleFrame: CGRect(x: 0, y: 0, width: 600, height: 400))
                == CGSize(width: 540, height: 308))
    }

    @Test func cascadeOffsetsAndStaysOnScreen() {
        let laptop = CGRect(x: 0, y: 25, width: 1440, height: 875)
        let size = CGSize(width: 800, height: 575)
        // The first editor is centred.
        let first = EditorWindowGeometry.cascaded(from: nil, size: size, visibleFrame: laptop)
        #expect(first == CGRect(x: 320, y: 175, width: 800, height: 575))
        // The next is 22 pt right and 22 pt down.
        #expect(EditorWindowGeometry.cascaded(from: first, size: size, visibleFrame: laptop)
                == CGRect(x: 342, y: 153, width: 800, height: 575))
        // After a window of another size, the top edge steps down, not the origin.
        #expect(EditorWindowGeometry.cascaded(from: CGRect(x: 100, y: 300, width: 900, height: 500), size: size, visibleFrame: laptop)
                == CGRect(x: 122, y: 203, width: 800, height: 575))
        // Past the right and bottom edges: clamped inside the visible frame.
        #expect(EditorWindowGeometry.cascaded(from: CGRect(x: 630, y: 30, width: 800, height: 575), size: size, visibleFrame: laptop)
                == CGRect(x: 640, y: 25, width: 800, height: 575))
        // Larger than the screen: the top-left corner stays on it, so the title bar can be reached.
        #expect(EditorWindowGeometry.cascaded(from: nil, size: CGSize(width: 1600, height: 1000), visibleFrame: laptop)
                == CGRect(x: 0, y: -100, width: 1600, height: 1000))
    }
}
```

The literals are chosen so that every `==` is exact in binary floating point; only the two round trips through 0.37 and 0.8 use a tolerance.

- [ ] **Step 2: Run the tests to verify they fail**

Run:
```bash
xcodegen generate && xcodebuild test -project TidyShot.xcodeproj -scheme TidyShot -destination 'platform=macOS' -derivedDataPath .build 2>&1 | grep -E "Test run with|error:|TEST"
```
Expected: compile errors, among them `cannot find 'CanvasTransform' in scope`, `cannot find 'ImageRects' in scope`, `cannot find 'EffectGeometry' in scope` and `cannot find 'EditorWindowGeometry' in scope`, then `** TEST FAILED **`.

- [ ] **Step 3: Write the geometry**

`TidyShot/Editor/Geometry/CanvasTransform.swift`:
```swift
import CoreGraphics

/// Maps the model's image pixels (origin top left, CGImage row 0 at the top) to the editor's
/// flipped canvas views (points, origin top left) and back: `view = image * zoom + offset`.
/// `zoom` is points per image pixel, so a 2x capture is at its natural size (100 %) at zoom 0.5.
nonisolated struct CanvasTransform: Equatable, Sendable {
    /// Points per image pixel.
    var zoom: CGFloat
    /// Where image pixel (0, 0) sits in the view, in points.
    var offset: CGPoint

    func viewPoint(_ point: CGPoint) -> CGPoint {
        CGPoint(x: point.x * zoom + offset.x, y: point.y * zoom + offset.y)
    }

    func imagePoint(_ point: CGPoint) -> CGPoint {
        CGPoint(x: (point.x - offset.x) / zoom, y: (point.y - offset.y) / zoom)
    }

    func viewRect(_ rect: CGRect) -> CGRect {
        guard !rect.isNull else { return rect }
        return CGRect(x: rect.minX * zoom + offset.x, y: rect.minY * zoom + offset.y,
                      width: rect.width * zoom, height: rect.height * zoom)
    }

    func imageRect(_ rect: CGRect) -> CGRect {
        guard !rect.isNull else { return rect }
        return CGRect(x: (rect.minX - offset.x) / zoom, y: (rect.minY - offset.y) / zoom,
                      width: rect.width / zoom, height: rect.height / zoom)
    }

    /// Concatenated onto a flipped view's CTM, this makes drawing happen in image pixels:
    /// `point.applying(affine) == viewPoint(point)`.
    var affine: CGAffineTransform {
        CGAffineTransform(a: zoom, b: 0, c: 0, d: zoom, tx: offset.x, ty: offset.y)
    }

    /// 10 % to 800 % of the natural size.
    static func zoomLimits(captureScale: CGFloat) -> ClosedRange<CGFloat> {
        let scale = captureScale > 0 ? captureScale : 1
        return (0.1 / scale)...(8 / scale)
    }

    /// The whole image inside `viewSize` less `inset` on every side, centred, and never above
    /// the natural size (`1 / captureScale`). Not clamped to `zoomLimits`, so a very tall capture
    /// still fits. The offset is not snapped; call `snapped(toBackingScale:)` before showing it.
    static func fitting(imagePixelSize: CGSize, in viewSize: CGSize, inset: CGFloat,
                        captureScale: CGFloat) -> CanvasTransform {
        let natural = 1 / (captureScale > 0 ? captureScale : 1)
        guard imagePixelSize.width > 0, imagePixelSize.height > 0 else {
            return CanvasTransform(zoom: natural, offset: .zero)
        }
        let roomWidth = max(viewSize.width - 2 * inset, 1)
        let roomHeight = max(viewSize.height - 2 * inset, 1)
        let zoom = min(natural, roomWidth / imagePixelSize.width, roomHeight / imagePixelSize.height)
        return CanvasTransform(zoom: zoom, offset: CGPoint(x: (viewSize.width - imagePixelSize.width * zoom) / 2,
                                                           y: (viewSize.height - imagePixelSize.height * zoom) / 2))
    }

    /// Zoom multiplied by `factor` and clamped to `limits`, keeping the image pixel under the
    /// view point `anchor` where it is. The range is widened to include the current zoom, so a
    /// zoom that starts outside the limits (a fit below 10 %) never moves against the gesture.
    func zoomed(by factor: CGFloat, around anchor: CGPoint, limits: ClosedRange<CGFloat>) -> CanvasTransform {
        guard factor > 0, factor.isFinite else { return self }
        let lower = min(limits.lowerBound, zoom)
        let upper = max(limits.upperBound, zoom)
        let next = min(max(zoom * factor, lower), upper)
        guard next != zoom else { return self }
        let fixed = imagePoint(anchor)
        return CanvasTransform(zoom: next, offset: CGPoint(x: anchor.x - fixed.x * next, y: anchor.y - fixed.y * next))
    }

    /// The image moved by `delta` view points. Unbounded.
    func panned(by delta: CGPoint) -> CanvasTransform {
        CanvasTransform(zoom: zoom, offset: CGPoint(x: offset.x + delta.x, y: offset.y + delta.y))
    }

    /// The offset rounded to the nearest device pixel at `backingScale`, so the image's pixel
    /// grid starts on a device pixel. The zoom is unchanged.
    func snapped(toBackingScale backingScale: CGFloat) -> CanvasTransform {
        guard backingScale > 0 else { return self }
        return CanvasTransform(zoom: zoom, offset: CGPoint(x: (offset.x * backingScale).rounded() / backingScale,
                                                           y: (offset.y * backingScale).rounded() / backingScale))
    }

    /// The zoom as a whole percentage of the natural size: 100 at `1 / captureScale`.
    func percent(captureScale: CGFloat) -> Int {
        Int((zoom * captureScale * 100).rounded())
    }
}
```

`TidyShot/Editor/Geometry/ImageRects.swift`:
```swift
import CoreGraphics

/// Rects in image pixels. The model uses a top-left origin (CGImage row 0 at the top, as for
/// `CGImage.cropping(to:)` and `Luminance.mean(of:in:)`); Core Graphics bitmap contexts and
/// Core Image use a bottom-left one, where y = 0 is the image's last row.
nonisolated enum ImageRects {
    /// `rect` rounded outward to whole pixels and clipped to an image of `size`. `.zero` when
    /// nothing is left: an empty or null rect, or one wholly outside or only touching an edge.
    static func integral(_ rect: CGRect, clippedTo size: CGSize) -> CGRect {
        guard !rect.isEmpty, !rect.isInfinite else { return .zero }
        let minX = rect.minX.rounded(.down)
        let minY = rect.minY.rounded(.down)
        let outward = CGRect(x: minX, y: minY, width: rect.maxX.rounded(.up) - minX, height: rect.maxY.rounded(.up) - minY)
        let clipped = outward.intersection(CGRect(origin: .zero, size: size))
        return clipped.isEmpty ? .zero : clipped
    }

    /// A top-left rect in the bottom-left space of an image `imageHeight` pixels tall.
    static func bottomLeft(_ topLeft: CGRect, imageHeight: Int) -> CGRect {
        flipped(topLeft, imageHeight: imageHeight)
    }

    /// A bottom-left rect in the model's top-left space. The inverse of `bottomLeft`.
    static func topLeft(_ bottomLeft: CGRect, imageHeight: Int) -> CGRect {
        flipped(bottomLeft, imageHeight: imageHeight)
    }

    private static func flipped(_ rect: CGRect, imageHeight: Int) -> CGRect {
        guard !rect.isNull else { return rect }
        return CGRect(x: rect.minX, y: CGFloat(imageHeight) - rect.maxY, width: rect.width, height: rect.height)
    }
}
```

`TidyShot/Editor/Geometry/EffectGeometry.swift`. The `default:` branch covers the drawings, so the 4b cases (ellipse, line, pencil, highlighter, text) need no change here:
```swift
import CoreGraphics

/// Which image pixels an effect reads, in the model's top-left image pixels. A tile depends on
/// the base and on every earlier effect whose tile meets its sample rect: `RedactionTileCache`
/// keys tiles by those effects, and `RedactionRenderer` composites their tiles beneath.
nonisolated enum EffectGeometry {
    /// A Gaussian blur reads this many sigmas beyond its rect.
    static let blurReachInSigmas: CGFloat = 3

    /// The pixels `effect`'s tile depends on, integral and clipped to the image:
    /// - blur: the rect grown by `ceil(3 * radius)` on every side;
    /// - pixelate: `mosaicRect(rect, block:)`, the whole cells the rect touches;
    /// - redact: the rect itself.
    ///
    /// A drawing has no tile and samples nothing: `.zero`. Compare the result with
    /// `ImageRects.integral(_:clippedTo:)` of an earlier effect's rect, the pixels its tile covers.
    static func sampleRect(of effect: Annotation, imageSize: CGSize) -> CGRect {
        switch effect {
        case .redact(let region, _):
            return ImageRects.integral(region.rect, clippedTo: imageSize)
        case .blur(let region, let radius):
            let reach = (blurReachInSigmas * radius).rounded(.up)
            return ImageRects.integral(region.rect.insetBy(dx: -reach, dy: -reach), clippedTo: imageSize)
        case .pixelate(let region, let block):
            return ImageRects.integral(mosaicRect(region.rect, block: block), clippedTo: imageSize)
        default:
            return .zero
        }
    }

    /// `rect` grown outward to whole `block` by `block` cells of a grid anchored at image pixel
    /// (0, 0), the top-left corner, so the cells under a region stay put while it is dragged.
    /// Not clipped to the image. `block` is a whole number of pixels; below 1 it counts as 1.
    /// In Core Image's bottom-left space this grid is anchored at y = image height, so a renderer
    /// moves `ImageRects.bottomLeft(mosaicRect(...))` to the origin before scaling by `1 / block`.
    static func mosaicRect(_ rect: CGRect, block: CGFloat) -> CGRect {
        guard !rect.isEmpty, !rect.isInfinite else { return .zero }
        let cell = max(block, 1)
        let minX = (rect.minX / cell).rounded(.down) * cell
        let minY = (rect.minY / cell).rounded(.down) * cell
        let maxX = (rect.maxX / cell).rounded(.up) * cell
        let maxY = (rect.maxY / cell).rounded(.up) * cell
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
}
```

`TidyShot/Editor/Geometry/EditorWindowGeometry.swift`:
```swift
import CoreGraphics

/// The editor window's first size and where it goes. Pure, so it is tested without windows.
/// Frames are AppKit screen rects (origin bottom left).
nonisolated enum EditorWindowGeometry {
    /// Space around the image at its natural size, in points; also the `inset` passed to
    /// `CanvasTransform.fitting`.
    static let inset: CGFloat = 24
    /// The smallest content size the editor opens at, in points.
    static let minimumContentSize = CGSize(width: 640, height: 420)
    /// The largest share of the visible frame the window's frame opens at.
    static let screenFraction: CGFloat = 0.9

    /// The content size for an image of `imagePixels` at `scale`: its natural point size plus
    /// `inset` on every side, rounded up to whole points, at least `minimumContentSize`, and
    /// small enough that the frame (content plus `chrome`, the title bar and toolbar) fits in
    /// 90 % of `visibleFrame`. On a screen too small for the minimum, the 90 % cap wins.
    static func initialContentSize(imagePixels: CGSize, scale: CGFloat, chrome: CGSize,
                                   visibleFrame: CGRect) -> CGSize {
        let scale = scale > 0 ? scale : 1
        let wantedWidth = (imagePixels.width / scale + 2 * inset).rounded(.up)
        let wantedHeight = (imagePixels.height / scale + 2 * inset).rounded(.up)
        let largestWidth = (visibleFrame.width * screenFraction - chrome.width).rounded(.down)
        let largestHeight = (visibleFrame.height * screenFraction - chrome.height).rounded(.down)
        return CGSize(width: min(max(wantedWidth, minimumContentSize.width), largestWidth),
                      height: min(max(wantedHeight, minimumContentSize.height), largestHeight))
    }

    /// A window frame of `size`: centred in `visibleFrame` when there is no `previous` editor,
    /// otherwise `offset` points right of and below `previous` (its top edge `offset` lower).
    /// Clamped inside `visibleFrame`; a frame larger than it keeps its top-left corner on screen
    /// so the title bar can be reached. The origin is rounded to whole points.
    static func cascaded(from previous: CGRect?, size: CGSize, visibleFrame: CGRect,
                         offset: CGFloat = 22) -> CGRect {
        let origin = previous.map { CGPoint(x: $0.minX + offset, y: $0.maxY - offset - size.height) }
            ?? CGPoint(x: visibleFrame.midX - size.width / 2, y: visibleFrame.midY - size.height / 2)
        let x = max(min(origin.x, visibleFrame.maxX - size.width), visibleFrame.minX)
        let y = min(max(origin.y, visibleFrame.minY), visibleFrame.maxY - size.height)
        return CGRect(x: x.rounded(), y: y.rounded(), width: size.width, height: size.height)
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run:
```bash
xcodegen generate && xcodebuild test -project TidyShot.xcodeproj -scheme TidyShot -destination 'platform=macOS' -derivedDataPath .build 2>&1 | grep -E "Test run with|error:|TEST"
```
Expected: no `error:` lines, `** TEST SUCCEEDED **`, and `Test run with 231 tests in 35 suites passed`. This task adds 19 tests in 4 new suites.

No hand check: this task has no UI. Task 10 checks zoom, pan and placement on screen.

- [ ] **Step 5: Commit**

```bash
git add TidyShot/Editor/Geometry/CanvasTransform.swift TidyShot/Editor/Geometry/ImageRects.swift TidyShot/Editor/Geometry/EffectGeometry.swift TidyShot/Editor/Geometry/EditorWindowGeometry.swift TidyShotTests/CanvasTransformTests.swift TidyShotTests/ImageRectsTests.swift TidyShotTests/EffectGeometryTests.swift TidyShotTests/EditorWindowGeometryTests.swift
git commit -m "feat: canvas transform and image-space geometry for the editor"
```

### Task 4: Drag, hit-test, arrow, key-routing and shortcut-table helpers (TDD)

**Files:**
- Create: `TidyShot/Editor/Geometry/DragGeometry.swift`
- Create: `TidyShot/Editor/Geometry/HitTester.swift`
- Create: `TidyShot/Editor/Geometry/ArrowGeometry.swift` (also holds `AnnotationGeometry`)
- Create: `TidyShot/Editor/Geometry/KeyRouting.swift` (also holds `EditorShortcut`)
- Test: `TidyShotTests/DragGeometryTests.swift`
- Test: `TidyShotTests/HitTesterTests.swift`
- Test: `TidyShotTests/ArrowGeometryTests.swift`
- Test: `TidyShotTests/KeyRoutingTests.swift`

No existing file changes. `xcodegen generate` picks the new files up.

**Interfaces:**
- Consumes (Task 2, `TidyShot/Editor/Model/`, all nonisolated):
  - `enum Annotation: Identifiable, Codable, Equatable, Sendable { case rectangle(ShapeBox), arrow(Segment), redact(Region, fill: RGBA), blur(Region, radius: CGFloat), pixelate(Region, block: CGFloat); var id: UUID }`.
  - `struct ShapeBox { let id: UUID; var rect: CGRect; var color: RGBA; var lineWidth: CGFloat }`, `struct Segment { let id: UUID; var from: CGPoint; var to: CGPoint; var color: RGBA; var lineWidth: CGFloat }`, `struct Region { let id: UUID; var rect: CGRect }`, each built in the tests with every member passed, `id` included.
  - `struct AnnotationDocument { var annotations: [Annotation]; var effects: [Annotation]; var drawings: [Annotation] }` (both lists in creation order), built in the tests as `AnnotationDocument(annotations:)`.
  - `enum EditorTool: CaseIterable { case select, redact, pixelate, blur, rectangle, arrow; var letter: Character; static func tool(forKey: Character) -> EditorTool? }`. `tool(forKey:)` ignores case.
  - `EditorPalette.lineWidthsPoints: [CGFloat] = [2, 3, 4, 6, 8, 12]`; the tests also use `EditorPalette.defaultStroke: RGBA`.
- Produces (all nonisolated, no AppKit import). Points, rects and lengths are image pixels with a top-left origin. `zoom` is `CanvasTransform.zoom` (Task 3), view points per image pixel.
  - `enum DragGeometry`:
    - `static let minimumDragPoints: CGFloat = 2`
    - `static func rect(from: CGPoint, to: CGPoint, square: Bool, fromCentre: Bool) -> CGRect`: standardized. `square` makes both sides the longer one and keeps the drag's quadrant; `fromCentre` treats `from` as the centre.
    - `static func segmentEnd(from: CGPoint, to: CGPoint, snap45: Bool) -> CGPoint`: with `snap45`, `to` projected onto the nearest multiple of 45 degrees around `from`.
    - `static func axisLocked(_ delta: CGVector) -> CGVector`: keeps the larger component (horizontal on a tie) and zeroes the other.
    - `static func isLargeEnough(_ rect: CGRect, zoom: CGFloat) -> Bool`: both sides at least `2 / zoom`. For the rect tools.
    - `static func isLongEnough(from: CGPoint, to: CGPoint, zoom: CGFloat) -> Bool`: length at least `2 / zoom`. For the two-point tools, so a horizontal arrow is kept.
  - `enum HitTester`:
    - `enum Hit: Equatable, Sendable { case body, handle(Int) }`
    - `static let tolerancePoints: CGFloat = 8`; `static func tolerance(zoom: CGFloat) -> CGFloat` (8 / zoom).
    - `static func handles(for: Annotation) -> [CGPoint]`: boxes (rectangle and every effect) have 8, clockwise from the top-left corner: 0 top-left, 1 top-middle, 2 top-right, 3 middle-right, 4 bottom-right, 5 bottom-middle, 6 bottom-left, 7 middle-left (top is minY). An arrow has 2: 0 the tail (`from`), 1 the head (`to`).
    - `static func hit(_: Annotation, at: CGPoint, tolerance: CGFloat) -> Hit?`: the nearest handle within `tolerance`, else the body. A rectangle's body is its stroke band (it is hollow), an arrow's is its shaft line within `lineWidth / 2 + tolerance`, and an effect's is its rect grown by `tolerance`.
    - `static func topmost(in: AnnotationDocument, at: CGPoint, tolerance: CGFloat) -> (id: UUID, hit: Hit)?`: first every handle, then every body, each pass over drawings front to back and then effects front to back.
    - `static func resized(_: Annotation, handle: Int, to: CGPoint, square: Bool) -> Annotation`: keeps the id, colour, width and effect parameter.
    - `static func resizedRect(_ rect: CGRect, handle: Int, to: CGPoint, square: Bool) -> CGRect`: the opposite corner or edge stays put; `square` applies to corner handles only. Crop (4b) can reuse it.
    - `static func distance(from: CGPoint, toSegment: CGPoint, _: CGPoint) -> CGFloat`.
  - `enum ArrowGeometry`:
    - `static let halfAngleDegrees: CGFloat = 28`
    - `static func headLength(from: CGPoint, to: CGPoint, lineWidth: CGFloat, scale: CGFloat) -> CGFloat`: `max(12 * scale, 4 * lineWidth)`, at most the arrow's length.
    - `static func head(from: CGPoint, to: CGPoint, lineWidth: CGFloat, scale: CGFloat) -> (tip: CGPoint, left: CGPoint, right: CGPoint)`: `tip` is `to`; `left` and `right` are the base corners on each side of the direction of travel.
    - `static func shaftEnd(from: CGPoint, to: CGPoint, lineWidth: CGFloat, scale: CGFloat) -> CGPoint`: half the head length back from the tip.
  - `enum AnnotationGeometry`:
    - `static let antialiasMargin: CGFloat = 1`
    - `static func bounds(of: Annotation, scale: CGFloat) -> CGRect`: everything the annotation paints, grown by `antialiasMargin`. Task 7 and the canvas use it for dirty rects.
  - `enum KeyRouting`:
    - `enum Action: Equatable, Sendable { case selectTool(EditorTool), lineWidth(index: Int), none }`. `index` indexes `EditorPalette.lineWidthsPoints`.
    - `static let nudgeStep: CGFloat = 1`; `static let shiftNudgeStep: CGFloat = 10`
    - `static func action(characters: String?, command: Bool, control: Bool, option: Bool, isEditingText: Bool) -> Action`
    - `static func nudge(dx: Int, dy: Int, shift: Bool) -> CGVector`: `dx` and `dy` are -1, 0 or 1; `dy: -1` is up.
  - `enum EditorShortcut: CaseIterable, Sendable`:
    - `case save, saveCopy, copy, copyImage, upload, uploadAsNew, undo, redo, close, zoomToFit, actualSize, zoomIn, zoomOut, selectAll`
    - `struct Chord: Hashable, Sendable { let key: String; var shift = false; var option = false }`; `var chord: Chord`. Command is always held, Control never.
    - `var selectorName: String`: `saveDocument:`, `saveDocumentCopy:`, `copy:`, `copyImage:`, `uploadDocument:`, `uploadDocumentAsNew:`, `undo:`, `redo:`, `performClose:`, `zoomToFit:`, `zoomToActualSize:`, `zoomIn:`, `zoomOut:`, `selectAll:`.
    - `var passesThroughWhileEditingText: Bool`: true for `copy`, `selectAll`, `undo`, `redo`.
    - `static func match(characters: String, command: Bool, shift: Bool, option: Bool, control: Bool, isEditingText: Bool) -> EditorShortcut?`. ⌘X has no case, so it never matches and always reaches the responder chain.
  - Both `KeyRouting.action` and `EditorShortcut.match` take `NSEvent.charactersIgnoringModifiers`, which keeps Shift (⇧1 arrives as `!`, ⇧⌘S as `S`) and drops Option (⌥⌘U arrives as `u`). Task 10 passes that property, with `?? ""` for `match`.

- [ ] **Step 1: Write the failing tests**

`TidyShotTests/DragGeometryTests.swift`:
```swift
import CoreGraphics
import Foundation
import Testing
@testable import TidyShot

struct DragGeometryTests {
    let start = CGPoint(x: 100, y: 100)

    /// Shift makes both sides the longer one, and the square grows toward the pointer in each axis.
    @Test func squareKeepsSignPerQuadrant() {
        func square(_ x: CGFloat, _ y: CGFloat) -> CGRect {
            DragGeometry.rect(from: start, to: CGPoint(x: x, y: y), square: true, fromCentre: false)
        }
        #expect(square(130, 110) == CGRect(x: 100, y: 100, width: 30, height: 30))
        #expect(square(70, 110) == CGRect(x: 70, y: 100, width: 30, height: 30))
        #expect(square(90, 60) == CGRect(x: 60, y: 60, width: 40, height: 40))
        #expect(square(140, 80) == CGRect(x: 100, y: 60, width: 40, height: 40))
        // Without Shift the rect follows the pointer, standardized for drags up and to the left.
        #expect(DragGeometry.rect(from: start, to: CGPoint(x: 130, y: 110), square: false, fromCentre: false)
                == CGRect(x: 100, y: 100, width: 30, height: 10))
        #expect(DragGeometry.rect(from: start, to: CGPoint(x: 70, y: 60), square: false, fromCentre: false)
                == CGRect(x: 70, y: 60, width: 30, height: 40))
    }

    /// Option draws from the centre: the pointer's offset is mirrored on the other side.
    @Test func fromCentreMirrors() {
        #expect(DragGeometry.rect(from: start, to: CGPoint(x: 130, y: 110), square: false, fromCentre: true)
                == CGRect(x: 70, y: 90, width: 60, height: 20))
        #expect(DragGeometry.rect(from: start, to: CGPoint(x: 70, y: 90), square: false, fromCentre: true)
                == CGRect(x: 70, y: 90, width: 60, height: 20))
        #expect(DragGeometry.rect(from: start, to: CGPoint(x: 130, y: 110), square: true, fromCentre: true)
                == CGRect(x: 70, y: 70, width: 60, height: 60))
        #expect(DragGeometry.rect(from: start, to: start, square: false, fromCentre: true)
                == CGRect(x: 100, y: 100, width: 0, height: 0))
    }

    /// The end is projected onto the nearest of the eight 45-degree directions around the start.
    @Test func snap45ToNearestOctant() {
        func snapped(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            DragGeometry.segmentEnd(from: start, to: CGPoint(x: x, y: y), snap45: true)
        }
        #expect(snapped(200, 110) == CGPoint(x: 200, y: 100))   // right
        #expect(snapped(10, 101) == CGPoint(x: 10, y: 100))     // left
        #expect(snapped(110, 30) == CGPoint(x: 100, y: 30))     // up (image y grows downward)
        #expect(snapped(160, 140) == CGPoint(x: 150, y: 150))   // down and right
        #expect(snapped(40, 170) == CGPoint(x: 35, y: 165))     // down and left
        #expect(snapped(30, 40) == CGPoint(x: 35, y: 35))       // up and left
        #expect(snapped(170, 20) == CGPoint(x: 175, y: 25))     // up and right
        #expect(DragGeometry.segmentEnd(from: start, to: CGPoint(x: 160, y: 140), snap45: false) == CGPoint(x: 160, y: 140))
        #expect(DragGeometry.segmentEnd(from: start, to: start, snap45: true) == start)
    }

    /// Shift during a move keeps the larger component of the total delta; a tie keeps horizontal.
    @Test func axisLockKeepsDominant() {
        #expect(DragGeometry.axisLocked(CGVector(dx: 12, dy: -5)) == CGVector(dx: 12, dy: 0))
        #expect(DragGeometry.axisLocked(CGVector(dx: 3, dy: -9)) == CGVector(dx: 0, dy: -9))
        #expect(DragGeometry.axisLocked(CGVector(dx: -4, dy: 4)) == CGVector(dx: -4, dy: 0))
        #expect(DragGeometry.axisLocked(CGVector(dx: 0, dy: 0)) == CGVector(dx: 0, dy: 0))
    }

    /// The minimum is 2 view points: 2 / zoom image pixels in each dimension for a rect, and in
    /// length for a segment.
    @Test func tinyDragRejectedRelativeToZoom() {
        #expect(!DragGeometry.isLargeEnough(CGRect(x: 0, y: 0, width: 1.5, height: 40), zoom: 1))
        #expect(!DragGeometry.isLargeEnough(CGRect(x: 0, y: 0, width: 40, height: 1), zoom: 1))
        #expect(DragGeometry.isLargeEnough(CGRect(x: 0, y: 0, width: 2, height: 2), zoom: 1))
        // A 2x capture at its natural size: 2 points are 4 pixels.
        #expect(!DragGeometry.isLargeEnough(CGRect(x: 0, y: 0, width: 3, height: 40), zoom: 0.5))
        #expect(DragGeometry.isLargeEnough(CGRect(x: 0, y: 0, width: 4, height: 4), zoom: 0.5))
        // Zoomed in to 4, half a pixel is enough.
        #expect(DragGeometry.isLargeEnough(CGRect(x: 0, y: 0, width: 0.5, height: 0.5), zoom: 4))
        // A negative size counts by its magnitude.
        #expect(DragGeometry.isLargeEnough(CGRect(x: 10, y: 10, width: -5, height: -5), zoom: 1))
        // A segment counts by its length, so a horizontal arrow (zero height) is kept.
        #expect(DragGeometry.isLongEnough(from: .zero, to: CGPoint(x: 3, y: 0), zoom: 1))
        #expect(!DragGeometry.isLongEnough(from: .zero, to: CGPoint(x: 1, y: 1), zoom: 1))
        #expect(!DragGeometry.isLongEnough(from: .zero, to: CGPoint(x: 3, y: 0), zoom: 0.5))
        #expect(DragGeometry.isLongEnough(from: .zero, to: CGPoint(x: 0, y: 0.6), zoom: 4))
    }
}
```

`TidyShotTests/HitTesterTests.swift`:
```swift
import CoreGraphics
import Foundation
import Testing
@testable import TidyShot

struct HitTesterTests {
    let red = EditorPalette.defaultStroke
    let id = UUID()
    /// minX 100, minY 50, maxX 300, maxY 150.
    let box = CGRect(x: 100, y: 50, width: 200, height: 100)

    func rectangle(_ rect: CGRect, lineWidth: CGFloat = 4, id: UUID = UUID()) -> Annotation {
        .rectangle(ShapeBox(id: id, rect: rect, color: red, lineWidth: lineWidth))
    }

    func arrow(_ from: CGPoint, _ to: CGPoint, lineWidth: CGFloat = 4, id: UUID = UUID()) -> Annotation {
        .arrow(Segment(id: id, from: from, to: to, color: red, lineWidth: lineWidth))
    }

    func blur(_ rect: CGRect, id: UUID = UUID()) -> Annotation {
        .blur(Region(id: id, rect: rect), radius: 16)
    }

    @Test func handlesBeforeBody() throws {
        let shape = rectangle(box)
        #expect(HitTester.handles(for: shape) == [
            CGPoint(x: 100, y: 50), CGPoint(x: 200, y: 50), CGPoint(x: 300, y: 50), CGPoint(x: 300, y: 100),
            CGPoint(x: 300, y: 150), CGPoint(x: 200, y: 150), CGPoint(x: 100, y: 150), CGPoint(x: 100, y: 100),
        ])
        // The corner is on the stroke too; the handle wins.
        #expect(HitTester.hit(shape, at: CGPoint(x: 101, y: 51), tolerance: 8) == .handle(0))
        #expect(HitTester.hit(shape, at: CGPoint(x: 200, y: 52), tolerance: 8) == .handle(1))
        #expect(HitTester.hit(shape, at: CGPoint(x: 150, y: 52), tolerance: 8) == .body)
        // On a small box several handles are in range; the nearest wins.
        let small = rectangle(CGRect(x: 0, y: 0, width: 10, height: 10))
        #expect(HitTester.hit(small, at: CGPoint(x: 1, y: 1), tolerance: 8) == .handle(0))
        #expect(HitTester.hit(small, at: CGPoint(x: 5, y: 1), tolerance: 8) == .handle(1))
        // Across the document every handle is tested before any body, so the corner of a blur
        // stays grabbable under an arrow that crosses it.
        let effect = blur(CGRect(x: 20, y: 20, width: 100, height: 60))
        let crossing = arrow(CGPoint(x: 120, y: 0), CGPoint(x: 120, y: 200))
        let document = AnnotationDocument(annotations: [effect, crossing])
        let found = try #require(HitTester.topmost(in: document, at: CGPoint(x: 121, y: 81), tolerance: 4))
        #expect(found.id == effect.id)
        #expect(found.hit == .handle(4))
    }

    /// The caller passes `tolerance(zoom:)`, 8 view points in image pixels.
    @Test func toleranceScalesWithZoomInput() {
        #expect(HitTester.tolerance(zoom: 1) == 8)
        #expect(HitTester.tolerance(zoom: 4) == 2)
        #expect(HitTester.tolerance(zoom: 0.5) == 16)
        let shape = rectangle(box)
        // 6 px above the top edge, far from any handle.
        #expect(HitTester.hit(shape, at: CGPoint(x: 150, y: 44), tolerance: HitTester.tolerance(zoom: 1)) == .body)
        #expect(HitTester.hit(shape, at: CGPoint(x: 150, y: 44), tolerance: HitTester.tolerance(zoom: 4)) == nil)
        // On the 4 px stroke, inside the rect.
        #expect(HitTester.hit(shape, at: CGPoint(x: 150, y: 53), tolerance: HitTester.tolerance(zoom: 4)) == .body)
        // A rectangle is hollow: its middle is not its body.
        #expect(HitTester.hit(shape, at: CGPoint(x: 200, y: 100), tolerance: HitTester.tolerance(zoom: 1)) == nil)
    }

    @Test func arrowHitsAlongSegmentWithinWidth() {
        let shaft = arrow(CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 0), lineWidth: 10)
        // Within lineWidth / 2 + tolerance = 7 of the line.
        #expect(HitTester.hit(shaft, at: CGPoint(x: 50, y: 6), tolerance: 2) == .body)
        #expect(HitTester.hit(shaft, at: CGPoint(x: 50, y: -7), tolerance: 2) == .body)
        #expect(HitTester.hit(shaft, at: CGPoint(x: 50, y: 8), tolerance: 2) == nil)
        // Past the ends the distance is to the nearest end.
        #expect(HitTester.hit(shaft, at: CGPoint(x: 106, y: 0), tolerance: 2) == .body)
        #expect(HitTester.hit(shaft, at: CGPoint(x: -8, y: 0), tolerance: 2) == nil)
        #expect(HitTester.distance(from: CGPoint(x: 50, y: 6), toSegment: CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 0)) == 6)
        #expect(HitTester.distance(from: CGPoint(x: 103, y: 4), toSegment: CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 0)) == 5)
        #expect(HitTester.distance(from: CGPoint(x: 8, y: 9), toSegment: CGPoint(x: 5, y: 5), CGPoint(x: 5, y: 5)) == 5)
    }

    /// Effects render beneath every drawing, so a drawing wins even over a later effect.
    @Test func topmostPrefersDrawingOverEffectBeneath() throws {
        let shape = rectangle(box)
        let effect = blur(CGRect(x: 0, y: 0, width: 400, height: 300))
        let document = AnnotationDocument(annotations: [shape, effect])
        let onStroke = try #require(HitTester.topmost(in: document, at: CGPoint(x: 150, y: 51), tolerance: 8))
        #expect(onStroke.id == shape.id)
        #expect(onStroke.hit == .body)
        // Of two drawings, the later one is in front.
        let first = arrow(CGPoint(x: 0, y: 100), CGPoint(x: 300, y: 100))
        let second = arrow(CGPoint(x: 150, y: 0), CGPoint(x: 150, y: 300))
        let crossed = try #require(HitTester.topmost(in: AnnotationDocument(annotations: [first, second]),
                                                     at: CGPoint(x: 150, y: 100), tolerance: 8))
        #expect(crossed.id == second.id)
    }

    @Test func effectSelectableOutsideDrawing() throws {
        let shape = rectangle(box)
        let effect = blur(CGRect(x: 0, y: 0, width: 400, height: 300))
        let document = AnnotationDocument(annotations: [shape, effect])
        let tolerance = HitTester.tolerance(zoom: 1)
        // Inside the hollow rectangle, the blur beneath is what is hit.
        let inside = try #require(HitTester.topmost(in: document, at: CGPoint(x: 200, y: 100), tolerance: tolerance))
        #expect(inside.id == effect.id)
        #expect(inside.hit == .body)
        #expect(HitTester.topmost(in: document, at: CGPoint(x: 350, y: 250), tolerance: tolerance)?.id == effect.id)
        #expect(HitTester.topmost(in: document, at: CGPoint(x: 500, y: 500), tolerance: tolerance) == nil)
        // Of two effects, the later one is in front.
        let later: Annotation = .pixelate(Region(id: UUID(), rect: CGRect(x: 50, y: 50, width: 100, height: 100)), block: 10)
        let stacked = AnnotationDocument(annotations: [effect, later])
        #expect(HitTester.topmost(in: stacked, at: CGPoint(x: 100, y: 100), tolerance: tolerance)?.id == later.id)
    }

    @Test func resizedByEachOfEightHandles() {
        let cases: [(handle: Int, point: CGPoint, expected: CGRect)] = [
            (0, CGPoint(x: 80, y: 40), CGRect(x: 80, y: 40, width: 220, height: 110)),
            (1, CGPoint(x: 999, y: 30), CGRect(x: 100, y: 30, width: 200, height: 120)),
            (2, CGPoint(x: 320, y: 40), CGRect(x: 100, y: 40, width: 220, height: 110)),
            (3, CGPoint(x: 350, y: 999), CGRect(x: 100, y: 50, width: 250, height: 100)),
            (4, CGPoint(x: 320, y: 170), CGRect(x: 100, y: 50, width: 220, height: 120)),
            (5, CGPoint(x: 0, y: 180), CGRect(x: 100, y: 50, width: 200, height: 130)),
            (6, CGPoint(x: 90, y: 160), CGRect(x: 90, y: 50, width: 210, height: 110)),
            (7, CGPoint(x: 60, y: 0), CGRect(x: 60, y: 50, width: 240, height: 100)),
        ]
        for item in cases {
            #expect(HitTester.resized(rectangle(box, id: id), handle: item.handle, to: item.point, square: false)
                    == rectangle(item.expected, id: id))
        }
        // Dragging past the opposite corner flips the rect.
        #expect(HitTester.resizedRect(box, handle: 4, to: CGPoint(x: 40, y: 20), square: false)
                == CGRect(x: 40, y: 20, width: 60, height: 30))
        // Shift squares a corner drag and leaves an edge drag alone.
        #expect(HitTester.resizedRect(box, handle: 4, to: CGPoint(x: 400, y: 100), square: true)
                == CGRect(x: 100, y: 50, width: 300, height: 300))
        #expect(HitTester.resizedRect(box, handle: 3, to: CGPoint(x: 350, y: 0), square: true)
                == CGRect(x: 100, y: 50, width: 250, height: 100))
        #expect(HitTester.resizedRect(box, handle: 8, to: .zero, square: false) == box)
        // Effects keep their id and parameter.
        #expect(HitTester.resized(blur(box, id: id), handle: 4, to: CGPoint(x: 320, y: 170), square: false)
                == blur(CGRect(x: 100, y: 50, width: 220, height: 120), id: id))
        let fill = EditorPalette.defaultRedact
        #expect(HitTester.resized(.redact(Region(id: id, rect: box), fill: fill), handle: 0, to: CGPoint(x: 80, y: 40), square: false)
                == .redact(Region(id: id, rect: CGRect(x: 80, y: 40, width: 220, height: 110)), fill: fill))
    }

    @Test func arrowEndpointHandlesMoveEnds() {
        let original = arrow(CGPoint(x: 10, y: 10), CGPoint(x: 100, y: 10), lineWidth: 6, id: id)
        #expect(HitTester.handles(for: original) == [CGPoint(x: 10, y: 10), CGPoint(x: 100, y: 10)])
        #expect(HitTester.hit(original, at: CGPoint(x: 99, y: 12), tolerance: 8) == .handle(1))
        #expect(HitTester.hit(original, at: CGPoint(x: 12, y: 9), tolerance: 8) == .handle(0))
        #expect(HitTester.resized(original, handle: 1, to: CGPoint(x: 120, y: 40), square: false)
                == arrow(CGPoint(x: 10, y: 10), CGPoint(x: 120, y: 40), lineWidth: 6, id: id))
        #expect(HitTester.resized(original, handle: 0, to: CGPoint(x: 0, y: 0), square: false)
                == arrow(CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 10), lineWidth: 6, id: id))
        // Shift snaps the moved end to 45 degrees around the other end.
        #expect(HitTester.resized(original, handle: 1, to: CGPoint(x: 200, y: 15), square: true)
                == arrow(CGPoint(x: 10, y: 10), CGPoint(x: 200, y: 10), lineWidth: 6, id: id))
        #expect(HitTester.resized(original, handle: 0, to: CGPoint(x: 40, y: -45), square: true)
                == arrow(CGPoint(x: 42.5, y: -47.5), CGPoint(x: 100, y: 10), lineWidth: 6, id: id))
    }
}
```

`TidyShotTests/ArrowGeometryTests.swift`:
```swift
import CoreGraphics
import Foundation
import Testing
@testable import TidyShot

struct ArrowGeometryTests {
    let halfAngle = 28 * CGFloat.pi / 180

    func near(_ a: CGPoint, _ b: CGPoint) -> Bool {
        hypot(a.x - b.x, a.y - b.y) < 1e-6
    }

    func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        hypot(a.x - b.x, a.y - b.y)
    }

    @Test func headSymmetricAboutShaft() {
        // Length 125 along (0.8, 0.6); the head is max(12 * 2, 4 * 4) = 24 long.
        let from = CGPoint(x: 10, y: 20)
        let to = CGPoint(x: 110, y: 95)
        let head = ArrowGeometry.head(from: from, to: to, lineWidth: 4, scale: 2)
        #expect(head.tip == to)
        #expect(abs(distance(head.tip, head.left) - distance(head.tip, head.right)) < 1e-9)
        // The base's midpoint is on the shaft, 24 px back from the tip, and the base is square to it.
        let middle = CGPoint(x: (head.left.x + head.right.x) / 2, y: (head.left.y + head.right.y) / 2)
        #expect(near(middle, CGPoint(x: 110 - 0.8 * 24, y: 95 - 0.6 * 24)))
        #expect(abs((head.right.x - head.left.x) * 0.8 + (head.right.y - head.left.y) * 0.6) < 1e-9)
        // Pointing right, left is up, because image y grows downward.
        let flat = ArrowGeometry.head(from: CGPoint(x: 0, y: 100), to: CGPoint(x: 200, y: 100), lineWidth: 8, scale: 2)
        #expect(flat.left.y < 100 && flat.right.y > 100)
        #expect(abs(flat.left.x - 168) < 1e-9 && abs(flat.right.x - 168) < 1e-9)
    }

    /// Length max(12 * scale, 4 * lineWidth), half-angle 28 degrees.
    @Test func headScalesWithLineWidthAndScale() {
        let cases: [(lineWidth: CGFloat, scale: CGFloat, expected: CGFloat)] = [
            (2, 1, 12), (4, 1, 16), (2, 2, 24), (8, 2, 32), (24, 2, 96),
        ]
        for item in cases {
            let to = CGPoint(x: 400, y: 0)
            let head = ArrowGeometry.head(from: .zero, to: to, lineWidth: item.lineWidth, scale: item.scale)
            #expect(abs((400 - head.left.x) - item.expected) < 1e-9)
            #expect(abs(ArrowGeometry.headLength(from: .zero, to: to, lineWidth: item.lineWidth, scale: item.scale) - item.expected) < 1e-9)
            #expect(abs(atan2(abs(head.left.y), 400 - head.left.x) - halfAngle) < 1e-9)
        }
    }

    @Test func shaftStopsBeforeTip() {
        let from = CGPoint(x: 0, y: 100)
        let to = CGPoint(x: 200, y: 100)
        let head = ArrowGeometry.head(from: from, to: to, lineWidth: 8, scale: 2)
        let end = ArrowGeometry.shaftEnd(from: from, to: to, lineWidth: 8, scale: 2)
        // Half of the 32 px head back from the tip: past the head's base, short of the tip.
        #expect(near(end, CGPoint(x: 184, y: 100)))
        #expect(end.x > head.left.x && end.x < head.tip.x)
        // The 4 px round cap stays inside the triangle.
        #expect(HitTester.distance(from: end, toSegment: head.tip, head.left) >= 4)
        #expect(HitTester.distance(from: end, toSegment: head.tip, head.right) >= 4)
        // An arrow shorter than its head: the head shrinks to the arrow and the shaft stops halfway.
        let short = ArrowGeometry.head(from: .zero, to: CGPoint(x: 10, y: 0), lineWidth: 8, scale: 2)
        #expect(abs(short.left.x) < 1e-9 && abs(short.right.x) < 1e-9)
        #expect(near(ArrowGeometry.shaftEnd(from: .zero, to: CGPoint(x: 10, y: 0), lineWidth: 8, scale: 2), CGPoint(x: 5, y: 0)))
        // A zero-length arrow collapses to its tip.
        let point = CGPoint(x: 7, y: 7)
        let collapsed = ArrowGeometry.head(from: point, to: point, lineWidth: 8, scale: 2)
        #expect(collapsed.tip == point && collapsed.left == point && collapsed.right == point)
        #expect(ArrowGeometry.shaftEnd(from: point, to: point, lineWidth: 8, scale: 2) == point)
    }

    @Test func boundsContainHead() {
        let red = EditorPalette.defaultStroke
        let flat = Segment(id: UUID(), from: CGPoint(x: 0, y: 100), to: CGPoint(x: 200, y: 100), color: red, lineWidth: 8)
        let diagonal = Segment(id: UUID(), from: CGPoint(x: 50, y: 60), to: CGPoint(x: 10, y: 20), color: red, lineWidth: 6)
        for segment in [flat, diagonal] {
            let bounds = AnnotationGeometry.bounds(of: .arrow(segment), scale: 2)
            let head = ArrowGeometry.head(from: segment.from, to: segment.to, lineWidth: segment.lineWidth, scale: 2)
            for point in [head.tip, head.left, head.right] {
                #expect(bounds.contains(point))
            }
            // The tail's round cap.
            let cap = segment.lineWidth / 2
            #expect(bounds.contains(CGRect(x: segment.from.x - cap, y: segment.from.y - cap, width: 2 * cap, height: 2 * cap)))
        }
        // The head is wider than the shaft: about 17 px each side of a flat 8 px arrow.
        #expect(AnnotationGeometry.bounds(of: .arrow(flat), scale: 2).minY < 100 - 17)
        // A rectangle's stroke sits inside its rect, and an effect paints its rect.
        let rect = CGRect(x: 10, y: 20, width: 30, height: 40)
        let margin = AnnotationGeometry.antialiasMargin
        #expect(AnnotationGeometry.bounds(of: .rectangle(ShapeBox(id: UUID(), rect: rect, color: red, lineWidth: 4)), scale: 2)
                == rect.insetBy(dx: -margin, dy: -margin))
        #expect(AnnotationGeometry.bounds(of: .blur(Region(id: UUID(), rect: rect), radius: 16), scale: 2)
                == rect.insetBy(dx: -margin, dy: -margin))
    }
}
```

`TidyShotTests/KeyRoutingTests.swift`:
```swift
import CoreGraphics
import Foundation
import Testing
@testable import TidyShot

struct KeyRoutingTests {
    /// Spelled out, because `.none` reads as `Optional.none` in an optional context.
    let ignored = KeyRouting.Action.none

    func action(_ characters: String?, command: Bool = false, control: Bool = false, option: Bool = false,
                editing: Bool = false) -> KeyRouting.Action {
        KeyRouting.action(characters: characters, command: command, control: control, option: option, isEditingText: editing)
    }

    func matched(_ characters: String, shift: Bool = false, option: Bool = false, command: Bool = true,
                 control: Bool = false, editing: Bool = false) -> EditorShortcut? {
        EditorShortcut.match(characters: characters, command: command, shift: shift, option: option, control: control,
                             isEditingText: editing)
    }

    @Test func lettersSelectTools() {
        let expected: [(String, EditorTool)] = [
            ("v", .select), ("d", .redact), ("x", .pixelate), ("b", .blur), ("r", .rectangle), ("a", .arrow),
        ]
        for (key, tool) in expected {
            #expect(action(key) == .selectTool(tool))
            // With Shift, charactersIgnoringModifiers gives the capital.
            #expect(action(key.uppercased()) == .selectTool(tool))
        }
        for tool in EditorTool.allCases {
            #expect(action(String(tool.letter)) == .selectTool(tool))
        }
        #expect(action("q") == ignored)
        #expect(action(nil) == ignored)
        #expect(action("") == ignored)
        #expect(action("vd") == ignored)
    }

    @Test func digitsOneToSixPickWidths() {
        for digit in 1...6 {
            #expect(action(String(digit)) == .lineWidth(index: digit - 1))
        }
        #expect(EditorPalette.lineWidthsPoints == [2, 3, 4, 6, 8, 12])
        #expect(action("5") == .lineWidth(index: 4))
        #expect(EditorPalette.lineWidthsPoints[4] == 8)
        for key in ["0", "7", "8", "9"] {
            #expect(action(key) == ignored)
        }
        // Shift-1 arrives as "!".
        #expect(action("!") == ignored)
    }

    /// ⌘1 is Actual Size in the shortcut table, never a line width.
    @Test func modifiersSuppressLetters() {
        #expect(action("v", command: true) == ignored)
        #expect(action("v", control: true) == ignored)
        #expect(action("v", option: true) == ignored)
        #expect(action("1", command: true) == ignored)
        #expect(action("2", option: true) == ignored)
    }

    @Test func editingTextSuppressesLetters() {
        for tool in EditorTool.allCases {
            #expect(action(String(tool.letter), editing: true) == ignored)
        }
        for digit in 1...6 {
            #expect(action(String(digit), editing: true) == ignored)
        }
    }

    @Test func nudgeOneOrTenPixels() {
        #expect(KeyRouting.nudge(dx: 1, dy: 0, shift: false) == CGVector(dx: 1, dy: 0))
        #expect(KeyRouting.nudge(dx: -1, dy: 0, shift: false) == CGVector(dx: -1, dy: 0))
        // Up is -1, because image y grows downward.
        #expect(KeyRouting.nudge(dx: 0, dy: -1, shift: false) == CGVector(dx: 0, dy: -1))
        #expect(KeyRouting.nudge(dx: 0, dy: 1, shift: true) == CGVector(dx: 0, dy: 10))
        #expect(KeyRouting.nudge(dx: -1, dy: 0, shift: true) == CGVector(dx: -10, dy: 0))
    }

    /// The 4a table from spec 2.6. Characters are as charactersIgnoringModifiers gives them.
    @Test func shortcutTableMatchesExpectedChords() {
        let expected: [(characters: String, shift: Bool, option: Bool, shortcut: EditorShortcut, selector: String)] = [
            ("s", false, false, .save, "saveDocument:"),
            ("S", true, false, .saveCopy, "saveDocumentCopy:"),
            ("c", false, false, .copy, "copy:"),
            ("C", true, false, .copyImage, "copyImage:"),
            ("u", false, false, .upload, "uploadDocument:"),
            ("u", false, true, .uploadAsNew, "uploadDocumentAsNew:"),
            ("z", false, false, .undo, "undo:"),
            ("Z", true, false, .redo, "redo:"),
            ("w", false, false, .close, "performClose:"),
            ("0", false, false, .zoomToFit, "zoomToFit:"),
            ("1", false, false, .actualSize, "zoomToActualSize:"),
            ("=", false, false, .zoomIn, "zoomIn:"),
            ("-", false, false, .zoomOut, "zoomOut:"),
            ("a", false, false, .selectAll, "selectAll:"),
        ]
        for row in expected {
            #expect(matched(row.characters, shift: row.shift, option: row.option) == row.shortcut)
            #expect(row.shortcut.selectorName == row.selector)
        }
        #expect(expected.count == EditorShortcut.allCases.count)
        // ⌘X has no row: Phase 4 has no object cut, so it always reaches the responder chain.
        #expect(matched("x") == nil)
        #expect(matched("X", shift: true) == nil)
        // Command is required, Control rules a chord out, and an extra modifier is another chord.
        #expect(matched("s", command: false) == nil)
        #expect(matched("s", control: true) == nil)
        #expect(matched("s", option: true) == nil)
        #expect(matched("w", shift: true) == nil)
        #expect(matched("U", shift: true, option: true) == nil)
    }

    @Test func shortcutTableHasNoDuplicateChords() {
        let chords = EditorShortcut.allCases.map(\.chord)
        #expect(Set(chords).count == chords.count)
        let selectors = EditorShortcut.allCases.map(\.selectorName)
        #expect(Set(selectors).count == selectors.count)
        // Every row's own chord reaches it.
        for shortcut in EditorShortcut.allCases {
            #expect(EditorShortcut.match(characters: shortcut.chord.key, command: true, shift: shortcut.chord.shift,
                                         option: shortcut.chord.option, control: false, isEditingText: false) == shortcut)
        }
    }

    /// While a text annotation is edited (4b), ⌘C, ⌘A, ⌘Z and ⇧⌘Z go to the NSTextView.
    @Test func editingTextPassesClipboardAndUndoChordsThrough() {
        #expect(Set(EditorShortcut.allCases.filter(\.passesThroughWhileEditingText)) == [.copy, .selectAll, .undo, .redo])
        for shortcut in EditorShortcut.allCases {
            let expected: EditorShortcut? = shortcut.passesThroughWhileEditingText ? nil : shortcut
            #expect(EditorShortcut.match(characters: shortcut.chord.key, command: true, shift: shortcut.chord.shift,
                                         option: shortcut.chord.option, control: false, isEditingText: true) == expected)
        }
        #expect(matched("c", editing: true) == nil)
        #expect(matched("a", editing: true) == nil)
        #expect(matched("z", editing: true) == nil)
        #expect(matched("Z", shift: true, editing: true) == nil)
        // Save, Copy Image, Upload, Close and Zoom still match.
        #expect(matched("s", editing: true) == .save)
        #expect(matched("C", shift: true, editing: true) == .copyImage)
        #expect(matched("u", editing: true) == .upload)
        #expect(matched("w", editing: true) == .close)
        #expect(matched("0", editing: true) == .zoomToFit)
        // ⌘X has no row, so it reaches the text view as well.
        #expect(matched("x", editing: true) == nil)
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run:
```bash
xcodegen generate && xcodebuild test -project TidyShot.xcodeproj -scheme TidyShot -destination 'platform=macOS' -derivedDataPath .build 2>&1 | grep -E "Test run with|error:|TEST"
```
Expected: compile errors, among them `cannot find 'DragGeometry' in scope`, `cannot find 'HitTester' in scope`, `cannot find 'ArrowGeometry' in scope`, `cannot find 'KeyRouting' in scope` and `cannot find 'EditorShortcut' in scope`, then `** TEST FAILED **`. No `Test run with` line.

- [ ] **Step 3: Write the drag constraints**

`TidyShot/Editor/Geometry/DragGeometry.swift`:
```swift
import CoreGraphics
import Foundation

/// Shift and Option constraints on a pointer drag, and the minimum drag. Points are image pixels
/// with a top-left origin; `zoom` is view points per image pixel.
nonisolated enum DragGeometry {
    /// A drag shorter than this many view points is a click: 2 / zoom image pixels.
    static let minimumDragPoints: CGFloat = 2

    /// The rect a drag spans, standardized. `square` (Shift) makes both sides the longer one and
    /// grows toward the pointer in each axis, so the square stays in the drag's quadrant.
    /// `fromCentre` (Option) treats `from` as the centre and mirrors the pointer's offset.
    static func rect(from: CGPoint, to: CGPoint, square: Bool, fromCentre: Bool) -> CGRect {
        var dx = to.x - from.x
        var dy = to.y - from.y
        if square {
            let side = max(abs(dx), abs(dy))
            dx = dx < 0 ? -side : side
            dy = dy < 0 ? -side : side
        }
        if fromCentre {
            return CGRect(x: from.x - abs(dx), y: from.y - abs(dy), width: 2 * abs(dx), height: 2 * abs(dy))
        }
        return CGRect(x: from.x, y: from.y, width: dx, height: dy).standardized
    }

    /// The end of a two-point drag. With `snap45` (Shift), `to` is projected onto the nearest of
    /// the eight 45-degree directions around `from`: a horizontal or vertical snap keeps the
    /// pointer's x or y, and a diagonal snap keeps the mean of the two offsets.
    static func segmentEnd(from: CGPoint, to: CGPoint, snap45: Bool) -> CGPoint {
        let dx = to.x - from.x
        let dy = to.y - from.y
        guard snap45, dx != 0 || dy != 0 else { return to }
        // 0 is right, 2 is down (image y grows downward), 4 is left, 6 is up.
        let octant = (Int((atan2(dy, dx) / (.pi / 4)).rounded()) + 8) % 8
        switch octant {
        case 0, 4:
            return CGPoint(x: to.x, y: from.y)
        case 2, 6:
            return CGPoint(x: from.x, y: to.y)
        default:
            let sx: CGFloat = octant == 1 || octant == 7 ? 1 : -1
            let sy: CGFloat = octant == 1 || octant == 3 ? 1 : -1
            let offset = (dx * sx + dy * sy) / 2
            return CGPoint(x: from.x + sx * offset, y: from.y + sy * offset)
        }
    }

    /// Shift during a move: the larger component of the total delta since mouseDown, the other
    /// zeroed. A tie keeps the horizontal one.
    static func axisLocked(_ delta: CGVector) -> CGVector {
        abs(delta.dx) >= abs(delta.dy) ? CGVector(dx: delta.dx, dy: 0) : CGVector(dx: 0, dy: delta.dy)
    }

    /// For the rect tools: both sides at least `minimumDragPoints / zoom`. `CGRect.width` and
    /// `height` are magnitudes, so an unstandardized rect works too.
    static func isLargeEnough(_ rect: CGRect, zoom: CGFloat) -> Bool {
        let minimum = minimumDragPoints / zoom
        return rect.width >= minimum && rect.height >= minimum
    }

    /// For the two-point tools: the segment at least `minimumDragPoints / zoom` long, so a
    /// horizontal or vertical arrow is kept.
    static func isLongEnough(from: CGPoint, to: CGPoint, zoom: CGFloat) -> Bool {
        hypot(to.x - from.x, to.y - from.y) >= minimumDragPoints / zoom
    }
}
```

- [ ] **Step 4: Write the hit tester**

`TidyShot/Editor/Geometry/HitTester.swift`. The switches over `Annotation` are exhaustive with no `default`, so each 4b annotation case fails to compile here until it has handles, a body and a resize.
```swift
import CoreGraphics
import Foundation

/// What a click on the canvas lands on. Points are image pixels with a top-left origin; the
/// caller converts the tolerance from view points with `tolerance(zoom:)`.
nonisolated enum HitTester {
    enum Hit: Equatable, Sendable {
        /// The annotation itself: a drag moves it.
        case body
        /// A handle, by its index in `handles(for:)`: a drag resizes.
        case handle(Int)
    }

    /// The hit tolerance in view points, the same at every zoom.
    static let tolerancePoints: CGFloat = 8

    /// `tolerancePoints` in image pixels at `zoom` (view points per image pixel).
    static func tolerance(zoom: CGFloat) -> CGFloat {
        tolerancePoints / zoom
    }

    /// Boxes (the rectangle and every effect) have eight handles, clockwise from the top-left
    /// corner: 0 top-left, 1 top-middle, 2 top-right, 3 middle-right, 4 bottom-right,
    /// 5 bottom-middle, 6 bottom-left, 7 middle-left. Top is minY. An arrow has two: 0 the tail
    /// (`from`) and 1 the head (`to`).
    static func handles(for annotation: Annotation) -> [CGPoint] {
        switch annotation {
        case .rectangle(let shape):
            boxHandles(shape.rect)
        case .redact(let region, _), .blur(let region, _), .pixelate(let region, _):
            boxHandles(region.rect)
        case .arrow(let segment):
            [segment.from, segment.to]
        }
    }

    /// The nearest handle within `tolerance`, else the body, else nil.
    static func hit(_ annotation: Annotation, at point: CGPoint, tolerance: CGFloat) -> Hit? {
        if let index = handleIndex(of: annotation, at: point, tolerance: tolerance) {
            return .handle(index)
        }
        return bodyContains(annotation, point, tolerance: tolerance) ? .body : nil
    }

    /// Two passes, every handle first and then every body, each over the drawings front to back
    /// and then the effects front to back. Effects render beneath every drawing, so a drawing
    /// wins over an effect created after it, and a handle wins over a body in front of it.
    static func topmost(in document: AnnotationDocument, at point: CGPoint, tolerance: CGFloat) -> (id: UUID, hit: Hit)? {
        let frontToBack = Array((document.effects + document.drawings).reversed())
        for annotation in frontToBack {
            if let index = handleIndex(of: annotation, at: point, tolerance: tolerance) {
                return (annotation.id, .handle(index))
            }
        }
        for annotation in frontToBack where bodyContains(annotation, point, tolerance: tolerance) {
            return (annotation.id, .body)
        }
        return nil
    }

    /// The annotation with handle `handle` dragged to `point`. A box handle goes through
    /// `resizedRect`; an arrow end moves, snapped to 45 degrees around the other end when
    /// `square` (Shift) is held. Id, colour, line width and effect parameter are kept.
    static func resized(_ annotation: Annotation, handle: Int, to point: CGPoint, square: Bool) -> Annotation {
        switch annotation {
        case .rectangle(var shape):
            shape.rect = resizedRect(shape.rect, handle: handle, to: point, square: square)
            return .rectangle(shape)
        case .arrow(var segment):
            switch handle {
            case 0: segment.from = DragGeometry.segmentEnd(from: segment.to, to: point, snap45: square)
            case 1: segment.to = DragGeometry.segmentEnd(from: segment.from, to: point, snap45: square)
            default: break
            }
            return .arrow(segment)
        case .redact(var region, let fill):
            region.rect = resizedRect(region.rect, handle: handle, to: point, square: square)
            return .redact(region, fill: fill)
        case .blur(var region, let radius):
            region.rect = resizedRect(region.rect, handle: handle, to: point, square: square)
            return .blur(region, radius: radius)
        case .pixelate(var region, let block):
            region.rect = resizedRect(region.rect, handle: handle, to: point, square: square)
            return .pixelate(region, block: block)
        }
    }

    /// `rect` with box handle `handle` dragged to `point`, standardized. The opposite corner (for
    /// a corner handle) or edge (for an edge handle) stays put. `square` applies to corner
    /// handles only, as in `DragGeometry.rect`. Any other index returns `rect`.
    static func resizedRect(_ rect: CGRect, handle: Int, to point: CGPoint, square: Bool) -> CGRect {
        let r = rect.standardized
        func span(_ anchor: CGPoint, _ moving: CGPoint, square: Bool = false) -> CGRect {
            DragGeometry.rect(from: anchor, to: moving, square: square, fromCentre: false)
        }
        switch handle {
        case 0: return span(CGPoint(x: r.maxX, y: r.maxY), point, square: square)
        case 1: return span(CGPoint(x: r.maxX, y: r.maxY), CGPoint(x: r.minX, y: point.y))
        case 2: return span(CGPoint(x: r.minX, y: r.maxY), point, square: square)
        case 3: return span(CGPoint(x: r.minX, y: r.minY), CGPoint(x: point.x, y: r.maxY))
        case 4: return span(CGPoint(x: r.minX, y: r.minY), point, square: square)
        case 5: return span(CGPoint(x: r.minX, y: r.minY), CGPoint(x: r.maxX, y: point.y))
        case 6: return span(CGPoint(x: r.maxX, y: r.minY), point, square: square)
        case 7: return span(CGPoint(x: r.maxX, y: r.maxY), CGPoint(x: point.x, y: r.minY))
        default: return r
        }
    }

    /// The distance from `point` to the segment from `a` to `b`; to `a` when they are equal.
    static func distance(from point: CGPoint, toSegment a: CGPoint, _ b: CGPoint) -> CGFloat {
        let abx = b.x - a.x
        let aby = b.y - a.y
        let lengthSquared = abx * abx + aby * aby
        guard lengthSquared > 0 else { return hypot(point.x - a.x, point.y - a.y) }
        let t = min(max(((point.x - a.x) * abx + (point.y - a.y) * aby) / lengthSquared, 0), 1)
        return hypot(point.x - (a.x + t * abx), point.y - (a.y + t * aby))
    }

    private static func boxHandles(_ rect: CGRect) -> [CGPoint] {
        let r = rect.standardized
        return [
            CGPoint(x: r.minX, y: r.minY), CGPoint(x: r.midX, y: r.minY),
            CGPoint(x: r.maxX, y: r.minY), CGPoint(x: r.maxX, y: r.midY),
            CGPoint(x: r.maxX, y: r.maxY), CGPoint(x: r.midX, y: r.maxY),
            CGPoint(x: r.minX, y: r.maxY), CGPoint(x: r.minX, y: r.midY),
        ]
    }

    /// The nearest handle within `tolerance` of `point`.
    private static func handleIndex(of annotation: Annotation, at point: CGPoint, tolerance: CGFloat) -> Int? {
        var best: (index: Int, distance: CGFloat)?
        for (index, handle) in handles(for: annotation).enumerated() {
            let distance = hypot(point.x - handle.x, point.y - handle.y)
            if distance <= tolerance, distance < (best?.distance ?? .infinity) {
                best = (index, distance)
            }
        }
        return best?.index
    }

    /// A rectangle is hollow: its body is the stroke band, from `tolerance` outside the rect to
    /// `lineWidth + tolerance` inside it (the stroke sits inside the rect). An arrow's body is its
    /// shaft line within `lineWidth / 2 + tolerance`. An effect is filled: its rect grown by
    /// `tolerance`.
    private static func bodyContains(_ annotation: Annotation, _ point: CGPoint, tolerance: CGFloat) -> Bool {
        switch annotation {
        case .rectangle(let shape):
            let rect = shape.rect.standardized
            let outer = rect.insetBy(dx: -tolerance, dy: -tolerance)
            let inner = rect.insetBy(dx: shape.lineWidth + tolerance, dy: shape.lineWidth + tolerance)
            return outer.contains(point) && !inner.contains(point)
        case .arrow(let segment):
            return distance(from: point, toSegment: segment.from, segment.to) <= segment.lineWidth / 2 + tolerance
        case .redact(let region, _), .blur(let region, _), .pixelate(let region, _):
            return region.rect.standardized.insetBy(dx: -tolerance, dy: -tolerance).contains(point)
        }
    }
}
```
`insetBy` past the middle returns `CGRect.null`, which contains nothing, so a rectangle thinner than its stroke band is hit everywhere inside.

- [ ] **Step 5: Write the arrow geometry and annotation bounds**

`TidyShot/Editor/Geometry/ArrowGeometry.swift`:
```swift
import CoreGraphics
import Foundation

/// The arrow's filled head and the end of its round-capped shaft, in image pixels. `scale` is the
/// capture scale, so a 2x capture gets a head twice as many pixels long.
nonisolated enum ArrowGeometry {
    /// Half the angle at the tip.
    static let halfAngleDegrees: CGFloat = 28

    /// The head's length along the shaft: max(12 * scale, 4 * lineWidth), but never longer than
    /// the arrow, so a short arrow's head ends at its tail.
    static func headLength(from: CGPoint, to: CGPoint, lineWidth: CGFloat, scale: CGFloat) -> CGFloat {
        min(max(12 * scale, 4 * lineWidth), hypot(to.x - from.x, to.y - from.y))
    }

    /// The head triangle. `tip` is `to`. `left` and `right` are the corners of the base, which is
    /// square to the shaft `headLength` back from the tip; left and right are as seen travelling
    /// from `from` to `to` with y growing downward. A zero-length arrow gives three equal points.
    static func head(from: CGPoint, to: CGPoint, lineWidth: CGFloat, scale: CGFloat) -> (tip: CGPoint, left: CGPoint, right: CGPoint) {
        guard let unit = direction(from: from, to: to) else { return (to, to, to) }
        let length = headLength(from: from, to: to, lineWidth: lineWidth, scale: scale)
        let halfWidth = length * tan(halfAngleDegrees * .pi / 180)
        let base = CGPoint(x: to.x - unit.dx * length, y: to.y - unit.dy * length)
        let left = CGPoint(x: base.x + unit.dy * halfWidth, y: base.y - unit.dx * halfWidth)
        let right = CGPoint(x: base.x - unit.dy * halfWidth, y: base.y + unit.dx * halfWidth)
        return (to, left, right)
    }

    /// Where the shaft stops: half the head's length back from the tip. That is past the base, so
    /// no gap shows, and the round cap stays inside the triangle: there the distance to each side
    /// is (length / 2) * sin(28°), at least 0.94 * lineWidth because length is at least
    /// 4 * lineWidth, against a cap radius of lineWidth / 2.
    static func shaftEnd(from: CGPoint, to: CGPoint, lineWidth: CGFloat, scale: CGFloat) -> CGPoint {
        guard let unit = direction(from: from, to: to) else { return to }
        let back = headLength(from: from, to: to, lineWidth: lineWidth, scale: scale) / 2
        return CGPoint(x: to.x - unit.dx * back, y: to.y - unit.dy * back)
    }

    /// The unit vector from `from` to `to`, nil when they are equal.
    private static func direction(from: CGPoint, to: CGPoint) -> CGVector? {
        let length = hypot(to.x - from.x, to.y - from.y)
        guard length > 0 else { return nil }
        return CGVector(dx: (to.x - from.x) / length, dy: (to.y - from.y) / length)
    }
}

/// Everything an annotation paints, in image pixels, so the canvas can invalidate it and skip the
/// drawings outside a dirty rect.
nonisolated enum AnnotationGeometry {
    /// Anti-aliasing can touch one pixel past the geometry.
    static let antialiasMargin: CGFloat = 1

    static func bounds(of annotation: Annotation, scale: CGFloat) -> CGRect {
        let painted: CGRect
        switch annotation {
        case .rectangle(let shape):
            // The stroke sits inside the rect.
            painted = shape.rect.standardized
        case .arrow(let segment):
            let head = ArrowGeometry.head(from: segment.from, to: segment.to, lineWidth: segment.lineWidth, scale: scale)
            let end = ArrowGeometry.shaftEnd(from: segment.from, to: segment.to, lineWidth: segment.lineWidth, scale: scale)
            let cap = segment.lineWidth / 2
            let shaft = enclosing([segment.from, end]).insetBy(dx: -cap, dy: -cap)
            painted = shaft.union(enclosing([head.tip, head.left, head.right]))
        case .redact(let region, _), .blur(let region, _), .pixelate(let region, _):
            painted = region.rect.standardized
        }
        return painted.insetBy(dx: -antialiasMargin, dy: -antialiasMargin)
    }

    /// The smallest rect holding `points`; it may have zero width or height.
    private static func enclosing(_ points: [CGPoint]) -> CGRect {
        let xs = points.map(\.x)
        let ys = points.map(\.y)
        let minX = xs.min() ?? 0
        let minY = ys.min() ?? 0
        return CGRect(x: minX, y: minY, width: (xs.max() ?? 0) - minX, height: (ys.max() ?? 0) - minY)
    }
}
```

- [ ] **Step 6: Write the key routing and the shortcut table**

`TidyShot/Editor/Geometry/KeyRouting.swift`:
```swift
import CoreGraphics
import Foundation

/// Unmodified keys that reach `CanvasView.keyDown`: the tool letters and the line-width digits.
/// Everything else goes to `interpretKeyEvents`, which turns Escape and ⌘. into `cancelOperation:`,
/// Delete into `deleteBackward:` or `deleteForward:`, and the arrow keys into `moveLeft:` and its
/// siblings, which nudge by `nudge(dx:dy:shift:)`.
nonisolated enum KeyRouting {
    enum Action: Equatable, Sendable {
        /// A tool letter, in either case.
        case selectTool(EditorTool)
        /// Digits 1 to 6: an index into `EditorPalette.lineWidthsPoints`.
        case lineWidth(index: Int)
        /// Not a canvas key: pass the event to `interpretKeyEvents`.
        case none
    }

    /// Image pixels per arrow-key press, without and with Shift.
    static let nudgeStep: CGFloat = 1
    static let shiftNudgeStep: CGFloat = 10

    /// `characters` is `NSEvent.charactersIgnoringModifiers`, which keeps Shift: ⇧1 arrives as
    /// "!" and matches nothing, while ⇧V arrives as "V" and still picks Select. Command, Control
    /// or Option held, or a text edit in progress (4b), make every key `.none`.
    static func action(characters: String?, command: Bool, control: Bool, option: Bool, isEditingText: Bool) -> Action {
        guard !command, !control, !option, !isEditingText,
              let characters, characters.count == 1, let key = characters.first else { return .none }
        if key.isASCII, let digit = key.wholeNumberValue, (1...EditorPalette.lineWidthsPoints.count).contains(digit) {
            return .lineWidth(index: digit - 1)
        }
        if let tool = EditorTool.tool(forKey: key) {
            return .selectTool(tool)
        }
        return .none
    }

    /// One arrow-key press. `dx` and `dy` are -1, 0 or 1; `dy` -1 is up, because image y grows
    /// downward.
    static func nudge(dx: Int, dy: Int, shift: Bool) -> CGVector {
        let step = shift ? shiftNudgeStep : nudgeStep
        return CGVector(dx: CGFloat(dx) * step, dy: CGFloat(dy) * step)
    }
}

/// The editor's key equivalents (spec 2.6, 4a table), matched by `EditorWindow.performKeyEquivalent`
/// before the main menu. ⌘X has no case: Phase 4 has no object cut, so ⌘X always reaches the
/// responder chain.
nonisolated enum EditorShortcut: CaseIterable, Sendable {
    case save, saveCopy, copy, copyImage, upload, uploadAsNew, undo, redo, close, zoomToFit, actualSize, zoomIn, zoomOut, selectAll

    /// A key with Command held. Control is never part of a chord.
    struct Chord: Hashable, Sendable {
        /// Lower case.
        let key: String
        var shift = false
        var option = false
    }

    var chord: Chord {
        switch self {
        case .save: Chord(key: "s")
        case .saveCopy: Chord(key: "s", shift: true)
        case .copy: Chord(key: "c")
        case .copyImage: Chord(key: "c", shift: true)
        case .upload: Chord(key: "u")
        case .uploadAsNew: Chord(key: "u", option: true)
        case .undo: Chord(key: "z")
        case .redo: Chord(key: "z", shift: true)
        case .close: Chord(key: "w")
        case .zoomToFit: Chord(key: "0")
        case .actualSize: Chord(key: "1")
        case .zoomIn: Chord(key: "=")
        case .zoomOut: Chord(key: "-")
        case .selectAll: Chord(key: "a")
        }
    }

    /// The action sent up the responder chain, for `NSSelectorFromString`.
    var selectorName: String {
        switch self {
        case .save: "saveDocument:"
        case .saveCopy: "saveDocumentCopy:"
        case .copy: "copy:"
        case .copyImage: "copyImage:"
        case .upload: "uploadDocument:"
        case .uploadAsNew: "uploadDocumentAsNew:"
        case .undo: "undo:"
        case .redo: "redo:"
        case .close: "performClose:"
        case .zoomToFit: "zoomToFit:"
        case .actualSize: "zoomToActualSize:"
        case .zoomIn: "zoomIn:"
        case .zoomOut: "zoomOut:"
        case .selectAll: "selectAll:"
        }
    }

    /// While a text annotation is edited (4b), these chords are left to the NSTextView.
    var passesThroughWhileEditingText: Bool {
        switch self {
        case .copy, .selectAll, .undo, .redo: true
        case .save, .saveCopy, .copyImage, .upload, .uploadAsNew, .close, .zoomToFit, .actualSize, .zoomIn, .zoomOut: false
        }
    }

    /// The row for a key event, or nil. `characters` is `NSEvent.charactersIgnoringModifiers`
    /// (⇧⌘S gives "S", ⌥⌘U gives "u"), compared in lower case. Command is required and Control
    /// rules a chord out. While `isEditingText`, the pass-through rows return nil.
    static func match(characters: String, command: Bool, shift: Bool, option: Bool, control: Bool, isEditingText: Bool) -> EditorShortcut? {
        guard command, !control else { return nil }
        let pressed = Chord(key: characters.lowercased(), shift: shift, option: option)
        guard let shortcut = allCases.first(where: { $0.chord == pressed }) else { return nil }
        if isEditingText && shortcut.passesThroughWhileEditingText {
            return nil
        }
        return shortcut
    }
}
```

- [ ] **Step 7: Run the tests to verify they pass**

Run:
```bash
xcodegen generate && xcodebuild test -project TidyShot.xcodeproj -scheme TidyShot -destination 'platform=macOS' -derivedDataPath .build 2>&1 | grep -E "Test run with|error:|TEST"
```
Expected: no `error:` lines, `Test run with 255 tests in 39 suites passed` and `** TEST SUCCEEDED **`. This task adds 24 tests in 4 new suites (DragGeometryTests 5, HitTesterTests 7, ArrowGeometryTests 4, KeyRoutingTests 8).

This task has no UI, so there is no hand check. Task 9 drives these helpers from the tools and Task 10 from the window.

- [ ] **Step 8: Commit**

```bash
git add TidyShot/Editor/Geometry/DragGeometry.swift TidyShot/Editor/Geometry/HitTester.swift TidyShot/Editor/Geometry/ArrowGeometry.swift TidyShot/Editor/Geometry/KeyRouting.swift TidyShotTests/DragGeometryTests.swift TidyShotTests/HitTesterTests.swift TidyShotTests/ArrowGeometryTests.swift TidyShotTests/KeyRoutingTests.swift
git commit -m "feat: hit testing, drag constraints and key routing for the editor"
```

### Task 5: RedactionRenderer actor: blur, pixelate and solid redact tiles (TDD)

**Files:**
- Create: `TidyShot/Editor/Rendering/RedactionRenderer.swift`
- Create: `TidyShotTests/RedactionRendererTests.swift`

No existing file changes. The task has no UI: tiles first reach the screen in Task 10.

**Interfaces:**
- Consumes (Task 2): `Annotation` with `.redact(Region, fill: RGBA)`, `.blur(Region, radius: CGFloat)`, `.pixelate(Region, block: CGFloat)`, `.arrow(Segment)` and `var effectRect: CGRect?`; `Region(id: UUID, rect: CGRect)`; `Segment(id:from:to:color:lineWidth:)`; `RGBA(red:green:blue:alpha:)` with `Double` components in sRGB.
- Consumes (Task 3): `ImageRects.integral(_ rect: CGRect, clippedTo size: CGSize) -> CGRect` (empty when the rect is outside), `ImageRects.bottomLeft(_ topLeft: CGRect, imageHeight: Int) -> CGRect`, and `EffectGeometry.sampleRect(of effect: Annotation, imageSize: CGSize) -> CGRect` (blur: the rect grown by `ceil(3 * radius)`; pixelate: the block-snapped rect; redact: the rect). The code works whether or not `sampleRect` clips to the image.
- Produces:
  - `nonisolated struct EffectTile: Sendable { let effect: Annotation; let image: CGImage; static func rect(for effect: Annotation, imageSize: CGSize) -> CGRect? }`. A tile's image covers exactly `EffectTile.rect(for:imageSize:)`: the effect rect rounded out to whole pixels and clipped to the image, top-left origin. Task 6 (cache), Task 7 (flattener, "on integral rects") and Task 10 (`BaseImageView` sublayer frames) place tiles at that rect, never at the raw fractional `effectRect`.
  - `nonisolated protocol TileRendering: Sendable { func tile(for effect: Annotation, over base: CGImage, beneath: [EffectTile]) async -> CGImage? }`. Under NonisolatedNonsendingByDefault the requirement runs on the caller's executor unless the conformer is an actor or marks the method `@concurrent` (Task 6's `FakeTileRenderer` does).
  - `actor RedactionRenderer: TileRendering { static let shared: RedactionRenderer; init(); func tile(for effect: Annotation, over base: CGImage, beneath: [EffectTile]) -> CGImage?; func warmUp(with base: CGImage); func clearCaches() }`.
  - Contract for callers: `beneath` is chosen by the caller (Task 6's `RedactionTileCache.keys`): every earlier effect whose rect meets `EffectGeometry.sampleRect(of: effect, imageSize:)`, in creation order. The renderer composites all of them, later over earlier, and reads no base pixel outside the sample rect. It returns nil for a drawing and for a rect wholly outside the image. Output is rendered at once (`deferred: false`), so no GPU work is left for `draw(_:)`. `warmUp(with:)` runs when an editor opens and `clearCaches()` when the last editor closes (Task 10).

- [ ] **Step 1: Write the failing tests**

`TidyShotTests/RedactionRendererTests.swift`:
```swift
import CoreGraphics
import CoreImage
import Foundation
import Metal
import Testing
@testable import TidyShot

/// Synthetic 64x64 images through the real Core Image renderer. Expected values are computed in
/// the same run, never read from golden files.
struct RedactionRendererTests {
    let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!
    let size = CGSize(width: 64, height: 64)
    let black = RGBA(red: 0, green: 0, blue: 0, alpha: 1)

    /// RGBA bytes read back through an sRGB premultipliedLast buffer. Row 0 is the image's top row,
    /// so `pixel(x, y)` uses the model's top-left convention.
    struct Pixels {
        let width: Int
        let height: Int
        let bytes: [UInt8]

        init(_ image: CGImage) {
            width = image.width
            height = image.height
            var buffer = [UInt8](repeating: 0, count: image.width * image.height * 4)
            buffer.withUnsafeMutableBytes { raw in
                let context = CGContext(data: raw.baseAddress, width: image.width, height: image.height,
                                        bitsPerComponent: 8, bytesPerRow: image.width * 4,
                                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
                context.interpolationQuality = .none
                context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            }
            bytes = buffer
        }

        func pixel(_ x: Int, _ y: Int) -> [UInt8] {
            let index = (y * width + x) * 4
            return Array(bytes[index..<index + 4])
        }
    }

    /// Every (x, y) in the two ranges, rows first.
    func grid(_ xs: Range<Int>, _ ys: Range<Int>) -> [(x: Int, y: Int)] {
        ys.flatMap { y in xs.map { (x: $0, y: y) } }
    }

    /// A 64x64 sRGB image; `paint` returns the RGBA bytes for each top-left pixel position.
    func image(_ paint: (Int, Int) -> [UInt8]) -> CGImage {
        var bytes: [UInt8] = []
        for y in 0..<64 {
            for x in 0..<64 {
                bytes += paint(x, y)
            }
        }
        return CGImage(width: 64, height: 64, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: 64 * 4, space: sRGB,
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: CGDataProvider(data: Data(bytes) as CFData)!, decode: nil,
                       shouldInterpolate: false, intent: .defaultIntent)!
    }

    /// Neighbouring pixels all differ, and no channel is 0 or 255.
    func noise() -> CGImage {
        image { x, y in
            [UInt8(20 + (x * 37 + y * 11) % 200), UInt8(20 + (x * 13 + y * 29) % 200), UInt8(20 + (x * 7 + y * 41) % 200), 255]
        }
    }

    func region(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat) -> Region {
        Region(id: UUID(), rect: CGRect(x: x, y: y, width: width, height: height))
    }

    @Test func solidTileIsFillColourOpaque() async throws {
        let renderer = RedactionRenderer()
        let base = noise()
        // A fractional rect rounds out to whole pixels, and a translucent fill still paints opaque
        // pixels: a see-through redaction would hide nothing.
        let effect = Annotation.redact(region(4.4, 6.6, 20.2, 10.1), fill: RGBA(red: 1, green: 0.5, blue: 0, alpha: 0.4))
        #expect(EffectTile.rect(for: effect, imageSize: size) == CGRect(x: 4, y: 6, width: 21, height: 11))
        let tile = try #require(await renderer.tile(for: effect, over: base, beneath: []))
        #expect(tile.width == 21 && tile.height == 11)
        #expect(tile.colorSpace?.name == CGColorSpace.sRGB)
        let pixels = Pixels(tile)
        let wrong = grid(0..<21, 0..<11).filter { point in
            let pixel = pixels.pixel(point.x, point.y)
            return !(pixel[0] == 255 && abs(Int(pixel[1]) - 128) <= 1 && pixel[2] == 0 && pixel[3] == 255)
        }
        #expect(wrong.isEmpty, "not the fill at \(wrong.prefix(3))")

        // The tile takes the base's colour space, and clearing the caches leaves the renderer usable.
        let p3 = try #require(base.copy(colorSpace: CGColorSpace(name: CGColorSpace.displayP3)!))
        let p3Tile = try #require(await renderer.tile(for: effect, over: p3, beneath: []))
        #expect(p3Tile.colorSpace?.name == CGColorSpace.displayP3)
        await renderer.clearCaches()
        #expect(Pixels(try #require(await renderer.tile(for: effect, over: base, beneath: []))).bytes == pixels.bytes)
    }

    @Test func blurTileEqualsFullImageBlurCrop() async throws {
        let renderer = RedactionRenderer()
        let base = noise()
        // The rect touches the image's left edge, where the blur reads clamped edge pixels.
        let rect = CGRect(x: 0, y: 8, width: 28, height: 40)
        let tile = try #require(await renderer.tile(for: .blur(Region(id: UUID(), rect: rect), radius: 3), over: base, beneath: []))

        // The whole image blurred in a separate context, then cropped with CGImage's own top-left
        // convention, so a flipped tile cannot pass.
        let context = MTLCreateSystemDefaultDevice().map { CIContext(mtlDevice: $0) } ?? CIContext()
        let input = CIImage(cgImage: base)
        let blurred = input.clampedToExtent().applyingGaussianBlur(sigma: 3).cropped(to: input.extent)
        let whole = try #require(context.createCGImage(blurred, from: input.extent, format: .RGBA8, colorSpace: sRGB))
        let expected = Pixels(try #require(whole.cropping(to: rect)))

        let actual = Pixels(tile)
        #expect(actual.width == 28 && actual.height == 40)
        let maxDiff = zip(actual.bytes, expected.bytes).map { abs(Int($0) - Int($1)) }.max() ?? 0
        #expect(maxDiff <= 1)
        #expect(actual.bytes != Pixels(try #require(base.cropping(to: rect))).bytes)
    }

    @Test func mosaicBlocksUniform() async throws {
        let renderer = RedactionRenderer()
        let base = noise()
        // A 10 px block over a region that is not on the grid: the grid starts at image pixel
        // (0,0), so the region's 30x22 pixels fall in 4x3 blocks.
        let effect = Annotation.pixelate(region(5, 3, 30, 22), block: 10)
        let pixels = Pixels(try #require(await renderer.tile(for: effect, over: base, beneath: [])))
        #expect(pixels.width == 30 && pixels.height == 22)
        var blocks: [[Int]: [UInt8]] = [:]
        var mixed: [(x: Int, y: Int)] = []
        for point in grid(0..<30, 0..<22) {
            let key = [(point.x + 5) / 10, (point.y + 3) / 10]
            let pixel = pixels.pixel(point.x, point.y)
            if let first = blocks[key], first != pixel {
                mixed.append(point)
            } else {
                blocks[key] = pixel
            }
        }
        #expect(mixed.isEmpty, "not uniform at \(mixed.prefix(3))")
        #expect(blocks.count == 12)
        #expect(Set(blocks.values).count > 1)
        #expect(pixels.bytes != Pixels(try #require(base.cropping(to: CGRect(x: 5, y: 3, width: 30, height: 22)))).bytes)
    }

    @Test func mosaicGridStableWhenRegionMoves() async throws {
        let renderer = RedactionRenderer()
        let base = noise()
        // 8 px is a power of two, so Core Image's high-quality downsample averages each block
        // from its own pixels only.
        let first = Pixels(try #require(await renderer.tile(for: .pixelate(region(5, 3, 30, 22), block: 8), over: base, beneath: [])))
        let moved = Pixels(try #require(await renderer.tile(for: .pixelate(region(9, 7, 30, 22), block: 8), over: base, beneath: [])))
        // Image pixels 9..<35 by 7..<25 are in both tiles.
        let changed = grid(9..<35, 7..<25).filter { first.pixel($0.x - 5, $0.y - 3) != moved.pixel($0.x - 9, $0.y - 7) }
        #expect(changed.isEmpty, "changed when the region moved: \(changed.prefix(3))")
    }

    @Test func mosaicAveragesHalfWhiteBlock() async throws {
        let renderer = RedactionRenderer()
        // The left half of every 8 px block is white and the right half black.
        let halves = image { x, _ in x % 8 < 4 ? [255, 255, 255, 255] : [0, 0, 0, 255] }
        let pixels = Pixels(try #require(await renderer.tile(for: .pixelate(region(16, 16, 16, 16), block: 8), over: halves, beneath: [])))
        // Averaged in linear light: half of white is sRGB 0.735, about 188. CIPixellate would give 0 or 255.
        let wrong = grid(0..<16, 0..<16).filter { point in
            let pixel = pixels.pixel(point.x, point.y)
            return !(abs(Int(pixel[0]) - 188) <= 3 && pixel[0] == pixel[1] && pixel[1] == pixel[2] && pixel[3] == 255)
        }
        #expect(wrong.isEmpty, "not mid grey at \(wrong.prefix(3)): \(pixels.pixel(0, 0))")
    }

    @Test func tileNilOutsideImage() async throws {
        let renderer = RedactionRenderer()
        let base = noise()
        #expect(await renderer.tile(for: .redact(region(70, 70, 10, 10), fill: black), over: base, beneath: []) == nil)
        #expect(await renderer.tile(for: .blur(region(-20, 10, 10, 10), radius: 4), over: base, beneath: []) == nil)
        #expect(await renderer.tile(for: .pixelate(region(10, 64, 20, 5), block: 8), over: base, beneath: []) == nil)
        let arrow = Annotation.arrow(Segment(id: UUID(), from: .zero, to: CGPoint(x: 30, y: 30), color: black, lineWidth: 4))
        #expect(await renderer.tile(for: arrow, over: base, beneath: []) == nil)
        // A region partly outside keeps only its pixels inside the image.
        let partial = try #require(await renderer.tile(for: .redact(region(-5, -5, 10, 10), fill: black), over: base, beneath: []))
        #expect(partial.width == 5 && partial.height == 5)
    }

    @Test func alphaZeroCornerStaysZero() async throws {
        let renderer = RedactionRenderer()
        // A window capture: the top-left 16x16 corner is fully transparent.
        let base = image { x, y in x < 16 && y < 16 ? [0, 0, 0, 0] : [200, 120, 40, 255] }
        let corner = region(0, 0, 32, 32)
        let blur = Pixels(try #require(await renderer.tile(for: .blur(corner, radius: 1), over: base, beneath: [])))
        let mosaic = Pixels(try #require(await renderer.tile(for: .pixelate(corner, block: 8), over: base, beneath: [])))
        let redact = Pixels(try #require(await renderer.tile(for: .redact(corner, fill: black), over: base, beneath: [])))
        #expect(grid(0..<8, 0..<8).allSatisfy { blur.pixel($0.x, $0.y)[3] == 0 })
        #expect(grid(0..<16, 0..<16).allSatisfy { mosaic.pixel($0.x, $0.y)[3] == 0 })
        #expect(mosaic.pixel(20, 20)[3] == 255)
        // Blocks cut by the image's right and bottom edges stay opaque: nothing outside the image is
        // averaged in, so the tile never lets the pixels it covers show through.
        let edge = Pixels(try #require(await renderer.tile(for: .pixelate(region(40, 40, 24, 24), block: 10), over: base, beneath: [])))
        #expect(grid(0..<24, 0..<24).allSatisfy { edge.pixel($0.x, $0.y)[3] == 255 })
        // A solid redaction over the transparent corner paints opaque pixels.
        #expect(grid(0..<16, 0..<16).allSatisfy { redact.pixel($0.x, $0.y) == [0, 0, 0, 255] })
    }

    @Test func blurOverEarlierRedactBlursBlack() async throws {
        let renderer = RedactionRenderer()
        let base = noise()
        let redact = Annotation.redact(region(16, 16, 32, 32), fill: black)
        let blur = Annotation.blur(region(8, 8, 48, 48), radius: 2)
        let redactTile = try #require(await renderer.tile(for: redact, over: base, beneath: []))
        let tile = Pixels(try #require(await renderer.tile(for: blur, over: base, beneath: [EffectTile(effect: redact, image: redactTile)])))
        let source = Pixels(base)
        // Image pixels 16..<48 are under the redaction; the blur tile starts at image pixel 8.
        let survived = grid(16..<48, 16..<48).filter { tile.pixel($0.x - 8, $0.y - 8)[0..<3] == source.pixel($0.x, $0.y)[0..<3] }
        #expect(survived.isEmpty, "source value survived at \(survived.prefix(3))")
        // Three sigma inside the redaction there is only black to blur.
        #expect(grid(22..<42, 22..<42).allSatisfy { tile.pixel($0.x - 8, $0.y - 8)[0..<3].allSatisfy { $0 <= 1 } })
    }

    @Test func blurNextToRedactSamplesRedactInMargin() async throws {
        let renderer = RedactionRenderer()
        // White, with a red secret where the redaction goes.
        let base = image { x, y in (40..<56).contains(x) && (16..<48).contains(y) ? [255, 0, 0, 255] : [255, 255, 255, 255] }
        let redact = Annotation.redact(region(40, 16, 16, 32), fill: black)
        let blur = Annotation.blur(region(8, 16, 28, 32), radius: 4)
        // The rects do not meet, but the blur's margin reaches the redaction, so the tile cache
        // passes the redaction as beneath.
        #expect(!CGRect(x: 8, y: 16, width: 28, height: 32).intersects(CGRect(x: 40, y: 16, width: 16, height: 32)))
        #expect(EffectGeometry.sampleRect(of: blur, imageSize: size).intersects(CGRect(x: 40, y: 16, width: 16, height: 32)))
        let redactTile = try #require(await renderer.tile(for: redact, over: base, beneath: []))
        let covered = Pixels(try #require(await renderer.tile(for: blur, over: base, beneath: [EffectTile(effect: redact, image: redactTile)])))
        let uncovered = Pixels(try #require(await renderer.tile(for: blur, over: base, beneath: [])))
        // The tile's right column (image x 35) is 5 px from the redaction. Without beneath the red
        // secret bleeds in; with it the margin darkens to grey and carries no red.
        let edge = (4..<28).map { (secret: uncovered.pixel(27, $0), pixel: covered.pixel(27, $0)) }
        #expect(edge.allSatisfy { Int($0.secret[0]) - Int($0.secret[1]) > 10 })
        #expect(edge.allSatisfy { abs(Int($0.pixel[0]) - Int($0.pixel[1])) <= 1 && abs(Int($0.pixel[1]) - Int($0.pixel[2])) <= 1 })
        #expect(edge.allSatisfy { $0.pixel[1] < 250 })
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run:
```bash
xcodegen generate && xcodebuild test -project TidyShot.xcodeproj -scheme TidyShot -destination 'platform=macOS' -derivedDataPath .build 2>&1 | grep -E "Test run with|error:|TEST"
```
Expected: compile errors, among them `cannot find 'RedactionRenderer' in scope` and `cannot find 'EffectTile' in scope`, then `** TEST FAILED **`.

- [ ] **Step 3: Write the renderer**

The graphs follow spec 2.6, with three additions that keep hidden pixels hidden:
- Blur crops the composite to the sample rect before `clampedToExtent()`. `beneath` covers exactly that rect, so the guarantee does not depend on how far Core Image's kernel reaches. Its kernel stays inside 3 sigma, so the tile still equals a full-image blur within 1 (`blurTileEqualsFullImageBlurCrop`).
- Pixelate clamps after its crop. Without the clamp, a block cut by the image edge averages in transparent pixels and comes out translucent over the pixels it should hide (`alphaZeroCornerStaysZero` fails).
- Redact ignores the fill's alpha and paints opaque.

The mosaic grid is anchored at image pixel (0,0), the top left. In Core Image's bottom-left space that is y = height, so the downsample transform translates by `-height` before scaling by `1 / block`, and block edges land on whole pixels of the small image. Pixelate reads only `EffectGeometry.sampleRect`, the same rect the tile cache uses to choose `beneath`.

`TidyShot/Editor/Rendering/RedactionRenderer.swift`:
```swift
import CoreGraphics
import CoreImage
import Metal

/// One rendered effect. `image` covers `EffectTile.rect(for: effect, imageSize:)` of the base, in
/// native pixels, so it is drawn there with no scaling.
nonisolated struct EffectTile: Sendable {
    let effect: Annotation
    let image: CGImage

    /// The pixels a tile for `effect` covers: its rect rounded out to whole pixels and clipped to
    /// the image, top-left origin. Nil for a drawing, or when nothing of the rect is in the image.
    static func rect(for effect: Annotation, imageSize: CGSize) -> CGRect? {
        guard let rect = effect.effectRect else { return nil }
        let clipped = ImageRects.integral(rect, clippedTo: imageSize)
        return clipped.isEmpty ? nil : clipped
    }
}

/// Renders effect tiles. Under NonisolatedNonsendingByDefault a nonisolated `tile` runs on the
/// caller's executor, so a conformer that must leave the main actor is an actor (RedactionRenderer)
/// or marks the method `@concurrent` (the test fake).
nonisolated protocol TileRendering: Sendable {
    func tile(for effect: Annotation, over base: CGImage, beneath: [EffectTile]) async -> CGImage?
}

/// Renders blur, pixelate and redact tiles with Core Image, off the main actor. It owns the app's
/// only CIContext; filters are built inside each call because CIFilter is not Sendable.
actor RedactionRenderer: TileRendering {
    static let shared = RedactionRenderer()

    private let context: CIContext
    private let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!

    init() {
        let options: [CIContextOption: Any] = [.cacheIntermediates: true, .name: "TidyShot.redaction"]
        if let device = MTLCreateSystemDefaultDevice() {
            context = CIContext(mtlDevice: device, options: options)
        } else {
            context = CIContext(options: options)
        }
    }

    /// The tile for `effect` over `base`, with every tile in `beneath` composited under it first,
    /// so a blur or pixelate over (or next to) a redaction samples the fill and never the pixels it
    /// hides. Nil for a drawing or a rect wholly outside the image.
    func tile(for effect: Annotation, over base: CGImage, beneath: [EffectTile]) -> CGImage? {
        let size = CGSize(width: base.width, height: base.height)
        guard let target = EffectTile.rect(for: effect, imageSize: size) else { return nil }
        let height = base.height
        let output: CIImage
        switch effect {
        case .redact(_, let fill):
            // Always opaque: a see-through redaction would not hide anything.
            guard let colour = CIColor(red: fill.red, green: fill.green, blue: fill.blue, alpha: 1, colorSpace: sRGB) else {
                return nil
            }
            output = CIImage(color: colour)
        case .blur(_, let radius):
            // Only the sample rect is read. `beneath` holds every earlier effect that meets it, so a
            // hidden pixel never reaches the blur, whatever the reach of Core Image's kernel.
            let sample = ImageRects.bottomLeft(EffectGeometry.sampleRect(of: effect, imageSize: size), imageHeight: height)
            output = composite(base, beneath: beneath).cropped(to: sample)
                .clampedToExtent()
                .applyingGaussianBlur(sigma: Double(radius))
        case .pixelate(_, let block):
            output = mosaic(composite(base, beneath: beneath), block: block,
                            sample: EffectGeometry.sampleRect(of: effect, imageSize: size), imageHeight: height)
        default:
            return nil
        }
        let rect = ImageRects.bottomLeft(target, imageHeight: height)
        let space = base.colorSpace.flatMap { $0.model == .rgb ? $0 : nil } ?? sRGB
        return context.createCGImage(output.cropped(to: rect), from: rect, format: .RGBA8, colorSpace: space, deferred: false)
    }

    /// Renders 1x1 blur and pixelate tiles, so the first real drag does not wait for Core Image
    /// to compile its kernels.
    func warmUp(with base: CGImage) {
        let pixel = Region(id: UUID(), rect: CGRect(x: 0, y: 0, width: 1, height: 1))
        _ = tile(for: .blur(pixel, radius: 1), over: base, beneath: [])
        _ = tile(for: .pixelate(pixel, block: 1), over: base, beneath: [])
    }

    /// Frees the context's intermediates when the last editor closes.
    func clearCaches() {
        context.clearCaches()
    }

    /// `base` with each tile in `beneath` drawn over it at its own rect, in order.
    private func composite(_ base: CGImage, beneath: [EffectTile]) -> CIImage {
        let size = CGSize(width: base.width, height: base.height)
        var image = CIImage(cgImage: base)
        for tile in beneath {
            guard let rect = EffectTile.rect(for: tile.effect, imageSize: size) else { continue }
            let origin = ImageRects.bottomLeft(rect, imageHeight: base.height).origin
            image = CIImage(cgImage: tile.image)
                .transformed(by: CGAffineTransform(translationX: origin.x, y: origin.y))
                .composited(over: image)
        }
        return image
    }

    /// An averaged mosaic: each `block` square of the grid anchored at image pixel (0,0) takes the
    /// mean of its pixels (exact for power-of-two blocks; Core Image's high-quality downsample
    /// widens the window slightly for other sizes). `sample` is the block-snapped rect clipped to
    /// the image, in top-left image pixels. Only it is read, and its edge pixels stand in for the
    /// part of a block outside the image, so every block stays opaque over opaque pixels.
    private func mosaic(_ input: CIImage, block: CGFloat, sample: CGRect, imageHeight: Int) -> CIImage {
        let side = max(1, block)
        let top = CGFloat(imageHeight)
        // Core Image's origin is the bottom left, so the grid is anchored at y = height. One pixel
        // of the small image is one block, and block edges land on whole small pixels.
        let toBlocks = CGAffineTransform(a: 1 / side, b: 0, c: 0, d: 1 / side, tx: 0, ty: -top / side)
        let fromBlocks = CGAffineTransform(a: side, b: 0, c: 0, d: side, tx: 0, ty: top)
        return input.cropped(to: ImageRects.bottomLeft(sample, imageHeight: imageHeight))
            .clampedToExtent()
            .transformed(by: toBlocks, highQualityDownsample: true)
            .samplingNearest()
            .transformed(by: fromBlocks)
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run:
```bash
xcodegen generate && xcodebuild test -project TidyShot.xcodeproj -scheme TidyShot -destination 'platform=macOS' -derivedDataPath .build 2>&1 | grep -E "Test run with|error:|TEST"
```
Expected: no `error:` lines, and `Test run with 265 tests in 40 suites passed`.

- [ ] **Step 5: Commit**

```bash
git add TidyShot/Editor/Rendering/RedactionRenderer.swift TidyShotTests/RedactionRendererTests.swift
git commit -m "feat: redaction tiles rendered with Core Image off the main actor"
```

### Task 6: RedactionTileCache keyed by effect and the effects beneath it

**Files:**
- Create: `TidyShot/Editor/Rendering/RedactionTileCache.swift`
- Modify: none.
- Test: `TidyShotTests/RedactionTileCacheTests.swift` (new suite), `TidyShotTests/FakeTileRenderer.swift` (new test helpers with no `@Test`; Task 8 reuses them)

**Interfaces:**
- Consumes:
  - `nonisolated protocol TileRendering: Sendable { func tile(for effect: Annotation, over base: CGImage, beneath: [EffectTile]) async -> CGImage? }` and `nonisolated struct EffectTile: Sendable { let effect: Annotation; let image: CGImage }` (Task 5, `TidyShot/Editor/Rendering/RedactionRenderer.swift`).
  - `Annotation` (Task 2): `id: UUID`, `isEffect: Bool`, `effectRect: CGRect?`, `moved(by: CGVector) -> Annotation`, and the cases `.redact(Region, fill: RGBA)`, `.blur(Region, radius: CGFloat)`, `.pixelate(Region, block: CGFloat)` and `.rectangle(ShapeBox)`. Also `Region(id:rect:)`, `ShapeBox(id:rect:color:lineWidth:)`, `EditorPalette.defaultRedact` and `EditorPalette.defaultStroke`.
  - `AnnotationDocument` (Task 2): `init(annotations:)`, `effects` (creation order), `appending(_:)`, `replacing(_:)` (keeps the position) and `removing(id:)`.
  - `EffectGeometry.sampleRect(of effect: Annotation, imageSize: CGSize) -> CGRect` (blur: the rect grown by `ceil(3 * radius)`; pixelate: the block-snapped rect; redact: the rect) and `ImageRects.integral(_ rect: CGRect, clippedTo size: CGSize) -> CGRect` (Task 3).
  - `@MainActor func eventually(_ condition: () async -> Bool) async throws` (`TidyShotTests/UploadQueueTests.swift:110-117`), and `Mutex` from Synchronization, already used by the tests (`TidyShotTests/UploadQueueTests.swift:2`).
- Produces:
  - `nonisolated struct TileKey: Equatable, Sendable { let effect: Annotation; let beneath: [Annotation] }`.
  - `final class RedactionTileCache`, MainActor through the target's default isolation:
    - `init(base: CGImage, renderer: any TileRendering)`
    - `private(set) var tiles: [UUID: (key: TileKey, image: CGImage)]`
    - `var onChange: () -> Void`, called after a tile is stored or tiles are dropped
    - `private(set) var renderTask: Task<Void, Never>?`, the pass for the latest keys (tests await it)
    - `nonisolated static func orderedEffects(in document: AnnotationDocument, transient: Annotation?) -> [Annotation]`
    - `nonisolated static func keys(for effects: [Annotation], imageSize: CGSize) -> [UUID: TileKey]`
    - `func currentTile(for effect: Annotation, in document: AnnotationDocument, transient: Annotation?) -> CGImage?`
    - `func reconcile(document: AnnotationDocument, transient: Annotation?)`
    - `func allTiles(for document: AnnotationDocument) async -> [EffectTile]`
  - In `TidyShotTests/FakeTileRenderer.swift`: `nonisolated final class FakeTileRenderer: TileRendering { init(gate: TileGate? = nil); let gate: TileGate?; var calls: [TileKey]; @concurrent func tile(for:over:beneath:) async -> CGImage? }` and `actor TileGate { func wait() async; func open() }`.
- Rules the code and tests pin:
  - A key's `beneath` holds, in creation order, every earlier effect whose rect meets the effect's sample rect, plus everything beneath those. A tile's pixels come from the tiles under it, so a change two steps down must change the key too. Both rects are rounded out with `ImageRects.integral`; rects that only share an edge do not meet.
  - The renderer still gets only the direct tiles (2.6: earlier effects whose rect meets the sample rect), each one matching its current key.
  - There is no invalidation pass. `reconcile` drops the tiles of effects that are gone at once, then renders the effects whose stored key differs, in creation order, in one task. Each call that changes the keys bumps a cache-wide generation, and a result from an older generation is dropped. A call with the same keys as the latest one is a no-op, so a commit that lands before the drag's last tile does not throw it away.
  - A transient effect with a new id is tiled last. A transient with the id of a document effect (Select moving or resizing it) takes that effect's place. A transient drawing is ignored. Either way the commit has the same keys, so the tile carries over.
  - `currentTile` returns a tile only when its key equals the key the effect wants now. Otherwise it returns nil and the canvas draws the placeholder.
  - `allTiles` returns every tile of the document in creation order. It reuses matching tiles, renders the rest through the same renderer, and never writes `tiles`, so an export of an older document cannot overwrite a newer preview tile.
  - The cache's order is the one the canvas must stack by. A moved or resized effect keeps its creation-order place, so a layer drawn above a later blur or pixelate would show the redacted pixels through it; only a new shape comes last. This refines the spec 2.6 sentence "reconciled as the last effect", which holds for a new shape.
  - `currentTile` is strict, and the canvas never draws a stored tile whose key differs. A stale redact tile at its old rect would leave part of the new rect unredacted on screen until the new tile lands, so the placeholder (the fill colour for a redact) is drawn instead.
- Later tasks call it like this: EditorModel (Task 8) calls `reconcile(document:transient:)` in every commit (undo and redo re-commit) and on every change to `transient`, and `renderExport` calls `allTiles(for: document)`. Task 8's tests can await `tileCache.renderTask?.value` instead of polling. The BaseImageView tile list and the canvas placeholders (Task 10) must come from `orderedEffects(in:transient:)` for the order and `currentTile(for:in:transient:)` for each tile, and must not read `tiles[id]` directly.

- [ ] **Step 1: Write the test helpers and the failing tests**

`TidyShotTests/FakeTileRenderer.swift`:
```swift
import CoreGraphics
import Synchronization
@testable import TidyShot

/// A `TileRendering` for the tile-cache and editor-model tests. It records each call as the key
/// it was asked for (the effect and the effects of the tiles passed beneath it) and returns a new
/// 1x1 image, so `===` tells a reused tile from a re-rendered one.
///
/// `tile` is `@concurrent`, so it runs off the main actor like the real actor does. With a
/// `gate`, the first call waits until the gate opens; later calls return at once.
nonisolated final class FakeTileRenderer: TileRendering {
    let gate: TileGate?
    private let recorded = Mutex<[TileKey]>([])

    init(gate: TileGate? = nil) {
        self.gate = gate
    }

    /// Every call so far, in the order they started.
    var calls: [TileKey] {
        recorded.withLock { $0 }
    }

    @concurrent func tile(for effect: Annotation, over base: CGImage, beneath: [EffectTile]) async -> CGImage? {
        let isFirst = recorded.withLock { calls in
            calls.append(TileKey(effect: effect, beneath: beneath.map(\.effect)))
            return calls.count == 1
        }
        if isFirst, let gate {
            await gate.wait()
        }
        return Self.pixel()
    }

    private static func pixel() -> CGImage {
        let context = CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
        return context.makeImage()!
    }
}

/// Holds a render until the test calls `open()`. It suspends on a continuation and never blocks
/// a thread: a `DispatchSemaphore` here would block the main actor the tests run on.
actor TileGate {
    private var isOpen = false
    private var waiting: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        guard !isOpen else { return }
        await withCheckedContinuation { waiting.append($0) }
    }

    func open() {
        isOpen = true
        for continuation in waiting { continuation.resume() }
        waiting = []
    }
}
```

The gate holds only the first call. That lets a test keep one render in flight while a later pass finishes, so the order of results is fixed and not left to timing.

`TidyShotTests/RedactionTileCacheTests.swift`:
```swift
import CoreGraphics
import Foundation
import Testing
@testable import TidyShot

/// The cache runs on the main actor, like these tests; the fake renderer runs off it.
struct RedactionTileCacheTests {
    let size = CGSize(width: 100, height: 100)
    let base: CGImage

    init() {
        let context = CGContext(data: nil, width: 100, height: 100, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(srgbRed: 0.2, green: 0.6, blue: 0.9, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 100, height: 100))
        base = context.makeImage()!
    }

    func makeCache(_ renderer: FakeTileRenderer) -> RedactionTileCache {
        RedactionTileCache(base: base, renderer: renderer)
    }

    func redact(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat) -> Annotation {
        .redact(Region(id: UUID(), rect: CGRect(x: x, y: y, width: width, height: height)), fill: EditorPalette.defaultRedact)
    }

    func blur(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat, radius: CGFloat = 2) -> Annotation {
        .blur(Region(id: UUID(), rect: CGRect(x: x, y: y, width: width, height: height)), radius: radius)
    }

    func pixelate(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat, block: CGFloat = 4) -> Annotation {
        .pixelate(Region(id: UUID(), rect: CGRect(x: x, y: y, width: width, height: height)), block: block)
    }

    func document(_ annotations: Annotation...) -> AnnotationDocument {
        AnnotationDocument(annotations: annotations)
    }

    /// A blur reads `ceil(3 * radius)` px around its rect, a pixelate its block-snapped rect and a
    /// redact only its own rect. Rects that only touch along an edge share no pixel. A later
    /// effect also inherits what lies beneath the tiles it samples.
    @Test func keysIncludeOnlySampledEarlierEffects() {
        let secret = redact(10, 10, 20, 20)             // x 10..<30
        let touching = redact(30, 10, 5, 5)             // starts where `secret` ends
        let blurred = blur(35, 10, 20, 20, radius: 2)   // samples x 29..<61, y 4..<36
        let far = redact(70, 70, 10, 10)
        let mosaic = pixelate(36, 28, 8, 8, block: 4)   // meets `blurred` (y 28..<30) and nothing else
        let keys = RedactionTileCache.keys(for: [secret, touching, blurred, far, mosaic], imageSize: size)

        #expect(keys.count == 5)
        #expect(keys[secret.id] == TileKey(effect: secret, beneath: []))
        #expect(keys[touching.id] == TileKey(effect: touching, beneath: []))
        #expect(keys[blurred.id] == TileKey(effect: blurred, beneath: [secret, touching]))
        #expect(keys[far.id] == TileKey(effect: far, beneath: []))
        #expect(keys[mosaic.id] == TileKey(effect: mosaic, beneath: [secret, touching, blurred]))

        // The blur radius sets the margin: 2 px reads from x 11, 3 px from x 8.
        let left = redact(0, 50, 10, 10)
        let narrow = blur(17, 50, 10, 10, radius: 2)
        let wide = blur(17, 50, 10, 10, radius: 3)
        #expect(RedactionTileCache.keys(for: [left, narrow], imageSize: size)[narrow.id]?.beneath == [])
        #expect(RedactionTileCache.keys(for: [left, wide], imageSize: size)[wide.id]?.beneath == [left])
    }

    @Test func unchangedEffectIsNotRerendered() async throws {
        let renderer = FakeTileRenderer()
        let cache = makeCache(renderer)
        var changes = 0
        cache.onChange = { changes += 1 }
        let secret = redact(10, 10, 20, 20)
        let start = document(secret)
        cache.reconcile(document: start, transient: nil)
        await cache.renderTask?.value
        let tile = try #require(cache.currentTile(for: secret, in: start, transient: nil))
        #expect(renderer.calls == [TileKey(effect: secret, beneath: [])])
        #expect(changes == 1)

        // A drawing, a transient drawing and an effect far away leave the tile alone.
        let box = Annotation.rectangle(ShapeBox(id: UUID(), rect: CGRect(x: 0, y: 0, width: 50, height: 50),
                                                color: EditorPalette.defaultStroke, lineWidth: 8))
        let dragging = Annotation.rectangle(ShapeBox(id: UUID(), rect: CGRect(x: 5, y: 5, width: 30, height: 30),
                                                     color: EditorPalette.defaultStroke, lineWidth: 8))
        let far = redact(70, 70, 10, 10)
        let more = start.appending(box).appending(far)
        cache.reconcile(document: more, transient: dragging)
        await cache.renderTask?.value

        #expect(renderer.calls.map(\.effect) == [secret, far])
        #expect(cache.currentTile(for: secret, in: more, transient: dragging) === tile)
        #expect(changes == 2)
    }

    @Test func movingEarlierEffectRerendersOverlappingLater() async throws {
        let renderer = FakeTileRenderer()
        let cache = makeCache(renderer)
        let secret = redact(10, 10, 20, 20)
        let blurred = blur(25, 10, 20, 20, radius: 2)   // overlaps `secret`
        let mosaic = pixelate(36, 28, 8, 8, block: 4)   // overlaps `blurred` only
        let before = document(secret, blurred, mosaic)
        cache.reconcile(document: before, transient: nil)
        await cache.renderTask?.value
        let oldBlur = try #require(cache.tiles[blurred.id]?.image)
        let oldMosaic = try #require(cache.tiles[mosaic.id]?.image)

        let moved = secret.moved(by: CGVector(dx: 2, dy: 0))
        let after = before.replacing(moved)
        cache.reconcile(document: after, transient: nil)
        // Until the new tiles land, the old ones are pending, never shown.
        #expect(cache.currentTile(for: blurred, in: after, transient: nil) == nil)
        await cache.renderTask?.value

        // All three re-render in creation order, each over the new tiles beneath it.
        #expect(Array(renderer.calls.dropFirst(3)) == [TileKey(effect: moved, beneath: []),
                                                         TileKey(effect: blurred, beneath: [moved]),
                                                         TileKey(effect: mosaic, beneath: [blurred])])
        #expect(cache.tiles[mosaic.id]?.key == TileKey(effect: mosaic, beneath: [moved, blurred]))
        #expect(try #require(cache.currentTile(for: blurred, in: after, transient: nil)) !== oldBlur)
        #expect(try #require(cache.currentTile(for: mosaic, in: after, transient: nil)) !== oldMosaic)
    }

    @Test func nonOverlappingLaterKeepsTile() async throws {
        let renderer = FakeTileRenderer()
        let cache = makeCache(renderer)
        let secret = redact(10, 10, 20, 20)
        let blurred = blur(60, 60, 20, 20, radius: 2)   // samples x and y 54..<86
        let before = document(secret, blurred)
        cache.reconcile(document: before, transient: nil)
        await cache.renderTask?.value
        let kept = try #require(cache.tiles[blurred.id]?.image)

        let moved = secret.moved(by: CGVector(dx: 20, dy: 20))   // x and y 30..<50
        let after = before.replacing(moved)
        cache.reconcile(document: after, transient: nil)
        await cache.renderTask?.value

        #expect(renderer.calls.dropFirst(2).map(\.effect) == [moved])
        #expect(cache.currentTile(for: blurred, in: after, transient: nil) === kept)
    }

    /// The first render is held at the gate while a second reconcile moves the blur. The second
    /// pass stores its tile; then the held result arrives and must not replace it.
    @Test func staleReconcileResultDropped() async throws {
        let gate = TileGate()
        let renderer = FakeTileRenderer(gate: gate)
        let cache = makeCache(renderer)
        let first = blur(10, 10, 20, 20)
        let second = first.moved(by: CGVector(dx: 8, dy: 0))
        cache.reconcile(document: document(first), transient: nil)
        let held = try #require(cache.renderTask)
        try await eventually { renderer.calls.count == 1 }

        cache.reconcile(document: document(second), transient: nil)
        await cache.renderTask?.value
        let latest = try #require(cache.currentTile(for: second, in: document(second), transient: nil))

        await gate.open()
        await held.value
        #expect(cache.tiles[second.id]?.key == TileKey(effect: second, beneath: []))
        #expect(cache.currentTile(for: second, in: document(second), transient: nil) === latest)
        #expect(renderer.calls.map(\.effect) == [first, second])
    }

    /// The drag's tiles are still rendering (held at the gate) when mouseUp commits the same
    /// value, so the pass in flight finishes and nothing renders twice. The new effect is tiled
    /// last; an existing effect being moved keeps its place.
    @Test func transientTileCarriesOverOnCommit() async throws {
        let gate = TileGate()
        let renderer = FakeTileRenderer(gate: gate)
        let cache = makeCache(renderer)
        let secret = redact(10, 10, 20, 20)
        let start = document(secret)
        let dragged = blur(20, 20, 30, 30)   // a new blur being dragged over the redaction
        #expect(RedactionTileCache.orderedEffects(in: start, transient: dragged) == [secret, dragged])
        cache.reconcile(document: start, transient: dragged)
        let pass = try #require(cache.renderTask)
        try await eventually { renderer.calls.count == 1 }

        // The commit, with the transient still set and then cleared, wants the same keys.
        let committed = start.appending(dragged)
        cache.reconcile(document: committed, transient: dragged)
        cache.reconcile(document: committed, transient: nil)
        await gate.open()
        await pass.value
        #expect(renderer.calls == [TileKey(effect: secret, beneath: []), TileKey(effect: dragged, beneath: [secret])])
        let tile = try #require(cache.currentTile(for: dragged, in: committed, transient: nil))

        let nudged = secret.moved(by: CGVector(dx: 1, dy: 0))
        #expect(RedactionTileCache.orderedEffects(in: committed, transient: nudged) == [nudged, dragged])
        cache.reconcile(document: committed, transient: nudged)
        await cache.renderTask?.value
        #expect(renderer.calls.dropFirst(2).map(\.effect) == [nudged, dragged])
        #expect(cache.currentTile(for: dragged, in: committed, transient: nudged) !== tile)
        let movedTile = try #require(cache.currentTile(for: nudged, in: committed, transient: nudged))
        let moveCommitted = committed.replacing(nudged)
        cache.reconcile(document: moveCommitted, transient: nil)
        await cache.renderTask?.value
        #expect(renderer.calls.count == 4)
        #expect(cache.currentTile(for: nudged, in: moveCommitted, transient: nil) === movedTile)
    }

    @Test func allTilesRendersMissingInOrder() async throws {
        let renderer = FakeTileRenderer()
        let cache = makeCache(renderer)
        let secret = redact(10, 10, 20, 20)
        let far = redact(70, 70, 10, 10)
        let start = document(secret, far)
        cache.reconcile(document: start, transient: nil)
        await cache.renderTask?.value
        let secretTile = try #require(cache.tiles[secret.id]?.image)
        let farTile = try #require(cache.tiles[far.id]?.image)

        // Two effects the preview has not rendered, the second over the first.
        let mosaic = pixelate(40, 10, 16, 16, block: 4)
        let blurred = blur(50, 10, 20, 20, radius: 2)   // samples x 44..<76, so it reads `mosaic`
        let export = start.appending(mosaic).appending(blurred)
        let tiles = await cache.allTiles(for: export)

        #expect(tiles.map(\.effect) == [secret, far, mosaic, blurred])
        #expect(tiles[0].image === secretTile)
        #expect(tiles[1].image === farTile)
        #expect(Array(renderer.calls.dropFirst(2)) == [TileKey(effect: mosaic, beneath: []),
                                                         TileKey(effect: blurred, beneath: [mosaic])])
        // Export renders leave the preview's tiles to `reconcile`.
        #expect(cache.tiles[mosaic.id] == nil)
    }

    @Test func removedEffectDropsTile() async throws {
        let renderer = FakeTileRenderer()
        let cache = makeCache(renderer)
        var changes = 0
        cache.onChange = { changes += 1 }
        let secret = redact(10, 10, 20, 20)
        let far = redact(70, 70, 10, 10)
        let dragged = blur(40, 40, 10, 10)               // samples 34..<56, clear of both
        let both = document(secret, far)
        cache.reconcile(document: both, transient: dragged)
        await cache.renderTask?.value
        #expect(cache.tiles.count == 3)
        #expect(changes == 3)

        // Deleting `secret` drops its tile at once; nothing else renders.
        let rest = both.removing(id: secret.id)
        cache.reconcile(document: rest, transient: dragged)
        #expect(cache.tiles[secret.id] == nil)
        #expect(cache.renderTask == nil)
        #expect(changes == 4)

        // Abandoning the drag drops the transient tile too.
        cache.reconcile(document: rest, transient: nil)
        #expect(Set(cache.tiles.keys) == [far.id])
        #expect(renderer.calls.count == 3)
        #expect(changes == 5)
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run:
```bash
xcodegen generate && xcodebuild test -project TidyShot.xcodeproj -scheme TidyShot -destination 'platform=macOS' -derivedDataPath .build 2>&1 | grep -E "Test run with|error:|TEST"
```
Expected: compile errors, among them `cannot find type 'TileKey' in scope` (and `cannot find type 'RedactionTileCache' in scope` if the compiler reaches the test file), then `** TEST FAILED **`.

- [ ] **Step 3: Write the cache**

`TidyShot/Editor/Rendering/RedactionTileCache.swift`:
```swift
import CoreGraphics
import Foundation

/// What a redaction tile was rendered from: the effect's own value and the values of the earlier
/// effects whose pixels reach it, in creation order. Equal keys mean equal tile pixels, so a tile
/// is reused exactly when its key is unchanged.
nonisolated struct TileKey: Equatable, Sendable {
    let effect: Annotation
    let beneath: [Annotation]
}

/// The editor's preview tiles for redact, blur and pixelate, one per effect, rendered by a
/// `TileRendering` (the app's `RedactionRenderer`) off the main actor.
///
/// There is no invalidation pass. `reconcile(document:transient:)` computes the key every effect
/// wants now and renders the effects whose stored key differs. A change to an earlier effect
/// changes the key of every later effect that samples it, so those re-render too. The renders of
/// one call run in creation order in one task, each over the tiles beneath it, and a later call
/// wins: every result is checked against the cache-wide generation before it is stored.
final class RedactionTileCache {
    /// The newest tile for each effect id and the key it was rendered for. An entry whose key
    /// differs from the effect's current key is stale and is never shown; `currentTile` checks.
    private(set) var tiles: [UUID: (key: TileKey, image: CGImage)] = [:]
    /// Called on the main actor after a tile is stored or tiles are dropped.
    var onChange: () -> Void = {}
    /// The render pass for the keys of the latest `reconcile`, or nil when they needed no render.
    /// Awaiting it waits until those tiles are stored; the tests do.
    private(set) var renderTask: Task<Void, Never>?

    private let base: CGImage
    private let renderer: any TileRendering
    private let imageSize: CGSize
    /// The keys the latest `reconcile` asked for. `generation` counts the calls that changed them.
    private var wanted: [UUID: TileKey] = [:]
    private var generation = 0

    init(base: CGImage, renderer: any TileRendering) {
        self.base = base
        self.renderer = renderer
        imageSize = CGSize(width: base.width, height: base.height)
    }

    /// The effects to tile, in creation order. An effect `transient` with the id of an effect in
    /// the document (one being moved or resized) takes that effect's place; a new one comes last.
    /// A transient drawing is ignored.
    nonisolated static func orderedEffects(in document: AnnotationDocument, transient: Annotation?) -> [Annotation] {
        var effects = document.effects
        guard let transient, transient.isEffect else { return effects }
        if let index = effects.firstIndex(where: { $0.id == transient.id }) {
            effects[index] = transient
        } else {
            effects.append(transient)
        }
        return effects
    }

    /// The key each effect's tile needs, by id. `beneath` lists, in creation order, every earlier
    /// effect whose rect meets the effect's sample rect (`EffectGeometry.sampleRect`), plus
    /// everything beneath those: the earlier tile's pixels came from them, so a change to any of
    /// them must change this key too.
    nonisolated static func keys(for effects: [Annotation], imageSize: CGSize) -> [UUID: TileKey] {
        var keys: [UUID: TileKey] = [:]
        var reach: [Set<Int>] = []
        for (index, effect) in effects.enumerated() {
            let sample = sampleArea(of: effect, imageSize: imageSize)
            var below = Set<Int>()
            for earlier in 0..<index where meets(effects[earlier], sample, imageSize: imageSize) {
                below.insert(earlier)
                below.formUnion(reach[earlier])
            }
            reach.append(below)
            keys[effect.id] = TileKey(effect: effect, beneath: below.sorted().map { effects[$0] })
        }
        return keys
    }

    /// The tile to show for `effect` now, or nil while it is pending (the canvas then draws the
    /// placeholder). A stored tile counts only when its key equals the key the effect wants in
    /// `document` with `transient`.
    func currentTile(for effect: Annotation, in document: AnnotationDocument, transient: Annotation?) -> CGImage? {
        guard let entry = tiles[effect.id] else { return nil }
        let effects = Self.orderedEffects(in: document, transient: transient)
        guard let index = effects.firstIndex(where: { $0.id == effect.id }) else { return nil }
        let wanted = Self.keys(for: Array(effects[...index]), imageSize: imageSize)[effect.id]
        return entry.key == wanted ? entry.image : nil
    }

    /// Brings the tiles in line with `document` and `transient`. Tiles of effects that are gone
    /// are dropped at once; the effects whose key changed render in creation order in one task.
    /// Call it after every change to the document or to the transient shape.
    func reconcile(document: AnnotationDocument, transient: Annotation?) {
        let effects = Self.orderedEffects(in: document, transient: transient)
        let keys = Self.keys(for: effects, imageSize: imageSize)
        // Same keys as the pass in flight or done (a commit of the dragged value): let it finish.
        guard keys != wanted else { return }
        wanted = keys
        generation += 1
        let gone = tiles.keys.filter { keys[$0] == nil }
        for id in gone { tiles[id] = nil }
        if !gone.isEmpty { onChange() }
        let stale = effects.filter { tiles[$0.id]?.key != keys[$0.id] }
        guard !stale.isEmpty else {
            renderTask = nil
            return
        }
        let generation = generation
        renderTask = Task { [weak self] in
            await self?.render(stale, keys: keys, generation: generation)
        }
    }

    /// Every tile `document` needs, in creation order, for export: the stored tile when its key
    /// matches, otherwise a new render through the same renderer, so the export equals the
    /// preview. The transient shape is never exported. Leaves `tiles` unchanged.
    func allTiles(for document: AnnotationDocument) async -> [EffectTile] {
        let effects = document.effects
        let keys = Self.keys(for: effects, imageSize: imageSize)
        var done: [UUID: EffectTile] = [:]
        var result: [EffectTile] = []
        for effect in effects {
            guard let key = keys[effect.id] else { continue }
            let image: CGImage?
            if let entry = tiles[effect.id], entry.key == key {
                image = entry.image
            } else {
                image = await renderer.tile(for: effect, over: base, beneath: directlyBeneath(key) { done[$0] })
            }
            guard let image else { continue }
            let tile = EffectTile(effect: effect, image: image)
            done[effect.id] = tile
            result.append(tile)
        }
        return result
    }

    // MARK: Private

    private func render(_ effects: [Annotation], keys: [UUID: TileKey], generation: Int) async {
        for effect in effects {
            guard generation == self.generation else { return }
            guard let key = keys[effect.id], tiles[effect.id]?.key != key else { continue }
            let beneath = directlyBeneath(key) { id in
                guard let entry = self.tiles[id], entry.key == keys[id] else { return nil }
                return EffectTile(effect: entry.key.effect, image: entry.image)
            }
            let image = await renderer.tile(for: effect, over: base, beneath: beneath)
            // A newer reconcile started while this tile rendered: drop it, that pass owns the cache.
            guard generation == self.generation else { return }
            // nil (an effect wholly outside the image) also clears a stale entry.
            tiles[effect.id] = image.map { (key, $0) }
            onChange()
        }
    }

    /// The tiles the renderer composites under `key.effect`: those of the earlier effects whose
    /// rects meet its sample rect, in creation order. `tile` returns a tile only when it matches
    /// the current key of that effect.
    private func directlyBeneath(_ key: TileKey, tile: (UUID) -> EffectTile?) -> [EffectTile] {
        let sample = Self.sampleArea(of: key.effect, imageSize: imageSize)
        return key.beneath.compactMap { earlier in
            Self.meets(earlier, sample, imageSize: imageSize) ? tile(earlier.id) : nil
        }
    }

    /// The pixels an effect reads, rounded out to whole pixels and clipped to the image.
    nonisolated private static func sampleArea(of effect: Annotation, imageSize: CGSize) -> CGRect {
        ImageRects.integral(EffectGeometry.sampleRect(of: effect, imageSize: imageSize), clippedTo: imageSize)
    }

    /// Whether `earlier`'s tile, its rect rounded out to whole pixels, shares at least one pixel
    /// with `sample`. Rects that only touch along an edge share none.
    nonisolated private static func meets(_ earlier: Annotation, _ sample: CGRect, imageSize: CGSize) -> Bool {
        guard let rect = earlier.effectRect else { return false }
        let tile = ImageRects.integral(rect, clippedTo: imageSize)
        return !tile.isEmpty && !sample.isEmpty && tile.intersects(sample)
    }
}
```

- [ ] **Step 4: Run the suite to verify it passes**

Run:
```bash
xcodegen generate && xcodebuild test -project TidyShot.xcodeproj -scheme TidyShot -destination 'platform=macOS' -derivedDataPath .build 2>&1 | grep -E "Test run with|error:|TEST"
```
Expected: no `error:` lines, and `Test run with 273 tests in 41 suites passed`.

This task has no UI, so there is no hand check. Task 10 checks the tiles on screen.

- [ ] **Step 5: Commit**

```bash
git add TidyShot/Editor/Rendering/RedactionTileCache.swift TidyShotTests/FakeTileRenderer.swift TidyShotTests/RedactionTileCacheTests.swift
git commit -m "feat: tile cache for redaction previews"
```

### Task 7: Shared CoreGraphics drawing and the flattener

**Files:**
- Create: `TidyShot/Editor/Rendering/AnnotationDrawing.swift`
- Create: `TidyShot/Editor/Rendering/EditorFlattener.swift`
- Test: `TidyShotTests/EditorFlattenerTests.swift` (new)

No existing file changes.

**Interfaces:**
- Consumes:
  - Task 2 (all nonisolated): `struct RGBA { var red, green, blue, alpha: Double; var cgColor: CGColor }` (sRGB); `ShapeBox(id:rect:color:lineWidth:)`; `Segment(id:from:to:color:lineWidth:)`; `Region(id:rect:)`; `enum Annotation { case rectangle(ShapeBox), arrow(Segment), redact(Region, fill: RGBA), blur(Region, radius: CGFloat), pixelate(Region, block: CGFloat); var id: UUID; var effectRect: CGRect?; func moved(by: CGVector) -> Annotation }`; `struct AnnotationDocument { var annotations: [Annotation]; var effects: [Annotation]; var drawings: [Annotation] }`, both lists in creation order. The tests use the memberwise inits, including `AnnotationDocument(annotations:)`.
  - Task 3: `CanvasTransform.viewPoint(_:) -> CGPoint` and `viewRect(_:) -> CGRect` (image pixels to view points); `ImageRects.integral(_ rect: CGRect, clippedTo size: CGSize) -> CGRect` (empty for a rect wholly outside); `ImageRects.bottomLeft(_ topLeft: CGRect, imageHeight: Int) -> CGRect`.
  - Task 4: `HitTester.handles(for: Annotation) -> [CGPoint]`; `ArrowGeometry.head(from:to:lineWidth:scale:) -> (tip: CGPoint, left: CGPoint, right: CGPoint)`; `ArrowGeometry.shaftEnd(from:to:lineWidth:scale:) -> CGPoint`.
  - Task 5: `nonisolated struct EffectTile: Sendable { let effect: Annotation; let image: CGImage }`. A tile's image covers `ImageRects.integral(effectRect, clippedTo: imageSize)` in native pixels. `RedactionRenderer` returns nil only for a rect wholly outside the image.
  - Existing, tests only: `ImageEncoder.pngData(from:scale:) throws -> Data` (ImageEncoder.swift:21) and `ImageEncoder.decode(_:) -> (image: CGImage, scale: CGFloat)?` (ImageEncoder.swift:42).
- Produces (all nonisolated, no AppKit import):
  - `enum AnnotationDrawing`:
    - `static let handleSide: CGFloat = 8`
    - `static let outlineDash: [CGFloat] = [4, 4]`
    - `static func draw(_ annotation: Annotation, in context: CGContext, scale: CGFloat)`. The CTM maps top-left image pixels. It draws drawings only; effects draw nothing. `scale` is the capture scale, which sizes the arrow head.
    - `static func drawPlaceholder(for effect: Annotation, in context: CGContext)`. Image-pixel CTM. A pending redact gets its fill, forced opaque. A pending blur or pixelate gets grey at 0.5 alpha.
    - `static func drawSelection(for annotation: Annotation, transform: CanvasTransform, scale: CGFloat, in context: CGContext)`. View space. A selected effect gets a two-tone dashed outline, then every selection gets 8 pt handles at `HitTester.handles(for:)`. `scale` here is the view's backing scale factor, used to snap to device pixels.
  - `enum EditorFlattener { static func flatten(base: CGImage, tiles: [EffectTile], document: AnnotationDocument, scale: CGFloat) -> CGImage? }`. It returns nil when no bitmap can be made, or when an effect inside the image has no tile for its current value.
  - What later tasks rely on:
    - Task 8's `renderExport` passes `await tileCache.allTiles(for: document)` and treats nil as a failed export.
    - Task 10's `CanvasView.draw(_:)` calls `draw(_:in:scale: model.scale)` and `drawPlaceholder(for:in:)` under `transform.affine`, then restores the CTM and calls `drawSelection(for:transform: model.transform, scale: backingScale, in:)`, where `backingScale` is the view's own backing scale factor, not `model.scale`. The `draw(_:in:scale:)` calls keep the capture scale.
    - The 4b tasks add their cases to the exhaustive switch in `draw(_:in:scale:)`, which has no `default`, and add tests to `EditorFlattenerTests` with its helpers.

- [ ] **Step 1: Write the failing tests**

The base is 64 x 48 and its green channel encodes the row, so a missing or doubled flip moves pixels to rows the tests can see. Bytes are read exactly as stored, with no colour conversion, and compared with values computed in the same run.

`TidyShotTests/EditorFlattenerTests.swift`:
```swift
import CoreGraphics
import Foundation
import Testing
@testable import TidyShot

/// The export path: the base, then the effect tiles, then the drawings, burned into one bitmap at
/// the capture's own pixel size. The base is 64 x 48 and its green channel encodes the row, so a
/// write to the wrong rows (a missing or doubled flip) lands somewhere visibly different.
struct EditorFlattenerTests {
    static let width = 64
    static let height = 48

    static let redPixel: [UInt8] = [255, 0, 0, 255]
    static let bluePixel: [UInt8] = [0, 0, 255, 255]
    static let greenPixel: [UInt8] = [0, 255, 0, 255]
    static let magentaPixel: [UInt8] = [255, 0, 255, 255]
    static let blackPixel: [UInt8] = [0, 0, 0, 255]
    static let clearPixel: [UInt8] = [0, 0, 0, 0]

    let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!
    let red = RGBA(red: 1, green: 0, blue: 0, alpha: 1)
    let blue = RGBA(red: 0, green: 0, blue: 1, alpha: 1)
    let black = RGBA(red: 0, green: 0, blue: 0, alpha: 1)

    /// Premultiplied RGBA of base pixel (x, y), top-left origin. Green is 3 + 5y, never 0 or 255,
    /// so no base pixel equals any of the colours above.
    nonisolated static func pattern(_ x: Int, _ y: Int) -> [UInt8] {
        [UInt8((x * 4 + y) % 256), UInt8(3 + y * 5), UInt8((x * 7 + y * 11 + 17) % 256), 255]
    }

    /// An image built from rows of premultiplied RGBA, top row first.
    func makeImage(width: Int = EditorFlattenerTests.width, height: Int = EditorFlattenerTests.height,
                   space: CGColorSpace? = nil,
                   pixel: (Int, Int) -> [UInt8] = EditorFlattenerTests.pattern) -> CGImage {
        var bytes: [UInt8] = []
        bytes.reserveCapacity(width * height * 4)
        for y in 0..<height {
            for x in 0..<width { bytes += pixel(x, y) }
        }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                       space: space ?? sRGB,
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: CGDataProvider(data: Data(bytes) as CFData)!,
                       decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
    }

    /// The stored bytes of an 8-bit premultiplied RGBA image, read without any colour conversion.
    struct Bitmap {
        let width: Int
        let height: Int
        let rows: [[UInt8]]

        init(_ image: CGImage) throws {
            try #require(image.bitsPerComponent == 8 && image.bitsPerPixel == 32)
            try #require(image.alphaInfo == .premultipliedLast)
            try #require(image.byteOrderInfo == .orderDefault || image.byteOrderInfo == .order32Big)
            let data = try #require(image.dataProvider?.data) as Data
            width = image.width
            height = image.height
            rows = (0..<image.height).map { y in
                let start = y * image.bytesPerRow
                return Array(data[start..<(start + image.width * 4)])
            }
        }

        /// The pixel at (x, y), top-left origin.
        subscript(x: Int, y: Int) -> [UInt8] {
            Array(rows[y][(x * 4)..<(x * 4 + 4)])
        }

        /// How many pixels differ from `other`, skipping those whose centre lies in `excluded`.
        func differences(from other: Bitmap, excluding excluded: [CGRect] = []) -> Int {
            var count = 0
            for y in 0..<height {
                for x in 0..<width {
                    let centre = CGPoint(x: Double(x) + 0.5, y: Double(y) + 0.5)
                    if excluded.contains(where: { $0.contains(centre) }) { continue }
                    if self[x, y] != other[x, y] { count += 1 }
                }
            }
            return count
        }
    }

    func redact(_ rect: CGRect) -> Annotation {
        .redact(Region(id: UUID(), rect: rect), fill: black)
    }

    func rectangle(_ rect: CGRect, lineWidth: CGFloat = 4) -> Annotation {
        .rectangle(ShapeBox(id: UUID(), rect: rect, color: red, lineWidth: lineWidth))
    }

    func arrow(from: CGPoint, to: CGPoint, lineWidth: CGFloat = 4) -> Annotation {
        .arrow(Segment(id: UUID(), from: from, to: to, color: blue, lineWidth: lineWidth))
    }

    /// A tile whose rows tell top from bottom: magenta on top, a clear bottom row, green between.
    func markedTile(for effect: Annotation, width: Int, height: Int) -> EffectTile {
        EffectTile(effect: effect, image: makeImage(width: width, height: height) { _, y in
            y == 0 ? Self.magentaPixel : y == height - 1 ? Self.clearPixel : Self.greenPixel
        })
    }

    func flatten(_ base: CGImage, _ annotations: [Annotation], tiles: [EffectTile] = [], scale: CGFloat = 1) throws -> CGImage {
        try #require(EditorFlattener.flatten(base: base, tiles: tiles,
                                             document: AnnotationDocument(annotations: annotations), scale: scale))
    }

    func spaceName(_ image: CGImage) -> String? {
        image.colorSpace?.name.map { $0 as String }
    }

    @Test func outputSizeEqualsBase() throws {
        let output = try flatten(makeImage(), [rectangle(CGRect(x: 10, y: 8, width: 30, height: 20))])
        #expect(output.width == 64)
        #expect(output.height == 48)
        #expect(output.bitsPerComponent == 8)
        #expect(output.alphaInfo == .premultipliedLast)
        #expect(spaceName(output) == CGColorSpace.sRGB as String)
    }

    /// With nothing to draw the base comes back byte for byte; one tile changes its own rect only.
    @Test func bytesOutsideEffectsEqualBase() throws {
        let base = makeImage()
        let original = try Bitmap(base)
        #expect(try Bitmap(flatten(base, [])).differences(from: original) == 0)

        let rect = CGRect(x: 8, y: 4, width: 10, height: 6)
        let effect = redact(rect)
        let output = try Bitmap(flatten(base, [effect], tiles: [markedTile(for: effect, width: 10, height: 6)]))
        #expect(output.differences(from: original, excluding: [rect]) == 0)
        #expect(output.differences(from: original) == 60)
    }

    /// The tile's first row lands on image row 4, the top of its rect, not on row 38 where an
    /// unflipped draw would put it. Its pixels replace the base: the clear row stays clear.
    @Test func tileBytesLandAtFlippedRows() throws {
        let base = makeImage()
        let original = try Bitmap(base)
        let effect = redact(CGRect(x: 8, y: 4, width: 10, height: 6))
        let output = try Bitmap(flatten(base, [effect], tiles: [markedTile(for: effect, width: 10, height: 6)]))
        for x in 8..<18 {
            #expect(output[x, 4] == Self.magentaPixel)
            #expect(output[x, 7] == Self.greenPixel)
            #expect(output[x, 9] == Self.clearPixel)
        }
        #expect(output[7, 4] == original[7, 4])
        #expect(output[18, 4] == original[18, 4])
        #expect(output[8, 3] == original[8, 3])
        #expect(output[8, 10] == original[8, 10])
        for y in 38..<44 {
            #expect(output[8, y] == original[8, y])
        }
    }

    /// A 4 px stroke on (10, 8, 30, 20) sits inside the rect: columns 10 to 13 and 36 to 39, rows
    /// 8 to 11 and 24 to 27.
    @Test func rectangleStrokeHitsExpectedPixelsAndCentreUntouched() throws {
        let base = makeImage()
        let original = try Bitmap(base)
        let output = try Bitmap(flatten(base, [rectangle(CGRect(x: 10, y: 8, width: 30, height: 20))]))
        let stroked = [(10, 8), (39, 8), (10, 27), (39, 27), (25, 8), (25, 11), (25, 24), (25, 27),
                       (10, 18), (13, 18), (36, 18), (39, 18)]
        for (x, y) in stroked {
            #expect(output[x, y] == Self.redPixel, "stroke at \(x), \(y)")
        }
        let untouched = [(25, 18), (14, 18), (35, 18), (25, 12), (25, 23), (9, 18), (40, 18), (25, 7), (25, 28)]
        for (x, y) in untouched {
            #expect(output[x, y] == original[x, y], "untouched at \(x), \(y)")
        }
    }

    /// The arrow runs along row 12, away from the middle row, so a flip would move it. A point
    /// halfway between the head's centroid and one barb lies off the 4 px shaft, so its colour
    /// comes from the filled head; the same row near the tail is untouched.
    @Test func arrowHeadPixelPresent() throws {
        let base = makeImage()
        let original = try Bitmap(base)
        let from = CGPoint(x: 8, y: 12)
        let to = CGPoint(x: 56, y: 12)
        let output = try Bitmap(flatten(base, [arrow(from: from, to: to)]))
        let head = ArrowGeometry.head(from: from, to: to, lineWidth: 4, scale: 1)
        let centroid = CGPoint(x: (head.tip.x + head.left.x + head.right.x) / 3,
                               y: (head.tip.y + head.left.y + head.right.y) / 3)
        let probe = CGPoint(x: (centroid.x + head.left.x) / 2, y: (centroid.y + head.left.y) / 2)
        try #require(abs(probe.y - 12) > 3, "the probe lies off the shaft")
        let row = Int(probe.y.rounded(.down))
        #expect(output[Int(probe.x.rounded(.down)), row] == Self.bluePixel)
        #expect(output[12, row] == original[12, row])
        #expect(output[30, 11] == Self.bluePixel)
        #expect(output[61, 12] == original[61, 12])
    }

    /// The rectangle was created before the redaction, yet its stroke covers the tile: effects
    /// belong to the base layer.
    @Test func drawingsRenderAboveTiles() throws {
        let effect = redact(CGRect(x: 8, y: 4, width: 10, height: 6))
        let box = rectangle(CGRect(x: 4, y: 2, width: 30, height: 20))
        let output = try Bitmap(flatten(makeImage(), [box, effect], tiles: [markedTile(for: effect, width: 10, height: 6)]))
        #expect(output[10, 4] == Self.redPixel)
        #expect(output[10, 5] == Self.redPixel)
        #expect(output[10, 6] == Self.greenPixel)
    }

    /// Window captures have transparent corners. One stays clear; a solid redaction over the
    /// other paints opaque pixels.
    @Test func alphaZeroCornerKept() throws {
        let base = makeImage { x, y in
            (x < 4 || x >= 60) && y < 4 ? Self.clearPixel : Self.pattern(x, y)
        }
        let effect = redact(CGRect(x: 60, y: 0, width: 4, height: 4))
        let fill = makeImage(width: 4, height: 4) { _, _ in Self.blackPixel }
        let output = try Bitmap(flatten(base, [effect, rectangle(CGRect(x: 20, y: 20, width: 10, height: 10))],
                                        tiles: [EffectTile(effect: effect, image: fill)]))
        #expect(output[0, 0] == Self.clearPixel)
        #expect(output[3, 3] == Self.clearPixel)
        #expect(output[60, 0] == Self.blackPixel)
        #expect(output[63, 3] == Self.blackPixel)
    }

    /// A Display P3 capture is flattened in P3: untouched pixels are not converted through sRGB.
    @Test func displayP3BaseKeepsColourSpace() throws {
        let p3 = try #require(CGColorSpace(name: CGColorSpace.displayP3))
        let base = makeImage(space: p3)
        let box = CGRect(x: 10, y: 8, width: 30, height: 20)
        let output = try flatten(base, [rectangle(box)])
        #expect(spaceName(output) == CGColorSpace.displayP3 as String)
        #expect(try Bitmap(output).differences(from: Bitmap(base), excluding: [box]) == 0)
    }

    /// A grey base would give a grey bitmap and turn a red stroke grey, so it is drawn into sRGB.
    @Test func greyBaseFallsBackToSRGB() throws {
        let grey = try #require(CGColorSpace(name: CGColorSpace.genericGrayGamma2_2))
        let context = try #require(CGContext(data: nil, width: 64, height: 48, bitsPerComponent: 8, bytesPerRow: 0,
                                             space: grey, bitmapInfo: CGImageAlphaInfo.none.rawValue))
        context.setFillColor(gray: 0.5, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: 64, height: 48))
        let base = try #require(context.makeImage())
        let output = try flatten(base, [rectangle(CGRect(x: 10, y: 8, width: 30, height: 20))])
        #expect(spaceName(output) == CGColorSpace.sRGB as String)
        let pixels = try Bitmap(output)
        #expect(pixels[10, 8] == Self.redPixel)
        let untouched = pixels[25, 18]
        #expect(untouched[3] == 255)
        #expect(abs(Int(untouched[0]) - Int(untouched[1])) <= 1 && abs(Int(untouched[1]) - Int(untouched[2])) <= 1)
    }

    /// Encoding at the capture's scale keeps a Retina edit at 144 DPI.
    @Test func pngRoundTripKeepsScaleTwo() throws {
        let effect = redact(CGRect(x: 8, y: 4, width: 10, height: 6))
        let output = try flatten(makeImage(), [effect, arrow(from: CGPoint(x: 8, y: 30), to: CGPoint(x: 56, y: 30))],
                                 tiles: [markedTile(for: effect, width: 10, height: 6)], scale: 2)
        let decoded = try #require(ImageEncoder.decode(try ImageEncoder.pngData(from: output, scale: 2)))
        #expect(decoded.scale == 2)
        #expect(decoded.image.width == 64)
        #expect(decoded.image.height == 48)
    }

    /// An effect inside the image with no tile, or with a tile rendered for an older value of it,
    /// fails the export instead of shipping what it should hide. An effect wholly outside the
    /// image needs no tile.
    @Test func missingOrStaleTileFailsClosed() {
        let base = makeImage()
        let effect = redact(CGRect(x: 8, y: 4, width: 10, height: 6))
        #expect(EditorFlattener.flatten(base: base, tiles: [], document: AnnotationDocument(annotations: [effect]),
                                        scale: 1) == nil)

        let stale = markedTile(for: effect, width: 10, height: 6)
        let moved = effect.moved(by: CGVector(dx: 4, dy: 0))
        #expect(EditorFlattener.flatten(base: base, tiles: [stale], document: AnnotationDocument(annotations: [moved]),
                                        scale: 1) == nil)

        let outside = redact(CGRect(x: 100, y: 100, width: 10, height: 10))
        #expect(EditorFlattener.flatten(base: base, tiles: [], document: AnnotationDocument(annotations: [outside]),
                                        scale: 1) != nil)
    }
}
```

`pattern` is `nonisolated` because it is the default value of a closure parameter that is not MainActor. Without `nonisolated`, the build fails with `converting function value ... loses global actor 'MainActor'`.

- [ ] **Step 2: Run the tests to verify they fail**

Run:
```bash
xcodegen generate && xcodebuild test -project TidyShot.xcodeproj -scheme TidyShot -destination 'platform=macOS' -derivedDataPath .build 2>&1 | grep -E "error:" | sort -u | head -3
```
Expected: compile errors, among them `cannot find 'EditorFlattener' in scope`.

- [ ] **Step 3: Write the shared drawing routine**

The canvas and the export both draw through this one routine, so the export equals the preview. It touches no NSGraphicsContext and no AppKit type, so the flattener can call it off the main actor.

Some choices are not obvious:
- A rectangle is stroked inset by half its line width, so the stroke sits inside the rect (spec 2.6, Rectangle). A box no wider or taller than the line is filled instead, because the inset rect would be empty.
- A pending redaction's placeholder is opaque whatever the fill's alpha is, so it hides what it covers before the tile arrives. Task 5's redact tile is opaque too.
- `drawSelection` follows spec 2.6, Rendering step 4. Every selection gets handles, and a selected effect also gets the dashed outline, because a blur has no edge of its own. The outline is white under black dashes so it shows on any background.

`TidyShot/Editor/Rendering/AnnotationDrawing.swift`:
```swift
import CoreGraphics

/// The one CoreGraphics routine for annotations. The canvas and the export both draw through it,
/// so the export equals the preview. `draw` and `drawPlaceholder` work in image pixels with a
/// top-left origin: the canvas concatenates `transform.affine` on its flipped view, and the
/// flattener flips its bitmap. `drawSelection` works in view space. Nothing here uses
/// NSGraphicsContext, so the export can run off the main actor.
nonisolated enum AnnotationDrawing {
    /// Selection handles are squares this many points wide at every zoom.
    static let handleSide: CGFloat = 8
    /// The dash pattern of a selected effect's outline, in points.
    static let outlineDash: [CGFloat] = [4, 4]

    /// Draws a drawing in image pixels. Effects draw nothing here, because they are tiles on the
    /// base layer. `scale` is the capture scale, which sizes the arrow head.
    static func draw(_ annotation: Annotation, in context: CGContext, scale: CGFloat) {
        switch annotation {
        case .rectangle(let box):
            drawRectangle(box, in: context)
        case .arrow(let segment):
            drawArrow(segment, in: context, scale: scale)
        case .redact, .blur, .pixelate:
            break
        }
    }

    /// Stands in, in image pixels, for an effect whose tile has not rendered yet. A redaction
    /// shows its fill, always opaque, so a pending redaction hides what it covers. A blur or
    /// pixelate shows grey at 0.5 alpha. The rect is rounded out to whole pixels, as the tile's is.
    static func drawPlaceholder(for effect: Annotation, in context: CGContext) {
        guard let rect = effect.effectRect?.integral, !rect.isEmpty else { return }
        let colour: CGColor
        if case .redact(_, var fill) = effect {
            fill.alpha = 1
            colour = fill.cgColor
        } else {
            colour = CGColor(gray: 0.5, alpha: 0.5)
        }
        context.saveGState()
        defer { context.restoreGState() }
        context.setFillColor(colour)
        context.fill(rect)
    }

    /// Selection chrome in view space, so it keeps its size at every zoom. A selected effect gets
    /// a dashed outline of its rect, white under black so it shows on any background, because a
    /// blur has no edge of its own. Every selection then gets an 8 pt white square with a dark
    /// border at each point of `HitTester.handles(for:)`. `scale` is the view's backing scale
    /// factor: edges snap to device pixels so the 1 pt lines stay sharp.
    static func drawSelection(for annotation: Annotation, transform: CanvasTransform, scale: CGFloat, in context: CGContext) {
        let device = max(scale, 1)
        func snap(_ value: CGFloat) -> CGFloat { (value * device).rounded() / device }
        context.saveGState()
        defer { context.restoreGState() }
        context.setLineWidth(1)
        if let rect = annotation.effectRect {
            let view = transform.viewRect(rect)
            let outline = CGRect(x: snap(view.minX), y: snap(view.minY),
                                 width: snap(view.maxX) - snap(view.minX),
                                 height: snap(view.maxY) - snap(view.minY)).insetBy(dx: 0.5, dy: 0.5)
            context.setStrokeColor(CGColor(gray: 1, alpha: 1))
            context.stroke(outline)
            context.setStrokeColor(CGColor(gray: 0, alpha: 1))
            context.setLineDash(phase: 0, lengths: outlineDash)
            context.stroke(outline)
            context.setLineDash(phase: 0, lengths: [])
        }
        let half = handleSide / 2
        for point in HitTester.handles(for: annotation) {
            let centre = transform.viewPoint(point)
            let square = CGRect(x: snap(centre.x - half), y: snap(centre.y - half), width: handleSide, height: handleSide)
            context.setFillColor(CGColor(gray: 1, alpha: 1))
            context.fill(square)
            context.setStrokeColor(CGColor(gray: 0, alpha: 0.6))
            context.stroke(square.insetBy(dx: 0.5, dy: 0.5))
        }
    }

    /// Stroked inset by half the line width, so the stroke sits inside the rect. A box no wider
    /// or taller than the line is filled instead, because the inset rect would be empty.
    private static func drawRectangle(_ box: ShapeBox, in context: CGContext) {
        let rect = box.rect.standardized
        guard rect.width > 0, rect.height > 0, box.lineWidth > 0 else { return }
        context.saveGState()
        defer { context.restoreGState() }
        if rect.width <= box.lineWidth || rect.height <= box.lineWidth {
            context.setFillColor(box.color.cgColor)
            context.fill(rect)
            return
        }
        context.setStrokeColor(box.color.cgColor)
        context.setLineWidth(box.lineWidth)
        context.setLineJoin(.miter)
        context.stroke(rect.insetBy(dx: box.lineWidth / 2, dy: box.lineWidth / 2))
    }

    /// A round-capped shaft from the tail to `ArrowGeometry.shaftEnd`, then the filled head
    /// triangle from `ArrowGeometry.head`.
    private static func drawArrow(_ segment: Segment, in context: CGContext, scale: CGFloat) {
        guard segment.from != segment.to, segment.lineWidth > 0 else { return }
        let head = ArrowGeometry.head(from: segment.from, to: segment.to, lineWidth: segment.lineWidth, scale: scale)
        let shaftEnd = ArrowGeometry.shaftEnd(from: segment.from, to: segment.to, lineWidth: segment.lineWidth, scale: scale)
        let colour = segment.color.cgColor
        context.saveGState()
        defer { context.restoreGState() }
        context.setStrokeColor(colour)
        context.setFillColor(colour)
        context.setLineWidth(segment.lineWidth)
        context.setLineCap(.round)
        context.move(to: segment.from)
        context.addLine(to: shaftEnd)
        context.strokePath()
        context.move(to: head.tip)
        context.addLine(to: head.left)
        context.addLine(to: head.right)
        context.closePath()
        context.fillPath()
    }
}
```

- [ ] **Step 4: Write the flattener**

It follows spec 2.6, Export, steps 1 to 5. Some choices are not obvious; each of the first three has a test that fails without it:
- **Colour space.** The bitmap uses the base's colour space only when that space is RGB. CoreGraphics does accept a grey space with `premultipliedLast`: it makes a two-channel grey and alpha bitmap, and the drawings would come out grey. Any other space, or one CoreGraphics refuses, falls back to sRGB, and drawing the base converts it once (`greyBaseFallsBackToSRGB`, `displayP3BaseKeepsColourSpace`).
- **Copy blend.** The base and the tiles are drawn with blend mode `.copy`, so each tile replaces its rect. With source-over, a partly transparent blur or pixelate pixel near a window's transparent corner would let the base pixel under it show through (`tileBytesLandAtFlippedRows`, clear row). Drawings go back to `.normal`.
- **Fail closed.** If an effect inside the image has no tile, or its tile was rendered for a different value, `flatten` returns nil instead of exporting the pixels that effect should hide. An effect wholly outside the image needs no tile (`missingOrStaleTileFailsClosed`).
- **Order and flip.** Tiles are drawn in `document.effects` order and found by id, so creation order holds even if `tiles` arrives in another order. The flip to top-left comes after the tiles, because `ImageRects.bottomLeft` already places them in CoreGraphics coordinates.
- **Debug log.** The colour-space names of the first flatten are logged once per run in Debug. The flag is an `Atomic<Bool>`, because Swift 6 rejects a plain mutable static in a nonisolated type.

`TidyShot/Editor/Rendering/EditorFlattener.swift`:
```swift
import CoreGraphics
import Foundation
import Synchronization

/// Burns the effect tiles and the drawings into a copy of the capture, at the capture's own pixel
/// size, for Save, Save Copy, Copy and Upload. `EditorModel.renderExport` calls it inside
/// `Task.detached(priority: .userInitiated)`. It uses no NSGraphicsContext, which is MainActor.
///
/// For an 8-bit RGB base, every pixel outside the effects and drawings equals the base byte for
/// byte, alpha included, so window captures keep their transparent corners. Each tile replaces
/// the pixels of its rect (blend mode copy), so nothing of the base shows through a tile, and a
/// solid redaction over a transparent corner paints opaque pixels.
nonisolated enum EditorFlattener {
    /// Nil when no bitmap can be made, or when an effect inside the image has no tile for its
    /// current value: the export fails rather than ship the pixels that effect should hide. An
    /// effect wholly outside the image needs no tile. `tiles` comes from
    /// `RedactionTileCache.allTiles(for:)`, one per effect, each covering
    /// `ImageRects.integral(effectRect, clippedTo:)` in native pixels.
    static func flatten(base: CGImage, tiles: [EffectTile], document: AnnotationDocument, scale: CGFloat) -> CGImage? {
        let width = base.width
        let height = base.height
        let size = CGSize(width: width, height: height)
        guard let context = makeContext(width: width, height: height, preferred: base.colorSpace) else { return nil }
        logColourSpaceOnce(base: base, output: context)
        context.interpolationQuality = .none

        // 1. The base, copied in. CoreGraphics coordinates here: origin bottom left.
        context.setBlendMode(.copy)
        context.draw(base, in: CGRect(origin: .zero, size: size))

        // 2. The tiles in creation order, each replacing its rect.
        let tileByID = Dictionary(tiles.map { ($0.effect.id, $0) }, uniquingKeysWith: { _, last in last })
        for effect in document.effects {
            guard let effectRect = effect.effectRect else { continue }
            let rect = ImageRects.integral(effectRect, clippedTo: size)
            guard !rect.isEmpty else { continue }
            guard let tile = tileByID[effect.id], tile.effect == effect else { return nil }
            context.draw(tile.image, in: ImageRects.bottomLeft(rect, imageHeight: height))
        }

        // 3. The drawings, in top-left image pixels as on the canvas, through the same routine.
        context.setBlendMode(.normal)
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)
        for drawing in document.drawings {
            AnnotationDrawing.draw(drawing, in: context, scale: scale)
        }
        return context.makeImage()
    }

    /// An 8-bit premultiplied RGBA bitmap in the base's colour space when that space is RGB and
    /// CoreGraphics accepts it, otherwise in sRGB; drawing the base then converts it once. A grey
    /// base would otherwise give a grey bitmap and grey arrows.
    private static func makeContext(width: Int, height: Int, preferred: CGColorSpace?) -> CGContext? {
        let info = CGImageAlphaInfo.premultipliedLast.rawValue
        if let preferred, preferred.model == .rgb,
           let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                   space: preferred, bitmapInfo: info) {
            return context
        }
        guard let sRGB = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        return CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                         space: sRGB, bitmapInfo: info)
    }

    #if DEBUG
    /// Set by the first flatten, so the colour space real captures carry is logged once per run.
    private static let loggedColourSpace = Atomic<Bool>(false)
    #endif

    private static func logColourSpaceOnce(base: CGImage, output: CGContext) {
        #if DEBUG
        guard !loggedColourSpace.exchange(true, ordering: .relaxed) else { return }
        let baseName = base.colorSpace?.name.map { $0 as String } ?? "none"
        let outputName = output.colorSpace?.name.map { $0 as String } ?? "none"
        NSLog("EditorFlattener: base colour space \(baseName), flattened in \(outputName)")
        #endif
    }
}
```

- [ ] **Step 5: Run the suite**

Run:
```bash
xcodegen generate && xcodebuild test -project TidyShot.xcodeproj -scheme TidyShot -destination 'platform=macOS' -derivedDataPath .build 2>&1 | grep -E "Test run with|error:|TEST"
```
Expected: no `error:` lines, then `Test run with 284 tests in 42 suites passed`.

- [ ] **Step 6: Hand check**

None in this task. Nothing draws on screen until Task 10, whose hand checks cover the placeholders, the handles and the dashed outline.

- [ ] **Step 7: Commit**

```bash
git add TidyShot/Editor/Rendering/AnnotationDrawing.swift TidyShot/Editor/Rendering/EditorFlattener.swift TidyShotTests/EditorFlattenerTests.swift
git commit -m "feat: flatten annotations to native pixels"
```

### Task 8: EditorModel with snapshot undo, and the end-to-end redaction export test

**Files:**
- Create: `TidyShot/Editor/Tools/CanvasTool.swift`
- Create: `TidyShot/Editor/Session/EditorModel.swift`
- Test: `TidyShotTests/EditorModelTests.swift` (new suite `EditorModelTests`, 15 tests)
- Test: `TidyShotTests/RedactionExportTests.swift` (new suite `RedactionExportTests`, 5 tests)

No existing file changes. `xcodegen generate` picks up the new `Editor/Session/` and `Editor/Tools/` folders.

**Interfaces:**
- Consumes:
  - Task 2: `nonisolated struct ScaledImage: Sendable { let image: CGImage; let scale: CGFloat }`; `RGBA(red:green:blue:alpha:)`; `ShapeBox(id:rect:color:lineWidth:)`, `Segment(id:from:to:color:lineWidth:)`, `Region(id:rect:)`; `enum Annotation` with `rectangle(ShapeBox)`, `arrow(Segment)`, `redact(Region, fill: RGBA)`, `blur(Region, radius: CGFloat)`, `pixelate(Region, block: CGFloat)`, `var id: UUID`, `var isEffect: Bool`, `var effectRect: CGRect?`, `func withColor(_: RGBA) -> Annotation` (sets the colour of a rectangle or arrow and the fill of a redaction; returns blur and pixelate unchanged), `func withLineWidth(_: CGFloat) -> Annotation` (effects unchanged), `func withEffectParameter(_: CGFloat) -> Annotation` (blur radius or pixel block); `AnnotationDocument(annotations:)` with `effects`, `drawings`, `annotation(id:)`, `appending(_:)`, `removing(id:)`, `replacing(_:)`, `moving(id:by:)`; `enum EditorTool { case select, redact, pixelate, blur, rectangle, arrow }`; `RedactionDefaults.blurRadius(points:scale:)` and `RedactionDefaults.block(points:scale:region:)`; `struct EditorDefaults { var strokeColor, redactColor: RGBA; var lineWidthPoints, blurRadiusPoints, blockPoints: CGFloat; static let standard }` (red, black, 4, 8, 10).
  - Task 3: `struct CanvasTransform { var zoom: CGFloat; var offset: CGPoint }` with its memberwise `init(zoom:offset:)`, where `zoom` is view points per image pixel; `ImageRects.integral(_ rect: CGRect, clippedTo size: CGSize) -> CGRect` (empty when the rect misses the image).
  - Task 5: `nonisolated protocol TileRendering: Sendable { func tile(for effect: Annotation, over base: CGImage, beneath: [EffectTile]) async -> CGImage? }`; `nonisolated struct EffectTile: Sendable { let effect: Annotation; let image: CGImage }`; `actor RedactionRenderer: TileRendering { init() }`.
  - Task 6: `RedactionTileCache(base: CGImage, renderer: any TileRendering)`, `func reconcile(document: AnnotationDocument, transient: Annotation?)`, `func allTiles(for document: AnnotationDocument) async -> [EffectTile]`; the test helper `FakeTileRenderer()` (TidyShotTests/FakeTileRenderer.swift, `gate` defaulting to nil).
  - Task 7: `EditorFlattener.flatten(base: CGImage, tiles: [EffectTile], document: AnnotationDocument, scale: CGFloat) -> CGImage?` (nonisolated).
  - Existing: `nonisolated enum ImageEncoder` with `static func pngData(from image: CGImage, scale: CGFloat) throws -> Data` (TidyShot/Output/ImageEncoder.swift:21) and `static func decode(_ data: Data) -> (image: CGImage, scale: CGFloat)?` (ImageEncoder.swift:42).
- Produces:
  - `nonisolated struct ToolInput: Equatable, Sendable { var point: CGPoint; var shift = false; var option = false; var clickCount = 1 }`, in image pixels with a top-left origin.
  - `protocol CanvasEditing: AnyObject { var document: AnnotationDocument { get }; var zoom: CGFloat { get }; var scale: CGFloat { get }; var transient: Annotation? { get set }; var selection: UUID? { get set }; func commit(_ new: AnnotationDocument, actionName: String, coalescingKey: String?); func makeAnnotation(_ tool: EditorTool, from: CGPoint, to: CGPoint) -> Annotation? }`. The contract Task 9's tools rely on:
    - A tool commits once per gesture, on mouseUp, while `transient` still holds the shape. A commit whose document contains the transient's id clears `transient` itself, so an effect's tile carries over instead of rendering again.
    - `makeAnnotation` reuses `transient?.id`, so one drag keeps one id. It returns nil for `.select`, for an empty rect and for a zero-length arrow.
    - A nil `transient` at mouseUp means Escape abandoned the drag, and the tool commits nothing.
  - `protocol CanvasTool: AnyObject { var cursor: NSCursor { get }; func mouseDown(_ input: ToolInput, on editing: any CanvasEditing); func mouseDragged(_ input: ToolInput, on editing: any CanvasEditing); func mouseUp(_ input: ToolInput, on editing: any CanvasEditing); func flagsChanged(_ input: ToolInput, on editing: any CanvasEditing) }`.
  - `nonisolated enum EffectParameter: Sendable { case blurRadius, block }`.
  - `@Observable final class EditorModel: CanvasEditing` with:
    - `init(recordID: UUID, image: ScaledImage, renderer: any TileRendering, defaults: EditorDefaults)`.
    - `enum ActionName { static let delete = "Delete", move = "Move", color = "Color", lineWidth = "Line Width", blurRadius = "Blur Radius", block = "Block Size" }`.
    - `let recordID: UUID; let base: CGImage; let scale: CGFloat; private(set) var document: AnnotationDocument; var hasUnsavedChanges: Bool { get }`.
    - `var selection: UUID?; var transient: Annotation?; var tool: EditorTool /* starts at .redact */; var strokeColor, redactColor: RGBA; var lineWidthPoints, blurRadiusPoints, blockPoints: CGFloat; var transform: CanvasTransform; var zoom: CGFloat { get }; var activeColor: RGBA { get }`.
    - `@ObservationIgnored let undoManager: UndoManager /* groupsByEvent = false */; @ObservationIgnored let tileCache: RedactionTileCache`.
    - `func commit(_ new: AnnotationDocument, actionName: String, coalescingKey: String? = nil); func makeAnnotation(_ tool: EditorTool, from: CGPoint, to: CGPoint) -> Annotation?; func deleteSelection(); func nudgeSelection(by delta: CGVector)`.
    - `func applyColor(_ color: RGBA); func applyLineWidth(points: CGFloat); func applyEffectParameter(_ parameter: EffectParameter, points: CGFloat)`.
    - `func cancelCurrentOperation(); func selectAll(); func markSaved(); func renderExport() async -> ScaledImage?`.

The rules the model applies:
- `commit` is the only write. Each call is one explicit undo group whose handler puts the previous snapshot back. That restore registers the inverse, which gives redo. A document equal to the current one is not a step.
- Coalescing has no timers. When `coalescingKey` equals the last commit's key, the document changes with no new registration. The key is cleared by any other commit, by undo, by redo and by a selection change. Arrow-key nudges use `Nudge-<id>`; `applyColor`, `applyLineWidth` and `applyEffectParameter` use `<action name>-<id>`, so a slider drag on a blur is `Blur Radius-<id>`, one step.
- Selection, zoom, pan, tool and colour choice never enter the undo stack. A commit or undo that removes the selected annotation clears `selection`.
- The palette: the Redact tool, or the Select tool with a redaction selected, edits `redactColor`; anything else edits `strokeColor`. The selected annotation also takes the colour through a coalesced commit. `activeColor` is the one rule for "the colour the palette currently shows": the selected annotation's colour, else the default the palette would edit. Task 11 reads it for the toolbar's colour circle and for the palette's current swatch and custom picker, and defines no second property for it.
- `applyLineWidth` and `applyEffectParameter` set the default in points, then change the selection when it is the matching kind: line width for a rectangle or arrow, blur radius for a blur, block for a pixelate. Stored values are image pixels: `points * scale`, `RedactionDefaults.blurRadius(points:scale:)`, `RedactionDefaults.block(points:scale:region:)`.
- `cancelCurrentOperation()` (Escape, ⌘.) clears `transient` when there is one, and otherwise deselects. `selectAll()` (⌘A) selects the frontmost annotation: the last drawing, else the last effect, the same front-to-back order as `HitTester.topmost`.
- `renderExport()` awaits `tileCache.allTiles(for:)`, then flattens in `Task.detached(priority: .userInitiated)`, and returns the capture's scale. It returns nil when an effect that covers any image pixel has no tile, because exporting without it would leave the pixels underneath unredacted. Callers treat nil as a failed export.

- [ ] **Step 1: Write the failing model tests**

`TidyShotTests/EditorModelTests.swift`:
```swift
import CoreGraphics
import Foundation
import Testing
@testable import TidyShot

/// A renderer that never produces a tile, standing in for a Core Image failure.
nonisolated struct NoTileRenderer: TileRendering {
    func tile(for effect: Annotation, over base: CGImage, beneath: [EffectTile]) async -> CGImage? { nil }
}

struct EditorModelTests {
    let red = RGBA(red: 1, green: 0, blue: 0, alpha: 1)
    let blue = RGBA(red: 0, green: 0, blue: 1, alpha: 1)
    let black = RGBA(red: 0, green: 0, blue: 0, alpha: 1)
    let white = RGBA(red: 1, green: 1, blue: 1, alpha: 1)

    /// A model over a 16x16 opaque grey capture at scale 2, with the standard defaults.
    func makeModel(renderer: any TileRendering = FakeTileRenderer()) -> EditorModel {
        let context = CGContext(data: nil, width: 16, height: 16, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(srgbRed: 0.5, green: 0.5, blue: 0.5, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 16, height: 16))
        return EditorModel(recordID: UUID(), image: ScaledImage(image: context.makeImage()!, scale: 2),
                           renderer: renderer, defaults: .standard)
    }

    func box(x: CGFloat = 2, color: RGBA? = nil) -> Annotation {
        .rectangle(ShapeBox(id: UUID(), rect: CGRect(x: x, y: 2, width: 6, height: 4), color: color ?? red, lineWidth: 4))
    }

    func blurRegion(radius: CGFloat) -> Annotation {
        .blur(Region(id: UUID(), rect: CGRect(x: 4, y: 4, width: 8, height: 8)), radius: radius)
    }

    func redaction() -> Annotation {
        .redact(Region(id: UUID(), rect: CGRect(x: 8, y: 8, width: 4, height: 4)), fill: black)
    }

    /// Commits `annotation` as its own step, as a tool does on mouseUp.
    @discardableResult
    func add(_ annotation: Annotation, to model: EditorModel) -> Annotation {
        model.commit(model.document.appending(annotation), actionName: "Add")
        return annotation
    }

    /// Undoes every step and returns the document after each undo.
    func undoAll(_ model: EditorModel) -> [AnnotationDocument] {
        var documents: [AnnotationDocument] = []
        while model.undoManager.canUndo, documents.count < 50 {
            model.undoManager.undo()
            documents.append(model.document)
        }
        return documents
    }

    @Test func commitRegistersOneUndoStepWithName() {
        let model = makeModel()
        #expect(model.undoManager.groupsByEvent == false)
        #expect(!model.undoManager.canUndo)
        let shape = box()
        model.commit(model.document.appending(shape), actionName: "Rectangle")
        #expect(model.document.annotations == [shape])
        #expect(model.undoManager.undoActionName == "Rectangle")
        #expect(model.undoManager.groupingLevel == 0)
        // An unchanged document is not a step.
        model.commit(model.document, actionName: "Nothing")
        #expect(model.undoManager.undoActionName == "Rectangle")
        #expect(undoAll(model) == [AnnotationDocument(annotations: [])])
    }

    @Test func undoRestoresSnapshotAndRedoReapplies() {
        let model = makeModel()
        let before = model.document
        model.commit(model.document.appending(box()), actionName: "Rectangle")
        let after = model.document
        model.undoManager.undo()
        #expect(model.document == before)
        #expect(model.undoManager.canRedo)
        #expect(model.undoManager.redoActionName == "Rectangle")
        #expect(model.undoManager.groupingLevel == 0)
        model.undoManager.redo()
        #expect(model.document == after)
        #expect(model.undoManager.undoActionName == "Rectangle")
        #expect(!model.undoManager.canRedo)
        model.undoManager.undo()
        #expect(model.document == before)
    }

    @Test func twoCommitsTwoUndos() {
        let model = makeModel()
        let first = add(box(x: 2), to: model)
        add(box(x: 8), to: model)
        #expect(undoAll(model) == [AnnotationDocument(annotations: [first]), AnnotationDocument(annotations: [])])
    }

    @Test func coalescedNudgesAreOneStep() {
        let model = makeModel()
        let shape = add(box(), to: model)
        let added = model.document
        model.selection = shape.id
        for _ in 0..<3 {
            model.nudgeSelection(by: CGVector(dx: 1, dy: 0))
        }
        #expect(model.document == added.moving(id: shape.id, by: CGVector(dx: 3, dy: 0)))
        #expect(model.undoManager.undoActionName == EditorModel.ActionName.move)
        #expect(undoAll(model) == [added, AnnotationDocument(annotations: [])])
    }

    @Test func differentCoalescingKeyStartsNewStep() {
        let empty = AnnotationDocument(annotations: [])
        let one = empty.appending(box(x: 2))
        let two = one.appending(box(x: 6))
        let three = two.appending(box(x: 10))

        // The same key folds into the last step; a different key starts a new one.
        let keyed = makeModel()
        keyed.commit(one, actionName: "Width", coalescingKey: "A")
        keyed.commit(two, actionName: "Width", coalescingKey: "A")
        keyed.commit(three, actionName: "Radius", coalescingKey: "B")
        #expect(undoAll(keyed) == [two, empty])

        // A commit without a key ends the burst.
        let interrupted = makeModel()
        interrupted.commit(one, actionName: "Width", coalescingKey: "A")
        interrupted.commit(two, actionName: "Add", coalescingKey: nil)
        interrupted.commit(three, actionName: "Width", coalescingKey: "A")
        #expect(undoAll(interrupted) == [two, one, empty])

        // So does a selection change.
        let reselected = makeModel()
        reselected.commit(one, actionName: "Width", coalescingKey: "A")
        reselected.selection = one.annotations[0].id
        reselected.commit(two, actionName: "Width", coalescingKey: "A")
        #expect(undoAll(reselected) == [one, empty])
    }

    @Test func undoClearsCoalescing() {
        let empty = AnnotationDocument(annotations: [])
        let one = empty.appending(box(x: 2))
        let two = one.appending(box(x: 6))

        // After an undo the same key registers a new step, so the change can be undone.
        let undone = makeModel()
        undone.commit(one, actionName: "Width", coalescingKey: "A")
        undone.undoManager.undo()
        undone.commit(two, actionName: "Width", coalescingKey: "A")
        #expect(undoAll(undone) == [empty])

        // The same after a redo.
        let redone = makeModel()
        redone.commit(one, actionName: "Width", coalescingKey: "A")
        redone.undoManager.undo()
        redone.undoManager.redo()
        redone.commit(two, actionName: "Width", coalescingKey: "A")
        #expect(undoAll(redone) == [one, empty])
    }

    @Test func selectionAndZoomNotUndone() {
        let model = makeModel()
        let first = add(box(x: 2), to: model)
        add(box(x: 8), to: model)
        model.selection = first.id
        model.transform.zoom = 2
        model.tool = .blur
        model.strokeColor = blue
        model.undoManager.undo()
        #expect(model.document.annotations == [first])
        #expect(model.selection == first.id)
        #expect(model.transform.zoom == 2)
        #expect(model.tool == .blur)
        #expect(model.strokeColor == blue)
        model.undoManager.undo()
        #expect(!model.undoManager.canUndo)
        // Its annotation is gone, so the selection is too.
        #expect(model.selection == nil)
    }

    @Test func selectAllAndCancelOnlyChangeSelection() {
        let model = makeModel()
        let shape = add(box(), to: model)
        add(blurRegion(radius: 16), to: model)
        model.selectAll()
        // Drawings sit above effects, so the rectangle is frontmost although the blur is newer.
        #expect(model.selection == shape.id)
        model.transient = model.makeAnnotation(.redact, from: CGPoint(x: 1, y: 1), to: CGPoint(x: 9, y: 9))
        model.cancelCurrentOperation()
        #expect(model.transient == nil)
        #expect(model.selection == shape.id)
        model.cancelCurrentOperation()
        #expect(model.selection == nil)
        #expect(undoAll(model).count == 2)
    }

    @Test func hasUnsavedChangesFollowsMarkSavedAndUndo() {
        let model = makeModel()
        #expect(!model.hasUnsavedChanges)
        add(box(), to: model)
        #expect(model.hasUnsavedChanges)
        model.markSaved()
        #expect(!model.hasUnsavedChanges)
        model.undoManager.undo()
        #expect(model.hasUnsavedChanges)
        model.undoManager.redo()
        #expect(!model.hasUnsavedChanges)
    }

    @Test func deleteSelectionCommitsOnce() {
        let model = makeModel()
        let first = add(box(x: 2), to: model)
        let second = add(box(x: 8), to: model)
        // Nothing selected: no step.
        model.deleteSelection()
        #expect(model.document.annotations == [first, second])
        #expect(model.undoManager.undoActionName == "Add")

        model.selection = first.id
        model.deleteSelection()
        #expect(model.document.annotations == [second])
        #expect(model.selection == nil)
        #expect(model.undoManager.undoActionName == EditorModel.ActionName.delete)
        model.undoManager.undo()
        #expect(model.document.annotations == [first, second])
        #expect(undoAll(model).count == 2)
    }

    @Test func applyColorToSelectionIsUndoable() {
        let model = makeModel()
        model.tool = .select
        let shape = add(box(color: red), to: model)
        let secret = add(redaction(), to: model)

        model.selection = shape.id
        #expect(model.activeColor == red)
        model.applyColor(blue)
        #expect(model.document.annotation(id: shape.id) == shape.withColor(blue))
        #expect(model.strokeColor == blue)
        #expect(model.activeColor == blue)
        #expect(model.undoManager.undoActionName == EditorModel.ActionName.color)
        model.undoManager.undo()
        #expect(model.document.annotation(id: shape.id) == shape)

        // Under Select, a selected redaction takes the fill, and the redact default follows.
        model.selection = secret.id
        model.applyColor(white)
        #expect(model.document.annotation(id: secret.id) == secret.withColor(white))
        #expect(model.redactColor == white)
        #expect(model.strokeColor == blue)

        // With nothing selected only the active tool's default changes, and no step is added.
        model.selection = nil
        model.tool = .redact
        model.applyColor(red)
        #expect(model.redactColor == red)
        #expect(model.activeColor == red)
        #expect(undoAll(model).count == 3)
    }

    @Test func sliderBurstOnSelectedBlurIsOneStep() {
        let model = makeModel()
        let effect = add(blurRegion(radius: RedactionDefaults.blurRadius(points: 8, scale: 2)), to: model)
        let added = model.document
        model.selection = effect.id
        for points in [10, 12, 14] as [CGFloat] {
            model.applyEffectParameter(.blurRadius, points: points)
        }
        let expected = effect.withEffectParameter(RedactionDefaults.blurRadius(points: 14, scale: 2))
        #expect(model.document.annotation(id: effect.id) == expected)
        #expect(model.blurRadiusPoints == 14)
        #expect(model.undoManager.undoActionName == EditorModel.ActionName.blurRadius)
        model.undoManager.undo()
        #expect(model.document == added)

        // The block slider sets its default and leaves a selected blur alone.
        model.applyEffectParameter(.block, points: 20)
        #expect(model.blockPoints == 20)
        #expect(model.document == added)
    }

    @Test func makeAnnotationUsesToolSettingsInImagePixels() {
        let model = makeModel()
        // Dragged up and to the left: the rect is normalised, the arrow keeps its direction.
        let from = CGPoint(x: 12, y: 10)
        let to = CGPoint(x: 2, y: 4)
        let rect = CGRect(x: 2, y: 4, width: 10, height: 6)

        if case .rectangle(let shape)? = model.makeAnnotation(.rectangle, from: from, to: to) {
            #expect(shape.rect == rect)
            #expect(shape.color == model.strokeColor)
            #expect(shape.lineWidth == model.lineWidthPoints * 2)
        } else {
            Issue.record("no rectangle")
        }
        if case .arrow(let segment)? = model.makeAnnotation(.arrow, from: from, to: to) {
            #expect(segment.from == from)
            #expect(segment.to == to)
            #expect(segment.lineWidth == model.lineWidthPoints * 2)
        } else {
            Issue.record("no arrow")
        }
        if case .redact(let region, let fill)? = model.makeAnnotation(.redact, from: from, to: to) {
            #expect(region.rect == rect)
            #expect(fill == model.redactColor)
        } else {
            Issue.record("no redaction")
        }
        if case .blur(_, let radius)? = model.makeAnnotation(.blur, from: from, to: to) {
            #expect(radius == RedactionDefaults.blurRadius(points: model.blurRadiusPoints, scale: 2))
        } else {
            Issue.record("no blur")
        }
        if case .pixelate(_, let block)? = model.makeAnnotation(.pixelate, from: from, to: to) {
            #expect(block == RedactionDefaults.block(points: model.blockPoints, scale: 2, region: rect))
        } else {
            Issue.record("no pixelate")
        }
        #expect(model.makeAnnotation(.select, from: from, to: to) == nil)
        #expect(model.makeAnnotation(.redact, from: from, to: CGPoint(x: 12, y: 20)) == nil)
        #expect(model.makeAnnotation(.arrow, from: from, to: from) == nil)

        // One drag keeps one id, so the transient's tile carries over on commit.
        model.transient = model.makeAnnotation(.redact, from: from, to: to)
        let id = model.transient?.id
        #expect(id != nil)
        #expect(model.makeAnnotation(.redact, from: from, to: .zero)?.id == id)
        model.transient = nil
        #expect(model.makeAnnotation(.redact, from: from, to: to)?.id != id)
    }

    @Test func renderExportReturnsCaptureScale() async throws {
        let model = makeModel()
        add(box(), to: model)
        let export = try #require(await model.renderExport())
        #expect(export.scale == 2)
        #expect(export.image.width == 16)
        #expect(export.image.height == 16)
    }

    @Test func renderExportFailsWhenAnEffectTileIsMissing() async {
        let model = makeModel(renderer: NoTileRenderer())
        // An effect wholly outside the image covers nothing, so the export goes ahead.
        add(.blur(Region(id: UUID(), rect: CGRect(x: 40, y: 40, width: 8, height: 8)), radius: 16), to: model)
        #expect(await model.renderExport() != nil)
        // A redaction over the image without its tile would export the secret: no export.
        add(redaction(), to: model)
        #expect(await model.renderExport() == nil)
    }
}
```

- [ ] **Step 2: Write the end-to-end redaction tests**

`TidyShotTests/RedactionExportTests.swift`:
```swift
import CoreGraphics
import Foundation
import Testing
@testable import TidyShot

/// The automated proof that redaction leaves no secret pixel. The real RedactionRenderer (a fresh
/// instance, not `.shared`) runs through EditorModel.renderExport, ImageEncoder.pngData and
/// ImageEncoder.decode, and the decoded bytes are checked. Every expected value is computed in
/// the same run; there are no golden files.
struct RedactionExportTests {
    static let width = 64
    static let height = 48

    /// The source pixels, RGBA, top row first: a fixed-seed xorshift stream, opaque, every colour
    /// channel in 16...239, so no pixel equals the black fill.
    let source: [UInt8]
    let model: EditorModel

    init() {
        var state: UInt32 = 0x9E37_79B9
        var bytes = [UInt8](repeating: 255, count: Self.width * Self.height * 4)
        for index in stride(from: 0, to: bytes.count, by: 4) {
            for channel in 0..<3 {
                state ^= state << 13
                state ^= state >> 17
                state ^= state << 5
                bytes[index + channel] = UInt8(16 + state % 224)
            }
        }
        source = bytes
        let image = CGImage(width: Self.width, height: Self.height, bitsPerComponent: 8, bitsPerPixel: 32,
                            bytesPerRow: Self.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                            provider: CGDataProvider(data: Data(bytes) as CFData)!, decode: nil,
                            shouldInterpolate: false, intent: .defaultIntent)!
        model = EditorModel(recordID: UUID(), image: ScaledImage(image: image, scale: 2),
                            renderer: RedactionRenderer(), defaults: .standard)
    }

    /// Adds what `tool` makes for a drag from `from` to `to`, as the tools do.
    @discardableResult
    func add(_ tool: EditorTool, from: CGPoint, to: CGPoint) throws -> Annotation {
        let annotation = try #require(model.makeAnnotation(tool, from: from, to: to))
        model.commit(model.document.appending(annotation), actionName: "Add")
        return annotation
    }

    /// Exports, encodes and decodes as Save and Copy do. The bytes are RGBA, top row first.
    func exportedPixels() async throws -> (scale: CGFloat, width: Int, height: Int, bytes: [UInt8]) {
        let export = try #require(await model.renderExport())
        let png = try ImageEncoder.pngData(from: export.image, scale: export.scale)
        let decoded = try #require(ImageEncoder.decode(png))
        let bytes = try rgba(of: decoded.image)
        return (decoded.scale, decoded.image.width, decoded.image.height, bytes)
    }

    /// `image` drawn 1:1 into an RGBA buffer in its own colour space, so no value is converted.
    func rgba(of image: CGImage) throws -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let space = image.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!
        let drawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: image.width, height: image.height,
                                          bitsPerComponent: 8, bytesPerRow: image.width * 4, space: space,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.interpolationQuality = .none
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            return true
        }
        try #require(drawn)
        return bytes
    }

    func pixel(_ bytes: [UInt8], _ x: Int, _ y: Int) -> [UInt8] {
        let index = (y * Self.width + x) * 4
        return Array(bytes[index..<index + 4])
    }

    /// Every pixel position inside `rect` (image pixels, top-left origin).
    func positions(in rect: CGRect) -> [(x: Int, y: Int)] {
        (Int(rect.minY)..<Int(rect.maxY)).flatMap { y in
            (Int(rect.minX)..<Int(rect.maxX)).map { (x: $0, y: y) }
        }
    }

    func rect(of effect: Annotation) throws -> CGRect {
        try #require(effect.effectRect)
    }

    @Test func redactRegionHoldsOnlyFillAfterPNGRoundTrip() async throws {
        let secret = try add(.redact, from: CGPoint(x: 8, y: 8), to: CGPoint(x: 40, y: 32))
        let fill = model.redactColor
        let expected = [fill.red, fill.green, fill.blue, fill.alpha].map { UInt8(($0 * 255).rounded()) }
        let inside = positions(in: try rect(of: secret))
        // The fixture means something: no source pixel already equals the fill.
        #expect(!inside.contains { pixel(source, $0.x, $0.y) == expected })

        let exported = try await exportedPixels()
        let wrong = inside.filter { pixel(exported.bytes, $0.x, $0.y) != expected }
        #expect(wrong.isEmpty, "\(wrong.count) of \(inside.count) pixels are not the fill")
    }

    @Test func blurOverRedactLeaksNoSourcePixel() async throws {
        // Sigma 8 px, so the middle of a 48x32 redaction lies 1.75 sigma or more inside it.
        model.blurRadiusPoints = 4
        let secret = try add(.redact, from: CGPoint(x: 8, y: 8), to: CGPoint(x: 56, y: 40))
        try add(.blur, from: .zero, to: CGPoint(x: Self.width, y: Self.height))
        let exported = try await exportedPixels()

        let inside = positions(in: try rect(of: secret))
        let leaked = inside.filter { pixel(exported.bytes, $0.x, $0.y) == pixel(source, $0.x, $0.y) }
        #expect(leaked.isEmpty, "\(leaked.count) pixels inside the redaction kept their source value")

        // The blur sampled the fill, not the secret, so the middle stays dark. Blurring the source
        // instead would give its mean, about 128 or more in every channel.
        let middle = positions(in: CGRect(x: 30, y: 22, width: 4, height: 4))
        let bright = middle.filter { pixel(exported.bytes, $0.x, $0.y).prefix(3).contains { $0 > 96 } }
        #expect(bright.isEmpty, "\(bright.count) middle pixels look like the blurred secret")
    }

    @Test func pixelateRegionIsBlockUniformAndDiffersFromSource() async throws {
        model.blockPoints = 6
        let mosaic = try add(.pixelate, from: CGPoint(x: 12, y: 12), to: CGPoint(x: 48, y: 36))
        guard case .pixelate(let region, let block) = mosaic else {
            Issue.record("not a pixelate")
            return
        }
        // 6 pt at 2x. The grid is anchored to image pixel (0,0), so the region holds 3 x 2 whole blocks.
        #expect(block == 12)
        try #require(block >= 1)
        let side = Int(block)
        let exported = try await exportedPixels()

        let cells = Dictionary(grouping: positions(in: region.rect)) { [$0.x / side, $0.y / side] }
        #expect(cells.count == 6)
        for (cell, members) in cells {
            let values = Set(members.map { pixel(exported.bytes, $0.x, $0.y) })
            #expect(values.count == 1, "block \(cell) holds \(values.count) values")
            #expect(members.contains { pixel(exported.bytes, $0.x, $0.y) != pixel(source, $0.x, $0.y) },
                    "block \(cell) equals the source")
        }
    }

    @Test func blurRegionDiffersFromSource() async throws {
        let blur = try add(.blur, from: CGPoint(x: 8, y: 8), to: CGPoint(x: 40, y: 32))
        let exported = try await exportedPixels()
        let inside = positions(in: try rect(of: blur))
        let kept = inside.filter { pixel(exported.bytes, $0.x, $0.y) == pixel(source, $0.x, $0.y) }
        #expect(kept.count * 100 <= inside.count, "\(kept.count) of \(inside.count) pixels kept their source value")
    }

    @Test func outsideEffectsEqualBaseAndScaleIsTwo() async throws {
        model.blockPoints = 6
        let effects = try [
            add(.redact, from: CGPoint(x: 2, y: 2), to: CGPoint(x: 14, y: 12)),
            add(.blur, from: CGPoint(x: 20, y: 4), to: CGPoint(x: 36, y: 20)),
            add(.pixelate, from: CGPoint(x: 36, y: 24), to: CGPoint(x: 60, y: 48)),
        ]
        let rects = try effects.map { try rect(of: $0) }
        let exported = try await exportedPixels()
        #expect(exported.scale == 2)
        #expect(exported.width == Self.width)
        #expect(exported.height == Self.height)

        let outside = positions(in: CGRect(x: 0, y: 0, width: Self.width, height: Self.height)).filter { position in
            let centre = CGPoint(x: CGFloat(position.x) + 0.5, y: CGFloat(position.y) + 0.5)
            return !rects.contains { $0.contains(centre) }
        }
        #expect(outside.count > Self.width * Self.height / 2)
        let changed = outside.filter { pixel(exported.bytes, $0.x, $0.y) != pixel(source, $0.x, $0.y) }
        #expect(changed.isEmpty, "\(changed.count) pixels outside every effect changed")
    }
}
```

- [ ] **Step 3: Run the tests to verify they fail**

Run:
```bash
xcodegen generate && xcodebuild test -project TidyShot.xcodeproj -scheme TidyShot -destination 'platform=macOS' -derivedDataPath .build 2>&1 | grep -E "error:" | sort -u | head -3
```
Expected: compile errors, among them `cannot find 'EditorModel' in scope`.

- [ ] **Step 4: Write the tool protocols**

`TidyShot/Editor/Tools/CanvasTool.swift`:
```swift
import AppKit

/// One pointer event for a tool: the point in image pixels (top-left origin) and the modifiers
/// that change a shape. `flagsChanged` repeats the last point with the new modifiers.
nonisolated struct ToolInput: Equatable, Sendable {
    var point: CGPoint
    var shift = false
    var option = false
    var clickCount = 1
}

/// What a tool may read and change. `EditorModel` adopts it; CanvasToolTests fake it.
///
/// - `commit` is the only write. A tool calls it once per completed gesture, on mouseUp, while
///   `transient` still holds the shape. A commit whose document contains the transient's id
///   clears `transient` itself, so an effect's tile carries over instead of rendering again.
/// - `makeAnnotation` builds the shape for a drag between two image points with the current
///   colours and sizes. It reuses the transient's id, so one drag keeps one id, and returns nil
///   for Select, an empty rect and a zero-length arrow.
/// - A nil `transient` at mouseUp means Escape abandoned the drag; the tool commits nothing.
protocol CanvasEditing: AnyObject {
    var document: AnnotationDocument { get }
    /// View points per image pixel.
    var zoom: CGFloat { get }
    /// The capture's backing scale: image pixels per point.
    var scale: CGFloat { get }
    /// The shape in progress. Never undoable.
    var transient: Annotation? { get set }
    var selection: UUID? { get set }
    func commit(_ new: AnnotationDocument, actionName: String, coalescingKey: String?)
    func makeAnnotation(_ tool: EditorTool, from: CGPoint, to: CGPoint) -> Annotation?
}

/// Turns pointer events into a transient shape and one commit per gesture. `makeTool(for:)` in
/// ToolFactory.swift (Task 9) creates the tools.
protocol CanvasTool: AnyObject {
    var cursor: NSCursor { get }
    func mouseDown(_ input: ToolInput, on editing: any CanvasEditing)
    func mouseDragged(_ input: ToolInput, on editing: any CanvasEditing)
    func mouseUp(_ input: ToolInput, on editing: any CanvasEditing)
    /// Shift or Option changed without the mouse moving: re-apply them to the drag in progress.
    func flagsChanged(_ input: ToolInput, on editing: any CanvasEditing)
}
```

- [ ] **Step 5: Write the model**

`TidyShot/Editor/Session/EditorModel.swift`:
```swift
import CoreGraphics
import Foundation
import Observation

/// Which effect setting a slider in the options popover changes.
nonisolated enum EffectParameter: Sendable {
    case blurRadius
    case block
}

/// One editor's state: the capture, the annotation document and the one path that changes it.
///
/// `commit(_:actionName:coalescingKey:)` is the only write. Each call is one explicit undo group
/// whose handler puts the previous snapshot back; that restore registers the inverse, which gives
/// redo. A commit whose key equals the last commit's key changes the document without a new
/// registration, so an arrow-key or slider burst is one step. Selection, zoom, pan, tool and
/// colour choice never enter the undo stack.
@Observable
final class EditorModel: CanvasEditing {
    /// Undo menu names for the commits the model makes itself. Tools name their own.
    enum ActionName {
        static let delete = "Delete"
        static let move = "Move"
        static let color = "Color"
        static let lineWidth = "Line Width"
        static let blurRadius = "Blur Radius"
        static let block = "Block Size"
    }

    let recordID: UUID
    /// The capture. Never mutated, and not part of the document or of undo.
    let base: CGImage
    /// Image pixels per point.
    let scale: CGFloat

    private(set) var document = AnnotationDocument(annotations: [])
    /// The document as last saved; empty when the editor opens.
    private var savedDocument = AnnotationDocument(annotations: [])
    var hasUnsavedChanges: Bool { document != savedDocument }

    var selection: UUID? {
        didSet { if selection != oldValue { coalescingKey = nil } }
    }
    /// The shape being drawn. An effect here is reconciled as the last effect.
    var transient: Annotation? {
        didSet {
            guard !isApplying, transient != oldValue,
                  transient?.isEffect == true || oldValue?.isEffect == true else { return }
            tileCache.reconcile(document: document, transient: transient)
        }
    }
    /// Redaction is the reason the editor exists, so it opens with Redact.
    var tool: EditorTool = .redact {
        didSet { if tool != oldValue { transient = nil } }
    }
    var strokeColor: RGBA
    var redactColor: RGBA
    var lineWidthPoints: CGFloat
    var blurRadiusPoints: CGFloat
    var blockPoints: CGFloat
    var transform: CanvasTransform
    var zoom: CGFloat { transform.zoom }

    @ObservationIgnored let undoManager: UndoManager
    @ObservationIgnored let tileCache: RedactionTileCache
    /// The last commit's key. Cleared by any other commit, by undo, by redo and by a selection change.
    @ObservationIgnored private var coalescingKey: String?
    /// True while `apply` runs, so `transient`'s observer leaves the one reconcile to it.
    @ObservationIgnored private var isApplying = false

    init(recordID: UUID, image: ScaledImage, renderer: any TileRendering, defaults: EditorDefaults) {
        self.recordID = recordID
        base = image.image
        scale = image.scale
        strokeColor = defaults.strokeColor
        redactColor = defaults.redactColor
        lineWidthPoints = defaults.lineWidthPoints
        blurRadiusPoints = defaults.blurRadiusPoints
        blockPoints = defaults.blockPoints
        // Natural size until the window controller fits the image to its view.
        transform = CanvasTransform(zoom: 1 / image.scale, offset: .zero)
        let undoManager = UndoManager()
        undoManager.groupsByEvent = false
        self.undoManager = undoManager
        tileCache = RedactionTileCache(base: image.image, renderer: renderer)
    }

    // MARK: The write path

    func commit(_ new: AnnotationDocument, actionName: String, coalescingKey: String? = nil) {
        guard new != document else { return }
        if let coalescingKey, coalescingKey == self.coalescingKey {
            // Same burst: the step the first commit registered already restores what came before.
            apply(new)
            return
        }
        let previous = document
        undoManager.beginUndoGrouping()
        undoManager.registerUndo(withTarget: self) { model in
            model.restore(previous, actionName: actionName)
        }
        undoManager.setActionName(actionName)
        undoManager.endUndoGrouping()
        self.coalescingKey = coalescingKey
        apply(new)
    }

    /// Undo and redo land here. UndoManager has opened a group on the other stack, so the
    /// registration below becomes the redo (or the undo again).
    private func restore(_ snapshot: AnnotationDocument, actionName: String) {
        let current = document
        undoManager.registerUndo(withTarget: self) { model in
            model.restore(current, actionName: actionName)
        }
        undoManager.setActionName(actionName)
        coalescingKey = nil
        apply(snapshot)
    }

    private func apply(_ new: AnnotationDocument) {
        isApplying = true
        document = new
        // A shape the tool just committed is no longer in progress; its tile carries over.
        if let transient, new.annotation(id: transient.id) != nil { self.transient = nil }
        if let selection, new.annotation(id: selection) == nil { self.selection = nil }
        isApplying = false
        tileCache.reconcile(document: new, transient: transient)
    }

    // MARK: Shapes and the selection

    func makeAnnotation(_ tool: EditorTool, from start: CGPoint, to end: CGPoint) -> Annotation? {
        let id = transient?.id ?? UUID()
        let rect = CGRect(x: min(start.x, end.x), y: min(start.y, end.y),
                          width: abs(end.x - start.x), height: abs(end.y - start.y))
        // Exhaustive: every new tool must decide what it makes here.
        switch tool {
        case .select:
            return nil
        case .redact:
            guard !rect.isEmpty else { return nil }
            return .redact(Region(id: id, rect: rect), fill: redactColor)
        case .pixelate:
            guard !rect.isEmpty else { return nil }
            return .pixelate(Region(id: id, rect: rect),
                             block: RedactionDefaults.block(points: blockPoints, scale: scale, region: rect))
        case .blur:
            guard !rect.isEmpty else { return nil }
            return .blur(Region(id: id, rect: rect),
                         radius: RedactionDefaults.blurRadius(points: blurRadiusPoints, scale: scale))
        case .rectangle:
            guard !rect.isEmpty else { return nil }
            return .rectangle(ShapeBox(id: id, rect: rect, color: strokeColor, lineWidth: lineWidthPoints * scale))
        case .arrow:
            guard start != end else { return nil }
            return .arrow(Segment(id: id, from: start, to: end, color: strokeColor, lineWidth: lineWidthPoints * scale))
        }
    }

    private var selectedAnnotation: Annotation? {
        selection.flatMap { document.annotation(id: $0) }
    }

    func deleteSelection() {
        guard let selected = selectedAnnotation else { return }
        commit(document.removing(id: selected.id), actionName: ActionName.delete)
    }

    func nudgeSelection(by delta: CGVector) {
        guard let selected = selectedAnnotation else { return }
        commit(document.moving(id: selected.id, by: delta), actionName: ActionName.move,
               coalescingKey: "Nudge-\(selected.id.uuidString)")
    }

    /// Escape and ⌘.: abandon the shape being drawn, otherwise deselect. Never closes the window.
    func cancelCurrentOperation() {
        if transient != nil {
            transient = nil
        } else {
            selection = nil
        }
    }

    /// ⌘A with one selection: the frontmost annotation, drawings before effects as in HitTester.
    func selectAll() {
        selection = (document.drawings.last ?? document.effects.last)?.id
    }

    func markSaved() {
        savedDocument = document
    }

    // MARK: Palette and options

    /// The colour the toolbar circle shows: the selected annotation's, else the default
    /// `applyColor` would change.
    var activeColor: RGBA {
        Self.color(of: selectedAnnotation) ?? (editsRedactColor ? redactColor : strokeColor)
    }

    /// Redact, or Select with a redaction selected, edits the fill; everything else the stroke.
    private var editsRedactColor: Bool {
        if tool == .redact { return true }
        guard tool == .select, case .redact? = selectedAnnotation else { return false }
        return true
    }

    func applyColor(_ color: RGBA) {
        if editsRedactColor { redactColor = color } else { strokeColor = color }
        guard let selected = selectedAnnotation else { return }
        commit(document.replacing(selected.withColor(color)), actionName: ActionName.color,
               coalescingKey: "\(ActionName.color)-\(selected.id.uuidString)")
    }

    func applyLineWidth(points: CGFloat) {
        lineWidthPoints = points
        guard let selected = selectedAnnotation else { return }
        commit(document.replacing(selected.withLineWidth(points * scale)), actionName: ActionName.lineWidth,
               coalescingKey: "\(ActionName.lineWidth)-\(selected.id.uuidString)")
    }

    func applyEffectParameter(_ parameter: EffectParameter, points: CGFloat) {
        switch parameter {
        case .blurRadius: blurRadiusPoints = points
        case .block: blockPoints = points
        }
        guard let selected = selectedAnnotation else { return }
        let changed: Annotation
        let actionName: String
        switch (parameter, selected) {
        case (.blurRadius, .blur):
            changed = selected.withEffectParameter(RedactionDefaults.blurRadius(points: points, scale: scale))
            actionName = ActionName.blurRadius
        case (.block, .pixelate(let region, _)):
            changed = selected.withEffectParameter(RedactionDefaults.block(points: points, scale: scale, region: region.rect))
            actionName = ActionName.block
        default:
            return
        }
        commit(document.replacing(changed), actionName: actionName,
               coalescingKey: "\(actionName)-\(selected.id.uuidString)")
    }

    private static func color(of annotation: Annotation?) -> RGBA? {
        switch annotation {
        case .rectangle(let box)?: return box.color
        case .arrow(let segment)?: return segment.color
        case .redact(_, let fill)?: return fill
        default: return nil
        }
    }

    // MARK: Export

    /// The flattened image at the capture's scale. Tiles come from the same renderer as the
    /// preview, so export bytes equal preview bytes; the flatten runs off the main actor.
    func renderExport() async -> ScaledImage? {
        let document = self.document
        let tiles = await tileCache.allTiles(for: document)
        let imageSize = CGSize(width: base.width, height: base.height)
        for effect in document.effects where !tiles.contains(where: { $0.effect == effect }) {
            // An effect that covers image pixels but has no tile would export them unredacted.
            guard let rect = effect.effectRect, ImageRects.integral(rect, clippedTo: imageSize).isEmpty else { return nil }
        }
        let base = self.base
        let scale = self.scale
        let image = await Task.detached(priority: .userInitiated) {
            EditorFlattener.flatten(base: base, tiles: tiles, document: document, scale: scale)
        }.value
        return image.map { ScaledImage(image: $0, scale: scale) }
    }
}
```

Notes for the implementer:
- `restore` opens no group of its own: `undo()` and `redo()` wrap the handler in a group on the other stack. If `undoRestoresSnapshotAndRedoReapplies` shows the redo landing outside a group (an exception, or `canRedo` false), wrap the registration in `restore` in `beginUndoGrouping()` and `endUndoGrouping()`.
- `makeAnnotation`'s switch over `EditorTool` stays exhaustive with no `default`, so each 4b tool case fails to compile until it says what it makes.

- [ ] **Step 6: Run the suite to verify it passes**

Run:
```bash
xcodegen generate && xcodebuild test -project TidyShot.xcodeproj -scheme TidyShot -destination 'platform=macOS' -derivedDataPath .build 2>&1 | grep -E "Test run with|error:|TEST"
```
Expected: no `error:` lines, and `Test run with 304 tests in 44 suites passed`.

A failing `RedactionExportTests` case means a defect in `RedactionRenderer`, `RedactionTileCache` or `EditorFlattener` (Tasks 5 to 7). Fix it there, add that file to the commit below, and never loosen an assertion. Without a Metal device the renderer falls back to `CIContext(options:)`; every expectation is computed in the same run, so the tests hold either way.

This task has no UI and no hand checks. The canvas and window that drive the model come in Task 10.

- [ ] **Step 7: Commit**

```bash
git add TidyShot/Editor/Tools/CanvasTool.swift TidyShot/Editor/Session/EditorModel.swift TidyShotTests/EditorModelTests.swift TidyShotTests/RedactionExportTests.swift
git commit -m "feat: editor model with snapshot undo and an end-to-end redaction test"
```

### Task 9: Select, rectangle-drag and two-point tools, and the tool factory (TDD with a fake canvas)

**Files:**
- Create: `TidyShot/Editor/Tools/ToolFactory.swift`
- Create: `TidyShot/Editor/Tools/RectDragTool.swift`
- Create: `TidyShot/Editor/Tools/TwoPointTool.swift`
- Create: `TidyShot/Editor/Tools/SelectTool.swift`
- Test: `TidyShotTests/CanvasToolTests.swift` (create; it also holds `FakeCanvasEditing`)

No existing file changes. Everything this task consumes comes from Tasks 2, 4 and 8.

**Interfaces:**
- Consumes:
  - Task 8 (`TidyShot/Editor/Tools/CanvasTool.swift`, `TidyShot/Editor/Session/EditorModel.swift`):
    - `struct ToolInput { var point: CGPoint; var shift: Bool; var option: Bool; var clickCount: Int }`, in image pixels, top-left origin.
    - `protocol CanvasEditing: AnyObject { var document: AnnotationDocument { get }; var zoom: CGFloat { get }; var scale: CGFloat { get }; var transient: Annotation? { get set }; var selection: UUID? { get set }; func commit(_ new: AnnotationDocument, actionName: String, coalescingKey: String?); func makeAnnotation(_ tool: EditorTool, from: CGPoint, to: CGPoint) -> Annotation? }`. Tools rely on `makeAnnotation` building the value with the model's current colour, line width and effect parameter from the rect that `from` and `to` span (tail and head for an arrow), reusing `transient?.id` when a transient exists (so one drag keeps one id; the fake below mints a new id on each call, which the tests tolerate), and returning nil for `.select`.
    - `protocol CanvasTool: AnyObject { var cursor: NSCursor { get }; func mouseDown(_ input: ToolInput, on canvas: any CanvasEditing); func mouseDragged(_ input: ToolInput, on canvas: any CanvasEditing); func mouseUp(_ input: ToolInput, on canvas: any CanvasEditing); func flagsChanged(_ input: ToolInput, on canvas: any CanvasEditing) }`.
  - Task 4 (`TidyShot/Editor/Geometry/DragGeometry.swift`, `HitTester.swift`):
    - `DragGeometry.rect(from: CGPoint, to: CGPoint, square: Bool, fromCentre: Bool) -> CGRect` (a standardized rect), `segmentEnd(from: CGPoint, to: CGPoint, snap45: Bool) -> CGPoint`, `axisLocked(_ delta: CGVector) -> CGVector`, `isLargeEnough(_ rect: CGRect, zoom: CGFloat) -> Bool` (the 2/zoom px rule), `isLongEnough(from: CGPoint, to: CGPoint, zoom: CGFloat) -> Bool` (the same rule for a length).
    - `HitTester.Hit` (`.body`, `.handle(Int)`), `tolerance(zoom: CGFloat) -> CGFloat` (8 view points in image pixels), `handles(for: Annotation) -> [CGPoint]`, `hit(_: Annotation, at: CGPoint, tolerance: CGFloat) -> Hit?`, `topmost(in: AnnotationDocument, at: CGPoint, tolerance: CGFloat) -> (id: UUID, hit: Hit)?`, `resized(_: Annotation, handle: Int, to: CGPoint, square: Bool) -> Annotation`.
  - Task 2 (`TidyShot/Editor/Model/`): `Annotation` (`id`, `title`, `isEffect`, `moved(by: CGVector)`), `ShapeBox(id:rect:color:lineWidth:)`, `Segment(id:from:to:color:lineWidth:)`, `Region(id:rect:)`, `AnnotationDocument(annotations:)` with `annotation(id:)`, `appending(_:)` and `replacing(_:)`, `EditorTool` (`select, redact, pixelate, blur, rectangle, arrow`), `EditorPalette.defaultStroke` and `EditorPalette.defaultRedact`.
- Produces:
  - `final class SelectTool: CanvasTool { init() }`. Cursor `.arrow`.
  - `final class RectDragTool: CanvasTool { let tool: EditorTool; init(tool: EditorTool) }` for redact, pixelate, blur and rectangle (4b adds ellipse). Cursor `.crosshair`.
  - `final class TwoPointTool: CanvasTool { let tool: EditorTool; init(tool: EditorTool) }` for arrow (4b adds line). Cursor `.crosshair`.
  - `func makeTool(for tool: EditorTool) -> any CanvasTool` in ToolFactory.swift: an exhaustive switch with no default, so every later `EditorTool` case fails to compile until it is wired.
  - `extension CanvasEditing { func commitNewShape(_ shape: Annotation) }` in ToolFactory.swift, for 4b's pencil and text tools too.
  - Undo action names: `Add <title>`, `Move <title>`, `Resize <title>`, from `Annotation.title`. No coalescing key: one gesture is one undo step.
  - The transient contract, which Task 6 (`RedactionTileCache.reconcile`) and Task 10 (`CanvasView.draw`) must honour. A Select gesture puts a changed copy in `transient` with the id of a document annotation. That copy stands in for the annotation and keeps its creation-order place: the document entry with the same id is replaced by the transient in `RedactionTileCache.orderedEffects(in:transient:)` (Task 6) and in Task 10's displayed lists, so a moved or resized annotation neither jumps in front of later ones nor flips back on commit. Only a new shape, whose id is not in the document, comes last. Spec 2.6 says "reconciled as the last effect" for the dragged effect; that holds for a new shape, and the controller is asked to amend the spec to match (a moved or resized effect keeps its place). Tools commit while the transient still holds the committed value and clear it afterwards. The tile cache therefore sees one key throughout, and the live tile carries over on commit.
  - Test helper `final class FakeCanvasEditing: CanvasEditing` (CanvasToolTests.swift), with `commits: [Commit]` (document, actionName, coalescingKey, and the transient at commit time) and `made` (each `makeAnnotation` call).

Rules every tool follows (spec 2.6, Tools):
- Exactly one commit per completed gesture, on mouseUp. Nothing is committed on mouseDown, mouseDragged or flagsChanged.
- The shape in progress lives only in `canvas.transient`.
- Drags below the 2/zoom px rule leave nothing. Rects use `DragGeometry.isLargeEnough`. Arrows and moves use the distance travelled through `DragGeometry.isLongEnough(from:to:zoom:)`, because a level drag has no height. This differs from spec 2.6's wording ("shorter than 2/zoom px in either dimension") on purpose; Task 17 Step 4 amends the spec to: rect tools need both sides at least 2/zoom px, arrows and moves need a length of at least 2/zoom px.
- `flagsChanged` re-reads Shift and Option with the last drag point, so a modifier pressed mid-drag applies without a mouse move. `input.point` is not used there.
- When a tool finds `canvas.transient` is not what it last set, the gesture was cancelled (Escape runs `cancelCurrentOperation()`), and the tool drops it.
- Delete, arrow-key nudges, Escape and ⌘A go from CanvasView to EditorModel (Tasks 8 and 10), not through the tools.

- [ ] **Step 1: Write the failing tests**

`TidyShotTests/CanvasToolTests.swift`:
```swift
import AppKit
import Testing
@testable import TidyShot

/// Stands in for EditorModel. It records commits and builds annotations the way the model does,
/// with fixed colours, widths and effect parameters.
final class FakeCanvasEditing: CanvasEditing {
    struct Commit {
        let document: AnnotationDocument
        let actionName: String
        let coalescingKey: String?
        /// The transient when the commit ran. Tools commit before they clear it.
        let transient: Annotation?
    }

    private(set) var document: AnnotationDocument
    var zoom: CGFloat = 1
    var scale: CGFloat = 2
    var transient: Annotation?
    var selection: UUID?
    private(set) var commits: [Commit] = []
    private(set) var made: [(tool: EditorTool, from: CGPoint, to: CGPoint)] = []

    init(_ annotations: [Annotation] = []) {
        document = AnnotationDocument(annotations: annotations)
    }

    func commit(_ new: AnnotationDocument, actionName: String, coalescingKey: String?) {
        commits.append(Commit(document: new, actionName: actionName, coalescingKey: coalescingKey, transient: transient))
        document = new
    }

    func makeAnnotation(_ tool: EditorTool, from: CGPoint, to: CGPoint) -> Annotation? {
        made.append((tool: tool, from: from, to: to))
        let rect = CGRect(x: min(from.x, to.x), y: min(from.y, to.y),
                          width: abs(to.x - from.x), height: abs(to.y - from.y))
        switch tool {
        case .redact: return .redact(Region(id: UUID(), rect: rect), fill: EditorPalette.defaultRedact)
        case .pixelate: return .pixelate(Region(id: UUID(), rect: rect), block: 20)
        case .blur: return .blur(Region(id: UUID(), rect: rect), radius: 16)
        case .rectangle:
            return .rectangle(ShapeBox(id: UUID(), rect: rect, color: EditorPalette.defaultStroke, lineWidth: 8))
        case .arrow:
            return .arrow(Segment(id: UUID(), from: from, to: to, color: EditorPalette.defaultStroke, lineWidth: 8))
        default: return nil
        }
    }
}

@MainActor
struct CanvasToolTests {
    let red = EditorPalette.defaultStroke

    func at(_ x: CGFloat, _ y: CGFloat, shift: Bool = false, option: Bool = false) -> ToolInput {
        ToolInput(point: CGPoint(x: x, y: y), shift: shift, option: option, clickCount: 1)
    }

    func rect(of annotation: Annotation?) -> CGRect? {
        switch annotation {
        case .rectangle(let box)?: box.rect
        case .redact(let region, _)?, .pixelate(let region, _)?, .blur(let region, _)?: region.rect
        default: nil
        }
    }

    func segment(of annotation: Annotation?) -> Segment? {
        if case .arrow(let segment)? = annotation { return segment }
        return nil
    }

    func arrow(_ from: CGPoint, _ to: CGPoint) -> Annotation {
        .arrow(Segment(id: UUID(), from: from, to: to, color: red, lineWidth: 8))
    }

    @Test func transientUpdatesDuringDrag() throws {
        let canvas = FakeCanvasEditing()
        let tool = makeTool(for: .redact)
        #expect(tool is RectDragTool)

        tool.mouseDown(at(10, 10), on: canvas)
        #expect(canvas.transient == nil)
        tool.mouseDragged(at(50, 40), on: canvas)
        #expect(rect(of: canvas.transient) == CGRect(x: 10, y: 10, width: 40, height: 30))
        #expect(canvas.transient?.isEffect == true)
        #expect(canvas.made.last?.tool == .redact)
        #expect(canvas.made.last?.from == CGPoint(x: 10, y: 10))
        #expect(canvas.made.last?.to == CGPoint(x: 50, y: 40))

        tool.mouseDragged(at(60, 70), on: canvas)
        #expect(rect(of: canvas.transient) == CGRect(x: 10, y: 10, width: 50, height: 60))

        // An event that gives the same rect keeps the same annotation, id included.
        let shown = try #require(canvas.transient)
        let calls = canvas.made.count
        tool.flagsChanged(at(60, 70), on: canvas)
        #expect(canvas.made.count == calls)
        #expect(canvas.transient == shown)

        // Dragging back past the press point passes the standardized corners.
        tool.mouseDragged(at(0, 5), on: canvas)
        #expect(rect(of: canvas.transient) == CGRect(x: 0, y: 5, width: 10, height: 5))
        #expect(canvas.made.last?.from == CGPoint(x: 0, y: 5))
        #expect(canvas.made.last?.to == CGPoint(x: 10, y: 10))

        #expect(canvas.commits.isEmpty)
        #expect(canvas.document.annotations.isEmpty)
    }

    @Test func commitOnMouseUpOnly() throws {
        let canvas = FakeCanvasEditing()
        let tool = makeTool(for: .rectangle)
        tool.mouseDown(at(10, 10), on: canvas)
        tool.mouseDragged(at(40, 30), on: canvas)
        tool.mouseDragged(at(60, 50), on: canvas)
        let shape = try #require(canvas.transient)
        #expect(canvas.commits.isEmpty)

        tool.mouseUp(at(60, 50), on: canvas)
        #expect(canvas.commits.count == 1)
        let commit = try #require(canvas.commits.first)
        #expect(commit.document == AnnotationDocument(annotations: [shape]))
        #expect(commit.actionName == "Add \(shape.title)")
        #expect(commit.coalescingKey == nil)
        #expect(commit.transient == shape)
        #expect(canvas.transient == nil)

        // A gesture cancelled mid-drag (Escape clears the transient) is not completed: no commit.
        tool.mouseDown(at(100, 100), on: canvas)
        tool.mouseDragged(at(140, 130), on: canvas)
        canvas.transient = nil
        tool.mouseDragged(at(150, 140), on: canvas)
        #expect(canvas.transient == nil)
        tool.mouseUp(at(150, 140), on: canvas)
        #expect(canvas.commits.count == 1)
    }

    @Test func tinyDragDiscarded() {
        let canvas = FakeCanvasEditing()
        let rectangle = makeTool(for: .rectangle)
        // At 100 % the rule is 2 px, so a 1 px wide drag leaves nothing.
        rectangle.mouseDown(at(10, 10), on: canvas)
        rectangle.mouseDragged(at(11, 40), on: canvas)
        #expect(canvas.transient == nil)
        rectangle.mouseUp(at(11, 40), on: canvas)
        #expect(canvas.commits.isEmpty)
        #expect(canvas.selection == nil)

        let arrowTool = makeTool(for: .arrow)
        arrowTool.mouseDown(at(10, 10), on: canvas)
        arrowTool.mouseDragged(at(11, 10.5), on: canvas)
        #expect(canvas.transient == nil)
        arrowTool.mouseUp(at(11, 10.5), on: canvas)
        #expect(canvas.commits.isEmpty)

        // A level arrow has no height and is still kept.
        arrowTool.mouseDown(at(10, 10), on: canvas)
        arrowTool.mouseDragged(at(60, 10), on: canvas)
        arrowTool.mouseUp(at(60, 10), on: canvas)
        #expect(canvas.commits.count == 1)

        // At 400 % the rule is 0.5 px, so the same 1 px drag is kept.
        canvas.zoom = 4
        rectangle.mouseDown(at(10, 10), on: canvas)
        rectangle.mouseDragged(at(11, 40), on: canvas)
        rectangle.mouseUp(at(11, 40), on: canvas)
        #expect(canvas.commits.count == 2)
    }

    @Test func shiftViaFlagsChangedSquares() throws {
        let canvas = FakeCanvasEditing()
        let tool = makeTool(for: .rectangle)
        tool.mouseDown(at(10, 10), on: canvas)
        tool.mouseDragged(at(50, 30), on: canvas)
        #expect(rect(of: canvas.transient) == CGRect(x: 10, y: 10, width: 40, height: 20))

        // Shift goes down with the mouse still: the shape squares without a drag event.
        tool.flagsChanged(at(50, 30, shift: true), on: canvas)
        let square = try #require(rect(of: canvas.transient))
        #expect(square == DragGeometry.rect(from: CGPoint(x: 10, y: 10), to: CGPoint(x: 50, y: 30),
                                            square: true, fromCentre: false))
        #expect(square.width == square.height)
        #expect(square.origin == CGPoint(x: 10, y: 10))

        tool.flagsChanged(at(50, 30), on: canvas)
        #expect(rect(of: canvas.transient) == CGRect(x: 10, y: 10, width: 40, height: 20))

        tool.flagsChanged(at(50, 30, shift: true), on: canvas)
        #expect(canvas.commits.isEmpty)
        tool.mouseUp(at(50, 30, shift: true), on: canvas)
        #expect(canvas.commits.count == 1)
        #expect(rect(of: canvas.document.annotations.last) == square)
    }

    @Test func optionDrawsFromCentre() {
        let canvas = FakeCanvasEditing()
        let tool = makeTool(for: .blur)
        tool.mouseDown(at(50, 50), on: canvas)
        tool.mouseDragged(at(70, 60), on: canvas)
        #expect(rect(of: canvas.transient) == CGRect(x: 50, y: 50, width: 20, height: 10))

        // The press point becomes the centre.
        tool.flagsChanged(at(70, 60, option: true), on: canvas)
        #expect(rect(of: canvas.transient) == CGRect(x: 30, y: 40, width: 40, height: 20))

        tool.mouseUp(at(70, 60, option: true), on: canvas)
        #expect(canvas.commits.count == 1)
        #expect(rect(of: canvas.document.annotations.last) == CGRect(x: 30, y: 40, width: 40, height: 20))
    }

    @Test func arrowShiftSnaps45() throws {
        let canvas = FakeCanvasEditing()
        let tool = makeTool(for: .arrow)
        #expect(tool is TwoPointTool)
        let tail = CGPoint(x: 10, y: 10)
        let pointer = CGPoint(x: 110, y: 100)

        tool.mouseDown(at(10, 10), on: canvas)
        tool.mouseDragged(at(110, 100), on: canvas)
        #expect(segment(of: canvas.transient)?.from == tail)
        #expect(segment(of: canvas.transient)?.to == pointer)

        tool.flagsChanged(at(110, 100, shift: true), on: canvas)
        let snapped = DragGeometry.segmentEnd(from: tail, to: pointer, snap45: true)
        #expect(segment(of: canvas.transient)?.to == snapped)
        #expect(snapped.x > tail.x && snapped.y > tail.y)
        #expect(abs(abs(snapped.x - tail.x) - abs(snapped.y - tail.y)) < 0.001)

        tool.mouseUp(at(110, 100, shift: true), on: canvas)
        #expect(canvas.commits.count == 1)
        let committed = try #require(segment(of: canvas.document.annotations.last))
        #expect(committed.from == tail)
        #expect(committed.to == snapped)
        #expect(canvas.made.last?.tool == .arrow)
    }

    @Test func newShapeSelected() throws {
        let existing = arrow(CGPoint(x: 0, y: 0), CGPoint(x: 30, y: 0))
        let canvas = FakeCanvasEditing([existing])
        canvas.selection = existing.id

        let pixelate = makeTool(for: .pixelate)
        pixelate.mouseDown(at(10, 10), on: canvas)
        pixelate.mouseDragged(at(80, 60), on: canvas)
        pixelate.mouseUp(at(80, 60), on: canvas)
        let region = try #require(canvas.document.annotations.last)
        #expect(region.isEffect)
        #expect(canvas.selection == region.id)

        let arrowTool = makeTool(for: .arrow)
        arrowTool.mouseDown(at(100, 100), on: canvas)
        arrowTool.mouseDragged(at(160, 120), on: canvas)
        arrowTool.mouseUp(at(160, 120), on: canvas)
        let drawn = try #require(canvas.document.annotations.last)
        #expect(segment(of: drawn) != nil)
        #expect(canvas.selection == drawn.id)
        #expect(canvas.document.annotations.count == 3)
        #expect(canvas.commits.count == 2)
    }

    @Test func selectPicksTopmost() {
        let blur = Annotation.blur(Region(id: UUID(), rect: CGRect(x: 0, y: 0, width: 200, height: 200)), radius: 16)
        let level = arrow(CGPoint(x: 20, y: 100), CGPoint(x: 180, y: 100))
        let upright = arrow(CGPoint(x: 100, y: 20), CGPoint(x: 100, y: 180))
        let canvas = FakeCanvasEditing([blur, level, upright])
        let tool = makeTool(for: .select)
        #expect(tool is SelectTool)

        func click(_ x: CGFloat, _ y: CGFloat) {
            tool.mouseDown(at(x, y), on: canvas)
            tool.mouseUp(at(x, y), on: canvas)
        }
        click(100, 100)  // both arrows cross here; the later one is in front
        #expect(canvas.selection == upright.id)
        click(60, 100)
        #expect(canvas.selection == level.id)
        click(40, 40)  // away from both drawings, the blur beneath them is picked
        #expect(canvas.selection == blur.id)
        #expect(canvas.commits.isEmpty)
        #expect(canvas.transient == nil)
    }

    @Test func moveCommitsOnceWithDelta() throws {
        let original = arrow(CGPoint(x: 20, y: 100), CGPoint(x: 180, y: 100))
        let canvas = FakeCanvasEditing([original])
        let tool = makeTool(for: .select)

        tool.mouseDown(at(100, 100), on: canvas)
        #expect(canvas.selection == original.id)
        tool.mouseDragged(at(110, 105), on: canvas)
        #expect(canvas.transient == original.moved(by: CGVector(dx: 10, dy: 5)))
        tool.mouseDragged(at(130, 120), on: canvas)
        #expect(canvas.transient?.id == original.id)
        #expect(canvas.commits.isEmpty)
        #expect(canvas.document.annotations == [original])

        tool.mouseUp(at(130, 120), on: canvas)
        #expect(canvas.commits.count == 1)
        let commit = try #require(canvas.commits.first)
        let moved = try #require(segment(of: commit.document.annotation(id: original.id)))
        #expect(moved.from == CGPoint(x: 50, y: 120))
        #expect(moved.to == CGPoint(x: 210, y: 120))
        #expect(commit.document.annotations.count == 1)
        #expect(commit.actionName == "Move \(original.title)")
        #expect(commit.coalescingKey == nil)
        #expect(canvas.transient == nil)
        #expect(canvas.selection == original.id)
    }

    @Test func shiftLocksMoveAxis() throws {
        let original = arrow(CGPoint(x: 20, y: 100), CGPoint(x: 180, y: 100))
        let canvas = FakeCanvasEditing([original])
        let tool = makeTool(for: .select)

        tool.mouseDown(at(100, 100), on: canvas)
        tool.mouseDragged(at(130, 110), on: canvas)
        #expect(segment(of: canvas.transient)?.from == CGPoint(x: 50, y: 110))

        // Shift mid-drag keeps the dominant horizontal travel and drops the vertical.
        tool.flagsChanged(at(130, 110, shift: true), on: canvas)
        #expect(segment(of: canvas.transient)?.from == CGPoint(x: 50, y: 100))

        tool.mouseUp(at(130, 110, shift: true), on: canvas)
        #expect(canvas.commits.count == 1)
        let moved = try #require(segment(of: canvas.document.annotation(id: original.id)))
        #expect(moved.from == CGPoint(x: 50, y: 100))
        #expect(moved.to == CGPoint(x: 210, y: 100))
    }

    @Test func handleDragResizes() throws {
        let box = Annotation.rectangle(ShapeBox(id: UUID(), rect: CGRect(x: 20, y: 20, width: 100, height: 80),
                                                color: red, lineWidth: 8))
        let canvas = FakeCanvasEditing([box])
        canvas.selection = box.id
        let handle = try #require(HitTester.handles(for: box).firstIndex(of: CGPoint(x: 120, y: 100)))
        let tool = makeTool(for: .select)

        tool.mouseDown(at(120, 100), on: canvas)
        tool.mouseDragged(at(170, 130), on: canvas)
        #expect(canvas.transient == HitTester.resized(box, handle: handle, to: CGPoint(x: 170, y: 130), square: false))
        #expect(canvas.commits.isEmpty)

        tool.mouseUp(at(170, 130), on: canvas)
        #expect(canvas.commits.count == 1)
        let commit = try #require(canvas.commits.first)
        #expect(rect(of: commit.document.annotation(id: box.id)) == CGRect(x: 20, y: 20, width: 150, height: 110))
        #expect(commit.actionName == "Resize \(box.title)")
        #expect(canvas.selection == box.id)
        #expect(canvas.transient == nil)
    }

    @Test func clickEmptyDeselects() {
        let original = arrow(CGPoint(x: 20, y: 100), CGPoint(x: 180, y: 100))
        let canvas = FakeCanvasEditing([original])
        canvas.selection = original.id
        let tool = makeTool(for: .select)

        tool.mouseDown(at(100, 300), on: canvas)
        #expect(canvas.selection == nil)
        tool.mouseDragged(at(150, 350), on: canvas)
        tool.mouseUp(at(150, 350), on: canvas)
        #expect(canvas.transient == nil)
        #expect(canvas.commits.isEmpty)
        #expect(canvas.document.annotations == [original])
    }
}
```

The fake's `makeAnnotation` ends in `default: return nil`, which covers `.select` now and the 4b cases later, so 4b needs no edit here.

- [ ] **Step 2: Run the tests to verify they fail**

Run:
```bash
xcodegen generate && xcodebuild test -project TidyShot.xcodeproj -scheme TidyShot -destination 'platform=macOS' -derivedDataPath .build 2>&1 | grep -E "error:" | sort -u | head -3
```
Expected: compile errors, among them `cannot find 'makeTool' in scope`.

- [ ] **Step 3: Write the factory and the shared helpers**

`TidyShot/Editor/Tools/ToolFactory.swift`:
```swift
import Foundation

/// The tool object behind each `EditorTool`. The switch is exhaustive with no default, so a new
/// case does not compile until it is wired here. 4b adds `RectDragTool(tool: .ellipse)` and
/// `TwoPointTool(tool: .line)`.
func makeTool(for tool: EditorTool) -> any CanvasTool {
    switch tool {
    case .select: return SelectTool()
    case .redact, .pixelate, .blur, .rectangle: return RectDragTool(tool: tool)
    case .arrow: return TwoPointTool(tool: tool)
    }
}

extension CanvasEditing {
    /// Ends a creation gesture with one commit named `Add <title>`, then clears the transient and
    /// selects the new shape. The commit runs while the transient still holds the same value, so the
    /// tile cache sees one key throughout and the live tile carries over (spec 2.6, Tiles).
    func commitNewShape(_ shape: Annotation) {
        commit(document.appending(shape), actionName: "Add \(shape.title)", coalescingKey: nil)
        transient = nil
        selection = shape.id
    }
}
```

- [ ] **Step 4: Write the rectangle-drag tool**

`TidyShot/Editor/Tools/RectDragTool.swift`:
```swift
import AppKit

/// Drags out a rect for Redact, Pixelate, Blur and Rectangle (4b adds Ellipse). Shift squares the
/// rect, and Option grows it from the press point as the centre. Both are read from every event,
/// flagsChanged included. The shape lives in `canvas.transient` until mouseUp commits it once and
/// selects it. A rect that fails `DragGeometry.isLargeEnough` at the current zoom leaves nothing.
final class RectDragTool: CanvasTool {
    let tool: EditorTool
    /// The press point in image pixels; nil when no gesture runs.
    private var start: CGPoint?
    /// The latest pointer position. flagsChanged reuses it, because the pointer has not moved.
    private var current = CGPoint.zero
    /// The rect behind `shown`. An event that gives the same rect keeps the same annotation, id
    /// included, so its tile is not rendered again.
    private var shownRect: CGRect?
    /// What this tool last put in `canvas.transient`. Anything else there means the gesture was
    /// cancelled, and the tool drops it.
    private var shown: Annotation?

    init(tool: EditorTool) {
        self.tool = tool
    }

    var cursor: NSCursor { .crosshair }

    func mouseDown(_ input: ToolInput, on canvas: any CanvasEditing) {
        start = input.point
        current = input.point
        shownRect = nil
        shown = nil
        canvas.transient = nil
    }

    func mouseDragged(_ input: ToolInput, on canvas: any CanvasEditing) {
        current = input.point
        update(input, on: canvas)
    }

    func flagsChanged(_ input: ToolInput, on canvas: any CanvasEditing) {
        update(input, on: canvas)
    }

    func mouseUp(_ input: ToolInput, on canvas: any CanvasEditing) {
        current = input.point
        update(input, on: canvas)
        let shape = start == nil ? nil : shown
        start = nil
        shownRect = nil
        shown = nil
        if let shape {
            canvas.commitNewShape(shape)
        }
    }

    private func update(_ input: ToolInput, on canvas: any CanvasEditing) {
        guard let start else { return }
        guard canvas.transient == shown else {
            self.start = nil
            shownRect = nil
            shown = nil
            return
        }
        let rect = DragGeometry.rect(from: start, to: current, square: input.shift, fromCentre: input.option)
        guard rect != shownRect else { return }
        shownRect = rect
        shown = DragGeometry.isLargeEnough(rect, zoom: canvas.zoom)
            ? canvas.makeAnnotation(tool, from: rect.origin, to: CGPoint(x: rect.maxX, y: rect.maxY))
            : nil
        canvas.transient = shown
    }
}
```

The model's `makeAnnotation` runs again whenever the rect changes. That is how Pixelate's default block (`RedactionDefaults.block(points:scale:region:)`, capped at the region's shorter side) follows the region during the drag.

- [ ] **Step 5: Write the two-point tool**

`TidyShot/Editor/Tools/TwoPointTool.swift`:
```swift
import AppKit

/// Arrow (4b adds Line): the tail at the press, the head at the pointer. Shift snaps the head to the
/// nearest 45 degrees, including through flagsChanged. Option has no effect in 4a. A segment
/// shorter than the tiny-drag rule leaves nothing.
final class TwoPointTool: CanvasTool {
    let tool: EditorTool
    /// The tail in image pixels; nil when no gesture runs.
    private var start: CGPoint?
    /// The latest pointer position. flagsChanged reuses it.
    private var current = CGPoint.zero
    /// The head behind `shown`, so an unchanged head keeps the same annotation and id.
    private var shownEnd: CGPoint?
    /// What this tool last put in `canvas.transient`. Anything else there means the gesture was
    /// cancelled.
    private var shown: Annotation?

    init(tool: EditorTool) {
        self.tool = tool
    }

    var cursor: NSCursor { .crosshair }

    func mouseDown(_ input: ToolInput, on canvas: any CanvasEditing) {
        start = input.point
        current = input.point
        shownEnd = nil
        shown = nil
        canvas.transient = nil
    }

    func mouseDragged(_ input: ToolInput, on canvas: any CanvasEditing) {
        current = input.point
        update(input, on: canvas)
    }

    func flagsChanged(_ input: ToolInput, on canvas: any CanvasEditing) {
        update(input, on: canvas)
    }

    func mouseUp(_ input: ToolInput, on canvas: any CanvasEditing) {
        current = input.point
        update(input, on: canvas)
        let shape = start == nil ? nil : shown
        start = nil
        shownEnd = nil
        shown = nil
        if let shape {
            canvas.commitNewShape(shape)
        }
    }

    private func update(_ input: ToolInput, on canvas: any CanvasEditing) {
        guard let start else { return }
        guard canvas.transient == shown else {
            self.start = nil
            shownEnd = nil
            shown = nil
            return
        }
        let end = DragGeometry.segmentEnd(from: start, to: current, snap45: input.shift)
        guard end != shownEnd else { return }
        shownEnd = end
        shown = DragGeometry.isLongEnough(from: start, to: end, zoom: canvas.zoom)
            ? canvas.makeAnnotation(tool, from: start, to: end)
            : nil
        canvas.transient = shown
    }
}
```

- [ ] **Step 6: Write the select tool**

`TidyShot/Editor/Tools/SelectTool.swift`:
```swift
import AppKit

/// Select (V). A press first tests the selected annotation's handles, because only the selection
/// shows handles. Otherwise `HitTester.topmost` picks the front-most drawing, then the front-most
/// effect, and that annotation becomes the selection. A hit on another annotation's handle selects
/// and moves it. A press on empty space deselects. A drag moves the selection (Shift keeps the
/// dominant axis) or resizes it by the pressed handle (Shift squares a box). The changed copy lives
/// in `canvas.transient`, with the annotation's own id, until mouseUp commits it once.
final class SelectTool: CanvasTool {
    private enum Gesture {
        case move(original: Annotation)
        /// `from` is where the handle sat at the press, so the handle keeps the grab offset.
        case resize(original: Annotation, handle: Int, from: CGPoint)

        var original: Annotation {
            switch self {
            case .move(let original), .resize(let original, _, _): original
            }
        }

        var verb: String {
            switch self {
            case .move: "Move"
            case .resize: "Resize"
            }
        }
    }

    private var gesture: Gesture?
    private var start = CGPoint.zero
    private var current = CGPoint.zero
    /// What this tool last put in `canvas.transient`. It stays nil until the pointer passes the
    /// tiny-drag rule, so a click changes nothing.
    private var shown: Annotation?

    var cursor: NSCursor { .arrow }

    func mouseDown(_ input: ToolInput, on canvas: any CanvasEditing) {
        gesture = nil
        shown = nil
        start = input.point
        current = input.point
        canvas.transient = nil
        let tolerance = HitTester.tolerance(zoom: canvas.zoom)
        if let id = canvas.selection, let selected = canvas.document.annotation(id: id),
           case .handle(let index)? = HitTester.hit(selected, at: input.point, tolerance: tolerance) {
            gesture = .resize(original: selected, handle: index, from: HitTester.handles(for: selected)[index])
            return
        }
        guard let top = HitTester.topmost(in: canvas.document, at: input.point, tolerance: tolerance),
              let annotation = canvas.document.annotation(id: top.id) else {
            canvas.selection = nil
            return
        }
        canvas.selection = annotation.id
        gesture = .move(original: annotation)
    }

    func mouseDragged(_ input: ToolInput, on canvas: any CanvasEditing) {
        current = input.point
        update(input, on: canvas)
    }

    func flagsChanged(_ input: ToolInput, on canvas: any CanvasEditing) {
        update(input, on: canvas)
    }

    func mouseUp(_ input: ToolInput, on canvas: any CanvasEditing) {
        current = input.point
        update(input, on: canvas)
        let ended = gesture
        let changed = shown
        gesture = nil
        shown = nil
        guard let ended, let changed else { return }
        guard changed != ended.original else {
            canvas.transient = nil
            return
        }
        canvas.commit(canvas.document.replacing(changed), actionName: "\(ended.verb) \(changed.title)",
                      coalescingKey: nil)
        canvas.transient = nil
    }

    private func update(_ input: ToolInput, on canvas: any CanvasEditing) {
        guard let gesture else { return }
        guard canvas.transient == shown else {
            self.gesture = nil
            shown = nil
            return
        }
        let delta = CGVector(dx: current.x - start.x, dy: current.y - start.y)
        guard shown != nil || DragGeometry.isLongEnough(from: start, to: current, zoom: canvas.zoom) else { return }
        switch gesture {
        case .move(let original):
            shown = original.moved(by: input.shift ? DragGeometry.axisLocked(delta) : delta)
        case .resize(let original, let handle, let from):
            let to = CGPoint(x: from.x + delta.dx, y: from.y + delta.dy)
            shown = HitTester.resized(original, handle: handle, to: to, square: input.shift)
        }
        canvas.transient = shown
    }
}
```

- [ ] **Step 7: Run the suite**

Run:
```bash
xcodegen generate && xcodebuild test -project TidyShot.xcodeproj -scheme TidyShot -destination 'platform=macOS' -derivedDataPath .build 2>&1 | grep -E "Test run with|error:|TEST"
```
Expected: no `error:` lines, and `Test run with 316 tests in 45 suites passed`.

There is no hand check in this task. The tools run in a window from Task 10, and its hand checks drag each one.

- [ ] **Step 8: Commit**

```bash
git add TidyShot/Editor/Tools/ToolFactory.swift TidyShot/Editor/Tools/RectDragTool.swift TidyShot/Editor/Tools/TwoPointTool.swift TidyShot/Editor/Tools/SelectTool.swift TidyShotTests/CanvasToolTests.swift
git commit -m "feat: select, rectangle, redaction and arrow tools"
```

### Task 10: Editor shell: base and canvas views, `EditorWindow`, controller and quit handling

**Files:**
- Create: `TidyShot/Editor/Window/BaseImageView.swift`
- Create: `TidyShot/Editor/Window/CanvasView.swift`
- Create: `TidyShot/Editor/Window/EditorWindow.swift`
- Create: `TidyShot/Editor/Window/EditorWindowController.swift`
- Modify: `TidyShot/App/AppCoordinator.swift` (a new `// MARK: Editor` section, inserted before `// MARK: Helpers` at line 842)
- Modify: `TidyShot/App/AppDelegate.swift` (one method after `applicationShouldTerminateAfterLastWindowClosed(_:)`, lines 18-20)
- Modify: `TidyShot/App/StatusMenuController.swift` (a Debug-only item after line 83, its action after line 112)
- Test: none new. This task is UI. Its decisions are already tested: `CanvasTransform` and `EditorWindowGeometry` in Task 3, `KeyRouting` and `EditorShortcut` in Task 4, `EditorModel` in Task 8, the tools in Task 9.

**Interfaces:**
- Consumes:
  - Task 2: `ScaledImage(image:scale:)`; `EditorDefaults.standard`; `EditorTool` (Equatable); `EditorPalette.lineWidthsPoints: [CGFloat]`; `Annotation.id`, `Annotation.isEffect: Bool`, `Annotation.effectRect: CGRect?`; `AnnotationDocument.effects`, `.drawings`, `.annotation(id:) -> Annotation?` (Equatable).
  - Task 3: `CanvasTransform` with its memberwise `init(zoom:offset:)`, `zoom` (view points per image pixel), `imagePoint(_:)`, `viewRect(_:)`, `imageRect(_:)`, `affine`, `static func fitting(imagePixelSize:in:inset:captureScale:) -> CanvasTransform`, `zoomed(by:around:limits:)` (anchor in view points), `panned(by:)` (adds a view-point delta to the offset), `snapped(toBackingScale:)`, `static func zoomLimits(captureScale:) -> ClosedRange<CGFloat>`; `ImageRects.integral(_:clippedTo:)`; `EditorWindowGeometry.initialContentSize(imagePixels:scale:chrome:visibleFrame:) -> CGSize` and `cascaded(from:size:visibleFrame:offset:) -> CGRect` (a frame of `size`; centred when `from` is nil).
  - Task 4: `KeyRouting.action(characters:command:control:option:isEditingText:) -> KeyRouting.Action` (`.selectTool(EditorTool)`, `.lineWidth(index:)` as an index into `lineWidthsPoints`, `.none`); `KeyRouting.nudge(dx:dy:shift:) -> CGVector`; `EditorShortcut.match(characters:command:shift:option:control:isEditingText:) -> EditorShortcut?` with lower-case `characters`; `EditorShortcut.selectorName`; `AnnotationGeometry.bounds(of:scale:) -> CGRect`.
  - Task 5: `RedactionRenderer.shared`, `warmUp(with:)`, `clearCaches()`.
  - Task 6: `RedactionTileCache.tiles: [UUID: (key: TileKey, image: CGImage)]`, `nonisolated static func orderedEffects(in:transient:) -> [Annotation]`, `currentTile(for:in:transient:) -> CGImage?`, `reconcile(document:transient:)`, `var onChange: () -> Void` (EditorModel does not set it; CanvasView does); `TileKey.effect`.
  - Task 7: `AnnotationDrawing.draw(_:in:scale:)`, `drawPlaceholder(for:in:)`, `drawSelection(for:transform:scale:in:)`.
  - Task 8: `EditorModel` (`init(recordID:image:renderer:defaults:)`, `recordID`, `base`, `scale`, `document`, `hasUnsavedChanges`, `selection`, `transient`, `tool`, `transform`, `undoManager`, `tileCache`, `deleteSelection()`, `nudgeSelection(by:)`, `applyLineWidth(points:)`, `cancelCurrentOperation()`, `selectAll()`, `markSaved()`, `renderExport() async -> ScaledImage?`); `ToolInput(point:shift:option:clickCount:)`; `CanvasTool` (`cursor`, `mouseDown(_:on:)`, `mouseDragged(_:on:)`, `mouseUp(_:on:)`, `flagsChanged(_:on:)`). A move or resize in progress is `transient` with the annotation's own id.
  - Task 9: `func makeTool(for: EditorTool) -> any CanvasTool`.
  - Existing: `private func imageData(of record: CaptureRecord) async throws -> Data` (AppCoordinator.swift:489), `private let notifier` (27) with `notifyError(_:title:)`, `let history` (22) with `record(id:)` and `records` (newest first, HistoryStore.swift:3), `CopyImageError.notAnImage` (AppCoordinator.swift:885), `ImageEncoder.decode(_:) -> (image: CGImage, scale: CGFloat)?` (ImageEncoder.swift:42), `AppDelegate.isRunningTests` (AppDelegate.swift:5), `StatusMenuController.item(_:_:key:)` (StatusMenuController.swift:89).
- Produces:
  - `final class BaseImageView: NSView`: `override init(frame: NSRect)`; `var image: CGImage?`; `var transform: CanvasTransform` (starts at `CanvasTransform(zoom: 1, offset: .zero)`); `func setTiles(_ tiles: [(id: UUID, rect: CGRect, image: CGImage?)])`, with `rect` in image pixels and a nil image hiding the tile. Flipped, layer-backed, `hitTest` returns nil.
  - `final class CanvasView: NSView`: `init(model: EditorModel, baseView: BaseImageView)`; `var isEditingText: Bool` (false in 4a; Task 4b-3 sets it); `override var undoManager: UndoManager?` (the model's); `func fitToView()`; `func zoom(by factor: CGFloat, around viewPoint: CGPoint? = nil)`; `func zoom(to level: CGFloat, around viewPoint: CGPoint? = nil)`, where `1 / model.scale` is natural size. It overrides `mouseDown`, `mouseDragged`, `mouseUp`, `flagsChanged`, `keyDown`, `scrollWheel`, `magnify`, `cancelOperation`, `deleteBackward`, `deleteForward`, `moveLeft`/`Right`/`Up`/`Down` and their four `…AndModifySelection` variants, `selectAll`, `resetCursorRects`, `setFrameSize`, `viewDidChangeBackingProperties` and `draw`.
  - `final class EditorWindow: NSWindow`: `weak var canvasView: CanvasView?`; `override func performKeyEquivalent(with event: NSEvent) -> Bool`.
  - `final class ShortcutItem: NSObject, NSValidatedUserInterfaceItem`: `init(action: Selector)`; `let action: Selector?`; `let tag: Int` (0).
  - `struct EditorActions { var save, saveCopy: (ScaledImage) async -> Bool; var copy: (ScaledImage) async -> Void; var upload: (ScaledImage, _ asNew: Bool) async -> Bool }`.
  - `final class EditorWindowController: NSWindowController, NSWindowDelegate, NSUserInterfaceValidations`: `let model: EditorModel`; `let canvasView: CanvasView`; `var onClose: ((EditorWindowController) -> Void)?`; `init(model: EditorModel, actions: EditorActions, title: String, representedURL: URL?, cascadeFrom: NSWindow?)`; `func present()`; `func askToSaveBeforeClosing() async -> Bool`; `@objc func saveDocument(_:)`, `saveDocumentCopy(_:)`, `copy(_:)` (calls `copyImage(_:)` in 4a), `copyImage(_:)`, `uploadDocument(_:)`, `uploadDocumentAsNew(_:)`, `zoomToFit(_:)`, `zoomToActualSize(_:)`, `zoomIn(_:)`, `zoomOut(_:)`, each `(_ sender: Any?)`; `func validateUserInterfaceItem(_ item: any NSValidatedUserInterfaceItem) -> Bool`; `windowShouldClose(_:)`, `windowWillReturnUndoManager(_:)`, `windowWillClose(_:)`.
    - Task 11 attaches the toolbar in `init` before the `placeWindow(cascadeFrom:)` call, so the measured chrome includes it. It drives every zoom through `canvasView.fitToView()`, `canvasView.zoom(to:)` and `canvasView.zoom(by:)` (the zoom pop-up too), and adds no transform arithmetic to the controller: only `CanvasView.apply(_:fits:)` clears `fitsOnResize` and refreshes the views at once.
    - Task 13 adds `recordDidChange(_:saveFolder:isDeleting:)` and the gate in `validateUserInterfaceItem(_:)` and in each action method. The gate is a `permits(_:)` guard placed first in each of the six action methods, ahead of their existing `runDocumentAction` call; Task 13 adds no second export path. `runDocumentAction`, `exportAndDeliver` and `isPerformingAction` stay the only way Save, Save Copy, Copy, Upload and the close sheet export, so a second Save while one runs still beeps. The close sheet picks Save or Save Copy… from `validateUserInterfaceItem` (`canSave`), which Task 13 gates, so it needs no change.
  - In AppCoordinator.swift, `// MARK: Editor`: `@ObservationIgnored private var editors: [UUID: EditorWindowController]`; `var hasUnsavedEditors: Bool`; `func openEditor(recordID: UUID)` (loads and decodes only; Task 16 refines it); `private func showEditor(recordID: UUID, image: ScaledImage)` (builds the `EditorModel` and the controller, stores it in `editors`, calls `present()`; Tasks 11 and 13 edit it, and Task 16 moves its body into `presentEditor`); `private func editorActions(for recordID: UUID) -> EditorActions` (logging stubs; Task 12 wires Save Copy and Copy, Task 13 Save, Task 15 Upload; those tasks replace the stubs here); `private func editorDidClose(_ controller: EditorWindowController)`; `func reviewEditorsBeforeQuit() async -> Bool`.
  - AppDelegate: `func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply`.
  - StatusMenuController, Debug builds only: the item `Annotate Last Capture (debug)` and `@objc private func annotateLastCapture()`. Task 16 removes both.

Three AppKit behaviours this task relies on were checked with a scratch app on this machine (macOS 27, SDK 27.0):
- The key window's `performKeyEquivalent(with:)` runs before the main menu. When it returns true, a main-menu item with the same key equivalent does not fire.
- `NSView` does not implement `undo:` or `redo:`, so the responder chain sends them to `NSWindow`. `NSWindow` undoes with its own `undoManager`, which comes from `windowWillReturnUndoManager(_:)`, not from the first responder's `undoManager`. Its `validateUserInterfaceItem(_:)` answers `canUndo` and `canRedo` for a bare `ShortcutItem`. The delegate method is therefore required.
- AppKit sets `geometryFlipped` on the layer of a flipped layer-backed view, so `BaseImageView`'s sublayer frames are in its top-left view coordinates.

The code below was type-checked under this project's settings against stubs of the Task 2 to 9 interfaces. Run against those stubs, ⌘= zoomed, the zoom limit refused a further ⌘= with a beep, ⌘W on a dirty document showed the sheet, and ⌘D closed the window and called `onClose`.

- [ ] **Step 1: Write the base image view**

`TidyShot/Editor/Window/BaseImageView.swift`:
```swift
import AppKit
import QuartzCore

/// The capture and its effect tiles, as layers placed by `transform`: one texture for the image and
/// one sublayer per tile, in creation order. Zoom and pan only move layer frames, and the view is
/// viewport-sized, so there is no document-sized backing store and no `_NSTiledLayer`. Clicks pass
/// through to the canvas above.
final class BaseImageView: NSView {
    var image: CGImage? {
        didSet {
            imageLayer.contents = image
            layoutLayers()
        }
    }

    var transform = CanvasTransform(zoom: 1, offset: .zero) {
        didSet {
            if transform != oldValue { layoutLayers() }
        }
    }

    private let imageLayer = CALayer()
    /// Tile layers by effect id, the image each shows and the rect it covers in image pixels.
    private var tileLayers: [UUID: CALayer] = [:]
    private var tileImages: [UUID: CGImage] = [:]
    private var tileRects: [UUID: CGRect] = [:]
    private var tileOrder: [UUID] = []

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layerContentsRedrawPolicy = .never
        imageLayer.contentsGravity = .resize
        layer?.addSublayer(imageLayer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    // AppKit sets geometryFlipped on a flipped view's layer, so sublayer frames are top-left
    // view points like everything else here.
    override var isFlipped: Bool { true }
    override var wantsUpdateLayer: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        layoutLayers()
    }

    /// One entry per effect on screen, in creation order. A nil image hides that tile; the canvas
    /// draws its placeholder. Layers for ids no longer listed are removed.
    func setTiles(_ tiles: [(id: UUID, rect: CGRect, image: CGImage?)]) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        var layers: [UUID: CALayer] = [:]
        var images: [UUID: CGImage] = [:]
        var rects: [UUID: CGRect] = [:]
        for tile in tiles {
            let tileLayer = tileLayers[tile.id] ?? makeTileLayer()
            if tileImages[tile.id] !== tile.image {
                tileLayer.contents = tile.image
            }
            tileLayer.isHidden = tile.image == nil
            layers[tile.id] = tileLayer
            images[tile.id] = tile.image
            rects[tile.id] = tile.rect
        }
        tileLayers = layers
        tileImages = images
        tileRects = rects
        tileOrder = tiles.map(\.id)
        layer?.sublayers = [imageLayer] + tileOrder.compactMap { layers[$0] }
        CATransaction.commit()
        layoutLayers()
    }

    private func makeTileLayer() -> CALayer {
        let tileLayer = CALayer()
        tileLayer.contentsGravity = .resize
        return tileLayer
    }

    /// Frames every layer at `transform.viewRect` of its image-pixel rect. Nearest-neighbour
    /// magnification from 2 device pixels per image pixel up, so redacted pixels read exactly when
    /// zoomed in; linear below; trilinear minification.
    private func layoutLayers() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let filter: CALayerContentsFilter = transform.zoom * (window?.backingScaleFactor ?? 2) >= 2 ? .nearest : .linear
        if let image {
            imageLayer.frame = transform.viewRect(CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        imageLayer.magnificationFilter = filter
        imageLayer.minificationFilter = .trilinear
        for id in tileOrder {
            guard let tileLayer = tileLayers[id], let rect = tileRects[id] else { continue }
            tileLayer.frame = transform.viewRect(rect)
            tileLayer.magnificationFilter = filter
            tileLayer.minificationFilter = .trilinear
        }
        CATransaction.commit()
    }
}
```

- [ ] **Step 2: Write the canvas view**

The canvas forwards pointer events to the active tool in image pixels, routes unmodified keys through `KeyRouting`, and applies zoom and pan. It repaints from the model. Some of its behaviour is not obvious from the spec:
- **Two refresh paths.** `refresh()` runs right after each event the canvas handles, so the overlay and the base view move in the same frame. It also runs from an Observation registration, which covers changes the canvas did not make: undo, redo, the toolbar and the controller's zoom actions. `refresh()` compares a snapshot (`Shown`), so running it twice costs nothing.
- **Repainting.** A change to `transient` alone repaints the union of the old and new shape, plus the document copy a move or resize replaces, outset 8 pt for handles. Any other change repaints the whole view.
- **Effect order.** The canvas lists effects with `RedactionTileCache.orderedEffects(in:transient:)`, the order the cache keys its tiles by: a new transient effect comes last, and a moved or resized one keeps its place. So while Select drags a redaction, an earlier blur is never stacked above it, and a later blur stays above it, exactly as after the commit.
- **Tiles during a drag.** While an effect is dragged, the canvas calls `tileCache.reconcile(document:transient:)` on each change. `EditorModel.commit` reconciles committed documents itself.
- **Stale tiles.** A redact shows its tile only while `tileCache.currentTile(for:in:transient:)` returns it. When that is nil (a new effect, or one just moved, resized or recoloured), the canvas draws the fill-colour placeholder, which has the pixels the finished tile will have, so no unredacted pixels show and nothing flickers. A blur or pixelate keeps showing the last tile the cache holds (`tiles[id]`) at the rect it was rendered for, one drag step behind; the grey placeholder appears only while it has no tile at all, so a dragged blur never flashes grey. This is the one place the canvas reads `tiles` directly: `currentTile` stays strict, and export never uses the preview tiles.
- **Shift-arrows.** Shift-arrow keys arrive as `moveLeftAndModifySelection:` and its three siblings, not as `moveLeft:` with Shift. Those four nudge by 10 px.
- **`flagsChanged`.** It re-sends the last `ToolInput` with the new modifiers. It never reads `clickCount` from the event: NSEvent raises for `clickCount` on anything but a mouse event.
- **Escape during a drag.** Escape replaces the tool, so the abandoned gesture's state goes with it, and ignores the rest of that gesture until the next mouseDown. Tool letters, Delete and nudges are ignored while the mouse is down.

`TidyShot/Editor/Window/CanvasView.swift`:
```swift
import AppKit
import Observation

/// The editor's interactive layer, on top of `BaseImageView`: it turns pointer and key events into
/// tool calls and model changes, and draws placeholders, drawings, the shape in progress and the
/// selection. Viewport-sized; zoom and pan are `model.transform`.
final class CanvasView: NSView {
    /// What the canvas last drew from. A change to `transient` alone repaints only the area it
    /// covered before and after; any other change repaints the whole view.
    private struct Shown: Equatable {
        var document: AnnotationDocument
        var transient: Annotation?
        var selection: UUID?
        var transform: CanvasTransform
    }

    /// True while a text annotation is being edited (4b). Always false in 4a.
    var isEditingText = false

    private let model: EditorModel
    private let baseView: BaseImageView
    private var activeTool: any CanvasTool
    private var activeToolKind: EditorTool
    private var shown: Shown
    /// Effects drawn as placeholders because they have no tile to show yet (see `shownTile(for:)`).
    private var pendingIDs: Set<UUID> = []
    /// Fit zoom is kept across window resizes until the user zooms or pans.
    private var fitsOnResize = true
    private var isTrackingMouse = false
    /// Set by Escape during a drag: the rest of that gesture is ignored.
    private var gestureCancelled = false
    /// The last pointer input, re-sent with new modifiers by `flagsChanged`.
    private var lastInput: ToolInput?

    init(model: EditorModel, baseView: BaseImageView) {
        self.model = model
        self.baseView = baseView
        activeToolKind = model.tool
        activeTool = makeTool(for: model.tool)
        shown = Shown(document: model.document, transient: model.transient, selection: model.selection,
                      transform: model.transform)
        super.init(frame: .zero)
        wantsLayer = true
        layerContentsRedrawPolicy = .onSetNeedsDisplay
        model.tileCache.onChange = { [weak self] in self?.tilesDidChange() }
        observeModel()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    override var isFlipped: Bool { true }
    override var isOpaque: Bool { false }
    override var acceptsFirstResponder: Bool { true }
    /// The responder chain's `undo:` and `redo:` reach the model's manager through here and
    /// through `windowWillReturnUndoManager(_:)`.
    override var undoManager: UndoManager? { model.undoManager }

    private var backingScale: CGFloat { window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2 }
    private var imagePixelSize: CGSize { CGSize(width: model.base.width, height: model.base.height) }

    // MARK: Zoom and pan

    /// The whole capture inside the view with `EditorWindowGeometry.inset` on every side, never above natural size; kept on resize.
    func fitToView() {
        guard bounds.width > 0, bounds.height > 0 else { return }
        apply(CanvasTransform.fitting(imagePixelSize: imagePixelSize, in: bounds.size, inset: EditorWindowGeometry.inset,
                                      captureScale: model.scale), fits: true)
    }

    /// Multiplies the zoom by `factor` around `viewPoint` (the view centre when nil), within
    /// `CanvasTransform.zoomLimits`.
    func zoom(by factor: CGFloat, around viewPoint: CGPoint? = nil) {
        let anchor = viewPoint ?? CGPoint(x: bounds.midX, y: bounds.midY)
        apply(model.transform.zoomed(by: factor, around: anchor,
                                     limits: CanvasTransform.zoomLimits(captureScale: model.scale)), fits: false)
    }

    /// Sets the zoom (view points per image pixel; `1 / model.scale` is natural size).
    func zoom(to level: CGFloat, around viewPoint: CGPoint? = nil) {
        zoom(by: level / model.transform.zoom, around: viewPoint)
    }

    private func apply(_ transform: CanvasTransform, fits: Bool) {
        fitsOnResize = fits
        model.transform = transform.snapped(toBackingScale: backingScale)
        refresh()
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        if fitsOnResize { fitToView() }
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        if fitsOnResize {
            fitToView()
        } else {
            apply(model.transform, fits: false)
        }
    }

    override func magnify(with event: NSEvent) {
        zoom(by: 1 + event.magnification, around: convert(event.locationInWindow, from: nil))
    }

    /// ⌘-scroll zooms around the cursor; plain scroll pans. A mouse wheel moves in lines, so its
    /// deltas are scaled by 10 points per line, and each ⌘-notch zooms by 1.25.
    override func scrollWheel(with event: NSEvent) {
        let precise = event.hasPreciseScrollingDeltas
        if event.modifierFlags.contains(.command) {
            let delta = event.scrollingDeltaY
            guard delta != 0 else { return }
            let factor = precise ? exp(delta / 100) : (delta > 0 ? 1.25 : 1 / 1.25)
            zoom(by: factor, around: convert(event.locationInWindow, from: nil))
        } else {
            let line: CGFloat = precise ? 1 : 10
            apply(model.transform.panned(by: CGPoint(x: event.scrollingDeltaX * line, y: event.scrollingDeltaY * line)),
                  fits: false)
        }
    }

    // MARK: Pointer

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        isTrackingMouse = true
        gestureCancelled = false
        activeTool.mouseDown(input(for: event), on: model)
        refresh()
    }

    override func mouseDragged(with event: NSEvent) {
        guard isTrackingMouse, !gestureCancelled else { return }
        activeTool.mouseDragged(input(for: event), on: model)
        refresh()
    }

    override func mouseUp(with event: NSEvent) {
        defer {
            isTrackingMouse = false
            gestureCancelled = false
            refresh()
        }
        guard isTrackingMouse, !gestureCancelled else { return }
        activeTool.mouseUp(input(for: event), on: model)
    }

    /// Shift and Option re-applied mid-drag without mouse movement. `clickCount` is not read from
    /// this event: NSEvent raises for it on anything but a mouse event.
    override func flagsChanged(with event: NSEvent) {
        super.flagsChanged(with: event)
        guard isTrackingMouse, !gestureCancelled, var input = lastInput else { return }
        input.shift = event.modifierFlags.contains(.shift)
        input.option = event.modifierFlags.contains(.option)
        lastInput = input
        activeTool.flagsChanged(input, on: model)
        refresh()
    }

    private func input(for event: NSEvent) -> ToolInput {
        let flags = event.modifierFlags
        let input = ToolInput(point: model.transform.imagePoint(convert(event.locationInWindow, from: nil)),
                              shift: flags.contains(.shift), option: flags.contains(.option),
                              clickCount: event.clickCount)
        lastInput = input
        return input
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: activeTool.cursor)
    }

    // MARK: Keys (unmodified keys; ⌘ chords are EditorWindow's)

    override func keyDown(with event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        switch KeyRouting.action(characters: event.charactersIgnoringModifiers, command: flags.contains(.command),
                                 control: flags.contains(.control), option: flags.contains(.option),
                                 isEditingText: isEditingText) {
        case .selectTool(let tool):
            guard !isTrackingMouse else { return }
            model.tool = tool
            refresh()
        case .lineWidth(let index):
            let widths = EditorPalette.lineWidthsPoints
            guard widths.indices.contains(index) else { return }
            model.applyLineWidth(points: widths[index])
            refresh()
        case .none:
            interpretKeyEvents([event])
        }
    }

    /// Escape and ⌘.: abandons a drag in progress (the tool is replaced, so its gesture state goes
    /// too), then the model drops the transient shape or the selection. Never closes the window.
    override func cancelOperation(_ sender: Any?) {
        if isTrackingMouse {
            gestureCancelled = true
            activeTool = makeTool(for: activeToolKind)
        }
        model.cancelCurrentOperation()
        refresh()
    }

    override func deleteBackward(_ sender: Any?) { deleteSelection() }
    override func deleteForward(_ sender: Any?) { deleteSelection() }
    override func moveLeft(_ sender: Any?) { nudge(dx: -1, dy: 0, shift: false) }
    override func moveRight(_ sender: Any?) { nudge(dx: 1, dy: 0, shift: false) }
    override func moveUp(_ sender: Any?) { nudge(dx: 0, dy: -1, shift: false) }
    override func moveDown(_ sender: Any?) { nudge(dx: 0, dy: 1, shift: false) }
    // Shift-arrow arrives as the …AndModifySelection: variants, not as moveLeft: with Shift.
    override func moveLeftAndModifySelection(_ sender: Any?) { nudge(dx: -1, dy: 0, shift: true) }
    override func moveRightAndModifySelection(_ sender: Any?) { nudge(dx: 1, dy: 0, shift: true) }
    override func moveUpAndModifySelection(_ sender: Any?) { nudge(dx: 0, dy: -1, shift: true) }
    override func moveDownAndModifySelection(_ sender: Any?) { nudge(dx: 0, dy: 1, shift: true) }

    override func selectAll(_ sender: Any?) {
        model.selectAll()
        refresh()
    }

    private func deleteSelection() {
        guard !isTrackingMouse else { return }
        model.deleteSelection()
        refresh()
    }

    private func nudge(dx: Int, dy: Int, shift: Bool) {
        guard !isTrackingMouse else { return }
        model.nudgeSelection(by: KeyRouting.nudge(dx: dx, dy: dy, shift: shift))
        refresh()
    }

    // MARK: Model to screen

    /// Re-registers on every change (Observation reports one change per registration, before it
    /// happens) and refreshes on the next main-actor turn, as StatusMenuController.updateIcon does.
    /// This covers changes this view did not make: undo and redo, the toolbar, the controller's
    /// zoom actions.
    private func observeModel() {
        withObservationTracking {
            _ = model.document
            _ = model.transient
            _ = model.selection
            _ = model.transform
            _ = model.tool
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.observeModel()
                self?.refresh()
            }
        }
    }

    /// Brings the tool, the base view, the tiles and the overlay in line with the model.
    /// Idempotent, so the synchronous call after an event and the observed one can both run.
    private func refresh() {
        if model.tool != activeToolKind, !isTrackingMouse {
            activeToolKind = model.tool
            activeTool = makeTool(for: activeToolKind)
            window?.invalidateCursorRects(for: self)
        }
        let now = Shown(document: model.document, transient: model.transient, selection: model.selection,
                        transform: model.transform)
        guard now != shown else { return }
        let previous = shown
        shown = now
        baseView.transform = now.transform
        // The effect being dragged is rendered on every change; commits reconcile in the model.
        if now.transient != previous.transient, now.transient?.isEffect == true || previous.transient?.isEffect == true {
            model.tileCache.reconcile(document: now.document, transient: now.transient)
        }
        if now.document != previous.document || now.transient != previous.transient {
            syncTiles()
        }
        #if DEBUG
        if now.document != previous.document {
            NSLog("Editor: undo \"\(model.undoManager.undoActionName)\", redo \"\(model.undoManager.redoActionName)\"")
        }
        #endif
        if now.document == previous.document, now.selection == previous.selection, now.transform == previous.transform {
            setNeedsDisplay(repaintRect(for: previous.transient, in: previous.document)
                .union(repaintRect(for: now.transient, in: now.document)))
        } else {
            needsDisplay = true
        }
    }

    /// The view area a transient shape covers, together with the document copy it replaces while
    /// it is moved or resized, with room for selection handles.
    private func repaintRect(for transient: Annotation?, in document: AnnotationDocument) -> CGRect {
        guard let transient else { return .null }
        var rect = imageBounds(of: transient)
        if let original = document.annotation(id: transient.id) {
            rect = rect.union(imageBounds(of: original))
        }
        return model.transform.viewRect(rect).insetBy(dx: -8, dy: -8)
    }

    private func imageBounds(of annotation: Annotation) -> CGRect {
        annotation.effectRect ?? AnnotationGeometry.bounds(of: annotation, scale: model.scale)
    }

    private func tilesDidChange() {
        syncTiles()
    }

    /// One entry per effect on screen, in the cache's order. An entry with no tile to show has a
    /// nil image, which hides its layer; the canvas draws its placeholder. Placeholders that now
    /// have a tile, and tiles that went stale, are repainted.
    private func syncTiles() {
        let effects = displayedEffects
        var tiles: [UUID: (rect: CGRect, image: CGImage)] = [:]
        for effect in effects {
            tiles[effect.id] = shownTile(for: effect)
        }
        baseView.setTiles(effects.map { effect -> (id: UUID, rect: CGRect, image: CGImage?) in
            if let tile = tiles[effect.id] {
                return (id: effect.id, rect: tile.rect, image: tile.image)
            }
            return (id: effect.id, rect: ImageRects.integral(effect.effectRect ?? .zero, clippedTo: imagePixelSize), image: nil)
        })
        let pending = Set(effects.filter { tiles[$0.id] == nil }.map(\.id))
        for effect in effects where pending.contains(effect.id) != pendingIDs.contains(effect.id) {
            if let rect = effect.effectRect {
                setNeedsDisplay(model.transform.viewRect(rect).insetBy(dx: -8, dy: -8))
            }
        }
        pendingIDs = pending
    }

    /// The tile to show for `effect` and the image-pixel rect it covers, or nil for the placeholder.
    /// A redact shows only a current tile (`currentTile` is nil when its key is stale), because its
    /// placeholder is the finished tile's pixels. A blur or pixelate shows the last stored tile at
    /// the rect it was rendered for, so a dragged one never flashes to its grey placeholder.
    private func shownTile(for effect: Annotation) -> (rect: CGRect, image: CGImage)? {
        let size = imagePixelSize
        if case .redact = effect {
            guard let image = model.tileCache.currentTile(for: effect, in: model.document, transient: model.transient),
                  let rect = effect.effectRect else { return nil }
            return (rect: ImageRects.integral(rect, clippedTo: size), image: image)
        }
        guard let tile = model.tileCache.tiles[effect.id], let rect = tile.key.effect.effectRect else { return nil }
        return (rect: ImageRects.integral(rect, clippedTo: size), image: tile.image)
    }

    /// Effects in the tile cache's order: creation order with `transient` in place of the document
    /// effect it moves or resizes, or last when it is a new shape.
    private var displayedEffects: [Annotation] {
        RedactionTileCache.orderedEffects(in: model.document, transient: model.transient)
    }

    /// Drawings in creation order, with `transient` in place of its document copy and drawn last
    /// (spec 2.6: the shape in progress is drawn after the drawings). Drawings always sit above
    /// effects, so their order cannot expose a redaction.
    private var displayedDrawings: [Annotation] {
        let transient = model.transient
        var drawings = model.document.drawings.filter { $0.id != transient?.id }
        if let transient, !transient.isEffect { drawings.append(transient) }
        return drawings
    }

    private var selectedAnnotation: Annotation? {
        guard let id = model.selection else { return nil }
        if let transient = model.transient, transient.id == id { return transient }
        return model.document.annotation(id: id)
    }

    // MARK: Drawing

    /// Spec 2.6 Rendering: (1) image-pixel CTM; (2) placeholders for effects with no tile yet;
    /// (3) drawings meeting the dirty rect, then the transient shape; (4) back in view space, the
    /// selection handles or dashed outline. No Core Image or GPU work happens here.
    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        let transform = model.transform
        let visible = transform.imageRect(dirtyRect)
        context.saveGState()
        context.concatenate(transform.affine)
        for effect in displayedEffects where pendingIDs.contains(effect.id) {
            guard let rect = effect.effectRect, rect.intersects(visible) else { continue }
            AnnotationDrawing.drawPlaceholder(for: effect, in: context)
        }
        for drawing in displayedDrawings where imageBounds(of: drawing).intersects(visible) {
            AnnotationDrawing.draw(drawing, in: context, scale: model.scale)
        }
        context.restoreGState()
        if let selected = selectedAnnotation {
            // The view's backing scale snaps the outline and handles to device pixels; the drawings
            // above take the capture scale (`model.scale`).
            AnnotationDrawing.drawSelection(for: selected, transform: transform, scale: backingScale, in: context)
        }
    }
}
```

- [ ] **Step 3: Write the editor window**

`TidyShot/Editor/Window/EditorWindow.swift`:
```swift
import AppKit

/// The annotation editor's window. The SwiftUI main menu of an LSUIElement app is never drawn, so
/// editor shortcuts are looked up here, in the pure `EditorShortcut` table. The key window sees a
/// key equivalent before the main menu, so a matched chord is handled exactly once.
final class EditorWindow: NSWindow {
    /// Set by EditorWindowController. Its `isEditingText` (4b) lets the clipboard and undo chords
    /// through to the text view.
    weak var canvasView: CanvasView?

    /// `NSApp.sendAction` does not consult NSUserInterfaceValidations, so a matched shortcut is
    /// validated against the target that would receive it first: a refusal beeps and consumes the
    /// event. Anything the table does not match (⌘X, ⌘Q, ⌘,) goes on to super and the main menu.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.type == .keyDown, let characters = event.charactersIgnoringModifiers else {
            return super.performKeyEquivalent(with: event)
        }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        // charactersIgnoringModifiers keeps Shift ("S" for ⇧⌘S), so it is lower-cased here and
        // Shift travels as its own flag.
        guard let shortcut = EditorShortcut.match(characters: characters.lowercased(),
                                                  command: flags.contains(.command), shift: flags.contains(.shift),
                                                  option: flags.contains(.option), control: flags.contains(.control),
                                                  isEditingText: canvasView?.isEditingText ?? false) else {
            return super.performKeyEquivalent(with: event)
        }
        let action = NSSelectorFromString(shortcut.selectorName)
        guard let target = NSApp.target(forAction: action, to: nil, from: self),
              (target as? NSUserInterfaceValidations)?.validateUserInterfaceItem(ShortcutItem(action: action)) ?? true else {
            NSSound.beep()
            return true
        }
        NSApp.sendAction(action, to: target, from: self)
        return true
    }
}

/// What a validator sees for a keyboard shortcut: its action, and no tag.
final class ShortcutItem: NSObject, NSValidatedUserInterfaceItem {
    let action: Selector?
    let tag = 0

    init(action: Selector) {
        self.action = action
    }
}
```

The targets the responder chain finds, with the canvas as first responder:
- `undo:`, `redo:` and `performClose:` go to the window.
- `selectAll:` goes to the canvas, which does not validate, so it is always sent.
- `saveDocument:`, `saveDocumentCopy:`, `copy:`, `copyImage:`, `uploadDocument:`, `uploadDocumentAsNew:` and the four zoom actions go to the controller, which is the window's delegate.

- [ ] **Step 4: Write the window controller**

The window follows spec 2.6 Window: style mask `[.titled, .closable, .miniaturizable, .resizable]`, `.unified` toolbar style, normal level, `[.managed, .fullScreenPrimary]`, tabbing disallowed and no frame autosave. Its content view is a plain container holding `BaseImageView` with `CanvasView` on top, both viewport-sized and autoresizing.

The document actions:
- **One at a time.** A second action while one runs beeps, and validation refuses it.
- **The export.** Each action flattens through `model.renderExport()` and hands the `ScaledImage` to its `EditorActions` closure.
- **Marking saved.** Save, Save Copy and Upload call `markSaved()` only when the closure succeeds and the document has not changed since the export started. Copy never marks the document saved.

`TidyShot/Editor/Window/EditorWindowController.swift`:
```swift
import AppKit
import Observation

/// What the editor's document actions do, provided by AppCoordinator: the editor never writes
/// files, never touches the pasteboard and never enqueues uploads. For Save, Save Copy and Upload
/// the Bool says whether the edit was written, which is when the editor marks itself saved.
struct EditorActions {
    var save, saveCopy: (ScaledImage) async -> Bool
    var copy: (ScaledImage) async -> Void
    var upload: (ScaledImage, _ asNew: Bool) async -> Bool
}

/// One annotation editor window for one capture record: the window, the two stacked views, the
/// document actions, zoom, and the unsaved-changes sheet.
final class EditorWindowController: NSWindowController, NSWindowDelegate, NSUserInterfaceValidations {
    let model: EditorModel
    let canvasView: CanvasView
    /// Called from `windowWillClose(_:)`; AppCoordinator drops the editor from its registry.
    var onClose: ((EditorWindowController) -> Void)?

    private let actions: EditorActions
    /// One document action at a time; another one beeps until it finishes.
    private var isPerformingAction = false

    #if DEBUG
    private static var loggedMainMenu = false
    #endif

    init(model: EditorModel, actions: EditorActions, title: String, representedURL: URL?, cascadeFrom: NSWindow?) {
        self.model = model
        self.actions = actions
        let baseView = BaseImageView(frame: .zero)
        baseView.image = model.base
        let canvasView = CanvasView(model: model, baseView: baseView)
        self.canvasView = canvasView

        let window = EditorWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 420),
                                  styleMask: [.titled, .closable, .miniaturizable, .resizable],
                                  backing: .buffered, defer: true)
        window.toolbarStyle = .unified
        window.level = .normal
        window.collectionBehavior = [.managed, .fullScreenPrimary]
        window.tabbingMode = .disallowed
        window.isReleasedWhenClosed = false
        window.title = title
        window.representedURL = representedURL
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 640, height: 420))
        for view in [baseView, canvasView] as [NSView] {
            view.frame = container.bounds
            view.autoresizingMask = [.width, .height]
            container.addSubview(view)
        }
        window.contentView = container
        window.canvasView = canvasView
        window.initialFirstResponder = canvasView
        super.init(window: window)
        shouldCascadeWindows = false
        window.delegate = self
        placeWindow(cascadeFrom: cascadeFrom)
        observeEdited()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not used")
    }

    /// Sizes the window to the capture's natural point size plus chrome, within 640x420 and 90%
    /// of the visible frame of the screen under the mouse, and cascades it 22 pt from
    /// `previous`. No frame autosave. The chrome is measured from the window, so a toolbar
    /// attached before this call is included.
    private func placeWindow(cascadeFrom previous: NSWindow?) {
        guard let window, let content = window.contentView else { return }
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main ?? NSScreen.screens[0]
        let visible = screen.visibleFrame
        let chrome = CGSize(width: window.frame.width - content.frame.width,
                            height: window.frame.height - content.frame.height)
        let contentSize = EditorWindowGeometry.initialContentSize(
            imagePixels: CGSize(width: model.base.width, height: model.base.height), scale: model.scale,
            chrome: chrome, visibleFrame: visible)
        let size = CGSize(width: contentSize.width + chrome.width, height: contentSize.height + chrome.height)
        window.setFrame(EditorWindowGeometry.cascaded(from: previous?.frame, size: size, visibleFrame: visible),
                        display: false)
    }

    /// `isDocumentEdited` mirrors `hasUnsavedChanges`, re-registering on each change.
    private func observeEdited() {
        let edited = withObservationTracking {
            model.hasUnsavedChanges
        } onChange: { [weak self] in
            Task { @MainActor in self?.observeEdited() }
        }
        window?.isDocumentEdited = edited
    }

    /// The codebase's activation idiom: a plain `activate()` is refused when called from the
    /// non-activating overlay.
    func present() {
        NSApplication.shared.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        if !NSApp.isActive {
            window?.orderFrontRegardless()
        }
        #if DEBUG
        if !Self.loggedMainMenu {
            Self.loggedMainMenu = true
            NSLog("Editor: main menu items \(NSApp.mainMenu?.items.map(\.title) ?? [])")
        }
        #endif
    }

    // MARK: Document actions

    @objc func saveDocument(_ sender: Any?) {
        runDocumentAction(marksSaved: true) { await self.actions.save($0) }
    }

    @objc func saveDocumentCopy(_ sender: Any?) {
        runDocumentAction(marksSaved: true) { await self.actions.saveCopy($0) }
    }

    /// ⌘C. In 4a it copies the flattened image, like ⇧⌘C; 4b gives CanvasView an object copy that
    /// passes this up when nothing is selected.
    @objc func copy(_ sender: Any?) {
        copyImage(sender)
    }

    @objc func copyImage(_ sender: Any?) {
        runDocumentAction(marksSaved: false) { image in
            await self.actions.copy(image)
            return true
        }
    }

    @objc func uploadDocument(_ sender: Any?) {
        runDocumentAction(marksSaved: true) { await self.actions.upload($0, false) }
    }

    @objc func uploadDocumentAsNew(_ sender: Any?) {
        runDocumentAction(marksSaved: true) { await self.actions.upload($0, true) }
    }

    private func runDocumentAction(marksSaved: Bool, _ deliver: @escaping (ScaledImage) async -> Bool) {
        guard !isPerformingAction else {
            NSSound.beep()
            return
        }
        isPerformingAction = true
        Task {
            defer { isPerformingAction = false }
            _ = await exportAndDeliver(marksSaved: marksSaved, deliver)
        }
    }

    /// Flattens the document as it is now and hands the image over. It is marked saved only when
    /// `deliver` succeeds and nothing was edited meanwhile; an edit made during the save stays
    /// unsaved.
    private func exportAndDeliver(marksSaved: Bool, _ deliver: (ScaledImage) async -> Bool) async -> Bool {
        let exported = model.document
        guard let image = await model.renderExport() else {
            NSLog("Editor: the export of \(model.recordID) failed")
            NSSound.beep()
            return false
        }
        guard await deliver(image) else { return false }
        if marksSaved, model.document == exported {
            model.markSaved()
        }
        return true
    }

    // MARK: Zoom

    @objc func zoomToFit(_ sender: Any?) { canvasView.fitToView() }
    @objc func zoomToActualSize(_ sender: Any?) { canvasView.zoom(to: 1 / model.scale) }
    @objc func zoomIn(_ sender: Any?) { canvasView.zoom(by: 1.25) }
    @objc func zoomOut(_ sender: Any?) { canvasView.zoom(by: 1 / 1.25) }

    // MARK: NSUserInterfaceValidations

    func validateUserInterfaceItem(_ item: any NSValidatedUserInterfaceItem) -> Bool {
        let limits = CanvasTransform.zoomLimits(captureScale: model.scale)
        switch item.action {
        case #selector(saveDocument(_:)), #selector(saveDocumentCopy(_:)), #selector(copy(_:)),
             #selector(copyImage(_:)), #selector(uploadDocument(_:)), #selector(uploadDocumentAsNew(_:)):
            return !isPerformingAction
        case #selector(zoomIn(_:)):
            return model.transform.zoom < limits.upperBound * 0.999
        case #selector(zoomOut(_:)):
            return model.transform.zoom > limits.lowerBound * 1.001
        default:
            return true
        }
    }

    // MARK: Closing

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard model.hasUnsavedChanges else { return true }
        Task {
            if await askToSaveBeforeClosing() {
                window?.close()
            }
        }
        return false
    }

    /// The unsaved-changes sheet. True when the window may close: nothing to save, Don’t Save, or a
    /// Save that wrote the edit. False for Cancel, a failed save, a sheet already showing or an
    /// action still running. Save becomes Save Copy… when this controller's own validation refuses
    /// Save.
    func askToSaveBeforeClosing() async -> Bool {
        guard model.hasUnsavedChanges else { return true }
        guard let window, window.attachedSheet == nil, !isPerformingAction else {
            NSSound.beep()
            return false
        }
        let canSave = validateUserInterfaceItem(ShortcutItem(action: #selector(saveDocument(_:))))
        let alert = NSAlert()
        alert.messageText = "Do you want to save the changes made to “\(window.title)”?"
        alert.informativeText = "Your changes will be lost if you don’t save them."
        alert.addButton(withTitle: canSave ? "Save" : "Save Copy…")
        alert.addButton(withTitle: "Cancel")
        let dontSave = alert.addButton(withTitle: "Don’t Save")
        dontSave.keyEquivalent = "d"
        dontSave.keyEquivalentModifierMask = .command
        switch await alert.beginSheetModal(for: window) {
        case .alertFirstButtonReturn:
            isPerformingAction = true
            defer { isPerformingAction = false }
            return await exportAndDeliver(marksSaved: true) { image in
                canSave ? await self.actions.save(image) : await self.actions.saveCopy(image)
            }
        case .alertThirdButtonReturn:
            return true
        default:
            return false
        }
    }

    func windowWillReturnUndoManager(_ window: NSWindow) -> UndoManager? {
        model.undoManager
    }

    func windowWillClose(_ notification: Notification) {
        onClose?(self)
    }
}
```

- [ ] **Step 5: Add the coordinator's editor section**

In `TidyShot/App/AppCoordinator.swift`, insert this before `    // MARK: Helpers` (line 842), after `deleteOrphanedObject(key:at:)` ends at line 840. It sits in the class body because it calls the `private` members `imageData(of:)` (489) and `notifier` (27). The decode in a detached task mirrors `copyImage(recordID:)` (469-472).

```swift
    // MARK: Editor

    /// Open annotation editors, one per record.
    @ObservationIgnored private var editors: [UUID: EditorWindowController] = [:]

    /// True while any open editor has changes that were not saved.
    var hasUnsavedEditors: Bool {
        editors.values.contains { $0.model.hasUnsavedChanges }
    }

    /// Opens the annotation editor for `recordID`, or brings its open editor forward. The PNG is
    /// read as Copy Image reads it (`imageData(of:)`: the local file, else the uploaded object),
    /// and decoded in a detached task, which also recovers the capture's scale from its DPI.
    /// Task 16 adds the in-memory image of the capture just taken (`EditorInput`).
    func openEditor(recordID: UUID) {
        if let open = editors[recordID] {
            open.present()
            return
        }
        guard let record = history.record(id: recordID) else { return }
        Task {
            do {
                let png = try await imageData(of: record)
                let decoded = await Task.detached(priority: .userInitiated) { ImageEncoder.decode(png) }.value
                guard let decoded else { throw CopyImageError.notAnImage }
                showEditor(recordID: recordID, image: ScaledImage(image: decoded.image, scale: decoded.scale))
            } catch {
                notifier.notifyError(error.localizedDescription, title: "Could not open the capture")
            }
        }
    }

    /// Builds the model and the window and shows them. Re-checked after the load's awaits: an
    /// editor opened meanwhile is brought forward instead, and a record deleted meanwhile opens
    /// nothing.
    private func showEditor(recordID: UUID, image: ScaledImage) {
        if let open = editors[recordID] {
            open.present()
            return
        }
        guard let record = history.record(id: recordID) else { return }
        // A save-folder file names the window and gives it a proxy icon; a pending file in the
        // container is not shown.
        let fileURL = record.fileIsTemporary ? nil : record.fileURL
        let title = fileURL?.lastPathComponent
            ?? "Capture \(record.timestamp.formatted(date: .omitted, time: .shortened))"
        let model = EditorModel(recordID: recordID, image: image, renderer: RedactionRenderer.shared, defaults: .standard)
        let controller = EditorWindowController(model: model, actions: editorActions(for: recordID), title: title,
                                                representedURL: fileURL,
                                                cascadeFrom: NSApp.orderedWindows.first { $0 is EditorWindow })
        controller.onClose = { [weak self] closed in self?.editorDidClose(closed) }
        editors[recordID] = controller
        Task { await RedactionRenderer.shared.warmUp(with: image.image) }
        controller.present()
    }

    /// Stubs that only log, so the window, tools and undo can be used before the actions exist:
    /// Task 12 wires Save Copy and Copy, Task 13 Save, Task 15 Upload. A stub reports failure, so
    /// nothing is marked saved and the close sheet's Save keeps the window open.
    private func editorActions(for recordID: UUID) -> EditorActions {
        EditorActions(
            save: { image in
                NSLog("Editor: Save of \(recordID) (\(image.image.width)x\(image.image.height) @\(image.scale)x) is not wired yet")
                return false
            },
            saveCopy: { _ in
                NSLog("Editor: Save Copy of \(recordID) is not wired yet")
                return false
            },
            copy: { _ in
                NSLog("Editor: Copy of \(recordID) is not wired yet")
            },
            upload: { _, asNew in
                NSLog("Editor: Upload\(asNew ? " as New" : "") of \(recordID) is not wired yet")
                return false
            })
    }

    /// Drops a closed editor. When the last one closes, the renderer frees its caches.
    private func editorDidClose(_ controller: EditorWindowController) {
        let id = controller.model.recordID
        guard editors[id] === controller else { return }
        editors[id] = nil
        if editors.isEmpty {
            Task { await RedactionRenderer.shared.clearCaches() }
        }
    }

    /// Quitting does not call `windowShouldClose`, so AppDelegate calls this while it holds the
    /// quit (`.terminateLater`). Each editor with unsaved changes comes forward and shows the
    /// close sheet in turn. False (Cancel, or a Save that failed) stops the quit; editors already
    /// answered stay as they are.
    func reviewEditorsBeforeQuit() async -> Bool {
        for controller in Array(editors.values) where controller.model.hasUnsavedChanges {
            guard editors[controller.model.recordID] === controller else { continue }
            controller.present()
            guard await controller.askToSaveBeforeClosing() else { return false }
        }
        return true
    }

```

`editors` is `@ObservationIgnored`, like `deletingIDs` (line 48). It is a registry, not state any view observes.

- [ ] **Step 6: Hold the quit while an editor is dirty**

In `TidyShot/App/AppDelegate.swift` (lines 18-21), replace:
```swift
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
```
with:
```swift
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    /// Quitting does not call `windowShouldClose`, so an editor with unsaved changes is reviewed
    /// here: the quit waits (`.terminateLater`) while `reviewEditorsBeforeQuit()` shows the close
    /// sheet in each one, and goes ahead only when none was cancelled.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !Self.isRunningTests, AppCoordinator.shared.hasUnsavedEditors else { return .terminateNow }
        Task {
            let proceed = await AppCoordinator.shared.reviewEditorsBeforeQuit()
            sender.reply(toApplicationShouldTerminate: proceed)
        }
        return .terminateLater
    }
}
```

While the reply is pending, AppKit runs the run loop in the modal-panel mode. That mode is one of the common modes, so the main-actor task and the sheets run.

- [ ] **Step 7: Add the temporary Debug entry point**

This item is the editor's only way in until Task 16 adds the overlay's Annotate button, and Task 16 removes it. AppKit calls the action after the menu has closed (the comment at StatusMenuController.swift:105), so the window never opens inside menu tracking.

In `TidyShot/App/StatusMenuController.swift` (lines 81-83), replace:
```swift
        let reveal = item("Reveal Last Capture", #selector(revealLastCapture))
        reveal.isEnabled = coordinator.lastCaptureURL != nil
        menu.addItem(reveal)
```
with:
```swift
        let reveal = item("Reveal Last Capture", #selector(revealLastCapture))
        reveal.isEnabled = coordinator.lastCaptureURL != nil
        menu.addItem(reveal)
        #if DEBUG
        // Temporary entry point to the editor until the overlay's Annotate button (Task 16).
        let annotate = item("Annotate Last Capture (debug)", #selector(annotateLastCapture))
        annotate.isEnabled = !coordinator.history.records.isEmpty
        menu.addItem(annotate)
        #endif
```

At line 112, replace:
```swift
    @objc private func revealLastCapture() { coordinator.revealLastCapture() }
```
with:
```swift
    @objc private func revealLastCapture() { coordinator.revealLastCapture() }
    #if DEBUG
    /// Opens the editor on the newest record (`history.records` is newest first).
    @objc private func annotateLastCapture() {
        guard let id = coordinator.history.records.first?.id else { return }
        coordinator.openEditor(recordID: id)
    }
    #endif
```

- [ ] **Step 8: Build and run the tests**

Run:
```bash
xcodegen generate && xcodebuild test -project TidyShot.xcodeproj -scheme TidyShot -destination 'platform=macOS' -derivedDataPath .build 2>&1 | grep -E "Test run with|error:|TEST"
```
Expected: no `error:` lines, and `Test run with 316 tests in 45 suites passed`, unchanged, because this task adds no tests. If the hosted test run ends, `applicationShouldTerminate(_:)` returns `.terminateNow` because of `isRunningTests`.

- [ ] **Step 9: Check by hand**

Run:
```bash
xcodebuild -project TidyShot.xcodeproj -scheme TidyShot -configuration Debug -derivedDataPath .build build -quiet && open .build/Build/Products/Debug/TidyShot.app
```
In a second terminal, follow the editor's log lines:
```bash
log stream --style compact --predicate 'process == "TidyShot" AND eventMessage CONTAINS "Editor"'
```

Expected:
- **Opening.** Take a fullscreen capture (⌃⇧3; 5120x2820 px on a 2560x1410 pt display at 2x). Make Safari frontmost, then choose Annotate Last Capture (debug) from the menu bar.
  - The editor opens in front of Safari and is key.
  - It is no larger than 90% of the screen, and the capture is fitted with a 24 pt margin.
  - The title is the file name, or `Capture <time>` for an upload-only capture.
  - The log shows `Editor: main menu items [...]` once. Note the titles in the task report.
- **Tools.**
  - D and a drag draw a black box. X and B draw pixelate and blur; during the drag the tile follows within a frame and never flashes grey, apart from the first frame of a new region.
  - R draws a red rectangle. A draws an arrow; Shift snaps it to 45°.
  - Press and release Shift mid-drag without moving the mouse: a rectangle squares and unsquares.
  - V selects: a drag moves the shape, Shift locks the axis, and a handle resizes it.
  - Stacking while dragging: draw a black box, then a blur over part of it. Select the black box and drag it. It stays under the blur the whole time, as after you let go, and a fresh unredacted strip never shows at its leading edge.
  - Digits 1 to 6 change the line width of a selected rectangle.
- **Undo.**
  - ⌘Z undoes one step per press and ⇧⌘Z redoes it. With two shapes drawn, one ⌘Z removes exactly one, so there is no double undo through the hidden menu.
  - Each step logs `Editor: undo "…", redo "…"` with the names changing.
  - With nothing left to undo, ⌘Z beeps and nothing happens. That is a refused validation.
- **Keys on the canvas.**
  - Delete and Forward Delete remove the selection.
  - Arrow keys nudge 1 px and Shift-arrow keys 10 px. A run of nudges undoes with one ⌘Z.
  - Escape during a drag abandons it, and releasing the mouse creates nothing. Escape again deselects. The window stays open. ⌘. does the same as Escape, mid-drag and with a selection.
- **Zoom.**
  - A pinch and a ⌘-scroll zoom around the cursor: the pixel under the pointer stays put. A plain two-finger scroll pans.
  - ⌘= and ⌘- zoom by 1.25 around the centre. At the top limit (800%), ⌘= beeps.
  - ⌘1 shows natural size: one image pixel per device pixel on the 2x display. From 200% up, image pixels show as crisp squares (nearest-neighbour).
  - ⌘0 fits again, and the fit follows window resizes until the next zoom or pan.
- **Actions.** ⌘S, ⇧⌘S, ⌘C, ⇧⌘C, ⌘U and ⌥⌘U each log one `… is not wired yet` line. Nothing is written, and the close button keeps its unsaved dot.
- **Closing.**
  - On a dirty editor, ⌘W shows the sheet: `Do you want to save the changes made to “<title>”?` and `Your changes will be lost if you don’t save them.`, with Save, Cancel and Don’t Save.
  - Cancel keeps the window. Save logs the stub and keeps the window, because the stub reports failure. ⌘D (Don’t Save) closes it.
  - A clean editor closes at once.
- **Quitting.** Draw a shape, then choose Quit TidyShot from the menu bar.
  - The editor comes forward with the same sheet. Cancel keeps the app running, and Don’t Save quits.
  - With two dirty editors, the sheets come one after the other.
- **Two editors.**
  - Choosing the item again for the same capture brings the same window forward.
  - Take another capture and choose the item: a second window opens 22 pt down and to the right of the first.
- **No tiled layers.** Open the project in Xcode (`open TidyShot.xcodeproj`), run the app, open the editor on the 5K capture, and use Debug > View Debugging > Capture View Hierarchy. The editor's content view holds `BaseImageView` and `CanvasView`, and no `_NSTiledLayer` appears.

- [ ] **Step 10: Commit**

```bash
git add TidyShot/Editor/Window/BaseImageView.swift TidyShot/Editor/Window/CanvasView.swift TidyShot/Editor/Window/EditorWindow.swift TidyShot/Editor/Window/EditorWindowController.swift TidyShot/App/AppCoordinator.swift TidyShot/App/AppDelegate.swift TidyShot/App/StatusMenuController.swift
git commit -m "feat: annotation editor window and canvas"
```

### Task 11: Toolbar, palette and options popovers, persisted editor defaults (TDD for the defaults)

**Files:**
- Create: `TidyShot/Editor/Window/EditorToolbar.swift`
- Create: `TidyShot/Editor/Window/ColorPaletteView.swift`
- Create: `TidyShot/Editor/Window/ToolOptionsView.swift`
- Modify: `TidyShot/Settings/AppSettings.swift` (`Keys` at lines 31-45, `s3Config` at 60-63, `register(defaults:)` at 67-79, the `s3Config` read at 93-94, after `storeS3Config()` at 107-120)
- Modify: `TidyShot/Editor/Window/EditorWindowController.swift` (Task 10: `model` access, two popover properties, `installToolbar()` in `init`)
- Modify: `TidyShot/App/AppCoordinator.swift` (Task 10's `showEditor(recordID:image:)`: the `defaults:` argument)
- Test: `TidyShotTests/AppSettingsTests.swift` (extend `phase2DefaultsAreUploadWithURLOnly` at lines 13-22; two new tests before the closing brace at line 59)

**Interfaces:**
- Consumes:
  - Task 2: `EditorTool.toolbarOrder: [EditorTool]` and `EditorTool.title`, `symbolName`, `tooltip` (the tooltip carries the letter); `EditorPalette.swatches: [RGBA]` (10, in the spec order black, red, orange, yellow, green, teal, blue, purple, pink, white), `EditorPalette.defaultStroke`, `EditorPalette.defaultRedact`, `EditorPalette.lineWidthsPoints: [CGFloat]`; `RedactionDefaults.blurRangePoints` and `blockRangePoints: ClosedRange<CGFloat>`; `RGBA` with its memberwise `init(red:green:blue:alpha:)` and `var cgColor: CGColor`; `EditorDefaults` with its memberwise `init(strokeColor:redactColor:lineWidthPoints:blurRadiusPoints:blockPoints:)` and `static let standard` (red, black, 4, 8, 10); `Annotation` cases `.rectangle(ShapeBox)`, `.arrow(Segment)`, `.redact(Region, fill: RGBA)`, `.blur`, `.pixelate`; `AnnotationDocument.annotation(id:) -> Annotation?`.
  - Task 3: `CanvasTransform.zoom: CGFloat` and `percent(captureScale: CGFloat) -> Int` (100 is natural point size, so zoom `p / 100 / scale` is `p` percent).
  - Task 8: `EditorModel` `tool`, `selection`, `document`, `transform`, `scale`, `strokeColor`, `redactColor`, `lineWidthPoints`, `blurRadiusPoints`, `blockPoints`; `activeColor: RGBA` (the selected annotation's colour, else the default the palette would edit), `EffectParameter` (`.blurRadius`, `.block`), `applyColor(_: RGBA)`, `applyLineWidth(points: CGFloat)`, `applyEffectParameter(_ parameter: EffectParameter, points: CGFloat)`. This task relies on `applyEffectParameter` setting the default named by `parameter` (`blurRadiusPoints` for `.blurRadius`, `blockPoints` for `.block`) and also changing the selection when it is the matching kind (blur for `.blurRadius`, pixelate for `.block`), committed with a coalescing key per id (`"Blur Radius-<id>"` for blur), so a slider drag is one undo step.
  - Task 10: `EditorWindowController.init(model:actions:title:representedURL:cascadeFrom:)`; `@objc` `saveDocument(_:)`, `saveDocumentCopy(_:)`, `copyImage(_:)`, `uploadDocument(_:)`, `uploadDocumentAsNew(_:)`, `zoomToFit(_:)`, `zoomToActualSize(_:)`, `zoomIn(_:)`, `zoomOut(_:)`; `validateUserInterfaceItem(_ item: any NSValidatedUserInterfaceItem) -> Bool`; `CanvasView` takes its `CanvasTool` from `model.tool`, so setting `model.tool` is the whole tool switch; `AppCoordinator.showEditor(recordID:image:)`, which builds `EditorModel(recordID:image:renderer:defaults:)`; `CanvasView.fitToView()`, `zoom(by:around:)` and `zoom(to:around:)`, which apply the transform, clear or set `fitsOnResize` and refresh the views.
  - Existing: the AppSettings pattern (`Keys`, `didSet` writes, `register(defaults:)`, reads in `init`, JSON with a logged encode failure as in `storeS3Config()`, AppSettings.swift:107-120); `let settings = AppSettings.shared` (AppCoordinator.swift:21); the `withObservationTracking` re-registration idiom of `StatusMenuController.updateIcon()` (StatusMenuController.swift:41-50).
- Produces:
  - `AppSettings`: `var editorStrokeColor: RGBA`, `var editorRedactColor: RGBA` (JSON `Data` under `editorStrokeColor` and `editorRedactColor`), `var editorLineWidthPoints: Double` (4), `var editorBlurRadiusPoints: Double` (8), `var editorPixelBlockPoints: Double` (10), and `var editorDefaults: EditorDefaults` (get, and a set that writes all five).
  - `extension NSToolbarItem.Identifier { static let tools, color, toolOptions, zoom, copyImage, save, upload }` (raw values `editor.<name>`).
  - `extension EditorWindowController: NSToolbarDelegate, NSToolbarItemValidation { func installToolbar(); func observeToolbarState(previous: EditorDefaults? = nil); func reflectTool(_ tool: EditorTool); func validateToolbarItem(_ item: NSToolbarItem) -> Bool; @objc func selectToolFromToolbar(_ sender: Any?); @objc func showColorPalette(_ sender: Any?); @objc func showToolOptions(_ sender: Any?); @objc func zoomToPercent(_ sender: NSMenuItem) }`. The tools group is built from `EditorTool.toolbarOrder`. `validateToolbarItem` forwards `.copyImage`, `.save` and `.upload` to `validateUserInterfaceItem(_:)`, so Task 13's gate also drives the toolbar through `validateVisibleItems()`.
  - In EditorWindowController.swift: `let model: EditorModel` (internal), `var colorPopover: NSPopover?`, `var optionsPopover: NSPopover?`. No zoom helper is added: every zoom goes through `CanvasView`.
  - `extension EditorModel { var currentDefaults: EditorDefaults }`. The colour shown comes from Task 8's `activeColor`.
  - `extension RGBA { init?(srgbConverting color: CGColor) }`.
  - `struct ColorPaletteView: View { let model: EditorModel }` and `struct ToolOptionsView: View { let model: EditorModel }`.

- [ ] **Step 1: Write the failing tests**

In `TidyShotTests/AppSettingsTests.swift`, replace lines 13-22:
```swift
    @Test func phase2DefaultsAreUploadWithURLOnly() {
        let settings = AppSettings(defaults: freshDefaults())
        #expect(settings.afterCaptureAction == .upload)
        #expect(settings.alsoCopyImageWhenUploading == false)
        #expect(settings.showOverlay)
        #expect(settings.overlayCorner == .bottomRight)
        #expect(settings.overlayAutoCloseSeconds == 5)
        #expect(settings.historyRetentionDays == 30)
        #expect(settings.s3Config == nil)
    }
```
with:
```swift
    @Test func phase2DefaultsAreUploadWithURLOnly() {
        let settings = AppSettings(defaults: freshDefaults())
        #expect(settings.afterCaptureAction == .upload)
        #expect(settings.alsoCopyImageWhenUploading == false)
        #expect(settings.showOverlay)
        #expect(settings.overlayCorner == .bottomRight)
        #expect(settings.overlayAutoCloseSeconds == 5)
        #expect(settings.historyRetentionDays == 30)
        #expect(settings.s3Config == nil)
        // Phase 4: a red stroke, black redactions, 4 pt lines, an 8 pt blur and 10 pt pixel blocks.
        #expect(settings.editorStrokeColor == EditorPalette.defaultStroke)
        #expect(settings.editorRedactColor == EditorPalette.defaultRedact)
        #expect(settings.editorLineWidthPoints == 4)
        #expect(settings.editorBlurRadiusPoints == 8)
        #expect(settings.editorPixelBlockPoints == 10)
        #expect(settings.editorDefaults == EditorDefaults.standard)
    }
```

Then add these two tests after `storedTemplatesLoseTheRemovedAppToken()`, before the struct's closing brace (line 59):
```swift

    /// The five editor values persist under the keys spec 2.6 names, and a second instance (the
    /// next launch) reads them back.
    @Test func editorDefaultsRoundTripThroughSecondInstance() {
        let defaults = freshDefaults()
        let chosen = EditorDefaults(strokeColor: RGBA(red: 0, green: 0.5, blue: 1, alpha: 1),
                                    redactColor: RGBA(red: 1, green: 1, blue: 1, alpha: 1),
                                    lineWidthPoints: 12, blurRadiusPoints: 20, blockPoints: 6)
        let first = AppSettings(defaults: defaults)
        first.editorDefaults = chosen
        #expect(first.editorDefaults == chosen)
        #expect(defaults.double(forKey: "editorLineWidthPoints") == 12)
        #expect(defaults.double(forKey: "editorBlurRadiusPoints") == 20)
        #expect(defaults.double(forKey: "editorPixelBlockPoints") == 6)

        let second = AppSettings(defaults: defaults)
        #expect(second.editorDefaults == chosen)

        // One value set on its own is stored too.
        second.editorBlurRadiusPoints = 4
        #expect(AppSettings(defaults: defaults).editorDefaults.blurRadiusPoints == 4)
    }

    /// Colours are stored as JSON `Data` that decodes as `RGBA`. Nothing is written until a colour
    /// is set, and a value that does not decode falls back to the default.
    @Test func rgbaStoredAsJSON() throws {
        let defaults = freshDefaults()
        let teal = RGBA(red: 0.2, green: 0.7, blue: 0.7, alpha: 1)
        let settings = AppSettings(defaults: defaults)
        settings.editorStrokeColor = teal
        let stored = try #require(defaults.data(forKey: "editorStrokeColor"))
        #expect(try JSONDecoder().decode(RGBA.self, from: stored) == teal)
        #expect(defaults.data(forKey: "editorRedactColor") == nil)

        defaults.set(Data("not json".utf8), forKey: "editorRedactColor")
        #expect(AppSettings(defaults: defaults).editorRedactColor == EditorPalette.defaultRedact)
    }
```

- [ ] **Step 2: Run the tests to verify they fail**

Run:
```bash
xcodegen generate && xcodebuild test -project TidyShot.xcodeproj -scheme TidyShot -destination 'platform=macOS' -derivedDataPath .build 2>&1 | grep -E "Test run with|error:|TEST"
```
Expected: compile errors, among them `value of type 'AppSettings' has no member 'editorStrokeColor'`, then `** TEST FAILED **`.

- [ ] **Step 3: Persist the editor defaults**

In `TidyShot/Settings/AppSettings.swift`:

Replace (lines 43-45):
```swift
        static let historyRetentionDays = "historyRetentionDays"
        static let s3Config = "s3DestinationConfig"
    }
```
with:
```swift
        static let historyRetentionDays = "historyRetentionDays"
        static let s3Config = "s3DestinationConfig"
        static let editorStrokeColor = "editorStrokeColor"
        static let editorRedactColor = "editorRedactColor"
        static let editorLineWidthPoints = "editorLineWidthPoints"
        static let editorBlurRadiusPoints = "editorBlurRadiusPoints"
        static let editorPixelBlockPoints = "editorPixelBlockPoints"
    }
```

Replace (lines 60-63):
```swift
    /// Nil until the Upload tab has been saved once. Stored as JSON.
    var s3Config: S3DestinationConfig? {
        didSet { storeS3Config() }
    }
```
with:
```swift
    /// Nil until the Upload tab has been saved once. Stored as JSON.
    var s3Config: S3DestinationConfig? {
        didSet { storeS3Config() }
    }
    /// The annotation editor's last colours (sRGB, stored as JSON) and sizes in points. An editor
    /// reads them once, as `editorDefaults`, when it opens. There is no Settings tab for them.
    var editorStrokeColor: RGBA { didSet { storeColor(editorStrokeColor, forKey: Keys.editorStrokeColor) } }
    var editorRedactColor: RGBA { didSet { storeColor(editorRedactColor, forKey: Keys.editorRedactColor) } }
    var editorLineWidthPoints: Double { didSet { defaults.set(editorLineWidthPoints, forKey: Keys.editorLineWidthPoints) } }
    var editorBlurRadiusPoints: Double { didSet { defaults.set(editorBlurRadiusPoints, forKey: Keys.editorBlurRadiusPoints) } }
    var editorPixelBlockPoints: Double { didSet { defaults.set(editorPixelBlockPoints, forKey: Keys.editorPixelBlockPoints) } }

    /// The five editor values as one value. Setting it writes all five keys.
    var editorDefaults: EditorDefaults {
        get {
            EditorDefaults(strokeColor: editorStrokeColor, redactColor: editorRedactColor,
                           lineWidthPoints: CGFloat(editorLineWidthPoints),
                           blurRadiusPoints: CGFloat(editorBlurRadiusPoints),
                           blockPoints: CGFloat(editorPixelBlockPoints))
        }
        set {
            editorStrokeColor = newValue.strokeColor
            editorRedactColor = newValue.redactColor
            editorLineWidthPoints = Double(newValue.lineWidthPoints)
            editorBlurRadiusPoints = Double(newValue.blurRadiusPoints)
            editorPixelBlockPoints = Double(newValue.blockPoints)
        }
    }
```

Replace (lines 78-79):
```swift
            Keys.historyRetentionDays: 30,
        ])
```
with:
```swift
            Keys.historyRetentionDays: 30,
            Keys.editorLineWidthPoints: Double(EditorDefaults.standard.lineWidthPoints),
            Keys.editorBlurRadiusPoints: Double(EditorDefaults.standard.blurRadiusPoints),
            Keys.editorPixelBlockPoints: Double(EditorDefaults.standard.blockPoints),
        ])
```

Replace (lines 93-94):
```swift
        let storedConfig = defaults.data(forKey: Keys.s3Config)
        s3Config = storedConfig.flatMap { try? JSONDecoder().decode(S3DestinationConfig.self, from: $0) }
```
with:
```swift
        let storedConfig = defaults.data(forKey: Keys.s3Config)
        s3Config = storedConfig.flatMap { try? JSONDecoder().decode(S3DestinationConfig.self, from: $0) }
        // Colours are not registered: a missing or unreadable value means the default.
        editorStrokeColor = Self.storedColor(defaults.data(forKey: Keys.editorStrokeColor)) ?? EditorDefaults.standard.strokeColor
        editorRedactColor = Self.storedColor(defaults.data(forKey: Keys.editorRedactColor)) ?? EditorDefaults.standard.redactColor
        editorLineWidthPoints = defaults.double(forKey: Keys.editorLineWidthPoints)
        editorBlurRadiusPoints = defaults.double(forKey: Keys.editorBlurRadiusPoints)
        editorPixelBlockPoints = defaults.double(forKey: Keys.editorPixelBlockPoints)
```
These assignments come before the migration block at line 96, because `storeS3Config()` there needs every stored property set.

After `storeS3Config()` (ends at line 120), add:
```swift

    /// An `RGBA` written by `storeColor(_:forKey:)`, or nil when there is none or it does not decode.
    private static func storedColor(_ data: Data?) -> RGBA? {
        data.flatMap { try? JSONDecoder().decode(RGBA.self, from: $0) }
    }

    /// Writes `color` as JSON. An encoding failure is logged and leaves the stored value as it was.
    private func storeColor(_ color: RGBA, forKey key: String) {
        do {
            defaults.set(try JSONEncoder().encode(color), forKey: key)
        } catch {
            NSLog("An editor colour could not be encoded, so the stored one is kept: \(error.localizedDescription)")
        }
    }
```

- [ ] **Step 4: Run the tests to verify they pass**

Run:
```bash
xcodegen generate && xcodebuild test -project TidyShot.xcodeproj -scheme TidyShot -destination 'platform=macOS' -derivedDataPath .build 2>&1 | grep -E "Test run with|error:|TEST"
```
Expected: no `error:` lines, and `Test run with 318 tests in 45 suites passed`.

- [ ] **Step 5: Write the colour palette**

`TidyShot/Editor/Window/ColorPaletteView.swift`:
```swift
import CoreGraphics
import SwiftUI

/// The colour popover (spec 2.6, Palette and options): ten swatches and a custom colour. A pick goes
/// through `EditorModel.applyColor(_:)`, which sets the active tool's colour and recolours the
/// selected annotation. No background: the popover's glass is the backdrop.
struct ColorPaletteView: View {
    let model: EditorModel

    /// Names for `EditorPalette.swatches`, in the spec's order, for help tags and VoiceOver.
    private static let names = ["Black", "Red", "Orange", "Yellow", "Green", "Teal", "Blue", "Purple", "Pink", "White"]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(22), spacing: 8), count: 5), spacing: 8) {
                ForEach(Array(EditorPalette.swatches.enumerated()), id: \.offset) { index, swatch in
                    swatchButton(swatch, name: index < Self.names.count ? Self.names[index] : "Colour \(index + 1)")
                }
            }
            ColorPicker("Custom", selection: customColor, supportsOpacity: false)
        }
        .padding(12)
    }

    private func swatchButton(_ swatch: RGBA, name: String) -> some View {
        let isCurrent = model.activeColor == swatch
        return Button {
            model.applyColor(swatch)
        } label: {
            Circle()
                .fill(Color(cgColor: swatch.cgColor))
                .overlay(Circle().strokeBorder(.separator))  // so white shows
                .padding(3)
                .overlay(Circle().strokeBorder(Color.accentColor, lineWidth: 2).opacity(isCurrent ? 1 : 0))
                .frame(width: 22, height: 22)
        }
        .buttonStyle(.plain)
        .help(name)
        .accessibilityLabel(name)
        .accessibilityAddTraits(isCurrent ? .isSelected : [])
    }

    /// The colour panel can hand back Display P3 or grey colours; they are converted to sRGB.
    private var customColor: Binding<CGColor> {
        Binding(get: { model.activeColor.cgColor },
                set: { color in
                    if let rgba = RGBA(srgbConverting: color) { model.applyColor(rgba) }
                })
    }
}

extension RGBA {
    /// `color` in sRGB with each component clamped to 0...1, or nil when it has no RGB form (a
    /// pattern). The picker has no opacity, so alpha is always 1.
    init?(srgbConverting color: CGColor) {
        guard let sRGB = CGColorSpace(name: CGColorSpace.sRGB),
              let converted = color.converted(to: sRGB, intent: .defaultIntent, options: nil),
              let components = converted.components, components.count >= 3 else { return nil }
        let clamped = components.prefix(3).map { Double(min(max($0, 0), 1)) }
        self.init(red: clamped[0], green: clamped[1], blue: clamped[2], alpha: 1)
    }
}
```
The colour shown and edited is `EditorModel.activeColor` (Task 8), so this file holds no copy of that rule and 4b's new kinds need no change here.

- [ ] **Step 6: Write the tool options**

`TidyShot/Editor/Window/ToolOptionsView.swift`:
```swift
import SwiftUI

/// The options popover (spec 2.6, Palette and options): line width, blur radius and pixel block.
/// Each control applies live through `EditorModel`, which commits a selected annotation under a
/// coalescing key, so one slider drag is one undo step. Only the slider for the effect in play is
/// enabled: the selected blur or pixelate, else the active Blur or Pixelate tool. A selected
/// annotation of another kind does not decide it, so with a rectangle selected the active effect
/// tool's slider still works and sets only the default.
struct ToolOptionsView: View {
    let model: EditorModel

    var body: some View {
        Form {
            Picker("Line width", selection: lineWidth) {
                ForEach(EditorPalette.lineWidthsPoints, id: \.self) { width in
                    Text("\(Int(width))").tag(width)
                }
            }
            .pickerStyle(.segmented)
            .help("Keys 1 to 6")
            LabeledContent("Blur radius") {
                HStack {
                    Slider(value: blurRadius, in: RedactionDefaults.blurRangePoints, step: 1)
                    readout(model.blurRadiusPoints)
                }
            }
            .disabled(effectTool != .blur)
            LabeledContent("Pixel block") {
                HStack {
                    Slider(value: block, in: RedactionDefaults.blockRangePoints, step: 1)
                    readout(model.blockPoints)
                }
            }
            .disabled(effectTool != .pixelate)
        }
        .formStyle(.columns)
        .padding(12)
        .frame(width: 300)
    }

    private func readout(_ points: CGFloat) -> some View {
        Text("\(Int(points)) pt")
            .monospacedDigit()
            .frame(width: 40, alignment: .trailing)
    }

    /// The effect the sliders act on: the selected annotation's kind, else the active tool's.
    private var effectTool: EditorTool? {
        if let id = model.selection, let annotation = model.document.annotation(id: id) {
            switch annotation {
            case .blur: return .blur
            case .pixelate: return .pixelate
            default: break
            }
        }
        return model.tool == .blur || model.tool == .pixelate ? model.tool : nil
    }

    private var lineWidth: Binding<CGFloat> {
        Binding(get: { model.lineWidthPoints }, set: { model.applyLineWidth(points: $0) })
    }

    private var blurRadius: Binding<CGFloat> {
        Binding(get: { model.blurRadiusPoints }, set: { model.applyEffectParameter(.blurRadius, points: $0) })
    }

    private var block: Binding<CGFloat> {
        Binding(get: { model.blockPoints }, set: { model.applyEffectParameter(.block, points: $0) })
    }
}
```

- [ ] **Step 7: Write the toolbar**

`TidyShot/Editor/Window/EditorToolbar.swift`:
```swift
import AppKit
import Observation
import SwiftUI

extension NSToolbarItem.Identifier {
    static let tools = NSToolbarItem.Identifier("editor.tools")
    static let color = NSToolbarItem.Identifier("editor.color")
    static let toolOptions = NSToolbarItem.Identifier("editor.toolOptions")
    static let zoom = NSToolbarItem.Identifier("editor.zoom")
    static let copyImage = NSToolbarItem.Identifier("editor.copyImage")
    static let save = NSToolbarItem.Identifier("editor.save")
    static let upload = NSToolbarItem.Identifier("editor.upload")
}

extension EditorModel {
    /// This editor's colours and sizes, in the shape AppSettings stores.
    var currentDefaults: EditorDefaults {
        EditorDefaults(strokeColor: strokeColor, redactColor: redactColor, lineWidthPoints: lineWidthPoints,
                       blurRadiusPoints: blurRadiusPoints, blockPoints: blockPoints)
    }
}

/// The editor toolbar (spec 2.6, Window): `NSToolbar(identifier: "AnnotationEditor")`, icon only,
/// not customisable. Its state follows the model through Observation, so letter keys, digit keys
/// and pinch zoom show here without the canvas knowing about the toolbar. Liquid Glass comes free:
/// no custom backgrounds.
extension EditorWindowController: NSToolbarDelegate, NSToolbarItemValidation {
    private static let itemIdentifiers: [NSToolbarItem.Identifier] = [
        .tools, .space, .color, .toolOptions, .flexibleSpace, .zoom, .copyImage, .save, .upload,
    ]

    /// Called once from `init`, after `super.init(window:)` and before the window is placed.
    func installToolbar() {
        let toolbar = NSToolbar(identifier: "AnnotationEditor")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = false
        window?.toolbar = toolbar
        observeToolbarState()
    }

    // MARK: NSToolbarDelegate

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        Self.itemIdentifiers
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        Self.itemIdentifiers
    }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
                 willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        switch itemIdentifier {
        case .tools:
            return makeToolsItem()
        case .color:
            return makeButtonItem(.color, label: "Colour", toolTip: "Colour",
                                  image: swatchImage(model.activeColor), action: #selector(showColorPalette(_:)))
        case .toolOptions:
            return makeButtonItem(.toolOptions, label: "Options", toolTip: "Line width, blur radius and pixel block",
                                  image: symbol("slider.horizontal.3", "Options"), action: #selector(showToolOptions(_:)))
        case .zoom:
            return makeZoomItem()
        case .copyImage:
            return makeButtonItem(.copyImage, label: "Copy", toolTip: "Copy the image (⌘C)",
                                  image: symbol("doc.on.doc", "Copy"), action: #selector(copyImage(_:)))
        case .save:
            return makeMenuItem(.save, label: "Save", toolTip: "Save (⌘S)",
                                image: symbol("square.and.arrow.down", "Save"), action: #selector(saveDocument(_:)),
                                entries: [("Save Copy…", #selector(saveDocumentCopy(_:)))])
        case .upload:
            let item = makeMenuItem(.upload, label: "Upload", toolTip: "Upload (⌘U)",
                                    image: symbol("icloud.and.arrow.up", "Upload"), action: #selector(uploadDocument(_:)),
                                    entries: [("Upload", #selector(uploadDocument(_:))),
                                              ("Upload as New", #selector(uploadDocumentAsNew(_:)))])
            item.style = .prominent
            return item
        default:
            return nil
        }
    }

    // MARK: Validation

    /// Copy, Save and Upload follow the same answer as their shortcuts (Task 13's gate); the rest
    /// are always enabled.
    func validateToolbarItem(_ item: NSToolbarItem) -> Bool {
        switch item.itemIdentifier {
        case .copyImage, .save, .upload: validateUserInterfaceItem(item)
        default: true
        }
    }

    // MARK: Following the model

    /// Re-registers on every change, as `StatusMenuController.updateIcon()` does: Observation calls
    /// `onChange` once, before the change, so the update runs in a scheduled task. `previous` is the
    /// model's defaults at the last registration, so only what this editor changed is stored and two
    /// open editors do not overwrite each other's choices.
    func observeToolbarState(previous: EditorDefaults? = nil) {
        let defaults = model.currentDefaults
        if let previous { storeChangedDefaults(from: previous, to: defaults) }
        let state = withObservationTracking {
            _ = model.currentDefaults
            return (tool: model.tool, color: model.activeColor,
                    percent: model.transform.percent(captureScale: model.scale))
        } onChange: { [weak self] in
            Task { @MainActor in self?.observeToolbarState(previous: defaults) }
        }
        reflectTool(state.tool)
        reflectColor(state.color)
        reflectZoom(percent: state.percent)
    }

    /// Keeps the group's selection in step when a letter key changed the tool. Setting
    /// `selectedIndex` does not send the action, so there is no loop.
    func reflectTool(_ tool: EditorTool) {
        guard let group = toolbarItem(.tools) as? NSToolbarItemGroup,
              let index = EditorTool.toolbarOrder.firstIndex(of: tool), group.selectedIndex != index else { return }
        group.selectedIndex = index
    }

    private func reflectColor(_ color: RGBA) {
        toolbarItem(.color)?.image = swatchImage(color)
    }

    /// A pull-down shows its first item's title, which `setTitle(_:)` sets.
    private func reflectZoom(percent: Int) {
        (toolbarItem(.zoom)?.view as? NSPopUpButton)?.setTitle("\(percent) %")
    }

    private func storeChangedDefaults(from old: EditorDefaults, to new: EditorDefaults) {
        let settings = AppSettings.shared
        if new.strokeColor != old.strokeColor { settings.editorStrokeColor = new.strokeColor }
        if new.redactColor != old.redactColor { settings.editorRedactColor = new.redactColor }
        if new.lineWidthPoints != old.lineWidthPoints { settings.editorLineWidthPoints = Double(new.lineWidthPoints) }
        if new.blurRadiusPoints != old.blurRadiusPoints { settings.editorBlurRadiusPoints = Double(new.blurRadiusPoints) }
        if new.blockPoints != old.blockPoints { settings.editorPixelBlockPoints = Double(new.blockPoints) }
    }

    // MARK: Actions

    /// The group sends this from its segments and from its collapsed menu alike.
    @objc func selectToolFromToolbar(_ sender: Any?) {
        guard let group = toolbarItem(.tools) as? NSToolbarItemGroup,
              EditorTool.toolbarOrder.indices.contains(group.selectedIndex) else { return }
        model.tool = EditorTool.toolbarOrder[group.selectedIndex]
    }

    @objc func showColorPalette(_ sender: Any?) {
        colorPopover = showPopover(ColorPaletteView(model: model), from: .color)
    }

    @objc func showToolOptions(_ sender: Any?) {
        optionsPopover = showPopover(ToolOptionsView(model: model), from: .toolOptions)
    }

    /// 50 %, 200 % and 400 % from the zoom pop-up: `tag` percent of natural size, around the
    /// view centre, through `CanvasView` like ⌘=, so the canvas stops refitting on resize and
    /// redraws at once.
    @objc func zoomToPercent(_ sender: NSMenuItem) {
        canvasView.zoom(to: CGFloat(sender.tag) / 100 / model.scale)
    }

    /// One popover at a time. `.transient` closes it on a click elsewhere; values apply live, so
    /// there is nothing to confirm. `show(relativeTo:)` anchors to the item, or to the overflow
    /// chevron when the item has moved into the overflow menu. The item is looked up by identifier
    /// because the overflow menu sends an `NSMenuItem`.
    private func showPopover(_ content: some View, from identifier: NSToolbarItem.Identifier) -> NSPopover? {
        colorPopover?.close()
        optionsPopover?.close()
        guard let item = toolbarItem(identifier) else { return nil }
        let host = NSHostingController(rootView: content)
        host.sizingOptions = .preferredContentSize
        let popover = NSPopover()
        popover.behavior = .transient
        popover.contentViewController = host
        popover.show(relativeTo: item)
        return popover
    }

    // MARK: Items

    private func makeToolsItem() -> NSToolbarItem {
        let tools = EditorTool.toolbarOrder
        let group = NSToolbarItemGroup(
            itemIdentifier: .tools,
            images: tools.map { NSImage(systemSymbolName: $0.symbolName, accessibilityDescription: $0.title) ?? NSImage() },
            selectionMode: .selectOne, labels: tools.map(\.title),
            target: self, action: #selector(selectToolFromToolbar(_:)))
        group.label = "Tools"
        group.controlRepresentation = .automatic  // segments, or a menu when the window is narrow
        for (item, tool) in zip(group.subitems, tools) { item.toolTip = tool.tooltip }
        group.selectedIndex = tools.firstIndex(of: model.tool) ?? 0
        return group
    }

    private func makeButtonItem(_ identifier: NSToolbarItem.Identifier, label: String, toolTip: String,
                                image: NSImage?, action: Selector) -> NSToolbarItem {
        let item = NSToolbarItem(itemIdentifier: identifier)
        item.label = label
        item.toolTip = toolTip
        item.image = image
        item.target = self
        item.action = action
        return item
    }

    /// The button runs `action`; the indicator opens `entries`, which autovalidate through
    /// `validateUserInterfaceItem(_:)`.
    private func makeMenuItem(_ identifier: NSToolbarItem.Identifier, label: String, toolTip: String, image: NSImage?,
                              action: Selector, entries: [(String, Selector)]) -> NSMenuToolbarItem {
        let item = NSMenuToolbarItem(itemIdentifier: identifier)
        item.label = label
        item.toolTip = toolTip
        item.image = image
        item.target = self
        item.action = action
        let menu = NSMenu(title: label)
        for (title, selector) in entries {
            let entry = NSMenuItem(title: title, action: selector, keyEquivalent: "")
            entry.target = self
            menu.addItem(entry)
        }
        item.menu = menu
        return item
    }

    private func makeZoomItem() -> NSToolbarItem {
        let popUp = NSPopUpButton(frame: .zero, pullsDown: true)
        popUp.menu = zoomMenu(withTitleItem: true)
        popUp.widthAnchor.constraint(equalToConstant: 84).isActive = true  // the title changes; the width does not
        let item = NSToolbarItem(itemIdentifier: .zoom)
        item.label = "Zoom"
        item.toolTip = "Zoom"
        item.view = popUp
        let form = NSMenuItem(title: "Zoom", action: nil, keyEquivalent: "")
        form.submenu = zoomMenu(withTitleItem: false)
        item.menuFormRepresentation = form
        return item
    }

    /// Fit, 50 %, 100 %, 200 % and 400 %. A pull-down's first item is its title, so the pop-up
    /// adds one showing the current percent. Zoom is always available.
    private func zoomMenu(withTitleItem: Bool) -> NSMenu {
        let menu = NSMenu(title: "Zoom")
        menu.autoenablesItems = false
        if withTitleItem {
            menu.addItem(withTitle: "\(model.transform.percent(captureScale: model.scale)) %", action: nil, keyEquivalent: "")
        }
        for (title, selector, tag) in [("Fit", #selector(zoomToFit(_:)), 0),
                                       ("50 %", #selector(zoomToPercent(_:)), 50),
                                       ("100 %", #selector(zoomToActualSize(_:)), 100),
                                       ("200 %", #selector(zoomToPercent(_:)), 200),
                                       ("400 %", #selector(zoomToPercent(_:)), 400)] {
            let entry = NSMenuItem(title: title, action: selector, keyEquivalent: "")
            entry.target = self
            entry.tag = tag
            menu.addItem(entry)
        }
        return menu
    }

    // MARK: Helpers

    private func toolbarItem(_ identifier: NSToolbarItem.Identifier) -> NSToolbarItem? {
        window?.toolbar?.items.first { $0.itemIdentifier == identifier }
    }

    private func symbol(_ name: String, _ description: String) -> NSImage? {
        NSImage(systemSymbolName: name, accessibilityDescription: description)
    }

    /// The current colour as a filled circle with a hairline edge, so white shows on a light toolbar.
    private func swatchImage(_ color: RGBA) -> NSImage {
        let image = NSImage(size: NSSize(width: 16, height: 16), flipped: false) { rect in
            let circle = NSBezierPath(ovalIn: rect.insetBy(dx: 1, dy: 1))
            NSColor(cgColor: color.cgColor)?.setFill()
            circle.fill()
            NSColor.separatorColor.setStroke()
            circle.lineWidth = 1
            circle.stroke()
            return true
        }
        image.accessibilityDescription = "Colour"
        return image
    }
}
```

- [ ] **Step 8: Install the toolbar and read the stored defaults**

In `TidyShot/Editor/Window/EditorWindowController.swift` (Task 10):
- The model property is `let model: EditorModel`, internal, because EditorToolbar.swift reads it. If Task 10 declared it `private`, drop `private`.
- Add, next to the other stored properties:
  ```swift
      /// The toolbar's popovers (EditorToolbar.swift), kept so only one is shown at a time.
      var colorPopover: NSPopover?
      var optionsPopover: NSPopover?
  ```
- In `init(model:actions:title:representedURL:cascadeFrom:)`, call `installToolbar()` after `super.init(window:)` and the window setup (style mask, `toolbarStyle = .unified`), and before the frame is placed with `EditorWindowGeometry.cascaded(...)`, so the toolbar's height is in the frame from the start.
- Zoom: `zoomIn(_:)` and `zoomOut(_:)` already call `canvasView.zoom(by:)` (Task 10), so leave them alone. Add no controller `zoom(by:)` helper and do not compute `zoomed(...)` or `snapped(...)` in the controller: every zoom goes through `CanvasView`, whose `apply(_, fits: false)` clears `fitsOnResize` (so a later window resize keeps the chosen zoom) and refreshes the views at once. `zoomToPercent(_:)` calls `canvasView.zoom(to:)`. If Task 10 names the controller's canvas property differently from `canvasView`, use its name.

In `TidyShot/App/AppCoordinator.swift`, in `showEditor(recordID:image:)` (Task 10, under `// MARK: Editor`; `openEditor(recordID:)` only loads and decodes), the `EditorModel(recordID:image:renderer:defaults:)` call passes `defaults: settings.editorDefaults` (`settings` is `AppSettings.shared`, AppCoordinator.swift:21) in place of `defaults: .standard`. This is the one read spec 2.6 asks for: once, when an editor opens.

- [ ] **Step 9: Build, run the tests, and check by hand**

Run:
```bash
xcodegen generate && xcodebuild test -project TidyShot.xcodeproj -scheme TidyShot -destination 'platform=macOS' -derivedDataPath .build 2>&1 | grep -E "Test run with|error:|TEST"
```
Expected: no `error:` lines, and `Test run with 318 tests in 45 suites passed`.

Then:
```bash
xcodebuild -project TidyShot.xcodeproj -scheme TidyShot -configuration Debug -derivedDataPath .build build -quiet && open .build/Build/Products/Debug/TidyShot.app
```
Capture an area, then choose `Annotate Last Capture (debug)` from the status menu. Expected:
1. The glass toolbar renders, left to right: the tools group (Select, Redact, Pixelate, Blur, Rectangle, Arrow), a space, the colour circle (red), Options, then on the right the zoom pop-up showing the fit percent, Copy, Save with a menu indicator, and a tinted, prominent Upload with a menu indicator. Hovering a tool shows its tooltip with its letter.
2. Narrow the window: the tools group collapses to a menu listing the tool names; narrower still, items move to the overflow chevron, and Colour and Options opened from there still show their popovers.
3. With the canvas focused, press D, X, B, R, A and V: the group's selection follows each key. Click Rectangle in the group: the next drag draws a rectangle, and letter keys still work afterwards.
4. Colour: the popover shows ten swatches in the order black, red, orange, yellow, green, teal, blue, purple, pink, white, then Custom. With Rectangle active, click blue: the toolbar circle turns blue and the next rectangle is blue. Select a redaction (V, click): the circle shows its fill; click white: the redaction turns white; ⌘Z once restores it. Click Custom and pick a colour in the colour panel: the selection and the circle follow. If clicking into the colour panel closes the popover and the pick stops applying, stop and ask: spec 2.6 sets the popover to `.transient`.
5. Options: with B active, Blur radius is enabled and Pixel block is not; with X, the reverse; with Rectangle active, neither. Draw a rectangle (it stays selected), then press B: Blur radius is still enabled, and moving it changes only the default, not the rectangle. Select a blur and drag its slider: the tile follows during the drag; ⌘Z once restores the original radius (one undo step). Keys 1 to 6 move the Line width control while the popover is open.
6. Zoom: the pop-up offers Fit, 50 %, 100 %, 200 % and 400 %, and each works; its title follows a pinch, ⌘= and ⌘-.
7. Copy, Save, Save Copy…, Upload and Upload as New each reach their controller method (Task 10's log lines in Console until Tasks 12 to 15).
8. Choose green, line width 8, blur 12 and block 20, close the editor and open another: it starts with those. Quit and relaunch: still those. With two editors open, change the colour in one and the line width in the other, then open a third: it has both changes.

- [ ] **Step 10: Commit**

```bash
git add TidyShot/Editor/Window/EditorToolbar.swift TidyShot/Editor/Window/ColorPaletteView.swift TidyShot/Editor/Window/ToolOptionsView.swift TidyShot/Editor/Window/EditorWindowController.swift TidyShot/Settings/AppSettings.swift TidyShot/App/AppCoordinator.swift TidyShotTests/AppSettingsTests.swift
git commit -m "feat: editor toolbar, colour palette and tool options"
```

### Task 12: One save path: persist() refactor, Save Copy, Copy and clipboard ownership

**Files:**
- Create: `TidyShot/Editor/Persistence/EditorNaming.swift`
- Create: `TidyShot/Editor/Persistence/EditorClipboard.swift`
- Create: `TidyShotTests/EditorNamingTests.swift`
- Create: `TidyShotTests/EditorClipboardTests.swift`
- Modify: `TidyShot/Output/Pasteboard.swift` (all five `copy` methods, lines 6-70)
- Modify: `TidyShot/App/AppCoordinator.swift` (`UploadLane` 11-15, stored properties 48-50, `save(_:)` 152-227, `writeFile`/`writePendingFile`/`keepOnClipboard` 238-275, and `editorActions(for:)` under `// MARK: Editor` from Task 10)
- Test: `TidyShotTests/EditorNamingTests.swift`, `TidyShotTests/EditorClipboardTests.swift`

Line numbers are those at f4541da. Task 10 adds code to AppCoordinator.swift, so find each block by its text.

**Interfaces:**
- Consumes:
  - `nonisolated struct ScaledImage: Sendable { let image: CGImage; let scale: CGFloat }` and `extension CaptureResult { var scaled: ScaledImage }` (Task 2).
  - `struct EditorActions { var save, saveCopy: (ScaledImage) async -> Bool; var copy: (ScaledImage) async -> Void; var upload: (ScaledImage, _ asNew: Bool) async -> Bool }` (Task 10), built with logging stubs in `editorActions(for recordID:)` (Task 10), which `showEditor(recordID:image:)` passes to `EditorWindowController`.
  - `EditorWindowController` (Task 10): `saveDocumentCopy(_:)` awaits `model.renderExport()`, passes the image to `actions.saveCopy` and calls `model.markSaved()` when that returns true; `copyImage(_:)` passes the export to `actions.copy`; `copy(_:)` calls `copyImage(_:)`. `EditorModel.renderExport() async -> ScaledImage?` and `markSaved()` come from Task 8.
  - Existing `private` members of AppCoordinator: `notifier` (27), `warnUploadNotConfiguredOnce(_ message: String)` (232), `writeFile(_ png: Data, result: CaptureResult, alreadyOnClipboard: Bool) async -> URL?` (241), `writePendingFile(_ png: Data, id: UUID, result: CaptureResult, alreadyOnClipboard: Bool) -> URL?` (260), `keepOnClipboard(_ result: CaptureResult, png: Data, alreadyOnClipboard: Bool)` (271), `makeThumbnail(from image: CGImage, for id: UUID)` (281), `showOverlay(for record: CaptureRecord, image: CGImage?, scale: CGFloat)` (302) and `startUpload(recordID: UUID, data: Data, destination: S3Destination)` (376). The internal `makeDestination() -> S3Destination?` (317).
  - The `copyImageNow` decision in `save(_:)` (AppCoordinator.swift:171-179): with a destination, `alsoCopyImageWhenUploading`; an upload action with no destination, true; Save mode, `copyImageToClipboard`.
  - `SaveLocation.write(_ data: Data, baseName: String, ext: String, in folder: URL) throws -> URL` (SaveLocation.swift:54), which makes the name unique with `FileNamer.uniqueURL(baseName:ext:in:fileManager:)` (FileNamer.swift:49).
  - `ImageEncoder.pngData(from: CGImage, scale: CGFloat) throws -> Data` (ImageEncoder.swift:21) and `nonisolated static func Pasteboard.tiffData(of: CGImage, scale: CGFloat) -> Data?` (Pasteboard.swift:47).
  - `Notifier.notify(title:body:)` and `notifyError(_:title:)` (Notifier.swift:43, 35), and `HistoryStore.record(id:) -> CaptureRecord?` (HistoryStore.swift:80).
- Produces:
  - Pasteboard, each `@discardableResult` and returning `NSPasteboard.general.changeCount` read after the write:
    - `static func copy(image: CGImage, pngData: Data, scale: CGFloat) -> Int`
    - `static func copy(pngData: Data, tiffData: Data?) -> Int`
    - `static func copy(image: CGImage, scale: CGFloat) -> Int`
    - `static func copy(fileURL: URL) -> Int`
    - `static func copy(url: URL) -> Int`
  - `nonisolated enum EditorNaming { static func copyBaseName(for record: CaptureRecord?) -> String? }`.
  - `nonisolated enum EditorClipboard { struct Owner: Equatable, Sendable { let recordID: UUID; let changeCount: Int }; static func shouldReplace(owner: Owner?, recordID: UUID, currentChangeCount: Int) -> Bool }`.
  - In AppCoordinator (all `private`):
    - `struct PersistOptions { var baseName: String?; var alreadyOnClipboard: Bool; var playsSound: Bool }`.
    - `func persist(png: Data, image: ScaledImage, action: AfterCaptureAction, destination: S3Destination?, options: PersistOptions) async -> CaptureRecord?`.
    - `func writeFile(_ png: Data, image: ScaledImage, baseName: String?, alreadyOnClipboard: Bool) async -> URL?`, `func writePendingFile(_ png: Data, id: UUID, image: ScaledImage, alreadyOnClipboard: Bool) -> URL?` and `func keepOnClipboard(_ image: ScaledImage, png: Data, alreadyOnClipboard: Bool)`.
    - `@ObservationIgnored var clipboardOwner: EditorClipboard.Owner?`. `save(_:)` sets it whenever `copyImageNow` is true (all three cases); `editorCopy` and `replaceClipboardIfStillOriginal` set it too. The `keepOnClipboard` failure paths do not, because no record exists for that image.
    - `func replaceClipboardIfStillOriginal(recordID: UUID, png: Data, image: ScaledImage) async`. Task 13's `applyLocalEdit` calls it.
    - `func editorSaveCopy(of recordID: UUID, image: ScaledImage) async -> Bool`. Task 13 adds its write-time refusal check at the top.
    - `func editorCopy(recordID: UUID, image: ScaledImage) async`.
    - `editorActions(for recordID:)` (Task 10) holds `saveCopy` and `copy` closures that call the two methods above. `save` and `upload` keep Task 10's stubs until Tasks 13 and 15.

- [ ] **Step 1: Write the failing tests**

`TidyShotTests/EditorNamingTests.swift`:
```swift
import Foundation
import Testing
@testable import TidyShot

struct EditorNamingTests {
    func record(fileURL: URL?, temporary: Bool = false) -> CaptureRecord {
        CaptureRecord(fileURL: fileURL, fileIsTemporary: temporary, pixelWidth: 64, pixelHeight: 48, appName: nil)
    }

    /// Only the extension goes; the dots in the time stay.
    @Test func stemPlusEditedForSaveFolderFile() {
        let file = URL(fileURLWithPath: "/Users/tim/Desktop/Screenshot 2026-10-20 at 09.15.02.png")
        #expect(EditorNaming.copyBaseName(for: record(fileURL: file)) == "Screenshot 2026-10-20 at 09.15.02 edited")
    }

    /// A pending file is `<id>.png`, and spec 2.6 takes the stem of any file the original has.
    @Test func stemPlusEditedForPendingFile() {
        let id = UUID()
        let file = URL(fileURLWithPath: "/tmp/pending/\(id.uuidString).png")
        #expect(EditorNaming.copyBaseName(for: record(fileURL: file, temporary: true)) == "\(id.uuidString) edited")
    }

    /// No file (an uploaded upload-only capture) or no record (deleted or pruned): the file name
    /// template names the copy.
    @Test func nilWhenNoFile() {
        let uploaded = CaptureRecord(fileURL: nil, pixelWidth: 64, pixelHeight: 48, appName: nil,
                                     uploadState: .uploaded(url: URL(string: "https://snap.example.com/a.png")!, key: "a.png"))
        #expect(EditorNaming.copyBaseName(for: uploaded) == nil)
        #expect(EditorNaming.copyBaseName(for: nil) == nil)
    }
}
```

`TidyShotTests/EditorClipboardTests.swift`:
```swift
import Foundation
import Testing
@testable import TidyShot

struct EditorClipboardTests {
    let id = UUID()

    @Test func replacesWhenStillOriginal() {
        let owner = EditorClipboard.Owner(recordID: id, changeCount: 41)
        #expect(EditorClipboard.shouldReplace(owner: owner, recordID: id, currentChangeCount: 41))
    }

    /// Any write since TidyShot's copy bumps the count: the user's text or a finished upload's URL.
    @Test func leavesWhenUserCopiedSomethingElse() {
        let owner = EditorClipboard.Owner(recordID: id, changeCount: 41)
        #expect(!EditorClipboard.shouldReplace(owner: owner, recordID: id, currentChangeCount: 42))
    }

    @Test func leavesWhenOwnerIsAnotherRecord() {
        let owner = EditorClipboard.Owner(recordID: UUID(), changeCount: 41)
        #expect(!EditorClipboard.shouldReplace(owner: owner, recordID: id, currentChangeCount: 41))
    }

    @Test func leavesWhenNoOwner() {
        #expect(!EditorClipboard.shouldReplace(owner: nil, recordID: id, currentChangeCount: 41))
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run:
```bash
xcodegen generate && xcodebuild test -project TidyShot.xcodeproj -scheme TidyShot -destination 'platform=macOS' -derivedDataPath .build 2>&1 | grep -E "Test run with|error:|TEST"
```
Expected: `error:` lines, among them `cannot find 'EditorNaming' in scope` and `cannot find 'EditorClipboard' in scope`, and no `Test run with` line.

- [ ] **Step 3: Write the two helpers**

`TidyShot/Editor/Persistence/EditorNaming.swift`:
```swift
import Foundation

/// The file name of a Save Copy from the editor.
nonisolated enum EditorNaming {
    /// `<original stem> edited` when the original has a file, in the save folder or in `pending`.
    /// `SaveLocation.write` makes it unique through `FileNamer.uniqueURL` (`… edited 2`, …). Nil
    /// when the original has no file or no record any more (deleted or pruned); the copy is then
    /// named from the file name template, with `{counter}` drawn as for a capture.
    static func copyBaseName(for record: CaptureRecord?) -> String? {
        guard let fileURL = record?.fileURL else { return nil }
        let stem = fileURL.deletingPathExtension().lastPathComponent
        guard !stem.isEmpty else { return nil }
        return "\(stem) edited"
    }
}
```

`TidyShot/Editor/Persistence/EditorClipboard.swift`:
```swift
import Foundation

/// The clipboard rule (spec 2.6): after an edit, the clipboard gets the edited image only while
/// it still holds exactly what TidyShot put there for that capture, so a redacted secret does not
/// linger and nothing the user copied since is lost.
nonisolated enum EditorClipboard {
    /// What TidyShot last put on the clipboard for a capture: the record, and the pasteboard's
    /// `changeCount` read right after that write.
    struct Owner: Equatable, Sendable {
        let recordID: UUID
        let changeCount: Int
    }

    /// True when `owner` is `recordID` and nothing has been written to the clipboard since.
    static func shouldReplace(owner: Owner?, recordID: UUID, currentChangeCount: Int) -> Bool {
        guard let owner else { return false }
        return owner.recordID == recordID && owner.changeCount == currentChangeCount
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run:
```bash
xcodegen generate && xcodebuild test -project TidyShot.xcodeproj -scheme TidyShot -destination 'platform=macOS' -derivedDataPath .build 2>&1 | grep -E "Test run with|error:|TEST"
```
Expected: no `error:` lines, and `Test run with 325 tests in 47 suites passed`.

- [ ] **Step 5: Return the change count from every pasteboard write**

Replace the whole of `TidyShot/Output/Pasteboard.swift` with this. The bodies are unchanged apart from the shared `write(_:)` and the returned count; `tiffData(of:scale:)` is unchanged.
```swift
import AppKit

enum Pasteboard {
    /// Puts the image on the general pasteboard as PNG and TIFF. The TIFF rep's size is set in
    /// points so Retina images paste at their on-screen size. Like every `copy` here, returns the
    /// pasteboard's `changeCount` after the write, which the editor's clipboard rule compares
    /// later (`EditorClipboard`).
    @discardableResult
    static func copy(image: CGImage, pngData: Data, scale: CGFloat) -> Int {
        let item = NSPasteboardItem()
        item.setData(pngData, forType: .png)
        if let tiff = tiffData(of: image, scale: scale) {
            item.setData(tiff, forType: .tiff)
        }
        return write([item])
    }

    /// Puts already encoded PNG and TIFF data on the general pasteboard; the TIFF comes from
    /// `tiffData(of:scale:)`, made off the main actor. A nil `tiffData` leaves the PNG alone.
    @discardableResult
    static func copy(pngData: Data, tiffData: Data?) -> Int {
        let item = NSPasteboardItem()
        item.setData(pngData, forType: .png)
        if let tiffData {
            item.setData(tiffData, forType: .tiff)
        }
        return write([item])
    }

    /// Puts the image on the general pasteboard as TIFF only, for when PNG encoding failed.
    /// The rep's size is set in points, as above.
    @discardableResult
    static func copy(image: CGImage, scale: CGFloat) -> Int {
        let item = NSPasteboardItem()
        if let tiff = tiffData(of: image, scale: scale) {
            item.setData(tiff, forType: .tiff)
        }
        return write([item])
    }

    /// The image as TIFF with its rep's size in points, so a Retina image pastes at its on-screen
    /// size. Touches no shared state, so it can run in a detached task (Copy Image).
    nonisolated static func tiffData(of image: CGImage, scale: CGFloat) -> Data? {
        let rep = NSBitmapImageRep(cgImage: image)
        rep.size = CGSize(width: CGFloat(image.width) / scale, height: CGFloat(image.height) / scale)
        return rep.tiffRepresentation
    }

    /// Replaces the pasteboard contents with a file reference, so a paste in Finder copies the
    /// file and a paste in Slack or Mail attaches it.
    @discardableResult
    static func copy(fileURL: URL) -> Int {
        write([fileURL as NSURL])
    }

    /// Replaces the pasteboard contents with `url`, as plain text and as a URL.
    @discardableResult
    static func copy(url: URL) -> Int {
        let item = NSPasteboardItem()
        item.setString(url.absoluteString, forType: .string)
        item.setString(url.absoluteString, forType: .URL)
        return write([item])
    }

    /// Replaces the general pasteboard's contents with `objects` and returns its `changeCount`,
    /// read after the write.
    private static func write(_ objects: [any NSPasteboardWriting]) -> Int {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects(objects)
        return pasteboard.changeCount
    }
}
```
The existing callers (AppCoordinator.swift:163, 181, 273, 446, 448, 456, 474, 796) ignore the result and compile unchanged.

- [ ] **Step 6: Factor `persist` out of `save(_:)`**

All edits are in `TidyShot/App/AppCoordinator.swift`.

After `UploadLane` (lines 11-15), add:
```swift
    /// What differs between a capture and the editor's Save Copy on the one save path.
    private struct PersistOptions {
        /// The file name in the save folder, without extension, made unique on write. Nil draws it
        /// from the file name template, `{counter}` included. Upload-only files are `<id>.png`.
        var baseName: String?
        /// The image is on the clipboard already, so a failed write need not put it there.
        var alreadyOnClipboard: Bool
        /// Plays the shutter when the Play sound setting is on. False for Save Copy.
        var playsSound: Bool
    }
```

Replace (lines 49-50):
```swift
    /// Set after the first "Upload not configured" notification so later captures stay quiet.
    @ObservationIgnored private var warnedUploadNotConfigured = false
```
with:
```swift
    /// Set after the first "Upload not configured" notification so later captures stay quiet.
    @ObservationIgnored private var warnedUploadNotConfigured = false
    /// What TidyShot last put on the clipboard for a capture: set when `save(_:)` copies the
    /// image, by the editor's Copy, and after an edit replaced the clipboard. An edit of that
    /// capture replaces the clipboard only while the count still matches.
    @ObservationIgnored private var clipboardOwner: EditorClipboard.Owner?
```

Replace `save(_:)` and its doc comment (lines 152-227) with the two functions below. The `copyImageNow` decision, the warning texts, the upload state and the notifications are unchanged. The only new behaviour is `clipboardOwner`.
```swift
    /// Encode, copy to clipboard (image now, or URL later), then `persist`: write the file, record
    /// in history, start the thumbnail, show the overlay, and start the upload. A file is always
    /// written before the upload starts; if it cannot be written the image stays on the clipboard,
    /// so a capture is never dropped. When the image goes on the clipboard, `clipboardOwner`
    /// records it for this capture, so an edit can replace it later.
    func save(_ result: CaptureResult) async {
        let image = result.scaled
        let png: Data
        do {
            png = try ImageEncoder.pngData(from: image.image, scale: image.scale)
        } catch {
            NSLog("Encode failed: \(error.localizedDescription)")
            // Never drop a capture: without PNG data the clipboard still gets the image as TIFF.
            Pasteboard.copy(image: image.image, scale: image.scale)
            notifier.notifyError(error.localizedDescription)
            return
        }

        let action = settings.afterCaptureAction
        // One keychain read per capture; persist passes the result to startUpload.
        let destination = action.uploads ? makeDestination() : nil
        let copyImageNow: Bool
        if destination != nil {
            copyImageNow = settings.alsoCopyImageWhenUploading
        } else if action.uploads {
            // Upload wanted but not possible: the clipboard gets the image instead of a URL.
            copyImageNow = true
        } else {
            copyImageNow = settings.copyImageToClipboard
        }
        let copiedChangeCount: Int? = copyImageNow
            ? Pasteboard.copy(image: image.image, pngData: png, scale: image.scale) : nil

        let options = PersistOptions(baseName: nil, alreadyOnClipboard: copyImageNow, playsSound: true)
        guard let record = await persist(png: png, image: image, action: action, destination: destination,
                                         options: options) else { return }
        if let copiedChangeCount {
            clipboardOwner = EditorClipboard.Owner(recordID: record.id, changeCount: copiedChangeCount)
        }
    }

    /// The one save path, shared by `save(_:)` and the editor's Save Copy. Writes the file (save
    /// folder, or the container's `pending` folder in upload-only mode), warns once when upload
    /// is not configured, plays the sound, records the capture, starts the thumbnail, shows the
    /// overlay, and starts the upload or posts "saved". Returns nil when the file could not be
    /// written; the writer has then notified and left the image on the clipboard. Any other
    /// clipboard write is the caller's.
    private func persist(png: Data, image: ScaledImage, action: AfterCaptureAction, destination: S3Destination?,
                         options: PersistOptions) async -> CaptureRecord? {
        // The object key is not named here: `startUpload` names it when the upload starts.
        let id = UUID()
        let fileURL: URL
        if action == .uploadOnly {
            guard let url = writePendingFile(png, id: id, image: image,
                                             alreadyOnClipboard: options.alreadyOnClipboard) else { return nil }
            fileURL = url
        } else {
            guard let url = await writeFile(png, image: image, baseName: options.baseName,
                                            alreadyOnClipboard: options.alreadyOnClipboard) else { return nil }
            fileURL = url
            lastCaptureURL = url
        }
        if action.uploads, destination == nil {
            warnUploadNotConfiguredOnce(action == .uploadOnly
                ? "Set up a destination in Settings > Upload, then retry from Recent Captures. The image is on the clipboard."
                : "Set up a destination in Settings > Upload. The capture was saved and the image is on the clipboard.")
        }
        if options.playsSound, settings.playSound {
            SoundPlayer.playShutter()
        }

        let state: CaptureRecord.UploadState
        if destination != nil {
            state = .uploading(fraction: 0)
        } else if action == .uploadOnly {
            // Nowhere to upload to yet; the pending file stays until a retry succeeds.
            state = .failed(message: UploadError.notConfigured.localizedDescription)
        } else {
            state = .none
        }
        // The source app is no longer recorded (Phase 3.1 removed its token); older records keep theirs.
        let record = CaptureRecord(id: id, fileURL: fileURL, fileIsTemporary: action == .uploadOnly,
                                   pixelWidth: image.image.width, pixelHeight: image.image.height,
                                   appName: nil, uploadState: state)
        history.add(record)
        makeThumbnail(from: image.image, for: id)
        showOverlay(for: record, image: image.image, scale: image.scale)

        if let destination {
            startUpload(recordID: record.id, data: png, destination: destination)
        } else if action != .uploadOnly, settings.showNotification {
            // Save mode, or upload mode with no destination (as in Phase 2): the file was saved.
            notifier.notifySaved(fileURL: fileURL)
        }
        return record
    }
```
`persist` has no suspension point after `history.add`, so `save(_:)` sets `clipboardOwner` before any other main-actor work can read it.

Replace `writeFile`, `writePendingFile` and `keepOnClipboard` with their doc comments (lines 238-275) with:
```swift
    /// Writes the PNG into the save folder as `baseName` (`baseName 2`, … when taken), or, when
    /// `baseName` is nil, under a name from the file name template with `{counter}` drawn as
    /// Phase 1 did. Returns nil after notifying, with the image left on the clipboard, when there
    /// is no folder or the write fails.
    private func writeFile(_ png: Data, image: ScaledImage, baseName: String?, alreadyOnClipboard: Bool) async -> URL? {
        guard let folder = await saveLocation.ensureFolder() else {
            keepOnClipboard(image, png: png, alreadyOnClipboard: alreadyOnClipboard)
            notifier.notifyError("No folder was chosen. The image is on the clipboard.", title: "Not saved")
            return nil
        }
        do {
            let name: String
            if let baseName {
                name = baseName
            } else {
                let counter = settings.fileNameTemplate.contains("{counter}") ? settings.nextCounter() : 0
                name = FileNamer(template: settings.fileNameTemplate).name(counter: counter)
            }
            return try saveLocation.write(png, baseName: name, ext: "png", in: folder)
        } catch {
            NSLog("Save failed: \(error.localizedDescription)")
            keepOnClipboard(image, png: png, alreadyOnClipboard: alreadyOnClipboard)
            notifier.notifyError("\(error.localizedDescription) The image is on the clipboard.", title: "Not saved")
            return nil
        }
    }

    /// Upload-only mode: writes the PNG into the container's `pending` folder as `<id>.png`, no
    /// folder prompt.
    private func writePendingFile(_ png: Data, id: UUID, image: ScaledImage, alreadyOnClipboard: Bool) -> URL? {
        do {
            return try pendingFiles.write(png, id: id, ext: "png")
        } catch {
            NSLog("Pending write failed: \(error.localizedDescription)")
            keepOnClipboard(image, png: png, alreadyOnClipboard: alreadyOnClipboard)
            notifier.notifyError("\(error.localizedDescription) The image is on the clipboard.", title: "Not saved")
            return nil
        }
    }

    /// A failed write's fallback, so a capture or an edit is never dropped. It sets no
    /// `clipboardOwner`: no record was made for this image.
    private func keepOnClipboard(_ image: ScaledImage, png: Data, alreadyOnClipboard: Bool) {
        if !alreadyOnClipboard {
            Pasteboard.copy(image: image.image, pngData: png, scale: image.scale)
        }
    }
```

Check that no caller still passes a `CaptureResult` to the writers, and that there is one save path:
```bash
grep -nE "result: CaptureResult, alreadyOnClipboard|keepOnClipboard\(result" TidyShot/App/AppCoordinator.swift
grep -c "persist(png:" TidyShot/App/AppCoordinator.swift
```
Expected: nothing from the first command. The second prints `2` now (the definition and `save(_:)`), and `3` after Step 7.

- [ ] **Step 7: Save Copy, Copy and the clipboard rule under `// MARK: Editor`**

Add these three methods to the `// MARK: Editor` section that Task 10 created in `TidyShot/App/AppCoordinator.swift`. They must stay in this file, because they call `persist`, `notifier` and `clipboardOwner`, which are `private`.
```swift
    /// Save Copy (⇧⌘S): the edited image becomes a new capture through `persist`, as if just taken
    /// with the current after-capture action. It gets a file in the save folder named by
    /// `EditorNaming.copyBaseName(for:)` (or by the template), or a pending file that uploads, plus
    /// a thumbnail, a Recent Captures row and the overlay. There is no shutter sound. A deleted or
    /// pruned original does not block it, and the editor stays on the original record. Then the
    /// clipboard gets the edited image only if it still holds what TidyShot put there for the
    /// original. Returns false when nothing was written; the edited image is then on the clipboard.
    private func editorSaveCopy(of recordID: UUID, image: ScaledImage) async -> Bool {
        let png: Data
        do {
            png = try await Task.detached(priority: .userInitiated) {
                try ImageEncoder.pngData(from: image.image, scale: image.scale)
            }.value
        } catch {
            NSLog("Encode failed: \(error.localizedDescription)")
            // Never drop an edit: without PNG data the clipboard still gets the image as TIFF.
            Pasteboard.copy(image: image.image, scale: image.scale)
            notifier.notifyError("\(error.localizedDescription) The image is on the clipboard.", title: "Not saved")
            return false
        }
        let action = settings.afterCaptureAction
        let destination = action.uploads ? makeDestination() : nil
        let options = PersistOptions(baseName: EditorNaming.copyBaseName(for: history.record(id: recordID)),
                                     alreadyOnClipboard: false, playsSound: false)
        guard await persist(png: png, image: image, action: action, destination: destination,
                            options: options) != nil else { return false }
        await replaceClipboardIfStillOriginal(recordID: recordID, png: png, image: image)
        return true
    }

    /// The clipboard rule (spec 2.6), after a Save Copy or (from Task 13) a local edit. Puts the
    /// edited PNG and TIFF on the clipboard only while it still holds exactly what TidyShot put
    /// there for `recordID`, and leaves anything copied since alone. The TIFF is made in a detached
    /// task. Ownership is checked again after that await, right before the write, so a URL that a
    /// finished upload copied in the meantime is never overwritten. TidyShot then owns the
    /// clipboard for this record at the new count, so a later edit replaces this one too.
    private func replaceClipboardIfStillOriginal(recordID: UUID, png: Data, image: ScaledImage) async {
        guard EditorClipboard.shouldReplace(owner: clipboardOwner, recordID: recordID,
                                            currentChangeCount: NSPasteboard.general.changeCount) else { return }
        let tiff = await Task.detached(priority: .userInitiated) {
            Pasteboard.tiffData(of: image.image, scale: image.scale)
        }.value
        guard EditorClipboard.shouldReplace(owner: clipboardOwner, recordID: recordID,
                                            currentChangeCount: NSPasteboard.general.changeCount) else { return }
        let changeCount = Pasteboard.copy(pngData: png, tiffData: tiff)
        clipboardOwner = EditorClipboard.Owner(recordID: recordID, changeCount: changeCount)
    }

    /// Copy (⌘C, ⇧⌘C): the edited image as PNG and TIFF, both encoded in a detached task and
    /// written here on the main actor. TidyShot then owns the clipboard for this record, so a later
    /// Save Copy or Save puts the newer edit there. The window stays open.
    private func editorCopy(recordID: UUID, image: ScaledImage) async {
        do {
            let encoded = try await Task.detached(priority: .userInitiated) { () throws -> (png: Data, tiff: Data?) in
                (try ImageEncoder.pngData(from: image.image, scale: image.scale),
                 Pasteboard.tiffData(of: image.image, scale: image.scale))
            }.value
            let changeCount = Pasteboard.copy(pngData: encoded.png, tiffData: encoded.tiff)
            clipboardOwner = EditorClipboard.Owner(recordID: recordID, changeCount: changeCount)
            if settings.showNotification {
                let record = history.record(id: recordID)
                notifier.notify(title: "Image copied", body: record?.uploadedKey ?? record?.fileURL?.lastPathComponent ?? "")
            }
        } catch {
            notifier.notifyError(error.localizedDescription, title: "Could not copy image")
        }
    }
```

In `editorActions(for recordID:)` (Task 10, under `// MARK: Editor`), the `EditorActions(...)` value it returns gets these two members in place of Task 10's logging stubs. `showEditor(recordID:image:)` already passes that value to `EditorWindowController`, and `openEditor(recordID:)` only loads and decodes, so neither changes. Leave `save` and `upload` as they are; Tasks 13 and 15 replace them.
```swift
            saveCopy: { [weak self] image in
                await self?.editorSaveCopy(of: recordID, image: image) ?? false
            },
            copy: { [weak self] image in
                await self?.editorCopy(recordID: recordID, image: image)
            },
```
The editor still never touches the pasteboard or the disk. Its controller only renders the export, calls these closures, and calls `markSaved()` after a Save Copy that returns true.

- [ ] **Step 8: Run the whole suite**

Run:
```bash
xcodegen generate && xcodebuild test -project TidyShot.xcodeproj -scheme TidyShot -destination 'platform=macOS' -derivedDataPath .build 2>&1 | grep -E "Test run with|error:|TEST"
grep -c "persist(png:" TidyShot/App/AppCoordinator.swift
```
Expected: no `error:` lines, `Test run with 325 tests in 47 suites passed`, then `3`.

- [ ] **Step 9: Check by hand**

Build and run:
```bash
xcodebuild -project TidyShot.xcodeproj -scheme TidyShot -configuration Debug -derivedDataPath .build build -quiet && open .build/Build/Products/Debug/TidyShot.app
```
Open the editor with Task 10's `Annotate Last Capture (debug)` status menu item.
1. Set each After capture mode in Settings > General in turn: Save, Upload, and Upload only. Capture an area with ⌃⇧4 each time. Expected, as before this task: shutter sound, file or pending file, overlay, Recent Captures row, upload, notifications. In Save mode with Copy image to clipboard on, the image is on the clipboard. In the upload modes, the URL is on the clipboard when the upload finishes.
2. Save mode, Copy image to clipboard on. Capture text, open the editor, draw a Redact box over part of it and press ⇧⌘S. Expected:
   - no shutter sound;
   - `<stem> edited.png` in the save folder, a new top row in Recent Captures, and the overlay for it;
   - the editor stays open with the original's title, and the close button's unsaved-changes dot clears;
   - in Preview, File > New from Clipboard shows the redacted image.

   Press ⇧⌘S again. Expected: `<stem> edited 2.png`.
3. Upload mode, then Upload only, both with a destination. Do Redact and Save Copy. Expected: the copy gets its own Recent Captures row and uploads, and its URL is on the clipboard at the end. In Upload only, no file appears in the save folder.
4. Upload mode with no destination (Forget Credentials in Settings > Upload). Capture, then Redact and Save Copy. Expected: File > New from Clipboard in Preview shows the redacted image.
5. Save mode. Capture, then copy some text in TextEdit, then Redact and Save Copy. Expected: a paste gives the text.
6. Save mode. Press ⌘C, then ⇧⌘C. Expected: each time, File > New from Clipboard in Preview shows the edited image at the capture's point size (Tools > Adjust Size shows 144 pixels/inch for a Retina capture). `Image copied` is posted when Show notification is on, and the window stays open. Then add another Redact box and press ⇧⌘S: the clipboard now holds the newer edit.
7. With the editor open, delete the original from Recent Captures, then press ⇧⌘S. Expected: a new capture named from the file name template appears.

- [ ] **Step 10: Commit**

```bash
git add TidyShot/Output/Pasteboard.swift TidyShot/App/AppCoordinator.swift TidyShot/Editor/Persistence/EditorNaming.swift TidyShot/Editor/Persistence/EditorClipboard.swift TidyShotTests/EditorNamingTests.swift TidyShotTests/EditorClipboardTests.swift
git commit -m "feat: save copy and copy from the editor through the one save path"
```

### Task 13: Save over, one local-edit path, editor state push, coordinator-side gate, edited thumbnails

**Files:**
- Create: `TidyShot/Editor/Persistence/EditorSaveTarget.swift` (`EditorSaveTarget`, `EditorAction`, `EditorAvailability`)
- Create: `TidyShot/Editor/Persistence/EditorCommandGate.swift`
- Create: `TidyShotTests/EditorSaveTargetTests.swift`
- Create: `TidyShotTests/SaveLocationOverwriteTests.swift`
- Modify: `TidyShot/Output/SaveLocation.swift` (two statics after `readScoped`, which ends at line 76)
- Modify: `TidyShot/History/CaptureRecord.swift` (properties and `init` at 32-50, `CodingKeys` at 52-55, decoder at 57-73, after `isPendingOnly` at 88-90)
- Modify: `TidyShot/History/HistoryStore.swift` (`didPrune` doc at 13-16, end of `load()` at 60-61, `add(_:)` and `prune(_:)` at 64-78, `pruned` at 112-118)
- Modify: `TidyShot/History/ThumbnailStore.swift` (type doc at 3-5, `fileName(for:)` and `write(_:id:)` at 20-34)
- Modify: `TidyShot/App/AppCoordinator.swift` (line numbers are at f4541da; 4a-10 and 4a-12 shift them, so match the code shown: `makeThumbnail` 277-300, `deleteCapture` 536-540, `removeRecord` 657-666, `removeFiles(ofPruned:)` 723-735, `refreshOverlay` 746-751, and `// MARK: Editor` from 4a-10 and 4a-12)
- Modify: `TidyShot/Editor/Window/EditorWindowController.swift` (from 4a-10 and 4a-11)
- Test: `TidyShotTests/CaptureRecordTests.swift`, `TidyShotTests/ThumbnailStoreTests.swift`, `TidyShotTests/HistoryStoreTests.swift`

**Interfaces:**
- Consumes:
  - `HistoryStore.record(id:) -> CaptureRecord?` (HistoryStore.swift:80), `update(id:_:)` (85), `static func pruned(_:retentionDays:now:)` (115), `didPrune` (16).
  - `PendingFileStore.write(_ data: Data, id: UUID, ext: String) throws -> URL` (PendingFileStore.swift:21). It always writes `pending/<id>.<ext>`, the name `save(_:)` gives an upload-only capture.
  - `ThumbnailMaker.thumbnail(from: CGImage, maxSide: Int = maxSide) -> CGImage?` (ThumbnailMaker.swift:22) and `pngData(_:) throws -> Data` (54).
  - `ThumbnailProvider.forget(_ id: UUID)` (ThumbnailProvider.swift:129). It drops the cached thumbnail and preview and bumps the generation.
  - `SaveLocation.currentURL` (`@Observable`, SaveLocation.swift:10). `ImageEncoder.pngData(from:scale:) throws -> Data` (nonisolated, ImageEncoder.swift:21). `Notifier.notifyError(_ message: String, title: String)` (Notifier.swift:35).
  - The private AppCoordinator members `deletingIDs` (48), `makeThumbnail(from:for:)` (281), `deleteCapture(recordID:)` (536), `removeRecord(id:)` (657), `removeFiles(ofPruned:)` (725), `refreshOverlay(for:)` (747), `thumbnails`, `pendingFiles`, `notifier`.
  - The `withObservationTracking { } onChange: { Task { @MainActor in … } }` idiom in `StatusMenuController.updateIcon()` (StatusMenuController.swift:41-46).
  - 4a-2: `nonisolated struct ScaledImage: Sendable { let image: CGImage; let scale: CGFloat }`.
  - 4a-4: `enum EditorShortcut: CaseIterable, Sendable` with `var selectorName: String` (`saveDocument:`, `saveDocumentCopy:`, `copy:`, `copyImage:`, `uploadDocument:`, `uploadDocumentAsNew:` for the six action rows).
  - 4a-8: `EditorModel.document: AnnotationDocument` (Equatable), `func renderExport() async -> ScaledImage?`, `func markSaved()`.
  - 4a-10: `struct EditorActions { var save, saveCopy: (ScaledImage) async -> Bool; … }`; the controller's `model` and `actions`, its `@objc` action methods, `validateUserInterfaceItem(_:)` and `askToSaveBeforeClosing() async -> Bool`; `private var editors: [UUID: EditorWindowController]`, `func openEditor(recordID: UUID)` (loads and decodes only), `private func showEditor(recordID: UUID, image: ScaledImage)` (builds the model and controller, stores it in `editors`, warms the renderer, calls `present()`) and `private func editorActions(for recordID: UUID) -> EditorActions` (the logging stubs) in `// MARK: Editor`. 4a-10's `runDocumentAction(marksSaved:_:)`, `exportAndDeliver(marksSaved:_:)` and `isPerformingAction` are the one export path for all six actions; this task keeps them.
  - 4a-11: `NSToolbarItem.Identifier.save` (an `NSMenuToolbarItem` whose menu offers Save Copy…).
  - 4a-12: every `Pasteboard.copy` method is `@discardableResult` and returns the pasteboard's `changeCount`; `private var clipboardOwner: EditorClipboard.Owner?`; `EditorClipboard.Owner(recordID:changeCount:)`; `private func replaceClipboardIfStillOriginal(recordID: UUID, png: Data, image: ScaledImage) async`; `private func editorSaveCopy(of recordID: UUID, image: ScaledImage) async -> Bool`.
- Produces:
  - `SaveLocation`: `nonisolated static func contains(_ fileURL: URL, inFolder folder: URL) -> Bool`; `nonisolated static func overwriteScoped(_ data: Data, at fileURL: URL, folder: URL) throws`.
  - `CaptureRecord`: `var editedAt: Date?`; `var uploadIsStale: Bool`; `init(…, pendingObjectKey: String? = nil, editedAt: Date? = nil, uploadIsStale: Bool = false)`; `var keepsUnuploadedEdit: Bool { fileIsTemporary && fileURL != nil && uploadIsStale }`. Both fields are `decodeIfPresent`, defaulting to nil and false.
  - `HistoryStore.pruned(_:retentionDays:now:)` also keeps `keepsUnuploadedEdit` records. `didPrune` now runs after `records` has dropped the pruned records.
  - `ThumbnailStore`: `func fileName(for id: UUID, editedAt: Date?) -> String` (`<UUID>.png`, or `<UUID>-<milliseconds>.png`); `func write(_ png: Data, fileName: String) throws -> String`.
  - `nonisolated enum EditorSaveTarget { enum Plan: Equatable, Sendable { case saveFolderFile(URL, folder: URL), pendingFile(URL), unavailable(String) }; static let noFileReason, noFolderReason, outsideFolderReason, uploadedCopyStaleNotice: String; static func plan(for record: CaptureRecord, saveFolder: URL?) -> Plan; static func uploadedCopyNotice(for record: CaptureRecord) -> String? }`.
  - `nonisolated enum EditorAction: CaseIterable, Sendable { case save, saveCopy, copy, upload, uploadAsNew }`.
  - `nonisolated enum EditorAvailability { static let deletedStatus, deletingStatus, uploadingStatus, deletedRefusal, deletingRefusal, uploadingRefusal, notUploadedRefusal: String; static func actions(record: CaptureRecord?, saveFolder: URL?, isDeleting: Bool) -> Set<EditorAction>; static func status(record: CaptureRecord?, saveFolder: URL?, isDeleting: Bool) -> String?; static func refusal(for action: EditorAction, record: CaptureRecord?, saveFolder: URL?, isDeleting: Bool) -> String? }`. `refusal` is nil exactly when `actions` contains the action.
  - `nonisolated enum EditorCommandGate { static func action(for selectorName: String) -> EditorAction?; static func permits(_ selectorName: String, available: Set<EditorAction>) -> Bool }`. A selector with no `EditorAction` is always permitted.
  - AppCoordinator (`// MARK: Editor`): `private func pushEditorState(for id: UUID)`; `private func observeSaveFolderForEditors()`; `private func applyLocalEdit(recordID: UUID, png: Data, image: ScaledImage) async -> Bool`; `private func editorSave(recordID: UUID, image: ScaledImage) async -> Bool`; `private func replaceThumbnail(for id: UUID, from image: CGImage, editedAt: Date)`; `private func keepFailedEditOnClipboard(_ image: ScaledImage, png: Data?, recordID: UUID, error: any Error)`. Callers of `pushEditorState`: `refreshOverlay(for:)`, `removeRecord(id:)`, `removeFiles(ofPruned:)` (per record), `deleteCapture(recordID:)` (after the insert and in its `defer`), `applyLocalEdit`, and `showEditor(recordID:image:)` (the first push).
  - EditorWindowController: `private(set) var available: Set<EditorAction>`; `func recordDidChange(_ record: CaptureRecord?, saveFolder: URL?, isDeleting: Bool)`; `func reflectSaveAvailability()` (in EditorToolbar.swift's `EditorWindowController` extension); `validateUserInterfaceItem(_:)` and the six action methods ask `EditorCommandGate`. No export helper is added: Save and Save Copy keep 4a-10's `runDocumentAction`/`exportAndDeliver` bodies, and the close sheet is unchanged.
  - Forward note: `EditorAvailability.refusal` (`uploadAsNew`) and `applyLocalEdit` (`uploadIsStale`) test `record.uploadedURL`, because `CaptureRecord.linkURL` and `priorUpload` do not exist until Task 14. Task 14 changes both conditions to `record.linkURL != nil` (so a replace interrupted by a quit, which keeps its link in `priorUpload`, still offers Upload as New and still marks the link stale).

- [ ] **Step 1: Write the failing tests**

`TidyShotTests/EditorSaveTargetTests.swift`:
```swift
import Foundation
import Testing
@testable import TidyShot

struct EditorSaveTargetTests {
    let folder = URL(filePath: "/Users/tim/Pictures/TidyShot", directoryHint: .isDirectory)
    let link = URL(string: "https://snap.tky.io/a.png")!
    let location = ObjectLocation(endpoint: "https://s3.us-west-2.amazonaws.com", region: "us-west-2",
                                  bucket: "snap.tky.io", usePathStyle: true)
    let pendingURL = URL(filePath: "/Users/tim/Library/Containers/io.tky.tidyshot/Data/Library/Application Support/TidyShot/pending/A.png")

    /// A capture saved in `folder` (this suite's save folder unless given), in `state`.
    func saved(in folder: URL? = nil, state: CaptureRecord.UploadState = .none, stale: Bool = false) -> CaptureRecord {
        CaptureRecord(fileURL: (folder ?? self.folder).appending(path: "Screenshot 2026-10-20 at 10.00.00.png"),
                      pixelWidth: 200, pixelHeight: 100, appName: nil, uploadState: state, uploadIsStale: stale)
    }

    func actions(_ record: CaptureRecord?, folder: URL? = nil, deleting: Bool = false) -> Set<EditorAction> {
        EditorAvailability.actions(record: record, saveFolder: folder ?? self.folder, isDeleting: deleting)
    }

    @Test func saveFolderFileInsideFolder() throws {
        let record = saved()
        let fileURL = try #require(record.fileURL)
        #expect(EditorSaveTarget.plan(for: record, saveFolder: folder) == .saveFolderFile(fileURL, folder: folder))
        #expect(actions(record).contains(.save))
    }

    @Test func fileOutsideFolderUnavailable() {
        let record = saved(in: URL(filePath: "/Users/tim/Desktop", directoryHint: .isDirectory))
        #expect(EditorSaveTarget.plan(for: record, saveFolder: folder)
                == .unavailable("The file is outside the current save folder, so it is not saved over."))
        #expect(!actions(record).contains(.save))
        #expect(actions(record).isSuperset(of: [.saveCopy, .copy, .upload]))
    }

    @Test func noFolderUnavailable() {
        #expect(EditorSaveTarget.plan(for: saved(), saveFolder: nil)
                == .unavailable("No save folder is set, so the file is not saved over."))
        #expect(EditorAvailability.status(record: saved(), saveFolder: nil, isDeleting: false)
                == "No save folder is set, so the file is not saved over.")
    }

    /// An upload-only capture's file in `pending` needs no save folder.
    @Test func pendingFileIsPendingTarget() {
        let record = CaptureRecord(fileURL: pendingURL, fileIsTemporary: true, pixelWidth: 200, pixelHeight: 100,
                                   appName: nil, uploadState: .failed(message: "offline"))
        #expect(EditorSaveTarget.plan(for: record, saveFolder: folder) == .pendingFile(pendingURL))
        #expect(EditorSaveTarget.plan(for: record, saveFolder: nil) == .pendingFile(pendingURL))
        #expect(actions(record) == [.save, .saveCopy, .copy, .upload])
    }

    @Test func uploadedUploadOnlyWithoutFileUnavailable() {
        let record = CaptureRecord(fileURL: nil, pixelWidth: 200, pixelHeight: 100, appName: nil,
                                   uploadState: .uploaded(url: link, key: "a.png"), objectLocation: location)
        #expect(EditorSaveTarget.plan(for: record, saveFolder: folder)
                == .unavailable("This capture has no local file to save over."))
        #expect(actions(record) == [.saveCopy, .copy, .upload, .uploadAsNew])
        #expect(EditorAvailability.refusal(for: .save, record: record, saveFolder: folder, isDeleting: false)
                == "This capture has no local file to save over.")
    }

    /// Records uploaded before Phase 3 keep their file in the save folder and have no stored location.
    @Test func prePhaseThreeUploadedWithFileOverwrites() throws {
        let record = saved(state: .uploaded(url: link, key: "a.png"))
        #expect(record.objectLocation == nil)
        let fileURL = try #require(record.fileURL)
        #expect(EditorSaveTarget.plan(for: record, saveFolder: folder) == .saveFolderFile(fileURL, folder: folder))
        #expect(actions(record) == Set(EditorAction.allCases))
    }

    @Test func noticeOnlyWhenUploadIsStale() {
        let fresh = saved(state: .uploaded(url: link, key: "a.png"))
        let stale = saved(state: .uploaded(url: link, key: "a.png"), stale: true)
        #expect(EditorSaveTarget.uploadedCopyNotice(for: fresh) == nil)
        #expect(EditorSaveTarget.uploadedCopyNotice(for: stale)
                == "The uploaded copy still shows the original. Upload to replace it.")
        #expect(EditorAvailability.status(record: fresh, saveFolder: folder, isDeleting: false) == nil)
        #expect(EditorAvailability.status(record: stale, saveFolder: folder, isDeleting: false)
                == "The uploaded copy still shows the original. Upload to replace it.")
    }

    @Test func availabilityWhileUploadingIsCopyAndSaveCopy() {
        let uploading = saved(state: .uploading(fraction: 0.3))
        #expect(actions(uploading) == [.copy, .saveCopy])
        #expect(EditorAvailability.status(record: uploading, saveFolder: folder, isDeleting: false) == "Uploading…")
        #expect(EditorAvailability.refusal(for: .save, record: uploading, saveFolder: folder, isDeleting: false)
                == "This capture is still uploading.")
        #expect(EditorAvailability.refusal(for: .upload, record: uploading, saveFolder: folder, isDeleting: false)
                == "This capture is still uploading.")
    }

    /// A nil record was deleted or pruned.
    @Test func availabilityWhenDeletedIsCopyAndSaveCopy() {
        #expect(actions(nil) == [.copy, .saveCopy])
        #expect(actions(nil, deleting: true) == [.copy, .saveCopy])
        #expect(EditorAvailability.status(record: nil, saveFolder: folder, isDeleting: false)
                == "This capture was deleted. Copy and Save Copy still work.")
        #expect(EditorAvailability.refusal(for: .save, record: nil, saveFolder: folder, isDeleting: false)
                == "This capture was deleted.")
        #expect(EditorAvailability.refusal(for: .saveCopy, record: nil, saveFolder: folder, isDeleting: false) == nil)
    }

    @Test func availabilityWhileDeletingIsCopyAndSaveCopy() {
        let record = saved(state: .uploaded(url: link, key: "a.png"))
        #expect(actions(record) == Set(EditorAction.allCases))
        #expect(actions(record, deleting: true) == [.copy, .saveCopy])
    }

    /// Keyed on `uploadedURL` here; Task 14 re-keys it on `linkURL` and adds the interrupted-replace case.
    @Test func uploadAsNewNeedsALink() {
        let never = saved()
        #expect(actions(never) == [.save, .saveCopy, .copy, .upload])
        #expect(EditorAvailability.refusal(for: .uploadAsNew, record: never, saveFolder: folder, isDeleting: false)
                == "This capture has no link yet. Use Upload.")
        #expect(!actions(saved(state: .failed(message: "offline"))).contains(.uploadAsNew))
        #expect(actions(saved(state: .uploaded(url: link, key: "a.png"))).contains(.uploadAsNew))
    }

    @Test func everyActionShortcutMapsToAnAvailabilityAction() {
        let expected: [EditorShortcut: EditorAction] = [
            .save: .save, .saveCopy: .saveCopy, .copy: .copy, .copyImage: .copy,
            .upload: .upload, .uploadAsNew: .uploadAsNew,
        ]
        for shortcut in EditorShortcut.allCases {
            #expect(EditorCommandGate.action(for: shortcut.selectorName) == expected[shortcut], "\(shortcut)")
        }
        #expect(Set(expected.values) == Set(EditorAction.allCases))
    }

    @Test func gateRefusesDisabledShortcut() {
        let available = actions(saved(state: .uploading(fraction: 0)))
        for selector in ["saveDocument:", "uploadDocument:", "uploadDocumentAsNew:"] {
            #expect(!EditorCommandGate.permits(selector, available: available), "\(selector)")
        }
        for selector in ["saveDocumentCopy:", "copy:", "copyImage:"] {
            #expect(EditorCommandGate.permits(selector, available: available), "\(selector)")
        }
        // Not an editor action: always let through, whatever is available.
        #expect(EditorCommandGate.permits("undo:", available: []))
        #expect(EditorCommandGate.permits("zoomIn:", available: []))
        #expect(EditorCommandGate.action(for: "cut:") == nil)
    }

    @Test func refusalWhileDeletingNamesTheDeleteForSaveAndUpload() {
        let record = saved(state: .uploaded(url: link, key: "a.png"))
        for action in [EditorAction.save, .upload, .uploadAsNew] {
            #expect(EditorAvailability.refusal(for: action, record: record, saveFolder: folder, isDeleting: true)
                    == "This capture is being deleted.", "\(action)")
        }
        #expect(EditorAvailability.refusal(for: .saveCopy, record: record, saveFolder: folder, isDeleting: true) == nil)
        #expect(EditorAvailability.refusal(for: .copy, record: record, saveFolder: folder, isDeleting: true) == nil)
        #expect(EditorAvailability.refusal(for: .save, record: record, saveFolder: folder, isDeleting: false) == nil)
    }

    @Test func availabilityFollowsSaveFolderChange() {
        let folderA = URL(filePath: "/Users/tim/Pictures/A", directoryHint: .isDirectory)
        let folderB = URL(filePath: "/Users/tim/Pictures/B", directoryHint: .isDirectory)
        let record = saved(in: folderA)
        #expect(actions(record, folder: folderA).contains(.save))
        #expect(!actions(record, folder: folderB).contains(.save))
        #expect(actions(record, folder: folderB).contains(.upload))
        #expect(EditorAvailability.status(record: record, saveFolder: folderA, isDeleting: false) == nil)
        #expect(EditorAvailability.status(record: record, saveFolder: folderB, isDeleting: false)
                == "The file is outside the current save folder, so it is not saved over.")
    }

    @Test func statusSaysDeletingWhileDeleting() {
        let uploading = saved(state: .uploading(fraction: 0.5))
        let stale = saved(state: .uploaded(url: link, key: "a.png"), stale: true)
        #expect(EditorAvailability.status(record: uploading, saveFolder: folder, isDeleting: true) == "Deleting…")
        #expect(EditorAvailability.status(record: stale, saveFolder: folder, isDeleting: true) == "Deleting…")
        // removeRecord has run: the record is gone, and the deleted text wins.
        #expect(EditorAvailability.status(record: nil, saveFolder: folder, isDeleting: true)
                == "This capture was deleted. Copy and Save Copy still work.")
    }
}
```

`TidyShotTests/SaveLocationOverwriteTests.swift`:
```swift
import Foundation
import Testing
@testable import TidyShot

struct SaveLocationOverwriteTests {
    let dir: URL

    init() throws {
        dir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dir.appending(path: "Shots"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: dir.appending(path: "Elsewhere"), withIntermediateDirectories: true)
    }

    @Test func overwriteReplacesBytesKeepsName() throws {
        defer { try? FileManager.default.removeItem(at: dir) }
        let folder = dir.appending(path: "Shots", directoryHint: .isDirectory)
        let file = folder.appending(path: "Screenshot 2026-10-20 at 10.00.00.png")
        try Data([1, 2, 3]).write(to: file)

        try SaveLocation.overwriteScoped(Data([4, 5, 6, 7]), at: file, folder: folder)

        #expect(try Data(contentsOf: file) == Data([4, 5, 6, 7]))
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path(percentEncoded: false))
                == ["Screenshot 2026-10-20 at 10.00.00.png"])
    }

    @Test func overwriteRefusesFileOutsideFolder() throws {
        defer { try? FileManager.default.removeItem(at: dir) }
        let folder = dir.appending(path: "Shots", directoryHint: .isDirectory)
        let outside = dir.appending(path: "Elsewhere/a.png")
        try Data([1, 2, 3]).write(to: outside)

        let error = #expect(throws: CocoaError.self) {
            try SaveLocation.overwriteScoped(Data([9]), at: outside, folder: folder)
        }
        #expect(error?.code == .fileWriteNoPermission)
        #expect(try Data(contentsOf: outside) == Data([1, 2, 3]))
    }

    /// Paths are compared component by component as written; no symlink is resolved.
    @Test func containsHandlesSymlinkFreePrefixes() {
        let folder = URL(filePath: "/Users/tim/Pictures/Shots", directoryHint: .isDirectory)
        #expect(SaveLocation.contains(URL(filePath: "/Users/tim/Pictures/Shots/a.png"), inFolder: folder))
        #expect(SaveLocation.contains(URL(filePath: "/Users/tim/Pictures/Shots/2026/a.png"), inFolder: folder))
        #expect(SaveLocation.contains(URL(filePath: "/Users/tim/Pictures/Shots/./b/../a.png"), inFolder: folder))
        #expect(SaveLocation.contains(URL(filePath: "/Users/tim/Pictures/Shots/a.png"),
                                      inFolder: URL(filePath: "/Users/tim/Pictures/Shots/")))
        // A sibling whose name starts with the folder's name is not inside it.
        #expect(!SaveLocation.contains(URL(filePath: "/Users/tim/Pictures/Shots 2/a.png"), inFolder: folder))
        #expect(!SaveLocation.contains(URL(filePath: "/Users/tim/Pictures/Shotsa.png"), inFolder: folder))
        #expect(!SaveLocation.contains(URL(filePath: "/Users/tim/Pictures/Shots/../a.png"), inFolder: folder))
        #expect(!SaveLocation.contains(folder, inFolder: folder))
        #expect(!SaveLocation.contains(URL(string: "https://snap.tky.io/Users/tim/Pictures/Shots/a.png")!, inFolder: folder))
    }
}
```

In `TidyShotTests/CaptureRecordTests.swift`, add after `uploadedKeyAndPendingOnly()` (it ends at line 94):
```swift
    /// A record as Phase 3 wrote it: temporary flag, thumbnail and location, but no edit fields.
    let phase3JSON = """
    [
      {
        "fileIsTemporary" : true,
        "fileURL" : "file:///Users/tim/Library/Containers/io.tky.tidyshot/Data/Library/Application%20Support/TidyShot/pending/5D1C2B3A-4E5F-4A6B-8C7D-9E0F1A2B3C4D.png",
        "id" : "5D1C2B3A-4E5F-4A6B-8C7D-9E0F1A2B3C4D",
        "objectLocation" : {
          "bucket" : "snap.tky.io",
          "endpoint" : "https://s3.us-west-2.amazonaws.com",
          "region" : "us-west-2",
          "usePathStyle" : true
        },
        "pixelHeight" : 100,
        "pixelWidth" : 200,
        "thumbnailFileName" : "5D1C2B3A-4E5F-4A6B-8C7D-9E0F1A2B3C4D.png",
        "timestamp" : "2026-10-19T16:56:03.000Z",
        "uploadState" : {
          "failed" : {
            "message" : "offline"
          }
        }
      }
    ]
    """

    @Test func editedAtAndStaleFlagDecodeFromPhaseThreeJSON() throws {
        try Data(phase3JSON.utf8).write(to: dir.appending(path: "history.json"))
        let history = store()
        history.load()

        let record = try #require(history.record(id: UUID(uuidString: "5D1C2B3A-4E5F-4A6B-8C7D-9E0F1A2B3C4D")!))
        #expect(record.fileIsTemporary)
        #expect(record.thumbnailFileName == "5D1C2B3A-4E5F-4A6B-8C7D-9E0F1A2B3C4D.png")
        #expect(record.editedAt == nil)
        #expect(record.uploadIsStale == false)
        #expect(!record.keepsUnuploadedEdit)
    }

    /// Timestamps are stored with millisecond precision, so the fixture uses whole seconds.
    @Test func editedAtAndStaleFlagRoundTrip() throws {
        let now = Date(timeIntervalSince1970: 1_792_411_200)
        let edited = CaptureRecord(timestamp: now, fileURL: dir.appending(path: "pending/x.png"), fileIsTemporary: true,
                                   pixelWidth: 40, pixelHeight: 30, appName: nil,
                                   uploadState: .uploaded(url: URL(string: "https://snap.tky.io/x.png")!, key: "x.png"),
                                   editedAt: now.addingTimeInterval(90), uploadIsStale: true)
        store().add(edited)

        let reloaded = store()
        reloaded.load()
        let record = try #require(reloaded.record(id: edited.id))
        #expect(record == edited)
        #expect(record.editedAt == now.addingTimeInterval(90))
        #expect(record.uploadIsStale)
        #expect(record.keepsUnuploadedEdit)
    }
```

In `TidyShotTests/ThumbnailStoreTests.swift`, add after `writeCreatesFolderAndReturnsFileName()` (it ends at line 28):
```swift
    /// An edit gets a new name per save, so rows keyed on the name reload, and the capture-time
    /// writer (`<UUID>.png` only) can never overwrite it.
    @Test func editedFileNameDiffersAndIsDeterministic() throws {
        let store = ThumbnailStore(directory: dir.appending(path: "thumbnails"))
        defer { try? FileManager.default.removeItem(at: dir) }
        let id = UUID(uuidString: "0B2E8A4C-1C3D-4E5F-8A9B-0C1D2E3F4A5B")!
        let edited = Date(timeIntervalSince1970: 1_792_411_200.123)

        #expect(store.fileName(for: id, editedAt: nil) == "0B2E8A4C-1C3D-4E5F-8A9B-0C1D2E3F4A5B.png")
        #expect(store.fileName(for: id, editedAt: edited) == "0B2E8A4C-1C3D-4E5F-8A9B-0C1D2E3F4A5B-1792411200123.png")
        #expect(store.fileName(for: id, editedAt: edited) == store.fileName(for: id, editedAt: edited))
        #expect(store.fileName(for: id, editedAt: edited.addingTimeInterval(1)) != store.fileName(for: id, editedAt: edited))

        let name = try store.write(Data([7, 8]), fileName: store.fileName(for: id, editedAt: edited))
        #expect(name == "0B2E8A4C-1C3D-4E5F-8A9B-0C1D2E3F4A5B-1792411200123.png")
        #expect(try Data(contentsOf: store.url(forFileName: name)) == Data([7, 8]))
        #expect(!FileManager.default.fileExists(atPath: store.url(forFileName: store.fileName(for: id)).path(percentEncoded: false)))
    }
```

In `TidyShotTests/HistoryStoreTests.swift`, replace `didPruneReportsDroppedRecordsOnAddAndLoad()` (lines 92-108) with this version, which also checks that a pruned record is gone when `didPrune` runs:
```swift
    @Test func didPruneReportsDroppedRecordsOnAddAndLoad() {
        let first = store(retentionDays: 30)
        var pruned: [[UUID]] = []
        var stillListed: [UUID] = []
        first.didPrune = { dropped in
            pruned.append(dropped.map(\.id))
            // Reported after `records` dropped them, so the editor state push finds them gone.
            stillListed += dropped.map(\.id).filter { first.record(id: $0) != nil }
        }
        let old = record(age: 31 * 86_400)
        first.add(old)
        #expect(pruned == [[old.id]])
        first.add(record(age: 29 * 86_400))
        #expect(pruned == [[old.id]])
        #expect(stillListed.isEmpty)

        let second = store(retentionDays: 7)
        var prunedOnLoad: [UUID] = []
        second.didPrune = { dropped in
            prunedOnLoad = dropped.map(\.id)
            stillListed += dropped.map(\.id).filter { second.record(id: $0) != nil }
        }
        second.load()
        #expect(prunedOnLoad.count == 1)
        #expect(second.records.isEmpty)
        #expect(stillListed.isEmpty)
    }
```

and add after `pruningKeepsUploadingRecords()` (it ends at line 143):
```swift
    /// An upload-only capture whose replace failed keeps the edited bytes in `pending/` while its
    /// link still shows the original. That file is the edit's only copy, so retention keeps it.
    @Test func staleUploadOnlyEditIsNeverPruned() {
        let history = store(retentionDays: 7)
        var pruned: [UUID] = []
        history.didPrune = { pruned += $0.map(\.id) }
        let staleEdit = CaptureRecord(timestamp: now.addingTimeInterval(-30 * 86_400), fileURL: dir.appending(path: "pending/a.png"),
                                      fileIsTemporary: true, pixelWidth: 1, pixelHeight: 1, appName: nil,
                                      uploadState: .uploaded(url: URL(string: "https://snap.tky.io/a.png")!, key: "a.png"),
                                      editedAt: now.addingTimeInterval(-29 * 86_400), uploadIsStale: true)
        let notStale = CaptureRecord(timestamp: now.addingTimeInterval(-30 * 86_400), fileURL: dir.appending(path: "pending/b.png"),
                                     fileIsTemporary: true, pixelWidth: 1, pixelHeight: 1, appName: nil,
                                     uploadState: .uploaded(url: URL(string: "https://snap.tky.io/b.png")!, key: "b.png"))
        #expect(staleEdit.keepsUnuploadedEdit)
        #expect(!notStale.keepsUnuploadedEdit)

        history.add(staleEdit)
        history.add(notStale)
        #expect(history.records.map(\.id) == [staleEdit.id])
        #expect(pruned == [notStale.id])

        let reloaded = store(retentionDays: 7)
        reloaded.load()
        #expect(reloaded.records.map(\.id) == [staleEdit.id])
    }
```

- [ ] **Step 2: Run the tests to verify they fail**

Run:
```bash
xcodegen generate && xcodebuild test -project TidyShot.xcodeproj -scheme TidyShot -destination 'platform=macOS' -derivedDataPath .build 2>&1 | grep -E "Test run with|error:|TEST"
```
Expected: the test target does not compile, with errors among them `cannot find 'EditorSaveTarget' in scope`.

- [ ] **Step 3: Add the edit fields, the pruning rule and edited thumbnail names**

In `TidyShot/History/CaptureRecord.swift`, replace lines 32-38:
```swift
    /// The key a cancelled upload had reserved. Its PUT may have completed on the server as it
    /// was cancelled, so Delete removes this key too, also when a first attempt failed.
    var pendingObjectKey: String?

    init(id: UUID = UUID(), timestamp: Date = Date(), fileURL: URL?, fileIsTemporary: Bool = false,
         thumbnailFileName: String? = nil, pixelWidth: Int, pixelHeight: Int, appName: String?,
         uploadState: UploadState = .none, objectLocation: ObjectLocation? = nil, pendingObjectKey: String? = nil) {
```
with:
```swift
    /// The key a cancelled upload had reserved. Its PUT may have completed on the server as it
    /// was cancelled, so Delete removes this key too, also when a first attempt failed.
    var pendingObjectKey: String?
    /// When an edit from the editor was last written over this capture's file (Save, or the
    /// local write before an Upload). Nil for a capture never edited. A capture-time thumbnail
    /// that finishes late is not named on an edited record, because it shows the original.
    var editedAt: Date?
    /// True once an edit was written locally while the link still serves the earlier upload.
    /// The editor's subtitle then says so. Cleared when an upload of the edit succeeds.
    var uploadIsStale: Bool

    init(id: UUID = UUID(), timestamp: Date = Date(), fileURL: URL?, fileIsTemporary: Bool = false,
         thumbnailFileName: String? = nil, pixelWidth: Int, pixelHeight: Int, appName: String?,
         uploadState: UploadState = .none, objectLocation: ObjectLocation? = nil, pendingObjectKey: String? = nil,
         editedAt: Date? = nil, uploadIsStale: Bool = false) {
```
In the `init` body, after `self.pendingObjectKey = pendingObjectKey` (line 49), add:
```swift
        self.editedAt = editedAt
        self.uploadIsStale = uploadIsStale
```
In `CodingKeys` (line 54), replace `case objectLocation, pendingObjectKey` with `case objectLocation, pendingObjectKey, editedAt, uploadIsStale`. Replace the decoder's doc comment (lines 57-59) with:
```swift
    /// Phase 2 history files have no `fileIsTemporary`, `thumbnailFileName`, `objectLocation` or
    /// `pendingObjectKey`, and always have a `fileURL`; Phase 3 files have no `editedAt` or
    /// `uploadIsStale`. They decode with the defaults. Encoding is synthesised.
```
and after `pendingObjectKey = try container.decodeIfPresent(String.self, forKey: .pendingObjectKey)` (line 72) add:
```swift
        editedAt = try container.decodeIfPresent(Date.self, forKey: .editedAt)
        uploadIsStale = try container.decodeIfPresent(Bool.self, forKey: .uploadIsStale) ?? false
```
After `isPendingOnly` (line 90) add:
```swift

    /// An upload-only capture whose `pending` file holds an edit its link does not show yet (a
    /// replace that failed). The file is the edit's only copy, so retention never prunes it.
    var keepsUnuploadedEdit: Bool { fileIsTemporary && fileURL != nil && uploadIsStale }
```

In `TidyShot/History/HistoryStore.swift`, `didPrune` runs today inside `prune(_:)`, before `records` drops the pruned records (lines 60, 65-66, 71-77). `removeFiles(ofPruned:)` now pushes the editor state, which reads `history.record(id:)`, so the report moves after the assignment. Replace the `didPrune` doc (lines 13-15) with:
```swift
    /// Called with the records dropped by retention on `load()` and `add(_:)`, once `records` no
    /// longer holds them, so their thumbnails and temporary files can be removed and their
    /// editors told. Files in the user's save folder are never touched.
```
Replace lines 60-61:
```swift
        records = Self.sortedNewestFirst(prune(loaded))
        if interrupted { save() }
```
with:
```swift
        let (kept, dropped) = prune(loaded)
        records = Self.sortedNewestFirst(kept)
        if interrupted { save() }
        report(pruned: dropped)
```
Replace lines 64-78 (`add(_:)` and `prune(_:)`) with:
```swift
    func add(_ record: CaptureRecord) {
        let (kept, dropped) = prune([record] + records)
        records = Self.sortedNewestFirst(kept)
        save()
        report(pruned: dropped)
    }

    /// Splits `input` into the records retention keeps and the ones it drops.
    private func prune(_ input: [CaptureRecord]) -> (kept: [CaptureRecord], dropped: [CaptureRecord]) {
        let kept = Self.pruned(input, retentionDays: retentionDays(), now: now())
        let keptIDs = Set(kept.map(\.id))
        return (kept, input.filter { !keptIDs.contains($0.id) })
    }

    /// Tells `didPrune` about dropped records. Called after `records` was assigned, so a handler
    /// that looks one up finds it gone.
    private func report(pruned dropped: [CaptureRecord]) {
        guard !dropped.isEmpty else { return }
        didPrune?(dropped)
    }
```
Replace `pruned` (lines 112-118) with:
```swift
    /// Records newer than the retention cutoff, plus every upload-only capture that has not been
    /// uploaded (its PNG in `pending` is the only copy, so it stays until it is uploaded or
    /// deleted), every upload-only capture whose `pending` file holds an edit its link does not
    /// show yet (`keepsUnuploadedEdit`), and every record with an upload in flight (its
    /// `.uploaded` event needs the record).
    static func pruned(_ records: [CaptureRecord], retentionDays: Int, now: Date) -> [CaptureRecord] {
        let cutoff = now.addingTimeInterval(-Double(retentionDays) * 86_400)
        return records.filter { $0.timestamp >= cutoff || $0.isPendingOnly || $0.keepsUnuploadedEdit || $0.isUploading }
    }
```

In `TidyShot/History/ThumbnailStore.swift`, replace the type doc (lines 3-5) with:
```swift
/// The `thumbnails` folder next to `history.json`: one PNG per capture, named by record id, or by
/// id and edit time once an edit was saved. Thumbnails belong to the app, so the store may delete
/// them; the user's screenshots never live here.
```
and replace lines 20-34 (`fileName(for:)` and `write(_:id:)`) with:
```swift
    func fileName(for id: UUID) -> String {
        id.uuidString + ".png"
    }

    /// `<UUID>.png` for the capture itself, `<UUID>-<milliseconds since 1970>.png` for an edit
    /// saved at `editedAt`. Each save gets a new name, so Recent Captures rows (which reload on the
    /// name) refresh, and the capture-time writer, which only writes `<UUID>.png`, never
    /// overwrites an edited thumbnail.
    func fileName(for id: UUID, editedAt: Date?) -> String {
        guard let editedAt else { return fileName(for: id) }
        let milliseconds = Int64((editedAt.timeIntervalSince1970 * 1000).rounded())
        return "\(id.uuidString)-\(milliseconds).png"
    }

    func url(forFileName name: String) -> URL {
        directory.appending(path: name)
    }

    /// Writes `png` for `id` (creating the folder) and returns the file name to store in the record.
    func write(_ png: Data, id: UUID) throws -> String {
        try write(png, fileName: fileName(for: id))
    }

    /// Writes `png` as `fileName` (creating the folder) and returns that name.
    func write(_ png: Data, fileName: String) throws -> String {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try png.write(to: url(forFileName: fileName), options: .atomic)
        return fileName
    }
```

- [ ] **Step 4: Add the scoped overwrite**

In `TidyShot/Output/SaveLocation.swift`, after `readScoped(_:folder:)` (it ends at line 76), add:
```swift

    /// True when `fileURL` lies inside `folder`, at any depth. Paths are compared component by
    /// component as written, with `.` and `..` applied. Symlinks are not resolved and the file
    /// system is not consulted, so a file reached through another spelling of the folder counts
    /// as outside, which only turns Save off.
    nonisolated static func contains(_ fileURL: URL, inFolder folder: URL) -> Bool {
        guard fileURL.isFileURL, folder.isFileURL else { return false }
        let file = lexicalComponents(of: fileURL)
        let base = lexicalComponents(of: folder)
        return file.count > base.count && file.starts(with: base)
    }

    /// Replaces `fileURL` with `data` atomically, holding `folder`'s security scope for the write.
    /// Throws `CocoaError(.fileWriteNoPermission)` for a file outside `folder`, so Save over never
    /// writes anywhere else. Touches no instance state, so it runs in a detached task.
    nonisolated static func overwriteScoped(_ data: Data, at fileURL: URL, folder: URL) throws {
        guard contains(fileURL, inFolder: folder) else {
            throw CocoaError(.fileWriteNoPermission,
                             userInfo: [NSLocalizedDescriptionKey: "\(fileURL.lastPathComponent) is not in the save folder."])
        }
        let accessing = folder.startAccessingSecurityScopedResource()
        defer { if accessing { folder.stopAccessingSecurityScopedResource() } }
        try data.write(to: fileURL, options: .atomic)
    }

    /// The path's components with `.` dropped and `..` applied, from the text alone.
    nonisolated private static func lexicalComponents(of url: URL) -> [String] {
        var parts: [String] = []
        for part in url.path(percentEncoded: false).split(separator: "/") {
            switch part {
            case ".": continue
            case "..": if !parts.isEmpty { parts.removeLast() }
            default: parts.append(String(part))
            }
        }
        return parts
    }
```

- [ ] **Step 5: Add the save target, the availability table and the command gate**

`TidyShot/Editor/Persistence/EditorSaveTarget.swift`:
```swift
import Foundation

/// Where ⌘S writes an edit, decided from the record and the save folder as they are now. The
/// coordinator asks again at write time, so a folder changed in Settings or a record changed by an
/// upload never sends the bytes to the wrong file.
nonisolated enum EditorSaveTarget {
    enum Plan: Equatable, Sendable {
        /// Overwrite the file in the save folder, under that folder's security scope.
        case saveFolderFile(URL, folder: URL)
        /// Overwrite `pending/<id>.png` in place, so a later retry uploads the edit.
        case pendingFile(URL)
        /// Save is off, for this reason (the window subtitle, and the body of `Not saved`).
        case unavailable(String)
    }

    static let noFileReason = "This capture has no local file to save over."
    static let noFolderReason = "No save folder is set, so the file is not saved over."
    static let outsideFolderReason = "The file is outside the current save folder, so it is not saved over."
    static let uploadedCopyStaleNotice = "The uploaded copy still shows the original. Upload to replace it."

    static func plan(for record: CaptureRecord, saveFolder: URL?) -> Plan {
        guard let fileURL = record.fileURL else { return .unavailable(noFileReason) }
        if record.fileIsTemporary { return .pendingFile(fileURL) }
        guard let saveFolder else { return .unavailable(noFolderReason) }
        guard SaveLocation.contains(fileURL, inFolder: saveFolder) else { return .unavailable(outsideFolderReason) }
        return .saveFolderFile(fileURL, folder: saveFolder)
    }

    /// The subtitle note for an edit that was saved locally but that the link does not show yet.
    static func uploadedCopyNotice(for record: CaptureRecord) -> String? {
        record.uploadIsStale ? uploadedCopyStaleNotice : nil
    }
}

/// The editor's commands as the availability table and the shortcut gate see them.
nonisolated enum EditorAction: CaseIterable, Sendable {
    case save, saveCopy, copy, upload, uploadAsNew
}

/// What the editor may do for its record now, why not, and the window subtitle. One table feeds
/// the toolbar validation, the shortcut gate, the action methods' guard and the coordinator's
/// write-time check. A nil record was deleted or pruned.
nonisolated enum EditorAvailability {
    static let deletedStatus = "This capture was deleted. Copy and Save Copy still work."
    static let deletingStatus = "Deleting…"
    static let uploadingStatus = "Uploading…"
    static let deletedRefusal = "This capture was deleted."
    static let deletingRefusal = "This capture is being deleted."
    static let uploadingRefusal = "This capture is still uploading."
    static let notUploadedRefusal = "This capture has no link yet. Use Upload."

    static func actions(record: CaptureRecord?, saveFolder: URL?, isDeleting: Bool) -> Set<EditorAction> {
        Set(EditorAction.allCases.filter {
            refusal(for: $0, record: record, saveFolder: saveFolder, isDeleting: isDeleting) == nil
        })
    }

    /// Nil when `action` may run; otherwise the reason, posted as the body of `Not saved` or
    /// `Not uploaded`. Copy and Save Copy are never refused: they work on the editor's own image,
    /// also for a deleted, deleting or uploading record.
    static func refusal(for action: EditorAction, record: CaptureRecord?, saveFolder: URL?, isDeleting: Bool) -> String? {
        switch action {
        case .copy, .saveCopy:
            return nil
        case .save, .upload, .uploadAsNew:
            guard let record else { return deletedRefusal }
            if isDeleting { return deletingRefusal }
            if record.isUploading { return uploadingRefusal }
            if action == .save, case .unavailable(let reason) = EditorSaveTarget.plan(for: record, saveFolder: saveFolder) {
                return reason
            }
            // Task 14 changes this to `record.linkURL == nil` (`priorUpload` keeps the link of an interrupted replace).
            if action == .uploadAsNew, record.uploadedURL == nil { return notUploadedRefusal }
            return nil
        }
    }

    /// The window subtitle, or nil for none. In order: deleted, deleting, uploading, the stale-link
    /// note, then why Save is off.
    static func status(record: CaptureRecord?, saveFolder: URL?, isDeleting: Bool) -> String? {
        guard let record else { return deletedStatus }
        if isDeleting { return deletingStatus }
        if record.isUploading { return uploadingStatus }
        if let notice = EditorSaveTarget.uploadedCopyNotice(for: record) { return notice }
        if case .unavailable(let reason) = EditorSaveTarget.plan(for: record, saveFolder: saveFolder) { return reason }
        return nil
    }
}
```

`TidyShot/Editor/Persistence/EditorCommandGate.swift`:
```swift
import Foundation

/// Which editor action a selector runs, and whether the available set lets it through. Asked by
/// the controller's validation (which EditorWindow consults before sending a shortcut) and again
/// by every action method.
nonisolated enum EditorCommandGate {
    static func action(for selectorName: String) -> EditorAction? {
        switch selectorName {
        case "saveDocument:": .save
        case "saveDocumentCopy:": .saveCopy
        case "copy:", "copyImage:": .copy
        case "uploadDocument:": .upload
        case "uploadDocumentAsNew:": .uploadAsNew
        default: nil
        }
    }

    /// Selectors that are not editor actions (undo, zoom, close, select all) always pass; their
    /// own validation decides.
    static func permits(_ selectorName: String, available: Set<EditorAction>) -> Bool {
        guard let action = action(for: selectorName) else { return true }
        return available.contains(action)
    }
}
```

- [ ] **Step 6: Run the tests to verify they pass**

Run:
```bash
xcodegen generate && xcodebuild test -project TidyShot.xcodeproj -scheme TidyShot -destination 'platform=macOS' -derivedDataPath .build 2>&1 | grep -E "Test run with|error:|TEST"
```
Expected: no `error:` lines, and `Test run with 348 tests in 49 suites passed`.

- [ ] **Step 7: Coordinator: state push, folder observation, Save through `applyLocalEdit`**

All in `TidyShot/App/AppCoordinator.swift`.

`makeThumbnail(from:for:)`: replace (lines 293-298):
```swift
            guard let name else { return }
            guard let self, self.history.record(id: id) != nil else {
                store.remove(fileName: name)
                return
            }
            self.history.update(id: id) { $0.thumbnailFileName = name }
```
with:
```swift
            guard let name else { return }
            // Deleted meanwhile, or edited already: an edit names its own thumbnail
            // (`replaceThumbnail`), and this one shows the original.
            guard let self, let record = self.history.record(id: id), record.editedAt == nil else {
                store.remove(fileName: name)
                return
            }
            self.history.update(id: id) { $0.thumbnailFileName = name }
```
and in its doc comment (lines 279-280) replace `If the record was deleted in the meantime the new file is removed again.` with `If the record was deleted in the meantime, or an edit was saved since, the new file is removed again.`

`deleteCapture(recordID:)`: replace (lines 537-540):
```swift
        guard !deletingIDs.contains(recordID), let record = history.record(id: recordID) else { return }
        deletingIDs.insert(recordID)
        defer { deletingIDs.remove(recordID) }
        guard confirmDelete(of: record) else { return }
```
with:
```swift
        guard !deletingIDs.contains(recordID), let record = history.record(id: recordID) else { return }
        deletingIDs.insert(recordID)
        // The record's editor drops Save and Upload before the alert shows, through
        // `cancelUpload`, `deleteObjects` and the second alert, and learns the outcome either way.
        pushEditorState(for: recordID)
        defer {
            deletingIDs.remove(recordID)
            pushEditorState(for: recordID)
        }
        guard confirmDelete(of: record) else { return }
```

`removeRecord(id:)`: replace (lines 663-665):
```swift
        history.remove(id: id)
        thumbnailProvider.forget(id)
        overlay.close(recordID: id)
```
with:
```swift
        history.remove(id: id)
        thumbnailProvider.forget(id)
        overlay.close(recordID: id)
        pushEditorState(for: id)
```

`removeFiles(ofPruned:)`: replace lines 723-735 with:
```swift
    /// Thumbnails and temporary files of records dropped by retention, and their editors told the
    /// record is gone (`didPrune` runs after the store dropped them). Files in the save folder are
    /// left alone. (A record whose temporary file is its only copy, or holds an edit its link does
    /// not show yet, is never pruned.)
    private func removeFiles(ofPruned records: [CaptureRecord]) {
        for record in records {
            thumbnailProvider.forget(record.id)
            if let name = record.thumbnailFileName {
                thumbnails.remove(fileName: name)
            }
            if record.fileIsTemporary, let fileURL = record.fileURL {
                removePendingFile(at: fileURL, context: "after pruning")
            }
            pushEditorState(for: record.id)
        }
    }
```

`refreshOverlay(for:)`: replace lines 746-751 with:
```swift
    /// Pushes the record's current state into the overlay, if the overlay is showing it, and into
    /// the record's editor, so every upload progress, success, failure and retry reaches both.
    private func refreshOverlay(for id: UUID) {
        if let record = history.record(id: id) {
            overlay.update(record: record)
        }
        pushEditorState(for: id)
    }
```

Under `// MARK: Editor`, next to `editors` (4a-10), add the stored flag:
```swift
    /// True while a save-folder observation is registered (`observeSaveFolderForEditors`).
    @ObservationIgnored private var isObservingSaveFolder = false
```

In `showEditor(recordID:image:)` (4a-10), right after `editors[recordID] = controller` and before `controller.present()`, add:
```swift
        pushEditorState(for: recordID)
        observeSaveFolderForEditors()
```
In `editorActions(for recordID:)` (4a-10), the one place the `EditorActions` closures are built, replace the `save:` stub with:
```swift
            save: { [weak self] image in await self?.editorSave(recordID: recordID, image: image) ?? false },
```
At the top of `editorSaveCopy(of:image:)` (4a-12), add the write-time check. It never refuses today (Save Copy works for a deleted, deleting or uploading original); it keeps the three editor writes on one table:
```swift
        if let reason = EditorAvailability.refusal(for: .saveCopy, record: history.record(id: recordID),
                                                   saveFolder: saveLocation.currentURL,
                                                   isDeleting: deletingIDs.contains(recordID)) {
            notifier.notifyError(reason, title: "Not saved")
            return false
        }
```

Then add, under `// MARK: Editor`:
```swift
    /// Tells the record's open editor, if any, what it may do now: the record as it is (nil once
    /// deleted or pruned), the save folder and whether a delete is running.
    private func pushEditorState(for id: UUID) {
        editors[id]?.recordDidChange(history.record(id: id), saveFolder: saveLocation.currentURL,
                                     isDeleting: deletingIDs.contains(id))
    }

    /// While any editor is open, pushes every editor's state when the save folder changes, so Save
    /// and the subtitle follow a folder chosen in Settings. Observation calls `onChange` once per
    /// registration, before the value changes, so the push is scheduled and registers again (as
    /// StatusMenuController.updateIcon does). With no editor left it stops re-registering; the flag
    /// keeps an editor opened while a registration is pending from adding a second one. Save stays
    /// safe without this push, because `applyLocalEdit` plans from the folder at write time.
    private func observeSaveFolderForEditors() {
        guard !isObservingSaveFolder, !editors.isEmpty else { return }
        isObservingSaveFolder = true
        withObservationTracking {
            _ = saveLocation.currentURL
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.isObservingSaveFolder = false
                for id in self.editors.keys {
                    self.pushEditorState(for: id)
                }
                self.observeSaveFolderForEditors()
            }
        }
    }

    /// ⌘S: encodes the edit off the main actor and saves it over the capture's own file through
    /// `applyLocalEdit`. Never touches the network.
    private func editorSave(recordID: UUID, image: ScaledImage) async -> Bool {
        if let reason = EditorAvailability.refusal(for: .save, record: history.record(id: recordID),
                                                   saveFolder: saveLocation.currentURL,
                                                   isDeleting: deletingIDs.contains(recordID)) {
            notifier.notifyError(reason, title: "Not saved")
            return false
        }
        let png: Data
        do {
            png = try await Task.detached(priority: .userInitiated) {
                try ImageEncoder.pngData(from: image.image, scale: image.scale)
            }.value
        } catch {
            keepFailedEditOnClipboard(image, png: nil, recordID: recordID, error: error)
            return false
        }
        return await applyLocalEdit(recordID: recordID, png: png, image: image)
    }

    /// The one local-edit path, for Save and for the local write before an editor Upload. It
    /// re-checks the live record and `deletingIDs` (a Save racing a delete writes nothing), writes
    /// the PNG to the target `EditorSaveTarget.plan` picks now, records the edit, replaces the
    /// thumbnail, applies the clipboard rule and pushes the editor's state. Returns false, with
    /// `Not saved` posted, when nothing was written.
    private func applyLocalEdit(recordID: UUID, png: Data, image: ScaledImage) async -> Bool {
        let folder = saveLocation.currentURL
        let live = history.record(id: recordID)
        if let reason = EditorAvailability.refusal(for: .save, record: live, saveFolder: folder,
                                                   isDeleting: deletingIDs.contains(recordID)) {
            notifier.notifyError(reason, title: "Not saved")
            return false
        }
        guard let live else { return false }
        do {
            switch EditorSaveTarget.plan(for: live, saveFolder: folder) {
            case .saveFolderFile(let fileURL, let scope):
                try await Task.detached(priority: .userInitiated) {
                    try SaveLocation.overwriteScoped(png, at: fileURL, folder: scope)
                }.value
            case .pendingFile:
                // Always `pending/<id>.png`, replaced in place, so a retry uploads the edit.
                _ = try pendingFiles.write(png, id: recordID, ext: "png")
            case .unavailable(let reason):
                // The refusal above already covers this; kept so the switch stays total.
                notifier.notifyError(reason, title: "Not saved")
                return false
            }
        } catch {
            keepFailedEditOnClipboard(image, png: png, recordID: recordID, error: error)
            return false
        }
        let editedAt = Date()
        history.update(id: recordID) { record in
            record.pixelWidth = image.image.width
            record.pixelHeight = image.image.height
            record.editedAt = editedAt
            // Task 14 changes this to `record.linkURL != nil`, so a record whose replace was
            // interrupted (link in `priorUpload`) is marked stale too (spec 2.6 step 4).
            if record.uploadedURL != nil {
                record.uploadIsStale = true
            }
        }
        replaceThumbnail(for: recordID, from: image.image, editedAt: editedAt)
        await replaceClipboardIfStillOriginal(recordID: recordID, png: png, image: image)
        pushEditorState(for: recordID)
        return true
    }

    /// A save that failed: the edit goes on the clipboard, so it is never lost, and `Not saved`
    /// says why. TidyShot put it there for this record, so the record owns the clipboard and a
    /// later successful save may replace it (the clipboard rule).
    private func keepFailedEditOnClipboard(_ image: ScaledImage, png: Data?, recordID: UUID, error: any Error) {
        NSLog("Save over failed: \(error.localizedDescription)")
        let changeCount = if let png {
            Pasteboard.copy(image: image.image, pngData: png, scale: image.scale)
        } else {
            Pasteboard.copy(image: image.image, scale: image.scale)
        }
        clipboardOwner = EditorClipboard.Owner(recordID: recordID, changeCount: changeCount)
        notifier.notifyError("\(error.localizedDescription) The edited image is on the clipboard.", title: "Not saved")
    }

    /// Makes the edited capture's thumbnail on a detached task and names it on the record under a
    /// new name, so Recent Captures rows reload; then drops the provider's cached images and
    /// removes the previous file. `forget` runs here, as the name changes, not before: a row that
    /// reloaded earlier would cache the old thumbnail again. A later save, a delete or a prune that
    /// got there first wins, and the new file is removed. When no thumbnail could be made the
    /// record names none, so `ThumbnailProvider` makes one from the edited file instead of showing
    /// the original.
    private func replaceThumbnail(for id: UUID, from image: CGImage, editedAt: Date) {
        let store = thumbnails
        let name = store.fileName(for: id, editedAt: editedAt)
        Task { [weak self] in
            let written = await Task.detached(priority: .utility) { () -> Bool in
                do {
                    guard let small = ThumbnailMaker.thumbnail(from: image) else { return false }
                    _ = try store.write(try ThumbnailMaker.pngData(small), fileName: name)
                    return true
                } catch {
                    NSLog("Edited thumbnail failed: \(error.localizedDescription)")
                    return false
                }
            }.value
            guard let self, let record = self.history.record(id: id), record.editedAt == editedAt else {
                if written { store.remove(fileName: name) }
                return
            }
            let previous = record.thumbnailFileName
            self.history.update(id: id) { $0.thumbnailFileName = written ? name : nil }
            self.thumbnailProvider.forget(id)
            if let previous, previous != name {
                store.remove(fileName: previous)
            }
        }
    }
```

- [ ] **Step 8: Editor window: available set, gate, subtitle, Save**

In `TidyShot/Editor/Window/EditorWindowController.swift`. The structure, names and behaviour are fixed; the code below is the non-obvious part.

Add the state and the push target:
```swift
    /// What the editor may do now. Empty until the coordinator's first push, which showEditor
    /// sends before the window shows.
    private(set) var available: Set<EditorAction> = []

    /// The coordinator's push (`pushEditorState`): the record as it is now (nil once deleted or
    /// pruned), the save folder, and whether a delete is running.
    func recordDidChange(_ record: CaptureRecord?, saveFolder: URL?, isDeleting: Bool) {
        let allowed = EditorAvailability.actions(record: record, saveFolder: saveFolder, isDeleting: isDeleting)
        if allowed != available {
            available = allowed
            reflectSaveAvailability()
            window?.toolbar?.validateVisibleItems()
        }
        let status = EditorAvailability.status(record: record, saveFolder: saveFolder, isDeleting: isDeleting) ?? ""
        if window?.subtitle != status {
            window?.subtitle = status
        }
    }

    /// The second guard: an action whose EditorAction is not available returns at once, whatever
    /// sent it (a menu, a toolbar item, or a shortcut that got past validation).
    private func permits(_ selector: Selector) -> Bool {
        EditorCommandGate.permits(NSStringFromSelector(selector), available: available)
    }
```

Put `func reflectSaveAvailability()` in the `EditorWindowController` extension in `TidyShot/Editor/Window/EditorToolbar.swift` (Task 11), next to `reflectTool(_:)`, so it can use that file's `private func toolbarItem(_:)` (`toolbarItem(.save)`). It reads `available` (internal `private(set)`). Cast the item with `as? NSMenuToolbarItem`, then set `action` to `#selector(saveDocumentCopy(_:))` or `#selector(saveDocument(_:))`, and set `label` and `toolTip` to `Save Copy…` or `Save`.

`reflectSaveAvailability()`: disabling the `.save` `NSMenuToolbarItem` would also disable its Save Copy… menu, and Save Copy must remain. So while `available` lacks `.save`, the item with identifier `.save` gets action `saveDocumentCopy(_:)`, and label and tool tip `Save Copy…`. When Save is back it gets `saveDocument(_:)` and `Save` again. Validation then enables it, because `saveDocumentCopy:` is always permitted.

`validateUserInterfaceItem(_:)`: make this its first statement, ahead of the checks 4a-10 and 4a-11 put there:
```swift
        if let action = item.action, !permits(action) { return false }
```
The toolbar items, their menus and EditorWindow's `ShortcutItem` all reach this method, so ⌘S, ⌘U and ⌥⌘U beep while their action is missing.

Make `guard permits(#selector(<the method's own selector>)) else { return }` the first statement of `saveDocument(_:)`, `saveDocumentCopy(_:)`, `copy(_:)`, `copyImage(_:)`, `uploadDocument(_:)` and `uploadDocumentAsNew(_:)`. For example, `guard permits(#selector(saveDocument(_:))) else { return }`.

Save and Save Copy keep 4a-10's export path: no second helper is added. After the `permits` guard, `saveDocument(_:)` is `runDocumentAction(marksSaved: true) { await self.actions.save($0) }` and `saveDocumentCopy(_:)` is `runDocumentAction(marksSaved: true) { await self.actions.saveCopy($0) }`, exactly the bodies 4a-10 wrote. The bodies of `copy(_:)`, `copyImage(_:)`, `uploadDocument(_:)` and `uploadDocumentAsNew(_:)` are unchanged apart from the guard. So the one-at-a-time rule (`isPerformingAction`, which makes a second ⌘S beep and validation refuse it), the beep and log on a failed export, and the markSaved-if-unchanged snapshot stay as 4a-10 specified, for all six actions.

`askToSaveBeforeClosing()` (4a-10) needs no code change. Its `canSave` comes from `validateUserInterfaceItem(ShortcutItem(action: #selector(saveDocument(_:))))`, and that method now checks `permits(_:)` first. So when `available` lacks `.save`, `canSave` is false, the first button reads `Save Copy…` and uses `actions.saveCopy`. The existing `isPerformingAction = true` and `exportAndDeliver` call stay, so the window closes only after the edit was kept. Cancel and Don’t Save (⌘D) are unchanged.

- [ ] **Step 9: Build, run the tests, and check by hand**

Run:
```bash
xcodegen generate && xcodebuild test -project TidyShot.xcodeproj -scheme TidyShot -destination 'platform=macOS' -derivedDataPath .build 2>&1 | grep -E "Test run with|error:|TEST"
```
Expected: no `error:` lines, and `Test run with 348 tests in 49 suites passed`.

Then:
```bash
xcodebuild -project TidyShot.xcodeproj -scheme TidyShot -configuration Debug -derivedDataPath .build build -quiet && open .build/Build/Products/Debug/TidyShot.app
```
Until 4a-16, open the editor with the status menu's `Annotate Last Capture (debug)`, which opens the newest capture. The container is `~/Library/Containers/io.tky.tidyshot/Data/Library/Application Support/TidyShot`.
1. Save mode with Copy image on. Capture some text, open the editor, Redact the text, press ⌘S. Expected: the close button's dot clears. The file in the save folder shows the redaction in Preview. The Recent Captures thumbnail shows it a moment later. `thumbnails/` holds `<id>-<milliseconds>.png` and no `<id>.png`. ⌘V in Preview pastes the redacted image.
2. Copy a word in TextEdit, Redact again, press ⌘S. Expected: the word is still on the clipboard.
3. Upload-only mode with no destination set. Capture, edit, press ⌘S. Expected: the record stays failed, and `pending/<id>.png` shows the edit.
4. Upload-only mode with a destination. When the upload has finished, open the editor. Expected: the subtitle reads `This capture has no local file to save over.`, the toolbar's Save item is Save Copy…, and ⌘S beeps.
5. Upload mode with a destination. Open the editor while a large capture uploads (use a slow Network Link Conditioner profile if needed). Expected: the subtitle reads `Uploading…`, ⌘S beeps, and Save and Upload are disabled. After the upload, the subtitle clears and Save is back. Then press ⌘S. Expected: the subtitle reads `The uploaded copy still shows the original. Upload to replace it.`, and `history.json` shows `editedAt` and `"uploadIsStale" : true` for the record.
6. With an editor open, choose Delete… on its Recent Captures row and leave the alert open. Expected: the editor's subtitle reads `Deleting…`, and Save and Upload are disabled. Cancel. Expected: they return and the subtitle clears. Delete again and confirm. Expected: the subtitle reads `This capture was deleted. Copy and Save Copy still work.`, ⌘S beeps, and ⇧⌘S adds a new capture.
7. With an editor open on a Save-mode capture, use Settings > General > Choose… to pick another folder. Expected: at once the Save item becomes Save Copy… and the subtitle reads `The file is outside the current save folder, so it is not saved over.` Choose the old folder again. Expected: Save is back.
8. Run `chmod a-w` on the save folder, edit, press ⌘S. Expected: a `Not saved` notification ending `The edited image is on the clipboard.`, the edit pastes in Preview, and the close button keeps its dot. Run `chmod u+w` on the folder; ⌘S then saves.
9. Retention. This needs the newest capture to be more than a day old; otherwise run it after 4a Task 16 adds Annotate to Recent Captures rows. Open the editor on that capture, set Settings > Keep history for 1 day, take a capture. Expected: the open editor's subtitle reads `This capture was deleted. Copy and Save Copy still work.`
10. One at a time. In a Save-mode capture, press ⌘S twice quickly, and ⌘S during ⇧⌘S. Expected: no second file (`… 2.png`) appears, and the extra press beeps (4a-10's guard still applies to Save and Save Copy).

- [ ] **Step 10: Commit**

```bash
git add TidyShot/Editor/Persistence/EditorSaveTarget.swift TidyShot/Editor/Persistence/EditorCommandGate.swift \
  TidyShot/Output/SaveLocation.swift TidyShot/History/CaptureRecord.swift TidyShot/History/HistoryStore.swift \
  TidyShot/History/ThumbnailStore.swift TidyShot/App/AppCoordinator.swift TidyShot/Editor/Window/EditorWindowController.swift \
  TidyShotTests/EditorSaveTargetTests.swift TidyShotTests/SaveLocationOverwriteTests.swift TidyShotTests/CaptureRecordTests.swift \
  TidyShotTests/ThumbnailStoreTests.swift TidyShotTests/HistoryStoreTests.swift
git commit -m "feat: save over from the editor"
```

### Task 14: Fixed-key uploads, Cache-Control, superseded objects and a persisted prior upload

This task adds the storage half of the editor's Upload, and nothing calls it yet: Task 15 starts fixed-key uploads, sets `priorUpload` and fills `supersededObjects`. Template uploads behave exactly as before, and the 16 existing UploadQueueTests pass unchanged. Delete, the shared-key checks, Copy URL, Upload as New's availability and the local-edit staleness rule learn about the new record fields now, so they are correct from the first record Task 15 writes, including one left by a quit in the middle of a replace. The last two are edits to Task 13's code, which cannot name `linkURL` before this task adds it (Step 6).

Line numbers are at f4541da. Tasks 10, 12 and 13 edit `AppCoordinator.swift` before this task, Task 13 edits `CaptureRecord.swift`, `CaptureRecordTests.swift` and `HistoryStoreTests.swift`, and Task 13 creates `EditorSaveTarget.swift` and `EditorSaveTargetTests.swift`. Find those spots by the quoted text.

**Files:**
- Modify: `TidyShot/Upload/Destination.swift` (the `upload` requirement at lines 9-11, `UploadJob` at 20-38, and the `.cancelled` doc at 45-47)
- Modify: `TidyShot/Upload/UploadQueue.swift` (the type doc at 3-5, the `CancelResult.stopped` doc at 15-18, the `reservedKeys` doc at 41, `process(_:)` at 105-111, and a new `objectKey(for:)` before `reserveKey` at 149)
- Modify: `TidyShot/Upload/S3Destination.swift` (`upload` at 56-62)
- Modify: `TidyShot/Upload/ObjectLocation.swift` (Hashable at line 6, and a new `ObjectRef`)
- Modify: `TidyShot/History/CaptureRecord.swift` (properties after 34, init at 36-50, CodingKeys at 52-55, `init(from:)` at 57-73, `linkURL` after 84, `recordLocalEdit` after it, and a new `PriorUpload` at the end)
- Modify: `TidyShot/History/CaptureDeletion.swift` (`objectKeys` doc at 17-19, `sharedKeys` at 28-37, `confirmationText` at 39-55, and the new `objects(for:)` and `grouped(_:)`)
- Modify: `TidyShot/RecentCaptures/RecentCaptureFormatting.swift` (`canCopyLink` at 27-30)
- Modify: `TidyShot/Editor/Persistence/EditorSaveTarget.swift` (Task 13: `EditorAvailability.refusal`, the `uploadAsNew` line)
- Modify: `TidyShot/App/AppCoordinator.swift` (`copyLinkOrFile` and `copyLink` at 442-457, `deleteCapture` doc at 528-535 and its storage step at 547-562, and Task 13's `applyLocalEdit`, whose `history.update` closure sets `uploadIsStale`)
- Test: `TidyShotTests/UploadQueueTests.swift` (FakeDestination at 8-79, six new tests)
- Test: `TidyShotTests/S3DestinationTests.swift` (two new tests)
- Test: `TidyShotTests/CaptureRecordTests.swift` (six new tests)
- Test: `TidyShotTests/EditorSaveTargetTests.swift` (Task 13's file, one new test)
- Test: `TidyShotTests/CaptureDeletionTests.swift` (the `record` helper at 10-14, five new tests)
- Test: `TidyShotTests/HistoryStoreTests.swift` (one new test)
- Test: `TidyShotTests/RecentCaptureFormattingTests.swift` (one new test)

**Interfaces:**
- Consumes:
  - `UploadJob.init(id:data:contentType:fileExtension:naming:)` and its stored `naming: TemplateContext` (Destination.swift:29-37). The queue reads `job.naming` at UploadQueue.swift:105, and the coordinator builds the job at AppCoordinator.swift:393-394.
  - `UploadQueue`'s `private var reservedKeys: [UUID: String]` (UploadQueue.swift:42) and `private func reserveKey(ext: String, context: TemplateContext) async throws -> String` (UploadQueue.swift:150).
  - `S3Destination.signedRequest(method:key:body:extraHeaders:) throws -> URLRequest` (S3Destination.swift:99), which signs every header in `extraHeaders`.
  - `CaptureDeletion.objectKeys(for:) -> [String]` (CaptureDeletion.swift:20) and `sharedKeys(_:at:with:) -> [String]` (CaptureDeletion.swift:31). Today both look only at `uploadedKey` and `pendingObjectKey` at `objectLocation`.
  - `HistoryStore.load()` (HistoryStore.swift:40), which turns `.uploading` into `.failed(message: "Upload was interrupted.")` and saves (HistoryStore.swift:55-61). It needs no change.
  - In AppCoordinator: `deleteCapture(recordID:) async` (AppCoordinator.swift:536), `private func deleteObjects(_ keys: [String], at location: ObjectLocation) async -> String?` (604), `copyLinkOrFile(recordID:)` (443) and `copyLink(recordID:)` (454), both of which read `record.uploadedURL` today. `deleteOrphanedObject(key:at:)` (821) calls `sharedKeys` and gets the wider check without an edit.
  - `RecentCaptureFormatting.canCopyLink(_:) -> Bool` (RecentCaptureFormatting.swift:28), which today returns `record.uploadedURL != nil`.
  - From Task 13: `CaptureRecord.editedAt: Date?` and `uploadIsStale: Bool`, with their CodingKeys, `decodeIfPresent` lines and defaulted init parameters. This task's CaptureRecord additions go after them.
- Produces:
  - `nonisolated struct UploadJob: Sendable, Identifiable` gains:
    - `enum KeyPolicy: Sendable, Equatable { case template(TemplateContext); case fixed(String) }`;
    - `let key: KeyPolicy` (it replaces the stored `naming`);
    - `let cacheControl: String?`;
    - `init(id: UUID, data: Data, contentType: String, fileExtension: String, fixedKey: String, cacheControl: String? = "no-cache")`.
    The existing `init(id:data:contentType:fileExtension:naming:)` keeps its signature and sets `.template(naming)` with `cacheControl` nil.
  - `Destination` requirement: `func upload(_ data: Data, key: String, contentType: String, cacheControl: String?, progress: @escaping @Sendable (Double) -> Void) async throws`. A protocol extension keeps `nonisolated func upload(_ data: Data, key: String, contentType: String, progress: @escaping @Sendable (Double) -> Void) async throws`, which forwards `cacheControl: nil`.
  - `S3Destination.upload(_:key:contentType:cacheControl:progress:)` sends a non-nil `cacheControl` as the signed header `cache-control`.
  - `UploadQueue.process(_:)`: for `.fixed` it skips `reserveKey` and HEAD, sets `reservedKeys[id]` to the key, PUTs the same key on every retry and never consults the key namer. `private func objectKey(for job: UploadJob) async throws -> String`.
  - `nonisolated struct ObjectLocation: Codable, Hashable, Sendable`.
  - `nonisolated struct ObjectRef: Codable, Hashable, Sendable { var key: String; var location: ObjectLocation }` (ObjectLocation.swift).
  - `nonisolated struct PriorUpload: Codable, Equatable, Sendable { var url: URL; var key: String; var location: ObjectLocation; var isReplace: Bool }` (CaptureRecord.swift).
  - `CaptureRecord`:
    - `var supersededObjects: [ObjectRef]` (`decodeIfPresent`, default `[]`);
    - `var priorUpload: PriorUpload?` (`decodeIfPresent`, default nil);
    - init parameters `supersededObjects: [ObjectRef] = [], priorUpload: PriorUpload? = nil`, after Task 13's;
    - `var linkURL: URL? { uploadedURL ?? priorUpload?.url }`. `uploadedURL` and `uploadedKey` are unchanged;
    - `mutating func recordLocalEdit(pixelWidth: Int, pixelHeight: Int, at editedAt: Date)`: sets the pixel size and `editedAt`, and sets `uploadIsStale = true` when `linkURL != nil`. Task 13's `applyLocalEdit` calls it, so a record whose link lives only in `priorUpload` is marked stale too.
  - `CaptureDeletion`:
    - `static func objects(for record: CaptureRecord) -> [ObjectRef]`;
    - `static func grouped(_ objects: [ObjectRef]) -> [(location: ObjectLocation, keys: [String])]`;
    - `sharedKeys(_:at:with:)` keeps its signature and matches every object `objects(for:)` lists for another record;
    - `confirmationText(for:)` counts any listed object as storage.
  - `EditorAvailability.refusal` refuses `.uploadAsNew` with `notUploadedRefusal` only when `record.linkURL == nil`, so a record with an interrupted or failed replace (`.failed`, link in `priorUpload`) keeps Upload as New.
  - `RecentCaptureFormatting.canCopyLink(_:)` returns `record.linkURL != nil`. `AppCoordinator.copyLink(recordID:)` and `copyLinkOrFile(recordID:)` read `record.linkURL`.
  - `deleteCapture` deletes one location group at a time, checking shared keys per group, and reports every kept key through `notifyKept`.

- [ ] **Step 1: Write the failing tests**

In `TidyShotTests/UploadQueueTests.swift`, FakeDestination adopts the new requirement, records `cacheControl` with each upload, and records the key of every attempt.

Replace (lines 13-15):
```swift
        var uploads: [(key: String, data: Data, contentType: String)] = []
        /// Every call to `upload`, including ones that throw.
        var uploadAttempts = 0
```
with:
```swift
        var uploads: [(key: String, data: Data, contentType: String, cacheControl: String?)] = []
        /// Every call to `upload`, including ones that throw.
        var uploadAttempts = 0
        /// The key of every call to `upload`, including ones that throw, in order.
        var attemptKeys: [String] = []
```

Replace (lines 41-43):
```swift
    func upload(_ data: Data, key: String, contentType: String, progress: @escaping @Sendable (Double) -> Void) async throws {
        let failure: UploadError? = state.withLock {
            $0.uploadAttempts += 1
```
with:
```swift
    func upload(_ data: Data, key: String, contentType: String, cacheControl: String?,
                progress: @escaping @Sendable (Double) -> Void) async throws {
        let failure: UploadError? = state.withLock {
            $0.uploadAttempts += 1
            $0.attemptKeys.append(key)
```

Replace (line 78):
```swift
        state.withLock { $0.uploads.append((key, data, contentType)) }
```
with:
```swift
        state.withLock { $0.uploads.append((key, data, contentType, cacheControl)) }
```

In `struct UploadQueueTests`, after `let data = Data("png".utf8)` (line 120), add:
```swift
    let fixedKey = "shots/2026/10/aB3dE9.png"
    let fixedURL = URL(string: "https://snap.tky.io/shots/2026/10/aB3dE9.png")!
```

Append these tests inside `struct UploadQueueTests`, after `processesJobsInOrderOneAtATime` (line 414):
```swift
    /// A fixed key is the record's own key at its own location, so the queue sends no HEAD. The
    /// existing initialiser still names its key from the template.
    @Test func fixedKeyJobSkipsHEAD() async throws {
        let naming = TemplateContext(date: Date(timeIntervalSince1970: 1_792_411_200), counter: 3, hostname: "miffle")
        #expect(UploadJob(id: UUID(), data: data, contentType: "image/png", fileExtension: "png", naming: naming).key
                == .template(naming))
        #expect(UploadJob(id: UUID(), data: data, contentType: "image/png", fileExtension: "png", fixedKey: fixedKey).key
                == .fixed(fixedKey))

        let destination = FakeDestination()
        let log = EventLog()
        let queue = makeQueue(destination: destination, log: log)
        let id = UUID()

        await queue.enqueue(UploadJob(id: id, data: data, contentType: "image/png", fileExtension: "png", fixedKey: fixedKey))
        try await eventually { log.events.contains(.uploaded(id: id, url: fixedURL, key: fixedKey)) }

        #expect(log.events.first == .started(id: id, attempt: 1))
        #expect(destination.state.withLock { $0.headKeys } == [])
        #expect(destination.state.withLock { state in state.uploads.map { $0.key } } == [fixedKey])
    }

    /// HEAD would find the record's own object and steer the replace to a new key. A fixed key
    /// overwrites the object that is there.
    @Test func fixedKeyPutsExactKeyEvenWhenItExists() async throws {
        let destination = FakeDestination(.init(existingKeys: [fixedKey]))
        let log = EventLog()
        let queue = makeQueue(destination: destination, log: log)
        let id = UUID()

        await queue.enqueue(UploadJob(id: id, data: data, contentType: "image/png", fileExtension: "png", fixedKey: fixedKey))
        try await eventually { log.events.contains(.uploaded(id: id, url: fixedURL, key: fixedKey)) }

        #expect(destination.state.withLock { state in state.uploads.map { $0.key } } == [fixedKey])
        #expect(destination.state.withLock { $0.headKeys } == [])
    }

    /// Every attempt PUTs the same key, so a retried replace keeps the URL.
    @Test func fixedKeyRetryReusesKey() async throws {
        let destination = FakeDestination(.init(failuresRemaining: 2, failure: .httpStatus(503, body: "")))
        let log = EventLog()
        let queue = makeQueue(destination: destination, log: log)
        let id = UUID()

        await queue.enqueue(UploadJob(id: id, data: data, contentType: "image/png", fileExtension: "png", fixedKey: fixedKey))
        try await eventually { log.events.contains(.uploaded(id: id, url: fixedURL, key: fixedKey)) }

        let starts = log.events.filter { if case .started = $0 { return true } else { return false } }
        #expect(starts == [.started(id: id, attempt: 1), .started(id: id, attempt: 2), .started(id: id, attempt: 3)])
        #expect(destination.state.withLock { $0.attemptKeys } == [fixedKey, fixedKey, fixedKey])
        #expect(destination.state.withLock { $0.headKeys } == [])
    }

    /// Delete cancels an in-flight replace and must learn its key, because the PUT may have landed.
    @Test func cancelOfFixedKeyJobReportsThatKey() async throws {
        let destination = FakeDestination(.init(blockingUploadsRemaining: 1))
        let log = EventLog()
        let queue = makeQueue(destination: destination, log: log)
        let id = UUID()

        await queue.enqueue(UploadJob(id: id, data: data, contentType: "image/png", fileExtension: "png", fixedKey: fixedKey))
        try await eventually { destination.state.withLock { $0.uploadAttempts } == 1 }

        #expect(await queue.cancel(recordID: id) == .stopped(reservedKey: fixedKey))
        #expect(log.events == [.started(id: id, attempt: 1), .cancelled(id: id, reservedKey: fixedKey)])
        try await eventually { await queue.isIdle }
        #expect(destination.state.withLock { $0.uploads.isEmpty })
    }

    /// The coordinator draws a `{counter}` only for template jobs. The queue never expands the
    /// template for a fixed key, so nothing is drawn from the key namer. The template job after it
    /// uses the same namer, which shows that the zero is not vacuous.
    @Test func fixedKeyDrawsNoCounter() async throws {
        let draws = Mutex(0)
        let destination = FakeDestination()
        let log = EventLog()
        let queue = UploadQueue(destination: destination,
                                keyNamer: ObjectKeyNamer(template: "{counter}-{random}", randomString: { length in
                                    draws.withLock { $0 += 1 }
                                    return String(repeating: "K", count: length)
                                }),
                                policy: .immediate, sleep: { _ in }, events: { log.events.append($0) })
        let fixed = UUID()
        let template = UUID()

        await queue.enqueue(UploadJob(id: fixed, data: data, contentType: "image/png", fileExtension: "png", fixedKey: fixedKey))
        try await eventually { log.events.contains(.uploaded(id: fixed, url: fixedURL, key: fixedKey)) }
        #expect(draws.withLock { $0 } == 0)

        let naming = TemplateContext(date: Date(timeIntervalSince1970: 1_792_411_200), counter: 7, hostname: "miffle")
        await queue.enqueue(UploadJob(id: template, data: data, contentType: "image/png", fileExtension: "png", naming: naming))
        try await eventually { log.events.contains(.uploaded(id: template, url: URL(string: "https://snap.tky.io/7-KKKKKK.png")!,
                                                              key: "7-KKKKKK.png")) }
        #expect(draws.withLock { $0 } == 1)
    }

    /// A replace sends `Cache-Control: no-cache` by default. A template job sends none.
    @Test func fixedKeyPassesCacheControl() async throws {
        #expect(UploadJob(id: UUID(), data: data, contentType: "image/png", fileExtension: "png", fixedKey: fixedKey).cacheControl
                == "no-cache")
        #expect(UploadJob(id: UUID(), data: data, contentType: "image/png", fileExtension: "png", fixedKey: fixedKey,
                          cacheControl: nil).cacheControl == nil)
        #expect(UploadJob(id: UUID(), data: data, contentType: "image/png", fileExtension: "png").cacheControl == nil)

        let destination = FakeDestination()
        let log = EventLog()
        let queue = makeQueue(destination: destination, log: log)
        let fixed = UUID()
        let template = UUID()

        await queue.enqueue(UploadJob(id: fixed, data: data, contentType: "image/png", fileExtension: "png", fixedKey: fixedKey))
        await queue.enqueue(UploadJob(id: template, data: data, contentType: "image/png", fileExtension: "png"))
        try await eventually { log.events.filter { if case .uploaded = $0 { return true } else { return false } }.count == 2 }

        let uploads = destination.state.withLock { $0.uploads }
        #expect(uploads.map { $0.key } == [fixedKey, "s/KKKKKK.png"])
        #expect(uploads.map { $0.cacheControl } == ["no-cache", nil])
    }
```

In `TidyShotTests/S3DestinationTests.swift`, add after `aclHeaderIsSentAndSignedWhenEnabled` (line 128). The signature was computed with an independent SigV4 script, which also reproduces the two existing PUT signatures (`3ae54c07…` and `5a73cf67…`):
```swift
    /// A replace asks caches to revalidate. The header is signed like the ACL. Expected signature
    /// computed independently with a reference implementation.
    @Test func cacheControlHeaderIsSignedWhenSet() async throws {
        let (session, stub) = StubSession.make { _ in (200, Data()) }
        try await destination(config, session: session).upload(body, key: "aSIS7.png", contentType: "image/png",
                                                               cacheControl: "no-cache") { _ in }

        let request = try #require(stub.requests.first)
        #expect(request.httpMethod == "PUT")
        #expect(request.value(forHTTPHeaderField: "cache-control") == "no-cache")
        #expect(request.value(forHTTPHeaderField: "content-type") == "image/png")
        #expect(request.value(forHTTPHeaderField: "authorization") == "AWS4-HMAC-SHA256 Credential=AKIAIOSFODNN7EXAMPLE/20261019/us-east-1/s3/aws4_request, SignedHeaders=cache-control;content-type;host;x-amz-content-sha256;x-amz-date, Signature=fe15f0f7a62489905cb08be4bc4e9e1e48bbfe919082923c2815b55b122d49ed")
    }

    /// The four-argument call (template uploads, the connection test) and an explicit nil send no
    /// Cache-Control and do not sign one.
    @Test func noCacheControlByDefault() async throws {
        let (session, stub) = StubSession.make { _ in (200, Data()) }
        try await destination(config, session: session).upload(body, key: "aSIS7.png", contentType: "image/png") { _ in }
        let request = try #require(stub.requests.first)
        #expect(request.value(forHTTPHeaderField: "cache-control") == nil)
        #expect(request.value(forHTTPHeaderField: "authorization")?.contains("SignedHeaders=content-type;host;x-amz-content-sha256;x-amz-date,") == true)

        let (explicitSession, explicitStub) = StubSession.make { _ in (200, Data()) }
        try await destination(config, session: explicitSession).upload(body, key: "aSIS7.png", contentType: "image/png",
                                                                       cacheControl: nil) { _ in }
        let explicit = try #require(explicitStub.requests.first)
        #expect(explicit.value(forHTTPHeaderField: "cache-control") == nil)
        #expect(explicit.value(forHTTPHeaderField: "authorization") == request.value(forHTTPHeaderField: "authorization"))
    }
```

In `TidyShotTests/CaptureRecordTests.swift`, append inside `struct CaptureRecordTests` after `uploadedKeyAndPendingOnly`. Task 13's two tests sit just before them.
```swift
    /// A Phase 3.1 record: uploaded with a location and no local file, and no Phase 4 fields.
    @Test func supersededObjectsDefaultEmptyFromOldJSON() throws {
        let json = """
        [
          {
            "fileIsTemporary" : false,
            "id" : "6F9619FF-8B86-D011-B42D-00C04FC964FF",
            "objectLocation" : {
              "bucket" : "snap.tky.io",
              "endpoint" : "https://s3.us-west-2.amazonaws.com",
              "region" : "us-west-2",
              "usePathStyle" : true
            },
            "pixelHeight" : 10,
            "pixelWidth" : 20,
            "thumbnailFileName" : "6F9619FF-8B86-D011-B42D-00C04FC964FF.png",
            "timestamp" : "2026-10-19T16:56:03.000Z",
            "uploadState" : {
              "uploaded" : {
                "key" : "aB3dE9.png",
                "url" : "https://snap.tky.io/aB3dE9.png"
              }
            }
          }
        ]
        """
        try Data(json.utf8).write(to: dir.appending(path: "history.json"))
        let history = store()
        history.load()

        let record = try #require(history.record(id: UUID(uuidString: "6F9619FF-8B86-D011-B42D-00C04FC964FF")!))
        #expect(record.supersededObjects == [])
        #expect(record.uploadedKey == "aB3dE9.png")
        #expect(record.objectLocation?.bucket == "snap.tky.io")
    }

    @Test func supersededObjectsRoundTrip() throws {
        let here = ObjectLocation(endpoint: "https://s3.us-west-2.amazonaws.com", region: "us-west-2",
                                  bucket: "snap.tky.io", usePathStyle: true)
        let there = ObjectLocation(endpoint: "https://abc.r2.cloudflarestorage.com", region: "auto",
                                   bucket: "shots", usePathStyle: false)
        let record = CaptureRecord(timestamp: Date(timeIntervalSince1970: 1_792_411_200), fileURL: nil, pixelWidth: 20, pixelHeight: 10,
                                   appName: nil, uploadState: .uploaded(url: URL(string: "https://snap.tky.io/new.png")!, key: "new.png"),
                                   objectLocation: here,
                                   supersededObjects: [ObjectRef(key: "old.png", location: here),
                                                       ObjectRef(key: "older.png", location: there)])
        store().add(record)

        let reloaded = store()
        reloaded.load()
        #expect(reloaded.record(id: record.id) == record)
        #expect(reloaded.record(id: record.id)?.supersededObjects.map { $0.location } == [here, there])
    }

    @Test func priorUploadDefaultsNilFromOldJSON() throws {
        try Data(phase2JSON.utf8).write(to: dir.appending(path: "history.json"))
        let history = store()
        history.load()

        let record = try #require(history.record(id: UUID(uuidString: "0B2E8A4C-1C3D-4E5F-8A9B-0C1D2E3F4A5B")!))
        #expect(record.priorUpload == nil)
        #expect(record.supersededObjects == [])
        #expect(record.linkURL?.absoluteString == "https://snap.tky.io/aSIS7x.png")
    }

    @Test func priorUploadRoundTrips() throws {
        let location = ObjectLocation(endpoint: "https://s3.us-west-2.amazonaws.com", region: "us-west-2",
                                      bucket: "snap.tky.io", usePathStyle: true)
        let now = Date(timeIntervalSince1970: 1_792_411_200)
        let replace = PriorUpload(url: URL(string: "https://snap.tky.io/aB3dE9.png")!, key: "aB3dE9.png",
                                  location: location, isReplace: true)
        let asNew = PriorUpload(url: URL(string: "https://snap.tky.io/Qx12Zz.png")!, key: "Qx12Zz.png",
                                location: location, isReplace: false)
        let interrupted = CaptureRecord(timestamp: now, fileURL: dir.appending(path: "pending/x.png"), fileIsTemporary: true,
                                        pixelWidth: 20, pixelHeight: 10, appName: nil,
                                        uploadState: .failed(message: "Upload was interrupted."),
                                        objectLocation: location, priorUpload: replace)
        let failed = CaptureRecord(timestamp: now.addingTimeInterval(-1), fileURL: nil, pixelWidth: 20, pixelHeight: 10, appName: nil,
                                   uploadState: .failed(message: "offline"), objectLocation: location, priorUpload: asNew)
        let first = store()
        first.add(interrupted)
        first.add(failed)

        let second = store()
        second.load()
        #expect(second.record(id: interrupted.id) == interrupted)
        #expect(second.record(id: interrupted.id)?.priorUpload == replace)
        #expect(second.record(id: failed.id)?.priorUpload == asNew)
    }

    /// `uploadedURL` stays computed from `uploadState` alone. The link falls back to the prior
    /// upload while an editor upload runs and after one was interrupted.
    @Test func linkURLFallsBackToPriorUpload() {
        let location = ObjectLocation(endpoint: "https://s3.us-west-2.amazonaws.com", region: "us-west-2",
                                      bucket: "snap.tky.io", usePathStyle: true)
        let old = URL(string: "https://snap.tky.io/aB3dE9.png")!
        var record = CaptureRecord(fileURL: nil, pixelWidth: 1, pixelHeight: 1, appName: nil, uploadState: .uploading(fraction: 0.3),
                                   priorUpload: PriorUpload(url: old, key: "aB3dE9.png", location: location, isReplace: true))
        #expect(record.uploadedURL == nil)
        #expect(record.uploadedKey == nil)
        #expect(record.linkURL == old)

        record.uploadState = .failed(message: "Upload was interrupted.")
        #expect(record.linkURL == old)

        let new = URL(string: "https://snap.tky.io/Qx12Zz.png")!
        record.uploadState = .uploaded(url: new, key: "Qx12Zz.png")
        #expect(record.linkURL == new)

        record.priorUpload = nil
        record.uploadState = .failed(message: "offline")
        #expect(record.linkURL == nil)
    }

    /// The staleness rule follows the link, not `uploadedURL`: a replace interrupted by a quit leaves
    /// `.failed` with the link in `priorUpload`, and the next local edit must still mark the link stale.
    @Test func localEditMarksStaleWhenThereIsALink() {
        let location = ObjectLocation(endpoint: "https://s3.us-west-2.amazonaws.com", region: "us-west-2",
                                      bucket: "snap.tky.io", usePathStyle: true)
        let edited = Date(timeIntervalSince1970: 1_792_411_200)
        let prior = PriorUpload(url: URL(string: "https://snap.tky.io/aB3dE9.png")!, key: "aB3dE9.png",
                                location: location, isReplace: true)

        var interrupted = CaptureRecord(fileURL: nil, fileIsTemporary: true, pixelWidth: 20, pixelHeight: 10, appName: nil,
                                        uploadState: .failed(message: "Upload was interrupted."),
                                        objectLocation: location, priorUpload: prior)
        interrupted.recordLocalEdit(pixelWidth: 40, pixelHeight: 30, at: edited)
        #expect(interrupted.uploadedURL == nil)
        #expect(interrupted.uploadIsStale)
        #expect(interrupted.editedAt == edited)
        #expect(interrupted.pixelWidth == 40 && interrupted.pixelHeight == 30)

        var uploaded = CaptureRecord(fileURL: nil, pixelWidth: 20, pixelHeight: 10, appName: nil,
                                     uploadState: .uploaded(url: prior.url, key: "aB3dE9.png"), objectLocation: location)
        uploaded.recordLocalEdit(pixelWidth: 20, pixelHeight: 10, at: edited)
        #expect(uploaded.uploadIsStale)

        // No link at all: nothing shows the original, so there is nothing to call stale.
        var never = CaptureRecord(fileURL: nil, pixelWidth: 20, pixelHeight: 10, appName: nil)
        never.recordLocalEdit(pixelWidth: 40, pixelHeight: 30, at: edited)
        #expect(!never.uploadIsStale)
        #expect(never.editedAt == edited)
    }
```

In `TidyShotTests/CaptureDeletionTests.swift`, add a second location after `location` (line 8):
```swift
    let elsewhere = ObjectLocation(endpoint: "https://abc.r2.cloudflarestorage.com", region: "auto",
                                   bucket: "shots", usePathStyle: false)
```

Replace the helper (lines 10-14):
```swift
    func record(state: CaptureRecord.UploadState, fileURL: URL? = URL(fileURLWithPath: "/Users/tim/Desktop/Shot.png"),
                temporary: Bool = false, location: ObjectLocation? = nil, pendingKey: String? = nil) -> CaptureRecord {
        CaptureRecord(fileURL: fileURL, fileIsTemporary: temporary, pixelWidth: 10, pixelHeight: 10, appName: "Safari",
                      uploadState: state, objectLocation: location, pendingObjectKey: pendingKey)
    }
```
with:
```swift
    func record(state: CaptureRecord.UploadState, fileURL: URL? = URL(fileURLWithPath: "/Users/tim/Desktop/Shot.png"),
                temporary: Bool = false, location: ObjectLocation? = nil, pendingKey: String? = nil,
                superseded: [ObjectRef] = [], prior: PriorUpload? = nil) -> CaptureRecord {
        CaptureRecord(fileURL: fileURL, fileIsTemporary: temporary, pixelWidth: 10, pixelHeight: 10, appName: "Safari",
                      uploadState: state, objectLocation: location, pendingObjectKey: pendingKey,
                      supersededObjects: superseded, priorUpload: prior)
    }
```

Append inside `struct CaptureDeletionTests` after `alertTexts` (line 87):
```swift
    /// An Upload as New, or an upload after the destination changed, leaves the old key behind at
    /// its own location. Delete removes it there, after the record's own keys, one location at a time.
    @Test func objectsIncludeSupersededAtTheirLocations() {
        let uploaded = record(state: .uploaded(url: url, key: "new.png"), location: location,
                              superseded: [ObjectRef(key: "old.png", location: elsewhere),
                                           ObjectRef(key: "older.png", location: location)])
        let objects = CaptureDeletion.objects(for: uploaded)
        #expect(objects == [ObjectRef(key: "new.png", location: location),
                            ObjectRef(key: "old.png", location: elsewhere),
                            ObjectRef(key: "older.png", location: location)])

        let groups = CaptureDeletion.grouped(objects)
        #expect(groups.map { $0.location } == [location, elsewhere])
        #expect(groups.map { $0.keys } == [["new.png", "older.png"], ["old.png"]])
        #expect(CaptureDeletion.grouped([]).isEmpty)
    }

    @Test func objectsDeduplicated() {
        let ref = ObjectRef(key: "aB3dE9.png", location: location)
        // A replace cancelled by Delete: the reserved key, the prior key and a superseded ref are one object.
        let replaced = record(state: .failed(message: "Upload cancelled."), location: location, pendingKey: "aB3dE9.png",
                              superseded: [ref, ref],
                              prior: PriorUpload(url: url, key: "aB3dE9.png", location: location, isReplace: true))
        #expect(CaptureDeletion.objects(for: replaced) == [ref])

        // The same key in another bucket is another object.
        let moved = record(state: .uploaded(url: url, key: "aB3dE9.png"), location: location,
                           superseded: [ObjectRef(key: "aB3dE9.png", location: elsewhere)])
        #expect(CaptureDeletion.objects(for: moved) == [ref, ObjectRef(key: "aB3dE9.png", location: elsewhere)])
    }

    /// A superseded object whose DELETE failed is still in storage, so the alert says so even when
    /// the record has no key of its own.
    @Test func confirmationMentionsStorageForSupersededOnly() {
        let left = [ObjectRef(key: "old.png", location: elsewhere)]
        #expect(CaptureDeletion.confirmationText(for: record(state: .none, superseded: left))
                == "Removes it from object storage, your save folder and history.")
        #expect(CaptureDeletion.confirmationText(for: record(state: .failed(message: "offline"), fileURL: nil, superseded: left))
                == "Removes it from object storage and from history.")
        #expect(CaptureDeletion.confirmationText(for: record(state: .none)) == "Removes it from your save folder and from history.")
    }

    /// While a replace runs, and after a quit or crash interrupted it, the link's key lives only in
    /// `priorUpload`. Delete finds it at the prior upload's own location, which need not be
    /// `objectLocation`.
    @Test func objectsIncludePriorUploadAtItsLocation() {
        let replace = PriorUpload(url: url, key: "aB3dE9.png", location: location, isReplace: true)
        let inFlight = record(state: .uploading(fraction: 0.3), location: location, prior: replace)
        #expect(CaptureDeletion.objects(for: inFlight) == [ObjectRef(key: "aB3dE9.png", location: location)])

        let interrupted = record(state: .failed(message: "Upload was interrupted."), fileURL: nil, location: location, prior: replace)
        #expect(CaptureDeletion.objects(for: interrupted) == [ObjectRef(key: "aB3dE9.png", location: location)])
        #expect(CaptureDeletion.confirmationText(for: interrupted) == "Removes it from object storage and from history.")

        // An Upload as New to another bucket, cancelled by Delete: the reserved key is at the new
        // location, the link's key at the old one.
        let cancelled = record(state: .failed(message: "Upload cancelled."), location: elsewhere, pendingKey: "Qx12Zz.png",
                               prior: PriorUpload(url: url, key: "aB3dE9.png", location: location, isReplace: false))
        #expect(CaptureDeletion.objects(for: cancelled) == [ObjectRef(key: "Qx12Zz.png", location: elsewhere),
                                                            ObjectRef(key: "aB3dE9.png", location: location)])
    }

    /// Another capture still links to a key through its prior upload (its replace is running or was
    /// interrupted) or still owns it as a superseded object. Deleting this capture keeps that object.
    @Test func sharedKeysSeeAnotherRecordsPriorUpload() {
        let others = [
            record(state: .uploading(fraction: 0.5), location: location,
                   prior: PriorUpload(url: url, key: "linked.png", location: location, isReplace: true)),
            record(state: .uploaded(url: url, key: "fresh.png"), location: location,
                   superseded: [ObjectRef(key: "old.png", location: location)]),
            record(state: .failed(message: "Upload was interrupted."),
                   prior: PriorUpload(url: url, key: "moved.png", location: elsewhere, isReplace: false)),
        ]
        #expect(CaptureDeletion.sharedKeys(["linked.png", "old.png", "moved.png", "mine.png"], at: location, with: others)
                == ["linked.png", "old.png"])
        #expect(CaptureDeletion.sharedKeys(["moved.png", "linked.png"], at: elsewhere, with: others) == ["moved.png"])
    }
```

In `TidyShotTests/EditorSaveTargetTests.swift` (Task 13's file), append inside `struct EditorSaveTargetTests` after `uploadAsNewNeedsALink`. That test stays as it is: a never-uploaded record and a plain `.failed` record with no link are still refused. Step 6 changes the rule from `uploadedURL` to `linkURL`, which is what this test pins:
```swift
    /// A replace killed by a quit leaves `.failed` with the link in `priorUpload`. The link still
    /// exists, so Upload as New stays available (Upload as New to a new key, then delete the old).
    @Test func uploadAsNewKeepsInterruptedReplace() {
        var interrupted = saved(state: .failed(message: "Upload was interrupted."), stale: true)
        interrupted.objectLocation = location
        interrupted.priorUpload = PriorUpload(url: link, key: "a.png", location: location, isReplace: true)
        #expect(actions(interrupted).contains(.uploadAsNew))
        #expect(EditorAvailability.refusal(for: .uploadAsNew, record: interrupted, saveFolder: folder, isDeleting: false) == nil)

        // The same record, still without a link, is refused.
        var linkless = interrupted
        linkless.priorUpload = nil
        #expect(!actions(linkless).contains(.uploadAsNew))
        #expect(EditorAvailability.refusal(for: .uploadAsNew, record: linkless, saveFolder: folder, isDeleting: false)
                == "This capture has no link yet. Use Upload.")

        // While the replace runs, the uploading refusal still wins.
        interrupted.uploadState = .uploading(fraction: 0.2)
        #expect(EditorAvailability.refusal(for: .uploadAsNew, record: interrupted, saveFolder: folder, isDeleting: false)
                == "This capture is still uploading.")
    }
```

In `TidyShotTests/HistoryStoreTests.swift`, append inside `struct HistoryStoreTests`, after Task 13's test:
```swift
    /// A quit or crash during an editor replace: the record loads as failed, and the link it had
    /// stays on disk, also after load saves the rewrite, so Copy URL and Delete still find it.
    @Test func interruptedReplaceKeepsPriorUpload() throws {
        let location = ObjectLocation(endpoint: "https://s3.us-west-2.amazonaws.com", region: "us-west-2",
                                      bucket: "snap", usePathStyle: false)
        let prior = PriorUpload(url: URL(string: "https://snap.tky.io/a.png")!, key: "a.png", location: location, isReplace: true)
        var item = record(state: .uploading(fraction: 0.4))
        item.objectLocation = location
        item.priorUpload = prior
        store().add(item)

        let second = store()
        second.load()
        let loaded = try #require(second.record(id: item.id))
        #expect(loaded.uploadState == .failed(message: "Upload was interrupted."))
        #expect(loaded.priorUpload == prior)
        #expect(loaded.linkURL == prior.url)

        let third = store()
        third.load()
        #expect(third.record(id: item.id)?.priorUpload == prior)
    }
```

In `TidyShotTests/RecentCaptureFormattingTests.swift`, append inside `struct RecentCaptureFormattingTests` after `buttonsFollowWhatTheCaptureHas` (line 57):
```swift
    /// A replace keeps its link in `priorUpload` while it runs and after a quit or crash
    /// interrupted it, so Copy URL stays enabled.
    @Test func canCopyLinkForInterruptedReplace() {
        let url = URL(string: "https://snap.tky.io/aB3dE9.png")!
        var replacing = record(.uploading(fraction: 0.4), location: location)
        replacing.priorUpload = PriorUpload(url: url, key: "aB3dE9.png", location: location, isReplace: true)
        #expect(RecentCaptureFormatting.canCopyLink(replacing))

        replacing.uploadState = .failed(message: "Upload was interrupted.")
        #expect(RecentCaptureFormatting.canCopyLink(replacing))

        replacing.priorUpload = nil
        #expect(!RecentCaptureFormatting.canCopyLink(replacing))
    }
```

- [ ] **Step 2: Run the tests to verify they fail**

Run:
```bash
xcodegen generate && xcodebuild test -project TidyShot.xcodeproj -scheme TidyShot -destination 'platform=macOS' -derivedDataPath .build 2>&1 | grep -E "error:" | sort -u | head -5
```
Expected: compile errors, among them `cannot find type 'ObjectRef' in scope`, `cannot find 'PriorUpload' in scope` and `type 'FakeDestination' does not conform to protocol 'Destination'`.

- [ ] **Step 3: Key policy, Cache-Control and the fixed-key path in the queue**

In `TidyShot/Upload/Destination.swift`, replace the `upload` requirement (lines 9-11):
```swift
    /// Uploads `data` to `key`. `progress` receives fractions in 0...1 from the transport thread.
    func upload(_ data: Data, key: String, contentType: String,
                progress: @escaping @Sendable (Double) -> Void) async throws
```
with:
```swift
    /// Uploads `data` to `key`. A non-nil `cacheControl` goes with the PUT as a signed
    /// `Cache-Control` header, which S3 stores with the object and returns on every GET.
    /// `progress` receives fractions in 0...1 from the transport thread.
    func upload(_ data: Data, key: String, contentType: String, cacheControl: String?,
                progress: @escaping @Sendable (Double) -> Void) async throws
```

Add this extension after the protocol's closing brace (line 18). The member is marked `nonisolated` explicitly, as `AWSCredentials.description` is, so default MainActor isolation never applies to it:
```swift

extension Destination {
    /// Uploads with no `Cache-Control`: every template upload and the connection test's probe.
    nonisolated func upload(_ data: Data, key: String, contentType: String,
                            progress: @escaping @Sendable (Double) -> Void) async throws {
        try await upload(data, key: key, contentType: contentType, cacheControl: nil, progress: progress)
    }
}
```

Replace `UploadJob` (lines 20-38) with:
```swift
nonisolated struct UploadJob: Sendable, Identifiable {
    /// How the queue picks the object key.
    enum KeyPolicy: Sendable, Equatable {
        /// Named from the destination's key template when the upload starts, expanded against
        /// this context afresh for every key attempt (only `{random}` changes on a collision),
        /// and reserved with HEAD.
        case template(TemplateContext)
        /// Exactly this key, with no HEAD and nothing drawn from the template: the editor's
        /// replace of the record's own object at its own location. Every retry PUTs it again.
        case fixed(String)
    }

    /// Matches the `CaptureRecord.id` this upload belongs to.
    let id: UUID
    let data: Data
    let contentType: String
    /// Without a dot, for example `png`. Only template keys use it.
    let fileExtension: String
    let key: KeyPolicy
    /// Sent as a signed `Cache-Control` header on the PUT; nil sends none.
    let cacheControl: String?

    /// A job whose key is named from the template. It sends no `Cache-Control`.
    init(id: UUID, data: Data, contentType: String, fileExtension: String, naming: TemplateContext = TemplateContext()) {
        self.id = id
        self.data = data
        self.contentType = contentType
        self.fileExtension = fileExtension
        self.key = .template(naming)
        self.cacheControl = nil
    }

    /// A job that PUTs `fixedKey` as is. By default it sends `Cache-Control: no-cache`, so a cache
    /// that honours it revalidates the replaced object from now on. A copy a cache already holds
    /// stays until its own TTL expires.
    init(id: UUID, data: Data, contentType: String, fileExtension: String, fixedKey: String,
         cacheControl: String? = "no-cache") {
        self.id = id
        self.data = data
        self.contentType = contentType
        self.fileExtension = fileExtension
        self.key = .fixed(fixedKey)
        self.cacheControl = cacheControl
    }
}
```

In the same file, replace the `.cancelled` doc (lines 45-47):
```swift
    /// Terminal, like `.failed`, after `UploadQueue.cancel(recordID:)`. Never followed by `.failed`.
    /// `reservedKey` is the key the job had claimed, nil when it was cancelled before HEAD
    /// found one; its PUT may have completed on the server, so a delete removes it too.
```
with:
```swift
    /// Terminal, like `.failed`, after `UploadQueue.cancel(recordID:)`. Never followed by `.failed`.
    /// `reservedKey` is the key the job had claimed (its fixed key, or the template key HEAD
    /// found free), nil when it was cancelled before it had one. Its PUT may have completed on
    /// the server, so a delete removes it too.
```

In `TidyShot/Upload/S3Destination.swift`, replace (lines 56-59):
```swift
    func upload(_ data: Data, key: String, contentType: String,
                progress: @escaping @Sendable (Double) -> Void) async throws {
        var headers = [(name: "content-type", value: contentType)]
        if config.sendPublicReadACL {
```
with:
```swift
    func upload(_ data: Data, key: String, contentType: String, cacheControl: String?,
                progress: @escaping @Sendable (Double) -> Void) async throws {
        var headers = [(name: "content-type", value: contentType)]
        if let cacheControl {
            // Signed like every extra header, so a change in transit fails the signature.
            headers.append((name: "cache-control", value: cacheControl))
        }
        if config.sendPublicReadACL {
```

In `TidyShot/Upload/UploadQueue.swift`, replace the type doc (lines 3-5):
```swift
/// Uploads jobs one at a time, in order, with HEAD-before-PUT key reservation and retry with
/// backoff. Reports progress and results through `events`, which runs on the main actor. A job
/// can be cancelled while pending or in flight; it then ends with a single `.cancelled` event.
```
with:
```swift
/// Uploads jobs one at a time, in order, with retry and backoff. A template job's key is reserved
/// with HEAD before its PUT; a fixed-key job PUTs its key as is. Reports progress and results
/// through `events`, which runs on the main actor. A job can be cancelled while pending or in
/// flight; it then ends with a single `.cancelled` event.
```

Replace the last three lines of the `.stopped` doc (lines 16-18):
```swift
        /// object key the job had claimed with HEAD-before-PUT, nil when it was cancelled before
        /// that. The PUT for that key may have completed on the server just as it was cancelled,
        /// so a caller that is deleting the capture deletes this key too.
```
with:
```swift
        /// object key the job had claimed (its fixed key, or one reserved with HEAD-before-PUT),
        /// nil when it was cancelled before that. The PUT for that key may have completed on the
        /// server just as it was cancelled, so a caller that is deleting the capture deletes this
        /// key too.
```

Replace the `reservedKeys` doc (line 41):
```swift
    /// Key reserved by the in-flight job, reported in its `.cancelled` event if it is cancelled.
```
with:
```swift
    /// The in-flight job's key (its fixed key, or one reserved with HEAD), reported in its
    /// `.cancelled` event if it is cancelled.
```

In `process(_:)`, replace (lines 105-111):
```swift
                let key = try await reserveKey(ext: job.fileExtension, context: job.naming)
                reservedKeys[job.id] = key
                let id = job.id
                let events = events
                try await destination.upload(job.data, key: key, contentType: job.contentType) { fraction in
                    Task { await events(.progress(id: id, fraction: fraction)) }
                }
```
with:
```swift
                let key = try await objectKey(for: job)
                reservedKeys[job.id] = key
                let id = job.id
                let events = events
                try await destination.upload(job.data, key: key, contentType: job.contentType,
                                             cacheControl: job.cacheControl) { fraction in
                    Task { await events(.progress(id: id, fraction: fraction)) }
                }
```

Add before `/// Generates keys until HEAD reports one unused.` (line 149):
```swift
    /// The key for this attempt. A template key is named afresh and reserved with HEAD. A fixed key
    /// is the record's own key at its own location, and no other record points at it (the
    /// coordinator's shared-key rule checks that), so it is PUT as is on every attempt. A HEAD
    /// would find the record's own object and steer away from it.
    private func objectKey(for job: UploadJob) async throws -> String {
        switch job.key {
        case .template(let context):
            return try await reserveKey(ext: job.fileExtension, context: context)
        case .fixed(let key):
            return key
        }
    }

```

The retry loop needs no change: `continue` re-enters the `do` block, which calls `objectKey(for:)` again and gets the same fixed key. A cancel during the PUT or the backoff sleep reports `reservedKeys[id]`, which is now the fixed key.

- [ ] **Step 4: ObjectRef, PriorUpload and the record fields**

Replace `TidyShot/Upload/ObjectLocation.swift` line 6:
```swift
nonisolated struct ObjectLocation: Codable, Equatable, Sendable {
```
with:
```swift
nonisolated struct ObjectLocation: Codable, Hashable, Sendable {
```
and append at the end of the file:
```swift

/// One object in a bucket: a key and where it lives. Used for objects a capture no longer links to
/// but still owns (`CaptureRecord.supersededObjects`), and for everything Delete removes
/// (`CaptureDeletion.objects(for:)`).
nonisolated struct ObjectRef: Codable, Hashable, Sendable {
    var key: String
    var location: ObjectLocation
}
```

In `TidyShot/History/CaptureRecord.swift`, add after `var pendingObjectKey: String?` (line 34) and after Task 13's `editedAt` and `uploadIsStale` properties:
```swift
    /// Objects the record's earlier uploads left behind: the old key of an Upload as New, or of an
    /// upload after the destination changed, each at its own location. Deleted after the new
    /// upload succeeds; a ref whose DELETE failed stays here, so Delete removes it later.
    var supersededObjects: [ObjectRef]
    /// The link the record had when the editor started an upload over it. Set in the same update
    /// that marks the record uploading; cleared on `.uploaded` and on a handled failure. It
    /// survives a quit or crash mid-upload (`HistoryStore.load` turns `.uploading` into
    /// `.failed`), so the link stays copyable and Delete still finds its object.
    var priorUpload: PriorUpload?
```

Add two parameters at the end of the memberwise `init` parameter list, after Task 13's `uploadIsStale: Bool = false`:
```swift
         supersededObjects: [ObjectRef] = [], priorUpload: PriorUpload? = nil
```
and these two lines at the end of its body:
```swift
        self.supersededObjects = supersededObjects
        self.priorUpload = priorUpload
```

Add this line to `CodingKeys`, after Task 13's case line:
```swift
        case supersededObjects, priorUpload
```

Add these two lines at the end of `init(from:)`:
```swift
        supersededObjects = try container.decodeIfPresent([ObjectRef].self, forKey: .supersededObjects) ?? []
        priorUpload = try container.decodeIfPresent(PriorUpload.self, forKey: .priorUpload)
```
and add one sentence to its doc (lines 57-59): `Files from before Phase 4 have no supersededObjects or priorUpload either; they decode as [] and nil.`

Add after `uploadedKey` (line 84):
```swift

    /// The link to copy: the uploaded URL, or, while an editor upload runs over an earlier link and
    /// after a quit or crash interrupted it, that earlier link. `uploadedURL` and `uploadedKey`
    /// stay computed from `uploadState` alone.
    var linkURL: URL? { uploadedURL ?? priorUpload?.url }

    /// What an edit written to the capture's file changes on the record: its pixel size, `editedAt`,
    /// and, when the record has a link (`linkURL`, so also one that lives only in `priorUpload`
    /// after an interrupted replace), `uploadIsStale`, because that link still shows the original.
    /// Task 13's `applyLocalEdit` calls this inside `history.update`.
    mutating func recordLocalEdit(pixelWidth: Int, pixelHeight: Int, at editedAt: Date) {
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.editedAt = editedAt
        if linkURL != nil {
            uploadIsStale = true
        }
    }
```

Append at the end of the file:
```swift

/// The link a record had when the editor started an upload over it. `isReplace` is true when that
/// upload PUTs the same key, so the URL stays. It is false when the upload makes a new object and
/// the old key goes to `supersededObjects`.
nonisolated struct PriorUpload: Codable, Equatable, Sendable {
    var url: URL
    var key: String
    var location: ObjectLocation
    var isReplace: Bool
}
```

- [ ] **Step 5: Delete sees every object, per location**

In `TidyShot/History/CaptureDeletion.swift`, replace the `objectKeys(for:)` doc (lines 17-19):
```swift
    /// Object keys that may hold the capture, in order and without duplicates: the key it was
    /// uploaded under, and the key a cancelled upload had reserved (its PUT may have completed
    /// on the server as it was cancelled). Both live at `record.objectLocation`.
```
with:
```swift
    /// The keys at `record.objectLocation` that may hold the capture, in order and without
    /// duplicates: the key it was uploaded under, and the key a cancelled upload had reserved (its
    /// PUT may have completed on the server as it was cancelled). `objects(for:)` adds the objects
    /// the record names elsewhere.
```

Replace `sharedKeys(_:at:with:)` (lines 28-37) with:
```swift
    /// Every object Delete removes for `record`, in order and without duplicates, each at its own
    /// location:
    /// - `objectKeys(for:)` at `objectLocation` (none without a location: a record from before
    ///   Phase 3 does not know its bucket);
    /// - the prior upload at its location, so the link's object is found while an editor upload
    ///   runs over it and after a quit or crash interrupted that upload;
    /// - the superseded objects, old keys left by an Upload as New or by an upload after the
    ///   destination changed.
    static func objects(for record: CaptureRecord) -> [ObjectRef] {
        var candidates: [ObjectRef] = []
        if let location = record.objectLocation {
            candidates += objectKeys(for: record).map { ObjectRef(key: $0, location: location) }
        }
        if let prior = record.priorUpload {
            candidates.append(ObjectRef(key: prior.key, location: prior.location))
        }
        candidates += record.supersededObjects
        var objects: [ObjectRef] = []
        for object in candidates where !objects.contains(object) {
            objects.append(object)
        }
        return objects
    }

    /// `objects` grouped by location, in order of first appearance, with each group's keys in
    /// their original order. Delete signs one destination per group.
    static func grouped(_ objects: [ObjectRef]) -> [(location: ObjectLocation, keys: [String])] {
        var groups: [(location: ObjectLocation, keys: [String])] = []
        for object in objects {
            if let index = groups.firstIndex(where: { $0.location == object.location }) {
                groups[index].keys.append(object.key)
            } else {
                groups.append((location: object.location, keys: [object.key]))
            }
        }
        return groups
    }

    /// The keys among `keys` that a record in `others` also points at, at `location`, through any
    /// object `objects(for:)` lists for it: its uploaded or reserved key, its prior upload, or a
    /// superseded object. A template without `{random}` or `{counter}` can give two captures the
    /// same key when HEAD cannot see the first object, and deleting it would break the other
    /// capture's URL. A capture whose replace is running or was interrupted still links to its
    /// prior key.
    static func sharedKeys(_ keys: [String], at location: ObjectLocation, with others: [CaptureRecord]) -> [String] {
        let claimed = Set(others.flatMap { objects(for: $0) })
        return keys.filter { claimed.contains(ObjectRef(key: $0, location: location)) }
    }
```

In `confirmationText(for:)`, replace the condition (line 46):
```swift
        if record.isUploading || (record.objectLocation != nil && !objectKeys(for: record).isEmpty) {
```
with:
```swift
        if record.isUploading || !objects(for: record).isEmpty {
```
and replace the end of its doc (lines 42-43):
```swift
    /// storage (the default Upload mode keeps both). A record uploaded before Phase 3 has no
    /// `objectLocation`, so its object cannot be deleted, and the line says it stays.
```
with:
```swift
    /// storage (the default Upload mode keeps both). A record uploaded before Phase 3 has no
    /// `objectLocation`, so its own object cannot be deleted, and the line says it stays. A prior
    /// upload or a superseded object names its own location, so either one counts as storage.
```

In `TidyShot/RecentCaptures/RecentCaptureFormatting.swift`, replace (lines 27-30):
```swift
    /// Copy URL needs an uploaded object.
    static func canCopyLink(_ record: CaptureRecord) -> Bool {
        record.uploadedURL != nil
    }
```
with:
```swift
    /// Copy URL needs a link: an uploaded object, or the earlier link of an editor upload that is
    /// running or was interrupted (`CaptureRecord.linkURL`).
    static func canCopyLink(_ record: CaptureRecord) -> Bool {
        record.linkURL != nil
    }
```

In `TidyShot/App/AppCoordinator.swift`, replace (lines 442-457):
```swift
    /// Copies the public URL, or the local file for a capture that was never uploaded.
    func copyLinkOrFile(recordID: UUID) {
        guard let record = history.record(id: recordID) else { return }
        if let url = record.uploadedURL {
            Pasteboard.copy(url: url)
        } else if let fileURL = record.fileURL {
            Pasteboard.copy(fileURL: fileURL)
        }
    }

    /// Copy URL: the public URL of an uploaded capture. A capture that was never uploaded has none,
    /// and its row's button is disabled.
    func copyLink(recordID: UUID) {
        guard let url = history.record(id: recordID)?.uploadedURL else { return }
        Pasteboard.copy(url: url)
    }
```
with:
```swift
    /// Copies the link (`linkURL`, which also covers an editor upload that is running or was
    /// interrupted), or the local file for a capture that has no link.
    func copyLinkOrFile(recordID: UUID) {
        guard let record = history.record(id: recordID) else { return }
        if let url = record.linkURL {
            Pasteboard.copy(url: url)
        } else if let fileURL = record.fileURL {
            Pasteboard.copy(fileURL: fileURL)
        }
    }

    /// Copy URL: the capture's link (`linkURL`). A capture that was never uploaded has none, and
    /// its row's button is disabled.
    func copyLink(recordID: UUID) {
        guard let url = history.record(id: recordID)?.linkURL else { return }
        Pasteboard.copy(url: url)
    }
```
Task 12 makes `Pasteboard.copy` `@discardableResult`, so these calls compile unchanged.

In the `deleteCapture` doc, replace (lines 529-530):
```swift
    /// Cancel. Delete stops an in-flight upload, removes the object from the bucket the record says
    /// it went to, then the local file, the thumbnail and the record. When the storage `DELETE`
```
with:
```swift
    /// Cancel. Delete stops an in-flight upload, removes its objects, each from the bucket the
    /// record names for it (`CaptureDeletion.objects(for:)`), then the local file, the thumbnail
    /// and the record. When the storage `DELETE`
```

Replace its storage step (lines 547-562):
```swift
        var sharedKeys: [String] = []
        let keys = CaptureDeletion.objectKeys(for: current)
        if !keys.isEmpty, let location = current.objectLocation {
            // Never delete an object another capture still points at.
            // A record whose own delete is still pending (its alert open) counts as a sharer: if
            // that delete is cancelled, its URL must keep working.
            let others = history.records.filter { $0.id != recordID }
            sharedKeys = CaptureDeletion.sharedKeys(keys, at: location, with: others)
            if let reason = await deleteObjects(keys.filter { !sharedKeys.contains($0) }, at: location) {
                if await confirmRemoveFromHistory(message: CaptureDeletion.storageFailureMessage(reason: reason),
                                                  informativeText: CaptureDeletion.storageFailureText) {
                    removeFromHistoryOnly(recordID)
                }
                return
            }
        }
```
with:
```swift
        // The record's own keys, its prior upload and its superseded objects, one location at a
        // time: an object left by an earlier destination lives in that destination's bucket.
        var sharedKeys: [String] = []
        for group in CaptureDeletion.grouped(CaptureDeletion.objects(for: current)) {
            // Never delete an object another capture still points at.
            // A record whose own delete is still pending (its alert open) counts as a sharer: if
            // that delete is cancelled, its URL must keep working. Read per group, because each
            // group's DELETEs await the network.
            let others = history.records.filter { $0.id != recordID }
            let shared = CaptureDeletion.sharedKeys(group.keys, at: group.location, with: others)
            sharedKeys += shared
            if let reason = await deleteObjects(group.keys.filter { !shared.contains($0) }, at: group.location) {
                if await confirmRemoveFromHistory(message: CaptureDeletion.storageFailureMessage(reason: reason),
                                                  informativeText: CaptureDeletion.storageFailureText) {
                    removeFromHistoryOnly(recordID)
                }
                return
            }
        }
```
A group whose keys are all shared calls `deleteObjects([])`, which returns nil without reading the Keychain (AppCoordinator.swift:605). A record with no objects runs no group, as before. The two `notifyKept(sharedKeys)` calls after this step are unchanged and now report kept keys from every group. `deleteOrphanedObject` (821) needs no edit: its `sharedKeys` call now also sees other records' prior uploads and superseded objects.

- [ ] **Step 6: Task 13's editor code follows the link**

Task 13 keyed two rules on `uploadedURL`, which is nil for a record whose replace was interrupted (`.failed`, the link in `priorUpload`). Both now follow `linkURL`.

In `TidyShot/Editor/Persistence/EditorSaveTarget.swift`, in `EditorAvailability.refusal`, replace the comment and the line below it:
```swift
            // Task 14 changes this to `record.linkURL == nil` (`priorUpload` keeps the link of an interrupted replace).
            if action == .uploadAsNew, record.uploadedURL == nil { return notUploadedRefusal }
```
with:
```swift
            if action == .uploadAsNew, record.linkURL == nil { return notUploadedRefusal }
```
`EditorUploadPlan.plan` (Task 15) already reads the link from `priorUpload`, so toolbar, shortcut and plan now agree.

In `TidyShot/App/AppCoordinator.swift`, in `applyLocalEdit(recordID:png:image:)`, replace the `history.update` call:
```swift
        history.update(id: recordID) { record in
            record.pixelWidth = image.image.width
            record.pixelHeight = image.image.height
            record.editedAt = editedAt
            // Task 14 changes this to `record.linkURL != nil`, so a record whose replace was
            // interrupted (link in `priorUpload`) is marked stale too (spec 2.6 step 4).
            if record.uploadedURL != nil {
                record.uploadIsStale = true
            }
        }
```
with:
```swift
        history.update(id: recordID) {
            $0.recordLocalEdit(pixelWidth: image.image.width, pixelHeight: image.image.height, at: editedAt)
        }
```
Without this, a replace interrupted by a quit, then saved or uploaded again and failed again, would come back `.uploaded` with `uploadIsStale` false: the subtitle would never say the link shows the original, and for an upload-only record `keepsUnuploadedEdit` would be false, so retention could prune the only copy of the edit in `pending/`.

Task 13's `uploadAsNewNeedsALink` and its `.failed` line stay valid as written (no link, so refused); `uploadAsNewKeepsInterruptedReplace` covers the record with a link. Task 15's tests for `applyingFailure` on this record are in Task 15.

- [ ] **Step 7: Run the tests to verify they pass**

Run:
```bash
xcodegen generate && xcodebuild test -project TidyShot.xcodeproj -scheme TidyShot -destination 'platform=macOS' -derivedDataPath .build 2>&1 | grep -E "Test run with|error:|TEST"
```
Expected: no `error:` lines, and `Test run with 370 tests in 49 suites passed`. The 16 earlier UploadQueueTests pass without edits to their bodies.

- [ ] **Step 8: Check by hand (regressions only)**

Nothing writes `priorUpload`, `supersededObjects` or a fixed-key job until Task 15. Its hand checks against a real bucket exercise the replace, the signed `Cache-Control` header and the cleanup of superseded objects. Here, check that template uploads, Copy URL and Delete still work:
```bash
xcodebuild -project TidyShot.xcodeproj -scheme TidyShot -configuration Debug -derivedDataPath .build build -quiet && open .build/Build/Products/Debug/TidyShot.app
```
- Settings > Upload > Save and Test Connection still reports `Upload and public read both work.` This exercises the four-argument `upload` through the protocol extension.
- Take a capture in Upload mode. Expected: it uploads under a new template key, and the URL is on the clipboard.
- In Recent Captures, click Copy URL on that row, and the overlay's Copy if it is still open. Expected: both copy the same URL.
- Delete the capture from Recent Captures. Expected: the alert reads `Removes it from object storage, your save folder and history.`, the object is gone (its URL no longer serves it), and the row disappears.

- [ ] **Step 9: Commit**

```bash
git add TidyShot/Upload/Destination.swift TidyShot/Upload/UploadQueue.swift TidyShot/Upload/S3Destination.swift TidyShot/Upload/ObjectLocation.swift TidyShot/History/CaptureRecord.swift TidyShot/History/CaptureDeletion.swift TidyShot/RecentCaptures/RecentCaptureFormatting.swift TidyShot/Editor/Persistence/EditorSaveTarget.swift TidyShot/App/AppCoordinator.swift TidyShotTests/UploadQueueTests.swift TidyShotTests/S3DestinationTests.swift TidyShotTests/CaptureRecordTests.swift TidyShotTests/CaptureDeletionTests.swift TidyShotTests/HistoryStoreTests.swift TidyShotTests/RecentCaptureFormattingTests.swift TidyShotTests/EditorSaveTargetTests.swift
git commit -m "feat: fixed-key uploads, superseded objects and persisted prior uploads"
```

---

### Task 15: Upload and Upload as New from the editor, with a retry path for interrupted replaces

**Files:**
- Create: `TidyShot/Editor/Persistence/EditorUploadPlan.swift`
- Create: `TidyShotTests/EditorUploadPlanTests.swift`
- Modify: `TidyShot/App/AppCoordinator.swift` (`startUpload`, `retry`, `handle(_:at:)`, one new property, and three methods under `// MARK: Editor`)

Line numbers below are at f4541da. Tasks 12 to 14 edit `AppCoordinator.swift` first and shift them, so find each spot by the quoted code.

**Interfaces:**
- Consumes:
  - `ScaledImage` (Task 2).
  - `EditorActions.upload: (ScaledImage, _ asNew: Bool) async -> Bool` and `private func editorActions(for recordID: UUID) -> EditorActions` in `AppCoordinator.swift`, the one place the `EditorActions` closures are built (Task 10; Tasks 12 and 13 already replaced its `saveCopy`, `copy` and `save` stubs); the `#if DEBUG` item `Annotate Last Capture (debug)` for the hand checks (Task 10, removed in Task 16).
  - `private func keepOnClipboard(_ image: ScaledImage, png: Data, alreadyOnClipboard: Bool)` and `private func replaceClipboardIfStillOriginal(recordID: UUID, png: Data, image: ScaledImage) async` (Task 12).
  - `enum EditorAction { case save, saveCopy, copy, upload, uploadAsNew }`, `EditorAvailability.refusal(for:record:saveFolder:isDeleting:) -> String?`, `EditorSaveTarget.plan(for:saveFolder:) -> EditorSaveTarget.Plan` (`.saveFolderFile(URL, folder: URL)`, `.pendingFile(URL)`, `.unavailable(String)`), `EditorSaveTarget.uploadedCopyNotice(for:) -> String?`, `CaptureRecord.uploadIsStale: Bool`, `CaptureRecord.keepsUnuploadedEdit: Bool`, `private func applyLocalEdit(recordID: UUID, png: Data, image: ScaledImage) async -> Bool`, and `refreshOverlay(for:)` ending with `pushEditorState(for:)` (Task 13). `applyLocalEdit` re-checks `refusal(for: .save, …)`, so it refuses a record with no file; `editorUpload` gives such a record a pending file first. Task 14 edits two Task 13 conditions to key on `CaptureRecord.linkURL` instead of `uploadedURL`: `applyLocalEdit` sets `uploadIsStale` when `record.linkURL != nil`, and `EditorAvailability.refusal(for: .uploadAsNew, …)` returns `notUploadedRefusal` only when `record.linkURL == nil`. This task relies on both: a replace interrupted by a quit (`.failed`, `priorUpload` set, `uploadedURL` nil) is marked stale by the next Save or Upload, and keeps Upload as New.
  - `UploadJob(id:data:contentType:fileExtension:fixedKey: String, cacheControl: String?)`, `struct ObjectRef: Codable, Hashable, Sendable { var key: String; var location: ObjectLocation }`, `struct PriorUpload: Codable, Equatable, Sendable { var url: URL; var key: String; var location: ObjectLocation; var isReplace: Bool }`, `CaptureRecord.priorUpload: PriorUpload?`, `CaptureRecord.supersededObjects: [ObjectRef]`, `CaptureRecord.linkURL: URL?`, and `CaptureDeletion.sharedKeys(_:at:with:)`, which also matches other records' prior uploads and superseded refs (Task 14).
  - Existing code: `func makeDestination() -> S3Destination?` (AppCoordinator.swift:317); `private var queue: UploadLane?` (41) with `UploadLane.location` (13); `private var deletingIDs: Set<UUID>` (48); `private func startUpload(recordID: UUID, data: Data, destination: S3Destination)` (376), which writes `.uploading(0)` and calls `refreshOverlay` only for a record not already uploading (385-388); `private func retry(recordID: UUID, destination: S3Destination)` (425); `func readLocalFile(of:) throws -> Data` (437); `private func deleteObjects(_ keys: [String], at location: ObjectLocation) async -> String?` (604), nil on success; `private func markFailed(_:message:)` (739); `private func refreshOverlay(for:)` (747); `private func handle(_ event: UploadEvent, at location: ObjectLocation)` (754); `PendingFileStore.write(_:id:ext:) throws -> URL` (PendingFileStore.swift:21); `Notifier.notify(title:body:)` (Notifier.swift:43), `notifyError(_:title:)` (35) and `notifyUploaded(url:)` (27); `ImageEncoder.pngData(from:scale:) throws -> Data` (ImageEncoder.swift:21).
- Produces:
  - `nonisolated enum EditorUploadPlan` in `TidyShot/Editor/Persistence/EditorUploadPlan.swift`:
    - `enum Plan: Equatable, Sendable { case replace(key: String), newObject(supersede: ObjectRef?, notice: String?), refuse(String) }`
    - `enum RetryPolicy: Equatable, Sendable { case fixed(String), template(supersede: ObjectRef?) }` (always written `EditorUploadPlan.RetryPolicy` outside the enum, because `TidyShot/Upload/RetryPolicy.swift:5` declares a top-level `RetryPolicy`)
    - `static let uploadingReason`, `destinationChangedNotice`, `sharedKeyNotice`, `legacyNotice`, `failedReplaceMessage`, `cacheNote: String`
    - `static func plan(record: CaptureRecord, currentLocation: ObjectLocation, others: [CaptureRecord], asNew: Bool) -> Plan`
    - `static func retryPolicy(record: CaptureRecord, currentLocation: ObjectLocation, others: [CaptureRecord]) -> RetryPolicy`
    - `static func startingUpload(_ record: CaptureRecord, plan: Plan) -> CaptureRecord`
    - `static func startingRetry(_ record: CaptureRecord, policy: RetryPolicy) -> CaptureRecord`
    - `static func applyingSuccess(to record: CaptureRecord) -> CaptureRecord`
    - `static func applyingFailure(to record: CaptureRecord, message: String) -> CaptureRecord`
    - `static func shouldPostCacheNote(prior: PriorUpload?, uploadedKey: String, at location: ObjectLocation, alreadyPosted: Bool) -> Bool`
  - `AppCoordinator`:
    - `private func startUpload(recordID: UUID, data: Data, destination: S3Destination, fixedKey: String? = nil)`
    - `@ObservationIgnored private var postedCacheNote: Bool`
    - `private func editorUpload(recordID: UUID, image: ScaledImage, asNew: Bool) async -> Bool`, wired into `EditorActions.upload`
    - `private func refuseUpload(_ action: EditorAction, recordID: UUID) -> Bool`
    - `private func deleteSupersededObjects(of id: UUID) async`
    - `retry(recordID:destination:)` consults `retryPolicy`; `handle(.uploaded)` applies `applyingSuccess`, posts the cache note once and deletes superseded objects; `handle(.failed)` uses `applyingFailure` when the record has a `priorUpload`.
  - No in-memory prior-upload dictionary: the state lives on the record, so it survives a quit.

- [ ] **Step 1: Write the failing tests**

`TidyShotTests/EditorUploadPlanTests.swift`:
```swift
import Foundation
import Testing
@testable import TidyShot

struct EditorUploadPlanTests {
    let here = ObjectLocation(endpoint: "https://s3.us-west-2.amazonaws.com", region: "us-west-2",
                              bucket: "snap.tky.io", usePathStyle: true)
    let elsewhere = ObjectLocation(endpoint: "https://s3.eu-west-1.amazonaws.com", region: "eu-west-1",
                                   bucket: "shots-eu", usePathStyle: false)
    let link = URL(string: "https://snap.tky.io/aB3dE9.png")!
    let key = "aB3dE9.png"
    let savedFile = URL(fileURLWithPath: "/Users/tim/Desktop/Shot.png")
    let pendingFile = URL(fileURLWithPath: "/Users/tim/Library/Containers/io.tky.tidyshot/Data/pending/Shot.png")

    let destinationChanged = "The destination changed, so this uploads as a new link."
    let sharedLink = "Another capture shares this link, so this uploads as a new link."
    let earlierStays = "The earlier upload stays in the bucket."

    /// A capture in the save folder in `state`, whose objects live at `location`.
    func record(_ state: CaptureRecord.UploadState, at location: ObjectLocation?) -> CaptureRecord {
        CaptureRecord(fileURL: savedFile, pixelWidth: 10, pixelHeight: 10, appName: nil,
                      uploadState: state, objectLocation: location)
    }

    /// Uploaded as `key` to `location`; nil is a capture uploaded before Phase 3.
    func uploaded(at location: ObjectLocation?) -> CaptureRecord {
        record(.uploaded(url: link, key: key), at: location)
    }

    /// An editor upload of `uploaded(at: location)` cut short by a quit or crash: `HistoryStore.load`
    /// turned `.uploading` into `.failed` and kept `priorUpload` (and, for Upload as New, the
    /// superseded old key).
    func interrupted(at location: ObjectLocation, isReplace: Bool) -> CaptureRecord {
        var capture = record(.failed(message: "Upload was interrupted."), at: location)
        capture.priorUpload = PriorUpload(url: link, key: key, location: location, isReplace: isReplace)
        if !isReplace {
            capture.supersededObjects = [ObjectRef(key: key, location: location)]
        }
        // What the local write that preceded the upload left: `applyLocalEdit` marks a record with a
        // link stale, and `linkURL` covers a link kept only in `priorUpload` (Task 14).
        capture.uploadIsStale = true
        return capture
    }

    func planned(_ capture: CaptureRecord, to location: ObjectLocation, others: [CaptureRecord] = [],
                 asNew: Bool = false) -> EditorUploadPlan.Plan {
        EditorUploadPlan.plan(record: capture, currentLocation: location, others: others, asNew: asNew)
    }

    @Test func refuseWhileUploading() {
        let uploading = record(.uploading(fraction: 0.4), at: here)
        #expect(planned(uploading, to: here) == .refuse("This capture is already uploading."))
        #expect(planned(uploading, to: here, asNew: true) == .refuse("This capture is already uploading."))
        // A refusal changes nothing.
        #expect(EditorUploadPlan.startingUpload(uploading, plan: .refuse("x")) == uploading)
    }

    @Test func neverUploadedIsNewObjectWithoutSupersede() {
        #expect(planned(record(.none, at: nil), to: here) == .newObject(supersede: nil, notice: nil))
        #expect(planned(record(.failed(message: "offline"), at: nil), to: here) == .newObject(supersede: nil, notice: nil))
        // A cancelled first upload reserved a key, but no link points at it.
        var cancelled = record(.failed(message: "Upload cancelled."), at: here)
        cancelled.pendingObjectKey = "Qx12Zz.png"
        #expect(planned(cancelled, to: here, asNew: true) == .newObject(supersede: nil, notice: nil))
    }

    @Test func sameLocationUnsharedIsReplace() {
        let other = record(.uploaded(url: URL(string: "https://snap.tky.io/other.png")!, key: "other.png"), at: here)
        #expect(planned(uploaded(at: here), to: here, others: [other]) == .replace(key: key))
        // The same key in another bucket is another object.
        #expect(planned(uploaded(at: here), to: here, others: [uploaded(at: elsewhere)]) == .replace(key: key))
    }

    @Test func asNewSupersedesOldKey() {
        #expect(planned(uploaded(at: here), to: here, asNew: true)
                == .newObject(supersede: ObjectRef(key: key, location: here), notice: nil))
    }

    @Test func destinationChangedSupersedesAtOldLocationWithNotice() {
        let expected = EditorUploadPlan.Plan.newObject(supersede: ObjectRef(key: key, location: here),
                                                       notice: destinationChanged)
        #expect(planned(uploaded(at: here), to: elsewhere) == expected)
        #expect(planned(uploaded(at: here), to: elsewhere, asNew: true) == expected)
    }

    @Test func sharedKeyIsNewObjectWithoutSupersede() {
        // Another capture got the same key from a template without {random} or {counter}.
        let twin = uploaded(at: here)
        let expected = EditorUploadPlan.Plan.newObject(supersede: nil, notice: sharedLink)
        #expect(planned(uploaded(at: here), to: here, others: [twin]) == expected)
        // Upload as New never deletes an object another capture links to.
        #expect(planned(uploaded(at: here), to: here, others: [twin], asNew: true) == expected)
    }

    @Test func prePhaseThreeIsNewObjectWithNotice() {
        let expected = EditorUploadPlan.Plan.newObject(supersede: nil, notice: earlierStays)
        #expect(planned(uploaded(at: nil), to: here) == expected)
        #expect(planned(uploaded(at: nil), to: here, asNew: true) == expected)
    }

    @Test func interruptedReplaceUploadFromEditorStillReplaces() {
        let replace = interrupted(at: here, isReplace: true)
        #expect(planned(replace, to: here) == .replace(key: key))
        #expect(planned(replace, to: elsewhere)
                == .newObject(supersede: ObjectRef(key: key, location: here), notice: destinationChanged))
        // An interrupted Upload as New, then Upload: the old key is the link again, so it is no
        // longer deleted as superseded.
        let asNew = interrupted(at: here, isReplace: false)
        #expect(planned(asNew, to: here) == .replace(key: key))
        let restarted = EditorUploadPlan.startingUpload(asNew, plan: .replace(key: key))
        #expect(restarted.supersededObjects.isEmpty)
        #expect(restarted.priorUpload == PriorUpload(url: link, key: key, location: here, isReplace: true))
    }

    @Test func retryOfInterruptedReplaceReusesKey() {
        let replace = interrupted(at: here, isReplace: true)
        let policy = EditorUploadPlan.retryPolicy(record: replace, currentLocation: here, others: [])
        #expect(policy == .fixed(key))
        #expect(EditorUploadPlan.startingRetry(replace, policy: policy) == replace)
        // A key another capture shares is never re-PUT.
        #expect(EditorUploadPlan.retryPolicy(record: replace, currentLocation: here, others: [uploaded(at: here)])
                == .template(supersede: nil))
    }

    @Test func retryOfInterruptedReplaceAfterDestinationChangeSupersedes() {
        let replace = interrupted(at: here, isReplace: true)
        let old = ObjectRef(key: key, location: here)
        let policy = EditorUploadPlan.retryPolicy(record: replace, currentLocation: elsewhere, others: [])
        #expect(policy == .template(supersede: old))
        let started = EditorUploadPlan.startingRetry(replace, policy: policy)
        #expect(started.supersededObjects == [old])
        // A new link now: success posts no cache note, and a later retry stays a template upload.
        #expect(started.priorUpload == PriorUpload(url: link, key: key, location: here, isReplace: false))
        #expect(EditorUploadPlan.retryPolicy(record: started, currentLocation: here, others: []) == .template(supersede: nil))
    }

    @Test func retryWithoutPriorUploadUsesTemplate() {
        let failed = record(.failed(message: "offline"), at: nil)
        #expect(EditorUploadPlan.retryPolicy(record: failed, currentLocation: here, others: []) == .template(supersede: nil))
        #expect(EditorUploadPlan.startingRetry(failed, policy: .template(supersede: nil)) == failed)
        // An interrupted Upload as New already lists its old key as superseded.
        let asNew = interrupted(at: here, isReplace: false)
        let policy = EditorUploadPlan.retryPolicy(record: asNew, currentLocation: here, others: [])
        #expect(policy == .template(supersede: nil))
        #expect(EditorUploadPlan.startingRetry(asNew, policy: policy) == asNew)
    }

    @Test func failureRestoresPriorUploadAndDropsSupersededRef() {
        var original = uploaded(at: here)
        original.uploadIsStale = true                                // set by the local write
        let older = ObjectRef(key: "older.png", location: elsewhere) // a superseded delete that failed earlier
        original.supersededObjects = [older]
        let started = EditorUploadPlan.startingUpload(original, plan: planned(original, to: here, asNew: true))
        #expect(started.supersededObjects == [older, ObjectRef(key: key, location: here)])
        // The old object is live again, so the record is exactly what it was.
        #expect(EditorUploadPlan.applyingFailure(to: started, message: "403 Forbidden") == original)
        #expect(EditorUploadPlan.failedReplaceMessage == "Upload failed. The link still shows the earlier image.")

        // A cancelled attempt at a new destination reserved a key there, then a retry failed. The
        // reserved key stays listed at its own location, so Delete still removes it.
        var cancelled = EditorUploadPlan.startingUpload(original, plan: planned(original, to: elsewhere))
        cancelled.pendingObjectKey = "Qx12Zz.png"
        cancelled.objectLocation = elsewhere
        let restored = EditorUploadPlan.applyingFailure(to: cancelled, message: "offline")
        #expect(restored.uploadState == .uploaded(url: link, key: key))
        #expect(restored.objectLocation == here)
        #expect(restored.pendingObjectKey == nil)
        #expect(restored.supersededObjects == [older, ObjectRef(key: "Qx12Zz.png", location: elsewhere)])
        #expect(restored.priorUpload == nil)
    }

    @Test func failureWithoutPriorUploadMarksFailed() {
        let first = EditorUploadPlan.startingUpload(record(.none, at: nil), plan: .newObject(supersede: nil, notice: nil))
        #expect(first.priorUpload == nil)
        #expect(EditorUploadPlan.applyingFailure(to: first, message: "offline").uploadState == .failed(message: "offline"))
        // A pre-Phase-3 link has no location to return to, so it fails as today.
        let legacy = EditorUploadPlan.startingUpload(uploaded(at: nil), plan: .newObject(supersede: nil, notice: earlierStays))
        #expect(legacy.priorUpload == nil)
        #expect(EditorUploadPlan.applyingFailure(to: legacy, message: "offline").uploadState == .failed(message: "offline"))
    }

    @Test func successClearsPriorUploadAndStaleFlag() {
        let old = ObjectRef(key: key, location: here)
        var done = EditorUploadPlan.startingUpload(interrupted(at: here, isReplace: false),
                                                   plan: .newObject(supersede: old, notice: nil))
        // As handle(.uploaded) sets it before applyingSuccess.
        done.uploadState = .uploaded(url: URL(string: "https://snap.tky.io/Qx12Zz.png")!, key: "Qx12Zz.png")
        let settled = EditorUploadPlan.applyingSuccess(to: done)
        #expect(settled.priorUpload == nil)
        #expect(!settled.uploadIsStale)
        #expect(settled.uploadState == done.uploadState)
        // deleteSupersededObjects deletes the old object afterwards and drops the ref.
        #expect(settled.supersededObjects == [old])
    }

    @Test func failedUploadOnlyReplaceKeepsEditedPendingFileAndMarksStale() {
        // An uploaded upload-only capture has no file. Upload wrote the edit to pending/<id>.png
        // first, and that local write marked the upload stale.
        var uploadOnly = CaptureRecord(fileURL: nil, pixelWidth: 10, pixelHeight: 10, appName: nil,
                                       uploadState: .uploaded(url: link, key: key), objectLocation: here)
        uploadOnly.fileURL = pendingFile
        uploadOnly.fileIsTemporary = true
        uploadOnly.uploadIsStale = true
        let replace = planned(uploadOnly, to: here)
        #expect(replace == .replace(key: key))
        let failed = EditorUploadPlan.applyingFailure(to: EditorUploadPlan.startingUpload(uploadOnly, plan: replace),
                                                      message: "403 Forbidden")
        #expect(failed.uploadState == .uploaded(url: link, key: key))
        #expect(failed.fileURL == pendingFile)
        #expect(failed.fileIsTemporary)
        #expect(failed.uploadIsStale)
        #expect(failed.keepsUnuploadedEdit) // retention never prunes it
        #expect(EditorSaveTarget.uploadedCopyNotice(for: failed)
                == "The uploaded copy still shows the original. Upload to replace it.")
        // The next Upload from the editor replaces the object.
        #expect(planned(failed, to: here) == .replace(key: key))
    }

    @Test func interruptedReplaceThatFailsAgainStaysStaleAndRetained() {
        // Upload-only capture: killed mid-replace, so it is `.failed` with the link only in
        // `priorUpload` (`uploadedURL` is nil), and its pending file holds the edit.
        var interruptedReplace = interrupted(at: here, isReplace: true)
        interruptedReplace.fileURL = pendingFile
        interruptedReplace.fileIsTemporary = true
        #expect(interruptedReplace.uploadedURL == nil)
        #expect(interruptedReplace.linkURL == link)
        // The user presses Save or Upload again and the replace fails again.
        let plan = planned(interruptedReplace, to: here)
        #expect(plan == .replace(key: key))
        let failed = EditorUploadPlan.applyingFailure(
            to: EditorUploadPlan.startingUpload(interruptedReplace, plan: plan), message: "403 Forbidden")
        #expect(failed.uploadState == .uploaded(url: link, key: key))
        #expect(failed.uploadIsStale)
        #expect(failed.keepsUnuploadedEdit) // retention never prunes the only copy of the edit
        #expect(EditorSaveTarget.uploadedCopyNotice(for: failed)
                == "The uploaded copy still shows the original. Upload to replace it.")
    }

    @Test func startingUploadSetsUploadingStateAndPriorUpload() {
        let original = uploaded(at: here)
        let replace = EditorUploadPlan.startingUpload(original, plan: .replace(key: key))
        #expect(replace.uploadState == .uploading(fraction: 0))
        #expect(replace.priorUpload == PriorUpload(url: link, key: key, location: here, isReplace: true))
        #expect(replace.supersededObjects.isEmpty)
        #expect(replace.linkURL == link) // Copy Link keeps working while it runs

        let old = ObjectRef(key: key, location: here)
        let asNew = EditorUploadPlan.startingUpload(original, plan: .newObject(supersede: old, notice: nil))
        #expect(asNew.uploadState == .uploading(fraction: 0))
        #expect(asNew.priorUpload == PriorUpload(url: link, key: key, location: here, isReplace: false))
        #expect(asNew.supersededObjects == [old])
        // Starting again never lists the old object twice.
        #expect(EditorUploadPlan.startingUpload(asNew, plan: .newObject(supersede: old, notice: nil)).supersededObjects == [old])

        let first = EditorUploadPlan.startingUpload(record(.none, at: nil), plan: .newObject(supersede: nil, notice: nil))
        #expect(first.uploadState == .uploading(fraction: 0))
        #expect(first.priorUpload == nil)
        #expect(first.supersededObjects.isEmpty)
    }

    @Test func cacheNoteOnlyOnFirstSameKeyReplace() {
        let replace = PriorUpload(url: link, key: key, location: here, isReplace: true)
        #expect(EditorUploadPlan.cacheNote == "Replaced. Copies opened before now may stay cached for a while.")
        #expect(EditorUploadPlan.shouldPostCacheNote(prior: replace, uploadedKey: key, at: here, alreadyPosted: false))
        #expect(!EditorUploadPlan.shouldPostCacheNote(prior: replace, uploadedKey: key, at: here, alreadyPosted: true))
        // A new link has nothing cached under it: a first upload, Upload as New, or a fallback.
        #expect(!EditorUploadPlan.shouldPostCacheNote(prior: nil, uploadedKey: key, at: here, alreadyPosted: false))
        let asNew = PriorUpload(url: link, key: key, location: here, isReplace: false)
        #expect(!EditorUploadPlan.shouldPostCacheNote(prior: asNew, uploadedKey: "Qx12Zz.png", at: here, alreadyPosted: false))
        #expect(!EditorUploadPlan.shouldPostCacheNote(prior: replace, uploadedKey: "Qx12Zz.png", at: elsewhere, alreadyPosted: false))
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run:
```bash
xcodegen generate && xcodebuild test -project TidyShot.xcodeproj -scheme TidyShot -destination 'platform=macOS' -derivedDataPath .build 2>&1 | grep -E "error:" | sort -u | head -3
```
Expected: compile errors, among them `cannot find 'EditorUploadPlan' in scope`.

- [ ] **Step 3: Write the plan**

`TidyShot/Editor/Persistence/EditorUploadPlan.swift`:
```swift
import Foundation

/// The decisions behind Upload and Upload as New in the editor, and behind a retry of an upload
/// the editor started: which key the PUT goes to, which old object goes after success, and what
/// the record says while the upload runs and after it ends. `AppCoordinator` does the I/O.
nonisolated enum EditorUploadPlan {
    /// What an editor upload does.
    enum Plan: Equatable, Sendable {
        /// PUT the edit over the link's own key, so the URL stays.
        case replace(key: String)
        /// Upload under a new template key. `supersede` is the old object, deleted after success;
        /// `notice` says why the link changes.
        case newObject(supersede: ObjectRef?, notice: String?)
        /// Upload nothing; the reason is posted as "Not uploaded".
        case refuse(String)
    }

    /// How a retry (the overlay's Retry, or Retry Failed Uploads) uploads.
    enum RetryPolicy: Equatable, Sendable {
        /// Re-PUT the key an interrupted or failed replace was writing, so the URL stays.
        case fixed(String)
        /// A new template key, as for any retry. `supersede` is an old object to delete after success.
        case template(supersede: ObjectRef?)
    }

    static let uploadingReason = "This capture is already uploading."
    static let destinationChangedNotice = "The destination changed, so this uploads as a new link."
    static let sharedKeyNotice = "Another capture shares this link, so this uploads as a new link."
    static let legacyNotice = "The earlier upload stays in the bucket."
    /// Posted, titled "Not uploaded", when the upload of a record that has a link fails.
    static let failedReplaceMessage = "Upload failed. The link still shows the earlier image."
    /// Posted once per launch on the first successful same-key replace, whatever Show
    /// notification says: a CDN or a browser may still serve the original.
    static let cacheNote = "Replaced. Copies opened before now may stay cached for a while."

    /// The record's link: its uploaded key where it went, or else the link that an editor upload
    /// in flight or interrupted keeps in `priorUpload`. `location` is nil for a capture uploaded
    /// before Phase 3.
    private static func link(of record: CaptureRecord) -> (url: URL, key: String, location: ObjectLocation?)? {
        if case .uploaded(let url, let key) = record.uploadState {
            return (url, key, record.objectLocation)
        }
        if let prior = record.priorUpload {
            return (prior.url, prior.key, prior.location)
        }
        return nil
    }

    /// The first rule that applies wins:
    /// 1. uploading: refuse;
    /// 2. no link: a plain first upload;
    /// 3. a link with no location (before Phase 3): a new object, and the old one stays;
    /// 4. another capture points at the key: a new object, and the old one stays;
    /// 5. the destination moved: a new object, and the old one is deleted at its own location;
    /// 6. Upload as New: a new object, and the old one is deleted;
    /// 7. otherwise, replace the key.
    /// `currentLocation` is where the upload lane writes; `others` is every other record.
    static func plan(record: CaptureRecord, currentLocation: ObjectLocation, others: [CaptureRecord], asNew: Bool) -> Plan {
        if record.isUploading {
            return .refuse(uploadingReason)
        }
        guard let link = link(of: record) else {
            return .newObject(supersede: nil, notice: nil)
        }
        guard let location = link.location else {
            return .newObject(supersede: nil, notice: legacyNotice)
        }
        if !CaptureDeletion.sharedKeys([link.key], at: location, with: others).isEmpty {
            return .newObject(supersede: nil, notice: sharedKeyNotice)
        }
        let old = ObjectRef(key: link.key, location: location)
        if location != currentLocation {
            return .newObject(supersede: old, notice: destinationChangedNotice)
        }
        if asNew {
            return .newObject(supersede: old, notice: nil)
        }
        return .replace(key: link.key)
    }

    /// A replace in `priorUpload` whose key is unshared and still at `currentLocation` is re-PUT to
    /// the same key. A replace whose destination moved supersedes its old key, unless another
    /// capture shares it. Everything else is a plain template retry.
    static func retryPolicy(record: CaptureRecord, currentLocation: ObjectLocation, others: [CaptureRecord]) -> RetryPolicy {
        guard let prior = record.priorUpload, prior.isReplace else {
            return .template(supersede: nil)
        }
        if !CaptureDeletion.sharedKeys([prior.key], at: prior.location, with: others).isEmpty {
            return .template(supersede: nil)
        }
        if prior.location == currentLocation {
            return .fixed(prior.key)
        }
        return .template(supersede: ObjectRef(key: prior.key, location: prior.location))
    }

    /// The one `history.update` before an editor upload starts: `.uploading(0)`, the link kept in
    /// `priorUpload` (when it has a location), and the superseded old object. A replace takes its
    /// key off the superseded list, because that key is the live link again (after an interrupted
    /// Upload as New, say). A refusal returns the record unchanged.
    static func startingUpload(_ record: CaptureRecord, plan: Plan) -> CaptureRecord {
        var next = record
        let prior = link(of: record).flatMap { link in
            link.location.map { PriorUpload(url: link.url, key: link.key, location: $0, isReplace: false) }
        }
        switch plan {
        case .refuse:
            return record
        case .replace(let key):
            if var prior {
                prior.isReplace = true
                next.priorUpload = prior
                next.supersededObjects.removeAll { $0 == ObjectRef(key: key, location: prior.location) }
            }
        case .newObject(let supersede, _):
            next.priorUpload = prior
            if let supersede, !next.supersededObjects.contains(supersede) {
                next.supersededObjects.append(supersede)
            }
        }
        next.uploadState = .uploading(fraction: 0)
        return next
    }

    /// The record before a retry starts. A fixed retry keeps its key off the superseded list. A
    /// template retry of a replace is a new link from now on (so its success posts no cache note
    /// and its next retry is a template one too), and lists the superseded object it was given.
    static func startingRetry(_ record: CaptureRecord, policy: RetryPolicy) -> CaptureRecord {
        var next = record
        switch policy {
        case .fixed(let key):
            if let prior = record.priorUpload {
                next.supersededObjects.removeAll { $0 == ObjectRef(key: key, location: prior.location) }
            }
        case .template(let supersede):
            next.priorUpload?.isReplace = false
            if let supersede, !next.supersededObjects.contains(supersede) {
                next.supersededObjects.append(supersede)
            }
        }
        return next
    }

    /// After `.uploaded`: the object holds the edit, so the earlier link is settled and the
    /// uploaded copy is current. The superseded list is left for `deleteSupersededObjects`.
    static func applyingSuccess(to record: CaptureRecord) -> CaptureRecord {
        var next = record
        next.priorUpload = nil
        next.uploadIsStale = false
        return next
    }

    /// After `.failed`. With a `priorUpload` the old object is untouched, so the record returns
    /// to `.uploaded` at the prior location, keeps its file and `uploadIsStale`, and drops the
    /// superseded ref the upload added. A key that a cancelled attempt reserved at another
    /// location moves to the superseded list, so it is still deleted there. Without a
    /// `priorUpload` the upload fails as any upload does.
    static func applyingFailure(to record: CaptureRecord, message: String) -> CaptureRecord {
        var next = record
        guard let prior = record.priorUpload else {
            next.uploadState = .failed(message: message)
            return next
        }
        if let reserved = next.pendingObjectKey, let reservedAt = next.objectLocation, reservedAt != prior.location {
            let orphan = ObjectRef(key: reserved, location: reservedAt)
            if !next.supersededObjects.contains(orphan) {
                next.supersededObjects.append(orphan)
            }
            next.pendingObjectKey = nil
        }
        next.uploadState = .uploaded(url: prior.url, key: prior.key)
        next.objectLocation = prior.location
        next.supersededObjects.removeAll { $0 == ObjectRef(key: prior.key, location: prior.location) }
        next.priorUpload = nil
        return next
    }

    /// True for the first upload in this launch that replaced its own key: `prior` was a replace
    /// of `uploadedKey` at `location`.
    static func shouldPostCacheNote(prior: PriorUpload?, uploadedKey: String, at location: ObjectLocation,
                                    alreadyPosted: Bool) -> Bool {
        guard !alreadyPosted, let prior, prior.isReplace else { return false }
        return prior.key == uploadedKey && prior.location == location
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run:
```bash
xcodegen generate && xcodebuild test -project TidyShot.xcodeproj -scheme TidyShot -destination 'platform=macOS' -derivedDataPath .build 2>&1 | grep -E "Test run with|error:|TEST"
```
Expected: no `error:` lines, and `Test run with 388 tests in 50 suites passed`.

- [ ] **Step 5: Fixed-key jobs in `startUpload`**

In `TidyShot/App/AppCoordinator.swift`, replace `startUpload(recordID:data:destination:)` (AppCoordinator.swift:374-396) with:
```swift
    /// Enqueues `data` for `recordID`. `destination` is only used when the queue has to be
    /// created (first upload, or after the Upload tab was saved); callers read it once. With
    /// `fixedKey` the job PUTs that exact key with `Cache-Control: no-cache` and draws no counter
    /// (an editor replace, or a retry of one); otherwise the key is named from the template.
    private func startUpload(recordID: UUID, data: Data, destination: S3Destination, fixedKey: String? = nil) {
        // Look the record up before marking it uploading, so a missing record never leaves an
        // id in `uploadingIDs` (and the menu bar icon spinning) with no job to clear it.
        guard let record = history.record(id: recordID) else { return }
        let lane = queue ?? makeLane(for: destination)
        queue = lane
        uploadingIDs.insert(recordID)
        // `save` and `editorUpload` mark their records uploading and refresh the overlay
        // themselves, so only a retry (a record in another state) needs the write and the refresh.
        if !record.isUploading {
            history.update(id: recordID) { $0.uploadState = .uploading(fraction: 0) }
            refreshOverlay(for: recordID)
        }
        let job: UploadJob
        if let fixedKey {
            job = UploadJob(id: recordID, data: data, contentType: "image/png", fileExtension: "png",
                            fixedKey: fixedKey, cacheControl: "no-cache")
        } else {
            // The key is named now, not at capture time: a capture taken while no destination was
            // set up, and every retry, get a counter drawn when their upload starts. The date stays
            // the capture's own, so a retried upload lands in the capture's date folder.
            let counter = lane.keyTemplate.contains("{counter}") ? settings.nextCounter() : 0
            job = UploadJob(id: recordID, data: data, contentType: "image/png", fileExtension: "png",
                            naming: TemplateContext(date: record.timestamp, counter: counter))
        }
        Task { await lane.queue.enqueue(job) }
    }
```
`save(_:)` (or `persist` after Task 12) calls it without `fixedKey`, so capture uploads are unchanged.

- [ ] **Step 6: Retry consults the policy**

Replace `retry(recordID:destination:)` (AppCoordinator.swift:423-433) with:
```swift
    /// Reads the record's file and starts its upload with `destination`. A record whose delete
    /// is in progress is never re-enqueued, so a retry cannot re-upload what Delete is removing.
    /// An interrupted or failed replace re-PUTs its own key, so its URL stays.
    private func retry(recordID: UUID, destination: S3Destination) {
        guard !deletingIDs.contains(recordID), let record = history.record(id: recordID) else { return }
        let data: Data
        do {
            data = try readLocalFile(of: record)
        } catch {
            markFailed(recordID, message: UploadError.fileUnreadable(record.fileURL?.lastPathComponent ?? "no local file").localizedDescription)
            return
        }
        // The location the lane writes to: the same expression `startUpload` uses for its lane.
        let location = queue?.location ?? ObjectLocation(config: destination.config)
        let policy = EditorUploadPlan.retryPolicy(record: record, currentLocation: location,
                                                  others: history.records.filter { $0.id != recordID })
        let started = EditorUploadPlan.startingRetry(record, policy: policy)
        if started != record {
            history.update(id: recordID) { $0 = started }
        }
        if case .fixed(let key) = policy {
            startUpload(recordID: recordID, data: data, destination: destination, fixedKey: key)
        } else {
            startUpload(recordID: recordID, data: data, destination: destination)
        }
    }
```
`retryUpload(recordID:)` (399) and `retryFailedUploads()` (411) both reach this, so the overlay's Retry and the menu's Retry Failed Uploads re-PUT an interrupted replace. After a quit mid-replace the record is `.failed("Upload was interrupted.")` with its `priorUpload` (Task 14), so it is listed by `history.failedRecords`.

- [ ] **Step 7: Settle the record on upload events, post the cache note, delete superseded objects**

Add after `warnedUploadNotConfigured` (AppCoordinator.swift:49-50):
```swift
    /// Set when the first same-key replace of this launch posts `EditorUploadPlan.cacheNote`.
    @ObservationIgnored private var postedCacheNote = false
```

Replace the `.uploaded` and `.failed` cases of `handle(_:at:)` (AppCoordinator.swift:768-802) with:
```swift
        case .uploaded(let id, let url, let key):
            uploadingIDs.remove(id)
            guard let before = history.record(id: id) else {
                // The record disappeared while its upload was running. Nothing would point at the
                // new object, so remove it again instead of copying or announcing its URL.
                deleteOrphanedObject(key: key, at: location)
                return
            }
            // Upload-only mode: the temporary file has done its job. If it cannot be removed the
            // record keeps pointing at it, so Delete can still remove it later.
            var removedTemporaryFile = false
            if before.fileIsTemporary, let fileURL = before.fileURL {
                removedTemporaryFile = removePendingFile(at: fileURL, context: "after upload")
            }
            history.update(id: id) { record in
                record.uploadState = .uploaded(url: url, key: key)
                if record.objectLocation != location {
                    // A reserved key from another destination named an object there, not here.
                    record.pendingObjectKey = nil
                } else if record.pendingObjectKey == key {
                    record.pendingObjectKey = nil
                }
                record.objectLocation = location
                if removedTemporaryFile {
                    record.fileURL = nil
                    record.fileIsTemporary = false
                }
                record = EditorUploadPlan.applyingSuccess(to: record)
            }
            Pasteboard.copy(url: url)
            if EditorUploadPlan.shouldPostCacheNote(prior: before.priorUpload, uploadedKey: key, at: location,
                                                    alreadyPosted: postedCacheNote) {
                // In place of the usual notification, and also with Show notification off.
                postedCacheNote = true
                notifier.notify(title: "Uploaded, URL copied", body: EditorUploadPlan.cacheNote)
            } else if settings.showNotification {
                notifier.notifyUploaded(url: url)
            }
            refreshOverlay(for: id)
            Task { [weak self] in await self?.deleteSupersededObjects(of: id) }
        case .failed(let id, let message):
            guard history.record(id: id)?.priorUpload != nil else {
                markFailed(id, message: message)
                return
            }
            // An upload of a record that has a link: the old object is untouched, so the record
            // goes back to it, and keeps the edited file and the stale note.
            NSLog("Upload failed, the earlier link is kept: \(message)")
            uploadingIDs.remove(id)
            history.update(id: id) { $0 = EditorUploadPlan.applyingFailure(to: $0, message: message) }
            refreshOverlay(for: id)
            notifier.notifyError(EditorUploadPlan.failedReplaceMessage, title: "Not uploaded")
```
The `.started`, `.progress` and `.cancelled` cases are unchanged. A cancel (from Delete) keeps `priorUpload`, so Delete still sees the prior key through `CaptureDeletion.objects(for:)`. `refreshOverlay` pushes the editor state (Task 13), so both paths reach the editor.

Add under `// MARK: Editor`:
```swift
    /// After a successful upload: deletes each superseded object at its own location, signed with
    /// the credentials stored now. A key another capture points at is kept and dropped from the
    /// list (that capture's own Delete removes it). A key that cannot be deleted stays listed, so
    /// Delete tries it again through `CaptureDeletion.objects(for:)`.
    private func deleteSupersededObjects(of id: UUID) async {
        guard !deletingIDs.contains(id), let record = history.record(id: id), !record.supersededObjects.isEmpty else { return }
        let live = record.uploadedKey.flatMap { key in record.objectLocation.map { ObjectRef(key: key, location: $0) } }
        var settled: [ObjectRef] = []
        for ref in record.supersededObjects {
            if ref == live {
                settled.append(ref) // never delete the link itself
                continue
            }
            let others = history.records.filter { $0.id != id }
            if !CaptureDeletion.sharedKeys([ref.key], at: ref.location, with: others).isEmpty {
                NSLog("Kept superseded \(ref.key): another capture shares it")
                settled.append(ref)
            } else if let reason = await deleteObjects([ref.key], at: ref.location) {
                NSLog("Could not delete superseded \(ref.key): \(reason)")
            } else {
                settled.append(ref)
            }
        }
        history.update(id: id) { $0.supersededObjects.removeAll { settled.contains($0) } }
    }
```
A Delete that starts during these requests may DELETE the same key; a 404 counts as gone, and `history.update` on a removed record does nothing.

- [ ] **Step 8: `editorUpload`, wired into the editor**

Add under `// MARK: Editor`:
```swift
    /// Upload (⌘U) and Upload as New (⌥⌘U). The edit is written locally first, so the file equals
    /// the object; then it goes through the live lane like any upload, over the link's own key for
    /// a replace or under a new template key. Returns true once the edit has been written locally
    /// or handed to the queue, which tells the editor to mark the document saved.
    private func editorUpload(recordID: UUID, image: ScaledImage, asNew: Bool) async -> Bool {
        let action: EditorAction = asNew ? .uploadAsNew : .upload
        // 1. The editor's available set can lag behind the record.
        if refuseUpload(action, recordID: recordID) { return false }
        // 2. Nothing is written, and the record stays as it is, without a destination.
        guard let destination = makeDestination() else {
            notifier.notifyError("Set up a destination in Settings > Upload, then upload again.", title: "Upload not configured")
            return false
        }
        let png: Data
        do {
            png = try await Task.detached(priority: .userInitiated) {
                try ImageEncoder.pngData(from: image.image, scale: image.scale)
            }.value
        } catch {
            notifier.notifyError(error.localizedDescription, title: "Not uploaded")
            return false
        }
        // 3. The local write, on the record as it is after the encode.
        if refuseUpload(action, recordID: recordID) { return false }
        guard let record = history.record(id: recordID) else { return false }
        var wroteLocally = false
        switch EditorSaveTarget.plan(for: record, saveFolder: saveLocation.currentURL) {
        case .saveFolderFile, .pendingFile:
            guard await applyLocalEdit(recordID: recordID, png: png, image: image) else { return false }
            wroteLocally = true
        case .unavailable where record.fileURL == nil:
            // An uploaded upload-only capture: its pending file went after its upload. The edit gets
            // pending/<id>.png, so Retry and Delete see a file and handle(.uploaded) removes it.
            do {
                let url = try pendingFiles.write(png, id: recordID, ext: "png")
                history.update(id: recordID) { record in
                    record.fileURL = url
                    record.fileIsTemporary = true
                }
            } catch {
                NSLog("Pending write failed: \(error.localizedDescription)")
                keepOnClipboard(image, png: png, alreadyOnClipboard: false)
                notifier.notifyError("\(error.localizedDescription) The image is on the clipboard.", title: "Not saved")
                return false
            }
            // Now a pending-file target: applyLocalEdit rewrites the same bytes and does the
            // bookkeeping (pixel size, editedAt, uploadIsStale, thumbnail, clipboard, editor state).
            guard await applyLocalEdit(recordID: recordID, png: png, image: image) else { return false }
            wroteLocally = true
        case .unavailable:
            // A save-folder file outside the current folder, or no folder: the file is not
            // rewritten and the subtitle says so. The clipboard still must not keep the original.
            await replaceClipboardIfStillOriginal(recordID: recordID, png: png, image: image)
        }
        // 4. Plan on the live record, against where the lane writes (as in startUpload).
        if refuseUpload(action, recordID: recordID) { return wroteLocally }
        guard let current = history.record(id: recordID) else { return wroteLocally }
        let location = queue?.location ?? ObjectLocation(config: destination.config)
        let plan = EditorUploadPlan.plan(record: current, currentLocation: location,
                                         others: history.records.filter { $0.id != recordID }, asNew: asNew)
        switch plan {
        case .refuse(let reason):
            notifier.notifyError(reason, title: "Not uploaded")
            return wroteLocally
        case .newObject(_, let notice?):
            notifier.notify(title: "New link", body: notice)
        case .newObject, .replace:
            break
        }
        // 5. Uploading, the prior link and any superseded object, in one write.
        history.update(id: recordID) { $0 = EditorUploadPlan.startingUpload($0, plan: plan) }
        // 6. startUpload skips this refresh for a record already uploading, so the overlay and the
        // editor (through pushEditorState) show Uploading… now, before the first progress event.
        refreshOverlay(for: recordID)
        // 7. Through the live lane: uploadingIDs, progress, cancel, Delete and the menu bar icon.
        if case .replace(let key) = plan {
            startUpload(recordID: recordID, data: png, destination: destination, fixedKey: key)
        } else {
            startUpload(recordID: recordID, data: png, destination: destination)
        }
        return true
    }

    /// Posts the live refusal for `action` as "Not uploaded". True when the upload must stop.
    private func refuseUpload(_ action: EditorAction, recordID: UUID) -> Bool {
        guard let reason = EditorAvailability.refusal(for: action, record: history.record(id: recordID),
                                                      saveFolder: saveLocation.currentURL,
                                                      isDeleting: deletingIDs.contains(recordID)) else { return false }
        notifier.notifyError(reason, title: "Not uploaded")
        return true
    }
```
Steps 4 to 7 run with no `await` between them, so the plan, the record write and the enqueue see the same record and lane. The refusal is checked three times because the encode, `applyLocalEdit` and the clipboard replacement each await, and a Delete or a Retry can start meanwhile.

In `editorActions(for recordID:)` (Task 10), replace the `upload` stub with a closure in the same form as the `save`, `saveCopy` and `copy` closures that Tasks 12 and 13 wired there. `showEditor(recordID:image:)` already passes that value to the controller, so nothing else changes (Task 16 later converts `showEditor` into `presentEditor` and keeps `editorActions(for:)` as the builder):
```swift
upload: { [weak self] image, asNew in
    await self?.editorUpload(recordID: recordID, image: image, asNew: asNew) ?? false
}
```
The controller's `uploadDocument(_:)` and `uploadDocumentAsNew(_:)` call it after `renderExport()` and call `markSaved()` when it returns true; no editor-side change is needed.

- [ ] **Step 9: Run the suite**

Run:
```bash
xcodegen generate && xcodebuild test -project TidyShot.xcodeproj -scheme TidyShot -destination 'platform=macOS' -derivedDataPath .build 2>&1 | grep -E "Test run with|error:|TEST"
```
Expected: no `error:` lines, and `Test run with 388 tests in 50 suites passed`.

- [ ] **Step 10: Check by hand against a real bucket**

```bash
xcodebuild -project TidyShot.xcodeproj -scheme TidyShot -configuration Debug -derivedDataPath .build build -quiet && open .build/Build/Products/Debug/TidyShot.app
```
Use Upload mode with a working destination. Open the editor with `Annotate Last Capture (debug)` in the menu bar menu. Expected:
- Redact an area and press ⌘U. The subtitle reads `Uploading…` at once, before any progress. When it finishes, the URL on the clipboard is the one from before, the object shows the redaction, and `curl -sI <url> | grep -i cache-control` prints `no-cache` (for a URL served straight from the bucket).
- That first replace posts `Replaced. Copies opened before now may stay cached for a while.`, also with Show notification off in Settings. A second replace in the same launch posts the usual `Uploaded, URL copied` only when Show notification is on.
- On a capture whose link is known, press ⌥⌘U. The URL changes, and `curl -sI <old url>` returns 404 once the new upload has finished.
- Change the bucket in Settings > Upload, then upload an earlier capture from the editor: a `New link` notification says `The destination changed, so this uploads as a new link.`, and the old object is gone from the old bucket afterwards.
- Save a wrong secret key in Settings > Upload, then ⌘U on an uploaded capture. `Not uploaded` says `Upload failed. The link still shows the earlier image.`. The overlay and Recent Captures keep the old URL, Copy URL copies it, and the editor subtitle reads `The uploaded copy still shows the original. Upload to replace it.` Restore the key afterwards.
- In Upload-only mode, capture, let it upload, open the editor, redact and ⌘U with the wrong key. The record keeps the old URL and a `pending/<id>.png` that holds the edit (see the container's `pending` folder). With the key restored, the next ⌘U from the same editor replaces the object and the pending file goes.
- Throttle the network (Network Link Conditioner, Very Bad Network), press ⌘U on a large uploaded capture, and quit from the menu bar while the bar runs. Relaunch: Copy URL still gives the old URL. Retry Failed Uploads re-uploads to the same key (the URL is unchanged and no new object appears in the bucket).
- Quit mid-replace as above and relaunch (the capture is `.failed`, Copy URL still works). In its editor, redact and press ⌘S (or ⌘U), then make the upload fail with the wrong secret key. The subtitle still reads `The uploaded copy still shows the original. Upload to replace it.`, and in Upload-only mode the `pending/<id>.png` is still there after the retention pass. Upload as New (⌥⌘U) is enabled on that capture too, and with the key restored it uploads to a new key and deletes the old object.
- Press ⌘U on a large capture and Delete it from Recent Captures while the replace runs. The upload stops, and the object is gone from the bucket.

- [ ] **Step 11: Commit**

```bash
git add TidyShot/Editor/Persistence/EditorUploadPlan.swift TidyShotTests/EditorUploadPlanTests.swift TidyShot/App/AppCoordinator.swift
git commit -m "feat: upload and upload as new from the editor"
```

---

### Task 16: Annotate on the overlay and on Recent Captures (TDD for the image source)

**Files:**
- Create: `TidyShot/Editor/Persistence/EditorInput.swift`
- Modify: `TidyShot/Overlay/QuickAccessController.swift`, `TidyShot/Overlay/QuickAccessModel.swift`, `TidyShot/Overlay/QuickAccessView.swift`
- Modify: `TidyShot/RecentCaptures/RecentCaptureFormatting.swift`, `TidyShot/RecentCaptures/RecentCaptureRow.swift`, `TidyShot/RecentCaptures/RecentCaptureMenuItemView.swift`, `TidyShot/RecentCaptures/RecentCapturesMenu.swift`
- Modify: `TidyShot/App/AppCoordinator.swift`, `TidyShot/App/StatusMenuController.swift`
- Test: `TidyShotTests/EditorInputTests.swift` (new), `TidyShotTests/RecentCaptureFormattingTests.swift` (two tests added)

Line numbers are those at f4541da. The Overlay and Recent Captures files are untouched by Tasks 1 to 15, apart from `canCopyLink` in RecentCaptureFormatting.swift (Task 14). AppCoordinator.swift has changed since (Tasks 10 and 12 to 15), so each AppCoordinator edit also names the code it anchors on.

**Interfaces:**
- Consumes:
  - `QuickAccessController.Actions { var copy, retry, reveal, delete: (UUID) -> Void }` (QuickAccessController.swift:6-12), `func show(record: CaptureRecord, thumbnail: NSImage?, corner: OverlayCorner, autoCloseSeconds: Double, actions: Actions)` (:19), `func close(recordID: UUID)` (:54) and `func close()` (:59).
  - QuickAccessModel's `@ObservationIgnored var onCopy, onRetry, onReveal, onDelete, onClose: () -> Void = {}` (QuickAccessModel.swift:11-15).
  - `struct RecentCaptureActions { var copyLinkOrFile, copyLink, copyImage, delete: (UUID) -> Void }` (RecentCaptureRow.swift:4-11) and the row's `private func iconButton(_ symbol: String, label: String, enabled: Bool, action: @escaping () -> Void) -> some View` (:96).
  - `RecentCaptureMenuItemView.init(record: CaptureRecord, now: Date, provider: ThumbnailProvider, actions: RecentCaptureActions, onThumbnailHover: @escaping (RecentCaptureMenuItemView, Bool) -> Void)` (RecentCaptureMenuItemView.swift:17-18).
  - `private func afterMenusClose(_ work: @escaping @MainActor (AppCoordinator) -> Void)` (RecentCapturesMenu.swift:115).
  - In AppCoordinator: `func save(_ result: CaptureResult) async` (:156, refactored by Task 12 with the same signature); `private func showOverlay(for record: CaptureRecord, image: CGImage?, scale: CGFloat)` (:302); `private func removeRecord(id: UUID)` (:657); `private func imageData(of record: CaptureRecord) async throws -> Data` (:489); `private func downloadImage(of record: CaptureRecord) async throws -> Data` (:511); `private let notifier` (:27); `private let overlay` (:29); `CopyImageError.notAnImage` (:885).
  - `SaveLocation.currentURL` (SaveLocation.swift:10) and `nonisolated static func SaveLocation.contains(_ fileURL: URL, inFolder folder: URL) -> Bool` (Task 13).
  - `CaptureRecord.fileURL`, `fileIsTemporary`, `objectLocation` and `uploadedKey` (CaptureRecord.swift:17, 20, 31, 81). `var uploadIsStale: Bool` (Task 13) is used by the tests only.
  - `nonisolated struct ScaledImage: Sendable { let image: CGImage; let scale: CGFloat }` (Task 2).
  - `ImageEncoder.decode(_ data: Data) -> (image: CGImage, scale: CGFloat)?` (ImageEncoder.swift:42).
  - Task 10: `private var editors: [UUID: EditorWindowController]`, `EditorWindowController.present()`, `func openEditor(recordID: UUID)` (loads and decodes only), `private func showEditor(recordID: UUID, image: ScaledImage)` (builds the model and the window, stores the controller in `editors`, warms the renderer and presents) and `private func editorActions(for recordID: UUID) -> EditorActions`. This task rewrites `openEditor` and converts `showEditor` into `presentEditor`; `editorActions(for:)` stays as the one place the closures are built. Task 10 also added the `#if DEBUG` status menu item `Annotate Last Capture (debug)`, which this task removes.
  - Task 13: `private func pushEditorState(for id: UUID)` and `private func observeSaveFolderForEditors()`, called from `showEditor` after the controller is stored in `editors`.
  - Kept as they are in `showEditor`, which becomes `presentEditor`: `EditorModel(recordID:image:renderer:defaults:)` (Task 8) with `RedactionRenderer.shared` (Task 5) and `settings.editorDefaults` (Task 11), `EditorWindowController(model:actions:title:representedURL:cascadeFrom:)` with `actions: editorActions(for:)` and its `onClose` (Task 10), the `editors` insert, Task 13's `pushEditorState` and `observeSaveFolderForEditors` calls, and the warm-up. `editorActions(for:)` holds the closures of `editorSave(recordID:image:)` (Task 13), `editorSaveCopy(of:image:)` and `editorCopy(recordID:image:)` (Task 12) and `editorUpload(recordID:image:asNew:)` (Task 15), and this task does not touch it.
- Produces:
  - `nonisolated enum EditorInput { enum Source: Equatable, Sendable { case retained, pendingFile(URL), saveFolderFile(URL), download(key: String, location: ObjectLocation), unavailable(String) }; static let neverUploadedText: String; static let unknownLocationText: String; static let outsideSaveFolderText: String; static func source(for record: CaptureRecord, retainedID: UUID?, saveFolder: URL?) -> Source }`.
  - `RecentCaptureFormatting.canAnnotate(_ record: CaptureRecord, retainedID: UUID?, saveFolder: URL?) -> Bool`.
  - `QuickAccessController.Actions.annotate: (UUID) -> Void`, the last member, so the memberwise init is `Actions(copy:retry:reveal:delete:annotate:)`. Also `QuickAccessController.onDidClose: ((UUID) -> Void)?`.
  - `QuickAccessModel.onAnnotate: () -> Void` (`@ObservationIgnored`, default `{}`).
  - QuickAccessView: an Annotate button (`pencil.tip.crop.circle`, help `Annotate`) at the top of the right column, above Close and Delete. Column spacing is 8, and `QuickAccessView.size` stays 340x104.
  - `RecentCaptureActions.annotate: (UUID) -> Void`, declared after `copyLinkOrFile`, so the memberwise init is `RecentCaptureActions(copyLinkOrFile:annotate:copyLink:copyImage:delete:)`.
  - `RecentCaptureRow.canAnnotate: Bool` (after `canCopyImage`), and a fourth icon button, Annotate, before Copy URL.
  - `RecentCaptureMenuItemView.init(record: CaptureRecord, now: Date, saveFolder: URL?, retainedID: UUID?, provider: ThumbnailProvider, actions: RecentCaptureActions, onThumbnailHover: @escaping (RecentCaptureMenuItemView, Bool) -> Void)`.
  - AppCoordinator:
    - `@ObservationIgnored private var latestCapture: (id: UUID, image: ScaledImage)?` and `@ObservationIgnored private var openingEditorIDs: Set<UUID>`.
    - `var retainedCaptureID: UUID? { get }`.
    - `func openEditor(recordID: UUID)`, now driven by EditorInput.
    - `private func loadAndPresentEditor(for record: CaptureRecord) async` and `private func presentEditor(record: CaptureRecord, image: ScaledImage)`, which replaces Task 10's `showEditor(recordID:image:)` (the old function is renamed, not left behind).
    - `private func forgetLatestCapture(_ id: UUID)` and `private func openEditorAfterMenuTracking(recordID: UUID)`.
    - `private func imageData(of record: CaptureRecord, downloadTitle: String = "Copying image…") async throws -> Data` and `private func downloadImage(of record: CaptureRecord, title: String) async throws -> Data`.

- [ ] **Step 1: Write the failing tests**

`TidyShotTests/EditorInputTests.swift`:
```swift
import Foundation
import Testing
@testable import TidyShot

struct EditorInputTests {
    let folder = URL(fileURLWithPath: "/Users/tim/Pictures/TidyShot", isDirectory: true)
    let saved = URL(fileURLWithPath: "/Users/tim/Pictures/TidyShot/Shot.png")
    /// A file in a folder that is no longer the save folder.
    let elsewhere = URL(fileURLWithPath: "/Users/tim/Desktop/Old Shots/Shot.png")
    let pending = URL(fileURLWithPath: "/Users/tim/Library/Containers/TidyShot/Data/pending/A.png")
    let link = URL(string: "https://snap.tky.io/aB3dE9.png")!
    let location = ObjectLocation(endpoint: "https://s3.us-west-2.amazonaws.com", region: "us-west-2",
                                  bucket: "snap", usePathStyle: false)

    func record(_ state: CaptureRecord.UploadState = .none, file: URL?, temporary: Bool = false,
                location: ObjectLocation? = nil) -> CaptureRecord {
        CaptureRecord(fileURL: file, fileIsTemporary: temporary, pixelWidth: 10, pixelHeight: 10, appName: nil,
                      uploadState: state, objectLocation: location)
    }

    @Test func retainedWinsForLatestCapture() {
        let uploading = record(.uploading(fraction: 0.4), file: pending, temporary: true)
        #expect(EditorInput.source(for: uploading, retainedID: uploading.id, saveFolder: folder) == .retained)
        // Upload-only, uploaded: the pending file went with the upload, the image is still in memory.
        let uploadedOnly = record(.uploaded(url: link, key: "aB3dE9.png"), file: nil, location: location)
        #expect(EditorInput.source(for: uploadedOnly, retainedID: uploadedOnly.id, saveFolder: nil) == .retained)
        // Another capture's image is not this one's.
        let savedRecord = record(file: saved)
        #expect(EditorInput.source(for: savedRecord, retainedID: UUID(), saveFolder: folder) == .saveFolderFile(saved))
    }

    @Test func pendingFileForUploadOnlyPending() {
        let uploading = record(.uploading(fraction: 0.4), file: pending, temporary: true)
        #expect(EditorInput.source(for: uploading, retainedID: nil, saveFolder: folder) == .pendingFile(pending))
        // A pending file needs no save folder.
        let failed = record(.failed(message: "Upload not configured"), file: pending, temporary: true)
        #expect(EditorInput.source(for: failed, retainedID: nil, saveFolder: nil) == .pendingFile(pending))
        // After a failed replace the pending file holds the edit and the object the original: the file wins.
        var stale = record(.uploaded(url: link, key: "aB3dE9.png"), file: pending, temporary: true, location: location)
        stale.uploadIsStale = true
        #expect(EditorInput.source(for: stale, retainedID: nil, saveFolder: nil) == .pendingFile(pending))
    }

    @Test func saveFolderFileForSavedCapture() {
        #expect(EditorInput.source(for: record(file: saved), retainedID: nil, saveFolder: folder) == .saveFolderFile(saved))
        // Upload mode: the file is read before the object, also once uploaded.
        let uploaded = record(.uploaded(url: link, key: "aB3dE9.png"), file: saved, location: location)
        #expect(EditorInput.source(for: uploaded, retainedID: nil, saveFolder: folder) == .saveFolderFile(saved))
    }

    @Test func downloadWhenFileGoneAndUploaded() {
        let uploadedOnly = record(.uploaded(url: link, key: "shots/aB3dE9.png"), file: nil, location: location)
        #expect(EditorInput.source(for: uploadedOnly, retainedID: nil, saveFolder: folder)
                == .download(key: "shots/aB3dE9.png", location: location))
    }

    @Test func unavailableForLegacyRecordWithoutFileOrLocation() {
        let legacy = record(.uploaded(url: link, key: "aB3dE9.png"), file: nil)
        #expect(EditorInput.source(for: legacy, retainedID: nil, saveFolder: folder)
                == .unavailable(EditorInput.unknownLocationText))
    }

    @Test func unavailableWhenNeverUploadedAndNoFile() {
        let nothing = record(.failed(message: "Upload was interrupted."), file: nil)
        #expect(EditorInput.source(for: nothing, retainedID: nil, saveFolder: folder)
                == .unavailable(EditorInput.neverUploadedText))
        #expect(EditorInput.source(for: record(file: nil), retainedID: nil, saveFolder: folder)
                == .unavailable(EditorInput.neverUploadedText))
    }

    /// Uploaded before Phase 3: a file and a key, but no location to download from.
    @Test func legacyRecordWithFileReadsTheFile() {
        let legacy = record(.uploaded(url: link, key: "aB3dE9.png"), file: saved)
        #expect(EditorInput.source(for: legacy, retainedID: nil, saveFolder: folder) == .saveFolderFile(saved))
        let otherFolder = URL(fileURLWithPath: "/Users/tim/Desktop", isDirectory: true)
        #expect(EditorInput.source(for: legacy, retainedID: nil, saveFolder: otherFolder)
                == .unavailable(EditorInput.outsideSaveFolderText))
    }

    @Test func fileOutsideSaveFolderDownloadsWhenUploaded() {
        let moved = record(.uploaded(url: link, key: "aB3dE9.png"), file: elsewhere, location: location)
        #expect(EditorInput.source(for: moved, retainedID: nil, saveFolder: folder)
                == .download(key: "aB3dE9.png", location: location))
        #expect(EditorInput.source(for: moved, retainedID: nil, saveFolder: nil)
                == .download(key: "aB3dE9.png", location: location))
    }

    @Test func fileOutsideSaveFolderWithoutUploadIsUnavailable() {
        let old = record(file: elsewhere)
        #expect(EditorInput.source(for: old, retainedID: nil, saveFolder: folder)
                == .unavailable(EditorInput.outsideSaveFolderText))
        #expect(EditorInput.source(for: old, retainedID: nil, saveFolder: nil)
                == .unavailable(EditorInput.outsideSaveFolderText))
    }
}
```

In `TidyShotTests/RecentCaptureFormattingTests.swift`, add these two tests to the struct. They use its `record(_:file:secondsAgo:location:appName:)` helper, whose default file is `/Users/tim/Desktop/Shot.png`, and its `location`:
```swift
    @Test func annotateIsEnabledWhenTheEditorCanLoadTheImage() {
        let desktop = URL(fileURLWithPath: "/Users/tim/Desktop", isDirectory: true)
        let url = URL(string: "https://snap.tky.io/aB3dE9.png")!
        #expect(RecentCaptureFormatting.canAnnotate(record(.none), retainedID: nil, saveFolder: desktop))
        #expect(RecentCaptureFormatting.canAnnotate(record(.uploading(fraction: 0.5)), retainedID: nil, saveFolder: desktop))
        // Upload-only and uploaded: downloaded with a signed GET.
        let uploadOnly = record(.uploaded(url: url, key: "aB3dE9.png"), file: nil, location: location)
        #expect(RecentCaptureFormatting.canAnnotate(uploadOnly, retainedID: nil, saveFolder: nil))
    }

    @Test func annotateIsDisabledWhenThereIsNothingToLoad() {
        let url = URL(string: "https://snap.tky.io/aB3dE9.png")!
        // Uploaded before Phase 3, with no file and no location.
        let legacy = record(.uploaded(url: url, key: "aB3dE9.png"), file: nil)
        #expect(!RecentCaptureFormatting.canAnnotate(legacy, retainedID: nil, saveFolder: nil))
        // Saved to a folder that is no longer the save folder, never uploaded...
        let pictures = URL(fileURLWithPath: "/Users/tim/Pictures", isDirectory: true)
        let moved = record(.none)
        #expect(!RecentCaptureFormatting.canAnnotate(moved, retainedID: nil, saveFolder: pictures))
        // ...unless it is the capture just taken, whose image is still in memory.
        #expect(RecentCaptureFormatting.canAnnotate(moved, retainedID: moved.id, saveFolder: pictures))
    }
```

- [ ] **Step 2: Run the tests to verify they fail**

Run:
```bash
xcodegen generate && xcodebuild test -project TidyShot.xcodeproj -scheme TidyShot -destination 'platform=macOS' -derivedDataPath .build 2>&1 | grep -E "Test run with|error:|TEST"
```
Expected: compile errors, among them `cannot find 'EditorInput' in scope` and `type 'RecentCaptureFormatting' has no member 'canAnnotate'`.

- [ ] **Step 3: Write the image-source table and the row flag**

`TidyShot/Editor/Persistence/EditorInput.swift`:
```swift
import Foundation

/// Where the annotation editor gets a capture's pixels, decided before anything is read.
/// `AppCoordinator.openEditor(recordID:)` acts on it, and `RecentCaptureFormatting.canAnnotate`
/// disables a row's Annotate button when it is `.unavailable`.
nonisolated enum EditorInput {
    enum Source: Equatable, Sendable {
        /// The capture just taken, still in memory (`AppCoordinator.latestCapture`).
        case retained
        /// An upload-only capture's PNG in the container's `pending` folder.
        case pendingFile(URL)
        /// A PNG in the current save folder, read under the folder's security scope.
        case saveFolderFile(URL)
        /// The uploaded object, fetched with a signed GET from where it went.
        case download(key: String, location: ObjectLocation)
        /// Nothing the editor can load. The reason is the body of the "Could not open the capture"
        /// notification.
        case unavailable(String)
    }

    static let neverUploadedText = "This capture has no local file and was never uploaded."
    static let unknownLocationText = "This capture has no local file, and TidyShot does not know where its upload went."
    static let outsideSaveFolderText = "The file is not in the current save folder, so TidyShot cannot read it."

    /// The order matches what `imageData(of:)` would do, so the editor opens from the same copy
    /// Copy Image uses:
    /// 1. The retained image, when `retainedID` is this record's.
    /// 2. A pending file. It holds the newest pixels, also after a failed replace whose object still
    ///    shows the original.
    /// 3. A file in `saveFolder`. A file outside it, or with no folder, cannot be read under the
    ///    sandbox, so it falls through.
    /// 4. The uploaded object, when its location is known.
    /// 5. Otherwise `.unavailable`, with the reason.
    static func source(for record: CaptureRecord, retainedID: UUID?, saveFolder: URL?) -> Source {
        if record.id == retainedID { return .retained }
        if let fileURL = record.fileURL {
            if record.fileIsTemporary { return .pendingFile(fileURL) }
            if let saveFolder, SaveLocation.contains(fileURL, inFolder: saveFolder) { return .saveFolderFile(fileURL) }
        }
        if let key = record.uploadedKey, let location = record.objectLocation {
            return .download(key: key, location: location)
        }
        if record.fileURL != nil { return .unavailable(outsideSaveFolderText) }
        return .unavailable(record.uploadedKey == nil ? neverUploadedText : unknownLocationText)
    }
}
```

In `TidyShot/RecentCaptures/RecentCaptureFormatting.swift`, after `canCopyImage(_:)` (lines 32-35), add:
```swift

    /// Annotate needs an image the editor can load: the capture just taken (still in memory), a
    /// file it can read, or an uploaded object whose bucket is known. Only `.unavailable` disables
    /// the button, for example a record from before Phase 3 with no file, or a file outside the
    /// current save folder that was never uploaded.
    static func canAnnotate(_ record: CaptureRecord, retainedID: UUID?, saveFolder: URL?) -> Bool {
        if case .unavailable = EditorInput.source(for: record, retainedID: retainedID, saveFolder: saveFolder) {
            return false
        }
        return true
    }
```

- [ ] **Step 4: Run the tests to verify they pass**

Run:
```bash
xcodegen generate && xcodebuild test -project TidyShot.xcodeproj -scheme TidyShot -destination 'platform=macOS' -derivedDataPath .build 2>&1 | grep -E "Test run with|error:|TEST"
```
Expected: no `error:` lines, and `Test run with 399 tests in 51 suites passed`.

- [ ] **Step 5: Annotate on the overlay**

In `TidyShot/Overlay/QuickAccessController.swift`, replace the `Actions` struct (lines 6-12):
```swift
    struct Actions {
        var copy: (UUID) -> Void
        var retry: (UUID) -> Void
        var reveal: (UUID) -> Void
        /// Deletes the capture everywhere after one confirmation; see `AppCoordinator.deleteCapture`.
        var delete: (UUID) -> Void
    }
```
with:
```swift
    struct Actions {
        var copy: (UUID) -> Void
        var retry: (UUID) -> Void
        var reveal: (UUID) -> Void
        /// Deletes the capture everywhere after one confirmation; see `AppCoordinator.deleteCapture`.
        var delete: (UUID) -> Void
        /// Opens the annotation editor; see `AppCoordinator.openEditor(recordID:)`. Stays enabled
        /// while the upload runs.
        var annotate: (UUID) -> Void
    }

    /// Called with the record's id each time a panel closes, whatever closed it: the Close button,
    /// the auto-close timer, a delete, the editor opening, or the next capture's panel replacing it.
    var onDidClose: ((UUID) -> Void)?
```

After `model.onDelete = { actions.delete(record.id) }` (line 25), add:
```swift
        model.onAnnotate = { actions.annotate(record.id) }
```

Replace `close()` (lines 59-65):
```swift
    func close() {
        closeTask?.cancel()
        closeTask = nil
        panel?.orderOut(nil)
        panel = nil
        model = nil
    }
```
with:
```swift
    func close() {
        closeTask?.cancel()
        closeTask = nil
        let closedID = model?.record.id
        panel?.orderOut(nil)
        panel = nil
        model = nil
        if let closedID {
            onDidClose?(closedID)
        }
    }
```

In `TidyShot/Overlay/QuickAccessModel.swift`, after `@ObservationIgnored var onDelete: () -> Void = {}` (line 14), add:
```swift
    @ObservationIgnored var onAnnotate: () -> Void = {}
```

In `TidyShot/Overlay/QuickAccessView.swift`, change the doc comment (line 3) to:
```swift
/// Thumbnail, upload status, and annotate, copy, retry, close and delete buttons. Hosted in `QuickAccessPanel`.
```
Then replace (lines 16-18):
```swift
            VStack(spacing: 10) {
                Button {
                    model.onClose()
```
with:
```swift
            VStack(spacing: 8) {
                Button {
                    model.onAnnotate()
                } label: {
                    Image(systemName: "pencil.tip.crop.circle")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Annotate")
                .accessibilityLabel("Annotate")
                Button {
                    model.onClose()
```
The button has no `.disabled`, so it stays enabled during an upload. `Self.size` (line 5) stays `CGSize(width: 340, height: 104)`.

- [ ] **Step 6: Annotate on Recent Captures rows**

In `TidyShot/RecentCaptures/RecentCaptureRow.swift`, replace `RecentCaptureActions` (lines 3-11):
```swift
/// What a Recent Captures row's buttons do. `RecentCapturesMenu` makes each one close the menu first.
struct RecentCaptureActions {
    /// Clicking the row: the URL, or the file when the capture was never uploaded.
    var copyLinkOrFile: (UUID) -> Void
    var copyLink: (UUID) -> Void
```
with:
```swift
/// What a Recent Captures row's buttons do. `RecentCapturesMenu` makes each one close the menu first.
struct RecentCaptureActions {
    /// Clicking the row: the URL, or the file when the capture was never uploaded.
    var copyLinkOrFile: (UUID) -> Void
    /// Opens the annotation editor (`AppCoordinator.openEditor(recordID:)`), once menu tracking has ended.
    var annotate: (UUID) -> Void
    var copyLink: (UUID) -> Void
```

Change the row's doc comment (lines 19-21) to say "and Annotate, Copy URL, Copy Image and Delete buttons". After `let canCopyImage: Bool` (line 35), add:
```swift
    /// From `RecentCaptureFormatting.canAnnotate`; false when `EditorInput.source` is `.unavailable`.
    let canAnnotate: Bool
```

Before the Copy URL button (line 62), add:
```swift
            iconButton("pencil.tip.crop.circle", label: "Annotate", enabled: canAnnotate) { actions.annotate(record.id) }
```
`RecentCaptureRow.size` stays 360x52. The fourth button narrows the name column by 28 pt, and the name already truncates in the middle.

In `TidyShot/RecentCaptures/RecentCaptureMenuItemView.swift`, replace lines 17-27:
```swift
    init(record: CaptureRecord, now: Date, provider: ThumbnailProvider, actions: RecentCaptureActions,
         onThumbnailHover: @escaping (RecentCaptureMenuItemView, Bool) -> Void) {
        recordID = record.id
        self.onThumbnailHover = onThumbnailHover
        super.init(frame: CGRect(origin: .zero, size: RecentCaptureRow.size))
        let name = RecentCaptureFormatting.name(for: record)
        let detail = RecentCaptureFormatting.detail(for: record, now: now)
        let row = RecentCaptureRow(record: record, name: name, detail: detail,
                                   canCopyLink: RecentCaptureFormatting.canCopyLink(record),
                                   canCopyImage: RecentCaptureFormatting.canCopyImage(record),
                                   state: state, provider: provider, actions: actions)
```
with:
```swift
    /// `saveFolder` and `retainedID` say what Annotate can load from; the menu reads them once per rebuild.
    init(record: CaptureRecord, now: Date, saveFolder: URL?, retainedID: UUID?, provider: ThumbnailProvider,
         actions: RecentCaptureActions, onThumbnailHover: @escaping (RecentCaptureMenuItemView, Bool) -> Void) {
        recordID = record.id
        self.onThumbnailHover = onThumbnailHover
        super.init(frame: CGRect(origin: .zero, size: RecentCaptureRow.size))
        let name = RecentCaptureFormatting.name(for: record)
        let detail = RecentCaptureFormatting.detail(for: record, now: now)
        let row = RecentCaptureRow(record: record, name: name, detail: detail,
                                   canCopyLink: RecentCaptureFormatting.canCopyLink(record),
                                   canCopyImage: RecentCaptureFormatting.canCopyImage(record),
                                   canAnnotate: RecentCaptureFormatting.canAnnotate(record, retainedID: retainedID,
                                                                                    saveFolder: saveFolder),
                                   state: state, provider: provider, actions: actions)
```

In `TidyShot/RecentCaptures/RecentCapturesMenu.swift`, change the end of the type comment (lines 5-6) to "so neither the delete alert nor the editor window opens inside the menu's tracking loop." In `rebuild()`, replace lines 50-57:
```swift
        let now = Date()
        let actions = makeActions()
        for record in records {
            let row = NSMenuItem()
            row.view = RecentCaptureMenuItemView(record: record, now: now, provider: coordinator.thumbnailProvider,
                                                 actions: actions, onThumbnailHover: { [weak self] view, inside in
                                                     self?.thumbnailHover(view, inside: inside)
                                                 })
```
with:
```swift
        let now = Date()
        let actions = makeActions()
        let saveFolder = coordinator.saveLocation.currentURL
        let retainedID = coordinator.retainedCaptureID
        for record in records {
            let row = NSMenuItem()
            row.view = RecentCaptureMenuItemView(record: record, now: now, saveFolder: saveFolder, retainedID: retainedID,
                                                 provider: coordinator.thumbnailProvider,
                                                 actions: actions, onThumbnailHover: { [weak self] view, inside in
                                                     self?.thumbnailHover(view, inside: inside)
                                                 })
```

In `makeActions()`, after the `copyLinkOrFile:` line (line 106), add:
```swift
            annotate: { [weak self] id in self?.afterMenusClose { $0.openEditor(recordID: id) } },
```

- [ ] **Step 7: Keep the capture just taken, and open the editor from it or from storage**

All in `TidyShot/App/AppCoordinator.swift`.

1. After `@ObservationIgnored private var warnedUploadNotConfigured = false` (line 50), add:
```swift
    /// The capture just taken and its pixels, kept while its overlay shows, so Annotate opens the
    /// editor at once: also while the upload runs, and after an upload-only capture's pending file
    /// is gone. The overlay's NSImage wraps the same CGImage, so this costs no memory. Cleared when
    /// the overlay closes, by the next capture and by `removeRecord`.
    @ObservationIgnored private var latestCapture: (id: UUID, image: ScaledImage)?
    /// Records whose editor image is loading, so a second Annotate does not open a second editor.
    @ObservationIgnored private var openingEditorIDs: Set<UUID> = []
```
   After `var isUploading: Bool { !uploadingIDs.isEmpty }` (line 59), add:
```swift
    /// The record whose image is retained, for the Annotate flag on Recent Captures rows.
    var retainedCaptureID: UUID? { latestCapture?.id }
```

2. In `init()`, after `history.didPrune = { [weak self] records in self?.removeFiles(ofPruned: records) }` (line 67), add:
```swift
        overlay.onDidClose = { [weak self] id in self?.forgetLatestCapture(id) }
```

3. Make `latestCapture = nil` the first statement of `save(_ result: CaptureResult) async` (line 156; Task 12 kept the signature). This is "the next capture": an older overlay left open with Show overlay off then loads from its file.

4. In `showOverlay(for:image:scale:)` (lines 302-312), replace:
```swift
                        delete: { [weak self] id in Task { await self?.deleteCapture(recordID: id) } }))
    }
```
with:
```swift
                        delete: { [weak self] id in Task { await self?.deleteCapture(recordID: id) } },
                        annotate: { [weak self] id in self?.openEditorAfterMenuTracking(recordID: id) }))
        // After `show`: its `close()` of the previous panel has already reported that capture.
        latestCapture = image.map { (id: record.id, image: ScaledImage(image: $0, scale: scale)) }
    }
```
   Since Task 12 the caller is `persist`, which Save Copy also uses, so a Save Copy's overlay keeps its edited image too.

5. In `removeRecord(id:)` (lines 657-666), add `forgetLatestCapture(id)` on the line before `overlay.close(recordID: id)`.

6. Give the download notice a title, so opening the editor does not say "Copying image…". Change `private func imageData(of record: CaptureRecord) async throws -> Data` (line 489) to `private func imageData(of record: CaptureRecord, downloadTitle: String = "Copying image…") async throws -> Data`. Change its two `downloadImage(of:)` calls (lines 504 and 506) to `downloadImage(of: current, title: downloadTitle)` and `downloadImage(of: record, title: downloadTitle)`. Change `private func downloadImage(of record: CaptureRecord) async throws -> Data` (line 511) to `private func downloadImage(of record: CaptureRecord, title: String) async throws -> Data`, and its notification (line 516) to `notifier.notify(title: title, body: "Downloading \(key)")`. `copyImage(recordID:)` (line 468) keeps the default.

7. Under `// MARK: Editor`, replace Task 10's `openEditor(recordID:)` with the code below. `forgetLatestCapture(_:)` and `openEditorAfterMenuTracking(recordID:)` go in the same section.
```swift
    /// Opens the annotation editor for a capture, or brings its open editor forward. The capture
    /// just taken opens at once from the image kept in memory. Any other capture is read from its
    /// file or downloaded through `imageData(of:)`, and the PNG is decoded in a detached task, which
    /// also recovers its scale. Callers run this once menu tracking has ended.
    func openEditor(recordID: UUID) {
        if let open = editors[recordID] {
            open.present()
            return
        }
        guard !openingEditorIDs.contains(recordID), let record = history.record(id: recordID) else { return }
        switch EditorInput.source(for: record, retainedID: latestCapture?.id, saveFolder: saveLocation.currentURL) {
        case .retained:
            guard let retained = latestCapture else { return }
            presentEditor(record: record, image: retained.image)
        case .pendingFile, .saveFolderFile, .download:
            openingEditorIDs.insert(recordID)
            Task { [weak self] in
                await self?.loadAndPresentEditor(for: record)
            }
        case .unavailable(let reason):
            notifier.notifyError(reason, title: "Could not open the capture")
        }
    }

    /// Reads or downloads the PNG, decodes it off the main actor, then opens the editor, unless
    /// the record was deleted or an editor for it opened during the load.
    private func loadAndPresentEditor(for record: CaptureRecord) async {
        defer { openingEditorIDs.remove(record.id) }
        let image: ScaledImage
        do {
            let png = try await imageData(of: record, downloadTitle: "Opening the capture…")
            let decoded = await Task.detached(priority: .userInitiated) { () -> ScaledImage? in
                ImageEncoder.decode(png).map { ScaledImage(image: $0.image, scale: $0.scale) }
            }.value
            guard let decoded else { throw CopyImageError.notAnImage }
            image = decoded
        } catch {
            notifier.notifyError(error.localizedDescription, title: "Could not open the capture")
            return
        }
        guard editors[record.id] == nil, let current = history.record(id: record.id) else { return }
        presentEditor(record: current, image: image)
    }

    /// Drops the retained image if it is `id`'s.
    private func forgetLatestCapture(_ id: UUID) {
        if latestCapture?.id == id {
            latestCapture = nil
        }
    }

    /// The overlay's Annotate: runs `openEditor` when the run loop is back in its default mode,
    /// after any menu tracking, as `RecentCapturesMenu.afterMenusClose` does for rows.
    private func openEditorAfterMenuTracking(recordID: UUID) {
        RunLoop.main.perform(inModes: [.default]) {
            MainActor.assumeIsolated { self.openEditor(recordID: recordID) }
        }
    }
```

   Convert Task 10's `showEditor(recordID:image:)` into `private func presentEditor(record: CaptureRecord, image: ScaledImage)`. It is a rename and a change of parameters, not a second copy: delete `showEditor`, and keep `editorActions(for:)` where it is. Task 10's `openEditor` built nothing after decoding, so nothing moves out of it. In `presentEditor`:
   1. Drop `showEditor`'s opening re-check of `editors[recordID]` and its `history.record(id:)` guard. `openEditor` and `loadAndPresentEditor` now make both checks, and the record is a parameter. Use `record.id` where the body used `recordID`.
   2. Keep, in order: the title and `representedURL` from the record (a pending file gets `Capture <time>` and no proxy icon); `EditorModel(recordID: record.id, image: image, renderer: RedactionRenderer.shared, defaults: settings.editorDefaults)`; `EditorWindowController(model:actions:title:representedURL:cascadeFrom:)` with `actions: editorActions(for: record.id)`, which now holds the Task 12, 13 and 15 closures; its `onClose`; `editors[record.id] = controller`; Task 13's `pushEditorState(for: record.id)` and `observeSaveFolderForEditors()`; the renderer warm-up; `controller.present()`.

   Then add, as the last line:
```swift
        // The editor is now the capture's surface; the record stays in Recent Captures.
        overlay.close(recordID: record.id)
```
   `close(recordID:)` closes the panel only when it shows this record. Its `onDidClose` then clears `latestCapture`, which the editor no longer needs.

- [ ] **Step 8: Remove the debug menu item**

In `TidyShot/App/StatusMenuController.swift`, delete the `Annotate Last Capture (debug)` item that Task 10 added. That is the `#if DEBUG ... #endif` block that follows `menu.addItem(reveal)` in `rebuild()`, and the `#if DEBUG ... annotateLastCapture() ... #endif` block that follows `revealLastCapture()`. Delete only those two blocks. Then run:
```bash
grep -rn "Annotate Last Capture" TidyShot; grep -rn "openEditor(recordID: " TidyShot | grep -v '///'; grep -rn "showEditor" TidyShot
```
Expected: nothing for the first and third. The second lists only AppCoordinator.swift (the definition and `openEditorAfterMenuTracking`) and RecentCapturesMenu.swift. The doc comments this task adds in QuickAccessController.swift, RecentCaptureRow.swift and EditorInput.swift also mention `openEditor(recordID:)` and stay.

- [ ] **Step 9: Run the whole suite**

Run:
```bash
xcodegen generate && xcodebuild test -project TidyShot.xcodeproj -scheme TidyShot -destination 'platform=macOS' -derivedDataPath .build 2>&1 | grep -E "Test run with|error:|TEST"
```
Expected: no `error:` lines, and `Test run with 399 tests in 51 suites passed`. OverlayGeometryTests are unchanged.

- [ ] **Step 10: Check by hand**

Run:
```bash
xcodebuild -project TidyShot.xcodeproj -scheme TidyShot -configuration Debug -derivedDataPath .build build -quiet && open .build/Build/Products/Debug/TidyShot.app
```
Make a different app frontmost before each Annotate. Expected:
- The overlay's right column shows Annotate, Close and Delete from top to bottom, nothing clipped, with the tooltip `Annotate`.
- Annotate on the overlay, in Save, Upload and Upload-only modes: the editor opens at once, key and frontmost, and the overlay closes.
- Annotate during an upload: the button stays enabled, the editor opens with the subtitle `Uploading…`, and the upload finishes.
- An upload-only capture that has finished uploading, its pending file gone: Annotate on its overlay still opens at once.
- Annotate on a Recent Captures row: the menu closes first, then the editor opens from the file. On an uploaded upload-only row whose overlay has closed, `Opening the capture…` is posted (with notifications on) and the editor opens from the download.
- With Show overlay off, Annotate on the newest row opens the editor.
- Take capture A with Show overlay on, then capture B. Open the editor on A from its Recent Captures row: it shows A's pixels, read from A's file (or downloaded), not B's.
- Open the overlay of a capture, then delete that capture's row from Recent Captures: the overlay closes, so its Annotate is gone.
- Rows show four buttons: Annotate, Copy URL, Copy Image, Delete…. VoiceOver reads "Annotate".
- Annotate on a row for a capture whose editor is open brings that editor forward and opens no second window.
- During a slow download, a second Annotate on the same row opens one editor only.
- The status menu of a Debug build has no `Annotate Last Capture (debug)`.

- [ ] **Step 11: Commit**

```bash
git add TidyShot/Editor/Persistence/EditorInput.swift TidyShotTests/EditorInputTests.swift \
  TidyShotTests/RecentCaptureFormattingTests.swift TidyShot/RecentCaptures/RecentCaptureFormatting.swift \
  TidyShot/RecentCaptures/RecentCaptureRow.swift TidyShot/RecentCaptures/RecentCaptureMenuItemView.swift \
  TidyShot/RecentCaptures/RecentCapturesMenu.swift TidyShot/Overlay/QuickAccessController.swift \
  TidyShot/Overlay/QuickAccessModel.swift TidyShot/Overlay/QuickAccessView.swift \
  TidyShot/App/AppCoordinator.swift TidyShot/App/StatusMenuController.swift
git commit -m "feat: Annotate on the overlay and on Recent Captures"
```

### Task 17: Phase 4a manual checklist, README and close-out

**Files:**
- Create: `docs/testing/phase-4a-manual-checklist.md`
- Modify: `README.md` (the Recent Captures paragraph, lines 75-79; a new `## Annotate` section after line 89, before `## Documents` at line 91; one line after line 98)
- Modify, only when Step 3 or Step 4 finds a divergence: `docs/superpowers/plans/2026-10-20-phase-4a-annotation-editor.md` (the test totals table) and `docs/superpowers/specs/2026-10-19-tidyshot-screenshot-design.md` (section 2.6, lines 102-428)
- Test: none (documentation only)

**Interfaces:**
- Consumes (behaviour and strings the checklist and README describe):
  - Task 1: the two-tone stroke, `CrosshairStyle.lineWhite`, `haloWhite`, `static let lineAlpha: CGFloat = 1`, `static let haloAlpha: CGFloat = 0.7`, used by `SelectionView.stroke(_:)` and the loupe cross.
  - Task 2: `EditorTool` letters V, D, X, B, R, A in `EditorTool.toolbarOrder` (Select, Redact, Pixelate, Blur, Rectangle, Arrow); `EditorPalette.swatches` (10), `EditorPalette.lineWidthsPoints = [2, 3, 4, 6, 8, 12]`; `RedactionDefaults.blurRangePoints = 4...24`, `RedactionDefaults.blockRangePoints = 6...32`; `EditorDefaults.standard` (red, black, 4, 8, 10).
  - Task 4: the `EditorShortcut` table (⌘S, ⇧⌘S, ⌘C, ⇧⌘C, ⌘U, ⌥⌘U, ⌘Z, ⇧⌘Z, ⌘W, ⌘0, ⌘1, ⌘=, ⌘-, ⌘A; no ⌘X row).
  - Task 8: `RedactionExportTests`, the automated twin of the 400% inspection.
  - Task 10: `EditorWindowController.askToSaveBeforeClosing() async -> Bool` (the close sheet), `AppDelegate.applicationShouldTerminate(_:)` returning `.terminateLater` while an editor is dirty, `present()`, and the temporary `Annotate Last Capture (debug)` item that Task 16 removes.
  - Task 11: the toolbar (tools group, `.color`, `.toolOptions`, `.zoom` with Fit, 50 %, 100 %, 200 %, 400 %, `.copyImage`, `.save` with Save Copy…, `.upload` with Upload and Upload as New) and the five persisted editor defaults.
  - Task 12: `EditorNaming.copyBaseName(for:)` (`<stem> edited`), `EditorClipboard.shouldReplace(owner:recordID:currentChangeCount:)`.
  - Task 13: `EditorAvailability.actions(record:saveFolder:isDeleting:)` and `status(...)` (the subtitles), `EditorSaveTarget.plan(for:saveFolder:)`, `pushEditorState(for:)` from delete, prune and save-folder changes.
  - Task 14: fixed-key `UploadJob` with `cacheControl: "no-cache"`, `CaptureRecord.priorUpload`, `CaptureRecord.linkURL`.
  - Task 15: `EditorUploadPlan.plan(record:currentLocation:others:asNew:)` and its three notices, `retryPolicy(...)`, `applyingFailure(to:message:)` and its notification, and the once-per-session `Replaced…` notification.
  - Task 16: the overlay's Annotate button, `RecentCaptureActions.annotate: (UUID) -> Void` (spec 2.6 "Annotate from Recent Captures"), `EditorInput.source(for:retainedID:saveFolder:) -> EditorInput.Source`.
  - Existing code, unchanged: `AfterCaptureAction.title` strings (TidyShot/Settings/AppSettings.swift:15-21); "Show Quick Access overlay after capture" (TidyShot/Settings/OverlaySettingsView.swift:8) and "Keep history for … days" (OverlaySettingsView.swift:21); `FileNamer.uniqueURL` appending ` 2`, ` 3` (TidyShot/Output/FileNamer.swift:49-57); `imageData(of:)` falling back to a signed GET (TidyShot/App/AppCoordinator.swift:489-508); `CopyImageError.unreadableFile` text "The local file could not be read." (AppCoordinator.swift:891); ISO 8601 `timestamp` values in `history.json` (TidyShot/History/HistoryStore.swift:141-157).
- Produces: documentation only. No later 4a task depends on it.

- [ ] **Step 1: Write the manual checklist**

`docs/testing/phase-4a-manual-checklist.md`:
````markdown
# Phase 4a manual test checklist

Run after any change to the crosshair, the editor, the Annotate buttons, or the save, copy, upload
or delete paths. Automated tests cover the editor model and undo, the geometry, the tile cache,
the decision tables for Save, Upload, the clipboard and the shortcuts, and the redaction export end
to end (`RedactionExportTests`); everything here needs real windows, a real bucket and eyes.

Setup: fresh build, Screen Recording granted, save folder set to Desktop, a working destination
saved in Settings > Upload (served through CloudFront for the Caches section), "Show notification"
on in Settings > General, "Show Quick Access overlay after capture" on in Settings > Overlay, and
Network Link Conditioner installed. History holds at least:
- a capture saved without upload ("Save and copy image");
- a capture uploaded with "Upload and copy URL";
- an upload-only capture that finished uploading ("Upload only, keep no local file");
- an upload-only capture whose upload failed (Wi-Fi off while capturing), with `pending/<UUID>.png`;
- a capture uploaded with the Phase 2 build (before Phase 3), its file still in the save folder.

`pending/` and `history.json` are in
`~/Library/Containers/io.tky.tidyshot/Data/Library/Application Support/TidyShot/`. Redact only
made-up secrets (for example `echo SECRET-TOKEN-0123456789` in Terminal). Where an item checks a
link with `curl`, use a link no browser has opened unless the item says otherwise: CloudFront
keeps what it has served (see Caches).

## Crosshair and loupe
- [ ] `⌃⇧4` over a white window (a new TextEdit document): the crosshair and the loupe's cross are black with a thin white halo. Over a dark window (Terminal) both are white with a black halo. Moving between the windows switches both; the loupe's ring stays white.
- [ ] For the first moment, before the snapshot arrives, the crosshair is white with a black halo and no loupe is drawn.
- [ ] Drag a rectangle that ends over the white window: its border is black with a white halo. One that ends over the dark window: white with a black halo.
- [ ] Over a photo or a mid-grey area the crosshair stays readable. Escape cancels.

## Annotate from the overlay
- [ ] The overlay's right column shows Annotate (a pencil in a circle, tooltip "Annotate") above Close and Delete. The overlay is the same size as before.
- [ ] "Save and copy image": capture, then Annotate. The overlay closes and the editor opens key and in front, at fit zoom, titled with the file name. It also comes to the front when Slack was frontmost.
- [ ] "Upload and copy URL", a large capture with Network Link Conditioner on a slow profile: Annotate while the overlay shows Uploading… opens the editor at once with the subtitle `Uploading…`. Save and Upload stay greyed until the upload finishes, then turn on.
- [ ] "Upload only, keep no local file": Annotate while uploading opens at once. Annotate after "URL copied" (the pending file is already gone) also opens at once, with no download.
- [ ] Annotate a capture whose editor is already open (from its Recent Captures row): that window comes forward and no second window opens.
- [ ] Editors on two captures: the second opens 22 points down and to the right of the first, on screen.

## Annotate from Recent Captures
Each row has four buttons: Annotate (the pencil, tooltip "Annotate"), Copy URL, Copy Image and
Delete. Annotate closes the menu first, then the editor opens key and in front, also when Slack was
frontmost.
- [ ] Saved capture, never uploaded: the editor opens from the file in the save folder.
- [ ] Capture uploaded with "Upload and copy URL": opens from the file in the save folder.
- [ ] Upload-only capture whose upload failed: opens from `pending/<UUID>.png`.
- [ ] Upload-only capture that finished uploading: after a moment (it downloads the object) the editor opens, titled `Capture <time>`. With Wi-Fi off: no window, and a `Could not open the capture` notification gives the reason.
- [ ] Capture from before Phase 3: opens from its file. Move the file out of the save folder and press Annotate: no window, and `Could not open the capture` with "The local file could not be read." Put the file back.
- [ ] Capture uploaded with "Upload and copy URL" whose file was renamed in Finder: the editor still opens, from the downloaded object. Rename the file back.
- [ ] Settings > Overlay, turn "Show Quick Access overlay after capture" off. Capture once in each after-capture mode: no overlay appears, and Annotate on the new row opens the editor each time (for "Upload only, keep no local file", also while it is still uploading). Turn the overlay back on.
- [ ] Stale retained image: with the overlay on, take capture A (leave its overlay open), then take capture B. Open the editor on A from its Recent Captures row: it shows A's pixels, not B's. Then delete a row whose overlay is still open: that overlay closes, and Annotate on a different row still opens the right capture.

## Tools
- [ ] The toolbar shows, in order: the tools (Select, Redact, Pixelate, Blur, Rectangle, Arrow), the colour button, the options button, the zoom pop-up, Copy, Save (its menu offers Save Copy…) and a prominent Upload (its menu offers Upload and Upload as New). Each tool's tooltip names its letter.
- [ ] With the canvas focused, `V` `D` `X` `B` `R` `A` pick Select, Redact, Pixelate, Blur, Rectangle and Arrow, and the toolbar follows. Narrow the window: the tools collapse into a menu that still works.
- [ ] Redact: a drag makes a black box. Shift makes a square and Option draws from the centre; pressing or releasing either mid-drag changes the box without moving the mouse. Escape mid-drag drops the box. A click without a drag adds nothing. The new box is selected.
- [ ] Pixelate: a drag makes a mosaic of equal squares, 10 points by default. A second region over the same text, offset by a few pixels, has squares that line up with the first. The options slider (6 to 32 pt) changes a selected mosaic live.
- [ ] Blur: a drag blurs the area. The options slider (4 to 24 pt) changes a selected blur live.
- [ ] Rectangle: red and 4 pt by default, the stroke inside the dragged box. Keys `1` to `6` set 2, 3, 4, 6, 8 and 12 pt on the selection and on the tool.
- [ ] Arrow: the tail is where the drag starts and the head where it ends; Shift snaps it to 45 degrees.
- [ ] Select: a click on an arrow drawn over a blur picks the arrow; a click on the blur away from the arrow picks the blur (dashed outline). A drag moves the selection and Shift locks the move to one axis. Boxes have 8 handles and arrows 2; dragging a handle resizes. A click on empty space deselects. Delete removes the selection. `←` moves it one image pixel, `⇧←` ten. Escape deselects and never closes the window.
- [ ] `⌘.` behaves like Escape: during a drag it abandons the drag, and otherwise it deselects. It never closes the window.
- [ ] The colour button shows the current colour as a filled circle. Its popover has ten swatches (black, red, orange, yellow, green, teal, blue, purple, pink, white) and a colour picker without opacity. A swatch recolours the selection and the active tool. With Redact active it sets the redact colour, and the shape colour stays.
- [ ] Choose blue and 8 pt, close the editor and open another: Rectangle starts blue at 8 pt. Quit and relaunch: still blue at 8 pt. Set red and 4 pt again.

## Redaction in the saved file
Do these on the 2x display and again on a 1x display (an external non-Retina display, or a
resolution without HiDPI); skip the 1x run if neither is available and say so.
- [ ] "Save and copy image": capture a Terminal window with three lines of made-up secret. Annotate, Redact the first line, Pixelate the second, Blur the third, ⌘S. Open the saved PNG in Preview and zoom in until single pixels show (about 400%): the redaction is solid black to its edges with no trace of text along its border, the mosaic is uniform squares, and the blur is unreadable.
- [ ] `sips -g pixelWidth -g pixelHeight -g dpiWidth <file>`: the same pixel size as before the edit, and `dpiWidth` 144 on the 2x display, 72 on the 1x display.
- [ ] Redact one word. Draw a Blur that covers half of the redaction and a second Blur that only touches its edge. ⌘S, and at 400% in the saved PNG both blurs show grey and black from the redaction but no letter shapes from under it.
- [ ] Move the redaction: the blur over it follows at once.
- [ ] A window capture (`⌃⇧2`) with a redaction keeps its transparent rounded corners in the saved PNG.

## Undo
- [ ] Draw a redaction, a mosaic and a rectangle: ⌘Z three times removes them newest first, and ⇧⌘Z three times brings them back.
- [ ] Select the rectangle, press `→` ten times and `⇧↓` three times, then ⌘Z once: it is back where it started. ⇧⌘Z moves it again.
- [ ] Nudge one shape, click another and nudge that: the first ⌘Z undoes only the second shape's nudges, the next ⌘Z the first shape's.
- [ ] Drag the radius slider of a selected blur for a few seconds: one ⌘Z restores the radius.
- [ ] Zoom in, change the tool, and with nothing selected change the colour, then ⌘Z: only the last edit is undone; zoom, tool and colour stay.
- [ ] After an edit the close button shows the unsaved dot; undoing back to the opened state clears it.

## Zoom on a 5K capture
- [ ] `⌃⇧3` on the 2x display (5120 by 2820 pixels on a 2560 by 1410 point screen), then Annotate: the window fits on the screen with the whole picture showing.
- [ ] ⌘1 shows the picture at its natural point size and ⌘0 fits it again. ⌘= and ⌘- zoom around the window centre. The zoom pop-up's Fit, 50 %, 100 %, 200 % and 400 % each work.
- [ ] Pinch and ⌘-scroll zoom around the pointer, and scrolling pans. Zoom stops at a limit each way and the picture never vanishes.
- [ ] At 400% pixels are hard-edged squares, redactions and mosaics are crisp, and panning shows no seams, stripes or blank tiles.
- [ ] Dragging out a blur at 400% and at fit follows the mouse without stutter.

## Save
- [ ] Saved capture: Redact, ⌘S. The same file in the save folder now shows the redaction (Quick Look), no new file appears, the unsaved dot clears, and the row's thumbnail shows the redaction the next time the menu opens. Nothing is uploaded.
- [ ] Capture uploaded with "Upload and copy URL": ⌘S rewrites the file only. The subtitle reads `The uploaded copy still shows the original. Upload to replace it.` and the link still shows the original.
- [ ] Capture from before Phase 3: ⌘S rewrites its file, with the same subtitle.
- [ ] Upload-only capture that finished uploading: Save is greyed and ⌘S beeps; Save Copy and Upload are on.
- [ ] Upload-only capture whose upload failed: Redact, ⌘S rewrites `pending/<UUID>.png`. Wi-Fi on, Retry Failed Uploads: the link shows the redaction.
- [ ] Lock the saved file (Finder, Get Info, Locked), edit, ⌘S: a `Not saved` notification with the reason, the unsaved dot stays, and the edited image is on the clipboard. Unlock the file.

## Save Copy
- [ ] "Save and copy image": edit a saved capture, then ⇧⌘S (or Save Copy… in the Save button's menu). A new file `<name> edited.png` appears in the save folder with a new Recent Captures row and its overlay, and no shutter sound plays. The editor keeps the original's title, its unsaved dot clears, and the original file is unchanged. A second Save Copy makes `<name> edited 2.png`.
- [ ] With "Upload and copy URL" the copy also uploads and its URL lands on the clipboard. With "Upload only, keep no local file" it uploads and keeps no local file.
- [ ] With "Save and copy image", Save Copy from an upload-only capture that finished uploading writes a new file named by the file name template.

## Copy
- [ ] ⌘C, ⇧⌘C and the toolbar's Copy button each post `Image copied`. Notes and Preview (File > New from Clipboard) paste the edited image at point size, not double. The window stays open.
- [ ] With "Show notification" off, Copy posts nothing. Turn it back on.

## Clipboard
- [ ] "Save and copy image" with "Copy image to clipboard" on: capture a made-up secret, Annotate, Redact, ⌘S. Preview, File > New from Clipboard: the redacted image.
- [ ] The same with ⇧⌘S in place of ⌘S: the clipboard holds the redacted copy.
- [ ] Capture, copy some text in TextEdit, then Annotate, Redact, ⌘S: the clipboard still holds the text.
- [ ] "Upload and copy URL" with no destination (Forget Credentials in Settings > Upload): capture (the image goes to the clipboard), Annotate, Redact, ⌘S: the clipboard holds the redacted image. ⌘U posts `Upload not configured` and changes nothing. Enter the credentials again.
- [ ] "Upload and copy URL" with "Also copy image" on: capture, Annotate, Redact, ⌘U. When the upload finishes the clipboard holds the URL.

## Upload
- [ ] Capture uploaded with "Upload and copy URL": Redact, ⌘U. The subtitle reads `Uploading…` at once, before any progress, and Save and Upload are greyed until it finishes. Then the clipboard holds the same URL as before, the link shows the redaction, the file in the save folder shows it too, and the unsaved dot is clear.
- [ ] `curl -sI <url>` after that replace includes `cache-control: no-cache`; for a capture that was never replaced there is no `cache-control` line.
- [ ] Another uploaded capture whose link was never opened: edit, then Upload as New (⌥⌘U, or the Upload button's menu). A new URL on the clipboard shows the edit, `curl -I <old url>` gives 403 or 404, and the row's link button copies the new URL.
- [ ] Saved capture never uploaded: Upload as New is greyed and ⌥⌘U beeps. ⌘U uploads it for the first time and copies a new link.
- [ ] Interrupted replace keeps Upload as New: after the "Quit during a replace" item below, relaunch (the row shows "· Upload failed" and its link still copies). Annotate on that row: Upload as New stays enabled and ⌥⌘U uploads to a new key, copies the new link and deletes the old object (`curl -I <old url>` gives 403 or 404).
- [ ] Capture from before Phase 3: ⌘U shows the notice `The earlier upload stays in the bucket.` and makes a new link; `curl -I <old url>` still gives 200.
- [ ] Optional, with a second bucket: point Settings > Upload at it, then ⌘U on a capture uploaded to the first. The notice reads `The destination changed, so this uploads as a new link.`, the link is in the second bucket, and the old object is gone from the first. Point the settings back.
- [ ] Enter a wrong secret access key in Settings > Upload and press Save, then ⌘U on an uploaded capture. After the retries: a notification `Upload failed. The link still shows the earlier image.`, the row still copies the old URL, and the subtitle reads `The uploaded copy still shows the original. Upload to replace it.` Enter the right key, ⌘U: the same URL now shows the edit.
- [ ] The same wrong key, ⌘U on an upload-only capture that finished uploading. After the failure `pending/<UUID>.png` exists and holds the edit. Close the editor; Annotate on the row reopens it with the edit, and the subtitle says the uploaded copy still shows the original. Right key, ⌘U: the same URL shows the edit and `pending/<UUID>.png` is gone.
- [ ] Quit during a replace: Network Link Conditioner on a slow profile (a custom profile with a few hundred Kbps uplink), ⌘U on a large uploaded capture, and while the subtitle reads `Uploading…` choose Quit TidyShot. Relaunch: the row shows "· Upload failed", and clicking the row or its link button still copies the old URL. Network Link Conditioner off, Retry Failed Uploads: the URL is unchanged and shows the edit.
- [ ] Slow profile again, ⌘U, then Delete on the row while the replace runs: Delete cancels the upload and removes the object (`curl -I <url>` gives 403 or 404), and the editor's subtitle reads `This capture was deleted. Copy and Save Copy still work.`

## Caches
- [ ] Redact before sharing: capture a made-up secret with "Upload and copy URL", do not open or paste the URL, Annotate from the overlay, Redact, ⌘U. Then open the link in a browser: it shows the redaction.
- [ ] Replace after opening: capture, open the link in a browser (it shows the secret), Annotate from the row, Redact, ⌘U. Reloading the link may still show the original for a while, from the browser or CloudFront; `curl -sI <url>` shows `x-cache: Hit from cloudfront` and an `age` header while CloudFront serves its copy. This is the documented caveat, not a failure.
- [ ] Upload as New on that capture: the new link shows the redaction. The old link may still be served from CloudFront's copy until it expires, although the object is gone from the bucket.
- [ ] Only if the bucket has versioning: after a replace, `aws s3api list-object-versions --bucket <bucket> --prefix <key>` lists two versions, the original being the older one.
- [ ] The first successful replace after launch posts `Replaced. Copies opened before now may stay cached for a while.` A second replace in the same launch does not, and neither does Upload as New or a first upload. Quit and relaunch: the next replace posts it again.

## Availability while uploading, deleting, or after a folder change
- [ ] While an editor upload runs (slow profile): ⌘S, ⌘U and ⌥⌘U beep and do nothing, and Save and Upload are greyed in the toolbar; ⌘C, ⇧⌘C and ⇧⌘S work. When the upload finishes they turn on again.
- [ ] With an editor open, press Delete on its row and leave the alert open: the editor's Save and Upload grey out at once, the subtitle reads `Deleting…`, and ⌘S beeps. Cancel: they turn on again and the subtitle returns to what it was.
- [ ] Delete again and confirm: the subtitle reads `This capture was deleted. Copy and Save Copy still work.`, Save and Upload stay greyed, ⌘C copies, and ⇧⌘S makes a new capture.
- [ ] Editor open on a capture in the save folder: Settings > General, Choose… another folder. Save greys out at once, the subtitle gives the reason, and ⌘S beeps. ⌘U still uploads the edit and the file in the old folder is not rewritten. Choose the original folder again: Save turns on.

## Closing and quitting
- [ ] ⌘W on an editor with no changes closes it at once.
- [ ] With changes, ⌘W (or the close button) shows a sheet: `Do you want to save the changes made to “<title>”?`, `Your changes will be lost if you don’t save them.`, and Save, Cancel and Don’t Save. Cancel keeps the window. Don’t Save (or ⌘D) closes it and leaves the file as it was. Save writes the file and closes.
- [ ] On an upload-only capture that finished uploading, the first button reads Save Copy…; it makes the copy and closes the window.
- [ ] Quit TidyShot from the menu with a changed editor: the sheet appears on it. Cancel: TidyShot keeps running and the editor stays open. Quit again, Don’t Save: TidyShot quits.
- [ ] Quit with only unchanged editors open: TidyShot quits at once.
- [ ] The green button takes the editor full screen and back.

## History pruning (do this last)
This drops every capture older than a day from history; files in the save folder and objects in
the bucket stay.
- [ ] Quit, set one record's `timestamp` in `history.json` to two days ago, relaunch, and open that capture from its row. Settings > Overlay, set Keep history to 1 day, then take a new capture: the editor's subtitle reads `This capture was deleted. Copy and Save Copy still work.`, Save and Upload are greyed, and ⇧⌘S still makes a new capture. Set the retention back.
````

- [ ] **Step 2: Update the README**

In `README.md`:

Replace lines 75-79:
```markdown
Hover Recent Captures in the menu bar menu for the newest 15 captures, each with a thumbnail, its
name and how long ago it was taken. Click a row to copy its URL (or the file when it was never
uploaded). The row's buttons copy the URL, copy the image (downloaded from the bucket with a
signed request when no local file is left), or delete the capture. Hover a thumbnail to see a
larger preview of the capture beside the menu.
```
with:
```markdown
Hover Recent Captures in the menu bar menu for the newest 15 captures, each with a thumbnail, its
name and how long ago it was taken. Click a row to copy its URL (or the file when it was never
uploaded). The row's buttons open the capture in the editor (see Annotate), copy the URL, copy the
image (downloaded from the bucket with a signed request when no local file is left), or delete the
capture. Hover a thumbnail to see a larger preview of the capture beside the menu.
```

After line 89 (`Thumbnails live in …`), before `## Documents` (line 91), insert a blank line and:
```markdown
## Annotate

The pencil button on the Quick Access overlay opens the capture in the editor. Each Recent Captures
row has the same button, which also works with the overlay turned off; a capture with no local
file left is downloaded from the bucket first.

Tools and their keys: Select `V`, Redact `D`, Pixelate `X`, Blur `B`, Rectangle `R`, Arrow `A`.
Shift squares a box and snaps an arrow to 45 degrees; Option draws a box from its centre. Keys `1`
to `6` set the line width to 2, 3, 4, 6, 8 or 12 points. With Select, the arrow keys move the
selection by one pixel (ten with Shift), Delete removes it and Escape deselects. The colour and
options buttons in the toolbar set the colour, line width, blur radius and pixel size for the tool
and the selection, and the editor remembers them.

| Action | Shortcut |
|---|---|
| Save (over the file) | ⌘S |
| Save Copy | ⇧⌘S |
| Copy image | ⌘C or ⇧⌘C |
| Upload (same link) | ⌘U |
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
of an upload-only capture whose upload has not succeeded. A capture with no local file left, or
whose file is outside the current save folder, has no Save; use Save Copy or Upload. Save never
uploads; on an uploaded capture the window then says the uploaded copy still shows the original.
Save Copy makes a new capture named after the original plus " edited", which follows the
after-capture setting, so it uploads in the upload modes. Copy puts the edited image on the
clipboard.

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

When the clipboard still holds the image TidyShot put there for a capture, Save, Save Copy and
Upload replace it with the edited image; Upload then puts the link there as usual. Anything you
copied since is left alone. A clipboard manager may still keep the original in its history; clear
it there.

Closing an editor with unsaved changes, or quitting TidyShot, asks whether to save them.
```

After line 98 (`- Phase 3.1 manual test checklist: …`), add:
```markdown
- Phase 4a manual test checklist: `docs/testing/phase-4a-manual-checklist.md`
```

- [ ] **Step 3: Run the full suite and check the totals table**

Run:
```bash
xcodegen generate && xcodebuild test -project TidyShot.xcodeproj -scheme TidyShot -destination 'platform=macOS' -derivedDataPath .build 2>&1 | grep -E "Test run with|error:|TEST"
```
Expected: no `error:` lines, `** TEST SUCCEEDED **`, and `Test run with 399 tests in 51 suites passed`.

That count must equal the Task 17 row of the "Test totals" table in the plan's header section (`task-00-header.md` in the plan files, and in `docs/superpowers/plans/2026-10-20-phase-4a-annotation-editor.md`, which is those files concatenated). Reconcile the table against the repo first:
```bash
grep -rhE '^(@MainActor )?struct [A-Za-z0-9]+Tests\b' TidyShotTests | wc -l; grep -rhE '^\s*@Test' TidyShotTests | wc -l
grep -c '{{' docs/superpowers/plans/2026-10-20-phase-4a-annotation-editor.md
```
Expected: the first count is the suites in the Task 17 row (one `struct …Tests` per suite; helper files such as FakeTileRenderer.swift declare none), and the second is its tests (Swift Testing counts a parameterized `@Test` once, as SigV4TestSuiteTests shows in the 191 baseline); the last count is `0`, so no `399 tests in 51 suites` placeholder is left. If the run differs from the Task 17 row, a review fix added or removed tests. Find which task with:
```bash
git log --oneline --stat f4541da..HEAD -- TidyShotTests
```
Correct that task's row and every row after it (a review fix that changes test counts must amend the table), and record the reason in one line under the table. Change nothing else in the plan.

- [ ] **Step 4: Check spec 2.6 against the build**

Run:
```bash
while IFS= read -r s; do grep -rqF -- "$s" TidyShot || echo "MISSING: $s"; done <<'EOF'
Not saved
Not uploaded
Could not open the capture
Image copied
Upload failed. The link still shows the earlier image.
Replaced. Copies opened before now may stay cached for a while.
Uploading…
Deleting…
The uploaded copy still shows the original. Upload to replace it.
This capture was deleted. Copy and Save Copy still work.
The destination changed, so this uploads as a new link.
Another capture shares this link, so this uploads as a new link.
The earlier upload stays in the bucket.
Do you want to save the changes made to “
Your changes will be lost if you don’t save them.
Don’t Save
Save Copy…
Upload as New
EOF
grep -rln "pencil.tip.crop.circle" TidyShot | sort
grep -rn "Annotate Last Capture" TidyShot; grep -rn "CIPixellate\|allowsMagnification" TidyShot; grep -ni "limitation" README.md docs/testing/phase-4a-manual-checklist.md
```
Expected: no `MISSING:` lines, then exactly:
```
TidyShot/Overlay/QuickAccessView.swift
TidyShot/RecentCaptures/RecentCaptureRow.swift
```
and nothing from the last three greps.

For a `MISSING:` line, find the text the code shows instead. If a review fix changed it on purpose (it is recorded in `.superpowers/sdd/progress.md`), write the new text into spec 2.6, into the Global Constraints string list of this plan, and into the checklist and README, all in this task's commit. Otherwise the code is wrong: stop and report it, and do not amend the spec to match. The `AppCoordinator.swift:<line>` citations in 2.6 describe the code before Phase 4a; leave them as they are.

- [ ] **Step 5: Run the end-to-end check**

Run:
```bash
xcodebuild -project TidyShot.xcodeproj -scheme TidyShot -configuration Debug -derivedDataPath .build build -quiet && open .build/Build/Products/Debug/TidyShot.app
```
In "Upload only, keep no local file": run `echo SECRET-TOKEN-0123456789` in Terminal, `⌃⇧2` on the Terminal window, press Annotate on the overlay, `D`, drag over the token, ⌘U. The subtitle reads `Uploading…` at once; when it clears, paste the link into Slack: the token is a black box, and the link is the one the overlay showed. Close the editor, open Recent Captures, press Annotate on that row: the editor opens from the downloaded object. Then work through `docs/testing/phase-4a-manual-checklist.md`.

- [ ] **Step 6: Commit**

```bash
git add docs/testing/phase-4a-manual-checklist.md README.md docs/superpowers/plans/2026-10-20-phase-4a-annotation-editor.md docs/superpowers/specs/2026-10-19-tidyshot-screenshot-design.md
git commit -m "docs: Phase 4a checklist and README"
```
The plan and the spec are in the list so that Step 3 and Step 4 amendments land in this commit; when they are unchanged, `git add` leaves them out.

- [ ] **Step 7: Stop here**

Phase 4a is done when the last test run reads `Test run with 399 tests in 51 suites passed` and the checklist passes. Do not push and do not open a PR: the controller pushes and opens PR 1 after the whole-branch review. Report the final test line, which checklist items were run (and whether the 1x and second-bucket items were skipped), and any amendment made in Step 3 or Step 4.

---
