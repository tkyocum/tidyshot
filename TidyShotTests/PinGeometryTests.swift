import CoreGraphics
import Foundation
import Testing
@testable import TidyShot

/// Pin to screen's pure parts (spec 2.9): where a pin opens, how it moves and zooms, its opacity
/// steps and which key does what. AppKit global points, origin bottom-left.
struct PinGeometryTests {
    let visible = CGRect(x: 0, y: 0, width: 1440, height: 900)

    func approx(_ a: CGRect, _ b: CGRect, tolerance: CGFloat = 1e-9) -> Bool {
        abs(a.minX - b.minX) < tolerance && abs(a.minY - b.minY) < tolerance
            && abs(a.width - b.width) < tolerance && abs(a.height - b.height) < tolerance
    }

    func approx(_ a: CGSize, _ b: CGSize, tolerance: CGFloat = 1e-9) -> Bool {
        abs(a.width - b.width) < tolerance && abs(a.height - b.height) < tolerance
    }

    // MARK: Placement

    @Test func anImageThatFitsKeepsItsPointSizeAndIsCentred() {
        let frame = PinGeometry.initialFrame(imagePoints: CGSize(width: 400, height: 300), preferred: nil, visibleFrame: visible)
        #expect(frame == CGRect(x: 520, y: 300, width: 400, height: 300))
        // A display right of and below the main one has an offset visible frame.
        let second = CGRect(x: 1440, y: -200, width: 1920, height: 1080)
        let onSecond = PinGeometry.initialFrame(imagePoints: CGSize(width: 400, height: 300), preferred: nil, visibleFrame: second)
        #expect(onSecond == CGRect(x: 2200, y: 190, width: 400, height: 300))
        // The origin is a whole point: a half point rounds up.
        let odd = PinGeometry.initialFrame(imagePoints: CGSize(width: 401, height: 301), preferred: nil, visibleFrame: visible)
        #expect(odd == CGRect(x: 520, y: 300, width: 401, height: 301))
    }

    @Test func aLargeImageIsScaledToEightyPercentOfTheVisibleFrame() {
        #expect(PinGeometry.fitFraction == 0.8)
        let full = PinGeometry.initialFrame(imagePoints: CGSize(width: 1440, height: 900), preferred: nil, visibleFrame: visible)
        #expect(approx(full, CGRect(x: 144, y: 90, width: 1152, height: 720)))
        // Wide: the width limits it.
        let wide = PinGeometry.initialFrame(imagePoints: CGSize(width: 2880, height: 900), preferred: nil, visibleFrame: visible)
        #expect(approx(wide, CGRect(x: 144, y: 270, width: 1152, height: 360)))
        // Tall: the height limits it.
        let tall = PinGeometry.initialFrame(imagePoints: CGSize(width: 720, height: 1800), preferred: nil, visibleFrame: visible)
        #expect(approx(tall, CGRect(x: 576, y: 90, width: 288, height: 720)))
        #expect(abs(tall.width / tall.height - 720.0 / 1800.0) < 1e-9)
    }

    @Test func thePreferredSpotIsKept() {
        let spot = CGRect(x: 100, y: 200, width: 400, height: 300)
        let frame = PinGeometry.initialFrame(imagePoints: spot.size, preferred: spot, visibleFrame: visible)
        #expect(frame == spot)
    }

    @Test func aPreferredSpotPartlyOffScreenIsMovedOnScreen() {
        let size = CGSize(width: 400, height: 300)
        let bottomLeft = PinGeometry.initialFrame(imagePoints: size, preferred: CGRect(x: -50, y: -20, width: 400, height: 300),
                                                  visibleFrame: visible)
        #expect(bottomLeft == CGRect(x: 0, y: 0, width: 400, height: 300))
        let topRight = PinGeometry.initialFrame(imagePoints: size, preferred: CGRect(x: 1300, y: 700, width: 400, height: 300),
                                                visibleFrame: visible)
        #expect(topRight == CGRect(x: 1040, y: 600, width: 400, height: 300))
        // A spot on no screen at all (its display was unplugged) still ends up on this one.
        let gone = PinGeometry.initialFrame(imagePoints: size, preferred: CGRect(x: 5000, y: 5000, width: 400, height: 300),
                                            visibleFrame: visible)
        #expect(gone == CGRect(x: 1040, y: 600, width: 400, height: 300))
    }

    /// A scrolling capture is far taller than the area it was taken from: it is fitted, centred on
    /// the area's centre, and moved down to the screen's edge.
    @Test func aFittedImageIsCentredOnThePreferredCentre() {
        let frame = PinGeometry.initialFrame(imagePoints: CGSize(width: 800, height: 5760),
                                             preferred: CGRect(x: 100, y: 100, width: 800, height: 500), visibleFrame: visible)
        #expect(frame == CGRect(x: 450, y: 0, width: 100, height: 720))
    }

    // MARK: Moving, zooming, actual size

    @Test func nudgesMoveOneOrTenPoints() {
        let frame = CGRect(x: 100, y: 100, width: 50, height: 50)
        #expect(PinGeometry.nudged(frame, dx: 1, dy: 0, shift: false) == CGRect(x: 101, y: 100, width: 50, height: 50))
        #expect(PinGeometry.nudged(frame, dx: -1, dy: 0, shift: true) == CGRect(x: 90, y: 100, width: 50, height: 50))
        // Up is +1: AppKit's y grows upward.
        #expect(PinGeometry.nudged(frame, dx: 0, dy: 1, shift: false) == CGRect(x: 100, y: 101, width: 50, height: 50))
        #expect(PinGeometry.nudged(frame, dx: 0, dy: -1, shift: true) == CGRect(x: 100, y: 90, width: 50, height: 50))
    }

    @Test func zoomKeepsTheCentreAndInverts() {
        #expect(PinGeometry.zoomStep == 1.1)
        let frame = CGRect(x: 100, y: 100, width: 400, height: 300)
        let larger = PinGeometry.zoomed(frame, factor: PinGeometry.zoomStep, visibleFrame: visible)
        #expect(approx(larger, CGRect(x: 80, y: 85, width: 440, height: 330)))
        #expect(approx(PinGeometry.zoomed(larger, factor: 1 / PinGeometry.zoomStep, visibleFrame: visible), frame))
    }

    /// The shorter side never goes below 40 pt, or below what it is when it is under 40 already
    /// (a fitted strip): the pin can then only grow.
    @Test func zoomStopsAtTheMinimumSide() {
        #expect(PinGeometry.minimumSide == 40)
        let small = PinGeometry.zoomed(CGRect(x: 0, y: 0, width: 160, height: 120), factor: 0.25, visibleFrame: visible)
        #expect(approx(small, CGRect(x: 54, y: 40, width: 53, height: 40)))
        let strip = CGRect(x: 100, y: 100, width: 30, height: 225)
        #expect(approx(PinGeometry.zoomed(strip, factor: 0.5, visibleFrame: visible), strip))
        #expect(approx(PinGeometry.zoomed(strip, factor: 2, visibleFrame: visible), CGRect(x: 85, y: -13, width: 60, height: 450)))
    }

    @Test func minimumSizeKeepsTheAspect() {
        #expect(approx(PinGeometry.minimumSize(aspect: CGSize(width: 400, height: 300), initial: CGSize(width: 500, height: 375)),
                       CGSize(width: 160.0 / 3, height: 40)))
        #expect(approx(PinGeometry.minimumSize(aspect: CGSize(width: 300, height: 400), initial: CGSize(width: 375, height: 500)),
                       CGSize(width: 40, height: 160.0 / 3)))
        #expect(PinGeometry.minimumSize(aspect: CGSize(width: 100, height: 100), initial: CGSize(width: 90, height: 90))
                == CGSize(width: 40, height: 40))
        // A strip fitted to the screen: 40 pt wide at most.
        #expect(PinGeometry.minimumSize(aspect: CGSize(width: 800, height: 5760), initial: CGSize(width: 100, height: 720))
                == CGSize(width: 40, height: 288))
        // One that is narrower than 40 pt already keeps its width as the floor.
        #expect(PinGeometry.minimumSize(aspect: CGSize(width: 800, height: 6000), initial: CGSize(width: 30, height: 225))
                == CGSize(width: 30, height: 225))
    }

    @Test func actualSizeKeepsTheCentre() {
        let frame = CGRect(x: 100, y: 100, width: 200, height: 150)
        #expect(PinGeometry.actualSize(frame, imagePoints: CGSize(width: 400, height: 300), visibleFrame: visible)
                == CGRect(x: 0, y: 25, width: 400, height: 300))
    }

    /// Zoomed and actual-size frames land on whole points, so the image stays sharp.
    @Test func zoomedAndActualSizeFramesAreWholePoints() {
        let zoomed = PinGeometry.zoomed(CGRect(x: 100.5, y: 100.5, width: 333, height: 211), factor: 1.1, visibleFrame: visible)
        #expect(zoomed == CGRect(x: 84, y: 90, width: 366, height: 232))
        let actual = PinGeometry.actualSize(CGRect(x: 10, y: 10, width: 101, height: 51),
                                            imagePoints: CGSize(width: 300.4, height: 200), visibleFrame: visible)
        #expect(actual == CGRect(x: -90, y: -65, width: 300, height: 200))
    }

    /// Past the visible frame a pin is scaled down to it, keeping the aspect ratio, on either axis.
    @Test func zoomedAndActualSizeAreCappedToTheVisibleFrame() {
        let wide = PinGeometry.zoomed(CGRect(x: 0, y: 0, width: 1400, height: 700), factor: 1.1, visibleFrame: visible)
        #expect(wide.size == CGSize(width: 1440, height: 720))
        let tall = PinGeometry.zoomed(CGRect(x: 0, y: 0, width: 600, height: 880), factor: 1.1, visibleFrame: visible)
        #expect(tall.size == CGSize(width: 614, height: 900))
        let actual = PinGeometry.actualSize(CGRect(x: 100, y: 100, width: 200, height: 150),
                                            imagePoints: CGSize(width: 2880, height: 1800), visibleFrame: visible)
        #expect(actual == CGRect(x: -520, y: -275, width: 1440, height: 900))
    }

    @Test func largeImagesAreShownFromADownsample() {
        #expect(PinGeometry.maxPixelSide == 8_192)
        #expect(PinGeometry.downsampleMaxSide(pixelWidth: 8_192, pixelHeight: 4_000, screenPixelSide: 5_120) == nil)
        #expect(PinGeometry.downsampleMaxSide(pixelWidth: 3_094, pixelHeight: 65_536, screenPixelSide: 5_120) == 5_120)
        #expect(PinGeometry.downsampleMaxSide(pixelWidth: 8_193, pixelHeight: 100, screenPixelSide: 5_120) == 5_120)
        // The result never exceeds the limit, whatever the screen.
        #expect(PinGeometry.downsampleMaxSide(pixelWidth: 9_000, pixelHeight: 100, screenPixelSide: 10_000) == 8_192)
    }

    // MARK: Opacity

    @Test func opacityStepsClampAndStayOnTheGrid() {
        #expect(PinOpacity.changed(1.0, steps: -1) == 0.95)
        #expect(PinOpacity.changed(1.0, steps: -18) == 0.1)
        #expect(PinOpacity.changed(1.0, steps: -30) == 0.1)
        #expect(PinOpacity.changed(0.1, steps: 1) == 0.15)
        #expect(PinOpacity.changed(0.9, steps: 5) == 1.0)
        // Off the 5 % grid snaps to it.
        #expect(PinOpacity.changed(0.77, steps: 0) == 0.75)
        // Single steps do not drift.
        var opacity = 1.0
        for _ in 0..<18 { opacity = PinOpacity.changed(opacity, steps: -1) }
        #expect(opacity == 0.1)
        for _ in 0..<18 { opacity = PinOpacity.changed(opacity, steps: 1) }
        #expect(opacity == 1.0)
    }

    @Test func opacityPresetsAndTitles() {
        #expect(PinOpacity.presets == [1.0, 0.9, 0.75, 0.5, 0.25])
        #expect(PinOpacity.presets.map(PinOpacity.title(for:)) == ["100%", "90%", "75%", "50%", "25%"])
        #expect(PinOpacity.matches(0.9, 0.9000001))
        #expect(!PinOpacity.matches(0.85, 0.9))
    }

    // MARK: Keys (key codes: 53 Escape, 123 left, 124 right, 125 down, 126 up)

    func key(_ code: UInt16, _ characters: String? = nil, command: Bool = false, shift: Bool = false,
             option: Bool = false, control: Bool = false) -> PinCommand? {
        PinKeys.command(keyCode: code, characters: characters, command: command, shift: shift, option: option, control: control)
    }

    @Test func arrowKeysNudgeAndEscapeCloses() {
        #expect(key(123) == .nudge(dx: -1, dy: 0, shift: false))
        #expect(key(124) == .nudge(dx: 1, dy: 0, shift: false))
        #expect(key(125) == .nudge(dx: 0, dy: -1, shift: false))
        #expect(key(126) == .nudge(dx: 0, dy: 1, shift: false))
        #expect(key(126, shift: true) == .nudge(dx: 0, dy: 1, shift: true))
        #expect(key(53) == .close)
    }

    @Test func commandKeysZoomCopyAndClose() {
        #expect(key(24, "=", command: true) == .zoomIn)
        #expect(key(24, "+", command: true, shift: true) == .zoomIn)
        #expect(key(69, "+", command: true) == .zoomIn)
        #expect(key(27, "-", command: true) == .zoomOut)
        #expect(key(78, "-", command: true) == .zoomOut)
        #expect(key(29, "0", command: true) == .actualSize)
        #expect(key(8, "c", command: true) == .copyImage)
        #expect(key(13, "w", command: true) == .close)
        // Caps Lock arrives as a capital.
        #expect(key(13, "W", command: true) == .close)
    }

    @Test func otherModifiersAndKeysAreIgnored() {
        #expect(key(8, "c") == nil)
        #expect(key(13, "w") == nil)
        #expect(key(8, "c", command: true, shift: true) == nil)
        #expect(key(8, "c", command: true, option: true) == nil)
        #expect(key(8, "c", command: true, control: true) == nil)
        #expect(key(123, command: true) == nil)
        #expect(key(123, option: true) == nil)
        #expect(key(53, option: true) == nil)
        #expect(key(12, "q", command: true) == nil)
        #expect(key(0) == nil)
    }
}
