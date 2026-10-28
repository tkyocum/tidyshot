import Foundation

/// An 8-bit sRGB colour, as a GIF colour table holds it.
nonisolated struct GIFColour: Hashable, Sendable {
    var r: UInt8
    var g: UInt8
    var b: UInt8
}

/// The GIF's one global colour table: up to 255 colours, with the next index left for
/// transparency.
nonisolated struct GIFPalette: Equatable, Sendable {
    static let maximumColours = 255

    let colours: [GIFColour]

    init(colours: [GIFColour]) {
        precondition((1...Self.maximumColours).contains(colours.count), "A palette holds 1 to 255 colours")
        self.colours = colours
    }

    /// The index just after the colours: 255 for a full palette.
    var transparentIndex: UInt8 { UInt8(colours.count) }

    /// The smallest `b` ≥ 1 with `2^b` ≥ the colours plus the transparent index.
    var tableBits: Int {
        var bits = 1
        while 1 << bits < colours.count + 1 { bits += 1 }
        return bits
    }

    /// The global table: `2^tableBits` RGB entries, padded with black.
    var tableBytes: [UInt8] {
        var bytes = [UInt8](repeating: 0, count: (1 << tableBits) * 3)
        for (index, colour) in colours.enumerated() {
            bytes[index * 3] = colour.r
            bytes[index * 3 + 1] = colour.g
            bytes[index * 3 + 2] = colour.b
        }
        return bytes
    }

    /// The entry with the least squared RGB distance to `colour`, the lowest index on a tie.
    func nearest(_ colour: GIFColour) -> UInt8 {
        let r = Int(colour.r), g = Int(colour.g), b = Int(colour.b)
        return colours.withUnsafeBufferPointer { entries in
            var best = 0
            var bestDistance = Int.max
            for index in 0..<entries.count {
                let entry = entries[index]
                let dr = Int(entry.r) &- r, dg = Int(entry.g) &- g, db = Int(entry.b) &- b
                let distance = dr &* dr &+ dg &* dg &+ db &* db
                if distance < bestDistance {
                    bestDistance = distance
                    best = index
                }
            }
            return UInt8(best)
        }
    }
}

/// Pass 1's palette. Sampled frames go into a histogram of 6 bits per channel; `build` splits it
/// into at most 255 boxes and refines their means with a few k-means passes. No entries are spent
/// on codec noise: a box tighter than `minimumBoxSpread` is never split.
nonisolated struct GIFPaletteBuilder {
    private static let binCount = 1 << 18

    let minimumBoxSpread: Double
    let refinementPasses: Int

    /// Pixels per bin. 32 frames of 4096 × 4096 fit in 32 bits.
    private var counts: [UInt32]
    /// The sums of each bin's exact colours, three per bin, so a bin stands for the mean of what
    /// fell in it.
    private var sums: [UInt64]

    init(minimumBoxSpread: Double = 2, refinementPasses: Int = 4) {
        self.minimumBoxSpread = minimumBoxSpread
        self.refinementPasses = refinementPasses
        counts = [UInt32](repeating: 0, count: Self.binCount)
        sums = [UInt64](repeating: 0, count: Self.binCount * 3)
    }

    /// Adds every pixel of an RGBA frame (4 bytes a pixel; the fourth is ignored).
    mutating func add(rgba: UnsafeBufferPointer<UInt8>) {
        let pixelCount = rgba.count / 4
        counts.withUnsafeMutableBufferPointer { counts in
            sums.withUnsafeMutableBufferPointer { sums in
                for pixel in 0..<pixelCount {
                    let r = rgba[pixel &* 4], g = rgba[pixel &* 4 &+ 1], b = rgba[pixel &* 4 &+ 2]
                    let bin = Int(r >> 2) << 12 | Int(g >> 2) << 6 | Int(b >> 2)
                    counts[bin] &+= 1
                    sums[bin &* 3] &+= UInt64(r)
                    sums[bin &* 3 &+ 1] &+= UInt64(g)
                    sums[bin &* 3 &+ 2] &+= UInt64(b)
                }
            }
        }
    }

    /// A greedy variance split over the non-empty bins: the box with the largest
    /// `sqrt(count)`-weighted squared error is split on the axis and at the position that minimise
    /// the halves' summed error, until there are 255 boxes or none can be split. No pixels give one
    /// black entry.
    ///
    /// `reserved` colours come first, in order and exactly (R3's click ring colours); the split
    /// then makes at most `255 − reserved.count` boxes, and drops any that equal a reserved colour.
    /// With colours reserved, no pixels give the reserved colours alone.
    func build(reserving reserved: [GIFColour] = []) -> GIFPalette {
        precondition(reserved.count <= GIFPalette.maximumColours, "At most 255 reserved colours")
        let boxLimit = GIFPalette.maximumColours - reserved.count
        var points = Points()
        for bin in 0..<Self.binCount where counts[bin] > 0 {
            let count = Double(counts[bin])
            points.append(r: Double(sums[bin * 3]) / count, g: Double(sums[bin * 3 + 1]) / count,
                          b: Double(sums[bin * 3 + 2]) / count, count: count)
        }
        guard points.count > 0, boxLimit > 0 else {
            return GIFPalette(colours: reserved.isEmpty ? [GIFColour(r: 0, g: 0, b: 0)] : reserved)
        }

        var order = Array(0..<points.count)
        var boxes = [points.box(order[...], lo: 0)]
        while boxes.count < boxLimit {
            var pick = -1
            var worst = 0.0
            for (index, box) in boxes.enumerated()
            where box.hi - box.lo >= 2 && box.error > worst && box.spread >= minimumBoxSpread {
                worst = box.error
                pick = index
            }
            guard pick >= 0 else { break }
            let box = boxes[pick]
            guard let split = points.bestSplit(order[box.lo..<box.hi]) else {
                boxes[pick].error = 0
                continue
            }
            order.replaceSubrange(box.lo..<box.hi, with: split.order)
            let middle = box.lo + split.position
            boxes[pick] = points.box(order[box.lo..<middle], lo: box.lo)
            boxes.append(points.box(order[middle..<box.hi], lo: middle))
        }

        // Each box's population-weighted mean, so a dominant exact colour stays exact.
        var means = boxes.map { points.mean(order[$0.lo..<$0.hi]) }
        for _ in 0..<refinementPasses {
            means = points.refine(means)
        }
        var colours = reserved
        var seen = Set(reserved)
        for mean in means {
            let colour = GIFColour(r: Self.level(mean.r), g: Self.level(mean.g), b: Self.level(mean.b))
            if seen.insert(colour).inserted { colours.append(colour) }
        }
        return GIFPalette(colours: colours)
    }

    private static func level(_ value: Double) -> UInt8 {
        UInt8(max(0, min(255, value.rounded())))
    }

    /// The non-empty bins as points at their mean colours, weighted by their counts.
    private struct Points {
        var r: [Double] = []
        var g: [Double] = []
        var b: [Double] = []
        /// Pixel counts: the weight for means and spreads.
        var counts: [Double] = []
        /// `sqrt(count)`: the weight for choosing and placing splits.
        var splitWeights: [Double] = []

        var count: Int { r.count }

        mutating func append(r: Double, g: Double, b: Double, count: Double) {
            self.r.append(r)
            self.g.append(g)
            self.b.append(b)
            counts.append(count)
            splitWeights.append(count.squareRoot())
        }

        struct Box {
            var lo: Int
            var hi: Int
            /// The `sqrt(count)`-weighted squared error.
            var error: Double
            /// The population RMS distance of the box's pixels from its mean.
            var spread: Double
        }

        /// Weighted sums: weight, the three coordinates, and the squared length.
        struct Sums {
            var weight = 0.0, r = 0.0, g = 0.0, b = 0.0, squares = 0.0

            mutating func add(_ points: Points, _ index: Int, weight w: Double) {
                let pr = points.r[index], pg = points.g[index], pb = points.b[index]
                weight += w
                r += w * pr
                g += w * pg
                b += w * pb
                squares += w * (pr * pr + pg * pg + pb * pb)
            }

            static func - (lhs: Sums, rhs: Sums) -> Sums {
                Sums(weight: lhs.weight - rhs.weight, r: lhs.r - rhs.r, g: lhs.g - rhs.g, b: lhs.b - rhs.b,
                     squares: lhs.squares - rhs.squares)
            }

            var error: Double {
                weight > 0 ? max(0, squares - (r * r + g * g + b * b) / weight) : 0
            }
        }

        func sums(_ indices: ArraySlice<Int>, weights: [Double]) -> Sums {
            var sums = Sums()
            for index in indices { sums.add(self, index, weight: weights[index]) }
            return sums
        }

        func box(_ indices: ArraySlice<Int>, lo: Int) -> Box {
            let population = sums(indices, weights: counts)
            return Box(lo: lo, hi: lo + indices.count, error: sums(indices, weights: splitWeights).error,
                       spread: (population.error / max(population.weight, 1)).squareRoot())
        }

        /// The axis and position that minimise the halves' summed error, as the box's indices
        /// sorted on that axis and the first index of the upper half. Nil when every point
        /// shares its coordinates.
        func bestSplit(_ indices: ArraySlice<Int>) -> (order: [Int], position: Int)? {
            let total = sums(indices, weights: splitWeights)
            var best: (order: [Int], position: Int)?
            var bestError = Double.infinity
            for axis in [r, g, b] {
                let sorted = indices.sorted { axis[$0] < axis[$1] }
                var lower = Sums()
                for position in 0..<(sorted.count - 1) {
                    lower.add(self, sorted[position], weight: splitWeights[sorted[position]])
                    if axis[sorted[position]] == axis[sorted[position + 1]] { continue }
                    let error = lower.error + (total - lower).error
                    if error < bestError {
                        bestError = error
                        best = (sorted, position + 1)
                    }
                }
            }
            return best
        }

        func mean(_ indices: ArraySlice<Int>) -> (r: Double, g: Double, b: Double) {
            let population = sums(indices, weights: counts)
            return (population.r / population.weight, population.g / population.weight,
                    population.b / population.weight)
        }

        /// One k-means pass: each point goes to its nearest mean, weighted by its count. A mean
        /// that gets no points stays where it is.
        func refine(_ means: [(r: Double, g: Double, b: Double)]) -> [(r: Double, g: Double, b: Double)] {
            var totals = [Sums](repeating: Sums(), count: means.count)
            for index in 0..<count {
                var nearest = 0
                var nearestDistance = Double.infinity
                for (candidate, mean) in means.enumerated() {
                    let dr = r[index] - mean.r, dg = g[index] - mean.g, db = b[index] - mean.b
                    let distance = dr * dr + dg * dg + db * db
                    if distance < nearestDistance {
                        nearestDistance = distance
                        nearest = candidate
                    }
                }
                totals[nearest].add(self, index, weight: counts[index])
            }
            return zip(means, totals).map { mean, total in
                total.weight > 0 ? (total.r / total.weight, total.g / total.weight, total.b / total.weight) : mean
            }
        }
    }
}
