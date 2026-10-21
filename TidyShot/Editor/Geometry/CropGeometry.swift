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
        var best: (index: Int, distance: CGFloat)?
        for (index, handle) in HitTester.boxHandles(rect).enumerated() {
            let distance = hypot(point.x - handle.x, point.y - handle.y)
            if distance <= tolerance, distance < (best?.distance ?? .infinity) {
                best = (index, distance)
            }
        }
        return best?.index
    }
}
