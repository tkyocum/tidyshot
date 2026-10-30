# TidyShot Checklist Tests (CT-1), Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 148 manual checklist lines that the suite can drive today become tests: 103 new test functions and 5 extended ones, in 33 suite files (10 new), over the coordinator harness and the existing fakes. Each covered line gets its `(suite: …)` mark. `TidyShot/` does not change.

**Architecture:** `docs/superpowers/specs/2026-10-30-tidyshot-checklist-tests-design.md` is the specification, and its catalogue `docs/superpowers/notes/2026-10-30-checklist-sweep/tests-A.md` describes every test (entry point, fakes, assertions, the lines it covers). When this plan and either disagree, the plan's "Plan decisions" (at the end) says why; stop and ask if anything else is unclear.
- **Support (Task 1):** four extensions to the test fakes, none a seam: `FakeDestination` gets a throw script for `download(key:)`, a failure script for `delete(key:)` and a digest of each part's bytes; `FakeNotifier.Call` carries the subtitle of an error or a notice.
- **Coordinator suites (Tasks 2 to 7):** drive `AppCoordinator`'s internal entry points over `CoordinatorWorld`, with `eventually`, `TaskWatch` and the held fakes as the harness suites do. Two more support pieces land with their first users: `CoordinatorWorld.storeSaveFolder()` (Task 2) and `HeldMicrophoneDevices` with `world.microphones` as an `any MicrophoneDevices` (Task 7).
- **Model and view suites (Tasks 8 to 11):** build their own `EditorModel`, `CanvasView`, `SelectionView` and the rest, never ordered front, as the existing suites do.
- **Marks (Task 12):** each covered line gets `(suite: …)` or `(suite, in part: …; by hand: …)`, placed by a script that finds each item by its text, after PR #28 is in the branch.

**Tech Stack:** Swift 6 language mode with default `MainActor` isolation and `NonisolatedNonsendingByDefault`, Swift Testing, AppKit, CryptoKit (in `FakeDestination`, for the part digest), XcodeGen 2.46.

**Tried before writing:** every Swift block below was applied, in task order, to a copy of the tree at f265aff; it built with no error and the suite read `Test run with 2272 tests in 191 suites passed` on three runs, and again after the review's changes to Task 3's Forget Credentials test, Task 4's four save tests, Task 7's two quit tests and the doc comments of Task 8's extended test and Task 10's drag-view test. Task 12's two scripts were run on a copy of PR #28's checklists and of the two designs: `148 lines marked`, `designs corrected`. A worker who finds a block that does not build or a test that fails has found drift since then: stop and report it rather than reshape the test.

Work happens on the branch `checklist-tests` (from `main` at e011d2f, the design at f265aff). Line numbers below are the working tree's at f265aff; once a task has grown a file, find the place by the quoted text.

## Global Constraints

- **From the brief, verbatim:**
  - `TidyShot/` does not change;
  - no private member opened;
  - no test touches `AppSettings.shared`, `NSPasteboard.general`, the Keychain, `UNUserNotificationCenter`, `NSWorkspace`, `NSScreen.screens`, the `tmp/` statics, a window ordered front, the screen, a camera, a microphone, a sound or the network;
  - explicit `CaptureIntent(action:)`;
  - `HistoryStore` prunes on the real `Date()`;
  - `CanvasView` transforms asserted as relations;
  - held fakes cancellable and single-entry, no direct await on the behaviour under test;
  - own temp folders and defaults suite per test, no `.serialized`;
  - commits carry no attribution lines and no session URL;
  - never push;
  - the tests' `MovieSamples` decoder untouched;
  - the suite command and the known noise lines (two history-file lines, `com.apple.linkd.autoShortcut`, about 40 `MDB_MAP_FULL` lines) as the harness plan states them;
  - baseline 2169 tests in 181 suites.
- **The suite command.** Run the full suite with:
  ```bash
  xcodegen generate && xcodebuild test -project TidyShot.xcodeproj -scheme TidyShot -destination 'platform=macOS' -derivedDataPath .build 2>&1 | grep -E "Test run with|error:|TEST"
  ```
  and one suite with `-only-testing:TidyShotTests/<Suite>` added before `2>&1`. The baseline is `Test run with 2169 tests in 181 suites passed` (confirmed at f265aff). The known noise lines are not failures: `History file could not be read or decoded, setting it aside` twice, `com.apple.linkd.autoShortcut`, and about 40 `mdb_txn_commit error: MDB_MAP_FULL` lines. When coreaudiod stalls the suite takes about 126 s instead of about 40 s; that is not a failure. The Release build is `xcodebuild -project TidyShot.xcodeproj -scheme TidyShot -configuration Release -derivedDataPath .build-rel build`.
- **Counting.** `xcodebuild`'s line counts each `@Test` function once, whatever its arguments: the baseline tree has exactly 2169 `@Test` attributes, 84 of them parameterized, and reads 2169 tests (D1). Each new test file is one new suite.
- **The harness's rules hold.** A coordinator test builds its world in the suite's `init`, calls `defer { world.removeAll() }` first, passes an explicit `CaptureIntent(action:)` to every entry point that takes one, and never calls an entry point whose default argument is `.standard`. A test that would wait on a held fake gates the call with `TaskWatch` and `eventually`. Retention tests stamp records relative to `Date()`. Every coordinator suite keeps `settings.showOverlay` off whenever a save could show a card, because `showOverlay(for:)` reads `NSScreen.screens` once the setting is on.
- **No new package, entitlement or setting.** `project.yml` does not change; new files are picked up by `xcodegen generate`.
- **Keep out of the system.** No task runs the app. The hand checks stay Tim's; each task's report says none were run.
- **Commits.** Commit after every task with the message the task gives and no attribution lines. Never push and never switch branches.

---

### Task 1: The four fake extensions [integration]

**Files:** modify `TidyShotTests/Support/FakeDestination.swift`, `TidyShotTests/Support/CoordinatorFakes.swift`, `TidyShotTests/UploadQueueTests.swift` (one assertion in `aFileAtTheThresholdGoesMultipart`).

**Produces:** `FakeDestination.State.dataDownloadFailures`, `.deleteFailures`, `.partDigests` and `FakeDestination.digest(_:)`; `FakeNotifier.Call.error(title:message:subtitle:)` and `.notice(title:body:subtitle:)` with the subtitle defaulting to nil.

**Steps:**
- [ ] In `FakeDestination.swift`, import CryptoKit under the other imports:
  ```swift
  import CryptoKit
  import Foundation
  import Synchronization
  @testable import TidyShot
  ```
- [ ] In `FakeDestination.State`, after `var dataDownloadKeys: [String] = []`, add the download throw script, and replace the `deletedKeys` line with the delete record and its failure script:
  ```swift
          var dataDownloadKeys: [String] = []
          /// Errors for `download(key:)`, one per call, in order; then it returns `downloadedData`.
          var dataDownloadFailures: [any Error & Sendable] = []
          /// Every `delete(key:)`, in order, including ones that throw.
          var deletedKeys: [String] = []
          /// Errors for `delete(key:)`, one per call, in order; then it succeeds.
          var deleteFailures: [UploadError] = []
  ```
- [ ] In `FakeDestination.State`, after `var sentParts: [Int] = []`, add:
  ```swift
          /// Every part call, including ones that throw, with the SHA-256 of the bytes it was given
          /// (`FakeDestination.digest`), so a test can see which bytes a retry sent.
          var partDigests: [(number: Int, digest: String)] = []
  ```
- [ ] Replace `download(key:)`:
  ```swift
      func download(key: String) async throws -> Data {
          let (failure, data) = state.withLock { state -> ((any Error & Sendable)?, Data) in
              state.dataDownloadKeys.append(key)
              let failure = state.dataDownloadFailures.isEmpty ? nil : state.dataDownloadFailures.removeFirst()
              return (failure, state.downloadedData)
          }
          if let failure { throw failure }
          return data
      }
  ```
- [ ] Replace `delete(key:)`:
  ```swift
      func delete(key: String) async throws {
          let failure = state.withLock { state -> UploadError? in
              state.deletedKeys.append(key)
              return Self.nextFailure(&state.deleteFailures)
          }
          if let failure { throw failure }
      }
  ```
- [ ] In `uploadPart`, record the digest with the part. Replace the `record("part \(number)")` block's first line inside the closure:
  ```swift
          let digest = Self.digest(data)
          let delay = record("part \(number)") { state in
              state.parts.append((uploadID, number, data.count))
              state.partDigests.append((number, digest))
  ```
  (the rest of the closure, from `state.answeredAtStart[number, default: []]...`, is unchanged), and add the helper after `nextFailure`:
  ```swift
      /// The SHA-256 of `data` in lowercase hex.
      static func digest(_ data: Data) -> String {
          SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
      }
  ```
- [ ] In `CoordinatorFakes.swift`, give `FakeNotifier.Call`'s `error` and `notice` the subtitle, defaulted so every existing `.error(title:message:)` and `.notice(title:body:)` still compiles and compares a subtitle of nil:
  ```swift
      enum Call: Equatable {
          case setUp
          case saved(title: String, file: String)
          case uploaded(url: URL, copied: Bool)
          case error(title: String, message: String, subtitle: String? = nil)
          case notice(title: String, body: String, subtitle: String? = nil)
          case held
          case released
          case waited(Duration)
      }
  ```
  and in the same class:
  ```swift
      /// The `notifyError` calls, in order.
      var errors: [(title: String, message: String)] {
          calls.compactMap { call -> (title: String, message: String)? in
              guard case .error(let title, let message, _) = call else { return nil }
              return (title, message)
          }
      }
  ```
  ```swift
      func notifyError(_ message: String, title: String, subtitle: String?, revealing fileURL: URL?) {
          calls.append(.error(title: title, message: message, subtitle: subtitle))
      }

      func notify(title: String, body: String, subtitle: String?, openURL: URL?) {
          calls.append(.notice(title: title, body: body, subtitle: subtitle))
      }
  ```
  `grep -rn "case .error(\|case .notice(" TidyShotTests` must list no other pattern that binds two values of these cases.
- [ ] Exercise the part digest in an existing test (`UploadQueueTests.aFileAtTheThresholdGoesMultipart`, after its `#expect(partNumbers(destination) == [1, 2, 3, 4])`): the movie is a sparse file, so each part's bytes are zeros.
  ```swift
          let zeros = FakeDestination.digest(Data(count: 262_144))
          #expect(destination.state.withLock { $0.partDigests.map(\.digest) } == Array(repeating: zeros, count: 4))
  ```
  The subtitle is exercised by every existing comparison of an `.error` call (each now compares a nil subtitle). The download and delete scripts are first used by Task 6's `aCopyImageWhoseDownloadFailsSaysCouldNotCopyImage` and Task 2's `aRemoteDeleteFailureDuringAnUploadKeepsTheRecordUntilRemoveFromHistory`; no existing test calls either in a way a script would change (D3).
- [ ] Run `UploadQueueTests` and `CoordinatorDeleteTests` alone, then the full suite: `Test run with 2169 tests in 181 suites passed`.
- [ ] Commit: `test: fake scripts for a failing download and delete, part digests, notice subtitles`.

### Task 2: `CoordinatorDeleteTests` [integration]

**Files:** modify `TidyShotTests/Support/CoordinatorWorld.swift` (one helper), `TidyShotTests/CoordinatorDeleteTests.swift`.

**Consumes:** Task 1 (`deleteFailures`).

**Produces:** `CoordinatorWorld.storeSaveFolder()`, used here and by Tasks 4 and 6.

**Steps:**
- [ ] In `CoordinatorWorld.swift`, after `removeAll()`, add:
  ```swift
      /// `<root>/Saved/`, stored as the save location's folder (`SaveLocation.store`, where Settings >
      /// General's Choose… lands), so a save-folder file is reached as in the app: a recording moves
      /// there, Delete removes from there, and an upload reads from there under the folder's scope. The
      /// folder panel is never built. Store it before anything a test drives asks for the folder.
      @discardableResult
      func storeSaveFolder() throws -> URL {
          let folder = root.appending(path: "Saved", directoryHint: .isDirectory)
          try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
          try saveLocation.store(folder)
          return folder
      }
  ```
- [ ] In `CoordinatorDeleteTests`, after `exists(_:)`, add the helpers:
  ```swift
      /// An upload-only screenshot in `pending/` with a thumbnail, added to history: failed, so a Retry
      /// starts it.
      func addPendingImage(to coordinator: AppCoordinator) throws -> CaptureRecord {
          let id = UUID()
          let png = try CoordinatorWorld.pngData(width: 4, height: 2)
          let url = try coordinator.pendingFiles.write(png, id: id, ext: "png")
          let thumbnail = try coordinator.thumbnails.write(Data("png".utf8), id: id)
          let record = CaptureRecord(id: id, fileURL: url, fileIsTemporary: true, thumbnailFileName: thumbnail,
                                     pixelWidth: 4, pixelHeight: 2, appName: nil,
                                     uploadState: .failed(message: "Upload was interrupted."), byteCount: png.count)
          coordinator.history.add(record)
          return record
      }

      /// An uploaded capture whose file is in the stored save folder, with a thumbnail. A nil `location`
      /// is a capture uploaded before Phase 3.
      func addSavedUpload(to coordinator: AppCoordinator, in folder: URL, kind: MediaKind = .image,
                          key: String = "s/SAVED.png", location: ObjectLocation?) throws -> CaptureRecord {
          let id = UUID()
          let file = folder.appending(path: "Saved \(id.uuidString).\(kind.fileExtension)")
          try Data("file".utf8).write(to: file)
          let thumbnail = try coordinator.thumbnails.write(Data("png".utf8), id: id)
          let record = CaptureRecord(id: id, fileURL: file, thumbnailFileName: thumbnail, pixelWidth: 4, pixelHeight: 2,
                                     appName: nil,
                                     uploadState: .uploaded(url: URL(string: "https://snap.tky.io/\(key)")!, key: key),
                                     objectLocation: location, mediaKind: kind,
                                     durationSeconds: kind == .image ? nil : 10)
          coordinator.history.add(record)
          return record
      }

      func thumbnailURL(_ coordinator: AppCoordinator, _ record: CaptureRecord) throws -> URL {
          coordinator.thumbnails.url(forFileName: try #require(record.thumbnailFileName))
      }

      /// The record kinds `deleteRemovesTheObjectTheFileTheThumbnailAndTheRow` deletes, each with its own
      /// Ask before deleting.
      nonisolated enum Kind: CaseIterable, Sendable {
          /// With Ask before deleting on.
          case image
          /// With it off.
          case video
          /// With it on.
          case gif

          var mediaKind: MediaKind {
              switch self {
              case .image: .image
              case .video: .video
              case .gif: .gif
              }
          }

          var asksFirst: Bool { self != .video }
      }
  ```
- [ ] Replace `removingARecordClearsItsBookkeeping` (the extension):
  ```swift
      /// 47 (harness design 3.3). Removing a record clears its bookkeeping everywhere. phase-4a :53: deleting a row
      /// whose card is open closes that card and drops the retained image, so Annotate on another row opens
      /// its own capture (which source it reads is `EditorInputTests.retainedWinsForLatestCapture`).
      @Test func removingARecordClearsItsBookkeeping() async throws {
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
          let image = try CoordinatorWorld.image(width: 4, height: 2)
          coordinator.latestCapture = (id: id, image: ScaledImage(image: image, scale: 1))

          await coordinator.deleteCapture(recordID: id)

          #expect(world.confirm.asked.isEmpty)
          #expect(coordinator.history.record(id: id) == nil)
          #expect(!coordinator.optimizingVideoIDs.contains(id))
          #expect(!coordinator.fileUploadIDs.contains(id))
          #expect(coordinator.videoClipboardCounts[id] == nil)
          #expect(!coordinator.linkNotCopiedIDs.contains(id))
          #expect(coordinator.copyFileCounts[id] == nil)
          #expect(coordinator.dragDownloadResume[id] == nil)
          #expect(coordinator.latestCapture?.id == nil)
          #expect(world.cards.closes == [.deleted])
      }
  ```
- [ ] Add the eleven tests at the end of the struct:
  ```swift
      /// coordinator-split :45, phase-3 :38, phase-3 :39, phase-3 :41. Delete during an upload: Cancel in the alert
      /// keeps everything, the upload goes on and the card stays; Delete cancels the upload, also on a lane the
      /// Upload tab replaced, deletes the key the upload had reserved, removes the row, the pending file and
      /// the thumbnail, closes the card, and the menu bar icon (`isUploading`) goes back.
      @Test(arguments: [false, true])
      func deleteDuringAnUploadCancelsItThenDeletesTheReservedKey(onAReplacedLane: Bool) async throws {
          defer { world.removeAll() }
          destination.state.withLock { $0.blockingUploadsRemaining = 1 }
          world.confirm.answers = [false, true]
          let coordinator = world.makeCoordinator()
          let record = try addPendingImage(to: coordinator)
          let pending = try #require(record.fileURL)
          let thumbnail = try thumbnailURL(coordinator, record)
          coordinator.retryUpload(recordID: record.id)
          try await eventually { destination.state.withLock { $0.uploadAttempts } == 1 }
          if onAReplacedLane {
              coordinator.destinationDidChange()
              #expect(coordinator.drainingQueues.count == 1)
          }
          // The question names the record as it is now, uploading.
          let uploading = try #require(coordinator.history.record(id: record.id))

          await coordinator.deleteCapture(recordID: record.id)
          #expect(world.confirm.asked == [.delete(uploading)])
          #expect(coordinator.history.record(id: record.id) != nil)
          #expect(coordinator.uploadingIDs.contains(record.id))
          #expect(world.cards.closes.isEmpty)

          await coordinator.deleteCapture(recordID: record.id)
          let attempted = destination.state.withLock { $0.attemptKeys }
          #expect(attempted.count == 1)
          #expect(destination.state.withLock { $0.deletedKeys } == attempted)
          #expect(coordinator.history.record(id: record.id) == nil)
          #expect(!exists(pending))
          #expect(!exists(thumbnail))
          #expect(world.cards.closes == [.deleted])
          #expect(!coordinator.isUploading)
          if onAReplacedLane {
              try await world.clock.run(until: { coordinator.drainingQueues.isEmpty })
          }
      }

      /// phase-3 :40, phase-5 :181, recording-r1 :309, recording-r2 :676. Delete after the upload finished removes the
      /// object, the save-folder file, the thumbnail and the row, after one confirmation with Ask before
      /// deleting on and none with it off; a stitched capture, a video and a GIF go as a screenshot does.
      @Test(arguments: Kind.allCases)
      func deleteRemovesTheObjectTheFileTheThumbnailAndTheRow(kind: Kind) async throws {
          defer { world.removeAll() }
          world.settings.confirmBeforeDeleting = kind.asksFirst
          let folder = try world.storeSaveFolder()
          let coordinator = world.makeCoordinator()
          let key = "s/SAVED.\(kind.mediaKind.fileExtension)"
          let record = try addSavedUpload(to: coordinator, in: folder, kind: kind.mediaKind, key: key,
                                          location: world.location)
          let file = try #require(record.fileURL)
          let thumbnail = try thumbnailURL(coordinator, record)

          await coordinator.deleteCapture(recordID: record.id)

          #expect(world.confirm.asked == (kind.asksFirst ? [.delete(record)] : []))
          #expect(destination.state.withLock { $0.deletedKeys } == [key])
          #expect(world.factory.askedLocations == [world.location])
          #expect(!exists(file))
          #expect(!exists(thumbnail))
          #expect(coordinator.history.record(id: record.id) == nil)
          #expect(world.cards.closes == [.deleted])
      }

      /// phase-3-1 :50. Delete of an upload-only capture whose upload failed asks once and sends no DELETE (nothing
      /// was uploaded and no key reserved), and the row, the thumbnail and `pending/<id>.png` go.
      @Test func aFailedUploadOnlyCaptureIsDeletedWithOneQuestionAndNoDelete() async throws {
          defer { world.removeAll() }
          let coordinator = world.makeCoordinator()
          let record = try addPendingImage(to: coordinator)
          let pending = try #require(record.fileURL)
          let thumbnail = try thumbnailURL(coordinator, record)

          await coordinator.deleteCapture(recordID: record.id)

          #expect(world.confirm.asked == [.delete(record)])
          #expect(destination.state.withLock { $0.deletedKeys.isEmpty })
          #expect(world.factory.askedConfigs.isEmpty)
          #expect(coordinator.history.record(id: record.id) == nil)
          #expect(!exists(thumbnail))
          #expect(!exists(pending))
      }

      /// phase-3-1 :52, small-tweaks :9. With no credentials, Delete of an uploaded capture shows the second alert,
      /// `Couldn't delete it from storage: No credentials are saved in Settings > Upload.`; with Ask before
      /// deleting off it is the only alert. Remove drops the row.
      @Test(arguments: [true, false])
      func aDeleteThatCannotReachStorageAsksToRemoveFromHistory(confirmFirst: Bool) async throws {
          defer { world.removeAll() }
          world.settings.confirmBeforeDeleting = confirmFirst
          try world.credentials.delete(account: KeychainCredentialStore.defaultAccount)
          let coordinator = world.makeCoordinator()
          let record = addUploadedImage(to: coordinator)
          let question = DeleteConfirmation.removeFromHistory(
              message: CaptureDeletion.storageFailureMessage(reason: "No credentials are saved in Settings > Upload."),
              informativeText: CaptureDeletion.storageFailureText)

          await coordinator.deleteCapture(recordID: record.id)

          #expect(world.confirm.asked == (confirmFirst ? [.delete(record), question] : [question]))
          #expect(coordinator.history.record(id: record.id) == nil)
          #expect(world.factory.askedConfigs.isEmpty)
      }

      /// phase-3-1 :51. Delete after an upload reserved its key, with the storage DELETE failing: the second alert
      /// carries the reason; Cancel keeps the row (`Upload cancelled.`, failed, its key reserved) and
      /// `pending/<id>.png`; a second Delete that fails again, then Remove, drops the row, the thumbnail and the
      /// pending file.
      @Test func aRemoteDeleteFailureDuringAnUploadKeepsTheRecordUntilRemoveFromHistory() async throws {
          defer { world.removeAll() }
          let refused = UploadError.httpStatus(403, body: "AccessDenied: Access Denied")
          destination.state.withLock {
              $0.blockingUploadsRemaining = 1
              $0.deleteFailures = [refused, refused]
          }
          world.confirm.answers = [true, false]
          let coordinator = world.makeCoordinator()
          let record = try addPendingImage(to: coordinator)
          let pending = try #require(record.fileURL)
          let thumbnail = try thumbnailURL(coordinator, record)
          coordinator.retryUpload(recordID: record.id)
          try await eventually { destination.state.withLock { $0.uploadAttempts } == 1 }
          let uploading = try #require(coordinator.history.record(id: record.id))
          let question = DeleteConfirmation.removeFromHistory(
              message: CaptureDeletion.storageFailureMessage(reason: refused.localizedDescription),
              informativeText: CaptureDeletion.storageFailureText)

          await coordinator.deleteCapture(recordID: record.id)
          let key = try #require(destination.state.withLock { $0.attemptKeys.first })
          let kept = try #require(coordinator.history.record(id: record.id))
          #expect(world.confirm.asked == [.delete(uploading), question])
          #expect(kept.uploadState == .failed(message: "Upload cancelled."))
          #expect(kept.pendingObjectKey == key)
          #expect(exists(pending))

          world.confirm.answers = [true, true]
          await coordinator.deleteCapture(recordID: record.id)
          #expect(world.confirm.asked == [.delete(uploading), question, .delete(kept), question])
          #expect(destination.state.withLock { $0.deletedKeys } == [key, key])
          #expect(coordinator.history.record(id: record.id) == nil)
          #expect(!exists(thumbnail))
          #expect(!exists(pending))
      }

      /// phase-3 :26 (with `CaptureDeletionTests.confirmationTextSaysWhenTheObjectStays`, the alert's text). A
      /// capture uploaded before Phase 3 has no stored location: Delete sends no DELETE, so the object stays,
      /// and removes the row and the save-folder file.
      @Test func aPrePhase3UploadedCaptureIsDeletedWithNoStorageRequest() async throws {
          defer { world.removeAll() }
          let folder = try world.storeSaveFolder()
          let coordinator = world.makeCoordinator()
          let record = try addSavedUpload(to: coordinator, in: folder, location: nil)
          let file = try #require(record.fileURL)

          await coordinator.deleteCapture(recordID: record.id)

          #expect(world.confirm.asked == [.delete(record)])
          #expect(world.factory.askedLocations.isEmpty)
          #expect(destination.state.withLock { $0.deletedKeys.isEmpty })
          #expect(!exists(file))
          #expect(coordinator.history.record(id: record.id) == nil)
      }

      /// phase-3 :31. After the Upload tab names another bucket, Delete of a capture uploaded before the change
      /// removes the object from the bucket it went to, never through the current settings.
      @Test func aDeleteAfterABucketChangeDeletesWhereTheObjectWent() async {
          defer { world.removeAll() }
          world.settings.confirmBeforeDeleting = false
          let old = FakeDestination()
          world.factory.add(old, at: location("old.tky.io"))
          let coordinator = world.makeCoordinator()
          let record = CaptureRecord(fileURL: nil, pixelWidth: 4, pixelHeight: 2, appName: nil,
                                     uploadState: .uploaded(url: URL(string: "https://old.tky.io/s/OLD.png")!,
                                                            key: "s/OLD.png"),
                                     objectLocation: location("old.tky.io"))
          coordinator.history.add(record)

          await coordinator.deleteCapture(recordID: record.id)

          #expect(old.state.withLock { $0.deletedKeys } == ["s/OLD.png"])
          #expect(destination.state.withLock { $0.deletedKeys.isEmpty })
          #expect(world.factory.askedLocations == [location("old.tky.io")])
          #expect(coordinator.history.record(id: record.id) == nil)
      }

      /// phase-4a :135. Delete during a replace (an upload over the link's own key) cancels the upload in its lane
      /// and deletes the link's key, so `curl -I <url>` gives 403 or 404.
      @Test func deleteDuringAReplaceCancelsItAndDeletesTheLinksKey() async throws {
          defer { world.removeAll() }
          world.settings.confirmBeforeDeleting = false
          destination.state.withLock { $0.blockingUploadsRemaining = 1 }
          let coordinator = world.makeCoordinator()
          let record = addUploadedImage(to: coordinator, key: "s/LINK.png")
          let png = try CoordinatorWorld.pngData(width: 4, height: 2)
          let target = try #require(coordinator.makeDestination())
          coordinator.startPlannedUpload(recordID: record.id, plan: .replace(key: "s/LINK.png"), payload: .data(png),
                                         destination: target)
          try await eventually { destination.state.withLock { $0.uploadAttempts } == 1 }
          #expect(destination.state.withLock { $0.attemptKeys } == ["s/LINK.png"])

          await coordinator.deleteCapture(recordID: record.id)

          #expect(coordinator.uploadingIDs.isEmpty)
          try await eventually { await coordinator.queue?.queue.isIdle == true }
          #expect(destination.state.withLock { $0.uploads.isEmpty })
          #expect(destination.state.withLock { $0.deletedKeys } == ["s/LINK.png"])
          #expect(coordinator.history.record(id: record.id) == nil)
      }

      /// recording-r4 :236. Delete of a recording mid-upload in parts: the parts are cancelled, the stored upload is
      /// aborted where it was created (twice: a 204 is repeated), the reserved key is deleted, and the record
      /// and its `multipart/` files go.
      @Test func deleteDuringAMultipartUploadAbortsItAndDeletesTheKey() async throws {
          defer { world.removeAll() }
          world.settings.confirmBeforeDeleting = false
          world.multipartPlan = MultipartPlan(threshold: 1_048_576, partSize: 262_144, inFlight: 3)
          destination.state.withLock { $0.partDelay = .seconds(60) }
          let coordinator = world.makeCoordinator()
          let id = UUID()
          let file = coordinator.pendingFiles.directory.appending(path: "\(id.uuidString).mp4")
          try CoordinatorWorld.writeSparseFile(at: file, byteCount: 1_048_576)
          coordinator.history.add(CaptureRecord(id: id, fileURL: file, fileIsTemporary: true, pixelWidth: 1600,
                                                pixelHeight: 1000, appName: nil,
                                                uploadState: .failed(message: "Upload was interrupted."),
                                                mediaKind: .video, durationSeconds: 10, byteCount: 1_048_576))
          coordinator.retryUpload(recordID: id)
          try await eventually { coordinator.history.record(id: id)?.multipart != nil }
          try await eventually { destination.state.withLock { $0.partsInFlight } == 3 }
          let key = try #require(destination.state.withLock { $0.creates.first?.key })

          await coordinator.deleteCapture(recordID: id)

          #expect(destination.state.withLock { $0.aborts.map(\.uploadID) } == ["upload-1", "upload-1"])
          #expect(destination.state.withLock { $0.deletedKeys } == [key])
          #expect(destination.state.withLock { $0.completes.isEmpty })
          #expect(coordinator.history.record(id: id) == nil)
          #expect(!exists(file))
          try await eventually { !exists(coordinator.multipartFiles.sidecarURL(for: id)) }
      }

      /// recording-r4 :377 (call G). Delete's second Abort failing, after a first that answered 204, fails Delete as
      /// a first failure does: the second alert carries the reason, the log names it, and Remove drops the
      /// record. `onCall` sets the failure after the first Abort has drawn its own.
      @Test func aSecondAbortThatFailsAsksToRemoveFromHistory() async throws {
          defer { world.removeAll() }
          world.settings.confirmBeforeDeleting = false
          let refused = UploadError.httpStatus(403, body: "AccessDenied: Access Denied")
          let fake = world.factory.standard
          fake.state.withLock {
              $0.onCall = { call in
                  guard call == "abort" else { return }
                  fake.state.withLock { state in
                      if state.aborts.count == 1 { state.abortFailures = [refused] }
                  }
              }
          }
          defer { fake.state.withLock { $0.onCall = nil } }
          let coordinator = world.makeCoordinator()
          let stored = MultipartUploadState(uploadID: "stored-1", key: "s/STORED.mp4", location: world.location,
                                            partSize: 262_144, byteCount: 3, sourceModified: Date(),
                                            sourcePath: "/nowhere/Recording.mp4", startedAt: Date())
          let record = try addPendingRecording(to: coordinator, state: .failed(message: "Upload was interrupted."),
                                               multipart: stored)
          let name = try #require(record.fileURL?.lastPathComponent)
          let question = DeleteConfirmation.removeFromHistory(
              message: CaptureDeletion.storageFailureMessage(reason: refused.localizedDescription),
              informativeText: CaptureDeletion.storageFailureText)

          await coordinator.deleteCapture(recordID: record.id)

          #expect(fake.state.withLock { $0.aborts.map(\.uploadID) } == ["stored-1", "stored-1"])
          #expect(world.confirm.asked == [question])
          #expect(world.logLines.contains("Upload: \(name) multipart abort failed: \(refused.localizedDescription)"))
          #expect(fake.state.withLock { $0.deletedKeys.isEmpty })
          #expect(coordinator.history.record(id: record.id) == nil)
      }

      /// phase-2 :57, phase-3 :66, recording-r1 :310. Retention at 1 day, then a capture: the older rows go with
      /// their thumbnails, their save-folder files stay (a video's as a screenshot's), a failed upload-only
      /// capture is kept with its `pending/` file however old it is, and nothing asks for a destination.
      @Test func retentionDropsOldRowsAndTheirThumbnailsButKeepsSaveFolderFilesAndUnsentUploads() async throws {
          defer { world.removeAll() }
          let folder = try world.storeSaveFolder()
          let coordinator = world.makeCoordinator()
          // Relative to the real `Date()`, which the history prunes against.
          let old = Date(timeIntervalSinceNow: -2 * 86_400)
          var oldRecords: [CaptureRecord] = []
          for kind in [MediaKind.image, .video] {
              let id = UUID()
              let file = folder.appending(path: "Old \(id.uuidString).\(kind.fileExtension)")
              try Data("file".utf8).write(to: file)
              let thumbnail = try coordinator.thumbnails.write(Data("png".utf8), id: id)
              let key = "s/\(id.uuidString).\(kind.fileExtension)"
              let record = CaptureRecord(id: id, timestamp: old, fileURL: file, thumbnailFileName: thumbnail,
                                         pixelWidth: 4, pixelHeight: 2, appName: nil,
                                         uploadState: .uploaded(url: URL(string: "https://snap.tky.io/\(key)")!, key: key),
                                         objectLocation: world.location, mediaKind: kind)
              coordinator.history.add(record)
              oldRecords.append(record)
          }
          let unsentID = UUID()
          let unsentFile = try coordinator.pendingFiles.write(try CoordinatorWorld.pngData(width: 4, height: 2),
                                                              id: unsentID, ext: "png")
          coordinator.history.add(CaptureRecord(id: unsentID, timestamp: old, fileURL: unsentFile, fileIsTemporary: true,
                                                pixelWidth: 4, pixelHeight: 2, appName: nil,
                                                uploadState: .failed(message: "Upload was interrupted.")))
          // Added under the 30-day default, so these adds prune nothing.
          #expect(coordinator.history.records.count == 3)

          world.settings.historyRetentionDays = 1
          coordinator.history.add(CaptureRecord(fileURL: nil, pixelWidth: 4, pixelHeight: 2, appName: nil))

          for record in oldRecords {
              let thumbnail = try thumbnailURL(coordinator, record)
              let file = try #require(record.fileURL)
              #expect(coordinator.history.record(id: record.id) == nil)
              #expect(!exists(thumbnail))
              #expect(exists(file))
          }
          #expect(coordinator.history.record(id: unsentID) != nil)
          #expect(exists(unsentFile))
          #expect(world.factory.askedConfigs.isEmpty)
      }
  ```
- [ ] Run `CoordinatorDeleteTests` alone, then the full suite: `Test run with 2180 tests in 181 suites passed`.
- [ ] Commit: `test: checklist delete cases on the coordinator`.

### Task 3: `CoordinatorUploadTests` [integration]

**Files:** modify `TidyShotTests/CoordinatorUploadTests.swift`.

**Steps:**
- [ ] Add the nine tests at the end of the struct. They use the suite's helpers (`pendingFile`, `addRecording`, `addPendingImage`, `storedState`, `writeSidecar`, `isUploaded`, `exists`):
  ```swift
      /// phase-2 :39. While an upload runs, the card is pushed `.uploading` with a fraction between 0 and 1, then
      /// `.uploaded`. A recording in parts with part 3 held, so the bar has moved and nothing ends the upload
      /// before the test has seen it (D8). How the ring draws the fraction is
      /// `QuickAccessModelTests.uploadingShowsTheFraction`.
      @Test func anUploadShowsItsFractionOnTheCardThenUploaded() async throws {
          defer { world.removeAll() }
          world.multipartPlan = MultipartPlan(threshold: 1_048_576, partSize: 262_144, inFlight: 1)
          destination.state.withLock { $0.holdingPart = 3 }
          let coordinator = world.makeCoordinator()
          let id = UUID()
          let file = try pendingFile(in: coordinator, id: id, byteCount: mib)
          addRecording(to: coordinator, id: id, file: file, byteCount: mib)

          coordinator.retryUpload(recordID: id)
          try await eventually {
              world.cards.updates(for: id).contains { state in
                  if case .uploading(let fraction) = state { return fraction > 0 && fraction < 1 }
                  return false
              }
          }
          destination.releaseParts()
          try await eventually { isUploaded(coordinator, id) }

          let uploaded = try #require(coordinator.history.record(id: id)?.uploadState)
          let updates = world.cards.updates(for: id)
          #expect(updates.first == .uploading(fraction: 0))
          #expect(updates.last == uploaded)
      }

      /// phase-2 :49, recording-r1 :279. Retry succeeds and copies the URL, and a screenshot's URL replaces the
      /// clipboard even after something else was copied meanwhile.
      @Test(arguments: [false, true])
      func aScreenshotsURLReplacesTheClipboardEvenAfterACopyElsewhere(clipboardMoved: Bool) async throws {
          defer { world.removeAll() }
          let coordinator = world.makeCoordinator()
          let record = try addPendingImage(to: coordinator)
          if clipboardMoved {
              world.clipboard.changeCount += 1
          }

          coordinator.retryUpload(recordID: record.id)
          try await eventually { isUploaded(coordinator, record.id) }

          let url = try #require(coordinator.history.record(id: record.id)?.uploadedURL)
          #expect(world.clipboard.copies == [.url(url)])
          #expect(world.notifier.calls.contains(.uploaded(url: url, copied: true)))
      }

      /// phase-3 :46, small-tweaks :19. An upload-only screenshot whose upload fails reads failed and keeps
      /// `pending/<id>.png` and its size; Retry Failed Uploads sends it, and the pending file goes.
      @Test func aFailedUploadOnlyImageKeepsItsPendingFileAndSizeUntilARetrySendsIt() async throws {
          defer { world.removeAll() }
          destination.state.withLock {
              $0.failuresRemaining = 1
              $0.failure = .httpStatus(403, body: "AccessDenied: Access Denied")
          }
          let coordinator = world.makeCoordinator()
          let record = try addPendingImage(to: coordinator)
          let pending = try #require(record.fileURL)
          let size = try #require(record.byteCount)

          coordinator.retryUpload(recordID: record.id)
          try await eventually {
              coordinator.history.record(id: record.id)?.uploadState
                  == .failed(message: "Server returned HTTP 403: AccessDenied: Access Denied")
          }
          #expect(coordinator.history.record(id: record.id)?.byteCount == size)
          #expect(exists(pending))

          coordinator.retryFailedUploads()
          try await eventually { isUploaded(coordinator, record.id) }
          #expect(!exists(pending))
          #expect(coordinator.history.record(id: record.id)?.fileURL == nil)
      }

      /// phase-3 :59. A retried upload lands under the capture's own date, with a counter drawn when the retry
      /// starts; an upload-only capture taken while no destination existed gets a real counter, not 0, when
      /// it is retried.
      @Test func aRetryIsNamedForTheCapturesDateWithANewlyDrawnCounter() async throws {
          defer { world.removeAll() }
          var config = CoordinatorWorld.config
          config.keyTemplate = "{date}/{counter}"
          world.settings.s3Config = config
          let coordinator = world.makeCoordinator()
          let taken = Date(timeIntervalSinceNow: -3 * 86_400)
          let day = TemplateExpander().expand("{date}", context: TemplateContext(date: taken), style: .objectKey)
          let png = try CoordinatorWorld.pngData(width: 4, height: 2)
          let oldID = UUID()
          let oldFile = try coordinator.pendingFiles.write(png, id: oldID, ext: "png")
          coordinator.history.add(CaptureRecord(id: oldID, timestamp: taken, fileURL: oldFile, fileIsTemporary: true,
                                                pixelWidth: 4, pixelHeight: 2, appName: nil,
                                                uploadState: .failed(message: "Upload was interrupted.")))
          let before = world.settings.currentCounter

          coordinator.retryUpload(recordID: oldID)
          try await eventually { isUploaded(coordinator, oldID) }
          #expect(coordinator.history.record(id: oldID)?.uploadedKey == "\(day)/\(before + 1).png")
          #expect(world.settings.currentCounter == before + 1)

          // Taken while no destination was set up: its retry fails as not configured, then, once
          // credentials exist, draws a counter.
          try world.credentials.delete(account: KeychainCredentialStore.defaultAccount)
          let notConfigured = UploadError.notConfigured.localizedDescription
          let waiting = try addPendingImage(to: coordinator, state: .failed(message: notConfigured))
          coordinator.retryUpload(recordID: waiting.id)
          #expect(coordinator.history.record(id: waiting.id)?.uploadState == .failed(message: notConfigured))
          try world.credentials.save(CoordinatorWorld.awsCredentials, account: KeychainCredentialStore.defaultAccount)
          coordinator.retryUpload(recordID: waiting.id)
          try await eventually { isUploaded(coordinator, waiting.id) }
          let key = try #require(coordinator.history.record(id: waiting.id)?.uploadedKey)
          #expect(key.hasSuffix("/\(before + 2).png"))
          #expect(!key.hasSuffix("/0.png"))
      }

      /// recording-r4 :352 (call 9). A resumed template upload whose key another capture took (the key holds an
      /// object of another size) starts again under a new key named with a counter of 0, and draws no counter.
      @Test func aResumedTemplateJobWhoseKeyIsTakenRedrawsItWithCounterZero() async throws {
          defer { world.removeAll() }
          var config = CoordinatorWorld.config
          config.keyTemplate = "s/{counter}-{random:6}"
          world.settings.s3Config = config
          destination.state.withLock { $0.objectSizes["s/STORED.mp4"] = 5 }
          let coordinator = world.makeCoordinator()
          let id = UUID()
          let file = try pendingFile(in: coordinator, id: id, byteCount: mib)
          try writeSidecar(coordinator, id: id)
          addRecording(to: coordinator, id: id, file: file, byteCount: mib, multipart: try storedState(of: file))
          let counter = world.settings.currentCounter

          coordinator.retryUpload(recordID: id)
          try await eventually { isUploaded(coordinator, id) }

          let key = try #require(coordinator.history.record(id: id)?.uploadedKey)
          #expect(key.hasPrefix("s/0-"))
          #expect(world.logLines.contains("Upload: \(file.lastPathComponent) key taken, starting again"))
          #expect(world.settings.currentCounter == counter)
      }

      /// phase-3 :63. Forget Credentials while an upload runs: that upload still finishes and copies its URL, the
      /// menu bar icon (`isUploading`) goes back, and the replaced lane drains.
      @Test func forgettingCredentialsMidUploadLetsThatUploadFinish() async throws {
          defer { world.removeAll() }
          destination.state.withLock { $0.holdingUploadsRemaining = 1 }
          let coordinator = world.makeCoordinator()
          let record = try addPendingImage(to: coordinator)
          coordinator.retryUpload(recordID: record.id)
          try await eventually { destination.state.withLock { $0.heldUploads.count } == 1 }

          try world.credentials.delete(account: KeychainCredentialStore.defaultAccount)
          coordinator.destinationDidChange()
          // A held upload finishes on its release even when cancelled, and the queue then reports it uploaded, so
          // only the fake's cancel count shows that Forget Credentials left the upload running. A cancel the
          // queue (an actor) started would land after this call returns, so the check waits for started work
          // while the upload is still held, then releases it (D31).
          for _ in 0..<20 { await Task.yield() }
          try await Task.sleep(for: .milliseconds(50))
          #expect(destination.state.withLock { $0.heldUploadCancellations } == 0)
          #expect(coordinator.uploadingIDs.contains(record.id))
          destination.releaseUploads()
          try await eventually { isUploaded(coordinator, record.id) }
          #expect(destination.state.withLock { $0.heldUploadCancellations } == 0)
          let url = try #require(coordinator.history.record(id: record.id)?.uploadedURL)
          #expect(world.clipboard.copies.last == .url(url))
          #expect(!coordinator.isUploading)
          try await world.clock.run(until: { coordinator.drainingQueues.isEmpty })
      }

      /// phase-4a :126, phase-4a :128. Upload as New sends the capture under a new template key, copies the new link
      /// and deletes the old object; the same after an interrupted replace read back at a relaunch, whose link
      /// is its prior upload.
      @Test(arguments: [false, true])
      func uploadAsNewCopiesTheNewLinkAndDeletesTheOldObject(afterAnInterruptedReplace: Bool) async throws {
          defer { world.removeAll() }
          let first = world.makeCoordinator()
          let oldURL = URL(string: "https://snap.tky.io/s/OLD.png")!
          let record: CaptureRecord
          if afterAnInterruptedReplace {
              let prior = PriorUpload(url: oldURL, key: "s/OLD.png", location: world.location, isReplace: true)
              record = try addPendingImage(to: first, state: .uploading(fraction: 0.4), priorUpload: prior,
                                           uploadIsStale: true)
          } else {
              record = try addPendingImage(to: first, state: .uploaded(url: oldURL, key: "s/OLD.png"), uploadIsStale: true)
              first.history.update(id: record.id) { $0.objectLocation = world.location }
          }
          // The relaunch: an upload that was running reads as interrupted, its link kept.
          let coordinator = world.makeCoordinator()
          coordinator.history.load()
          let current = try #require(coordinator.history.record(id: record.id))
          #expect(current.linkURL == oldURL)
          let plan = EditorUploadPlan.plan(record: current, currentLocation: world.location, others: [], asNew: true)
          #expect(plan == .newObject(supersede: ObjectRef(key: "s/OLD.png", location: world.location), notice: nil))

          let payload = try coordinator.uploadPayload(for: current)
          let target = try #require(coordinator.makeDestination())
          coordinator.startPlannedUpload(recordID: record.id, plan: plan, payload: payload, destination: target)
          try await eventually { isUploaded(coordinator, record.id) }

          let uploaded = try #require(coordinator.history.record(id: record.id))
          let newKey = try #require(uploaded.uploadedKey)
          let newURL = try #require(uploaded.uploadedURL)
          #expect(newKey != "s/OLD.png")
          #expect(destination.state.withLock { $0.uploads.map(\.key) } == [newKey])
          #expect(world.clipboard.copies.last == .url(newURL))
          try await eventually { destination.state.withLock { $0.deletedKeys } == ["s/OLD.png"] }
      }

      /// phase-4a :134. A quit during a replace leaves the record uploading; after the relaunch it reads failed and
      /// its link still copies, and Retry Failed Uploads PUTs the link's own key again with `no-cache`, so the
      /// URL is unchanged.
      @Test func anInterruptedReplaceRetriesOverItsOwnKeyAfterARelaunch() async throws {
          defer { world.removeAll() }
          let first = world.makeCoordinator()
          let oldURL = URL(string: "https://snap.tky.io/s/OLD.png")!
          let prior = PriorUpload(url: oldURL, key: "s/OLD.png", location: world.location, isReplace: true)
          let record = try addPendingImage(to: first, state: .uploading(fraction: 0.4), priorUpload: prior,
                                           uploadIsStale: true)
          let coordinator = world.makeCoordinator()
          coordinator.history.load()
          #expect(coordinator.history.record(id: record.id)?.uploadState == .failed(message: "Upload was interrupted."))
          #expect(coordinator.history.record(id: record.id)?.linkURL == oldURL)

          coordinator.retryFailedUploads()
          try await eventually { isUploaded(coordinator, record.id) }

          let last = try #require(destination.state.withLock { $0.uploads.last })
          #expect(last.key == "s/OLD.png")
          #expect(last.cacheControl == "no-cache")
          #expect(coordinator.history.record(id: record.id)?.uploadState == .uploaded(url: oldURL, key: "s/OLD.png"))
      }

      /// phase-4a :142. The first replace of a launch posts the cache note, also with Show notification off; a second
      /// replace in that launch and an upload to a new object post none; after a relaunch the next replace
      /// posts it again.
      @Test func onlyTheFirstReplaceOfALaunchPostsTheCacheNote() async throws {
          defer { world.removeAll() }
          world.settings.showNotification = false
          let png = try CoordinatorWorld.pngData(width: 4, height: 2)
          let note = FakeNotifier.Call.notice(title: "Uploaded, URL copied", body: EditorUploadPlan.cacheNote)
          let record = CaptureRecord(fileURL: nil, pixelWidth: 4, pixelHeight: 2, appName: nil,
                                     uploadState: .uploaded(url: URL(string: "https://snap.tky.io/s/LINK.png")!,
                                                            key: "s/LINK.png"),
                                     objectLocation: world.location)
          var notices: [FakeNotifier.Call] {
              world.notifier.calls.filter { if case .notice = $0 { return true } else { return false } }
          }
          func upload(_ coordinator: AppCoordinator, _ plan: (CaptureRecord) -> EditorUploadPlan.Plan) async throws {
              let current = try #require(coordinator.history.record(id: record.id))
              let target = try #require(coordinator.makeDestination())
              coordinator.startPlannedUpload(recordID: record.id, plan: plan(current), payload: .data(png),
                                             destination: target)
              try await eventually { isUploaded(coordinator, record.id) && coordinator.uploadingIDs.isEmpty }
          }
          let replace: (CaptureRecord) -> EditorUploadPlan.Plan = { .replace(key: $0.uploadedKey ?? "") }

          let coordinator = world.makeCoordinator()
          coordinator.history.add(record)
          try await upload(coordinator, replace)
          #expect(notices == [note])
          try await upload(coordinator, replace)
          #expect(notices == [note])

          let relaunched = world.makeCoordinator()
          relaunched.history.load()
          try await upload(relaunched) { _ in .newObject(supersede: nil, notice: nil) }
          #expect(notices == [note])
          try await upload(relaunched, replace)
          #expect(notices == [note, note])
      }
  ```
- [ ] Run `CoordinatorUploadTests` alone, then the full suite: `Test run with 2189 tests in 181 suites passed`.
- [ ] Commit: `test: checklist upload cases on the coordinator`.

### Task 4: `CoordinatorSaveTests` [integration]

**Files:** create `TidyShotTests/CoordinatorSaveTests.swift`.

**Consumes:** Task 1 (the subtitle in `FakeNotifier.Call`), Task 2 (`storeSaveFolder()`).

**Steps:**
- [ ] Create the suite:
  ```swift
  import Foundation
  import Testing
  @testable import TidyShot

  /// The save funnels' shared tail and the recording funnel on a built coordinator (`finishSave`,
  /// `saveRecording`; recording design, After stopping and Clipboard after the upload; R2's privacy rule; R1's
  /// quit mode). Each recording is a few bytes in the world's temporary folder: the funnel moves its file and
  /// the fake destination never reads it. Overlay is off unless a test says otherwise, since a card on screen
  /// reads the screens.
  @Suite(.timeLimit(.minutes(1)))
  struct CoordinatorSaveTests {
      let world: CoordinatorWorld

      init() throws {
          world = try CoordinatorWorld()
          world.settings.showOverlay = false
      }

      var destination: FakeDestination { world.factory.standard }

      /// A finished recording of `bytes` bytes in the world's temporary folder, started now, so retention
      /// (which prunes against the real `Date()`) keeps its record.
      func makeRecording(_ kind: MediaKind = .video, bytes: Int = 3) throws -> Recording {
          let id = UUID()
          let url = world.temporaryDirectory.appending(path: "\(id.uuidString).\(kind.fileExtension)")
          try Data(repeating: 7, count: bytes).write(to: url)
          return Recording(id: id, fileURL: url, startedAt: Date(), pixelWidth: 1600, pixelHeight: 1000, duration: 10,
                           poster: nil, displayID: 1, mediaKind: kind)
      }

      /// `saveRecording`, with the recording counted in first, as the recorder's `.keep` does.
      @discardableResult
      func save(_ coordinator: AppCoordinator, _ recording: Recording, _ intent: CaptureIntent,
                mode: RecordingSaveMode = .normal, stopNotice: RecordingNotice? = nil, saveNotice: RecordingNotice? = nil,
                microphoneNote: RecordingNotice? = nil, cameraNote: RecordingNotice? = nil,
                highlightsNote: RecordingNotice? = nil, unmutedIntervals: [MuteInterval] = []) async -> CaptureRecord? {
          coordinator.recordingSavesInFlight = 1
          return await coordinator.saveRecording(recording, intent: intent, stopNotice: stopNotice, mode: mode,
                                                 saveNotice: saveNotice, microphoneNote: microphoneNote,
                                                 cameraNote: cameraNote, highlightsNote: highlightsNote,
                                                 unmutedIntervals: unmutedIntervals)
      }

      func isUploaded(_ coordinator: AppCoordinator, _ id: UUID) -> Bool {
          if case .uploaded = coordinator.history.record(id: id)?.uploadState { return true }
          return false
      }

      func exists(_ url: URL?) -> Bool {
          guard let url else { return false }
          return FileManager.default.fileExists(atPath: url.path(percentEncoded: false))
      }

      /// True when `url` sits directly in `folder`.
      func isIn(_ url: URL?, _ folder: URL) -> Bool {
          url?.deletingLastPathComponent().pathComponents == folder.pathComponents
      }

      /// Every string a notifier call carries.
      func texts(of call: FakeNotifier.Call) -> [String] {
          switch call {
          case .saved(let title, let file): [title, file]
          case .uploaded(let url, _): [url.absoluteString]
          case .error(let title, let message, let subtitle): [title, message] + [subtitle].compactMap { $0 }
          case .notice(let title, let body, let subtitle): [title, body] + [subtitle].compactMap { $0 }
          case .setUp, .held, .released, .waited: []
          }
      }

      nonisolated enum Cause: CaseIterable, Sendable {
          /// No credentials when it is saved; stored again before the retry.
          case noDestination
          /// The upload refused; the retry comes after a relaunch.
          case failingDestination
      }

      /// phase-2 :44. With Overlay off a capture shows no card and still uploads. The tail is `finishSave`, which a
      /// screenshot's save and a recording's share.
      @Test func aCaptureWithTheOverlayOffShowsNoCardAndStillUploads() async throws {
          defer { world.removeAll() }
          let coordinator = world.makeCoordinator()
          let id = UUID()
          let png = try CoordinatorWorld.pngData(width: 4, height: 2)
          let image = try CoordinatorWorld.image(width: 4, height: 2)
          let file = try coordinator.pendingFiles.write(png, id: id, ext: "png")
          let record = CaptureRecord(id: id, fileURL: file, fileIsTemporary: true, pixelWidth: 4, pixelHeight: 2,
                                     appName: nil, uploadState: .uploading(fraction: 0), byteCount: png.count)
          let target = coordinator.makeDestination()

          await coordinator.finishSave(record, image: image, scale: 1, captureDisplayID: 1, notConfiguredWarning: nil,
                                       showsCard: true, upload: target, payload: { .data(png) }, notification: .none)
          try await eventually { isUploaded(coordinator, id) }

          #expect(!world.cards.calls.contains(.show(id)))
          #expect(coordinator.latestCapture?.id == nil)
          #expect(destination.state.withLock { $0.uploads.count } == 1)
      }

      /// recording-r1 :94, recording-r1 :319. An upload-only recording that cannot upload waits in `pending/`,
      /// failed, with nothing on the clipboard and no `Recording saved` (with no destination, the warning says
      /// TidyShot keeps it); a Retry, after a relaunch too, uploads it and empties `pending/`.
      @Test(arguments: Cause.allCases)
      func anUploadOnlyRecordingThatCannotUploadWaitsInPendingUntilARetry(cause: Cause) async throws {
          defer { world.removeAll() }
          switch cause {
          case .noDestination:
              try world.credentials.delete(account: KeychainCredentialStore.defaultAccount)
          case .failingDestination:
              destination.state.withLock {
                  $0.failuresRemaining = 1
                  $0.failure = .httpStatus(403, body: "AccessDenied: Access Denied")
              }
          }
          // A folder is stored, so a file sent to the save folder by mistake lands in `<root>/Saved/` and fails
          // `isIn(pending, …)` below instead of opening the folder panel (D31).
          try world.storeSaveFolder()
          var coordinator = world.makeCoordinator()
          let recording = try makeRecording()

          let record = try #require(await save(coordinator, recording, CaptureIntent(action: .uploadOnly)))
          try await eventually { coordinator.history.record(id: record.id)?.isFailed == true }

          let pending = try #require(record.fileURL)
          #expect(isIn(pending, coordinator.pendingFiles.directory))
          #expect(pending.lastPathComponent == "\(recording.id.uuidString).mp4")
          #expect(exists(pending))
          #expect(world.clipboard.copies.isEmpty)
          #expect(!world.notifier.calls.contains { if case .saved = $0 { true } else { false } })
          switch cause {
          case .noDestination:
              #expect(world.notifier.calls.contains(.error(title: "Upload not configured",
                                                            message: RecordingSavePlan.uploadOnlyNotConfiguredWarning)))
              try world.credentials.save(CoordinatorWorld.awsCredentials, account: KeychainCredentialStore.defaultAccount)
          case .failingDestination:
              coordinator = world.makeCoordinator()
              coordinator.history.load()
          }
          coordinator.retryUpload(recordID: record.id)
          try await eventually { isUploaded(coordinator, record.id) }

          #expect(destination.state.withLock { $0.fileUploads.map(\.url.lastPathComponent) } == [pending.lastPathComponent])
          #expect(!exists(pending))
      }

      /// recording-r1 :277, recording-r2 :271. Upload and copy URL: with Also copy image on, a recording's file
      /// reference is on the clipboard meanwhile and its URL replaces it after, while nothing else was copied; a
      /// GIF uploads as `image/gif`, its URL leaves a copy made meanwhile alone with `Uploaded`, and a click then
      /// copies the link.
      @Test(arguments: zip([MediaKind.video, .gif], [false, true]))
      func aRecordingsURLReplacesItsFileReferenceOnlyWhileTheClipboardHoldsIt(kind: MediaKind,
                                                                              clipboardMoved: Bool) async throws {
          defer { world.removeAll() }
          world.settings.alsoCopyImageWhenUploading = kind == .video
          let folder = try world.storeSaveFolder()
          destination.state.withLock { $0.holdingUploadsRemaining = 1 }
          let coordinator = world.makeCoordinator()
          let recording = try makeRecording(kind)

          let record = try #require(await save(coordinator, recording, CaptureIntent(action: .upload)))
          let file = try #require(record.fileURL)
          #expect(isIn(file, folder))
          try await eventually { destination.state.withLock { $0.heldUploads.count } == 1 }
          if clipboardMoved {
              world.clipboard.changeCount += 1
          }
          destination.releaseUploads()
          try await eventually { isUploaded(coordinator, record.id) }

          let url = try #require(coordinator.history.record(id: record.id)?.uploadedURL)
          if clipboardMoved {
              #expect(world.clipboard.copies.isEmpty)
              #expect(world.notifier.calls.contains(.uploaded(url: url, copied: false)))
              #expect(destination.state.withLock { $0.fileUploads.map(\.contentType) } == ["image/gif"])
              coordinator.copyLinkOrFile(recordID: record.id)
              #expect(world.clipboard.copies == [.url(url)])
          } else {
              #expect(world.clipboard.copies == [.fileURL(file), .url(url)])
              #expect(world.notifier.calls.contains(.uploaded(url: url, copied: true)))
          }
      }

      /// recording-r1 :318. Upload and copy URL with no destination saves the recording as Save and copy image
      /// would: in the save folder with no upload, its file on the clipboard whatever the copy setting says,
      /// `Recording saved`, and the `Upload not configured` warning.
      @Test func uploadWithNoDestinationSavesTheRecordingAndCopiesItsFile() async throws {
          defer { world.removeAll() }
          world.settings.copyImageToClipboard = false
          try world.credentials.delete(account: KeychainCredentialStore.defaultAccount)
          let folder = try world.storeSaveFolder()
          let coordinator = world.makeCoordinator()
          let recording = try makeRecording()

          let record = try #require(await save(coordinator, recording, CaptureIntent(action: .upload)))

          let file = try #require(record.fileURL)
          #expect(isIn(file, folder))
          #expect(!record.fileIsTemporary)
          #expect(record.uploadState == .none)
          #expect(world.clipboard.copies == [.fileURL(file)])
          #expect(world.notifier.calls == [.error(title: "Upload not configured",
                                                   message: RecordingSavePlan.uploadNotConfiguredWarning),
                                           .saved(title: "Recording saved", file: file.lastPathComponent)])
          #expect(world.factory.askedConfigs.isEmpty)
      }

      /// recording-r1 :332 (gap 5). Quit mode, for every action and with Overlay on: no folder prompt, no upload, no
      /// card, no notice and no warning, while the clipboard rule (`RecordingSavePlan` in quit mode) and the
      /// shutter still apply. An uploading action still reads its destination; nothing is sent (D7).
      @Test func quitModeSkipsTheCardTheUploadAndTheNoticesForEveryAction() async throws {
          defer { world.removeAll() }
          world.settings.showOverlay = true
          let folder = try world.storeSaveFolder()
          let coordinator = world.makeCoordinator()
          // `copyOnly` is the URL command's `action=copy`, which a recording's save ignores.
          let intents = [CaptureIntent(action: .save), CaptureIntent(action: .save, copyOnly: true),
                         CaptureIntent(action: .upload), CaptureIntent(action: .uploadOnly)]
          var expected: [FakeClipboard.Copy] = []

          for (index, intent) in intents.enumerated() {
              let recording = try makeRecording()
              let record = try #require(await save(coordinator, recording, intent, mode: .quit))
              let file = try #require(record.fileURL)
              let plan = RecordingSavePlan.make(action: intent.action, hasDestination: true,
                                                result: intent.action == .uploadOnly ? .pending : .saveFolder,
                                                copyImage: world.settings.copyImageToClipboard,
                                                alsoCopyImage: world.settings.alsoCopyImageWhenUploading, quitMode: true)
              if plan.copiesFileReference {
                  expected.append(.fileURL(file))
              }
              #expect(isIn(file, intent.action == .uploadOnly ? coordinator.pendingFiles.directory : folder))
              #expect(world.clipboard.copies == expected)
              #expect(world.shutterCount == index + 1)
          }

          #expect(expected.count == 2)
          #expect(!world.cards.calls.contains { if case .show = $0 { true } else { false } })
          #expect(world.notifier.calls.isEmpty)
          #expect(destination.state.withLock { $0.uploadAttempts } == 0)
          #expect(coordinator.uploadingIDs.isEmpty)
      }

      /// recording-r2 :312, in part. A recording whose muting failed, for Save with no folder set and with one,
      /// Upload and Upload only: no folder is asked for, the file is in `pending/` and not in the save folder,
      /// nothing uploads, the clipboard is unchanged, and `Sound not muted` posts; Retry Failed Uploads posts
      /// nothing and a press on the card stages nothing to drag. By hand: the `-MuteFailure` run itself, the card's
      /// tool tip and the mark after a relaunch; the card's text and what it offers are
      /// `QuickAccessModelTests.aMarkedRecordSaysSoundNotMutedAndOffersOpenTrimAndDeleteOnly` (D16).
      @Test func aMarkedRecordingStaysInPendingForEveryActionAndNeverLeaves() async throws {
          defer { world.removeAll() }
          let coordinator = world.makeCoordinator()
          let marked = [MuteInterval(start: 1, end: 2)]
          var records: [CaptureRecord] = []
          // Save first with no folder set: a marked save never asks for one. Gated, since a save that asked would
          // wait on a real folder panel; the panel is then closed as Cancel, so the save returns (D31).
          let unsaved = try makeRecording()
          let first = Task { await save(coordinator, unsaved, CaptureIntent(action: .save), unmutedIntervals: marked) }
          let watch = TaskWatch(first)
          do {
              try await eventually { watch.hasReturned }
          } catch {
              world.saveLocation.cancelFolderChoice()
              throw error
          }
          records.append(try #require(await first.value))
          #expect(world.saveLocation.currentURL == nil)
          try world.storeSaveFolder()
          for action in [AfterCaptureAction.save, .upload, .uploadOnly] {
              let recording = try makeRecording()
              records.append(try #require(await save(coordinator, recording, CaptureIntent(action: action),
                                                     unmutedIntervals: marked)))
          }

          for record in records {
              #expect(record.fileIsTemporary)
              #expect(isIn(record.fileURL, coordinator.pendingFiles.directory))
              #expect(exists(record.fileURL))
              #expect(record.uploadState == .none)
              #expect(record.uploadBlockedReason == CaptureRecord.soundNotMutedBody)
          }
          #expect(world.factory.askedConfigs.isEmpty)
          #expect(world.clipboard.copies.isEmpty)
          #expect(world.notifier.calls == Array(repeating: FakeNotifier.Call.error(title: CaptureRecord.soundNotMutedTitle,
                                                                   message: CaptureRecord.soundNotMutedBody), count: 4))

          coordinator.retryFailedUploads()
          let shown = records[0]
          world.cards.showing.insert(shown.id)
          coordinator.prepareDragFile(recordID: shown.id)
          for _ in 0..<20 { await Task.yield() }
          #expect(world.notifier.calls.count == 4)
          #expect(coordinator.dragFiles.stagedFile(id: shown.id) == nil)
          #expect(world.cards.dragFiles(for: shown.id).isEmpty)
          #expect(destination.state.withLock { $0.uploadAttempts } == 0)
      }

      /// recording-r2 :608, recording-r3 :367. After Stop the notices come in one order: the save's own (`GIF not
      /// made`), `Recording stopped`, the microphone note, the camera note, the highlights note; and `GIF not
      /// made` posts with Show notification off.
      @Test func noticesAfterStopComeInOrderWhateverShowNotificationSays() async throws {
          defer { world.removeAll() }
          world.settings.showNotification = false
          // Stored so an upload-only save sent to the save folder by mistake opens no folder panel (D31).
          try world.storeSaveFolder()
          let coordinator = world.makeCoordinator()
          let notMade = GIFConversion.notMade(GIFMakerError.couldNotRead.localizedDescription)
          let stopped = RecordingNotice(title: "Recording stopped", body: "The display was disconnected.")
          let microphone = RecordingNotice(title: MicrophoneChoice.recordedWithoutTitle, body: MicrophoneChoice.noInputText)
          let camera = RecordingNotice(title: "Recorded without the camera", body: "No camera is connected.")
          let highlights = RecordingNotice(title: "Recorded without click highlights", body: "Input Monitoring is off.")
          let recording = try makeRecording()

          let record = try #require(await save(coordinator, recording, CaptureIntent(action: .uploadOnly),
                                               stopNotice: stopped, saveNotice: notMade, microphoneNote: microphone,
                                               cameraNote: camera, highlightsNote: highlights))
          try await eventually { isUploaded(coordinator, record.id) }

          #expect(world.notifier.errors.map(\.title) == [notMade.title, stopped.title, microphone.title, camera.title,
                                                          highlights.title])
          #expect(world.notifier.errors.first?.message == notMade.body)
      }

      /// recording-r2 :632, in part. A GIF's size is the GIF file's own after its move into the save folder. By
      /// hand: the MP4's size after a failed conversion, and the rows against `ls -l` (a muted recording's size
      /// is `VideoValidationTests.aRewrittenFileReadsItsNewSize`, a trimmed one's
      /// `CaptureRecordTests.aTrimsWriteRecordsTheTrimmedFile`).
      @Test func aGIFsSizeIsTheMovedFilesSize() async throws {
          defer { world.removeAll() }
          let folder = try world.storeSaveFolder()
          let coordinator = world.makeCoordinator()
          let recording = try makeRecording(.gif, bytes: 1_234)

          let record = try #require(await save(coordinator, recording, CaptureIntent(action: .save)))

          let file = try #require(record.fileURL)
          #expect(isIn(file, folder))
          #expect(file.pathExtension == "gif")
          #expect(record.mediaKind == .gif)
          let size = try FileManager.default.attributesOfItem(atPath: file.path(percentEncoded: false))[.size] as? Int
          #expect(record.byteCount == size)
          #expect(record.byteCount == 1_234)
      }

      /// recording-r4 :313 (gap 6). A recording's notices never name the URL command's sender: not its stop notice,
      /// not its upload's.
      @Test func recordingNoticesNeverNameTheSender() async throws {
          defer { world.removeAll() }
          // Stored so an upload-only save sent to the save folder by mistake opens no folder panel (D31).
          try world.storeSaveFolder()
          let coordinator = world.makeCoordinator()
          let stopped = RecordingNotice(title: "Recording stopped", body: "The display was disconnected.")
          let recording = try makeRecording()

          let record = try #require(await save(coordinator, recording,
                                               CaptureIntent(action: .uploadOnly, sender: "Raycast"), stopNotice: stopped))
          try await eventually { isUploaded(coordinator, record.id) }

          #expect(world.notifier.calls.contains(.error(title: stopped.title, message: stopped.body)))
          #expect(world.notifier.calls.contains { if case .uploaded = $0 { true } else { false } })
          for call in world.notifier.calls {
              #expect(!texts(of: call).contains { $0.contains("Raycast") }, "\(call)")
          }
      }
  }
  ```
- [ ] Run `CoordinatorSaveTests` alone, then the full suite: `Test run with 2198 tests in 182 suites passed`.
- [ ] Commit: `test: checklist save cases on the coordinator`.

### Task 5: `CoordinatorDragOutTests` [integration]

**Files:** modify `TidyShotTests/CoordinatorDragOutTests.swift`.

**Steps:**
- [ ] After `downloadsFolder`, add the helpers:
  ```swift
      /// A recording in `pending/` of 3 bytes, added to history: kept in TidyShot (`.none`) unless `state`
      /// says otherwise.
      func addPendingVideo(to coordinator: AppCoordinator,
                           state: CaptureRecord.UploadState = .none) throws -> CaptureRecord {
          let id = UUID()
          let url = coordinator.pendingFiles.directory.appending(path: "\(id.uuidString).mp4")
          try CoordinatorWorld.writeSparseFile(at: url, byteCount: 3)
          let record = CaptureRecord(id: id, fileURL: url, fileIsTemporary: true, pixelWidth: 1600, pixelHeight: 1000,
                                     appName: nil, uploadState: state, mediaKind: .video, durationSeconds: 10,
                                     byteCount: 3)
          coordinator.history.add(record)
          return record
      }

      func exists(_ url: URL) -> Bool {
          FileManager.default.fileExists(atPath: url.path(percentEncoded: false))
      }

      /// The file Copy File put on the clipboard, when that is the clipboard's only write.
      var copiedFile: URL? {
          guard world.clipboard.copies.count == 1, case .fileURL(let url) = world.clipboard.copies[0] else { return nil }
          return url
      }

      /// The names in the record's drag folder.
      func dragFolderNames(_ coordinator: AppCoordinator, _ id: UUID) -> [String] {
          let path = coordinator.dragFiles.folder(for: id).path(percentEncoded: false)
          return ((try? FileManager.default.contentsOfDirectory(atPath: path)) ?? []).filter { !$0.hasPrefix(".") }
      }
  ```
- [ ] Replace `aFailureWithResumeDataKeepsItWithTheSigningTime` (the extension):
  ```swift
      /// 8 (harness design 3.1). R4 checklist, Drag-out: Wi-Fi off shows `Download failed` with the error and posts
      /// nothing; the resume data is kept with the time the request was signed (plan Gap 16 of R4).
      /// recording-r4 :361 (call 16): that time is read before the first call, so a clock that moves while the
      /// transfer runs does not change it.
      @Test func aFailureWithResumeDataKeepsItWithTheSigningTime() async throws {
          defer { world.removeAll() }
          let coordinator = world.makeCoordinator()
          let record = showingUploadedRecording(in: coordinator)
          let data = try resumeData(partial: "CFNetworkDownload_A.tmp")
          let error = failure(resumeData: data)
          destination.state.withLock {
              $0.downloadOutcome = .fails(error)
              $0.holdsDownloads = true
          }
          let signedAt = world.date

          let task = try startDownload(coordinator, record)
          try await eventually { destination.state.withLock { $0.downloads.count } == 1 }
          world.date = signedAt.addingTimeInterval(300)
          destination.releaseDownloads()

          #expect(await task.value == nil)
          #expect(world.cards.downloads(for: record.id).last == .failed(error.localizedDescription))
          #expect(world.logLines.contains("Drag-out download for \(record.id) failed: \(error.localizedDescription)"))
          let kept = try #require(coordinator.dragDownloadResume[record.id])
          #expect(kept.data == data)
          #expect(kept.signedAt == signedAt)
          #expect(world.notifier.calls.isEmpty)
      }
  ```
- [ ] Add the seven tests at the end of the struct:
  ```swift
      /// recording-r1 :282, recording-r1 :334 (gap 7, the upload). Copy File on a pending video while it uploads puts
      /// a staged copy in `Drag/<id>` on the clipboard; at `.uploaded` the pending file goes and the staged copy
      /// stays, so the reference still pastes.
      @Test func aCopyFileStageOfAPendingVideoOutlivesItsUpload() async throws {
          defer { world.removeAll() }
          destination.state.withLock { $0.holdingUploadsRemaining = 1 }
          let coordinator = world.makeCoordinator()
          let record = try addPendingVideo(to: coordinator, state: .failed(message: "Upload was interrupted."))
          let pending = try #require(record.fileURL)
          world.cards.showing.insert(record.id)
          coordinator.retryUpload(recordID: record.id)
          try await eventually { destination.state.withLock { $0.heldUploads.count } == 1 }

          await coordinator.copyFile(recordID: record.id)
          let staged = try #require(copiedFile)
          #expect(staged.deletingLastPathComponent().lastPathComponent == record.id.uuidString)

          destination.releaseUploads()
          try await eventually { coordinator.history.record(id: record.id)?.uploadedKey != nil }
          #expect(!exists(pending))
          #expect(coordinator.history.record(id: record.id)?.fileURL == nil)
          #expect(exists(staged))
          #expect(dragFolderNames(coordinator, record.id) == [staged.lastPathComponent])
      }

      /// recording-r1 :283, recording-r1 :334 (gap 7, the clean-up). After the card closes, the one-minute clean-up
      /// waits again, a minute at a time, while the clipboard still holds Copy File's reference, and removes the
      /// copy once the clipboard has moved on.
      @Test func theCleanUpWaitsWhileTheClipboardHoldsTheCopyFileReference() async throws {
          defer { world.removeAll() }
          let coordinator = world.makeCoordinator()
          let record = try addPendingVideo(to: coordinator)
          world.cards.showing.insert(record.id)
          await coordinator.copyFile(recordID: record.id)
          let staged = try #require(copiedFile)
          let folder = coordinator.dragFiles.folder(for: record.id)

          world.cards.close(recordID: record.id, reason: .user)
          try await world.clock.run(for: .seconds(60))
          #expect(exists(staged))
          try await world.clock.run(for: .seconds(60))
          #expect(exists(staged))

          world.clipboard.changeCount += 1
          try await world.clock.run(for: .seconds(60))
          try await eventually { !exists(folder) }
      }

      /// recording-r1 :284, recording-r1 :334 (gap 7, no card). Copy File from the row of a video kept in TidyShot,
      /// with no card showing, schedules the clean-up itself: once the clipboard has moved on, the copy goes a
      /// minute later, though no card closed.
      @Test func aCopyFileWithNoCardSchedulesItsOwnCleanUp() async throws {
          defer { world.removeAll() }
          let coordinator = world.makeCoordinator()
          let record = try addPendingVideo(to: coordinator)

          await coordinator.copyFile(recordID: record.id)
          let staged = try #require(copiedFile)
          #expect(exists(staged))
          #expect(coordinator.dragCleanups[record.id] != nil)

          world.clipboard.changeCount += 1
          try await world.clock.run(for: .seconds(60))
          try await eventually { !exists(coordinator.dragFiles.folder(for: record.id)) }
          #expect(world.cards.closes.isEmpty)
      }

      /// recording-r1 :285. Copy File within the minute after the card closed cancels the clean-up that was due, as a
      /// press does, and schedules its own, so the copy is still there a minute after the close. With the
      /// clipboard unchanged the old clean-up would wait again too, so the cancel is read off its task (D11).
      @Test func aCopyFileWithinTheMinuteReplacesTheCloseCleanUp() async throws {
          defer { world.removeAll() }
          let coordinator = world.makeCoordinator()
          let record = try addPendingVideo(to: coordinator)
          world.cards.showing.insert(record.id)
          world.cards.close(recordID: record.id, reason: .user)
          let due = try #require(coordinator.dragCleanups[record.id])
          try await world.clock.run(for: .seconds(30))

          await coordinator.copyFile(recordID: record.id)
          let staged = try #require(copiedFile)
          #expect(due.isCancelled)
          let own = try #require(coordinator.dragCleanups[record.id])
          #expect(own != due)

          try await world.clock.run(for: .seconds(30))
          #expect(exists(staged))
      }

      /// recording-r1 :289. With `{counter}` in Recording file name, a press on a pending video's card after Copy
      /// File reuses the staged copy under the name it has, though the name the press works out has moved on, so
      /// the clipboard's file still pastes.
      @Test func aDragPressAfterCopyFileReusesTheStagedCopy() async throws {
          defer { world.removeAll() }
          world.settings.recordingFileNameTemplate = "Clip {counter}"
          let coordinator = world.makeCoordinator()
          let record = try addPendingVideo(to: coordinator)
          world.cards.showing.insert(record.id)
          await coordinator.copyFile(recordID: record.id)
          let staged = try #require(copiedFile)
          let handed = world.cards.dragFiles(for: record.id).count
          _ = world.settings.nextCounter()

          coordinator.prepareDragFile(recordID: record.id)
          try await eventually { world.cards.dragFiles(for: record.id).count == handed + 2 }

          #expect(world.cards.dragFiles(for: record.id).last??.lastPathComponent == staged.lastPathComponent)
          #expect(dragFolderNames(coordinator, record.id) == [staged.lastPathComponent])
      }

      /// phase-6a :183. A restored upload-only card with no local file downloads quietly into its drag folder under
      /// the key's last part (`aSIS7.png` for `shots/aSIS7.png`), posting nothing; with a copy of another name
      /// already there, the folder ends with one file under the key's name.
      @Test func aRestoredUploadOnlyCardsQuietDownloadIsNamedForItsKey() async throws {
          defer { world.removeAll() }
          let png = try CoordinatorWorld.pngData(width: 4, height: 2)
          destination.state.withLock { $0.downloadedData = png }
          let coordinator = world.makeCoordinator()
          let record = CaptureRecord(fileURL: nil, pixelWidth: 4, pixelHeight: 2, appName: nil,
                                     uploadState: .uploaded(url: URL(string: "https://snap.tky.io/shots/aSIS7.png")!,
                                                            key: "shots/aSIS7.png"),
                                     objectLocation: world.location)
          coordinator.history.add(record)
          world.cards.showing.insert(record.id)

          coordinator.prepareDragFile(recordID: record.id)
          try await eventually { world.cards.dragFiles(for: record.id).last??.lastPathComponent == "aSIS7.png" }
          #expect(destination.state.withLock { $0.dataDownloadKeys } == ["shots/aSIS7.png"])
          #expect(world.notifier.calls.isEmpty)
          #expect(dragFolderNames(coordinator, record.id) == ["aSIS7.png"])

          // An earlier copy under another name.
          coordinator.removeDragFolder(record.id)
          let folder = coordinator.dragFiles.folder(for: record.id)
          try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
          try png.write(to: folder.appending(path: "Screenshot 2026-10-30.png"))
          let handed = world.cards.dragFiles(for: record.id).count

          coordinator.prepareDragFile(recordID: record.id)
          try await eventually { world.cards.dragFiles(for: record.id).count == handed + 2 }
          #expect(world.cards.dragFiles(for: record.id).last??.lastPathComponent == "aSIS7.png")
          #expect(dragFolderNames(coordinator, record.id) == ["aSIS7.png"])
      }

      /// recording-r4 :291. After the card closes, the 60 s clean-up removes a downloaded drag copy, and a restored
      /// card downloads again on its next drag.
      @Test func theCleanUpRemovesADownloadedCopyAndALaterDragDownloadsAgain() async throws {
          defer { world.removeAll() }
          let coordinator = world.makeCoordinator()
          let record = showingUploadedRecording(in: coordinator)
          destination.state.withLock { $0.downloadOutcome = .lands(bytes: 1_000) }
          let task = try startDownload(coordinator, record)
          let landed = try #require(await task.value)
          #expect(exists(landed))

          world.cards.close(recordID: record.id, reason: .user)
          try await world.clock.run(for: .seconds(60))
          try await eventually { !exists(coordinator.dragFiles.folder(for: record.id)) }

          world.cards.showing.insert(record.id)
          let again = try startDownload(coordinator, record)
          _ = await again.value
          #expect(destination.state.withLock { $0.downloads.count } == 2)
      }
  ```
- [ ] Run `CoordinatorDragOutTests` alone, then the full suite: `Test run with 2205 tests in 182 suites passed`.
- [ ] Commit: `test: checklist drag-out and Copy File cases on the coordinator`.

### Task 6: `CoordinatorRecordActionsTests` and `CoordinatorEditorTests` [integration]

**Files:** create `TidyShotTests/CoordinatorRecordActionsTests.swift`, `TidyShotTests/CoordinatorEditorTests.swift`.

**Consumes:** Task 1 (`dataDownloadFailures`), Task 2 (`storeSaveFolder()`).

**Steps:**
- [ ] Create `CoordinatorRecordActionsTests.swift`:
  ```swift
  import Foundation
  import Testing
  @testable import TidyShot

  /// The actions on a record from a card, a pin or a Recent Captures row (`AppCoordinator+RecordActions`):
  /// Copy URL and the row's click, Copy Image, Copy File, and the Save As… suggestion and write. The Save
  /// panel is the system's and is never built here.
  @Suite(.timeLimit(.minutes(1)))
  struct CoordinatorRecordActionsTests {
      let world: CoordinatorWorld
      let key = "s/SHOT.png"

      init() throws {
          world = try CoordinatorWorld()
      }

      var destination: FakeDestination { world.factory.standard }
      var link: URL { URL(string: "https://snap.tky.io/\(key)")! }

      /// An uploaded capture with no local file, at the world's location.
      func uploadedOnly() -> CaptureRecord {
          CaptureRecord(fileURL: nil, pixelWidth: 4, pixelHeight: 2, appName: nil,
                        uploadState: .uploaded(url: link, key: key), objectLocation: world.location)
      }

      /// A PNG of 4 by 2 pixels written into `folder` as `name`.
      func writePNG(_ name: String, in folder: URL) throws -> URL {
          let url = folder.appending(path: name)
          try CoordinatorWorld.pngData(width: 4, height: 2).write(to: url)
          return url
      }

      nonisolated enum Source: CaseIterable, Sendable {
          /// Saved in the save folder, never uploaded.
          case savedFile
          /// Uploaded, its file kept in the save folder.
          case uploadedWithItsFile
          /// Upload only, uploaded: no local file.
          case uploadOnly
      }

      nonisolated enum Missing: CaseIterable, Sendable {
          /// Uploaded before Phase 3 (no stored location), its save-folder file deleted.
          case prePhase3Upload
          /// Saved and never uploaded, its file renamed in Finder.
          case renamedSavedFile
      }

      /// phase-2 :40, phase-2 :51, phase-3-1 :30, phase-3 :23. Copy URL and a row's click copy an uploaded capture's
      /// link, again after something else was copied; a saved capture that was never uploaded copies its file.
      /// By hand (phase-3-1 :30, phase-3 :23): the menu closing, which is real menu tracking
      /// (`RecentCapturesMenu.afterMenusClose`).
      @Test func copyLinkOrFileCopiesTheLinkEachTimeOrTheSavedFile() {
          defer { world.removeAll() }
          let coordinator = world.makeCoordinator()
          let uploaded = uploadedOnly()
          coordinator.history.add(uploaded)
          let file = URL(filePath: "/Users/tim/Pictures/Shot.png")
          let saved = CaptureRecord(fileURL: file, pixelWidth: 4, pixelHeight: 2, appName: nil)
          coordinator.history.add(saved)

          coordinator.copyLinkOrFile(recordID: uploaded.id)
          world.clipboard.changeCount += 1
          coordinator.copyLinkOrFile(recordID: uploaded.id)
          coordinator.copyLinkOrFile(recordID: saved.id)

          #expect(world.clipboard.copies == [.url(link), .url(link), .fileURL(file)])
      }

      /// phase-6a :151, phase-3-1 :33 (with `aCopyImageWhoseDownloadFailsSaysCouldNotCopyImage`). Copy Image puts
      /// the PNG and its TIFF on the clipboard for each kind of capture: from the file when there is one,
      /// otherwise from a signed download that posts `Copying image…`; `Image copied` names the key, or the
      /// file of a capture never uploaded (D9).
      @Test(arguments: Source.allCases)
      func copyImageReadsTheFileOrDownloadsTheObject(source: Source) async throws {
          defer { world.removeAll() }
          destination.state.withLock { $0.downloadedData = (try? CoordinatorWorld.pngData(width: 4, height: 2)) ?? Data() }
          let folder = try world.storeSaveFolder()
          let coordinator = world.makeCoordinator()
          let record: CaptureRecord
          switch source {
          case .savedFile:
              let file = try writePNG("Shot.png", in: folder)
              record = CaptureRecord(fileURL: file, pixelWidth: 4, pixelHeight: 2, appName: nil)
          case .uploadedWithItsFile:
              let file = try writePNG("Shot.png", in: folder)
              record = CaptureRecord(fileURL: file, pixelWidth: 4, pixelHeight: 2, appName: nil,
                                     uploadState: .uploaded(url: link, key: key), objectLocation: world.location)
          case .uploadOnly:
              record = uploadedOnly()
          }
          coordinator.history.add(record)

          await coordinator.copyImage(recordID: record.id)

          #expect(world.clipboard.copies == [.pngAndTIFF])
          switch source {
          case .savedFile:
              #expect(world.notifier.calls == [.notice(title: "Image copied", body: "Shot.png")])
              #expect(destination.state.withLock { $0.dataDownloadKeys.isEmpty })
          case .uploadedWithItsFile:
              #expect(world.notifier.calls == [.notice(title: "Image copied", body: key)])
              #expect(destination.state.withLock { $0.dataDownloadKeys.isEmpty })
          case .uploadOnly:
              #expect(world.notifier.calls == [.notice(title: "Copying image…", body: "Downloading \(key)"),
                                               .notice(title: "Image copied", body: key)])
              #expect(destination.state.withLock { $0.dataDownloadKeys } == [key])
          }
      }

      /// phase-3-1 :33 (with `copyImageReadsTheFileOrDownloadsTheObject`). Copy Image of an upload-only capture whose
      /// download fails (Wi-Fi off) posts `Could not copy image` with the reason, after `Copying image…`, and
      /// copies nothing.
      @Test func aCopyImageWhoseDownloadFailsSaysCouldNotCopyImage() async {
          defer { world.removeAll() }
          let offline = URLError(.notConnectedToInternet)
          destination.state.withLock { $0.dataDownloadFailures = [offline] }
          let coordinator = world.makeCoordinator()
          let record = uploadedOnly()
          coordinator.history.add(record)

          await coordinator.copyImage(recordID: record.id)

          #expect(world.notifier.calls == [.notice(title: "Copying image…", body: "Downloading \(key)"),
                                           .error(title: "Could not copy image", message: offline.localizedDescription)])
          #expect(world.clipboard.copies.isEmpty)
          #expect(destination.state.withLock { $0.dataDownloadKeys } == [key])
      }

      /// phase-3-1 :34, phase-3-1 :35. Copy Image of a capture whose recorded file cannot be read and that has no
      /// upload to download from (one from before Phase 3 has no stored location) posts `Could not copy image`
      /// with `The local file could not be read.`, and downloads nothing.
      @Test(arguments: Missing.allCases)
      func copyImageOfAMissingFileWithNoUsableUploadSaysTheFileCouldNotBeRead(record missing: Missing) async throws {
          defer { world.removeAll() }
          let folder = try world.storeSaveFolder()
          let coordinator = world.makeCoordinator()
          let gone = folder.appending(path: "Shot.png")
          let record: CaptureRecord
          switch missing {
          case .prePhase3Upload:
              record = CaptureRecord(fileURL: gone, pixelWidth: 4, pixelHeight: 2, appName: nil,
                                     uploadState: .uploaded(url: link, key: key))
          case .renamedSavedFile:
              _ = try writePNG("Shot renamed.png", in: folder)
              record = CaptureRecord(fileURL: gone, pixelWidth: 4, pixelHeight: 2, appName: nil)
          }
          coordinator.history.add(record)

          await coordinator.copyImage(recordID: record.id)

          #expect(world.notifier.calls == [.error(title: "Could not copy image",
                                                   message: "The local file could not be read.")])
          #expect(world.clipboard.copies.isEmpty)
          #expect(destination.state.withLock { $0.dataDownloadKeys.isEmpty })
      }

      /// phase-4a :105. The Save As… suggestion of an uploaded upload-only capture is named from the file name
      /// template with the counter as it stands, and draws none, so the next capture's number is not skipped.
      @Test func saveAsSuggestionUsesTheCurrentCounterWithoutDrawingOne() {
          defer { world.removeAll() }
          world.settings.fileNameTemplate = "shot-{counter}"
          _ = world.settings.nextCounter()
          _ = world.settings.nextCounter()
          let coordinator = world.makeCoordinator()
          let record = uploadedOnly()
          coordinator.history.add(record)

          let suggestion = coordinator.saveAsSuggestion(recordID: record.id)

          #expect(suggestion.fileName == "shot-2.png")
          #expect(world.settings.currentCounter == 2)
      }

      /// phase-4a :108, in part. The Save As… write over an existing file replaces it and posts `Saved`; over a
      /// locked file it fails with `Not saved` and the reason, and the file is unchanged. By hand: the panel's
      /// Replace prompt, and the editor's unsaved dot staying (D16).
      @Test func saveAsReplacesAnExistingFileAndSaysNotSavedForALockedOne() async throws {
          defer { world.removeAll() }
          let coordinator = world.makeCoordinator()
          let png = try CoordinatorWorld.pngData(width: 4, height: 2)
          let existing = world.root.appending(path: "Existing.png")
          try Data("old".utf8).write(to: existing)

          let replaced = await coordinator.writeSaveAsCopy(png, to: existing)
          #expect(replaced)
          #expect(try Data(contentsOf: existing) == png)
          #expect(world.notifier.calls == [.saved(title: "Saved", file: "Existing.png")])

          let locked = world.root.appending(path: "Locked.png")
          try Data("old".utf8).write(to: locked)
          try FileManager.default.setAttributes([.immutable: true], ofItemAtPath: locked.path(percentEncoded: false))
          defer { try? FileManager.default.setAttributes([.immutable: false], ofItemAtPath: locked.path(percentEncoded: false)) }

          let written = await coordinator.writeSaveAsCopy(png, to: locked)
          #expect(!written)
          #expect(try Data(contentsOf: locked) == Data("old".utf8))
          let error = try #require(world.notifier.errors.last)
          #expect(error.title == "Not saved")
          #expect(!error.message.isEmpty)
      }

      /// recording-r1 :287, recording-r4 :290. Copy File on a recording in the save folder puts the file itself on
      /// the clipboard; an uploaded recording with no local file copies nothing, also when a downloaded drag copy
      /// sits in its folder (that is not a local file). That Trim downloads its own copy is
      /// `RecordingTrimTests.sourceFollowsEditorInputsOrder`.
      @Test func copyFilePutsASavedRecordingItselfAndNeedsALocalFile() async throws {
          defer { world.removeAll() }
          let folder = try world.storeSaveFolder()
          let coordinator = world.makeCoordinator()
          let file = folder.appending(path: "Recording.mp4")
          try Data(repeating: 7, count: 3).write(to: file)
          let saved = CaptureRecord(fileURL: file, pixelWidth: 1600, pixelHeight: 1000, appName: nil, mediaKind: .video,
                                    durationSeconds: 10)
          let uploaded = CaptureRecord(fileURL: nil, pixelWidth: 1600, pixelHeight: 1000, appName: nil,
                                       uploadState: .uploaded(url: URL(string: "https://snap.tky.io/s/REC.mp4")!,
                                                              key: "s/REC.mp4"),
                                       objectLocation: world.location, mediaKind: .video, durationSeconds: 10)
          coordinator.history.add(saved)
          coordinator.history.add(uploaded)
          let downloaded = coordinator.dragFiles.folder(for: uploaded.id)
          try FileManager.default.createDirectory(at: downloaded, withIntermediateDirectories: true)
          try Data(repeating: 7, count: 3).write(to: downloaded.appending(path: "REC.mp4"))

          await coordinator.copyFile(recordID: saved.id)
          await coordinator.copyFile(recordID: uploaded.id)

          #expect(world.clipboard.copies == [.fileURL(file)])
          #expect(coordinator.dragFiles.stagedFile(id: saved.id) == nil)
          #expect(coordinator.copyFileCounts.isEmpty)
          #expect(coordinator.dragCleanups.isEmpty)
      }
  }
  ```
- [ ] Create `CoordinatorEditorTests.swift`:
  ```swift
  import Foundation
  import Testing
  @testable import TidyShot

  /// The editor's load on a built coordinator (`AppCoordinator+Editor`): `loadImage(for:)`, and an Annotate
  /// whose load fails. Presenting the window builds an `EditorWindowController`, which reads the screens;
  /// that is the editor seam's, and no test here reaches it.
  @Suite(.timeLimit(.minutes(1)))
  struct CoordinatorEditorTests {
      let world: CoordinatorWorld
      let key = "s/SHOT.png"

      init() throws {
          world = try CoordinatorWorld()
      }

      var destination: FakeDestination { world.factory.standard }
      var link: URL { URL(string: "https://snap.tky.io/\(key)")! }

      nonisolated enum Kept: CaseIterable, Sendable {
          /// Saved, never uploaded: the file in the save folder.
          case savedFile
          /// Uploaded, its file kept in the save folder.
          case uploadedWithItsFile
          /// Upload only, the upload failed: `pending/<id>.png`.
          case pendingFile
          /// Uploaded, its file renamed in Finder: the object.
          case renamedUploadedFile
      }

      /// phase-4a :46, phase-4a :47, phase-4a :48, phase-4a :51. The editor's pixels come from the save-folder file
      /// of a saved capture and of an uploaded one, from `pending/<id>.png` of a failed upload-only capture, and
      /// from the downloaded object when an uploaded capture's file was renamed. The object is a 6 by 3 PNG, so
      /// the size tells the source.
      @Test(arguments: Kept.allCases)
      func loadImageReadsTheLocalFileOrDownloadsTheObject(record kept: Kept) async throws {
          defer { world.removeAll() }
          let png = try CoordinatorWorld.pngData(width: 4, height: 2)
          let object = try CoordinatorWorld.pngData(width: 6, height: 3)
          destination.state.withLock { $0.downloadedData = object }
          let folder = try world.storeSaveFolder()
          let coordinator = world.makeCoordinator()
          let id = UUID()
          let saved = folder.appending(path: "Shot.png")
          let record: CaptureRecord
          switch kept {
          case .savedFile:
              try png.write(to: saved)
              record = CaptureRecord(id: id, fileURL: saved, pixelWidth: 4, pixelHeight: 2, appName: nil)
          case .uploadedWithItsFile:
              try png.write(to: saved)
              record = CaptureRecord(id: id, fileURL: saved, pixelWidth: 4, pixelHeight: 2, appName: nil,
                                     uploadState: .uploaded(url: link, key: key), objectLocation: world.location)
          case .pendingFile:
              let pending = try coordinator.pendingFiles.write(png, id: id, ext: "png")
              record = CaptureRecord(id: id, fileURL: pending, fileIsTemporary: true, pixelWidth: 4, pixelHeight: 2,
                                     appName: nil, uploadState: .failed(message: "Upload was interrupted."))
          case .renamedUploadedFile:
              record = CaptureRecord(id: id, fileURL: saved, pixelWidth: 4, pixelHeight: 2, appName: nil,
                                     uploadState: .uploaded(url: link, key: key), objectLocation: world.location)
          }
          coordinator.history.add(record)

          let image = try #require(await coordinator.loadImage(for: record))

          let downloads = kept == .renamedUploadedFile
          #expect(image.image.width == (downloads ? 6 : 4))
          #expect(image.image.height == (downloads ? 3 : 2))
          #expect(destination.state.withLock { $0.dataDownloadKeys } == (downloads ? [key] : []))
          #expect(world.notifier.errors.isEmpty)
      }

      /// phase-4a :50. Annotate on a capture from before Phase 3 whose file was moved out of the save folder opens no
      /// window and posts `Could not open the capture` with `The local file could not be read.`
      @Test func annotateOnAMovedPrePhase3FileSaysCouldNotOpenAndOpensNoEditor() async throws {
          defer { world.removeAll() }
          let folder = try world.storeSaveFolder()
          let coordinator = world.makeCoordinator()
          let record = CaptureRecord(fileURL: folder.appending(path: "Moved.png"), pixelWidth: 4, pixelHeight: 2,
                                     appName: nil, uploadState: .uploaded(url: link, key: key))
          coordinator.history.add(record)

          coordinator.openEditor(recordID: record.id)
          try await eventually {
              world.notifier.calls.contains(.error(title: "Could not open the capture",
                                                   message: "The local file could not be read."))
          }
          try await eventually { coordinator.openingEditorIDs.isEmpty }

          #expect(coordinator.editors.isEmpty)
          #expect(destination.state.withLock { $0.dataDownloadKeys.isEmpty })
      }
  }
  ```
- [ ] Run `CoordinatorRecordActionsTests` and `CoordinatorEditorTests` alone, then the full suite: `Test run with 2214 tests in 184 suites passed`.
- [ ] Commit: `test: checklist record actions and editor loads on the coordinator`.

### Task 7: Trim, recording prompts, the capture lock, the closed-card list, recovery [integration]

**Files:** create `TidyShotTests/CoordinatorTrimTests.swift`, `TidyShotTests/CoordinatorCaptureTests.swift`, `TidyShotTests/CoordinatorOverlayTests.swift`; modify `TidyShotTests/Support/CoordinatorWorld.swift`, `TidyShotTests/Support/CoordinatorFakes.swift`, `TidyShotTests/CoordinatorRecordingTests.swift`, `TidyShotTests/CoordinatorRecoveryTests.swift`.

**Produces:** `HeldMicrophoneDevices`; `CoordinatorWorld.microphones` as `any MicrophoneDevices` (D4).

**Steps:**
- [ ] In `CoordinatorWorld.swift`, replace `let microphones = FakeMicrophoneDevices()` with:
  ```swift
      /// The coordinator's microphones; a test sets others before `makeCoordinator()`.
      var microphones: any MicrophoneDevices = FakeMicrophoneDevices()
  ```
  `grep -rn "world.microphones" TidyShotTests` lists nothing before this task, so no existing test reads it as a `FakeMicrophoneDevices`.
- [ ] In `CoordinatorFakes.swift`, after `HeldCameraDevices`, add:
  ```swift
  /// Microphones whose access prompt stays open until `answer(_:)`, as `HeldCameraDevices` does for the
  /// camera. A prompt whose task is cancelled ends as refused, and a second prompt while one is open is
  /// recorded as an issue and refused at once.
  final class HeldMicrophoneDevices: MicrophoneDevices {
      var currentAccess = MicrophoneAccess.notDetermined
      private(set) var requestCount = 0
      private let prompt = SingleWaiter(cancelled: false,
                                        secondEntry: "HeldMicrophoneDevices was asked again while its prompt was open")

      var isAsking: Bool { prompt.isWaiting }

      func list() -> [MicrophoneDevice] { [] }
      func defaultDevice() -> MicrophoneDevice? { nil }
      func access() -> MicrophoneAccess { currentAccess }

      func requestAccess() async -> Bool {
          requestCount += 1
          return await prompt.wait()
      }

      func answer(_ granted: Bool) {
          currentAccess = granted ? .authorized : .denied
          prompt.resume(granted)
      }
  }
  ```
- [ ] Create `CoordinatorTrimTests.swift`:
  ```swift
  import Foundation
  import Testing
  @testable import TidyShot

  /// `Upload Trimmed` and the trim's refusals on a built coordinator (`AppCoordinator+Trim`, recording design,
  /// Stale link and Write-time checks). `uploadTrimmed` reaches only the refusal rule, the destination, the
  /// save folder, the payload and `startPlannedUpload`; no Trim window is built.
  @Suite(.timeLimit(.minutes(1)))
  struct CoordinatorTrimTests {
      let world: CoordinatorWorld

      init() throws {
          world = try CoordinatorWorld()
      }

      var destination: FakeDestination { world.factory.standard }

      /// An uploaded recording in `pending/` whose link still shows the full recording (`uploadIsStale`), as a
      /// trim's Save leaves an upload-only one.
      func addTrimmedUpload(to coordinator: AppCoordinator, byteCount: Int64 = 3,
                            key: String = "s/REC.mp4") throws -> CaptureRecord {
          let id = UUID()
          let file = coordinator.pendingFiles.directory.appending(path: "\(id.uuidString).mp4")
          try CoordinatorWorld.writeSparseFile(at: file, byteCount: byteCount)
          let record = CaptureRecord(id: id, fileURL: file, fileIsTemporary: true, pixelWidth: 1600, pixelHeight: 1000,
                                     appName: nil,
                                     uploadState: .uploaded(url: URL(string: "https://snap.tky.io/\(key)")!, key: key),
                                     objectLocation: world.location, uploadIsStale: true, mediaKind: .video,
                                     durationSeconds: 10, byteCount: Int(byteCount))
          coordinator.history.add(record)
          return record
      }

      /// recording-r2 :456, in part. `Upload Trimmed` PUTs the link's own key and clears `Link not updated`; a
      /// failed one keeps the link and the note and says `Not uploaded`. By hand: the trim sheet as it shows
      /// (its table is `RecordingTrimTests.saveTargetWithADestination` and `.saveTargetWithNoDestination`).
      @Test func uploadTrimmedClearsTheStaleNoteOnSuccessAndKeepsItOnFailure() async throws {
          defer { world.removeAll() }
          let coordinator = world.makeCoordinator()
          let trimmed = try addTrimmedUpload(to: coordinator)

          coordinator.uploadTrimmed(recordID: trimmed.id)
          try await eventually { coordinator.history.record(id: trimmed.id)?.uploadIsStale == false }

          #expect(destination.state.withLock { $0.fileUploads.map(\.key) } == ["s/REC.mp4"])
          #expect(destination.state.withLock { $0.fileUploads.map(\.cacheControl) } == ["no-cache"])
          #expect(coordinator.history.record(id: trimmed.id)?.uploadedKey == "s/REC.mp4")

          destination.state.withLock {
              $0.failuresRemaining = 1
              $0.failure = .httpStatus(403, body: "AccessDenied: Access Denied")
          }
          let failing = try addTrimmedUpload(to: coordinator, key: "s/OTHER.mp4")
          coordinator.uploadTrimmed(recordID: failing.id)
          try await eventually {
              world.notifier.calls.contains(.error(title: "Not uploaded",
                                                   message: EditorUploadPlan.failedReplaceRecordingMessage))
          }
          let kept = try #require(coordinator.history.record(id: failing.id))
          #expect(kept.uploadState == failing.uploadState)
          #expect(kept.uploadIsStale)
          #expect(kept.fileURL == failing.fileURL)
      }

      /// recording-r4 :251. `Upload Trimmed` of a file over the part threshold replaces the link in parts, at the
      /// link's key; a failure keeps the old link, marked stale, and a later `Upload Trimmed` of the unchanged
      /// file resumes the stored upload with no second Create.
      @Test func uploadTrimmedReplacesInPartsKeepsTheLinkOnFailureAndResumes() async throws {
          defer { world.removeAll() }
          world.multipartPlan = MultipartPlan(threshold: 1_048_576, partSize: 262_144, inFlight: 1)
          destination.state.withLock { $0.partFailures = [2: [.httpStatus(403, body: "AccessDenied: Access Denied")]] }
          let coordinator = world.makeCoordinator()
          let trimmed = try addTrimmedUpload(to: coordinator, byteCount: 1_048_576)

          coordinator.uploadTrimmed(recordID: trimmed.id)
          try await eventually {
              world.notifier.calls.contains(.error(title: "Not uploaded",
                                                   message: EditorUploadPlan.failedReplaceRecordingMessage))
          }
          #expect(destination.state.withLock { $0.creates.map(\.key) } == ["s/REC.mp4"])
          let failed = try #require(coordinator.history.record(id: trimmed.id))
          #expect(failed.uploadState == trimmed.uploadState)
          #expect(failed.uploadIsStale)
          #expect(failed.multipart?.uploadID == "upload-1")

          coordinator.uploadTrimmed(recordID: trimmed.id)
          try await eventually { coordinator.history.record(id: trimmed.id)?.uploadIsStale == false }

          #expect(destination.state.withLock { $0.creates.count } == 1)
          #expect(destination.state.withLock { $0.completes.map(\.uploadID) } == ["upload-1"])
          #expect(coordinator.history.record(id: trimmed.id)?.uploadedKey == "s/REC.mp4")
      }

      /// recording-r2 :645 (call C). The first replace of a launch whose URL was not copied, because the clipboard
      /// changed during the upload, posts the cache note titled `Uploaded`, not `Uploaded, URL copied`.
      @Test func aFirstReplaceWhoseURLWasNotCopiedPostsTheCacheNoteAsUploaded() async throws {
          defer { world.removeAll() }
          destination.state.withLock { $0.holdingUploadsRemaining = 1 }
          let coordinator = world.makeCoordinator()
          let trimmed = try addTrimmedUpload(to: coordinator)

          coordinator.uploadTrimmed(recordID: trimmed.id)
          try await eventually { destination.state.withLock { $0.heldUploads.count } == 1 }
          world.clipboard.changeCount += 1
          destination.releaseUploads()
          try await eventually { coordinator.history.record(id: trimmed.id)?.uploadIsStale == false }

          #expect(world.notifier.calls.contains(.notice(title: "Uploaded", body: EditorUploadPlan.cacheNote)))
          #expect(!world.notifier.calls.contains(.notice(title: "Uploaded, URL copied", body: EditorUploadPlan.cacheNote)))
          #expect(!world.clipboard.copies.contains { if case .url = $0 { true } else { false } })
          #expect(coordinator.linkNotCopiedIDs.contains(trimmed.id))
      }

      /// recording-r2 :475. While a Trim pass writes the file, Delete is refused with `Not deleted` and the trimming
      /// text, and `Upload Trimmed` with `Not uploaded` / `This capture is being trimmed.`; the record stays.
      /// Retry's refusal is `CoordinatorUploadTests.aRetryOfATrimmingOrUploadingRecordDoesNothingButSay`, and the
      /// card's disabled items `QuickAccessModelTests.retryUploadTrimmedAndDeleteAreDisabledWhileTrimming`.
      @Test func aCaptureBeingTrimmedRefusesDeleteAndUploadTrimmed() async throws {
          defer { world.removeAll() }
          let coordinator = world.makeCoordinator()
          let trimmed = try addTrimmedUpload(to: coordinator)
          coordinator.trimmingIDs.insert(trimmed.id)

          await coordinator.deleteCapture(recordID: trimmed.id)
          coordinator.uploadTrimmed(recordID: trimmed.id)

          #expect(world.notifier.calls == [.error(title: "Not deleted", message: CaptureDeletion.trimmingRefusal),
                                           .error(title: "Not uploaded", message: "This capture is being trimmed.")])
          #expect(world.confirm.asked.isEmpty)
          #expect(coordinator.history.record(id: trimmed.id) == trimmed)
          #expect(world.factory.askedConfigs.isEmpty)
      }
  }
  ```
- [ ] Add the three tests at the end of `CoordinatorRecordingTests`. Each press is Record Fullscreen's: Record Screen's evaluates `CaptureIntent.standard`, which reads `AppSettings.shared`, once the shortcut rule lets it start; Record Fullscreen reads it only after the prompts, which these tests end first (D6). The one `recordScreen()` below is a press the shortcut rule ignores, so it returns before `.standard`.
  ```swift
      /// recording-r2 :364, in part. With microphone access undecided and another capture holding the lock (an area
      /// selection, a self-timer countdown, a scrolling capture), a record press shows no prompt and starts
      /// nothing, and the capture goes on. By hand: the press once the capture is done, which prompts and then
      /// makes the live `tmp/Recording`, and that nothing is logged.
      @Test func aRecordPressDuringACaptureWithAccessUndecidedShowsNoPrompt() async throws {
          defer { world.removeAll() }
          world.settings.recordingMicrophone = MicrophoneChoice.systemDefaultValue
          let microphones = FakeMicrophoneDevices(access: .notDetermined)
          world.microphones = microphones
          let coordinator = world.makeCoordinator()
          let gate = TestGate()
          let lock = Task { await coordinator.withCaptureLock(coversDesktop: false) { await gate.wait() } }
          try await eventually { gate.isWaiting }

          let press = TaskWatch(Task { await coordinator.recordFullscreen() })
          try await eventually { press.hasReturned }

          #expect(microphones.requestCount == 0)
          #expect(coordinator.askingPermission == nil)
          #expect(coordinator.isCapturing)
          #expect(coordinator.recordingPhase == .idle)
          #expect(world.notifier.calls.isEmpty)
          gate.open()
          _ = await lock.value
      }

      /// recording-r3 :155. A GIF start asks for the camera (the bubble applies to GIF) and never for the microphone,
      /// though one is set. A quit while the camera prompt is up ends the start before the capture lock.
      @Test func aGIFStartAsksForTheCameraAndNotTheMicrophone() async throws {
          defer { world.removeAll() }
          world.settings.recordingFormat = .gif
          world.settings.recordingMicrophone = MicrophoneChoice.systemDefaultValue
          world.settings.recordingWebcamBubble = true
          world.settings.hideDesktopIconsWhileCapturing = false
          let microphones = FakeMicrophoneDevices(access: .notDetermined)
          world.microphones = microphones
          let cameras = HeldCameraDevices()
          world.cameras = cameras
          let coordinator = world.makeCoordinator()

          let start = TaskWatch(Task { await coordinator.recordFullscreen() })
          try await eventually { cameras.isAsking }
          #expect(coordinator.askingPermission == .camera)
          #expect(microphones.requestCount == 0)

          // The quit makes the start give up once the prompt is answered: no lock, no `tmp/Recording`. It returns
          // while the prompt is up only because nothing records yet; gated, so a start that locked or counted in
          // first fails here instead of hanging, and the deferred answer frees the start either way (D31).
          do {
              defer { cameras.answer(false) }
              let quit = TaskWatch(Task { await coordinator.finishRecordingForQuit() })
              try await eventually { quit.hasReturned }
          }
          try await eventually { start.hasReturned }
          #expect(cameras.requestCount == 1)
          #expect(microphones.requestCount == 0)
          #expect(!coordinator.isCapturing)
          #expect(world.notifier.calls == [.waited(.seconds(1))])
      }

      /// recording-r2 :351, the held prompt's part (a B line, left unmarked, D15). With the microphone prompt up, a
      /// second record press asks nothing, every capture is refused for the prompt, and a quit before the answer
      /// starts nothing. The disabled menu items, the dropped URL command's log line and the recording that
      /// starts after the answer stay with the line's seams.
      @Test func aSecondRecordPressWhileTheMicrophonePromptIsUpAsksNothingAndAQuitStartsNothing() async throws {
          defer { world.removeAll() }
          world.settings.recordingMicrophone = MicrophoneChoice.systemDefaultValue
          let microphones = HeldMicrophoneDevices()
          world.microphones = microphones
          let coordinator = world.makeCoordinator()

          let first = TaskWatch(Task { await coordinator.recordFullscreen() })
          try await eventually { microphones.isAsking }
          #expect(coordinator.askingPermission == .microphone)
          #expect(coordinator.capturesRefused)
          #expect(coordinator.captureRefusal == .permissionPrompt(.microphone))

          let second = TaskWatch(Task { await coordinator.recordScreen() })
          try await eventually { second.hasReturned }
          #expect(microphones.requestCount == 1)

          // Gated as the GIF test's quit is (D31).
          do {
              defer { microphones.answer(false) }
              let quit = TaskWatch(Task { await coordinator.finishRecordingForQuit() })
              try await eventually { quit.hasReturned }
          }
          try await eventually { first.hasReturned }
          #expect(!coordinator.isCapturing)
          #expect(coordinator.askingPermission == nil)
          #expect(world.notifier.calls == [.waited(.seconds(1))])
      }
  ```
- [ ] Create `CoordinatorCaptureTests.swift`:
  ```swift
  import Foundation
  import Testing
  @testable import TidyShot

  /// The capture lock on a built coordinator (`withCaptureLock`): a capture command while another capture holds
  /// it returns at once. A capture the lock let through would read the shareable content, which the suite never
  /// reaches.
  @Suite(.timeLimit(.minutes(1)))
  struct CoordinatorCaptureTests {
      let world: CoordinatorWorld

      init() throws {
          world = try CoordinatorWorld()
      }

      nonisolated enum Entry: CaseIterable, Sendable {
          case area
          case window
          case previousArea
      }

      /// phase-1 :25, phase-6a :215, in part. While a capture holds the lock (the selection overlay is up, or a
      /// self-timer or a scrolling session runs), Capture Area, Capture Window and Capture Previous Area (⌃⇧6)
      /// return at once and post, show and copy nothing. By hand (phase-6a :215): the disabled menu item (D16).
      @Test(arguments: Entry.allCases)
      func aCaptureWhileTheLockIsHeldReturnsAtOnceAndPostsNothing(entry: Entry) async throws {
          defer { world.removeAll() }
          let coordinator = world.makeCoordinator()
          let gate = TestGate()
          let lock = Task { await coordinator.withCaptureLock(coversDesktop: false) { await gate.wait() } }
          try await eventually { gate.isWaiting }
          let intent = CaptureIntent(action: .save)

          // Gated with `eventually`: a lock that let the capture through would wait on the content read.
          let capture = TaskWatch(Task {
              switch entry {
              case .area: await coordinator.captureArea(intent: intent)
              case .window: await coordinator.captureWindow(intent: intent)
              case .previousArea: await coordinator.capturePreviousArea(intent: intent)
              }
          })
          try await eventually { capture.hasReturned }

          #expect(world.notifier.calls.isEmpty)
          #expect(world.cards.calls.isEmpty)
          #expect(world.clipboard.copies.isEmpty)
          #expect(coordinator.isCapturing)
          gate.open()
          _ = await lock.value
          #expect(!coordinator.isCapturing)
      }
  }
  ```
- [ ] Create `CoordinatorOverlayTests.swift`:
  ```swift
  import Foundation
  import Testing
  @testable import TidyShot

  /// Restore Closed Overlay's memory on a built coordinator (`AppCoordinator+Overlay`, spec 2.9): in memory only.
  @Suite(.timeLimit(.minutes(1)))
  struct CoordinatorOverlayTests {
      let world: CoordinatorWorld

      init() throws {
          world = try CoordinatorWorld()
      }

      /// phase-6a :165. After a relaunch the closed-card list is empty, so Restore Closed Overlay is disabled, while
      /// Recent Captures keeps every record.
      @Test func aRelaunchForgetsClosedCardsButKeepsTheirRecords() {
          defer { world.removeAll() }
          let coordinator = world.makeCoordinator()
          let record = CaptureRecord(fileURL: nil, pixelWidth: 4, pixelHeight: 2, appName: nil)
          coordinator.history.add(record)
          world.cards.showing.insert(record.id)
          world.cards.close(recordID: record.id, reason: .user)
          #expect(coordinator.canRestoreClosedOverlay)

          let relaunched = world.makeCoordinator()
          relaunched.history.load()

          #expect(!relaunched.canRestoreClosedOverlay)
          #expect(relaunched.history.records.map(\.id) == [record.id])
      }
  }
  ```
- [ ] In `CoordinatorRecoveryTests.anOrphanMP4IsAdoptedWithItsLength` (the extension), after `#expect(record.byteCount == FileSizes.byteCount(of: url))`, add:
  ```swift
          // coordinator-harness :52 (item 8): an adopted recording is kept in TidyShot, as an image is.
          #expect(record.fileIsTemporary)
          #expect(record.uploadState == .none)
  ```
  and end its doc comment with ` coordinator-harness :52: an adopted recording gets \`.none\` and \`fileIsTemporary\`.`
- [ ] Run `CoordinatorTrimTests`, `CoordinatorRecordingTests`, `CoordinatorCaptureTests`, `CoordinatorOverlayTests` and `CoordinatorRecoveryTests` alone, then the full suite: `Test run with 2223 tests in 187 suites passed`.
- [ ] Commit: `test: checklist trim, recording prompt, capture lock and closed-card cases`.

### Task 8: The editor model's checklist cases [mechanical]

**Files:** modify `TidyShotTests/EditorModelTests.swift`, `TidyShotTests/CounterTests.swift`, `TidyShotTests/EditorFlattenerTests.swift`, `TidyShotTests/EditorBackgroundExportTests.swift`.

**Steps:**
- [ ] In `EditorModelTests`, replace `aSelectedCounterShowsAndTakesTheColour` (the extension) together with its doc
  comment:
  ```swift
      /// A counter has a colour: selected, the swatch shows it and a pick recolours it as `Color`. phase-4c :151:
      /// a counter placed afterwards takes the applied colour.
      @Test func aSelectedCounterShowsAndTakesTheColour() throws {
          let model = makeModel(side: 200)
          model.tool = .select
          let mark = add(counter(), to: model)
          model.selection = mark.id
          #expect(model.activeColor == red)
          #expect(model.colorApplies)
          model.applyColor(blue)
          #expect(model.document.annotation(id: mark.id) == mark.withColor(blue))
          #expect(model.activeColor == blue)
          #expect(model.undoManager.undoActionName == EditorModel.ActionName.color)
          model.undoManager.undo()
          #expect(model.document.annotation(id: mark.id) == mark)
          #expect(model.activeColor == red)
          // phase-4c :151: the stroke colour followed the swatch, so a counter placed afterwards takes it.
          let placed = try #require(model.makeAnnotation(.counter, from: CGPoint(x: 120, y: 120), to: CGPoint(x: 120, y: 120)))
          #expect(placed.counterMark?.color == blue)
      }
  ```
- [ ] Add at the end of `EditorModelTests`:
  ```swift
      // MARK: Checklist cases (CT-1)

      nonisolated enum Shape: CaseIterable, Sendable {
          case rectangle
          case ellipse
          case line
      }

      nonisolated enum Duplicated: CaseIterable, Sendable {
          case ellipse, line, pencil, highlighter, text, arrow, blur, redact
      }

      /// phase-4a :60. The options slider's block size changes a selected mosaic, live, as one step: a burst of
      /// changes undoes at once (`Block Size`).
      @Test func blockSizeAppliesToTheSelectedPixelateInOneStep() throws {
          let model = makeModel(side: 256)
          model.tool = .select
          let rect = CGRect(x: 4, y: 4, width: 200, height: 200)
          let region = add(.pixelate(Region(id: UUID(), rect: rect),
                                     block: RedactionDefaults.block(points: 10, scale: 2, region: rect)), to: model)
          model.selection = region.id

          model.applyEffectParameter(.block, points: 20)
          model.applyEffectParameter(.block, points: 24)

          guard case .pixelate(_, let block)? = model.document.annotation(id: region.id) else {
              Issue.record("the selection is not a mosaic")
              return
          }
          #expect(block == RedactionDefaults.block(points: 24, scale: 2, region: rect))
          #expect(model.blockPoints == 24)
          #expect(model.undoManager.undoActionName == EditorModel.ActionName.block)
          model.undoManager.undo()
          #expect(model.document.annotation(id: region.id) == region)
      }

      /// phase-4a :62, phase-4b :37. Keys 1 to 6 (`applyLineWidth`) set the width on a selected rectangle, ellipse or
      /// line and on its tool; a swatch recolours the selection, and the tool's colour follows.
      @Test(arguments: Shape.allCases)
      func widthAndColourApplyToTheSelectedShapeAndItsTool(kind: Shape) {
          let model = makeModel(side: 64)
          model.tool = .select
          let shape: Annotation = switch kind {
          case .rectangle:
              .rectangle(ShapeBox(id: UUID(), rect: CGRect(x: 4, y: 4, width: 20, height: 10), color: red, lineWidth: 8))
          case .ellipse:
              .ellipse(ShapeBox(id: UUID(), rect: CGRect(x: 4, y: 4, width: 20, height: 10), color: red, lineWidth: 8))
          case .line:
              .line(Segment(id: UUID(), from: CGPoint(x: 4, y: 4), to: CGPoint(x: 30, y: 20), color: red, lineWidth: 8))
          }
          add(shape, to: model)
          model.selection = shape.id

          model.applyLineWidth(points: 12)
          #expect(model.document.annotation(id: shape.id) == shape.withLineWidth(12 * model.scale))
          #expect(model.lineWidthPoints == 12)
          #expect(model.undoManager.undoActionName == EditorModel.ActionName.lineWidth)

          model.applyColor(blue)
          #expect(model.document.annotation(id: shape.id) == shape.withLineWidth(12 * model.scale).withColor(blue))
          #expect(model.strokeColor == blue)
          #expect(model.undoManager.undoActionName == EditorModel.ActionName.color)
      }

      /// phase-4b :55. The colour button recolours a selected text and the tool's colour, and the text being typed,
      /// so a text placed afterwards takes that colour.
      @Test func colourAppliesToTheSelectedTextAndTheTextBeingTyped() {
          let model = makeModel(side: 64)
          model.tool = .select
          let text = add(.text(TextBox(id: UUID(), string: "Hi", origin: CGPoint(x: 4, y: 4), fontSize: 24, color: red)),
                         to: model)
          model.selection = text.id

          model.applyColor(blue)
          #expect(model.document.annotation(id: text.id) == text.withColor(blue))
          #expect(model.strokeColor == blue)

          model.tool = .text
          model.beginTextEditing(at: CGPoint(x: 30, y: 30), existing: nil)
          #expect(model.textEditing?.box.color == blue)
          model.applyColor(black)
          #expect(model.textEditing?.box.color == black)
          #expect(model.strokeColor == black)
      }

      /// phase-4b :84 (the all-outside case). With a crop applied and every annotation wholly outside it, ⌘A selects
      /// nothing.
      @Test func selectAllWithEveryAnnotationOutsideTheCropSelectsNothing() {
          let model = makeModel(side: 64)
          add(box(x: 40), to: model)
          add(blurRegion(radius: 4), to: model)
          model.tool = .crop
          model.cropDraft = CGRect(x: 20, y: 20, width: 10, height: 10)
          model.applyCrop()
          #expect(model.document.crop == CGRect(x: 20, y: 20, width: 10, height: 10))

          model.selectAll()

          #expect(model.selection == nil)
      }

      /// phase-4b :88. ⌘D copies every kind: the copy is the same annotation `duplicateOffset` away with its own id,
      /// selected, in one step `Duplicate <title>`; a redaction's copy is a redaction.
      @Test(arguments: Duplicated.allCases)
      func duplicateCopiesEveryKindOffsetAndNamed(kind: Duplicated) throws {
          let model = makeModel(side: 64)
          model.tool = .select
          let points = [CGPoint(x: 4, y: 4), CGPoint(x: 10, y: 8), CGPoint(x: 16, y: 6)]
          let original: Annotation = switch kind {
          case .ellipse:
              .ellipse(ShapeBox(id: UUID(), rect: CGRect(x: 4, y: 4, width: 12, height: 8), color: red, lineWidth: 4))
          case .line: .line(Segment(id: UUID(), from: CGPoint(x: 4, y: 4), to: CGPoint(x: 20, y: 12), color: red, lineWidth: 4))
          case .pencil: .pencil(Stroke(id: UUID(), points: points, color: red, lineWidth: 4))
          case .highlighter: .highlighter(Stroke(id: UUID(), points: points, color: red, lineWidth: 12))
          case .text: .text(TextBox(id: UUID(), string: "Hi", origin: CGPoint(x: 4, y: 4), fontSize: 24, color: red))
          case .arrow: arrow()
          case .blur: blurRegion(radius: 4)
          case .redact: redaction()
          }
          add(original, to: model)
          model.selection = original.id

          model.duplicateSelection()

          #expect(model.document.annotations.count == 2)
          let copy = try #require(model.document.annotations.last)
          #expect(copy.id != original.id)
          #expect(copy == original.moved(by: model.duplicateOffset).withID(copy.id))
          #expect(model.selection == copy.id)
          #expect(model.undoManager.undoActionName == "Duplicate \(original.title)")
      }

      /// phase-4b :118. One of each tool (Redact, Pixelate, Blur, Rectangle, Arrow, Ellipse, Line, Pencil, Highlighter,
      /// Text), made by the real tools over the model, then a crop: undo takes the crop as its own step, then the
      /// ten annotations newest first; redo brings them back in order, then the crop.
      @Test func oneOfEachToolUndoesNewestFirstAndRedoesInOrder() {
          let model = makeModel(side: 400)
          for (index, tool) in [EditorTool.redact, .pixelate, .blur, .rectangle, .arrow, .ellipse, .line].enumerated() {
              let y = CGFloat(10 + index * 40)
              let drag = makeTool(for: tool)
              drag.mouseDown(ToolInput(point: CGPoint(x: 10, y: y)), on: model)
              drag.mouseDragged(ToolInput(point: CGPoint(x: 60, y: y + 30)), on: model)
              drag.mouseUp(ToolInput(point: CGPoint(x: 60, y: y + 30)), on: model)
          }
          for (index, tool) in [EditorTool.pencil, .highlighter].enumerated() {
              let y = CGFloat(300 + index * 40)
              let stroke = makeTool(for: tool)
              stroke.mouseDown(ToolInput(point: CGPoint(x: 10, y: y)), on: model)
              for x in stride(from: 20, through: 80, by: 10) {
                  stroke.mouseDragged(ToolInput(point: CGPoint(x: CGFloat(x), y: y + 5)), on: model)
              }
              stroke.mouseUp(ToolInput(point: CGPoint(x: 80, y: y + 5)), on: model)
          }
          model.beginTextEditing(at: CGPoint(x: 200, y: 200), existing: nil)
          model.updateEditingText("Ten")
          model.commitTextEditing()
          let all = model.document.annotations
          #expect(all.count == 10)
          model.tool = .crop
          model.cropDraft = CGRect(x: 0, y: 0, width: 300, height: 300)
          model.applyCrop()
          let cropped = model.document

          model.undoManager.undo()
          #expect(model.document.crop == nil)
          #expect(model.document.annotations == all)
          for count in stride(from: 9, through: 0, by: -1) {
              model.undoManager.undo()
              #expect(model.document.annotations == Array(all.prefix(count)))
          }
          #expect(!model.undoManager.canUndo)
          for count in 1...10 {
              model.undoManager.redo()
              #expect(model.document.annotations == Array(all.prefix(count)))
          }
          model.undoManager.redo()
          #expect(model.document == cropped)
      }

      /// phase-4c :140. With a spotlight or a counter selected, `Line width` changes only the default: the selected
      /// one is unchanged, no undo step is added and nothing is unsaved.
      @Test func lineWidthWithASpotlightOrCounterSelectedChangesOnlyTheDefault() {
          let model = makeModel(side: 200)
          model.tool = .select
          let hole = add(spotlight(), to: model)
          let mark = add(counter(), to: model)
          model.markSaved()
          let document = model.document
          let lastStep = model.undoManager.undoActionName

          for (selected, points) in [(hole.id, CGFloat(8)), (mark.id, CGFloat(12))] {
              model.selection = selected
              model.applyLineWidth(points: points)
              #expect(model.lineWidthPoints == points)
              #expect(model.document == document)
              #expect(model.undoManager.undoActionName == lastStep)
              #expect(!model.hasUnsavedChanges)
          }
      }

      /// phase-4c :163, phase-4c :167. Every spotlight edit is one named step: `Add Spotlight`, `Move Spotlight`,
      /// `Resize Spotlight`, `Duplicate Spotlight` (⌘D and an ⌥-drag) and `Paste Spotlight`, the second paste one
      /// cascade step further; undo and redo restore each document, and the unsaved state follows.
      @Test func everySpotlightEditIsOneNamedUndoStep() throws {
          let model = makeModel(side: 400)
          model.tool = .select
          var documents = [model.document]
          var names: [String] = []
          func step() {
              documents.append(model.document)
              names.append(model.undoManager.undoActionName)
          }

          let draw = makeTool(for: .spotlight)
          draw.mouseDown(ToolInput(point: CGPoint(x: 40, y: 40)), on: model)
          draw.mouseDragged(ToolInput(point: CGPoint(x: 140, y: 100)), on: model)
          draw.mouseUp(ToolInput(point: CGPoint(x: 140, y: 100)), on: model)
          step()
          let hole = try #require(model.document.spotlights.first)
          model.selection = hole.id

          let select = makeTool(for: .select)
          select.mouseDown(ToolInput(point: CGPoint(x: 90, y: 70)), on: model)
          select.mouseDragged(ToolInput(point: CGPoint(x: 110, y: 80)), on: model)
          select.mouseUp(ToolInput(point: CGPoint(x: 110, y: 80)), on: model)
          step()
          let moved = try #require(model.document.annotation(id: hole.id)?.spotlightShape?.rect)
          select.mouseDown(ToolInput(point: CGPoint(x: moved.maxX, y: moved.maxY)), on: model)
          select.mouseDragged(ToolInput(point: CGPoint(x: moved.maxX + 30, y: moved.maxY + 20)), on: model)
          select.mouseUp(ToolInput(point: CGPoint(x: moved.maxX + 30, y: moved.maxY + 20)), on: model)
          step()
          model.duplicateSelection()
          step()
          let resized = try #require(model.document.annotation(id: hole.id)?.spotlightShape?.rect)
          let centre = CGPoint(x: resized.midX, y: resized.midY)
          select.mouseDown(ToolInput(point: centre, option: true), on: model)
          select.mouseDragged(ToolInput(point: CGPoint(x: centre.x, y: centre.y + 150), option: true), on: model)
          select.mouseUp(ToolInput(point: CGPoint(x: centre.x, y: centre.y + 150), option: true), on: model)
          step()
          model.selection = hole.id
          let clip = try #require(model.objectClip())
          model.paste(clip)
          step()
          let firstPaste = try #require(model.document.annotations.last?.spotlightShape?.rect)
          model.paste(clip)
          step()
          let secondPaste = try #require(model.document.annotations.last?.spotlightShape?.rect)

          #expect(names == ["Add Spotlight", "Move Spotlight", "Resize Spotlight", "Duplicate Spotlight",
                            "Duplicate Spotlight", "Paste Spotlight", "Paste Spotlight"])
          #expect(secondPaste.origin == CGPoint(x: firstPaste.minX + model.duplicateOffset.dx,
                                                y: firstPaste.minY + model.duplicateOffset.dy))
          for document in documents.reversed().dropFirst() {
              model.undoManager.undo()
              #expect(model.document == document)
          }
          #expect(!model.hasUnsavedChanges)
          for document in documents.dropFirst() {
              model.undoManager.redo()
              #expect(model.document == document)
              #expect(model.hasUnsavedChanges)
          }
      }

      /// phase-4c :203. The spotlight Dim belongs to its document: 70 % in one editor leaves another at 50 %, and a
      /// new editor starts at 50 %.
      @Test func spotlightDimStaysWithItsModel() {
          let first = makeModel()
          let second = makeModel()
          add(spotlight(), to: first)
          add(spotlight(), to: second)

          first.applySpotlightDim(0.7)

          #expect(first.document.effectiveSpotlightDim == 0.7)
          #expect(second.document.effectiveSpotlightDim == 0.5)
          #expect(makeModel().document.effectiveSpotlightDim == 0.5)
      }
  ```
- [ ] Add at the end of `CounterTests`:
  ```swift
      /// phase-4c :159. Undoing the paste, the ⌥-drag copy and the ⌘D copy in turn returns the numbers to 1 and 2;
      /// each redo brings its copy back with its number; after undoing the three again a new counter is 3.
      @Test func undoingCopiesReturnsTheNumbersAndRedoRestoresThem() throws {
          let model = models.makeModel(side: 400)
          model.tool = .select
          let first = models.add(counter(1, at: CGPoint(x: 60, y: 60)), to: model)
          models.add(counter(2, at: CGPoint(x: 200, y: 60)), to: model)
          model.selection = first.id
          model.duplicateSelection()
          let select = makeTool(for: .select)
          select.mouseDown(ToolInput(point: CGPoint(x: 60, y: 60), option: true), on: model)
          select.mouseDragged(ToolInput(point: CGPoint(x: 60, y: 200), option: true), on: model)
          select.mouseUp(ToolInput(point: CGPoint(x: 60, y: 200), option: true), on: model)
          model.selection = first.id
          model.paste(try #require(model.objectClip()))
          #expect(numbers(in: model.document) == [1, 2, 3, 4, 5])

          for expected in [[1, 2, 3, 4], [1, 2, 3], [1, 2]] {
              model.undoManager.undo()
              #expect(numbers(in: model.document) == expected)
          }
          for expected in [[1, 2, 3], [1, 2, 3, 4], [1, 2, 3, 4, 5]] {
              model.undoManager.redo()
              #expect(numbers(in: model.document) == expected)
          }
          for _ in 0..<3 { model.undoManager.undo() }
          let placed = try #require(model.makeAnnotation(.counter, from: CGPoint(x: 300, y: 300),
                                                         to: CGPoint(x: 300, y: 300)))
          #expect(placed.counterMark?.number == 3)
      }

      /// phase-4c :162. A counter copied in an editor at one scale and pasted twice into one at another takes the
      /// target's next numbers, the second cascaded from the first, at the source's point size (64 px at 2x is
      /// 32 px at 1x); both ways.
      @Test func aCounterPastedTwiceAcrossScalesTakesTheNextNumbersAtItsPointSize() throws {
          for (from, to) in [(CGFloat(2), CGFloat(1)), (CGFloat(1), CGFloat(2))] {
              let source = models.makeModel(scale: from, side: 400)
              let mark = models.add(counter(1, at: CGPoint(x: 100, y: 100), diameter: 32 * from), to: source)
              source.selection = mark.id
              let data = try #require(source.objectClip()?.encoded())
              let clip = try #require(AnnotationClip.decoded(from: data))
              let target = models.makeModel(scale: to, side: 400)
              models.add(counter(1, at: CGPoint(x: 300, y: 300), diameter: 32 * to), to: target)
              models.add(counter(2, at: CGPoint(x: 340, y: 300), diameter: 32 * to), to: target)

              target.paste(clip)
              let firstPaste = try #require(target.document.annotations.last?.counterMark)
              target.paste(clip)
              let secondPaste = try #require(target.document.annotations.last?.counterMark)

              #expect(firstPaste.number == 3)
              #expect(secondPaste.number == 4)
              #expect(firstPaste.diameter == 32 * to)
              #expect(secondPaste.diameter == 32 * to)
              #expect(secondPaste.center == CGPoint(x: firstPaste.center.x + target.duplicateOffset.dx,
                                                    y: firstPaste.center.y + target.duplicateOffset.dy))
          }
      }
  ```
- [ ] Add at the end of `EditorFlattenerTests`:
  ```swift
      /// phase-4b :79. A crop of a window capture that keeps a transparent corner keeps it transparent in the saved
      /// PNG.
      @Test func aCropKeepingATransparentCornerKeepsItClear() throws {
          let base = makeImage { x, y in x < 4 && y < 4 ? Self.clearPixel : Self.pattern(x, y) }
          let document = AnnotationDocument(annotations: []).withCrop(CGRect(x: 0, y: 0, width: 32, height: 24))
          let flat = try #require(EditorFlattener.flatten(base: base, tiles: [], document: document, scale: 1))
          let output = try Bitmap(flat)
          #expect(output.width == 32)
          #expect(output.height == 24)
          #expect(output[0, 0] == Self.clearPixel)
          #expect(output[3, 3] == Self.clearPixel)
          #expect(output[31, 23] == Self.pattern(31, 23))
      }
  ```
- [ ] Add at the end of `EditorBackgroundExportTests` (solid fills only: a desktop picture or a custom image reads the wallpaper or `CustomBackgroundStore.shared`):
  ```swift
      /// phase-7c :94, phase-7c :98, in part. A swatch, the Shadow toggle and an aspect change are one step each: the
      /// editor is dirty after each and clean after Save, and three undos take them back in reverse, one at a
      /// time. By hand: the window's edited mark.
      @Test func aSwatchTheShadowAndAnAspectAreThreeStepsThatDirtyTheEditor() throws {
          let model = makeModel()
          model.setBackground(solid(red))
          model.markSaved()
          let start = model.document.background

          try change(model) { $0.fill = .solid(blue) }
          #expect(model.hasUnsavedChanges)
          let swatched = model.document.background
          try change(model) { $0.shadow.toggle() }
          #expect(model.hasUnsavedChanges)
          let shadowed = model.document.background
          try change(model) { $0.aspect = .square }
          #expect(model.hasUnsavedChanges)
          model.markSaved()
          #expect(!model.hasUnsavedChanges)

          model.undoManager.undo()
          #expect(model.document.background == shadowed)
          #expect(model.hasUnsavedChanges)
          model.undoManager.undo()
          #expect(model.document.background == swatched)
          model.undoManager.undo()
          #expect(model.document.background == start)
      }

      /// phase-7c :143, phase-7c :165. For every aspect ratio the canvas the editor shows has the export's size, and
      /// with a crop the ratio is laid out from the crop's size.
      @Test func theShownCanvasHasTheExportsSizeForEveryAspect() async throws {
          for aspect in BackgroundAspect.allCases {
              let model = makeModel()
              var style = solid(red)
              style.aspect = aspect
              model.setBackground(style)
              let shown = try #require(model.shownBackground)
              let export = try await model.renderExport()
              #expect(shown.canvasRect.size == CGSize(width: export.image.width, height: export.image.height), "\(aspect)")
          }

          let model = makeModel()
          model.tool = .crop
          model.cropDraft = CGRect(x: 2, y: 3, width: 10, height: 8)
          model.applyCrop()
          var style = solid(red)
          style.aspect = .sixteenNine
          model.setBackground(style)
          let shown = try #require(model.shownBackground)
          let export = try await model.renderExport()
          let layout = try #require(BackgroundLayout.make(contentSize: CGSize(width: 10, height: 8), style: style, scale: 2))
          #expect(shown.contentRect == CGRect(x: 2, y: 3, width: 10, height: 8))
          #expect(shown.canvasRect.size == layout.canvasSize)
          #expect(CGSize(width: export.image.width, height: export.image.height) == layout.canvasSize)
      }

      /// phase-7c :147, phase-7c :150. A tall capture (14,000 px, as a scrolling capture of `tall.html`) takes a
      /// background and exports with the padding; an 18,000 px one does not until a crop brings the content
      /// under the limit. Undo after that takes the background step first (the line's first outcome), then the
      /// crop, and the bare capture still exports.
      @Test func aBackgroundFitsTallContentAndACropUnderTheLimit() async throws {
          let style = solid(red)
          let tall = makeModel(width: 10, height: 14_000, scale: 2)
          #expect(tall.backgroundFits(style))
          tall.setBackground(style)
          let tallExport = try await tall.renderExport()
          #expect(tallExport.image.width == 10 + 16)
          #expect(tallExport.image.height == 14_000 + 16)

          let taller = makeModel(width: 10, height: 18_000, scale: 2)
          #expect(!taller.backgroundFits(style))
          taller.tool = .crop
          taller.cropDraft = CGRect(x: 0, y: 0, width: 10, height: 10_000)
          taller.applyCrop()
          #expect(taller.backgroundFits(style))
          taller.setBackground(style)
          let croppedExport = try await taller.renderExport()
          #expect(croppedExport.image.height == 10_000 + 16)

          taller.undoManager.undo()
          #expect(taller.document.background == nil)
          #expect(taller.document.crop != nil)
          taller.undoManager.undo()
          #expect(taller.document.crop == nil)
          let bareExport = try await taller.renderExport()
          #expect(bareExport.image.height == 18_000)
      }

      /// phase-7c :158, phase-7c :164. With a background on, the Crop tool hides it (the handles work on the whole
      /// capture); Escape (`cancelCrop`) brings it back around the whole capture; an applied crop is framed; and
      /// undoing the crop frames the whole capture again, with the background still on.
      @Test func theCropToolHidesTheBackgroundAndCancelOrUndoReturnsItAroundTheWholeCapture() {
          let model = makeModel()
          model.setBackground(solid(red))
          let whole = CGRect(x: 0, y: 0, width: 16, height: 16)
          let crop = CGRect(x: 2, y: 2, width: 8, height: 8)

          model.tool = .crop
          #expect(model.shownBackground == nil)
          #expect(model.cropDraft == whole)
          model.cropDraft = crop
          model.cancelCrop()
          #expect(model.shownBackground?.contentRect == whole)

          model.tool = .crop
          model.cropDraft = crop
          model.applyCrop()
          #expect(model.shownBackground?.contentRect == crop)
          model.undoManager.undo()
          #expect(model.document.crop == nil)
          #expect(model.document.background != nil)
          #expect(model.shownBackground?.contentRect == whole)
      }
  ```
- [ ] Run `EditorModelTests`, `CounterTests`, `EditorFlattenerTests` and `EditorBackgroundExportTests` alone, then the full suite: `Test run with 2239 tests in 187 suites passed`.
- [ ] Commit: `test: checklist editor model, counter, crop and background cases`.

### Task 9: The canvas's events, accessibility, fit and tools [integration]

**Files:** create `TidyShotTests/CanvasViewEventTests.swift`; modify `TidyShotTests/CanvasAccessibilityTests.swift`, `TidyShotTests/CanvasFitTests.swift`, `TidyShotTests/CanvasToolTests.swift`.

Every canvas here has no window. Its transform snaps to `NSScreen.main`'s backing scale, so the tests compare transforms with each other and with the view's bounds, never with fixed numbers. Mouse events are placed with `canvas.convert(_:to: nil)`, the inverse of the conversion `CanvasView` applies to `locationInWindow`, so a test names a view point (or an image point through `model.transform.viewPoint`) and the canvas reads it back (D18). No path here beeps: none sends an unhandled key or a paste with nothing to paste.

**Steps:**
- [ ] Create `CanvasViewEventTests.swift`:
  ```swift
  import AppKit
  import Testing
  @testable import TidyShot

  /// Synthesized pointer and key events on a windowless `CanvasView` over an `EditorModel` with
  /// `FakeTileRenderer` (spec 2.6, Phase 4b): what a letter, Space, a re-edit, a crop and object copy and paste do
  /// on the canvas itself.
  struct CanvasViewEventTests {
      let red = RGBA(red: 1, green: 0, blue: 0, alpha: 1)

      /// A canvas over an 800 x 600 capture at `scale`, fitted into 300 x 200 points.
      func makeCanvas(scale: CGFloat = 2) -> (canvas: CanvasView, model: EditorModel) {
          let context = CGContext(data: nil, width: 800, height: 600, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
          context.setFillColor(CGColor(srgbRed: 0.5, green: 0.5, blue: 0.5, alpha: 1))
          context.fill(CGRect(x: 0, y: 0, width: 800, height: 600))
          let model = EditorModel(recordID: UUID(), image: ScaledImage(image: context.makeImage()!, scale: scale),
                                  renderer: FakeTileRenderer(), defaults: .standard)
          let canvas = CanvasView(model: model, baseView: BaseImageView(frame: .zero))
          canvas.setFrameSize(NSSize(width: 300, height: 200))
          return (canvas, model)
      }

      /// A left-button event at `point` in the canvas's own coordinates.
      func mouse(_ type: NSEvent.EventType, at point: CGPoint, in canvas: CanvasView) -> NSEvent {
          NSEvent.mouseEvent(with: type, location: canvas.convert(point, to: nil), modifierFlags: [], timestamp: 0,
                             windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1,
                             pressure: type == .leftMouseUp ? 0 : 1)!
      }

      /// A press at `start`, one move to `end` and the release there, in view points.
      func drag(_ canvas: CanvasView, from start: CGPoint, to end: CGPoint) {
          canvas.mouseDown(with: mouse(.leftMouseDown, at: start, in: canvas))
          canvas.mouseDragged(with: mouse(.leftMouseDragged, at: end, in: canvas))
          canvas.mouseUp(with: mouse(.leftMouseUp, at: end, in: canvas))
      }

      func key(_ characters: String, _ keyCode: UInt16, up: Bool = false) -> NSEvent {
          NSEvent.keyEvent(with: up ? .keyUp : .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                           windowNumber: 0, context: nil, characters: characters, charactersIgnoringModifiers: characters,
                           isARepeat: false, keyCode: keyCode)!
      }

      func rect(of annotation: Annotation?) -> CGRect? {
          if case .rectangle(let box)? = annotation { return box.rect }
          return nil
      }

      /// The clipboard two editors share, standing in for the coordinator's (`EditorObjectClipboard`).
      final class ObjectClips {
          var data: Data?
          private(set) var writes = 0

          var clipboard: EditorObjectClipboard {
              EditorObjectClipboard(copy: { [self] in data = $0; writes += 1 }, paste: { [self] in data },
                                    canPaste: { [self] in data != nil })
          }
      }

      /// phase-4b :30, in part. A letter pressed in the middle of a drag does nothing; after the release the same
      /// letter picks its tool. By hand: the toolbar following the tool (the letters themselves are
      /// `KeyRoutingTests.lettersSelectTools`, `.editingTextSuppressesLetters`).
      @Test func aLetterPressedDuringADragKeepsTheTool() {
          let (canvas, model) = makeCanvas()
          canvas.keyDown(with: key("r", 15))
          #expect(model.tool == .rectangle)

          canvas.mouseDown(with: mouse(.leftMouseDown, at: CGPoint(x: 100, y: 60), in: canvas))
          canvas.mouseDragged(with: mouse(.leftMouseDragged, at: CGPoint(x: 160, y: 120), in: canvas))
          canvas.keyDown(with: key("e", 14))
          #expect(model.tool == .rectangle)
          canvas.mouseUp(with: mouse(.leftMouseUp, at: CGPoint(x: 160, y: 120), in: canvas))
          #expect(model.document.annotations.count == 1)

          canvas.keyDown(with: key("e", 14))
          #expect(model.tool == .ellipse)
      }

      /// phase-4b :56. Re-editing a committed text puts the caret at the end of its string, in a text view at the
      /// text's own frame through the canvas's transform.
      @Test func reEditingATextPutsTheCaretAtTheEndInTheTextsFrame() async throws {
          let (canvas, model) = makeCanvas()
          let box = TextBox(id: UUID(), string: "Hello", origin: CGPoint(x: 200, y: 200), fontSize: 40, color: red)
          model.commit(model.document.appending(.text(box)), actionName: "Add Text")

          model.beginTextEditing(at: CGPoint(x: 210, y: 210), existing: box.id)
          // The canvas installs the text view on its next refresh, which the model's observation schedules.
          try await eventually { canvas.subviews.contains { $0 is NSTextView } }

          let view = try #require(canvas.subviews.compactMap { $0 as? NSTextView }.first)
          #expect(view.string == "Hello")
          #expect(view.selectedRange() == NSRange(location: 5, length: 0))
          let frame = TextLayout.frame(for: box)
          #expect(view.frame.origin == model.transform.viewPoint(frame.origin))
          #expect(view.frame.width == frame.width * model.transform.zoom)
          #expect(view.frame.height == frame.height * model.transform.zoom)
      }

      /// phase-4b :82. With a crop applied, input stops at the crop's edge: a Rectangle dragged from inside out into the
      /// covered area ends on the edge, one dragged from the covered area in starts on it, and a click in the
      /// covered area with Text starts no text.
      @Test func drawingUnderAnAppliedCropStopsAtItsEdge() {
          let (canvas, model) = makeCanvas()
          let crop = CGRect(x: 200, y: 150, width: 400, height: 300)
          model.tool = .crop
          model.cropDraft = crop
          model.applyCrop()
          canvas.keyDown(with: key("r", 15))
          canvas.fitToView()
          let view = { (image: CGPoint) in model.transform.viewPoint(image) }

          drag(canvas, from: view(CGPoint(x: 300, y: 250)), to: view(CGPoint(x: 700, y: 550)))
          let outward = rect(of: model.document.annotations.last)
          #expect(abs((outward?.minX ?? 0) - 300) < 0.01)
          #expect(abs((outward?.maxX ?? 0) - crop.maxX) < 0.01)
          #expect(abs((outward?.maxY ?? 0) - crop.maxY) < 0.01)

          drag(canvas, from: view(CGPoint(x: 100, y: 100)), to: view(CGPoint(x: 400, y: 300)))
          let inward = rect(of: model.document.annotations.last)
          #expect(abs((inward?.minX ?? 0) - crop.minX) < 0.01)
          #expect(abs((inward?.minY ?? 0) - crop.minY) < 0.01)
          #expect(model.document.annotations.count == 2)

          canvas.keyDown(with: key("t", 17))
          let covered = view(CGPoint(x: 100, y: 100))
          canvas.mouseDown(with: mouse(.leftMouseDown, at: covered, in: canvas))
          canvas.mouseUp(with: mouse(.leftMouseUp, at: covered, in: canvas))
          #expect(!model.isEditingText)
          #expect(model.document.annotations.count == 2)
      }

      /// phase-4b :91. An object copied in one editor pastes into another, selected, with the same string, colour and
      /// point size, also from a 2x capture into a 1x one: a text, a pencil stroke and a redaction. The first
      /// editor is unchanged, and only the second has unsaved changes.
      @Test func anObjectCopiedInOneCanvasPastesIntoAnotherAtItsPointSize() throws {
          let clips = ObjectClips()
          let (first, source) = makeCanvas(scale: 2)
          let (second, target) = makeCanvas(scale: 1)
          first.objectClipboard = clips.clipboard
          second.objectClipboard = clips.clipboard
          let text = Annotation.text(TextBox(id: UUID(), string: "Note", origin: CGPoint(x: 100, y: 100), fontSize: 40,
                                             color: red))
          let stroke = Annotation.pencil(Stroke(id: UUID(), points: [CGPoint(x: 100, y: 300), CGPoint(x: 160, y: 320),
                                                                     CGPoint(x: 220, y: 300)], color: red, lineWidth: 8))
          let redaction = Annotation.redact(Region(id: UUID(), rect: CGRect(x: 400, y: 100, width: 80, height: 40)),
                                            fill: RGBA(red: 0, green: 0, blue: 0, alpha: 1))
          source.commit(AnnotationDocument(annotations: [text, stroke, redaction]), actionName: "Add")
          source.markSaved()
          let before = source.document

          for original in [text, stroke, redaction] {
              source.selection = original.id
              first.copy(nil)
              second.paste(nil)
              let pasted = try #require(target.document.annotations.last)
              #expect(target.selection == pasted.id)
              switch (original, pasted) {
              case (.text(let from), .text(let to)):
                  #expect(to.string == from.string)
                  #expect(to.color == from.color)
                  #expect(to.fontSize == from.fontSize / 2)
              case (.pencil(let from), .pencil(let to)):
                  #expect(to.color == from.color)
                  #expect(to.lineWidth == from.lineWidth / 2)
              case (.redact(let from, let fromFill), .redact(let to, let toFill)):
                  #expect(toFill == fromFill)
                  #expect(to.rect.size == CGSize(width: from.rect.width / 2, height: from.rect.height / 2))
              default:
                  Issue.record("pasted \(pasted.title) for \(original.title)")
              }
          }

          #expect(clips.writes == 3)
          #expect(source.document == before)
          #expect(!source.hasUnsavedChanges)
          #expect(target.hasUnsavedChanges)
      }

      /// phase-4b :99, in part; phase-4b :100. Space pressed in the middle of a Rectangle drag starts no pan, the drag
      /// draws and the next drag draws again; Space let go mid-pan keeps panning until the release; after
      /// `endSpacePan()` (the window's resign-key) a press reaches the tool; with a crop pending, a Space-drag pans and
      /// leaves the draft where it was. By hand (phase-4b :99): the ⌘-Tab itself.
      @Test func spacePansOnlyBetweenDragsAndNeverMovesACropDraft() {
          let (canvas, model) = makeCanvas()
          let space = key(" ", 49)
          let spaceUp = key(" ", 49, up: true)
          canvas.keyDown(with: key("r", 15))
          let fitted = model.transform

          canvas.mouseDown(with: mouse(.leftMouseDown, at: CGPoint(x: 100, y: 60), in: canvas))
          canvas.keyDown(with: space)
          canvas.mouseDragged(with: mouse(.leftMouseDragged, at: CGPoint(x: 160, y: 120), in: canvas))
          canvas.keyUp(with: spaceUp)
          canvas.mouseUp(with: mouse(.leftMouseUp, at: CGPoint(x: 160, y: 120), in: canvas))
          #expect(model.document.annotations.count == 1)
          #expect(model.transform == fitted)
          drag(canvas, from: CGPoint(x: 120, y: 70), to: CGPoint(x: 170, y: 110))
          #expect(model.document.annotations.count == 2)

          canvas.keyDown(with: space)
          canvas.mouseDown(with: mouse(.leftMouseDown, at: CGPoint(x: 100, y: 60), in: canvas))
          canvas.mouseDragged(with: mouse(.leftMouseDragged, at: CGPoint(x: 130, y: 60), in: canvas))
          let panned = model.transform
          #expect(panned != fitted)
          canvas.keyUp(with: spaceUp)
          canvas.mouseDragged(with: mouse(.leftMouseDragged, at: CGPoint(x: 160, y: 60), in: canvas))
          #expect(model.transform != panned)
          canvas.mouseUp(with: mouse(.leftMouseUp, at: CGPoint(x: 160, y: 60), in: canvas))
          #expect(model.document.annotations.count == 2)

          canvas.keyDown(with: space)
          canvas.endSpacePan()
          drag(canvas, from: CGPoint(x: 100, y: 60), to: CGPoint(x: 150, y: 100))
          #expect(model.document.annotations.count == 3)

          canvas.keyDown(with: key("c", 8))
          #expect(model.tool == .crop)
          let draft = CGRect(x: 100, y: 100, width: 300, height: 200)
          model.cropDraft = draft
          let beforePan = model.transform
          canvas.keyDown(with: space)
          let inside = model.transform.viewPoint(CGPoint(x: 250, y: 200))
          drag(canvas, from: inside, to: CGPoint(x: inside.x + 40, y: inside.y + 20))
          canvas.keyUp(with: spaceUp)
          #expect(model.cropDraft == draft)
          #expect(model.transform != beforePan)
      }
  }
  ```
- [ ] In `CanvasAccessibilityTests.swift`, add `import AppKit` above `import CoreGraphics`, and add after `redaction(_:)`:
  ```swift
      /// A canvas over a 200 x 150 capture at scale 1, fitted into 300 x 200 points, with no window.
      func makeCanvas() -> (canvas: CanvasView, model: EditorModel) {
          let context = CGContext(data: nil, width: 200, height: 150, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
          context.setFillColor(CGColor(srgbRed: 0.5, green: 0.5, blue: 0.5, alpha: 1))
          context.fill(CGRect(x: 0, y: 0, width: 200, height: 150))
          let model = EditorModel(recordID: UUID(), image: ScaledImage(image: context.makeImage()!, scale: 1),
                                  renderer: FakeTileRenderer(), defaults: .standard)
          let canvas = CanvasView(model: model, baseView: BaseImageView(frame: .zero))
          canvas.setFrameSize(NSSize(width: 300, height: 200))
          return (canvas, model)
      }

      func elements(_ canvas: CanvasView) -> [AnnotationAccessibilityElement] {
          (canvas.accessibilityChildren() ?? []).compactMap { $0 as? AnnotationAccessibilityElement }
      }

      func element(_ id: UUID, in canvas: CanvasView) throws -> AnnotationAccessibilityElement {
          try #require(elements(canvas).first { $0.annotationID == id })
      }

      func key(_ characters: String, _ keyCode: UInt16) -> NSEvent {
          NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
                           characters: characters, charactersIgnoringModifiers: characters, isARepeat: false,
                           keyCode: keyCode)!
      }
  ```
  and the three tests at the end of the struct:
  ```swift
      /// phase-4b :128. The canvas's elements follow edits at once: one element is kept for an annotation across a
      /// move and a resize, none is left for a deleted one, and a new one takes its place in painting order (a
      /// drawing last, an effect after the other effects).
      @Test func canvasElementsFollowMovesResizesDeletesAndAdds() throws {
          let (canvas, model) = makeCanvas()
          let line = arrow(10)
          let box = Annotation.rectangle(ShapeBox(id: UUID(), rect: CGRect(x: 20, y: 40, width: 30, height: 20), color: red,
                                                  lineWidth: 4))
          let hidden = redaction(100)
          model.commit(AnnotationDocument(annotations: [line, box, hidden]), actionName: "Add")
          let boxElement = try element(box.id, in: canvas)

          model.commit(model.document.moving(id: box.id, by: CGVector(dx: 10, dy: 5)), actionName: "Move")
          #expect(try element(box.id, in: canvas) === boxElement)
          let resized = Annotation.rectangle(ShapeBox(id: box.id, rect: CGRect(x: 30, y: 45, width: 60, height: 40),
                                                      color: red, lineWidth: 4))
          model.commit(model.document.replacing(resized), actionName: "Resize")
          #expect(try element(box.id, in: canvas) === boxElement)

          model.commit(model.document.removing(id: line.id), actionName: "Delete")
          #expect(!elements(canvas).contains { $0.annotationID == line.id })

          let ellipse = Annotation.ellipse(ShapeBox(id: UUID(), rect: CGRect(x: 60, y: 60, width: 20, height: 20),
                                                    color: red, lineWidth: 4))
          let blur = Annotation.blur(Region(id: UUID(), rect: CGRect(x: 120, y: 20, width: 20, height: 20)), radius: 8)
          model.commit(model.document.appending(ellipse).appending(blur), actionName: "Add")
          let ids = elements(canvas).map(\.annotationID)
          #expect(ids == CanvasAccessibility.items(in: model.document, scale: model.scale).map(\.id))
          #expect(ids == [hidden.id, blur.id, box.id, ellipse.id])
          #expect(try element(box.id, in: canvas) === boxElement)
      }

      /// phase-4b :129, phase-4b :131, phase-4c :209, in part. VO-Space (AXPress) on an element selects its annotation,
      /// which the canvas reports as selected, and pressing another moves that state; Delete, the arrow keys, ⌘C and
      /// ⌘D then act on it. By hand (phase-4c :209): VoiceOver itself, and the canvas's own list with a crop.
      @Test func anAccessibilityPressSelectsAndTheCanvasActsOnTheSelection() throws {
          let (canvas, model) = makeCanvas()
          var writes = 0
          canvas.objectClipboard = EditorObjectClipboard(copy: { _ in writes += 1 }, paste: { nil }, canPaste: { false })
          let first = arrow(10)
          let second = arrow(60)
          let third = arrow(110)
          model.commit(AnnotationDocument(annotations: [first, second, third]), actionName: "Add")
          let firstElement = try element(first.id, in: canvas)
          let secondElement = try element(second.id, in: canvas)

          #expect(firstElement.accessibilityPerformPress())
          #expect(model.selection == first.id)
          #expect(firstElement.isAccessibilitySelected())
          #expect(!secondElement.isAccessibilitySelected())
          let selected = (canvas.accessibilitySelectedChildren() ?? []).compactMap { $0 as? AnnotationAccessibilityElement }
          #expect(selected.map(\.annotationID) == [first.id])

          #expect(secondElement.accessibilityPerformPress())
          #expect(model.selection == second.id)
          #expect(secondElement.isAccessibilitySelected())
          #expect(!firstElement.isAccessibilitySelected())

          canvas.moveLeft(nil)
          #expect(model.document.annotation(id: second.id) == second.moved(by: CGVector(dx: -1, dy: 0)))
          canvas.copy(nil)
          #expect(writes == 1)
          canvas.duplicate(nil)
          #expect(model.document.annotations.count == 4)
          #expect(try element(third.id, in: canvas).accessibilityPerformPress())
          canvas.deleteBackward(nil)
          #expect(model.document.annotation(id: third.id) == nil)
      }

      /// phase-4b :130, in part; phase-4c :209, in part. AXPress does nothing while the Crop tool is active or while a
      /// drag runs, and the selection stays. The listing under an applied crop is `cropHidesAnnotationsOutsideIt`.
      /// By hand (phase-4b :130): the list while the Crop tool is open over an applied crop.
      @Test func anAccessibilityPressIsRefusedWithTheCropToolOrDuringADrag() throws {
          let (canvas, model) = makeCanvas()
          let first = arrow(10)
          let second = arrow(60)
          model.commit(AnnotationDocument(annotations: [first, second]), actionName: "Add")
          let firstElement = try element(first.id, in: canvas)
          let secondElement = try element(second.id, in: canvas)

          canvas.keyDown(with: key("c", 8))
          #expect(model.tool == .crop)
          #expect(!secondElement.accessibilityPerformPress())
          #expect(model.selection == nil)
          canvas.cancelOperation(nil)

          canvas.keyDown(with: key("v", 9))
          #expect(firstElement.accessibilityPerformPress())
          let onFirst = canvas.convert(model.transform.viewPoint(CGPoint(x: 25, y: 10)), to: nil)
          canvas.mouseDown(with: NSEvent.mouseEvent(with: .leftMouseDown, location: onFirst, modifierFlags: [], timestamp: 0,
                                                    windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1,
                                                    pressure: 1)!)
          #expect(!secondElement.accessibilityPerformPress())
          #expect(model.selection == first.id)
          canvas.mouseUp(with: NSEvent.mouseEvent(with: .leftMouseUp, location: onFirst, modifierFlags: [], timestamp: 0,
                                                  windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1,
                                                  pressure: 0)!)
      }
  ```
- [ ] In `CanvasFitTests.swift`, add after `afterResize(_:_:)`:
  ```swift
      /// A left-button event at `point` in the canvas's own coordinates.
      func mouse(_ type: NSEvent.EventType, at point: CGPoint, in canvas: CanvasView) -> NSEvent {
          NSEvent.mouseEvent(with: type, location: canvas.convert(point, to: nil), modifierFlags: [], timestamp: 0,
                             windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1,
                             pressure: type == .leftMouseUp ? 0 : 1)!
      }

      func key(_ characters: String, _ keyCode: UInt16, up: Bool = false) -> NSEvent {
          NSEvent.keyEvent(with: up ? .keyUp : .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                           windowNumber: 0, context: nil, characters: characters, charactersIgnoringModifiers: characters,
                           isARepeat: false, keyCode: keyCode)!
      }

      /// A solid background with a 48 pt margin, no corner radius and no shadow.
      func plainBackground() -> BackgroundStyle {
          BackgroundStyle(fill: .solid(RGBA(red: 1, green: 1, blue: 1, alpha: 1)), padding: 48, cornerRadius: 0, shadow: false)
      }

      /// True when `rect` (image pixels) shows centred in the view's inset box, inside it and touching it on one
      /// axis, within a point (the transform snaps to the backing scale).
      func isFitted(_ rect: CGRect, _ model: EditorModel, _ canvas: CanvasView) -> Bool {
          let shown = model.transform.viewRect(rect)
          let box = canvas.bounds.insetBy(dx: EditorWindowGeometry.inset, dy: EditorWindowGeometry.inset)
          let centred = abs(shown.midX - box.midX) <= 1 && abs(shown.midY - box.midY) <= 1
          let inside = shown.minX >= box.minX - 1 && shown.maxX <= box.maxX + 1
              && shown.minY >= box.minY - 1 && shown.maxY <= box.maxY + 1
          let touches = abs(shown.width - box.width) <= 1 || abs(shown.height - box.height) <= 1
          return centred && inside && touches
      }
  ```
  and the three tests at the end of the struct:
  ```swift
      /// phase-4b :101. A Space-drag at Fit moves the picture, and the fit no longer follows a resize, as after a
      /// scroll; Fit to View (⌘0) fits again, and the fit follows resizes again.
      @Test func aSpaceDragStopsTheFitOnResizeAndFitToViewBringsItBack() {
          let (canvas, model) = makeCanvas()
          canvas.keyDown(with: key(" ", 49))
          canvas.mouseDown(with: mouse(.leftMouseDown, at: CGPoint(x: 100, y: 100), in: canvas))
          canvas.mouseDragged(with: mouse(.leftMouseDragged, at: CGPoint(x: 140, y: 120), in: canvas))
          canvas.mouseUp(with: mouse(.leftMouseUp, at: CGPoint(x: 140, y: 120), in: canvas))
          canvas.keyUp(with: key(" ", 49, up: true))

          let after = afterResize(canvas, model)
          #expect(after.shown != after.fit)
          // `afterResize` ends with `fitToView()`, so the fit follows the next resize.
          canvas.setFrameSize(NSSize(width: 420, height: 300))
          let followed = model.transform
          canvas.fitToView()
          #expect(followed == model.transform)
      }

      /// phase-7c :144, phase-7c :157, phase-7c :199. At Fit the whole canvas (the background's margin included) fits
      /// the view and stays fitted while it resizes; actual size is the capture's natural scale; an aspect change
      /// at Fit refits; and with no background the fit is the bare capture's, as a canvas that never had one.
      @Test func theFitFramesTheBackgroundsCanvasAndRefitsOnAnAspectChange() async throws {
          let (canvas, model) = makeCanvas()
          let bare = model.transform
          model.setBackground(plainBackground())
          try await eventually { model.transform != bare }
          let shown = try #require(model.shownBackground)
          #expect(isFitted(shown.canvasRect, model, canvas))
          #expect(model.transform.zoom < bare.zoom)

          canvas.setFrameSize(NSSize(width: 420, height: 300))
          #expect(isFitted(shown.canvasRect, model, canvas))

          canvas.zoom(to: 1 / model.scale)
          #expect(abs(model.transform.zoom - 1 / model.scale) < 0.0001)

          canvas.fitToView()
          let before = model.transform
          var style = try #require(model.document.background)
          style.aspect = .square
          model.backgroundDraft = style
          model.commitBackgroundDraft()
          try await eventually { model.transform != before }
          let square = try #require(model.shownBackground)
          #expect(square.canvasRect.width == square.canvasRect.height)
          #expect(isFitted(square.canvasRect, model, canvas))

          model.setBackground(nil)
          let (fresh, freshModel) = makeCanvas()
          fresh.setFrameSize(NSSize(width: 420, height: 300))
          try await eventually { model.transform == freshModel.transform }
          #expect(model.shownBackground == nil)
      }

      /// phase-7c :156. With a background on, a Rectangle dragged from where the capture's corner is drawn starts at
      /// pixel (0, 0), not offset by the margin, so annotations land where the pointer is.
      @Test func aPointerOnTheCaptureMapsToItsPixelWithABackground() async throws {
          let (canvas, model) = makeCanvas()
          let bare = model.transform
          model.setBackground(plainBackground())
          try await eventually { model.transform != bare }
          canvas.keyDown(with: key("r", 15))
          let shown = try #require(model.shownBackground)
          let corner = model.transform.viewPoint(.zero)
          // The capture is drawn inside the canvas, by the margin.
          #expect(corner.x - model.transform.viewRect(shown.canvasRect).minX > 1)

          let end = model.transform.viewPoint(CGPoint(x: 200, y: 100))
          canvas.mouseDown(with: mouse(.leftMouseDown, at: corner, in: canvas))
          canvas.mouseDragged(with: mouse(.leftMouseDragged, at: end, in: canvas))
          canvas.mouseUp(with: mouse(.leftMouseUp, at: end, in: canvas))

          guard case .rectangle(let drawn)? = model.document.annotations.last else {
              Issue.record("no rectangle")
              return
          }
          #expect(abs(drawn.rect.minX) < 0.01)
          #expect(abs(drawn.rect.minY) < 0.01)
          #expect(abs(drawn.rect.maxX - 200) < 0.01)
      }
  ```
- [ ] Add at the end of `CanvasToolTests`:
  ```swift
      /// phase-4b :61. A selected text moves with a drag, as one step, Delete removes it, and it has no handles.
      @Test func aSelectedTextMovesAndDeletesAndHasNoHandles() throws {
          let box = TextBox(id: UUID(), string: "Here", origin: CGPoint(x: 100, y: 100), fontSize: 40, color: red)
          let text = Annotation.text(box)
          let canvas = FakeCanvasEditing([text])
          let tool = makeTool(for: .select)
          let inside = CGPoint(x: TextLayout.frame(for: box).midX, y: TextLayout.frame(for: box).midY)

          tool.mouseDown(ToolInput(point: inside), on: canvas)
          #expect(canvas.selection == text.id)
          tool.mouseDragged(ToolInput(point: CGPoint(x: inside.x + 20, y: inside.y + 10)), on: canvas)
          tool.mouseUp(ToolInput(point: CGPoint(x: inside.x + 20, y: inside.y + 10)), on: canvas)
          #expect(canvas.commits.count == 1)
          #expect(canvas.commits.first?.actionName == "Move Text")
          #expect(canvas.document.annotation(id: text.id) == text.moved(by: CGVector(dx: 20, dy: 10)))
          #expect(HitTester.handles(for: text).isEmpty)

          let model = EditorModelTests().makeModel(side: 400)
          model.commit(model.document.appending(text), actionName: "Add Text")
          model.selection = text.id
          model.deleteSelection()
          #expect(model.document.annotation(id: text.id) == nil)
      }

      /// phase-4b :80 (the draft's minimum). A crop draft's handle dragged below the tiny-drag size (2 pt, so 2 px at
      /// this zoom) leaves the last draft that was large enough, and nothing crashes.
      @Test func aCropDraftStopsAtTheTinyDragSize() {
          let canvas = FakeCanvasEditing()
          canvas.cropDraft = CGRect(x: 10, y: 10, width: 20, height: 10)
          let tool = makeTool(for: .crop)

          tool.mouseDown(at(30, 20), on: canvas)
          tool.mouseDragged(at(20, 15), on: canvas)
          #expect(canvas.cropDraft == CGRect(x: 10, y: 10, width: 10, height: 5))
          tool.mouseDragged(at(11, 11), on: canvas)
          #expect(canvas.cropDraft == CGRect(x: 10, y: 10, width: 10, height: 5))
          tool.mouseDragged(at(10, 10), on: canvas)
          tool.mouseUp(at(10, 10), on: canvas)
          #expect(canvas.cropDraft == CGRect(x: 10, y: 10, width: 10, height: 5))
          #expect(canvas.commits.isEmpty)
      }
  ```
- [ ] Run `CanvasViewEventTests`, `CanvasAccessibilityTests`, `CanvasFitTests` and `CanvasToolTests` alone, then the full suite: `Test run with 2252 tests in 188 suites passed`.
- [ ] Commit: `test: checklist canvas event, accessibility, fit and tool cases`.

### Task 10: The selection overlay, the card's drag view, the panels and the submenu [integration]

**Files:** create `TidyShotTests/SelectionViewTests.swift`, `TidyShotTests/QuickAccessCardDragViewTests.swift`, `TidyShotTests/RecentCapturesMenuTests.swift`; modify `TidyShotTests/SelfTimerTests.swift`, `TidyShotTests/ClickRingOverlayTests.swift`, `TidyShotTests/QuickAccessModelTests.swift`.

**Steps:**
- [ ] Create `SelectionViewTests.swift`:
  ```swift
  import AppKit
  import Testing
  @testable import TidyShot

  /// The selection overlay's own events (spec 2.9 and R4 design, Record Screen's preset rect): a `SelectionView` in a
  /// borderless window that is never shown, driven by synthesized events, as `SelectionViewArmingTests` does; its
  /// completion converts the rect through that window. A key the view leaves to `super.keyDown` goes to a responder
  /// that keeps it, where the window would beep (D10).
  struct SelectionViewTests {
      let rect = CGRect(x: 100, y: 100, width: 400, height: 200)

      final class Fired {
          var completed: [CGRect] = []
          var cancels = 0
          var pickedWindow = 0
          var actions: [AllInOneAction] = []
          var rectsSet: [Bool] = []
          var emptyClicks = 0
      }

      /// Keeps the keys the view passes up the responder chain.
      final class KeySink: NSResponder {
          private(set) var keyCodes: [UInt16] = []

          override func keyDown(with event: NSEvent) {
              keyCodes.append(event.keyCode)
          }
      }

      nonisolated enum Mode: CaseIterable, Sendable {
          case area
          case window
      }

      func makeView(_ mode: SelectionMode) -> (view: SelectionView, window: NSWindow, fired: Fired, sink: KeySink) {
          let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 1000, height: 800), styleMask: .borderless,
                                backing: .buffered, defer: true)
          window.isReleasedWhenClosed = false
          let view = SelectionView(frame: CGRect(x: 0, y: 0, width: 1000, height: 800))
          view.mode = mode
          window.contentView = view
          let sink = KeySink()
          view.nextResponder = sink
          let fired = Fired()
          view.onComplete = { fired.completed.append($0) }
          view.onCancel = { fired.cancels += 1 }
          view.onPickWindow = { fired.pickedWindow += 1 }
          view.onAllInOneAction = { action, _ in fired.actions.append(action) }
          view.onAdjustRectSet = { fired.rectsSet.append($0) }
          view.onEmptyClick = { fired.emptyClicks += 1 }
          return (view, window, fired, sink)
      }

      func key(_ keyCode: UInt16, _ characters: String, _ flags: NSEvent.ModifierFlags = [], in window: NSWindow) -> NSEvent {
          NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0,
                           windowNumber: window.windowNumber, context: nil, characters: characters,
                           charactersIgnoringModifiers: characters, isARepeat: false, keyCode: keyCode)!
      }

      func mouse(_ type: NSEvent.EventType, at point: CGPoint, in window: NSWindow) -> NSEvent {
          NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: 0,
                             windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1,
                             pressure: type == .leftMouseUp ? 0 : 1)!
      }

      func click(_ view: SelectionView, at point: CGPoint, in window: NSWindow) {
          view.mouseDown(with: mouse(.leftMouseDown, at: point, in: window))
          view.mouseUp(with: mouse(.leftMouseUp, at: point, in: window))
      }

      func drag(_ view: SelectionView, from start: CGPoint, to end: CGPoint, in window: NSWindow) {
          view.mouseDown(with: mouse(.leftMouseDown, at: start, in: window))
          view.mouseDragged(with: mouse(.leftMouseDragged, at: end, in: window))
          view.mouseUp(with: mouse(.leftMouseUp, at: end, in: window))
      }

      /// The toolbar's text field with the accessibility label `label`; the fields are private, so it is found
      /// among the subviews.
      func textField(_ label: String, in view: NSView) -> NSTextField? {
          for subview in view.subviews {
              if let candidate = subview as? NSTextField, candidate.accessibilityLabel() == label { return candidate }
              if let found = textField(label, in: subview) { return found }
          }
          return nil
      }

      /// phase-1 :19, phase-1 :33. Escape before any click cancels an area selection, and cancels a window selection.
      /// The controller's dismiss, which needs `SelectionController.present`, is not reached.
      @Test(arguments: Mode.allCases)
      func escapeCancelsAnAreaOrWindowSelection(mode: Mode) {
          let (view, window, fired, _) = makeView(mode == .area ? .area : .window)

          view.keyDown(with: key(53, "\u{1B}", in: window))

          #expect(fired.cancels == 1)
          #expect(fired.completed.isEmpty)
      }

      /// recording-r4 :208, recording-r4 :311 (gap 4). In a recording selection with a preset rect, Return and Enter do
      /// nothing; a click inside records the preset; a drag, also one that starts inside, records the dragged
      /// area; a click outside on a window picks the window; Escape cancels. No key records.
      @Test func aRecordingSelectionIgnoresReturnAndRecordsAClickInsideTheRect() {
          let (view, window, fired, sink) = makeView(.recording)
          view.presetRect = rect

          view.keyDown(with: key(36, "\r", in: window))
          view.keyDown(with: key(76, "\u{3}", in: window))
          #expect(fired.completed.isEmpty)
          #expect(fired.cancels == 0)
          #expect(sink.keyCodes == [36, 76])

          click(view, at: CGPoint(x: rect.midX, y: rect.midY), in: window)
          #expect(fired.completed == [rect])

          drag(view, from: CGPoint(x: 150, y: 150), to: CGPoint(x: 300, y: 250), in: window)
          #expect(fired.completed == [rect, CGRect(x: 150, y: 150, width: 150, height: 100)])

          view.highlightedRect = CGRect(x: 600, y: 500, width: 200, height: 100)
          click(view, at: CGPoint(x: 700, y: 550), in: window)
          #expect(fired.pickedWindow == 1)

          view.keyDown(with: key(53, "\u{1B}", in: window))
          #expect(fired.cancels == 1)
          #expect(fired.completed.count == 2)
      }

      /// phase-6b :52. In All-in-One a click without a drag takes the highlighted window's frame, fitted to the
      /// display, with Window enabled; a resize and a nudge keep Window enabled; a new drag greys it; a click outside
      /// on another window takes that frame; a click outside on the bare desktop keeps the rect.
      @Test func aClickWithoutADragTakesTheHighlightedWindowAndADragDoesNot() {
          let (view, window, fired, _) = makeView(.allInOne)
          let first = CGRect(x: 100, y: 100, width: 300, height: 200)
          view.highlightedRect = first

          click(view, at: CGPoint(x: 200, y: 200), in: window)
          #expect(view.adjustRect == SelectionAdjust.fitted(first, in: view.bounds))
          #expect(view.adjustRectIsWindow)
          #expect(fired.rectsSet == [true])

          // The right edge's handle, dragged out.
          drag(view, from: CGPoint(x: first.maxX, y: first.midY), to: CGPoint(x: first.maxX + 50, y: first.midY),
               in: window)
          #expect(view.adjustRect?.width == first.width + 50)
          #expect(view.adjustRectIsWindow)
          view.keyDown(with: key(124, "\u{F703}", in: window))
          #expect(view.adjustRect?.minX == first.minX + 1)
          #expect(view.adjustRectIsWindow)

          view.highlightedRect = nil
          drag(view, from: CGPoint(x: 600, y: 500), to: CGPoint(x: 700, y: 600), in: window)
          #expect(view.adjustRect == CGRect(x: 600, y: 500, width: 100, height: 100))
          #expect(!view.adjustRectIsWindow)
          #expect(fired.rectsSet == [true, false])

          let second = CGRect(x: 50, y: 600, width: 200, height: 100)
          view.highlightedRect = second
          click(view, at: CGPoint(x: 60, y: 610), in: window)
          #expect(view.adjustRect == second)
          #expect(view.adjustRectIsWindow)

          view.highlightedRect = nil
          click(view, at: CGPoint(x: 900, y: 100), in: window)
          #expect(view.adjustRect == second)
          #expect(fired.emptyClicks == 0)
      }

      /// phase-6b :53 (a press outside the rect). A press outside the rect and a drag start a new rect, and the pointer
      /// is held to the display while it drags. The handles' geometry is `SelectionAdjustTests`.
      @Test func aPressOutsideTheRectStartsANewOne() {
          let (view, window, _, _) = makeView(.allInOne)
          view.beginAdjusting(rect, fromWindow: false)

          drag(view, from: CGPoint(x: 700, y: 600), to: CGPoint(x: 900, y: 700), in: window)
          #expect(view.adjustRect == CGRect(x: 700, y: 600, width: 200, height: 100))

          drag(view, from: CGPoint(x: 650, y: 550), to: CGPoint(x: 1_200, y: 900), in: window)
          #expect(view.adjustRect == CGRect(x: 650, y: 550, width: 350, height: 250))
      }

      /// phase-6b :55. In All-in-One, Command-Return and Command-arrows neither capture nor nudge (they go on up the
      /// responder chain), and a Shift-arrow moves the rect 10 pt. Plain arrows are
      /// `SelectionViewArmingTests.aDisarmedRectStillNudgesAndCancels`.
      @Test func commandKeysNeitherCaptureNorNudgeAndShiftArrowMovesTen() {
          let (view, window, fired, sink) = makeView(.allInOne)
          view.beginAdjusting(rect, fromWindow: false)

          view.keyDown(with: key(36, "\r", .command, in: window))
          view.keyDown(with: key(124, "\u{F703}", .command, in: window))
          #expect(fired.actions.isEmpty)
          #expect(view.adjustRect == rect)
          #expect(sink.keyCodes == [36, 124])

          view.keyDown(with: key(124, "\u{F703}", .shift, in: window))
          #expect(view.adjustRect == rect.offsetBy(dx: 10, dy: 0))
      }

      /// phase-6b :56. Typing 640 into W and pressing Return makes the width 640, growing from the top-left corner, and
      /// captures nothing; the same for H; a width larger than the room is clamped and moved inside, and the field
      /// then shows the size the rect has; a Return in the overlay then captures; Tab goes from W to H.
      @Test func aTypedWidthResizesFromTheTopLeftWithoutCapturing() throws {
          let (view, window, fired, _) = makeView(.allInOne)
          view.beginAdjusting(rect, fromWindow: false)
          let toolbar = try #require(view.subviews.compactMap { $0 as? AllInOneToolbar }.first)
          let width = try #require(textField("Width", in: toolbar))
          let height = try #require(textField("Height", in: toolbar))
          let newline = #selector(NSResponder.insertNewline(_:))

          width.stringValue = "640"
          #expect(toolbar.control(width, textView: NSTextView(), doCommandBy: newline))
          #expect(view.adjustRect == CGRect(x: 100, y: 100, width: 640, height: 200))
          height.stringValue = "300"
          #expect(toolbar.control(height, textView: NSTextView(), doCommandBy: newline))
          #expect(view.adjustRect == CGRect(x: 100, y: 0, width: 640, height: 300))
          #expect(fired.actions.isEmpty)

          width.stringValue = "5000"
          #expect(toolbar.control(width, textView: NSTextView(), doCommandBy: newline))
          #expect(view.adjustRect == CGRect(x: 0, y: 0, width: 1_000, height: 300))
          #expect(width.stringValue == "1000")
          #expect(fired.actions.isEmpty)

          view.keyDown(with: key(36, "\r", in: window))
          #expect(fired.actions == [.capture])
          #expect(width.nextKeyView === height)
      }
  }
  ```
- [ ] Add at the end of `SelfTimerTests`:
  ```swift
      /// phase-6b :72. The countdown panel and the scrolling capture's dashed frame let clicks through to the app
      /// beneath: both ignore the mouse.
      @Test func theCountdownPanelAndTheScrollFrameLetClicksThrough() {
          let panel = SelfTimerPanel(model: SelfTimerModel(), frame: CGRect(x: 0, y: 0, width: 120, height: 120))
          let frame = ScrollAreaFrameWindow(area: CGRect(x: 100, y: 100, width: 400, height: 300))
          #expect(panel.ignoresMouseEvents)
          #expect(frame.ignoresMouseEvents)
      }
  ```
- [ ] Add to `ClickRingOverlayTests`, after `shapes(of:)`:
  ```swift
      /// A timing function's four control points, so two can be compared.
      func controlPoints(_ function: CAMediaTimingFunction?) -> [Float]? {
          guard let function else { return nil }
          var points: [Float] = []
          for index in 0..<4 {
              var values: [Float] = [0, 0]
              function.getControlPoint(at: index, values: &values)
              points += values
          }
          return points
      }
  ```
  and at the end of the struct:
  ```swift
      /// recording-r3 :440 (call F). The ring's grow eases out and its fade is linear: the grow has the ease-out curve,
      /// and neither the fade group nor its parts has a timing function.
      @Test func theRingGrowsEasingOutAndFadesLinearly() throws {
          let overlay = ClickRingOverlay(screenFrame: screenFrame)
          overlay.apply(.begin(ClickRing(button: .left, colour: .yellow, point: CGPoint(x: 120, y: 80))))
          let ring = try #require(overlay.ringContainer.sublayers?.first)
          let grow = try #require(ring.animation(forKey: ClickRingOverlay.growKey))
          #expect(controlPoints(grow.timingFunction) == controlPoints(CAMediaTimingFunction(name: .easeOut)))

          overlay.apply(.end(.left))
          let fade = try #require(ring.animation(forKey: ClickRingOverlay.fadeKey) as? CAAnimationGroup)
          #expect(fade.timingFunction == nil)
          #expect((fade.animations ?? []).allSatisfy { $0.timingFunction == nil })
      }
  ```
- [ ] Create `QuickAccessCardDragViewTests.swift`:
  ```swift
  import AppKit
  import Testing
  @testable import TidyShot

  /// A Quick Access card's drag surface (`QuickAccessCardDragView`; R4 design, Drag-out download): a press stages the
  /// drag file, and past the 3 pt threshold with no file yet it asks for the download, once per press. With no drag
  /// file no dragging session starts, so the view needs no window: it reads only the events' `locationInWindow`.
  struct QuickAccessCardDragViewTests {
      final class Asked {
          var prepares = 0
          var downloads = 0
      }

      func event(_ type: NSEvent.EventType, at point: CGPoint) -> NSEvent {
          NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
                             eventNumber: 0, clickCount: 1, pressure: type == .leftMouseUp ? 0 : 1)!
      }

      /// recording-r4 :330 (gap 22), in part, recording-r4 :355 (gap 11). A press asks only to stage the drag file;
      /// a 2 pt drag asks nothing; the drag that reaches 3 pt asks for the download once, and the press's later
      /// drags do not; a new press asks again after its own 3 pt drag. By hand: that the card's menu has no download
      /// item (gap 22's second half, D16).
      @Test func theDragViewAsksForTheDownloadOncePerPressPastTheThreshold() {
          let record = CaptureRecord(fileURL: nil, pixelWidth: 1600, pixelHeight: 1000, appName: nil,
                                     uploadState: .uploaded(url: URL(string: "https://snap.tky.io/s/REC.mp4")!,
                                                            key: "s/REC.mp4"),
                                     mediaKind: .video, durationSeconds: 10)
          let model = QuickAccessModel(record: record, thumbnail: nil)
          let asked = Asked()
          model.onPrepareDrag = { asked.prepares += 1 }
          model.onDownloadForDrag = { asked.downloads += 1 }
          let view = QuickAccessCardDragView()
          // The view holds its model weakly; the test keeps it.
          view.model = model

          view.mouseDown(with: event(.leftMouseDown, at: CGPoint(x: 10, y: 10)))
          #expect(asked.prepares == 1)
          #expect(asked.downloads == 0)
          view.mouseDragged(with: event(.leftMouseDragged, at: CGPoint(x: 12, y: 10)))
          #expect(asked.downloads == 0)
          view.mouseDragged(with: event(.leftMouseDragged, at: CGPoint(x: 13, y: 10)))
          #expect(asked.downloads == 1)
          view.mouseDragged(with: event(.leftMouseDragged, at: CGPoint(x: 30, y: 10)))
          view.mouseDragged(with: event(.leftMouseDragged, at: CGPoint(x: 40, y: 20)))
          #expect(asked.downloads == 1)
          view.mouseUp(with: event(.leftMouseUp, at: CGPoint(x: 40, y: 20)))

          view.mouseDown(with: event(.leftMouseDown, at: CGPoint(x: 10, y: 10)))
          #expect(asked.prepares == 2)
          view.mouseDragged(with: event(.leftMouseDragged, at: CGPoint(x: 10, y: 13)))
          #expect(asked.downloads == 2)
          withExtendedLifetime(model) {}
      }
  }
  ```
- [ ] Add at the end of `QuickAccessModelTests`:
  ```swift
      /// phase-3 :42. An upload-only capture's thumbnail reveals nothing in Finder: not while its pending file is kept,
      /// and not after the upload, when it has no file. A saved capture's does.
      @Test func anUploadOnlyCardsThumbnailRevealsNothing() {
          #expect(!model(.uploading(fraction: 0.5), file: pending, temporary: true, kind: .image).canReveal)
          #expect(!model(.uploaded(url: link, key: "aB3dE9.png"), file: nil, kind: .image).canReveal)
          #expect(model(file: saved, kind: .image).canReveal)
      }
  ```
- [ ] Create `RecentCapturesMenuTests.swift`:
  ```swift
  import AppKit
  import Testing
  @testable import TidyShot

  /// The Recent Captures submenu (`RecentCapturesMenu`) over a built coordinator. The menu is built and never
  /// opened; its preview panel is made deferred and only hidden.
  @Suite(.timeLimit(.minutes(1)))
  struct RecentCapturesMenuTests {
      let world: CoordinatorWorld

      init() throws {
          world = try CoordinatorWorld()
      }

      /// phase-3-1 :37. With an empty history the submenu shows one greyed `No captures yet`.
      @Test func anEmptyHistoryShowsOneDisabledNoCapturesYet() {
          defer { world.removeAll() }
          let menu = RecentCapturesMenu(coordinator: world.makeCoordinator(), closeMenus: {}, statusItemFrame: { nil })

          menu.rebuild()

          #expect(menu.menu.items.map(\.title) == ["No captures yet"])
          #expect(menu.menu.items.first?.isEnabled == false)
      }
  }
  ```
- [ ] Run `SelectionViewTests`, `SelfTimerTests`, `ClickRingOverlayTests`, `QuickAccessCardDragViewTests`, `QuickAccessModelTests` and `RecentCapturesMenuTests` alone, then the full suite: `Test run with 2263 tests in 191 suites passed`.
- [ ] Commit: `test: checklist selection overlay, drag view, panel and submenu cases`.

### Task 11: Settings, URL commands, the connection test, GIF, scrolling, templates, thumbnails, part retries [mechanical]

**Files:** modify `TidyShotTests/AppSettingsTests.swift`, `TidyShotTests/URLCommandHandlerTests.swift`, `TidyShotTests/ConnectionTesterTests.swift`, `TidyShotTests/GIFFileSinkTests.swift`, `TidyShotTests/ScrollCaptureSessionTests.swift`, `TidyShotTests/TemplateExpanderTests.swift`, `TidyShotTests/ThumbnailProviderTests.swift`, `TidyShotTests/UploadQueueTests.swift`.

**Consumes:** Task 1 (`partDigests`, `FakeDestination.digest`).

**Steps:**
- [ ] Add at the end of `AppSettingsTests`:
  ```swift
      /// phase-1 :41. After a relaunch the save folder is remembered (its bookmark resolves) and the counter carries on.
      @Test func aSecondInstanceKeepsTheSaveFolderAndContinuesTheCounter() throws {
          let name = "AppSettingsTests-\(UUID().uuidString)"
          let defaults = try #require(UserDefaults(suiteName: name))
          defaults.removePersistentDomain(forName: name)
          defer { defaults.removePersistentDomain(forName: name) }
          let folder = FileManager.default.temporaryDirectory
              .appending(path: "AppSettingsTests-\(UUID().uuidString)", directoryHint: .isDirectory)
          try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
          defer { try? FileManager.default.removeItem(at: folder) }

          try SaveLocation(defaults: defaults).store(folder)
          let first = AppSettings(defaults: defaults)
          #expect(first.nextCounter() == 1)
          #expect(first.nextCounter() == 2)

          let resolved = try #require(SaveLocation(defaults: defaults).currentURL)
          #expect(resolved.standardizedFileURL.resolvingSymlinksInPath().pathComponents
                  == folder.standardizedFileURL.resolvingSymlinksInPath().pathComponents)
          #expect(AppSettings(defaults: defaults).nextCounter() == 3)
      }

      /// recording-r1 :86, recording-r2 :157, recording-r3 :110. The recording settings' defaults are registered, not
      /// written: a fresh domain holds none of their keys while each reads its default, and a key appears once its
      /// setting changes.
      @Test func recordingDefaultsAreRegisteredNotWritten() throws {
          let name = "AppSettingsTests-\(UUID().uuidString)"
          let defaults = try #require(UserDefaults(suiteName: name))
          defaults.removePersistentDomain(forName: name)
          defer { defaults.removePersistentDomain(forName: name) }

          let settings = AppSettings(defaults: defaults)

          let stored = defaults.persistentDomain(forName: name) ?? [:]
          for key in ["recordingFrameRate", "recordingRetina", "recordingSystemAudio", "recordingShowsCursor",
                      "recordingCountdown", "recordingFileNameTemplate", "recordingFormat", "gifFrameRate", "gifMaxSide",
                      "recordingClickHighlights", "recordingWebcamBubble", "recordingBubbleSize"] {
              #expect(stored[key] == nil, "\(key)")
          }
          #expect(settings.recordingFrameRate == 30)
          #expect(settings.recordingFormat == .mp4)
          #expect(settings.gifFrameRate == 15)
          #expect(settings.gifMaxSide == 1280)
          #expect(!settings.recordingWebcamBubble)

          settings.recordingFrameRate = 60
          #expect((defaults.persistentDomain(forName: name) ?? [:])["recordingFrameRate"] as? Int == 60)
      }
  ```
- [ ] Add at the end of `URLCommandHandlerTests`:
  ```swift
      /// phase-6b :153. `capture-area?display=7` with no rect opens the normal selection: the display counts only with
      /// a rect. `display=abc`'s notice is `URLCommandTests.theDisplayIsAWholeNumberFromOne`.
      @Test func aDisplayWithoutARectOpensTheNormalSelection() async throws {
          let handler = await makeHandler()

          try await send(handler, "tidyshot://capture-area?display=7")

          #expect(target.calls == [.area(standard)])
          #expect(log.notices.isEmpty)
      }

      /// phase-6b :161. With silent captures off, a `capture-fullscreen` the gate refuses, queued ahead of a
      /// `capture-window` before the launch finished, does not count as the first capture command: the window
      /// selection still opens.
      @Test func aGateRefusedCaptureDoesNotCountAsTheFirstQueuedOne() async throws {
          settings.urlCommandsAllowSilent = false
          let handler = await makeHandler(ready: false)
          try await send(handler, "tidyshot://capture-fullscreen")
          try await send(handler, "tidyshot://capture-window")

          await handler.ready()

          #expect(target.calls == [.window(standard)])
          #expect(log.notices == [notice("capture-fullscreen from Raycast" + refusal)])
      }
  ```
- [ ] In `ConnectionTesterTests.uploadFailedWhenPutIsRejected` (the extension), add a doc comment and the summary:
  ```swift
      /// phase-3-1 :63 (with `readableSummaryDoesNotEchoTheProbeURL`). A rejected PUT, as a wrong secret gives,
      /// reports `Upload failed: …`.
      @Test func uploadFailedWhenPutIsRejected() async {
          let (session, stub) = StubSession.make { _ in (403, Data("AccessDenied".utf8)) }
          let result = await ConnectionTester.run(destination: destination(session), keyTemplate: config.normalized.keyTemplate, session: session)
          #expect(result.outcome == .uploadFailed("Server returned HTTP 403: AccessDenied"))
          #expect(result.summary == "Upload failed: Server returned HTTP 403: AccessDenied")
          #expect(stub.requests.count == 1)
      }
  ```
- [ ] Add at the end of `GIFFileSinkTests`:
  ```swift
      /// recording-r2 :640 (call A). A recording that cannot be read for its GIF says `The recording could not be
      /// read.`, and the notice is `GIF not made` / `The recording could not be read. The recording was saved as an MP4.`
      @Test func couldNotReadSaysTheRecordingCouldNotBeRead() {
          defer { try? FileManager.default.removeItem(at: folder) }
          #expect(GIFMakerError.couldNotRead.localizedDescription == "The recording could not be read.")
          #expect(GIFConversion.notMade(GIFMakerError.couldNotRead.localizedDescription)
                  == RecordingNotice(title: "GIF not made",
                                     body: "The recording could not be read. The recording was saved as an MP4."))
      }
  ```
- [ ] Add at the end of `ScrollCaptureSessionTests`:
  ```swift
      /// phase-5 :106. Done while the too-fast line shows saves what was stitched before the loss, at its size, with no
      /// half-written rows at the end.
      @Test func doneWhileLostSavesWhatWasStitchedBeforeTheLoss() async throws {
          var page = makePage()
          let (session, source, _) = makeSession(page)
          await session.start()
          send(&page, source, offsets: [0, 100])
          try await eventually { session.heightPixels == 500 }
          send(&page, source, offsets: [700])
          try await eventually { session.status == .manualLost }

          await session.done()

          guard case .image(let image)? = session.outcome else {
              Issue.record("no image")
              return
          }
          #expect(image.image.height == 500)
          let comparison = page.compare(try stitchedPixels(of: image), reached: 100)
          #expect(comparison.actualHeight == comparison.expectedHeight)
          #expect(comparison.mismatched == 0)
      }
  ```
- [ ] Add at the end of `TemplateExpanderTests`:
  ```swift
      /// phase-3-1 :60. The token list both settings captions show (General and Upload) names every token.
      @Test func theTokenListNamesEveryToken() {
          #expect(TemplateExpander.tokenList
                  == "{date} {year} {month} {day} {time} {datetime} {hostname} {counter} {random} {random:8}")
      }
  ```
- [ ] Add to `ThumbnailProviderTests`, after `record(thumbnail:file:)`:
  ```swift
      /// A PNG of `width` by `height` whose top `top` rows are red and the rest blue.
      func twoTonePNG(width: Int, height: Int, top: Int) throws -> Data {
          let context = try #require(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                               space: CGColorSpaceCreateDeviceRGB(),
                                               bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
          context.setFillColor(CGColor(red: 0, green: 0, blue: 1, alpha: 1))
          context.fill(CGRect(x: 0, y: 0, width: width, height: height))
          // CoreGraphics' origin is the bottom left, so the top rows are the highest y.
          context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
          context.fill(CGRect(x: 0, y: height - top, width: width, height: top))
          return try ImageEncoder.pngData(from: try #require(context.makeImage()), scale: 1)
      }

      /// The red and the blue of `image`'s middle pixel.
      func middle(_ image: CGImage) throws -> (red: UInt8, blue: UInt8) {
          let context = try #require(CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                               space: CGColorSpaceCreateDeviceRGB(),
                                               bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
          context.draw(image, in: CGRect(x: -CGFloat(image.width / 2), y: -CGFloat(image.height / 2),
                                         width: CGFloat(image.width), height: CGFloat(image.height)))
          let bytes = try #require(context.data).assumingMemoryBound(to: UInt8.self)
          return (bytes[0], bytes[2])
      }
  ```
  and at the end of the struct:
  ```swift
      /// phase-5 :199. A record whose named thumbnail file is gone gets one made again from its file through ImageIO:
      /// about 213 by 320, showing the top of a tall page, written to the store and named on the record.
      @Test func aNamedThumbnailThatIsGoneIsMadeAgainFromTheFile() async throws {
          let item = record(thumbnail: "gone.png")
          history.add(item)
          let data = try twoTonePNG(width: 640, height: 4_000, top: 960)
          let provider = makeProvider { _, _ in data }

          let image = try #require(await provider.thumbnail(for: item))

          #expect(image.size == CGSize(width: 213, height: 320))
          let name = try #require(history.record(id: item.id)?.thumbnailFileName)
          #expect(name != "gone.png")
          let stored = try Data(contentsOf: store.url(forFileName: name))
          let decoded = try #require(ImageEncoder.decode(stored)?.image)
          let colour = try middle(decoded)
          #expect(colour.red > 200)
          #expect(colour.blue < 50)
      }
  ```
- [ ] Add after `aCancelDuringThePartsWaitsForEveryPart` in `UploadQueueTests`:
  ```swift
      /// recording-r4 :378 (call H). A part's retry sends the bytes the part first read, not a fresh read: part 3's range
      /// changes in the file after its first try is sent, and both tries carry the first bytes' digest. Harness D18
      /// asked for a read counter; changing the file shows the same thing with no seam.
      @Test func aPartRetrySendsTheBytesItFirstRead() async throws {
          let movie = try makeLargeMovie(byteCount: mib)
          defer { try? FileManager.default.removeItem(at: movie.folder) }
          let file = movie.file
          let destination = FakeDestination(.init(onCall: { call in
              guard call == "part 3" else { return }
              // Part 3's bytes were read before this call; overwrite its range in the file.
              guard let handle = try? FileHandle(forWritingTo: file) else { return }
              try? handle.seek(toOffset: 2 * 262_144)
              try? handle.write(contentsOf: Data(repeating: 0xFF, count: 262_144))
              try? handle.close()
          }, partFailures: [3: [.httpStatus(503, body: "")]]))
          let log = EventLog()
          let queue = makeMultipartQueue(destination: destination, log: log, store: movie.store)
          let id = UUID()

          await queue.enqueue(largeJob(id, file: movie.file, byteCount: mib))
          try await eventually { log.events.contains(.uploaded(id: id, url: templateURL, key: templateKey)) }

          let digests = destination.state.withLock { $0.partDigests.filter { $0.number == 3 }.map(\.digest) }
          #expect(digests == Array(repeating: FakeDestination.digest(Data(count: 262_144)), count: 2))
      }
  ```
- [ ] Run the eight suites alone, then the full suite: `Test run with 2272 tests in 191 suites passed`.
- [ ] Commit: `test: checklist settings, URL command, connection, GIF, scrolling, template, thumbnail and part retry cases`.

### Task 12: The checklist marks and the designs' notes [mechanical]

**Files:** modify the checklists in `docs/testing/` that hold a covered line (`coordinator-harness`, `coordinator-split`, `phase-1`, `phase-2`, `phase-3`, `phase-3-1`, `phase-4a`, `phase-4b`, `phase-4c`, `phase-5`, `phase-6a`, `phase-6b`, `phase-7c`, `recording-r1`, `recording-r2`, `recording-r3`, `recording-r4`, `small-tweaks`), `docs/superpowers/specs/2026-10-29-tidyshot-coordinator-harness-design.md` (section 8 and a built-notes line), `docs/superpowers/specs/2026-10-30-tidyshot-checklist-tests-design.md` (section 7's counting sentence and `## 11. Built notes`).

**Gate:** the marks go on PR #28's text (its marks, obsolete lines and corrections move and reword checklist lines). Check for its content, not its commit: `git grep -c '(obsolete: ' HEAD -- docs/testing` must list files (e011d2f has no `(obsolete: ` line; PR #28 adds 19, and a squash merge or a rebase keeps them while it loses ac32593 from the ancestry). If no file is listed, stop and ask Tim to bring PR #28 in (merge it, then say whether to merge `main` into this branch or rebase onto it); do not do it unasked (D17). The script's own asserts are the second check: each anchor must match exactly one line of PR #28's text.

**Steps:**
- [ ] Mark the lines. Each entry names the line by its number at e011d2f (as tests-A does) and by text that occurs once in its checklist after PR #28; the script checks that every test a mark names exists, that each anchor matches one line, and that no item is marked twice. It puts each mark where PR #28 put its own: at the end of the item's last line, wrapped at 120 columns with two-space continuation lines, or on new continuation lines when that last line is longer than 120; a closing `______` blank stays last. The three recording-r4 items whose older in-part mark this phase replaces have it removed first. phase-3 line 31 first gets obsolete-E's corrected text (PR #28 left it for this phase), and phase-3 line 26's mark names its D half (`CaptureDeletionTests.confirmationTextSaysWhenTheObjectStays`) with the new test.
  ```bash
  python3 - <<'EOF'
  import re
  import sys
  from pathlib import Path
  
  ROOT = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(".")
  CHECK_NAMES = len(sys.argv) <= 2
  
  # (checklist, line at e011d2f, text unique to the item in PR #28's file, mark, replaces an older in-part mark)
  MARKS = [
      ('coordinator-harness', 52, '8. An adopted image or recording gets `.none` and ',
       '(suite: CoordinatorRecoveryTests.anOrphanPNGIsAdoptedWithItsSizeAThumbnailAndANotice, .anOrphanMP4IsAdoptedWithItsLength)', False),
      ('coordinator-split', 45, 'Delete during an upload [`+Delete`, `cancelUpload`',
       '(suite: CoordinatorDeleteTests.deleteDuringAnUploadCancelsItThenDeletesTheReservedKey)', False),
      ('phase-1', 19, 'Escape before any click cancels.',
       '(suite: SelectionViewTests.escapeCancelsAnAreaOrWindowSelection)', False),
      ('phase-1', 25, 'Pressing the shortcut while the overlay is up does',
       '(suite: CoordinatorCaptureTests.aCaptureWhileTheLockIsHeldReturnsAtOnceAndPostsNothing, ShortcutsTests.aCaptureIsRefusedWhileAnotherRunsOrAPromptIsOpen)', False),
      ('phase-1', 33, 'Escape cancels.',
       '(suite: SelectionViewTests.escapeCancelsAnAreaOrWindowSelection)', False),
      ('phase-1', 41, 'Quit and relaunch: save folder remembered, counter',
       '(suite: AppSettingsTests.aSecondInstanceKeepsTheSaveFolderAndContinuesTheCounter)', False),
      ('phase-2', 39, 'Progress ring moves during a large (fullscreen Ret',
       '(suite: CoordinatorUploadTests.anUploadShowsItsFractionOnTheCardThenUploaded, QuickAccessModelTests.uploadingShowsTheFraction, .uploadedSaysWhetherTheLinkWasCopied)', False),
      ('phase-2', 40, '"Copy URL" puts the URL on the clipboard again aft',
       '(suite: CoordinatorRecordActionsTests.copyLinkOrFileCopiesTheLinkEachTimeOrTheSavedFile)', False),
      ('phase-2', 44, 'Settings > Overlay off: no panel, uploads still wo',
       '(suite: CoordinatorSaveTests.aCaptureWithTheOverlayOffShowsNoCardAndStillUploads)', False),
      ('phase-2', 49, 'Turn Wi-Fi on, click Retry in the overlay: the upl',
       '(suite: CoordinatorUploadTests.aScreenshotsURLReplacesTheClipboardEvenAfterACopyElsewhere)', False),
      ('phase-2', 51, 'Clicking an uploaded Recent Captures row copies its URL',
       '(suite: CoordinatorRecordActionsTests.copyLinkOrFileCopiesTheLinkEachTimeOrTheSavedFile)', False),
      ('phase-2', 57, 'With captures older than a day in history, set ret',
       '(suite: CoordinatorDeleteTests.retentionDropsOldRowsAndTheirThumbnailsButKeepsSaveFolderFilesAndUnsentUploads, HistoryStoreTests.prunesRecordsOlderThanRetention)', False),
      ('phase-3', 23, 'Clicking an Uploaded cell copies the URL (paste in',
       '(suite, in part: CoordinatorRecordActionsTests.copyLinkOrFileCopiesTheLinkEachTimeOrTheSavedFile; by hand: the menu closing)', False),
      ('phase-3', 26, 'Delete… on a Phase 2 capture that was uploaded: th',
       '(suite: CaptureDeletionTests.confirmationTextSaysWhenTheObjectStays, CoordinatorDeleteTests.aPrePhase3UploadedCaptureIsDeletedWithNoStorageRequest)', False),
      ('phase-3', 31, "Change the Upload tab's bucket (to a second bucket you can write to)",
       '(suite: CoordinatorDeleteTests.aDeleteAfterABucketChangeDeletesWhereTheObjectWent, CaptureDeletionTests.objectsIncludeSupersededAtTheirLocations)', False),
      ('phase-3', 38, 'Trash button during an upload (fullscreen capture ',
       '(suite: CoordinatorDeleteTests.deleteDuringAnUploadCancelsItThenDeletesTheReservedKey, CaptureDeletionTests.confirmationTextIsOneLine)', False),
      ('phase-3', 39, 'Trash button during an upload, right after saving ',
       '(suite: CoordinatorDeleteTests.deleteDuringAnUploadCancelsItThenDeletesTheReservedKey)', False),
      ('phase-3', 40, 'Trash button after the upload finished: object, ro',
       '(suite: CoordinatorDeleteTests.deleteRemovesTheObjectTheFileTheThumbnailAndTheRow)', False),
      ('phase-3', 41, 'Cancel in the alert keeps everything and the overl',
       '(suite: CoordinatorDeleteTests.deleteDuringAnUploadCancelsItThenDeletesTheReservedKey, .deleteAsksOnceAndASecondDeleteWhileItAsksAsksNothing)', False),
      ('phase-3', 42, 'Clicking the thumbnail of an upload-only capture d',
       '(suite: QuickAccessModelTests.anUploadOnlyCardsThumbnailRevealsNothing)', False),
      ('phase-3', 46, 'Wi-Fi off, capture: overlay "Upload failed" with R',
       '(suite: CoordinatorUploadTests.aFailedUploadOnlyImageKeepsItsPendingFileAndSizeUntilARetrySendsIt)', False),
      ('phase-3', 59, "A retried failed upload lands under the capture's ",
       '(suite: CoordinatorUploadTests.aRetryIsNamedForTheCapturesDateWithANewlyDrawnCounter)', False),
      ('phase-3', 63, 'Forget Credentials while an upload is running: tha',
       '(suite: CoordinatorUploadTests.forgettingCredentialsMidUploadLetsThatUploadFinish)', False),
      ('phase-3', 66, 'Retention 1 day with older captures present, then ',
       '(suite: CoordinatorDeleteTests.retentionDropsOldRowsAndTheirThumbnailsButKeepsSaveFolderFilesAndUnsentUploads, HistoryStoreTests.pruningKeepsUploadOnlyCapturesThatWereNeverUploaded)', False),
      ('phase-3-1', 30, 'Clicking an uploaded row closes the menu and puts ',
       '(suite, in part: CoordinatorRecordActionsTests.copyLinkOrFileCopiesTheLinkEachTimeOrTheSavedFile; by hand: the menu closing)', False),
      ('phase-3-1', 33, 'The photo button on an upload-only capture (no loc',
       '(suite: CoordinatorRecordActionsTests.copyImageReadsTheFileOrDownloadsTheObject, .aCopyImageWhoseDownloadFailsSaysCouldNotCopyImage)', False),
      ('phase-3-1', 34, 'On a capture made before Phase 3 whose file was de',
       '(suite: CoordinatorRecordActionsTests.copyImageOfAMissingFileWithNoUsableUploadSaysTheFileCouldNotBeRead, RecentCaptureFormattingTests.buttonsFollowWhatTheCaptureHas)', False),
      ('phase-3-1', 35, 'Rename the file of a capture that was saved but ne',
       '(suite: CoordinatorRecordActionsTests.copyImageOfAMissingFileWithNoUsableUploadSaysTheFileCouldNotBeRead)', False),
      ('phase-3-1', 37, 'With an empty history the submenu shows a greyed "',
       '(suite: RecentCapturesMenuTests.anEmptyHistoryShowsOneDisabledNoCapturesYet)', False),
      ('phase-3-1', 50, 'Wi-Fi off, capture in upload-only mode: the row sh',
       '(suite: CoordinatorDeleteTests.aFailedUploadOnlyCaptureIsDeletedWithOneQuestionAndNoDelete, CaptureDeletionTests.confirmationTextIsOneLine)', False),
      ('phase-3-1', 51, 'Upload-only mode, Network Link Conditioner on a lo',
       '(suite: CoordinatorDeleteTests.aRemoteDeleteFailureDuringAnUploadKeepsTheRecordUntilRemoveFromHistory)', False),
      ('phase-3-1', 52, 'Forget Credentials, then Delete on an uploaded cap',
       '(suite: CoordinatorDeleteTests.aDeleteThatCannotReachStorageAsksToRemoveFromHistory)', False),
      ('phase-3-1', 60, 'The token captions in Settings > General and Setti',
       '(suite: TemplateExpanderTests.theTokenListNamesEveryToken)', False),
      ('phase-3-1', 63, 'Save and Test Connection with correct settings rep',
       '(suite: ConnectionTesterTests.readableSummaryDoesNotEchoTheProbeURL, .uploadFailedWhenPutIsRejected)', False),
      ('phase-4a', 46, 'Saved capture, never uploaded: the editor opens fr',
       '(suite: CoordinatorEditorTests.loadImageReadsTheLocalFileOrDownloadsTheObject, EditorInputTests.saveFolderFileForSavedCapture)', False),
      ('phase-4a', 47, 'Capture uploaded with "Upload and copy URL": opens',
       '(suite: CoordinatorEditorTests.loadImageReadsTheLocalFileOrDownloadsTheObject, EditorInputTests.saveFolderFileForSavedCapture)', False),
      ('phase-4a', 48, 'Upload-only capture whose upload failed: opens fro',
       '(suite: CoordinatorEditorTests.loadImageReadsTheLocalFileOrDownloadsTheObject, EditorInputTests.pendingFileForUploadOnlyPending)', False),
      ('phase-4a', 50, 'Capture from before Phase 3: opens from its file. ',
       '(suite: CoordinatorEditorTests.annotateOnAMovedPrePhase3FileSaysCouldNotOpenAndOpensNoEditor, EditorInputTests.legacyRecordWithFileReadsTheFile)', False),
      ('phase-4a', 51, 'Capture uploaded with "Upload and copy URL" whose ',
       '(suite: CoordinatorEditorTests.loadImageReadsTheLocalFileOrDownloadsTheObject)', False),
      ('phase-4a', 53, 'Stale retained image: with the overlay on, take ca',
       '(suite: CoordinatorDeleteTests.removingARecordClearsItsBookkeeping, EditorInputTests.retainedWinsForLatestCapture)', False),
      ('phase-4a', 60, 'Pixelate: a drag makes a mosaic of equal squares, ',
       '(suite: EditorModelTests.blockSizeAppliesToTheSelectedPixelateInOneStep, RedactionRendererTests.mosaicBlocksUniform, .mosaicGridStableWhenRegionMoves, EffectGeometryTests.mosaicRectAnchoredToImageGrid, EditorPaletteTests.standardDefaultsAreRedBlackFourEightTen)', False),
      ('phase-4a', 62, 'Rectangle: red and 4 pt by default, the stroke ins',
       '(suite: EditorModelTests.widthAndColourApplyToTheSelectedShapeAndItsTool, EditorPaletteTests.standardDefaultsAreRedBlackFourEightTen, EditorFlattenerTests.rectangleStrokeHitsExpectedPixelsAndCentreUntouched, KeyRoutingTests.digitsOneToSixPickWidths)', False),
      ('phase-4a', 105, 'Settings > General, set the file name template to ',
       '(suite: CoordinatorRecordActionsTests.saveAsSuggestionUsesTheCurrentCounterWithoutDrawingOne, EditorNamingTests.counterUsesTheCurrentValue)', False),
      ('phase-4a', 108, 'In the panel, pick an existing PNG and confirm Rep',
       "(suite, in part: CoordinatorRecordActionsTests.saveAsReplacesAnExistingFileAndSaysNotSavedForALockedOne; by hand: the panel's Replace prompt and the unsaved dot staying)", False),
      ('phase-4a', 126, 'Another uploaded capture whose link was never open',
       '(suite: CoordinatorUploadTests.uploadAsNewCopiesTheNewLinkAndDeletesTheOldObject, EditorUploadPlanTests.asNewSupersedesOldKey)', False),
      ('phase-4a', 128, 'Interrupted replace keeps Upload as New: after the',
       '(suite: CoordinatorUploadTests.uploadAsNewCopiesTheNewLinkAndDeletesTheOldObject, HistoryStoreTests.interruptedReplaceKeepsPriorUpload, EditorSaveTargetTests.uploadAsNewKeepsInterruptedReplace)', False),
      ('phase-4a', 134, 'Quit during a replace: Network Link Conditioner on',
       '(suite: CoordinatorUploadTests.anInterruptedReplaceRetriesOverItsOwnKeyAfterARelaunch, HistoryStoreTests.uploadingRecordsBecomeFailedOnLoadAndPersist, EditorUploadPlanTests.retryOfInterruptedReplaceReusesKey)', False),
      ('phase-4a', 135, 'Slow profile again, ⌘U, then Delete on the row whi',
       '(suite: CoordinatorDeleteTests.deleteDuringAReplaceCancelsItAndDeletesTheLinksKey, CaptureDeletionTests.objectsIncludePriorUploadAtItsLocation)', False),
      ('phase-4a', 142, 'The first successful replace after launch posts `R',
       '(suite: CoordinatorUploadTests.onlyTheFirstReplaceOfALaunchPostsTheCacheNote, EditorUploadPlanTests.cacheNoteOnlyOnFirstSameKeyReplace)', False),
      ('phase-4b', 30, 'With the canvas focused, each letter (either case)',
       '(suite, in part: CanvasViewEventTests.aLetterPressedDuringADragKeepsTheTool, KeyRoutingTests.lettersSelectTools, .editingTextSuppressesLetters, EditorToolTests.toolForKeyIsCaseInsensitive; by hand: the toolbar following the tool)', False),
      ('phase-4b', 37, 'Keys `1` to `6` set 2, 3, 4, 6, 8 and 12 pt on the',
       '(suite: EditorModelTests.widthAndColourApplyToTheSelectedShapeAndItsTool, KeyRoutingTests.digitsOneToSixPickWidths)', False),
      ('phase-4b', 55, 'The colour button recolours the selected text and ',
       '(suite: EditorModelTests.colourAppliesToTheSelectedTextAndTheTextBeingTyped, .textEditCommitsOnceWithoutEditorUndo)', False),
      ('phase-4b', 56, 'Click committed text with Text, or double-click it',
       '(suite: CanvasViewEventTests.reEditingATextPutsTheCaretAtTheEndInTheTextsFrame, CanvasToolTests.textToolClickPlacesOrReEditsText, EditorModelTests.reEditReplacesInPlaceAndBlankDeletes)', False),
      ('phase-4b', 61, 'Select a committed text: a drag moves it, Delete r',
       '(suite: CanvasToolTests.aSelectedTextMovesAndDeletesAndHasNoHandles, KeyRoutingTests.nudgeOneOrTenPixels, SelectionOutlineTests.earlierKindsAreUnchanged)', False),
      ('phase-4b', 79, 'Crop of the window capture with transparent corner',
       '(suite: EditorFlattenerTests.aCropKeepingATransparentCornerKeepsItClear)', False),
      ('phase-4b', 80, 'A crop dragged back to the whole image and applied',
       '(suite: CanvasToolTests.aCropDraftStopsAtTheTinyDragSize, EditorModelTests.escapeCancelsCropAndAnotherToolApplies, CropGeometryTests.emptyCropIsNil)', False),
      ('phase-4b', 82, "With a crop applied, input stops at the crop's edg",
       '(suite: CanvasViewEventTests.drawingUnderAnAppliedCropStopsAtItsEdge, CropGeometryTests.pressOutsideAnAppliedCrop)', False),
      ('phase-4b', 84, 'With a crop applied, ⌘A selects the front-most ann',
       '(suite: EditorModelTests.selectAllWithEveryAnnotationOutsideTheCropSelectsNothing, .selectAllSkipsAnnotationsOutsideTheCrop, .selectAllAndCancelOnlyChangeSelection)', False),
      ('phase-4b', 88, '⌘D works on every kind: ellipse, line, pencil stro',
       '(suite: EditorModelTests.duplicateCopiesEveryKindOffsetAndNamed, .duplicateIsOneUndoStep)', False),
      ('phase-4b', 91, 'Between two editors: open the two captures from Se',
       '(suite: CanvasViewEventTests.anObjectCopiedInOneCanvasPastesIntoAnotherAtItsPointSize, AnnotationClipTests.offImageObjectIsCentredThenCascades, EditorModelTests.pasteIntoAnotherEditorKeepsPointSize)', False),
      ('phase-4b', 99, 'Press and release Space in the middle of a Rectang',
       "(suite, in part: CanvasViewEventTests.spacePansOnlyBetweenDragsAndNeverMovesACropDraft; by hand: the ⌘-Tab itself, which reaches `endSpacePan` through the window's resign-key)", False),
      ('phase-4b', 100, 'While editing text, Space types a space. With a cr',
       '(suite: CanvasViewEventTests.spacePansOnlyBetweenDragsAndNeverMovesACropDraft, KeyRoutingTests.spaceIsThePanKey)', False),
      ('phase-4b', 101, 'Space-drag at Fit moves the picture off centre and',
       '(suite: CanvasFitTests.aSpaceDragStopsTheFitOnResizeAndFitToViewBringsItBack)', False),
      ('phase-4b', 118, 'Draw one of each tool (Redact, Pixelate, Blur, Rec',
       '(suite: EditorModelTests.oneOfEachToolUndoesNewestFirstAndRedoesInOrder)', False),
      ('phase-4b', 128, 'Move, resize or delete an annotation with the mous',
       '(suite: CanvasAccessibilityTests.canvasElementsFollowMovesResizesDeletesAndAdds, .itemsFollowPaintingOrderAndNumberEachKind)', False),
      ('phase-4b', 129, 'The selected annotation is reported as selected. S',
       '(suite: CanvasAccessibilityTests.anAccessibilityPressSelectsAndTheCanvasActsOnTheSelection)', False),
      ('phase-4b', 130, 'With a crop applied, VoiceOver lists only the anno',
       '(suite, in part: CanvasAccessibilityTests.anAccessibilityPressIsRefusedWithTheCropToolOrDuringADrag, .cropHidesAnnotationsOutsideIt; by hand: the list while the Crop tool is open over an applied crop)', False),
      ('phase-4b', 131, 'VO-Space on an element selects that annotation; De',
       '(suite: CanvasAccessibilityTests.anAccessibilityPressSelectsAndTheCanvasActsOnTheSelection)', False),
      ('phase-4c', 140, '`Line width` is always enabled. With a spotlight o',
       '(suite: EditorModelTests.lineWidthWithASpotlightOrCounterSelectedChangesOnlyTheDefault)', False),
      ('phase-4c', 151, "With a counter selected, the Colour button's swatc",
       '(suite: EditorModelTests.aSelectedCounterShowsAndTakesTheColour, CounterTests.numberColourContrastsWithEverySwatch)', False),
      ('phase-4c', 159, 'Undo the paste, the ⌥-drag copy and the ⌘D copy in',
       '(suite: CounterTests.undoingCopiesReturnsTheNumbersAndRedoRestoresThem)', False),
      ('phase-4c', 162, '⌘C a counter in one editor and ⌘V it twice in anot',
       '(suite: CounterTests.aCounterPastedTwiceAcrossScalesTakesTheNextNumbersAtItsPointSize)', False),
      ('phase-4c', 163, 'The same for a spotlight: ⌘D, ⌥-drag and ⌘C, ⌘V gi',
       '(suite: EditorModelTests.everySpotlightEditIsOneNamedUndoStep, SpotlightRenderingTests.overlappingSpotlightsLeaveTheirUnionUndimmed)', False),
      ('phase-4c', 167, '`Add Spotlight`, `Move Spotlight`, `Resize Spotlig',
       '(suite: EditorModelTests.everySpotlightEditIsOneNamedUndoStep, CanvasToolTests.spotlightDragCommitsAddSpotlight)', False),
      ('phase-4c', 203, 'Dim does not carry into a new capture. Set 70 % on',
       '(suite: EditorModelTests.spotlightDimStaysWithItsModel)', False),
      ('phase-4c', 209, 'AXPress on an element selects it (not while a drag',
       "(suite, in part: CanvasAccessibilityTests.anAccessibilityPressSelectsAndTheCanvasActsOnTheSelection, .anAccessibilityPressIsRefusedWithTheCropToolOrDuringADrag, .cropHidesAnnotationsOutsideIt; by hand: VoiceOver itself, and the canvas's own list with a crop)", False),
      ('phase-5', 106, 'Done while the line shows saves what was stitched ',
       '(suite: ScrollCaptureSessionTests.doneWhileLostSavesWhatWasStitchedBeforeTheLoss)', False),
      ('phase-5', 181, "The overlay's Delete on a stitched capture, after ",
       '(suite: CoordinatorDeleteTests.deleteRemovesTheObjectTheFileTheThumbnailAndTheRow)', False),
      ('phase-5', 199, 'Thumbnail made from the file: quit TidyShot, delet',
       '(suite: ThumbnailProviderTests.aNamedThumbnailThatIsGoneIsMadeAgainFromTheFile, ThumbnailMakerTests.thumbnailOfATallPNGShowsItsTop)', False),
      ('phase-6a', 151, 'Copy Image, from the context menu, with each kind ',
       '(suite: CoordinatorRecordActionsTests.copyImageReadsTheFileOrDownloadsTheObject)', False),
      ('phase-6a', 165, 'Quit and reopen: the list is empty and the menu it',
       '(suite: CoordinatorOverlayTests.aRelaunchForgetsClosedCardsButKeepsTheirRecords)', False),
      ('phase-6a', 183, "Names: an uploaded capture's file is named like th",
       '(suite: CoordinatorDragOutTests.aRestoredUploadOnlyCardsQuietDownloadIsNamedForItsKey, DragFileNameTests.uploadedKeyNamesTheFile, .nestedKeyGivesItsLastComponent, .withoutAKeyTheSaveAsSuggestionNamesTheFile)', False),
      ('phase-6a', 215, 'The menu item is disabled while a capture or a scr',
       '(suite, in part: CoordinatorCaptureTests.aCaptureWhileTheLockIsHeldReturnsAtOnceAndPostsNothing, ShortcutsTests.aCaptureIsRefusedWhileAnotherRunsOrAPromptIsOpen; by hand: the menu item shown disabled)', False),
      ('phase-6b', 52, 'Click a window without dragging: the rect is the w',
       '(suite: SelectionViewTests.aClickWithoutADragTakesTheHighlightedWindowAndADragDoesNot, SelectionOutcomeTests.allInOneModeDragsAnAreaOrClicksAWindow)', False),
      ('phase-6b', 53, 'Drag each of the eight handles: the rect resizes o',
       '(suite: SelectionViewTests.aPressOutsideTheRectStartsANewOne, SelectionAdjustTests.eachHandleMovesOnlyItsEdges, .resizingStopsAtTheMinimumSide, .resizingIsClampedToTheBounds, .halfPointDragsKeepTheOppositeEdges, .insideMovesTheRectAndClampsAtEachEdge)', False),
      ('phase-6b', 55, 'Arrow keys move the rect 1 pt, Shift-arrows 10 pt,',
       '(suite: SelectionViewTests.commandKeysNeitherCaptureNorNudgeAndShiftArrowMovesTen, SelectionAdjustTests.arrowsNudgeByOneOrTenAndStopAtTheEdge, .nudgesStopAtTheBounds, SelectionViewArmingTests.aDisarmedRectStillNudgesAndCancels)', False),
      ('phase-6b', 56, 'Type 640 into `W` and press Return: the width beco',
       '(suite: SelectionViewTests.aTypedWidthResizesFromTheTopLeftWithoutCapturing, SelectionAdjustTests.typedSizeGrowsFromTheTopLeft, .typedSizeIsClampedAndMovedInside)', False),
      ('phase-6b', 72, 'The countdown panel and frame are click-through: c',
       '(suite: SelfTimerTests.theCountdownPanelAndTheScrollFrameLetClicksThrough)', False),
      ('phase-6b', 153, "`t 'capture-area?display=7'` with no rect opens th",
       '(suite: URLCommandHandlerTests.aDisplayWithoutARectOpensTheNormalSelection, URLCommandTests.theDisplayIsAWholeNumberFromOne)', False),
      ('phase-6b', 161, 'Several URLs waiting for a cold launch: quit TidyS',
       '(suite: URLCommandHandlerTests.aGateRefusedCaptureDoesNotCountAsTheFirstQueuedOne, .onlyTheFirstQueuedCaptureCommandRuns)', False),
      ('phase-7c', 94, 'A swatch click, the Shadow toggle and an Aspect Ra',
       '(suite: EditorBackgroundExportTests.aSwatchTheShadowAndAnAspectAreThreeStepsThatDirtyTheEditor)', False),
      ('phase-7c', 98, 'The editor is dirty after any of these (the title ',
       "(suite, in part: EditorBackgroundExportTests.aSwatchTheShadowAndAnAspectAreThreeStepsThatDirtyTheEditor; by hand: the title's edited mark)", False),
      ('phase-7c', 143, 'The preview matches the export for every ratio: th',
       '(suite: EditorBackgroundExportTests.theShownCanvasHasTheExportsSizeForEveryAspect, .baseImageViewPlacesTheBackgroundLayers)', False),
      ('phase-7c', 144, 'Aspect Ratio changes while Zoom to fit is on: the ',
       '(suite: CanvasFitTests.theFitFramesTheBackgroundsCanvasAndRefitsOnAnAspectChange)', False),
      ('phase-7c', 147, 'Scrolling capture of `tall.html` (⌃⇧5, Start, scro',
       '(suite: EditorBackgroundExportTests.aBackgroundFitsTallContentAndACropUnderTheLimit)', False),
      ('phase-7c', 150, 'Crop a 18,000 px capture to 10,000 px tall, then o',
       '(suite: EditorBackgroundExportTests.aBackgroundFitsTallContentAndACropUnderTheLimit)', False),
      ('phase-7c', 156, 'Draw annotations with a background on: a redact, a',
       '(suite: CanvasFitTests.aPointerOnTheCaptureMapsToItsPixelWithABackground)', False),
      ('phase-7c', 157, 'Zoom to fit (⌘0) fits the whole canvas, and the ca',
       '(suite: CanvasFitTests.theFitFramesTheBackgroundsCanvasAndRefitsOnAnAspectChange, .aSpaceDragStopsTheFitOnResizeAndFitToViewBringsItBack)', False),
      ('phase-7c', 158, "Pick the Crop tool: the preview's background hides",
       '(suite: EditorBackgroundExportTests.theCropToolHidesTheBackgroundAndCancelOrUndoReturnsItAroundTheWholeCapture, .shownBackgroundFramesTheCropInImagePixels)', False),
      ('phase-7c', 164, "Background first, then crop: the crop's handles wo",
       '(suite: EditorBackgroundExportTests.theCropToolHidesTheBackgroundAndCancelOrUndoReturnsItAroundTheWholeCapture, .shownBackgroundFramesTheCropInImagePixels)', False),
      ('phase-7c', 165, 'Aspect Ratio 16:9 with a crop: the ratio applies t',
       '(suite: EditorBackgroundExportTests.theShownCanvasHasTheExportsSizeForEveryAspect)', False),
      ('phase-7c', 199, "An old capture's editor, opened with no background",
       '(suite: CanvasFitTests.theFitFramesTheBackgroundsCanvasAndRefitsOnAnAspectChange, EditorBackgroundExportTests.noBackgroundExportsTheCaptureAsBefore, .baseImageViewPlacesTheBackgroundLayers)', False),
      ('recording-r1', 86, 'Settings persist. After the reset, `defaults read ',
       '(suite: AppSettingsTests.recordingDefaultsAreRegisteredNotWritten, .recordingSettingsPersistUnderTheirKeys, .aStoredFrameRateOtherThan30Or60ReadsAs30)', False),
      ('recording-r1', 94, 'Repeat the last step with `Upload only, keep no lo',
       '(suite: CoordinatorSaveTests.anUploadOnlyRecordingThatCannotUploadWaitsInPendingUntilARetry)', False),
      ('recording-r1', 277, 'With `Upload and copy URL` and `Also copy image` o',
       '(suite: CoordinatorSaveTests.aRecordingsURLReplacesItsFileReferenceOnlyWhileTheClipboardHoldsIt)', False),
      ('recording-r1', 279, "Screenshots keep today's behaviour: their URL alwa",
       '(suite: CoordinatorUploadTests.aScreenshotsURLReplacesTheClipboardEvenAfterACopyElsewhere)', False),
      ('recording-r1', 282, 'Copy File on a pending video (`Upload only` while ',
       '(suite: CoordinatorDragOutTests.aCopyFileStageOfAPendingVideoOutlivesItsUpload)', False),
      ('recording-r1', 283, 'Let the card close (or close it), wait more than a',
       '(suite: CoordinatorDragOutTests.theCleanUpWaitsWhileTheClipboardHoldsTheCopyFileReference, DragCleanupTests.theClipboardStillHoldingCopyFilesReferenceWaitsAgain, .aClipboardThatMovedOnRemovesTheFolder)', False),
      ('recording-r1', 284, 'With no card showing for it, Copy File from the Re',
       '(suite: CoordinatorDragOutTests.aCopyFileWithNoCardSchedulesItsOwnCleanUp)', False),
      ('recording-r1', 285, "Close a `Kept in TidyShot` video's card (restore i",
       '(suite: CoordinatorDragOutTests.aCopyFileWithinTheMinuteReplacesTheCloseCleanUp)', False),
      ('recording-r1', 287, 'Copy File on a recording in the save folder puts t',
       '(suite: CoordinatorRecordActionsTests.copyFilePutsASavedRecordingItselfAndNeedsALocalFile)', False),
      ('recording-r1', 289, 'With `{counter}` in the Recording file name templa',
       '(suite: CoordinatorDragOutTests.aDragPressAfterCopyFileReusesTheStagedCopy, DragFileStoreTests.aVideoStageReusesAMatchingCopyUnderAnotherName)', False),
      ('recording-r1', 309, 'Delete removes the save-folder file, the pending f',
       '(suite: CoordinatorDeleteTests.deleteRemovesTheObjectTheFileTheThumbnailAndTheRow)', False),
      ('recording-r1', 310, 'Retention (optional): quit TidyShot, back up `hist',
       '(suite: CoordinatorDeleteTests.retentionDropsOldRowsAndTheirThumbnailsButKeepsSaveFolderFilesAndUnsentUploads, HistoryStoreTests.pruningKeepsUploadOnlyCapturesThatWereNeverUploaded)', False),
      ('recording-r1', 318, '`Upload and copy URL`: the recording is saved exac',
       '(suite: CoordinatorSaveTests.uploadWithNoDestinationSavesTheRecordingAndCopiesItsFile, RecordingSavePlanTests.uploadWithNoDestinationIsSavedAndCopiedAsAFile)', False),
      ('recording-r1', 319, '`Upload only, keep no local file`: the file goes t',
       '(suite: CoordinatorSaveTests.anUploadOnlyRecordingThatCannotUploadWaitsInPendingUntilARetry, RecordingSavePlanTests.uploadOnlyWithNoDestinationWaitsInPendingWithNothingCopied)', False),
      ('recording-r1', 332, '5. Quit mode skips only the folder prompt, Clop, t',
       '(suite: CoordinatorSaveTests.quitModeSkipsTheCardTheUploadAndTheNoticesForEveryAction, RecordingSavePlanTests.quitModeForEachAction)', False),
      ('recording-r1', 334, "7. Copy File's drag copy outlives the upload and t",
       '(suite: CoordinatorDragOutTests.aCopyFileStageOfAPendingVideoOutlivesItsUpload, .theCleanUpWaitsWhileTheClipboardHoldsTheCopyFileReference, .aCopyFileWithNoCardSchedulesItsOwnCleanUp, DragCleanupTests.theClipboardStillHoldingCopyFilesReferenceWaitsAgain)', False),
      ('recording-r2', 157, 'Persistence. After the reset, `defaults read io.tk',
       '(suite: AppSettingsTests.recordingDefaultsAreRegisteredNotWritten, .r2RecordingSettingsPersistUnderTheirKeys, .r2StoredValuesOutsideTheChoicesReadAsTheDefaults)', False),
      ('recording-r2', 271, "A GIF's upload and the clipboard. `Upload and copy",
       '(suite: CoordinatorSaveTests.aRecordingsURLReplacesItsFileReferenceOnlyWhileTheClipboardHoldsIt, UploadPayloadTests.gifIsAFile, CaptureRecordTests.gifKindTypes)', False),
      ('recording-r2', 312, '**(Debug)** `--args -MuteFailure both`, for each o',
       "(suite, in part: CoordinatorSaveTests.aMarkedRecordingStaysInPendingForEveryActionAndNeverLeaves, RecordingSavePlanTests.aMarkedRecordingTargetsPendingForEveryAction, QuickAccessModelTests.aMarkedRecordSaysSoundNotMutedAndOffersOpenTrimAndDeleteOnly, UploadRefusalTests.retryFailedUploadsLeavesOutMarkedAndDeletingRecords; by hand: the `-MuteFailure` run itself, the card's tool tip and the mark after a relaunch)", False),
      ('recording-r2', 364, 'With access undecided (`tccutil reset Microphone i',
       '(suite, in part: CoordinatorRecordingTests.aRecordPressDuringACaptureWithAccessUndecidedShowsNoPrompt, ShortcutsTests.aPromptShowsOnlyWithNoCaptureRunning; by hand: the Record press once the capture is done, which prompts)', False),
      ('recording-r2', 456, "The sheet's text, buttons and default button for e",
       '(suite, in part: CoordinatorTrimTests.uploadTrimmedClearsTheStaleNoteOnSuccessAndKeepsItOnFailure, RecordingTrimTests.saveTargetWithADestination, .saveTargetWithNoDestination, .cancelIsAlwaysLastAndTheButtonsHaveTheirTitles, .thePutMarksTheLinkStaleOnlyWhenItSetsTheFlag; by hand: the sheet as it shows)', False),
      ('recording-r2', 475, 'During a slow Save to the other volume (a long rec',
       '(suite: CoordinatorTrimTests.aCaptureBeingTrimmedRefusesDeleteAndUploadTrimmed, CoordinatorUploadTests.aRetryOfATrimmingOrUploadingRecordDoesNothingButSay, QuickAccessModelTests.retryUploadTrimmedAndDeleteAreDisabledWhileTrimming)', False),
      ('recording-r2', 608, '2. Notices after Stop come in a fixed order (`Reco',
       '(suite: CoordinatorSaveTests.noticesAfterStopComeInOrderWhateverShowNotificationSays, RecordingNoticeOrderTests.theSavesNoticeThenRecordingStoppedThenTheMicrophoneNote, .quitModeGivesNothing)', False),
      ('recording-r2', 632, "11. Sizes (spec 2.13): a GIF's size is the GIF's a",
       "(suite, in part: CoordinatorSaveTests.aGIFsSizeIsTheMovedFilesSize, VideoValidationTests.aRewrittenFileReadsItsNewSize, CaptureRecordTests.aTrimsWriteRecordsTheTrimmedFile; by hand: the MP4's size after a failed conversion, and the rows against `ls -l`)", False),
      ('recording-r2', 640, 'A. `GIFMakerError.couldNotRead` (`The recording co',
       '(suite: GIFFileSinkTests.couldNotReadSaysTheRecordingCouldNotBeRead)', False),
      ('recording-r2', 645, "C. The cache note's title when a replaced upload's",
       '(suite: CoordinatorTrimTests.aFirstReplaceWhoseURLWasNotCopiedPostsTheCacheNoteAsUploaded)', False),
      ('recording-r2', 676, 'Delete (and confirm) a GIF: the file, the record a',
       '(suite: CoordinatorDeleteTests.deleteRemovesTheObjectTheFileTheThumbnailAndTheRow)', False),
      ('recording-r3', 110, 'Persistence. After the reset, `defaults read io.tk',
       '(suite: AppSettingsTests.recordingDefaultsAreRegisteredNotWritten, .r3RecordingSettingsPersistUnderTheirKeys, .aStoredBubbleSizeOutsideTheThreeReadsAsMedium, .aNegativeOrUnreadableBubbleInsetReadsAs16, BubblePlacementTests.theStandardInsets)', False),
      ('recording-r3', 155, 'A GIF start still asks for the camera and not the ',
       '(suite: CoordinatorRecordingTests.aGIFStartAsksForTheCameraAndNotTheMicrophone)', False),
      ('recording-r3', 367, 'A note and a microphone note together: the order i',
       '(suite: CoordinatorSaveTests.noticesAfterStopComeInOrderWhateverShowNotificationSays, RecordingNoticeOrderTests.theCameraNoteThenTheHighlightsNoteComeLast)', False),
      ('recording-r3', 440, "F. The ring's grow eases out and its fade is linea",
       '(suite: ClickRingOverlayTests.theRingGrowsEasingOutAndFadesLinearly)', False),
      ('recording-r4', 208, 'Return and Enter do nothing. A click inside record',
       '(suite: SelectionViewTests.aRecordingSelectionIgnoresReturnAndRecordsAClickInsideTheRect, SelectionOutcomeTests.recordingModeClickInThePresetRecordsIt, .recordingModeDragReplacesThePreset)', False),
      ('recording-r4', 236, 'Delete mid-upload aborts it (the AWS console, or `',
       '(suite: CoordinatorDeleteTests.deleteDuringAMultipartUploadAbortsItAndDeletesTheKey, .eachUploadIsAbortedWhereItWasCreated, UploadQueueTests.aCancelDuringThePartsWaitsForEveryPart)', True),
      ('recording-r4', 251, '`Upload Trimmed` on a 300 MB trimmed file replaces',
       '(suite: CoordinatorTrimTests.uploadTrimmedReplacesInPartsKeepsTheLinkOnFailureAndResumes, CoordinatorUploadTests.aFailedUploadMarksTheRecordOrReturnsItToItsLink, MultipartPlanTests.resumesWhenEverythingMatches)', True),
      ('recording-r4', 290, 'A downloaded drag copy is not a local file: Copy F',
       '(suite: CoordinatorRecordActionsTests.copyFilePutsASavedRecordingItselfAndNeedsALocalFile, RecentCaptureFormattingTests.copyFileNeedsAVideoWithALocalFile, RecordingTrimTests.sourceFollowsEditorInputsOrder)', False),
      ('recording-r4', 291, 'After the card closes, the 60 s clean-up removes t',
       '(suite: CoordinatorDragOutTests.theCleanUpRemovesADownloadedCopyAndALaterDragDownloadsAgain, DragCleanupTests.aCardShowingTheRecordLeavesTheFolder, .noCopyFileRemovesTheFolder)', True),
      ('recording-r4', 311, '4. A rect is preselected and only a click inside i',
       '(suite: SelectionViewTests.aRecordingSelectionIgnoresReturnAndRecordsAClickInsideTheRect, SelectionOutcomeTests.recordingModeClickInThePresetRecordsIt, URLCommandGateTests.theRecordingCommandsNeedOnlyURLCommandsOn)', False),
      ('recording-r4', 313, "6. Recording notices do not name the URL's sender.",
       '(suite: CoordinatorSaveTests.recordingNoticesNeverNameTheSender)', False),
      ('recording-r4', 330, '22. The drag-out download starts at the drag thres',
       "(suite, in part: QuickAccessCardDragViewTests.theDragViewAsksForTheDownloadOncePerPressPastTheThreshold; by hand: the card's menu has no download item)", False),
      ('recording-r4', 352, '9. A resumed template job that must draw a new key',
       '(suite: CoordinatorUploadTests.aResumedTemplateJobWhoseKeyIsTakenRedrawsItWithCounterZero, UploadQueueTests.aTemplateResumeWhoseKeyWasTakenDrawsANewKeyAndRestarts)', False),
      ('recording-r4', 355, "11. The card's drag view asks for the download onc",
       '(suite: QuickAccessCardDragViewTests.theDragViewAsksForTheDownloadOncePerPressPastTheThreshold, CoordinatorDragOutTests.aSecondDragWhileOneRunsStartsNoSecondDownload)', False),
      ('recording-r4', 361, '16. Resume data travels in the error with `signedA',
       '(suite: CoordinatorDragOutTests.aFailureWithResumeDataKeepsItWithTheSigningTime, DragDownloadTests.resumeDataContinuesWithARangeRequest)', False),
      ('recording-r4', 377, "G. Delete's second Abort failing fails Delete (the",
       '(suite: CoordinatorDeleteTests.aSecondAbortThatFailsAsksToRemoveFromHistory)', False),
      ('recording-r4', 378, 'H. Part reads retry from the same bytes held in me',
       '(suite: UploadQueueTests.aPartRetrySendsTheBytesItFirstRead)', False),
      ('small-tweaks', 9, 'With it off, make a remote delete fail: set a wron',
       '(suite: CoordinatorDeleteTests.aDeleteThatCannotReachStorageAsksToRemoveFromHistory, .anAbortFailureAsksToRemoveFromHistory)', False),
      ('small-tweaks', 19, 'Make an upload fail (no network): the row keeps it',
       '(suite: CoordinatorUploadTests.aFailedUploadOnlyImageKeepsItsPendingFileAndSizeUntilARetrySendsIt, RecentCaptureFormattingTests.detailIsTheTimeTheSizeAndEachUploadState)', False),
  ]
  
  # obsolete-E's corrected text for phase-3 line 31 (PR #28 left it for this phase).
  PHASE_3_31_OLD = ("Change the Upload tab's bucket (to a second bucket you can write to) and Save, then Delete… a capture "
                    "uploaded before the change: the object is removed from the bucket it was uploaded to (`curl -I <old url>` "
                    "gives 403 or 404), not looked for in the new one.")
  PHASE_3_31_NEW = ("Change the Upload tab's bucket and Save, then Delete a capture uploaded before the change (trash button "
                    "on its row or card): the object is removed from the bucket it was uploaded to (`curl -I <old url>` gives "
                    "403 or 404), not looked for in the new one.")
  OLD_MARK = re.compile(r" \(suite, in part: [^)]*\)$")
  WIDTH = 120
  
  
  def tests_named(mark):
      """Every Suite.test the mark names, the `.test` shorthand expanded."""
      body = re.sub(r"^\(suite(, in part)?: ", "", mark).split("; by hand")[0].rstrip(")")
      suite, names = None, []
      for part in (p.strip() for p in body.split(",")):
          if part.startswith("."):
              names.append((suite, part[1:]))
          else:
              suite, name = part.split(".", 1)
              names.append((suite, name))
      return names
  
  
  def wrap(first, words):
      """`first` with `words` appended, wrapped at WIDTH with two-space continuation lines."""
      lines, current = [], first
      for word in words:
          if current.strip() and len(current) + 1 + len(word) > WIDTH:
              lines.append(current)
              current = "  " + word
          else:
              current = current + " " + word if current.strip() else "  " + word
      lines.append(current)
      return lines
  
  
  def place(item, mark):
      """The item's lines with `mark` at the end of its last line, as PR #28 placed them: appended when that line is
      at most WIDTH long, otherwise on new continuation lines; a closing `______` blank stays last."""
      words = mark.split(" ")
      item = list(item)
      if item[-1].endswith(" ______"):
          item[-1] = item[-1][: -len(" ______")]
          words.append("______")
      last = item[-1]
      if len(last) <= WIDTH:
          return item[:-1] + wrap(last, words)
      return item + wrap("", words)
  
  
  if CHECK_NAMES:
      missing = []
      for _, _, _, mark, _ in MARKS:
          for suite, name in tests_named(mark):
              source = ROOT / "TidyShotTests" / f"{suite}.swift"
              if not source.exists() or f"func {name}(" not in source.read_text():
                  missing.append(f"{suite}.{name}")
      assert not missing, f"tests not found: {sorted(set(missing))}"
  
  by_file = {}
  for checklist, line, anchor, mark, replaces in MARKS:
      by_file.setdefault(checklist, []).append((line, anchor, mark, replaces))
  
  marked = 0
  for checklist, entries in by_file.items():
      path = ROOT / "docs" / "testing" / f"{checklist}-manual-checklist.md"
      text = path.read_text()
      if checklist == "phase-3":
          assert text.count(PHASE_3_31_OLD) == 1, "phase-3 line 31's text"
          text = text.replace(PHASE_3_31_OLD, PHASE_3_31_NEW)
      lines = text.split("\n")
      spans = []
      for line, anchor, mark, replaces in entries:
          anchor = PHASE_3_31_NEW[:60] if (checklist, line) == ("phase-3", 31) else anchor
          hits = [i for i, l in enumerate(lines) if anchor in l]
          assert len(hits) == 1, f"{checklist}:{line} matches {len(hits)} lines"
          start = hits[0]
          end = start + 1
          while end < len(lines) and lines[end].startswith("  ") and not lines[end].lstrip().startswith("- ["):
              end += 1
          item = lines[start:end]
          assert "(suite" not in " ".join(item) or replaces, f"{checklist}:{line} is already marked"
          if replaces:
              assert OLD_MARK.search(item[-1]), f"{checklist}:{line} has no older mark on its last line"
              item[-1] = OLD_MARK.sub("", item[-1])
          spans.append((start, end, place(item, mark)))
      for start, end, item in sorted(spans, reverse=True):
          lines[start:end] = item
          marked += 1
      path.write_text("\n".join(lines))
  print(f"{marked} lines marked")
  EOF
  ```
  It prints `148 lines marked`. `recording-r2` line 351 (part of a B line) gets no mark (D15).
- [ ] Spot-check the diff: `git diff --stat -- docs/testing` lists the eighteen checklists; `git diff -- docs/testing/recording-r4-manual-checklist.md` shows the three older in-part marks replaced and the calls G and H marked; no line outside an item changed.
- [ ] Correct the harness design's two lines on the calls G and H, and this design's counting sentence:
  ```bash
  python3 - <<'EOF'
  from pathlib import Path
  harness = Path("docs/superpowers/specs/2026-10-29-tidyshot-coordinator-harness-design.md")
  text = harness.read_text()
  fixes = [
      ("lines 224-227, 230-263, 271-291 and the calls A to F, except the real bucket, CloudFront, `footprint`, the Wi-Fi "
       "toggle, the AWS console and the Clop run. The calls G and H stay with Tim: G's second Abort must fail after a first "
       "that answered 204, which needs a per-call `FakeDestination` script the harness does not add, and H's rereads need "
       "a read counter `readPart` does not have.",
       "lines 224-227, 230-263, 271-291 and the calls A to H, except the real bucket, CloudFront, `footprint`, the Wi-Fi "
       "toggle, the AWS console and the Clop run. The harness covered A to F; the checklist tests phase covered G with the "
       "`onCall` script `FakeDestination` already had (`CoordinatorDeleteTests.aSecondAbortThatFailsAsksToRemoveFromHistory`) "
       "and H with a digest of each part's bytes (`UploadQueueTests.aPartRetrySendsTheBytesItFirstRead`)."),
      ("- 8 said the suite covers the calls A to H; it covers A to F. G (a second Abort failing after a 204) needs a\n"
       "  per-call Abort script `FakeDestination` does not have, and H needs a read counter `readPart` does not have (D18),\n"
       "  so both stay in Tim's R4 run.",
       "- 8 said the suite covers the calls A to H; the harness covered A to F, and G and H stayed in Tim's R4 run (D18).\n"
       "  The checklist tests phase (`docs/superpowers/specs/2026-10-30-tidyshot-checklist-tests-design.md`) covers G with\n"
       "  the `onCall` script `FakeDestination` already had and H with a digest of each part's bytes, so 8 reads A to H."),
  ]
  for old, new in fixes:
      assert text.count(old) == 1, old
      text = text.replace(old, new, 1)
  harness.write_text(text)

  design = Path("docs/superpowers/specs/2026-10-30-tidyshot-checklist-tests-design.md")
  text = design.read_text()
  old = ("2169 tests in 181 suites → 2272 in 191 (103 new test functions, 10 new suite files; a parameterized test counts "
         "once per argument in `xcodebuild`'s line, so the plan states the exact expected line after counting arguments).")
  new = ("2169 tests in 181 suites → 2272 in 191 (103 new test functions, 10 new suite files; `xcodebuild`'s line counts "
         "a parameterized test once, whatever its arguments).")
  assert text.count(old) == 1
  design.write_text(text.replace(old, new, 1))
  print("designs corrected")
  EOF
  ```
- [ ] Replace this design's `## 11. Built notes` placeholder (`(Written at close-out.)`) with:
  ```markdown
  ## 11. Built notes

  Built on `checklist-tests` from the plan `docs/superpowers/plans/2026-10-30-checklist-tests.md`. The suite reads
  `2272 tests in 191 suites` (2169 in 181, plus 103 test functions: 10 new suite files and 23 existing ones); write the
  last run's line here if it differs. `TidyShot/` and `project.yml` are unchanged.

  What was built differently from this design and from tests-A, each with its reason, is the plan's "Plan decisions"
  list, D1 to D31. In short:
  - Section 7 said a parameterized test counts once per argument; `xcodebuild` counts it once, as the baseline shows
    (2169 `@Test` functions, 2169 tests), and section 7 now says so. The totals were right (D1).
  - Section 3's four fake extensions landed as written; `FakeNotifier.Call`'s subtitle is a defaulted value of `.error`
    and `.notice`, so no existing test changed (D2). Two more support pieces landed with their first tests:
    `CoordinatorWorld.storeSaveFolder()` (D5) and `HeldMicrophoneDevices`, with `world.microphones` an
    `any MicrophoneDevices` (D4).
  - The three record-press tests press Record Fullscreen, since Record Screen's press reads `CaptureIntent.standard`
    and so `AppSettings.shared` (D6). The quit-mode test still sees the destination read for an uploading action (D7).
    The card's fraction is seen on a recording sent in parts, with a part held (D8).
  - The selection tests give the view a responder that keeps the keys it passes up, where the window would beep (D10).
  - The marks name every test that pins a part of the line, the existing D ones too (D13). 148 lines are marked, 14 of
    them in part; recording-r2 351, part of a B line, has none (D15). phase-2 51 is marked in full on PR #28's corrected
    text (D14), and recording-r2 312, phase-4a 108, phase-6a 215 and recording-r4 330 are marked in part though
    tests-A counted them in full (D16). phase-3 31 has obsolete-E's corrected text, and phase-3 26's mark names its D
    half (D17).
  - A call that only a regression would leave waiting is gated too: the two quits under a held prompt, and the saves
    that would open the folder panel if a recording were sent to the save folder by mistake (D31).
  - R4's calls G and H are covered, so the harness design's section 8 and its built notes read A to H again.

  Hand checks: none (section 8). The checklists' marks are the record.
  ```
- [ ] Run the full suite once more (`Test run with 2272 tests in 191 suites passed`) and the Release build. `git diff --stat main -- project.yml TidyShot` prints nothing.
- [ ] Commit: `docs: checklist tests marks and close-out`.

## Test totals

| After | Total |
|---|---|
| Baseline | 2169 tests in 181 suites (confirmed at f265aff) |
| Task 1 | unchanged (fake extensions; one assertion added to `UploadQueueTests.aFileAtTheThresholdGoesMultipart`) |
| Task 2 | 2180 in 181 (`CoordinatorDeleteTests` +11; `removingARecordClearsItsBookkeeping` extended) |
| Task 3 | 2189 in 181 (`CoordinatorUploadTests` +9) |
| Task 4 | 2198 in 182 (`CoordinatorSaveTests` 9, new) |
| Task 5 | 2205 in 182 (`CoordinatorDragOutTests` +7; `aFailureWithResumeDataKeepsItWithTheSigningTime` extended) |
| Task 6 | 2214 in 184 (`CoordinatorRecordActionsTests` 7 and `CoordinatorEditorTests` 2, new) |
| Task 7 | 2223 in 187 (`CoordinatorTrimTests` 4, `CoordinatorCaptureTests` 1 and `CoordinatorOverlayTests` 1, new; `CoordinatorRecordingTests` +3; `anOrphanMP4IsAdoptedWithItsLength` extended) |
| Task 8 | 2239 in 187 (`EditorModelTests` +9, `CounterTests` +2, `EditorFlattenerTests` +1, `EditorBackgroundExportTests` +4; `aSelectedCounterShowsAndTakesTheColour` extended) |
| Task 9 | 2252 in 188 (`CanvasViewEventTests` 5, new; `CanvasAccessibilityTests` +3, `CanvasFitTests` +3, `CanvasToolTests` +2) |
| Task 10 | 2263 in 191 (`SelectionViewTests` 6, `QuickAccessCardDragViewTests` 1 and `RecentCapturesMenuTests` 1, new; `SelfTimerTests`, `ClickRingOverlayTests`, `QuickAccessModelTests` +1 each) |
| Task 11 | 2272 in 191 (`AppSettingsTests` +2, `URLCommandHandlerTests` +2, `GIFFileSinkTests`, `ScrollCaptureSessionTests`, `TemplateExpanderTests`, `ThumbnailProviderTests`, `UploadQueueTests` +1 each; `uploadFailedWhenPutIsRejected` extended) |
| Task 12 | 2272 in 191 |

Each count is test functions: a parameterized test is one, whatever its arguments (D1). The 103 new functions and 5 extended ones are the design's 108 tests.

## Plan decisions

Where the plan departs from the design or from tests-A, or settles a detail they leave open, with the reason. Task 12 writes a summary into the design's built notes.

1. **The expected lines count test functions.** The design's section 7 says a parameterized test counts once per argument in `xcodebuild`'s line. The baseline tree has exactly 2169 `@Test` attributes (84 of them parameterized) and reads `2169 tests in 181 suites`, so each function counts once. The design's totals (2272 in 191) already counted that way; Task 12 corrects its sentence.
2. **`FakeNotifier.Call`'s subtitle is a defaulted associated value** of `.error` and `.notice` (`subtitle: String? = nil`). Every existing `.error(title:message:)` and `.notice(title:body:)` still compiles and now also compares a nil subtitle; the only coordinator paths that pass a subtitle (a URL command's notice, `action=copy`'s `Image copied`) no existing test reaches. `errors` binds the third value with `_`.
3. **The download throw script and the delete failure script are first exercised by their new tests** (Task 6's `aCopyImageWhoseDownloadFailsSaysCouldNotCopyImage`, Task 2's `aRemoteDeleteFailureDuringAnUploadKeepsTheRecordUntilRemoveFromHistory`): no existing test calls `download(key:)` or a DELETE whose failure would change anything, so there is nothing cheap to extend. The part digest is exercised at once by `aFileAtTheThresholdGoesMultipart`; the subtitle by every existing `.error` comparison. `delete(key:)` records a call in `deletedKeys` before it throws, so `deletedKeys` reads every DELETE sent.
4. **`HeldMicrophoneDevices` and `world.microphones` as `any MicrophoneDevices`** are a fifth support change the design's section 3 does not list; tests-A names both for `aSecondRecordPressWhileTheMicrophonePromptIsUpAsksNothingAndAQuitStartsNothing`. They land in Task 7 with that test. No existing test read `world.microphones`.
5. **`CoordinatorWorld.storeSaveFolder()`** stores `<root>/Saved/` with `SaveLocation.store`, as `SaveLocationStoreTests` does, and lands in Task 2 with its first user. The harness's D25 kept every upload in `pending/` because choosing a folder takes the panel; `store` needs no panel, and a stored folder gives `UploadPayload.video` its scope, so a save-folder recording uploads (design section 3's first use).
6. **The record-press tests press Record Fullscreen.** tests-A drives `recordScreen()`. Once the shortcut rule lets it start, `recordScreen()` evaluates `startRecordScreen(intent: .standard, …)`'s argument, and `CaptureIntent.standard` reads `AppSettings.shared`, which no test may touch. `recordFullscreen()` reads `.standard` only after `recordingPrompts()` returns, and every test here ends the start there (a prompt refused for the lock, or a quit before the answer). The second press in the held-prompt test is `recordScreen()`: the shortcut rule ignores it while the prompt is open, before `.standard` is read. The rule under test, `recordingPrompts`, is the one both presses share.
7. **The quit-mode test does not expect "no `askedConfigs`".** `saveRecording` reads the destination for an uploading action (`makeDestination()`, +Recording.swift:778) before quit mode decides anything; in quit mode the plan starts no upload. The test checks that nothing is sent (`uploadAttempts == 0`, `uploadingIDs` empty). It runs the four intents in one test, so `shutterCount` grows by one per save, and tests-A's `.copyOnly` is `CaptureIntent(action: .save, copyOnly: true)` (`copyOnly` is an intent flag, not an after-capture action, and a recording's save ignores it).
8. **The card's fraction is seen on a recording sent in parts, with part 3 held.** A screenshot's single PUT reports its fraction from an unstructured task (`throttledProgress`) that can lose the race with the queue's `.uploaded`, after which `setProgress` ignores it; the test would fail now and then. With a part held, parts 1 and 2 have reported and nothing ends the upload until the test releases it. The card's push (`refreshOverlay`) is the same for both.
9. **`Image copied` names the key for an uploaded capture that kept its file.** `copyImage` posts `uploadedKey ?? fileURL?.lastPathComponent` (+RecordActions.swift:101); tests-A said it names the file for the first two sources.
10. **The selection tests give the view a responder that keeps the keys it passes up.** `SelectionView` sends a key it does not handle to `super.keyDown` (Return and Enter in recording mode, Command-keys in All-in-One), and at the end of the chain the window beeps. The view's `nextResponder` is set to a `KeySink`, which also lets the tests see that those keys went on up.
11. **Copy File's cancel of the clean-up that was due is read off the task.** With the clipboard unchanged, the close's clean-up would wait again too (`dragCleanupStep` returns `.waitAgain` while the clipboard holds the reference), so the copy surviving the minute does not show the cancel; the test also checks `due.isCancelled` and that a new clean-up replaced it.
12. **`aRecordingsURLReplacesItsFileReferenceOnlyWhileTheClipboardHoldsIt(kind:clipboardMoved:)` takes `zip`'d arguments**, the MP4 with the clipboard unchanged and the GIF with it moved, as tests-A pairs them, rather than the four combinations.
13. **A mark names every test that pins part of its line.** tests-A gives each line's new test; the sweep's catalogue names the existing tests that pin the line's other parts (a pure rule, a text, a key map). A mark naming only the new test would claim the line on its behalf, so Task 12's marks list both, and the script checks that each named test exists.
14. **phase-2 line 51 is marked in full.** tests-A lists it in part against the old text (a saved row revealed its file); PR #28 replaced that with obsolete-E's corrected text (a never-uploaded row copies its file), which tests-A says the test covers in full.
15. **recording-r2 line 351 gets no mark.** Its held-prompt part is tested, but the line is B and stays with its seams (the status menu builder, the recording start), and tests-A counts it outside the 148.
16. **Four lines tests-A counts in full are marked in part**, because the line names a check no test makes: recording-r2 312 (tests-A's own entry says the card's tool tip and the relaunch stay by hand), phase-4a 108 (the editor's unsaved dot staying after a failed Save As…), phase-6a 215 (the status menu item shown disabled), recording-r4 330 (gap 22's "and has no menu item": the drag view's test drives only `mouseDown` and `mouseDragged`, and no test reads the card's menu items). The in-part lines are then tests-A's eleven, less phase-2 51 (D14), plus these four: 14.
17. **The marks are placed on PR #28's text, found by text.** PR #28 (not in this branch at f265aff) adds marks, wraps lines and corrects wording, so line numbers move; the script finds each item by text unique to it after PR #28 and stops if PR #28 is missing (Task 12's gate). It also does the two items PR #28 left for this phase: phase-3 31's corrected text and phase-3 26's D-half mark.
18. **Canvas events are placed through the canvas's own conversion.** A windowless view's `convert(_:from: nil)` is the only mapping the canvas applies to `locationInWindow`; the tests place each event at `canvas.convert(point, to: nil)`, its inverse, so they depend on neither how AppKit maps a windowless flipped view nor the backing scale.
19. **`aPointerOnTheCaptureMapsToItsPixelWithABackground` draws a rectangle from where the capture's corner is shown.** tests-A reads `model.transform.imagePoint` of that view point, which is the inverse of `viewPoint` for any transform; a drag through `CanvasView.input(for:)` shows that the canvas uses that transform, with the margin outside the capture.
20. **`theFitFramesTheBackgroundsCanvasAndRefitsOnAnAspectChange` asserts the fit as a relation** (the canvas rect centred in the inset box, inside it and touching it on one axis, within a point), and compares the no-background fit with a canvas that never had one, never with fixed numbers (design section 4).
21. **The retention test adds its old records under the 30-day default and then sets 1 day**, since `history.add` prunes as it adds; the new record's add is the prune under test.
22. **A recording's file is a few bytes, not a `VideoFixtures` MP4 or a `GIFBlocks` GIF.** `saveRecording` moves the file without reading it, and `FakeDestination` never reads a file it uploads, so a real movie adds nothing and costs time.
23. **The marked recording's Retry Failed Uploads posts nothing because a marked record is `.none`, not `.failed`**; the test pins what the line asks (no notice, nothing sent), and the refusal of a failed marked record is `UploadRefusalTests.retryFailedUploadsLeavesOutMarkedAndDeletingRecords`, named in the line's mark.
24. **`aTypedWidthResizesFromTheTopLeftWithoutCapturing` also types H**, which phase-6b 56 asks for in the same line ("The same for `H`").
25. **Failures are refusals where a retry would only add time.** The save test's failing destination and the trim test's failing part use a 403 (not retried) instead of 503s past the retry policy's attempts; the outcome, a failed upload, is the same.
26. **small-tweaks line 9's wrong secret is stood in for by missing credentials**, as tests-A has it: both make `deleteObjects` return a reason, which is what shows the second alert with Ask before deleting off. The DELETE failure script would also do; it is used by phase-3-1 51's test.
27. **Doc comments name their lines as `/// <checklist> :<line>. <rule>`**, the brief's form, with the e011d2f line numbers tests-A uses; an in-part line's comment says what stays by hand.
28. **The Copy Image download failure is `URLError(.notConnectedToInternet)`**, Wi-Fi off as the line has it; the notice carries its `localizedDescription`.
29. **`uploadAsNewCopiesTheNewLinkAndDeletesTheOldObject` reads the record back through a second coordinator for both arguments.** For the interrupted replace that is the relaunch the line needs; for the plain case it changes nothing and keeps one code path.
30. **`deleteRemovesTheObjectTheFileTheThumbnailAndTheRow` keeps every file in the stored save folder**, an image, a video and a GIF alike, so the delete goes through `SaveLocation.remove(at:)` for each, the save-folder path the lines describe; the pending-file path is the failed upload-only test's.
31. **A call that only a regression would leave waiting is gated too**, beyond the held fakes the harness's rule names. `finishRecordingForQuit` polls on the world's clock until `recordingPhase` is idle (AppCoordinator.swift:495); under a held camera or microphone prompt it returns only because the prompts come before the lock and the count-in, which is the rule those two tests pin. A start that locked or counted in first would leave the quit asleep on a clock nothing moves, and at the time limit the cancelled sleep would throw on every pass of a `try?` loop and wedge the run; so the quit runs in its own task, gated with `TaskWatch`, and the prompt's answer is deferred so it frees the start either way. A recording save sent to the save folder with no folder stored awaits `NSOpenPanel.begin()` (+Recording.swift:782, SaveLocation.swift:31), which no cancel ends: the marked test's first save, whose point is that no folder is asked for, is gated and closes any panel with `cancelFolderChoice()` before it fails, and the three upload-only saves (the waits-in-pending test and the two notice tests) store a folder first, so a misrouted save never waits on a panel; only the waits-in-pending test checks that the file is in `pending/`, the two notice tests do not pin where the file goes. On the regression the marked test guards (a marked save asking for a folder) a real `NSOpenPanel` shows and the test host activates for up to the gate's 2 s, until `cancelFolderChoice()` closes it and the test fails: the brief rules out a window ordered front, and no seam exists for that panel without changing `TidyShot/`, so this is the one place a regression, and only a regression, shows one. Separately, the Forget Credentials test checks `heldUploadCancellations` while the upload is still held: a held upload returns on its release even when cancelled, and the queue reports `.uploaded` whenever the PUT returns, so the record's end state alone would not show a cancel, and a cancel the queue started would land only after `destinationDidChange()` returned, so the test yields and waits 50 ms before it looks.
