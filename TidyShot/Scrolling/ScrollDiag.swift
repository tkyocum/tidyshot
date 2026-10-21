#if DEBUG
import CoreGraphics
import Foundation
import ImageIO
import Synchronization
import UniformTypeIdentifiers

/// Debug-only scrolling capture diagnostics: NSLog lines prefixed "ScrollDiag", the same lines in
/// scrolldiag.log, and PNGs of the first frame pairs the stitcher compares, all in the container's
/// temporary directory. The log file is emptied when a session starts, so it holds the latest
/// session (NSLog lines do not always reach `log show`). On in Debug builds, off under tests (they
/// run the finder thousands of times) and when the defaults key `ScrollDiagOff` is set.
nonisolated enum ScrollDiag {
    static let enabled: Bool = {
        let env = ProcessInfo.processInfo.environment
        if env["XCTestConfigurationFilePath"] != nil || env["XCTestBundlePath"] != nil
            || env["XCTestSessionIdentifier"] != nil || NSClassFromString("XCTestCase") != nil { return false }
        return !UserDefaults.standard.bool(forKey: "ScrollDiagOff")
    }()

    /// Pairs written so far; at most `maxPairs`.
    static let maxPairs = 6
    private static let pairs = Mutex(0)
    private static let origin = ContinuousClock.now
    /// NSTemporaryDirectory()/scrolldiag.log, in the app's container.
    static let logURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("scrolldiag.log")
    /// Open from the first `beginSession()`; lines from any thread are appended under the lock.
    private static let logFile = Mutex<FileHandle?>(nil)

    /// Milliseconds since the app first logged a diagnostic, for lining lines up.
    static var t: String { ms(since: origin) }

    static func log(_ message: @autoclosure () -> String) {
        guard enabled else { return }
        let line = "t=\(t) \(message())"
        NSLog("ScrollDiag %@", line)
        logFile.withLock { handle in
            try? handle?.write(contentsOf: Data((line + "\n").utf8))
        }
    }

    static func ms(since start: ContinuousClock.Instant) -> String {
        ms(ContinuousClock.now - start)
    }

    static func ms(_ d: Duration) -> String {
        String(format: "%.1f", Double(d.components.seconds) * 1000 + Double(d.components.attoseconds) / 1e15)
    }

    /// Resets the pair counter and empties the log file at the start of a session, then logs the
    /// file's path.
    static func beginSession() {
        pairs.withLock { $0 = 0 }
        guard enabled else { return }
        logFile.withLock { handle in
            if let handle {
                try? handle.truncate(atOffset: 0)
            } else {
                FileManager.default.createFile(atPath: logURL.path, contents: nil)
                handle = try? FileHandle(forWritingTo: logURL)
                try? handle?.truncate(atOffset: 0)
            }
        }
        log("log file path=\(logURL.path)")
    }

    /// Writes `previous` and `current` as scrolldiag-NN-prev.png and -cur.png, for the first
    /// `maxPairs` comparisons of a session, and logs their paths.
    static func dumpPair(previous: ScrollFrame, current: ScrollFrame) {
        guard enabled else { return }
        let n: Int? = pairs.withLock { count in
            guard count < maxPairs else { return nil }
            count += 1
            return count
        }
        guard let n else { return }
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
        for (frame, suffix) in [(previous, "prev"), (current, "cur")] {
            let url = dir.appendingPathComponent(String(format: "scrolldiag-%02d-%@.png", n, suffix))
            let ok = writePNG(frame, to: url)
            log("png pair=\(n) \(suffix) \(frame.width)x\(frame.height) ok=\(ok) path=\(url.path)")
        }
    }

    /// The frame's bytes as they are (BGRA, tagged sRGB so nothing converts them), losslessly.
    private static func writePNG(_ frame: ScrollFrame, to url: URL) -> Bool {
        guard let provider = CGDataProvider(data: frame.bgra as CFData),
              let image = CGImage(width: frame.width, height: frame.height, bitsPerComponent: 8, bitsPerPixel: 32,
                                  bytesPerRow: frame.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipFirst.rawValue
                                                           | CGBitmapInfo.byteOrder32Little.rawValue),
                                  provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent),
              let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
        else { return false }
        CGImageDestinationAddImage(dest, image, nil)
        return CGImageDestinationFinalize(dest)
    }

    static func describe(_ match: OverlapMatch) -> String {
        switch match {
        case .still: "still"
        case .lost: "lost"
        case .moved(let dy, let top, let bandEnd, let score):
            "moved dy=\(dy) top=\(top) bandEnd=\(bandEnd) score=\(String(format: "%.3f", score))"
        }
    }
}
#endif
