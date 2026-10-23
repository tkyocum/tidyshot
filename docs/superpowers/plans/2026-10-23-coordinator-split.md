# TidyShot AppCoordinator Split, Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `TidyShot/App/AppCoordinator.swift` (3,492 lines) becomes `AppCoordinator.swift` (about 430 lines: every stored property, the composition root, quit, and the capture lock) plus ten `extension AppCoordinator` files, one per area, with no change in behaviour. Every moved line is byte-identical; the only edits are 76 access keywords. The 1272 tests in 131 suites pass unchanged after every commit.

**Architecture:** `docs/superpowers/specs/2026-10-23-coordinator-split-design.md` is the specification: the decision, the file map (3.1), the state groups (3.2), the 76 access changes (3.3), what stays private (3.4), the rules (4) and the checks (5). When this plan and the design disagree, the design wins; stop and ask if it is unclear.
- **One type.** `AppCoordinator` stays one `@Observable final class`. Extensions cannot hold stored properties, so all 55 stay in the class body, grouped by the area that owns them. `@ObservationIgnored` markings, doc comments and defaults do not change, so the tracked set and the status icon's observation are unchanged.
- **Pure moves.** A member moves with its doc comment and attributes, at its original 4-space indent, in its original relative order. `private` is file scope in Swift, so a member used from another file loses its `private ` or `private(set) ` token and nothing else. No member is narrowed, renamed or rewritten.
- **Nothing outside the family changes.** No test, no other source file, no `project.yml`. The three statics the tests reach (`recordingShortcutAction`, `holdsQuit`, `dragCleanupStep`) stay on `AppCoordinator`; the five top-level enums keep their names and move with their areas.

**Tech Stack:** Swift 6 language mode with default `MainActor` isolation and `NonisolatedNonsendingByDefault`, AppKit, ScreenCaptureKit, Observation, KeyboardShortcuts, Swift Testing, XcodeGen 2.46.

Work happens on the branch `coordinator-split`, cut from `main` at 3737262. Every line number in this plan is from `TidyShot/App/AppCoordinator.swift` at that commit; after Task 1 the file shifts, so cut by the member names given beside each range, and check the range against `git show 3737262:TidyShot/App/AppCoordinator.swift`. The design is committed with this plan.

## Global Constraints

- **Earlier constraints still apply.**
  - Minimum macOS 26.0, Swift 6 with MainActor by default, App Sandbox, credentials only in the Keychain.
  - One save, upload and delete path in `AppCoordinator`: `save`/`finishSave`, `startUpload` and `deleteCapture`/`removeRecord` each still exist once, and no new caller of any of them appears.
  - KeyboardShortcuts is the only Swift package. No GPL code is read or copied.
- **No behaviour change.** No user-visible string, default argument, `await`, `Task`, `defer` or capture list changes. No `nonisolated` is added or removed. No stored property leaves the class body, and the eight side-effecting defaults (`engine`, `saveLocation`, `settings`, `credentialStore`, `notifier`, `permissionWindow`, `overlay`, `clopOptimiser`) keep their relative order. No "while I'm here" fixes: the three quirks in the design's section 8 stay as they are.
- **Only the listed access changes.** Each task names the exact declarations that lose `private ` or `private(set) `. A compile error about a member not in that task's list means a cut landed in the wrong file: fix the cut, do not widen. Nothing becomes `fileprivate`, and nothing is narrowed.
- **Each new file is:** its imports; one `//` header line naming the area and saying its state is declared in `AppCoordinator.swift`; `extension AppCoordinator {`; the ranges in the order given, verbatim, with one blank line between members; `}`; then any top-level types the area owns, verbatim. Lines inside the extension keep their 4-space indent, so every moved line is byte-identical.
- **Checks after every commit**, from the repo root:
  ```bash
  xcodegen generate && xcodebuild test -project TidyShot.xcodeproj -scheme TidyShot -destination 'platform=macOS' -derivedDataPath .build 2>&1 | grep -E "Test run with|error:|TEST"
  ```
  The baseline, and the expected line after every commit, is `Test run with 1272 tests in 131 suites passed`. The Release build is `xcodebuild -project TidyShot.xcodeproj -scheme TidyShot -configuration Release -derivedDataPath .build-rel build` (Task 8 only). Then:
  ```bash
  # The pure-move check: every line of the family, less imports, wrappers, column-0 braces, indent-0/4 `//` comments
  # and blank lines, with the access tokens removed, as a multiset, equals the base file's.
  norm() { grep -vE '^(import |extension AppCoordinator \{$|\}$|(    )?// )' | sed -E 's/(^|[[:space:]])private(\(set\))? /\1/' | grep -v '^[[:space:]]*$' | sort; }
  diff <(git show 3737262:TidyShot/App/AppCoordinator.swift | norm) <(cat TidyShot/App/AppCoordinator*.swift | norm) && echo "pure move"
  # The access count: 151 at the base, down by exactly the commit's rows (the expected value is given per commit).
  cat TidyShot/App/AppCoordinator*.swift | grep -cE '(^|[[:space:]])private(\(set\))? '
  # The diff review: moved blocks, the access edits, the new file's imports, header and wrapper, the dropped MARK lines, and nothing else.
  git diff HEAD~1 --color-moved=dimmed-zebra --color-moved-ws=allow-indentation-change -- TidyShot/App
  ```
  `pure move` must print, the count must match, and the diff must show nothing unexplained. The check does not see a reorder inside a body; the diff review does, so look at every block that is not shown as moved whole.
- **Commits.** One commit per file (Task 1 has three, Tasks 2 and 6 have two), each green on every check above, with a conventional message and no attribution lines. Never push.

### Task 1: Group the state, then Pins and Overlay

**Files:**
- Modify `TidyShot/App/AppCoordinator.swift` (the stored properties are regrouped; nothing else in the file changes in the first commit).
- Create `TidyShot/App/AppCoordinator+Pins.swift` and `TidyShot/App/AppCoordinator+Overlay.swift`.

**Produces:**
- The class body's stored properties in the design's 3.2 order, under `// MARK:` group lines, with `editors` and `isObservingSaveFolder` (2716-2719) moved up from the Editor section into the class body's state block.
- `+Pins`: `retainedCaptureID` (181-182), `hasPins`, `hasLockedPins`, `unlockPins`, `closePins`, `pin`, `pinScreen`, `pinActions`, `forgetLatestCapture` (2793-2865). 9 access changes.
- `+Overlay`: `showOverlay`, `overlayActions`, `overlayScreen`, `overlayDidClose`, `canRestoreClosedOverlay`, `restoreClosedOverlay` (1393-1475), `refreshOverlay`, `pushCardFlags` (2348-2363). 9 access changes.

**Steps:**
- [ ] **Regroup.** Reorder the stored properties of `AppCoordinator.swift` into this sequence, each range cut whole (doc comment, attributes, declaration, default) and pasted in this order, with the `// MARK:` lines added as plain `//` comments at indent 4:
  1. line 17 (`shared`), a blank line;
  2. `// MARK: Collaborators`, then lines 19-69 exactly as they are;
  3. `// MARK: Capture state (AppCoordinator+Capture.swift; the lock is withCaptureLock, below)`, then 150 (`isCapturing`), 166-167 (`lastCaptureURL`);
  4. `// MARK: Recording state (AppCoordinator+Recording.swift)`, then 151-165 (`isRecording` … `isQuitting`), 173-177 (`videoClipboardCounts`);
  5. `// MARK: Retained capture and pins (AppCoordinator+Pins.swift)`, then 105-116 (`latestCapture`, `latestCaptureArea`, `pins`, `pinningIDs`);
  6. `// MARK: Overlay state (AppCoordinator+Overlay.swift)`, then 117-121 (`closedOverlays`, `isRestoring`);
  7. `// MARK: Upload state (AppCoordinator+Upload.swift)`, then 70-99 (`queue` … `uploadActivity`, with `clopOptimiser` at 79 inside), 103-104 (`warnedUploadNotConfigured`), 124-125 (`postedCacheNote`), 168-172 (`uploadingIDs`, `linkNotCopiedIDs`);
  8. `// MARK: Delete state (AppCoordinator+Delete.swift)`, then 100-102 (`deletingIDs`);
  9. `// MARK: Drag-out state (AppCoordinator+DragOut.swift)`, then 130-148;
  10. `// MARK: Editor state (AppCoordinator+Editor.swift)`, then 122-123 (`openingEditorIDs`), 126-129 (`clipboardOwner`), 2716-2719 (`editors`, `isObservingSaveFolder`, cut from under `// MARK: Editor`);
  11. a blank line, then 179-191 (`permissionGranted` … `recordingPhase`) as they are. Later commits move 181-182 (`retainedCaptureID`, Pins below), 180 (`isUploading`, Task 4) and 183-191 (`recordingPhase`, Task 6); `permissionGranted` (179) stays in the root for good.

  Under the Upload, Drag-out and Editor MARKs add the `//` writer notes from the design's 3.2 sketch (one or two lines each, plain `//`, not `///`). Nothing else moves and no keyword changes.
- [ ] Check the initialiser order: `grep -nE '^    (private )?let (engine|saveLocation|settings|credentialStore|notifier|permissionWindow|overlay|clopOptimiser)\b' TidyShot/App/AppCoordinator.swift` lists the eight in that order, `clopOptimiser` last. Check that every default moved is `nil`, `false`, `0`, `[]`, `[:]` or `ClosedOverlays()`, or the property is `lazy`.
- [ ] Run the full suite and the checks. The access count is still 151.
- [ ] Commit: `refactor: group AppCoordinator's stored state by area`.
- [ ] **Pins.** Create `AppCoordinator+Pins.swift`: `import AppKit`; header `// Pin to screen and the retained capture (spec 2.9). Its state is declared in AppCoordinator.swift.`; `extension AppCoordinator {`; lines 181-182 (`retainedCaptureID`), then 2793-2865 (`hasPins` through `forgetLatestCapture`); `}`. Delete those lines from `AppCoordinator.swift`.
- [ ] Remove the access token from exactly these 9 declarations: `private let notifier` (29), `private var deletingIDs` (102), `private var latestCapture` (110), `private var latestCaptureArea` (113), `private lazy var pins` (115), `private var pinningIDs` (116), `private func forgetLatestCapture` (2860, now in `+Pins`), `private func afterMenuTracking` (2869, still in the root), `private func openEditorAfterMenuTracking` (2876, still in the root).
- [ ] Run the full suite and the checks. The access count is 142.
- [ ] Commit: `refactor: move pins into AppCoordinator+Pins.swift`.
- [ ] **Overlay.** Create `AppCoordinator+Overlay.swift`: `import AppKit`; header `// The Quick Access overlay: showing, restoring and refreshing cards. Its state is declared in AppCoordinator.swift.`; `extension AppCoordinator {`; lines 1393-1475 (`showOverlay` through `restoreClosedOverlay`), then 2348-2363 (`refreshOverlay`, `pushCardFlags`); `}`. Delete those lines from `AppCoordinator.swift`.
- [ ] Remove the access token from exactly these 9 declarations: `private let overlay` (31), `private var closedOverlays` (118), `private var isRestoring` (121), `private func showOverlay` (1395), `private func overlayDidClose` (1441), `private func refreshOverlay` (2351) (all three now in `+Overlay`), `private func dragDidEnd` (2613), `private func scheduleDragCleanup` (2623), `private func pushEditorState` (2934) (all three still in the root). `overlayDidClose` is wired from `init` (201): it must compile from the root.
- [ ] Run the full suite and the checks. The access count is 133.
- [ ] Commit: `refactor: move the overlay into AppCoordinator+Overlay.swift`.

### Task 2: Drag-out and record actions

**Files:**
- Create `TidyShot/App/AppCoordinator+DragOut.swift` and `TidyShot/App/AppCoordinator+RecordActions.swift`.
- Modify `TidyShot/App/AppCoordinator.swift`.

**Consumes:** Task 1's widened `overlay`, `notifier`, `afterMenuTracking`, `scheduleDragCleanup`, `dragDidEnd`.

**Produces:**
- `+DragOut`: `dragCleanupDelay`, `prepareDragFile`, `prefetchDragFile`, `keepForDragOut`, `dragDidEnd`, `scheduleDragCleanup`, `dragCleanupStep`, `removeDragFolder`, `stageVideoDragFile`, `dropStaleDragFolder` (2505-2712); top level `DragCleanupStep` (3462-3469). 11 access changes. `DragCleanupTests` still reads `AppCoordinator.dragCleanupStep`.
- `+RecordActions`: `copyLinkOrFile` through `reveal` (1827-2086), `afterMenuTracking` (2867-2873), `writeSaveAsCopy`, `performSaveAs`, `saveAsSuggestion` (3112-3156); top level `CopyImageError` (3471-3492). 3 access changes.

**Steps:**
- [ ] **Drag-out.** Create `AppCoordinator+DragOut.swift`: `import AppKit`; header `// Drag-out from a card and the drag folders (spec 2.9, Gap 7). Its state is declared in AppCoordinator.swift.`; `extension AppCoordinator {`; lines 2505-2712; `}`; a blank line; lines 3462-3469 (`DragCleanupStep`). Delete those lines and the `// MARK: Drag-out` line (2503) from `AppCoordinator.swift`. The static `dragCleanupDelay` and the `nonisolated static dragCleanupStep` sit in the extension unchanged.
- [ ] Remove the access token from exactly these 11 declarations: `private var dragGenerations` (132), `private var dragStageSeqs` (135), `private var dragCleanups` (138), `private var prefetchingDragIDs` (140), `private(set) var stagingVideoIDs` (144), `private(set) var copyFileCounts` (148), `private func downloadImage` (2064, still in the root), `private func keepForDragOut` (2594), `private func removeDragFolder` (2650), `private func stageVideoDragFile` (2668) (all three now in `+DragOut`), `private func saveAsSuggestion` (3147, still in the root).
- [ ] Run the full suite and the checks. The access count is 122. `DragCleanupTests` compiles unchanged.
- [ ] Commit: `refactor: move drag-out into AppCoordinator+DragOut.swift`.
- [ ] **Record actions.** Create `AppCoordinator+RecordActions.swift`: `import AppKit`; header `// The actions on a record from a card, a pin or a Recent Captures row: copy, open, reveal, Save As…. Their state is declared in AppCoordinator.swift.`; `extension AppCoordinator {`; lines 1827-2086 (`copyLinkOrFile` through `reveal`), then 2867-2873 (`afterMenuTracking`), then 3112-3156 (`writeSaveAsCopy`, `performSaveAs`, `saveAsSuggestion`); `}`; a blank line; lines 3471-3492 (`CopyImageError`). Delete those lines from `AppCoordinator.swift`.
- [ ] Remove the access token from exactly these 3 declarations: `private func loadCredentials` (1487, still in the root; `downloadSource` calls it), `private func imageData` (2025, now in `+RecordActions`; the root's `loadImage` calls it), `private func writeSaveAsCopy` (3117, now in `+RecordActions`; the root's `editorSaveAs` calls it). `performSaveAs` stays private: both its callers moved with it.
- [ ] Run the full suite and the checks. The access count is 119.
- [ ] Commit: `refactor: move the record actions into AppCoordinator+RecordActions.swift`.

### Task 3: Delete

**Files:**
- Create `TidyShot/App/AppCoordinator+Delete.swift`.
- Modify `TidyShot/App/AppCoordinator.swift`.

**Consumes:** Task 1's `pushEditorState`, `forgetLatestCapture`, `pins`, `overlay`, `notifier`, `deletingIDs`; Task 2's `removeDragFolder`, `copyFileCounts`.

**Produces:** `+Delete`: `deleteCapture`, `notifyKept`, `deleteObjects`, `removeFromHistoryOnly` (2090-2210), `removeRecord`, `removePendingFile`, `confirmDelete`, `confirmRemoveFromHistory`, `removeFiles(ofPruned:)` (2236-2337). `cancelUpload` (2212-2234) stays behind for Task 4. 11 access changes. `removeFiles` is wired from `init` (200).

**Steps:**
- [ ] Create `AppCoordinator+Delete.swift`: `import AppKit`; header `// The one delete path, and the teardown that pruning shares with it. Its state is declared in AppCoordinator.swift.`; `extension AppCoordinator {`; lines 2090-2210, then 2236-2337; `}`. Delete those lines and the `// MARK: Delete` line (2088) from `AppCoordinator.swift`. `cancelUpload` (2212-2234) stays in the root.
- [ ] Remove the access token from exactly these 11 declarations: `private(set) var optimizingVideoIDs` (90), `private var fileUploadIDs` (96), `private(set) var lastCaptureURL` (167), `private(set) var linkNotCopiedIDs` (172), `private(set) var videoClipboardCounts` (177), `private func storedCredentials` (1499), `private static func keychainReadFailure` (1507), `private func cancelUpload` (2215) (all three still in the root), `private func deleteObjects` (2175), `private func removePendingFile` (2263), `private func removeFiles` (2319) (all three now in `+Delete`).
- [ ] Review the moved `removeRecord` (2240-2257) and `removeFiles` (2319-2337) line by line in the diff: their order is behaviour (`overlay.close` before `removeDragFolder`; the four set removals in the same order in both).
- [ ] Run the full suite and the checks. The access count is 108.
- [ ] Commit: `refactor: move delete into AppCoordinator+Delete.swift`.

### Task 4: Upload

**Files:**
- Create `TidyShot/App/AppCoordinator+Upload.swift`.
- Modify `TidyShot/App/AppCoordinator.swift`.

**Consumes:** Task 1's `refreshOverlay`, `notifier`, `deletingIDs`; Task 2's `keepForDragOut`; Task 3's `removePendingFile`, `storedCredentials`, `keychainReadFailure`, `cancelUpload`, the four sets.

**Produces:** `+Upload`: `UploadLane` (9-15), `isUploading` (180), `warnUploadNotConfiguredOnce` (1313-1320), `makeDestination` through `refuseOversizedUpload` (1477-1701), `removeClopFile` through `uploadPayload` (1713-1825), `cancelUpload` (2212-2234), `markFailed` (2341-2346), `handle(_:at:)` and `deleteOrphanedObject` (2365-2501). `updateUploadActivity` (1703-1711) stays in the root with `fileUploadIDs.didSet`. 15 access changes.

**Steps:**
- [ ] Create `AppCoordinator+Upload.swift`: `import AppKit`; header `// Uploads: the destination, the lanes, Clop, the size check, retry and the queue's events. Its state is declared in AppCoordinator.swift.`; `extension AppCoordinator {`; lines 9-15 (`UploadLane`), 180 (`isUploading`), 1313-1320, 1477-1701, 1713-1825, 2212-2234, 2341-2346, 2365-2501, in that order; `}`. Delete those lines and the `// MARK: Upload events` line (2339) from `AppCoordinator.swift`. `updateUploadActivity` (1703-1711) stays.
- [ ] Remove the access token from exactly these 15 declarations: `private struct UploadLane` (11, now in `+Upload`; it is the type of `queue` and `drainingQueues` in the class body), `private var queue` (72), `private var drainingQueues` (76), `private let clopOptimiser` (79), `private var optimisingIDs` (84), `private var clopWaitsPerLane` (87), `private var clopResults` (93), `private var warnedUploadNotConfigured` (104), `private var postedCacheNote` (125), `private(set) var uploadingIDs` (169), `private func recordingBaseName` (1278, still in the root; `refuseOversizedUpload` calls it), `private func warnUploadNotConfiguredOnce` (1316), `private func startUpload` (1548), `private func markFailed` (2341) (all three now in `+Upload`; the root's `finishSave` calls them), `private func deleteSupersededObjects` (3255, still in the root; `handle(.uploaded)` calls it).
- [ ] Review the moved `handle(_:at:)` (2366-2478) in the diff: the Clop-file, optimizing and `fileUploadIDs` cleanup at the top before any early return, and `keepForDragOut` before `history.update`.
- [ ] Run the full suite and the checks. The access count is 93.
- [ ] Commit: `refactor: move upload into AppCoordinator+Upload.swift`.

### Task 5: Editor

**Files:**
- Create `TidyShot/App/AppCoordinator+Editor.swift`.
- Modify `TidyShot/App/AppCoordinator.swift`.

**Consumes:** Task 1's `latestCapture`, `closedOverlays`, `overlay`, `refreshOverlay`, `afterMenuTracking`; Task 2's `imageData`, `writeSaveAsCopy`, `saveAsSuggestion`, `removeDragFolder`; Task 3's `deleteObjects`; Task 4's `queue`, `startUpload`.

**Produces:** `+Editor`: `hasUnsavedEditors` (2721-2724), `openEditor`, `loadAndPresentEditor`, `loadImage` (2737-2791), `openEditorAfterMenuTracking` (2875-2878), `presentEditor` through `editorSaveAs` (2880-3110), `editorUpload` through `editorDidClose` (3158-3335). `holdsQuit` and `quitNeedsHold` (2726-2735) and `reviewEditorsBeforeQuit` (3337-3348) stay in the root. 5 access changes.

**Steps:**
- [ ] Create `AppCoordinator+Editor.swift`: `import AppKit`, `import Observation` (for `withObservationTracking`, as CanvasView does); header `// The editor bridge (spec 2.6): opening editors and their Save, Save As…, Upload and Copy. Its state is declared in AppCoordinator.swift.`; `extension AppCoordinator {`; lines 2721-2724, 2737-2791, 2875-2878, 2880-3110, 3158-3335, in that order; `}`. Delete those lines and the `// MARK: Editor` line (2714) from `AppCoordinator.swift`. `holdsQuit`, `quitNeedsHold` and `reviewEditorsBeforeQuit` stay.
- [ ] Remove the access token from exactly these 5 declarations: `private var openingEditorIDs` (123), `private var clipboardOwner` (129), `private var editors` (2717), `private var isObservingSaveFolder` (2719) (all four in the class body), `private func keepOnClipboard` (1358, still in the root; `editorUpload` calls it).
- [ ] Review the moved `presentEditor` (2882-2902) in the diff: `editors[record.id] = controller`, `pushEditorState`, `observeSaveFolderForEditors`, then `overlay.close(.editorOpened)` before `closedOverlays.didClose`, in that order.
- [ ] Run the full suite and the checks. The access count is 88. `QuitHoldTests` compiles unchanged (`holdsQuit` is still in the root).
- [ ] Commit: `refactor: move the editor bridge into AppCoordinator+Editor.swift`.

### Task 6: The two save funnels

**Files:**
- Create `TidyShot/App/AppCoordinator+Save.swift` and `TidyShot/App/AppCoordinator+Recording.swift`.
- Modify `TidyShot/App/AppCoordinator.swift`.

**Consumes:** Task 1's `showOverlay`, `latestCapture`, `latestCaptureArea`, `notifier`; Task 3's `lastCaptureURL`, `videoClipboardCounts`; Task 4's `startUpload`, `markFailed`, `warnUploadNotConfiguredOnce`, `recordingBaseName`; Task 5's `clipboardOwner`.

**Produces:**
- `+Save`: `save`, `withWindowBackground`, `notifyUnusableBackgroundImage`, `copyOnly`, `persist`, `SaveNotification`, `finishSave` (952-1184), `writeFile`, `writePendingFile`, `keepOnClipboard`, `makeThumbnail` (1322-1391). 3 access changes.
- `+Recording`: `recordingPhase` (183-191), `recordingCountInSeconds` through `endRecording` (493-756), `saveRecording`, `recordingBaseName`, `placeRecording` (1186-1311); top level `RecordingSaveMode`, `RecordingPhase`, `RecordingShortcutAction` (3437-3460). 9 access changes. `ShortcutsTests` still reads `AppCoordinator.recordingShortcutAction`.

**Steps:**
- [ ] **Save.** Create `AppCoordinator+Save.swift`: `import AppKit`; header `// The screenshot save funnel and the tail it shares with saveRecording (finishSave). Its state is declared in AppCoordinator.swift.`; `extension AppCoordinator {`; lines 952-1184, then 1322-1391; `}`. Delete those lines from `AppCoordinator.swift`. The `// MARK: Save and upload` line (950) stays until the Recording commit empties its section.
- [ ] Remove the access token from exactly these 3 declarations, all now in `+Save`: `private enum SaveNotification` (1131), `private func finishSave` (1147), `private func makeThumbnail` (1370). The root's `saveRecording` builds a `SaveNotification` and calls `finishSave`; its `recoverRecordings` calls `makeThumbnail`.
- [ ] Review the moved `save` (963-1021) and `finishSave` (1147-1184) in the diff: `latestCapture = nil` before `persist`; `latestCaptureArea` and `clipboardOwner` after `persist` and before `intent.then`; in `finishSave`, warn, shutter, `history.add`, `makeThumbnail`, `showOverlay`, `startUpload`, notification, the optional thumbnail await.
- [ ] Run the full suite and the checks. The access count is 85.
- [ ] Commit: `refactor: move the save funnel into AppCoordinator+Save.swift`.
- [ ] **Recording.** Create `AppCoordinator+Recording.swift`: `import AppKit`, `import ScreenCaptureKit`; header `// Record Screen and Record Fullscreen (recording design): start, hand-off, recovery, end and the recording save funnel. Its state is declared in AppCoordinator.swift.`; `extension AppCoordinator {`; lines 183-191 (`recordingPhase`), 493-756, 1186-1311, in that order; `}`; a blank line; lines 3437-3460 (the three enums). Delete those lines and the `// MARK: Recording` (491) and `// MARK: Save and upload` (950) lines from `AppCoordinator.swift`: nothing is left under the second, and the first would now head the capture helpers (758-948) that Task 7 moves.
- [ ] Remove the access token from exactly these 9 declarations: `private lazy var selector` (32), `private lazy var selfTimer` (41), `private lazy var recorder` (45), `private lazy var covers` (54), `private(set) var isRecording` (153), `private var recordingCountIn` (158), `private(set) var recordingSavesInFlight` (161) (all in the class body; `+Capture` will use the first two and `covers` too), `private func recoverRecordings` (713, now in `+Recording`; `start` calls it), `private func withCaptureLock` (3413, still in the root). `isQuitting` keeps `private(set)`: only `finishRecordingForQuit` in the root writes it. `recordingCountInSeconds`, `placeRecording`, `connectedDisplay`, `recordingDisplay` and `visibleFrame` stay private.
- [ ] Review the moved `record` (605-618) and `saveRecording` (1199-1274) in the diff: `isQuitting` read right before `recorder.run` with no await between; `recordingSavesInFlight += 1` before `recorder.close()`; the `defer`; `quitMode` re-read after each await; the `videoClipboardCounts` write beside the clipboard copy.
- [ ] Run the full suite and the checks. The access count is 76. `ShortcutsTests` and `QuitHoldTests` compile unchanged.
- [ ] Commit: `refactor: move recording into AppCoordinator+Recording.swift`.

### Task 7: Capture, and the root's final shape

**Files:**
- Create `TidyShot/App/AppCoordinator+Capture.swift`.
- Modify `TidyShot/App/AppCoordinator.swift`.

**Consumes:** Task 6's `withCaptureLock`, `selector`, `selfTimer`, `covers`; the internal `loadContent`, `save`.

**Produces:**
- `+Capture`: the ten image capture entry points (299-489), `runSelection` through `capture(_:excludingWindows:duringSelection:)` (758-948, `revealLastCapture` included), `cardWindows` (3388-3394), `display(under:in:)` (3426-3431). 1 access change.
- `AppCoordinator.swift` at about 430 lines: the state (Task 1), `permissionGranted`, `init`, `start`, `showPermissionWindow`, `handleURL`, `urlCommandScreens`, `setDesktopIconsHidden`, `toggleDesktopIconsHidden`, `registerShortcuts`, `updateUploadActivity`, `holdsQuit`, `quitNeedsHold`, `reviewEditorsBeforeQuit`, `finishRecordingForQuit`, `quitPollInterval`, `loadContent`, `withCaptureLock`, and `extension AppCoordinator: URLCommandTarget {}`, under MARK lines.

**Steps:**
- [ ] Create `AppCoordinator+Capture.swift`: `import AppKit`, `import ScreenCaptureKit`; header `// Image capture flows: the entry points behind the status menu, the shortcuts and the URL commands, ending in save(_:intent:). Their state is declared in AppCoordinator.swift.`; `extension AppCoordinator {`; lines 299-489, 758-948, 3388-3394, 3426-3431, in that order; `}`. Delete those lines from `AppCoordinator.swift`.
- [ ] Remove the access token from exactly this 1 declaration: `private lazy var scrollCapture` (33). `cardWindows` stays private: its callers all moved with it.
- [ ] Tidy the root with plain `//` lines and one block move, nothing else: `// MARK: Lifecycle` before `init`; move `urlCommandScreens` (3396-3407, whole block) to directly after `handleURL` (232-234) and put `// MARK: URL commands and desktop icons` before `handleURL`; `// MARK: Shortcuts` before `registerShortcuts`; `// MARK: Upload activity (fileUploadIDs.didSet)` before `updateUploadActivity`; `// MARK: Quit` before `holdsQuit`; replace `// MARK: Helpers` (3369) with `// MARK: Shared by +Capture and +Recording` before `loadContent`. The pure-move check ignores these lines, and the moved block shows as moved whole.
- [ ] Run the full suite and the checks. The access count is 75; `wc -l TidyShot/App/AppCoordinator*.swift` shows the root at about 430 lines and the family at about 3,600.
- [ ] Check the surface (design rule 5) over all 76 widened members. Code outside the family reaches the coordinator through `coordinator` (a stored property, a local, or a closure parameter), `AppCoordinator.shared`, `AppCoordinator.` (statics and types) and `$0` (the closures passed to `RecentCapturesMenu.afterMenusClose`, lines 110-112). The first grep looks for the 67 members widened from `private` (32 stored properties, 2 nested types, 33 methods) behind those receivers. The second looks for a write to the 9 widened from `private(set)` on any receiver: outside reads of `isRecording`, `lastCaptureURL` and `optimizingVideoIDs` are legitimate today (3.5), so only an assignment, a compound assignment, a subscript assignment or a mutating call is new. Doc-comment lines are dropped. Together they print nothing:
  ```bash
  W='notifier|overlay|selector|selfTimer|covers|scrollCapture|recorder|recordingCountIn|queue|drainingQueues|clopOptimiser|optimisingIDs|clopWaitsPerLane|clopResults|warnedUploadNotConfigured|postedCacheNote|fileUploadIDs|deletingIDs|latestCapture|latestCaptureArea|pins|pinningIDs|closedOverlays|isRestoring|openingEditorIDs|editors|isObservingSaveFolder|clipboardOwner|dragGenerations|dragStageSeqs|prefetchingDragIDs|dragCleanups|UploadLane|SaveNotification|finishSave|makeThumbnail|keepOnClipboard|warnUploadNotConfiguredOnce|recoverRecordings|recordingBaseName|showOverlay|overlayDidClose|refreshOverlay|loadCredentials|storedCredentials|keychainReadFailure|startUpload|cancelUpload|markFailed|imageData|downloadImage|afterMenuTracking|writeSaveAsCopy|saveAsSuggestion|deleteObjects|removePendingFile|removeFiles|keepForDragOut|dragDidEnd|scheduleDragCleanup|removeDragFolder|stageVideoDragFile|forgetLatestCapture|openEditorAfterMenuTracking|pushEditorState|deleteSupersededObjects|withCaptureLock'
  S='optimizingVideoIDs|stagingVideoIDs|copyFileCounts|isRecording|recordingSavesInFlight|lastCaptureURL|uploadingIDs|linkNotCopiedIDs|videoClipboardCounts'
  { grep -rnE "(coordinator|AppCoordinator(\.shared)?|\\\$0)\??\.($W)\b" TidyShot --include='*.swift'
    grep -rnE "\.($S)(\[[^]]*\])?[[:space:]]*([-+]?=[^=]|\.(insert|remove|removeAll|removeValue|update|formUnion|subtract|merge)\()" TidyShot --include='*.swift'
  } | grep -v 'TidyShot/App/AppCoordinator' | grep -vE '^[^:]+:[0-9]+:[[:space:]]*//'
  ```
  `W` is 3.3's stored-property, nested-type and method rows; `S` is its `private(set)` rows. A hit is code outside the family reaching a widened member: stop and ask. The grep knows only these receivers, so a new spelling (`let c = AppCoordinator.shared`) needs adding to it.
- [ ] Commit: `refactor: move image capture into AppCoordinator+Capture.swift`.

### Task 8: Checklist, specs, README and design close-out

**Files:** Create `docs/testing/coordinator-split-manual-checklist.md`. Modify `docs/superpowers/specs/2026-10-19-tidyshot-screenshot-design.md` (2.6 and section 5), `docs/superpowers/specs/2026-10-21-tidyshot-screen-recording-design.md` (the R2 list), `README.md` (Documents) and `docs/superpowers/specs/2026-10-23-coordinator-split-design.md` (a Built section).

**Steps:**
- [ ] Run the full suite and the Release build once; both must be clean. Run the pure-move check a last time and record its output.
- [ ] Write the checklist: about fifteen items, each exercising one file's wiring, for Tim's hand pass in the Debug build:
  - launch with Hide Desktop Icons on (root: `start`, `covers`);
  - Capture Area: the file, the card and the clipboard (`+Capture`, `+Save`, `+Overlay`);
  - All-in-One Timer and Scrolling (`+Capture`);
  - Capture Text (`+Capture`);
  - an upload-only capture: the status icon's arrow, `URL copied`, then drag the card out (`+Upload`, `+DragOut`, the observation path);
  - Retry Failed Uploads with no destination: one notification (`+Upload`);
  - Annotate the newest card, Save, then Upload (`+Editor`);
  - Pin, then the pin menu's three items (`+Pins`, `+RecordActions`);
  - Delete during an upload (`+Delete`, `cancelUpload`);
  - Restore Closed Overlay (`+Overlay`, and `init`'s `overlay.onDidClose`);
  - retention pruning of a pinned upload-only capture that has uploaded: quit, set its `timestamp` in `history.json` to two days ago, relaunch, pin it from Recent Captures, set Overlay > `Keep history for 1 days`, then take a new capture: the record leaves Recent Captures, its pin closes and its file leaves `pending/`; set the retention back (`init`'s `history.didPrune`, `+Delete`'s `removeFiles(ofPruned:)`, `+Pins`);
  - Record Screen with Clop on: `Optimizing…`, then Copy File (`+Recording`, `+Upload`, `+RecordActions`);
  - quit during a recording (`+Recording`, quit);
  - quit with an unsaved editor (`+Editor`, quit);
  - a `tidyshot://capture-area` URL with a rect, and `tidyshot://toggle-desktop-icons` (root, `URLCommandTarget`);
  - `record.circle` in the menu bar while recording.
- [ ] Screenshot design 2.6, the paragraph at line 134 that says the editor bridge "has to" live in `AppCoordinator.swift` because of `private` members: replace it with one that says the bridge lives in `AppCoordinator+Editor.swift` and calls internal members of the coordinator declared in its other files, keeping the sentence about every branch coming from a tested helper in `Editor/Persistence/`.
- [ ] Screenshot design section 5, the `AppCoordinator` bullet (line 1497): keep its sentence, then add the file map (the eleven files and what each holds, one line each) and the four conventions from the coordinator split design's section 6.
- [ ] Recording design, the R2 list (line 562): add one line saying that the coordinator's part of the microphone, GIF export and trim lands in the files named in the coordinator split design, section 6. Name no other R2 item: section 6 maps only those three, and the line must not claim more.
- [ ] README, Documents: add `Coordinator split design: docs/superpowers/specs/2026-10-23-coordinator-split-design.md` after the recording design line, and `Coordinator split manual test checklist: docs/testing/coordinator-split-manual-checklist.md` at the end of the list. README has no architecture section, so nothing else changes.
- [ ] Add a short `## 9. Built` section to the coordinator split design: the date and branch, the suite line, the final line counts of the eleven files, the access count (75), the pure-move check's output, anything that differed from the plan (a range that had to move, a row that turned out needless or missing), and a line that Tim's hand pass is pending.
- [ ] Commit: `docs: coordinator split checklist, specs, README and design close-out`.

## Test totals

| After | Total |
|---|---|
| Baseline | 1272 tests in 131 suites |
| Task 1 | unchanged |
| Task 2 | unchanged (`DragCleanupTests` compiles against `AppCoordinator.dragCleanupStep`, now in `+DragOut`) |
| Task 3 | unchanged |
| Task 4 | unchanged |
| Task 5 | unchanged (`QuitHoldTests` compiles against `AppCoordinator.holdsQuit`, still in the root) |
| Task 6 | unchanged (`ShortcutsTests` compiles against `AppCoordinator.recordingShortcutAction`, now in `+Recording`) |
| Task 7 | unchanged |
| Task 8 | unchanged, 1272 tests in 131 suites |
