import CoreGraphics
import Foundation
import ImageIO
import Synchronization
import UniformTypeIdentifiers

/// Scrolling capture diagnostics, in every configuration and off unless the defaults key
/// `ScrollDiag` is true (`defaults write <bundle id> ScrollDiag -bool true`), read once when a
/// session starts. When on: NSLog lines prefixed "ScrollDiag", the same lines in scrolldiag.log, and
/// PNGs of the first compared frame pairs and of the pairs the finder lost, all in the container's
/// temporary directory. The log file is emptied when a session starts, so it holds the latest
/// session (NSLog lines do not always reach `log show`, and Release redacts their arguments). Always
/// off under tests (they run the finder thousands of times) and when `ScrollDiagOff` is set. When
/// off, messages are autoclosures that never run and no PNG is written.
nonisolated enum ScrollDiag {
    /// Compared pairs dumped regardless of the result.
    static let firstPairs = 3
    /// Pairs the finder lost that are dumped per session.
    static let maxLostPairs = 30

    private struct State {
        var enabled = false
        var compared = 0
        var lostDumped = 0
        var dumps = 0
        var notes: [String] = []
    }

    private static let state = Mutex(State())
    private static let origin = ContinuousClock.now
    /// NSTemporaryDirectory()/scrolldiag.log, in the app's container.
    static let logURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("scrolldiag.log")
    /// Open from `beginSession()` while enabled; lines from any thread are appended under the lock.
    private static let logFile = Mutex<FileHandle?>(nil)

    /// Whether this session logs: decided by `beginSession()`, false before the first one.
    static var enabled: Bool { state.withLock { $0.enabled } }

    private static var underTests: Bool {
        let env = ProcessInfo.processInfo.environment
        return env["XCTestConfigurationFilePath"] != nil || env["XCTestBundlePath"] != nil
            || env["XCTestSessionIdentifier"] != nil || NSClassFromString("XCTestCase") != nil
    }

    /// Milliseconds since the app first logged a diagnostic, for lining lines up.
    static var t: String { ms(since: origin) }

    static func log(_ message: @autoclosure () -> String) {
        guard enabled else { return }
        write("t=\(t) \(message())")
    }

    private static func write(_ line: String) {
        NSLog("ScrollDiag %@", line)
        logFile.withLock { handle in
            try? handle?.write(contentsOf: Data((line + "\n").utf8))
        }
    }

    /// The overlap finder's reasoning: logged like `log`, and kept for the pair line `compared`
    /// writes after the find.
    static func findNote(_ message: @autoclosure () -> String) {
        guard enabled else { return }
        let text = message()
        state.withLock { $0.notes.append(text) }
        write("t=\(t) \(text)")
    }

    static func ms(since start: ContinuousClock.Instant) -> String {
        ms(ContinuousClock.now - start)
    }

    static func ms(_ d: Duration) -> String {
        String(format: "%.1f", Double(d.components.seconds) * 1000 + Double(d.components.attoseconds) / 1e15)
    }

    /// Reads the `ScrollDiag` default, resets the counters and empties the log file at the start of
    /// a session, then logs the file's path once.
    static func beginSession() {
        let defaults = UserDefaults.standard
        let on = !underTests && defaults.bool(forKey: "ScrollDiag") && !defaults.bool(forKey: "ScrollDiagOff")
        state.withLock { $0 = State(enabled: on) }
        logFile.withLock { handle in
            guard on else {
                try? handle?.close()
                handle = nil
                return
            }
            if let handle {
                try? handle.truncate(atOffset: 0)
                try? handle.seek(toOffset: 0)
            } else {
                FileManager.default.createFile(atPath: logURL.path, contents: nil)
                handle = try? FileHandle(forWritingTo: logURL)
                try? handle?.truncate(atOffset: 0)
            }
        }
        log("log file path=\(logURL.path)")
    }

    /// Clears the finder's notes before a find.
    static func beginFind() {
        guard enabled else { return }
        state.withLock { $0.notes.removeAll(keepingCapacity: true) }
    }

    /// Logs one comparison: which frame was the previous (its serial and the content offset it was
    /// accepted at) and which the current, so a stale previous shows. Writes both frames as
    /// scrolldiag-NN-prev.png and -cur.png for the first `firstPairs` comparisons and for every
    /// lost one (at most `maxLostPairs`), with the finder's reasons on the line.
    static func compared(previous: ScrollFrame, previousOffset: Int, current: ScrollFrame, predicted: Int?,
                         lastDy: Int?, committedHeight: Int, findDuration: Duration, match: OverlapMatch) {
        guard enabled else { return }
        let isLost = match == .lost
        let (n, dump, notes) = state.withLock { s -> (Int, Int?, [String]) in
            s.compared += 1
            var dump: Int?
            if isLost && s.lostDumped < maxLostPairs {
                s.lostDumped += 1
                dump = s.dumps + 1
            } else if s.compared <= firstPairs {
                dump = s.dumps + 1
            }
            if dump != nil { s.dumps += 1 }
            return (s.compared, dump, s.notes)
        }
        var line = "compare #\(n) previous=serial \(previous.serial) accepted at offset \(previousOffset) current=serial \(current.serial) "
            + "framesApart=\(current.serial - previous.serial) predicted=\(predicted.map(String.init) ?? "nil") "
            + "lastDy=\(lastDy.map(String.init) ?? "nil") committedHeight=\(committedHeight) find=\(ms(findDuration))ms "
            + "-> \(describe(match))"
        if let dump {
            line += " pair=\(String(format: "%02d", dump)) reasons=[\(notes.joined(separator: " | "))]"
            log(line)
            writePair(index: dump, previous: previous, current: current)
        } else {
            log(line)
        }
    }

    private static func writePair(index: Int, previous: ScrollFrame, current: ScrollFrame) {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
        for (frame, suffix) in [(previous, "prev"), (current, "cur")] {
            let url = dir.appendingPathComponent(String(format: "scrolldiag-%02d-%@.png", index, suffix))
            let ok = writePNG(frame, to: url)
            log("png pair=\(index) \(suffix) serial=\(frame.serial) \(frame.width)x\(frame.height) ok=\(ok) path=\(url.path)")
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
