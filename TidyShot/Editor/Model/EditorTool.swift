/// The editor's tools. `toolbarOrder` is the only source for the toolbar's tools group, and
/// `makeTool(for:)` switches over every case with no default, so a new case is wired in both.
nonisolated enum EditorTool: String, CaseIterable, Sendable {
    case select, redact, pixelate, blur, rectangle, arrow

    /// The unmodified key that picks the tool, in upper case.
    var letter: Character {
        switch self {
        case .select: "V"
        case .redact: "D"
        case .pixelate: "X"
        case .blur: "B"
        case .rectangle: "R"
        case .arrow: "A"
        }
    }

    var title: String {
        switch self {
        case .select: "Select"
        case .redact: "Redact"
        case .pixelate: "Pixelate"
        case .blur: "Blur"
        case .rectangle: "Rectangle"
        case .arrow: "Arrow"
        }
    }

    /// The SF Symbol for the toolbar.
    var symbolName: String {
        switch self {
        case .select: "cursorarrow"
        case .redact: "rectangle.fill"
        case .pixelate: "checkerboard.rectangle"
        case .blur: "drop.halffull"
        case .rectangle: "rectangle"
        case .arrow: "arrow.up.right"
        }
    }

    /// The toolbar tooltip: the title and the key, for example "Redact (D)".
    var tooltip: String { "\(title) (\(letter))" }

    /// Redact, pixelate and blur make effects, which render beneath every drawing.
    var isEffect: Bool {
        switch self {
        case .redact, .pixelate, .blur: true
        case .select, .rectangle, .arrow: false
        }
    }

    /// Select, then Redact first among the drawing tools, because it is the only safe redaction.
    /// 4b inserts its tools here.
    static var toolbarOrder: [EditorTool] {
        [.select, .redact, .pixelate, .blur, .rectangle, .arrow]
    }

    /// The tool whose letter is `key`, in either case; nil for any other key.
    static func tool(forKey key: Character) -> EditorTool? {
        let typed = String(key).uppercased()
        return allCases.first { String($0.letter) == typed }
    }
}
