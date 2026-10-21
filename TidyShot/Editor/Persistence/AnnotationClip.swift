import CoreGraphics
import Foundation

/// One annotation on the pasteboard, for object copy and paste (4b). It travels as JSON under the
/// private type `pasteboardTypeName` only. The annotation keeps its image-pixel geometry, and
/// `scale` says which capture scale those pixels belong to, so a paste into an editor at another
/// scale keeps the size in points. AppCoordinator does the pasteboard I/O (`Pasteboard`).
nonisolated struct AnnotationClip: Codable, Equatable, Sendable {
    static let pasteboardTypeName = "io.tky.tidyshot.annotation"
    static let currentFormatVersion = 1
    /// How many duplicate offsets a paste may step to get clear of identical annotations.
    static let maximumCascade = 100

    var formatVersion: Int
    var annotation: Annotation
    /// Image pixels per point of the capture the annotation was copied from.
    var scale: CGFloat

    init(annotation: Annotation, scale: CGFloat) {
        formatVersion = Self.currentFormatVersion
        self.annotation = annotation
        self.scale = scale
    }

    func encoded() -> Data? {
        try? JSONEncoder().encode(self)
    }

    /// Nil for anything this build cannot paste: not JSON of a clip, another format version, or a
    /// scale that is not a positive number.
    static func decoded(from data: Data) -> AnnotationClip? {
        guard let clip = try? JSONDecoder().decode(AnnotationClip.self, from: data),
              clip.formatVersion == currentFormatVersion,
              clip.scale.isFinite, clip.scale > 0 else { return nil }
        return clip
    }

    /// The annotation as it lands in `document`, an image of `imageSize` pixels at `scale`:
    /// 1. scaled by `scale / self.scale` and given `id`;
    /// 2. centred in the image when its bounds lie wholly outside it;
    /// 3. moved by `step` while an annotation identical apart from its id is already there, at
    ///    most `maximumCascade` times, so repeated pastes step aside instead of stacking.
    func placed(in document: AnnotationDocument, imageSize: CGSize, scale: CGFloat, step: CGVector, id: UUID) -> Annotation {
        var pasted = annotation.scaled(by: scale / self.scale).withID(id)
        let image = CGRect(origin: .zero, size: imageSize)
        let bounds = AnnotationGeometry.bounds(of: pasted, scale: scale)
        if !bounds.intersects(image) {
            pasted = pasted.moved(by: CGVector(dx: image.midX - bounds.midX, dy: image.midY - bounds.midY))
        }
        var steps = 0
        while steps < Self.maximumCascade, document.annotations.contains(where: { $0.withID(id) == pasted }) {
            pasted = pasted.moved(by: step)
            steps += 1
        }
        return pasted
    }
}
