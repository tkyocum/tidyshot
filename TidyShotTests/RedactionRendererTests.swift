import CoreGraphics
import CoreImage
import Foundation
import Metal
import Testing
@testable import TidyShot

/// Synthetic 64x64 images through the real Core Image renderer. Expected values are computed in
/// the same run, never read from golden files.
struct RedactionRendererTests {
    let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!
    let size = CGSize(width: 64, height: 64)
    let black = RGBA(red: 0, green: 0, blue: 0, alpha: 1)

    /// RGBA bytes read back through an sRGB premultipliedLast buffer. Row 0 is the image's top row,
    /// so `pixel(x, y)` uses the model's top-left convention.
    struct Pixels {
        let width: Int
        let height: Int
        let bytes: [UInt8]

        init(_ image: CGImage) {
            width = image.width
            height = image.height
            var buffer = [UInt8](repeating: 0, count: image.width * image.height * 4)
            buffer.withUnsafeMutableBytes { raw in
                let context = CGContext(data: raw.baseAddress, width: image.width, height: image.height,
                                        bitsPerComponent: 8, bytesPerRow: image.width * 4,
                                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
                context.interpolationQuality = .none
                context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            }
            bytes = buffer
        }

        func pixel(_ x: Int, _ y: Int) -> [UInt8] {
            let index = (y * width + x) * 4
            return Array(bytes[index..<index + 4])
        }
    }

    /// Every (x, y) in the two ranges, rows first.
    func grid(_ xs: Range<Int>, _ ys: Range<Int>) -> [(x: Int, y: Int)] {
        ys.flatMap { y in xs.map { (x: $0, y: y) } }
    }

    /// A 64x64 sRGB image; `paint` returns the RGBA bytes for each top-left pixel position.
    func image(_ paint: (Int, Int) -> [UInt8]) -> CGImage {
        var bytes: [UInt8] = []
        for y in 0..<64 {
            for x in 0..<64 {
                bytes += paint(x, y)
            }
        }
        return CGImage(width: 64, height: 64, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: 64 * 4, space: sRGB,
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: CGDataProvider(data: Data(bytes) as CFData)!, decode: nil,
                       shouldInterpolate: false, intent: .defaultIntent)!
    }

    /// Neighbouring pixels all differ, and no channel is 0 or 255.
    func noise() -> CGImage {
        image { x, y in
            [UInt8(20 + (x * 37 + y * 11) % 200), UInt8(20 + (x * 13 + y * 29) % 200), UInt8(20 + (x * 7 + y * 41) % 200), 255]
        }
    }

    func region(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat) -> Region {
        Region(id: UUID(), rect: CGRect(x: x, y: y, width: width, height: height))
    }

    @Test func solidTileIsFillColourOpaque() async throws {
        let renderer = RedactionRenderer()
        let base = noise()
        // A fractional rect rounds out to whole pixels, and a translucent fill still paints opaque
        // pixels: a see-through redaction would hide nothing.
        let effect = Annotation.redact(region(4.4, 6.6, 20.2, 10.1), fill: RGBA(red: 1, green: 0.5, blue: 0, alpha: 0.4))
        #expect(EffectTile.rect(for: effect, imageSize: size) == CGRect(x: 4, y: 6, width: 21, height: 11))
        let tile = try #require(await renderer.tile(for: effect, over: base, beneath: []))
        #expect(tile.width == 21 && tile.height == 11)
        #expect(tile.colorSpace?.name == CGColorSpace.sRGB)
        let pixels = Pixels(tile)
        let wrong = grid(0..<21, 0..<11).filter { point in
            let pixel = pixels.pixel(point.x, point.y)
            return !(pixel[0] == 255 && abs(Int(pixel[1]) - 128) <= 1 && pixel[2] == 0 && pixel[3] == 255)
        }
        #expect(wrong.isEmpty, "not the fill at \(wrong.prefix(3))")

        // The tile takes the base's colour space, and clearing the caches leaves the renderer usable.
        let p3 = try #require(base.copy(colorSpace: CGColorSpace(name: CGColorSpace.displayP3)!))
        let p3Tile = try #require(await renderer.tile(for: effect, over: p3, beneath: []))
        #expect(p3Tile.colorSpace?.name == CGColorSpace.displayP3)
        await renderer.clearCaches()
        #expect(Pixels(try #require(await renderer.tile(for: effect, over: base, beneath: []))).bytes == pixels.bytes)
    }

    @Test func blurTileEqualsFullImageBlurCrop() async throws {
        let renderer = RedactionRenderer()
        let base = noise()
        // The rect touches the image's left edge, where the blur reads clamped edge pixels.
        let rect = CGRect(x: 0, y: 8, width: 28, height: 40)
        let tile = try #require(await renderer.tile(for: .blur(Region(id: UUID(), rect: rect), radius: 3), over: base, beneath: []))

        // The whole image blurred in a separate context, then cropped with CGImage's own top-left
        // convention, so a flipped tile cannot pass.
        let context = MTLCreateSystemDefaultDevice().map { CIContext(mtlDevice: $0) } ?? CIContext()
        let input = CIImage(cgImage: base)
        let blurred = input.clampedToExtent().applyingGaussianBlur(sigma: 3).cropped(to: input.extent)
        let whole = try #require(context.createCGImage(blurred, from: input.extent, format: .RGBA8, colorSpace: sRGB))
        let expected = Pixels(try #require(whole.cropping(to: rect)))

        let actual = Pixels(tile)
        #expect(actual.width == 28 && actual.height == 40)
        let maxDiff = zip(actual.bytes, expected.bytes).map { abs(Int($0) - Int($1)) }.max() ?? 0
        #expect(maxDiff <= 1)
        #expect(actual.bytes != Pixels(try #require(base.cropping(to: rect))).bytes)
    }

    @Test func mosaicBlocksUniform() async throws {
        let renderer = RedactionRenderer()
        let base = noise()
        // A 10 px block over a region that is not on the grid: the grid starts at image pixel
        // (0,0), so the region's 30x22 pixels fall in 4x3 blocks.
        let effect = Annotation.pixelate(region(5, 3, 30, 22), block: 10)
        let pixels = Pixels(try #require(await renderer.tile(for: effect, over: base, beneath: [])))
        #expect(pixels.width == 30 && pixels.height == 22)
        var blocks: [[Int]: [UInt8]] = [:]
        var mixed: [(x: Int, y: Int)] = []
        for point in grid(0..<30, 0..<22) {
            let key = [(point.x + 5) / 10, (point.y + 3) / 10]
            let pixel = pixels.pixel(point.x, point.y)
            if let first = blocks[key], first != pixel {
                mixed.append(point)
            } else {
                blocks[key] = pixel
            }
        }
        #expect(mixed.isEmpty, "not uniform at \(mixed.prefix(3))")
        #expect(blocks.count == 12)
        #expect(Set(blocks.values).count > 1)
        #expect(pixels.bytes != Pixels(try #require(base.cropping(to: CGRect(x: 5, y: 3, width: 30, height: 22)))).bytes)
    }

    @Test func mosaicGridStableWhenRegionMoves() async throws {
        let renderer = RedactionRenderer()
        let base = noise()
        // 8 px is a power of two, so Core Image's high-quality downsample averages each block
        // from its own pixels only.
        let first = Pixels(try #require(await renderer.tile(for: .pixelate(region(5, 3, 30, 22), block: 8), over: base, beneath: [])))
        let moved = Pixels(try #require(await renderer.tile(for: .pixelate(region(9, 7, 30, 22), block: 8), over: base, beneath: [])))
        // Image pixels 9..<35 by 7..<25 are in both tiles.
        let changed = grid(9..<35, 7..<25).filter { first.pixel($0.x - 5, $0.y - 3) != moved.pixel($0.x - 9, $0.y - 7) }
        #expect(changed.isEmpty, "changed when the region moved: \(changed.prefix(3))")
    }

    @Test func mosaicAveragesHalfWhiteBlock() async throws {
        let renderer = RedactionRenderer()
        // The left half of every 8 px block is white and the right half black.
        let halves = image { x, _ in x % 8 < 4 ? [255, 255, 255, 255] : [0, 0, 0, 255] }
        let pixels = Pixels(try #require(await renderer.tile(for: .pixelate(region(16, 16, 16, 16), block: 8), over: halves, beneath: [])))
        // Averaged in linear light: half of white is sRGB 0.735, about 188. CIPixellate would give 0 or 255.
        let wrong = grid(0..<16, 0..<16).filter { point in
            let pixel = pixels.pixel(point.x, point.y)
            return !(abs(Int(pixel[0]) - 188) <= 3 && pixel[0] == pixel[1] && pixel[1] == pixel[2] && pixel[3] == 255)
        }
        #expect(wrong.isEmpty, "not mid grey at \(wrong.prefix(3)): \(pixels.pixel(0, 0))")
    }

    @Test func tileNilOutsideImage() async throws {
        let renderer = RedactionRenderer()
        let base = noise()
        #expect(await renderer.tile(for: .redact(region(70, 70, 10, 10), fill: black), over: base, beneath: []) == nil)
        #expect(await renderer.tile(for: .blur(region(-20, 10, 10, 10), radius: 4), over: base, beneath: []) == nil)
        #expect(await renderer.tile(for: .pixelate(region(10, 64, 20, 5), block: 8), over: base, beneath: []) == nil)
        let arrow = Annotation.arrow(Segment(id: UUID(), from: .zero, to: CGPoint(x: 30, y: 30), color: black, lineWidth: 4))
        #expect(await renderer.tile(for: arrow, over: base, beneath: []) == nil)
        // A region partly outside keeps only its pixels inside the image.
        let partial = try #require(await renderer.tile(for: .redact(region(-5, -5, 10, 10), fill: black), over: base, beneath: []))
        #expect(partial.width == 5 && partial.height == 5)
    }

    @Test func alphaZeroCornerStaysZero() async throws {
        let renderer = RedactionRenderer()
        // A window capture: the top-left 16x16 corner is fully transparent.
        let base = image { x, y in x < 16 && y < 16 ? [0, 0, 0, 0] : [200, 120, 40, 255] }
        let corner = region(0, 0, 32, 32)
        let blur = Pixels(try #require(await renderer.tile(for: .blur(corner, radius: 1), over: base, beneath: [])))
        let mosaic = Pixels(try #require(await renderer.tile(for: .pixelate(corner, block: 8), over: base, beneath: [])))
        let redact = Pixels(try #require(await renderer.tile(for: .redact(corner, fill: black), over: base, beneath: [])))
        #expect(grid(0..<8, 0..<8).allSatisfy { blur.pixel($0.x, $0.y)[3] == 0 })
        #expect(grid(0..<16, 0..<16).allSatisfy { mosaic.pixel($0.x, $0.y)[3] == 0 })
        #expect(mosaic.pixel(20, 20)[3] == 255)
        // Blocks cut by the image's right and bottom edges stay opaque: nothing outside the image is
        // averaged in, so the tile never lets the pixels it covers show through.
        let edge = Pixels(try #require(await renderer.tile(for: .pixelate(region(40, 40, 24, 24), block: 10), over: base, beneath: [])))
        #expect(grid(0..<24, 0..<24).allSatisfy { edge.pixel($0.x, $0.y)[3] == 255 })
        // A solid redaction over the transparent corner paints opaque pixels.
        #expect(grid(0..<16, 0..<16).allSatisfy { redact.pixel($0.x, $0.y) == [0, 0, 0, 255] })
    }

    @Test func blurOverEarlierRedactBlursBlack() async throws {
        let renderer = RedactionRenderer()
        let base = noise()
        let redact = Annotation.redact(region(16, 16, 32, 32), fill: black)
        let blur = Annotation.blur(region(8, 8, 48, 48), radius: 2)
        let redactTile = try #require(await renderer.tile(for: redact, over: base, beneath: []))
        let tile = Pixels(try #require(await renderer.tile(for: blur, over: base, beneath: [EffectTile(effect: redact, image: redactTile)])))
        let source = Pixels(base)
        // Image pixels 16..<48 are under the redaction; the blur tile starts at image pixel 8.
        let survived = grid(16..<48, 16..<48).filter { tile.pixel($0.x - 8, $0.y - 8)[0..<3] == source.pixel($0.x, $0.y)[0..<3] }
        #expect(survived.isEmpty, "source value survived at \(survived.prefix(3))")
        // Three sigma inside the redaction there is only black to blur.
        #expect(grid(22..<42, 22..<42).allSatisfy { tile.pixel($0.x - 8, $0.y - 8)[0..<3].allSatisfy { $0 <= 1 } })
    }

    @Test func blurNextToRedactSamplesRedactInMargin() async throws {
        let renderer = RedactionRenderer()
        // White, with a red secret where the redaction goes.
        let base = image { x, y in (40..<56).contains(x) && (16..<48).contains(y) ? [255, 0, 0, 255] : [255, 255, 255, 255] }
        let redact = Annotation.redact(region(40, 16, 16, 32), fill: black)
        let blur = Annotation.blur(region(8, 16, 28, 32), radius: 4)
        // The rects do not meet, but the blur's margin reaches the redaction, so the tile cache
        // passes the redaction as beneath.
        #expect(!CGRect(x: 8, y: 16, width: 28, height: 32).intersects(CGRect(x: 40, y: 16, width: 16, height: 32)))
        #expect(EffectGeometry.sampleRect(of: blur, imageSize: size).intersects(CGRect(x: 40, y: 16, width: 16, height: 32)))
        let redactTile = try #require(await renderer.tile(for: redact, over: base, beneath: []))
        let covered = Pixels(try #require(await renderer.tile(for: blur, over: base, beneath: [EffectTile(effect: redact, image: redactTile)])))
        let uncovered = Pixels(try #require(await renderer.tile(for: blur, over: base, beneath: [])))
        // The tile's right column (image x 35) is 5 px from the redaction. Without beneath the red
        // secret bleeds in; with it the margin darkens to grey and carries no red.
        let edge = (4..<28).map { (secret: uncovered.pixel(27, $0), pixel: covered.pixel(27, $0)) }
        #expect(edge.allSatisfy { Int($0.secret[0]) - Int($0.secret[1]) > 10 })
        #expect(edge.allSatisfy { abs(Int($0.pixel[0]) - Int($0.pixel[1])) <= 1 && abs(Int($0.pixel[1]) - Int($0.pixel[2])) <= 1 })
        #expect(edge.allSatisfy { $0.pixel[1] < 250 })
    }

    @Test func pixelateOverEarlierRedactAveragesFill() async throws {
        let renderer = RedactionRenderer()
        let base = noise()
        let redact = Annotation.redact(region(16, 16, 32, 32), fill: black)
        let pixelate = Annotation.pixelate(region(8, 8, 48, 48), block: 8)
        let redactTile = try #require(await renderer.tile(for: redact, over: base, beneath: []))
        let tile = Pixels(try #require(await renderer.tile(for: pixelate, over: base, beneath: [EffectTile(effect: redact, image: redactTile)])))
        let source = Pixels(base)
        // Image pixels 16..<48 are under the redaction, and the 8 px blocks there lie wholly inside
        // it, so each averages only black. The pixelate tile starts at image pixel 8.
        let notBlack = grid(16..<48, 16..<48).filter { tile.pixel($0.x - 8, $0.y - 8) != [0, 0, 0, 255] }
        #expect(notBlack.isEmpty, "not black at \(notBlack.prefix(3))")
        let survived = grid(16..<48, 16..<48).filter { tile.pixel($0.x - 8, $0.y - 8)[0..<3] == source.pixel($0.x, $0.y)[0..<3] }
        #expect(survived.isEmpty, "source value survived at \(survived.prefix(3))")
    }

    /// Core Image takes a base taller than any GPU texture (16 x 40,000, red above row 39,000 and
    /// blue from it) and renders a region near either end from the right rows.
    @Test func tilesRenderOverABaseTallerThanATexture() async throws {
        let renderer = RedactionRenderer()
        let width = 16
        let height = 40_000
        var bytes = [UInt8](repeating: 255, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let index = (y * width + x) * 4
                bytes[index] = y < 39_000 ? 255 : 0
                bytes[index + 1] = 0
                bytes[index + 2] = y < 39_000 ? 0 : 255
            }
        }
        let base = try #require(CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                                        bytesPerRow: width * 4, space: sRGB,
                                        bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                                        provider: CGDataProvider(data: Data(bytes) as CFData)!, decode: nil,
                                        shouldInterpolate: false, intent: .defaultIntent))
        let size = CGSize(width: width, height: height)
        for (effect, expected) in [(Annotation.blur(region(0, 39_900, 16, 90), radius: 4), [UInt8(0), 0, 255, 255]),
                                   (.pixelate(region(0, 39_500, 16, 64), block: 8), [0, 0, 255, 255]),
                                   (.blur(region(0, 100, 16, 90), radius: 4), [255, 0, 0, 255]),
                                   (.pixelate(region(0, 16_360, 16, 48), block: 8), [255, 0, 0, 255])] {
            let tile = Pixels(try #require(await renderer.tile(for: effect, over: base, beneath: [])))
            let rect = try #require(EffectTile.rect(for: effect, imageSize: size))
            #expect(tile.width == Int(rect.width) && tile.height == Int(rect.height))
            let wrong = grid(0..<tile.width, 0..<tile.height).filter { point in
                zip(tile.pixel(point.x, point.y), expected).contains { abs(Int($0) - Int($1)) > 1 }
            }
            #expect(wrong.isEmpty, "\(effect): not \(expected) at \(wrong.prefix(3))")
        }
    }
}
