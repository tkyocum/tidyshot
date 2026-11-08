import CoreGraphics
import Foundation

/// The edits on one capture, in creation order. The base image is not part of it: EditorModel
/// holds the CGImage next to the document and never changes it.
nonisolated struct AnnotationDocument: Codable, Equatable, Sendable {
    var annotations: [Annotation] = []
    /// The part of the capture export keeps, in image pixels (top-left origin), as
    /// `CropGeometry.integralCrop` gives it: whole pixels, inside the image, never the whole image.
    /// Nil keeps the whole capture. `EditorFlattener` applies it last. Optional, so the synthesized
    /// decoder reads it with `decodeIfPresent` and a document without the key has no crop.
    var crop: CGRect? = nil
    /// What export puts the capture (or its crop) on (spec 2.11); nil for none. Optional, so a
    /// document without the key, written before 7c, decodes with no background.
    var background: BackgroundStyle? = nil
    /// The spotlight overlay's black alpha (spec 2.12), one value for the whole document; nil reads
    /// as `defaultSpotlightDim`, which `withSpotlightDim` stores as nil. Optional, so a document
    /// written before 4c decodes with the default.
    var spotlightDim: Double? = nil

    static let defaultSpotlightDim = 0.5

    var effectiveSpotlightDim: Double { spotlightDim ?? Self.defaultSpotlightDim }

    /// Redact, blur and pixelate, in creation order. They render first, on the base layer.
    var effects: [Annotation] { annotations.filter(\.isEffect) }

    /// The spotlights, in creation order: a third list, painted as one overlay between the effects
    /// and the drawings.
    var spotlights: [Annotation] { annotations.filter(\.isSpotlight) }

    /// Every other annotation, in creation order, drawn above all effects and the spotlight overlay.
    var drawings: [Annotation] { annotations.filter { !$0.isEffect && !$0.isSpotlight } }

    /// The annotations `layer` picks, in creation order, with `transient` in place of its document
    /// copy (one being moved or resized) or last when it is new. A transient of another layer is
    /// ignored. The tile cache shows the effects this way, the overlay the spotlights.
    func displayed(inLayer layer: (Annotation) -> Bool, transient: Annotation?) -> [Annotation] {
        var shown = annotations.filter(layer)
        guard let transient, layer(transient) else { return shown }
        if let index = shown.firstIndex(where: { $0.id == transient.id }) {
            shown[index] = transient
        } else {
            shown.append(transient)
        }
        return shown
    }

    /// The number a new counter gets (spec 2.12, Number): one more than the largest counter number,
    /// or 1 with none. Deleting a counter renumbers nothing.
    var nextCounterNumber: Int {
        (annotations.compactMap { $0.counterMark?.number }.max() ?? 0) + 1
    }

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

    func withCrop(_ crop: CGRect?) -> AnnotationDocument {
        var copy = self
        copy.crop = crop
        return copy
    }

    func withBackground(_ background: BackgroundStyle?) -> AnnotationDocument {
        var copy = self
        copy.background = background
        return copy
    }

    /// The default is stored as nil, so picking it again equals a document that never had a dim.
    func withSpotlightDim(_ dim: Double) -> AnnotationDocument {
        var copy = self
        copy.spotlightDim = dim == Self.defaultSpotlightDim ? nil : dim
        return copy
    }
}
