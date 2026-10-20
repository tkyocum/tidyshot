import Foundation
import Testing
@testable import TidyShot

struct ObjectKeyNamerTests {
    let fixedDate = DateComponents(calendar: .current, year: 2026, month: 10, day: 19, hour: 11, minute: 56, second: 3).date!

    func namer(_ template: String = ObjectKeyNamer.defaultTemplate) -> ObjectKeyNamer {
        ObjectKeyNamer(template: template, randomString: { String(repeating: "X", count: $0) })
    }

    func context(counter: Int = 7, hostname: String = "miffle") -> TemplateContext {
        TemplateContext(date: fixedDate, counter: counter, hostname: hostname)
    }

    @Test func defaultTemplateIsSixRandomCharactersPlusExtension() {
        #expect(ObjectKeyNamer.defaultTemplate == "{random:6}")
        #expect(namer().makeKey(ext: "png", context: context()) == "XXXXXX.png")
    }

    @Test func literalFoldersAndTokens() {
        #expect(namer("shots/{year}/{month}/{hostname}-{random:8}").makeKey(ext: "png", context: context())
                == "shots/2026/10/miffle-XXXXXXXX.png")
        #expect(namer("{hostname}/{date}_{time}-{counter}").makeKey(ext: "png", context: context())
                == "miffle/2026-10-19_11-56-03-7.png")
        #expect(namer("{datetime}").makeKey(ext: "txt", context: context()) == "2026-10-19_11-56-03.txt")
    }

    @Test func slashesAreFoldedAndEmptyExpansionFallsBackToRandom() {
        #expect(namer("/a//b/{random:2}/").makeKey(ext: "png", context: context()) == "a/b/XX.png")
        #expect(namer("   ").makeKey(ext: "png", context: context()) == "XXXXXX.png")
        #expect(ObjectKeyNamer.fold("///") == "")
        #expect(ObjectKeyNamer.normalize("  shots/{random}  ") == "shots/{random}")
    }

    @Test func templateEndingInExtensionIsNotDoubled() {
        #expect(namer("shots/{random:4}.png").makeKey(ext: "png", context: context()) == "shots/XXXX.png")
        #expect(namer("{random:4}.PNG").makeKey(ext: "png", context: context()) == "XXXX.PNG")
        #expect(namer("{random:4}.png.bak").makeKey(ext: "png", context: context()) == "XXXX.png.bak.png")
        // A folder named only `.png` is not a file name ending in the extension.
        #expect(namer("a/.png").makeKey(ext: "png", context: context()) == "a/.png.png")
    }

    @Test func tokenValuesAreKeySafe() {
        #expect(namer("{hostname}/{random:2}").makeKey(ext: "png", context: context(hostname: "Tim's Mac (2)")) == "Tim-s-Mac-2/XX.png")
        #expect(namer("{hostname}").makeKey(ext: "png", context: context(hostname: "")) == "x.png")
    }

    @Test func validateAcceptsGoodTemplates() {
        #expect(ObjectKeyNamer.validate("{random:6}") == nil)
        #expect(ObjectKeyNamer.validate("shots/{year}/{month}/{hostname}-{random:8}") == nil)
        #expect(ObjectKeyNamer.validate("a.b_c-d/{date}") == nil)
        #expect(ObjectKeyNamer.validate(" /{counter}/ ") == nil)
    }

    @Test func validateRejectsBadTemplates() {
        #expect(ObjectKeyNamer.validate("") == .empty)
        #expect(ObjectKeyNamer.validate("  /// ") == .empty)
        #expect(ObjectKeyNamer.validate("my shots/{random}") == .illegalCharacter(" "))
        #expect(ObjectKeyNamer.validate("{random}?x") == .illegalCharacter("?"))
        #expect(ObjectKeyNamer.validate("ünïcode") == .illegalCharacter("ü"))
        #expect(ObjectKeyNamer.validate("{foo}") == .unknownToken("foo"))
        #expect(ObjectKeyNamer.validate("{app}/{random}") == .unknownToken("app"))
        #expect(ObjectKeyNamer.validate("{random:x}") == .unknownToken("random:x"))
        #expect(ObjectKeyNamer.validate("{date") == .unbalancedBraces)
        #expect(ObjectKeyNamer.validate("date}") == .unbalancedBraces)
        #expect(ObjectKeyNamer.validate("../{random}") == .dotSegment(".."))
        #expect(ObjectKeyNamer.validate("a/./{random}") == .dotSegment("."))
    }

    @Test func templateErrorsHaveMessages() {
        #expect(ObjectKeyNamer.TemplateError.illegalCharacter(" ").localizedDescription.contains("\" \" is not allowed"))
        #expect(ObjectKeyNamer.TemplateError.unknownToken("foo").localizedDescription.hasPrefix("{foo} is not a token."))
        #expect(ObjectKeyNamer.TemplateError.dotSegment("..").localizedDescription == "A folder cannot be \"..\".")
    }

    @Test func collisionWarningOnlyWithoutRandomOrCounter() {
        #expect(ObjectKeyNamer.collisionWarning(for: "{random:6}") == nil)
        #expect(ObjectKeyNamer.collisionWarning(for: "{date}/{counter}") == nil)
        #expect(ObjectKeyNamer.collisionWarning(for: "{date}/{hostname}")?.hasPrefix("This template has no {random} or {counter}, so captures can produce the same key") == true)
    }

    @Test func folderOfKey() {
        #expect(ObjectKeyNamer.folder(of: "shots/2026/10/aB3dE9.png") == "shots/2026/10")
        #expect(ObjectKeyNamer.folder(of: "aB3dE9.png") == "")
    }

    @Test func migratedTemplateFromPhase2Settings() {
        #expect(ObjectKeyNamer.migratedTemplate(prefix: "shots", length: 8) == "shots/{random:8}")
        #expect(ObjectKeyNamer.migratedTemplate(prefix: "", length: 6) == "{random:6}")
        #expect(ObjectKeyNamer.migratedTemplate(prefix: " /a/b/ ", length: 1) == "a/b/{random:4}")
        #expect(ObjectKeyNamer.migratedTemplate(prefix: "p", length: 99) == "p/{random:32}")
    }

    /// Phase 2 accepted any prefix text; the migrated template must still pass `validate`.
    @Test func migratedTemplateSanitisesThePrefix() {
        let spaced = ObjectKeyNamer.migratedTemplate(prefix: "team shots/a+b", length: 8)
        #expect(spaced == "team-shots/a-b/{random:8}")
        #expect(ObjectKeyNamer.validate(spaced) == nil)
        let braced = ObjectKeyNamer.migratedTemplate(prefix: "../{date}", length: 6)
        #expect(braced == "-date-/{random:6}")
        #expect(ObjectKeyNamer.validate(braced) == nil)
        #expect(ObjectKeyNamer.validate(ObjectKeyNamer.migratedTemplate(prefix: "é ü//./x", length: 6)) == nil)
    }

    @Test func realKeysUseTheFileNamerAlphabet() {
        let key = ObjectKeyNamer(template: "{random:10}").makeKey(ext: "png", context: context())
        #expect(key.count == 14)
        #expect(key.hasSuffix(".png"))
        #expect(key.dropLast(4).allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber) })
    }
}
