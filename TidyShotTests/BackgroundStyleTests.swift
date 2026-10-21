import Foundation
import Testing
@testable import TidyShot

struct BackgroundStyleTests {
    @Test func defaults() {
        let style = BackgroundStyle()
        #expect(style.fill == .gradient(0))
        #expect(style.padding == 48)
        #expect(style.cornerRadius == 12)
        #expect(style.shadow)
        #expect(style.aspect == .auto)
    }

    @Test func jsonRoundTrip() throws {
        let style = BackgroundStyle(fill: .solid(RGBA(red: 0.1, green: 0.2, blue: 0.3, alpha: 1)),
                                    padding: 100, cornerRadius: 30, shadow: false, aspect: .sixteenNine)
        let data = try JSONEncoder().encode(style)
        #expect(try JSONDecoder().decode(BackgroundStyle.self, from: data) == style)
    }

    @Test func everyFillRoundTrips() throws {
        let fills: [BackgroundFill] = [.gradient(7), .solid(RGBA(red: 1, green: 0, blue: 0)),
                                       .desktopPicture, .customImage]
        for fill in fills {
            let data = try JSONEncoder().encode(BackgroundStyle(fill: fill))
            #expect(try JSONDecoder().decode(BackgroundStyle.self, from: data).fill == fill)
        }
    }

    @Test func emptyObjectDecodesToDefaults() throws {
        let style = try JSONDecoder().decode(BackgroundStyle.self, from: Data("{}".utf8))
        #expect(style == BackgroundStyle())
    }

    @Test func missingFieldsFallBackOneByOne() throws {
        let style = try JSONDecoder().decode(BackgroundStyle.self, from: Data(#"{"padding": 10}"#.utf8))
        #expect(style == BackgroundStyle(padding: 10))
    }

    @Test func aspectTitlesAndRatios() {
        #expect(BackgroundAspect.allCases.map(\.title) == ["Auto", "1:1", "4:3", "3:2", "16:10", "16:9"])
        #expect(BackgroundAspect.auto.ratio == nil)
        #expect(BackgroundAspect.square.ratio == 1)
        #expect(BackgroundAspect.sixteenNine.ratio == CGFloat(16) / 9)
    }
}
