# TidyShot Coordinator Harness and Close-out, Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `AppCoordinator` takes its world as a parameter (`AppEnvironment`), so the suite builds one over temp folders, a fresh `UserDefaults` suite, an in-memory credential store and fakes, and fifty-six of its rules that were hand checks become tests. `pending/` gets its launch step: a file no record names is adopted, never deleted. And the R4 reviews' leftovers close: `UploadQueue.swift` splits into three files, an Abort that finds nothing is logged as such, a cancel during a stored upload's abort is tested, a part added after a cancel sends nothing, an upload whose first sidecar cannot be written is aborted, and the coordinator's log lines stop being format strings.

**Architecture:** `docs/superpowers/specs/2026-10-29-tidyshot-coordinator-harness-design.md` is the full specification. When this plan and the design disagree, the design wins, except where "Plan decisions" (at the end) says why the plan departs; stop and ask if anything else is unclear.
- **The environment.** `AppEnvironment` (a struct of values and closures with `.live()`, the shape `RecordingEnvironment` has) holds the coordinator's files, settings and the collaborators that reach the system. `AppCoordinator.init(environment: AppEnvironment = .live())` replaces `init()`; `static let shared = AppCoordinator()` is unchanged. The coordinator keeps every stored property and its name, built from the environment, so the extension files change only where they touched a global (Tasks 1 to 3).
- **Three protocols** (`Notifying`, `QuickAccessCards`, `Clipboard`) name what the coordinator calls; `Notifier`, `QuickAccessController` and the new `SystemClipboard` conform unchanged. `Destination` gains the two downloads, so every destination the coordinator holds is `any Destination` from `environment.makeDestination`.
- **The harness** (`TidyShotTests/Support/`): `FakeDestination` (moved from `UploadQueueTests.swift` and extended), `CoordinatorFakes.swift` and `CoordinatorWorld.swift`. Four suites drive the coordinator through its internal entry points; no `private` member opens.
- **Pure moves** (the coordinator split design, sections 2 and 5): `recoverRecordings` moves to `AppCoordinator+Recovery.swift`, and `UploadQueue.swift` splits into `UploadQueue.swift`, `UploadQueue+Multipart.swift` and `UploadQueue+Parts.swift`, each checked with the line-multiset check before any behaviour change lands on top.

**Tech Stack:** Swift 6 language mode with default `MainActor` isolation and `NonisolatedNonsendingByDefault`, Foundation, AppKit, ImageIO, AVFoundation (only through `VideoValidation` and `PosterFrame`), Swift concurrency (`Mutex`, `withTaskCancellationHandler`, `CheckedContinuation`), Swift Testing, XcodeGen 2.46.

Work happens on the branch `coordinator-harness`, cut from `main` at 6a52a7c (R4 merged). The design is committed (48b7cde). Line numbers below are the working tree's at 48b7cde (they equal 6a52a7c's for every source file); once an earlier task has moved or grown a file, find the code by the quoted text, which each step gives in full.

## Global Constraints

- **From the brief, verbatim:**
  - no behaviour change from the harness (the live environment builds what `init()` built);
  - no `private` member opened for tests;
  - no test touches `AppSettings.shared`, `NSPasteboard.general`, the Keychain, `UNUserNotificationCenter`, a window, the screen, the camera, the microphone, a sound or the network;
  - new suites run in parallel with the rest (own temp folders and defaults suite per test);
  - commits carry no attribution lines and no session URL;
  - the tests' `MovieSamples` decoder is untouched;
  - `RecordingLog.note` is untouched.
- **Earlier constraints still apply.** Minimum macOS 26.0, Swift 6 with MainActor by default and `NonisolatedNonsendingByDefault`, App Sandbox, XcodeGen, Swift Testing, ad-hoc signing, credentials only in the Keychain. KeyboardShortcuts is the only package. No new package, entitlement, Info.plist key or setting: `project.yml` does not change (new files are picked up by `xcodegen generate`).
- **The coordinator split's conventions.** New members start `private` in their area's file unless another file calls them; nothing outside `TidyShot/App/AppCoordinator*.swift` gains an entry point. The one new file is `TidyShot/App/AppCoordinator+Recovery.swift` (launch recovery).
- **Exact strings** come from the design or from the code as it stands. New log lines: `Upload: <name> multipart upload already gone`, `Recovery: <name> recovered`, `Recovery: <name> could not be read, removed`, `Recovery: <name> is empty, removed`, `Recovery: <name> <reason>, and could not be removed: <error>`. New notice title: `Recovered a capture`.
- **Tests** use Swift Testing. Run the full suite with:
  ```bash
  xcodegen generate && xcodebuild test -project TidyShot.xcodeproj -scheme TidyShot -destination 'platform=macOS' -derivedDataPath .build 2>&1 | grep -E "Test run with|error:|TEST"
  ```
  and one suite with `-only-testing:TidyShotTests/<Suite>` added before `2>&1`. The baseline is `Test run with 2090 tests in 174 suites passed` (R4's close-out); Task 1's first run confirms it, and if it differs every later count shifts by the same amount. The known noise lines (`History file could not be read or decoded, setting it aside` twice, `com.apple.linkd.autoShortcut`) are not failures. When coreaudiod stalls the suite takes about 126 s instead of about 40 s; that is not a failure. The Release build is `xcodebuild -project TidyShot.xcodeproj -scheme TidyShot -configuration Release -derivedDataPath .build-rel build`.
- **Keep out of the system.** No task runs the app, records, opens a camera or a microphone, plays a sound or talks to S3. The hand checks are Tim's and go in Task 16's checklist; each task's report says none were run.
- **Commits.** Commit after every task with the message the task gives and no attribution lines. Never push and never switch branches.

---

### Task 1: `AppEnvironment` and the three protocols [integration]

**Files:**
- Create `TidyShot/App/AppEnvironment.swift`.
- Modify `TidyShot/Output/Notifier.swift` (the `Notifying` protocol, at the end), `TidyShot/Overlay/QuickAccessController.swift` (the `QuickAccessCards` protocol, at the end), `TidyShot/Output/Pasteboard.swift` (`Clipboard` and `SystemClipboard`, at the end), `TidyShot/App/AppCoordinator.swift` (the Collaborators group :11-26 and `init` :262-274).

**Produces:** `AppEnvironment` with `.live()`; `DeleteConfirmation`; `Notifying`, `QuickAccessCards`, `Clipboard`, `SystemClipboard`; `AppCoordinator.init(environment:)`; the coordinator's `environment`, `saveLocation`, `settings`, `credentialStore`, `notifier`, `overlay` and the new `clipboard` built from it. No call site changes yet: the members that are not stored properties (`makeDestination`, `multipartPlan`, `uploadSleep`, `freeBytes`, `confirm`, `playShutter`, `now`, `clock`, `log`) are read from Task 2 on.

**Steps:**
- [ ] Run the full suite once and write down its line (the baseline).
- [ ] At the end of `TidyShot/Output/Notifier.swift`, add:
  ```swift

  /// What the coordinator asks of its notifier (harness design 2.2): `Notifier` in the app, a fake in
  /// the suite. The call forms with fewer arguments are in the extension below, so no call site changes.
  protocol Notifying: AnyObject {
      func setUp()
      func notifySaved(fileURL: URL, title: String)
      func notifyUploaded(url: URL, copied: Bool)
      func notifyError(_ message: String, title: String, subtitle: String?, revealing fileURL: URL?)
      func notify(title: String, body: String, subtitle: String?, openURL: URL?)
      func holdNotices()
      @discardableResult func releaseHeldNotices() -> Int
      func waitForReleasedNotices(upTo limit: Duration) async
  }

  extension Notifying {
      /// `Uploaded, URL copied`.
      func notifyUploaded(url: URL) {
          notifyUploaded(url: url, copied: true)
      }

      func notifyError(_ message: String, title: String = "Capture failed", subtitle: String? = nil) {
          notifyError(message, title: title, subtitle: subtitle, revealing: nil)
      }

      func notifyError(_ message: String, title: String, revealing fileURL: URL?) {
          notifyError(message, title: title, subtitle: nil, revealing: fileURL)
      }

      func notify(title: String, body: String, subtitle: String? = nil) {
          notify(title: title, body: body, subtitle: subtitle, openURL: nil)
      }

      func notify(title: String, body: String, openURL: URL?) {
          notify(title: title, body: body, subtitle: nil, openURL: openURL)
      }
  }

  extension Notifier: Notifying {}
  ```
- [ ] At the end of `TidyShot/Overlay/QuickAccessController.swift`, add:
  ```swift

  /// What the coordinator asks of the card stack (harness design 2.2): `QuickAccessController` in the
  /// app, a fake in the suite. `QuickAccessController.Actions` stays where it is.
  protocol QuickAccessCards: AnyObject {
      var windowNumbers: Set<CGWindowID> { get }
      var shownIDs: [UUID] { get }
      var screen: NSScreen? { get }
      var onDidClose: ((UUID, QuickAccessCloseReason) -> Void)? { get set }
      func isShowing(recordID: UUID) -> Bool
      func show(record: CaptureRecord, thumbnail: NSImage?, screen: NSScreen, autoCloseSeconds: Double,
                actions: QuickAccessController.Actions)
      func update(record: CaptureRecord)
      func setOptimizing(_ isOptimizing: Bool, for recordID: UUID)
      func setDownloading(_ status: DragDownloadStatus?, for recordID: UUID)
      func setLinkWasCopied(_ linkWasCopied: Bool, for recordID: UUID)
      func setTrimState(_ trimState: RecordingTrim.MenuState, for recordID: UUID)
      func setThumbnail(_ thumbnail: NSImage?, for recordID: UUID)
      func setDragFile(_ url: URL?, for recordID: UUID)
      func close(recordID: UUID, reason: QuickAccessCloseReason)
  }

  extension QuickAccessController: QuickAccessCards {}
  ```
- [ ] At the end of `TidyShot/Output/Pasteboard.swift`, add:
  ```swift

  /// The general pasteboard as the coordinator uses it (harness design 2.2): `SystemClipboard` in the
  /// app, a fake in the suite. Each `copy` returns the change count after the write, as `Pasteboard`'s
  /// do. The pure helpers (`includesTIFF`, `companionTIFF`, `tiffData`) stay on `Pasteboard`.
  protocol Clipboard: AnyObject {
      var changeCount: Int { get }
      /// Replaces the contents with `string` as plain text (Capture Text).
      func setString(_ string: String)
      @discardableResult func copy(image: CGImage, pngData: Data, scale: CGFloat) -> Int
      @discardableResult func copy(pngData: Data, tiffData: Data?) -> Int
      @discardableResult func copy(tiffData: Data?) -> Int
      @discardableResult func copy(fileURL: URL) -> Int
      @discardableResult func copy(url: URL) -> Int
      @discardableResult func copy(annotationClip data: Data) -> Int
      func annotationClipData() -> Data?
      var hasAnnotationClip: Bool { get }
  }

  /// `NSPasteboard.general`, through `Pasteboard`.
  final class SystemClipboard: Clipboard {
      var changeCount: Int { NSPasteboard.general.changeCount }

      func setString(_ string: String) {
          NSPasteboard.general.clearContents()
          NSPasteboard.general.setString(string, forType: .string)
      }

      @discardableResult func copy(image: CGImage, pngData: Data, scale: CGFloat) -> Int {
          Pasteboard.copy(image: image, pngData: pngData, scale: scale)
      }

      @discardableResult func copy(pngData: Data, tiffData: Data?) -> Int {
          Pasteboard.copy(pngData: pngData, tiffData: tiffData)
      }

      @discardableResult func copy(tiffData: Data?) -> Int {
          Pasteboard.copy(tiffData: tiffData)
      }

      @discardableResult func copy(fileURL: URL) -> Int {
          Pasteboard.copy(fileURL: fileURL)
      }

      @discardableResult func copy(url: URL) -> Int {
          Pasteboard.copy(url: url)
      }

      @discardableResult func copy(annotationClip data: Data) -> Int {
          Pasteboard.copy(annotationClip: data)
      }

      func annotationClipData() -> Data? {
          Pasteboard.annotationClipData()
      }

      var hasAnnotationClip: Bool { Pasteboard.hasAnnotationClip }
  }
  ```
- [ ] Create `TidyShot/App/AppEnvironment.swift`. The two alert bodies are `confirmDelete` and `confirmRemoveFromHistory` from `AppCoordinator+Delete.swift` (:228-264), copied here unchanged as statics; Task 3 removes the originals.
  ```swift
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
      /// Delete's two alerts: true for Delete or Remove.
      var confirm: @MainActor (DeleteConfirmation) async -> Bool
      var playShutter: @MainActor () -> Void
      var now: @Sendable () -> Date
      /// The coordinator's own waits: the drag folder's clean-up, a replaced lane's poll, a recording's
      /// settle delay without a count-in, and a quit's poll.
      var clock: any ScrollClock
      /// Every coordinator log line (`RecordingLog.note` keeps its own).
      var log: @Sendable (String) -> Void

      /// What the app runs on: the user's Application Support folder (the temporary folder when it
      /// cannot be had), the shared settings, the Keychain, the notification centre, the card stack,
      /// the general pasteboard, S3, the alerts, the shutter sound, the wall clock and `NSLog`. The
      /// collaborators are built in the order the coordinator's stored properties built them.
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
              confirm: { await AppEnvironment.confirmLive($0) },
              playShutter: { SoundPlayer.playShutter() },
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
  ```
- [ ] In `TidyShot/App/AppCoordinator.swift`, replace the Collaborators group's first lines (:11-26), from `    // MARK: Collaborators` through `    let overlay = QuickAccessController(settings: AppSettings.shared)`, with:
  ```swift
      // MARK: Collaborators
      /// What the coordinator was built over (harness design 2.1): `.live()` in the app, a test's world
      /// in the suite. The collaborators below come from it, and the extension files read its closures.
      let environment: AppEnvironment
      let engine = CaptureEngine()
      let saveLocation: SaveLocation
      let settings: AppSettings
      let history: HistoryStore
      /// `thumbnails` and `pending` folders next to `history.json`.
      let thumbnails: ThumbnailStore
      let pendingFiles: PendingFileStore
      /// `multipart` next to `history.json`: each multipart upload's part list and kept Clop copy.
      let multipartFiles: MultipartStore
      /// Drag-out copies, `<container tmp>/Drag/<id>/` (spec 2.9).
      let dragFiles: DragFileStore
      let credentialStore: any CredentialStore
      let notifier: any Notifying
      private let permissionWindow = PermissionWindowController()
      let overlay: any QuickAccessCards
      /// The general pasteboard, through `Clipboard`.
      let clipboard: any Clipboard
  ```
- [ ] Replace `init()` (:262-274) with:
  ```swift
      init(environment: AppEnvironment = .live()) {
          self.environment = environment
          saveLocation = environment.saveLocation
          settings = environment.settings
          credentialStore = environment.credentialStore
          notifier = environment.notifier
          overlay = environment.overlay
          clipboard = environment.clipboard
          let url = environment.historyFileURL
          // The shared settings in the app, read on each prune as before.
          let retentionSettings = environment.settings
          history = HistoryStore(fileURL: url, retentionDays: { retentionSettings.historyRetentionDays })
          thumbnails = ThumbnailStore(nextTo: url)
          pendingFiles = PendingFileStore(nextTo: url)
          multipartFiles = MultipartStore(nextTo: url)
          dragFiles = DragFileStore(temporaryDirectory: environment.temporaryDirectory)
          history.didPrune = { [weak self] records in self?.removeFiles(ofPruned: records) }
          overlay.onDidClose = { [weak self] id, reason in self?.overlayDidClose(id, reason: reason) }
          // The shown cards' Trim items follow a save folder chosen at any panel.
          saveLocation.didStoreFolder = { [weak self] in self?.refreshCardTrimStates() }
      }
  ```
- [ ] Check: `grep -n "AppSettings.shared\|Notifier()\|QuickAccessController(\|KeychainCredentialStore()\|SaveLocation()" TidyShot/App/AppCoordinator*.swift` prints nothing. The split design's initialiser-order check, `grep -nE '^    (private )?let (engine|saveLocation|settings|credentialStore|notifier|permissionWindow|overlay|clopOptimiser)\b' TidyShot/App/AppCoordinator.swift`, still lists the eight in that order.
- [ ] Run the full suite: the baseline line again.
- [ ] Commit: `refactor: AppEnvironment and the coordinator's three protocols`.

### Task 2: The coordinator's destinations through `Destination` [integration]

**Files:**
- Modify `TidyShot/Upload/Destination.swift` (two requirements after `download(key:to:)`, :20); `TidyShot/App/AppCoordinator+Upload.swift` (`UploadLane` :7-11, `makeDestination` :31-34, `startPlannedUpload` :90-91, `makeLane` :101-111, `startUpload` :123, `retry` :497 and :513, `deleteOrphanedObject` :733); `+Delete.swift` (:123, :156); `+RecordActions.swift` (`downloadSource` :262-270); `+DragOut.swift` (:108); `+Save.swift` (:140, :202); `+Editor.swift` (:361); `+Trim.swift` (:426); `TidyShot/Settings/UploadSettingsView.swift` (`test()` :176-183, the one caller of `makeDestination()` outside the coordinator); `TidyShot/Upload/ConnectionTester.swift` (`run` :38-43, `deleteProbe` :86).
- Tests: `TidyShotTests/UploadQueueTests.swift` (`FakeDestination` gains the two requirements as stubs; Task 4 scripts them); `TidyShotTests/ConnectionTesterTests.swift` (the seven `run` calls gain `keyTemplate:`).

**Produces:** `Destination.download(key:)` and `download(key:to:expectedBytes:resumeData:progress:)`; `AppCoordinator.UploadTarget { destination: any Destination; location: ObjectLocation; keyTemplate: String }`; `makeDestination() -> UploadTarget?`; every coordinator signature that carried `S3Destination` carries `UploadTarget` (the label `destination:` stays) or `any Destination` (`downloadSource`). `makeLane` reads the environment's `multipartPlan`, `uploadSleep`, `now` and `log`, whose live values are `UploadQueue`'s defaults. `ConnectionTester.run(destination: any Destination, keyTemplate: String, …)`, called by the Upload tab's connection test with `makeDestination()`'s target (D19).

**Steps:**
- [ ] In `Destination.swift`, after `    func download(key: String, to destination: URL) async throws`, add:
  ```swift
      /// GET Object into memory (Copy Image, a restored card's drag file). A 404 is an error.
      func download(key: String) async throws -> Data
      /// The drag-out download (`S3Destination+Download.swift`): a GET that lands at `landing`, with
      /// progress, replayed from `resumeData` when it is given.
      func download(key: String, to landing: URL, expectedBytes: Int64?, resumeData: Data?,
                    progress: @escaping @Sendable (Double) -> Void) async throws
  ```
  `S3Destination` already has both (S3Destination.swift:109, S3Destination+Download.swift:14).
- [ ] In `UploadQueueTests.swift`, after `    func download(key: String, to destination: URL) async throws {}` (:121), add:
  ```swift

      func download(key: String) async throws -> Data { Data() }

      func download(key: String, to landing: URL, expectedBytes: Int64?, resumeData: Data?,
                    progress: @escaping @Sendable (Double) -> Void) async throws {}
  ```
- [ ] `+Upload.swift`: after `UploadLane`'s closing brace (:11), add:
  ```swift

      /// What `makeDestination()` returns (harness design 2.2): the destination, where it writes and its
      /// key template, from one configuration. A lane is made from it.
      struct UploadTarget {
          let destination: any Destination
          let location: ObjectLocation
          let keyTemplate: String
      }
  ```
  Replace `makeDestination()` (:31-34) with:
  ```swift
      func makeDestination() -> UploadTarget? {
          guard let config = settings.s3Config, config.isComplete, let credentials = loadCredentials() else { return nil }
          // The live destination normalizes its configuration; the lane's location and template were read from that.
          let clean = config.normalized
          return UploadTarget(destination: environment.makeDestination(config, credentials),
                              location: ObjectLocation(config: clean), keyTemplate: clean.keyTemplate)
      }
  ```
  In `startPlannedUpload`, `destination: S3Destination) {` becomes `destination: UploadTarget) {`. Replace `makeLane` (:101-111) with:
  ```swift
      /// A queue for `target` whose events are handled with the location it uploads to.
      private func makeLane(for target: UploadTarget) -> UploadLane {
          let location = target.location
          let keyTemplate = target.keyTemplate
          let queue = UploadQueue(destination: target.destination,
                                  keyNamer: ObjectKeyNamer(template: keyTemplate),
                                  sleep: environment.uploadSleep,
                                  plan: environment.multipartPlan,
                                  store: multipartFiles,
                                  now: environment.now,
                                  log: environment.log,
                                  events: { [weak self] event in self?.handle(event, at: location) })
          return UploadLane(queue: queue, location: location, keyTemplate: keyTemplate)
      }
  ```
  `startUpload`'s signature (:123) becomes `func startUpload(recordID: UUID, payload: UploadPayload, destination: UploadTarget, fixedKey: String? = nil) {`. `retry`'s (:497) becomes `private func retry(recordID: UUID, destination: UploadTarget) {`, and its line `let location = queue?.location ?? ObjectLocation(config: destination.config)` (:513) becomes `let location = queue?.location ?? destination.location`. In `deleteOrphanedObject`, `let destination = S3Destination(config: location.config, credentials: credentials)` (:733) becomes `let destination = environment.makeDestination(location.config, credentials)`.
- [ ] `+Delete.swift`: `let destination = S3Destination(config: location.config, credentials: credentials)` (:123) becomes `let destination = environment.makeDestination(location.config, credentials)`; `let destination = S3Destination(config: ref.location.config, credentials: credentials)` (:156) becomes `let destination = environment.makeDestination(ref.location.config, credentials)`.
- [ ] `+RecordActions.swift`: `downloadSource`'s signature (:262) returns `(key: String, destination: any Destination)`, and its last line (:269) becomes `return (key, environment.makeDestination(location.config, credentials))`.
- [ ] `+DragOut.swift` (:108): `let source: (key: String, destination: S3Destination)` becomes `let source: (key: String, destination: any Destination)`.
- [ ] `+Save.swift`: in `persist` (:140) and `finishSave` (:202), `S3Destination?` becomes `UploadTarget?`.
- [ ] `+Editor.swift` (:361) and `+Trim.swift` (:426): `let location = queue?.location ?? ObjectLocation(config: destination.config)` becomes `let location = queue?.location ?? destination.location`.
- [ ] The Upload tab's connection test, the one caller of `makeDestination()` outside the coordinator (`grep -rn "makeDestination()" TidyShot | grep -v TidyShot/App/` finds only it), takes the target. In `ConnectionTester.swift`, `static func run(destination: S3Destination,` (:38) becomes
  ```swift
      static func run(destination: any Destination,
                      keyTemplate: String,
  ```
  (the `session:` and `randomString:` lines after it unchanged), `let namer = ObjectKeyNamer(template: destination.config.keyTemplate, randomString: randomString)` (:43) becomes `let namer = ObjectKeyNamer(template: keyTemplate, randomString: randomString)`, and `private static func deleteProbe(_ key: String, destination: S3Destination) async -> String? {` (:86) becomes `private static func deleteProbe(_ key: String, destination: any Destination) async -> String? {`. The probe uses only `upload(_:key:contentType:progress:)`, `publicURL(for:)` and `delete(key:)`, all on `Destination`. In `UploadSettingsView.swift`'s `test()`, `guard let destination = coordinator.makeDestination() else {` (:176) becomes `guard let target = coordinator.makeDestination() else {`, and `let result = await ConnectionTester.run(destination: destination)` (:183) becomes `let result = await ConnectionTester.run(destination: target.destination, keyTemplate: target.keyTemplate)`. In `ConnectionTesterTests.swift`, each of the seven `ConnectionTester.run(destination: destination(session), ` becomes `ConnectionTester.run(destination: destination(session), keyTemplate: config.normalized.keyTemplate, ` (the template `S3Destination.config` held):
  ```bash
  sed -i '' 's/ConnectionTester\.run(destination: destination(session), /ConnectionTester.run(destination: destination(session), keyTemplate: config.normalized.keyTemplate, /' TidyShotTests/ConnectionTesterTests.swift
  grep -c "keyTemplate: config.normalized.keyTemplate" TidyShotTests/ConnectionTesterTests.swift   # 7
  ```
- [ ] Check: `grep -n "S3Destination\|destination\.config" TidyShot/App/AppCoordinator*.swift` prints nothing, and `grep -nE "destination\.config|S3Destination([^C]|$)" TidyShot/Upload/ConnectionTester.swift TidyShot/Settings/UploadSettingsView.swift` prints nothing (`S3DestinationConfig` in the view stays).
- [ ] Run the full suite: the baseline line.
- [ ] Commit: `refactor: the coordinator's destinations through the Destination protocol`.

### Task 3: The log, the clock, the time, the clipboard, the alerts, the free space and the shutter [mechanical]

**Files:** every `TidyShot/App/AppCoordinator*.swift` file.

**Produces:** `func log(_ message: String)` on the coordinator; no `NSLog`, `NSPasteboard`, `Pasteboard.copy`, `SoundPlayer`, `Date()`, `Task.sleep` or `RecordingLimits.freeBytes` left in the coordinator's code (`log(_:)`'s doc comment names the live `NSLog("%@", …)`); Delete's alerts through `environment.confirm`; `removePartialDownload` looks in `environment.temporaryDirectory`. The live environment does what each replaced call did; `NSLog("%@", …)` for every line is the design's fix for the lines that interpolated an error into a format string.

**Steps:**
- [ ] In `AppCoordinator.swift`, after `init(environment:)`'s closing brace, add:
  ```swift

      /// A coordinator log line, through the environment (`NSLog("%@", …)` in the app).
      func log(_ message: String) {
          environment.log(message)
      }
  ```
- [ ] Run from the repo root:
  ```bash
  perl -pi -e 'next if m{^\s*///}; s/NSLog\("%@", /log(/g; s/NSLog\(/log(/g; s/NSPasteboard\.general\.changeCount/clipboard.changeCount/g; s/\bPasteboard\.copy\(/clipboard.copy(/g; s/\bPasteboard\.annotationClipData\(\)/clipboard.annotationClipData()/g; s/\bPasteboard\.hasAnnotationClip\b/clipboard.hasAnnotationClip/g; s/SoundPlayer\.playShutter\(\)/environment.playShutter()/g' TidyShot/App/AppCoordinator*.swift
  ```
  This turns the 52 `NSLog` lines into `log(...)` with the same text, the `Pasteboard.copy` and `NSPasteboard.general.changeCount` sites into the clipboard's, and the three shutters into the environment's. Doc-comment lines (`///`) are skipped, so the comment just added keeps its `NSLog("%@", …)`; no other `///` line in these files names any of the replaced calls.
- [ ] Three of the new `log(...)` calls run off the main actor and must use a captured copy of the closure:
  - `+Save.swift`, `makeThumbnail`: after `        let store = thumbnails` add `        let log = environment.log`.
  - `+Editor.swift`, `replaceThumbnail`: after `        let name = store.fileName(for: id, editedAt: editedAt)` add `        let log = environment.log`.
  - `+RecordActions.swift`, `openCapture`: before `                NSWorkspace.shared.open(fileURL, configuration: NSWorkspace.OpenConfiguration()) { _, error in` add `                let log = environment.log`.
  And in `+DragOut.swift`'s progress report, `                    log("Drag-out download for \(recordID) resumed at \(String(format: "%.4f", fraction))")` becomes `                    self.log("Drag-out download for \(recordID) resumed at \(String(format: "%.4f", fraction))")`.
- [ ] `+Editor.swift` (:114-116), the object clipboard's closures need the clipboard captured. After the perl run they read `copy: { data in clipboard.copy(annotationClip: data) },` / `paste: { clipboard.annotationClipData() },` / `canPaste: { clipboard.hasAnnotationClip }),`; make them:
  ```swift
                  copy: { [clipboard] data in clipboard.copy(annotationClip: data) },
                  paste: { [clipboard] in clipboard.annotationClipData() },
                  canPaste: { [clipboard] in clipboard.hasAnnotationClip }),
  ```
- [ ] `+Capture.swift` (:284-285): `        NSPasteboard.general.clearContents()` and `        NSPasteboard.general.setString(text, forType: .string)` become one line, `        clipboard.setString(text)`.
- [ ] `+Delete.swift`: delete `confirmDelete(of:)` and `confirmRemoveFromHistory(message:informativeText:)` with their doc comments (:228-264; they are in `AppEnvironment` now). Then:
  - `            guard confirmDelete(of: record) else { return }` becomes `            guard await environment.confirm(.delete(record)) else { return }`.
  - Both
    ```swift
    if await confirmRemoveFromHistory(message: CaptureDeletion.storageFailureMessage(reason: reason),
                                      informativeText: CaptureDeletion.storageFailureText) {
    ```
    (at :44-45, indented 12, and :63-64, indented 16) become, at the same indent,
    ```swift
    if await environment.confirm(.removeFromHistory(message: CaptureDeletion.storageFailureMessage(reason: reason),
                                                    informativeText: CaptureDeletion.storageFailureText)) {
    ```
  - `                    if await confirmRemoveFromHistory(message: message, informativeText: CaptureDeletion.fileFailureText) {` (:84) becomes `                    if await environment.confirm(.removeFromHistory(message: message, informativeText: CaptureDeletion.fileFailureText)) {`.
- [ ] The time: `        let now = Date()` (+DragOut:123) becomes `        let now = environment.now()`; `        let editedAt = Date()` (+Editor:212 and +Trim:307) becomes `        let editedAt = environment.now()`; `        let startedAt = record?.timestamp ?? Date()` (+RecordActions:322) becomes `        let startedAt = record?.timestamp ?? environment.now()`; in `start()` (AppCoordinator.swift:289-290),
  ```swift
          let multipartFiles = multipartFiles
          Task.detached(priority: .utility) { multipartFiles.sweep(states: multipartStates, now: Date()) }
  ```
  becomes
  ```swift
          let multipartFiles = multipartFiles
          let now = environment.now
          Task.detached(priority: .utility) { multipartFiles.sweep(states: multipartStates, now: now()) }
  ```
- [ ] The clock:
  - `+DragOut.swift`, `scheduleDragCleanup`: `        dragCleanups[id] = Task { [weak self] in` / `            try? await Task.sleep(for: Self.dragCleanupDelay)` becomes
    ```swift
            let clock = environment.clock
            dragCleanups[id] = Task { [weak self] in
                try? await clock.sleep(for: Self.dragCleanupDelay)
    ```
  - `+Upload.swift`, `destinationDidChange`: before `        Task { [weak self] in` add `        let clock = environment.clock`, and `                try? await Task.sleep(for: .milliseconds(500))` becomes `                try? await clock.sleep(for: .milliseconds(500))`.
  - `+Recording.swift` (:509): `            try? await Task.sleep(for: SelfTimerController.settleDelay)` becomes `            try? await environment.clock.sleep(for: SelfTimerController.settleDelay)`.
  - `AppCoordinator.swift` (:466): `            try? await Task.sleep(for: Self.quitPollInterval)` becomes `            try? await environment.clock.sleep(for: Self.quitPollInterval)`.
- [ ] The free space:
  - `+DragOut.swift` (:103): `                                       freeBytes: RecordingLimits.freeBytes(at: dragFiles.directory)) else {` becomes `                                       freeBytes: environment.freeBytes(dragFiles.directory)) else {`.
  - `+Recording.swift` (:355): `        let freeBytes = RecordingLimits.freeBytes(at: Recording.directory)` becomes `        let freeBytes = environment.freeBytes(Recording.directory)`.
  - `+Recording.swift`, `makeGIF`: before `        let conversion = GIFConversion(` add `        let freeBytes = environment.freeBytes`; then both `{ RecordingLimits.freeBytes(at: Recording.directory) }` in that call become `{ freeBytes(Recording.directory) }`.
  - `+Trim.swift` (:209): `                freeBytes: { RecordingLimits.freeBytes(at: RecordingTrim.directory) },` becomes `                freeBytes: { [freeBytes = environment.freeBytes] in freeBytes(RecordingTrim.directory) },`.
- [ ] `+DragOut.swift`, `removePartialDownload` (:218-223) becomes:
  ```swift
      private func removePartialDownload(_ resumeData: Data) {
          let temporaryDirectory = environment.temporaryDirectory
          Task.detached(priority: .utility) {
              guard let partial = DragDownloadRule.partialFile(in: resumeData, temporaryDirectory: temporaryDirectory)
              else { return }
              try? FileManager.default.removeItem(at: partial)
          }
      }
  ```
- [ ] Check: `grep -nE "NSLog|NSPasteboard|Pasteboard\.copy|Pasteboard\.annotationClipData|Pasteboard\.hasAnnotationClip|SoundPlayer|Date\(\)|Task\.sleep|RecordingLimits\.freeBytes|confirmDelete|confirmRemoveFromHistory" TidyShot/App/AppCoordinator*.swift | grep -vE '^[^:]+:[0-9]+:[[:space:]]*///'` prints nothing (the filter drops doc comments, such as `log(_:)`'s). `grep -c "log(" TidyShot/App/AppCoordinator*.swift | awk -F: '{s+=$2} END {print s}'` is at least 52.
- [ ] Run the full suite: the baseline line.
- [ ] Commit: `refactor: the coordinator's log, clock, clipboard and alerts through its environment`.

### Task 4: The harness's support and a smoke test [integration]

**Files:**
- Create `TidyShotTests/Support/FakeDestination.swift` (moved out of `UploadQueueTests.swift`, then extended), `TidyShotTests/Support/CoordinatorFakes.swift`, `TidyShotTests/Support/CoordinatorWorld.swift`, `TidyShotTests/CoordinatorWorldTests.swift`.
- Modify `TidyShotTests/UploadQueueTests.swift` (the `FakeDestination` block leaves it).

**Produces:**
- `FakeDestination`, unchanged, plus: a scripted drag-out download (`downloadOutcome`, `downloadFractions`, `holdsDownloads` with `releaseDownloads()`, `downloads`, `downloadCancellations`, `reportLateFraction(_:)`), a scripted `download(key:)`, `deletedKeys`, a held part (`holdingPart` with `releaseParts()`, `heldPartCancellations`), and blocked or held Aborts (`blockingAbortsRemaining`, `holdingAbortsRemaining` with `releaseAborts()`, `heldAbortCancellations`).
- `FakeNotifier`, `FakeCards`, `FakeClipboard`, `FakeConfirm`, `FakeDestinationFactory`, `CoordinatorWorldState`, `ThrowingCredentialStore`, `HeldCameraDevices`, `TestGate`, `TaskWatch`. The three held fakes (`FakeConfirm` while it holds, `HeldCameraDevices`, `TestGate`) end a wait when its task is cancelled, and a second entry while one waits records an `Issue` and returns at once, so a regression fails a test instead of hanging the run. `TaskWatch` says whether a task has returned, so a test gates on it with `eventually` rather than awaiting a call whose only way out is the behaviour under test.
- `CoordinatorWorld` with `makeCoordinator()` and `removeAll()`.

**Steps:**
- [ ] Move `FakeDestination` out, byte for byte:
  ```bash
  python3 - <<'EOF'
  from pathlib import Path
  tests = Path("TidyShotTests/UploadQueueTests.swift")
  text = tests.read_text()
  start = text.index("/// Scripted destination: records calls")
  end = text.index("/// Counts security-scope starts and stops")
  Path("TidyShotTests/Support/FakeDestination.swift").write_text(
      "import Foundation\nimport Synchronization\n@testable import TidyShot\n\n" + text[start:end].rstrip() + "\n")
  tests.write_text(text[:start] + text[end:])
  EOF
  ```
- [ ] In `FakeDestination.swift`, after `        var objectSizeKeys: [String] = []` (the last field of `State`), add:
  ```swift

          // The coordinator harness (harness design 2.4): the downloads, Delete's DELETEs, a held part
          // and blocked or held Aborts.

          /// What a drag-out download does once any hold is released: reports `downloadFractions`, then
          /// lands `downloadOutcome`'s bytes at the landing path or throws its error.
          var downloadOutcome: DownloadOutcome = .lands(bytes: 4)
          var downloadFractions: [Double] = [0.5, 1]
          /// Each drag-out download's key and resume data, in order.
          var downloads: [(key: String, resumeData: Data?)] = []
          /// When true, each drag-out download waits for `releaseDownloads()`, even when its task is
          /// cancelled, like a transfer that finishes just as it is cancelled.
          var holdsDownloads = false
          var heldDownloads: [CheckedContinuation<Void, Never>] = []
          var downloadsReleased = false
          /// Times a held download's task was cancelled while it waited.
          var downloadCancellations = 0
          /// The last drag-out download's progress callback, for a fraction that comes after its end.
          var downloadProgress: (@Sendable (Double) -> Void)?
          /// What `download(key:)` returns, and the keys it was asked for.
          var downloadedData = Data("object".utf8)
          var dataDownloadKeys: [String] = []
          /// Every `delete(key:)`, in order.
          var deletedKeys: [String] = []
          /// This part waits for `releaseParts()` before it reports anything, even when its task is
          /// cancelled, then answers.
          var holdingPart: Int?
          var heldParts: [CheckedContinuation<Void, Never>] = []
          var partsReleased = false
          var heldPartCancellations = 0
          /// This many Aborts wait a minute instead of answering; the wait throws `CancellationError`
          /// when the task is cancelled.
          var blockingAbortsRemaining = 0
          /// This many Aborts (after any blocking ones) wait for `releaseAborts()` even when their task
          /// is cancelled, then answer.
          var holdingAbortsRemaining = 0
          var heldAborts: [CheckedContinuation<Void, Never>] = []
          var abortsReleased = false
          var heldAbortCancellations = 0
  ```
  and, after `State`'s closing brace (before `    let state: Mutex<State>`), add:
  ```swift

      /// How a drag-out download ends.
      enum DownloadOutcome: Sendable {
          /// A file of this many bytes at the landing path.
          case lands(bytes: Int)
          case fails(any Error & Sendable)
      }
  ```
- [ ] Replace the Task 2 stubs
  ```swift
      func download(key: String) async throws -> Data { Data() }

      func download(key: String, to landing: URL, expectedBytes: Int64?, resumeData: Data?,
                    progress: @escaping @Sendable (Double) -> Void) async throws {}
  ```
  with:
  ```swift
      func download(key: String) async throws -> Data {
          state.withLock { state in
              state.dataDownloadKeys.append(key)
              return state.downloadedData
          }
      }

      func download(key: String, to landing: URL, expectedBytes: Int64?, resumeData: Data?,
                    progress: @escaping @Sendable (Double) -> Void) async throws {
          let holds = state.withLock { state in
              state.downloads.append((key, resumeData))
              state.downloadProgress = progress
              return state.holdsDownloads
          }
          if holds {
              await withTaskCancellationHandler {
                  await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                      let released = state.withLock { state in
                          if state.downloadsReleased { return true }
                          state.heldDownloads.append(continuation)
                          return false
                      }
                      if released { continuation.resume() }
                  }
              } onCancel: {
                  state.withLock { $0.downloadCancellations += 1 }
              }
          }
          let (fractions, outcome) = state.withLock { ($0.downloadFractions, $0.downloadOutcome) }
          for fraction in fractions {
              progress(fraction)
          }
          switch outcome {
          case .lands(let bytes):
              try Data(count: bytes).write(to: landing)
          case .fails(let error):
              throw error
          }
      }

      /// Lets every held download go on, now and later.
      func releaseDownloads() {
          let held = state.withLock { state in
              state.downloadsReleased = true
              defer { state.heldDownloads = [] }
              return state.heldDownloads
          }
          for continuation in held { continuation.resume() }
      }

      /// Calls the last download's progress callback, after the download has ended.
      func reportLateFraction(_ fraction: Double) {
          state.withLock { $0.downloadProgress }?(fraction)
      }
  ```
- [ ] Replace `    func delete(key: String) async throws {}` with:
  ```swift
      func delete(key: String) async throws {
          state.withLock { $0.deletedKeys.append(key) }
      }
  ```
- [ ] In `uploadPart`, after `        defer { state.withLock { $0.partsInFlight -= 1 } }`, add:
  ```swift
          if state.withLock({ $0.holdingPart == number }) {
              await withTaskCancellationHandler {
                  await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                      let released = state.withLock { state in
                          if state.partsReleased { return true }
                          state.heldParts.append(continuation)
                          return false
                      }
                      if released { continuation.resume() }
                  }
              } onCancel: {
                  state.withLock { $0.heldPartCancellations += 1 }
              }
          }
  ```
  and after `uploadPart`'s closing brace add:
  ```swift

      /// Lets the held part, and a later one with its number, answer.
      func releaseParts() {
          let held = state.withLock { state in
              state.partsReleased = true
              defer { state.heldParts = [] }
              return state.heldParts
          }
          for continuation in held { continuation.resume() }
      }
  ```
- [ ] Replace `abortMultipartUpload` with:
  ```swift
      func abortMultipartUpload(key: String, uploadID: String) async throws -> MultipartAbortResult {
          let (failure, result, blocks, holds) = record("abort") { state in
              state.aborts.append((key, uploadID))
              let blocks = state.blockingAbortsRemaining > 0
              if blocks { state.blockingAbortsRemaining -= 1 }
              let holds = !blocks && state.holdingAbortsRemaining > 0
              if holds { state.holdingAbortsRemaining -= 1 }
              return (Self.nextFailure(&state.abortFailures), state.abortResult, blocks, holds)
          }
          if blocks {
              try await Task.sleep(for: .seconds(60))
          }
          if holds {
              await withTaskCancellationHandler {
                  await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                      let released = state.withLock { state in
                          if state.abortsReleased { return true }
                          state.heldAborts.append(continuation)
                          return false
                      }
                      if released { continuation.resume() }
                  }
              } onCancel: {
                  state.withLock { $0.heldAbortCancellations += 1 }
              }
          }
          if let failure { throw failure }
          return result
      }

      /// Lets every held Abort answer, now and later.
      func releaseAborts() {
          let held = state.withLock { state in
              state.abortsReleased = true
              defer { state.heldAborts = [] }
              return state.heldAborts
          }
          for continuation in held { continuation.resume() }
      }
  ```
- [ ] Create `TidyShotTests/Support/CoordinatorFakes.swift`:
  ```swift
  import AppKit
  import Foundation
  import Synchronization
  import Testing
  @testable import TidyShot

  /// The coordinator's notifier in the suite: every call as a value, in order (harness design 2.4).
  final class FakeNotifier: Notifying {
      enum Call: Equatable {
          case setUp
          case saved(title: String, file: String)
          case uploaded(url: URL, copied: Bool)
          case error(title: String, message: String)
          case notice(title: String, body: String)
          case held
          case released
          case waited(Duration)
      }

      private(set) var calls: [Call] = []

      /// The `notifyError` calls, in order.
      var errors: [(title: String, message: String)] {
          calls.compactMap { call -> (title: String, message: String)? in
              guard case .error(let title, let message) = call else { return nil }
              return (title, message)
          }
      }

      func setUp() { calls.append(.setUp) }

      func notifySaved(fileURL: URL, title: String) {
          calls.append(.saved(title: title, file: fileURL.lastPathComponent))
      }

      func notifyUploaded(url: URL, copied: Bool) { calls.append(.uploaded(url: url, copied: copied)) }

      func notifyError(_ message: String, title: String, subtitle: String?, revealing fileURL: URL?) {
          calls.append(.error(title: title, message: message))
      }

      func notify(title: String, body: String, subtitle: String?, openURL: URL?) {
          calls.append(.notice(title: title, body: body))
      }

      func holdNotices() { calls.append(.held) }

      func releaseHeldNotices() -> Int {
          calls.append(.released)
          return 0
      }

      /// Runs at each `waitForReleasedNotices`, before it returns, so a test can read the coordinator's
      /// state at the moment of the wait (test 56).
      var onWait: (() -> Void)?

      func waitForReleasedNotices(upTo limit: Duration) async {
          calls.append(.waited(limit))
          onWait?()
      }
  }

  /// The card stack in the suite: what the coordinator told it, in order, and the records a test
  /// says are showing. No card is ever made. A close of a showing record reports it, as the real
  /// stack does.
  final class FakeCards: QuickAccessCards {
      enum Call: Equatable {
          case show(UUID)
          case update(UUID, CaptureRecord.UploadState)
          case optimizing(UUID, Bool)
          case downloading(UUID, DragDownloadStatus?)
          case linkWasCopied(UUID, Bool)
          case trimState(UUID)
          case thumbnail(UUID)
          case dragFile(UUID, URL?)
          case close(UUID, QuickAccessCloseReason)
      }

      /// A card's download status as set, with nil as `.cleared`.
      enum DownloadShown: Equatable {
          case running(Double)
          case failed(String)
          case cleared
      }

      private(set) var calls: [Call] = []
      /// The records whose card shows.
      var showing: Set<UUID> = []
      var onDidClose: ((UUID, QuickAccessCloseReason) -> Void)?

      var windowNumbers: Set<CGWindowID> { [] }
      var shownIDs: [UUID] { Array(showing) }
      var screen: NSScreen? { nil }

      func isShowing(recordID: UUID) -> Bool { showing.contains(recordID) }

      func show(record: CaptureRecord, thumbnail: NSImage?, screen: NSScreen, autoCloseSeconds: Double,
                actions: QuickAccessController.Actions) {
          showing.insert(record.id)
          calls.append(.show(record.id))
      }

      func update(record: CaptureRecord) { calls.append(.update(record.id, record.uploadState)) }
      func setOptimizing(_ isOptimizing: Bool, for recordID: UUID) { calls.append(.optimizing(recordID, isOptimizing)) }
      func setDownloading(_ status: DragDownloadStatus?, for recordID: UUID) { calls.append(.downloading(recordID, status)) }
      func setLinkWasCopied(_ linkWasCopied: Bool, for recordID: UUID) { calls.append(.linkWasCopied(recordID, linkWasCopied)) }
      func setTrimState(_ trimState: RecordingTrim.MenuState, for recordID: UUID) { calls.append(.trimState(recordID)) }
      func setThumbnail(_ thumbnail: NSImage?, for recordID: UUID) { calls.append(.thumbnail(recordID)) }
      func setDragFile(_ url: URL?, for recordID: UUID) { calls.append(.dragFile(recordID, url)) }

      func close(recordID: UUID, reason: QuickAccessCloseReason) {
          calls.append(.close(recordID, reason))
          guard showing.remove(recordID) != nil else { return }
          onDidClose?(recordID, reason)
      }

      /// The download statuses set for `id`, in order.
      func downloads(for id: UUID) -> [DownloadShown] {
          calls.compactMap { call -> DownloadShown? in
              guard case .downloading(let callID, let status) = call, callID == id else { return nil }
              switch status {
              case .some(.running(let fraction)): return .running(fraction)
              case .some(.failed(let message)): return .failed(message)
              case .none: return .cleared
              }
          }
      }

      /// The drag files handed to `id`'s card, in order.
      func dragFiles(for id: UUID) -> [URL?] {
          calls.compactMap { call -> URL?? in
              guard case .dragFile(let callID, let url) = call, callID == id else { return nil }
              return .some(url)
          }
      }

      /// The upload states pushed to `id`'s card, in order.
      func updates(for id: UUID) -> [CaptureRecord.UploadState] {
          calls.compactMap { call -> CaptureRecord.UploadState? in
              guard case .update(let callID, let state) = call, callID == id else { return nil }
              return state
          }
      }

      /// Every close, in order.
      var closes: [QuickAccessCloseReason] {
          calls.compactMap { call -> QuickAccessCloseReason? in
              guard case .close(_, let reason) = call else { return nil }
              return reason
          }
      }
  }

  /// The pasteboard in the suite: what was put there, in order. Every write moves `changeCount`, as
  /// the pasteboard's does, and a test moves it to stand for a copy made elsewhere.
  final class FakeClipboard: Clipboard {
      enum Copy: Equatable {
          case image
          case pngAndTIFF
          case tiff
          case fileURL(URL)
          case url(URL)
          case annotationClip(Data)
          case string(String)
      }

      private(set) var copies: [Copy] = []
      var changeCount = 0
      var annotationClip: Data?

      func setString(_ string: String) { write(.string(string)) }
      func copy(image: CGImage, pngData: Data, scale: CGFloat) -> Int { write(.image) }
      func copy(pngData: Data, tiffData: Data?) -> Int { write(.pngAndTIFF) }
      func copy(tiffData: Data?) -> Int { write(.tiff) }
      func copy(fileURL: URL) -> Int { write(.fileURL(fileURL)) }
      func copy(url: URL) -> Int { write(.url(url)) }

      func copy(annotationClip data: Data) -> Int {
          annotationClip = data
          return write(.annotationClip(data))
      }

      func annotationClipData() -> Data? { annotationClip }
      var hasAnnotationClip: Bool { annotationClip != nil }

      @discardableResult
      private func write(_ copy: Copy) -> Int {
          copies.append(copy)
          changeCount += 1
          return changeCount
      }
  }

  /// Delete's alerts in the suite: each question, in order, answered from `answers` (Yes when they
  /// run out), or held until `answer(_:)` while `holds` is set. A held question whose task is
  /// cancelled is answered Cancel, so a suite's time limit can end it. A second question while one
  /// is held is a fault in the code under test: it is recorded as an issue and answered Cancel at
  /// once, so the test fails instead of hanging.
  final class FakeConfirm {
      private(set) var asked: [DeleteConfirmation] = []
      var answers: [Bool] = []
      var holds = false
      private var waiter: (id: Int, continuation: CheckedContinuation<Bool, Never>)?
      private var nextID = 0

      var isWaiting: Bool { waiter != nil }

      func confirm(_ question: DeleteConfirmation) async -> Bool {
          asked.append(question)
          guard holds else { return answers.isEmpty ? true : answers.removeFirst() }
          guard waiter == nil else {
              Issue.record("FakeConfirm was asked again while a question was held")
              return false
          }
          guard !Task.isCancelled else { return false }
          let id = nextID
          nextID += 1
          return await withTaskCancellationHandler {
              await withCheckedContinuation { waiter = (id, $0) }
          } onCancel: {
              Task { @MainActor in self.resume(false, id: id) }
          }
      }

      /// Answers the held question; later ones come from `answers`.
      func answer(_ yes: Bool) {
          holds = false
          resume(yes, id: nil)
      }

      /// Resumes the held question: any one when `id` is nil, otherwise only the one it names.
      private func resume(_ yes: Bool, id: Int?) {
          guard let waiter, id == nil || waiter.id == id else { return }
          self.waiter = nil
          waiter.continuation.resume(returning: yes)
      }
  }

  /// `environment.makeDestination` in the suite: a `FakeDestination` per location, `standard` for the
  /// rest, and every configuration asked for. Called off the main actor, so it is locked.
  nonisolated final class FakeDestinationFactory: Sendable {
      private struct State {
          var byLocation: [ObjectLocation: FakeDestination] = [:]
          var asked: [S3DestinationConfig] = []
      }

      /// The destination of any location without its own, the world's Upload settings' among them.
      let standard = FakeDestination()
      private let state = Mutex(State())

      /// Hands out `destination` for every configuration that writes to `location`.
      func add(_ destination: FakeDestination, at location: ObjectLocation) {
          state.withLock { $0.byLocation[location] = destination }
      }

      /// The configurations asked for, in order.
      var askedConfigs: [S3DestinationConfig] { state.withLock { $0.asked } }
      var askedLocations: [ObjectLocation] { askedConfigs.map { ObjectLocation(config: $0) } }

      func make(_ config: S3DestinationConfig, _ credentials: AWSCredentials) -> any Destination {
          let location = ObjectLocation(config: config)
          let found = state.withLock { state -> FakeDestination? in
              state.asked.append(config)
              return state.byLocation[location]
          }
          return found ?? standard
      }
  }

  /// The world's values that the coordinator's `@Sendable` closures read and write: the date, the
  /// free space and the log. Locked, as a closure may run off the main actor.
  nonisolated final class CoordinatorWorldState: Sendable {
      private struct Values {
          var date = Date(timeIntervalSinceReferenceDate: 800_000_000)
          var freeBytes: Int64? = 100_000_000_000
          var freeBytesAsked: [URL] = []
          var lines: [String] = []
      }

      private let values = Mutex(Values())

      var date: Date {
          get { values.withLock { $0.date } }
          set { values.withLock { $0.date = newValue } }
      }

      var freeBytes: Int64? {
          get { values.withLock { $0.freeBytes } }
          set { values.withLock { $0.freeBytes = newValue } }
      }

      var freeBytesAsked: [URL] { values.withLock { $0.freeBytesAsked } }
      var lines: [String] { values.withLock { $0.lines } }

      func freeBytes(at url: URL) -> Int64? {
          values.withLock { values in
              values.freeBytesAsked.append(url)
              return values.freeBytes
          }
      }

      func append(_ line: String) {
          values.withLock { $0.lines.append(line) }
      }
  }

  nonisolated struct CredentialReadFailed: LocalizedError {
      var errorDescription: String? { "The keychain is locked." }
  }

  /// A credential store whose every read fails, as a locked or denied Keychain does.
  final class ThrowingCredentialStore: CredentialStore {
      func load(account: String) throws -> AWSCredentials? { throw CredentialReadFailed() }
      func save(_ credentials: AWSCredentials, account: String) throws { throw CredentialReadFailed() }
      func delete(account: String) throws { throw CredentialReadFailed() }
  }

  /// Cameras whose access prompt stays open until `answer(_:)`, so a test can look while it is up. A
  /// prompt whose task is cancelled ends as refused, so a suite's time limit can end it. A second
  /// prompt while one is open is recorded as an issue and refused at once, so a regression fails the
  /// test instead of hanging it.
  final class HeldCameraDevices: CameraDevices {
      var currentAccess = CameraAccess.notDetermined
      private(set) var requestCount = 0
      private var waiter: (id: Int, continuation: CheckedContinuation<Bool, Never>)?
      private var nextID = 0

      var isAsking: Bool { waiter != nil }

      func list() -> [CameraDevice] { [] }
      func preferred() -> CameraDevice? { nil }
      func access() -> CameraAccess { currentAccess }

      func requestAccess() async -> Bool {
          requestCount += 1
          guard waiter == nil else {
              Issue.record("HeldCameraDevices was asked again while its prompt was open")
              return false
          }
          guard !Task.isCancelled else { return false }
          let id = nextID
          nextID += 1
          return await withTaskCancellationHandler {
              await withCheckedContinuation { waiter = (id, $0) }
          } onCancel: {
              Task { @MainActor in self.resume(false, id: id) }
          }
      }

      func answer(_ granted: Bool) {
          currentAccess = granted ? .authorized : .denied
          resume(granted, id: nil)
      }

      /// Resumes the open prompt: any one when `id` is nil, otherwise only the one it names.
      private func resume(_ granted: Bool, id: Int?) {
          guard let waiter, id == nil || waiter.id == id else { return }
          self.waiter = nil
          waiter.continuation.resume(returning: granted)
      }
  }

  /// A wait a test opens by hand, for a body held inside the capture lock. A wait whose task is
  /// cancelled ends, so a suite's time limit can end it. A second wait while one is open is recorded
  /// as an issue and ends at once.
  final class TestGate {
      private var waiter: (id: Int, continuation: CheckedContinuation<Void, Never>)?
      private var nextID = 0

      var isWaiting: Bool { waiter != nil }

      func wait() async {
          guard waiter == nil else {
              Issue.record("TestGate was entered again while a wait was open")
              return
          }
          guard !Task.isCancelled else { return }
          let id = nextID
          nextID += 1
          await withTaskCancellationHandler {
              await withCheckedContinuation { waiter = (id, $0) }
          } onCancel: {
              Task { @MainActor in self.release(id: id) }
          }
      }

      func open() {
          release(id: nil)
      }

      /// Ends the open wait: any one when `id` is nil, otherwise only the one it names.
      private func release(id: Int?) {
          guard let waiter, id == nil || waiter.id == id else { return }
          self.waiter = nil
          waiter.continuation.resume()
      }
  }

  /// Whether a task the test started has returned, read without waiting for it. A test gates on
  /// `hasReturned` with `eventually`, so a regression that would hold the task for ever fails the test
  /// in two seconds; awaiting the task itself would hang the run, since a suite's time limit cancels
  /// the test's task and not one it started.
  final class TaskWatch {
      private(set) var hasReturned = false

      init<Success: Sendable>(_ task: Task<Success, Never>) {
          Task { [weak self] in
              _ = await task.value
              self?.hasReturned = true
          }
      }
  }
  ```
- [ ] Create `TidyShotTests/Support/CoordinatorWorld.swift`:
  ```swift
  import AppKit
  import Foundation
  import Testing
  @testable import TidyShot

  nonisolated enum CoordinatorWorldError: Error {
      case noDefaults
      case noFile
  }

  /// A coordinator's world in the suite (harness design 2.4): temp folders, a `UserDefaults` suite named
  /// after the test, settings and a save location over it, credentials in memory, the fakes, a clock the
  /// test moves, a date it sets, free space it sets, a log it reads and a destination factory. Build it in
  /// the suite's `init`, make the coordinator with `makeCoordinator()`, and `defer { world.removeAll() }`
  /// first thing in each test. Nothing here reaches the system, except the `ProcessInfo` activity
  /// (`Uploading a recording`) the coordinator begins while `fileUploadIDs` is not empty: the design
  /// leaves `ProcessInfo` activities out of the environment (2.1, Deferred), and it ends when the set empties.
  final class CoordinatorWorld {
      static let config = S3DestinationConfig(endpoint: "https://s3.us-west-2.amazonaws.com", region: "us-west-2",
                                               bucket: "snap.tky.io", publicURLTemplate: "https://snap.tky.io/{key}")
      static let awsCredentials = AWSCredentials(accessKeyID: "AKIDEXAMPLE",
                                                 secretAccessKey: "wJalrXUtnFEMI/K7MDENG+bPxRfiCYEXAMPLEKEY")

      /// `<tmp>/CoordinatorWorld-<uuid>/`.
      let root: URL
      /// `<root>/Support/history.json`; `thumbnails/`, `pending/` and `multipart/` beside it.
      let historyFileURL: URL
      /// `<root>/tmp/`, the coordinator's `Drag/` and partial downloads.
      let temporaryDirectory: URL
      let suiteName: String
      let defaults: UserDefaults
      let settings: AppSettings
      let saveLocation: SaveLocation
      /// `awsCredentials` under the default account.
      let credentials: InMemoryCredentialStore
      /// The coordinator's store: `credentials`, unless a test sets another before `makeCoordinator()`.
      var credentialStore: any CredentialStore
      let notifier = FakeNotifier()
      let cards = FakeCards()
      let clipboard = FakeClipboard()
      let confirm = FakeConfirm()
      /// The coordinator's clock, and its self-timer's.
      let clock = FakeScrollClock()
      let factory = FakeDestinationFactory()
      let state = CoordinatorWorldState()
      /// The lanes' plan; a test sets another before `makeCoordinator()`.
      var multipartPlan = MultipartPlan.standard
      private(set) var shutterCount = 0
      /// The recorder's world, driver and chrome.
      let recording: RecordingTestWorld
      let driver: FakeRecordingDriver
      let chrome: FakeRecordingChrome
      let microphones = FakeMicrophoneDevices()
      /// The coordinator's cameras; a test sets others before `makeCoordinator()`.
      var cameras: any CameraDevices = FakeCameraDevices()

      init() throws {
          let name = Test.current?.name ?? "CoordinatorWorld"
          let root = FileManager.default.temporaryDirectory
              .appending(path: "CoordinatorWorld-\(UUID().uuidString)", directoryHint: .isDirectory)
          let historyFileURL = root.appending(path: "Support", directoryHint: .isDirectory)
              .appending(path: HistoryStore.fileName)
          let temporaryDirectory = root.appending(path: "tmp", directoryHint: .isDirectory)
          try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
          try FileManager.default.createDirectory(at: historyFileURL.deletingLastPathComponent(),
                                                  withIntermediateDirectories: true)
          self.root = root
          self.historyFileURL = historyFileURL
          self.temporaryDirectory = temporaryDirectory
          let suiteName = "io.tky.tidyshot.tests.CoordinatorWorld-\(name)-\(UUID().uuidString)"
          guard let defaults = UserDefaults(suiteName: suiteName) else { throw CoordinatorWorldError.noDefaults }
          defaults.removePersistentDomain(forName: suiteName)
          self.suiteName = suiteName
          self.defaults = defaults
          settings = AppSettings(defaults: defaults)
          saveLocation = SaveLocation(defaults: defaults)
          let credentials = InMemoryCredentialStore()
          try credentials.save(Self.awsCredentials, account: KeychainCredentialStore.defaultAccount)
          self.credentials = credentials
          credentialStore = credentials
          let recording = RecordingTestWorld()
          self.recording = recording
          driver = FakeRecordingDriver(log: recording.log)
          chrome = FakeRecordingChrome(log: recording.log)
          settings.s3Config = Self.config
      }

      /// Where the world's Upload settings write.
      var location: ObjectLocation { ObjectLocation(config: Self.config) }

      var date: Date {
          get { state.date }
          set { state.date = newValue }
      }

      var freeBytes: Int64? {
          get { state.freeBytes }
          set { state.freeBytes = newValue }
      }

      var freeBytesAsked: [URL] { state.freeBytesAsked }
      var logLines: [String] { state.lines }

      var environment: AppEnvironment {
          let factory = factory
          let state = state
          let confirm = confirm
          return AppEnvironment(
              historyFileURL: historyFileURL,
              temporaryDirectory: temporaryDirectory,
              settings: settings,
              saveLocation: saveLocation,
              credentialStore: credentialStore,
              notifier: notifier,
              overlay: cards,
              clipboard: clipboard,
              makeDestination: { config, credentials in factory.make(config, credentials) },
              multipartPlan: multipartPlan,
              uploadSleep: { _ in },
              freeBytes: { url in state.freeBytes(at: url) },
              confirm: { question in await confirm.confirm(question) },
              playShutter: { [weak self] in self?.shutterCount += 1 },
              now: { state.date },
              clock: clock,
              log: { line in state.append(line) })
      }

      /// A coordinator over this world, with the recorder, the self-timer, the microphones and the
      /// cameras set before anything builds the live ones.
      func makeCoordinator() -> AppCoordinator {
          let coordinator = AppCoordinator(environment: environment)
          let driver = driver
          coordinator.recorder = RecordingController(environment: recording.environment, makeDriver: { driver })
          coordinator.microphones = microphones
          coordinator.cameras = cameras
          coordinator.selfTimer = SelfTimerController(clock: clock)
          return coordinator
      }

      func removeAll() {
          try? FileManager.default.removeItem(at: root)
          defaults.removePersistentDomain(forName: suiteName)
      }

      /// A sparse file of `byteCount` bytes at `url`, its folder made.
      static func writeSparseFile(at url: URL, byteCount: Int64) throws {
          try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
          guard FileManager.default.createFile(atPath: url.path(percentEncoded: false), contents: nil) else {
              throw CoordinatorWorldError.noFile
          }
          let handle = try FileHandle(forWritingTo: url)
          try handle.truncate(atOffset: UInt64(byteCount))
          try handle.close()
      }

      /// A red image of `width` by `height` pixels.
      static func image(width: Int, height: Int) throws -> CGImage {
          let context = try #require(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                               space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                               bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
          context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
          context.fill(CGRect(x: 0, y: 0, width: width, height: height))
          return try #require(context.makeImage())
      }

      /// That image as a PNG.
      static func pngData(width: Int, height: Int) throws -> Data {
          try ImageEncoder.pngData(from: image(width: width, height: height), scale: 1)
      }
  }
  ```
- [ ] Create `TidyShotTests/CoordinatorWorldTests.swift`:
  ```swift
  import Foundation
  import Testing
  @testable import TidyShot

  /// The harness itself (harness design 2.4): a coordinator over a world of temp folders and fakes starts
  /// empty, keeps its files in the world's folders, and reaches the world's settings and destination.
  struct CoordinatorWorldTests {
      let world: CoordinatorWorld

      init() throws {
          world = try CoordinatorWorld()
      }

      @Test func aCoordinatorOverTheWorldKeepsToTheWorld() throws {
          defer { world.removeAll() }
          let coordinator = world.makeCoordinator()

          #expect(coordinator.history.records.isEmpty)
          #expect(coordinator.history.fileURL == world.historyFileURL)
          #expect(coordinator.pendingFiles.directory.deletingLastPathComponent().path(percentEncoded: false)
                  == world.historyFileURL.deletingLastPathComponent().path(percentEncoded: false))
          #expect(coordinator.dragFiles.directory.deletingLastPathComponent().path(percentEncoded: false)
                  == world.temporaryDirectory.path(percentEncoded: false))
          #expect(coordinator.settings === world.settings)
          #expect(coordinator.recordingPhase == .idle)
          #expect(world.cards.onDidClose != nil)
          let target = try #require(coordinator.makeDestination())
          #expect(target.location == world.location)
          #expect(world.factory.askedLocations == [world.location])
          #expect(world.notifier.calls.isEmpty)
          #expect(world.logLines.isEmpty)
      }
  }
  ```
- [ ] Run `CoordinatorWorldTests` alone, then the full suite: baseline plus 1 test in 1 suite (`2091 tests in 175 suites`).
- [ ] Commit: `test: coordinator harness support`.

### Task 5: `CoordinatorDragOutTests` [integration]

**Files:** create `TidyShotTests/CoordinatorDragOutTests.swift`.

**Consumes:** Task 4. No source change.

**Steps:**
- [ ] Create the suite. Every test's doc comment names the design section and the R4 checklist line it replaces.
  ```swift
  import Foundation
  import Testing
  @testable import TidyShot

  /// The drag-out download on a built coordinator (R4 design, Drag-out download; harness design 3.1): which
  /// record starts one, the card's ring, the three ways it ends, and the resume data a failure keeps.
  /// The transfer is `FakeDestination`'s scripted download.
  @Suite(.timeLimit(.minutes(1)))
  struct CoordinatorDragOutTests {
      let world: CoordinatorWorld
      let key = "s/2026/rec.mp4"

      init() throws {
          world = try CoordinatorWorld()
      }

      var destination: FakeDestination { world.factory.standard }

      /// An uploaded recording with no local file at the world's location, its card showing.
      func showingUploadedRecording(in coordinator: AppCoordinator) -> CaptureRecord {
          let record = CaptureRecord(fileURL: nil, pixelWidth: 1600, pixelHeight: 1000, appName: nil,
                                     uploadState: .uploaded(url: URL(string: "https://snap.tky.io/\(key)")!, key: key),
                                     objectLocation: world.location, mediaKind: .video, durationSeconds: 10,
                                     byteCount: 1_000)
          coordinator.history.add(record)
          world.cards.showing.insert(record.id)
          return record
      }

      /// Resume data naming `name` as URLSession's partial file in the world's temporary folder.
      func resumeData(partial name: String) throws -> Data {
          try PropertyListSerialization.data(fromPropertyList: ["NSURLSessionResumeInfoTempFileName": name],
                                             format: .binary, options: 0)
      }

      func failure(resumeData: Data) -> URLError {
          URLError(.networkConnectionLost, userInfo: [NSURLSessionDownloadTaskResumeData: resumeData])
      }

      /// Starts a download for `record` and returns its task.
      func startDownload(_ coordinator: AppCoordinator, _ record: CaptureRecord) throws -> Task<URL?, Never> {
          coordinator.downloadDragFile(recordID: record.id)
          return try #require(coordinator.downloadingDragIDs[record.id])
      }

      var downloadsFolder: URL {
          world.temporaryDirectory.appending(path: "Drag/.downloads", directoryHint: .isDirectory)
      }

      /// 1 (harness design 3.1). R4 checklist, Drag-out: a drag shows `Downloading…` with a ring.
      @Test func aDragOfAShowingUploadedRecordingStartsOneDownload() async throws {
          defer { world.removeAll() }
          let coordinator = world.makeCoordinator()
          let record = showingUploadedRecording(in: coordinator)
          destination.state.withLock { $0.holdsDownloads = true }

          let task = try startDownload(coordinator, record)
          try await eventually { destination.state.withLock { $0.downloads.count } == 1 }

          #expect(destination.state.withLock { $0.downloads.map(\.key) } == [key])
          #expect(destination.state.withLock { $0.downloads.map(\.resumeData) } == [nil])
          #expect(coordinator.downloadingVideoIDs == [record.id])
          #expect(world.cards.downloads(for: record.id) == [.running(0)])
          destination.releaseDownloads()
          _ = await task.value
      }

      /// 2 (harness design 3.1). `DragDownloadRule.starts` has its own tests; this pins the coordinator's `isShowing` read.
      @Test func aDragWithNoCardShowingStartsNothing() throws {
          defer { world.removeAll() }
          let coordinator = world.makeCoordinator()
          let record = showingUploadedRecording(in: coordinator)
          world.cards.showing = []

          coordinator.downloadDragFile(recordID: record.id)

          #expect(coordinator.downloadingDragIDs.isEmpty)
          #expect(coordinator.downloadingVideoIDs.isEmpty)
          #expect(world.factory.askedConfigs.isEmpty)
          #expect(world.cards.downloads(for: record.id).isEmpty)
      }

      /// 3 (harness design 3.1). R4 checklist, Drag-out: a disk-check refusal shows `Your disk is almost full.` and logs it.
      @Test func tooLittleFreeSpaceRefusesTheDownload() throws {
          defer { world.removeAll() }
          let coordinator = world.makeCoordinator()
          let record = showingUploadedRecording(in: coordinator)
          // One byte under the record's 1,000 bytes plus the 1 GB a recording keeps free.
          world.freeBytes = 1_000_000_999

          coordinator.downloadDragFile(recordID: record.id)

          #expect(world.cards.downloads(for: record.id) == [.failed(RecordingLimits.diskFullText)])
          #expect(world.logLines == ["Drag-out download for \(record.id) refused, not enough disk space"])
          #expect(world.freeBytesAsked == [coordinator.dragFiles.directory])
          #expect(world.factory.askedConfigs.isEmpty)
          #expect(coordinator.downloadingDragIDs.isEmpty)
      }

      /// 4 (harness design 3.1). No credentials: the card says why, and the log has the failure.
      @Test func noStoredCredentialsFailsTheDownload() throws {
          defer { world.removeAll() }
          try world.credentials.delete(account: KeychainCredentialStore.defaultAccount)
          let coordinator = world.makeCoordinator()
          let record = showingUploadedRecording(in: coordinator)

          coordinator.downloadDragFile(recordID: record.id)

          let text = UploadError.notConfigured.localizedDescription
          #expect(world.cards.downloads(for: record.id) == [.failed(text)])
          #expect(world.logLines == ["Drag-out download for \(record.id) failed: \(text)"])
          #expect(coordinator.downloadingDragIDs.isEmpty)
          #expect(world.notifier.calls.isEmpty)
      }

      /// 5 (harness design 3.1). R4 checklist, Drag-out: the file lands under the key's name in `tmp/Drag/<id>/`.
      @Test func aDownloadThatLandsIsAdoptedAndHandedToTheCard() async throws {
          defer { world.removeAll() }
          let coordinator = world.makeCoordinator()
          let record = showingUploadedRecording(in: coordinator)
          destination.state.withLock {
              $0.downloadFractions = [0.25, 0.5, 1]
              $0.downloadOutcome = .lands(bytes: 1_000)
          }

          let task = try startDownload(coordinator, record)
          let url = try #require(await task.value)

          let expected = coordinator.dragFiles.folder(for: record.id).appending(path: "rec.mp4")
          #expect(url.path(percentEncoded: false) == expected.path(percentEncoded: false))
          #expect(try Data(contentsOf: url).count == 1_000)
          let shown = world.cards.downloads(for: record.id)
          #expect(shown.first == .running(0))
          #expect(shown.contains(.running(0.25)))
          #expect(shown.contains(.running(0.5)))
          #expect(shown.last == .cleared)
          #expect(world.cards.dragFiles(for: record.id) == [url])
          // The ring clears before the card gets the file.
          let ends = world.cards.calls.filter { $0 == .downloading(record.id, nil) || $0 == .dragFile(record.id, url) }
          #expect(ends == [.downloading(record.id, nil), .dragFile(record.id, url)])
          #expect(coordinator.downloadingDragIDs.isEmpty)
          #expect(coordinator.downloadingVideoIDs.isEmpty)
      }

      /// 6 (harness design 3.1). R4 checklist, Drag-out: Close during the download cancels it, `… cancelled` in the log, and
      /// `tmp/Drag/<id>` and `.downloads/` hold nothing. The file lands as the cancel arrives.
      @Test func aCloseDuringTheTransferDropsWhatLands() async throws {
          defer { world.removeAll() }
          let coordinator = world.makeCoordinator()
          let record = showingUploadedRecording(in: coordinator)
          destination.state.withLock {
              $0.holdsDownloads = true
              $0.downloadOutcome = .lands(bytes: 1_000)
          }
          let task = try startDownload(coordinator, record)
          try await eventually { destination.state.withLock { $0.downloads.count } == 1 }

          coordinator.overlayDidClose(record.id, reason: .user)
          try await eventually { destination.state.withLock { $0.downloadCancellations } == 1 }
          destination.releaseDownloads()

          #expect(await task.value == nil)
          #expect(world.cards.downloads(for: record.id).last == .cleared)
          #expect(world.logLines.contains("Drag-out download for \(record.id) cancelled"))
          #expect(world.cards.dragFiles(for: record.id).isEmpty)
          #expect(coordinator.dragFiles.stagedFile(id: record.id) == nil)
          #expect(try FileManager.default.contentsOfDirectory(atPath: downloadsFolder.path(percentEncoded: false)).isEmpty)
      }

      /// 7 (harness design 3.1). The drag folder's removal (Delete, the clean-up) during the transfer bumps the generation and
      /// cancels: the same outcome as a close.
      @Test func aRemovedDragFolderDropsWhatLands() async throws {
          defer { world.removeAll() }
          let coordinator = world.makeCoordinator()
          let record = showingUploadedRecording(in: coordinator)
          destination.state.withLock {
              $0.holdsDownloads = true
              $0.downloadOutcome = .lands(bytes: 1_000)
          }
          let task = try startDownload(coordinator, record)
          try await eventually { destination.state.withLock { $0.downloads.count } == 1 }

          coordinator.removeDragFolder(record.id)
          try await eventually { destination.state.withLock { $0.downloadCancellations } == 1 }
          destination.releaseDownloads()

          #expect(await task.value == nil)
          #expect(world.cards.downloads(for: record.id).last == .cleared)
          #expect(world.logLines.contains("Drag-out download for \(record.id) cancelled"))
          #expect(world.cards.dragFiles(for: record.id).isEmpty)
          #expect(coordinator.dragFiles.stagedFile(id: record.id) == nil)
          // The landed file is in `Drag/.downloads/`, which `removeDragFolder` does not touch.
          #expect(try FileManager.default.contentsOfDirectory(atPath: downloadsFolder.path(percentEncoded: false)).isEmpty)
      }

      /// 8 (harness design 3.1). R4 checklist, Drag-out: Wi-Fi off shows `Download failed` with the error and posts nothing;
      /// the resume data is kept with the time the request was signed (plan Gap 16 of R4).
      @Test func aFailureWithResumeDataKeepsItWithTheSigningTime() async throws {
          defer { world.removeAll() }
          let coordinator = world.makeCoordinator()
          let record = showingUploadedRecording(in: coordinator)
          let data = try resumeData(partial: "CFNetworkDownload_A.tmp")
          let error = failure(resumeData: data)
          destination.state.withLock { $0.downloadOutcome = .fails(error) }
          let signedAt = world.date

          let task = try startDownload(coordinator, record)

          #expect(await task.value == nil)
          #expect(world.cards.downloads(for: record.id).last == .failed(error.localizedDescription))
          #expect(world.logLines.contains("Drag-out download for \(record.id) failed: \(error.localizedDescription)"))
          let kept = try #require(coordinator.dragDownloadResume[record.id])
          #expect(kept.data == data)
          #expect(kept.signedAt == signedAt)
          #expect(world.notifier.calls.isEmpty)
      }

      /// 9 (harness design 3.1). A failure that is not a transport error (a 403) keeps nothing.
      @Test func aFailureWithoutResumeDataKeepsNothing() async throws {
          defer { world.removeAll() }
          let coordinator = world.makeCoordinator()
          let record = showingUploadedRecording(in: coordinator)
          destination.state.withLock { $0.downloadOutcome = .fails(UploadError.httpStatus(403, body: "")) }

          let task = try startDownload(coordinator, record)

          #expect(await task.value == nil)
          #expect(world.cards.downloads(for: record.id).last == .failed("Server returned HTTP 403."))
          #expect(coordinator.dragDownloadResume[record.id] == nil)
      }

      /// 10 (harness design 3.1). A transfer that fails after a cancel is a cancel: nothing failed, nothing kept.
      @Test func aFailureAfterACancelKeepsNothing() async throws {
          defer { world.removeAll() }
          let coordinator = world.makeCoordinator()
          let record = showingUploadedRecording(in: coordinator)
          let error = failure(resumeData: try resumeData(partial: "CFNetworkDownload_B.tmp"))
          destination.state.withLock {
              $0.holdsDownloads = true
              $0.downloadOutcome = .fails(error)
          }
          let task = try startDownload(coordinator, record)
          try await eventually { destination.state.withLock { $0.downloads.count } == 1 }

          coordinator.overlayDidClose(record.id, reason: .user)
          try await eventually { destination.state.withLock { $0.downloadCancellations } == 1 }
          destination.releaseDownloads()

          #expect(await task.value == nil)
          #expect(world.cards.downloads(for: record.id).last == .cleared)
          #expect(world.logLines.contains("Drag-out download for \(record.id) cancelled"))
          #expect(!world.logLines.contains { $0.contains("failed") })
          #expect(coordinator.dragDownloadResume[record.id] == nil)
      }

      /// 11 (harness design 3.1). R4 checklist, Drag-out: a drag soon after resumes, and the log shows `resumed at <fraction>`
      /// once; a resume keeps the first request's signing time.
      @Test func aDragWithinTheWindowResumesFromTheKeptData() async throws {
          defer { world.removeAll() }
          let coordinator = world.makeCoordinator()
          let record = showingUploadedRecording(in: coordinator)
          let first = try resumeData(partial: "CFNetworkDownload_C.tmp")
          // The first download reports no fraction, so every `.running` after 0 is the resumed one's.
          destination.state.withLock {
              $0.downloadFractions = []
              $0.downloadOutcome = .fails(failure(resumeData: first))
          }
          let signedAt = world.date
          _ = try await startDownload(coordinator, record).value

          world.date = signedAt.addingTimeInterval(839)
          let second = try resumeData(partial: "CFNetworkDownload_D.tmp")
          let secondError = failure(resumeData: second)
          destination.state.withLock {
              $0.downloadFractions = [0.25, 0.5]
              $0.downloadOutcome = .fails(secondError)
          }
          _ = try await startDownload(coordinator, record).value

          #expect(destination.state.withLock { $0.downloads.map(\.resumeData) } == [nil, first])
          #expect(world.logLines.filter { $0.contains("resumed at") }
                  == ["Drag-out download for \(record.id) resumed at 0.2500"])
          let shown = world.cards.downloads(for: record.id)
          #expect(shown == [.running(0), .failed(failure(resumeData: first).localizedDescription),
                            .running(0), .running(0.25), .running(0.5), .failed(secondError.localizedDescription)])
          #expect(coordinator.dragDownloadResume[record.id]?.data == second)
          #expect(coordinator.dragDownloadResume[record.id]?.signedAt == signedAt)
      }

      /// 12 (harness design 3.1). R4 checklist, Drag-out: 14 minutes or more after signing, a drag starts again from 0 with no
      /// `resumed at` line, signs afresh, and the unused resume data's partial file goes.
      @Test func aDragPastTheWindowStartsAgainAndRemovesThePartialFile() async throws {
          defer { world.removeAll() }
          let coordinator = world.makeCoordinator()
          let record = showingUploadedRecording(in: coordinator)
          let partialName = "CFNetworkDownload_E.tmp"
          let partial = world.temporaryDirectory.appending(path: partialName)
          try Data("partial".utf8).write(to: partial)
          let first = try resumeData(partial: partialName)
          destination.state.withLock { $0.downloadOutcome = .fails(failure(resumeData: first)) }
          let signedAt = world.date
          _ = try await startDownload(coordinator, record).value

          world.date = signedAt.addingTimeInterval(840)
          let secondError = failure(resumeData: try resumeData(partial: "CFNetworkDownload_F.tmp"))
          destination.state.withLock { $0.downloadOutcome = .fails(secondError) }
          _ = try await startDownload(coordinator, record).value

          #expect(destination.state.withLock { $0.downloads.map(\.resumeData) } == [nil, nil])
          #expect(!world.logLines.contains { $0.contains("resumed at") })
          #expect(coordinator.dragDownloadResume[record.id]?.signedAt == signedAt.addingTimeInterval(840))
          try await eventually { !FileManager.default.fileExists(atPath: partial.path(percentEncoded: false)) }
      }

      /// 13 (harness design 3.1). A cancel with resume data kept drops it and its partial file, and clears the card.
      @Test func cancellingWithKeptResumeDataRemovesThePartialFile() async throws {
          defer { world.removeAll() }
          let coordinator = world.makeCoordinator()
          let record = showingUploadedRecording(in: coordinator)
          let partialName = "CFNetworkDownload_G.tmp"
          let partial = world.temporaryDirectory.appending(path: partialName)
          try Data("partial".utf8).write(to: partial)
          let error = failure(resumeData: try resumeData(partial: partialName))
          destination.state.withLock { $0.downloadOutcome = .fails(error) }
          _ = try await startDownload(coordinator, record).value

          coordinator.cancelDragDownload(record.id)

          #expect(coordinator.dragDownloadResume[record.id] == nil)
          #expect(world.cards.downloads(for: record.id).last == .cleared)
          try await eventually { !FileManager.default.fileExists(atPath: partial.path(percentEncoded: false)) }
      }

      /// 14 (harness design 3.1). A fraction that arrives after the end does not put the ring back. A
      /// second record's running download is the control: its fraction, sent after the late one, shows,
      /// so the late one's main-actor hop has run by then.
      @Test func aFractionAfterTheEndDoesNotPutTheRingBack() async throws {
          defer { world.removeAll() }
          let coordinator = world.makeCoordinator()
          let record = showingUploadedRecording(in: coordinator)
          _ = try await startDownload(coordinator, record).value
          let ended = try #require(destination.state.withLock { $0.downloadProgress })
          let other = showingUploadedRecording(in: coordinator)
          destination.state.withLock { $0.holdsDownloads = true }
          let otherTask = try startDownload(coordinator, other)
          try await eventually { destination.state.withLock { $0.downloads.count } == 2 }

          ended(0.9)
          destination.reportLateFraction(0.9)
          try await eventually { world.cards.downloads(for: other.id).contains(.running(0.9)) }

          #expect(world.cards.downloads(for: record.id).last == .cleared)
          #expect(!world.cards.downloads(for: record.id).contains(.running(0.9)))
          destination.releaseDownloads()
          _ = await otherTask.value
      }

      /// 15 (harness design 3.1). R4 checklist, Drag-out: Delete during the download cancels it and removes the folder.
      @Test func deleteCancelsARunningDownloadAndRemovesTheFolder() async throws {
          defer { world.removeAll() }
          world.settings.confirmBeforeDeleting = false
          let coordinator = world.makeCoordinator()
          let record = showingUploadedRecording(in: coordinator)
          destination.state.withLock {
              $0.holdsDownloads = true
              $0.downloadOutcome = .lands(bytes: 1_000)
          }
          let task = try startDownload(coordinator, record)
          try await eventually { destination.state.withLock { $0.downloads.count } == 1 }
          // A stale copy in the record's drag folder, so the folder's removal can be seen (the download
          // only makes `Drag/<id>/` when it is adopted).
          let folder = coordinator.dragFiles.folder(for: record.id)
          try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
          try Data("stale".utf8).write(to: folder.appending(path: "rec.mp4"))

          await coordinator.deleteCapture(recordID: record.id)
          try await eventually { destination.state.withLock { $0.downloadCancellations } >= 1 }
          destination.releaseDownloads()

          #expect(await task.value == nil)
          #expect(world.confirm.asked.isEmpty)
          #expect(coordinator.history.record(id: record.id) == nil)
          #expect(destination.state.withLock { $0.deletedKeys } == [key])
          #expect(!FileManager.default.fileExists(atPath: folder.path(percentEncoded: false)))
          #expect(try FileManager.default.contentsOfDirectory(atPath: downloadsFolder.path(percentEncoded: false)).isEmpty)
      }

      /// 16 (harness design 3.1). A second drag while one runs starts no second GET.
      @Test func aSecondDragWhileOneRunsStartsNoSecondDownload() async throws {
          defer { world.removeAll() }
          let coordinator = world.makeCoordinator()
          let record = showingUploadedRecording(in: coordinator)
          destination.state.withLock { $0.holdsDownloads = true }
          let task = try startDownload(coordinator, record)
          try await eventually { destination.state.withLock { $0.downloads.count } == 1 }

          coordinator.downloadDragFile(recordID: record.id)
          for _ in 0..<20 { await Task.yield() }

          #expect(destination.state.withLock { $0.downloads.count } == 1)
          #expect(coordinator.downloadingDragIDs[record.id] == task)
          destination.releaseDownloads()
          _ = await task.value
      }
  }
  ```
- [ ] Run `CoordinatorDragOutTests` alone, then the full suite: `2107 tests in 176 suites`.
- [ ] Commit: `test: coordinator drag-out download`.

### Task 6: `CoordinatorUploadTests` [integration]

**Files:** create `TidyShotTests/CoordinatorUploadTests.swift`.

**Consumes:** Tasks 2 and 4 (`makeLane` reads the world's `multipartPlan`, `uploadSleep` and `log`).

**Steps:**
- [ ] Create the suite:
  ```swift
  import Foundation
  import Testing
  @testable import TidyShot

  /// Uploads on a built coordinator, through the real `UploadQueue` over `FakeDestination` (R4 design,
  /// Multipart and Resume; R1's clipboard rule; Phase 3's cancel and draining; harness design 3.2). The
  /// lanes use a 1 MiB threshold and 256 KiB parts, as `UploadQueueTests` does, and never sleep.
  @Suite(.timeLimit(.minutes(1)))
  struct CoordinatorUploadTests {
      let world: CoordinatorWorld
      let mib: Int64 = 1_048_576

      init() throws {
          world = try CoordinatorWorld()
          world.multipartPlan = MultipartPlan(threshold: 1_048_576, partSize: 262_144, inFlight: 3)
      }

      var destination: FakeDestination { world.factory.standard }

      /// `pending/<id>.mp4`, sparse, of `byteCount` bytes.
      func pendingFile(in coordinator: AppCoordinator, id: UUID, byteCount: Int64) throws -> URL {
          let url = coordinator.pendingFiles.directory.appending(path: "\(id.uuidString).mp4")
          try CoordinatorWorld.writeSparseFile(at: url, byteCount: byteCount)
          return url
      }

      /// A recording whose file is `file` in `pending/`, added to history: failed, so a Retry starts it.
      @discardableResult
      func addRecording(to coordinator: AppCoordinator, id: UUID, file: URL, byteCount: Int64,
                        state: CaptureRecord.UploadState = .failed(message: "Upload was interrupted."),
                        multipart: MultipartUploadState? = nil, unmutedIntervals: [MuteInterval] = []) -> CaptureRecord {
          let record = CaptureRecord(id: id, fileURL: file, fileIsTemporary: true, pixelWidth: 1600, pixelHeight: 1000,
                                     appName: nil, uploadState: state, mediaKind: .video, durationSeconds: 10,
                                     byteCount: Int(byteCount), unmutedIntervals: unmutedIntervals, multipart: multipart)
          coordinator.history.add(record)
          return record
      }

      /// An upload-only screenshot in `pending/`, added to history.
      func addPendingImage(to coordinator: AppCoordinator,
                           state: CaptureRecord.UploadState = .failed(message: "Upload was interrupted."),
                           priorUpload: PriorUpload? = nil, uploadIsStale: Bool = false) throws -> CaptureRecord {
          let id = UUID()
          let png = try CoordinatorWorld.pngData(width: 4, height: 2)
          let url = try coordinator.pendingFiles.write(png, id: id, ext: "png")
          let record = CaptureRecord(id: id, fileURL: url, fileIsTemporary: true, pixelWidth: 4, pixelHeight: 2,
                                     appName: nil, uploadState: state, uploadIsStale: uploadIsStale,
                                     priorUpload: priorUpload, byteCount: png.count)
          coordinator.history.add(record)
          return record
      }

      /// A stored upload `stored-1` of `file` at `key`: the file's own size and modification date unless
      /// `byteCount` says otherwise, at the world's location unless `location` does.
      func storedState(of file: URL, key: String = "s/STORED.mp4", byteCount: Int64? = nil,
                       location: ObjectLocation? = nil,
                       startedAt: Date = Date(timeIntervalSinceNow: -60)) throws -> MultipartUploadState {
          let values = try file.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
          let size = try #require(values.fileSize)
          let modified = try #require(values.contentModificationDate)
          return MultipartUploadState(uploadID: "stored-1", key: key, location: location ?? world.location,
                                      partSize: 262_144, byteCount: byteCount ?? Int64(size),
                                      sourceModified: modified, sourcePath: file.path(percentEncoded: false),
                                      startedAt: startedAt)
      }

      func part(_ number: Int) -> MultipartPart {
          MultipartPart(number: number, etag: "\"etag-\(number)\"", size: 262_144)
      }

      /// Parts 1 and 2 of `stored-1` in the sidecar, as an interrupted upload leaves them.
      func writeSidecar(_ coordinator: AppCoordinator, id: UUID) throws {
          try coordinator.multipartFiles.writeSidecar(MultipartSidecar(uploadID: "stored-1", completeSent: false,
                                                                       parts: [part(1), part(2)]), id: id)
      }

      func isUploaded(_ coordinator: AppCoordinator, _ id: UUID) -> Bool {
          if case .uploaded = coordinator.history.record(id: id)?.uploadState { return true }
          return false
      }

      func exists(_ url: URL) -> Bool {
          FileManager.default.fileExists(atPath: url.path(percentEncoded: false))
      }

      /// 17 (harness design 3.2). R4 checklist, Multipart: Retry resumes, from the sidecar's parts, with no Create, no
      /// ListParts and no counter drawn; the record stores the stored size.
      @Test func aStoredUploadWhoseSourceMatchesResumes() async throws {
          defer { world.removeAll() }
          var config = CoordinatorWorld.config
          config.keyTemplate = "s/{counter}-{random:6}"
          world.settings.s3Config = config
          let coordinator = world.makeCoordinator()
          let id = UUID()
          let file = try pendingFile(in: coordinator, id: id, byteCount: mib)
          try writeSidecar(coordinator, id: id)
          // The record starts at 1 byte, so the size it ends with is the one `.uploaded` stored.
          addRecording(to: coordinator, id: id, file: file, byteCount: 1, multipart: try storedState(of: file))
          let counter = world.settings.currentCounter

          coordinator.retryUpload(recordID: id)
          try await eventually { isUploaded(coordinator, id) }

          let calls = destination.state.withLock { $0.calls }
          #expect(!calls.contains("create"))
          #expect(!calls.contains("list"))
          #expect(Set(calls.filter { $0.hasPrefix("part") }) == ["part 3", "part 4"])
          #expect(calls.last == "complete")
          #expect(coordinator.history.record(id: id)?.uploadedKey == "s/STORED.mp4")
          #expect(coordinator.history.record(id: id)?.byteCount == Int(mib))
          #expect(world.settings.currentCounter == counter)
      }

      /// 18 (harness design 3.2). R4 design, Resume: the bar is at the done fraction at once (R4 checklist, Multipart, the
      /// bar at that fraction at once). Part 3 waits, so nothing else moves the bar meanwhile.
      @Test func aResumesStartSetsTheBarAtItsDoneFraction() async throws {
          defer { world.removeAll() }
          world.multipartPlan = MultipartPlan(threshold: 1_048_576, partSize: 262_144, inFlight: 1)
          destination.state.withLock { $0.holdingPart = 3 }
          let coordinator = world.makeCoordinator()
          let id = UUID()
          let file = try pendingFile(in: coordinator, id: id, byteCount: mib)
          try writeSidecar(coordinator, id: id)
          addRecording(to: coordinator, id: id, file: file, byteCount: mib, multipart: try storedState(of: file))

          coordinator.retryUpload(recordID: id)
          try await eventually { coordinator.history.record(id: id)?.uploadState == .uploading(fraction: 0.5) }

          #expect(world.cards.updates(for: id).contains(.uploading(fraction: 0.5)))
          destination.releaseParts()
          try await eventually { isUploaded(coordinator, id) }
      }

      /// 19 (harness design 3.2). A retried attempt (`.started(attempt: 2)`, a single PUT's retry) is logged.
      @Test func aRetriedAttemptIsLogged() async throws {
          defer { world.removeAll() }
          destination.state.withLock {
              $0.failuresRemaining = 1
              $0.failure = .httpStatus(503, body: "")
          }
          let coordinator = world.makeCoordinator()
          let record = try addPendingImage(to: coordinator)

          coordinator.retryUpload(recordID: record.id)
          try await eventually { isUploaded(coordinator, record.id) }

          #expect(world.logLines.contains("Upload retry 2 for \(record.id)"))
      }

      /// 20 (harness design 3.2). R4 checklist, Multipart: after Settings names another bucket, `destination changed, starting
      /// again`; the old upload is aborted where it was created (twice: a 204 is repeated, test 38), and
      /// the new bucket gets a fresh upload with no abort.
      @Test func aStoredUploadAtAnotherLocationIsAbortedThereAndStartsAgain() async throws {
          defer { world.removeAll() }
          let old = ObjectLocation(endpoint: "https://s3.us-west-2.amazonaws.com", region: "us-west-2",
                                   bucket: "old.tky.io", usePathStyle: true)
          let oldDestination = FakeDestination()
          world.factory.add(oldDestination, at: old)
          let coordinator = world.makeCoordinator()
          let id = UUID()
          let file = try pendingFile(in: coordinator, id: id, byteCount: mib)
          addRecording(to: coordinator, id: id, file: file, byteCount: mib,
                       multipart: try storedState(of: file, location: old))

          coordinator.retryUpload(recordID: id)
          try await eventually { isUploaded(coordinator, id) }
          try await eventually { oldDestination.state.withLock { $0.aborts.count } == 2 }

          #expect(world.logLines.contains("Upload: \(file.lastPathComponent) destination changed, starting again"))
          #expect(world.factory.askedLocations.contains(old))
          #expect(oldDestination.state.withLock { $0.aborts.map(\.uploadID) } == ["stored-1", "stored-1"])
          #expect(!destination.state.withLock { $0.calls }.contains("abort"))
          #expect(destination.state.withLock { $0.calls }.first == "create")
      }

      /// 21 (harness design 3.2). R4 checklist, Multipart: after the file changed, `source changed, starting again`, and the
      /// old upload is aborted first.
      @Test func aSourceWhoseSizeChangedStartsAgainAbortingFirst() async throws {
          defer { world.removeAll() }
          let coordinator = world.makeCoordinator()
          let id = UUID()
          let file = try pendingFile(in: coordinator, id: id, byteCount: mib)
          addRecording(to: coordinator, id: id, file: file, byteCount: mib,
                       multipart: try storedState(of: file, byteCount: 2 * mib))

          coordinator.retryUpload(recordID: id)
          try await eventually { isUploaded(coordinator, id) }

          #expect(world.logLines.contains("Upload: \(file.lastPathComponent) source changed, starting again"))
          #expect(Array(destination.state.withLock { $0.calls }.prefix(2)) == ["abort", "create"])
          #expect(destination.state.withLock { $0.aborts.first?.uploadID } == "stored-1")
      }

      /// 22 (harness design 3.2). A fixed key other than the stored one starts again (`key changed`).
      @Test func aDifferentFixedKeyStartsAgain() async throws {
          defer { world.removeAll() }
          let coordinator = world.makeCoordinator()
          let id = UUID()
          let file = try pendingFile(in: coordinator, id: id, byteCount: mib)
          let record = addRecording(to: coordinator, id: id, file: file, byteCount: mib,
                                    multipart: try storedState(of: file))
          let target = try #require(coordinator.makeDestination())

          coordinator.startUpload(recordID: id, payload: try coordinator.uploadPayload(for: record), destination: target,
                                  fixedKey: "s/OTHER.mp4")
          try await eventually { isUploaded(coordinator, id) }

          #expect(world.logLines.contains("Upload: \(file.lastPathComponent) key changed, starting again"))
          #expect(destination.state.withLock { $0.creates.map(\.key) } == ["s/OTHER.mp4"])
          #expect(Array(destination.state.withLock { $0.calls }.prefix(2)) == ["abort", "create"])
      }

      /// 23 (harness design 3.2). R4 checklist, call B: a kept Clop copy older than the record's file counts as changed.
      @Test func anOutdatedKeptClopCopyCountsAsAChangedSource() async throws {
          defer { world.removeAll() }
          let coordinator = world.makeCoordinator()
          let id = UUID()
          let keptCopy = coordinator.multipartFiles.keptCopyURL(for: id, ext: "mp4")
          try CoordinatorWorld.writeSparseFile(at: keptCopy, byteCount: mib)
          // Written now, after the stored upload started an hour ago: a trim since.
          let file = try pendingFile(in: coordinator, id: id, byteCount: mib)
          addRecording(to: coordinator, id: id, file: file, byteCount: mib,
                       multipart: try storedState(of: keptCopy, startedAt: Date(timeIntervalSinceNow: -3600)))

          coordinator.retryUpload(recordID: id)
          try await eventually { isUploaded(coordinator, id) }

          #expect(world.logLines.contains("Upload: \(file.lastPathComponent) source changed, starting again"))
          #expect(destination.state.withLock { $0.calls }.contains("create"))
      }

      /// 24 (harness design 3.2). R1's clipboard rule: a recording's link replaces the clipboard only while it holds what the
      /// save left there; otherwise the card says `Uploaded`.
      @Test(arguments: [false, true])
      func anUploadedRecordingReplacesTheClipboardOnlyWhileItHoldsWhatTheSaveLeft(clipboardMoved: Bool) async throws {
          defer { world.removeAll() }
          let coordinator = world.makeCoordinator()
          let id = UUID()
          let file = try pendingFile(in: coordinator, id: id, byteCount: 3)
          addRecording(to: coordinator, id: id, file: file, byteCount: 3)
          coordinator.videoClipboardCounts[id] = world.clipboard.changeCount
          if clipboardMoved {
              world.clipboard.changeCount += 1
          }

          coordinator.retryUpload(recordID: id)
          try await eventually { isUploaded(coordinator, id) }

          let url = try #require(coordinator.history.record(id: id)?.uploadedURL)
          if clipboardMoved {
              #expect(world.clipboard.copies.isEmpty)
              #expect(world.notifier.calls.contains(.uploaded(url: url, copied: false)))
              #expect(coordinator.linkNotCopiedIDs.contains(id))
          } else {
              #expect(world.clipboard.copies == [.url(url)])
              #expect(world.notifier.calls.contains(.uploaded(url: url, copied: true)))
              #expect(!coordinator.linkNotCopiedIDs.contains(id))
          }
      }

      /// 25 (harness design 3.2). R4 checklist, Multipart: after `.uploaded`, `multipart/` holds neither the sidecar nor a kept
      /// copy; the record's state is gone and its size is the sent size.
      @Test func anUploadedResumeClearsItsStateSidecarAndKeptCopy() async throws {
          defer { world.removeAll() }
          let coordinator = world.makeCoordinator()
          let id = UUID()
          let file = try pendingFile(in: coordinator, id: id, byteCount: mib)
          let keptCopy = coordinator.multipartFiles.keptCopyURL(for: id, ext: "mp4")
          try CoordinatorWorld.writeSparseFile(at: keptCopy, byteCount: mib)
          try writeSidecar(coordinator, id: id)
          // Started after the record's file was written: the kept copy is current. The record starts at
          // 1 byte, so the size it ends with is the one `.uploaded` stored.
          addRecording(to: coordinator, id: id, file: file, byteCount: 1,
                       multipart: try storedState(of: keptCopy, startedAt: Date(timeIntervalSinceNow: 3600)))

          coordinator.retryUpload(recordID: id)
          try await eventually { isUploaded(coordinator, id) }

          #expect(coordinator.history.record(id: id)?.multipart == nil)
          #expect(coordinator.history.record(id: id)?.byteCount == Int(mib))
          #expect(!destination.state.withLock { $0.calls }.contains("create"))
          try await eventually {
              !exists(coordinator.multipartFiles.sidecarURL(for: id)) && !exists(keptCopy)
          }
      }

      /// 26 (harness design 3.2). Spec 2.9: an upload-only screenshot's pending file moves into its drag folder under the key's
      /// name while its card shows; with no card it is removed. Either way the record has no file.
      @Test(arguments: [true, false])
      func anUploadedUploadOnlyImageMovesToItsDragFolderOnlyWithACard(cardShowing: Bool) async throws {
          defer { world.removeAll() }
          let coordinator = world.makeCoordinator()
          let record = try addPendingImage(to: coordinator)
          let pending = try #require(record.fileURL)
          if cardShowing {
              world.cards.showing.insert(record.id)
          }

          coordinator.retryUpload(recordID: record.id)
          try await eventually { isUploaded(coordinator, record.id) }

          let uploaded = try #require(coordinator.history.record(id: record.id))
          #expect(uploaded.fileURL == nil)
          #expect(!exists(pending))
          let dragged = coordinator.dragFiles.stagedFile(id: record.id)
          if cardShowing {
              let key = try #require(uploaded.uploadedKey)
              #expect(dragged?.lastPathComponent == key.split(separator: "/").last.map(String.init))
              #expect(world.cards.dragFiles(for: record.id).map { $0?.lastPathComponent } == [dragged?.lastPathComponent])
          } else {
              #expect(dragged == nil)
              #expect(world.cards.dragFiles(for: record.id).isEmpty)
          }
      }

      /// 27 (harness design 3.2). A failed upload with no link is marked failed and posts `Upload failed`; one over a link goes
      /// back to the link, keeps `uploadIsStale`, and posts `Not uploaded` with the replace's text.
      @Test func aFailedUploadMarksTheRecordOrReturnsItToItsLink() async throws {
          defer { world.removeAll() }
          destination.state.withLock {
              $0.failuresRemaining = 2
              $0.failure = .httpStatus(403, body: "AccessDenied: Access Denied")
          }
          let coordinator = world.makeCoordinator()
          let message = "Server returned HTTP 403: AccessDenied: Access Denied"

          let plain = try addPendingImage(to: coordinator)
          coordinator.retryUpload(recordID: plain.id)
          try await eventually { coordinator.history.record(id: plain.id)?.uploadState == .failed(message: message) }
          #expect(world.notifier.calls.contains(.error(title: "Upload failed", message: message)))

          let prior = PriorUpload(url: URL(string: "https://snap.tky.io/s/OLD.png")!, key: "s/OLD.png",
                                  location: world.location, isReplace: false)
          let linked = try addPendingImage(to: coordinator, state: .uploading(fraction: 0), priorUpload: prior,
                                           uploadIsStale: true)
          coordinator.startUpload(recordID: linked.id, payload: try coordinator.uploadPayload(for: linked),
                                  destination: try #require(coordinator.makeDestination()))
          try await eventually {
              coordinator.history.record(id: linked.id)?.uploadState == .uploaded(url: prior.url, key: prior.key)
          }
          #expect(coordinator.history.record(id: linked.id)?.uploadIsStale == true)
          #expect(world.notifier.calls.contains(.error(title: "Not uploaded", message: EditorUploadPlan.failedReplaceMessage)))
      }

      /// 28 (harness design 3.2). Phase 3's cancel: during the resume and size wait, the token is taken, the record reads
      /// `Upload cancelled.`, and nothing reaches the queue.
      @Test func cancellingDuringTheWaitEndsTheUploadWithoutTheQueue() async throws {
          defer { world.removeAll() }
          let coordinator = world.makeCoordinator()
          let id = UUID()
          let file = try pendingFile(in: coordinator, id: id, byteCount: 3)
          addRecording(to: coordinator, id: id, file: file, byteCount: 3)

          coordinator.retryUpload(recordID: id)
          #expect(coordinator.optimisingIDs[id] != nil)
          await coordinator.cancelUpload(of: id)

          #expect(coordinator.optimisingIDs[id] == nil)
          #expect(coordinator.history.record(id: id)?.uploadState == .failed(message: "Upload cancelled."))
          #expect(!coordinator.uploadingIDs.contains(id))
          try await eventually { coordinator.clopWaitsPerLane.isEmpty }
          #expect(destination.state.withLock { $0.uploadAttempts } == 0)
          // The lane exists (`startUpload` makes it before the wait) but was never given the job, so the
          // cancel ended before `queue.cancel`; a queue cancel of a job it does not hold changes nothing.
          #expect(await coordinator.queue?.queue.isIdle == true)
          #expect(coordinator.fileUploadIDs.isEmpty)
      }

      /// 29 (harness design 3.2). Phase 3's cancel: a job in flight is cancelled in its lane, and the record keeps the key the
      /// job reserved, so Delete removes it too.
      @Test func cancellingAQueuedJobKeepsItsReservedKey() async throws {
          defer { world.removeAll() }
          destination.state.withLock { $0.blockingUploadsRemaining = 1 }
          let coordinator = world.makeCoordinator()
          let id = UUID()
          let file = try pendingFile(in: coordinator, id: id, byteCount: 3)
          addRecording(to: coordinator, id: id, file: file, byteCount: 3)

          coordinator.retryUpload(recordID: id)
          try await eventually { destination.state.withLock { $0.uploadAttempts } == 1 }
          await coordinator.cancelUpload(of: id)

          let key = try #require(destination.state.withLock { $0.attemptKeys.first })
          let record = try #require(coordinator.history.record(id: id))
          #expect(record.pendingObjectKey == key)
          #expect(record.objectLocation == world.location)
          #expect(record.uploadState == .failed(message: "Upload cancelled."))
          #expect(coordinator.fileUploadIDs.isEmpty)
          #expect(coordinator.uploadingIDs.isEmpty)
      }

      /// 30 (harness design 3.2). Phase 3's draining: a lane the Upload tab replaced stays in `drainingQueues` while it has work,
      /// polling every 500 ms on the clock, and goes once it is idle.
      @Test func aReplacedLaneDrainsUntilIdle() async throws {
          defer { world.removeAll() }
          destination.state.withLock { $0.blockingUploadsRemaining = 1 }
          let coordinator = world.makeCoordinator()
          let id = UUID()
          let file = try pendingFile(in: coordinator, id: id, byteCount: 3)
          addRecording(to: coordinator, id: id, file: file, byteCount: 3)
          coordinator.retryUpload(recordID: id)
          try await eventually { destination.state.withLock { $0.uploadAttempts } == 1 }

          coordinator.destinationDidChange()
          #expect(coordinator.queue == nil)
          #expect(coordinator.drainingQueues.count == 1)
          try await world.clock.run(for: .seconds(1))
          #expect(coordinator.drainingQueues.count == 1)

          await coordinator.cancelUpload(of: id)
          try await world.clock.run(until: { coordinator.drainingQueues.isEmpty })
          #expect(coordinator.drainingQueues.isEmpty)
      }

      /// 31 (harness design 3.2). A Retry of a record being trimmed says why and reads no destination; of a record already
      /// uploading, nothing.
      @Test func aRetryOfATrimmingOrUploadingRecordDoesNothingButSay() async throws {
          defer { world.removeAll() }
          let coordinator = world.makeCoordinator()
          let trimming = try addPendingImage(to: coordinator)
          let uploading = try addPendingImage(to: coordinator)
          coordinator.trimmingIDs.insert(trimming.id)
          coordinator.uploadingIDs.insert(uploading.id)

          coordinator.retryUpload(recordID: trimming.id)
          coordinator.retryUpload(recordID: uploading.id)

          #expect(world.notifier.calls == [.error(title: "Not uploaded", message: "This capture is being trimmed.")])
          #expect(world.factory.askedConfigs.isEmpty)
          #expect(coordinator.queue == nil)
      }

      /// 32 (harness design 3.2). Retry Failed Uploads with no credentials says so once; with them, every failed record goes.
      @Test func retryFailedUploadsSaysOnceWithoutCredentialsAndEnqueuesWithThem() async throws {
          defer { world.removeAll() }
          try world.credentials.delete(account: KeychainCredentialStore.defaultAccount)
          let coordinator = world.makeCoordinator()
          let first = try addPendingImage(to: coordinator)
          let second = try addPendingImage(to: coordinator)

          coordinator.retryFailedUploads()
          #expect(world.notifier.calls == [.error(title: "Upload not configured",
                                                   message: "Set up a destination in Settings > Upload, then retry.")])
          #expect(coordinator.uploadingIDs.isEmpty)

          try world.credentials.save(CoordinatorWorld.awsCredentials, account: KeychainCredentialStore.defaultAccount)
          coordinator.retryFailedUploads()
          #expect(coordinator.uploadingIDs == [first.id, second.id])
          try await eventually { isUploaded(coordinator, first.id) && isUploaded(coordinator, second.id) }
      }

      /// 33 (harness design 3.2). `Upload not configured` posts once per launch, that is once per coordinator.
      @Test func notConfiguredIsPostedOncePerCoordinator() {
          defer { world.removeAll() }
          let coordinator = world.makeCoordinator()
          coordinator.warnUploadNotConfiguredOnce("first")
          coordinator.warnUploadNotConfiguredOnce("second")
          let relaunched = world.makeCoordinator()
          relaunched.warnUploadNotConfiguredOnce("third")

          #expect(world.notifier.calls == [.error(title: "Upload not configured", message: "first"),
                                           .error(title: "Upload not configured", message: "third")])
      }

      /// 34 (harness design 3.2). R2's privacy rule's backstop: `startUpload` of a recording marked `Sound not muted` logs and
      /// changes nothing.
      @Test func aRefusedRecordIsLoggedAndLeftAlone() throws {
          defer { world.removeAll() }
          let coordinator = world.makeCoordinator()
          let id = UUID()
          let file = try pendingFile(in: coordinator, id: id, byteCount: 3)
          let record = addRecording(to: coordinator, id: id, file: file, byteCount: 3,
                                    unmutedIntervals: [MuteInterval(start: 0, end: 1)])
          let target = try #require(coordinator.makeDestination())

          coordinator.startUpload(recordID: id, payload: .file(file, scope: nil), destination: target)

          #expect(world.logLines == ["Upload: refused for \(file.lastPathComponent): \(CaptureRecord.soundNotMutedBody)"])
          #expect(coordinator.history.record(id: id) == record)
          #expect(coordinator.uploadingIDs.isEmpty)
          #expect(coordinator.queue == nil)
      }
  }
  ```
- [ ] Run `CoordinatorUploadTests` alone, then the full suite: `2125 tests in 177 suites`.
- [ ] Commit: `test: coordinator uploads`.

### Task 7: `CoordinatorDeleteTests` [integration]

**Files:** create `TidyShotTests/CoordinatorDeleteTests.swift`.

**Consumes:** Tasks 3 and 4 (`environment.confirm`). Test 39 lands with Task 13, which changes the 404's log line.

**Gate (D12):** test 46 pins that pruning closes no card, where the design's 3.3 line says it closes the card with `.deleted`. Tim rules on D12 before this task runs (at the plan's review). If he confirms, write the suite as below, and Task 16 corrects the design's line. If he overrules, stop: closing the card on a prune is a behaviour change, and it gets its own task (an `overlay.close(recordID: record.id, reason: .deleted)` in `removeFiles(ofPruned:)`, with test 46 expecting `world.cards.closes == [.deleted]` for a showing card) before this one.

**Steps:**
- [ ] Create the suite:
  ```swift
  import Foundation
  import Testing
  @testable import TidyShot

  /// Delete, its aborts and the prune on a built coordinator (R4 design, Delete; Phase 3's delete order;
  /// harness design 3.3). Destinations come from the world's factory; the alerts are `FakeConfirm`.
  @Suite(.timeLimit(.minutes(1)))
  struct CoordinatorDeleteTests {
      let world: CoordinatorWorld

      init() throws {
          world = try CoordinatorWorld()
      }

      var destination: FakeDestination { world.factory.standard }

      func location(_ bucket: String) -> ObjectLocation {
          ObjectLocation(endpoint: "https://s3.us-west-2.amazonaws.com", region: "us-west-2", bucket: bucket,
                         usePathStyle: true)
      }

      func ref(at location: ObjectLocation, uploadID: String = "stored-1") -> MultipartRef {
          MultipartRef(uploadID: uploadID, key: "s/STORED.mp4", location: location)
      }

      /// An uploaded screenshot with no local file, at the world's location.
      func addUploadedImage(to coordinator: AppCoordinator, key: String = "s/SHOT.png") -> CaptureRecord {
          let record = CaptureRecord(fileURL: nil, pixelWidth: 4, pixelHeight: 2, appName: nil,
                                     uploadState: .uploaded(url: URL(string: "https://snap.tky.io/\(key)")!, key: key),
                                     objectLocation: world.location)
          coordinator.history.add(record)
          return record
      }

      /// A recording in `pending/` of 3 bytes, added to history.
      func addPendingRecording(to coordinator: AppCoordinator, state: CaptureRecord.UploadState = .none,
                               multipart: MultipartUploadState? = nil) throws -> CaptureRecord {
          let id = UUID()
          let url = coordinator.pendingFiles.directory.appending(path: "\(id.uuidString).mp4")
          try CoordinatorWorld.writeSparseFile(at: url, byteCount: 3)
          let record = CaptureRecord(id: id, fileURL: url, fileIsTemporary: true, pixelWidth: 1600, pixelHeight: 1000,
                                     appName: nil, uploadState: state, mediaKind: .video, durationSeconds: 10,
                                     byteCount: 3, multipart: multipart)
          coordinator.history.add(record)
          return record
      }

      func exists(_ url: URL) -> Bool {
          FileManager.default.fileExists(atPath: url.path(percentEncoded: false))
      }

      /// 35 (harness design 3.3). Nothing to abort: nil, and no destination is made.
      @Test func abortingNothingAsksForNoDestination() async {
          defer { world.removeAll() }
          let coordinator = world.makeCoordinator()

          #expect(await coordinator.abortUploads([], name: "Recording.mp4") == nil)
          #expect(world.factory.askedConfigs.isEmpty)
      }

      /// 36 (harness design 3.3). A Keychain read that fails is the reason, not missing credentials.
      @Test func aKeychainReadThatFailsIsTheAbortsReason() async {
          defer { world.removeAll() }
          world.credentialStore = ThrowingCredentialStore()
          let coordinator = world.makeCoordinator()

          let reason = await coordinator.abortUploads([ref(at: world.location)], name: "Recording.mp4")

          let expected = "Could not read S3 credentials from the keychain: The keychain is locked."
          #expect(reason == expected)
          #expect(world.logLines == ["Keychain read failed: The keychain is locked.",
                                     "Upload: Recording.mp4 multipart abort failed: \(expected)"])
          #expect(world.factory.askedConfigs.isEmpty)
      }

      /// 37 (harness design 3.3). No stored credentials is the reason.
      @Test func noStoredCredentialsIsTheAbortsReason() async throws {
          defer { world.removeAll() }
          try world.credentials.delete(account: KeychainCredentialStore.defaultAccount)
          let coordinator = world.makeCoordinator()

          let reason = await coordinator.abortUploads([ref(at: world.location)], name: "Recording.mp4")

          #expect(reason == "No credentials are saved in Settings > Upload.")
          #expect(world.logLines == ["Upload: Recording.mp4 multipart abort failed: No credentials are saved in Settings > Upload."])
      }

      /// 38 (harness design 3.3). R4 checklist, Multipart: Delete of a failed multipart upload aborts it. A 204 is sent again,
      /// for a part that lands after the first.
      @Test func anAbortThatAnswers204IsSentAgain() async {
          defer { world.removeAll() }
          let coordinator = world.makeCoordinator()

          let reason = await coordinator.abortUploads([ref(at: world.location)], name: "Recording.mp4")

          #expect(reason == nil)
          #expect(destination.state.withLock { $0.aborts.map(\.uploadID) } == ["stored-1", "stored-1"])
          #expect(world.logLines == ["Upload: Recording.mp4 multipart aborted"])
      }

      /// 40 (harness design 3.3). A failed Abort is the reason at once; a later upload is not tried.
      @Test func aFailedAbortStopsAtOnce() async {
          defer { world.removeAll() }
          destination.state.withLock { $0.abortFailures = [.httpStatus(403, body: "AccessDenied: Access Denied")] }
          let other = FakeDestination()
          world.factory.add(other, at: location("old.tky.io"))
          let coordinator = world.makeCoordinator()

          let reason = await coordinator.abortUploads([ref(at: world.location), ref(at: location("old.tky.io"))],
                                                      name: "Recording.mp4")

          #expect(reason == "Server returned HTTP 403: AccessDenied: Access Denied")
          #expect(other.state.withLock { $0.aborts.isEmpty })
          #expect(world.factory.askedLocations == [world.location])
          #expect(world.logLines == ["Upload: Recording.mp4 multipart abort failed: Server returned HTTP 403: AccessDenied: Access Denied"])
      }

      /// 41 (harness design 3.3). Each upload is aborted where it was created, never through the current Upload settings.
      @Test func eachUploadIsAbortedWhereItWasCreated() async {
          defer { world.removeAll() }
          let first = FakeDestination()
          let second = FakeDestination()
          world.factory.add(first, at: location("one.tky.io"))
          world.factory.add(second, at: location("two.tky.io"))
          let coordinator = world.makeCoordinator()

          let reason = await coordinator.abortUploads([ref(at: location("one.tky.io"), uploadID: "one"),
                                                       ref(at: location("two.tky.io"), uploadID: "two")],
                                                      name: "Recording.mp4")

          #expect(reason == nil)
          #expect(world.factory.askedLocations == [location("one.tky.io"), location("two.tky.io")])
          #expect(first.state.withLock { $0.aborts.map(\.uploadID) } == ["one", "one"])
          #expect(second.state.withLock { $0.aborts.map(\.uploadID) } == ["two", "two"])
          #expect(destination.state.withLock { $0.aborts.isEmpty })
      }

      /// 42 (harness design 3.3). Phase 3: one confirmation; a second Delete while it is open asks nothing; Cancel keeps the
      /// record and deletes nothing.
      @Test func deleteAsksOnceAndASecondDeleteWhileItAsksAsksNothing() async throws {
          defer { world.removeAll() }
          world.confirm.holds = true
          let coordinator = world.makeCoordinator()
          let record = addUploadedImage(to: coordinator)

          let first = Task { await coordinator.deleteCapture(recordID: record.id) }
          try await eventually { world.confirm.isWaiting }
          // Its own task, gated with `eventually`: were the guard broken, `FakeConfirm` would record the
          // second ask as an issue and answer it Cancel, so the test fails instead of hanging.
          let second = TaskWatch(Task { await coordinator.deleteCapture(recordID: record.id) })
          try await eventually { second.hasReturned }
          #expect(world.confirm.asked == [.delete(record)])
          world.confirm.answer(false)
          await first.value

          #expect(coordinator.deletingIDs.isEmpty)
          #expect(coordinator.history.record(id: record.id) != nil)
          #expect(destination.state.withLock { $0.deletedKeys.isEmpty })
      }

      /// 43 (harness design 3.3). R4 checklist, Multipart: an Abort refused shows the second alert with the reason and `The
      /// object stays in the bucket.`; No keeps the record and deletes nothing, Yes removes the record and
      /// its pending file.
      @Test func anAbortFailureAsksToRemoveFromHistory() async throws {
          defer { world.removeAll() }
          world.settings.confirmBeforeDeleting = false
          let refused = UploadError.httpStatus(403, body: "AccessDenied: Access Denied")
          destination.state.withLock { $0.abortFailures = [refused, refused] }
          world.confirm.answers = [false, true]
          let coordinator = world.makeCoordinator()
          let stored = MultipartUploadState(uploadID: "stored-1", key: "s/STORED.mp4", location: world.location,
                                            partSize: 262_144, byteCount: 3, sourceModified: Date(),
                                            sourcePath: "/nowhere/Recording.mp4", startedAt: Date())
          let record = try addPendingRecording(to: coordinator, state: .failed(message: "Upload was interrupted."),
                                               multipart: stored)
          let pending = try #require(record.fileURL)
          let question = DeleteConfirmation.removeFromHistory(
              message: CaptureDeletion.storageFailureMessage(reason: "Server returned HTTP 403: AccessDenied: Access Denied"),
              informativeText: CaptureDeletion.storageFailureText)

          await coordinator.deleteCapture(recordID: record.id)
          #expect(world.confirm.asked == [question])
          #expect(coordinator.history.record(id: record.id) != nil)
          #expect(exists(pending))

          await coordinator.deleteCapture(recordID: record.id)
          #expect(world.confirm.asked == [question, question])
          #expect(coordinator.history.record(id: record.id) == nil)
          #expect(!exists(pending))
          #expect(destination.state.withLock { $0.deletedKeys.isEmpty })
      }

      /// 44 (harness design 3.3). Phase 3: a key another capture shares is kept, `Not deleted from storage` says so, and the
      /// record goes.
      @Test func aSharedKeyKeepsTheObjectAndSaysSo() async {
          defer { world.removeAll() }
          world.settings.confirmBeforeDeleting = false
          let coordinator = world.makeCoordinator()
          let deleted = addUploadedImage(to: coordinator, key: "s/SHARED.png")
          let sharer = addUploadedImage(to: coordinator, key: "s/SHARED.png")

          await coordinator.deleteCapture(recordID: deleted.id)

          #expect(world.confirm.asked.isEmpty)
          #expect(coordinator.history.record(id: deleted.id) == nil)
          #expect(coordinator.history.record(id: sharer.id) != nil)
          #expect(destination.state.withLock { $0.deletedKeys.isEmpty })
          #expect(world.notifier.calls == [.error(title: "Not deleted from storage",
                                                   message: "Another capture shares this key, s/SHARED.png, so its object was kept. This capture was removed from Recent Captures.")])
      }

      /// 45 (harness design 3.3). Phase 3: a pending file that cannot be removed keeps the record, with `Not deleted`.
      @Test func aPendingFileThatCannotBeRemovedKeepsTheRecord() async throws {
          defer { world.removeAll() }
          world.settings.confirmBeforeDeleting = false
          let coordinator = world.makeCoordinator()
          let record = try addPendingRecording(to: coordinator)
          let pending = try #require(record.fileURL)
          let folder = coordinator.pendingFiles.directory.path(percentEncoded: false)
          try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: folder)
          defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: folder) }

          await coordinator.deleteCapture(recordID: record.id)

          #expect(world.confirm.asked.isEmpty)
          #expect(coordinator.history.record(id: record.id) != nil)
          #expect(exists(pending))
          let error = try #require(world.notifier.errors.first)
          #expect(error.title == "Not deleted")
          #expect(error.message.hasPrefix("Could not delete \(pending.lastPathComponent): "))
      }

      /// 46 (harness design 3.3). R4 checklist, Multipart: pruning removes the thumbnail, the pending file, the sidecar and the
      /// kept copy, and aborts nothing (no destination is made). It closes no card.
      @Test func pruningRemovesTheFilesAndAsksForNoDestination() async throws {
          defer { world.removeAll() }
          let coordinator = world.makeCoordinator()
          let id = UUID()
          let thumbnail = try coordinator.thumbnails.write(Data("png".utf8), id: id)
          let pending = coordinator.pendingFiles.directory.appending(path: "\(id.uuidString).mp4")
          try CoordinatorWorld.writeSparseFile(at: pending, byteCount: 3)
          try coordinator.multipartFiles.writeSidecar(MultipartSidecar(uploadID: "stored-1", completeSent: false, parts: []),
                                                      id: id)
          let keptCopy = coordinator.multipartFiles.keptCopyURL(for: id, ext: "mp4")
          try Data([1]).write(to: keptCopy)
          let record = CaptureRecord(id: id, fileURL: pending, fileIsTemporary: true, thumbnailFileName: thumbnail,
                                     pixelWidth: 1600, pixelHeight: 1000, appName: nil,
                                     uploadState: .uploaded(url: URL(string: "https://snap.tky.io/s/OLD.mp4")!, key: "s/OLD.mp4"),
                                     objectLocation: world.location, mediaKind: .video)

          coordinator.removeFiles(ofPruned: [record])

          #expect(!exists(coordinator.thumbnails.url(forFileName: thumbnail)))
          #expect(!exists(pending))
          try await eventually { !exists(coordinator.multipartFiles.sidecarURL(for: id)) && !exists(keptCopy) }
          #expect(world.factory.askedConfigs.isEmpty)
          #expect(world.cards.closes.isEmpty)
      }

      /// 47 (harness design 3.3). Removing a record clears its bookkeeping everywhere.
      @Test func removingARecordClearsItsBookkeeping() async {
          defer { world.removeAll() }
          world.settings.confirmBeforeDeleting = false
          let coordinator = world.makeCoordinator()
          let record = CaptureRecord(fileURL: nil, pixelWidth: 4, pixelHeight: 2, appName: nil)
          coordinator.history.add(record)
          let id = record.id
          coordinator.optimizingVideoIDs.insert(id)
          coordinator.fileUploadIDs.insert(id)
          coordinator.videoClipboardCounts[id] = 3
          coordinator.linkNotCopiedIDs.insert(id)
          coordinator.copyFileCounts[id] = 4
          coordinator.dragDownloadResume[id] = (data: Data([1]), signedAt: world.date)

          await coordinator.deleteCapture(recordID: id)

          #expect(world.confirm.asked.isEmpty)
          #expect(coordinator.history.record(id: id) == nil)
          #expect(!coordinator.optimizingVideoIDs.contains(id))
          #expect(!coordinator.fileUploadIDs.contains(id))
          #expect(coordinator.videoClipboardCounts[id] == nil)
          #expect(!coordinator.linkNotCopiedIDs.contains(id))
          #expect(coordinator.copyFileCounts[id] == nil)
          #expect(coordinator.dragDownloadResume[id] == nil)
      }
  }
  ```
- [ ] Run `CoordinatorDeleteTests` alone, then the full suite: `2137 tests in 178 suites`.
- [ ] Commit: `test: coordinator delete and aborts`.

### Task 8: `CoordinatorRecordingTests` and `recordingProceeds` [integration]

**Files:**
- Modify `TidyShot/App/AppCoordinator+Recording.swift`: the static after `recordingStopCommandAction` (:45-51), the guard in `record()` (:397-405), and the enum at the file's end.
- Create `TidyShotTests/CoordinatorRecordingTests.swift`.

**Produces:** `nonisolated enum RecordingProceeds: Equatable, Sendable { case start; case stop(logsCancel: Bool) }` and `nonisolated static func recordingProceeds(started: Bool, isQuitting: Bool, cancelled: Bool) -> RecordingProceeds`; `record()` reads it, with the same check, log and return as before.

**Steps:**
- [ ] After `recordingStopCommandAction(for:)`'s closing brace, add:
  ```swift

      /// What `record()` does once the hand-off returns (harness design 3.4): it starts only with a start,
      /// no quit and no cancelled count-in. Otherwise nothing records, and the log says why only when
      /// the cancel stopped a start the hand-off allowed; a quit, or a hand-off that gave up, says nothing here.
      nonisolated static func recordingProceeds(started: Bool, isQuitting: Bool, cancelled: Bool) -> RecordingProceeds {
          guard started, !isQuitting else { return .stop(logsCancel: false) }
          return cancelled ? .stop(logsCancel: true) : .start
      }
  ```
- [ ] In `record()`, replace
  ```swift
          guard let start, !isQuitting, !recordingStartCancelled else {
              if start != nil, !isQuitting {
                  RecordingLog.note("Recording: not started, the count-in was cancelled")
              }
  ```
  with
  ```swift
          let proceeds = Self.recordingProceeds(started: start != nil, isQuitting: isQuitting,
                                                cancelled: recordingStartCancelled)
          guard let start, proceeds == .start else {
              if proceeds == .stop(logsCancel: true) {
                  RecordingLog.note("Recording: not started, the count-in was cancelled")
              }
  ```
  The two comment lines above the guard, `endNoticeHold()`, `return nil` and the rest stay; nothing suspends between the reads and `recorder.run`.
- [ ] At the end of the file, add:
  ```swift

  /// What `record()` does after the hand-off (`AppCoordinator.recordingProceeds(started:isQuitting:cancelled:)`).
  nonisolated enum RecordingProceeds: Equatable, Sendable {
      case start
      /// Nothing records; `logsCancel` when a cancelled count-in stopped a start the hand-off allowed.
      case stop(logsCancel: Bool)
  }
  ```
- [ ] Create the suite:
  ```swift
  import AppKit
  import Foundation
  import Testing
  @testable import TidyShot

  /// The recording commands and prompts on a built coordinator (R4 design, `stop-recording` and
  /// `record-screen` in each phase; R3 design, Asking from Settings; R1 design, Quit; harness design 3.4).
  /// A recording runs on the world's `RecordingController` over `FakeRecordingDriver`; nothing records.
  @Suite(.timeLimit(.minutes(1)))
  struct CoordinatorRecordingTests {
      let world: CoordinatorWorld
      let display = RecordingDisplay(id: 1, frame: CGRect(x: 0, y: 0, width: 1728, height: 1117), scale: 2)

      init() throws {
          world = try CoordinatorWorld()
      }

      func areaRequest() -> RecordingRequest {
          let id = UUID()
          let options = RecordingOptions(framesPerSecond: 30, retina: true, systemAudio: false, showsCursor: true)
          return RecordingRequest(id: id,
                                  configuration: .make(.area(CGRect(x: 100, y: 100, width: 800, height: 500), on: display),
                                                       options: options),
                                  displayID: display.id,
                                  outputURL: URL(filePath: "/private/tmp/CoordinatorRecordingTests/Recording/\(id.uuidString).mp4"),
                                  muteLogURL: URL(filePath: "/private/tmp/CoordinatorRecordingTests/Mute/\(id.uuidString).json"),
                                  lag: RecordingMute.defaultLag)
      }

      /// A recording on the coordinator's recorder, past its first frame.
      func beginRecording(on coordinator: AppCoordinator) async -> Task<RecordingOutcome, Never> {
          let request = areaRequest()
          let recorder = coordinator.recorder
          let chrome = world.chrome
          let run = Task { await recorder.run(request, chrome: chrome, onStarted: {}) }
          await world.recording.advance(by: .zero)
          world.driver.send(.recordingStarted)
          await world.recording.advance(by: .seconds(3))
          return run
      }

      /// A countdown on the coordinator's self-timer, shown.
      func beginCountdown(on coordinator: AppCoordinator) async throws -> Task<SelfTimerOutcome, Never> {
          let stage = FakeSelfTimerStage()
          let selfTimer = coordinator.selfTimer
          let countdown = Task { await selfTimer.run(seconds: 3, stage: stage, capture: {}) }
          try await eventually { stage.events.contains("show 3") }
          return countdown
      }

      /// 48 (harness design 3.4). R4 checklist, U1: `stop-recording` with nothing recording, or during a save, posts nothing,
      /// cancels no count-in, leaves the phase as it was, and stops no recorder. The recorder drops a stop with no run
      /// itself, so this does not tell the `.nothing` branch from a stray `recorder.stop()` (D24).
      @Test func stopRecordingWhileIdleOrSavingChangesNothing() {
          defer { world.removeAll() }
          let coordinator = world.makeCoordinator()

          coordinator.stopRecordingCommand(sender: "Raycast")
          coordinator.recordingSavesInFlight = 1
          #expect(coordinator.recordingPhase == .saving)
          coordinator.stopRecordingCommand(sender: "Raycast")

          #expect(!coordinator.recordingStartCancelled)
          #expect(world.driver.stopCount == 0)
          #expect(world.notifier.calls.isEmpty)
          #expect(coordinator.recordingPhase == .saving)
      }

      /// 49 (harness design 3.4). R4 checklist, U1: during the count-in it is cancelled, and the flag holds the cancel for the
      /// settle delay and the content read.
      @Test func stopRecordingDuringACountInCancelsIt() async throws {
          defer { world.removeAll() }
          let coordinator = world.makeCoordinator()
          coordinator.recordingCountIn = true
          let countdown = try await beginCountdown(on: coordinator)

          coordinator.stopRecordingCommand(sender: "Raycast")

          #expect(coordinator.recordingStartCancelled)
          // Gated with `eventually`: a countdown the command did not cancel sleeps on the world's clock,
          // which nothing moves, so awaiting it would hang.
          let ended = TaskWatch(countdown)
          try await eventually { ended.hasReturned }
          #expect(await countdown.value == .cancelled)
          #expect(world.notifier.calls.isEmpty)
      }

      /// 50 (harness design 3.4). R4 checklist, U1: during the recording it stops it, and with a second one during the stop
      /// wait (plan Gap 5 of R4) the recorder still stops once and nothing posts. The recorder drops a repeated stop
      /// itself, so this does not see the coordinator's `isEnding` check; its log line is Tim's (D24).
      @Test func stopRecordingDuringARecordingStopsItOnce() async throws {
          defer { world.removeAll() }
          let coordinator = world.makeCoordinator()
          let run = await beginRecording(on: coordinator)
          #expect(coordinator.recordingPhase == .recording)

          coordinator.stopRecordingCommand(sender: "Raycast")
          #expect(coordinator.recorder.isEnding)
          coordinator.stopRecordingCommand(sender: "Raycast")
          // Gated with `eventually`: a recording the command did not stop waits for its end for ever.
          let ended = TaskWatch(run)
          try await eventually { ended.hasReturned }

          #expect(!coordinator.recorder.isRunning)
          #expect(world.driver.stopCount == 1)
          #expect(world.notifier.calls.isEmpty)
      }

      /// 51 (harness design 3.4). R4 plan Gap 6: the start's cancel flag resets when a count-in begins, and only then.
      @Test func theStartCancelResetsOnlyWhenACountInBegins() {
          defer { world.removeAll() }
          let coordinator = world.makeCoordinator()

          coordinator.recordingStartCancelled = true
          coordinator.recordingCountIn = true
          #expect(!coordinator.recordingStartCancelled)

          coordinator.recordingStartCancelled = true
          coordinator.recordingCountIn = true
          #expect(coordinator.recordingStartCancelled)
      }

      /// 52 (harness design 3.4). R4 checklist, Settings prompt section: the record shortcut or `stop-recording` in the settle
      /// delay records nothing and logs `not started, the count-in was cancelled`; a quit says nothing.
      @Test func recordingProceedsOnlyWhenStartedNotQuittingAndNotCancelled() {
          defer { world.removeAll() }
          #expect(AppCoordinator.recordingProceeds(started: true, isQuitting: false, cancelled: false) == .start)
          #expect(AppCoordinator.recordingProceeds(started: true, isQuitting: false, cancelled: true)
                  == .stop(logsCancel: true))
          #expect(AppCoordinator.recordingProceeds(started: true, isQuitting: true, cancelled: false)
                  == .stop(logsCancel: false))
          #expect(AppCoordinator.recordingProceeds(started: true, isQuitting: true, cancelled: true)
                  == .stop(logsCancel: false))
          #expect(AppCoordinator.recordingProceeds(started: false, isQuitting: false, cancelled: false)
                  == .stop(logsCancel: false))
          #expect(AppCoordinator.recordingProceeds(started: false, isQuitting: false, cancelled: true)
                  == .stop(logsCancel: false))
          #expect(AppCoordinator.recordingProceeds(started: false, isQuitting: true, cancelled: false)
                  == .stop(logsCancel: false))
          #expect(AppCoordinator.recordingProceeds(started: false, isQuitting: true, cancelled: true)
                  == .stop(logsCancel: false))
      }

      /// 53 (harness design 3.4). R4 checklist, U1: `record-screen` during a count-in, a recording or a prompt starts nothing;
      /// a second one while the first is pending starts nothing; nor while quitting. (The successful
      /// start reaches ScreenCaptureKit and stays a hand check.)
      @Test func aURLStartIsRefusedInEveryPhaseThatDropsIt() async {
          defer { world.removeAll() }
          // A start that got past a refusal parks at its camera prompt (the bubble on, access not
          // determined), before the capture lock, so it never makes `tmp/Recording`, reads the content
          // or shows a selection; the last checks catch it. The parked prompt is never answered. Desktop
          // covers stay off whatever the defaults say.
          world.settings.recordingWebcamBubble = true
          world.settings.hideDesktopIconsWhileCapturing = false
          let cameras = HeldCameraDevices()
          world.cameras = cameras
          let coordinator = world.makeCoordinator()
          // `.standard` reads `AppSettings.shared`; this intent reads no settings.
          let intent = CaptureIntent(action: .save)

          coordinator.recordingCountIn = true
          coordinator.startRecording(intent: intent, preselect: nil)
          #expect(!coordinator.urlRecordingStartPending)
          coordinator.recordingCountIn = false

          coordinator.askingPermission = .camera
          coordinator.startRecording(intent: intent, preselect: nil)
          #expect(!coordinator.urlRecordingStartPending)
          coordinator.askingPermission = nil

          coordinator.urlRecordingStartPending = true
          coordinator.startRecording(intent: intent, preselect: nil)
          for _ in 0..<20 { await Task.yield() }
          #expect(coordinator.urlRecordingStartPending)
          #expect(!coordinator.isCapturing)
          #expect(coordinator.askingPermission == nil)
          coordinator.urlRecordingStartPending = false

          let run = await beginRecording(on: coordinator)
          coordinator.startRecording(intent: intent, preselect: nil)
          #expect(!coordinator.urlRecordingStartPending)
          coordinator.recorder.stop()
          _ = await run.value

          await coordinator.finishRecordingForQuit()
          coordinator.startRecording(intent: intent, preselect: nil)
          #expect(!coordinator.urlRecordingStartPending)
          for _ in 0..<20 { await Task.yield() }
          // No start reached the camera prompt, and only the quit's wait posted.
          #expect(cameras.requestCount == 0)
          #expect(coordinator.askingPermission == nil)
          #expect(world.notifier.calls == [.waited(.seconds(1))])
      }

      /// 54 (harness design 3.4). R3 design, Asking from Settings: Settings asks while nothing else runs, with the prompt held
      /// as `askingPermission`; not while a capture holds the lock, nor while another prompt is open.
      @Test func aSettingsPromptAsksOnlyWhenNothingElseRuns() async throws {
          defer { world.removeAll() }
          let cameras = HeldCameraDevices()
          world.cameras = cameras
          let coordinator = world.makeCoordinator()

          let ask = Task { await coordinator.requestAccessFromSettings(.camera) }
          try await eventually { cameras.isAsking }
          #expect(coordinator.askingPermission == .camera)
          #expect(cameras.requestCount == 1)
          cameras.answer(true)
          await ask.value
          #expect(coordinator.askingPermission == nil)

          // The two asks that must not prompt run as their own tasks, gated with `eventually`: one that
          // prompted after all would wait for an answer that never comes, so the test fails in two
          // seconds instead of hanging.
          let gate = TestGate()
          let lock = Task { await coordinator.withCaptureLock(coversDesktop: false) { await gate.wait() } }
          try await eventually { gate.isWaiting }
          let duringLock = TaskWatch(Task { await coordinator.requestAccessFromSettings(.camera) })
          try await eventually { duringLock.hasReturned }
          #expect(cameras.requestCount == 1)
          #expect(coordinator.askingPermission == nil)
          gate.open()
          _ = await lock.value

          coordinator.askingPermission = .microphone
          let duringPrompt = TaskWatch(Task { await coordinator.requestAccessFromSettings(.camera) })
          try await eventually { duringPrompt.hasReturned }
          #expect(cameras.requestCount == 1)
          #expect(coordinator.askingPermission == .microphone)
      }

      /// 55 (harness design 3.4). R2 design, Decided 2026-10-24, 9: while a prompt is open every capture is refused, and the
      /// URL handler's reason names it; after the answer both clear.
      @Test func anOpenPromptRefusesCapturesUntilItIsAnswered() async throws {
          defer { world.removeAll() }
          let cameras = HeldCameraDevices()
          world.cameras = cameras
          let coordinator = world.makeCoordinator()

          let ask = Task { await coordinator.requestAccessFromSettings(.camera) }
          try await eventually { cameras.isAsking }
          #expect(coordinator.captureRefusal == .permissionPrompt(.camera))
          #expect(coordinator.capturesRefused)

          cameras.answer(false)
          await ask.value
          #expect(coordinator.captureRefusal == nil)
          #expect(!coordinator.capturesRefused)
      }

      /// 56 (harness design 3.4). R1 design, Quit: a quit cancels the count-in, stops the recording as Stop does (answering a
      /// Cancel's question with Save), and waits for the held notices once nothing records.
      @Test func aQuitCancelsTheCountInStopsTheRecordingAndWaitsForTheNotices() async throws {
          defer { world.removeAll() }
          let coordinator = world.makeCoordinator()
          let run = await beginRecording(on: coordinator)
          let countdown = try await beginCountdown(on: coordinator)
          // What the coordinator reads at the wait: the notices are waited for only once nothing records.
          var atWait: (phase: RecordingPhase, stops: Int)?
          let driver = world.driver
          world.notifier.onWait = { [weak coordinator] in
              if let coordinator { atWait = (coordinator.recordingPhase, driver.stopCount) }
          }

          let quit = Task { await coordinator.finishRecordingForQuit() }
          try await world.clock.run(until: { world.notifier.calls.contains(.waited(.seconds(1))) })
          await quit.value
          _ = await run.value

          #expect(coordinator.isQuitting)
          // Gated with `eventually`: a countdown the quit did not cancel sleeps on the world's clock past
          // what `run(until:)` moves it, so awaiting it would hang.
          let countdownEnded = TaskWatch(countdown)
          try await eventually { countdownEnded.hasReturned }
          #expect(await countdown.value == .cancelled)
          #expect(world.chrome.calls.contains("answer save"))
          #expect(world.driver.stopCount == 1)
          #expect(coordinator.recordingPhase == .idle)
          #expect(world.notifier.calls == [.waited(.seconds(1))])
          #expect(atWait?.phase == .idle)
          #expect(atWait?.stops == 1)
      }
  }
  ```
- [ ] Run `CoordinatorRecordingTests` and `ShortcutsTests` alone, then the full suite: `2146 tests in 179 suites`.
- [ ] Commit: `test: coordinator recording commands and prompts`.

### Task 9: `PendingFileStore.list` and `PendingRecovery` [mechanical]

**Files:**
- Modify `TidyShot/Output/PendingFileStore.swift` (`list()` after `remove(_:)`).
- Create `TidyShot/Output/PendingRecovery.swift`, `TidyShotTests/PendingRecoveryTests.swift`.
- Tests: add two to `TidyShotTests/PendingFileStoreTests.swift`.

**Steps:**
- [ ] Write the tests and see them fail. In `PendingFileStoreTests`, after `removeThrowsWhenTheFileCannotBeDeleted`:
  ```swift

      /// The launch step's listing (harness design 4.2): a missing folder and an empty one list nothing.
      @Test func listOfAMissingOrEmptyFolderIsEmpty() throws {
          defer { try? FileManager.default.removeItem(at: dir) }
          let store = PendingFileStore(directory: dir.appending(path: "pending"))
          #expect(store.list().isEmpty)

          try FileManager.default.createDirectory(at: store.directory, withIntermediateDirectories: true)
          #expect(store.list().isEmpty)
      }

      /// Hidden files are skipped; every other file is listed.
      @Test func listSkipsHiddenFiles() throws {
          defer { try? FileManager.default.removeItem(at: dir) }
          let store = PendingFileStore(directory: dir.appending(path: "pending"))
          let url = try store.write(Data([1]), id: UUID(), ext: "png")
          try Data([2]).write(to: store.directory.appending(path: ".DS_Store"))

          #expect(store.list().map(\.lastPathComponent) == [url.lastPathComponent])
      }
  ```
  Create `TidyShotTests/PendingRecoveryTests.swift`:
  ```swift
  import Foundation
  import Testing
  @testable import TidyShot

  /// Which files in `pending/` the launch step adopts (harness design 4.2): a `<UUID>.<png|mp4|gif>` that
  /// no record's id names, in name order; any other name is left alone.
  struct PendingRecoveryTests {
      let folder = URL(filePath: "/pending/", directoryHint: .isDirectory)

      func file(_ name: String) -> URL {
          folder.appending(path: name)
      }

      @Test func aUUIDNamedPNGWithNoRecordIsAnOrphan() {
          let id = UUID()
          let url = file("\(id.uuidString).png")
          #expect(PendingRecovery.orphans(listed: [url], recordIDs: [])
                  == [PendingRecovery.Found(url: url, id: id, kind: .image)])
      }

      @Test func anMP4AndAGIFAreOrphansToo() {
          let movie = UUID()
          let gif = UUID()
          let found = PendingRecovery.orphans(listed: [file("\(movie.uuidString).mp4"), file("\(gif.uuidString).gif")],
                                              recordIDs: [])
          #expect(Set(found.map(\.id)) == [movie, gif])
          #expect(found.first { $0.id == movie }?.kind == .video)
          #expect(found.first { $0.id == gif }?.kind == .gif)
      }

      /// By id, so a trim's write (the record exists, its `fileURL` not yet set) is kept.
      @Test func aFileWhoseUUIDIsARecordsIDIsKept() {
          let id = UUID()
          #expect(PendingRecovery.orphans(listed: [file("\(id.uuidString).mp4")], recordIDs: [id]).isEmpty)
      }

      @Test func aNameThatIsNotAUUIDWithACaptureExtensionIsLeftAlone() {
          let id = UUID()
          let names = ["\(id.uuidString).png.sb-6c1d2a0f-Xy12Ab", ".\(id.uuidString).png", "\(id.uuidString).txt",
                       "notes.png", id.uuidString]
          #expect(PendingRecovery.orphans(listed: names.map { file($0) }, recordIDs: []).isEmpty)
      }

      @Test func theOrphansComeInNameOrder() {
          let urls = (0..<4).map { _ in file("\(UUID().uuidString).png") }
          let sorted = urls.sorted { $0.lastPathComponent < $1.lastPathComponent }
          #expect(PendingRecovery.orphans(listed: urls.reversed(), recordIDs: []).map(\.url) == sorted)
      }
  }
  ```
- [ ] In `PendingFileStore.swift`, after `remove(_:)`'s closing brace, add:
  ```swift

      /// The folder's files, hidden ones skipped; nothing when the folder is missing. The launch step lists
      /// once, before any task starts (harness design 4.2).
      func list() -> [URL] {
          (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil,
                                                        options: .skipsHiddenFiles)) ?? []
      }
  ```
- [ ] Create `TidyShot/Output/PendingRecovery.swift`:
  ```swift
  import Foundation

  /// The `pending/` launch step's rule (harness design 4.2): which listed files are orphans to adopt. A file
  /// is one when its name is `<UUID>.<png|mp4|gif>` and that UUID is no record's id; any other name is left
  /// alone. By id, not by `fileURL`, so a trim's write (the record exists, its `fileURL` not yet set) and an
  /// edit kept under its own record are never taken, and a record's spelling of its path never matters.
  nonisolated enum PendingRecovery {
      /// An orphan: its file, the record id its name gives, and the kind its extension gives.
      struct Found: Equatable, Sendable {
          var url: URL
          var id: UUID
          var kind: MediaKind
      }

      /// The orphans among `listed`, in name order.
      static func orphans(listed: [URL], recordIDs: Set<UUID>) -> [Found] {
          listed.compactMap { url -> Found? in
              guard !url.lastPathComponent.hasPrefix("."),
                    let kind = [MediaKind.image, .video, .gif].first(where: { $0.fileExtension == url.pathExtension }),
                    let id = UUID(uuidString: url.deletingPathExtension().lastPathComponent),
                    !recordIDs.contains(id) else { return nil }
              return Found(url: url, id: id, kind: kind)
          }
          .sorted { $0.url.lastPathComponent < $1.url.lastPathComponent }
      }
  }
  ```
- [ ] Run `PendingRecoveryTests` and `PendingFileStoreTests` alone, then the full suite: `2153 tests in 180 suites`.
- [ ] Commit: `feat: pending folder listing and its orphan rule`.

### Task 10: `recoverRecordings` moves to `AppCoordinator+Recovery.swift` [mechanical]

**Files:** create `TidyShot/App/AppCoordinator+Recovery.swift`; modify `TidyShot/App/AppCoordinator+Recording.swift` (`recoverRecordings()` and its doc comment leave it).

A pure move, under the coordinator split design's section 2 argument: the body sees a subset of what it saw (its own file's privates are none, and every member it calls is internal), so no name resolves differently, and a missed widening would be a compile error.

**Steps:**
- [ ] Cut, from `+Recording.swift`, the block from `    /// The launch check (design, Relaunch after a crash), after \`history.load()\`. Each playable file` through `recoverRecordings()`'s closing `    }` (the line before the doc comment `    /// After the capture lock: a kept file is handed to \`saveRecording\`…`), with the blank line after it. Create `AppCoordinator+Recovery.swift` holding exactly:
  ```swift
  import AppKit
  import ImageIO

  // Launch recovery: what a crash, a kill or a failed rename left in pending/ and tmp/Recording (recording design, Relaunch after a crash; harness design 4.2). Its state is declared in AppCoordinator.swift.
  extension AppCoordinator {
  <the cut block, unchanged>
  }
  ```
- [ ] The pure-move check prints `pure move`:
  ```bash
  norm() { grep -vE '^(import |extension AppCoordinator \{$|\}$|(    )?// )' | sed -E 's/(^|[[:space:]])private(\(set\))? /\1/' | grep -v '^[[:space:]]*$' | sort; }
  diff <(for f in $(git ls-tree --name-only HEAD TidyShot/App/ | grep '/AppCoordinator'); do git show HEAD:$f; done | norm) <(cat TidyShot/App/AppCoordinator*.swift | norm) && echo "pure move"
  ```
  and `git status --short -- TidyShot` shows only ` M TidyShot/App/AppCoordinator+Recording.swift` and `?? TidyShot/App/AppCoordinator+Recovery.swift` (the new file is untracked until it is staged, so `git diff --stat` would list only the first).
- [ ] Run the full suite: `2153 tests in 180 suites`.
- [ ] Commit: `refactor: move recoverRecordings to AppCoordinator+Recovery`.

### Task 11: Adopting `pending/`'s orphans at launch [integration]

**Files:**
- Modify `TidyShot/App/AppCoordinator+Recovery.swift` (`adoptPendingFiles(_:)` and its reader), `TidyShot/App/AppCoordinator.swift` (`start()`, :284 and :293-295).
- Create `TidyShotTests/CoordinatorRecoveryTests.swift`.

**Produces:** `func adoptPendingFiles(_ listed: [URL]) async` (internal, as `recoverRecordings` is); `start()` lists `pending/` right after `history.load()` and runs one task, `adoptPendingFiles` then `recoverRecordings`.

**Steps:**
- [ ] Write `CoordinatorRecoveryTests` and see them fail:
  ```swift
  import CoreGraphics
  import Foundation
  import ImageIO
  import Testing
  import UniformTypeIdentifiers
  @testable import TidyShot

  /// The `pending/` launch step on a built coordinator (harness design 4.2): an orphan is adopted with a
  /// record kept until the user acts, never deleted, unless it is empty or cannot be read; only the listed
  /// files are considered, and a record added since the listing keeps its file.
  @Suite(.timeLimit(.minutes(1)))
  struct CoordinatorRecoveryTests {
      let world: CoordinatorWorld

      init() throws {
          world = try CoordinatorWorld()
      }

      func pendingURL(_ coordinator: AppCoordinator, _ id: UUID, _ ext: String) throws -> URL {
          try FileManager.default.createDirectory(at: coordinator.pendingFiles.directory, withIntermediateDirectories: true)
          return coordinator.pendingFiles.directory.appending(path: "\(id.uuidString).\(ext)")
      }

      /// A two-frame GIF of 8 by 6 pixels, each frame shown for half a second.
      func writeGIF(at url: URL) throws {
          let frame = try CoordinatorWorld.image(width: 8, height: 6)
          let destination = try #require(CGImageDestinationCreateWithURL(url as CFURL, UTType.gif.identifier as CFString,
                                                                         2, nil))
          let properties = [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 0.5]] as CFDictionary
          CGImageDestinationAddImage(destination, frame, properties)
          CGImageDestinationAddImage(destination, frame, properties)
          #expect(CGImageDestinationFinalize(destination))
      }

      func exists(_ url: URL) -> Bool {
          FileManager.default.fileExists(atPath: url.path(percentEncoded: false))
      }

      /// Harness design 4.2 (a `.png`) and 4.3: an orphan PNG gets a record of its pixel size and byte count,
      /// kept until the user acts, with a thumbnail, `Recovery: <name> recovered` and `Recovered a capture`.
      @Test func anOrphanPNGIsAdoptedWithItsSizeAThumbnailAndANotice() async throws {
          defer { world.removeAll() }
          let coordinator = world.makeCoordinator()
          let id = UUID()
          let png = try CoordinatorWorld.pngData(width: 40, height: 30)
          let url = try coordinator.pendingFiles.write(png, id: id, ext: "png")

          await coordinator.adoptPendingFiles(coordinator.pendingFiles.list())

          let record = try #require(coordinator.history.record(id: id))
          #expect(record.mediaKind == .image)
          #expect(record.pixelWidth == 40)
          #expect(record.pixelHeight == 30)
          #expect(record.byteCount == png.count)
          #expect(record.fileIsTemporary)
          #expect(record.fileURL?.lastPathComponent == url.lastPathComponent)
          #expect(record.uploadState == .none)
          #expect(record.isPendingOnly)
          #expect(world.notifier.calls == [.error(title: "Recovered a capture",
                                                   message: "\(url.lastPathComponent). Find it in Recent Captures.")])
          #expect(world.logLines == ["Recovery: \(url.lastPathComponent) recovered"])
          #expect(world.cards.calls.isEmpty)
          try await eventually { coordinator.history.record(id: id)?.thumbnailFileName != nil }
      }

      /// Harness design 4.2 (a `.mp4`) and 4.3: an orphan MP4 gets a record with its length, and
      /// `Recovered a recording` with `m:ss`.
      @Test func anOrphanMP4IsAdoptedWithItsLength() async throws {
          defer { world.removeAll() }
          let coordinator = world.makeCoordinator()
          let id = UUID()
          let url = try pendingURL(coordinator, id, "mp4")
          try await VideoFixtures.makeMP4(at: url, width: 64, height: 48, seconds: 1, audio: false)

          await coordinator.adoptPendingFiles(coordinator.pendingFiles.list())

          let record = try #require(coordinator.history.record(id: id))
          #expect(record.mediaKind == .video)
          #expect(record.pixelWidth == 64)
          #expect(record.pixelHeight == 48)
          let duration = try #require(record.durationSeconds)
          #expect(abs(duration - 1) < 0.1)
          #expect(record.byteCount == FileSizes.byteCount(of: url))
          #expect(world.notifier.calls == [.error(title: "Recovered a recording",
                                                   message: "\(url.lastPathComponent), \(RecordingClock.format(duration)). Find it in Recent Captures.")])
          try await eventually { coordinator.history.record(id: id)?.thumbnailFileName != nil }
      }

      /// Harness design 4.2 (a zero-byte file) and 4.3: removed, with `Recovery: <name> is empty, removed` (D11).
      @Test func aZeroByteFileIsRemoved() async throws {
          defer { world.removeAll() }
          let coordinator = world.makeCoordinator()
          let url = try pendingURL(coordinator, UUID(), "png")
          #expect(FileManager.default.createFile(atPath: url.path(percentEncoded: false), contents: Data()))

          await coordinator.adoptPendingFiles(coordinator.pendingFiles.list())

          #expect(!exists(url))
          #expect(coordinator.history.records.isEmpty)
          #expect(world.notifier.calls.isEmpty)
          #expect(world.logLines == ["Recovery: \(url.lastPathComponent) is empty, removed"])
      }

      /// Harness design 4.2 (adopting re-reads the records) and 4.3: a record added between the listing and
      /// the adoption keeps its file.
      @Test func aFileWhoseRecordWasAddedAfterTheListingIsLeftAlone() async throws {
          defer { world.removeAll() }
          let coordinator = world.makeCoordinator()
          let id = UUID()
          let url = try coordinator.pendingFiles.write(try CoordinatorWorld.pngData(width: 40, height: 30), id: id, ext: "png")
          let listed = coordinator.pendingFiles.list()
          let record = CaptureRecord(id: id, fileURL: url, fileIsTemporary: true, pixelWidth: 40, pixelHeight: 30,
                                     appName: nil)
          coordinator.history.add(record)

          await coordinator.adoptPendingFiles(listed)

          #expect(coordinator.history.records == [record])
          #expect(exists(url))
          #expect(world.notifier.calls.isEmpty)
          #expect(world.logLines.isEmpty)
      }

      /// Harness design 4.2 (listing) and 4.3: a file written after the listing is never considered.
      @Test func aFileNotInTheListingIsLeftAlone() async throws {
          defer { world.removeAll() }
          let coordinator = world.makeCoordinator()
          let listed = coordinator.pendingFiles.list()
          let url = try coordinator.pendingFiles.write(try CoordinatorWorld.pngData(width: 40, height: 30), id: UUID(),
                                                       ext: "png")

          await coordinator.adoptPendingFiles(listed)

          #expect(coordinator.history.records.isEmpty)
          #expect(exists(url))
          #expect(world.notifier.calls.isEmpty)
      }

      /// Harness design 4.2 (a `.png` that does not decode) and 4.3: removed, with
      /// `Recovery: <name> could not be read, removed`.
      @Test func aFileThatCannotBeReadIsRemovedAndLogged() async throws {
          defer { world.removeAll() }
          let coordinator = world.makeCoordinator()
          let url = try coordinator.pendingFiles.write(Data("not a png".utf8), id: UUID(), ext: "png")

          await coordinator.adoptPendingFiles(coordinator.pendingFiles.list())

          #expect(!exists(url))
          #expect(coordinator.history.records.isEmpty)
          #expect(world.notifier.calls.isEmpty)
          #expect(world.logLines == ["Recovery: \(url.lastPathComponent) could not be read, removed"])
      }

      /// Harness design 4.1 and 4.3, Phase 3's objection to a deleting sweep: an empty history (a corrupt
      /// file set aside) must not cost a capture. Every orphan comes back and every file stays.
      @Test func anEmptyHistoryAdoptsEveryOrphanAndDeletesNothing() async throws {
          defer { world.removeAll() }
          let coordinator = world.makeCoordinator()
          let image = UUID()
          let movie = UUID()
          let gif = UUID()
          let imageURL = try coordinator.pendingFiles.write(try CoordinatorWorld.pngData(width: 40, height: 30), id: image,
                                                            ext: "png")
          let movieURL = try pendingURL(coordinator, movie, "mp4")
          try await VideoFixtures.makeMP4(at: movieURL, width: 64, height: 48, seconds: 1, audio: false)
          let gifURL = try pendingURL(coordinator, gif, "gif")
          try writeGIF(at: gifURL)

          await coordinator.adoptPendingFiles(coordinator.pendingFiles.list())

          #expect(coordinator.history.record(id: image)?.mediaKind == .image)
          #expect(coordinator.history.record(id: movie)?.mediaKind == .video)
          let gifRecord = try #require(coordinator.history.record(id: gif))
          #expect(gifRecord.mediaKind == .gif)
          #expect(gifRecord.pixelWidth == 8)
          #expect(gifRecord.pixelHeight == 6)
          #expect(abs((gifRecord.durationSeconds ?? 0) - 1) < 0.01)
          #expect(exists(imageURL) && exists(movieURL) && exists(gifURL))
          #expect(world.notifier.calls.count == 3)
          #expect(world.logLines.allSatisfy { $0.hasSuffix(" recovered") })
          // The three thumbnails are written on detached tasks; wait for them, so none lands after
          // `removeAll()` and makes the world's folders again.
          try await eventually {
              [image, movie, gif].allSatisfy { coordinator.history.record(id: $0)?.thumbnailFileName != nil }
          }
      }
  }
  ```
- [ ] In `AppCoordinator+Recovery.swift`, before `recoverRecordings()`'s doc comment, add:
  ```swift
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
  ```
  and after the extension's closing brace, at the end of the file:
  ```swift

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
  ```
- [ ] In `AppCoordinator.swift`'s `start()`, after `        history.load()` (:284), add:
  ```swift
          // Listed now, before any task starts, so a file written from here on is never adopted (harness
          // design 4.2): a capture, a recovery and a URL command all write after this.
          let pendingListed = pendingFiles.list()
  ```
  and replace
  ```swift
          // A recording a crash, a kill or a failed rename left in tmp/Recording is checked, not swept.
          // The scan lists the folder first, long before a recording started now could write there.
          Task { await recoverRecordings() }
  ```
  with
  ```swift
          // A capture in pending/ that no record names is adopted, never deleted; then a recording a
          // crash, a kill or a failed rename left in tmp/Recording is checked, not swept. One task, so
          // the two never interleave. The scan lists its folder first, long before a recording started
          // now could write there.
          Task {
              await adoptPendingFiles(pendingListed)
              await recoverRecordings()
          }
  ```
- [ ] Run `CoordinatorRecoveryTests` alone, then the full suite: `2160 tests in 181 suites`.
- [ ] Hand check (Tim's, for Task 16's checklist): the design's section 8, item 2.
- [ ] Commit: `feat: adopt pending files no record names at launch`.

### Task 12: `UploadQueue.swift` splits into three files [mechanical]

**Files:** modify `TidyShot/Upload/UploadQueue.swift`; create `TidyShot/Upload/UploadQueue+Multipart.swift` and `TidyShot/Upload/UploadQueue+Parts.swift`.

A pure move (design 5.1; split design section 2): no body changes, no renames; 24 members widen from `private` to internal, exactly the design's list. `UploadQueueTests.swift` does not change.

**Steps:**
- [ ] Check the file is 6a52a7c's: `git diff --quiet 6a52a7c -- TidyShot/Upload/UploadQueue.swift && echo unchanged` prints `unchanged`. Base line ranges (verified): core 1-58, 123-276 (122 is blank), 533-548, 566-584, 604-666, 710-718; multipart 70-121, 278-418, 550-564; parts 60-68, 420-531, 586-602, 669-707, 720-762.
- [ ] Run:
  ```bash
  python3 - <<'EOF'
  import subprocess
  from pathlib import Path
  base = subprocess.run(["git", "show", "6a52a7c:TidyShot/Upload/UploadQueue.swift"],
                        capture_output=True, text=True, check=True).stdout
  assert Path("TidyShot/Upload/UploadQueue.swift").read_text() == base
  L = base.split("\n")
  def lines(a, b): return L[a - 1:b]

  def widen(text, olds):
      for old in olds:
          assert text.count(old) == 1, old
          text = text.replace(old, old.replace("private ", "", 1), 1)
      return text

  core = (lines(1, 58) + [""] + lines(123, 276) + [""] + lines(533, 548) + [""] + lines(566, 584) + [""]
          + lines(604, 666) + [""] + lines(710, 718))
  core = widen("\n".join(core) + "\n", [
      "    private let destination: any Destination",
      "    private let filePolicy: RetryPolicy",
      "    private let scope: SecurityScope",
      "    private let sleep: Sleeper",
      "    private let plan: MultipartPlan",
      "    private let now: @Sendable () -> Date",
      "    private let log: Logger",
      "    private let events: EventHandler",
      "    private var cancelledIDs: Set<UUID> = []",
      "    private var reservedKeys: [UUID: String] = [:]",
      "    private nonisolated enum JobOutcome: Sendable {",
      "    private func abortUpload(key: String, uploadID: String, name: String) async {",
      "    private nonisolated static func withRetries<T>(",
      "    private func throttledProgress(for id: UUID)",
      "    private func deliverCancelled(_ id: UUID)",
      "    private func objectKey(for job: UploadJob",
      "    private func reserveKey(ext: String",
  ])

  multipart = (["import Foundation", "",
                "// A multipart job's pass: its steps, a new upload and a resumed one. Split from UploadQueue.swift with no body changed (harness design 5.1).",
                "extension UploadQueue {"]
               + lines(70, 121) + [""] + lines(278, 418) + [""] + lines(550, 564) + ["}"])
  multipart = widen("\n".join(multipart) + "\n", [
      "    private nonisolated struct Restart: Error {",
      "    private nonisolated struct MultipartTarget: Sendable {",
      "    private nonisolated struct MultipartPass: Sendable {",
      "    private func processMultipart(_ job: UploadJob",
  ])

  parts = (["import Foundation", "import Synchronization", "",
            "// A multipart job's parts: the part list, the parts in flight, Complete, and the part reads and progress. Split from UploadQueue.swift with no body changed (harness design 5.1).",
            "extension UploadQueue {"]
           + lines(60, 68) + [""] + lines(420, 531) + [""] + lines(586, 602) + [""] + lines(669, 707) + ["}", ""]
           + lines(720, 762))
  parts = widen("\n".join(parts) + "\n", [
      "    private func partList(of target: MultipartTarget",
      "    private func sendParts(_ numbers: [Int]",
      "    private func complete(_ target: MultipartTarget",
  ])

  Path("TidyShot/Upload/UploadQueue.swift").write_text(core)
  Path("TidyShot/Upload/UploadQueue+Multipart.swift").write_text(multipart)
  Path("TidyShot/Upload/UploadQueue+Parts.swift").write_text(parts)
  EOF
  ```
- [ ] The pure-move check prints `pure move`, and the access count falls from 48 to 24:
  ```bash
  norm() { grep -vE '^(import |extension UploadQueue \{$|\}$|(    )?// )' | sed -E 's/(^|[[:space:]])private /\1/' | grep -v '^[[:space:]]*$' | sort; }
  diff <(git show 6a52a7c:TidyShot/Upload/UploadQueue.swift | norm) <(cat TidyShot/Upload/UploadQueue*.swift | norm) && echo "pure move"
  git show 6a52a7c:TidyShot/Upload/UploadQueue.swift | grep -cE '(^|[[:space:]])private '
  cat TidyShot/Upload/UploadQueue*.swift | grep -cE '(^|[[:space:]])private '
  wc -l TidyShot/Upload/UploadQueue*.swift
  ```
  expects `pure move`, `48`, `24`, and the three files at 324 (`UploadQueue.swift`), 215 (`+Multipart`) and 230 (`+Parts`) lines.
- [ ] Run the full suite: `2160 tests in 181 suites`. `git diff --stat -- TidyShotTests` prints nothing.
- [ ] Commit: `refactor: split UploadQueue into three files`.

### Task 13: An Abort that finds nothing is logged as such [integration]

**Files:**
- Modify `TidyShot/Upload/UploadQueue.swift` (`abortUpload`), `TidyShot/App/AppCoordinator+Delete.swift` (`abortUploads`).
- Tests: two in `UploadQueueTests`, test 39 in `CoordinatorDeleteTests`.

**Steps:**
- [ ] Write the tests and see them fail. In `UploadQueueTests`, after `aSinglePutJobAbortsOnceAcrossItsRetries`:
  ```swift

      /// A stored upload already gone (an Abort's 404) is logged as such, not as aborted (harness design 5.2).
      @Test func aSinglePutJobsAbortThatFindsNothingIsLoggedAsGone() async throws {
          let movie = try makeMovie()
          defer { try? FileManager.default.removeItem(at: movie.folder) }
          let id = UUID()
          let destination = FakeDestination(.init(abortResult: .notFound))
          let log = EventLog()
          let lines = LogLines()
          let queue = makeMultipartQueue(destination: destination, log: log, store: MultipartStore(directory: movie.folder),
                                         lines: lines)
          var job = largeJob(id, file: movie.file, byteCount: 3)
          job.abortFirst = MultipartRef(uploadID: "old-1", key: "s/OLD.mp4", location: lane)

          await queue.enqueue(job)
          try await eventually { hasEnded(log) }

          #expect(log.events.contains(.uploaded(id: id, url: templateURL, key: templateKey)))
          #expect(destination.state.withLock { $0.aborts.map(\.uploadID) } == ["old-1"])
          #expect(logged(lines) == ["multipart upload already gone"])
      }

      @Test func aMultipartJobsAbortThatFindsNothingIsLoggedAsGone() async throws {
          let movie = try makeLargeMovie(byteCount: mib)
          defer { try? FileManager.default.removeItem(at: movie.folder) }
          let id = UUID()
          let destination = FakeDestination(.init(abortResult: .notFound))
          let log = EventLog()
          let lines = LogLines()
          let queue = makeMultipartQueue(destination: destination, log: log, store: movie.store, lines: lines)
          var job = largeJob(id, file: movie.file, byteCount: mib)
          job.abortFirst = MultipartRef(uploadID: "old-1", key: "s/OLD.mp4", location: lane)

          await queue.enqueue(job)
          try await eventually { hasEnded(log) }

          #expect(log.events.contains(.uploaded(id: id, url: templateURL, key: templateKey)))
          #expect(logged(lines) == ["multipart upload already gone", created("upload-1"), "multipart completed"])
      }
  ```
  In `CoordinatorDeleteTests`, after `anAbortThatAnswers204IsSentAgain`:
  ```swift

      /// 39 (harness design 3.3 and 5.2). An Abort that answers 404 is not sent again, counts as done, and is
      /// logged as gone.
      @Test func anAbortThatFindsNothingIsNotRepeatedAndLogsItGone() async {
          defer { world.removeAll() }
          destination.state.withLock { $0.abortResult = .notFound }
          let coordinator = world.makeCoordinator()

          let reason = await coordinator.abortUploads([ref(at: world.location)], name: "Recording.mp4")

          #expect(reason == nil)
          #expect(destination.state.withLock { $0.aborts.count } == 1)
          #expect(world.logLines == ["Upload: Recording.mp4 multipart upload already gone"])
      }
  ```
- [ ] `UploadQueue.abortUpload` becomes:
  ```swift
      /// Aborts an upload the job no longer uses, in one try. A 404 means nothing was left, and is logged
      /// as such. A failure is logged and the job goes on; the bucket's lifecycle rule removes what is left.
      func abortUpload(key: String, uploadID: String, name: String) async {
          do {
              switch try await destination.abortMultipartUpload(key: key, uploadID: uploadID) {
              case .aborted: log("Upload: \(name) multipart aborted")
              case .notFound: log("Upload: \(name) multipart upload already gone")
              }
          } catch {
              guard !Task.isCancelled else { return }
              log("Upload: \(name) multipart abort failed: \(error.localizedDescription)")
          }
      }
  ```
- [ ] In `abortUploads`, the `do` block
  ```swift
                  if try await destination.abortMultipartUpload(key: ref.key, uploadID: ref.uploadID) == .aborted {
                      _ = try await destination.abortMultipartUpload(key: ref.key, uploadID: ref.uploadID)
                  }
                  log("Upload: \(name) multipart aborted")
  ```
  becomes
  ```swift
                  if try await destination.abortMultipartUpload(key: ref.key, uploadID: ref.uploadID) == .aborted {
                      _ = try await destination.abortMultipartUpload(key: ref.key, uploadID: ref.uploadID)
                      log("Upload: \(name) multipart aborted")
                  } else {
                      log("Upload: \(name) multipart upload already gone")
                  }
  ```
- [ ] Run `UploadQueueTests` and `CoordinatorDeleteTests` alone, then the full suite: `2163 tests in 181 suites`.
- [ ] Commit: `fix: log an abort that found nothing as already gone`.

### Task 14: A cancel during a stored upload's abort [mechanical]

**Files:** tests only, in `TidyShotTests/UploadQueueTests.swift`. Uses Task 4's `blockingAbortsRemaining` and `holdingAbortsRemaining`.

**Steps:**
- [ ] After Task 13's two tests, add (design 5.3):
  ```swift

      /// A cancel that lands while a single PUT's stored upload is being aborted ends the job with one
      /// `.cancelled` and nothing else: no `.started`, no upload, and no log line, as a cancelled Abort
      /// logs nothing (harness design 5.3).
      @Test func aCancelDuringTheSinglePutAbortDeliversCancelled() async throws {
          let movie = try makeMovie()
          defer { try? FileManager.default.removeItem(at: movie.folder) }
          let id = UUID()
          let destination = FakeDestination(.init(blockingAbortsRemaining: 1))
          let log = EventLog()
          let lines = LogLines()
          let queue = makeMultipartQueue(destination: destination, log: log, store: MultipartStore(directory: movie.folder),
                                         lines: lines)
          var job = largeJob(id, file: movie.file, byteCount: 3)
          job.abortFirst = MultipartRef(uploadID: "old-1", key: "s/OLD.mp4", location: lane)

          await queue.enqueue(job)
          try await eventually { destination.state.withLock { $0.calls } == ["abort"] }

          #expect(await queue.cancel(recordID: id) == .stopped(reservedKey: nil))
          #expect(log.events == [.cancelled(id: id, reservedKey: nil)])
          #expect(destination.state.withLock { $0.uploadAttempts } == 0)
          #expect(destination.state.withLock { $0.creates.isEmpty })
          #expect(logged(lines).isEmpty)
          try await eventually { await queue.isIdle }
      }

      /// An Abort that answers after the cancel is logged, and the job still ends cancelled.
      @Test func anAbortThatAnswersAfterTheSinglePutsCancelIsLoggedAndTheJobCancels() async throws {
          let movie = try makeMovie()
          defer { try? FileManager.default.removeItem(at: movie.folder) }
          let id = UUID()
          let destination = FakeDestination(.init(holdingAbortsRemaining: 1))
          let log = EventLog()
          let lines = LogLines()
          let queue = makeMultipartQueue(destination: destination, log: log, store: MultipartStore(directory: movie.folder),
                                         lines: lines)
          var job = largeJob(id, file: movie.file, byteCount: 3)
          job.abortFirst = MultipartRef(uploadID: "old-1", key: "s/OLD.mp4", location: lane)

          await queue.enqueue(job)
          try await eventually { destination.state.withLock { $0.calls } == ["abort"] }
          let cancel = Task { await queue.cancel(recordID: id) }
          try await eventually { destination.state.withLock { $0.heldAbortCancellations } == 1 }
          destination.releaseAborts()

          #expect(await cancel.value == .stopped(reservedKey: nil))
          #expect(log.events == [.cancelled(id: id, reservedKey: nil)])
          #expect(destination.state.withLock { $0.uploadAttempts } == 0)
          #expect(logged(lines) == ["multipart aborted"])
      }

      /// The multipart path's equivalent: `.started` went before the abort, and `.cancelled` follows it.
      @Test func aCancelDuringTheMultipartAbortDeliversCancelled() async throws {
          let movie = try makeLargeMovie(byteCount: mib)
          defer { try? FileManager.default.removeItem(at: movie.folder) }
          let id = UUID()
          let destination = FakeDestination(.init(blockingAbortsRemaining: 1))
          let log = EventLog()
          let lines = LogLines()
          let queue = makeMultipartQueue(destination: destination, log: log, store: movie.store, lines: lines)
          var job = largeJob(id, file: movie.file, byteCount: mib)
          job.abortFirst = MultipartRef(uploadID: "old-1", key: "s/OLD.mp4", location: lane)

          await queue.enqueue(job)
          try await eventually { destination.state.withLock { $0.calls } == ["abort"] }

          #expect(await queue.cancel(recordID: id) == .stopped(reservedKey: nil))
          #expect(log.events == [.started(id: id, attempt: 1, fraction: 0), .cancelled(id: id, reservedKey: nil)])
          #expect(destination.state.withLock { $0.creates.isEmpty })
          #expect(logged(lines).isEmpty)
          try await eventually { await queue.isIdle }
      }

      @Test func anAbortThatAnswersAfterTheMultipartCancelIsLoggedAndTheJobCancels() async throws {
          let movie = try makeLargeMovie(byteCount: mib)
          defer { try? FileManager.default.removeItem(at: movie.folder) }
          let id = UUID()
          let destination = FakeDestination(.init(holdingAbortsRemaining: 1))
          let log = EventLog()
          let lines = LogLines()
          let queue = makeMultipartQueue(destination: destination, log: log, store: movie.store, lines: lines)
          var job = largeJob(id, file: movie.file, byteCount: mib)
          job.abortFirst = MultipartRef(uploadID: "old-1", key: "s/OLD.mp4", location: lane)

          await queue.enqueue(job)
          try await eventually { destination.state.withLock { $0.calls } == ["abort"] }
          let cancel = Task { await queue.cancel(recordID: id) }
          try await eventually { destination.state.withLock { $0.heldAbortCancellations } == 1 }
          destination.releaseAborts()

          #expect(await cancel.value == .stopped(reservedKey: nil))
          #expect(log.events == [.started(id: id, attempt: 1, fraction: 0), .cancelled(id: id, reservedKey: nil)])
          #expect(destination.state.withLock { $0.creates.isEmpty })
          #expect(logged(lines) == ["multipart aborted"])
      }
  ```
- [ ] Run `UploadQueueTests` alone (they pass: the code is 6b4f553's), then the full suite: `2167 tests in 181 suites`.
- [ ] Commit: `test: a cancel during a stored upload's abort`.

### Task 15: The queue's two findings, `PartSender`'s lets, and `MultipartStore`'s log line [integration]

**Files:**
- Modify `TidyShot/Upload/UploadQueue+Parts.swift` (`PartSender`), `TidyShot/Upload/UploadQueue+Multipart.swift` (`createUpload`), `TidyShot/Upload/MultipartStore.swift` (:113).
- Tests: two in `UploadQueueTests`, and `aSidecarUnwritableAtCreateFailsTheJob`'s `calls` expectation.

**Steps:**
- [ ] Write the tests and see them fail. After Task 14's tests:
  ```swift

      /// A part the loop adds after a cancel, because the part before it finished at that moment, reads
      /// and sends nothing: `PartSender.send` checks for the cancel first (harness design 5.4). One part
      /// at a time, part 1 held through the cancel and then answering.
      @Test func aPartAddedAfterACancelSendsNothing() async throws {
          let movie = try makeLargeMovie(byteCount: mib)
          defer { try? FileManager.default.removeItem(at: movie.folder) }
          let destination = FakeDestination(.init(holdingPart: 1))
          let log = EventLog()
          let queue = makeMultipartQueue(destination: destination, log: log, store: movie.store,
                                         plan: MultipartPlan(threshold: 1_048_576, partSize: 262_144, inFlight: 1))
          let id = UUID()

          await queue.enqueue(largeJob(id, file: movie.file, byteCount: mib))
          try await eventually { destination.state.withLock { $0.calls }.contains("part 1") }
          let cancel = Task { await queue.cancel(recordID: id) }
          try await eventually { destination.state.withLock { $0.heldPartCancellations } == 1 }
          destination.releaseParts()

          #expect(await cancel.value == .stopped(reservedKey: templateKey))
          #expect(destination.state.withLock { $0.calls }.filter { $0.hasPrefix("part") } == ["part 1"])
          #expect(log.events.last == .cancelled(id: id, reservedKey: templateKey))
          #expect(destination.state.withLock { $0.completes.isEmpty })
          try await eventually { await queue.isIdle }
      }

      /// A new upload whose first sidecar cannot be written is aborted at once, best effort, so its id is
      /// not left to the lifecycle rule; the job fails with the write's error (harness design 5.4).
      @Test func aNewUploadWhoseFirstSidecarCannotBeWrittenIsAborted() async throws {
          let movie = try makeLargeMovie(byteCount: mib)
          defer { try? FileManager.default.removeItem(at: movie.folder) }
          let store = movie.store
          let destination = FakeDestination(.init(onCall: { call in
              if call == "create" { Self.blockSidecarWrites(in: store) }
          }))
          let log = EventLog()
          let lines = LogLines()
          let queue = makeMultipartQueue(destination: destination, log: log, store: store, lines: lines)
          let id = UUID()

          await queue.enqueue(largeJob(id, file: movie.file, byteCount: mib))
          try await eventually { hasEnded(log) }

          #expect(destination.state.withLock { $0.calls } == ["create", "abort"])
          #expect(destination.state.withLock { $0.aborts.map(\.uploadID) } == ["upload-1"])
          #expect(destination.state.withLock { $0.aborts.map(\.key) } == [templateKey])
          #expect(failures(in: log).count == 1)
          #expect(logged(lines) == ["multipart aborted"])
      }
  ```
  and in `aSidecarUnwritableAtCreateFailsTheJob`, `#expect(destination.state.withLock { $0.calls } == ["create"])` becomes `#expect(destination.state.withLock { $0.calls } == ["create", "abort"])`.
- [ ] `PartSender` in `UploadQueue+Parts.swift`: each of its thirteen stored properties `var` becomes `let` (`destination`, `policy`, `sleep`, `log`, `name`, `file`, `key`, `uploadID`, `partSize`, `byteCount`, `count`, `progress`, `report`); nothing mutates them, and the memberwise initializer `sendParts` calls is the same. In `send(_:)`, the first line inside `do {` is new:
  ```swift
              do {
                  // A part the loop adds after a cancel reads and sends nothing (harness design 5.4).
                  try Task.checkCancellation()
                  let range = MultipartPlan.range(ofPart: number, partSize: partSize, byteCount: byteCount)
  ```
- [ ] `createUpload` in `UploadQueue+Multipart.swift`: `        try pass.store.writeSidecar(sidecar, id: job.id)` (the one right after `var sidecar = MultipartSidecar(uploadID: uploadID, completeSent: false, parts: [])`) becomes:
  ```swift
          do {
              try pass.store.writeSidecar(sidecar, id: job.id)
          } catch {
              // The new upload id is stored nowhere yet: abort it now, best effort, rather than leave it to
              // the bucket's lifecycle rule (harness design 5.4).
              await abortUpload(key: key, uploadID: uploadID, name: pass.name)
              throw error
          }
  ```
- [ ] `MultipartStore.swift` (:113): `NSLog("Could not remove \(url.lastPathComponent) from the multipart folder: \(error.localizedDescription)")` becomes `NSLog("%@", "Could not remove \(url.lastPathComponent) from the multipart folder: \(error.localizedDescription)")`.
- [ ] Run `UploadQueueTests` alone, then the full suite: `2169 tests in 181 suites`.
- [ ] Commit: `fix: a part added after a cancel sends nothing; abort an upload whose sidecar cannot be written`.

### Task 16: Checklist and design close-out [mechanical]

**Files:**
- Create `docs/testing/coordinator-harness-manual-checklist.md`.
- Modify `docs/testing/recording-r4-manual-checklist.md` (the `(suite)` marks), `README.md` (:386, the recovery sentence), `docs/superpowers/specs/2026-10-29-tidyshot-coordinator-harness-design.md` (the lines of 2.1, 2.2, 3.2, 3.3, 4.2 and 8 the build departs from, and a `## 11. Built notes` section at the end).

**Steps:**
- [ ] Grep the finished code for every new string (`multipart upload already gone`, `Recovery: `, `Recovered a capture`, `Recovered a recording`, `is empty, removed`, `could not be read, removed`) and fix any drift from Global Constraints.
- [ ] The coordinator split's surface check: `grep -rnE "coordinator\.|AppCoordinator\.shared\." TidyShot --include='*.swift' | grep -v 'TidyShot/App/AppCoordinator' | grep -oE "coordinator\.[a-zA-Z]+|shared\.[a-zA-Z]+" | sort -u` lists nothing new beyond the split design's 3.5 surface and R4's `startRecording`/`stopRecordingCommand` (`environment`, `clipboard`, `log`, `adoptPendingFiles` are reached from no file outside the coordinator's family). In zsh, quote the glob or run it in bash.
- [ ] Write `docs/testing/coordinator-harness-manual-checklist.md`:
  ```markdown
  # Coordinator harness manual checklist

  Run after the coordinator harness phase (`docs/superpowers/specs/2026-10-29-tidyshot-coordinator-harness-design.md`),
  and after any later change to `AppEnvironment`, the three protocols (`Notifying`, `QuickAccessCards`,
  `Clipboard`), `AppCoordinator+Recovery.swift` or `PendingFileStore.list`. The suite now builds an
  `AppCoordinator` over temp folders and fakes and covers the R4 lines the R4 checklist marks `(suite)`; what is
  left here needs the real app: the live environment, the container's `pending/` folder, a URL command, and the log.

  Read the log with
  `/usr/bin/log show --last 10m --style compact --predicate 'process == "TidyShot"' | grep -E "Recovery:|Recording:|Upload:"`.

  ## Checks

  - [ ] 1. The live world is unchanged. Launch a Release build; take a screenshot (⌃⇧4), let it upload, record a
    short area and let it upload: the cards, the notifications, the clipboard (the link replaces it), the shutter
    sound and the log read as before. Delete one of them with `Ask before deleting` on: the alert is the same.
  - [ ] 2. `pending/` adoption. Quit TidyShot. Copy any PNG into
    `~/Library/Containers/io.tky.tidyshot/Data/Library/Application Support/TidyShot/pending/` as `<a new UUID>.png`
    (`uuidgen` gives one; keep it upper case). Launch: `Recovered a capture` posts with the file's name, the row is
    in Recent Captures with the image's size, the log says `Recovery: <name> recovered`, Annotate opens it, and
    Delete removes the row and the file. Repeat with a short MP4 as `<UUID>.mp4`: `Recovered a recording` with its
    length (`m:ss`). A zero-byte `<UUID>.png` is removed at launch with `Recovery: <name> is empty, removed`; a file
    named `notes.png` is left alone.
  - [ ] 3. A `record-screen` URL still starts a selection, and `urlRecordingStartPending` clears: send
    `open 'tidyshot://record-screen'`, press Escape, then send it again: a second selection shows. (Test 53 covers
    every refusal; the successful start reaches ScreenCaptureKit.)
  - [ ] 4. `stop-recording`'s log lines in each phase (R4 checklist :178-186) read as they did: the suite pins the
    state, not the `RecordingLog` text, and tests 48 and 50 cannot tell the coordinator's own do-nothing branches from
    the recorder's (plan D24), so the `did nothing` lines are the check.

  ## The design's calls, to confirm or overrule

  The design lists them in section 9. Write `confirm` or `overrule` and why; an overrule goes in its built notes.
  - [ ] 1. `AppEnvironment` as one struct with `.live()` and `init(environment:)`; `shared` unchanged. ______
  - [ ] 2. `Notifying`, `QuickAccessCards`, `Clipboard` and `DeleteConfirmation`; the live types conform unchanged. ______
  - [ ] 3. `Destination` gains the two downloads; the coordinator's upload signatures carry the location and the key
    template with the destination. ______
  - [ ] 4. Every coordinator log line through the environment, live `NSLog("%@", …)`; `RecordingLog.note` stays. ______
  - [ ] 5. No `private` member opened for tests; `record()` not driven; `recordingProceeds` extracted. ______
  - [ ] 6. The fifty-six tests are this phase's set; the rest of the catalogue waits. ______
  - [ ] 7. `pending/` orphans adopted, never deleted; by record id; listed in `start()` before any task; one task,
    `pending/` first. ______
  - [ ] 8. An adopted image or recording gets `.none` and `fileIsTemporary`. ______
  - [ ] 9. The three-file queue split with 24 widenings. ______
  - [ ] 10. `multipart upload already gone` for a 404. ______
  - [ ] 11. `PartSender.send` checks for a cancel first; `createUpload` aborts the fresh id when the first sidecar
    write fails. ______
  - [ ] 12. The 33 interpolating `NSLog` lines outside the coordinator stay. ______

  ## The plan's decisions, to confirm or overrule

  The plan lists them at its end (`docs/superpowers/plans/2026-10-29-coordinator-harness.md`, Plan decisions). Most
  are internal; these change what a user could see or what Tim decided before:
  - [ ] D11. A GIF in `pending/` is read with ImageIO, not `VideoValidation` (which would find every GIF unplayable
    and remove it); an empty file logs `is empty, removed`. ______
  - [ ] D12. Test 46 pins that pruning closes no card (the design's line said it does; the code never did). Ruled
    before Task 7; write the ruling here. ______
  - [ ] D14. Test 27 follows the code's titles: `Upload failed` with the error for a capture with no link, `Not
    uploaded` with the replace's text for one with a link. ______

  ## Observations
  Write into the design's built notes: anything above that failed, and each call and decision confirmed or overruled.
  ```
- [ ] Mark the R4 checklist items the suite now covers by appending ` (suite: <tests>)` at the end of the item's last line, before any `______`. Each mark names the tests, and "in part" where the item also needs the real bucket, CloudFront, `footprint`, Wi-Fi, the AWS console, Clop, a drag session or a window. The design's section 8 names lines 224-227, 230-263, 271-291 and the calls A to H (A to F once this task's design correction lands: G and H stay with Tim); every item in them is listed here, marked or not covered:
  - Multipart, `The ring moves. …` (:224-227) → `(suite, in part: UploadQueueTests.theStateIsDeliveredFirstAndTheSidecarFollowsEachPart, .aTemplateKeyIsReservedOncePerUploadID, CoordinatorUploadTests.anUploadedResumeClearsItsStateSidecarAndKeptCopy)`
  - Multipart, `Wi-Fi off for 30 seconds mid-upload: …` → `(suite, in part: UploadQueueTests.aFailingPartRetriesAloneWhileTheOthersFinish)`
  - Multipart, `Wi-Fi off for two minutes: …` → `(suite, in part: CoordinatorUploadTests.aStoredUploadWhoseSourceMatchesResumes, .aResumesStartSetsTheBarAtItsDoneFraction)`
  - Multipart, `Quit mid-upload and relaunch: …` → `(suite, in part: HistoryStoreTests.interruptedMultipartUploadKeepsItsStateOnLoad, CoordinatorUploadTests.aStoredUploadWhoseSourceMatchesResumes)`
  - Multipart, `Delete mid-upload aborts it …` → `(suite, in part: UploadQueueTests.aCancelDuringThePartsWaitsForEveryPart, CoordinatorDeleteTests.eachUploadIsAbortedWhereItWasCreated)`
  - Multipart, `Delete of a failed multipart upload aborts it; …` → `(suite: CoordinatorDeleteTests.anAbortThatAnswers204IsSentAgain, CaptureDeletionTests)`
  - Multipart, `Remove \`s3:AbortMultipartUpload\` from the key …` → `(suite, in part: CoordinatorDeleteTests.anAbortFailureAsksToRemoveFromHistory)`
  - Multipart, `Retry a failed multipart upload after Settings > Upload names another bucket: …` → `(suite, in part: CoordinatorUploadTests.aStoredUploadAtAnotherLocationIsAbortedThereAndStartsAgain)`
  - Multipart, `Retry after the recording's file changed …` → `(suite: CoordinatorUploadTests.aSourceWhoseSizeChangedStartsAgainAbortingFirst)`
  - Multipart, `A start over whose new file is under 100 MiB …` → `(suite: UploadQueueTests.aSinglePutJobWithAnUploadToAbortAbortsItFirst)`
  - Multipart, `\`Upload Trimmed\` on a 300 MB trimmed file …` → `(suite, in part: CoordinatorUploadTests.aFailedUploadMarksTheRecordOrReturnsItToItsLink, MultipartPlanTests.resumesWhenEverythingMatches)`
  - Multipart, `Clop on, \`Upload Trimmed\` on a trimmed file over 100 MiB …` → `(suite, in part: CoordinatorUploadTests.anOutdatedKeptClopCopyCountsAsAChangedSource)`
  - Multipart, `A Clop result kept in \`multipart/<id>.mp4\` …` → `(suite, in part: CoordinatorUploadTests.anUploadedResumeClearsItsStateSidecarAndKeptCopy)`
  - Multipart, `Pruning removes the sidecar and the kept copy and aborts nothing. …` → `(suite: CoordinatorDeleteTests.pruningRemovesTheFilesAndAsksForNoDestination)`
  - Multipart, `The files in \`multipart/\` of a record with no state, …` → `(suite, in part: MultipartStoreTests.sweepRemovalsDropsNoStateAndStatesOlderThanSevenDays, .sweepLeavesAFileNotNamedByAnID)`
  - Drag-out, `A drag of the card shows \`Downloading…\` …` → `(suite, in part: CoordinatorDragOutTests.aDragOfAShowingUploadedRecordingStartsOneDownload, .aDownloadThatLandsIsAdoptedAndHandedToTheCard)`
  - Drag-out, `Close during the download cancels it: …` → `(suite: CoordinatorDragOutTests.aCloseDuringTheTransferDropsWhatLands)`
  - Drag-out, `Delete during the download cancels it and removes the folder.` → `(suite: CoordinatorDragOutTests.deleteCancelsARunningDownloadAndRemovesTheFolder)`
  - Drag-out, `The row in Recent Captures reads \`Downloading\` …` → `(suite, in part: RecentCaptureFormattingTests.detailSaysDownloadingWhileADragDownloadRuns)`
  - Drag-out, `Wi-Fi off during the download shows \`Download failed\` …` → `(suite, in part: CoordinatorDragOutTests.aFailureWithResumeDataKeepsItWithTheSigningTime, .aDragWithinTheWindowResumesFromTheKeptData, .aDragPastTheWindowStartsAgainAndRemovesThePartialFile)`
  - Drag-out, `A recording marked \`Sound not muted\` starts no download on a drag.` → `(suite: DragDownloadRuleTests.startsForNothingElse)`
  - Drag-out, `A disk-check refusal shows \`Download failed\` …` → `(suite: CoordinatorDragOutTests.tooLittleFreeSpaceRefusesTheDownload)`
  - Drag-out, `A GIF with no local file downloads too.` → `(suite, in part: DragDownloadRuleTests.startsForAnUploadedVideoOrGIFWithNoLocalFile)`
  - Drag-out, `After the card closes, the 60 s clean-up …` → `(suite, in part: DragCleanupTests.aCardShowingTheRecordLeavesTheFolder, .noCopyFileRemovesTheFolder)`
  - Calls, `A. A multipart sidecar that cannot be written fails the job …` → `(suite: UploadQueueTests.aSidecarUnwritableAtCreateFailsTheJob, .aSidecarUnwritableDuringThePartsFailsTheJobBeforeComplete, .aNewUploadWhoseFirstSidecarCannotBeWrittenIsAborted)`
  - Calls, `B. A kept Clop copy outdated by a later trim …` → `(suite: CoordinatorUploadTests.anOutdatedKeptClopCopyCountsAsAChangedSource)`
  - Calls, `C. A start over whose new file is under 100 MiB …` → `(suite: UploadQueueTests.aSinglePutJobWithAnUploadToAbortAbortsItFirst)`
  - Calls, `D. A second \`partsRejected\` in a job restarts …` → `(suite: UploadQueueTests.aSecondRejectedPartListRestarts)`
  - Calls, `E. A resume sends no \`.started\` until it knows its done fraction.` → `(suite: CoordinatorUploadTests.aResumesStartSetsTheBarAtItsDoneFraction, UploadQueueTests.aResumeSendsOnlyTheMissingParts)`
  - Calls, `F. Every abort of a start over or a restart is one try, …` → `(suite: UploadQueueTests.aJobWithAnUploadToAbortAbortsItBeforeItsCreate, .aSinglePutJobAbortsOnceAcrossItsRetries, .aSecondRejectedPartListRestarts)`
  - Settings prompt, `The record shortcut during the settle delay …` (:217, outside section 8's ranges; D20) → `(suite, the rule: CoordinatorRecordingTests.recordingProceedsOnlyWhenStartedNotQuittingAndNotCancelled)`

  Not covered, so left unmarked: Drag-out `A drag held through a short download starts the session …` (the drag session), `A click on the thumbnail opens the link …` (the card's click and Restore Closed Overlay), `Save As… during the download waits …` (the Save As panel, Deferred), `A downloaded drag copy is not a local file: …` (Copy File and Trim, Deferred); Calls `G. Delete's second Abort failing fails Delete …` (the second Abort must fail after a first that answered 204, and `FakeDestination`'s `abortFailures` fail from the first call on; a per-call script is not added) and `H. Part reads retry from the same bytes …` (`readPart` has no counter, D18); the design's section 8 is corrected below to say both stay with Tim. The `[x]` lifecycle line (:264) stays as it is.
- [ ] `README.md` (:386): after `the next launch keeps it with *Recovered a recording*.` add ` A screenshot or recording TidyShot keeps in its own folder that a crash left without its row in Recent Captures comes back the same way, with *Recovered a capture* or *Recovered a recording*.`
- [ ] Correct the design's lines that the built code and tests depart from, so a reader of sections 2 to 4 and 8 sees what was built (D1, D4, D11 to D15, Deferred's `ProcessInfo`, and the calls G and H). Each old string is the design's at 48b7cde; the script stops if one is not found once. If Tim overruled D12 (Task 7's gate), drop the test 46 pair, since the card then closes as the design says.
  ```bash
  python3 - <<'EOF'
  from pathlib import Path
  design = Path("docs/superpowers/specs/2026-10-29-tidyshot-coordinator-harness-design.md")
  text = design.read_text()
  fixes = [
      # 2.1: the two members the plan added (D4).
      ("| `makeDestination` | `@Sendable (S3DestinationConfig, AWSCredentials) -> any Destination` | `S3Destination(config:credentials:)` at five sites | the same |\n",
       "| `makeDestination` | `@Sendable (S3DestinationConfig, AWSCredentials) -> any Destination` | `S3Destination(config:credentials:)` at five sites | the same |\n"
       "| `multipartPlan` | `MultipartPlan` | `UploadQueue`'s default `plan` in `makeLane` | `.standard` |\n"
       "| `uploadSleep` | `UploadQueue.Sleeper` | `UploadQueue`'s default `sleep` (the lane's backoff) | `{ try await Task.sleep(for: $0) }` |\n"),
      # 2.2: `Notifier.notifyError` takes `revealing:` (D1).
      ("`notifyError(_:title:subtitle:openURL:)`", "`notifyError(_:title:subtitle:revealing:)`"),
      # 3.2 test 19: a part's retry sends no `.started` (D15).
      ("(the fake fails the first part once, `RetryPolicy` with one retry, `sleep` injected)",
       "(a screenshot's single PUT that the fake fails once, `RetryPolicy` with one retry, `sleep` injected)"),
      # 3.2 test 20: a 204 is repeated (D13).
      ("that destination got one `abort`,", "that destination got two `abort`s (a 204 is repeated, test 38),"),
      # 3.2 test 27: the titles were crossed (D14).
      ("marks the record `.failed(message)` and posts `Not uploaded`; with a `priorUpload` the record returns to the earlier link, `uploadIsStale` stays, and the notice reads `Upload failed. The link still shows the earlier image.`",
       "marks the record `.failed(message)` and posts `Upload failed` with the error; with a `priorUpload` the record returns to the earlier link, `uploadIsStale` stays, and the notice is `Not uploaded` with `Upload failed. The link still shows the earlier image.`"),
      # 3.3 test 46: pruning closes no card (D12, as Tim ruled).
      ("closes the card with `.deleted` and asks the factory for no destination.",
       "closes no card (the code never did; D12) and asks the factory for no destination."),
      # 4.2: a GIF is read with ImageIO, and every recovery line is named (D11).
      ("  - A `.mp4` or `.gif`: `VideoValidation.inspect` as `recoverRecordings` uses it;",
       "  - A `.gif`: read with ImageIO (its size, first frame and the sum of its frames' delays as `durationSeconds`), since AVFoundation does not open a GIF and `VideoValidation` would find every one unplayable; the record `recoverRecordings` builds, with `mediaKind: .gif`; `history.add`; the first frame as its thumbnail. One that does not decode is removed and logged the same way.\n"
       "  - A `.mp4`: `VideoValidation.inspect` as `recoverRecordings` uses it;"),
      ("  - A zero-byte file of any kind is removed.\n",
       "  - A zero-byte file of any kind is removed and logged `Recovery: <name> is empty, removed`. A removal that fails logs `Recovery: <name> <reason>, and could not be removed: <error>` (`<reason>` is `is empty` or `could not be read`) and leaves the file.\n"),
      # 4.2: tmp/Recording is scanned at launch, before adopting (D27).
      ("- **Order at launch.** `start()` runs `Task { await adoptPendingFiles(listed); await recoverRecordings() }`: one task, `pending/` first, so the two recoveries never interleave and a recovery of `tmp/Recording` never sees a half-adopted file. Nothing else in `start()` moves.",
       "- **Order at launch.** `start()` runs one task: `RecordingRecovery.begin` (list `tmp/Mute`, scan `tmp/Recording`) first, at launch as before, then `adoptPendingFiles(listed)`, then `recoverRecordings(begun)` with the scan's result. The two recoveries never interleave, and `pending/` is adopted before any scanned file moves into it or is checked against the records. The scan runs at launch, before adopting, because adopting reads each orphan off the main actor and can take seconds while shortcuts are already registered: a scan that ran after it would list a recording started in that window and remove it as unplayable mid-write (D27). Nothing else in `start()` moves."),
      # 8: the suite covers the calls A to F; G and H stay with Tim.
      ("lines 224-227, 230-263, 271-291 and the calls A to H, except the real bucket, CloudFront, `footprint`, the Wi-Fi toggle, the AWS console and the Clop run.",
       "lines 224-227, 230-263, 271-291 and the calls A to F, except the real bucket, CloudFront, `footprint`, the Wi-Fi toggle, the AWS console and the Clop run. The calls G and H stay with Tim: G's second Abort must fail after a first that answered 204, which needs a per-call `FakeDestination` script the harness does not add, and H's rereads need a read counter `readPart` does not have."),
      # 10: the activity the harness cannot keep out (2.1 says Deferred lists it).
      ("Clop's optimiser, the `tmp/` directory statics. Rules",
       "Clop's optimiser, the `tmp/` directory statics, and `ProcessInfo` activities (a test's recording upload takes the real `Uploading a recording` activity while `fileUploadIDs` is not empty). Rules"),
  ]
  for old, new in fixes:
      assert text.count(old) == 1, old
      text = text.replace(old, new, 1)
  design.write_text(text)
  print("design corrected")
  EOF
  ```
- [ ] At the end of the design, add `## 11. Built notes`:
  ```markdown
  ## 11. Built notes

  Built on `coordinator-harness` from the plan `docs/superpowers/plans/2026-10-29-coordinator-harness.md`. The suite
  reads `2169 tests in 181 suites` (R4's 2090 in 174, plus `CoordinatorWorldTests` 1, `CoordinatorDragOutTests` 16,
  `CoordinatorUploadTests` 18, `CoordinatorDeleteTests` 13, `CoordinatorRecordingTests` 9, `PendingRecoveryTests` 5,
  `CoordinatorRecoveryTests` 7, two in `PendingFileStoreTests` and eight in `UploadQueueTests`); write the last
  run's line here if it differs.

  What was built differently from this design, each with its reason, is the plan's "Plan decisions" list,
  numbered D1 to D27; Tim's checklist (`docs/testing/coordinator-harness-manual-checklist.md`) asks him to confirm
  the three a user could see (D11, D12, D14). Sections 2.1, 2.2, 3.2 (tests 19, 20, 27), 3.3 (test 46), 4.2 and 8
  above now read as built; what they said before:
  - 2.1 had no `multipartPlan` or `uploadSleep` rows (D4: the lanes' plan and backoff, so test 19's retry does not wait).
  - 2.2 gave `notifyError(_:title:subtitle:openURL:)`; `Notifier.notifyError` takes `revealing:` (D1).
  - Test 19 failed the first part once; a part's retry sends no `.started`, so it is a single PUT's (D15).
  - Test 20 said one `abort`; `abortUploads` repeats a 204 (D13, test 38).
  - Test 27 had the titles crossed: `Upload failed` is the no-link case, `Not uploaded` the case over a link (D14).
  - Test 46 said pruning closes the card with `.deleted`; `removeFiles(ofPruned:)` never closed it (D12).
  - 4.2 read a `.gif` with `VideoValidation`, which would remove every GIF; it is read with ImageIO (D11). It named no
    line for an empty file or a failed removal; `Recovery: <name> is empty, removed` and `Recovery: <name> <reason>, and
    could not be removed: <error>` are logged (D11).
  - 4.2 ran `adoptPendingFiles` before the `tmp/Recording` scan; the scan runs first, at launch, so a recording started
    while adopting runs is never listed and removed mid-write (D27). `recoverRecordings` takes `begin`'s result.
  - 8 said the suite covers the calls A to H; it covers A to F. G (a second Abort failing after a 204) needs a
    per-call Abort script `FakeDestination` does not have, and H needs a read counter `readPart` does not have (D18),
    so both stay in Tim's R4 run.

  The other departures, in short: `Clipboard` also has `hasAnnotationClip` (D2); the triple `makeDestination()`
  returns is `AppCoordinator.UploadTarget`, and `persist` and `finishSave` take `UploadTarget?` (D3); the Upload
  tab's connection test takes the target, so `ConnectionTester.run` takes `any Destination` and the key template
  (D19). `FakeDestination`'s download holds until released, ignoring a cancel, instead of sleeping until cancelled
  (2.4; D7). Test 28 cannot see "the queue got no cancel" (a queue cancel of a job it does not hold changes nothing),
  so it checks the lane was never given the job (D23). Test 56 cannot see `saveLocation.cancelFolderChoice()`: with no
  folder panel open it does nothing, and the panel is Deferred (D22). 5.3's multipart pair expects `.started` before
  `.cancelled`, the multipart path's order (`.started` goes before its `abortFirst`; D23). 5.4's `sendParts` test
  checks no `part n` after the cancel, not a read count (`readPart` has no counter; D18). Tests 48 and 50 cannot tell
  the coordinator's own do-nothing branches from the recorder's, which drops a stop with no run and a repeated stop
  itself, so they pin no notice and one recorder stop, and the `did nothing` log lines stay Tim's (D24). The upload
  tests keep every recording in `pending/` rather than a temp save folder (D25). The suite also has
  `CoordinatorWorldTests` (one test of the harness itself), and README names the `pending/` recovery (D21).
  After the split, `UploadQueue.swift` is 324 lines (5.1 estimated about 290), `UploadQueue+Multipart.swift` 215 and
  `UploadQueue+Parts.swift` 230; write the counts `wc -l` gives if they differ.

  Hand checks: section 8, in the checklist above, not yet run. The R4 checklist's covered items are marked
  `(suite: …)`.
  ```
- [ ] Run the full suite and the Release build once. `git diff --stat main -- project.yml` prints nothing.
- [ ] Commit: `docs: coordinator harness checklist and design close-out`.

## Test totals

| After | Total |
|---|---|
| Baseline | 2090 tests in 174 suites (confirm in Task 1) |
| Task 1 | unchanged |
| Task 2 | unchanged |
| Task 3 | unchanged |
| Task 4 | 2091 in 175 (`CoordinatorWorldTests` 1) |
| Task 5 | 2107 in 176 (`CoordinatorDragOutTests` 16) |
| Task 6 | 2125 in 177 (`CoordinatorUploadTests` 18) |
| Task 7 | 2137 in 178 (`CoordinatorDeleteTests` 12) |
| Task 8 | 2146 in 179 (`CoordinatorRecordingTests` 9) |
| Task 9 | 2153 in 180 (`PendingRecoveryTests` 5, `PendingFileStoreTests` +2) |
| Task 10 | unchanged |
| Task 11 | 2160 in 181 (`CoordinatorRecoveryTests` 7) |
| Task 12 | unchanged |
| Task 13 | 2163 (`UploadQueueTests` +2, `CoordinatorDeleteTests` +1, test 39) |
| Task 14 | 2167 (`UploadQueueTests` +4) |
| Task 15 | 2169 (`UploadQueueTests` +2) |
| Task 16 | 2169 in 181 |

## Plan decisions

Where the design leaves a detail to the plan, or where the plan departs from its wording, with the reason. Task 16 writes them into the design's built notes.

1. **`Notifying`'s signatures.** The requirements carry every parameter: `notifySaved(fileURL:title:)`, `notifyUploaded(url:copied:)`, `notifyError(_:title:subtitle:revealing:)` (the design wrote `openURL:`, which is `notify`'s; `Notifier.notifyError` takes `revealing:`), `notify(title:body:subtitle:openURL:)`, `holdNotices()`, `releaseHeldNotices() -> Int`, `waitForReleasedNotices(upTo:)`, `setUp()`. Protocol-extension overloads give the shorter call forms the coordinator uses, so no call site changes.
2. **`Clipboard` also has `hasAnnotationClip`**, which the editor's object clipboard reads, and `setString(_:)` is Capture Text's clear-and-set as one call.
3. **The triple is `AppCoordinator.UploadTarget`** (`destination`, `location`, `keyTemplate`), the parameter label `destination:` kept so callers do not change; `persist` and `finishSave` take `UploadTarget?` where they took `S3Destination?`. Its location and template are read from `config.normalized`, as `S3Destination.config` held them.
4. **The environment also holds `multipartPlan`** (design 3.2's setup) **and `uploadSleep`** (the lane's backoff, so test 19's retry does not wait), and `makeLane` passes the environment's `now` and `log` to the queue. The live values are `UploadQueue`'s defaults, so the app's lanes are as before.
5. **`.live()` builds the save location, the settings, the credential store, the notifier and the card stack in their old order**, then the history URL. `engine`, `permissionWindow` and `clopOptimiser` keep their property initializers and now run after those five; none of the three does anything in its initializer, so nothing observable moves.
6. **The coordinator stores `let environment`** and forwards `log(_:)`. Three log sites off the main actor (`makeThumbnail`, `replaceThumbnail`, `openCapture`'s completion) capture `environment.log`.
7. **`FakeDestination`'s download** is scripted by `downloadOutcome` (`.lands(bytes:)` or `.fails(error)`), `downloadFractions` reported first, and `holdsDownloads`/`releaseDownloads()` (a hold that ignores a cancel, so a test can land a file or a failure after it). It records each call's key and resume data, keeps the last progress callback for `reportLateFraction(_:)`, and `download(key:)` returns `downloadedData`. It also gains `deletedKeys` (Delete's DELETEs were not recorded), `holdingPart` and the two Abort scripts (`blockingAbortsRemaining`, `holdingAbortsRemaining`).
8. **`CoordinatorWorld`'s defaults suite** is `io.tky.tidyshot.tests.CoordinatorWorld-<Test.current's name>-<uuid>`, emptied at the start and removed by `removeAll()`. The folders are `<tmp>/CoordinatorWorld-<uuid>/Support/history.json` and `<tmp>/CoordinatorWorld-<uuid>/tmp/`.
9. **`RecordingProceeds`** is `case start` and `case stop(logsCancel: Bool)`, beside `RecordingStopCommandAction`; `record()` reads it in one expression with no suspension before `recorder.run`.
10. **`adoptPendingFiles` reads each orphan off the main actor** in a `@concurrent` static and checks again, after the read, that no record has its id; a removal goes through `pendingFiles.remove`, and a timestamp the file system cannot give is `environment.now()`.
11. **An adopted GIF is read with ImageIO** (size, first frame, the sum of its frame delays), not `VideoValidation`: AVFoundation does not open a GIF, so the design's rule would remove every GIF it found, against its own "never deleted" stance. A zero-byte file logs `Recovery: <name> is empty, removed` (the design gave none); a failed removal logs `… , and could not be removed: <error>`.
12. **Test 46 asserts that pruning closes no card.** The design's line says it closes the card with `.deleted`; `removeFiles(ofPruned:)` never did (+Delete.swift:278-301 closes the pins only; `removeRecord` is what calls `overlay.close(… .deleted)`), and the harness changes no behaviour. Tim rules before Task 7 runs (its gate): confirmed, Task 16 corrects the design's line; overruled, the close is a behaviour change with its own task before Task 7, and test 46 expects the `.deleted` close.
13. **Test 20 expects two Aborts at the old location**: `abortUploads` repeats an Abort that answered 204 (test 38), where the design's line said one.
14. **Test 27 follows the code's titles**: a failed upload with no link posts `Upload failed` with the error (`markFailed`, +Upload.swift:575), and one over a link posts `Not uploaded` with `Upload failed. The link still shows the earlier image.` (+Upload.swift:704); the design's line had the two titles crossed. Task 16 corrects the design's 3.2 line and says so in the built notes.
15. **Test 19's retry is a screenshot's single PUT.** The queue sends `.started(attempt: 2)` for a single PUT's retry and a multipart restart; a part's own retry sends none, so the design's "fails the first part once" would log nothing.
16. **Test 17 reads the sent size from the record** after `.uploaded` (`sentByteCounts` is taken when the upload ends and stored as `byteCount`). Tests 17 and 25 add the record at 1 byte over a file of 1 MiB, so the size it ends with is the one `.uploaded` wrote. Test 39 lands with Task 13, the change it pins, so the suite passes after every task.
17. **Test 6 cancels through `overlayDidClose(_:reason: .user)`**, which calls `cancelDragDownload`; test 7 covers `removeDragFolder`.
18. **The `sendParts` test observes calls, not reads**: `readPart` is a static with no counter, so "the read count did not grow" is checked as "no `part n` call after the cancel", which the check placed before the read guarantees. The existing `aSidecarUnwritableAtCreateFailsTheJob` now expects `create`, `abort`.
19. **The Upload tab's connection test takes `makeDestination()`'s target.** `UploadSettingsView.test()` is the one caller of `makeDestination()` outside the coordinator, and it handed the result to `ConnectionTester.run(destination: S3Destination)`, which read `destination.config.keyTemplate`. `run` now takes `any Destination` and `keyTemplate:` (the probe uses only `upload`, `publicURL(for:)` and `delete`, all on `Destination`), and the view passes `target.destination` and `target.keyTemplate`, the normalized template `S3Destination.config` held. Building an `S3Destination` in the view instead would have reached `loadCredentials`, a member the split design's 3.5 surface does not give the settings views. `ConnectionTesterTests`' seven calls pass `config.normalized.keyTemplate`.
20. **The R4 checklist's Settings prompt line (:217) is marked**, though the design's section 8 names only lines 224-227, 230-263, 271-291 and the calls: test 52 pins that line's rule (a cancelled settle delay records nothing and logs the cancel; a quit logs nothing), so the mark reads `(suite, the rule: …)`; the log line itself stays Tim's.
21. **Beyond section 7's suites**: `CoordinatorWorldTests` (one test that the harness keeps the coordinator to its world, so a broken world fails there before any suite that uses it), a README sentence for the `pending/` recovery a user can see (`Recovered a capture`), and the design's `## 11. Built notes`, as every phase's close-out writes.
22. **Test 56 does not observe `saveLocation.cancelFolderChoice()`.** It only cancels open folder panels (`SaveLocation.swift:57-61`), so with none open it does nothing a test can see, and a panel seam is Deferred (the design's Deferred list has the Save As panel and `saveLocation.chooseFolder`). Test 56 pins the rest, and the order: `FakeNotifier.onWait` reads the phase and the driver's stop count at the wait, which must be `.idle` and 1.
23. **Two observations the design asks for are made another way.** Test 28's "the queue got no cancel": `startUpload` makes the lane before the wait, and a queue cancel of a job it does not hold changes nothing, so the test checks the lane's queue is idle (never given the job) and that nothing was uploaded. 5.3's multipart pair expects `.started` then `.cancelled`, not `.cancelled` alone: the multipart path sends `.started` before its `abortFirst` (UploadQueue.swift:295 and :301), which is the code's order and the harness does not change it.
24. **Tests 48 and 50 pin the outcome, not the coordinator's branch.** `RecordingController.stop()` ends through `end(_:)`, whose `guard isRunning, self.cause == nil` turns a stop with no run and a repeated stop into no-ops (RecordingController.swift:238-240 and :480-481), so `driver.stopCount` reads 0 in test 48 and 1 in test 50 whether or not `stopRecordingCommand`'s `.nothing` branch and its `recorder.isEnding` check work. No seam counts the coordinator's own stop calls: it would be a test-only member, or an environment closure for one call. The two tests pin what can be seen (no notice, no cancelled count-in, the phase unchanged in test 48, one recorder stop in test 50), their doc comments claim no more, and the `RecordingLog` line each branch writes is Tim's (the harness checklist's item 4).
25. **`pending/` stands in for the save folder.** The design's setup (3.2) puts a recording in a temp save folder; the upload tests' helpers put every recording and screenshot in `pending/` with `fileIsTemporary: true`. A save-folder file is reached through `SaveLocation`'s security-scoped bookmark, and a test's world has no bookmarked folder (`currentURL` is resolved from a bookmark, and choosing one takes the folder panel, which is Deferred); `UploadPayload.video` refuses a file that is not temporary and has no scope (`fileUnreadable`, UploadPayload.swift:25-27), so a plain temp folder would not upload at all. Past the payload the two paths are one lane, one resume rule and the same events; the scope's start and stop around a read are `UploadQueueTests`' (its security-scope counter).
26. **The harness fakes share their hold and their single-entry wait** (decided at execution, Task 4's review). The plan's code wrote the hold-until-release block three times in `FakeDestination` (downloads, parts, Aborts) and the single-entry waiter three times in `CoordinatorFakes` (`FakeConfirm`, `HeldCameraDevices`, `TestGate`). They share one helper each: a `HeldReleases` for the three new holds and a `SingleWaiter` for the three fakes. The pre-existing upload hold (`heldUploads`/`releaseUploads(throwing:)`, moved from `UploadQueueTests.swift`) stays as it was, so the move of `FakeDestination` is still byte-for-byte for the code it moved. Every member a later brief reads (`holdsDownloads`, `releaseDownloads()`, `releaseParts()`, `releaseAborts()`, the cancellation counters, `isWaiting`, `isAsking`, `confirm`, `requestAccess`, `answer(_:)`, `wait()`, `open()`) keeps its name and behaviour, and the issue texts are unchanged.
27. **`tmp/Recording` is scanned at launch, before `pending/` is adopted** (decided at execution, Task 11's review). The design's 4.2 gave `Task { await adoptPendingFiles(listed); await recoverRecordings() }`. `registerShortcuts()` runs right after that task is made and adopting reads each orphan off the main actor (ImageIO, `VideoValidation.inspect`, `PosterFrame.image`), so it can take seconds, during which a recording can start; with adoption first, `RecordingRecovery.begin`'s scan would list that recording and remove it as unplayable mid-write, or move it to `pending/` while still recording. The old code's comment ("the scan lists the folder first, long before a recording started now could write there") and the recording design's "Relaunch after a crash" rest on the scan running at launch. So `start()`'s one task runs `RecordingRecovery.begin(recordingDirectory:muteDirectory:)` first, then `adoptPendingFiles(pendingListed)`, then `recoverRecordings(begun)`; `recoverRecordings` takes `begin`'s `(muteFiles:found:)` instead of calling `begin` itself, and its loop and sweep are unchanged. Adoption still comes before any scanned file moves into `pending/` or is checked against the records, so a GIF orphan adopted first still makes its MP4 `.savedAsGIF`. Running `recoverRecordings` entirely first was rejected: a GIF orphan whose MP4 is still in `tmp/Recording` would get the MP4 recovered under its id and the GIF left with no record. No test pins the order (`start()` touches the globals the harness keeps out).
