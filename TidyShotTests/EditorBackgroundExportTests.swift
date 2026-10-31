import CoreGraphics
import Foundation
import Testing
@testable import TidyShot

/// The editor's Background tool (spec 2.11, Editor): the export composes the flattened (and
/// cropped) capture on the document's background, each toggle and style change is one undo step,
/// and a run of solid-colour changes is one.
struct EditorBackgroundExportTests {
    let red = RGBA(red: 1, green: 0, blue: 0)
    let green = RGBA(red: 0, green: 1, blue: 0)
    let blue = RGBA(red: 0, green: 0, blue: 1)

    /// A 16 x 16 capture at 2x whose pixel (x, y) is (x * 16, y * 16, 0), so a framed crop can be
    /// told apart from the rest. `clearCorner` makes the top-left 2 x 2 pixels transparent, as a
    /// window capture's rounded corner is.
    func makeModel(width: Int = 16, height: Int = 16, scale: CGFloat = 2, clearCorner: Bool = false) -> EditorModel {
        var bytes: [UInt8] = []
        for y in 0..<height {
            for x in 0..<width {
                bytes += clearCorner && x < 2 && y < 2 ? [0, 0, 0, 0] : [UInt8((x * 16) % 256), UInt8((y * 16) % 256), 0, 255]
            }
        }
        let image = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                            bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                            provider: CGDataProvider(data: Data(bytes) as CFData)!, decode: nil,
                            shouldInterpolate: false, intent: .defaultIntent)!
        return EditorModel(recordID: UUID(), image: ScaledImage(image: image, scale: scale),
                           renderer: FakeTileRenderer(), defaults: .standard)
    }

    func solid(_ color: RGBA, padding: Double = 4) -> BackgroundStyle {
        BackgroundStyle(fill: .solid(color), padding: padding, cornerRadius: 0, shadow: false)
    }

    /// The Background popover's change: the binding sets the draft, then `onCommit` commits it.
    func change(_ model: EditorModel, _ edit: (inout BackgroundStyle) -> Void) throws {
        var style = try #require(model.backgroundDraft ?? model.document.background)
        edit(&style)
        model.backgroundDraft = style
        model.commitBackgroundDraft()
    }

    @Test func solidBackgroundExportHasTheLayoutsSizeAndFill() async throws {
        let model = makeModel()
        let style = solid(red)
        model.setBackground(style)
        let export = try await model.renderExport()
        let layout = try #require(BackgroundLayout.make(contentSize: CGSize(width: 16, height: 16), style: style, scale: 2))
        #expect(CGSize(width: export.image.width, height: export.image.height) == layout.canvasSize)
        #expect(layout.canvasSize == CGSize(width: 32, height: 32))
        #expect(export.scale == 2)
        let bitmap = try EditorFlattenerTests.Bitmap(export.image)
        #expect(bitmap[0, 0] == [255, 0, 0, 255])
        #expect(bitmap[31, 31] == [255, 0, 0, 255])
        // The capture sits 8 px (4 pt at 2x) in.
        #expect(bitmap[8, 8] == [0, 0, 0, 255])
        #expect(bitmap[8 + 15, 8 + 15] == [240, 240, 0, 255])
    }

    @Test func backgroundFramesTheCrop() async throws {
        let model = makeModel()
        model.tool = .crop
        model.cropDraft = CGRect(x: 2, y: 3, width: 10, height: 8)
        model.applyCrop()
        model.setBackground(solid(blue))
        let export = try await model.renderExport()
        #expect(export.image.width == 10 + 16)
        #expect(export.image.height == 8 + 16)
        let bitmap = try EditorFlattenerTests.Bitmap(export.image)
        #expect(bitmap[7, 7] == [0, 0, 255, 255])
        // Canvas (8, 8) is crop (0, 0), which is capture (2, 3).
        #expect(bitmap[8, 8] == [32, 48, 0, 255])
        #expect(bitmap[8 + 9, 8 + 7] == [176, 160, 0, 255])
        #expect(bitmap[8 + 10, 8 + 8] == [0, 0, 255, 255])
    }

    /// The overlay belongs to the content and keeps its alpha (spec 2.12, Crop and Alpha): the
    /// fill shows undimmed through a transparent corner outside every spotlight, and in the padding,
    /// while the opaque capture outside the hole is dimmed.
    @Test func aTransparentCornerShowsTheUndimmedFill() async throws {
        let model = makeModel(clearCorner: true)
        model.commit(model.document.appending(.spotlight(SpotlightShape(id: UUID(), rect: CGRect(x: 8, y: 8, width: 4, height: 4),
                                                                        isEllipse: false))),
                     actionName: "Add Spotlight")
        model.setBackground(solid(red))
        let bitmap = try EditorFlattenerTests.Bitmap(try await model.renderExport().image)
        // The capture sits 8 px in: canvas (8, 8) and (9, 9) are its transparent corner.
        #expect(bitmap[8, 8] == [255, 0, 0, 255])
        #expect(bitmap[9, 9] == [255, 0, 0, 255])
        #expect(bitmap[0, 0] == [255, 0, 0, 255])
        // Capture (10, 10) is inside the hole; capture (15, 15), (240, 240, 0), is dimmed by half.
        #expect(bitmap[18, 18] == [160, 160, 0, 255])
        let dimmed = bitmap[23, 23]
        #expect((119...121).contains(Int(dimmed[0])) && (119...121).contains(Int(dimmed[1])), "\(dimmed)")
        #expect(dimmed[2] == 0 && dimmed[3] == 255)
    }

    @Test func noBackgroundExportsTheCaptureAsBefore() async throws {
        let model = makeModel()
        model.setBackground(solid(red))
        model.setBackground(nil)
        let export = try await model.renderExport()
        #expect(export.image.width == 16)
        #expect(export.image.height == 16)
    }

    /// A content over 16,384 px has no layout, so compose returns nil and the export fails.
    @Test func exportFailsWhenTheBackgroundCannotBeDrawn() async {
        let model = makeModel(width: BackgroundLayout.maximumContentSide + 1, height: 1, scale: 1)
        #expect(!model.backgroundFits(BackgroundStyle()))
        model.setBackground(BackgroundStyle())
        await #expect(throws: EditorExportFailure.background) { try await model.renderExport() }
        #expect(EditorExportFailure.background.message == "The background could not be drawn.")
    }

    @Test func toggleAndStyleChangeAreEachOneUndoStep() throws {
        let model = makeModel()
        let style = BackgroundStyle()
        model.setBackground(style)
        #expect(model.document.background == style)
        #expect(model.undoManager.undoActionName == EditorModel.ActionName.background)

        // A slider drag: live values go to the draft only, then one commit.
        model.backgroundDraft = BackgroundStyle(padding: 60)
        model.backgroundDraft = BackgroundStyle(padding: 80)
        #expect(model.document.background == style)
        #expect(model.shownBackground?.style.padding == 80)
        model.commitBackgroundDraft()
        #expect(model.backgroundDraft == nil)
        #expect(model.document.background?.padding == 80)

        try change(model) { $0.fill = .gradient(4) }
        try change(model) { $0.aspect = .square }

        model.undoManager.undo()
        #expect(model.document.background?.aspect == .auto)
        model.undoManager.undo()
        #expect(model.document.background?.fill == .gradient(0))
        model.undoManager.undo()
        #expect(model.document.background == style)
        model.undoManager.undo()
        #expect(model.document.background == nil)
        #expect(!model.undoManager.canUndo)
        model.undoManager.redo()
        #expect(model.document.background == style)
    }

    /// The colour panel commits on every change; a run of them with nothing else in between is one step.
    @Test func solidColourRunIsOneUndoStep() throws {
        let model = makeModel()
        model.setBackground(BackgroundStyle())
        try change(model) { $0.fill = .solid(red) }
        try change(model) { $0.fill = .solid(green) }
        try change(model) { $0.fill = .solid(blue) }
        #expect(model.document.background?.fill == .solid(blue))
        model.undoManager.undo()
        #expect(model.document.background?.fill == .gradient(0))

        // Another change ends the run.
        model.undoManager.redo()
        try change(model) { $0.padding = 10 }
        try change(model) { $0.fill = .solid(red) }
        try change(model) { $0.fill = .solid(green) }
        model.undoManager.undo()
        #expect(model.document.background == BackgroundStyle(fill: .solid(blue), padding: 10))
    }

    @Test func draftWithoutABackgroundCommitsNothing() {
        let model = makeModel()
        model.backgroundDraft = BackgroundStyle(padding: 10)
        model.commitBackgroundDraft()
        #expect(model.document.background == nil)
        #expect(model.backgroundDraft == nil)
        #expect(!model.undoManager.canUndo)
    }

    /// The canvas frames the applied crop, reaching past it by the padding, and shows nothing while
    /// the Crop tool is open.
    @Test func shownBackgroundFramesTheCropInImagePixels() throws {
        let model = makeModel()
        #expect(model.shownBackground == nil)
        model.setBackground(solid(red))
        let whole = try #require(model.shownBackground)
        #expect(whole.contentRect == CGRect(x: 0, y: 0, width: 16, height: 16))
        #expect(whole.canvasRect == CGRect(x: -8, y: -8, width: 32, height: 32))

        model.tool = .crop
        #expect(model.shownBackground == nil)
        model.cropDraft = CGRect(x: 2, y: 3, width: 10, height: 8)
        model.applyCrop()
        let cropped = try #require(model.shownBackground)
        #expect(cropped.contentRect == CGRect(x: 2, y: 3, width: 10, height: 8))
        #expect(cropped.canvasRect == CGRect(x: -6, y: -5, width: 26, height: 24))
        #expect(cropped.radius == 0)
    }

    /// The preview's fill is the canvas, at most 2,048 px on its long side.
    @Test func previewFillIsAtMost2048Pixels() throws {
        let small = makeModel()
        small.setBackground(solid(red))
        #expect(try #require(small.shownBackground).previewFillSize == CGSize(width: 32, height: 32))

        let large = makeModel(width: 4000, height: 1000, scale: 1)
        large.setBackground(BackgroundStyle(padding: 0, aspect: .square))
        let shown = try #require(large.shownBackground)
        #expect(shown.canvasRect.size == CGSize(width: 4000, height: 4000))
        #expect(shown.previewFillSize == CGSize(width: 2048, height: 2048))
    }

    /// The preview's layers follow the transform: the fill over the whole canvas, the mask and the
    /// shadow at the rounded content rect (the shadow 8 pt lower), and none of it without a background.
    @Test func baseImageViewPlacesTheBackgroundLayers() throws {
        let model = makeModel()
        model.setBackground(BackgroundStyle(fill: .solid(red), padding: 4, cornerRadius: 2, shadow: true))
        let shown = try #require(model.shownBackground)
        let view = BaseImageView(frame: CGRect(x: 0, y: 0, width: 400, height: 300))
        view.image = model.base
        let transform = CanvasTransform(zoom: 4, offset: CGPoint(x: 100, y: 50))
        view.transform = transform
        view.setBackground(shown, captureScale: 2)

        #expect(!view.backgroundLayer.isHidden)
        #expect(view.backgroundLayer.frame == transform.viewRect(shown.canvasRect))
        #expect(view.backgroundLayer.frame == CGRect(x: 68, y: 18, width: 128, height: 128))
        #expect(view.isContentMasked)
        #expect(view.roundedMask.frame == CGRect(x: 100, y: 50, width: 64, height: 64))
        #expect(view.roundedMask.cornerRadius == 16)  // 2 pt at 2x is 4 px, at zoom 4
        #expect(!view.shadowLayer.isHidden)
        #expect(view.shadowLayer.frame == CGRect(x: 100, y: 50 + 64, width: 64, height: 64))  // 8 pt at 2x and zoom 4
        #expect(view.shadowLayer.shadowRadius == 96)  // half the 24 pt blur, at 2x and zoom 4

        view.setBackground(nil, captureScale: 2)
        #expect(view.backgroundLayer.isHidden)
        #expect(view.shadowLayer.isHidden)
        #expect(!view.isContentMasked)
    }

    /// phase-7c :94, phase-7c :98, in part. A swatch, the Shadow toggle and an aspect change are one step each: the
    /// editor is dirty after each and clean after Save, and three undos take them back in reverse, one at a
    /// time. By hand: the window's edited mark.
    @Test func aSwatchTheShadowAndAnAspectAreThreeStepsThatDirtyTheEditor() throws {
        let model = makeModel()
        model.setBackground(solid(red))
        model.markSaved()
        let start = model.document.background

        try change(model) { $0.fill = .solid(blue) }
        #expect(model.hasUnsavedChanges)
        let swatched = model.document.background
        try change(model) { $0.shadow.toggle() }
        #expect(model.hasUnsavedChanges)
        let shadowed = model.document.background
        try change(model) { $0.aspect = .square }
        #expect(model.hasUnsavedChanges)
        model.markSaved()
        #expect(!model.hasUnsavedChanges)

        model.undoManager.undo()
        #expect(model.document.background == shadowed)
        #expect(model.hasUnsavedChanges)
        model.undoManager.undo()
        #expect(model.document.background == swatched)
        model.undoManager.undo()
        #expect(model.document.background == start)
    }

    /// phase-7c :143, phase-7c :165. For every aspect ratio the canvas the editor shows has the export's size, and
    /// with a crop the ratio is laid out from the crop's size.
    @Test func theShownCanvasHasTheExportsSizeForEveryAspect() async throws {
        for aspect in BackgroundAspect.allCases {
            let model = makeModel()
            var style = solid(red)
            style.aspect = aspect
            model.setBackground(style)
            let shown = try #require(model.shownBackground)
            let export = try await model.renderExport()
            #expect(shown.canvasRect.size == CGSize(width: export.image.width, height: export.image.height), "\(aspect)")
        }

        let model = makeModel()
        model.tool = .crop
        model.cropDraft = CGRect(x: 2, y: 3, width: 10, height: 8)
        model.applyCrop()
        var style = solid(red)
        style.aspect = .sixteenNine
        model.setBackground(style)
        let shown = try #require(model.shownBackground)
        let export = try await model.renderExport()
        let layout = try #require(BackgroundLayout.make(contentSize: CGSize(width: 10, height: 8), style: style, scale: 2))
        #expect(shown.contentRect == CGRect(x: 2, y: 3, width: 10, height: 8))
        #expect(shown.canvasRect.size == layout.canvasSize)
        #expect(CGSize(width: export.image.width, height: export.image.height) == layout.canvasSize)
    }

    /// phase-7c :147, phase-7c :150. A tall capture (14,000 px, as a scrolling capture of `tall.html`) takes a
    /// background and exports with the padding; an 18,000 px one does not until a crop brings the content
    /// under the limit. Undo after that takes the background step first (the line's first outcome), then the
    /// crop, and the bare capture still exports.
    @Test func aBackgroundFitsTallContentAndACropUnderTheLimit() async throws {
        let style = solid(red)
        let tall = makeModel(width: 10, height: 14_000, scale: 2)
        #expect(tall.backgroundFits(style))
        tall.setBackground(style)
        let tallExport = try await tall.renderExport()
        #expect(tallExport.image.width == 10 + 16)
        #expect(tallExport.image.height == 14_000 + 16)

        let taller = makeModel(width: 10, height: 18_000, scale: 2)
        #expect(!taller.backgroundFits(style))
        taller.tool = .crop
        taller.cropDraft = CGRect(x: 0, y: 0, width: 10, height: 10_000)
        taller.applyCrop()
        #expect(taller.backgroundFits(style))
        taller.setBackground(style)
        let croppedExport = try await taller.renderExport()
        #expect(croppedExport.image.height == 10_000 + 16)

        taller.undoManager.undo()
        #expect(taller.document.background == nil)
        #expect(taller.document.crop != nil)
        taller.undoManager.undo()
        #expect(taller.document.crop == nil)
        let bareExport = try await taller.renderExport()
        #expect(bareExport.image.height == 18_000)
    }

    /// phase-7c :158, phase-7c :164. With a background on, the Crop tool hides it (the handles work on the whole
    /// capture); Escape (`cancelCrop`) brings it back around the whole capture; an applied crop is framed; and
    /// undoing the crop frames the whole capture again, with the background still on.
    @Test func theCropToolHidesTheBackgroundAndCancelOrUndoReturnsItAroundTheWholeCapture() {
        let model = makeModel()
        model.setBackground(solid(red))
        let whole = CGRect(x: 0, y: 0, width: 16, height: 16)
        let crop = CGRect(x: 2, y: 2, width: 8, height: 8)

        model.tool = .crop
        #expect(model.shownBackground == nil)
        #expect(model.cropDraft == whole)
        model.cropDraft = crop
        model.cancelCrop()
        #expect(model.shownBackground?.contentRect == whole)

        model.tool = .crop
        model.cropDraft = crop
        model.applyCrop()
        #expect(model.shownBackground?.contentRect == crop)
        model.undoManager.undo()
        #expect(model.document.crop == nil)
        #expect(model.document.background != nil)
        #expect(model.shownBackground?.contentRect == whole)
    }
}
