# TidyShot AppCoordinator Split, Design

Date 2026-10-23. Branch `coordinator-split`, cut from `main` at 3737262. Line numbers below are from
`TidyShot/App/AppCoordinator.swift` at that commit (3,492 lines). The responsibility map this was
judged from is summarised in section 3; the app-wide design is
`2026-10-19-tidyshot-screenshot-design.md` and recording's is
`2026-10-21-tidyshot-screen-recording-design.md`.

## 1. Goal

`AppCoordinator.swift` is one `@Observable final class` of about 3,500 lines. It is the one save,
upload and delete path, and it owns the capture flows, recording, uploads and Clop, history, the
Quick Access overlay, drag-out, the editor bridge, pins, URL commands, desktop covers and quit.
Recording R2 (GIF output, the microphone, trim) adds to recording, upload, the card actions and a
new trim area, and three implementers would edit one file.

Split the file so that each area has a file of its own, with no change in behaviour: every
user-visible string, ordering and state hand-off stays, and the 1272 tests in 131 suites pass
unchanged after every step.

## 2. The decision

**`AppCoordinator` stays one type. Its members move, byte for byte, into ten
`extension AppCoordinator` files, one per area. `AppCoordinator.swift` keeps every stored property,
grouped by the area that owns it, plus the composition root (init, start, shortcuts, quit, the URL
and desktop-icon wiring) and the two members image capture and recording share: the capture lock
and the content read. 76 declarations widen from `private` to internal so the other files can reach
them. Nothing is renamed, no body changes, no test changes, no other source file changes.**

### Why this one

- **Zero behaviour change is provable.** A body whose only change is its file keeps its meaning:
  after the split it sees a subset of what it saw before (its own file's privates plus every
  internal member), so no unqualified name can start resolving to a different declaration, and a
  missed widening is a compile error, never a silent change. A three-line check (section 5)
  compares the line multiset of the whole family against the base file, so a dropped, duplicated or
  edited line fails the step. Isolation is unchanged: the module default is MainActor, so an
  extension member is MainActor as the class body is, and `nonisolated` keeps its keyword.
- **Observation is unchanged.** `@Observable` expands only the stored properties in the class body,
  and they all stay there with their `@ObservationIgnored` markings. The status icon's
  `withObservationTracking { (coordinator.isRecording, coordinator.isUploading) }` still registers
  on the same tracked storage; `isUploading` is a computed getter over the tracked `uploadingIDs`
  wherever that getter is declared.
- **Small steps.** Each file is one commit, each one builds and passes the suite, and the diff of
  each is moved blocks plus a reviewed list of access keywords. The review reads the list, not the
  3,100 moved lines.
- **It is what R2 needs.** GIF lands in `+Recording` and `+Upload`, the microphone in
  `+Recording`'s start path, Trim in a new `+Trim` file, and they rarely touch the same file. The
  dependency graph between areas becomes explicit: the widened-member list (3.3) is that graph, and
  an area that R2 wants as a real type can be cut from its file later as a local change.
- **It is not over-engineered.** About 100 net new lines (imports, extension wrappers, headers,
  group notes). No new types, no new indirection, no injected dependencies, no forwarders.

### The rejected alternative: owning types

The other design cut the coordinator into 17 classes under `TidyShot/App/Coordinator/`, each owning
its state, with strong references down a layered DAG and weak closures back up. It has real merits:
one owner per stored property, `removeRecord` talking to owners through verbs, a `DeletionStatus`
read-only protocol, and `EditorBridge`'s 16 init parameters as an honest picture of the editor's
coupling. It was rejected for this PR because:

- **It is not a move.** Every cross-type call in every moved body is rewritten (`deletingIDs` to
  `deletions.deletingIDs`, `startUpload(` to `upload.startUpload(`), ten new "bundling" methods
  (`clear`, `forget`, `register`, `cardReplacedByEditor`, `location(for:)`,
  `setVideoClipboardCount`, `claimClipboard`, …) replace consecutive lines of today's code, and
  about 350 lines of inits, stored `let`s and 42 forwarders are new. No mechanical check can prove
  that a pure move, so the behaviour argument rests on review of 18 steps.
- **It changes things the brief says not to change.** Five lazy collaborators become eager `let`s
  built in `init`; `[weak self]` and the one `[unowned self]` capture become captured leaves; two
  helpers move into `Notifier` and `Pasteboard`; the card action table becomes an implicitly
  unwrapped optional installed after `init`; two test files change for moved statics; the tracked
  `isRecording`, `isCapturing`, `lastCaptureURL` and three upload sets move to four new
  `@Observable` owners behind computed forwarders. Each is defensible, and no test covers the status
  icon or any of the wiring, so each is a risk with no net.
- **It is more than R2 needs.** R2 adds code inside recording, upload and a new trim area. It does
  not need `SaveFunnel`, `DeleteCoordinator` or `OverlayBridge` as types, and the one place it
  would gain from injected dependencies (testing `UploadCoordinator.handle` against a fake
  destination) is listed there as a later seam anyway.

### Why not a combination

The brief allowed extracting the clearly separable collaborators and using extension files for the
rest. The map was read for state that is self-contained enough to move into a type without
rewriting its callers. There is almost none: `latestCapture`/`latestCaptureArea` and `deletingIDs`
are leaves of 3 and 2 lines whose extraction rewrites 20 call sites to save nothing; drag-out owns
six variables but needs `saveAsSuggestion`, `downloadImage`, `overlay` and Copy File moving in with
it, for an area R2 does not touch; recording, where R2 adds the most, calls `finishSave`,
`makeDestination`, `uploadPayload`, `makeThumbnail`, `withCaptureLock`, `loadContent`, `selector`,
`covers`, `selfTimer`, the retained capture and `lastCaptureURL`, so a recording type would hold a
reference back to the coordinator and widen the same members, with a receiver rewrite on every
line that uses one. The file split puts recording in one file either way. If R2's own plan wants a
`Recording` type, `+Recording` is the exact cut and this spec's 3.3 is its dependency list.

## 3. Target layout

### 3.1 Files

All in `TidyShot/App/`. XcodeGen's `sources: - path: TidyShot` picks them up; the project is
gitignored, so every step runs `xcodegen generate`. Ranges are inclusive and include each member's
doc comments and attributes; within a file, members keep their original relative order. The seven
`// MARK:` lines (491, 950, 2088, 2339, 2503, 2714, 3369) are dropped: each file's name says what
its MARK said.

| File | Holds | Source lines at 3737262 | Lines |
|---|---|---|---|
| `AppCoordinator.swift` | Every stored property, grouped (3.2); `shared`; `permissionGranted`; `init`, `start`, `showPermissionWindow`, `handleURL`, `setDesktopIconsHidden`, `toggleDesktopIconsHidden`, `registerShortcuts`; `updateUploadActivity` (the `fileUploadIDs.didSet` target); quit: `holdsQuit`, `quitNeedsHold`, `reviewEditorsBeforeQuit`, `finishRecordingForQuit`, `quitPollInterval`; shared by capture and recording: `loadContent`, `withCaptureLock`; `urlCommandScreens`; `extension AppCoordinator: URLCommandTarget {}` | 1-8, 17-179, 193-297, 1703-1711, 2716-2719, 2726-2735, 3337-3367, 3371-3386, 3396-3424, 3432-3435 | ~430 |
| `AppCoordinator+Capture.swift` | The image capture entry points, `revealLastCapture`, `capture(_:excludingWindows:duringSelection:)`, `runScrolling`, `runSelection`, `copyText`, `runSelfTimer`, `captureAfterCountdown`, `areaResult`, `selectedAreaResult`, `frozenResult`, `cardWindows`, `display(under:in:)` | 299-489, 758-948, 3388-3394, 3426-3431 | ~400 |
| `AppCoordinator+Recording.swift` | `recordingPhase`, `recordingCountInSeconds`, `recordingShortcutAction`, `recordScreen`, `recordFullscreen`, `stopRecording`, `recordShortcutStarts`, `recordingCanStart`, `record`, `recordingHandOff`, `connectedDisplay`, `recordingDisplay`, `visibleFrame`, `recoverRecordings`, `endRecording`, `saveRecording`, `recordingBaseName`, `placeRecording`. Top level: `RecordingSaveMode`, `RecordingPhase`, `RecordingShortcutAction` | 183-191, 493-756, 1186-1311, 3437-3460 | ~430 |
| `AppCoordinator+Save.swift` | `save`, `withWindowBackground`, `notifyUnusableBackgroundImage`, `copyOnly`, `persist`, `SaveNotification`, `finishSave`, `writeFile`, `writePendingFile`, `keepOnClipboard`, `makeThumbnail` | 952-1184, 1322-1391 | ~310 |
| `AppCoordinator+Overlay.swift` | `showOverlay`, `overlayActions`, `overlayScreen`, `overlayDidClose`, `canRestoreClosedOverlay`, `restoreClosedOverlay`, `refreshOverlay`, `pushCardFlags` | 1393-1475, 2348-2363 | ~105 |
| `AppCoordinator+Upload.swift` | `UploadLane`, `isUploading`, `warnUploadNotConfiguredOnce`, `makeDestination`, `loadCredentials`, `storedCredentials`, `keychainReadFailure`, `destinationDidChange`, `makeLane`, `startUpload`, `fitsSingleUpload`, `refuseOversizedUpload`, `removeClopFile`, `clopIsRunning`, `optimisedForUpload`, `retryUpload`, `retryFailedUploads`, `retry`, `uploadPayload`, `cancelUpload`, `markFailed`, `handle(_:at:)`, `deleteOrphanedObject` | 9-15, 180, 1313-1320, 1477-1701, 1713-1825, 2212-2234, 2341-2346, 2365-2501 | ~530 |
| `AppCoordinator+RecordActions.swift` | The actions on a record from a card, a pin or a Recent Captures row: `copyLinkOrFile`, `copyFile`, `openCapture`, `copyLink`, `copyImage`, `saveAs`, `saveVideoCopy`, `copyVideo`, `saveCopy`, `askSaveAsTarget`, `imageData`, `uploadedFallback`, `downloadImage`, `downloadSource`, `reveal`, `afterMenuTracking`, `writeSaveAsCopy`, `performSaveAs`, `saveAsSuggestion`. Top level: `CopyImageError` | 1827-2086, 2867-2873, 3112-3156, 3471-3492 | ~340 |
| `AppCoordinator+Delete.swift` | `deleteCapture`, `notifyKept`, `deleteObjects`, `removeFromHistoryOnly`, `removeRecord`, `removePendingFile`, `confirmDelete`, `confirmRemoveFromHistory`, `removeFiles(ofPruned:)` | 2090-2210, 2236-2337 | ~230 |
| `AppCoordinator+DragOut.swift` | `dragCleanupDelay`, `prepareDragFile`, `prefetchDragFile`, `keepForDragOut`, `dragDidEnd`, `scheduleDragCleanup`, `dragCleanupStep`, `removeDragFolder`, `stageVideoDragFile`, `dropStaleDragFolder`. Top level: `DragCleanupStep` | 2505-2712, 3462-3469 | ~220 |
| `AppCoordinator+Editor.swift` | `hasUnsavedEditors`, `openEditor`, `loadAndPresentEditor`, `loadImage`, `openEditorAfterMenuTracking`, `presentEditor`, `editorActions`, `pushEditorState`, `observeSaveFolderForEditors`, `editorSave`, `applyLocalEdit`, `keepFailedEditOnClipboard`, `replaceThumbnail`, `editorSaveAs`, `editorUpload`, `refuseUpload`, `deleteSupersededObjects`, `replaceClipboardIfStillOriginal`, `editorCopy`, `editorDidClose` | 2721-2724, 2737-2791, 2875-2878, 2880-3110, 3158-3335 | ~480 |
| `AppCoordinator+Pins.swift` | `retainedCaptureID`, `hasPins`, `hasLockedPins`, `unlockPins`, `closePins`, `pin`, `pinScreen`, `pinActions`, `forgetLatestCapture` | 181-182, 2793-2865 | ~80 |

**Placements that differ from the map's areas**, each putting a member beside the state or the
callers it serves:
- `warnUploadNotConfiguredOnce` goes to `+Upload`: it guards the upload configuration, and
  `loadCredentials` calls it as `finishSave` does.
- `cancelUpload` goes to `+Upload`: it is lane bookkeeping (it removes the attempt token, clears the
  upload sets and awaits the lane's cancel), and Delete only calls it. R2's upload work (multipart,
  resume) changes it with the lanes.
- `afterMenuTracking`, `writeSaveAsCopy`, `performSaveAs` and `saveAsSuggestion` go to
  `+RecordActions`: the card, pin and drag code are their main callers; the editor calls them too.
- `withCaptureLock` and `loadContent` stay in `AppCoordinator.swift`, because image capture and
  recording share them. That keeps `isCapturing`'s setter and `permissionWindow` private.
- Quit stays in `AppCoordinator.swift` as lifecycle, next to `start`. That keeps `isQuitting`'s
  setter and `quitPollInterval` private.
- URL commands and the desktop-icon toggle stay as wiring. That keeps `urlCommands` and
  `urlCommandScreens` private.
- `updateUploadActivity` stays next to the `fileUploadIDs.didSet` that calls it. That keeps it and
  `uploadActivity` private.
- `retainedCaptureID` goes to `+Pins` (next to `forgetLatestCapture`), `isUploading` to `+Upload`
  and `recordingPhase` to `+Recording`.

**Imports.** Every file imports AppKit. `AppCoordinator.swift`, `+Capture` and `+Recording` also
import ScreenCaptureKit. `AppCoordinator.swift` (for `@Observable`) and `+Editor` (for
`withObservationTracking`, as CanvasView and EditorToolbar do) also import Observation.
KeyboardShortcuts is imported only in `AppCoordinator.swift`.

**Each new file is:** its imports; a one-line `//` header naming the area and saying its state is
declared in `AppCoordinator.swift`; `extension AppCoordinator {` … `}` with the members at their
original 4-space indent, one blank line between members; then any top-level types the area owns.

### 3.2 Stored state

All 55 stored properties stay in the class body, in the order below (the first step of the plan
regroups them). Each group opens with a `// MARK: <Area> state (AppCoordinator+<Area>.swift)`, and
where other files write the group's state a `//` line names them. Every property keeps its own doc
comment, attributes and default. Names and access only; this is not compilable Swift.

```
static let shared = AppCoordinator()

// MARK: Collaborators (lines 19-69 as they are)
let engine; let saveLocation; let settings; let history; let thumbnails; let pendingFiles; let dragFiles
let credentialStore; let notifier; private let permissionWindow; let overlay
lazy var selector; lazy var scrollCapture; private lazy var urlCommands; lazy var selfTimer
lazy var recorder; lazy var covers; private(set) lazy var thumbnailProvider

// MARK: Capture state (AppCoordinator+Capture.swift; the lock is withCaptureLock, below)
private(set) var isCapturing                    // only the lock writes it
var lastCaptureURL                              // set by +Save and +Recording, cleared by +Delete

// MARK: Recording state (AppCoordinator+Recording.swift)
var isRecording; var recordingCountIn; var recordingSavesInFlight
private(set) var isQuitting                     // set only by finishRecordingForQuit, below
var videoClipboardCounts                        // consumed by +Upload's .uploaded, cleared by +Delete

// MARK: Retained capture and pins (AppCoordinator+Pins.swift)
var latestCapture; var latestCaptureArea        // set by +Save and +Overlay, cleared by +Recording; read by +Editor
lazy var pins; var pinningIDs

// MARK: Overlay state (AppCoordinator+Overlay.swift)
var closedOverlays                              // +Editor records an editor-opened close
var isRestoring

// MARK: Upload state (AppCoordinator+Upload.swift)
// +Delete's teardown clears optimizingVideoIDs, fileUploadIDs and linkNotCopiedIDs; +Overlay reads
// the two flag sets; +Editor reads queue?.location.
var queue; var drainingQueues; let clopOptimiser; var optimisingIDs; var clopWaitsPerLane
var optimizingVideoIDs; var clopResults; var fileUploadIDs { didSet }; private var uploadActivity
var warnedUploadNotConfigured; var postedCacheNote; var uploadingIDs; var linkNotCopiedIDs

// MARK: Delete state (AppCoordinator+Delete.swift)
var deletingIDs                                 // read by +Overlay, +Upload, +Editor and +Pins, also after their awaits

// MARK: Drag-out state (AppCoordinator+DragOut.swift)
// +RecordActions' Copy File writes dragCleanups and copyFileCounts; +Delete's prune clears copyFileCounts.
var dragGenerations; var dragStageSeqs; var dragCleanups; var prefetchingDragIDs; var stagingVideoIDs
var copyFileCounts

// MARK: Editor state (AppCoordinator+Editor.swift)
var openingEditorIDs
var clipboardOwner                              // also set by +Save when a capture goes on the clipboard
var editors                                     // read by the quit, below
var isObservingSaveFolder
```

- **Initialiser order.** Stored defaults run in declaration order before `init`'s body. Eight of
  them create objects or read singletons: `engine`, `saveLocation`, `settings`, `credentialStore`,
  `notifier`, `permissionWindow`, `overlay` (19-31, untouched) and `clopOptimiser` (79, inside the
  upload block, which stays after them). Every default that moves is `nil`, `false`, `0`, an empty
  collection or `ClosedOverlays()` (a struct whose only state is `ids = []`), or the property is
  `lazy`. The regroup therefore changes nothing that runs.
- **Tracked set.** The six stored vars without `@ObservationIgnored` (`isCapturing`, `isRecording`,
  `lastCaptureURL`, `optimizingVideoIDs`, `uploadingIDs`, `linkNotCopiedIDs`) keep that marking by
  staying where they are declared. The only live observer is `StatusMenuController.updateIcon`.
- **Not done: a state struct per area** (`var upload = UploadState()`). Every access site would
  change (`dragGenerations` to `drag.generations`), so the move could not be checked, and a tracked
  set inside a struct would notify on every write to the struct.

### 3.3 Access changes: 76, all to internal

Each change is the removal of one `private ` or `private(set) ` token on a declaration line.
Nothing narrows, nothing becomes `fileprivate`, and no name changes. "Used from" names the files
whose code uses the member in the final layout; the plan assigns each row to the step that first
makes it cross-file.

**Stored properties, `private` to internal (32).** Each one stays in the class body and is read or
written from another file.

| Property (line) | Used from |
|---|---|
| `notifier` (29) | every file but `+Overlay` directly; `+Capture`, `+Recording`, `+Save`, `+Upload`, `+RecordActions`, `+Delete`, `+Editor`, `+Pins` |
| `overlay` (31) | `+Overlay`, `+Capture`, `+DragOut`, `+RecordActions`, `+Delete`, `+Editor` |
| `selector` (32), `selfTimer` (41), `covers` (54) | `+Capture`, `+Recording` |
| `scrollCapture` (33) | `+Capture` |
| `recorder` (45), `recordingCountIn` (158) | `+Recording` |
| `queue` (72) | `+Upload`, `+Editor` (`queue?.location`) |
| `drainingQueues` (76), `clopOptimiser` (79), `optimisingIDs` (84), `clopWaitsPerLane` (87), `clopResults` (93), `warnedUploadNotConfigured` (104), `postedCacheNote` (125) | `+Upload` |
| `fileUploadIDs` (96) | `+Upload`, `+Delete` |
| `deletingIDs` (102) | `+Delete`, `+Overlay`, `+Upload`, `+Editor`, `+Pins` |
| `latestCapture` (110) | `+Pins`, `+Save`, `+Recording`, `+Overlay`, `+Editor` |
| `latestCaptureArea` (113) | `+Pins`, `+Save`, `+Recording` |
| `pins` (115) | `+Pins`, `+Delete` |
| `pinningIDs` (116) | `+Pins` |
| `closedOverlays` (118) | `+Overlay`, `+Editor` |
| `isRestoring` (121) | `+Overlay` |
| `openingEditorIDs` (123), `editors` (2717), `isObservingSaveFolder` (2719) | `+Editor` (`editors` also by the quit in the root) |
| `clipboardOwner` (129) | `+Editor`, `+Save` |
| `dragGenerations` (132), `dragStageSeqs` (135), `prefetchingDragIDs` (140) | `+DragOut` |
| `dragCleanups` (138) | `+DragOut`, `+RecordActions` |

**`private(set)` to internal (9).** Their getters were already internal; another file writes them.

| Property (line) | Written from |
|---|---|
| `optimizingVideoIDs` (90) | `+Upload`, `+Delete` |
| `stagingVideoIDs` (144) | `+DragOut` |
| `copyFileCounts` (148) | `+DragOut`, `+RecordActions`, `+Delete` |
| `isRecording` (153), `recordingSavesInFlight` (161) | `+Recording` |
| `lastCaptureURL` (167) | `+Save`, `+Recording`, `+Delete` |
| `uploadingIDs` (169) | `+Upload` |
| `linkNotCopiedIDs` (172) | `+Upload`, `+Delete` |
| `videoClipboardCounts` (177) | `+Recording`, `+Upload`, `+Delete` |

**Nested types, `private` to internal (2).** `UploadLane` (11), declared in `+Upload`, is the type
of `queue` and `drainingQueues` in the class body. `SaveNotification` (1131), declared in `+Save`,
is built by `+Recording`'s `saveRecording` and is a parameter of the now-internal `finishSave`.

**Methods, `private` to internal (33).**

| Method (line) | Home | Called from |
|---|---|---|
| `finishSave` (1147), `makeThumbnail` (1370) | `+Save` | `+Recording` |
| `keepOnClipboard` (1358) | `+Save` | `+Editor` |
| `warnUploadNotConfiguredOnce` (1316) | `+Upload` | `+Save` |
| `recoverRecordings` (713) | `+Recording` | root (`start`) |
| `recordingBaseName` (1278) | `+Recording` | `+Upload` |
| `showOverlay` (1395) | `+Overlay` | `+Save` |
| `overlayDidClose` (1441) | `+Overlay` | root (`init`) |
| `refreshOverlay` (2351) | `+Overlay` | `+Upload`, `+Editor` |
| `loadCredentials` (1487) | `+Upload` | `+RecordActions` |
| `storedCredentials` (1499), `keychainReadFailure` (1507) | `+Upload` | `+Delete` |
| `startUpload` (1548) | `+Upload` | `+Save`, `+Editor` |
| `cancelUpload` (2215) | `+Upload` | `+Delete` |
| `markFailed` (2341) | `+Upload` | `+Save` |
| `imageData` (2025) | `+RecordActions` | `+Editor` |
| `downloadImage` (2064) | `+RecordActions` | `+DragOut` |
| `afterMenuTracking` (2869) | `+RecordActions` | `+Overlay`, `+Pins`, `+Editor` |
| `writeSaveAsCopy` (3117) | `+RecordActions` | `+Editor` |
| `saveAsSuggestion` (3147) | `+RecordActions` | `+DragOut`, `+Editor` |
| `deleteObjects` (2175) | `+Delete` | `+Editor` |
| `removePendingFile` (2263) | `+Delete` | `+Upload` |
| `removeFiles(ofPruned:)` (2319) | `+Delete` | root (`init`) |
| `keepForDragOut` (2594) | `+DragOut` | `+Upload` |
| `dragDidEnd` (2613) | `+DragOut` | `+Overlay` |
| `scheduleDragCleanup` (2623) | `+DragOut` | `+Overlay`, `+RecordActions` |
| `removeDragFolder` (2650) | `+DragOut` | `+Delete`, `+Editor` |
| `stageVideoDragFile` (2668) | `+DragOut` | `+RecordActions` |
| `forgetLatestCapture` (2860) | `+Pins` | `+Overlay`, `+Delete` |
| `openEditorAfterMenuTracking` (2876) | `+Editor` | `+Overlay`, `+Pins` |
| `pushEditorState` (2934) | `+Editor` | `+Overlay`, `+Delete` |
| `deleteSupersededObjects` (3255) | `+Editor` | `+Upload` |
| `withCaptureLock` (3413) | root | `+Capture`, `+Recording` |

That accounts for 76 of the 151 `private`/`private(set)` tokens at 3737262. The list was produced by
reference analysis over every member body (a scan of each private name against the final layout,
with comment and local-name collisions removed by hand), and the compiler confirms it at every step.

### 3.4 Stays private (75)

- `AppCoordinator.swift`: `permissionWindow`, `urlCommands`, `uploadActivity` and the setters of
  `isCapturing`, `isQuitting` and `thumbnailProvider`; `registerShortcuts`, `updateUploadActivity`,
  `urlCommandScreens`, `quitPollInterval`.
- `+Capture`: `runScrolling`, `runSelection`, `copyText`, `runSelfTimer`, `captureAfterCountdown`,
  `areaResult`, `selectedAreaResult`, `frozenResult`, `cardWindows`.
- `+Recording`: `recordingCountInSeconds`, `recordShortcutStarts`, `recordingCanStart`, `record`,
  `recordingHandOff`, `connectedDisplay`, `recordingDisplay`, `visibleFrame`, `endRecording`,
  `placeRecording`.
- `+Save`: `withWindowBackground`, `copyOnly`, `persist`, `writeFile`, `writePendingFile`.
- `+Overlay`: `overlayActions`, `overlayScreen`, `pushCardFlags`.
- `+Upload`: `makeLane`, `fitsSingleUpload`, `refuseOversizedUpload`, `removeClopFile`,
  `clopIsRunning`, `optimisedForUpload`, `retry`, `handle`, `deleteOrphanedObject`.
- `+RecordActions`: `copyVideo`, `saveCopy`, `askSaveAsTarget`, `uploadedFallback`,
  `downloadSource`, `performSaveAs`.
- `+Delete`: `notifyKept`, `removeFromHistoryOnly`, `removeRecord`, `confirmDelete`,
  `confirmRemoveFromHistory`.
- `+DragOut`: `prefetchDragFile`, `dropStaleDragFolder`.
- `+Editor`: `loadAndPresentEditor`, `presentEditor`, `editorActions`, `observeSaveFolderForEditors`,
  `editorSave`, `applyLocalEdit`, `keepFailedEditOnClipboard`, `replaceThumbnail`, `editorSaveAs`,
  `editorUpload`, `refuseUpload`, `replaceClipboardIfStillOriginal`, `editorCopy`, `editorDidClose`.
- `+Pins`: `pinScreen`, `pinActions`.

**Not narrowed.** `capture(_:…)`, `saveRecording`, `saveVideoCopy`, `loadImage`, `uploadPayload`,
`dragCleanupDelay` and the collaborators `engine`, `pendingFiles`, `dragFiles`, `thumbnails` are
internal with no caller outside the coordinator. They could become private or file-local. They are
left so that every diff is a pure move.

### 3.5 External surface, unchanged

AppDelegate (`shared`, `handleURL`, `start`, `quitNeedsHold`, `reviewEditorsBeforeQuit`,
`finishRecordingForQuit`), StatusMenuController (observes `isRecording` and `isUploading`; reads
`isCapturing`, `permissionGranted`, `canRestoreClosedOverlay`, `history`, `lastCaptureURL`,
`settings`, `hasPins`, `hasLockedPins`; calls 18 methods), RecentCapturesMenu (`history`,
`saveLocation`, `retainedCaptureID`, `optimizingVideoIDs`, `thumbnailProvider`, `copyLinkOrFile`,
`openEditor`, `copyLink`, `copyImage`, `copyFile`, `deleteCapture`), the settings views
(`settings`, `credentialStore`, `destinationDidChange`, `makeDestination`, `saveLocation`,
`notifyUnusableBackgroundImage`) and `URLCommandTarget` (whose requirements are `isCapturing` and
the `+Capture`, `+Overlay` and root entry points with their exact signatures) see the same members
with the same signatures and defaults. No file outside `TidyShot/App/AppCoordinator*.swift` changes.

## 4. Rules every step follows

1. **No behaviour change.** A member's body moves verbatim: the same lines, in the same order, with
   the same literals, `await`s, `Task`s, `defer`s and `[weak self]` captures. No string a user sees
   changes, no `await` is added, removed or reordered, no default argument changes.
2. **Only the access keyword may differ**, and only by removing `private ` or `private(set) ` from a
   row in 3.3. Nothing is narrowed, nothing becomes `fileprivate`, and a row is added to the list
   only after review, never by fixing a compile error in passing.
3. **Stored properties stay in the class body** in `AppCoordinator.swift`, with their
   `@ObservationIgnored` markings, doc comments and defaults. The eight side-effecting defaults keep
   their relative order. Static stored properties and nested types move with their area.
4. **MainActor is kept.** No `nonisolated` is added or removed; the module default makes every
   extension member MainActor as the class body is.
5. **One save, upload and delete path.** `save`/`finishSave`, `startUpload` and
   `deleteCapture`/`removeRecord` each still exist exactly once, and no new caller of any of them
   appears. Widening a member grants no one outside the coordinator a new entry point: code outside
   `TidyShot/App/AppCoordinator*.swift` keeps to the surface in 3.5.
6. **Tests are unchanged.** The three statics tests reach (`recordingShortcutAction`, `holdsQuit`,
   `dragCleanupStep`) stay on `AppCoordinator` under the same names, and the enums they use stay
   top-level with the same names and cases. No test file changes; the suite reads
   `Test run with 1272 tests in 131 suites passed` after every step.
7. **Each step is one file** (the regroup and the docs excepted), builds, passes the suite, passes
   the pure-move check (section 5), and is one commit with no attribution lines. Nothing is pushed
   from inside the plan.
8. **No "while I'm here" fixes.** The three quirks found (section 8) are left as they are.

## 5. Checks

Run after every step, from the repo root:

```bash
xcodegen generate && xcodebuild test -project TidyShot.xcodeproj -scheme TidyShot -destination 'platform=macOS' -derivedDataPath .build 2>&1 | grep -E "Test run with|error:|TEST"
```
expects `Test run with 1272 tests in 131 suites passed`.

**The pure-move check.** The family's lines, less imports, `extension AppCoordinator {` and
column-0 `}` lines, `//` comment lines at indent 0 or 4 (file headers, MARKs and group notes) and
blank lines, with every `private ` and `private(set) ` token removed, sorted, must equal the base
file treated the same way:

```bash
norm() { grep -vE '^(import |extension AppCoordinator \{$|\}$|(    )?// )' | sed -E 's/(^|[[:space:]])private(\(set\))? /\1/' | grep -v '^[[:space:]]*$' | sort; }
diff <(git show 3737262:TidyShot/App/AppCoordinator.swift | norm) <(cat TidyShot/App/AppCoordinator*.swift | norm) && echo "pure move"
```
It prints `pure move` for the untouched file and names the line for an edited, dropped or duplicated
one (tested on a mutated copy). It does not see a reorder inside a body; the diff review does.

**The access count.** `cat TidyShot/App/AppCoordinator*.swift | grep -cE '(^|[[:space:]])private(\(set\))? '`
is 151 at the base and falls by exactly the step's row count; it is 75 at the end.

**The diff review.** `git diff HEAD~1 --color-moved=dimmed-zebra --color-moved-ws=allow-indentation-change -- TidyShot/App`
shows moved blocks, the step's access edits, the new file's imports, header and wrapper lines, and
the removed MARK lines, and nothing else. A reviewer checks that moved blocks are whole and the
enum cases are in their order.

**The initialiser order** (regroup step):
`grep -nE '^    (private )?let (engine|saveLocation|settings|credentialStore|notifier|permissionWindow|overlay|clopOptimiser)\b' TidyShot/App/AppCoordinator.swift`
lists the eight in that order.

**A hand pass by Tim at the end**, as in every phase, on a checklist of about fifteen items that each
exercise one file's wiring (the plan's last task writes it). No test creates an `AppCoordinator`,
so a green suite says nothing about the wiring; the checks above carry the move argument, and the
hand pass is the net under the observation path and the callbacks wired in `init`.

## 6. What it does for R2, and the conventions R2 follows

R2's settled answers: one MP4/GIF format setting; a GIF that is not blurry (R2: TidyShot's own
encoder with no Clop, no audio, with a soft length warning); the microphone off by default with an
input choice, silence when muted, mixed with system audio; an optional Trim on the card and in Recent
Captures; no pause.

- **GIF.** `+Recording`: the encode in `saveRecording`, between the recorder's file and
  `placeRecording`, with the GIF's media kind and poster (R2: the conversion runs in `endRecording`'s
  `.keep` branch, `makeGIF`, and every path ends in one `saveRecording` call). `+Upload`: `startUpload`
  already takes the content type and extension from `record.mediaKind`, and (R2) a GIF never goes to
  Clop (`isSentToClop`). `+RecordActions`: the Save As panel's type, and what Copy Image and Copy File
  do for a GIF. The settings and the warning are outside the coordinator.
- **Microphone.** The permission check and its notice on `+Recording`'s start path
  (`recordingCanStart`, `recordingHandOff`). RecordingConfiguration, the driver, the settings, the
  entitlement and the usage string are outside the coordinator.
- **Trim.** A new `AppCoordinator+Trim.swift`, a second editor-like area, with a `Trim state` group
  in the class body for its window registry; a `trim:` closure in `overlayActions`; a new internal
  entry point for RecentCapturesMenu; two lines in `removeRecord` and `removeFiles` to close a trim
  window. It reuses members that are internal after the split: `history`, `pendingFiles`,
  `saveLocation`, `makeThumbnail`, `removeDragFolder`, `refreshOverlay`, `startUpload(fixedKey:)`,
  `deletingIDs`, `notifier`, `thumbnailProvider`; it will likely need `replaceThumbnail`
  (`+Editor`, private), a reviewed one-word change. `quitNeedsHold` changes only if Trim can hold
  unsaved work.
  (R2, as planned: the in-progress marker `trimmingIDs` is read by `+Upload`'s gates, which refuse
  Retry, Retry Failed Uploads and `startUpload` while a record is being trimmed, and by `+Delete`'s
  `deleteCapture`, which refuses before its alert. The two members widened are `replaceThumbnail`
  (`+Editor`) and `downloadSource` (`+RecordActions`), each by dropping `private`. The new entry points
  for code outside the family are `trimCapture(recordID:)`, `uploadTrimmed(recordID:)` and
  `trimMenuState(for:)`. Built so far: the marker, its gates, `trimMenuState(for:)` and the two
  widenings; the pass, the window and the wiring are held, see the R2 design's built notes. The
  surface check's list of widened members takes both names.)
- **Mute.** (R2.) `+Recording`: the mute ladder at the end of a recording (`muteAndSave`, between the
  recorder's file and `saveRecording`, inside `recordingSavesInFlight`) and in `recoverRecordings`,
  both through `RecordingMute.resolve`. `saveRecording` takes the ladder's `unmutedIntervals`, which
  make its target `pending/` before any folder is chosen. The `Sound not muted` gates are
  `CaptureRecord.uploadBlockedReason`, read by `+Upload` (`retry`, `retryFailedUploads`,
  `startUpload`), `+RecordActions` (`copyFile`, `copyLinkOrFile`'s file branch, `saveAs`) and
  `+DragOut` (`prepareDragFile`). Its state is the controller's, and `muteLag(for:)` is a private
  member of `+Recording`.
- **Parallel work.** GIF (`+Recording`, `+Upload`), the microphone (`+Recording`) and Trim
  (`+Trim`, `+Overlay`, `+Delete`) can be built on separate branches that rarely touch the same file.

**What it does not buy.** The coordinator is still never instantiated in tests. Trim adds to the
teardown hub (`removeRecord`, `removeFiles`) and to `refreshOverlay`'s fan-out. R2's branching still
belongs in pure, tested helpers, as `RecordingSavePlan` and `EditorUploadPlan` are.

**Conventions**, written into the screenshot design's section 5 by the plan's last task:
- New stored state goes in the class body in `AppCoordinator.swift`, under its area's group, with a
  `//` line naming any other file that writes it.
- New members start `private` in their area's file. Widening one is a reviewed decision, listed in
  the PR.
- A new area gets a new `AppCoordinator+<Area>.swift`.
- Outside `TidyShot/App/AppCoordinator*.swift`, code uses only the surface in 3.5 and new entry
  points made for it. A review that touches the coordinator greps outside the family for every
  member 3.3 widened from `private` behind `coordinator.`, `AppCoordinator.shared.`,
  `AppCoordinator.` and `$0.` (RecentCapturesMenu's `afterMenusClose` closures), and for any write
  to the nine widened from `private(set)` on any receiver (outside reads of `isRecording`,
  `lastCaptureURL` and `optimizingVideoIDs` are part of 3.5). The plan's Task 7 has the command.

## 7. Risks

| Risk | Guard |
|---|---|
| A body changes in transit: a line dropped, duplicated, edited or reordered, or a fix made in passing | The pure-move check (every line, as a multiset) and the color-moved diff (order). Rule 8. |
| The order of the eight side-effecting stored defaults changes in the regroup | They are not moved relative to each other; the grep in section 5 checks it. Every other default is pure or lazy. |
| The tracked set, or the status icon's updates, change | No stored property leaves the class body or loses `@ObservationIgnored`; the pure-move check compares declaration lines. The hand pass checks the upload arrow and `record.circle`. |
| A reference resolves to a different declaration after the move | It cannot: a body sees a subset of what it saw, and every cross-file target is widened, so a reference finds its original declaration or fails to compile. The only overloaded base names (`captureArea`, `captureText`) are already internal. |
| A missed widening | A compile error; it cannot pass silently. |
| A needless widening | Each row in 3.3 names its callers; a reviewer checks one exists. The access count must fall by exactly the step's rows. |
| Other app code starts using coordinator internals, now or in R2 | 76 members are visible to the module, and the compiler no longer stops `StatusMenuController` from writing `uploadingIDs`. The convention and the grep in section 6 replace that guard; they are weaker, and that is the cost of this design. |
| Isolation or concurrency changes | `nonisolated` moves verbatim; default isolation is the same in every file; bodies are identical, so no `Task`, `await` or `defer` moves. |
| An enum's cases reordered | The check compares a multiset, so it would miss this. Each enum moves whole and shows as one moved block; the reviewer checks it. |
| `xcodegen generate` forgotten after pulling | The build fails loudly. The PR says to run it. |
| Conflicts with in-flight work | No branch, local or remote, changes `AppCoordinator.swift` relative to `main` (28 refs checked 2026-10-23). Merge before R2's plan runs. If `main` moves first, redo the step's cut on the new base and run the check against the new merge base. |
| The specs go stale: 2.6 says the editor bridge must live in `AppCoordinator.swift` | The plan's last task rewrites it and adds the file map to section 5. |
| Blame continuity | `git blame -C -C -w` or `git log -L` follows lines into the new files. Noted in the PR. |

## 8. Found, not touched

Each changes behaviour, so each needs Tim's word and its own PR:
- `removeFiles(ofPruned:)` clears `copyFileCounts` and keeps the drag folder, while `removeRecord`
  removes the drag folder (which clears the count); the two teardowns have drifted.
- `refreshOverlay` also pushes the editor's state, so its name undersells it.
- `afterMenuTracking` duplicates `RecentCapturesMenu.afterMenusClose`.

## 9. Built

Built 2026-10-23 on `coordinator-split`, cut from `main` at 3737262: the design and plan (04b24e8), the
state regroup (16dca78) and ten file moves, one commit each (`+Pins` 5d26f7c, `+Overlay` a87c046,
`+DragOut` 50e42d6, `+RecordActions` eaaa324, `+Delete` 6be482c, `+Upload` d91b3ca, `+Editor` 3c5d3a2,
`+Save` 874fe0a, `+Recording` 31d68ef, `+Capture` 3111452), then this close-out. Nothing is pushed.

- **Suite.** `Test run with 1272 tests in 131 suites passed` after every commit and again before the
  close-out, and `xcodebuild -configuration Release` builds. No test, `project.yml` or source file
  outside `TidyShot/App/AppCoordinator*.swift` changed (`git diff --name-only 3737262 HEAD`).
- **Line counts** (`wc -l TidyShot/App/AppCoordinator*.swift`; the base is one file of 3,492 lines):

  | File | Design | Built |
  |---|---|---|
  | `AppCoordinator.swift` | ~430 | 417 |
  | `AppCoordinator+Capture.swift` | ~400 | 404 |
  | `AppCoordinator+Recording.swift` | ~430 | 432 |
  | `AppCoordinator+Save.swift` | ~310 | 309 |
  | `AppCoordinator+Overlay.swift` | ~105 | 105 |
  | `AppCoordinator+Upload.swift` | ~530 | 532 |
  | `AppCoordinator+RecordActions.swift` | ~340 | 342 |
  | `AppCoordinator+Delete.swift` | ~230 | 229 |
  | `AppCoordinator+DragOut.swift` | ~220 | 222 |
  | `AppCoordinator+Editor.swift` | ~480 | 482 |
  | `AppCoordinator+Pins.swift` | ~80 | 81 |
  | Total | ~3,600 | 3,555 |

  The family is 63 lines longer than the base (imports, wrappers, headers, group notes); section 2
  estimated about 100.
- **Access count.** 75, the base's 151 less the 76 rows of 3.3. Each step's count fell by exactly its
  rows, and the 75 left are the 3.4 list.
- **The pure-move check**, run on the final tree against 3737262:
  ```
  pure move
  ```
- **The surface check** (rule 5, the plan's Task 7 greps over the 67 members widened from `private` and
  the 9 from `private(set)`) prints nothing.
- **What differed from the plan.** No range had to move to another file and no row of 3.3 turned out
  needless or missing. The plan's line numbers shifted as earlier steps cut, so each cut was located by
  member name. Otherwise:
  - The class body's `//` notes naming another file that writes a group's state exist only under the
    Upload, Drag-out and Editor groups, as the plan listed; the sketch in 3.2 also has them for
    Capture, Recording, Retained capture and pins, Overlay and Delete.
  - `showOverlay` and `finishSave` have wrapped signatures. Removing `private ` left their continuation
    lines 8 columns further in than the declaration, which a pure move may not realign.
  - The `///` line above `extension AppCoordinator: URLCommandTarget {}` in the root still says the URL
    scheme's routes are the capture functions "above"; they are in `AppCoordinator+Capture.swift`. It
    is left as it is because the pure-move check counts `///` lines and no step listed it.
  - The root is 417 lines against about 430, and the family 3,555 against about 3,600 (table above).
  - The checklist's pruning item differs from the plan's sketch. A Recent Captures row has no Pin, and
    an uploaded upload-only capture has no file in `pending/` (the upload moves it to the drag folder
    or removes it), so the item pins from the card, ages the capture with the system clock and
    watches the thumbnail instead of the pending file.
- **Pending.** Tim's hand pass on `docs/testing/coordinator-split-manual-checklist.md` (16 items) is
  still to do; until then the wiring (the status icon's observation, `init`'s callbacks, the capture
  lock) is covered by the move argument alone.
