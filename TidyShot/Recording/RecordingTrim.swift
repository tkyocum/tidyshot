import AVFoundation
import CoreMedia
import Foundation

/// Why a trim's range was refused (design, Trim): the part kept would be under
/// `RecordingTrim.minimumDuration`.
nonisolated enum TrimRefusal: Error, Equatable, Sendable {
    case tooShort

    /// The body of `Not trimmed`.
    var message: String {
        switch self {
        case .tooShort: RecordingTrim.tooShortText
        }
    }
}

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
/// once the live record is read again; and the export, off the main actor. `AppCoordinator` does the
/// rest of the I/O.
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
    /// under `minimumDuration` is refused.
    static func range(start: CMTime, end: CMTime, duration: CMTime) -> Result<CMTimeRange, TrimRefusal> {
        func clamped(_ time: CMTime) -> CMTime { CMTimeMaximum(.zero, CMTimeMinimum(time, duration)) }
        let from = clamped(start.isNumeric ? start : .zero)
        let to = clamped(end.isNumeric ? end : duration)
        guard CMTimeSubtract(to, from).seconds >= minimumDuration else { return .failure(.tooShort) }
        return .success(CMTimeRange(start: from, end: to))
    }

    // MARK: The source file

    /// Where the Trim window reads the recording from.
    enum Source: Equatable, Sendable {
        /// `pending/<id>.mp4`, read directly.
        case pendingFile(URL)
        /// A file inside the current save folder, read under that folder's scope while the window is open.
        case saveFolderFile(URL, folder: URL)
        /// The uploaded object, downloaded to `downloadURL(for:)`.
        case download(key: String, location: ObjectLocation)
        /// Nothing to read, with `EditorInput`'s reason.
        case unavailable(String)
    }

    /// `EditorInput.fileSource`, so Trim keeps the editor's order and texts: a pending file; a file
    /// in the current save folder, with that folder; the uploaded object when its location is known
    /// (also for a file outside the folder, or with no folder); otherwise unavailable.
    static func source(for record: CaptureRecord, saveFolder: URL?) -> Source {
        switch (EditorInput.fileSource(for: record, saveFolder: saveFolder), saveFolder) {
        case (.pendingFile(let fileURL), _): .pendingFile(fileURL)
        case (.saveFolderFile(let fileURL), let folder?): .saveFolderFile(fileURL, folder: folder)
        case (.download(let key, let location), _): .download(key: key, location: location)
        case (.unavailable(let reason), _): .unavailable(reason)
        // `fileSource` gives neither: a save-folder file comes only with a folder, and the
        // retained image is the editor's own. Nothing to read, as for a file outside the folder.
        case (.saveFolderFile, nil), (.retained, _): .unavailable(EditorInput.outsideSaveFolderText)
        }
    }

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

    /// Whether `Trim…` opens the window: not while the record uploads, is deleted or is trimmed,
    /// not with nothing to read, and not when the sheet would have no button. Save and Save and
    /// Upload check again when they write (`writePlan`).
    static func canTrim(_ record: CaptureRecord, saveFolder: URL?, hasDestination: Bool, isDeleting: Bool,
                        isTrimming: Bool) -> Bool {
        guard showsTrim(record), !record.isUploading, !isDeleting, !isTrimming else { return false }
        if case .unavailable = source(for: record, saveFolder: saveFolder) { return false }
        return sheet(plan: EditorSaveTarget.plan(for: record, saveFolder: saveFolder),
                     hasDestination: hasDestination, hasLink: record.linkURL != nil) != nil
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

    /// How the export cuts (design, Method): `.passthrough` when the start is on a sync sample,
    /// else `.reencode`.
    enum TrimMethod: Equatable, Sendable {
        case passthrough, reencode
    }

    // MARK: The method

    /// Whether the video sample shown at `start`, in the asset's time, is a full sync sample, so a
    /// passthrough from there keeps no earlier frame (design, Method). A sample cursor works in media
    /// time, and a recording's video track starts with an edit to a later media time, so `start` is
    /// mapped through the track's edit list first (Decided 2026-10-24, 3). A start in an empty edit or
    /// outside every edit, and a track that cannot give a cursor, are false: doubt re-encodes.
    @concurrent
    static func startsOnSyncSample(_ url: URL, at start: CMTime) async throws -> Bool {
        let asset = AVURLAsset(url: url, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])
        guard let track = try await asset.loadTracks(withMediaType: .video).first else {
            throw RecordingTrimError.couldNotRead
        }
        let (canProvideCursors, segments) = try await track.load(.canProvideSampleCursors, .segments)
        let mappings = segments.map { segment in
            segment.isEmpty ? CMTimeMapping(source: .invalid, target: segment.timeMapping.target) : segment.timeMapping
        }
        guard canProvideCursors, let media = mediaTime(of: start, through: mappings),
              let cursor = track.makeSampleCursor(presentationTimeStamp: media) else { return false }
        // The cursor's sample is the one shown at that time only when it starts at or before it.
        return CMTimeCompare(cursor.presentationTimeStamp, media) <= 0
            && cursor.currentSampleSyncInfo.sampleIsFullSync.boolValue
    }

    /// `time`, on a track's timeline, as the media time its edit list shows there: the segment whose
    /// target range holds it gives its source start plus how far into the segment `time` is, scaled
    /// by the segment's rate. Nil in an empty edit (a source with no numeric start) and outside every
    /// segment.
    static func mediaTime(of time: CMTime, through mappings: [CMTimeMapping]) -> CMTime? {
        guard time.isNumeric,
              let mapping = mappings.first(where: { $0.target.isValid && $0.target.containsTime(time) }),
              mapping.source.isValid, mapping.source.start.isNumeric, mapping.source.duration.isNumeric else {
            return nil
        }
        return CMTimeMapTimeFromRangeToRange(time, fromRange: mapping.target, toRange: mapping.source)
    }

    // MARK: The export for Save

    /// What a pass writes in its folder, before the 1 GB `RecordingLimits.hasRoom` adds (design, Disk
    /// space): the source's size for a passthrough, twice that for a re-encode, which can come out
    /// larger than its source (Decided 2026-10-24, 2), and the source's size again for the mute step's
    /// copy.
    static func bytesNeeded(sourceBytes: Int64, method: TrimMethod, mutes: Bool) -> Int64 {
        sourceBytes * (method == .reencode ? 2 : 1) + (mutes ? sourceBytes : 0)
    }

    /// Save's export (design, Export, Disk space, Cleanup). It makes `directory` when it is missing
    /// (the launch clears `tmp/Trim`, and a pending or save-folder source downloads nothing into it),
    /// then refuses with `notEnoughSpace` before writing anything unless `freeBytes` leaves room for
    /// `bytesNeeded` plus 1 GB. A record with `unmutedIntervals` is muted first, with
    /// `RecordingMute.apply` into `<id>-muted.mp4`, and that copy trimmed, so its muted sound never
    /// reaches the trimmed file. It returns `<id>-trimmed.mp4`. `<id>-muted.mp4` is gone on every
    /// exit, and a failed or cancelled export removes its own output. `source` is only read.
    /// `directory` is for tests.
    @concurrent
    static func exportForSave(_ source: URL, id: UUID, range: CMTimeRange, method: TrimMethod,
                              unmutedIntervals: [MuteInterval], directory: URL = RecordingTrim.directory,
                              freeBytes: @escaping @Sendable () -> Int64?,
                              progress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        let trimmed = trimmedURL(for: id, in: directory)
        let muted = mutedURL(for: id, in: directory)
        // Each step clears its output first, so neither may be the recording.
        guard !isSameFile(source, trimmed), !isSameFile(source, muted) else { throw RecordingTrimError.couldNotWrite }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: muted) }
        let mutes = !unmutedIntervals.isEmpty
        let sourceBytes = Int64(FileSizes.byteCount(of: source) ?? 0)
        guard RecordingLimits.hasRoom(for: bytesNeeded(sourceBytes: sourceBytes, method: method, mutes: mutes),
                                      freeBytes: freeBytes()) else {
            throw RecordingTrimError.notEnoughSpace
        }
        var input = source
        if mutes {
            try await RecordingMute.apply(source, intervals: unmutedIntervals, to: muted)
            input = muted
        }
        try await export(input, range: range, method: method, to: trimmed, progress: progress)
        return trimmed
    }

    // MARK: The export

    /// Writes `range` of `source` to `output` as an MP4 (design, Export): `.passthrough` with an
    /// `AVAssetExportSession`, or `.reencode` with TidyShot's own pass. `progress` gets fractions
    /// that never decrease, then 1 once the file is written; a passthrough reports only the 1.
    /// `output`'s folder is made when it is missing, and any file there is replaced. A throw or a
    /// cancel removes what was written. `source` is only read.
    @concurrent
    static func export(_ source: URL, range: CMTimeRange, method: TrimMethod, to output: URL,
                       progress: @escaping @Sendable (Double) -> Void) async throws {
        guard !isSameFile(source, output) else { throw RecordingTrimError.couldNotWrite }
        guard range.isValid, range.start.isNumeric, range.duration.isNumeric, range.duration > .zero else {
            throw RecordingTrimError.couldNotRead
        }
        try FileManager.default.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: output)
        do {
            try Task.checkCancellation()
            switch method {
            case .passthrough: try await passthrough(source, range: range, to: output)
            case .reencode: try await reencode(source, range: range, to: output, progress: progress)
            }
        } catch {
            try? FileManager.default.removeItem(at: output)
            if Task.isCancelled { throw CancellationError() }
            throw error
        }
        progress(1)
    }

    /// Whether two file URLs name the same file, symbolic links resolved.
    private static func isSameFile(_ one: URL, _ other: URL) -> Bool {
        one.standardizedFileURL.resolvingSymlinksInPath().path(percentEncoded: false)
            == other.standardizedFileURL.resolvingSymlinksInPath().path(percentEncoded: false)
    }

    /// The design's `.passthrough`: the samples from the sync sample shown at the start, copied, with
    /// at most two AAC packets of audio before the start, hidden by the edit list (Decided 2026-10-23, 3).
    private static func passthrough(_ source: URL, range: CMTimeRange, to output: URL) async throws {
        guard let session = AVAssetExportSession(asset: AVURLAsset(url: source),
                                                 presetName: AVAssetExportPresetPassthrough) else {
            throw RecordingTrimError.couldNotWrite
        }
        session.timeRange = range
        try await session.export(to: output, as: .mp4)
    }

    // MARK: The re-encode

    private typealias Sample = CMReadySampleBuffer<CMSampleBuffer.DynamicContent>

    /// The design's `.reencode` (Decided 2026-10-24, 1 and 4), built as `RecordingMute.apply` is: one
    /// reader limited to `range`, one writer, and a task per track. The first video track is decoded
    /// and encoded again as H.264 at the source's size; the first audio track is read as stored,
    /// decoded by `AudioDecoder`, cut at the range's ends to the frame and encoded again as AAC. So
    /// nothing from before the start is in the file. The session runs from 0 to the range's duration.
    private static func reencode(_ source: URL, range: CMTimeRange, to output: URL,
                                 progress: @escaping @Sendable (Double) -> Void) async throws {
        let asset = AVURLAsset(url: source)
        guard let videoTrack = try await asset.loadTracks(withMediaType: .video).first else {
            throw RecordingTrimError.couldNotRead
        }
        let audioTrack = try await asset.loadTracks(withMediaType: .audio).first
        let reader = try AVAssetReader(asset: asset)
        reader.timeRange = range
        let writer = try AVAssetWriter(outputURL: output, fileType: .mp4)

        let (formats, transform, dataRate, dataLength, videoRange) = try await videoTrack.load(
            .formatDescriptions, .preferredTransform, .estimatedDataRate, .totalSampleDataLength, .timeRange)
        guard let videoFormat = formats.first else { throw RecordingTrimError.couldNotRead }
        let bitRate = averageBitRate(estimated: dataRate, bytes: dataLength, over: videoRange.duration)
        // `AVAssetWriterInput` raises on settings it cannot take, so they are asked about first.
        guard let settings = videoSettings(for: videoFormat, bitRate: bitRate).first(where: {
            writer.canApply(outputSettings: $0, forMediaType: .video)
        }) else { throw RecordingTrimError.couldNotWrite }
        let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        videoInput.transform = transform
        videoInput.expectsMediaDataInRealTime = false
        let videoOutput = AVAssetReaderTrackOutput(track: videoTrack, outputSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
        ])
        videoOutput.alwaysCopiesSampleData = false
        let video = VideoCut(provider: reader.outputProvider(for: videoOutput),
                             receiver: writer.inputReceiver(for: videoInput), range: range, progress: progress)

        var audio: AudioCut?
        if let audioTrack {
            let (formats, audioRange) = try await audioTrack.load(.formatDescriptions, .timeRange)
            guard let format = formats.first,
                  let description = CMAudioFormatDescriptionGetStreamBasicDescription(format)?.pointee else {
                throw RecordingTrimError.couldNotRead
            }
            let decoder = try AudioDecoder(format: format, end: audioRange.end)
            let audioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: description.mSampleRate,
                AVNumberOfChannelsKey: Int(description.mChannelsPerFrame),
                AVEncoderBitRateKey: RecordingMute.audioBitRate,
            ])
            audioInput.expectsMediaDataInRealTime = false
            audio = AudioCut(provider: reader.outputProvider(for: AVAssetReaderTrackOutput(track: audioTrack, outputSettings: nil)),
                             receiver: writer.inputReceiver(for: audioInput), decoder: decoder,
                             frames: try frames(of: range, rate: description.mSampleRate), rate: description.mSampleRate)
        }

        try reader.start()
        try writer.start()
        writer.startSession(atSourceTime: .zero)
        do {
            try await run(video, audio)
        } catch {
            // Only once neither track reads or appends, as in `RecordingMute.apply`.
            reader.cancelReading()
            writer.cancelWriting()
            throw error
        }
        guard reader.status != .failed else {
            writer.cancelWriting()
            throw reader.error ?? RecordingTrimError.couldNotRead
        }
        // A track that reached the range's end can leave samples unread.
        reader.cancelReading()
        writer.endSession(atSourceTime: range.duration)
        await writer.finishWriting()
        guard writer.status == .completed else {
            throw writer.error ?? RecordingTrimError.couldNotWrite
        }
    }

    /// The video's average bit rate: its estimated data rate, or its sample data over its duration
    /// when that is 0. Nil when neither is known, which leaves the encoder its own.
    static func averageBitRate(estimated: Float, bytes: Int64, over duration: CMTime) -> Int? {
        if estimated.isFinite, estimated >= 1 { return Int(estimated) }
        guard bytes > 0, duration.isNumeric, duration.seconds > 0 else { return nil }
        return Int(Double(bytes) * 8 / duration.seconds)
    }

    /// The re-encode's H.264 settings at `format`'s encoded size (design, `.reencode`): High profile,
    /// `bitRate` on average, a sync frame at least every 2 s and no frame reordering. First with the
    /// source's colour primaries, transfer function and YCbCr matrix when its format description
    /// carries all three, then without them, for a writer that cannot apply them.
    static func videoSettings(for format: CMFormatDescription, bitRate: Int?) -> [[String: Any]] {
        let size = CMVideoFormatDescriptionGetDimensions(format)
        var compression: [String: Any] = [
            AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
            AVVideoMaxKeyFrameIntervalDurationKey: 2,
            AVVideoAllowFrameReorderingKey: false,
        ]
        if let bitRate { compression[AVVideoAverageBitRateKey] = bitRate }
        let plain: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: Int(size.width),
            AVVideoHeightKey: Int(size.height),
            AVVideoCompressionPropertiesKey: compression,
        ]
        func colour(_ key: CFString) -> String? {
            CMFormatDescriptionGetExtension(format, extensionKey: key) as? String
        }
        guard let primaries = colour(kCMFormatDescriptionExtension_ColorPrimaries),
              let transfer = colour(kCMFormatDescriptionExtension_TransferFunction),
              let matrix = colour(kCMFormatDescriptionExtension_YCbCrMatrix) else { return [plain] }
        var coloured = plain
        coloured[AVVideoColorPropertiesKey] = [
            AVVideoColorPrimariesKey: primaries,
            AVVideoTransferFunctionKey: transfer,
            AVVideoYCbCrMatrixKey: matrix,
        ]
        return [coloured, plain]
    }

    /// `range` in whole frames at `rate`, as `AudioDecoder` places them: from the frame at its start to
    /// the one at its end.
    static func frames(of range: CMTimeRange, rate: Double) throws -> Range<Int> {
        let start = (range.start.seconds * rate).rounded()
        let end = (range.end.seconds * rate).rounded()
        guard range.start.isNumeric, range.end.isNumeric, start >= 0, end >= start, end <= 0x1p53 else {
            throw RecordingTrimError.couldNotRead
        }
        return Int(start)..<Int(end)
    }

    /// Runs both tracks, each on a task of its own. At the first failure, or a cancel, the other
    /// track's task is cancelled and ends at its next sample; the failure is thrown once both have
    /// ended (`RecordingMute.apply`, A failure partway).
    private static func run(_ video: VideoCut, _ audio: AudioCut?) async throws {
        // Each track goes to its own task, and nothing here touches it again.
        nonisolated(unsafe) let video = video
        nonisolated(unsafe) let audio = audio
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask { try await video.run() }
            if audio != nil {
                group.addTask { try await audio?.run() }
            }
            do {
                while try await group.next() != nil {}
            } catch {
                group.cancelAll()
                throw error
            }
        }
    }

    /// The video's way through a re-encode: decoded frames, each written at its presentation time
    /// minus the range's start, the frame shown at the start at 0, and none from before it or from the
    /// range's end on. Each is shown until the next or the range's end, so a last frame held over a
    /// still screen lasts to the end. `progress` gets the last written frame's time over the range's
    /// duration, at most every 0.1 s and never less than before.
    private struct VideoCut {
        let provider: AVAssetReaderOutput.Provider<Sample>
        let receiver: AVAssetWriterInput.SampleBufferReceiver
        let range: CMTimeRange
        let progress: @Sendable (Double) -> Void

        /// Writes the frames, then finishes the input. A failure finishes it too, so the writer stops
        /// holding the other track back for it. A range with no frame to show throws, rather than give
        /// a file with no picture.
        func run() async throws {
            do {
                // The latest frame at or before the start: the one shown there.
                var shown: Sample?
                var last: CMTime?
                var reported = 0.0
                var reportedAt: ContinuousClock.Instant?
                while true {
                    // Before each read, as in `RecordingMute.apply`.
                    try Task.checkCancellation()
                    guard let read = try await provider.next() else { break }
                    let time = read.presentationTimeStamp
                    guard read.withUnsafeSampleBuffer({ CMSampleBufferGetImageBuffer($0) != nil }), time.isNumeric else {
                        continue
                    }
                    if time <= range.start {
                        shown = read
                        continue
                    }
                    guard time < range.end else { break }
                    if let frame = shown {
                        last = try await write(frame, at: .zero, after: last)
                        shown = nil
                    }
                    last = try await write(read, at: time - range.start, after: last)
                    let fraction = (time - range.start).seconds / range.duration.seconds
                    let now = ContinuousClock.now
                    if fraction > reported, fraction < 1, reportedAt.map({ now - $0 >= .milliseconds(100) }) ?? true {
                        progress(fraction)
                        reported = fraction
                        reportedAt = now
                    }
                }
                if let frame = shown {
                    last = try await write(frame, at: .zero, after: last)
                }
                guard last != nil else { throw RecordingTrimError.couldNotRead }
            } catch {
                receiver.finish()
                throw error
            }
            receiver.finish()
        }

        /// Appends `frame` retimed to `time`, unless that is not after `last`; gives the last time
        /// written. Its duration runs to the range's end: the writer takes a frame's duration from the
        /// next one's time, so only the last keeps it, and without it the last lasts as long as the one
        /// before it.
        private func write(_ frame: Sample, at time: CMTime, after last: CMTime?) async throws -> CMTime? {
            if let last, time <= last { return last }
            let retimed = try frame.withUnsafeSampleBuffer { buffer -> CMSampleBuffer in
                let timing = CMSampleTimingInfo(duration: range.duration - time, presentationTimeStamp: time,
                                                decodeTimeStamp: .invalid)
                let copy = try CMSampleBuffer(copying: buffer, withNewTiming: [timing])
                // A new buffer: nothing else holds it.
                nonisolated(unsafe) let made = copy
                return made
            }
            nonisolated(unsafe) let made = retimed
            try await receiver.append(Sample(unsafeBuffer: made))
            return time
        }
    }

    /// The sound's way through a re-encode: packets as stored, decoded by `AudioDecoder`, and only the
    /// frames from the range's start to its end, moved back by the start, so the sound starts and ends
    /// with the range to the frame (Decided 2026-10-24, 4).
    private struct AudioCut {
        let provider: AVAssetReaderOutput.Provider<Sample>
        let receiver: AVAssetWriterInput.SampleBufferReceiver
        let decoder: AudioDecoder
        /// The range in frames at the source's rate.
        let frames: Range<Int>
        let rate: Double

        /// Appends the range's sound, then finishes the input. A failure finishes it too.
        func run() async throws {
            do {
                var ended = false
                while !ended {
                    try Task.checkCancellation()
                    guard let read = try await provider.next() else { break }
                    try decoder.decode(read)
                    ended = try await appendDecoded()
                }
                if !ended {
                    // Silence to the track's end, where an empty edit ends the sound.
                    try Task.checkCancellation()
                    try decoder.finish()
                    _ = try await appendDecoded()
                }
            } catch {
                receiver.finish()
                throw error
            }
            receiver.finish()
        }

        /// Appends what `decoder` holds inside the range; true once it reaches the range's end, after
        /// which nothing more is wanted.
        private func appendDecoded() async throws -> Bool {
            while let sample = try decoder.nextBuffer() {
                try Task.checkCancellation()
                if let inside = try RecordingTrim.cut(sample, to: frames, rate: rate) {
                    try await receiver.append(inside)
                }
                let first = Int((sample.presentationTimeStamp.seconds * rate).rounded())
                if first + sample.sampleCount >= frames.upperBound { return true }
            }
            return false
        }
    }

    /// The frames of `sample`, a PCM buffer of the decoder's, that fall inside `frames`, copied and
    /// moved back by its lower bound; nil when none does.
    private static func cut(_ sample: Sample, to frames: Range<Int>, rate: Double) throws -> Sample? {
        let inside = try sample.withUnsafeSampleBuffer { buffer -> CMSampleBuffer? in
            guard let format = buffer.formatDescription,
                  let description = CMAudioFormatDescriptionGetStreamBasicDescription(format)?.pointee,
                  description.mBytesPerFrame > 0, buffer.presentationTimeStamp.isNumeric,
                  let data = buffer.dataBuffer else { throw RecordingTrimError.couldNotRead }
            let first = Int((buffer.presentationTimeStamp.seconds * rate).rounded())
            let lower = max(first, frames.lowerBound)
            let upper = min(first + buffer.numSamples, frames.upperBound)
            guard upper > lower else { return nil }
            let bytesPerFrame = Int(description.mBytesPerFrame)
            let offset = (lower - first) * bytesPerFrame
            let length = (upper - lower) * bytesPerFrame
            let block = try CMBlockBuffer(length: length, flags: .assureMemoryNow)
            try block.withUnsafeMutableBytes { destination in
                try data.withContiguousStorage { source in
                    guard let to = destination.baseAddress, let from = source.baseAddress,
                          offset + length <= source.count else { throw RecordingTrimError.couldNotRead }
                    memcpy(to, from + offset, length)
                }
            }
            let cut = try CMSampleBuffer(dataBuffer: block, formatDescription: format, numSamples: upper - lower,
                                         presentationTimeStamp: CMTime(value: CMTimeValue(lower - frames.lowerBound),
                                                                       timescale: CMTimeScale(rate)),
                                         packetDescriptions: [])
            // A new buffer over a new block: nothing else holds it.
            nonisolated(unsafe) let made: CMSampleBuffer? = cut
            return made
        }
        guard let inside else { return nil }
        nonisolated(unsafe) let made = inside
        return Sample(unsafeBuffer: made)
    }
}
