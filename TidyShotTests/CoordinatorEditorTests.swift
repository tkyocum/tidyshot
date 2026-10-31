import Foundation
import Testing
@testable import TidyShot

/// The editor's load on a built coordinator (`AppCoordinator+Editor`): `loadImage(for:)`, and an Annotate
/// whose load fails. Presenting the window builds an `EditorWindowController`, which reads the screens;
/// that is the editor seam's, and no test here reaches it.
@Suite(.timeLimit(.minutes(1)))
struct CoordinatorEditorTests {
    let world: CoordinatorWorld
    let key = "s/SHOT.png"

    init() throws {
        world = try CoordinatorWorld()
    }

    var destination: FakeDestination { world.factory.standard }
    var link: URL { URL(string: "https://snap.tky.io/\(key)")! }

    nonisolated enum Kept: CaseIterable, Sendable {
        /// Saved, never uploaded: the file in the save folder.
        case savedFile
        /// Uploaded, its file kept in the save folder.
        case uploadedWithItsFile
        /// Upload only, the upload failed: `pending/<id>.png`.
        case pendingFile
        /// Uploaded, its file renamed in Finder: the object.
        case renamedUploadedFile
    }

    /// phase-4a :46, phase-4a :47, phase-4a :48, phase-4a :51. The editor's pixels come from the save-folder file
    /// of a saved capture and of an uploaded one, from `pending/<id>.png` of a failed upload-only capture, and
    /// from the downloaded object when an uploaded capture's file was renamed. The object is a 6 by 3 PNG, so
    /// the size tells the source.
    @Test(arguments: Kept.allCases)
    func loadImageReadsTheLocalFileOrDownloadsTheObject(record kept: Kept) async throws {
        defer { world.removeAll() }
        let png = try CoordinatorWorld.pngData(width: 4, height: 2)
        let object = try CoordinatorWorld.pngData(width: 6, height: 3)
        destination.state.withLock { $0.downloadedData = object }
        let folder = try world.storeSaveFolder()
        let coordinator = world.makeCoordinator()
        let id = UUID()
        let saved = folder.appending(path: "Shot.png")
        let record: CaptureRecord
        switch kept {
        case .savedFile:
            try png.write(to: saved)
            record = CaptureRecord(id: id, fileURL: saved, pixelWidth: 4, pixelHeight: 2, appName: nil)
        case .uploadedWithItsFile:
            try png.write(to: saved)
            record = CaptureRecord(id: id, fileURL: saved, pixelWidth: 4, pixelHeight: 2, appName: nil,
                                   uploadState: .uploaded(url: link, key: key), objectLocation: world.location)
        case .pendingFile:
            let pending = try coordinator.pendingFiles.write(png, id: id, ext: "png")
            record = CaptureRecord(id: id, fileURL: pending, fileIsTemporary: true, pixelWidth: 4, pixelHeight: 2,
                                   appName: nil, uploadState: .failed(message: "Upload was interrupted."))
        case .renamedUploadedFile:
            record = CaptureRecord(id: id, fileURL: saved, pixelWidth: 4, pixelHeight: 2, appName: nil,
                                   uploadState: .uploaded(url: link, key: key), objectLocation: world.location)
        }
        coordinator.history.add(record)

        let image = try #require(await coordinator.loadImage(for: record))

        let downloads = kept == .renamedUploadedFile
        #expect(image.image.width == (downloads ? 6 : 4))
        #expect(image.image.height == (downloads ? 3 : 2))
        #expect(destination.state.withLock { $0.dataDownloadKeys } == (downloads ? [key] : []))
        #expect(world.notifier.errors.isEmpty)
    }

    /// phase-4a :50. Annotate on a capture from before Phase 3 whose file was moved out of the save folder opens no
    /// window and posts `Could not open the capture` with `The local file could not be read.`
    @Test func annotateOnAMovedPrePhase3FileSaysCouldNotOpenAndOpensNoEditor() async throws {
        defer { world.removeAll() }
        let folder = try world.storeSaveFolder()
        let coordinator = world.makeCoordinator()
        let record = CaptureRecord(fileURL: folder.appending(path: "Moved.png"), pixelWidth: 4, pixelHeight: 2,
                                   appName: nil, uploadState: .uploaded(url: link, key: key))
        coordinator.history.add(record)

        coordinator.openEditor(recordID: record.id)
        try await eventually {
            world.notifier.calls.contains(.error(title: "Could not open the capture",
                                                 message: "The local file could not be read."))
        }
        try await eventually { coordinator.openingEditorIDs.isEmpty }

        #expect(coordinator.editors.isEmpty)
        #expect(destination.state.withLock { $0.dataDownloadKeys.isEmpty })
    }
}
