import AVFoundation
let a = AVURLAsset(url: URL(fileURLWithPath: CommandLine.arguments[1]))
do { let (p, d, t) = try await a.load(.isPlayable, .duration, .tracks); print("playable", p, "duration", d.seconds, "tracks", t.map(\.mediaType.rawValue)) } catch { print("error", error.localizedDescription) }
