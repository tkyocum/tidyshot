import Testing
@testable import TidyShot

struct TemplateMigrationTests {
    func migrate(_ template: String) -> String {
        TemplateMigration.removingAppToken(from: template, fallback: "FALLBACK")
    }

    @Test func templatesWithoutTheTokenAreUnchanged() {
        #expect(migrate("{random:6}") == "{random:6}")
        #expect(migrate("Screenshot {date} at {time}") == "Screenshot {date} at {time}")
        #expect(migrate("a--b  {date}") == "a--b  {date}")
        #expect(migrate("{application}") == "{application}")
    }

    @Test func tokenBetweenSeparatorsTakesOneOfThemWithIt() {
        #expect(migrate("shots/{app}/{random:8}") == "shots/{random:8}")
        #expect(migrate("shots/{app}-{random}") == "shots/{random}")
        #expect(migrate("Screenshot {app} {datetime}") == "Screenshot {datetime}")
        #expect(migrate("{date}_{app}_{random}") == "{date}_{random}")
        #expect(migrate("{date}-{app}/{random}") == "{date}/{random}")
    }

    /// `.` is not a separator: it is never removed, and a `-`, `_` or space left next to it dangles.
    @Test func dotIsNeverTouched() {
        #expect(migrate("{random}-{app}.png") == "{random}.png")
        #expect(migrate("shots/{app}.png") == "shots/.png")
        #expect(migrate("{date}_{app}.{counter}") == "{date}.{counter}")
    }

    @Test func tokenAtEitherEndTakesItsSeparatorWithIt() {
        #expect(migrate("{app} {datetime}") == "{datetime}")
        #expect(migrate("{app}/{date}/{random}") == "{date}/{random}")
        #expect(migrate("Screenshot {date} {app}") == "Screenshot {date}")
        #expect(migrate("{random}-{app}") == "{random}")
    }

    @Test func tokenNextToTextIsDroppedAndAnEmptyResultFallsBack() {
        #expect(migrate("x{app}y") == "xy")
        #expect(migrate("{app}{app}-{random}") == "{random}")
        #expect(migrate("{app}") == "FALLBACK")
        #expect(migrate(" {app} ") == "FALLBACK")
    }

    /// `{app}` alone leaves nothing, so each stored template gets its own default.
    @Test func tokenAloneBecomesTheDefaultTemplate() {
        #expect(TemplateMigration.removingAppToken(from: "{app}", fallback: FileNamer.defaultTemplate) == FileNamer.defaultTemplate)
        #expect(TemplateMigration.removingAppToken(from: "{app}", fallback: ObjectKeyNamer.defaultTemplate) == ObjectKeyNamer.defaultTemplate)
    }
}
