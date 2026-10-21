import CoreGraphics
import Testing
@testable import TidyShot

/// The stack's geometry: the newest card at the corner, the others 10 pt apart away from it,
/// and how many fit (spec 2.9, Stacking). AppKit screen coordinates, origin bottom-left.
struct QuickAccessStackLayoutTests {
    let screen = CGRect(x: 0, y: 25, width: 1440, height: 875)
    let card = CGSize(width: 340, height: 104)

    /// One card is placed exactly as Phase 5 placed the one panel.
    @Test func oneCardSitsWhereOverlayGeometryPutsIt() {
        for corner in OverlayCorner.allCases {
            let frames = QuickAccessStackLayout.frames(count: 1, cardSize: card, corner: corner, visibleFrame: screen)
            #expect(frames == [OverlayGeometry.frame(size: card, corner: corner, in: screen)])
        }
    }

    @Test func topCornersStackDownwardTenPointsApart() {
        let right = QuickAccessStackLayout.frames(count: 3, cardSize: card, corner: .topRight, visibleFrame: screen)
        #expect(right == [
            CGRect(x: 1084, y: 780, width: 340, height: 104),
            CGRect(x: 1084, y: 666, width: 340, height: 104),
            CGRect(x: 1084, y: 552, width: 340, height: 104),
        ])
        let left = QuickAccessStackLayout.frames(count: 2, cardSize: card, corner: .topLeft, visibleFrame: screen)
        #expect(left.map(\.minX) == [16, 16])
        #expect(left.map(\.minY) == [780, 666])
    }

    @Test func bottomCornersStackUpward() {
        let right = QuickAccessStackLayout.frames(count: 3, cardSize: card, corner: .bottomRight, visibleFrame: screen)
        #expect(right.map(\.minY) == [41, 155, 269])
        #expect(right.allSatisfy { $0.minX == 1084 && $0.size == card })
        let left = QuickAccessStackLayout.frames(count: 2, cardSize: card, corner: .bottomLeft, visibleFrame: screen)
        #expect(left == [CGRect(x: 16, y: 41, width: 340, height: 104), CGRect(x: 16, y: 155, width: 340, height: 104)])
    }

    /// A display left of and below the main one has negative coordinates.
    @Test func secondDisplayWithANegativeOriginIsHonoured() {
        let second = CGRect(x: -1920, y: -200, width: 1920, height: 1055)
        let frames = QuickAccessStackLayout.frames(count: 2, cardSize: card, corner: .topLeft, visibleFrame: second,
                                                   margin: 20, spacing: 10)
        #expect(frames == [CGRect(x: -1900, y: 731, width: 340, height: 104),
                           CGRect(x: -1900, y: 617, width: 340, height: 104)])
    }

    @Test func noCardsNoFrames() {
        #expect(QuickAccessStackLayout.frames(count: 0, cardSize: card, corner: .topRight, visibleFrame: screen).isEmpty)
    }

    @Test func capacityIsTheLimitOnATallScreen() {
        #expect(QuickAccessStackLayout.capacity(cardHeight: 104, visibleHeight: 875, limit: 5) == 5)
        // 875 pt fits seven: 16 + 7 x 104 + 6 x 10 + 16 = 820; eight need 934.
        #expect(QuickAccessStackLayout.capacity(cardHeight: 104, visibleHeight: 875, limit: 8) == 7)
    }

    @Test func capacityOnAShortScreen() {
        // 300 pt fits two (250 pt); three need 364.
        #expect(QuickAccessStackLayout.capacity(cardHeight: 104, visibleHeight: 300, limit: 5) == 2)
        #expect(QuickAccessStackLayout.capacity(cardHeight: 104, visibleHeight: 364, limit: 5) == 3)
    }

    /// The newest card always shows, as the one panel did on any screen.
    @Test func capacityIsAtLeastOne() {
        #expect(QuickAccessStackLayout.capacity(cardHeight: 104, visibleHeight: 80, limit: 5) == 1)
        #expect(QuickAccessStackLayout.capacity(cardHeight: 104, visibleHeight: 875, limit: 0) == 1)
    }
}
