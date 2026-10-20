import Foundation
import Testing
@testable import TidyShot

struct TemplateExpanderTests {
    /// 2026-10-19 11:56:03 in the current time zone, matching what DateFormatter will print.
    let fixedDate = DateComponents(calendar: .current, year: 2026, month: 10, day: 19, hour: 11, minute: 56, second: 3).date!
    let expander = TemplateExpander(randomString: { String(repeating: "X", count: $0) })

    func context(app: String? = "Safari", counter: Int = 7) -> TemplateContext {
        TemplateContext(date: fixedDate, appName: app, counter: counter, hostname: "miffle")
    }

    @Test func parsesLiteralsAndTokens() {
        #expect(TemplateExpander.parse("shots/{year}/{random:8}")
                == [.literal("shots/"), .token(.year), .literal("/"), .token(.random(length: 8))])
    }

    @Test func unknownAndUnterminatedBracesStayLiteral() {
        #expect(TemplateExpander.parse("{foo}-{date") == [.literal("{foo}-{date")])
        #expect(TemplateExpander.parse("{{date}") == [.literal("{"), .token(.date)])
        #expect(TemplateExpander.parse("") == [])
    }

    @Test func randomLengthDefaultsAndClamps() {
        #expect(TemplateExpander.parse("{random}") == [.token(.random(length: 6))])
        #expect(TemplateExpander.parse("{random:0}") == [.token(.random(length: 1))])
        #expect(TemplateExpander.parse("{random:999}") == [.token(.random(length: 64))])
        #expect(TemplateExpander.parse("{random:1000}") == [.token(.random(length: 64))])
        #expect(TemplateExpander.parse("{random:99999999999999999999999}") == [.token(.random(length: 64))])
        #expect(TemplateExpander.parse("{random:x}") == [.literal("{random:x}")])
    }

    @Test func dateTokens() {
        #expect(expander.expand("{date}|{year}|{month}|{day}", context: context(), style: .objectKey)
                == "2026-10-19|2026|10|19")
    }

    @Test func timeAndDatetimeDifferByStyle() {
        #expect(expander.expand("{time}", context: context(), style: .fileName) == "11.56.03")
        #expect(expander.expand("{time}", context: context(), style: .objectKey) == "11-56-03")
        #expect(expander.expand("{datetime}", context: context(), style: .fileName) == "2026-10-19 11.56.03")
        #expect(expander.expand("{datetime}", context: context(), style: .objectKey) == "2026-10-19_11-56-03")
    }

    @Test func appHostnameCounterAndRandom() {
        #expect(expander.expand("{app}/{hostname}-{counter}-{random:3}", context: context(), style: .objectKey)
                == "Safari/miffle-7-XXX")
        #expect(expander.expand("{app}", context: context(app: nil), style: .fileName) == "Screen")
    }

    @Test func objectKeyStyleSanitisesTokenValuesOnly() {
        let chrome = context(app: "Google Chrome (Beta)")
        #expect(expander.expand("{app}", context: chrome, style: .fileName) == "Google Chrome (Beta)")
        #expect(expander.expand("{app}", context: chrome, style: .objectKey) == "Google-Chrome-Beta")
        // Literal text is the template author's business; the key namer validates it.
        #expect(expander.expand("a b/{counter}", context: chrome, style: .objectKey) == "a b/7")
    }

    @Test func hasCollisionGuard() {
        #expect(TemplateExpander.hasCollisionGuard("{random:6}"))
        #expect(TemplateExpander.hasCollisionGuard("shots/{counter}"))
        #expect(!TemplateExpander.hasCollisionGuard("{date}/{hostname}"))
        #expect(!TemplateExpander.hasCollisionGuard("{random"))
    }

    @Test func keySafe() {
        #expect(TemplateExpander.keySafe("Google Chrome") == "Google-Chrome")
        #expect(TemplateExpander.keySafe("..hidden..") == "hidden")
        #expect(TemplateExpander.keySafe("a//b  c") == "a-b-c")
        #expect(TemplateExpander.keySafe("") == "x")
        #expect(TemplateExpander.keySafe("é") == "x")
        #expect(TemplateExpander.keySafe("2026-10-19_11-56-03") == "2026-10-19_11-56-03")
    }

    @Test func normalizeHostname() {
        #expect(TemplateExpander.normalizeHostname("Tims-MacBook-Pro.local") == "tims-macbook-pro")
        #expect(TemplateExpander.normalizeHostname("miffle.alligator-in.ts.net") == "miffle.alligator-in.ts.net")
        #expect(TemplateExpander.normalizeHostname("Tim's Mac\n") == "tim-s-mac")
        #expect(TemplateExpander.normalizeHostname("build_host_01") == "build-host-01")
        #expect(TemplateExpander.normalizeHostname("-a__b--c..d.-e-") == "a-b-c.d.e")
        #expect(TemplateExpander.normalizeHostname("Café.local") == "caf")
        #expect(TemplateExpander.normalizeHostname("") == "mac")
        #expect(TemplateExpander.normalizeHostname(".local") == "mac")
        #expect(TemplateExpander.normalizeHostname("__") == "mac")
    }

    /// Runs inside the sandboxed test host, so this also proves `gethostname` works there.
    @Test func localHostNameIsNonEmptyAndKeySafe() {
        let name = HostName.local()
        #expect(!name.isEmpty)
        #expect(!name.hasSuffix(".local"))
        #expect(name.allSatisfy { $0.isASCII && ($0.isLowercase || $0.isNumber || $0 == "-" || $0 == ".") })
    }
}
