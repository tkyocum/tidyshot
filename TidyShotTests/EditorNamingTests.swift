import Foundation
import Testing
@testable import TidyShot

struct EditorNamingTests {
    func record(fileURL: URL?, temporary: Bool = false) -> CaptureRecord {
        CaptureRecord(fileURL: fileURL, fileIsTemporary: temporary, pixelWidth: 64, pixelHeight: 48, appName: nil)
    }

    /// Only the extension goes; the dots in the time stay.
    @Test func stemPlusEditedForSaveFolderFile() {
        let file = URL(fileURLWithPath: "/Users/tim/Desktop/Screenshot 2026-10-20 at 09.15.02.png")
        #expect(EditorNaming.copyBaseName(for: record(fileURL: file)) == "Screenshot 2026-10-20 at 09.15.02 edited")
    }

    /// A pending file is `<id>.png`, and spec 2.6 takes the stem of any file the original has.
    @Test func stemPlusEditedForPendingFile() {
        let id = UUID()
        let file = URL(fileURLWithPath: "/tmp/pending/\(id.uuidString).png")
        #expect(EditorNaming.copyBaseName(for: record(fileURL: file, temporary: true)) == "\(id.uuidString) edited")
    }

    /// No file (an uploaded upload-only capture) or no record (deleted or pruned): the file name
    /// template names the copy.
    @Test func nilWhenNoFile() {
        let uploaded = CaptureRecord(fileURL: nil, pixelWidth: 64, pixelHeight: 48, appName: nil,
                                     uploadState: .uploaded(url: URL(string: "https://snap.example.com/a.png")!, key: "a.png"))
        #expect(EditorNaming.copyBaseName(for: uploaded) == nil)
        #expect(EditorNaming.copyBaseName(for: nil) == nil)
    }
}
