import AppKit
import ImageIO

// Launch recovery: what a crash, a kill or a failed rename left in pending/ and tmp/Recording (recording design, Relaunch after a crash; harness design 4.2). Its state is declared in AppCoordinator.swift.
extension AppCoordinator {
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
