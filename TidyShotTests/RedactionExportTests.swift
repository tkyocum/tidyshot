import CoreGraphics
import Foundation
import Testing
@testable import TidyShot

/// The automated proof that redaction leaves no secret pixel. The real RedactionRenderer (a fresh
/// instance, not `.shared`) runs through EditorModel.renderExport, ImageEncoder.pngData and
/// ImageEncoder.decode, and the decoded bytes are checked. Every expected value is computed in
/// the same run; there are no golden files.
struct RedactionExportTests {
    static let width = 64
    static let height = 48

    /// The source pixels, RGBA, top row first: a fixed-seed xorshift stream, opaque, every colour
    /// channel in 16...239, so no pixel equals the black fill.
    let source: [UInt8]
    let model: EditorModel

    init() {
        var state: UInt32 = 0x9E37_79B9
        var bytes = [UInt8](repeating: 255, count: Self.width * Self.height * 4)
        for index in stride(from: 0, to: bytes.count, by: 4) {
            for channel in 0..<3 {
                state ^= state << 13
                state ^= state >> 17
                state ^= state << 5
                bytes[index + channel] = UInt8(16 + state % 224)
            }
        }
        source = bytes
        let image = CGImage(width: Self.width, height: Self.height, bitsPerComponent: 8, bitsPerPixel: 32,
                            bytesPerRow: Self.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                            provider: CGDataProvider(data: Data(bytes) as CFData)!, decode: nil,
                            shouldInterpolate: false, intent: .defaultIntent)!
        model = EditorModel(recordID: UUID(), image: ScaledImage(image: image, scale: 2),
                            renderer: RedactionRenderer(), defaults: .standard)
    }

    /// Adds what `tool` makes for a drag from `from` to `to`, as the tools do.
    @discardableResult
    func add(_ tool: EditorTool, from: CGPoint, to: CGPoint) throws -> Annotation {
        let annotation = try #require(model.makeAnnotation(tool, from: from, to: to))
        model.commit(model.document.appending(annotation), actionName: "Add")
        return annotation
    }

    /// Exports, encodes and decodes as Save and Copy do. The bytes are RGBA, top row first.
    func exportedPixels() async throws -> (scale: CGFloat, width: Int, height: Int, bytes: [UInt8]) {
        let export = try await model.renderExport()
        let png = try ImageEncoder.pngData(from: export.image, scale: export.scale)
        let decoded = try #require(ImageEncoder.decode(png))
        let bytes = try rgba(of: decoded.image)
        return (decoded.scale, decoded.image.width, decoded.image.height, bytes)
    }

    /// `image` drawn 1:1 into an RGBA buffer in its own colour space, so no value is converted.
    func rgba(of image: CGImage) throws -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let space = image.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!
        let drawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: image.width, height: image.height,
                                          bitsPerComponent: 8, bytesPerRow: image.width * 4, space: space,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.interpolationQuality = .none
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            return true
        }
        try #require(drawn)
        return bytes
    }

    func pixel(_ bytes: [UInt8], _ x: Int, _ y: Int, width: Int = RedactionExportTests.width) -> [UInt8] {
        let index = (y * width + x) * 4
        return Array(bytes[index..<index + 4])
    }

    /// Every pixel position inside `rect` (image pixels, top-left origin).
    func positions(in rect: CGRect) -> [(x: Int, y: Int)] {
        (Int(rect.minY)..<Int(rect.maxY)).flatMap { y in
            (Int(rect.minX)..<Int(rect.maxX)).map { (x: $0, y: y) }
        }
    }

    func rect(of effect: Annotation) throws -> CGRect {
        try #require(effect.effectRect)
    }

    @Test func redactRegionHoldsOnlyFillAfterPNGRoundTrip() async throws {
        let secret = try add(.redact, from: CGPoint(x: 8, y: 8), to: CGPoint(x: 40, y: 32))
        let fill = model.redactColor
        let expected = [fill.red, fill.green, fill.blue, fill.alpha].map { UInt8(($0 * 255).rounded()) }
        let inside = positions(in: try rect(of: secret))
        // The fixture means something: no source pixel already equals the fill.
        #expect(!inside.contains { pixel(source, $0.x, $0.y) == expected })

        let exported = try await exportedPixels()
        let wrong = inside.filter { pixel(exported.bytes, $0.x, $0.y) != expected }
        #expect(wrong.isEmpty, "\(wrong.count) of \(inside.count) pixels are not the fill")
    }

    @Test func blurOverRedactLeaksNoSourcePixel() async throws {
        // Sigma 8 px, so the middle of a 48x32 redaction lies 1.75 sigma or more inside it.
        model.blurRadiusPoints = 4
        let secret = try add(.redact, from: CGPoint(x: 8, y: 8), to: CGPoint(x: 56, y: 40))
        try add(.blur, from: .zero, to: CGPoint(x: Self.width, y: Self.height))
        let exported = try await exportedPixels()

        let inside = positions(in: try rect(of: secret))
        let leaked = inside.filter { pixel(exported.bytes, $0.x, $0.y) == pixel(source, $0.x, $0.y) }
        #expect(leaked.isEmpty, "\(leaked.count) pixels inside the redaction kept their source value")

        // The blur sampled the fill, not the secret, so the middle stays dark. Blurring the source
        // instead would give its mean, about 128 or more in every channel.
        let middle = positions(in: CGRect(x: 30, y: 22, width: 4, height: 4))
        let bright = middle.filter { pixel(exported.bytes, $0.x, $0.y).prefix(3).contains { $0 > 96 } }
        #expect(bright.isEmpty, "\(bright.count) middle pixels look like the blurred secret")
    }

    @Test func pixelateRegionIsBlockUniformAndDiffersFromSource() async throws {
        model.blockPoints = 6
        let mosaic = try add(.pixelate, from: CGPoint(x: 12, y: 12), to: CGPoint(x: 48, y: 36))
        guard case .pixelate(let region, let block) = mosaic else {
            Issue.record("not a pixelate")
            return
        }
        // 6 pt at 2x. The grid is anchored to image pixel (0,0), so the region holds 3 x 2 whole blocks.
        #expect(block == 12)
        try #require(block >= 1)
        let side = Int(block)
        let exported = try await exportedPixels()

        let cells = Dictionary(grouping: positions(in: region.rect)) { [$0.x / side, $0.y / side] }
        #expect(cells.count == 6)
        for (cell, members) in cells {
            let values = Set(members.map { pixel(exported.bytes, $0.x, $0.y) })
            #expect(values.count == 1, "block \(cell) holds \(values.count) values")
            #expect(members.contains { pixel(exported.bytes, $0.x, $0.y) != pixel(source, $0.x, $0.y) },
                    "block \(cell) equals the source")
        }
    }

    @Test func blurRegionDiffersFromSource() async throws {
        let blur = try add(.blur, from: CGPoint(x: 8, y: 8), to: CGPoint(x: 40, y: 32))
        let exported = try await exportedPixels()
        let inside = positions(in: try rect(of: blur))
        let kept = inside.filter { pixel(exported.bytes, $0.x, $0.y) == pixel(source, $0.x, $0.y) }
        #expect(kept.count * 100 <= inside.count, "\(kept.count) of \(inside.count) pixels kept their source value")
    }

    @Test func outsideEffectsEqualBaseAndScaleIsTwo() async throws {
        model.blockPoints = 6
        let effects = try [
            add(.redact, from: CGPoint(x: 2, y: 2), to: CGPoint(x: 14, y: 12)),
            add(.blur, from: CGPoint(x: 20, y: 4), to: CGPoint(x: 36, y: 20)),
            add(.pixelate, from: CGPoint(x: 36, y: 24), to: CGPoint(x: 60, y: 48)),
        ]
        let rects = try effects.map { try rect(of: $0) }
        let exported = try await exportedPixels()
        #expect(exported.scale == 2)
        #expect(exported.width == Self.width)
        #expect(exported.height == Self.height)

        let outside = positions(in: CGRect(x: 0, y: 0, width: Self.width, height: Self.height)).filter { position in
            let centre = CGPoint(x: CGFloat(position.x) + 0.5, y: CGFloat(position.y) + 0.5)
            return !rects.contains { $0.contains(centre) }
        }
        #expect(outside.count > Self.width * Self.height / 2)
        let changed = outside.filter { pixel(exported.bytes, $0.x, $0.y) != pixel(source, $0.x, $0.y) }
        #expect(changed.isEmpty, "\(changed.count) pixels outside every effect changed")
    }

    /// The crop is applied after every effect, through the real renderer and a PNG round trip.
    /// A redaction cut by the crop's edge holds only the fill, every other kept pixel is the
    /// source at the crop's offset, and the PNG has the crop's size at scale 2: the size Save
    /// records as pixelWidth and pixelHeight.
    @Test func croppedExportKeepsRedactionAndHasCropSize() async throws {
        let secret = try add(.redact, from: CGPoint(x: 8, y: 8), to: CGPoint(x: 40, y: 32))
        let crop = CGRect(x: 20, y: 4, width: 36, height: 30)
        model.commit(model.document.withCrop(crop), actionName: EditorModel.ActionName.crop)
        let fill = model.redactColor
        let expected = [fill.red, fill.green, fill.blue, fill.alpha].map { UInt8(($0 * 255).rounded()) }

        let exported = try await exportedPixels()
        #expect(exported.scale == 2)
        #expect(exported.width == 36)
        #expect(exported.height == 30)

        let secretRect = try rect(of: secret)
        var redacted = 0
        var wrong = 0
        for position in positions(in: CGRect(origin: .zero, size: crop.size)) {
            let x = position.x + Int(crop.minX)
            let y = position.y + Int(crop.minY)
            let inside = secretRect.contains(CGPoint(x: CGFloat(x) + 0.5, y: CGFloat(y) + 0.5))
            if inside { redacted += 1 }
            let want = inside ? expected : pixel(source, x, y)
            if pixel(exported.bytes, position.x, position.y, width: exported.width) != want { wrong += 1 }
        }
        // The crop keeps 20 of the redaction's 32 columns and all 24 of its rows.
        #expect(redacted == 20 * 24)
        #expect(wrong == 0, "\(wrong) kept pixels are neither the fill inside the redaction nor the source outside it")
    }
}
