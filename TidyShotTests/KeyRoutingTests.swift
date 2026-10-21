import CoreGraphics
import Foundation
import Testing
@testable import TidyShot

struct KeyRoutingTests {
    /// Spelled out, because `.none` reads as `Optional.none` in an optional context.
    let ignored = KeyRouting.Action.none

    func action(_ characters: String?, command: Bool = false, control: Bool = false, option: Bool = false,
                editing: Bool = false, tool: EditorTool = .select) -> KeyRouting.Action {
        KeyRouting.action(characters: characters, command: command, control: control, option: option,
                          isEditingText: editing, tool: tool)
    }

    func matched(_ characters: String, shift: Bool = false, option: Bool = false, command: Bool = true,
                 control: Bool = false, editing: Bool = false) -> EditorShortcut? {
        EditorShortcut.match(characters: characters, command: command, shift: shift, option: option, control: control,
                             isEditingText: editing)
    }

    @Test func lettersSelectTools() {
        let expected: [(String, EditorTool)] = [
            ("v", .select), ("d", .redact), ("x", .pixelate), ("b", .blur), ("r", .rectangle), ("a", .arrow),
        ]
        for (key, tool) in expected {
            #expect(action(key) == .selectTool(tool))
            // With Shift, charactersIgnoringModifiers gives the capital.
            #expect(action(key.uppercased()) == .selectTool(tool))
        }
        for tool in EditorTool.allCases {
            #expect(action(String(tool.letter)) == .selectTool(tool))
        }
        #expect(action("q") == ignored)
        #expect(action(nil) == ignored)
        #expect(action("") == ignored)
        #expect(action("vd") == ignored)
    }

    @Test func digitsOneToSixPickWidths() {
        for digit in 1...6 {
            #expect(action(String(digit)) == .lineWidth(index: digit - 1))
        }
        #expect(EditorPalette.lineWidthsPoints == [2, 3, 4, 6, 8, 12])
        #expect(action("5") == .lineWidth(index: 4))
        #expect(EditorPalette.lineWidthsPoints[4] == 8)
        for key in ["0", "7", "8", "9"] {
            #expect(action(key) == ignored)
        }
        // Shift-1 arrives as "!".
        #expect(action("!") == ignored)
    }

    /// ⌘1 is Actual Size in the shortcut table, never a line width.
    @Test func modifiersSuppressLetters() {
        #expect(action("v", command: true) == ignored)
        #expect(action("v", control: true) == ignored)
        #expect(action("v", option: true) == ignored)
        #expect(action("1", command: true) == ignored)
        #expect(action("2", option: true) == ignored)
    }

    @Test func editingTextSuppressesLetters() {
        for tool in EditorTool.allCases {
            #expect(action(String(tool.letter), editing: true) == ignored)
        }
        for digit in 1...6 {
            #expect(action(String(digit), editing: true) == ignored)
        }
    }

    @Test func nudgeOneOrTenPixels() {
        #expect(KeyRouting.nudge(dx: 1, dy: 0, shift: false) == CGVector(dx: 1, dy: 0))
        #expect(KeyRouting.nudge(dx: -1, dy: 0, shift: false) == CGVector(dx: -1, dy: 0))
        // Up is -1, because image y grows downward.
        #expect(KeyRouting.nudge(dx: 0, dy: -1, shift: false) == CGVector(dx: 0, dy: -1))
        #expect(KeyRouting.nudge(dx: 0, dy: 1, shift: true) == CGVector(dx: 0, dy: 10))
        #expect(KeyRouting.nudge(dx: -1, dy: 0, shift: true) == CGVector(dx: -10, dy: 0))
    }

    /// The 4a table from spec 2.6 plus 4b's ⌘V and ⌘D. Characters are as charactersIgnoringModifiers gives them.
    @Test func shortcutTableMatchesExpectedChords() {
        let expected: [(characters: String, shift: Bool, option: Bool, shortcut: EditorShortcut, selector: String)] = [
            ("s", false, false, .save, "saveDocument:"),
            ("S", true, false, .saveAs, "saveDocumentAs:"),
            ("c", false, false, .copy, "copy:"),
            ("C", true, false, .copyImage, "copyImage:"),
            ("v", false, false, .paste, "paste:"),
            ("d", false, false, .duplicate, "duplicate:"),
            ("u", false, false, .upload, "uploadDocument:"),
            ("u", false, true, .uploadAsNew, "uploadDocumentAsNew:"),
            ("z", false, false, .undo, "undo:"),
            ("Z", true, false, .redo, "redo:"),
            ("w", false, false, .close, "performClose:"),
            ("0", false, false, .zoomToFit, "zoomToFit:"),
            ("1", false, false, .actualSize, "zoomToActualSize:"),
            ("=", false, false, .zoomIn, "zoomIn:"),
            ("-", false, false, .zoomOut, "zoomOut:"),
            ("a", false, false, .selectAll, "selectAll:"),
        ]
        for row in expected {
            #expect(matched(row.characters, shift: row.shift, option: row.option) == row.shortcut)
            #expect(row.shortcut.selectorName == row.selector)
        }
        #expect(expected.count == EditorShortcut.allCases.count)
        // ⌘X has no row: Phase 4 has no object cut, so it always reaches the responder chain.
        #expect(matched("x") == nil)
        #expect(matched("X", shift: true) == nil)
        // Command is required, Control rules a chord out, and an extra modifier is another chord.
        #expect(matched("s", command: false) == nil)
        #expect(matched("s", control: true) == nil)
        #expect(matched("s", option: true) == nil)
        #expect(matched("w", shift: true) == nil)
        #expect(matched("U", shift: true, option: true) == nil)
        // ⇧⌘V and ⌥⌘D are other chords.
        #expect(matched("V", shift: true) == nil)
        #expect(matched("d", option: true) == nil)
    }

    @Test func shortcutTableHasNoDuplicateChords() {
        let chords = EditorShortcut.allCases.map(\.chord)
        #expect(Set(chords).count == chords.count)
        let selectors = EditorShortcut.allCases.map(\.selectorName)
        #expect(Set(selectors).count == selectors.count)
        // Every row's own chord reaches it.
        for shortcut in EditorShortcut.allCases {
            #expect(EditorShortcut.match(characters: shortcut.chord.key, command: true, shift: shortcut.chord.shift,
                                         option: shortcut.chord.option, control: false, isEditingText: false) == shortcut)
        }
    }

    /// While a text annotation is edited (4b), ⌘C, ⌘V, ⌘D, ⌘A, ⌘Z and ⇧⌘Z go to the NSTextView.
    @Test func editingTextPassesClipboardAndUndoChordsThrough() {
        #expect(Set(EditorShortcut.allCases.filter(\.passesThroughWhileEditingText)) == [.copy, .paste, .duplicate, .selectAll, .undo, .redo])
        for shortcut in EditorShortcut.allCases {
            let expected: EditorShortcut? = shortcut.passesThroughWhileEditingText ? nil : shortcut
            #expect(EditorShortcut.match(characters: shortcut.chord.key, command: true, shift: shortcut.chord.shift,
                                         option: shortcut.chord.option, control: false, isEditingText: true) == expected)
        }
        #expect(matched("c", editing: true) == nil)
        #expect(matched("v", editing: true) == nil)
        #expect(matched("d", editing: true) == nil)
        #expect(matched("a", editing: true) == nil)
        #expect(matched("z", editing: true) == nil)
        #expect(matched("Z", shift: true, editing: true) == nil)
        // Save, Copy Image, Upload, Close and Zoom still match.
        #expect(matched("s", editing: true) == .save)
        #expect(matched("C", shift: true, editing: true) == .copyImage)
        #expect(matched("u", editing: true) == .upload)
        #expect(matched("w", editing: true) == .close)
        #expect(matched("0", editing: true) == .zoomToFit)
        // ⌘X has no row, so it reaches the text view as well.
        #expect(matched("x", editing: true) == nil)
    }

    /// With the Text tool active the digits pick text sizes instead of line widths.
    @Test func digitsPickTextSizesForTextTool() {
        #expect(EditorPalette.textSizesPoints == [12, 16, 20, 28, 40, 56])
        #expect(EditorPalette.textSizesPoints.count == EditorPalette.lineWidthsPoints.count)
        #expect(EditorPalette.defaultTextSizePoints == 20)
        for digit in 1...6 {
            #expect(action(String(digit), tool: .text) == .textSize(index: digit - 1))
            #expect(action(String(digit), tool: .rectangle) == .lineWidth(index: digit - 1))
            #expect(action(String(digit), tool: .select) == .lineWidth(index: digit - 1))
        }
        #expect(EditorPalette.textSizesPoints[3] == 28)
        // Letters still pick tools, T among them, and other keys stay ignored.
        #expect(action("v", tool: .text) == .selectTool(.select))
        #expect(action("t") == .selectTool(.text))
        for key in ["0", "7", "!"] {
            #expect(action(key, tool: .text) == ignored)
        }
        #expect(action("1", command: true, tool: .text) == ignored)
        // While typing, every key belongs to the text view.
        #expect(action("3", editing: true, tool: .text) == ignored)
        #expect(action("t", editing: true, tool: .text) == ignored)
    }

    /// While typing, EditorWindow sends these to the text view itself, so they work whether or not
    /// the never-drawn main menu has an Edit menu. The table leaves every one of them alone.
    @Test func textEditingChordsGoToTheTextView() {
        let expected: [(characters: String, shift: Bool, selector: String)] = [
            ("c", false, "copy:"), ("x", false, "cut:"), ("v", false, "paste:"),
            ("a", false, "selectAll:"), ("z", false, "undo:"), ("Z", true, "redo:"),
        ]
        for row in expected {
            #expect(TextEditingChord.selectorName(characters: row.characters, command: true, shift: row.shift,
                                                  option: false, control: false) == row.selector)
            #expect(matched(row.characters, shift: row.shift, editing: true) == nil)
        }
        // Command is required; Option, Control or another key is something else.
        #expect(TextEditingChord.selectorName(characters: "c", command: false, shift: false, option: false, control: false) == nil)
        #expect(TextEditingChord.selectorName(characters: "c", command: true, shift: false, option: true, control: false) == nil)
        #expect(TextEditingChord.selectorName(characters: "c", command: true, shift: false, option: false, control: true) == nil)
        #expect(TextEditingChord.selectorName(characters: "s", command: true, shift: false, option: false, control: false) == nil)
        // ⇧⌘C stays Copy Image, which commits the text and copies the picture.
        #expect(TextEditingChord.selectorName(characters: "C", command: true, shift: true, option: false, control: false) == nil)
        #expect(matched("C", shift: true, editing: true) == .copyImage)
    }

    /// Space alone pans; it is never a tool letter or a width, so `action` leaves it alone too.
    @Test func spaceIsThePanKey() {
        func pan(_ characters: String?, command: Bool = false, control: Bool = false, option: Bool = false,
                 editing: Bool = false) -> Bool {
            KeyRouting.isPanKey(characters: characters, command: command, control: control, option: option,
                                isEditingText: editing)
        }
        #expect(pan(" "))
        #expect(!pan(" ", command: true))
        #expect(!pan(" ", control: true))
        #expect(!pan(" ", option: true))
        #expect(!pan(" ", editing: true))
        #expect(!pan("v"))
        #expect(!pan(nil))
        #expect(!pan("  "))
        #expect(action(" ") == ignored)
        #expect(action(" ", tool: .text) == ignored)
    }
}
