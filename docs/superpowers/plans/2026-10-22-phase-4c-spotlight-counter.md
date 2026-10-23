# TidyShot Phase 4c: Spotlight and Counter, Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Two editor tools. Spotlight (`S`) dims everything outside one or more rectangles or ellipses, and Counter (`N`) drops numbered circles for step-by-step shots. Both move, duplicate, copy, paste, undo, export and read in VoiceOver like the other annotations.

**Architecture:** Spec section 2.12 of `docs/superpowers/specs/2026-10-19-tidyshot-screenshot-design.md` is the full specification: names, strings, constants, the overlay's method, the hit, paint and accessibility orders, the undo names and the tests. Section 2.6 holds the editor rules that 2.12 builds on and amends in four places. When this plan and 2.12 disagree, 2.12 wins.
- **Model.** Two new `Annotation` cases. A spotlight is neither an effect nor a drawing: `AnnotationDocument.spotlights` is a third list, painted between the two as one overlay with one document-wide `spotlightDim`. A counter is a drawing.
- **One overlay routine.** `AnnotationDrawing.drawSpotlightOverlay` serves the flattener (once per `ImageTiling` strip, composited `.sourceAtop`) and the canvas (inside the image-pixel CTM block, composited `.normal` and masked by the capture's alpha through `HighlighterBackdrop.draw`).
- **One numbering rule.** `Annotation.renumbered(in:)`, applied in `commitNewShape`, numbers every new counter: Add, ⌘D, the ⌥-drag copy and ⌘V.

**Tech Stack:** Swift 6 language mode with default `MainActor` isolation and `NonisolatedNonsendingByDefault`, CoreGraphics (transparency layers, blend modes), CoreText, AppKit, SwiftUI (the options popover), Swift Testing, XcodeGen 2.46.

Work happens on the branch `editor-4c`, stacked on `recording-r1` at its current HEAD (15d5d70 when this plan was written). The spec commit is 784ad34; the amended 2.12 is committed with this plan.

## Global Constraints

- **Earlier constraints still apply.**
  - Minimum macOS 26.0, Swift 6 with MainActor by default, App Sandbox, credentials only in the Keychain.
  - One save, upload and delete path in `AppCoordinator`. 4c changes nothing there.
  - The editor never writes files or the pasteboard itself. Object copy and paste still go through `EditorObjectClipboard`.
  - KeyboardShortcuts is the only Swift package. No GPL code is read or copied.
- **No new entitlement and no new package.** No settings keys beyond the two editor defaults, `editorSpotlightEllipse` and `editorCounterDiameterPoints`.
- **Off the main actor.** Under `NonisolatedNonsendingByDefault` a `nonisolated async` function runs on the caller's executor, so async work that must leave the main actor is `@concurrent` or a detached task, as `renderExport`'s flatten already is. The new model and geometry types (`SpotlightShape`, `CounterMark`, `SpotlightGeometry`, `CounterLayout`) are `nonisolated` and `Sendable`. The overlay routine and the counter drawing are `nonisolated`, so the flattener calls them inside its detached task.
- **`draw(_:)` only draws.** No Core Image, GPU work, decoding or new bitmaps inside `CanvasView.draw(_:)`. The overlay and the counters are CoreGraphics and CoreText calls. The overlay's coverage list reuses the base tiles and shown effect tiles the canvas already holds, as the highlighter backdrop does.
- **The model stores values.** `RGBA`, rects, points, numbers and Bools only; never a CGColor, NSColor, CGPath or CGImage. The dim is a `Double`.
- **Export equals preview.** The flattener and the canvas draw spotlights and counters through the same `AnnotationDrawing` routines. Pixels outside the effects, the drawings and the overlay equal the base byte for byte, and alpha survives everywhere, under the overlay too (2.12 amends 2.6 Export).
- **Exact strings, names, constants and orders** come from 2.12: letters, titles, symbols, tool tips, option labels and stops, undo names, accessibility labels, and the hit, paint and accessibility orders.
- **Tests** use Swift Testing, run with:
  ```bash
  xcodegen generate && xcodebuild test -project TidyShot.xcodeproj -scheme TidyShot -destination 'platform=macOS' -derivedDataPath .build 2>&1 | grep -E "Test run with|error:|TEST"
  ```
  The baseline is `Test run with 1193 tests in 126 suites passed`. The Release build is `xcodebuild -project TidyShot.xcodeproj -scheme TidyShot -configuration Release -derivedDataPath .build-rel build`.
- **Commits.** Commit after every task with a conventional message and no attribution lines, and never push.

### Task 1: Model, tools, keys, clipboard coding and defaults

**Files:**
- Modify:
  - `TidyShot/Editor/Model/Annotation.swift`, `AnnotationDocument.swift`, `EditorTool.swift`, `EditorPalette.swift`;
  - `TidyShot/Editor/Geometry/ArrowGeometry.swift` (`AnnotationGeometry`), `HitTester.swift`, `CropGeometry.swift` (`press`), `EditorWindowGeometry.swift` (the `ToolbarMetrics.segment` comment);
  - `TidyShot/Editor/Rendering/AnnotationDrawing.swift` (`draw`, `drawSelection`);
  - `TidyShot/Editor/Tools/ToolFactory.swift` (`makeTool(for:)`);
  - `TidyShot/Editor/Session/EditorModel.swift` (`init`, the two defaults, `makeAnnotation`);
  - `TidyShot/Editor/Window/EditorToolbar.swift` (`currentDefaults`, `storeChangedDefaults`);
  - `TidyShot/Settings/AppSettings.swift`.
- Create the test `TidyShotTests/SelectionOutlineTests.swift`.
- Tests: add to `EditorToolTests`, `KeyRoutingTests`, `AnnotationDocumentTests`, `HitTesterTests`, `CropGeometryTests`, `AnnotationClipTests`, `EditorWindowGeometryTests`, `EditorToolbarTests`, `EditorPaletteTests` and `AppSettingsTests`.

**Produces** (model and geometry `nonisolated`, `Sendable`):
- Beside `ShapeBox` in Annotation.swift: `struct SpotlightShape: Codable, Equatable { let id: UUID; var rect: CGRect; var isEllipse: Bool }` and `struct CounterMark: Codable, Equatable { let id: UUID; var center: CGPoint; var number: Int; var diameter: CGFloat; var color: RGBA }`.
- `Annotation.spotlight(SpotlightShape)` and `Annotation.counter(CounterMark)`, with `var spotlightShape: SpotlightShape?`, `var counterMark: CounterMark?` and `var isSpotlight: Bool`.
- `AnnotationDocument`:
  - `var spotlightDim: Double? = nil` and `static let defaultSpotlightDim = 0.5`;
  - `var effectiveSpotlightDim: Double` (nil reads as 0.5);
  - `func withSpotlightDim(_ dim: Double) -> AnnotationDocument`, which stores 0.5 as nil;
  - `var spotlights: [Annotation]`, and `drawings` without them.
- `EditorTool.spotlight` and `EditorTool.counter`.
- `AnnotationGeometry.selectionOutline(of:) -> CGRect?`.
- `EditorPalette.spotlightDims: [Double] = [0.3, 0.5, 0.7]`, `counterDiametersPoints: [CGFloat] = [24, 32, 44]` and `defaultCounterDiameterPoints: CGFloat = 32`.
- `EditorDefaults.spotlightEllipse: Bool` and `counterDiameterPoints: CGFloat`; `EditorModel.spotlightEllipse` and `counterDiameterPoints`; `AppSettings.editorSpotlightEllipse: Bool` and `editorCounterDiameterPoints: Double`.

**Steps:**
- [ ] Write the failing tests:
  - `EditorToolTests`:
    - fourteen tools in the order `select, redact, pixelate, blur, spotlight, rectangle, arrow, ellipse, line, pencil, highlighter, text, counter, crop`;
    - letters unique, with `[.spotlight, .counter]` pinned to `["S", "N"]` and the tips `Spotlight (S)` and `Counter (N)`;
    - Spotlight is not an effect;
    - `toolbarOrderCoversEveryToolOnce`: `dropFirst(phase4a.count).prefix(2)` becomes `[.arrow, .ellipse]`, and its comment says Ellipse and Line follow Arrow.
  - `KeyRoutingTests`: `S` and `N`, in either case, pick Spotlight and Counter.
  - `AnnotationDocumentTests`:
    - bounds and move for both kinds;
    - a Codable round trip of a document holding both and a dim;
    - a document without `spotlightDim` decodes and reads 0.5, and `withSpotlightDim(0.5)` stores nil;
    - `spotlights` holds the spotlights in creation order, `drawings` leaves them out, and a counter is a drawing;
    - both kinds survive `scaled(by:)`: a spotlight's rect scales, a counter's centre and diameter scale and its number does not;
    - `withID` keeps a counter's number; `withColor` recolours a counter and returns a spotlight unchanged; `withLineWidth` and `withEffectParameter` return both unchanged.
  - `HitTesterTests`, through `HitTester.hit` (the order through `topmost` is Task 2):
    - a spotlight's body is filled: a point inside a rect spotlight, or within the tolerance outside its edge, hits; inside an ellipse spotlight hits, its bounding-box corner misses;
    - a spotlight has the 8 box handles and resizes through `resizedRect`;
    - a counter's body is its circle grown by the tolerance; it has no handles and does not resize.
  - `CropGeometryTests`: outside an applied crop, `press` gives `.clampedToEdge` for Spotlight and `.ignore` for Counter.
  - `SelectionOutlineTests` (new): `selectionOutline` of a counter is its bounding square and of a spotlight its rect; every existing kind gives what `effectRect ?? strokeOutline ?? textFrame` gave.
  - `AnnotationClipTests`: a counter and a spotlight round-trip through `encoded()` and `decoded(from:)`; a counter placed from a 2x clip into a 1x editor has its centre and diameter halved and keeps its number.
  - `EditorWindowGeometryTests.toolbarWithEveryToolFitsASmallDisplay`: 14 tools and 1134 pt; its history comment gains the 4c line.
  - `EditorToolbarTests.measuredToolbarFitsASmallDisplay` (new test): put `EditorWindowController.makeToolsControl(selected:).fittingSize.width` into `EditorWindowGeometry.toolbarWidth` as `minimumToolbarContentWidth()` does. Use the `ToolbarMetrics` window buttons, a 230 pt title, five buttons, one prominent button, the 84 pt zoom pop-up and one fixed space, and expect at most 1152 pt.
  - `EditorPaletteTests`: the standard defaults add `spotlightEllipse == false` and `counterDiameterPoints == 32`.
  - `AppSettingsTests`:
    - the round trip carries the two values under `editorSpotlightEllipse` and `editorCounterDiameterPoints`;
    - a fresh store reads false and 32, which is registered;
    - a stored 40 reads as 32.
- [ ] See them fail to compile.
- [ ] Model:
  - Add the payloads and cases, and every switch in Annotation.swift: `id`, `isEffect` (false), `effectRect` (nil), `title` (`Spotlight`, `Counter`), `moved`, `withID`, `scaled(by:)`, `withColor`, `withLineWidth` and `withEffectParameter`.
  - In `AnnotationDocument`, add the dim, its accessor and `withSpotlightDim`, and add `spotlights`. `drawings` becomes `!isEffect && !isSpotlight`. Its doc comments say spotlights are a third list, painted between effects and drawings.
- [ ] Tools:
  - Add the two `EditorTool` cases with 2.12's letters, titles and symbols (`light.max`, `1.circle`). `toolbarOrder` puts Spotlight after Blur and Counter after Text.
  - `makeTool(for:)`: `.spotlight` gets `RectDragTool(tool: .spotlight)`. `.counter` gets `RectDragTool(tool: .counter)` for now, which places nothing, because `makeAnnotation` returns nil for it. Task 3 replaces it with `CounterTool`.
  - `EditorModel.makeAnnotation`: `.spotlight` and `.counter` return nil for now, with a comment that Tasks 2 and 3 build them.
  - `CropGeometry.press`: `.clampedToEdge` for Spotlight, `.ignore` for Counter.
  - `AnnotationDrawing.draw`: nothing for a spotlight, which the overlay draws (Task 2). Nothing for a counter yet (Task 3).
- [ ] Geometry:
  - `AnnotationGeometry.bounds`: a spotlight's rect, and a counter's circle box (`center` ± `diameter / 2`). Both get the anti-alias margin, as now.
  - `AnnotationGeometry.selectionOutline(of:)` is an exhaustive switch with no `default`. It gives the effect rect, the stroke outline and the text frame as before, nil for a rectangle, ellipse, arrow or line, a spotlight's rect, and a counter's bounding square.
    - `drawSelection` uses it in place of `effectRect ?? strokeOutline ?? textFrame`. Its private `textFrame(of:)` goes, and its doc comment names the two new kinds.
  - `HitTester`:
    - `handles(for:)`: `boxHandles(rect)` for a spotlight, none for a counter;
    - `resized`: a spotlight through `resizedRect`, a counter unchanged;
    - `bodyContains`: a spotlight's rect, or the ellipse in it, grown by the tolerance, with no band; a counter's circle, within `diameter / 2 + tolerance` of the centre.
    - Update the doc comments of `handles(for:)` and `bodyContains`.
- [ ] Defaults:
  - `EditorDefaults` gains the two fields with no default values, so every call site is updated: `standard`, `AppSettings.editorDefaults`, `EditorModel.currentDefaults` (EditorToolbar.swift), and the `AppSettingsTests` and `EditorPaletteTests` literals.
  - `EditorModel` holds `spotlightEllipse` and `counterDiameterPoints`, set in `init`. `currentDefaults` and `storeChangedDefaults` carry them.
  - `AppSettings` adds:
    - the two keys, and properties whose `didSet` writes them;
    - `false` and `32.0` in the registered defaults;
    - the init reads, where a size not in `EditorPalette.counterDiametersPoints` reads as 32;
    - both values in `editorDefaults`, get and set.
  - The "five editor keys" and "five editor values" comments (AppSettings.swift, EditorPalette.swift, AppSettingsTests) become seven.
- [ ] The `ToolbarMetrics.segment` comment ends "twelve after 4b, fourteen in 4c".
- [ ] Run the full suite.
- [ ] Hand check in the Debug build, on a 1280 pt wide display (Tim's primary is one):
  - open the editor on a capture with a long title and shrink the window to its minimum. All fourteen tools, Colour, Options, Background, the zoom pop-up, Copy, Save and Upload show, with no chevron;
  - S and N move the segment.

  If anything overflows, stop and report `minimumToolbarContentWidth()` and the control's fitting width; do not ship an overflow (2.12 Shared, Toolbar). Note in the report if the check could not be done.
- [ ] Commit: `feat: Spotlight and Counter model, keys and defaults`.

### Task 2: Spotlight

**Files:**
- Create `TidyShot/Editor/Geometry/SpotlightGeometry.swift`.
- Modify:
  - `TidyShot/Editor/Model/Annotation.swift` (`withSpotlightShape(isEllipse:)`);
  - `TidyShot/Editor/Rendering/AnnotationDrawing.swift` (the overlay and the tool's outline), `EditorFlattener.swift` (step 3 and the type's doc comment);
  - `TidyShot/Editor/Geometry/HitTester.swift` (`topmost`), `CanvasAccessibility.swift` (`items`);
  - `TidyShot/Editor/Session/EditorModel.swift` (`makeAnnotation`, `selectAll`, the Shape and Dim options, `colorApplies`, `ActionName`);
  - `TidyShot/Editor/Tools/SelectTool.swift` (its doc comment);
  - `TidyShot/Editor/Window/CanvasView.swift` (`Shown`, `refresh()`, `draw(_:)`, `displayedDrawings`, `drawHighlighterBackdrops`), `ToolOptionsView.swift`, `EditorToolbar.swift` (`validateToolbarItem`, the Options tool tip).
- Create tests: `TidyShotTests/SpotlightRenderingTests.swift`, `SpotlightDisplayTests.swift`.
- Tests: add to `HitTesterTests`, `CanvasToolTests` (with `.spotlight` in `FakeCanvasEditing.makeAnnotation`), `EditorModelTests`, `CanvasAccessibilityTests` and `EditorBackgroundExportTests`.

**Consumes:** Task 1's model, tool, geometry and defaults.

**Produces:**
- `AnnotationDrawing.drawSpotlightOverlay(_ shapes: [SpotlightShape], dim: Double, in context: CGContext, imageRect: CGRect, coverage: [(rect: CGRect, image: CGImage)]?)`, `nonisolated`.
- `AnnotationDrawing.drawSpotlightOutline(_ shape: SpotlightShape, transform: CanvasTransform, scale: CGFloat, in context: CGContext)`: the tool's outline, in view space.
- `SpotlightGeometry.displayedSpotlights(in document: AnnotationDocument, transient: Annotation?) -> [Annotation]`, pure, like `RedactionTileCache.orderedEffects`.
- `CanvasView.Shown`, no longer private, with `hasSpotlights`, `showsSpotlightOutlines` and `func allowsPartialRepaint(since previous: Shown) -> Bool`.
- `EditorModel`:
  - `applySpotlightShape(isEllipse:)`, `applySpotlightDim(_:)` and `activeSpotlightEllipse`;
  - `spotlightShapeApplies`, `spotlightDimApplies` and `colorApplies`;
  - `ActionName.spotlightShape` (`Spotlight Shape`) and `ActionName.spotlightDim` (`Spotlight Dim`).

**Steps:**
- [ ] Write the failing tests. Some order tests pass before the change, because Task 1 left spotlights out of every list; they guard the order.
  - `SpotlightRenderingTests`: every item 2.12 lists.
    - Flatten through `EditorFlattener.flatten` on images from `EditorFlattenerTests().makeImage`, and read them with `EditorFlattenerTests.Bitmap`. Reuse both; do not copy them.
    - For "an opaque base gives the same pixels as a `.normal` composite", build the reference by drawing the base into a bitmap and calling the routine with `coverage: []`.
    - The two canvas-order items draw into a transparent premultiplied RGBA bitmap flipped to y-down, as `HighlighterBackdropTests` does.
  - `SpotlightDisplayTests`:
    - `displayedSpotlights` puts the transient in place of its document copy, appends a new one, and ignores a transient of another kind;
    - `allowsPartialRepaint` is false when `hasSpotlights` or `showsSpotlightOutlines` flips;
    - it is true for a transient-only change while `hasSpotlights` stays true;
    - it stays false for each change the old guard sent to a full repaint.
  - `HitTesterTests`, through `topmost`:
    - an arrow inside a spotlight is hit first, whether it was made before or after the spotlight;
    - a click on bare image inside a rectangle spotlight hits its `.body`, and so does one within the tolerance outside its edge;
    - inside an ellipse spotlight a click hits it, and on its bounding-box corner it misses;
    - a redact inside a spotlight is hit, whichever was made first;
    - a spotlight's handle within the tolerance beats an effect's body under it.
  - `CanvasToolTests`:
    - the Spotlight drag commits `Add Spotlight`; Shift squares it; a tiny drag adds nothing;
    - a text inside a spotlight, made after it, is re-edited by the Text tool's click and by Select's double-click.
  - `EditorModelTests`:
    - ⌘A with an arrow made before a spotlight selects the arrow, and with only a spotlight selects the spotlight;
    - a new spotlight takes `spotlightEllipse`;
    - Shape and Dim on a selected spotlight are each one step, `Spotlight Shape` and `Spotlight Dim`, and undo and redo restore them;
    - a run of Dim clicks is one step;
    - Shape with nothing selected changes only `spotlightEllipse` and adds no step;
    - Dim with no spotlight adds no step and leaves `hasUnsavedChanges` false, and picking the dim in effect adds no step;
    - the Shape and Dim enable rules;
    - `colorApplies` is false for the Spotlight tool with no coloured selection and with a spotlight selected, and true otherwise;
    - with a spotlight selected, `activeColor` is unchanged.
  - `CanvasAccessibilityTests`: the order is effects, spotlights, drawings, and spotlights read `Spotlight 1`, `Spotlight 2` in that order.
  - `EditorBackgroundExportTests`: with a solid background, a transparent corner of the capture outside every spotlight shows the undimmed fill.
- [ ] See them fail.
- [ ] Drawing tool. `makeAnnotation(.spotlight, …)` returns a `SpotlightShape` with `isEllipse: spotlightEllipse` for a non-empty rect. `RectDragTool` already gives the Shift square, the Option centre and Rectangle's minimum side. `FakeCanvasEditing.makeAnnotation` builds one too.
- [ ] Overlay routine, as 2.12 Rendering gives it (Routine, Method, Alpha):
  - save the state;
  - set `.sourceAtop` when `coverage` is nil, else `.normal`, then begin a transparency layer;
  - set `.normal` and fill `imageRect` with black at `dim`;
  - set `.clear` and fill each shape: `fill(rect)`, or `fillEllipse(in:)`;
  - when `coverage` holds layers, set `.destinationIn`, begin a nested layer, set `.normal`, draw the list through `HighlighterBackdrop.draw`, and end the nested layer;
  - end the layer and restore.

  Inside each layer, set the mode each fill needs; the mode set before a layer begins is the one it composites with. The routine sets no clip of its own: the caller's clip bounds the layer. Its doc comment says why the export uses `.sourceAtop` and the canvas a coverage list, and gives 2.12's probe numbers (alpha 128 shows as 160 on the canvas at a 0.5 dim).
- [ ] Flattener. In step 3, after `setBlendMode(.normal)` and the flip and before the drawings loop: when `document.spotlights` is not empty, loop over `ImageTiling.tiles(width:height:)`. For each rect:
  - save the state and `clip(to:)` the rect;
  - call the routine with the shapes, `document.effectiveSpotlightDim`, the whole image rect and `coverage: nil`;
  - restore the state.

  Never call it once for the whole image, or straight after the tile loop. The type's doc comment states the amended Export rule.
- [ ] Canvas:
  - Extract the layer list `drawHighlighterBackdrops` builds (`baseView.baseTiles`, then `shownTile(for:)` of each `displayedEffects`) and its interpolation quality into two private helpers. The backdrops and the overlay both use them.
  - `displayedDrawings` no longer appends a transient spotlight.
  - `draw(_:)`:
    - Inside the CTM block and the background's rounded clip, after the placeholders and before the drawings, call the routine while any spotlight is displayed. Pass:
      - the displayed shapes whose rect meets the dirty rect;
      - `model.document.effectiveSpotlightDim`;
      - the whole capture as `imageRect`;
      - the backdrop layers as `coverage`, or `[]` when the base has no alpha channel (`alphaInfo` `.none`, `.noneSkipFirst` or `.noneSkipLast`, decided once in `init`).

      Set the backdrop's interpolation quality around the call. Draw it on every `draw(_:)` while a spotlight is displayed, with no bounds test.
    - After the crop cover and before the selection, while `model.tool == .spotlight`, call `drawSpotlightOutline` for every displayed spotlight. This is never drawn while cropping (that branch returns first) and is not clipped to an applied crop.
      - The outline is the shape's own edge: the rect, or the ellipse in it. It is 1 pt, white under black `outlineDash` dashes, through a two-tone stroke helper that `drawSelection` shares.
  - `Shown` gains:
    - `hasSpotlights`: any displayed spotlight;
    - `showsSpotlightOutlines`: `model.tool == .spotlight`.

    Both are set in `init` and in `refresh()`. `allowsPartialRepaint(since:)` holds the old guard plus the two fields, and `refresh()` uses it.
  - `draw(_:)`'s doc comment gives the new order: backdrops, placeholders, overlay, drawings, then the crop cover, the tool's outlines and the selection.
- [ ] Order:
  - `HitTester.topmost` builds its list from `spotlights + effects + drawings` reversed, so each pass runs over the drawings, then the effects, then the spotlights, front to back.
  - `EditorModel.selectAll` falls back to `document.spotlights.last(where: visible)`.
  - `CanvasAccessibility.items` lists `effects + spotlights + drawings`.
  - The doc comments of `topmost`, `selectAll`, `SelectTool` and `CanvasAccessibility` state the new orders.
- [ ] Options:
  - `Annotation.withSpotlightShape(isEllipse:)`; other kinds come back unchanged.
  - Predicates:
    - `spotlightShapeApplies`: the tool is Spotlight, or a spotlight is selected;
    - `spotlightDimApplies`: the document has a spotlight, and either of those holds;
    - `colorApplies`: false while a spotlight is selected, and while the tool is Spotlight and `color(of:)` the selection is nil; true otherwise.
  - `applySpotlightShape(isEllipse:)` always sets `spotlightEllipse`. With a spotlight selected, it commits the change as `Spotlight Shape` under the key `Spotlight Shape-<id>`, as `applyLineWidth` keys its steps. `activeSpotlightEllipse` is the selected spotlight's shape, else `spotlightEllipse`.
  - `applySpotlightDim(_:)` returns at once when the document has no spotlight. Otherwise it commits `withSpotlightDim` as `Spotlight Dim` under the one key `Spotlight Dim`. `commit`'s equality guard means the value in effect adds no step.
  - `ToolOptionsView`, after Pixel block:
    - a segmented `Shape` row (`Rectangle`, `Ellipse`) showing `activeSpotlightEllipse`;
    - a segmented `Dim` row (`30 %`, `50 %`, `70 %`) showing `effectiveSpotlightDim`.

    Both are disabled by their predicates, never swapped per tool. The view's doc comment describes the rows and the rules.
  - The Options tool tip becomes `Tool options`.
  - `validateToolbarItem` returns `model.colorApplies` for `.color`, and its doc comment says so.
- [ ] Run the full suite.
- [ ] Hand check in the Debug build, 2.12's Spotlight checks:
  - the live dim, Escape mid-drag and the minimum size;
  - moving and resizing both shapes with Select;
  - the outlines on S, then V, R, A, T and the toolbar, at 50 %, 100 % and 400 %;
  - a highlighter across the dim edge against a saved copy;
  - a crop with a Background;
  - a window capture with Include window shadow on and off;
  - a selected spotlight's outline and handles;
  - the Colour item, and the Options rows.

  Note in the report what could not be done.
- [ ] Commit: `feat: Spotlight tool`.

### Task 3: Counter

**Files:**
- Create `TidyShot/Editor/Tools/CounterTool.swift`, `TidyShot/Editor/Geometry/CounterLayout.swift` and the test `TidyShotTests/CounterTests.swift`.
- Modify:
  - `TidyShot/Editor/Model/Annotation.swift` (`renumbered(in:)`, `withCounterDiameter(_:)`), `AnnotationDocument.swift` (`nextCounterNumber`), `EditorPalette.swift` (`contrastingTextColor(for:)`);
  - `TidyShot/Editor/Rendering/AnnotationDrawing.swift` (the counter in `draw`);
  - `TidyShot/Editor/Tools/ToolFactory.swift` (`makeTool(for:)`, `commitNewShape`), `SelectTool.swift` (the ⌥-drag copy);
  - `TidyShot/Editor/Persistence/AnnotationClip.swift` (`placed`);
  - `TidyShot/Editor/Geometry/CanvasAccessibility.swift`;
  - `TidyShot/Editor/Session/EditorModel.swift` (`makeAnnotation`, `color(of:)`, the Size option, `ActionName`);
  - `TidyShot/Editor/Window/ToolOptionsView.swift`.
- Tests: add to `CanvasToolTests` (with `.counter` in `FakeCanvasEditing.makeAnnotation`), `EditorModelTests`, `AnnotationClipTests` and `CanvasAccessibilityTests`.

**Consumes:** Task 1's model and defaults; Task 2's options rows and `colorApplies`.

**Produces:**
- `CounterLayout`, pure:
  - `fontSize(number: Int, diameter: CGFloat) -> CGFloat`;
  - `center(forPress press: CGPoint, diameter: CGFloat, within bounds: CGRect) -> CGPoint`.
- `EditorPalette.contrastingTextColor(for: RGBA) -> RGBA`, pure.
- `AnnotationDocument.nextCounterNumber: Int`, `Annotation.renumbered(in: AnnotationDocument) -> Annotation` and `Annotation.withCounterDiameter(_:) -> Annotation`.
- `final class CounterTool: CanvasTool`.
- `EditorModel`: `applyCounterSize(points:)`, `activeCounterDiameterPoints`, `counterSizeApplies`, and `ActionName.counterSize` (`Counter Size`).

**Steps:**
- [ ] Write the failing tests:
  - `CounterTests`: every item 2.12 lists.
    - The next number with none, after 1-2-3, and after deleting 2 (4).
    - ⌘D, the ⌥-drag copy and ⌘V each number the new counter max + 1, through the real `EditorModel`.
    - Three pastes of one counter at scale 2 land at +20, +40 and +60 px as 2, 3 and 4. Model this on `EditorModelTests.pasteOntoItsOriginalCascades`.
    - `CounterLayout.center` clamps inside the image and inside the crop, and centres on an axis where they are smaller than the counter.
    - The text colour for every swatch, and for the 180/255 grey.
    - A counter rendered through `EditorFlattener`: the fill at `(center.x, center.y + 0.35 × diameter)`, and white just inside the edge.
    - 9, 42 and 100 each fit in 0.8 × diameter, and 100 is smaller than 0.55 × diameter.
  - `CanvasToolTests`:
    - a Counter click and a Counter drag both place at the press, as one `Add Counter`;
    - Escape during the press places nothing (the fake's `transient` set to nil);
    - with counters 1 and 2, an ⌥-drag of counter 1 shows a transient copy numbered 3, commits `Duplicate Counter` with number 3, and leaves counter 1 untouched;
    - releasing Option mid-drag shows the moved original numbered 1.
  - `EditorModelTests`:
    - a new counter has `counterDiameterPoints × scale` and `strokeColor`, and is centred on the press;
    - Size on a selected counter is one `Counter Size` step that keeps its centre, and undo and redo restore it;
    - Size with nothing selected changes only the default and adds no step;
    - the Size enable rule;
    - with a counter selected, `activeColor` is its colour, and `applyColor` recolours it as `Color`.
  - `AnnotationClipTests`: `placed` treats a counter with another number at the same place as identical, so it steps, and one with another diameter or colour as different.
  - `CanvasAccessibilityTests`: a counter reads `Counter <its number>` with no value, also after a middle counter is deleted.
- [ ] See them fail.
- [ ] Numbering:
  - `nextCounterNumber`: the largest counter number plus 1, or 1 with none.
  - `renumbered(in:)`: a counter comes back with the document's `nextCounterNumber`; any other kind comes back unchanged.
  - `commitNewShape` applies it before the commit, so Add, ⌘D, the ⌥-drag copy and ⌘V all pass through it. The id, and so the selection, is unchanged.
  - `SelectTool.update`: with Option held, the copy is `moved.withID(copyID).renumbered(in: canvas.document)`. The original is never renumbered.
  - `AnnotationClip.placed`: the cascade compares through a private helper. For two counters it compares centre, diameter and colour only; anything else compares as now (`withID(id) ==`). Step 3 of the doc comment says so.
- [ ] Placing:
  - `CounterLayout.center(forPress:diameter:within:)`: on each axis, the press clamped to `[min + d/2, max − d/2]`, or the bounds' middle when they are narrower than `d`.
  - `makeAnnotation(.counter, from: press, to: _)` builds a `CounterMark` with:
    - number `document.nextCounterNumber`;
    - diameter `counterDiameterPoints × scale`;
    - colour `strokeColor`;
    - centre from `CounterLayout.center` within `document.crop`, or else the image.

    `FakeCanvasEditing` mirrors it, with a 64 px diameter and the default stroke.
  - `CounterTool`:
    - the cursor is the crosshair;
    - mouseDown puts `makeAnnotation(.counter, from: press, to: press)` in `transient` and remembers it;
    - mouseDragged and flagsChanged do nothing;
    - mouseUp commits it through `commitNewShape` (`Add Counter`), only while `transient` still holds it.

    `makeTool(for: .counter)` returns it, replacing Task 1's stand-in.
- [ ] Drawing. `AnnotationDrawing.draw` draws a counter:
  - Fill the circle in its colour. Stroke a white ring `1.5 × scale` wide, inset by half its width, so nothing paints outside the diameter.
  - Draw the number with `TextLayout.font(size: CounterLayout.fontSize(...))` and `CTLineDraw`, in `contrastingTextColor(for:)`. Use `drawText`'s flipped text matrix and put it back by hand. Centre it horizontally by the line's typographic width, and vertically by the font's cap height, so digits sit on the centre.
  - `CounterLayout.fontSize`: start at 0.55 × diameter. While the line's typographic width there (`TextLayout.width(of:font:)`) is over 0.8 × diameter, scale the size by `0.8 × diameter / width` and measure again. The system font's optical sizes stop width scaling exactly with size, so one pass may not be enough.
  - `contrastingTextColor(for:)`: luma `0.2126 R + 0.7152 G + 0.0722 B` on the stored components. White under 0.5, else black.
- [ ] Colour and options:
  - `EditorModel.color(of:)` loses its `default`: a counter gives its colour, a spotlight nil.
  - `withCounterDiameter(_:)` sets a counter's diameter, and its centre stays put; other kinds come back unchanged.
  - `counterSizeApplies`: Counter is the tool, or a counter is selected.
  - `applyCounterSize(points:)` always sets `counterDiameterPoints`. With a counter selected, it commits `withCounterDiameter(points × scale)` as `Counter Size` under `Counter Size-<id>`.
  - `activeCounterDiameterPoints`: the selected counter's diameter over the scale, else the default.
  - `ToolOptionsView`: a segmented `Size` row after Dim (`Small`, `Medium`, `Large` for 24, 32 and 44 pt), disabled by `counterSizeApplies`. The doc comment gains it.
- [ ] Accessibility. `CanvasAccessibility.items` labels a counter `Counter <number>`. `value(of:)` already returns nil for it.
- [ ] Run the full suite.
- [ ] Hand check in the Debug build, 2.12's Counter checks:
  - placing shows the dashed outline and no handles;
  - Select moves the outline to another counter, and clicking empty space clears it;
  - Small counters on a 1x capture are legible and their ring shows;
  - ⌘C a counter, then ⌘V twice in another editor at another scale;
  - VoiceOver reads `Counter 3` after the second counter is deleted.

  Also recolour a selected counter, and place counters at the crop's edge and outside it. Note in the report what could not be done.
- [ ] Commit: `feat: Counter tool`.

### Task 4: Checklist, README and spec close-out

**Files:**
- Create `docs/testing/phase-4c-manual-checklist.md`.
- Modify `README.md`: the Annotate section, and a Documents line.
- Modify the spec: the 2.1 Annotate row, the 2.6 "Phase 4c (later, P2)" list, and Built notes at the end of 2.12.

**Steps:**
- [ ] Grep the finished code for every string 2.12 gives, and fix any drift. That covers letters, titles, symbols, tool tips, `Tool options`, the option labels and stops, the undo names, `Spotlight <n>` and `Counter <n>`.
- [ ] Write the checklist in the shape of the 7c one: what it covers, what the tests already cover, and the setup (a fresh Release build, then `defaults delete io.tky.tidyshot` for the two new keys). Then list every hand check in 2.12, plus:
  - Copy, Save, Save As… and Upload with spotlights and counters, each compared with the canvas at 100 %;
  - a scrolling capture over 16,384 px with a spotlight across a strip seam;
  - undo and redo of every new step name;
  - Shape and Size surviving a relaunch, and Dim not carrying into a new capture.
- [ ] README Annotate:
  - add Spotlight `S` and Counter `N` to the tool list, and the new Options rows to the toolbar sentence;
  - one paragraph on Spotlight: what it dims, Shift and Option, Shape and Dim, and that arrows, text and counters stay bright;
  - one on Counter: click to place, the numbering (the highest plus one, no renumbering on delete, new numbers for copies and pastes), Size, colour and the contrasting digits.

  Add the checklist to Documents.
- [ ] Spec:
  - the 2.1 Annotate row's note becomes `Built in Phase 4c (2.12): …`;
  - 2.6's 4c list marks Spotlight and Counter built;
  - add a **Phase 4c (built)** paragraph at the end of 2.12, in the style of 7c's. Give the date, the branch, the suite total, and that no entitlement or package was added. List every name or behaviour the build added or changed: the helpers this plan named, the tool outline's ellipse, the toolbar's measured width, and anything a review changed. Leave a line for Tim's checklist observations.
- [ ] Run the full suite and the Release build once.
- [ ] Commit: `docs: Phase 4c checklist, README and spec close-out`.

## Test totals

| After | Total |
|---|---|
| Baseline | 1193 tests in 126 suites |
| Task 1 | baseline plus `SelectionOutlineTests` (1 new suite) and the `EditorToolTests`, `KeyRoutingTests`, `AnnotationDocumentTests`, `HitTesterTests`, `CropGeometryTests`, `AnnotationClipTests`, `EditorWindowGeometryTests`, `EditorToolbarTests`, `EditorPaletteTests` and `AppSettingsTests` additions |
| Task 2 | Task 1 plus `SpotlightRenderingTests` and `SpotlightDisplayTests` (2 new suites) and the `HitTesterTests`, `CanvasToolTests`, `EditorModelTests`, `CanvasAccessibilityTests` and `EditorBackgroundExportTests` additions |
| Task 3 | Task 2 plus `CounterTests` (1 new suite) and the `CanvasToolTests`, `EditorModelTests`, `AnnotationClipTests` and `CanvasAccessibilityTests` additions; 130 suites |
| Task 4 | unchanged |
