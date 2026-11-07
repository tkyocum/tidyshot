import Foundation

/// A rectangle of the GIF's logical screen, in pixels from the top left.
nonisolated struct GIFRect: Equatable, Sendable {
    var x: Int
    var y: Int
    var width: Int
    var height: Int
}

/// What changed from the frame a decoder shows to the next, inside the changed pixels' bounding box.
nonisolated struct GIFFrameChange: Equatable, Sendable {
    var rect: GIFRect
    /// The rectangle's indices, row by row, with the transparent index where nothing changed.
    var changedOnly: [UInt8]
    /// The rectangle's indices as now shown.
    var opaque: [UInt8]
}

/// Maps each frame to the palette, without dithering, and finds what changed since the frame a
/// decoder shows. A shown colour is kept while it is nearly as close to the source as the nearest
/// entry, so codec noise does not flip pixels between neighbouring entries.
nonisolated struct GIFFrameDiffer {
    /// A colour whose nearest entry has not been looked up yet. A palette holds at most 255
    /// colours, so `nearest` never returns 255.
    private static let unfilled = UInt8.max

    let width: Int
    let height: Int
    let palette: GIFPalette
    let hysteresis: Int

    /// The composed index frame a decoder shows, all `transparentIndex` before the first frame.
    private(set) var shown: [UInt8]

    /// Per pixel of the last frame: its new index, or `transparentIndex` where it did not change.
    private var changes: [UInt8]
    /// The returned rectangles' storage, reused once the caller lets go of the last change.
    private var changedOnly: [UInt8] = []
    private var opaque: [UInt8] = []
    /// `palette.nearest` for every 24-bit colour, filled as colours are met; it never changes a
    /// result. One byte per colour is 16 MB, less than one 4K BGRA frame, and the lookup is one load
    /// per pixel with no hash and no collision, so the 255-entry scan runs once per distinct colour.
    private var cache: [UInt8]

    init(width: Int, height: Int, palette: GIFPalette, hysteresis: Int = 4) {
        precondition(width > 0 && height > 0)
        self.width = width
        self.height = height
        self.palette = palette
        self.hysteresis = hysteresis
        shown = [UInt8](repeating: palette.transparentIndex, count: width * height)
        changes = [UInt8](repeating: palette.transparentIndex, count: width * height)
        cache = [UInt8](repeating: Self.unfilled, count: 1 << 24)
    }

    /// The change from `shown` to `rgba` (4 bytes a pixel, the fourth ignored), applied to `shown`,
    /// or nil when no pixel changes. The first call changes every pixel.
    mutating func next(rgba: UnsafeBufferPointer<UInt8>) -> GIFFrameChange? {
        precondition(rgba.count >= width * height * 4, "The frame is smaller than the GIF")
        let width = width, height = height
        let transparent = palette.transparentIndex
        let keep = Double(hysteresis)
        var minX = width, maxX = -1, minY = height, maxY = -1

        shown.withUnsafeMutableBufferPointer { shown in
        changes.withUnsafeMutableBufferPointer { changes in
        cache.withUnsafeMutableBufferPointer { cache in
        palette.colours.withUnsafeBufferPointer { entries in
            for y in 0..<height {
                var rowMin = width, rowMax = -1
                let rowStart = y &* width
                for x in 0..<width {
                    let pixel = rowStart &+ x
                    let r = rgba[pixel &* 4], g = rgba[pixel &* 4 &+ 1], b = rgba[pixel &* 4 &+ 2]
                    let key = Int(r) << 16 | Int(g) << 8 | Int(b)
                    var nearest = cache[key]
                    if nearest == Self.unfilled {
                        nearest = palette.nearest(GIFColour(r: r, g: g, b: b))
                        cache[key] = nearest
                    }
                    let current = shown[pixel]
                    var changed = nearest != current
                    if changed, current != transparent {
                        // Kept unless the shown colour is further from the source than the
                        // nearest entry by more than `hysteresis` (Euclidean RGB distance).
                        let toShown = Self.distance(entries[Int(current)], r, g, b)
                        let toNearest = Self.distance(entries[Int(nearest)], r, g, b)
                        changed = toShown > toNearest + keep
                    }
                    if changed {
                        changes[pixel] = nearest
                        shown[pixel] = nearest
                        if x < rowMin { rowMin = x }
                        rowMax = x
                    } else {
                        changes[pixel] = transparent
                    }
                }
                if rowMax >= 0 {
                    if y < minY { minY = y }
                    maxY = y
                    if rowMin < minX { minX = rowMin }
                    if rowMax > maxX { maxX = rowMax }
                }
            }
        }
        }
        }
        }

        guard maxX >= 0 else { return nil }
        let rect = GIFRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
        changedOnly.removeAll(keepingCapacity: true)
        opaque.removeAll(keepingCapacity: true)
        for y in rect.y..<rect.y + rect.height {
            let start = y * width + rect.x
            changedOnly.append(contentsOf: changes[start..<start + rect.width])
            opaque.append(contentsOf: shown[start..<start + rect.width])
        }
        return GIFFrameChange(rect: rect, changedOnly: changedOnly, opaque: opaque)
    }

    @inline(__always)
    private static func distance(_ entry: GIFColour, _ r: UInt8, _ g: UInt8, _ b: UInt8) -> Double {
        let dr = Int(entry.r) &- Int(r), dg = Int(entry.g) &- Int(g), db = Int(entry.b) &- Int(b)
        return Double(dr &* dr &+ dg &* dg &+ db &* db).squareRoot()
    }
}
