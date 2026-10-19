import Foundation

/// Expands a file name template. Tokens: {date} {time} {datetime} {app} {counter} {random} {random:N}.
/// The extension is not part of the template.
struct FileNamer {
    static let defaultTemplate = "Screenshot {date} at {time}"

    var template: String
    var now: () -> Date
    var randomString: (Int) -> String

    init(template: String = FileNamer.defaultTemplate,
         now: @escaping () -> Date = { Date() },
         randomString: @escaping (Int) -> String = FileNamer.randomString) {
        self.template = template
        self.now = now
        self.randomString = randomString
    }

    func name(appName: String?, counter: Int) -> String {
        let date = now()
        var result = template
        result = result.replacingOccurrences(of: "{datetime}", with: Self.format(date, "yyyy-MM-dd HH.mm.ss"))
        result = result.replacingOccurrences(of: "{date}", with: Self.format(date, "yyyy-MM-dd"))
        result = result.replacingOccurrences(of: "{time}", with: Self.format(date, "HH.mm.ss"))
        result = result.replacingOccurrences(of: "{app}", with: appName ?? "Screen")
        result = result.replacingOccurrences(of: "{counter}", with: String(counter))
        result = expandRandom(in: result)
        let sanitized = Self.sanitize(result)
        return sanitized.isEmpty ? "Screenshot" : sanitized
    }

    private func expandRandom(in input: String) -> String {
        let pattern = /\{random(?::(\d+))?\}/
        var result = input
        while let match = result.firstMatch(of: pattern) {
            let requested = match.output.1.flatMap { Int($0) } ?? 6
            let length = min(max(requested, 1), 64)
            result.replaceSubrange(match.range, with: randomString(length))
        }
        return result
    }

    static func format(_ date: Date, _ pattern: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = pattern
        return formatter.string(from: date)
    }

    /// Removes characters that are illegal or awkward in file names.
    static func sanitize(_ input: String) -> String {
        var output = input
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if output.hasPrefix(".") {
            output = "_" + output.dropFirst()
        }
        return output
    }

    /// `nonisolated` so it can be the default for the non-isolated `randomString` closure parameter.
    nonisolated static func randomString(length: Int) -> String {
        let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789")
        return String((0..<length).map { _ in alphabet.randomElement()! })
    }

    /// Returns `baseName.ext` in `directory`, or `baseName 2.ext`, `baseName 3.ext`, ... if taken.
    static func uniqueURL(baseName: String, ext: String, in directory: URL, fileManager: FileManager = .default) -> URL {
        var candidate = directory.appendingPathComponent(baseName).appendingPathExtension(ext)
        var suffix = 2
        while fileManager.fileExists(atPath: candidate.path) {
            candidate = directory.appendingPathComponent("\(baseName) \(suffix)").appendingPathExtension(ext)
            suffix += 1
        }
        return candidate
    }
}
