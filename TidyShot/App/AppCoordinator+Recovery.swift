import AppKit
import ImageIO

// Launch recovery: what a crash, a kill or a failed rename left in pending/ and tmp/Recording (recording design, Relaunch after a crash; harness design 4.2). Its state is declared in AppCoordinator.swift.
extension AppCoordinator {
    /// The `pending/` launch step (harness design 4.2): each file of `listed` named `<record id>.<png|mp4|gif>`
    /// whose id no record has gets a record, as a leftover recording in `tmp/Recording` does: `.none` and
    /// `fileIsTemporary`, so it is kept until the user acts on it, timestamped with the file's creation
    /// date, with a thumbnail and `Recovered a capture` or `Recovered a recording`, and no card. A file
    /// that is empty or cannot be read is removed; nothing else is. Only `listed` is considered, so a file
    /// written after `start()` listed the folder is never touched, and the records are read again before
    /// each record is made, so a file a record names by then is left alone.
    func adoptPendingFiles(_ listed: [URL]) async {
        for found in PendingRecovery.orphans(listed: listed, recordIDs: Set(history.records.map(\.id))) {
            let name = found.url.lastPathComponent
            let read = await Self.readPendingFile(found)
            // A capture or a recovery may have made its record during the read.
            guard history.record(id: found.id) == nil else { continue }
            let contents: PendingFileContents
            switch read {
            case .readable(let readable):
                contents = readable
            case .empty:
                removeUnadoptable(found.url, reason: "is empty")
                continue
            case .unreadable:
                removeUnadoptable(found.url, reason: "could not be read")
                continue
            }
            let record = CaptureRecord(id: found.id, timestamp: contents.created ?? environment.now(),
                                       fileURL: found.url, fileIsTemporary: true,
                                       pixelWidth: contents.pixelWidth, pixelHeight: contents.pixelHeight,
                                       appName: nil, uploadState: .none, mediaKind: found.kind,
                                       durationSeconds: contents.durationSeconds, byteCount: contents.byteCount)
            history.add(record)
            if let thumbnail = contents.thumbnail {
                makeThumbnail(from: thumbnail, for: found.id)
            }
            log("Recovery: \(name) recovered")
            if let duration = contents.durationSeconds {
                notifier.notifyError("\(name), \(RecordingClock.format(duration)). Find it in Recent Captures.",
                                     title: "Recovered a recording")
            } else {
                notifier.notifyError("\(name). Find it in Recent Captures.", title: "Recovered a capture")
            }
        }
    }

    /// Removes an orphan that cannot be adopted, and says why.
    private func removeUnadoptable(_ url: URL, reason: String) {
        do {
            try pendingFiles.remove(url)
            log("Recovery: \(url.lastPathComponent) \(reason), removed")
        } catch {
            log("Recovery: \(url.lastPathComponent) \(reason), and could not be removed: \(error.localizedDescription)")
        }
    }

    /// What an orphan holds, read off the main actor: an image's size and pixels and a GIF's size,
    /// length and first frame through ImageIO (AVFoundation does not open a GIF), a recording's facts
    /// and poster as the launch check reads `tmp/Recording`'s.
    @concurrent
    nonisolated private static func readPendingFile(_ found: PendingRecovery.Found) async -> PendingFileRead {
        let url = found.url
        let values = try? url.resourceValues(forKeys: [.fileSizeKey, .creationDateKey])
        guard let byteCount = values?.fileSize else { return .unreadable }
        guard byteCount > 0 else { return .empty }
        let created = values?.creationDate
        switch found.kind {
        case .image, .gif:
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return .unreadable }
            return .readable(PendingFileContents(pixelWidth: image.width, pixelHeight: image.height,
                                                 durationSeconds: found.kind == .gif ? gifDuration(of: source) : nil,
                                                 byteCount: byteCount, created: created, thumbnail: image))
        case .video:
            let facts = await VideoValidation.inspect(url)
            guard facts.isPlayable, facts.videoTracks > 0 else { return .unreadable }
            let size = facts.naturalSize ?? .zero
            return .readable(PendingFileContents(pixelWidth: Int(size.width.rounded()),
                                                 pixelHeight: Int(size.height.rounded()),
                                                 durationSeconds: facts.duration, byteCount: byteCount,
                                                 created: created, thumbnail: await PosterFrame.image(of: url)))
        }
    }

    /// A GIF's length: the sum of its frames' delays.
    nonisolated private static func gifDuration(of source: CGImageSource) -> Double {
        (0..<CGImageSourceGetCount(source)).reduce(0) { total, index in
            let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any]
            let gif = properties?[kCGImagePropertyGIFDictionary] as? [CFString: Any]
            let delay = gif?[kCGImagePropertyGIFUnclampedDelayTime] as? Double
                ?? gif?[kCGImagePropertyGIFDelayTime] as? Double ?? 0
            return total + delay
        }
    }

    /// The launch check (design, Relaunch after a crash), after `history.load()`. Each playable file
    /// in `tmp/Recording` moves to `pending/<id>.mp4` and gets a record kept until it is deleted
    /// (`fileIsTemporary`, `.none`), timestamped with the file's creation date, sized from the moved
    /// file's attributes, with its poster as the thumbnail; `Recovered a recording` posts and no
    /// card shows. The id is the name's UUID unless a record has it. A file whose move fails stays
    /// for the next launch. An MP4 whose GIF was saved already (`isSavedAsGIF`) is removed instead.
    /// Before its move, a file with a mute log goes through the mute ladder with the same live steps
    /// as the end of a recording (`RecordingRecovery.prepare`): its record is marked when the
    /// muting failed, the body says how it went, and the log goes once the record exists. After
    /// the loop, of what `tmp/Mute` held before it, only what belongs to a file still in
    /// `tmp/Recording` is kept; what was written since is not touched (Decided 2026-10-24, 6).
    func recoverRecordings() async {
        let ext = MediaKind.video.fileExtension
        // `tmp/Mute` is listed before the scan and the loop, which can run long after launch: the
        // sweep never removes the log of a recording made since, even one muted before its first frame.
        let (muteFiles, foundFiles) = await RecordingRecovery.begin(recordingDirectory: Recording.directory,
                                                                    muteDirectory: MuteLog.directory)
        for found in foundFiles {
            let (source, pending) = (found.url, pendingFiles)
            let prepared = await RecordingRecovery.prepare(found, records: history.records,
                                                           muteDirectory: MuteLog.directory) { file, duration, intervals, lag in
                // `prepare` runs the ladder only for a file named by its UUID, which has a log.
                await RecordingMute.resolve(file: file, output: RecordingMute.rewriteURL(for: found.id ?? UUID()),
                                            duration: duration, intervals: intervals, lag: lag, steps: .live)
            }
            guard case .recover(let unmutedIntervals, let bodySuffix, let removesLog) = prepared else {
                let removed = await Task.detached(priority: .utility) { try FileManager.default.removeItem(at: source) }.result
                if case .failure(let error) = removed {
                    RecordingLog.note("Recording: \(source.lastPathComponent) was saved as a GIF and could not be removed: \(error.localizedDescription)")
                } else {
                    RecordingLog.note("Recording: \(source.lastPathComponent) was saved as a GIF, removed")
                }
                continue
            }
            // Read before the move, so only the rename comes between the move and the record.
            let poster = await PosterFrame.image(of: source)
            let id = found.id.flatMap { history.record(id: $0) == nil ? $0 : nil } ?? UUID()
            // The size is the moved file's: after a mute step, the rewritten one's.
            let moved = await Task.detached(priority: .utility) { () throws -> (url: URL, byteCount: Int?) in
                let url = try pending.moveIn(source, id: id, ext: ext)
                return (url, FileSizes.byteCount(of: url))
            }.result
            guard case .success(let (fileURL, byteCount)) = moved else {
                if case .failure(let error) = moved {
                    RecordingLog.note("Recording: \(source.lastPathComponent) could not be recovered, kept for the next launch: \(error.localizedDescription)")
                }
                continue
            }
            let size = found.facts.naturalSize ?? .zero
            let record = CaptureRecord(id: id, timestamp: found.created, fileURL: fileURL, fileIsTemporary: true,
                                       pixelWidth: Int(size.width.rounded()), pixelHeight: Int(size.height.rounded()),
                                       appName: nil, uploadState: .none,
                                       mediaKind: .video, durationSeconds: found.facts.duration, byteCount: byteCount,
                                       unmutedIntervals: unmutedIntervals)
            history.add(record)
            // By the file name's UUID, not the record's id, which can be a fresh one.
            if removesLog, let logID = found.id {
                Recording.removeFile(at: MuteLog.url(for: logID))
            }
            if let poster {
                makeThumbnail(from: poster, for: id)
            }
            RecordingLog.note("Recording: \(source.lastPathComponent) recovered as \(fileURL.lastPathComponent)")
            let body = "\(fileURL.lastPathComponent), \(RecordingClock.format(found.facts.duration)). Find it in Recent Captures."
            notifier.notifyError(bodySuffix.map { "\(body) \($0)" } ?? body, title: "Recovered a recording")
        }
        let recordings = Recording.directory
        await Task.detached(priority: .utility) {
            RecordingRecovery.sweepMuteFolder(muteFiles, recordingDirectory: recordings)
        }.value
    }
}

/// What `adoptPendingFiles` read from an orphan.
private nonisolated enum PendingFileRead: Sendable {
    case readable(PendingFileContents)
    case empty
    case unreadable
}

/// An orphan's facts for its record, and the image its thumbnail is made from.
private nonisolated struct PendingFileContents: Sendable {
    var pixelWidth: Int
    var pixelHeight: Int
    var durationSeconds: Double?
    var byteCount: Int
    var created: Date?
    var thumbnail: CGImage?
}
