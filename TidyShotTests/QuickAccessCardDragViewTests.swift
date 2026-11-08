import AppKit
import Testing
@testable import TidyShot

/// A Quick Access card's drag surface (`QuickAccessCardDragView`; R4 design, Drag-out download): a press stages the
/// drag file, and past the 3 pt threshold with no file yet it asks for the download, once per press. With no drag
/// file no dragging session starts, so the view needs no window: it reads only the events' `locationInWindow`.
struct QuickAccessCardDragViewTests {
    final class Asked {
        var prepares = 0
        var downloads = 0
    }

    func event(_ type: NSEvent.EventType, at point: CGPoint) -> NSEvent {
        NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
                           eventNumber: 0, clickCount: 1, pressure: type == .leftMouseUp ? 0 : 1)!
    }

    /// recording-r4 :330 (gap 22), in part, recording-r4 :355 (gap 11). A press asks only to stage the drag file;
    /// a 2 pt drag asks nothing; the drag that reaches 3 pt asks for the download once, and the press's later
    /// drags do not; a new press asks again after its own 3 pt drag. By hand: that the card's menu has no download
    /// item (gap 22's second half, D16).
    @Test func theDragViewAsksForTheDownloadOncePerPressPastTheThreshold() {
        let record = CaptureRecord(fileURL: nil, pixelWidth: 1600, pixelHeight: 1000, appName: nil,
                                   uploadState: .uploaded(url: URL(string: "https://snap.tky.io/s/REC.mp4")!,
                                                          key: "s/REC.mp4"),
                                   mediaKind: .video, durationSeconds: 10)
        let model = QuickAccessModel(record: record, thumbnail: nil)
        let asked = Asked()
        model.actions.prepareDrag = { _ in asked.prepares += 1 }
        model.actions.downloadForDrag = { _ in asked.downloads += 1 }
        let view = QuickAccessCardDragView()
        // The view holds its model weakly; the test keeps it.
        view.model = model

        view.mouseDown(with: event(.leftMouseDown, at: CGPoint(x: 10, y: 10)))
        #expect(asked.prepares == 1)
        #expect(asked.downloads == 0)
        view.mouseDragged(with: event(.leftMouseDragged, at: CGPoint(x: 12, y: 10)))
        #expect(asked.downloads == 0)
        view.mouseDragged(with: event(.leftMouseDragged, at: CGPoint(x: 13, y: 10)))
        #expect(asked.downloads == 1)
        view.mouseDragged(with: event(.leftMouseDragged, at: CGPoint(x: 30, y: 10)))
        view.mouseDragged(with: event(.leftMouseDragged, at: CGPoint(x: 40, y: 20)))
        #expect(asked.downloads == 1)
        view.mouseUp(with: event(.leftMouseUp, at: CGPoint(x: 40, y: 20)))

        view.mouseDown(with: event(.leftMouseDown, at: CGPoint(x: 10, y: 10)))
        #expect(asked.prepares == 2)
        view.mouseDragged(with: event(.leftMouseDragged, at: CGPoint(x: 10, y: 13)))
        #expect(asked.downloads == 2)
        withExtendedLifetime(model) {}
    }
}
