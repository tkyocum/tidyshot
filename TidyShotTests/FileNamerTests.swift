import Foundation
import Testing
@testable import TidyShot

struct FileNamerTests {
    /// 2026-10-19 11:56:03 in the current time zone, matching what DateFormatter will print.
    let fixedDate = DateComponents(calendar: .current, year: 2026, month: 10, day: 19, hour: 11, minute: 56, second: 3).date!

    func namer(_ template: String) -> FileNamer {
        FileNamer(template: template, now: { fixedDate }, randomString: { String(repeating: "X", count: $0) }, hostname: "miffle")
    }

    @Test func defaultTemplateMatchesSystemStyle() {
        let name = FileNamer(now: { fixedDate }).name(counter: 1)
        #expect(name == "Screenshot 2026-10-19 at 11.56.03")
    }

    @Test func datetimeToken() {
        #expect(namer("Shot {datetime}").name(counter: 1) == "Shot 2026-10-19 11.56.03")
    }

    /// `{app}` was removed in Phase 3.1; stored templates are migrated, so this only shows that the
    /// engine treats it like any other unknown text.
    @Test func removedAppTokenIsLiteralText() {
        #expect(namer("{app}").name(counter: 1) == "{app}")
    }

    @Test func counterToken() {
        #expect(namer("shot-{counter}").name(counter: 42) == "shot-42")
    }

    @Test func randomTokenDefaultsToSixCharacters() {
        #expect(namer("{random}").name(counter: 1) == "XXXXXX")
    }

    @Test func randomTokenWithLength() {
        #expect(namer("{random:8}-{random:2}").name(counter: 1) == "XXXXXXXX-XX")
    }

    @Test func yearMonthDayAndHostnameTokens() {
        #expect(namer("{year}/{month}/{day} {hostname}").name(counter: 1) == "2026-10-19 miffle")
    }

    @Test func sanitizeReplacesPathSeparatorsAndColons() {
        #expect(FileNamer.sanitize("a/b:c") == "a-b-c")
    }

    @Test func sanitizeTrimsWhitespaceAndLeadingDot() {
        #expect(FileNamer.sanitize("  .hidden ") == "_hidden")
    }

    @Test func emptyResultFallsBackToScreenshot() {
        #expect(namer("   ").name(counter: 1) == "Screenshot")
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
