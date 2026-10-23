import CoreGraphics
import Foundation
import Testing
@testable import TidyShot

struct EditorPaletteTests {
    let large = CGRect(x: 0, y: 0, width: 1000, height: 1000)

    @Test func tenSwatchesUnique() {
        let swatches = EditorPalette.swatches
        #expect(swatches.count == 10)
        for (index, swatch) in swatches.enumerated() {
            #expect(!swatches[(index + 1)...].contains(swatch))
            #expect([swatch.red, swatch.green, swatch.blue].allSatisfy { (0...1).contains($0) })
            #expect(swatch.alpha == 1)
        }
        // Black first and white last, as in the popover.
        #expect(swatches.first == RGBA(red: 0, green: 0, blue: 0))
        #expect(swatches.last == RGBA(red: 1, green: 1, blue: 1))
        #expect(swatches.contains(EditorPalette.defaultStroke))
        #expect(swatches.contains(EditorPalette.defaultRedact))
    }

    @Test func standardDefaultsAreRedBlackFourEightTen() {
        let standard = EditorDefaults.standard
        #expect(standard == EditorDefaults(strokeColor: EditorPalette.defaultStroke,
                                           redactColor: EditorPalette.defaultRedact,
                                           lineWidthPoints: 4, blurRadiusPoints: 8, blockPoints: 10,
                                           spotlightEllipse: false, counterDiameterPoints: 32))
        #expect(EditorPalette.defaultRedact == RGBA(red: 0, green: 0, blue: 0))
        let red = EditorPalette.defaultStroke
        #expect(red.red == 1 && red.green < 0.3 && red.blue < 0.3)
        #expect(EditorPalette.lineWidthsPoints == [2, 3, 4, 6, 8, 12])
        #expect(EditorPalette.lineWidthsPoints.contains(standard.lineWidthPoints))
        #expect(RedactionDefaults.blurRangePoints == 4...24)
        #expect(RedactionDefaults.blurRangePoints.contains(standard.blurRadiusPoints))
        #expect(RedactionDefaults.blockRangePoints == 6...32)
        #expect(RedactionDefaults.blockRangePoints.contains(standard.blockPoints))
        // 4c: a rectangle spotlight and a Medium counter.
        #expect(EditorPalette.spotlightDims == [0.3, 0.5, 0.7])
        #expect(EditorPalette.spotlightDims.contains(AnnotationDocument.defaultSpotlightDim))
        #expect(EditorPalette.counterDiametersPoints == [24, 32, 44])
        #expect(EditorPalette.defaultCounterDiameterPoints == 32)
        #expect(standard.counterDiameterPoints == EditorPalette.defaultCounterDiameterPoints)
    }

    @Test func blurDefaultDoublesAtRetina() {
        #expect(RedactionDefaults.blurRadius(points: 8, scale: 1) == 8)
        #expect(RedactionDefaults.blurRadius(points: 8, scale: 2) == 16)
        #expect(RedactionDefaults.blurRadius(points: 24, scale: 2) == 48)
    }

    @Test func blurFloor() {
        #expect(RedactionDefaults.blurRadius(points: 2, scale: 2) == 8)
        #expect(RedactionDefaults.blurRadius(points: 0, scale: 1) == 4)
        #expect(RedactionDefaults.blurRadius(points: 4, scale: 2) == 8)
    }

    @Test func blockCappedAtRegionShorterSide() {
        #expect(RedactionDefaults.block(points: 10, scale: 2, region: CGRect(x: 10, y: 10, width: 300, height: 14)) == 14)
        // A fractional side rounds down, so the region still holds one whole block.
        #expect(RedactionDefaults.block(points: 10, scale: 2, region: CGRect(x: 0, y: 0, width: 14.6, height: 300)) == 14)
        // The cap wins over the floor in a thin region, but a block is never below one pixel.
        #expect(RedactionDefaults.block(points: 6, scale: 2, region: CGRect(x: 0, y: 0, width: 300, height: 5)) == 5)
        #expect(RedactionDefaults.block(points: 10, scale: 2, region: CGRect(x: 0, y: 0, width: 300, height: 0.5)) == 1)
        // A rect with a negative width is measured by its size.
        #expect(RedactionDefaults.block(points: 10, scale: 1, region: CGRect(x: 50, y: 50, width: -8, height: 40)) == 8)
    }

    @Test func blockFloor() {
        #expect(RedactionDefaults.block(points: 10, scale: 2, region: large) == 20)
        #expect(RedactionDefaults.block(points: 2, scale: 2, region: large) == 12)
        #expect(RedactionDefaults.block(points: 0, scale: 1, region: large) == 6)
        // Whole pixels, so the mosaic grid stays on pixel boundaries.
        #expect(RedactionDefaults.block(points: 7.4, scale: 2, region: large) == 15)
    }

    @Test func rgbaCodableRoundTrip() throws {
        let colour = RGBA(red: 0.25, green: 0.5, blue: 0.75, alpha: 0.5)
        let data = try JSONEncoder().encode(colour)
        #expect(try JSONDecoder().decode(RGBA.self, from: data) == colour)
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Double])
        #expect(object == ["red": 0.25, "green": 0.5, "blue": 0.75, "alpha": 0.5])
        // cgColor is made in sRGB from the same components.
        let cgColor = colour.cgColor
        #expect(cgColor.colorSpace?.name == CGColorSpace.sRGB)
        #expect(cgColor.components == [0.25, 0.5, 0.75, 0.5])
        #expect(RGBA(red: 1, green: 0, blue: 0).alpha == 1)
    }
}
