import Foundation
import Testing
@testable import TidyShot
/// Clop in the suite (small seams design 3.1): `environment.clopOptimiser` and `isClopRunning` in one.
/// Each request is recorded, then answered from `answers` in order. A request with no answer left, or an
/// answer of the other kind, records an issue and is answered `.original(unscripted)`. A second hold
/// while one is held records an issue and is answered `cancelledAnswer` at once. Nothing here reaches
/// Clop, its port, `NSRunningApplication` or the serial queues.
final class FakeClop: ClopOptimising {
    /// What one request answers. `Sendable` because `SingleWaiter` carries it.
    nonisolated enum Answer: Equatable, Sendable {
        case smaller(Data)  // an image: these bytes, fewer than the request's
        /// A recording: a sparse movie of this many bytes in `workDirectory`, owned by the caller.
        case smallerMovie(byteCount: Int64)
        case original(ClopSkipReason)
        case hold  // waits for `release(_:)`
    }
    nonisolated enum Request: Equatable, Sendable {
        case png(Data)
        case video(URL, duration: TimeInterval)
    }
    static let cancelledAnswer = Answer.original(.failed("FakeClop's held request was cancelled"))
    static let unscripted = ClopSkipReason.failed("FakeClop had no answer for this request")
    let workDirectory: URL
    var isRunning = true
    private(set) var runningChecks = 0
    private(set) var requests: [Request] = []
    var answers: [Answer] = []
    private let held = SingleWaiter(cancelled: FakeClop.cancelledAnswer,
                                    secondEntry: "FakeClop held a second request while one was held")
    init(workDirectory: URL) { self.workDirectory = workDirectory }
    var isHolding: Bool { held.isWaiting }
    func checkRunning() -> Bool {
        runningChecks += 1
        return isRunning
    }
    /// Answers the held request; a no-op when none is held, so a test's `defer` can call it.
    func release(_ answer: Answer) { held.resume(answer) }
    var workFiles: [String] {
        (try? FileManager.default.contentsOfDirectory(atPath: workDirectory.path(percentEncoded: false))) ?? []
    }
    func optimisedPNG(_ data: Data) async -> ClopOutcome {
        requests.append(.png(data))
        switch await nextAnswer() {
        case .smaller(let bytes):
            if bytes.count >= data.count {
                Issue.record("FakeClop's smaller PNG is \(bytes.count) bytes, the request \(data.count)")
            }
            return .optimised(bytes, oldBytes: data.count, newBytes: bytes.count)
        case .original(let reason):
            return .original(reason)
        case .smallerMovie, .hold:
            Issue.record("FakeClop was given a movie answer for a PNG")
            return .original(Self.unscripted)
        }
    }
    func optimisedVideo(at source: URL, duration: TimeInterval, scope: URL?) async -> ClopVideoOutcome {
        requests.append(.video(source, duration: duration))
        // Read before any hold: `ClopOptimiser` copies the source before it sends the request.
        let oldBytes = Int64((try? source.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        switch await nextAnswer() {
        case .smallerMovie(let byteCount):
            if byteCount >= oldBytes {
                Issue.record("FakeClop's smaller movie is \(byteCount) bytes, the source \(oldBytes)")
            }
            let movie = workDirectory.appending(path: "\(UUID().uuidString).mp4", directoryHint: .notDirectory)
            do {
                try CoordinatorWorld.writeSparseFile(at: movie, byteCount: byteCount)
            } catch {
                Issue.record(error)
                return .original(Self.unscripted)
            }
            return .optimised(movie, oldBytes: oldBytes, newBytes: byteCount)
        case .original(let reason):
            return .original(reason)
        case .smaller, .hold:
            Issue.record("FakeClop was given a PNG answer for a movie")
            return .original(Self.unscripted)
        }
    }
    private func nextAnswer() async -> Answer {
        guard !answers.isEmpty else {
            Issue.record("FakeClop was asked with no answer scripted")
            return .original(Self.unscripted)
        }
        let answer = answers.removeFirst()
        guard answer == .hold else { return answer }
        let released = await held.wait()
        guard released != .hold else {
            Issue.record("FakeClop's held request was released with .hold")
            return Self.cancelledAnswer
        }
        return released
    }
}
