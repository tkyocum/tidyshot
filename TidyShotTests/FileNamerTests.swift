import Foundation
import Testing
@testable import TidyShot

struct FileNamerTests {
    /// 2026-10-19 11:56:03 in the current time zone, matching what DateFormatter will print.
    let fixedDate = DateComponents(calendar: .current, year: 2026, month: 10, day: 19, hour: 11, minute: 56, second: 3).date!

    func namer(_ template: String) -> FileNamer {
        FileNamer(template: template, now: { fixedDate }, randomString: { String(repeating: "X", count: $0) })
    }

    @Test func defaultTemplateMatchesSystemStyle() {
        let name = FileNamer(now: { fixedDate }).name(appName: nil, counter: 1)
        #expect(name == "Screenshot 2026-10-19 at 11.56.03")
    }

    @Test func appAndDatetimeTokens() {
        #expect(namer("{app} {datetime}").name(appName: "Safari", counter: 1) == "Safari 2026-10-19 11.56.03")
    }

    @Test func missingAppFallsBackToScreen() {
        #expect(namer("{app}").name(appName: nil, counter: 1) == "Screen")
    }

    @Test func counterToken() {
        #expect(namer("shot-{counter}").name(appName: nil, counter: 42) == "shot-42")
    }

    @Test func randomTokenDefaultsToSixCharacters() {
        #expect(namer("{random}").name(appName: nil, counter: 1) == "XXXXXX")
    }

    @Test func randomTokenWithLength() {
        #expect(namer("{random:8}-{random:2}").name(appName: nil, counter: 1) == "XXXXXXXX-XX")
    }

    @Test func sanitizeReplacesPathSeparatorsAndColons() {
        #expect(FileNamer.sanitize("a/b:c") == "a-b-c")
    }

    @Test func sanitizeTrimsWhitespaceAndLeadingDot() {
        #expect(FileNamer.sanitize("  .hidden ") == "_hidden")
    }

    @Test func emptyResultFallsBackToScreenshot() {
        #expect(namer("   ").name(appName: nil, counter: 1) == "Screenshot")
    }

    @Test func realRandomStringUsesAlphanumerics() {
        let value = FileNamer.randomString(length: 32)
        #expect(value.count == 32)
        #expect(value.allSatisfy { $0.isLetter || $0.isNumber })
        #expect(value.allSatisfy { $0.isASCII })
    }

    @Test func uniqueURLAppendsCounterWhenFileExists() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let first = FileNamer.uniqueURL(baseName: "Shot", ext: "png", in: dir)
        #expect(first.lastPathComponent == "Shot.png")
        try Data().write(to: first)

        let second = FileNamer.uniqueURL(baseName: "Shot", ext: "png", in: dir)
        #expect(second.lastPathComponent == "Shot 2.png")
        try Data().write(to: second)

        let third = FileNamer.uniqueURL(baseName: "Shot", ext: "png", in: dir)
        #expect(third.lastPathComponent == "Shot 3.png")
    }
}
