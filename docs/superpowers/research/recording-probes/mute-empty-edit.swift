import AVFoundation
setbuf(stdout, nil)
let src = URL(fileURLWithPath: CommandLine.arguments[1]); let out = URL(fileURLWithPath: CommandLine.arguments[2])
let muteStart = Double(CommandLine.arguments[3])!, muteEnd = Double(CommandLine.arguments[4])!
let asset = AVURLAsset(url: src)
let duration = try await asset.load(.duration)
let comp = AVMutableComposition()
let full = CMTimeRange(start: .zero, duration: duration)
for v in try await asset.loadTracks(withMediaType: .video) {
    let t = comp.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)!
    try t.insertTimeRange(try await v.load(.timeRange), of: v, at: .zero)
}
for a in try await asset.loadTracks(withMediaType: .audio) {
    let t = comp.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)!
    let ms = CMTime(seconds: muteStart, preferredTimescale: 600), me = CMTime(seconds: muteEnd, preferredTimescale: 600)
    try t.insertTimeRange(CMTimeRange(start: .zero, end: ms), of: a, at: .zero)
    t.insertEmptyTimeRange(CMTimeRange(start: ms, end: me))
    try t.insertTimeRange(CMTimeRange(start: me, end: duration), of: a, at: me)
}
try? FileManager.default.removeItem(at: out)
let s = AVAssetExportSession(asset: comp, presetName: AVAssetExportPresetPassthrough)!
let t0 = Date()
try await s.export(to: out, as: .mp4)
let o = AVURLAsset(url: out)
var desc: [String] = []
for t in try await o.load(.tracks) {
    let segs = try await t.load(.segments).map { $0.isEmpty ? String(format: "[empty %.2f-%.2f]", $0.timeMapping.target.start.seconds, $0.timeMapping.target.end.seconds) : String(format: "[%.2f-%.2f]", $0.timeMapping.target.start.seconds, $0.timeMapping.target.end.seconds) }
    desc.append("\(t.mediaType.rawValue) \(segs.joined())")
}
print(String(format: "export %.2fs, duration %.2f (source %.2f), %@", Date().timeIntervalSince(t0), try await o.load(.duration).seconds, duration.seconds, desc.joined(separator: " | ")))
// Decode the audio in the muted range to confirm silence.
let reader = try AVAssetReader(asset: o)
let at = try await o.loadTracks(withMediaType: .audio)[0]
let output = AVAssetReaderTrackOutput(track: at, outputSettings: [AVFormatIDKey: kAudioFormatLinearPCM, AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false])
reader.add(output); reader.startReading()
var peakIn = 0, peakOut = 0
while let buf = output.copyNextSampleBuffer() {
    let time = CMSampleBufferGetPresentationTimeStamp(buf).seconds
    guard let block = CMSampleBufferGetDataBuffer(buf) else { continue }
    var len = 0; var ptr: UnsafeMutablePointer<CChar>?
    CMBlockBufferGetDataPointer(block, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &len, dataPointerOut: &ptr)
    let samples = UnsafeBufferPointer(start: UnsafeRawPointer(ptr!).assumingMemoryBound(to: Int16.self), count: len / 2)
    let peak = samples.map { abs(Int($0)) }.max() ?? 0
    if time > muteStart + 0.05 && time < muteEnd - 0.1 { peakIn = max(peakIn, peak) } else { peakOut = max(peakOut, peak) }
}
print("peak inside mute:", peakIn, "outside:", peakOut)
