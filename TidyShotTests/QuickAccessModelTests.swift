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

    // MARK: GIF, Trim and the sound mark (recording R2)

    let folder = URL(fileURLWithPath: "/Users/tim/Pictures/TidyShot", isDirectory: true)

    /// `RecordingTrim.menuState` as `AppCoordinator.trimMenuState(for:)` reads it, with a destination.
    func trimState(_ card: QuickAccessModel, deleting: Bool = false, trimming: Bool = false,
                   destination: Bool = true) -> RecordingTrim.MenuState {
        RecordingTrim.menuState(card.record, saveFolder: folder, hasDestination: destination,
                                isDeleting: deleting, isTrimming: trimming)
    }

    /// A GIF has Copy File, Save As… and Open in place of the image actions, and the `GIF` badge.
    @Test func aGIFHasNoImageActionsCopiesItsFileAndHasTheGIFBadge() {
        let gif = model(file: URL(fileURLWithPath: "/Users/tim/Pictures/TidyShot/Recording.gif"), kind: .gif)
        #expect(!gif.showsImageActions)
        #expect(gif.canCopyFile)
        #expect(gif.canSaveAs)
        #expect(gif.canOpen)
        #expect(gif.badge == .gif)
        #expect(model(file: saved).badge == .play)
        #expect(model(file: URL(fileURLWithPath: "/Users/tim/Desktop/Shot.png"), kind: .image).badge == nil)
        #expect(!model(.uploaded(url: link, key: "aB3dE9.gif"), file: nil, kind: .gif).canCopyFile)
    }

    /// A card starts with no Trim items, until the coordinator sets its state.
    @Test func aNewCardHasNoTrimItems() {
        let card = model(file: saved)
        #expect(card.trimState == RecordingTrim.MenuState())
        #expect(!card.trimState.showsTrim)
        #expect(!card.trimState.showsUploadTrimmed)
        #expect(card.canRetry)
        #expect(card.canDelete)
    }

    /// `Trim…` shows for an MP4 only, and is disabled while it uploads or is being deleted.
    @Test func trimShowsOnlyForAVideoAndIsDisabledWhileUploadingOrDeleting() {
        let video = model(file: saved)
        video.trimState = trimState(video)
        #expect(video.trimState.showsTrim)
        #expect(video.trimState.canTrim)

        let gif = model(file: URL(fileURLWithPath: "/Users/tim/Pictures/TidyShot/Recording.gif"), kind: .gif)
        #expect(!trimState(gif).showsTrim)
        let image = model(file: URL(fileURLWithPath: "/Users/tim/Pictures/TidyShot/Shot.png"), kind: .image)
        #expect(!trimState(image).showsTrim)

        let uploading = model(.uploading(fraction: 0.4), file: saved)
        #expect(trimState(uploading).showsTrim)
        #expect(!trimState(uploading).canTrim)
        #expect(trimState(video, deleting: true).showsTrim)
        #expect(!trimState(video, deleting: true).canTrim)
    }

    /// An uploaded MP4 whose trim the link does not show yet says `Link not updated`, whether or not
    /// its URL was copied, and offers `Upload Trimmed`. An edited image keeps `URL copied`.
    @Test func aStaleVideoSaysLinkNotUpdatedAndOffersUploadTrimmed() {
        let card = model(.uploaded(url: link, key: "aB3dE9.mp4"), file: saved)
        card.record.uploadIsStale = true
        #expect(card.status == .linkNotUpdated(link))
        card.linkWasCopied = false
        #expect(card.status == .linkNotUpdated(link))
        card.trimState = trimState(card)
        #expect(card.trimState.showsUploadTrimmed)
        #expect(card.trimState.canUploadTrimmed)

        card.record.uploadIsStale = false
        #expect(card.status == .uploaded(link))
        #expect(!trimState(card).showsUploadTrimmed)

        let image = model(.uploaded(url: link, key: "aB3dE9.png"), file: URL(fileURLWithPath: "/Users/tim/Desktop/Shot.png"),
                          kind: .image)
        image.record.uploadIsStale = true
        #expect(image.status == .urlCopied(link))
    }

    /// A recording whose muting failed says `Sound not muted` and offers the thumbnail's Open,
    /// `Trim…` and Delete only: no Copy File, Save As…, Reveal or image actions.
    @Test func aMarkedRecordSaysSoundNotMutedAndOffersOpenTrimAndDeleteOnly() {
        let card = model(file: pending, temporary: true)
        card.record.unmutedIntervals = [MuteInterval(start: 2, end: 5)]
        #expect(card.status == .soundNotMuted)
        #expect(card.canOpen)
        #expect(!card.canCopyFile)
        #expect(!card.canSaveAs)
        #expect(!card.canReveal)
        #expect(!card.showsImageActions)
        card.trimState = trimState(card)
        #expect(card.trimState.showsTrim)
        #expect(card.trimState.canTrim)
        #expect(!card.trimState.showsUploadTrimmed)
        #expect(card.canDelete)

        card.record.unmutedIntervals = []
        #expect(card.status == .kept)
        #expect(card.canCopyFile)
        #expect(card.canSaveAs)
    }

    /// A drag-out download over an uploaded recording with no local file says `Downloading…` with
    /// its fraction, in place of `URL copied`.
    @Test func aRunningDragDownloadShowsItsFraction() {
        let card = model(.uploaded(url: link, key: "aB3dE9.mp4"), file: nil)
        #expect(card.dragDownload == nil)
        #expect(!card.isDownloadingForDrag)
        card.dragDownload = .running(0.4)
        #expect(card.status == .downloading(0.4))
        #expect(card.isDownloadingForDrag)
        card.dragDownload = nil
        #expect(card.status == .urlCopied(link))
    }

    /// A failed download says `Download failed` with its error. The record stays uploaded, so the
    /// card offers Copy URL, not Retry; the next drag tries again.
    @Test func aFailedDragDownloadShowsTheErrorAndLeavesTheUpload() {
        let card = model(.uploaded(url: link, key: "aB3dE9.mp4"), file: nil)
        card.dragDownload = .failed("Server returned HTTP 403.")
        #expect(card.status == .downloadFailed("Server returned HTTP 403."))
        #expect(!card.isDownloadingForDrag)
        #expect(card.record.uploadedURL == link)
    }

    /// `Sound not muted` wins over a download's status.
    @Test func soundNotMutedWinsOverADragDownload() {
        let card = model(.uploaded(url: link, key: "aB3dE9.mp4"), file: nil)
        card.record.unmutedIntervals = [MuteInterval(start: 2, end: 5)]
        card.dragDownload = .running(0.4)
        #expect(card.status == .soundNotMuted)
        card.dragDownload = .failed("offline")
        #expect(card.status == .soundNotMuted)
    }

    /// While a Trim pass writes the record's file, Retry, `Upload Trimmed` and Delete are disabled,
    /// as Retry and `Upload Trimmed` are while the record uploads.
    @Test func retryUploadTrimmedAndDeleteAreDisabledWhileTrimming() {
        let stale = model(.uploaded(url: link, key: "aB3dE9.mp4"), file: saved)
        stale.record.uploadIsStale = true
        stale.trimState = trimState(stale, trimming: true)
        #expect(stale.trimState.showsUploadTrimmed)
        #expect(!stale.trimState.canUploadTrimmed)
        #expect(!stale.trimState.canTrim)
        #expect(!stale.canDelete)

        let failed = model(.failed(message: "offline"), file: saved)
        failed.trimState = trimState(failed, trimming: true)
        #expect(!failed.canRetry)
        #expect(!failed.canDelete)
        failed.trimState = trimState(failed)
        #expect(failed.canRetry)
        #expect(failed.canDelete)
    }
}
