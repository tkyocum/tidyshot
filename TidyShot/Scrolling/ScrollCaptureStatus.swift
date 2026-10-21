import Foundation

/// The panel's status line for each session state, and the size readout (spec 2.8, Exact strings).
nonisolated enum ScrollCaptureStatus: Equatable, Sendable {
    case readyManual
    case readyAuto
    case manualCapturing
    /// Manual mode lost its place; clears on the next movement.
    case manualLost
    case autoScrolling
    /// Auto mode is waiting for the pointer, or paused because it left.
    case autoPaused
    case autoHandedOver
    case autoReachedEnd
    case heightLimit
    case finishing

    static func ready(autoScroll: Bool) -> ScrollCaptureStatus {
        autoScroll ? .readyAuto : .readyManual
    }

    var text: String {
        switch self {
        case .readyManual: "Click Start, then scroll down slowly."
        case .readyAuto: "Click Start, then hold the pointer over the area."
        case .manualCapturing: "Scroll down slowly. Click Done at the end."
        case .manualLost: "Too fast. Scroll back up a little."
        case .autoScrolling: "Scrolling… Move the pointer away to pause."
        case .autoPaused: "Paused. Move the pointer over the area to continue."
        case .autoHandedOver: "Auto-scroll lost its place. Scroll back up a little, or click Done."
        case .autoReachedEnd: "Reached the end."
        case .heightLimit: "Reached the \(Self.grouped(ScrollCaptureLimits.maxPixelHeight, locale: Locale(identifier: "en_US"))) pixel limit."
        case .finishing: "Stitching…"
        }
    }

    /// `2,560 × 7,340 px`: the stitched image's size in pixels, with the locale's digit grouping.
    static func sizeText(width: Int, height: Int, locale: Locale = .current) -> String {
        "\(grouped(width, locale: locale)) × \(grouped(height, locale: locale)) px"
    }

    private static func grouped(_ value: Int, locale: Locale) -> String {
        value.formatted(.number.grouping(.automatic).locale(locale))
    }
}
