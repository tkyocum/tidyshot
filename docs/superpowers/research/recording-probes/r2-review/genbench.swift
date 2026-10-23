import AVFoundation
setbuf(stdout, nil)
let url = URL(fileURLWithPath: CommandLine.arguments[1]); let fps = 15.0
let asset = AVURLAsset(url: url)
let duration = try await asset.load(.duration).seconds
let count = Int((duration * fps).rounded(.down))
let times = (0..<count).map { CMTime(seconds: Double($0) / fps, preferredTimescale: 600) }
func gen() -> AVAssetImageGenerator {
    let g = AVAssetImageGenerator(asset: asset); g.appliesPreferredTrackTransform = true
    g.requestedTimeToleranceBefore = .zero; g.requestedTimeToleranceAfter = .zero; return g
}
var t0 = Date(); let g1 = gen()
for t in times { _ = try await g1.image(at: t) }
print(String(format: "image(at:) x%d: %.2fs", count, Date().timeIntervalSince(t0)))
t0 = Date(); let g2 = gen(); var n = 0
for await r in g2.images(for: times) { _ = try r.image; n += 1 }
print(String(format: "images(for:) x%d: %.2fs", n, Date().timeIntervalSince(t0)))
