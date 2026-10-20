import Foundation

/// Expands the local file name template with `TemplateExpander` in the file-name style and
/// sanitises the result for the file system. The extension is not part of the template.
struct FileNamer {
    static let defaultTemplate = "Screenshot {date} at {time}"

    var template: String
    var now: () -> Date
    var randomString: @Sendable (Int) -> String
    var hostname: String

    init(template: String = FileNamer.defaultTemplate,
         now: @escaping () -> Date = { Date() },
         randomString: @escaping @Sendable (Int) -> String = FileNamer.randomString,
         hostname: String = HostName.local()) {
        self.template = template
        self.now = now
        self.randomString = randomString
        self.hostname = hostname
    }

    func name(counter: Int) -> String {
        let context = TemplateContext(date: now(), counter: counter, hostname: hostname)
        let expanded = TemplateExpander(randomString: randomString).expand(template, context: context, style: .fileName)
        let sanitized = Self.sanitize(expanded)
        return sanitized.isEmpty ? "Screenshot" : sanitized
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
