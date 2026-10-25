import Foundation
import ImageIO
import CoreGraphics
import UniformTypeIdentifiers
import Darwin
setbuf(stdout, nil)
func footprintMB() -> Double {
    var info = task_vm_info_data_t()
    var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
    let kr = withUnsafeMutablePointer(to: &info) { $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count) } }
    return kr == KERN_SUCCESS ? Double(info.phys_footprint) / 1_048_576 : -1
}
let args = CommandLine.arguments
let n = Int(args[1])!, fps = Double(args[2])!
let w = 1280, h = 832
let out = URL(fileURLWithPath: args[3])
let dest = CGImageDestinationCreateWithURL(out as CFURL, UTType.gif.identifier as CFString, n, nil)!
CGImageDestinationSetProperties(dest, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0, kCGImagePropertyGIFHasGlobalColorMap: false]] as CFDictionary)
let props = [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 1 / fps, kCGImagePropertyGIFUnclampedDelayTime: 1 / fps]] as CFDictionary
let space = CGColorSpace(name: CGColorSpace.sRGB)!
print("start", footprintMB())
let t0 = Date()
for i in 0..<n {
    autoreleasepool {
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        // Changing content: gradient stripes shifted per frame plus text-like noise.
        for y in stride(from: 0, to: h, by: 8) {
            ctx.setFillColor(CGColor(srgbRed: CGFloat((y + i * 7) % 256) / 255, green: CGFloat((y * 3 + i) % 256) / 255, blue: i < n / 2 ? 0 : 1, alpha: 1))
            ctx.fill(CGRect(x: (i * 5) % 64, y: y, width: w, height: 8))
        }
        for _ in 0..<400 { ctx.setFillColor(CGColor(gray: CGFloat.random(in: 0...1), alpha: 1)); ctx.fill(CGRect(x: Int.random(in: 0..<w), y: Int.random(in: 0..<h), width: 6, height: 10)) }
        CGImageDestinationAddImage(dest, ctx.makeImage()!, props)
    }
    if (i + 1) % max(1, n / 5) == 0 { print("added", i + 1, String(format: "%.0f MB", footprintMB()), String(format: "%.1fs", Date().timeIntervalSince(t0))) }
}
let t1 = Date()
let ok = CGImageDestinationFinalize(dest)
print("finalize", ok, String(format: "%.1fs", Date().timeIntervalSince(t1)), String(format: "%.0f MB after", footprintMB()))
let src = CGImageSourceCreateWithURL(out as CFURL, nil)!
let count = CGImageSourceGetCount(src)
var delays: [String] = []
for i in 0..<min(4, count) {
    let p = CGImageSourceCopyPropertiesAtIndex(src, i, nil) as! [CFString: Any]
    let g = p[kCGImagePropertyGIFDictionary] as! [CFString: Any]
    delays.append("\(g[kCGImagePropertyGIFDelayTime] ?? "-")/\(g[kCGImagePropertyGIFUnclampedDelayTime] ?? "-")")
}
print("frames", count, "delays", delays)
