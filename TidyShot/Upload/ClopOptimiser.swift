import AppKit
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Why TidyShot uploads the original instead of a Clop result.
nonisolated enum ClopSkipReason: Equatable, Sendable {
    case notRunning
    case failed(String)
    case converted
    case notSmaller
    case invalidResult
    /// The `tmp` volume has less free space than the recording plus `videoHeadroomBytes`.
    case notEnoughSpace
    case lostAudio
    case notPlayable
    case differentVideo
    case durationChanged

    /// For the `Clop: <reason>, uploading the original` log line.
    var summary: String {
        switch self {
        case .notRunning: "Clop is not running"
        case .failed(let detail): detail
        case .converted: "Clop converted the file to another format"
        case .notSmaller: "the result is not smaller"
        case .invalidResult: "the result is not a PNG of the same pixel size"
        case .notEnoughSpace: "not enough free space"
        case .lostAudio: "the result lost its audio"
        case .notPlayable: "the result does not play"
        case .differentVideo: "the result is not one video track of the same size"
        case .durationChanged: "the result's duration changed"
        }
    }
}

nonisolated enum ClopOutcome: Equatable, Sendable {
    case optimised(Data, oldBytes: Int, newBytes: Int)
    case original(ClopSkipReason)
}

/// A recording's Clop step. `.optimised` is Clop's movie in `tmp/Clop`, which the caller then owns
/// and removes; `.original` has left nothing behind.
nonisolated enum ClopVideoOutcome: Equatable, Sendable {
    case optimised(URL, oldBytes: Int64, newBytes: Int64)
    case original(ClopSkipReason)
}

/// Lets Clop rewrite a throwaway copy of a PNG or a recording and hands back the result when it
/// passes the checks. Every other outcome is `.original(reason)`: the caller uploads what it has.
/// The original data or file is never touched.
nonisolated struct ClopOptimiser: Sendable {
    /// The container's `tmp/Clop`. Created on demand.
    let workDirectory: URL
    /// Asks Clop to optimise the file at the URL in place, waiting up to the given receive timeout.
    /// Blocking; runs on one of the serial queues below.
    let transport: @Sendable (URL, TimeInterval) throws -> ClopResponse
    /// Free bytes on the volume of a URL, or nil when unreadable, which counts as enough.
    let freeBytes: @Sendable (URL) -> Int64?

    /// The receive timeout for an image (spec 2.7).
    static let imageTimeout: TimeInterval = 30
    /// What must stay free on the `tmp` volume besides the work copy (decimal GB, as Finder shows).
    static let videoHeadroomBytes: Int64 = 1_000_000_000
    /// How far the result's duration may be from the work file's.
    static let durationTolerance: TimeInterval = 0.5

    /// The receive timeout for a recording of `duration` seconds. Clop took about a quarter of
    /// the duration in the probes.
    static func videoTimeout(duration: TimeInterval) -> TimeInterval {
        60 + 3 * duration
    }

    init(workDirectory: URL, transport: @escaping @Sendable (URL, TimeInterval) throws -> ClopResponse,
         freeBytes: @escaping @Sendable (URL) -> Int64? = RecordingLimits.freeBytes(at:)) {
        self.workDirectory = workDirectory
        self.transport = transport
        self.freeBytes = freeBytes
    }

    /// One private serial queue for every image request, so Clop sees one at a time and a blocked
    /// `CFMessagePortSendRequest` (up to the 32 s send and receive timeouts) never occupies a
    /// cooperative-pool thread.
    private static let queue = DispatchQueue(label: "io.tky.tidyshot.clop", qos: .utility)
    /// The same for recordings, so a long video request never holds a screenshot's: Clop sees at
    /// most one image request and one video request at a time.
    private static let videoQueue = DispatchQueue(label: "io.tky.tidyshot.clop-video", qos: .utility)

    /// The write, the blocking request, the checks and the read-back all run on the serial queue,
    /// so a main-actor caller is never blocked by file I/O or Clop's reply.
    func optimisedPNG(_ data: Data) async -> ClopOutcome {
        let workDirectory = workDirectory
        let transport = transport
        return await withCheckedContinuation { continuation in
            Self.queue.async {
                continuation.resume(returning: Self.optimise(data, workDirectory: workDirectory, transport: transport))
            }
        }
    }

    /// Lets Clop rewrite a copy of the recording at `source` and hands the copy back when it still
    /// plays, has one video track of the same size, keeps its audio tracks and its duration (within
    /// `durationTolerance`), and is smaller. `duration` is the recording's length, for the receive
    /// timeout; `scope` is the save folder for a file inside it, held while the copy is made.
    /// Runs off the caller's actor; only the request runs on the video queue. On every
    /// `.original` the work file, and any file Clop converted it to, is gone before this returns.
    @concurrent
    func optimisedVideo(at source: URL, duration: TimeInterval, scope: URL?) async -> ClopVideoOutcome {
        let work = workDirectory.appending(path: "\(UUID().uuidString).mp4", directoryHint: .notDirectory)
        if let reason = makeWorkCopy(of: source, at: work, scope: scope) {
            return .original(reason)
        }
        // Read before the request, because Clop rewrites the file in place.
        let before = await VideoValidation.inspect(work)
        guard before.isPlayable, before.naturalSize != nil else {
            try? FileManager.default.removeItem(at: work)
            return .original(.failed("the recording could not be read"))
        }

        let transport = transport
        let timeout = Self.videoTimeout(duration: duration)
        let reply = await withCheckedContinuation { (continuation: CheckedContinuation<Result<ClopResponse, any Error>, Never>) in
            Self.videoQueue.async {
                continuation.resume(returning: Result { try transport(work, timeout) })
            }
        }

        let outcome: ClopVideoOutcome
        switch reply {
        case .failure(let error):
            outcome = .original(.failed(Self.describe(error)))
        case .success(let response):
            outcome = await Self.check(response, work: work, before: before)
            if case .original = outcome {
                Self.removeConvertedOutput(response.path, in: workDirectory)
            }
        }
        if case .original = outcome {
            try? FileManager.default.removeItem(at: work)
        }
        return outcome
    }

    /// Checks the space on the `tmp` volume, then copies the recording to `work` (a clone when both
    /// are on one volume), holding `scope` for both. This runs inside `optimisedVideo`, so never on
    /// the main actor. Returns why Clop is skipped, or nil when the copy is made.
    private func makeWorkCopy(of source: URL, at work: URL, scope: URL?) -> ClopSkipReason? {
        let accessing = scope?.startAccessingSecurityScopedResource() ?? false
        defer { if accessing { scope?.stopAccessingSecurityScopedResource() } }

        let size: Int64
        do {
            size = Int64(try source.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0)
        } catch {
            return .failed("could not read the recording: \(error.localizedDescription)")
        }
        if let free = freeBytes(workDirectory), free < size + Self.videoHeadroomBytes {
            return .notEnoughSpace
        }
        do {
            try FileManager.default.createDirectory(at: workDirectory, withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: source, to: work)
        } catch {
            // A copy that failed part way leaves a partial file.
            try? FileManager.default.removeItem(at: work)
            return .failed("could not copy the recording: \(error.localizedDescription)")
        }
        return nil
    }

    /// The acceptance checks, in the design's order, against what the work file was before Clop.
    private static func check(_ response: ClopResponse, work: URL, before: VideoFacts) async -> ClopVideoOutcome {
        guard samePath(response.path, work), response.convertedFrom == nil else { return .original(.converted) }
        let after = await VideoValidation.inspect(work)
        guard after.isPlayable else { return .original(.notPlayable) }
        guard after.videoTracks == 1, after.naturalSize == before.naturalSize else { return .original(.differentVideo) }
        guard after.audioTracks >= before.audioTracks else { return .original(.lostAudio) }
        guard abs(after.duration - before.duration) <= durationTolerance else { return .original(.durationChanged) }
        guard after.byteCount < before.byteCount else { return .original(.notSmaller) }
        return .optimised(work, oldBytes: before.byteCount, newBytes: after.byteCount)
    }

    /// Removes the file Clop converted the work file to (for example `<UUID>.jpg`), which it
    /// writes next to it. Anything outside the work directory is left alone.
    private static func removeConvertedOutput(_ path: String, in workDirectory: URL) {
        let output = URL(fileURLWithPath: path)
        if output.deletingLastPathComponent().resolvingSymlinksInPath().path
            == workDirectory.resolvingSymlinksInPath().path {
            try? FileManager.default.removeItem(at: output)
        }
    }

    private static func optimise(_ data: Data, workDirectory: URL,
                                 transport: @Sendable (URL, TimeInterval) throws -> ClopResponse) -> ClopOutcome {
        let file = workDirectory.appending(path: "\(UUID().uuidString).png", directoryHint: .notDirectory)
        // Clop keeps its own copy, but the work file is ours to remove on every path.
        defer { try? FileManager.default.removeItem(at: file) }

        do {
            try FileManager.default.createDirectory(at: workDirectory, withIntermediateDirectories: true)
            try data.write(to: file)
        } catch {
            return .original(.failed("could not write the work file: \(error.localizedDescription)"))
        }

        let response: ClopResponse
        do {
            response = try transport(file, imageTimeout)
        } catch {
            return .original(.failed(describe(error)))
        }

        guard response.convertedFrom == nil, samePath(response.path, file) else {
            removeConvertedOutput(response.path, in: workDirectory)
            return .original(.converted)
        }
        guard response.newBytes < response.oldBytes else { return .original(.notSmaller) }

        guard let expected = pixelSize(of: data), let result = try? Data(contentsOf: file),
              isPNG(result), pixelSize(of: result) == expected else { return .original(.invalidResult) }
        guard result.count < data.count else { return .original(.notSmaller) }
        return .optimised(result, oldBytes: data.count, newBytes: result.count)
    }

    private static func describe(_ error: Error) -> String {
        guard let clopError = error as? ClopClientError else { return error.localizedDescription }
        return switch clopError {
        case .portUnavailable: "Clop's port is unavailable"
        case .sendFailed(let status): "the request failed (status \(status))"
        case .badReply: "Clop sent an unreadable reply"
        }
    }

    /// Compares through symlinks, since `/var` and `/private/var` name the same file.
    private static func samePath(_ path: String, _ file: URL) -> Bool {
        URL(fileURLWithPath: path).resolvingSymlinksInPath().path == file.resolvingSymlinksInPath().path
    }

    private static func isPNG(_ data: Data) -> Bool {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let type = CGImageSourceGetType(source) else { return false }
        return UTType(type as String)?.conforms(to: .png) == true
    }

    private static func pixelSize(of data: Data) -> CGSize? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int else { return nil }
        return CGSize(width: width, height: height)
    }
}

/// Finding Clop (spec 2.7). TidyShot never launches it: a Clop that is not running means the
/// original uploads.
nonisolated enum ClopApp {
    /// The direct build and the Setapp build, in that order.
    static let bundleIDs = ["com.lowtechguys.Clop", "com.lowtechguys.Clop-setapp"]

    /// True when either build is installed, for the Upload tab's toggle.
    static var isInstalled: Bool {
        bundleIDs.contains { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) != nil }
    }

    /// The bundle id of a running Clop, or nil when neither build runs.
    static func runningBundleID() -> String? {
        bundleIDs.first { !NSRunningApplication.runningApplications(withBundleIdentifier: $0).isEmpty }
    }

    /// The container's `tmp/Clop`, where `ClopOptimiser` writes its throwaway copies.
    static var workDirectory: URL {
        FileManager.default.temporaryDirectory.appending(path: "Clop", directoryHint: .isDirectory)
    }

    /// The coordinator's optimiser: each request goes to whichever build is running when it is
    /// sent. A Clop that quit since the check throws `portUnavailable`, so the original uploads.
    static func makeOptimiser() -> ClopOptimiser {
        ClopOptimiser(workDirectory: workDirectory) { url, timeout in
            guard let bundleID = runningBundleID() else { throw ClopClientError.portUnavailable }
            return try ClopClient(bundleID: bundleID, receiveTimeout: timeout).optimise(url)
        }
    }
}
