import AVFoundation
let asset = AVURLAsset(url: URL(fileURLWithPath: CommandLine.arguments[1]))
let times = (0..<150).map { CMTime(seconds: Double($0) / 15, preferredTimescale: 600) }
let g = AVAssetImageGenerator(asset: asset); g.requestedTimeToleranceBefore = .zero; g.requestedTimeToleranceAfter = .zero
var last = -1.0, inOrder = true, n = 0, maxErr = 0.0
for await r in g.images(for: times) { let t = r.requestedTime.seconds; if t < last { inOrder = false }; last = t; n += 1; if let a = try? r.actualTime { maxErr = max(maxErr, abs(a.seconds - t)) } }
print("results", n, "in order", inOrder, "max |actual-requested|", maxErr)
