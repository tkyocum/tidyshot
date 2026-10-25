import AVFoundation
setbuf(stdout, nil)

// usage: mute2 src.mp4 out.mp4 start end
let srcURL = URL(fileURLWithPath: CommandLine.arguments[1])
let outURL = URL(fileURLWithPath: CommandLine.arguments[2])
let muteStart = Double(CommandLine.arguments[3])!, muteEnd = Double(CommandLine.arguments[4])!

try? FileManager.default.removeItem(at: outURL)
let asset = AVURLAsset(url: srcURL)
let vTrack = try await asset.loadTracks(withMediaType: .video)[0]
let aTrack = try await asset.loadTracks(withMediaType: .audio)[0]

let reader = try AVAssetReader(asset: asset)
let vOut = AVAssetReaderTrackOutput(track: vTrack, outputSettings: nil)
let pcm: [String: Any] = [
    AVFormatIDKey: kAudioFormatLinearPCM, AVLinearPCMBitDepthKey: 16,
    AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false, AVLinearPCMIsNonInterleaved: false,
]
let aOut = AVAssetReaderTrackOutput(track: aTrack, outputSettings: pcm)
reader.add(vOut); reader.add(aOut)

let writer = try AVAssetWriter(outputURL: outURL, fileType: .mp4)
let vFormat = try await vTrack.load(.formatDescriptions).first
let vIn = AVAssetWriterInput(mediaType: .video, outputSettings: nil, sourceFormatHint: vFormat)
vIn.transform = try await vTrack.load(.preferredTransform)
// Source audio format
let aDesc = try await aTrack.load(.formatDescriptions).first!
let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(aDesc)!.pointee
let rate = asbd.mSampleRate, ch = Int(asbd.mChannelsPerFrame)
let aIn = AVAssetWriterInput(mediaType: .audio, outputSettings: [
    AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: rate, AVNumberOfChannelsKey: ch, AVEncoderBitRateKey: 128_000,
])
writer.add(vIn); writer.add(aIn)
precondition(reader.startReading()); precondition(writer.startWriting())
writer.startSession(atSourceTime: .zero)

func zeroed(_ buf: CMSampleBuffer) -> CMSampleBuffer {
    let t0 = CMSampleBufferGetPresentationTimeStamp(buf).seconds
    let n = CMSampleBufferGetNumSamples(buf)
    let t1 = t0 + Double(n) / rate
    if t1 <= muteStart || t0 >= muteEnd { return buf }
    // copy the data so we never mutate the reader's buffer
    guard let block = CMSampleBufferGetDataBuffer(buf) else { return buf }
    var copy: CMBlockBuffer?
    let len = CMBlockBufferGetDataLength(block)
    CMBlockBufferCreateContiguous(allocator: nil, sourceBuffer: block, blockAllocator: nil, customBlockSource: nil, offsetToData: 0, dataLength: len, flags: 0, blockBufferOut: &copy)
    var ptr: UnsafeMutablePointer<CChar>?
    CMBlockBufferGetDataPointer(copy!, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: nil, dataPointerOut: &ptr)
    let bytesPerFrame = ch * 2
    let first = max(0, Int(((muteStart - t0) * rate).rounded()))
    let last = min(n, Int(((muteEnd - t0) * rate).rounded()))
    if last > first { memset(ptr! + first * bytesPerFrame, 0, (last - first) * bytesPerFrame) }
    var timing = CMSampleTimingInfo(duration: CMSampleBufferGetDuration(buf), presentationTimeStamp: CMSampleBufferGetPresentationTimeStamp(buf), decodeTimeStamp: .invalid)
    var out: CMSampleBuffer?
    CMSampleBufferCreate(allocator: nil, dataBuffer: copy, dataReady: true, makeDataReadyCallback: nil, refcon: nil,
                         formatDescription: CMSampleBufferGetFormatDescription(buf), sampleCount: n, sampleTimingEntryCount: 1,
                         sampleTimingArray: &timing, sampleSizeEntryCount: 0, sampleSizeArray: nil, sampleBufferOut: &out)
    return out ?? buf
}

final class Box<T>: @unchecked Sendable { var v: T; init(_ v: T) { self.v = v } }
func pump(_ input: AVAssetWriterInput, _ output: AVAssetReaderTrackOutput, _ q: String, map: @escaping @Sendable (CMSampleBuffer) -> CMSampleBuffer) async {
    let o = Box(output)
    await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
        input.requestMediaDataWhenReady(on: DispatchQueue(label: q)) {
            while input.isReadyForMoreMediaData {
                if let b = o.v.copyNextSampleBuffer() { input.append(map(b)) } else { input.markAsFinished(); c.resume(); return }
            }
        }
    }
}
async let v: Void = pump(vIn, vOut, "v") { $0 }
async let a: Void = pump(aIn, aOut, "a") { zeroed($0) }
_ = await (v, a)
await writer.finishWriting()
print("writer status", writer.status.rawValue, writer.error as Any, "reader", reader.status.rawValue, reader.error as Any)
