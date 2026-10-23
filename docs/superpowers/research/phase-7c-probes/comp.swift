import CoreGraphics
import Foundation
import ImageIO
func ms(_ s: Date) -> Int { Int(Date().timeIntervalSince(s) * 1000) }
let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!
func content(_ w: Int, _ h: Int) -> CGImage {
    let c = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: sRGB, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    c.setFillColor(CGColor(srgbRed: 0.95, green: 0.95, blue: 0.97, alpha: 1)); c.fill(CGRect(x: 0, y: 0, width: w, height: h))
    c.setFillColor(CGColor(srgbRed: 0.2, green: 0.3, blue: 0.8, alpha: 1)); c.fill(CGRect(x: 40, y: 40, width: w / 3, height: h / 4))
    return c.makeImage()!
}
func compose(_ img: CGImage, pad: Int, radius: CGFloat, blur: CGFloat, offset: CGFloat) -> CGImage {
    let W = img.width + 2 * pad, H = img.height + 2 * pad
    let c = CGContext(data: nil, width: W, height: H, bitsPerComponent: 8, bytesPerRow: 0, space: sRGB, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    let g = CGGradient(colorsSpace: sRGB, colors: [CGColor(srgbRed: 0.98, green: 0.45, blue: 0.4, alpha: 1), CGColor(srgbRed: 0.45, green: 0.3, blue: 0.95, alpha: 1)] as CFArray, locations: [0, 1])!
    c.drawLinearGradient(g, start: .zero, end: CGPoint(x: W, y: H), options: [])
    let r = CGRect(x: pad, y: pad, width: img.width, height: img.height)
    let path = CGPath(roundedRect: r, cornerWidth: radius, cornerHeight: radius, transform: nil)
    c.saveGState()
    c.setShadow(offset: CGSize(width: 0, height: -offset), blur: blur, color: CGColor(gray: 0, alpha: 0.35))
    c.beginTransparencyLayer(auxiliaryInfo: nil)
    c.addPath(path); c.clip()
    c.draw(img, in: r)
    c.endTransparencyLayer()
    c.restoreGState()
    return c.makeImage()!
}
for (w, h) in [(1600, 1000), (5120, 2880), (3094, 16000), (3094, 65536)] {
    let img = content(w, h)
    let s = Date()
    let out = compose(img, pad: 128, radius: 20, blur: 48, offset: 16)
    print("\(w)x\(h): \(ms(s)) ms -> \(out.width)x\(out.height)")
    if w == 1600 {
        let d = CGImageDestinationCreateWithURL(URL(fileURLWithPath: "comp.png") as CFURL, "public.png" as CFString, 1, nil)!
        CGImageDestinationAddImage(d, out, nil); CGImageDestinationFinalize(d)
    }
}
