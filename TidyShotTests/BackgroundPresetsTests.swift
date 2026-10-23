import Testing
@testable import TidyShot

struct BackgroundPresetsTests {
    @Test func twelveWithUniqueNames() {
        let names = BackgroundPresets.gradients.map(\.name)
        #expect(names.count == 12)
        #expect(Set(names).count == 12)
    }

    @Test func tableValuesForFirstAndLast() {
        let sunset = BackgroundPresets.gradients[0]
        #expect(sunset.name == "Sunset")
        #expect(sunset.first == RGBA(hex: 0xFF7A59))
        #expect(sunset.second == RGBA(hex: 0x7B4DFF))
        let berry = BackgroundPresets.gradients[11]
        #expect(berry.name == "Berry")
        #expect(berry.first == RGBA(hex: 0xC471F5))
        #expect(berry.second == RGBA(hex: 0xFA71CD))
    }

    @Test func hexComponents() {
        let colour = RGBA(hex: 0xFF7A59)
        #expect(colour.red == 1)
        #expect(colour.green == 122.0 / 255)
        #expect(colour.blue == 89.0 / 255)
        #expect(colour.alpha == 1)
    }
}
