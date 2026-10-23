import AppKit
import SwiftUI

/// Wraps `QuickAccessCardDragView` for SwiftUI. The card puts one in its background (a press
/// does nothing but drag) and one over its thumbnail (a click reveals a local file, or opens a
/// recording).
struct QuickAccessCardDragSource: NSViewRepresentable {
    let model: QuickAccessModel
    /// A press and release without a drag. Nil: nothing.
    var onClick: (() -> Void)? = nil
    var toolTip: String? = nil

    func makeNSView(context: Context) -> QuickAccessCardDragView {
        let view = QuickAccessCardDragView()
        updateNSView(view, context: context)
        return view
    }

    func updateNSView(_ view: QuickAccessCardDragView, context: Context) {
        view.model = model
        view.onClick = onClick
        view.toolTip = toolTip
    }
}

/// The drag-out surface of a Quick Access card (spec 2.9). A press asks for the drag file to be
/// staged; once the pointer has moved `dragThreshold` points and the file exists, a session starts
/// with the file URL. A file that is not staged yet makes the drag wait for the next
/// mouse-dragged event; for a restored card still downloading, the drag does nothing.
final class QuickAccessCardDragView: NSView, NSDraggingSource {
    /// How far the pointer moves, in points, before a press becomes a drag.
    static let dragThreshold: CGFloat = 3
    /// The drag image's box: the card's thumbnail well.
    static let dragImageBox = CGSize(width: 96, height: 72)

    weak var model: QuickAccessModel?
    var onClick: (() -> Void)?
    private var mouseDownEvent: NSEvent?
    private var dragStarted = false
    /// The pointer has passed `dragThreshold` since the press: a release is not a click, also
    /// when the drag never started because the file was not ready.
    private var movedPastThreshold = false

    // The card's panel never becomes key and TidyShot is usually not active.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    override func mouseDown(with event: NSEvent) {
        // Control-click is the context menu (Task 4): leave it to the responder chain.
        if event.modifierFlags.contains(.control) {
            super.mouseDown(with: event)
            return
        }
        mouseDownEvent = event
        dragStarted = false
        movedPastThreshold = false
        model?.onPrepareDrag()
    }

    override func mouseDragged(with event: NSEvent) {
        guard !dragStarted, let down = mouseDownEvent, let model else { return }
        let dx = event.locationInWindow.x - down.locationInWindow.x
        let dy = event.locationInWindow.y - down.locationInWindow.y
        guard movedPastThreshold || dx * dx + dy * dy >= Self.dragThreshold * Self.dragThreshold else { return }
        movedPastThreshold = true
        guard let fileURL = model.dragFileURL else { return }
        dragStarted = true
        model.isDraggingOut = true
        let item = NSDraggingItem(pasteboardWriter: fileURL as NSURL)
        let placeholder = model.record.isVideo ? "film" : "photo"
        let image = model.thumbnail ?? NSImage(systemSymbolName: placeholder, accessibilityDescription: nil) ?? NSImage()
        item.setDraggingFrame(Self.dragFrame(imageSize: image.size, centredOn: convert(down.locationInWindow, from: nil)),
                              contents: image)
        let session = beginDraggingSession(with: [item], event: event, source: self)
        session.animatesToStartingPositionsOnCancelOrFail = true
    }

    override func mouseUp(with event: NSEvent) {
        defer { mouseDownEvent = nil }
        if mouseDownEvent != nil, !dragStarted, !movedPastThreshold {
            onClick?()
        }
    }

    /// The image fitted in `dragImageBox` (never enlarged), centred on `point`.
    static func dragFrame(imageSize: CGSize, centredOn point: CGPoint) -> CGRect {
        let fit = imageSize.width > 0 && imageSize.height > 0
            ? min(1, dragImageBox.width / imageSize.width, dragImageBox.height / imageSize.height)
            : 1
        let size = CGSize(width: imageSize.width * fit, height: imageSize.height * fit)
        return CGRect(x: point.x - size.width / 2, y: point.y - size.height / 2, width: size.width, height: size.height)
    }

    // MARK: NSDraggingSource

    /// Copy is the only operation, and only to other apps: nothing in TidyShot takes a drop.
    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        context == .outsideApplication ? .copy : []
    }

    func ignoreModifierKeys(for session: NSDraggingSession) -> Bool { true }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        mouseDownEvent = nil
        dragStarted = false
        model?.isDraggingOut = false
        model?.onDragEnded(operation != [])
    }
}
