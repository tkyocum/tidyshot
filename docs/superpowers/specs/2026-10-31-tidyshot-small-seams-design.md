# TidyShot: Small Seams (Phase CT-3) Design

Date: 2026-10-31. Branch `small-seams` from `main` at 30d3c15 (CT-2, the editor seam, merged). Every file:line below is at 30d3c15. Abbreviations: `Coord` = `TidyShot/App/AppCoordinator.swift`; `+Upload`, `+Recording`, `+Recovery`, `+Delete`, `+Trim` = `TidyShot/App/AppCoordinator+<name>.swift`; `RA` = `TidyShot/App/AppCoordinator+RecordActions.swift`; `Env` = `TidyShot/App/AppEnvironment.swift`; `CO` = `TidyShot/Upload/ClopOptimiser.swift`; `RR` = `TidyShot/Recording/RecordingRecovery.swift`; `World` = `TidyShotTests/Support/CoordinatorWorld.swift`; `Fakes` = `TidyShotTests/Support/CoordinatorFakes.swift`; `FD` = `TidyShotTests/Support/FakeDestination.swift`. seams.md is `docs/superpowers/notes/2026-10-30-checklist-sweep/seams.md`.

## 1. Goal

Three seams from the sweep, each a value or closure on `AppEnvironment` in the pattern of `Notifying`, `confirm`, `log` and `makeEditor` (harness design section 2; editor seam design section 2):

- **`CLOP`** (seams.md section 5, :284-316; 23 lines, 22 alone). The coordinator builds its own optimiser, `let clopOptimiser = ClopApp.makeOptimiser()` (Coord:160), over the real `tmp/Clop` and Clop's XPC port, and `clopIsRunning()` asks `ClopApp.runningBundleID()` (+Upload:425-431), which reads `NSRunningApplication` (CO:257-284). With `optimiseWithClop` on, a test would depend on whether Clop runs on the Mac; no coordinator suite turns it on (it defaults off, AppSettings.swift:294).
- **`SAVEAS`** (section 6, :317-340; 14 lines). `askSaveAsTarget` builds `EditorNaming.savePanel(for:)`, activates the app and awaits `panel.begin()` (RA:195-207), all barred in the suite; `CoordinatorRecordActionsTests` says the panel "is never built here" (CoordinatorRecordActionsTests.swift:5-7).
- **`LOG`** (section 8, :366-387; 12 lines). The coordinator's 24 `Recording:` lines go to `RecordingLog.note`, a static `Logger` the suite cannot read (ScreenRecordingDriver.swift:88-97): 18 in +Recording, 4 in +Recovery, 2 in +Upload. The launch scan's removal line is in `RecordingRecovery.scan` (RR:34, :36).

They go together because each is small (production +94 −52 in nine files, merged), they touch different regions of the files they share (section 2.4), and together they reach 49 lines with no new window, panel or process check left in the coordinator's paths. The phase writes 34 tests and marks 46 lines: 28 in full and 18 in part; 3 lines are deferred (section 11). The notes are committed beside this design in `docs/superpowers/notes/2026-10-31-small-seams/`: `lines-small.md` gives each of the 49 lines with its text, verdict and what stays; `tests-small.md` is the catalogue, with every value a test body needs. The plan copies from there; nothing depends on the git-ignored `.superpowers/` files.

## 2. The seams

### 2.1 `CLOP`: the optimiser and the running check

**Members** (Env, after `freeBytes` at :32): `clopOptimiser: any ClopOptimising` and `isClopRunning: @MainActor () -> Bool`. The protocol names exactly the two calls the coordinator makes (+Upload:441, :448). A fake transport under the concrete `ClopOptimiser` (seams.md's shape, :287) is rejected: a hold there blocks a thread on the optimiser's two `private static` serial queues, shared by the process (CO:85, :88), and its continuations have no cancellation handler (CO:95-99, :123-127), so it could be neither cancellable nor single-entry. The running check is a `Bool` because the coordinator reads the bundle id only as nil or not (+Upload:426); the live transport asks again per request (CO:280).

`CO`, after the end of `ClopOptimiser` (:253) and before `ClopApp`'s doc comment (:255):
```swift
/// What the coordinator asks of Clop (small seams design 2.1): `AppEnvironment.clopOptimiser`.
/// `ClopOptimiser` is the app's; the suite's is `FakeClop`.
protocol ClopOptimising {
    func optimisedPNG(_ data: Data) async -> ClopOutcome
    func optimisedVideo(at source: URL, duration: TimeInterval, scope: URL?) async -> ClopVideoOutcome
}
extension ClopOptimiser: ClopOptimising {}
```

`Env`, the members and the live values (after `freeBytes:` in `live()`, Env:73):
```swift
    /// Clop's optimiser (spec 2.7): a PNG or a recording rewritten smaller, or why the original uploads.
    var clopOptimiser: any ClopOptimising
    /// Whether a Clop build runs now, asked once per upload's Clop decision.
    var isClopRunning: @MainActor () -> Bool
// in live():
            clopOptimiser: ClopApp.makeOptimiser(),
            isClopRunning: { ClopApp.runningBundleID() != nil },
```

`Coord` (:158-160, and in `init` after `clipboard = environment.clipboard`, :274):
```diff
-    /// Optimize images and videos with Clop (spec 2.7): one optimiser, sending to whichever Clop
-    /// build runs.
-    let clopOptimiser = ClopApp.makeOptimiser()
+    /// Optimize images and videos with Clop (spec 2.7): the environment's optimiser, which in the
+    /// app sends to whichever Clop build runs.
+    let clopOptimiser: any ClopOptimising
@@ init
         clipboard = environment.clipboard
+        clopOptimiser = environment.clopOptimiser
```

`+Upload` (:426):
```diff
     private func clopIsRunning() -> Bool {
-        guard ClopApp.runningBundleID() != nil else {
+        guard environment.isClopRunning() else {
             log("Clop: \(ClopSkipReason.notRunning.summary), uploading the original")
```

Isolation: under the project's default `MainActor` isolation (project.yml:29-31, :101-103) the protocol is main-actor; the `nonisolated struct ClopOptimiser: Sendable` (CO:53) witnesses both async requirements with nonisolated methods, and the existential sits in a `let` on the main-actor coordinator and is never sent. `isClopRunning` is `@MainActor` like `confirm` (Env:34): both decisions run on the main actor (+Upload:189; :255 inside the start `Task`). The judge's merged build gave no diagnostic.

**What does not change.** `live()` builds what the stored property built (`ClopApp.makeOptimiser()`, CO:272-283) and runs the expression `clopIsRunning()` ran. The optimiser is now built in `live()` before the coordinator instead of by its stored property; building it reads `FileManager.default.temporaryDirectory` and captures two closures, nothing a user sees. The property keeps its name, so +Upload:441 and :448 are untouched; nothing else reads it. For the user: with Clop on and running, an image or MP4 is still sent to Clop and the smaller result uploads; with Clop quit, the original uploads with `Clop: Clop is not running, uploading the original` and TidyShot does not launch Clop; GIFs are still never sent; the card's `Optimizing…`, the size shown and every log line are as before. `GeneralSettingsView`'s `ClopApp.isInstalled` and `start()`'s sweep of `ClopApp.workDirectory` (Coord:298) are untouched; the work directory stays a static (`TMPDIRS`).

### 2.2 `SAVEAS`: the card's Save As… panel

**Member** (Env, after `makeEditor` at :38-40): `chooseSaveAsURL: @MainActor (EditorNaming.SaveAsSuggestion) async -> URL?`, seams.md's shape (:319). It is the narrowest cut that removes every system call from `askSaveAsTarget` (the panel RA:197, `activate` RA:200, `begin()` RA:201) and keeps the record check (RA:196), the suggestion (`saveAsSuggestion(recordID:)`, RA:321-330) and the re-read with its log line (RA:202-205) under test. The argument is a value the coordinator builds (`Equatable, Sendable`, EditorNaming.swift:6-13), so the fake records what the panel would show, as `FakeConfirm.asked` records a `DeleteConfirmation`.

`Env`, the member, the live value (after the `makeEditor` closure, Env:76-84) and a private live body after `live()`, before `confirmLive` (Env:90-91):
```swift
    /// A card's Save As… panel: a place for the suggestion, or nil for Cancel.
    var chooseSaveAsURL: @MainActor (EditorNaming.SaveAsSuggestion) async -> URL?
// in live():
            chooseSaveAsURL: { await AppEnvironment.chooseSaveAsURLLive($0) },
// after live():
    /// The card's Save As… panel as `askSaveAsTarget` ran it: the panel for the suggestion
    /// (`EditorNaming.savePanel(for:)`), the app activated, then the panel as a window (`begin()`,
    /// not a sheet). Nil when it was cancelled.
    private static func chooseSaveAsURLLive(_ suggestion: EditorNaming.SaveAsSuggestion) async -> URL? {
        let panel = EditorNaming.savePanel(for: suggestion)
        // Reached from a non-activating card while another app is active; a plain activate() can
        // be refused and the panel would open behind that app (as in SaveLocation.chooseFolder).
        NSApplication.shared.activate(ignoringOtherApps: true)
        guard await panel.begin() == .OK else { return nil }
        return panel.url
    }
```

`RA` (:191-201):
```diff
-    /// A card's Save As… panel, for an image and for a recording: activates the app and asks for a
-    /// place with the record's suggestion (`EditorNaming.savePanel(for:)`). Then the record is read
-    /// again, since the upload may have finished, or the capture been deleted, while the panel was
-    /// open. Nil when the panel was cancelled or the capture is gone.
+    /// A card's Save As… panel, for an image and for a recording: asks for a place with the record's
+    /// suggestion (`environment.chooseSaveAsURL`, which activates the app and shows
+    /// `EditorNaming.savePanel(for:)`). Then the record is read again, since the upload may have
+    /// finished, or the capture been deleted, while the panel was open. Nil when the panel was
+    /// cancelled or the capture is gone.
     private func askSaveAsTarget(recordID: UUID) async -> (record: CaptureRecord, url: URL)? {
         guard history.record(id: recordID) != nil else { return nil }
-        let panel = EditorNaming.savePanel(for: saveAsSuggestion(recordID: recordID))
-        // Reached from a non-activating card while another app is active; a plain activate() can
-        // be refused and the panel would open behind that app (as in SaveLocation.chooseFolder).
-        NSApplication.shared.activate(ignoringOtherApps: true)
-        guard await panel.begin() == .OK, let url = panel.url else { return nil }
+        guard let url = await environment.chooseSaveAsURL(saveAsSuggestion(recordID: recordID)) else { return nil }
         guard let record = history.record(id: recordID) else {
```

**What does not change.** The suggestion is computed once at the same point, the same panel is built from it, the app is activated the same way, and `panel.url` is read only after `.OK`. The re-read, the log line and the recording's wait for a drag-out download (RA:132-134) are as before. The panel is now released when the closure returns rather than at the end of `askSaveAsTarget`; `begin()` has returned by then either way. For the user: Save As… on a card or a pin (`pinActions`, +Pins.swift:70) opens the same window-style panel, in front, with the capture's own name in the save folder or the template name, PNG or GIF only. Cancel writes nothing and posts nothing; Save writes the copy and posts `Saved`; an upload-only recording still downloads to the chosen file. Two panels at once still work, since the live closure builds a new panel per call. `askSaveAsTarget` stays `private`; `saveAs` (RA:111), `saveVideoCopy` (:130), `saveCopy` (:179) and `performSaveAs` (:303) are untouched. RA keeps `import AppKit` (`NSWorkspace` at RA:60, :71, :275). The editor's ⇧⌘S sheet (EditorWindowController.swift:277) is `EDSAVEAS` and stays.

### 2.3 `LOG`: the recording log sink

**Member** (Env, after `log` at :46, last): `recordingLog: @Sendable (String) -> Void`, live `{ RecordingLog.note($0) }`. It is a second member, not a prefix route through `log`. The two sinks differ in privacy on purpose: `RecordingLog` writes `.public` through `Logger` (ScreenRecordingDriver.swift:88-95), while `log` goes to `NSLog`, whose text shows `<private>`. A router would make a later `log("Recording: …")` public without anyone choosing it. `log` is also the `UploadQueue.Logger` handed to every lane (+Upload:117-124), and existing tests compare `world.logLines` whole. A settable static on `RecordingLog` is rejected: one sink shared by parallel suites.

**Scope** (call 2). The coordinator's 24 calls, plus `RecordingRecovery.scan`, which is the only way to reach recording-r1:263 (RR:34). `sweepMuteFolder` (RR:125-140, its line :137) is not threaded: about 7 lines for no checklist line, and `recoverRecordings` is driven by no test. `RecordingExtras` is not threaded: its four lines (RecordingExtras.swift:215, :221, :235, :250) are fed only by a real `CameraSession`, and `EXTRAS` changes its `init` anyway (seams.md:499). Coordinator only would defer recording-r1:263 too; adding `RecordingExtras` would unlock nothing now.

`Env`:
```diff
-    /// Every coordinator log line (`RecordingLog.note` keeps its own).
+    /// Every coordinator log line but the `Recording:` ones.
     var log: @Sendable (String) -> Void
+    /// The coordinator's `Recording:` lines, and the launch scan's (`RecordingRecovery.scan`);
+    /// `RecordingLog.note` in the app.
+    var recordingLog: @Sendable (String) -> Void
@@ live()
-            log: { NSLog("%@", $0) })
+            log: { NSLog("%@", $0) },
+            recordingLog: { RecordingLog.note($0) })
```

`Coord`, a forwarder after `log(_:)` (:289-292), and `start()` (:320-325) handing `scan` the sink through `begin`'s existing `scanning:` parameter (RR:107-108):
```diff
+    /// A `Recording:` line, through the environment (`RecordingLog.note` in the app).
+    func recordingLog(_ message: String) {
+        environment.recordingLog(message)
+    }
@@ start()
+        let note = environment.recordingLog
         Task {
             let leftRecordings = await RecordingRecovery.begin(recordingDirectory: Recording.directory,
-                                                               muteDirectory: MuteLog.directory)
+                                                               muteDirectory: MuteLog.directory,
+                                                               scanning: { await RecordingRecovery.scan($0, note: note) })
```

**The 22 main-actor call sites.** At +Recording:109, :114, :160, :165, :180, :183, :189, :191, :273, :293, :339, :358, :365, :411, :468, :590, +Recovery:127, :129, :143, :161 and +Upload:378, :395, the call `RecordingLog.note(` becomes `recordingLog(`; the rest of each line, its string included, is unchanged byte for byte. For example +Recording:191: `RecordingLog.note("Recording: stop-recording from \(name) did nothing, no recording is running")` becomes `recordingLog("Recording: stop-recording from \(name) did nothing, no recording is running")`. **The two detached sites**, in `placeRecording` (`nonisolated private static`, run in `Task.detached`, +Recording:796-801, :873-896), take the value as a parameter:
```diff
@@ saveRecording (+Recording:793-799)
-        let (kind, recoveryURL) = (recording.mediaKind, recording.recoveryURL)
+        let (kind, recoveryURL, note) = (recording.mediaKind, recording.recoveryURL, environment.recordingLog)
@@
-                                                    recoveryURL: recoveryURL)
+                                                    recoveryURL: recoveryURL, note: note)
@@ placeRecording (+Recording:873-876, :884, :892)
+    /// A failed move is logged with `note`, the environment's `recordingLog`.
     nonisolated private static func placeRecording(_ source: URL, kind: MediaKind, id: UUID,
                                                    folder: (url: URL, baseName: String)?, noFolderReason: String?,
-                                                   pending: PendingFileStore,
-                                                   recoveryURL: URL) -> (result: RecordingFileResult, url: URL) {
+                                                   pending: PendingFileStore, recoveryURL: URL,
+                                                   note: @Sendable (String) -> Void) -> (result: RecordingFileResult, url: URL) {
-                RecordingLog.note("Recording: \(source.lastPathComponent) could not be moved into the save folder: \(error.localizedDescription)")
+                note("Recording: \(source.lastPathComponent) could not be moved into the save folder: \(error.localizedDescription)")
-            RecordingLog.note("Recording: \(source.lastPathComponent) could not be moved to pending: \(error.localizedDescription)")
+            note("Recording: \(source.lastPathComponent) could not be moved to pending: \(error.localizedDescription)")
```

`RR`, `scan` only (:17-22, :34, :36) and `begin`'s doc (:105-106):
```diff
-    /// rule's 0.5 s is kept too.
+    /// rule's 0.5 s is kept too. A removal is logged with `note`.
     @concurrent
-    static func scan(_ directory: URL) async -> [Found] {
+    static func scan(_ directory: URL,
+                     note: @Sendable (String) -> Void = { RecordingLog.note($0) }) async -> [Found] {
-                    RecordingLog.note("Recording: \(url.lastPathComponent) could not be played, removed")
+                    note("Recording: \(url.lastPathComponent) could not be played, removed")
-                    RecordingLog.note("Recording: \(url.lastPathComponent) could not be played or removed: \(error.localizedDescription)")
+                    note("Recording: \(url.lastPathComponent) could not be played or removed: \(error.localizedDescription)")
-    /// `scan`, injected by tests.
+    /// `scan`: the coordinator passes it with its `recordingLog`, and tests inject their own.
```

ScreenRecordingDriver.swift gains one doc line after :90: `/// The coordinator reaches it through \`AppEnvironment.recordingLog\`.` After the change `grep -c "RecordingLog.note"` is 0 in +Recording, +Recovery and +Upload, and 2 in RR (`scan`'s default and the sweep).

**What does not change.** The same `Logger`, `.public`, the same text and the same thread per call: the forwarder is synchronous, `placeRecording` and `scan` take a `@Sendable` value, and the default argument is a closure literal. Every existing `scan(dir)` call in `RecordingRecoveryTests` compiles unchanged. For the user, `log show --predicate 'process == "TidyShot"' | grep "Recording:"` reads exactly as before, in the same order; nothing on screen changes. The recorder's, the driver's, `GIFMaker`'s, `RecordingExtras`' and the mute sweep's lines still call `RecordingLog.note` directly.

### 2.4 What the three share

`AppEnvironment` has no memberwise init shortcut: a member is a positional argument at exactly two sites, `live()` (Env:61) and `World:113`. The order is `clopOptimiser`, `isClopRunning` after `freeBytes`; `chooseSaveAsURL` after `makeEditor`; `recordingLog` after `log`, last. Each plan task adds its own lines at its own place. Only `live()`'s doc sentence (Env:48-52) is reworded by all three; the task that lands last leaves it as:
```swift
    /// What the app runs on: the user's Application Support folder (the temporary folder when it
    /// cannot be had), the shared settings, the Keychain, the notification centre, the card stack,
    /// the general pasteboard, S3, Clop, the alerts, the shutter sound, the editor window, the card's
    /// Save As… panel, the wall clock, `NSLog` and `RecordingLog`. The collaborators are built in the
    /// order the coordinator's stored properties built them; Clop's optimiser, a value that reaches
    /// nothing until a request, is built here.
```

The other shared files are touched in different regions: `Coord` (CLOP :158-160, :274; LOG :289-292, :320-325), `+Upload` (CLOP :426; LOG :378, :395), `Fakes` (SAVEAS after `FakeConfirm`, :196-221; LOG in `CoordinatorWorldState`, :255-289). The judge merged the three scratch trees with `patch` and no rejects: production +94 −52 in nine files by section 2's diffs (the merged tree has one more blank line, after the new protocol in ClopOptimiser.swift).

## 3. The fakes

### 3.1 `FakeClop` (new `TidyShotTests/Support/ClopFakes.swift`)

```swift
import Foundation
import Testing
@testable import TidyShot
/// Clop in the suite (small seams design 3.1): `environment.clopOptimiser` and `isClopRunning` in one.
/// Each request is recorded, then answered from `answers` in order. A request with no answer left, or an
/// answer of the other kind, records an issue and is answered `.original(unscripted)`. A second hold
/// while one is held records an issue and is answered `cancelledAnswer` at once. Nothing here reaches
/// Clop, its port, `NSRunningApplication` or the serial queues.
final class FakeClop: ClopOptimising {
    /// What one request answers. `Sendable` because `SingleWaiter` carries it.
    nonisolated enum Answer: Equatable, Sendable {
        case smaller(Data)  // an image: these bytes, fewer than the request's
        /// A recording: a sparse movie of this many bytes in `workDirectory`, owned by the caller.
        case smallerMovie(byteCount: Int64)
        case original(ClopSkipReason)
        case hold  // waits for `release(_:)`
    }
    nonisolated enum Request: Equatable, Sendable {
        case png(Data)
        case video(URL, duration: TimeInterval)
    }
    static let cancelledAnswer = Answer.original(.failed("FakeClop's held request was cancelled"))
    static let unscripted = ClopSkipReason.failed("FakeClop had no answer for this request")
    let workDirectory: URL
    var isRunning = true
    private(set) var runningChecks = 0
    private(set) var requests: [Request] = []
    var answers: [Answer] = []
    private let held = SingleWaiter(cancelled: FakeClop.cancelledAnswer,
                                    secondEntry: "FakeClop held a second request while one was held")
    init(workDirectory: URL) { self.workDirectory = workDirectory }
    var isHolding: Bool { held.isWaiting }
    func checkRunning() -> Bool {
        runningChecks += 1
        return isRunning
    }
    /// Answers the held request; a no-op when none is held, so a test's `defer` can call it.
    func release(_ answer: Answer) { held.resume(answer) }
    var workFiles: [String] {
        (try? FileManager.default.contentsOfDirectory(atPath: workDirectory.path(percentEncoded: false))) ?? []
    }
    func optimisedPNG(_ data: Data) async -> ClopOutcome {
        requests.append(.png(data))
        switch await nextAnswer() {
        case .smaller(let bytes):
            if bytes.count >= data.count {
                Issue.record("FakeClop's smaller PNG is \(bytes.count) bytes, the request \(data.count)")
            }
            return .optimised(bytes, oldBytes: data.count, newBytes: bytes.count)
        case .original(let reason):
            return .original(reason)
        case .smallerMovie, .hold:
            Issue.record("FakeClop was given a movie answer for a PNG")
            return .original(Self.unscripted)
        }
    }
    func optimisedVideo(at source: URL, duration: TimeInterval, scope: URL?) async -> ClopVideoOutcome {
        requests.append(.video(source, duration: duration))
        // Read before any hold: `ClopOptimiser` copies the source before it sends the request.
        let oldBytes = Int64((try? source.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        switch await nextAnswer() {
        case .smallerMovie(let byteCount):
            if byteCount >= oldBytes {
                Issue.record("FakeClop's smaller movie is \(byteCount) bytes, the source \(oldBytes)")
            }
            let movie = workDirectory.appending(path: "\(UUID().uuidString).mp4", directoryHint: .notDirectory)
            do {
                try CoordinatorWorld.writeSparseFile(at: movie, byteCount: byteCount)
            } catch {
                Issue.record(error)
                return .original(Self.unscripted)
            }
            return .optimised(movie, oldBytes: oldBytes, newBytes: byteCount)
        case .original(let reason):
            return .original(reason)
        case .smaller, .hold:
            Issue.record("FakeClop was given a PNG answer for a movie")
            return .original(Self.unscripted)
        }
    }
    private func nextAnswer() async -> Answer {
        guard !answers.isEmpty else {
            Issue.record("FakeClop was asked with no answer scripted")
            return .original(Self.unscripted)
        }
        let answer = answers.removeFirst()
        guard answer == .hold else { return answer }
        let released = await held.wait()
        guard released != .hold else {
            Issue.record("FakeClop's held request was released with .hold")
            return Self.cancelledAnswer
        }
        return released
    }
}
```

This is the judge's fake (built and run in its merged tree) with shorter doc comments. It does not model the serial queues (two requests can be in flight; the app answers the first first), the PNG and movie checks, the space check or `inspect`. Those stay in `ClopOptimiserTests`.

### 3.2 `FakeSaveAsChooser` (`Fakes`, after `FakeConfirm`) and `FakeDestination.download(key:to:)`

```swift
/// A card's Save As… panel in the suite (`environment.chooseSaveAsURL`): no panel is built and the app
/// is never activated. Every suggestion is kept, in order; each is answered from `answers` (a URL, or
/// nil for Cancel; Cancel when they run out), or held until `answer(_:)` while `holds` is set. A held
/// panel whose task is cancelled answers Cancel; a second panel while one is held records an issue.
final class FakeSaveAsChooser {
    private(set) var asked: [EditorNaming.SaveAsSuggestion] = []
    var answers: [URL?] = []
    var holds = false
    private let held = SingleWaiter<URL?>(cancelled: nil,
                                          secondEntry: "FakeSaveAsChooser was asked again while a panel was held")
    var isWaiting: Bool { held.isWaiting }
    func choose(_ suggestion: EditorNaming.SaveAsSuggestion) async -> URL? {
        asked.append(suggestion)
        guard holds else { return answers.isEmpty ? nil : answers.removeFirst() }
        return await held.wait()
    }
    /// Answers the held panel (nil: Cancel); later ones come from `answers`.
    func answer(_ url: URL?) {
        holds = false
        held.resume(url)
    }
}
```

It answers Cancel when its list runs out, where `FakeConfirm` answers Yes, so a test that reaches Save As without scripting it writes nothing. A harness gap, not a seam: `FD:171`'s `download(key:to:) async throws {}` records nothing and writes nothing, so a recording's Save As download (RA:150-152) can be neither counted (recording-r4:277) nor saved (recording-r1:313). `State` gains one field after `dataDownloadFailures` (FD:107), and the method records and writes as `download(key:)` reads (FD:173-181):
```swift
        /// Each `download(key:to:)` (a recording's Save As…, Trim): its key and file, in order.
        var fileDownloads: [(key: String, file: URL)] = []
    func download(key: String, to destination: URL) async throws {
        let data = state.withLock { state -> Data in
            state.fileDownloads.append((key, destination))
            return state.downloadedData
        }
        try data.write(to: destination, options: .atomic)
    }
```

### 3.3 The log sink: `CoordinatorWorldState` (`Fakes:255-289`)

No new type. `Values` gains `var recordingLines: [String] = []`; the class gains `var recordingLines: [String] { values.withLock { $0.recordingLines } }` and `func appendRecording(_ line: String) { values.withLock { $0.recordingLines.append(line) } }`; its doc says "the free space and the two logs". `RecordingRecoveryTests` has no world and collects with the existing `LogLines` (UploadQueueTests.swift:21) passed as `note:`.

### 3.4 `CoordinatorWorld` additions

- `let clop: FakeClop`, set in `init` after `self.temporaryDirectory = temporaryDirectory` as `FakeClop(workDirectory: temporaryDirectory.appending(path: "Clop", directoryHint: .isDirectory))`, so it is `<root>/tmp/Clop` and `removeAll()` removes it. `let saveAsChooser = FakeSaveAsChooser()` after `editors` (World:44); `var recordingLines: [String] { state.recordingLines }` after `logLines` (World:106).
- In `environment` (World:108-134), `let clop = clop` and `let saveAsChooser = saveAsChooser` beside the other locals, then `clopOptimiser: clop, isClopRunning: { clop.checkRunning() }` after `freeBytes:`, `chooseSaveAsURL: { suggestion in await saveAsChooser.choose(suggestion) }` after the `makeEditor` closure, and `recordingLog: { line in state.appendRecording(line) }` after `log:`. The type doc (World:11-17) names Clop (`clop`, over `<root>/tmp/Clop`), the card's Save As… panel (`saveAsChooser`; none is built) and "the two logs it reads (`logLines`, `recordingLines`)".
- `CoordinatorWorldTests.aCoordinatorOverTheWorldKeepsToTheWorld`, after `#expect(world.logLines.isEmpty)` (CoordinatorWorldTests.swift:31): `#expect(world.recordingLines.isEmpty)`, `#expect(world.clop.runningChecks == 0)`, `#expect(world.clop.requests.isEmpty)`, `#expect(world.saveAsChooser.asked.isEmpty)`. Building a coordinator asks none of the three anything. These are checks in an existing test, not tests.

### 3.5 Driving each seam in a test

1. **Clop.** Turn it on with `world.settings.optimiseWithClop = true`; `CoordinatorClopTests.init` does it and sets a small `world.multipartPlan`. Script one `answers` element per request. A test that scripts `.hold` declares `defer { world.clop.release(FakeClop.cancelledAnswer) }` right after `defer { world.removeAll() }` and waits with `eventually { world.clop.isHolding }`, never by awaiting the upload. After its own `release(_:)` it gates on `eventually { coordinator.clopWaitsPerLane.isEmpty }` (the start task's `defer`, +Upload:209-212; the task is not stored, :208) or on the record's final state. The suite's time limit cancels the test's task, not the coordinator's, so the `defer` release is what ends a held request on a failing test. Delete during a hold runs in a `Task` with `defer { delete.cancel() }` and a `TaskWatch`, and is gated by `eventually { watch.hasReturned }`; then `isHolding` still true is "cancels at once". An image's Clop decision is taken in `startUpload` (+Upload:189) and a recording's in its task (:255). Clop's movie is removed detached (+Upload:418-422), so a test that made one ends with `eventually { world.clop.workFiles.isEmpty }`. `FakeDestination.publicURL(for:)` answers one URL shape for every destination (FD:274-276), so destinations are told apart by `objectLocation` and by which fake received the bytes.
2. **Save As.** Script `world.saveAsChooser.answers` and read `asked`. `saveAs(recordID:)` returns at once through `afterMenuTracking` and an unstored `Task` (RA:111-121, :280-284), so the test gates with `eventually` on `asked.count`, the notifier or the file. `saveVideoCopy(recordID:)` is async: it runs in the test's own `Task` with `defer { task.cancel() }`, gated by `TaskWatch`. A held panel is `holds = true`, `defer { chooser.answer(nil) }` right after the world's `defer`, `eventually { chooser.isWaiting }`, the step under test, then `answer(url)`. Never two held at once. Writes go under `<root>/Desktop/`.
3. **The log.** Assert `world.recordingLines` whole and in order with `==`, and `world.logLines.isEmpty` beside it where the path logs nothing else. Only the coordinator's and `scan`'s lines are collected. No test passes `recordingCanStart` (+Recording:354-378, which makes the live `tmp/Recording`). Every start parks at a held prompt (`HeldCameraDevices`, `HeldMicrophoneDevices`, Fakes:302-371) and is ended by a quit, in the D31 form (CoordinatorRecordingTests.swift:315-378).

## 4. The tests

34 tests, 2 new suite files; `tests-small.md` has each in full. Of them, 18 were built and run in the designers' trees and together in the judge's merged tree (CLOP T1-T5, SAVEAS 1-8, LOG's five). The other 16 are written from the code and the suites' idioms, and two LOG tests change from their run form. Effort: S 10, M 18, L 6. Two tests are parameterized (CLOP T2, T12).

| Suite file | New? | Tests | tests-small.md | What they drive |
|---|---|---|---|---|
| `CoordinatorClopTests` | new | 15 | 3, CLOP.3 | Clop on and off, mid-run toggle, the four skip reasons, delete and retry during a hold, settings change during a hold, counters, a failed upload's pending file, recordings: the kept movie and resume, a keep failure, GIFs, the cleanup |
| `CoordinatorTrimTests` | existing | 1 (T16) | CLOP.4 | Upload Trimmed with Clop after the file changed |
| `CoordinatorEditorUploadTests` | existing | 2 (T17; SAVEAS 10) | CLOP.4, SAVEAS.5 | editor Upload and Upload as New through Clop; Save As after an editor upload |
| `CoordinatorSaveTests` | existing | 1 (T18) | CLOP.4 | an MP4's size is the moved file's |
| `CoordinatorSaveAsTests` | new | 9 (8 for lines, E1) | 4, SAVEAS.3 | a saved image, an upload-only capture, the drag copy or a download, a held panel through the auto-close, any card, recordings and GIFs, the deleted-while-open branch |
| `CoordinatorEditorSaveTests` | existing | 1 (SAVEAS 9) | SAVEAS.5 | Save As after a save over the file writes the edit |
| `CoordinatorRecordingTests` | existing | 4 | 5, LOG.3 | `stop-recording` in each phase, prompt answers and a second press, the Settings prompt, a second URL start |
| `RecordingRecoveryTests` | existing | 1 | LOG.4 | a leftover that does not play |

Each test's doc comment names its checklist lines by catalogue key and current line. A part test says what stays and whose. Tests 48 and 50 of `CoordinatorRecordingTests` (CoordinatorRecordingTests.swift:50-53, :87-90) keep their bodies; their D24 comments gain the pointer to `stopRecordingLogsWhatItDidInEachPhase` (LOG.6).

## 5. Rules for the tests

From CT-2 section 5, still binding: `TidyShot/` changes only as section 2 says, and no `private` member opens; a test that would need more is reported, not forced. No test touches `AppSettings.shared`, `NSPasteboard.general`, the Keychain, `UNUserNotificationCenter`, `NSWorkspace`, `NSRunningApplication`, `NSScreen.screens`, the `tmp/` statics, a window ordered front, a panel shown, the screen, a camera, a microphone, a sound, the real Clop app or the network. History is loaded with `history.load()`, never `start()` (Coord:294-300). `HistoryStore` prunes on the real `Date()`, so records keep timestamps near now. Held fakes are cancellable and single-entry; nothing awaits the behaviour under test directly (`eventually`, UploadQueueTests.swift:39-48; `TaskWatch`, Fakes:418-431). A held task is cancelled or released in a `defer` declared right after `defer { world.removeAll() }`. Nothing an edit starts outlives its test: `settledEdit` for SAVEAS 9 and 10 and CLOP T17. A relaunch is a second `world.makeCoordinator()`, after which the first is not called. Each test owns its world and defaults suite; suites are `@Suite(.timeLimit(.minutes(1)))` with no `.serialized`. No effect is committed in an editor test (`RedactionRenderer.shared`). The tests' `MovieSamples` decoder is untouched.

This phase's own rules:
- **The world's Clop work directory.** `FakeClop` writes only in `world.clop.workDirectory` (`<root>/tmp/Clop`), never the container's `ClopApp.workDirectory` (CO:272). Recordings are sparse pending movies; the fake never reads one. A test that keeps Clop's movie for a resume sets `world.date` later than the record's file, or the kept copy reads as outdated (`MultipartPlan.keptCopyIsOutdated`). A failed file removal is made with a 0o555 folder restored in a `defer` that runs before `removeAll()` (as CoordinatorDeleteTests.swift:290-291).
- **The held chooser.** One held panel at a time. For an image the coordinator's task cannot be cancelled by the test, so the `defer` answer is what ends it. A Cancel step proves "nothing written or posted" through the next step's whole comparison of `world.notifier.calls`. A suggestion with no save-folder file is compared only under a template without `{time}`, `{date}` or `{datetime}`: the coordinator's `FileNamer` reads `Date()` (RA:321-329, FileNamer.swift:21), so the default template's seconds can tick between its read and the test's (tests-small.md SAVEAS.2).
- **The log sink.** Two lists, each asserted whole. `beginRecording` runs the real `RecordingController` over `FakeRecordingDriver` and adds no line, because the recorder keeps `RecordingLog.note`. A Settings ask that must not prompt runs as its own gated task, so a prompt that comes after all fails in two seconds.

## 6. The marks

As CT-2 section 6: `(suite: Suite.test)` for full and `(suite, in part: Suite.test; by hand: <what>)` for part, appended to the end of the item's last line, wrapped at 120 columns with two-space continuation lines, a closing `______` kept last. The sources are each test's "Covers" line and merged mark in tests-small.md (CLOP.5, the SAVEAS entries, LOG.8) and each line's "Stays" in lines-small.md. A by-hand text names the other seam where there is one (`TMPDIRS`, `PINS`, `SCREENS`, `WORKSPACE`, `URLLOG`, `EXTRAS`, `CAPSRC`). A mark also names an existing test that pins part of the line, such as `ClopOptimiserTests`, `AppSettingsTests.optimiseWithClopDefaultsOffAndPersists`, `CoordinatorDeleteTests`, `EditorNamingTests` or `ShortcutsTests`. Since the checklists have moved since e011d2f, the script finds each line by an anchor that occurs once in its file at the branch head.

**Extended, not duplicated.** Six of the lines carry a mark already. A line gets one mark: the script edits the existing note in place and never appends a second. coordinator-split:44 (coordinator-split checklist :48-51), phase-6a:198 (:220-223) and phase-6a:199 (:224-229) carry CT-2 in-part marks that name `SAVEAS` in their by-hand lists. Each gains the CT-3 tests in its test list. `SAVEAS` leaves its by-hand list, and phase-6a:199's gains `PINS` (only a pin offers Save As… after an edit). recording-r4:253 (:268) and :255 (:271) carry earlier in-part marks. :253 gains T16 and stays in part; :255 gains T5 and T15 and drops `in part`. recording-r4:217 (:222) keeps its rule mark and gains `by hand: the log line, in private record() past the capture lock (TMPDIRS, CAPSRC)`. The script asserts that each anchor matches one line, that every named test exists (`func <name>(` in `TidyShotTests/`), and that each of the six carries exactly one `(suite` note after the edit. It also asserts that none of the other 41 lines carries one before. 46 lines are marked: 28 full, 18 part. recording-r3:416 and :436 stay unmarked. Where a line's text is at odds with the code (coordinator-harness:27's "the suite pins the state, not the `RecordingLog` text"), the text is not changed (call 8).

## 7. Settings, entitlements, packages

None change. `project.yml` takes `TidyShotTests/` whole, less `Fixtures/**` (project.yml:92-97), so the three new files are picked up by `xcodegen generate`. No new setting: `optimiseWithClop` exists (AppSettings.swift:150) and the tests set it on the world's own defaults suite.

## 8. Tests summary

`Test run with 2318 tests in 193 suites passed` at 30d3c15 → `Test run with 2352 tests in 195 suites passed`: 34 new `@Test` functions, each counted once, and 2 new suite files (`CoordinatorClopTests`, `CoordinatorSaveAsTests`). `ClopFakes.swift` holds no tests. Without E1 the line is 2351. The noise lines are unchanged.

## 9. Hand checks (short)

The three live values never run in the suite, because `live()` builds `AppSettings.shared`, the Keychain store and the notifier. `docs/testing/small-seams-manual-checklist.md`, written at close-out, checks them for Tim:

1. **The real Clop path.** Clop running, `Optimize with Clop` on: a capture's upload shows `Optimizing…` and the row shows the smaller size; an MP4 recording does the same. Quit Clop and capture: the original uploads, the log has `Clop: Clop is not running, uploading the original`, and Clop is not launched.
2. **The real panel.** Save As… on a card while another app is frontmost: the panel opens in front of it, with the capture's name in the save folder. Cancel writes nothing; Save writes the copy and posts `Saved`. Save As… on an upload-only recording's card downloads to the chosen file.
3. **The real log.** `stop-recording` with nothing running, then `log show --last 5m --style compact --predicate 'process == "TidyShot"' | grep "Recording:"`: one `did nothing, no recording is running` line, public, not `<private>`. Then `echo junk > "$C/tmp/Recording/x.mp4"`, relaunch, and the same command shows `Recording: x.mp4 could not be played, removed`.

## 10. The design's calls (for Tim to overrule)

1. **CLOP's shape overrules seams.md's.** A protocol `ClopOptimising` on the environment, not the concrete optimiser with a fake transport, and `isClopRunning: () -> Bool`, not `() -> String?` (2.1). The cost is one protocol and one empty conformance. Overrule only to exercise the optimiser's file checks inside coordinator tests; `ClopOptimiserTests` already does.
2. **LOG's scope.** The coordinator plus `RecordingRecovery.scan`. The mute sweep is not threaded (about 7 lines, no line unlocked), and `RecordingExtras` is left to `EXTRAS`. Two log members, not one, for the privacy split at the call site (2.3).
3. **`FakeDestination.download(key:to:)` records and writes** (3.2). A future Trim test through `downloadAndPresentTrimWindow` (+Trim:68) would then get a file under the real `tmp/`, which is `TMPDIRS`' business.
4. **SAVEAS 9 and 10 are new tests** on CT-2's helpers, not in-place extensions of the CT-2 tests. The marks are the same either way; in place, the suite line is 2350.
5. **E1 is included**: the deleted-while-open branch of `askSaveAsTarget` (RA:202-205), the one branch of the changed function nothing else reaches. It covers no line.
6. **recording-r1:340 and recording-r2:670 are full.** Save As… is CT-3's test, and each other verb has an existing test (tests-small.md SAVEAS.4). If a verb has none for a screenshot, the line becomes part.
7. **recording-r1:263 is full** on the reading that the relaunch and the junk file are set-up. `start()` handing `scan` the sink is read from the code (Coord:320-325), not driven (`TMPDIRS`, `LAUNCH`).
8. **coordinator-harness:27's wording stays** although the mark makes its "pins the state, not the `RecordingLog` text" history.
9. **Neighbours not marked.** phase-6a:169 (:188) and :173 (:192) are reached by SAVEAS test 1 but are not among the 49; they stay as they are.
10. **CLOP T7 enters at `finishSave`**, not `save(_:intent:)`, which no test can call (`CaptureTarget` holds an `SCDisplay` or `SCWindow`).
11. **seams.md ties keep the old table order** (section 11), and recording-r4:192 joins no seam: its by-hand part, the one selection on screen, is the drawn UI. The order of the three plan tasks is free; CLOP, SAVEAS, LOG is the proposal.

## 11. Deferred, and what seams.md records

- **`EXTRAS`**: recording-r3:416 (:452) and :436 (:482). The lines come from `RecordingExtras` (RecordingExtras.swift:215, :221, :235), fed only by a real `CameraSession`. When `EXTRAS` lands it adds `log: @escaping @Sendable (String) -> Void` to `RecordingExtras.init` (:60-71), and `makeRecordingExtras` passes `environment.recordingLog` (+Recording:438-449). Both are already under `EXTRAS` in seams.md. **`TMPDIRS` and `CAPSRC`**: recording-r4:217 (:221). The line is +Recording:411, in private `record()`, past `recordingCanStart` (the live `tmp/Recording`) and `loadContent`.
- **Part remainders by seam**: `TMPDIRS` recording-r1:296; `SCREENS` coordinator-split:44, phase-6a:172, :176, recording-r1:313; `PINS` coordinator-split:44, phase-6a:199; `WORKSPACE` recording-r2:264; `URLLOG` recording-r3:419. The other 10 part lines leave only checks by hand with no seam (tests-small.md 7.2).

**seams.md at close-out.** seams.md keeps its rules (seams.md:9-12). The close-out script edits it from this section, and a script that parses its line lists reproduces its current 404 / 186 / 279:

1. Every one of the 49 lines stays under its seam, its entry gaining its CT-3 verdict (`CT-3: full`, `CT-3: in part`, `CT-3: deferred`). phase-7-clop:28's free-text note ("would also need EDITOR; startUpload(fixedKey:) stands in") becomes "the editor half through `EDITOR` (landed in CT-2)". The `Shape` lines of sections 5 and 8 say what was built (2.1, 2.3).
2. Each part or deferred line joins the row of every other seam its mark names that does not list it yet, noted "also `<seam>`, in part since CT-3". `SCREENS` gains phase-6a:172 and :176; `PINS` phase-6a:199; `URLLOG` recording-r3:419; `TMPDIRS` and `CAPSRC` recording-r4:217. That is 6 new seam slots. Every other remainder is listed under its seam already.
3. The counts, redone by those rules and checked by the same parse: 42 seams; 279 B lines, unchanged; Lines 410; Alone 182; Completes 279; 97 lines need two or more seams (93 before); 15 seams unlock three or fewer (16 before; `URLLOG` goes to 4). The first three seams still complete 78 lines; the first ten complete 150 (152 before). Rows that change, as Lines / Alone / Completes, with ties kept in the old order: `CAPSRC` 34 / 8 / 8 (fourth, level with `TARGET`); `SAVEAS` 14 / 7 / 8; `SCREENS` 14 / 6 / 10 (tenth to eighth); `TMPDIRS` 13 / 7 / 8 (ninth); `LOG` 12 / 7 / 8 (eighth to tenth); `PINS` 10 / 5 / 9; `URLLOG` 4 / 2 / 4 (28th to 27th, ahead of `CHROMEMAP`). The section headers, the summary, the multi-seam section (`SAVEAS` + `SCREENS` goes from 1 line to 3, `LOG` + `URLLOG` from 1 to 2, `EDITOR` + `SAVEAS` from 2 to 1, and two groups are new: `EDITOR` + `SAVEAS` + `PINS` for phase-6a:199 and `LOG` + `TMPDIRS` + `CAPSRC` for recording-r4:217) and the three-or-fewer section are regenerated, and the script asserts the three sums.

lines-small.md's "only this seam (now)" column (SAVEAS 11, LOG 7) reads a line as needing only seams not yet built. seams.md's Alone column counts the line lists as written, with landed seams kept, so it is not the same number. Both are given; seams.md keeps its own rule.

## 12. Built notes

From the design's review (`.superpowers/sdd/ct3/judge.md` section 0). The judge merged the three designers' scratch trees into one tree at 30d3c15 with section 2's diffs, the fakes of section 3 and the 18 run tests: `Test run with 2336 tests in 195 suites passed after 50.947 seconds`, `** TEST SUCCEEDED **`. That is 2318 + CLOP 5 + SAVEAS 8 + LOG 5. The compiler gave no `warning:` in `TidyShot/` or `TidyShotTests/`, and the only `error:` lines were the known noise. The production diff is +94 −52 in nine files. Not run: a Release build of the merged tree (CLOP's tree alone built in Release), the 16 tests the catalogue adds, T3's extension and the two LOG test changes (tests-small.md 1, LOG.10; four of them ran in the facts review, below). The close-out adds the branch's suite line and Release build, the marks made and the seams.md edit.

From the facts review (`.superpowers/sdd/ct3/review-facts.md`), in a scratch tree with section 2's diffs, the fakes and the 18 run tests plus four catalogue tests (CLOP T7, T8, SAVEAS E1, the changed `stopRecordingLogsWhatItDidInEachPhase`): the focused run passed, 55 tests in 5 suites; the full run failed once on SAVEAS test 3's suggestion under the default template, since fixed by the template rule in section 5 (tests-small.md SAVEAS.2, test 3 step 2). The fixed tree's full run: `Test run with 2339 tests in 195 suites passed` (2336 + CLOP T7, T8 and SAVEAS E1; the changed `stopRecordingLogsWhatItDidInEachPhase` ran too). Not run: the other 12 catalogue tests and `aSettingsPromptLogsItsAnswerOrWhyItWaits`' changes. **For the plan:** the test bodies are written from `tests-small.md` (SAVEAS test 3 from its amended step 2); the review's scratch tree is a reference only, and where it and the catalogue differ the catalogue wins. CT-2's suites (`CoordinatorEditorTests`, `CoordinatorEditorSaveTests`, `CoordinatorEditorUploadTests`) are not edited in place: SAVEAS 9 and 10 are new tests (call 4) and CT-2's test keeps its direct read, or the suite line is 2350, not 2352.
