import AppKit
import Testing
@testable import TidyShot

struct EditorToolTests {
    /// The Phase 4a tools. 4b adds cases, so the assertions that pin values look only at these.
    let phase4a: [EditorTool] = [.select, .redact, .pixelate, .blur, .rectangle, .arrow]

    @Test func lettersAreUnique() {
        let letters = EditorTool.allCases.map(\.letter)
        #expect(Set(letters).count == letters.count)
        #expect(letters.allSatisfy { $0.isASCII && $0.isUppercase })
        #expect(phase4a.map(\.letter) == ["V", "D", "X", "B", "R", "A"])
        #expect([EditorTool.ellipse, .line].map(\.letter) == ["E", "L"])
        #expect([EditorTool.spotlight, .counter].map(\.letter) == ["S", "N"])
    }

    /// 4c's Spotlight sits after Blur, with the effects it works like, and Counter after Text.
    @Test func fourteenToolsInToolbarOrder() {
        let expected: [EditorTool] = [.select, .redact, .pixelate, .blur, .spotlight, .rectangle, .arrow, .ellipse,
                                      .line, .pencil, .highlighter, .text, .counter, .crop]
        #expect(EditorTool.toolbarOrder == expected)
        #expect(EditorTool.allCases.count == 14)
    }

    @Test func toolForKeyIsCaseInsensitive() {
        for tool in EditorTool.allCases {
            #expect(EditorTool.tool(forKey: tool.letter) == tool)
            #expect(EditorTool.tool(forKey: Character(tool.letter.lowercased())) == tool)
        }
        #expect(EditorTool.tool(forKey: "d") == .redact)
        #expect(EditorTool.tool(forKey: "X") == .pixelate)
    }

    @Test func unknownKeyIsNil() {
        // "ß" upper-cases to two letters, so the lookup must compare strings, not build a Character.
        for key: Character in ["q", "Z", "1", " ", "ß", "\u{1B}"] {
            #expect(EditorTool.tool(forKey: key) == nil)
        }
    }

    @Test func everyToolHasSymbolAndTooltipWithLetter() {
        for tool in EditorTool.allCases {
            #expect(NSImage(systemSymbolName: tool.symbolName, accessibilityDescription: tool.title) != nil,
                    "\(tool.symbolName) is not an SF Symbol")
            #expect(tool.tooltip == "\(tool.title) (\(tool.letter))")
        }
        #expect(EditorTool.redact.tooltip == "Redact (D)")
        #expect(EditorTool.ellipse.tooltip == "Ellipse (E)")
        #expect(EditorTool.line.tooltip == "Line (L)")
        #expect(EditorTool.spotlight.tooltip == "Spotlight (S)")
        #expect(EditorTool.counter.tooltip == "Counter (N)")
        #expect([EditorTool.spotlight, .counter].map(\.symbolName) == ["light.max", "1.circle"])
        #expect(phase4a.map(\.title) == ["Select", "Redact", "Pixelate", "Blur", "Rectangle", "Arrow"])
    }

    @Test func effectToolsAreRedactPixelateBlur() {
        #expect(EditorTool.allCases.filter(\.isEffect) == [.redact, .pixelate, .blur])
        // Spotlight works on the picture but makes no tile.
        #expect(!EditorTool.spotlight.isEffect)
    }

    @Test func toolbarOrderCoversEveryToolOnce() {
        let order = EditorTool.toolbarOrder
        #expect(order.count == EditorTool.allCases.count)
        #expect(Set(order) == Set(EditorTool.allCases))
        #expect(order.first == .select)
        // Redact leads the drawing tools because it is the only safe redaction. 4b inserts its
        // tools without reordering these.
        #expect(order.filter { phase4a.contains($0) } == phase4a)
        // Spotlight sits before Rectangle, so Arrow is the seventh tool. Ellipse and Line follow
        // Arrow; later tools go after them.
        #expect(Array(order.dropFirst(phase4a.count).prefix(2)) == [.arrow, .ellipse])
    }
}
