import Foundation
import Testing
@testable import TidyShot

struct EditorSaveTargetTests {
    let folder = URL(filePath: "/Users/tim/Pictures/TidyShot", directoryHint: .isDirectory)
    let link = URL(string: "https://snap.tky.io/a.png")!
    let location = ObjectLocation(endpoint: "https://s3.us-west-2.amazonaws.com", region: "us-west-2",
                                  bucket: "snap.tky.io", usePathStyle: true)
    let pendingURL = URL(filePath: "/Users/tim/Library/Containers/io.tky.tidyshot/Data/Library/Application Support/TidyShot/pending/A.png")

    /// A capture saved in `folder` (this suite's save folder unless given), in `state`.
    func saved(in folder: URL? = nil, state: CaptureRecord.UploadState = .none, stale: Bool = false) -> CaptureRecord {
        CaptureRecord(fileURL: (folder ?? self.folder).appending(path: "Screenshot 2026-10-20 at 10.00.00.png"),
                      pixelWidth: 200, pixelHeight: 100, appName: nil, uploadState: state, uploadIsStale: stale)
    }

    func actions(_ record: CaptureRecord?, folder: URL? = nil, deleting: Bool = false) -> Set<EditorAction> {
        EditorAvailability.actions(record: record, saveFolder: folder ?? self.folder, isDeleting: deleting)
    }

    @Test func saveFolderFileInsideFolder() throws {
        let record = saved()
        let fileURL = try #require(record.fileURL)
        #expect(EditorSaveTarget.plan(for: record, saveFolder: folder) == .saveFolderFile(fileURL, folder: folder))
        #expect(actions(record).contains(.save))
    }

    @Test func fileOutsideFolderUnavailable() {
        let record = saved(in: URL(filePath: "/Users/tim/Desktop", directoryHint: .isDirectory))
        #expect(EditorSaveTarget.plan(for: record, saveFolder: folder)
                == .unavailable("The file is outside the current save folder, so it is not saved over."))
        // Save stays on: with nothing to write over it opens the save panel (Save As…).
        #expect(actions(record) == [.save, .saveAs, .copy, .upload])
        #expect(EditorSaveCommand.forSave(record: record, saveFolder: folder) == .saveAs)
    }

    @Test func noFolderUnavailable() {
        #expect(EditorSaveTarget.plan(for: saved(), saveFolder: nil)
                == .unavailable("No save folder is set, so the file is not saved over."))
        #expect(EditorAvailability.status(record: saved(), saveFolder: nil, isDeleting: false)
                == "No save folder is set, so the file is not saved over.")
        #expect(EditorSaveCommand.forSave(record: saved(), saveFolder: nil) == .saveAs)
    }

    /// An upload-only capture's file in `pending` needs no save folder.
    @Test func pendingFileIsPendingTarget() {
        let record = CaptureRecord(fileURL: pendingURL, fileIsTemporary: true, pixelWidth: 200, pixelHeight: 100,
                                   appName: nil, uploadState: .failed(message: "offline"))
        #expect(EditorSaveTarget.plan(for: record, saveFolder: folder) == .pendingFile(pendingURL))
        #expect(EditorSaveTarget.plan(for: record, saveFolder: nil) == .pendingFile(pendingURL))
        #expect(actions(record) == [.save, .saveAs, .copy, .upload])
        #expect(EditorSaveCommand.forSave(record: record, saveFolder: nil) == .writeOver)
    }

    @Test func uploadedUploadOnlyWithoutFileUnavailable() {
        let record = CaptureRecord(fileURL: nil, pixelWidth: 200, pixelHeight: 100, appName: nil,
                                   uploadState: .uploaded(url: link, key: "a.png"), objectLocation: location)
        #expect(EditorSaveTarget.plan(for: record, saveFolder: folder)
                == .unavailable("This capture has no local file to save over."))
        // Save opens the save panel instead of writing over a file; the subtitle says why.
        #expect(actions(record) == Set(EditorAction.allCases))
        #expect(EditorAvailability.refusal(for: .save, record: record, saveFolder: folder, isDeleting: false) == nil)
        #expect(EditorSaveCommand.forSave(record: record, saveFolder: folder) == .saveAs)
        #expect(EditorAvailability.status(record: record, saveFolder: folder, isDeleting: false)
                == "This capture has no local file to save over.")
    }

    /// Records uploaded before Phase 3 keep their file in the save folder and have no stored location.
    @Test func prePhaseThreeUploadedWithFileOverwrites() throws {
        let record = saved(state: .uploaded(url: link, key: "a.png"))
        #expect(record.objectLocation == nil)
        let fileURL = try #require(record.fileURL)
        #expect(EditorSaveTarget.plan(for: record, saveFolder: folder) == .saveFolderFile(fileURL, folder: folder))
        #expect(actions(record) == Set(EditorAction.allCases))
        #expect(EditorSaveCommand.forSave(record: record, saveFolder: folder) == .writeOver)
    }

    /// Upload saves over the Save target first, and gives an uploaded upload-only capture a pending file.
    @Test func uploadWritesLocallyWhenASaveTargetExists() {
        let pending = CaptureRecord(fileURL: pendingURL, fileIsTemporary: true, pixelWidth: 200, pixelHeight: 100,
                                    appName: nil, uploadState: .failed(message: "offline"))
        let uploadOnly = CaptureRecord(fileURL: nil, pixelWidth: 200, pixelHeight: 100, appName: nil,
                                       uploadState: .uploaded(url: link, key: "a.png"), objectLocation: location)
        #expect(EditorSaveTarget.uploadWrite(for: saved(), saveFolder: folder) == .saveTarget)
        #expect(EditorSaveTarget.uploadWrite(for: pending, saveFolder: nil) == .saveTarget)
        #expect(EditorSaveTarget.uploadWrite(for: uploadOnly, saveFolder: folder) == .newPendingFile)
    }

    /// A file outside the current folder, or no folder: the original is left where it is and the
    /// edit gets `pending/<id>.png`, so a failed upload keeps it and Retry uploads the edited bytes,
    /// never the unredacted original.
    @Test func uploadOutsideTheSaveFolderGetsAPendingFile() {
        let outside = saved(in: URL(filePath: "/Users/tim/Desktop", directoryHint: .isDirectory))
        #expect(EditorSaveTarget.uploadWrite(for: outside, saveFolder: folder) == .newPendingFile)
        #expect(EditorSaveTarget.uploadWrite(for: saved(), saveFolder: nil) == .newPendingFile)
        #expect(actions(outside).contains(.upload))
    }

    /// Save As… onto the record's own file, when ⌘S could write over it, goes through Save, so
    /// the record, thumbnail and stale flag follow. Any other URL, or a file Save cannot write
    /// over now, is a plain Save As….
    @Test func saveAsOntoTheOwnFileIsASave() throws {
        let record = saved(state: .uploaded(url: link, key: "a.png"))
        let fileURL = try #require(record.fileURL)
        let sameFileSpelledDifferently = folder.appending(path: "sub/../Screenshot 2026-10-20 at 10.00.00.png")
        #expect(EditorSaveTarget.saveAsWritesOverOwnFile(fileURL, record: record, saveFolder: folder, isDeleting: false))
        #expect(EditorSaveTarget.saveAsWritesOverOwnFile(sameFileSpelledDifferently, record: record,
                                                         saveFolder: folder, isDeleting: false))
        let elsewhere = URL(filePath: "/Users/tim/Desktop/Screenshot 2026-10-20 at 10.00.00.png")
        #expect(!EditorSaveTarget.saveAsWritesOverOwnFile(elsewhere, record: record, saveFolder: folder, isDeleting: false))
        // Save cannot write over it now: outside the current folder, deleting, uploading, deleted.
        let otherFolder = URL(filePath: "/Users/tim/Pictures/Other", directoryHint: .isDirectory)
        #expect(!EditorSaveTarget.saveAsWritesOverOwnFile(fileURL, record: record, saveFolder: otherFolder, isDeleting: false))
        #expect(!EditorSaveTarget.saveAsWritesOverOwnFile(fileURL, record: record, saveFolder: folder, isDeleting: true))
        #expect(!EditorSaveTarget.saveAsWritesOverOwnFile(fileURL, record: saved(state: .uploading(fraction: 0.1)),
                                                          saveFolder: folder, isDeleting: false))
        #expect(!EditorSaveTarget.saveAsWritesOverOwnFile(fileURL, record: nil, saveFolder: folder, isDeleting: false))
    }

    @Test func noticeOnlyWhenUploadIsStale() {
        let fresh = saved(state: .uploaded(url: link, key: "a.png"))
        let stale = saved(state: .uploaded(url: link, key: "a.png"), stale: true)
        #expect(EditorSaveTarget.uploadedCopyNotice(for: fresh) == nil)
        #expect(EditorSaveTarget.uploadedCopyNotice(for: stale)
                == "The uploaded copy still shows the original. Upload to replace it.")
        #expect(EditorAvailability.status(record: fresh, saveFolder: folder, isDeleting: false) == nil)
        #expect(EditorAvailability.status(record: stale, saveFolder: folder, isDeleting: false)
                == "The uploaded copy still shows the original. Upload to replace it.")
    }

    @Test func availabilityWhileUploadingIsCopyAndSaveAs() {
        let uploading = saved(state: .uploading(fraction: 0.3))
        #expect(actions(uploading) == [.copy, .saveAs])
        #expect(EditorAvailability.status(record: uploading, saveFolder: folder, isDeleting: false) == "Uploading…")
        #expect(EditorAvailability.refusal(for: .save, record: uploading, saveFolder: folder, isDeleting: false)
                == "This capture is still uploading.")
        #expect(EditorAvailability.refusal(for: .upload, record: uploading, saveFolder: folder, isDeleting: false)
                == "This capture is still uploading.")
    }

    /// A nil record was deleted or pruned.
    @Test func availabilityWhenDeletedIsCopyAndSaveAs() {
        #expect(actions(nil) == [.copy, .saveAs])
        #expect(actions(nil, deleting: true) == [.copy, .saveAs])
        #expect(EditorAvailability.status(record: nil, saveFolder: folder, isDeleting: false)
                == "This capture was deleted. Copy and Save As still work.")
        #expect(EditorAvailability.refusal(for: .save, record: nil, saveFolder: folder, isDeleting: false)
                == "This capture was deleted.")
        #expect(EditorAvailability.refusal(for: .saveAs, record: nil, saveFolder: folder, isDeleting: false) == nil)
    }

    @Test func availabilityWhileDeletingIsCopyAndSaveAs() {
        let record = saved(state: .uploaded(url: link, key: "a.png"))
        #expect(actions(record) == Set(EditorAction.allCases))
        #expect(actions(record, deleting: true) == [.copy, .saveAs])
    }

    /// Keyed on `linkURL`; `uploadAsNewKeepsInterruptedReplace` covers a link held only in `priorUpload`.
    @Test func uploadAsNewNeedsALink() {
        let never = saved()
        #expect(actions(never) == [.save, .saveAs, .copy, .upload])
        #expect(EditorAvailability.refusal(for: .uploadAsNew, record: never, saveFolder: folder, isDeleting: false)
                == "This capture has no link yet. Use Upload.")
        #expect(!actions(saved(state: .failed(message: "offline"))).contains(.uploadAsNew))
        #expect(actions(saved(state: .uploaded(url: link, key: "a.png"))).contains(.uploadAsNew))
    }

    /// A replace killed by a quit leaves `.failed` with the link in `priorUpload`. The link still
    /// exists, so Upload as New stays available (Upload as New to a new key, then delete the old).
    @Test func uploadAsNewKeepsInterruptedReplace() {
        var interrupted = saved(state: .failed(message: "Upload was interrupted."), stale: true)
        interrupted.objectLocation = location
        interrupted.priorUpload = PriorUpload(url: link, key: "a.png", location: location, isReplace: true)
        #expect(actions(interrupted).contains(.uploadAsNew))
        #expect(EditorAvailability.refusal(for: .uploadAsNew, record: interrupted, saveFolder: folder, isDeleting: false) == nil)

        // The same record, still without a link, is refused.
        var linkless = interrupted
        linkless.priorUpload = nil
        #expect(!actions(linkless).contains(.uploadAsNew))
        #expect(EditorAvailability.refusal(for: .uploadAsNew, record: linkless, saveFolder: folder, isDeleting: false)
                == "This capture has no link yet. Use Upload.")

        // While the replace runs, the uploading refusal still wins.
        interrupted.uploadState = .uploading(fraction: 0.2)
        #expect(EditorAvailability.refusal(for: .uploadAsNew, record: interrupted, saveFolder: folder, isDeleting: false)
                == "This capture is still uploading.")
    }

    @Test func everyActionShortcutMapsToAnAvailabilityAction() {
        let expected: [EditorShortcut: EditorAction] = [
            .save: .save, .saveAs: .saveAs, .copy: .copy, .copyImage: .copy,
            .upload: .upload, .uploadAsNew: .uploadAsNew,
        ]
        for shortcut in EditorShortcut.allCases {
            #expect(EditorCommandGate.action(for: shortcut.selectorName) == expected[shortcut], "\(shortcut)")
        }
        #expect(Set(expected.values) == Set(EditorAction.allCases))
    }

    @Test func gateRefusesDisabledShortcut() {
        let available = actions(saved(state: .uploading(fraction: 0)))
        for selector in ["saveDocument:", "uploadDocument:", "uploadDocumentAsNew:"] {
            #expect(!EditorCommandGate.permits(selector, available: available), "\(selector)")
        }
        for selector in ["saveDocumentAs:", "copy:", "copyImage:"] {
            #expect(EditorCommandGate.permits(selector, available: available), "\(selector)")
        }
        // Not an editor action: always let through, whatever is available.
        #expect(EditorCommandGate.permits("undo:", available: []))
        #expect(EditorCommandGate.permits("zoomIn:", available: []))
        #expect(EditorCommandGate.action(for: "cut:") == nil)
    }

    @Test func refusalWhileDeletingNamesTheDeleteForSaveAndUpload() {
        let record = saved(state: .uploaded(url: link, key: "a.png"))
        for action in [EditorAction.save, .upload, .uploadAsNew] {
            #expect(EditorAvailability.refusal(for: action, record: record, saveFolder: folder, isDeleting: true)
                    == "This capture is being deleted.", "\(action)")
        }
        #expect(EditorAvailability.refusal(for: .saveAs, record: record, saveFolder: folder, isDeleting: true) == nil)
        #expect(EditorAvailability.refusal(for: .copy, record: record, saveFolder: folder, isDeleting: true) == nil)
        #expect(EditorAvailability.refusal(for: .save, record: record, saveFolder: folder, isDeleting: false) == nil)
    }

    @Test func availabilityFollowsSaveFolderChange() {
        let folderA = URL(filePath: "/Users/tim/Pictures/A", directoryHint: .isDirectory)
        let folderB = URL(filePath: "/Users/tim/Pictures/B", directoryHint: .isDirectory)
        let record = saved(in: folderA)
        #expect(actions(record, folder: folderA).contains(.save))
        #expect(EditorSaveCommand.forSave(record: record, saveFolder: folderA) == .writeOver)
        // Outside the new folder, ⌘S opens the save panel instead of writing over the old file.
        #expect(actions(record, folder: folderB).contains(.save))
        #expect(EditorSaveCommand.forSave(record: record, saveFolder: folderB) == .saveAs)
        #expect(actions(record, folder: folderB).contains(.upload))
        #expect(EditorAvailability.status(record: record, saveFolder: folderA, isDeleting: false) == nil)
        #expect(EditorAvailability.status(record: record, saveFolder: folderB, isDeleting: false)
                == "The file is outside the current save folder, so it is not saved over.")
    }

    @Test func statusSaysDeletingWhileDeleting() {
        let uploading = saved(state: .uploading(fraction: 0.5))
        let stale = saved(state: .uploaded(url: link, key: "a.png"), stale: true)
        #expect(EditorAvailability.status(record: uploading, saveFolder: folder, isDeleting: true) == "Deleting…")
        #expect(EditorAvailability.status(record: stale, saveFolder: folder, isDeleting: true) == "Deleting…")
        // removeRecord has run: the record is gone, and the deleted text wins.
        #expect(EditorAvailability.status(record: nil, saveFolder: folder, isDeleting: true)
                == "This capture was deleted. Copy and Save As still work.")
    }

    /// ⌘S writes over the Save target when there is one, and otherwise opens the save panel. A
    /// deleted or pruned record has nothing to write over.
    @Test func saveCommandWritesOverOrOpensThePanel() {
        let pending = CaptureRecord(fileURL: pendingURL, fileIsTemporary: true, pixelWidth: 200, pixelHeight: 100,
                                    appName: nil, uploadState: .failed(message: "offline"))
        let uploadOnly = CaptureRecord(fileURL: nil, pixelWidth: 200, pixelHeight: 100, appName: nil,
                                       uploadState: .uploaded(url: link, key: "a.png"), objectLocation: location)
        #expect(EditorSaveCommand.forSave(record: saved(), saveFolder: folder) == .writeOver)
        #expect(EditorSaveCommand.forSave(record: pending, saveFolder: folder) == .writeOver)
        #expect(EditorSaveCommand.forSave(record: uploadOnly, saveFolder: folder) == .saveAs)
        #expect(EditorSaveCommand.forSave(record: nil, saveFolder: folder) == .saveAs)
    }

    /// Save As… is never refused, so the panel is there whenever ⌘S is not.
    @Test func saveAsIsAlwaysAvailable() {
        let uploading = saved(state: .uploading(fraction: 0.4))
        for (record, deleting) in [(saved(), false), (saved(), true), (uploading, false), (nil, false)] as [(CaptureRecord?, Bool)] {
            #expect(EditorAvailability.refusal(for: .saveAs, record: record, saveFolder: folder, isDeleting: deleting) == nil)
            #expect(actions(record, deleting: deleting).contains(.saveAs))
        }
    }

    /// The close sheet's first button runs Save (which may open the panel itself), or Save As…
    /// when Save is unavailable: uploading, deleting or deleted.
    @Test func closeSheetSaveButton() {
        #expect(EditorSaveCommand.closeSheetButton(available: actions(saved())) == .save)
        #expect(EditorSaveCommand.closeSheetButton(available: actions(saved(state: .uploading(fraction: 0)))) == .saveAs)
        #expect(EditorSaveCommand.closeSheetButton(available: actions(saved(), deleting: true)) == .saveAs)
        #expect(EditorSaveCommand.closeSheetButton(available: actions(nil)) == .saveAs)
        #expect(EditorSaveCommand.CloseSheetButton.save.title == "Save")
        #expect(EditorSaveCommand.CloseSheetButton.saveAs.title == "Save As…")
    }
}
