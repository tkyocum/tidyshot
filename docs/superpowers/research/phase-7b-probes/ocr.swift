import Vision
import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins

func makeImage(qr: String?, scale: CGFloat) -> CGImage {
    let w = 900 * scale, h = 500 * scale
    let ctx = CGContext(data: nil, width: Int(w), height: Int(h), bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.setFillColor(.white); ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
    let ns = NSGraphicsContext(cgContext: ctx, flipped: false)
    NSGraphicsContext.current = ns
    let font = NSFont.systemFont(ofSize: 15 * scale)
    let lines = ["Invoice 4471 — due 2026-11-03", "Total: $1,284.50   Ref: QX-993", "Column A        Column B", "left text       right text", "Ünïcödé café naïve"]
    for (i, l) in lines.enumerated() {
        (l as NSString).draw(at: CGPoint(x: 30 * scale, y: h - CGFloat(i + 1) * 40 * scale), withAttributes: [.font: font, .foregroundColor: NSColor.black])
    }
    if let qr {
        let f = CIFilter.qrCodeGenerator(); f.message = Data(qr.utf8); f.correctionLevel = "M"
        let img = f.outputImage!.transformed(by: .init(scaleX: 6 * scale, y: 6 * scale))
        let cg = CIContext().createCGImage(img, from: img.extent)!
        ctx.draw(cg, in: CGRect(x: w - CGFloat(cg.width) - 30 * scale, y: 30 * scale, width: CGFloat(cg.width), height: CGFloat(cg.height)))
    }
    NSGraphicsContext.current = nil
    return ctx.makeImage()!
}

for (qr, scale) in [(nil, 2.0), ("https://snap.tky.io/2BkqQ.png", 2.0), ("https://snap.tky.io/2BkqQ.png", 1.0)] as [(String?, CGFloat)] {
    let img = makeImage(qr: qr, scale: scale)
    var t = Date()
    var text = RecognizeTextRequest()
    text.recognitionLevel = .accurate
    text.usesLanguageCorrection = true
    text.automaticallyDetectsLanguage = true
    let obs = try await text.perform(on: img)
    print("scale \(scale) qr \(qr != nil) text \(String(format: "%.2f", Date().timeIntervalSince(t)))s, \(obs.count) obs")
    for o in obs { print("  ", o.topCandidates(1).first?.string ?? "-", o.boundingBox.cgRect) }
    t = Date()
    let bar = DetectBarcodesRequest()
    let b = try await bar.perform(on: img)
    print("  barcodes \(String(format: "%.2f", Date().timeIntervalSince(t)))s:", b.map { "\($0.symbology) \($0.payloadString ?? "nil") \($0.boundingBox.cgRect)" })
}
print(try RecognizeTextRequest().supportedRecognitionLanguages.prefix(40).map(\.maximalIdentifier))
