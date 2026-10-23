import Testing
@testable import TidyShot

/// The status menu's GIF items (design, While it runs; plan Gap 5).
struct GIFProgressMenuTests {
    @Test func oneConversionGivesMakingGIFAndStopMakingGIF() throws {
        let items = try #require(GIFProgressMenu.items([GIFProgress(fraction: 0.42, frameCount: 150)]))
        #expect(items.progress == "Making GIF… 42 %")
        #expect(items.stop == "Stop Making GIF")
    }

    /// 0.5 of 100 frames and 0.25 of 300: 125 of 400 frames, 31 %.
    @Test func twoConversionsAreWeightedByTheirFrameCounts() throws {
        let items = try #require(GIFProgressMenu.items([GIFProgress(fraction: 0.5, frameCount: 100),
                                                       GIFProgress(fraction: 0.25, frameCount: 300)]))
        #expect(items.progress == "Making 2 GIFs… 31 %")
        #expect(items.stop == "Stop Making GIFs")
    }

    @Test func threeConversionsCountThemAll() throws {
        let items = try #require(GIFProgressMenu.items(Array(repeating: GIFProgress(fraction: 0.1, frameCount: 10), count: 3)))
        #expect(items.progress == "Making 3 GIFs… 10 %")
        #expect(items.stop == "Stop Making GIFs")
    }

    /// Rounded down, so 100 % never shows while a conversion runs.
    @Test func thePercentageIsRoundedDown() throws {
        #expect(GIFProgressMenu.items([GIFProgress(fraction: 0.999, frameCount: 150)])?.progress == "Making GIF… 99 %")
        #expect(GIFProgressMenu.items([GIFProgress(fraction: 0, frameCount: 150)])?.progress == "Making GIF… 0 %")
        #expect(GIFProgressMenu.items([GIFProgress(fraction: 0.57, frameCount: 1)])?.progress == "Making GIF… 57 %")
        #expect(GIFProgressMenu.items([GIFProgress(fraction: 1, frameCount: 150)])?.progress == "Making GIF… 100 %")
    }

    @Test func noConversionGivesNoItems() {
        #expect(GIFProgressMenu.items([]) == nil)
    }
}
