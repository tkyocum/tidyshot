import CoreGraphics
import Foundation

/// The edits on one capture, in creation order. The base image is not part of it: EditorModel
/// holds the CGImage next to the document and never changes it.
nonisolated struct AnnotationDocument: Codable, Equatable, Sendable {
    var annotations: [Annotation] = []

    /// Redact, blur and pixelate, in creation order. They render first, on the base layer.
    var effects: [Annotation] { annotations.filter(\.isEffect) }

    /// Every other annotation, in creation order, drawn above all effects.
    var drawings: [Annotation] { annotations.filter { !$0.isEffect } }

    func annotation(id: UUID) -> Annotation? {
        annotations.first { $0.id == id }
    }

    func appending(_ annotation: Annotation) -> AnnotationDocument {
        var copy = self
        copy.annotations.append(annotation)
        return copy
    }

    func removing(id: UUID) -> AnnotationDocument {
        var copy = self
        copy.annotations.removeAll { $0.id == id }
        return copy
    }

    /// Puts `annotation` where the annotation with its id sits, so the creation order is kept.
    /// Unchanged when no annotation has that id.
    func replacing(_ annotation: Annotation) -> AnnotationDocument {
        guard let index = annotations.firstIndex(where: { $0.id == annotation.id }) else { return self }
        var copy = self
        copy.annotations[index] = annotation
        return copy
    }

    /// Unchanged when no annotation has that id.
    func moving(id: UUID, by delta: CGVector) -> AnnotationDocument {
        guard let annotation = annotation(id: id) else { return self }
        return replacing(annotation.moved(by: delta))
    }
}
