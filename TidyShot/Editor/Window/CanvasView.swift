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
        /// The text being typed. A change repaints the whole view, which hides or shows the
        /// committed copy of a re-edited text.
        var editingID: UUID?
        /// The Crop tool's rect. A change repaints the whole view, since the readout sits outside it.
        var cropDraft: CGRect?
    }

    /// True while a text annotation is being typed. EditorWindow reads it to let the clipboard and
    /// undo chords through to the text view; KeyRouting reads it to leave every key to it.
    var isEditingText: Bool { model.isEditingText }

    private let model: EditorModel
    private let baseView: BaseImageView
    private var activeTool: any CanvasTool
    private var activeToolKind: EditorTool
    private var shown: Shown
    /// Effects drawn as placeholders because they have no tile to show yet (see `shownTile(for:)`).
    private var pendingIDs: Set<UUID> = []
    /// The tile each effect showed at the last `syncTiles`, as `BaseImageView` keeps its own. The
    /// highlighter backdrop copies these, so a replaced or moved tile repaints the area it covered.
    private var shownTiles: [UUID: TileRepaint.Shown] = [:]
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
                      transform: model.transform, editingID: model.textEditing?.box.id, cropDraft: model.cropDraft)
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

    /// A zero magnification (a pinch's begin and end events) moves nothing, so it leaves the fit
    /// following window resizes. The same holds for zero-delta scroll events below.
    override func magnify(with event: NSEvent) {
        guard event.magnification != 0 else { return }
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
            guard event.scrollingDeltaX != 0 || event.scrollingDeltaY != 0 else { return }
            let line: CGFloat = precise ? 1 : 10
            apply(model.transform.panned(by: CGPoint(x: event.scrollingDeltaX * line, y: event.scrollingDeltaY * line)),
                  fits: false)
        }
    }

    // MARK: Pointer

    override func mouseDown(with event: NSEvent) {
        // A click outside the text view while typing commits the text and does nothing else.
        if model.isEditingText {
            endTextEditing(commit: true)
            return
        }
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
                                 isEditingText: isEditingText, tool: model.tool) {
        case .selectTool(let tool):
            guard !isTrackingMouse else { return }
            model.tool = tool
            refresh()
        case .lineWidth(let index):
            let widths = EditorPalette.lineWidthsPoints
            guard widths.indices.contains(index) else { return }
            model.applyLineWidth(points: widths[index])
            refresh()
        case .textSize(let index):
            let sizes = EditorPalette.textSizesPoints
            guard sizes.indices.contains(index) else { return }
            model.applyTextSize(points: sizes[index])
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
            _ = model.textEditing
            _ = model.cropDraft
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
        syncTextView()
        let now = Shown(document: model.document, transient: model.transient, selection: model.selection,
                        transform: model.transform, editingID: model.textEditing?.box.id, cropDraft: model.cropDraft)
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
        if now.document == previous.document, now.selection == previous.selection, now.transform == previous.transform,
           now.cropDraft == previous.cropDraft {
            setNeedsDisplay(repaintRect(for: previous.transient, in: previous.document)
                .union(repaintRect(for: now.transient, in: now.document)))
        } else {
            needsDisplay = true
        }
        // Starting or ending cropping, and undo or redo of a crop, change what Fit shows.
        if fitsOnResize, fitRect(document: now.document, cropDraft: now.cropDraft)
            != fitRect(document: previous.document, cropDraft: previous.cropDraft) {
            fitToView()
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
        var current: [UUID: TileRepaint.Shown] = [:]
        for (id, tile) in tiles {
            current[id] = TileRepaint.Shown(image: tile.image, rect: tile.rect)
        }
        for id in Set(shownTiles.keys).union(current.keys) {
            if let dirty = TileRepaint.dirtyRect(old: shownTiles[id], new: current[id]) {
                setNeedsDisplay(model.transform.viewRect(dirty).insetBy(dx: -8, dy: -8))
            }
        }
        shownTiles = current
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
    /// effects, so their order cannot expose a redaction. A text being re-edited is left out: the
    /// text view shows it instead.
    private var displayedDrawings: [Annotation] {
        let transient = model.transient
        let editingID = model.textEditing?.box.id
        var drawings = model.document.drawings.filter { $0.id != transient?.id && $0.id != editingID }
        if let transient, !transient.isEffect { drawings.append(transient) }
        return drawings
    }

    private var selectedAnnotation: Annotation? {
        guard let id = model.selection else { return nil }
        if let transient = model.transient, transient.id == id { return transient }
        return model.document.annotation(id: id)
    }

    // MARK: Text editing

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

    // MARK: Drawing

    /// For each highlighter meeting `visible` (including the one in progress): clip to its stroked
    /// outline, then draw the capture and the shown effect tiles into that clip. The copy equals
    /// what `baseView` shows there, so the picture does not change, and the multiply that follows
    /// in `AnnotationDrawing.draw` has real pixels to multiply. Runs before every other drawing, so
    /// shapes made before the highlighter lie under it and shapes made after lie over it, as in the
    /// export. The CTM is image pixels, top-left origin. The clip is stroked 1 view point wider on
    /// each side so anti-aliased edge pixels get a whole backdrop, as in the export. Interpolation
    /// follows `BaseImageView`: nearest from 2 device pixels per image pixel up, bilinear from 1,
    /// and the highest quality below.
    private func drawHighlighterBackdrops(in context: CGContext, visible: CGRect) {
        var strokes: [Stroke] = []
        for drawing in displayedDrawings {
            if case .highlighter(let stroke) = drawing, AnnotationGeometry.strokeBounds(of: stroke).intersects(visible) {
                strokes.append(stroke)
            }
        }
        guard !strokes.isEmpty else { return }
        let devicePixelsPerImagePixel = model.transform.zoom * backingScale
        let quality: CGInterpolationQuality = devicePixelsPerImagePixel >= 2 ? .none
            : devicePixelsPerImagePixel >= 1 ? .low : .high
        for stroke in strokes {
            context.saveGState()
            context.addPath(StrokeSmoothing.path(for: stroke.points))
            context.setLineWidth(stroke.lineWidth + 2 / model.transform.zoom)
            context.setLineCap(.round)
            context.setLineJoin(.round)
            context.replacePathWithStrokedPath()
            context.clip()
            context.interpolationQuality = quality
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

    /// Spec 2.6 Rendering: (1) image-pixel CTM; (2) placeholders for effects with no tile yet;
    /// (3) drawings meeting the dirty rect, then the transient shape; (4) back in view space, the
    /// crop chrome and readout while cropping, else the cover outside an applied crop and the
    /// selection handles or dashed outline. No Core Image or GPU work happens here.
    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        let transform = model.transform
        let visible = transform.imageRect(dirtyRect)
        context.saveGState()
        context.concatenate(transform.affine)
        drawHighlighterBackdrops(in: context, visible: visible)
        for effect in displayedEffects where pendingIDs.contains(effect.id) {
            guard let rect = effect.effectRect, rect.intersects(visible) else { continue }
            AnnotationDrawing.drawPlaceholder(for: effect, in: context)
        }
        for drawing in displayedDrawings where imageBounds(of: drawing).intersects(visible) {
            AnnotationDrawing.draw(drawing, in: context, scale: model.scale)
        }
        context.restoreGState()
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
            // The view's backing scale snaps the outline and handles to device pixels; the drawings
            // above take the capture scale (`model.scale`).
            AnnotationDrawing.drawSelection(for: selected, transform: transform, scale: backingScale, in: context)
        }
    }

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
}

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
