import Foundation

/// Which spotlights the overlay shows (spec 2.12, Rendering). Pure, so a test reaches it, like
/// `RedactionTileCache.orderedEffects`.
nonisolated enum SpotlightGeometry {
    /// The document's spotlights in creation order. A spotlight `transient` with the id of one in
    /// the document (one being moved or resized) takes its place; a new one comes last. A transient
    /// of any other kind is ignored. `EditorFlattener` has no transient and uses
    /// `document.spotlights`.
    static func displayedSpotlights(in document: AnnotationDocument, transient: Annotation?) -> [Annotation] {
        var spotlights = document.spotlights
        guard let transient, transient.isSpotlight else { return spotlights }
        if let index = spotlights.firstIndex(where: { $0.id == transient.id }) {
            spotlights[index] = transient
        } else {
            spotlights.append(transient)
        }
        return spotlights
    }
}
