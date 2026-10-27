# TidyShot Screen Recording R3, Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Two Settings toggles, both off by default, each with a button on the recording bar to turn it on or off mid-recording. Click highlights draw a short ring at each left and right click (yellow for left, blue for right and control-click), and a drag keeps its ring until the button comes up. The webcam bubble shows the chosen camera in a round window that the recording films. It can be dragged anywhere in the recorded area, it comes in Small, Medium or Large, and its last place and size are remembered. Neither feature appears in a window recording, and the camera prompt is never filmed.

**Architecture:** `docs/superpowers/specs/2026-10-24-tidyshot-screen-recording-r3-design.md` is the full specification: behaviour, types, strings, constants, settings keys and tests. R1's design (`2026-10-21-tidyshot-screen-recording-design.md`) and R2's (`2026-10-23-tidyshot-screen-recording-r2-design.md`) hold wherever R3's does not change them. When this plan and the R3 design disagree, the design wins; stop and ask if it is unclear.
- **Pure decisions.** `ClickHighlightRule`, `ClickRingTiming`, `BubblePlacement`, `CameraRunState`, `CameraChoice`, `BubbleButtonState`, `CameraNote`, `CameraLossTracker`, `RecordingSettingsLayout`, `RecordingPanelLayout.Bar`, `RecordingExclusions`' filter sets, `RecordingExtrasPlace`, `RecordingNoticeOrder`, the prompt steps and `GIFPaletteBuilder.build(reserving:)` decide everything that can be decided without a screen, a camera or a mouse event, and are tested that way.
- **Thin shells.** `ClickRingOverlay`, `ClickMonitor`, `WebcamBubblePanel` and `CameraSession` are AppKit and AVFoundation shells over the pure parts. `ClickHighlighter` joins the monitor, the rule and the overlay behind two protocols, so it is tested with fakes.
- **One owner.** `RecordingExtras` owns, for one area or fullscreen recording, the bubble, the camera session, the ring overlay and the click monitors. `record()` makes it and closes it in a `defer`. `RecordingScreenChrome` holds it, so the bar's buttons reach it, and its `close` closes it too. Window recordings get none.
- **`RecordingController`** (in this plan, "the controller") owns the two bar states as it owns mute. It learns from the driver which of the two windows the filter films, and reports what the notes after Stop need in `extrasSummary`.
- **The coordinator split** (`2026-10-23-coordinator-split-design.md`, section 6) places R3's coordinator code: the prompt state and the capture refusal rule in `AppCoordinator.swift`; the camera prompt, the camera resolve, `RecordingExtras` and the notes in `AppCoordinator+Recording.swift`.

**Tech Stack:** Swift 6 language mode with default `MainActor` isolation and `NonisolatedNonsendingByDefault`, AppKit (`NSPanel`, `NSEvent` global and local monitors), Core Animation (`CAShapeLayer`, `CABasicAnimation`, `CATransaction`), AVFoundation (`AVCaptureSession`, `AVCaptureDeviceInput`, `AVCaptureVideoPreviewLayer`, `AVCaptureDevice.DiscoverySession`, `systemPreferredCamera`), ScreenCaptureKit (`SCContentFilter(display:excludingApplications:exceptingWindows:)`), SwiftUI Settings, Swift Testing, XcodeGen 2.46.

Work happens on the branch `recording-r3`, cut from `main` at 8e31c09 (R2 merged). The R3 design and its probe sources are committed (534a8a1, 05ca5af); this plan is `docs: R3 plan`. Line numbers are at 05ca5af; once an earlier task has moved a member, find it by name.

## Probes Tim runs

Every probe is Tim's: each needs his screen, his clicks, his cameras or a permission. Nobody else runs them. The session running this plan (not `RecordingController`) asks Tim to run each one as soon as the task it waits on has landed, and writes his results into the design's Probes section with the date and the Mac. Build lines are the design's (Probes): `xcrun swiftc -O -target arm64-apple-macos26.0 -o /tmp/<name> <name>.swift`, with `-Xlinker -sectcreate -Xlinker __TEXT -Xlinker __info_plist -Xlinker r3-camera-info.plist` for `r3-camera-list.swift` and `r3-bubble-camera.swift`.

| Probe | What Tim runs | Records or opens | Ready after | Settles |
|---|---|---|---|---|
| P1 | `r3-clicks.swift monitor 60`, then `ring 60` | nothing | now | G1 |
| P2 | `r3-clicks.swift builtin /tmp/r3-builtin.mp4 12`, then `window <id>` | the screen | now | nothing (informational; see Gates) |
| P3, recording | `r3-clicks.swift record-ring /tmp/r3-ring.mp4 60`, clicking about every 5 s with drags and right-clicks | the screen | now | G2 (the `overlay windows in shareable content N of M` line) |
| P3, GIF | Task 3's harness on `/tmp/r3-ring.mp4` at 15 and 10 fps, 1280 px, with and without the reserved colours | nothing (reads the MP4) | Task 3 | the reserved colours; 40 pt at 0.5 px per point |
| P4 | the Debug build with `-ClickMonitorSpike YES` | nothing | Task 1 | G1 |
| B1 | `r3-bubble-filter.swift`, then `r3-bubble-filter.swift output /tmp/r3-filter.mp4` | screen frames, then a file | Task 1 | G2 |
| C1 | `r3-camera-list.swift 30`, plugging the Brio in and out and bringing the iPhone near | nothing | now | G3 |
| C2 | `r3-bubble-camera.swift brio 720 120`, `iphone 720 120`, then each at `1080` | the camera | Task 1 | G4, G5 |
| C3 | the Debug build with `Show webcam bubble` on, after Tim runs `tccutil reset Camera io.tky.tidyshot` | the camera prompt | Task 7 | a hand check |

P3's GIF half reads a file Tim recorded and records nothing, so the session may run Task 3's harness on it once the file exists.

## Gates

A gate that trips holds only the steps named here. The rest of its task and the later tasks go on, held steps stay unchecked until the design is amended and Tim says to go on, and the branch is not offered for merge while a step is held.
- **G1, the click monitor** (P1, P4). It trips if the global monitor misses clicks TidyShot must see, or raises a prompt in the sandbox. It holds Task 10's "Install the monitors" step (the `ClickMonitor` class) and Task 12's step that reaches the highlighter from the bar. `ClickHighlightRule`, `ClickRingTiming`, the overlay, the `ClickEventSource` protocol, `ClickHighlighter` with its fakes, and the bar button land. `RecordingExtras` takes its click source from `record()` (Task 12), so it compiles without `ClickMonitor`; while G1 holds, `record()` passes the stand-in Task 12 names. The design goes back to Tim (an event tap needs Input Monitoring; `showMouseClicks` cannot give two colours).
- **G2, windows made at the start** (P3's log line, B1's `orderOut` case). It trips if a fully transparent, empty window is not listed in shareable content, or a window ordered out and back is not filmed again. It holds Task 12's "Wire the start" step and the bubble and ring hand checks. Task 8's filter code and its pure sets land unchanged: the filter is the same for the fallback the design names (`updateContentFilter` when a bar button turns a feature on), which waits on B1's output variant. If neither holds, the bar buttons go and the design goes back to Tim.
- **G3, the camera picker** (C1). It holds nothing. If C1 lists the Brio or the iPhone under another device type, or `systemPreferredCamera` gives a Desk View camera or nil while cameras are listed, Task 6's `LiveCameraDevices.deviceTypes` and `preferred()` change to match before Task 12, and the change is listed for Tim.
- **G4, the camera's loss** (C2). It holds nothing. Task 11 treats every error, interruption and stop notification as a loss, except stops TidyShot asked for, and Task 13 uses the design's note. If C2 shows a notification that never fires, one that fires with no loss, or a session that does not recover on its own, the handling and the note's wording go to Tim.
- **G5, the budget** (C2 and the hand checks). It holds nothing. A number over the design's budget goes to Tim; the sizes and the format do not change.
- **P2** holds nothing. If it answers all four of its questions yes (design, Probes), the result goes to Tim before Task 14, because it reopens the design's call 2.
- Task 14 runs after every held step has landed, or records in the Built notes any that Tim chooses to ship without.

## Global Constraints

- **Earlier constraints still apply.**
  - Minimum macOS 26.0, Swift 6 with MainActor by default and `NonisolatedNonsendingByDefault`, App Sandbox, XcodeGen, Swift Testing, credentials only in the Keychain.
  - KeyboardShortcuts is the only Swift package. No GPL code is read or copied: macshot, the Clop app, gifsicle, ffmpeg and gifski are off limits as sources. The rings and the bubble are written from Apple's documentation and headers.
  - R2's decisions stand (R2 design, Decided 2026-10-23 and Decided 2026-10-24, 1 to 11): notices held from a recording's count-in until its Stop, captures refused while a permission prompt is open, and TidyShot's own GIF encoder at 15 fps by default with the long side capped at 1280 px.
- **One new entitlement, three Info.plist keys, no new package** (Task 7, through `project.yml`): `com.apple.security.device.camera`; `NSCameraUsageDescription`, `NSCameraUseContinuityCameraDeviceType` and `NSCameraReactionEffectGesturesEnabledDefault`. Nothing else in the entitlements or the Info.plist changes.
- **Consent and privacy.**
  - The camera is never opened without access granted, and the system prompt is never filmed, never in a count-in and never in a screenshot: it shows only before the capture lock, or from Settings when no capture or recording runs.
  - The camera's microphone is never opened. Nothing about muting changes.
  - No log line holds a position, a click count or a frame.
- **Never lose a recording.** A camera failure, a missing camera or a window the filter cannot find never fails a recording; it records without that feature and says so after Stop.
- **Nothing of R3 outlives a recording, or a start that gave up.** Every exit of `record()` closes `RecordingExtras`, and `RecordingScreenChrome.close` closes it too.
- **Off the main actor.** Only `CameraSession`'s work runs off it, on its one serial queue (`io.tky.tidyshot.camera`). Every window, monitor, layer, the controller and the settings are MainActor. The pure types are `nonisolated` and `Sendable`.
- **The coordinator split's conventions.**
  - New stored state goes in the class body in `AppCoordinator.swift`, in the Recording state group: `askingPermission` replaces `isAskingMicrophone`, and `cameras` joins the Collaborators beside `microphones`.
  - New members start `private` in their area's file.
  - One new entry point for code outside the family: `requestAccessFromSettings(_:)`, for `CaptureSettingsView`. Task 14's surface check lists it.
- **Exact strings, defaults, sizes, colours, timings, symbols and settings keys** come from the design.
- **Tests** use Swift Testing and never need Screen Recording, camera or microphone access, a real mouse event or a display. The cameras, the access status, the chrome, the driver, the click source and the ring drawing are faked; no test creates an `AVCaptureDeviceInput`. Run with:
  ```bash
  xcodegen generate && xcodebuild test -project TidyShot.xcodeproj -scheme TidyShot -destination 'platform=macOS' -derivedDataPath .build 2>&1 | grep -E "Test run with|error:|TEST"
  ```
  The baseline after R2's merge is 1633 tests in 153 suites. When coreaudiod stalls on Tim's Mac the suite takes about 126 s instead of about 36 s; that is not a failure. The Release build is `xcodebuild -project TidyShot.xcodeproj -scheme TidyShot -configuration Release -derivedDataPath .build-rel build`.
- **Hand checks are Tim's.** Implementers and reviewers do not run anything that records the screen, opens the camera or the microphone, or plays sound, and never open or change privacy settings or run `tccutil`. Each task lists its hand checks; Task 14 puts them in the checklist, and each task's report says they were not run.
- **Commits.** Commit after every task with the message the task gives and no attribution lines. Never push and never switch branches.

## Gaps this plan fills

Each is this plan's call. Most fill what the design leaves open. Gaps 1, 2 and 5 change signatures the design gave, and Task 12's `show(at:)` and `place(at:)` replace its `show(in:)` and `place(in:)`; the design was amended to match in the commit `docs: R3 plan review fixes`, so the rule that the design wins still holds. Task 14 records every gap in the design's Built notes, and the PR flags them.
1. **The resolve takes no toggle.** `CameraChoice.resolveAtStart(stored:access:devices:preferred:)` leaves out the design's `bubble:` argument. It resolves the camera for every start, toggle on or off, so the bar can turn the bubble on, and `CameraNote` decides whether the start's note posts.
2. **The window drop takes the source.** `CameraChoice.forRecording(_:source:)` takes the hand-off's `RecordingSource` in place of the target, as `CaptureTarget` holds ScreenCaptureKit objects tests cannot make. `.window` drops the camera and its note.
3. **One R3 snapshot per recording.** `record()` reads `settings.recordingOptions` for `RecordingExtras` before the hand-off, because the bubble shows from the count-in. The hand-off still reads `settings.recordingOptions` after the count-in, as R2 does, then copies the two toggles and the size from `extras.options` and sets `cameraID` and `cameraName` from the window-filtered `CameraStart`, so the bubble on screen and the run agree. Without extras (a window recording) the hand-off sets the two toggles false and the size to `.medium`, and leaves `cameraID` and `cameraName` nil, so the options say neither feature ran.
4. **Filmed features.** `FilmedFeature` (`.bubble`, `.highlights`) names the two windows. The chrome gives `filmedWindowNumbers: [FilmedFeature: CGWindowID]` and takes `setFilmed(_ features: Set<FilmedFeature>)`. The controller maps the driver's set of window numbers to features; a feature with no window number counts as missed.
5. **Who installs the monitors.** `RecordingChrome.setHighlights(_ on: Bool, monitoring: Bool)`: `on` is the button, `monitoring` installs or removes the monitors. The controller passes `monitoring: on && firstFrame != nil`, and again `true` at `.recordingStarted`, so the rule "monitors only from the first frame" is the controller's and is tested there.
6. **What the notes need.** The controller's `extrasSummary` (`bubbleWanted`, `highlightsAtStart`, `highlightsUsed`, `missed`) is read in `record()` after `recorder.run` returns. `Recording.highlightedClicks` carries `highlightsUsed` to the GIF conversion.
7. **The recording's clock for R3.** `RecordingExtras` takes `elapsed: () -> TimeInterval`, which reads the controller's new `elapsedTime`, for the camera's log lines and the loss note's `<m:ss>`. The controller logs the two toggles itself.
8. **Settings prompts.** `requestAccessFromSettings(_:)` asks only when `settingsPromptStep` says `.ask`: `recordingPhase` is `.idle`, `isCapturing` is false and no other prompt is open. Otherwise it logs and returns. With a prompt open the line is `Recording: <microphone|camera> prompt from Settings deferred, the <microphone|camera> prompt is open`, naming the open one; else it is `Recording: <microphone|camera> prompt from Settings deferred, a capture is running`.
9. **Prompt order and logs.** `startPrompts(microphone:camera:)` gives the prompts a start shows, microphone first. Each answer logs `Recording: <microphone|camera> access allowed|refused at the prompt`, or `… at the Settings prompt` from Settings. A start the lock then refuses logs `Recording: not started after the <microphone|camera> prompt, another capture was running`, naming the last prompt shown.
10. **The local monitor.** A local mouse-down draws only on the bubble. Local drags and ups pass from any TidyShot window, so a held ring is still matched by button and never stays on screen.
11. **A second down.** A down for a button whose ring is still held ends that ring first.
12. **The preferred camera.** `LiveCameraDevices.preferred()` is `systemPreferredCamera` when its device type is one of the three listed, else the first listed camera, else nil (G3 checks it).
13. **The recorded rects.** `RecordingExtrasPlace` holds the bubble's rect (AppKit), the ring area (CG, nil for fullscreen), the display's CG frame and its screen's AppKit frame, made by one pure function.
14. **When the place is stored.** `BubblePlacement.storedInsets(after:frame:recorded:)` gives insets only after `.dragEnded` and `.sizeStepped`, never after `.start` or `.reclamp`.
15. **The camera format.** When `.hd1280x720` cannot be set, `CameraFormat.pick` takes the format closest to 1280×720 in pixel count among those that reach 30 fps, the smaller on a tie; with none it keeps the active format and sets no frame duration.
16. **The ring's colours** live in `ClickRingColour`, with `reservedGIFColours` (yellow, blue, black) for the palette, and `GIFMaker.make` gains `reserving:`.
17. **The P4 spike** is `ClickMonitorSpike`, Debug only, launched with `-ClickMonitorSpike YES`.

---

### Task 1: Probe changes and the click monitor spike

**Files:**
- Modify in `docs/superpowers/research/recording-probes/`:
  - `r3-bubble-filter.swift`: the content reads (:43, :69) and an output variant;
  - `r3-bubble-camera.swift`: the content view's drag (:20-25);
  - `README.md`: the R3 section.
- Create `TidyShot/Recording/Clicks/ClickMonitorSpike.swift` (Debug only).
- Modify `TidyShot/App/AppDelegate.swift`: the `#if DEBUG` block (:44-49).

**Produces:** DEBUG `enum ClickMonitorSpike { static let mask: NSEvent.EventTypeMask; static func run() async }`.

**Steps:**
- [ ] B1 (design, Probes): both content reads become `SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)`, as TidyShot's are. Add an `output <file.mp4>` argument after the seconds. With it, the stream gets an `SCRecordingOutput` (H.264 `.mp4`, as `ScreenRecordingDriver.outputConfiguration` makes it) before `startCapture`; after `updateContentFilter` the probe prints `recordedDuration` once a second for 3 s, and at the end the file's duration and its video sample count, so an output that stopped writing shows. Without `output` it behaves as now.
- [ ] C2 (design, Probes and The window): the content view returns true from `acceptsFirstMouse(for:)` and false from `mouseDownCanMoveWindow`. `mouseDown` keeps the double-click size step; otherwise it records the pointer's screen point and the window's origin. `mouseDragged` moves the window by the pointer's offset, clamped so the whole bubble stays inside its screen's `visibleFrame`. `performDrag(with:)` is gone.
- [ ] Write `ClickMonitorSpike.run()` for P4, all inside `#if DEBUG`:
  - log `Click spike: AXIsProcessTrusted <true|false>, CGPreflightListenEventAccess <true|false>` (neither call prompts);
  - show a titled 240 × 120 pt `NSPanel` named `Click spike` at the main screen's centre, to click on a TidyShot window;
  - install `NSEvent.addGlobalMonitorForEvents(matching: mask)` and `addLocalMonitorForEvents(matching: mask)` (returning the event), `mask` being `[.leftMouseDown, .leftMouseUp, .leftMouseDragged, .rightMouseDown, .rightMouseUp, .rightMouseDragged]`;
  - log each event as `Click spike: <global|local> <type>, delay <ms> ms, window <yes|no>, frontmost <bundle id>`, the delay being `ProcessInfo.processInfo.systemUptime − event.timestamp`, with no position;
  - after 60 s remove both monitors, close the panel and log `Click spike: done`;
  - log through `Logger(subsystem: "io.tky.tidyshot", category: "ClickSpike")` with `privacy: .public`.
- [ ] In `AppDelegate`'s `#if DEBUG` block, beside the R1 spike: `if UserDefaults.standard.bool(forKey: "ClickMonitorSpike") { Task { await ClickMonitorSpike.run() } }`.
- [ ] The probes README's R3 section: B1's `output` argument and C2's drag, with the "Before it runs" sentences gone, and a P4 line: `open .build/Build/Products/Debug/TidyShot.app --args -ClickMonitorSpike YES`, read with `/usr/bin/log show --last 2m --style compact --predicate 'process == "TidyShot"' | grep "Click spike"`.
- [ ] Check: both probes compile with the README's lines and `-o` outside the repository (compile only; do not run them). Run the full suite. Build Release; `strings .build-rel/Build/Products/Release/TidyShot.app/Contents/MacOS/TidyShot | grep -c ClickMonitorSpike` prints 0.
- [ ] Commit: `chore: R3 probe changes and the click monitor spike`.

Then the session asks Tim to run P1, P2, P3's recording, P4, B1 (both forms), C1 and C2.

### Task 2: The click rule and the ring's timing

**Files:**
- Create in `TidyShot/Recording/Clicks/`: `ClickHighlightRule.swift`, `ClickRingTiming.swift`.
- Tests: create `TidyShotTests/ClickHighlightRuleTests.swift` and `ClickRingTimingTests.swift`.

**Produces** (all `nonisolated` and `Sendable`):
- `enum ClickButton: Hashable { case left, right }`.
- `enum ClickRingColour: Equatable { case yellow, blue }`:
  - `var components: (red: CGFloat, green: CGFloat, blue: CGFloat)`: sRGB (1.0, 0.8, 0.0) and (0.04, 0.52, 1.0);
  - `var gifColour: GIFColour`: (255, 204, 0) and (10, 133, 255);
  - `static let reservedGIFColours: [GIFColour]`: yellow, blue, then black (0, 0, 0).
- `struct ClickEvent: Equatable`:
  - `enum Phase: Equatable { case down, dragged, up }`; `var phase: Phase`, `var button: ClickButton`, `var isControl: Bool`, `var point: CGPoint` (CG global points);
  - `static func make(type: NSEvent.EventType, modifierFlags: NSEvent.ModifierFlags, locationInWindow: CGPoint, windowFrame: CGRect?, primaryMaxY: CGFloat) -> ClickEvent?`: nil for any type but the six; `windowFrame` nil for a global event.
- `struct ClickRing: Equatable { var button: ClickButton; var colour: ClickRingColour; var point: CGPoint }`, the point in overlay points from the display's top-left (CG orientation).
- `enum ClickRingChange: Equatable { case begin(ClickRing), move(ClickButton, to: CGPoint), end(ClickButton) }`.
- `struct ClickHighlightRule: Equatable`:
  - `init(displayFrame: CGRect, area: CGRect?)`, both CG global points, `area` already inside the display; `var recordedRect: CGRect` is `area ?? displayFrame`;
  - `private(set) var held: [ClickButton: ClickRing]`;
  - `mutating func handle(_ event: ClickEvent) -> [ClickRingChange]`;
  - `mutating func endAll() -> [ClickRingChange]`: an `.end` for each held ring, left then right, and `held` empty;
  - `static func screenPoint(locationInWindow: CGPoint, windowFrame: CGRect?) -> CGPoint`: the location for nil, the frame's origin plus the location otherwise (Cocoa points);
  - `static func cgPoint(fromCocoa point: CGPoint, primaryMaxY: CGFloat) -> CGPoint`: `y = primaryMaxY − point.y`;
  - `static let notFilmedNotice = RecordingNotice(title: "Recorded without click highlights", body: "The click highlights could not be filmed.")` and `static func noteAfterStop(onAtStart: Bool, missed: Bool) -> RecordingNotice?`: the notice only when both hold.
- `enum ClickRingTiming`:
  - `static let grow: TimeInterval = 0.15`, `fade: TimeInterval = 0.35`, `startScale: CGFloat = 0.5`, `fadeScale: CGFloat = 1.3`;
  - `static func fadeStart(down: TimeInterval, up: TimeInterval) -> TimeInterval`: `max(up, down + grow)`;
  - `static func visibleDuration(down: TimeInterval, up: TimeInterval) -> TimeInterval`: `fadeStart − down + fade`;
  - `static func framesShowing(start: TimeInterval, duration: TimeInterval, fps: Int) -> Int`: the frames `i` with `start ≤ i / fps < start + duration`.

**The rule** (design, Click highlights, Seeing clicks and Where rings draw):
- A down's colour is blue for a right button, or a left button with `isControl`; yellow otherwise. Its button is the event's (a control-click is `.left`, so its `leftMouseUp` ends it).
- A down inside `recordedRect` (`CGRect.contains`) gives `.begin` at `point − displayFrame.origin`; outside, nothing. A down for a button already held gives `.end` of the old ring first (Gap 11).
- A drag of a held button gives `.move` to the point clamped to `recordedRect` (each coordinate to its range), in overlay points. An up of a held button gives `.end`, wherever it lands. A drag or an up with no held ring gives nothing.

**Steps:**
- [ ] Write the design's `ClickHighlightRuleTests` and `ClickRingTimingTests` and see them fail. Add:
  - `ClickEvent.make`: each of the six types maps to its phase and button, `.control` sets `isControl`, `.keyDown` gives nil; a global event (no window frame) at Cocoa (100, 200) with `primaryMaxY` 1410 gives CG (100, 1210); a local event at (30, 40) in a window at (500, 300) gives CG (530, 1070);
  - the flip on a second display left of and below the primary: Cocoa (−100, −500) with `primaryMaxY` 1410 gives CG (−100, 1910);
  - a second down of a held button gives `[.end, .begin]`;
  - `notFilmedNotice` and `noteAfterStop` for the four cases;
  - `framesShowing` for a 0.5 s ring at starts 0, 0.02 and 0.049 s: 5, 7, 10, 15 and 30 frames at 10, 15, 20, 30 and 60 fps, each within one.
- [ ] Implement both files.
- [ ] Run the full suite.
- [ ] Commit: `feat: click highlight rule and ring timing`.

### Task 3: The ring colours in GIF palettes

**Files:**
- Modify:
  - `TidyShot/Recording/GIF/GIFPalette.swift`: `GIFPaletteBuilder.build` (:106);
  - `TidyShot/Recording/GIFMaker.swift`: `make` (:34) and `makePalette` (:84-104);
  - `TidyShot/Recording/Recording.swift`: a new field beside `muteIntervals` (:27);
  - `TidyShot/App/AppCoordinator+Recording.swift`: `makeGIF`'s `make` closure (:509-513);
  - tests support: `TidyShotTests/Support/GIFBlocks.swift`, whose `parse` gains the global table's colours.
- Tests: add to `GIFPaletteBuilderTests` and `GIFMakerTests`.

**Consumes:** Task 2's `ClickRingColour.reservedGIFColours`.

**Produces:**
- `GIFPaletteBuilder.build(reserving reserved: [GIFColour] = []) -> GIFPalette`: the reserved colours first, in order and exactly; the variance split fills at most `255 − reserved.count` more entries, dropping any that equal a reserved colour. With `[]` it is R2's `build()`, entry for entry.
- `GIFMaker.make(from:to:fps:maxSide:reserving: [GIFColour] = [], freeBytes:progress:)`, which passes `reserving` to the palette pass.
- `Recording.highlightedClicks: Bool = false`: highlights were on at some point after the first frame (Gap 6). Task 9 sets it.
- `GIFBlocks.GIFFile.globalTable: [GIFColour]`.

**Steps:**
- [ ] Write the tests and see them fail:
  - `GIFPaletteBuilderTests` (design, Tests): with `reservedGIFColours` over a 256-step gradient frame, the palette holds 255 colours and its first three are yellow, blue and black exactly; `nearest` gives index 0 for (255, 204, 0) and 1 for (10, 133, 255) when no sampled pixel had either; a frame of only yellow pixels gives no second yellow entry; every R2 test runs unchanged on `build()`.
  - `GIFMakerTests`: a GIF made from `VideoFixtures.makeMP4` with `reserving: ClickRingColour.reservedGIFColours` has yellow, blue and black as the first three entries of its global table, read with `GIFBlocks.parse`; R2's `GIFMakerTests` pass unchanged with no `reserving`.
- [ ] Implement the builder change and `make(reserving:)`. `GIFConversion` is unchanged: `makeGIF`'s `make` closure passes `reserving: recording.highlightedClicks ? ClickRingColour.reservedGIFColours : []`.
- [ ] Run the full suite.
- [ ] Write P3's GIF harness (design, P3) in a work folder outside the repository, not committed: a `main.swift` that calls `GIFMaker.make(from:to:fps:maxSide:reserving:freeBytes:progress:)` on a given MP4 at a given fps, 1280 px, with or without the reserved colours, compiled with `TidyShot/Recording/GIFMaker.swift`, `TidyShot/Recording/GIF/*.swift` and stubs for what they reference elsewhere, as R2's trim harness was. Note its build line for the design's P3 entry. Once Tim has recorded `/tmp/r3-ring.mp4`, the session may run it (it records nothing) and gives Tim the GIFs to judge.
- [ ] Commit: `feat: reserve the click ring colours in GIF palettes`.

### Task 4: Bubble placement and the camera's run state

**Files:**
- Create in `TidyShot/Recording/Bubble/`: `BubblePlacement.swift`, `CameraRunState.swift`.
- Tests: create `TidyShotTests/BubblePlacementTests.swift` and `CameraRunStateTests.swift`.

**Produces** (all `nonisolated` and `Sendable`):
- `enum BubbleSize: String, CaseIterable { case small, medium, large }`:
  - `init(stored: String)`: anything but the three raw values reads as `.medium`;
  - `var diameter: CGFloat`: 120, 180 and 260;
  - `var next: BubbleSize`: small → medium → large → small;
  - `var title: String`: `Small`, `Medium`, `Large`.
- `struct BubbleInsets: Equatable { var right: CGFloat; var bottom: CGFloat }`, `static let standard` (16, 16) and `static func reading(_ value: Double) -> CGFloat`: a negative or non-finite value reads as 16.
- `enum BubblePlacement` (AppKit points, y up):
  - `static func frame(recorded: CGRect, size: BubbleSize, insets: BubbleInsets) -> CGRect`: origin `(recorded.maxX − insets.right − d, recorded.minY + insets.bottom)`, then `clamp`;
  - `static func clamp(_ frame: CGRect, into recorded: CGRect) -> CGRect`: the whole bubble inside; in a dimension where `recorded` is smaller than the bubble, centred on it;
  - `static func drag(startFrame: CGRect, from start: CGPoint, to current: CGPoint, in recorded: CGRect) -> CGRect`: moved by `current − start`, then clamped;
  - `static func step(_ frame: CGRect, to size: BubbleSize, in recorded: CGRect) -> CGRect`: the new diameter about the same centre, then clamped;
  - `static func insets(of frame: CGRect, in recorded: CGRect) -> BubbleInsets`: `recorded.maxX − frame.maxX` and `frame.minY − recorded.minY`;
  - `enum Move: Equatable { case start, reclamp, dragEnded, sizeStepped }` and `static func storedInsets(after move: Move, frame: CGRect, recorded: CGRect) -> BubbleInsets?`: `insets(of:in:)` after `.dragEnded` and `.sizeStepped`, nil after `.start` and `.reclamp` (Gap 14).
- `struct CameraRunState: Equatable` (design, The camera session):
  - `enum Event: Equatable { case runtimeError, wasInterrupted, interruptionEnded, didStopRunning, didStartRunning, deviceDisconnected, deviceConnected }`;
  - `enum Change: Equatable { case none, lost, back, rebuild }`;
  - `private(set) var wantsOn = false`, `generation = 0`, `isLost = false`, `rebuildPending = false`;
  - `mutating func request(_ on: Bool) -> (generation: Int, rebuild: Bool)`: sets `wantsOn`, bumps `generation`; turning on clears `isLost` and returns `rebuild: true` once when a reconnect waited (`rebuildPending`);
  - `func stopsAfterStart(generation: Int) -> Bool`: true when `generation` is not the latest or `wantsOn` is false;
  - `mutating func handle(_ event: Event) -> Change`: the four loss events give `.lost` once while `wantsOn` and not lost; `interruptionEnded` and `didStartRunning` give `.back` while `wantsOn` and lost; `deviceConnected` gives `.rebuild` while `wantsOn`, else sets `rebuildPending`; everything else `.none`.

**Steps:**
- [ ] Write the design's `BubblePlacementTests` and `CameraRunStateTests` and see them fail. Use a recorded rect (0, 0, 1000, 800): the default frames are (864, 16, 120, 120), (804, 16, 180, 180) and (724, 16, 260, 260); a 100 × 100 rect centres a Medium bubble at (−40, −40); a drag of +500 pt from (804, 16) stops at x 820; the default Small bubble stepped to Medium keeps its centre (924, 76) and is then clamped to (820, 0, 180, 180). Add:
  - `BubbleSize(stored:)` for each raw value, `"huge"` and `""`; `BubbleInsets.reading` for −4, `.nan`, `.infinity` and 24;
  - `storedInsets` is nil after `.start` and `.reclamp` and the frame's insets after the other two;
  - `CameraRunState`: a `didStopRunning` after `request(false)` is `.none`; an off, on, off sequence while a start is in flight makes `stopsAfterStart` true for the first generation; a reconnect while off returns `rebuild: true` at the next `request(true)` and only then.
- [ ] Implement both files.
- [ ] Run the full suite.
- [ ] Commit: `feat: bubble placement and the camera run state`.

### Task 5: R3 settings, options and the Settings rows

**Files:**
- Modify:
  - `TidyShot/Settings/AppSettings.swift`: `Keys` (:69-79), the Recording properties (:159-198), `register` (:256-266) and the reads (:312-329);
  - `TidyShot/Recording/RecordingConfiguration.swift`: `RecordingOptions` (:27-38);
  - `TidyShot/Recording/RecordingFormat.swift`: `RecordingSettingsLayout` (:23-42);
  - `TidyShot/Settings/CaptureSettingsView.swift`: `recordingLayout` (:21-23) and `Section("Recording")` (:62-122).
- Tests: add to `AppSettingsTests` and `RecordingSettingsLayoutTests`; create `TidyShotTests/RecordingOptionsTests.swift`.

**Consumes:** Task 4's `BubbleSize` and `BubbleInsets`.

**Produces:**
- `AppSettings` (design, Settings summary): `recordingClickHighlights: Bool` (false), `recordingWebcamBubble: Bool` (false), `recordingCamera: String` (`default`), `recordingCameraName: String` (empty), `recordingBubbleSize: BubbleSize` (`.medium`, stored as its raw value), `recordingBubbleInsetRight: Double` and `recordingBubbleInsetBottom: Double` (16, read through `BubbleInsets.reading`), and `var bubbleInsets: BubbleInsets`. `recordingOptions` fills the two toggles and the size.
- `RecordingOptions` gains `clickHighlights: Bool = false`, `webcamBubble: Bool = false`, `bubbleSize: BubbleSize = .medium`, `cameraID: String? = nil` and `cameraName: String? = nil`. `RecordingConfiguration.make` ignores them.
- `RecordingSettingsLayout`:
  - `init(format: RecordingFormat, clickHighlights: Bool = false, webcamBubble: Bool = false)`;
  - `cameraRowsEnabled` (the bubble toggle), `showsBubbleGIFCaption` (GIF and the bubble toggle), `showsOverlayCaption` (either toggle);
  - `static let bubbleGIFCaption = "A webcam bubble makes GIFs larger, because its picture changes in every frame."` and `overlayCaption = "Click highlights and the webcam bubble apply to area and fullscreen recordings."`.

**Steps:**
- [ ] Write the tests and see them fail:
  - `AppSettingsTests`: the seven keys default and persist; a stored `recordingBubbleSize` of `huge` reads as `.medium`; an inset of −4 reads as 16; `bubbleInsets` gives the two values.
  - `RecordingSettingsLayoutTests` (design, Tests): `cameraRowsEnabled` follows the bubble toggle for MP4 and GIF; the bubble's GIF caption shows for GIF with the bubble on only; the overlay caption shows with either toggle on; R2's four fields do not change with the new arguments.
  - `RecordingOptionsTests`: `recordingOptions` carries both toggles and the size, with `cameraID` and `cameraName` nil; a later settings change leaves the snapshot as it was; an options value keeps a `cameraID` and `cameraName` set on it.
- [ ] Implement the keys, the options and the layout.
- [ ] Change `Section("Recording")` (design, Settings summary). `recordingLayout` passes the two toggles. After `Count down before recording`:
  - `Toggle("Highlight clicks", isOn: $settings.recordingClickHighlights)`;
  - `Toggle("Show webcam bubble", isOn: $settings.recordingWebcamBubble)`, with no prompt until Task 7, which also puts `Camera` after it;
  - `Picker("Bubble size", …)`, segmented, `Small`, `Medium`, `Large`, disabled unless `cameraRowsEnabled`, with `bubbleGIFCaption` under it when `showsBubbleGIFCaption`;
  - `overlayCaption` last when `showsOverlayCaption`.
  Captions use `.font(.caption)` and `.foregroundStyle(.secondary)`, as the others do.
- [ ] Run the full suite.
- [ ] Commit: `feat: R3 recording settings`.

### Task 6: Cameras and the camera choice

**Files:**
- Create in `TidyShot/Recording/Bubble/`: `CameraDevices.swift`; `CameraChoice.swift` (`CameraChoice`, `CameraStart`, `BubbleButtonState`, `CameraLoss`, `CameraLossTracker`, `CameraNote`).
- Modify tests support: `TidyShotTests/Support/RecordingFakes.swift` gains `FakeCameraDevices`.
- Tests: create `TidyShotTests/CameraChoiceTests.swift`, `CameraNoteTests.swift` and `BubbleButtonStateTests.swift`.

**Consumes:** `RecordingSource`, `RecordingNotice` and `RecordingClock.format(_:)`.

**Produces:**
- `nonisolated struct CameraDevice: Equatable, Sendable { var uniqueID: String; var name: String }`.
- `nonisolated enum CameraAccess: Equatable, Sendable { case authorized, denied, restricted, notDetermined }`.
- `protocol CameraDevices: AnyObject { func list() -> [CameraDevice]; func preferred() -> CameraDevice?; func access() -> CameraAccess; func requestAccess() async -> Bool }`.
- `final class LiveCameraDevices: CameraDevices`:
  - `static let deviceTypes: [AVCaptureDevice.DeviceType] = [.builtInWideAngleCamera, .external, .continuityCamera]`, so no Desk View;
  - `static let changeNotifications` (`AVCaptureDevice.wasConnectedNotification`, `wasDisconnectedNotification`);
  - `list()` over `AVCaptureDevice.DiscoverySession(deviceTypes: deviceTypes, mediaType: .video, position: .unspecified)`;
  - `preferred()` (Gap 12); `access()` from `authorizationStatus(for: .video)`, `@unknown default` as `.denied`; `requestAccess()` is `AVCaptureDevice.requestAccess(for: .video)`.
- `nonisolated enum CameraChoice`:
  - `enum Stored: Equatable, Sendable { case systemDefault; case device(id: String, name: String) }`, `init(value: String, name: String)` (`default` or empty is `.systemDefault`), `var value: String` and `var name: String`;
  - `struct Entry: Equatable, Sendable { var tag: String; var title: String }` and `static func entries(stored: Stored, devices: [CameraDevice]) -> [Entry]`: `System Default` (tag `default`), each camera by name, then a missing stored camera as `<name> (not connected)`, or `Unknown camera (not connected)` with no name;
  - `static func pick(tag: String, devices: [CameraDevice], stored: Stored) -> Stored`: the name from the list, else the stored name when the tag is the stored camera's;
  - `static func refreshedName(stored: Stored, devices: [CameraDevice]) -> String?`: the listed name when the stored camera is listed under another name;
  - `static func asksForAccess(bubble: Bool, access: CameraAccess) -> Bool`: the toggle on and `.notDetermined`, whatever the format;
  - `static func showsAccessNote(bubble: Bool, access: CameraAccess) -> Bool`: the toggle on and `.denied` or `.restricted`;
  - `static func resolveAtStart(stored: Stored, access: () -> CameraAccess, devices: () -> [CameraDevice], preferred: () -> CameraDevice?) -> CameraStart` (Gap 1), which reads no device when access is not `.authorized`;
  - `static func forRecording(_ start: CameraStart, source: RecordingSource) -> CameraStart` (Gap 2);
  - `systemDefaultValue = "default"`, `systemDefaultTitle = "System Default"`, `unknownName = "Unknown camera"`, `recordedWithoutTitle = "Recorded without the webcam bubble"`, `accessOffText = "Camera access is off for TidyShot."`, `noCameraText = "No camera is connected."`, `couldNotStartText = "The camera could not be started."`, `notFilmedText = "The bubble could not be filmed."`, `recordedWithTitle(_:)` (`Recorded with <name>`), `notConnectedText(_:)` (`<name> is not connected.`, `Unknown camera` for an empty name) and `privacySettingsURL` (`x-apple.systempreferences:com.apple.preference.security?Privacy_Camera`).
- `nonisolated struct CameraStart: Equatable, Sendable { var camera: CameraDevice?; var access: CameraAccess; var note: RecordingNotice? }`.
- `nonisolated struct BubbleButtonState: Equatable, Sendable { var isEnabled: Bool; var disabledToolTip: String? }` and `static func make(camera: CameraDevice?, access: CameraAccess, filmed: Bool) -> BubbleButtonState`, checked in this order: `.notDetermined` gives `Turn on Show webcam bubble in Settings to allow the camera.` (`allowInSettingsText`); `.denied` or `.restricted` gives `accessOffText`; no camera gives `noCameraText`; not filmed gives `Not available for this recording` (`notAvailableText`, which the highlights button uses too).
- `nonisolated enum CameraLoss: Equatable, Sendable { case couldNotStart; case stopped(at: TimeInterval, backAt: TimeInterval?) }`.
- `nonisolated struct CameraLossTracker: Equatable, Sendable`, the first-loss bookkeeping `RecordingExtras` keeps (Task 12):
  - `private(set) var loss: CameraLoss?` and `private(set) var isClosed = false`;
  - `mutating func couldNotStart()`: `.couldNotStart` when `loss` is nil;
  - `mutating func lost(at: TimeInterval)`: `.stopped` at that time with no `backAt`, when `loss` is nil, so a `.couldNotStart` or an earlier loss is kept;
  - `mutating func back(at: TimeInterval)`: sets `backAt` when `loss` is `.stopped` with no `backAt`, so only the first return counts;
  - `mutating func close()`: sets `isClosed`; after it every call changes nothing.
- `nonisolated enum CameraNote`:
  - `static let lostTitle = "Camera lost"` and `static func lostBody(at: TimeInterval, backAt: TimeInterval?) -> String`: `The camera stopped at <m:ss>.` then ` It came back at <m:ss>.` or ` The bubble had no picture from there.`;
  - `static func afterStop(start: RecordingNotice?, wanted: Bool, missed: Bool, loss: CameraLoss?) -> RecordingNotice?`: nil unless `wanted`; then the start's note, else `recordedWithoutTitle` / `notFilmedText` when `missed`, else the loss's note (`recordedWithoutTitle` / `couldNotStartText`, or `lostTitle` / `lostBody`).
- `FakeCameraDevices`: `devices`, `preferredCamera`, `currentAccess`, `grants: Bool` (what a request answers, which also sets `currentAccess`) and `requestCount`.

**`resolveAtStart`** (design, Under the lock):
- access not `.authorized`: no camera, `recordedWithoutTitle` / `accessOffText`;
- `.systemDefault`: `preferred()` with no note, or with none, no camera and `recordedWithoutTitle` / `noCameraText`;
- a listed `.device`: that camera, no note;
- a missing `.device`: `preferred()` with `recordedWithTitle(<its name>)` / `notConnectedText(<stored name>)`, or with none, no camera and `recordedWithoutTitle` / `notConnectedText(<stored name>)`.

**Steps:**
- [ ] Write the design's `CameraChoiceTests`, `CameraNoteTests` and `BubbleButtonStateTests` and see them fail. Add:
  - `LiveCameraDevices.deviceTypes` is the three types, with no `.deskViewCamera` (a constant; nothing opens a camera);
  - `forRecording` keeps the camera and the note for `.area` and `.display`, and drops both for `.window`. There is no format argument, so a GIF start resolves as an MP4 one (design: a GIF keeps the choice);
  - `pick` and `refreshedName` for a listed, a renamed and a missing camera; `Stored(value:name:)` for `default`, empty and an id;
  - `lostBody(at: 12, backAt: 20)` is `The camera stopped at 0:12. It came back at 0:20.`, and with no return `The camera stopped at 0:12. The bubble had no picture from there.`;
  - `CameraLossTracker`, in `CameraNoteTests`: a loss at 12 then a return at 20 gives `.stopped(at: 12, backAt: 20)`; a second loss and a second return change nothing; a `.couldNotStart` is kept over a later loss; a return with no loss changes nothing; after `close()` a loss, a return or a `couldNotStart` changes nothing.
- [ ] Implement both files and the fake.
- [ ] Run the full suite.
- [ ] Commit: `feat: camera list and the camera choice`.

### Task 7: The camera permission and the shared prompt rule

**Files:**
- Modify:
  - `project.yml`: `info.properties` (:46-60) and `entitlements.properties` (:61-72); then the regenerated `TidyShot/Info.plist` and `TidyShot/TidyShot.entitlements`;
  - `TidyShot/App/AppCoordinator.swift`: the Collaborators (`microphones`, :47), the Recording state group (`isAskingMicrophone`, :85), and `refusesCapture`, `capturesRefused` and `captureRefusal` (:457-481);
  - `TidyShot/App/AppCoordinator+Recording.swift`: `recordingShortcutAction` (:22-29), `microphonePromptStep` (:35-38), the typealiases (:47-52), `recordScreen` and `recordFullscreen` (:60-115), `lockRefusedStart` (:120-124), `recordShortcutStarts` (:135-147), `recordingMicrophoneChoice` (:158-177), `recordingCanStart` (:185-206), `record` (:221-240), `recordingHandOff` (:260-324) and `MicrophonePromptStep` (:709);
  - `TidyShot/URLScheme/URLCommandHandler.swift`: `CaptureRefusal` (:4-9) and `dropReason` (:106);
  - `TidyShot/Settings/CaptureSettingsView.swift`: the camera state, the `Camera` row, the toggle's prompt and `pickMicrophone` (:155-167).
- Tests: change `ShortcutsTests` (:81-123) and `URLCommandHandlerTests` (:194-219). The design lists `URLCommandGateTests` too; at 05ca5af it does not read the refusal, so it does not change.

**Consumes:** Task 5's settings and rows; Task 6's camera types and `FakeCameraDevices`.

**Produces:**
- `nonisolated enum PermissionPrompt: Equatable, Sendable { case microphone, camera }` with `var name: String` (`microphone`, `camera`), in `AppCoordinator.swift` beside `refusesCapture`.
- `CaptureRefusal.permissionPrompt(PermissionPrompt)` in place of `.microphonePrompt`; `dropReason` gives `the microphone prompt is open` or `the camera prompt is open`.
- `AppCoordinator`:
  - `@ObservationIgnored var askingPermission: PermissionPrompt?` in place of `isAskingMicrophone`, and `@ObservationIgnored lazy var cameras: any CameraDevices = LiveCameraDevices()`;
  - `nonisolated static func refusesCapture(isCapturing: Bool, askingPermission: PermissionPrompt?) -> Bool` and `captureRefusal(isCapturing:askingPermission:) -> CaptureRefusal?` (`.captureRunning` wins);
  - `nonisolated static func recordingShortcutAction(for: RecordingPhase, askingPermission: PermissionPrompt?) -> RecordingShortcutAction`;
  - `nonisolated static func permissionPromptStep(asksForAccess: Bool, isCapturing: Bool) -> PermissionPromptStep`, the enum renamed from `MicrophonePromptStep` with its cases (`goOn`, `end`, `prompt`);
  - `nonisolated static func startPrompts(microphone: Bool, camera: Bool) -> [PermissionPrompt]` (Gap 9);
  - `nonisolated enum SettingsPromptStep: Equatable, Sendable { case ask, wait }` and `nonisolated static func settingsPromptStep(phase: RecordingPhase, isCapturing: Bool, askingPermission: PermissionPrompt?) -> SettingsPromptStep` (Gap 8);
  - `func requestAccessFromSettings(_ prompt: PermissionPrompt) async`, the new entry point.
- In `+Recording` (private): `recordingPrompts() async -> RecordingAsk?` in place of `recordingMicrophoneChoice()`, with `RecordingAsk = (microphone: MicrophoneChoice.Stored, prompted: PermissionPrompt?)`; `recordingCanStart(microphone:)` returns `RecordingInputs = (microphone: MicrophoneStart, camera: CameraStart)`; `record(_:inputs:)`; `recordingHandOff(_:inputs:)` also returns `camera: CameraStart`, after `forRecording`.

**Steps:**
- [ ] Add to `project.yml`, before any code that asks (asking without the usage string ends the process):
  - the entitlement `com.apple.security.device.camera: true`, under `# Capture → Recording → Show webcam bubble (recording R3).`;
  - `NSCameraUsageDescription: TidyShot shows your camera in a bubble in screen recordings when you turn it on.`, `NSCameraUseContinuityCameraDeviceType: true` and `NSCameraReactionEffectGesturesEnabledDefault: false`.
  Run `xcodegen generate` and commit the regenerated files with this task.
- [ ] Write the tests and see them fail (design, Tests: the Shortcuts and URL items):
  - `ShortcutsTests`: `refusesCapture` holds for either prompt and for the lock; `captureRefusal` is `.permissionPrompt(.camera)` with the camera prompt open and the lock free, `.captureRunning` with the lock held; a record shortcut gives `.ignore` in `.idle` and `.saving` with either prompt open, and still cancels a count-in and stops a recording; `permissionPromptStep` keeps R2's table; `startPrompts` gives `[.microphone, .camera]`, `[.camera]`, `[.microphone]` and `[]`; `settingsPromptStep` gives `.ask` only for `.idle`, no lock and no prompt, and `.wait` for `.countIn`, `.recording`, `.saving`, a held lock and either prompt open.
  - `URLCommandHandlerTests`: the refusal test runs over `.captureRunning`, `.permissionPrompt(.microphone)` and `.permissionPrompt(.camera)`; `dropReason` names each prompt.
- [ ] Rename mechanically. Afterwards `git grep -n -e isAskingMicrophone -e microphonePrompt -e MicrophonePromptStep -- TidyShot TidyShotTests` prints nothing.
- [ ] Wire the start (design, Permission, Before the capture lock):
  - `recordShortcutStarts` logs `Recording: start ignored, the <name> prompt is open`.
  - `recordingPrompts()` reads the microphone choice as R2 does (`forRecording` with the format, so GIF and `Off` ask nothing), and `CameraChoice.asksForAccess(bubble: settings.recordingWebcamBubble, access: cameras.access())`, which a GIF start asks too. For each of `startPrompts(microphone:camera:)`: `permissionPromptStep(asksForAccess: true, isCapturing: isCapturing)`; `.end` returns nil; otherwise set `askingPermission`, await that collaborator's `requestAccess()`, clear it, log the answer (Gap 9) and return nil if `isQuitting`. A start with the toggle off never prompts for the camera.
  - `lockRefusedStart(afterPrompt: PermissionPrompt?)` logs the line naming the prompt (Gap 9) and posts `lockRefusalNotice(afterPrompt: prompted != nil)`.
  - Under the lock, beside `MicrophoneChoice.resolveAtStart`, `recordingCanStart` runs `CameraChoice.resolveAtStart(stored: CameraChoice.Stored(value: settings.recordingCamera, name: settings.recordingCameraName), access: { cameras.access() }, devices: { cameras.list() }, preferred: { cameras.preferred() })` for every start. Nothing there awaits.
  - The hand-off takes `let camera = CameraChoice.forRecording(inputs.camera, source: source)` and returns it. Task 12 sets the options' camera fields from it, and Task 13 posts its note.
- [ ] Implement `requestAccessFromSettings(_:)` (design, Asking from Settings; Gap 8): with `.wait`, log the deferred line (the open prompt's wording when `askingPermission` is set, else the capture's) and return; with `.ask`, set `askingPermission`, await `cameras.requestAccess()` or `microphones.requestAccess()`, clear it and log the answer.
- [ ] Change `CaptureSettingsView` (design, Settings and Denied):
  - `cameraDevices` and `cameraAccess` state, read from a `LiveCameraDevices` when the tab appears and on its `changeNotifications`, the access again when the Settings window becomes key, beside the microphone's;
  - `Picker("Camera", …)` between `Show webcam bubble` and `Bubble size`, over `CameraChoice.entries`, disabled unless `cameraRowsEnabled`. A pick writes `recordingCamera` and `recordingCameraName` through `CameraChoice.pick`; `refreshedName` rewrites the name when the list shows another;
  - with `showsAccessNote(bubble:access:)`, `Camera access is off for TidyShot.` and `Privacy Settings…`, which opens `CameraChoice.privacySettingsURL`;
  - `Show webcam bubble` turned on while `cameraAccess` is `.notDetermined` runs `Task { await AppCoordinator.shared.requestAccessFromSettings(.camera); cameraAccess = cameras.access() }`. The toggle stays on whatever the answer (Decided 2026-10-24, 7);
  - `pickMicrophone` asks through `requestAccessFromSettings(.microphone)` in place of `microphones.requestAccess()`, so R2's pick gets the same rule (design call 25).
- [ ] Run the full suite.
- [ ] Build Release and check it:
  - `codesign -d --entitlements - .build-rel/Build/Products/Release/TidyShot.app 2>&1 | grep -c "device.camera"` prints 1, and the same with `device.audio-input` prints 1;
  - `/usr/libexec/PlistBuddy -c "Print :NSCameraUsageDescription" .build-rel/Build/Products/Release/TidyShot.app/Contents/Info.plist` prints the string, `Print :NSCameraUseContinuityCameraDeviceType` prints `true`, and `Print :NSCameraReactionEffectGesturesEnabledDefault` prints `false`.
- [ ] Hand checks (Tim's, for the checklist): C3, the first camera prompt from Record Screen and Record Fullscreen, before the selection or the count-in and after the microphone prompt when both are due; a GIF start asks for the camera and not the microphone; Deny keeps the toggle on; while the prompt is up a second Record press does nothing (logged) and a screenshot shortcut is refused; the prompt from Settings; the toggle turned on in Settings during a recording shows no prompt, logs `… deferred, a capture is running`, and the next start asks; the toggle turned on in Settings while the microphone prompt from Settings is open shows no second prompt and logs `Recording: camera prompt from Settings deferred, the microphone prompt is open`; the microphone pick during a recording, the same as the toggle.
- [ ] Commit: `feat: camera permission and the shared prompt rule`.

### Task 8: What the filter films

**Files:**
- Modify:
  - `TidyShot/Recording/ScreenRecordingDriver.swift`: `RecordingExclusions` (:22-26), the protocol's `start` (:46-50), `start` (:81-98), `makeFilter` (:136-159) and `fallbackFilter` (:164-172);
  - `TidyShot/Recording/RecordingChrome.swift`: the protocol (:5-24) and `RecordingScreenChrome`;
  - `TidyShot/Recording/RecordingController.swift`: `RecordingRequest` (:8-19), `run` (:158-193) and `reset` (:254-271);
  - tests support: `FakeRecordingDriver` (:25-110) and `FakeRecordingChrome` (:111-196) in `RecordingFakes.swift`.
- Tests: add to `RecordingConfigurationTests` and `RecordingControllerTests`.

**Consumes:** Task 6's `BubbleButtonState`.

**Produces:**
- `nonisolated enum FilmedFeature: String, CaseIterable, Hashable, Sendable { case bubble, highlights }` beside `RecordingExclusions`.
- `RecordingExclusions`:
  - `var filmedWindows: Set<CGWindowID> = []`, so R2's callers compile;
  - `func exceptedWindowNumbers(for plan: RecordingFilterPlan) -> Set<CGWindowID>`: `coverWindows ∪ filmedWindows` for `.area` and `.display`, empty for `.window`;
  - `var fallbackExcludedWindowNumbers: Set<CGWindowID>`: `chromeWindows ∪ cardWindows`;
  - `func filmed(found: Set<CGWindowID>) -> Set<CGWindowID>`: `filmedWindows ∩ found`.
- `RecordingStreamDriver.start(_:outputURL:exclusions:events:) async throws -> Set<CGWindowID>`, `@discardableResult`: the filmed windows the filter holds. The real driver returns `filmed(found:)` of the lookup, all of `filmedWindows` from the fallback filter, and none for a window.
- `RecordingChrome` gains `var filmedWindowNumbers: [FilmedFeature: CGWindowID] { get }` and `func setFilmed(_ features: Set<FilmedFeature>)` (Gap 4). `RecordingScreenChrome` gives `[:]` and does nothing until Tasks 9 and 12.
- `nonisolated struct RecordingExtrasStart: Equatable, Sendable { var highlights: Bool; var bubbleToggle: Bool; var bubble: BubbleButtonState }`, the R3 features at the start, and `RecordingRequest.extras: RecordingExtrasStart? = nil`, nil for a window recording.
- `nonisolated struct RecordingExtrasSummary: Equatable, Sendable { var bubbleWanted = false; var highlightsAtStart = false; var highlightsUsed = false; var missed: Set<FilmedFeature> = [] }` and the controller's `private(set) var extrasSummary`, reset in `reset` (Gap 6). This task fills `missed`; Task 9 fills the rest.
- `FakeRecordingDriver.filmed: Set<CGWindowID>?`: what `start` returns, nil meaning all of `exclusions.filmedWindows`. `FakeRecordingChrome.filmedWindowNumbers` defaults to `[.bubble: 51, .highlights: 52]`, and `filmedShown: [Set<FilmedFeature>]` records each `setFilmed`.

**Steps:**
- [ ] Write the tests and see them fail:
  - `RecordingConfigurationTests` (design, Tests): `exceptedWindowNumbers` holds the covers and the filmed windows for an area and a display and nothing for a window; `fallbackExcludedWindowNumbers` never holds a filmed window; `filmed(found:)` keeps only filmed windows that were found.
  - `RecordingControllerTests`: a request with `extras` gives the driver `filmedWindows` [51, 52] and one without gives none, the R2 exclusions test still passing; the driver's set reaches `setFilmed` as features (both, the bubble only, the highlights only, neither); a feature missing from `filmedWindowNumbers` is missed; `extrasSummary.missed` matches; a request without `extras` never calls `setFilmed`; a start that throws calls neither.
- [ ] Implement the exclusions and the driver: `makeFilter` looks up `exceptedWindowNumbers(for:)` once through `OverlayWindowLookup`, uses what it finds as `exceptingWindows`, and returns it with `filmed(found:)`; `fallbackFilter` looks up `fallbackExcludedWindowNumbers` and returns `filmedWindows`.
- [ ] Implement the controller (design, Lookup misses): in `run`, the exclusions get `filmedWindows: Set(chrome.filmedWindowNumbers.values)` when `request.extras` is set. After `start` returns, with `extras`, a feature is filmed when its number is in the returned set. Each missed one logs `Recording: <bubble|highlights> window not in shareable content, not filmed`; then `Recording: filming <n> own windows (<names>)` logs with the filmed names in `FilmedFeature.allCases` order, joined by `, `; then `chrome.setFilmed(filmed)` and `extrasSummary.missed` is set.
- [ ] Run the full suite.
- [ ] Commit: `feat: film the bubble and the ring overlay`.

### Task 9: The bar's two buttons

**Files:**
- Modify:
  - `TidyShot/Recording/RecordingPanelLayout.swift`;
  - `TidyShot/Recording/RecordingPanelView.swift`: `RecordingPanelModel` (:6-38) and the view (:41-113);
  - `TidyShot/Recording/RecordingChrome.swift`: the protocol's `show` and two setters, and `RecordingScreenChrome`'s `show`, `setFilmed` and `close` (:72-140);
  - `TidyShot/Recording/RecordingController.swift`: `run`'s `show` (:168-171), `handle`'s `.recordingStarted` (:288-294), `reset`, the toggles beside `toggleMute` (:209), and `finish`'s kept recording (:421-428);
  - tests support: `FakeRecordingChrome`.
- Tests: add to `RecordingPanelLayoutTests` and `RecordingControllerTests`.

**Consumes:** Task 3's `Recording.highlightedClicks`; Task 6's `BubbleButtonState`; Task 8's `FilmedFeature`, `RecordingExtrasStart`, `RecordingExtrasSummary` and `setFilmed`.

**Produces:**
- `RecordingPanelLayout` (design, Bar, Widths):
  - `nonisolated struct Bar: Equatable, Sendable { var showsTag: Bool; var showsMute: Bool; var showsOverlayButtons: Bool }`, with `static let plain`, `mute` and `gif` for R2's three bars, which a window recording still has and R2's tests use. They are only three of the bars: an area or fullscreen bar is one of them with `showsOverlayButtons` true, and equals none of them;
  - `static func bar(showsMute: Bool, isGIF: Bool, showsOverlayButtons: Bool = false) -> Bar`: a GIF has the tag and never the mute button;
  - `static func size(of bar: Bar) -> CGSize`: width `172 + 36 × slots`, where the tag or the mute button is one slot and the two R3 buttons two, height 44. That gives 172 and 208 for a window recording, 244 for an area or fullscreen MP4 with no sound, and 280 with sound or for a GIF;
  - `tagFrame(of:)` reads `showsTag` and `muteFrame(of:)` reads `showsMute`, in place of R2's `bar == .gif` and `bar == .mute`;
  - `highlightsFrame(of:)` and `bubbleFrame(of:)`, nil without the overlay buttons. Left to right: the tag, the time, highlights, bubble, mute, Stop, Cancel. `timeFrame` ends `spacing` before the first button.
- `RecordingPanelModel.format` is `.gif` when `bar.showsTag`, else `.mp4`, in place of R2's `bar == .gif`. With R2's comparison every area and fullscreen GIF bar would read as `.mp4`, and the time would turn orange at 300 s instead of the GIF's 30 s (design, Notices and R2, GIF).
- `nonisolated struct BarToggle: Equatable, Sendable { var isOn: Bool; var isEnabled: Bool; var disabledToolTip: String? }` in `RecordingChrome.swift`.
- `RecordingChrome`:
  - `show(onStop:onCancel:onMute:onHighlights:onBubble:bar:highlights: BarToggle, bubble: BarToggle)`;
  - `setHighlights(_ on: Bool, monitoring: Bool)` (Gap 5) and `setBubble(_ on: Bool)`.
- `RecordingPanelModel`: `highlights` and `bubble` (`BarToggle`), `onHighlights` and `onBubble`, and:
  - `highlightsSymbol` (`cursorarrow.rays` on, `cursorarrow` off), `highlightsToolTip` (`Stop highlighting clicks` / `Highlight clicks`, or the disabled tool tip), `highlightsAccessibilityLabel` (`Stop highlighting clicks` / `Highlight clicks`);
  - `bubbleSymbol` (`video.fill` on, `video.slash.fill` off), `bubbleToolTip` (`Hide the webcam bubble` / `Show the webcam bubble`, or the disabled tool tip), `bubbleAccessibilityLabel` (`Hide webcam bubble` / `Show webcam bubble`).
- `RecordingController`: `private(set) var highlightsClicks` and `showsBubble`; `func toggleHighlights()` and `func toggleBubble()`; `var elapsedTime: TimeInterval` (the private `elapsed`, Gap 7).
- `FakeRecordingChrome`: `shownToggles: [(highlights: BarToggle, bubble: BarToggle)]`; `calls` gains `highlights <on|off> monitoring <on|off>` and `bubble <on|off>`; `pressHighlights()` and `pressBubble()`.

**The controller's rules** (design, Bar, State; Click highlights; Webcam bubble):
- `reset` sets `highlightsClicks` to `extras.highlights` and `showsBubble` to `extras.bubbleToggle && extras.bubble.isEnabled`, both false without `extras`; `extrasSummary.highlightsAtStart` and `bubbleWanted` start from the two toggles.
- `show` passes `BarToggle(isOn: highlightsClicks, isEnabled: true, disabledToolTip: nil)` and `BarToggle(isOn: showsBubble, isEnabled: extras.bubble.isEnabled, disabledToolTip: extras.bubble.disabledToolTip)`, and the bar with `showsOverlayButtons: request.extras != nil`. With the toggle on and no camera, the bubble starts off and disabled.
- `toggleHighlights()` guards on `isRunning`, `cause == nil`, `request?.extras` and highlights not missed. It flips the value, marks `highlightsUsed` when it is on after the first frame, calls `setHighlights(highlightsClicks, monitoring: highlightsClicks && firstFrame != nil)`, and logs `Recording: click highlights on|off at <m:ss>`.
- At `.recordingStarted`, with `extras`, highlights on and not missed: `highlightsUsed` and `setHighlights(true, monitoring: true)`.
- `toggleBubble()` guards the same way, plus `extras.bubble.isEnabled` and the bubble not missed. It flips the value, marks `bubbleWanted` when on, calls `setBubble(_:)` at once, before the first frame too, and logs `Recording: webcam bubble on|off at <m:ss>`.
- A missed feature (Task 8) sets its value false. A press once the recording is ending is ignored. The kept `Recording` gets `highlightedClicks = extrasSummary.highlightsUsed`.
- `RecordingScreenChrome.setFilmed` makes each missing feature's toggle `BarToggle(isOn: false, isEnabled: false, disabledToolTip: BubbleButtonState.notAvailableText)`. Both buttons are disabled with Stop (`stopEnabled`), as the mute button is.

**Steps:**
- [ ] Write the tests and see them fail:
  - `RecordingPanelLayoutTests` (design, Tests): the 172, 208, 244 and 280 bars, each with `9:59:59`, clip no subview and overlap nowhere; the left-to-right order; a window recording's bars have no R3 frames; R2's tests pass on `.plain`, `.mute` and `.gif`; `tagFrame` is set for both GIF bars and `muteFrame` for both mute bars, with and without the overlay buttons; `RecordingPanelModel.format` is `.gif` for the GIF bar with the overlay buttons as well as for `.gif`, and `.mp4` for the four others, and `RecordingClock.isPastSoftLimit(30, format: model.format)` holds for the GIF bar with the overlay buttons; the model's symbols, tool tips and labels for on, off and disabled.
  - `RecordingControllerTests` (design, Tests): `toggleHighlights` and `toggleBubble` flip and reach the fake chrome; a bubble press before `.recordingStarted` applies at once, and a highlights press gives `monitoring off`, then `monitoring on` at `.recordingStarted`; a press after Stop is ignored; both reset at the next run; `showsBubble` starts false with the toggle on and no camera; a missed feature's press is ignored; `extrasSummary` and the kept recording's `highlightedClicks` follow the presses; `close` reaches the chrome once on every end; a request without `extras` shows R2's bars.
- [ ] Implement the layout, the model and the view: `size`, `tagFrame`, `muteFrame` and `format` read the bar's fields, and afterwards `git grep -n -e "bar == \." -e "bar != \." -- TidyShot` prints nothing; the two buttons at their frames with their symbols, tool tips and accessibility labels, disabled by `!stopEnabled || !toggle.isEnabled`. `RecordingScreenChrome.show` stores the toggles and the closures; `close` clears both closures.
- [ ] Implement the controller's state, presses and summary.
- [ ] Run the full suite.
- [ ] Commit: `feat: highlight and bubble buttons on the recording bar`.

### Task 10: The ring overlay and the click monitor

**Files:**
- Create in `TidyShot/Recording/Clicks/`: `ClickRingOverlay.swift`; `ClickMonitor.swift` (`ClickEventSource`, `ClickRingDrawing`, `ClickMonitor`, `ClickHighlighter`).
- Tests: create `TidyShotTests/ClickHighlighterTests.swift` and `ClickRingOverlayTests.swift`.

**Consumes:** Task 2's rule, events, changes and timing.

**Produces:**
- `protocol ClickEventSource: AnyObject { func install(_ handler: @escaping (ClickEvent) -> Void); func remove() }`.
- `protocol ClickRingDrawing: AnyObject { func apply(_ change: ClickRingChange); func removeAllRings() }`.
- `final class ClickMonitor: ClickEventSource`:
  - `init(isFilmedWindow: @escaping (NSWindow) -> Bool)`, true for the bubble;
  - `static let mask: NSEvent.EventTypeMask`, the six types;
  - `install` adds the global monitor (no window) and the local one (returning the event), each through `ClickEvent.make` with `NSScreen.screens.first?.frame.maxY` read per event. A local down passes only when `isFilmedWindow(event.window)`; local drags and ups always pass (Gap 10). `install` twice installs once. `remove` removes both.
- `final class ClickHighlighter`:
  - `init(rule: ClickHighlightRule, source: any ClickEventSource, drawing: any ClickRingDrawing)`;
  - `private(set) var isMonitoring`;
  - `func setRule(_ rule: ClickHighlightRule)`: replaces the rule while not monitoring, and is ignored while monitoring, so `RecordingExtras.place(at:)` can give it the fresh recorded rect before the first frame;
  - `start()` installs once; `stop()` removes the monitors and applies `rule.endAll()`; `close()` stops and calls `removeAllRings()`.
- `final class ClickRingOverlay: NSPanel, ClickRingDrawing` (design, The overlay, The ring, Animation):
  - `init(screenFrame: CGRect)` and `func setScreenFrame(_:)`;
  - `[.borderless, .nonactivatingPanel]`, `isFloatingPanel = true` and then `level = .screenSaver`, `ignoresMouseEvents = true`, `isOpaque = false`, `backgroundColor = .clear`, `hasShadow = false`, `hidesOnDeactivate = false`, `collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]`, never key or main, `sharingType` left at its default;
  - a layer-backed content view whose ring container has `isGeometryFlipped = true`, so ring points are CG-oriented from the display's top-left;
  - `static func makeRingLayer(colour: ClickRingColour, scale: CGFloat) -> CALayer`: 40 pt across; a 6 pt black stroke at 60 % under a 3.5 pt stroke of the colour, with a 20 % fill of the colour; `contentsScale` set to `scale` on every layer;
  - `apply(.begin)` adds a ring at the point, growing from 0.5× to 1× over 0.15 s, fully opaque; `.move` sets its position inside `CATransaction.setDisableActions(true)`; `.end` waits until the grow has finished (`ClickRingTiming.fadeStart`), then scales to 1.3× and fades to clear over 0.35 s and removes the layer when done. With highlights off it holds no layers.

**Steps:**
- [ ] Write the tests and see them fail:
  - `ClickHighlighterTests`, over a fake source and a fake drawing: `start` installs once; events reach the drawing as the rule's changes; a down outside the recorded rect draws nothing; `setRule` before `start` moves where a down draws, and `setRule` while monitoring changes nothing; `stop` removes the monitors and ends each held ring; an event after `stop` draws nothing; `close` removes every ring.
  - `ClickRingOverlayTests`: `makeRingLayer`'s bounds, stroke widths, colours and alpha for both colours, and its `contentsScale` at 2; a `.begin` adds a layer at the point with a scale animation from 0.5 to 1 over 0.15 s; `.end` adds a fade from 1 to 1.3 and from opacity 1 to 0 over 0.35 s; the panel's level, collection behaviour, `ignoresMouseEvents` and `hasShadow`.
- [ ] Implement `ClickRingOverlay`, `ClickHighlighter` and the protocols.
- [ ] Install the monitors (held by G1): the `ClickMonitor` class as above. No event tap, and no Accessibility or Input Monitoring call. Nothing else in Tasks 10 to 13 names `ClickMonitor` but `record()`'s click source (Task 12), so the rest compiles while this step is held.
- [ ] Run the full suite.
- [ ] Hand checks (Tim's, for the checklist; they run once Task 12 wires the overlay): rings on clicks only inside the recorded rect on both displays, over menus, the menu bar and a fullscreen app; a held ring follows the pointer during a drag without trailing; a drag out of the area waits at the edge and its release ends it; a control-click is blue; a click on the bubble draws its ring in place; no ring during the selection or the count-in.
- [ ] Commit: `feat: click ring overlay and monitor`.

### Task 11: The bubble window and the camera session

**Files:**
- Create in `TidyShot/Recording/Bubble/`: `WebcamBubblePanel.swift`, `CameraSession.swift` (`CameraSession`, `CameraSessionReport`, `CameraFormat`).
- Tests: create `TidyShotTests/WebcamBubblePanelTests.swift` and `CameraSessionTests.swift`.

**Consumes:** Task 4's `BubbleSize`, `BubblePlacement` and `CameraRunState`.

**Produces:**
- `final class WebcamBubblePanel: NSPanel` (design, The window):
  - `init(preview: CALayer, size: BubbleSize, frame: CGRect, recorded: CGRect)`. The preview is the extras' `AVCaptureVideoPreviewLayer` (`videoGravity = .resizeAspectFill`), or a plain layer in tests and when no camera resolved;
  - `[.borderless, .nonactivatingPanel]`, `isOpaque = false`, `backgroundColor = .clear`, `hasShadow = false`, `hidesOnDeactivate = false`, never key or main, `level = .floating`, `collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]`;
  - a layer-backed content view with `cornerRadius = side / 2` and `masksToBounds = true`, dark grey (white 0.15) behind the preview, a 2 pt white border at 85 % opacity in a `CAShapeLayer` above it, and `video.slash` in white at 40 % of the diameter shown only after a loss; `contentsScale` from `backingScaleFactor`, again in `viewDidChangeBackingProperties`. `acceptsFirstMouse(for:)` is true, and `hitTest` is nil outside the circle;
  - `var recorded: CGRect`, `private(set) var size: BubbleSize`;
  - `var onDragEnded: (CGRect) -> Void`, `onSizeStepped: (BubbleSize, CGRect) -> Void` and `onInteraction: () -> Void`;
  - `mouseDown`: `onInteraction()`, then `clickCount == 2` steps the size, else records the drag start; `mouseDragged` sets the frame from `BubblePlacement.drag`; `mouseUp` after a drag calls `onDragEnded`. A right-click does nothing;
  - `func stepSize()`: `BubblePlacement.step` to `size.next`, then `onSizeStepped`;
  - `func reclamp(into recorded: CGRect)`;
  - `func setPictureShown(_ shown: Bool)`: off hides the preview, the border and the loss symbol at once, draws nothing and sets `ignoresMouseEvents = true`; on reverses it;
  - `func setLost(_ lost: Bool)`.
- `nonisolated final class CameraSession: @unchecked Sendable` (design, The camera session):
  - `static let queueLabel = "io.tky.tidyshot.camera"`;
  - `let session: AVCaptureSession`, for the preview layer; it is configured, started and stopped only on the queue;
  - `init(deviceID: String, preview: AVCaptureVideoPreviewLayer, report: @escaping @MainActor @Sendable (CameraSessionReport) -> Void)`. `RecordingExtras` makes the preview layer with no session and calls this init on the main actor. The init creates the `AVCaptureSession` and sets `preview.session = session` there, before any work goes to the queue; from then on the queue touches the session and never the layer;
  - `func run(_ on: Bool)`: records the request in its `CameraRunState` and returns at once; the queue builds the session on the first on (and on a rebuild), starts it, and stops it again when `stopsAfterStart` says so;
  - `func close()`: the queue removes its observers, then `run(false)`, both on the queue in that order. A report already on its way to the main actor can still arrive after `close`; `RecordingExtras` drops it (Task 12).
- `nonisolated enum CameraSessionReport: Equatable, Sendable { case started, couldNotStart(String), lost(String), back }`. `lost` carries the notification's name.
- `nonisolated enum CameraFormat { struct Candidate: Equatable, Sendable { var width: Int; var height: Int; var maxFrameRate: Double }; static func pick(_ candidates: [Candidate]) -> Int? }` (Gap 15).

**The session on its queue:**
- The device is `AVCaptureDevice(uniqueID:)` with its input. The session uses `sessionPreset = .hd1280x720` when `canSetSessionPreset` allows it, else the format `CameraFormat.pick` gives. The frame rate is fixed at 30 fps: `activeVideoMinFrameDuration` and `activeVideoMaxFrameDuration` set to 1/30 s under `lockForConfiguration`. There is no audio input and no file output.
- After `commitConfiguration` and before `startRunning`, on every build and rebuild, the queue sets `automaticallyAdjustsVideoMirroring = false` and `isVideoMirrored = true` on each of `session.connections` where `isVideoMirroringSupported`. The preview layer is the session's only output, so these are its connections, which exist once the input is committed; the queue reaches them through the session, not the layer. The mirroring is set before the first frame, so no frame shows unmirrored.
- After `startRunning` it logs `Recording: camera <name>, <width>×<height> at <fps> fps, started in <ms> ms` and reports `.started`. No device, a failed input or a session that does not run reports `.couldNotStart`.
- It observes `AVCaptureSession.runtimeErrorNotification`, `wasInterruptedNotification`, `interruptionEndedNotification`, `didStartRunningNotification` and `didStopRunningNotification` for its session, and `AVCaptureDevice.wasDisconnectedNotification` and `wasConnectedNotification` for its `uniqueID`. Each goes to the queue, through `CameraRunState.handle`, and `.lost` or `.back` hops to the main actor. `.rebuild` rebuilds the input while the bubble is meant to be on. Every error, interruption and stop is a loss until C2 says otherwise (G4).

**Steps:**
- [ ] Write the tests and see them fail:
  - `WebcamBubblePanelTests`, with a plain preview layer and no session: the panel's style, level, collection behaviour, `hasShadow` and `acceptsFirstMouse`; the corner radius for each size; `stepSize` keeps the centre, clamps, and calls `onSizeStepped` with the new size and frame; `setPictureShown(false)` sets `ignoresMouseEvents` and hides the preview, and `true` reverses it; `setLost` shows and hides the symbol.
  - `CameraSessionTests`: `CameraFormat.pick` takes 1280×720 at 30 over 1920×1080 at 60 and 640×480 at 30; skips a 1280×720 that reaches only 15 fps; gives nil when nothing reaches 30; takes the smaller of two at the same distance.
- [ ] Implement `WebcamBubblePanel` and `CameraSession`.
- [ ] Run the full suite. No test creates a `CameraSession` with a device.
- [ ] Hand checks (Tim's, for the checklist; C2 first, then the app once Task 12 wires it): the bubble at each size, mirrored, over a fullscreen Space; dragged and clamped in an area and in fullscreen against the visible frame by the Dock; a double-click steps the size; the transparent corners pass clicks through; the Brio unplugged and the iPhone locked mid-recording show the loss picture and the recording goes on, and plugged back in it returns; another app taking the camera and letting it go; camera access turned off by Tim mid-recording, and what the session posts then (the design treats a revoke as a loss; if nothing posts, it goes to Tim); a quick Stop and a quick bar-off while the iPhone is still starting leave the camera's light off.
- [ ] Commit: `feat: webcam bubble panel and camera session`.

### Task 12: RecordingExtras and the start

**Files:**
- Create `TidyShot/Recording/RecordingExtras.swift` (`RecordingExtrasPlace`, `RecordingExtras`).
- Modify:
  - `TidyShot/Recording/RecordingChrome.swift`: `RecordingScreenChrome`'s `init` (:45-53), `filmedWindowNumbers`, `show`, the setters, `setFilmed` and `close` (:134-140);
  - `TidyShot/App/AppCoordinator+Recording.swift`: `record` (:221-240) and `recordingHandOff` (:260-324).
- Tests: create `TidyShotTests/RecordingExtrasPlaceTests.swift`.

**Consumes:** Tasks 4 to 11.

**Produces:**
- `nonisolated struct RecordingExtrasPlace: Equatable, Sendable` (Gap 13):
  - `var bubbleRect: CGRect` (AppKit: the area, or the visible frame for fullscreen), `var screenFrame: CGRect` (AppKit: the display's whole frame, the overlay's frame), `var ringArea: CGRect?` (CG: the area within the display, nil for fullscreen), `var displayFrame: CGRect` (CG);
  - `static func make(cgArea: CGRect?, cgDisplayFrame: CGRect, screenFrame: CGRect, visibleFrame: CGRect, primaryHeight: CGFloat) -> RecordingExtrasPlace`.
- `final class RecordingExtras` (design, Who owns the bubble, Filming, Webcam bubble):
  - `init(options: RecordingOptions, camera: CameraStart, insets: BubbleInsets, clickSource: @escaping (_ isFilmedWindow: @escaping (NSWindow) -> Bool) -> any ClickEventSource, elapsed: @escaping () -> TimeInterval, storeInsets: @escaping (BubbleInsets) -> Void, storeSize: @escaping (BubbleSize) -> Void)`. `clickSource` makes the highlighter's source in `show(at:)`, given a test for the bubble's window;
  - `let options: RecordingOptions` and `let camera: CameraStart`;
  - `var onBubbleInteraction: () -> Void`;
  - `func show(at place: RecordingExtrasPlace)`, `func place(at place: RecordingExtrasPlace)`;
  - `var windowNumbers: [FilmedFeature: CGWindowID]`;
  - `func setFilmed(_ features: Set<FilmedFeature>)`, `func setBubble(_ on: Bool)`, `func setHighlights(monitoring: Bool)`;
  - `var cameraLoss: CameraLoss?`, read from its `CameraLossTracker` (Task 6);
  - `func close()`, idempotent.
- `RecordingScreenChrome.init(placement: RecordingChromePlacement, extras: RecordingExtras? = nil)`.

**Steps:**
- [ ] Write `RecordingExtrasPlaceTests` and see them fail: an area on the primary display gives the area in AppKit points for the bubble and in CG for the rings; fullscreen gives the visible frame for the bubble and no ring area; an area on a second display left of and below the primary converts with the primary's height; an area that crosses the display's edge is cut to it.
- [ ] Implement `RecordingExtrasPlace` and `RecordingExtras`:
  - `show(at:)`, once per recording: makes the `ClickRingOverlay` at `screenFrame` and the `WebcamBubblePanel` at `BubblePlacement.frame(recorded: bubbleRect, size: options.bubbleSize, insets:)`, and orders both front. With `options.webcamBubble`, a camera and `.authorized` access, it makes the `AVCaptureVideoPreviewLayer` and the `CameraSession`, shows the picture and runs the camera. Otherwise the bubble is on screen, invisible and click-through, and makes no session. The `ClickHighlighter` is made over `ClickHighlightRule(displayFrame:area:)` and `clickSource { $0 === bubble }`, and is not started.
  - `place(at:)`: reclamps the bubble (`.reclamp`, not stored), moves the overlay to the fresh `screenFrame`, and gives the highlighter `ClickHighlightRule(displayFrame:area:)` from the fresh place through `setRule` (Task 10). The monitors are not installed yet at that point, since `place(at:)` runs before the driver starts.
  - `windowNumbers`: each window's number while it is visible and above 0.
  - `setFilmed`: a missing bubble hides its picture and stops the camera for good; missing highlights are never started.
  - `setBubble(_:)`, while the bubble is filmed and usable: on makes the session if needed, shows the picture and runs the camera; off hides the picture at once, then stops the camera, and the window stays on screen for the filter.
  - `setHighlights(monitoring:)` (its reach from the bar is held by G1): starts or stops the highlighter while highlights are filmed.
  - The panel's callbacks: a drag's end stores `storedInsets(after: .dragEnded, …)`; a size step stores the size through `storeSize`, logs `Recording: bubble size <small|medium|large>` and stores `storedInsets(after: .sizeStepped, …)`; every one calls `onBubbleInteraction`.
  - The session's reports: `.couldNotStart` calls the tracker's `couldNotStart()` and shows the loss picture; `.lost(name)` shows the loss picture, logs `Recording: camera lost at <m:ss>: <name>` and calls `lost(at: elapsed())`; `.back` shows the picture, logs `Recording: camera back at <m:ss>` and calls `back(at: elapsed())`. The tracker keeps the first loss only (Task 6). The bubble's place never changes on a loss. A report that arrives after `close()` is dropped: no picture change, no log line, and `cameraLoss` stays as `record()` reads it.
  - `close()`: once, on the main actor. It closes the tracker, orders both windows out at once, closes the highlighter (monitors and every ring layer), closes the camera session (its observers, then the stop on its queue, as Task 11 says), then closes both windows.
- [ ] Change `RecordingScreenChrome`: it holds `extras`. `filmedWindowNumbers` is `extras?.windowNumbers ?? [:]`. `setHighlights`, `setBubble` and `setFilmed` change the model as in Task 9 and then call the extras. `show` sets `extras?.onBubbleInteraction` to order the bar's panel front, and orders it front after the bubble. `close` calls `extras?.close()` first.
- [ ] Wire the start (held by G2; design, When they are made and Who owns the bubble; Gap 3):
  - `record(_:inputs:)` makes `RecordingExtras` for an `.area` or `.display` target only, with `settings.recordingOptions`, `inputs.camera`, `settings.bubbleInsets`, `clickSource: { ClickMonitor(isFilmedWindow: $0) }`, `elapsed: { [weak self] in self?.recorder.elapsedTime ?? 0 }`, `storeInsets` writing `recordingBubbleInsetRight` and `recordingBubbleInsetBottom`, and `storeSize` writing `recordingBubbleSize`. It closes it in a `defer`, so every exit tears it down. While G1 holds Task 10's monitor step, `clickSource` is `{ _ in InertClickSource() }` instead: a private `ClickEventSource` in `RecordingExtras.swift` whose `install` and `remove` do nothing, removed when the held step lands.
  - `recordingHandOff(_:inputs:extras:)`: right after its `guard !isQuitting`, before the count-in or the settle delay, `extras?.show(at:)` with the place from the target (the area's CG rect, or none for fullscreen; the display's CG frame from the target's `SCDisplay`; its screen's frame and `visibleFrame(forDisplayID:cgFrame:)`). When `CaptureEngine.screen(forDisplayID:)` finds no screen (the display went before the count-in), both AppKit frames fall back to the display's CG frame converted with the primary's height, as `visibleFrame(forDisplayID:cgFrame:)` already does, and the extras still show. The start does not give up there: the content read finds the display gone, the hand-off gives nil as R2's does, and the `defer` closes the extras. After the content read, `extras?.place(at:)` with the fresh area ∩ display.
  - The options' two toggles and size come from `extras.options`, and `cameraID` and `cameraName` from the window-filtered `CameraStart` (Gap 3). Without extras the hand-off sets the two toggles false and the size to `.medium`, and the camera fields stay nil.
  - The request's `extras` is `RecordingExtrasStart(highlights: options.clickHighlights, bubbleToggle: options.webcamBubble, bubble: BubbleButtonState.make(camera: camera.camera, access: camera.access, filmed: true))`, nil without extras. The chrome is `RecordingScreenChrome(placement:extras:)`.
- [ ] Run the full suite.
- [ ] Hand checks (Tim's, for the checklist; design, Hand checks): the bubble during the count-in and dragged there, and none during the selection; every give-up exit with the bubble on (Cancel in the count-in, the record shortcut in the count-in, quit in the count-in, the display unplugged in the count-in, a failed content read) leaves no bubble and the camera's light off; under the bar after a drag and a double-click on it; its place remembered across recordings and displays, and the size setting following a double-click; both bar buttons on and off mid-recording, in the first second and while ending; a window recording with both toggles on shows neither and has the 172 or 208 pt bar; no ring or bubble after Stop; quit with the bubble on; `kill -9` with the bubble on, then relaunch; the log's `filming 2 own windows (bubble, highlights)`.
- [ ] Commit: `feat: the webcam bubble and click highlights in recordings`.

### Task 13: The notes after Stop

**Files:**
- Modify:
  - `TidyShot/Recording/RecordingNoticeOrder.swift`;
  - `TidyShot/App/AppCoordinator+Recording.swift`: `RecordingEnded` (:52), `record`, `endRecording` (:436-453), `muteAndSave` (:464-485), `makeGIF` (:505-533), `saveRecording` (:553-638) and `postAfterStop` (:642-647).
- Tests: add to `RecordingNoticeOrderTests`.

**Consumes:** Task 2's `ClickHighlightRule.noteAfterStop`; Task 6's `CameraNote`; Task 7's `CameraStart` from the hand-off; Task 8's and 9's `extrasSummary`; Task 12's `cameraLoss`.

**Produces:**
- `RecordingNoticeOrder.afterStop(save:stop:microphone:camera:highlights:quitMode:) -> [RecordingNotice]`, in that order, skipping nils, nothing in quit mode.
- `RecordingEnded` gains `cameraNote` and `highlightsNote`.
- `saveRecording` gains `cameraNote: RecordingNotice? = nil` and `highlightsNote: RecordingNotice? = nil`, after `microphoneNote:`, so every caller compiles.

**Steps:**
- [ ] Write the design's `RecordingNoticeOrderTests` and see them fail: the camera note after the microphone note and the highlights note after it; after `.nothing`'s notice with no save notice; nothing in quit mode; R2's tests pass with the two new arguments nil.
- [ ] Implement `afterStop` and pass the two notes through `postAfterStop`.
- [ ] In `record`, after `recorder.run` returns and before `recorder.close()`: `CameraNote.afterStop(start: start.camera.note, wanted: summary.bubbleWanted, missed: summary.missed.contains(.bubble), loss: extras?.cameraLoss)` and `ClickHighlightRule.noteAfterStop(onAtStart: summary.highlightsAtStart, missed: summary.missed.contains(.highlights))`, with `summary = recorder.extrasSummary`. A window recording's summary is empty, so neither posts.
- [ ] In `endRecording`, both notes reach every path: `.nothing` through `postAfterStop`; an MP4 through `saveRecording`; a muted MP4 through `muteAndSave`; a GIF through `makeGIF`'s `save` closure, unlike the microphone note, which a GIF never has. The hold covers them (Decided 2026-10-24, 8): they post after Stop, after the save's own notification.
- [ ] Run the full suite.
- [ ] Hand checks (Tim's, for the checklist): Deny at the camera prompt posts `Recorded without the webcam bubble` / `Camera access is off for TidyShot.` after Stop and after the save's notification; the chosen camera unplugged before recording gives `Recorded with <name>`; the Brio unplugged mid-recording gives `Camera lost`; the bubble turned off from the bar logs no loss and posts no note; a recording with the toggle off and the bar never pressed posts no camera note, whatever the access; a 15 and a 10 fps GIF of 60 s show each click in its colour and a face with the bubble.
- [ ] Commit: `feat: post the camera and highlights notes after Stop`.

### Task 14: Checklist, README and design close-out

**Files:**
- Create `docs/testing/recording-r3-manual-checklist.md`.
- Modify:
  - `README.md`: Permissions (:34-58), the camera as a fourth optional permission, with its entitlement, its three Info.plist keys and `tccutil reset Camera io.tky.tidyshot`; Screen recording (:213-345), `Highlight clicks`, `Show webcam bubble`, `Camera`, `Bubble size`, the two bar buttons, and that neither applies to a window recording; Documents (:647-668), lines for the R3 design and the checklist;
  - the R3 design: the probe results the tasks could not record, and an "R3 built notes" section;
  - `docs/superpowers/specs/2026-10-21-tidyshot-screen-recording-design.md` (:101): "What stays out" names R3's two filmed windows as exceptions beside the covers, pointing to the R3 design;
  - `docs/superpowers/specs/2026-10-23-coordinator-split-design.md`, section 6: an R3 bullet for `askingPermission` and `PermissionPrompt` in `AppCoordinator.swift`, the camera prompt, the camera resolve, `RecordingExtras` and the notes in `+Recording`, and `requestAccessFromSettings(_:)` as the one new entry point, used by `CaptureSettingsView`.

**Steps:**
- [ ] Grep the finished code for every string the design gives (Settings rows and captions, tool tips, accessibility labels, notes, log lines, Info.plist strings), and fix any drift.
- [ ] Run the coordinator split's surface check (its plan's Task 7 command) with `requestAccessFromSettings` added to the entry points; it prints nothing.
- [ ] Write the checklist in the form of `recording-r2-manual-checklist.md`: setup, a Release build, the grants Tim gives (Screen Recording, Camera), the defaults to delete (`recordingClickHighlights`, `recordingWebcamBubble`, `recordingCamera`, `recordingCameraName`, `recordingBubbleSize`, `recordingBubbleInsetRight`, `recordingBubbleInsetBottom`), and `tccutil reset Camera io.tky.tidyshot` as Tim's step. It covers every probe still open with its command and a blank for the result, every hand check in the design and in Tasks 7 and 10 to 13, the budget (CPU in Activity Monitor and `footprint TidyShot` before and during a minute with the bubble at Medium and steady clicking), lip sync with a clap (`mute-offset-onsets.py` for the sound's onset), and every gap above to confirm or overrule. Log lines are read with `/usr/bin/log show --last 10m --style compact --predicate 'process == "TidyShot"' | grep "Recording:"`.
- [ ] Write the README text and the Built notes: what was built differently, the seventeen gaps, the probe results (P2's with what Tim said, when it answered all four yes), any held step Tim chose to ship without, and the items still open, which the PR lists.
- [ ] Run the full suite and the Release build once. `codesign -d --entitlements - .build-rel/Build/Products/Release/TidyShot.app` lists exactly R2's entitlements plus `com.apple.security.device.camera`; `strings` on the binary finds no `ClickMonitorSpike`.
- [ ] Commit: `docs: recording R3 checklist, README and design close-out`.

## Test totals

| After | Total |
|---|---|
| Baseline | 1633 tests in 153 suites (main after R2) |
| Task 1 | unchanged |
| Task 2 | baseline plus `ClickHighlightRuleTests` and `ClickRingTimingTests` (2 new suites) |
| Task 3 | Task 2 plus the `GIFPaletteBuilderTests` and `GIFMakerTests` additions |
| Task 4 | Task 3 plus `BubblePlacementTests` and `CameraRunStateTests` (2 new suites) |
| Task 5 | Task 4 plus `RecordingOptionsTests` (1 new suite) and the `AppSettingsTests` and `RecordingSettingsLayoutTests` additions |
| Task 6 | Task 5 plus `CameraChoiceTests`, `CameraNoteTests` and `BubbleButtonStateTests` (3 new suites) |
| Task 7 | Task 6 with `ShortcutsTests` and `URLCommandHandlerTests` changed and extended |
| Task 8 | Task 7 plus the `RecordingConfigurationTests` and `RecordingControllerTests` additions |
| Task 9 | Task 8 plus the `RecordingPanelLayoutTests` and `RecordingControllerTests` additions |
| Task 10 | Task 9 plus `ClickHighlighterTests` and `ClickRingOverlayTests` (2 new suites) |
| Task 11 | Task 10 plus `WebcamBubblePanelTests` and `CameraSessionTests` (2 new suites) |
| Task 12 | Task 11 plus `RecordingExtrasPlaceTests` (1 new suite) |
| Task 13 | Task 12 plus the `RecordingNoticeOrderTests` additions |
| Task 14 | unchanged: 166 suites, the baseline's plus 13 |
