import CoreGraphics
import Foundation
import Testing
@testable import TidyShot

/// What the canvas shows of the spotlights (spec 2.12, Rendering): the overlay's source list, and
/// when a change may repaint only the transient's rects.
struct SpotlightDisplayTests {
    let red = RGBA(red: 1, green: 0, blue: 0, alpha: 1)

    func spotlight(_ x: CGFloat) -> Annotation {
        .spotlight(SpotlightShape(id: UUID(), rect: CGRect(x: x, y: 10, width: 20, height: 20), isEllipse: false))
    }

    func arrow() -> Annotation {
        .arrow(Segment(id: UUID(), from: CGPoint(x: 0, y: 0), to: CGPoint(x: 40, y: 40), color: red, lineWidth: 4))
    }

    /// A shown state with no spotlights and the Select tool; each test changes one field.
    func shown(document: AnnotationDocument = AnnotationDocument(annotations: []), transient: Annotation? = nil,
               hasSpotlights: Bool = false, showsSpotlightOutlines: Bool = false) -> CanvasView.Shown {
        CanvasView.Shown(document: document, transient: transient, selection: nil,
                         transform: CanvasTransform(zoom: 1, offset: .zero), editingID: nil, cropDraft: nil,
                         background: nil, hasSpotlights: hasSpotlights, showsSpotlightOutlines: showsSpotlightOutlines)
    }

    @Test func displayedSpotlightsPutTheTransientInPlace() {
        let first = spotlight(0)
        let line = arrow()
        let second = spotlight(50)
        let document = AnnotationDocument(annotations: [first, line, second])
        #expect(SpotlightGeometry.displayedSpotlights(in: document, transient: nil) == [first, second])

        // Moved or resized: in place of its document copy, so the creation order is kept.
        let moved = first.moved(by: CGVector(dx: 5, dy: 5))
        #expect(SpotlightGeometry.displayedSpotlights(in: document, transient: moved) == [moved, second])

        // New: last.
        let new = spotlight(100)
        #expect(SpotlightGeometry.displayedSpotlights(in: document, transient: new) == [first, second, new])
        #expect(SpotlightGeometry.displayedSpotlights(in: AnnotationDocument(annotations: []), transient: new) == [new])

        // A transient of another kind is ignored, a drawing or an effect.
        #expect(SpotlightGeometry.displayedSpotlights(in: document, transient: line.moved(by: CGVector(dx: 1, dy: 0)))
                == [first, second])
        let effect = Annotation.blur(Region(id: UUID(), rect: CGRect(x: 0, y: 0, width: 10, height: 10)), radius: 8)
        #expect(SpotlightGeometry.displayedSpotlights(in: document, transient: effect) == [first, second])
    }

    /// The first spotlight appearing or the last going changes the dim everywhere, and the tool's
    /// outlines come and go with the tool alone: both repaint the whole view.
    @Test func aFlipOfEitherSpotlightFieldRepaintsTheWholeView() {
        let before = shown()
        #expect(!shown(hasSpotlights: true).allowsPartialRepaint(since: before))
        #expect(!before.allowsPartialRepaint(since: shown(hasSpotlights: true)))
        #expect(!shown(showsSpotlightOutlines: true).allowsPartialRepaint(since: before))
        #expect(!before.allowsPartialRepaint(since: shown(showsSpotlightOutlines: true)))
    }

    /// While a spotlight stays displayed, a hole's move or resize changes the overlay only inside
    /// its old and new rects, so a transient-only change still repaints just those.
    @Test func aTransientOnlyChangeRepaintsPartOfTheView() {
        let document = AnnotationDocument(annotations: [spotlight(0)])
        let first = spotlight(40)
        let previous = shown(document: document, transient: first, hasSpotlights: true, showsSpotlightOutlines: true)
        let now = shown(document: document, transient: first.moved(by: CGVector(dx: 3, dy: 0)), hasSpotlights: true,
                        showsSpotlightOutlines: true)
        #expect(now.allowsPartialRepaint(since: previous))
        // As before 4c, with no spotlight at all.
        #expect(shown(transient: arrow()).allowsPartialRepaint(since: shown()))
    }

    /// Every change the guard sent to a full repaint before 4c still does.
    @Test func everyOtherChangeStillRepaintsTheWholeView() {
        let base = shown()
        var document = base
        document.document = AnnotationDocument(annotations: [arrow()])
        var selection = base
        selection.selection = UUID()
        var transform = base
        transform.transform = CanvasTransform(zoom: 2, offset: .zero)
        var editing = base
        editing.editingID = UUID()
        var crop = base
        crop.cropDraft = CGRect(x: 0, y: 0, width: 10, height: 10)
        var background = base
        background.background = ShownBackground(style: BackgroundStyle(), canvasRect: CGRect(x: -8, y: -8, width: 32, height: 32),
                                                contentRect: CGRect(x: 0, y: 0, width: 16, height: 16), radius: 0)
        for changed in [document, selection, transform, editing, crop, background] {
            #expect(!changed.allowsPartialRepaint(since: base))
            #expect(!base.allowsPartialRepaint(since: changed))
        }
        #expect(base.allowsPartialRepaint(since: base))
    }
}
