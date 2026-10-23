import Foundation
import Testing
@testable import TidyShot

struct UploadPayloadTests {
    let saveFolder = URL(filePath: "/Users/tim/Pictures/Shots", directoryHint: .isDirectory)
    let container = URL(filePath: "/Users/tim/Library/Containers/io.tky.tidyshot/Data", directoryHint: .isDirectory)

    var pendingFile: URL { container.appending(path: "Library/Application Support/TidyShot/pending/A.mp4") }
    var recordingFile: URL { container.appending(path: "tmp/Recording/B.mp4") }
    var clopFile: URL { container.appending(path: "tmp/Clop/C.mp4") }
    var savedFile: URL { saveFolder.appending(path: "Recording 2026-10-22 at 10.00.00.mp4") }

    func video(at fileURL: URL?, temporary: Bool) -> CaptureRecord {
        CaptureRecord(fileURL: fileURL, fileIsTemporary: temporary, pixelWidth: 1600, pixelHeight: 1000,
                      appName: nil, uploadState: .none, mediaKind: .video, durationSeconds: 3)
    }

    @Test func saveFolderFileIsScopedToTheFolder() {
        #expect(UploadPayload.scope(for: savedFile, isTemporary: false, saveFolder: saveFolder) == saveFolder)
        let nested = saveFolder.appending(path: "2026/10/Recording.mp4")
        #expect(UploadPayload.scope(for: nested, isTemporary: false, saveFolder: saveFolder) == saveFolder)
    }

    /// `pending/`, `tmp/Recording` and `tmp/Clop` are in the container, which needs no scope.
    @Test func containerFilesHaveNoScope() {
        for file in [pendingFile, recordingFile, clopFile] {
            #expect(UploadPayload.scope(for: file, isTemporary: true, saveFolder: saveFolder) == nil)
            #expect(UploadPayload.scope(for: file, isTemporary: false, saveFolder: saveFolder) == nil)
        }
    }

    @Test func noSaveFolderMeansNoScope() {
        #expect(UploadPayload.scope(for: savedFile, isTemporary: false, saveFolder: nil) == nil)
    }

    @Test func pendingVideoIsAFileWithoutScope() throws {
        var checked: [(URL, URL?)] = []
        let payload = try UploadPayload.video(for: video(at: pendingFile, temporary: true), saveFolder: saveFolder) {
            checked.append(($0, $1))
            return true
        }
        #expect(payload == .file(pendingFile, scope: nil))
        #expect(checked.count == 1)
        #expect(checked.first?.0 == pendingFile)
        #expect(checked.first?.1 == nil)
    }

    /// The existence check runs with the folder whose scope it must hold.
    @Test func saveFolderVideoIsAFileWithTheFolderAsScope() throws {
        var checked: [(URL, URL?)] = []
        let payload = try UploadPayload.video(for: video(at: savedFile, temporary: false), saveFolder: saveFolder) {
            checked.append(($0, $1))
            return true
        }
        #expect(payload == .file(savedFile, scope: saveFolder))
        #expect(checked.first?.0 == savedFile)
        #expect(checked.first?.1 == saveFolder)
    }

    @Test func missingFileThrows() {
        #expect(throws: UploadError.fileUnreadable(savedFile.lastPathComponent)) {
            try UploadPayload.video(for: video(at: savedFile, temporary: false), saveFolder: saveFolder) { _, _ in false }
        }
        #expect(throws: UploadError.fileUnreadable(pendingFile.lastPathComponent)) {
            try UploadPayload.video(for: video(at: pendingFile, temporary: true), saveFolder: nil) { _, _ in false }
        }
    }

    @Test func recordWithoutAFileThrows() {
        #expect(throws: UploadError.fileUnreadable("no local file")) {
            try UploadPayload.video(for: video(at: nil, temporary: false), saveFolder: saveFolder) { _, _ in true }
        }
    }

    /// The folder was changed since the recording was saved: its old folder's scope is gone.
    @Test func saveFolderVideoOutsideTheCurrentFolderThrows() {
        let elsewhere = URL(filePath: "/Volumes/Archive/Shots/Recording.mp4")
        var checks = 0
        #expect(throws: UploadError.fileUnreadable("Recording.mp4")) {
            try UploadPayload.video(for: video(at: elsewhere, temporary: false), saveFolder: saveFolder) { _, _ in
                checks += 1
                return true
            }
        }
        #expect(checks == 0)
    }

    @Test func saveFolderVideoWithNoFolderThrows() {
        #expect(throws: UploadError.fileUnreadable(savedFile.lastPathComponent)) {
            try UploadPayload.video(for: video(at: savedFile, temporary: false), saveFolder: nil) { _, _ in true }
        }
    }
}
