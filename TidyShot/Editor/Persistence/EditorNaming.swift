import Foundation

/// What the editor's Save As… panel suggests.
nonisolated enum EditorNaming {
    struct SaveAsSuggestion: Equatable, Sendable {
        /// `nameFieldStringValue`, with `.png`.
        var fileName: String
        /// The save folder, or nil to leave the panel where it last was.
        var directory: URL?
    }

    /// The record's own file name when it has a file in the save folder. Otherwise (no file, a
    /// pending `<id>.png` that is not the user's, or no record) the name `FileNamer` would give
    /// now, plus `.png`; `{counter}` uses `currentCounter` and draws nothing, so the next capture's
    /// number is unchanged. The directory is the save folder when one is set.
    @MainActor
    static func saveAsSuggestion(for record: CaptureRecord?, saveFolder: URL?, namer: FileNamer,
                                 currentCounter: Int) -> SaveAsSuggestion {
        let fileName: String
        if let record, let fileURL = record.fileURL, !record.fileIsTemporary, !fileURL.lastPathComponent.isEmpty {
            fileName = fileURL.lastPathComponent
        } else {
            let counter = namer.template.contains("{counter}") ? currentCounter : 0
            fileName = namer.name(counter: counter) + ".png"
        }
        return SaveAsSuggestion(fileName: fileName, directory: saveFolder)
    }
}
