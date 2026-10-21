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
        #expect(!actions(record).contains(.save))
        #expect(actions(record).isSuperset(of: [.saveCopy, .copy, .upload]))
    }

    @Test func noFolderUnavailable() {
        #expect(EditorSaveTarget.plan(for: saved(), saveFolder: nil)
                == .unavailable("No save folder is set, so the file is not saved over."))
        #expect(EditorAvailability.status(record: saved(), saveFolder: nil, isDeleting: false)
                == "No save folder is set, so the file is not saved over.")
    }

    /// An upload-only capture's file in `pending` needs no save folder.
    @Test func pendingFileIsPendingTarget() {
        let record = CaptureRecord(fileURL: pendingURL, fileIsTemporary: true, pixelWidth: 200, pixelHeight: 100,
                                   appName: nil, uploadState: .failed(message: "offline"))
        #expect(EditorSaveTarget.plan(for: record, saveFolder: folder) == .pendingFile(pendingURL))
        #expect(EditorSaveTarget.plan(for: record, saveFolder: nil) == .pendingFile(pendingURL))
        #expect(actions(record) == [.save, .saveCopy, .copy, .upload])
    }

    @Test func uploadedUploadOnlyWithoutFileUnavailable() {
        let record = CaptureRecord(fileURL: nil, pixelWidth: 200, pixelHeight: 100, appName: nil,
                                   uploadState: .uploaded(url: link, key: "a.png"), objectLocation: location)
        #expect(EditorSaveTarget.plan(for: record, saveFolder: folder)
                == .unavailable("This capture has no local file to save over."))
        #expect(actions(record) == [.saveCopy, .copy, .upload, .uploadAsNew])
        #expect(EditorAvailability.refusal(for: .save, record: record, saveFolder: folder, isDeleting: false)
                == "This capture has no local file to save over.")
    }

    /// Records uploaded before Phase 3 keep their file in the save folder and have no stored location.
    @Test func prePhaseThreeUploadedWithFileOverwrites() throws {
        let record = saved(state: .uploaded(url: link, key: "a.png"))
        #expect(record.objectLocation == nil)
        let fileURL = try #require(record.fileURL)
        #expect(EditorSaveTarget.plan(for: record, saveFolder: folder) == .saveFolderFile(fileURL, folder: folder))
        #expect(actions(record) == Set(EditorAction.allCases))
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

    @Test func availabilityWhileUploadingIsCopyAndSaveCopy() {
        let uploading = saved(state: .uploading(fraction: 0.3))
        #expect(actions(uploading) == [.copy, .saveCopy])
        #expect(EditorAvailability.status(record: uploading, saveFolder: folder, isDeleting: false) == "Uploading…")
        #expect(EditorAvailability.refusal(for: .save, record: uploading, saveFolder: folder, isDeleting: false)
                == "This capture is still uploading.")
        #expect(EditorAvailability.refusal(for: .upload, record: uploading, saveFolder: folder, isDeleting: false)
                == "This capture is still uploading.")
    }

    /// A nil record was deleted or pruned.
    @Test func availabilityWhenDeletedIsCopyAndSaveCopy() {
        #expect(actions(nil) == [.copy, .saveCopy])
        #expect(actions(nil, deleting: true) == [.copy, .saveCopy])
        #expect(EditorAvailability.status(record: nil, saveFolder: folder, isDeleting: false)
                == "This capture was deleted. Copy and Save Copy still work.")
        #expect(EditorAvailability.refusal(for: .save, record: nil, saveFolder: folder, isDeleting: false)
                == "This capture was deleted.")
        #expect(EditorAvailability.refusal(for: .saveCopy, record: nil, saveFolder: folder, isDeleting: false) == nil)
    }

    @Test func availabilityWhileDeletingIsCopyAndSaveCopy() {
        let record = saved(state: .uploaded(url: link, key: "a.png"))
        #expect(actions(record) == Set(EditorAction.allCases))
        #expect(actions(record, deleting: true) == [.copy, .saveCopy])
    }

    /// Keyed on `uploadedURL` here; Task 14 re-keys it on `linkURL` and adds the interrupted-replace case.
    @Test func uploadAsNewNeedsALink() {
        let never = saved()
        #expect(actions(never) == [.save, .saveCopy, .copy, .upload])
        #expect(EditorAvailability.refusal(for: .uploadAsNew, record: never, saveFolder: folder, isDeleting: false)
                == "This capture has no link yet. Use Upload.")
        #expect(!actions(saved(state: .failed(message: "offline"))).contains(.uploadAsNew))
        #expect(actions(saved(state: .uploaded(url: link, key: "a.png"))).contains(.uploadAsNew))
    }

    @Test func everyActionShortcutMapsToAnAvailabilityAction() {
        let expected: [EditorShortcut: EditorAction] = [
            .save: .save, .saveCopy: .saveCopy, .copy: .copy, .copyImage: .copy,
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
        for selector in ["saveDocumentCopy:", "copy:", "copyImage:"] {
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
        #expect(EditorAvailability.refusal(for: .saveCopy, record: record, saveFolder: folder, isDeleting: true) == nil)
        #expect(EditorAvailability.refusal(for: .copy, record: record, saveFolder: folder, isDeleting: true) == nil)
        #expect(EditorAvailability.refusal(for: .save, record: record, saveFolder: folder, isDeleting: false) == nil)
    }

    @Test func availabilityFollowsSaveFolderChange() {
        let folderA = URL(filePath: "/Users/tim/Pictures/A", directoryHint: .isDirectory)
        let folderB = URL(filePath: "/Users/tim/Pictures/B", directoryHint: .isDirectory)
        let record = saved(in: folderA)
        #expect(actions(record, folder: folderA).contains(.save))
        #expect(!actions(record, folder: folderB).contains(.save))
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
                == "This capture was deleted. Copy and Save Copy still work.")
    }
}
