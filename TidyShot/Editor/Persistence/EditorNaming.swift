import AppKit
import UniformTypeIdentifiers

/// What a Save As… panel suggests, for the editor and for a Quick Access card.
nonisolated enum EditorNaming {
    struct SaveAsSuggestion: Equatable, Sendable {
        /// `nameFieldStringValue`, with `.png`, or `.mp4` or `.gif` for a recording.
        var fileName: String
        /// The save folder, or nil to leave the panel where it last was.
        var directory: URL?
        /// The record's kind, which decides the extension and the panel's one allowed type.
        var mediaKind: MediaKind = .image
    }

    /// The record's own file name when it has a file in the save folder. Otherwise (no file, a
    /// pending `<id>.png`, `<id>.mp4` or `<id>.gif` that is not the user's, or no record) the name
    /// the file name template would give now, plus the kind's extension: `namer` for a screenshot,
    /// `recordingNamer` (`Recording file name`) for a recording, MP4 or GIF. `{counter}` uses
    /// `currentCounter` and draws nothing, so the next capture's number is unchanged. The
    /// directory is the save folder when one is set.
    @MainActor
    static func saveAsSuggestion(for record: CaptureRecord?, saveFolder: URL?, namer: FileNamer,
                                 recordingNamer: FileNamer, currentCounter: Int) -> SaveAsSuggestion {
        let kind = record?.mediaKind ?? .image
        let fileName: String
        if let record, let fileURL = record.fileURL, !record.fileIsTemporary, !fileURL.lastPathComponent.isEmpty {
            fileName = fileURL.lastPathComponent
        } else {
            let templateNamer = kind != .image ? recordingNamer : namer
            let counter = templateNamer.template.contains("{counter}") ? currentCounter : 0
            fileName = templateNamer.name(counter: counter) + "." + kind.fileExtension
        }
        return SaveAsSuggestion(fileName: fileName, directory: saveFolder, mediaKind: kind)
    }

    /// The Save As… panel for `suggestion`: the kind's one type (PNG, MPEG-4 movie or GIF), its
    /// name, and its folder when it has one (otherwise the panel opens where it last was). The
    /// editor shows it as a sheet, a Quick Access card as a window.
    @MainActor
    static func savePanel(for suggestion: SaveAsSuggestion) -> NSSavePanel {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [suggestion.mediaKind.utType]
        panel.nameFieldStringValue = suggestion.fileName
        if let directory = suggestion.directory {
            panel.directoryURL = directory
        }
        return panel
    }
}
