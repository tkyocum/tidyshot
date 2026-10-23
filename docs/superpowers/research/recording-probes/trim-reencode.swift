import AVFoundation
setbuf(stdout, nil)
// trim-reencode <in.mp4> <start> [output folder]
// The trim probe (R2 design, Still to probe): the video track's sync samples from AVSampleCursor,
// then a passthrough, a HighestQuality and a HighestQuality-with-video-composition export from
// <start> to the end, each with its time, size and fractionCompleted readings, and what each output
// keeps before the start in decode order (which ignores the edit list): video samples, and for
// audio the packets and sample frames.
let args = CommandLine.arguments
guard args.count >= 3, let startSeconds = Double(args[2]) else {
    print("usage: trim-reencode <in.mp4> <start seconds> [output folder]")
    exit(2)
}
let src = URL(fileURLWithPath: args[1])
let outFolder = URL(fileURLWithPath: args.count > 3 ? args[3] : ".", isDirectory: true)
let start = CMTime(seconds: startSeconds, preferredTimescale: 600)

func size(_ url: URL) -> Int { (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0 }
func f(_ t: CMTime) -> String { t.isNumeric ? String(format: "%.3f", t.seconds) : "\(t)" }

/// Each segment as target start → media start, duration; "empty" for an empty edit.
func describeSegments(_ track: AVAssetTrack) async throws -> String {
    try await track.load(.segments).map { segment in
        let map = segment.timeMapping
        return segment.isEmpty ? "[empty \(f(map.target.start))+\(f(map.target.duration))]"
            : "[target \(f(map.target.start)) ← media \(f(map.source.start)) for \(f(map.source.duration))]"
    }.joined(separator: " ")
}

/// The media time at which presentation starts: the first non-empty segment's source start.
func mediaStart(of track: AVAssetTrack) async throws -> CMTime {
    try await track.load(.segments).first { !$0.isEmpty }?.timeMapping.source.start ?? .zero
}

/// Every sample in decode order: presentation time, duration, full sync.
func samples(of track: AVAssetTrack) -> [(pts: CMTime, duration: CMTime, sync: Bool)] {
    guard let cursor = track.makeSampleCursorAtFirstSampleInDecodeOrder() else { return [] }
    var out: [(CMTime, CMTime, Bool)] = []
    repeat {
        out.append((cursor.presentationTimeStamp, cursor.currentSampleDuration, cursor.currentSampleSyncInfo.sampleIsFullSync.boolValue))
    } while cursor.stepInDecodeOrder(byCount: 1) == 1
    return out
}

func report(_ url: URL, label: String) async throws {
    let asset = AVURLAsset(url: url)
    print("\(label): duration \(f(try await asset.load(.duration))) s, \(size(url) / 1024) KB")
    for track in try await asset.load(.tracks) {
        let type = track.mediaType.rawValue
        print("  \(type) track: \(try await describeSegments(track))")
        let begin = try await mediaStart(of: track)
        let all = samples(of: track)
        let before = all.filter { $0.pts < begin }
        if track.mediaType == .video {
            let natural = try await track.load(.naturalSize)
            print("  video: \(Int(natural.width))×\(Int(natural.height)), \(all.count) samples, \(before.count) before the start (media \(f(begin))), first sample sync \(all.first?.sync ?? false)")
        } else if track.mediaType == .audio {
            let rate = Double(try await track.load(.naturalTimeScale))
            let frames = all.reduce(0.0) { sum, sample in
                let end = CMTimeAdd(sample.pts, sample.duration)
                let kept = CMTimeSubtract(CMTimeMinimum(end, begin), sample.pts)
                return sum + max(0, kept.seconds) * rate
            }
            print("  audio: \(all.count) packets, \(before.count) before the start (media \(f(begin))), \(Int(frames.rounded())) sample frames before it at \(Int(rate)) Hz")
        }
    }
}

let asset = AVURLAsset(url: src)
let duration = try await asset.load(.duration)
try await report(src, label: "source")

guard let video = try await asset.loadTracks(withMediaType: .video).first else { print("no video track"); exit(1) }
print("canProvideSampleCursors:", try await video.load(.canProvideSampleCursors))
let sourceSamples = samples(of: video)
let syncTimes = sourceSamples.filter(\.sync).map(\.pts.seconds).sorted()
print("sync samples: \(syncTimes.count) of \(sourceSamples.count):", syncTimes.prefix(40).map { String(format: "%.3f", $0) }.joined(separator: " "))
// A sample cursor works in media time. The track's edit list can start the media later than the
// track (SCRecordingOutput's first frame), so the start is read both as given and through the edit.
let mediaOffset = try await mediaStart(of: video)
for (label, time) in [("as given", start), ("through the edit", CMTimeAdd(start, mediaOffset))] {
    if let cursor = video.makeSampleCursor(presentationTimeStamp: time) {
        print("cursor \(label) at media \(f(time)): sample at \(f(cursor.presentationTimeStamp)), full sync \(cursor.currentSampleSyncInfo.sampleIsFullSync.boolValue)")
    }
}

// The third export adds a video composition with the asset's own properties, which makes the
// session decode and encode every frame instead of passing compatible samples through.
for (preset, name, composed) in [(AVAssetExportPresetPassthrough, "trim-pass.mp4", false),
                                 (AVAssetExportPresetHighestQuality, "trim-hq.mp4", false),
                                 (AVAssetExportPresetHighestQuality, "trim-hq-composed.mp4", true)] {
    let out = outFolder.appending(path: name)
    try? FileManager.default.removeItem(at: out)
    // A fresh asset per export, so no export shares anything with another.
    let fresh = AVURLAsset(url: src)
    guard let session = AVAssetExportSession(asset: fresh, presetName: preset) else { print("no session for \(preset)"); continue }
    session.timeRange = CMTimeRange(start: start, end: duration)
    if composed {
        session.videoComposition = try await AVVideoComposition.videoComposition(withPropertiesOf: fresh)
    }
    let readings = Task { () -> [Double] in
        var values: [Double] = []
        for await state in session.states(updateInterval: 0.1) {
            if case .exporting(let progress) = state { values.append(progress.fractionCompleted) }
        }
        return values
    }
    let t0 = Date()
    try await session.export(to: out, as: .mp4)
    let elapsed = Date().timeIntervalSince(t0)
    readings.cancel()
    let values = await readings.value
    print("\(preset)\(composed ? " with a video composition" : ""): \(String(format: "%.2f", elapsed)) s, \(size(out) / 1024) KB (source \(size(src) / 1024) KB)")
    print("  fractionCompleted (\(values.count)):", values.map { String(format: "%.2f", $0) }.joined(separator: " "))
    try await report(out, label: name)
}
