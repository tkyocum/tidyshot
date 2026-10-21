import CoreGraphics
import Foundation
@testable import TidyShot

/// A synthetic page behind a fake stream and a fake scroll wheel, for the auto-scroll tests.
/// Each posted event scrolls the page and the source sends the frame at the new offset, as an
/// app that redraws at once would.
final class FakeScrollWorld: ScrollEventPoster {
    var page: SyntheticPage
    let source = FakeFrameSource()
    let clock: FakeScrollClock
    /// Pixels per point of the fake display.
    let scale: CGFloat
    /// Page rows one posted pixel moves; 5 makes every step jump past the band.
    var gain: CGFloat = 1
    /// The app inverts synthetic deltas, as natural scrolling might.
    var inverted = false
    /// Lazy loading: the page cannot scroll past this offset until a post finds it held there
    /// for `loadDelay`.
    var loadedLimit: Int?
    var loadDelay: Duration = .milliseconds(300)
    /// When set, the frame a post shows reaches the session this long after the post, as from a
    /// slow stream or a busy consumer; until then the session still has the frame from before.
    var frameDelay: Duration?
    /// The pointer in CoreGraphics global points.
    var pointer: CGPoint
    var permitted = true
    /// How often the driver asked for the grant.
    private(set) var permissionChecks = 0
    /// Runs after each post, with the posts so far: a test moves the pointer or takes the grant
    /// mid-burst here.
    var afterPost: ((FakeScrollWorld) -> Void)?
    private(set) var offset: Int
    private(set) var posted: [CGFloat] = []
    /// Posts that found the page held at `loadedLimit`.
    private(set) var blockedPosts = 0
    private var blockedSince: ContinuousClock.Instant?

    init(page: SyntheticPage, clock: FakeScrollClock, scale: CGFloat = 2, offset: Int = 0, pointer: CGPoint) {
        self.page = page
        self.clock = clock
        self.scale = scale
        self.offset = offset
        self.pointer = pointer
    }

    var environment: AutoScrollEnvironment {
        AutoScrollEnvironment(poster: self,
                              pointerLocation: { [unowned self] in self.pointer },
                              isPermitted: { [unowned self] in
                                  self.permissionChecks += 1
                                  return self.permitted
                              })
    }

    func post(points: CGFloat) {
        posted.append(points)
        if let loadedLimit, offset >= loadedLimit {
            blockedPosts += 1
            if let blockedSince {
                if clock.now - blockedSince >= loadDelay { self.loadedLimit = nil }
            } else {
                blockedSince = clock.now
            }
        }
        let rows = Int((points * scale * gain).rounded()) * (inverted ? -1 : 1)
        let limit = min(page.maxOffset, loadedLimit ?? page.maxOffset)
        offset = max(0, min(limit, offset + rows))
        if let frameDelay {
            let frame = page.frame(at: offset, animated: false)
            Task { [source, clock] in
                try? await clock.sleep(for: frameDelay)
                source.send(.frame(frame))
            }
        } else {
            showFrame()
        }
        afterPost?(self)
    }

    /// Sends the frame at the current offset.
    func showFrame() {
        source.send(.frame(page.frame(at: offset, animated: false)))
    }

    /// The user scrolls to `newOffset` (manual mode after a hand-over).
    func scroll(to newOffset: Int) {
        offset = newOffset
        showFrame()
    }
}
