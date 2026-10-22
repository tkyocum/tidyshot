import AVFoundation
let url = URL(fileURLWithPath: "out.mp4")
let gen = AVAssetImageGenerator(asset: AVURLAsset(url: url))
gen.appliesPreferredTrackTransform = true
gen.maximumSize = CGSize(width: 800, height: 800)
let t = Date()
let (image, actual) = try await gen.image(at: .zero)
print("thumb", image.width, image.height, "at", actual.seconds, "in", Int(Date().timeIntervalSince(t) * 1000), "ms")
let tracks = try await AVURLAsset(url: url).loadTracks(withMediaType: .video)
print("natural size", try await tracks[0].load(.naturalSize))
