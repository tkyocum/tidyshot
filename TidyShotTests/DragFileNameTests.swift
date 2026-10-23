import Foundation
import Testing
@testable import TidyShot

struct DragFileNameTests {
    let suggestion = EditorNaming.SaveAsSuggestion(fileName: "Screenshot 2026-10-21 at 09.15.02.png", directory: nil)
    let location = ObjectLocation(endpoint: "https://s3.us-west-2.amazonaws.com", region: "us-west-2", bucket: "snap",
                                  usePathStyle: false)

    func record(file: URL? = nil, temporary: Bool = false, state: CaptureRecord.UploadState = .none,
                prior: PriorUpload? = nil) -> CaptureRecord {
        CaptureRecord(fileURL: file, fileIsTemporary: temporary, pixelWidth: 64, pixelHeight: 48, appName: nil,
                      uploadState: state, priorUpload: prior)
    }

    func uploaded(_ key: String) -> CaptureRecord.UploadState {
        .uploaded(url: URL(string: "https://snap.example.com/\(key)")!, key: key)
    }

    /// The key's name, so the dropped file matches the link on the clipboard: for an uploaded
    /// upload-only capture (no file) and for a save-folder file that was uploaded too.
    @Test func uploadedKeyNamesTheFile() {
        #expect(DragFileName.name(for: record(state: uploaded("aSIS7.png")), suggestion: suggestion) == "aSIS7.png")
        let saved = record(file: URL(fileURLWithPath: "/Users/tim/Pictures/TidyShot/Bug 12.png"), state: uploaded("aSIS7.png"))
        let own = EditorNaming.SaveAsSuggestion(fileName: "Bug 12.png", directory: nil)
        #expect(DragFileName.name(for: saved, suggestion: own) == "aSIS7.png")
    }

    @Test func nestedKeyGivesItsLastComponent() {
        #expect(DragFileName.name(for: record(state: uploaded("shots/2026/x.png")), suggestion: suggestion) == "x.png")
    }

    /// No key: the Save As suggestion, which is the save-folder file's own name or the template's
    /// name (never a pending `<id>.png`).
    @Test func withoutAKeyTheSaveAsSuggestionNamesTheFile() {
        let own = EditorNaming.SaveAsSuggestion(fileName: "Bug 12.png", directory: nil)
        #expect(DragFileName.name(for: record(file: URL(fileURLWithPath: "/Users/tim/Pictures/TidyShot/Bug 12.png")),
                                  suggestion: own) == "Bug 12.png")
        let pending = URL(fileURLWithPath: "/tmp/pending/\(UUID().uuidString).png")
        for state in [.uploading(fraction: 0.5), .failed(message: "Upload failed."), .none] as [CaptureRecord.UploadState] {
            #expect(DragFileName.name(for: record(file: pending, temporary: true, state: state), suggestion: suggestion)
                    == "Screenshot 2026-10-21 at 09.15.02.png")
        }
    }

    /// While the editor uploads over a link, the clipboard still holds that link: its key names the file.
    @Test func anUploadOverALinkUsesThePriorKey() {
        let prior = PriorUpload(url: URL(string: "https://snap.example.com/p/aSIS7.png")!, key: "p/aSIS7.png",
                                location: location, isReplace: true)
        #expect(DragFileName.name(for: record(state: .uploading(fraction: 0.2), prior: prior), suggestion: suggestion)
                == "aSIS7.png")
    }

    /// A key's name is made safe for a file: `.png` added when missing, `:` and a leading dot
    /// replaced. A key ending in `/` has no name, so the suggestion is used.
    @Test func keyNamesAreMadeSafeForAFile() {
        #expect(DragFileName.name(for: record(state: uploaded("p/aSIS7")), suggestion: suggestion) == "aSIS7.png")
        #expect(DragFileName.name(for: record(state: uploaded("p/.hidden.png")), suggestion: suggestion) == "_hidden.png")
        #expect(DragFileName.name(for: record(state: uploaded("p/a:b.PNG")), suggestion: suggestion) == "a-b.PNG")
        #expect(DragFileName.name(for: record(state: uploaded("shots/")), suggestion: suggestion) == suggestion.fileName)
    }

    func video(file: URL? = nil, temporary: Bool = false, state: CaptureRecord.UploadState = .none) -> CaptureRecord {
        CaptureRecord(fileURL: file, fileIsTemporary: temporary, pixelWidth: 1600, pixelHeight: 1000, appName: nil,
                      uploadState: state, mediaKind: .video, durationSeconds: 42)
    }

    /// A recording's key keeps its own extension; `.png` is added only to images.
    @Test func anMP4KeyKeepsItsName() {
        #expect(DragFileName.name(for: video(state: uploaded("shots/aSIS7.mp4")), suggestion: suggestion) == "aSIS7.mp4")
        #expect(DragFileName.name(for: video(state: uploaded("p/aSIS7")), suggestion: suggestion) == "aSIS7")
        #expect(DragFileName.name(for: video(state: uploaded("p/a:b.MP4")), suggestion: suggestion) == "a-b.MP4")
    }

    /// Without a key, the Save As… suggestion names the file, with the record's extension.
    @Test func theFallbackUsesTheRecordsExtension() {
        let folder = URL(filePath: "/Users/tim/Pictures/TidyShot", directoryHint: .isDirectory)
        let started = DateComponents(calendar: .current, year: 2026, month: 10, day: 22, hour: 10, minute: 0, second: 0).date!
        let namer = FileNamer(template: FileNamer.defaultTemplate, now: { started }, hostname: "miffle")
        let recordingNamer = FileNamer(template: FileNamer.recordingDefaultTemplate, fallbackName: FileNamer.recordingFallbackName,
                                       now: { started }, hostname: "miffle")
        let pending = video(file: URL(fileURLWithPath: "/tmp/pending/\(UUID().uuidString).mp4"), temporary: true,
                            state: .uploading(fraction: 0.5))
        let suggestion = EditorNaming.saveAsSuggestion(for: pending, saveFolder: folder, namer: namer,
                                                       recordingNamer: recordingNamer, currentCounter: 3)
        #expect(DragFileName.name(for: pending, suggestion: suggestion) == "Recording 2026-10-22 at 10.00.00.mp4")
    }

    func gif(file: URL? = nil, temporary: Bool = false, state: CaptureRecord.UploadState = .none) -> CaptureRecord {
        CaptureRecord(fileURL: file, fileIsTemporary: temporary, pixelWidth: 1280, pixelHeight: 832, appName: nil,
                      uploadState: state, mediaKind: .gif, durationSeconds: 10)
    }

    /// A GIF's key keeps its name: `.png` is added only to images.
    @Test func aGIFKeyKeepsItsName() {
        #expect(DragFileName.name(for: gif(state: uploaded("shots/aSIS7.gif")), suggestion: suggestion) == "aSIS7.gif")
        #expect(DragFileName.name(for: gif(state: uploaded("p/aSIS7")), suggestion: suggestion) == "aSIS7")
        #expect(DragFileName.name(for: gif(state: uploaded("p/a:b.GIF")), suggestion: suggestion) == "a-b.GIF")
    }

    /// Without a key, the Save As… suggestion names the GIF: the recording template plus `.gif`.
    @Test func aGIFWithoutAKeyUsesTheSuggestion() {
        let folder = URL(filePath: "/Users/tim/Pictures/TidyShot", directoryHint: .isDirectory)
        let started = DateComponents(calendar: .current, year: 2026, month: 10, day: 22, hour: 10, minute: 0, second: 0).date!
        let namer = FileNamer(template: FileNamer.defaultTemplate, now: { started }, hostname: "miffle")
        let recordingNamer = FileNamer(template: FileNamer.recordingDefaultTemplate, fallbackName: FileNamer.recordingFallbackName,
                                       now: { started }, hostname: "miffle")
        let pending = gif(file: URL(fileURLWithPath: "/tmp/pending/\(UUID().uuidString).gif"), temporary: true,
                          state: .uploading(fraction: 0.5))
        let suggestion = EditorNaming.saveAsSuggestion(for: pending, saveFolder: folder, namer: namer,
                                                       recordingNamer: recordingNamer, currentCounter: 3)
        let name = DragFileName.name(for: pending, suggestion: suggestion)
        #expect(name == suggestion.fileName)
        #expect(name == "Recording 2026-10-22 at 10.00.00.gif")
    }
}
