import AVFoundation
import ImageIO
import UniformTypeIdentifiers
import CoreGraphics
setbuf(stdout, nil)
// togif <in.mp4> <out.gif> <fps> <maxSide>
let args = CommandLine.arguments
let src = URL(fileURLWithPath: args[1]), dst = URL(fileURLWithPath: args[2])
let fps = Double(args[3])!, maxSide = CGFloat(Double(args[4])!)
let asset = AVURLAsset(url: src)
let duration = try await asset.load(.duration).seconds
let track = try await asset.loadTracks(withMediaType: .video)[0]
let natural = try await track.load(.naturalSize)
let scale = min(1, maxSide / max(natural.width, natural.height))
let outSize = CGSize(width: (natural.width * scale).rounded(), height: (natural.height * scale).rounded())
let gen = AVAssetImageGenerator(asset: asset)
gen.appliesPreferredTrackTransform = true
gen.requestedTimeToleranceBefore = .zero; gen.requestedTimeToleranceAfter = .zero
let count = Int((duration * fps).rounded(.down))
let dest = CGImageDestinationCreateWithURL(dst as CFURL, UTType.gif.identifier as CFString, count, nil)!
CGImageDestinationSetProperties(dest, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
let frameProps = [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 1 / fps, kCGImagePropertyGIFUnclampedDelayTime: 1 / fps]] as CFDictionary
let t0 = Date()
let space = CGColorSpace(name: CGColorSpace.sRGB)!
for i in 0..<count {
    let (frame, _) = try await gen.image(at: CMTime(seconds: Double(i) / fps, preferredTimescale: 600))
    // High-quality downscale ourselves (the generator's maximumSize uses a faster filter).
    let ctx = CGContext(data: nil, width: Int(outSize.width), height: Int(outSize.height), bitsPerComponent: 8, bytesPerRow: 0, space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    ctx.interpolationQuality = .high
    ctx.draw(frame, in: CGRect(origin: .zero, size: outSize))
    CGImageDestinationAddImage(dest, ctx.makeImage()!, frameProps)
    if i == count / 2 { let d = CGImageDestinationCreateWithURL(URL(fileURLWithPath: dst.path + ".mid.png") as CFURL, UTType.png.identifier as CFString, 1, nil)!; CGImageDestinationAddImage(d, ctx.makeImage()!, nil); CGImageDestinationFinalize(d) }
}
guard CGImageDestinationFinalize(dest) else { print("finalize failed"); exit(1) }
let bytes = (try FileManager.default.attributesOfItem(atPath: dst.path)[.size] as? Int) ?? 0
print(String(format: "%@: %d frames %dx%d from %dx%d, %.1fs encode, %d KB (mp4 %d KB)", dst.lastPathComponent, count, Int(outSize.width), Int(outSize.height), Int(natural.width), Int(natural.height), Date().timeIntervalSince(t0), bytes / 1024, ((try FileManager.default.attributesOfItem(atPath: src.path)[.size] as? Int) ?? 0) / 1024))
