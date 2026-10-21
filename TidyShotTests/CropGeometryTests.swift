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

    /// A press in the dimmed area is not a press on the picture (spec 2.6, Crop).
    @Test func pressOutsideAnAppliedCrop() {
        let crop = CGRect(x: 10, y: 10, width: 20, height: 20)
        // Straddles the crop's right edge; its handle at (40, 20) sits in the dimmed area.
        let box = Annotation.rectangle(ShapeBox(id: UUID(), rect: CGRect(x: 20, y: 10, width: 20, height: 20),
                                                color: RGBA(red: 1, green: 0, blue: 0, alpha: 1), lineWidth: 4))
        let outside = CGPoint(x: 50, y: 50)
        func press(_ point: CGPoint, tool: EditorTool, crop: CGRect? = crop, selected: Annotation? = nil) -> CropGeometry.Press {
            CropGeometry.press(at: point, crop: crop, tool: tool, selected: selected, tolerance: 2)
        }
        // Inside, or no crop: the tool sees the press as it landed, edges included.
        #expect(press(CGPoint(x: 15, y: 15), tool: .select) == .asPressed)
        #expect(press(CGPoint(x: 30, y: 30), tool: .text) == .asPressed)
        #expect(press(outside, tool: .select, crop: nil) == .asPressed)
        // Select: outside deselects, unless it is on a handle of the selection.
        #expect(press(outside, tool: .select) == .deselect)
        #expect(press(CGPoint(x: 35, y: 20), tool: .select, selected: box) == .deselect)
        #expect(press(CGPoint(x: 40, y: 20), tool: .select, selected: box) == .asPressed)
        #expect(press(CGPoint(x: 40, y: 20), tool: .select) == .deselect)
        // Text ignores it; the drawing tools begin at the edge.
        #expect(press(outside, tool: .text) == .ignore)
        for tool in [EditorTool.redact, .pixelate, .blur, .rectangle, .arrow, .ellipse, .line, .pencil, .highlighter] {
            #expect(press(outside, tool: tool) == .clampedToEdge)
        }
        #expect(CropGeometry.clamped(outside, to: crop) == CGPoint(x: 30, y: 30))
        #expect(CropGeometry.clamped(CGPoint(x: 15, y: 0), to: crop) == CGPoint(x: 15, y: 10))
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
