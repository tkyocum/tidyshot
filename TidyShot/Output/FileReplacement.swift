import Foundation

/// Puts a recording's Save As… copy in place: a copy of its file, or its download.
nonisolated enum FileReplacement {
    /// Puts a file at `destination` with `put`, which copies or moves one to the URL it is given.
    /// A new destination gets the file directly. An existing one (the save panel already asked)
    /// is replaced with `FileManager.replaceItemAt`, from a file put first into the replacement
    /// folder for it: `replaceItemAt` fails across volumes (EXDEV), and a Save As… target can be
    /// on any volume. A failed put leaves an existing file as it was. Touches only the file
    /// system, so callers on the main actor run it in a detached task.
    static func put(at destination: URL, _ put: (URL) throws -> Void) throws {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: destination.path(percentEncoded: false)) else {
            try put(destination)
            return
        }
        let staging = try fileManager.url(for: .itemReplacementDirectory, in: .userDomainMask,
                                          appropriateFor: destination, create: true)
        defer { try? fileManager.removeItem(at: staging) }
        let staged = staging.appending(path: destination.lastPathComponent)
        try put(staged)
        _ = try fileManager.replaceItemAt(destination, withItemAt: staged)
    }
}
