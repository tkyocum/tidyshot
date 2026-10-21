import CoreGraphics
import Foundation

/// Unmodified keys that reach `CanvasView.keyDown`: the tool letters and the line-width (or, with
/// the Text tool, text-size) digits.
/// Everything else goes to `interpretKeyEvents`, which turns Escape and ⌘. into `cancelOperation:`,
/// Delete into `deleteBackward:` or `deleteForward:`, and the arrow keys into `moveLeft:` and its
/// siblings, which nudge by `nudge(dx:dy:shift:)`. Space is the pan key (`isPanKey`); CanvasView
/// checks it before `action`, so it never reaches `interpretKeyEvents`.
nonisolated enum KeyRouting {
    enum Action: Equatable, Sendable {
        /// A tool letter, in either case.
        case selectTool(EditorTool)
        /// Digits 1 to 6: an index into `EditorPalette.lineWidthsPoints`.
        case lineWidth(index: Int)
        /// Digits 1 to 6 while the Text tool is active: an index into `EditorPalette.textSizesPoints`.
        case textSize(index: Int)
        /// Not a canvas key: pass the event to `interpretKeyEvents`.
        case none
    }

    /// Image pixels per arrow-key press, without and with Shift.
    static let nudgeStep: CGFloat = 1
    static let shiftNudgeStep: CGFloat = 10

    /// `characters` is `NSEvent.charactersIgnoringModifiers`, which keeps Shift: ⇧1 arrives as
    /// "!" and matches nothing, while ⇧V arrives as "V" and still picks Select. Command, Control
    /// or Option held, or a text edit in progress, make every key `.none`. The digits pick text
    /// sizes while `tool` is Text and line widths otherwise.
    static func action(characters: String?, command: Bool, control: Bool, option: Bool, isEditingText: Bool,
                       tool: EditorTool = .select) -> Action {
        guard !command, !control, !option, !isEditingText,
              let characters, characters.count == 1, let key = characters.first else { return .none }
        if key.isASCII, let digit = key.wholeNumberValue, (1...EditorPalette.lineWidthsPoints.count).contains(digit) {
            return tool == .text ? .textSize(index: digit - 1) : .lineWidth(index: digit - 1)
        }
        if let picked = EditorTool.tool(forKey: key) {
            return .selectTool(picked)
        }
        return .none
    }

    /// Space with no Command, Control or Option, and no text edit in progress: hold it and drag to
    /// pan. Shift does not matter.
    static func isPanKey(characters: String?, command: Bool, control: Bool, option: Bool, isEditingText: Bool) -> Bool {
        !command && !control && !option && !isEditingText && characters == " "
    }

    /// One arrow-key press. `dx` and `dy` are -1, 0 or 1; `dy` -1 is up, because image y grows
    /// downward.
    static func nudge(dx: Int, dy: Int, shift: Bool) -> CGVector {
        let step = shift ? shiftNudgeStep : nudgeStep
        return CGVector(dx: CGFloat(dx) * step, dy: CGFloat(dy) * step)
    }
}

/// The editor's key equivalents (spec 2.6: the 4a table plus 4b's ⌘V and ⌘D), matched by `EditorWindow.performKeyEquivalent`
/// before the main menu. ⌘X has no case: Phase 4 has no object cut, so ⌘X always reaches the
/// responder chain.
nonisolated enum EditorShortcut: CaseIterable, Sendable {
    case save, saveAs, copy, copyImage, paste, duplicate, upload, uploadAsNew, undo, redo, close, zoomToFit, actualSize, zoomIn, zoomOut, selectAll

    /// A key with Command held. Control is never part of a chord.
    struct Chord: Hashable, Sendable {
        /// Lower case.
        let key: String
        var shift = false
        var option = false
    }

    var chord: Chord {
        switch self {
        case .save: Chord(key: "s")
        case .saveAs: Chord(key: "s", shift: true)
        case .copy: Chord(key: "c")
        case .copyImage: Chord(key: "c", shift: true)
        case .paste: Chord(key: "v")
        case .duplicate: Chord(key: "d")
        case .upload: Chord(key: "u")
        case .uploadAsNew: Chord(key: "u", option: true)
        case .undo: Chord(key: "z")
        case .redo: Chord(key: "z", shift: true)
        case .close: Chord(key: "w")
        case .zoomToFit: Chord(key: "0")
        case .actualSize: Chord(key: "1")
        case .zoomIn: Chord(key: "=")
        case .zoomOut: Chord(key: "-")
        case .selectAll: Chord(key: "a")
        }
    }

    /// The action sent up the responder chain, for `NSSelectorFromString`.
    var selectorName: String {
        switch self {
        case .save: "saveDocument:"
        case .saveAs: "saveDocumentAs:"
        case .copy: "copy:"
        case .copyImage: "copyImage:"
        case .paste: "paste:"
        case .duplicate: "duplicate:"
        case .upload: "uploadDocument:"
        case .uploadAsNew: "uploadDocumentAsNew:"
        case .undo: "undo:"
        case .redo: "redo:"
        case .close: "performClose:"
        case .zoomToFit: "zoomToFit:"
        case .actualSize: "zoomToActualSize:"
        case .zoomIn: "zoomIn:"
        case .zoomOut: "zoomOut:"
        case .selectAll: "selectAll:"
        }
    }

    /// While a text annotation is edited (4b), these chords are left to the NSTextView.
    var passesThroughWhileEditingText: Bool {
        switch self {
        case .copy, .paste, .duplicate, .selectAll, .undo, .redo: true
        case .save, .saveAs, .copyImage, .upload, .uploadAsNew, .close, .zoomToFit, .actualSize, .zoomIn, .zoomOut: false
        }
    }

    /// The row for a key event, or nil. `characters` is `NSEvent.charactersIgnoringModifiers`
    /// (⇧⌘S gives "S", ⌥⌘U gives "u"), compared in lower case. Command is required and Control
    /// rules a chord out. While `isEditingText`, the pass-through rows return nil.
    static func match(characters: String, command: Bool, shift: Bool, option: Bool, control: Bool, isEditingText: Bool) -> EditorShortcut? {
        guard command, !control else { return nil }
        let pressed = Chord(key: characters.lowercased(), shift: shift, option: option)
        guard let shortcut = allCases.first(where: { $0.chord == pressed }) else { return nil }
        if isEditingText && shortcut.passesThroughWhileEditingText {
            return nil
        }
        return shortcut
    }
}

/// While a text annotation is being typed, the chords `EditorShortcut` leaves to the text view
/// (its `passesThroughWhileEditingText` rows, and ⌘X, which has no row). `EditorWindow` sends them
/// to the first responder itself, so they reach the NSTextView, and ⌘Z its own UndoManager, whether
/// or not the never-drawn main menu has an Edit menu.
nonisolated enum TextEditingChord {
    static func selectorName(characters: String, command: Bool, shift: Bool, option: Bool, control: Bool) -> String? {
        guard command, !option, !control else { return nil }
        switch (characters.lowercased(), shift) {
        case ("c", false): return "copy:"
        case ("x", false): return "cut:"
        case ("v", false): return "paste:"
        case ("a", false): return "selectAll:"
        case ("z", false): return "undo:"
        case ("z", true): return "redo:"
        default: return nil
        }
    }
}
