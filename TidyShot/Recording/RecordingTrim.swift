import AVFoundation
import CoreMedia
import Foundation

/// Why a trim's export failed (design, Trim, Export): `Not trimmed` posts its text.
nonisolated enum RecordingTrimError: LocalizedError, Equatable, Sendable {
    /// The disk check refused before anything was written.
    case notEnoughSpace
    case couldNotRead
    case couldNotWrite

    var errorDescription: String? {
        switch self {
        case .notEnoughSpace: RecordingTrim.notEnoughSpaceText
        case .couldNotRead: "The recording could not be read."
        case .couldNotWrite: "The trimmed recording could not be written."
        }
    }
}

/// Trim's decisions (design, Trim): its files in `tmp/Trim`, the range, where the source file comes
/// from, the sheet, whether the card and the row offer it, and what Save and Save and Upload write
/// once the live record is read again. The export, off the main actor, is in RecordingTrimExport.swift.
/// `AppCoordinator` does the rest of the I/O.
nonisolated enum RecordingTrim {
    /// A trimmed recording is never shorter than this.
    static let minimumDuration: TimeInterval = 0.5
    static let notTrimmedTitle = "Not trimmed"
    static let tooShortText = "The trimmed recording would be too short."
    static let notEnoughSpaceText = "Not enough disk space."
    /// The save sheet's message.
    static let saveMessage = "Save the trimmed recording?"

    // MARK: Files

    /// `tmp/Trim`, removed at launch: a downloaded source and each pass's working copies.
    static var directory: URL {
        FileManager.default.temporaryDirectory.appending(path: "Trim", directoryHint: .isDirectory)
    }

    /// `<id>.mp4`, the download of a record with no readable file.
    static func downloadURL(for id: UUID) -> URL {
        directory.appending(path: "\(id.uuidString).\(MediaKind.video.fileExtension)", directoryHint: .notDirectory)
    }

    /// `<id>-trimmed.mp4`, the export the put moves over the record's file.
    static func trimmedURL(for id: UUID, in folder: URL = RecordingTrim.directory) -> URL {
        folder.appending(path: "\(id.uuidString)-trimmed.\(MediaKind.video.fileExtension)", directoryHint: .notDirectory)
    }

    /// `<id>-muted.mp4`, a marked record's source with its stored intervals silenced, before the export.
    static func mutedURL(for id: UUID, in folder: URL = RecordingTrim.directory) -> URL {
        folder.appending(path: "\(id.uuidString)-muted.\(MediaKind.video.fileExtension)", directoryHint: .notDirectory)
    }

    // MARK: The range

    /// The trim bar's range, from `reversePlaybackEndTime` to `forwardPlaybackEndTime`: an invalid
    /// (or infinite) time is the file's start or end, and both ends are clamped to the file. A range
    /// under `minimumDuration` is refused: nil, and `Not trimmed` posts `tooShortText`.
    static func range(start: CMTime, end: CMTime, duration: CMTime) -> CMTimeRange? {
        func clamped(_ time: CMTime) -> CMTime { CMTimeMaximum(.zero, CMTimeMinimum(time, duration)) }
        let from = clamped(start.isNumeric ? start : .zero)
        let to = clamped(end.isNumeric ? end : duration)
        guard CMTimeSubtract(to, from).seconds >= minimumDuration else { return nil }
        return CMTimeRange(start: from, end: to)
    }

    // MARK: The source file

    // The Trim window reads the recording from where the editor would (`EditorInput.fileSource`): a
    // pending file, read directly; a file in the current save folder, read under the folder's scope
    // while the window is open; the uploaded object, downloaded to `downloadURL(for:)`; or nothing,
    // with the editor's reason. `fileSource` never gives `.retained` for a recording.

    // MARK: The sheet

    enum SheetButton: Equatable, Sendable {
        case save, saveAndUpload, cancel

        var title: String {
            switch self {
            case .save: "Save"
            case .saveAndUpload: "Save and Upload"
            case .cancel: "Cancel"
            }
        }
    }

    /// The save sheet: its buttons, the first the default (Return) and `Cancel` last (Escape), and the
    /// sentence a record with a link adds to the informative text.
    struct Sheet: Equatable, Sendable {
        var buttons: [SheetButton]
        var linkSentence: String?
    }

    /// The design's table, from `EditorSaveTarget.plan`, whether a destination is set and whether the
    /// record has a link (`linkURL`). Nil when there would be no button but `Cancel`: nothing to save
    /// over and no destination, where `Trim…` is disabled.
    static func sheet(plan: EditorSaveTarget.Plan, hasDestination: Bool, hasLink: Bool) -> Sheet? {
        switch plan {
        case .saveFolderFile, .pendingFile:
            guard hasDestination else {
                return Sheet(buttons: [.save, .cancel],
                             linkSentence: hasLink ? "The link keeps showing the full recording." : nil)
            }
            return hasLink
                ? Sheet(buttons: [.saveAndUpload, .save, .cancel],
                        linkSentence: "The link keeps showing the full recording unless you choose Save and Upload.")
                : Sheet(buttons: [.save, .saveAndUpload, .cancel], linkSentence: nil)
        case .unavailable:
            guard hasDestination else { return nil }
            return Sheet(buttons: [.saveAndUpload, .cancel],
                         linkSentence: hasLink ? "The link will show the trimmed recording." : nil)
        }
    }

    /// `Keeps <m:ss> of <m:ss>. The rest is cut from the file.`, then the sheet's sentence.
    static func informativeText(kept: TimeInterval, of total: TimeInterval, sheet: Sheet) -> String {
        let text = "Keeps \(RecordingClock.format(kept)) of \(RecordingClock.format(total)). The rest is cut from the file."
        guard let sentence = sheet.linkSentence else { return text }
        return "\(text) \(sentence)"
    }

    // MARK: Where Trim shows

    /// `Trim…` is offered for MP4 recordings only (design, Kind).
    static func showsTrim(_ record: CaptureRecord) -> Bool {
        record.mediaKind == .video
    }

    /// Whether `Trim…` opens the window: not while the record uploads, is deleted or is trimmed, and
    /// not while `openRefusal` gives a reason. Save and Save and Upload check again when they write
    /// (`writePlan`).
    static func canTrim(_ record: CaptureRecord, saveFolder: URL?, hasDestination: Bool, isDeleting: Bool,
                        isTrimming: Bool) -> Bool {
        guard showsTrim(record), !record.isUploading, !isDeleting, !isTrimming else { return false }
        return openRefusal(for: record, source: EditorInput.fileSource(for: record, saveFolder: saveFolder),
                           saveFolder: saveFolder, hasDestination: hasDestination) == nil
    }

    /// Why the window cannot open on the record, from its `source` (`EditorInput.fileSource`, which
    /// `trimCapture` works out once and then opens), the save folder and the destination alone, or
    /// nil: nothing to read (the source's reason), or a sheet with no button but `Cancel`, with
    /// nothing to save over and no destination (the Save target's reason). A card drawn before a
    /// change in Settings can still offer `Trim…`, so `trimCapture` posts it as `Not trimmed`.
    static func openRefusal(for record: CaptureRecord, source: EditorInput.Source, saveFolder: URL?,
                            hasDestination: Bool) -> String? {
        if case .unavailable(let reason) = source { return reason }
        let plan = EditorSaveTarget.plan(for: record, saveFolder: saveFolder)
        guard sheet(plan: plan, hasDestination: hasDestination, hasLink: record.linkURL != nil) == nil,
              case .unavailable(let reason) = plan else { return nil }
        return reason
    }

    /// The card's and the row's Trim items.
    struct MenuState: Equatable, Sendable {
        var showsTrim: Bool
        var canTrim: Bool
        /// A trimmed video whose link still shows the full recording (design, Stale link).
        var showsUploadTrimmed: Bool
        var canUploadTrimmed: Bool
        /// Retry, `Upload Trimmed` and Delete are disabled while a pass runs.
        var isTrimming: Bool

        init(showsTrim: Bool = false, canTrim: Bool = false, showsUploadTrimmed: Bool = false,
             canUploadTrimmed: Bool = false, isTrimming: Bool = false) {
            self.showsTrim = showsTrim
            self.canTrim = canTrim
            self.showsUploadTrimmed = showsUploadTrimmed
            self.canUploadTrimmed = canUploadTrimmed
            self.isTrimming = isTrimming
        }
    }

    /// `Trim…` as `showsTrim` and `canTrim` say. `Upload Trimmed` shows for an MP4 with
    /// `uploadIsStale`, a local file and a destination, and is disabled while the record uploads,
    /// is deleted or is trimmed.
    static func menuState(_ record: CaptureRecord, saveFolder: URL?, hasDestination: Bool, isDeleting: Bool,
                          isTrimming: Bool) -> MenuState {
        let showsUploadTrimmed = showsTrim(record) && record.uploadIsStale && record.hasLocalFile && hasDestination
        return MenuState(showsTrim: showsTrim(record),
                         canTrim: canTrim(record, saveFolder: saveFolder, hasDestination: hasDestination,
                                          isDeleting: isDeleting, isTrimming: isTrimming),
                         showsUploadTrimmed: showsUploadTrimmed,
                         canUploadTrimmed: showsUploadTrimmed && !record.isUploading && !isDeleting && !isTrimming,
                         isTrimming: isTrimming)
    }

    // MARK: Write-time checks

    /// What Save or Save and Upload writes, read from the live record before the export and again
    /// right before the put.
    enum WritePlan: Equatable, Sendable {
        /// Write nothing; the reason is posted as `Not trimmed`.
        case refuse(String)
        /// Put the trimmed file over the Save target.
        case saveTarget(EditorSaveTarget.Plan)
        /// Save and Upload with nothing to write over: the trimmed file becomes `pending/<id>.mp4`
        /// and the record points at it.
        case newPendingFile
    }

    /// `EditorAvailability.refusal` (`.save`, or `.upload` for Save and Upload) with `isTrimming`
    /// false, as the marker is the pass's own; then the Save target, which Save needs and Save and
    /// Upload uses when there is one (`EditorSaveTarget.uploadWrite`). A nil record was deleted or
    /// pruned. Cancel writes nothing: its plan is an empty refusal, never posted, as the sheet's
    /// Cancel closes the window first.
    static func writePlan(_ button: SheetButton, record: CaptureRecord?, saveFolder: URL?, isDeleting: Bool) -> WritePlan {
        let action: EditorAction
        switch button {
        case .save: action = .save
        case .saveAndUpload: action = .upload
        case .cancel: return .refuse("")
        }
        if let reason = EditorAvailability.refusal(for: action, record: record, saveFolder: saveFolder,
                                                   isDeleting: isDeleting, isTrimming: false) {
            return .refuse(reason)
        }
        guard let record else { return .refuse(EditorAvailability.deletedRefusal) }
        let plan = EditorSaveTarget.plan(for: record, saveFolder: saveFolder)
        if button == .saveAndUpload, EditorSaveTarget.uploadWrite(for: record, saveFolder: saveFolder) == .newPendingFile {
            return .newPendingFile
        }
        if case .unavailable(let reason) = plan { return .refuse(reason) }
        return .saveTarget(plan)
    }

    /// After the put, with the record read once more.
    enum AfterPut: Equatable, Sendable {
        /// The record is there: record the trim (`finishTrimWrite`).
        case finish
        /// The record was pruned during the put: remove the pending file it wrote, as pruning does.
        case removePendingFile(URL)
        /// The record was pruned: a save-folder file stays, as pruning leaves those alone.
        case keepFile
    }

    /// `fileURL` is the file the put wrote. Delete cannot have run, as it refuses while the marker
    /// is set, but pruning does not read the marker.
    static func afterPut(_ plan: WritePlan, fileURL: URL, recordExists: Bool) -> AfterPut {
        guard !recordExists else { return .finish }
        switch plan {
        case .saveTarget(.pendingFile), .newPendingFile: return .removePendingFile(fileURL)
        case .saveTarget, .refuse: return .keepFile
        }
    }

    /// Where the put writes the trimmed file.
    enum PutTarget: Equatable, Sendable {
        /// Over the Save target with `FileReplacement`, holding `scope` (the save folder's for a
        /// save-folder file; none for `pending/<id>.mp4`).
        case replace(URL, scope: URL?)
        /// Moved in as `pending/<id>.mp4`, and the record points at it.
        case newPendingFile
    }

    /// The put for a plan the write-time checks let through; nil for one they refuse.
    static func putTarget(for plan: WritePlan) -> PutTarget? {
        switch plan {
        case .saveTarget(.saveFolderFile(let fileURL, let folder)): .replace(fileURL, scope: folder)
        case .saveTarget(.pendingFile(let fileURL)): .replace(fileURL, scope: nil)
        case .newPendingFile: .newPendingFile
        case .saveTarget(.unavailable), .refuse: nil
        }
    }

    /// The put over a Save target (design, Save): `trimmed` is moved into `destination`'s replacement
    /// folder and swapped in with `replaceItemAt`, as `FileReplacement` does, holding `scope` throughout.
    /// A failed put leaves the file at `destination` as it was. Runs in a detached task.
    static func putTrimmed(_ trimmed: URL, over destination: URL, scope: URL?) throws {
        let accessing = scope?.startAccessingSecurityScopedResource() ?? false
        defer { if accessing { scope?.stopAccessingSecurityScopedResource() } }
        try FileReplacement.put(at: destination) { try FileManager.default.moveItem(at: trimmed, to: $0) }
    }

    /// Whether the pass sets `uploadIsStale` before its put: the record has a link (`linkURL`, so also
    /// one kept only in `priorUpload`) that is not marked stale already. A failed put clears only what
    /// its pass set.
    static func putMarksLinkStale(_ record: CaptureRecord) -> Bool {
        record.linkURL != nil && !record.uploadIsStale
    }

    /// The button the save sheet's response chose, by its index among `buttons` (0 for the first).
    /// Any other response, as when the window closes under the sheet, is `Cancel`.
    static func sheetButton(at index: Int, of buttons: [SheetButton]) -> SheetButton {
        buttons.indices.contains(index) ? buttons[index] : .cancel
    }

    // MARK: Failure and cleanup

    /// `Not trimmed`'s body for a full disk (design, Failure).
    static let diskFullText = "Disk Full"

    /// `Not trimmed`'s body for a failed download, export or put: `Disk Full` for a full disk, else the
    /// error's own text.
    static func failureText(for error: any Error) -> String {
        isDiskFull(error) ? diskFullText : error.localizedDescription
    }

    /// Out of space, from Foundation, POSIX or AVFoundation, also as an underlying error.
    static func isDiskFull(_ error: any Error) -> Bool {
        let error = error as NSError
        switch (error.domain, error.code) {
        case (NSCocoaErrorDomain, NSFileWriteOutOfSpaceError), (NSPOSIXErrorDomain, Int(ENOSPC)),
             (AVFoundationErrorDomain, AVError.Code.diskFull.rawValue):
            return true
        default:
            return (error.userInfo[NSUnderlyingErrorKey] as? NSError).map { isDiskFull($0) } ?? false
        }
    }

    /// Removes `tmp/Trim/<id>*` (design, Cleanup): the download and whatever a failed or stopped step
    /// left. Another record's files stay. A folder that is missing is nothing to remove.
    static func removeWorkFiles(of id: UUID, in folder: URL = RecordingTrim.directory) {
        let fileManager = FileManager.default
        let names = (try? fileManager.contentsOfDirectory(atPath: folder.path(percentEncoded: false))) ?? []
        for name in names where name.hasPrefix(id.uuidString) {
            try? fileManager.removeItem(at: folder.appending(path: name, directoryHint: .notDirectory))
        }
    }

    /// How the export cuts (design, Method): `.passthrough` when the start is on a sync sample,
    /// else `.reencode`.
    enum TrimMethod: Equatable, Sendable {
        case passthrough, reencode
    }
}
