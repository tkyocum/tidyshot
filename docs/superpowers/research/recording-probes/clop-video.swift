import Foundation
import AVFoundation
import CoreGraphics
setbuf(stdout, nil)
func describe(_ url: URL) async throws -> String {
    let asset = AVURLAsset(url: url)
    let duration = try await asset.load(.duration).seconds
    let tracks = try await asset.load(.tracks)
    var parts = ["\(url.lastPathComponent)", "\((try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int ?? 0) / 1024) KB", String(format: "%.2fs", duration)]
    for t in tracks {
        let fmts = try await t.load(.formatDescriptions)
        let codec = fmts.first.map { CMFormatDescriptionGetMediaSubType($0) }.map { String(bytes: withUnsafeBytes(of: $0.bigEndian, Array.init), encoding: .ascii) ?? "?" } ?? "?"
        if t.mediaType == .video {
            let size = try await t.load(.naturalSize); let fps = try await t.load(.nominalFrameRate); let rate = try await t.load(.estimatedDataRate)
            parts.append("video \(codec) \(Int(size.width))x\(Int(size.height)) \(String(format: "%.1f", fps))fps \(Int(rate / 1000))kbps")
        } else { parts.append("\(t.mediaType.rawValue) \(codec)") }
    }
    return parts.joined(separator: ", ")
}
let src = URL(fileURLWithPath: CommandLine.arguments[1])
let work = FileManager.default.temporaryDirectory.appending(path: "clop-video-probe-\(UUID().uuidString.prefix(6))", directoryHint: .isDirectory)
try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
let copy = work.appending(path: "recording.mp4")
try FileManager.default.copyItem(at: src, to: copy)
print("before:", try await describe(copy))
let client = ClopClient(bundleID: "com.lowtechguys.Clop", sendTimeout: 2, receiveTimeout: 600)
let t0 = Date()
do {
    let response = try client.optimise(copy)
    print(String(format: "reply after %.1fs:", Date().timeIntervalSince(t0)), response)
    let out = URL(fileURLWithPath: response.path)
    print("after:", try await describe(out))
    print("same path:", out.standardizedFileURL == copy.standardizedFileURL, "dir listing:", (try? FileManager.default.contentsOfDirectory(atPath: work.path)) ?? [])
} catch { print(String(format: "failed after %.1fs:", Date().timeIntervalSince(t0)), error) }
