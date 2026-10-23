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

    /// 4c's kinds travel on the pasteboard like the others.
    @Test func spotlightAndCounterRoundTrip() throws {
        let kinds: [Annotation] = [
            .spotlight(SpotlightShape(id: UUID(), rect: CGRect(x: 10, y: 20, width: 30, height: 40), isEllipse: true)),
            .counter(CounterMark(id: UUID(), center: CGPoint(x: 50, y: 60), number: 12, diameter: 64, color: red)),
        ]
        for annotation in kinds {
            let clip = AnnotationClip(annotation: annotation, scale: 2)
            #expect(AnnotationClip.decoded(from: try #require(clip.encoded())) == clip)
        }
    }

    /// A counter from a 2x capture pasted into a 1x editor keeps its size in points: its centre
    /// and diameter halve, and it keeps its number (the model renumbers it when it commits).
    @Test func counterFromATwoXClipKeepsItsPointSize() throws {
        let id = UUID()
        let copied = Annotation.counter(CounterMark(id: UUID(), center: CGPoint(x: 100, y: 80), number: 3, diameter: 64,
                                                    color: red))
        let clip = AnnotationClip(annotation: copied, scale: 2)
        let placed = clip.placed(in: AnnotationDocument(annotations: []), imageSize: CGSize(width: 400, height: 300),
                                 scale: 1, step: CGVector(dx: 10, dy: 10), id: id)
        #expect(placed == .counter(CounterMark(id: id, center: CGPoint(x: 50, y: 40), number: 3, diameter: 32, color: red)))
    }

    /// The cascade compares counters without their numbers (spec 2.12): one with another number at
    /// the same place counts as identical, so the paste steps aside; one with another diameter or
    /// colour there does not.
    @Test func cascadeIgnoresACountersNumber() {
        let size = CGSize(width: 400, height: 300)
        let step = CGVector(dx: 20, dy: 20)
        let id = UUID()
        let blue = RGBA(red: 0, green: 0, blue: 1, alpha: 1)
        func counter(number: Int, diameter: CGFloat = 64, color: RGBA? = nil) -> Annotation {
            .counter(CounterMark(id: UUID(), center: CGPoint(x: 100, y: 80), number: number, diameter: diameter,
                                 color: color ?? red))
        }
        let clip = AnnotationClip(annotation: counter(number: 5), scale: 2)
        let landed = clip.annotation.withID(id)

        let sameButNumber = AnnotationDocument(annotations: [counter(number: 1)])
        #expect(clip.placed(in: sameButNumber, imageSize: size, scale: 2, step: step, id: id) == landed.moved(by: step))
        // Two steps when the first is taken too, by a counter with yet another number.
        let twoTaken = sameButNumber.appending(counter(number: 2).moved(by: step))
        #expect(clip.placed(in: twoTaken, imageSize: size, scale: 2, step: step, id: id)
                == landed.moved(by: CGVector(dx: 40, dy: 40)))

        let otherDiameter = AnnotationDocument(annotations: [counter(number: 5, diameter: 88)])
        #expect(clip.placed(in: otherDiameter, imageSize: size, scale: 2, step: step, id: id) == landed)
        let otherColour = AnnotationDocument(annotations: [counter(number: 5, color: blue)])
        #expect(clip.placed(in: otherColour, imageSize: size, scale: 2, step: step, id: id) == landed)
        // Other kinds compare as before: identical apart from the id.
        let shape = box(x: 10, y: 10)
        let shapeClip = AnnotationClip(annotation: shape, scale: 2)
        #expect(shapeClip.placed(in: AnnotationDocument(annotations: [shape]), imageSize: size, scale: 2, step: step, id: id)
                == shape.withID(id).moved(by: step))
    }
}
