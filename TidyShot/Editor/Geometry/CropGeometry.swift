import CoreGraphics
import Foundation

/// The crop rect, in image pixels with a top-left origin. The model stores `integralCrop` output and
/// the flattener crops to `integralCrop` again, so the readout, the document and the export agree
/// on the pixels kept.
nonisolated enum CropGeometry {
    /// `rect` standardized and cut to an image of `imageSize`; `.zero` when nothing of it is inside.
    static func clamped(_ rect: CGRect, to imageSize: CGSize) -> CGRect {
        guard !rect.isNull, !rect.isInfinite else { return .zero }
        let cut = rect.standardized.intersection(CGRect(origin: .zero, size: imageSize))
        return cut.isEmpty ? .zero : cut
    }

    /// `rect` moved by `delta` with its size kept, then pushed back inside the image. A rect larger
    /// than the image is clamped instead.
    static func moved(_ rect: CGRect, by delta: CGVector, within imageSize: CGSize) -> CGRect {
        let r = rect.standardized
        guard r.width <= imageSize.width, r.height <= imageSize.height else { return clamped(r, to: imageSize) }
        let x = min(max(r.minX + delta.dx, 0), imageSize.width - r.width)
        let y = min(max(r.minY + delta.dy, 0), imageSize.height - r.height)
        return CGRect(x: x, y: y, width: r.width, height: r.height)
    }

    /// Each edge of `rect` rounded to the nearest whole pixel, then cut to the image; `.zero` when
    /// nothing is left. These are the pixels export keeps, and what the readout counts.
    static func snapped(_ rect: CGRect, in imageSize: CGSize) -> CGRect {
        guard !rect.isNull, !rect.isInfinite else { return .zero }
        let r = rect.standardized
        let minX = r.minX.rounded()
        let minY = r.minY.rounded()
        let edges = CGRect(x: minX, y: minY, width: r.maxX.rounded() - minX, height: r.maxY.rounded() - minY)
        return clamped(edges, to: imageSize)
    }

    /// What the document stores and export crops to: `snapped`, or nil when there is no crop,
    /// nothing is left, or the whole image is kept. A crop dragged back to the whole capture
    /// therefore stores nil and changes nothing.
    static func integralCrop(_ rect: CGRect?, in imageSize: CGSize) -> CGRect? {
        guard let rect else { return nil }
        let kept = snapped(rect, in: imageSize)
        guard !kept.isEmpty, kept != CGRect(origin: .zero, size: imageSize) else { return nil }
        return kept
    }

    /// The readout beside the crop: width and height in image pixels, for example "1280 × 720".
    static func readout(for rect: CGRect) -> String {
        "\(Int(rect.width.rounded())) × \(Int(rect.height.rounded()))"
    }

    /// The nearest of `rect`'s eight handles (`HitTester.boxHandles` order) within `tolerance`.
    static func handle(of rect: CGRect, at point: CGPoint, tolerance: CGFloat) -> Int? {
        HitTester.nearestHandle(in: HitTester.boxHandles(rect), to: point, tolerance: tolerance)
    }

    /// What a press does when an applied crop dims part of the capture.
    enum Press: Equatable, Sendable {
        /// The tool gets the press where it landed: inside the crop, or on a handle of the selection.
        case asPressed
        /// The tool gets the press moved to the crop's edge, so a drag that starts outside begins there.
        case clampedToEdge
        /// Select: the press lands on nothing visible, so the selection goes and the tool never sees it.
        case deselect
        /// Nothing happens.
        case ignore
    }

    /// How a press at `point` is handled under `crop`, the applied crop (nil: none, or Crop is open and
    /// shows the whole capture). Outside the crop Select deselects unless the press is on a handle of
    /// `selected`, Text and Counter ignore it, and the drawing tools and Spotlight start at the edge.
    static func press(at point: CGPoint, crop: CGRect?, tool: EditorTool, selected: Annotation?,
                      tolerance: CGFloat) -> Press {
        guard let crop else { return .asPressed }
        let inside = point.x >= crop.minX && point.x <= crop.maxX && point.y >= crop.minY && point.y <= crop.maxY
        if inside { return .asPressed }
        switch tool {
        case .select:
            if let selected, case .handle? = HitTester.hit(selected, at: point, tolerance: tolerance) {
                return .asPressed
            }
            return .deselect
        case .text, .counter:
            return .ignore
        case .redact, .pixelate, .blur, .spotlight, .rectangle, .arrow, .ellipse, .line, .pencil, .highlighter, .crop:
            return .clampedToEdge
        }
    }

    /// `point` moved to the nearest point of `crop`.
    static func clamped(_ point: CGPoint, to crop: CGRect) -> CGPoint {
        CGPoint(x: min(max(point.x, crop.minX), crop.maxX), y: min(max(point.y, crop.minY), crop.maxY))
    }
}
