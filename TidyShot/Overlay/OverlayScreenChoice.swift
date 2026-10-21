import CoreGraphics

/// The Overlay tab's `Show on` (spec 2.9).
nonisolated enum OverlayDisplayChoice: String, CaseIterable, Identifiable, Sendable {
    case capture, pointer, main

    var id: String { rawValue }

    var title: String {
        switch self {
        case .capture: "Display of the capture"
        case .pointer: "Display with the pointer"
        case .main: "Main display"
        }
    }
}

/// Picks the screen for the card stack, as an index into `NSScreen.screens`
/// (`screenDisplayIDs` in the same order; index 0 is the main display).
nonisolated enum OverlayScreenChoice {
    /// `.capture`: the screen showing `captureDisplayID`, else the pointer's, else 0.
    /// `.pointer`: the pointer's screen, else 0. `.main`: 0. A `pointerIndex` outside the list
    /// counts as none.
    static func index(choice: OverlayDisplayChoice, captureDisplayID: CGDirectDisplayID?,
                      pointerIndex: Int?, screenDisplayIDs: [CGDirectDisplayID]) -> Int {
        let pointer = pointerIndex.flatMap { screenDisplayIDs.indices.contains($0) ? $0 : nil }
        switch choice {
        case .capture:
            if let captureDisplayID, let index = screenDisplayIDs.firstIndex(of: captureDisplayID) {
                return index
            }
            return pointer ?? 0
        case .pointer:
            return pointer ?? 0
        case .main:
            return 0
        }
    }
}
