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
                                         usePathStyle: true, sendPublicReadACL: true,
                                         publicURLTemplate: "https://snap.tky.io/{key}", keyTemplate: "p/{random:8}")
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

    /// `{app}` was removed in Phase 3.1. Templates saved before that lose it on load, and the
    /// rewritten values are stored, so the next launch reads them as they are.
    @Test func storedTemplatesLoseTheRemovedAppToken() throws {
        let defaults = freshDefaults()
        defaults.set("{app} {datetime}", forKey: "fileNameTemplate")
        let old = S3DestinationConfig(endpoint: "https://s3.us-east-1.amazonaws.com", region: "us-east-1", bucket: "snap",
                                      publicURLTemplate: "https://snap.tky.io/{key}", keyTemplate: "shots/{app}/{random:8}")
        defaults.set(try JSONEncoder().encode(old), forKey: "s3DestinationConfig")

        let settings = AppSettings(defaults: defaults)
        #expect(settings.fileNameTemplate == "{datetime}")
        #expect(settings.s3Config?.keyTemplate == "shots/{random:8}")
        #expect(defaults.string(forKey: "fileNameTemplate") == "{datetime}")
        let stored = try #require(defaults.data(forKey: "s3DestinationConfig"))
        #expect(!String(decoding: stored, as: UTF8.self).contains("{app}"))
    }
}
