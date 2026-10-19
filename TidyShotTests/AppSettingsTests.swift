import Foundation
import Testing
@testable import TidyShot

struct AppSettingsTests {
    func freshDefaults() -> UserDefaults {
        let name = "AppSettingsTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test func phase2DefaultsAreUploadWithURLOnly() {
        let settings = AppSettings(defaults: freshDefaults())
        #expect(settings.afterCaptureAction == .upload)
        #expect(settings.alsoCopyImageWhenUploading == false)
        #expect(settings.showOverlay)
        #expect(settings.overlayCorner == .bottomRight)
        #expect(settings.overlayAutoCloseSeconds == 5)
        #expect(settings.historyRetentionDays == 30)
        #expect(settings.s3Config == nil)
    }

    @Test func s3ConfigRoundTripsThroughDefaults() {
        let defaults = freshDefaults()
        let config = S3DestinationConfig(endpoint: "https://s3.us-east-1.amazonaws.com", region: "us-east-1", bucket: "snap",
                                         keyPrefix: "p", usePathStyle: true, sendPublicReadACL: true,
                                         publicURLTemplate: "https://snap.tky.io/{key}", keyLength: 8)
        let first = AppSettings(defaults: defaults)
        first.s3Config = config
        first.afterCaptureAction = .save
        first.overlayCorner = .topLeft

        let second = AppSettings(defaults: defaults)
        #expect(second.s3Config == config)
        #expect(second.afterCaptureAction == .save)
        #expect(second.overlayCorner == .topLeft)

        second.s3Config = nil
        #expect(AppSettings(defaults: defaults).s3Config == nil)
    }
}
