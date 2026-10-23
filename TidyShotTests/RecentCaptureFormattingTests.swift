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
                secondsAgo: TimeInterval = 120, location: ObjectLocation? = nil, appName: String? = nil,
                byteCount: Int? = nil) -> CaptureRecord {
        CaptureRecord(timestamp: now.addingTimeInterval(-secondsAgo), fileURL: file, pixelWidth: 10, pixelHeight: 10,
                      appName: appName, uploadState: state, objectLocation: location, byteCount: byteCount)
    }

    /// `ByteCountFormatter` has no locale of its own and writes in the current one, so the tests that
    /// compare its text with literals run only where that is US English (Tim's Mac). The others
    /// compare the row's text with `sizeText` itself.
    nonisolated static let currentIsUSEnglish = Locale.current.language.languageCode == .english
        && Locale.current.region == .unitedStates

    /// The size text for 5,000 bytes in the current locale (`5 KB` in US English).
    var fiveKB: String { RecentCaptureFormatting.sizeText(5_000) ?? "missing" }

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

    /// A replace keeps its link in `priorUpload` while it runs and after a quit or crash
    /// interrupted it, so Copy URL stays enabled.
    @Test func canCopyLinkForInterruptedReplace() {
        let url = URL(string: "https://snap.tky.io/aB3dE9.png")!
        var replacing = record(.uploading(fraction: 0.4), location: location)
        replacing.priorUpload = PriorUpload(url: url, key: "aB3dE9.png", location: location, isReplace: true)
        #expect(RecentCaptureFormatting.canCopyLink(replacing))

        replacing.uploadState = .failed(message: "Upload was interrupted.")
        #expect(RecentCaptureFormatting.canCopyLink(replacing))

        replacing.priorUpload = nil
        #expect(!RecentCaptureFormatting.canCopyLink(replacing))
    }

    @Test func annotateIsEnabledWhenTheEditorCanLoadTheImage() {
        let desktop = URL(fileURLWithPath: "/Users/tim/Desktop", isDirectory: true)
        let url = URL(string: "https://snap.tky.io/aB3dE9.png")!
        #expect(RecentCaptureFormatting.canAnnotate(record(.none), retainedID: nil, saveFolder: desktop))
        #expect(RecentCaptureFormatting.canAnnotate(record(.uploading(fraction: 0.5)), retainedID: nil, saveFolder: desktop))
        // Upload-only and uploaded: downloaded with a signed GET.
        let uploadOnly = record(.uploaded(url: url, key: "aB3dE9.png"), file: nil, location: location)
        #expect(RecentCaptureFormatting.canAnnotate(uploadOnly, retainedID: nil, saveFolder: nil))
    }

    @Test func annotateIsDisabledWhenThereIsNothingToLoad() {
        let url = URL(string: "https://snap.tky.io/aB3dE9.png")!
        // Uploaded before Phase 3, with no file and no location.
        let legacy = record(.uploaded(url: url, key: "aB3dE9.png"), file: nil)
        #expect(!RecentCaptureFormatting.canAnnotate(legacy, retainedID: nil, saveFolder: nil))
        // Saved to a folder that is no longer the save folder, never uploaded...
        let pictures = URL(fileURLWithPath: "/Users/tim/Pictures", isDirectory: true)
        let moved = record(.none)
        #expect(!RecentCaptureFormatting.canAnnotate(moved, retainedID: nil, saveFolder: pictures))
        // ...unless it is the capture just taken, whose image is still in memory.
        #expect(RecentCaptureFormatting.canAnnotate(moved, retainedID: moved.id, saveFolder: pictures))
    }

    func video(_ state: CaptureRecord.UploadState, file: URL? = URL(fileURLWithPath: "/Users/tim/Desktop/Recording.mp4"),
               temporary: Bool = false, location: ObjectLocation? = nil) -> CaptureRecord {
        CaptureRecord(timestamp: now.addingTimeInterval(-120), fileURL: file, fileIsTemporary: temporary,
                      pixelWidth: 1600, pixelHeight: 1000, appName: nil, uploadState: state, objectLocation: location,
                      mediaKind: .video, durationSeconds: 42)
    }

    /// While a recording waits for Clop, its row says so in place of `Uploading`.
    @Test func detailSaysOptimizingWhileClopRuns() {
        #expect(RecentCaptureFormatting.detail(for: video(.uploading(fraction: 0)), now: now, locale: english,
                                               isOptimizing: true) == "2 minutes ago · Optimizing…")
        #expect(RecentCaptureFormatting.detail(for: video(.uploading(fraction: 0)), now: now, locale: english,
                                               isOptimizing: false) == "2 minutes ago · Uploading")
        #expect(RecentCaptureFormatting.detail(for: video(.uploading(fraction: 0.3)), now: now, locale: english)
                == "2 minutes ago · Uploading")
    }

    /// No Annotate, Pin or Copy Image for a video, wherever its file is and whatever was retained.
    @Test func aVideoHasNoImageActions() {
        let desktop = URL(fileURLWithPath: "/Users/tim/Desktop", isDirectory: true)
        let url = URL(string: "https://snap.tky.io/aB3dE9.mp4")!
        let saved = video(.none)
        let uploadedOnly = video(.uploaded(url: url, key: "aB3dE9.mp4"), file: nil, location: location)
        for record in [saved, uploadedOnly] {
            #expect(!RecentCaptureFormatting.showsImageActions(record))
            #expect(!RecentCaptureFormatting.canCopyImage(record))
            #expect(!RecentCaptureFormatting.canAnnotate(record, retainedID: record.id, saveFolder: desktop))
        }
        #expect(RecentCaptureFormatting.canCopyLink(uploadedOnly))
        #expect(RecentCaptureFormatting.showsImageActions(record(.none)))
    }

    /// Copy File needs a video with a local file, in the save folder or `pending/`.
    @Test func copyFileNeedsAVideoWithALocalFile() {
        let url = URL(string: "https://snap.tky.io/aB3dE9.mp4")!
        let pending = URL(fileURLWithPath: "/tmp/pending/\(UUID().uuidString).mp4")
        #expect(RecentCaptureFormatting.canCopyFile(video(.none)))
        #expect(RecentCaptureFormatting.canCopyFile(video(.uploading(fraction: 0.5), file: pending, temporary: true)))
        #expect(!RecentCaptureFormatting.canCopyFile(video(.uploaded(url: url, key: "aB3dE9.mp4"), file: nil,
                                                           location: location)))
        #expect(!RecentCaptureFormatting.canCopyFile(record(.none)))
    }

    // MARK: GIF, Trim and the sound mark (recording R2)

    func gif(_ state: CaptureRecord.UploadState, file: URL? = URL(fileURLWithPath: "/Users/tim/Desktop/Recording.gif"),
             location: ObjectLocation? = nil) -> CaptureRecord {
        CaptureRecord(timestamp: now.addingTimeInterval(-120), fileURL: file, pixelWidth: 1280, pixelHeight: 800,
                      appName: nil, uploadState: state, objectLocation: location, mediaKind: .gif, durationSeconds: 12)
    }

    /// A GIF hides the image actions like an MP4, has Copy File with a local file, and shows the
    /// `GIF` badge where an MP4 shows `play.fill`. An image has no badge.
    @Test func aGIFHidesTheImageActionsCopiesItsFileAndHasTheGIFBadge() {
        let desktop = URL(fileURLWithPath: "/Users/tim/Desktop", isDirectory: true)
        let url = URL(string: "https://snap.tky.io/aB3dE9.gif")!
        let saved = gif(.none)
        #expect(!RecentCaptureFormatting.showsImageActions(saved))
        #expect(!RecentCaptureFormatting.canCopyImage(saved))
        #expect(!RecentCaptureFormatting.canAnnotate(saved, retainedID: saved.id, saveFolder: desktop))
        #expect(RecentCaptureFormatting.canCopyFile(saved))
        #expect(!RecentCaptureFormatting.canCopyFile(gif(.uploaded(url: url, key: "aB3dE9.gif"), file: nil, location: location)))

        #expect(RecentCaptureFormatting.badge(for: saved) == .gif)
        #expect(RecentCaptureFormatting.badge(for: video(.none)) == .play)
        #expect(RecentCaptureFormatting.badge(for: record(.none)) == nil)
    }

    /// An uploaded MP4 whose trim the link does not show yet says `Link not updated`, after the size,
    /// and keeps it when the size gives way. An upload running over it says `Uploading`, and an
    /// image or a GIF never says it.
    @Test func aStaleVideoSaysLinkNotUpdated() {
        let url = URL(string: "https://snap.tky.io/aB3dE9.mp4")!
        var stale = video(.uploaded(url: url, key: "aB3dE9.mp4"))
        stale.uploadIsStale = true
        #expect(RecentCaptureFormatting.detail(for: stale, now: now, locale: english) == "2 minutes ago · Link not updated")
        stale.byteCount = 5_000
        #expect(RecentCaptureFormatting.detail(for: stale, now: now, locale: english)
                == "2 minutes ago · \(fiveKB) · Link not updated")
        #expect(RecentCaptureFormatting.detailWithoutSize(for: stale, now: now, locale: english)
                == "2 minutes ago · Link not updated")

        var uploading = stale
        uploading.uploadState = .uploading(fraction: 0.5)
        #expect(RecentCaptureFormatting.detailWithoutSize(for: uploading, now: now, locale: english) == "2 minutes ago · Uploading")

        var current = stale
        current.uploadIsStale = false
        #expect(RecentCaptureFormatting.detailWithoutSize(for: current, now: now, locale: english) == "2 minutes ago")

        var editedImage = record(.uploaded(url: URL(string: "https://snap.tky.io/aB3dE9.png")!, key: "aB3dE9.png"))
        editedImage.uploadIsStale = true
        #expect(RecentCaptureFormatting.detail(for: editedImage, now: now, locale: english) == "2 minutes ago")
        var staleGIF = gif(.uploaded(url: URL(string: "https://snap.tky.io/aB3dE9.gif")!, key: "aB3dE9.gif"))
        staleGIF.uploadIsStale = true
        #expect(RecentCaptureFormatting.detail(for: staleGIF, now: now, locale: english) == "2 minutes ago")
    }

    /// A recording whose muting failed says `Sound not muted`, which the size gives way to. It has no
    /// Copy File, and its row's click opens the file instead.
    @Test func aMarkedRecordSaysSoundNotMutedAndItsClickOpensTheFile() {
        let pending = URL(fileURLWithPath: "/tmp/pending/\(UUID().uuidString).mp4")
        var marked = video(.none, file: pending, temporary: true)
        marked.unmutedIntervals = [MuteInterval(start: 2, end: 5)]
        #expect(RecentCaptureFormatting.detail(for: marked, now: now, locale: english) == "2 minutes ago · Sound not muted")
        marked.byteCount = 1_200_000
        let size = RecentCaptureFormatting.sizeText(1_200_000) ?? "missing"
        #expect(RecentCaptureFormatting.detail(for: marked, now: now, locale: english)
                == "2 minutes ago · \(size) · Sound not muted")
        #expect(RecentCaptureFormatting.detailWithoutSize(for: marked, now: now, locale: english)
                == "2 minutes ago · Sound not muted")

        #expect(!RecentCaptureFormatting.canCopyFile(marked))
        #expect(!RecentCaptureFormatting.showsImageActions(marked))
        #expect(RecentCaptureFormatting.rowClickOpens(marked))
        #expect(!RecentCaptureFormatting.rowClickOpens(video(.none)))
        #expect(!RecentCaptureFormatting.rowClickOpens(gif(.none)))
        #expect(!RecentCaptureFormatting.rowClickOpens(record(.none)))
    }

    // MARK: Size (spec 2.13)

    @Test func detailIsTheTimeAndTheSize() {
        #expect(RecentCaptureFormatting.detail(for: record(.none, byteCount: 5_000), now: now, locale: english)
                == "2 minutes ago · \(fiveKB)")
        let url = URL(string: "https://snap.tky.io/aB3dE9.png")!
        #expect(RecentCaptureFormatting.detail(for: record(.uploaded(url: url, key: "aB3dE9.png"), file: nil, byteCount: 5_000),
                                               now: now, locale: english) == "2 minutes ago · \(fiveKB)")
    }

    /// The upload state follows the size: `3 hours ago · 5 KB · Uploading`.
    @Test func detailIsTheTimeTheSizeAndEachUploadState() {
        #expect(RecentCaptureFormatting.detail(for: record(.uploading(fraction: 0.5), byteCount: 5_000), now: now, locale: english)
                == "2 minutes ago · \(fiveKB) · Uploading")
        #expect(RecentCaptureFormatting.detail(for: record(.failed(message: "offline"), secondsAgo: 86_400, byteCount: 5_000),
                                               now: now, locale: english) == "yesterday · \(fiveKB) · Upload failed")
        var recording = video(.uploading(fraction: 0))
        recording.byteCount = 5_000
        #expect(RecentCaptureFormatting.detail(for: recording, now: now, locale: english, isOptimizing: true)
                == "2 minutes ago · \(fiveKB) · Optimizing…")
        #expect(RecentCaptureFormatting.detail(for: recording, now: now, locale: english, isOptimizing: false)
                == "2 minutes ago · \(fiveKB) · Uploading")
    }

    /// An unknown size (a record from before 2.13 with no local file) and a zero one show no size part.
    @Test func detailHasNoSizeWhenNilOrZero() {
        for byteCount in [nil, 0] as [Int?] {
            #expect(RecentCaptureFormatting.detail(for: record(.none, byteCount: byteCount), now: now, locale: english)
                    == "2 minutes ago")
            #expect(RecentCaptureFormatting.detail(for: record(.uploading(fraction: 0.5), byteCount: byteCount), now: now,
                                                   locale: english) == "2 minutes ago · Uploading")
            #expect(RecentCaptureFormatting.detail(for: record(.failed(message: "offline"), byteCount: byteCount), now: now,
                                                   locale: english) == "2 minutes ago · Upload failed")
        }
        #expect(RecentCaptureFormatting.sizeText(nil) == nil)
        #expect(RecentCaptureFormatting.sizeText(0) == nil)
    }

    /// The parts are joined by a middle dot (U+00B7) with one space either side.
    @Test func partsAreSeparatedByAMiddleDot() {
        let detail = RecentCaptureFormatting.detail(for: record(.uploading(fraction: 0.5), byteCount: 5_000), now: now, locale: english)
        let parts = detail.components(separatedBy: " \u{00B7} ")
        #expect(parts == ["2 minutes ago", fiveKB, "Uploading"])
        #expect(detail.unicodeScalars.filter { $0 == "\u{00B7}" }.count == 2)
    }

    /// What the row falls back to when the whole detail would not fit: the time and the state, in
    /// that order, with the size left out. Nil when there is no size to leave out.
    @Test func detailWithoutSizeKeepsTheTimeAndTheState() {
        #expect(RecentCaptureFormatting.detailWithoutSize(for: record(.uploading(fraction: 0.5), byteCount: 120_000),
                                                          now: now, locale: english) == "2 minutes ago · Uploading")
        #expect(RecentCaptureFormatting.detailWithoutSize(for: record(.failed(message: "offline"), byteCount: 120_000),
                                                          now: now, locale: english) == "2 minutes ago · Upload failed")
        var recording = video(.uploading(fraction: 0))
        recording.byteCount = 1_200_000
        #expect(RecentCaptureFormatting.detailWithoutSize(for: recording, now: now, locale: english, isOptimizing: true)
                == "2 minutes ago · Optimizing…")
        #expect(RecentCaptureFormatting.detailWithoutSize(for: record(.none, byteCount: 5_000), now: now, locale: english)
                == "2 minutes ago")
        for byteCount in [nil, 0] as [Int?] {
            #expect(RecentCaptureFormatting.detailWithoutSize(for: record(.failed(message: "offline"), byteCount: byteCount),
                                                              now: now, locale: english) == nil)
        }
    }

    /// `ByteCountFormatter`'s `.file` style: decimal units, as Finder shows them.
    @Test(.enabled(if: currentIsUSEnglish, "ByteCountFormatter writes in the current locale"))
    func sizeTextInUSEnglish() {
        #expect(RecentCaptureFormatting.sizeText(999) == "999 bytes")
        #expect(RecentCaptureFormatting.sizeText(5_000) == "5 KB")
        #expect(RecentCaptureFormatting.sizeText(1_200_000) == "1.2 MB")
        #expect(RecentCaptureFormatting.sizeText(3_400_000_000) == "3.4 GB")
        #expect(RecentCaptureFormatting.detail(for: record(.none, secondsAgo: 3 * 3_600, byteCount: 5_000), now: now, locale: english)
                == "3 hours ago · 5 KB")
    }
}
