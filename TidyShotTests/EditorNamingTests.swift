import AppKit
import Foundation
import Testing
import UniformTypeIdentifiers
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

    func recordingNamer(_ template: String = FileNamer.recordingDefaultTemplate) -> FileNamer {
        FileNamer(template: template, fallbackName: FileNamer.recordingFallbackName, now: { fixedDate },
                  randomString: { String(repeating: "X", count: $0) }, hostname: "miffle")
    }

    /// A capture with a file in the save folder suggests that file's name, in the save folder.
    @Test func saveFolderFileSuggestsItsOwnName() {
        let file = folder.appending(path: "Screenshot 2026-10-20 at 09.15.02.png")
        let suggestion = EditorNaming.saveAsSuggestion(for: record(fileURL: file), saveFolder: folder, namer: namer(),
                                                       recordingNamer: recordingNamer(), currentCounter: 7)
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
            #expect(EditorNaming.saveAsSuggestion(for: record, saveFolder: folder, namer: namer(), recordingNamer: recordingNamer(),
                                                  currentCounter: 7).fileName
                    == "Screenshot 2026-10-20 at 09.15.02.png")
        }
    }

    /// `{counter}` uses the current value; nothing is drawn, so the next capture's number is unchanged.
    @Test func counterUsesTheCurrentValue() {
        let suggestion = EditorNaming.saveAsSuggestion(for: nil, saveFolder: folder, namer: namer("shot-{counter}"),
                                                       recordingNamer: recordingNamer(), currentCounter: 41)
        #expect(suggestion.fileName == "shot-41.png")
    }

    /// No save folder: the panel opens where it last was.
    @Test func noFolderLeavesTheDirectoryToThePanel() {
        #expect(EditorNaming.saveAsSuggestion(for: nil, saveFolder: nil, namer: namer(), recordingNamer: recordingNamer(),
                                              currentCounter: 0).directory == nil)
    }

    /// The card's Save As… (spec 2.9) uses this suggestion. An upload-only capture before its
    /// upload finished (its pending `<id>.png`, uploading or failed) has no key: the template's
    /// name, in the save folder when one is set, else where the panel last was.
    @Test func uploadOnlyCaptureWithoutAKeySuggestsTheTemplateName() {
        let pending = URL(fileURLWithPath: "/tmp/pending/\(UUID().uuidString).png")
        let uploading = CaptureRecord(fileURL: pending, fileIsTemporary: true, pixelWidth: 64, pixelHeight: 48,
                                      appName: nil, uploadState: .uploading(fraction: 0.4))
        let failed = CaptureRecord(fileURL: pending, fileIsTemporary: true, pixelWidth: 64, pixelHeight: 48,
                                   appName: nil, uploadState: .failed(message: "Upload not configured."))
        for record in [uploading, failed] {
            #expect(EditorNaming.saveAsSuggestion(for: record, saveFolder: folder, namer: namer(), recordingNamer: recordingNamer(),
                                                  currentCounter: 7)
                    == EditorNaming.SaveAsSuggestion(fileName: "Screenshot 2026-10-20 at 09.15.02.png", directory: folder))
            #expect(EditorNaming.saveAsSuggestion(for: record, saveFolder: nil, namer: namer(), recordingNamer: recordingNamer(),
                                                  currentCounter: 7)
                    == EditorNaming.SaveAsSuggestion(fileName: "Screenshot 2026-10-20 at 09.15.02.png", directory: nil))
        }
    }

    /// With a key: an uploaded upload-only capture (no file) still gets the template's name, not the
    /// key (the key names the drag file, Task 6); `{counter}` is the current one. A save-folder file
    /// that was also uploaded keeps its own name.
    @Test func uploadedCaptureWithAKeySuggestsTheTemplateOrItsOwnName() {
        let link = URL(string: "https://snap.example.com/shots/aSIS7.png")!
        let uploadedOnly = CaptureRecord(fileURL: nil, pixelWidth: 64, pixelHeight: 48, appName: nil,
                                         uploadState: .uploaded(url: link, key: "shots/aSIS7.png"))
        #expect(EditorNaming.saveAsSuggestion(for: uploadedOnly, saveFolder: nil, namer: namer(), recordingNamer: recordingNamer(),
                                              currentCounter: 7)
                == EditorNaming.SaveAsSuggestion(fileName: "Screenshot 2026-10-20 at 09.15.02.png", directory: nil))
        #expect(EditorNaming.saveAsSuggestion(for: uploadedOnly, saveFolder: folder, namer: namer("shot-{counter}"),
                                              recordingNamer: recordingNamer(), currentCounter: 12).fileName == "shot-12.png")

        let file = folder.appending(path: "Bug 12.png")
        let savedAndUploaded = CaptureRecord(fileURL: file, pixelWidth: 64, pixelHeight: 48, appName: nil,
                                             uploadState: .uploaded(url: link, key: "shots/aSIS7.png"))
        #expect(EditorNaming.saveAsSuggestion(for: savedAndUploaded, saveFolder: folder, namer: namer(),
                                              recordingNamer: recordingNamer(), currentCounter: 7)
                == EditorNaming.SaveAsSuggestion(fileName: "Bug 12.png", directory: folder))
    }

    func video(fileURL: URL?, temporary: Bool = false, state: CaptureRecord.UploadState = .none) -> CaptureRecord {
        CaptureRecord(fileURL: fileURL, fileIsTemporary: temporary, pixelWidth: 1600, pixelHeight: 1000, appName: nil,
                      uploadState: state, mediaKind: .video, durationSeconds: 42)
    }

    /// A recording in the save folder suggests its own file name.
    @Test func aVideoWithASaveFolderFileSuggestsItsOwnName() {
        let file = folder.appending(path: "Recording 2026-10-20 at 09.15.02.mp4")
        #expect(EditorNaming.saveAsSuggestion(for: video(fileURL: file), saveFolder: folder, namer: namer(),
                                              recordingNamer: recordingNamer(), currentCounter: 7)
                == EditorNaming.SaveAsSuggestion(fileName: "Recording 2026-10-20 at 09.15.02.mp4", directory: folder,
                                                 mediaKind: .video))
    }

    /// Without one (a pending `<id>.mp4`, or only an upload), the recording template plus `.mp4`,
    /// with `{counter}` as for screenshots.
    @Test func aVideoWithoutOneSuggestsTheRecordingTemplate() {
        let pending = video(fileURL: URL(fileURLWithPath: "/tmp/pending/\(UUID().uuidString).mp4"), temporary: true,
                            state: .uploading(fraction: 0.3))
        let uploadedOnly = video(fileURL: nil, state: .uploaded(url: URL(string: "https://snap.example.com/a.mp4")!, key: "a.mp4"))
        for record in [pending, uploadedOnly] {
            #expect(EditorNaming.saveAsSuggestion(for: record, saveFolder: folder, namer: namer(),
                                                  recordingNamer: recordingNamer(), currentCounter: 7)
                    == EditorNaming.SaveAsSuggestion(fileName: "Recording 2026-10-20 at 09.15.02.mp4", directory: folder,
                                                     mediaKind: .video))
        }
        #expect(EditorNaming.saveAsSuggestion(for: pending, saveFolder: nil, namer: namer(),
                                              recordingNamer: recordingNamer("clip-{counter}"), currentCounter: 41).fileName
                == "clip-41.mp4")
        #expect(EditorNaming.saveAsSuggestion(for: pending, saveFolder: nil, namer: namer(),
                                              recordingNamer: recordingNamer(""), currentCounter: 0).fileName
                == "Recording.mp4")
    }

    func gif(fileURL: URL?, temporary: Bool = false, state: CaptureRecord.UploadState = .none) -> CaptureRecord {
        CaptureRecord(fileURL: fileURL, fileIsTemporary: temporary, pixelWidth: 1280, pixelHeight: 832, appName: nil,
                      uploadState: state, mediaKind: .gif, durationSeconds: 10)
    }

    /// A GIF is named as a recording: `Recording file name` plus `.gif`, or its own name in the
    /// save folder.
    @Test func aGIFSuggestionUsesTheRecordingTemplateAndGIF() {
        let pending = gif(fileURL: URL(fileURLWithPath: "/tmp/pending/\(UUID().uuidString).gif"), temporary: true,
                          state: .uploading(fraction: 0.3))
        let uploadedOnly = gif(fileURL: nil, state: .uploaded(url: URL(string: "https://snap.example.com/a.gif")!, key: "a.gif"))
        for record in [pending, uploadedOnly] {
            #expect(EditorNaming.saveAsSuggestion(for: record, saveFolder: folder, namer: namer(),
                                                  recordingNamer: recordingNamer(), currentCounter: 7)
                    == EditorNaming.SaveAsSuggestion(fileName: "Recording 2026-10-20 at 09.15.02.gif", directory: folder,
                                                     mediaKind: .gif))
        }
        #expect(EditorNaming.saveAsSuggestion(for: pending, saveFolder: nil, namer: namer(),
                                              recordingNamer: recordingNamer("clip-{counter}"), currentCounter: 41).fileName
                == "clip-41.gif")

        let file = folder.appending(path: "Recording 2026-10-20 at 09.15.02.gif")
        #expect(EditorNaming.saveAsSuggestion(for: gif(fileURL: file), saveFolder: folder, namer: namer(),
                                              recordingNamer: recordingNamer(), currentCounter: 7)
                == EditorNaming.SaveAsSuggestion(fileName: "Recording 2026-10-20 at 09.15.02.gif", directory: folder,
                                                 mediaKind: .gif))
    }

    /// A GIF's Save As… panel offers `com.compuserve.gif` only.
    @Test func aGIFPanelAllowsGIFOnly() {
        let panel = EditorNaming.savePanel(for: EditorNaming.SaveAsSuggestion(fileName: "Recording.gif", directory: folder,
                                                                             mediaKind: .gif))
        #expect(panel.allowedContentTypes == [.gif])
        #expect(UTType.gif.identifier == "com.compuserve.gif")
    }

    /// A screenshot, or no record, is an image.
    @Test func anImageSuggestionIsAnImage() {
        #expect(EditorNaming.saveAsSuggestion(for: nil, saveFolder: folder, namer: namer(), recordingNamer: recordingNamer(),
                                              currentCounter: 0).mediaKind == .image)
        let file = folder.appending(path: "Bug 12.png")
        #expect(EditorNaming.saveAsSuggestion(for: record(fileURL: file), saveFolder: folder, namer: namer(),
                                              recordingNamer: recordingNamer(), currentCounter: 0).mediaKind == .image)
    }

    /// The panel takes `.mpeg4Movie` only for a video, and PNG only for an image.
    @Test func thePanelAllowsTheSuggestionsType() {
        let movie = EditorNaming.savePanel(for: EditorNaming.SaveAsSuggestion(fileName: "Recording.mp4", directory: folder,
                                                                             mediaKind: .video))
        #expect(movie.allowedContentTypes == [.mpeg4Movie])
        #expect(movie.nameFieldStringValue == "Recording.mp4")
        let image = EditorNaming.savePanel(for: EditorNaming.SaveAsSuggestion(fileName: "Shot.png", directory: nil))
        #expect(image.allowedContentTypes == [.png])
    }
}
