import Foundation

/// What VoiceOver reads on the canvas: one item per annotation, in painting order (effects, then
/// drawings, each in creation order). CanvasView turns each into an `AnnotationAccessibilityElement`.
nonisolated enum CanvasAccessibility {
    static let canvasLabel = "Annotation canvas"

    struct Item: Equatable, Sendable {
        let id: UUID
        /// The kind and a number counted per kind in painting order: "Redact 1", "Arrow 2".
        let label: String
        let value: String?
    }

    static func items(in document: AnnotationDocument) -> [Item] {
        var counts: [String: Int] = [:]
        return (document.effects + document.drawings).map { annotation in
            let number = (counts[annotation.title] ?? 0) + 1
            counts[annotation.title] = number
            return Item(id: annotation.id, label: "\(annotation.title) \(number)", value: value(of: annotation))
        }
    }

    /// A text annotation's string; nil for every other kind.
    static func value(of annotation: Annotation) -> String? {
        if case .text(let box) = annotation { return box.string }
        return nil
    }
}
