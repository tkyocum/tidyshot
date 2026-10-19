import CoreGraphics
import Testing
@testable import TidyShot

struct GeometryTests {
    let primaryHeight: CGFloat = 1080

    @Test func appKitRectToCGFlipsY() {
        let appKit = CGRect(x: 100, y: 100, width: 200, height: 50)
        let cg = Geometry.cgRect(fromAppKit: appKit, primaryHeight: primaryHeight)
        #expect(cg == CGRect(x: 100, y: 930, width: 200, height: 50))
    }

    @Test func cgRectToAppKitRoundTrips() {
        let appKit = CGRect(x: -300, y: 1200, width: 640, height: 480)
        let cg = Geometry.cgRect(fromAppKit: appKit, primaryHeight: primaryHeight)
        let back = Geometry.appKitRect(fromCG: cg, primaryHeight: primaryHeight)
        #expect(back == appKit)
    }

    @Test func appKitPointToCG() {
        let point = Geometry.cgPoint(fromAppKit: CGPoint(x: 10, y: 1070), primaryHeight: primaryHeight)
        #expect(point == CGPoint(x: 10, y: 10))
    }

    @Test func displayLocalOnSecondaryDisplayToTheLeft() {
        let displayFrame = CGRect(x: -1920, y: 0, width: 1920, height: 1080)
        let global = CGRect(x: -500, y: 200, width: 100, height: 100)
        let local = Geometry.displayLocal(global, in: displayFrame)
        #expect(local == CGRect(x: 1420, y: 200, width: 100, height: 100))
    }

    @Test func displayLocalOnDisplayAbovePrimary() {
        let displayFrame = CGRect(x: 0, y: -900, width: 1440, height: 900)
        let global = CGRect(x: 10, y: -890, width: 50, height: 50)
        let local = Geometry.displayLocal(global, in: displayFrame)
        #expect(local == CGRect(x: 10, y: 10, width: 50, height: 50))
    }

    @Test func pixelSizeRoundsToNearestPixel() {
        let size = Geometry.pixelSize(points: CGSize(width: 100.4, height: 50.6), scale: 2)
        #expect(size.width == 201)
        #expect(size.height == 101)
    }
}
