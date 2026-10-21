import Foundation

/// Which editor action a selector runs, and whether the available set lets it through. Asked by
/// the controller's validation (which EditorWindow consults before sending a shortcut) and again
/// by every action method.
nonisolated enum EditorCommandGate {
    static func action(for selectorName: String) -> EditorAction? {
        switch selectorName {
        case "saveDocument:": .save
        case "saveDocumentCopy:": .saveCopy
        case "copy:", "copyImage:": .copy
        case "uploadDocument:": .upload
        case "uploadDocumentAsNew:": .uploadAsNew
        default: nil
        }
    }

    /// Selectors that are not editor actions (undo, zoom, close, select all) always pass; their
    /// own validation decides.
    static func permits(_ selectorName: String, available: Set<EditorAction>) -> Bool {
        guard let action = action(for: selectorName) else { return true }
        return available.contains(action)
    }
}
