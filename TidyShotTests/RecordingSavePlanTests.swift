import Foundation
import Testing
@testable import TidyShot

struct RecordingSavePlanTests {
    let uploadWarning = "Set up a destination in Settings > Upload. The recording was saved and is on the clipboard as a file."
    let uploadOnlyWarning = "Set up a destination in Settings > Upload, then retry from Recent Captures. TidyShot keeps the recording until then."
    let notConfigured = CaptureRecord.UploadState.failed(message: "No upload destination is configured.")
    let interrupted = CaptureRecord.UploadState.failed(message: "Upload was interrupted.")

    func plan(_ action: AfterCaptureAction, destination: Bool = true, result: RecordingFileResult,
              copyImage: Bool = false, alsoCopyImage: Bool = false, quit: Bool = false) -> RecordingSavePlan {
        RecordingSavePlan.make(action: action, hasDestination: destination, result: result,
                               copyImage: copyImage, alsoCopyImage: alsoCopyImage, quitMode: quit)
    }

    // MARK: The table

    @Test func targets() {
        #expect(RecordingSavePlan.target(for: .save) == .saveFolder)
        #expect(RecordingSavePlan.target(for: .upload) == .saveFolder)
        #expect(RecordingSavePlan.target(for: .uploadOnly) == .pending)
    }

    @Test func saveMovesIntoTheFolderAndCopiesAReferenceWhenAsked() {
        let copying = plan(.save, result: .saveFolder, copyImage: true)
        #expect(copying.makesRecord)
        #expect(!copying.fileIsTemporary)
        #expect(copying.uploadState == .none)
        #expect(!copying.uploads)
        #expect(copying.copiesFileReference)
        #expect(copying.setsLastCaptureURL)
        #expect(copying.showsCard)
        #expect(copying.notification == .saved)
        #expect(copying.notConfiguredWarning == nil)

        #expect(!plan(.save, result: .saveFolder, copyImage: false).copiesFileReference)
        // `Also copy image…` is for uploads; it does not copy a `.save` recording.
        #expect(!plan(.save, result: .saveFolder, alsoCopyImage: true).copiesFileReference)
    }

    @Test func uploadUploadsTheSaveFolderFileAndCopiesAReferenceMeanwhileWhenAsked() {
        let copying = plan(.upload, result: .saveFolder, alsoCopyImage: true)
        #expect(!copying.fileIsTemporary)
        #expect(copying.uploadState == .uploading(fraction: 0))
        #expect(copying.uploads)
        #expect(copying.copiesFileReference)
        #expect(copying.setsLastCaptureURL)
        #expect(copying.showsCard)
        #expect(copying.notification == .none)
        #expect(copying.notConfiguredWarning == nil)

        #expect(!plan(.upload, result: .saveFolder, copyImage: true, alsoCopyImage: false).copiesFileReference)
    }

    @Test func uploadOnlyUploadsThePendingFileAndCopiesNothing() {
        let pending = plan(.uploadOnly, result: .pending, copyImage: true, alsoCopyImage: true)
        #expect(pending.makesRecord)
        #expect(pending.fileIsTemporary)
        #expect(pending.uploadState == .uploading(fraction: 0))
        #expect(pending.uploads)
        #expect(!pending.copiesFileReference)
        #expect(!pending.setsLastCaptureURL)
        #expect(pending.showsCard)
        #expect(pending.notification == .none)
    }

    // MARK: No destination

    /// Saved exactly as `.save`, with a file reference on the clipboard whatever the settings say.
    @Test func uploadWithNoDestinationIsSavedAndCopiedAsAFile() {
        let saved = plan(.upload, destination: false, result: .saveFolder)
        #expect(!saved.fileIsTemporary)
        #expect(saved.uploadState == .none)
        #expect(!saved.uploads)
        #expect(saved.copiesFileReference)
        #expect(saved.setsLastCaptureURL)
        #expect(saved.notification == .saved)
        #expect(saved.notConfiguredWarning == uploadWarning)
    }

    @Test func uploadOnlyWithNoDestinationWaitsInPendingWithNothingCopied() {
        let waiting = plan(.uploadOnly, destination: false, result: .pending, copyImage: true, alsoCopyImage: true)
        #expect(waiting.fileIsTemporary)
        #expect(waiting.uploadState == notConfigured)
        #expect(!waiting.uploads)
        #expect(!waiting.copiesFileReference)
        #expect(waiting.notification == .none)
        #expect(waiting.notConfiguredWarning == uploadOnlyWarning)
    }

    // MARK: Where the file lands (fallbacks)

    @Test func noFolderChosenGivesNotSavedToAFolder() {
        for action in [AfterCaptureAction.save, .upload] {
            let fallback = plan(action, result: .fallback(reason: RecordingSavePlan.noFolderReason))
            guard case .notice(let notice) = fallback.notification else {
                Issue.record("\(action) posts no notice")
                continue
            }
            #expect(notice.title == "Not saved to a folder")
            #expect(notice.body.hasPrefix("No folder was chosen."))
        }
        #expect(RecordingSavePlan.noFolderReason == "No folder was chosen.")
    }

    /// The file stays in `pending/` with `.none`, never `.failed`, and the reference follows the
    /// table's rule, so it points at the pending file (Gap 4).
    @Test func saveFallbackKeepsTheRecordingInPending() {
        let fallback = plan(.save, result: .fallback(reason: "The folder is gone."), copyImage: true)
        #expect(fallback.makesRecord)
        #expect(fallback.fileIsTemporary)
        #expect(fallback.uploadState == .none)
        #expect(!fallback.uploads)
        #expect(fallback.copiesFileReference)
        #expect(!fallback.setsLastCaptureURL)
        #expect(fallback.showsCard)
        #expect(fallback.notification == .notice(RecordingNotice(
            title: "Not saved to a folder",
            body: "The folder is gone. TidyShot keeps the recording. Use Save As… on its card.")))
        #expect(!plan(.save, result: .fallback(reason: "x"), copyImage: false).copiesFileReference)
    }

    /// From here on it behaves as `.uploadOnly`, the clipboard included.
    @Test func uploadFallbackUploadsWithoutALocalCopy() {
        let fallback = plan(.upload, result: .fallback(reason: "The folder is gone."), copyImage: true, alsoCopyImage: true)
        #expect(fallback.fileIsTemporary)
        #expect(fallback.uploadState == .uploading(fraction: 0))
        #expect(fallback.uploads)
        #expect(!fallback.copiesFileReference)
        #expect(!fallback.setsLastCaptureURL)
        #expect(fallback.notification == .notice(RecordingNotice(
            title: "Not saved to a folder",
            body: "The folder is gone. The recording uploads without a local copy.")))
    }

    /// `.upload` with no destination falls back exactly as `.save`, with the forced reference (Gap 4).
    @Test func uploadWithNoDestinationFallsBackAsSave() {
        let fallback = plan(.upload, destination: false, result: .fallback(reason: RecordingSavePlan.noFolderReason))
        #expect(fallback.fileIsTemporary)
        #expect(fallback.uploadState == .none)
        #expect(!fallback.uploads)
        #expect(fallback.copiesFileReference)
        #expect(fallback.notification == .notice(RecordingNotice(
            title: "Not saved to a folder",
            body: "No folder was chosen. TidyShot keeps the recording. Use Save As… on its card.")))
        #expect(fallback.notConfiguredWarning == uploadWarning)
    }

    /// Even the rename into `pending/` failed: no record, and the notice gives the path (Gap 6).
    @Test func leftInTmpMakesNoRecordAndGivesThePath() {
        let path = "/Users/tim/Library/Containers/io.tky.tidyshot/Data/tmp/Recording/A.mp4"
        for action in [AfterCaptureAction.save, .upload, .uploadOnly] {
            let left = plan(action, result: .leftInTmp(reason: "The disk is full.", path: path), copyImage: true, alsoCopyImage: true)
            #expect(!left.makesRecord)
            #expect(!left.uploads)
            #expect(!left.copiesFileReference)
            #expect(!left.setsLastCaptureURL)
            #expect(!left.showsCard)
            #expect(left.notConfiguredWarning == nil)
            #expect(left.notification == .notice(RecordingNotice(
                title: "Not saved to a folder",
                body: "The disk is full. The recording is still at \(path).")))
        }
    }

    @Test func notSavedToFolderText() {
        #expect(RecordingSavePlan.notSavedToFolder(reason: "No folder was chosen.", uploads: false)
            == RecordingNotice(title: "Not saved to a folder",
                               body: "No folder was chosen. TidyShot keeps the recording. Use Save As… on its card."))
        #expect(RecordingSavePlan.notSavedToFolder(reason: "No folder was chosen.", uploads: true)
            == RecordingNotice(title: "Not saved to a folder",
                               body: "No folder was chosen. The recording uploads without a local copy."))
    }

    // MARK: Quit mode (Gap 5)

    /// No upload, card, notification or warning; the clipboard rule still applies, and an
    /// uploading action is written as interrupted.
    @Test(arguments: [true, false])
    func quitModeForEachAction(destination: Bool) {
        let save = plan(.save, destination: destination, result: .saveFolder, copyImage: true, quit: true)
        #expect(save.makesRecord)
        #expect(save.uploadState == .none)
        #expect(save.copiesFileReference)
        #expect(save.setsLastCaptureURL)

        let upload = plan(.upload, destination: destination, result: .saveFolder, alsoCopyImage: true, quit: true)
        #expect(upload.uploadState == (destination ? interrupted : .none))
        #expect(upload.copiesFileReference)
        #expect(!upload.fileIsTemporary)

        let uploadOnly = plan(.uploadOnly, destination: destination, result: .pending, quit: true)
        #expect(uploadOnly.uploadState == (destination ? interrupted : notConfigured))
        #expect(!uploadOnly.copiesFileReference)
        #expect(uploadOnly.fileIsTemporary)

        let fallback = plan(.save, destination: destination, result: .fallback(reason: RecordingSavePlan.noFolderReason), quit: true)
        #expect(fallback.makesRecord)
        #expect(fallback.fileIsTemporary)

        for quitPlan in [save, upload, uploadOnly, fallback] {
            #expect(!quitPlan.uploads)
            #expect(!quitPlan.showsCard)
            #expect(quitPlan.notification == .none)
            #expect(quitPlan.notConfiguredWarning == nil)
        }
    }

    @Test func quitModeLeftInTmpPostsNothing() {
        let left = plan(.save, result: .leftInTmp(reason: "x", path: "/tmp/A.mp4"), quit: true)
        #expect(!left.makesRecord)
        #expect(left.notification == .none)
    }

    // MARK: Sound not muted (design, Privacy rule)

    let unmuted = [MuteInterval(start: 1.9, end: 5.3)]

    /// The folder is skipped before it is chosen: `saveRecording` never asks for one or moves into
    /// one for a marked recording.
    @Test func aMarkedRecordingTargetsPendingForEveryAction() {
        for action in [AfterCaptureAction.save, .upload, .uploadOnly] {
            #expect(RecordingSavePlan.target(for: action, unmutedIntervals: unmuted) == .pending)
            #expect(RecordingSavePlan.target(for: action, unmutedIntervals: [])
                == RecordingSavePlan.target(for: action))
        }
        #expect(RecordingSavePlan.target(for: .save, unmutedIntervals: []) == .saveFolder)
        #expect(RecordingSavePlan.target(for: .upload, unmutedIntervals: []) == .saveFolder)
        #expect(RecordingSavePlan.target(for: .uploadOnly, unmutedIntervals: []) == .pending)
    }

    /// No upload, no file reference and no `lastCaptureURL`, the state `.none`, in normal and quit
    /// mode, with or without a destination. `Sound not muted` posts in normal mode only.
    @Test(arguments: [true, false])
    func aMarkedRecordingIsKeptAndNeverLeaves(quit: Bool) {
        for action in [AfterCaptureAction.save, .upload, .uploadOnly] {
            for destination in [true, false] {
                let marked = RecordingSavePlan.make(action: action, hasDestination: destination, result: .pending,
                                                    copyImage: true, alsoCopyImage: true, quitMode: quit,
                                                    unmutedIntervals: unmuted)
                #expect(marked.makesRecord)
                #expect(marked.fileIsTemporary)
                #expect(marked.uploadState == .none)
                #expect(!marked.uploads)
                #expect(!marked.copiesFileReference)
                #expect(!marked.setsLastCaptureURL)
                #expect(marked.showsCard == !quit)
                #expect(marked.notConfiguredWarning == nil)
                #expect(marked.notification == (quit ? .none : .notice(RecordingSavePlan.soundNotMutedNotice)))
            }
        }
    }

    @Test func aMarkedRecordingLeftInTmpMakesNoRecord() {
        let left = RecordingSavePlan.make(action: .save, hasDestination: true,
                                          result: .leftInTmp(reason: "The disk is full.", path: "/tmp/A.mp4"),
                                          copyImage: true, alsoCopyImage: false, quitMode: false,
                                          unmutedIntervals: unmuted)
        #expect(!left.makesRecord)
        #expect(!left.uploads)
        #expect(!left.copiesFileReference)
        #expect(left.notification == .notice(RecordingNotice(
            title: "Not saved to a folder", body: "The disk is full. The recording is still at /tmp/A.mp4.")))
    }

    @Test func soundNotMutedHasTheRecordsText() {
        #expect(RecordingSavePlan.soundNotMutedNotice == RecordingNotice(
            title: "Sound not muted",
            body: "Muting failed. The recording is kept in TidyShot and not uploaded. Trim it to fix the sound, or delete it."))
    }

    // MARK: Clipboard after the upload

    @Test func urlReplacesTheClipboardOnlyWhenItIsUnchanged() {
        #expect(RecordingSavePlan.replacesClipboard(savedChangeCount: 42, currentChangeCount: 42))
        #expect(!RecordingSavePlan.replacesClipboard(savedChangeCount: 42, currentChangeCount: 43))
        // No count, as after a relaunch: the clipboard counts as changed.
        #expect(!RecordingSavePlan.replacesClipboard(savedChangeCount: nil, currentChangeCount: 42))
    }

    // MARK: The size refusal (Gap 4)

    @Test func oversizedNotice() {
        #expect(RecordingSavePlan.oversizedNotice == RecordingNotice(
            title: "Not uploaded", body: "The recording is larger than 5 GB, too large to upload in one piece."))
    }

    @Test func oversizedSaveFolderFileStays() {
        #expect(!RecordingSavePlan.oversizedMoves(fileIsTemporary: false))
        #expect(RecordingSavePlan.oversized(fileIsTemporary: false, move: nil) == RecordingOversizePlan(
            fileIsTemporary: false, uploadState: .none, notices: [RecordingSavePlan.oversizedNotice]))
    }

    @Test func oversizedPendingFileMovesIntoTheSaveFolder() {
        #expect(RecordingSavePlan.oversizedMoves(fileIsTemporary: true))
        #expect(RecordingSavePlan.oversized(fileIsTemporary: true, move: .saveFolder) == RecordingOversizePlan(
            fileIsTemporary: false, uploadState: .none, notices: [RecordingSavePlan.oversizedNotice]))
    }

    @Test(arguments: [RecordingSavePlan.noFolderReason, "The folder is gone."])
    func oversizedPendingFileThatCannotMoveStaysWithBothNotices(reason: String) {
        #expect(RecordingSavePlan.oversized(fileIsTemporary: true, move: .fallback(reason: reason)) == RecordingOversizePlan(
            fileIsTemporary: true, uploadState: .none,
            notices: [RecordingSavePlan.oversizedNotice, RecordingSavePlan.notSavedToFolder(reason: reason, uploads: false)]))
    }

    /// Where the file is decides, not the action: a `.upload` fallback is in `pending/`, so it moves.
    @Test func oversizedUploadFallbackMovesAsUploadOnlyDoes() {
        let fallback = plan(.upload, result: .fallback(reason: "The folder is gone."))
        let uploadOnly = plan(.uploadOnly, result: .pending)
        #expect(RecordingSavePlan.oversizedMoves(fileIsTemporary: fallback.fileIsTemporary))
        #expect(RecordingSavePlan.oversizedMoves(fileIsTemporary: fallback.fileIsTemporary)
            == RecordingSavePlan.oversizedMoves(fileIsTemporary: uploadOnly.fileIsTemporary))
    }
}
