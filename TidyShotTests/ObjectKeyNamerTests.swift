import Foundation
import Testing
@testable import TidyShot

struct ObjectKeyNamerTests {
    func namer(prefix: String = "", length: Int = 6) -> ObjectKeyNamer {
        ObjectKeyNamer(prefix: prefix, length: length, randomString: { String(repeating: "X", count: $0) })
    }

    @Test func defaultIsSixRandomCharactersPlusExtension() {
        #expect(namer().makeKey(ext: "png") == "XXXXXX.png")
    }

    @Test func prefixBecomesFolder() {
        #expect(namer(prefix: "shots").makeKey(ext: "png") == "shots/XXXXXX.png")
        #expect(namer(prefix: "/a/b/").makeKey(ext: "png") == "a/b/XXXXXX.png")
        #expect(namer(prefix: "  ").makeKey(ext: "png") == "XXXXXX.png")
    }

    @Test func lengthIsClampedToFourThroughThirtyTwo() {
        #expect(namer(length: 1).makeKey(ext: "png") == "XXXX.png")
        #expect(namer(length: 99).makeKey(ext: "png") == String(repeating: "X", count: 32) + ".png")
        #expect(namer(length: 8).makeKey(ext: "png") == "XXXXXXXX.png")
    }

    @Test func realKeysUseTheFileNamerAlphabet() {
        let key = ObjectKeyNamer(length: 10).makeKey(ext: "png")
        #expect(key.count == 14)
        #expect(key.hasSuffix(".png"))
        #expect(key.dropLast(4).allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber) })
    }

    @Test func joinHelper() {
        #expect(ObjectKeyNamer.join(prefix: "", name: "probe.txt") == "probe.txt")
        #expect(ObjectKeyNamer.join(prefix: "p/", name: "probe.txt") == "p/probe.txt")
    }
}
