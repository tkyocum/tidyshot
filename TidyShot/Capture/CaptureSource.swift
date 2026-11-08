import CoreGraphics
import ScreenCaptureKit
/// The displays and windows on screen as values, in ScreenCaptureKit's order; `live` is the content
/// they were read from (the overlay's window picker uses it), nil for content a test built.
struct ScreenContent {
    let displays: [CaptureDisplay]
    let windows: [CaptureWindow]
    let live: SCShareableContent?
    init(displays: [CaptureDisplay], windows: [CaptureWindow]) { self.displays = displays; self.windows = windows; live = nil }
    init(_ content: SCShareableContent) {
        displays = content.displays.map(CaptureDisplay.init); windows = content.windows.map(CaptureWindow.init); live = content
    }

    /// The display with `id`; nil once it is disconnected.
    func display(id: CGDirectDisplayID) -> CaptureDisplay? {
        displays.first { $0.displayID == id }
    }

    /// The window with `id`; nil once it has closed or left the screen.
    func window(id: CGWindowID) -> CaptureWindow? {
        windows.first { $0.windowID == id }
    }
}
/// What the capture flows read of the screen. `CaptureEngine` in the app; `FakeCaptureSource` in the suite.
protocol CaptureSource: AnyObject {
    func screenContent() async throws -> ScreenContent
    func capture(_ target: CaptureTarget, options: CaptureOptions, excludingWindows: [CaptureWindow]) async throws -> CaptureResult
    func windows(numbers: Set<CGWindowID>) async -> [CaptureWindow]  // retried briefly; whatever was found
    func displayUnderPointer(in displays: [CaptureDisplay]) -> CaptureDisplay?
    var isScreenRecordingGranted: Bool { get }
}
