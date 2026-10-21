import Foundation
import Testing
@testable import TidyShot

struct EditorNamingTests {
    let folder = URL(filePath: "/Users/tim/Pictures/TidyShot", directoryHint: .isDirectory)
    /// 2026-10-20 09:15:02 in the current time zone.
    let fixedDate = DateComponents(calendar: .current, year: 2026, month: 10, day: 20, hour: 9, minute: 15, second: 2).date!

    func record(fileURL: URL?, temporary: Bool = false) -> CaptureRecord {
        CaptureRecord(fileURL: fileURL, fileIsTemporary: temporary, pixelWidth: 64, pixelHeight: 48, appName: nil)
    }

    func namer(_ template: String = FileNamer.defaultTemplate) -> FileNamer {
        FileNamer(template: template, now: { fixedDate }, randomString: { String(repeating: "X", count: $0) }, hostname: "miffle")
    }

    /// A capture with a file in the save folder suggests that file's name, in the save folder.
    @Test func saveFolderFileSuggestsItsOwnName() {
        let file = folder.appending(path: "Screenshot 2026-10-20 at 09.15.02.png")
        let suggestion = EditorNaming.saveAsSuggestion(for: record(fileURL: file), saveFolder: folder,
                                                       namer: namer(), currentCounter: 7)
        #expect(suggestion == EditorNaming.SaveAsSuggestion(fileName: "Screenshot 2026-10-20 at 09.15.02.png",
                                                            directory: folder))
    }

    /// No file (an uploaded upload-only capture), no record (deleted or pruned), or a pending
    /// `<id>.png` that is not the user's: the name comes from the file name template, plus `.png`.
    @Test func noFileSuggestsTheTemplateName() {
        let uploaded = CaptureRecord(fileURL: nil, pixelWidth: 64, pixelHeight: 48, appName: nil,
                                     uploadState: .uploaded(url: URL(string: "https://snap.example.com/a.png")!, key: "a.png"))
        let pending = record(fileURL: URL(fileURLWithPath: "/tmp/pending/\(UUID().uuidString).png"), temporary: true)
        for record in [uploaded, pending, nil] as [CaptureRecord?] {
            #expect(EditorNaming.saveAsSuggestion(for: record, saveFolder: folder, namer: namer(), currentCounter: 7).fileName
                    == "Screenshot 2026-10-20 at 09.15.02.png")
        }
    }

    /// `{counter}` uses the current value; nothing is drawn, so the next capture's number is unchanged.
    @Test func counterUsesTheCurrentValue() {
        let suggestion = EditorNaming.saveAsSuggestion(for: nil, saveFolder: folder, namer: namer("shot-{counter}"),
                                                       currentCounter: 41)
        #expect(suggestion.fileName == "shot-41.png")
    }

    /// No save folder: the panel opens where it last was.
    @Test func noFolderLeavesTheDirectoryToThePanel() {
        #expect(EditorNaming.saveAsSuggestion(for: nil, saveFolder: nil, namer: namer(), currentCounter: 0).directory == nil)
    }
}
