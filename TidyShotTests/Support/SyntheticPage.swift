import Foundation
@testable import TidyShot

/// A tall synthetic page and the frames a scrolling viewer shows of it, as the stitching probe
/// rendered them (spec 2.8, Tests). A frame is `width` by `height` pixels: a sticky header on top,
/// a sticky footer at the bottom, a fixed sidebar on the left and a scrollbar on the right whose
/// thumb moves with the scroll offset. In between, the band shows rows `offset..<offset + band` of
/// the page. An optional animated square sits at a fixed screen position and changes every frame.
///
/// The page is text lines (pixel rows that differ glyph row by glyph row), blank gaps, repeated
/// list items and noisy image blocks, so it has the content that defeats naive matching.
nonisolated struct SyntheticPage {
    let width: Int
    let height: Int
    let header: Int
    let footer: Int
    let sidebar: Int
    let scrollbar: Int
    let pageHeight: Int
    let spinnerWidth: Int
    let spinnerHeight: Int
    let spinnerX: Int
    /// Rows below the header where the spinner starts.
    let spinnerY: Int
    /// The page's pixels, `pageWidth * pageHeight`, grey.
    let page: [UInt8]
    private var frameNumber = 0

    var bandHeight: Int { height - header - footer }
    var pageWidth: Int { width - sidebar - scrollbar }
    /// The largest offset the viewer can scroll to.
    var maxOffset: Int { pageHeight - bandHeight }
    /// The finder these frames need: it ignores the scrollbar's columns plus a pixel or two.
    var finder: OverlapFinder { OverlapFinder(scrollbarColumns: scrollbar + 2) }

    init(width: Int = 160, height: Int = 900, header: Int = 80, footer: Int = 50, sidebar: Int = 40,
         scrollbar: Int = 8, pageHeight: Int = 9000, seed: UInt64 = 42, period: Int? = nil) {
        self.width = width
        self.height = height
        self.header = header
        self.footer = footer
        self.sidebar = sidebar
        self.scrollbar = scrollbar
        self.pageHeight = pageHeight
        spinnerWidth = 12
        spinnerHeight = 40
        spinnerX = 100
        spinnerY = 200
        let pageWidth = width - sidebar - scrollbar
        page = period.map { Self.periodicPage(width: pageWidth, height: pageHeight, period: $0, seed: seed) }
            ?? Self.mixedPage(width: pageWidth, height: pageHeight, seed: seed)
    }

    // MARK: Fixed pieces

    func headerPixel(_ x: Int, _ y: Int) -> UInt8 { UInt8(100 + (x * 7 + y * 13) % 120) }
    func footerPixel(_ x: Int, _ y: Int) -> UInt8 { UInt8(60 + (x * 11 + y * 5) % 90) }
    func sidebarPixel(_ x: Int, _ y: Int) -> UInt8 { UInt8(200 + (x + y) % 40) }

    // MARK: Frames

    /// The frame at scroll offset `offset`. `thumbTop` overrides where the scrollbar thumb is drawn.
    mutating func frame(at offset: Int, animated: Bool = true, scrollbarVisible: Bool = true,
                        thumbTop: Int? = nil) -> ScrollFrame {
        frameNumber += 1
        var generator = LCG(seed: UInt64(frameNumber) &* 7919)
        var bgra = [UInt8](repeating: 255, count: width * height * 4)
        let thumb = thumbTop ?? header + (offset * bandHeight) / pageHeight
        for y in 0..<height {
            for x in 0..<width {
                let value: UInt8
                if y < header {
                    value = headerPixel(x, y)
                } else if y >= height - footer {
                    value = footerPixel(x, y)
                } else if x < sidebar {
                    value = sidebarPixel(x, y)
                } else if x >= width - scrollbar {
                    value = scrollbarVisible && y >= thumb && y < thumb + 20 ? 120 : 245
                } else {
                    let pageY = offset + (y - header)
                    value = pageY < pageHeight ? page[pageY * pageWidth + (x - sidebar)] : 250
                }
                let i = (y * width + x) * 4
                bgra[i] = value; bgra[i + 1] = value; bgra[i + 2] = value
            }
        }
        if animated {
            for y in (header + spinnerY)..<(header + spinnerY + spinnerHeight) {
                for x in spinnerX..<(spinnerX + spinnerWidth) {
                    let v = UInt8(truncatingIfNeeded: generator.next())
                    let i = (y * width + x) * 4
                    bgra[i] = v; bgra[i + 1] = v; bgra[i + 2] = v
                }
            }
        }
        return ScrollFrame(bgra: Data(bgra), width: width, height: height, bytesPerRow: width * 4)
    }

    /// An all-blank frame of the same size.
    func blankFrame() -> ScrollFrame {
        ScrollFrame(bgra: Data(repeating: 255, count: width * height * 4), width: width, height: height,
                    bytesPerRow: width * 4)
    }

    // MARK: Expected output

    struct Comparison {
        let expectedHeight: Int
        let actualHeight: Int
        /// Page-column pixels that differ from the ideal tall image.
        let mismatched: Int
        /// Of those, the ones outside the animated square's columns.
        let mismatchedOutsideSpinner: Int
    }

    /// Compares a stitched image with the ideal one for a scroll that reached `reached`:
    /// header, page rows `0..<reached + band`, footer. Only the page's columns are compared; the
    /// sidebar and the scrollbar differ by design.
    func compare(_ out: StitchedImage, reached: Int) -> Comparison {
        let expectedHeight = header + reached + bandHeight + footer
        var bad = 0, badOutside = 0
        for y in 0..<min(out.height, expectedHeight) {
            for x in sidebar..<(width - scrollbar) {
                let want: UInt8
                if y < header { want = headerPixel(x, y) }
                else if y >= expectedHeight - footer { want = footerPixel(x, y - (expectedHeight - height)) }
                else { want = page[(y - header) * pageWidth + (x - sidebar)] }
                if out.bgra[(y * out.width + x) * 4] != want {
                    bad += 1
                    if !(spinnerX..<(spinnerX + spinnerWidth)).contains(x) { badOutside += 1 }
                }
            }
        }
        return Comparison(expectedHeight: expectedHeight, actualHeight: out.height, mismatched: bad,
                          mismatchedOutsideSpinner: badOutside)
    }

    /// The B channel of output pixel (x, y).
    static func value(_ image: StitchedImage, _ x: Int, _ y: Int) -> UInt8 { image.bgra[(y * image.width + x) * 4] }

    // MARK: Page generators

    struct LCG {
        var state: UInt64
        init(seed: UInt64) { state = seed }
        mutating func next() -> UInt64 {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return state >> 33
        }
    }

    /// Text, gaps, list items and image blocks, as the probe generated them.
    static func mixedPage(width: Int, height: Int, seed: UInt64) -> [UInt8] {
        var g = LCG(seed: seed)
        let margin = min(20, width / 8)
        var px = [UInt8](repeating: 250, count: width * height)
        var y = 0
        while y < height {
            let kind = g.next() % 10
            if kind < 5 {                       // a text line: 22 rows, glyph strokes differ per pixel row
                let lineHeight = 22
                for yy in y..<min(height, y + lineHeight) where (yy - y) > 4 && (yy - y) < 18 {
                    var x = margin
                    var g2 = LCG(seed: UInt64(y) &* 31 &+ seed)
                    while x < width - margin {
                        let run = Int(g2.next() % 14) + 3
                        let ink = g2.next() % 3 == 0
                        let glyph = Int(g2.next() % 97)
                        let r = yy - y
                        for xx in x..<min(width, x + run) {
                            px[yy * width + xx] = ink && ((xx * 3 + r * glyph) % 7 < 3) ? UInt8(30 + (glyph % 60)) : 250
                        }
                        x += run
                    }
                }
                y += lineHeight + 8
            } else if kind < 7 {                // a blank gap
                y += Int(g.next() % 60) + 10
            } else if kind < 9 {                // a repeated list item: identical rows
                let itemHeight = 40
                for yy in y..<min(height, y + itemHeight) {
                    for xx in margin..<(width / 2) {
                        px[yy * width + xx] = (yy - y) < 2 ? 180 : ((xx / 7 + (yy - y)) % 5 == 0 ? 90 : 240)
                    }
                }
                y += itemHeight
            } else {                            // an image block: gradient plus noise
                let blockHeight = Int(g.next() % 200) + 80
                for yy in y..<min(height, y + blockHeight) {
                    for xx in (2 * margin)..<(width - 2 * margin) { px[yy * width + xx] = UInt8((xx + yy * 3 + Int(g.next() % 7)) & 0xff) }
                }
                y += blockHeight + 10
            }
        }
        return px
    }

    /// `period` rows of noise repeated down the page, for tests of repeated content.
    static func periodicPage(width: Int, height: Int, period: Int, seed: UInt64) -> [UInt8] {
        var g = LCG(seed: seed)
        let base = (0..<(width * period)).map { _ in UInt8(truncatingIfNeeded: g.next()) }
        var px = [UInt8](repeating: 0, count: width * height)
        for y in 0..<height {
            for x in 0..<width { px[y * width + x] = base[(y % period) * width + x] }
        }
        return px
    }
}
