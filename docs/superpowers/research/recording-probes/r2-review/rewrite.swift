import AVFoundation
setbuf(stdout, nil)
// rewrite <in> <out> <muteStart> <muteEnd>: video passthrough, audio decoded, zeroed in the range, re-encoded to AAC.
let src = URL(fileURLWithPath: CommandLine.arguments[1]), dst = URL(fileURLWithPath: CommandLine.arguments[2])
let ms = Double(CommandLine.arguments[3])!, me = Double(CommandLine.arguments[4])!
try? FileManager.default.removeItem(at: dst)
let asset = AVURLAsset(url: src)
let v = try await asset.loadTracks(withMediaType: .video)[0], a = try await asset.loadTracks(withMediaType: .audio)[0]
let vfd = try await v.load(.formatDescriptions).first!
let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(try await a.load(.formatDescriptions).first!)!.pointee
let reader = try AVAssetReader(asset: asset)
let vo = AVAssetReaderTrackOutput(track: v, outputSettings: nil)
let ao = AVAssetReaderTrackOutput(track: a, outputSettings: [AVFormatIDKey: kAudioFormatLinearPCM, AVLinearPCMBitDepthKey: 32, AVLinearPCMIsFloatKey: true, AVLinearPCMIsNonInterleaved: false])
reader.add(vo); reader.add(ao)
let writer = try AVAssetWriter(outputURL: dst, fileType: .mp4)
let vi = AVAssetWriterInput(mediaType: .video, outputSettings: nil, sourceFormatHint: vfd)
let ai = AVAssetWriterInput(mediaType: .audio, outputSettings: [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: asbd.mSampleRate, AVNumberOfChannelsKey: asbd.mChannelsPerFrame, AVEncoderBitRateKey: 128_000])
vi.expectsMediaDataInRealTime = false; ai.expectsMediaDataInRealTime = false
writer.add(vi); writer.add(ai)
let t0 = Date()
reader.startReading(); writer.startWriting(); writer.startSession(atSourceTime: .zero)
var vDone = false, aDone = false
while !(vDone && aDone) {
    if !vDone && vi.isReadyForMoreMediaData { if let b = vo.copyNextSampleBuffer() { vi.append(b) } else { vi.markAsFinished(); vDone = true } }
    if !aDone && ai.isReadyForMoreMediaData {
        if let b = ao.copyNextSampleBuffer() {
            let start = CMSampleBufferGetPresentationTimeStamp(b).seconds, n = CMSampleBufferGetNumSamples(b)
            let rate = asbd.mSampleRate, ch = Int(asbd.mChannelsPerFrame)
            let block = CMSampleBufferGetDataBuffer(b)!
            var len = 0; var ptr: UnsafeMutablePointer<CChar>?
            CMBlockBufferGetDataPointer(block, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &len, dataPointerOut: &ptr)
            let f = UnsafeMutableRawPointer(ptr!).assumingMemoryBound(to: Float.self)
            for i in 0..<n { let t = start + Double(i) / rate; if t >= ms && t < me { for c in 0..<ch { f[i * ch + c] = 0 } } }
            ai.append(b)
        } else { ai.markAsFinished(); aDone = true }
    }
    if !(vi.isReadyForMoreMediaData || ai.isReadyForMoreMediaData) { usleep(1000) }
}
await writer.finishWriting()
print("status", writer.status.rawValue, writer.error?.localizedDescription ?? "", String(format: "%.2fs", Date().timeIntervalSince(t0)))
