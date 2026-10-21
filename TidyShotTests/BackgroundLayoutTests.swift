import CoreGraphics
import Testing
@testable import TidyShot

struct BackgroundLayoutTests {
    func layout(_ width: Int, _ height: Int, padding: Double = 0, radius: Double = 0,
                aspect: BackgroundAspect = .auto, scale: CGFloat = 1) -> BackgroundLayout? {
        BackgroundLayout.make(contentSize: CGSize(width: width, height: height),
                              style: BackgroundStyle(padding: padding, cornerRadius: radius, aspect: aspect),
                              scale: scale)
    }

    @Test func paddingAtOneX() throws {
        let result = try #require(layout(200, 100, padding: 48))
        #expect(result.canvasSize == CGSize(width: 296, height: 196))
        #expect(result.contentRect == CGRect(x: 48, y: 48, width: 200, height: 100))
    }

    @Test func paddingAtTwoX() throws {
        let result = try #require(layout(400, 200, padding: 48, scale: 2))
        #expect(result.canvasSize == CGSize(width: 592, height: 392))
        #expect(result.contentRect == CGRect(x: 96, y: 96, width: 400, height: 200))
    }

    @Test func autoKeepsTheMinimumCanvas() throws {
        #expect(try #require(layout(200, 100)).canvasSize == CGSize(width: 200, height: 100))
    }

    @Test func eachRatioGrowsTheHeightOfWideContent() throws {
        let cases: [(BackgroundAspect, Int)] = [(.square, 200), (.fourThree, 150), (.threeTwo, 134),
                                                (.sixteenTen, 125), (.sixteenNine, 113)]
        for (aspect, height) in cases {
            let result = try #require(layout(200, 100, aspect: aspect))
            #expect(result.canvasSize == CGSize(width: 200, height: CGFloat(height)), "\(aspect)")
        }
    }

    @Test func contentNarrowerThanTheRatioGrowsTheWidth() throws {
        // 100 x 16/9 = 177.8, rounded up.
        let result = try #require(layout(120, 100, aspect: .sixteenNine))
        #expect(result.canvasSize == CGSize(width: 178, height: 100))
        #expect(result.contentRect.origin == CGPoint(x: 29, y: 0))
    }

    @Test func exactRatioDoesNotGrow() throws {
        let result = try #require(layout(1600, 900, aspect: .sixteenNine))
        #expect(result.canvasSize == CGSize(width: 1600, height: 900))
    }

    @Test func portraitContentInvertsTheRatio() throws {
        // 9:16 for 100 x 200: the width grows to 112.5, rounded up.
        let sixteenNine = try #require(layout(100, 200, aspect: .sixteenNine))
        #expect(sixteenNine.canvasSize == CGSize(width: 113, height: 200))
        let square = try #require(layout(100, 200, aspect: .square))
        #expect(square.canvasSize == CGSize(width: 200, height: 200))
    }

    @Test func paddingCountsBeforeTheRatio() throws {
        // 100 x 50 plus 25 each side is 150 x 100, narrower than 16:9, so the width grows.
        let result = try #require(layout(100, 50, padding: 25, aspect: .sixteenNine))
        #expect(result.canvasSize == CGSize(width: 178, height: 100))
    }

    @Test func oddSizesCentreWithTheOriginRoundedDown() throws {
        let result = try #require(layout(100, 51, aspect: .square))
        #expect(result.canvasSize == CGSize(width: 100, height: 100))
        // (100 - 51) / 2 = 24.5, rounded down.
        #expect(result.contentRect == CGRect(x: 0, y: 24, width: 100, height: 51))
    }

    @Test func radiusScalesWithTheCapture() throws {
        #expect(try #require(layout(400, 300, radius: 12, scale: 2)).radius == 24)
    }

    @Test func radiusIsCappedAtHalfTheShorterSide() throws {
        #expect(try #require(layout(30, 20, radius: 40)).radius == 10)
        #expect(try #require(layout(20, 30, radius: 40)).radius == 10)
    }

    @Test func nilAboveTheContentLimit() throws {
        #expect(layout(16_385, 10) == nil)
        #expect(layout(10, 16_385) == nil)
        #expect(try #require(layout(16_384, 10)).canvasSize == CGSize(width: 16_384, height: 10))
    }

    @Test func nilWhenTheCanvasIsTooBig() throws {
        // 16,384 + 2 x 8,192 is exactly 32,768; one more pixel of padding is over.
        let edge = try #require(layout(16_384, 100, padding: 8_192))
        #expect(edge.canvasSize.width == 32_768)
        #expect(layout(16_384, 100, padding: 8_193) == nil)
        #expect(layout(100, 100, padding: 160, scale: 1_000) == nil)
    }

    @Test func emptyContentHasNoLayout() {
        #expect(layout(0, 10) == nil)
        #expect(layout(10, 0) == nil)
    }
}
