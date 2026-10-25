import AVFoundation
setbuf(stdout, nil)
// trim <in.mp4> <start> <end>
let src = URL(fileURLWithPath: CommandLine.arguments[1])
let start = Double(CommandLine.arguments[2])!, end = Double(CommandLine.arguments[3])!
let asset = AVURLAsset(url: src)
print("source", try await asset.load(.duration).seconds, "s", (try FileManager.default.attributesOfItem(atPath: src.path)[.size] as? Int ?? 0) / 1024, "KB")
for preset in [AVAssetExportPresetPassthrough, AVAssetExportPresetHighestQuality] {
    let out = URL(fileURLWithPath: "trim-\(preset == AVAssetExportPresetPassthrough ? "pass" : "hq").mp4")
    try? FileManager.default.removeItem(at: out)
    let session = AVAssetExportSession(asset: asset, presetName: preset)!
    session.timeRange = CMTimeRange(start: CMTime(seconds: start, preferredTimescale: 600), end: CMTime(seconds: end, preferredTimescale: 600))
    let t0 = Date()
    try await session.export(to: out, as: .mp4)
    let a = AVURLAsset(url: out)
    let d = try await a.load(.duration).seconds
    let tracks = try await a.load(.tracks).map(\.mediaType.rawValue)
    // first frame time vs asked start: compare first video frame against the source frame at `start`
    print(preset, String(format: "%.2fs export, duration %.3f (asked %.3f), %@, %d KB", Date().timeIntervalSince(t0), d, end - start, tracks.joined(separator: "+"), (try FileManager.default.attributesOfItem(atPath: out.path)[.size] as? Int ?? 0) / 1024))
}
