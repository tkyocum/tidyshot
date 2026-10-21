import AppKit

/// One annotation on the canvas for VoiceOver: an `AXLayoutItem` child of CanvasView. The label
/// and value are set by the canvas each time it lists its children; the frame and the selected
/// state are read from the canvas on every query, so they follow zoom, pan and selection.
///
/// `NSAccessibilityElement` is not main-actor isolated in the SDK, so the class is `nonisolated`
/// and each override steps onto the main actor, where AppKit's accessibility queries arrive.
nonisolated final class AnnotationAccessibilityElement: NSAccessibilityElement {
    let annotationID: UUID
    private weak var canvas: CanvasView?

    init(annotationID: UUID, canvas: CanvasView) {
        self.annotationID = annotationID
        self.canvas = canvas
        super.init()
        setAccessibilityElement(true)
        setAccessibilityRole(.layoutItem)
        setAccessibilityParent(canvas)
    }

    // The canvas and the id are read out first: both are Sendable, the element is not.

    override func accessibilityFrame() -> NSRect {
        let (canvas, id) = (canvas, annotationID)
        return MainActor.assumeIsolated { canvas?.accessibilityScreenFrame(of: id) ?? .zero }
    }

    override func isAccessibilitySelected() -> Bool {
        let (canvas, id) = (canvas, annotationID)
        return MainActor.assumeIsolated { canvas?.isAccessibilitySelected(id) ?? false }
    }

    /// AXPress selects the annotation; Delete, the arrow keys, ⌘C and ⌘D then act on it.
    override func accessibilityPerformPress() -> Bool {
        let (canvas, id) = (canvas, annotationID)
        return MainActor.assumeIsolated { canvas?.selectFromAccessibility(id) ?? false }
    }
}
