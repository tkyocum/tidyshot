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
    /// The Highlighter's own colour and width (the Pencil uses `strokeColor` and `lineWidthPoints`).
    /// Not persisted: every editor starts from yellow at alpha 0.45 and 12 pt.
    var highlightColor = EditorPalette.defaultHighlight
    var highlightWidthPoints = EditorPalette.highlighterWidthPoints
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
        case .ellipse:
            guard !rect.isEmpty else { return nil }
            return .ellipse(ShapeBox(id: id, rect: rect, color: strokeColor, lineWidth: lineWidthPoints * scale))
        case .line:
            guard start != end else { return nil }
            return .line(Segment(id: id, from: start, to: end, color: strokeColor, lineWidth: lineWidthPoints * scale))
        case .pencil, .highlighter:
            return nil  // Strokes come from `makeStroke`.
        }
    }

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
        Self.color(of: selectedAnnotation) ?? (editsRedactColor ? redactColor : editsHighlighter ? highlightColor : strokeColor)
    }

    /// Redact, or Select with a redaction selected, edits the fill; everything else the stroke.
    private var editsRedactColor: Bool {
        if tool == .redact { return true }
        guard tool == .select, case .redact? = selectedAnnotation else { return false }
        return true
    }

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

    func applyColor(_ color: RGBA) {
        if editsRedactColor {
            redactColor = color
        } else if editsHighlighter {
            highlightColor = EditorPalette.highlighterColor(from: color)
        } else {
            strokeColor = color
        }
        guard let selected = selectedAnnotation else { return }
        commit(document.replacing(selected.withColor(color)), actionName: ActionName.color,
               coalescingKey: "\(ActionName.color)-\(selected.id.uuidString)")
    }

    func applyLineWidth(points: CGFloat) {
        if editsHighlighter { highlightWidthPoints = points } else { lineWidthPoints = points }
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
        case .rectangle(let box)?, .ellipse(let box)?: return box.color
        case .arrow(let segment)?, .line(let segment)?: return segment.color
        case .pencil(let stroke)?, .highlighter(let stroke)?: return stroke.color
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
