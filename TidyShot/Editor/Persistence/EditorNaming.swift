import AppKit
import UniformTypeIdentifiers

/// What a Save As… panel suggests, for the editor and for a Quick Access card.
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

    /// The Save As… panel for `suggestion`: PNG only, its name, and its folder when it has one
    /// (otherwise the panel opens where it last was). The editor shows it as a sheet, a Quick
    /// Access card as a window.
    @MainActor
    static func savePanel(for suggestion: SaveAsSuggestion) -> NSSavePanel {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = suggestion.fileName
        if let directory = suggestion.directory {
            panel.directoryURL = directory
        }
        return panel
    }
}
