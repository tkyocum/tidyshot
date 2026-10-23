/// The editor's tools. `toolbarOrder` is the only source for the toolbar's tools group, and
/// `makeTool(for:)` switches over every case with no default, so a new case is wired in both.
nonisolated enum EditorTool: String, CaseIterable, Sendable {
    case select, redact, pixelate, blur, spotlight, rectangle, arrow, ellipse, line, pencil, highlighter, text, counter, crop

    /// The unmodified key that picks the tool, in upper case.
    var letter: Character {
        switch self {
        case .select: "V"
        case .redact: "D"
        case .pixelate: "X"
        case .blur: "B"
        case .spotlight: "S"
        case .rectangle: "R"
        case .arrow: "A"
        case .ellipse: "E"
        case .line: "L"
        case .pencil: "P"
        case .highlighter: "H"
        case .text: "T"
        case .counter: "N"
        case .crop: "C"
        }
    }

    var title: String {
        switch self {
        case .select: "Select"
        case .redact: "Redact"
        case .pixelate: "Pixelate"
        case .blur: "Blur"
        case .spotlight: "Spotlight"
        case .rectangle: "Rectangle"
        case .arrow: "Arrow"
        case .ellipse: "Ellipse"
        case .line: "Line"
        case .pencil: "Pencil"
        case .highlighter: "Highlighter"
        case .text: "Text"
        case .counter: "Counter"
        case .crop: "Crop"
        }
    }

    /// The SF Symbol for the toolbar.
    var symbolName: String {
        switch self {
        case .select: "cursorarrow"
        case .redact: "rectangle.fill"
        case .pixelate: "checkerboard.rectangle"
        case .blur: "drop.halffull"
        case .spotlight: "light.max"
        case .rectangle: "rectangle"
        case .arrow: "arrow.up.right"
        case .ellipse: "circle"
        case .line: "line.diagonal"
        case .pencil: "pencil"
        case .highlighter: "highlighter"
        case .text: "textformat"
        case .counter: "1.circle"
        case .crop: "crop"
        }
    }

    /// The toolbar tooltip: the title and the key, for example "Redact (D)".
    var tooltip: String { "\(title) (\(letter))" }

    /// Redact, pixelate and blur make effects, which render beneath every drawing. Spotlight is not
    /// one: it gets no tile.
    var isEffect: Bool {
        switch self {
        case .redact, .pixelate, .blur: true
        case .select, .spotlight, .rectangle, .arrow, .ellipse, .line, .pencil, .highlighter, .text, .counter, .crop: false
        }
    }

    /// Select, then Redact first among the drawing tools, because it is the only safe redaction.
    /// Spotlight follows the effects, since it works on the picture as they do, and Counter follows
    /// Text.
    static var toolbarOrder: [EditorTool] {
        [.select, .redact, .pixelate, .blur, .spotlight, .rectangle, .arrow, .ellipse, .line, .pencil, .highlighter,
         .text, .counter, .crop]
    }

    /// The tool whose letter is `key`, in either case; nil for any other key.
    static func tool(forKey key: Character) -> EditorTool? {
        let typed = String(key).uppercased()
        return allCases.first { String($0.letter) == typed }
    }
}
