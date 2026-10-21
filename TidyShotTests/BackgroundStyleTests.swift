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

    /// A document written before 7c has no "background" key and decodes with none; a document
    /// without a background writes none; a background round-trips and survives other edits.
    @Test func annotationDocumentWithoutBackgroundDecodesToNil() throws {
        let old = try JSONDecoder().decode(AnnotationDocument.self, from: Data(#"{"annotations":[]}"#.utf8))
        #expect(old.background == nil)
        let json = try JSONEncoder().encode(AnnotationDocument(annotations: []))
        let written = try #require(try JSONSerialization.jsonObject(with: json) as? [String: Any])
        #expect(!written.keys.contains("background"))

        let style = BackgroundStyle(fill: .gradient(3), padding: 20, aspect: .fourThree)
        let document = AnnotationDocument(annotations: []).withBackground(style)
        #expect(try JSONDecoder().decode(AnnotationDocument.self, from: JSONEncoder().encode(document)) == document)
        #expect(document.withCrop(CGRect(x: 0, y: 0, width: 4, height: 4)).background == style)
        #expect(document.withBackground(nil) == AnnotationDocument(annotations: []))
    }
}
