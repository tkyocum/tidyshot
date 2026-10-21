import AppKit
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Why TidyShot uploads the original PNG instead of a Clop result.
nonisolated enum ClopSkipReason: Equatable, Sendable {
    case notRunning
    case failed(String)
    case converted
    case notSmaller
    case invalidResult

    /// For the `Clop: <reason>, uploading the original` log line.
    var summary: String {
        switch self {
        case .notRunning: "Clop is not running"
        case .failed(let detail): detail
        case .converted: "Clop converted the image to another format"
        case .notSmaller: "the result is not smaller"
        case .invalidResult: "the result is not a PNG of the same pixel size"
        }
    }
}

nonisolated enum ClopOutcome: Equatable, Sendable {
    case optimised(Data, oldBytes: Int, newBytes: Int)
    case original(ClopSkipReason)
}

/// Lets Clop rewrite a throwaway copy of a PNG and hands back the result when it is a smaller,
/// same-size PNG. Every other outcome is `.original(reason)`: the caller uploads the bytes it has.
/// The original data is never touched.
nonisolated struct ClopOptimiser: Sendable {
    /// The container's `tmp/Clop`. Created on demand.
    let workDirectory: URL
    /// Asks Clop to optimise the file at the URL in place. Blocking; runs off the calling actor.
    let transport: @Sendable (URL) throws -> ClopResponse

    init(workDirectory: URL, transport: @escaping @Sendable (URL) throws -> ClopResponse) {
        self.workDirectory = workDirectory
        self.transport = transport
    }

    /// The write, the blocking request, the checks and the read-back all run in a detached task,
    /// so a main-actor caller is never blocked by file I/O or Clop's reply.
    func optimisedPNG(_ data: Data) async -> ClopOutcome {
        let workDirectory = workDirectory
        let transport = transport
        return await Task.detached {
            Self.optimise(data, workDirectory: workDirectory, transport: transport)
        }.value
    }

    private static func optimise(_ data: Data, workDirectory: URL,
                                 transport: @Sendable (URL) throws -> ClopResponse) -> ClopOutcome {
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
            response = try transport(file)
        } catch {
            return .original(.failed(describe(error)))
        }

        guard response.convertedFrom == nil, samePath(response.path, file) else {
            // Clop wrote its converted output (for example <UUID>.jpg) next to the work file.
            let output = URL(fileURLWithPath: response.path)
            if output.deletingLastPathComponent().resolvingSymlinksInPath().path
                == workDirectory.resolvingSymlinksInPath().path {
                try? FileManager.default.removeItem(at: output)
            }
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
        ClopOptimiser(workDirectory: workDirectory) { url in
            guard let bundleID = runningBundleID() else { throw ClopClientError.portUnavailable }
            return try ClopClient(bundleID: bundleID).optimise(url)
        }
    }
}
