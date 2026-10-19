import CoreGraphics
import Testing
@testable import TidyShot

struct OverlayGeometryTests {
    let screen = CGRect(x: 0, y: 25, width: 1440, height: 875)
    let size = CGSize(width: 320, height: 96)

    @Test func bottomRightDefault() {
        let frame = OverlayGeometry.frame(size: size, corner: .bottomRight, in: screen)
        #expect(frame == CGRect(x: 1440 - 16 - 320, y: 25 + 16, width: 320, height: 96))
    }

    @Test func topLeft() {
        let frame = OverlayGeometry.frame(size: size, corner: .topLeft, in: screen)
        #expect(frame == CGRect(x: 16, y: 900 - 16 - 96, width: 320, height: 96))
    }

    @Test func secondDisplayOffsetIsHonoured() {
        let second = CGRect(x: 1440, y: 200, width: 1920, height: 1055)
        let frame = OverlayGeometry.frame(size: size, corner: .bottomLeft, in: second, margin: 20)
        #expect(frame.origin == CGPoint(x: 1460, y: 220))
    }
}
