# TidyShot: Capture Seams (Phase CT-4) Design

Date: 2026-11-01. Branch `capture-seams` from `main` at 5c2cc33 (CT-3, the small seams, merged). Every file:line below is at 5c2cc33. Abbreviations: `Coord` = `TidyShot/App/AppCoordinator.swift`; `+Save`, `+Capture`, `+Recording` = `TidyShot/App/AppCoordinator+<name>.swift`; `Env` = `TidyShot/App/AppEnvironment.swift`; `CT` = `TidyShot/Capture/CaptureTarget.swift`; `CE` = `TidyShot/Capture/CaptureEngine.swift`; `SC` = `TidyShot/Selection/SelectionController.swift`; `World` = `TidyShotTests/Support/CoordinatorWorld.swift`; `Fakes` = `TidyShotTests/Support/CoordinatorFakes.swift`; `FD` = `TidyShotTests/Support/FakeDestination.swift`. seams.md is `docs/superpowers/notes/2026-10-30-checklist-sweep/seams.md`.

## 1. Goal

The two capture seams from the sweep:

- **`TARGET`** (seams.md section 3, :196-239; 34 lines, 26 alone). `CaptureTarget` holds an `SCDisplay` or `SCWindow` (CT:5-9), which a test cannot build, and `CaptureResult` carries it (CT:59-64) into `save(_:intent:)` (+Save:16). So `save`, `persist` (+Save:140), `writeFile` (:243), `writePendingFile` (:263), `copyOnly` (:111) and `withWindowBackground` (:81) are never driven. `save` reads three things of the target: `case .window` (:82), `displayID` (:62, :86) and `areaRect` (:64).
- **`CAPSRC`** (section 4, :240-284; 34 lines, 8 alone). The coordinator's own `let engine = CaptureEngine()` (Coord:15), read through `loadContent` (Coord:519-531) and `capture(_:excludingWindows:duringSelection:)` (+Capture:377-387), and `lazy var selector = SelectionController(...)` (Coord:32), which every capture and recording entry point asks (+Capture:37, :102, :187, :206, :232; +Recording:215). Built on `TARGET`.

They go together because `CAPSRC` is built on `TARGET` and the two diffs touch disjoint lines (section 2.3). `TARGET` is small (production about +43 −18 in two files) and reaches 32 lines; `CAPSRC` is large (about +141 −60 in eleven files; the two together measure +184 −78 in twelve files, section 12) and reaches 12 lines on its own, and is the floor under every later capture seam. Whether to build `CAPSRC` now is call 1 (section 10). The phase writes 28 tests (21 `TARGET`, 7 `CAPSRC`), adds a step to one existing test, and marks 44 lines: 23 in full and 21 in part; 24 lines are deferred (section 11). The notes are committed beside this design in `docs/superpowers/notes/2026-11-01-capture-seams/`: `lines-capture.md` gives each of the 68 lines with its text, current mark, verdict and what stays; `tests-capture.md` is the catalogue, with every value a test body needs (`T1` to `T21` are `TARGET`'s, `C1` to `C9` `CAPSRC`'s). The plan copies from there and from this design; nothing depends on the git-ignored `.superpowers/` files.

## 2. The seams

### 2.1 `TARGET`: the value the save path reads

**Type and member.** A `nonisolated` value `CaptureOrigin` (what the save path reads: the kind, with an area's rect, and the display id) and an internal `save(_ captured: ScaledImage, from origin: CaptureOrigin, intent: CaptureIntent)` that `save(_:intent:)` forwards to. No `AppEnvironment` member and no fake: nothing on the save path needs replacing beyond what the world already fakes. A value target the engine resolves back by id (seams.md's main shape, :199) is rejected here: it would add a second content read per capture or state on a stateless engine (CE:5), and edit every maker of a target (sixteen sites in +Capture, three in +Recording, two in SC). That is `CAPSRC`'s diff, paid for by its lines. A `CaptureResult` carrying the origin is rejected too: it changes three other makers of a result (CE:49, +Capture:137, :366) for no line.

**The live value.** `CaptureTarget.origin`, built from the live target in the forwarder. `CaptureEngine.capture` (CE:13-50), `CaptureTarget`, `CaptureResult` and the seven callers of `save(_:intent:)` (+Capture:11, :70, :137, :159, :178, :218, :337) are untouched.

`CT`, the `areaRect` extension (:35-41) is replaced; `CaptureOrigin` has the only reader's property:
```diff
 extension CaptureTarget {
-    /// The rect of an area capture (CoreGraphics global points), nil for a display or a window.
-    /// A pin of the newest capture opens over it.
-    var areaRect: CGRect? {
-        if case .area(let rect, _) = self { rect } else { nil }
+    /// What the save path reads of this target (`AppCoordinator.save(_:from:intent:)`).
+    var origin: CaptureOrigin {
+        switch self {
+        case .display: CaptureOrigin(kind: .display, displayID: displayID)
+        case .area(let rect, _): CaptureOrigin(kind: .area(rect), displayID: displayID)
+        case .window: CaptureOrigin(kind: .window, displayID: displayID)
+        }
     }
 }
+
+/// Where a capture came from, as the save path reads it: a display, an area or a window, and the
+/// display it came from. A value, not the ScreenCaptureKit objects, so the suite can build one
+/// (seams.md section 3, `TARGET`); `CaptureTarget.origin` makes it from a live target.
+nonisolated struct CaptureOrigin: Equatable, Sendable {
+    /// An area carries its rect, in CoreGraphics global points.
+    enum Kind: Equatable, Sendable { case display, area(CGRect), window }
+    var kind: Kind
+    /// `CaptureTarget.displayID`: the card's screen under `Show on` and the desktop picture's display.
+    var displayID: CGDirectDisplayID
+    /// The rect of an area capture, nil for a display or a window. A pin of the newest capture opens over it.
+    var areaRect: CGRect? { if case .area(let rect) = kind { rect } else { nil } }
+    /// Only a window capture goes on the Capture tab's background.
+    var isWindow: Bool { kind == .window }
+}
```

`+Save`, every changed statement (the body of `save` is otherwise the same statement sequence; `persist` from :140 on is unchanged and moves down 9 lines):
```diff
@@ save (+Save:15-25)
     @discardableResult
     func save(_ result: CaptureResult, intent: CaptureIntent = .standard) async -> CaptureRecord? {
+        await save(result.scaled, from: result.target.origin, intent: intent)
+    }
+
+    /// `save(_:intent:)` over the image and what the save path reads of its target (`CaptureOrigin`).
+    /// The suite calls it with an origin it builds (seams.md section 3, `TARGET`). The intent has no
+    /// default, so nothing here reads `AppSettings.shared`.
+    @discardableResult
+    func save(_ captured: ScaledImage, from origin: CaptureOrigin, intent: CaptureIntent) async -> CaptureRecord? {
         // Before the copy-only branch, so `action=copy` gets the background too.
-        let result = await withWindowBackground(result)
+        let image = await withWindowBackground(captured, from: origin)
         if intent.copyOnly {
-            await copyOnly(result, sender: intent.sender)
+            await copyOnly(image, sender: intent.sender)
             return nil
         }
         latestCapture = nil
         latestCaptureArea = nil
-        let image = result.scaled
         let action = intent.action
@@ (+Save:60-64)
                                          alreadyOnClipboard: copyImageNow,
-                                         captureDisplayID: result.target.displayID) else { return nil }
+                                         captureDisplayID: origin.displayID) else { return nil }
         // Before anything below, so a pin of this record opens over the spot it came from.
-        latestCaptureArea = result.target.areaRect.map { (id: record.id, rect: $0) }
+        latestCaptureArea = origin.areaRect.map { (id: record.id, rect: $0) }
@@ withWindowBackground (+Save:81-97)
-    private func withWindowBackground(_ result: CaptureResult) async -> CaptureResult {
-        guard settings.windowBackground, case .window = result.target else { return result }
+    private func withWindowBackground(_ image: ScaledImage, from origin: CaptureOrigin) async -> ScaledImage {
+        guard settings.windowBackground, origin.isWindow else { return image }
         let style = settings.backgroundStyle
-        let content = result.image
-        let scale = result.scale
-        let fillImage = await BackgroundFillSource.fillImage(for: style.fill, displayID: result.target.displayID)
+        let content = image.image
+        let scale = image.scale
+        let fillImage = await BackgroundFillSource.fillImage(for: style.fill, displayID: origin.displayID)
@@ (+Save:95-97)
             log("Background: \(reason), keeping the window capture")
-            return result
+            return image
         }
-        return CaptureResult(image: composed, scale: scale, target: result.target)
+        return ScaledImage(image: composed, scale: scale)
@@ copyOnly (+Save:111-112)
-    private func copyOnly(_ result: CaptureResult, sender: String?) async {
-        let image = result.scaled
+    private func copyOnly(_ image: ScaledImage, sender: String?) async {
```

Isolation: `CaptureOrigin` is a `nonisolated struct` with a nested `Equatable, Sendable` enum, the shape of `CaptureIntent` and its `Then` (CaptureIntent.swift:5-12), which compiles under `SWIFT_DEFAULT_ACTOR_ISOLATION: MainActor` (project.yml:30, :102). `CaptureTarget.origin` stays main-actor, since `.window`'s id calls the main-actor `CaptureEngine.displayID(containing:)` (CT:18, CE:94). `ScaledImage` is `nonisolated ... Sendable` (ScaledImage.swift:6); the detached encode and compose take the same `CGImage`, `CGFloat`, style and fill as today. This diff and T1 to T4 built and ran green in the designer's scratch tree (section 12).

**What does not change.** The same pixels, files, names, clipboard writes, notices, history and log lines, in the same order. The forwarder takes `result.scaled` once, where `save` took it after the background step; the background step now returns the image alone, where it returned a result with the same target. One timing detail: a window target's display id (`CGGetDisplaysWithPoint` on `SCWindow.frame`, CE:94-99) is computed once when the forwarder runs instead of at :86 and :62; the frame is a snapshot, so only a display plugged in or out within those milliseconds could tell. For the user: ⌃⇧4 still saves the area with `Screenshot saved`, the clipboard image and a card on the capture's display; a window capture with `Add background to window captures` on is still composed in the file, the clipboard, the card and the upload, and a fullscreen or area capture is not; `action=copy` still copies and posts `Image copied` with nothing else; a pin of the newest capture still opens over its area. `CaptureIntent.standard` (the `AppSettings.shared` read, CaptureIntent.swift:42-44) stays the forwarder's default.

### 2.2 `CAPSRC`: the capture source and the selector

**Types and members.** The ScreenCaptureKit objects become values that carry the object as a `live` handle: `CaptureDisplay` (id, frame, `live: SCDisplay?`), `CaptureWindow` (window id, frame, `live: SCWindow?`) and `ScreenContent` (displays, windows, `live: SCShareableContent?`). `CaptureTarget`, `Selection` and `AllInOneChoice` carry the values. Two protocols go on `AppEnvironment`: `captureSource: any CaptureSource` (the content read, a capture, the card windows by number, the display under the pointer, the grant) and `selector: any CaptureSelecting` (the five members the coordinator calls). This is seams.md's shape (:245) with the pointer and the grant added, because the coordinator reads `NSEvent.mouseLocation` (+Capture:9, +Recording:254) and `ScreenCapturePermission.isGranted` (Coord:524) beside the content. Resolving a value back by id instead of the handle is rejected: a smaller type, but a second content read per capture (call 4). `CaptureTarget.origin` (2.1) compiles unchanged over the values, which carry `displayID` and `frame` under the same names.

**The live values.** `CaptureEngine` and `SelectionController` conform. `live()` builds one `CaptureEngine()` (stateless, CE:5) for the source and the selector; `SelectionController.init` only stores (SC:28-32), so building it in `live()` rather than on the first capture shows nothing. The coordinator keeps its own `engine` (Coord:15) for the scrolling session and the recording driver.

`CT:1-9`, replacing the three SC-typed cases (and `CaptureTarget` gains `: Equatable`):
```swift
/// A display a capture can use: its id and frame, and the SC display it was read from (`live`, nil for one a test built).
struct CaptureDisplay: Equatable {
    let displayID: CGDirectDisplayID
    let frame: CGRect
    let live: SCDisplay?
    init(displayID: CGDirectDisplayID, frame: CGRect) { self.displayID = displayID; self.frame = frame; live = nil }
    init(_ display: SCDisplay) { displayID = display.displayID; frame = display.frame; live = display }
}
/// A window a capture can use: its window number and frame, and the ScreenCaptureKit window (`live`).
struct CaptureWindow: Equatable {
    let windowID: CGWindowID
    let frame: CGRect
    let live: SCWindow?
    init(windowID: CGWindowID, frame: CGRect) { self.windowID = windowID; self.frame = frame; live = nil }
    init(_ window: SCWindow) { windowID = window.windowID; frame = window.frame; live = window }
}
/// What to capture. Rects are in CoreGraphics global points (top-left origin).
enum CaptureTarget: Equatable {
    case display(CaptureDisplay)
    case area(rect: CGRect, display: CaptureDisplay)
    case window(CaptureWindow)
}
```
`CaptureError` (CT:66-74) gains `case notListed` with "The display or window is not one ScreenCaptureKit listed.", unreachable in the app. New `TidyShot/Capture/CaptureSource.swift`:
```swift
import CoreGraphics
import ScreenCaptureKit
/// The displays and windows on screen as values, in ScreenCaptureKit's order; `live` is the content
/// they were read from (the overlay's window picker uses it), nil for content a test built.
struct ScreenContent {
    let displays: [CaptureDisplay]
    let windows: [CaptureWindow]
    let live: SCShareableContent?
    init(displays: [CaptureDisplay], windows: [CaptureWindow]) { self.displays = displays; self.windows = windows; live = nil }
    init(_ content: SCShareableContent) {
        displays = content.displays.map(CaptureDisplay.init); windows = content.windows.map(CaptureWindow.init); live = content
    }
}
/// What the capture flows read of the screen. `CaptureEngine` in the app; `FakeCaptureSource` in the suite.
protocol CaptureSource: AnyObject {
    func screenContent() async throws -> ScreenContent
    func capture(_ target: CaptureTarget, options: CaptureOptions, excludingWindows: [CaptureWindow]) async throws -> CaptureResult
    func windows(numbers: Set<CGWindowID>) async -> [CaptureWindow]  // retried briefly; whatever was found
    func displayUnderPointer(in displays: [CaptureDisplay]) -> CaptureDisplay?
    var isScreenRecordingGranted: Bool { get }
}
```
`TidyShot/Selection/Selection.swift:22-25`: `Selection`'s cases take `CaptureDisplay` and `CaptureWindow`, and after it:
```swift
/// The selection overlay as the capture flows use it. `SelectionController` in the app; `FakeSelector` in the suite.
protocol CaptureSelecting: AnyObject {
    func select(mode: SelectionMode, content: ScreenContent, freeze: CaptureOptions?, preselect: CGRect?) async -> Selection?
    func selectAllInOne(content: ScreenContent, freeze: CaptureOptions?, preselect: CGRect?, armed: Bool) async -> AllInOneChoice?
    func frozenCapture(for displayID: CGDirectDisplayID) -> FrozenSnapshot?
    func overlayWindows() async -> [CaptureWindow]
    func dismiss()
}
```
`AllInOneChoice.swift:7-17`: the five cases take `CaptureDisplay` and `CaptureWindow`. `CE`: `capture` (:13) takes `excludingWindows: [CaptureWindow] = []`, filters with `excludingWindows.compactMap(\.live)`, and each case unwraps its `live` object (`guard let source = display.live else { throw CaptureError.notListed }`) before `SCContentFilter`; `AppCoordinator.display(under:in:)` (+Capture:397-402) moves to `CE` as `static func display(under:in: [CaptureDisplay]) -> CaptureDisplay?` with the same body; and `extension CaptureEngine: CaptureSource` answers `ScreenContent(try await shareableContent())`, `OverlayWindowLookup.windows(numbers:engine: self).map(CaptureWindow.init)`, `Self.display(under: NSEvent.mouseLocation, in:)` and `ScreenCapturePermission.isGranted`. `SC`: `select` (:36) and `selectAllInOne` (:49) take `ScreenContent` and add `let live = content.live` to their guards, presenting the live content as today; `cachedOverlayWindows` (:19) and `overlayWindows()` (:260) become `[CaptureWindow]` (the lookup's result `.map(CaptureWindow.init)`); `clippedToDisplay` (:227) returns `CaptureDisplay(display)`; `resumeAllInOne(.window(CaptureWindow(pickedWindow)))` (:187), `finish(.window(CaptureWindow(window)))` (:338) and the two `engine.capture(.display(CaptureDisplay(display)), ...)` (:242, :283) wrap at the boundary; `extension SelectionController: CaptureSelecting {}` at the end. `PreviousArea.swift:25`'s doc says `CaptureDisplay`. Nothing else outside the diff reads these types: the recording driver, `ScrollCaptureController.run(rect:display: SCDisplay, ...)`, `WindowPicker` and `OverlayWindowLookup` stay SC-typed and are handed `live` objects.

`Env`, after `var clipboard: any Clipboard` (:24), and in `live()` (:63-79):
```diff
+    /// The displays and windows, a capture, the cards as windows, the display under the pointer, the grant.
+    var captureSource: any CaptureSource
+    /// The selection overlay: an area or a window, All-in-One's choice, the freeze snapshots.
+    var selector: any CaptureSelecting
@@ live()
         let overlay = QuickAccessController(settings: settings)
+        let engine = CaptureEngine()
@@
             clipboard: SystemClipboard(),
+            captureSource: engine,
+            // Every capture leaves out the cards on screen, as the coordinator's own selector did.
+            selector: SelectionController(engine: engine, settings: settings,
+                                          cardWindowNumbers: { [overlay] in overlay.windowNumbers }),
```
`live()`'s doc (Env:57-62) names "ScreenCaptureKit and the selection overlay over it" after "the general pasteboard", and says Clop's optimiser and the selection overlay, which store what they are given, are built there.

`Coord`:
```diff
@@ (:32)
-    @ObservationIgnored lazy var selector = SelectionController(engine: engine, settings: settings, cardWindowNumbers: { [weak self] in self?.overlay.windowNumbers ?? [] })
+    /// The selection overlay, from the environment (CT-4).
+    let selector: any CaptureSelecting
+    /// What every capture and recording start reads of the screen, from the environment (CT-4).
+    /// `engine` stays for the scrolling session and the recording driver.
+    let captureSource: any CaptureSource
@@ init, after `clopOptimiser = environment.clopOptimiser` (:275)
+        selector = environment.selector
+        captureSource = environment.captureSource
@@ loadContent (:519-524)
-    func loadContent(failureTitle: String = "Capture failed") async -> SCShareableContent? {
+    func loadContent(failureTitle: String = "Capture failed") async -> ScreenContent? {
         do {
-            return try await engine.shareableContent()
+            return try await captureSource.screenContent()
         } catch {
             log("Shareable content failed: \(error.localizedDescription)")
-            if ScreenCapturePermission.isGranted {
+            if captureSource.isScreenRecordingGranted {
```

`+Capture`:
```diff
@@ (:9)
-            guard let display = Self.display(under: NSEvent.mouseLocation, in: content.displays) else { return }
+            guard let display = captureSource.displayUnderPointer(in: content.displays) else { return }
@@ (:102, :187; :206 and :232 likewise add `preselect: nil` after `freeze: freeze`)
-            guard let selection = await selector.select(mode: .scrolling, content: content) else { return }
+            guard let selection = await selector.select(mode: .scrolling, content: content, freeze: nil, preselect: nil) else { return }
@@ runScrolling (:117, :125-128)
-    private func runScrolling(rect: CGRect, display: SCDisplay, intent: CaptureIntent,
+    private func runScrolling(rect: CGRect, display: CaptureDisplay, intent: CaptureIntent,
@@
         selector.dismiss()
-        let outcome = await scrollCapture.run(rect: rect, display: display, makesPanelKey: !preselected,
+        // The session films the ScreenCaptureKit display; a display a test built has none and ends here.
+        guard let liveDisplay = display.live else { return }
+        let outcome = await scrollCapture.run(rect: rect, display: liveDisplay, makesPanelKey: !preselected,
@@ areaResult (:342), selectedAreaResult (:349), frozenResult (:359): `display: SCDisplay` becomes `display: CaptureDisplay`
@@ capture (:377-380)
-    func capture(_ target: CaptureTarget, excludingWindows: [SCWindow] = [],
+    func capture(_ target: CaptureTarget, excludingWindows: [CaptureWindow] = [],
@@
-            return try await engine.capture(target, options: options, excludingWindows: excludingWindows)
+            return try await captureSource.capture(target, options: options, excludingWindows: excludingWindows)
@@ cardWindows (:391-394)
-    private func cardWindows() async -> [SCWindow] {
+    private func cardWindows() async -> [CaptureWindow] {
@@
-        return await OverlayWindowLookup.windows(numbers: numbers, engine: engine)
+        return await captureSource.windows(numbers: numbers)
@@ (:397-402) `static func display(under:in:)` removed (moved to CaptureEngine)
```

`+Recording`:
```diff
@@ (:215)
-            guard let selection = await selector.select(mode: .recording, content: content,
+            guard let selection = await selector.select(mode: .recording, content: content, freeze: nil,
@@ (:254)
-                  let display = Self.display(under: NSEvent.mouseLocation, in: content.displays) else {
+                  let display = captureSource.displayUnderPointer(in: content.displays) else {
@@ (:596, :604; bodies unchanged)
-    private func connectedDisplay(_ id: CGDirectDisplayID, in content: SCShareableContent) -> SCDisplay? {
+    private func connectedDisplay(_ id: CGDirectDisplayID, in content: ScreenContent) -> CaptureDisplay? {
-    private static func recordingDisplay(_ display: SCDisplay) -> RecordingDisplay {
+    private static func recordingDisplay(_ display: CaptureDisplay) -> RecordingDisplay {
```
`recordingHandOff` (+Recording:484-582) compiles unchanged: it reads `displayID`, `frame` and `windowID` and rebuilds targets from `content.displays.first(where:)` and `content.windows.first(where:)`, which now yield the values.

Isolation: the protocols, the value types and the conformances are main-actor by default isolation, as `Notifying` and `ClopOptimising` are; under `SWIFT_APPROACHABLE_CONCURRENCY` (project.yml:31) the async requirements run on the caller's actor, so no value crosses a boundary. The values hold non-Sendable SC objects and are not `Sendable`, as today's types are not. The design's review built this diff with section 2.1's in a scratch copy of 5c2cc33 (section 12): it compiled clean under Swift 6 on the first pass, and none of the three places the judge expected the compiler to push back (the synthesized `Equatable` over `SCDisplay?`, the `[overlay]` capture in `live()`, and `let` members on an `@Observable` class) needed a change. If a fix in the plan's compile pass for the remaining tests moves the diff beyond this section, the task stops and reports.

**What does not change.** The engine films exactly the `SCDisplay` or `SCWindow` it films today: the value's `live` is the object the content read returned, and `displayID`, `frame` and `windowID` are copies read when it was wrapped. The content is read once per flow as today, never resolved by id. `loadContent` logs, posts under the same title or shows the permission window exactly as before; the pointer rule is moved, not changed; the same frames, scale, source rect and exclusions (the overlay and the cards) reach ScreenCaptureKit. For the user: every shortcut, menu item and URL command opens the same overlay, captures the same pixels and saves as before; a scrolling capture, a self-timer and a recording start as before; with Screen Recording refused the permission window still shows. Each content read also wraps every window as a value, which is not measurable against the read itself.

### 2.3 What the two share

`CT` is edited by both in disjoint lines: `TARGET` replaces :35-41 and adds `CaptureOrigin`; `CAPSRC` rewrites :1-9 and appends to `CaptureError`. `CAPSRC` takes `CaptureOrigin`, `save(_:from:intent:)`, `CaptureSamples` and the save-suite rules from `TARGET` and changes none of them. `AppEnvironment` is a positional init at two sites, `live()` (Env:72) and `World:125`; `CAPSRC` adds `captureSource`, `selector` after `clipboard` at both. Each seam is its own plan task, `TARGET` first.

## 3. The fakes

### 3.1 `TARGET`: `CaptureSamples` (new `TidyShotTests/Support/CaptureSamples.swift`), no fake

```swift
import CoreGraphics
import Foundation
import Testing
@testable import TidyShot
/// Captures as the save path takes them (`AppCoordinator.save(_:from:intent:)`): an image of a pixel size at a scale,
/// and where it came from. No ScreenCaptureKit object is made; the display id is the suite's own number.
nonisolated enum CaptureSamples {
    static let displayID: CGDirectDisplayID = 1
    /// A red capture of `width` by `height` pixels at `scale`, white when `white`.
    static func image(width: Int, height: Int, scale: CGFloat = 2, white: Bool = false) throws -> ScaledImage { ScaledImage(image: try EditorPixels.image(width: width, height: height, white: white), scale: scale) }
    static let display = CaptureOrigin(kind: .display, displayID: displayID)
    static let window = CaptureOrigin(kind: .window, displayID: displayID)
    static func area(_ rect: CGRect = CGRect(x: 100, y: 80, width: 200, height: 150)) -> CaptureOrigin { CaptureOrigin(kind: .area(rect), displayID: displayID) }
    /// The names of the files directly in `folder`, sorted; none when it does not exist.
    static func fileNames(in folder: URL) -> [String] { ((try? FileManager.default.contentsOfDirectory(atPath: folder.path(percentEncoded: false))) ?? []).sorted() }
}
```
The only held fake `TARGET` uses is the destination's upload (`holdingUploadsRemaining`, `heldUploads`, `releaseUploads()`, FD:26, :28, :264). `CoordinatorWorld` is unchanged.

### 3.2 `CAPSRC`: `FakeCaptureSource` and `FakeSelector` (new `TidyShotTests/Support/CaptureSourceFakes.swift`)

```swift
nonisolated struct FakeCaptureError: LocalizedError, Sendable { var errorDescription: String? { "The fake source failed." } }
/// The capture source in the suite: ScreenCaptureKit, the screen and the pointer are never reached. Each read gives
/// `content` unless `contentFailures` has an error left; a capture is recorded, then throws `captureFailure` or answers
/// a red image of the target's `cgFrame` size at `scale`. Screen Recording is always granted.
final class FakeCaptureSource: CaptureSource {
    struct Capture: Equatable { let target: CaptureTarget; let options: CaptureOptions; let excludedWindowIDs: [CGWindowID] }
    static let display = CaptureDisplay(displayID: 1, frame: CGRect(x: 0, y: 0, width: 1440, height: 900))
    var content = ScreenContent(displays: [FakeCaptureSource.display], windows: [])
    var contentFailures: [any Error] = [], scale: CGFloat = 1, captureFailure: (any Error)?, pointerDisplayID: CGDirectDisplayID?
    private(set) var contentReads = 0, captures: [Capture] = [], windowLookups: [Set<CGWindowID>] = []
    let isScreenRecordingGranted = true
    func screenContent() async throws -> ScreenContent {
        contentReads += 1; if !contentFailures.isEmpty { throw contentFailures.removeFirst() }; return content
    }
    func capture(_ target: CaptureTarget, options: CaptureOptions, excludingWindows: [CaptureWindow]) async throws -> CaptureResult {
        captures.append(Capture(target: target, options: options, excludedWindowIDs: excludingWindows.map(\.windowID)))
        if let captureFailure { throw captureFailure }
        let size = Geometry.pixelSize(points: target.cgFrame.size, scale: scale)
        return CaptureResult(image: try CoordinatorWorld.image(width: max(size.width, 1), height: max(size.height, 1)), scale: scale, target: target)
    }
    func windows(numbers: Set<CGWindowID>) async -> [CaptureWindow] { windowLookups.append(numbers); return content.windows.filter { numbers.contains($0.windowID) } }
    func displayUnderPointer(in displays: [CaptureDisplay]) -> CaptureDisplay? { displays.first { $0.displayID == pointerDisplayID } ?? displays.first }
}
/// The selection overlay in the suite: no window is built and the screen is never read. Every ask is kept; each answers
/// the next of `selections` or `choices` (nil, or none left, is Escape), or while `holds` waits for `answer(_:)` or
/// `answerAllInOne(_:)`. A held overlay whose task is cancelled answers Escape; a second while one is held records an issue.
final class FakeSelector: CaptureSelecting {
    struct Select: Equatable { let mode: SelectionMode; let freeze: CaptureOptions?; let preselect: CGRect? }
    struct AllInOne: Equatable { let freeze: CaptureOptions?; let preselect: CGRect?; let armed: Bool }
    private(set) var selects: [Select] = [], allInOnes: [AllInOne] = [], frozenAsked: [CGDirectDisplayID] = []
    private(set) var overlayLookups = 0, dismissCount = 0
    var selections: [Selection?] = [], choices: [AllInOneChoice?] = [], holds = false
    var overlays: [CaptureWindow] = [], frozen: [CGDirectDisplayID: FrozenSnapshot] = [:]
    private var heldSelection: Selection?, heldChoice: AllInOneChoice?
    private let held = SingleWaiter(cancelled: false, secondEntry: "FakeSelector was asked again while an overlay was held")
    var isWaiting: Bool { held.isWaiting }
    func select(mode: SelectionMode, content: ScreenContent, freeze: CaptureOptions?, preselect: CGRect?) async -> Selection? {
        selects.append(Select(mode: mode, freeze: freeze, preselect: preselect))
        guard holds else { return selections.isEmpty ? nil : selections.removeFirst() }
        guard await held.wait() else { return nil }
        defer { heldSelection = nil }; return heldSelection
    }
    func selectAllInOne(content: ScreenContent, freeze: CaptureOptions?, preselect: CGRect?, armed: Bool) async -> AllInOneChoice? {
        allInOnes.append(AllInOne(freeze: freeze, preselect: preselect, armed: armed))
        guard holds else { return choices.isEmpty ? nil : choices.removeFirst() }
        guard await held.wait() else { return nil }
        defer { heldChoice = nil }; return heldChoice
    }
    func answer(_ selection: Selection?) { holds = false; heldSelection = selection; held.resume(true) }
    func answerAllInOne(_ choice: AllInOneChoice?) { holds = false; heldChoice = choice; held.resume(true) }
    func frozenCapture(for displayID: CGDirectDisplayID) -> FrozenSnapshot? { frozenAsked.append(displayID); return frozen[displayID] }
    func overlayWindows() async -> [CaptureWindow] { overlayLookups += 1; return overlays }
    func dismiss() { dismissCount += 1 }
}
```
The file opens with the imports of 3.1. `SingleWaiter` (Fakes:409) needs `Value: Sendable`, hence the `Bool` and the answer kept beside it. One waiter serves both kinds, as the live `isIdle` covers both continuations. An unheld ask with nothing scripted is Escape with no issue: every entry handles Escape (+Capture:37-40, :102, :187, :206, :232; +Recording:215-216), and tests read `selects` and `allInOnes`.

### 3.3 `CoordinatorWorld` and two suite edits (`CAPSRC` only)

`World`, after `let clipboard = FakeClipboard()` (:43): `let source = FakeCaptureSource()` and `let selector = FakeSelector()`, with one-line docs; in `environment` (:118-151), after `clipboard: clipboard,` (:133): `captureSource: source, selector: selector,`. The type doc names "the capture source and the selection overlay (`source`, `selector`; no window is built and ScreenCaptureKit is never read)". `CoordinatorWorldTests.aCoordinatorOverTheWorldKeepsToTheWorld`, after `#expect(world.saveAsChooser.asked.isEmpty)` (CoordinatorWorldTests.swift:35): `contentReads == 0`, `captures.isEmpty`, `selects.isEmpty`, `allInOnes.isEmpty`. `CoordinatorCaptureTests`' lock test gains `#expect(world.source.contentReads == 0)` and its doc (:5-7) says the content read is counted. These are checks, not tests.

## 4. The tests

28 tests, 2 new suite files; `tests-capture.md` has each in full (sections 3 and 4) and the line table (1.1, 1.2). Of them, T1 to T4 ran green in the `TARGET` designer's scratch tree and T1, T2, C3 and C5 in the design's review (section 12); the other 22 and C8's step are written from the code and the suites' idioms. Effort over the 28 and C8: S 12, M 15, L 2. Nine tests are parameterized and count once (T4, T5, T8, T9, T10, T11, T14, T15, C1).

| Suite file | New? | Tests | tests-capture.md | What they drive |
|---|---|---|---|---|
| `CoordinatorCaptureSaveTests` | new | 21 (T1-T21) | TARGET.3 | names and ` 2` after a relaunch, Also copy then the link, Ocean in file, clipboard and upload, copy-only, save and copy, a new folder, upload and copy URL, no destination twice, a failing upload, upload-only with and without a card, `action=upload` and `action=save`, a tall capture, annotate, area and fullscreen plain, each canvas style, the setting off, the editor on a composed capture, copy and upload composed, too large for a background, two at once, a failed upload-only capture retried |
| `CoordinatorCaptureSourceTests` | new | 7 (C1-C7) | CAPSRC.4 | Previous Area with no usable area, All-in-One's preselect and arming, a held selection dropping URL captures, Previous Area after Capture Text, a failed content read, a scrolling area under 100 pt, which captures store the previous area |
| `CoordinatorRecordingTests` | existing | 0 (C8, a step) | CAPSRC.5 | the eight capture entries refused at the microphone prompt, reading nothing |
| `SelectionViewArmingTests` | existing | 0 (C9, 1 if taken) | CAPSRC.5 | a width change or the lock arming a disarmed rect (call 3) |

Each test's doc comment names its checklist lines by catalogue key and current line, and a part test says what stays and whose. If `CAPSRC` is deferred (call 1), C1 to C8 and section 3.2-3.3 go; C9 stays only if taken alone.

## 5. Rules for the tests

From CT-3 section 5, still binding: `TidyShot/` changes only as section 2 says, and no `private` member opens; a test that would need more is reported, not forced. No test touches `AppSettings.shared`, `NSPasteboard.general`, the Keychain, `UNUserNotificationCenter`, `NSWorkspace`, `NSRunningApplication`, `NSScreen.screens`, the `tmp/` statics, a window ordered front, a panel shown, the screen, a camera, a microphone, a sound, the real Clop app or the network. History is loaded with `history.load()`, never `start()`. `HistoryStore` prunes on the real `Date()`. Held fakes are cancellable and single-entry; a held call is never awaited directly: the test runs it in a `Task` and gates it with `eventually`, UploadQueueTests.swift:42 and `TaskWatch`, Fakes:454, while a call nothing holds is awaited directly; a held task is cancelled or released in a `defer` declared right after `defer { world.removeAll() }`. Each test owns its world and defaults suite; suites are `@Suite(.timeLimit(.minutes(1)))` with no `.serialized`, built in `init() throws` with `world.settings.showOverlay = false` (a card's screen reads `NSScreen`, +Overlay.swift:9, :55-62). The tests' `MovieSamples` decoder is untouched.

This phase's own rules (tests-capture.md TARGET.2 and CAPSRC.2 give the values):
- **An explicit intent everywhere.** The forwarder's and every entry point's default `.standard` reads `AppSettings.shared` (CaptureIntent.swift:42-44); the `TARGET` tests call the three-argument entry, which has none. A save stores a folder first (`world.storeSaveFolder()`, World:175-180) or is copy-only or `.uploadOnly`, so `ensureFolder` never builds an `NSOpenPanel` (SaveLocation.swift:30-44).
- **Names and the clock.** `writeFile`'s `FileNamer` reads `Date()` (+Save:251): a test that reads a name sets the template `Shot`; a test with two saves and no template asserts distinct names only.
- **The thumbnail.** `finishSave` starts an unawaited thumbnail write under `<root>/thumbnails/` (+Save:288-310), so every test that saves a record ends with `eventually` on the record's `thumbnailFileName`.
- **Out of reach, not driven.** `.pin` (`PINS`, +Pins.swift:31), a `.desktopPicture` or `.customImage` fill (`BGFILL`, BackgroundFillSource.swift:12-13), a save with no stored folder (`FOLDER`), any path into `runSelfTimer` (`STAGE`, +Capture:297-307), `recordingCanStart` (`TMPDIRS`, +Recording:213, :249, :354), All-in-One's `.fullscreen` (`NSCursor.arrow.set()`, +Capture:54), `covers` with `hideDesktopIconsWhileCapturing` on (`COVERS`). `scrollCapture.run` is never reached: a test-built display has no `live` object, so `runScrolling` stops at its guard after the 100 pt check and the store.
- **The held overlay.** `world.selector.holds = true`, `defer { world.selector.answer(nil) }`, the entry in a `Task` with `defer { task.cancel() }` and a `TaskWatch`, `eventually { world.selector.isWaiting }`, assert, answer, `eventually { watch.hasReturned }`. Never two held at once.
- **Window display ids.** A window target's id is `CGGetDisplaysWithPoint` on the host (CE:94-99): no test asserts on it.
- **C4 runs the real `TextRecognizer`** on a 40 x 20 red image (+Capture:273), as `TextRecognizerTests` already do in the same run (call 5).

## 6. The marks

As CT-3 section 6: `(suite: Suite.test)` for full and `(suite, in part: Suite.test; by hand: <what>)` for part, appended to the end of the item's last line, wrapped at 120 columns with two-space continuation lines, a closing `______` kept last. The sources are tests-capture.md TARGET.4 and CAPSRC.6 (the mark per line) and each line's "What stays" in lines-capture.md. A by-hand text names the other seam where there is one (`SCREENS`, `WORKSPACE`, `STATUSMENU`, `UPLOADFORM`, `EDPLACE`, `PINS`, `BGPOP`, `SCROLL`, `SELINT`, `STAGE`, `TMPDIRS`, `RECCHROME`, `CAPSRC`), and a mark names the existing tests that pin part of the line (`CaptureIntentTests`, `BackgroundLayoutTests`, `RecentCaptureFormattingTests`, `CoordinatorUploadTests`, `PreviousAreaTests`, `SelectionViewArmingTests`, `URLCommandHandlerTests` and the others TARGET.4 and CAPSRC.6 list). The script finds each line by an anchor that occurs once in its file at the branch head.

**Extended, not duplicated.** Five lines carry a mark already, and a line gets one mark: the script edits the existing note in place and never appends a second. phase-4a:119 (phase-4a checklist :210), phase-4a:120 (:215), phase-6b:118 (phase-6b :144) and phase-7c:187 (phase-7c :241) carry CT-2 in-part marks whose by-hand lists name `TARGET`; each gains its CT-4 test (T8, T2, T13, T17) at the end of its test list, and the `TARGET` clause leaves its by-hand list, which keeps `EDPLACE`, `PINS` or `BGPOP` and `EDPLACE`. All four stay in part. recording-r4:217 (recording-r4 :226) keeps its rule test and its by-hand clause is reworded with no test: "by hand: the log line, in private `record()` past the capture lock (`TMPDIRS`, and the hand-off's `NSScreen` read, +Recording.swift:496, which only `STAGE`'s screen lookup names)", because `TMPDIRS` and `CAPSRC` do not finish it (+Recording:491, :496). The script asserts that each anchor matches one line, that every named test exists (`func <name>(` in `TidyShotTests/`), that each of the five carries exactly one `(suite` note after the edit, and that none of the other 40 marked lines carries one before. 44 lines are marked: 23 full, 21 part (`TARGET` 19 and 13, `CAPSRC` 4 and 8). The 24 deferred lines get no mark, as CT-3 left recording-r3:416 and :436; recording-r2:653 stays ticked `[x]`. Where a line's text is partly out of date (phase-2:32 and small-tweaks:13 name a `Saved` word the row no longer shows), the text is not changed (call 9).

## 7. Settings, entitlements, packages

None change. `project.yml` takes `TidyShotTests/` whole, less `Fixtures/**` (project.yml:93-96), and `TidyShot/` whole, so the new `CaptureSource.swift`, the two support files and the two suite files are picked up by `xcodegen generate`. No new setting; the tests set `windowBackground`, `backgroundStyle`, `fileNameTemplate`, `alsoCopyImageWhenUploading`, `urlCommandsAllowSilent` and `lastAreaRect` on the world's own defaults suite. The entitlements (project.yml:68-69) are untouched: the same Screen Recording use, through the same `SCShareableContent` and `SCScreenshotManager` calls.

## 8. Tests summary

`Test run with 2352 tests in 195 suites passed` at 5c2cc33 → `Test run with 2380 tests in 197 suites passed`: 28 new `@Test` functions, each counted once, and 2 new suite files (`CoordinatorCaptureSaveTests`, `CoordinatorCaptureSourceTests`). C8 adds a step to an existing test and no function; `CaptureSamples.swift` and `CaptureSourceFakes.swift` hold no tests. With C9: 2381 in 197. `TARGET` alone (`CAPSRC` deferred): 2373 in 196, 2374 with C9. The noise lines are unchanged; the flaky `UploadQueueTests.aSidecarUnwritableDuringThePartsFailsTheJobBeforeComplete` fails about one full run in six, and a run that fails only on it passes on a second.

## 9. Hand checks (short)

The live values never run in the suite: the forwarder's `CaptureTarget.origin` takes a live target, and `live()` builds `AppSettings.shared`, the Keychain store and the notifier. `docs/testing/capture-seams-manual-checklist.md`, written at close-out, checks them for Tim:

1. **The real capture of each kind.** ⌃⇧3, ⌃⇧4 (drag an area) and ⌃⇧2 (click a window), each with `Save and copy image`: one PNG each in the save folder at the right size (`sips -g pixelWidth -g pixelHeight`: the display, the area or the window times the display scale), `Screenshot saved`, the image on the clipboard, a card on the capture's display. With `Add background to window captures` on, the window capture is composed and the other two are not. ⌃⇧6 recaptures the area. `t 'capture-window?action=copy'`: the image only, `Image copied`. A pin of the newest area capture opens over it.
2. **The real selection** (`CAPSRC` only). ⌃⇧1, ⌃⇧4 and ⌃⇧5 open the overlay on every display with the cards left out of the picture; Escape captures nothing; a window click in All-in-One captures that window; a scrolling capture starts its session; Record Screen's overlay and the recording start as before. With Screen Recording turned off for TidyShot (by Tim, in System Settings, and back on after), a capture shows the permission window.

## 10. The design's calls (for Tim to overrule)

1. **Build `CAPSRC` now, as the second task.** By its own lines it is not worth its diff: L effort, eleven files (about +141 −60; built clean in the review, section 12), about 350 test lines, for 4 full and 8 part lines of 34. It is the floor: all 22 lines it defers need it and another seam (`TMPDIRS` 17, `STAGE` 3, `SCROLL` 1, `COVERS` 1), none of which can finish a line without it, and the first of those phases would carry its L diff on top of its own. The design is written and merges with `TARGET` on no shared line. For deferring: no user-visible gain, the token budget from 2026-11-01, and the first consumer phase can carry it. Deferred, the phase is `TARGET` alone: 21 tests, 32 lines marked, 2373 in 196.
2. **`TARGET`'s form**: the internal entry over `CaptureOrigin`, not a value target the engine resolves by id, nor a `CaptureResult` carrying the origin (2.1). It leaves `CAPSRC`'s value target free to land without touching `save`.
3. **C9** (S, no seam, no production change): a width change or the lock toggle arming a disarmed rect, in `SelectionViewArmingTests`. It takes phase-6b:105's arming to its by-hand remainder only; the line stays in part either way.
4. **The `live` handle** on `CaptureDisplay` and `CaptureWindow` (2.2): the engine films the same object; the cost is `CaptureError.notListed` and one guard in `runScrolling`, both unreachable in the app.
5. **C4 runs the real `TextRecognizer`**; the first request after a restart can take about 24 s, inside the one-minute limit. The alternatives are `captureText(at:)` (same cost) or deferring phase-7b:81 to `COPYTEXT`.
6. **recording-r2:351 is part, not deferred** (tests-capture.md CAPSRC.7 item 1): its "captures are blocked while the prompt is up" clause is observable with the fake source and selector, so C8 adds it to the existing held-prompt test rather than a parameterized new test (which would add eight cases).
7. **recording-r1:105 needs `TMPDIRS`, not nothing**: seams.md lists it under `CAPSRC` alone, but both halves come after `recordingCanStart` (+Recording:213). It is the one recording line `TMPDIRS` with `CAPSRC` finishes.
8. **The deferred recording lines join `TMPDIRS` in seams.md** (section 11, item 2), though they carry no mark: their deferral names it as the first blocker. Not joining leaves seams.md's `TMPDIRS` row at 14 lines and understates what it unlocks. Item 2 does not add `STAGE` or a screen lookup for the hand-off's `NSScreen.screens` read (+Recording:496), which every recording line also meets (tests-capture.md CAPSRC.7 item 9); that is the next recording phase's design.
9. **Out-of-date text stays.** phase-2:32 and small-tweaks:13 name a row word that is gone; they are marked on what is still true.
10. **`TARGET` lines that leave a remainder to `CAPSRC`** (coordinator-split:36, phase-6b:66, phase-7c:182) keep naming it even when `CAPSRC` lands in this phase: no test here drives those entry points into a save. Once both land, a later sweep can drive `capturePreviousArea`, `captureFullscreen` and `captureAllInOne` with `choices = [.area(...)]` into the save and tighten the three marks; not counted here.
11. **T10's `cardShows` leg, T9's `cause` and T21** go beyond the judge's twenty tests (tests-capture.md 1.1): the card branch moves an upload-only file to the drag folder (+Upload.swift:653), the offline cause stands in for Wi-Fi off, and the retry leg is its own path.

## 11. Deferred, and what seams.md records

- **`TARGET`, 2 lines**: phase-1:39 (`FOLDER`: the no-folder branch, +Save:244-248, is behind `chooseFolder`'s `NSOpenPanel`, SaveLocation.swift:30-44) and phase-7c:117 (`BGFILL`: `CustomBackgroundStore.shared`, BackgroundFillSource.swift:13).
- **`CAPSRC`, 22 lines**, each by its first blocker (tests-capture.md CAPSRC.1): `TMPDIRS` 17 (recording-r1:102, :105, :122, :124, :196; recording-r2:231, :236, :238, :390, :397, :402, :407, :409, :605, :653; recording-r3:276; recording-r4:217), because `recordingCanStart` makes the container's real `tmp/Recording` (+Recording:213, :249, :354; Recording.swift:50-56) before the first content read (+Recording:214, :253); `STAGE` 3 (phase-6b:75, :77, :79: `runSelfTimer`, +Capture:297-307); `SCROLL` 1 (phase-5:182: the session outcome, +Capture:128-139); `COVERS` 1 (phase-7b:96).
- **Part remainders by seam**: `SCREENS` coordinator-split:36, :42, phase-2:25, :48, phase-6b:66, phase-7c:179; `WORKSPACE` coordinator-split:36; `STATUSMENU` coordinator-split:42, recording-r2:351; `UPLOADFORM` phase-2:33; `EDPLACE` phase-4a:119, :120, phase-7c:187; `PINS` phase-6b:118; `BGPOP` phase-7c:187; `CAPSRC` coordinator-split:36, phase-6b:66, phase-7c:182; `SCROLL` phase-5:78, phase-6a:211, phase-6b:127, :159, phase-7c:182; `SELINT` phase-6a:211, phase-6b:62, :104; `STAGE` phase-6b:159; `TMPDIRS` and `RECCHROME` recording-r2:351. phase-7c:189 and phase-6b:105 leave only checks by hand with no seam.

**seams.md at close-out.** seams.md keeps its rules (seams.md:9-12). The close-out script edits it from this section, and a script that parses its line lists reproduces its current 410 / 182 / 279:

1. Every one of the 68 lines stays under its seam, its entry gaining its CT-4 verdict (`CT-4: full`, `CT-4: in part`, `CT-4: deferred`). The `Shape` lines of sections 3 and 4 say what was built (2.1, 2.2), and section 4's line for recording-r1:105 notes "needs `TMPDIRS` first (CT-4)".
2. Each part line joins the row of every other seam its mark names that does not list it yet, noted "also `<seam>`, in part since CT-4": `SCREENS` gains coordinator-split:42, phase-2:25, :48, phase-6b:66, phase-7c:179 (5); `STATUSMENU` coordinator-split:42; `CAPSRC` coordinator-split:36, phase-6b:66, phase-7c:182 (3); `SCROLL` phase-7c:182, phase-6b:127 (2); `SELINT` phase-6a:211, phase-6b:104 (2); `TMPDIRS` recording-r2:351. Each deferred recording line not yet under `TMPDIRS` joins it, noted "also `TMPDIRS`, deferred in CT-4" (16, call 8). That is 30 new seam slots (14 from part lines, 16 from deferred).
3. The counts, redone by those rules and checked by the same parse: 42 seams; 279 B lines, unchanged; Lines 440; Alone 173; Completes 279; 106 lines need two or more seams (97 before); 15 seams unlock three or fewer, unchanged. The first three seams complete 55 lines (78 before) and the first ten 146 (150 before). Rows that change, as Lines / Alone / Completes, with ties kept in the old order: `CAPSRC` 37 / 5 / 5 (fourth to third); `TARGET` 34 / 20 / 22 (third to fourth); `TMPDIRS` 30 / 7 / 8 (ninth to fifth); `CLOP` 23 / 22 / 23 (fifth to sixth); `SCREENS` 19 / 6 / 11 (eighth to seventh); `SAVEAS` 14 / 7 / 11 (sixth to eighth); `RECCHROME` 14 / 0 / 8 (seventh to ninth); `STATUSMENU` 9 / 5 / 9; `SCROLL` 8 / 2 / 7 (22nd to 17th); `SELINT` 6 / 3 / 6 (25th to 24th); `LOG` stays tenth. Without item 2's 16 deferred joins (call 8 overruled): Lines 424, Alone 174, 105 lines need two or more, `CAPSRC` 37 / 6 / 6, `TMPDIRS` 14 / 7 / 8 (ninth), first three 56, first ten 146. The section headers, the summary, the multi-seam section (for example `CAPSRC` + `RECCHROME` goes from 8 lines to 0 and `CAPSRC` + `RECCHROME` + `TMPDIRS` from 0 to 8; `SCREENS` + `TARGET` is new with 3; `CAPSRC` + `SELINT` goes from 1 to 2) and the three-or-fewer section are regenerated, and the script asserts the three sums.

lines-capture.md's "Other seams" column lists seams.md's own "also" notes; seams.md's Alone column counts the line lists as written, with landed seams kept, so the two are not the same number. seams.md keeps its own rule.

## 12. Built notes

From the design's review (`.superpowers/sdd/ct4/judge.md`, sections 1.3 and 5). The `TARGET` diff of section 2.1, `CaptureSamples` and T1 to T4 were built and run by the `TARGET` designer in a scratch worktree at 5c2cc33, not committed and removed after the run: clean under Swift 6, `CoordinatorCaptureSaveTests` alone (4 tests) and the whole suite `Test run with 2356 tests in 196 suites passed` (2352 + 4). The judge did not rebuild it; it checked the before-text of both files against the tree line for line and recomputed T15's canvas sizes from `BackgroundLayout.make` (BackgroundLayout.swift:20-47). The judge did not compile the `CAPSRC` diff of section 2.2 (the review below did): it checked its before-text against the tree and every reader of `SCDisplay`, `SCWindow`, `SCShareableContent`, `Selection`, `AllInOneChoice` and `AppCoordinator.display(under:in:)`, by reading only. Not run anywhere: T5 to T21, C1, C2, C4, C6 to C9 and C8's step. T1 and T2 ran in the review in the form tests-capture.md gives them; T3 and T4 ran only in the designer's earlier form (rule 8's thumbnail wait and the extra pixel reads were added after that run). Line numbers in this design were re-read at 5c2cc33 where they differ from the judge's (`connectedDisplay` +Recording:596, `recordingDisplay` :604, `display(under:in:)` +Capture:398, `SC:36`, :49, :227, :260). **The design's review** (`.superpowers/sdd/ct4/review-facts.md`, section 1) applied both diffs (sections 2.1 and 2.2, less the `live()` doc rewrite of Env:57-62; production 12 files, +184 −78 together by `diff` against 5c2cc33, `TARGET` about +43 −18 and `CAPSRC` about +141 −60), the support of sections 3.1 to 3.3 verbatim, the checks added to `CoordinatorWorldTests.aCoordinatorOverTheWorldKeepsToTheWorld` and the lock test, and four catalogue tests as tests-capture.md gives them (T1, T2 with the held upload, C3 with the held `FakeSelector`, C5) to a scratch copy of 5c2cc33. It compiled clean on the first pass, `** TEST BUILD SUCCEEDED **`, with no warning from a changed or new file. The four suites with `-only-testing` (`CoordinatorCaptureSaveTests`, `CoordinatorCaptureSourceTests`, `CoordinatorWorldTests`, `CoordinatorCaptureTests`): `Test run with 6 tests in 4 suites passed after 0.212 seconds.` The whole suite once: `Test run with 2356 tests in 197 suites passed after 57.866 seconds.` (2352 + 4 tests, 195 + 2 suites), noise only. A Release build: `** BUILD SUCCEEDED **`, with the one known `appintentsmetadataprocessor` warning. Every before-text and file:line of sections 2.1 and 2.2 matched the tree and every edit applied as one exact match. **For the plan:** test bodies come from `tests-capture.md`; five fake members no catalogue test uses (`FakeSelector.answerAllInOne(_:)` and its held All-in-One branch, `FakeSelector.overlays`, `FakeSelector.frozen`, `FakeCaptureSource.scale`, a non-nil `pointerDisplayID`) are left out of the fakes unless a test the plan writes needs one; and the compile-and-fix budget covers the tests the review did not build (T3 to T21, C1, C2, C4, C6 to C9 and C8's step); a fix that widens section 2.1 or 2.2 stops the task, which reports. The close-out adds the branch's suite line and Release build, the marks made, the seams.md edit and `docs/testing/capture-seams-manual-checklist.md`.

Built on `capture-seams` from the plan `docs/superpowers/plans/2026-11-01-capture-seams.md`: the full suite `Test run
with 2380 tests in 197 suites passed` (the baseline's 2352 tests in 195 suites, and 28 tests in two new suite files;
C8 is a step in an existing test and C9 was not built) and the Release build `** BUILD SUCCEEDED **` with no `error:`
or `warning:` line from the compiler or the linker. 44 lines carry new or extended marks, 23 in full and 21 in part
(40 first marks, and the CT-2 marks of phase-4a:119, phase-4a:120, phase-6b:118 and phase-7c:187 extended);
recording-r4:217's mark was reworded with no test, and the other 23 deferred lines stay unmarked. seams.md has section
11's edit: 42 seams, Lines 440, Alone 173, Completes 279, 30 new seam slots (14 from part lines, 16 from deferred
recording lines joining `TMPDIRS`), 106 lines that need two or more seams and 15 seams that unlock three or fewer;
`CAPSRC` is third, `TARGET` fourth and `TMPDIRS` fifth, and the first ten seams complete 146 lines. The hand checks of
section 9 are `docs/testing/capture-seams-manual-checklist.md`, for Tim.

Built differently from the plan, the design and the catalogue, from the task reports: T4
(`copyOnlyPutsTheImageOnTheClipboardAndNothingElse`) and T18 (`copyAndUploadOfAWindowCarryTheComposedImage`) store a
save folder before their copy-only save and check that the folder stays empty, where the catalogue's T4 saves with no
folder stored and checks `currentURL` is nil and design rule 2 says "stores a folder first or is copy-only"; with no
folder stored, a regression that dropped the copy-only branch or moved it after `persist` would reach
`SaveLocation.ensureFolder` and build a real folder panel rather than fail (plan decision D48, from the fix rounds of
Tasks 1 and 2; the design and the catalogue are unchanged, the stricter form wins). Tasks 1 to 3 otherwise built the
brief's steps verbatim, with no drift from the files they quoted; the other departures from the catalogue and the
design (the helpers, `UploadFailureCause`, `Canvas`, the five fake members left out, `persist` moving 6 lines, the
`live()` doc rewrite) are plan decisions D5 to D30. No hand check was run; they are Tim's.
