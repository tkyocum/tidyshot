import AVFoundation
import Foundation
import Synchronization
import Testing
@testable import TidyShot

/// Trim (design, Trim): the range, the source, the sheet, the menu, the write-time plans, what
/// follows a put and the in-progress marker's refusals, which are pure; then the method, the export
/// and Save's export over `VideoFixtures` movies (Export, Method, Progress, Disk space).
@Suite(.timeLimit(.minutes(2)))
struct RecordingTrimTests {
    let folder = URL(filePath: "/Users/tim/Movies/TidyShot", directoryHint: .isDirectory)
    let savedFile = URL(filePath: "/Users/tim/Movies/TidyShot/Recording 2026-10-23 at 10.00.00.mp4")
    let outsideFile = URL(filePath: "/Users/tim/Desktop/Recording 2026-10-23 at 10.00.00.mp4")
    let pendingFile = URL(filePath: "/Users/tim/Library/Containers/io.tky.tidyshot/Data/pending/A.mp4")
    let location = ObjectLocation(endpoint: "https://s3.us-west-2.amazonaws.com", region: "us-west-2",
                                  bucket: "snap.tky.io", usePathStyle: true)
    let link = URL(string: "https://snap.tky.io/rec.mp4")!

    func t(_ seconds: Double) -> CMTime { CMTime(seconds: seconds, preferredTimescale: 600) }

    func recording(_ fileURL: URL?, temporary: Bool = false, state: CaptureRecord.UploadState = .none,
                   located: Bool = false, stale: Bool = false, kind: MediaKind = .video) -> CaptureRecord {
        CaptureRecord(fileURL: fileURL, fileIsTemporary: temporary, pixelWidth: 1600, pixelHeight: 1000, appName: nil,
                      uploadState: state, objectLocation: located ? location : nil, uploadIsStale: stale,
                      mediaKind: kind, durationSeconds: 64)
    }

    /// In the save folder, never uploaded.
    var saved: CaptureRecord { recording(savedFile) }
    /// In `pending/`, never uploaded.
    var pending: CaptureRecord { recording(pendingFile, temporary: true) }
    /// Uploaded upload-only: no file left, only the object.
    var uploadOnly: CaptureRecord { recording(nil, state: .uploaded(url: link, key: "rec.mp4"), located: true) }
    /// In the save folder and uploaded, so it has a link.
    var savedAndUploaded: CaptureRecord {
        recording(savedFile, state: .uploaded(url: link, key: "rec.mp4"), located: true)
    }

    // MARK: Paths and texts

    @Test func pathsAreInTmpTrim() {
        let id = UUID(uuidString: "6F1A3C0E-2B4D-4E5F-8A9B-0C1D2E3F4A5B")!
        let trim = FileManager.default.temporaryDirectory.appending(path: "Trim", directoryHint: .isDirectory)
        #expect(RecordingTrim.directory.standardizedFileURL == trim.standardizedFileURL)
        #expect(RecordingTrim.downloadURL(for: id) == RecordingTrim.directory.appending(path: "\(id.uuidString).mp4"))
        #expect(RecordingTrim.trimmedURL(for: id) == RecordingTrim.directory.appending(path: "\(id.uuidString)-trimmed.mp4"))
        #expect(RecordingTrim.mutedURL(for: id) == RecordingTrim.directory.appending(path: "\(id.uuidString)-muted.mp4"))
    }

    @Test func texts() {
        #expect(RecordingTrim.minimumDuration == 0.5)
        #expect(RecordingTrim.notTrimmedTitle == "Not trimmed")
        #expect(RecordingTrim.tooShortText == "The trimmed recording would be too short.")
        #expect(RecordingTrim.notEnoughSpaceText == "Not enough disk space.")
        #expect(RecordingTrimError.notEnoughSpace.localizedDescription == "Not enough disk space.")
        #expect(EditorAvailability.trimmingRefusal == "This capture is being trimmed.")
        #expect(CaptureDeletion.trimmingRefusal == "This capture is being trimmed. Delete it when the trim finishes.")
    }

    // MARK: The range

    @Test func rangeKeepsAValidRange() throws {
        let range = try #require(RecordingTrim.range(start: t(1), end: t(3.5), duration: t(10)))
        #expect(range == CMTimeRange(start: t(1), end: t(3.5)))
    }

    @Test func rangeReadsAnInvalidTimeAsTheFilesStartOrEnd() throws {
        #expect(try #require(RecordingTrim.range(start: .invalid, end: t(4), duration: t(10)))
                == CMTimeRange(start: .zero, end: t(4)))
        #expect(try #require(RecordingTrim.range(start: t(2), end: .invalid, duration: t(10)))
                == CMTimeRange(start: t(2), end: t(10)))
        #expect(try #require(RecordingTrim.range(start: .invalid, end: .indefinite, duration: t(10)))
                == CMTimeRange(start: .zero, end: t(10)))
    }

    @Test func rangeClampsToTheFile() throws {
        #expect(try #require(RecordingTrim.range(start: t(-1), end: t(12), duration: t(10)))
                == CMTimeRange(start: .zero, end: t(10)))
    }

    @Test func rangeRefusesUnderHalfASecond() throws {
        #expect(RecordingTrim.range(start: t(2), end: t(2.4), duration: t(10)) == nil)
        #expect(RecordingTrim.range(start: t(9.8), end: .invalid, duration: t(10)) == nil)
        #expect(RecordingTrim.range(start: t(5), end: t(3), duration: t(10)) == nil)
        #expect(RecordingTrim.range(start: t(11), end: t(12), duration: t(10)) == nil)
        #expect(try #require(RecordingTrim.range(start: t(2), end: t(2.5), duration: t(10)))
                == CMTimeRange(start: t(2), end: t(2.5)))
    }

    // MARK: The sheet

    @Test func saveTargetWithADestination() {
        let target = EditorSaveTarget.Plan.saveFolderFile(savedFile, folder: folder)
        #expect(RecordingTrim.sheet(plan: target, hasDestination: true, hasLink: true)
                == RecordingTrim.Sheet(buttons: [.saveAndUpload, .save, .cancel],
                                       linkSentence: "The link keeps showing the full recording unless you choose Save and Upload."))
        #expect(RecordingTrim.sheet(plan: .pendingFile(pendingFile), hasDestination: true, hasLink: false)
                == RecordingTrim.Sheet(buttons: [.save, .saveAndUpload, .cancel], linkSentence: nil))
    }

    @Test func saveTargetWithNoDestination() {
        #expect(RecordingTrim.sheet(plan: .pendingFile(pendingFile), hasDestination: false, hasLink: true)
                == RecordingTrim.Sheet(buttons: [.save, .cancel], linkSentence: "The link keeps showing the full recording."))
        #expect(RecordingTrim.sheet(plan: .saveFolderFile(savedFile, folder: folder), hasDestination: false, hasLink: false)
                == RecordingTrim.Sheet(buttons: [.save, .cancel], linkSentence: nil))
    }

    @Test func nothingToSaveOver() {
        let unavailable = EditorSaveTarget.Plan.unavailable(EditorSaveTarget.noFileReason)
        #expect(RecordingTrim.sheet(plan: unavailable, hasDestination: true, hasLink: true)
                == RecordingTrim.Sheet(buttons: [.saveAndUpload, .cancel], linkSentence: "The link will show the trimmed recording."))
        #expect(RecordingTrim.sheet(plan: unavailable, hasDestination: true, hasLink: false)
                == RecordingTrim.Sheet(buttons: [.saveAndUpload, .cancel], linkSentence: nil))
        #expect(RecordingTrim.sheet(plan: unavailable, hasDestination: false, hasLink: true) == nil)
        #expect(RecordingTrim.sheet(plan: unavailable, hasDestination: false, hasLink: false) == nil)
    }

    @Test func cancelIsAlwaysLastAndTheButtonsHaveTheirTitles() {
        let plans: [EditorSaveTarget.Plan] = [.saveFolderFile(savedFile, folder: folder), .pendingFile(pendingFile),
                                              .unavailable(EditorSaveTarget.noFolderReason)]
        for plan in plans {
            for hasDestination in [true, false] {
                for hasLink in [true, false] {
                    guard let sheet = RecordingTrim.sheet(plan: plan, hasDestination: hasDestination, hasLink: hasLink) else { continue }
                    #expect(sheet.buttons.last == .cancel)
                    #expect(sheet.buttons.filter { $0 == .cancel }.count == 1)
                }
            }
        }
        #expect(RecordingTrim.SheetButton.save.title == "Save")
        #expect(RecordingTrim.SheetButton.saveAndUpload.title == "Save and Upload")
        #expect(RecordingTrim.SheetButton.cancel.title == "Cancel")
        #expect(RecordingTrim.saveMessage == "Save the trimmed recording?")
    }

    @Test func informativeTextSaysWhatIsKeptThenTheSentence() {
        let plain = RecordingTrim.Sheet(buttons: [.save, .cancel], linkSentence: nil)
        #expect(RecordingTrim.informativeText(kept: 12.4, of: 64.9, sheet: plain)
                == "Keeps 0:12 of 1:04. The rest is cut from the file.")
        let linked = RecordingTrim.Sheet(buttons: [.save, .cancel], linkSentence: "The link keeps showing the full recording.")
        #expect(RecordingTrim.informativeText(kept: 12.4, of: 64.9, sheet: linked)
                == "Keeps 0:12 of 1:04. The rest is cut from the file. The link keeps showing the full recording.")
    }

    // MARK: Where Trim shows

    @Test func trimShowsForMP4RecordingsOnly() {
        #expect(RecordingTrim.showsTrim(saved))
        #expect(!RecordingTrim.showsTrim(recording(savedFile, kind: .gif)))
        #expect(!RecordingTrim.showsTrim(recording(savedFile, kind: .image)))
    }

    @Test func canTrimARecordingWithASourceAndAButton() {
        func can(_ record: CaptureRecord, folder: URL?, destination: Bool) -> Bool {
            RecordingTrim.canTrim(record, saveFolder: folder, hasDestination: destination, isDeleting: false, isTrimming: false)
        }
        #expect(can(saved, folder: folder, destination: false))
        #expect(can(pending, folder: nil, destination: false))
        // Upload-only: only Save and Upload, so it needs a destination.
        #expect(can(uploadOnly, folder: folder, destination: true))
        #expect(!can(uploadOnly, folder: folder, destination: false))
        // Outside the folder with an upload: a download and Save and Upload.
        #expect(can(savedAndUploaded, folder: nil, destination: true))
        #expect(!can(savedAndUploaded, folder: nil, destination: false))
        // `.unavailable`: never uploaded and nothing to read.
        #expect(!can(recording(nil), folder: folder, destination: true))
        #expect(!can(recording(outsideFile), folder: folder, destination: true))
        // GIFs and screenshots are never trimmed.
        #expect(!can(recording(savedFile, kind: .gif), folder: folder, destination: true))
        #expect(!can(recording(savedFile, kind: .image), folder: folder, destination: true))
    }

    /// Why `Trim…` cannot open the window from the folder and the destination alone, which
    /// `trimCapture` posts for a card drawn before Settings changed: nothing to read, or nothing to
    /// save over with no destination (the sheet would have no button but `Cancel`).
    @Test func openRefusalGivesTheSourcesOrTheSaveTargetsReason() {
        func refusal(_ record: CaptureRecord, folder: URL?, destination: Bool) -> String? {
            RecordingTrim.openRefusal(for: record, source: EditorInput.fileSource(for: record, saveFolder: folder),
                                      saveFolder: folder, hasDestination: destination)
        }
        #expect(refusal(saved, folder: folder, destination: false) == nil)
        #expect(refusal(pending, folder: nil, destination: false) == nil)
        #expect(refusal(uploadOnly, folder: folder, destination: true) == nil)
        // The destination was forgotten: nothing to save over, and no button but Cancel.
        #expect(refusal(uploadOnly, folder: folder, destination: false) == EditorSaveTarget.noFileReason)
        #expect(refusal(savedAndUploaded, folder: nil, destination: false) == EditorSaveTarget.noFolderReason)
        // The save folder changed: a file outside it that was never uploaded has nothing to read.
        #expect(refusal(saved, folder: nil, destination: true) == EditorInput.outsideSaveFolderText)
        #expect(refusal(recording(nil), folder: folder, destination: true) == EditorInput.neverUploadedText)
        // Uploading, being deleted or trimmed are not its reasons: the item is disabled then.
        let uploading = recording(savedFile, state: .uploading(fraction: 0.3))
        #expect(refusal(uploading, folder: folder, destination: true) == nil)
        #expect(!RecordingTrim.canTrim(uploading, saveFolder: folder, hasDestination: true, isDeleting: false,
                                       isTrimming: false))
    }

    @Test func canTrimIsFalseWhileUploadingDeletingOrTrimming() {
        let uploading = recording(savedFile, state: .uploading(fraction: 0.3))
        #expect(!RecordingTrim.canTrim(uploading, saveFolder: folder, hasDestination: true, isDeleting: false, isTrimming: false))
        #expect(!RecordingTrim.canTrim(saved, saveFolder: folder, hasDestination: true, isDeleting: true, isTrimming: false))
        #expect(!RecordingTrim.canTrim(saved, saveFolder: folder, hasDestination: true, isDeleting: false, isTrimming: true))
    }

    @Test func aMarkedRecordCanBeTrimmed() {
        var marked = pending
        marked.unmutedIntervals = [MuteInterval(start: 1, end: 2)]
        #expect(RecordingTrim.canTrim(marked, saveFolder: nil, hasDestination: false, isDeleting: false, isTrimming: false))
    }

    @Test func menuStateShowsUploadTrimmedForAStaleVideoWithAFileAndADestination() {
        let stale = recording(savedFile, state: .uploaded(url: link, key: "rec.mp4"), located: true, stale: true)
        let state = RecordingTrim.menuState(stale, saveFolder: folder, hasDestination: true, isDeleting: false, isTrimming: false)
        #expect(state == RecordingTrim.MenuState(showsTrim: true, canTrim: true, showsUploadTrimmed: true,
                                                 canUploadTrimmed: true, isTrimming: false))
        func shows(_ record: CaptureRecord, destination: Bool = true) -> Bool {
            RecordingTrim.menuState(record, saveFolder: folder, hasDestination: destination, isDeleting: false,
                                    isTrimming: false).showsUploadTrimmed
        }
        #expect(!shows(savedAndUploaded))                     // not stale
        #expect(!shows(stale, destination: false))           // no destination
        #expect(!shows(recording(nil, state: .uploaded(url: link, key: "rec.mp4"), located: true, stale: true)))
        #expect(!shows(recording(savedFile, state: .uploaded(url: link, key: "rec.mp4"), located: true, stale: true,
                                 kind: .gif)))
        #expect(!shows(recording(savedFile, state: .uploaded(url: link, key: "rec.mp4"), located: true, stale: true,
                                 kind: .image)))
    }

    @Test func uploadTrimmedIsDisabledWhileUploadingDeletingOrTrimming() {
        let stale = recording(savedFile, state: .uploaded(url: link, key: "rec.mp4"), located: true, stale: true)
        var uploading = stale
        uploading.uploadState = .uploading(fraction: 0.5)
        let whileUploading = RecordingTrim.menuState(uploading, saveFolder: folder, hasDestination: true,
                                                     isDeleting: false, isTrimming: false)
        #expect(whileUploading.showsUploadTrimmed && !whileUploading.canUploadTrimmed && !whileUploading.canTrim)
        let whileDeleting = RecordingTrim.menuState(stale, saveFolder: folder, hasDestination: true,
                                                    isDeleting: true, isTrimming: false)
        #expect(whileDeleting.showsUploadTrimmed && !whileDeleting.canUploadTrimmed && !whileDeleting.canTrim)
        let whileTrimming = RecordingTrim.menuState(stale, saveFolder: folder, hasDestination: true,
                                                    isDeleting: false, isTrimming: true)
        #expect(whileTrimming == RecordingTrim.MenuState(showsTrim: true, canTrim: false, showsUploadTrimmed: true,
                                                         canUploadTrimmed: false, isTrimming: true))
    }

    @Test func menuStateHidesBothForAGIF() {
        let gif = recording(savedFile, state: .uploaded(url: link, key: "rec.gif"), located: true, stale: true, kind: .gif)
        #expect(RecordingTrim.menuState(gif, saveFolder: folder, hasDestination: true, isDeleting: false, isTrimming: false)
                == RecordingTrim.MenuState(showsTrim: false, canTrim: false, showsUploadTrimmed: false,
                                           canUploadTrimmed: false, isTrimming: false))
    }

    // MARK: Write-time checks

    @Test func writePlanRefusesADeletedDeletingOrUploadingRecord() {
        for button in [RecordingTrim.SheetButton.save, .saveAndUpload] {
            #expect(RecordingTrim.writePlan(button, record: nil, saveFolder: folder, isDeleting: false)
                    == .refuse("This capture was deleted."))
            #expect(RecordingTrim.writePlan(button, record: saved, saveFolder: folder, isDeleting: true)
                    == .refuse("This capture is being deleted."))
            let uploading = recording(savedFile, state: .uploading(fraction: 0.1))
            #expect(RecordingTrim.writePlan(button, record: uploading, saveFolder: folder, isDeleting: false)
                    == .refuse("This capture is still uploading."))
        }
    }

    @Test func writePlanForSave() {
        #expect(RecordingTrim.writePlan(.save, record: saved, saveFolder: folder, isDeleting: false)
                == .saveTarget(.saveFolderFile(savedFile, folder: folder)))
        #expect(RecordingTrim.writePlan(.save, record: pending, saveFolder: nil, isDeleting: false)
                == .saveTarget(.pendingFile(pendingFile)))
        // The folder changed in Settings: Save has nothing to write over and says why.
        #expect(RecordingTrim.writePlan(.save, record: saved, saveFolder: nil, isDeleting: false)
                == .refuse(EditorSaveTarget.noFolderReason))
        #expect(RecordingTrim.writePlan(.save, record: uploadOnly, saveFolder: folder, isDeleting: false)
                == .refuse(EditorSaveTarget.noFileReason))
    }

    @Test func writePlanForSaveAndUpload() {
        #expect(RecordingTrim.writePlan(.saveAndUpload, record: savedAndUploaded, saveFolder: folder, isDeleting: false)
                == .saveTarget(.saveFolderFile(savedFile, folder: folder)))
        #expect(RecordingTrim.writePlan(.saveAndUpload, record: pending, saveFolder: folder, isDeleting: false)
                == .saveTarget(.pendingFile(pendingFile)))
        // Nothing to write over: the trimmed file becomes the record's pending file.
        #expect(RecordingTrim.writePlan(.saveAndUpload, record: uploadOnly, saveFolder: folder, isDeleting: false)
                == .newPendingFile)
        #expect(RecordingTrim.writePlan(.saveAndUpload, record: savedAndUploaded, saveFolder: nil, isDeleting: false)
                == .newPendingFile)
    }

    @Test func cancelPlansNoWrite() {
        #expect(RecordingTrim.writePlan(.cancel, record: saved, saveFolder: folder, isDeleting: false) == .refuse(""))
    }

    /// The window opened on an idle record; a Retry then started its upload. Save refuses at write
    /// time, so the file its upload reads is never replaced.
    @Test func aRecordThatStartsUploadingAfterTheWindowOpenedIsRefused() {
        let failed = recording(savedFile, state: .failed(message: "Offline"))
        #expect(RecordingTrim.canTrim(failed, saveFolder: folder, hasDestination: true, isDeleting: false, isTrimming: false))
        var retried = failed
        retried.uploadState = .uploading(fraction: 0)
        for button in [RecordingTrim.SheetButton.save, .saveAndUpload] {
            #expect(RecordingTrim.writePlan(button, record: retried, saveFolder: folder, isDeleting: false)
                    == .refuse(EditorAvailability.uploadingRefusal))
        }
    }

    // MARK: After the put

    @Test func aLiveRecordFinishes() {
        let written = RecordingTrim.trimmedURL(for: UUID())
        for plan in [RecordingTrim.WritePlan.saveTarget(.saveFolderFile(savedFile, folder: folder)),
                     .saveTarget(.pendingFile(pendingFile)), .newPendingFile] {
            #expect(RecordingTrim.afterPut(plan, fileURL: written, recordExists: true) == .finish)
        }
    }

    /// Pruned during the put: the pending file the put wrote goes, as pruning removes pending files;
    /// a save-folder file stays, as pruning leaves save-folder files alone.
    @Test func aRecordPrunedDuringThePutHasItsPendingFileRemovedAndItsSaveFolderFileKept() {
        #expect(RecordingTrim.afterPut(.saveTarget(.pendingFile(pendingFile)), fileURL: pendingFile, recordExists: false)
                == .removePendingFile(pendingFile))
        #expect(RecordingTrim.afterPut(.newPendingFile, fileURL: pendingFile, recordExists: false)
                == .removePendingFile(pendingFile))
        #expect(RecordingTrim.afterPut(.saveTarget(.saveFolderFile(savedFile, folder: folder)), fileURL: savedFile,
                                       recordExists: false) == .keepFile)
    }

    // MARK: The put

    /// A save-folder file is put under the folder's scope and `pending/<id>.mp4` under none; Save and
    /// Upload with nothing to write over moves the file in as a new pending file.
    @Test func thePutHoldsTheSaveFoldersScopeOnlyForASaveFolderFile() {
        #expect(RecordingTrim.putTarget(for: .saveTarget(.saveFolderFile(savedFile, folder: folder)))
                == .replace(savedFile, scope: folder))
        #expect(RecordingTrim.putTarget(for: .saveTarget(.pendingFile(pendingFile))) == .replace(pendingFile, scope: nil))
        #expect(RecordingTrim.putTarget(for: .newPendingFile) == .newPendingFile)
        #expect(RecordingTrim.putTarget(for: .refuse(EditorAvailability.uploadingRefusal)) == nil)
        #expect(RecordingTrim.putTarget(for: .saveTarget(.unavailable(EditorSaveTarget.noFileReason))) == nil)
    }

    /// The put swaps the trimmed file in over the recording, and a put that fails leaves the recording
    /// as it was.
    @Test func thePutReplacesTheRecordingAndAFailedPutLeavesIt() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "TrimPut-\(UUID().uuidString)",
                                                                     directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let recording = folder.appending(path: "Recording.mp4")
        let trimmed = folder.appending(path: "A-trimmed.mp4")
        try Data("full".utf8).write(to: recording)
        try Data("trimmed".utf8).write(to: trimmed)

        try RecordingTrim.putTrimmed(trimmed, over: recording, scope: nil)
        #expect(try Data(contentsOf: recording) == Data("trimmed".utf8))
        #expect(!FileManager.default.fileExists(atPath: trimmed.path(percentEncoded: false)))

        // Nothing to move: the put throws and the recording stays.
        #expect(throws: (any Error).self) { try RecordingTrim.putTrimmed(trimmed, over: recording, scope: nil) }
        #expect(try Data(contentsOf: recording) == Data("trimmed".utf8))
    }

    /// `uploadIsStale` is set before the put for a record with a link, also one kept only in
    /// `priorUpload`, and not again for one already stale, whose flag a failed put must leave set.
    @Test func thePutMarksTheLinkStaleOnlyWhenItSetsTheFlag() {
        #expect(RecordingTrim.putMarksLinkStale(savedAndUploaded))
        #expect(!RecordingTrim.putMarksLinkStale(saved))
        #expect(!RecordingTrim.putMarksLinkStale(pending))
        var stale = savedAndUploaded
        stale.uploadIsStale = true
        #expect(!RecordingTrim.putMarksLinkStale(stale))
        var interrupted = recording(savedFile, state: .failed(message: "Upload was interrupted."), located: true)
        interrupted.priorUpload = PriorUpload(url: link, key: "rec.mp4", location: location, isReplace: true)
        #expect(RecordingTrim.putMarksLinkStale(interrupted))
    }

    @Test func theSheetsResponseChoosesItsButtonByIndex() {
        let buttons: [RecordingTrim.SheetButton] = [.saveAndUpload, .save, .cancel]
        #expect(RecordingTrim.sheetButton(at: 0, of: buttons) == .saveAndUpload)
        #expect(RecordingTrim.sheetButton(at: 1, of: buttons) == .save)
        #expect(RecordingTrim.sheetButton(at: 2, of: buttons) == .cancel)
        // The window closed under the sheet (`NSModalResponse.cancel`, 0, is index -1000), or any
        // other response (`.abort`, -1001, is index -2001).
        #expect(RecordingTrim.sheetButton(at: -1000, of: buttons) == .cancel)
        #expect(RecordingTrim.sheetButton(at: -2001, of: buttons) == .cancel)
        #expect(RecordingTrim.sheetButton(at: 3, of: buttons) == .cancel)
    }

    // MARK: Failure and cleanup

    @Test func aFullDiskReadsDiskFullAndOtherErrorsTheirOwnText() {
        #expect(RecordingTrim.diskFullText == "Disk Full")
        #expect(RecordingTrim.failureText(for: CocoaError(.fileWriteOutOfSpace)) == "Disk Full")
        #expect(RecordingTrim.failureText(for: POSIXError(.ENOSPC)) == "Disk Full")
        #expect(RecordingTrim.failureText(for: AVError(.diskFull)) == "Disk Full")
        let wrapped = NSError(domain: NSCocoaErrorDomain, code: NSFileWriteUnknownError,
                              userInfo: [NSUnderlyingErrorKey: POSIXError(.ENOSPC) as NSError])
        #expect(RecordingTrim.failureText(for: wrapped) == "Disk Full")
        #expect(RecordingTrim.failureText(for: RecordingTrimError.notEnoughSpace) == "Not enough disk space.")
        #expect(RecordingTrim.failureText(for: RecordingTrimError.couldNotRead) == "The recording could not be read.")
        let missing = CocoaError(.fileNoSuchFile)
        #expect(RecordingTrim.failureText(for: missing) == missing.localizedDescription)
    }

    /// Closing a Trim window removes `tmp/Trim/<id>*`: the download, the trimmed file and the muted
    /// copy. Another record's files stay, and a missing folder is nothing to remove.
    @Test func closingAWindowRemovesOnlyItsRecordsWorkFiles() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "TrimClean-\(UUID().uuidString)",
                                                                     directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let (id, other) = (UUID(), UUID())
        let mine = [folder.appending(path: "\(id.uuidString).mp4"), RecordingTrim.trimmedURL(for: id, in: folder),
                    RecordingTrim.mutedURL(for: id, in: folder)]
        let theirs = [folder.appending(path: "\(other.uuidString).mp4"), RecordingTrim.trimmedURL(for: other, in: folder)]
        for file in mine + theirs {
            try Data("x".utf8).write(to: file)
        }

        RecordingTrim.removeWorkFiles(of: id, in: folder)
        let left = try FileManager.default.contentsOfDirectory(atPath: folder.path(percentEncoded: false)).sorted()
        #expect(left == theirs.map(\.lastPathComponent).sorted())

        RecordingTrim.removeWorkFiles(of: id, in: folder.appending(path: "Missing", directoryHint: .isDirectory))
    }

    // MARK: The in-progress marker

    @Test func whileTrimmingEditorAvailabilityRefusesWithTheTrimmingText() {
        for action in [EditorAction.save, .upload, .uploadAsNew] {
            #expect(EditorAvailability.refusal(for: action, record: savedAndUploaded, saveFolder: folder, isDeleting: false,
                                               isTrimming: true) == EditorAvailability.trimmingRefusal)
            #expect(EditorAvailability.refusal(for: action, record: savedAndUploaded, saveFolder: folder, isDeleting: false)
                    == nil)
        }
        for action in [EditorAction.copy, .saveAs] {
            #expect(EditorAvailability.refusal(for: action, record: saved, saveFolder: folder, isDeleting: false,
                                               isTrimming: true) == nil)
        }
        // A deleted or deleting record keeps its own text.
        #expect(EditorAvailability.refusal(for: .upload, record: nil, saveFolder: folder, isDeleting: false, isTrimming: true)
                == EditorAvailability.deletedRefusal)
        #expect(EditorAvailability.refusal(for: .upload, record: saved, saveFolder: folder, isDeleting: true, isTrimming: true)
                == EditorAvailability.deletingRefusal)
    }

    // MARK: Fixtures

    /// A folder of its own for one test's movies.
    func makeFolder() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appending(path: "RecordingTrimTests-\(UUID().uuidString)",
                                                                     directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    func remove(_ folder: URL) {
        try? FileManager.default.removeItem(at: folder)
    }

    func exists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path(percentEncoded: false))
    }

    func contents(of folder: URL) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: folder.path(percentEncoded: false)).sorted()
    }

    func range(_ start: Double, _ end: Double) -> CMTimeRange {
        CMTimeRange(start: t(start), end: t(end))
    }

    /// 320 × 200 at 10 fps with frame `n` a grey of level `64 + 16n mod 128`, a 1 kHz tone over
    /// `tone` (mono at 44.1 kHz unless told otherwise) or no sound, and with `keyframeInterval` a
    /// sync sample every that many frames; `reorders` gives it a recording's frame reordering and
    /// leading edit.
    func movie(in folder: URL, _ name: String = "source.mp4", seconds: Double = 4,
               tone: [ClosedRange<Double>]? = [0...4], keyframeInterval: Int? = nil, reorders: Bool = false,
               sampleRate: Int = 44_100, channels: Int = 1, width: Int = 320, height: Int = 200) async throws -> URL {
        let url = folder.appending(path: name)
        try await VideoFixtures.makeMP4(at: url, width: width, height: height, seconds: seconds, audio: tone != nil,
                                        tone: tone, keyframeInterval: keyframeInterval, reordersFrames: reorders,
                                        sampleRate: sampleRate, channels: channels)
        return url
    }

    /// The time of the first frame between `start` and `end` s with a channel louder than a tenth of
    /// full scale, or with `last` of the last one; nil when none is (the mute tests' timing method).
    func loud(_ audio: MovieSamples.Audio, from start: TimeInterval, to end: TimeInterval,
              last: Bool = false) -> TimeInterval? {
        let first = max(0, Int((start * audio.sampleRate).rounded(.down)))
        let stop = min(audio.samples.count / audio.channels, Int((end * audio.sampleRate).rounded(.up)))
        guard stop > first else { return nil }
        func isLoud(_ frame: Int) -> Bool {
            (0..<audio.channels).contains { abs(Int(audio.samples[frame * audio.channels + $0])) > 3_277 }
        }
        let frame = last ? (first..<stop).reversed().first(where: isLoud) : (first..<stop).first(where: isLoud)
        return frame.map { Double($0) / audio.sampleRate }
    }

    /// Sample frames of the first audio track stored before the media time its edit list starts at,
    /// which only the edit list hides.
    func hiddenAudioFrames(of url: URL) async throws -> Double {
        let start = try #require(try await MovieSamples.mediaStart(of: url, .audio))
        let rate = try #require(try await AVURLAsset(url: url).loadTracks(withMediaType: .audio).first?
            .load(.naturalTimeScale))
        return try await MovieSamples.storedSamples(of: url, .audio).reduce(0) { sum, sample in
            let kept = CMTimeSubtract(CMTimeMinimum(CMTimeAdd(sample.time, sample.duration), start), sample.time)
            return sum + max(0, kept.seconds) * Double(rate)
        }
    }

    /// Sample frames the first audio track stores, whatever its edit list shows.
    func storedAudioFrames(of url: URL) async throws -> Double {
        let rate = try #require(try await AVURLAsset(url: url).loadTracks(withMediaType: .audio).first?
            .load(.naturalTimeScale))
        return try await MovieSamples.storedSamples(of: url, .audio).reduce(0) { $0 + $1.duration.seconds * Double(rate) }
    }

    /// The first video track's edit list as (track start, media start or nil for an empty edit,
    /// track duration), in seconds.
    func videoEdits(of url: URL) async throws -> [(Double, Double?, Double)] {
        let track = try #require(try await AVURLAsset(url: url).loadTracks(withMediaType: .video).first)
        return try await track.load(.segments).map { segment in
            let mapping = segment.timeMapping
            return (mapping.target.start.seconds, segment.isEmpty ? nil : mapping.source.start.seconds,
                    mapping.target.duration.seconds)
        }
    }

    /// The fixture's options: `keyframeInterval` puts a sync sample every 2 s at 10 fps, with frame
    /// reordering off; with `reordersFrames` the video's first sample is at media time 0.2 s, shown at
    /// track time 0, as in `SCRecordingOutput`'s recordings (Probes, Trim re-encode, as probed).
    @Test(arguments: [false, true])
    func aKeyframeIntervalFixtureHasASyncSampleEveryInterval(reorders: Bool) async throws {
        let folder = try makeFolder()
        defer { remove(folder) }
        let url = try await movie(in: folder, seconds: 5, tone: nil, keyframeInterval: 20, reorders: reorders)
        let samples = try await MovieSamples.storedSamples(of: url, .video)
        #expect(samples.count == 50)
        let start = try #require(try await MovieSamples.mediaStart(of: url, .video))
        #expect(abs(start.seconds - (reorders ? 0.2 : 0)) < 0.001)
        // In track time.
        let syncTimes = samples.filter(\.isSync).map { (($0.time - start).seconds * 10).rounded() / 10 }.sorted()
        #expect(syncTimes == [0, 2, 4])
        let inDecodeOrder = samples.map(\.time)
        #expect((inDecodeOrder == inDecodeOrder.sorted()) == !reorders)
    }

    // MARK: The method

    @Test func mediaTimeMapsThroughTheSegmentHoldingTheTime() {
        let edit = CMTimeMapping(source: CMTimeRange(start: t(0.2), duration: t(4)),
                                 target: CMTimeRange(start: .zero, duration: t(4)))
        #expect(RecordingTrim.mediaTime(of: .zero, through: [edit]) == t(0.2))
        #expect(RecordingTrim.mediaTime(of: t(2), through: [edit]) == t(2.2))
        // Outside every segment, and not a time.
        #expect(RecordingTrim.mediaTime(of: t(4), through: [edit]) == nil)
        #expect(RecordingTrim.mediaTime(of: t(-0.1), through: [edit]) == nil)
        #expect(RecordingTrim.mediaTime(of: .invalid, through: [edit]) == nil)
        // An empty edit, then a second of track time showing two of media.
        let empty = CMTimeMapping(source: .invalid, target: CMTimeRange(start: .zero, duration: t(1)))
        let fast = CMTimeMapping(source: CMTimeRange(start: t(3), duration: t(2)),
                                 target: CMTimeRange(start: t(1), duration: t(1)))
        #expect(RecordingTrim.mediaTime(of: t(0.5), through: [empty, fast]) == nil)
        #expect(RecordingTrim.mediaTime(of: t(1.5), through: [empty, fast]) == t(4))
    }

    /// Sync samples at 0, 2 and 4 s (frames 0, 20 and 40). A start inside a sync sample's frame is
    /// on it (0, 2.0, 2.05 and 4.0); inside the next two frames (2.15, 2.25), and between keyframes
    /// (1.0, 3.95), it is not. With the reordered fixture's edit to media time 0.2 s, a cursor read at
    /// the start unmapped answers 0, 2.0, 2.05, 2.25 and 4.0 wrongly: at 2.25 it would read the
    /// keyframe while frame 22 is shown, and a passthrough would keep the keyframe's earlier frames.
    @Test(arguments: [false, true])
    func startsOnSyncSampleReadsTheSampleShownAtTheStart(reorders: Bool) async throws {
        let folder = try makeFolder()
        defer { remove(folder) }
        let url = try await movie(in: folder, seconds: 5, tone: nil, keyframeInterval: 20, reorders: reorders)
        let answers: [(Double, Bool)] = [(0, true), (2.0, true), (2.05, true), (4.0, true),
                                         (2.15, false), (2.25, false), (1.0, false), (3.95, false)]
        for (start, expected) in answers {
            #expect(try await RecordingTrim.startsOnSyncSample(url, at: t(start)) == expected, "at \(start) s")
        }
    }

    /// A file with no video track has nothing to trim: `couldNotRead`. A start in an empty edit of the
    /// video track shows no sample, so it is not on a sync sample (an empty edit's source has no
    /// numeric start, which `mediaTime` refuses); after the edit, track time maps to media time 1 s
    /// earlier, so 1.0 and 3.0 s are the keyframes at 0 and 2 s, and 2.0 s is frame 10.
    @Test func startsOnSyncSampleWithNoVideoTrackOrInAnEmptyEdit() async throws {
        let folder = try makeFolder()
        defer { remove(folder) }
        let source = try await movie(in: folder, keyframeInterval: 20)
        let soundOnly = AVMutableMovie(url: source, options: nil)
        let picture = try #require(try await soundOnly.load(.tracks).first { $0.mediaType == .video })
        soundOnly.removeTrack(picture)
        let noVideo = folder.appending(path: "sound.mov")
        try soundOnly.writeHeader(to: noVideo, fileType: .mov, options: .addMovieHeaderToDestination)
        await #expect(throws: RecordingTrimError.couldNotRead) {
            try await RecordingTrim.startsOnSyncSample(noVideo, at: .zero)
        }

        let edited = AVMutableMovie(url: source, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])
        let video = try #require(try await edited.load(.tracks).first { $0.mediaType == .video })
        video.insertEmptyTimeRange(CMTimeRange(start: .zero, duration: t(1)))
        let empty = folder.appending(path: "empty.mov")
        try edited.writeHeader(to: empty, fileType: .mov, options: .addMovieHeaderToDestination)
        let edits = try await videoEdits(of: empty)
        #expect(edits.count == 2 && edits.first?.1 == nil)
        #expect(try await RecordingTrim.startsOnSyncSample(empty, at: t(0.5)) == false)
        #expect(try await RecordingTrim.startsOnSyncSample(empty, at: t(1.0)))
        #expect(try await RecordingTrim.startsOnSyncSample(empty, at: t(2.0)) == false)
        #expect(try await RecordingTrim.startsOnSyncSample(empty, at: t(3.0)))
    }

    // MARK: The export

    /// The plan's `export` item for each method: the requested duration within 0.05 s, the audio
    /// track kept, `output`'s missing folder made, and the source as it was.
    @Test(arguments: [RecordingTrim.TrimMethod.passthrough, .reencode])
    func exportWritesTheRangeIntoAFolderItMakes(method: RecordingTrim.TrimMethod) async throws {
        let folder = try makeFolder()
        defer { remove(folder) }
        let source = try await movie(in: folder)
        let before = try Data(contentsOf: source)
        let output = folder.appending(path: "Trim/deeper/trimmed.mp4")
        try await RecordingTrim.export(source, range: range(1.0, 3.0), method: method, to: output, progress: { _ in })
        #expect(abs(try await MovieSamples.duration(of: output) - 2) <= 0.05)
        #expect(try await MovieSamples.trackCount(of: output, .audio) == 1)
        #expect(try await MovieSamples.trackCount(of: output, .video) == 1)
        #expect(try Data(contentsOf: source) == before)
    }

    /// A re-encode from 1.05 s, inside frame 10, of a recording-shaped source (reordered frames and a
    /// leading edit): the file stores frame 10 at 0, then frames 11 to 29 at their times minus the
    /// start, and nothing from before; its first frame is frame 10's grey (96), not frame 9's (80),
    /// frame 11's (112) or the keyframe's (64); its size is the source's and its length the range's.
    /// A passthrough from the same start stores frames from before it, hidden by the edit list: the
    /// keyframe and those that decode from it (7 here).
    @Test func aReencodeStoresOnlyTheFramesFromTheStart() async throws {
        let folder = try makeFolder()
        defer { remove(folder) }
        let source = try await movie(in: folder, keyframeInterval: 20, reorders: true)
        let output = folder.appending(path: "trimmed.mp4")
        try await RecordingTrim.export(source, range: range(1.05, 3.0), method: .reencode, to: output, progress: { _ in })

        let start = try #require(try await MovieSamples.mediaStart(of: output, .video))
        let stored = try await MovieSamples.storedSamples(of: output, .video)
        let expected = [0.0] + (11..<30).map { Double($0) / 10 - 1.05 }
        #expect(stored.count == expected.count)
        for (sample, time) in zip(stored, expected) {
            #expect(abs((sample.time - start).seconds - time) < 0.001, "a frame at \((sample.time - start).seconds) s")
        }
        #expect(stored.allSatisfy { $0.time >= start })
        // One edit, from track time 0 for the range's length: the frames are on the track's timeline
        // where the times above say, with no empty edit before them.
        let edits = try await videoEdits(of: output)
        #expect(edits.count == 1)
        #expect(edits.first?.0 == 0 && edits.first?.1 != nil)
        #expect(abs((edits.first?.2 ?? 0) - 1.95) < 0.001)
        let level = try #require(try await MovieSamples.firstFrameLevel(of: output))
        #expect(abs(level - 96) <= 6, "the first frame's level is \(level)")
        let size = try #require(try await MovieSamples.videoSize(of: output))
        #expect(size.width == 320 && size.height == 200)
        #expect(abs(try await MovieSamples.duration(of: output) - 1.95) <= 0.1)

        let passthrough = folder.appending(path: "passthrough.mp4")
        try await RecordingTrim.export(source, range: range(1.05, 3.0), method: .passthrough, to: passthrough,
                                       progress: { _ in })
        let kept = try #require(try await MovieSamples.mediaStart(of: passthrough, .video))
        #expect(try await MovieSamples.storedSamples(of: passthrough, .video).filter { $0.time < kept }.isEmpty == false)
    }

    /// The source's size above 3840×2160, which `HighestQuality` scaled down (Probes).
    @Test func aReencodeKeepsTheSourcesSizeAbove3840By2160() async throws {
        let folder = try makeFolder()
        defer { remove(folder) }
        let source = try await movie(in: folder, seconds: 1, tone: nil, width: 4096, height: 2304)
        let output = folder.appending(path: "trimmed.mp4")
        try await RecordingTrim.export(source, range: range(0.25, 0.95), method: .reencode, to: output, progress: { _ in })
        let size = try #require(try await MovieSamples.videoSize(of: output))
        #expect(size.width == 4096 && size.height == 2304)
        #expect(abs(try await MovieSamples.duration(of: output) - 0.7) <= 0.1)
        // Frame 2, shown at the start, then frames 3 to 9.
        #expect(try await MovieSamples.storedSamples(of: output, .video).count == 8)
    }

    /// A format description as a recording's video track carries it: 2940×1912 H.264 with
    /// `extensions`.
    func videoFormat(_ extensions: [String: Any]) throws -> CMFormatDescription {
        var format: CMFormatDescription?
        let status = CMVideoFormatDescriptionCreate(allocator: nil, codecType: kCMVideoCodecType_H264, width: 2940,
                                                    height: 1912, extensions: extensions as CFDictionary,
                                                    formatDescriptionOut: &format)
        #expect(status == noErr)
        return try #require(format)
    }

    /// ITU-R 709 for all three, as every recording probed carries.
    let rec709: [String: Any] = [
        kCMFormatDescriptionExtension_ColorPrimaries as String: kCMFormatDescriptionColorPrimaries_ITU_R_709_2,
        kCMFormatDescriptionExtension_TransferFunction as String: kCMFormatDescriptionTransferFunction_ITU_R_709_2,
        kCMFormatDescriptionExtension_YCbCrMatrix as String: kCMFormatDescriptionYCbCrMatrix_ITU_R_709_2,
    ]

    /// The writer's settings (design, `.reencode`): H.264 High at the format's encoded size, the bit
    /// rate when known, a sync frame at least every 2 s and no reordering; first with the format's
    /// colour primaries, transfer function and YCbCr matrix when it carries all three, then without
    /// them; only without them when one is missing.
    @Test func videoSettingsCarryTheSourcesColourFirstWhenItHasAllThree() throws {
        let settings = RecordingTrim.videoSettings(for: try videoFormat(rec709), bitRate: 8_000_000)
        #expect(settings.count == 2)
        let colour = try #require(settings.first?[AVVideoColorPropertiesKey] as? [String: String])
        #expect(colour == [AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
                           AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
                           AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2])
        #expect(settings.last?[AVVideoColorPropertiesKey] == nil)
        for each in settings {
            #expect(each[AVVideoCodecKey] as? AVVideoCodecType == .h264)
            #expect(each[AVVideoWidthKey] as? Int == 2940 && each[AVVideoHeightKey] as? Int == 1912)
            let compression = try #require(each[AVVideoCompressionPropertiesKey] as? [String: Any])
            #expect(compression[AVVideoProfileLevelKey] as? String == AVVideoProfileLevelH264HighAutoLevel)
            #expect(compression[AVVideoAverageBitRateKey] as? Int == 8_000_000)
            #expect(compression[AVVideoMaxKeyFrameIntervalDurationKey] as? Int == 2)
            #expect(compression[AVVideoAllowFrameReorderingKey] as? Bool == false)
        }
        var partial = rec709
        partial[kCMFormatDescriptionExtension_YCbCrMatrix as String] = nil
        let plain = RecordingTrim.videoSettings(for: try videoFormat(partial), bitRate: nil)
        #expect(plain.count == 1)
        #expect(plain.first?[AVVideoColorPropertiesKey] == nil)
        let compression = try #require(plain.first?[AVVideoCompressionPropertiesKey] as? [String: Any])
        #expect(compression[AVVideoAverageBitRateKey] == nil)
    }

    /// The writer input takes the first settings the writer can apply: the source's colour, or for a
    /// writer that cannot apply it none, with the track's transform either way; and is not made when
    /// the writer can apply neither.
    @Test func theVideoInputTakesTheFirstSettingsTheWriterAppliesWithTheTransform() throws {
        let format = try videoFormat(rec709)
        let quarterTurn = CGAffineTransform(rotationAngle: .pi / 2)
        let coloured = try #require(RecordingTrim.videoInput(for: format, bitRate: nil, transform: quarterTurn,
                                                             canApply: { _ in true }))
        #expect(coloured.outputSettings?[AVVideoColorPropertiesKey] != nil)
        #expect(coloured.transform == quarterTurn)
        #expect(!coloured.expectsMediaDataInRealTime)
        let plain = try #require(RecordingTrim.videoInput(for: format, bitRate: nil, transform: quarterTurn,
                                                          canApply: { $0[AVVideoColorPropertiesKey] == nil }))
        #expect(plain.outputSettings?[AVVideoColorPropertiesKey] == nil)
        #expect(plain.outputSettings?[AVVideoWidthKey] as? Int == 2940)
        #expect(plain.transform == quarterTurn)
        #expect(RecordingTrim.videoInput(for: format, bitRate: nil, transform: .identity, canApply: { _ in false }) == nil)
    }

    /// The track's estimated data rate, or its sample data over its duration when that is 0 (design,
    /// `.reencode`); none when neither is known, which leaves the encoder its own.
    @Test func averageBitRateFallsBackToTheSampleDataOverTheDuration() {
        #expect(RecordingTrim.averageBitRate(estimated: 6_000_000, bytes: 1_000_000, over: t(2)) == 6_000_000)
        #expect(RecordingTrim.averageBitRate(estimated: 0, bytes: 1_000_000, over: t(2)) == 4_000_000)
        #expect(RecordingTrim.averageBitRate(estimated: .nan, bytes: 1_000_000, over: t(2)) == 4_000_000)
        #expect(RecordingTrim.averageBitRate(estimated: 0, bytes: 0, over: t(2)) == nil)
        #expect(RecordingTrim.averageBitRate(estimated: 0, bytes: 1_000_000, over: .zero) == nil)
        #expect(RecordingTrim.averageBitRate(estimated: 0, bytes: 1_000_000, over: .invalid) == nil)
    }

    /// A decoded buffer of 16-bit mono at 48 kHz, `count` frames from frame `first`, each frame's
    /// value its own number.
    func pcmBuffer(at first: Int, count: Int) throws -> ReadySample {
        let description = AudioStreamBasicDescription(mSampleRate: 48_000, mFormatID: kAudioFormatLinearPCM,
                                                      mFormatFlags: kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked,
                                                      mBytesPerPacket: 2, mFramesPerPacket: 1, mBytesPerFrame: 2,
                                                      mChannelsPerFrame: 1, mBitsPerChannel: 16, mReserved: 0)
        let format = try CMAudioFormatDescription(audioStreamBasicDescription: description)
        let values = (first..<first + count).map { Int16(truncatingIfNeeded: $0) }
        let block = try CMBlockBuffer(length: count * 2, flags: .assureMemoryNow)
        try block.withUnsafeMutableBytes { bytes in
            values.withUnsafeBytes { bytes.copyMemory(from: $0) }
        }
        let buffer = try CMSampleBuffer(dataBuffer: block, formatDescription: format, numSamples: count,
                                        presentationTimeStamp: CMTime(value: CMTimeValue(first), timescale: 48_000),
                                        packetDescriptions: [])
        // A new buffer over a new block: nothing else holds it.
        nonisolated(unsafe) let made = buffer
        return ReadySample(unsafeBuffer: made)
    }

    /// A buffer's first frame, in frames at 48 kHz, and its values.
    func frames(of sample: ReadySample) throws -> (start: Int64, values: [Int16]) {
        try sample.withUnsafeSampleBuffer { buffer in
            let data = try #require(buffer.dataBuffer)
            let values = try data.withContiguousStorage { bytes in Array(bytes.bindMemory(to: Int16.self)) }
            return (buffer.presentationTimeStamp.convertScale(48_000, method: .default).value, values)
        }
    }

    /// `cut` keeps a decoded buffer's frames inside the range, moved back by its start (Decided
    /// 2026-10-24, 4): a buffer that straddles the end gives only the frames before it, whatever the
    /// reader's time range does; one that straddles the start only those from it; one inside all of
    /// them; one outside none.
    @Test func cutKeepsOnlyTheRangesFramesOfABuffer() throws {
        let range = 48_000..<96_000
        let end = try #require(try RecordingTrim.cut(try pcmBuffer(at: 95_000, count: 2_048), to: range, rate: 48_000))
        let atEnd = try frames(of: end)
        #expect(atEnd.start == 47_000)
        #expect(atEnd.values == (95_000..<96_000).map { Int16(truncatingIfNeeded: $0) })
        let start = try #require(try RecordingTrim.cut(try pcmBuffer(at: 47_000, count: 2_048), to: range, rate: 48_000))
        let atStart = try frames(of: start)
        #expect(atStart.start == 0)
        #expect(atStart.values == (48_000..<49_048).map { Int16(truncatingIfNeeded: $0) })
        let inside = try #require(try RecordingTrim.cut(try pcmBuffer(at: 60_000, count: 1_024), to: range, rate: 48_000))
        #expect(try frames(of: inside).start == 12_000)
        #expect(try frames(of: inside).values.count == 1_024)
        #expect(try RecordingTrim.cut(try pcmBuffer(at: 96_000, count: 1_024), to: range, rate: 48_000) == nil)
        #expect(try RecordingTrim.cut(try pcmBuffer(at: 40_000, count: 1_024), to: range, rate: 48_000) == nil)
    }

    /// `SCRecordingOutput` writes a frame only when the screen changes, so a frame can be shown for
    /// seconds. A re-encode from 0.15 s to 3.0 s of frames at 0, 0.1, 0.2, 1.0 and 3.9 s writes the
    /// frames at 0.1 (shown at the start), 0.2 and 1.0 s, and the last is held to the range's end, not
    /// for the gap before it. With sound, which runs to the end on its own, the writer does not hold
    /// the last frame by itself (Probes, `Trim export, as built`).
    @Test func aReencodeHoldsItsLastFrameToTheRangesEnd() async throws {
        let folder = try makeFolder()
        defer { remove(folder) }
        let source = folder.appending(path: "still.mp4")
        try await VideoFixtures.makeMP4(at: source, width: 320, height: 200, seconds: 4, audio: true,
                                        frameTimes: [0, 0.1, 0.2, 1.0, 3.9], tone: [0...4])
        let output = folder.appending(path: "trimmed.mp4")
        try await RecordingTrim.export(source, range: range(0.15, 3.0), method: .reencode, to: output, progress: { _ in })
        #expect(try await MovieSamples.storedSamples(of: output, .video).map { ($0.time.seconds * 100).rounded() / 100 }
            == [0, 0.05, 0.85])
        let edits = try await videoEdits(of: output)
        #expect(edits.count == 1)
        #expect(abs((edits.first?.2 ?? 0) - 2.85) < 0.001)
        #expect(abs(try await MovieSamples.duration(of: output) - 2.85) < 0.001)
    }

    /// A range that no frame of the video track shows (past its last sample) gives no file with
    /// sound and no picture: the re-encode throws and leaves nothing.
    @Test func aReencodeWithNoFrameToShowThrowsAndLeavesNoOutput() async throws {
        let folder = try makeFolder()
        defer { remove(folder) }
        let source = folder.appending(path: "short.mp4")
        try await VideoFixtures.makeMP4(at: source, width: 320, height: 200, seconds: 4, audio: true,
                                        frameTimes: [0, 0.1, 0.2, 1.0], tone: [0...4])
        let video = try #require(try await AVURLAsset(url: source).loadTracks(withMediaType: .video).first)
        #expect(try await video.load(.timeRange).end.seconds < 1.5)
        let output = folder.appending(path: "trimmed.mp4")
        await #expect(throws: RecordingTrimError.couldNotRead) {
            try await RecordingTrim.export(source, range: range(1.5, 3.5), method: .reencode, to: output, progress: { _ in })
        }
        #expect(!exists(output))
    }

    /// The sound starts at the start and ends at the end (Decided 2026-10-24, 4): exactly the range's
    /// frames, and each edge of the tone, the cut ones included, within 1 ms of the source's.
    @Test(arguments: [(44_100, 1), (48_000, 2)])
    func aReencodesSoundStartsAndEndsWithTheRange(sampleRate: Int, channels: Int) async throws {
        let folder = try makeFolder()
        defer { remove(folder) }
        let source = try await movie(in: folder, tone: [0.5...1.5, 2.0...3.5], sampleRate: sampleRate, channels: channels)
        let output = folder.appending(path: "trimmed.mp4")
        try await RecordingTrim.export(source, range: range(1.0, 3.0), method: .reencode, to: output, progress: { _ in })
        let before = try #require(try await MovieSamples.audio(of: source))
        let after = try #require(try await MovieSamples.audio(of: output))
        #expect(after.sampleRate == Double(sampleRate))
        #expect(after.channels == channels)
        #expect(after.samples.count / channels == 2 * sampleRate)

        // Source seconds, output seconds, and whether the edge is a tone's last frame.
        let edges: [(ClosedRange<Double>, ClosedRange<Double>, Bool)] = [
            (1.0...1.1, 0.0...0.1, false), (1.4...1.6, 0.4...0.6, true),
            (1.9...2.1, 0.9...1.1, false), (2.9...3.0, 1.9...2.0, true),
        ]
        for (was, now, last) in edges {
            let sourceEdge = try #require(loud(before, from: was.lowerBound, to: was.upperBound, last: last))
            let outputEdge = try #require(loud(after, from: now.lowerBound, to: now.upperBound, last: last))
            #expect(abs(outputEdge - (sourceEdge - 1.0)) < 0.001, "the edge at \(sourceEdge) s is at \(outputEdge) s")
        }
        #expect(after.peak(from: 0.55, to: 0.95) < 0.01)
        // Stored, the sound is the AAC encoder's priming (2,112 frames), the range's frames and under a
        // packet of padding: nothing from before the start or after the end hides behind the edit list.
        // 2,112 is the encoder delay of macOS's AAC encoder, not Trim's: an OS change to it fails these
        // two lines with nothing changed in Trim.
        #expect(try await hiddenAudioFrames(of: output) == 2_112)
        let padding = try await storedAudioFrames(of: output) - 2_112 - Double(2 * sampleRate)
        #expect(padding >= 0 && padding < 1_024, "\(padding) frames after the end")
    }

    /// A tone that ends 50 ms before the start (the AAC smear's margin) is nowhere in the output:
    /// not in the sound it plays, nor in the packets it stores, which the edit list could hide.
    @Test func nothingOfAToneThatEndsBeforeTheStartIsInAReencode() async throws {
        let folder = try makeFolder()
        defer { remove(folder) }
        let source = try await movie(in: folder, tone: [0.2...0.95, 1.6...2.5], sampleRate: 48_000, channels: 2)
        let output = folder.appending(path: "trimmed.mp4")
        try await RecordingTrim.export(source, range: range(1.0, 3.0), method: .reencode, to: output, progress: { _ in })
        let played = try #require(try await MovieSamples.audio(of: output))
        #expect(played.peak(from: 0, to: 0.55) < 0.01)
        #expect(played.peak(from: 0.65, to: 1.45) > 0.5)
        let stored = try #require(try await MovieSamples.storedAudio(of: output))
        let start = try #require(try await MovieSamples.mediaStart(of: output, .audio))
        #expect(stored.peak(from: 0, to: start.seconds + 0.55) < 0.01)
        #expect(stored.peak(from: start.seconds + 0.65, to: start.seconds + 1.45) > 0.5)
    }

    @Test func aReencodeOfASourceWithNoSoundHasNone() async throws {
        let folder = try makeFolder()
        defer { remove(folder) }
        let source = try await movie(in: folder, tone: nil)
        let output = folder.appending(path: "trimmed.mp4")
        try await RecordingTrim.export(source, range: range(1.0, 3.0), method: .reencode, to: output, progress: { _ in })
        #expect(try await MovieSamples.trackCount(of: output, .audio) == 0)
        #expect(try await MovieSamples.trackCount(of: output, .video) == 1)
        #expect(abs(try await MovieSamples.duration(of: output) - 2) <= 0.1)
    }

    /// From a keyframe of a recording-shaped source: no video sample before the start, and at most
    /// two AAC packets (2,048 sample frames) of sound before it, hidden by the edit list: the one
    /// exception to Decided 2026-10-23, 3. The stored sound shows those hidden frames are the tone.
    @Test func aPassthroughFromASyncSampleKeepsNoEarlierFrameAndAtMostTwoPacketsOfSound() async throws {
        let folder = try makeFolder()
        defer { remove(folder) }
        let source = try await movie(in: folder, keyframeInterval: 10, reorders: true, sampleRate: 48_000, channels: 2)
        #expect(try await RecordingTrim.startsOnSyncSample(source, at: t(2.0)))
        let output = folder.appending(path: "trimmed.mp4")
        try await RecordingTrim.export(source, range: range(2.0, 4.0), method: .passthrough, to: output, progress: { _ in })

        let start = try #require(try await MovieSamples.mediaStart(of: output, .video))
        let stored = try await MovieSamples.storedSamples(of: output, .video)
        #expect(stored.filter { $0.time < start }.isEmpty)
        #expect(stored.count == 20)
        let hidden = try await hiddenAudioFrames(of: output)
        #expect(hidden <= 2_048)
        // Stored, from its first packet, hidden or not, the sound is the tone.
        let sound = try #require(try await MovieSamples.storedAudio(of: output))
        #expect(sound.peak(from: 0, to: (hidden + 2_048) / 48_000) > 0.4)
    }

    @Test func aReencodesProgressRisesAndEndsWithExactlyOneOne() async throws {
        let folder = try makeFolder()
        defer { remove(folder) }
        let source = try await movie(in: folder, seconds: 20, tone: [0...20])
        let readings = Mutex<[Double]>([])
        try await RecordingTrim.export(source, range: range(1.0, 19.0), method: .reencode,
                                       to: folder.appending(path: "trimmed.mp4"),
                                       progress: { value in readings.withLock { $0.append(value) } })
        let values = readings.withLock { $0 }
        #expect(values.last == 1)
        #expect(values.filter { $0 == 1 }.count == 1)
        #expect(values.count >= 2)
        #expect(values.allSatisfy { $0 > 0 && $0 <= 1 })
        #expect(zip(values, values.dropFirst()).allSatisfy { $0 <= $1 }, "\(values)")
    }

    @Test func aPassthroughReportsOnlyOne() async throws {
        let folder = try makeFolder()
        defer { remove(folder) }
        let source = try await movie(in: folder)
        let readings = Mutex<[Double]>([])
        try await RecordingTrim.export(source, range: range(1.0, 3.0), method: .passthrough,
                                       to: folder.appending(path: "trimmed.mp4"),
                                       progress: { value in readings.withLock { $0.append(value) } })
        #expect(readings.withLock { $0 } == [1])
    }

    /// A cancel before anything is read.
    @Test func aCancelledReencodeThrowsAndLeavesNoOutput() async throws {
        let folder = try makeFolder()
        defer { remove(folder) }
        let source = try await movie(in: folder)
        let output = folder.appending(path: "trimmed.mp4")
        try Data("stale".utf8).write(to: output)
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            try await RecordingTrim.export(source, range: range(1.0, 3.0), method: .reencode, to: output, progress: { _ in })
        }
        let result = await task.result
        #expect(throws: CancellationError.self) { try result.get() }
        #expect(!exists(output))
        #expect(exists(source))
    }

    /// `Stop` while the re-encode writes: cancelled from inside its first progress reading. The
    /// readings are taken once the export has ended, so one that throws before any reading fails at
    /// once rather than at the suite's time limit.
    @Test func aCancelWhileAReencodeWritesThrowsAndLeavesNoOutput() async throws {
        let folder = try makeFolder()
        defer { remove(folder) }
        let source = try await movie(in: folder, seconds: 20, tone: [0...20])
        let before = try Data(contentsOf: source)
        let output = folder.appending(path: "trimmed.mp4")
        let (result, values) = await stopAtFirstReading { progress in
            try await RecordingTrim.export(source, range: range(1.0, 19.0), method: .reencode, to: output,
                                           progress: progress)
        }
        #expect(throws: CancellationError.self) { try result.get() }
        #expect(!values.isEmpty && values.allSatisfy { $0 < 1 }, "\(values)")
        #expect(!exists(output))
        #expect(try Data(contentsOf: source) == before)
    }

    /// Runs `export` in a task that its first progress reading cancels, as `Stop` does, and gives its
    /// result and the readings. The task is held in a `Mutex` the progress closure reads, and the
    /// readings' stream is finished once the result is in, so nothing waits on a reading that never
    /// comes.
    func stopAtFirstReading(_ export: @escaping @Sendable (@escaping @Sendable (Double) -> Void) async throws -> Void)
        async -> (Result<Void, any Error>, [Double]) {
        let running = Mutex<Task<Void, any Error>?>(nil)
        let (readings, reading) = AsyncStream<Double>.makeStream()
        let task = Task {
            try await export { value in
                reading.yield(value)
                running.withLock { $0?.cancel() }
            }
        }
        running.withLock { $0 = task }
        let result = await task.result
        reading.finish()
        var values: [Double] = []
        for await value in readings {
            values.append(value)
        }
        return (result, values)
    }

    /// Sound whose decode fails partway, as in the mute tests: an edit at another rate from 2 s. The
    /// re-encode throws the decode's own error, `RecordingMuteError.couldNotRead` from
    /// `AudioDecoder.decode` while the tracks run (its setup takes this AAC track, and setup's own
    /// refusals are `RecordingTrimError`s or AVFoundation's), at once rather than wait on the video,
    /// and leaves nothing.
    @Test func aReencodeThatFailsPartwayThrowsAndLeavesNoOutput() async throws {
        let folder = try makeFolder()
        defer { remove(folder) }
        let source = try await movie(in: folder)
        let file = folder.appending(path: "speed.mov")
        try await VideoFixtures.makeAudioSpeedChange(of: source, over: 2.0...3.0, lasting: 0.5, at: file)
        let track = try #require(try await AVURLAsset(url: file).loadTracks(withMediaType: .audio).first)
        let format = try #require(try await track.load(.formatDescriptions).first)
        _ = try AudioDecoder(format: format, end: try await track.load(.timeRange).end)
        let output = folder.appending(path: "trimmed.mp4")
        let error = await #expect(throws: RecordingMuteError.self) {
            try await RecordingTrim.export(file, range: range(1.0, 3.5), method: .reencode, to: output, progress: { _ in })
        }
        if case .couldNotRead? = error {} else { Issue.record("\(String(describing: error))") }
        #expect(!exists(output))
        #expect(exists(file))
    }

    /// Never the recording: an export onto its own source refuses before it clears anything, and so
    /// does Save's export of a source at its own working paths.
    @Test func anExportOverItsSourceIsRefusedAndTheSourceKept() async throws {
        let folder = try makeFolder()
        defer { remove(folder) }
        let source = try await movie(in: folder)
        let before = try Data(contentsOf: source)
        for method in [RecordingTrim.TrimMethod.passthrough, .reencode] {
            await #expect(throws: RecordingTrimError.couldNotWrite) {
                try await RecordingTrim.export(source, range: range(1.0, 3.0), method: method, to: source, progress: { _ in })
            }
        }
        #expect(try Data(contentsOf: source) == before)
        let id = UUID()
        for working in [RecordingTrim.mutedURL(for: id, in: folder), RecordingTrim.trimmedURL(for: id, in: folder)] {
            try FileManager.default.copyItem(at: source, to: working)
            await #expect(throws: RecordingTrimError.couldNotWrite) {
                try await RecordingTrim.exportForSave(working, id: id, range: range(1.0, 3.0), method: .reencode,
                                                      unmutedIntervals: [MuteInterval(start: 1, end: 2)],
                                                      directory: folder, freeBytes: { nil }, progress: { _ in })
            }
            #expect(try Data(contentsOf: working) == before)
        }
    }

    /// `isSameFile` reads the file system's identity when both files exist, so a hard link and
    /// another spelling of the path (APFS ignores case) are the source; otherwise the paths, with
    /// symbolic links resolved.
    @Test func isSameFileFollowsTheFileNotItsPath() throws {
        let folder = try makeFolder()
        defer { remove(folder) }
        let file = folder.appending(path: "source.mp4")
        try Data("movie".utf8).write(to: file)
        let other = folder.appending(path: "other.mp4")
        try Data("movie".utf8).write(to: other)
        let link = folder.appending(path: "link.mp4")
        try FileManager.default.linkItem(at: file, to: link)
        let alias = folder.appending(path: "SOURCE.mp4")
        let caseInsensitive = exists(alias)
        let symbolic = folder.appending(path: "symbolic.mp4")
        try FileManager.default.createSymbolicLink(at: symbolic, withDestinationURL: file)

        #expect(RecordingTrim.isSameFile(file, file))
        #expect(RecordingTrim.isSameFile(file, link))
        #expect(RecordingTrim.isSameFile(file, symbolic))
        #expect(RecordingTrim.isSameFile(file, alias) == caseInsensitive)
        #expect(!RecordingTrim.isSameFile(file, other))
        // A file that is not there yet: its path.
        let missing = folder.appending(path: "trimmed.mp4")
        #expect(!RecordingTrim.isSameFile(file, missing))
        #expect(RecordingTrim.isSameFile(missing, folder.appending(path: "./trimmed.mp4")))
    }

    // MARK: The export for Save

    /// A source whose size cannot be read fails closed (design, Disk space): `couldNotRead`, before
    /// the check and before anything is written, even with exactly 1 GB free, which a size taken as
    /// 0 would pass.
    @Test func aSourceWhoseSizeCannotBeReadIsNotTrimmed() async throws {
        let folder = try makeFolder()
        defer { remove(folder) }
        let directory = folder.appending(path: "Trim", directoryHint: .isDirectory)
        let missing = folder.appending(path: "gone.mp4")
        for method in [RecordingTrim.TrimMethod.passthrough, .reencode] {
            await #expect(throws: RecordingTrimError.couldNotRead) {
                try await RecordingTrim.exportForSave(missing, id: UUID(), range: range(1.0, 3.0), method: method,
                                                      unmutedIntervals: [], directory: directory,
                                                      freeBytes: { 1_000_000_000 }, progress: { _ in })
            }
            #expect(try contents(of: directory).isEmpty)
        }
    }

    /// The plan's missing `tmp/Trim` item: after the launch clear, a pending or save-folder source has
    /// downloaded nothing into it. Save's export makes it, with and without the mute step, and leaves
    /// only `<id>-trimmed.mp4` there.
    @Test(arguments: [RecordingTrim.TrimMethod.passthrough, .reencode], [false, true])
    func exportForSaveMakesAMissingFolderAndLeavesOnlyTheTrimmedFile(method: RecordingTrim.TrimMethod,
                                                                     marked: Bool) async throws {
        let folder = try makeFolder()
        defer { remove(folder) }
        let source = try await movie(in: folder)
        let directory = folder.appending(path: "tmp/Trim", directoryHint: .isDirectory)
        let id = UUID()
        let trimmed = try await RecordingTrim.exportForSave(
            source, id: id, range: range(1.0, 3.0), method: method,
            unmutedIntervals: marked ? [MuteInterval(start: 1.5, end: 2.0)] : [], directory: directory,
            freeBytes: { nil }, progress: { _ in })
        #expect(trimmed == RecordingTrim.trimmedURL(for: id, in: directory))
        #expect(try contents(of: directory) == ["\(id.uuidString)-trimmed.mp4"])
        #expect(abs(try await MovieSamples.duration(of: trimmed) - 2) <= 0.05)
    }

    /// Never save muted sound: a marked record is muted before it is trimmed, by either method.
    @Test(arguments: [RecordingTrim.TrimMethod.passthrough, .reencode])
    func aMarkedRecordsTrimHasItsMutedStretchesSilent(method: RecordingTrim.TrimMethod) async throws {
        let folder = try makeFolder()
        defer { remove(folder) }
        let source = try await movie(in: folder)
        let trimmed = try await RecordingTrim.exportForSave(
            source, id: UUID(), range: range(1.0, 3.5), method: method,
            unmutedIntervals: [MuteInterval(start: 1.5, end: 2.5)], directory: folder.appending(path: "Trim"),
            freeBytes: { nil }, progress: { _ in })
        let sound = try #require(try await MovieSamples.audio(of: trimmed))
        // 50 ms at each edge for the AAC smear.
        #expect(sound.peak(from: 0.55, to: 1.45) < 0.01)
        #expect(sound.peak(from: 0.05, to: 0.45) > 0.5)
        #expect(sound.peak(from: 1.55, to: 2.45) > 0.5)
    }

    /// A mute step that fails, a re-encode that fails partway, and a re-encode stopped while it
    /// writes after the mute step: none leaves `<id>-muted.mp4` or `<id>-trimmed.mp4`.
    @Test func aFailedOrStoppedSaveExportLeavesNoWorkingFile() async throws {
        let folder = try makeFolder()
        defer { remove(folder) }
        let source = try await movie(in: folder)
        let speed = folder.appending(path: "speed.mov")
        try await VideoFixtures.makeAudioSpeedChange(of: source, over: 2.0...3.0, lasting: 0.5, at: speed)
        let directory = folder.appending(path: "Trim", directoryHint: .isDirectory)
        for marks in [[MuteInterval(start: 1.5, end: 2.0)], []] {
            await #expect(throws: (any Error).self) {
                try await RecordingTrim.exportForSave(speed, id: UUID(), range: range(1.0, 3.5), method: .reencode,
                                                      unmutedIntervals: marks, directory: directory,
                                                      freeBytes: { nil }, progress: { _ in })
            }
            #expect(try contents(of: directory).isEmpty)
        }

        let long = try await movie(in: folder, "long.mp4", seconds: 20, tone: [0...20])
        let (result, values) = await stopAtFirstReading { progress in
            _ = try await RecordingTrim.exportForSave(long, id: UUID(), range: range(1.0, 19.0), method: .reencode,
                                                      unmutedIntervals: [MuteInterval(start: 5, end: 6)],
                                                      directory: directory, freeBytes: { nil }, progress: progress)
        }
        #expect(throws: CancellationError.self) { try result.get() }
        #expect(!values.isEmpty && values.allSatisfy { $0 < 1 }, "\(values)")
        #expect(try contents(of: directory).isEmpty)
    }

    /// The disk check (design, Disk space; Decided 2026-10-24, 2): the source's size for a
    /// passthrough, twice that for a re-encode, the source's size again with the mute step, plus
    /// 1 GB. One byte short refuses before anything is written; exactly enough writes.
    @Test(arguments: [(RecordingTrim.TrimMethod.passthrough, false, Int64(1)), (.reencode, false, 2),
                      (.passthrough, true, 2), (.reencode, true, 3)])
    func theDiskCheckNeedsTheSourcesSizeTimesItsFactorAndAGigabyte(method: RecordingTrim.TrimMethod, marked: Bool,
                                                                   factor: Int64) async throws {
        let folder = try makeFolder()
        defer { remove(folder) }
        let source = try await movie(in: folder)
        let size = Int64(try #require(FileSizes.byteCount(of: source)))
        #expect(RecordingTrim.bytesNeeded(sourceBytes: size, method: method, mutes: marked) == size * factor)
        let room = size * factor + 1_000_000_000
        let directory = folder.appending(path: "Trim", directoryHint: .isDirectory)
        let marks = marked ? [MuteInterval(start: 1.5, end: 2.0)] : []
        await #expect(throws: RecordingTrimError.notEnoughSpace) {
            try await RecordingTrim.exportForSave(source, id: UUID(), range: range(1.0, 3.0), method: method,
                                                  unmutedIntervals: marks, directory: directory,
                                                  freeBytes: { room - 1 }, progress: { _ in })
        }
        #expect(try contents(of: directory).isEmpty)
        let trimmed = try await RecordingTrim.exportForSave(source, id: UUID(), range: range(1.0, 3.0), method: method,
                                                            unmutedIntervals: marks, directory: directory,
                                                            freeBytes: { room }, progress: { _ in })
        #expect(exists(trimmed))
    }
}
