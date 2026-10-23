import AVFoundation
import Foundation
import Testing
@testable import TidyShot

/// Trim's pure decisions (design, Trim): the range, the source, the sheet, the menu, the write-time
/// plans, what follows a put, and the in-progress marker's refusals. The export, the sync-sample
/// check and the window wait for the trim gate (plan, Gates).
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
        #expect(TrimRefusal.tooShort.message == RecordingTrim.tooShortText)
        #expect(EditorAvailability.trimmingRefusal == "This capture is being trimmed.")
        #expect(CaptureDeletion.trimmingRefusal == "This capture is being trimmed. Delete it when the trim finishes.")
    }

    // MARK: The range

    @Test func rangeKeepsAValidRange() throws {
        let range = try RecordingTrim.range(start: t(1), end: t(3.5), duration: t(10)).get()
        #expect(range == CMTimeRange(start: t(1), end: t(3.5)))
    }

    @Test func rangeReadsAnInvalidTimeAsTheFilesStartOrEnd() throws {
        #expect(try RecordingTrim.range(start: .invalid, end: t(4), duration: t(10)).get()
                == CMTimeRange(start: .zero, end: t(4)))
        #expect(try RecordingTrim.range(start: t(2), end: .invalid, duration: t(10)).get()
                == CMTimeRange(start: t(2), end: t(10)))
        #expect(try RecordingTrim.range(start: .invalid, end: .indefinite, duration: t(10)).get()
                == CMTimeRange(start: .zero, end: t(10)))
    }

    @Test func rangeClampsToTheFile() throws {
        #expect(try RecordingTrim.range(start: t(-1), end: t(12), duration: t(10)).get()
                == CMTimeRange(start: .zero, end: t(10)))
    }

    @Test func rangeRefusesUnderHalfASecond() throws {
        #expect(RecordingTrim.range(start: t(2), end: t(2.4), duration: t(10)) == .failure(.tooShort))
        #expect(RecordingTrim.range(start: t(9.8), end: .invalid, duration: t(10)) == .failure(.tooShort))
        #expect(RecordingTrim.range(start: t(5), end: t(3), duration: t(10)) == .failure(.tooShort))
        #expect(RecordingTrim.range(start: t(11), end: t(12), duration: t(10)) == .failure(.tooShort))
        #expect(try RecordingTrim.range(start: t(2), end: t(2.5), duration: t(10)).get()
                == CMTimeRange(start: t(2), end: t(2.5)))
    }

    // MARK: The source file

    @Test func sourceFollowsEditorInputsOrder() {
        #expect(RecordingTrim.source(for: pending, saveFolder: folder) == .pendingFile(pendingFile))
        #expect(RecordingTrim.source(for: pending, saveFolder: nil) == .pendingFile(pendingFile))
        #expect(RecordingTrim.source(for: saved, saveFolder: folder) == .saveFolderFile(savedFile, folder: folder))
        // A file outside the folder, or with no folder, downloads when it was uploaded.
        let outsideUploaded = recording(outsideFile, state: .uploaded(url: link, key: "rec.mp4"), located: true)
        #expect(RecordingTrim.source(for: outsideUploaded, saveFolder: folder) == .download(key: "rec.mp4", location: location))
        #expect(RecordingTrim.source(for: savedAndUploaded, saveFolder: nil) == .download(key: "rec.mp4", location: location))
        #expect(RecordingTrim.source(for: uploadOnly, saveFolder: folder) == .download(key: "rec.mp4", location: location))
    }

    @Test func sourceIsUnavailableWithEditorInputsTexts() {
        #expect(RecordingTrim.source(for: recording(outsideFile), saveFolder: folder)
                == .unavailable(EditorInput.outsideSaveFolderText))
        #expect(RecordingTrim.source(for: saved, saveFolder: nil) == .unavailable(EditorInput.outsideSaveFolderText))
        #expect(RecordingTrim.source(for: recording(nil), saveFolder: folder) == .unavailable(EditorInput.neverUploadedText))
        let unknown = recording(nil, state: .uploaded(url: link, key: "rec.mp4"))
        #expect(RecordingTrim.source(for: unknown, saveFolder: folder) == .unavailable(EditorInput.unknownLocationText))
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

    /// The sync-sample tests (held with the export) read a 10 fps fixture with a sync sample every
    /// 2 s; this checks the fixture gives one.
    @Test func aKeyframeIntervalFixtureHasASyncSampleEveryInterval() async throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "RecordingTrimTests-\(UUID().uuidString).mp4")
        defer { try? FileManager.default.removeItem(at: url) }
        try await VideoFixtures.makeMP4(at: url, width: 64, height: 64, seconds: 5, audio: false, keyframeInterval: 20)
        let track = try #require(try await AVURLAsset(url: url).loadTracks(withMediaType: .video).first)
        let cursor = try #require(track.makeSampleCursorAtFirstSampleInDecodeOrder())
        var syncTimes: [Double] = []
        var count = 0
        repeat {
            count += 1
            if cursor.currentSampleSyncInfo.sampleIsFullSync.boolValue {
                syncTimes.append(cursor.presentationTimeStamp.seconds)
            }
        } while cursor.stepInDecodeOrder(byCount: 1) == 1
        #expect(count == 50)
        #expect(syncTimes.map { ($0 * 10).rounded() / 10 } == [0, 2, 4])
    }
}
