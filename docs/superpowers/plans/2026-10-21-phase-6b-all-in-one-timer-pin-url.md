# TidyShot Phase 6b: All-in-One, Self-Timer, Pin and URL Scheme, Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** New ways to start a capture: All-in-One mode (one hotkey, adjustable selection, a small toolbar to pick area, window or fullscreen and an action), Self-Timer, Pin to screen, and the `tidyshot://` URL scheme with a gate for silent captures.

**Architecture:** Spec 2.9 (the 6b parts). Pure helpers carry the decisions (selection adjust geometry, toolbar placement, the All-in-One choice, pin geometry, URL command parsing, geometry and the gate); the selection overlay gains an All-in-One mode; Self-Timer and Pin are small controllers with panels; the URL scheme is handled by an Apple-event handler in AppDelegate and routed to the existing capture commands through `AppCoordinator`, the one save, upload and delete path.

**Tech Stack:** Swift 6 language mode with default `MainActor` isolation and `NonisolatedNonsendingByDefault`, AppKit (`NSPanel`, `NSDraggingSource`, `NSSavePanel`, `NSMenu`), SwiftUI (`NSHostingView`), ScreenCaptureKit, KeyboardShortcuts, Swift Testing, XcodeGen 2.46.

Spec: `docs/superpowers/specs/2026-10-19-tidyshot-screenshot-design.md`, section 2.9 (the 6b parts binding, including its decisions, which Tim confirmed with the 6a plan PR) and section 6 (Phase 6). Section 2.9 is the authority for behaviour, names and exact strings; when this plan and 2.9 disagree, stop and ask.

Builds on Phase 6a (merged as PR 13, 4c67c04). Work happens on the branch `phase-6b-polish`, created from `main` at 4c67c04. Confirm:

```bash
git switch phase-6b-polish
git merge-base --is-ancestor 4c67c04 HEAD && echo BASE_PRESENT
```
Expected: `Already on 'phase-6b-polish'` (or `Switched to branch 'phase-6b-polish'`) then `BASE_PRESENT`.

## How code is specified in this plan

Each task gives the exact Swift interfaces it produces, complete Swift Testing test code, and complete code for pure helpers and algorithms (the selection adjust geometry, the toolbar placement and buttons, the self-timer countdown and badge placement, the pin geometry, opacity and keys, the URL command parser, its rect geometry, the gate, the handler and the capture intent). AppKit windows, the panels, the SwiftUI views and menu wiring are specified by structure, exact names, behaviour and hand checks, and the implementer writes that code. The tests and the interfaces are the contract: a reviewer rejects a task whose names, signatures, strings or test assertions differ from this plan or from spec 2.9.

These points go beyond 2.9's text, settle what it left open or correct it, and Task 6 writes each into 2.9 (in place where 2.9's sentence changes, and as a line of the "Phase 6b (built)" paragraph):
1. **All-in-One fullscreen.** The Fullscreen button dismisses the overlay first and captures as Capture Fullscreen does: the rect's display, the overlay's windows and the cards excluded, the pointer from Show cursor (`duringSelection: false`), never the crosshair. Capture and Window are taken with the overlay up (`duringSelection: true`).
2. **All-in-One selecting.** With a rect showing, a click outside it without a drag takes the window under the pointer when there is one and otherwise keeps the rect; a drag outside starts a new rect; a new rect on another display clears the first. The Window button stays enabled through a resize, move, nudge or typed size of a window's rect and is dropped by a new drag or a preselect. A handle is within 6 pt of its edge (the nearer side wins on a narrow rect); Return and keypad Enter capture.
3. **All-in-One resize rules.** A moving edge stops 4 pt short of the opposite one (the rect never flips); every result is whole points. With the aspect lock, a corner takes the larger of the pointer's width and its height times the ratio, an edge sets its side and grows the other about the rect's centre, both stop at the display; the ratio kept is the rect's when the lock went on, or when a new rect was set while locked. Typed W and H grow the rect from its top-left corner and move it inside the display; with the lock W wins when both are given.
4. **All-in-One toolbar and start.** The toolbar sits 8 pt below the rect, above it, or inside its bottom edge, 8 pt inside the screen's sides and below the menu bar's safe area, and hides while a drag, resize or move runs. A field's Return applies the value and gives focus back to the selection, its Escape reverts it. All-in-One's start rect comes through `selectAllInOne(content:freeze:preselect:)`: a URL command's rect, else `lastAreaRect`; a preselect does not write `lastAreaRect`.
5. **Focus loss (corrects 2.9's Risks).** 2.9 says focus loss when another app activates cancels the selection, "as now"; no selection mode does that today, and 6b does not add it. The All-in-One overlay, like the others, stays up until Escape, Cancel or a choice. The key routing is tested through `SelectionAdjust.keyCommand`, not KeyRouting.
6. **Self-Timer.** After the overlay is dismissed TidyShot gives up activation (`NSApplication.shared.deactivate()`) so the user's app keeps its menus and keys during the countdown; the badge is kept inside its screen. At zero the shareable content is read again and the display or window found by id; a window that is gone posts `The window is no longer on screen.` and a display that is gone `The display is no longer connected.`, both titled `Self-timer`. A picked window does not write `lastAreaRect`. A stored `selfTimerSeconds` other than 3, 5 or 10 reads as 5. The shared Escape hotkey cancels whichever of the countdown and the scrolling session runs.
7. **Pin.** The downsample is `ThumbnailMaker.scaled(_:maxSide:)`, new in Task 4, not `thumbnail(from:maxSide:)`, which cuts a tall image to its top and would pin a scrolling capture as a sliver (corrects 2.9). A second Pin on a capture that is pinned brings its pin forward. The spot a pin opens over is `latestCaptureArea`, the newest capture's area rect, set in `save(_:intent:)` right after the record exists. A pin opens without taking the keyboard; it becomes key when clicked. A strip already under 40 pt keeps its short side as the floor. The status menu's pin items are not disabled during a capture. Load failures are titled `Could not pin the capture`, the download `Pinning the capture…`, a failed downsample `The capture is too large to pin.`
8. **CaptureIntent and the sender.** `CaptureIntent` (`Capture/CaptureIntent.swift`) also carries `sender`, and `.standard` is read when the capture starts. Every URL notification (refusals, errors, `Image copied`) carries `From <sender>` as its subtitle when the sender is known; `URLCommandGate.decision(for:enabled:allowSilent:sender:)` names it in the silent refusal. `Notifier.notifyError` and `notify` gain `subtitle:`. `AfterCaptureAction` becomes `nonisolated` and `Sendable`. `action=copy` plays the shutter sound and posts the pixel size as the body of `Image copied`.
9. **Two new URL error strings.** `“<name>” is given more than once.` for a repeated parameter a command takes (found before any value is checked), and `The area leaves less than a point on display <n>.` for a rect clipped to less than 1 pt.
10. **URL number limits.** A rect value is a plain decimal (an optional `-`, digits, at most one `.` with digits on both sides), at most 16 characters and 100,000 pt; `display` is 1 to 99 in ASCII digits, checked for form and otherwise used only with a rect; values in messages lose control and format characters and are cut at 40 characters with `…`; at most 8 URLs wait for `start()`. Names and actions match ignoring case after percent-decoding. With URL commands off even an unparseable URL gets the off message.
11. **capture-scrolling with a rect** skips the selection: the session panel opens on the rect (TidyShot is activated so Return is Start), refused under 100 pt with the Phase 5 message, and nothing is captured until Start. A URL rect for `capture-area` is stored as `lastAreaRect`.
12. **Code structure.** `URLCommandHandler` with the `URLCommandTarget` protocol and its own suite (`URLCommandHandlerTests`); `.cancelScrollingCapture` renamed in code to `.cancelCapture` (stored name unchanged) with every test that names it; `SelectionController.init(engine:settings:cardWindowNumbers:)`; `CaptureTarget.cgFrame` and `areaRect`.

## Global Constraints

- Every Phase 0 to 3.1 constraint still applies: minimum macOS `26.0`, Xcode 27.1 with the macOS 27.0 SDK, App Sandbox on with no new entitlements, Swift 6 language mode with `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` and `SWIFT_APPROACHABLE_CONCURRENCY = YES`, `KeyboardShortcuts` as the only package, credentials only in the Keychain, files in the save folder only through the security-scoped bookmark, thumbnails and upload-only files in the container next to `history.json`, one token engine for file names and object keys, keys named when the upload starts, HEAD before PUT for template keys, and no GPL-licensed code read or copied.
- New code lives where spec 2.9 names it (`Capture/`, `Selection/`, `Overlay/`, `Output/`, `App/`, `Settings/`). New tests live in `TidyShotTests/`, shared helpers in `TidyShotTests/Support/`. XcodeGen's recursive source paths pick new folders up; run `xcodegen generate` after adding files.
- Concurrency: any `nonisolated async` function that must run off the main actor is marked `@concurrent`. Tests never block the main actor with a semaphore; fakes wait on an async gate.
- Tests use Swift Testing, run with:
  ```bash
  xcodegen generate && xcodebuild test -project TidyShot.xcodeproj -scheme TidyShot -destination 'platform=macOS' -derivedDataPath .build 2>&1 | grep -E "Test run with|error:|TEST"
  ```
  Baseline `Test run with 686 tests in 85 suites passed`; the totals after each task are in the table below.
- Commit after every task with a conventional commit message and no attribution lines. Never include a Claude Code session URL in a commit or PR. This plan never pushes or opens a PR: the last task stops after its commit, and the controller pushes and opens the PR after the whole-branch review.
- Phase 6b specifics:
  - This plan's Task 1 to Task 6 are spec 2.9's task list items 9 to 14, in that order.
  - Every capture a URL command or the self-timer triggers goes through the existing capture commands in `AppCoordinator`; no new save, upload or delete path.
  - URL scheme security: commands that capture without a user's drag or click (capture-fullscreen, capture-previous-area, capture-area with a rect) run only when the silent-capture setting is on (off by default); a master URL-scheme toggle is on by default; both live in the General tab with the exact strings in spec 2.9. Registering the scheme needs only `CFBundleURLTypes` in project.yml; no new entitlement.
  - Default shortcuts: All-in-One ⌃⇧1. Exact strings come from spec 2.9.
  - Run builds Tim uses as Release (`-configuration Release -derivedDataPath .build-rel`); tests use Debug.

## Test totals

| After | New tests | New suites | Total |
|---|---|---|---|
| Baseline | | | 686 tests in 85 suites |
| Task 1 | 28 | 3 | 714 tests in 88 suites |
| Task 2 | 3 | 0 | 717 tests in 88 suites |
| Task 3 | 13 | 1 | 730 tests in 89 suites |
| Task 4 | 17 | 1 | 747 tests in 90 suites |
| Task 5 | 55 | 5 | 802 tests in 95 suites |
| Task 6 | 0 | 0 | 802 tests in 95 suites |

Task 6 correction: review fixes added 8 tests and no suite after the rows above were written, so every row from Task 1 on is short by the fixes landed up to it: 0b2e1cd +4 after Task 1 (opposite edges stay on half-point drags, and three more edge cases, all in `SelectionAdjustTests`; `AllInOneToolbarPlacementTests` gains an assertion in an existing test), 400d912 +1 after Task 3 (the self-timer badge's level, `SelfTimerTests`), 6c4758b +2 after Task 4 (zoom and actual size in whole points and capped to the screen, `PinGeometryTests`) and 9136820 +1 after Task 5 (a queued capture command after the first is dropped, `URLCommandHandlerTests`). The rows stay as written; with the fixes, Tasks 1 to 5 end at 718, 721, 735, 754 and 810 tests (the suite counts are unchanged), and the real run after Task 6 reads `Test run with 810 tests in 95 suites passed`.

The totals come from each task's declared tests. Task 6 checks them against a real run and adds a note for any difference.

---

### Task 1: Selection adjust geometry

Spec 2.9, All-in-One, item 9. Pure only: the arithmetic and the decisions behind All-in-One's handles, move, nudge, typed size, aspect lock and restored rect; where its toolbar sits; and what the toolbar's buttons are. No AppKit, nothing wired; Task 2 consumes all of it.

**Files:**
- Create: `TidyShot/Selection/SelectionAdjust.swift` (`SelectionHandle`, `SelectionAdjust`)
- Create: `TidyShot/Selection/AllInOneToolbarPlacement.swift` (`AllInOneToolbarPlacement`)
- Create: `TidyShot/Selection/AllInOneChoice.swift` (`AllInOneChoice`, `AllInOneAction`, `AllInOneLock`)
- Test: `TidyShotTests/SelectionAdjustTests.swift` (new, struct `SelectionAdjustTests`), `TidyShotTests/AllInOneToolbarPlacementTests.swift` (new, struct `AllInOneToolbarPlacementTests`), `TidyShotTests/AllInOneChoiceTests.swift` (new, struct `AllInOneChoiceTests`)

**Interfaces:**
- Consumes:
  - `main`: nothing beyond CoreGraphics and ScreenCaptureKit's `SCDisplay` and `SCWindow` (the payloads of `AllInOneChoice`, as `Selection` in `Selection/Selection.swift:12-15` carries them).
- Produces (all used by Task 2; `AllInOneChoice.timer` and `AllInOneAction.timer` by Task 3; `AllInOneChoice` by Task 5):
  - `nonisolated enum SelectionHandle: Equatable, Sendable` with cases `topLeft, top, topRight, right, bottomRight, bottom, bottomLeft, left, inside`; `static let resizeHandles: [SelectionHandle]` (the eight, drawing order); `var movesMinX / movesMaxX / movesMinY / movesMaxY: Bool`; `func point(on rect: CGRect) -> CGPoint?` (the knob's centre; nil for `.inside`).
  - `nonisolated enum SelectionAdjust` (all rects in the selection view's coordinates, bottom-left origin, y up; results are whole points):
    - `static let minSide: CGFloat = 4`, `static let handleTolerance: CGFloat = 6`, `static let nudgeStep: CGFloat = 1`, `static let shiftNudgeStep: CGFloat = 10`
    - `enum Arrow: Equatable, Sendable { case left, right, up, down; init?(keyCode: UInt16) }`
    - `enum KeyCommand: Equatable, Sendable { case capture, cancel, nudge(Arrow) }`
    - `static func keyCommand(keyCode: UInt16, hasRect: Bool) -> KeyCommand?`
    - `static func handle(at point: CGPoint, rect: CGRect, tolerance: CGFloat) -> SelectionHandle?`
    - `static func resized(_ rect: CGRect, handle: SelectionHandle, to point: CGPoint, lockedRatio: CGFloat?, bounds: CGRect, minSide: CGFloat) -> CGRect`
    - `static func moved(_ rect: CGRect, by delta: CGVector, bounds: CGRect) -> CGRect`
    - `static func nudged(_ rect: CGRect, key: Arrow, shift: Bool, bounds: CGRect) -> CGRect`
    - `static func sized(_ rect: CGRect, width: CGFloat?, height: CGFloat?, lockedRatio: CGFloat?, bounds: CGRect) -> CGRect`
    - `static func restored(_ rect: CGRect, displayFrames: [CGRect]) -> CGRect?`
    - `static func fitted(_ rect: CGRect, in bounds: CGRect) -> CGRect`
  - `nonisolated enum AllInOneToolbarPlacement { static let gap: CGFloat = 8; static let margin: CGFloat = 8; static func frame(toolbarSize: CGSize, selection: CGRect, screenBounds: CGRect) -> CGRect }`
  - `enum AllInOneChoice { case area(rect: CGRect, display: SCDisplay); case window(SCWindow); case fullscreen(SCDisplay); case scrolling(rect: CGRect, display: SCDisplay); case timer(rect: CGRect, display: SCDisplay) }` (rects in CoreGraphics global points, clipped to the display; MainActor like `Selection`, because `SCDisplay` and `SCWindow` are not Sendable).
  - `nonisolated enum AllInOneAction: CaseIterable, Equatable, Sendable { case capture, window, fullscreen, scrolling, timer, cancel }` with `var title: String`, `var symbolName: String`, `func help(timerSeconds: Int) -> String`, `func isEnabled(hasWindow: Bool) -> Bool`.
  - `nonisolated enum AllInOneLock { static let help: String; static func symbolName(locked: Bool) -> String }`.

Behaviour (spec 2.9, All-in-One):
- Handles: four corners and four edges, an edge hit anywhere along it within the tolerance, a corner within the tolerance of both of its edges. On a rect narrower than two tolerances the nearer side wins. Inside and not near an edge is `.inside` (a move); further out is nil (a new rect).
- Resize: the handle's edges follow the pointer (clamped to `bounds`), the opposite edges stay, and a moving edge stops `minSide` short of the one opposite it (no flipping). With a lock the ratio holds: a corner takes the larger of the pointer's width and its height times the ratio, so the rect reaches the pointer; an edge sets its own side and grows the other about the rect's centre; both stop at the bounds (the centred side moves inside them).
- Move and nudge keep the size and are clamped inside `bounds`; arrows move 1 pt, Shift-arrows 10 pt.
- Typed size: the rect grows from its top-left corner (`minX`, `maxY` here), is limited to `bounds` and moved inside them; with the lock a typed W sets H and a typed H sets W (W wins when both are given). Minimum side 4.
- Restore: the stored rect (Task 2 converts `lastAreaRect` to AppKit global points first) on the display holding its centre, clipped to it; nil when its centre is on no display or less than 4 pt is left on a side.
- Every result is whole points (`fitted`: origin and size rounded, size limited to the bounds, origin moved inside), as the overlay's drag rect is `integral`.
- Toolbar: centred under the rect with an 8 pt gap; above it when below leaves less than 8 pt to the screen's edge; otherwise inside its bottom edge. Its x is clamped 8 pt inside the screen's sides (the left side wins on a screen narrower than the toolbar). The origin is whole points; the size is the toolbar's own.
- Keys: Escape cancels always; Return and keypad Enter capture and arrows nudge only once a rect exists.

- [ ] **Step 1: Write the failing tests**

`TidyShotTests/SelectionAdjustTests.swift`:
```swift
import CoreGraphics
import Testing
@testable import TidyShot

struct SelectionAdjustTests {
    let bounds = CGRect(x: 0, y: 0, width: 1440, height: 900)
    /// minX 100, maxX 500, minY 100, maxY 300, in the view's coordinates (y up). Ratio 2.
    let rect = CGRect(x: 100, y: 100, width: 400, height: 200)
    let main = CGRect(x: 0, y: 0, width: 1440, height: 900)
    let right = CGRect(x: 1440, y: 0, width: 1920, height: 1080)

    func resize(_ handle: SelectionHandle, to x: CGFloat, _ y: CGFloat, from start: CGRect? = nil,
                ratio: CGFloat? = nil) -> CGRect {
        SelectionAdjust.resized(start ?? rect, handle: handle, to: CGPoint(x: x, y: y), lockedRatio: ratio,
                                bounds: bounds, minSide: SelectionAdjust.minSide)
    }

    func hit(_ x: CGFloat, _ y: CGFloat, on target: CGRect? = nil) -> SelectionHandle? {
        SelectionAdjust.handle(at: CGPoint(x: x, y: y), rect: target ?? rect, tolerance: SelectionAdjust.handleTolerance)
    }

    @Test func eachHandleIsFoundAtItsCornerOrEdge() {
        #expect(hit(100, 300) == .topLeft)
        #expect(hit(300, 300) == .top)
        #expect(hit(500, 300) == .topRight)
        #expect(hit(500, 200) == .right)
        #expect(hit(500, 100) == .bottomRight)
        #expect(hit(300, 100) == .bottom)
        #expect(hit(100, 100) == .bottomLeft)
        #expect(hit(100, 200) == .left)
        #expect(hit(300, 200) == .inside)
        // Within the tolerance, outside the rect, and anywhere along an edge.
        #expect(hit(95, 305) == .topLeft)
        #expect(hit(200, 304) == .top)
        #expect(hit(504, 150) == .right)
        // Beyond the tolerance: a new rect.
        #expect(hit(300, 307) == nil)
        #expect(hit(50, 200) == nil)
        #expect(hit(600, 600) == nil)
    }

    /// Both sides of an 8 pt wide rect are within 6 pt of the middle; the nearer one wins.
    @Test func aNarrowRectGivesTheNearerSide() {
        let narrow = CGRect(x: 100, y: 100, width: 8, height: 200)
        #expect(hit(101, 200, on: narrow) == .left)
        #expect(hit(107, 200, on: narrow) == .right)
        #expect(hit(107, 299, on: narrow) == .topRight)
    }

    @Test func handlePointsSitOnCornersAndEdgeMidpoints() throws {
        #expect(SelectionHandle.resizeHandles.count == 8)
        #expect(!SelectionHandle.resizeHandles.contains(.inside))
        #expect(SelectionHandle.topLeft.point(on: rect) == CGPoint(x: 100, y: 300))
        #expect(SelectionHandle.top.point(on: rect) == CGPoint(x: 300, y: 300))
        #expect(SelectionHandle.right.point(on: rect) == CGPoint(x: 500, y: 200))
        #expect(SelectionHandle.bottomLeft.point(on: rect) == CGPoint(x: 100, y: 100))
        #expect(SelectionHandle.inside.point(on: rect) == nil)
        for handle in SelectionHandle.resizeHandles {
            let point = try #require(handle.point(on: rect))
            #expect(SelectionAdjust.handle(at: point, rect: rect, tolerance: 6) == handle)
        }
    }

    @Test func eachHandleMovesOnlyItsEdges() {
        #expect(resize(.right, to: 600, 0) == CGRect(x: 100, y: 100, width: 500, height: 200))
        #expect(resize(.left, to: 50, 999) == CGRect(x: 50, y: 100, width: 450, height: 200))
        #expect(resize(.top, to: 999, 350) == CGRect(x: 100, y: 100, width: 400, height: 250))
        #expect(resize(.bottom, to: 0, 40) == CGRect(x: 100, y: 40, width: 400, height: 260))
        #expect(resize(.topRight, to: 600, 350) == CGRect(x: 100, y: 100, width: 500, height: 250))
        #expect(resize(.bottomLeft, to: 50, 40) == CGRect(x: 50, y: 40, width: 450, height: 260))
        #expect(resize(.topLeft, to: 50, 350) == CGRect(x: 50, y: 100, width: 450, height: 250))
        #expect(resize(.bottomRight, to: 600, 40) == CGRect(x: 100, y: 40, width: 500, height: 260))
        #expect(resize(.inside, to: 600, 40) == rect)
    }

    /// Dragging an edge past the opposite one stops 4 pt short of it; the rect never flips.
    @Test func resizingStopsAtTheMinimumSide() {
        #expect(resize(.right, to: 50, 200) == CGRect(x: 100, y: 100, width: 4, height: 200))
        #expect(resize(.top, to: 300, 0) == CGRect(x: 100, y: 100, width: 400, height: 4))
        #expect(resize(.bottomLeft, to: 900, 800) == CGRect(x: 496, y: 296, width: 4, height: 4))
    }

    @Test func resizingIsClampedToTheBounds() {
        #expect(resize(.right, to: 2000, 200) == CGRect(x: 100, y: 100, width: 1340, height: 200))
        #expect(resize(.topLeft, to: -50, 1000) == CGRect(x: 0, y: 100, width: 500, height: 800))
        #expect(resize(.bottom, to: 300, -300) == CGRect(x: 100, y: 0, width: 400, height: 300))
    }

    /// A corner takes the larger of the two directions, so the rect reaches the pointer.
    @Test func aLockedCornerKeepsTheRatio() {
        #expect(resize(.bottomRight, to: 600, 40, ratio: 2) == CGRect(x: 100, y: 40, width: 520, height: 260))
        #expect(resize(.topLeft, to: 300, 250, ratio: 2) == CGRect(x: 200, y: 100, width: 300, height: 150))
    }

    @Test func aLockedEdgeGrowsTheOtherSideAboutTheCentre() {
        #expect(resize(.right, to: 700, 123, ratio: 2) == CGRect(x: 100, y: 50, width: 600, height: 300))
        #expect(resize(.top, to: 77, 400, ratio: 2) == CGRect(x: 0, y: 100, width: 600, height: 300))
    }

    @Test func aLockedResizeStopsAtTheBounds() {
        // The corner runs out of room to the right first; the ratio holds.
        let nearRight = CGRect(x: 1000, y: 100, width: 400, height: 200)
        #expect(resize(.bottomRight, to: 1500, -100, from: nearRight, ratio: 2)
                == CGRect(x: 1000, y: 80, width: 440, height: 220))
        // An edge near the top: the centred side would leave the screen and moves inside it.
        let nearTop = CGRect(x: 100, y: 600, width: 400, height: 200)
        #expect(resize(.right, to: 1100, 700, from: nearTop, ratio: 2)
                == CGRect(x: 100, y: 400, width: 1000, height: 500))
    }

    @Test func aLockedResizeKeepsTheMinimumSide() {
        #expect(resize(.bottomRight, to: 101, 299, ratio: 2) == CGRect(x: 100, y: 296, width: 8, height: 4))
    }

    @Test func insideMovesTheRectAndClampsAtEachEdge() {
        func move(_ dx: CGFloat, _ dy: CGFloat) -> CGRect {
            SelectionAdjust.moved(rect, by: CGVector(dx: dx, dy: dy), bounds: bounds)
        }
        #expect(move(50, -30) == CGRect(x: 150, y: 70, width: 400, height: 200))
        #expect(move(-500, 0) == CGRect(x: 0, y: 100, width: 400, height: 200))
        #expect(move(5000, 0) == CGRect(x: 1040, y: 100, width: 400, height: 200))
        #expect(move(0, -500) == CGRect(x: 100, y: 0, width: 400, height: 200))
        #expect(move(0, 5000) == CGRect(x: 100, y: 700, width: 400, height: 200))
        // Fractions round to whole points.
        #expect(move(0.4, 0.6) == CGRect(x: 100, y: 101, width: 400, height: 200))
    }

    @Test func arrowsNudgeByOneOrTenAndStopAtTheEdge() {
        func nudge(_ key: SelectionAdjust.Arrow, shift: Bool = false, _ start: CGRect? = nil) -> CGRect {
            SelectionAdjust.nudged(start ?? rect, key: key, shift: shift, bounds: bounds)
        }
        #expect(nudge(.left) == CGRect(x: 99, y: 100, width: 400, height: 200))
        #expect(nudge(.right, shift: true) == CGRect(x: 110, y: 100, width: 400, height: 200))
        // Up is +y in the view's coordinates.
        #expect(nudge(.up) == CGRect(x: 100, y: 101, width: 400, height: 200))
        #expect(nudge(.down, shift: true) == CGRect(x: 100, y: 90, width: 400, height: 200))
        let corner = CGRect(x: 0, y: 0, width: 400, height: 200)
        #expect(nudge(.left, corner) == corner)
        #expect(nudge(.down, shift: true, corner) == corner)
    }

    @Test func keysMapToCommands() {
        #expect(SelectionAdjust.keyCommand(keyCode: 53, hasRect: false) == .cancel)
        #expect(SelectionAdjust.keyCommand(keyCode: 53, hasRect: true) == .cancel)
        #expect(SelectionAdjust.keyCommand(keyCode: 36, hasRect: true) == .capture)
        #expect(SelectionAdjust.keyCommand(keyCode: 76, hasRect: true) == .capture)
        #expect(SelectionAdjust.keyCommand(keyCode: 36, hasRect: false) == nil)
        #expect(SelectionAdjust.keyCommand(keyCode: 123, hasRect: true) == .nudge(.left))
        #expect(SelectionAdjust.keyCommand(keyCode: 124, hasRect: true) == .nudge(.right))
        #expect(SelectionAdjust.keyCommand(keyCode: 125, hasRect: true) == .nudge(.down))
        #expect(SelectionAdjust.keyCommand(keyCode: 126, hasRect: true) == .nudge(.up))
        #expect(SelectionAdjust.keyCommand(keyCode: 126, hasRect: false) == nil)
        // A, and Tab: not the overlay's.
        #expect(SelectionAdjust.keyCommand(keyCode: 0, hasRect: true) == nil)
        #expect(SelectionAdjust.keyCommand(keyCode: 48, hasRect: true) == nil)
    }

    @Test func typedSizeGrowsFromTheTopLeft() {
        #expect(SelectionAdjust.sized(rect, width: 600, height: nil, lockedRatio: nil, bounds: bounds)
                == CGRect(x: 100, y: 100, width: 600, height: 200))
        // The top edge (maxY 300) stays; the bottom moves.
        #expect(SelectionAdjust.sized(rect, width: nil, height: 250, lockedRatio: nil, bounds: bounds)
                == CGRect(x: 100, y: 50, width: 400, height: 250))
        #expect(SelectionAdjust.sized(rect, width: 300, height: 100, lockedRatio: nil, bounds: bounds)
                == CGRect(x: 100, y: 200, width: 300, height: 100))
    }

    @Test func typedSizeIsClampedAndMovedInside() {
        let nearRight = CGRect(x: 1000, y: 100, width: 400, height: 200)
        func size(_ width: CGFloat?, _ height: CGFloat?) -> CGRect {
            SelectionAdjust.sized(nearRight, width: width, height: height, lockedRatio: nil, bounds: bounds)
        }
        #expect(size(600, nil) == CGRect(x: 840, y: 100, width: 600, height: 200))
        #expect(size(2000, nil) == CGRect(x: 0, y: 100, width: 1440, height: 200))
        #expect(size(nil, 1000) == CGRect(x: 1000, y: 0, width: 400, height: 900))
        #expect(size(0, nil) == CGRect(x: 1000, y: 100, width: 4, height: 200))
    }

    @Test func typedSizeWithTheLockChangesTheOtherSide() {
        func size(_ width: CGFloat?, _ height: CGFloat?) -> CGRect {
            SelectionAdjust.sized(rect, width: width, height: height, lockedRatio: 2, bounds: bounds)
        }
        #expect(size(600, nil) == CGRect(x: 100, y: 0, width: 600, height: 300))
        #expect(size(nil, 100) == CGRect(x: 100, y: 200, width: 200, height: 100))
        // Both given: the width wins.
        #expect(size(600, 50) == CGRect(x: 100, y: 0, width: 600, height: 300))
        // Too large for the screen: both sides shrink together, then the rect moves inside.
        #expect(size(2000, nil) == CGRect(x: 0, y: 0, width: 1440, height: 720))
        // Below the minimum: the short side is 4 pt.
        #expect(size(0, nil) == CGRect(x: 100, y: 296, width: 8, height: 4))
    }

    @Test func restoreKeepsARectOnItsDisplay() {
        #expect(SelectionAdjust.restored(rect, displayFrames: [main, right]) == rect)
        let second = CGRect(x: 2000, y: 500, width: 300, height: 300)
        #expect(SelectionAdjust.restored(second, displayFrames: [main, right]) == second)
        // Across two displays: the display holding the centre keeps its part.
        #expect(SelectionAdjust.restored(CGRect(x: 1300, y: 100, width: 400, height: 200), displayFrames: [main, right])
                == CGRect(x: 1440, y: 100, width: 260, height: 200))
        // A display above the main one (AppKit y up); fractions round.
        let above = CGRect(x: 0, y: 900, width: 1440, height: 900)
        #expect(SelectionAdjust.restored(CGRect(x: 10.4, y: 1000.6, width: 99.8, height: 50), displayFrames: [main, above])
                == CGRect(x: 10, y: 1001, width: 100, height: 50))
    }

    @Test func restoreRefusesARectOffEveryDisplay() {
        // The display it was on is gone.
        #expect(SelectionAdjust.restored(CGRect(x: 2000, y: 100, width: 400, height: 200), displayFrames: [main]) == nil)
        // The centre is on the second display, with 3 pt of the rect on it.
        #expect(SelectionAdjust.restored(CGRect(x: 1437, y: 100, width: 6, height: 200), displayFrames: [main, right]) == nil)
        #expect(SelectionAdjust.restored(CGRect(x: 100, y: 100, width: 3, height: 200), displayFrames: [main]) == nil)
        #expect(SelectionAdjust.restored(.null, displayFrames: [main]) == nil)
        #expect(SelectionAdjust.restored(rect, displayFrames: []) == nil)
    }
}
```

`TidyShotTests/AllInOneToolbarPlacementTests.swift`:
```swift
import CoreGraphics
import Testing
@testable import TidyShot

struct AllInOneToolbarPlacementTests {
    let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
    let toolbar = CGSize(width: 440, height: 36)

    func frame(_ selection: CGRect, screen bounds: CGRect? = nil, toolbar size: CGSize? = nil) -> CGRect {
        AllInOneToolbarPlacement.frame(toolbarSize: size ?? toolbar, selection: selection, screenBounds: bounds ?? screen)
    }

    @Test func belowTheSelectionAndCentred() {
        #expect(frame(CGRect(x: 400, y: 300, width: 600, height: 300)) == CGRect(x: 480, y: 256, width: 440, height: 36))
    }

    @Test func aboveWhenThereIsNoRoomBelow() {
        #expect(frame(CGRect(x: 400, y: 30, width: 600, height: 300)) == CGRect(x: 480, y: 338, width: 440, height: 36))
    }

    @Test func insideTheBottomEdgeWhenNeitherFits() {
        #expect(frame(screen) == CGRect(x: 500, y: 8, width: 440, height: 36))
        #expect(frame(CGRect(x: 100, y: 20, width: 600, height: 860)) == CGRect(x: 180, y: 28, width: 440, height: 36))
    }

    @Test func clampedToTheScreensSides() {
        #expect(frame(CGRect(x: 0, y: 300, width: 100, height: 100)) == CGRect(x: 8, y: 256, width: 440, height: 36))
        #expect(frame(CGRect(x: 1400, y: 300, width: 40, height: 100)) == CGRect(x: 992, y: 256, width: 440, height: 36))
    }

    @Test func aScreenNarrowerThanTheToolbarAlignsItLeft() {
        #expect(frame(CGRect(x: 50, y: 100, width: 100, height: 100), screen: CGRect(x: 0, y: 0, width: 400, height: 300))
                == CGRect(x: 8, y: 56, width: 440, height: 36))
    }

    @Test func screenBoundsWithAnOrigin() {
        #expect(frame(CGRect(x: 150, y: 60, width: 200, height: 100), screen: CGRect(x: 100, y: 50, width: 800, height: 600))
                == CGRect(x: 108, y: 168, width: 440, height: 36))
    }

    @Test func theOriginIsWholePoints() {
        #expect(frame(CGRect(x: 400.5, y: 300, width: 601, height: 300), toolbar: CGSize(width: 441.4, height: 36))
                == CGRect(x: 480, y: 256, width: 441.4, height: 36))
    }
}
```

`TidyShotTests/AllInOneChoiceTests.swift`:
```swift
import Testing
@testable import TidyShot

struct AllInOneChoiceTests {
    /// Left to right after the size fields and the lock, with the symbols and help of spec 2.9.
    @Test func toolbarButtonsInOrderWithTheirSymbolsAndHelp() {
        #expect(AllInOneAction.allCases == [.capture, .window, .fullscreen, .scrolling, .timer, .cancel])
        #expect(AllInOneAction.allCases.map(\.symbolName) == ["camera", "macwindow", "display", "scroll", "timer", "xmark"])
        #expect(AllInOneAction.allCases.map(\.title) == ["Capture", "Window", "Fullscreen", "Scrolling", "Timer", "Cancel"])
        #expect(AllInOneAction.allCases.map { $0.help(timerSeconds: 5) } == [
            "Capture area (Return)",
            "Capture the window with transparent corners",
            "Capture this display",
            "Scrolling capture of this area",
            "Capture this area after 5 seconds",
            "Cancel (Escape)",
        ])
        #expect(AllInOneAction.timer.help(timerSeconds: 10) == "Capture this area after 10 seconds")
    }

    /// Window needs a rect that came from a window click; every other button is always enabled.
    @Test func windowIsEnabledOnlyAfterAWindowClick() {
        #expect(!AllInOneAction.window.isEnabled(hasWindow: false))
        #expect(AllInOneAction.window.isEnabled(hasWindow: true))
        for action in AllInOneAction.allCases where action != .window {
            #expect(action.isEnabled(hasWindow: false))
        }
    }

    @Test func theLockButtonsSymbolFollowsItsState() {
        #expect(AllInOneLock.help == "Lock aspect ratio")
        #expect(AllInOneLock.symbolName(locked: true) == "lock")
        #expect(AllInOneLock.symbolName(locked: false) == "lock.open")
    }
}
```

- [ ] **Step 2: Run the new tests and see them fail**

Run the header's full-suite command. Expected: the build fails with `error:` lines `cannot find 'SelectionAdjust' in scope`, `cannot find type 'SelectionHandle' in scope`, `cannot find 'AllInOneToolbarPlacement' in scope`, `cannot find 'AllInOneAction' in scope` and `cannot find 'AllInOneLock' in scope`. No `Test run` line appears.

- [ ] **Step 3: Implement**

`TidyShot/Selection/SelectionAdjust.swift`:
```swift
import CoreGraphics

/// The eight handles of All-in-One's adjustable selection, plus its inside (a move). In the
/// selection view's coordinates, bottom-left origin: `.top` is the edge at `maxY`.
nonisolated enum SelectionHandle: Equatable, Sendable {
    case topLeft, top, topRight, right, bottomRight, bottom, bottomLeft, left
    case inside

    /// The eight resize handles, in drawing order.
    static let resizeHandles: [SelectionHandle] = [.topLeft, .top, .topRight, .right, .bottomRight, .bottom, .bottomLeft, .left]

    var movesMinX: Bool { self == .topLeft || self == .left || self == .bottomLeft }
    var movesMaxX: Bool { self == .topRight || self == .right || self == .bottomRight }
    var movesMinY: Bool { self == .bottomLeft || self == .bottom || self == .bottomRight }
    var movesMaxY: Bool { self == .topLeft || self == .top || self == .topRight }

    /// Where the handle's knob is drawn: a corner, or an edge's midpoint. Nil for `.inside`.
    func point(on rect: CGRect) -> CGPoint? {
        guard self != .inside else { return nil }
        let x = movesMinX ? rect.minX : movesMaxX ? rect.maxX : rect.midX
        let y = movesMinY ? rect.minY : movesMaxY ? rect.maxY : rect.midY
        return CGPoint(x: x, y: y)
    }
}

/// All-in-One's selection arithmetic (spec 2.9): hit testing, resize, move, nudge, typed size,
/// aspect lock and the restored rect. Pure. Every rect is in the selection view's coordinates
/// (bottom-left origin, y up) or, for `restored`, AppKit global points; `bounds` is the display
/// the rect lives on. Results are whole points, as the overlay's drag rect is `integral`.
nonisolated enum SelectionAdjust {
    static let minSide: CGFloat = 4
    /// How far from an edge, in points, a press still takes that edge's handle.
    static let handleTolerance: CGFloat = 6
    static let nudgeStep: CGFloat = 1
    static let shiftNudgeStep: CGFloat = 10

    enum Arrow: Equatable, Sendable {
        case left, right, up, down

        /// The arrow keys' virtual key codes.
        init?(keyCode: UInt16) {
            switch keyCode {
            case 123: self = .left
            case 124: self = .right
            case 125: self = .down
            case 126: self = .up
            default: return nil
            }
        }
    }

    /// What a key does in All-in-One while no text field is editing.
    enum KeyCommand: Equatable, Sendable {
        case capture
        case cancel
        case nudge(Arrow)
    }

    /// Escape (53) cancels always. Return (36) and keypad Enter (76) capture, and arrows nudge,
    /// only once a rect exists. Anything else is not the overlay's (nil).
    static func keyCommand(keyCode: UInt16, hasRect: Bool) -> KeyCommand? {
        if keyCode == 53 { return .cancel }
        guard hasRect else { return nil }
        if keyCode == 36 || keyCode == 76 { return .capture }
        return Arrow(keyCode: keyCode).map(KeyCommand.nudge)
    }

    /// The handle under `point`: a corner within `tolerance` of both its edges, an edge within
    /// `tolerance` anywhere along it, `.inside` further in, nil further out (a new rect). On a
    /// rect narrower than two tolerances both sides are in reach and the nearer one wins.
    static func handle(at point: CGPoint, rect: CGRect, tolerance: CGFloat) -> SelectionHandle? {
        guard !rect.isNull, !rect.isInfinite, rect.width > 0, rect.height > 0 else { return nil }
        guard point.x >= rect.minX - tolerance, point.x <= rect.maxX + tolerance,
              point.y >= rect.minY - tolerance, point.y <= rect.maxY + tolerance else { return nil }
        let toMinX = abs(point.x - rect.minX)
        let toMaxX = abs(point.x - rect.maxX)
        let toMinY = abs(point.y - rect.minY)
        let toMaxY = abs(point.y - rect.maxY)
        let left = toMinX <= tolerance && toMinX <= toMaxX
        let right = !left && toMaxX <= tolerance
        let bottom = toMinY <= tolerance && toMinY <= toMaxY
        let top = !bottom && toMaxY <= tolerance
        switch (left, right, bottom, top) {
        case (true, _, _, true): return .topLeft
        case (true, _, true, _): return .bottomLeft
        case (_, true, _, true): return .topRight
        case (_, true, true, _): return .bottomRight
        case (true, _, _, _): return .left
        case (_, true, _, _): return .right
        case (_, _, true, _): return .bottom
        case (_, _, _, true): return .top
        default: return rect.contains(point) ? .inside : nil
        }
    }

    /// `rect` with `handle` dragged to `point`. The pointer is clamped to `bounds`; the handle's
    /// edges follow it and the opposite ones stay; a moving edge stops `minSide` short of the edge
    /// opposite it, so the rect never flips. With `lockedRatio` (width over height) the ratio holds:
    /// see `lockedResize`. `.inside` returns `rect` (a move is `moved`).
    static func resized(_ rect: CGRect, handle: SelectionHandle, to point: CGPoint, lockedRatio: CGFloat?,
                        bounds: CGRect, minSide: CGFloat) -> CGRect {
        guard handle != .inside else { return rect }
        let p = CGPoint(x: min(max(point.x, bounds.minX), bounds.maxX),
                        y: min(max(point.y, bounds.minY), bounds.maxY))
        if let ratio = usableRatio(lockedRatio) {
            return lockedResize(rect, handle: handle, to: p, ratio: ratio, bounds: bounds, minSide: minSide)
        }
        var minX = rect.minX, maxX = rect.maxX, minY = rect.minY, maxY = rect.maxY
        if handle.movesMinX { minX = min(p.x, maxX - minSide) }
        if handle.movesMaxX { maxX = max(p.x, minX + minSide) }
        if handle.movesMinY { minY = min(p.y, maxY - minSide) }
        if handle.movesMaxY { maxY = max(p.y, minY + minSide) }
        return fitted(CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY), in: bounds)
    }

    /// A corner takes the larger of the pointer's width and its height times the ratio, so the
    /// rect reaches the pointer; an edge sets its own side and the other side grows about the
    /// rect's centre. The short side is at least `minSide`. The width is then limited by the room
    /// from the fixed edges to `bounds` (all of `bounds` along a centred side), and `fitted` moves
    /// a centred side inside.
    private static func lockedResize(_ rect: CGRect, handle: SelectionHandle, to p: CGPoint, ratio: CGFloat,
                                     bounds: CGRect, minSide: CGFloat) -> CGRect {
        let horizontal = handle.movesMinX || handle.movesMaxX
        let vertical = handle.movesMinY || handle.movesMaxY
        let pointerWidth = max(handle.movesMaxX ? p.x - rect.minX : rect.maxX - p.x, 0)
        let pointerHeight = max(handle.movesMaxY ? p.y - rect.minY : rect.maxY - p.y, 0)
        var width: CGFloat
        if horizontal && vertical {
            width = max(pointerWidth, pointerHeight * ratio)
        } else if horizontal {
            width = pointerWidth
        } else {
            width = pointerHeight * ratio
        }
        width = max(width, minSide, minSide * ratio)
        let roomWidth = horizontal ? (handle.movesMaxX ? bounds.maxX - rect.minX : rect.maxX - bounds.minX) : bounds.width
        let roomHeight = vertical ? (handle.movesMaxY ? bounds.maxY - rect.minY : rect.maxY - bounds.minY) : bounds.height
        width = min(width, roomWidth, roomHeight * ratio)
        let height = width / ratio
        let x = horizontal ? (handle.movesMaxX ? rect.minX : rect.maxX - width) : rect.midX - width / 2
        let y = vertical ? (handle.movesMaxY ? rect.minY : rect.maxY - height) : rect.midY - height / 2
        return fitted(CGRect(x: x, y: y, width: width, height: height), in: bounds)
    }

    /// `rect` moved by `delta`, kept inside `bounds` with its size.
    static func moved(_ rect: CGRect, by delta: CGVector, bounds: CGRect) -> CGRect {
        fitted(rect.offsetBy(dx: delta.dx, dy: delta.dy), in: bounds)
    }

    /// An arrow key: 1 pt, 10 pt with Shift. Up is +y in the view's coordinates.
    static func nudged(_ rect: CGRect, key: Arrow, shift: Bool, bounds: CGRect) -> CGRect {
        let step = shift ? shiftNudgeStep : nudgeStep
        let delta = switch key {
        case .left: CGVector(dx: -step, dy: 0)
        case .right: CGVector(dx: step, dy: 0)
        case .up: CGVector(dx: 0, dy: step)
        case .down: CGVector(dx: 0, dy: -step)
        }
        return moved(rect, by: delta, bounds: bounds)
    }

    /// The W and H fields. A nil side keeps its value, or with `lockedRatio` follows the typed one
    /// (the width wins when both are given). The rect grows from its top-left corner (`minX`,
    /// `maxY` here); it is limited to `bounds` (with the lock both sides shrink together) and
    /// moved inside them. Each side is at least `minSide`.
    static func sized(_ rect: CGRect, width: CGFloat?, height: CGFloat?, lockedRatio: CGFloat?, bounds: CGRect) -> CGRect {
        var w = width ?? rect.width
        var h = height ?? rect.height
        if let ratio = usableRatio(lockedRatio) {
            if width != nil {
                h = w / ratio
            } else if height != nil {
                w = h * ratio
            }
            if w < minSide || h < minSide {
                (w, h) = ratio >= 1 ? (minSide * ratio, minSide) : (minSide, minSide / ratio)
            }
            let shrink = min(1, bounds.width / w, bounds.height / h)
            w *= shrink
            h *= shrink
        } else {
            w = min(max(w, minSide), bounds.width)
            h = min(max(h, minSide), bounds.height)
        }
        return fitted(CGRect(x: rect.minX, y: rect.maxY - h, width: w, height: h), in: bounds)
    }

    /// All-in-One's starting rect from the remembered one: on the display holding its centre (the
    /// first, when frames overlap), clipped to it. Nil when no display holds the centre or less
    /// than `minSide` is left on a side. `rect` and `displayFrames` share one coordinate space.
    static func restored(_ rect: CGRect, displayFrames: [CGRect]) -> CGRect? {
        guard !rect.isNull, !rect.isInfinite else { return nil }
        let centre = CGPoint(x: rect.midX, y: rect.midY)
        guard let frame = displayFrames.first(where: { $0.contains(centre) }) else { return nil }
        let clipped = rect.intersection(frame)
        guard clipped.width >= minSide, clipped.height >= minSide else { return nil }
        return fitted(clipped, in: frame)
    }

    /// `rect` in whole points (origin and size rounded), no larger than `bounds`, moved inside them.
    static func fitted(_ rect: CGRect, in bounds: CGRect) -> CGRect {
        let width = min(rect.width.rounded(), bounds.width)
        let height = min(rect.height.rounded(), bounds.height)
        let x = min(max(rect.minX.rounded(), bounds.minX), bounds.maxX - width)
        let y = min(max(rect.minY.rounded(), bounds.minY), bounds.maxY - height)
        return CGRect(x: x, y: y, width: width, height: height)
    }

    private static func usableRatio(_ ratio: CGFloat?) -> CGFloat? {
        guard let ratio, ratio.isFinite, ratio > 0 else { return nil }
        return ratio
    }
}
```

`TidyShot/Selection/AllInOneToolbarPlacement.swift`:
```swift
import CoreGraphics

/// Where All-in-One's toolbar sits (spec 2.9). Pure; the selection view's coordinates, bottom-left
/// origin. `screenBounds` is the view's bounds less the menu bar's safe-area inset (Task 2).
nonisolated enum AllInOneToolbarPlacement {
    /// Between the selection and the toolbar.
    static let gap: CGFloat = 8
    /// Between the toolbar and the screen's edges.
    static let margin: CGFloat = 8

    /// Centred under the selection; above it when below leaves less than `margin` to the screen's
    /// edge; otherwise inside its bottom edge. x is clamped `margin` inside the screen's sides (the
    /// left side wins on a screen narrower than the toolbar). The origin is whole points.
    static func frame(toolbarSize size: CGSize, selection: CGRect, screenBounds bounds: CGRect) -> CGRect {
        let below = selection.minY - gap - size.height
        let above = selection.maxY + gap
        let y: CGFloat
        if below >= bounds.minY + margin {
            y = below
        } else if above + size.height <= bounds.maxY - margin {
            y = above
        } else {
            y = max(min(selection.minY + gap, bounds.maxY - margin - size.height), bounds.minY + margin)
        }
        let x = max(min(selection.midX - size.width / 2, bounds.maxX - margin - size.width), bounds.minX + margin)
        return CGRect(x: x.rounded(), y: y.rounded(), width: size.width, height: size.height)
    }
}
```

`TidyShot/Selection/AllInOneChoice.swift`:
```swift
import CoreGraphics
import ScreenCaptureKit

/// What All-in-One resolved to (spec 2.9), returned by `SelectionController.selectAllInOne`. Rects
/// are CoreGraphics global points, clipped to `display`. `Selection` gains no case: the coordinator
/// maps each of these to an existing capture path.
enum AllInOneChoice {
    /// Capture (the button, Return or a double-click inside): the area, frozen or live.
    case area(rect: CGRect, display: SCDisplay)
    /// The window whose frame a click took, captured from its own surface.
    case window(SCWindow)
    /// The display the rect is on.
    case fullscreen(SCDisplay)
    case scrolling(rect: CGRect, display: SCDisplay)
    /// The Self-Timer countdown over the rect (Task 3).
    case timer(rect: CGRect, display: SCDisplay)
}

/// All-in-One's toolbar buttons, left to right after the size fields and the lock (spec 2.9).
nonisolated enum AllInOneAction: CaseIterable, Equatable, Sendable {
    case capture, window, fullscreen, scrolling, timer, cancel

    /// The accessibility label.
    var title: String {
        switch self {
        case .capture: "Capture"
        case .window: "Window"
        case .fullscreen: "Fullscreen"
        case .scrolling: "Scrolling"
        case .timer: "Timer"
        case .cancel: "Cancel"
        }
    }

    var symbolName: String {
        switch self {
        case .capture: "camera"
        case .window: "macwindow"
        case .fullscreen: "display"
        case .scrolling: "scroll"
        case .timer: "timer"
        case .cancel: "xmark"
        }
    }

    /// The tooltip. `timerSeconds` is `settings.selfTimerSeconds` (Task 3).
    func help(timerSeconds: Int) -> String {
        switch self {
        case .capture: "Capture area (Return)"
        case .window: "Capture the window with transparent corners"
        case .fullscreen: "Capture this display"
        case .scrolling: "Scrolling capture of this area"
        case .timer: "Capture this area after \(timerSeconds) seconds"
        case .cancel: "Cancel (Escape)"
        }
    }

    /// Window only when the rect came from a window click.
    func isEnabled(hasWindow: Bool) -> Bool {
        self != .window || hasWindow
    }
}

/// The aspect-ratio lock button's strings.
nonisolated enum AllInOneLock {
    static let help = "Lock aspect ratio"

    static func symbolName(locked: Bool) -> String {
        locked ? "lock" : "lock.open"
    }
}
```

- [ ] **Step 4: Run the full suite**

Run the header's full-suite command. Expected: no `error:` lines, and `Test run with 714 tests in 88 suites passed`. This task adds 28 tests in 3 suites: `SelectionAdjustTests` (18: `eachHandleIsFoundAtItsCornerOrEdge`, `aNarrowRectGivesTheNearerSide`, `handlePointsSitOnCornersAndEdgeMidpoints`, `eachHandleMovesOnlyItsEdges`, `resizingStopsAtTheMinimumSide`, `resizingIsClampedToTheBounds`, `aLockedCornerKeepsTheRatio`, `aLockedEdgeGrowsTheOtherSideAboutTheCentre`, `aLockedResizeStopsAtTheBounds`, `aLockedResizeKeepsTheMinimumSide`, `insideMovesTheRectAndClampsAtEachEdge`, `arrowsNudgeByOneOrTenAndStopAtTheEdge`, `keysMapToCommands`, `typedSizeGrowsFromTheTopLeft`, `typedSizeIsClampedAndMovedInside`, `typedSizeWithTheLockChangesTheOtherSide`, `restoreKeepsARectOnItsDisplay`, `restoreRefusesARectOffEveryDisplay`), `AllInOneToolbarPlacementTests` (7: `belowTheSelectionAndCentred`, `aboveWhenThereIsNoRoomBelow`, `insideTheBottomEdgeWhenNeitherFits`, `clampedToTheScreensSides`, `aScreenNarrowerThanTheToolbarAlignsItLeft`, `screenBoundsWithAnOrigin`, `theOriginIsWholePoints`) and `AllInOneChoiceTests` (3: `toolbarButtonsInOrderWithTheirSymbolsAndHelp`, `windowIsEnabledOnlyAfterAWindowClick`, `theLockButtonsSymbolFollowsItsState`). Nothing is removed or renamed.

No hand checks: nothing is wired yet.

- [ ] **Step 5: Commit**

```bash
git add TidyShot/Selection/SelectionAdjust.swift TidyShot/Selection/AllInOneToolbarPlacement.swift TidyShot/Selection/AllInOneChoice.swift TidyShotTests/SelectionAdjustTests.swift TidyShotTests/AllInOneToolbarPlacementTests.swift TidyShotTests/AllInOneChoiceTests.swift
git commit -m "feat: All-in-One selection geometry, toolbar placement and choices"
```

### Task 2: All-in-One

Spec 2.9, All-in-One, item 10. One shortcut (⌃⇧1) opens a selection that stays adjustable, with a toolbar that offers every capture kind. It runs in the existing selection overlay as a new `SelectionMode.allInOne`, so it keeps what 6a gave that overlay: Freeze screen (the snapshots before any overlay window, the opaque backdrop, the crop), the Quick Access cards left out of snapshots and captures (`overlayWindows()`), and the cursor rule (a capture taken while the overlay is up passes `duringSelection: true`). The Timer button is left out here and arrives with Task 3.

**Files:**
- Create: `TidyShot/Selection/AllInOneToolbar.swift` (`AllInOneToolbar`)
- Modify: `TidyShot/Selection/Selection.swift` (`SelectionMode`, lines 4-9: `.allInOne`)
- Modify: `TidyShot/Selection/SelectionOutcome.swift` (doc comments, lines 3-4 and 15-17; no code change)
- Modify: `TidyShot/Selection/SelectionView.swift` (properties after line 42; `resetCursorRects`, lines 63-65; `updateTrackingAreas`, lines 53-61; `mouseEntered`/`mouseMoved`, lines 69-85; `mouseDown`, lines 87-90; `mouseDragged`, lines 92-104; `mouseUp`, lines 106-125; `keyDown`, lines 127-133; `draw`, lines 137-170; new All-in-One methods)
- Modify: `TidyShot/Selection/SelectionController.swift` (properties, lines 7-20; `init`, lines 22-25; `select`, lines 27-78, split into `select`, `selectAllInOne` and `present`; `dismiss`, lines 139-153; `finishArea(cgRect:)`, lines 192-206; `finish`, lines 208-218; new All-in-One methods)
- Modify: `TidyShot/App/AppCoordinator.swift` (`selector`, line 32; `registerShortcuts`, lines 121-146; new `captureAllInOne(preselect:)` after `captureWindow`, line 163; `captureScrolling`, lines 167-196; `runSelection`, lines 221-249; new `areaResult(rect:display:)` and `runScrolling(rect:display:)`)
- Modify: `TidyShot/App/Shortcuts.swift` (line 4: `allInOne` first)
- Modify: `TidyShot/App/StatusMenuController.swift` (`rebuild`, line 72; actions, line 118)
- Modify: `TidyShot/Settings/ShortcutsSettingsView.swift` (a recorder before line 11)
- Modify: `TidyShot/Settings/AppSettings.swift` (`Keys` after line 56, property after line 98, `register` after line 139, `init` after line 170)
- Test: `TidyShotTests/SelectionOutcomeTests.swift`, `TidyShotTests/AppSettingsTests.swift`, `TidyShotTests/ShortcutsTests.swift` (one test appended to each)

**Interfaces:**
- Consumes:
  - `main`: `SelectionController.select(mode:content:freeze:)`, `frozenCapture(for:)`, `overlayWindows()`, `dismiss()`, `captureFrozenSnapshots(options:)`, `takeSnapshots()`, `updateHover(at:)` and `hoveredWindow` (`SelectionController.swift:27-171`); `SelectionView`'s `snapshot`, `isFrozen`, `highlightedRect`, `punchHole`, `stroke`, `drawSizeLabel`, `drawLoupe` (`SelectionView.swift`); `SelectionOutcome.resolve(mode:dragRect:hasHighlight:)` (`SelectionOutcome.swift:18`); `Geometry.cgRect(fromAppKit:primaryHeight:)`, `appKitRect(fromCG:primaryHeight:)` (`Geometry.swift:7-13`); `StoredRect` and `AppSettings.lastAreaRect` (`PreviousArea.swift:6`, `AppSettings.swift:94`); `CaptureOptions(settings:duringSelection:)` (`CaptureTarget.swift:34`); `AppCoordinator.capture(_:excludingWindows:duringSelection:)`, `save(_:)`, `frozenResult(for:display:)`, `withCaptureLock`, `loadContent()`, `scrollCapture.run(rect:display:)`, `ScrollCaptureLimits.minimumAreaHeightPoints`, `notifier.notifyError(_:title:)`.
  - Task 1: `SelectionHandle`, `SelectionAdjust` (`minSide`, `handleTolerance`, `keyCommand(keyCode:hasRect:)`, `handle(at:rect:tolerance:)`, `resized`, `moved`, `nudged`, `sized`, `restored`, `fitted`), `AllInOneToolbarPlacement.frame(toolbarSize:selection:screenBounds:)`, `AllInOneChoice`, `AllInOneAction`, `AllInOneLock`.
- Produces:
  - `SelectionMode.allInOne`. `SelectionOutcome.resolve` treats it as `.scrolling` (a drag is an area, a click the highlighted window).
  - `SelectionController.init(engine: CaptureEngine, settings: AppSettings, cardWindowNumbers: @escaping () -> Set<CGWindowID> = { [] })`.
  - `SelectionController.selectAllInOne(content: SCShareableContent, freeze: CaptureOptions? = nil, preselect: CGRect? = nil) async -> AllInOneChoice?`. `preselect` is CoreGraphics global points (as `lastAreaRect` and a URL command's rect); nil or off-screen opens with no rect. The overlay stays up after a choice until `dismiss()`, as after `select`; `frozenCapture(for:)` and `overlayWindows()` work as they do for area mode.
  - `SelectionView.timerSeconds: Int?` (nil leaves the Timer button out; Task 3 sets it to `settings.selfTimerSeconds` in `SelectionController.configureAllInOne(_:)`).
  - `AppCoordinator.captureAllInOne(preselect: CGRect? = nil) async`. Task 3 replaces its `.timer` case; Task 5 makes it `captureAllInOne(intent: CaptureIntent = .standard, preselect: ScreenRect? = nil)` and passes `preselect?.rect` on to `selectAllInOne`'s `preselect:`.
  - `AppCoordinator.areaResult(rect:display:) async -> CaptureResult?` and `runScrolling(rect:display:) async` (private; Task 5 adds an `intent:` parameter to `runScrolling` and calls it from `captureScrolling` too).
  - `KeyboardShortcuts.Name.allInOne` (stored name `allInOne`, initial ⌃⇧1).
  - `AppSettings.allInOneAspectLock: Bool` (key `allInOneAspectLock`, default false).

Behaviour (spec 2.9, All-in-One), with the points it leaves open settled:
- **Start.** `captureAllInOne()` passes `preselect ?? settings.lastAreaRect?.cgRect`. The controller converts it to AppKit global points and calls `SelectionAdjust.restored(_:displayFrames:)` with the selection windows' frames; on a hit, that display's view opens with the rect selected and adjustable (handles and toolbar), and its window is made key. Otherwise the overlay opens as Capture Scrolling's: crosshair, loupe, the window under the pointer highlighted.
- **Selecting.** With no rect, a drag draws one and a click takes the highlighted window's frame (already clipped to the display, as `highlightedRect` is) and remembers the window. With a rect: a press on a handle resizes, inside moves, outside starts a new rect; a click outside without a drag takes the window under the pointer when there is one and otherwise keeps the rect (the hover highlight is not drawn while a rect exists). A new rect on another display clears this one. The pointer is clamped to the display, so every rect stays on one display. While a drag, resize or move runs the toolbar is hidden and the size label shows; the loupe shows while drawing or resizing.
- **Window button.** Enabled while the current rect came from a window click; resizing, moving or typing a size keeps the window, a new drag or preselect drops it.
- **Keys** (the selection view is first responder whenever no field is editing): Escape cancels; Return or keypad Enter is Capture; arrows move 1 pt, Shift-arrows 10 pt. In a W or H field, Return applies the value and gives focus back to the view, Escape reverts the field and gives focus back, Tab moves between the two fields. A double-click inside the rect is Capture.
- **Aspect lock.** The lock button reads `settings.allInOneAspectLock` when the overlay opens and writes it when toggled. While locked the ratio is the rect's width over height at the moment the lock went on, or when a new rect (drag, window click, preselect) was set while locked.
- **Choices.** The coordinator maps each choice to the existing path. Capture and Window are taken while the overlay is still up, with the overlay and the cards excluded, so the cursor rule gives no pointer (`duringSelection: true`): Capture through `areaResult` (stores `lastAreaRect`, then the frozen crop or a live area capture); Window through `capture(.window(_:), duringSelection: true)`. Fullscreen dismisses the overlay first and captures as `captureFullscreen()` does (header point 1): the rect's display, with the overlay's windows (looked up before the dismiss, in case the window server still shows them) and the cards excluded, the pointer from Show cursor (`duringSelection: false`) after `NSCursor.arrow.set()`, so the crosshair the overlay set is never in it. Scrolling through `runScrolling` (the Phase 5 refusal under 100 pt, `lastAreaRect`, dismiss, session, save). Freeze applies to Capture only; with Freeze on the overlay is frozen, and Window, Fullscreen and Scrolling still capture live (spec 2.9).

- [ ] **Step 1: Write the failing tests**

`TidyShotTests/SelectionOutcomeTests.swift`, append inside the struct after `scrollingModeDragsAnAreaOrClicksAWindow` (line 39):
```swift

    /// All-in-One's first selection works as scrolling's: a drag is an area, a click the
    /// highlighted window (spec 2.9). The overlay then keeps the rect adjustable.
    @Test func allInOneModeDragsAnAreaOrClicksAWindow() {
        #expect(SelectionOutcome.resolve(mode: .allInOne, dragRect: drag, hasHighlight: false) == .area(drag))
        #expect(SelectionOutcome.resolve(mode: .allInOne, dragRect: drag, hasHighlight: true) == .area(drag))
        #expect(SelectionOutcome.resolve(mode: .allInOne, dragRect: nil, hasHighlight: true) == .window)
        let jitter = CGRect(x: 10, y: 10, width: 1, height: 1)
        #expect(SelectionOutcome.resolve(mode: .allInOne, dragRect: jitter, hasHighlight: true) == .window)
        #expect(SelectionOutcome.resolve(mode: .allInOne, dragRect: nil, hasHighlight: false) == .cancel)
    }
```

`TidyShotTests/AppSettingsTests.swift`, append inside the struct after `overlayCloseAfterDragDefaultsOnAndPersists` (its last test):
```swift

    /// All-in-One's aspect lock is off by default and persists (spec 2.9).
    @Test func allInOneAspectLockDefaultsOffAndPersists() {
        let defaults = freshDefaults()
        let first = AppSettings(defaults: defaults)
        #expect(!first.allInOneAspectLock)
        first.allInOneAspectLock = true
        #expect(defaults.object(forKey: "allInOneAspectLock") as? Bool == true)
        #expect(AppSettings(defaults: defaults).allInOneAspectLock)
    }
```

`TidyShotTests/ShortcutsTests.swift`, append inside the struct after `capturePreviousAreaIsControlShiftSix` (line 31):
```swift

    /// ⌃⇧1 sits before ⌃⇧2 to ⌃⇧6 (spec 2.9). No two names share a key or a default shortcut
    /// (Restore Closed Overlay has none).
    @Test func allInOneIsControlShiftOne() {
        #expect(KeyboardShortcuts.Name.allInOne.rawValue == "allInOne")
        #expect(KeyboardShortcuts.Name.allInOne.initialShortcut == .init(.one, modifiers: [.control, .shift]))
        let names: [KeyboardShortcuts.Name] = [.allInOne, .captureArea, .captureWindow, .captureFullscreen,
                                               .captureScrolling, .capturePreviousArea, .restoreOverlay,
                                               .cancelScrollingCapture]
        #expect(Set(names.map(\.rawValue)).count == names.count)
        #expect(Set(names.compactMap(\.initialShortcut)).count == names.count - 1)
    }
```

- [ ] **Step 2: Run the new tests and see them fail**

Run the header's full-suite command. Expected: the build fails with `error:` lines `type 'SelectionMode' has no member 'allInOne'`, `value of type 'AppSettings' has no member 'allInOneAspectLock'` and `type 'KeyboardShortcuts.Name' has no member 'allInOne'`. No `Test run` line appears.

- [ ] **Step 3: Mode, setting, shortcut, outcome comment**

`Selection.swift`, `SelectionMode` (lines 4-9), after `case scrolling`:
```swift
    /// All-in-One: starts as `.scrolling` (crosshair, loupe, window highlight), then keeps the
    /// rect adjustable under a toolbar. Resolved through `SelectionController.selectAllInOne`.
    case allInOne
```

`SelectionOutcome.swift`: line 3 reads `/// What a mouse-up in the selection overlay means, for each mode. Pure, so it is tested`; lines 15-17 read
```swift
    /// `.area`, `.scrolling` and `.allInOne` take a dragged rect of at least 2 by 2; a click (no
    /// drag, or a tiny one) picks the highlighted window when there is one; `.window` ignores drags
    /// and only picks the highlight. With neither, the selection is cancelled. All-in-One asks
    /// only for a press that does not start on its rect.
```
The code is unchanged: `mode != .window` already covers `.allInOne`.

`AppSettings.swift`: `Keys` gets `static let allInOneAspectLock = "allInOneAspectLock"` after line 56; after the `freezeScreen` property (line 98):
```swift
    /// All-in-One's aspect-ratio lock, as the toolbar last left it (spec 2.9).
    var allInOneAspectLock: Bool { didSet { defaults.set(allInOneAspectLock, forKey: Keys.allInOneAspectLock) } }
```
`register(defaults:)` gets `Keys.allInOneAspectLock: false,` after line 139; `init` gets `allInOneAspectLock = defaults.bool(forKey: Keys.allInOneAspectLock)` after line 170.

`Shortcuts.swift`, before line 4:
```swift
    /// All-in-One (spec 2.9): the first capture item, ⌃⇧1.
    static let allInOne = Self("allInOne", initial: .init(.one, modifiers: [.control, .shift]))
```

`ShortcutsSettingsView.swift`, before line 11 (`Capture previous area:`), so the order is spec 2.9's (after the four existing recorders):
```swift
            KeyboardShortcuts.Recorder("All-in-One:", name: .allInOne)
```

`StatusMenuController.swift`: before line 72 (`Capture Area`), the first capture item:
```swift
        menu.addItem(captureItem("All-in-One", .allInOne, #selector(allInOne)))
```
and after line 117:
```swift
    @objc private func allInOne() { Task { await coordinator.captureAllInOne() } }
```
`captureItem` already disables it while a capture runs and puts `  ⌃⇧1` in the title.

- [ ] **Step 4: The toolbar**

`TidyShot/Selection/AllInOneToolbar.swift`, AppKit, a subview of the selection view (spec 2.9: the area capture excludes it with the overlay window, and a key, borderless window can hold text fields):
```swift
/// All-in-One's toolbar: W and H fields, the aspect lock, a separator, then the actions.
final class AllInOneToolbar: NSVisualEffectView, NSTextFieldDelegate {
    var onAction: ((AllInOneAction) -> Void)?
    /// Return in W gives (width, nil), in H (nil, height): whole points above 0.
    var onSize: ((_ width: Int?, _ height: Int?) -> Void)?
    var onToggleLock: (() -> Void)?
    /// Called after Return or Escape in a field, so the selection view takes focus back.
    var onFieldDone: (() -> Void)?

    /// `timerSeconds` nil leaves the Timer button out.
    init(timerSeconds: Int?)
    /// Writes W and H (whole points) unless that field is being edited, the lock's symbol, and
    /// the Window button's enabled state.
    func update(size: CGSize, locked: Bool, windowEnabled: Bool)
}
```
Structure and behaviour:
- `material = .hudWindow`, `blendingMode = .withinWindow`, `state = .active`, `wantsLayer = true`, corner radius 8 (`layer?.cornerRadius`, `layer?.masksToBounds`). One horizontal `NSStackView` (spacing 4, edge insets 6) pinned to the edges; `fittingSize` is the size Task 1's placement gets.
- Left to right: a `W` label, the W field, an `H` label, the H field (each `NSTextField`, width 56, `alignment = .right`, monospaced-digit font, accessibility labels `Width` and `Height`, `delegate = self`, W's `nextKeyView` is H and H's is W); the lock button (`NSButton`, image `NSImage(systemSymbolName: AllInOneLock.symbolName(locked:), accessibilityDescription: AllInOneLock.help)`, `toolTip = AllInOneLock.help`); a vertical separator (`NSBox`, `.separator`); then one button per `AllInOneAction.allCases`, skipping `.timer` when `timerSeconds` is nil: image `action.symbolName`, `toolTip = action.help(timerSeconds: timerSeconds ?? 0)`, accessibility label `action.title`. Buttons are borderless 28 x 28 image buttons with `refusesFirstResponder = true`, so a click never moves focus off the selection view.
- `update` sets the Window button's `isEnabled = AllInOneAction.window.isEnabled(hasWindow: windowEnabled)`, the lock button's image, and each field's `stringValue = String(Int(side.rounded()))` when `field.currentEditor() == nil`.
- `control(_:textView:doCommandBy:)`: `insertNewline(_:)` parses `Int(field.stringValue.trimmingCharacters(in: .whitespaces))`; a value above 0 goes to `onSize` (W as `(value, nil)`, H as `(nil, value)`), anything else is ignored; then `onFieldDone`, return true. `cancelOperation(_:)` calls `onFieldDone` and returns true (the next `update` rewrites the field). Everything else returns false.
- `mouseDown(with:)` is overridden to do nothing: a press on the toolbar's background must not reach the selection view and start a new rect. `acceptsFirstMouse(for:)` returns true.

- [ ] **Step 5: SelectionView: the adjustable rect**

`TidyShot/Selection/SelectionView.swift`. Other modes do not change: every new branch is guarded by `mode == .allInOne`.

New state, after `trackingArea` (line 42):
```swift
    // MARK: All-in-One state

    /// The adjustable selection on this display, view coordinates. Set through `beginAdjusting`
    /// (a drag, a window click, the preselected rect); a resize, move, nudge or typed size changes it.
    private(set) var adjustRect: CGRect?
    /// True while `adjustRect` came from a window click: the Window button is enabled.
    private(set) var adjustRectIsWindow = false
    /// The toolbar's lock, from `settings.allInOneAspectLock` when the overlay opens.
    var isAspectLocked = false
    /// Width over height kept while locked. Set when the lock goes on and when a new rect is set while locked.
    private var lockedRatio: CGFloat?
    /// The Timer button's seconds; nil leaves it out (Task 3 sets it).
    var timerSeconds: Int?
    /// A new rect: `fromWindow` is true for a window click. The controller clears the other displays.
    var onAdjustRectSet: ((_ fromWindow: Bool) -> Void)?
    /// A press that resolved to nothing (no drag, no window, no rect here). The controller cancels
    /// unless another display holds a rect.
    var onEmptyClick: (() -> Void)?
    /// Capture, Window, Fullscreen, Scrolling or Timer, with the rect in AppKit global points.
    var onAllInOneAction: ((AllInOneAction, CGRect) -> Void)?
    var onAspectLockChanged: ((Bool) -> Void)?
    private enum AdjustDrag {
        case resize(SelectionHandle, CGRect)
        case move(start: CGPoint, original: CGRect)
    }
    private var adjustDrag: AdjustDrag?
    private var toolbar: AllInOneToolbar?
```

Entry points the controller calls:
```swift
    /// A new rect (view coordinates, on this display): handles and toolbar appear. While locked,
    /// its ratio becomes the one kept.
    func beginAdjusting(_ rect: CGRect, fromWindow: Bool) {
        adjustRect = rect
        adjustRectIsWindow = fromWindow
        lockedRatio = isAspectLocked && rect.height > 0 ? rect.width / rect.height : nil
        layoutToolbar()
        needsDisplay = true
    }

    /// Another display took the selection.
    func clearAdjustRect() {
        adjustRect = nil
        adjustRectIsWindow = false
        lockedRatio = nil
        adjustDrag = nil
        layoutToolbar()
        needsDisplay = true
    }
```

Mouse, in `.allInOne` only (the existing bodies stay for the other modes; each method starts with `if mode == .allInOne { allInOne…(event); return }` or calls the helper where noted):
```swift
    private func allInOneMouseDown(_ event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        dragRect = nil
        guard let adjustRect,
              let handle = SelectionAdjust.handle(at: point, rect: adjustRect, tolerance: SelectionAdjust.handleTolerance) else {
            dragStart = point // a new rect, or a click outside
            return
        }
        if handle == .inside {
            if event.clickCount == 2 {
                fireAllInOne(.capture)
                return
            }
            adjustDrag = .move(start: point, original: adjustRect)
        } else {
            adjustDrag = .resize(handle, adjustRect)
        }
    }

    private func allInOneMouseDragged(_ event: NSEvent) {
        let raw = convert(event.locationInWindow, from: nil)
        // The rect stays on this display: the pointer is clamped to it.
        let point = CGPoint(x: min(max(raw.x, bounds.minX), bounds.maxX), y: min(max(raw.y, bounds.minY), bounds.maxY))
        cursor = point
        crosshairStyle = style(at: point)
        switch adjustDrag {
        case .resize(let handle, let original):
            adjustRect = SelectionAdjust.resized(original, handle: handle, to: point, lockedRatio: lockedRatio,
                                                 bounds: bounds, minSide: SelectionAdjust.minSide)
        case .move(let start, let original):
            adjustRect = SelectionAdjust.moved(original, by: CGVector(dx: point.x - start.x, dy: point.y - start.y),
                                               bounds: bounds)
        case nil:
            guard let start = dragStart else { return }
            dragRect = CGRect(x: min(start.x, point.x), y: min(start.y, point.y),
                              width: abs(point.x - start.x), height: abs(point.y - start.y)).integral
        }
        toolbar?.isHidden = true
        updateAllInOneCursor(at: point)
        needsDisplay = true
        if let window {
            onMouseMoved?(window.convertToScreen(CGRect(origin: event.locationInWindow, size: .zero)).origin)
        }
    }

    private func allInOneMouseUp(_ event: NSEvent) {
        defer {
            dragStart = nil
            dragRect = nil
            adjustDrag = nil
            layoutToolbar()
            updateAllInOneCursor(at: cursor)
            needsDisplay = true
        }
        // A resize or move already changed the rect; a double-click already fired.
        guard adjustDrag == nil, dragStart != nil else { return }
        switch SelectionOutcome.resolve(mode: .allInOne, dragRect: dragRect, hasHighlight: highlightedRect != nil) {
        case .area(let rect):
            beginAdjusting(SelectionAdjust.fitted(rect, in: bounds), fromWindow: false)
            onAdjustRectSet?(false)
        case .window:
            guard let highlightedRect else { return }
            beginAdjusting(SelectionAdjust.fitted(highlightedRect, in: bounds), fromWindow: true)
            onAdjustRectSet?(true)
        case .cancel:
            if adjustRect == nil { onEmptyClick?() }
        }
    }
```
`onAdjustRectSet` is called synchronously, so the controller reads the `hoveredWindow` that produced `highlightedRect`.

Keys: `keyDown` (lines 127-133) starts with
```swift
        if mode == .allInOne {
            switch SelectionAdjust.keyCommand(keyCode: event.keyCode, hasRect: adjustRect != nil) {
            case .cancel?:
                onCancel?()
            case .capture?:
                fireAllInOne(.capture)
            case .nudge(let arrow)?:
                if let adjustRect {
                    self.adjustRect = SelectionAdjust.nudged(adjustRect, key: arrow,
                                                             shift: event.modifierFlags.contains(.shift), bounds: bounds)
                    layoutToolbar()
                    needsDisplay = true
                }
            case nil:
                super.keyDown(with: event)
            }
            return
        }
```

Toolbar wiring and the action:
```swift
    /// Shows the toolbar under (or above, or inside) the rect, or hides it while there is no rect
    /// or a drag, resize or move runs. The menu bar's safe-area inset is left free at the top.
    private func layoutToolbar() {
        guard mode == .allInOne, let adjustRect, adjustDrag == nil, dragRect == nil else {
            toolbar?.isHidden = true
            return
        }
        let toolbar = self.toolbar ?? makeToolbar()
        toolbar.update(size: adjustRect.size, locked: isAspectLocked, windowEnabled: adjustRectIsWindow)
        var screenBounds = bounds
        screenBounds.size.height -= window?.screen?.safeAreaInsets.top ?? 0
        toolbar.frame = AllInOneToolbarPlacement.frame(toolbarSize: toolbar.fittingSize, selection: adjustRect,
                                                       screenBounds: screenBounds)
        toolbar.isHidden = false
    }

    private func makeToolbar() -> AllInOneToolbar {
        let toolbar = AllInOneToolbar(timerSeconds: timerSeconds)
        toolbar.onAction = { [weak self] action in
            guard let self else { return }
            window?.makeFirstResponder(self)
            if action == .cancel { onCancel?() } else { fireAllInOne(action) }
        }
        toolbar.onSize = { [weak self] width, height in
            guard let self, let adjustRect else { return }
            self.adjustRect = SelectionAdjust.sized(adjustRect, width: width.map { CGFloat($0) },
                                                    height: height.map { CGFloat($0) },
                                                    lockedRatio: lockedRatio, bounds: bounds)
            layoutToolbar()
            needsDisplay = true
        }
        toolbar.onToggleLock = { [weak self] in
            guard let self else { return }
            isAspectLocked.toggle()
            lockedRatio = isAspectLocked ? adjustRect.flatMap { $0.height > 0 ? $0.width / $0.height : nil } : nil
            onAspectLockChanged?(isAspectLocked)
            window?.makeFirstResponder(self)
            layoutToolbar()
        }
        toolbar.onFieldDone = { [weak self] in
            guard let self else { return }
            window?.makeFirstResponder(self)
        }
        addSubview(toolbar)
        self.toolbar = toolbar
        return toolbar
    }

    /// Hands the rect, in AppKit global points, to the controller. Window only while the rect
    /// came from a window click.
    private func fireAllInOne(_ action: AllInOneAction) {
        guard let adjustRect, let window, action.isEnabled(hasWindow: adjustRectIsWindow) else { return }
        onAllInOneAction?(action, window.convertToScreen(convert(adjustRect, to: nil)))
    }
```

Cursor. Overlapping cursor rects are undefined in AppKit, so in `.allInOne` the view sets the cursor itself: `resetCursorRects` (lines 63-65) adds nothing in `.allInOne` (`guard mode != .allInOne else { return }` before the existing line); `updateTrackingAreas` (lines 53-61) adds `.cursorUpdate` to the options in `.allInOne`, and `cursorUpdate(with:)` and `mouseMoved` (after setting `cursor`) call
```swift
    /// Arrow over the toolbar, the resize cursor over a handle, an open hand inside (closed while
    /// moving), the crosshair elsewhere.
    private func updateAllInOneCursor(at point: CGPoint?) {
        guard mode == .allInOne else { return }
        if case .move = adjustDrag { NSCursor.closedHand.set(); return }
        if let point, let toolbar, !toolbar.isHidden, toolbar.frame.contains(point) { NSCursor.arrow.set(); return }
        guard let point, let adjustRect,
              let handle = SelectionAdjust.handle(at: point, rect: adjustRect, tolerance: SelectionAdjust.handleTolerance) else {
            NSCursor.crosshair.set()
            return
        }
        resizeCursor(for: handle).set()
    }
```
where `resizeCursor(for:)` maps `.inside` to `.openHand` and each resize handle to `NSCursor.frameResize(position:directions: .all)` (`.topLeft`, `.top`, `.topRight`, `.right`, `.bottomRight`, `.bottom`, `.bottomLeft`, `.left`; macOS 15 API). An adjusting resize keeps its handle's cursor (`case .resize(let handle, _)`: `resizeCursor(for: handle)`).

Drawing. `draw` (lines 137-170): after the `completedRect` block (lines 142-146) and before `let isDragging` (line 148):
```swift
        if mode == .allInOne, let adjustRect, dragRect == nil {
            punchHole(adjustRect)
            stroke(NSBezierPath(rect: adjustRect.insetBy(dx: 0.5, dy: 0.5)))
            drawHandles(on: adjustRect)
            if adjustDrag != nil { drawSizeLabel(for: adjustRect) }
            if case .resize = adjustDrag, let cursor { drawLoupe(at: cursor) }
            return
        }
```
`drawHandles(on:)` draws a white circle of 8 pt diameter with a 1 pt black stroke at 50 % opacity at each `SelectionHandle.resizeHandles` `point(on:)`. The frozen backdrop and the dimming are drawn first, as before, so the hole shows the frozen image when Freeze is on. With no rect here the existing code runs: a new drag draws the drag rect, the size label and the loupe; otherwise the highlight, the crosshair and the loupe, as in scrolling mode.

- [ ] **Step 6: SelectionController: selectAllInOne**

`TidyShot/Selection/SelectionController.swift`.

Properties (lines 7-20): add
```swift
    private let settings: AppSettings
    /// All-in-One's caller, waiting for a choice (nil: cancelled).
    private var allInOneContinuation: CheckedContinuation<AllInOneChoice?, Never>?
    /// All-in-One: the window whose frame the current rect came from, for the Window button.
    private var pickedWindow: SCWindow?
    private var isIdle: Bool { continuation == nil && allInOneContinuation == nil }
```
`init` (lines 22-25) becomes `init(engine: CaptureEngine, settings: AppSettings, cardWindowNumbers: @escaping () -> Set<CGWindowID> = { [] })` and stores `settings`.

`select` (lines 27-78) splits: its body from `displays = content.displays` (line 29) to the `snapshotTask` lines (73-75) moves into `present`; `select` and `selectAllInOne` wrap it:
```swift
    func select(mode: SelectionMode, content: SCShareableContent, freeze: CaptureOptions? = nil) async -> Selection? {
        // All-in-One resolves through `selectAllInOne`.
        guard isIdle, mode != .allInOne, !NSScreen.screens.isEmpty else { return nil }
        await present(mode: mode, content: content, freeze: freeze, preselect: nil)
        return await withCheckedContinuation { continuation = $0 }
    }

    /// All-in-One (spec 2.9): the overlay opens on `preselect` (CoreGraphics global points) when it
    /// is on a display, otherwise as Capture Scrolling's; it stays adjustable until a toolbar
    /// button, Return or a double-click picks the choice. On a choice the overlay stays up until
    /// `dismiss()`; `freeze` works as in area mode.
    func selectAllInOne(content: SCShareableContent, freeze: CaptureOptions? = nil,
                        preselect: CGRect? = nil) async -> AllInOneChoice? {
        guard isIdle, !NSScreen.screens.isEmpty else { return nil }
        await present(mode: .allInOne, content: content, freeze: freeze, preselect: preselect)
        return await withCheckedContinuation { allInOneContinuation = $0 }
    }
```
In `present(mode:content:freeze:preselect:)`, three changes to the moved code:
- the freeze condition (line 38) becomes `if mode == .area || mode == .allInOne, let freeze {` (comment: area and All-in-One freeze; window and scrolling stay live);
- `view.onCancel` (line 53) becomes `{ [weak self] in Task { self?.cancel() } }`, and after it `if mode == .allInOne { configureAllInOne(view) }`;
- after the pointer's window is made key (line 71): `if mode == .allInOne, let preselect { placePreselected(preselect) }`.

New methods:
```swift
    private func configureAllInOne(_ view: SelectionView) {
        view.isAspectLocked = settings.allInOneAspectLock
        // Task 3 (Self-Timer) sets `settings.selfTimerSeconds` here; nil leaves the Timer button out.
        view.timerSeconds = nil
        view.onAdjustRectSet = { [weak self, weak view] fromWindow in
            guard let self, let view else { return }
            allInOneRectSet(on: view, fromWindow: fromWindow)
        }
        view.onEmptyClick = { [weak self] in Task { self?.allInOneEmptyClick() } }
        view.onAllInOneAction = { [weak self] action, appKitRect in
            Task { self?.finishAllInOne(action, appKitRect: appKitRect) }
        }
        view.onAspectLockChanged = { [weak self] locked in self?.settings.allInOneAspectLock = locked }
    }

    /// The preselected rect on the screen holding its centre, as that view's adjustable rect.
    /// Nothing when it is on no screen: the overlay opens with no rect.
    private func placePreselected(_ cgRect: CGRect) {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        let appKitRect = Geometry.appKitRect(fromCG: cgRect, primaryHeight: primaryHeight)
        guard let rect = SelectionAdjust.restored(appKitRect, displayFrames: windows.map(\.frame)),
              let index = windows.firstIndex(where: { $0.frame.contains(CGPoint(x: rect.midX, y: rect.midY)) })
        else { return }
        let frame = windows[index].frame
        views[index].beginAdjusting(rect.offsetBy(dx: -frame.minX, dy: -frame.minY), fromWindow: false)
        windows[index].makeKey()
    }

    /// A new rect on `view`: the other displays drop theirs, the window it came from is
    /// remembered (or forgotten), and its window becomes key so Return and the arrows reach it.
    private func allInOneRectSet(on view: SelectionView, fromWindow: Bool) {
        pickedWindow = fromWindow ? hoveredWindow : nil
        for other in views where other !== view {
            other.clearAdjustRect()
        }
        if let index = views.firstIndex(where: { $0 === view }) {
            windows[index].makeKey()
        }
    }

    /// A click that selected nothing: cancels while no display holds a rect, otherwise gives the
    /// key back to the display that does.
    private func allInOneEmptyClick() {
        if let index = views.firstIndex(where: { $0.adjustRect != nil }) {
            windows[index].makeKey()
        } else {
            cancel()
        }
    }

    /// A toolbar button, Return or a double-click. The rect is clipped to the display under its
    /// centre, as an area selection is.
    private func finishAllInOne(_ action: AllInOneAction, appKitRect: CGRect) {
        if action == .window {
            if let pickedWindow { resumeAllInOne(.window(pickedWindow)) }
            return
        }
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        guard case let (rect, display)? = clippedToDisplay(Geometry.cgRect(fromAppKit: appKitRect, primaryHeight: primaryHeight)) else {
            resumeAllInOne(nil)
            return
        }
        switch action {
        case .capture: resumeAllInOne(.area(rect: rect, display: display))
        case .fullscreen: resumeAllInOne(.fullscreen(display))
        case .scrolling: resumeAllInOne(.scrolling(rect: rect, display: display))
        case .timer: resumeAllInOne(.timer(rect: rect, display: display))
        case .window, .cancel: resumeAllInOne(nil)
        }
    }

    /// Resumes All-in-One's caller. Cancel dismisses the overlay at once; a choice leaves it up.
    private func resumeAllInOne(_ choice: AllInOneChoice?) {
        guard let allInOneContinuation else { return }
        snapshotTask?.cancel()
        snapshotTask = nil
        self.allInOneContinuation = nil
        if choice == nil {
            dismiss()
        }
        allInOneContinuation.resume(returning: choice)
    }

    /// Escape, Cancel, or an empty click: whichever caller waits gets nil.
    private func cancel() {
        if allInOneContinuation != nil {
            resumeAllInOne(nil)
        } else {
            finish(nil)
        }
    }

    /// `cgRect` clipped to the display under its centre, or the first display; nil when nothing
    /// of it is on that display.
    private func clippedToDisplay(_ cgRect: CGRect) -> (CGRect, SCDisplay)? {
        let centre = CGPoint(x: cgRect.midX, y: cgRect.midY)
        guard let display = displays.first(where: { $0.frame.contains(centre) }) ?? displays.first else { return nil }
        let clipped = cgRect.intersection(display.frame)
        return clipped.isEmpty ? nil : (clipped, display)
    }
```
`finishArea(cgRect:)` (lines 192-206) becomes
```swift
    private func finishArea(cgRect: CGRect) {
        guard case let (rect, display)? = clippedToDisplay(cgRect) else {
            finish(nil)
            return
        }
        finish(.area(rect: rect, display: display))
    }
```
`dismiss()` (lines 139-153) also sets `pickedWindow = nil`. `finish(_:)`, `finishPick`, `updateHover`, `takeSnapshots`, `overlayWindows` and `captureFrozenSnapshots` are unchanged: `updateHover` and the loupe snapshots already run in every mode but `.area` and `.window` respectively, and `frozenCapture(for:)` reads the same dictionary.

- [ ] **Step 7: AppCoordinator: captureAllInOne**

`TidyShot/App/AppCoordinator.swift`.

Line 32: `SelectionController(engine: engine, settings: settings, cardWindowNumbers: { [weak self] in self?.overlay.windowNumbers ?? [] })`.

`registerShortcuts` (lines 121-146), first:
```swift
        KeyboardShortcuts.onKeyUp(for: .allInOne) { [weak self] in
            Task { await self?.captureAllInOne() }
        }
```

`runSelection` (lines 221-249): the `.area` case (lines 232-239) becomes `result = await areaResult(rect: rect, display: display)`. New, after `runSelection`:
```swift
    /// An area chosen in the overlay, which is still up: stores it as the previous area, then cuts
    /// it from the frozen snapshot or captures it live with the overlay and the cards excluded.
    private func areaResult(rect: CGRect, display: SCDisplay) async -> CaptureResult? {
        settings.lastAreaRect = StoredRect(rect)
        if let frozen = frozenResult(for: rect, display: display) {
            return frozen
        }
        let overlays = await selector.overlayWindows()
        return await capture(.area(rect: rect, display: display), excludingWindows: overlays, duringSelection: true)
    }
```

`captureScrolling` (lines 167-196): lines 180-194 move into `runScrolling`, and the closure ends with `await runScrolling(rect: rect, display: display)` after the `guard case .area` (lines 176-179):
```swift
    /// A scrolling capture of an area chosen in the overlay, which is still up: refuses one under
    /// 100 pt with the Phase 5 message, stores the previous area, dismisses the overlay, runs the
    /// session and saves the stitched image like any capture.
    private func runScrolling(rect: CGRect, display: SCDisplay) async {
        guard rect.height >= CGFloat(ScrollCaptureLimits.minimumAreaHeightPoints) else {
            selector.dismiss()
            notifier.notifyError("Select an area at least 100 points tall.", title: "Scrolling capture")
            return
        }
        settings.lastAreaRect = StoredRect(rect)
        selector.dismiss()
        let outcome = await scrollCapture.run(rect: rect, display: display)
        if let notice = outcome.failureNotice {
            notifier.notifyError(notice.body, title: notice.title)
        }
        if let image = outcome.imageToSave {
            await save(CaptureResult(image: image.image, scale: image.scale,
                                     target: .area(rect: rect, display: display)))
        }
    }
```
The scrolling shortcut still advances a session started from All-in-One (`captureScrolling` checks `scrollCapture.isRunning` before the lock).

New, after `captureWindow` (line 163):
```swift
    /// All-in-One (spec 2.9): one adjustable selection whose toolbar picks the capture. Opens on
    /// `preselect` (CoreGraphics global points; a URL command's rect, Task 5) or else the last
    /// area, when it is on a connected display. Capture and Window are taken while the overlay is
    /// up, with the overlay and the cards excluded, so the pointer is never in them; Fullscreen
    /// dismisses the overlay first and follows Show cursor, as Capture Fullscreen does. Each ends
    /// in `save(_:)`.
    func captureAllInOne(preselect: CGRect? = nil) async {
        await withCaptureLock {
            guard let content = await loadContent() else { return }
            // Freeze applies to Capture; the snapshots follow the cursor setting, as in area mode.
            let freeze = settings.freezeScreen ? CaptureOptions(settings: settings, duringSelection: false) : nil
            guard let choice = await selector.selectAllInOne(content: content, freeze: freeze,
                                                             preselect: preselect ?? settings.lastAreaRect?.cgRect)
            else { return }

            let result: CaptureResult?
            switch choice {
            case .area(let rect, let display):
                result = await areaResult(rect: rect, display: display)
            case .window(let window):
                result = await capture(.window(window), duringSelection: true)
            case .fullscreen(let display):
                // As Capture Fullscreen: the overlay goes first and the pointer follows Show cursor.
                // Its windows stay excluded in case the window server has not dropped them yet; the
                // arrow replaces the crosshair the overlay set, which is not the user's pointer.
                let overlays = await selector.overlayWindows()
                selector.dismiss()
                NSCursor.arrow.set()
                result = await capture(.display(display), excludingWindows: overlays)
            case .scrolling(let rect, let display):
                await runScrolling(rect: rect, display: display)
                return
            case .timer:
                // Task 3 (Self-Timer) runs the countdown here; until then the Timer button is not shown.
                selector.dismiss()
                return
            }
            selector.dismiss()
            if let result {
                await save(result)
            }
        }
    }
```

- [ ] **Step 8: Run the full suite**

Run the header's full-suite command. Expected: no `error:` lines, and `Test run with 717 tests in 88 suites passed`. This task adds 3 tests and no suite: `SelectionOutcomeTests.allInOneModeDragsAnAreaOrClicksAWindow`, `AppSettingsTests.allInOneAspectLockDefaultsOffAndPersists`, `ShortcutsTests.allInOneIsControlShiftOne`. Nothing is removed or renamed; `SelectionAdjustTests`, `FreezeCropTests`, `PreviousAreaTests` and `WindowPickerTests` stay green.

- [ ] **Step 9: Hand checks (Tim)**

For Tim; the implementer lists these in its report and goes on to Step 10. Task 6's checklist repeats them. Release build (`-configuration Release -derivedDataPath .build-rel`), re-grant Screen Recording after an ad-hoc rebuild.
- The status menu starts with `All-in-One  ⌃⇧1`, disabled while a capture runs. Settings > Shortcuts lists `All-in-One:` after `Capture scrolling:`.
- No previous area (`defaults delete io.tky.tidyshot lastAreaRect`, or a fresh install): ⌃⇧1 opens with the crosshair, the loupe and the window highlight. A drag draws a rect with eight handles and the toolbar centred under it; a click on a window takes its frame and enables Window.
- With a previous area: ⌃⇧1 opens with that rect selected and the toolbar showing. Unplug the display it was on: ⌃⇧1 opens with no rect.
- Handles: each corner and edge resizes only its sides; the rect never flips and stops at 4 pt; nothing leaves the display. Inside moves it. A drag outside replaces it. The cursor is the resize cursor on handles, an open hand inside (closed while moving), an arrow over the toolbar, the crosshair elsewhere. The size label shows while dragging, the toolbar while not.
- Toolbar placement: under the rect; above it for a rect at the bottom of the screen; inside its bottom edge for a full-screen rect; never off the screen's sides; never under the notch.
- Arrows move 1 pt, Shift-arrows 10 pt. Return and a double-click inside capture the area. Escape cancels; Escape while editing W leaves the field, a second Escape cancels.
- W and H: type 640, Return: the rect is 640 wide from its top-left corner, and Return again captures. A value larger than the room moves the rect inside the display. Tab moves between the fields.
- Aspect lock: turn it on, drag a corner and an edge: the ratio holds (an edge grows the other side about the centre); typing W changes H. Close and reopen All-in-One: the lock is still on.
- Each button: Capture (an area capture; Capture Previous Area then repeats it), Window (the window with transparent corners), Fullscreen (that display, with no overlay, no toolbar and no Quick Access card in it; with Show cursor on the pointer is in it as an arrow, never the crosshair), Scrolling (the scrolling session on that rect; a rect under 100 pt shows `Select an area at least 100 points tall.`), Cancel. No Timer button yet.
- Freeze screen on: the All-in-One overlay is frozen, Capture cuts the frozen image (a playing video shows the frame from the shortcut); Window, Fullscreen and Scrolling capture live. Show cursor on: no pointer and no crosshair in an All-in-One Capture or Window; Fullscreen shows the pointer as an arrow.
- Two displays: a rect on one, then a drag on the other moves the selection there (the first display loses its rect and toolbar); Return captures on the display holding the rect.
- Captures from All-in-One behave like any other in upload-only mode, the Quick Access stack and Recent Captures.

- [ ] **Step 10: Commit**

```bash
git add TidyShot/Selection/AllInOneToolbar.swift TidyShot/Selection/Selection.swift TidyShot/Selection/SelectionOutcome.swift TidyShot/Selection/SelectionView.swift TidyShot/Selection/SelectionController.swift TidyShot/App/AppCoordinator.swift TidyShot/App/Shortcuts.swift TidyShot/App/StatusMenuController.swift TidyShot/Settings/ShortcutsSettingsView.swift TidyShot/Settings/AppSettings.swift TidyShotTests/SelectionOutcomeTests.swift TidyShotTests/AppSettingsTests.swift TidyShotTests/ShortcutsTests.swift
git commit -m "feat: All-in-One capture with an adjustable selection and toolbar"
```

### Task 3: Self-Timer

**Files:**
- Create: `TidyShot/SelfTimer/SelfTimerController.swift` (`SelfTimerOutcome`, `SelfTimerStage`, `SelfTimerGeometry`, `SelfTimerController`; no AppKit windows, so the logic is tested)
- Create: `TidyShot/SelfTimer/SelfTimerPanel.swift` (`SelfTimerModel`, `SelfTimerBadge`, `SelfTimerPanel`, `SelfTimerScreenStage`)
- Modify: `TidyShot/Selection/Selection.swift` (the `SelectionMode` enum, lines 4-9: a case)
- Modify: `TidyShot/Selection/SelectionOutcome.swift` (doc comment of `resolve`, lines 14-18; no code)
- Modify: `TidyShot/Selection/SelectionController.swift` (comments at line 31, which Task 2 moved into `present`, and above `finishPick`, line 176; one line in Task 2's `configureAllInOne(_:)`: the Timer button's seconds)
- Modify: `TidyShot/Capture/CaptureTarget.swift` (an extension next to `displayID`, line 14)
- Modify: `TidyShot/Settings/AppSettings.swift` (`Keys`, a property, the registered default and the read in `init`, next to `freezeScreen`)
- Modify: `TidyShot/App/Shortcuts.swift` (`selfTimer` after `capturePreviousArea`, line 8; `cancelScrollingCapture` renamed, line 13)
- Modify: `TidyShot/Scrolling/ScrollCaptureController.swift` (lines 70 and 87: the renamed name)
- Modify: `TidyShot/App/AppCoordinator.swift` (the lazy `selfTimer` next to `scrollCapture`, line 33; `registerShortcuts()`, lines 121-146; new `captureSelfTimer()` after `capturePreviousArea()`, line 219; `runSelfTimer(_:)` and `captureAfterCountdown(_:)` after `runSelection`, line 251; the `.timer` case of Task 2's `captureAllInOne(preselect:)`)
- Modify: `TidyShot/App/StatusMenuController.swift` (`rebuild()`, after the `Capture Previous Area` item, line 76; one `@objc` action after `capturePreviousArea()`, line 122)
- Modify: `TidyShot/Settings/ShortcutsSettingsView.swift` (after the `Capture previous area:` row, line 11)
- Modify: `TidyShot/Settings/CaptureSettingsView.swift` (a picker after the shadow caption, line 22)
- Create: `TidyShotTests/SelfTimerTests.swift` (struct `SelfTimerTests`, with `FakeSelfTimerStage`)
- Test: `TidyShotTests/SelectionOutcomeTests.swift`, `TidyShotTests/AppSettingsTests.swift`, `TidyShotTests/ShortcutsTests.swift`

Line numbers are `main`'s at 4c67c04. Tasks 1 and 2 add the All-in-One mode, shortcut and menu item to the same files, so find each place by the quoted code.

**Interfaces:**
- Consumes:
  - `main`: `ScrollClock`, `SystemScrollClock` (`Scrolling/ScrollClock.swift`) and the test double `FakeScrollClock` (`TidyShotTests/Support/ScrollSessionFakes.swift:63`, `advance(by:)`); `ScrollAreaFrameWindow(area:)` (`Scrolling/ScrollAreaFrameWindow.swift:12`, the 2 pt dashed frame just outside an AppKit-global rect, click-through); `SelectionController.select(mode:content:freeze:)`, `dismiss()`; `CaptureTarget` (`.display`, `.area(rect:display:)`, `.window`) and `CaptureTarget.displayID`; `CaptureEngine.screen(forDisplayID:)`; `Geometry.appKitRect(fromCG:primaryHeight:)`; `StoredRect` and `settings.lastAreaRect` (6a Task 7); `AppCoordinator.capture(_:excludingWindows:duringSelection:)`, `save(_:)`, `loadContent()`, `cardWindows()`, `withCaptureLock(_:)`, `notifier.notifyError(_:title:)`.
  - Task 1 (selection adjust): `AllInOneChoice.timer(rect: CGRect, display: SCDisplay)` and `AllInOneAction.timer` with `help(timerSeconds:)` and `isEnabled(hasWindow:)`.
  - Task 2 (All-in-One): `SelectionMode.allInOne`; `AppCoordinator.captureAllInOne(preselect:)`, whose `switch` over the `AllInOneChoice` has a placeholder `case .timer:` that only dismisses the overlay and returns; `SelectionController.configureAllInOne(_:)`, which sets `view.timerSeconds = nil` (nil leaves the Timer button out of `AllInOneToolbar`); `SelectionController.select(mode:content:freeze:)` after Task 2's split (it refuses `.allInOne` and freezes only `.area` and `.allInOne`); the `ShortcutsTests.allInOneIsControlShiftOne` test, which names `.cancelScrollingCapture`. Steps 1, 6 and 7 say exactly what changes.
- Produces (Tasks 4 to 6 rely on these names):
  ```swift
  // Selection.swift
  enum SelectionMode { case area, window, scrolling, allInOne /* Task 2 */, selfTimer }

  // CaptureTarget.swift
  extension CaptureTarget { var cgFrame: CGRect { get } }   // display frame, area rect, or window frame; CG global points

  // AppSettings
  var selfTimerSeconds: Int                                   // key "selfTimerSeconds", default 5
  static let selfTimerChoices: [Int]                          // [3, 5, 10]

  // Shortcuts.swift
  static let selfTimer          // stored name "selfTimer", no default
  static let cancelCapture      // renamed from cancelScrollingCapture; stored name "cancelScrollingCapture" (unchanged), initial Escape

  // SelfTimer/SelfTimerController.swift
  nonisolated enum SelfTimerOutcome: Equatable, Sendable { case finished, cancelled }
  protocol SelfTimerStage: AnyObject {
      func armEscape(); func show(seconds: Int); func tick(seconds: Int); func dismiss(); func disarmEscape()
  }
  nonisolated enum SelfTimerGeometry {
      static let badgeSide: CGFloat                           // 96
      static func badgeFrame(around subject: CGRect, in screenFrame: CGRect) -> CGRect
  }
  final class SelfTimerController {
      static let settleDelay: Duration                        // 100 ms
      init(clock: any ScrollClock = SystemScrollClock())
      private(set) var isRunning: Bool
      func run(seconds: Int, stage: any SelfTimerStage, capture: () async -> Void) async -> SelfTimerOutcome
      func cancel()
  }

  // AppCoordinator
  func captureSelfTimer() async                               // Self-Timer shortcut and menu item
  private func runSelfTimer(_ target: CaptureTarget) async    // call with the capture lock held
  ```
  Task 5 (URL scheme) calls `captureSelfTimer` for `tidyshot://self-timer` and adds an `intent: CaptureIntent` parameter to `captureSelfTimer`, `runSelfTimer` and `captureAfterCountdown`, so the URL command's intent reaches the one `save(_:)` call in `captureAfterCountdown` (Step 6), which becomes `save(result, intent: intent)`. This task has no `CaptureIntent` yet and keeps that single call.

Behaviour (spec 2.9, Self-Timer):
- `Self-Timer` (menu, after Capture Previous Area; Shortcuts tab `Self-timer:`, no default) opens the selection in `SelectionMode.selfTimer`: area mode's crosshair and loupe plus window mode's highlight. A drag selects an area; a click picks the highlighted window. `SelectionOutcome.resolve` already treats every mode but `.window` that way, and `SelectionController.finishPick` returns `.window` for a click in any mode but `.scrolling`, so the mode needs no new selection code. Freeze does not apply (`captureSelfTimer` passes no `freeze`).
- The overlay is dismissed at once. TidyShot then gives up activation (`NSApplication.shared.deactivate()`) so the app the user is working in is frontmost during the countdown and its menus and keys work. A countdown badge (`SelfTimerPanel`: borderless, non-activating, click-through, level `.screenSaver`, 96 pt rounded square, the seconds left in a 48 pt monospaced-digit font, the caption `Esc to cancel`) sits centred on the area or window, kept inside its screen, with the dashed frame (`ScrollAreaFrameWindow`) around it. It counts `settings.selfTimerSeconds` (Capture tab `Self-timer` picker: `3 seconds`, `5 seconds`, `10 seconds`, default 5) down once a second.
- At zero both panels are ordered out, the controller waits 100 ms for the window server to drop them, and the capture runs live (the cursor follows `Show cursor in screenshots`, the Quick Access cards excluded), then `save(_:)`. The shareable content is read again first: a window may have moved or closed during the countdown, and an `SCWindow` from before sizes the image from its old frame. A window that is gone posts `The window is no longer on screen.` titled `Self-timer`; a display that is gone, `The display is no longer connected.` with the same title.
- Escape cancels through the global Escape hotkey: `.cancelScrollingCapture` is renamed in code to `.cancelCapture` with the same stored name (nothing to migrate); the countdown enables it when it starts and disables it at zero or on cancel, as the scrolling session does. The capture lock is held for the whole countdown and the capture, so other shortcuts are ignored meanwhile.
- A self-timer area stores `settings.lastAreaRect` (a picked window does not). All-in-One's Timer button runs the same countdown on its rect (`AllInOneChoice.timer`); its case in `captureAllInOne(preselect:)` stores the rect first, as every All-in-One area kind does (Step 6).

- [ ] **Step 1: Write the failing tests**

`TidyShotTests/SelfTimerTests.swift` (new):
```swift
import CoreGraphics
import Foundation
import Testing
@testable import TidyShot

/// A stage that records what the controller does to it, in order. `note` lets a test put its own
/// marks (the capture) in the same list.
final class FakeSelfTimerStage: SelfTimerStage {
    private(set) var events: [String] = []

    func armEscape() { events.append("arm") }
    func show(seconds: Int) { events.append("show \(seconds)") }
    func tick(seconds: Int) { events.append("tick \(seconds)") }
    func dismiss() { events.append("dismiss") }
    func disarmEscape() { events.append("disarm") }
    func note(_ event: String) { events.append(event) }
}

/// The countdown on a clock the test moves (spec 2.9, Self-Timer), and where the badge goes.
struct SelfTimerTests {
    /// Starts a run of `seconds` and returns its task. The capture marks the stage's event list.
    func start(_ controller: SelfTimerController, _ stage: FakeSelfTimerStage, seconds: Int = 3)
        -> Task<SelfTimerOutcome, Never> {
        Task { await controller.run(seconds: seconds, stage: stage) { stage.note("capture") } }
    }

    @Test func countsDownFromTheConfiguredSeconds() async {
        let clock = FakeScrollClock()
        let stage = FakeSelfTimerStage()
        let controller = SelfTimerController(clock: clock)
        let run = start(controller, stage)

        await clock.advance(by: .zero)
        #expect(stage.events == ["arm", "show 3"])
        #expect(controller.isRunning)
        await clock.advance(by: .seconds(1))
        #expect(stage.events == ["arm", "show 3", "tick 2"])
        await clock.advance(by: .seconds(1))
        #expect(stage.events == ["arm", "show 3", "tick 2", "tick 1"])
        // Nothing moves between the seconds.
        await clock.advance(by: .milliseconds(999))
        #expect(stage.events.count == 4)
        await clock.advance(by: .milliseconds(1))
        // Zero: the panels go and Escape is released; the capture waits for the settle delay.
        #expect(stage.events == ["arm", "show 3", "tick 2", "tick 1", "dismiss", "disarm"])

        await clock.advance(by: SelfTimerController.settleDelay)
        #expect(await run.value == .finished)
        #expect(!controller.isRunning)
    }

    /// The capture runs once, after the panels are gone and 100 ms later, not before.
    @Test func capturesOnceOnlyAfterThePanelsAreGoneAndTheSettleDelay() async {
        let clock = FakeScrollClock()
        let stage = FakeSelfTimerStage()
        let controller = SelfTimerController(clock: clock)
        let run = start(controller, stage, seconds: 2)

        await clock.advance(by: .seconds(2))
        #expect(stage.events.suffix(2) == ["dismiss", "disarm"])
        #expect(!stage.events.contains("capture"))
        await clock.advance(by: .milliseconds(99))
        #expect(!stage.events.contains("capture"))
        await clock.advance(by: .milliseconds(1))
        #expect(await run.value == .finished)
        #expect(stage.events == ["arm", "show 2", "tick 1", "dismiss", "disarm", "capture"])
        // Time passing afterwards captures nothing more.
        await clock.advance(by: .seconds(30))
        #expect(stage.events.filter { $0 == "capture" }.count == 1)
    }

    @Test func cancelStopsTheCountdownBeforeTheCapture() async {
        let clock = FakeScrollClock()
        let stage = FakeSelfTimerStage()
        let controller = SelfTimerController(clock: clock)
        let run = start(controller, stage)

        await clock.advance(by: .seconds(1))
        controller.cancel()
        #expect(await run.value == .cancelled)
        #expect(stage.events == ["arm", "show 3", "tick 2", "dismiss", "disarm"])
        await clock.advance(by: .seconds(30))
        #expect(!stage.events.contains("capture"))
        #expect(!controller.isRunning)
    }

    /// Escape after zero (the capture is under way) cancels nothing.
    @Test func cancelOnceTheCountdownHasEndedIsIgnored() async {
        let clock = FakeScrollClock()
        let stage = FakeSelfTimerStage()
        let controller = SelfTimerController(clock: clock)
        let run = start(controller, stage, seconds: 1)

        await clock.advance(by: .seconds(1))
        controller.cancel()
        await clock.advance(by: SelfTimerController.settleDelay)
        #expect(await run.value == .finished)
        #expect(stage.events == ["arm", "show 1", "dismiss", "disarm", "capture"])
    }

    @Test func aSecondRunWhileOneRunsIsRefusedAndTouchesNothing() async {
        let clock = FakeScrollClock()
        let first = FakeSelfTimerStage()
        let second = FakeSelfTimerStage()
        let controller = SelfTimerController(clock: clock)
        let run = start(controller, first)
        await clock.advance(by: .zero)

        let refused = await controller.run(seconds: 3, stage: second) { second.note("capture") }
        #expect(refused == .cancelled)
        #expect(second.events.isEmpty)
        #expect(controller.isRunning)

        controller.cancel()
        #expect(await run.value == .cancelled)
    }

    @Test func zeroSecondsIsRefused() async {
        let stage = FakeSelfTimerStage()
        let controller = SelfTimerController(clock: FakeScrollClock())
        let outcome = await controller.run(seconds: 0, stage: stage) { stage.note("capture") }
        #expect(outcome == .cancelled)
        #expect(stage.events.isEmpty)
        #expect(!controller.isRunning)
    }

    // MARK: Badge geometry (AppKit global points, origin bottom-left)

    let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)

    @Test func theBadgeIsCentredOnTheSubject() {
        #expect(SelfTimerGeometry.badgeSide == 96)
        let area = SelfTimerGeometry.badgeFrame(around: CGRect(x: 100, y: 100, width: 400, height: 300), in: screen)
        #expect(area == CGRect(x: 252, y: 202, width: 96, height: 96))
        // A subject smaller than the badge is still centred; a half point rounds up.
        let tiny = SelfTimerGeometry.badgeFrame(around: CGRect(x: 100, y: 100, width: 20, height: 20), in: screen)
        #expect(tiny == CGRect(x: 62, y: 62, width: 96, height: 96))
        let odd = SelfTimerGeometry.badgeFrame(around: CGRect(x: 100, y: 100, width: 45, height: 45), in: screen)
        #expect(odd == CGRect(x: 75, y: 75, width: 96, height: 96))
    }

    @Test func theBadgeStaysInsideItsScreen() {
        let corner = SelfTimerGeometry.badgeFrame(around: CGRect(x: 0, y: 0, width: 40, height: 40), in: screen)
        #expect(corner == CGRect(x: 0, y: 0, width: 96, height: 96))
        let far = SelfTimerGeometry.badgeFrame(around: CGRect(x: 1420, y: 880, width: 20, height: 20), in: screen)
        #expect(far == CGRect(x: 1344, y: 804, width: 96, height: 96))
        // A display left of and below the main one has negative coordinates.
        let second = CGRect(x: -1920, y: -200, width: 1920, height: 1080)
        let inside = SelfTimerGeometry.badgeFrame(around: CGRect(x: -1000, y: 100, width: 300, height: 200), in: second)
        #expect(inside == CGRect(x: -898, y: 152, width: 96, height: 96))
        let edge = SelfTimerGeometry.badgeFrame(around: CGRect(x: -1930, y: -210, width: 20, height: 20), in: second)
        #expect(edge == CGRect(x: -1920, y: -200, width: 96, height: 96))
    }
}
```

`TidyShotTests/SelectionOutcomeTests.swift`, inside `struct SelectionOutcomeTests`, after Task 2's `allInOneModeDragsAnAreaOrClicksAWindow`:
```swift
    /// Self-Timer selects like scrolling: a drag is an area, a click on the highlight is a window.
    @Test func selfTimerModeDragsAnAreaOrClicksAWindow() {
        #expect(SelectionOutcome.resolve(mode: .selfTimer, dragRect: drag, hasHighlight: false) == .area(drag))
        #expect(SelectionOutcome.resolve(mode: .selfTimer, dragRect: drag, hasHighlight: true) == .area(drag))
        #expect(SelectionOutcome.resolve(mode: .selfTimer, dragRect: nil, hasHighlight: true) == .window)
        let jitter = CGRect(x: 10, y: 10, width: 1, height: 1)
        #expect(SelectionOutcome.resolve(mode: .selfTimer, dragRect: jitter, hasHighlight: true) == .window)
        #expect(SelectionOutcome.resolve(mode: .selfTimer, dragRect: nil, hasHighlight: false) == .cancel)
        #expect(SelectionOutcome.resolve(mode: .selfTimer, dragRect: jitter, hasHighlight: false) == .cancel)
    }
```

`TidyShotTests/AppSettingsTests.swift`, two tests appended inside `AppSettingsTests`, after Task 2's `allInOneAspectLockDefaultsOffAndPersists` (its last test):
```swift
    /// Phase 6b: Self-timer counts 5 seconds unless the Capture tab says 3 or 10 (spec 2.9).
    @Test func selfTimerSecondsDefaultsToFiveAndPersists() {
        let defaults = freshDefaults()
        let first = AppSettings(defaults: defaults)
        #expect(first.selfTimerSeconds == 5)
        #expect(AppSettings.selfTimerChoices == [3, 5, 10])
        first.selfTimerSeconds = 10
        #expect(defaults.integer(forKey: "selfTimerSeconds") == 10)
        #expect(AppSettings(defaults: defaults).selfTimerSeconds == 10)
    }

    /// A stored value the picker does not offer reads as the default.
    @Test func selfTimerSecondsOutsideTheChoicesReadAsFive() {
        let defaults = freshDefaults()
        for stored in [0, 1, 4, 7, 60, -3] {
            defaults.set(stored, forKey: "selfTimerSeconds")
            #expect(AppSettings(defaults: defaults).selfTimerSeconds == 5)
        }
        defaults.set(3, forKey: "selfTimerSeconds")
        #expect(AppSettings(defaults: defaults).selfTimerSeconds == 3)
    }
```

`TidyShotTests/ShortcutsTests.swift`: first rename `.cancelScrollingCapture` to `.cancelCapture` in every test that names it, changing only that name: `scrollingShortcutsHaveTheirInitialKeys` (lines 10 and 12), `capturePreviousAreaIsControlShiftSix` (line 28) and Task 2's `allInOneIsControlShiftOne` (the last entry of its `names` list). Afterwards `grep -rn cancelScrollingCapture TidyShot TidyShotTests` finds only the stored name in `Shortcuts.swift`. Then add inside `struct ShortcutsTests`, after `allInOneIsControlShiftOne`:
```swift
    /// Self-Timer has a recorder in the Shortcuts tab but no default (spec 2.9), like Restore Closed Overlay.
    @Test func selfTimerHasNoInitialShortcut() {
        #expect(KeyboardShortcuts.Name.selfTimer.rawValue == "selfTimer")
        #expect(KeyboardShortcuts.Name.selfTimer.initialShortcut == nil)
    }

    /// The Escape name serves scrolling and the self-timer now; the stored name is the old one,
    /// so nothing in UserDefaults moves.
    @Test func cancelCaptureKeepsTheStoredNameOfTheScrollingEscape() {
        #expect(KeyboardShortcuts.Name.cancelCapture.rawValue == "cancelScrollingCapture")
        #expect(KeyboardShortcuts.Name.cancelCapture.initialShortcut == .init(.escape))
    }
```

- [ ] **Step 2: Run the tests and see them fail**

Run:
```bash
xcodegen generate && xcodebuild test -project TidyShot.xcodeproj -scheme TidyShot -destination 'platform=macOS' -derivedDataPath .build 2>&1 | grep -E "Test run with|error:|TEST"
```
Expected: the build fails with `error:` lines such as `cannot find type 'SelfTimerStage' in scope`, `cannot find 'SelfTimerController' in scope`, `cannot find 'SelfTimerGeometry' in scope`, `type 'SelectionMode' has no member 'selfTimer'`, `value of type 'AppSettings' has no member 'selfTimerSeconds'` and `type 'KeyboardShortcuts.Name' has no member 'selfTimer'` / `'cancelCapture'`, then `** TEST FAILED **` or `** BUILD FAILED **`. No test runs.

- [ ] **Step 3: The mode, the target frame, the setting and the shortcut names**

`TidyShot/Selection/Selection.swift`: after the `scrolling` case (line 9) add
```swift
    /// Self-Timer: the same crosshair, loupe and window highlight as `.scrolling`. A drag is an
    /// area; a click on the highlight returns the window (the controller returns `.window` for a
    /// click in every mode but `.scrolling`).
    case selfTimer
```
Task 2's `.allInOne` case stays where it is.

`TidyShot/Selection/SelectionOutcome.swift`: in the doc comment of `resolve` (lines 14-18) change "`.area` and `.scrolling` take a dragged rect" to "`.area`, `.scrolling` and `.selfTimer` take a dragged rect". No code change: `mode != .window` already covers it.

`TidyShot/Selection/SelectionController.swift`: line 31, "Window picking is offered in window and scrolling mode;" becomes "Window picking is offered in every mode but area;"; above `finishPick` (line 176) extend the doc to "...; in self-timer mode, as in window mode, the window itself."

`TidyShot/Capture/CaptureTarget.swift`: after the `displayID` extension's closing brace (line 20) add
```swift
extension CaptureTarget {
    /// Where the capture looks, in CoreGraphics global points: the display's frame, the area's
    /// rect or the window's frame. The self-timer's badge and frame are placed from it.
    var cgFrame: CGRect {
        switch self {
        case .display(let display): display.frame
        case .area(let rect, _): rect
        case .window(let window): window.frame
        }
    }
}
```

`TidyShot/Settings/AppSettings.swift`:
- `Keys`, after `static let freezeScreen = "freezeScreen"`: `static let selfTimerSeconds = "selfTimerSeconds"`.
- After the `freezeScreen` property:
  ```swift
    /// The Capture tab's Self-timer: seconds counted down before the capture. One of `selfTimerChoices`.
    var selfTimerSeconds: Int { didSet { defaults.set(selfTimerSeconds, forKey: Keys.selfTimerSeconds) } }
    static let selfTimerChoices = [3, 5, 10]
  ```
- In `defaults.register(defaults:)`, after `Keys.freezeScreen: false,` add `Keys.selfTimerSeconds: 5,`.
- In `init`, after `freezeScreen = defaults.bool(forKey: Keys.freezeScreen)` add
  ```swift
        let storedSelfTimer = defaults.integer(forKey: Keys.selfTimerSeconds)
        selfTimerSeconds = Self.selfTimerChoices.contains(storedSelfTimer) ? storedSelfTimer : 5
  ```

`TidyShot/App/Shortcuts.swift`: after the `capturePreviousArea` line (line 8) add
```swift
    /// Self-Timer. No default; the Shortcuts tab records one.
    static let selfTimer = Self("selfTimer")
```
and replace the `cancelScrollingCapture` declaration and its comment (lines 11-13) with
```swift
    /// Escape, live only while a scrolling capture or a self-timer countdown runs (disabled at
    /// launch). It has no recorder row: the recorder refuses keys without modifiers, the hotkey
    /// itself does not. The stored name is the one Phase 5 shipped, so nothing migrates.
    static let cancelCapture = Self("cancelScrollingCapture", initial: .init(.escape))
```

`TidyShot/Scrolling/ScrollCaptureController.swift`: lines 70 and 87, `.cancelScrollingCapture` becomes `.cancelCapture`.

- [ ] **Step 4: The countdown**

`TidyShot/SelfTimer/SelfTimerController.swift`:
```swift
import CoreGraphics
import Foundation

nonisolated enum SelfTimerOutcome: Equatable, Sendable {
    /// The countdown reached zero and the capture closure ran.
    case finished
    /// Escape, or a refused start. The capture closure did not run.
    case cancelled
}

/// What the countdown puts on screen and the Escape hotkey it holds. The controller calls these in
/// a fixed order (tested through a fake): `armEscape`, `show`, a `tick` for each second left
/// below the first, `dismiss`, `disarmEscape`. `SelfTimerScreenStage` is the real one.
protocol SelfTimerStage: AnyObject {
    func armEscape()
    func show(seconds: Int)
    func tick(seconds: Int)
    /// Orders every panel out. Called once per run, before the settle delay.
    func dismiss()
    func disarmEscape()
}

/// Where the countdown badge goes (spec 2.9, Self-Timer). AppKit global points, origin bottom-left.
nonisolated enum SelfTimerGeometry {
    static let badgeSide: CGFloat = 96

    /// The badge centred on `subject` (the area or window), whole-point origin, kept inside
    /// `screenFrame` so a subject at the edge of its display still shows it.
    static func badgeFrame(around subject: CGRect, in screenFrame: CGRect) -> CGRect {
        let side = badgeSide
        var x = (subject.midX - side / 2).rounded()
        var y = (subject.midY - side / 2).rounded()
        x = min(max(x, screenFrame.minX), screenFrame.maxX - side)
        y = min(max(y, screenFrame.minY), screenFrame.maxY - side)
        return CGRect(x: x, y: y, width: side, height: side)
    }
}

/// The self-timer's countdown, on the clock the scrolling session uses so a test moves it by hand
/// (spec 2.9). One run at a time. The caller holds the capture lock around `run`.
final class SelfTimerController {
    /// After the panels are ordered out, for the window server to drop them before the capture.
    static let settleDelay: Duration = .milliseconds(100)

    private let clock: any ScrollClock
    /// The counting task; nil outside the counting, so Escape during the capture does nothing.
    private var countdown: Task<Bool, Never>?
    /// True from the start of a run until its capture closure returns.
    private(set) var isRunning = false

    init(clock: any ScrollClock = SystemScrollClock()) {
        self.clock = clock
    }

    /// Shows `seconds` on `stage`, counts down once a second, then orders the stage out, waits
    /// `settleDelay` and awaits `capture`. Returns `.cancelled` at once (touching nothing) when a
    /// run is under way or `seconds` is not above zero, and `.cancelled` after `cancel()` during
    /// the counting, with the stage already out and `capture` not called.
    func run(seconds: Int, stage: any SelfTimerStage, capture: () async -> Void) async -> SelfTimerOutcome {
        guard !isRunning, seconds > 0 else { return .cancelled }
        isRunning = true
        defer { isRunning = false }
        stage.armEscape()
        stage.show(seconds: seconds)
        let clock = self.clock
        let counting = Task { () -> Bool in
            var left = seconds
            while left > 0 {
                do { try await clock.sleep(for: .seconds(1)) } catch { return false }
                left -= 1
                if left > 0 { stage.tick(seconds: left) }
            }
            return true
        }
        countdown = counting
        let reachedZero = await counting.value
        countdown = nil
        stage.dismiss()
        stage.disarmEscape()
        guard reachedZero else { return .cancelled }
        // A cancelled caller skips the pause and still captures: the countdown ran out.
        try? await clock.sleep(for: Self.settleDelay)
        await capture()
        return .finished
    }

    /// Escape: stops the counting. No effect before it starts, or once the capture is under way.
    func cancel() {
        countdown?.cancel()
    }
}
```

- [ ] **Step 5: The panels**

`TidyShot/SelfTimer/SelfTimerPanel.swift` (AppKit and SwiftUI: structure and exact names; the implementer writes the bodies):
- `@Observable final class SelfTimerModel { var seconds = 0 }`.
- `struct SelfTimerBadge: View` with `let model: SelfTimerModel`: a `VStack(spacing: 2)` of `Text("\(model.seconds)")` in `.font(.system(size: 48, weight: .semibold).monospacedDigit())` and `Text("Esc to cancel")` in `.font(.caption2)` with `.foregroundStyle(.secondary)`, framed 96 x 96 on `.regularMaterial` in a `RoundedRectangle(cornerRadius: 20, style: .continuous)`. `.accessibilityElement(children: .ignore)` with `.accessibilityLabel("\(model.seconds) seconds left")`.
- `final class SelfTimerPanel: NSPanel`, `init(model:frame:)`: `styleMask [.borderless, .nonactivatingPanel]`, `backing: .buffered`, `level = .screenSaver`, `isFloatingPanel = true`, `hidesOnDeactivate = false`, `ignoresMouseEvents = true` (click-through), `collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]`, `isOpaque = false`, `backgroundColor = .clear`, `hasShadow = false`, `animationBehavior = .none`, `isReleasedWhenClosed = false`. The content is an `NSHostingView(rootView: SelfTimerBadge(model: model))` with `sizingOptions = []`, as `ScrollCapturePanel` does. `canBecomeKey` and `canBecomeMain` return false.
- `final class SelfTimerScreenStage: SelfTimerStage`, `init(subject: CGRect, screenFrame: CGRect)` (both AppKit global): makes the model in a local first (a class cannot read `self.model` before every stored property is set), then `panel = SelfTimerPanel(model: model, frame: SelfTimerGeometry.badgeFrame(around: subject, in: screenFrame))` and `frameWindow = ScrollAreaFrameWindow(area: subject)`, the dashed frame the scrolling capture uses (a 2 pt dashed line just outside `subject`, click-through).
  - `armEscape()`: `KeyboardShortcuts.enable(.cancelCapture)`. `disarmEscape()`: `KeyboardShortcuts.disable(.cancelCapture)`.
  - `show(seconds:)`: sets `model.seconds`, then `frameWindow.orderFrontRegardless()` and `panel.orderFrontRegardless()`. `tick(seconds:)`: sets `model.seconds`.
  - `dismiss()`: `orderOut(nil)` on both.

- [ ] **Step 6: Wire the coordinator**

All in `TidyShot/App/AppCoordinator.swift`.

1. After the `scrollCapture` lazy property (line 33) add
   ```swift
    @ObservationIgnored private lazy var selfTimer = SelfTimerController()
   ```
2. `registerShortcuts()`: after the `.capturePreviousArea` handler add
   ```swift
        KeyboardShortcuts.onKeyUp(for: .selfTimer) { [weak self] in
            Task { await self?.captureSelfTimer() }
        }
   ```
   and replace the Escape block (lines 140-146, the two comments, `KeyboardShortcuts.disable(.cancelScrollingCapture)` and its `onKeyUp`) with
   ```swift
        // Escape must never be swallowed outside a scrolling capture or a self-timer countdown;
        // each enables it while it runs.
        KeyboardShortcuts.disable(.cancelCapture)
        KeyboardShortcuts.onKeyUp(for: .cancelCapture) { [weak self] in
            // Both are no-ops unless theirs is the one running; the capture lock allows one.
            self?.selfTimer.cancel()
            self?.scrollCapture.cancel()
        }
   ```
3. After `capturePreviousArea()` add:
   ```swift
    /// Self-Timer: select an area or click a window, then count down and capture it live. The
    /// lock is held for the selection, the countdown and the capture.
    func captureSelfTimer() async {
        await withCaptureLock {
            guard let content = await loadContent() else { return }
            guard let selection = await selector.select(mode: .selfTimer, content: content) else { return }
            switch selection {
            case .area(let rect, let display):
                settings.lastAreaRect = StoredRect(rect)
                await runSelfTimer(.area(rect: rect, display: display))
            case .window(let window):
                await runSelfTimer(.window(window))
            }
        }
    }
   ```
4. After `runSelection` / `frozenResult` add:
   ```swift
    /// The countdown and the capture behind Self-Timer and All-in-One's Timer button. Call it with
    /// the capture lock held. The selection overlay goes first, then TidyShot gives up activation
    /// so the user's app is frontmost while the badge counts: its menus open and its keys work.
    /// A countdown that is cancelled leaves nothing behind.
    private func runSelfTimer(_ target: CaptureTarget) async {
        selector.dismiss()
        NSApplication.shared.deactivate()
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        guard let screenFrame = CaptureEngine.screen(forDisplayID: target.displayID)?.frame ?? NSScreen.main?.frame else { return }
        let stage = SelfTimerScreenStage(subject: Geometry.appKitRect(fromCG: target.cgFrame, primaryHeight: primaryHeight),
                                         screenFrame: screenFrame)
        _ = await selfTimer.run(seconds: settings.selfTimerSeconds, stage: stage) { [self] in
            await captureAfterCountdown(target)
        }
    }

    /// The live capture once the panels are gone. The shareable content is read again, and the
    /// display or window is found in it by id: a window may have moved or closed during the
    /// countdown, and an `SCWindow` from before would size the image from its old frame. The
    /// pointer follows Show cursor and the cards are left out, as for a fullscreen capture.
    private func captureAfterCountdown(_ target: CaptureTarget) async {
        guard let content = await loadContent() else { return }
        let fresh: CaptureTarget
        switch target {
        case .display(let display):
            guard let current = content.displays.first(where: { $0.displayID == display.displayID }) else {
                notifier.notifyError("The display is no longer connected.", title: "Self-timer")
                return
            }
            fresh = .display(current)
        case .area(let rect, let display):
            guard let current = content.displays.first(where: { $0.displayID == display.displayID }) else {
                notifier.notifyError("The display is no longer connected.", title: "Self-timer")
                return
            }
            fresh = .area(rect: rect, display: current)
        case .window(let window):
            guard let current = content.windows.first(where: { $0.windowID == window.windowID }) else {
                notifier.notifyError("The window is no longer on screen.", title: "Self-timer")
                return
            }
            fresh = .window(current)
        }
        guard let result = await capture(fresh, excludingWindows: await cardWindows()) else { return }
        await save(result)
    }
   ```
5. In Task 2's `captureAllInOne(preselect:)`, replace the placeholder case (`case .timer:`, its comment, `selector.dismiss()` and `return`) with
   ```swift
            case .timer(let rect, let display):
                // Every All-in-One area kind stores the previous area (spec 2.9). `runSelfTimer`
                // dismisses the overlay; the countdown ends in its own `save(_:)`.
                settings.lastAreaRect = StoredRect(rect)
                await runSelfTimer(.area(rect: rect, display: display))
                return
   ```
   The `return` skips the `selector.dismiss()` and `save(result)` after the `switch`, as the `.scrolling` case does, and leaves `result` unassigned on a path that exits.

- [ ] **Step 7: Menu item, Shortcuts row, Capture picker, Timer button**

`TidyShot/App/StatusMenuController.swift`: in `rebuild()`, after the `Capture Previous Area` item (line 76) add
```swift
        menu.addItem(captureItem("Self-Timer", .selfTimer, #selector(captureSelfTimer)))
```
and after `capturePreviousArea()` (line 122) the action
```swift
    @objc private func captureSelfTimer() { Task { await coordinator.captureSelfTimer() } }
```
`captureItem` appends a recorded shortcut to the title (`Self-Timer  ⌃⇧7`, say) and disables the item while a capture runs.

`TidyShot/Settings/ShortcutsSettingsView.swift`: directly after the `Capture previous area:` row add
```swift
            KeyboardShortcuts.Recorder("Self-timer:", name: .selfTimer)
```
before the `Restore closed overlay:` row.

`TidyShot/Settings/CaptureSettingsView.swift`: at the end of the `Form`, after the `Include window shadow` caption add
```swift
            Picker("Self-timer", selection: $settings.selfTimerSeconds) {
                ForEach(AppSettings.selfTimerChoices, id: \.self) { seconds in
                    Text("\(seconds) seconds").tag(seconds)
                }
            }
```

`TidyShot/Selection/SelectionController.swift`, Task 2's `configureAllInOne(_:)`: replace `view.timerSeconds = nil` and the comment above it with
```swift
        // The Timer button's tooltip, `Capture this area after <n> seconds`, read when the overlay opens.
        view.timerSeconds = settings.selfTimerSeconds
```
`AllInOneToolbar` (Task 2) then shows the Timer button with `AllInOneAction.timer.help(timerSeconds:)`; it is enabled whenever Capture is (`AllInOneAction.isEnabled(hasWindow:)`), and Task 2's `finishAllInOne` already returns `AllInOneChoice.timer(rect:display:)` for it. `AllInOneToolbar.swift` does not change.

- [ ] **Step 8: Run the full suite**

Run:
```bash
xcodegen generate && xcodebuild test -project TidyShot.xcodeproj -scheme TidyShot -destination 'platform=macOS' -derivedDataPath .build 2>&1 | grep -E "Test run with|error:|TEST"
```
Expected: no `error:` lines, `** TEST SUCCEEDED **`, and `Test run with 730 tests in 89 suites passed`. This task adds 13 tests in 1 new suite: 8 in `SelfTimerTests`, 1 in `SelectionOutcomeTests`, 2 in `AppSettingsTests`, 2 in `ShortcutsTests`. No test is removed; `ShortcutsTests` and the scrolling controller only use the renamed Escape name.

- [ ] **Step 9: Hand checks (Tim)**

For Tim; the implementer builds the Release configuration, lists these in its report and goes on to Step 10. Task 6's checklist repeats them.
```bash
xcodebuild -project TidyShot.xcodeproj -scheme TidyShot -configuration Release -derivedDataPath .build-rel build -quiet
```
Tim opens `.build-rel/Build/Products/Release/TidyShot.app`.
- Settings > Shortcuts has `Self-timer:` with no key; record ⌃⇧7. The menu shows `Self-Timer  ⌃⇧7` after Capture Previous Area. Settings > Capture has the `Self-timer` picker with `3 seconds`, `5 seconds`, `10 seconds`, 5 by default.
- Press the Self-Timer shortcut: the dimmed overlay with crosshair, loupe and the window highlight opens. Drag an area: the overlay goes, a 96 pt badge with `5` and `Esc to cancel` sits centred on the area with a dashed frame around it, counts 5, 4, 3, 2, 1 once a second, then both vanish and the area is captured and shown as a card. The badge and the frame are not in the image; the card is not either.
- Start the timer, click another app, open one of its menus with the mouse, and wait: the capture shows the open menu (the point of the feature). Repeat with a menu opened by keyboard in that app: the app still has the keys, so TidyShot is not frontmost during the countdown.
- Click a window instead of dragging: the badge centres on the window, and the capture is that window with transparent corners. Move the window during the countdown: the capture follows it. Close it before zero: the notification `The window is no longer on screen.` titled `Self-timer`, no capture.
- Escape during the countdown, with another app frontmost: badge and frame go, nothing is captured, no card. Escape in other apps works normally again afterwards (type in a text field). Escape in the selection overlay (before the countdown) still cancels the selection.
- During the countdown press ⌃⇧4 and the menu bar items: nothing starts (they are disabled), and the countdown is not disturbed. Press the Self-Timer shortcut again: nothing. After the capture, everything works.
- Pick a rect near the top-right corner of the screen: the badge stays fully on screen. On a second display, the badge and frame are on that display.
- With `Show cursor in screenshots` on, the capture shows the pointer where it is at zero; off, it does not. After a self-timer area, Capture Previous Area (⌃⇧6) repeats that area. After a window pick, it does not change.
- All-in-One (⌃⇧1): the Timer button sits between Scrolling and Cancel, its tooltip reads `Capture this area after 5 seconds` (3 and 10 after changing the picker); clicking it counts down on the selected rect and captures it as above, and Capture Previous Area then repeats that rect.
- Scrolling capture still ends on Escape (select an area, Start, press Escape: the session cancels), which proves the renamed hotkey still serves it.

- [ ] **Step 10: Commit**

```bash
git add TidyShot/SelfTimer/SelfTimerController.swift TidyShot/SelfTimer/SelfTimerPanel.swift TidyShot/Selection/Selection.swift TidyShot/Selection/SelectionOutcome.swift TidyShot/Selection/SelectionController.swift TidyShot/Capture/CaptureTarget.swift TidyShot/Settings/AppSettings.swift TidyShot/Settings/CaptureSettingsView.swift TidyShot/Settings/ShortcutsSettingsView.swift TidyShot/App/Shortcuts.swift TidyShot/App/AppCoordinator.swift TidyShot/App/StatusMenuController.swift TidyShot/Scrolling/ScrollCaptureController.swift TidyShotTests/SelfTimerTests.swift TidyShotTests/SelectionOutcomeTests.swift TidyShotTests/AppSettingsTests.swift TidyShotTests/ShortcutsTests.swift
git commit -m "feat: Self-Timer with a countdown badge and the shared Escape hotkey"
```
Check `git status` is clean afterwards (`TidyShot.xcodeproj` is ignored).

### Task 4: Pin to screen

**Files:**
- Create: `TidyShot/Pin/PinGeometry.swift` (`PinGeometry`, `PinOpacity`, `PinCommand`, `PinKeys`; pure)
- Create: `TidyShot/Pin/PinController.swift` (`PinController`)
- Create: `TidyShot/Pin/PinPanel.swift` (`PinPanel`)
- Create: `TidyShot/Pin/PinView.swift` (`PinView`)
- Modify: `TidyShot/Output/ThumbnailMaker.swift` (`scaled(_:maxSide:)`, and `thumbnail(from:maxSide:)` at line 62 calls it)
- Modify: `TidyShot/Capture/CaptureTarget.swift` (an extension next to `displayID`, line 14)
- Modify: `TidyShot/Overlay/QuickAccessController.swift` (`Actions`, lines 29-47: `pin`; `makeCard`, line 173)
- Modify: `TidyShot/Overlay/QuickAccessModel.swift` (`onPin`, after `onAnnotate`, line 20)
- Modify: `TidyShot/Overlay/QuickAccessView.swift` (the right column, lines 17-35; `menuItems`, lines 74-87)
- Modify: `TidyShot/App/AppCoordinator.swift` (`pins`, `pinningIDs`, `latestCaptureArea` next to `latestCapture`, line 59; `save(_:)`, lines 293 and 329-333; `overlayActions()`, line 484; `removeRecord`, line 965; `loadAndPresentEditor`, lines 1351-1368; new `loadImage(for:)` and `pin(recordID:)` after it)
- Modify: `TidyShot/App/StatusMenuController.swift` (`rebuild()`, after the separator at line 90 and before `Settings…`, line 91; two `@objc` actions)
- Test: `TidyShotTests/PinGeometryTests.swift` (new, struct `PinGeometryTests`), `TidyShotTests/ThumbnailMakerTests.swift` (one test added)

Line numbers are `main`'s at 4c67c04. Tasks 1 to 3 touch `AppCoordinator`, `StatusMenuController`, `CaptureTarget` and the shortcut files; find each place by the quoted code.

**Interfaces:**
- Consumes:
  - `main`: `ScaledImage` (`Output/ScaledImage.swift`); `ImageEncoder.decode(_:) -> (image: CGImage, scale: CGFloat)?`; `ThumbnailMaker.targetSize(for:maxSide:)`; `AppCoordinator.imageData(of:downloadTitle:)`, `openEditor(recordID:)`, `openEditorAfterMenuTracking(recordID:)`, `copyImage(recordID:)`, `saveAs(recordID:)` (6a Task 5), `afterMenuTracking(_:)`, `deletingIDs`, `latestCapture`, `forgetLatestCapture(_:)`, `removeRecord(id:)`, `history.record(id:)`, `notifier.notifyError(_:title:)`; `Geometry.appKitRect(fromCG:primaryHeight:)`; `QuickAccessModel`, `QuickAccessController.Actions`, `QuickAccessView`; `StatusMenuController.item(_:_:key:)`.
  - Task 3 added `CaptureTarget.cgFrame`; this task adds `areaRect` beside it. `CaptureTarget.displayID` (6a Task 3) is unchanged.
- Produces (Task 5, the URL scheme, relies on these):
  ```swift
  // Pin/PinGeometry.swift (all nonisolated)
  enum PinGeometry {
      static let minimumSide: CGFloat          // 40
      static let fitFraction: CGFloat          // 0.8
      static let zoomStep: CGFloat             // 1.1
      static let maxPixelSide: Int             // 8_192
      static func initialFrame(imagePoints: CGSize, preferred: CGRect?, visibleFrame: CGRect) -> CGRect
      static func nudged(_ frame: CGRect, dx: Int, dy: Int, shift: Bool) -> CGRect
      static func zoomed(_ frame: CGRect, factor: CGFloat) -> CGRect
      static func actualSize(_ frame: CGRect, imagePoints: CGSize) -> CGRect
      static func minimumSize(aspect: CGSize, initial: CGSize) -> CGSize
      static func downsampleMaxSide(pixelWidth: Int, pixelHeight: Int, screenPixelSide: Int) -> Int?
  }
  enum PinOpacity { static let presets: [Double]; static func changed(_ opacity: Double, steps: Int) -> Double
                    static func title(for opacity: Double) -> String; static func matches(_ a: Double, _ b: Double) -> Bool }
  enum PinCommand: Equatable, Sendable { case nudge(dx: Int, dy: Int, shift: Bool), zoomIn, zoomOut, actualSize, copyImage, close }
  enum PinKeys { static func command(keyCode: UInt16, characters: String?, command: Bool, shift: Bool,
                                     option: Bool, control: Bool) -> PinCommand? }

  // ThumbnailMaker
  static func scaled(_ image: CGImage, maxSide: Int) -> CGImage?     // nonisolated; never crops

  // CaptureTarget
  extension CaptureTarget { var areaRect: CGRect? { get } }          // the rect of an .area target, else nil

  // PinController (Pin/PinController.swift)
  final class PinController {
      struct Actions { var copyImage: (UUID) -> Void; var saveAs: (UUID) -> Void; var annotate: (UUID) -> Void }
      var hasPins: Bool { get }
      var hasLockedPins: Bool { get }
      func bringToFront(recordID: UUID) -> Bool
      func open(recordID: UUID, image: CGImage, imagePoints: CGSize, frame: CGRect, actions: Actions)
      func close(recordID: UUID)
      func closeAll()
      func unlockAll()
  }

  // AppCoordinator
  func pin(recordID: UUID) async                                    // the card's Pin, and the URL scheme's action=pin
  func loadImage(for record: CaptureRecord, downloadTitle: String = "Opening the capture…",
                 failureTitle: String = "Could not open the capture") async -> ScaledImage?
  var hasPins: Bool { get }; var hasLockedPins: Bool { get }
  func unlockPins(); func closePins()
  ```
  The area a capture was taken from is kept in `latestCaptureArea`, set in `save(_:)` right after `persist` returns and before anything the caller does next, so a `pin(recordID:)` that follows a capture at once (Task 5's `action=pin`) already finds it. Task 5's `save(_:intent:)` keeps that assignment.

Behaviour (spec 2.9, Pin to screen):
- A pin is a floating copy of a capture. `PinController` owns the pins; each is a `PinPanel` (borderless, non-activating, resizable, level `.floating`, joins all Spaces, has a shadow, can become key without activating TidyShot) hosting `PinView`, a layer-backed `NSView` whose layer shows the image with `.trilinear` minification and a hairline border. Opening a pin does not close the card, and it does not take key focus from the user's app: the pin becomes key when it is clicked.
- Opening: the card's `Pin` button (`pin` symbol, help `Pin to screen`, between Annotate and Delete) and the context menu's `Pin to Screen` (after Annotate), and Task 5's `action=pin`. The image is the retained capture for the newest card, otherwise the record's PNG through `imageData(of:)` and a detached decode, shared with `openEditor` as `loadImage(for:)`. An image over 8,192 px on a side is shown from a downsample to the screen's pixel size, so a 65,536 px scrolling capture pins as a fitted strip; the pin keeps the capture's point size for Actual Size and its aspect ratio. A second Pin on a capture that is pinned already brings that pin to the front.
- Placement: `PinGeometry.initialFrame`: the image at its point size, scaled down to fit 80 % of the visible frame, centred on the spot it was captured from when that is known (an area capture's rect, kept in `latestCaptureArea` for the newest capture), otherwise centred on the pointer's screen; always inside the visible frame.
- Interaction: drag anywhere to move; drag an edge to resize with the aspect ratio fixed (`contentAspectRatio`) and the shorter side at least 40 pt (`PinGeometry.minimumSize`). While the pin is key: arrows move it 1 pt, Shift-arrows 10 pt; Command-plus and Command-minus zoom by 10 % about the centre; Command-0 is actual size; Command-C copies the image; Escape or Command-W closes. Option-scroll changes the opacity in steps of 5 %, between 10 % and 100 %.
- Context menu: `Copy Image`, `Save As…`, `Annotate`, `Opacity` (submenu `100%`, `90%`, `75%`, `50%`, `25%`, a check on the current one), `Actual Size`, `Lock`, a separator, `Close`. Copy Image and Save As… export the capture as the record holds it now; the pin keeps the pixels it was opened with.
- Lock makes the pin click-through (`ignoresMouseEvents = true`) and removes its border. The status menu shows `Unlock Pinned Screenshots` while any pin is locked and `Close Pinned Screenshots` while any pin exists, both before `Settings…`.
- Lifetime: pins live in memory, close at quit and are not restored. Deleting a capture (or removing it from history) closes its pins. Pins stay in captures (they are content the user placed); the scrolling stream excludes them with the rest of TidyShot.
- The spec names `ThumbnailMaker.thumbnail(from:maxSide:)` for the downsample. That function cuts an image taller than three times its width to its top (`cropForThumbnail`), which would pin a scrolling capture as a sliver. This task adds `ThumbnailMaker.scaled(_:maxSide:)`, the same drawing without the cut, and Task 6 writes the correction into 2.9.

- [ ] **Step 1: Write the failing tests**

`TidyShotTests/PinGeometryTests.swift` (new):
```swift
import CoreGraphics
import Foundation
import Testing
@testable import TidyShot

/// Pin to screen's pure parts (spec 2.9): where a pin opens, how it moves and zooms, its opacity
/// steps and which key does what. AppKit global points, origin bottom-left.
struct PinGeometryTests {
    let visible = CGRect(x: 0, y: 0, width: 1440, height: 900)

    func approx(_ a: CGRect, _ b: CGRect, tolerance: CGFloat = 1e-9) -> Bool {
        abs(a.minX - b.minX) < tolerance && abs(a.minY - b.minY) < tolerance
            && abs(a.width - b.width) < tolerance && abs(a.height - b.height) < tolerance
    }

    func approx(_ a: CGSize, _ b: CGSize, tolerance: CGFloat = 1e-9) -> Bool {
        abs(a.width - b.width) < tolerance && abs(a.height - b.height) < tolerance
    }

    // MARK: Placement

    @Test func anImageThatFitsKeepsItsPointSizeAndIsCentred() {
        let frame = PinGeometry.initialFrame(imagePoints: CGSize(width: 400, height: 300), preferred: nil, visibleFrame: visible)
        #expect(frame == CGRect(x: 520, y: 300, width: 400, height: 300))
        // A display right of and below the main one has an offset visible frame.
        let second = CGRect(x: 1440, y: -200, width: 1920, height: 1080)
        let onSecond = PinGeometry.initialFrame(imagePoints: CGSize(width: 400, height: 300), preferred: nil, visibleFrame: second)
        #expect(onSecond == CGRect(x: 2200, y: 190, width: 400, height: 300))
        // The origin is a whole point: a half point rounds up.
        let odd = PinGeometry.initialFrame(imagePoints: CGSize(width: 401, height: 301), preferred: nil, visibleFrame: visible)
        #expect(odd == CGRect(x: 520, y: 300, width: 401, height: 301))
    }

    @Test func aLargeImageIsScaledToEightyPercentOfTheVisibleFrame() {
        #expect(PinGeometry.fitFraction == 0.8)
        let full = PinGeometry.initialFrame(imagePoints: CGSize(width: 1440, height: 900), preferred: nil, visibleFrame: visible)
        #expect(approx(full, CGRect(x: 144, y: 90, width: 1152, height: 720)))
        // Wide: the width limits it.
        let wide = PinGeometry.initialFrame(imagePoints: CGSize(width: 2880, height: 900), preferred: nil, visibleFrame: visible)
        #expect(approx(wide, CGRect(x: 144, y: 270, width: 1152, height: 360)))
        // Tall: the height limits it.
        let tall = PinGeometry.initialFrame(imagePoints: CGSize(width: 720, height: 1800), preferred: nil, visibleFrame: visible)
        #expect(approx(tall, CGRect(x: 576, y: 90, width: 288, height: 720)))
        #expect(abs(tall.width / tall.height - 720.0 / 1800.0) < 1e-9)
    }

    @Test func thePreferredSpotIsKept() {
        let spot = CGRect(x: 100, y: 200, width: 400, height: 300)
        let frame = PinGeometry.initialFrame(imagePoints: spot.size, preferred: spot, visibleFrame: visible)
        #expect(frame == spot)
    }

    @Test func aPreferredSpotPartlyOffScreenIsMovedOnScreen() {
        let size = CGSize(width: 400, height: 300)
        let bottomLeft = PinGeometry.initialFrame(imagePoints: size, preferred: CGRect(x: -50, y: -20, width: 400, height: 300),
                                                  visibleFrame: visible)
        #expect(bottomLeft == CGRect(x: 0, y: 0, width: 400, height: 300))
        let topRight = PinGeometry.initialFrame(imagePoints: size, preferred: CGRect(x: 1300, y: 700, width: 400, height: 300),
                                                visibleFrame: visible)
        #expect(topRight == CGRect(x: 1040, y: 600, width: 400, height: 300))
        // A spot on no screen at all (its display was unplugged) still ends up on this one.
        let gone = PinGeometry.initialFrame(imagePoints: size, preferred: CGRect(x: 5000, y: 5000, width: 400, height: 300),
                                            visibleFrame: visible)
        #expect(gone == CGRect(x: 1040, y: 600, width: 400, height: 300))
    }

    /// A scrolling capture is far taller than the area it was taken from: it is fitted, centred on
    /// the area's centre, and moved down to the screen's edge.
    @Test func aFittedImageIsCentredOnThePreferredCentre() {
        let frame = PinGeometry.initialFrame(imagePoints: CGSize(width: 800, height: 5760),
                                             preferred: CGRect(x: 100, y: 100, width: 800, height: 500), visibleFrame: visible)
        #expect(frame == CGRect(x: 450, y: 0, width: 100, height: 720))
    }

    // MARK: Moving, zooming, actual size

    @Test func nudgesMoveOneOrTenPoints() {
        let frame = CGRect(x: 100, y: 100, width: 50, height: 50)
        #expect(PinGeometry.nudged(frame, dx: 1, dy: 0, shift: false) == CGRect(x: 101, y: 100, width: 50, height: 50))
        #expect(PinGeometry.nudged(frame, dx: -1, dy: 0, shift: true) == CGRect(x: 90, y: 100, width: 50, height: 50))
        // Up is +1: AppKit's y grows upward.
        #expect(PinGeometry.nudged(frame, dx: 0, dy: 1, shift: false) == CGRect(x: 100, y: 101, width: 50, height: 50))
        #expect(PinGeometry.nudged(frame, dx: 0, dy: -1, shift: true) == CGRect(x: 100, y: 90, width: 50, height: 50))
    }

    @Test func zoomKeepsTheCentreAndInverts() {
        #expect(PinGeometry.zoomStep == 1.1)
        let frame = CGRect(x: 100, y: 100, width: 400, height: 300)
        let larger = PinGeometry.zoomed(frame, factor: PinGeometry.zoomStep)
        #expect(approx(larger, CGRect(x: 80, y: 85, width: 440, height: 330)))
        #expect(approx(PinGeometry.zoomed(larger, factor: 1 / PinGeometry.zoomStep), frame))
    }

    /// The shorter side never goes below 40 pt, or below what it is when it is under 40 already
    /// (a fitted strip): the pin can then only grow.
    @Test func zoomStopsAtTheMinimumSide() {
        #expect(PinGeometry.minimumSide == 40)
        let small = PinGeometry.zoomed(CGRect(x: 0, y: 0, width: 160, height: 120), factor: 0.25)
        #expect(approx(small, CGRect(x: 160.0 / 3, y: 40, width: 160.0 / 3, height: 40)))
        let strip = CGRect(x: 100, y: 100, width: 30, height: 225)
        #expect(approx(PinGeometry.zoomed(strip, factor: 0.5), strip))
        #expect(approx(PinGeometry.zoomed(strip, factor: 2), CGRect(x: 85, y: -12.5, width: 60, height: 450)))
    }

    @Test func minimumSizeKeepsTheAspect() {
        #expect(approx(PinGeometry.minimumSize(aspect: CGSize(width: 400, height: 300), initial: CGSize(width: 500, height: 375)),
                       CGSize(width: 160.0 / 3, height: 40)))
        #expect(approx(PinGeometry.minimumSize(aspect: CGSize(width: 300, height: 400), initial: CGSize(width: 375, height: 500)),
                       CGSize(width: 40, height: 160.0 / 3)))
        #expect(PinGeometry.minimumSize(aspect: CGSize(width: 100, height: 100), initial: CGSize(width: 90, height: 90))
                == CGSize(width: 40, height: 40))
        // A strip fitted to the screen: 40 pt wide at most.
        #expect(PinGeometry.minimumSize(aspect: CGSize(width: 800, height: 5760), initial: CGSize(width: 100, height: 720))
                == CGSize(width: 40, height: 288))
        // One that is narrower than 40 pt already keeps its width as the floor.
        #expect(PinGeometry.minimumSize(aspect: CGSize(width: 800, height: 6000), initial: CGSize(width: 30, height: 225))
                == CGSize(width: 30, height: 225))
    }

    @Test func actualSizeKeepsTheCentre() {
        let frame = CGRect(x: 100, y: 100, width: 200, height: 150)
        #expect(PinGeometry.actualSize(frame, imagePoints: CGSize(width: 400, height: 300))
                == CGRect(x: 0, y: 25, width: 400, height: 300))
    }

    @Test func largeImagesAreShownFromADownsample() {
        #expect(PinGeometry.maxPixelSide == 8_192)
        #expect(PinGeometry.downsampleMaxSide(pixelWidth: 8_192, pixelHeight: 4_000, screenPixelSide: 5_120) == nil)
        #expect(PinGeometry.downsampleMaxSide(pixelWidth: 3_094, pixelHeight: 65_536, screenPixelSide: 5_120) == 5_120)
        #expect(PinGeometry.downsampleMaxSide(pixelWidth: 8_193, pixelHeight: 100, screenPixelSide: 5_120) == 5_120)
        // The result never exceeds the limit, whatever the screen.
        #expect(PinGeometry.downsampleMaxSide(pixelWidth: 9_000, pixelHeight: 100, screenPixelSide: 10_000) == 8_192)
    }

    // MARK: Opacity

    @Test func opacityStepsClampAndStayOnTheGrid() {
        #expect(PinOpacity.changed(1.0, steps: -1) == 0.95)
        #expect(PinOpacity.changed(1.0, steps: -18) == 0.1)
        #expect(PinOpacity.changed(1.0, steps: -30) == 0.1)
        #expect(PinOpacity.changed(0.1, steps: 1) == 0.15)
        #expect(PinOpacity.changed(0.9, steps: 5) == 1.0)
        // Off the 5 % grid snaps to it.
        #expect(PinOpacity.changed(0.77, steps: 0) == 0.75)
        // Single steps do not drift.
        var opacity = 1.0
        for _ in 0..<18 { opacity = PinOpacity.changed(opacity, steps: -1) }
        #expect(opacity == 0.1)
        for _ in 0..<18 { opacity = PinOpacity.changed(opacity, steps: 1) }
        #expect(opacity == 1.0)
    }

    @Test func opacityPresetsAndTitles() {
        #expect(PinOpacity.presets == [1.0, 0.9, 0.75, 0.5, 0.25])
        #expect(PinOpacity.presets.map(PinOpacity.title(for:)) == ["100%", "90%", "75%", "50%", "25%"])
        #expect(PinOpacity.matches(0.9, 0.9000001))
        #expect(!PinOpacity.matches(0.85, 0.9))
    }

    // MARK: Keys (key codes: 53 Escape, 123 left, 124 right, 125 down, 126 up)

    func key(_ code: UInt16, _ characters: String? = nil, command: Bool = false, shift: Bool = false,
             option: Bool = false, control: Bool = false) -> PinCommand? {
        PinKeys.command(keyCode: code, characters: characters, command: command, shift: shift, option: option, control: control)
    }

    @Test func arrowKeysNudgeAndEscapeCloses() {
        #expect(key(123) == .nudge(dx: -1, dy: 0, shift: false))
        #expect(key(124) == .nudge(dx: 1, dy: 0, shift: false))
        #expect(key(125) == .nudge(dx: 0, dy: -1, shift: false))
        #expect(key(126) == .nudge(dx: 0, dy: 1, shift: false))
        #expect(key(126, shift: true) == .nudge(dx: 0, dy: 1, shift: true))
        #expect(key(53) == .close)
    }

    @Test func commandKeysZoomCopyAndClose() {
        #expect(key(24, "=", command: true) == .zoomIn)
        #expect(key(24, "+", command: true, shift: true) == .zoomIn)
        #expect(key(69, "+", command: true) == .zoomIn)
        #expect(key(27, "-", command: true) == .zoomOut)
        #expect(key(78, "-", command: true) == .zoomOut)
        #expect(key(29, "0", command: true) == .actualSize)
        #expect(key(8, "c", command: true) == .copyImage)
        #expect(key(13, "w", command: true) == .close)
        // Caps Lock arrives as a capital.
        #expect(key(13, "W", command: true) == .close)
    }

    @Test func otherModifiersAndKeysAreIgnored() {
        #expect(key(8, "c") == nil)
        #expect(key(13, "w") == nil)
        #expect(key(8, "c", command: true, shift: true) == nil)
        #expect(key(8, "c", command: true, option: true) == nil)
        #expect(key(8, "c", command: true, control: true) == nil)
        #expect(key(123, command: true) == nil)
        #expect(key(123, option: true) == nil)
        #expect(key(53, option: true) == nil)
        #expect(key(12, "q", command: true) == nil)
        #expect(key(0) == nil)
    }
}
```

`TidyShotTests/ThumbnailMakerTests.swift`, inside `struct ThumbnailMakerTests`, after `thumbnailFromImageKeepsAspectAndAlpha`:
```swift
    /// Pin to screen shows a huge capture from `scaled`: a tall image stays whole, where
    /// `thumbnail(from:)` cuts it to its top rows.
    @Test func scaledKeepsATallImageWholeAndNeverUpscales() throws {
        let tall = makeImage(width: 100, height: 700)
        let whole = try #require(ThumbnailMaker.scaled(tall, maxSide: 350))
        #expect(whole.width == 50)
        #expect(whole.height == 350)
        #expect(whole.alphaInfo != .none && whole.alphaInfo != .noneSkipLast && whole.alphaInfo != .noneSkipFirst)
        // The thumbnail of the same image is its top 150 rows (`cropForThumbnail`), not the whole.
        let cut = try #require(ThumbnailMaker.thumbnail(from: tall, maxSide: 350))
        #expect(cut.width == 100)
        #expect(cut.height == 150)
        let small = try #require(ThumbnailMaker.scaled(makeImage(width: 100, height: 50), maxSide: 350))
        #expect(small.width == 100)
        #expect(small.height == 50)
    }
```

- [ ] **Step 2: Run the tests and see them fail**

Run:
```bash
xcodegen generate && xcodebuild test -project TidyShot.xcodeproj -scheme TidyShot -destination 'platform=macOS' -derivedDataPath .build 2>&1 | grep -E "Test run with|error:|TEST"
```
Expected: the build fails with `error:` lines such as `cannot find 'PinGeometry' in scope`, `cannot find 'PinOpacity' in scope`, `cannot find 'PinKeys' in scope` and `type 'ThumbnailMaker' has no member 'scaled'`, then `** TEST FAILED **` or `** BUILD FAILED **`. No test runs.

- [ ] **Step 3: The pure parts**

`TidyShot/Pin/PinGeometry.swift`:
```swift
import CoreGraphics

/// Pin to screen's geometry (spec 2.9). AppKit global points, origin bottom-left.
nonisolated enum PinGeometry {
    /// The shorter side of a pin never goes below this by resizing or zooming, or below what it
    /// is when it starts under it (a fitted strip).
    static let minimumSide: CGFloat = 40
    /// A pin opens at most this fraction of the visible frame on each axis.
    static let fitFraction: CGFloat = 0.8
    /// Command-plus multiplies the size by this, Command-minus divides by it.
    static let zoomStep: CGFloat = 1.1
    /// An image with a side over this many pixels is shown from a downsample.
    static let maxPixelSide = 8_192

    /// Where a pin opens: `imagePoints` (the capture's size in points) scaled down, never up, to fit
    /// `fitFraction` of `visibleFrame`, centred on `preferred`'s centre (the area the capture was
    /// taken from) or on the visible frame, with a whole-point origin, then moved inside
    /// `visibleFrame`. `imagePoints` has positive sides.
    static func initialFrame(imagePoints: CGSize, preferred: CGRect?, visibleFrame: CGRect) -> CGRect {
        let fit = min(1, visibleFrame.width * fitFraction / imagePoints.width,
                      visibleFrame.height * fitFraction / imagePoints.height)
        let size = CGSize(width: imagePoints.width * fit, height: imagePoints.height * fit)
        let centre = preferred.map { CGPoint(x: $0.midX, y: $0.midY) } ?? CGPoint(x: visibleFrame.midX, y: visibleFrame.midY)
        var x = (centre.x - size.width / 2).rounded()
        var y = (centre.y - size.height / 2).rounded()
        x = min(max(x, visibleFrame.minX), visibleFrame.maxX - size.width)
        y = min(max(y, visibleFrame.minY), visibleFrame.maxY - size.height)
        return CGRect(origin: CGPoint(x: x, y: y), size: size)
    }

    /// An arrow key: one point, or ten with Shift, in the direction (`dx`, `dy`), up being +1.
    static func nudged(_ frame: CGRect, dx: Int, dy: Int, shift: Bool) -> CGRect {
        let step: CGFloat = shift ? 10 : 1
        return frame.offsetBy(dx: CGFloat(dx) * step, dy: CGFloat(dy) * step)
    }

    /// `frame` scaled by `factor` about its centre. A factor that would take the shorter side
    /// below `min(minimumSide, its current value)` is raised to the one that reaches it exactly.
    static func zoomed(_ frame: CGRect, factor: CGFloat) -> CGRect {
        let shorter = min(frame.width, frame.height)
        let floor = min(minimumSide, shorter)
        let applied = shorter * factor < floor ? floor / shorter : factor
        let size = CGSize(width: frame.width * applied, height: frame.height * applied)
        return CGRect(x: frame.midX - size.width / 2, y: frame.midY - size.height / 2,
                      width: size.width, height: size.height)
    }

    /// The capture's point size, about the centre of `frame`.
    static func actualSize(_ frame: CGRect, imagePoints: CGSize) -> CGRect {
        CGRect(x: frame.midX - imagePoints.width / 2, y: frame.midY - imagePoints.height / 2,
               width: imagePoints.width, height: imagePoints.height)
    }

    /// The panel's `contentMinSize`: the image's aspect with the shorter side at
    /// `min(minimumSide, the shorter side of initial)`.
    static func minimumSize(aspect: CGSize, initial: CGSize) -> CGSize {
        let floor = min(minimumSide, initial.width, initial.height)
        if aspect.width <= aspect.height {
            return CGSize(width: floor, height: floor * aspect.height / aspect.width)
        }
        return CGSize(width: floor * aspect.width / aspect.height, height: floor)
    }

    /// The longest side to downsample to, or nil when the image needs none: only an image with a
    /// side over `maxPixelSide` is, to the screen's longer pixel side, never above `maxPixelSide`.
    static func downsampleMaxSide(pixelWidth: Int, pixelHeight: Int, screenPixelSide: Int) -> Int? {
        guard max(pixelWidth, pixelHeight) > maxPixelSide else { return nil }
        return min(max(screenPixelSide, 1), maxPixelSide)
    }
}

/// A pin's opacity: 10 % to 100 % in steps of 5 %, in whole percents so nothing drifts.
nonisolated enum PinOpacity {
    static let presets: [Double] = [1.0, 0.9, 0.75, 0.5, 0.25]
    private static let step = 5
    private static let range = 10...100

    /// `opacity` moved by `steps` of 5 %, snapped to the 5 % grid and clamped to 10 % to 100 %.
    static func changed(_ opacity: Double, steps: Int) -> Double {
        let percent = Int((opacity * 100).rounded())
        let snapped = Int((Double(percent) / Double(step)).rounded()) * step
        let next = min(max(snapped + steps * step, range.lowerBound), range.upperBound)
        return Double(next) / 100
    }

    /// `90%` for 0.9: the menu item's title.
    static func title(for opacity: Double) -> String {
        "\(Int((opacity * 100).rounded()))%"
    }

    /// Whether two opacities are the same preset (the menu's check mark).
    static func matches(_ a: Double, _ b: Double) -> Bool {
        abs(a - b) < 0.001
    }
}

/// What a key does while a pin is key.
nonisolated enum PinCommand: Equatable, Sendable {
    case nudge(dx: Int, dy: Int, shift: Bool)
    case zoomIn
    case zoomOut
    case actualSize
    case copyImage
    case close
}

nonisolated enum PinKeys {
    /// The command for a key press, or nil. Escape and the arrows without Command; Command with
    /// `=`/`+`, `-`, `0`, `c` or `w` (`characters` is `charactersIgnoringModifiers`). Option and
    /// Control cancel any match, and Shift only counts for the arrows and the zoom keys (`+` is
    /// Shift-`=`).
    static func command(keyCode: UInt16, characters: String?, command: Bool, shift: Bool,
                        option: Bool, control: Bool) -> PinCommand? {
        guard !option, !control else { return nil }
        if !command {
            switch keyCode {
            case 53: return .close
            case 123: return .nudge(dx: -1, dy: 0, shift: shift)
            case 124: return .nudge(dx: 1, dy: 0, shift: shift)
            case 125: return .nudge(dx: 0, dy: -1, shift: shift)
            case 126: return .nudge(dx: 0, dy: 1, shift: shift)
            default: return nil
            }
        }
        switch characters?.lowercased() ?? "" {
        case "=", "+": return .zoomIn
        case "-", "_": return .zoomOut
        case "0": return shift ? nil : .actualSize
        case "c": return shift ? nil : .copyImage
        case "w": return shift ? nil : .close
        default: return nil
        }
    }
}
```

`TidyShot/Output/ThumbnailMaker.swift`: add after `thumbnail(from:maxSide:)`'s doc and replace its body (lines 54-67) so the drawing is shared:
```swift
    /// Draws `image`, cut by `cropForThumbnail(_:)`, into a smaller bitmap. Used at capture time,
    /// when the CGImage is already in memory.
    static func thumbnail(from image: CGImage, maxSide: Int = maxSide) -> CGImage? {
        let crop = cropForThumbnail(CGSize(width: image.width, height: image.height))
        let image = crop.height < CGFloat(image.height) ? (image.cropping(to: crop) ?? image) : image
        return scaled(image, maxSide: maxSide)
    }

    /// Draws all of `image` into a bitmap whose longest side is at most `maxSide` pixels: aspect
    /// kept, never upscaled, alpha kept (sRGB). Unlike `thumbnail(from:maxSide:)` it never cuts a
    /// tall image to its top. Pin to screen shows captures over 8,192 px from it.
    static func scaled(_ image: CGImage, maxSide: Int) -> CGImage? {
        let size = targetSize(for: CGSize(width: image.width, height: image.height), maxSide: maxSide)
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8,
                                      bytesPerRow: 0, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(origin: .zero, size: size))
        return context.makeImage()
    }
```

`TidyShot/Capture/CaptureTarget.swift`: after Task 3's `cgFrame` extension (or after the `displayID` extension, line 20) add
```swift
extension CaptureTarget {
    /// The rect of an area capture (CoreGraphics global points), nil for a display or a window.
    /// A pin of the newest capture opens over it.
    var areaRect: CGRect? {
        if case .area(let rect, _) = self { rect } else { nil }
    }
}
```

- [ ] **Step 4: The pin windows**

AppKit code: structure, exact names and the non-obvious lines; the implementer writes the bodies.

`TidyShot/Pin/PinPanel.swift`: `final class PinPanel: NSPanel`, `init(contentRect: CGRect)`.
- `styleMask: [.borderless, .nonactivatingPanel, .resizable]`, `backing: .buffered`, `defer: false`. A borderless window with `.resizable` resizes from its edges.
- `level = .floating`, `isFloatingPanel = true`, `hidesOnDeactivate = false`, `collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]`, `isOpaque = false`, `backgroundColor = .clear`, `hasShadow = true`, `isMovableByWindowBackground = true`, `animationBehavior = .none`, `isReleasedWhenClosed = false`.
- `override var canBecomeKey: Bool { true }` (keys without activating TidyShot), `canBecomeMain` false.

`TidyShot/Pin/PinView.swift`: `final class PinView: NSView`.
- `init(image: CGImage)`: `wantsLayer = true`; `layer.contents = image`, `contentsGravity = .resize`, `minificationFilter = .trilinear`, `magnificationFilter = .linear`, `borderWidth` one device pixel (`1 / backingScaleFactor`, set again in `viewDidChangeBackingProperties`), `borderColor = NSColor(white: 0.5, alpha: 0.6).cgColor`.
- `var showsBorder: Bool { didSet }` sets the border width to 0 or the hairline (Lock turns it off).
- Closures set by the controller: `onCommand: (PinCommand) -> Void`, `onOpacitySteps: (Int) -> Void`, `onSaveAs`, `onAnnotate`, `onLock`, `menuState: () -> Double` (the current opacity, for the check).
- `override var mouseDownCanMoveWindow: Bool { true }` (a plain drag moves the panel), `acceptsFirstMouse` true, `acceptsFirstResponder` true, `isOpaque` false.
- `keyDown(with:)` and `performKeyEquivalent(with:)` both call `PinKeys.command(keyCode: event.keyCode, characters: event.charactersIgnoringModifiers, command: event.modifierFlags.contains(.command), shift: …, option: …, control: …)` and, on a match, `onCommand` and return true (`keyDown` falls back to `super` otherwise; `performKeyEquivalent` returns false). Command keys arrive through `performKeyEquivalent` because the app has no main menu items for them.
- `scrollWheel(with:)`: without Option, pass to `nextResponder`. With Option, accumulate `scrollingDeltaY` in a remainder; one step per 8 points for a trackpad (`hasPreciseScrollingDeltas`) or per 1 for a wheel; positive is more opaque; `onOpacitySteps(steps)` for the whole steps, the rest stays in the remainder; reset it at `phase == .ended`.
- `menu(for:)` builds the context menu each time: `Copy Image` (`.copyImage`), `Save As…`, `Annotate`, `Opacity` with a submenu of `PinOpacity.presets` titled `PinOpacity.title(for:)` and `state = .on` where `PinOpacity.matches(preset, menuState())`, `Actual Size` (`.actualSize`), `Lock`, a separator, `Close` (`.close`). Targets are the view; the actions call the closures. No key equivalents on the items.

`TidyShot/Pin/PinController.swift`: `final class PinController`.
- `struct Actions { var copyImage: (UUID) -> Void; var saveAs: (UUID) -> Void; var annotate: (UUID) -> Void }`.
- A private `Pin` class per pin: `recordID`, `panel`, `view`, `imagePoints`, `opacity` (1.0), `isLocked`.
- `open(recordID:image:imagePoints:frame:actions:)`: a `PinPanel(contentRect: frame)` with a `PinView(image:)` as content view; `panel.contentAspectRatio = imagePoints`; `panel.contentMinSize = PinGeometry.minimumSize(aspect: imagePoints, initial: frame.size)`; `panel.makeFirstResponder(view)`; `panel.orderFrontRegardless()` (not `makeKeyAndOrderFront`: the user's app keeps the keyboard until the pin is clicked); the view's closures:
  - `.nudge`: `panel.setFrame(PinGeometry.nudged(panel.frame, dx:, dy:, shift:), display: true)`; `.zoomIn`/`.zoomOut`: `PinGeometry.zoomed(panel.frame, factor: PinGeometry.zoomStep)` and `1 / PinGeometry.zoomStep`; `.actualSize`: `PinGeometry.actualSize(panel.frame, imagePoints:)`; `.copyImage`: `actions.copyImage(recordID)`; `.close`: close this pin.
  - Opacity steps: `pin.opacity = PinOpacity.changed(pin.opacity, steps:)`; `panel.alphaValue = pin.opacity`. A menu preset sets it the same way.
  - Lock: `pin.isLocked = true`, `panel.ignoresMouseEvents = true`, `view.showsBorder = false`.
  - After the content is set, `panel.invalidateShadow()` so a window capture's transparent corners cast the right shadow.
- `bringToFront(recordID:) -> Bool`: orders the first pin of that record front (`orderFrontRegardless()`) and returns true; false when there is none.
- `close(recordID:)` (all of its pins), `closeAll()`, `unlockAll()` (`ignoresMouseEvents = false`, border back, `isLocked = false`), `hasPins`, `hasLockedPins`. Closing is `orderOut(nil)` and dropping the reference.

- [ ] **Step 5: The card, the model and the menus**

`TidyShot/Overlay/QuickAccessModel.swift`: after `onAnnotate` add `@ObservationIgnored var onPin: () -> Void = {}`.

`TidyShot/Overlay/QuickAccessController.swift`: in `Actions` add, after `annotate`, `/// Pins the capture on screen; see AppCoordinator.pin(recordID:).` and `var pin: (UUID) -> Void`; in `makeCard`, after `model.onAnnotate = …`, add `model.onPin = { actions.pin(id) }`.

`TidyShot/Overlay/QuickAccessView.swift`:
- The right column (the `VStack(spacing: 8)` with Annotate and Delete) gets a button between them: `Image(systemName: "pin")` in `.foregroundStyle(.secondary)`, `.buttonStyle(.plain)`, `.help("Pin to screen")`, `.accessibilityLabel("Pin to screen")`, calling `model.onPin()`.
- `menuItems`: after `Button("Annotate")` add `Button("Pin to Screen") { model.onPin() }`, so the menu reads Copy URL, Copy Image, Save As…, Annotate, Pin to Screen, Reveal in Finder (when it applies), a divider, Close, Delete….

`TidyShot/App/StatusMenuController.swift`: in `rebuild()`, directly after the separator that follows `Reveal Last Capture` (line 90) and before `Settings…`, add
```swift
        if coordinator.hasLockedPins {
            menu.addItem(item("Unlock Pinned Screenshots", #selector(unlockPins)))
        }
        if coordinator.hasPins {
            menu.addItem(item("Close Pinned Screenshots", #selector(closePins)))
        }
```
and two actions beside the others:
```swift
    @objc private func unlockPins() { coordinator.unlockPins() }
    @objc private func closePins() { coordinator.closePins() }
```
Both items are plain (not `captureItem`): a pin does not need the capture lock, and a locked pin cannot be clicked, so this is the only way back to it.

- [ ] **Step 6: Wire the coordinator**

All in `TidyShot/App/AppCoordinator.swift`.

1. Properties, next to `latestCapture` (line 59):
   ```swift
    /// The area the newest capture was taken from (CoreGraphics global points), so its pin opens
    /// over the spot. Kept with `latestCapture`: cleared by `save(_:)`, by `forgetLatestCapture`.
    @ObservationIgnored private var latestCaptureArea: (id: UUID, rect: CGRect)?
    /// Pin to screen's windows. Records whose image is loading for a pin are in `pinningIDs`.
    @ObservationIgnored private lazy var pins = PinController()
    @ObservationIgnored private var pinningIDs: Set<UUID> = []
   ```
2. `save(_:)`: next to `latestCapture = nil` (line 293) add `latestCaptureArea = nil`. After the `guard let record = await persist(...)` (lines 329-331) and before the `copiedChangeCount` block add
   ```swift
        latestCaptureArea = result.target.areaRect.map { (id: record.id, rect: $0) }
   ```
   Set here and not in `showOverlay`, which returns early when the overlay is off.
3. `forgetLatestCapture(_:)` (line 1370): inside the `if latestCapture?.id == id` body also set `latestCaptureArea = nil`.
4. `removeRecord(id:)` (line 965): after `overlay.close(recordID: id, reason: .deleted)` add `pins.close(recordID: id)`.
5. Share the image load with the editor. Replace `loadAndPresentEditor(for:)` (lines 1351-1368) with
   ```swift
    private func loadAndPresentEditor(for record: CaptureRecord) async {
        defer { openingEditorIDs.remove(record.id) }
        guard let image = await loadImage(for: record) else { return }
        guard editors[record.id] == nil, let current = history.record(id: record.id) else { return }
        presentEditor(record: current, image: image)
    }

    /// The capture's pixels: its PNG through `imageData(of:)` (the local file, the drag copy or a
    /// signed GET, posting `downloadTitle` while that downloads), decoded off the main actor with
    /// the scale recovered from the PNG. On failure posts `failureTitle` and returns nil. The
    /// editor and Pin to screen use it.
    func loadImage(for record: CaptureRecord, downloadTitle: String = "Opening the capture…",
                   failureTitle: String = "Could not open the capture") async -> ScaledImage? {
        do {
            let png = try await imageData(of: record, downloadTitle: downloadTitle)
            let decoded = await Task.detached(priority: .userInitiated) { () -> ScaledImage? in
                ImageEncoder.decode(png).map { ScaledImage(image: $0.image, scale: $0.scale) }
            }.value
            guard let decoded else { throw CopyImageError.notAnImage }
            return decoded
        } catch {
            notifier.notifyError(error.localizedDescription, title: failureTitle)
            return nil
        }
    }
   ```
   The editor behaves as before: same download title, same failure title, the same two guards after the load.
6. After `loadImage`, the pin:
   ```swift
    var hasPins: Bool { pins.hasPins }
    var hasLockedPins: Bool { pins.hasLockedPins }
    func unlockPins() { pins.unlockAll() }
    func closePins() { pins.closeAll() }

    /// Pin to screen (spec 2.9): a floating copy of the capture. The newest capture's pixels are
    /// retained; any other is loaded with `loadImage(for:)`. An image over 8,192 px on a side is
    /// shown from `ThumbnailMaker.scaled` at the screen's pixel size; the pin keeps the capture's
    /// point size for Actual Size. A pin of the newest area capture opens over the spot it came
    /// from, any other centred on the pointer's screen. A second Pin on a pinned capture brings
    /// its pin forward. A capture deleted during the load is not pinned.
    func pin(recordID: UUID) async {
        guard let record = history.record(id: recordID), !deletingIDs.contains(recordID) else { return }
        guard !pins.bringToFront(recordID: recordID), pinningIDs.insert(recordID).inserted else { return }
        defer { pinningIDs.remove(recordID) }
        let image: ScaledImage
        if let retained = latestCapture, retained.id == recordID {
            image = retained.image
        } else {
            guard let loaded = await loadImage(for: record, downloadTitle: "Pinning the capture…",
                                               failureTitle: "Could not pin the capture") else { return }
            image = loaded
        }
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        var preferred: CGRect?
        if let area = latestCaptureArea, area.id == recordID {
            preferred = Geometry.appKitRect(fromCG: area.rect, primaryHeight: primaryHeight)
        }
        guard let screen = pinScreen(preferred: preferred) else { return }
        var shown = image.image
        let screenSide = Int((max(screen.frame.width, screen.frame.height) * screen.backingScaleFactor).rounded())
        if let side = PinGeometry.downsampleMaxSide(pixelWidth: shown.width, pixelHeight: shown.height, screenPixelSide: screenSide) {
            let source = image
            guard let scaled = await Task.detached(priority: .userInitiated, operation: {
                ThumbnailMaker.scaled(source.image, maxSide: side)
            }).value else {
                notifier.notifyError("The capture is too large to pin.", title: "Could not pin the capture")
                return
            }
            shown = scaled
        }
        // Deleted, or its delete started, while the image loaded.
        guard history.record(id: recordID) != nil, !deletingIDs.contains(recordID) else { return }
        let imagePoints = CGSize(width: CGFloat(image.image.width) / image.scale,
                                 height: CGFloat(image.image.height) / image.scale)
        let frame = PinGeometry.initialFrame(imagePoints: imagePoints, preferred: preferred, visibleFrame: screen.visibleFrame)
        pins.open(recordID: recordID, image: shown, imagePoints: imagePoints, frame: frame, actions: pinActions())
    }

    /// The screen holding `preferred`'s centre, otherwise the pointer's, otherwise the first.
    private func pinScreen(preferred: CGRect?) -> NSScreen? {
        let screens = NSScreen.screens
        if let preferred, let screen = screens.first(where: { $0.frame.contains(CGPoint(x: preferred.midX, y: preferred.midY)) }) {
            return screen
        }
        return screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? screens.first
    }

    /// The pin context menu's actions: all three work on the record, after the menu has closed.
    private func pinActions() -> PinController.Actions {
        PinController.Actions(
            copyImage: { [weak self] id in self?.afterMenuTracking { Task { await self?.copyImage(recordID: id) } } },
            saveAs: { [weak self] id in self?.saveAs(recordID: id) },
            annotate: { [weak self] id in self?.openEditorAfterMenuTracking(recordID: id) })
    }
   ```
7. `overlayActions()` (line 484): after `annotate:` add
   ```swift
            pin: { [weak self] id in self?.afterMenuTracking { Task { await self?.pin(recordID: id) } } },
   ```

- [ ] **Step 7: Run the full suite**

Run:
```bash
xcodegen generate && xcodebuild test -project TidyShot.xcodeproj -scheme TidyShot -destination 'platform=macOS' -derivedDataPath .build 2>&1 | grep -E "Test run with|error:|TEST"
```
Expected: no `error:` lines, `** TEST SUCCEEDED **`, and `Test run with 747 tests in 90 suites passed`. This task adds 17 tests in 1 new suite: 16 in `PinGeometryTests`, 1 in `ThumbnailMakerTests`. No test is removed or renamed; `loadAndPresentEditor` changes only by sharing `loadImage(for:)`, and the existing editor tests still pass.

- [ ] **Step 8: Hand checks (Tim)**

For Tim; the implementer builds the Release configuration, lists these in its report and goes on to Step 9. Task 6's checklist repeats them.
```bash
xcodebuild -project TidyShot.xcodeproj -scheme TidyShot -configuration Release -derivedDataPath .build-rel build -quiet
```
Tim opens `.build-rel/Build/Products/Release/TidyShot.app`.
- Capture an area of about 500 by 300 pt. On the card, click the pin button (tooltip `Pin to screen`, between the pencil and the trash can): a pin appears exactly over the captured region, the card stays, and the keyboard stays with the app you were typing in. Right-click the card: `Pin to Screen` follows Annotate.
- Drag the pin by its image: it moves. Drag an edge or corner: it resizes with the aspect ratio kept, and it will not go below 40 pt on its short side. (If edges do not resize, stop: a borderless panel with `.resizable` is what 2.9 specifies and the fallback is not in this plan.)
- Click the pin once so it is key, then: arrows move it 1 pt, Shift-arrows 10 pt; Command-plus and Command-minus grow and shrink it by 10 % about its centre (Command-plus on a US keyboard is Command-Shift-=; the bare `=` also works); Command-0 returns to actual size (a Retina area capture pinned at 80 % goes back to its point size); Command-C puts the image on the clipboard (paste into Preview); Escape closes it; pin another capture and close that one with Command-W.
- Hold Option and scroll over the pin: the opacity falls in steps and rises the other way, never below 10 % or above 100 %. If it moves the wrong way, flip the sign in `PinView.scrollWheel`.
- Right-click the pin: `Copy Image`, `Save As…` (the save panel opens with the editor's suggestion), `Annotate` (the editor opens; the pin stays), `Opacity` with a check on `100%`, then on the preset chosen, `Actual Size`, `Lock`, `Close`.
- Choose `Lock`: the border goes and clicks go through to the app below (click a button under the pin). The menu bar menu now shows `Unlock Pinned Screenshots` and `Close Pinned Screenshots` before `Settings…`; Unlock makes the pin clickable again, Close removes every pin. With no pins neither item shows.
- Pin a fullscreen capture: it opens fitted to 80 % of the screen, centred. Pin a capture from an older card in the stack: it opens centred on the pointer's screen. Pin the same capture twice: the second click brings the first pin forward.
- Pin a window capture with transparent corners: the corners are transparent and the shadow follows them.
- Delete the capture from its card (confirm): its pin closes. Switch Spaces and enter a full-screen app: the pin stays above. Take a fullscreen capture with a pin showing: the pin is in the image.
- Scrolling capture of a long page (65,536 px if you can): pin it. It opens as a fitted strip, without a wait of more than a second or two, and Actual Size shows its point size.
- In upload-only mode, pin a capture whose pending file is gone (an older card, after the URL is on the clipboard): the pin loads from the bucket, with `Pinning the capture…` posted while it downloads.
- Pin, then quit TidyShot from the menu: the pins close and are not back at launch.

- [ ] **Step 9: Commit**

```bash
git add TidyShot/Pin/PinGeometry.swift TidyShot/Pin/PinController.swift TidyShot/Pin/PinPanel.swift TidyShot/Pin/PinView.swift TidyShot/Output/ThumbnailMaker.swift TidyShot/Capture/CaptureTarget.swift TidyShot/Overlay/QuickAccessController.swift TidyShot/Overlay/QuickAccessModel.swift TidyShot/Overlay/QuickAccessView.swift TidyShot/App/AppCoordinator.swift TidyShot/App/StatusMenuController.swift TidyShotTests/PinGeometryTests.swift TidyShotTests/ThumbnailMakerTests.swift
git commit -m "feat: Pin to screen with lock, opacity and keyboard control"
```
Check `git status` is clean afterwards (`TidyShot.xcodeproj` is ignored).

### Task 5: URL scheme

**Files:**
- Create: `TidyShot/URLScheme/URLCommand.swift` (pure: `URLCommand`, `URLCommandError`)
- Create: `TidyShot/URLScheme/URLCommandGeometry.swift` (pure: `ScreenRect`, `URLCommandGeometry`)
- Create: `TidyShot/URLScheme/URLCommandGate.swift` (pure)
- Create: `TidyShot/URLScheme/URLCommandHandler.swift` (`URLCommandTarget`, `URLCommandNotice`, `URLCommandHandler`)
- Create: `TidyShot/Capture/CaptureIntent.swift` (pure)
- Modify: `TidyShot/Settings/AppSettings.swift` (line 4, `enum AfterCaptureAction`; `Keys`, after line 56 `freezeScreen`; the properties, after line 98; `register`, after line 139; `init`, after line 170. Tasks 2 and 3 add `allInOneAspectLock` and `selfTimerSeconds` next to these, so find each place by name)
- Modify: `TidyShot/Settings/GeneralSettingsView.swift` (the `Form`, lines 8-42)
- Modify: `TidyShot/Output/Notifier.swift` (`notifyError`, lines 36-41; `notify`, lines 44-49)
- Modify: `TidyShot/App/AppDelegate.swift` (a new `applicationWillFinishLaunching` and the Apple-event handler, after line 10)
- Modify: `TidyShot/App/AppCoordinator.swift` (the `scrollCapture` property, line 33; `start()`, lines 106-115; `showPermissionWindow()`, lines 117-119; `captureFullscreen()`, lines 148-155; `captureArea()`, 157-159; `captureWindow()`, 161-163; `captureScrolling()`, 167-196 as Task 2 left it; `capturePreviousArea()`, 202-218; `runSelection(mode:)`, 221-249; `save(_:)`, 292-335 as Task 4 left it; the helpers before `withCaptureLock`, line 1865; the end of the class, line 1880; Task 2's `captureAllInOne(preselect:)` and `runScrolling(rect:display:)`, Task 3's `captureSelfTimer()`, `runSelfTimer(_:)` and `captureAfterCountdown(_:)`)
- Modify: `project.yml` (the TidyShot target's `info.properties`, lines 38-47)
- Modify: `TidyShot/Info.plist` (regenerated by `xcodegen generate`; committed)
- Test: `TidyShotTests/URLCommandTests.swift`, `TidyShotTests/URLCommandGeometryTests.swift`, `TidyShotTests/URLCommandGateTests.swift`, `TidyShotTests/CaptureIntentTests.swift`, `TidyShotTests/URLCommandHandlerTests.swift` (5 new suites), `TidyShotTests/AppSettingsTests.swift`

Line numbers are from `main` at 4c67c04. Tasks 1 to 4 shift them in `AppCoordinator.swift`, `AppSettings.swift`, `StatusMenuController.swift` and `SelectionController.swift`, so find each place by the quoted code.

**Interfaces:**
- Consumes:
  - `main`: `AppCoordinator.isCapturing`, `loadContent()`, `withCaptureLock(_:)`, `capture(_:excludingWindows:duringSelection:)` (no `duringSelection` means the cursor follows Show cursor, which 2.9's cursor rule wants for a URL-rect capture), `cardWindows()`, `restoreClosedOverlay()`, `openEditor(recordID:)`, `save(_:)`, `persist(...)`, `scrollCapture.run(rect:display:)`, `selector.select(mode:content:freeze:)`, `selector.dismiss()` (safe to call with no overlay up), `notifier`; `ScrollCaptureLimits.minimumAreaHeightPoints`; `StoredRect`; `Geometry.cgRect(fromAppKit:primaryHeight:)`; `NSScreen.displayID`; `Pasteboard.copy(pngData:tiffData:)`, `Pasteboard.companionTIFF(of:scale:)`, `Pasteboard.tiffData(of:scale:)`, `Pasteboard.copy(tiffData:)`; `ImageEncoder.pngData(from:scale:)`; `SoundPlayer.playShutter()`; `CaptureResult.scaled`.
  - Task 2: `AppCoordinator.captureAllInOne(preselect: CGRect? = nil) async`, which passes `preselect ?? settings.lastAreaRect?.cgRect` to `SelectionController.selectAllInOne(content: SCShareableContent, freeze: CaptureOptions? = nil, preselect: CGRect? = nil) async -> AllInOneChoice?` (the controller places it with `SelectionAdjust.restored(_:displayFrames:)`); its `switch` assigns `result` for `.area` (`areaResult(rect:display:)`), `.window` and `.fullscreen`, ends in one `save(result)`, and returns early from `.scrolling` (`runScrolling(rect:display:)`) and `.timer`; the private `runScrolling(rect:display:)`, which refuses a rect under 100 pt, stores `lastAreaRect`, dismisses the overlay, runs the session and saves; `captureScrolling()`, which after its selection calls `runScrolling`.
  - Task 3: `AppCoordinator.captureSelfTimer() async`, `runSelfTimer(_ target: CaptureTarget) async` (also All-in-One's `.timer` case) and `captureAfterCountdown(_ target: CaptureTarget) async`, which holds the countdown's one `save(result)`.
  - Task 4: `AppCoordinator.pin(recordID: UUID) async` (it loads the image itself); `latestCaptureArea`, cleared next to `latestCapture = nil` at the top of `save(_:)` and set from `result.target.areaRect` right after `persist` returns.
- Produces:
  ```swift
  // URLScheme/URLCommand.swift
  nonisolated struct URLCommand: Equatable, Sendable {
      enum Kind: String, CaseIterable, Sendable {
          case captureArea = "capture-area", captureWindow = "capture-window"
          case captureFullscreen = "capture-fullscreen", capturePreviousArea = "capture-previous-area"
          case allInOne = "all-in-one", selfTimer = "self-timer", captureScrolling = "capture-scrolling"
          case restoreRecentlyClosed = "restore-recently-closed"
          static let aliases: [String: Kind]           // "scrolling-capture" -> .captureScrolling
          var isCapture: Bool { get }                  // all but restoreRecentlyClosed
          var takesArea: Bool { get }                  // captureArea, allInOne, captureScrolling
      }
      enum Action: String, CaseIterable, Sendable { case upload, save, copy, annotate, pin }
      struct Area: Equatable, Sendable { var x: Double; var y: Double; var width: Double; var height: Double }
      var kind: Kind
      var action: Action?
      var area: Area?
      var display: Int?
      var capturesWithoutSelection: Bool { get }
      static let coordinateLimit: Double               // 100_000
      static let numberLengthLimit: Int                // 16
      static let displayLimit: Int                     // 40
      static func parse(_ url: URL) -> Result<URLCommand, URLCommandError>
      static func number(_ text: String) -> Double?
      static func displayNumber(_ text: String) -> Int?
      static func displayed(_ raw: String) -> String
  }
  nonisolated enum URLCommandError: Error, Equatable, Sendable {
      case unknownCommand(String), unknownAction(String), badArea, noDisplay(String), repeatedParameter(String)
      var message: String { get }
  }

  // URLScheme/URLCommandGeometry.swift
  nonisolated struct ScreenRect: Equatable, Sendable { var rect: CGRect; var displayID: CGDirectDisplayID }
  nonisolated enum URLCommandGeometry {
      struct Display: Equatable, Sendable { let id: CGDirectDisplayID; let frame: CGRect }
      enum Resolution: Equatable, Sendable { case area(ScreenRect), noDisplay(Int), outside(display: Int) }
      static func resolve(_ area: URLCommand.Area, display: Int?, displays: [Display], pointerIndex: Int?) -> Resolution
      static func outsideMessage(display: Int) -> String
  }

  // URLScheme/URLCommandGate.swift
  nonisolated enum URLCommandGate {
      enum Decision: Equatable, Sendable { case run, refuse(String) }
      static let disabledMessage: String
      static func decision(for command: URLCommand, enabled: Bool, allowSilent: Bool, sender: String? = nil) -> Decision
  }

  // URLScheme/URLCommandHandler.swift (MainActor)
  protocol URLCommandTarget: AnyObject {
      var isCapturing: Bool { get }
      func captureArea(intent: CaptureIntent) async
      func captureArea(at area: ScreenRect, intent: CaptureIntent) async
      func captureWindow(intent: CaptureIntent) async
      func captureFullscreen(intent: CaptureIntent) async
      func capturePreviousArea(intent: CaptureIntent) async
      func captureAllInOne(intent: CaptureIntent, preselect: ScreenRect?) async
      func captureSelfTimer(intent: CaptureIntent) async
      func captureScrolling(intent: CaptureIntent, preselect: ScreenRect?) async
      func restoreClosedOverlay() async
  }
  nonisolated struct URLCommandNotice: Equatable, Sendable { var title: String; var subtitle: String?; var body: String }
  final class URLCommandHandler {
      struct Screens { var displays: [URLCommandGeometry.Display]; var pointerIndex: Int? }
      static let noticeTitle: String                   // "TidyShot URL command"
      static let queueLimit: Int                       // 8
      init(settings: AppSettings, target: any URLCommandTarget, screens: @escaping () -> Screens,
           post: @escaping (URLCommandNotice) -> Void)
      func handle(_ url: URL, sender: String?) async
      func ready() async
      static func senderName(_ sender: String?) -> String?
  }

  // Capture/CaptureIntent.swift
  nonisolated struct CaptureIntent: Equatable, Sendable {
      enum Then: Equatable, Sendable { case none, annotate, pin }
      var action: AfterCaptureAction
      var copyOnly: Bool
      var then: Then
      var sender: String?
      init(action: AfterCaptureAction, copyOnly: Bool = false, then: Then = .none, sender: String? = nil)
      init(urlAction: URLCommand.Action?, setting: AfterCaptureAction, sender: String? = nil)
      @MainActor static var standard: CaptureIntent { get }
  }

  // AppSettings
  nonisolated enum AfterCaptureAction: String, CaseIterable, Identifiable, Sendable   // was MainActor
  var urlCommandsEnabled: Bool                       // key "urlCommandsEnabled", default true
  var urlCommandsAllowSilent: Bool                   // key "urlCommandsAllowSilent", default false

  // Notifier
  func notifyError(_ message: String, title: String = "Capture failed", subtitle: String? = nil)
  func notify(title: String, body: String, subtitle: String? = nil)

  // AppCoordinator (all MainActor)
  func captureFullscreen(intent: CaptureIntent = .standard) async
  func captureArea(intent: CaptureIntent = .standard) async
  func captureArea(at area: ScreenRect, intent: CaptureIntent) async
  func captureWindow(intent: CaptureIntent = .standard) async
  func captureScrolling(intent: CaptureIntent = .standard, preselect: ScreenRect? = nil) async
  func capturePreviousArea(intent: CaptureIntent = .standard) async
  func captureAllInOne(intent: CaptureIntent = .standard, preselect: ScreenRect? = nil) async   // Task 2's, extended (preselect was CGRect?)
  func captureSelfTimer(intent: CaptureIntent = .standard) async                              // Task 3's, extended
  private func runScrolling(rect: CGRect, display: SCDisplay, intent: CaptureIntent) async      // Task 2's, extended
  private func runSelfTimer(_ target: CaptureTarget, intent: CaptureIntent) async             // Task 3's, extended
  private func captureAfterCountdown(_ target: CaptureTarget, intent: CaptureIntent) async    // Task 3's, extended
  @discardableResult func save(_ result: CaptureResult, intent: CaptureIntent = .standard) async -> CaptureRecord?
  func handleURL(_ url: URL, sender: String?)
  extension AppCoordinator: URLCommandTarget {}
  ```
  Task 6 documents these; nothing later in the plan calls them.

Behaviour (spec 2.9, URL scheme and URL security), pinned down:
- **Security model.** Two General settings: `Allow URL commands (tidyshot://)` (`urlCommandsEnabled`, on by default) and `Allow URL commands that capture without a selection` (`urlCommandsAllowSilent`, off by default). With the first off, every URL is refused with `URL commands are off. Turn them on in Settings > General.`, before anything else is looked at, so a disabled scheme reveals nothing about parsing. The silent commands are exactly three: `capture-fullscreen`, `capture-previous-area`, and `capture-area` with x, y, width and height. With the second toggle off they are refused with `<command> from <sender> captures without a selection. Allow it in Settings > General > URL commands.` (without ` from <sender>` when the sender is unknown). Every other command needs the user's drag, click or Start before anything is captured: `capture-area` without a rect, `capture-window`, `all-in-one` with or without a rect (a rect only preselects), `self-timer` (it selects first), `capture-scrolling` with or without a rect (the session waits for Start, and a URL never presses Start). `restore-recently-closed` captures nothing and runs whenever the first toggle is on. The `action` never changes the decision (decision 4: no separate upload switch). There is no prompt: a refused command is refused, with a notification.
- **The sender.** `AppDelegate`'s handler reads `keySenderPIDAttr` and `NSRunningApplication(processIdentifier:)?.localizedName`. `URLCommandHandler.senderName` cleans it (`URLCommand.displayed`) and treats an empty result as unknown. Every notification the URL scheme posts (refusals, errors, and `Image copied` for `action=copy`) carries `From <sender>` as its subtitle when the sender is known; the silent refusal names it in its body too, as 2.9 says. Every URL is logged with its sender. The name is what the sending app calls itself, a hint for the user, not an identity: no decision depends on it.
- **Parsing** (`URLCommand.parse`, pure). The scheme must be `tidyshot` (any case). The command is the host, else the first path component, both percent-decoded by `URLComponents`, matched ignoring case; `scrolling-capture` is an alias of `capture-scrolling`. Query names are percent-decoded and matched ignoring case. A parameter the command does not take is ignored (also when repeated, also with a bad value); a parameter it takes that appears twice is an error (`“<name>” is given more than once.`), found while the query is read, before any value is checked. `action` (every capture command): `upload`, `save`, `copy`, `annotate`, `pin`, any case. `x`, `y`, `width`, `height`, `display` (`capture-area`, `all-in-one`, `capture-scrolling`): the four come together or not at all, each a plain decimal (an optional `-`, digits, at most one `.` followed by digits, at most 16 characters, magnitude at most 100,000 points; `Double(_:)` alone would take `nan`, `inf`, `1e3`, `0x10` and `+5`), width and height above 0; `display` is 1 to 99 in digits only and is used only together with the rect. Every value quoted in a message passes through `URLCommand.displayed`: control and format characters (a NUL, a newline, a right-to-left override) removed, cut at 40 characters with `…`. Logs pass URL text as an argument (`NSLog("%@", text)`), never as the format.
- **Rect coordinates** (decision 13). Points from the bottom-left corner of the display, as CleanShot's API says; display 1 is `NSScreen.screens[0]` (the main display), the others in `NSScreen.screens` order; no `display` means the display under the pointer, else display 1. `URLCommandGeometry.resolve` turns that into CoreGraphics global points (`x = frame.minX + x`, `y = frame.maxY - y - height`, with `frame` the display's CoreGraphics frame), clips it to the display, and refuses a result under 1 pt on a side with `The area leaves less than a point on display <n>.`; a display that does not exist is `There is no display <n>.`
- **Queue and busy.** The handler holds URLs that arrive before `AppCoordinator.start()` has run (at most 8; a cold launch brings one) and runs them in order once `start()` calls `ready()`. A capture command that arrives while `isCapturing` is true is dropped with a log line and no notification, never queued; that includes `capture-scrolling` during a scrolling session, which therefore never advances it. `restore-recently-closed` runs during a capture, as its menu item does.
- **Routing.** Every command ends in the coordinator's existing capture functions, and every capture in `save(_:intent:)`: `capture-area` → `captureArea(intent:)` (selection) or `captureArea(at:intent:)` (rect, live, cards excluded, cursor from the setting, stored as `lastAreaRect`); `capture-window` → `captureWindow(intent:)`; `capture-fullscreen` → `captureFullscreen(intent:)`; `capture-previous-area` → `capturePreviousArea(intent:)`; `all-in-one` → `captureAllInOne(intent:preselect:)`; `self-timer` → `captureSelfTimer(intent:)`; `capture-scrolling` → `captureScrolling(intent:preselect:)` (a rect skips the selection and opens the session panel on it, refused under 100 pt with the Phase 5 message); `restore-recently-closed` → `restoreClosedOverlay()`. Hotkeys and the menu call the same functions with `CaptureIntent.standard`.
- **Actions** (`CaptureIntent`). None: the General action. `upload`: `uploadOnly` when that is the setting, otherwise `upload`. `save`: `save` (Save and copy image, whose copy follows the General toggle as always). `copy`: the image on the clipboard only, no file, record, thumbnail, card or upload, the shutter sound by Play sound, `Image copied` (body `<w> × <h> px`) when notifications are on. `annotate` and `pin`: the General action, then `openEditor(recordID:)` or `pin(recordID:)` on the new record.

Settled beyond 2.9 (the plan header's points 8 to 12 carry these, and Task 6 writes them into 2.9): the sender as the subtitle of every URL notification, and `CaptureIntent.sender`; `URLCommandGate.decision` takes `sender:`; the repeated-parameter error and its text; the less-than-a-point error and its text; the number grammar and limits (16 characters, 100,000 pt, display 1 to 99); names and actions matched ignoring case after percent-decoding; `display` without a rect checked for form and otherwise ignored; `capture-scrolling` with a rect opens the session directly; `action=copy` plays the shutter sound and its notification body is the pixel size; values in messages cleaned and cut at 40 characters; a queue of at most 8 URLs before start; with URL commands off, unparseable URLs get the same refusal; `CaptureIntent` in `Capture/CaptureIntent.swift`, with `.standard` read when the capture starts; `URLCommandHandler` with the `URLCommandTarget` protocol and its own test suite; `AfterCaptureAction` made `nonisolated` and `Sendable`.

- [ ] **Step 1: Write the failing tests**

`TidyShotTests/URLCommandTests.swift`:
```swift
import Foundation
import Testing
@testable import TidyShot

/// Parsing and validating `tidyshot://` URLs (spec 2.9, URL scheme). Everything here is input any
/// process on the Mac controls.
struct URLCommandTests {
    func parse(_ string: String) throws -> Result<URLCommand, URLCommandError> {
        URLCommand.parse(try #require(URL(string: string)))
    }

    /// `tidyshot://<command>` with these query items, percent-encoded by Foundation.
    func url(_ command: String, _ items: [(String, String)]) throws -> URL {
        var components = URLComponents()
        components.scheme = "tidyshot"
        components.host = command
        components.queryItems = items.map { URLQueryItem(name: $0.0, value: $0.1) }
        return try #require(components.url)
    }

    @Test func everyCommandParsesFromTheHost() throws {
        #expect(URLCommand.Kind.allCases.count == 8)
        for kind in URLCommand.Kind.allCases {
            #expect(try parse("tidyshot://\(kind.rawValue)") == .success(URLCommand(kind: kind)))
        }
    }

    @Test func everyCommandParsesFromThePath() throws {
        for kind in URLCommand.Kind.allCases {
            #expect(try parse("tidyshot:\(kind.rawValue)") == .success(URLCommand(kind: kind)))
            #expect(try parse("tidyshot:///\(kind.rawValue)") == .success(URLCommand(kind: kind)))
        }
        #expect(try parse("tidyshot:capture-area?action=copy") == .success(URLCommand(kind: .captureArea, action: .copy)))
        // The host names the command; a path after it is ignored.
        #expect(try parse("tidyshot://capture-area/") == .success(URLCommand(kind: .captureArea)))
        #expect(try parse("tidyshot://capture-area/capture-fullscreen") == .success(URLCommand(kind: .captureArea)))
    }

    @Test func scrollingCaptureIsCleanShotsNameForCaptureScrolling() throws {
        #expect(try parse("tidyshot://scrolling-capture?x=0&y=0&width=400&height=600")
                == .success(URLCommand(kind: .captureScrolling, area: .init(x: 0, y: 0, width: 400, height: 600))))
        #expect(URLCommand.Kind.aliases == ["scrolling-capture": .captureScrolling])
    }

    @Test func theSchemeTheCommandAndTheNamesIgnoreCase() throws {
        #expect(try parse("tidyshot://CAPTURE-Area") == .success(URLCommand(kind: .captureArea)))
        #expect(try parse("TIDYSHOT://capture-area") == .success(URLCommand(kind: .captureArea)))
        #expect(try parse("TidyShot:Capture-Window?Action=COPY") == .success(URLCommand(kind: .captureWindow, action: .copy)))
        #expect(try parse("tidyshot://capture-area?X=1&Y=2&WIDTH=3&Height=4")
                == .success(URLCommand(kind: .captureArea, area: .init(x: 1, y: 2, width: 3, height: 4))))
    }

    @Test func percentEncodingIsDecodedBeforeMatching() throws {
        #expect(try parse("tidyshot://capture%2Dfullscreen?action=%75pload")
                == .success(URLCommand(kind: .captureFullscreen, action: .upload)))
        #expect(try parse("tidyshot://capture-fullscreen?%61ction=copy")
                == .success(URLCommand(kind: .captureFullscreen, action: .copy)))
        #expect(try parse("tidyshot://capture-area?x=%31&y=%30&width=%31%30&height=%31%30")
                == .success(URLCommand(kind: .captureArea, area: .init(x: 1, y: 0, width: 10, height: 10))))
        // An encoded & and = stay inside the one value: no second parameter appears.
        #expect(try parse("tidyshot://capture-fullscreen?action=upload%26action%3Dcopy")
                == .failure(.unknownAction("upload&action=copy")))
    }

    @Test func everyActionParsesOnEveryCaptureCommand() throws {
        #expect(URLCommand.Action.allCases.map(\.rawValue) == ["upload", "save", "copy", "annotate", "pin"])
        for kind in URLCommand.Kind.allCases where kind.isCapture {
            for action in URLCommand.Action.allCases {
                #expect(try parse("tidyshot://\(kind.rawValue)?action=\(action.rawValue)")
                        == .success(URLCommand(kind: kind, action: action)))
            }
        }
        #expect(try parse("tidyshot://capture-area?action=UPLOAD") == .success(URLCommand(kind: .captureArea, action: .upload)))
    }

    @Test func noActionLeavesItToTheAfterCaptureSetting() throws {
        #expect(try parse("tidyshot://capture-window").get().action == nil)
        #expect(try parse("tidyshot://capture-window?foo=upload").get().action == nil)
    }

    @Test func anUnknownCommandIsAnError() throws {
        #expect(try parse("tidyshot://capture-everything") == .failure(.unknownCommand("capture-everything")))
        #expect(try parse("tidyshot://Capture-Everything") == .failure(.unknownCommand("Capture-Everything")))
        #expect(try parse("tidyshot://") == .failure(.unknownCommand("")))
        #expect(try parse("tidyshot:") == .failure(.unknownCommand("")))
        // CleanShot commands that take a file path, open other windows or record are not offered.
        for name in ["pin", "open-annotate", "add-quick-access-overlay", "open-settings", "open-history", "record-screen", "capture-text"] {
            #expect(try parse("tidyshot://\(name)?filepath=/tmp/x.png") == .failure(.unknownCommand(name)))
        }
        #expect(try parse("https://capture-area") == .failure(.unknownCommand("https://capture-area")))
    }

    @Test func anUnknownOrEmptyActionIsAnError() throws {
        #expect(try parse("tidyshot://capture-area?action=print") == .failure(.unknownAction("print")))
        #expect(try parse("tidyshot://capture-area?action=") == .failure(.unknownAction("")))
        #expect(try parse("tidyshot://capture-area?action") == .failure(.unknownAction("")))
        #expect(try parse("tidyshot://capture-area?action=upload%20") == .failure(.unknownAction("upload ")))
    }

    @Test func theFourRectValuesAndTheDisplayParse() throws {
        #expect(try parse("tidyshot://capture-area?x=10&y=20.5&width=640&height=480&display=2")
                == .success(URLCommand(kind: .captureArea, area: .init(x: 10, y: 20.5, width: 640, height: 480), display: 2)))
        // Negative x and y are allowed: the geometry clips the rect to its display.
        #expect(try parse("tidyshot://all-in-one?x=-100&y=-0.5&width=1&height=0.25")
                == .success(URLCommand(kind: .allInOne, area: .init(x: -100, y: -0.5, width: 1, height: 0.25))))
    }

    @Test func theRectValuesComeTogetherOrNotAtAll() throws {
        let all = [("x", "1"), ("y", "2"), ("width", "30"), ("height", "40")]
        for skipped in all.indices {
            var items = all
            items.remove(at: skipped)
            #expect(URLCommand.parse(try url("capture-area", items)) == .failure(.badArea))
        }
        #expect(try parse("tidyshot://capture-scrolling?x=1&y=2") == .failure(.badArea))
    }

    @Test func widthAndHeightMustBeAboveZero() throws {
        for (width, height) in [("0", "10"), ("10", "0"), ("-10", "10"), ("10", "-0.5"), ("-0", "5"), ("0.0", "5")] {
            let items = [("x", "0"), ("y", "0"), ("width", width), ("height", height)]
            #expect(URLCommand.parse(try url("capture-area", items)) == .failure(.badArea), "width \(width), height \(height)")
        }
    }

    /// `Double(_:)` takes `nan`, `inf`, `1e3`, `0x10` and `+5`; a URL number is a plain decimal.
    @Test func onlyPlainDecimalsAreNumbers() throws {
        let bad = ["abc", "nan", "NaN", "inf", "-inf", "infinity", "1e3", "0x10", "+5", " 5", "5 ", "5.", ".5",
                   "1.2.3", "--5", "-", "%", "1_000", "١٢", "", "5,5", "%@%s"]
        for value in bad {
            let items = [("x", "0"), ("y", "0"), ("width", value), ("height", "10")]
            #expect(URLCommand.parse(try url("capture-area", items)) == .failure(.badArea), "width=\(value)")
        }
        #expect(URLCommand.number("12.5") == 12.5)
        #expect(URLCommand.number("-0.25") == -0.25)
        #expect(URLCommand.number("007") == 7)
    }

    /// No arrangement of displays reaches 100,000 points; a larger or longer number is refused
    /// before any arithmetic sees it.
    @Test func hugeAndOverlongNumbersAreRefused() throws {
        for value in ["100001", "-100001", "99999999999999999999", "1000000000000000", "0.00000000000000001"] {
            let items = [("x", value), ("y", "0"), ("width", "10"), ("height", "10")]
            #expect(URLCommand.parse(try url("capture-area", items)) == .failure(.badArea), "x=\(value)")
        }
        #expect(URLCommand.number("100000") == 100_000)
        #expect(URLCommand.number("-100000") == -100_000)
        // 16 characters, the longest accepted.
        #expect(URLCommand.number("0.00000000000001") == 0.00000000000001)
    }

    @Test func aRepeatedParameterIsAnError() throws {
        #expect(try parse("tidyshot://capture-area?action=upload&action=copy") == .failure(.repeatedParameter("action")))
        #expect(try parse("tidyshot://capture-area?action=copy&action=copy") == .failure(.repeatedParameter("action")))
        #expect(try parse("tidyshot://capture-area?action=copy&ACTION=upload") == .failure(.repeatedParameter("action")))
        #expect(try parse("tidyshot://capture-area?x=1&y=1&width=5&height=5&x=2") == .failure(.repeatedParameter("x")))
        #expect(try parse("tidyshot://all-in-one?display=1&display=1") == .failure(.repeatedParameter("display")))
        // Found while the query is read, before any value is checked.
        #expect(try parse("tidyshot://capture-area?action=bogus&action=copy") == .failure(.repeatedParameter("action")))
    }

    @Test func parametersACommandDoesNotTakeAreIgnored() throws {
        #expect(try parse("tidyshot://capture-fullscreen?x=1&x=2&width=-5&display=abc&foo=bar&foo=baz")
                == .success(URLCommand(kind: .captureFullscreen)))
        #expect(try parse("tidyshot://capture-window?x=1&y=1&width=1&height=1&display=2")
                == .success(URLCommand(kind: .captureWindow)))
        #expect(try parse("tidyshot://restore-recently-closed?action=bogus&action=pin")
                == .success(URLCommand(kind: .restoreRecentlyClosed)))
        #expect(try parse("tidyshot://capture-area?=5&&filepath=/etc/passwd") == .success(URLCommand(kind: .captureArea)))
    }

    @Test func theDisplayIsAWholeNumberFromOne() throws {
        #expect(try parse("tidyshot://capture-area?display=12") == .success(URLCommand(kind: .captureArea, display: 12)))
        for value in ["0", "-1", "abc", "1.5", "100", "", "+2", " 1"] {
            #expect(URLCommand.parse(try url("capture-area", [("display", value)])) == .failure(.noDisplay(value)), "display=\(value)")
        }
    }

    @Test func onlyFullscreenPreviousAreaAndARectAreaCaptureWithoutASelection() throws {
        let rect = "x=0&y=0&width=10&height=10"
        let silent = ["capture-fullscreen", "capture-previous-area", "capture-area?\(rect)", "capture-fullscreen?action=copy"]
        let selecting = ["capture-area", "capture-area?action=copy", "capture-window", "all-in-one", "all-in-one?\(rect)",
                         "self-timer", "capture-scrolling", "capture-scrolling?\(rect)", "scrolling-capture?\(rect)",
                         "restore-recently-closed"]
        for string in silent {
            #expect(try parse("tidyshot://\(string)").get().capturesWithoutSelection == true, "\(string)")
        }
        for string in selecting {
            #expect(try parse("tidyshot://\(string)").get().capturesWithoutSelection == false, "\(string)")
        }
    }

    @Test func valuesInMessagesAreCleanedAndShortened() throws {
        #expect(URLCommand.displayed("up\u{0}load") == "upload")
        #expect(URLCommand.displayed("\u{202E}gnp.exe") == "gnp.exe")
        #expect(URLCommand.displayed("a\u{2028}b\nc") == "abc")
        #expect(URLCommand.displayed(String(repeating: "x", count: 60)) == String(repeating: "x", count: 40) + "…")
        #expect(URLCommand.displayed(String(repeating: "x", count: 40)) == String(repeating: "x", count: 40))
        #expect(try parse("tidyshot://capture-area?action=%E2%80%AEdaolpu") == .failure(.unknownAction("\u{202E}daolpu")))
        #expect(URLCommandError.unknownAction("\u{202E}daolpu").message == "Unknown action “daolpu”. Use upload, save, copy, annotate or pin.")
    }

    @Test func errorMessagesAreTheSpecStrings() {
        #expect(URLCommandError.unknownCommand("capture-everything").message == "Unknown command “capture-everything”.")
        #expect(URLCommandError.unknownAction("print").message == "Unknown action “print”. Use upload, save, copy, annotate or pin.")
        #expect(URLCommandError.badArea.message
                == "x, y, width and height must be given together, as numbers, with width and height above 0.")
        #expect(URLCommandError.noDisplay("3").message == "There is no display 3.")
        #expect(URLCommandError.noDisplay("0").message == "There is no display 0.")
        #expect(URLCommandError.repeatedParameter("action").message == "“action” is given more than once.")
    }

    /// `xcodegen generate` writes `CFBundleURLTypes` from `project.yml` into the app's Info.plist.
    /// The tests run inside the app, so `Bundle.main` is TidyShot.app.
    @Test func theAppRegistersTheTidyShotScheme() throws {
        let types = try #require(Bundle.main.object(forInfoDictionaryKey: "CFBundleURLTypes") as? [[String: Any]])
        #expect(types.count == 1)
        #expect(types.first?["CFBundleURLName"] as? String == "io.tky.tidyshot")
        #expect(types.first?["CFBundleURLSchemes"] as? [String] == ["tidyshot"])
    }
}
```

`TidyShotTests/URLCommandGeometryTests.swift`:
```swift
import CoreGraphics
import Testing
@testable import TidyShot

/// CleanShot's rect convention (spec 2.9, decision 13): points from the bottom-left corner of the
/// display, display 1 the main one. The result is CoreGraphics global points, clipped.
struct URLCommandGeometryTests {
    /// CoreGraphics global points in `NSScreen.screens` order. Display 1 is the main display;
    /// display 2 sits above it and to the left (negative x and y); display 3 to its right, lower.
    let displays = [
        URLCommandGeometry.Display(id: 1, frame: CGRect(x: 0, y: 0, width: 1920, height: 1080)),
        URLCommandGeometry.Display(id: 2, frame: CGRect(x: -1440, y: -900, width: 1440, height: 900)),
        URLCommandGeometry.Display(id: 3, frame: CGRect(x: 1920, y: 300, width: 2560, height: 1440)),
    ]

    func area(_ x: Double, _ y: Double, _ width: Double, _ height: Double) -> URLCommand.Area {
        URLCommand.Area(x: x, y: y, width: width, height: height)
    }

    func on(_ rect: CGRect, _ id: CGDirectDisplayID) -> URLCommandGeometry.Resolution {
        .area(ScreenRect(rect: rect, displayID: id))
    }

    @Test func theOriginIsTheBottomLeftOfTheMainDisplay() {
        #expect(URLCommandGeometry.resolve(area(0, 0, 200, 100), display: 1, displays: displays, pointerIndex: nil)
                == on(CGRect(x: 0, y: 980, width: 200, height: 100), 1))
        #expect(URLCommandGeometry.resolve(area(100, 100, 200, 50), display: 1, displays: displays, pointerIndex: nil)
                == on(CGRect(x: 100, y: 930, width: 200, height: 50), 1))
        // The top-right corner of the display.
        #expect(URLCommandGeometry.resolve(area(1720, 980, 200, 100), display: 1, displays: displays, pointerIndex: nil)
                == on(CGRect(x: 1720, y: 0, width: 200, height: 100), 1))
    }

    @Test func aDisplayAboveAndToTheLeftUsesItsOwnBottomLeft() {
        #expect(URLCommandGeometry.resolve(area(0, 0, 100, 100), display: 2, displays: displays, pointerIndex: 0)
                == on(CGRect(x: -1440, y: -100, width: 100, height: 100), 2))
        #expect(URLCommandGeometry.resolve(area(20, 800, 300, 50), display: 2, displays: displays, pointerIndex: 0)
                == on(CGRect(x: -1420, y: -850, width: 300, height: 50), 2))
    }

    @Test func withoutADisplayThePointersIsUsedThenTheMainOne() {
        #expect(URLCommandGeometry.resolve(area(10, 10, 100, 100), display: nil, displays: displays, pointerIndex: 2)
                == on(CGRect(x: 1930, y: 1630, width: 100, height: 100), 3))
        #expect(URLCommandGeometry.resolve(area(10, 10, 100, 100), display: nil, displays: displays, pointerIndex: nil)
                == on(CGRect(x: 10, y: 970, width: 100, height: 100), 1))
        #expect(URLCommandGeometry.resolve(area(10, 10, 100, 100), display: nil, displays: displays, pointerIndex: 7)
                == on(CGRect(x: 10, y: 970, width: 100, height: 100), 1))
        // A given display wins over the pointer.
        #expect(URLCommandGeometry.resolve(area(10, 10, 100, 100), display: 1, displays: displays, pointerIndex: 2)
                == on(CGRect(x: 10, y: 970, width: 100, height: 100), 1))
    }

    @Test func aRectPartlyOffItsDisplayIsClipped() {
        #expect(URLCommandGeometry.resolve(area(1800, -20, 200, 100), display: 1, displays: displays, pointerIndex: nil)
                == on(CGRect(x: 1800, y: 1000, width: 120, height: 80), 1))
        #expect(URLCommandGeometry.resolve(area(-50, 10, 100, 100), display: 1, displays: displays, pointerIndex: nil)
                == on(CGRect(x: 0, y: 970, width: 50, height: 100), 1))
        // Larger than the display: the whole display.
        #expect(URLCommandGeometry.resolve(area(-10, -10, 5000, 5000), display: 3, displays: displays, pointerIndex: nil)
                == on(CGRect(x: 1920, y: 300, width: 2560, height: 1440), 3))
    }

    @Test func aRectThatLeavesLessThanAPointIsOutside() {
        #expect(URLCommandGeometry.resolve(area(2000, 0, 100, 100), display: 1, displays: displays, pointerIndex: nil)
                == .outside(display: 1))
        #expect(URLCommandGeometry.resolve(area(10, 10, 0.5, 100), display: 1, displays: displays, pointerIndex: nil)
                == .outside(display: 1))
        #expect(URLCommandGeometry.resolve(area(1919.5, 10, 100, 100), display: 1, displays: displays, pointerIndex: nil)
                == .outside(display: 1))
        #expect(URLCommandGeometry.resolve(area(5000, 0, 10, 10), display: nil, displays: displays, pointerIndex: 2)
                == .outside(display: 3))
        #expect(URLCommandGeometry.outsideMessage(display: 2) == "The area leaves less than a point on display 2.")
    }

    @Test func aMissingDisplayIsReported() {
        #expect(URLCommandGeometry.resolve(area(0, 0, 10, 10), display: 4, displays: displays, pointerIndex: 0) == .noDisplay(4))
        #expect(URLCommandGeometry.resolve(area(0, 0, 10, 10), display: 0, displays: displays, pointerIndex: 0) == .noDisplay(0))
        #expect(URLCommandGeometry.resolve(area(0, 0, 10, 10), display: 2, displays: [], pointerIndex: nil) == .noDisplay(2))
        #expect(URLCommandGeometry.resolve(area(0, 0, 10, 10), display: nil, displays: [], pointerIndex: nil) == .noDisplay(1))
    }

    @Test func fractionalPointsAreKept() {
        #expect(URLCommandGeometry.resolve(area(10.5, 20.25, 100.5, 50.75), display: 1, displays: displays, pointerIndex: nil)
                == on(CGRect(x: 10.5, y: 1009, width: 100.5, height: 50.75), 1))
    }
}
```

`TidyShotTests/URLCommandGateTests.swift`:
```swift
import Testing
@testable import TidyShot

/// The two General toggles against every command (spec 2.9, URL security).
struct URLCommandGateTests {
    let area = URLCommand.Area(x: 0, y: 0, width: 10, height: 10)
    let off = "URL commands are off. Turn them on in Settings > General."
    let refusal = " captures without a selection. Allow it in Settings > General > URL commands."

    /// Every command, and with a rect where one is taken: 8 kinds, 3 of them with a rect too.
    var everyCommand: [URLCommand] {
        URLCommand.Kind.allCases.flatMap { kind in
            kind.takesArea ? [URLCommand(kind: kind), URLCommand(kind: kind, area: area)] : [URLCommand(kind: kind)]
        }
    }

    @Test func withURLCommandsOffEveryCommandIsRefused() {
        #expect(everyCommand.count == 11)
        #expect(URLCommandGate.disabledMessage == off)
        for command in everyCommand {
            for allowSilent in [false, true] {
                #expect(URLCommandGate.decision(for: command, enabled: false, allowSilent: allowSilent, sender: "Raycast")
                        == .refuse(off))
            }
        }
    }

    @Test func capturesWithoutASelectionNeedTheSecondToggle() {
        let silent = [URLCommand(kind: .captureFullscreen), URLCommand(kind: .capturePreviousArea),
                      URLCommand(kind: .captureArea, area: area)]
        for command in silent {
            #expect(URLCommandGate.decision(for: command, enabled: true, allowSilent: false)
                    == .refuse(command.kind.rawValue + refusal))
            #expect(URLCommandGate.decision(for: command, enabled: true, allowSilent: true) == .run)
        }
    }

    @Test func theRefusalNamesTheSenderWhenItIsKnown() {
        let command = URLCommand(kind: .captureArea, area: area)
        #expect(URLCommandGate.decision(for: command, enabled: true, allowSilent: false, sender: "Keyboard Maestro")
                == .refuse("capture-area from Keyboard Maestro" + refusal))
        #expect(URLCommandGate.decision(for: command, enabled: true, allowSilent: false, sender: nil)
                == .refuse("capture-area" + refusal))
        #expect(URLCommandGate.decision(for: command, enabled: true, allowSilent: false, sender: "")
                == .refuse("capture-area" + refusal))
        #expect(URLCommandGate.decision(for: command, enabled: true, allowSilent: false, sender: "Evil\u{202E}ppA")
                == .refuse("capture-area from EvilppA" + refusal))
    }

    /// A selection, a window click, All-in-One (a rect only preselects), the self-timer (it selects
    /// first) and scrolling (the session waits for Start) all wait for the user.
    @Test func commandsThatWaitForTheUserRunWithTheSecondToggleOff() {
        let waiting = everyCommand.filter { !$0.capturesWithoutSelection }
        #expect(waiting.count == 8)
        for command in waiting {
            #expect(URLCommandGate.decision(for: command, enabled: true, allowSilent: false, sender: "Raycast") == .run)
        }
    }

    @Test func restoreRecentlyClosedRunsWheneverURLCommandsAreOn() {
        let restore = URLCommand(kind: .restoreRecentlyClosed)
        #expect(URLCommandGate.decision(for: restore, enabled: true, allowSilent: false) == .run)
        #expect(URLCommandGate.decision(for: restore, enabled: true, allowSilent: true) == .run)
        #expect(URLCommandGate.decision(for: restore, enabled: false, allowSilent: true) == .refuse(off))
    }

    /// No separate switch for uploads (decision 4): the action never changes the decision.
    @Test func theActionDoesNotChangeTheDecision() {
        for action in URLCommand.Action.allCases {
            #expect(URLCommandGate.decision(for: URLCommand(kind: .captureFullscreen, action: action), enabled: true, allowSilent: false)
                    == .refuse("capture-fullscreen" + refusal))
            #expect(URLCommandGate.decision(for: URLCommand(kind: .captureWindow, action: action), enabled: true, allowSilent: false)
                    == .run)
        }
    }
}
```

`TidyShotTests/CaptureIntentTests.swift`:
```swift
import Testing
@testable import TidyShot

/// What each `action` asks for under each after-capture action (spec 2.9, URL scheme, Actions).
struct CaptureIntentTests {
    @Test func noActionIsTheAfterCaptureActionInGeneral() {
        for setting in AfterCaptureAction.allCases {
            #expect(CaptureIntent(urlAction: nil, setting: setting) == CaptureIntent(action: setting, copyOnly: false, then: .none))
        }
    }

    /// `upload` is Upload only when that is the setting (Tim's case), otherwise Upload and copy URL.
    @Test func uploadUploadsUnderEverySetting() {
        #expect(CaptureIntent(urlAction: .upload, setting: .uploadOnly) == CaptureIntent(action: .uploadOnly))
        #expect(CaptureIntent(urlAction: .upload, setting: .upload) == CaptureIntent(action: .upload))
        #expect(CaptureIntent(urlAction: .upload, setting: .save) == CaptureIntent(action: .upload))
    }

    @Test func saveIsSaveAndCopyImageUnderEverySetting() {
        for setting in AfterCaptureAction.allCases {
            #expect(CaptureIntent(urlAction: .save, setting: setting) == CaptureIntent(action: .save))
        }
    }

    @Test func copyPutsTheImageOnTheClipboardOnly() {
        for setting in AfterCaptureAction.allCases {
            let intent = CaptureIntent(urlAction: .copy, setting: setting)
            #expect(intent.copyOnly)
            #expect(intent.then == .none)
        }
    }

    @Test func annotateRunsTheAfterCaptureActionThenOpensTheEditor() {
        for setting in AfterCaptureAction.allCases {
            #expect(CaptureIntent(urlAction: .annotate, setting: setting) == CaptureIntent(action: setting, then: .annotate))
        }
    }

    @Test func pinRunsTheAfterCaptureActionThenPins() {
        for setting in AfterCaptureAction.allCases {
            #expect(CaptureIntent(urlAction: .pin, setting: setting) == CaptureIntent(action: setting, then: .pin))
        }
    }

    @Test func theSenderTravelsWithTheIntent() {
        #expect(CaptureIntent(urlAction: .copy, setting: .save, sender: "Raycast").sender == "Raycast")
        #expect(CaptureIntent(urlAction: nil, setting: .save).sender == nil)
    }

    /// Hotkeys and the menu: the General action, nothing else.
    @Test func standardIsTheGeneralSettingWithNothingAfter() {
        #expect(CaptureIntent.standard == CaptureIntent(action: AppSettings.shared.afterCaptureAction))
    }
}
```

`TidyShotTests/URLCommandHandlerTests.swift`:
```swift
import CoreGraphics
import Foundation
import Testing
@testable import TidyShot

/// Records what `URLCommandHandler` asked the app to do, in order.
final class URLTargetRecorder: URLCommandTarget {
    enum Call: Equatable {
        case area(CaptureIntent)
        case areaAt(ScreenRect, CaptureIntent)
        case window(CaptureIntent)
        case fullscreen(CaptureIntent)
        case previousArea(CaptureIntent)
        case allInOne(CaptureIntent, ScreenRect?)
        case selfTimer(CaptureIntent)
        case scrolling(CaptureIntent, ScreenRect?)
        case restore
    }

    var isCapturing = false
    private(set) var calls: [Call] = []

    func captureArea(intent: CaptureIntent) async { calls.append(.area(intent)) }
    func captureArea(at area: ScreenRect, intent: CaptureIntent) async { calls.append(.areaAt(area, intent)) }
    func captureWindow(intent: CaptureIntent) async { calls.append(.window(intent)) }
    func captureFullscreen(intent: CaptureIntent) async { calls.append(.fullscreen(intent)) }
    func capturePreviousArea(intent: CaptureIntent) async { calls.append(.previousArea(intent)) }
    func captureAllInOne(intent: CaptureIntent, preselect: ScreenRect?) async { calls.append(.allInOne(intent, preselect)) }
    func captureSelfTimer(intent: CaptureIntent) async { calls.append(.selfTimer(intent)) }
    func captureScrolling(intent: CaptureIntent, preselect: ScreenRect?) async { calls.append(.scrolling(intent, preselect)) }
    func restoreClosedOverlay() async { calls.append(.restore) }
}

/// The notices a handler posted.
final class URLNoticeLog {
    var notices: [URLCommandNotice] = []
}

/// The queue, the gate, the busy rule, the errors and the routing to every capture function
/// (spec 2.9, URL scheme and URL security).
struct URLCommandHandlerTests {
    let settings: AppSettings
    let target = URLTargetRecorder()
    let log = URLNoticeLog()
    /// Display 1 is 1920 x 1080 at the origin; display 2 sits to its right, 1280 x 800, top-aligned.
    let screens = URLCommandHandler.Screens(
        displays: [URLCommandGeometry.Display(id: 1, frame: CGRect(x: 0, y: 0, width: 1920, height: 1080)),
                   URLCommandGeometry.Display(id: 2, frame: CGRect(x: 1920, y: 0, width: 1280, height: 800))],
        pointerIndex: 0)
    let refusal = " captures without a selection. Allow it in Settings > General > URL commands."

    init() {
        let name = "URLCommandHandlerTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        settings = AppSettings(defaults: defaults)
        // Tim's mode, so the intents below differ from the default `.upload`.
        settings.afterCaptureAction = .uploadOnly
    }

    /// The intent a URL without `action` from Raycast carries.
    var standard: CaptureIntent { CaptureIntent(action: .uploadOnly, sender: "Raycast") }

    func notice(_ body: String, from sender: String? = "Raycast") -> URLCommandNotice {
        URLCommandNotice(title: "TidyShot URL command", subtitle: sender.map { "From \($0)" }, body: body)
    }

    /// A handler that has started, unless `ready` is false.
    func makeHandler(ready: Bool = true) async -> URLCommandHandler {
        let screens = screens
        let log = log
        let handler = URLCommandHandler(settings: settings, target: target, screens: { screens },
                                        post: { log.notices.append($0) })
        if ready {
            await handler.ready()
        }
        return handler
    }

    func send(_ handler: URLCommandHandler, _ string: String, from sender: String? = "Raycast") async throws {
        await handler.handle(try #require(URL(string: string)), sender: sender)
    }

    @Test func everyCommandReachesItsCaptureFunction() async throws {
        settings.urlCommandsAllowSilent = true
        let handler = await makeHandler()
        for string in ["capture-area", "capture-area?x=100&y=100&width=200&height=50", "capture-window",
                       "capture-fullscreen", "capture-previous-area", "all-in-one",
                       "all-in-one?x=10&y=10&width=300&height=200&display=2", "self-timer", "capture-scrolling",
                       "scrolling-capture?x=0&y=0&width=400&height=600", "restore-recently-closed"] {
            try await send(handler, "tidyshot://\(string)")
        }
        let small = ScreenRect(rect: CGRect(x: 100, y: 930, width: 200, height: 50), displayID: 1)
        let second = ScreenRect(rect: CGRect(x: 1930, y: 590, width: 300, height: 200), displayID: 2)
        let tall = ScreenRect(rect: CGRect(x: 0, y: 480, width: 400, height: 600), displayID: 1)
        #expect(target.calls == [.area(standard), .areaAt(small, standard), .window(standard), .fullscreen(standard),
                                 .previousArea(standard), .allInOne(standard, nil), .allInOne(standard, second),
                                 .selfTimer(standard), .scrolling(standard, nil), .scrolling(standard, tall), .restore])
        #expect(log.notices.isEmpty)
    }

    @Test func theActionTravelsAsTheIntent() async throws {
        let handler = await makeHandler()
        for action in ["copy", "save", "upload", "annotate"] {
            try await send(handler, "tidyshot://capture-window?action=\(action)")
        }
        try await send(handler, "tidyshot://capture-window?action=pin", from: nil)
        #expect(target.calls == [
            .window(CaptureIntent(action: .uploadOnly, copyOnly: true, sender: "Raycast")),
            .window(CaptureIntent(action: .save, sender: "Raycast")),
            .window(CaptureIntent(action: .uploadOnly, sender: "Raycast")),
            .window(CaptureIntent(action: .uploadOnly, then: .annotate, sender: "Raycast")),
            .window(CaptureIntent(action: .uploadOnly, then: .pin)),
        ])
    }

    @Test func silentCommandsAreRefusedByDefaultNamingTheSender() async throws {
        let handler = await makeHandler()
        try await send(handler, "tidyshot://capture-fullscreen?action=copy", from: "Keyboard Maestro")
        try await send(handler, "tidyshot://capture-previous-area", from: nil)
        try await send(handler, "tidyshot://capture-area?x=0&y=0&width=10&height=10")
        #expect(target.calls.isEmpty)
        #expect(log.notices == [
            notice("capture-fullscreen from Keyboard Maestro" + refusal, from: "Keyboard Maestro"),
            notice("capture-previous-area" + refusal, from: nil),
            notice("capture-area from Raycast" + refusal),
        ])
    }

    @Test func commandsThatWaitForTheUserRunWithSilentCapturesOff() async throws {
        let handler = await makeHandler()
        for string in ["capture-area?action=copy", "capture-window", "all-in-one?x=100&y=100&width=200&height=50",
                       "self-timer", "capture-scrolling?x=0&y=0&width=400&height=600", "restore-recently-closed"] {
            try await send(handler, "tidyshot://\(string)")
        }
        let small = ScreenRect(rect: CGRect(x: 100, y: 930, width: 200, height: 50), displayID: 1)
        let tall = ScreenRect(rect: CGRect(x: 0, y: 480, width: 400, height: 600), displayID: 1)
        #expect(target.calls == [.area(CaptureIntent(action: .uploadOnly, copyOnly: true, sender: "Raycast")),
                                 .window(standard), .allInOne(standard, small), .selfTimer(standard),
                                 .scrolling(standard, tall), .restore])
        #expect(log.notices.isEmpty)
    }

    /// Off means off: nothing is parsed, so a bad URL gets the same answer as a good one.
    @Test func withURLCommandsOffEveryURLIsRefusedAlike() async throws {
        settings.urlCommandsEnabled = false
        settings.urlCommandsAllowSilent = true
        let handler = await makeHandler()
        for string in ["capture-area", "restore-recently-closed", "capture-everything", "capture-area?action=print"] {
            try await send(handler, "tidyshot://\(string)")
        }
        #expect(target.calls.isEmpty)
        #expect(log.notices == Array(repeating: notice("URL commands are off. Turn them on in Settings > General."), count: 4))
    }

    @Test func errorsArePostedAndRunNothing() async throws {
        settings.urlCommandsAllowSilent = true
        let handler = await makeHandler()
        for string in ["capture-everything", "capture-area?x=1&y=2", "all-in-one?x=0&y=0&width=10&height=10&display=3",
                       "capture-scrolling?x=5000&y=0&width=10&height=10", "capture-area?action=copy&action=upload"] {
            try await send(handler, "tidyshot://\(string)")
        }
        #expect(target.calls.isEmpty)
        #expect(log.notices == [
            notice("Unknown command “capture-everything”."),
            notice("x, y, width and height must be given together, as numbers, with width and height above 0."),
            notice("There is no display 3."),
            notice("The area leaves less than a point on display 1."),
            notice("“action” is given more than once."),
        ])
    }

    /// Never queued behind a running capture; a scrolling session is never advanced by a URL.
    @Test func captureCommandsAreDroppedWhileACaptureRuns() async throws {
        settings.urlCommandsAllowSilent = true
        target.isCapturing = true
        let handler = await makeHandler()
        for string in ["capture-area", "capture-fullscreen", "capture-scrolling", "all-in-one", "self-timer"] {
            try await send(handler, "tidyshot://\(string)")
        }
        #expect(target.calls.isEmpty)
        #expect(log.notices.isEmpty)
        try await send(handler, "tidyshot://restore-recently-closed")
        #expect(target.calls == [.restore])
    }

    @Test func urlsWaitUntilTheAppHasStartedThenRunInOrder() async throws {
        let handler = await makeHandler(ready: false)
        try await send(handler, "tidyshot://capture-window")
        try await send(handler, "tidyshot://restore-recently-closed")
        try await send(handler, "tidyshot://capture-fullscreen")
        #expect(target.calls.isEmpty)
        #expect(log.notices.isEmpty)
        await handler.ready()
        #expect(target.calls == [.window(standard), .restore])
        #expect(log.notices == [notice("capture-fullscreen from Raycast" + refusal)])
        await handler.ready()
        #expect(target.calls.count == 2)
    }

    @Test func theQueueHoldsAtMostEightURLs() async throws {
        #expect(URLCommandHandler.queueLimit == 8)
        let handler = await makeHandler(ready: false)
        for _ in 0..<10 {
            try await send(handler, "tidyshot://restore-recently-closed")
        }
        await handler.ready()
        #expect(target.calls.count == 8)
    }

    /// URL text reaches logs and notifications as data, never as a format string.
    @Test func formatSpecifiersInAURLAreJustText() async throws {
        let handler = await makeHandler()
        try await send(handler, "tidyshot://capture-area?action=%25@%25@%25s%25n", from: "%@ %n App")
        #expect(log.notices == [notice("Unknown action “%@%@%s%n”. Use upload, save, copy, annotate or pin.", from: "%@ %n App")])
    }

    @Test func aSenderNameIsCleanedAndAnEmptyOneIsUnknown() async throws {
        let handler = await makeHandler()
        try await send(handler, "tidyshot://capture-fullscreen", from: "\u{202E}")
        try await send(handler, "tidyshot://capture-fullscreen", from: "Key\u{0}board\u{202E} Maestro")
        #expect(log.notices == [notice("capture-fullscreen" + refusal, from: nil),
                                notice("capture-fullscreen from Keyboard Maestro" + refusal, from: "Keyboard Maestro")])
        #expect(URLCommandHandler.senderName("  ") == "  ")
        #expect(URLCommandHandler.senderName(nil) == nil)
    }
}
```

In `TidyShotTests/AppSettingsTests.swift`, add inside `struct AppSettingsTests`, after Task 3's `selfTimerSecondsOutsideTheChoicesReadAsFive` (its last test):
```swift
    @Test func urlCommandsAreOnAndSilentCapturesOffByDefault() {
        let settings = AppSettings(defaults: freshDefaults())
        #expect(settings.urlCommandsEnabled)
        #expect(!settings.urlCommandsAllowSilent)
    }

    @Test func urlCommandSettingsRoundTripThroughASecondInstance() {
        let defaults = freshDefaults()
        let first = AppSettings(defaults: defaults)
        first.urlCommandsEnabled = false
        first.urlCommandsAllowSilent = true
        let second = AppSettings(defaults: defaults)
        #expect(!second.urlCommandsEnabled)
        #expect(second.urlCommandsAllowSilent)
        #expect(defaults.object(forKey: "urlCommandsEnabled") as? Bool == false)
        #expect(defaults.object(forKey: "urlCommandsAllowSilent") as? Bool == true)
    }
```

- [ ] **Step 2: Run the tests and see them fail**

Run:
```bash
xcodegen generate && xcodebuild test -project TidyShot.xcodeproj -scheme TidyShot -destination 'platform=macOS' -derivedDataPath .build 2>&1 | grep -E "Test run with|error:|TEST"
```
Expected: the build fails with `error:` lines such as `cannot find 'URLCommand' in scope`, `cannot find type 'URLCommandTarget' in scope`, `cannot find 'CaptureIntent' in scope`, `cannot find 'ScreenRect' in scope` and `value of type 'AppSettings' has no member 'urlCommandsEnabled'`, then `** TEST FAILED **` or `** BUILD FAILED **`. No test runs.

- [ ] **Step 3: Implement `URLCommand`**

`TidyShot/URLScheme/URLCommand.swift`:
```swift
import Foundation

/// One `tidyshot://` command, parsed (spec 2.9, URL scheme). Pure. `parse` checks everything a
/// sender controls, so the gate, the geometry and the coordinator only see well-formed values.
nonisolated struct URLCommand: Equatable, Sendable {
    enum Kind: String, CaseIterable, Sendable {
        case captureArea = "capture-area"
        case captureWindow = "capture-window"
        case captureFullscreen = "capture-fullscreen"
        case capturePreviousArea = "capture-previous-area"
        case allInOne = "all-in-one"
        case selfTimer = "self-timer"
        case captureScrolling = "capture-scrolling"
        case restoreRecentlyClosed = "restore-recently-closed"

        /// CleanShot's names that mean the same command.
        static let aliases: [String: Kind] = ["scrolling-capture": .captureScrolling]

        /// Takes `action`. Restore captures nothing.
        var isCapture: Bool { self != .restoreRecentlyClosed }
        /// Takes `x`, `y`, `width`, `height` and `display`.
        var takesArea: Bool { self == .captureArea || self == .allInOne || self == .captureScrolling }
    }

    enum Action: String, CaseIterable, Sendable {
        case upload, save, copy, annotate, pin
    }

    /// The rect as sent: points, origin at the bottom-left corner of the display.
    struct Area: Equatable, Sendable {
        var x: Double
        var y: Double
        var width: Double
        var height: Double
    }

    var kind: Kind
    var action: Action?
    var area: Area?
    /// 1-based, 1 the main display. Used only together with `area`.
    var display: Int?

    /// Captures with no drag or click by the user (spec 2.9, URL security). Only these need
    /// Allow URL commands that capture without a selection.
    var capturesWithoutSelection: Bool {
        switch kind {
        case .captureFullscreen, .capturePreviousArea: true
        case .captureArea: area != nil
        case .captureWindow, .allInOne, .selfTimer, .captureScrolling, .restoreRecentlyClosed: false
        }
    }

    /// No arrangement of displays reaches this many points from a display's corner.
    static let coordinateLimit: Double = 100_000
    /// The longest number accepted, in characters.
    static let numberLengthLimit = 16
    /// The longest value a message quotes, in characters.
    static let displayLimit = 40
    private static let rectNames = ["x", "y", "width", "height"]

    /// The command is the host (`tidyshot://capture-area`) or the first path component
    /// (`tidyshot:capture-area`, `tidyshot:///capture-area`). `URLComponents` percent-decodes the
    /// host, the path and every query name and value; names and actions are then matched ignoring
    /// case. A parameter the command does not take is ignored; one it takes may appear once.
    static func parse(_ url: URL) -> Result<URLCommand, URLCommandError> {
        guard url.scheme?.lowercased() == "tidyshot",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return .failure(.unknownCommand(url.absoluteString))
        }
        let host = components.host.flatMap { $0.isEmpty ? nil : $0 }
        let name = host ?? components.path.split(separator: "/").first.map(String.init) ?? ""
        guard let kind = Kind(rawValue: name.lowercased()) ?? Kind.aliases[name.lowercased()] else {
            return .failure(.unknownCommand(name))
        }

        var taken: Set<String> = kind.isCapture ? ["action"] : []
        if kind.takesArea {
            taken.formUnion(rectNames + ["display"])
        }
        var values: [String: String] = [:]
        for item in components.queryItems ?? [] {
            let key = item.name.lowercased()
            guard taken.contains(key) else { continue }
            guard values[key] == nil else { return .failure(.repeatedParameter(key)) }
            values[key] = item.value ?? ""
        }

        var command = URLCommand(kind: kind)
        if let raw = values["action"] {
            guard let action = Action(rawValue: raw.lowercased()) else { return .failure(.unknownAction(raw)) }
            command.action = action
        }
        let rect = rectNames.map { values[$0] }
        if rect.contains(where: { $0 != nil }) {
            let numbers = rect.map { $0.flatMap { number($0) } }
            guard let x = numbers[0], let y = numbers[1], let width = numbers[2], let height = numbers[3],
                  width > 0, height > 0 else { return .failure(.badArea) }
            command.area = Area(x: x, y: y, width: width, height: height)
        }
        if let raw = values["display"] {
            guard let display = displayNumber(raw) else { return .failure(.noDisplay(raw)) }
            command.display = display
        }
        return .success(command)
    }

    /// A plain decimal: an optional `-`, digits, and at most one `.` followed by digits; at most
    /// `numberLengthLimit` characters and `coordinateLimit` in size. `Double(_:)` alone would also
    /// take `nan`, `inf`, `1e3`, `0x10` and `+5`.
    static func number(_ text: String) -> Double? {
        guard !text.isEmpty, text.utf8.count <= numberLengthLimit else { return nil }
        let unsigned = text.hasPrefix("-") ? text.dropFirst() : Substring(text)
        let parts = unsigned.split(separator: ".", omittingEmptySubsequences: false)
        guard (1...2).contains(parts.count),
              parts.allSatisfy({ part in !part.isEmpty && part.unicodeScalars.allSatisfy { (48...57).contains($0.value) } }),
              let value = Double(text), value.isFinite, abs(value) <= coordinateLimit else { return nil }
        return value
    }

    /// `display`: 1 to 99, ASCII digits only.
    static func displayNumber(_ text: String) -> Int? {
        guard (1...2).contains(text.utf8.count),
              text.unicodeScalars.allSatisfy({ (48...57).contains($0.value) }),
              let value = Int(text), value >= 1 else { return nil }
        return value
    }

    /// A value from the URL (or a sender's name) as a message shows it: control and format
    /// characters (a NUL, a newline, a right-to-left override) and line separators removed, and
    /// at most `displayLimit` characters, then `…`.
    static func displayed(_ raw: String) -> String {
        let kept = raw.unicodeScalars.filter { scalar in
            switch scalar.properties.generalCategory {
            case .control, .format, .lineSeparator, .paragraphSeparator: false
            default: true
            }
        }
        let text = String(kept)
        return text.count > displayLimit ? String(text.prefix(displayLimit)) + "…" : text
    }
}

/// Why a URL was not run. `message` is the notification body (spec 2.9, Errors and refusals; the
/// repeated-parameter text is this plan's).
nonisolated enum URLCommandError: Error, Equatable, Sendable {
    case unknownCommand(String)
    case unknownAction(String)
    case badArea
    case noDisplay(String)
    case repeatedParameter(String)

    var message: String {
        switch self {
        case .unknownCommand(let name):
            "Unknown command “\(URLCommand.displayed(name))”."
        case .unknownAction(let value):
            "Unknown action “\(URLCommand.displayed(value))”. Use upload, save, copy, annotate or pin."
        case .badArea:
            "x, y, width and height must be given together, as numbers, with width and height above 0."
        case .noDisplay(let value):
            "There is no display \(URLCommand.displayed(value))."
        case .repeatedParameter(let name):
            "“\(URLCommand.displayed(name))” is given more than once."
        }
    }
}
```

- [ ] **Step 4: Implement `URLCommandGeometry`**

`TidyShot/URLScheme/URLCommandGeometry.swift`:
```swift
import CoreGraphics

/// A rect in CoreGraphics global points (origin top left of the main display, y down) and the
/// display it lies on.
nonisolated struct ScreenRect: Equatable, Sendable {
    var rect: CGRect
    var displayID: CGDirectDisplayID
}

/// A URL command's x, y, width and height on screen (spec 2.9, decision 13). Pure. The command
/// gives points from the bottom-left corner of one display, as CleanShot's API does; the capture
/// code takes CoreGraphics global points.
nonisolated enum URLCommandGeometry {
    /// A connected display, in `NSScreen.screens` order: display 1 is index 0, the main display.
    struct Display: Equatable, Sendable {
        let id: CGDirectDisplayID
        /// CoreGraphics global points.
        let frame: CGRect
    }

    enum Resolution: Equatable, Sendable {
        /// The rect clipped to its display.
        case area(ScreenRect)
        /// The display named, or display 1 when none is connected, does not exist.
        case noDisplay(Int)
        /// The rect leaves less than a point on its display.
        case outside(display: Int)
    }

    /// `display` (1-based) when given, otherwise the display at `pointerIndex`, otherwise display 1.
    /// The display's bottom-left corner is `(frame.minX, frame.maxY)` in CoreGraphics points.
    static func resolve(_ area: URLCommand.Area, display: Int?, displays: [Display], pointerIndex: Int?) -> Resolution {
        let index: Int
        if let display {
            guard displays.indices.contains(display - 1) else { return .noDisplay(display) }
            index = display - 1
        } else if let pointerIndex, displays.indices.contains(pointerIndex) {
            index = pointerIndex
        } else {
            guard !displays.isEmpty else { return .noDisplay(1) }
            index = 0
        }
        let frame = displays[index].frame
        let rect = CGRect(x: frame.minX + area.x, y: frame.maxY - area.y - area.height,
                          width: area.width, height: area.height)
        let clipped = rect.intersection(frame)
        guard !clipped.isNull, clipped.width >= 1, clipped.height >= 1 else { return .outside(display: index + 1) }
        return .area(ScreenRect(rect: clipped, displayID: displays[index].id))
    }

    /// The notification body for `.outside` (this plan's text; 2.9 has none for it).
    static func outsideMessage(display: Int) -> String {
        "The area leaves less than a point on display \(display)."
    }
}
```

- [ ] **Step 5: Implement `URLCommandGate`**

`TidyShot/URLScheme/URLCommandGate.swift`:
```swift
/// Whether a parsed URL command may run (spec 2.9, URL security). Pure.
nonisolated enum URLCommandGate {
    enum Decision: Equatable, Sendable {
        case run
        /// The notification body.
        case refuse(String)
    }

    static let disabledMessage = "URL commands are off. Turn them on in Settings > General."

    /// Off refuses everything. On, a command that captures without a selection
    /// (`URLCommand.capturesWithoutSelection`) also needs `allowSilent`; every other command,
    /// restore included, runs. The action plays no part (decision 4). `sender` is named in the
    /// refusal when it is known and not empty once cleaned.
    static func decision(for command: URLCommand, enabled: Bool, allowSilent: Bool, sender: String? = nil) -> Decision {
        guard enabled else { return .refuse(disabledMessage) }
        guard command.capturesWithoutSelection, !allowSilent else { return .run }
        let name = sender.map(URLCommand.displayed).flatMap { $0.isEmpty ? nil : $0 }
        let from = name.map { " from \($0)" } ?? ""
        return .refuse("\(command.kind.rawValue)\(from) captures without a selection. Allow it in Settings > General > URL commands.")
    }
}
```

- [ ] **Step 6: Implement `CaptureIntent`**

In `TidyShot/Settings/AppSettings.swift`, line 4, `enum AfterCaptureAction: String, CaseIterable, Identifiable {` becomes
```swift
nonisolated enum AfterCaptureAction: String, CaseIterable, Identifiable, Sendable {
```
so the pure `CaptureIntent` can hold it (its members are string constants and a comparison).

`TidyShot/Capture/CaptureIntent.swift`:
```swift
/// How one capture is finished (spec 2.9, URL scheme, Actions): the after-capture action, whether
/// the image only goes on the clipboard, and what opens afterwards. Hotkeys and the menu pass
/// `.standard`; a URL command's `action` makes the others. It travels through every capture
/// function into `AppCoordinator.save(_:intent:)`.
nonisolated struct CaptureIntent: Equatable, Sendable {
    enum Then: Equatable, Sendable {
        case none
        /// Open the editor on the new record.
        case annotate
        /// Open a pin of the new record.
        case pin
    }

    var action: AfterCaptureAction
    /// `action=copy`: the image goes on the clipboard and nothing else happens.
    var copyOnly: Bool
    var then: Then
    /// The app that sent the URL command, cleaned, for the notifications this capture posts. Nil
    /// for hotkeys, the menu and an unknown sender.
    var sender: String?

    init(action: AfterCaptureAction, copyOnly: Bool = false, then: Then = .none, sender: String? = nil) {
        self.action = action
        self.copyOnly = copyOnly
        self.then = then
        self.sender = sender
    }

    /// What a URL command's `action` asks for, given the after-capture action in General.
    init(urlAction: URLCommand.Action?, setting: AfterCaptureAction, sender: String? = nil) {
        switch urlAction {
        case nil: self.init(action: setting, sender: sender)
        case .upload: self.init(action: setting == .uploadOnly ? .uploadOnly : .upload, sender: sender)
        case .save: self.init(action: .save, sender: sender)
        case .copy: self.init(action: setting, copyOnly: true, sender: sender)
        case .annotate: self.init(action: setting, then: .annotate, sender: sender)
        case .pin: self.init(action: setting, then: .pin, sender: sender)
        }
    }

    /// Hotkeys and the menu: the after-capture action in General, read when the capture starts.
    @MainActor static var standard: CaptureIntent {
        CaptureIntent(urlAction: nil, setting: AppSettings.shared.afterCaptureAction)
    }
}
```

- [ ] **Step 7: Implement `URLCommandHandler`**

`TidyShot/URLScheme/URLCommandHandler.swift`:
```swift
import Foundation

/// What URL commands run: the app's existing capture functions. `AppCoordinator` conforms; the
/// tests use a recorder.
protocol URLCommandTarget: AnyObject {
    var isCapturing: Bool { get }
    func captureArea(intent: CaptureIntent) async
    func captureArea(at area: ScreenRect, intent: CaptureIntent) async
    func captureWindow(intent: CaptureIntent) async
    func captureFullscreen(intent: CaptureIntent) async
    func capturePreviousArea(intent: CaptureIntent) async
    func captureAllInOne(intent: CaptureIntent, preselect: ScreenRect?) async
    func captureSelfTimer(intent: CaptureIntent) async
    func captureScrolling(intent: CaptureIntent, preselect: ScreenRect?) async
    func restoreClosedOverlay() async
}

/// A notification the URL scheme posts. The subtitle names the sending app when it is known.
nonisolated struct URLCommandNotice: Equatable, Sendable {
    var title: String
    var subtitle: String?
    var body: String
}

/// Runs `tidyshot://` URLs (spec 2.9, URL scheme and URL security). It holds URLs until the app has
/// started, then for each: parse, gate, drop a capture command while a capture runs, place a rect,
/// and call the target's capture function with the command's `CaptureIntent`. Every refusal and
/// error posts a notice titled `TidyShot URL command`; every URL is logged with its sender, the
/// URL passed as an argument and never as a format.
final class URLCommandHandler {
    struct Screens {
        /// In `NSScreen.screens` order, CoreGraphics frames.
        var displays: [URLCommandGeometry.Display]
        /// The display under the pointer.
        var pointerIndex: Int?
    }

    static let noticeTitle = "TidyShot URL command"
    /// URLs held before `ready()`. A cold launch from a URL brings one; more is a flood.
    static let queueLimit = 8

    private let settings: AppSettings
    private weak var target: (any URLCommandTarget)?
    private let screens: () -> Screens
    private let post: (URLCommandNotice) -> Void
    private var isReady = false
    private var queued: [(url: URL, sender: String?)] = []

    init(settings: AppSettings, target: any URLCommandTarget, screens: @escaping () -> Screens,
         post: @escaping (URLCommandNotice) -> Void) {
        self.settings = settings
        self.target = target
        self.screens = screens
        self.post = post
    }

    /// Runs `url` now, or queues it until `ready()`.
    func handle(_ url: URL, sender: String?) async {
        guard isReady else {
            guard queued.count < Self.queueLimit else {
                NSLog("%@", "URL command dropped, \(Self.queueLimit) are already waiting for launch: \(url.absoluteString)")
                return
            }
            queued.append((url, sender))
            return
        }
        await run(url, sender: sender)
    }

    /// Called once `AppCoordinator.start()` has run: the waiting URLs run in the order they came.
    func ready() async {
        guard !isReady else { return }
        isReady = true
        let waiting = queued
        queued = []
        for item in waiting {
            await run(item.url, sender: item.sender)
        }
    }

    /// The sender as messages show it (`URLCommand.displayed`), or nil when unknown or empty.
    static func senderName(_ sender: String?) -> String? {
        guard let sender else { return nil }
        let shown = URLCommand.displayed(sender)
        return shown.isEmpty ? nil : shown
    }

    private func run(_ url: URL, sender rawSender: String?) async {
        let sender = Self.senderName(rawSender)
        let command: URLCommand
        switch URLCommand.parse(url) {
        case .failure(let error):
            // With URL commands off nothing is parsed: every URL gets the same refusal.
            refuse(settings.urlCommandsEnabled ? error.message : URLCommandGate.disabledMessage, url: url, sender: sender)
            return
        case .success(let parsed):
            command = parsed
        }
        if case .refuse(let message) = URLCommandGate.decision(for: command, enabled: settings.urlCommandsEnabled,
                                                               allowSilent: settings.urlCommandsAllowSilent, sender: sender) {
            refuse(message, url: url, sender: sender)
            return
        }
        guard let target else { return }
        // Never queued behind a running capture, and never a Start or Done for a scrolling session.
        if command.kind.isCapture, target.isCapturing {
            NSLog("%@", "URL command from \(sender ?? "an unknown app") dropped, a capture is running: \(url.absoluteString)")
            return
        }
        var placement: ScreenRect?
        if let area = command.area {
            let current = screens()
            switch URLCommandGeometry.resolve(area, display: command.display, displays: current.displays,
                                              pointerIndex: current.pointerIndex) {
            case .area(let resolved):
                placement = resolved
            case .noDisplay(let number):
                refuse(URLCommandError.noDisplay(String(number)).message, url: url, sender: sender)
                return
            case .outside(let number):
                refuse(URLCommandGeometry.outsideMessage(display: number), url: url, sender: sender)
                return
            }
        }
        NSLog("%@", "URL command from \(sender ?? "an unknown app"): \(url.absoluteString)")
        let intent = CaptureIntent(urlAction: command.action, setting: settings.afterCaptureAction, sender: sender)
        switch command.kind {
        case .captureArea:
            if let placement {
                await target.captureArea(at: placement, intent: intent)
            } else {
                await target.captureArea(intent: intent)
            }
        case .captureWindow: await target.captureWindow(intent: intent)
        case .captureFullscreen: await target.captureFullscreen(intent: intent)
        case .capturePreviousArea: await target.capturePreviousArea(intent: intent)
        case .allInOne: await target.captureAllInOne(intent: intent, preselect: placement)
        case .selfTimer: await target.captureSelfTimer(intent: intent)
        case .captureScrolling: await target.captureScrolling(intent: intent, preselect: placement)
        case .restoreRecentlyClosed: await target.restoreClosedOverlay()
        }
    }

    private func refuse(_ message: String, url: URL, sender: String?) {
        NSLog("%@", "URL command from \(sender ?? "an unknown app") refused (\(message)): \(url.absoluteString)")
        post(URLCommandNotice(title: Self.noticeTitle, subtitle: sender.map { "From \($0)" }, body: message))
    }
}
```
Every `NSLog` here takes `"%@"` as its format: a URL is sender-controlled text, and `%@` or `%n` in a format string reads or writes memory. The rest of the app's `NSLog` calls are not touched.

- [ ] **Step 8: Add the settings, the General section and the notification subtitle**

In `TidyShot/Settings/AppSettings.swift`:
- In `Keys`, after `static let freezeScreen = "freezeScreen"` (line 56):
  ```swift
          static let urlCommandsEnabled = "urlCommandsEnabled"
          static let urlCommandsAllowSilent = "urlCommandsAllowSilent"
  ```
- After the `freezeScreen` property (line 98):
  ```swift
      /// General, URL commands: `Allow URL commands (tidyshot://)`. Off refuses every command.
      var urlCommandsEnabled: Bool { didSet { defaults.set(urlCommandsEnabled, forKey: Keys.urlCommandsEnabled) } }
      /// General, URL commands: `Allow URL commands that capture without a selection`
      /// (capture-fullscreen, capture-previous-area, capture-area with a rect). Off by default.
      var urlCommandsAllowSilent: Bool { didSet { defaults.set(urlCommandsAllowSilent, forKey: Keys.urlCommandsAllowSilent) } }
  ```
- In `defaults.register`, after `Keys.freezeScreen: false,` (line 139):
  ```swift
              Keys.urlCommandsEnabled: true,
              Keys.urlCommandsAllowSilent: false,
  ```
- In `init`, after `freezeScreen = defaults.bool(forKey: Keys.freezeScreen)` (line 170):
  ```swift
          urlCommandsEnabled = defaults.bool(forKey: Keys.urlCommandsEnabled)
          urlCommandsAllowSilent = defaults.bool(forKey: Keys.urlCommandsAllowSilent)
  ```

`TidyShot/Settings/GeneralSettingsView.swift`: the `Form`'s existing rows (lines 9-40, `LabeledContent("Save to")` to `Toggle("Play sound", …)`) move unchanged into a `Section { … }`, and a second section follows it inside the `Form`:
```swift
            Section("URL commands") {
                Toggle("Allow URL commands (tidyshot://)", isOn: $settings.urlCommandsEnabled)
                Toggle("Allow URL commands that capture without a selection", isOn: $settings.urlCommandsAllowSilent)
                    .disabled(!settings.urlCommandsEnabled)
                Text("capture-fullscreen, capture-previous-area and capture-area with x, y, width and height capture at once. Any app on this Mac, and any web page you let open TidyShot, can send them.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
```
`.formStyle(.grouped)` stays on the `Form`. The window is 600 x 800 (`SettingsView`) and the form scrolls if it is taller.

`TidyShot/Output/Notifier.swift`: `notifyError` (lines 36-41) and `notify` (lines 44-49) gain a last parameter `subtitle: String? = nil`, and each sets `content.subtitle = subtitle` when it is not nil, before `post(content)`. Every existing call compiles unchanged.

- [ ] **Step 9: Carry the intent through every capture function into `save`**

All in `TidyShot/App/AppCoordinator.swift`.

1. `captureFullscreen()` (lines 148-155) becomes `func captureFullscreen(intent: CaptureIntent = .standard) async`, and its `await save(result)` (line 153) becomes `await save(result, intent: intent)`.
2. `captureArea()` (lines 157-159) becomes
   ```swift
    func captureArea(intent: CaptureIntent = .standard) async {
        await runSelection(mode: .area, intent: intent)
    }
   ```
   and `captureWindow()` (lines 161-163) the same with `mode: .window`.
3. `runSelection(mode:)` (line 221) becomes `private func runSelection(mode: SelectionMode, intent: CaptureIntent) async`, and its `await save(result)` (line 246) becomes `await save(result, intent: intent)`. Its `.area` case is Task 2's `areaResult(rect:display:)` and does not change.
4. `capturePreviousArea()` (line 202) becomes `func capturePreviousArea(intent: CaptureIntent = .standard) async`, and its `await save(result)` (line 215) becomes `await save(result, intent: intent)`.
5. `captureScrolling()` (as Task 2 left it, calling `runScrolling` after the selection) becomes:
   ```swift
    /// Capture Scrolling: select an area or a window's frame, run the scrolling session, and save
    /// the stitched image like any capture. During a session the shortcut is Start, then Done. A URL
    /// command's rect (`preselect`) skips the selection: the session opens on it and waits for
    /// Start. A URL command never reaches this during a session: the handler drops it while a
    /// capture runs.
    func captureScrolling(intent: CaptureIntent = .standard, preselect: ScreenRect? = nil) async {
        // During a session the shortcut is Start, then Done (the lock is held meanwhile).
        if scrollCapture.isRunning {
            scrollCapture.advance()
            return
        }
        await withCaptureLock {
            guard let content = await loadContent() else { return }
            if let preselect {
                guard let display = content.displays.first(where: { $0.displayID == preselect.displayID }) else {
                    NSLog("%@", "Capture Scrolling: display \(preselect.displayID) is gone")
                    return
                }
                // No selection overlay activated the app, and the panel's Start must take Return.
                NSApplication.shared.activate(ignoringOtherApps: true)
                // `runScrolling` refuses a rect under 100 pt; its `dismiss()` is a no-op here.
                await runScrolling(rect: preselect.rect, display: display, intent: intent)
                return
            }
            guard let selection = await selector.select(mode: .scrolling, content: content) else { return }
            guard case .area(let rect, let display) = selection else {
                selector.dismiss()
                return
            }
            await runScrolling(rect: rect, display: display, intent: intent)
        }
    }
   ```
   `runScrolling` gains its `intent:` parameter in Step 10.
6. After `capturePreviousArea`, add the URL rect capture:
   ```swift
    /// A URL command's `capture-area` with x, y, width and height (the gate has allowed it): that
    /// rect at once, live, with no selection overlay, as Capture Previous Area captures (the cards
    /// excluded, the pointer from Show cursor). It is stored as the previous area.
    func captureArea(at area: ScreenRect, intent: CaptureIntent) async {
        await withCaptureLock {
            guard let content = await loadContent() else { return }
            guard let display = content.displays.first(where: { $0.displayID == area.displayID }) else {
                NSLog("%@", "URL capture-area: display \(area.displayID) is gone")
                return
            }
            settings.lastAreaRect = StoredRect(area.rect)
            let cards = await cardWindows()
            guard let result = await capture(.area(rect: area.rect, display: display), excludingWindows: cards) else { return }
            await save(result, intent: intent)
        }
    }
   ```
7. `save(_:)` (lines 285-335) gains the intent and returns the record. Its doc comment gains: `The intent's action replaces the General one; `copyOnly` leaves after `copyOnly(_:sender:)`; `then` opens the editor or a pin on the new record. Returns the record, or nil when nothing was recorded.` The function becomes:
   ```swift
    @discardableResult
    func save(_ result: CaptureResult, intent: CaptureIntent = .standard) async -> CaptureRecord? {
        if intent.copyOnly {
            await copyOnly(result, sender: intent.sender)
            return nil
        }
        latestCapture = nil
        latestCaptureArea = nil
        let image = result.scaled
        let action = intent.action
   ```
   followed by the body of lines 296-328 unchanged, except that the `return` in the encode `catch` (line 324) becomes `return nil`; then:
   ```swift
        guard let record = await persist(png: png, image: image, action: action, destination: destination,
                                         alreadyOnClipboard: copyImageNow,
                                         captureDisplayID: result.target.displayID) else { return nil }
        // Task 4: before anything below, so a pin of this record opens over the spot it came from.
        latestCaptureArea = result.target.areaRect.map { (id: record.id, rect: $0) }
        if let copiedChangeCount {
            clipboardOwner = EditorClipboard.Owner(recordID: record.id, changeCount: copiedChangeCount)
        }
        switch intent.then {
        case .none: break
        case .annotate: openEditor(recordID: record.id)
        case .pin: await pin(recordID: record.id)
        }
        return record
    }
   ```
   `persist` is unchanged: it takes `action` as a parameter already. Task 4's two `latestCaptureArea` lines stay where Task 4 put them; `copyOnly` touches neither.
8. After `save`, add:
   ```swift
    /// `action=copy` (spec 2.9, URL scheme, Actions): the image goes on the clipboard and nothing
    /// else happens: no file, no record, no thumbnail, no card, no upload. The shutter sound follows
    /// Play sound, so no capture happens unheard, and `Image copied` is posted when notifications
    /// are on, naming the sending app. `latestCapture` and `clipboardOwner` stay: the newest card
    /// still owns its image, and an edit of an earlier capture compares the clipboard's change
    /// count, which this copy has moved on.
    private func copyOnly(_ result: CaptureResult, sender: String?) async {
        let image = result.scaled
        let encoded = await Task.detached(priority: .userInitiated) { () -> (png: Data?, tiff: Data?) in
            (try? ImageEncoder.pngData(from: image.image, scale: image.scale),
             Pasteboard.companionTIFF(of: image.image, scale: image.scale))
        }.value
        if let png = encoded.png {
            Pasteboard.copy(pngData: png, tiffData: encoded.tiff)
        } else {
            // As `save` does when the PNG fails: the TIFF alone, so the capture is not lost.
            let tiff = await Task.detached(priority: .userInitiated) {
                Pasteboard.tiffData(of: image.image, scale: image.scale)
            }.value
            Pasteboard.copy(tiffData: tiff)
        }
        if settings.playSound {
            SoundPlayer.playShutter()
        }
        if settings.showNotification {
            notifier.notify(title: "Image copied", body: "\(image.image.width) × \(image.image.height) px",
                            subtitle: sender.map { "From \($0)" })
        }
    }
   ```

- [ ] **Step 10: Extend All-in-One and the Self-Timer**

Tasks 2 and 3 wrote these functions; this step threads the intent through them and gives All-in-One's `preselect` the URL rect's type. `SelectionController` does not change: Task 2's `selectAllInOne(content:freeze:preselect:)` already takes the start rect.

1. Task 2's `runScrolling(rect:display:)` becomes `private func runScrolling(rect: CGRect, display: SCDisplay, intent: CaptureIntent) async`, and its `await save(CaptureResult(...))` passes `intent: intent`. Its callers are `captureScrolling` (Step 9) and `captureAllInOne` (item 2).
2. Task 2's `captureAllInOne(preselect: CGRect? = nil)` becomes `func captureAllInOne(intent: CaptureIntent = .standard, preselect: ScreenRect? = nil) async`, and in its body:
   - the `selectAllInOne` call passes `preselect: preselect?.rect ?? settings.lastAreaRect?.cgRect`, so a URL rect wins and the stored rect is otherwise used as before. The URL rect is already clipped to its display, so `restored` keeps it. A preselect does not write `lastAreaRect`; the capture that follows does, as every All-in-One area kind does;
   - `.scrolling`: `await runScrolling(rect: rect, display: display, intent: intent)`;
   - `.timer` (Task 3's case): `await runSelfTimer(.area(rect: rect, display: display), intent: intent)`;
   - the one `await save(result)` after the `switch` becomes `await save(result, intent: intent)`. `.area`, `.window` and `.fullscreen` only assign `result` and do not change.
3. Task 3's countdown: `captureSelfTimer()` becomes `func captureSelfTimer(intent: CaptureIntent = .standard) async` and passes `intent: intent` to both of its `runSelfTimer` calls; `runSelfTimer(_:)` becomes `private func runSelfTimer(_ target: CaptureTarget, intent: CaptureIntent) async`, and its closure calls `await captureAfterCountdown(target, intent: intent)`; `captureAfterCountdown(_:)` becomes `private func captureAfterCountdown(_ target: CaptureTarget, intent: CaptureIntent) async`, and its one `await save(result)` becomes `await save(result, intent: intent)`.
4. Hotkeys, the menu and the All-in-One toolbar call these with no arguments, so they pass `.standard`. Afterwards every `await save(` in `AppCoordinator.swift` passes `intent: intent` (`grep -n "await save(" TidyShot/App/AppCoordinator.swift`).

- [ ] **Step 11: Route URLs from the Apple event to the handler**

In `TidyShot/App/AppCoordinator.swift`:
1. After the `scrollCapture` property (line 33):
   ```swift
    /// `tidyshot://` commands (spec 2.9): held until `start()` has run, then parsed, gated and
    /// routed to the capture functions. It holds this coordinator weakly.
    @ObservationIgnored private lazy var urlCommands = URLCommandHandler(
        settings: settings, target: self, screens: { AppCoordinator.urlCommandScreens() },
        post: { [weak self] notice in
            self?.notifier.notifyError(notice.body, title: notice.title, subtitle: notice.subtitle)
        })
   ```
2. At the end of `start()` (after line 114, the permission window):
   ```swift
        // A URL that launched the app arrived before this point and waits in the handler.
        Task { await urlCommands.ready() }
   ```
3. After `showPermissionWindow()` (lines 117-119):
   ```swift
    /// A `tidyshot://` URL from `AppDelegate`'s Apple-event handler, with the sending app's name
    /// when it is known. The handler holds it until `start()` has run.
    func handleURL(_ url: URL, sender: String?) {
        Task { await urlCommands.handle(url, sender: sender) }
    }
   ```
4. Before `withCaptureLock` (line 1865):
   ```swift
    /// The displays in `NSScreen.screens` order with CoreGraphics frames, and the one under the
    /// pointer, for a URL command's rect.
    private static func urlCommandScreens() -> URLCommandHandler.Screens {
        let screens = NSScreen.screens
        let primaryHeight = screens.first?.frame.height ?? 0
        let displays = screens.map {
            URLCommandGeometry.Display(id: $0.displayID ?? 0,
                                       frame: Geometry.cgRect(fromAppKit: $0.frame, primaryHeight: primaryHeight))
        }
        return URLCommandHandler.Screens(displays: displays,
                                         pointerIndex: screens.firstIndex { $0.frame.contains(NSEvent.mouseLocation) })
    }
   ```
5. After the class's closing brace (line 1880), before `CopyImageError`:
   ```swift
/// The URL scheme's routes are the capture functions above, with their own signatures.
extension AppCoordinator: URLCommandTarget {}
   ```
   It compiles only if every capture function has the signature in Interfaces; a missing intent anywhere is a build error here.

`TidyShot/App/AppDelegate.swift`, after the `statusMenu` property (line 10):
```swift
    /// Installed before launch finishes, so a URL that launched the app reaches it (spec 2.9). It
    /// replaces AppKit's default handler, so SwiftUI's scene machinery never sees the URL.
    func applicationWillFinishLaunching(_ notification: Notification) {
        guard !Self.isRunningTests else { return }
        NSAppleEventManager.shared().setEventHandler(self, andSelector: #selector(handleGetURL(_:withReplyEvent:)),
                                                     forEventClass: AEEventClass(kInternetEventClass),
                                                     andEventID: AEEventID(kAEGetURL))
    }

    /// A `tidyshot://` URL from LaunchServices: `open`, Raycast, Keyboard Maestro, Shortcuts, a browser.
    @objc private func handleGetURL(_ event: NSAppleEventDescriptor, withReplyEvent reply: NSAppleEventDescriptor) {
        guard let string = event.paramDescriptor(forKeyword: AEKeyword(keyDirectObject))?.stringValue,
              let url = URL(string: string) else {
            NSLog("%@", "A URL event without a readable URL was ignored")
            return
        }
        AppCoordinator.shared.handleURL(url, sender: Self.senderName(of: event))
    }

    /// The sending app's name: the event's `keySenderPIDAttr`, then the running application with
    /// that pid. Nil when the event carries no pid, or the process has gone or has no name.
    private static func senderName(of event: NSAppleEventDescriptor) -> String? {
        guard let pid = event.attributeDescriptor(forKeyword: AEKeyword(keySenderPIDAttr))?.int32Value, pid > 0 else {
            return nil
        }
        return NSRunningApplication(processIdentifier: pid)?.localizedName
    }
```
`applicationDidFinishLaunching` is unchanged: it calls `start()`, which ends by calling `ready()`.

- [ ] **Step 12: Register the scheme**

In `project.yml`, under the TidyShot target's `info: properties:`, after `NSHumanReadableCopyright` (line 47):
```yaml
        CFBundleURLTypes:
          - CFBundleURLName: io.tky.tidyshot
            CFBundleURLSchemes:
              - tidyshot
```
Run `xcodegen generate`. `TidyShot/Info.plist` now has, between `CFBundleShortVersionString` and `CFBundleVersion`:
```xml
	<key>CFBundleURLTypes</key>
	<array>
		<dict>
			<key>CFBundleURLName</key>
			<string>io.tky.tidyshot</string>
			<key>CFBundleURLSchemes</key>
			<array>
				<string>tidyshot</string>
			</array>
		</dict>
	</array>
```
Check: `git diff --stat -- TidyShot/TidyShot.entitlements` is empty (receiving URL events needs no entitlement), and `git diff TidyShot/Info.plist` shows only that block.

- [ ] **Step 13: Run the full suite**

Run:
```bash
xcodegen generate && xcodebuild test -project TidyShot.xcodeproj -scheme TidyShot -destination 'platform=macOS' -derivedDataPath .build 2>&1 | grep -E "Test run with|error:|TEST"
```
Expected: no `error:` lines, `** TEST SUCCEEDED **`, and `Test run with 802 tests in 95 suites passed`. This task adds 55 tests in 5 new suites: 21 in `URLCommandTests`, 7 in `URLCommandGeometryTests`, 6 in `URLCommandGateTests`, 8 in `CaptureIntentTests`, 11 in `URLCommandHandlerTests`, and 2 in `AppSettingsTests`. None is parameterized, so each counts once.

- [ ] **Step 14: Hand checks (Tim)**

For Tim; the implementer builds the Release configuration, lists these in its report and goes on to Step 15. Task 6's checklist repeats them.
```bash
xcodebuild -project TidyShot.xcodeproj -scheme TidyShot -configuration Release -derivedDataPath .build-rel build -quiet
plutil -p .build-rel/Build/Products/Release/TidyShot.app/Contents/Info.plist | grep -A6 CFBundleURLTypes
codesign -d --entitlements - .build-rel/Build/Products/Release/TidyShot.app 2>/dev/null | grep -c "com.apple.security"
```
Expected: the URL type with `tidyshot`; 4 entitlements, as before.

Tim, with only the Release build registered (probe 4): quit TidyShot, then
```bash
LSR=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
$LSR -dump | grep -i -B2 -A8 "tidyshot" | grep -E "path:|claimed schemes|bindings" | sort -u
$LSR -u .build/Build/Products/Debug/TidyShot.app      # each stale path the dump lists
$LSR -f .build-rel/Build/Products/Release/TidyShot.app
```
- Cold launch: `open 'tidyshot://capture-area?action=save'` with TidyShot not running starts `.build-rel`'s app (Activity Monitor > the process's Open Files and Ports shows the path) and opens the selection overlay once it has started; the capture is saved and the image copied. No Settings window opens.
- Each command from Terminal, URL commands on and the silent toggle on: `capture-area` (select, saved by the General action), `capture-area?x=100&y=100&width=400&height=300` (captured at once, 100 pt from the left and bottom edges of the display under the pointer; `sips -g pixelWidth` reads 400 times the scale), the same with `&display=2` on the second display, `capture-window`, `capture-fullscreen`, `capture-previous-area` (the last area again), `all-in-one` (preselects the last area) and `all-in-one?x=0&y=0&width=500&height=400` (preselects that rect at the bottom-left), `self-timer`, `capture-scrolling` and `scrolling-capture?x=0&y=0&width=600&height=800` (the session panel opens on that rect without a selection; nothing is captured until Start), `restore-recently-closed`.
- Actions on `capture-window`: `action=upload` with the General action `Save and copy image` uploads and copies the URL; under `Upload only` it uploads without a local file. `action=save` saves and copies the image under `Upload only`. `action=copy`: the clipboard holds the image (Preview > New from Clipboard), no file in the save folder, no card, no Recent Captures row, no upload, the shutter sound, and `Image copied` with `From Terminal` (or whatever the sender reads) and the pixel size. `action=annotate` opens the editor on the new capture; `action=pin` opens a pin and keeps the card.
- The silent gate, off (default): `open 'tidyshot://capture-fullscreen?action=copy'` captures nothing, the clipboard is unchanged, and `TidyShot URL command` reads `capture-fullscreen from <sender> captures without a selection. Allow it in Settings > General > URL commands.` with the subtitle `From <sender>`. The same for `capture-previous-area` and `capture-area?x=0&y=0&width=100&height=100`. `capture-area` without a rect, `all-in-one?x=…`, `self-timer` and `capture-scrolling?x=…` still open their selection or panel. Write down the sender each source shows (Terminal's `open`, Raycast, Keyboard Maestro, Safari, Chrome); an unknown sender gives no subtitle and no ` from …`.
- The master toggle off: every URL above, and `tidyshot://nonsense`, posts `URL commands are off. Turn them on in Settings > General.` and does nothing. The second toggle is greyed while the first is off.
- Hostile input, toggles on: `tidyshot://capture-area?x=1e3&y=0&width=10&height=10`, `…width=nan…`, `…width=-5…`, `…x=99999999999999999999…`, `tidyshot://capture-area?action=upload&action=copy`, `tidyshot://capture-area?action=%25@%25n%25s` and `tidyshot://capture-area?action=%E2%80%AEdaolpu` each post the matching error (the last shows `daolpu` with no reversed text) and capture nothing; nothing crashes, and `log show --last 2m --predicate 'process == "TidyShot"' | grep "URL command"` shows each URL with `%@` and `%n` as plain text. `tidyshot://capture-area?display=3` with two displays opens the normal selection (display is used only with a rect); `…width=10&height=10&display=3` posts `There is no display 3.`
- While a capture runs (a selection open, a self-timer counting, a scrolling session before and after Start): `open 'tidyshot://capture-fullscreen'` and `open 'tidyshot://capture-scrolling'` do nothing and post nothing; the session does not start or finish. `restore-recently-closed` still brings back a card.
- From Raycast (a Quicklink to `tidyshot://capture-area?action=upload`) and Keyboard Maestro (an Open URL action for `tidyshot://capture-fullscreen?action=copy`, silent toggle on): both run. From a browser: a page with `<a href="tidyshot://capture-fullscreen?action=copy">` asks "Open TidyShot?"; allowing it with the silent toggle off posts the refusal naming the browser.
- The General tab shows the `URL commands` section with both toggles and the caption, the first on and the second off on a fresh install (`defaults delete io.tky.tidyshot urlCommandsEnabled; defaults delete io.tky.tidyshot urlCommandsAllowSilent`, then relaunch).
- Hotkeys and menu items behave as before this task (the General action, no extra notification).

- [ ] **Step 15: Commit**

```bash
git add TidyShot/URLScheme/URLCommand.swift TidyShot/URLScheme/URLCommandGeometry.swift TidyShot/URLScheme/URLCommandGate.swift TidyShot/URLScheme/URLCommandHandler.swift TidyShot/Capture/CaptureIntent.swift TidyShot/Settings/AppSettings.swift TidyShot/Settings/GeneralSettingsView.swift TidyShot/Output/Notifier.swift TidyShot/App/AppDelegate.swift TidyShot/App/AppCoordinator.swift project.yml TidyShot/Info.plist TidyShotTests/URLCommandTests.swift TidyShotTests/URLCommandGeometryTests.swift TidyShotTests/URLCommandGateTests.swift TidyShotTests/CaptureIntentTests.swift TidyShotTests/URLCommandHandlerTests.swift TidyShotTests/AppSettingsTests.swift
git commit -m "feat: tidyshot:// URL scheme with a gate for silent captures"
```
Check `git status` is clean afterwards (`TidyShot.xcodeproj` is ignored).

### Task 6: 6b checklist, README and spec close-out

**Files:**
- Create: `docs/testing/phase-6b-manual-checklist.md`
- Modify: `README.md` (the `## Default shortcuts` table, lines 52-59; four new sections before `## Upload`, line 136; one line after the Phase 6a entry in `## Documents`, line 287)
- Modify: `docs/superpowers/specs/2026-10-19-tidyshot-screenshot-design.md` (the 2.1 rows at lines 26, 28, 36, 42 and 45; the 2.8 Deferred paragraph, line 595; section 2.9: the Scope paragraph at line 621, the 6b text at lines 656-689, the Settings summary at lines 691-698, the places the plan header's points and the tasks' "Settled beyond 2.9" lists change, and a "Phase 6b (built)" paragraph after the "Phase 6a (built)" paragraphs, which end at line 786; section 5's Settings bullet, line 840; the Phase 6 block of section 6, line 906)
- Modify, only when Step 4 finds a divergence: `docs/superpowers/plans/2026-10-21-phase-6b-all-in-one-timer-pin-url.md` (the "Test totals" table)
- Test: none (documentation only; no new tests)

Line numbers are from `main` at 4c67c04; Tasks 1 to 5 change no line of these three documents, so they hold.

**Interfaces:**
- Consumes (behaviour, names and strings the checklist, README and spec describe; each comes from Tasks 1 to 5 or `main`):
  - Task 1: `SelectionAdjust` (`handle(at:rect:tolerance:)`, `resized`, `moved`, `nudged`, `sized`, `restored`, minimum side 4 pt), `AllInOneToolbarPlacement.frame(toolbarSize:selection:screenBounds:)` (below, above, inside, clamped), `AllInOneChoice`, `AllInOneAction`, `AllInOneLock`.
  - Task 2: `SelectionMode.allInOne`, the handles, move, resize, arrows, Return and double-click in `SelectionView`, `AllInOneToolbar` (W and H fields, `lock` / `lock.open` with help `Lock aspect ratio`, Capture, Window, Fullscreen, Scrolling, Timer, Cancel with 2.9's help strings), `SelectionController.selectAllInOne(content:freeze:preselect:)`, `AppCoordinator.captureAllInOne(intent:preselect:)` (Fullscreen dismisses the overlay first and follows Show cursor), `KeyboardShortcuts.Name.allInOne` (⌃⇧1), the menu item `All-in-One  ⌃⇧1`, `All-in-One:` in Settings > Shortcuts, `AppSettings.allInOneAspectLock` (default false).
  - Task 3: `SelectionMode.selfTimer`, `SelfTimerController` and `SelfTimerPanel` (96 pt square, 48 pt monospaced digits, `Esc to cancel`, 2 pt dashed frame, 100 ms wait), `AppCoordinator.captureSelfTimer(intent:)` (TidyShot deactivates during the countdown; at zero the display or window is looked up again, with `The window is no longer on screen.` and `The display is no longer connected.` titled `Self-timer`), `KeyboardShortcuts.Name.selfTimer` (no default), `.cancelScrollingCapture` renamed in code to `.cancelCapture` with the stored name `cancelScrollingCapture`, `AppSettings.selfTimerSeconds` (3, 5 or 10; default 5), the Capture tab's `Self-timer` picker, the menu item `Self-Timer`, All-in-One's Timer button.
  - Task 4: `PinGeometry`, `PinController`, `PinPanel`, `PinView`, `ThumbnailMaker.scaled(_:maxSide:)` (the downsample, no top crop), `AppCoordinator.pin(recordID:) async` (a second Pin brings the pin forward; `latestCaptureArea` places it) and `loadImage(for:)`, the card's Pin button (`pin`, help `Pin to screen`) and `Pin to Screen` menu item, the pin's keys and context menu (`Copy Image`, `Save As…`, `Annotate`, `Opacity` with `100%`, `90%`, `75%`, `50%`, `25%`, `Actual Size`, `Lock`, `Close`), `Unlock Pinned Screenshots` and `Close Pinned Screenshots` in the status menu, delete closing pins.
  - Task 5: the `tidyshot://` scheme (`CFBundleURLTypes` in `project.yml` and `TidyShot/Info.plist`), the eight commands and the `scrolling-capture` alias, `action`, `x`, `y`, `width`, `height`, `display`, CleanShot's bottom-left coordinates, `URLCommandGate` (`Allow URL commands (tidyshot://)` on by default, `Allow URL commands that capture without a selection` off by default, the three silent commands), the notifications titled `TidyShot URL command` with `From <sender>` as subtitle, the error strings, `action=copy`'s `Image copied`, the queue before start (8), dropping while a capture runs, `AppDelegate`'s `kAEGetURL` handler with `keySenderPIDAttr`, and Task 5's "Settled beyond 2.9" list.
  - `main`, unchanged: the Phase 6a checklist's shape (`docs/testing/phase-6a-manual-checklist.md`), the README sections, the research notes `docs/superpowers/research/phase-6-research.md` (probe 4, scheme ownership).
- Produces: documentation only. Nothing depends on it.

Three points to follow here:
- Every GUI check is Tim's (plan header). Probe 4 of the research notes (which build owns the scheme) is a checklist item, as are the sender names each source produces. This task writes the checklist and the documents, builds the Release app, and does not run a GUI check or wait for one.
- 2.9 is amended where the build differs from it: the plan header's list of 6b decisions (points 1 to 12, which gather everything Tasks 1 to 5 settled beyond 2.9 or correct in it; Task 5's "Settled beyond 2.9" paragraph is points 8 to 12 in detail), and anything Step 1 finds. The 6a text and the "Phase 6a (built)" paragraph are not touched, except the Scope paragraph's branch sentence and the Settings summary, which cover both.
- A divergence that looks like a bug rather than a decision is reported, not documented away.

- [ ] **Step 1: Read the finished code the documents describe**

The checklist, the README and the spec must match the build, not the plan. Run:
```bash
ls TidyShot/Selection TidyShot/SelfTimer TidyShot/Pin TidyShot/URLScheme TidyShot/Capture
git diff --name-only --diff-filter=A 4c67c04...HEAD -- TidyShot TidyShotTests | sort
grep -rn "static let\|minSide\|tolerance" TidyShot/Selection/SelectionAdjust.swift TidyShot/Pin/PinGeometry.swift TidyShot/SelfTimer/*.swift TidyShot/URLScheme/*.swift | cut -c1-170
grep -rn "allInOneAspectLock\|selfTimerSeconds\|urlCommandsEnabled\|urlCommandsAllowSilent" TidyShot/Settings/AppSettings.swift | cut -c1-170
grep -rn "allInOne\|selfTimer\|cancelCapture\|cancelScrollingCapture" TidyShot/App/Shortcuts.swift
grep -n "addItem" TidyShot/App/StatusMenuController.swift | cut -c1-170
grep -rn "Recorder(" TidyShot/Settings/ShortcutsSettingsView.swift
git diff 4c67c04 --stat -- TidyShot/TidyShot.entitlements
git diff 4c67c04 -- project.yml
while IFS= read -r s; do grep -rqF -- "$s" TidyShot || echo "MISSING: $s"; done <<'EOF'
All-in-One
All-in-One:
Lock aspect ratio
Capture area (Return)
Capture the window with transparent corners
Capture this display
Scrolling capture of this area
Capture this area after
Cancel (Escape)
Self-Timer
Self-timer:
Self-timer
3 seconds
5 seconds
10 seconds
Esc to cancel
Pin to screen
Pin to Screen
Opacity
Actual Size
Unlock Pinned Screenshots
Close Pinned Screenshots
URL commands
Allow URL commands (tidyshot://)
Allow URL commands that capture without a selection
capture-fullscreen, capture-previous-area and capture-area with x, y, width and height capture at once.
URL commands are off. Turn them on in Settings > General.
captures without a selection. Allow it in Settings > General > URL commands.
TidyShot URL command
Unknown command “
Unknown action “
Use upload, save, copy, annotate or pin.
x, y, width and height must be given together, as numbers, with width and height above 0.
There is no display
is given more than once.
The area leaves less than a point on display
Image copied
Select an area at least 100 points tall.
The window is no longer on screen.
The display is no longer connected.
Pinning the capture…
Could not pin the capture
The capture is too large to pin.
EOF
```
Expected: the files Tasks 1 to 5 list; the constants of 2.9 and Task 5 (All-in-One minimum side 4 pt, nudges 1 and 10 pt; self-timer 3, 5 and 10 s, default 5, a 96 pt panel, 48 pt digits, a 2 pt dashed frame, 100 ms; pin minimum side 40 pt, opacity 10 % to 100 % in steps of 5 %, zoom 10 %, 8,192 px downsample, 80 % fit; URL numbers at most 16 characters and 100,000 pt, display 1 to 99, messages cut at 40 characters, a queue of 8); the four new keys with defaults `false`, `5`, `true`, `false`; `allInOne` with ⌃⇧1, `selfTimer` with none, `cancelCapture` stored as `cancelScrollingCapture`; the menu order of 2.9's "Status menu after Phase 6"; no `MISSING:` line (a string split over two lines in code is checked by its first half); an empty entitlements diff; a `project.yml` diff that adds only `CFBundleURLTypes`. Where the code differs from the wording in Step 2, the README text of Step 3 or 2.9, write the code's behaviour in the documents and list each change in the report. A `MISSING:` string, a constant or an entitlement change that looks like a bug rather than a decision is not documented away: stop and report it. Do not change code.

- [ ] **Step 2: Write the manual checklist**

`docs/testing/phase-6b-manual-checklist.md`:
````markdown
# Phase 6b manual test checklist

Run after any change to All-in-One (`SelectionAdjust`, `AllInOneToolbar`, the All-in-One mode of
`SelectionView` and `SelectionController`), `TidyShot/SelfTimer/`, `TidyShot/Pin/`,
`TidyShot/URLScheme/`, `AppDelegate`'s URL handler, or the capture functions of `AppCoordinator`.
Automated tests cover the selection adjust geometry, the toolbar placement, the self-timer countdown,
the pin geometry, the URL parser, the URL rect geometry, the gate, the handler's queue and routing,
the capture intent, the new settings keys and the shortcuts; everything here needs real windows,
real displays, real senders and eyes. The Phase 6a checklist still covers the overlay, drag-out,
freeze and Capture Previous Area, the 4a and 4b checklists the editor and the Phase 5 checklist the
scrolling session; run them too after a change to those paths.

Setup: a fresh **Release** build (`xcodebuild -project TidyShot.xcodeproj -scheme TidyShot
-configuration Release -derivedDataPath .build-rel build`), Screen Recording granted, save folder
set to Desktop, a working destination saved in Settings > Upload, "Show notification" on in
Settings > General, "Show Quick Access overlay after capture" on in Settings > Overlay, a second
display if you have one (ideally at a different scale, arranged above or to the left of the main
one), Raycast and Keyboard Maestro if you use them (skip their rows otherwise), and the 65,536 px
capture of the Phase 5 checklist still in Recent Captures. The 6a test pages in `~/Desktop/p6` (make
them as `docs/testing/phase-6a-manual-checklist.md` says if they are gone). Capture only made-up
data: a capture may be uploaded and the link may be shared. Note how the build is signed
(`Config/Local.xcconfig`).

Make the link page and a shell helper once.
```bash
mkdir -p ~/Desktop/p6b && cd ~/Desktop/p6b
cat > links.html <<'HTML'
<!doctype html><meta charset="utf-8"><title>TidyShot links</title>
<style>body{font:18px -apple-system,sans-serif;margin:40px}a{display:block;margin:10px 0}</style>
<a href="tidyshot://capture-area?action=upload">capture-area, upload (needs your drag)</a>
<a href="tidyshot://capture-fullscreen?action=copy">capture-fullscreen, copy (silent)</a>
<a href="tidyshot://capture-area?x=0&amp;y=0&amp;width=300&amp;height=200&amp;action=copy">capture-area with a rect, copy (silent)</a>
<a href="tidyshot://restore-recently-closed">restore-recently-closed</a>
HTML
t() { open "tidyshot://$1"; }   # in the shell you test from: t 'capture-area?action=save'
```
`links.html` opens with `open -a Safari ~/Desktop/p6b/links.html` (Chrome the same way). `t` runs a
command from Terminal. The log of URL commands is
`log show --last 5m --predicate 'process == "TidyShot"' | grep "URL command"`. Settings are read
with `defaults read io.tky.tidyshot <key>`.

## Settings and strings
- [ ] Settings > General ends with a `URL commands` section: `Allow URL commands (tidyshot://)` (on), `Allow URL commands that capture without a selection` (off, greyed while the first is off), and the caption `capture-fullscreen, capture-previous-area and capture-area with x, y, width and height capture at once. Any app on this Mac, and any web page you let open TidyShot, can send them.` (Fresh values: `for k in urlCommandsEnabled urlCommandsAllowSilent allInOneAspectLock selfTimerSeconds; do defaults delete io.tky.tidyshot $k; done`, then relaunch.)
- [ ] Settings > Shortcuts lists, after the four existing recorders, `All-in-One:` (⌃⇧1), `Capture previous area:` (⌃⇧6), `Self-timer:` (empty) and `Restore closed overlay:` (empty). Record a combination for `Self-timer:` for the Self-Timer section and clear it at the end. Change `All-in-One:`, confirm the new keys work and ⌃⇧1 does not, then reset it.
- [ ] Settings > Capture has a `Self-timer` picker with `3 seconds`, `5 seconds` (selected) and `10 seconds`, after the three toggles.
- [ ] The menu bar menu reads `All-in-One  ⌃⇧1`, `Capture Area  ⌃⇧4`, `Capture Window  ⌃⇧2`, `Capture Fullscreen  ⌃⇧3`, `Capture Scrolling  ⌃⇧5`, `Capture Previous Area  ⌃⇧6`, `Self-Timer`; a separator; Recent Captures, `Restore Closed Overlay`, Retry Failed Uploads (only after a failure), Reveal Last Capture; a separator; `Unlock Pinned Screenshots` and `Close Pinned Screenshots` only when they apply; Settings…, Quit TidyShot. Every capture item is disabled while a capture, a countdown or a scrolling session runs.
- [ ] Settings persist: set the aspect lock on (All-in-One toolbar), the timer to 10 seconds, and both URL toggles the other way, quit and reopen: `defaults read io.tky.tidyshot <key>` reads `1`, `10`, `0`, `1` for `allInOneAspectLock`, `selfTimerSeconds`, `urlCommandsEnabled`, `urlCommandsAllowSilent`, and the panes show the same. Set them back.

## All-in-One
- [ ] No stored area (`defaults delete io.tky.tidyshot lastAreaRect`, relaunch): ⌃⇧1 opens like Capture Scrolling's selection: crosshair, loupe, and the window under the pointer highlighted.
- [ ] Drag a rectangle: eight handles appear and the toolbar sits centred under it, reading left to right `W` and `H` fields, the lock, a separator, Capture, Window (greyed), Fullscreen, Scrolling, Timer, Cancel. Each button's tooltip is 2.9's: `Lock aspect ratio`, `Capture area (Return)`, `Capture the window with transparent corners`, `Capture this display`, `Scrolling capture of this area`, `Capture this area after 5 seconds`, `Cancel (Escape)`.
- [ ] Click a window without dragging: the rect is the window's frame (clipped to its display) and Window is enabled; resizing, moving or nudging it keeps Window enabled. Drag a new rect: Window is greyed again. With a rect showing, click (no drag) outside it on another window: that window's frame becomes the rect; click outside on the bare desktop: the rect stays.
- [ ] Drag each of the eight handles: the rect resizes only that handle's sides; it never flips, never gets smaller than 4 pt on a side and never leaves its display. Drag inside: it moves, clamped at every edge. Drag outside: a new rect starts.
- [ ] The cursor is the resize cursor on each handle, an open hand inside (closed while moving), an arrow over the toolbar and the crosshair elsewhere. While a drag, resize or move runs the size label shows and the toolbar hides; it comes back at mouse-up.
- [ ] Arrow keys move the rect 1 pt, Shift-arrows 10 pt, clamped at the edges; the W and H fields keep their values.
- [ ] Type 640 into `W` and press Return: the width becomes 640, growing from the top-left corner, clamped at the display edge; nothing is captured, and a second Return captures. A value larger than the room moves the rect inside the display. The same for `H`. Tab moves between the two fields.
- [ ] Lock on (`lock` shown): a corner or edge drag keeps the ratio the rect had when the lock was turned on; typing W changes H and the other way. Lock off (`lock.open`) frees it. The lock is remembered across launches.
- [ ] Toolbar placement: a rect near the bottom of the display puts the toolbar above it; a rect that fills the display puts it inside its bottom edge; a rect at the left or right edge keeps the toolbar on screen; a rect at the top of a notched display never puts it under the notch or the menu bar.
- [ ] Capture (button, Return with no field editing, or a double-click inside): the area is saved by the after-capture action, the card appears, and ⌃⇧6 captures the same area again. The toolbar, handles and dimming are not in the image.
- [ ] Window: the clicked window with transparent corners (and the shadow, when `Include window shadow` is on). Fullscreen: the overlay goes first, then the rect's display is captured with no dimming, handles, toolbar or Quick Access card in it. Scrolling: the scrolling panel opens on the rect; a rect under 100 pt tall is refused with `Select an area at least 100 points tall.` Timer: the self-timer countdown runs on the rect, then captures it.
- [ ] Cancel and Escape (also with a field focused but not editing) close the overlay with nothing captured. While a field is being edited, Return applies the value and Escape reverts it and leaves the field; neither captures or cancels, and a second Escape cancels. ⌘-Tab to another app and back: the overlay is still up (focus loss does not cancel, as in the other modes) and Escape cancels it.
- [ ] A stored area on a connected display: ⌃⇧1 opens with it selected and adjustable. Store an area on the second display, unplug it, press ⌃⇧1: it opens with no rect.
- [ ] Freeze on: the All-in-One overlay shows the frozen screen (open Safari's File menu first) and Capture cuts from it; Window, Fullscreen, Scrolling and Timer capture live.
- [ ] Show cursor on, freeze off: the All-in-One Capture and Window captures have no pointer and no crosshair; with freeze on the Capture pointer is where it was when ⌃⇧1 was pressed. Fullscreen shows the pointer as an arrow, never the crosshair.
- [ ] Two displays: the rect and the toolbar stay on the display the rect started on. Draw a rect on one display, then drag on the other: the selection moves there and the first display loses its rect and toolbar; Return captures on the display holding the rect.
- [ ] All-in-One captures behave like any other in upload-only mode, in the Quick Access stack and in Recent Captures.

## Self-Timer
- [ ] Menu `Self-Timer` (or its recorded shortcut): the overlay shows the crosshair, the loupe and the window highlight. Drag an area: the overlay goes, a 96 pt rounded square appears centred on the area with `5` in large monospaced digits and `Esc to cancel` under it, and a dashed frame marks the area. It counts 5, 4, 3, 2, 1, once a second; at zero both disappear and the capture is saved. Neither is in the image, nor is a Quick Access card. Escape in the selection overlay, before the countdown, still cancels the selection.
- [ ] Click a window instead: the countdown centres on the window and the result is a window capture with transparent corners. Move the window during the countdown: the capture follows it. Close it before zero: `The window is no longer on screen.` titled `Self-timer`, and no capture. Start a countdown on the second display and unplug it before zero: `The display is no longer connected.`, no capture.
- [ ] A menu: start a timer over Safari's menu bar area, then open the File menu during the countdown and hold it open: the image contains the open menu. The same with a tooltip (`~/Desktop/p6/freeze.html`). During the countdown the app you clicked before is frontmost (its name in the menu bar), and a menu opened from the keyboard there works: TidyShot gave up activation.
- [ ] The countdown panel and frame are click-through: clicking under them reaches the app beneath.
- [ ] Escape, with Safari frontmost, cancels: both panels go and nothing is captured. After that Escape works normally in Safari (it is not swallowed). Escape still cancels a scrolling session (Phase 5).
- [ ] While the countdown runs, ⌃⇧4, the Self-Timer shortcut and the other shortcuts do nothing and the menu's capture items are disabled; the countdown is not disturbed.
- [ ] A rect near the top-right corner of the screen: the badge stays fully on screen. On a second display the badge and the frame are on that display.
- [ ] `3 seconds` and `10 seconds` in Settings > Capture count from 3 and 10. All-in-One's Timer button uses the same setting, and its tooltip follows it.
- [ ] Show cursor on: the pointer is in the self-timer capture where it is at zero. Freeze on: ignored, the capture is live.
- [ ] A self-timer area becomes the previous area (⌃⇧6 captures it again); a window does not.

## Pin to screen
- [ ] A card's right column is Annotate, Pin (`pin`, help `Pin to screen`), Delete; the context menu has `Pin to Screen` after `Annotate`. Pin an area capture: a borderless panel with a hairline border shows the image at its point size exactly over the spot it was captured from. The card stays, and the keyboard stays with the app you were typing in.
- [ ] Pin a window or fullscreen capture: centred on the pointer's screen, scaled down to fit 80 % of the visible frame when larger. Pin an older card in the stack: centred on the pointer's screen. Pin the same capture twice: the second click brings the first pin forward, no second pin opens. Pin from a restored card and from an upload-only capture after its upload: it loads from the file, the drag copy or the bucket, with `Pinning the capture…` posted while it downloads.
- [ ] A pinned window capture keeps its transparent corners, and the pin's shadow follows them.
- [ ] The pin floats above other apps' windows, on every Space, and over a full-screen app. TidyShot does not become the active app when you click the pin (the menu bar keeps the other app's name).
- [ ] Drag anywhere to move. Drag an edge or corner: it resizes with the aspect ratio fixed, never below 40 pt on a side.
- [ ] Click the pin, then: arrows move it 1 pt, Shift-arrows 10 pt; ⌘+ and ⌘- zoom by 10 % about the centre; ⌘0 returns to actual size; ⌘C copies the image (Preview > New from Clipboard matches the capture's pixel size); Escape and ⌘W close it. Option-scroll changes opacity in steps of 5 %, never below 10 % or above 100 %.
- [ ] Right-click: `Copy Image`, `Save As…`, `Annotate`, `Opacity` (`100%`, `90%`, `75%`, `50%`, `25%`, the current one checked), `Actual Size`, `Lock`, a separator, `Close`. Each works; Save As… is the card's (the same panel and suggestion).
- [ ] `Lock`: the border goes and clicks pass through to the app beneath. The status menu then lists `Unlock Pinned Screenshots` and `Close Pinned Screenshots` before Settings…; Unlock makes every pin clickable again; Close closes them all. With no pins neither item shows; with only unlocked pins only `Close Pinned Screenshots` shows.
- [ ] Pins are in captures: ⌃⇧3 with a pin showing contains the pin. A scrolling capture over a pin leaves it out.
- [ ] Delete the capture (card, Recent Captures): its pins close. Quit with pins showing: they go; relaunch: no pins.
- [ ] Pin the 65,536 px capture: it shows as a whole fitted strip (not cut to its top), within a second or two; ⌘0 shows its point size; Activity Monitor's memory for TidyShot grows by tens of megabytes, not gigabytes.
- [ ] On a 2x display the pin at actual size is as sharp as the capture; zoomed out it stays smooth (trilinear). A pin dragged to the second display keeps its point size.

## URL scheme: which build owns it (probe 4)
- [ ] Quit TidyShot. List every registered copy: `LSR=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister; $LSR -dump | grep -i -B2 -A8 tidyshot | grep -E "path:|claimed schemes" | sort -u`. Write down the paths. Unregister each stale one (`$LSR -u <path>`, the Debug build in `.build`, DerivedData, old copies), register the Release build (`$LSR -f .build-rel/Build/Products/Release/TidyShot.app`), and list again: one path claims `tidyshot:`.
- [ ] `plutil -p .build-rel/Build/Products/Release/TidyShot.app/Contents/Info.plist | grep -A6 CFBundleURLTypes` shows `io.tky.tidyshot` and `tidyshot`; `codesign -d --entitlements - .build-rel/Build/Products/Release/TidyShot.app` shows the same four entitlements as before this phase.
- [ ] Cold launch: with TidyShot not running, `t 'capture-area?action=save'` starts the Release app (Activity Monitor > TidyShot > Open Files and Ports shows `.build-rel`) and, once it has started, opens the selection; the capture is saved. No Settings window and no other window opens.

## URL scheme: commands
URL commands on, the silent toggle on for this section.
- [ ] `t capture-area`: the selection opens; the capture follows the after-capture action. `t capture-window`: window mode. `t capture-fullscreen`: the display under the pointer, at once. `t capture-previous-area`: the last area again, at once.
- [ ] `t all-in-one`: All-in-One with the last area preselected. `t 'all-in-one?x=0&y=0&width=500&height=400'`: All-in-One with that rect preselected at the bottom-left of the display under the pointer, adjustable; Escape leaves the stored previous area unchanged.
- [ ] `t self-timer`: the self-timer selection, then the countdown.
- [ ] `t capture-scrolling`: the scrolling selection. `t 'scrolling-capture?x=0&y=0&width=600&height=800'`: no selection; the frame and panel open on that rect, TidyShot is active so Return is Start, and nothing is captured until Start. A rect under 100 pt tall posts `Select an area at least 100 points tall.`
- [ ] `t restore-recently-closed`: the last closed card comes back, as the menu item does.
- [ ] The path forms work too: `open 'tidyshot:capture-window'` and `open 'tidyshot:///capture-window'`; and `t CAPTURE-WINDOW`.
- [ ] Hotkeys and menu items behave as before: the after-capture action, no extra notification, no subtitle.

## URL scheme: actions
Use `capture-window` (click a window each time).
- [ ] No `action`: the after-capture action in General.
- [ ] `action=upload` with General set to `Save and copy image`: saved, uploaded, URL on the clipboard. With `Upload only, keep no local file`: uploaded with no file in the save folder.
- [ ] `action=save` under `Upload only`: saved in the save folder, the image copied (with General's copy toggle on), no upload.
- [ ] `action=copy`: the image is on the clipboard (Preview > New from Clipboard), and nothing else: no file in the save folder or `pending`, no card, no Recent Captures row, no upload; the shutter sound plays (with Play sound on); `Image copied` shows the pixel size with the subtitle `From <sender>`. With Show notification off, no notification. The newest card's Annotate still opens its own capture.
- [ ] `action=annotate`: the after-capture action runs, then the editor opens on the new capture and its card closes. `action=pin`: the action runs, then a pin opens and the card stays.
- [ ] `action=UPLOAD` works like `upload`. `action=print` posts `Unknown action “print”. Use upload, save, copy, annotate or pin.`

## URL scheme: rect coordinates
Silent toggle on. Coordinates are points from the display's bottom-left corner (as in CleanShot).
- [ ] `t 'capture-area?x=0&y=0&width=300&height=200'` captures the bottom-left corner of the display under the pointer (the Dock's end or the desktop corner); `sips -g pixelWidth -g pixelHeight` reads 300 x 200 times the display's scale.
- [ ] With the display's size in points W x H (System Settings > Displays, "looks like"), `x=W-300&y=H-200&width=300&height=200` captures the top-right corner with the menu bar clock.
- [ ] `&display=1` captures on the main display whatever the pointer; `&display=2` on the second (`NSScreen.screens` order), also when it is above or to the left of the main one. `&display=3` with two displays posts `There is no display 3.`
- [ ] A rect running past the display edge is clipped to it (`x=-100&y=-100&width=400&height=300` gives 300 x 200). A rect fully off the display (`x=99999&y=0&width=10&height=10`) posts `The area leaves less than a point on display 1.`
- [ ] A URL rect becomes the previous area: ⌃⇧6 captures it again.
- [ ] Show cursor on: the pointer is in a URL rect capture when it lies inside the rect.

## URL scheme: security
- [ ] Silent toggle off (default): `t 'capture-fullscreen?action=copy'`, `t capture-previous-area` and `t 'capture-area?x=0&y=0&width=100&height=100&action=copy'` capture nothing and leave the clipboard as it was (copy some text first; `pbpaste` prints it before and after, and `osascript -e 'clipboard info'` lists no image type after). Each posts `TidyShot URL command` with `<command> from <sender> captures without a selection. Allow it in Settings > General > URL commands.` and the subtitle `From <sender>` (no ` from …` and no subtitle when the sender is unknown).
- [ ] Silent toggle off: `capture-area` without a rect, `capture-window`, `all-in-one` with and without a rect, `self-timer`, and `capture-scrolling` with and without a rect all still run, because each waits for your drag, click or Start.
- [ ] Master toggle off: every command above, `restore-recently-closed`, and `t nonsense` post `URL commands are off. Turn them on in Settings > General.` and do nothing.
- [ ] From Safari and Chrome, open `~/Desktop/p6b/links.html` and click each link: the browser asks whether to open TidyShot; after you allow it, the silent links are refused naming the browser, and the others run. Write down whether Chrome offers "Always allow".
- [ ] Raycast: a Quicklink to `tidyshot://capture-area?action=upload` runs. Keyboard Maestro: an Open URL action for `tidyshot://capture-fullscreen?action=copy` is refused with the toggle off and runs with it on. Shortcuts: an Open URLs action for `tidyshot://capture-window` runs.
- [ ] Fill in the sender each source produces (the notification's subtitle and the log line):

  | Source | Sender shown |
  |---|---|
  | Terminal (`open`) | |
  | Raycast | |
  | Keyboard Maestro | |
  | Shortcuts | |
  | Safari | |
  | Chrome | |

## URL scheme: hostile input
Both toggles on. Each line posts the error named and captures nothing; nothing crashes.
- [ ] `t 'capture-area?x=1e3&y=0&width=10&height=10'`, `width=nan`, `width=inf`, `width=0x10`, `width=+5`, `width=-5`, `width=0`, `x=99999999999999999999`, `x=100001`, and a missing `height`: `x, y, width and height must be given together, as numbers, with width and height above 0.`
- [ ] `t 'capture-area?action=upload&action=copy'` and `t 'capture-area?action=copy&ACTION=copy'`: `“action” is given more than once.`
- [ ] `t 'capture-fullscreen?action=upload%26action%3Dcopy'`: `Unknown action “upload&action=copy”. …`, not a copy. `t 'capture%2Dwindow'` runs Capture Window (percent-encoding is decoded first, and the gate sees the decoded command: `t 'capture%2Dfullscreen'` is refused with the silent toggle off).
- [ ] `t 'capture-area?action=%25@%25n%25s'`: `Unknown action “%@%n%s”. …`; the log shows `%@%n%s` as plain text. `t 'capture-area?action=%E2%80%AEdaolpu'`: the notification shows `daolpu` with no reversed text. A 200-character action is cut at 40 characters with `…`.
- [ ] `t 'capture-area?display=7'` with no rect opens the normal selection (display counts only with a rect); `t 'capture-area?display=abc'` posts `There is no display abc.`
- [ ] Unknown commands, including CleanShot's file-path ones: `t pin`, `t 'open-annotate?filepath=/etc/hosts'`, `t 'add-quick-access-overlay?filepath=/tmp/x.png'`, `t open-settings`: `Unknown command “…”.` No file is read (no sandbox prompt, nothing in the log about the path).
- [ ] Unknown parameters are ignored: `t 'capture-window?foo=1&filepath=/etc/hosts'` runs Capture Window.

## URL scheme: launch, queue and busy
- [ ] Cold launch with the silent toggle off: quit TidyShot, `t capture-fullscreen`: TidyShot starts, then posts the refusal; nothing is captured.
- [ ] While a selection is open (⌃⇧4, not released), while a self-timer counts, and during a scrolling session before and after Start: `t capture-fullscreen`, `t capture-area` and `t capture-scrolling` do nothing and post nothing (the log reads `dropped, a capture is running`); the scrolling session neither starts nor finishes. `t restore-recently-closed` still restores a card.
- [ ] `for i in 1 2 3; do t capture-window; done`: one window selection opens; the other two are dropped.

## VoiceOver
Turn VoiceOver on (⌘F5).
- [ ] In All-in-One, VO-arrow through the toolbar: the W and H fields, the lock and each button are read by name (their help text). Return and Escape still capture and cancel.
- [ ] A card's Pin button is read as `Pin to screen`. A pin's context-menu actions are listed in the VoiceOver actions menu.
- [ ] Turn VoiceOver off. Everything above behaves as before.

## Regression
- [ ] ⌃⇧2 to ⌃⇧6, the overlay, Save As…, drag-out, Restore Closed Overlay and Recent Captures behave as in the Phase 6a checklist's Regression section.
- [ ] Escape outside a capture, a countdown and a scrolling session reaches the frontmost app (Safari's find bar closes with Escape).
- [ ] Upload-only mode end to end through a URL command: `t 'capture-area?action=upload'`, select, URL on the clipboard, drag the card, pin it, Delete: the pin closes and nothing is left in `pending` or `Drag`.
- [ ] Quit TidyShot with pins, cards and a countdown showing: everything goes and nothing is left on screen.

## Probe results
Write these under probe 4 in `docs/superpowers/research/phase-6-research.md` and into the "Phase 6b (built)" paragraph of spec 2.9 (which lists them as still to be written down):
- Scheme ownership: the paths registered before cleaning, the one that owns `tidyshot:` after, and which bundle the cold launch started.
- The sender table above, and whether Chrome offered "Always allow".
- Anything that failed above, and timings and observations the items ask for (the 65,536 px pin's memory, All-in-One's Return and Escape with the fields).
````

- [ ] **Step 3: Update the README**

In `README.md`:

In the shortcuts table, before `| Capture area | ⌃⇧4 |` (line 54) add `| All-in-One | ⌃⇧1 |`, and after `| Capture previous area | ⌃⇧6 |` (line 58) add `| Self-timer | none; set one in Settings > Shortcuts |`.

Insert before `## Upload` (line 136) these four sections:
````markdown
## All-in-One

All-in-One (⌃⇧1) opens a selection that stays adjustable. Drag a rectangle, or click a window to
take its frame; then drag the handles to resize it, drag inside to move it, or nudge it with the
arrow keys (Shift for 10 points). The toolbar under the selection has width and height fields, an
aspect-ratio lock, and Capture, Window, Fullscreen, Scrolling, Timer and Cancel. Return or a
double-click inside captures the area; Escape cancels. It opens with your last area already
selected, when that is on a connected display.

## Self-timer

Self-Timer (in the menu; no default shortcut) lets you select an area or click a window, then counts
down 3, 5 or 10 seconds (Settings > Capture) before it captures, so you can open a menu or show a
tooltip first. Escape cancels from any app.

## Pin to screen

Pin a capture from its card (the pin button or the right-click menu) to keep a floating copy above
other windows, on every Space. Drag it to move it, drag an edge to resize it, and with the pin
clicked: arrow keys move it (Shift for 10 points), ⌘+ and ⌘- zoom, ⌘0 is actual size, ⌘C copies,
Escape or ⌘W closes, and Option-scroll changes the opacity. Its right-click menu has Copy Image,
Save As…, Annotate, Opacity, Actual Size, Lock and Close. A locked pin lets clicks through to the
window beneath; *Unlock Pinned Screenshots* in the menu bar menu makes pins clickable again. Pins
close when you quit, and deleting a capture closes its pins.

## URL scheme

Raycast, Keyboard Maestro, Shortcuts and scripts can drive TidyShot with `tidyshot://` URLs:

```bash
open 'tidyshot://capture-area?action=upload'
```

The names follow CleanShot X's, so a CleanShot macro works after changing `cleanshot://` to
`tidyshot://`.

| Command | What it does | Parameters |
|---|---|---|
| `capture-area` | Select an area; with a rectangle, capture it at once | `action`, `x`, `y`, `width`, `height`, `display` |
| `capture-window` | Click a window | `action` |
| `capture-fullscreen` | Capture the display under the pointer | `action` |
| `capture-previous-area` | Capture your last area again | `action` |
| `all-in-one` | All-in-One; a rectangle is preselected | `action`, `x`, `y`, `width`, `height`, `display` |
| `self-timer` | Select, then count down | `action` |
| `capture-scrolling` (or `scrolling-capture`) | Scrolling capture; a rectangle skips the selection, and the capture waits for Start | `action`, `x`, `y`, `width`, `height`, `display` |
| `restore-recently-closed` | Restore Closed Overlay | none |

`action` is `upload` (upload only when that is your after-capture setting, otherwise save, upload
and copy the URL), `save` (save and copy the image), `copy` (the image on the clipboard and nothing
else: no file, no history, no card, no upload), `annotate` (then open the editor) or `pin` (then pin
it). Without `action` the after-capture setting in Settings > General applies.

`x`, `y`, `width` and `height` are points from the bottom-left corner of the display, as in
CleanShot: all four or none, plain numbers such as `120` or `40.5`, width and height above 0. A
rectangle that runs off the display is clipped to it. `display` is 1 for the main display and 2, 3
and so on for the others in the order macOS lists them; without it, the display under the pointer.
Command and parameter names, and actions, may be in any case. Other parameters are ignored, and a
parameter given twice is an error.

**Security.** Any app on this Mac can open a `tidyshot://` URL, and a web page can once you let
your browser open TidyShot. Settings > General > URL commands has two switches. *Allow URL commands
(tidyshot://)* is on by default; off, every command is refused. *Allow URL commands that capture
without a selection* is off by default: it covers the three commands that capture without your drag
or click (`capture-fullscreen`, `capture-previous-area`, and `capture-area` with a rectangle), which
are otherwise refused with a notification naming the app that sent them. Turn it on only for macros
that need it (a Keyboard Maestro macro for a fullscreen shot, say): any app on the Mac can then take
a screenshot through TidyShot and read it from the clipboard. The name shown is what the sending app
calls itself. Every other command waits for your drag, click or Start, and commands never take a
file path.

Errors (an unknown command or action, a bad rectangle, a missing display, a parameter given twice)
appear as notifications titled *TidyShot URL command*. A command that arrives while a capture runs
is ignored. If `open tidyshot://…` starts an old build, more than one TidyShot.app is registered:
list them with
`/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -dump | grep -i tidyshot`
and remove the stale ones with `lsregister -u <path>`.
````

In `## Documents`, after the Phase 6a entry (line 287) add:
```markdown
- Phase 6b manual test checklist: `docs/testing/phase-6b-manual-checklist.md`
```

Then confirm no stale text remains:
```bash
grep -ni "limitation\|not yet\|coming\|later phase\|phase 6\|url scheme\|tidyshot://" README.md | cut -c1-140
```
Expected: the Documents entries, the new `## URL scheme` section, and nothing that says pins, All-in-One, the self-timer or the URL scheme are missing. If the build differs from the README text above (a key, a menu item, the queue, the case rule), write the code's behaviour.

- [ ] **Step 4: Run the full suite and check the totals table**

Run:
```bash
xcodegen generate && xcodebuild test -project TidyShot.xcodeproj -scheme TidyShot -destination 'platform=macOS' -derivedDataPath .build 2>&1 | grep -E "Test run with|error:|TEST"
```
Expected: no `error:` lines, `** TEST SUCCEEDED **`, and `Test run with 802 tests in 95 suites passed`. This task adds no tests, so that count must equal the Task 5 row of the "Test totals" table in the plan's header section.

Reconcile the table against the repo:
```bash
grep -rhE '^(@MainActor )?(nonisolated )?struct [A-Za-z0-9]+Tests\b' TidyShotTests | wc -l; grep -rhE '^\s*@Test' TidyShotTests | wc -l
grep -c '[{][{]' docs/superpowers/plans/2026-10-21-phase-6b-all-in-one-timer-pin-url.md
```
Expected: the first count is the suites and the second the tests in the Task 5 row (one `struct …Tests` per suite; Swift Testing counts a parameterized `@Test` once per argument in the run, so the run's count is the one to trust and the greps only help find which suites differ), and the last count is `0`, so no placeholder is left in the plan. The branch starts from `Test run with 686 tests in 85 suites passed`. If the run differs from the Task 5 row, a review fix added or removed tests. Find which with:
```bash
git log --oneline --stat 4c67c04..HEAD -- TidyShotTests
```
Leave the rows as written and add one line under the table: `Task 6 correction: <commit> <what changed>; the real run reads <the line>.` Change nothing else in the plan. If the run equals the row, change nothing.

Then check the new files against the task list:
```bash
git diff --name-only --diff-filter=A 4c67c04...HEAD -- TidyShot TidyShotTests | sort
git diff --name-only --diff-filter=A 4c67c04...HEAD -- TidyShot TidyShotTests | while read -r f; do grep -q "$(basename "$f")" docs/superpowers/plans/2026-10-21-phase-6b-all-in-one-timer-pin-url.md || echo "NOT IN PLAN: $f"; done
for f in Selection/SelectionAdjust Selection/AllInOneToolbarPlacement Selection/AllInOneChoice Selection/AllInOneToolbar SelfTimer/SelfTimerController SelfTimer/SelfTimerPanel Pin/PinGeometry Pin/PinController Pin/PinPanel Pin/PinView URLScheme/URLCommand URLScheme/URLCommandGeometry URLScheme/URLCommandGate URLScheme/URLCommandHandler Capture/CaptureIntent; do test -f TidyShot/$f.swift || echo "NO FILE: $f"; done
for t in SelectionAdjustTests AllInOneToolbarPlacementTests AllInOneChoiceTests SelfTimerTests PinGeometryTests URLCommandTests URLCommandGeometryTests URLCommandGateTests CaptureIntentTests URLCommandHandlerTests SelectionOutcomeTests AppSettingsTests ShortcutsTests ThumbnailMakerTests; do test -f TidyShotTests/$t.swift || echo "NO TEST: $t"; done
grep -rln "filepath" TidyShot --include=*.swift && echo "UNEXPECTED: a filepath parameter (2.9 defers it)"
```
Expected: the files Tasks 1 to 5 add; no `NOT IN PLAN:` line (a stray file means a review fix added it, so say which); no `NO FILE:` or `NO TEST:` line; no `UNEXPECTED:` line. `SelectionOutcomeTests`, `AppSettingsTests`, `ShortcutsTests` and `ThumbnailMakerTests` exist on `main` and are modified, not added. A file a task section named differently is reconciled here against that section, not in the code.

- [ ] **Step 5: Build the Release app and hand the checklist to Tim**

Run:
```bash
xcodebuild -project TidyShot.xcodeproj -scheme TidyShot -configuration Release -derivedDataPath .build-rel build -quiet && echo RELEASE_BUILT
plutil -p .build-rel/Build/Products/Release/TidyShot.app/Contents/Info.plist | grep -A6 CFBundleURLTypes
```
Expected: `RELEASE_BUILT`, and the URL type with `io.tky.tidyshot` and `tidyshot`. Do not open the app, run `open tidyshot://…`, call `lsregister` or work through the checklist: every item of `docs/testing/phase-6b-manual-checklist.md` is Tim's (plan header), as are the observations it asks for (probe 4, the sender table, the browser prompt). Fix nothing in code. Step 6 writes the "Phase 6b (built)" paragraph with those observations listed as still to be written down by Tim.

- [ ] **Step 6: Amend the spec, and mark Phase 6b delivered**

1. The 2.1 rows. Replace the row at line 26 (All-in-One mode) with:
```markdown
| All-in-One mode | One hotkey, then pick mode from a small toolbar; locks size and aspect ratio; remembers last selection | P1 | Built in Phase 6b (2.9): ⌃⇧1 opens an adjustable selection (handles, arrows, W and H, aspect lock) with Capture, Window, Fullscreen, Scrolling and Timer, starting from the last area |
```
   In the Quick Access Overlay row (line 28), `Pin is 6b, swipe gestures and hide-temporarily are deferred` becomes `Phase 6b added Pin; swipe gestures and hide-temporarily are deferred`.
   Replace the row at line 36 (Self-timer) with:
```markdown
| Self-timer | Delay before capture | P1 | Built in Phase 6b (2.9): select an area or a window, then a 3, 5 or 10 second countdown; Escape cancels |
```
   Replace the row at line 42 (Pin) with:
```markdown
| Pin (floating screenshot) | Always-on-top window, opacity, nudge with arrows, lock mode | P1 | Built in Phase 6b (2.9): a non-activating panel per pin with move, resize, zoom, opacity, arrows, lock (click-through) and a context menu; pins live until quit |
```
   Replace the row at line 45 (URL scheme) with:
```markdown
| URL scheme | `cleanshot://capture-area?action=upload`, `capture-window`, `capture-fullscreen`, `all-in-one`, `self-timer` | P1 | Built in Phase 6b (2.9): `tidyshot://` with CleanShot's command names, actions and bottom-left coordinates; commands that capture without a selection are off until allowed in General |
```

2. Section 2.8, the Deferred paragraph (line 595): delete `scrolling capture in the URL scheme (`tidyshot://capture-scrolling`, Phase 6); ` (Phase 6b built it).

3. Section 2.9:
   - The Scope paragraph (line 621): `It ships as two PRs on the branch `phase-6-polish`:` becomes `It ships as two PRs, 6a on the branch `phase-6-polish` and 6b on `phase-6b-polish`:`.
   - The URL scheme paragraph's `research.md` (line 677) becomes `docs/superpowers/research/phase-6-research.md`; so does any other bare `research.md` in the 6b text.
   - Rewrite in place every sentence of the 6b text (lines 656-689), of the Settings summary and Architecture lists (lines 691-713) and of the Risks list that the plan header's list of 6b decisions or Step 1 change. At least: the Pin **Opening** bullet names `ThumbnailMaker.scaled(_:maxSide:)` instead of `ThumbnailMaker.thumbnail(from:maxSide:)`, which cuts a tall image to its top (point 7); the Risks bullet *All-in-One in a key window* drops "focus loss when another app activates cancels the selection, as now", which no selection mode does, and says instead that the overlay stays up until Escape, Cancel or a choice, with the key routing tested through `SelectionAdjust.keyCommand` (point 5); the All-in-One bullets gain the click-outside, Window-button, handle and resize rules and the toolbar placement (points 2 to 4) and keep "fullscreen as `captureFullscreen()` does for that display" (point 1); the **Self-Timer** paragraph gains the deactivation during the countdown, the lookup at zero and its two strings (point 6); the **Pin to screen** bullets gain the bring-forward and where `latestCaptureArea` comes from (point 7). For Task 5 (points 8 to 12) at least: the **Errors and refusals** bullet gains the repeated-parameter text `“<name>” is given more than once.` and the less-than-a-point text `The area leaves less than a point on display <n>.`, and says that every URL notification carries `From <sender>` as its subtitle when the sender is known; the **Parameters** bullet gains the number rule (a plain decimal, at most 16 characters, at most 100,000 pt; `display` 1 to 99, used only with the rect), that names and actions are matched ignoring case after percent-decoding, that a parameter a command takes may appear once, and that a `capture-scrolling` rect opens the session panel directly and waits for Start; the **Actions** bullet says that `copy` plays the shutter sound and posts the pixel size, and that `CaptureIntent` also carries the sender; the **URL security** paragraph gives `URLCommandGate.decision(for:enabled:allowSilent:sender:)`, says that with URL commands off even an unparseable URL gets the off message, and that URLs held before start are at most 8; the Architecture list gains `Capture/CaptureIntent.swift` and the `URLCommandTarget` protocol in `URLCommandHandler.swift`.
   - After the last "Phase 6a (built)" paragraph (it ends at line 786, before `## 3. Core workflow in detail`), add `**Phase 6b (built).**` followed by: `Delivered <date> on phase-6b-polish`, the real test line of Step 4 and the checklist's name (`docs/testing/phase-6b-manual-checklist.md`); one line each for the plan header's points 1 to 12 (they gather every task's additions), and for every other place Step 1 found the build differing from the text (a constant, a name, a string, a size or a behaviour); the constants as built (All-in-One minimum side 4 pt and nudges 1 and 10 pt; self-timer 3, 5 and 10 s, default 5, a 96 pt panel with 48 pt digits, a 2 pt dashed frame, 100 ms before the capture; pins at least 40 pt, opacity 10 % to 100 % in 5 % steps, zoom steps of 10 %, a downsample above 8,192 px, an 80 % fit; URL numbers of at most 16 characters and 100,000 pt, displays 1 to 99, values cut at 40 characters, 8 URLs held before start), the four new keys with their defaults (`allInOneAspectLock` false, `selfTimerSeconds` 5, `urlCommandsEnabled` true, `urlCommandsAllowSilent` false) and the shortcuts (`allInOne` ⌃⇧1, `selfTimer` none, `cancelCapture` stored as `cancelScrollingCapture`); then, as the 6a paragraph does, `Observations from the checklist run are still to be written down here by Tim:` which bundle owns `tidyshot:` after cleaning and which one a cold launch started (probe 4), the sender each source shows (Terminal's `open`, Raycast, Keyboard Maestro, Shortcuts, Safari, Chrome) and whether Chrome offers "Always allow", whether Return and Escape behave with All-in-One's fields, the 65,536 px pin's memory, and that none of the GUI checks had been run when this was written.

4. Section 5, the Settings bullet (line 840): `Advanced (URL scheme, history retention).` becomes `no Advanced tab: URL commands are in General and history retention in Overlay (2.9).`

5. The Phase 6 block of section 6 (line 906): `Delivered 2026-10-21: 6a on `phase-6-polish`. 6b follows in its own PR; Phase 6 is released when both have merged. Design and what was built: 2.9.` becomes `Delivered: 6a on 2026-10-21 on `phase-6-polish` (PR 13); 6b on <date> on `phase-6b-polish`. Phase 6 is released when the 6b PR merges. Design and what was built: 2.9.` Write the real date (`date +%F`), not the placeholder.

Where a sentence of 2.9's 6b text is simply wrong after the build (a number, a name, a string), rewrite that sentence in place as well. For a divergence that looks like a bug rather than a decision (the code contradicts a sentence of 2.9 that was the intended behaviour, for example a silent command that runs with the second toggle off, a capture that skips `save(_:intent:)`, or a URL that reaches a capture while one runs), stop and report it; do not amend 2.9 to match a bug. Record every amendment as one line in the report.

Check the result:
```bash
grep -n "Delivered\|Phase 6b (built)\|Phase 6a (built)" docs/superpowers/specs/2026-10-19-tidyshot-screenshot-design.md | cut -c1-140
grep -n "Advanced (URL scheme\|tidyshot://capture-scrolling., Phase 6\|Pin is 6b\|on the branch .phase-6-polish.:" docs/superpowers/specs/2026-10-19-tidyshot-screenshot-design.md
sed -n '/#### 6b:/,/#### Settings summary/p' docs/superpowers/specs/2026-10-19-tidyshot-screenshot-design.md | grep -n "research.md" | grep -v "docs/superpowers/research"
```
Expected: the `Delivered` line in section 6 naming both PRs, and the `Phase 6a (built)` and `Phase 6b (built)` paragraphs in 2.9, in that order; no output from the second and third commands.

- [ ] **Step 7: Commit**

```bash
git add docs/testing/phase-6b-manual-checklist.md README.md docs/superpowers/specs/2026-10-19-tidyshot-screenshot-design.md
git add docs/superpowers/plans/2026-10-21-phase-6b-all-in-one-timer-pin-url.md
git commit -m "docs: Phase 6b checklist, README and spec close-out"
```
The plan is in the list so that a Step 4 correction lands in this commit; when the table is unchanged, `git add` leaves it out. Check `git status` is clean afterwards.

- [ ] **Step 8: Stop here**

Phase 6b's code and documents are done when the last test run reads `Test run with 802 tests in 95 suites passed`; the checklist is left for Tim. Do not push and do not open a PR: the controller pushes and opens the PR after the whole-branch review. Report the final test line, that the checklist (with probe 4 and the sender table) is Tim's and was not run, every checklist, README or 2.9 sentence changed in Step 1 to follow the code, and every amendment made in Step 4 or Step 6.
