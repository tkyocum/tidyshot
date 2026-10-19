import CoreGraphics

nonisolated enum OverlayCorner: String, CaseIterable, Identifiable, Sendable {
    case topLeft, topRight, bottomLeft, bottomRight

    var id: String { rawValue }

    var title: String {
        switch self {
        case .topLeft: "Top left"
        case .topRight: "Top right"
        case .bottomLeft: "Bottom left"
        case .bottomRight: "Bottom right"
        }
    }
}

/// Where the Quick Access panel goes. `visibleFrame` is an AppKit screen rect (origin bottom-left).
nonisolated enum OverlayGeometry {
    static func frame(size: CGSize, corner: OverlayCorner, in visibleFrame: CGRect, margin: CGFloat = 16) -> CGRect {
        let x: CGFloat
        let y: CGFloat
        switch corner {
        case .topLeft, .bottomLeft:
            x = visibleFrame.minX + margin
        case .topRight, .bottomRight:
            x = visibleFrame.maxX - margin - size.width
        }
        switch corner {
        case .topLeft, .topRight:
            y = visibleFrame.maxY - margin - size.height
        case .bottomLeft, .bottomRight:
            y = visibleFrame.minY + margin
        }
        return CGRect(origin: CGPoint(x: x, y: y), size: size)
    }
}
