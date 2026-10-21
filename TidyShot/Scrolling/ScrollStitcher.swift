import Foundation

/// The finished stitch: `height` rows of `width` BGRA pixels, rows packed, blue first.
nonisolated struct StitchedImage: Sendable {
    let width: Int
    let height: Int
    let bgra: Data
}

/// What one `ScrollStitcher.add` did.
nonisolated struct StitchStep: Equatable, Sendable {
    /// The finder's verdict. A `.moved` with `dy <= 0` is a scroll back up and commits nothing.
    let match: OverlapMatch
    /// Output rows this call appended.
    let committedRows: Int
    /// The output has reached `maxPixelHeight`.
    let isFull: Bool
}

/// Rows committed since the last `previewRows` call, box-downscaled for the live preview.
nonisolated struct PreviewStrip: Equatable, Sendable {
    let width: Int
    let height: Int
    let bgra: Data
    var isEmpty: Bool { height == 0 }
}

/// Builds the tall image from frames of a scrolling area (spec 2.8, Stitcher). Pure.
///
/// Output row equals content row of the first frame. The stitcher holds the last accepted frame
/// and its content offset, and commits rows of that frame, from where the output stops up to the
/// band end, whenever a new frame has moved forward. Scrolling back, stillness and a lost place
/// commit nothing and matching stays against the last accepted frame, so scrolling back into
/// overlap recovers.
nonisolated struct ScrollStitcher: Sendable {
    let width: Int
    let maxPixelHeight: Int
    /// Output rows written so far.
    private(set) var committedHeight = 0
    var isFull: Bool { committedHeight >= maxPixelHeight }

    private var output = Data()
    private var last: ScrollFrame
    /// Content row of `last`'s row 0.
    private var lastOffset = 0
    private var lastDy: Int?
    private var previewCursor = 0
    private let finder: OverlapFinder

    init(first: ScrollFrame, maxPixelHeight: Int = ScrollCaptureLimits.maxPixelHeight,
         finder: OverlapFinder = OverlapFinder()) {
        precondition(maxPixelHeight > 0)
        width = first.width
        self.maxPixelHeight = maxPixelHeight
        self.finder = finder
        last = first
        // Reserved for the cap; the pages are committed only as rows are written.
        output.reserveCapacity(first.width * 4 * maxPixelHeight)
    }

    /// Matches `frame` against the last accepted frame and commits what it newly shows.
    /// `predicted` is the expected shift in pixels (auto mode passes the posted step); without it
    /// the previous accepted shift is used.
    mutating func add(_ frame: ScrollFrame, predicted: Int? = nil) -> StitchStep {
        if isFull { return StitchStep(match: .still, committedRows: 0, isFull: true) }
        #if DEBUG
        ScrollDiag.dumpPair(previous: last, current: frame)
        let findStart = ContinuousClock.now
        #endif
        let match = finder.find(previous: last, current: frame, predicted: predicted ?? lastDy)
        #if DEBUG
        ScrollDiag.log("stitch find=\(ScrollDiag.ms(since: findStart))ms predicted=\(predicted.map(String.init) ?? "nil") lastDy=\(lastDy.map(String.init) ?? "nil") lastOffset=\(lastOffset) committedHeight=\(committedHeight) -> \(ScrollDiag.describe(match))")
        #endif
        var committed = 0
        if case .moved(let dy, _, let bandEnd, _) = match, dy > 0 {
            committed = commit(from: last, offset: lastOffset, upTo: bandEnd)
            lastOffset += dy
            lastDy = dy
            last = frame
        }
        return StitchStep(match: match, committedRows: committed, isFull: isFull)
    }

    /// Commits the last frame down to its bottom, footer included, and returns the image.
    mutating func finish() -> StitchedImage {
        _ = commit(from: last, offset: lastOffset, upTo: last.height)
        return StitchedImage(width: width, height: committedHeight, bgra: output)
    }

    /// Appends rows of `frame` (whose row 0 is content row `offset`) from the first row the output
    /// does not have yet up to `end`, never past `maxPixelHeight`. Starting from the output's end,
    /// not from the pair's header height, keeps the output contiguous even when one pair over-reads
    /// a header or footer (blank rows equal at the same y).
    private mutating func commit(from frame: ScrollFrame, offset: Int, upTo end: Int) -> Int {
        let start = max(committedHeight - offset, 0)
        let stop = min(end, maxPixelHeight - offset)
        guard start < stop else { return 0 }
        let rowBytes = width * 4
        frame.bgra.withUnsafeBytes { raw in
            output.append(raw.baseAddress!.advanced(by: start * rowBytes).assumingMemoryBound(to: UInt8.self),
                          count: (stop - start) * rowBytes)
        }
        committedHeight = offset + stop
        return stop - start
    }

    /// A box-downscaled copy of the rows committed since the last call, at most `maxWidth` wide,
    /// for the live preview. The factor is a whole number, so a few trailing columns drop, and a
    /// remainder of rows waits for the next call, so the strips join without a seam.
    mutating func previewRows(maxWidth: Int = ScrollCaptureLimits.previewMaxWidth) -> PreviewStrip {
        let limit = max(1, maxWidth)
        let factor = (width + limit - 1) / limit
        let outWidth = width / factor
        let rows = (committedHeight - previewCursor) / factor * factor
        guard rows > 0 else { return PreviewStrip(width: outWidth, height: 0, bgra: Data()) }
        let outHeight = rows / factor
        let area = factor * factor
        var out = Data(count: outWidth * outHeight * 4)
        output.withUnsafeBytes { src in
            out.withUnsafeMutableBytes { dst in
                for oy in 0..<outHeight {
                    for ox in 0..<outWidth {
                        var sums = (0, 0, 0, 0)
                        for fy in 0..<factor {
                            let rowStart = ((previewCursor + oy * factor + fy) * width + ox * factor) * 4
                            for fx in 0..<factor {
                                let p = rowStart + fx * 4
                                sums.0 += Int(src[p]); sums.1 += Int(src[p + 1])
                                sums.2 += Int(src[p + 2]); sums.3 += Int(src[p + 3])
                            }
                        }
                        let o = (oy * outWidth + ox) * 4
                        dst[o] = UInt8((sums.0 + area / 2) / area); dst[o + 1] = UInt8((sums.1 + area / 2) / area)
                        dst[o + 2] = UInt8((sums.2 + area / 2) / area); dst[o + 3] = UInt8((sums.3 + area / 2) / area)
                    }
                }
            }
        }
        previewCursor += rows
        return PreviewStrip(width: outWidth, height: outHeight, bgra: out)
    }
}
