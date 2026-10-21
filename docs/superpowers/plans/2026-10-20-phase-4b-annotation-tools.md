# TidyShot Phase 4b: Annotation Tools, Text, Crop and Keyboard Polish, Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Complete the Phase 4 editor release: add the Ellipse, Line, Pencil, Highlighter, Text and Crop tools, duplicate (⌘D, ⌥-drag), object copy and paste, Space-drag pan and canvas accessibility, on top of the Phase 4a editor merged in PR 7.

**Architecture:** Unchanged from Phase 4a (spec 2.6): each new tool adds an `Annotation` case and an `EditorTool` case, a `CanvasTool` in `Tools/` built by `makeTool(for:)`, drawing in the shared nonisolated `AnnotationDrawing` (so preview equals export), hit testing in `HitTester`, and a toolbar entry. Text edits in an `NSTextView` subview of `CanvasView` with its own `UndoManager` and commits as one editor commit; committed text draws with CoreText on the bare `CGContext`. Crop is `AnnotationDocument.crop`, applied last by `EditorFlattener`, so Save, Upload, the thumbnail and the record's pixel size all follow it through the existing coordinator paths.

**Tech Stack:** Swift 6 language mode with default `MainActor` isolation and `NonisolatedNonsendingByDefault`, AppKit (`NSWindow`, `NSToolbar` with `NSToolbarItemGroup` and `NSMenuToolbarItem`, `NSPopover`, layer-backed `NSView`, `UndoManager`, `NSUserInterfaceValidations`), SwiftUI (`NSHostingController` in popovers), Core Image (Metal-backed `CIContext`, `CIImage.applyingGaussianBlur`, `samplingNearest`), Core Graphics (bitmap `CGContext`), ImageIO, Swift Testing, XcodeGen 2.46.

Spec: `docs/superpowers/specs/2026-10-19-tidyshot-screenshot-design.md`, section 2.6 (all of it, including "Phase 4b" and "Feedback after the 4a build") and section 6 (Phase 4). Section 2.6 is the authority for behaviour, names and exact strings; when this plan and 2.6 disagree, stop and ask.

Builds on Phase 4a (`docs/superpowers/plans/2026-10-20-phase-4a-annotation-editor.md`, merged as PR 7, 9193586), including its feedback round (spec 2.6, "Feedback after the 4a build": Copy, Save and Upload buttons, Save As… instead of Save Copy, Upload closes the window). Work happens on the branch `phase-4b-annotation`, created from `main` at 9193586. Confirm:

```bash
git switch phase-4b-annotation
git merge-base --is-ancestor 9193586 HEAD && echo BASE_PRESENT
```
Expected: `Already on 'phase-4b-annotation'` (or `Switched to branch 'phase-4b-annotation'`) then `BASE_PRESENT`.

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
  - Notification titles: `Not saved`, `Not uploaded`, `Could not open the capture`, `Image copied`; bodies `Upload failed. The link still shows the earlier image.`, `Replaced. Copies opened before now may stay cached for a while.` (posted once per app session, on the first successful same-key replace).
  - Window subtitles: `Uploading…`, `Deleting…`, `The uploaded copy still shows the original. Upload to replace it.`, `This capture was deleted. Copy and Save As still work.` (was `… Copy and Save Copy still work.` until feedback round 1)
  - Upload notices: `The destination changed, so this uploads as a new link.`, `Another capture shares this link, so this uploads as a new link.`, `The earlier upload stays in the bucket.`
  - Close sheet: message `Do you want to save the changes made to “<title>”?`, informative text `Your changes will be lost if you don’t save them.`, buttons Save (or `Save As…` when Save is unavailable), Cancel, Don’t Save. Feedback round 1 replaced Save Copy with Save As… (⇧⌘S, `saveDocumentAs:`), and the toolbar tool tips are `Copy the image (⌘C)`, `Save (⌘S)` and `Upload and copy the link (⌘U)`; notification title `Saved` for Save As….
- Shortcuts: the 4a `EditorShortcut` table in spec 2.6 (⌘S, ⇧⌘S, ⌘C, ⇧⌘C, ⌘U, ⌥⌘U, ⌘Z, ⇧⌘Z, ⌘W, ⌘0, ⌘1, ⌘=, ⌘-, ⌘A); tool letters V, D, X, B, R, A; digits 1 to 6 for line widths 2, 3, 4, 6, 8, 12 pt. ⌘X has no row.
- The editor activates the app (`activate(ignoringOtherApps:)`, then `makeKeyAndOrderFront`, then `orderFrontRegardless` if still inactive). Menu and overlay actions that open it run after menu tracking ends (`afterMenusClose`).
- Tests use Swift Testing, run with:
  ```bash
  xcodegen generate && xcodebuild test -project TidyShot.xcodeproj -scheme TidyShot -destination 'platform=macOS' -derivedDataPath .build 2>&1 | grep -E "Test run with|error:|TEST"
  ```
  Baseline `Test run with 414 tests in 52 suites passed`; the totals after each task are in the table below.
- Commit after every task with a conventional commit message and no attribution lines. Never include a Claude Code session URL in a commit or PR. This plan never pushes or opens a PR: the last task stops after its commit, and the controller pushes and opens the PR after the whole-branch review.


- Phase 4b specifics:
  - Tool letters E (Ellipse), L (Line), P (Pencil), H (Highlighter), T (Text), C (Crop); the toolbar order comes from `EditorTool.toolbarOrder`. Every new tool widens the toolbar by one 36 pt segment; `minimumToolbarContentWidth()` already counts `toolbarOrder`, so `ToolbarMetrics` stays unless a hand check shows an overflow. Task 1's `toolbarWithEveryToolFitsASmallDisplay` pins the tool count and the toolbar width, and each later task that adds a tool updates those two pinned lines in its own commit (10 and 944 pt after Task 2, 11 and 980 after Task 3, 12 and 1016 after Task 4); no other task adds a toolbar-width test.
  - New shortcut rows: ⌘V `paste:` and ⌘D `duplicate:`, both passing through while text is being edited; ⌘X still has no row. ⌘C on a selected object copies the object; with nothing selected it copies the flattened image as in 4a.
  - Highlighter: multiply blend, yellow at 0.45 alpha by default. Pencil: decimated points with Catmull-Rom smoothing.
  - Text never registers undo into the editor's `UndoManager` (`groupsByEvent = false`) while typing; the commit is one editor commit.
  - Crop is undoable, applied last at export, and changes the saved and uploaded pixel size; Return applies, Escape cancels.

## Test totals

| After | New tests | New suites | Total |
|---|---|---|---|
| Baseline | | | 414 tests in 52 suites |
| Task 1 | 6 | 0 | 420 tests in 52 suites |
| Task 2 | 10 | 1 | 430 tests in 53 suites |
| Task 3 | 7 | 1 | 437 tests in 54 suites |
| Task 4 | 9 | 1 | 446 tests in 55 suites |
| Task 5 | 12 | 2 | 458 tests in 57 suites |
| Task 6 | 0 | 0 | 458 tests in 57 suites |

The totals come from each task's declared tests. Task 6 checks them against a real run and corrects any row that differs.

Task 6 correction: the rows above are the plan's declared counts and stay as written. Two review fixes added tests beyond them. ee9c689 (the highlighter preview follows tile changes, a fix to Task 2's highlighter committed after Task 3) added `TileRepaintTests`, 5 tests in 1 suite. 5bacbe9 (crop undo keeps the draft in step, a fix to Task 4) added 1 test. The real count by commit was 420 tests in 52 suites (Task 1), 430 in 53 (Task 2), 437 in 54 (Task 3), 442 in 55 (ee9c689), 451 in 56 (Task 4), 452 in 56 (5bacbe9) and 464 in 58 (Task 5, 12 tests in 2 suites as declared). Task 6 adds none, and the real run reads `Test run with 464 tests in 58 suites passed`.

---

### Task 1: Ellipse and Line tools

**Files:**
- Modify: `TidyShot/Editor/Model/Annotation.swift`
- Modify: `TidyShot/Editor/Model/EditorTool.swift`
- Modify: `TidyShot/Editor/Geometry/HitTester.swift`
- Modify: `TidyShot/Editor/Geometry/ArrowGeometry.swift` (`AnnotationGeometry.bounds`, lines 53-69; not in the synthesized entry's list, but its switch has no default)
- Modify: `TidyShot/Editor/Geometry/EditorWindowGeometry.swift` (a doc comment on `ToolbarMetrics.segment`, line 50)
- Modify: `TidyShot/Editor/Rendering/AnnotationDrawing.swift`
- Modify: `TidyShot/Editor/Session/EditorModel.swift` (`makeAnnotation`, lines 132-157, and `color(of:)`, lines 244-251; also missing from the entry)
- Modify: `TidyShot/Editor/Tools/ToolFactory.swift`
- Modify: `TidyShot/Editor/Tools/RectDragTool.swift` and `TidyShot/Editor/Tools/TwoPointTool.swift` (doc comments only)
- Modify: `TidyShot/Editor/Window/EditorToolbar.swift` (doc comments only)
- Test: `TidyShotTests/EditorToolTests.swift`, `TidyShotTests/HitTesterTests.swift`, `TidyShotTests/EditorFlattenerTests.swift`, `TidyShotTests/CanvasToolTests.swift`, `TidyShotTests/EditorModelTests.swift`, `TidyShotTests/EditorWindowGeometryTests.swift` (all modified; no new file, so no new test struct)

**Interfaces:**
- Consumes (all on `main`, 9193586):
  - `ShapeBox { id; rect; color: RGBA; lineWidth }` and `Segment { id; from; to; color; lineWidth }` (`Annotation.swift:8-22`). `Segment`'s doc already says "an arrow in 4a, a line in 4b".
  - `DragGeometry.rect(from:to:square:fromCentre:)`, `segmentEnd(from:to:snap45:)`, `isLargeEnough(_:zoom:)`, `isLongEnough(from:to:zoom:)` (`DragGeometry.swift`). `RectDragTool` and `TwoPointTool` already pass Shift and Option to them, so the Shift circle and the 45 degree snap need no tool code.
  - `CanvasEditing.makeAnnotation(_:from:to:)` (`CanvasTool.swift:31`) and `commitNewShape(_:)` (`ToolFactory.swift:18`), which names the commit `Add <title>`.
  - `HitTester.distance(from:toSegment:_:)`, `boxHandles`, `resizedRect`; `AnnotationDrawing.draw(_:in:scale:)`; `AnnotationGeometry.bounds(of:scale:)`; `EditorWindowGeometry.toolbarWidth(...)`.
- Produces:
  - `Annotation.ellipse(ShapeBox)` and `Annotation.line(Segment)`; `title` is `Ellipse` and `Line`. Both are drawings (`isEffect == false`, `effectRect == nil`).
  - `EditorTool.ellipse` (letter E, symbol `circle`, title `Ellipse`) and `EditorTool.line` (letter L, symbol `line.diagonal`, title `Line`). `toolbarOrder` is `[.select, .redact, .pixelate, .blur, .rectangle, .arrow, .ellipse, .line]`; later 4b tasks append after `.line`.
  - `makeTool(for:)`: `.ellipse` gives `RectDragTool(tool:)` and `.line` gives `TwoPointTool(tool:)`.
  - `HitTester`: ellipse handles are the bounding box's eight (as for a rectangle); an ellipse body is the ring from `tolerance` outside the outline to `lineWidth + tolerance` inside it; a line has two endpoint handles and a body within `lineWidth / 2 + tolerance` of the segment.
  - `AnnotationDrawing`: private `strokeEllipse(_:in:)` (stroked inset by half the line width, so the stroke sits inside the rect) and `strokeLine(_:in:)` (a round-capped segment).
  - `EditorWindowGeometry.ToolbarMetrics.segment` stays 36 pt unless the hand check in Step 8 shows an overflow.

Behaviour (spec 2.6, Tools; Ellipse and Line follow Rectangle and Arrow):
- Ellipse (E): `RectDragTool(.ellipse)`. Shift makes a circle, Option draws from the centre. It takes the stroke colour and the line width in points times the capture scale, like Rectangle.
- Line (L): `TwoPointTool(.line)`. The start is `from` and the pointer is `to`; Shift snaps to 45 degrees. No head: a plain stroke with round caps.
- A new shape is selected after creation. Select moves it, resizes it by its handles, and Delete, nudges, colour and line width work as for Rectangle and Arrow, because they go through `Annotation.moved`, `withColor` and `withLineWidth`.
- An ellipse no wider or taller than its line width is filled, as a rectangle is, so a tiny one still shows.

- [ ] **Step 1: Write the failing tests**

`TidyShotTests/EditorToolTests.swift`. In `lettersAreUnique` (line 9), after the `phase4a` letters assertion (line 13), add:
```swift
        #expect([EditorTool.ellipse, .line].map(\.letter) == ["E", "L"])
```
In `everyToolHasSymbolAndTooltipWithLetter` (line 32), after the `Redact (D)` assertion (line 38), add (the loop above it already checks that both symbols exist):
```swift
        #expect(EditorTool.ellipse.tooltip == "Ellipse (E)")
        #expect(EditorTool.line.tooltip == "Line (L)")
```
In `toolbarOrderCoversEveryToolOnce` (line 46), after the `phase4a` order assertion (line 53), add:
```swift
        // Ellipse and Line follow the 4a tools. Later 4b tools go after them.
        #expect(Array(order.dropFirst(phase4a.count).prefix(2)) == [.ellipse, .line])
```
`effectToolsAreRedactPixelateBlur` (line 42) stays as it is and proves that the new tools are not effects.

`TidyShotTests/HitTesterTests.swift`. After the `arrow(_:_:lineWidth:id:)` helper (line 18), add:
```swift
    func ellipse(_ rect: CGRect, lineWidth: CGFloat = 4, id: UUID = UUID()) -> Annotation {
        .ellipse(ShapeBox(id: id, rect: rect, color: red, lineWidth: lineWidth))
    }

    func line(_ from: CGPoint, _ to: CGPoint, lineWidth: CGFloat = 4, id: UUID = UUID()) -> Annotation {
        .line(Segment(id: id, from: from, to: to, color: red, lineWidth: lineWidth))
    }
```
After `arrowEndpointHandlesMoveEnds` (ends at line 158, before the struct's closing brace), add:
```swift
    /// `box` is 200 by 100 with its centre at (200, 100), so the outline's radii are 100 and 50.
    /// With a 4 px stroke and a tolerance of 2, the ring runs from radii (102, 52) down to (94, 44).
    @Test func ellipseHitOnRingNotCentre() {
        let shape = ellipse(box, id: id)
        let tolerance: CGFloat = 2
        // The handles are the bounding box's, as for a rectangle.
        #expect(HitTester.handles(for: shape) == HitTester.handles(for: rectangle(box)))
        #expect(HitTester.hit(shape, at: CGPoint(x: 201, y: 51), tolerance: tolerance) == .handle(1))
        // On the stroke, just outside it (within the tolerance) and just inside it.
        #expect(HitTester.hit(shape, at: CGPoint(x: 230, y: 54), tolerance: tolerance) == .body)
        #expect(HitTester.hit(shape, at: CGPoint(x: 230, y: 51), tolerance: tolerance) == .body)
        #expect(HitTester.hit(shape, at: CGPoint(x: 230, y: 57), tolerance: tolerance) == .body)
        // Beyond the tolerance outside, and inside the hollow: no hit.
        #expect(HitTester.hit(shape, at: CGPoint(x: 230, y: 48), tolerance: tolerance) == nil)
        #expect(HitTester.hit(shape, at: CGPoint(x: 230, y: 62), tolerance: tolerance) == nil)
        #expect(HitTester.hit(shape, at: CGPoint(x: 200, y: 100), tolerance: tolerance) == nil)
        // The bounding box's corner region is outside an ellipse and on a rectangle.
        let corner = CGPoint(x: 296, y: 146)
        #expect(HitTester.hit(shape, at: corner, tolerance: tolerance) == nil)
        #expect(HitTester.hit(rectangle(box), at: corner, tolerance: tolerance) == .body)
        // Too small to have a hollow, it is filled, as it is drawn.
        let dot = ellipse(CGRect(x: 0, y: 0, width: 10, height: 10))
        #expect(HitTester.hit(dot, at: CGPoint(x: 5, y: 5), tolerance: tolerance) == .body)
        // Handles resize it like a rectangle, keeping id and stroke.
        #expect(HitTester.resized(shape, handle: 4, to: CGPoint(x: 320, y: 170), square: false)
                == ellipse(CGRect(x: 100, y: 50, width: 220, height: 120), id: id))
        #expect(HitTester.resized(shape, handle: 4, to: CGPoint(x: 400, y: 100), square: true)
                == ellipse(CGRect(x: 100, y: 50, width: 300, height: 300), id: id))
        // Moving shifts the rect.
        #expect(shape.moved(by: CGVector(dx: 5, dy: -3)) == ellipse(box.offsetBy(dx: 5, dy: -3), id: id))
    }

    @Test func lineHitWithinWidth() {
        let level = line(CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 0), lineWidth: 10, id: id)
        // Within lineWidth / 2 + tolerance = 7 of the segment, which includes a round cap past each end.
        #expect(HitTester.hit(level, at: CGPoint(x: 50, y: 6), tolerance: 2) == .body)
        #expect(HitTester.hit(level, at: CGPoint(x: 50, y: 8), tolerance: 2) == nil)
        #expect(HitTester.hit(level, at: CGPoint(x: 106, y: 0), tolerance: 2) == .body)
        #expect(HitTester.hit(level, at: CGPoint(x: -8, y: 0), tolerance: 2) == nil)
        // A diagonal measures the perpendicular distance: 7 / sqrt(2) = 4.95 in, 10 / sqrt(2) = 7.07 out.
        let diagonal = line(CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 100), lineWidth: 10)
        #expect(HitTester.hit(diagonal, at: CGPoint(x: 50, y: 57), tolerance: 2) == .body)
        #expect(HitTester.hit(diagonal, at: CGPoint(x: 50, y: 60), tolerance: 2) == nil)
        // Two endpoint handles, tail then head, which beat the body.
        #expect(HitTester.handles(for: level) == [CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 0)])
        #expect(HitTester.hit(level, at: CGPoint(x: 99, y: 1), tolerance: 8) == .handle(1))
        #expect(HitTester.hit(level, at: CGPoint(x: 1, y: 1), tolerance: 8) == .handle(0))
        // A moved end keeps id, colour and width; Shift snaps it to 45 degrees around the other end.
        let original = line(CGPoint(x: 10, y: 10), CGPoint(x: 100, y: 10), lineWidth: 6, id: id)
        #expect(HitTester.resized(original, handle: 1, to: CGPoint(x: 120, y: 40), square: false)
                == line(CGPoint(x: 10, y: 10), CGPoint(x: 120, y: 40), lineWidth: 6, id: id))
        #expect(HitTester.resized(original, handle: 1, to: CGPoint(x: 200, y: 15), square: true)
                == line(CGPoint(x: 10, y: 10), CGPoint(x: 200, y: 10), lineWidth: 6, id: id))
        // Moving shifts both ends.
        #expect(original.moved(by: CGVector(dx: 5, dy: -3))
                == line(CGPoint(x: 15, y: 7), CGPoint(x: 105, y: 7), lineWidth: 6, id: id))
    }
```

`TidyShotTests/EditorFlattenerTests.swift`. After the `arrow(from:to:lineWidth:)` helper (line 100), add:
```swift
    func ellipse(_ rect: CGRect, lineWidth: CGFloat = 4) -> Annotation {
        .ellipse(ShapeBox(id: UUID(), rect: rect, color: red, lineWidth: lineWidth))
    }

    func line(from: CGPoint, to: CGPoint, lineWidth: CGFloat = 4) -> Annotation {
        .line(Segment(id: UUID(), from: from, to: to, color: blue, lineWidth: lineWidth))
    }
```
After `arrowHeadPixelPresent` (ends at line 194, before `drawingsRenderAboveTiles`), add:
```swift
    /// A 4 px stroke on the ellipse in (10, 8, 40, 24) sits inside the rect: the centre line is the
    /// ellipse in (12, 10, 36, 20), centre (30, 20) with radii 18 and 10, so the band runs from radii
    /// (16, 8) to (20, 12). The bounding box's corners and the hollow are untouched, which tells an
    /// ellipse from a rectangle, and the off-centre rows tell a flip.
    @Test func ellipseStrokePixels() throws {
        let base = makeImage()
        let original = try Bitmap(base)
        let output = try Bitmap(flatten(base, [ellipse(CGRect(x: 10, y: 8, width: 40, height: 24))]))
        let stroked = [(11, 19), (11, 20), (47, 19), (47, 20), (30, 9), (29, 9), (30, 30), (29, 30), (42, 26)]
        for (x, y) in stroked {
            #expect(output[x, y] == Self.redPixel, "stroke at \(x), \(y)")
        }
        let untouched = [(30, 20), (20, 20), (10, 8), (49, 8), (10, 31), (49, 31), (8, 20), (30, 6)]
        for (x, y) in untouched {
            #expect(output[x, y] == original[x, y], "untouched at \(x), \(y)")
        }
    }

    /// A level line along row 12 (rows 10 to 13 at 4 px) with round caps: the pixels just beyond
    /// each end, which a butt cap would leave alone, are painted. A diagonal from (10, 30) to
    /// (40, 40) crosses (25, 35). Neither line is near the middle row, so a flip would move them.
    @Test func lineStrokePixels() throws {
        let base = makeImage()
        let original = try Bitmap(base)
        let level = line(from: CGPoint(x: 8, y: 12), to: CGPoint(x: 56, y: 12))
        let slanted = line(from: CGPoint(x: 10, y: 30), to: CGPoint(x: 40, y: 40))
        let output = try Bitmap(flatten(base, [level, slanted]))
        let stroked = [(30, 10), (30, 13), (8, 11), (7, 11), (7, 12), (56, 11), (56, 12), (25, 35)]
        for (x, y) in stroked {
            #expect(output[x, y] == Self.bluePixel, "stroke at \(x), \(y)")
        }
        let untouched = [(30, 8), (30, 15), (4, 12), (60, 12), (25, 40), (25, 30)]
        for (x, y) in untouched {
            #expect(output[x, y] == original[x, y], "untouched at \(x), \(y)")
        }
    }
```

`TidyShotTests/CanvasToolTests.swift`. In `FakeCanvasEditing.makeAnnotation` (line 33), add two cases before `default` (line 47):
```swift
        case .ellipse:
            return .ellipse(ShapeBox(id: UUID(), rect: rect, color: EditorPalette.defaultStroke, lineWidth: 8))
        case .line:
            return .line(Segment(id: UUID(), from: from, to: to, color: EditorPalette.defaultStroke, lineWidth: 8))
```
In the test helpers, make `rect(of:)` (line 59) and `segment(of:)` (line 66) see the new cases:
```swift
        case .rectangle(let box)?, .ellipse(let box)?: box.rect
```
```swift
        switch annotation {
        case .arrow(let segment)?, .line(let segment)?: return segment
        default: return nil
        }
```
(Replace the single `if case .arrow(let segment)? = annotation { return segment }` body of `segment(of:)` with that switch.) After `shiftViaFlagsChangedSquares` add:
```swift
    @Test func ellipseShiftMakesCircleAndLineSnapsTo45() throws {
        let canvas = FakeCanvasEditing()
        let ellipse = makeTool(for: .ellipse)
        #expect(ellipse is RectDragTool)
        ellipse.mouseDown(at(10, 10), on: canvas)
        ellipse.mouseDragged(at(50, 30), on: canvas)
        #expect(rect(of: canvas.transient) == CGRect(x: 10, y: 10, width: 40, height: 20))
        // Shift goes down with the mouse still: the ellipse becomes a circle.
        ellipse.flagsChanged(at(50, 30, shift: true), on: canvas)
        #expect(rect(of: canvas.transient) == CGRect(x: 10, y: 10, width: 40, height: 40))
        ellipse.mouseUp(at(50, 30, shift: true), on: canvas)
        #expect(canvas.commits.count == 1)
        #expect(canvas.commits.first?.actionName == "Add Ellipse")
        #expect(rect(of: canvas.document.annotations.last) == CGRect(x: 10, y: 10, width: 40, height: 40))
        #expect(canvas.selection == canvas.document.annotations.last?.id)

        let line = makeTool(for: .line)
        #expect(line is TwoPointTool)
        line.mouseDown(at(10, 10), on: canvas)
        line.mouseDragged(at(60, 18), on: canvas)
        #expect(segment(of: canvas.transient)?.to == CGPoint(x: 60, y: 18))
        line.flagsChanged(at(60, 18, shift: true), on: canvas)
        #expect(segment(of: canvas.transient)?.from == CGPoint(x: 10, y: 10))
        #expect(segment(of: canvas.transient)?.to == CGPoint(x: 60, y: 10))
        line.mouseUp(at(60, 18, shift: true), on: canvas)
        #expect(canvas.commits.count == 2)
        #expect(canvas.commits.last?.actionName == "Add Line")
        #expect(segment(of: canvas.document.annotations.last)?.to == CGPoint(x: 60, y: 10))
    }
```

`TidyShotTests/EditorModelTests.swift`, in `makeAnnotationUsesToolSettingsInImagePixels` (line 280): after the arrow block (ends line 299) add
```swift
        if case .ellipse(let shape)? = model.makeAnnotation(.ellipse, from: from, to: to) {
            #expect(shape.rect == rect)
            #expect(shape.color == model.strokeColor)
            #expect(shape.lineWidth == model.lineWidthPoints * 2)
        } else {
            Issue.record("no ellipse")
        }
        if case .line(let segment)? = model.makeAnnotation(.line, from: from, to: to) {
            #expect(segment.from == from)
            #expect(segment.to == to)
            #expect(segment.color == model.strokeColor)
            #expect(segment.lineWidth == model.lineWidthPoints * 2)
        } else {
            Issue.record("no line")
        }
```
and after `#expect(model.makeAnnotation(.arrow, from: from, to: from) == nil)` (line 319) add
```swift
        #expect(model.makeAnnotation(.ellipse, from: from, to: CGPoint(x: 12, y: 20)) == nil)
        #expect(model.makeAnnotation(.line, from: from, to: from) == nil)
```

`TidyShotTests/EditorWindowGeometryTests.swift`. The existing `toolbarWidthCountsEveryItem` (line 71) passes its segment count explicitly, so it stays valid. After `minimumContentWidthCoversTheToolbar` (line 87) add:
```swift
    /// Every tool in `EditorTool.toolbarOrder` is one more segment, so each new tool widens the
    /// toolbar by `ToolbarMetrics.segment`. With the widest title, the toolbar for the tools the
    /// editor has must still fit 90 % of a 1280 pt wide display, or the 90 % cap would win over
    /// the minimum and the toolbar would overflow.
    @Test func toolbarWithEveryToolFitsASmallDisplay() {
        func width(segments: Int) -> CGFloat {
            EditorWindowGeometry.toolbarWidth(windowButtonsMaxX: EditorWindowGeometry.ToolbarMetrics.windowButtons,
                                              titleWidth: 230, toolSegments: segments, buttons: 4,
                                              prominentButtons: 1, viewWidths: [84], fixedSpaces: 1)
        }
        #expect(width(segments: 8) - width(segments: 6) == 2 * EditorWindowGeometry.ToolbarMetrics.segment)
        // The 4a toolbar is 800 pt wide. Each 4b task that adds a tool updates these two lines:
        // 8 tools and 872 pt (Task 1), 10 and 944 (Task 2), 11 and 980 (Task 3), 12 and 1016 (Task 4).
        #expect(EditorTool.toolbarOrder.count == 8)
        #expect(width(segments: EditorTool.toolbarOrder.count) == 872)
        let widest = EditorWindowGeometry.minimumContentWidth(toolbarWidth: width(segments: EditorTool.toolbarOrder.count))
        let ninetyPercent = (1280 * EditorWindowGeometry.screenFraction).rounded(.down)
        #expect(widest <= ninetyPercent)
    }
```
This is the one toolbar-width test 4b keeps. It pins the toolbar at the current tool count, so a task that adds a tool fails it until that task, in the same commit, replaces the two pinned lines with its own count and width (`800 + 36 * (count - 6)` with `main`'s metrics): Task 2 writes 10 and 944, Task 3 11 and 980, Task 4 12 and 1016. No later task adds another toolbar-width test.

- [ ] **Step 2: Run the tests and see them fail**

Run the header's full-suite command. Expected: no test runs; the build fails with errors such as `type 'Annotation' has no member 'ellipse'`, `type 'EditorTool' has no member 'ellipse'` and `type 'Annotation' has no member 'line'`, in `EditorToolTests.swift`, `HitTesterTests.swift`, `EditorFlattenerTests.swift`, `CanvasToolTests.swift` and `EditorModelTests.swift`.

- [ ] **Step 3: Implement the model**

`TidyShot/Editor/Model/Annotation.swift`. Every switch is exhaustive, so each one gets the two cases. Update the enum's doc (lines 30-31) to `drawings (rectangle, ellipse, arrow, line)`.

Cases (lines 33-38): add after `case arrow(Segment)`:
```swift
    case ellipse(ShapeBox)
    case line(Segment)
```
`id` (lines 40-46):
```swift
        case .rectangle(let box), .ellipse(let box): box.id
        case .arrow(let segment), .line(let segment): segment.id
```
`isEffect` (lines 48-53) and `effectRect` (lines 56-61): add the new cases to the existing drawing arm:
```swift
        case .rectangle, .ellipse, .arrow, .line: false
```
```swift
        case .rectangle, .ellipse, .arrow, .line: nil
```
`title` (lines 64-72): add `case .ellipse: "Ellipse"` and `case .line: "Line"`.

`moved(by:)` (lines 75-94): add
```swift
        case .ellipse(var box):
            box.rect = box.rect.offsetBy(dx: delta.dx, dy: delta.dy)
            return .ellipse(box)
        case .line(var segment):
            segment.from = CGPoint(x: segment.from.x + delta.dx, y: segment.from.y + delta.dy)
            segment.to = CGPoint(x: segment.to.x + delta.dx, y: segment.to.y + delta.dy)
            return .line(segment)
```
`withColor(_:)` (lines 98-111) and `withLineWidth(_:)` (lines 114-125): add
```swift
        case .ellipse(var box):
            box.color = color
            return .ellipse(box)
        case .line(var segment):
            segment.color = color
            return .line(segment)
```
and in `withLineWidth` the same with `box.lineWidth = width` and `segment.lineWidth = width`. `withEffectParameter(_:)` (lines 129-138): extend the unchanged arm to `case .rectangle, .ellipse, .arrow, .line, .redact:`.

`TidyShot/Editor/Model/EditorTool.swift`:
- Line 4: `case select, redact, pixelate, blur, rectangle, arrow, ellipse, line`.
- `letter` (lines 7-16): `case .ellipse: "E"` and `case .line: "L"`.
- `title` (lines 18-27): `case .ellipse: "Ellipse"` and `case .line: "Line"`.
- `symbolName` (lines 30-39): `case .ellipse: "circle"` and `case .line: "line.diagonal"`.
- `isEffect` (lines 45-50): `case .select, .rectangle, .arrow, .ellipse, .line: false`.
- `toolbarOrder` (lines 52-56): replace the doc's last sentence with `4b appends its tools here, in toolbar order.` and the body with
```swift
        [.select, .redact, .pixelate, .blur, .rectangle, .arrow, .ellipse, .line]
```

- [ ] **Step 4: Implement hit testing and bounds**

`TidyShot/Editor/Geometry/HitTester.swift`.

Doc of `handles(for:)` (lines 22-25): boxes are the rectangle, the ellipse and every effect; a segment (arrow or line) has two handles.

`handles(for:)` (lines 26-35):
```swift
        case .rectangle(let shape), .ellipse(let shape):
            boxHandles(shape.rect)
        case .redact(let region, _), .blur(let region, _), .pixelate(let region, _):
            boxHandles(region.rect)
        case .arrow(let segment), .line(let segment):
            [segment.from, segment.to]
```
`resized(_:handle:to:square:)` (lines 64-86): add after the `.rectangle` and `.arrow` cases
```swift
        case .ellipse(var shape):
            shape.rect = resizedRect(shape.rect, handle: handle, to: point, square: square)
            return .ellipse(shape)
```
```swift
        case .line(var segment):
            switch handle {
            case 0: segment.from = DragGeometry.segmentEnd(from: segment.to, to: point, snap45: square)
            case 1: segment.to = DragGeometry.segmentEnd(from: segment.from, to: point, snap45: square)
            default: break
            }
            return .line(segment)
```
`bodyContains` (lines 141-157). Extend the doc: an ellipse is hollow like a rectangle, so its body is the ring between the ellipse grown by `tolerance` and the ellipse of the rect inset by `lineWidth + tolerance`; a line is hit like an arrow's shaft. Add

```swift
        case .ellipse(let shape):
            let rect = shape.rect.standardized
            let outer = rect.insetBy(dx: -tolerance, dy: -tolerance)
            let inner = rect.insetBy(dx: shape.lineWidth + tolerance, dy: shape.lineWidth + tolerance)
            return ellipseContains(outer, point) && !ellipseContains(inner, point)
        case .line(let segment):
            return distance(from: point, toSegment: segment.from, segment.to) <= segment.lineWidth / 2 + tolerance
```
and the helper next to `distance(from:toSegment:_:)`:
```swift
    /// Whether `point` is inside or on the ellipse inscribed in `rect`. An empty or null rect
    /// holds nothing, so a rect inset past its own size has no hollow and the ring is a disc,
    /// as `AnnotationDrawing` fills an ellipse that small.
    private static func ellipseContains(_ rect: CGRect, _ point: CGPoint) -> Bool {
        guard !rect.isNull, rect.width > 0, rect.height > 0 else { return false }
        let dx = (point.x - rect.midX) / (rect.width / 2)
        let dy = (point.y - rect.midY) / (rect.height / 2)
        return dx * dx + dy * dy <= 1
    }
```

`TidyShot/Editor/Geometry/ArrowGeometry.swift`, `AnnotationGeometry.bounds(of:scale:)` (lines 53-69). The ellipse's stroke sits inside its rect and a line has round caps and no head:
```swift
        case .rectangle(let shape), .ellipse(let shape):
            // The stroke sits inside the rect.
            painted = shape.rect.standardized
        case .line(let segment):
            let cap = segment.lineWidth / 2
            painted = enclosing([segment.from, segment.to]).insetBy(dx: -cap, dy: -cap)
```
(the first arm replaces the `.rectangle` arm at lines 56-58; keep `.arrow` and the effects arm.)

- [ ] **Step 5: Implement drawing and the model's shape builder**

`TidyShot/Editor/Rendering/AnnotationDrawing.swift`, `draw(_:in:scale:)` (lines 16-25): add `case .ellipse(let box): strokeEllipse(box, in: context)` and `case .line(let segment): strokeLine(segment, in: context)`. Update the doc comment of `draw` where it says what `scale` sizes (the arrow head only). Add the two functions after `drawArrow`:
```swift
    /// Stroked inset by half the line width, so the stroke sits inside the rect, as the rectangle's
    /// does. An ellipse no wider or taller than the line is filled instead, because the inset
    /// ellipse would be empty.
    private static func strokeEllipse(_ box: ShapeBox, in context: CGContext) {
        let rect = box.rect.standardized
        guard rect.width > 0, rect.height > 0, box.lineWidth > 0 else { return }
        context.saveGState()
        defer { context.restoreGState() }
        if rect.width <= box.lineWidth || rect.height <= box.lineWidth {
            context.setFillColor(box.color.cgColor)
            context.fillEllipse(in: rect)
            return
        }
        context.setStrokeColor(box.color.cgColor)
        context.setLineWidth(box.lineWidth)
        context.strokeEllipse(in: rect.insetBy(dx: box.lineWidth / 2, dy: box.lineWidth / 2))
    }

    /// A straight stroke from `from` to `to` with round caps and no head.
    private static func strokeLine(_ segment: Segment, in context: CGContext) {
        guard segment.from != segment.to, segment.lineWidth > 0 else { return }
        context.saveGState()
        defer { context.restoreGState() }
        context.setStrokeColor(segment.color.cgColor)
        context.setLineWidth(segment.lineWidth)
        context.setLineCap(.round)
        context.move(to: segment.from)
        context.addLine(to: segment.to)
        context.strokePath()
    }
```

`TidyShot/Editor/Session/EditorModel.swift`, `makeAnnotation` (lines 132-157): add after the `.rectangle` and `.arrow` cases
```swift
        case .ellipse:
            guard !rect.isEmpty else { return nil }
            return .ellipse(ShapeBox(id: id, rect: rect, color: strokeColor, lineWidth: lineWidthPoints * scale))
        case .line:
            guard start != end else { return nil }
            return .line(Segment(id: id, from: start, to: end, color: strokeColor, lineWidth: lineWidthPoints * scale))
```
`color(of:)` (lines 244-251), so the toolbar circle and the palette follow a selected ellipse or line:
```swift
        case .rectangle(let box)?, .ellipse(let box)?: return box.color
        case .arrow(let segment)?, .line(let segment)?: return segment.color
```
`editsRedactColor`, `applyColor`, `applyLineWidth` and the line width popover need no change: they go through `withColor` and `withLineWidth`.

- [ ] **Step 6: Wire the tools and the toolbar**

`TidyShot/Editor/Tools/ToolFactory.swift` (lines 1-12): replace the doc's last sentence and the two lines of the switch:
```swift
/// The tool object behind each `EditorTool`. The switch is exhaustive with no default, so a new
/// case does not compile until it is wired here.
func makeTool(for tool: EditorTool) -> any CanvasTool {
    switch tool {
    case .select: return SelectTool()
    case .redact, .pixelate, .blur, .rectangle, .ellipse: return RectDragTool(tool: tool)
    case .arrow, .line: return TwoPointTool(tool: tool)
    }
}
```
`TidyShot/Editor/Tools/RectDragTool.swift` line 3 and `TwoPointTool.swift` line 3: change the doc comments to name Ellipse and Line ("for Redact, Pixelate, Blur, Rectangle and Ellipse"; "Arrow and Line"). No code in the two tools changes: Shift and Option arrive in `ToolInput`, and `canvas.makeAnnotation(tool, ...)` builds the right case.

`TidyShot/Editor/Window/EditorToolbar.swift`: no code changes. `makeToolsItem` (lines 202-214) builds the group's images, labels and tooltips from `EditorTool.toolbarOrder`, and `selectToolFromToolbar` and `reflectTool` index into the same array, so the two tools appear as segments, in the collapsed menu (labels `Ellipse` and `Line`) and on E and L. Update the comment at lines 36-37 from "the six tool segments" to "one segment per tool in `EditorTool.toolbarOrder`".

`TidyShot/Editor/Geometry/EditorWindowGeometry.swift`, line 50: give `segment` the doc `/// One segment per tool in EditorTool.toolbarOrder: six in 4a, eight with Ellipse and Line, twelve after 4b.` The value stays 36 and the other metrics stay as they are, because `minimumToolbarContentWidth()` already passes `toolSegments: EditorTool.toolbarOrder.count` (`EditorToolbar.swift:45`) and `toolbarWidth` adds 36 pt per segment: the content minimum for a 230 pt title grows from 800 to 872 pt. Step 8 checks that against the real toolbar.

- [ ] **Step 7: Run the suite**

Run:
```bash
xcodegen generate && xcodebuild test -project TidyShot.xcodeproj -scheme TidyShot -destination 'platform=macOS' -derivedDataPath .build 2>&1 | grep -E "Test run with|error:|TEST"
```
Expected: no `error:` lines, and `Test run with 420 tests in 52 suites passed`. This task adds 6 tests (`ellipseHitOnRingNotCentre`, `lineHitWithinWidth`, `ellipseStrokePixels`, `lineStrokePixels`, `ellipseShiftMakesCircleAndLineSnapsTo45`, `toolbarWithEveryToolFitsASmallDisplay`) and no new suite; the assertions added to `lettersAreUnique`, `everyToolHasSymbolAndTooltipWithLetter`, `toolbarOrderCoversEveryToolOnce` and `makeAnnotationUsesToolSettingsInImagePixels` raise no count. If an ellipse pixel assertion fails by one pixel at an edge, the probe sits on antialiasing: move the probe one pixel into the band, never loosen the comparison.

- [ ] **Step 8: Hand checks**

Build and run the app, take a capture and press Annotate (or open one from Recent Captures).
- The toolbar shows eight tool segments (Select, Redact, Pixelate, Blur, Rectangle, Arrow, Ellipse, Line) with no overflow chevron. Hover Ellipse and Line: tool tips `Ellipse (E)` and `Line (L)`. Resize the window to its smallest width, with a short title and then a long one: still no chevron. If a chevron appears, the metrics undercount: raise `ToolbarMetrics.segment` to 38, change the expected widths in `toolbarWidthCountsEveryItem` (800 and 744) and in `toolbarWithEveryToolFitsASmallDisplay` (872) by 2 pt per segment (812, 756 and 888), and run the suite again. Then the widths Tasks 2 to 4 pin become `812 + 38 * (count - 6)`: say so in the commit message so they use them.
- Press E then drag: an ellipse follows the pointer. Hold Shift mid-drag without moving: it becomes a circle. Hold Option: it grows from the press point. Release: it stays selected with eight handles; the stroke sits inside the dragged box, and the toolbar shows E selected. Press L and drag: a plain line with round ends and no head. Hold Shift: it snaps to horizontal, vertical or a diagonal; a level or vertical drag is kept.
- With V, click on an ellipse's ring (it selects) and in its hollow (it does not, unless another shape is there); drag a ring to move it; drag a handle to resize, and Shift on a corner handle squares it. Drag a line's endpoint, and Shift snaps it. Change the colour and the line width from the toolbar with each selected. ⌘Z undoes each creation, move and resize in one step each.
- Save, then open the file: the ellipse and line match the canvas. Draw at 200 % zoom and at Fit: line widths look the same in the saved file (they are stored in image pixels).
- The collapsed-menu labels come from `EditorTool.title`, which the tests pin (`Ellipse`, `Line`). The window cannot be made narrow enough to collapse the group, so there is nothing more to check here.

- [ ] **Step 9: Commit**

```bash
git add TidyShot/Editor/Model/Annotation.swift TidyShot/Editor/Model/EditorTool.swift TidyShot/Editor/Geometry/HitTester.swift TidyShot/Editor/Geometry/ArrowGeometry.swift TidyShot/Editor/Geometry/EditorWindowGeometry.swift TidyShot/Editor/Rendering/AnnotationDrawing.swift TidyShot/Editor/Session/EditorModel.swift TidyShot/Editor/Tools/ToolFactory.swift TidyShot/Editor/Tools/RectDragTool.swift TidyShot/Editor/Tools/TwoPointTool.swift TidyShot/Editor/Window/EditorToolbar.swift TidyShotTests/EditorToolTests.swift TidyShotTests/HitTesterTests.swift TidyShotTests/EditorFlattenerTests.swift TidyShotTests/CanvasToolTests.swift TidyShotTests/EditorModelTests.swift TidyShotTests/EditorWindowGeometryTests.swift
git commit -m "feat: ellipse and line tools"
```

### Task 2: Pencil and Highlighter (TDD)

**Files:**
- Create: `TidyShot/Editor/Geometry/StrokeSmoothing.swift`
- Create: `TidyShot/Editor/Tools/PencilTool.swift`
- Create: `TidyShotTests/StrokeSmoothingTests.swift`
- Modify: `TidyShot/Editor/Model/Annotation.swift` (`Segment` ends at line 22; the `Annotation` switches at lines 40, 48, 56, 64, 75, 98, 114, 129)
- Modify: `TidyShot/Editor/Model/EditorTool.swift` (cases line 4; switches at 7, 18, 30, 45; `toolbarOrder` at 54)
- Modify: `TidyShot/Editor/Model/EditorPalette.swift` (after `lineWidthsPoints`, line 23)
- Modify: `TidyShot/Editor/Model/RGBA.swift` (after `cgColor`)
- Modify: `TidyShot/Editor/Geometry/HitTester.swift` (`handles` line 26, `resized` line 64, `bodyContains` line 145)
- Modify: `TidyShot/Editor/Geometry/ArrowGeometry.swift` (`AnnotationGeometry.bounds` line 53)
- Modify: `TidyShot/Editor/Rendering/AnnotationDrawing.swift` (`draw` line 16, `drawSelection` line 56)
- Modify: `TidyShot/Editor/Tools/CanvasTool.swift` (`CanvasEditing`, line 31)
- Modify: `TidyShot/Editor/Tools/ToolFactory.swift` (the switch, lines 5 to 11)
- Modify: `TidyShot/Editor/Session/EditorModel.swift` (`makeAnnotation` line 132, `activeColor` line 197, `applyColor` line 208, `applyLineWidth` line 215, `color(of:)` line 244)
- Modify: `TidyShot/Editor/Window/CanvasView.swift` (`draw` line 382)
- Modify: `TidyShot/Editor/Window/ColorPaletteView.swift` (lines 26 and 45), `TidyShot/Editor/Window/ToolOptionsView.swift` (line 60), `TidyShot/Editor/Window/EditorToolbar.swift` (comment at line 36)
- Test: `TidyShotTests/StrokeSmoothingTests.swift`, `HitTesterTests.swift`, `ArrowGeometryTests.swift`, `EditorFlattenerTests.swift`, `CanvasToolTests.swift`, `EditorModelTests.swift`, `AnnotationDocumentTests.swift`, `EditorWindowGeometryTests.swift`

Line numbers are those of `main` at 9193586. Task 1 adds `ellipse` and `line` to the same switches and shifts them, so find each place by the construct named, and add this task's cases beside Task 1's. Every `Annotation` and `EditorTool` switch below is exhaustive with no default, so Steps 3 to 8 must all be in place before the build succeeds.

**Interfaces:**
- Consumes:
  - `main`: `ShapeBox`, `Segment`, `Annotation` and its members (`id`, `isEffect`, `effectRect`, `title`, `moved(by:)`, `withColor(_:)`, `withLineWidth(_:)`, `withEffectParameter(_:)`); `AnnotationDocument.appending(_:)` and `annotation(id:)`; `EditorTool`, `makeTool(for:)`, `CanvasTool`, `CanvasEditing`, `ToolInput`; `CanvasEditing.commitNewShape(_:)` (ToolFactory.swift:14); `DragGeometry.isLongEnough(from:to:zoom:)`; `HitTester.tolerance(zoom:)`, `hit`, `topmost`; `AnnotationGeometry` (ArrowGeometry.swift:49) and its private `enclosing`; `AnnotationDrawing.draw`, `drawSelection`; `EditorModel.strokeColor`, `lineWidthPoints`, `scale`, `transient`, `commit`; `EditorPalette` (`yellow` is private to it); `RGBA`; `EditorWindowGeometry.toolbarWidth(...)`.
  - Task 1: `Annotation.ellipse(ShapeBox)`, `Annotation.line(Segment)`, `EditorTool.ellipse` (E) and `.line` (L), and `toolbarOrder` ending `... .rectangle, .arrow, .ellipse, .line`. This task appends after `.line`.
- Produces (all nonisolated unless noted):
  - `struct Stroke: Codable, Equatable, Sendable { let id: UUID; var points: [CGPoint]; var color: RGBA; var lineWidth: CGFloat }`. `points` are the decimated pointer samples in image pixels. The smoothed curve is rebuilt from them whenever it is drawn or hit, and no `CGPath` is stored.
  - `Annotation.pencil(Stroke)` and `Annotation.highlighter(Stroke)`; titles `Pencil` and `Highlighter`; both are drawings, move by shifting every point, and have no handles.
  - `EditorTool.pencil` (P, symbol `pencil`) and `EditorTool.highlighter` (H, symbol `highlighter`), appended to `toolbarOrder` after `.line`.
  - `makeTool(for:)` returns `PencilTool(tool:)` for both. `final class PencilTool: CanvasTool { let tool: EditorTool; init(tool: EditorTool) }`. Undo names `Add Pencil` and `Add Highlighter`.
  - `CanvasEditing.makeStroke(_ tool: EditorTool, points: [CGPoint]) -> Annotation?`: the model builds the stroke with the tool's colour and width, reusing `transient?.id`; nil for fewer than two points and for any tool but Pencil and Highlighter. `makeAnnotation` returns nil for the two new tools.
  - `enum StrokeSmoothing { static let spacingPoints: CGFloat; static let segmentsPerSpan: Int; static func decimated(_ points: [CGPoint], minDistance: CGFloat) -> [CGPoint]; static func catmullRom(_ points: [CGPoint]) -> [CGPoint]; static func path(for points: [CGPoint]) -> CGPath }`.
  - `HitTester.strokeContains(_ stroke: Stroke, _ point: CGPoint, tolerance: CGFloat) -> Bool`. `AnnotationGeometry.strokeBounds(of: Stroke) -> CGRect` and `AnnotationGeometry.strokeOutline(of: Annotation) -> CGRect?` (the dashed selection box).
  - `EditorPalette.highlighterAlpha` (0.45), `.defaultHighlight` (the palette yellow at that alpha), `.highlighterWidthPoints` (12) and `.highlighterColor(from:)`; `RGBA.withAlpha(_:)`.
  - `EditorModel.highlightColor`, `.highlightWidthPoints` and `.activeLineWidthPoints` (not persisted; a new editor starts from the defaults above). With the Highlighter tool active, or Select with a highlighter selected, a colour pick sets `highlightColor` at alpha 0.45 and a line width pick sets `highlightWidthPoints`; the Pencil keeps `strokeColor` and `lineWidthPoints`.
  - Rendering: Pencil strokes with round caps and joins in normal blend. Highlighter strokes the same path once in multiply blend, so a stroke crossing itself does not darken twice. The canvas fills a highlighter's stroked area with a copy of the capture and tiles before drawing, so the preview multiplies against real pixels like the export.

Rules for this task (spec 2.6, Phase 4b and Tools):
- One stroke is one gesture and one commit, on mouseUp, named `Add Pencil` or `Add Highlighter`. While dragging, the stroke lives only in `canvas.transient`, under one id.
- A stroke whose points all lie within 2 / zoom image pixels of the first leaves nothing. Escape mid-stroke abandons it, as for every tool.
- Pointer samples are decimated to a spacing of `spacingPoints / zoom` image pixels (2 view points) and always keep the last sample, so the stroke ends under the pointer.
- No resize handles. A selected stroke shows a dashed outline of its bounds; it moves, recolours and changes width through the existing paths.
- The highlighter is yellow at 0.45 alpha and 12 pt by default, and any colour picked for it keeps alpha 0.45.

- [ ] **Step 1: Write the failing tests**

Create `TidyShotTests/StrokeSmoothingTests.swift`:
```swift
import CoreGraphics
import Testing
@testable import TidyShot

struct StrokeSmoothingTests {
    /// Distance is measured from the last point kept, so a slow drift still adds points; the last
    /// sample always stays, so the stroke ends where the pointer did.
    @Test func decimationDropsClosePoints() {
        let line = [CGPoint(x: 0, y: 0), CGPoint(x: 0.5, y: 0), CGPoint(x: 1, y: 0), CGPoint(x: 3, y: 0),
                    CGPoint(x: 3.4, y: 0), CGPoint(x: 10, y: 0)]
        #expect(StrokeSmoothing.decimated(line, minDistance: 2)
                == [CGPoint(x: 0, y: 0), CGPoint(x: 3, y: 0), CGPoint(x: 10, y: 0)])

        // 1 and 2 are under 2.5 from the point kept (0) even though each is 1 from its neighbour; 3 is not.
        let drift = [CGPoint(x: 0, y: 0), CGPoint(x: 1, y: 0), CGPoint(x: 2, y: 0), CGPoint(x: 3, y: 0)]
        #expect(StrokeSmoothing.decimated(drift, minDistance: 2.5) == [CGPoint(x: 0, y: 0), CGPoint(x: 3, y: 0)])

        // A last sample closer than the minimum is kept anyway.
        let tail = [CGPoint(x: 0, y: 0), CGPoint(x: 5, y: 0), CGPoint(x: 5.5, y: 0)]
        #expect(StrokeSmoothing.decimated(tail, minDistance: 2) == tail)

        #expect(StrokeSmoothing.decimated([], minDistance: 2) == [])
        #expect(StrokeSmoothing.decimated([CGPoint(x: 4, y: 4)], minDistance: 2) == [CGPoint(x: 4, y: 4)])
    }

    /// The curve starts and ends on the first and last point, passes through every other point, and
    /// has `segmentsPerSpan` samples per span. Fewer than three points are returned as they are.
    @Test func smoothingKeepsEndpoints() {
        let corner = [CGPoint(x: 0, y: 0), CGPoint(x: 10, y: 20), CGPoint(x: 30, y: 10), CGPoint(x: 40, y: 40)]
        let curve = StrokeSmoothing.catmullRom(corner)
        #expect(curve.first == corner.first)
        #expect(curve.last == corner.last)
        #expect(curve.count == 1 + (corner.count - 1) * StrokeSmoothing.segmentsPerSpan)
        #expect(curve.contains(corner[1]))
        #expect(curve.contains(corner[2]))

        #expect(StrokeSmoothing.catmullRom([]) == [])
        #expect(StrokeSmoothing.catmullRom([corner[0]]) == [corner[0]])
        #expect(StrokeSmoothing.catmullRom([corner[0], corner[3]]) == [corner[0], corner[3]])

        // Equally spaced points on a level line stay on it.
        let level = [CGPoint(x: 0, y: 5), CGPoint(x: 10, y: 5), CGPoint(x: 20, y: 5), CGPoint(x: 30, y: 5)]
        #expect(StrokeSmoothing.catmullRom(level).allSatisfy { $0.y == 5 })
    }
}
```

`TidyShotTests/HitTesterTests.swift`: add the helper beside `blur(_:id:)` (line 20):
```swift
    func pencil(_ points: [CGPoint], width: CGFloat = 8, id: UUID = UUID()) -> Annotation {
        .pencil(Stroke(id: id, points: points, color: red, lineWidth: width))
    }
```
and the test after `arrowHitsAlongSegmentWithinWidth`:
```swift
    /// A stroke is hit within half its width plus the tolerance of its smoothed path, with round
    /// caps, and not in the hollow of a curve. It has no handles, so a drag can only move it.
    @Test func strokeHitWithinWidth() {
        let level = pencil([CGPoint(x: 100, y: 100), CGPoint(x: 150, y: 100), CGPoint(x: 200, y: 100)])
        #expect(HitTester.handles(for: level).isEmpty)
        // Width 8: 3 px off the path is inside, 5 px is not until the tolerance reaches it.
        #expect(HitTester.hit(level, at: CGPoint(x: 150, y: 103), tolerance: 0) == .body)
        #expect(HitTester.hit(level, at: CGPoint(x: 150, y: 105), tolerance: 0) == nil)
        #expect(HitTester.hit(level, at: CGPoint(x: 150, y: 105), tolerance: 4) == .body)
        #expect(HitTester.hit(level, at: CGPoint(x: 150, y: 109), tolerance: 4) == nil)
        // The round cap reaches 4 px past the last point along the path.
        #expect(HitTester.hit(level, at: CGPoint(x: 203, y: 100), tolerance: 0) == .body)
        #expect(HitTester.hit(level, at: CGPoint(x: 206, y: 100), tolerance: 0) == nil)

        // The smoothed curve passes through its points; the space under the arch is not the body.
        let arch = pencil([CGPoint(x: 0, y: 0), CGPoint(x: 50, y: 50), CGPoint(x: 100, y: 0)])
        #expect(HitTester.hit(arch, at: CGPoint(x: 50, y: 50), tolerance: 0) == .body)
        #expect(HitTester.hit(arch, at: CGPoint(x: 50, y: 10), tolerance: 4) == nil)

        // A highlighter is hit the same way.
        let marker = Annotation.highlighter(Stroke(id: UUID(), points: [CGPoint(x: 0, y: 0), CGPoint(x: 40, y: 0), CGPoint(x: 80, y: 0)],
                                                   color: EditorPalette.defaultHighlight, lineWidth: 24))
        #expect(HitTester.hit(marker, at: CGPoint(x: 40, y: 11), tolerance: 0) == .body)
        #expect(HitTester.hit(marker, at: CGPoint(x: 40, y: 13), tolerance: 0) == nil)
    }
```

`TidyShotTests/ArrowGeometryTests.swift`: add after `boundsContainHead`:
```swift
    /// A stroke's bounds hold its path grown by half the width, plus the anti-alias margin; the
    /// selection outline is the same box without the margin.
    @Test func strokeBoundsIncludeWidthAndMargin() {
        let stroke = Stroke(id: UUID(), points: [CGPoint(x: 100, y: 100), CGPoint(x: 150, y: 100), CGPoint(x: 200, y: 100)],
                            color: EditorPalette.defaultStroke, lineWidth: 8)
        let outline = CGRect(x: 96, y: 96, width: 108, height: 8)
        #expect(AnnotationGeometry.strokeBounds(of: stroke) == outline)
        #expect(AnnotationGeometry.strokeOutline(of: .pencil(stroke)) == outline)
        #expect(AnnotationGeometry.bounds(of: .highlighter(stroke), scale: 2)
                == outline.insetBy(dx: -AnnotationGeometry.antialiasMargin, dy: -AnnotationGeometry.antialiasMargin))
        #expect(AnnotationGeometry.strokeOutline(of: .blur(Region(id: UUID(), rect: outline), radius: 16)) == nil)
    }
```

`TidyShotTests/EditorFlattenerTests.swift`: add after `arrowHeadPixelPresent`:
```swift
    /// A level pencil stroke along row 12 (width 4) covers rows 10 to 13 and nothing else. Row 12
    /// is far from the middle row, so a missing or doubled flip would move it to row 35.
    @Test func pencilStrokePixels() throws {
        let base = makeImage()
        let original = try Bitmap(base)
        let line = [CGPoint(x: 8, y: 12), CGPoint(x: 32, y: 12), CGPoint(x: 56, y: 12)]
        let pencil = Annotation.pencil(Stroke(id: UUID(), points: line, color: red, lineWidth: 4))
        let output = try Bitmap(flatten(base, [pencil]))
        for (x, y) in [(30, 10), (30, 11), (30, 12), (30, 13), (9, 11), (55, 12)] {
            #expect(output[x, y] == Self.redPixel, "stroke at \(x), \(y)")
        }
        for (x, y) in [(30, 9), (30, 14), (30, 35), (3, 12), (60, 12)] {
            #expect(output[x, y] == original[x, y], "untouched at \(x), \(y)")
        }
    }

    /// Multiply never lightens. The left half is black and the right half white: a normal blend of
    /// translucent yellow would lift the black to (115, 92, 0); multiply leaves it black and tints
    /// the white to yellow x 0.45 + white x 0.55, about (255, 232, 140). Outside the band nothing
    /// changes, and the tint is the same along the whole band.
    @Test func highlighterDarkensNeverLightens() throws {
        let base = makeImage { x, _ in x < 32 ? Self.blackPixel : [255, 255, 255, 255] }
        let original = try Bitmap(base)
        let line = [CGPoint(x: 8, y: 24), CGPoint(x: 32, y: 24), CGPoint(x: 56, y: 24)]
        let marker = Annotation.highlighter(Stroke(id: UUID(), points: line, color: EditorPalette.defaultHighlight,
                                                   lineWidth: 12))
        let output = try Bitmap(flatten(base, [marker]))

        var lighter: [String] = []
        for y in 0..<output.height {
            for x in 0..<output.width {
                for channel in 0..<4 where output[x, y][channel] > original[x, y][channel] {
                    lighter.append("\(x),\(y),\(channel)")
                }
            }
        }
        #expect(lighter.isEmpty, "lightened: \(lighter.prefix(5))")

        #expect(output[16, 24] == Self.blackPixel)
        let tinted = output[48, 24]
        #expect(tinted[0] == 255)
        #expect((230...234).contains(Int(tinted[1])), "green \(tinted[1])")
        #expect((138...142).contains(Int(tinted[2])), "blue \(tinted[2])")
        #expect(tinted[3] == 255)
        // The band is rows 18 to 29.
        #expect(output[48, 17] == original[48, 17])
        #expect(output[48, 30] == original[48, 30])
        #expect(output[48, 24] == output[48, 19])
    }
```

`TidyShotTests/CanvasToolTests.swift`: in `FakeCanvasEditing` add, after `made`:
```swift
    private(set) var strokes: [(tool: EditorTool, points: [CGPoint])] = []
```
and after `makeAnnotation`:
```swift
    func makeStroke(_ tool: EditorTool, points: [CGPoint]) -> Annotation? {
        strokes.append((tool: tool, points: points))
        guard points.count >= 2 else { return nil }
        let stroke = Stroke(id: transient?.id ?? UUID(), points: points, color: EditorPalette.defaultStroke, lineWidth: 8)
        switch tool {
        case .pencil: return .pencil(stroke)
        case .highlighter: return .highlighter(stroke)
        default: return nil
        }
    }
```
In `CanvasToolTests`, add the helper beside `segment(of:)`:
```swift
    func stroke(of annotation: Annotation?) -> Stroke? {
        switch annotation {
        case .pencil(let stroke)?, .highlighter(let stroke)?: stroke
        default: nil
        }
    }
```
and the tests after `tinyDragDiscarded`:
```swift
    /// The stroke grows in `transient` under one id, keeps the pointer as its last point, drops
    /// samples closer than 2 px (at 100 %), and commits once on mouseUp.
    @Test func pencilDragsOneStrokeAndCommitsOnMouseUp() throws {
        let canvas = FakeCanvasEditing()
        let tool = makeTool(for: .pencil)
        #expect(tool is PencilTool)

        tool.mouseDown(at(10, 10), on: canvas)
        #expect(canvas.transient == nil)
        tool.mouseDragged(at(20, 14), on: canvas)
        let first = try #require(stroke(of: canvas.transient))
        #expect(first.points == [CGPoint(x: 10, y: 10), CGPoint(x: 20, y: 14)])

        tool.mouseDragged(at(30, 18), on: canvas)
        tool.mouseDragged(at(30.5, 18.2), on: canvas)
        let near = try #require(stroke(of: canvas.transient))
        #expect(near.id == first.id)
        #expect(near.points.last == CGPoint(x: 30.5, y: 18.2))

        tool.mouseDragged(at(50, 12), on: canvas)
        #expect(canvas.commits.isEmpty)
        tool.mouseUp(at(50, 12), on: canvas)

        #expect(canvas.commits.count == 1)
        let commit = try #require(canvas.commits.first)
        #expect(commit.actionName == "Add Pencil")
        #expect(commit.coalescingKey == nil)
        let committed = try #require(canvas.document.annotations.last)
        #expect(commit.transient == committed)
        let result = try #require(stroke(of: committed))
        #expect(result.id == first.id)
        #expect(result.points == [CGPoint(x: 10, y: 10), CGPoint(x: 20, y: 14), CGPoint(x: 30, y: 18), CGPoint(x: 50, y: 12)])
        #expect(canvas.transient == nil)
        #expect(canvas.selection == committed.id)
        #expect(canvas.strokes.allSatisfy { $0.tool == .pencil })
    }

    /// A click and a 1 px jiggle leave nothing; Escape mid-stroke (the model clears `transient`)
    /// ends the gesture; a real drag with the Highlighter commits `Add Highlighter`.
    @Test func tinyOrCancelledStrokeLeavesNothing() throws {
        let canvas = FakeCanvasEditing()
        let tool = makeTool(for: .highlighter)

        tool.mouseDown(at(10, 10), on: canvas)
        tool.mouseUp(at(10, 10), on: canvas)
        #expect(canvas.commits.isEmpty)
        #expect(canvas.transient == nil)

        tool.mouseDown(at(10, 10), on: canvas)
        tool.mouseDragged(at(11, 10.5), on: canvas)
        #expect(canvas.transient == nil)
        tool.mouseUp(at(11, 10.5), on: canvas)
        #expect(canvas.commits.isEmpty)

        tool.mouseDown(at(10, 10), on: canvas)
        tool.mouseDragged(at(40, 10), on: canvas)
        #expect(canvas.transient != nil)
        canvas.transient = nil
        tool.mouseDragged(at(80, 10), on: canvas)
        #expect(canvas.transient == nil)
        tool.mouseUp(at(80, 10), on: canvas)
        #expect(canvas.commits.isEmpty)

        tool.mouseDown(at(10, 10), on: canvas)
        tool.mouseDragged(at(60, 10), on: canvas)
        tool.mouseUp(at(60, 10), on: canvas)
        #expect(canvas.commits.count == 1)
        #expect(canvas.commits.first?.actionName == "Add Highlighter")
        guard case .highlighter? = canvas.document.annotations.last else {
            Issue.record("no highlighter")
            return
        }
    }
```

`TidyShotTests/EditorModelTests.swift`: add after `makeAnnotationUsesToolSettingsInImagePixels`:
```swift
    /// The Pencil follows the stroke colour and line width; the Highlighter has its own colour at
    /// alpha 0.45 and its own 12 pt width, and the model's scale 2 turns points into pixels.
    @Test func strokeToolsKeepTheirOwnColourAndWidth() {
        let model = makeModel()
        let points = [CGPoint(x: 1, y: 1), CGPoint(x: 8, y: 5), CGPoint(x: 12, y: 9)]

        if case .pencil(let stroke)? = model.makeStroke(.pencil, points: points) {
            #expect(stroke.points == points)
            #expect(stroke.color == model.strokeColor)
            #expect(stroke.lineWidth == model.lineWidthPoints * 2)
        } else {
            Issue.record("no pencil stroke")
        }
        if case .highlighter(let stroke)? = model.makeStroke(.highlighter, points: points) {
            #expect(stroke.color == EditorPalette.defaultHighlight)
            #expect(stroke.color.alpha == 0.45)
            #expect(stroke.lineWidth == 12 * 2)
        } else {
            Issue.record("no highlighter stroke")
        }
        #expect(model.makeStroke(.pencil, points: [points[0]]) == nil)
        #expect(model.makeStroke(.rectangle, points: points) == nil)
        #expect(model.makeAnnotation(.pencil, from: points[0], to: points[2]) == nil)
        #expect(model.makeAnnotation(.highlighter, from: points[0], to: points[2]) == nil)

        // With the Highlighter active, colour and width go to the highlighter's own settings.
        model.tool = .highlighter
        model.applyColor(blue)
        #expect(model.highlightColor == RGBA(red: 0, green: 0, blue: 1, alpha: EditorPalette.highlighterAlpha))
        #expect(model.strokeColor == EditorPalette.defaultStroke)
        model.applyLineWidth(points: 8)
        #expect(model.highlightWidthPoints == 8)
        #expect(model.lineWidthPoints == EditorDefaults.standard.lineWidthPoints)
        #expect(model.activeLineWidthPoints == 8)
        model.tool = .pencil
        #expect(model.activeLineWidthPoints == EditorDefaults.standard.lineWidthPoints)

        // Select with a highlighter selected recolours it and keeps alpha 0.45.
        let marked = Annotation.highlighter(Stroke(id: UUID(), points: points, color: EditorPalette.defaultHighlight, lineWidth: 24))
        model.commit(model.document.appending(marked), actionName: "Add Highlighter")
        model.tool = .select
        model.selection = marked.id
        model.applyColor(red)
        #expect(model.document.annotation(id: marked.id)
                == Annotation.highlighter(Stroke(id: marked.id, points: points,
                                                 color: RGBA(red: 1, green: 0, blue: 0, alpha: 0.45), lineWidth: 24)))
        #expect(model.activeColor.alpha == 0.45)
    }
```

`TidyShotTests/AnnotationDocumentTests.swift`: add after `appendKeepsCreationOrder`:
```swift
    /// Strokes are drawings; they move by shifting every point, recolour (a highlighter keeps its
    /// alpha), change width, ignore effect parameters, and survive an encode and decode.
    @Test func strokesMoveRecolourAndRoundTrip() throws {
        let id = UUID()
        let points = [CGPoint(x: 0, y: 0), CGPoint(x: 10, y: 5), CGPoint(x: 20, y: 0)]
        let pencil = Annotation.pencil(Stroke(id: id, points: points, color: red, lineWidth: 6))
        let marker = Annotation.highlighter(Stroke(id: id, points: points, color: EditorPalette.defaultHighlight, lineWidth: 24))

        #expect(!pencil.isEffect)
        #expect(!marker.isEffect)
        #expect(pencil.effectRect == nil)
        #expect(pencil.id == id)
        #expect(pencil.title == "Pencil")
        #expect(marker.title == "Highlighter")

        let shifted = points.map { CGPoint(x: $0.x + 3, y: $0.y - 2) }
        #expect(pencil.moved(by: CGVector(dx: 3, dy: -2)) == .pencil(Stroke(id: id, points: shifted, color: red, lineWidth: 6)))
        #expect(pencil.withColor(blue) == .pencil(Stroke(id: id, points: points, color: blue, lineWidth: 6)))
        #expect(marker.withColor(blue)
                == .highlighter(Stroke(id: id, points: points, color: RGBA(red: 0, green: 0, blue: 1, alpha: 0.45), lineWidth: 24)))
        #expect(pencil.withLineWidth(12) == .pencil(Stroke(id: id, points: points, color: red, lineWidth: 12)))
        #expect(marker.withEffectParameter(9) == marker)

        let document = AnnotationDocument(annotations: [pencil, box(), marker.withColor(blue)])
        #expect(document.drawings.count == 3)
        let decoded = try JSONDecoder().decode(AnnotationDocument.self, from: JSONEncoder().encode(document))
        #expect(decoded == document)
    }
```
(The fixtures `box()` share `boxID`; the stroke fixtures use their own `id`, and `moving`/`replacing` are not used here, so the repeated stroke id in one document only matters for `decoded == document`, which holds.)

`TidyShotTests/EditorWindowGeometryTests.swift`: no new test. In Task 1's `toolbarWithEveryToolFitsASmallDisplay`, replace the two pinned lines with the ten-tool values (the six of 4a plus Ellipse, Line, Pencil and Highlighter: four segments of 36 pt more than 4a's 800):
```swift
        #expect(EditorTool.toolbarOrder.count == 10)
        #expect(width(segments: EditorTool.toolbarOrder.count) == 944)
```
The expected numbers use the `ToolbarMetrics` on `main` (`segment` 36, `itemGap` 10 for 7 items). `toolbarWidth` takes the segment count from `EditorTool.toolbarOrder.count` in `minimumToolbarContentWidth()` (EditorToolbar.swift:45), so no metric changes: the two new tools widen the toolbar by themselves. If Task 1 changed a `ToolbarMetrics` constant, recompute with the formula in `toolbarWidth` (`800 + 36 * (segments - 6)` on `main`'s constants) before running. Without this update the test fails on its `== 8` line once the two tools are in `toolbarOrder`.

- [ ] **Step 2: Run the tests and see them fail**

```bash
xcodegen generate && xcodebuild test -project TidyShot.xcodeproj -scheme TidyShot -destination 'platform=macOS' -derivedDataPath .build 2>&1 | grep -E "Test run with|error:|TEST"
```
Expected: the test target does not compile. `error:` lines say `cannot find 'Stroke' in scope`, `cannot find 'StrokeSmoothing' in scope`, `type 'EditorTool' has no member 'pencil'`, `cannot find 'PencilTool' in scope`, `has no member 'makeStroke'` and `has no member 'highlightColor'`. No `Test run with` line.

- [ ] **Step 3: Model: Stroke, the two Annotation cases, the tools and the palette**

`TidyShot/Editor/Model/RGBA.swift`: add after `cgColor`:
```swift
    /// The same colour at `alpha`.
    func withAlpha(_ alpha: Double) -> RGBA {
        RGBA(red: red, green: green, blue: blue, alpha: alpha)
    }
```

`TidyShot/Editor/Model/EditorPalette.swift`: add after `lineWidthsPoints`:
```swift
    /// A highlighter stroke's alpha. Any colour picked for the highlighter keeps it, so text stays
    /// readable under the multiply.
    static let highlighterAlpha: Double = 0.45
    /// The highlighter's colour until another is picked: the palette's yellow at `highlighterAlpha`.
    static let defaultHighlight = yellow.withAlpha(highlighterAlpha)
    /// The highlighter's width in points; also the last stop of `lineWidthsPoints`.
    static let highlighterWidthPoints: CGFloat = 12

    /// `color` at the highlighter's alpha.
    static func highlighterColor(from color: RGBA) -> RGBA {
        color.withAlpha(highlighterAlpha)
    }
```

`TidyShot/Editor/Model/Annotation.swift`:
1. After `Segment` (line 22) add:
```swift
/// A freehand stroke: Pencil and Highlighter. `points` are the pointer samples after
/// `StrokeSmoothing.decimated`, in image pixels. The smoothed curve is rebuilt from them each time
/// it is drawn or hit (`StrokeSmoothing.path(for:)`); no CGPath is stored.
nonisolated struct Stroke: Codable, Equatable, Sendable {
    let id: UUID
    var points: [CGPoint]
    var color: RGBA
    var lineWidth: CGFloat
}
```
2. In the `Annotation` enum add the cases beside Task 1's `ellipse` and `line`:
```swift
    /// Freehand in the stroke colour.
    case pencil(Stroke)
    /// Freehand in a translucent colour that multiplies with what is beneath it.
    case highlighter(Stroke)
```
3. `id`: `case .pencil(let stroke), .highlighter(let stroke): stroke.id`.
4. `isEffect` and `effectRect`: add `.pencil, .highlighter` to the drawings group (`false` and `nil`).
5. `title`: `case .pencil: "Pencil"` and `case .highlighter: "Highlighter"`.
6. `moved(by:)`:
```swift
        case .pencil(var stroke):
            stroke.points = stroke.points.map { CGPoint(x: $0.x + delta.dx, y: $0.y + delta.dy) }
            return .pencil(stroke)
        case .highlighter(var stroke):
            stroke.points = stroke.points.map { CGPoint(x: $0.x + delta.dx, y: $0.y + delta.dy) }
            return .highlighter(stroke)
```
7. `withColor(_:)` (and extend its doc: a highlighter keeps alpha 0.45):
```swift
        case .pencil(var stroke):
            stroke.color = color
            return .pencil(stroke)
        case .highlighter(var stroke):
            stroke.color = EditorPalette.highlighterColor(from: color)
            return .highlighter(stroke)
```
8. `withLineWidth(_:)`: `.pencil(var stroke)` and `.highlighter(var stroke)` set `stroke.lineWidth = width` and return the same case.
9. `withEffectParameter(_:)`: add `.pencil, .highlighter` to the unchanged group.

`TidyShot/Editor/Model/EditorTool.swift`: add `pencil, highlighter` after Task 1's `line` in the case list (line 4). Then:
- `letter`: `case .pencil: "P"`, `case .highlighter: "H"`.
- `title`: `"Pencil"`, `"Highlighter"`.
- `symbolName`: `"pencil"`, `"highlighter"`. `EditorToolTests.everyToolHasSymbolAndTooltipWithLetter` fails if either name is not a symbol on this SDK; if so use `"pencil.line"` or `"paintbrush.pointed"` for the highlighter.
- `isEffect`: add both to the `false` group.
- `toolbarOrder`: append `.pencil, .highlighter` after `.line`. Task 1's doc comment ("4b appends its tools here, in toolbar order.") stays true for Text and Crop.

The existing `EditorToolTests` need no change: `lettersAreUnique`, `toolForKeyIsCaseInsensitive`, `everyToolHasSymbolAndTooltipWithLetter` and `toolbarOrderCoversEveryToolOnce` iterate `allCases`, and the pinned `phase4a` list and Task 1's `[.ellipse, .line]` prefix check still hold.

- [ ] **Step 4: Stroke smoothing**

`TidyShot/Editor/Geometry/StrokeSmoothing.swift`:
```swift
import CoreGraphics

/// Freehand strokes: the pointer's samples are thinned when they are recorded, and the curve
/// through the thinned points is rebuilt from them whenever it is drawn or hit. All points are
/// image pixels.
nonisolated enum StrokeSmoothing {
    /// The spacing the tool keeps between recorded points, in view points. The tool divides it by
    /// the zoom, so a stroke made zoomed in is finer in the image.
    static let spacingPoints: CGFloat = 2
    /// Samples the curve gets between each pair of neighbouring points.
    static let segmentsPerSpan = 8

    /// `points` without those closer than `minDistance` to the last point kept, measured from that
    /// point and not from the previous sample, so a slow drift still adds points. The first and the
    /// last sample are always kept, so the stroke starts and ends where the pointer did.
    static func decimated(_ points: [CGPoint], minDistance: CGFloat) -> [CGPoint] {
        guard var last = points.first else { return [] }
        var kept = [last]
        for point in points.dropFirst() {
            if hypot(point.x - last.x, point.y - last.y) >= minDistance {
                kept.append(point)
                last = point
            }
        }
        if let end = points.last, end != last { kept.append(end) }
        return kept
    }

    /// A uniform Catmull-Rom curve through `points`: the first point, then `segmentsPerSpan`
    /// samples for each span, the last of which is the span's end point itself, so the curve passes
    /// through every point and ends exactly on the last. The first and last points are repeated as
    /// their own neighbours. Fewer than three points come back unchanged.
    static func catmullRom(_ points: [CGPoint]) -> [CGPoint] {
        guard points.count > 2 else { return points }
        var curve = [points[0]]
        curve.reserveCapacity(1 + (points.count - 1) * segmentsPerSpan)
        for index in 0..<(points.count - 1) {
            let p0 = points[max(index - 1, 0)]
            let p1 = points[index]
            let p2 = points[index + 1]
            let p3 = points[min(index + 2, points.count - 1)]
            for step in 1..<segmentsPerSpan {
                let t = CGFloat(step) / CGFloat(segmentsPerSpan)
                curve.append(CGPoint(x: spline(p0.x, p1.x, p2.x, p3.x, t), y: spline(p0.y, p1.y, p2.y, p3.y, t)))
            }
            // t = 1 is p2; appending it avoids a rounding error on the stroke's last point.
            curve.append(p2)
        }
        return curve
    }

    /// The smoothed curve as a path of straight pieces. Built on each call and never stored. One
    /// point gives a zero-length piece, which a round cap draws as a dot.
    static func path(for points: [CGPoint]) -> CGPath {
        let path = CGMutablePath()
        let curve = catmullRom(points)
        guard let first = curve.first else { return path }
        if curve.count == 1 {
            path.move(to: first)
            path.addLine(to: first)
        } else {
            path.addLines(between: curve)
        }
        return path
    }

    /// One coordinate of the uniform Catmull-Rom spline between `b` and `c` at `t` in 0...1.
    private static func spline(_ a: CGFloat, _ b: CGFloat, _ c: CGFloat, _ d: CGFloat, _ t: CGFloat) -> CGFloat {
        let t2 = t * t
        let t3 = t2 * t
        return 0.5 * (2 * b + (c - a) * t + (2 * a - 5 * b + 4 * c - d) * t2 + (3 * b - a - 3 * c + d) * t3)
    }
}
```

- [ ] **Step 5: Hit testing and bounds**

`TidyShot/Editor/Geometry/ArrowGeometry.swift`, in `AnnotationGeometry`:
- In `bounds(of:scale:)` (line 53) add, beside the other cases:
```swift
        case .pencil(let stroke), .highlighter(let stroke):
            painted = strokeBounds(of: stroke)
```
- Add after `bounds(of:scale:)`:
```swift
    /// A stroke's smoothed path grown by half its width. The path is built here and dropped.
    /// Catmull-Rom can overshoot its points a little, so the bounds come from the curve, not from
    /// the points.
    static func strokeBounds(of stroke: Stroke) -> CGRect {
        guard !stroke.points.isEmpty else { return .null }
        let box = StrokeSmoothing.path(for: stroke.points).boundingBoxOfPath
        return box.insetBy(dx: -stroke.lineWidth / 2, dy: -stroke.lineWidth / 2)
    }

    /// The box the selection outline draws around a stroke; nil for every other annotation.
    static func strokeOutline(of annotation: Annotation) -> CGRect? {
        switch annotation {
        case .pencil(let stroke), .highlighter(let stroke): strokeBounds(of: stroke)
        default: nil
        }
    }
```

`TidyShot/Editor/Geometry/HitTester.swift`:
- `handles(for:)` (line 26): `case .pencil, .highlighter: []`, and add to the doc comment: "A stroke has none: it moves and does not resize."
- `resized(_:handle:to:square:)` (line 64): `case .pencil, .highlighter: return annotation`.
- `bodyContains` (line 145): add `case .pencil(let stroke), .highlighter(let stroke): return strokeContains(stroke, point, tolerance: tolerance)`, and extend its doc comment with "A stroke's body is its smoothed path stroked at its width plus the tolerance on each side."
- Add after `distance(from:toSegment:_:)`:
```swift
    /// Whether `point` lies on `stroke`: the smoothed path stroked at the line width plus the
    /// tolerance on each side, with round caps and joins, tested for containment. The path and its
    /// outline are built here and dropped. A point outside the path's bounds grown by the same
    /// reach is refused before the outline is made.
    static func strokeContains(_ stroke: Stroke, _ point: CGPoint, tolerance: CGFloat) -> Bool {
        guard !stroke.points.isEmpty else { return false }
        let reach = stroke.lineWidth / 2 + tolerance
        let path = StrokeSmoothing.path(for: stroke.points)
        guard path.boundingBoxOfPath.insetBy(dx: -reach, dy: -reach).contains(point) else { return false }
        let outline = path.copy(strokingWithWidth: 2 * reach, lineCap: .round, lineJoin: .round, miterLimit: 1)
        return outline.contains(point)
    }
```

- [ ] **Step 6: Drawing**

`TidyShot/Editor/Rendering/AnnotationDrawing.swift`:
- In `draw(_:in:scale:)` (line 16) add:
```swift
        case .pencil(let stroke):
            drawStroke(stroke, blend: .normal, in: context)
        case .highlighter(let stroke):
            drawStroke(stroke, blend: .multiply, in: context)
```
- In `drawSelection` (line 56) change `if let rect = annotation.effectRect {` to `if let rect = annotation.effectRect ?? AnnotationGeometry.strokeOutline(of: annotation) {`, and say in its doc comment that a selected stroke gets the same dashed outline (it has no handles). `viewRect` and the snapping apply unchanged.
- Add after `drawArrow`:
```swift
    /// The smoothed path stroked once with round caps and joins. A single stroke operation paints
    /// the stroked outline as one shape, so a translucent highlighter that crosses itself is not
    /// painted twice. `.multiply` multiplies the colour with what is already in the context, so
    /// the highlighter can only darken: black stays black, white becomes the colour. The flattener
    /// draws into the capture's bitmap, where that is exactly what multiplies.
    private static func drawStroke(_ stroke: Stroke, blend: CGBlendMode, in context: CGContext) {
        guard !stroke.points.isEmpty, stroke.lineWidth > 0 else { return }
        context.saveGState()
        defer { context.restoreGState() }
        context.setBlendMode(blend)
        context.setStrokeColor(stroke.color.cgColor)
        context.setLineWidth(stroke.lineWidth)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        context.addPath(StrokeSmoothing.path(for: stroke.points))
        context.strokePath()
    }
```

- [ ] **Step 7: The tool, the factory and the model**

`TidyShot/Editor/Tools/CanvasTool.swift`: add to `CanvasEditing` after `makeAnnotation` (line 31), with this doc comment:
```swift
    /// Builds the freehand stroke for Pencil or Highlighter from the decimated points with the
    /// current colour and width, reusing the transient's id. Nil for fewer than two points and for
    /// any other tool.
    func makeStroke(_ tool: EditorTool, points: [CGPoint]) -> Annotation?
```

`TidyShot/Editor/Tools/PencilTool.swift`:
```swift
import AppKit

/// Pencil and Highlighter: a freehand stroke. Every pointer sample is kept in `raw`; after each
/// event the stroke in `canvas.transient` is rebuilt from `StrokeSmoothing.decimated(raw, ...)`, so
/// the same samples always give the same points, and the last point is always the pointer. The
/// spacing is `spacingPoints / zoom` image pixels. The model keeps the transient's id across
/// rebuilds. mouseUp commits once through `commitNewShape` and selects the stroke. A stroke whose
/// points all lie within the tiny-drag distance of the first leaves nothing, and Escape (which
/// clears `canvas.transient`) ends the gesture, as in the other creation tools. Modifier keys do
/// nothing. Recomputing from `raw` is quadratic in the samples of one stroke, which stays far
/// below a millisecond for a stroke of a few thousand.
final class PencilTool: CanvasTool {
    let tool: EditorTool
    /// Every sample of the gesture in image pixels; empty when none runs.
    private var raw: [CGPoint] = []
    private var isDrawing = false
    /// The points behind `shown`, so an event that changes nothing keeps the same annotation.
    private var shownPoints: [CGPoint]?
    /// What this tool last put in `canvas.transient`. Anything else there means the gesture was
    /// cancelled, and the tool drops it.
    private var shown: Annotation?

    init(tool: EditorTool) {
        self.tool = tool
    }

    var cursor: NSCursor { .crosshair }

    func mouseDown(_ input: ToolInput, on canvas: any CanvasEditing) {
        raw = [input.point]
        isDrawing = true
        shownPoints = nil
        shown = nil
        canvas.transient = nil
    }

    func mouseDragged(_ input: ToolInput, on canvas: any CanvasEditing) {
        guard isDrawing else { return }
        raw.append(input.point)
        update(on: canvas)
    }

    func flagsChanged(_ input: ToolInput, on canvas: any CanvasEditing) {}

    func mouseUp(_ input: ToolInput, on canvas: any CanvasEditing) {
        guard isDrawing else { return }
        raw.append(input.point)
        update(on: canvas)
        let stroke = shown
        reset()
        if let stroke {
            canvas.commitNewShape(stroke)
        }
    }

    private func update(on canvas: any CanvasEditing) {
        guard canvas.transient == shown else {
            reset()
            return
        }
        let points = StrokeSmoothing.decimated(raw, minDistance: StrokeSmoothing.spacingPoints / canvas.zoom)
        guard points != shownPoints else { return }
        shownPoints = points
        shown = isLongEnough(points, zoom: canvas.zoom) ? canvas.makeStroke(tool, points: points) : nil
        canvas.transient = shown
    }

    /// Some point at least the tiny-drag distance from the first, so a loop that returns to its
    /// start still counts.
    private func isLongEnough(_ points: [CGPoint], zoom: CGFloat) -> Bool {
        guard let first = points.first else { return false }
        return points.dropFirst().contains { DragGeometry.isLongEnough(from: first, to: $0, zoom: zoom) }
    }

    private func reset() {
        raw = []
        isDrawing = false
        shownPoints = nil
        shown = nil
    }
}
```

`TidyShot/Editor/Tools/ToolFactory.swift`: add `case .pencil, .highlighter: return PencilTool(tool: tool)` to the switch (beside Task 1's `.ellipse` and `.line`). Task 1 already rewrote the doc comment without the "4b adds ..." sentence, so it stays as Task 1 left it.

`TidyShot/Editor/Session/EditorModel.swift`:
- Properties, beside `strokeColor` and `lineWidthPoints`:
```swift
    /// The Highlighter's own colour and width (the Pencil uses `strokeColor` and `lineWidthPoints`).
    /// Not persisted: every editor starts from yellow at alpha 0.45 and 12 pt.
    var highlightColor = EditorPalette.defaultHighlight
    var highlightWidthPoints = EditorPalette.highlighterWidthPoints
```
- `makeAnnotation` (line 132): add `case .pencil, .highlighter: return nil` with the comment "Strokes come from `makeStroke`." Add after `makeAnnotation`:
```swift
    func makeStroke(_ tool: EditorTool, points: [CGPoint]) -> Annotation? {
        guard points.count >= 2 else { return nil }
        let id = transient?.id ?? UUID()
        switch tool {
        case .pencil:
            return .pencil(Stroke(id: id, points: points, color: strokeColor, lineWidth: lineWidthPoints * scale))
        case .highlighter:
            return .highlighter(Stroke(id: id, points: points, color: highlightColor, lineWidth: highlightWidthPoints * scale))
        default:
            return nil  // No other tool draws freehand; this switch needs no case per tool.
        }
    }
```
- Beside `editsRedactColor` (line 202) add:
```swift
    /// The Highlighter, or Select with a highlighter selected, edits the highlight colour and
    /// width; the same rule as `editsRedactColor`.
    private var editsHighlighter: Bool {
        if tool == .highlighter { return true }
        guard tool == .select, case .highlighter? = selectedAnnotation else { return false }
        return true
    }

    /// The width the line-width control shows: the highlighter's while it is being edited.
    var activeLineWidthPoints: CGFloat {
        editsHighlighter ? highlightWidthPoints : lineWidthPoints
    }
```
- `activeColor` (line 197): `Self.color(of: selectedAnnotation) ?? (editsRedactColor ? redactColor : editsHighlighter ? highlightColor : strokeColor)`.
- `applyColor` (line 208): replace the first line with
```swift
        if editsRedactColor {
            redactColor = color
        } else if editsHighlighter {
            highlightColor = EditorPalette.highlighterColor(from: color)
        } else {
            strokeColor = color
        }
```
- `applyLineWidth` (line 215): replace `lineWidthPoints = points` with `if editsHighlighter { highlightWidthPoints = points } else { lineWidthPoints = points }`.
- `color(of:)` (line 244): add `case .pencil(let stroke)?, .highlighter(let stroke)?: return stroke.color`.

`TidyShot/Editor/Window/ToolOptionsView.swift` (line 60): the `lineWidth` binding reads `model.activeLineWidthPoints`, so the segmented control shows 12 for the highlighter. Add a sentence to the type's doc comment: "While the Highlighter is in play the width control edits the highlighter's width."

`TidyShot/Editor/Window/ColorPaletteView.swift`: line 26 becomes `let isCurrent = model.activeColor.withAlpha(1) == swatch`, so the yellow swatch shows as current for the translucent highlighter; line 45's getter returns `model.activeColor.withAlpha(1).cgColor` (the picker has no opacity).

`TidyShot/Editor/Window/EditorToolbar.swift`: no code change. The tools group is built from `EditorTool.toolbarOrder` (`makeToolsItem`) and the window's minimum width from `EditorTool.toolbarOrder.count` (line 45), so the two new segments, their tooltips `Pencil (P)` and `Highlighter (H)`, and the 944 pt minimum come from the enum. Update the comment at line 36 from "the six tool segments" to "one tool segment per `EditorTool.toolbarOrder` entry".

- [ ] **Step 8: Preview the highlighter with a backdrop**

`TidyShot/Editor/Window/CanvasView.swift`. The capture and the tiles are layers of `BaseImageView`, not pixels of this view's backing store. A multiply drawn here would multiply against nothing and show as plain translucent yellow, which lightens dark text where the export darkens it. So `draw(_:)` first fills each visible highlighter's stroked area with a copy of what lies beneath, then draws as before. In `draw(_:)` (line 382), call the new method right after `context.concatenate(transform.affine)` (line 387) and before the placeholders:
```swift
        drawHighlighterBackdrops(in: context, visible: visible)
```
Add to the `// MARK: Drawing` section:
```swift
    /// For each highlighter meeting `visible` (including the one in progress): clip to its stroked
    /// outline, then draw the capture and the shown effect tiles into that clip. The copy equals
    /// what `baseView` shows there, so the picture does not change, and the multiply that follows
    /// in `AnnotationDrawing.draw` has real pixels to multiply. Runs before every other drawing, so
    /// shapes made before the highlighter lie under it and shapes made after lie over it, as in the
    /// export. The CTM is image pixels, top-left origin. Interpolation follows `BaseImageView`:
    /// nearest from 2 device pixels per image pixel up.
    private func drawHighlighterBackdrops(in context: CGContext, visible: CGRect) {
        let strokes = displayedDrawings.compactMap { drawing -> Stroke? in
            if case .highlighter(let stroke) = drawing { stroke } else { nil }
        }.filter { AnnotationGeometry.strokeBounds(of: $0).intersects(visible) }
        guard !strokes.isEmpty else { return }
        let nearest = model.transform.zoom * backingScale >= 2
        for stroke in strokes {
            context.saveGState()
            context.addPath(StrokeSmoothing.path(for: stroke.points))
            context.setLineWidth(stroke.lineWidth)
            context.setLineCap(.round)
            context.setLineJoin(.round)
            context.replacePathWithStrokedPath()
            context.clip()
            context.interpolationQuality = nearest ? .none : .high
            drawFlipped(model.base, in: CGRect(origin: .zero, size: imagePixelSize), context: context)
            for effect in displayedEffects {
                if let tile = shownTile(for: effect) { drawFlipped(tile.image, in: tile.rect, context: context) }
            }
            context.restoreGState()
        }
    }

    /// `CGContext.draw` assumes a y-up space and the CTM here is y-down, so the image is drawn
    /// through a local flip about `rect`; without it the copy would be upside down.
    private func drawFlipped(_ image: CGImage, in rect: CGRect, context: CGContext) {
        context.saveGState()
        context.translateBy(x: rect.minX, y: rect.maxY)
        context.scaleBy(x: 1, y: -1)
        context.draw(image, in: CGRect(x: 0, y: 0, width: rect.width, height: rect.height))
        context.restoreGState()
    }
```
Nothing else in `CanvasView` changes: `imageBounds(of:)` already goes through `AnnotationGeometry.bounds`, which now covers strokes, so the repaint rects for a stroke in progress include its width. If the `compactMap` closure with `if case ... { stroke } else { nil }` does not compile as an expression, write it with `switch` and explicit `return`s.

- [ ] **Step 9: Run the full suite**

```bash
xcodegen generate && xcodebuild test -project TidyShot.xcodeproj -scheme TidyShot -destination 'platform=macOS' -derivedDataPath .build 2>&1 | grep -E "Test run with|error:|TEST"
```
Expected: no `error:` lines, and `Test run with 430 tests in 53 suites passed`. This task adds 10 tests (`decimationDropsClosePoints`, `smoothingKeepsEndpoints`, `strokeHitWithinWidth`, `strokeBoundsIncludeWidthAndMargin`, `pencilStrokePixels`, `highlighterDarkensNeverLightens`, `pencilDragsOneStrokeAndCommitsOnMouseUp`, `tinyOrCancelledStrokeLeavesNothing`, `strokeToolsKeepTheirOwnColourAndWidth`, `strokesMoveRecolourAndRoundTrip`) and 1 suite (`StrokeSmoothingTests`); the toolbar width change edits Task 1's test.

If `highlighterDarkensNeverLightens` fails on the tinted pixel, print the pixel before widening the range: the multiply is `D x (0.55 + 0.45 x colour)`, so green is 232 and blue 140 on white.

- [ ] **Step 10: Hand checks**

Run the app, open an editor from Recent Captures, and use a capture that has dark text on a light background.
- The toolbar shows ten tools, ending Pencil then Highlighter, with the tooltips `Pencil (P)` and `Highlighter (H)`. Drag the window to its minimum width: every item still shows and there is no overflow chevron. Keys P and H pick the tools and the toolbar follows.
- Pencil: drag a loop; the line is smooth with no corners at the samples, round at both ends, in the stroke colour and the chosen width (keys 1 to 6). One drag is one undo step named `Add Pencil` in Edit; undo removes it whole and redo restores it. A click, or a drag under 2 pt, leaves nothing. Escape mid-drag leaves nothing and the window stays open.
- Highlighter: drag across a line of text. The text stays dark and readable under a yellow tint. Cross the stroke over itself: the crossing is not darker. Pick another colour from the palette: the stroke stays translucent, the yellow swatch ring is shown for the default. Key 6 is 12 pt, the default.
- Preview equals export: with a highlighter over text and a pencil line over it, press Copy, paste into Preview, and compare with the canvas. Colours and the darkened text match. Repeat at 37 % zoom: no visible seam or sharper patch inside the highlighted area.
- Order: draw a rectangle, then a highlighter across its edge: the highlighter tints the rectangle's red. Draw a highlighter, then a rectangle across it: the rectangle's red is unchanged where they meet. A highlighter over a blurred or redacted area leaves the redaction opaque.
- Select: with the Select tool, click within 8 pt of a stroke (not in the hollow of a loop) and it selects with a dashed outline and no handles; drag moves it as one `Move Pencil` step (Shift locks the axis); arrow keys nudge it; Delete removes it. Changing colour or width with it selected edits it as one `Color` or `Line Width` step.
- A stroke made on a very large capture (5000 px wide) at fit zoom follows the pointer without lag, both Pencil and Highlighter.

- [ ] **Step 11: Commit**

```bash
git add TidyShot/Editor/Geometry/StrokeSmoothing.swift TidyShot/Editor/Tools/PencilTool.swift TidyShot/Editor/Geometry/HitTester.swift TidyShot/Editor/Geometry/ArrowGeometry.swift TidyShot/Editor/Model/Annotation.swift TidyShot/Editor/Model/EditorTool.swift TidyShot/Editor/Model/EditorPalette.swift TidyShot/Editor/Model/RGBA.swift TidyShot/Editor/Rendering/AnnotationDrawing.swift TidyShot/Editor/Session/EditorModel.swift TidyShot/Editor/Tools/CanvasTool.swift TidyShot/Editor/Tools/ToolFactory.swift TidyShot/Editor/Window/CanvasView.swift TidyShot/Editor/Window/ColorPaletteView.swift TidyShot/Editor/Window/ToolOptionsView.swift TidyShot/Editor/Window/EditorToolbar.swift TidyShotTests/StrokeSmoothingTests.swift TidyShotTests/HitTesterTests.swift TidyShotTests/ArrowGeometryTests.swift TidyShotTests/EditorFlattenerTests.swift TidyShotTests/CanvasToolTests.swift TidyShotTests/EditorModelTests.swift TidyShotTests/AnnotationDocumentTests.swift TidyShotTests/EditorWindowGeometryTests.swift
git commit -m "feat: pencil and highlighter"
```

### Task 3: Text tool

**Files:**
- Create: `TidyShot/Editor/Geometry/TextLayout.swift`
- Create: `TidyShot/Editor/Tools/TextTool.swift`
- Modify: `TidyShot/Editor/Model/Annotation.swift` (`TextBox`, `.text`, `withFontSize`)
- Modify: `TidyShot/Editor/Model/EditorTool.swift` (`.text`, letter T)
- Modify: `TidyShot/Editor/Model/EditorPalette.swift` (text sizes)
- Modify: `TidyShot/Editor/Geometry/KeyRouting.swift` (`.textSize`, the `tool:` parameter, `TextEditingChord`)
- Modify: `TidyShot/Editor/Geometry/HitTester.swift` and `TidyShot/Editor/Geometry/ArrowGeometry.swift` (`AnnotationGeometry.bounds`)
- Modify: `TidyShot/Editor/Rendering/AnnotationDrawing.swift` (CoreText drawing, text selection outline)
- Modify: `TidyShot/Editor/Session/EditorModel.swift` (text editing state, commit, cancel, text size)
- Modify: `TidyShot/Editor/Tools/CanvasTool.swift`, `TidyShot/Editor/Tools/ToolFactory.swift`, `TidyShot/Editor/Tools/SelectTool.swift` (double-click re-edits)
- Modify: `TidyShot/Editor/Window/CanvasView.swift` (the NSTextView and its delegate)
- Modify: `TidyShot/Editor/Window/EditorWindow.swift` (text chords while typing)
- Modify: `TidyShot/Editor/Window/EditorWindowController.swift` and `TidyShot/Editor/Window/EditorToolbar.swift` (commit before Save, Upload, Close and Zoom)
- Test: `TidyShotTests/TextLayoutTests.swift` (create)
- Test: `TidyShotTests/EditorFlattenerTests.swift`, `TidyShotTests/KeyRoutingTests.swift`, `TidyShotTests/EditorModelTests.swift`, `TidyShotTests/CanvasToolTests.swift`, `TidyShotTests/EditorWindowGeometryTests.swift` (modify)

Line numbers below are those on `main` (9193586). Tasks 1 and 2 have since added arms for `ellipse`, `line`, `pencil` and `highlighter` to the same switches; add the `text` arm next to theirs.

**Why the layout is specified to the pixel.** Committed text is drawn by `AnnotationDrawing`, which the canvas and the flattener share, so the committed preview equals the export by construction. The text being typed is an NSTextView, and it must put every glyph where CoreText will put it, or the text jumps on Return. Measured on macOS 27 (Xcode 27.1 SDK) with the bold system font, an NSTextView set up as in Step 9 and `TextLayout` + `AnnotationDrawing.drawText` below give identical pixels at 25 %, 33 %, 37 %, 50 %, 100 %, 125 %, 200 % and 400 % zoom, for 12 to 56 px text with empty lines. Two choices make that true, and both are load-bearing:
1. The text view's bounds stay in image pixels and only its frame is zoomed, so TextKit lays out at the model's `fontSize`. Setting the font to `fontSize * zoom` instead picks other optical-size tracking for the system font and the widths drift by up to 8 %.
2. TextKit 2 puts the baseline of a fixed-height line `round(descent)` above the line's bottom, not `ascent` below its top. `TextLayout.baselineOffset` uses the same rule. TextKit 1 lays out differently, so the view is made with `NSTextView(usingTextLayoutManager: true)` and its `layoutManager` property is never read (reading it switches the view to TextKit 1).

Each line is drawn with `CTLineDraw` at the baseline TextLayout gives, rather than with a `CTFramesetter` and `CTFrameDraw` as the synthesized entry said: a framesetter wraps at the path width, drops the empty line after a trailing newline that the text view shows, and places baselines by its own rule. Lines split only at newlines, so the frame grows with the text and nothing wraps.

**Interfaces:**
- Consumes:
  - From `main`: `protocol CanvasEditing` (CanvasTool.swift:21-32) and `extension CanvasEditing { func commitNewShape(_ shape: Annotation) }` (ToolFactory.swift:14-23); `HitTester.tolerance(zoom:)`, `HitTester.topmost(in:at:tolerance:) -> (id: UUID, hit: Hit)?`; `DragGeometry.isLongEnough(from:to:zoom:) -> Bool`; `CanvasTransform.viewPoint(_:)` and `zoom`; `EditorModel.commit(_:actionName:coalescingKey:)`, `EditorModel.ActionName.delete`; `EditorShortcut.match(characters:command:shift:option:control:isEditingText:)` with `passesThroughWhileEditingText`, which `EditorWindow` already calls with `canvasView?.isEditingText` (EditorWindow.swift:22-25); `ShortcutItem(action:)`; `EditorFlattener.flatten(base:tiles:document:scale:)`; `EditorWindowGeometry.toolbarWidth(...)` and `ToolbarMetrics.segment`.
  - From Tasks 1 and 2: `EditorTool.ellipse`, `.line`, `.pencil`, `.highlighter` in `allCases` and `toolbarOrder` (ten tools), and the `Annotation` cases `ellipse`, `line`, `pencil`, `highlighter`. This task appends `.text` after them.
- Produces:
  - `nonisolated struct TextBox: Codable, Equatable, Sendable { let id: UUID; var string: String; var origin: CGPoint; var fontSize: CGFloat; var color: RGBA }`, all in image pixels; `origin` is the top-left of `TextLayout.frame(for:)`.
  - `Annotation.text(TextBox)` (title `Text`, a drawing, not an effect) and `Annotation.withFontSize(_ size: CGFloat) -> Annotation`.
  - `EditorTool.text`: letter `T`, title `Text`, symbol `textformat`, last in `toolbarOrder` (Task 4 appends `.crop` after it); `makeTool(for: .text)` returns `TextTool`.
  - `EditorPalette.textSizesPoints: [CGFloat] = [12, 16, 20, 28, 40, 56]`, `EditorPalette.defaultTextSizePoints: CGFloat = 20`.
  - `nonisolated enum TextLayout` with `font(size:) -> CTFont`, `padding(fontSize:) -> CGFloat`, `lineHeight(fontSize:) -> CGFloat`, `baselineOffset(fontSize:) -> CGFloat`, `lines(of:) -> [String]`, `line(_:font:color:) -> CTLine`, `width(of:font:) -> CGFloat`, `frame(for: TextBox) -> CGRect`, `baselineOrigins(for: TextBox) -> [CGPoint]`, `origin(forClickAt:fontSize:) -> CGPoint`, `committedString(_:) -> String?`.
  - `KeyRouting.Action.textSize(index: Int)` and `KeyRouting.action(characters:command:control:option:isEditingText:tool:)`, with `tool: EditorTool = .select`.
  - `nonisolated enum TextEditingChord { static func selectorName(characters: String, command: Bool, shift: Bool, option: Bool, control: Bool) -> String? }`: ⌘C `copy:`, ⌘X `cut:`, ⌘V `paste:`, ⌘A `selectAll:`, ⌘Z `undo:`, ⇧⌘Z `redo:`.
  - `CanvasEditing.beginTextEditing(at point: CGPoint, existing id: UUID?)`.
  - `nonisolated struct TextEditing: Equatable, Sendable { var box: TextBox; let original: TextBox? }` (EditorModel.swift).
  - On `EditorModel`: `private(set) var textEditing: TextEditing?`, `var isEditingText: Bool`, `@ObservationIgnored private(set) var textUndoManager: UndoManager?`, `var textSizePoints: CGFloat`, `func beginTextEditing(at:existing:)`, `func updateEditingText(_ string: String)`, `func commitTextEditing()`, `func cancelTextEditing()`, `func applyTextSize(points: CGFloat)`, `ActionName.editText = "Edit Text"`, `ActionName.textSize = "Text Size"`. `hasUnsavedChanges` is also true while typed text would change the document.
  - On `CanvasView`: `var isEditingText: Bool { get }` (now computed from the model), `func commitTextEditing()` (ends the edit and removes the text view at once), and `NSTextViewDelegate` conformance whose `undoManager(for:)` returns the edit's own manager.
  - Undo names: `Add Text`, `Edit Text`, `Delete` (a re-edit cleared to blank), `Text Size`, plus the Select tool's `Move Text`.
  - For Task 5: the text being typed lives in `model.textEditing`, not in the document, and is hidden from `CanvasView.displayedDrawings`; object duplicate, copy and paste must handle `.text` (a new `TextBox` id). While typing, ⌘V and ⌘D match nothing in `EditorShortcut`; `EditorWindow` then sends ⌘V to the text view as `paste:` through `TextEditingChord`, and ⌘D falls through to `super`.

Behaviour (spec 2.6, Phase 4b):
- With Text (T), a click places a box whose first line is centred on the pointer, in the stroke colour at the current text size (20 pt by default, times the capture scale). A click on an existing text annotation edits it again. A drag places nothing. With Select (V), a double-click on a text edits it again.
- Return, Enter and Tab commit; Shift-Return and ⌥Return insert a newline; Escape and ⌘. cancel. A click on the canvas outside the text view commits, and that click does nothing else. Changing the tool commits. Save, Save As…, Copy (the toolbar button and ⇧⌘C), Upload, Upload as New, Close, the close sheet, and the zoom commands and pop-up commit first.
- Committing is one editor commit: `Add Text` for a new box, `Edit Text` for a re-edit (in place, so the creation order is kept), `Delete` for a re-edit cleared to blank, and nothing for a new box left blank. Trailing newlines are dropped. Cancel leaves the document as it was.
- While typing, every unmodified key belongs to the text view, and ⌘C, ⌘X, ⌘V, ⌘A, ⌘Z and ⇧⌘Z act on the text. Typing registers undo only in the edit's own UndoManager, which is emptied and dropped when the edit ends, so the editor's `groupsByEvent = false` manager sees exactly one step per edit.
- Digits 1 to 6 with the Text tool active pick 12, 16, 20, 28, 40 or 56 pt, for new text and, as one coalesced step, for the selected text. Other tools keep the line widths.
- Text has no handles; a selected text shows the dashed outline effects use, around its frame. Its body is the whole frame grown by the hit tolerance.

- [ ] **Step 1: Write the failing tests**

Create `TidyShotTests/TextLayoutTests.swift`:
```swift
import CoreGraphics
import CoreText
import Foundation
import Testing
@testable import TidyShot

/// Text geometry in image pixels (spec 2.6, Phase 4b). The metrics come from the system font, so
/// the expectations are written in TextLayout's own terms rather than in fixed numbers.
struct TextLayoutTests {
    func box(_ string: String, size: CGFloat = 40) -> TextBox {
        TextBox(id: UUID(), string: string, origin: CGPoint(x: 10, y: 20), fontSize: size,
                color: RGBA(red: 1, green: 0, blue: 0))
    }

    @Test func textFrameGrowsWithLines() {
        let font = TextLayout.font(size: 40)
        let lineHeight = TextLayout.lineHeight(fontSize: 40)
        let padding = TextLayout.padding(fontSize: 40)
        #expect(padding == 10)
        #expect(TextLayout.padding(fontSize: 13) == 4)
        #expect(lineHeight > 40)
        // The line height scales with the size, so text looks the same at every capture scale.
        #expect(abs(lineHeight - 2 * TextLayout.lineHeight(fontSize: 20)) < 0.001)

        let one = TextLayout.frame(for: box("Hi"))
        #expect(one == CGRect(x: 10, y: 20, width: TextLayout.width(of: "Hi", font: font) + 2 * padding,
                              height: lineHeight + 2 * padding))
        let two = TextLayout.frame(for: box("Hi\nthere"))
        #expect(two.origin == one.origin)
        #expect(two.height == 2 * lineHeight + 2 * padding)
        #expect(two.width == TextLayout.width(of: "there", font: font) + 2 * padding)
        #expect(two.width > one.width)
        // Empty lines count, the one after a trailing newline too, as in the text view.
        let trailing = TextLayout.frame(for: box("Hi\n\n"))
        #expect(trailing.height == 3 * lineHeight + 2 * padding)
        #expect(trailing.width == one.width)
        // An empty box still has one line, so the caret has somewhere to go.
        #expect(TextLayout.frame(for: box("")) == CGRect(x: 10, y: 20, width: 2 * padding, height: lineHeight + 2 * padding))
        // Every kind of line break the text view accepts splits a line; nothing wraps.
        #expect(TextLayout.lines(of: "a\r\nb\u{2028}c") == ["a", "b", "c"])

        // One baseline per line, a line height apart, round(descent) above the bottom of its line.
        let baselines = TextLayout.baselineOrigins(for: box("Hi\nthere\n"))
        #expect(baselines.count == 3)
        #expect(baselines.allSatisfy { $0.x == 10 + padding })
        let first = 20 + padding + lineHeight - CTFontGetDescent(font).rounded()
        #expect(abs(baselines[0].y - first) < 0.0001)
        #expect(abs(baselines[1].y - baselines[0].y - lineHeight) < 0.0001)
        #expect(abs(baselines[2].y - baselines[1].y - lineHeight) < 0.0001)

        // A click puts the middle of the first line under the pointer, one padding in from the left.
        #expect(TextLayout.origin(forClickAt: CGPoint(x: 50, y: 60), fontSize: 40)
                == CGPoint(x: 50 - padding, y: 60 - padding - lineHeight / 2))
    }
}
```

In `TidyShotTests/EditorFlattenerTests.swift`, add `import CoreText` after `import CoreGraphics` (line 1), and add this test after `missingOrStaleTileFailsClosed` (line 276):
```swift
    /// Text burns in with CoreText under a flipped text matrix: upright, a line height apart, and
    /// only inside its frame. "HI" has no descenders, so on each line the fully red pixels lie
    /// between the cap height and the baseline. Text drawn upside down would hang below the
    /// baseline instead, and a missing flip of the bitmap would put it near the bottom rows.
    @Test func flattenedTextInkInsideFrameOnly() throws {
        let base = makeImage()
        let original = try Bitmap(base)
        let box = TextBox(id: UUID(), string: "HI\nHI", origin: CGPoint(x: 6, y: 4), fontSize: 14, color: red)
        let frame = TextLayout.frame(for: box)
        try #require(frame.maxX < 64 && frame.maxY < 48)
        let output = try Bitmap(flatten(base, [.text(box)]))
        #expect(output.differences(from: original, excluding: [frame]) == 0)

        let capHeight = CTFontGetCapHeight(TextLayout.font(size: 14))
        let baselines = TextLayout.baselineOrigins(for: box).map(\.y)
        try #require(baselines.count == 2)
        var rowsPerLine: [Set<Int>] = [[], []]
        for y in 0..<48 {
            for x in 0..<64 where output[x, y] == Self.redPixel {
                let centre = CGFloat(y) + 0.5
                let line = baselines.firstIndex { centre > $0 - capHeight - 1 && centre < $0 + 1 }
                #expect(line != nil, "red at \(x), \(y) is on neither line")
                if let line { rowsPerLine[line].insert(y) }
            }
        }
        #expect(rowsPerLine[0].count >= 5)
        #expect(rowsPerLine[1].count >= 5)
    }
```

In `TidyShotTests/KeyRoutingTests.swift`, replace the `action` helper (lines 10-13) with:
```swift
    func action(_ characters: String?, command: Bool = false, control: Bool = false, option: Bool = false,
                editing: Bool = false, tool: EditorTool = .select) -> KeyRouting.Action {
        KeyRouting.action(characters: characters, command: command, control: control, option: option,
                          isEditingText: editing, tool: tool)
    }
```
and add these tests after `editingTextPassesClipboardAndUndoChordsThrough` (line 146):
```swift
    /// With the Text tool active the digits pick text sizes instead of line widths.
    @Test func digitsPickTextSizesForTextTool() {
        #expect(EditorPalette.textSizesPoints == [12, 16, 20, 28, 40, 56])
        #expect(EditorPalette.textSizesPoints.count == EditorPalette.lineWidthsPoints.count)
        #expect(EditorPalette.defaultTextSizePoints == 20)
        for digit in 1...6 {
            #expect(action(String(digit), tool: .text) == .textSize(index: digit - 1))
            #expect(action(String(digit), tool: .rectangle) == .lineWidth(index: digit - 1))
            #expect(action(String(digit), tool: .select) == .lineWidth(index: digit - 1))
        }
        #expect(EditorPalette.textSizesPoints[3] == 28)
        // Letters still pick tools, T among them, and other keys stay ignored.
        #expect(action("v", tool: .text) == .selectTool(.select))
        #expect(action("t") == .selectTool(.text))
        for key in ["0", "7", "!"] {
            #expect(action(key, tool: .text) == ignored)
        }
        #expect(action("1", command: true, tool: .text) == ignored)
        // While typing, every key belongs to the text view.
        #expect(action("3", editing: true, tool: .text) == ignored)
        #expect(action("t", editing: true, tool: .text) == ignored)
    }

    /// While typing, EditorWindow sends these to the text view itself, so they work whether or not
    /// the never-drawn main menu has an Edit menu. The table leaves every one of them alone.
    @Test func textEditingChordsGoToTheTextView() {
        let expected: [(characters: String, shift: Bool, selector: String)] = [
            ("c", false, "copy:"), ("x", false, "cut:"), ("v", false, "paste:"),
            ("a", false, "selectAll:"), ("z", false, "undo:"), ("Z", true, "redo:"),
        ]
        for row in expected {
            #expect(TextEditingChord.selectorName(characters: row.characters, command: true, shift: row.shift,
                                                  option: false, control: false) == row.selector)
            #expect(matched(row.characters, shift: row.shift, editing: true) == nil)
        }
        // Command is required; Option, Control or another key is something else.
        #expect(TextEditingChord.selectorName(characters: "c", command: false, shift: false, option: false, control: false) == nil)
        #expect(TextEditingChord.selectorName(characters: "c", command: true, shift: false, option: true, control: false) == nil)
        #expect(TextEditingChord.selectorName(characters: "c", command: true, shift: false, option: false, control: true) == nil)
        #expect(TextEditingChord.selectorName(characters: "s", command: true, shift: false, option: false, control: false) == nil)
        // ⇧⌘C stays Copy Image, which commits the text and copies the picture.
        #expect(TextEditingChord.selectorName(characters: "C", command: true, shift: true, option: false, control: false) == nil)
        #expect(matched("C", shift: true, editing: true) == .copyImage)
    }
```

In `TidyShotTests/EditorModelTests.swift`, add these tests before the closing brace (line 348):
```swift
    /// Typing lives in the edit's own UndoManager. The editor's manager sees one step, on commit.
    @Test func textEditCommitsOnceWithoutEditorUndo() throws {
        let model = makeModel()
        model.tool = .text
        let click = CGPoint(x: 6, y: 5)
        model.beginTextEditing(at: click, existing: nil)
        #expect(model.isEditingText)
        let typing = try #require(model.textUndoManager)
        #expect(typing !== model.undoManager)
        #expect(typing.groupsByEvent)
        let editing = try #require(model.textEditing)
        #expect(editing.original == nil)
        #expect(editing.box.string.isEmpty)
        #expect(editing.box.fontSize == EditorPalette.defaultTextSizePoints * 2)
        #expect(editing.box.color == model.strokeColor)
        #expect(editing.box.origin == TextLayout.origin(forClickAt: click, fontSize: editing.box.fontSize))
        #expect(!model.hasUnsavedChanges)

        model.updateEditingText("Hi")
        model.updateEditingText("Hi\nthere\n")
        #expect(model.document.annotations.isEmpty)
        #expect(!model.undoManager.canUndo)
        // Typed text counts as unsaved, so ⌘W and Quit ask before it is lost.
        #expect(model.hasUnsavedChanges)

        model.commitTextEditing()
        #expect(!model.isEditingText)
        #expect(model.textUndoManager == nil)
        guard case .text(let box)? = model.document.annotations.first else {
            Issue.record("no text")
            return
        }
        #expect(model.document.annotations.count == 1)
        #expect(box.id == editing.box.id)
        #expect(box.string == "Hi\nthere")
        #expect(box.origin == editing.box.origin)
        #expect(model.selection == box.id)
        #expect(model.undoManager.undoActionName == "Add Text")
        // Committing again does nothing, and one undo removes the whole edit.
        model.commitTextEditing()
        #expect(undoAll(model) == [AnnotationDocument(annotations: [])])
    }

    @Test func reEditReplacesInPlaceAndBlankDeletes() throws {
        let model = makeModel()
        let shape = add(box(), to: model)
        let text = add(.text(TextBox(id: UUID(), string: "Old", origin: CGPoint(x: 2, y: 2), fontSize: 24, color: red)),
                       to: model)

        model.beginTextEditing(at: .zero, existing: text.id)
        #expect(model.textEditing?.box.string == "Old")
        #expect(model.textEditing?.original?.id == text.id)
        model.updateEditingText("New")
        model.commitTextEditing()
        #expect(model.document.annotations.map(\.id) == [shape.id, text.id])
        #expect(model.undoManager.undoActionName == "Edit Text")
        guard case .text(let edited)? = model.document.annotation(id: text.id) else {
            Issue.record("no text")
            return
        }
        #expect(edited.string == "New")
        #expect(edited.origin == CGPoint(x: 2, y: 2))
        #expect(edited.fontSize == 24)
        let afterEdit = model.document

        // Escape keeps what was committed and adds no step.
        model.beginTextEditing(at: .zero, existing: text.id)
        model.updateEditingText("Discarded")
        model.cancelTextEditing()
        #expect(model.document == afterEdit)
        #expect(model.undoManager.undoActionName == "Edit Text")
        #expect(model.selection == text.id)
        #expect(model.textUndoManager == nil)

        // The size keys resize the selected text as one step, in image pixels.
        model.applyTextSize(points: 28)
        model.applyTextSize(points: 40)
        #expect(model.textSizePoints == 40)
        guard case .text(let resized)? = model.document.annotation(id: text.id) else {
            Issue.record("no text")
            return
        }
        #expect(resized.fontSize == 80)
        #expect(model.undoManager.undoActionName == "Text Size")
        model.undoManager.undo()
        #expect(model.document == afterEdit)

        // Clearing the text deletes it in one step, and undo brings it back.
        model.beginTextEditing(at: .zero, existing: text.id)
        model.updateEditingText(" \n ")
        model.commitTextEditing()
        #expect(model.document.annotation(id: text.id) == nil)
        #expect(model.undoManager.undoActionName == "Delete")
        model.undoManager.undo()
        #expect(model.document == afterEdit)

        // A new box left blank adds nothing.
        model.beginTextEditing(at: CGPoint(x: 8, y: 8), existing: nil)
        model.commitTextEditing()
        #expect(model.document == afterEdit)
        #expect(!model.isEditingText)
    }
```

In `TidyShotTests/CanvasToolTests.swift`, add to `FakeCanvasEditing` (after `made`, line 22):
```swift
    /// Each `beginTextEditing` call.
    private(set) var textBegun: [(point: CGPoint, existing: UUID?)] = []
```
and, after `makeAnnotation` (line 48):
```swift
    func beginTextEditing(at point: CGPoint, existing id: UUID?) {
        textBegun.append((point: point, existing: id))
    }
```
Then add this test at the end of `CanvasToolTests` (before line 365):
```swift
    /// The Text tool starts typing on a click and never commits; the edit commits when it ends.
    @Test func textToolClickPlacesOrReEditsText() throws {
        let box = TextBox(id: UUID(), string: "Hello", origin: CGPoint(x: 100, y: 100), fontSize: 40, color: red)
        let canvas = FakeCanvasEditing([.text(box)])
        let tool = makeTool(for: .text)
        #expect(tool is TextTool)
        #expect(tool.cursor == NSCursor.iBeam)
        let inside = CGPoint(x: TextLayout.frame(for: box).midX, y: TextLayout.frame(for: box).midY)

        // A click on empty canvas starts a new box at the press, within the tiny-drag rule.
        tool.mouseDown(at(10, 10), on: canvas)
        tool.mouseUp(at(10.5, 10), on: canvas)
        // A click on a text edits it again.
        tool.mouseDown(at(inside.x, inside.y), on: canvas)
        tool.mouseUp(at(inside.x, inside.y), on: canvas)
        // A drag places nothing.
        tool.mouseDown(at(10, 10), on: canvas)
        tool.mouseDragged(at(40, 40), on: canvas)
        tool.mouseUp(at(40, 40), on: canvas)
        #expect(canvas.textBegun.map(\.point) == [CGPoint(x: 10, y: 10), inside])
        #expect(canvas.textBegun.map(\.existing) == [nil, box.id])
        #expect(canvas.commits.isEmpty)
        #expect(canvas.transient == nil)

        // With Select, a click selects the text and a double-click edits it again.
        let select = makeTool(for: .select)
        select.mouseDown(ToolInput(point: inside, clickCount: 1), on: canvas)
        select.mouseUp(ToolInput(point: inside, clickCount: 1), on: canvas)
        #expect(canvas.selection == box.id)
        #expect(canvas.textBegun.count == 2)
        select.mouseDown(ToolInput(point: inside, clickCount: 2), on: canvas)
        select.mouseUp(ToolInput(point: inside, clickCount: 2), on: canvas)
        #expect(canvas.textBegun.count == 3)
        #expect(canvas.textBegun.last?.existing == box.id)
        #expect(canvas.commits.isEmpty)
    }
```

In `TidyShotTests/EditorWindowGeometryTests.swift`, `toolbarWidthCountsEveryItem` stays as it is (it passes six segments explicitly). In Task 1's `toolbarWithEveryToolFitsASmallDisplay`, replace the two pinned lines Task 2 left (10 and 944) with the eleven-tool values (Select to Text, five segments of 36 pt more than 4a's 800):
```swift
        #expect(EditorTool.toolbarOrder.count == 11)
        #expect(width(segments: EditorTool.toolbarOrder.count) == 980)
```
`minimumToolbarContentWidth()` (EditorToolbar.swift:38-50) already counts `EditorTool.toolbarOrder`, so no `ToolbarMetrics` constant changes; the window's minimum width grows by one 36 pt segment.

- [ ] **Step 2: Run the tests and watch them fail**

Run:
```bash
xcodegen generate && xcodebuild test -project TidyShot.xcodeproj -scheme TidyShot -destination 'platform=macOS' -derivedDataPath .build 2>&1 | grep -E "Test run with|error:|TEST"
```
Expected: compile errors, among them `cannot find type 'TextBox' in scope`, `cannot find 'TextLayout' in scope`, `cannot find 'TextEditingChord' in scope`, `extra argument 'tool' in call`, `type 'EditorTool' has no member 'text'` and `value of type 'EditorModel' has no member 'beginTextEditing'`, then `** TEST FAILED **` and no `Test run with` line.

- [ ] **Step 3: The model, the tool table and the palette**

In `TidyShot/Editor/Model/Annotation.swift`, after `Region` (line 28):
```swift
/// A text annotation. `origin` is the top-left corner of its frame (`TextLayout.frame(for:)`), and
/// `fontSize` is in image pixels: the points chosen in the UI times the capture scale. Lines are
/// split at newlines only; nothing wraps.
nonisolated struct TextBox: Codable, Equatable, Sendable {
    let id: UUID
    var string: String
    var origin: CGPoint
    var fontSize: CGFloat
    var color: RGBA
}
```
In `enum Annotation` add `case text(TextBox)` after the drawing cases (lines 33-38), and an arm in every member:
- `id` (lines 40-46): `case .text(let box): box.id`
- `isEffect` (lines 48-53) and `effectRect` (lines 56-61): add `.text` to the drawings' arm (`false`, `nil`).
- `title` (lines 64-72): `case .text: "Text"`
- `moved(by:)` (lines 75-94):
  ```swift
          case .text(var box):
              box.origin = CGPoint(x: box.origin.x + delta.dx, y: box.origin.y + delta.dy)
              return .text(box)
  ```
- `withColor(_:)` (lines 98-111):
  ```swift
          case .text(var box):
              box.color = color
              return .text(box)
  ```
- `withLineWidth(_:)` (lines 114-125) and `withEffectParameter(_:)` (lines 129-138): add `.text` to the arm that returns `self`. Text has a size, not a line width.

Then add after `withEffectParameter`:
```swift
    /// A text annotation at `size` image pixels, keeping its top-left corner. Everything else comes
    /// back unchanged.
    func withFontSize(_ size: CGFloat) -> Annotation {
        guard case .text(var box) = self else { return self }
        box.fontSize = size
        return .text(box)
    }
```

In `TidyShot/Editor/Model/EditorTool.swift`: add `text` to the cases (line 4, after Task 2's `highlighter`), and the arms `case .text: "T"` (letter, lines 7-16), `case .text: "Text"` (title, lines 18-27) and `case .text: "textformat"` (symbolName, lines 30-39). Add `.text` to the `false` arm of `isEffect` (lines 45-50), and append `.text` as the last element of `toolbarOrder` (lines 54-56).

In `TidyShot/Editor/Model/EditorPalette.swift`, after `lineWidthsPoints` (line 23):
```swift
    /// Text sizes in points, on keys 1 to 6 while the Text tool is active.
    static let textSizesPoints: [CGFloat] = [12, 16, 20, 28, 40, 56]
    /// New text starts at this size. It is not persisted: AppSettings keeps its five editor keys.
    static let defaultTextSizePoints: CGFloat = 20
```

- [ ] **Step 4: TextLayout**

Create `TidyShot/Editor/Geometry/TextLayout.swift`:
```swift
import CoreGraphics
import CoreText
import Foundation

/// Where a text annotation's lines sit, in image pixels with a top-left origin. AnnotationDrawing
/// draws committed text from these numbers with CoreText, and CanvasView's NSTextView lays out the
/// text being typed by the same rules, so the text does not move on commit and the export equals
/// the preview:
/// - one font, `font(size:)` at the box's `fontSize`. The text view's bounds are in image pixels
///   and only its frame is zoomed, so TextKit never sees a zoomed point size (the system font
///   tracks differently at different sizes);
/// - lines split at newlines only, never wrapped, so the frame grows with the text;
/// - a fixed line height of ascent + descent + leading, set on the text view as its paragraph
///   style's minimum and maximum line height;
/// - each baseline `round(descent)` above the bottom of its line, which is where TextKit 2 puts it;
/// - `padding` on every side: the text view's `textContainerInset`, with no line fragment padding.
/// Measured on macOS 27: the NSTextView (TextKit 2) and `CTLineDraw` give the same pixels from
/// 25 % to 400 % zoom.
nonisolated enum TextLayout {
    /// The bold system font, so text reads on busy screenshots. CTFont is toll-free bridged to
    /// NSFont, so the text view uses the same font (`as NSFont`).
    static func font(size: CGFloat) -> CTFont {
        CTFontCreateUIFontForLanguage(.emphasizedSystem, size, nil)
            ?? CTFontCreateWithName("Helvetica-Bold" as CFString, size, nil)
    }

    /// Space between the frame and the glyphs on every side, a quarter of the size rounded up.
    /// It holds the glyphs' overhang and gives a click on the text some room.
    static func padding(fontSize: CGFloat) -> CGFloat {
        (fontSize / 4).rounded(.up)
    }

    /// The distance between baselines.
    static func lineHeight(fontSize: CGFloat) -> CGFloat {
        let font = font(size: fontSize)
        return CTFontGetAscent(font) + CTFontGetDescent(font) + CTFontGetLeading(font)
    }

    /// From the top of a line to its baseline: TextKit 2 sets the baseline of a fixed-height line
    /// `round(descent)` above the line's bottom.
    static func baselineOffset(fontSize: CGFloat) -> CGFloat {
        lineHeight(fontSize: fontSize) - CTFontGetDescent(font(size: fontSize)).rounded()
    }

    /// The lines of `string`, split at every newline character (LF, CR, CRLF, U+2028, U+2029). An
    /// empty string, or the end after a trailing newline, is an empty line.
    static func lines(of string: String) -> [String] {
        string.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).map(String.init)
    }

    /// One line in `font` and `color`, made on each call and never stored.
    static func line(_ text: String, font: CTFont, color: CGColor) -> CTLine {
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): color,
        ]
        return CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
    }

    /// The typographic width of one line, trailing spaces included, as the caret sees it.
    static func width(of text: String, font: CTFont) -> CGFloat {
        guard !text.isEmpty else { return 0 }
        return CGFloat(CTLineGetTypographicBounds(line(text, font: font, color: CGColor(gray: 0, alpha: 1)), nil, nil, nil))
    }

    /// The box's frame: the widest line and one line height per line, plus `padding` on every side.
    static func frame(for box: TextBox) -> CGRect {
        let font = font(size: box.fontSize)
        let lines = lines(of: box.string)
        let widest = lines.map { width(of: $0, font: font) }.max() ?? 0
        let padding = padding(fontSize: box.fontSize)
        return CGRect(x: box.origin.x, y: box.origin.y, width: widest + 2 * padding,
                      height: CGFloat(lines.count) * lineHeight(fontSize: box.fontSize) + 2 * padding)
    }

    /// Where each line starts on its baseline, one per line of `lines(of:)`.
    static func baselineOrigins(for box: TextBox) -> [CGPoint] {
        let padding = padding(fontSize: box.fontSize)
        let lineHeight = lineHeight(fontSize: box.fontSize)
        let first = box.origin.y + padding + baselineOffset(fontSize: box.fontSize)
        return lines(of: box.string).indices.map { index in
            CGPoint(x: box.origin.x + padding, y: first + CGFloat(index) * lineHeight)
        }
    }

    /// The origin of a new box clicked at `point`: the middle of its first line under the
    /// pointer, the text starting at the pointer.
    static func origin(forClickAt point: CGPoint, fontSize: CGFloat) -> CGPoint {
        let padding = padding(fontSize: fontSize)
        return CGPoint(x: point.x - padding, y: point.y - padding - lineHeight(fontSize: fontSize) / 2)
    }

    /// What a commit stores: the typed text without trailing newlines, or nil when nothing but
    /// whitespace was typed.
    static func committedString(_ typed: String) -> String? {
        guard typed.contains(where: { !$0.isWhitespace }) else { return nil }
        var string = typed
        while let last = string.last, last.isNewline {
            string.removeLast()
        }
        return string
    }
}
```

- [ ] **Step 5: Drawing, bounds and hit testing**

In `TidyShot/Editor/Rendering/AnnotationDrawing.swift`, add `import CoreText` after `import CoreGraphics` (line 1). In `draw(_:in:scale:)` (lines 16-25) add `case .text(let box): drawText(box, in: context)`. Add after `drawArrow` (line 118):
```swift
    /// CoreText on the bare context, which is in image pixels with a top-left origin (y down), so
    /// the text matrix flips the glyphs upright. Each line starts at its baseline origin from
    /// TextLayout, where CanvasView's NSTextView also put it while the text was typed. The text
    /// matrix is not part of the graphics state, so it is put back by hand.
    private static func drawText(_ box: TextBox, in context: CGContext) {
        guard box.fontSize > 0, !box.string.isEmpty else { return }
        let font = TextLayout.font(size: box.fontSize)
        let colour = box.color.cgColor
        let savedTextMatrix = context.textMatrix
        context.saveGState()
        defer {
            context.restoreGState()
            context.textMatrix = savedTextMatrix
        }
        context.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
        for (text, origin) in zip(TextLayout.lines(of: box.string), TextLayout.baselineOrigins(for: box)) where !text.isEmpty {
            context.textPosition = origin
            CTLineDraw(TextLayout.line(text, font: font, color: colour), context)
        }
    }
```
In `drawSelection` (lines 50-67), outline text like an effect: Task 2 left the condition as `if let rect = annotation.effectRect ?? AnnotationGeometry.strokeOutline(of: annotation) {`; make it `if let rect = annotation.effectRect ?? AnnotationGeometry.strokeOutline(of: annotation) ?? textFrame(of: annotation) {` (keep the stroke outline), extend the doc comment ("A selected effect or text gets a dashed outline …; text has no handles"), and add:
```swift
    /// A text annotation's frame, outlined when it is selected because text has no handles.
    private static func textFrame(of annotation: Annotation) -> CGRect? {
        guard case .text(let box) = annotation else { return nil }
        return TextLayout.frame(for: box)
    }
```

In `TidyShot/Editor/Geometry/ArrowGeometry.swift`, `AnnotationGeometry.bounds` (lines 53-69):
```swift
        case .text(let box):
            // The padding holds the glyphs' overhang.
            painted = TextLayout.frame(for: box)
```

In `TidyShot/Editor/Geometry/HitTester.swift`:
- `handles(for:)` (lines 26-35): `case .text: []`, and add "Text has none: its size comes from the size keys." to the doc comment (lines 22-25).
- `resized(_:handle:to:square:)` (lines 64-86): `case .text: return annotation`.
- `bodyContains` (lines 145-157), filled like an effect:
  ```swift
          case .text(let box):
              return TextLayout.frame(for: box).insetBy(dx: -tolerance, dy: -tolerance).contains(point)
  ```

- [ ] **Step 6: Key routing and the text chords**

In `TidyShot/Editor/Geometry/KeyRouting.swift`, add to `Action` (lines 9-16), after `lineWidth`:
```swift
        /// Digits 1 to 6 while the Text tool is active: an index into `EditorPalette.textSizesPoints`.
        case textSize(index: Int)
```
Replace `action` (lines 22-35) with:
```swift
    /// `characters` is `NSEvent.charactersIgnoringModifiers`, which keeps Shift: ⇧1 arrives as
    /// "!" and matches nothing, while ⇧V arrives as "V" and still picks Select. Command, Control
    /// or Option held, or a text edit in progress, make every key `.none`. The digits pick text
    /// sizes while `tool` is Text and line widths otherwise.
    static func action(characters: String?, command: Bool, control: Bool, option: Bool, isEditingText: Bool,
                       tool: EditorTool = .select) -> Action {
        guard !command, !control, !option, !isEditingText,
              let characters, characters.count == 1, let key = characters.first else { return .none }
        if key.isASCII, let digit = key.wholeNumberValue, (1...EditorPalette.lineWidthsPoints.count).contains(digit) {
            return tool == .text ? .textSize(index: digit - 1) : .lineWidth(index: digit - 1)
        }
        if let picked = EditorTool.tool(forKey: key) {
            return .selectTool(picked)
        }
        return .none
    }
```
Append at the end of the file (after line 118):
```swift
/// While a text annotation is being typed, the chords `EditorShortcut` leaves to the text view
/// (its `passesThroughWhileEditingText` rows, and ⌘X, which has no row). `EditorWindow` sends them
/// to the first responder itself, so they reach the NSTextView, and ⌘Z its own UndoManager, whether
/// or not the never-drawn main menu has an Edit menu.
nonisolated enum TextEditingChord {
    static func selectorName(characters: String, command: Bool, shift: Bool, option: Bool, control: Bool) -> String? {
        guard command, !option, !control else { return nil }
        switch (characters.lowercased(), shift) {
        case ("c", false): return "copy:"
        case ("x", false): return "cut:"
        case ("v", false): return "paste:"
        case ("a", false): return "selectAll:"
        case ("z", false): return "undo:"
        case ("z", true): return "redo:"
        default: return nil
        }
    }
}
```

- [ ] **Step 7: Text editing in EditorModel**

In `TidyShot/Editor/Session/EditorModel.swift`, after `EffectParameter` (line 9):
```swift
/// A text annotation being typed (spec 2.6, Phase 4b). The string follows the text view on every
/// change, so the commit needs nothing from AppKit.
nonisolated struct TextEditing: Equatable, Sendable {
    /// The box as it would be committed now. A re-edit keeps the annotation's id.
    var box: TextBox
    /// The committed text being edited again; nil for a new box.
    let original: TextBox?
}
```
Add to `ActionName` (lines 21-28):
```swift
        static let editText = "Edit Text"
        static let textSize = "Text Size"
```
Replace `hasUnsavedChanges` (line 39) with:
```swift
    /// Also true while typed text would change the document, so ⌘W and Quit ask before it is lost
    /// (`AppCoordinator.hasUnsavedEditors` reads this).
    var hasUnsavedChanges: Bool { document != savedDocument || textEditChangesDocument }
```
Replace `tool` (lines 53-55) with:
```swift
    /// Redaction is the reason the editor exists, so it opens with Redact. A tool change commits the
    /// text being typed.
    var tool: EditorTool = .redact {
        didSet {
            guard tool != oldValue else { return }
            transient = nil
            commitTextEditing()
        }
    }
```
After `blockPoints` (line 60):
```swift
    /// The size for new text, in points; keys 1 to 6 with the Text tool change it.
    var textSizePoints: CGFloat = EditorPalette.defaultTextSizePoints
    /// The text being typed, or nil. While it is set, CanvasView shows an NSTextView over it.
    private(set) var textEditing: TextEditing?
    var isEditingText: Bool { textEditing != nil }
```
and next to `undoManager` (line 64):
```swift
    /// The edit's own UndoManager, made by `beginTextEditing` and emptied and dropped when the edit
    /// ends. The text view's delegate returns it from `undoManager(for:)`, so typing never registers
    /// in `undoManager` (groupsByEvent = false). It groups by event, as NSTextView's typing needs.
    @ObservationIgnored private(set) var textUndoManager: UndoManager?
```
In `makeAnnotation` (lines 137-157) add `case .text: return nil`: text is placed by `beginTextEditing`, not by a drag.

Add a section after `selectAll()` (line 187):
```swift
    // MARK: Text

    /// Starts typing (the Text tool's click, or a double-click on a text with Select): the text
    /// annotation `existing` again, or else a new box whose first line is centred on `point`, in
    /// the stroke colour at `textSizePoints`. An edit already running is committed first.
    func beginTextEditing(at point: CGPoint, existing id: UUID?) {
        commitTextEditing()
        transient = nil
        if let id, case .text(let box)? = document.annotation(id: id) {
            textEditing = TextEditing(box: box, original: box)
        } else {
            let fontSize = textSizePoints * scale
            let box = TextBox(id: UUID(), string: "", origin: TextLayout.origin(forClickAt: point, fontSize: fontSize),
                              fontSize: fontSize, color: strokeColor)
            textEditing = TextEditing(box: box, original: nil)
        }
        selection = nil
        textUndoManager = UndoManager()
    }

    /// The text view's string after each change.
    func updateEditingText(_ string: String) {
        guard let editing = textEditing, editing.box.string != string else { return }
        textEditing?.box.string = string
    }

    /// One editor commit for the whole edit: `Add Text` for a new box, `Edit Text` for a re-edit
    /// (replaced in place, so the creation order is kept), `Delete` for a re-edit left blank, and
    /// nothing for a new box left blank. Trailing newlines are dropped. The edit's UndoManager is
    /// emptied and dropped first, so nothing typed can be undone after the commit.
    func commitTextEditing() {
        guard let editing = textEditing else { return }
        endTextEditing()
        guard let string = TextLayout.committedString(editing.box.string) else {
            if let original = editing.original {
                commit(document.removing(id: original.id), actionName: ActionName.delete)
            }
            return
        }
        var box = editing.box
        box.string = string
        if editing.original != nil {
            commit(document.replacing(.text(box)), actionName: ActionName.editText)
            selection = box.id
        } else {
            commitNewShape(.text(box))
        }
    }

    /// Escape: the typing is dropped. A re-edited annotation stays as committed, selected.
    func cancelTextEditing() {
        guard let editing = textEditing else { return }
        endTextEditing()
        selection = editing.original?.id
    }

    private func endTextEditing() {
        textUndoManager?.removeAllActions()
        textUndoManager = nil
        textEditing = nil
    }

    private var textEditChangesDocument: Bool {
        guard let editing = textEditing else { return false }
        if let original = editing.original { return editing.box != original }
        return TextLayout.committedString(editing.box.string) != nil
    }
```
Palette and options:
- `activeColor` (lines 197-199, as Task 2 left it): put `textEditing?.box.color ??` in front, keeping Task 2's highlighter branch: `textEditing?.box.color ?? Self.color(of: selectedAnnotation) ?? (editsRedactColor ? redactColor : editsHighlighter ? highlightColor : strokeColor)`.
- `applyColor` (lines 208-213): after Task 2's `if editsRedactColor … else if editsHighlighter … else …` block that sets `redactColor`, `highlightColor` or `strokeColor`, add `if textEditing != nil { textEditing?.box.color = color }`. The text being typed takes the colour at once and keeps it on commit. (While typing, the tool is Text or Select and nothing is selected, so that block sets `strokeColor`.)
- `color(of:)` (lines 244-251): `case .text(let box)?: return box.color`.
- After `applyLineWidth` (line 220):
  ```swift
      /// Keys 1 to 6 with the Text tool: the size for new text, and for the selected text as one
      /// coalesced step.
      func applyTextSize(points: CGFloat) {
          textSizePoints = points
          guard let selected = selectedAnnotation, case .text = selected else { return }
          commit(document.replacing(selected.withFontSize(points * scale)), actionName: ActionName.textSize,
                 coalescingKey: "\(ActionName.textSize)-\(selected.id.uuidString)")
      }
  ```

- [ ] **Step 8: The tools**

In `TidyShot/Editor/Tools/CanvasTool.swift`, add to `protocol CanvasEditing` (lines 21-32), and a line to its doc comment ("`beginTextEditing` hands typing to the canvas; the edit commits when it ends, not on mouseUp."):
```swift
    /// Starts typing a text annotation: `existing` again, or a new box at `point` (4b).
    func beginTextEditing(at point: CGPoint, existing id: UUID?)
```
In `TidyShot/Editor/Tools/ToolFactory.swift` `makeTool(for:)` (lines 6-12): `case .text: return TextTool()`, and update the doc comment.

Create `TidyShot/Editor/Tools/TextTool.swift`:
```swift
import AppKit

/// Text (T). A click places a new text box with its first line centred on the pointer, or, on a
/// text annotation, edits that text again. A drag places nothing. The typing happens in
/// CanvasView's NSTextView and `EditorModel.commitTextEditing()` commits it when editing ends, so
/// this tool never commits.
final class TextTool: CanvasTool {
    /// Where the press landed; nil when no gesture runs.
    private var start: CGPoint?

    var cursor: NSCursor { .iBeam }

    func mouseDown(_ input: ToolInput, on canvas: any CanvasEditing) {
        start = input.point
    }

    func mouseDragged(_ input: ToolInput, on canvas: any CanvasEditing) {}

    func flagsChanged(_ input: ToolInput, on canvas: any CanvasEditing) {}

    func mouseUp(_ input: ToolInput, on canvas: any CanvasEditing) {
        guard let start else { return }
        self.start = nil
        // The tiny-drag rule, the other way round: only a click places or reopens text.
        guard !DragGeometry.isLongEnough(from: start, to: input.point, zoom: canvas.zoom) else { return }
        let tolerance = HitTester.tolerance(zoom: canvas.zoom)
        if let hit = HitTester.topmost(in: canvas.document, at: start, tolerance: tolerance),
           case .text? = canvas.document.annotation(id: hit.id) {
            canvas.beginTextEditing(at: start, existing: hit.id)
        } else {
            canvas.beginTextEditing(at: start, existing: nil)
        }
    }
}
```
In `TidyShot/Editor/Tools/SelectTool.swift` `mouseDown` (lines 50-56), between the `guard let top … else` block and `canvas.selection = annotation.id`:
```swift
        // A double-click on a text annotation edits it again (spec 2.6, Phase 4b).
        if input.clickCount >= 2, case .text = annotation {
            canvas.beginTextEditing(at: input.point, existing: annotation.id)
            return
        }
```
Add "A double-click on a text edits it again." to the class comment (lines 3-8).

- [ ] **Step 9: The text view in CanvasView**

`TidyShot/Editor/Window/CanvasView.swift`. The structure and the non-obvious code are below; the order of the teardown steps and the text view's set-up are part of the contract.

1. Replace the stored `isEditingText` (lines 17-18) with:
   ```swift
       /// True while a text annotation is being typed. EditorWindow reads it to let the clipboard and
       /// undo chords through to the text view; KeyRouting reads it to leave every key to it.
       var isEditingText: Bool { model.isEditingText }
   ```
2. `Shown` (lines 10-15) gains `var editingID: UUID?`, set from `model.textEditing?.box.id` where `now` is built (lines 271-272) and in `init` (lines 40-41). A change repaints the whole view, which hides or shows the committed copy of a re-edited text.
3. `observeModel()` (lines 248-261) also reads `_ = model.textEditing`.
4. `refresh()` (lines 265-295) calls `syncTextView()` right after the tool sync (line 270), before the `guard now != shown`, so the text view follows the transform, the edit and its colour on every refresh.
5. `displayedDrawings` (lines 364-369) also skips the annotation being re-edited: `model.document.drawings.filter { $0.id != transient?.id && $0.id != model.textEditing?.box.id }`. The text view shows it instead.
6. `mouseDown` (lines 132-138) starts with:
   ```swift
           // A click outside the text view while typing commits the text and does nothing else.
           if model.isEditingText {
               endTextEditing(commit: true)
               return
           }
   ```
   A click inside the text view never reaches the canvas: the text view is a subview and takes it.
7. `keyDown` (lines 183-200) passes `tool: model.tool` to `KeyRouting.action` and handles the new case:
   ```swift
           case .textSize(let index):
               let sizes = EditorPalette.textSizesPoints
               guard sizes.indices.contains(index) else { return }
               model.applyTextSize(points: sizes[index])
               refresh()
   ```
8. Add a `// MARK: Text editing` section with this state and these methods:
   ```swift
       /// The text view for `model.textEditing`: a subview placed by the transform, nil when nothing is typed.
       private var textView: NSTextView?
       /// The id of the box the text view edits, so a new edit gets a new view.
       private var textViewID: UUID?
       /// The edit's UndoManager, held from install to removal. `undoManager(for:)` must never return
       /// nil while the view lives: NSTextView would then fall back to the next responder's manager,
       /// the model's groupsByEvent = false one.
       private var textViewUndoManager: UndoManager?
       /// The colour the text view shows, so a palette change restyles it once.
       private var textViewColor: RGBA?

       /// For EditorWindowController's Save, Upload, Close and Zoom actions: commits the text and
       /// removes the text view at once, so the export and the close sheet see the committed text.
       func commitTextEditing() {
           endTextEditing(commit: true)
       }

       private func endTextEditing(commit: Bool) {
           guard model.isEditingText else { return }
           if let textView {
               // An input-method composition still open becomes part of the text.
               if textView.hasMarkedText() { textView.unmarkText() }
               model.updateEditingText(textView.string)
           }
           if commit {
               model.commitTextEditing()
           } else {
               model.cancelTextEditing()
           }
           refresh()
       }

       /// Brings the text view in line with `model.textEditing`: installs one for a new edit, removes
       /// it when the edit ended (also when the model ended it, as a tool change does), and otherwise
       /// re-applies the colour and the frame.
       private func syncTextView() {
           guard let editing = model.textEditing else {
               removeTextView()
               return
           }
           guard let view = textView, textViewID == editing.box.id else {
               removeTextView()
               installTextView(for: editing)
               return
           }
           if textViewColor != editing.box.color {
               textViewColor = editing.box.color
               let attributes = textAttributes(for: editing.box)
               if let storage = view.textStorage, let colour = attributes[.foregroundColor] {
                   storage.addAttribute(.foregroundColor, value: colour, range: NSRange(location: 0, length: storage.length))
               }
               view.typingAttributes = attributes
               view.insertionPointColor = attributes[.foregroundColor] as? NSColor ?? .labelColor
           }
           layoutTextView(view, for: editing.box)
       }

       /// TextKit 2 only: reading `view.layoutManager` would switch the view to TextKit 1, whose
       /// baselines differ from TextLayout's. Plain text, no substitutions or spelling marks, so the
       /// string typed is the string committed.
       private func installTextView(for editing: TextEditing) {
           let view = NSTextView(usingTextLayoutManager: true)
           view.delegate = self
           view.isRichText = false
           view.importsGraphics = false
           view.allowsUndo = true
           view.drawsBackground = false
           view.isHorizontallyResizable = false
           view.isVerticallyResizable = false
           view.isAutomaticQuoteSubstitutionEnabled = false
           view.isAutomaticDashSubstitutionEnabled = false
           view.isAutomaticTextReplacementEnabled = false
           view.isAutomaticSpellingCorrectionEnabled = false
           view.isContinuousSpellCheckingEnabled = false
           view.isGrammarCheckingEnabled = false
           view.usesFontPanel = false
           view.usesFindBar = false
           let padding = TextLayout.padding(fontSize: editing.box.fontSize)
           view.textContainerInset = NSSize(width: padding, height: padding)
           if let container = view.textContainer {
               container.lineFragmentPadding = 0
               container.widthTracksTextView = false
               container.heightTracksTextView = false
               container.size = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
           }
           let attributes = textAttributes(for: editing.box)
           view.defaultParagraphStyle = attributes[.paragraphStyle] as? NSParagraphStyle
           view.typingAttributes = attributes
           view.insertionPointColor = attributes[.foregroundColor] as? NSColor ?? .labelColor
           view.textStorage?.setAttributedString(NSAttributedString(string: editing.box.string, attributes: attributes))
           textView = view
           textViewID = editing.box.id
           textViewUndoManager = model.textUndoManager
           textViewColor = editing.box.color
           addSubview(view)
           layoutTextView(view, for: editing.box)
           window?.makeFirstResponder(view)
           view.setSelectedRange(NSRange(location: (view.string as NSString).length, length: 0))
       }

       /// TextLayout's font, colour and fixed line height, in image pixels.
       private func textAttributes(for box: TextBox) -> [NSAttributedString.Key: Any] {
           let lineHeight = TextLayout.lineHeight(fontSize: box.fontSize)
           let paragraph = NSMutableParagraphStyle()
           paragraph.minimumLineHeight = lineHeight
           paragraph.maximumLineHeight = lineHeight
           return [.font: TextLayout.font(size: box.fontSize) as NSFont,
                   .foregroundColor: NSColor(cgColor: box.color.cgColor) ?? NSColor.systemRed,
                   .paragraphStyle: paragraph]
       }

       /// The frame is `TextLayout.frame` in view points; the bounds stay that frame's size in image
       /// pixels. AppKit scales the drawing by the zoom and TextKit lays the text out at the model's
       /// font size, exactly where CoreText will draw it. The bounds are set after the frame, which
       /// resets them.
       private func layoutTextView(_ view: NSTextView, for box: TextBox) {
           let frame = TextLayout.frame(for: box)
           let zoom = model.transform.zoom
           view.setFrameOrigin(model.transform.viewPoint(frame.origin))
           view.setFrameSize(NSSize(width: frame.width * zoom, height: frame.height * zoom))
           view.setBoundsSize(frame.size)
       }

       /// In this order, so nothing typed from here on registers undo anywhere.
       private func removeTextView() {
           guard let view = textView else { return }
           let wasFirstResponder = window?.firstResponder === view
           textView = nil
           textViewID = nil
           textViewColor = nil
           view.allowsUndo = false
           view.isEditable = false
           view.delegate = nil
           textViewUndoManager = nil
           view.removeFromSuperview()
           if wasFirstResponder {
               window?.makeFirstResponder(self)
           }
       }
   ```
9. The delegate, after the class:
   ```swift
   extension CanvasView: NSTextViewDelegate {
       /// Typing registers in the edit's own manager, never in the model's (spec 2.6, Phase 4b).
       func undoManager(for view: NSTextView) -> UndoManager? {
           textViewUndoManager
       }

       func textDidChange(_ notification: Notification) {
           guard let textView, notification.object as? NSTextView === textView else { return }
           model.updateEditingText(textView.string)
           if let box = model.textEditing?.box {
               layoutTextView(textView, for: box)
           }
       }

       /// Return, Enter and Tab commit, Escape and ⌘. cancel. Shift-Return arrives as the same
       /// `insertNewline:` as Return, so the current event tells them apart; ⌥Return arrives as
       /// `insertNewlineIgnoringFieldEditor:` and inserts a newline as usual.
       func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
           switch commandSelector {
           case #selector(NSResponder.insertNewline(_:)):
               if NSApp.currentEvent?.modifierFlags.contains(.shift) == true {
                   textView.insertNewlineIgnoringFieldEditor(nil)
               } else {
                   endTextEditing(commit: true)
               }
               return true
           case #selector(NSResponder.insertTab(_:)), #selector(NSResponder.insertBacktab(_:)):
               endTextEditing(commit: true)
               return true
           case #selector(NSResponder.cancelOperation(_:)):
               endTextEditing(commit: false)
               return true
           default:
               return false
           }
       }
   }
   ```
   Measured: with `allowsUndo` on and this delegate, typing leaves the model's manager with nothing to undo, and Escape reaches `cancelOperation:` here before NSTextView turns it into `complete:`.

`resetCursorRects` needs no change: the Text tool's cursor is `.iBeam` and the text view sets its own.

- [ ] **Step 10: Shortcuts while typing, and commit before the window's actions**

`TidyShot/Editor/Window/EditorWindow.swift`: replace `performKeyEquivalent(with:)` (lines 11-36) so a chord the table leaves to the text view is sent to the first responder here. `undo:` is implemented by NSWindow, which undoes the first responder's manager, so ⌘Z reaches the text view's private manager this way (measured):
```swift
    /// `NSApp.sendAction` does not consult NSUserInterfaceValidations, so a matched shortcut is
    /// validated against the target that would receive it first: a refusal beeps and consumes the
    /// event. While text is typed, the chords the table leaves alone (`TextEditingChord`) are sent to
    /// the text view the same way. Anything else (⌘Q, ⌘,, or ⌘X when nothing is typed) goes on to
    /// super and the main menu.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        // Behind the unsaved-changes sheet, editor shortcuts do nothing.
        guard attachedSheet == nil, event.type == .keyDown, let characters = event.charactersIgnoringModifiers else {
            return super.performKeyEquivalent(with: event)
        }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let command = flags.contains(.command)
        let shift = flags.contains(.shift)
        let option = flags.contains(.option)
        let control = flags.contains(.control)
        let isEditingText = canvasView?.isEditingText ?? false
        // charactersIgnoringModifiers keeps Shift ("S" for ⇧⌘S), so it is lower-cased here and
        // Shift travels as its own flag.
        if let shortcut = EditorShortcut.match(characters: characters.lowercased(), command: command, shift: shift,
                                               option: option, control: control, isEditingText: isEditingText) {
            return send(NSSelectorFromString(shortcut.selectorName))
        }
        if isEditingText, let name = TextEditingChord.selectorName(characters: characters, command: command, shift: shift,
                                                                   option: option, control: control) {
            return send(NSSelectorFromString(name))
        }
        return super.performKeyEquivalent(with: event)
    }

    /// Sends `action` up the responder chain after its first target validates it; a refusal beeps.
    /// Either way the event is consumed, so a main-menu item with the same key never fires as well.
    private func send(_ action: Selector) -> Bool {
        guard let target = NSApp.target(forAction: action, to: nil, from: self),
              (target as? NSUserInterfaceValidations)?.validateUserInterfaceItem(ShortcutItem(action: action)) ?? true else {
            NSSound.beep()
            return true
        }
        NSApp.sendAction(action, to: target, from: self)
        return true
    }
```
Update the class comment's sentence about `isEditingText` (lines 7-8): it now says the text view also gets ⌘X and, with Task 5, ⌘V.

`TidyShot/Editor/Window/EditorWindowController.swift`: make `canvasView.commitTextEditing()` the first statement of `saveDocument(_:)` (line 156), `saveDocumentAs(_:)` (line 162), `copyImage(_:)` (line 174; `copy(_:)` reaches it), `uploadDocument(_:)` (line 186), `uploadDocumentAsNew(_:)` (line 192), `windowShouldClose(_:)` (line 306) and `askToSaveBeforeClosing()` (line 321, before its `hasUnsavedChanges` guard, so Quit sees the committed text), and of the zoom actions (lines 281-284), which become:
```swift
    @objc func zoomToFit(_ sender: Any?) {
        canvasView.commitTextEditing()
        canvasView.fitToView()
    }
```
and likewise for `zoomToActualSize`, `zoomIn` and `zoomOut`. Spec 2.6 asks Save, Upload, Close and Zoom to commit first. A pinch, a ⌘-scroll and a plain scroll keep the edit open: the text view follows the transform. In `TidyShot/Editor/Window/EditorToolbar.swift`, `zoomToPercent(_:)` (lines 179-181) also starts with `canvasView.commitTextEditing()`. The tools group needs no change: it is built from `EditorTool.toolbarOrder`, so Text appears last with `textformat` and the tooltip `Text (T)`.

- [ ] **Step 11: Run the suite**

Run:
```bash
xcodegen generate && xcodebuild test -project TidyShot.xcodeproj -scheme TidyShot -destination 'platform=macOS' -derivedDataPath .build 2>&1 | grep -E "Test run with|error:|TEST"
```
Expected: no `error:` lines, `Test run with 437 tests in 54 suites passed`, then `** TEST SUCCEEDED **`. This task adds 7 tests and 1 suite (`TextLayoutTests`).

- [ ] **Step 12: Check by hand**

Run:
```bash
xcodebuild -project TidyShot.xcodeproj -scheme TidyShot -configuration Debug -derivedDataPath .build build -quiet && open .build/Build/Products/Debug/TidyShot.app
```
In a second terminal:
```bash
log stream --style compact --predicate 'process == "TidyShot" AND eventMessage CONTAINS "Editor"'
```
Take a capture of a busy window (Slack), open the editor from the overlay's Annotate button, and press T.

Expected:
- **Placing.** The toolbar shows a `textformat` segment last, tooltip `Text (T)`, and every item still shows at the window's minimum width. A click puts a caret at the pointer, in bold red at 20 pt. Typing grows the box to the right; Shift-Return starts a new line; Return commits and the text shows a dashed outline. A drag with T places nothing.
- **No jump on commit.** At 100 % (⌘1), 200 % (zoom pop-up) and a fit below 50 %, type two lines including `gy` and an empty line, then press Return: no glyph, line or baseline moves by a pixel when the text view goes away. Pinch and scroll while typing: the text view follows the image.
- **Preview equals export.** With two lines of 28 pt text (press 4 with T active before clicking), Save As… a PNG and open it in Preview at Actual Size beside the editor at 100 %: line breaks, spacing and glyph positions match. Repeat at 200 % against Preview zoomed to 200 %.
- **Ending an edit.** Escape on a new box adds nothing. Double-click a committed text with Select (V), change it, press Escape: the old text comes back. A click on the canvas outside the text commits, and that click neither places a new box nor selects anything. Pressing R while typing types an `r`; choosing Rectangle in the toolbar commits the text. Clearing a re-edited text and pressing Return deletes it; ⌘Z brings it back.
- **Clipboard and undo while typing.** Select a word and press ⌘C, then paste in TextEdit: the word arrives, not the image. ⌘X cuts the word, ⌘V pastes it back as plain text, ⌘A selects all the text. ⌘Z undoes typing only: keep pressing it until the field is empty, then ⌘Z beeps and the shapes drawn earlier stay. No `Editor: undo` line is logged while typing; Return logs one with `"Add Text"`, and one more ⌘Z removes the whole text.
- **Window actions.** While typing, ⌘S, ⇧⌘C and ⌘U include the text in what they write, copy or upload, and the text view closes first. ⌘W while typing a new box shows the unsaved-changes sheet; so does Quit TidyShot from the menu bar. ⌘= while typing commits, then zooms.
- **Sizes and colour.** With T active and a text selected, 1 to 6 resize it to 12, 16, 20, 28, 40 and 56 pt, and a run of presses undoes in one ⌘Z. With Rectangle active the digits still set the line width. A swatch picked while typing recolours the text being typed.
- **Selection.** A committed text is selected with a click anywhere on it, moves with a drag and with the arrow keys, and Delete removes it. It shows a dashed outline and no handles.

- [ ] **Step 13: Commit**

```bash
git add TidyShot/Editor/Geometry/TextLayout.swift TidyShot/Editor/Tools/TextTool.swift TidyShot/Editor/Model/Annotation.swift TidyShot/Editor/Model/EditorTool.swift TidyShot/Editor/Model/EditorPalette.swift TidyShot/Editor/Geometry/KeyRouting.swift TidyShot/Editor/Geometry/HitTester.swift TidyShot/Editor/Geometry/ArrowGeometry.swift TidyShot/Editor/Rendering/AnnotationDrawing.swift TidyShot/Editor/Session/EditorModel.swift TidyShot/Editor/Tools/CanvasTool.swift TidyShot/Editor/Tools/ToolFactory.swift TidyShot/Editor/Tools/SelectTool.swift TidyShot/Editor/Window/CanvasView.swift TidyShot/Editor/Window/EditorWindow.swift TidyShot/Editor/Window/EditorWindowController.swift TidyShot/Editor/Window/EditorToolbar.swift TidyShotTests/TextLayoutTests.swift TidyShotTests/EditorFlattenerTests.swift TidyShotTests/KeyRoutingTests.swift TidyShotTests/EditorModelTests.swift TidyShotTests/CanvasToolTests.swift TidyShotTests/EditorWindowGeometryTests.swift
git commit -m "feat: text annotations"
```

### Task 4: Crop

**Files:**
- Create: `TidyShot/Editor/Geometry/CropGeometry.swift`
- Create: `TidyShot/Editor/Tools/CropTool.swift`
- Modify: `TidyShot/Editor/Model/AnnotationDocument.swift`
- Modify: `TidyShot/Editor/Model/EditorTool.swift`
- Modify: `TidyShot/Editor/Geometry/HitTester.swift` (one access level)
- Modify: `TidyShot/Editor/Rendering/EditorFlattener.swift`
- Modify: `TidyShot/Editor/Rendering/AnnotationDrawing.swift`
- Modify: `TidyShot/Editor/Session/EditorModel.swift`
- Modify: `TidyShot/Editor/Tools/CanvasTool.swift`
- Modify: `TidyShot/Editor/Tools/ToolFactory.swift`
- Modify: `TidyShot/Editor/Window/CanvasView.swift`
- Modify: `TidyShot/Editor/Window/EditorWindowController.swift` (one line in `export()`)
- Test: `TidyShotTests/CropGeometryTests.swift` (create)
- Test: `TidyShotTests/EditorModelTests.swift`, `TidyShotTests/AnnotationDocumentTests.swift`, `TidyShotTests/RedactionExportTests.swift`, `TidyShotTests/CanvasToolTests.swift`, `TidyShotTests/EditorWindowGeometryTests.swift` (Task 1's pinned toolbar width, for twelve tools)

Line numbers are `main` at 9193586. Tasks 1 to 3 add cases and lines to several of these files, so find each spot by the code quoted, not by the number alone.

Not modified, on purpose:
- `EditorToolbar.swift`. The tools group is built from `EditorTool.toolbarOrder` (EditorToolbar.swift:202-214), so the Crop segment, its image and its tool tip `Crop (C)` appear without a change there.
- `EditorWindowGeometry.swift`. `minimumToolbarContentWidth()` counts `EditorTool.toolbarOrder.count` segments (EditorToolbar.swift:45), so Crop widens the minimum by one `ToolbarMetrics.segment` (36 pt) with no new constant. The hand check confirms that no item overflows. Its test, Task 1's `toolbarWithEveryToolFitsASmallDisplay`, does change (Step 1).
- `AppCoordinator.swift`. The cropped size reaches the record through the existing paths, traced below.

How the cropped size reaches the record (no coordinator change):
1. `EditorWindowController.export()` (EditorWindowController.swift:269-277) calls `model.renderExport()`. `EditorFlattener.flatten` returns the cropped `CGImage` (this task, Step 5), and `renderExport` wraps it as `ScaledImage(image:scale:)` at the capture's scale (EditorModel.swift:257-271).
2. Save (`editorSave`, AppCoordinator.swift:1088) encodes that image and calls `applyLocalEdit(recordID:png:image:)`. At AppCoordinator.swift:1141 it records `recordLocalEdit(pixelWidth: image.image.width, pixelHeight: image.image.height, at:)`, and at 1143 `replaceThumbnail(for:from: image.image, editedAt:)` makes the thumbnail from the cropped image.
3. Upload (`editorUpload`, AppCoordinator.swift:1244) runs `applyLocalEdit` before every enqueue, on both the `.saveTarget` path (1269) and the `.newPendingFile` path (1288), and uploads the same cropped PNG.
4. Save As… (`editorSaveAs`, AppCoordinator.swift:1203) writes the cropped PNG and leaves the record alone, as spec 2.6 says. When the panel picks the record's own file it runs `editorSave`, so step 2 applies.
5. Copy (`editorCopy`, AppCoordinator.swift:1390) copies the cropped image.

**Interfaces:**
- Consumes:
  - `main`: `AnnotationDocument` (Codable, Equatable, Sendable; `annotations`, `effects`, `drawings`, `annotation(id:)`, `appending(_:)`, `removing(id:)`, `replacing(_:)`, `moving(id:by:)`). `EditorModel.commit(_:actionName:coalescingKey:)`, `undoManager`, `hasUnsavedChanges`, `markSaved()`, `cancelCurrentOperation()`, `selectAll()`, `renderExport() async -> ScaledImage?`. `protocol CanvasEditing`, `protocol CanvasTool`, `struct ToolInput`. `HitTester.tolerance(zoom:)`, `HitTester.resizedRect(_:handle:to:square:)`. `DragGeometry.rect(from:to:square:fromCentre:)`, `axisLocked(_:)`, `isLargeEnough(_:zoom:)`, `isLongEnough(from:to:zoom:)`. `CanvasTransform.fitting(imagePixelSize:in:inset:captureScale:)`, `viewRect(_:)`, `viewPoint(_:)`, `panned(by:)`. `AnnotationDrawing.handleSide`, `drawSelection(for:transform:scale:in:)`. `EditorFlattener.flatten(base:tiles:document:scale:) -> CGImage?`. Test helpers `EditorFlattenerTests.makeImage(...)`, `EditorFlattenerTests.pattern(_:_:)`, `EditorFlattenerTests.Bitmap`, `EditorFlattenerTests.redPixel`, `FakeCanvasEditing`, `FakeTileRenderer`.
  - Tasks 1 to 3: the `EditorTool` cases `ellipse`, `line`, `pencil`, `highlighter` and `text` (letters E, L, P, H, T) with their `toolbarOrder` places, `makeTool(for:)` arms and `EditorModel.makeAnnotation` arms. This task only appends to them. Task 1's `toolbarWithEveryToolFitsASmallDisplay`, pinned by Task 3 at 11 tools and 980 pt. Task 3's text editing commits through its own path, but two members this task replaces already carry Task 3 lines that must stay: `hasUnsavedChanges` (`|| textEditChangesDocument`) and `tool`'s `didSet` (`commitTextEditing()`). Task 3 handles Return while typing in the text view's delegate and does not override `CanvasView.insertNewline(_:)`.
- Produces:
  - `AnnotationDocument.crop: CGRect?` (default nil; the synthesized decoder reads an Optional with `decodeIfPresent`, so a document without the key decodes with no crop) and `func withCrop(_ crop: CGRect?) -> AnnotationDocument`. The stored crop is always `CropGeometry.integralCrop` output, so whole pixels, inside the image, never the whole image.
  - `EditorTool.crop`: letter `C`, title `Crop`, symbol `crop`, not an effect, last in `toolbarOrder`. `makeTool(for: .crop)` returns `CropTool()`.
  - `nonisolated enum CropGeometry` with `clamped(_:to:) -> CGRect`, `moved(_:by:within:) -> CGRect`, `snapped(_:in:) -> CGRect`, `integralCrop(_:in:) -> CGRect?`, `readout(for:) -> String`, `handle(of:at:tolerance:) -> Int?`.
  - `HitTester.boxHandles(_ rect: CGRect) -> [CGPoint]`, no longer private.
  - `CanvasEditing` gains `var cropDraft: CGRect? { get set }` and `var imageSize: CGSize { get }`. `FakeCanvasEditing` gains both.
  - `EditorModel`: `var cropDraft: CGRect?`, `var imageSize: CGSize`, `func applyCrop()`, `func cancelCrop()`, `ActionName.crop = "Crop"`. Picking `.crop` starts the draft; Escape (`cancelCurrentOperation()`) runs `cancelCrop()` while cropping; `hasUnsavedChanges` counts a draft that would change the crop.
  - `final class CropTool: CanvasTool`.
  - `AnnotationDrawing.cropDimAlpha: CGFloat = 0.5`, `drawHandles(_:transform:scale:in:)`, `drawCropChrome(crop:imageSize:transform:scale:in:)`, `drawCropCover(keeping:bounds:transform:color:scale:in:)`.
  - The flattener applies `CGImage.cropping(to:)` last.
  - `CanvasView` draws the dim mask, the 8 handles and the `W × H` readout while cropping, and covers everything outside an applied crop. Return (`insertNewline:`) applies, and Fit fits the applied crop.

Behaviour (spec 2.6, Phase 4b: "`document.crop` with 8 handles, a dim mask and a W x H readout. Return applies and Escape cancels. The crop is undoable, is applied last at export, and updates the pixel size on Save."):
- Picking Crop (C or the toolbar) clears the selection and starts `cropDraft` at the applied crop, or the whole capture when there is none. The canvas shows the whole capture with the outside of the draft dimmed (black at 0.5 alpha), a 1 pt white edge, 8 handles and the readout.
- A handle drag resizes (Shift squares a corner drag). A drag inside moves the draft, keeping its size (Shift keeps the dominant axis). A drag outside draws a new rect (Shift squares, Option grows it from the centre). Every rect stays inside the image. The draft is never undoable.
- Return applies the draft as one commit named `Crop`, then returns to the tool used before Crop. Escape drops the draft, leaves the document unchanged, and returns to that tool too, so it never leaves the user stuck in the mask.
- The readout counts the pixels export keeps (`CropGeometry.snapped`), for example `2560 × 1440` for a full 2x capture.
- Decisions beyond the spec's sentence. Picking another tool while cropping applies the draft as one `Crop` step, as clicking elsewhere commits a text edit. Escape is the only way to drop the draft. A Copy, Save, Save As… or Upload while cropping applies the draft first (one line in `export()`), so the export is what the window shows. A draft that would change the crop counts in `hasUnsavedChanges`, so the edited dot, the close sheet and the quit review see it. A draft dragged back to the whole capture stores nil and adds no step.
- Once a crop is applied and the Crop tool is not active, the canvas paints the window background over everything outside the crop, drawings and tiles included. Fit (⌘0, and the fit kept on resize) fits the crop. While cropping, Fit fits the whole capture. Undo and redo of `Crop` follow the same rule. Annotations outside the crop stay in the document. Tiles still render on the whole capture, and the crop is applied after them, so an effect cut by the crop's edge has exactly the pixels it has uncropped.

- [ ] **Step 1: Write the failing tests**

`TidyShotTests/CropGeometryTests.swift` (new):
```swift
import CoreGraphics
import Foundation
import Testing
@testable import TidyShot

/// The crop rect's geometry, and the flattener applying it last. Image pixels, top-left origin,
/// on the 64 x 48 fixture EditorFlattenerTests uses.
struct CropGeometryTests {
    let size = CGSize(width: 64, height: 48)

    @Test func cropClampedToImage() {
        #expect(CropGeometry.clamped(CGRect(x: -10, y: 40, width: 30, height: 20), to: size)
                == CGRect(x: 0, y: 40, width: 20, height: 8))
        #expect(CropGeometry.clamped(CGRect(x: 100, y: 0, width: 10, height: 10), to: size) == .zero)
        // Dragged up and to the left: standardized first.
        #expect(CropGeometry.clamped(CGRect(x: 50, y: 30, width: -20, height: -10), to: size)
                == CGRect(x: 30, y: 20, width: 20, height: 10))

        // A move keeps the size and stops at the image's edges.
        let rect = CGRect(x: 10, y: 10, width: 20, height: 10)
        #expect(CropGeometry.moved(rect, by: CGVector(dx: 3, dy: 4), within: size)
                == CGRect(x: 13, y: 14, width: 20, height: 10))
        #expect(CropGeometry.moved(rect, by: CGVector(dx: 100, dy: -100), within: size)
                == CGRect(x: 44, y: 0, width: 20, height: 10))

        // Handles are numbered as HitTester numbers a box's: 4 is the bottom-right corner.
        #expect(CropGeometry.handle(of: rect, at: CGPoint(x: 31, y: 21), tolerance: 2) == 4)
        #expect(CropGeometry.handle(of: rect, at: CGPoint(x: 20, y: 9), tolerance: 2) == 1)
        #expect(CropGeometry.handle(of: rect, at: CGPoint(x: 20, y: 15), tolerance: 2) == nil)
    }

    /// No crop, nothing left after rounding, nothing inside the image, and the whole image all
    /// store nil, so export keeps the capture as it is.
    @Test func emptyCropIsNil() {
        #expect(CropGeometry.integralCrop(nil, in: size) == nil)
        #expect(CropGeometry.integralCrop(.zero, in: size) == nil)
        #expect(CropGeometry.integralCrop(.null, in: size) == nil)
        #expect(CropGeometry.integralCrop(CGRect(x: 10, y: 10, width: 0.4, height: 20), in: size) == nil)
        #expect(CropGeometry.integralCrop(CGRect(x: 70, y: 10, width: 20, height: 20), in: size) == nil)
        #expect(CropGeometry.integralCrop(CGRect(origin: .zero, size: size), in: size) == nil)
        #expect(CropGeometry.integralCrop(CGRect(x: -5, y: -5, width: 80, height: 60), in: size) == nil)
        // One row short of the whole image is a crop.
        #expect(CropGeometry.integralCrop(CGRect(x: 0, y: 0, width: 64, height: 47), in: size)
                == CGRect(x: 0, y: 0, width: 64, height: 47))
        #expect(CropGeometry.integralCrop(CGRect(x: 30, y: 20, width: -10, height: -8), in: size)
                == CGRect(x: 20, y: 12, width: 10, height: 8))
    }

    /// Each edge rounds to the nearest pixel, and the readout counts what export will keep.
    @Test func readoutCountsExportedPixels() {
        let draft = CGRect(x: 10.4, y: 5.6, width: 20.2, height: 9.7)
        let snapped = CropGeometry.snapped(draft, in: size)
        #expect(snapped == CGRect(x: 10, y: 6, width: 21, height: 9))
        #expect(CropGeometry.integralCrop(draft, in: size) == snapped)
        #expect(CropGeometry.readout(for: snapped) == "21 × 9")
        // The whole capture reads as its own size, although it stores no crop.
        #expect(CropGeometry.readout(for: CropGeometry.snapped(CGRect(origin: .zero, size: size), in: size)) == "64 × 48")
    }

    /// The crop is cut from the finished bitmap: the output has the crop's size, its pixels are the
    /// flattened capture's at the crop's offset, and a drawing across the crop's edge keeps its
    /// pixels. No crop, or a whole-image crop, changes nothing.
    @Test func flattenedSizeEqualsCrop() throws {
        let fixture = EditorFlattenerTests()
        let base = fixture.makeImage()
        let crop = try #require(CropGeometry.integralCrop(CGRect(x: 10.4, y: 5.6, width: 20.2, height: 9.7), in: size))
        // A 2 px red stroke inside (4, 8, 12, 4): its right band covers columns 14 and 15.
        let box = Annotation.rectangle(ShapeBox(id: UUID(), rect: CGRect(x: 4, y: 8, width: 12, height: 4),
                                                color: fixture.red, lineWidth: 2))

        let output = try #require(EditorFlattener.flatten(base: base, tiles: [],
                                                          document: AnnotationDocument(annotations: [box], crop: crop),
                                                          scale: 1))
        #expect(output.width == 21)
        #expect(output.height == 9)
        #expect(CropGeometry.readout(for: crop) == "\(output.width) × \(output.height)")
        let pixels = try EditorFlattenerTests.Bitmap(output)
        #expect(pixels[0, 0] == EditorFlattenerTests.pattern(10, 6))
        #expect(pixels[20, 8] == EditorFlattenerTests.pattern(30, 14))
        #expect(pixels[5, 3] == EditorFlattenerTests.redPixel)

        let whole = try #require(EditorFlattener.flatten(base: base, tiles: [],
                                                         document: AnnotationDocument(annotations: [box]), scale: 1))
        #expect(whole.width == 64)
        #expect(whole.height == 48)
        let full = AnnotationDocument(annotations: [box], crop: CGRect(origin: .zero, size: size))
        let fullOutput = try #require(EditorFlattener.flatten(base: base, tiles: [], document: full, scale: 1))
        #expect(try EditorFlattenerTests.Bitmap(fullOutput).differences(from: EditorFlattenerTests.Bitmap(whole)) == 0)
    }
}
```

`EditorFlattenerTests.Bitmap` works on a cropped image unchanged. A `CGImage` from `cropping(to:)` keeps the parent's `bytesPerRow`, and its data provider's bytes start at the crop's first pixel; this was checked on this SDK.

`TidyShotTests/EditorModelTests.swift`, two tests appended before the closing brace (after `renderExportFailsWhenAnEffectTileIsMissing`, line 346):
```swift
    @Test func undoRestoresUncropped() async throws {
        let model = makeModel()
        let shape = add(box(), to: model)
        model.selection = shape.id
        model.tool = .crop
        // Cropping starts at the whole capture, with nothing selected, and ⌘A selects nothing.
        #expect(model.cropDraft == CGRect(x: 0, y: 0, width: 16, height: 16))
        #expect(model.selection == nil)
        model.selectAll()
        #expect(model.selection == nil)

        model.cropDraft = CGRect(x: 2.4, y: 1.6, width: 9.8, height: 8.1)
        model.applyCrop()
        let crop = CGRect(x: 2, y: 2, width: 10, height: 8)
        #expect(model.document.crop == crop)
        #expect(model.document.annotations == [shape])
        #expect(model.cropDraft == nil)
        #expect(model.tool == .redact)
        #expect(model.undoManager.undoActionName == EditorModel.ActionName.crop)
        let cropped = try #require(await model.renderExport())
        #expect(cropped.image.width == 10)
        #expect(cropped.image.height == 8)
        #expect(cropped.scale == 2)

        model.undoManager.undo()
        #expect(model.document.crop == nil)
        #expect(model.document.annotations == [shape])
        let uncropped = try #require(await model.renderExport())
        #expect(uncropped.image.width == 16)
        model.undoManager.redo()
        #expect(model.document.crop == crop)
        // Cropping again starts at the applied crop.
        model.tool = .crop
        #expect(model.cropDraft == crop)
    }

    @Test func escapeCancelsCropAndAnotherToolApplies() {
        let model = makeModel()
        model.tool = .select
        model.tool = .crop
        model.cropDraft = CGRect(x: 4, y: 4, width: 8, height: 8)
        // A draft that would change the crop is an unsaved change, so closing asks.
        #expect(model.hasUnsavedChanges)
        model.cancelCurrentOperation()
        #expect(model.cropDraft == nil)
        #expect(model.document.crop == nil)
        #expect(model.tool == .select)
        #expect(!model.hasUnsavedChanges)
        #expect(!model.undoManager.canUndo)

        // Another tool keeps the draft as one step; a draft left at the whole capture adds none.
        model.tool = .crop
        model.tool = .arrow
        #expect(!model.undoManager.canUndo)
        model.tool = .crop
        model.cropDraft = CGRect(x: 4, y: 4, width: 8, height: 8)
        model.tool = .arrow
        #expect(model.cropDraft == nil)
        #expect(model.document.crop == CGRect(x: 4, y: 4, width: 8, height: 8))
        #expect(model.undoManager.undoActionName == EditorModel.ActionName.crop)
        // Return outside Crop does nothing.
        model.applyCrop()
        #expect(model.tool == .arrow)
        #expect(undoAll(model).count == 1)
    }
```

`TidyShotTests/AnnotationDocumentTests.swift`, appended after `jsonRoundTrip` (line 93):
```swift
    /// A document written before 4b has no "crop" key and decodes with no crop; an uncropped
    /// document writes none; a crop round-trips; edits keep it.
    @Test func documentWithoutCropDecodes() throws {
        let old = try JSONDecoder().decode(AnnotationDocument.self, from: Data(#"{"annotations":[]}"#.utf8))
        #expect(old == AnnotationDocument(annotations: []))
        #expect(old.crop == nil)
        let json = try JSONEncoder().encode(mixed)
        let written = try #require(try JSONSerialization.jsonObject(with: json) as? [String: Any])
        #expect(!written.keys.contains("crop"))

        let crop = CGRect(x: 4, y: 6, width: 30, height: 20)
        let cropped = mixed.withCrop(crop)
        #expect(cropped != mixed)
        #expect(try JSONDecoder().decode(AnnotationDocument.self, from: JSONEncoder().encode(cropped)) == cropped)
        #expect(cropped.removing(id: boxID).crop == crop)
        #expect(cropped.moving(id: arrowID, by: CGVector(dx: 1, dy: 1)).crop == crop)
        #expect(cropped.withCrop(nil) == mixed)
    }
```

`TidyShotTests/RedactionExportTests.swift`. Give `pixel` (lines 73-76) a row width, so a cropped export can be read; every existing call keeps the default:
```swift
    func pixel(_ bytes: [UInt8], _ x: Int, _ y: Int, width: Int = RedactionExportTests.width) -> [UInt8] {
        let index = (y * width + x) * 4
        return Array(bytes[index..<index + 4])
    }
```
Append after `outsideEffectsEqualBaseAndScaleIsTwo`:
```swift
    /// The crop is applied after every effect, through the real renderer and a PNG round trip.
    /// A redaction cut by the crop's edge holds only the fill, every other kept pixel is the
    /// source at the crop's offset, and the PNG has the crop's size at scale 2: the size Save
    /// records as pixelWidth and pixelHeight.
    @Test func croppedExportKeepsRedactionAndHasCropSize() async throws {
        let secret = try add(.redact, from: CGPoint(x: 8, y: 8), to: CGPoint(x: 40, y: 32))
        let crop = CGRect(x: 20, y: 4, width: 36, height: 30)
        model.commit(model.document.withCrop(crop), actionName: EditorModel.ActionName.crop)
        let fill = model.redactColor
        let expected = [fill.red, fill.green, fill.blue, fill.alpha].map { UInt8(($0 * 255).rounded()) }

        let exported = try await exportedPixels()
        #expect(exported.scale == 2)
        #expect(exported.width == 36)
        #expect(exported.height == 30)

        let secretRect = try rect(of: secret)
        var redacted = 0
        var wrong = 0
        for position in positions(in: CGRect(origin: .zero, size: crop.size)) {
            let x = position.x + Int(crop.minX)
            let y = position.y + Int(crop.minY)
            let inside = secretRect.contains(CGPoint(x: CGFloat(x) + 0.5, y: CGFloat(y) + 0.5))
            if inside { redacted += 1 }
            let want = inside ? expected : pixel(source, x, y)
            if pixel(exported.bytes, position.x, position.y, width: exported.width) != want { wrong += 1 }
        }
        // The crop keeps 20 of the redaction's 32 columns and all 24 of its rows.
        #expect(redacted == 20 * 24)
        #expect(wrong == 0, "\(wrong) kept pixels are neither the fill inside the redaction nor the source outside it")
    }
```

The five existing RedactionExportTests still hold unchanged. They set no crop, `CropGeometry.integralCrop(nil, in:)` is nil, and the flattener then returns `context.makeImage()` exactly as before. The same goes for every EditorFlattenerTests case, `outputSizeEqualsBase` included.

`TidyShotTests/CanvasToolTests.swift`. In `FakeCanvasEditing`, after `var selection: UUID?` (line 20), add:
```swift
    var cropDraft: CGRect?
    var imageSize = CGSize(width: 64, height: 48)
```
Append to `CanvasToolTests`:
```swift
    @Test func cropToolResizesMovesAndClamps() {
        let canvas = FakeCanvasEditing()
        canvas.cropDraft = CGRect(x: 10, y: 10, width: 20, height: 10)
        let tool = makeTool(for: .crop)
        #expect(tool is CropTool)

        // The bottom-right handle dragged past the image's corner stops at it.
        tool.mouseDown(at(30, 20), on: canvas)
        tool.mouseDragged(at(90, 70), on: canvas)
        tool.mouseUp(at(90, 70), on: canvas)
        #expect(canvas.cropDraft == CGRect(x: 10, y: 10, width: 54, height: 38))

        // A press inside moves it, size kept, held inside the image.
        tool.mouseDown(at(20, 20), on: canvas)
        tool.mouseDragged(at(-10, 20), on: canvas)
        tool.mouseUp(at(-10, 20), on: canvas)
        #expect(canvas.cropDraft == CGRect(x: 0, y: 10, width: 54, height: 38))

        // A click outside changes nothing; a drag outside draws a new rect.
        tool.mouseDown(at(62, 2), on: canvas)
        tool.mouseUp(at(62, 2), on: canvas)
        #expect(canvas.cropDraft == CGRect(x: 0, y: 10, width: 54, height: 38))
        tool.mouseDown(at(62, 2), on: canvas)
        tool.mouseDragged(at(40, 30), on: canvas)
        tool.mouseUp(at(40, 30), on: canvas)
        #expect(canvas.cropDraft == CGRect(x: 40, y: 2, width: 22, height: 28))

        // Escape (the draft cleared mid-drag) ends the gesture; the tool never commits.
        tool.mouseDown(at(50, 15), on: canvas)
        canvas.cropDraft = nil
        tool.mouseDragged(at(55, 20), on: canvas)
        tool.mouseUp(at(55, 20), on: canvas)
        #expect(canvas.cropDraft == nil)
        #expect(canvas.commits.isEmpty)
    }
```

`TidyShotTests/EditorWindowGeometryTests.swift`: no new test. In Task 1's `toolbarWithEveryToolFitsASmallDisplay`, replace the two pinned lines Task 3 left (11 and 980) with the twelve-tool values (six segments of 36 pt more than 4a's 800; recompute if Task 1 changed `ToolbarMetrics`):
```swift
        #expect(EditorTool.toolbarOrder.count == 12)
        #expect(width(segments: EditorTool.toolbarOrder.count) == 1016)
```
Its last assertion still holds: 1016 pt is under 90 % of a 1280 pt display (1152).

That is 9 new tests: CropGeometryTests 4 (new suite), EditorModelTests 2, AnnotationDocumentTests 1, RedactionExportTests 1, CanvasToolTests 1. No test is removed or renamed.

- [ ] **Step 2: Run the tests to verify they fail**

Run:
```bash
xcodegen generate && xcodebuild test -project TidyShot.xcodeproj -scheme TidyShot -destination 'platform=macOS' -derivedDataPath .build 2>&1 | grep -E "Test run with|error:|TEST"
```
Expected: compile errors, among them `cannot find 'CropGeometry' in scope`, `value of type 'AnnotationDocument' has no member 'withCrop'` and `type 'EditorTool' has no member 'crop'`.

- [ ] **Step 3: The model: `crop` on the document and the Crop tool case**

`TidyShot/Editor/Model/AnnotationDocument.swift`. After `var annotations: [Annotation] = []` (line 7) add:
```swift
    /// The part of the capture export keeps, in image pixels (top-left origin), as
    /// `CropGeometry.integralCrop` gives it: whole pixels, inside the image, never the whole image.
    /// Nil keeps the whole capture. `EditorFlattener` applies it last. Optional, so the synthesized
    /// decoder reads it with `decodeIfPresent` and a document without the key has no crop.
    var crop: CGRect? = nil
```
After `moving(id:by:)` (ends line 44) add:
```swift
    func withCrop(_ crop: CGRect?) -> AnnotationDocument {
        var copy = self
        copy.crop = crop
        return copy
    }
```
The other edits copy `self`, so they keep the crop. `AnnotationDocument(annotations:)` and `AnnotationDocument()` still compile, since `crop` has a default.

`TidyShot/Editor/Model/EditorTool.swift`. Append `crop` to the case list (line 4) after the cases Tasks 1 to 3 added, and give it an arm in each switch:
- `letter` (7-15): `case .crop: "C"`
- `title` (18-27): `case .crop: "Crop"`
- `symbolName` (30-39): `case .crop: "crop"`
- `isEffect` (45-50): add `.crop` to the `false` arm.
- `toolbarOrder` (54-56): append `.crop` as the last element, after every drawing tool.

`EditorToolTests` already covers the case: unique letters, the SF Symbol and tool tip (`Crop (C)`), not an effect, and in the toolbar once.

- [ ] **Step 4: The geometry**

`TidyShot/Editor/Geometry/HitTester.swift:119`. Drop `private` from `boxHandles`, so the crop shares the box handle order:
```swift
    /// The eight box handles of `rect`, in the order `handles(for:)` documents.
    static func boxHandles(_ rect: CGRect) -> [CGPoint] {
```

`TidyShot/Editor/Geometry/CropGeometry.swift` (new):
```swift
import CoreGraphics
import Foundation

/// The crop rect, in image pixels with a top-left origin. The model stores `integralCrop` output and
/// the flattener crops to `integralCrop` again, so the readout, the document and the export agree
/// on the pixels kept.
nonisolated enum CropGeometry {
    /// `rect` standardized and cut to an image of `imageSize`; `.zero` when nothing of it is inside.
    static func clamped(_ rect: CGRect, to imageSize: CGSize) -> CGRect {
        guard !rect.isNull, !rect.isInfinite else { return .zero }
        let cut = rect.standardized.intersection(CGRect(origin: .zero, size: imageSize))
        return cut.isEmpty ? .zero : cut
    }

    /// `rect` moved by `delta` with its size kept, then pushed back inside the image. A rect larger
    /// than the image is clamped instead.
    static func moved(_ rect: CGRect, by delta: CGVector, within imageSize: CGSize) -> CGRect {
        let r = rect.standardized
        guard r.width <= imageSize.width, r.height <= imageSize.height else { return clamped(r, to: imageSize) }
        let x = min(max(r.minX + delta.dx, 0), imageSize.width - r.width)
        let y = min(max(r.minY + delta.dy, 0), imageSize.height - r.height)
        return CGRect(x: x, y: y, width: r.width, height: r.height)
    }

    /// Each edge of `rect` rounded to the nearest whole pixel, then cut to the image; `.zero` when
    /// nothing is left. These are the pixels export keeps, and what the readout counts.
    static func snapped(_ rect: CGRect, in imageSize: CGSize) -> CGRect {
        guard !rect.isNull, !rect.isInfinite else { return .zero }
        let r = rect.standardized
        let minX = r.minX.rounded()
        let minY = r.minY.rounded()
        let edges = CGRect(x: minX, y: minY, width: r.maxX.rounded() - minX, height: r.maxY.rounded() - minY)
        return clamped(edges, to: imageSize)
    }

    /// What the document stores and export crops to: `snapped`, or nil when there is no crop,
    /// nothing is left, or the whole image is kept. A crop dragged back to the whole capture
    /// therefore stores nil and changes nothing.
    static func integralCrop(_ rect: CGRect?, in imageSize: CGSize) -> CGRect? {
        guard let rect else { return nil }
        let kept = snapped(rect, in: imageSize)
        guard !kept.isEmpty, kept != CGRect(origin: .zero, size: imageSize) else { return nil }
        return kept
    }

    /// The readout beside the crop: width and height in image pixels, for example "1280 × 720".
    static func readout(for rect: CGRect) -> String {
        "\(Int(rect.width.rounded())) × \(Int(rect.height.rounded()))"
    }

    /// The nearest of `rect`'s eight handles (`HitTester.boxHandles` order) within `tolerance`.
    static func handle(of rect: CGRect, at point: CGPoint, tolerance: CGFloat) -> Int? {
        var best: (index: Int, distance: CGFloat)?
        for (index, handle) in HitTester.boxHandles(rect).enumerated() {
            let distance = hypot(point.x - handle.x, point.y - handle.y)
            if distance <= tolerance, distance < (best?.distance ?? .infinity) {
                best = (index, distance)
            }
        }
        return best?.index
    }
}
```

- [ ] **Step 5: The flattener applies the crop last**

`TidyShot/Editor/Rendering/EditorFlattener.swift`. In the type comment (lines 5-6), change "at the capture's own pixel size" to "at the capture's own pixel size, or at the crop's when the document has one". Replace `return context.makeImage()` (line 48) with:
```swift
        guard let flattened = context.makeImage() else { return nil }
        // 4. The crop, last. Effects and drawings render on the whole capture first, so a blur or a
        // redaction cut by the crop's edge has exactly the pixels it has uncropped. CGImage's
        // `cropping(to:)` takes the model's top-left rect as it is.
        guard let crop = CropGeometry.integralCrop(document.crop, in: size) else { return flattened }
        return flattened.cropping(to: crop)
```
A nil from `cropping(to:)` fails the export, which beeps (EditorWindowController.swift:271-275), as a missing tile does.

- [ ] **Step 6: The model's crop draft, Return and Escape**

`TidyShot/Editor/Tools/CanvasTool.swift`. In `protocol CanvasEditing` (lines 21-32), after `var selection: UUID? { get set }` add:
```swift
    /// The Crop tool's rect while cropping (4b), in image pixels; nil otherwise. Never undoable:
    /// Return applies it as one commit, Escape drops it.
    var cropDraft: CGRect? { get set }
    /// The capture's size in image pixels.
    var imageSize: CGSize { get }
```

`TidyShot/Editor/Session/EditorModel.swift`:
- `ActionName` (lines 21-28): add `static let crop = "Crop"`.
- Replace `hasUnsavedChanges` (line 39; Task 3 made it `document != savedDocument || textEditChangesDocument`) with:
```swift
    /// Also true while typed text would change the document (Task 3) and while a crop draft would
    /// change the crop, so the edited dot, the close sheet and the quit review see a text or a crop
    /// that has not been committed yet (`AppCoordinator.hasUnsavedEditors` reads this).
    var hasUnsavedChanges: Bool {
        if document != savedDocument || textEditChangesDocument { return true }
        guard let cropDraft else { return false }
        return CropGeometry.integralCrop(cropDraft, in: imageSize) != document.crop
    }
```
  Task 3's `textEditCommitsOnceWithoutEditorUndo` and this task's `escapeCancelsCropAndAnotherToolApplies` both check it.
- After `transient` (ends line 51) add:
```swift
    /// The Crop tool's rect while it is active; nil otherwise. Not part of the document or of undo.
    var cropDraft: CGRect?
    var imageSize: CGSize { CGSize(width: base.width, height: base.height) }
```
- Replace the `tool` property (lines 53-55, as Task 3 left it), keeping Task 3's `commitTextEditing()`:
```swift
    /// Redaction is the reason the editor exists, so it opens with Redact. A tool change commits the
    /// text being typed and applies a crop draft.
    var tool: EditorTool = .redact {
        didSet {
            guard tool != oldValue else { return }
            transient = nil
            commitTextEditing()
            // Leaving Crop for another tool keeps the draft, as one step; Escape drops it.
            if oldValue == .crop { applyCropDraft() }
            if tool == .crop {
                toolBeforeCrop = oldValue
                selection = nil
                cropDraft = document.crop ?? CGRect(origin: .zero, size: imageSize)
            }
        }
    }
```
- Next to `coalescingKey` (line 67) add:
```swift
    /// Where Return and Escape go back to when they end cropping.
    @ObservationIgnored private var toolBeforeCrop: EditorTool = .select
```
- In `makeAnnotation` (lines 137-139), change `case .select:` to `case .select, .crop:`, which returns nil.
- Replace `cancelCurrentOperation()` (lines 175-182):
```swift
    /// Escape and ⌘.: while cropping, drop the draft (`cancelCrop()`); otherwise abandon the shape
    /// being drawn, else deselect. Never closes the window.
    func cancelCurrentOperation() {
        if tool == .crop {
            cancelCrop()
        } else if transient != nil {
            transient = nil
        } else {
            selection = nil
        }
    }
```
- In `selectAll()` (lines 185-187), add `guard tool != .crop else { return }` as its first line, since cropping shows no selection.
- After `selectAll()` add:
```swift
    // MARK: Crop

    /// Return while cropping: applies the draft as one step named `Crop`, then goes back to the tool
    /// used before Crop. Does nothing outside Crop, so `export()` can call it unconditionally.
    func applyCrop() {
        guard tool == .crop else { return }
        applyCropDraft()
        tool = toolBeforeCrop
    }

    /// Escape while cropping: drops the draft, leaves the document unchanged, and goes back to the
    /// tool used before Crop.
    func cancelCrop() {
        guard tool == .crop else { return }
        cropDraft = nil
        tool = toolBeforeCrop
    }

    /// Ends the draft. A draft that keeps the whole capture stores nil; `commit` adds no step when
    /// the crop is unchanged.
    private func applyCropDraft() {
        guard let draft = cropDraft else { return }
        cropDraft = nil
        commit(document.withCrop(CropGeometry.integralCrop(draft, in: imageSize)), actionName: ActionName.crop)
    }
```
`applyCrop()` sets `tool`, and `tool`'s `didSet` calls `applyCropDraft()` again; the draft is already nil by then, so nothing more happens.

`TidyShot/Editor/Window/EditorWindowController.swift`, `export()` (lines 269-277). Make the first line:
```swift
        // A crop still being edited is what the window shows, so it is applied (one undo step) first.
        model.applyCrop()
```
Copy, Save, Save As… and Upload all export through here. A close or a quit with a draft gets the unsaved-changes sheet through `hasUnsavedChanges`, and its Save exports through here too.

- [ ] **Step 7: The Crop tool**

`TidyShot/Editor/Tools/CropTool.swift` (new):
```swift
import AppKit

/// Crop (C). Edits `canvas.cropDraft`, which the model sets to the applied crop, or the whole
/// capture, when the tool is picked. A press on one of the draft's eight handles resizes it (Shift
/// squares a corner), a press inside moves it (Shift keeps the dominant axis), and a press outside
/// drags out a new rect (Shift squares, Option grows it from the press point). Every rect stays
/// inside the image. The tool never commits: Return applies the draft as one undo step
/// (`EditorModel.applyCrop()`), Escape drops it, and picking another tool applies it.
final class CropTool: CanvasTool {
    private enum Gesture {
        /// `from` is where the handle sat at the press, so the handle keeps the grab offset.
        case resize(original: CGRect, handle: Int, from: CGPoint)
        case move(original: CGRect)
        /// A new rect from the press point; `original` stays until the new rect is large enough.
        case draw(original: CGRect)
    }

    private var gesture: Gesture?
    private var start = CGPoint.zero
    private var current = CGPoint.zero
    /// True once the pointer has travelled 2/zoom px, so a click changes nothing.
    private var hasMoved = false
    /// What this tool last put in `canvas.cropDraft`, or the draft at the press. Anything else
    /// there means Escape ended cropping, and the tool drops the gesture.
    private var shown: CGRect?

    var cursor: NSCursor { .crosshair }

    func mouseDown(_ input: ToolInput, on canvas: any CanvasEditing) {
        gesture = nil
        hasMoved = false
        start = input.point
        current = input.point
        shown = canvas.cropDraft
        guard let draft = canvas.cropDraft else { return }
        if let handle = CropGeometry.handle(of: draft, at: input.point, tolerance: HitTester.tolerance(zoom: canvas.zoom)) {
            gesture = .resize(original: draft, handle: handle, from: HitTester.boxHandles(draft)[handle])
        } else if draft.contains(input.point) {
            gesture = .move(original: draft)
        } else {
            gesture = .draw(original: draft)
        }
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
        gesture = nil
        shown = nil
        hasMoved = false
    }

    private func update(_ input: ToolInput, on canvas: any CanvasEditing) {
        guard let gesture else { return }
        guard canvas.cropDraft == shown else {
            self.gesture = nil
            shown = nil
            return
        }
        if !hasMoved {
            guard DragGeometry.isLongEnough(from: start, to: current, zoom: canvas.zoom) else { return }
            hasMoved = true
        }
        let size = canvas.imageSize
        let delta = CGVector(dx: current.x - start.x, dy: current.y - start.y)
        let next: CGRect
        switch gesture {
        case .resize(let original, let handle, let from):
            let to = CGPoint(x: from.x + delta.dx, y: from.y + delta.dy)
            next = CropGeometry.clamped(HitTester.resizedRect(original, handle: handle, to: to, square: input.shift), to: size)
        case .move(let original):
            next = CropGeometry.moved(original, by: input.shift ? DragGeometry.axisLocked(delta) : delta, within: size)
        case .draw(let original):
            let drawn = CropGeometry.clamped(DragGeometry.rect(from: start, to: current, square: input.shift,
                                                               fromCentre: input.option), to: size)
            next = DragGeometry.isLargeEnough(drawn, zoom: canvas.zoom) ? drawn : original
        }
        // A handle dragged wholly off the image leaves nothing to keep: the last rect stays.
        guard DragGeometry.isLargeEnough(next, zoom: canvas.zoom), next != shown else { return }
        shown = next
        canvas.cropDraft = next
    }
}
```

`TidyShot/Editor/Tools/ToolFactory.swift` (lines 6-12): add `case .crop: return CropTool()`.

- [ ] **Step 8: The crop chrome and the cover**

`TidyShot/Editor/Rendering/AnnotationDrawing.swift`:
- Move the handle loop out of `drawSelection` (lines 68-76) into this function, and call it there as `drawHandles(HitTester.handles(for: annotation), transform: transform, scale: scale, in: context)`:
```swift
    /// An 8 pt white square with a dark border at each of `points` (image pixels), in view space.
    /// `scale` is the view's backing scale factor; edges snap to device pixels.
    static func drawHandles(_ points: [CGPoint], transform: CanvasTransform, scale: CGFloat, in context: CGContext) {
        let device = max(scale, 1)
        func snap(_ value: CGFloat) -> CGFloat { (value * device).rounded() / device }
        let half = handleSide / 2
        context.saveGState()
        defer { context.restoreGState() }
        context.setLineWidth(1)
        for point in points {
            let centre = transform.viewPoint(point)
            let square = CGRect(x: snap(centre.x - half), y: snap(centre.y - half), width: handleSide, height: handleSide)
            context.setFillColor(CGColor(gray: 1, alpha: 1))
            context.fill(square)
            context.setStrokeColor(CGColor(gray: 0, alpha: 0.6))
            context.stroke(square.insetBy(dx: 0.5, dy: 0.5))
        }
    }
```
- Add after `drawSelection`:
```swift
    /// How dark the image outside a crop being edited gets: black at this alpha.
    static let cropDimAlpha: CGFloat = 0.5

    /// The Crop tool's chrome, in view space: the image outside `crop` dimmed, a 1 pt white edge on
    /// the crop, and its eight handles. `scale` is the view's backing scale factor.
    static func drawCropChrome(crop: CGRect, imageSize: CGSize, transform: CanvasTransform, scale: CGFloat,
                               in context: CGContext) {
        let image = snapped(transform.viewRect(CGRect(origin: .zero, size: imageSize)), scale: scale)
        let kept = snapped(transform.viewRect(crop), scale: scale)
        context.saveGState()
        defer { context.restoreGState() }
        context.addRect(image)
        context.addRect(kept)
        context.setFillColor(CGColor(gray: 0, alpha: cropDimAlpha))
        context.fillPath(using: .evenOdd)
        context.setLineWidth(1)
        context.setStrokeColor(CGColor(gray: 1, alpha: 1))
        context.stroke(kept.insetBy(dx: 0.5, dy: 0.5))
        drawHandles(HitTester.boxHandles(crop), transform: transform, scale: scale, in: context)
    }

    /// An applied crop, outside the Crop tool: everything in `bounds` (view space) outside `crop`
    /// is painted `color`, the window's background, so the canvas shows what export keeps. Drawings
    /// and tiles beneath are hidden, not removed.
    static func drawCropCover(keeping crop: CGRect, bounds: CGRect, transform: CanvasTransform, color: CGColor,
                              scale: CGFloat, in context: CGContext) {
        context.saveGState()
        defer { context.restoreGState() }
        context.addRect(bounds)
        context.addRect(snapped(transform.viewRect(crop), scale: scale))
        context.setFillColor(color)
        context.fillPath(using: .evenOdd)
    }

    /// `rect`'s edges on device pixels at `scale`.
    private static func snapped(_ rect: CGRect, scale: CGFloat) -> CGRect {
        let device = max(scale, 1)
        func snap(_ value: CGFloat) -> CGFloat { (value * device).rounded() / device }
        return CGRect(x: snap(rect.minX), y: snap(rect.minY),
                      width: snap(rect.maxX) - snap(rect.minX), height: snap(rect.maxY) - snap(rect.minY))
    }
```

- [ ] **Step 9: The canvas**

`TidyShot/Editor/Window/CanvasView.swift`. The implementer writes the view code to this structure:
- `Shown` (lines 10-15) gains `var cropDraft: CGRect?`. Both places that build it, `init` (40-41) and `refresh()` (271-272), pass `cropDraft: model.cropDraft`.
- `observeModel()` (249-255) also reads `_ = model.cropDraft`, so a draft the tool changes, and the start or end of cropping, repaint.
- Add the rect Fit shows, and use it in `fitToView()` (lines 67-71):
```swift
    /// What Fit shows: the whole capture while cropping or with no crop, else the applied crop.
    private func fitRect(document: AnnotationDocument, cropDraft: CGRect?) -> CGRect {
        let whole = CGRect(origin: .zero, size: imagePixelSize)
        return cropDraft == nil ? (document.crop ?? whole) : whole
    }

    /// `fitRect` inside the view with `EditorWindowGeometry.inset` on every side, never above
    /// natural size; kept on resize.
    func fitToView() {
        guard bounds.width > 0, bounds.height > 0 else { return }
        let shown = fitRect(document: model.document, cropDraft: model.cropDraft)
        let fit = CanvasTransform.fitting(imagePixelSize: shown.size, in: bounds.size, inset: EditorWindowGeometry.inset,
                                          captureScale: model.scale)
        apply(fit.panned(by: CGPoint(x: -shown.minX * fit.zoom, y: -shown.minY * fit.zoom)), fits: true)
    }
```
- `refresh()` (265-295). Add `now.cropDraft == previous.cropDraft` to the partial-repaint condition at line 289, so any crop change repaints the whole view (the readout sits outside the crop). As the last statement, refit when what Fit shows changed:
```swift
        if fitsOnResize, fitRect(document: now.document, cropDraft: now.cropDraft)
            != fitRect(document: previous.document, cropDraft: previous.cropDraft) {
            fitToView()
        }
```
  `fitToView()` calls `refresh()` again through `apply`. `shown` is already `now` by then, so the inner call only moves the transform and does not refit again.
- Return. After `cancelOperation(_:)` (ends line 211):
```swift
    /// Return and Enter: apply the crop being edited and go back to the tool used before Crop.
    /// NSResponder does not implement insertNewline:, so outside Crop this beeps as an unhandled
    /// Return did before; super is not called.
    override func insertNewline(_ sender: Any?) {
        guard model.tool == .crop, !isTrackingMouse else {
            NSSound.beep()
            return
        }
        model.applyCrop()
        refresh()
    }
```
  Task 3 does not override `insertNewline(_:)` on the canvas: while text is typed the NSTextView is first responder and its delegate (`textView(_:doCommandBy:)`) takes Return, so this override never sees a Return meant for text. Escape needs no change: `cancelOperation(_:)` (202-211) already abandons the drag by replacing the tool, then calls `model.cancelCurrentOperation()`, which now ends cropping.
- `draw(_:)` (382-401). After `context.restoreGState()` (line 395), replace the selection block with:
```swift
        if let draft = model.cropDraft {
            // Cropping: dim, edge, handles and readout; no selection is shown.
            AnnotationDrawing.drawCropChrome(crop: draft, imageSize: imagePixelSize, transform: transform,
                                             scale: backingScale, in: context)
            drawCropReadout(for: draft)
            return
        }
        if let crop = model.document.crop {
            // Resolved under the view's appearance, which AppKit makes current inside draw(_:).
            AnnotationDrawing.drawCropCover(keeping: crop, bounds: bounds, transform: transform,
                                            color: NSColor.windowBackgroundColor.cgColor, scale: backingScale, in: context)
        }
        if let selected = selectedAnnotation {
            // (the existing drawSelection call, unchanged)
        }
```
- The readout, MainActor AppKit text in the flipped view:
```swift
    /// "W × H" in image pixels, the size export will write, in a dark pill 6 pt under the crop's
    /// bottom-left corner, or inside the crop's bottom edge when the pill would leave the view.
    private func drawCropReadout(for draft: CGRect) {
        let label = NSAttributedString(
            string: CropGeometry.readout(for: CropGeometry.snapped(draft, in: imagePixelSize)),
            attributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium),
                         .foregroundColor: NSColor.white])
        let text = label.size()
        let pill = CGSize(width: ceil(text.width) + 12, height: ceil(text.height) + 6)
        let crop = model.transform.viewRect(draft)
        var origin = CGPoint(x: crop.minX, y: crop.maxY + 6)
        if origin.y + pill.height > bounds.maxY { origin.y = crop.maxY - pill.height - 6 }
        origin.x = min(max(origin.x, bounds.minX + 4), bounds.maxX - pill.width - 4)
        let frame = CGRect(origin: origin, size: pill)
        NSColor.black.withAlphaComponent(0.7).setFill()
        NSBezierPath(roundedRect: frame, xRadius: 4, yRadius: 4).fill()
        label.draw(at: CGPoint(x: frame.minX + 6, y: frame.minY + 3))
    }
```

No change is needed for the tool swap: `refresh()` already builds `makeTool(for: model.tool)` when the tool changes and no drag runs (266-270), and Return or Escape mid-drag only lands after `mouseUp`.

- [ ] **Step 10: Run the suite**

Run:
```bash
xcodegen generate && xcodebuild test -project TidyShot.xcodeproj -scheme TidyShot -destination 'platform=macOS' -derivedDataPath .build 2>&1 | grep -E "Test run with|error:|TEST"
```
Expected: no `error:` lines, and `Test run with 446 tests in 55 suites passed`.

- [ ] **Step 11: Check by hand**

```bash
xcodebuild -project TidyShot.xcodeproj -scheme TidyShot -configuration Debug -derivedDataPath .build build -quiet && open .build/Build/Products/Debug/TidyShot.app
```
Capture an area on a Retina screen and open it with the overlay's Annotate button. Expected:
1. The tools group ends with Crop (`crop` symbol, tool tip `Crop (C)`). At the window's minimum width every segment and every button shows, with no overflow chevron.
2. Draw a rectangle, select it, press C. The selection goes. Handles sit at the image's corners and edge midpoints, nothing is dimmed, and the readout shows the capture's pixel size (twice its point size). The window shows no edited dot for the crop yet.
3. Drag the bottom-right handle in. The outside dims at half black and the readout follows in whole pixels. Drag past the image's edge: the crop stops at the edge. Drag inside to move it (Shift locks the axis), and drag outside to draw a new one (Shift squares, Option grows it from the centre). The edited dot appears.
4. Press Return. The canvas shows only the crop, fitted, with the window background around it, and the tool is back to Rectangle. The Edit menu's undo (or ⌘Z) restores the whole capture, refitted, and ⇧⌘Z crops again.
5. Press C: the draft starts at the applied crop. Change it and press Escape: nothing changes, and the tool returns. Press C, change it, press V: the crop applies as one `Crop` step.
6. Redact across the crop's edge, crop, then ⌘S. The saved file opens in Preview at the readout's size, and the redaction is solid up to the crop's edge. The Recent Captures thumbnail shows the crop, and in `~/Library/Containers/io.tky.tidyshot/Data/Library/Application Support/TidyShot/history.json` the record's `pixelWidth` and `pixelHeight` equal the readout.
7. With a crop drafted but not applied, press ⌘C, then use Preview's New from Clipboard: the image is the crop's size, and the crop is now applied (one undo step). Close with a new unapplied draft: the unsaved-changes sheet asks.
8. Upload: the uploaded object opens at the crop's size. Save As… to a new file: the file is the crop's size, and the record and its thumbnail stay as they were.
9. Switch to Dark appearance with a crop applied: the cover matches the window background in both appearances.

- [ ] **Step 12: Commit**

```bash
git add TidyShot/Editor/Geometry/CropGeometry.swift TidyShot/Editor/Tools/CropTool.swift TidyShot/Editor/Model/AnnotationDocument.swift TidyShot/Editor/Model/EditorTool.swift TidyShot/Editor/Geometry/HitTester.swift TidyShot/Editor/Rendering/EditorFlattener.swift TidyShot/Editor/Rendering/AnnotationDrawing.swift TidyShot/Editor/Session/EditorModel.swift TidyShot/Editor/Tools/CanvasTool.swift TidyShot/Editor/Tools/ToolFactory.swift TidyShot/Editor/Window/CanvasView.swift TidyShot/Editor/Window/EditorWindowController.swift TidyShotTests/CropGeometryTests.swift TidyShotTests/EditorModelTests.swift TidyShotTests/AnnotationDocumentTests.swift TidyShotTests/RedactionExportTests.swift TidyShotTests/CanvasToolTests.swift TidyShotTests/EditorWindowGeometryTests.swift
git commit -m "feat: crop in the editor"
```

### Task 5: Duplicate, object copy and paste, Space-drag pan and canvas accessibility

**Files:**
- Create: `TidyShot/Editor/Persistence/AnnotationClip.swift`
- Create: `TidyShot/Editor/Geometry/CanvasAccessibility.swift`
- Create: `TidyShot/Editor/Window/AnnotationAccessibilityElement.swift`
- Modify: `TidyShot/Editor/Model/Annotation.swift` (after `moved(by:)`, Annotation.swift:74-94 on `main`)
- Modify: `TidyShot/Editor/Geometry/KeyRouting.swift` (`KeyRouting` at :8-43, `EditorShortcut` at :45-117)
- Modify: `TidyShot/Editor/Tools/ToolFactory.swift` (`commitNewShape`, :14-22)
- Modify: `TidyShot/Editor/Tools/SelectTool.swift` (whole file, :1-103)
- Modify: `TidyShot/Editor/Session/EditorModel.swift` (`ActionName` :21-28, the selection section :160-191)
- Modify: `TidyShot/Editor/Window/CanvasView.swift` (state :17-33, :54-59, pointer :132-154, cursor :177-179, keys :183-240, `refresh()` :265-295)
- Modify: `TidyShot/Editor/Window/EditorWindowController.swift` (`EditorActions` :9-17, `init` :43-76, `copy(_:)` :167-172, delegate methods :354-360)
- Modify: `TidyShot/Output/Pasteboard.swift` (before `write(_:)`, :65-72)
- Modify: `TidyShot/App/AppCoordinator.swift` (`editorActions(for:)`, :1036-1053, under `// MARK: Editor`)
- Test: `TidyShotTests/AnnotationClipTests.swift` (create)
- Test: `TidyShotTests/CanvasAccessibilityTests.swift` (create)
- Test: `TidyShotTests/EditorModelTests.swift` (`makeModel` :17-26; four tests appended)
- Test: `TidyShotTests/CanvasToolTests.swift` (two tests appended to `CanvasToolTests`)
- Test: `TidyShotTests/KeyRoutingTests.swift` (`shortcutTableMatchesExpectedChords` :80-112, `editingTextPassesClipboardAndUndoChordsThrough` :126-146; one test appended)

Line numbers are on `main` at 9193586. Tasks 1 to 4 shift them; find each place by the symbol named.

Annotate from Recent Captures is not part of this task: it shipped in 4a.

**Interfaces:**
- Consumes:
  - `main`: `Annotation` (`id`, `title`, `isEffect`, `moved(by:)`), `ShapeBox`, `Segment`, `Region`, `AnnotationDocument` (`annotations`, `effects`, `drawings`, `annotation(id:)`, `appending(_:)`, `replacing(_:)`), `AnnotationGeometry.bounds(of: Annotation, scale: CGFloat) -> CGRect`, `HitTester.hit/topmost/handles/resized/tolerance`, `DragGeometry.isLongEnough/axisLocked`, `protocol CanvasEditing`, `ToolInput`, `makeTool(for:)`, `extension CanvasEditing { func commitNewShape(_:) }`, `EditorModel` (`commit`, `selection`, `transient`, `scale`, `base`, `undoManager`, private `selectedAnnotation`), `CanvasView` (`isEditingText`, `apply(_:fits:)`, `refresh()`, `imageBounds(of:)`, `isTrackingMouse`), `EditorWindow.performKeyEquivalent` as Task 3 left it (this task does not change it: its `send(_:)` sends a matched row's selector to `NSApp.target(forAction:to:nil,from:)` and beeps when there is no target or validation fails; while text is typed, a chord no row matches goes to `TextEditingChord`, then to super), `EditorActions`, `Pasteboard.write(_:)`, `CanvasTransform.panned(by:)`.
  - Task 1: `Annotation.ellipse(ShapeBox)`, `Annotation.line(Segment)`, titles `Ellipse` and `Line`.
  - Task 2: `struct Stroke { let id: UUID; var points: [CGPoint]; var color: RGBA; var lineWidth: CGFloat }`, `Annotation.pencil(Stroke)`, `.highlighter(Stroke)`.
  - Task 3: `struct TextBox { let id: UUID; var string: String; var origin: CGPoint; var fontSize: CGFloat; var color: RGBA }` with `fontSize` in image pixels (checked against Task 3: these are its field names), `Annotation.text(TextBox)` with title `Text`, `CanvasView.isEditingText` (computed from `model.isEditingText`), `KeyRouting.action(…, isEditingText:, tool: EditorTool = .select)` and the `KeyRoutingTests.action` helper with its `tool:` parameter, `TextEditingChord` (⌘C, ⌘X, ⌘V, ⌘A, ⌘Z, ⇧⌘Z sent to the text view), the double-click branch in `SelectTool.mouseDown`, and the text-commit lines at the start of `CanvasView.mouseDown` and in `keyDown`'s `.textSize` case. Keep all of them where this task edits the same members.
  - Task 4: `CanvasEditing.cropDraft` and `imageSize` (and `FakeCanvasEditing`'s), `EditorModel.imageSize`, and the rule that cropping shows no selection (picking Crop clears it, `selectAll()` does nothing while cropping).
  - Every earlier 4b task extended `moved(by:)` and `AnnotationGeometry.bounds(of:scale:)` for its case. `Annotation` then has ten cases (rectangle, ellipse, arrow, line, pencil, highlighter, text, redact, blur, pixelate; Select and Crop make none), and `withID(_:)` and `scaled(by:)` below switch over all ten with no default.
- Produces:
  - `Annotation.withID(_ id: UUID) -> Annotation` and `Annotation.scaled(by factor: CGFloat) -> Annotation`.
  - `nonisolated struct AnnotationClip: Codable, Equatable, Sendable { var formatVersion: Int; var annotation: Annotation; var scale: CGFloat }` with `static let pasteboardTypeName = "io.tky.tidyshot.annotation"`, `static let currentFormatVersion = 1`, `static let maximumCascade = 100`, `init(annotation:scale:)`, `func encoded() -> Data?`, `static func decoded(from: Data) -> AnnotationClip?`, `func placed(in:imageSize:scale:step:id:) -> Annotation`.
  - `nonisolated enum CanvasAccessibility { static let canvasLabel = "Annotation canvas"; struct Item: Equatable, Sendable { let id: UUID; let label: String; let value: String? }; static func items(in: AnnotationDocument) -> [Item]; static func value(of: Annotation) -> String? }`.
  - `KeyRouting.isPanKey(characters: String?, command: Bool, control: Bool, option: Bool, isEditingText: Bool) -> Bool`.
  - `EditorShortcut.paste` (⌘V, `paste:`) and `EditorShortcut.duplicate` (⌘D, `duplicate:`), both passing through while text is edited. ⌘X still has no row.
  - `extension CanvasEditing { func commitNewShape(_ shape: Annotation, actionName: String? = nil) }` (nil keeps `Add <title>`).
  - `EditorModel.duplicateOffsetPoints: CGFloat = 10` (static), `EditorModel.duplicateOffset: CGVector`, `duplicateSelection()`, `objectClip() -> AnnotationClip?`, `paste(_ clip: AnnotationClip)`. Undo names `Duplicate <title>` and `Paste <title>`.
  - SelectTool: Option during a move drag (pressed at mouseDown or later, via `flagsChanged`) drags a copy; mouseUp commits it once as `Duplicate <title>` and selects it.
  - `struct EditorObjectClipboard { var copy: (Data) -> Void; var paste: () -> Data?; var canPaste: () -> Bool }` and `EditorActions.objectClipboard: EditorObjectClipboard`.
  - `Pasteboard.annotationClipType`, `Pasteboard.copy(annotationClip:) -> Int`, `Pasteboard.annotationClipData() -> Data?`, `Pasteboard.hasAnnotationClip: Bool`.
  - `CanvasView`: `var objectClipboard: EditorObjectClipboard?`, `@objc copy(_:)`, `@objc paste(_:)`, `@objc duplicate(_:)`, `func endSpacePan()`, `func selectFromAccessibility(_ id: UUID) -> Bool`, `func accessibilityScreenFrame(of id: UUID) -> NSRect`, `func isAccessibilitySelected(_ id: UUID) -> Bool`, and an `NSAccessibilityElement` child per annotation (`final class AnnotationAccessibilityElement`).
  - Task 6 adds the hand checks below to the 4b checklist and the strings `Annotation canvas`, `Duplicate <title>` and `Paste <title>` to spec 2.6.

Decisions this task pins down (spec 2.6 gives the behaviour, not these details):
- **⌘D** duplicates the selected annotation (document copy, never the transient) 10 pt (`10 * scale` image pixels) down and to the right, appends it (so it is front-most in its layer, and an effect's copy is the newest effect), selects it, and is one undo step `Duplicate <title>`. Pressing ⌘D again duplicates the copy, so copies step diagonally. Nothing selected: CanvasView does not respond to `duplicate:`, so EditorWindow finds no target and beeps. The tool does not change.
- **⌥-drag** (Select tool, a drag that starts on an annotation's body or on another annotation's handle) moves a copy and leaves the original where it is. Option is live, as spec 2.6 Tools says for every modifier: pressing or releasing it mid-drag (`flagsChanged`) swaps between the copy and a plain move, and the copy keeps one id for the whole gesture. A drag on the selection's own handle is a resize, and Option has no effect there. An ⌥-click that never passes the tiny-drag rule changes nothing. The selection stays on the original during the drag and moves to the copy on mouseUp.
- **⌘C** with a selection: CanvasView writes the `AnnotationClip` of the selected annotation under the private type `io.tky.tidyshot.annotation` only (JSON). There is no image or text representation, so pasting into another app pastes nothing; the toolbar Copy button and ⇧⌘C still copy the flattened image. No notification, and `clipboardOwner` is not set: the write moves the change count, so the clipboard rule leaves the object alone after a later Save. With nothing selected CanvasView does not respond to `copy:`, so `NSApp.target(forAction:)` lands on EditorWindowController exactly as in 4a (validation, `Image copied`). The `copy:` row of the table does not change.
- **⌘V**: CanvasView responds to `paste:` only while the pasteboard holds the private type (a type check, which reads no data). It decodes the clip, places it with `AnnotationClip.placed`, commits `Paste <title>` as one step and selects it. The pasteboard is the general one, so a copy from one editor window pastes into any other. The clip carries the source capture's scale, and the paste scales the annotation by `target.scale / clip.scale` around image pixel (0,0), so line widths, blur radii, blocks, font sizes and positions keep their size in points. Placement: an annotation whose bounds lie wholly outside the target image is centred in it; then, while an annotation identical apart from its id is already in the document, the paste moves by the duplicate offset (at most 100 times), so pasting back onto the original steps aside like ⌘D. A clip of another format version, an unreadable payload or a non-positive scale beeps (the same as nothing to paste).
- **The editor never touches the pasteboard.** CanvasView calls `EditorObjectClipboard` closures, which AppCoordinator implements with three new `Pasteboard` members.
- **Text editing.** While `isEditingText`, `match` returns nil for ⌘V and ⌘D as for ⌘C, ⌘A, ⌘Z and ⇧⌘Z. EditorWindow (Task 3) then sends ⌘V to the text view as `paste:` through `TextEditingChord`; ⌘D has no `TextEditingChord` row, so it goes on to super and duplicates nothing (the canvas is not first responder, and nothing is selected while typing).
- **Cropping.** While the Crop tool is active, ⌘V and AXPress do nothing (the canvas does not respond to `paste:`, and `selectFromAccessibility` returns false), because cropping shows no selection (Task 4). ⌘C and ⌘D need nothing more: picking Crop clears the selection.
- **Close sheet.** Don’t Save keeps ⌘D: while the sheet shows, the sheet's window is key and EditorWindow already passes every key equivalent on (`attachedSheet != nil`), so the two never meet.
- **Space-drag pan.** Space (no ⌘, ⌃ or ⌥, not while editing text, not while a tool drag runs) sets `spaceHeld` and shows the open hand; key repeats are swallowed so they never reach `interpretKeyEvents` (which would beep). A press while Space is down starts a pan instead of reaching the tool: closed hand, and every drag sets `model.transform` to the press-time transform panned by the pointer's travel in view points, through `apply(_:fits: false)`, so offsets snap to device pixels without drift. The pan ends on mouseUp even if Space was let go first. Space up, the canvas resigning first responder, or the window resigning key (`windowDidResignKey`) clears `spaceHeld`. Pan never enters undo.
- **Accessibility.** CanvasView is an `AXLayoutArea` labelled `Annotation canvas`. It has one `AnnotationAccessibilityElement` (role `AXLayoutItem`) per annotation, in painting order (effects, then drawings, each in creation order). Labels are the kind plus a number counted per kind in that order (`Redact 1`, `Redact 2`, `Arrow 1`); a text annotation's value is its string. The frame follows zoom and pan because it is computed on every query. AXPress selects the annotation, after which Delete, the arrow keys, ⌘C and ⌘D act on it. `isAccessibilitySelected` follows the selection. The canvas posts `layoutChanged` when the document changes and `selectedChildrenChanged` when the selection changes. Elements are cached by id so VoiceOver focus survives a refresh.

- [ ] **Step 1: Write the failing tests**

`TidyShotTests/AnnotationClipTests.swift`:
```swift
import CoreGraphics
import Foundation
import Testing
@testable import TidyShot

struct AnnotationClipTests {
    let red = RGBA(red: 1, green: 0, blue: 0, alpha: 1)

    func box(x: CGFloat, y: CGFloat) -> Annotation {
        .rectangle(ShapeBox(id: UUID(), rect: CGRect(x: x, y: y, width: 40, height: 20), color: red, lineWidth: 8))
    }

    @Test func roundTripKeepsAnnotationAndScale() throws {
        let clip = AnnotationClip(annotation: box(x: 10, y: 10), scale: 2)
        #expect(clip.formatVersion == AnnotationClip.currentFormatVersion)
        #expect(AnnotationClip.pasteboardTypeName == "io.tky.tidyshot.annotation")
        let data = try #require(clip.encoded())
        #expect(AnnotationClip.decoded(from: data) == clip)
    }

    @Test func decodeRejectsForeignOrDamagedData() throws {
        #expect(AnnotationClip.decoded(from: Data()) == nil)
        #expect(AnnotationClip.decoded(from: Data("hello".utf8)) == nil)
        let data = try #require(AnnotationClip(annotation: box(x: 0, y: 0), scale: 2).encoded())
        #expect(AnnotationClip.decoded(from: data.prefix(data.count / 2)) == nil)
        var newer = AnnotationClip(annotation: box(x: 0, y: 0), scale: 2)
        newer.formatVersion = AnnotationClip.currentFormatVersion + 1
        #expect(AnnotationClip.decoded(from: try #require(newer.encoded())) == nil)
        let flat = AnnotationClip(annotation: box(x: 0, y: 0), scale: 0)
        #expect(AnnotationClip.decoded(from: try #require(flat.encoded())) == nil)
    }

    @Test func offImageObjectIsCentredThenCascades() throws {
        let size = CGSize(width: 400, height: 300)
        let step = CGVector(dx: 20, dy: 20)
        let id = UUID()
        // Copied far out in a larger capture: wholly outside this image, so it is centred.
        let clip = AnnotationClip(annotation: box(x: 1500, y: 1200), scale: 2)
        let placed = clip.placed(in: AnnotationDocument(annotations: []), imageSize: size, scale: 2, step: step, id: id)
        #expect(placed == .rectangle(ShapeBox(id: id, rect: CGRect(x: 180, y: 140, width: 40, height: 20),
                                              color: red, lineWidth: 8)))
        // Identical copies (other ids) already at both spots: the paste steps aside twice.
        let crowded = AnnotationDocument(annotations: [placed.withID(UUID()), placed.moved(by: step).withID(UUID())])
        #expect(clip.placed(in: crowded, imageSize: size, scale: 2, step: step, id: id)
                == placed.moved(by: CGVector(dx: 40, dy: 40)))
        // Inside the image and not a copy of anything there: it lands where it was copied.
        let near = box(x: 10, y: 10)
        #expect(AnnotationClip(annotation: near, scale: 2).placed(in: crowded, imageSize: size, scale: 2, step: step, id: id)
                == near.withID(id))
    }
}
```

`TidyShotTests/CanvasAccessibilityTests.swift`:
```swift
import CoreGraphics
import Foundation
import Testing
@testable import TidyShot

struct CanvasAccessibilityTests {
    let red = RGBA(red: 1, green: 0, blue: 0, alpha: 1)
    let black = RGBA(red: 0, green: 0, blue: 0, alpha: 1)

    func arrow(_ y: CGFloat) -> Annotation {
        .arrow(Segment(id: UUID(), from: CGPoint(x: 0, y: y), to: CGPoint(x: 50, y: y), color: red, lineWidth: 4))
    }

    func redaction(_ x: CGFloat) -> Annotation {
        .redact(Region(id: UUID(), rect: CGRect(x: x, y: 0, width: 10, height: 10)), fill: black)
    }

    /// Effects paint first, so VoiceOver reads them first; each kind is numbered on its own.
    @Test func itemsFollowPaintingOrderAndNumberEachKind() {
        let firstArrow = arrow(10)
        let firstRedact = redaction(0)
        let box = Annotation.rectangle(ShapeBox(id: UUID(), rect: CGRect(x: 5, y: 5, width: 20, height: 20),
                                                color: red, lineWidth: 4))
        let secondArrow = arrow(40)
        let secondRedact = redaction(30)
        let document = AnnotationDocument(annotations: [firstArrow, firstRedact, box, secondArrow, secondRedact])
        let items = CanvasAccessibility.items(in: document)
        #expect(items.map(\.id) == [firstRedact.id, secondRedact.id, firstArrow.id, box.id, secondArrow.id])
        #expect(items.map(\.label) == ["Redact 1", "Redact 2", "Arrow 1", "Rectangle 1", "Arrow 2"])
        #expect(items.allSatisfy { $0.value == nil })
        #expect(CanvasAccessibility.items(in: AnnotationDocument(annotations: [])).isEmpty)
        #expect(CanvasAccessibility.canvasLabel == "Annotation canvas")
    }

    @Test func textItemReadsItsString() {
        let text = Annotation.text(TextBox(id: UUID(), string: "Click here", origin: CGPoint(x: 4, y: 4),
                                           fontSize: 40, color: red))
        let items = CanvasAccessibility.items(in: AnnotationDocument(annotations: [text]))
        #expect(items.map(\.label) == ["Text 1"])
        #expect(items.first?.value == "Click here")
    }
}
```

`TidyShotTests/EditorModelTests.swift`: replace `makeModel` (:17-26) so a test can ask for another scale and a larger image; every existing call keeps compiling:
```swift
    /// A model over a `side` x `side` opaque grey capture at `scale` (16 px at 2x unless a test
    /// needs room or another scale), with the standard defaults.
    func makeModel(renderer: any TileRendering = FakeTileRenderer(), scale: CGFloat = 2, side: Int = 16) -> EditorModel {
        let context = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(srgbRed: 0.5, green: 0.5, blue: 0.5, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: side, height: side))
        return EditorModel(recordID: UUID(), image: ScaledImage(image: context.makeImage()!, scale: scale),
                           renderer: renderer, defaults: .standard)
    }
```
Append to `EditorModelTests`:
```swift
    @Test func duplicateOffsetsAndSelects() throws {
        let model = makeModel(side: 64)
        let shape = add(box(x: 2), to: model)
        // Nothing selected: nothing to duplicate, and no step.
        model.duplicateSelection()
        #expect(model.document.annotations == [shape])
        #expect(model.undoManager.undoActionName == "Add")

        model.selection = shape.id
        model.duplicateSelection()
        // 10 pt down and to the right at scale 2.
        #expect(model.duplicateOffset == CGVector(dx: 20, dy: 20))
        let copy = try #require(model.document.annotations.last)
        #expect(model.document.annotations.count == 2)
        #expect(copy.id != shape.id)
        #expect(copy == shape.moved(by: CGVector(dx: 20, dy: 20)).withID(copy.id))
        #expect(model.selection == copy.id)
        #expect(model.undoManager.undoActionName == "Duplicate Rectangle")

        // ⌘D again duplicates the copy, one more step down and to the right.
        model.duplicateSelection()
        let third = try #require(model.document.annotations.last)
        #expect(third == shape.moved(by: CGVector(dx: 40, dy: 40)).withID(third.id))
        #expect(model.selection == third.id)
        #expect(Set(model.document.annotations.map(\.id)).count == 3)
    }

    @Test func duplicateIsOneUndoStep() {
        let model = makeModel(side: 64)
        let effect = add(redaction(), to: model)
        model.selection = effect.id
        model.duplicateSelection()
        #expect(model.document.effects.count == 2)
        model.undoManager.undo()
        #expect(model.document.annotations == [effect])
        // The copy is gone, so the selection is too.
        #expect(model.selection == nil)
        model.undoManager.redo()
        #expect(model.document.effects.count == 2)
        #expect(undoAll(model).count == 2)
    }

    /// A copy from a 2x editor pasted into a 1x editor keeps its size in points.
    @Test func pasteIntoAnotherEditorKeepsPointSize() throws {
        let source = makeModel()
        let shape = add(box(x: 2), to: source)
        #expect(source.objectClip() == nil)
        source.selection = shape.id
        let data = try #require(source.objectClip()?.encoded())
        let clip = try #require(AnnotationClip.decoded(from: data))
        #expect(clip.scale == 2)

        let target = makeModel(scale: 1)
        target.paste(clip)
        let pasted = try #require(target.document.annotations.first)
        #expect(pasted.id != shape.id)
        #expect(pasted == .rectangle(ShapeBox(id: pasted.id, rect: CGRect(x: 1, y: 1, width: 3, height: 2),
                                              color: red, lineWidth: 2)))
        #expect(target.selection == pasted.id)
        #expect(target.undoManager.undoActionName == "Paste Rectangle")
        target.undoManager.undo()
        #expect(target.document.annotations.isEmpty)
        #expect(source.document.annotations == [shape])
    }

    /// Pasting back into the same editor steps aside from the original, like ⌘D.
    @Test func pasteOntoItsOriginalCascades() throws {
        let model = makeModel(side: 200)
        let shape = add(box(x: 2), to: model)
        model.selection = shape.id
        let clip = try #require(model.objectClip())
        model.paste(clip)
        let first = try #require(model.document.annotations.last)
        #expect(first == shape.moved(by: CGVector(dx: 20, dy: 20)).withID(first.id))
        model.paste(clip)
        let second = try #require(model.document.annotations.last)
        #expect(second == shape.moved(by: CGVector(dx: 40, dy: 40)).withID(second.id))
        #expect(model.selection == second.id)
        #expect(undoAll(model).count == 3)
    }
```

`TidyShotTests/CanvasToolTests.swift`: append to `CanvasToolTests`:
```swift
    @Test func optionDragDuplicates() throws {
        let original = arrow(CGPoint(x: 20, y: 100), CGPoint(x: 180, y: 100))
        let canvas = FakeCanvasEditing([original])
        let tool = makeTool(for: .select)

        // An Option-click that never passes the tiny-drag rule changes nothing.
        tool.mouseDown(at(100, 100, option: true), on: canvas)
        tool.mouseUp(at(100, 100, option: true), on: canvas)
        #expect(canvas.commits.isEmpty)
        #expect(canvas.selection == original.id)

        tool.mouseDown(at(100, 100, option: true), on: canvas)
        tool.mouseDragged(at(130, 120, option: true), on: canvas)
        let shown = try #require(canvas.transient)
        #expect(shown.id != original.id)
        #expect(shown == original.moved(by: CGVector(dx: 30, dy: 20)).withID(shown.id))
        #expect(canvas.document.annotations == [original])
        #expect(canvas.selection == original.id)

        tool.mouseUp(at(130, 120, option: true), on: canvas)
        #expect(canvas.commits.count == 1)
        let commit = try #require(canvas.commits.first)
        #expect(commit.actionName == "Duplicate \(original.title)")
        #expect(commit.coalescingKey == nil)
        #expect(commit.document.annotations == [original, shown])
        #expect(canvas.selection == shown.id)
        #expect(canvas.transient == nil)
    }

    /// Option is live: released mid-drag the gesture is a move, pressed again the same copy returns.
    @Test func optionReleasedMidDragMoves() throws {
        let original = arrow(CGPoint(x: 20, y: 100), CGPoint(x: 180, y: 100))
        let canvas = FakeCanvasEditing([original])
        let tool = makeTool(for: .select)
        let moved = original.moved(by: CGVector(dx: 30, dy: 20))

        tool.mouseDown(at(100, 100, option: true), on: canvas)
        tool.mouseDragged(at(130, 120, option: true), on: canvas)
        let copyID = try #require(canvas.transient?.id)
        #expect(copyID != original.id)

        tool.flagsChanged(at(130, 120), on: canvas)
        #expect(canvas.transient == moved)
        tool.flagsChanged(at(130, 120, option: true), on: canvas)
        #expect(canvas.transient == moved.withID(copyID))
        tool.flagsChanged(at(130, 120), on: canvas)

        tool.mouseUp(at(130, 120), on: canvas)
        #expect(canvas.commits.count == 1)
        #expect(canvas.commits.first?.actionName == "Move \(original.title)")
        #expect(canvas.document.annotations == [moved])
        #expect(canvas.selection == original.id)
        #expect(canvas.transient == nil)
    }
```

`TidyShotTests/KeyRoutingTests.swift`:
- In `shortcutTableMatchesExpectedChords` (:80-112), change the doc comment to `/// The 4a table from spec 2.6 plus 4b's ⌘V and ⌘D. Characters are as charactersIgnoringModifiers gives them.` and add two rows after the `copyImage` row:
```swift
            ("v", false, false, .paste, "paste:"),
            ("d", false, false, .duplicate, "duplicate:"),
```
  The `expected.count == EditorShortcut.allCases.count` line now checks 16 rows, and the ⌘X lines stay as they are. After `#expect(matched("U", shift: true, option: true) == nil)` add:
```swift
        // ⇧⌘V and ⌥⌘D are other chords.
        #expect(matched("V", shift: true) == nil)
        #expect(matched("d", option: true) == nil)
```
- In `editingTextPassesClipboardAndUndoChordsThrough` (:126-146), change the doc comment to `/// While a text annotation is edited (4b), ⌘C, ⌘V, ⌘D, ⌘A, ⌘Z and ⇧⌘Z go to the NSTextView.`, change the set on its first line to `[.copy, .paste, .duplicate, .selectAll, .undo, .redo]`, and after `#expect(matched("c", editing: true) == nil)` add:
```swift
        #expect(matched("v", editing: true) == nil)
        #expect(matched("d", editing: true) == nil)
```
- Append:
```swift
    /// Space alone pans; it is never a tool letter or a width, so `action` leaves it alone too.
    @Test func spaceIsThePanKey() {
        func pan(_ characters: String?, command: Bool = false, control: Bool = false, option: Bool = false,
                 editing: Bool = false) -> Bool {
            KeyRouting.isPanKey(characters: characters, command: command, control: control, option: option,
                                isEditingText: editing)
        }
        #expect(pan(" "))
        #expect(!pan(" ", command: true))
        #expect(!pan(" ", control: true))
        #expect(!pan(" ", option: true))
        #expect(!pan(" ", editing: true))
        #expect(!pan("v"))
        #expect(!pan(nil))
        #expect(!pan("  "))
        #expect(action(" ") == ignored)
        #expect(action(" ", tool: .text) == ignored)
    }
```
  `action` is the helper as Task 3 left it (its `tool:` parameter defaults to `.select`).

- [ ] **Step 2: Run the tests and see them fail**

Run:
```bash
xcodegen generate && xcodebuild test -project TidyShot.xcodeproj -scheme TidyShot -destination 'platform=macOS' -derivedDataPath .build 2>&1 | grep -E "Test run with|error:|TEST"
```
Expected: the build fails with `error:` lines such as `cannot find 'AnnotationClip' in scope`, `cannot find 'CanvasAccessibility' in scope`, `value of type 'Annotation' has no member 'withID'`, `value of type 'EditorModel' has no member 'duplicateSelection'`, `type 'EditorShortcut' has no member 'paste'` and `type 'KeyRouting' has no member 'isPanKey'`, then `** TEST FAILED **`.

- [ ] **Step 3: Implement the model, the clip, the accessibility items and the key tables**

`TidyShot/Editor/Model/Annotation.swift`, after `moved(by:)`:
```swift
    /// The same annotation under another id, for duplicate and paste. Every other field is kept.
    func withID(_ id: UUID) -> Annotation {
        switch self {
        case .rectangle(let box):
            .rectangle(ShapeBox(id: id, rect: box.rect, color: box.color, lineWidth: box.lineWidth))
        case .ellipse(let box):
            .ellipse(ShapeBox(id: id, rect: box.rect, color: box.color, lineWidth: box.lineWidth))
        case .arrow(let segment):
            .arrow(Segment(id: id, from: segment.from, to: segment.to, color: segment.color, lineWidth: segment.lineWidth))
        case .line(let segment):
            .line(Segment(id: id, from: segment.from, to: segment.to, color: segment.color, lineWidth: segment.lineWidth))
        case .pencil(let stroke):
            .pencil(Stroke(id: id, points: stroke.points, color: stroke.color, lineWidth: stroke.lineWidth))
        case .highlighter(let stroke):
            .highlighter(Stroke(id: id, points: stroke.points, color: stroke.color, lineWidth: stroke.lineWidth))
        case .text(let box):
            .text(TextBox(id: id, string: box.string, origin: box.origin, fontSize: box.fontSize, color: box.color))
        case .redact(let region, let fill):
            .redact(Region(id: id, rect: region.rect), fill: fill)
        case .blur(let region, let radius):
            .blur(Region(id: id, rect: region.rect), radius: radius)
        case .pixelate(let region, let block):
            .pixelate(Region(id: id, rect: region.rect), block: block)
        }
    }

    /// Every position and size times `factor`, around image pixel (0, 0): a paste from a capture
    /// at another scale keeps the annotation's size in points. A pixel block stays a whole pixel
    /// count of at least 1. Unchanged for a factor of 1 or a factor that is not a positive number.
    func scaled(by factor: CGFloat) -> Annotation {
        guard factor != 1, factor > 0, factor.isFinite else { return self }
        func point(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x * factor, y: p.y * factor) }
        func rect(_ r: CGRect) -> CGRect {
            CGRect(x: r.minX * factor, y: r.minY * factor, width: r.width * factor, height: r.height * factor)
        }
        switch self {
        case .rectangle(var box):
            box.rect = rect(box.rect)
            box.lineWidth *= factor
            return .rectangle(box)
        case .ellipse(var box):
            box.rect = rect(box.rect)
            box.lineWidth *= factor
            return .ellipse(box)
        case .arrow(var segment):
            segment.from = point(segment.from)
            segment.to = point(segment.to)
            segment.lineWidth *= factor
            return .arrow(segment)
        case .line(var segment):
            segment.from = point(segment.from)
            segment.to = point(segment.to)
            segment.lineWidth *= factor
            return .line(segment)
        case .pencil(var stroke):
            stroke.points = stroke.points.map(point)
            stroke.lineWidth *= factor
            return .pencil(stroke)
        case .highlighter(var stroke):
            stroke.points = stroke.points.map(point)
            stroke.lineWidth *= factor
            return .highlighter(stroke)
        case .text(var box):
            box.origin = point(box.origin)
            box.fontSize *= factor
            return .text(box)
        case .redact(var region, let fill):
            region.rect = rect(region.rect)
            return .redact(region, fill: fill)
        case .blur(var region, let radius):
            region.rect = rect(region.rect)
            return .blur(region, radius: radius * factor)
        case .pixelate(var region, let block):
            region.rect = rect(region.rect)
            return .pixelate(region, block: max(1, (block * factor).rounded()))
        }
    }
```

`TidyShot/Editor/Persistence/AnnotationClip.swift`:
```swift
import CoreGraphics
import Foundation

/// One annotation on the pasteboard, for object copy and paste (4b). It travels as JSON under the
/// private type `pasteboardTypeName` only. The annotation keeps its image-pixel geometry, and
/// `scale` says which capture scale those pixels belong to, so a paste into an editor at another
/// scale keeps the size in points. AppCoordinator does the pasteboard I/O (`Pasteboard`).
nonisolated struct AnnotationClip: Codable, Equatable, Sendable {
    static let pasteboardTypeName = "io.tky.tidyshot.annotation"
    static let currentFormatVersion = 1
    /// How many duplicate offsets a paste may step to get clear of identical annotations.
    static let maximumCascade = 100

    var formatVersion: Int
    var annotation: Annotation
    /// Image pixels per point of the capture the annotation was copied from.
    var scale: CGFloat

    init(annotation: Annotation, scale: CGFloat) {
        formatVersion = Self.currentFormatVersion
        self.annotation = annotation
        self.scale = scale
    }

    func encoded() -> Data? {
        try? JSONEncoder().encode(self)
    }

    /// Nil for anything this build cannot paste: not JSON of a clip, another format version, or a
    /// scale that is not a positive number.
    static func decoded(from data: Data) -> AnnotationClip? {
        guard let clip = try? JSONDecoder().decode(AnnotationClip.self, from: data),
              clip.formatVersion == currentFormatVersion,
              clip.scale.isFinite, clip.scale > 0 else { return nil }
        return clip
    }

    /// The annotation as it lands in `document`, an image of `imageSize` pixels at `scale`:
    /// 1. scaled by `scale / self.scale` and given `id`;
    /// 2. centred in the image when its bounds lie wholly outside it;
    /// 3. moved by `step` while an annotation identical apart from its id is already there, at
    ///    most `maximumCascade` times, so repeated pastes step aside instead of stacking.
    func placed(in document: AnnotationDocument, imageSize: CGSize, scale: CGFloat, step: CGVector, id: UUID) -> Annotation {
        var pasted = annotation.scaled(by: scale / self.scale).withID(id)
        let image = CGRect(origin: .zero, size: imageSize)
        let bounds = AnnotationGeometry.bounds(of: pasted, scale: scale)
        if !bounds.intersects(image) {
            pasted = pasted.moved(by: CGVector(dx: image.midX - bounds.midX, dy: image.midY - bounds.midY))
        }
        var steps = 0
        while steps < Self.maximumCascade, document.annotations.contains(where: { $0.withID(id) == pasted }) {
            pasted = pasted.moved(by: step)
            steps += 1
        }
        return pasted
    }
}
```

`TidyShot/Editor/Geometry/CanvasAccessibility.swift`:
```swift
import Foundation

/// What VoiceOver reads on the canvas: one item per annotation, in painting order (effects, then
/// drawings, each in creation order). CanvasView turns each into an `AnnotationAccessibilityElement`.
nonisolated enum CanvasAccessibility {
    static let canvasLabel = "Annotation canvas"

    struct Item: Equatable, Sendable {
        let id: UUID
        /// The kind and a number counted per kind in painting order: "Redact 1", "Arrow 2".
        let label: String
        let value: String?
    }

    static func items(in document: AnnotationDocument) -> [Item] {
        var counts: [String: Int] = [:]
        return (document.effects + document.drawings).map { annotation in
            let number = (counts[annotation.title] ?? 0) + 1
            counts[annotation.title] = number
            return Item(id: annotation.id, label: "\(annotation.title) \(number)", value: value(of: annotation))
        }
    }

    /// A text annotation's string; nil for every other kind.
    static func value(of annotation: Annotation) -> String? {
        if case .text(let box) = annotation { return box.string }
        return nil
    }
}
```

`TidyShot/Editor/Geometry/KeyRouting.swift`:
- In the `KeyRouting` doc comment add: `Space is the pan key (`isPanKey`); CanvasView checks it before `action`, so it never reaches `interpretKeyEvents`.` Add to `KeyRouting`:
```swift
    /// Space with no Command, Control or Option, and no text edit in progress: hold it and drag to
    /// pan. Shift does not matter.
    static func isPanKey(characters: String?, command: Bool, control: Bool, option: Bool, isEditingText: Bool) -> Bool {
        !command && !control && !option && !isEditingText && characters == " "
    }
```
- `EditorShortcut`: the doc comment reads `The editor's key equivalents (spec 2.6: the 4a table plus 4b's ⌘V and ⌘D), …`, keeping the ⌘X sentence. The case list becomes `case save, saveAs, copy, copyImage, paste, duplicate, upload, uploadAsNew, undo, redo, close, zoomToFit, actualSize, zoomIn, zoomOut, selectAll`. Add `case .paste: Chord(key: "v")` and `case .duplicate: Chord(key: "d")` to `chord`, `case .paste: "paste:"` and `case .duplicate: "duplicate:"` to `selectorName`, and change `passesThroughWhileEditingText` to:
```swift
    /// While a text annotation is edited (4b), these chords are left to the NSTextView.
    var passesThroughWhileEditingText: Bool {
        switch self {
        case .copy, .paste, .duplicate, .selectAll, .undo, .redo: true
        case .save, .saveAs, .copyImage, .upload, .uploadAsNew, .close, .zoomToFit, .actualSize, .zoomIn, .zoomOut: false
        }
    }
```
  `EditorWindow` does not change: as Task 3 left it, it already sends the matched selector to the first target in the responder chain, and Task 3's `TextEditingChord` already sends ⌘V to the text view while typing.

`TidyShot/Editor/Tools/ToolFactory.swift`, replacing `commitNewShape` (:14-22):
```swift
extension CanvasEditing {
    /// Ends a gesture that adds `shape` with one commit, named `actionName` or else `Add <title>`,
    /// then clears the transient and selects the new shape. The commit runs while the transient
    /// still holds the same value, so the tile cache sees one key throughout and the live tile
    /// carries over (spec 2.6, Tiles). ⌥-drag, ⌘D and ⌘V use it too.
    func commitNewShape(_ shape: Annotation, actionName: String? = nil) {
        commit(document.appending(shape), actionName: actionName ?? "Add \(shape.title)", coalescingKey: nil)
        transient = nil
        selection = shape.id
    }
}
```

`TidyShot/Editor/Session/EditorModel.swift`, in the `// MARK: Shapes and the selection` section after `nudgeSelection(by:)`:
```swift
    /// ⌘D, and a paste that lands on an identical annotation, move the copy this far down and to
    /// the right.
    static let duplicateOffsetPoints: CGFloat = 10

    /// `duplicateOffsetPoints` in image pixels.
    var duplicateOffset: CGVector {
        CGVector(dx: Self.duplicateOffsetPoints * scale, dy: Self.duplicateOffsetPoints * scale)
    }

    /// ⌘D: a copy of the selection, `duplicateOffset` away, appended and selected. One step,
    /// `Duplicate <title>`. Nothing selected: nothing happens.
    func duplicateSelection() {
        guard let selected = selectedAnnotation else { return }
        commitNewShape(selected.moved(by: duplicateOffset).withID(UUID()), actionName: "Duplicate \(selected.title)")
    }

    /// ⌘C with a selection: the selected annotation as it is in the document, with this capture's
    /// scale. Nil with nothing selected (⌘C then copies the image).
    func objectClip() -> AnnotationClip? {
        selectedAnnotation.map { AnnotationClip(annotation: $0, scale: scale) }
    }

    /// ⌘V: the clip placed by `AnnotationClip.placed`, appended and selected. One step,
    /// `Paste <title>`.
    func paste(_ clip: AnnotationClip) {
        let pasted = clip.placed(in: document, imageSize: imageSize, scale: scale, step: duplicateOffset, id: UUID())
        commitNewShape(pasted, actionName: "Paste \(pasted.title)")
    }
```

`TidyShot/Editor/Tools/SelectTool.swift`. Add to the class doc comment: `With Option held (at the press or later; flagsChanged re-reads it), a move drags a copy with its own id and leaves the original; mouseUp commits it once as Duplicate <title> and selects it.` Then the gesture and the three methods that change:
```swift
    private enum Gesture {
        /// `copyID` is the id a copy gets when Option is held; one per gesture.
        case move(original: Annotation, copyID: UUID)
        /// `from` is where the handle sat at the press, so the handle keeps the grab offset.
        case resize(original: Annotation, handle: Int, from: CGPoint)

        var original: Annotation {
            switch self {
            case .move(let original, _), .resize(let original, _, _): original
            }
        }

        var verb: String {
            switch self {
            case .move: "Move"
            case .resize: "Resize"
            }
        }
    }
```
In `mouseDown`, the last line becomes `gesture = .move(original: annotation, copyID: UUID())`; Task 3's double-click branch above it (re-edit a text, then return) stays. `mouseUp`:
```swift
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
        if changed.id != ended.original.id {
            // An ⌥-drag: the copy is new, the original stays.
            canvas.commitNewShape(changed, actionName: "Duplicate \(changed.title)")
            return
        }
        canvas.commit(canvas.document.replacing(changed), actionName: "\(ended.verb) \(changed.title)",
                      coalescingKey: nil)
        canvas.transient = nil
    }
```
And the `.move` arm of `update`:
```swift
        case .move(let original, let copyID):
            let moved = original.moved(by: input.shift ? DragGeometry.axisLocked(delta) : delta)
            shown = input.option ? moved.withID(copyID) : moved
```

Run the suite command from Step 2. Expected: no `error:` lines and every test passes, because nothing Step 1 tests needs Step 4. A build error here is a switch Step 3 missed; fix it before going on.

- [ ] **Step 4: Wire the pasteboard, the canvas, the controller and the coordinator**

`TidyShot/Output/Pasteboard.swift`, before `write(_:)`:
```swift
    /// The private type of an object copy (`AnnotationClip`).
    static let annotationClipType = NSPasteboard.PasteboardType(AnnotationClip.pasteboardTypeName)

    /// Replaces the pasteboard contents with one copied annotation, under the private type only:
    /// pasting into another app pastes nothing.
    @discardableResult
    static func copy(annotationClip data: Data) -> Int {
        let item = NSPasteboardItem()
        item.setData(data, forType: annotationClipType)
        return write([item])
    }

    /// The copied annotation's data, or nil.
    static func annotationClipData() -> Data? {
        NSPasteboard.general.data(forType: annotationClipType)
    }

    /// Whether an object copy is on the pasteboard. Checks the types only, so no data is read.
    static var hasAnnotationClip: Bool {
        NSPasteboard.general.availableType(from: [annotationClipType]) != nil
    }
```

`TidyShot/Editor/Window/EditorWindowController.swift`:
- Above `EditorActions`:
```swift
/// The pasteboard as object copy and paste see it (4b). AppCoordinator implements it, because the
/// editor never touches the pasteboard.
struct EditorObjectClipboard {
    var copy: (Data) -> Void
    var paste: () -> Data?
    /// A type check only; validation calls it often.
    var canPaste: () -> Bool
}
```
  and in `EditorActions` add `var objectClipboard: EditorObjectClipboard` after `copy`.
- In `init`, after `self.canvasView = canvasView`: `canvasView.objectClipboard = actions.objectClipboard`.
- The doc comment of `copy(_:)` becomes: `⌘C with nothing selected: copies the flattened image, like ⇧⌘C. With a selection CanvasView takes copy: first (object copy) and this is not reached.` The body does not change.
- Add, next to `windowWillClose(_:)`:
```swift
    /// Space's key-up goes elsewhere once the window is not key, so the pan key is let go here.
    func windowDidResignKey(_ notification: Notification) {
        canvasView.endSpacePan()
    }
```

`TidyShot/App/AppCoordinator.swift`, in `editorActions(for:)` after the `copy:` argument:
```swift
            objectClipboard: EditorObjectClipboard(
                // An object copy is not an image: clipboardOwner is left alone. The write moves the
                // change count, so the clipboard rule will not replace the object after a Save.
                copy: { data in Pasteboard.copy(annotationClip: data) },
                paste: { Pasteboard.annotationClipData() },
                canPaste: { Pasteboard.hasAnnotationClip }),
```

`TidyShot/Editor/Window/AnnotationAccessibilityElement.swift`:
```swift
import AppKit

/// One annotation on the canvas for VoiceOver: an `AXLayoutItem` child of CanvasView. The label
/// and value are set by the canvas each time it lists its children; the frame and the selected
/// state are read from the canvas on every query, so they follow zoom, pan and selection.
final class AnnotationAccessibilityElement: NSAccessibilityElement {
    let annotationID: UUID
    private weak var canvas: CanvasView?

    init(annotationID: UUID, canvas: CanvasView) {
        self.annotationID = annotationID
        self.canvas = canvas
        super.init()
        setAccessibilityElement(true)
        setAccessibilityRole(.layoutItem)
        setAccessibilityParent(canvas)
    }

    override func accessibilityFrame() -> NSRect {
        canvas?.accessibilityScreenFrame(of: annotationID) ?? .zero
    }

    override func isAccessibilitySelected() -> Bool {
        canvas?.isAccessibilitySelected(annotationID) ?? false
    }

    /// AXPress selects the annotation; Delete, the arrow keys, ⌘C and ⌘D then act on it.
    override func accessibilityPerformPress() -> Bool {
        canvas?.selectFromAccessibility(annotationID) ?? false
    }
}
```

`TidyShot/Editor/Window/CanvasView.swift`:
- State, after `lastInput`:
```swift
    /// Object copy and paste through the coordinator; set by EditorWindowController.
    var objectClipboard: EditorObjectClipboard?
    /// Space is down: the next press pans instead of reaching the tool.
    private var spaceHeld = false
    /// The press that started a Space-drag pan, in view points, and the transform at that moment.
    private var panStart: (viewPoint: CGPoint, transform: CanvasTransform)?
    /// One element per annotation id, kept so VoiceOver focus survives a refresh.
    private var accessibilityElements: [UUID: AnnotationAccessibilityElement] = [:]
```
- Responding only when there is something to act on. This is what passes `copy:` up when nothing is selected: `NSApp.target(forAction:)` asks `responds(to:)` on each responder, skips the canvas, and lands on EditorWindowController. For `duplicate:` and `paste:` with nothing to act on, no target is found and EditorWindow beeps.
```swift
    override func responds(to aSelector: Selector!) -> Bool {
        switch aSelector {
        case #selector(copy(_:)):
            return hasSelectedAnnotation
        case #selector(duplicate(_:)):
            return !isTrackingMouse && hasSelectedAnnotation
        case #selector(paste(_:)):
            // Cropping shows no selection (Task 4), so a paste waits until Crop ends.
            return !isTrackingMouse && model.tool != .crop && objectClipboard?.canPaste() == true
        default:
            return super.responds(to: aSelector)
        }
    }

    private var hasSelectedAnnotation: Bool {
        model.selection.flatMap { model.document.annotation(id: $0) } != nil
    }
```
- Actions, in a new `// MARK: Object copy, paste and duplicate` section:
  - `@objc func copy(_ sender: Any?)`: `guard let data = model.objectClip()?.encoded() else { nextResponder?.tryToPerform(#selector(copy(_:)), with: sender); return }`, then `objectClipboard?.copy(data)`. No notification.
  - `@objc func paste(_ sender: Any?)`: `guard !isTrackingMouse, model.tool != .crop, let data = objectClipboard?.paste(), let clip = AnnotationClip.decoded(from: data) else { NSSound.beep(); return }`, then `model.paste(clip)` and `refresh()`.
  - `@objc func duplicate(_ sender: Any?)`: `guard !isTrackingMouse else { return }`, then `model.duplicateSelection()` and `refresh()`.
- Space-drag pan. `keyDown` starts with the following, after its `flags` line and before the `KeyRouting.action` switch, which keeps Task 3's `tool: model.tool` argument and `.textSize` case:
```swift
        if KeyRouting.isPanKey(characters: event.charactersIgnoringModifiers, command: flags.contains(.command),
                               control: flags.contains(.control), option: flags.contains(.option),
                               isEditingText: isEditingText) {
            // Repeats are swallowed too, so they never reach interpretKeyEvents (which beeps).
            if !event.isARepeat, !isTrackingMouse {
                spaceHeld = true
                updatePanCursor()
            }
            return
        }
```
  Add:
```swift
    override func keyUp(with event: NSEvent) {
        if event.charactersIgnoringModifiers == " " {
            endSpacePan()
        } else {
            super.keyUp(with: event)
        }
    }

    override func resignFirstResponder() -> Bool {
        endSpacePan()
        return super.resignFirstResponder()
    }

    /// Lets go of Space. A pan already under way finishes on mouseUp.
    func endSpacePan() {
        guard spaceHeld else { return }
        spaceHeld = false
        updatePanCursor()
    }

    private var currentCursor: NSCursor {
        if panStart != nil { return .closedHand }
        return spaceHeld ? .openHand : activeTool.cursor
    }

    /// Cursor rects change only when the pointer moves, so the new cursor is also set at once.
    private func updatePanCursor() {
        window?.invalidateCursorRects(for: self)
        currentCursor.set()
    }
```
  `resetCursorRects` uses `currentCursor` instead of `activeTool.cursor`. The pointer methods check the pan first:
  - `mouseDown`: Task 3's block that commits the text being typed and returns stays first. Then, after `window?.makeFirstResponder(self)`, `if spaceHeld, !isTrackingMouse { panStart = (convert(event.locationInWindow, from: nil), model.transform); updatePanCursor(); return }`.
  - `mouseDragged`: first, `if let panStart { let point = convert(event.locationInWindow, from: nil); apply(panStart.transform.panned(by: CGPoint(x: point.x - panStart.viewPoint.x, y: point.y - panStart.viewPoint.y)), fits: false); return }`. Panning from the press-time transform each time keeps device-pixel snapping from adding up.
  - `mouseUp`: first, before the `defer`, `if panStart != nil { panStart = nil; updatePanCursor(); return }`.
  - `flagsChanged` needs no change: `isTrackingMouse` stays false during a pan.
- Accessibility:
```swift
    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { .layoutArea }
    override func accessibilityLabel() -> String? { CanvasAccessibility.canvasLabel }

    override func accessibilityChildren() -> [Any]? {
        let items = CanvasAccessibility.items(in: model.document)
        accessibilityElements = accessibilityElements.filter { id, _ in items.contains { $0.id == id } }
        return items.map { item -> AnnotationAccessibilityElement in
            let element = accessibilityElements[item.id] ?? AnnotationAccessibilityElement(annotationID: item.id, canvas: self)
            accessibilityElements[item.id] = element
            element.setAccessibilityLabel(item.label)
            element.setAccessibilityValue(item.value)
            return element
        }
    }

    override func accessibilitySelectedChildren() -> [Any]? {
        guard let id = model.selection, model.document.annotation(id: id) != nil else { return [] }
        _ = accessibilityChildren()
        return accessibilityElements[id].map { [$0] } ?? []
    }

    /// The annotation's painted bounds on screen, at the current zoom and pan.
    func accessibilityScreenFrame(of id: UUID) -> NSRect {
        guard let annotation = model.document.annotation(id: id) else { return .zero }
        return NSAccessibility.screenRect(fromView: self, rect: model.transform.viewRect(imageBounds(of: annotation)))
    }

    func isAccessibilitySelected(_ id: UUID) -> Bool { model.selection == id }

    func selectFromAccessibility(_ id: UUID) -> Bool {
        guard !isTrackingMouse, model.tool != .crop, model.document.annotation(id: id) != nil else { return false }
        model.selection = id
        refresh()
        return true
    }
```
  In `refresh()`, after `shown = now`:
```swift
        if now.document != previous.document {
            NSAccessibility.post(element: self, notification: .layoutChanged)
        }
        if now.selection != previous.selection {
            NSAccessibility.post(element: self, notification: .selectedChildrenChanged)
        }
```

- [ ] **Step 5: Run the suite**

Run:
```bash
xcodegen generate && xcodebuild test -project TidyShot.xcodeproj -scheme TidyShot -destination 'platform=macOS' -derivedDataPath .build 2>&1 | grep -E "Test run with|error:|TEST"
```
Expected: no `error:` lines, and `Test run with 458 tests in 57 suites passed`. This task adds 12 tests and 2 suites (AnnotationClipTests, CanvasAccessibilityTests).

- [ ] **Step 6: Hand checks**

Build and run (`open .build/Build/Products/Debug/TidyShot.app` after the test build, or Run in Xcode). Take a capture and open it in the editor.
1. Draw a rectangle, select it, press ⌘D: a copy appears 10 pt down and to the right, selected. ⌘D again steps once more. ⌘Z removes one copy per press. With nothing selected (Escape), ⌘D beeps.
2. ⌥-drag an arrow: a copy follows the pointer and the original stays. Release ⌥ before the mouse button: the original moves instead. ⌘Z undoes the drag in one step. ⌥-drag a redaction: the copy's tile renders and the original stays black.
3. Select a shape, ⌘C, ⌘V: the paste lands 10 pt away and is selected; ⌘V again steps further. Paste into TextEdit: nothing is pasted. Toolbar Copy and ⇧⌘C still put the flattened image on the clipboard (paste into Preview with New from Clipboard). Press C to crop, then ⌘V: it beeps and nothing is pasted; Escape, then ⌘V pastes.
4. Press Escape so nothing is selected, then ⌘C: `Image copied` shows (with notifications on) and Preview's New from Clipboard opens the flattened image.
5. Open a second editor (another capture). Copy a shape in one and ⌘V in the other: it pastes at the same size in points. If one capture is 1x (an external non-Retina display), check that the line width looks the same in both. Copy some text in TextEdit, then ⌘V in the editor: it beeps.
6. No “paste from another app” permission alert appears on ⌘V for an object TidyShot copied.
7. Clipboard rule: in an editor of a capture that was copied to the clipboard, ⌘C a shape, then ⌘S. ⌘V still pastes the shape, so Save did not replace the object with the image.
8. Edit a text annotation and press ⌘V and ⌘D: text pastes into the text view and no annotation is duplicated.
9. Hold Space: the cursor is an open hand. Drag: the image follows the pointer with a closed hand, and nothing is drawn or selected. Release Space mid-drag: the pan continues until the mouse button is released, then the tool's cursor returns. A Space press does not beep. ⌘0 fits again after a pan. Hold Space, ⌘-Tab away and back, then click: the tool works (Space was let go on resign key).
10. VoiceOver (⌘F5): move into the canvas. It reads `Annotation canvas`, and its children read `Redact 1`, `Arrow 1` and so on, in painting order; a text annotation reads its string. VO-Space on one selects it, and Delete removes it. Accessibility Inspector shows each element's frame over its shape after zooming and panning.

- [ ] **Step 7: Commit**

```bash
git add TidyShot/Editor/Persistence/AnnotationClip.swift TidyShot/Editor/Geometry/CanvasAccessibility.swift TidyShot/Editor/Window/AnnotationAccessibilityElement.swift TidyShot/Editor/Model/Annotation.swift TidyShot/Editor/Geometry/KeyRouting.swift TidyShot/Editor/Tools/ToolFactory.swift TidyShot/Editor/Tools/SelectTool.swift TidyShot/Editor/Session/EditorModel.swift TidyShot/Editor/Window/CanvasView.swift TidyShot/Editor/Window/EditorWindowController.swift TidyShot/Output/Pasteboard.swift TidyShot/App/AppCoordinator.swift TidyShotTests/AnnotationClipTests.swift TidyShotTests/CanvasAccessibilityTests.swift TidyShotTests/EditorModelTests.swift TidyShotTests/CanvasToolTests.swift TidyShotTests/KeyRoutingTests.swift
git commit -m "feat: duplicate, object copy and paste, space-drag pan and canvas accessibility"
```

### Task 6: Phase 4b manual checklist, README and close-out

**Files:**
- Create: `docs/testing/phase-4b-manual-checklist.md`
- Modify: `README.md` (the `## Annotate` section: the tools paragraph at lines 97-104, the shortcut table and zoom sentence at lines 106-119; one line after line 176 in `## Documents`)
- Modify: `docs/testing/phase-4a-manual-checklist.md` (one pointer line after the intro paragraph, line 6)
- Modify: `docs/superpowers/specs/2026-10-19-tidyshot-screenshot-design.md` (section 2.6, lines 102-435, only where Step 6 finds a divergence; section 6, the Phase 4 block at lines 557-561, always)
- Modify, only when Step 5 finds a divergence: `docs/superpowers/plans/2026-10-20-phase-4b-annotation-tools.md` (the "Test totals" table)
- Test: none (documentation only; no new tests)

**Interfaces:**
- Consumes (behaviour, names and strings the checklist, README and spec check describe; each is produced by Tasks 1 to 5 or by `main`):
  - Task 1: `Annotation.ellipse(ShapeBox)`, `Annotation.line(Segment)`, `EditorTool.ellipse` (E) and `.line` (L), `RectDragTool(.ellipse)` (Shift circle, Option from the centre), `TwoPointTool(.line)` (Shift snaps to 45 degrees), `EditorWindowGeometry.ToolbarMetrics`.
  - Task 2: `Stroke`, `Annotation.pencil` and `.highlighter`, `EditorTool.pencil` (P) and `.highlighter` (H), `PencilTool`, `StrokeSmoothing.decimated(_:minDistance:)` and `catmullRom(_:)`; the highlighter is yellow at 0.45 alpha, 12 pt wide, with a multiply blend.
  - Task 3: `TextBox`, `Annotation.text`, `EditorTool.text` (T), `TextTool`, `TextLayout.frame(for:)`, `EditorModel.commitTextEditing()`, `CanvasView.isEditingText`; Return commits, Shift-Return inserts a newline, Escape cancels, clicking elsewhere commits, a double-click re-edits; digits 1 to 6 pick text sizes 12, 16, 20, 28, 40 and 56 pt while Text is active (20 pt by default); ⌘C, ⌘X, ⌘V, ⌘A, ⌘Z and ⇧⌘Z act on the text while editing, and ⌘D does nothing then; with Text, a click on a committed text edits it again, and with Select a double-click does; typed text counts in `hasUnsavedChanges`.
  - Task 4: `AnnotationDocument.crop: CGRect?`, `EditorTool.crop` (C), `CropTool`, `CropGeometry.clamped(_:to:)` and `integralCrop(_:in:)`, the dim mask and the W x H readout in `CanvasView`; picking Crop starts the draft at the applied crop or the whole capture; Return applies, Escape drops the draft, and both return to the tool used before Crop; picking another tool applies the draft; a draft that would change the crop counts in `hasUnsavedChanges`; `EditorFlattener` crops last.
  - Task 5: `RecentCaptureActions.annotate` (already on `main` since 4a, `TidyShot/RecentCaptures/RecentCaptureRow.swift:8`), `EditorShortcut` rows ⌘V `paste:` and ⌘D `duplicate:`, `EditorModel.duplicateSelection()` (10 pt down and to the right, `Duplicate <title>`), ⌥-drag duplicate in `SelectTool` (Option live mid-drag), object `copy:` and `paste:` in `CanvasView` (`Paste <title>`; a paste onto an identical annotation steps 10 pt aside; one from another capture keeps its size in points), ⌘D and ⌘V beeping with nothing to act on, Space-drag pan (unclamped, like scrolling), and an `AnnotationAccessibilityElement` (`AXLayoutItem`) per annotation inside the `AXLayoutArea` labelled `Annotation canvas`, in painting order (effects, then drawings), labelled kind plus per-kind number (`Redact 1`, `Arrow 2`), a text's value its string, AXPress selecting.
  - `main`, unchanged: the 4a checklist's sections and wording (`docs/testing/phase-4a-manual-checklist.md`), the README's `## Annotate` section, `EditorWindowGeometry.minimumContentWidth(toolbarWidth:)` (`TidyShot/Editor/Geometry/EditorWindowGeometry.swift:84`), `ImageEncoder.pngData(from:scale:)` writing 72 x scale DPI, and `history.json` records with `pixelWidth` and `pixelHeight`.
- Produces: documentation only. Nothing depends on it. It is the last task of the plan.

Two entry details no longer hold, so follow the code on `main`:
- The 4a checklist has no "Known limitations" section, and neither does the README. The two 4a gaps the entry meant (Recent Captures as an entry point with Show overlay off, and reopening a stale upload-only record after a failed replace) were closed inside 4a. The 4b checklist keeps both as regression items run with the 4b tools, and Step 4 greps that no limitation text is left.
- The checklist is `docs/testing/phase-4b-manual-checklist.md`, beside `phase-4a-manual-checklist.md`; there is no `phase-4-manual-checklist.md`.

- [ ] **Step 1: Read the finished code the documents describe**

The checklist, the README and the spec check must match the build, not the plan. Run:
```bash
grep -n "case " TidyShot/Editor/Model/EditorTool.swift | head -30
grep -n -A8 "static var toolbarOrder" TidyShot/Editor/Model/EditorTool.swift
grep -rn "setAccessibilityLabel\|accessibilityLabel\|NSAccessibilityElement\|accessibilityRole" TidyShot/Editor/Window | cut -c1-200
grep -n "paste:\|duplicate:\|\"x\"" TidyShot/Editor/Geometry/KeyRouting.swift
grep -n "multiply\|0.45" TidyShot/Editor/Rendering/AnnotationDrawing.swift TidyShot/Editor/Model/EditorPalette.swift
grep -rn "keyDown\|isSpaceDown\|spaceHeld\|panning" TidyShot/Editor/Window/CanvasView.swift | cut -c1-200
```
Expected: the toolbar order Step 2 lists (twelve tools); the accessibility labels Task 5 wrote; the two new shortcut rows and no `"x"` row; the highlighter's multiply blend and 0.45 alpha; the Space handling in `CanvasView`. Where the code differs from the wording in Step 2 (the toolbar order, an accessibility label, how Space pans, what a pasted object does), write the code's behaviour in the checklist and the README, and list each such change in the report. Do not change code.

- [ ] **Step 2: Write the manual checklist**

`docs/testing/phase-4b-manual-checklist.md`:
````markdown
# Phase 4b manual test checklist

Run after any change to the editor's tools, the canvas, the toolbar, crop, text, the keyboard
handling or the accessibility elements. Automated tests cover the model and undo, the geometry
(hit testing, smoothing, text layout, crop), the shortcut table, the flattener's pixels for every
tool and the toolbar width arithmetic; everything here needs real windows and eyes. The 4a
checklist (`phase-4a-manual-checklist.md`) still covers redaction, Save, Save As…, Copy, Upload,
caches, availability and closing; run it too after a change to those paths.

Setup: fresh build, Screen Recording granted, save folder set to Desktop, a working destination
saved in Settings > Upload, "Show notification" on in Settings > General, "Show Quick Access
overlay after capture" on in Settings > Overlay, Network Link Conditioner installed. Take these
captures first, so every section has something to draw on:
- a Terminal window with a few lines of dark text on a white background (a TextEdit window works)
  and a few lines of made-up secret (`echo SECRET-TOKEN-0123456789`), saved with "Save and copy
  image";
- the same kind of capture with "Upload and copy URL", and one with "Upload only, keep no local
  file" that has finished uploading;
- a second, different window capture with "Save and copy image", for the two-editor items;
- a window capture (`⌃⇧2`) with transparent rounded corners.

`history.json` is in `~/Library/Containers/io.tky.tidyshot/Data/Library/Application Support/TidyShot/`.
Where an item checks a link with `curl`, use a link no browser has opened. Draw only on made-up
data.

## Toolbar and keys
- [ ] The toolbar shows twelve tools, in order: Select, Redact, Pixelate, Blur, Rectangle, Arrow, Ellipse, Line, Pencil, Highlighter, Text and Crop, then the colour button, the options button, the zoom pop-up, Copy, Save and Upload. Each tool's tooltip names its letter: `V` `D` `X` `B` `R` `A` `E` `L` `P` `H` `T` `C`.
- [ ] Narrow the window as far as it goes, with a small capture and then with a long file name in the title (rename a capture to 60 characters first): every one of the twelve tools, the colour and options buttons, the zoom pop-up, Copy, Save and Upload still show, with no » overflow chevron at the right. The title truncates before any item does. Widen the window and the layout returns.
- [ ] Repeat the narrowest-window check with the window full screen and back, and on a second display if one is attached.
- [ ] With the canvas focused, each letter picks its tool and the toolbar follows. Typing a letter while a text is being edited types the letter and does not change the tool.
- [ ] Choose a tool, then press `V`: Select is active and the drawing tool's cursor is gone.

## Ellipse and Line
- [ ] Ellipse (`E`): a drag draws an ellipse inscribed in the dragged box, red and 4 pt by default, the stroke inside the box. Shift draws a circle and Option draws from the centre; pressing or releasing either mid-drag changes the shape without moving the mouse. Escape mid-drag drops it. A click without a drag adds nothing. The new ellipse is selected, with 8 handles.
- [ ] Select an ellipse: a click on its ring picks it; a click in the middle of an empty ellipse does not, and picks whatever is under it (a blur or the background). Dragging a handle resizes it, and Shift keeps it a circle.
- [ ] Line (`L`): the drag start and end are the line's ends, with round caps and no arrowhead. Shift snaps to 45 degrees. The new line is selected with 2 handles; dragging a handle moves that end.
- [ ] Keys `1` to `6` set 2, 3, 4, 6, 8 and 12 pt on the selected ellipse or line and on the tool. A swatch from the colour button recolours the selection.
- [ ] Save, and open the PNG in Preview at actual size: the ellipse and the line match the editor in position, width and colour, and their edges are smooth.

## Pencil and Highlighter
- [ ] Pencil (`P`): a freehand drag draws a smooth line in the stroke colour and width, with no visible corners at fit zoom and at 400%. A fast scribble stays smooth and keeps up with the mouse. One stroke is one ⌘Z.
- [ ] A click, or a stroke that never gets 2 pt from where it started, adds nothing and never crashes. Escape mid-stroke drops it.
- [ ] Select a stroke: a click within a few pixels of the line picks it, and a click inside a loop of the stroke does not. A drag moves the whole stroke. Delete removes it.
- [ ] Highlighter (`H`): a drag draws a wide yellow stroke, 12 pt, translucent (45% opacity). Draw it over the white page and over the dark text of the Terminal or TextEdit capture: the text under it stays fully readable and dark; the highlighter never lightens black text.
- [ ] Draw two highlighter strokes that cross: the crossing is darker than either stroke. One stroke that crosses itself is not darker where it crosses. A highlighter stroke over a dark Terminal background darkens it slightly and never turns it light. A swatch picked with the Highlighter active keeps the stroke translucent.
- [ ] Save and open the PNG in Preview at 400%: the highlighter over the text matches the editor (yellow over white, dark text unchanged), and the pencil line is smooth, not stepped.

## Text
- [ ] Text (`T`): a click on the canvas places a text box whose first line is centred on the click and starts editing, with a visible insertion point, in the stroke colour at 20 pt; typing appears at the size you will get in the export. Return (or Enter, or Tab) commits. The new text is selected, with a dashed outline. A drag with Text places nothing.
- [ ] Shift-Return (or ⌥Return) inserts a newline and Return then commits. Escape cancels: a new text disappears, and an edit of existing text restores the earlier string. Clicking elsewhere on the canvas commits. Committing an empty text adds nothing.
- [ ] Keys `1` to `6`, with the Text tool active and not editing, set the size to 12, 16, 20, 28, 40 and 56 pt on the tool and on a selected text. While editing, the digits type digits.
- [ ] The colour button recolours the selected text and the Text tool. Choose a colour, place a text: it uses that colour.
- [ ] Click committed text with Text, or double-click it with Select: editing starts with the caret in the text and the existing string, at the same position and size. Change it and press Return: the text changes in place.
- [ ] While editing, ⌘A selects the text in the box and not every annotation. ⌘C copies the selected characters; paste them into TextEdit to check, and the editor shows no `Image copied` notification. ⌘X cuts the characters. ⌘V pastes characters at the caret. ⌘D does not duplicate anything while editing.
- [ ] Undo while editing: type three words, ⌘Z removes typing step by step (the characters only), ⇧⌘Z restores them. No annotation is added or removed by those keys. The unsaved dot appears as soon as the typed text would change the capture, before it is committed.
- [ ] Undo after committing: draw a rectangle, place a text, commit it. ⌘Z removes the whole text in one step (not letter by letter); ⌘Z again removes the rectangle; ⇧⌘Z twice brings both back. Edit an existing text and commit: ⌘Z restores the earlier string in one step. Clear a re-edited text and press Return: it is deleted, and ⌘Z brings it back.
- [ ] While editing, Save (⌘S), Save As… (⇧⌘S), Copy Image (⇧⌘C), Upload (⌘U), the zoom commands and ⌘W commit the text first: ⌘S writes a PNG that contains the text, and ⌘W with an uncommitted change shows the unsaved-changes sheet. Picking another tool in the toolbar commits; a tool letter types the letter.
- [ ] Select a committed text: a drag moves it, Delete removes it, `←` nudges it one pixel. The selection shows a box that encloses the text.
- [ ] Parity with the export at 100% and 200%: type a text of two lines at 20 pt and a third line at 40 pt. Set the zoom pop-up to 100 %, take a ⌃⇧4 capture of the text in the editor, then ⌘S and open the saved PNG in Preview at actual size. Line breaks, glyph shapes and the text's width match to within a point. Repeat with the zoom pop-up at 200 %: the editor shows the same text twice as large, and the saved PNG is unchanged.
- [ ] Text over a redaction or a blur: the text draws above the effect, and a blur never blurs the text.
- [ ] A text near the right edge of the capture, partly outside it: the editor and the saved PNG both clip it at the image edge.

## Crop
- [ ] Crop (`C`): the selection goes, and the crop starts at the whole capture (or at the applied crop) with 8 handles and a readout of its size as W × H in image pixels (a Retina capture shows twice the points). Dragging a handle changes the rectangle and the readout, and the area outside it dims; dragging inside moves it (Shift locks the axis); dragging outside draws a new one (Shift squares, Option from the centre). It never extends outside the image.
- [ ] The unsaved dot appears once the draft differs from the applied crop. Return applies the crop as one `Crop` step and returns to the tool used before Crop; the canvas shows only the cropped area, fitted. ⌘Z removes the crop in one step (⇧⌘Z applies it again). Escape while cropping drops the draft, leaves the capture as it was (an earlier crop stays), and returns to the earlier tool.
- [ ] Draw a rectangle that straddles the crop's edge, then crop: the saved PNG contains only the part inside the crop.
- [ ] Saved pixel size: on a saved capture, crop to a readout of, say, 800 x 400, Return, ⌘S. `sips -g pixelWidth -g pixelHeight -g dpiWidth <file>` reports 800 x 400 (the readout, not the original size), and `dpiWidth` is 144 on the 2x display (72 on a 1x display). Quick Look shows only the cropped picture, and no new file appears.
- [ ] Thumbnail: open the Recent Captures menu. The row's thumbnail shows the cropped picture with its new proportions, and the hover preview shows the cropped image. The row's pixel size in `history.json` (`pixelWidth`, `pixelHeight`) equals the crop.
- [ ] Reopen the cropped capture with Annotate: the editor opens the cropped file at its new size, with no crop pending, and Crop starts from the whole picture again.
- [ ] Uploaded pixel size: on a capture uploaded with "Upload and copy URL", crop, then the Upload button. When the upload finishes, `curl -s <url> -o /tmp/crop.png && sips -g pixelWidth -g pixelHeight /tmp/crop.png` reports the cropped size, the file in the save folder is cropped too, and `history.json` has the cropped `pixelWidth` and `pixelHeight`. The link is the same as before.
- [ ] Upload-only capture that finished uploading: crop, ⌘U. The link then serves the cropped size.
- [ ] Save As… (⇧⌘S) with a crop: the new PNG has the cropped pixel size, and the capture's own file is unchanged.
- [ ] Copy (⌘C with nothing selected) with a crop: Preview, File > New from Clipboard, shows the cropped image at point size.
- [ ] Crop a redacted capture so that the redaction is partly outside: the saved PNG has no trace of the cropped-away part, and the part inside is still solid.
- [ ] Crop of the window capture with transparent corners, keeping a corner: the corner stays transparent in the saved PNG.
- [ ] A crop dragged back to the whole image and applied adds no undo step and saves at the original size. A draft cannot be made smaller than the tiny-drag size (2 pt), and nothing crashes trying.
- [ ] With a crop pending, pick another tool: the crop is applied as one `Crop` step. Draw across its edge: the part inside appears in the export, and the part outside is hidden by the window background on the canvas and absent from the file.

## Duplicate, copy and paste
- [ ] ⌘D on a selected rectangle makes a copy 10 pt down and to the right of the original and selects the copy; ⌘D again steps once more from the copy. One ⌘Z removes one copy. ⌘D with nothing selected beeps and adds nothing.
- [ ] ⌘D works on every kind: ellipse, line, pencil stroke, highlighter stroke, text, arrow, and an effect (a blur or a redaction; the copy of a redaction is a redaction).
- [ ] Option-drag a rectangle with Select: the original stays where it was and a copy is dragged; one ⌘Z removes the copy and the original does not move. Option is live: pressing it after the mouse went down turns the move into a copy, and releasing it mid-drag moves the original instead and leaves no copy. An Option-click without a drag changes nothing.
- [ ] Copy and paste in one editor: select an ellipse, ⌘C, ⌘V. A second ellipse appears 10 pt down and to the right and is selected; ⌘V again adds another one more step away. One ⌘Z per paste, named `Paste Ellipse`. Pasting into TextEdit pastes nothing.
- [ ] Between two editors: open the two captures from Setup in two editor windows. Select a text in the first, ⌘C, switch to the second window, ⌘V: the text appears in the second capture, selected, with the same string, size in points and colour (also when one capture is 1x and the other 2x). The first editor is unchanged. The second editor shows the unsaved dot, the first does not. Repeat with a pencil stroke and a redaction.
- [ ] ⌘C with nothing selected still copies the flattened image (`Image copied`; Preview > New from Clipboard shows it). With an object selected, ⌘C copies the object and ⇧⌘C and the toolbar's Copy button still copy the image.
- [ ] ⌘V with nothing on the clipboard to paste, or with an image or text on it, beeps and adds nothing. ⌘V while Crop is active beeps. ⌘X with an object selected does nothing to the object.
- [ ] While editing text, ⌘V and ⌘X act on the text, as in the Text section, and ⌘D duplicates nothing.

## Space-drag pan
- [ ] Zoom to 200% so the picture is bigger than the window. Hold Space and drag with Select, then with Rectangle, Pencil, Text and Crop: the picture pans under the pointer, nothing is drawn, nothing moves and no annotation is selected or created. Release Space and the tool works again.
- [ ] Space-drag pans as freely as scrolling does (neither stops at the picture's edge); ⌘0 fits the picture again. Scrolling and the trackpad still pan as before. A Space press never beeps, and holding it (key repeat) beeps neither.
- [ ] Press and release Space in the middle of a Rectangle drag: the drag goes on drawing, the editor is never left stuck in pan mode, and the next drag draws a rectangle again. Release Space mid-pan: the pan goes on until the mouse button is released. Hold Space, ⌘-Tab away and back, then click: the tool works.
- [ ] While editing text, Space types a space. With a crop pending (not yet applied), Space-drag pans and does not move the crop.
- [ ] Space-drag at Fit moves the picture off centre and the fit no longer follows window resizes, as after a scroll; ⌘0 fits again.

## Annotate from Recent Captures, with the 4b tools
The row's Annotate button was built in 4a; these confirm it with the new tools.
- [ ] Saved capture, never uploaded: Annotate on its row opens the editor. Place a text and an ellipse, crop, ⌘S: the same file now shows all three (cropped, with the text and ellipse inside).
- [ ] Capture uploaded with "Upload and copy URL": Annotate on its row, highlight a line, ⌘U. The editor closes at once, and the link shows the highlight.
- [ ] Upload-only capture whose upload failed: opens from `pending/<UUID>.png`; add a pencil stroke, ⌘S writes the pending file, Retry Failed Uploads uploads it with the stroke.
- [ ] Upload-only capture that finished uploading: Annotate downloads the object and opens `Capture <time>`; add text, crop and ⌘U. The link serves the cropped image with the text.
- [ ] Settings > Overlay, turn "Show Quick Access overlay after capture" off. Capture in each after-capture mode and press Annotate on the new row: the editor opens every time, and a 4b tool works in it. Turn the overlay back on.

## Reopening a stale upload-only record
- [ ] Enter a wrong secret access key in Settings > Upload and press Save. On an upload-only capture that finished uploading, Annotate, add text, crop to a readout you note, ⌘U. The editor closes, and after the retries a notification says `Upload failed. The link still shows the earlier image.` Quit TidyShot and relaunch.
- [ ] The row still copies the old URL. Annotate on the row reopens the edit with the text and at the cropped size, with the subtitle `The uploaded copy still shows the original. Upload to replace it.` (the pending file holds the cropped, edited bytes).
- [ ] Enter the right key and press ⌘U: the same URL now serves the cropped image with the text, `pending/<UUID>.png` is gone, and the row's pixel size in `history.json` is the cropped size.

## Selection, undo and export across the tools
- [ ] ⌘A selects the front-most annotation (drawings before effects), whichever tool made it: an ellipse, line, stroke or text included. Delete removes it; one ⌘Z brings it back. While Crop is active ⌘A selects nothing.
- [ ] Draw one of each tool (Redact, Pixelate, Blur, Rectangle, Arrow, Ellipse, Line, Pencil, Highlighter, Text): ten ⌘Z remove them newest first and ten ⇧⌘Z bring them back in order. Crop is a separate undo step.
- [ ] A click picks the topmost annotation: an arrow over an ellipse picks the arrow; a click inside an unfilled ellipse or rectangle picks what is underneath.
- [ ] A pencil stroke or highlighter drawn over a blur or a redaction stays above it, and the blur/redaction is never changed by a drawing above it.
- [ ] ⌘S, and in Preview at 400%: every tool matches the editor at the same zoom in position, width, colour and opacity. Pixels outside every annotation equal the original.
- [ ] A 5K capture (`⌃⇧3` on the 2x display, 5120 by 2820 pixels): draw with Pencil and Highlighter across the picture at fit zoom and at 400%. Drawing follows the mouse without stutter, and Save finishes in about a second.

## VoiceOver
Turn VoiceOver on (⌘F5). Draw an ellipse, a line, a stroke, a highlight, a text with the string `Hello` and a redaction in an editor first.
- [ ] VO-arrow around the window: the toolbar tools are read by name and the current tool as selected; the colour button, the options button, the zoom pop-up, Copy, Save and Upload are read by name.
- [ ] VO-arrow into the canvas: it reads `Annotation canvas` (a layout area). Inside it, each annotation is its own element, in painting order (every effect first, then every drawing, each in creation order), labelled with its kind and a number counted per kind (`Redact 1`, `Ellipse 1`, `Line 1`, `Pencil 1`, `Highlighter 1`, `Text 1`; a second arrow is `Arrow 2`), and a text's value is its string (`Hello`). The VoiceOver cursor box around each element matches the shape on screen, also after zooming and panning.
- [ ] Move, resize or delete an annotation with the mouse: the elements follow at once, with no stale element left and no element for a deleted annotation. A newly drawn annotation appears as the last element.
- [ ] The selected annotation is reported as selected. Selecting another with the mouse moves that state.
- [ ] With a crop applied, an annotation outside the crop is still listed (it stays in the document), with its frame where it would be uncropped; VO-Space on any element while Crop is active does nothing.
- [ ] VO-Space on an element selects that annotation; Delete, the arrow keys, ⌘C and ⌘D then act on it.
- [ ] Turn VoiceOver off. The editor behaves as before, and no accessibility work runs for a window with no VoiceOver (typing and drawing feel the same).
````

- [ ] **Step 3: Point the 4a checklist at the 4b one**

In `docs/testing/phase-4a-manual-checklist.md`, after the intro paragraph that ends `everything here needs real windows, a real bucket and eyes.` (line 6), add a blank line and:
```markdown
Phase 4b added six tools (Ellipse, Line, Pencil, Highlighter, Text, Crop). Where an item below lists
the six 4a tools, the toolbar and tool-letter items of `phase-4b-manual-checklist.md` list all
twelve; this checklist's other sections are unchanged.
```
Change nothing else in the 4a checklist.

- [ ] **Step 4: Update the README**

In `README.md`, replace lines 97-104 (from `Tools and their keys:` through `button stays in view.`) with:
```markdown
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
size in pixels), and press Return to apply or Escape to cancel; picking another tool applies it. A crop is undoable and applies last, so Save, Save As…, Copy and Upload all produce the
cropped image, the capture's recorded size and thumbnail follow it, and nothing outside the crop
is in the saved or uploaded file.

With Select, ⌘D duplicates the selection 10 points down and to the right, and dragging it with
Option held drags a copy. ⌘C copies the selected object and ⌘V pastes it, in the same editor or
another one, at the same size in points; with nothing selected ⌘C still copies the image. Hold Space and drag to pan. Each annotation is an accessibility element,
so VoiceOver can read the canvas.
```

Replace the table and the line after it (lines 106-119, from `| Action | Shortcut |` through `Pinch or ⌘-scroll to zoom around the pointer; scroll to pan.`) with:
```markdown
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
```

After the line `- Phase 4a manual test checklist: …` (line 176), add:
```markdown
- Phase 4b manual test checklist: `docs/testing/phase-4b-manual-checklist.md`
```

Then confirm no limitation or "coming" text remains:
```bash
grep -ni "limitation\|4b\|not yet\|coming\|later phase" README.md docs/testing/phase-4a-manual-checklist.md docs/testing/phase-4b-manual-checklist.md
```
Expected: only the two new lines that name Phase 4b (the Documents entry and the pointer in the 4a checklist), and the checklist's own title and prose. A README or 4a checklist line that says a tool or feature is missing or coming in 4b is deleted.

- [ ] **Step 5: Run the full suite and check the totals table**

Run:
```bash
xcodegen generate && xcodebuild test -project TidyShot.xcodeproj -scheme TidyShot -destination 'platform=macOS' -derivedDataPath .build 2>&1 | grep -E "Test run with|error:|TEST"
```
Expected: no `error:` lines, `** TEST SUCCEEDED **`, and `Test run with 458 tests in 57 suites passed`. This task adds no tests, so that count must equal the Task 5 row and the Task 6 row of the "Test totals" table in the plan's header section.

Reconcile the table against the repo:
```bash
grep -rhE '^(@MainActor )?(nonisolated )?struct [A-Za-z0-9]+Tests\b' TidyShotTests | wc -l; grep -rhE '^\s*@Test' TidyShotTests | wc -l
grep -c '{{' docs/superpowers/plans/2026-10-20-phase-4b-annotation-tools.md
```
Expected: the first count is the suites and the second the tests in the Task 6 row (one `struct …Tests` per suite; Swift Testing counts a parameterized `@Test` once), and the last count is `0`, so no placeholder is left in the plan. The branch starts from the 4a baseline of 414 tests in 52 suites. If the run differs from the Task 6 row, a review fix added or removed tests. Find which task with:
```bash
git log --oneline --stat 9193586..HEAD -- TidyShotTests
```
Correct that task's row and every row after it in the table, and add one line under the table: `Task 6 correction: <commit> <what changed>; the real run reads <the line>.` Change nothing else in the plan. If the run equals the row, change nothing.

- [ ] **Step 6: Check spec 2.6 against the build, and mark Phase 4 delivered**

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
This capture was deleted. Copy and Save As still work.
The destination changed, so this uploads as a new link.
Another capture shares this link, so this uploads as a new link.
The earlier upload stays in the bucket.
Do you want to save the changes made to “
Your changes will be lost if you don’t save them.
Don’t Save
Save As…
Upload as New
Annotation canvas
Edit Text
Text Size
io.tky.tidyshot.annotation
EOF
grep -n "case ellipse\|case line\|case pencil\|case highlighter\|case text" TidyShot/Editor/Model/Annotation.swift
grep -n "var crop" TidyShot/Editor/Model/AnnotationDocument.swift
grep -n "paste:\|duplicate:" TidyShot/Editor/Geometry/KeyRouting.swift
grep -rn "func commitTextEditing\|func duplicateSelection\|isEditingText" TidyShot/Editor | cut -c1-160
grep -rn "Annotate Last Capture\|CIPixellate\|allowsMagnification" TidyShot
grep -n "4b\|phase-4-annotation\|phase-4b" docs/superpowers/specs/2026-10-19-tidyshot-screenshot-design.md | cut -c1-160
```
Expected: no `MISSING:` lines; five `case` lines in `Annotation.swift`; one `crop` property; the two shortcut rows; the Task 3 and Task 5 functions; nothing from the next-to-last grep.

Then compare 2.6 with the code and amend it wherever they differ. At least check and, where the build differs, rewrite these places (in 2.6, lines 102-435):
- **Scope line** (line 104, "on the branch `phase-4-annotation`"): 4a landed on `phase-4-annotation` (PR 7) and 4b on `phase-4b-annotation` (PR 2). Write both.
- **Tools** (the table at lines 217-224 and the sentence at line 226): add a row each for Ellipse (E), Line (L), Pencil (P), Highlighter (H), Text (T) and Crop (C) with the behaviour the code has (Shift and Option on Ellipse, 45 degree snap on Line, the highlighter's colour, alpha and width, the text commit keys, Return and Escape on Crop), and change "4b adds Ellipse…" to say they were added.
- **Keyboard** (lines 251-262, 269): `KeyRouting.action` gains whatever parameters the text-size digits needed (read its real signature); ⌘V and ⌘D are in the table; ⌘X still has no row; the pass-through rows while editing text match `EditorShortcut`'s `passesThroughWhileEditingText`.
- **Window, Toolbar** (lines 281, 284): the tools group now has twelve items and `ToolbarMetrics` and the width arithmetic account for them; the toolbar still never overflows.
- **Phase 4b bullets** (lines 420-430): rewrite them as the built state. Keep the 4b checklist and README line. Where the code does something the bullets never said (Shift-Return, double-click re-edit, the digit text sizes, the paste offset, the duplicate offset, the accessibility labels), add it in one line each. Task 5 left these to this step, so 2.6 must name them verbatim: the canvas label `Annotation canvas`, element labels as kind plus per-kind number in painting order (`Redact 1`), the undo names `Duplicate <title>` and `Paste <title>` (with Task 3's `Add Text`, `Edit Text`, `Text Size` and Task 4's `Crop`), the 10 pt duplicate and paste step, and the private pasteboard type `io.tky.tidyshot.annotation`.
- Annotate from Recent Captures was built in 4a, not 4b; nothing in the 4b bullets claims otherwise.

For a divergence that looks like a bug rather than a decision (the code contradicts a sentence of 2.6 that was the intended behaviour), stop and report it; do not amend 2.6 to match a bug. Record every amendment as one line in the report.

Mark the phase delivered in section 6. In the "### Phase 4: annotation (1 to 2 weeks)" block (lines 557-561), after the 4c bullet (line 561) add a blank line and:
```markdown
Delivered <date of this run, YYYY-MM-DD>: 4a in PR 7 (merge commit 9193586) and 4b in PR 2 on `phase-4b-annotation`. Phase 4 is released when PR 2 merges. Design and what was built: 2.6.
```
Write the real date, not the placeholder.

- [ ] **Step 7: Run the end-to-end check**

Run:
```bash
xcodebuild -project TidyShot.xcodeproj -scheme TidyShot -configuration Debug -derivedDataPath .build build -quiet && open .build/Build/Products/Debug/TidyShot.app
```
In "Upload only, keep no local file": run `echo SECRET-TOKEN-0123456789` in Terminal, `⌃⇧2` on the Terminal window, Annotate on the overlay. Press `D` and drag over the token, `T` and click above it to type `check`, Return, `C` and drag a crop that keeps both, Return, then ⌘U. The editor closes; when the upload finishes, `curl -s <link> -o /tmp/p4b.png && sips -g pixelWidth -g pixelHeight /tmp/p4b.png` reports the crop's size, and the picture has the black box and the text. Then work through `docs/testing/phase-4b-manual-checklist.md`, and report which items were run (and whether the 1x display, the second display and the VoiceOver items were skipped).

- [ ] **Step 8: Commit**

```bash
git add docs/testing/phase-4b-manual-checklist.md docs/testing/phase-4a-manual-checklist.md README.md docs/superpowers/specs/2026-10-19-tidyshot-screenshot-design.md
git add docs/superpowers/plans/2026-10-20-phase-4b-annotation-tools.md
git commit -m "docs: Phase 4b checklist and README"
```
The plan is in the list so that a Step 5 correction lands in this commit; when the table is unchanged, `git add` leaves it out.

- [ ] **Step 9: Stop here**

Phase 4b is done when the last test run reads `Test run with 458 tests in 57 suites passed` and the checklist passes. Do not push and do not open a PR: the controller opens PR 2 after the whole-branch review, and Phase 4 is released when PR 2 merges. Report the final test line, which checklist items were run (and which were skipped), every checklist or README sentence changed in Step 1 to follow the code, and every amendment made in Step 5 or Step 6.

---
