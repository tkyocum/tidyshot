import Foundation

/// The file name of a Save Copy from the editor.
nonisolated enum EditorNaming {
    /// `<original stem> edited` when the original has a file, in the save folder or in `pending`.
    /// `SaveLocation.write` makes it unique through `FileNamer.uniqueURL` (`… edited 2`, …). Nil
    /// when the original has no file or no record any more (deleted or pruned); the copy is then
    /// named from the file name template, with `{counter}` drawn as for a capture.
    static func copyBaseName(for record: CaptureRecord?) -> String? {
        guard let fileURL = record?.fileURL else { return nil }
        let stem = fileURL.deletingPathExtension().lastPathComponent
        guard !stem.isEmpty else { return nil }
        return "\(stem) edited"
    }
}
