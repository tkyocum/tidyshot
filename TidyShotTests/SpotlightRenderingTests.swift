import CoreGraphics
import Foundation
import Testing
@testable import TidyShot

/// The spotlight overlay (spec 2.12, Rendering), through `EditorFlattener` on the flattener tests'
/// images unless stated: black at the document's dim over the whole capture with each spotlight's
/// shape cleared from it, after the effects and before the drawings. It darkens the picture, never
/// its transparency.
struct SpotlightRenderingTests {
    typealias Bitmap = EditorFlattenerTests.Bitmap

    let images = EditorFlattenerTests()
    let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!

    func spotlight(_ rect: CGRect, ellipse: Bool = false) -> Annotation {
        .spotlight(SpotlightShape(id: UUID(), rect: rect, isEllipse: ellipse))
    }

    func highlighter(_ points: [CGPoint], width: CGFloat = 12) -> Annotation {
        .highlighter(Stroke(id: UUID(), points: points, color: EditorPalette.defaultHighlight, lineWidth: width))
    }

    func flatten(_ base: CGImage, _ annotations: [Annotation], dim: Double? = nil, crop: CGRect? = nil,
                 tiles: [EffectTile] = []) throws -> Bitmap {
        var document = AnnotationDocument(annotations: annotations).withCrop(crop)
        if let dim { document = document.withSpotlightDim(dim) }
        return try Bitmap(try #require(EditorFlattener.flatten(base: base, tiles: tiles, document: document, scale: 1)))
    }

    /// One opaque colour everywhere.
    func uniform(_ pixel: [UInt8], width: Int = EditorFlattenerTests.width,
                 height: Int = EditorFlattenerTests.height) -> CGImage {
        images.makeImage(width: width, height: height) { _, _ in pixel }
    }

    /// `pixel` with black at `dim` over it, per channel and unrounded: what the overlay should give.
    func dimmed(_ pixel: [UInt8], by dim: Double) -> [Double] {
        pixel.prefix(3).map { Double($0) * (1 - dim) } + [Double(pixel[3])]
    }

    /// Every channel within one level of `expected`.
    func isClose(_ pixel: [UInt8], to expected: [Double]) -> Bool {
        zip(pixel, expected).allSatisfy { abs(Double($0) - $1) <= 1 }
    }

    func isClose(_ pixel: [UInt8], to expected: [UInt8]) -> Bool {
        isClose(pixel, to: expected.map(Double.init))
    }

    /// A transparent premultiplied RGBA bitmap flipped to y-down, as the canvas draws in image
    /// pixels (`HighlighterBackdropTests` sets up the same).
    func canvasContext(width: Int = EditorFlattenerTests.width, height: Int = EditorFlattenerTests.height) throws -> CGContext {
        let context = try #require(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                             space: sRGB, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)
        return context
    }

    func bitmap(of context: CGContext) throws -> Bitmap {
        try Bitmap(try #require(context.makeImage()))
    }

    /// The whole capture as one coverage layer, as `BaseImageView.baseTiles` lists a small one.
    func coverage(_ base: CGImage) -> [(rect: CGRect, image: CGImage)] {
        [(rect: CGRect(x: 0, y: 0, width: base.width, height: base.height), image: base)]
    }

    // MARK: Holes and dimming

    /// Outside every spotlight each channel is darkened by the dim and alpha is kept. Inside a
    /// rectangle and inside an ellipse the base is untouched, but the ellipse's bounding-box corner
    /// is dimmed.
    @Test func outsideIsDimmedAndInsideIsNot() throws {
        let base = images.makeImage()
        let original = try Bitmap(base)
        let rect = CGRect(x: 8, y: 8, width: 16, height: 12)
        // Centre (46, 23), radii 10 and 15.
        let oval = CGRect(x: 36, y: 8, width: 20, height: 30)
        let output = try flatten(base, [spotlight(rect), spotlight(oval, ellipse: true)])
        for (x, y) in [(2, 40), (30, 4), (60, 44), (20, 30)] {
            #expect(isClose(output[x, y], to: dimmed(original[x, y], by: 0.5)), "outside at \(x), \(y)")
        }
        for (x, y) in [(8, 8), (12, 12), (23, 19), (46, 23), (40, 23), (46, 10)] {
            #expect(output[x, y] == original[x, y], "inside at \(x), \(y)")
        }
        // Pixel (37, 9) lies wholly outside the ellipse, inside its bounding box.
        #expect(isClose(output[37, 9], to: dimmed(original[37, 9], by: 0.5)))
        #expect(output[37, 9] != original[37, 9])
    }

    /// Two overlapping spotlights clear their union: one overlay with two holes, not two overlays.
    @Test func overlappingSpotlightsLeaveTheirUnionUndimmed() throws {
        let base = images.makeImage()
        let original = try Bitmap(base)
        let output = try flatten(base, [spotlight(CGRect(x: 8, y: 8, width: 20, height: 20)),
                                        spotlight(CGRect(x: 20, y: 16, width: 20, height: 20))])
        for (x, y) in [(10, 10), (24, 20), (35, 30), (26, 26)] {
            #expect(output[x, y] == original[x, y], "union at \(x), \(y)")
        }
        for (x, y) in [(30, 10), (10, 32), (45, 20)] {
            #expect(isClose(output[x, y], to: dimmed(original[x, y], by: 0.5)), "outside at \(x), \(y)")
        }
    }

    /// The overlay lies under the drawings: an arrow over the dim keeps its colour, even one made
    /// before the spotlight.
    @Test func anArrowOverTheDimKeepsItsColour() throws {
        let base = images.makeImage()
        let original = try Bitmap(base)
        let arrow = images.arrow(from: CGPoint(x: 8, y: 40), to: CGPoint(x: 56, y: 40))
        let output = try flatten(base, [arrow, spotlight(CGRect(x: 8, y: 4, width: 10, height: 10))])
        #expect(output[30, 40] == EditorFlattenerTests.bluePixel)
        #expect(output[30, 39] == EditorFlattenerTests.bluePixel)
        #expect(isClose(output[30, 30], to: dimmed(original[30, 30], by: 0.5)))
    }

    /// Without a spotlight the dim is ignored: the base comes back byte for byte.
    @Test func noSpotlightDimsNothing() throws {
        let base = images.makeImage()
        let original = try Bitmap(base)
        #expect(try flatten(base, [], dim: 0.7).differences(from: original) == 0)
        let box = CGRect(x: 10, y: 8, width: 30, height: 20)
        #expect(try flatten(base, [images.rectangle(box)], dim: 0.3).differences(from: original, excluding: [box]) == 0)
    }

    /// Each stop darkens by its own amount; the hole is untouched at every stop.
    @Test func eachDimDarkensByItsAmount() throws {
        let colour: [UInt8] = [200, 100, 50, 255]
        let base = uniform(colour)
        for dim in EditorPalette.spotlightDims {
            let output = try flatten(base, [spotlight(CGRect(x: 8, y: 8, width: 16, height: 16))], dim: dim)
            #expect(isClose(output[40, 30], to: dimmed(colour, by: dim)), "dim \(dim): \(output[40, 30])")
            #expect(output[16, 16] == colour, "dim \(dim)")
        }
        #expect(EditorPalette.spotlightDims == [0.3, 0.5, 0.7])
    }

    /// The overlay is drawn on the whole capture and the crop cut afterwards, so the hole stays
    /// where it is in the capture: the cropped export is the uncropped one's pixels at the crop.
    @Test func theCropIsAppliedAfterTheOverlay() throws {
        let base = images.makeImage()
        let original = try Bitmap(base)
        let crop = CGRect(x: 16, y: 8, width: 32, height: 24)
        // Straddles the crop's top-left corner.
        let hole = spotlight(CGRect(x: 8, y: 4, width: 16, height: 12))
        let whole = try flatten(base, [hole])
        let cropped = try flatten(base, [hole], crop: crop)
        #expect(cropped.width == 32)
        #expect(cropped.height == 24)
        for y in 0..<24 {
            for x in 0..<32 where cropped[x, y] != whole[x + 16, y + 8] {
                Issue.record("cropped \(x), \(y) differs")
            }
        }
        // Crop (2, 2) is capture (18, 10), inside the hole; crop (20, 20) is capture (36, 28), outside.
        #expect(cropped[2, 2] == original[18, 10])
        #expect(isClose(cropped[20, 20], to: dimmed(original[36, 28], by: 0.5)))
    }

    /// A strip at a time, the overlay is the same on both sides of each seam, and a hole across
    /// the seam at 16,384 is clear on both sides of it.
    @Test func aTallCaptureIsDimmedTheSameAcrossTheStripSeams() throws {
        let colour: [UInt8] = [200, 100, 50, 255]
        let base = uniform(colour, width: 4, height: 40_000)
        let output = try flatten(base, [spotlight(CGRect(x: 2, y: 16_380, width: 2, height: 8))])
        #expect(output.height == 40_000)
        for y in [16_383, 16_384, 32_767, 32_768, 0, 39_999] {
            #expect(isClose(output[0, y], to: dimmed(colour, by: 0.5)), "row \(y): \(output[0, y])")
        }
        #expect(output[0, 16_383] == output[0, 16_384])
        #expect(output[1, 32_767] == output[1, 32_768])
        for y in [16_380, 16_383, 16_384, 16_387] {
            #expect(output[2, y] == colour, "hole row \(y)")
            #expect(output[3, y] == colour, "hole row \(y)")
        }
        #expect(output[2, 16_379] != colour)
        #expect(output[2, 16_388] != colour)
    }

    // MARK: Alpha

    /// A transparent corner stays transparent, and a half-transparent pixel keeps its alpha while
    /// its colour darkens: the overlay dims the picture, not its transparency.
    @Test func transparencySurvivesTheOverlay() throws {
        let half: [UInt8] = [64, 32, 100, 128]
        let base = images.makeImage { x, y in
            if x < 4, y < 4 { return EditorFlattenerTests.clearPixel }
            if x >= 56, y >= 40 { return half }
            return EditorFlattenerTests.pattern(x, y)
        }
        let output = try flatten(base, [spotlight(CGRect(x: 20, y: 20, width: 10, height: 10))])
        #expect(output[0, 0] == EditorFlattenerTests.clearPixel)
        #expect(output[3, 3] == EditorFlattenerTests.clearPixel)
        let darkened = output[60, 44]
        #expect(darkened[3] == 128)
        #expect(isClose(darkened, to: [32, 16, 50, 128] as [Double]), "\(darkened)")
    }

    /// On an opaque capture the export's `.sourceAtop` composite gives exactly the pixels a
    /// `.normal` composite (the routine with an empty coverage list) gives, edges included.
    @Test func anOpaqueBaseMatchesANormalComposite() throws {
        let base = images.makeImage()
        let shapes = [SpotlightShape(id: UUID(), rect: CGRect(x: 8.5, y: 6.25, width: 17, height: 13.5), isEllipse: false),
                      SpotlightShape(id: UUID(), rect: CGRect(x: 30, y: 10, width: 25, height: 31), isEllipse: true)]
        let exported = try flatten(base, shapes.map(Annotation.spotlight))

        let width = EditorFlattenerTests.width
        let height = EditorFlattenerTests.height
        let reference = try #require(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                               space: sRGB, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        reference.draw(base, in: CGRect(x: 0, y: 0, width: width, height: height))
        reference.translateBy(x: 0, y: CGFloat(height))
        reference.scaleBy(x: 1, y: -1)
        AnnotationDrawing.drawSpotlightOverlay(shapes, dim: 0.5, in: reference,
                                               imageRect: CGRect(x: 0, y: 0, width: width, height: height), coverage: [])
        #expect(exported.differences(from: try bitmap(of: reference)) == 0)
    }

    /// A solid redaction over a transparent corner paints opaque pixels, and the overlay dims them
    /// like any other opaque pixel.
    @Test func aRedactionOverATransparentCornerIsOpaqueAndDimmed() throws {
        let base = images.makeImage { x, y in
            x >= 60 && y < 4 ? EditorFlattenerTests.clearPixel : EditorFlattenerTests.pattern(x, y)
        }
        let effect = Annotation.redact(Region(id: UUID(), rect: CGRect(x: 60, y: 0, width: 4, height: 4)),
                                       fill: RGBA(red: 1, green: 1, blue: 1))
        let fill = images.makeImage(width: 4, height: 4) { _, _ in [255, 255, 255, 255] }
        let output = try flatten(base, [effect, spotlight(CGRect(x: 10, y: 10, width: 10, height: 10))],
                                 tiles: [EffectTile(effect: effect, image: fill)])
        for (x, y) in [(60, 0), (63, 3)] {
            #expect(output[x, y][3] == 255)
            #expect(isClose(output[x, y], to: [127.5, 127.5, 127.5, 255]), "\(output[x, y])")
        }
    }

    // MARK: The canvas's order

    /// The canvas draws the highlighter's backdrop, then the overlay masked by the capture, then
    /// the multiply: under the stroke in the dimmed area that gives the export's pixel, and in a
    /// hole the undimmed multiply. The overlay is never drawn into the backdrop as well.
    @Test func theCanvasOrderMatchesTheExportUnderAHighlighter() throws {
        let base = uniform([230, 220, 200, 255])
        let hole = SpotlightShape(id: UUID(), rect: CGRect(x: 32, y: 0, width: 32, height: 48), isEllipse: false)
        let points = [CGPoint(x: 8, y: 24), CGPoint(x: 32, y: 24), CGPoint(x: 56, y: 24)]
        let marker = highlighter(points)
        let exported = try flatten(base, [.spotlight(hole), marker])
        let plain = try flatten(base, [marker])

        let context = try canvasContext()
        context.saveGState()
        context.addPath(StrokeSmoothing.path(for: points))
        context.setLineWidth(12 + 2)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        context.replacePathWithStrokedPath()
        context.clip()
        HighlighterBackdrop.draw(coverage(base), in: context)
        context.restoreGState()
        AnnotationDrawing.drawSpotlightOverlay([hole], dim: 0.5, in: context,
                                               imageRect: CGRect(x: 0, y: 0, width: 64, height: 48), coverage: coverage(base))
        AnnotationDrawing.draw(marker, in: context, scale: 1)
        let canvas = try bitmap(of: context)

        for (x, y) in [(16, 24), (12, 20), (24, 28)] {
            #expect(isClose(canvas[x, y], to: exported[x, y]), "dimmed \(x), \(y): \(canvas[x, y]) \(exported[x, y])")
        }
        for (x, y) in [(48, 24), (40, 20), (52, 28)] {
            #expect(isClose(canvas[x, y], to: plain[x, y]), "hole \(x), \(y): \(canvas[x, y]) \(plain[x, y])")
        }
        // The dimmed multiply is darker than the plain one, so the overlay was not skipped.
        #expect(canvas[16, 24][1] < plain[16, 24][1])
    }

    /// With a coverage list, the overlay's alpha follows the capture's: none over a transparent
    /// pixel, the dim over an opaque one, none in a hole. An empty list leaves it unmasked.
    @Test func coverageMasksTheOverlayByTheCapturesAlpha() throws {
        let base = images.makeImage { x, y in
            x < 4 && y < 4 ? EditorFlattenerTests.clearPixel : EditorFlattenerTests.pattern(x, y)
        }
        let hole = SpotlightShape(id: UUID(), rect: CGRect(x: 20, y: 20, width: 10, height: 10), isEllipse: false)
        let imageRect = CGRect(x: 0, y: 0, width: 64, height: 48)

        let masked = try canvasContext()
        AnnotationDrawing.drawSpotlightOverlay([hole], dim: 0.5, in: masked, imageRect: imageRect, coverage: coverage(base))
        let overlay = try bitmap(of: masked)
        #expect(overlay[0, 0] == EditorFlattenerTests.clearPixel)
        #expect(overlay[3, 3] == EditorFlattenerTests.clearPixel)
        #expect(isClose(overlay[40, 40], to: [0, 0, 0, 127.5]), "\(overlay[40, 40])")
        #expect(overlay[25, 25] == EditorFlattenerTests.clearPixel)

        let unmasked = try canvasContext()
        AnnotationDrawing.drawSpotlightOverlay([hole], dim: 0.5, in: unmasked, imageRect: imageRect, coverage: [])
        #expect(isClose(try bitmap(of: unmasked)[0, 0], to: [0, 0, 0, 127.5]))
    }
}
