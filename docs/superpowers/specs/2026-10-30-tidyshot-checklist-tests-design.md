# TidyShot: Checklist Tests (Phase CT-1) Design

Date: 2026-10-30. Branch `checklist-tests` from `main` at e011d2f (the coordinator harness merged), on top of PR #28 (the `(suite)` marks, obsolete lines and corrections from the sweep).

## 1. Goal

A sweep classified every line of the 20 manual checklists in `docs/testing/` (1,405 lines) against the code at e011d2f. 148 lines pin a rule the suite can drive today, through the coordinator harness or the existing fakes, with no new seam. This phase turns those 148 lines into tests, marks each line `(suite: …)`, and changes nothing in `TidyShot/`.

The sweep's documents are committed beside this design in `docs/superpowers/notes/2026-10-30-checklist-sweep/`:
- `tests-A.md`: the test for every one of the 148 lines (name, suite file, entry point, fakes, assertions, effort, lines covered). It is this design's catalogue; the plan copies each test's code from it.
- `seams.md`: the 279 lines that need a seam, grouped under 41 seams, for the next phase (section 10).
- `marks-D.md` and `obsolete-E.md`: what PR #28 applied.

## 2. The tests

108 tests, 103 new and 5 extending an existing test, in 33 suite files, 10 of them new. By file (`tests-A.md` has each test in full):

| Suite file | New? | Tests | What they drive |
|---|---|---|---|
| `CoordinatorDeleteTests` | existing | 12 | Delete during an upload, a replace or a multipart upload; a storage failure's two alerts; a pre-Phase-3 record; delete after a bucket change; retention; bookkeeping |
| `CoordinatorUploadTests` | existing | 9 | the card's fraction; the clipboard rule after a copy elsewhere; a failed upload-only image's file and size; retry names; a taken key; Forget Credentials mid-upload; Upload as New; an interrupted replace; the cache note |
| `CoordinatorSaveTests` | new | 9 | `saveRecording` and `finishSave`: overlay off, upload-only with no destination or credentials, a recording's URL and the clipboard, quit mode, a marked recording, the notices' order, a GIF's size, no sender in a notice |
| `CoordinatorDragOutTests` | existing | 8 | Copy File's staged copy and its clean-up, a drag press after Copy File, a restored card's quiet download, resume data's signing time |
| `CoordinatorRecordActionsTests` | new | 7 | Copy URL / Copy File / Copy Image / Save As on a row |
| `SelectionViewTests` | new | 6 | Escape, Return, a click and a drag in a recording selection, Command keys, a typed width |
| `EditorModelTests` | existing | 10 | widths, colours, block size, select-all under a crop, duplicate, undo order, the spotlight's steps |
| `CanvasViewEventTests` | new | 5 | a letter mid-drag, re-editing a text, drawing under a crop, copy and paste between canvases, Space panning |
| `CoordinatorTrimTests` | new | 4 | Upload Trimmed: the stale note, a replace in parts, the cache note, refusals while trimming |
| `EditorBackgroundExportTests` | existing | 4 | undo steps, the shown canvas's size per aspect, tall content and the crop limit, the crop tool and the background |
| `CoordinatorRecordingTests` | existing | 3 | a record press during a capture, a GIF start's prompts, a second press while a prompt is up |
| `CanvasAccessibilityTests` | existing | 3 | elements follow edits, a press selects, a press refused under Crop or a drag |
| `CanvasFitTests` | existing | 3 | Space-drag ends the fit, the fit with a background, pointer to pixel with a background |
| `CoordinatorEditorTests` | new | 2 | `loadImage` from the file or the object; Annotate on a moved pre-Phase-3 file |
| `AppSettingsTests` | existing | 2 | a second instance keeps the folder and counter; recording defaults registered, not written |
| `CanvasToolTests` | existing | 2 | a selected text; a crop draft's minimum |
| `CounterTests` | existing | 2 | undo and redo of copies; a counter pasted across scales |
| `URLCommandHandlerTests` | existing | 2 | a display without a rect; a gate refusal ahead of the window selection |
| `CoordinatorCaptureTests` | new | 1 | a capture while the lock is held |
| `CoordinatorOverlayTests` | new | 1 | a relaunch forgets closed cards |
| `CoordinatorRecoveryTests` | existing | 1 (extend) | an adopted recording's `.none` and `fileIsTemporary` |
| `QuickAccessCardDragViewTests` | new | 1 | the download starts at the drag threshold |
| `RecentCapturesMenuTests` | new | 1 | an empty history's submenu |
| `ConnectionTesterTests` | existing | 1 (extend) | the two summaries |
| `ClickRingOverlayTests`, `EditorFlattenerTests`, `GIFFileSinkTests`, `QuickAccessModelTests`, `ScrollCaptureSessionTests`, `SelfTimerTests`, `TemplateExpanderTests`, `ThumbnailProviderTests`, `UploadQueueTests` | existing | 1 each | as `tests-A.md` says |

Each test's doc comment names the checklist line(s) it replaces, as the harness suites do (`/// phase-3-1 :52. …`). A test that covers a line in part says what stays by hand.

## 3. Harness additions (fakes only, no seam)

Four extensions to the test support, each named by the test that needs it in `tests-A.md`:
- `FakeDestination.download(key:)` takes a throw script (a `Copy Image` whose download fails).
- `FakeDestination.delete(key:)` takes a failure script (a remote delete that fails).
- `FakeNotifier.Call` carries the notice's subtitle.
- `FakeDestination` keeps a digest of each part's bytes (a part retry sends the bytes it first read; R4 call H, which D18 said needed a read counter: the digest is observed on the fake instead).

The `onCall` script `FakeDestination` already has covers R4 call G (a second Abort that fails after a first that answered 204). Calls G and H therefore leave Tim's R4 list: the harness design's section 8 and its built notes say "A to F"; this phase's built notes correct that to "A to H".

First uses the harness has not tried: `world.saveLocation.store(tempURL)` for the save-folder cases (harness D25 kept every recording in `pending/`); `recordingSavesInFlight = 1` before each `saveRecording` call.

## 4. Rules for the tests

- `TidyShot/` does not change. Every test drives an internal entry point; no `private` member opens. If a test cannot be written without a production change, it is reported, not forced: the line goes to the seam phase.
- No test touches `AppSettings.shared`, `NSPasteboard.general`, the Keychain, `UNUserNotificationCenter`, `NSWorkspace`, `NSScreen.screens`, the `tmp/` statics, a window ordered front, the screen, a camera, a microphone, a sound or the network. A window or panel a test builds and never orders front is allowed (`SelectionViewArmingTests`, `SelfTimerTests` do this).
- Every coordinator test passes an explicit `CaptureIntent(action:)` (`.standard` reads `AppSettings.shared`).
- The coordinator's `HistoryStore` prunes against the real `Date()`: retention tests stamp old records relative to `Date()`, not `world.date`.
- A `CanvasView` with no window snaps its transform to `NSScreen.main`'s scale: assert relations (shown against fit, before against after), not exact values.
- Held fakes are cancellable and single-entry; no test awaits directly on a call whose only way out is the behaviour under test (`eventually` and `TaskWatch`, as the harness suites do). Each test owns its temp folders and defaults suite; no `.serialized`.
- Test names are camelCase sentences; parameterized tests use `@Test(arguments:)`.
- The suite stays green after every task; the Release build is run at the end.

## 5. The marks

When a test lands, its lines get `(suite: SuiteName.testName)`, or `(suite, in part: …; by hand: <what>)`, appended as PR #28 did (end of the item's last line, wrapped at 120 columns). `tests-A.md`'s "Covers" line is the source. Three recording-r4 lines (236, 251, 291) carry an older in-part mark that the new test's mark replaces. Two items PR #28 left for this phase: phase-3:26's D-half mark (`CoordinatorDeleteTests.aPrePhase3UploadedCaptureIsDeletedWithNoStorageRequest`) and phase-3:31's corrected text from `obsolete-E.md`.

## 6. Settings, entitlements, packages

None. `project.yml` does not change; new test files are picked up by `xcodegen generate`.

## 7. Tests summary

2169 tests in 181 suites → 2272 in 191 (103 new test functions, 10 new suite files; `xcodebuild`'s line counts a parameterized test once, whatever its arguments).

## 8. Hand checks

None. This phase adds tests and marks; it changes no behaviour. The existing checklists, with their marks, are the record. No new checklist file.

## 9. The design's calls (for Tim to overrule)

1. Tests only, no seam: a line whose test would need a production change waits for the seam phase.
2. The four fake extensions in section 3 are test support, not seams.
3. A phase-3 line that duplicates a phase-3-1 line stays and gets the same mark; the checklists are not deduplicated.
4. In-part marks name what stays by hand on the line itself.
5. R4 calls G and H count as covered (section 3); the harness design's "A to F" becomes "A to H".
6. No new checklist file for this phase.

## 10. Deferred

- The 279 seam lines (`seams.md`): 41 seams, the first ten unlocking 173 lines. By lines unlocked: an editor presenter factory (73), the capture source (33), a value capture target (32), the Clop optimiser (23), a recording chrome factory (14), the card's Save As panel (13), a `RecordingLog` sink (12), the trim window (11), the screen list (11), the `tmp/` statics (12). Each is a phase or a slice of one, in that order unless Tim reorders.
- The 663 real-app lines stay Tim's.
- `catalogue.json` (the per-line classification with evidence) is scratch under `.superpowers/sdd/checklists/`, not committed.

## 11. Built notes

Built on `checklist-tests` from the plan `docs/superpowers/plans/2026-10-30-checklist-tests.md`. The suite reads
`2272 tests in 191 suites` (2169 in 181, plus 103 test functions: 10 new suite files and 23 existing ones). `TidyShot/`
and `project.yml` are unchanged.

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
- The marks name every test that pins a part of the line, the existing D ones too (D13). 148 lines are marked, 16 of
  them in part; recording-r2 351, part of a B line, has none (D15). phase-2 51 is marked in full on PR #28's corrected
  text (D14), and recording-r2 312, phase-4a 108, phase-6a 215 and recording-r4 330 are marked in part though
  tests-A counted them in full (D16). phase-3 31 has obsolete-E's corrected text, and phase-3 26's mark names its D
  half (D17).
- A call that only a regression would leave waiting is gated too: the two quits under a held prompt, and the saves
  that would open the folder panel if a recording were sent to the save folder by mistake (D31).
- R4's calls G and H are covered, so the harness design's section 8 and its built notes read A to H again.
- The quit-mode test (recording-r1 332) went through a fix round after review: it also saves once in quit mode with no
  folder stored, gated so a regression that opens the folder panel fails it, and it pins the file kept in `pending/`,
  the record's interrupted state for `.upload` and the clipboard rule. The quit itself, a folder panel open at the quit
  and `.upload`'s `Upload failed` and Retry after the relaunch stay by hand, so that line is marked in part and not in
  full as the plan's script had it (a fifth line besides D16's four).
- phase-7c 189 is marked in part after the whole-branch review: its test drags one Rectangle through the mapping every
  tool shares, so the redact, blur, pixelate, text and arrow, and the select, move and resize, stay by hand (a sixth).
- Six tests that already existed were extended or replaced in place, not added: `removingARecordClearsItsBookkeeping`
  (now also the latest capture and the card closing, phase-4a 53), `aFailureWithResumeDataKeepsItWithTheSigningTime`
  (the clock moves while the download is held), `anOrphanMP4IsAdoptedWithItsLength` (the coordinator-harness 52
  expectations), `aSelectedCounterShowsAndTakesTheColour`, `uploadFailedWhenPutIsRejected` and
  `aFileAtTheThresholdGoesMultipart` (the part digests). Every other task's blocks and anchors landed as the brief
  quoted them.

Hand checks: none (section 8). The checklists' marks are the record.
