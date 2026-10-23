import Foundation

/// What VoiceOver reads on the canvas: one item per annotation, in painting order (effects, then
/// spotlights, then drawings, each in creation order; spec 2.12 overrides 2.6's "every effect, then
/// every drawing"). CanvasView turns each into an `AnnotationAccessibilityElement`.
nonisolated enum CanvasAccessibility {
    static let canvasLabel = "Annotation canvas"

    struct Item: Equatable, Sendable {
        let id: UUID
        /// The kind and a number counted per kind in painting order: "Redact 1", "Arrow 2".
        let label: String
        let value: String?
    }

    /// With a crop applied the canvas shows only the crop, so only annotations that reach into it
    /// are listed (the rule `EditorModel.selectAll` uses). Numbering counts the listed ones.
    static func items(in document: AnnotationDocument, scale: CGFloat) -> [Item] {
        var counts: [String: Int] = [:]
        let listed = (document.effects + document.spotlights + document.drawings).filter { annotation in
            guard let crop = document.crop else { return true }
            let bounds = annotation.effectRect ?? AnnotationGeometry.bounds(of: annotation, scale: scale)
            return bounds.intersects(crop)
        }
        return listed.map { annotation in
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
