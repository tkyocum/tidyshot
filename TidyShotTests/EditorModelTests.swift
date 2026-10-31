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
        let export = try await model.renderExport()
        #expect(export.scale == 2)
        #expect(export.image.width == 16)
        #expect(export.image.height == 16)
    }

    @Test func renderExportFailsWhenAnEffectTileIsMissing() async throws {
        let model = makeModel(renderer: NoTileRenderer())
        // An effect wholly outside the image covers nothing, so the export goes ahead.
        add(.blur(Region(id: UUID(), rect: CGRect(x: 40, y: 40, width: 8, height: 8)), radius: 16), to: model)
        _ = try await model.renderExport()
        // A redaction over the image without its tile would export the secret: no export.
        add(redaction(), to: model)
        await #expect(throws: EditorExportFailure.missingTile) { try await model.renderExport() }
    }

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
        let cropped = try await model.renderExport()
        #expect(cropped.image.width == 10)
        #expect(cropped.image.height == 8)
        #expect(cropped.scale == 2)

        model.undoManager.undo()
        #expect(model.document.crop == nil)
        #expect(model.document.annotations == [shape])
        let uncropped = try await model.renderExport()
        #expect(uncropped.image.width == 16)
        model.undoManager.redo()
        #expect(model.document.crop == crop)
        // Cropping again starts at the applied crop.
        model.tool = .crop
        #expect(model.cropDraft == crop)

        // Undo and redo while Crop is open move the draft too, so Return cannot re-apply the undone crop.
        model.undoManager.undo()
        #expect(model.document.crop == nil)
        #expect(model.cropDraft == CGRect(x: 0, y: 0, width: 16, height: 16))
        model.undoManager.redo()
        #expect(model.cropDraft == crop)
        model.undoManager.undo()
        model.applyCrop()
        #expect(model.document.crop == nil)
        #expect(model.undoManager.canRedo)
    }

    /// Undoing a step that leaves the crop alone must not throw away the draft being dragged.
    @Test func undoOfAnUnrelatedStepKeepsTheCropDraft() {
        let model = makeModel()
        let shape = add(box(), to: model)
        model.tool = .crop
        let draft = CGRect(x: 3, y: 3, width: 8, height: 8)
        model.cropDraft = draft
        model.undoManager.undo()
        #expect(model.document.annotation(id: shape.id) == nil)
        #expect(model.cropDraft == draft)
        model.undoManager.redo()
        #expect(model.document.annotation(id: shape.id) != nil)
        #expect(model.cropDraft == draft)
    }

    @Test func selectAllSkipsAnnotationsOutsideTheCrop() {
        let model = makeModel()
        let inside = add(box(x: 2), to: model)
        _ = add(box(x: 10), to: model)
        model.tool = .crop
        model.cropDraft = CGRect(x: 0, y: 0, width: 9, height: 16)
        model.applyCrop()
        #expect(model.document.crop == CGRect(x: 0, y: 0, width: 9, height: 16))
        model.selectAll()
        #expect(model.selection == inside.id)
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

    // MARK: Spotlight (spec 2.12)

    func spotlight(isEllipse: Bool = false) -> Annotation {
        .spotlight(SpotlightShape(id: UUID(), rect: CGRect(x: 2, y: 2, width: 8, height: 8), isEllipse: isEllipse))
    }

    func arrow() -> Annotation {
        .arrow(Segment(id: UUID(), from: CGPoint(x: 1, y: 1), to: CGPoint(x: 12, y: 12), color: red, lineWidth: 4))
    }

    /// ⌘A follows the hit order: the frontmost drawing, else effect, else spotlight.
    @Test func selectAllFallsBackToASpotlight() {
        let model = makeModel()
        let line = add(arrow(), to: model)
        add(spotlight(), to: model)
        model.selectAll()
        #expect(model.selection == line.id)

        let alone = makeModel()
        let hole = add(spotlight(), to: alone)
        alone.selectAll()
        #expect(alone.selection == hole.id)
    }

    @Test func aNewSpotlightTakesTheShapeDefault() throws {
        let model = makeModel()
        let from = CGPoint(x: 12, y: 10)
        let to = CGPoint(x: 2, y: 4)
        let rect = try #require(model.makeAnnotation(.spotlight, from: from, to: to)?.spotlightShape)
        #expect(rect.rect == CGRect(x: 2, y: 4, width: 10, height: 6))
        #expect(!rect.isEllipse)
        model.spotlightEllipse = true
        #expect(model.makeAnnotation(.spotlight, from: from, to: to)?.spotlightShape?.isEllipse == true)
        #expect(model.makeAnnotation(.spotlight, from: from, to: from) == nil)
    }

    /// Shape and Dim on a selected spotlight are each one named step that undo and redo restore.
    @Test func shapeAndDimOnASelectedSpotlightAreOneStepEach() throws {
        let model = makeModel()
        model.tool = .select
        let hole = add(spotlight(), to: model)
        let added = model.document
        model.selection = hole.id

        model.applySpotlightShape(isEllipse: true)
        #expect(model.document.annotation(id: hole.id) == hole.withSpotlightShape(isEllipse: true))
        #expect(model.spotlightEllipse)
        #expect(model.activeSpotlightEllipse)
        #expect(model.undoManager.undoActionName == EditorModel.ActionName.spotlightShape)
        #expect(EditorModel.ActionName.spotlightShape == "Spotlight Shape")
        let reshaped = model.document

        model.applySpotlightDim(0.7)
        #expect(model.document.effectiveSpotlightDim == 0.7)
        #expect(model.undoManager.undoActionName == EditorModel.ActionName.spotlightDim)
        #expect(EditorModel.ActionName.spotlightDim == "Spotlight Dim")
        let dimmed = model.document

        model.undoManager.undo()
        #expect(model.document == reshaped)
        model.undoManager.undo()
        #expect(model.document == added)
        // The selected spotlight's own shape shows again; the default stays as last picked.
        #expect(!model.activeSpotlightEllipse)
        #expect(model.spotlightEllipse)
        model.undoManager.redo()
        #expect(model.document == reshaped)
        model.undoManager.redo()
        #expect(model.document == dimmed)
        #expect(undoAll(model).count == 3)
    }

    /// A run of Dim clicks is one step, whatever the selection.
    @Test func aRunOfDimClicksIsOneStep() {
        let model = makeModel()
        model.tool = .spotlight
        add(spotlight(), to: model)
        let added = model.document
        model.selection = nil
        for dim in [0.3, 0.7, 0.3] {
            model.applySpotlightDim(dim)
        }
        #expect(model.document.effectiveSpotlightDim == 0.3)
        model.undoManager.undo()
        #expect(model.document == added)
        #expect(undoAll(model).count == 1)
    }

    /// With nothing selected, Shape sets only the default for the next spotlight.
    @Test func shapeWithNothingSelectedChangesOnlyTheDefault() {
        let model = makeModel()
        model.tool = .spotlight
        add(spotlight(), to: model)
        let added = model.document
        model.selection = nil
        model.applySpotlightShape(isEllipse: true)
        #expect(model.spotlightEllipse)
        #expect(model.activeSpotlightEllipse)
        #expect(model.document == added)
        #expect(undoAll(model).count == 1)
    }

    /// A dim nothing shows adds no step and no unsaved change, and neither does the dim in effect.
    @Test func dimWithoutASpotlightOrUnchangedAddsNoStep() {
        let model = makeModel()
        model.tool = .spotlight
        model.applySpotlightDim(0.7)
        #expect(model.document.spotlightDim == nil)
        #expect(!model.undoManager.canUndo)
        #expect(!model.hasUnsavedChanges)

        add(spotlight(), to: model)
        model.applySpotlightDim(0.5)
        #expect(model.document.spotlightDim == nil)
        #expect(model.undoManager.undoActionName == "Add")
        model.applySpotlightDim(0.3)
        model.applySpotlightDim(0.3)
        #expect(undoAll(model).count == 2)
    }

    /// Shape applies to the Spotlight tool or a selected spotlight; Dim needs a spotlight in the
    /// document as well.
    @Test func shapeAndDimEnableRules() {
        let model = makeModel()
        model.tool = .rectangle
        #expect(!model.spotlightShapeApplies)
        #expect(!model.spotlightDimApplies)
        model.tool = .spotlight
        #expect(model.spotlightShapeApplies)
        #expect(!model.spotlightDimApplies)

        let hole = add(spotlight(), to: model)
        #expect(model.spotlightDimApplies)
        model.tool = .select
        #expect(!model.spotlightShapeApplies)
        #expect(!model.spotlightDimApplies)
        model.selection = hole.id
        #expect(model.spotlightShapeApplies)
        #expect(model.spotlightDimApplies)

        // Another kind selected under Select: neither.
        let line = add(arrow(), to: model)
        model.selection = line.id
        #expect(!model.spotlightShapeApplies)
        #expect(!model.spotlightDimApplies)
    }

    /// The Colour item is off while a spotlight is selected, and for the Spotlight tool unless the
    /// selection has a colour; on otherwise, Crop included.
    @Test func colorAppliesRule() {
        let model = makeModel()
        #expect(model.colorApplies)
        model.tool = .spotlight
        #expect(!model.colorApplies)
        let hole = add(spotlight(), to: model)
        model.selection = hole.id
        #expect(!model.colorApplies)
        let line = add(arrow(), to: model)
        model.selection = line.id
        #expect(model.colorApplies)

        model.tool = .select
        model.selection = hole.id
        #expect(!model.colorApplies)
        model.selection = nil
        #expect(model.colorApplies)
        for tool in [EditorTool.rectangle, .redact, .highlighter, .crop] {
            model.tool = tool
            #expect(model.colorApplies, "\(tool)")
        }
    }

    /// A spotlight has no colour, so selecting one leaves the swatch on the default.
    @Test func aSelectedSpotlightLeavesTheActiveColour() {
        let model = makeModel()
        model.tool = .select
        let hole = add(spotlight(), to: model)
        let before = model.activeColor
        model.selection = hole.id
        #expect(model.activeColor == before)
        #expect(model.activeColor == model.strokeColor)
    }

    // MARK: Counter (spec 2.12)

    func counter(number: Int = 1, at center: CGPoint = CGPoint(x: 50, y: 50), diameter: CGFloat = 64) -> Annotation {
        .counter(CounterMark(id: UUID(), center: center, number: number, diameter: diameter, color: red))
    }

    /// A new counter is `counterDiameterPoints × scale` across, in `strokeColor`, centred on the
    /// press and numbered next; it is clamped inside the applied crop.
    @Test func aNewCounterTakesTheSizeAndColourDefaults() throws {
        let model = makeModel(side: 200)
        let press = CGPoint(x: 100, y: 80)
        let first = try #require(model.makeAnnotation(.counter, from: press, to: CGPoint(x: 150, y: 150))?.counterMark)
        #expect(first.diameter == EditorPalette.defaultCounterDiameterPoints * 2)
        #expect(first.diameter == 64)
        #expect(first.color == model.strokeColor)
        #expect(first.center == press)
        #expect(first.number == 1)

        add(.counter(first), to: model)
        model.counterDiameterPoints = 44
        model.strokeColor = blue
        let second = try #require(model.makeAnnotation(.counter, from: press, to: press)?.counterMark)
        #expect(second.diameter == 88)
        #expect(second.color == blue)
        #expect(second.number == 2)

        // Within the crop: the whole circle inside it.
        model.commit(model.document.withCrop(CGRect(x: 60, y: 40, width: 100, height: 100)), actionName: "Crop")
        let clamped = try #require(model.makeAnnotation(.counter, from: CGPoint(x: 62, y: 139), to: press)?.counterMark)
        #expect(clamped.center == CGPoint(x: 104, y: 96))
    }

    /// Size on a selected counter is one `Counter Size` step that keeps its centre, a run of picks
    /// is one step, and undo and redo restore it. It also sets the default.
    @Test func sizeOnASelectedCounterIsOneStepAboutItsCentre() throws {
        let model = makeModel(side: 200)
        model.tool = .select
        let mark = add(counter(at: CGPoint(x: 70, y: 60), diameter: 64), to: model)
        let added = model.document
        model.selection = mark.id
        #expect(model.activeCounterDiameterPoints == 32)

        model.applyCounterSize(points: 24)
        model.applyCounterSize(points: 44)
        #expect(model.document.annotation(id: mark.id) == mark.withCounterDiameter(88))
        #expect(model.document.annotation(id: mark.id)?.counterMark?.center == CGPoint(x: 70, y: 60))
        #expect(model.counterDiameterPoints == 44)
        #expect(model.activeCounterDiameterPoints == 44)
        #expect(model.undoManager.undoActionName == EditorModel.ActionName.counterSize)
        #expect(EditorModel.ActionName.counterSize == "Counter Size")
        let resized = model.document

        model.undoManager.undo()
        #expect(model.document == added)
        // The selected counter's own size shows again; the default stays as last picked.
        #expect(model.activeCounterDiameterPoints == 32)
        #expect(model.counterDiameterPoints == 44)
        model.undoManager.redo()
        #expect(model.document == resized)
        #expect(undoAll(model).count == 2)
    }

    /// With nothing selected, Size sets only the default for the next counter.
    @Test func sizeWithNothingSelectedChangesOnlyTheDefault() {
        let model = makeModel(side: 200)
        model.tool = .counter
        add(counter(), to: model)
        let added = model.document
        model.selection = nil
        model.applyCounterSize(points: 24)
        #expect(model.counterDiameterPoints == 24)
        #expect(model.activeCounterDiameterPoints == 24)
        #expect(model.document == added)
        #expect(undoAll(model).count == 1)
    }

    /// Size applies while Counter is the tool or a counter is selected.
    @Test func sizeEnableRule() {
        let model = makeModel(side: 200)
        model.tool = .rectangle
        #expect(!model.counterSizeApplies)
        model.tool = .counter
        #expect(model.counterSizeApplies)
        let mark = add(counter(), to: model)
        model.tool = .select
        #expect(!model.counterSizeApplies)
        model.selection = mark.id
        #expect(model.counterSizeApplies)
        let line = add(arrow(), to: model)
        model.selection = line.id
        #expect(!model.counterSizeApplies)
        model.tool = .counter
        #expect(model.counterSizeApplies)
    }

    /// A counter has a colour: selected, the swatch shows it and a pick recolours it as `Color`. phase-4c :151:
    /// a counter placed afterwards takes the applied colour.
    @Test func aSelectedCounterShowsAndTakesTheColour() throws {
        let model = makeModel(side: 200)
        model.tool = .select
        let mark = add(counter(), to: model)
        model.selection = mark.id
        #expect(model.activeColor == red)
        #expect(model.colorApplies)
        model.applyColor(blue)
        #expect(model.document.annotation(id: mark.id) == mark.withColor(blue))
        #expect(model.activeColor == blue)
        #expect(model.undoManager.undoActionName == EditorModel.ActionName.color)
        model.undoManager.undo()
        #expect(model.document.annotation(id: mark.id) == mark)
        #expect(model.activeColor == red)
        // phase-4c :151: the stroke colour followed the swatch, so a counter placed afterwards takes it.
        let placed = try #require(model.makeAnnotation(.counter, from: CGPoint(x: 120, y: 120), to: CGPoint(x: 120, y: 120)))
        #expect(placed.counterMark?.color == blue)
    }

    // MARK: Checklist cases (CT-1)

    nonisolated enum Shape: CaseIterable, Sendable {
        case rectangle
        case ellipse
        case line
    }

    nonisolated enum Duplicated: CaseIterable, Sendable {
        case ellipse, line, pencil, highlighter, text, arrow, blur, redact
    }

    /// phase-4a :60. The options slider's block size changes a selected mosaic, live, as one step: a burst of
    /// changes undoes at once (`Block Size`).
    @Test func blockSizeAppliesToTheSelectedPixelateInOneStep() throws {
        let model = makeModel(side: 256)
        model.tool = .select
        let rect = CGRect(x: 4, y: 4, width: 200, height: 200)
        let region = add(.pixelate(Region(id: UUID(), rect: rect),
                                   block: RedactionDefaults.block(points: 10, scale: 2, region: rect)), to: model)
        model.selection = region.id

        model.applyEffectParameter(.block, points: 20)
        model.applyEffectParameter(.block, points: 24)

        guard case .pixelate(_, let block)? = model.document.annotation(id: region.id) else {
            Issue.record("the selection is not a mosaic")
            return
        }
        #expect(block == RedactionDefaults.block(points: 24, scale: 2, region: rect))
        #expect(model.blockPoints == 24)
        #expect(model.undoManager.undoActionName == EditorModel.ActionName.block)
        model.undoManager.undo()
        #expect(model.document.annotation(id: region.id) == region)
    }

    /// phase-4a :62, phase-4b :37. Keys 1 to 6 (`applyLineWidth`) set the width on a selected rectangle, ellipse or
    /// line and on its tool; a swatch recolours the selection, and the tool's colour follows.
    @Test(arguments: Shape.allCases)
    func widthAndColourApplyToTheSelectedShapeAndItsTool(kind: Shape) {
        let model = makeModel(side: 64)
        model.tool = .select
        let shape: Annotation = switch kind {
        case .rectangle:
            .rectangle(ShapeBox(id: UUID(), rect: CGRect(x: 4, y: 4, width: 20, height: 10), color: red, lineWidth: 8))
        case .ellipse:
            .ellipse(ShapeBox(id: UUID(), rect: CGRect(x: 4, y: 4, width: 20, height: 10), color: red, lineWidth: 8))
        case .line:
            .line(Segment(id: UUID(), from: CGPoint(x: 4, y: 4), to: CGPoint(x: 30, y: 20), color: red, lineWidth: 8))
        }
        add(shape, to: model)
        model.selection = shape.id

        model.applyLineWidth(points: 12)
        #expect(model.document.annotation(id: shape.id) == shape.withLineWidth(12 * model.scale))
        #expect(model.lineWidthPoints == 12)
        #expect(model.undoManager.undoActionName == EditorModel.ActionName.lineWidth)

        model.applyColor(blue)
        #expect(model.document.annotation(id: shape.id) == shape.withLineWidth(12 * model.scale).withColor(blue))
        #expect(model.strokeColor == blue)
        #expect(model.undoManager.undoActionName == EditorModel.ActionName.color)
    }

    /// phase-4b :55. The colour button recolours a selected text and the tool's colour, and the text being typed,
    /// so a text placed afterwards takes that colour.
    @Test func colourAppliesToTheSelectedTextAndTheTextBeingTyped() {
        let model = makeModel(side: 64)
        model.tool = .select
        let text = add(.text(TextBox(id: UUID(), string: "Hi", origin: CGPoint(x: 4, y: 4), fontSize: 24, color: red)),
                       to: model)
        model.selection = text.id

        model.applyColor(blue)
        #expect(model.document.annotation(id: text.id) == text.withColor(blue))
        #expect(model.strokeColor == blue)

        model.tool = .text
        model.beginTextEditing(at: CGPoint(x: 30, y: 30), existing: nil)
        #expect(model.textEditing?.box.color == blue)
        model.applyColor(black)
        #expect(model.textEditing?.box.color == black)
        #expect(model.strokeColor == black)
    }

    /// phase-4b :84 (the all-outside case). With a crop applied and every annotation wholly outside it, ⌘A selects
    /// nothing.
    @Test func selectAllWithEveryAnnotationOutsideTheCropSelectsNothing() {
        let model = makeModel(side: 64)
        add(box(x: 40), to: model)
        add(blurRegion(radius: 4), to: model)
        model.tool = .crop
        model.cropDraft = CGRect(x: 20, y: 20, width: 10, height: 10)
        model.applyCrop()
        #expect(model.document.crop == CGRect(x: 20, y: 20, width: 10, height: 10))

        model.selectAll()

        #expect(model.selection == nil)
    }

    /// phase-4b :88. ⌘D copies every kind: the copy is the same annotation `duplicateOffset` away with its own id,
    /// selected, in one step `Duplicate <title>`; a redaction's copy is a redaction.
    @Test(arguments: Duplicated.allCases)
    func duplicateCopiesEveryKindOffsetAndNamed(kind: Duplicated) throws {
        let model = makeModel(side: 64)
        model.tool = .select
        let points = [CGPoint(x: 4, y: 4), CGPoint(x: 10, y: 8), CGPoint(x: 16, y: 6)]
        let original: Annotation = switch kind {
        case .ellipse:
            .ellipse(ShapeBox(id: UUID(), rect: CGRect(x: 4, y: 4, width: 12, height: 8), color: red, lineWidth: 4))
        case .line: .line(Segment(id: UUID(), from: CGPoint(x: 4, y: 4), to: CGPoint(x: 20, y: 12), color: red, lineWidth: 4))
        case .pencil: .pencil(Stroke(id: UUID(), points: points, color: red, lineWidth: 4))
        case .highlighter: .highlighter(Stroke(id: UUID(), points: points, color: red, lineWidth: 12))
        case .text: .text(TextBox(id: UUID(), string: "Hi", origin: CGPoint(x: 4, y: 4), fontSize: 24, color: red))
        case .arrow: arrow()
        case .blur: blurRegion(radius: 4)
        case .redact: redaction()
        }
        add(original, to: model)
        model.selection = original.id

        model.duplicateSelection()

        #expect(model.document.annotations.count == 2)
        let copy = try #require(model.document.annotations.last)
        #expect(copy.id != original.id)
        #expect(copy == original.moved(by: model.duplicateOffset).withID(copy.id))
        #expect(model.selection == copy.id)
        #expect(model.undoManager.undoActionName == "Duplicate \(original.title)")
    }

    /// phase-4b :118. One of each tool (Redact, Pixelate, Blur, Rectangle, Arrow, Ellipse, Line, Pencil, Highlighter,
    /// Text), made by the real tools over the model, then a crop: undo takes the crop as its own step, then the
    /// ten annotations newest first; redo brings them back in order, then the crop.
    @Test func oneOfEachToolUndoesNewestFirstAndRedoesInOrder() {
        let model = makeModel(side: 400)
        for (index, tool) in [EditorTool.redact, .pixelate, .blur, .rectangle, .arrow, .ellipse, .line].enumerated() {
            let y = CGFloat(10 + index * 40)
            let drag = makeTool(for: tool)
            drag.mouseDown(ToolInput(point: CGPoint(x: 10, y: y)), on: model)
            drag.mouseDragged(ToolInput(point: CGPoint(x: 60, y: y + 30)), on: model)
            drag.mouseUp(ToolInput(point: CGPoint(x: 60, y: y + 30)), on: model)
        }
        for (index, tool) in [EditorTool.pencil, .highlighter].enumerated() {
            let y = CGFloat(300 + index * 40)
            let stroke = makeTool(for: tool)
            stroke.mouseDown(ToolInput(point: CGPoint(x: 10, y: y)), on: model)
            for x in stride(from: 20, through: 80, by: 10) {
                stroke.mouseDragged(ToolInput(point: CGPoint(x: CGFloat(x), y: y + 5)), on: model)
            }
            stroke.mouseUp(ToolInput(point: CGPoint(x: 80, y: y + 5)), on: model)
        }
        model.beginTextEditing(at: CGPoint(x: 200, y: 200), existing: nil)
        model.updateEditingText("Ten")
        model.commitTextEditing()
        let all = model.document.annotations
        #expect(all.count == 10)
        model.tool = .crop
        model.cropDraft = CGRect(x: 0, y: 0, width: 300, height: 300)
        model.applyCrop()
        let cropped = model.document

        model.undoManager.undo()
        #expect(model.document.crop == nil)
        #expect(model.document.annotations == all)
        for count in stride(from: 9, through: 0, by: -1) {
            model.undoManager.undo()
            #expect(model.document.annotations == Array(all.prefix(count)))
        }
        #expect(!model.undoManager.canUndo)
        for count in 1...10 {
            model.undoManager.redo()
            #expect(model.document.annotations == Array(all.prefix(count)))
        }
        model.undoManager.redo()
        #expect(model.document == cropped)
    }

    /// phase-4c :140. With a spotlight or a counter selected, `Line width` changes only the default: the selected
    /// one is unchanged, no undo step is added and nothing is unsaved.
    @Test func lineWidthWithASpotlightOrCounterSelectedChangesOnlyTheDefault() {
        let model = makeModel(side: 200)
        model.tool = .select
        let hole = add(spotlight(), to: model)
        let mark = add(counter(), to: model)
        model.markSaved()
        let document = model.document
        let lastStep = model.undoManager.undoActionName

        for (selected, points) in [(hole.id, CGFloat(8)), (mark.id, CGFloat(12))] {
            model.selection = selected
            model.applyLineWidth(points: points)
            #expect(model.lineWidthPoints == points)
            #expect(model.document == document)
            #expect(model.undoManager.undoActionName == lastStep)
            #expect(!model.hasUnsavedChanges)
        }
    }

    /// phase-4c :163, phase-4c :167. Every spotlight edit is one named step: `Add Spotlight`, `Move Spotlight`,
    /// `Resize Spotlight`, `Duplicate Spotlight` (⌘D and an ⌥-drag) and `Paste Spotlight`, the second paste one
    /// cascade step further; undo and redo restore each document, and the unsaved state follows.
    @Test func everySpotlightEditIsOneNamedUndoStep() throws {
        let model = makeModel(side: 400)
        model.tool = .select
        var documents = [model.document]
        var names: [String] = []
        func step() {
            documents.append(model.document)
            names.append(model.undoManager.undoActionName)
        }

        let draw = makeTool(for: .spotlight)
        draw.mouseDown(ToolInput(point: CGPoint(x: 40, y: 40)), on: model)
        draw.mouseDragged(ToolInput(point: CGPoint(x: 140, y: 100)), on: model)
        draw.mouseUp(ToolInput(point: CGPoint(x: 140, y: 100)), on: model)
        step()
        let hole = try #require(model.document.spotlights.first)
        model.selection = hole.id

        let select = makeTool(for: .select)
        select.mouseDown(ToolInput(point: CGPoint(x: 90, y: 70)), on: model)
        select.mouseDragged(ToolInput(point: CGPoint(x: 110, y: 80)), on: model)
        select.mouseUp(ToolInput(point: CGPoint(x: 110, y: 80)), on: model)
        step()
        let moved = try #require(model.document.annotation(id: hole.id)?.spotlightShape?.rect)
        select.mouseDown(ToolInput(point: CGPoint(x: moved.maxX, y: moved.maxY)), on: model)
        select.mouseDragged(ToolInput(point: CGPoint(x: moved.maxX + 30, y: moved.maxY + 20)), on: model)
        select.mouseUp(ToolInput(point: CGPoint(x: moved.maxX + 30, y: moved.maxY + 20)), on: model)
        step()
        model.duplicateSelection()
        step()
        let resized = try #require(model.document.annotation(id: hole.id)?.spotlightShape?.rect)
        let centre = CGPoint(x: resized.midX, y: resized.midY)
        select.mouseDown(ToolInput(point: centre, option: true), on: model)
        select.mouseDragged(ToolInput(point: CGPoint(x: centre.x, y: centre.y + 150), option: true), on: model)
        select.mouseUp(ToolInput(point: CGPoint(x: centre.x, y: centre.y + 150), option: true), on: model)
        step()
        model.selection = hole.id
        let clip = try #require(model.objectClip())
        model.paste(clip)
        step()
        let firstPaste = try #require(model.document.annotations.last?.spotlightShape?.rect)
        model.paste(clip)
        step()
        let secondPaste = try #require(model.document.annotations.last?.spotlightShape?.rect)

        #expect(names == ["Add Spotlight", "Move Spotlight", "Resize Spotlight", "Duplicate Spotlight",
                          "Duplicate Spotlight", "Paste Spotlight", "Paste Spotlight"])
        #expect(secondPaste.origin == CGPoint(x: firstPaste.minX + model.duplicateOffset.dx,
                                              y: firstPaste.minY + model.duplicateOffset.dy))
        for document in documents.reversed().dropFirst() {
            model.undoManager.undo()
            #expect(model.document == document)
        }
        #expect(!model.hasUnsavedChanges)
        for document in documents.dropFirst() {
            model.undoManager.redo()
            #expect(model.document == document)
            #expect(model.hasUnsavedChanges)
        }
    }

    /// phase-4c :203. The spotlight Dim belongs to its document: 70 % in one editor leaves another at 50 %, and a
    /// new editor starts at 50 %.
    @Test func spotlightDimStaysWithItsModel() {
        let first = makeModel()
        let second = makeModel()
        add(spotlight(), to: first)
        add(spotlight(), to: second)

        first.applySpotlightDim(0.7)

        #expect(first.document.effectiveSpotlightDim == 0.7)
        #expect(second.document.effectiveSpotlightDim == 0.5)
        #expect(makeModel().document.effectiveSpotlightDim == 0.5)
    }
}
