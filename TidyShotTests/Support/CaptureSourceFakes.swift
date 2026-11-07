import CoreGraphics
import Foundation
import Testing
@testable import TidyShot

nonisolated struct FakeCaptureError: LocalizedError, Sendable { var errorDescription: String? { "The fake source failed." } }
/// The capture source in the suite: ScreenCaptureKit, the screen and the pointer are never reached. Each read gives
/// `content` unless `contentFailures` has an error left; a capture is recorded, then throws `captureFailure` or answers
/// a red image of the target's `cgFrame` size at scale 1. The display under the pointer is the first one, and Screen
/// Recording is always granted.
final class FakeCaptureSource: CaptureSource {
    struct Capture: Equatable { let target: CaptureTarget; let options: CaptureOptions; let excludedWindowIDs: [CGWindowID] }
    static let display = CaptureDisplay(displayID: 1, frame: CGRect(x: 0, y: 0, width: 1440, height: 900))
    var content = ScreenContent(displays: [FakeCaptureSource.display], windows: [])
    var contentFailures: [any Error] = [], captureFailure: (any Error)?
    private(set) var contentReads = 0, captures: [Capture] = [], windowLookups: [Set<CGWindowID>] = []
    let isScreenRecordingGranted = true
    func screenContent() async throws -> ScreenContent {
        contentReads += 1; if !contentFailures.isEmpty { throw contentFailures.removeFirst() }; return content
    }
    func capture(_ target: CaptureTarget, options: CaptureOptions, excludingWindows: [CaptureWindow]) async throws -> CaptureResult {
        captures.append(Capture(target: target, options: options, excludedWindowIDs: excludingWindows.map(\.windowID)))
        if let captureFailure { throw captureFailure }
        let size = Geometry.pixelSize(points: target.cgFrame.size, scale: 1)
        return CaptureResult(image: try CoordinatorWorld.image(width: max(size.width, 1), height: max(size.height, 1)), scale: 1, target: target)
    }
    func windows(numbers: Set<CGWindowID>) async -> [CaptureWindow] { windowLookups.append(numbers); return content.windows.filter { numbers.contains($0.windowID) } }
    func displayUnderPointer(in displays: [CaptureDisplay]) -> CaptureDisplay? { displays.first }
}
/// The selection overlay in the suite: no window is built and the screen is never read. Every ask is kept; each answers
/// the next of `selections` or `choices` (nil, or none left, is Escape). While `holds` is set, `select` waits for
/// `answer(_:)`; a held overlay whose task is cancelled answers Escape, and a second while one is held records an issue.
/// No freeze snapshot and no overlay window exist.
final class FakeSelector: CaptureSelecting {
    struct Select: Equatable { let mode: SelectionMode; let freeze: CaptureOptions?; let preselect: CGRect?; var armed = true }
    struct AllInOne: Equatable { let freeze: CaptureOptions?; let preselect: CGRect?; let armed: Bool }
    private(set) var selects: [Select] = [], allInOnes: [AllInOne] = [], frozenAsked: [CGDirectDisplayID] = []
    private(set) var overlayLookups = 0, dismissCount = 0
    var selections: [Selection?] = [], choices: [AllInOneChoice?] = [], holds = false
    private var heldSelection: Selection?
    private let held = SingleWaiter(cancelled: false, secondEntry: "FakeSelector was asked again while an overlay was held")
    var isWaiting: Bool { held.isWaiting }
    func select(mode: SelectionMode, content: ScreenContent, freeze: CaptureOptions?, preselect: CGRect?,
                armed: Bool) async -> Selection? {
        selects.append(Select(mode: mode, freeze: freeze, preselect: preselect, armed: armed))
        guard holds else { return selections.isEmpty ? nil : selections.removeFirst() }
        guard await held.wait() else { return nil }
        defer { heldSelection = nil }; return heldSelection
    }
    func selectAllInOne(content: ScreenContent, freeze: CaptureOptions?, preselect: CGRect?, armed: Bool) async -> AllInOneChoice? {
        allInOnes.append(AllInOne(freeze: freeze, preselect: preselect, armed: armed))
        return choices.isEmpty ? nil : choices.removeFirst()
    }
    /// Answers the held `select`; with none held it only clears `holds`, so a test's `defer` can call it.
    func answer(_ selection: Selection?) { holds = false; heldSelection = selection; held.resume(true) }
    func frozenCapture(for displayID: CGDirectDisplayID) -> FrozenSnapshot? { frozenAsked.append(displayID); return nil }
    func overlayWindows() async -> [CaptureWindow] { overlayLookups += 1; return [] }
    func dismiss() { dismissCount += 1 }
}
