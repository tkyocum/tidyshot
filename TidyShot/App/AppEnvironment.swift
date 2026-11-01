import AppKit

/// What Delete asks before it acts (harness design 2.2): the first alert, Delete or Cancel, and the
/// second, after an Abort, a storage `DELETE` or the save folder's file failed, Remove or Cancel.
nonisolated enum DeleteConfirmation: Equatable, Sendable {
    case delete(CaptureRecord)
    case removeFromHistory(message: String, informativeText: String)
}

/// The coordinator's world (harness design 2.1): its files, its settings, the collaborators that
/// show something or reach the system, and the time, the clock, the free space and the log. The
/// app runs on `.live()`, which builds exactly what `AppCoordinator.init()` built before; the suite
/// builds one over temp folders and fakes (`CoordinatorWorld`).
struct AppEnvironment {
    /// `history.json`; `thumbnails/`, `pending/` and `multipart/` are made beside it.
    var historyFileURL: URL
    /// The container's `tmp`: `Drag/`, and URLSession's partial downloads.
    var temporaryDirectory: URL
    var settings: AppSettings
    var saveLocation: SaveLocation
    var credentialStore: any CredentialStore
    var notifier: any Notifying
    var overlay: any QuickAccessCards
    var clipboard: any Clipboard
    /// A destination for a configuration, signed with credentials read now.
    var makeDestination: @Sendable (S3DestinationConfig, AWSCredentials) -> any Destination
    /// When a lane's file job goes multipart, and in what parts.
    var multipartPlan: MultipartPlan
    /// A lane's backoff sleep between retries.
    var uploadSleep: UploadQueue.Sleeper
    /// Free space on the volume of a URL, nil when it cannot be read.
    var freeBytes: @Sendable (URL) -> Int64?
    /// Clop's optimiser (spec 2.7): a PNG or a recording rewritten smaller, or why the original uploads.
    var clopOptimiser: any ClopOptimising
    /// Whether a Clop build runs now, asked once per upload's Clop decision.
    var isClopRunning: @MainActor () -> Bool
    /// Delete's two alerts: true for Delete or Remove.
    var confirm: @MainActor (DeleteConfirmation) async -> Bool
    var playShutter: @MainActor () -> Void
    /// Builds an annotation editor over the coordinator's model and actions, titled `title`, with
    /// `representedURL` as its proxy icon, not yet shown. `onClose` runs when its window closes.
    var makeEditor: @MainActor (_ model: EditorModel, _ actions: EditorActions, _ title: String,
                                _ representedURL: URL?,
                                _ onClose: @escaping @MainActor (any EditorPresenting) -> Void) -> any EditorPresenting
    var now: @Sendable () -> Date
    /// The coordinator's own waits: the drag folder's clean-up, a replaced lane's poll, a recording's
    /// settle delay without a count-in, and a quit's poll.
    var clock: any ScrollClock
    /// Every coordinator log line (`RecordingLog.note` keeps its own).
    var log: @Sendable (String) -> Void

    /// What the app runs on: the user's Application Support folder (the temporary folder when it
    /// cannot be had), the shared settings, the Keychain, the notification centre, the card stack,
    /// the general pasteboard, S3, Clop, the alerts, the shutter sound, the editor window, the wall
    /// clock and `NSLog`. The collaborators are built in the order the coordinator's stored
    /// properties built them; Clop's optimiser, a value that reaches nothing until a request, is
    /// built here.
    static func live() -> AppEnvironment {
        let saveLocation = SaveLocation()
        let settings = AppSettings.shared
        let credentialStore = KeychainCredentialStore()
        let notifier = Notifier()
        let overlay = QuickAccessController(settings: settings)
        let historyFileURL = (try? HistoryStore.defaultFileURL())
            ?? FileManager.default.temporaryDirectory.appending(path: HistoryStore.fileName)
        return AppEnvironment(
            historyFileURL: historyFileURL,
            temporaryDirectory: FileManager.default.temporaryDirectory,
            settings: settings,
            saveLocation: saveLocation,
            credentialStore: credentialStore,
            notifier: notifier,
            overlay: overlay,
            clipboard: SystemClipboard(),
            makeDestination: { config, credentials in S3Destination(config: config, credentials: credentials) },
            multipartPlan: .standard,
            uploadSleep: { try await Task.sleep(for: $0) },
            freeBytes: { RecordingLimits.freeBytes(at: $0) },
            clopOptimiser: ClopApp.makeOptimiser(),
            isClopRunning: { ClopApp.runningBundleID() != nil },
            confirm: { await AppEnvironment.confirmLive($0) },
            playShutter: { SoundPlayer.playShutter() },
            makeEditor: { model, actions, title, representedURL, onClose in
                // The window as presentEditor built it: cascaded 22 pt from the frontmost editor,
                // read now, before this one exists. Its close reaches the coordinator's callback.
                let controller = EditorWindowController(model: model, actions: actions, title: title,
                                                        representedURL: representedURL,
                                                        cascadeFrom: NSApp.orderedWindows.first { $0 is EditorWindow })
                controller.onClose = { closed in onClose(closed) }
                return controller
            },
            now: { Date() },
            clock: SystemScrollClock(),
            log: { NSLog("%@", $0) })
    }

    /// Delete's alerts as `AppCoordinator+Delete.swift` ran them.
    private static func confirmLive(_ question: DeleteConfirmation) async -> Bool {
        switch question {
        case .delete(let record):
            return confirmDelete(of: record)
        case .removeFromHistory(let message, let informativeText):
            return await confirmRemoveFromHistory(message: message, informativeText: informativeText)
        }
    }

    /// The confirmation: Delete or Cancel (Escape). The app is activated first so the alert appears
    /// in front even when it was triggered from the non-activating overlay panel or the menu.
    private static func confirmDelete(of record: CaptureRecord) -> Bool {
        let alert = NSAlert()
        alert.messageText = CaptureDeletion.confirmationMessage
        alert.informativeText = CaptureDeletion.confirmationText(for: record)
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Delete").hasDestructiveAction = true
        alert.addButton(withTitle: "Cancel")
        NSApplication.shared.activate(ignoringOtherApps: true)
        return alert.runModal() == .alertFirstButtonReturn
    }

    /// The second alert, only after the Abort or the storage `DELETE` failed or the file in the save
    /// folder could not be removed: Remove (from history; what could not be deleted stays) or Cancel. It comes
    /// after the delete's network awaits, and a main-actor continuation also runs while a menu is
    /// tracking (the main queue is served in the common run-loop modes), so the user may have
    /// opened the menu bar menu in the meantime. The alert therefore runs inside a block that the
    /// run loop performs only in its default mode, which is not entered while a menu tracks, so
    /// `runModal()` never starts inside a menu's tracking loop (resuming first and running the
    /// alert afterwards would leave one main-queue turn in which tracking could begin).
    private static func confirmRemoveFromHistory(message: String, informativeText: String) async -> Bool {
        await withCheckedContinuation { (done: CheckedContinuation<Bool, Never>) in
            RunLoop.main.perform(inModes: [.default]) {
                MainActor.assumeIsolated {
                    let alert = NSAlert()
                    alert.messageText = message
                    alert.informativeText = informativeText
                    alert.alertStyle = .warning
                    alert.addButton(withTitle: "Remove").hasDestructiveAction = true
                    alert.addButton(withTitle: "Cancel")
                    NSApplication.shared.activate(ignoringOtherApps: true)
                    done.resume(returning: alert.runModal() == .alertFirstButtonReturn)
                }
            }
        }
    }
}
