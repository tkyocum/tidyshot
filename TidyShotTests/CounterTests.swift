import CoreGraphics
import CoreText
import Foundation
import Testing
@testable import TidyShot

/// The Counter (spec 2.12): numbering, placing, the colour of the number, and the drawn circle, the
/// last through `EditorFlattener` on real pixels.
struct CounterTests {
    typealias Bitmap = EditorFlattenerTests.Bitmap

    let models = EditorModelTests()
    let images = EditorFlattenerTests()
    let red = EditorPalette.defaultStroke

    func counter(_ number: Int, at center: CGPoint = CGPoint(x: 40, y: 40), diameter: CGFloat = 64,
                 color: RGBA? = nil) -> Annotation {
        .counter(CounterMark(id: UUID(), center: center, number: number, diameter: diameter, color: color ?? red))
    }

    func numbers(in document: AnnotationDocument) -> [Int] {
        document.annotations.compactMap(\.counterMark?.number)
    }

    /// A 128 x 96 capture, room for a 2x Medium counter, whose pixels encode their place.
    func makeBase() -> CGImage {
        images.makeImage(width: 128, height: 96) { x, y in [UInt8(x), UInt8(y), 90, 255] }
    }

    // MARK: Numbering

    @Test func nextNumberIsOneMoreThanTheLargest() {
        #expect(AnnotationDocument(annotations: []).nextCounterNumber == 1)
        let arrow = Annotation.arrow(Segment(id: UUID(), from: .zero, to: CGPoint(x: 9, y: 9), color: red, lineWidth: 4))
        #expect(AnnotationDocument(annotations: [arrow]).nextCounterNumber == 1)
        let two = counter(2)
        let document = AnnotationDocument(annotations: [counter(1), arrow, two, counter(3)])
        #expect(document.nextCounterNumber == 4)
        // Deleting a counter renumbers nothing, so the next is still one more than the largest.
        #expect(document.removing(id: two.id).nextCounterNumber == 4)
    }

    /// A counter comes back with the document's next number, whatever it arrived with, and keeps
    /// its id; any other kind comes back unchanged.
    @Test func renumberedTakesTheDocumentsNextNumber() throws {
        let document = AnnotationDocument(annotations: [counter(1), counter(7)])
        let arrived = counter(3)
        let renumbered = arrived.renumbered(in: document)
        #expect(renumbered.id == arrived.id)
        #expect(renumbered.counterMark?.number == 8)
        #expect(counter(99).renumbered(in: AnnotationDocument(annotations: [])).counterMark?.number == 1)
        let box = Annotation.rectangle(ShapeBox(id: UUID(), rect: CGRect(x: 1, y: 1, width: 5, height: 5), color: red,
                                                lineWidth: 2))
        #expect(box.renumbered(in: document) == box)
    }

    /// Size changes a counter's diameter about its centre; other kinds come back unchanged.
    @Test func withCounterDiameterKeepsTheCentre() {
        let mark = counter(4, at: CGPoint(x: 50, y: 30), diameter: 64)
        #expect(mark.withCounterDiameter(88)
                == .counter(CounterMark(id: mark.id, center: CGPoint(x: 50, y: 30), number: 4, diameter: 88, color: red)))
        let hole = Annotation.spotlight(SpotlightShape(id: UUID(), rect: CGRect(x: 0, y: 0, width: 9, height: 9),
                                                       isEllipse: false))
        #expect(hole.withCounterDiameter(88) == hole)
    }

    /// ⌘D, the ⌥-drag copy and ⌘V each number the new counter one more than the largest, through
    /// the real model, so no number repeats. Undo gives back the numbers the document had.
    @Test func duplicateOptionDragAndPasteEachTakeTheNextNumber() throws {
        let model = models.makeModel(side: 400)
        model.tool = .select
        let first = models.add(counter(1, at: CGPoint(x: 60, y: 60)), to: model)
        models.add(counter(2, at: CGPoint(x: 200, y: 60)), to: model)

        model.selection = first.id
        model.duplicateSelection()
        #expect(numbers(in: model.document) == [1, 2, 3])
        #expect(model.undoManager.undoActionName == "Duplicate Counter")

        let select = makeTool(for: .select)
        select.mouseDown(ToolInput(point: CGPoint(x: 60, y: 60), option: true), on: model)
        select.mouseDragged(ToolInput(point: CGPoint(x: 60, y: 200), option: true), on: model)
        #expect(model.transient?.counterMark?.number == 4)
        select.mouseUp(ToolInput(point: CGPoint(x: 60, y: 200), option: true), on: model)
        #expect(numbers(in: model.document) == [1, 2, 3, 4])
        #expect(model.undoManager.undoActionName == "Duplicate Counter")
        #expect(model.document.annotation(id: first.id) == first)

        model.selection = first.id
        let clip = try #require(model.objectClip())
        model.paste(clip)
        #expect(numbers(in: model.document) == [1, 2, 3, 4, 5])
        #expect(model.undoManager.undoActionName == "Paste Counter")
        #expect(model.selection == model.document.annotations.last?.id)

        model.undoManager.undo()
        #expect(numbers(in: model.document) == [1, 2, 3, 4])
        #expect(model.document.nextCounterNumber == 5)
    }

    /// Pasting one counter three times steps it 1, 2 and 3 duplicate offsets away from the
    /// original, as counters 2, 3 and 4: the cascade ignores the numbers (spec 2.12).
    @Test func threePastesOfOneCounterCascade() throws {
        let model = models.makeModel(side: 200)
        let original = models.add(counter(1, at: CGPoint(x: 40, y: 40)), to: model)
        model.selection = original.id
        let clip = try #require(model.objectClip())
        for (step, number) in [(1, 2), (2, 3), (3, 4)] {
            model.paste(clip)
            let pasted = try #require(model.document.annotations.last)
            let offset = CGFloat(20 * step)
            #expect(pasted == .counter(CounterMark(id: pasted.id, center: CGPoint(x: 40 + offset, y: 40 + offset),
                                                   number: number, diameter: 64, color: red)))
            #expect(model.selection == pasted.id)
        }
        #expect(model.document.annotation(id: original.id) == original)
        #expect(models.undoAll(model).count == 4)
    }

    // MARK: Placing

    /// The whole circle stays inside the image or the crop; on an axis where they are narrower
    /// than the counter, it is centred.
    @Test func centreClampsInsideTheBounds() {
        let image = CGRect(x: 0, y: 0, width: 400, height: 300)
        // Well inside: the press itself.
        #expect(CounterLayout.center(forPress: CGPoint(x: 100, y: 80), diameter: 64, within: image)
                == CGPoint(x: 100, y: 80))
        // Near each edge and outside it: clamped by the radius.
        #expect(CounterLayout.center(forPress: CGPoint(x: 5, y: 290), diameter: 64, within: image)
                == CGPoint(x: 32, y: 268))
        #expect(CounterLayout.center(forPress: CGPoint(x: 500, y: -40), diameter: 64, within: image)
                == CGPoint(x: 368, y: 32))
        // Inside a crop: the same, against the crop's edges.
        let crop = CGRect(x: 100, y: 50, width: 200, height: 100)
        #expect(CounterLayout.center(forPress: CGPoint(x: 110, y: 145), diameter: 64, within: crop)
                == CGPoint(x: 132, y: 118))
        #expect(CounterLayout.center(forPress: CGPoint(x: 299, y: 51), diameter: 64, within: crop)
                == CGPoint(x: 268, y: 82))
        // Narrower than the counter on one axis: centred there, clamped on the other.
        let strip = CGRect(x: 100, y: 50, width: 200, height: 40)
        #expect(CounterLayout.center(forPress: CGPoint(x: 120, y: 52), diameter: 64, within: strip)
                == CGPoint(x: 132, y: 70))
        // Smaller on both axes: centred on both.
        #expect(CounterLayout.center(forPress: CGPoint(x: 0, y: 0), diameter: 64,
                                     within: CGRect(x: 10, y: 20, width: 30, height: 50))
                == CGPoint(x: 25, y: 45))
        // Exactly as wide as the counter: the one place it fits.
        #expect(CounterLayout.center(forPress: CGPoint(x: 0, y: 70), diameter: 64,
                                     within: CGRect(x: 10, y: 0, width: 64, height: 300))
                == CGPoint(x: 42, y: 70))
    }

    // MARK: Look

    /// White on Black, Red, Blue, Purple and Pink; black on Orange, Yellow, Green, Teal and White;
    /// and black on a 180/255 grey, which a linearised measure would give white digits.
    @Test func numberColourContrastsWithEverySwatch() {
        let white = RGBA(red: 1, green: 1, blue: 1)
        let black = RGBA(red: 0, green: 0, blue: 0)
        #expect(EditorPalette.swatches.count == 10)
        let expected = [white, white, black, black, black, black, white, white, white, black]
        for (swatch, text) in zip(EditorPalette.swatches, expected) {
            #expect(EditorPalette.contrastingTextColor(for: swatch) == text, "\(swatch)")
        }
        let grey = Double(180) / 255
        #expect(EditorPalette.contrastingTextColor(for: RGBA(red: grey, green: grey, blue: grey)) == black)
    }

    /// The circle is filled in the counter's colour, its outer 1.5 pt is a white ring, and nothing
    /// paints outside its box.
    @Test func renderedCounterIsFilledAndRinged() throws {
        let base = makeBase()
        let mark = CounterMark(id: UUID(), center: CGPoint(x: 64, y: 48), number: 3, diameter: 64, color: red)
        let document = AnnotationDocument(annotations: [.counter(mark)])
        let flat = try Bitmap(try #require(EditorFlattener.flatten(base: base, tiles: [], document: document, scale: 2)))
        // Below the glyph and inside the ring, at (centre.x, centre.y + 0.35 × diameter): the fill.
        #expect(flat[64, Int(48 + 0.35 * 64)] == [255, 59, 48, 255])
        // Just inside the edge, within the 3 px ring at 2x: white.
        #expect(flat[64 + 30, 48] == [255, 255, 255, 255])
        #expect(flat[64 - 31, 48] == [255, 255, 255, 255])
        #expect(flat[64, 48 + 30] == [255, 255, 255, 255])
        // Just outside the edge: the base.
        let original = try Bitmap(base)
        #expect(flat[64 + 33, 48] == original[64 + 33, 48])
        let bounds = AnnotationGeometry.bounds(of: .counter(mark), scale: 2)
        #expect(flat.differences(from: original, excluding: [bounds]) == 0)
    }

    /// The digits sit on the centre: the number's ink, in its contrasting colour, is centred on the
    /// circle within a pixel or so, and about a cap height tall.
    @Test func renderedNumberIsCentred() throws {
        let base = makeBase()
        let mark = CounterMark(id: UUID(), center: CGPoint(x: 64, y: 48), number: 8, diameter: 64, color: red)
        let document = AnnotationDocument(annotations: [.counter(mark)])
        let flat = try Bitmap(try #require(EditorFlattener.flatten(base: base, tiles: [], document: document, scale: 2)))
        // White digits on red: the green channel rises well above the fill's 59 only where there is ink.
        var ink = CGRect.null
        for y in 0..<flat.height {
            for x in 0..<flat.width where hypot(Double(x) + 0.5 - 64, Double(y) + 0.5 - 48) < 26 && flat[x, y][1] > 160 {
                ink = ink.union(CGRect(x: x, y: y, width: 1, height: 1))
            }
        }
        try #require(!ink.isNull)
        #expect(abs(ink.midX - 64) <= 1.5)
        #expect(abs(ink.midY - 48) <= 1.5)
        let capHeight = CTFontGetCapHeight(TextLayout.font(size: CounterLayout.fontSize(number: 8, diameter: 64)))
        #expect(abs(ink.height - capHeight) <= 2)
    }

    /// One and two digits are drawn at 0.55 × diameter; any number's line fits in 0.8 × diameter,
    /// so 100 is the first to be drawn smaller. Checked at every Size stop at 1x and 2x.
    @Test func numbersFitTheCircle() {
        for diameter: CGFloat in [24, 32, 44, 48, 64, 88] {
            for number in [9, 42, 100] {
                let size = CounterLayout.fontSize(number: number, diameter: diameter)
                let width = TextLayout.width(of: String(number), font: TextLayout.font(size: size))
                #expect(width <= 0.8 * diameter, "\(number) at \(diameter)")
            }
            #expect(CounterLayout.fontSize(number: 9, diameter: diameter) == 0.55 * diameter)
            #expect(CounterLayout.fontSize(number: 42, diameter: diameter) == 0.55 * diameter)
            #expect(CounterLayout.fontSize(number: 100, diameter: diameter) < 0.55 * diameter, "\(diameter)")
        }
    }

    /// phase-4c :159. Undoing the paste, the ⌥-drag copy and the ⌘D copy in turn returns the numbers to 1 and 2;
    /// each redo brings its copy back with its number; after undoing the three again a new counter is 3.
    @Test func undoingCopiesReturnsTheNumbersAndRedoRestoresThem() throws {
        let model = models.makeModel(side: 400)
        model.tool = .select
        let first = models.add(counter(1, at: CGPoint(x: 60, y: 60)), to: model)
        models.add(counter(2, at: CGPoint(x: 200, y: 60)), to: model)
        model.selection = first.id
        model.duplicateSelection()
        let select = makeTool(for: .select)
        select.mouseDown(ToolInput(point: CGPoint(x: 60, y: 60), option: true), on: model)
        select.mouseDragged(ToolInput(point: CGPoint(x: 60, y: 200), option: true), on: model)
        select.mouseUp(ToolInput(point: CGPoint(x: 60, y: 200), option: true), on: model)
        model.selection = first.id
        model.paste(try #require(model.objectClip()))
        #expect(numbers(in: model.document) == [1, 2, 3, 4, 5])

        for expected in [[1, 2, 3, 4], [1, 2, 3], [1, 2]] {
            model.undoManager.undo()
            #expect(numbers(in: model.document) == expected)
        }
        for expected in [[1, 2, 3], [1, 2, 3, 4], [1, 2, 3, 4, 5]] {
            model.undoManager.redo()
            #expect(numbers(in: model.document) == expected)
        }
        for _ in 0..<3 { model.undoManager.undo() }
        let placed = try #require(model.makeAnnotation(.counter, from: CGPoint(x: 300, y: 300),
                                                       to: CGPoint(x: 300, y: 300)))
        #expect(placed.counterMark?.number == 3)
    }

    /// phase-4c :162. A counter copied in an editor at one scale and pasted twice into one at another takes the
    /// target's next numbers, the second cascaded from the first, at the source's point size (64 px at 2x is
    /// 32 px at 1x); both ways.
    @Test func aCounterPastedTwiceAcrossScalesTakesTheNextNumbersAtItsPointSize() throws {
        for (from, to) in [(CGFloat(2), CGFloat(1)), (CGFloat(1), CGFloat(2))] {
            let source = models.makeModel(scale: from, side: 400)
            let mark = models.add(counter(1, at: CGPoint(x: 100, y: 100), diameter: 32 * from), to: source)
            source.selection = mark.id
            let data = try #require(source.objectClip()?.encoded())
            let clip = try #require(AnnotationClip.decoded(from: data))
            let target = models.makeModel(scale: to, side: 400)
            models.add(counter(1, at: CGPoint(x: 300, y: 300), diameter: 32 * to), to: target)
            models.add(counter(2, at: CGPoint(x: 340, y: 300), diameter: 32 * to), to: target)

            target.paste(clip)
            let firstPaste = try #require(target.document.annotations.last?.counterMark)
            target.paste(clip)
            let secondPaste = try #require(target.document.annotations.last?.counterMark)

            #expect(firstPaste.number == 3)
            #expect(secondPaste.number == 4)
            #expect(firstPaste.diameter == 32 * to)
            #expect(secondPaste.diameter == 32 * to)
            #expect(secondPaste.center == CGPoint(x: firstPaste.center.x + target.duplicateOffset.dx,
                                                  y: firstPaste.center.y + target.duplicateOffset.dy))
        }
    }
}
