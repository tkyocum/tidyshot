import Foundation
import Testing
@testable import TidyShot

struct RecentCaptureFormattingTests {
    /// 2026-10-19T12:00:00Z
    let now = Date(timeIntervalSince1970: 1_792_411_200)
    let english = Locale(identifier: "en_US")
    let location = ObjectLocation(endpoint: "https://s3.us-west-2.amazonaws.com", region: "us-west-2",
                                  bucket: "snap", usePathStyle: false)

    func record(_ state: CaptureRecord.UploadState, file: URL? = URL(fileURLWithPath: "/Users/tim/Desktop/Shot.png"),
                secondsAgo: TimeInterval = 120, location: ObjectLocation? = nil, appName: String? = nil) -> CaptureRecord {
        CaptureRecord(timestamp: now.addingTimeInterval(-secondsAgo), fileURL: file, pixelWidth: 10, pixelHeight: 10,
                      appName: appName, uploadState: state, objectLocation: location)
    }

    @Test func nameIsTheObjectOrTheFileName() {
        let url = URL(string: "https://snap.tky.io/shots/2026/10/aB3dE9.png")!
        #expect(RecentCaptureFormatting.name(for: record(.uploaded(url: url, key: "shots/2026/10/aB3dE9.png"))) == "aB3dE9.png")
        #expect(RecentCaptureFormatting.name(for: record(.none)) == "Shot.png")
        #expect(RecentCaptureFormatting.name(for: record(.failed(message: "x"), file: nil, appName: "Safari")) == "Safari")
        #expect(RecentCaptureFormatting.name(for: record(.failed(message: "x"), file: nil)) == "Capture")
    }

    @Test func detailIsTheRelativeTimeAndAnUnsettledState() {
        #expect(RecentCaptureFormatting.detail(for: record(.none), now: now, locale: english) == "2 minutes ago")
        #expect(RecentCaptureFormatting.detail(for: record(.uploading(fraction: 0.5)), now: now, locale: english)
                == "2 minutes ago · Uploading")
        #expect(RecentCaptureFormatting.detail(for: record(.failed(message: "offline"), secondsAgo: 86_400), now: now, locale: english)
                == "yesterday · Upload failed")
        #expect(RecentCaptureFormatting.detail(for: record(.none, secondsAgo: 0), now: now, locale: english) == "now")
    }

    @Test func buttonsFollowWhatTheCaptureHas() {
        let url = URL(string: "https://snap.tky.io/aB3dE9.png")!
        let uploadOnly = record(.uploaded(url: url, key: "aB3dE9.png"), file: nil, location: location)
        #expect(RecentCaptureFormatting.canCopyLink(uploadOnly))
        #expect(RecentCaptureFormatting.canCopyImage(uploadOnly))

        let saved = record(.none)
        #expect(!RecentCaptureFormatting.canCopyLink(saved))
        #expect(RecentCaptureFormatting.canCopyImage(saved))

        // Uploaded before Phase 3 (no location): such a record always keeps its file URL, also after
        // the file is deleted in Finder, so the button stays enabled; Copy Image then reports
        // CopyImageError.unreadableFile ("The local file could not be read.").
        let phase2 = record(.uploaded(url: url, key: "aB3dE9.png"))
        #expect(RecentCaptureFormatting.canCopyLink(phase2))
        #expect(RecentCaptureFormatting.canCopyImage(phase2))

        // Uploaded with neither a file URL nor a location: nothing to download from. No real history
        // holds such a record (see CopyImageError.unknownLocation); the button would be disabled.
        let noFileNoLocation = record(.uploaded(url: url, key: "aB3dE9.png"), file: nil)
        #expect(RecentCaptureFormatting.canCopyLink(noFileNoLocation))
        #expect(!RecentCaptureFormatting.canCopyImage(noFileNoLocation))
    }
}
