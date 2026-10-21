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
        #expect(model.makeAnnotation(.ellipse, from: from, to: CGPoint(x: 12, y: 20)) == nil)
        #expect(model.makeAnnotation(.line, from: from, to: from) == nil)

        // One drag keeps one id, so the transient's tile carries over on commit.
        model.transient = model.makeAnnotation(.redact, from: from, to: to)
        let id = model.transient?.id
        #expect(id != nil)
        #expect(model.makeAnnotation(.redact, from: from, to: .zero)?.id == id)
        model.transient = nil
        #expect(model.makeAnnotation(.redact, from: from, to: to)?.id != id)
    }

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
            #expect(stroke.lineWidth == CGFloat(12) * 2)
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
