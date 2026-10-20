import Foundation

/// Rewrites naming templates saved before Phase 3.1, when `{app}` was still a token. Applied when
/// `AppSettings` loads the file name template and when `S3DestinationConfig` decodes its key
/// template, so a stored template never reaches `TemplateExpander` with `{app}` in it (it would
/// now be literal text in a file name, and an invalid key template).
nonisolated enum TemplateMigration {
    static let removedAppToken = "{app}"
    /// Separators that deleting the token can bring together; the pair collapses to one.
    static let separators: Set<Character> = ["-", "_", " ", "/"]
    /// Separators that deleting the token can leave dangling; a dangling one is dropped. A `.` is
    /// in neither set: it is never touched.
    static let danglingSeparators: Set<Character> = ["-", "_", " "]

    /// `template` without `{app}`, tidied only where the token was:
    /// - two separators it brought together become one, a `/` winning over the others
    ///   (`shots/{app}/{random:8}` and `shots/{app}-{random}` become `shots/{random:8}` and
    ///   `shots/{random}`, `{date}_{app}_{random}` becomes `{date}_{random}`);
    /// - a `-`, `_` or space it left at the start or end of the template or of a path segment, or
    ///   next to a `.`, goes (`{app} {datetime}` becomes `{datetime}`, `Screenshot {date} {app}`
    ///   becomes `Screenshot {date}`, `{random}-{app}.png` becomes `{random}.png`), and so does a
    ///   `/` left at either end of the template (`{app}/{date}` becomes `{date}`);
    /// - a `.` stays (`shots/{app}.png` becomes `shots/.png`, which validation then handles as it
    ///   does any template).
    /// Text away from the token is never touched. A template left blank becomes `fallback`, and
    /// the original is logged so the change can be traced; callers store the result, so that
    /// happens once per stored template.
    static func removingAppToken(from template: String, fallback: String) -> String {
        guard template.contains(removedAppToken) else { return template }
        let token = Array(removedAppToken)
        var characters = Array(template)
        while let start = firstIndex(of: token, in: characters) {
            characters.removeSubrange(start..<(start + token.count))
            tidySeparators(&characters, around: start)
        }
        let result = String(characters)
        guard result.trimmingCharacters(in: .whitespaces).isEmpty else { return result }
        NSLog("Naming template \"\(template)\" held only the removed \(removedAppToken) token; using \"\(fallback)\" instead")
        return fallback
    }

    /// Tidies the separators beside `gap`, where the token was: `characters[gap - 1]` is the
    /// character before it and `characters[gap]` the one after.
    private static func tidySeparators(_ characters: inout [Character], around gap: Int) {
        var gap = gap
        // Brought together: keep one, the `/` when there is one.
        if gap > 0, gap < characters.count,
           separators.contains(characters[gap - 1]), separators.contains(characters[gap]) {
            if characters[gap] == "/", characters[gap - 1] != "/" {
                characters.remove(at: gap - 1)
                gap -= 1
            } else {
                characters.remove(at: gap)
            }
        }
        // Dangling: the other side of the gap is an end of the template, a `/` or a `.`.
        func isEdge(_ index: Int) -> Bool {
            index < 0 || index >= characters.count || characters[index] == "/" || characters[index] == "."
        }
        if gap < characters.count, danglingSeparators.contains(characters[gap]), isEdge(gap - 1) {
            characters.remove(at: gap)
        } else if gap > 0, danglingSeparators.contains(characters[gap - 1]), isEdge(gap) {
            characters.remove(at: gap - 1)
        } else if gap == 0, characters.first == "/" {
            characters.removeFirst()
        } else if gap > 0, gap == characters.count, characters.last == "/" {
            characters.removeLast()
        }
    }

    private static func firstIndex(of needle: [Character], in haystack: [Character]) -> Int? {
        guard haystack.count >= needle.count else { return nil }
        return (0...(haystack.count - needle.count)).first { Array(haystack[$0..<($0 + needle.count)]) == needle }
    }
}
