import Foundation

/// The name of a Quick Access card's drag file (spec 2.9, Drag-out).
nonisolated enum DragFileName {
    /// The last path component of the key behind the record's link (`uploadedKey`, or
    /// `priorUpload.key` while the editor uploads over a link), so the dropped file matches the
    /// link on the clipboard; `:` becomes `-`, a leading `.` becomes `_`, and for an image `.png`
    /// is added when the name does not end in it. A recording's key keeps its own extension.
    /// Without a key, or for a key ending in `/`, the Save As suggestion's file name, whose
    /// extension comes from the record's kind.
    static func name(for record: CaptureRecord, suggestion: EditorNaming.SaveAsSuggestion) -> String {
        guard let key = record.uploadedKey ?? record.priorUpload?.key,
              let last = key.split(separator: "/", omittingEmptySubsequences: false).last, !last.isEmpty else {
            return suggestion.fileName
        }
        var name = last.replacingOccurrences(of: ":", with: "-")
        if name.hasPrefix(".") {
            name = "_" + name.dropFirst()
        }
        if record.mediaKind == .image, !name.lowercased().hasSuffix(".png") {
            name += ".png"
        }
        return name
    }
}
