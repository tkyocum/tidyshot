import Foundation
import Testing
@testable import TidyShot

struct SmokeTests {
    /// The test bundle is hosted inside the app, so Bundle.main is the app bundle.
    @Test func testsRunInsideTheAppBundle() {
        #expect(Bundle.main.bundleIdentifier == "io.tky.tidyshot")
    }
}
