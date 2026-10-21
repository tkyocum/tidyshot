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
        // With a crop applied the canvas shows only the crop: centred in it, not in the whole image.
        let cropped = AnnotationDocument(annotations: []).withCrop(CGRect(x: 0, y: 0, width: 100, height: 100))
        #expect(AnnotationClip(annotation: box(x: 200, y: 200), scale: 2)
            .placed(in: cropped, imageSize: size, scale: 2, step: step, id: id)
                == .rectangle(ShapeBox(id: id, rect: CGRect(x: 30, y: 40, width: 40, height: 20),
                                       color: red, lineWidth: 8)))
    }
}
