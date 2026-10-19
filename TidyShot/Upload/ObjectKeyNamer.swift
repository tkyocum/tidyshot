import Foundation

/// Builds S3 object keys: an optional prefix folder, a random name, and an extension,
/// for example `shots/aSIS7x.png`. Random characters come from `FileNamer.randomString`.
nonisolated struct ObjectKeyNamer: Sendable {
    static let lengthRange = 4...32
    static let defaultLength = 6

    var prefix: String
    var length: Int
    var randomString: @Sendable (Int) -> String

    init(prefix: String = "", length: Int = ObjectKeyNamer.defaultLength,
         randomString: @escaping @Sendable (Int) -> String = FileNamer.randomString) {
        self.prefix = prefix
        self.length = length
        self.randomString = randomString
    }

    /// `prefix/RANDOM.ext`, or `RANDOM.ext` without a prefix. `ext` is given without a dot.
    func makeKey(ext: String) -> String {
        let name = randomString(Self.clamp(length)) + "." + ext
        return Self.join(prefix: prefix, name: name)
    }

    static func clamp(_ length: Int) -> Int {
        min(max(length, lengthRange.lowerBound), lengthRange.upperBound)
    }

    /// Trims whitespace and slashes from `prefix` and joins it to `name` with one slash.
    static func join(prefix: String, name: String) -> String {
        let cleaned = normalizePrefix(prefix)
        return cleaned.isEmpty ? name : "\(cleaned)/\(name)"
    }

    static func normalizePrefix(_ prefix: String) -> String {
        prefix
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }
}
