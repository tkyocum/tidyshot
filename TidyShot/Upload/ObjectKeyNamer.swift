import Foundation

/// Builds S3 object keys from a template such as `shots/{year}/{month}/{hostname}-{random:8}`,
/// expanded by `TemplateExpander` in the object-key style and followed by the extension. The
/// default `{random:6}` gives the Phase 2 behaviour: `aSIS7x.png`.
///
/// Keys stay URL-safe: literal text is limited to `[A-Za-z0-9._-/]` (checked by `validate`) and
/// tokens never emit anything outside `[A-Za-z0-9._-]`. `/` separates folders; leading, trailing
/// and doubled slashes are folded away.
nonisolated struct ObjectKeyNamer: Sendable {
    static let defaultTemplate = "{random:6}"
    static let literalCharacters = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._-/")

    enum TemplateError: LocalizedError, Equatable, Sendable {
        case empty
        case illegalCharacter(Character)
        case unknownToken(String)
        case unbalancedBraces
        case dotSegment(String)

        var errorDescription: String? {
            switch self {
            case .empty: "The key template is empty."
            case .illegalCharacter(let character): "\"\(character)\" is not allowed in a key template; use letters, digits, . _ - and / outside tokens."
            case .unknownToken(let name): "{\(name)} is not a token. Tokens: \(TemplateExpander.tokenList)."
            case .unbalancedBraces: "Every { needs a matching }."
            case .dotSegment(let segment): "A folder cannot be \"\(segment)\"."
            }
        }
    }

    var template: String
    var randomString: @Sendable (Int) -> String

    init(template: String = ObjectKeyNamer.defaultTemplate,
         randomString: @escaping @Sendable (Int) -> String = FileNamer.randomString) {
        self.template = template
        self.randomString = randomString
    }

    /// `shots/2026/10/miffle-aB3dE9fG.png`: the template expanded for `context`, folded, plus
    /// `.ext` (`ext` without a dot). A template that expands to nothing falls back to six random
    /// characters so a key is never just `.png`.
    func makeKey(ext: String, context: TemplateContext) -> String {
        let expander = TemplateExpander(randomString: randomString)
        var name = Self.normalize(expander.expand(template, context: context, style: .objectKey))
        if name.isEmpty {
            name = randomString(TemplateExpander.defaultRandomLength)
        }
        return name + "." + ext
    }

    /// Trims whitespace and folds slashes. Saved templates, validation and expanded keys all go
    /// through this.
    static func normalize(_ template: String) -> String {
        fold(template.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// Removes leading, trailing and repeated slashes: `/a//b/` becomes `a/b`.
    static func fold(_ key: String) -> String {
        key.split(separator: "/", omittingEmptySubsequences: true).joined(separator: "/")
    }

    /// The first problem with `template`, or nil when it can be saved.
    static func validate(_ template: String) -> TemplateError? {
        let normalized = normalize(template)
        guard !normalized.isEmpty else { return .empty }
        for case .literal(let text) in TemplateExpander.parse(normalized) {
            if let open = text.firstIndex(of: "{") {
                guard let close = text[open...].firstIndex(of: "}") else { return .unbalancedBraces }
                return .unknownToken(String(text[text.index(after: open)..<close]))
            }
            if text.contains("}") { return .unbalancedBraces }
            if let bad = text.first(where: { !literalCharacters.contains($0) }) { return .illegalCharacter(bad) }
        }
        for segment in normalized.split(separator: "/") where segment.allSatisfy({ $0 == "." }) {
            return .dotSegment(String(segment))
        }
        return nil
    }

    /// Shown in Settings when nothing in the template is guaranteed to differ between two
    /// captures. Nil when the template has `{random}`, `{random:N}` or `{counter}`.
    static func collisionWarning(for template: String) -> String? {
        TemplateExpander.hasCollisionGuard(template)
            ? nil
            : "This template has no {random} or {counter}, so captures can produce the same key; only the HEAD check before each upload keeps a capture from overwriting an earlier object."
    }

    /// `shots/2026/10` for `shots/2026/10/aB3dE9.png`, empty for a key without folders. The
    /// connection test uses it to put its probe object next to real uploads.
    static func folder(of key: String) -> String {
        guard let slash = key.lastIndex(of: "/") else { return "" }
        return String(key[..<slash])
    }

    /// The Phase 2 settings (optional prefix folder plus random length 4...32) as a template:
    /// prefix `shots` and length 8 become `shots/{random:8}`; no prefix and 6 become `{random:6}`.
    /// Phase 2 accepted any prefix text, so every character outside `literalCharacters` (a space,
    /// `+`, a brace) becomes `-`, slashes are folded, and folders made only of dots are dropped;
    /// the result always passes `validate`.
    static func migratedTemplate(prefix: String, length: Int) -> String {
        let mapped = String(prefix.trimmingCharacters(in: .whitespacesAndNewlines).map { literalCharacters.contains($0) ? $0 : "-" })
        let folder = mapped.split(separator: "/").filter { !$0.allSatisfy { $0 == "." } }.joined(separator: "/")
        let name = "{random:\(min(max(length, 4), 32))}"
        return folder.isEmpty ? name : "\(folder)/\(name)"
    }
}
