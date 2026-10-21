import AppKit
import CoreGraphics
import CoreImage
import CoreImage.CIFilterBuiltins
import Testing
@testable import TidyShot

/// Real Vision on a generated image. The first text request after a restart can take about 24 s
/// while the system loads its model.
@Suite(.timeLimit(.minutes(2)))
struct TextRecognizerTests {
    private static let payload = "https://snap.tky.io/2BkqQ.png"

    /// Dark text on white at 2x, with a QR code at the bottom right when `qr` is given.
    private func makeImage(qr: String?, lines: [String]) throws -> CGImage {
        let scale: CGFloat = 2
        let w = 900 * scale, h = 500 * scale
        let ctx = try #require(CGContext(
            data: nil, width: Int(w), height: Int(h), bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        ctx.setFillColor(.white)
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
        let font = NSFont.systemFont(ofSize: 15 * scale)
        for (i, line) in lines.enumerated() {
            (line as NSString).draw(
                at: CGPoint(x: 30 * scale, y: h - CGFloat(i + 1) * 40 * scale),
                withAttributes: [.font: font, .foregroundColor: NSColor.black])
        }
        if let qr {
            let filter = CIFilter.qrCodeGenerator()
            filter.message = Data(qr.utf8)
            filter.correctionLevel = "M"
            let output = try #require(filter.outputImage).transformed(by: .init(scaleX: 6 * scale, y: 6 * scale))
            let code = try #require(CIContext().createCGImage(output, from: output.extent))
            ctx.draw(code, in: CGRect(
                x: w - CGFloat(code.width) - 30 * scale, y: 30 * scale,
                width: CGFloat(code.width), height: CGFloat(code.height)))
        }
        NSGraphicsContext.current = nil
        return try #require(ctx.makeImage())
    }

    @Test func readsTextAndAQRCode() async throws {
        let image = try makeImage(qr: Self.payload, lines: ["Invoice 4471 due soon", "Total: $1,284.50   Ref: QX-993"])
        let scan = try await TextRecognizer().recognize(image)

        let joined = TextJoiner.join(scan.pieces)
        #expect(joined.contains("Invoice 4471"))
        #expect(joined.contains("QX-993"))
        #expect(scan.codes.count == 1)
        #expect(scan.codes.first?.payload == Self.payload)
        #expect(scan.codes.first?.symbology == .qr)
        for piece in scan.pieces {
            #expect(CGRect(x: 0, y: 0, width: 1, height: 1).insetBy(dx: -0.01, dy: -0.01).contains(piece.box))
        }
    }

    @Test func readsTextWithoutACode() async throws {
        let image = try makeImage(qr: nil, lines: ["Plain words only"])
        let scan = try await TextRecognizer().recognize(image)
        #expect(TextJoiner.join(scan.pieces).contains("Plain words"))
        #expect(scan.codes.isEmpty)
    }

    @Test func aBlankImageFindsNothing() async throws {
        let image = try makeImage(qr: nil, lines: [])
        let scan = try await TextRecognizer().recognize(image)
        #expect(scan.pieces.isEmpty)
        #expect(scan.codes.isEmpty)
    }
}
