import CoreGraphics
import CoreText
import Foundation
import Testing
@testable import TidyShot

/// The export path: the base, then the effect tiles, then the drawings, burned into one bitmap at
/// the capture's own pixel size. The base is 64 x 48 and its green channel encodes the row, so a
/// write to the wrong rows (a missing or doubled flip) lands somewhere visibly different.
struct EditorFlattenerTests {
    static let width = 64
    static let height = 48

    static let redPixel: [UInt8] = [255, 0, 0, 255]
    static let bluePixel: [UInt8] = [0, 0, 255, 255]
    static let greenPixel: [UInt8] = [0, 255, 0, 255]
    static let magentaPixel: [UInt8] = [255, 0, 255, 255]
    static let blackPixel: [UInt8] = [0, 0, 0, 255]
    static let clearPixel: [UInt8] = [0, 0, 0, 0]

    let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!
    let red = RGBA(red: 1, green: 0, blue: 0, alpha: 1)
    let blue = RGBA(red: 0, green: 0, blue: 1, alpha: 1)
    let black = RGBA(red: 0, green: 0, blue: 0, alpha: 1)

    /// Premultiplied RGBA of base pixel (x, y), top-left origin. Green is 3 + 5y, never 0 or 255,
    /// so no base pixel equals any of the colours above.
    nonisolated static func pattern(_ x: Int, _ y: Int) -> [UInt8] {
        [UInt8((x * 4 + y) % 256), UInt8(3 + y * 5), UInt8((x * 7 + y * 11 + 17) % 256), 255]
    }

    /// An image built from rows of premultiplied RGBA, top row first.
    func makeImage(width: Int = EditorFlattenerTests.width, height: Int = EditorFlattenerTests.height,
                   space: CGColorSpace? = nil,
                   pixel: (Int, Int) -> [UInt8] = EditorFlattenerTests.pattern) -> CGImage {
        var bytes: [UInt8] = []
        bytes.reserveCapacity(width * height * 4)
        for y in 0..<height {
            for x in 0..<width { bytes += pixel(x, y) }
        }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                       space: space ?? sRGB,
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: CGDataProvider(data: Data(bytes) as CFData)!,
                       decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
    }

    /// The stored bytes of an 8-bit premultiplied RGBA image, read without any colour conversion.
    struct Bitmap {
        let width: Int
        let height: Int
        let rows: [[UInt8]]

        init(_ image: CGImage) throws {
            try #require(image.bitsPerComponent == 8 && image.bitsPerPixel == 32)
            try #require(image.alphaInfo == .premultipliedLast)
            try #require(image.byteOrderInfo == .orderDefault || image.byteOrderInfo == .order32Big)
            let data = try #require(image.dataProvider?.data) as Data
            width = image.width
            height = image.height
            rows = (0..<image.height).map { y in
                let start = y * image.bytesPerRow
                return Array(data[start..<(start + image.width * 4)])
            }
        }

        /// The pixel at (x, y), top-left origin.
        subscript(x: Int, y: Int) -> [UInt8] {
            Array(rows[y][(x * 4)..<(x * 4 + 4)])
        }

        /// How many pixels differ from `other`, skipping those whose centre lies in `excluded`.
        func differences(from other: Bitmap, excluding excluded: [CGRect] = []) -> Int {
            var count = 0
            for y in 0..<height {
                for x in 0..<width {
                    let centre = CGPoint(x: Double(x) + 0.5, y: Double(y) + 0.5)
                    if excluded.contains(where: { $0.contains(centre) }) { continue }
                    if self[x, y] != other[x, y] { count += 1 }
                }
            }
            return count
        }
    }

    func redact(_ rect: CGRect) -> Annotation {
        .redact(Region(id: UUID(), rect: rect), fill: black)
    }

    func rectangle(_ rect: CGRect, lineWidth: CGFloat = 4) -> Annotation {
        .rectangle(ShapeBox(id: UUID(), rect: rect, color: red, lineWidth: lineWidth))
    }

    func arrow(from: CGPoint, to: CGPoint, lineWidth: CGFloat = 4) -> Annotation {
        .arrow(Segment(id: UUID(), from: from, to: to, color: blue, lineWidth: lineWidth))
    }

    func ellipse(_ rect: CGRect, lineWidth: CGFloat = 4) -> Annotation {
        .ellipse(ShapeBox(id: UUID(), rect: rect, color: red, lineWidth: lineWidth))
    }

    func line(from: CGPoint, to: CGPoint, lineWidth: CGFloat = 4) -> Annotation {
        .line(Segment(id: UUID(), from: from, to: to, color: blue, lineWidth: lineWidth))
    }

    /// A tile whose rows tell top from bottom: magenta on top, a clear bottom row, green between.
    func markedTile(for effect: Annotation, width: Int, height: Int) -> EffectTile {
        EffectTile(effect: effect, image: makeImage(width: width, height: height) { _, y in
            y == 0 ? Self.magentaPixel : y == height - 1 ? Self.clearPixel : Self.greenPixel
        })
    }

    func flatten(_ base: CGImage, _ annotations: [Annotation], tiles: [EffectTile] = [], scale: CGFloat = 1) throws -> CGImage {
        try #require(EditorFlattener.flatten(base: base, tiles: tiles,
                                             document: AnnotationDocument(annotations: annotations), scale: scale))
    }

    func spaceName(_ image: CGImage) -> String? {
        image.colorSpace?.name.map { $0 as String }
    }

    @Test func outputSizeEqualsBase() throws {
        let output = try flatten(makeImage(), [rectangle(CGRect(x: 10, y: 8, width: 30, height: 20))])
        #expect(output.width == 64)
        #expect(output.height == 48)
        #expect(output.bitsPerComponent == 8)
        #expect(output.alphaInfo == .premultipliedLast)
        #expect(spaceName(output) == CGColorSpace.sRGB as String)
    }

    /// With nothing to draw the base comes back byte for byte; one tile changes its own rect only.
    @Test func bytesOutsideEffectsEqualBase() throws {
        let base = makeImage()
        let original = try Bitmap(base)
        #expect(try Bitmap(flatten(base, [])).differences(from: original) == 0)

        let rect = CGRect(x: 8, y: 4, width: 10, height: 6)
        let effect = redact(rect)
        let output = try Bitmap(flatten(base, [effect], tiles: [markedTile(for: effect, width: 10, height: 6)]))
        #expect(output.differences(from: original, excluding: [rect]) == 0)
        #expect(output.differences(from: original) == 60)
    }

    /// A capture taller than `ImageTiling.maxTileSide` is copied in strip by strip: every row,
    /// across the seams at 16,384 and 32,768, equals the base byte for byte, and a redaction near
    /// the bottom lands on its own rows. Red and green together number each row.
    @Test func aTallBaseIsCopiedExactlyAcrossTheStripSeams() throws {
        let height = 40_000
        let base = makeImage(width: 4, height: height) { x, y in [UInt8(y / 256 % 256), UInt8(y % 256), UInt8(x), 255] }
        let original = try Bitmap(base)
        let rect = CGRect(x: 1, y: 39_990, width: 2, height: 5)
        let effect = redact(rect)
        let output = try Bitmap(flatten(base, [effect], tiles: [markedTile(for: effect, width: 2, height: 5)]))
        #expect(output.height == height)
        #expect(output.differences(from: original, excluding: [rect]) == 0)
        #expect(output[1, 39_990] == Self.magentaPixel)
        #expect(output[2, 39_994] == Self.clearPixel)
        for y in [16_383, 16_384, 32_767, 32_768, 39_999] {
            #expect(output[0, y] == original[0, y])
        }
    }

    /// The tile's first row lands on image row 4, the top of its rect, not on row 38 where an
    /// unflipped draw would put it. Its pixels replace the base: the clear row stays clear.
    @Test func tileBytesLandAtFlippedRows() throws {
        let base = makeImage()
        let original = try Bitmap(base)
        let effect = redact(CGRect(x: 8, y: 4, width: 10, height: 6))
        let output = try Bitmap(flatten(base, [effect], tiles: [markedTile(for: effect, width: 10, height: 6)]))
        for x in 8..<18 {
            #expect(output[x, 4] == Self.magentaPixel)
            #expect(output[x, 7] == Self.greenPixel)
            #expect(output[x, 9] == Self.clearPixel)
        }
        #expect(output[7, 4] == original[7, 4])
        #expect(output[18, 4] == original[18, 4])
        #expect(output[8, 3] == original[8, 3])
        #expect(output[8, 10] == original[8, 10])
        for y in 38..<44 {
            #expect(output[8, y] == original[8, y])
        }
    }

    /// A 4 px stroke on (10, 8, 30, 20) sits inside the rect: columns 10 to 13 and 36 to 39, rows
    /// 8 to 11 and 24 to 27.
    @Test func rectangleStrokeHitsExpectedPixelsAndCentreUntouched() throws {
        let base = makeImage()
        let original = try Bitmap(base)
        let output = try Bitmap(flatten(base, [rectangle(CGRect(x: 10, y: 8, width: 30, height: 20))]))
        let stroked = [(10, 8), (39, 8), (10, 27), (39, 27), (25, 8), (25, 11), (25, 24), (25, 27),
                       (10, 18), (13, 18), (36, 18), (39, 18)]
        for (x, y) in stroked {
            #expect(output[x, y] == Self.redPixel, "stroke at \(x), \(y)")
        }
        let untouched = [(25, 18), (14, 18), (35, 18), (25, 12), (25, 23), (9, 18), (40, 18), (25, 7), (25, 28)]
        for (x, y) in untouched {
            #expect(output[x, y] == original[x, y], "untouched at \(x), \(y)")
        }
    }

    /// The arrow runs along row 12, away from the middle row, so a flip would move it. A point
    /// halfway between the head's centroid and one barb lies off the 4 px shaft, so its colour
    /// comes from the filled head; the same row near the tail is untouched.
    @Test func arrowHeadPixelPresent() throws {
        let base = makeImage()
        let original = try Bitmap(base)
        let from = CGPoint(x: 8, y: 12)
        let to = CGPoint(x: 56, y: 12)
        let output = try Bitmap(flatten(base, [arrow(from: from, to: to)]))
        let head = ArrowGeometry.head(from: from, to: to, lineWidth: 4, scale: 1)
        let centroid = CGPoint(x: (head.tip.x + head.left.x + head.right.x) / 3,
                               y: (head.tip.y + head.left.y + head.right.y) / 3)
        let probe = CGPoint(x: (centroid.x + head.left.x) / 2, y: (centroid.y + head.left.y) / 2)
        try #require(abs(probe.y - 12) > 3, "the probe lies off the shaft")
        let row = Int(probe.y.rounded(.down))
        #expect(output[Int(probe.x.rounded(.down)), row] == Self.bluePixel)
        #expect(output[12, row] == original[12, row])
        #expect(output[30, 11] == Self.bluePixel)
        #expect(output[61, 12] == original[61, 12])
    }

    /// A level pencil stroke along row 12 (width 4) covers rows 10 to 13 and nothing else. Row 12
    /// is far from the middle row, so a missing or doubled flip would move it to row 35.
    @Test func pencilStrokePixels() throws {
        let base = makeImage()
        let original = try Bitmap(base)
        let line = [CGPoint(x: 8, y: 12), CGPoint(x: 32, y: 12), CGPoint(x: 56, y: 12)]
        let pencil = Annotation.pencil(Stroke(id: UUID(), points: line, color: red, lineWidth: 4))
        let output = try Bitmap(flatten(base, [pencil]))
        for (x, y) in [(30, 10), (30, 11), (30, 12), (30, 13), (9, 11), (55, 12)] {
            #expect(output[x, y] == Self.redPixel, "stroke at \(x), \(y)")
        }
        for (x, y) in [(30, 9), (30, 14), (30, 35), (3, 12), (60, 12)] {
            #expect(output[x, y] == original[x, y], "untouched at \(x), \(y)")
        }
    }

    /// Multiply never lightens. The left half is black and the right half white: a normal blend of
    /// translucent yellow would lift the black to (115, 92, 0); multiply leaves it black and tints
    /// the white to yellow x 0.45 + white x 0.55, about (255, 232, 140). Outside the band nothing
    /// changes, and the tint is the same along the whole band.
    @Test func highlighterDarkensNeverLightens() throws {
        let base = makeImage { x, _ in x < 32 ? Self.blackPixel : [255, 255, 255, 255] }
        let original = try Bitmap(base)
        let line = [CGPoint(x: 8, y: 24), CGPoint(x: 32, y: 24), CGPoint(x: 56, y: 24)]
        let marker = Annotation.highlighter(Stroke(id: UUID(), points: line, color: EditorPalette.defaultHighlight,
                                                   lineWidth: 12))
        let output = try Bitmap(flatten(base, [marker]))

        var lighter: [String] = []
        for y in 0..<output.height {
            for x in 0..<output.width {
                for channel in 0..<4 where output[x, y][channel] > original[x, y][channel] {
                    lighter.append("\(x),\(y),\(channel)")
                }
            }
        }
        #expect(lighter.isEmpty, "lightened: \(lighter.prefix(5))")

        #expect(output[16, 24] == Self.blackPixel)
        let tinted = output[48, 24]
        #expect(tinted[0] == 255)
        #expect((230...234).contains(Int(tinted[1])), "green \(tinted[1])")
        #expect((138...142).contains(Int(tinted[2])), "blue \(tinted[2])")
        #expect(tinted[3] == 255)
        // The band is rows 18 to 29.
        #expect(output[48, 17] == original[48, 17])
        #expect(output[48, 30] == original[48, 30])
        #expect(output[48, 24] == output[48, 19])
    }

    /// A 4 px stroke on the ellipse in (10, 8, 40, 24) sits inside the rect: the centre line is the
    /// ellipse in (12, 10, 36, 20), centre (30, 20) with radii 18 and 10, so the band runs from radii
    /// (16, 8) to (20, 12). The bounding box's corners and the hollow are untouched, which tells an
    /// ellipse from a rectangle, and the off-centre rows tell a flip.
    @Test func ellipseStrokePixels() throws {
        let base = makeImage()
        let original = try Bitmap(base)
        let output = try Bitmap(flatten(base, [ellipse(CGRect(x: 10, y: 8, width: 40, height: 24))]))
        let stroked = [(11, 19), (11, 20), (47, 19), (47, 20), (30, 9), (29, 9), (30, 30), (29, 30), (42, 26)]
        for (x, y) in stroked {
            #expect(output[x, y] == Self.redPixel, "stroke at \(x), \(y)")
        }
        let untouched = [(30, 20), (20, 20), (10, 8), (49, 8), (10, 31), (49, 31), (8, 20), (30, 6)]
        for (x, y) in untouched {
            #expect(output[x, y] == original[x, y], "untouched at \(x), \(y)")
        }
    }

    /// A level line along row 12 (rows 10 to 13 at 4 px) with round caps: the pixels just beyond
    /// each end, which a butt cap would leave alone, are painted. A diagonal from (10, 30) to
    /// (40, 40) crosses (25, 35). Neither line is near the middle row, so a flip would move them.
    @Test func lineStrokePixels() throws {
        let base = makeImage()
        let original = try Bitmap(base)
        let level = line(from: CGPoint(x: 8, y: 12), to: CGPoint(x: 56, y: 12))
        let slanted = line(from: CGPoint(x: 10, y: 30), to: CGPoint(x: 40, y: 40))
        let output = try Bitmap(flatten(base, [level, slanted]))
        let stroked = [(30, 10), (30, 13), (8, 11), (7, 11), (7, 12), (56, 11), (56, 12), (25, 35)]
        for (x, y) in stroked {
            #expect(output[x, y] == Self.bluePixel, "stroke at \(x), \(y)")
        }
        let untouched = [(30, 8), (30, 15), (4, 12), (60, 12), (25, 40), (25, 30)]
        for (x, y) in untouched {
            #expect(output[x, y] == original[x, y], "untouched at \(x), \(y)")
        }
    }

    /// The rectangle was created before the redaction, yet its stroke covers the tile: effects
    /// belong to the base layer.
    @Test func drawingsRenderAboveTiles() throws {
        let effect = redact(CGRect(x: 8, y: 4, width: 10, height: 6))
        let box = rectangle(CGRect(x: 4, y: 2, width: 30, height: 20))
        let output = try Bitmap(flatten(makeImage(), [box, effect], tiles: [markedTile(for: effect, width: 10, height: 6)]))
        #expect(output[10, 4] == Self.redPixel)
        #expect(output[10, 5] == Self.redPixel)
        #expect(output[10, 6] == Self.greenPixel)
    }

    /// Window captures have transparent corners. One stays clear; a solid redaction over the
    /// other paints opaque pixels.
    @Test func alphaZeroCornerKept() throws {
        let base = makeImage { x, y in
            (x < 4 || x >= 60) && y < 4 ? Self.clearPixel : Self.pattern(x, y)
        }
        let effect = redact(CGRect(x: 60, y: 0, width: 4, height: 4))
        let fill = makeImage(width: 4, height: 4) { _, _ in Self.blackPixel }
        let output = try Bitmap(flatten(base, [effect, rectangle(CGRect(x: 20, y: 20, width: 10, height: 10))],
                                        tiles: [EffectTile(effect: effect, image: fill)]))
        #expect(output[0, 0] == Self.clearPixel)
        #expect(output[3, 3] == Self.clearPixel)
        #expect(output[60, 0] == Self.blackPixel)
        #expect(output[63, 3] == Self.blackPixel)
    }

    /// A Display P3 capture is flattened in P3: untouched pixels are not converted through sRGB.
    @Test func displayP3BaseKeepsColourSpace() throws {
        let p3 = try #require(CGColorSpace(name: CGColorSpace.displayP3))
        let base = makeImage(space: p3)
        let box = CGRect(x: 10, y: 8, width: 30, height: 20)
        let output = try flatten(base, [rectangle(box)])
        #expect(spaceName(output) == CGColorSpace.displayP3 as String)
        #expect(try Bitmap(output).differences(from: Bitmap(base), excluding: [box]) == 0)
    }

    /// A grey base would give a grey bitmap and turn a red stroke grey, so it is drawn into sRGB.
    @Test func greyBaseFallsBackToSRGB() throws {
        let grey = try #require(CGColorSpace(name: CGColorSpace.genericGrayGamma2_2))
        let context = try #require(CGContext(data: nil, width: 64, height: 48, bitsPerComponent: 8, bytesPerRow: 0,
                                             space: grey, bitmapInfo: CGImageAlphaInfo.none.rawValue))
        context.setFillColor(gray: 0.5, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: 64, height: 48))
        let base = try #require(context.makeImage())
        let output = try flatten(base, [rectangle(CGRect(x: 10, y: 8, width: 30, height: 20))])
        #expect(spaceName(output) == CGColorSpace.sRGB as String)
        let pixels = try Bitmap(output)
        #expect(pixels[10, 8] == Self.redPixel)
        let untouched = pixels[25, 18]
        #expect(untouched[3] == 255)
        #expect(abs(Int(untouched[0]) - Int(untouched[1])) <= 1 && abs(Int(untouched[1]) - Int(untouched[2])) <= 1)
    }

    /// Encoding at the capture's scale keeps a Retina edit at 144 DPI.
    @Test func pngRoundTripKeepsScaleTwo() throws {
        let effect = redact(CGRect(x: 8, y: 4, width: 10, height: 6))
        let output = try flatten(makeImage(), [effect, arrow(from: CGPoint(x: 8, y: 30), to: CGPoint(x: 56, y: 30))],
                                 tiles: [markedTile(for: effect, width: 10, height: 6)], scale: 2)
        let decoded = try #require(ImageEncoder.decode(try ImageEncoder.pngData(from: output, scale: 2)))
        #expect(decoded.scale == 2)
        #expect(decoded.image.width == 64)
        #expect(decoded.image.height == 48)
    }

    /// An effect inside the image with no tile, or with a tile rendered for an older value of it,
    /// fails the export instead of shipping what it should hide. An effect wholly outside the
    /// image needs no tile.
    @Test func missingOrStaleTileFailsClosed() {
        let base = makeImage()
        let effect = redact(CGRect(x: 8, y: 4, width: 10, height: 6))
        #expect(EditorFlattener.flatten(base: base, tiles: [], document: AnnotationDocument(annotations: [effect]),
                                        scale: 1) == nil)

        let stale = markedTile(for: effect, width: 10, height: 6)
        let moved = effect.moved(by: CGVector(dx: 4, dy: 0))
        #expect(EditorFlattener.flatten(base: base, tiles: [stale], document: AnnotationDocument(annotations: [moved]),
                                        scale: 1) == nil)

        let outside = redact(CGRect(x: 100, y: 100, width: 10, height: 10))
        #expect(EditorFlattener.flatten(base: base, tiles: [], document: AnnotationDocument(annotations: [outside]),
                                        scale: 1) != nil)
    }

    /// Text burns in with CoreText under a flipped text matrix: upright, a line height apart, and
    /// only inside its frame. "HI" has no descenders, so on each line the fully red pixels lie
    /// between the cap height and the baseline. Text drawn upside down would hang below the
    /// baseline instead, and a missing flip of the bitmap would put it near the bottom rows.
    @Test func flattenedTextInkInsideFrameOnly() throws {
        let base = makeImage()
        let original = try Bitmap(base)
        let box = TextBox(id: UUID(), string: "HI\nHI", origin: CGPoint(x: 6, y: 4), fontSize: 14, color: red)
        let frame = TextLayout.frame(for: box)
        try #require(frame.maxX < 64 && frame.maxY < 48)
        let output = try Bitmap(flatten(base, [.text(box)]))
        #expect(output.differences(from: original, excluding: [frame]) == 0)

        let capHeight = CTFontGetCapHeight(TextLayout.font(size: 14))
        let baselines = TextLayout.baselineOrigins(for: box).map(\.y)
        try #require(baselines.count == 2)
        var rowsPerLine: [Set<Int>] = [[], []]
        for y in 0..<48 {
            for x in 0..<64 where output[x, y] == Self.redPixel {
                let centre = CGFloat(y) + 0.5
                let line = baselines.firstIndex { centre > $0 - capHeight - 1 && centre < $0 + 1 }
                #expect(line != nil, "red at \(x), \(y) is on neither line")
                if let line { rowsPerLine[line].insert(y) }
            }
        }
        #expect(rowsPerLine[0].count >= 5)
        #expect(rowsPerLine[1].count >= 5)
    }
}
