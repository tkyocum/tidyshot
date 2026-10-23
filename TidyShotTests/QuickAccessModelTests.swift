import Foundation
import Testing
@testable import TidyShot

struct QuickAccessModelTests {
    let saved = URL(fileURLWithPath: "/Users/tim/Pictures/TidyShot/Recording 2026-10-22 at 10.00.00.mp4")
    let pending = URL(fileURLWithPath: "/Users/tim/Library/Containers/io.tky.tidyshot/Data/pending/A.mp4")
    let link = URL(string: "https://snap.tky.io/aB3dE9.mp4")!

    func model(_ state: CaptureRecord.UploadState = .none, file: URL?, temporary: Bool = false,
               kind: MediaKind = .video) -> QuickAccessModel {
        let record = CaptureRecord(fileURL: file, fileIsTemporary: temporary, pixelWidth: 1600, pixelHeight: 1000,
                                   appName: nil, uploadState: state, mediaKind: kind,
                                   durationSeconds: kind == .video ? 42 : nil)
        return QuickAccessModel(record: record, thumbnail: nil)
    }

    @Test func aNewCardIsNotOptimizingAndItsLinkWasCopied() {
        let card = model(file: saved)
        #expect(!card.isOptimizing)
        #expect(card.linkWasCopied)
    }

    /// A saved capture shows its file name; one with no file says so.
    @Test func savedShowsTheFileName() {
        #expect(model(file: saved).status == .saved("Recording 2026-10-22 at 10.00.00.mp4"))
        #expect(model(file: URL(fileURLWithPath: "/Users/tim/Desktop/Shot.png"), kind: .image).status == .saved("Shot.png"))
        #expect(model(file: nil, kind: .image).status == .saved("Upload only, no local file"))
    }

    /// A temporary file with `.none` (a recording that could not reach the save folder) is kept in
    /// TidyShot, not saved under its `<uuid>.mp4`.
    @Test func aTemporaryFileWithNoUploadIsKept() {
        #expect(model(file: pending, temporary: true).status == .kept)
    }

    @Test func uploadingShowsTheFraction() {
        #expect(model(.uploading(fraction: 0.4), file: saved).status == .uploading(0.4))
        #expect(model(.uploading(fraction: 0.4), file: pending, temporary: true).status == .uploading(0.4))
    }

    /// While a recording waits for Clop its card says `Optimizing…` in place of the progress.
    @Test func optimizingWhileClopRuns() {
        let card = model(.uploading(fraction: 0), file: saved)
        card.isOptimizing = true
        #expect(card.status == .optimizing)
        card.isOptimizing = false
        #expect(card.status == .uploading(0))
    }

    /// `URL copied` when the link replaced the clipboard; `Uploaded` for a recording whose link did
    /// not, because the clipboard had changed since the save.
    @Test func uploadedSaysWhetherTheLinkWasCopied() {
        let card = model(.uploaded(url: link, key: "aB3dE9.mp4"), file: nil)
        #expect(card.status == .urlCopied(link))
        card.linkWasCopied = false
        #expect(card.status == .uploaded(link))
    }

    @Test func failedShowsTheMessage() {
        #expect(model(.failed(message: "Upload cancelled."), file: pending, temporary: true).status
                == .failed("Upload cancelled."))
    }

    /// No Annotate, Pin or Copy Image for a video; Copy File for one with a local file, in the save
    /// folder or `pending/`, and none without.
    @Test func aVideoHasCopyFileInPlaceOfTheImageActions() {
        let video = model(file: saved)
        #expect(!video.showsImageActions)
        #expect(video.canCopyFile)
        #expect(model(.uploading(fraction: 0.2), file: pending, temporary: true).canCopyFile)
        let uploadedOnly = model(.uploaded(url: link, key: "aB3dE9.mp4"), file: nil)
        #expect(!uploadedOnly.canCopyFile)
        #expect(!uploadedOnly.showsImageActions)

        let image = model(file: URL(fileURLWithPath: "/Users/tim/Desktop/Shot.png"), kind: .image)
        #expect(image.showsImageActions)
        #expect(!image.canCopyFile)
    }
}
