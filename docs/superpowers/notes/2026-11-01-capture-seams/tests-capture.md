# CT-4 test catalogue: the capture seams (TARGET, CAPSRC)

The tests the two capture seams give the 68 lines of `lines-capture.md` (in this folder), in the form of
`docs/superpowers/notes/2026-10-31-small-seams/tests-small.md`: each test names its suite file, its entry point, how it builds its input, the fakes
that observe it, the sequence of calls, every assertion with the value read from the code, what stays by hand, its effort and every checklist line
it covers. It merges two catalogues that were written per seam (TARGET, CAPSRC) from the judge's decisions (`.superpowers/sdd/ct4/judge.md`,
scratch: the seams, the fakes and the rules each seam's tests follow; "the judge" below). The seams are the value `CaptureOrigin` with the internal
`save(_:from:intent:)` (TARGET; form (b), no `AppEnvironment` member, no fake) and `AppEnvironment.captureSource: any CaptureSource` with
`AppEnvironment.selector: any CaptureSelecting`, over the value types `CaptureDisplay`, `CaptureWindow` and `ScreenContent` (CAPSRC, built on TARGET). The
support is `TidyShotTests/Support/CaptureSamples.swift` (TARGET) and the fakes `FakeCaptureSource` (`world.source`) and `FakeSelector` (`world.selector`) in
`TidyShotTests/Support/CaptureSourceFakes.swift` (CAPSRC). None of it is in the tree at 5c2cc33: every code reference below is at 5c2cc33 (branch
`capture-seams`, working tree clean) and names the code as it stands before either seam, and a place a seam changes is said so. Checklist lines are named
by catalogue key with the current line in brackets, as `lines-capture.md` does. No Swift bodies; each entry gives every value a body needs.

Reading the note: section 3 (TARGET) and section 4 (CAPSRC) each keep their catalogue's own subsections, numbered `TARGET.n` and `CAPSRC.n`; "the judge, section n" is
`judge.md`. Within a seam the tests are grouped under their suite file, the new suite file first. A test is cited by its name; the short ids are `T1` to `T21` (TARGET)
and `C1` to `C9` (CAPSRC). Abbreviations are given at the head of each seam; those that appear in both (`+Save`, `+Upload`, `+Capture`, `+Recording`, `Coord`, `World`, `Fakes`) mean the same file.

## 1. Summary

28 tests, and one more if Tim takes the optional C9: 21 in the new `CoordinatorCaptureSaveTests` (TARGET) and 7 in the new `CoordinatorCaptureSourceTests`
(CAPSRC). One existing test, in `CoordinatorRecordingTests`, gets a step (C8) and adds no test; the optional C9 would add one to the existing
`SelectionViewArmingTests`. By seam: TARGET 21, CAPSRC 7 (plus C8 and the optional C9). Nine tests are parameterized and count once (TARGET: T4, T5, T8, T9,
T10, T11, T14, T15; CAPSRC: C1). Of the 68 lines: full 23, in part 21, deferred 24 (TARGET 2: `FOLDER`, `BGFILL`; CAPSRC 22: `TMPDIRS` 17, `STAGE` 3, `SCROLL` 1,
`COVERS` 1), obsolete or already covered 0. Four CT-2 marks are extended (phase-4a:119, phase-4a:120, phase-6b:118, phase-7c:187) and one earlier mark is
reworded with no test (recording-r4:217). What ran: TARGET's T1 to T4 built and green in the TARGET designer's scratch tree (since removed,
with the whole suite at 2356 tests); the design's review then built both diffs with T1, T2, C3 and C5 as this note gives them (clean; the four suites `Test
run with 6 tests in 4 suites passed`, the whole suite `Test run with 2356 tests in 197 suites passed`, Release `** BUILD SUCCEEDED **`; the design's
section 12). The other tests were read from the code and the suites' idioms. The expected suite line is in section 6.3.

### 1.1 TARGET (34 lines)

All the tests are in `CoordinatorCaptureSaveTests`.

| Line (key, current line) | Test | Verdict |
|---|---|---|
| coordinator-split:36 (:36) | T5 | part |
| coordinator-split:42 (:42) | T8 `.uploadOnly`; Retry half already D | part |
| phase-1:36 (:38) | T1 | full |
| phase-1:39 (:41) | none | deferred (`FOLDER`) |
| phase-1:45 (:48) | T6 | full |
| phase-2:25 (:40) | T7 | part |
| phase-2:30 (:47) | T2 | full |
| phase-2:32 (:51) | T5 | full |
| phase-2:33 (:52) | T8 `.upload` | part |
| phase-2:48 (:77) | T9 | part |
| phase-3:48 (:89) | T8 `.uploadOnly`; T21 retry leg; Retry half also D | full |
| phase-3:49 (:90) | T2 | full |
| phase-4a:119 (:210) | T8 `.upload` | part (extends CT-2 mark) |
| phase-4a:120 (:215) | T2 | part (extends CT-2 mark) |
| phase-5:179 (:191) | T10, T21 | full |
| phase-5:202 (:218) | T12 | full |
| phase-6b:66 (:81) | T10 | part |
| phase-6b:115 (:141) | T11 | full |
| phase-6b:116 (:142) | T5 (second argument) | full |
| phase-6b:117 (:143) | T4 | full |
| phase-6b:118 (:144) | T13 | part (extends CT-2 mark) |
| phase-7c:117 (:133) | none | deferred (`BGFILL`) |
| phase-7c:179 (:233) | T3 | part |
| phase-7c:182 (:236) | T14 | part |
| phase-7c:184 (:238) | T15 | full |
| phase-7c:185 (:239) | T15 (portrait case) | full |
| phase-7c:186 (:240) | T16 | full |
| phase-7c:187 (:241) | T17 | part (extends CT-2 mark) |
| phase-7c:188 (:244) | T18 | full |
| phase-7c:189 (:245) | T19 | part |
| phase-7c:190 (:246) | T20 | full |
| phase-7c:197 (:254) | T16; edit half already D | full |
| small-tweaks:13 (:16) | T5 | full |
| small-tweaks:16 (:22) | T10, T21 | full |

Changes against the judge's 1.7/1.8, all small, each argued in the entry named:

- T21 is new (above). phase-3:48 and phase-5:179 gain it as their retry leg; their verdicts do not change.
- T10 gains a `cardShows` argument. With a card on screen an upload-only capture's temporary file is not deleted after the upload:
  `keepForDragOut` moves it into the drag folder (+Upload:653, +DragOut:232-247) and only then does the record drop it. The
  judge's T10 ran only the no-card case (the suite's overlay is off), which is not what phase-5:179's text meets on a real
  run. The fourth argument set drives the card-showing branch with `world.cards.showing`. See T10.
- T9 takes a `cause` argument (a refused upload and an offline one) so that the line's "Wi-Fi off" has its own stand-in: three
  failed attempts and the transport message, besides the judge's 403.
- Every test that saves waits for the record's thumbnail before it ends (rule 8, below). It is a rule, not a test.

### 1.2 CAPSRC (34 lines)

C1 to C7 are in `CoordinatorCaptureSourceTests`, C8 in `CoordinatorRecordingTests`, C9 (optional) in `SelectionViewArmingTests`.

| Line (key, current line) | Test | Verdict | What stays, and whose |
|---|---|---|---|
| phase-5:78 (:78) | C6, C7 | part | the session starting on an accepted 100 pt area (`SCROLL`); the drag in the overlay (C) |
| phase-5:182 (:195) | none | deferred | `SCROLL` (held session outcome, +Capture.swift:128-139) |
| phase-6a:209 (:254) | C1 | full | |
| phase-6a:211 (:256) | C7, C6 | part | a scrolling session on the accepted area (`SCROLL`); a window click becoming the scrolling area is the overlay's own (`SELINT`); relaunch D |
| phase-6a:214 (:260) | C1 | full | |
| phase-6b:62 (:77) | C2 | part | selected and adjustable, and no rect when its display is gone (`placePreselected`, `SELINT`); the restore rule D |
| phase-6b:75 (:91) | none | deferred | `STAGE` (+Capture.swift:297-307); the menu's disabled items `STATUSMENU` |
| phase-6b:77 (:93) | none | deferred | `STAGE` (+Capture.swift:304); the tooltip D |
| phase-6b:79 (:95) | none | deferred | `STAGE`: the store at +Capture.swift:190 is followed by `runSelfTimer` with no stop |
| phase-6b:104 (:122) | C2 | part | the rect shown adjustable (`placePreselected`, `SELINT`); the rect's geometry D |
| phase-6b:105 (:123) | C2 (C9 if taken) | part | Return typed in another app as the overlay appears (C); arming by a W change or the lock toggle is C9, if Tim takes it |
| phase-6b:127 (:162) | C7 | part | the `capture-scrolling` half, stored only once the stitched image is saved (`SCROLL`) |
| phase-6b:159 (:210) | C3 | part | a self-timer counting (`STAGE`); a scrolling session before and after Start (`SCROLL`); the log text D |
| phase-6b:160 (:211) | C3 | full | |
| phase-7b:81 (:87) | C4 | full | |
| phase-7b:96 (:108) | none | deferred | `COVERS` |
| recording-r1:102 (:105) | none | deferred | `TMPDIRS` first (CAPSRC.1) |
| recording-r1:105 (:108) | none | deferred | `TMPDIRS`: both halves come after `recordingCanStart` (CAPSRC.1) |
| recording-r1:122 (:125) | none | deferred | `TMPDIRS`, `COVERS` |
| recording-r1:124 (:129) | none | deferred | `TMPDIRS` |
| recording-r1:196 (:207) | none | deferred | `TMPDIRS` |
| recording-r2:231 (:241) | none | deferred | `TMPDIRS` |
| recording-r2:236 (:246) | none | deferred | `TMPDIRS` |
| recording-r2:238 (:248) | none | deferred | `TMPDIRS` |
| recording-r2:351 (:386) | C8 | part | the disabled menu items (`STATUSMENU`); the recording that starts after the answer (`TMPDIRS`, `RECCHROME`); the URL command's dropped line text D |
| recording-r2:390 (:436) | none | deferred | `TMPDIRS` |
| recording-r2:397 (:443) | none | deferred | `TMPDIRS` |
| recording-r2:402 (:448) | none | deferred | `TMPDIRS` |
| recording-r2:407 (:455) | none | deferred | `TMPDIRS` |
| recording-r2:409 (:457) | none | deferred | `TMPDIRS` |
| recording-r2:605 (:669) | none | deferred | `TMPDIRS` |
| recording-r2:653 (:734) | none | deferred | `TMPDIRS`; stays ticked `[x]`, no mark change |
| recording-r3:276 (:285) | none | deferred | `TMPDIRS` |
| recording-r4:217 (:226) | none | deferred | `TMPDIRS` and the hand-off's `NSScreen` read; the CT-1 mark is rewritten (CAPSRC.1) |

Full (4): phase-6a:209, phase-6a:214, phase-6b:160, phase-7b:81. Part (8): phase-5:78, phase-6a:211, phase-6b:62,
phase-6b:104, phase-6b:105, phase-6b:127, phase-6b:159, recording-r2:351. Deferred (22): phase-5:182, phase-6b:75, :77, :79,
phase-7b:96, and the 17 recording lines. What stays, by kind: another seam's, in all 22 deferred lines (`TMPDIRS` 17,
`STAGE` 3, `SCROLL` 1, `COVERS` 1, each the first blocker) and in 7 of the 8 part lines (`SCROLL` in 4, `SELINT` in 3,
`STAGE` in 1, `STATUSMENU` with `TMPDIRS` in 1; two lines name two); by hand with no seam, in phase-6b:105 and in the C
parts (the drag, a key typed in another app) inside part lines. The marks are in CAPSRC.6; no deferred line gets a mark
(CT-3's practice, small-seams `LOG.8`).

### 1.3 Tests

| # | Test | Suite | Effort | Lines |
|---|---|---|---|---|
| T1 | `capturesUnderOneTemplateTakeTheNextFreeNameAlsoAfterARelaunch` | CoordinatorCaptureSaveTests (new) | M | phase-1:36 |
| T2 | `withAlsoCopyImageTheImageIsOnTheClipboardUntilTheUploadEndsThenTheLink` | CoordinatorCaptureSaveTests (new) | M | phase-2:30, phase-3:49, phase-4a:120 |
| T3 | `aWindowCaptureOnOceanIsComposedInTheFileTheClipboardAndTheUpload` | CoordinatorCaptureSaveTests (new) | M | phase-7c:179 |
| T4 | `copyOnlyPutsTheImageOnTheClipboardAndNothingElse(showNotification:)` | CoordinatorCaptureSaveTests (new) | M | phase-6b:117 |
| T5 | `aSaveAndCopyImageCaptureSavesCopiesAndAsksForNoDestination(intent:)` | CoordinatorCaptureSaveTests (new) | M | coordinator-split:36, phase-2:32, phase-6b:116, small-tweaks:13 |
| T6 | `theNextCaptureLandsInTheNewlyStoredFolder` | CoordinatorCaptureSaveTests (new) | S | phase-1:45 |
| T7 | `uploadAndCopyURLLeavesTheClipboardEmptyUntilTheLink` | CoordinatorCaptureSaveTests (new) | S | phase-2:25 |
| T8 | `withNoDestinationTwoCapturesCopyTheImageAndPostOneNotice(action:)` | CoordinatorCaptureSaveTests (new) | M | coordinator-split:42, phase-2:33, phase-3:48, phase-4a:119 |
| T9 | `aFailingUploadKeepsTheFileAndFailsTheRecord(cause:alsoCopy:)` | CoordinatorCaptureSaveTests (new) | M | phase-2:48 |
| T10 | `anUploadOnlyCaptureKeepsOnlyAPendingFileUntilItsUploaded(origin:cardShows:)` | CoordinatorCaptureSaveTests (new) | M | phase-5:179, phase-6b:66, small-tweaks:16 |
| T11 | `actionUploadSavesUploadsAndCopiesTheLinkUnderEitherSetting(setting:)` | CoordinatorCaptureSaveTests (new) | S | phase-6b:115 |
| T12 | `aTallCaptureKeepsItsFullPixelSizeInHistory` | CoordinatorCaptureSaveTests (new) | S | phase-5:202 |
| T13 | `annotateRunsTheActionThenOpensTheEditorOnTheNewCapture` | CoordinatorCaptureSaveTests (new) | M | phase-6b:118 |
| T14 | `areaAndFullscreenCapturesKeepThePlainImageWithTheBackgroundOn(origin:)` | CoordinatorCaptureSaveTests (new) | S | phase-7c:182 |
| T15 | `aWindowCanvasFollowsTheStyle(case:)` | CoordinatorCaptureSaveTests (new) | M | phase-7c:184, phase-7c:185 |
| T16 | `withTheBackgroundOffEveryCaptureIsPlainAtOnce` | CoordinatorCaptureSaveTests (new) | S | phase-7c:186, phase-7c:197 |
| T17 | `aComposedWindowCaptureOpensInTheEditorComposed` | CoordinatorCaptureSaveTests (new) | M | phase-7c:187 |
| T18 | `copyAndUploadOfAWindowCarryTheComposedImage` | CoordinatorCaptureSaveTests (new) | M | phase-7c:188 |
| T19 | `aWindowTooLargeForABackgroundIsSavedPlainWithOneLine` | CoordinatorCaptureSaveTests (new) | S | phase-7c:189 |
| T20 | `twoWindowCapturesAtOnceAreEachComposedInTheirOwnFile` | CoordinatorCaptureSaveTests (new) | L | phase-7c:190 |
| T21 | `anUploadOnlyCaptureThatFailsKeepsItsPendingFileUntilARetrySucceeds` | CoordinatorCaptureSaveTests (new) | L | phase-5:179, phase-3:48 (retry leg), small-tweaks:16 |
| C1 | `capturePreviousAreaWithNoUsableStoredAreaIsRefusedAndCapturesNothing(stored:)` | CoordinatorCaptureSourceTests (new) | S | phase-6a:209, phase-6a:214 |
| C2 | `allInOneOpensOnThePreviousAreaArmedOrAURLRectDisarmedAndEscapeStoresNothing` | CoordinatorCaptureSourceTests | S | phase-6b:62, :104, :105 |
| C3 | `aHeldSelectionOpensOneWindowAndDropsEveryOtherURLCaptureCommandWithoutReadingOrPosting` | CoordinatorCaptureSourceTests | M (held) | phase-6b:160, phase-6b:159 |
| C4 | `capturePreviousAreaAfterCaptureTextCapturesTheEarlierImageArea` | CoordinatorCaptureSourceTests | M (real Vision) | phase-7b:81 |
| C5 | `aFailedContentReadIsLoggedAndPostedAndAsksNothingMore` | CoordinatorCaptureSourceTests | S | none (the harness) |
| C6 | `aScrollingAreaUnder100PointsIsRefusedAndTheNextShortcutWorks` | CoordinatorCaptureSourceTests | S | phase-5:78, phase-6a:211 |
| C7 | `windowAndFullscreenCapturesLeaveThePreviousAreaAndAScrollingDragStoresIt` | CoordinatorCaptureSourceTests | M | phase-6a:211, phase-6b:127, phase-5:78 |
| C8 | step added to `aSecondRecordPressWhileTheMicrophonePromptIsUpAsksNothingAndAQuitStartsNothing` | CoordinatorRecordingTests (existing) | S | recording-r2:351 |
| C9 | `aWidthChangeOrTheLockToggleArmsADisarmedRect(control:)` (optional, no seam) | SelectionViewArmingTests (existing) | S | phase-6b:105 |

Effort over the 28 counted tests plus C8: S 12 (T6, T7, T11, T12, T14, T16, T19; C1, C2, C5, C6, C8), M 15 (T1, T2, T3, T4, T5, T8, T9, T10, T13, T15, T17, T18; C3, C4, C7), L 2 (T20, T21).

## 2. What holds for every test here

Each seam's rules are in its own subsection (`TARGET.2` from the judge's 1.6, `CAPSRC.2` from 2.7). What both share, from the phase's constraints
(the spec's section 5):

- A suite is `@Suite(.timeLimit(.minutes(1)))`, owns a `CoordinatorWorld` built in `init() throws` with `world.settings.showOverlay = false` (a card's screen is
  read from `NSScreen`, +Overlay.swift:9, :55-62), and each test opens with `defer { world.removeAll() }`. No `.serialized`. Own temp folders and defaults
  suite per test, never `AppSettings.shared`.
- Every save or capture entry point is called with an explicit `CaptureIntent`: the entry points' default `CaptureIntent.standard` reads `AppSettings.shared`
  (CaptureIntent.swift:42-44). A save either stores a folder first (`world.storeSaveFolder()`) or is copy-only or `.uploadOnly`, so `ensureFolder` never builds an
  `NSOpenPanel` (SaveLocation.swift:30-44).
- No test touches `NSPasteboard.general`, the Keychain, `UNUserNotificationCenter`, `NSWorkspace`, `NSRunningApplication`, `NSScreen.screens`, the `tmp/`
  statics, a window ordered front, a panel shown, the screen, a camera, a microphone, a sound, the real Clop app or the network. No test passes
  `recordingCanStart` (it makes the live `tmp/Recording`, +Recording.swift:213, :356).
- A held fake is cancellable and single-entry. A held call is never awaited directly: the test runs it in a `Task`, gates with `eventually` and
  `TaskWatch`, and cancels or releases it in a `defer` declared right after `defer { world.removeAll() }` (so it runs first). A call that nothing holds
  (most entries here, as in `CoordinatorSaveTests`) is awaited directly. `HistoryStore` prunes on the real `Date()`.
- A TARGET test that saves a record waits for its thumbnail before it ends (TARGET.2 rule 8), so a late write cannot recreate a folder in the removed root.

### 2.1 What the merge changed

- Counts. TARGET has 21 tests: the judge's twenty (1.7) plus T21, split out of the judge's T10 (its second-save leg, a failing upload and a retry, is a
  different path from T10's held success). CAPSRC has 7 new tests, not 8: the catalogue's tests 3 and 8 are merged (below). Line verdicts: TARGET 19 full, 13 part,
  2 deferred as the judge's 1.8; CAPSRC 4 full, 8 part, 22 deferred, where the judge had 4, 7, 23 (recording-r2:351 moves from deferred to part, CAPSRC.7 item 1).
- **Merged: C3** (the catalogue's tests 3 and 8). Both pin one rule: a URL capture command that arrives while a selection is open is dropped, reads nothing and
  posts nothing (URLCommandHandler.swift:154-157, `captureRefusal` is `.captureRunning` while `isCapturing`, AppCoordinator.swift:557). They differed only in which
  commands follow the held one: test 3 two more `capture-window` URLs (phase-6b:160), test 8 `capture-fullscreen`, `capture-area` and `capture-scrolling` (phase-6b:159).
  C3 holds one `capture-window` and sends the other five behind it, with `urlCommandsAllowSilent` on (test 8's requirement), and lists both lines. The held
  selection is a window one, as line 160's is; the drop reads the lock, not the mode. C3 asserts the union of the two tests' values.
- Looked at and not merged, because each pins a different branch: C6 and C7 both touch the 100 pt rule (C6 the refusal below it and the free lock, C7 acceptance at
  exactly 100 and the store before the stop at `live`); T8 `.uploadOnly`, T10 and T21 all leave an upload-only capture (T8 with no destination so no upload starts, T10 a held
  success, T21 a failed attempt and a retry); T14 and T16 both save a plain area capture with the background on or off (T14 the origin-kind guard, T16 the setting read at
  each save); C4 and C7 step 4 both call `capturePreviousArea` (after `captureText`, and after a URL rect); T4 and C7 both copy-only (T4 the save's effects, C7 the
  captures it was handed).
- Names. All 29 new names (21 + 7 + C9) were looked up in `TidyShotTests/` at 5c2cc33 with grep: none exists, and no two are the same (C8 extends an existing test and has no new name). They follow the
  suites' naming (a sentence in camelCase, parameterized tests with their argument labels).
- Ids. TARGET keeps `T1` to `T21`. CAPSRC's catalogue numbered its tests 1 to 10; here they are `C1` to `C9` (old 1, 2, 4, 5, 6, 7 keep their order as C1, C2, C4, C5, C6, C7; old 3 and 8 are
  C3; old 9 is C8; old 10 is C9). References inside the CAPSRC text were renamed to match.
- Form. The CAPSRC catalogue's per-entry "Effort" lines are folded into the entry headings, as the TARGET entries have them.
- Order. CAPSRC is built on TARGET and merges after it. If Tim defers CAPSRC (the judge, section 4, call 1) section 4 and its 7 tests go; C8 goes with it, and C9 stays only if taken
  alone. The expected suite line is then 2373 in 196 (TARGET alone), 2374 with C9.

Calls for Tim that bear on the tests (the judge, section 4): (1) build CAPSRC in CT-4 or defer it; (2) take C9, which takes phase-6b:105 to its by-hand remainder only; (3) accept
C4's run of the real `TextRecognizer` (the first request after a restart can take about 24 s; inside the one-minute limit); (4) confirm the `live` handle on `CaptureDisplay` and `CaptureWindow`.

## 3. TARGET: the value capture target

The tests for the 34 TARGET lines of `lines-capture.md`. The seam, the support and the rules are the judge's (the judge, section 1): `CaptureOrigin`, the internal
`save(_ captured: ScaledImage, from: CaptureOrigin, intent:)` that `save(_:intent:)` forwards to, and `CaptureSamples`. What was run: T1 to T4 ran green in the TARGET designer's scratch tree, and the design's review built both diffs and
ran T1, T2, C3 and C5 (spec section 12); everything else is read from the code and the suites' idioms (TARGET.5 lists it).

Every code reference is at 5c2cc33 (branch `capture-seams`, clean), where the seam is not in the tree yet. File:line is the statement as it stands in
`TidyShot/App/AppCoordinator+Save.swift` and neighbours today; the judge's diff keeps every statement and only changes how the three target reads are spelled
(`result.target.displayID` and `.areaRect` become `origin.displayID` and `.areaRect`, `case .window = result.target` becomes `origin.isWindow`), so a line number below names the
same statement after the diff, shifted by at most the 9 lines the diff adds above `persist`. Abbreviations: `+Save` = `TidyShot/App/AppCoordinator+Save.swift`, `+Upload`, `+Editor`,
`+Overlay`, `+Delete`, `+DragOut` likewise; `World` = `TidyShotTests/Support/CoordinatorWorld.swift`; `Fakes` = `TidyShotTests/Support/CoordinatorFakes.swift`; `FD` =
`TidyShotTests/Support/FakeDestination.swift`; `Pixels` = `TidyShotTests/Support/EditorPixels.swift`; `Samples` = `TidyShotTests/Support/CaptureSamples.swift` (new, the judge 1.4).

### TARGET.1 Lines already covered, obsolete, or covered in part elsewhere

No line is obsolete: none carries an `(obsolete: ...)` mark (lines-capture.md "Counts"), and each line's text still names a
behaviour the code has (checked: the card's `Saved` label is still drawn, QuickAccessView.swift:284; `Reveal Last Capture` is
StatusMenuController.swift:120; the row text without a `Saved` word is RecentCaptureFormatting, already D). No line is wholly
covered by an existing test: no suite calls `save(_:intent:)` (a grep of TidyShotTests/ at 5c2cc33). Parts that an existing test pins, which the
entries below rely on and name:

- coordinator-split:42 and phase-3:48, the Retry half: `CoordinatorUploadTests.retryFailedUploadsSaysOnceWithoutCredentialsAndEnqueuesWithThem`
  (CoordinatorUploadTests.swift:434: two failed records, no credentials, exactly one `Upload not configured` with `Set up a
  destination in Settings > Upload, then retry.`, then both upload with credentials; the text is +Upload:500). The once-per-launch
  rule: `notConfiguredIsPostedOncePerCoordinator` (+Upload:26-31).
- phase-6b:115, :116, :117: the intent mapping, `CaptureIntentTests.uploadUploadsUnderEverySetting`,
  `.saveIsSaveAndCopyImageUnderEverySetting`, `.copyPutsTheImageOnTheClipboardOnly` (CaptureIntentTests.swift:6-51). T11, T5 and T4
  add the save that follows the intent.
- phase-7c:184, :185: the arithmetic, `BackgroundLayoutTests` and `.portraitContentInvertsTheRatio`. T15 adds that the save writes
  the layout's size.
- phase-7c:197: the editor half, `EditorBackgroundExportTests.noBackgroundExportsTheCaptureAsBefore`.
- small-tweaks:13: the row text, `RecentCaptureFormattingTests.detailIsTheTimeAndTheSize`, `.partsAreSeparatedByAMiddleDot`,
  `.sizeTextInUSEnglish`; the uploaded object's size, `CoordinatorUploadTests.aStoredUploadWhoseSourceMatchesResumes`.
- phase-4a:119, :120, phase-6b:118, phase-7c:187: the CT-2 tests named in their marks (TARGET.4).

### TARGET.2 What holds for every test here

The judge's rules (1.6) as written, with the exact values a body needs and one addition.

1. Suite: `@Suite(.timeLimit(.minutes(1)))` `struct CoordinatorCaptureSaveTests`; `init() throws` builds `world = try
   CoordinatorWorld()` and sets `world.settings.showOverlay = false` (a card's screen reads `NSScreen.screens`, +Overlay:9,
   :55-62; the same line as CoordinatorSaveTests.swift:16). Each test opens with `defer { world.removeAll() }`. No `.serialized`.
2. Every save passes an explicit `CaptureIntent` (the forwarder's `.standard` reads `AppSettings.shared`, CaptureIntent.swift:42-44;
   the tests call the three-argument entry, which has no default) and either stores a folder first (`world.storeSaveFolder()`,
   World:175-180, returns `<root>/Saved/`) or uses `copyOnly` or `.uploadOnly`, so `ensureFolder` never builds an `NSOpenPanel`
   (SaveLocation.swift:30-44, :64-67).
3. The one held fake is the destination's upload: `destination.state.withLock { $0.holdingUploadsRemaining = 1 }` before the
   save, `defer { destination.releaseUploads() }` declared right after `defer { world.removeAll() }` so it runs first,
   `try await eventually { destination.state.withLock { $0.heldUploads.count } == 1 }`, assert, `destination.releaseUploads()`,
   `try await eventually { isUploaded(coordinator, record.id) }` (FD:26, :28, :264; `eventually` is UploadQueueTests.swift:42-48,
   2 s). `destination` is `world.factory.standard`. The upload hold ranks after scripted failures and blocks (FD:215-246).
4. Two saves at once (T20) run in two plain `Task`s, each wrapped in `TaskWatch` (Fakes:454-465), gated with
   `eventually { a.hasReturned && b.hasReturned }`, both cancelled in a `defer`, and awaited only after the gate.
5. File names follow the real `Date()` (`FileNamer(template:)` in `writeFile` takes no `now`, +Save:251; `HistoryStore` prunes on
   `Date()` too). A test that reads a name sets `world.settings.fileNameTemplate = "Shot"` first (no date token, no `{counter}`,
   so `settings.nextCounter()` is not called, +Save:250); a test with two saves of no template asserts distinct names only.
   `FileNamer.uniqueURL` adds ` 2`, ` 3` before the extension (FileNamer.swift:56-66).
6. Images come from `CaptureSamples.image(width:height:scale:white:)` (judge 1.4); the file, the clipboard PNG and the upload body
   are read back with `EditorPixels.decoded(_:)` (Pixels:22-24: pixel width and height, and the scale from the DPI, 144 dpi is 2,
   `ImageEncoder.decode` ImageEncoder.swift:42-48). "The world's red" is `EditorPixels.worldRed()` = `[255, 38, 0, 255]` (Pixels:
   69-71); a pixel read is `EditorPixels.pixel(_:x:y:)` (Pixels:44, :50).
7. Nothing drives `.pin` (`PINS`: +Pins.swift:31 reads `NSScreen.screens`), a `.desktopPicture` or `.customImage` fill (`BGFILL`:
   BackgroundFillSource.swift:12-13), or a save with no stored folder (`FOLDER`). Background fills used are `.gradient(1)` and
   the default style's `.gradient(0)`; both return a nil `fillImage` (BackgroundFillSource.swift:11).
8. (Addition.) `finishSave` starts a thumbnail task that writes under `<root>/thumbnails/` (`makeThumbnail`, +Save:288-310) and
   nothing awaits it. A test that ends before it lands would let it recreate a folder in the removed root. So every test that
   saves a record ends with `try await eventually { coordinator.history.record(id: record.id)?.thumbnailFileName != nil }` for
   each record it made (a copy-only save and a refused one make none). The judge's design-target T1 to T4 ran green without it;
   the cost is one poll loop per record.
9. The suite's helpers (private, as the existing suites keep theirs): `destination`; `save(_ coordinator, _ image, _ origin,
   _ intent) async -> CaptureRecord?` calling `coordinator.save(image, from: origin, intent: intent)`; `isUploaded(_:_:)`
   (`history.record(id:)?.uploadedURL != nil`, as CoordinatorSaveTests.swift:49-52 does with a switch); `exists(_:)`;
   `openedEditor(_:)` copied from CoordinatorEditorTests.swift:29-32; `fileSize(_:)` (`FileManager.attributesOfItem(atPath:)[.size]`).
10. Values common to the entries. The fake destination's link for a key is `https://snap.tky.io/<key>` (FD:274-276); the default key
    template is `{random:6}` (ObjectKeyNamer.swift:11), so a key is six random characters plus `.png`, and a test reads the link
    and key from `history.record(id:)?.uploadedURL` / `.uploadedKey`, never guesses them. Default settings the entries rely on
    (AppSettings.swift:267-297): `copyImageToClipboard` true, `showNotification` true, `playSound` true, `alsoCopyImageWhenUploading`
    false, `windowBackground` false. `world.settings.s3Config` is the world's complete config, so `makeDestination()` answers
    unless credentials are deleted (World:97; +Upload:39-45). `FakeClipboard.changeCount` starts at 0 and each write adds 1
    (Fakes:167-193); `FakeNotifier.notifyUploaded(url:)` is the protocol extension's `copied: true` (Notifier.swift:176-178).

### TARGET.3 CoordinatorCaptureSaveTests.swift (new)

#### T1 `capturesUnderOneTemplateTakeTheNextFreeNameAlsoAfterARelaunch` (M, design-target's, built green there)

- Entry point: `coordinator.save(_:from:intent:)`, three times across two coordinators (+Save:16 after the forwarder; `persist` :140,
  `writeFile` :243).
- Input: `folder = try world.storeSaveFolder()`; `world.settings.fileNameTemplate = "Shot"`; image `CaptureSamples.image(width: 40,
  height: 30, scale: 2)`; origin `CaptureSamples.area()`; intent `CaptureIntent(action: .save)`.
- Sequence: `first = world.makeCoordinator()`; save a, save b; `second = world.makeCoordinator()`; `second.history.load()` (a
  coordinator reads `history.json` in `start()` only, AppCoordinator.swift:308, so the test calls it); save c on `second`.
- Assertions: the records' file names are `Shot.png`, `Shot 2.png`, `Shot 3.png` (+Save:251-252, FileNamer.swift:56-66; the
  template has no `{counter}`, so `world.settings.currentCounter` is unchanged, +Save:250);
  `CaptureSamples.fileNames(in: folder) == ["Shot 2.png", "Shot 3.png", "Shot.png"]` (sorted; a space sorts before a dot);
  `world.notifier.calls == [.saved(title: "Screenshot saved", file: "Shot.png"), .saved(..., file: "Shot 2.png"), .saved(...,
  file: "Shot 3.png")]` (+Save:176-177, :229-230; Show notification defaults on); `first.lastCaptureURL == b.fileURL`,
  `second.lastCaptureURL == c.fileURL` (+Save:152); `second.history.records.count == 3`; `world.logLines.isEmpty`.
- By hand / seam: the folder panel behind Choose… (T6 stands in with `saveLocation.store`); the template's date tokens
  (`FileNamerTests`, D).
- Covers: phase-1:36 (full).
- Mark: `(suite: CoordinatorCaptureSaveTests.capturesUnderOneTemplateTakeTheNextFreeNameAlsoAfterARelaunch,
  FileNamerTests.uniqueURLAppendsCounterWhenFileExists)`.

#### T2 `withAlsoCopyImageTheImageIsOnTheClipboardUntilTheUploadEndsThenTheLink` (M, design-target's, built green there)

- Entry point: `save(_:from:intent:)` with `CaptureIntent(action: .upload)`; the upload through `startUpload` (+Upload:138).
- Input: `world.settings.alsoCopyImageWhenUploading = true`; template `"Shot"`; stored folder; the upload held (rule 3); 40 x 30 at 2,
  origin `CaptureSamples.display`.
- Sequence: save; gate on `heldUploads.count == 1`; assert (held); `releaseUploads()`; gate on `isUploaded`; assert (after);
  rule 8.
- Assertions, held: `record.uploadState == .uploading(fraction: 0)` (+Save:162-163); `world.clipboard.copies == [.pngAndTIFF]`
  (+Save:31, :58); `coordinator.clipboardOwner == EditorClipboard.Owner(recordID: record.id, changeCount: 1)` (+Save:66; the first
  write moves the fake's count 0 to 1); `destination.state.withLock { $0.uploads }.isEmpty`; the file is `<folder>/Shot.png`,
  `record.fileIsTemporary == false`; `world.shutterCount == 1` (+Save:208-210); `world.notifier.calls.isEmpty` (a destination
  means notification `.none` and no warning, +Save:155, :176-177); `world.factory.askedConfigs.count == 1`.
  After the release: `world.clipboard.copies == [.pngAndTIFF, .url(link)]` with `link = record.uploadedURL` (+Upload:698-699, "a
  screenshot's URL always replaces the clipboard"); `link.absoluteString.hasPrefix("https://snap.tky.io/")`; the key ends `.png`;
  `world.notifier.calls == [.uploaded(url: link, copied: true)]` (+Upload:702-704); the upload body equals the file's bytes
  (`uploads[0].data == Data(contentsOf: file)` and `uploads[0].contentType == "image/png"`, since `persist` passes the same
  `png`, +Save:180); `history.record(id:)?.byteCount == uploads[0].data.count` (+Upload:666-667); the clipboard PNG
  (`world.clipboard.pngs[0]`) decodes to 40 x 30 at scale 2.
- By hand / seam: pasting into another app (Preview > New from Clipboard); the editor closing (`EDPLACE`).
- Covers: phase-2:30 (full), phase-3:49 (full), phase-4a:120 (the capture's own clipboard copy and owner; part).
- Mark, phase-4a:120: `(suite, in part: CoordinatorEditorUploadTests.anUploadAfterTheCapturesOwnClosesAtOnceAndEndsWithTheLinkCopied,
  CoordinatorCaptureSaveTests.withAlsoCopyImageTheImageIsOnTheClipboardUntilTheUploadEndsThenTheLink; by hand: the editor closing
  (`EDPLACE`))`. The `TARGET` clause goes. Marks for phase-2:30 and phase-3:49: `(suite: ...T2)`.

#### T3 `aWindowCaptureOnOceanIsComposedInTheFileTheClipboardAndTheUpload` (M, design-target's, built green there)

- Entry point: `save` with a window origin; `withWindowBackground` (+Save:81-98).
- Input: `world.settings.windowBackground = true`; `world.settings.backgroundStyle = BackgroundStyle(fill: .gradient(1), padding: 48)`
  (cornerRadius 12, shadow on, aspect auto, BackgroundStyle.swift:7-13); `#expect(BackgroundPresets.gradients[1].name ==
  "Ocean")` ties the literal to the name (BackgroundPresets.swift:18); `alsoCopyImageWhenUploading = true`; stored folder; template
  `"Shot"`; image 400 x 300 at 2 (a 200 x 150 pt window); origin `CaptureSamples.window`; intent `CaptureIntent(action: .upload)`.
- Sequence: save; gate on `isUploaded`; assert; rule 8.
- Assertions: the size is the layout's, `BackgroundLayout.make` (BackgroundLayout.swift:20-47): padding 48 pt x scale 2 = 96 px a
  side, so 400 + 192 = 592 wide and 300 + 192 = 492 high, content at (96, 96). The saved file, `world.clipboard.pngs[0]`, the
  upload body (`uploads[0].data`) and the record (`pixelWidth` 592, `pixelHeight` 492) all say 592 x 492, and the decoded scale
  of each PNG is 2 (+Save:97 keeps `scale`). The file's pixel at (296, 246) is the world's red (the content, centre of its rect),
  and its pixel at (1, 1) is not (the gradient fill) with alpha 255 (BackgroundCompositor.swift:20-37, `drawGradient` fills
  the canvas). `record.byteCount == uploads[0].data.count == fileSize(file)`. `world.logLines.isEmpty` (no `Background:` line);
  `world.clipboard.copies == [.pngAndTIFF, .url(link)]`.
- By hand / seam: the card's thumbnail drawn on screen (`SCREENS`); Ocean's exact colours (`BackgroundCompositorTests`, D); `sips`
  is the test's decode.
- Covers: phase-7c:179 (part).
- Mark: `(suite, in part: CoordinatorCaptureSaveTests.aWindowCaptureOnOceanIsComposedInTheFileTheClipboardAndTheUpload; by hand: the
  card's thumbnail on screen (`SCREENS`))`.

#### T4 `copyOnlyPutsTheImageOnTheClipboardAndNothingElse(showNotification:)` (M, design-target's, built green there)

- Entry point: `save` with `CaptureIntent(action: .save, copyOnly: true, sender: "Shortcuts")`; `copyOnly(_:sender:)` (+Save:111-133).
- Arguments: `showNotification` true and false (`world.settings.showNotification`).
- Input: 400 x 300 at 2, origin `CaptureSamples.area()`; no folder stored (the branch never asks, +Save:19-22); before the save the test
  sets `coordinator.latestCapture = (id: previous, image: <any ScaledImage>)` and `coordinator.clipboardOwner =
  EditorClipboard.Owner(recordID: previous, changeCount: 0)` for a made-up `previous` id.
- Assertions: the result is nil (+Save:21); `world.clipboard.copies == [.pngAndTIFF]` and `pngs[0]` decodes to 400 wide (+Save:117-118);
  `world.shutterCount == 1` (+Save:126-128; Play sound defaults on); notifier calls are `[.notice(title: "Image copied", body:
  "400 × 300 px", subtitle: "From Shortcuts")]` when on (+Save:129-132; the multiplication sign is U+00D7 with a space either
  side) and `[]` when off; `coordinator.history.records.isEmpty`; no file in `world.saveLocation.currentURL` (it is nil) or in
  `coordinator.pendingFiles.directory` (`CaptureSamples.fileNames(in:)` is `[]`); `world.cards.calls.isEmpty`;
  `world.factory.askedConfigs.isEmpty`; `coordinator.latestCapture?.id == previous` and `clipboardOwner` unchanged (the doc at
  +Save:105-110 and the early return before :23-24); `world.logLines.isEmpty`.
- By hand / seam: hearing the shutter (C); pasting into Preview.
- Covers: phase-6b:117 (full).
- Mark: `(suite: CoordinatorCaptureSaveTests.copyOnlyPutsTheImageOnTheClipboardAndNothingElse, CaptureIntentTests.copyPutsTheImageOnTheClipboardOnly)`;
  the shutter heard stays by hand for good and is not in the mark.

#### T5 `aSaveAndCopyImageCaptureSavesCopiesAndAsksForNoDestination(intent:)` (M)

- Entry point: `save` for an area origin.
- Arguments: `CaptureIntent(action: .save)` (the hotkey and the menu under `Save and copy image`) and `CaptureIntent(urlAction: .save,
  setting: .uploadOnly)` (`action=save` under `Upload only`, CaptureIntent.swift:34).
- Input: stored folder; template `"Shot"`; 40 x 30 at 2; `CaptureSamples.area()` (rect (100, 80, 200, 150)); the default
  settings (copy toggle on).
- Assertions: one file in Saved, `Shot.png`, decoding to 40 x 30 at 2, `record.fileURL` is it, `fileIsTemporary == false`;
  `world.clipboard.copies == [.pngAndTIFF]` and `pngs[0] == Data(contentsOf: file)` (+Save:36, :58); `world.factory.askedConfigs.isEmpty`
  (a `.save` never calls `makeDestination`, +Save:28); `record.uploadState == .none` (+Save:168); `world.shutterCount == 1`;
  `world.notifier.calls == [.saved(title: "Screenshot saved", file: "Shot.png")]`; `coordinator.lastCaptureURL == record.fileURL`
  (+Save:152); `coordinator.latestCaptureArea?.id == record.id` and `?.rect == CGRect(x: 100, y: 80, width: 200, height: 150)`
  (+Save:64); `coordinator.clipboardOwner == Owner(recordID: record.id, changeCount: 1)`; `record.byteCount == fileSize(file)` and
  `== pngs[0].count` (+Save:174, "the size is the PNG's, as written"); `coordinator.history.records.map(\.id) == [record.id]`;
  `coordinator.latestCapture == nil` (the overlay is off, so +Overlay:15-17 never sets it); `world.logLines.isEmpty`.
- By hand / seam: the card with its thumbnail and `Saved` (`SCREENS`); `Reveal Last Capture` selecting the file in Finder (`WORKSPACE`;
  `lastCaptureURL` is pinned); the ⌃⇧4 drag and the area width times the display scale (`CAPSRC`); the audible shutter (C).
- Covers: coordinator-split:36 (part), phase-2:32 (full), phase-6b:116 (full, second argument), small-tweaks:13 (full; the file's
  size equals the record's).
- Mark, coordinator-split:36: `(suite, in part: CoordinatorCaptureSaveTests.aSaveAndCopyImageCaptureSavesCopiesAndAsksForNoDestination;
  by hand: the ⌃⇧4 drag and the pixel width (`CAPSRC`), the card with its thumbnail and `Saved` (`SCREENS`), `Reveal Last Capture` in
  Finder (`WORKSPACE`), the audible shutter)`. phase-2:32, phase-6b:116, small-tweaks:13: `(suite: ...)` with the tests TARGET.4 lists for each; Finder's figure on screen (C) stays by
  hand for good and is not in small-tweaks:13's mark.

#### T6 `theNextCaptureLandsInTheNewlyStoredFolder` (S)

- Entry point: `save` twice with `saveLocation.store(_:)` between (Settings > General > Choose… lands in `store`, SaveLocation.swift:23-28).
- Input: `a = try world.storeSaveFolder()`; `b = <root>/B/` made with `FileManager.createDirectory`; template `"Shot"`; `.save`; 40 x 30 at 2.
- Sequence: save; `try world.saveLocation.store(b)`; save.
- Assertions: the first record's file is `a/Shot.png`, the second's `b/Shot.png` (+Save:244, :252: the folder is read at each save); `a`
  still holds only `Shot.png`; `world.saveLocation.currentURL?.standardizedFileURL == b.standardizedFileURL`.
- By hand / seam: the Choose… panel itself (C; `SaveLocationStoreTests` pins `store`).
- Covers: phase-1:45 (full).
- Mark: `(suite: CoordinatorCaptureSaveTests.theNextCaptureLandsInTheNewlyStoredFolder, SaveLocationStoreTests.storingAFolderMakesItCurrentThenTellsTheHook)`.

#### T7 `uploadAndCopyURLLeavesTheClipboardEmptyUntilTheLink` (S)

- Entry point: `save` with `CaptureIntent(action: .upload)`, Also copy off.
- Input: as T2 but `alsoCopyImageWhenUploading` left false; the upload held.
- Assertions, held: `world.clipboard.copies.isEmpty` (+Save:31: `copyImageNow` is the Also copy setting, false; +Save:58 not called);
  `coordinator.clipboardOwner == nil`; `world.notifier.calls.isEmpty`; no `.saved`. After the release: `world.clipboard.copies == [.url(link)]`;
  `world.notifier.calls == [.uploaded(url: link, copied: true)]`; the file in Saved is still there (the capture is also saved with
  Upload and copy URL).
- By hand / seam: the link pasted into Slack or Notes opening a working page (the real bucket, C); the URL's shape (D:
  `S3DestinationConfigTests.publicURLFromTemplate`, `ObjectKeyNamerTests.defaultTemplateIsSixRandomCharactersPlusExtension`); the overlay's checkmark (`SCREENS`).
- Covers: phase-2:25 (part).
- Mark: `(suite, in part: CoordinatorCaptureSaveTests.uploadAndCopyURLLeavesTheClipboardEmptyUntilTheLink,
  S3DestinationConfigTests.publicURLFromTemplate, ObjectKeyNamerTests.defaultTemplateIsSixRandomCharactersPlusExtension; by hand: the
  link working in Slack (the real bucket) and the overlay checkmark (`SCREENS`))`.

#### T8 `withNoDestinationTwoCapturesCopyTheImageAndPostOneNotice(action:)` (M)

- Entry point: `save` twice on one coordinator.
- Arguments: `.upload` and `.uploadOnly` (as `CaptureIntent(action:)`).
- Input: `try world.credentials.delete(account: KeychainCredentialStore.defaultAccount)` before `makeCoordinator()` (CoordinatorSaveTests.swift:188;
  `makeDestination()` returns nil at +Upload:40 before the factory is asked); stored folder (only `.upload` needs it); template `"Shot"`;
  40 x 30 at 2; origin `CaptureSamples.display`.
- Assertions common: `world.factory.askedConfigs.isEmpty`; `world.clipboard.copies == [.pngAndTIFF, .pngAndTIFF]` (+Save:32-34: upload
  wanted but not possible, so the image goes on the clipboard); `coordinator.clipboardOwner == Owner(recordID: second.id, changeCount: 2)`;
  exactly one `Upload not configured` error among `world.notifier.errors` (+Upload:26-31, once per coordinator); `world.shutterCount == 2`;
  `world.logLines.isEmpty`.
- `.upload`: both `uploadState == .none` (+Save:168); two files `Shot.png`, `Shot 2.png` in Saved; `world.notifier.calls == [.error(title:
  "Upload not configured", message: "Set up a destination in Settings > Upload. The capture was saved and the image is on the clipboard."),
  .saved(title: "Screenshot saved", file: "Shot.png"), .saved(title: "Screenshot saved", file: "Shot 2.png")]` (+Save:158, :205-207 before
  :229-230; the warning posts first, on the first save only); `history.failedRecords.isEmpty`.
- `.uploadOnly`: both `uploadState == .failed(message: "No upload destination is configured.")` (+Save:166, Destination.swift:192); Saved is empty;
  both records `fileIsTemporary` with `pending/<id>.png` existing; `world.notifier.calls == [.error(title: "Upload not configured", message:
  "Set up a destination in Settings > Upload, then retry from Recent Captures. The image is on the clipboard.")]` (+Save:157; no
  `.saved`, +Save:176-177); `history.failedRecords.count == 2`; `world.cards.updates(for:)` is empty (no upload started).
- By hand / seam: both cards saying `Upload failed` (`SCREENS`; the `.failed` state is pinned) and the menu gaining `Retry Failed Uploads`
  (`STATUSMENU`; `failedRecords` is pinned); Settings > Upload showing empty fields with no keychain error (`UPLOADFORM`); the Retry
  half is `CoordinatorUploadTests.retryFailedUploadsSaysOnceWithoutCredentialsAndEnqueuesWithThem` (D).
- Covers: coordinator-split:42 (part, `.uploadOnly`), phase-2:33 (part, `.upload`), phase-3:48 (full, `.uploadOnly`; with T21 for the retry
  leg), phase-4a:119 (part, `.upload`: the capture's own clipboard copy and owner).
- Note on the checklist text: coordinator-split:42 says both cards say `Upload failed` with `Upload and copy URL`; the code gives `.none`
  for that action (catalogue note; +Save:161-169), so the `.upload` argument shows what a user on that setting sees (no failed card, no
  retry item) and the `.uploadOnly` argument what the line's own text needs. The checklist text is not changed here.
- Mark, phase-4a:119: `(suite, in part: CoordinatorEditorUploadTests.withNoDestinationSaveTakesTheClipboardAndUploadIsRefused,
  EditorUploadPlanTests.uploadOutcomeClosesWhenEnqueued, CoordinatorCaptureSaveTests.withNoDestinationTwoCapturesCopyTheImageAndPostOneNotice;
  by hand: the editor staying open (`EDPLACE`))`. The `TARGET` clause goes.
- Mark, coordinator-split:42: `(suite, in part: CoordinatorCaptureSaveTests.withNoDestinationTwoCapturesCopyTheImageAndPostOneNotice,
  CoordinatorUploadTests.retryFailedUploadsSaysOnceWithoutCredentialsAndEnqueuesWithThem; by hand: the cards saying `Upload failed`
  (`SCREENS`) and the menu item (`STATUSMENU`))`. phase-2:33: `(suite, in part: ...T8, CoordinatorUploadTests.notConfiguredIsPostedOncePerCoordinator;
  by hand: Settings > Upload's empty fields and no keychain error (`UPLOADFORM`))`. phase-3:48: `(suite: ...T8, ...T21,
  CoordinatorUploadTests.retryFailedUploadsSaysOnceWithoutCredentialsAndEnqueuesWithThem)`.

#### T9 `aFailingUploadKeepsTheFileAndFailsTheRecord(cause:alsoCopy:)` (M)

- Entry point: `save` with `CaptureIntent(action: .upload)`.
- Arguments (cause, alsoCopy, expected attempts, expected message): (`.denied`, false, 1, `Server returned HTTP 403: AccessDenied: Access Denied`),
  (`.denied`, true, 1, same), (`.offline`, false, 3, `No HTTP response.`).
- Input: `destination.state.withLock { $0.failuresRemaining = n; $0.failure = <error> }` with `n` 1 and `.httpStatus(403, body: "AccessDenied:
  Access Denied")` for `.denied` (403 is not retried: Destination.swift:178-180), `n` 3 and `.noHTTPResponse` for `.offline` (retried, three
  attempts in all: UploadQueue.swift:193, RetryPolicy.default maxAttempts 3, no waiting because the world's `uploadSleep` is `{ _ in }`, World:136);
  `alsoCopyImageWhenUploading = alsoCopy`; stored folder; template `"Shot"`.
- Sequence: save; `eventually` the record is `.failed`; assert; rule 8.
- Assertions: `record.uploadState == .failed(message: <expected message>)` (UploadQueue.swift:203, :209 take `error.localizedDescription`;
  Destination.swift:188-190); `destination.state.withLock { $0.uploadAttempts } == <attempts>`; `world.notifier.calls == [.error(title: "Upload
  failed", message: <expected message>)]` (+Upload:586-590; no `.saved`, since a destination existed); `world.cards.updates(for: record.id).last ==
  .failed(message: <expected message>)` (`refreshOverlay` pushes to `overlay.update` whether or not a card shows, +Overlay:107-110); the file
  `<folder>/Shot.png` exists and `record.fileURL` still points at it; `world.clipboard.copies` is `[]` for `alsoCopy` false and
  `[.pngAndTIFF]` for true (no `.url`); `coordinator.history.failedRecords.map(\.id) == [record.id]`.
- By hand / seam: Wi-Fi off in the real network stack (C; the offline argument stands in); the card drawn with Retry (`SCREENS`; the `.failed` update
  is pinned); the row reading `Upload failed` (D: `RecentCaptureFormattingTests.detailIsTheTimeTheSizeAndEachUploadState`).
- Covers: phase-2:48 (part).
- Mark: `(suite, in part: CoordinatorCaptureSaveTests.aFailingUploadKeepsTheFileAndFailsTheRecord,
  RecentCaptureFormattingTests.detailIsTheTimeTheSizeAndEachUploadState; by hand: the card drawn with Retry (`SCREENS`) and Wi-Fi off for real)`.

#### T10 `anUploadOnlyCaptureKeepsOnlyAPendingFileUntilItsUploaded(origin:cardShows:)` (M; the judge's, with `cardShows` added)

- Entry point: `save` with `CaptureIntent(action: .uploadOnly)`.
- Arguments (origin, cardShows): (`CaptureSamples.display`, false), (`CaptureSamples.window`, false), (`CaptureSamples.area()`, false),
  (`CaptureSamples.area()`, true).
- Input: stored folder (so a mistaken Saved write would show); upload held (rule 3); 40 x 30 at 2; Also copy off.
- Sequence: save; gate on `heldUploads.count == 1`; assert (held); when `cardShows`, `world.cards.showing.insert(record.id)`; release; gate on
  `isUploaded`; assert (after); rule 8.
- Assertions, held: `CaptureSamples.fileNames(in: folder) == []` (nothing in the save folder); `record.fileURL == coordinator.pendingFiles.directory
  .appending(path: "\(record.id.uuidString).png")` and the file exists (+Save:145-148, PendingFileStore.swift:21-26); `record.fileIsTemporary`;
  `record.byteCount == fileSize(pending file)` (+Save:174; small-tweaks:16 "a size before"); `record.uploadState == .uploading(fraction: 0)`;
  `world.clipboard.copies.isEmpty`; `world.notifier.calls.isEmpty`; `coordinator.lastCaptureURL == nil` (only the save-folder branch sets it, +Save:152);
  `coordinator.latestCaptureArea` is `(record.id, rect)` for the area origin and nil for display and window (+Save:64).
- Assertions, after, `cardShows` false: the pending file is gone and `fileNames(in: coordinator.pendingFiles.directory) == []` (+Upload:653-654 with no card:
  `keepForDragOut` returns false at +DragOut:233, `removePendingFile` removes it); `record.fileURL == nil`, `!record.fileIsTemporary` (+Upload:668-671);
  `record.byteCount == uploads[0].data.count` (+Upload:666-667; small-tweaks:16 "after", equal to the PNG's size because the payload is the same bytes);
  `world.clipboard.copies == [.url(link)]`; `world.notifier.calls == [.uploaded(url: link, copied: true)]`.
- Assertions, after, `cardShows` true: the pending directory is empty because the file moved (`keepForDragOut`, +DragOut:232-247: `dragFiles.adopt` renames it to
  `<root>/tmp/Drag/<id>/<last path component of uploadedKey>`, DragFileName.swift:11-24, DragFileStore.swift:103-109); that file exists and decodes to 40 x
  30; `world.cards.dragFiles(for: record.id)` ends with `.some(thatURL)` (+DragOut:241); `record.fileURL == nil` and `!record.fileIsTemporary` (the
  record drops the file either way, +Upload:668-671); clipboard and notifier as above.
- By hand / seam: Wi-Fi off (T21 stands in); the Quick Access stack and Recent Captures drawn (`SCREENS`); that All-in-One builds these origins (`CAPSRC`).
- Covers: phase-5:179 (full; the `cardShows` leg is what the line meets on a real run with a card up), phase-6b:66 (part: any origin saves as any other in upload-only
  mode), small-tweaks:16 (full with T21).
- Mark, phase-5:179: `(suite: CoordinatorCaptureSaveTests.anUploadOnlyCaptureKeepsOnlyAPendingFileUntilItsUploaded,
  CoordinatorCaptureSaveTests.anUploadOnlyCaptureThatFailsKeepsItsPendingFileUntilARetrySucceeds)`. phase-6b:66:
  `(suite, in part: ...T10; by hand: the Quick Access stack and Recent Captures on screen (`SCREENS`), and that All-in-One builds these captures (`CAPSRC`))`.

#### T11 `actionUploadSavesUploadsAndCopiesTheLinkUnderEitherSetting(setting:)` (S)

- Entry point: `save` with `CaptureIntent(urlAction: .upload, setting: setting)` (action `.upload` for `.save`, `.uploadOnly` for `.uploadOnly`,
  CaptureIntent.swift:35).
- Arguments: `setting` = `.save`, `.uploadOnly`.
- Input: stored folder, template `"Shot"`, 40 x 30 at 2, `CaptureSamples.window` with the background off (a window origin shows the intent mapping holds there too).
- Sequence: save; gate on `isUploaded`; rule 8.
- Assertions: `.save`: `<folder>/Shot.png` exists, `record.fileURL` is it, `uploads.count == 1`, `world.clipboard.copies == [.url(link)]`, notifier
  `[.uploaded(url: link, copied: true)]`. `.uploadOnly`: `fileNames(in: folder) == []`, the pending directory empty after the upload (no card), `record.fileURL == nil`,
  `uploads.count == 1`, clipboard `[.url(link)]`. Both: `world.factory.askedConfigs.count == 1`.
- By hand / seam: the URL parsing and the `t` command (D: `CaptureIntentTests.uploadUploadsUnderEverySetting`, URLCommand suites).
- Covers: phase-6b:115 (full).
- Mark: `(suite: CoordinatorCaptureSaveTests.actionUploadSavesUploadsAndCopiesTheLinkUnderEitherSetting, CaptureIntentTests.uploadUploadsUnderEverySetting)`.

#### T12 `aTallCaptureKeepsItsFullPixelSizeInHistory` (S)

- Entry point: `save` with `.save`.
- Input: stored folder; an 8 x 20,000 image at scale 2 (as a stitched scrolling capture's size; `Pasteboard.tiffMaxSide` is 16,384, so the clipboard gets
  the PNG only, Pasteboard.swift:22-33); origin `CaptureSamples.area()` (a scrolling result is an `.area`, +Capture.swift:137-138).
- Assertions: `record.pixelWidth == 8`, `record.pixelHeight == 20_000` (+Save:173); `coordinator.history.record(id:)` has the same; a new coordinator
  from `world.makeCoordinator()` with `history.load()` reads the record with 8 and 20,000 (history.json written by `history.add`, +Save:211); the saved file decodes
  to 8 x 20,000; `world.clipboard.copies == [.pngAndTIFF]` (the call is made with a nil TIFF, which the fake does not distinguish); `world.logLines.isEmpty`.
- By hand / seam: the Recent Captures row's subtitle (C; `RecentCaptureFormattingTests` pins the text); the scrolling capture itself (`SCROLL`).
- Covers: phase-5:202 (full).
- Mark: `(suite: CoordinatorCaptureSaveTests.aTallCaptureKeepsItsFullPixelSizeInHistory)`.

#### T13 `annotateRunsTheActionThenOpensTheEditorOnTheNewCapture` (M)

- Entry point: `save` with `CaptureIntent(action: .save, then: .annotate)` (+Save:68-72 `openEditor(recordID:)`).
- Input: stored folder; template `"Shot"`; 40 x 30 at 2; `CaptureSamples.area()`.
- Sequence: save; `let editor = try await openedEditor(record.id)` (the overlay is off, so no capture is retained and the editor opens from the file asynchronously,
  +Editor:21-28); rule 8.
- Assertions: the file `<folder>/Shot.png` exists and `world.notifier.calls == [.saved(title: "Screenshot saved", file: "Shot.png")]` (the action ran);
  `editor.representedURL == record.fileURL` and `editor.title == "Shot.png"` (+Editor:78-83; FakeEditor keeps both, EditorFakes.swift:30-33);
  `editor.model.base.width == 40`, `.height == 30`; `world.cards.calls.contains(.close(record.id, .editorOpened))` (+Editor:90); `world.editors.built.count == 1`.
- By hand / seam: `action=pin` opening a pin with the card staying (`PINS`); the card closing on screen (`SCREENS`).
- Covers: phase-6b:118 (annotate half; part).
- Mark: `(suite, in part: CoordinatorEditorUploadTests.annotateTheNewestCardSaveThenUploadWritesTheFileThenUploadsAndCopiesTheURL,
  CaptureIntentTests.annotateRunsTheAfterCaptureActionThenOpensTheEditor, .pinRunsTheAfterCaptureActionThenPins,
  CoordinatorCaptureSaveTests.annotateRunsTheActionThenOpensTheEditorOnTheNewCapture; by hand: the `action=pin` half (`PINS`))`. The
  `reaching save(_:intent:) (TARGET)` clause goes.

#### T14 `areaAndFullscreenCapturesKeepThePlainImageWithTheBackgroundOn(origin:)` (S)

- Entry point: `save` with the background on (`withWindowBackground` guard, +Save:82).
- Arguments: `CaptureSamples.display`, `CaptureSamples.area()`.
- Input: `windowBackground = true`, Ocean style as T3, stored folder, `.save`, 400 x 300 at 2.
- Assertions: the file, the record and `pngs[0]` are 400 x 300 at scale 2; the file's pixel at (1, 1) is the world's red (no fill); `world.logLines.isEmpty`.
- By hand / seam: that Previous Area, a scrolling capture and an All-in-One drag build an `.area` or `.display` origin (`CAPSRC`, `SCROLL`): the rule that an origin of those
  kinds is plain is pinned here, which origin each entry point makes is not.
- Covers: phase-7c:182 (part).
- Mark: `(suite, in part: CoordinatorCaptureSaveTests.areaAndFullscreenCapturesKeepThePlainImageWithTheBackgroundOn; by hand: which origin each entry builds for Previous
  Area, a scrolling capture and an All-in-One drag (`CAPSRC`, `SCROLL`))`.

#### T15 `aWindowCanvasFollowsTheStyle(case:)` (M)

- Entry point: `save` with a window origin, `.save`, stored folder.
- Arguments (name; content pixels at scale 2; style; expected canvas). `BackgroundLayout.make` (BackgroundLayout.swift:20-47): pad = padding x 2, aspect grows the short
  side to the ratio, rounding up; the content is swapped to (height, width) terms for a portrait image (:33). Style is `BackgroundStyle(fill: .gradient(1), padding:,
  cornerRadius:, shadow:, aspect:)`.
  - `padding0`: 400 x 300; padding 0, radius 12, shadow on, auto; 400 x 300.
  - `padding160`: 400 x 300; padding 160; 1040 x 940 (pad 320).
  - `radius0`: padding 48, radius 0; 592 x 492.
  - `radius40`: padding 48, radius 40; 592 x 492.
  - `shadowOff`: padding 48, shadow off; 592 x 492.
  - `square`: padding 48, `.square`; 592 x 592.
  - `fourThree`: `.fourThree`; 656 x 492 (width = (492 x 4 + 2) / 3).
  - `threeTwo`: `.threeTwo`; 738 x 492.
  - `sixteenTen`: `.sixteenTen`; 788 x 492.
  - `sixteenNine`: `.sixteenNine`; 875 x 492.
  - `portrait`: content 300 x 400, padding 48, `.sixteenNine`; 492 x 875 (inverted terms, phase-7c:185).
  - `auto`: padding 48, `.auto`; 592 x 492 (the default the checklist's arithmetic starts from).
- Assertions per case: the saved file and the record both equal the expected size, and equal `BackgroundLayout.make(contentSize:style:scale:)!.canvasSize`; the decoded scale is 2;
  `world.logLines.isEmpty`.
- By hand / seam: how radius and shadow look (D: `BackgroundCompositorTests`); the arithmetic itself (D: `BackgroundLayoutTests`, `.portraitContentInvertsTheRatio`).
- Covers: phase-7c:184 (full), phase-7c:185 (full).
- Mark: `(suite: CoordinatorCaptureSaveTests.aWindowCanvasFollowsTheStyle, BackgroundLayoutTests)`; phase-7c:185 names
  `BackgroundLayoutTests.portraitContentInvertsTheRatio` as well.

#### T16 `withTheBackgroundOffEveryCaptureIsPlainAtOnce` (S)

- Entry point: `save` three times on one coordinator, flipping `world.settings.windowBackground` between saves (read at each save, +Save:82).
- Input: stored folder; template `"Shot"`; Ocean style; 400 x 300 at 2; `.save`.
- Sequence: setting on, window save; setting off, window save; setting off, area save.
- Assertions: the first file is 592 x 492; the second (window, `Shot 2.png`) and the third (area, `Shot 3.png`) are both 400 x 300 with the world's red at (1, 1); the records agree;
  `world.logLines.isEmpty`; no relaunch between.
- By hand / seam: the editor's own background switch and an edit's Save (D: `EditorBackgroundExportTests.noBackgroundExportsTheCaptureAsBefore`).
- Covers: phase-7c:186 (full), phase-7c:197 (full with the D edit half).
- Mark: phase-7c:186 `(suite: ...T16)`; phase-7c:197 `(suite: ...T16, EditorBackgroundExportTests.noBackgroundExportsTheCaptureAsBefore)`.

#### T17 `aComposedWindowCaptureOpensInTheEditorComposed` (M)

- Entry point: `save` with `CaptureIntent(action: .save, then: .annotate)`, a window origin, the background on.
- Input: as T3 with 400 x 300 at 2, no upload; template `"Shot"`.
- Sequence: save; `openedEditor(record.id)`; rule 8.
- Assertions: `editor.model.base` is 592 wide and 492 high (decoded from the saved file, +Editor:37-42); its pixel at (296, 246) is the world's red and at (1, 1) is not;
  `editor.model.document == AnnotationDocument()` and `editor.model.document.background == nil` (the popover's switch reads off from this, as CoordinatorEditorTests.swift:496-501);
  `!editor.model.hasUnsavedChanges`.
- By hand / seam: the popover's switch as its binding shows it (`BGPOP`) and drawn in the window (`EDPLACE`).
- Covers: phase-7c:187 (producing the capture through `save`; part).
- Mark: `(suite, in part: CoordinatorEditorTests.aComposedWindowCaptureOpensFlatWithNoBackground, CoordinatorCaptureSaveTests.aComposedWindowCaptureOpensInTheEditorComposed;
  by hand: the popover's switch as its binding shows it (`BGPOP`) and drawn in the window (`EDPLACE`))`. The `producing the window capture (TARGET)` clause goes.

#### T18 `copyAndUploadOfAWindowCarryTheComposedImage` (M)

- Entry point: `save` twice on one coordinator, a window origin, the background on, Ocean style, 400 x 300 at 2.
- Sequence: (1) `CaptureIntent(action: .save, copyOnly: true)`, no folder stored; (2) store a folder, `CaptureIntent(urlAction: .upload, setting: .save)`; gate on `isUploaded`; rule 8.
- Assertions, (1): the result is nil; `world.clipboard.pngs[0]` decodes to 592 x 492 (+Save:18 swaps before the copy-only branch :19-22); `copies == [.pngAndTIFF]`;
  `world.notifier.calls == [.notice(title: "Image copied", body: "592 × 492 px", subtitle: nil)]` (+Save:130, composed size); `history.records.isEmpty`; Saved and pending
  empty; `world.cards.calls.isEmpty`; `world.factory.askedConfigs.isEmpty`. (2): `uploads[0].data` decodes to 592 x 492 at 2; the file and the record are 592 x 492;
  `world.clipboard.copies.last == .url(link)`.
- By hand / seam: the URL parsing and the window click (the user's selection, as the line's own `t` call is).
- Covers: phase-7c:188 (full).
- Mark: `(suite: CoordinatorCaptureSaveTests.copyAndUploadOfAWindowCarryTheComposedImage)`.

#### T19 `aWindowTooLargeForABackgroundIsSavedPlainWithOneLine` (S, design-target's idea, not yet run)

- Entry point: `save`, window origin, the background on.
- Input: `CaptureSamples.image(width: 16_385, height: 2, scale: 1)`; Ocean style; stored folder; template `"Shot"`; `.save`. 16,385 exceeds `BackgroundLayout.maximumContentSide`
  16,384 (BackgroundLayout.swift:6, :24), so the layout is nil, `compose` returns nil and `fits` is false (+Save:90-93).
- Assertions: `world.logLines == ["Background: the window is too large for a background, keeping the window capture"]` (+Save:93-94; the other reason string, `no bitmap
  could be made`, is for a layout that fits); `world.notifier.calls == [.saved(title: "Screenshot saved", file: "Shot.png")]` only (no error for the fallback, doc
  +Save:77-80); the file and record are 16,385 x 2; `world.clipboard.copies == [.pngAndTIFF]` (a nil TIFF above 16,384, Pasteboard.swift:22-33).
- By hand / seam: `no bitmap could be made`: no input forces `compose` to fail while the layout fits, so it stays by code reading, as the line says.
- Covers: phase-7c:189 (part).
- Mark: `(suite, in part: CoordinatorCaptureSaveTests.aWindowTooLargeForABackgroundIsSavedPlainWithOneLine; by hand: the `no bitmap could be made` line, by code reading)`.

#### T20 `twoWindowCapturesAtOnceAreEachComposedInTheirOwnFile` (L)

- Entry point: two `save` calls in two plain `Task`s (rule 4).
- Input: the background on, Ocean style, stored folder, template `"Shot"`, `.save`; capture A 400 x 300 red at 2; capture B 200 x 100 white (`white: true`) at 2.
- Sequence: start both tasks with no await between; gate on both `TaskWatch`es; read both records; rule 8.
- Assertions: two records with distinct ids; their file names are `Shot.png` and `Shot 2.png` in some order (`Set(names) == ["Shot.png", "Shot 2.png"]`); A's file decodes to 592 x 492
  with the world's red at (296, 246); B's decodes to 392 x 292 with `[255, 255, 255, 255]` at (196, 146) (pad 96 each side); the records' sizes agree with their own files;
  `world.notifier.calls.count == 2`, both `.saved`; `world.logLines.isEmpty`.
- By hand / seam: the second capture's card not yet showing (`SCREENS`).
- Covers: phase-7c:190 (full).
- Mark: `(suite: CoordinatorCaptureSaveTests.twoWindowCapturesAtOnceAreEachComposedInTheirOwnFile)`.

#### T21 `anUploadOnlyCaptureThatFailsKeepsItsPendingFileUntilARetrySucceeds` (L)

- Entry point: `save` with `.uploadOnly`, then `coordinator.retryFailedUploads()` (+Upload:496-506).
- Input: stored folder; `destination.state.withLock { $0.failuresRemaining = 1; $0.failure = .httpStatus(403, body: "AccessDenied: Access Denied") }`; 40 x 30 at 2;
  `CaptureSamples.area()`; Also copy off.
- Sequence: save; `eventually` the record is `.failed`; assert; `retryFailedUploads()`; gate on `isUploaded`; assert; rule 8.
- Assertions, after the failure: `record.uploadState == .failed(message: "Server returned HTTP 403: AccessDenied: Access Denied")`; the pending file exists, `fileIsTemporary`, its size equals
  `record.byteCount` (+Save:174); Saved is empty; `world.notifier.calls == [.error(title: "Upload failed", message: <that message>)]`; `world.clipboard.copies.isEmpty`;
  `coordinator.history.failedRecords.map(\.id) == [record.id]`; `uploadAttempts == 1`. After the retry: `uploadAttempts == 2`, `uploads.count == 1` and `uploads[0].data` equals the
  pending file's old bytes (the retry reads the pending file, +Upload:550-551); the pending directory is empty; `record.fileURL == nil`; `record.byteCount == uploads[0].data.count`;
  `world.clipboard.copies == [.url(link)]`; `world.notifier.calls.last == .uploaded(url: link, copied: true)`.
- By hand / seam: Wi-Fi off in the real network (C).
- Covers: phase-5:179 (the Wi-Fi-off clause), phase-3:48 (the retry leg; also D), small-tweaks:16 (the size kept until retried).
- Mark: see T10 and T8.
### TARGET.4 Merged marks

The marks the checklists should carry once the tests land (the wording is the reviewer's to polish; the clauses are what the tests decide). `T<n>` below
stands for `CoordinatorCaptureSaveTests.<name>`. A full line's mark is `(suite: ...)` with no `by hand:` clause, the form every earlier full mark in `docs/testing/` takes; what a full
line leaves by hand for good stays in lines-capture.md's "What stays" and is not in the mark. Where this table and an entry's "Mark:" line differ, this
table wins.

| Line | Mark |
|---|---|
| coordinator-split:36 | in part: T5; by hand: ⌃⇧4 drag and pixel width (`CAPSRC`), card with thumbnail and `Saved` (`SCREENS`), `Reveal Last Capture` (`WORKSPACE`), the audible shutter |
| coordinator-split:42 | in part: T8, `CoordinatorUploadTests.retryFailedUploadsSaysOnceWithoutCredentialsAndEnqueuesWithThem`; by hand: cards saying `Upload failed` (`SCREENS`), the menu item (`STATUSMENU`) |
| phase-1:36 | suite: T1, `FileNamerTests.uniqueURLAppendsCounterWhenFileExists` |
| phase-1:39 | no mark; stays `FOLDER` (the no-folder branch is behind `chooseFolder`'s `NSOpenPanel`, SaveLocation.swift:30-44; +Save:244-248) |
| phase-1:45 | suite: T6, `SaveLocationStoreTests.storingAFolderMakesItCurrentThenTellsTheHook` |
| phase-2:25 | in part: T7, `S3DestinationConfigTests.publicURLFromTemplate`, `ObjectKeyNamerTests.defaultTemplateIsSixRandomCharactersPlusExtension`; by hand: the link in Slack (real bucket), the overlay checkmark (`SCREENS`) |
| phase-2:30 | suite: T2 |
| phase-2:32 | suite: T5 |
| phase-2:33 | in part: T8, `CoordinatorUploadTests.notConfiguredIsPostedOncePerCoordinator`; by hand: Settings > Upload's empty fields (`UPLOADFORM`) |
| phase-2:48 | in part: T9, `RecentCaptureFormattingTests.detailIsTheTimeTheSizeAndEachUploadState`; by hand: the card drawn with Retry (`SCREENS`), Wi-Fi off for real |
| phase-3:48 | suite: T8, T21, `CoordinatorUploadTests.retryFailedUploadsSaysOnceWithoutCredentialsAndEnqueuesWithThem` |
| phase-3:49 | suite: T2 |
| phase-4a:119 | in part: `CoordinatorEditorUploadTests.withNoDestinationSaveTakesTheClipboardAndUploadIsRefused`, `EditorUploadPlanTests.uploadOutcomeClosesWhenEnqueued`, T8; by hand: the editor staying open (`EDPLACE`) |
| phase-4a:120 | in part: `CoordinatorEditorUploadTests.anUploadAfterTheCapturesOwnClosesAtOnceAndEndsWithTheLinkCopied`, T2; by hand: the editor closing (`EDPLACE`) |
| phase-5:179 | suite: T10, T21 |
| phase-5:202 | suite: T12 |
| phase-6b:66 | in part: T10; by hand: Quick Access stack and Recent Captures on screen (`SCREENS`), All-in-One building the captures (`CAPSRC`) |
| phase-6b:115 | suite: T11, `CaptureIntentTests.uploadUploadsUnderEverySetting` |
| phase-6b:116 | suite: T5, `CaptureIntentTests.saveIsSaveAndCopyImageUnderEverySetting` |
| phase-6b:117 | suite: T4, `CaptureIntentTests.copyPutsTheImageOnTheClipboardOnly` |
| phase-6b:118 | in part: `CoordinatorEditorUploadTests.annotateTheNewestCardSaveThenUploadWritesTheFileThenUploadsAndCopiesTheURL`, `CaptureIntentTests.annotateRunsTheAfterCaptureActionThenOpensTheEditor`, `.pinRunsTheAfterCaptureActionThenPins`, T13; by hand: the `action=pin` half (`PINS`) |
| phase-7c:117 | no mark; stays `BGFILL` |
| phase-7c:179 | in part: T3; by hand: the card's thumbnail (`SCREENS`) |
| phase-7c:182 | in part: T14; by hand: which origin Previous Area, a scrolling capture and an All-in-One drag build (`CAPSRC`, `SCROLL`) |
| phase-7c:184 | suite: T15, `BackgroundLayoutTests` |
| phase-7c:185 | suite: T15, `BackgroundLayoutTests.portraitContentInvertsTheRatio` |
| phase-7c:186 | suite: T16 |
| phase-7c:187 | in part: `CoordinatorEditorTests.aComposedWindowCaptureOpensFlatWithNoBackground`, T17; by hand: the popover's switch (`BGPOP`), drawn in the window (`EDPLACE`) |
| phase-7c:188 | suite: T18 |
| phase-7c:189 | in part: T19; by hand: `no bitmap could be made`, by code reading |
| phase-7c:190 | suite: T20 |
| phase-7c:197 | suite: T16, `EditorBackgroundExportTests.noBackgroundExportsTheCaptureAsBefore` |
| small-tweaks:13 | suite: T5, `RecentCaptureFormattingTests.detailIsTheTimeAndTheSize`, `.partsAreSeparatedByAMiddleDot`, `.sizeTextInUSEnglish`, `CoordinatorUploadTests.aStoredUploadWhoseSourceMatchesResumes` |
| small-tweaks:16 | suite: T10, T21 |

### TARGET.5 What was only read, and what could fail

Read from the code and the suites, never run (everything except T1 to T4, which the TARGET designer ran, and T1 and T2, which the design's review ran again; spec section 12):

- T5 to T21, and the changes this note makes to T1 to T4 (rule 8, the pixel reads, the extra assertions). The first compile will find argument-label mistakes.
- The `cardShows` leg of T10: `keepForDragOut` needs `saveAsSuggestion(recordID:)` to answer for a record with a pending file and no card
  (+DragOut:237). Read as total; if it needs the card's state, the leg moves to CoordinatorDragOutTests' setup. `world.temporaryDirectory` must be the
  `DragFileStore`'s root (AppCoordinator.swift:283), which it is.
- T19's `logLines == [one line]`: the thumbnail of a 16,385 x 2 image is a 320 x 1 bitmap (ThumbnailMaker.swift:14-19, :57-66), so no `Thumbnail failed:`
  line; and the PNG encoder takes the width. If either logs, the assertion becomes `contains` with the first line asserted.
- T3's and T20's pixel reads: the gradient's corner and the content centre are inferred from `BackgroundCompositor.compose` (BackgroundCompositor.swift:20-37,
  :73-84); the sizes are the load-bearing assertions, the pixels are the cheap check that the file holds the right capture.
- T12: a 20,000 px PNG and its thumbnail (`cropForThumbnail` cuts a tall image to its top, ThumbnailMaker.swift:36-40) read as fine; the record's size comes
  from the image, not the thumbnail.
- The expected suite line (2373 in 196) assumes all 21 tests pass and no other suite changes.

What stays out of reach whatever the tests: the card on screen (`SCREENS`), Reveal in Finder (`WORKSPACE`), the folder panel (`FOLDER`), the custom image fill (`BGFILL`),
a pin (`PINS`), the desktop-picture fill, and every entry point that builds the origin (`CAPSRC`). None of the 21 tests touches `AppSettings.shared`, `NSPasteboard.general`,
the Keychain, a notification, `NSWorkspace`, `NSScreen.screens`, the `tmp/` statics, a window ordered front, a panel, the screen, a sound, Clop or the network. T17 and T13 construct no
window (`FakeEditors`). The one place a test reads the real clock is `Date()` through `FileNamer` and `HistoryStore`, which rule 5 sidesteps.


## 4. CAPSRC: the capture source (engine and selector)

The tests the capture-source seam gives the 34 CAPSRC lines of `lines-capture.md`. The seam, the fakes and the rules are the judge's (the judge, sections 2.4 to 2.7): `AppEnvironment.captureSource:
any CaptureSource` and `AppEnvironment.selector: any CaptureSelecting`, the value types `CaptureDisplay`, `CaptureWindow` and `ScreenContent`, `FakeCaptureSource` (`world.source`) and
`FakeSelector` (`world.selector`). It sits on TARGET (`CaptureOrigin`, `save(_:from:intent:)`, the save-suite rules), which merges first. The design's review built the CAPSRC diff on the TARGET diff and ran C3 and C5
green (spec section 12); the other tests below were read from the code and have not run. The expected texts and states were each read in the tree; the file:line is given next to the value. Where this note differs from the judge's
2.8 or 2.9 it says so in CAPSRC.7.

Abbreviations: `+Capture`, `+Recording`, `+Save`, `+Overlay` = `TidyShot/App/AppCoordinator+<name>.swift`; `Coord` = `TidyShot/App/AppCoordinator.swift`; `PA` = `TidyShot/Capture/PreviousArea.swift`; `UCH` =
`TidyShot/URLScheme/URLCommandHandler.swift`; `Fakes` = `TidyShotTests/Support/CoordinatorFakes.swift`; `CSF` = `TidyShotTests/Support/CaptureSourceFakes.swift` (new, the judge 2.5); `World` =
`TidyShotTests/Support/CoordinatorWorld.swift`; `CRT` = `TidyShotTests/CoordinatorRecordingTests.swift`.

### CAPSRC.1 Deferred lines and what stops them

CAPSRC supplies the content read (+Capture.swift's `loadContent`, Coord:519-531; +Recording.swift:214, :253, :522), the selection (+Recording.swift:215-216), the display under the pointer (:254) and a second
read that can change or fail between reads. It does not remove these, which a recording start meets in this order (code at 5c2cc33):

1. `recordingCanStart` runs `Recording.makeDirectory()` on the container's `tmp/Recording` (+Recording.swift:213 for Record Screen,
   :249 for Record Fullscreen, :356; Recording.swift:50-56), before the first content read (:214, :253): `TMPDIRS`.
2. Past the lock, `record()` builds `RecordingExtras` for an area or a fullscreen target (+Recording.swift:398, :438-449), and the
   hand-off shows it (:499-508): `EXTRAS`.
3. The hand-off reads `NSScreen.screens.first` (+Recording.swift:496) for every target, and calls `NSApplication.shared.deactivate()`
   for an area or a window (:489-492). With the count-in on (default true, AppSettings.swift:302) it builds `SelfTimerScreenStage`
   from `CaptureEngine.screen(forDisplayID:)?.frame ?? NSScreen.main?.frame` (:509-513): `STAGE`. With it off it sleeps on the
   world clock (:519), a `FakeScrollClock` the test controls. seams.md names the :496 read only inside `STAGE`'s screen lookup
   (seams.md section 15), so a count-in-off start has no seam for it.
4. The request ends in `RecordingScreenChrome(placement:extras:)` (+Recording.swift:582), which `recorder.run(start.request, chrome:)`
   shows (:416): `RECCHROME`. A window target's `covers.hide(for: .capture)` (:229) is the live covers: `COVERS` to observe it.

| Line | First blocker | Beyond `TMPDIRS` and CAPSRC |
|---|---|---|
| phase-5:182 (:195) | `SCROLL` | `scrollCapture.run` (+Capture.swift:128) orders a frame window and a panel front (ScrollCaptureController.swift:42-43, :72-76); the outcome is not held anywhere a test reaches; `TARGET`'s save then follows (:133-139) |
| phase-6b:75 (:91) | `STAGE` | `runSelfTimer` (+Capture.swift:297-307) holds the lock through a countdown it cannot build without `SelfTimerScreenStage`; the menu's disabled items `STATUSMENU` |
| phase-6b:77 (:93) | `STAGE` | `selfTimer.run(seconds: settings.selfTimerSeconds, stage:)` (+Capture.swift:304) is behind the same stage; the tooltip is D |
| phase-6b:79 (:95) | `STAGE` | `settings.lastAreaRect` is stored at +Capture.swift:190 and `runSelfTimer` follows at :191 with no stop; the ⌃⇧6 recapture is C7's shape |
| phase-7b:96 (:108) | `COVERS` | `captureScrolling` and `captureText` pass `coversDesktop: false` (+Capture.swift:86, :229, :251), so `withCaptureLock` skips `covers` (Coord:576). To see that no `show(for: .capture)` happens the test needs a covers fake and `hideDesktopIconsWhileCapturing` on; without the fake, a wrong guard would call the live `covers.show` (Coord:61, :580), which reads ScreenCaptureKit and `NSScreen` |
| recording-r1:102 (:105) | `TMPDIRS` | `EXTRAS`, `RECCHROME`, `STAGE` (default count-in on), item 3 |
| recording-r1:105 (:108) | `TMPDIRS` | none: the refusal `Select a larger area to record.` (title `Screen recording`, `RecordingEnd.refusalTitle`, RecordingEnd.swift:47) is at +Recording.swift:220-223, before the hand-off, and no code on the recording path writes `lastAreaRect` (the only writes are +Capture.swift:64, :125, :135, :177, :190, :343). **`TMPDIRS` with CAPSRC finishes this line**; seams.md and `lines-capture.md` list it with no other seam, which is true only if `TMPDIRS` counts as landed |
| recording-r1:122 (:125) | `TMPDIRS` | `COVERS` (the hide at +Recording.swift:229), `RECCHROME`; no `EXTRAS` (a window) |
| recording-r1:124 (:129) | `TMPDIRS` | `COVERS`, `EXTRAS`, `RECCHROME`, `STAGE` |
| recording-r1:196 (:207) | `TMPDIRS` | `STAGE` for a count-in, or count-in off with the world clock held and `world.source.content` changed during the settle sleep (+Recording.swift:519, :522); item 3's screen read; `RECCHROME` for the moved window's request. The notice `The window is no longer on screen.` titled `Screen recording` (:544-547) comes before the chrome (:582) |
| recording-r2:231, :236, :238, :390, :402, :407, :605, :653 | `TMPDIRS` | `RECCHROME`; `EXTRAS` unless the target is a window; `STAGE` unless the count-in is off; item 3's screen read. recording-r2:653 is ticked `[x]` and stays so |
| recording-r2:397, :409 | `TMPDIRS` | as above, and `STAGE`: the count-in is the scenario |
| recording-r3:276 (:285) | `TMPDIRS` | item 3's screen read; `EXTRAS` for the `defer { extras?.close() }` (+Recording.swift:399) the line names, unless the target is a window (no extras). CAPSRC supplies the failing second read: the first read (:214) succeeds, the selector is held, the test sets `world.source.contentFailures = [FakeCaptureError()]` while it waits, then answers the selection, and the read at :522 fails (C5 pins the failure itself; `contentFailures` is consumed from the first read after it is set) |
| recording-r4:217 (:226) | `TMPDIRS` | see the end of this subsection |

#### recording-r4:217

Current mark (CT-1, extended by CT-3 to name `CAPSRC`): `(suite, the rule: CoordinatorRecordingTests.recordingProceedsOnlyWhenStartedNotQuittingAndNotCancelled;
by hand: the log line, in private record() past the capture lock (TMPDIRS, CAPSRC))`. No test is added: the line is a window
target with the count-in off, cancelled in the settle delay (+Recording.swift:519; the cancel is `recordShortcutStarts`'
`.cancelCountIn`, :295-299, which sets `recordingStartCancelled`), and the log is `Recording: not started, the count-in was
cancelled` (+Recording.swift:411, through `recordingLog`, done in CT-3). With CAPSRC the content read (:214, :522) and the window
selection (:215) are fakes, and the settle sleep is the world clock. It is still unreachable: `recordingCanStart` makes the
real `tmp/Recording` (`TMPDIRS`, :213, :356), and the hand-off, before the sleep, calls `NSApplication.shared.deactivate()`
(:491) and reads `NSScreen.screens` (:496). Over Record Fullscreen it also needs `EXTRAS` (:398). So CAPSRC leaves the mark and
the screen read joins it. Merged mark: (suite, the rule: `CoordinatorRecordingTests.recordingProceedsOnlyWhenStartedNotQuittingAndNotCancelled`;
by hand: the log line, in private `record()` past the capture lock (`TMPDIRS`, and the hand-off's `NSScreen` read,
+Recording.swift:496, which only `STAGE`'s screen lookup names)).

### CAPSRC.2 What holds for every test here

From the judge (2.7) and the phase constraints (the spec's section 5), with the two additions marked **new**.

- Suite `TidyShotTests/CoordinatorCaptureSourceTests.swift` (new): `@Suite(.timeLimit(.minutes(1)))`, `let world:
  CoordinatorWorld`, built in `init() throws` with `world.settings.showOverlay = false` (a card's screen is read from
  `NSScreen`, +Overlay.swift:9, :55-62); every test opens with `defer { world.removeAll() }`; no `.serialized`; one defaults
  suite and one temp root per test (World:70-88).
- The world gains `source` (`FakeCaptureSource`: one 1440 x 900 pt display, id 1, frame (0, 0, 1440, 900), no windows,
  scale 1) and `selector` (`FakeSelector`: Escape unless a test scripts or holds an answer), judge 2.6. A display is
  `FakeCaptureSource.display`; a window is `CaptureWindow(windowID:frame:)`.
- **New: every call passes an explicit `CaptureIntent`.** The entry points default to `CaptureIntent.standard`
  (+Capture.swift:6, :15, :19, :29, :80, :146, :184), which reads `AppSettings.shared` (`CaptureIntent.swift:42-44`).
  The value used is `CaptureIntent(action: .save)`, or `CaptureIntent(action: .save, copyOnly: true)` when the capture
  reaches a save (copy-only needs no save folder, so `ensureFolder` never builds a panel, TARGET rule 2). `captureText()`
  takes no intent. A URL command builds its intent from the world's own `settings.afterCaptureAction` (UCH:179), not the
  shared one.
- No test calls an entry point whose path reaches `runSelfTimer` (+Capture.swift:297-307: `NSApplication.deactivate`,
  `NSScreen`, `SelfTimerScreenStage`), `recordingCanStart` (+Recording.swift:213, :249, :356: the real `tmp/Recording`),
  All-in-One's `.fullscreen` choice (`NSCursor.arrow.set()`, +Capture.swift:54), or `covers` with
  `hideDesktopIconsWhileCapturing` on (the live `DesktopCoverController`, Coord:61). `scrollCapture.run` is never reached:
  a test-built display has no `live` object, and `runScrolling` stops at its guard after the 100 pt check and the store
  (judge 2.4, `runScrolling`); a test asserts only what happened before that.
- A held overlay (judge 2.7 rule 4): `world.selector.holds = true`, `defer { world.selector.answer(nil) }` declared right
  after `defer { world.removeAll() }`; the entry point runs in a plain `Task` with `defer { task.cancel() }` and a
  `TaskWatch` (Fakes:450-463); the test waits with `try await eventually { world.selector.isWaiting }`
  (`eventually`, UploadQueueTests.swift:42) and never awaits the task directly.
- A window target's display id is `CGGetDisplaysWithPoint` on the host (CaptureTarget.swift:18, CaptureEngine.swift:94-99): a
  test never asserts on a window target's display id or origin. Nothing in a CAPSRC test reads `NSScreen.screens`: the fake
  selector and the fake pointer display replace every read the coordinator made.
- File names follow the real `Date()` (TARGET rule 5); no CAPSRC test checks a saved file's name, and none saves to a
  folder (all saves are copy-only).
- `HistoryStore` prunes on the real `Date()`; no test here adds a record.
- `FakeNotifier.Call.error(title:message:subtitle:)` has `subtitle` defaulting to nil (Fakes:13), so `.error(title:message:)`
  compares a notice with no subtitle. `notifyError(_:title:)` posts under `Capture failed` unless a title is given
  (Notifier.swift:180).
- A copy-only save posts `.notice(title: "Image copied", body: "<w> × <h> px", subtitle: nil)` when `showNotification` is on
  (default true, AppSettings.swift:269; +Save.swift:129-131), and plays the shutter when `playSound` is on (default true, :270;
  +Save.swift:126-128), so `world.shutterCount` rises by one per such save. The body's `×` is U+00D7 with a space each side.

### CAPSRC.3 The values the fakes carry (the judge 2.5, for reading the entries)

- `FakeCaptureSource.Capture` is `{ target: CaptureTarget, options: CaptureOptions, excludedWindowIDs: [CGWindowID] }`,
  `Equatable`; `world.source.captures` is every `capture` call in order, a failed one included; `contentReads` counts
  `screenContent()` calls; `contentFailures: [any Error]` is consumed one per read; `captureFailure: (any Error)?` makes
  every capture throw after recording it; `pointerDisplayID: CGDirectDisplayID?` (nil: the first display); `scale` (1).
  A successful capture answers a red image of `Geometry.pixelSize(points: target.cgFrame.size, scale: scale)` (Geometry.swift:24-26:
  `(width * scale).rounded()` each side), scale `scale`, and the target handed in.
- `FakeCaptureError` has `errorDescription == "The fake source failed."`; `localizedDescription` is that text.
- `FakeSelector.Select` is `{ mode, freeze: CaptureOptions?, preselect: CGRect? }`, `FakeSelector.AllInOne` is
  `{ freeze, preselect, armed }`; `selects`, `allInOnes` record every ask in order; `selections: [Selection?]` and
  `choices: [AllInOneChoice?]` are consumed one per ask (empty or nil is Escape); `holds`, `isWaiting`, `answer(_:)`,
  `answerAllInOne(_:)`; `overlays` (what `overlayWindows()` gives), `frozen` (by display id), `frozenAsked`, `overlayLookups`,
  `dismissCount`.
- `CaptureOptions(showsCursor:windowShadow:)` is the memberwise init (CaptureTarget.swift:43-47). A capture's options come from
  `CaptureOptions(settings:duringSelection:)` (+Capture.swift:380): `showsCursor` is `settings.showsCursor &&
  !duringSelection` and `windowShadow` is `settings.windowShadow`; both settings are false in a fresh world (AppSettings.swift:267,
  :288), so every capture in this suite has `CaptureOptions(showsCursor: false, windowShadow: false)`, whichever `duringSelection`.

### CAPSRC.4 CoordinatorCaptureSourceTests.swift (new)

#### C1 `capturePreviousAreaWithNoUsableStoredAreaIsRefusedAndCapturesNothing(stored:)` (S; two arguments)

- Entry point: `coordinator.capturePreviousArea(intent: CaptureIntent(action: .save))` (+Capture.swift:146).
- Arguments: `nonisolated enum StoredArea: CaseIterable, Sendable { case none, offItsDisplay }`.
  - `.none`: `world.settings.lastAreaRect = nil` (the default). Message `Capture an area first.` (+Capture.swift:152; `PA.resolve`
    answers `.none` for a nil rect, PA:45).
  - `.offItsDisplay`: `world.settings.lastAreaRect = StoredRect(CGRect(x: -0.4, y: 100, width: 1.2, height: 200))`. The rect
    is at least 1 pt each side (PA:45), its centre (0.2, 200) is on display 1 (frame (0, 0, 1440, 900), PA:47), and the part
    on the display is x 0 to 0.8, 0.8 pt wide, under 1 (PA:49-50), so `.offScreen`. Message `The previous area is not on a
    connected display.` (+Capture.swift:154). The strip is the line's own value (phase-6a :260).
- Fakes and scripts: none beyond the world's defaults; the one-display content is the line's "main display's left edge at
  x 0".
- Sequence: build the coordinator (`world.makeCoordinator()`), set the setting, call the entry point once (it returns
  without waiting on anything: the content read, the resolution and one notice).
- Assertions: `world.notifier.calls == [.error(title: "No previous area", message: <the message>)]` (+Capture.swift:152, :154);
  `world.source.contentReads == 1` (`loadContent`, Coord:521, behind `captureSource.screenContent()`);
  `world.source.captures.isEmpty`; `world.source.windowLookups.isEmpty`; `world.selector.selects.isEmpty`;
  `world.selector.allInOnes.isEmpty`; `world.clipboard.copies.isEmpty`; `coordinator.history.records.isEmpty`;
  `world.shutterCount == 0`; `world.cards.calls.isEmpty`; `world.logLines.isEmpty`; `world.settings.lastAreaRect` equal to
  what was set (a refusal writes nothing, +Capture.swift:145 doc, no store in :146-162); `!coordinator.isCapturing`
  (the lock, Coord:572-584, ends with the body).
- By hand / seam: `defaults delete ... lastAreaRect`, `defaults write`, and the quit and reopen are replaced by the setting;
  that a stored value survives a relaunch is D (`AppSettingsTests.lastAreaRectRoundTripsThroughASecondInstanceAndClears`,
  AppSettingsTests.swift:57; `lastAreaRectIsNilUntilAnAreaIsCaptured`, :53). The two resolutions are D too
  (`PreviousAreaTests.noRectResolvesToNone`, PreviousAreaTests.swift:13; `aRectLeavingUnderOnePointOnItsDisplayIsOffScreen`, :56);
  this test adds that the coordinator posts them under `No previous area` and captures nothing, which was by hand.

#### C2 `allInOneOpensOnThePreviousAreaArmedOrAURLRectDisarmedAndEscapeStoresNothing` (S)

- Entry point: `coordinator.captureAllInOne(intent:preselect:fromURLCommand:)` (+Capture.swift:29-30), three calls.
- Input: `previous = CGRect(x: 100, y: 120, width: 300, height: 200)`, stored with `world.settings.lastAreaRect =
  StoredRect(previous)`; `urlRect = CGRect(x: 0, y: 500, width: 500, height: 400)`, which is where `all-in-one?x=0&y=0&width=500&height=400`
  lands on a 900 pt high display (CoreGraphics y = 900 - 0 - 400 = 500; the placement itself is D); the handler's
  `ScreenRect(rect: urlRect, displayID: 1)`; `intent = CaptureIntent(action: .save)`.
- Fakes and scripts: `world.selector.choices` left empty, so each overlay answers Escape (a nil choice).
- Sequence: (1) `captureAllInOne(intent: intent)` (the shortcut and the menu: both pass the defaults, `fromURLCommand` false);
  (2) `captureAllInOne(intent: intent, preselect: ScreenRect(rect: urlRect, displayID: 1), fromURLCommand: true)` (`t 'all-in-one?x=0...'`);
  (3) `captureAllInOne(intent: intent, preselect: nil, fromURLCommand: true)` (`t all-in-one`, no rect).
- Assertions, after the three: `world.selector.allInOnes == [AllInOne(freeze: nil, preselect: previous, armed: true),
  AllInOne(freeze: nil, preselect: urlRect, armed: false), AllInOne(freeze: nil, preselect: previous, armed: false)]` (the call
  is `selectAllInOne(content:freeze:preselect: preselect?.rect ?? settings.lastAreaRect?.cgRect, armed: !fromURLCommand)`,
  +Capture.swift:37-39; `freeze` is nil because `settings.freezeScreen` defaults false, AppSettings.swift:289, :34;
  `StoredRect(previous).cgRect == previous` exactly, PA:12-19); `world.settings.lastAreaRect == StoredRect(previous)`
  (Escape returns at :40 before any store, :44-45, :64); `world.selector.dismissCount == 0` (:68 is after the `guard`);
  `world.source.contentReads == 3`; `world.source.captures.isEmpty`; `world.selector.selects.isEmpty`;
  `world.notifier.calls.isEmpty`; `!coordinator.isCapturing`.
- By hand / seam: the overlay showing the rect selected and adjustable, and showing none when its display is gone, is
  `SelectionController.placePreselected` (SelectionController.swift:137-148, reads `NSScreen.screens`): `SELINT`. Its restore rule
  is D (`SelectionAdjustTests.restoreKeepsARectOnItsDisplay`, SelectionAdjustTests.swift:232; `restoreRefusesARectOffEveryDisplay`, :245).
  The URL form's routing and rect are D (`URLCommandHandlerTests.everyCommandReachesItsCaptureFunction`, URLCommandHandlerTests.swift:100;
  `URLCommandGeometryTests.theOriginIsTheBottomLeftOfTheMainDisplay`, URLCommandGeometryTests.swift:24). The view's disarmed
  Return and double-click are D (`SelectionViewArmingTests.aDisarmedRectIgnoresReturnUntilAPress`, :56, `.aDisarmedRectStillNudgesAndCancels`,
  `.aDoubleClickCapturesOnlyWhenArmedBeforeIt`, :86, `.aNewRectIsArmed`, :100). Arming by a W change or the lock toggle has no
  test: C9. Return typed in another app as the overlay appears is C.

#### C3 `aHeldSelectionOpensOneWindowAndDropsEveryOtherURLCaptureCommandWithoutReadingOrPosting` (M, held; the catalogue's tests 3 and 8 merged)

- Entry point: `URLCommandHandler.handle(_:sender:)` (UCH:83) six times, over the real coordinator as target. The coordinator's own handler is private and readied only by `start()`
  (Coord:36, :343), so the test builds one: `URLCommandHandler(settings: world.settings, target: coordinator, screens: { URLCommandHandler.Screens(displays: [], pointerIndex: nil) }, post: { notice in
  Issue.record("posted \(notice.body)") })` (the internal init, UCH:74), then `await handler.ready()` (UCH:98). The handler holds the coordinator weakly (UCH:68): the test keeps `coordinator` alive.
  **`world.settings.urlCommandsAllowSilent = true` is required**: `capture-fullscreen` is a command that captures without a selection (URLCommand.swift:68-70), and with the default (false,
  AppSettings.swift:291) the gate refuses it and posts a notice (UCH:146-150) instead of reaching the drop, which would fail the `post` guard. `capture-window`, and `capture-area` and
  `capture-scrolling` without a rect, need no allowance (URLCommand.swift:68-75).
- Input: sender `"Terminal"`; URLs, in order: `tidyshot://capture-window` (the one that holds), `tidyshot://capture-window`, `tidyshot://capture-window`, `tidyshot://capture-fullscreen`,
  `tidyshot://capture-area`, `tidyshot://capture-scrolling`. The gate runs each: `URLCommandGate.decision` is `.run` (URLCommandGate.swift:15-21; URL commands are on by default,
  AppSettings.swift:290). With no rect, `screens()` is not called.
- Fakes and scripts: `world.selector.holds = true`; `defer { world.selector.answer(nil) }`.
- Sequence: `first = Task { await handler.handle(window, sender: "Terminal") }` with `defer { first.cancel() }` and `firstWatch = TaskWatch(first)`; `try await eventually { world.selector.isWaiting }`;
  then a `TaskWatch(Task { ... })` per further URL, in the order above, and `try await eventually { all five hasReturned }`; assert; `world.selector.answer(nil)`;
  `try await eventually { firstWatch.hasReturned }`; assert.
- Assertions, with the selection held and the other five returned: `world.selector.selects == [Select(mode: .window, freeze: nil, preselect: nil)]` (`runSelection`, +Capture.swift:199-206; freeze is nil
  for a non-area mode, :204); `world.selector.allInOnes.isEmpty`; `world.source.contentReads == 1` (the dropped five read nothing: they stop at the handler's drop, UCH:154-157, which reads
  `target.captureRefusal`, Coord:562-564, `.captureRunning` while `isCapturing`, Coord:557); `world.source.captures.isEmpty`; `world.notifier.calls.isEmpty` (a drop posts nothing, only an `NSLog`,
  UCH:155; the `post` closure records an issue if it is called); `coordinator.isCapturing`; `!firstWatch.hasReturned`; `!coordinator.scrollCapture.isRunning` (the scrolling command did not start a session;
  `captureScrolling` is refused by the handler's drop, and would be by the lock too, Coord:573). After the answer: `!coordinator.isCapturing` (a nil selection returns at +Capture.swift:206, before
  `dismiss`, :215); `world.source.captures.isEmpty`; `world.selector.selects.count == 1`; `world.selector.dismissCount == 0`.
- By hand / seam: the log line `... dropped, a capture is running: <url>` is an `NSLog` (UCH:155; the sink is `URLLOG`); its text is already covered
  (`URLCommandHandlerTests.theLogSaysWhyACaptureCommandWasDropped`, URLCommandHandlerTests.swift:221) and the drop itself with the refusal faked is too
  (`.captureCommandsAreDroppedWhileCapturesAreRefused`, :201). What this test adds is the live burst: the first Task takes the lock before its first suspension that matters (the held `select`), so
  the next five see it (`handleURL` runs one Task per URL, Coord:367-369). `restore-recently-closed` still restoring a card is not asserted (the handler's routing is already covered, and
  `restoreClosedOverlay` has its own tests, CoordinatorOverlayTests.swift:66). While a self-timer counts: `STAGE`. During a scrolling session before and after Start: `SCROLL`. A selection opened by
  `capture-area` instead of `capture-window` is the same drop; line 159 names ⌃⇧4, line 160 `capture-window`, and one held selection serves both.
- Covers: phase-6b:160 (full), phase-6b:159 (the open-selection leg; part).

#### C4 `capturePreviousAreaAfterCaptureTextCapturesTheEarlierImageArea` (M, runs the real text recognizer)

- Entry points: `coordinator.captureText()` (+Capture.swift:227) then `coordinator.capturePreviousArea(intent: CaptureIntent(action:
  .save, copyOnly: true))` (:146).
- Input: `earlier = CGRect(x: 100, y: 100, width: 300, height: 200)`, stored with `world.settings.lastAreaRect =
  StoredRect(earlier)`; `textArea = CGRect(x: 600, y: 400, width: 40, height: 20)`.
- Fakes and scripts: `world.selector.selections = [.area(rect: textArea, display: FakeCaptureSource.display)]`.
- Sequence: `captureText()`; assert; `capturePreviousArea(...)`; assert. `captureText` ends in `copyText(in:)`, which runs the real
  `TextRecognizer().recognize(image)` (+Capture.swift:273) on the fake's red 40 x 20 image: it finds nothing and posts a
  notice that this test does not read (+Capture.swift:280-282). Vision is not on the forbidden list and `TextRecognizerTests`
  load it in the same run; the first request after a restart can take about 24 s (the doc, +Capture.swift:224-225), inside
  the one-minute limit (Tim's call 3, judge section 4).
- Assertions, after `captureText()`: `world.settings.lastAreaRect == StoredRect(earlier)` (`captureText` takes
  `selectedAreaResult`, which stores nothing, +Capture.swift:235, :349-355; `areaResult` is the one that stores, :343);
  `world.selector.selects == [Select(mode: .area, freeze: nil, preselect: nil)]` (:232); `world.selector.frozenAsked == [1]`
  (`frozenResult` asks for the display's snapshot even with freeze off, :360); `world.selector.overlayLookups == 1` (:353);
  `world.selector.dismissCount == 1` (:240); `world.source.captures == [Capture(target: .area(rect: textArea, display:
  FakeCaptureSource.display), options: CaptureOptions(showsCursor: false, windowShadow: false), excludedWindowIDs: [])]`
  (:354, with the overlay up and no card windows). After `capturePreviousArea`: `world.settings.lastAreaRect ==
  StoredRect(earlier)`; `world.source.contentReads == 2`; `world.source.captures` is the first capture followed by
  `Capture(target: .area(rect: earlier, display: FakeCaptureSource.display), options: CaptureOptions(showsCursor: false,
  windowShadow: false), excludedWindowIDs: [])` (the stored rect is clipped to display 1 and is inside it, so unchanged,
  PA:47-51; `cardWindows()` is `[]` because `FakeCards.windowNumbers` is empty, +Capture.swift:392-393, Fakes:91); and the
  copy-only save left exactly one PNG on the clipboard that decodes 300 x 200 at scale 1: `world.clipboard.pngs.count == 1` and
  `EditorPixels.decoded(world.clipboard.pngs[0])` has `image.width == 300`, `image.height == 200`, `scale == 1`
  (EditorPixels.swift:22-24; the PNG records its pixel size, ImageEncoder.swift:21-26). That PNG is the previous image area,
  not the 40 x 20 text selection (which never reaches the clipboard as a PNG: `copyText` at most writes a string,
  +Capture.swift:284).
- By hand / seam: the drag of the text selection and the ⌃⇧6 press are the entry points; `COPYTEXT` (seams.md section 30) would
  remove the recognizer run and is not needed for these assertions.

#### C5 `aFailedContentReadIsLoggedAndPostedAndAsksNothingMore` (S, the harness: no line)

- Entry point: `coordinator.captureArea(intent: CaptureIntent(action: .save))` (+Capture.swift:15 -> `runSelection`, :199).
- Fakes and scripts: `world.source.contentFailures = [FakeCaptureError()]`. The fake reports Screen Recording granted, so the
  failure posts and the permission window is never shown (Coord:524-527).
- Assertions: `world.logLines == ["Shareable content failed: The fake source failed."]` (Coord:523); `world.notifier.calls ==
  [.error(title: "Capture failed", message: "Could not list screens and windows: The fake source failed.")]` (Coord:525,
  `failureTitle` defaults to `Capture failed`, Coord:519); `world.selector.selects.isEmpty` (`runSelection` returns at :201);
  `world.source.captures.isEmpty`; `world.source.contentReads == 1`; `!coordinator.isCapturing`.
- By hand / seam: the other branch (not granted: `permissionWindow.show()`, Coord:527) is not reached; the fake's grant is
  always true. No checklist line claims this branch's text; `recording-r3:276`'s failed read is a recording one (CAPSRC.1).

#### C6 `aScrollingAreaUnder100PointsIsRefusedAndTheNextShortcutWorks` (S)

- Entry points: `coordinator.captureScrolling(intent:preselect:)` (+Capture.swift:80), three calls. Reading `scrollCapture.isRunning`
  (:82) builds the controller lazily (Coord:33), which only stores its engine and settings (ScrollCaptureController.swift:21-24).
- Input: `stored = StoredRect(CGRect(x: 10, y: 20, width: 300, height: 200))` set as `world.settings.lastAreaRect`;
  `drag = CGRect(x: 100, y: 100, width: 400, height: 60)` (400 wide, 60 tall: the line's own); `intent = CaptureIntent(action: .save)`.
- Fakes and scripts: `world.selector.selections = [.area(rect: drag, display: FakeCaptureSource.display), .area(rect: drag,
  display: FakeCaptureSource.display)]`.
- Sequence: (1) `captureScrolling(intent: intent)`; (2) `captureScrolling(intent: intent)` (the next ⌃⇧5); (3) `captureScrolling(intent: intent,
  preselect: ScreenRect(rect: drag, displayID: 1))` (a URL command's rect: added here; `runScrolling(... preselected: true)`, +Capture.swift:99).
- Assertions, after the three: `world.notifier.calls == [.error(title: "Scrolling capture", message: "Select an area at least 100
  points tall."), (the same), (the same)]` (+Capture.swift:121; the check is `rect.height >= 100`, :119, with
  `ScrollCaptureLimits.minimumAreaHeightPoints` 100, ScrollCaptureLimits.swift:11); `world.selector.selects == [Select(mode:
  .scrolling, freeze: nil, preselect: nil), (the same)]` (+Capture.swift:102: two overlays asked, so the second shortcut got an
  idle overlay and a free lock; the preselect form asks none); `world.selector.dismissCount == 3` (:120, once per refusal);
  `world.source.contentReads == 3`; `world.settings.lastAreaRect == stored` (the store at :125 is after the check, and the
  preselected form never stores before the session, :124); `world.source.captures.isEmpty`; `!coordinator.isCapturing`;
  `!coordinator.scrollCapture.isRunning` (the session is never started, :128).
- By hand / seam: the drag in the overlay is C. An area exactly 100 pt tall passing the check is C7; the session that
  follows is `SCROLL`.
  replace the rect; part).

#### C7 `windowAndFullscreenCapturesLeaveThePreviousAreaAndAScrollingDragStoresIt` (M)

- Entry points, in order: `captureWindow`, `captureFullscreen`, `captureArea(at:intent:)`, `capturePreviousArea`,
  `captureArea(at:intent:)` with a failing source, `captureScrolling`.
- Input: `stored = StoredRect(CGRect(x: 10, y: 20, width: 300, height: 200))` as `lastAreaRect`; `window = CaptureWindow(windowID: 7,
  frame: CGRect(x: 200, y: 150, width: 300, height: 200))`; `urlArea = ScreenRect(rect: CGRect(x: 50, y: 60, width: 200, height: 120),
  displayID: 1)`; `failedArea = ScreenRect(rect: CGRect(x: 400, y: 300, width: 200, height: 120), displayID: 1)`; `drag =
  CGRect(x: 100, y: 100, width: 400, height: 100)`; `copy = CaptureIntent(action: .save, copyOnly: true)` for every capture that
  saves (copy-only: no folder, no record, TARGET rule 2); `CaptureIntent(action: .save)` for scrolling.
- Fakes and scripts: `world.selector.selections = [.window(window)]` for step 1 and `[.area(rect: drag, display:
  FakeCaptureSource.display)]` set before step 6; `world.source.pointerDisplayID` nil (the first display, which is the only one).
- Sequence and assertions (`options` below is `CaptureOptions(showsCursor: false, windowShadow: false)`; `Cap` is `FakeCaptureSource.Capture`):
  1. `captureWindow(intent: copy)`: `world.source.captures == [Cap(target: .window(window), options: options, excludedWindowIDs: [])]`
     (:212-213, `duringSelection: true`; a window capture excludes nothing); `world.selector.selects == [Select(mode: .window,
     freeze: nil, preselect: nil)]`; `lastAreaRect == stored` (the `.window` arm of `runSelection` stores nothing, :212-213);
     one PNG on the clipboard decoding 300 x 200 at scale 1; `.notice(title: "Image copied", body: "300 × 200 px", subtitle: nil)`;
     `world.shutterCount == 1`; `world.selector.dismissCount == 1` (:215). No window background (`settings.windowBackground` defaults false, AppSettings.swift:297).
  2. `captureFullscreen(intent: copy)`: `captures[1] == Cap(target: .display(FakeCaptureSource.display), options: options,
     excludedWindowIDs: [])` (:9-10: the display under the pointer by `captureSource.displayUnderPointer`, no card windows);
     `lastAreaRect == stored` (no store anywhere in :6-13); `.notice(... body: "1440 × 900 px")`; `shutterCount == 2`.
  3. `captureArea(at: urlArea, intent: copy)`: `captures[2] == Cap(target: .area(rect: urlArea.rect, display: FakeCaptureSource.display),
     options: options, excludedWindowIDs: [])` (:175); `lastAreaRect == StoredRect(urlArea.rect)` (:177, after the capture
     succeeded); `.notice(... body: "200 × 120 px")`.
  4. `capturePreviousArea(intent: copy)`: `captures[3] == Cap(target: .area(rect: urlArea.rect, display: FakeCaptureSource.display),
     options: options, excludedWindowIDs: [])` (the URL rect is what ⌃⇧6 captures again, :150-158; inside display 1, so unclipped);
     `lastAreaRect == StoredRect(urlArea.rect)`; `.notice(... body: "200 × 120 px")`; `shutterCount == 4`.
  5. `world.source.captureFailure = FakeCaptureError()`; `captureArea(at: failedArea, intent: copy)`: `captures.count == 5` and
     `captures[4].target == .area(rect: failedArea.rect, display: FakeCaptureSource.display)` (the fake records before it
     throws); `lastAreaRect` still `StoredRect(urlArea.rect)` (`guard let result` returns before the store, :175-177);
     `world.logLines == ["Capture failed: The fake source failed."]` (:383); the last notifier call is `.error(title: "Capture failed",
     message: "The fake source failed.")` (:384, Notifier.swift:180); `shutterCount` still 4. Then `captureFailure = nil`.
  6. `captureScrolling(intent: CaptureIntent(action: .save))` with the 400 x 100 drag: `lastAreaRect == StoredRect(drag)` (stored at
     :125 once the check passes, and the check is `>=`, so exactly 100 pt passes, :119); no notice is added; `world.selector.selects.last
     == Select(mode: .scrolling, freeze: nil, preselect: nil)`; `world.selector.dismissCount == 2` (one from step 1's `runSelection`, :215, one from :127); `!coordinator.isCapturing`;
     `!coordinator.scrollCapture.isRunning`; `world.source.captures.count` still 5. The call stops at the test-built display's
     missing `live` object, which is what stands for the session (judge 2.4).
- Notifier calls at the end, whole: `[.notice(title: "Image copied", body: "300 × 200 px", subtitle: nil), .notice(... "1440 × 900
  px"), .notice(... "200 × 120 px"), .notice(... "200 × 120 px"), .error(title: "Capture failed", message: "The fake source
  failed.")]`.
- By hand / seam: a scrolling session on the accepted area, and its stitched image stored only once saved for a preselected
  rect (+Capture.swift:133-136): `SCROLL`. A window click turning into a scrolling area is `SelectionController.finishPick` (:330-340): `SELINT`.
  The relaunch is D (AppSettingsTests.swift:57). A `capture-area` URL's geometry is D (URLCommandGeometryTests). The Capture
  Fullscreen step uses `pointerDisplayID` nil; which display is under the pointer is `CaptureEngine.display(under:in:)` (moved from
  `AppCoordinator.display(under:in:)`, +Capture.swift:398-402), unchanged and not tested here.
  capture, not after a failure, and ⌃⇧6 captures it again; part), phase-5:78 (exactly 100 pt is accepted as far as the session; part).

### CAPSRC.5 Added to existing suites, and support

#### C8 a step in `aSecondRecordPressWhileTheMicrophonePromptIsUpAsksNothingAndAQuitStartsNothing` (S; CoordinatorRecordingTests, CRT:353)

The existing test holds a start at the microphone prompt, presses Record again, quits before the answer, and asserts the
refusal as a predicate (`capturesRefused`, `captureRefusal == .permissionPrompt(.microphone)`, CRT:363-364). Its doc says
"every capture is refused for the prompt" and leaves "the disabled menu items, the dropped URL command's log line and the
recording that starts after the answer" with the line's seams. What the predicate cannot show is the checklist's own claim for
the shortcuts: "each capture shortcut (⌃⇧1 to ⌃⇧7, and the self-timer's) does nothing, no selection overlay or countdown shows, and
no capture appears". With the fake source and selector that is observable: nothing reads the screen and nothing asks the overlay.

- Entry points: the eight capture entry points, each with `CaptureIntent(action: .save)` (CAPSRC.2): `captureAllInOne(intent:)` (⌃⇧1),
  `captureWindow(intent:)` (⌃⇧2), `captureFullscreen(intent:)` (⌃⇧3), `captureArea(intent:)` (⌃⇧4), `captureScrolling(intent:)`
  (⌃⇧5), `capturePreviousArea(intent:)` (⌃⇧6), `captureText()` (⌃⇧7) and `captureSelfTimer(intent:)`.
- Placement: after the existing `#expect(coordinator.captureRefusal == .permissionPrompt(.microphone))` (CRT:364) and before `let
  second = ...`. Each entry runs as `TaskWatch(Task { ... })` and the test waits with `try await eventually { watch.hasReturned }`,
  one at a time. The prompt is still held (`microphones.isAsking`), so the start has not taken the lock (it takes it after the
  prompts, +Recording.swift:211, :248) and `isCapturing` is false: each entry is refused by `withCaptureLock` at Coord:573
  (`captureScrolling` first reads `scrollCapture.isRunning`, +Capture.swift:82, false). The quit block at the end of the existing
  test is unchanged and still ends the start before the lock (`if isQuitting { return nil }`, +Recording.swift:340), so nothing
  makes `tmp/Recording`.
- New assertions, after the eight: `world.source.contentReads == 0`; `world.source.captures.isEmpty`;
  `world.source.windowLookups.isEmpty`; `world.selector.selects.isEmpty`; `world.selector.allInOnes.isEmpty`;
  `world.selector.dismissCount == 0`; `world.notifier.calls.isEmpty`; `world.cards.calls.isEmpty`;
  `world.clipboard.copies.isEmpty`; `coordinator.history.records.isEmpty`; `world.shutterCount == 0`;
  `coordinator.askingPermission == .microphone`; `!coordinator.isCapturing`. The test's final `world.notifier.calls ==
  [.waited(.seconds(1))]` still holds.
- Also, for the line's first clause, after `second` returns: `world.recordingLines == ["Recording: start ignored, the microphone
  prompt is open"]` (+Recording.swift:293, `prompt.name` is `microphone`, Coord:599), and at the end, after the quit and the
  answer, `world.recordingLines == [that, "Recording: microphone access refused at the prompt"]` (+Recording.swift:339 with
  `granted` false); `world.logLines.isEmpty`. These are LOG's lines (the camera form is already asserted, CRT:484); the
  microphone form is the same statement.
- By hand / seam: the status menu's disabled capture items, Record Screen and Record Fullscreen among them (`STATUSMENU`); the
  URL command's `dropped, the microphone prompt is open` line is the handler's `NSLog` (UCH:155, `URLLOG`) and its text is D
  (URLCommandHandlerTests.swift:227); that the recording starts as usual after the answer needs `TMPDIRS` and `RECCHROME` (CAPSRC.1).

#### C9 `aWidthChangeOrTheLockToggleArmsADisarmedRect(control:)` (S; SelectionViewArmingTests; optional, Tim's call 2; no seam)

Not a CAPSRC test: the seam adds nothing to it. It is the one piece of phase-6b:105 that has no test, and the judge left it to
Tim (judge section 4, call 2). The view is built as `SelectionViewArmingTests.makeView()` builds it (SelectionViewArmingTests.swift:16-27:
a borderless `NSWindow` of 1000 x 800 that is never shown, the view in `.allInOne` mode, `onAllInOneAction` and `onCancel` recorded).

- Entry point: the toolbar's two closures, `onSize` and `onToggleLock` (SelectionView.swift:557, :566; `AllInOneToolbar.onSize:
  ((Int?, Int?) -> Void)?`, `onToggleLock: (() -> Void)?`, AllInOneToolbar.swift:9-10). The toolbar is `private var toolbar`
  (SelectionView.swift:83), so the test finds it as a subview: `view.subviews.compactMap { $0 as? AllInOneToolbar }.first`. It exists
  once `beginAdjusting(rect, fromWindow: false, armed: false)` has laid it out (`layoutToolbar` makes it, SelectionView.swift:447,
  :535-548). No `private` member is opened.
- Input: `rect = CGRect(x: 100, y: 100, width: 400, height: 200)` (the suite's own, SelectionViewArmingTests.swift:9).
- Arguments: `control`: `.size` (call `toolbar.onSize?(500, nil)`) and `.lock` (call `toolbar.onToggleLock?()`).
- Assertions: before the call `!view.keyCaptureArmed`; after it `view.keyCaptureArmed` (SelectionView.swift:559, :568); then a Return key
  (`key(36, "\r", in: window)`, SelectionViewArmingTests.swift:29-33) gives `fired.actions == [.capture]`. For `.size` also `view.adjustRect ==
  CGRect(x: 100, y: 100, width: 500, height: 200)` (`SelectionAdjust.sized`: the width 500, the height kept, the rect grows from its top-left
  corner, `y = maxY - h = 300 - 200`, SelectionAdjust.swift:166-187, inside the 1000 x 800 bounds); for `.lock` also `view.isAspectLocked`.
- By hand / seam: Return typed in another app as the overlay appears (C).


#### Support and existing-suite edits (the judge 2.6, unchanged)

`CoordinatorWorld` gains `source` and `selector` and the two environment arguments; `CoordinatorWorldTests.aCoordinatorOverTheWorldKeepsToTheWorld`
(CoordinatorWorldTests.swift:14-36) gains `world.source.contentReads == 0`, `world.source.captures.isEmpty`,
`world.selector.selects.isEmpty`, `world.selector.allInOnes.isEmpty` after its `saveAsChooser.asked.isEmpty` check (:35);
`CoordinatorCaptureTests.aCaptureWhileTheLockIsHeldReturnsAtOnceAndPostsNothing(entry:)` gains `#expect(world.source.contentReads
== 0)` after its last no-effect check, and its doc (":6-7: would read the shareable content, which the suite never reaches") is
reworded to the count. Neither edit is a line's test.

### CAPSRC.6 Marks, as the merged checklists should read

Form as `docs/testing/phase-6a-manual-checklist.md`: `(suite[, in part]: Suite.test, ...; by hand: ...)`. `CCS` below stands for
`CoordinatorCaptureSourceTests`; the merged marks spell it out.

| Line | Merged mark |
|---|---|
| phase-5:78 | (suite, in part: CCS.aScrollingAreaUnder100PointsIsRefusedAndTheNextShortcutWorks, CCS.windowAndFullscreenCapturesLeaveThePreviousAreaAndAScrollingDragStoresIt (a 100 pt drag passes the check); by hand: the session starting on the accepted area (`SCROLL`), the drag in the overlay) |
| phase-6a:209 | (suite: CCS.capturePreviousAreaWithNoUsableStoredAreaIsRefusedAndCapturesNothing, PreviousAreaTests.noRectResolvesToNone, AppSettingsTests.lastAreaRectRoundTripsThroughASecondInstanceAndClears) |
| phase-6a:211 | (suite, in part: CCS.windowAndFullscreenCapturesLeaveThePreviousAreaAndAScrollingDragStoresIt, CCS.aScrollingAreaUnder100PointsIsRefusedAndTheNextShortcutWorks, AppSettingsTests.lastAreaRectRoundTripsThroughASecondInstanceAndClears; by hand: a scrolling session on the accepted area (`SCROLL`), a window click becoming the scrolling area (the overlay's own, `SELINT`)) |
| phase-6a:214 | (suite: CCS.capturePreviousAreaWithNoUsableStoredAreaIsRefusedAndCapturesNothing, PreviousAreaTests.aRectLeavingUnderOnePointOnItsDisplayIsOffScreen) |
| phase-6b:62 | (suite, in part: CCS.allInOneOpensOnThePreviousAreaArmedOrAURLRectDisarmedAndEscapeStoresNothing, SelectionAdjustTests.restoreKeepsARectOnItsDisplay, .restoreRefusesARectOffEveryDisplay; by hand: the rect shown selected and adjustable, and none when its display is unplugged (SelectionController.placePreselected, `SELINT`)) |
| phase-6b:104 | (suite, in part: CCS.allInOneOpensOnThePreviousAreaArmedOrAURLRectDisarmedAndEscapeStoresNothing, URLCommandHandlerTests.everyCommandReachesItsCaptureFunction, URLCommandGeometryTests.theOriginIsTheBottomLeftOfTheMainDisplay; by hand: the rect shown adjustable on the overlay (`SELINT`)) |
| phase-6b:105 | (suite, in part: CCS.allInOneOpensOnThePreviousAreaArmedOrAURLRectDisarmedAndEscapeStoresNothing, SelectionViewArmingTests.aDisarmedRectIgnoresReturnUntilAPress, .aDisarmedRectStillNudgesAndCancels, .aDoubleClickCapturesOnlyWhenArmedBeforeIt, .aNewRectIsArmed, URLCommandHandlerTests.everyCommandReachesItsCaptureFunction; by hand: arming by a W change or the lock toggle, and Return typed in another app as the overlay appears); with C9 the first by-hand item goes and the suite list gains `SelectionViewArmingTests.aWidthChangeOrTheLockToggleArmsADisarmedRect` |
| phase-6b:127 | (suite, in part: CCS.windowAndFullscreenCapturesLeaveThePreviousAreaAndAScrollingDragStoresIt; by hand: a capture-scrolling rect becoming the previous area only once the stitched image is saved (`SCROLL`)) |
| phase-6b:159 | (suite, in part: CCS.aHeldSelectionOpensOneWindowAndDropsEveryOtherURLCaptureCommandWithoutReadingOrPosting, URLCommandHandlerTests.captureCommandsAreDroppedWhileCapturesAreRefused, .theLogSaysWhyACaptureCommandWasDropped; by hand: while a self-timer counts (`STAGE`), and during a scrolling session before and after Start (`SCROLL`)) |
| phase-6b:160 | (suite: CCS.aHeldSelectionOpensOneWindowAndDropsEveryOtherURLCaptureCommandWithoutReadingOrPosting, URLCommandHandlerTests.captureCommandsAreDroppedWhileCapturesAreRefused) |
| phase-7b:81 | (suite: CCS.capturePreviousAreaAfterCaptureTextCapturesTheEarlierImageArea) |
| recording-r2:351 | (suite, in part: CoordinatorRecordingTests.aSecondRecordPressWhileTheMicrophonePromptIsUpAsksNothingAndAQuitStartsNothing, URLCommandHandlerTests.theLogSaysWhyACaptureCommandWasDropped; by hand: the status menu's capture items shown disabled (`STATUSMENU`), and the recording that starts as usual after the answer (`TMPDIRS`, `RECCHROME`)) |
| recording-r4:217 | see the end of this subsection |
| the other 21 deferred lines | none (CT-3's practice for a deferred line); the first blocker is in CAPSRC.1 |


### CAPSRC.7 Where this note differs from the judge and the lines file

1. **recording-r2:351 moves from deferred to part.** The judge deferred it for `STATUSMENU`, `TMPDIRS`, `RECCHROME`. Its
   "captures are blocked while the prompt is up" clause is observable with the fake source (`contentReads == 0`, no overlay
   asked), and its first clause's log line is LOG's. C8 adds that to the existing test. Counts: judge 4 full, 7 part, 23
   deferred; here 4, 8, 22.
2. **C6 covers no part of phase-6b:159.** The judge's 2.8 row for it reads `phase-6b:159 (nothing)`; the test holds
   nothing, so the open-selection leg is C3's alone.
3. **C7 uses a 100 pt drag, not 120**, to pin the boundary (`rect.height >= 100`, +Capture.swift:119) as well as the store, and
   adds ⌃⇧6 recapturing the URL rect (phase-6b:127's "captures it again") and the failed-capture leg (a rect is stored only
   once captured, +Capture.swift:175-177). The judge's section 2.8 row has neither.
4. **C3 needs `world.settings.urlCommandsAllowSilent = true`.** `capture-fullscreen` is `capturesWithoutSelection`
   (URLCommand.swift:70) and the default is false (AppSettings.swift:291), so without it the gate posts a refusal (UCH:146-150)
   and the test's `post` guard fails. The judge's row does not say so.
5. **C3's `handleURL` reference.** The judge cites `Coord:360-362`; at 5c2cc33 `handleURL` is `Coord:367-369`.
6. **Every call passes an explicit intent** (CAPSRC.2). The judge's tests do; the three added here do too. A forgotten
   default would read `AppSettings.shared`.
7. **recording-r1:105 needs only `TMPDIRS` (with CAPSRC)** (CAPSRC.1). seams.md section 4 lists it with no other seam and the judge
   said it is wrong; the correction is that it is also the one recording line `TMPDIRS` finishes by itself. What seams.md records at close-out,
   this line and the 16 deferred recording lines joining `TMPDIRS` included, is the design's section 11, which wins over this note.
8. **recording-r4:217 is not finished by `TMPDIRS` and CAPSRC** (CAPSRC.1): CT-3's note (small-seams `LOG.7`, `LOG.10`) and the judge
   section 2.9 say it is. The hand-off's `NSScreen.screens` read and `NSApplication.shared.deactivate()` remain.
9. **No recording line completes on `TMPDIRS` and CAPSRC except recording-r1:105** (CAPSRC.1, item 3). A small screen lookup on
   `AppEnvironment`, or `STAGE`'s, is the next seam every recording line needs; seams.md section 15 names it for the count-in only.
   This is for Tim and the next phase's design, not CT-4.
10. **phase-6b:62's second sentence** ("store an area on the second display, unplug it, press ⌃⇧1: it opens with no rect") is not
    reached by the coordinator: `captureAllInOne` passes the stored rect whatever the displays are (+Capture.swift:38), and the
    overlay drops it (`placePreselected`, SelectionController.swift:137-148). It stays `SELINT`'s.
11. **"restore still runs"** (the judge's prose for the catalogue's tests 3 and 8, phase-6b:159) is not asserted by C3: it is the handler's
    routing (D) and `restoreClosedOverlay` has its own tests (CoordinatorOverlayTests.swift:66).

Open points for the plan, beyond the judge's section 4 (build CAPSRC now, 6b:105's last piece, the Vision run, the live handle):

- Take C9 (S, no seam, no production change)? It takes phase-6b:105's arming to its by-hand C remainder only.
- C8 edits an existing held test rather than adding a parameterized one; a parameterized version (the eight entries as
  arguments, its own held prompt) costs about 25 lines of repeated set-up and adds eight cases to the count. The plan takes the
  edit unless told otherwise.

## 5. What the two seams share

From the judge (sections 2.2 and 3). Each seam is one plan task on `capture-seams` (its production diff, its support, its tests, its marks in `docs/testing/` and its row in seams.md); TARGET first.

- `TidyShot/Capture/CaptureTarget.swift`: TARGET adds `CaptureTarget.origin` and `CaptureOrigin`; CAPSRC rewrites lines 1-9 (the value types) and appends `CaptureError.notListed`. The two
  diffs touch disjoint lines, and `CaptureTarget.origin` compiles unchanged over the value types.
- `TidyShotTests/Support/`: TARGET adds `CaptureSamples.swift` (a `nonisolated` enum: images, origins, `fileNames(in:)`); CAPSRC adds `CaptureSourceFakes.swift` and edits `CoordinatorWorld.swift` (the members
  `source` and `selector` and their two environment arguments). TARGET changes no `CoordinatorWorld` member.
- `TidyShotTests/CoordinatorWorldTests.swift`, `aCoordinatorOverTheWorldKeepsToTheWorld`: CAPSRC adds four `#expect`s (`source.contentReads == 0`, `source.captures.isEmpty`, `selector.selects.isEmpty`,
  `selector.allInOnes.isEmpty`); `CoordinatorCaptureTests.aCaptureWhileTheLockIsHeldReturnsAtOnceAndPostsNothing(entry:)` gains `#expect(world.source.contentReads == 0)`. They are checks, not tests.
- No suite receives tests from both seams. `CoordinatorRecordingTests` receives C8's step, and `SelectionViewArmingTests` C9 if taken.
- No line is in both seams' tables. TARGET lines that name `CAPSRC` for a remainder (coordinator-split:36, phase-6b:66, phase-7c:182) keep it: which origin each entry point builds is not tested by T5, T10 or T14.
  Once CAPSRC lands those lines can be driven from the real entry points (`capturePreviousArea`, `captureFullscreen`, `captureAllInOne` with `choices = [.area(...)]`, the handler's `action=` forms)
  and their marks tightened; that is not counted here.
- The rules of TARGET.2 (explicit intent, a stored folder or copy-only, `showOverlay = false`, the held upload idiom) apply to C4 and C7, which reach a copy-only save.

## 6. Suite files and totals

### 6.1 Suite files

| Suite file | New or existing | Tests added | Seam | Of them parameterized |
|---|---|---|---|---|
| `TidyShotTests/CoordinatorCaptureSaveTests.swift` | new | 21 | TARGET | 8 (T4, T5, T8, T9, T10, T11, T14, T15) |
| `TidyShotTests/CoordinatorCaptureSourceTests.swift` | new | 7 | CAPSRC | 1 (C1) |
| `TidyShotTests/CoordinatorRecordingTests.swift` | existing | 0 (C8 adds a step to the test at CRT:353) | CAPSRC | 0 |
| `TidyShotTests/SelectionViewArmingTests.swift` | existing | 0 (1 if Tim takes C9, not counted) | CAPSRC, no seam | (C9: 2 arguments) |
| `TidyShotTests/Support/CaptureSamples.swift` | new support, no suite | 0 | TARGET | |
| `TidyShotTests/Support/CaptureSourceFakes.swift` | new support, no suite | 0 | CAPSRC | |
| `TidyShotTests/Support/CoordinatorWorld.swift`, `CoordinatorWorldTests.swift`, `CoordinatorCaptureTests.swift` | existing support (section 5) | 0 | CAPSRC | |
| **All** | | **28** | | |

### 6.2 Totals per seam

| Seam | Tests | Lines | Full | In part | Deferred (to) | Obsolete or already covered | Earlier marks extended |
|---|---|---|---|---|---|---|---|
| TARGET | 21 | 34 | 19 | 13 | 2 (`FOLDER` 1: phase-1:39; `BGFILL` 1: phase-7c:117) | 0 | 4 (phase-4a:119, :120, phase-6b:118, phase-7c:187) |
| CAPSRC | 7 (plus C8 as a step, C9 optional) | 34 | 4 | 8 | 22 (`TMPDIRS` 17, `STAGE` 3, `SCROLL` 1, `COVERS` 1) | 0 | 0 extended; 1 reworded (recording-r4:217) |
| **All** | **28** | **68** | **23** | **21** | **24** | **0** | **4**, and 1 reworded |

- Full (23): TARGET 19 (phase-1:36, :45; phase-2:30, :32; phase-3:48, :49; phase-5:179, :202; phase-6b:115, :116, :117; phase-7c:184, :185, :186, :188, :190, :197; small-tweaks:13, :16),
  CAPSRC 4 (phase-6a:209, :214; phase-6b:160; phase-7b:81).
- In part (21), by what stays. Another seam's: 19. TARGET 12 (coordinator-split:36 `SCREENS`, `WORKSPACE`, `CAPSRC`; coordinator-split:42 `SCREENS`, `STATUSMENU`; phase-2:25 `SCREENS`; phase-2:33 `UPLOADFORM`;
  phase-2:48 `SCREENS`; phase-4a:119 and :120 `EDPLACE`; phase-6b:66 `SCREENS`, `CAPSRC`; phase-6b:118 `PINS`; phase-7c:179 `SCREENS`; phase-7c:182 `CAPSRC`, `SCROLL`; phase-7c:187 `BGPOP`, `EDPLACE`);
  CAPSRC 7 (phase-5:78, phase-6a:211, phase-6b:127 `SCROLL`; phase-6a:211, phase-6b:62, :104 `SELINT`; phase-6b:159 `SCROLL`, `STAGE`; recording-r2:351 `STATUSMENU`, with `TMPDIRS` and `RECCHROME`).
  By hand with no seam: 2 (TARGET phase-7c:189, `no bitmap could be made`, by code reading; CAPSRC phase-6b:105, Return typed in another app, and arming by a width change or the lock unless C9 is taken).
  Several part lines also keep a by-hand remainder beside a seam (the Slack link in phase-2:25, Wi-Fi off in phase-2:48, the audible shutter in coordinator-split:36).
- Deferred (24) and why: TARGET phase-1:39 needs `FOLDER` (the no-folder branch is behind `chooseFolder`'s `NSOpenPanel`), phase-7c:117 `BGFILL` (`CustomBackgroundStore.shared`); CAPSRC: 17 recording lines
  stop at `TMPDIRS` first (`recordingCanStart` makes the container's real `tmp/Recording` before the content read), phase-6b:75, :77, :79 at `STAGE`, phase-5:182 at `SCROLL`, phase-7b:96 at `COVERS`.
  recording-r1:105 is the one recording line that `TMPDIRS` with CAPSRC finishes alone; recording-r4:217 is not finished by them (CAPSRC.1).
- seams.md counts that change: the design's section 11 gives them (the 30 new seam slots, the new totals and every changed row, `TARGET` 34 / 20 / 22,
  `CAPSRC` 37 / 5 / 5, `TMPDIRS` 30 / 7 / 8 among them) and wins over any figure in this note.
- Effort (the entries give each test's): S 12, M 15, L 2 over the 28 tests and C8 (section 1.3). TARGET S 7, M 12, L 2; CAPSRC S 5 (C1, C2, C5, C6, C8), M 3 (C3, C4, C7).

### 6.3 Expected suite line

Baseline at 5c2cc33: `Test run with 2352 tests in 195 suites passed`. Plus 28 tests (each new `@Test` function once; T4, T5, T8, T9, T10, T11, T14, T15 and C1 count once each; C8 adds a step, no
function) and 2 suites (the two new files, `CoordinatorCaptureSaveTests` and `CoordinatorCaptureSourceTests`; `CaptureSamples.swift` and `CaptureSourceFakes.swift` hold no tests and the other suites already count):

`Test run with 2380 tests in 197 suites passed`

With Tim's optional C9: 2381 in 197. TARGET alone (CAPSRC deferred): 2373 in 196 (the judge's 2372 plus T21), 2374 with C9. The catalogues' own figures were 2373 (TARGET) and 2380 (CAPSRC on the judge's 2372);
the merge removes one CAPSRC test and keeps T21, so the sum is 2352 + 21 + 7. Known noise is as in the context note; the flaky `UploadQueueTests.aSidecarUnwritableDuringThePartsFailsTheJobBeforeComplete` fails about one
full run in six, and a run that fails only on it passes on a second.
