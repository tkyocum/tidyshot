import CoreGraphics
import Foundation
import Testing
@testable import TidyShot

/// The live preview keeps only its newest rows: the panel shows at most a few hundred of them,
/// and a preview as tall as a 65,536 px capture would exceed a GPU texture.
struct PreviewRowsTests {
    /// A strip `height` rows tall and 3 wide whose every byte is `mark`.
    func strip(height: Int, mark: UInt8) -> PreviewStrip {
        PreviewStrip(width: 3, height: height, bgra: Data(repeating: mark, count: 3 * height * 4))
    }

    @Test func theImageIsTheNewestRowsOnly() throws {
        let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!
        #expect(ScrollCaptureLimits.previewMaxRows == 2048)
        var rows = PreviewRows(maxRows: 10)
        rows.append(strip(height: 4, mark: 1))
        #expect(try #require(rows.image(colorSpace: sRGB)).height == 4)
        for mark in UInt8(2)...UInt8(9) {
            rows.append(strip(height: 4, mark: mark))
            #expect(rows.height <= 20)
        }
        let image = try #require(rows.image(colorSpace: sRGB))
        #expect(image.width == 3)
        #expect(image.height == 10)
        let data = try #require(image.dataProvider?.data) as Data
        // Marks 7, 8 and 9 are the newest 12 rows; the image starts two rows into mark 7.
        #expect(data.first == 7)
        #expect(data[2 * 12] == 8)
        #expect(data.last == 9)
    }

    @Test func aStripOfAnotherWidthIsIgnored() {
        var rows = PreviewRows(maxRows: 10)
        rows.append(strip(height: 4, mark: 1))
        rows.append(PreviewStrip(width: 5, height: 2, bgra: Data(count: 40)))
        #expect(rows.height == 4)
        #expect(!rows.isEmpty)
    }
}
