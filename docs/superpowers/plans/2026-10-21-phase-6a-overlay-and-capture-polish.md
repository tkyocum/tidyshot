# TidyShot Phase 6a: Overlay and Capture Polish, Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The polish Tim uses on every capture: the cursor rule and window-shadow option, freeze screen, a stack of Quick Access cards on the capture's display with a close badge and restore, Save As… and Copy Image on the card, drag-out of a real file, and Capture Previous Area.

**Architecture:** Spec 2.9. Pure helpers carry the decisions (capture options, freeze crop, stack layout, overlay screen choice, closed-overlay restore list, drag file naming, previous-area geometry); `QuickAccessController` grows from one panel to a stack of cards; `AppCoordinator` stays the one save, upload and delete path; drag-out hands over a file URL to a copy in the container (`DragFileStore`), amending decision 6.

**Tech Stack:** Swift 6 language mode with default `MainActor` isolation and `NonisolatedNonsendingByDefault`, AppKit (`NSPanel`, `NSDraggingSource`, `NSSavePanel`, `NSMenu`), SwiftUI (`NSHostingView`), ScreenCaptureKit, KeyboardShortcuts, Swift Testing, XcodeGen 2.46.

Spec: `docs/superpowers/specs/2026-10-19-tidyshot-screenshot-design.md`, section 2.9 (all of it, the 6a parts binding) and section 6 (Phase 6). Section 2.9 is the authority for behaviour, names and exact strings; when this plan and 2.9 disagree, stop and ask, except for the six points listed under "How code is specified", which the controller decided and Task 8 writes into 2.9.

Builds on Phases 0-5 (merged; Phase 5 as PR 11, a1dde71). Work happens on the branch `phase-6-polish`, created from `main` at a1dde71, which also holds the spec commit 9ae28c4. Confirm:

```bash
git switch phase-6-polish
git merge-base --is-ancestor 9ae28c4 HEAD && echo SPEC_PRESENT
```
Expected: `Already on 'phase-6-polish'` (or `Switched to branch 'phase-6-polish'`) then `SPEC_PRESENT`.

## How code is specified in this plan

Each task gives the exact Swift interfaces it produces, complete Swift Testing test code, and complete code for pure helpers and algorithms (the capture options and cursor rule, the window pixel size, the freeze crop, the stack layout, the overlay screen choice, the closed-overlay list, the drag file name and store, the previous-area geometry). AppKit windows, the panels, the SwiftUI views and menu wiring are specified by structure, exact names, behaviour and hand checks, and the implementer writes that code. The tests and the interfaces are the contract: a reviewer rejects a task whose names, signatures, strings or test assertions differ from this plan or from spec 2.9.

Six points in this plan go beyond 2.9's text or settle what it left open, and Task 8 writes each into 2.9:
1. Window shadow: the built path is the system shadow (`ignoreShadows = false`, sized by `CaptureEngine.windowPixelSize` from the filter's `contentRect` and `pointPixelScale`). The probe is not an implementer step: Task 1 commits `probes/window-shadow/probe.swift`, and Tim runs it as a hand check (Task 1, Task 8's checklist) and records the result in the research notes. The synthetic shadow (`WindowShadow.composite`) is written in Task 1 as a documented fallback and is not built.
2. Drag-out: the detached copy starts at mouse-down on the card, and the drag session begins once the file exists (2.9 says the copy is made at drag start).
3. The card's Save As… posts its download, when one is needed, under the title `Saving a copy…`.
4. The Overlay stepper reads `Show up to 1 overlay` at 1 and `Show up to N overlays` otherwise.
5. The cards move together through `NSAnimationContext` and `animator().setFrame(_:display:)`, not `setFrame(_:display:animate: true)`, which animates one window after another and blocks the main actor.
6. The file-promise fallback for drag-out (Task 6, Step 9) is not built in 6a; it is a follow-up, built only if Tim's checklist shows a receiver refusing the file URL.

## Global Constraints

- Every Phase 0 to 3.1 constraint still applies: minimum macOS `26.0`, Xcode 27.1 with the macOS 27.0 SDK, App Sandbox on with no new entitlements, Swift 6 language mode with `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` and `SWIFT_APPROACHABLE_CONCURRENCY = YES`, `KeyboardShortcuts` as the only package, credentials only in the Keychain, files in the save folder only through the security-scoped bookmark, thumbnails and upload-only files in the container next to `history.json`, one token engine for file names and object keys, keys named when the upload starts, HEAD before PUT for template keys, and no GPL-licensed code read or copied.
- New code lives where spec 2.9 names it (`Capture/`, `Selection/`, `Overlay/`, `Output/`, `App/`, `Settings/`). New tests live in `TidyShotTests/`, shared helpers in `TidyShotTests/Support/`. XcodeGen's recursive source paths pick new folders up; run `xcodegen generate` after adding files.
- Concurrency: any `nonisolated async` function that must run off the main actor is marked `@concurrent`. Tests never block the main actor with a semaphore; fakes wait on an async gate.
- Tests use Swift Testing, run with:
  ```bash
  xcodegen generate && xcodebuild test -project TidyShot.xcodeproj -scheme TidyShot -destination 'platform=macOS' -derivedDataPath .build 2>&1 | grep -E "Test run with|error:|TEST"
  ```
  Baseline `Test run with 602 tests in 76 suites passed`; the totals after each task are in the table below.
- Commit after every task with a conventional commit message and no attribution lines. Never include a Claude Code session URL in a commit or PR. This plan never pushes or opens a PR: the last task stops after its commit, and the controller pushes and opens the PR after the whole-branch review.
- Phase 6a specifics:
  - One save, upload and delete path: every card action (Save As…, Copy Image, Delete, drag-out) goes through `AppCoordinator`; no new path writes the save folder except through the bookmark or a user-chosen save panel URL.
  - Drag-out hands over a file URL to a copy in the container, never the original save-folder file; no new entitlement; no `NSFilePromiseProvider` unless the plan says it is the fallback.
  - Quick Access cards are excluded from every capture; the cursor shows only in captures taken without the selection overlay up.
  - Exact strings come from spec 2.9.
  - Run builds Tim uses as Release (`-configuration Release -derivedDataPath .build-rel`); tests use Debug.
  - Research notes: `docs/superpowers/research/phase-6-research.md` (in the repo). Every reference to the research notes, and every probe result, points there.
  - Hand checks are Tim's. Anything that needs the GUI (the window-shadow probe, drag-out receivers, the context menu in a non-activating panel, freeze drawing and latency, displays, VoiceOver) is a hand check for Tim, never an implementer step: the implementer builds, does not wait for a GUI result, lists the task's hand checks in its report and goes on to the commit. Task 8's checklist collects every hand check. A fallback written for a failed hand check (Task 1's synthetic shadow, Task 2's layer backdrop, Task 4's `NSHostingView` menu, Task 6's file promise) is not built in 6a; it becomes a follow-up only when Tim's checklist shows the failure.

## Test totals

| After | New tests | New suites | Total |
|---|---|---|---|
| Baseline | | | 602 tests in 76 suites |
| Task 1 | 8 | 2 | 610 tests in 78 suites |
| Task 2 | 10 | 1 | 620 tests in 79 suites |
| Task 3 | 15 | 2 | 635 tests in 81 suites |
| Task 4 | 8 | 1 | 643 tests in 82 suites |
| Task 5 | 2 | 0 | 645 tests in 82 suites |
| Task 6 | 14 | 2 | 659 tests in 84 suites |
| Task 7 | 16 | 1 | 675 tests in 85 suites |
| Task 8 | 0 | 0 | 675 tests in 85 suites |

The totals come from each task's declared tests. Task 8 checks them against a real run and adds a note for any difference.

---

### Task 1: Capture options: cursor rule and window shadow

**Files:**
- Create: `probes/window-shadow/probe.swift` (a probe Tim runs as a hand check, committed; not part of the Xcode project)
- Create: `TidyShotTests/CaptureOptionsTests.swift` (struct `CaptureOptionsTests`), `TidyShotTests/WindowShadowTests.swift` (struct `WindowShadowTests`, testing `CaptureEngine.windowPixelSize`)
- Not created in 6a: `TidyShot/Capture/WindowShadow.swift` (the synthetic-shadow fallback, written out at the end of this task)
- Modify: `TidyShot/Capture/CaptureTarget.swift` (`CaptureOptions`, lines 11-13)
- Modify: `TidyShot/Capture/CaptureEngine.swift` (`capture(_:options:excludingWindows:)`, lines 13-46; a new static `windowPixelSize` after `capture`, line 46)
- Modify: `TidyShot/Settings/AppSettings.swift` (`Keys`, line 50; properties, line 78; `register`, line 114; `init`, line 137)
- Modify: `TidyShot/Settings/CaptureSettingsView.swift` (whole body, lines 6-11)
- Modify: `TidyShot/App/AppCoordinator.swift` (`runSelection`, lines 178-183; `capture(_:excludingWindows:)`, lines 198-206)
- Test: `TidyShotTests/AppSettingsTests.swift` (modified, one test appended after line 112); `TidyShotTests/CaptureOptionsTests.swift` and `TidyShotTests/WindowShadowTests.swift` (new)

**Interfaces:**
- Consumes (all on `main`): `CaptureOptions(showsCursor:)` (`CaptureTarget.swift:11`), `CaptureEngine.capture(_:options:excludingWindows:)`, `Geometry.pixelSize(points:scale:) -> (width: Int, height: Int)` (`Geometry.swift:24`), `CaptureEngine.scale(forDisplayID:)`, `AppSettings.showsCursor`, `AppCoordinator.capture(_:excludingWindows:)` (`AppCoordinator.swift:198`), `SelectionController.takeSnapshots()` which builds `CaptureOptions(showsCursor: false)` (`SelectionController.swift:83`, unchanged and still compiling).
- Produces:
  - `struct CaptureOptions: Equatable { var showsCursor: Bool; var windowShadow: Bool; init(showsCursor: Bool = false, windowShadow: Bool = false) }` (the memberwise init, kept) and, in an extension, `init(settings: AppSettings, duringSelection: Bool)`: `showsCursor = settings.showsCursor && !duringSelection`, `windowShadow = settings.windowShadow`. This is the one place the cursor rule lives.
  - `AppSettings.windowShadow: Bool` (key `windowShadow`, default false, persisted).
  - `AppCoordinator.capture(_ target: CaptureTarget, excludingWindows: [SCWindow] = [], duringSelection: Bool = false) async -> CaptureResult?`. The two live captures taken while the selection overlay is up pass `duringSelection: true`; every other caller (fullscreen now; Capture Previous Area, Self-Timer and URL captures later) keeps the default `false`, so the pointer follows the setting.
  - `CaptureEngine` window captures honour `options.windowShadow` with the system shadow (`ignoreShadows = !options.windowShadow`), the output sized through `static func windowPixelSize(frame: CGRect, contentRect: CGRect, pointPixelScale: CGFloat, displayScale: CGFloat, includeShadow: Bool) -> (width: Int, height: Int)` on `CaptureEngine`. Later tasks do not use it directly. The synthetic shadow, `WindowShadow.composite(_:scale:) -> CGImage?`, is a documented fallback at the end of this task and is not built.
  - The Capture tab with `Show cursor in screenshots` (new caption) and `Include window shadow`. Task 2 adds `Freeze screen while selecting` above them.

Behaviour (spec 2.9, Cursor and Window shadow):
- A capture taken while the selection overlay is up (live area and window captures after mouse-up) never shows the pointer. The overlay's crosshair is a real cursor (`SelectionView.resetCursorRects`, `SelectionView.swift:55`), and ScreenCaptureKit draws the cursor when `showsCursor` is true, so today Show cursor on puts TidyShot's own crosshair into the image. Fullscreen shows the pointer when the setting is on.
- `Include window shadow` (default off) keeps today's output when off: `ignoreShadows = true`, size from `window.frame`, transparent rounded corners. On, the image is the window with its system shadow, larger than the frame, with alpha outside the shadow.
- Exact strings. Toggle `Show cursor in screenshots`, caption `Fullscreen, previous-area, self-timer and URL captures show the pointer where it is. Area captures show it only with Freeze screen on. TidyShot never captures its own crosshair.` Toggle `Include window shadow`, caption `Window captures keep transparent rounded corners either way.`

- [ ] **Step 1: Write the window-shadow probe (Tim runs it)**

Nothing about `SCContentFilter.contentRect` or `SCScreenshotConfiguration.ignoreShadows = false` with an explicit size is documented (research notes, `docs/superpowers/research/phase-6-research.md`, Platform and probe 1). The build takes the system shadow (header, point 1); the probe tells Tim whether it holds. Create `probes/window-shadow/probe.swift` (a single-file command-line tool; `probes/` is outside `project.yml`'s source paths, so XcodeGen ignores it):
```swift
// Build: swiftc -parse-as-library -O probes/window-shadow/probe.swift -o .build/window-shadow-probe
// Run:   .build/window-shadow-probe com.apple.finder com.tinyspeck.slackmacgap
// The terminal that runs it needs the Screen Recording grant. Writes PNGs to the temporary folder.
import AppKit
import ImageIO
import ScreenCaptureKit
import UniformTypeIdentifiers

@main
struct WindowShadowProbe {
    static func main() async {
        let outDir = URL(fileURLWithPath: NSTemporaryDirectory()).appending(path: "window-shadow-probe")
        try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
        print("PNGs in \(outDir.path(percentEncoded: false))")
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            for bundleID in CommandLine.arguments.dropFirst() {
                let candidates = content.windows.filter {
                    $0.owningApplication?.bundleIdentifier == bundleID && $0.windowLayer == 0
                        && $0.frame.width > 200 && $0.frame.height > 150
                }
                guard let window = candidates.max(by: { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }) else {
                    print("\(bundleID): no suitable on-screen window")
                    continue
                }
                await probe(window, name: bundleID, outDir: outDir)
            }
        } catch {
            print("failed: \(error)")
        }
    }

    static func probe(_ window: SCWindow, name: String, outDir: URL) async {
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let scale = CGFloat(filter.pointPixelScale)
        let fromFilter = (width: Int((filter.contentRect.width * scale).rounded()), height: Int((filter.contentRect.height * scale).rounded()))
        print("\n\(name): frame \(window.frame), contentRect \(filter.contentRect), pointPixelScale \(filter.pointPixelScale)")
        print("  frame x scale = \(Int((window.frame.width * scale).rounded())) x \(Int((window.frame.height * scale).rounded())), contentRect x scale = \(fromFilter.width) x \(fromFilter.height)")
        for ignoreShadows in [true, false] {
            for sizedFromFilter in [false, true] {
                let config = SCScreenshotConfiguration()
                config.showsCursor = false
                config.dynamicRange = .sdr
                config.ignoreShadows = ignoreShadows
                if sizedFromFilter {
                    config.width = fromFilter.width
                    config.height = fromFilter.height
                }
                let label = "ignoreShadows=\(ignoreShadows) size=\(sizedFromFilter ? "contentRect x scale" : "unset")"
                guard let image = try? await SCScreenshotManager.captureScreenshot(contentFilter: filter, configuration: config).sdrImage else {
                    print("  \(label): capture failed")
                    continue
                }
                let w = image.width, h = image.height
                let corners = [(0, 0), (w - 1, 0), (0, h - 1), (w - 1, h - 1)].map { alpha(of: image, x: $0.0, y: $0.1) }
                let below = alpha(of: image, x: w / 2, y: max(0, h - 1 - Int(20 * scale)))
                print("  \(label): \(w) x \(h); corner alphas \(corners); alpha 20 pt above the last row \(below); alpha of last row \(alpha(of: image, x: w / 2, y: h - 1))")
                let file = outDir.appending(path: "\(name)-\(ignoreShadows ? "noshadow" : "shadow")-\(sizedFromFilter ? "filter" : "default").png")
                if let destination = CGImageDestinationCreateWithURL(file as CFURL, UTType.png.identifier as CFString, 1, nil) {
                    CGImageDestinationAddImage(destination, image, nil)
                    CGImageDestinationFinalize(destination)
                }
            }
        }
    }

    /// The alpha byte of the pixel at (x, y), counted from the top left.
    static func alpha(of image: CGImage, x: Int, y: Int) -> Int {
        guard let context = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let data = context.data?.assumingMemoryBound(to: UInt8.self) else { return -1 }
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return Int(data[y * context.bytesPerRow + x * 4 + 3])
    }
}
```
Check that it compiles, without running it (running needs the Screen Recording grant and on-screen windows, so it is Tim's):
```bash
mkdir -p .build && swiftc -parse-as-library -O probes/window-shadow/probe.swift -o .build/window-shadow-probe && echo PROBE_BUILT
```
Expected: `PROBE_BUILT`. Do not run the binary; Step 6 lists the run for Tim.

- [ ] **Step 2: Write the failing tests**

`TidyShotTests/CaptureOptionsTests.swift`:
```swift
import Foundation
import Testing
@testable import TidyShot

struct CaptureOptionsTests {
    func settings(showsCursor: Bool, windowShadow: Bool = false) -> AppSettings {
        let name = "CaptureOptionsTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        let settings = AppSettings(defaults: defaults)
        settings.showsCursor = showsCursor
        settings.windowShadow = windowShadow
        return settings
    }

    /// The overlay's crosshair is a real cursor, so no capture taken while the overlay is up may
    /// ask for the pointer, whatever the setting says.
    @Test func aCaptureDuringSelectionNeverShowsTheCursor() {
        #expect(CaptureOptions(settings: settings(showsCursor: true), duringSelection: true).showsCursor == false)
        #expect(CaptureOptions(settings: settings(showsCursor: false), duringSelection: true).showsCursor == false)
    }

    /// Fullscreen, previous-area, self-timer and URL captures (no overlay) and a frozen snapshot
    /// follow the setting.
    @Test func aCaptureWithoutTheOverlayFollowsTheSetting() {
        #expect(CaptureOptions(settings: settings(showsCursor: true), duringSelection: false).showsCursor)
        #expect(CaptureOptions(settings: settings(showsCursor: false), duringSelection: false).showsCursor == false)
    }

    /// The shadow option does not depend on the overlay.
    @Test func theWindowShadowFollowsTheSettingEitherWay() {
        for duringSelection in [true, false] {
            #expect(CaptureOptions(settings: settings(showsCursor: false, windowShadow: true), duringSelection: duringSelection).windowShadow)
            #expect(CaptureOptions(settings: settings(showsCursor: true, windowShadow: false), duringSelection: duringSelection).windowShadow == false)
        }
        #expect(CaptureOptions() == CaptureOptions(showsCursor: false, windowShadow: false))
    }
}
```

`TidyShotTests/AppSettingsTests.swift`, append inside the struct, after `scrollingAutoScrollDefaultsOnAndPersists` (line 112):
```swift

    /// Include window shadow is off by default, which keeps today's output, and persists (spec 2.9).
    @Test func windowShadowDefaultsOffAndPersists() {
        let defaults = freshDefaults()
        let first = AppSettings(defaults: defaults)
        #expect(!first.windowShadow)
        first.windowShadow = true
        #expect(defaults.object(forKey: "windowShadow") as? Bool == true)
        #expect(AppSettings(defaults: defaults).windowShadow)
    }
```

`TidyShotTests/WindowShadowTests.swift` (the system shadow, sized from the filter):
```swift
import CoreGraphics
import Testing
@testable import TidyShot

struct WindowShadowTests {
    let frame = CGRect(x: 100, y: 80, width: 800, height: 600)
    let withShadow = CGRect(x: 60, y: 50, width: 880, height: 680)

    /// Shadow off: today's size, from the window's frame and the display's scale.
    @Test func withoutTheShadowTheSizeComesFromTheFrame() {
        let size = CaptureEngine.windowPixelSize(frame: frame, contentRect: withShadow, pointPixelScale: 2,
                                                 displayScale: 2, includeShadow: false)
        #expect(size.width == 1600)
        #expect(size.height == 1200)
    }

    /// Shadow on: the filter's content rect times its point-pixel scale, rounded like
    /// `Geometry.pixelSize` rounds (half away from zero).
    @Test func withTheShadowTheSizeComesFromTheFilter() {
        let size = CaptureEngine.windowPixelSize(frame: frame, contentRect: withShadow, pointPixelScale: 2,
                                                 displayScale: 2, includeShadow: true)
        #expect(size.width == 1760)
        #expect(size.height == 1360)
        let odd = CaptureEngine.windowPixelSize(frame: frame, contentRect: CGRect(x: 0, y: 0, width: 880.25, height: 680),
                                                pointPixelScale: 2, displayScale: 2, includeShadow: true)
        #expect(odd.width == 1761)
        let other = CaptureEngine.windowPixelSize(frame: frame, contentRect: withShadow, pointPixelScale: 1.5,
                                                  displayScale: 2, includeShadow: true)
        #expect(other.width == 1320)
        #expect(other.height == 1020)
    }

    /// A filter that reports nothing useful must not produce a zero-sized capture.
    @Test func aDegenerateFilterFallsBackToTheFrame() {
        let empty = CaptureEngine.windowPixelSize(frame: frame, contentRect: .zero, pointPixelScale: 2,
                                                  displayScale: 2, includeShadow: true)
        #expect(empty.width == 1600)
        #expect(empty.height == 1200)
        let noScale = CaptureEngine.windowPixelSize(frame: frame, contentRect: withShadow, pointPixelScale: 0,
                                                    displayScale: 2, includeShadow: true)
        #expect(noScale.width == 1600)
        #expect(noScale.height == 1200)
    }

    /// A content rect smaller than the frame cannot be the shadowed window; keep the frame.
    @Test func aContentRectSmallerThanTheFrameFallsBackToTheFrame() {
        let size = CaptureEngine.windowPixelSize(frame: frame, contentRect: CGRect(x: 100, y: 80, width: 700, height: 600),
                                                 pointPixelScale: 2, displayScale: 2, includeShadow: true)
        #expect(size.width == 1600)
        #expect(size.height == 1200)
    }
}
```

- [ ] **Step 3: Run the new tests and see them fail**

Run the header's full-suite command. Expected: the build fails with `error:` lines naming the missing members: `value of type 'AppSettings' has no member 'windowShadow'`, `extra argument 'settings' in call` (or `no exact matches in call to initializer`) for `CaptureOptions(settings:duringSelection:)`, `has no member 'windowShadow'` for `CaptureOptions`, and in `WindowShadowTests` `type 'CaptureEngine' has no member 'windowPixelSize'`. No `Test run` line appears.

- [ ] **Step 4: Implement**

`TidyShot/Settings/AppSettings.swift`:
- `Keys` (after line 50): `static let windowShadow = "windowShadow"`.
- After `scrollingAutoScroll` (line 78): 
  ```swift
      /// The Capture tab's Include window shadow. Off keeps window shots without a shadow.
      var windowShadow: Bool { didSet { defaults.set(windowShadow, forKey: Keys.windowShadow) } }
  ```
- `register(defaults:)`, after `Keys.scrollingAutoScroll: true,` (line 114): `Keys.windowShadow: false,`
- `init`, after `scrollingAutoScroll = defaults.bool(...)` (line 137): `windowShadow = defaults.bool(forKey: Keys.windowShadow)`

`TidyShot/Capture/CaptureTarget.swift`, replace lines 11-13 with:
```swift
struct CaptureOptions: Equatable {
    var showsCursor: Bool = false
    /// Window captures only: keep the window's shadow (spec 2.9). Off is today's output.
    var windowShadow: Bool = false
}

extension CaptureOptions {
    /// The one place the cursor rule lives (spec 2.9, Cursor). A capture taken while the
    /// selection overlay is up never shows the pointer: it would be TidyShot's own crosshair.
    /// Any other capture, and a frozen snapshot taken before the overlay appears, follows the
    /// setting. In an extension so the memberwise `init(showsCursor:windowShadow:)` stays.
    init(settings: AppSettings, duringSelection: Bool) {
        self.init(showsCursor: settings.showsCursor && !duringSelection, windowShadow: settings.windowShadow)
    }
}
```

`TidyShot/Capture/CaptureEngine.swift`: replace the body of `capture` from line 14 to line 41 (`config.height = pixels.height`) so the size is chosen in each case:
```swift
        let config = SCScreenshotConfiguration()
        config.showsCursor = options.showsCursor
        config.dynamicRange = .sdr

        let filter: SCContentFilter
        let scale: CGFloat
        let pixels: (width: Int, height: Int)

        switch target {
        case .display(let display):
            filter = SCContentFilter(display: display, excludingWindows: excludingWindows)
            scale = Self.scale(forDisplayID: display.displayID)
            pixels = Geometry.pixelSize(points: display.frame.size, scale: scale)
        case .area(let rect, let display):
            filter = SCContentFilter(display: display, excludingWindows: excludingWindows)
            scale = Self.scale(forDisplayID: display.displayID)
            config.sourceRect = Geometry.displayLocal(rect, in: display.frame)
            pixels = Geometry.pixelSize(points: rect.size, scale: scale)
        case .window(let window):
            filter = SCContentFilter(desktopIndependentWindow: window)
            // Off is today's output. On, the shadow lies outside `window.frame`, so the size
            // comes from the filter (see `windowPixelSize`).
            config.ignoreShadows = !options.windowShadow
            scale = Self.scale(forDisplayID: Self.displayID(containing: window.frame))
            pixels = Self.windowPixelSize(frame: window.frame, contentRect: filter.contentRect,
                                          pointPixelScale: CGFloat(filter.pointPixelScale),
                                          displayScale: scale, includeShadow: options.windowShadow)
        }
        config.width = pixels.width
        config.height = pixels.height
```
The rest of the function (lines 43-45) is unchanged. After `capture` (line 46) add:
```swift
    /// The pixel size of a window capture. Without the shadow: the frame at the display's scale,
    /// as before. With it: the filter's `contentRect` (points) times `pointPixelScale`, which the
    /// probe (`probes/window-shadow`) checks includes the shadow. A degenerate filter (empty or smaller than
    /// the frame, or a zero scale) falls back to the frame, so a capture is never zero-sized.
    static func windowPixelSize(frame: CGRect, contentRect: CGRect, pointPixelScale: CGFloat,
                                displayScale: CGFloat, includeShadow: Bool) -> (width: Int, height: Int) {
        if includeShadow, pointPixelScale > 0,
           contentRect.width >= frame.width, contentRect.height >= frame.height {
            return Geometry.pixelSize(points: contentRect.size, scale: pointPixelScale)
        }
        return Geometry.pixelSize(points: frame.size, scale: displayScale)
    }
```
`CaptureResult.scale` stays the display's scale. The probe prints `pointPixelScale`, which should equal it (2 on a Retina display); if Tim's run shows otherwise, using `pointPixelScale` for the window result's scale is a follow-up.

`TidyShot/App/AppCoordinator.swift`:
- `capture(_:excludingWindows:)` (lines 198-206) becomes:
  ```swift
      /// Runs the engine. On failure posts a notification and returns nil. `duringSelection` is
      /// true for the live captures taken while the selection overlay is still up; the pointer is
      /// then never captured (`CaptureOptions.init(settings:duringSelection:)`).
      func capture(_ target: CaptureTarget, excludingWindows: [SCWindow] = [],
                   duringSelection: Bool = false) async -> CaptureResult? {
          do {
              let options = CaptureOptions(settings: settings, duringSelection: duringSelection)
              return try await engine.capture(target, options: options, excludingWindows: excludingWindows)
          } catch {
              NSLog("Capture failed: \(error.localizedDescription)")
              notifier.notifyError(error.localizedDescription)
              return nil
          }
      }
  ```
- `runSelection` (lines 178-183): the area call at line 180 becomes `result = await capture(.area(rect: rect, display: display), excludingWindows: overlays, duringSelection: true)`; the window call at line 182 becomes `result = await capture(.window(window), duringSelection: true)`.
- `captureFullscreen()` (line 125) is unchanged: it keeps the default `false`, so the pointer follows the setting.

`TidyShot/Settings/CaptureSettingsView.swift`, replace the `Form` content (lines 7-9):
```swift
        Form {
            Toggle("Show cursor in screenshots", isOn: $settings.showsCursor)
            Text("Fullscreen, previous-area, self-timer and URL captures show the pointer where it is. Area captures show it only with Freeze screen on. TidyShot never captures its own crosshair.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Toggle("Include window shadow", isOn: $settings.windowShadow)
            Text("Window captures keep transparent rounded corners either way.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
```

- [ ] **Step 5: Run the full suite**

Run the header's full-suite command. Expected: no `error:` lines, and `Test run with 610 tests in 78 suites passed`. This task adds 8 tests and 2 suites: `CaptureOptionsTests` (3: `aCaptureDuringSelectionNeverShowsTheCursor`, `aCaptureWithoutTheOverlayFollowsTheSetting`, `theWindowShadowFollowsTheSettingEitherWay`), `WindowShadowTests` (4: `withoutTheShadowTheSizeComesFromTheFrame`, `withTheShadowTheSizeComesFromTheFilter`, `aDegenerateFilterFallsBackToTheFrame`, `aContentRectSmallerThanTheFrameFallsBackToTheFrame`) and `AppSettingsTests.windowShadowDefaultsOffAndPersists` (1). Nothing is removed or renamed. `xcodegen generate` is clean (the `probes/` folder is not a source path).

- [ ] **Step 6: Hand checks (Tim)**

For Tim; the implementer lists these in its report and goes on to Step 7. Task 8's checklist repeats them.
- The probe: open a Finder window and a Slack window (or any Electron window), then, in a terminal with the Screen Recording grant:
  ```bash
  mkdir -p .build && swiftc -parse-as-library -O probes/window-shadow/probe.swift -o .build/window-shadow-probe && .build/window-shadow-probe com.apple.finder com.tinyspeck.slackmacgap
  ```
  For each app a header line and four capture lines. Open the `ignoreShadows=false size=contentRect x scale` PNG and the `ignoreShadows=true size=unset` PNG of each window. The system shadow passes only if, for both windows: (1) the shadowed image is larger than frame x scale on every side (roughly 20 pt or more at the bottom, less at the top); (2) the four corner alphas are 0 and the last row's alpha is 0 or small while the alpha 20 pt above it is above 0 (the shadow fades out inside the image, not cut off); (3) the window is at 1:1 (title bar and traffic lights the same pixel size as in the shadow-off PNG). Anything else, including `contentRect` equal to `frame`, fails. Record the sizes, the corner alphas, the three checks, pass or fail, `pointPixelScale` and the macOS build under probe 1 in `docs/superpowers/research/phase-6-research.md`. A failure makes the synthetic-shadow fallback below a follow-up.
- Settings > Capture shows both toggles with their captions, in this order (Release build, re-grant Screen Recording after an ad-hoc rebuild).
- Cursor, the bug: turn Show cursor on. Area capture (⌃⇧4) of a region holding text: the saved image has no crosshair. Window capture (⌃⇧2) of a window with the pointer over it: no crosshair. Fullscreen (⌃⇧3) with the pointer in a quiet spot: the arrow is in the image. Turn Show cursor off: fullscreen has no pointer. The loupe and the dimming are not in any image, as before.
- Shadow off: window capture is the window with transparent rounded corners and no shadow, the same pixel size as before this task (record one image's size before and after). Shadow on: the image is larger, the shadow is soft, the corners and the area around the shadow are transparent (open it in Preview on a coloured background, or the editor), the window itself is not blurred or scaled (compare the traffic lights against a shadow-off capture). Repeat on the external display if there is one (scale 1 or 2).
- A shadow-on capture goes through the overlay, the clipboard, the thumbnail, the editor and an upload as any capture does; the uploaded PNG keeps its alpha.
- Scrolling capture still works (it does not use this path).

- [ ] **Step 7: Commit**

```bash
git add probes/window-shadow/probe.swift TidyShot/Capture/CaptureTarget.swift TidyShot/Capture/CaptureEngine.swift TidyShot/Settings/AppSettings.swift TidyShot/Settings/CaptureSettingsView.swift TidyShot/App/AppCoordinator.swift TidyShotTests/CaptureOptionsTests.swift TidyShotTests/WindowShadowTests.swift TidyShotTests/AppSettingsTests.swift
git commit -m "feat: cursor rule for live captures and an Include window shadow option"
```

#### Fallback, not built in 6a: the synthetic shadow

Built only as a follow-up, and only if Tim's probe (Step 6) or the shadow items of Task 8's checklist fail. The suite count stays the same (4 tests in `WindowShadowTests`). The commit then also adds `TidyShot/Capture/WindowShadow.swift`.

In `CaptureEngine.capture`, the `.window` case goes back to `config.ignoreShadows = true` with the size from the frame (`windowPixelSize(…, includeShadow: false)`), and the image lines at the end of the function become
```swift
        guard var image = output.sdrImage else { throw CaptureError.noImage }
        // The system shadow does not come out at 1:1 (research notes, probe 1), so draw one.
        if case .window = target, options.windowShadow, let shadowed = WindowShadow.composite(image, scale: scale) {
            image = shadowed
        }
        return CaptureResult(image: image, scale: scale, target: target)
```
and create `TidyShot/Capture/WindowShadow.swift`:
```swift
import CoreGraphics

/// A drop shadow for a window capture taken without the system shadow (spec 2.9, the fallback).
/// The window keeps its alpha; the output is padded and the shadow drawn from that alpha.
enum WindowShadow {
    /// Padding on each side, points.
    static let padding: CGFloat = 40
    /// Blur radius, points.
    static let blur: CGFloat = 20
    /// How far the shadow drops, points.
    static let drop: CGFloat = 10
    /// Black at this opacity.
    static let opacity: CGFloat = 0.4

    /// `image` padded by `padding` points on each side with a black shadow under it, or nil if
    /// no bitmap context could be made. `scale` is the capture's pixels per point.
    static func composite(_ image: CGImage, scale: CGFloat) -> CGImage? {
        let pad = Int((padding * scale).rounded())
        guard let context = CGContext(data: nil, width: image.width + pad * 2, height: image.height + pad * 2,
                                      bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        // setShadow works in device pixels and CoreGraphics y runs up, so a drop is negative.
        context.setShadow(offset: CGSize(width: 0, height: -drop * scale), blur: blur * scale,
                          color: CGColor(gray: 0, alpha: opacity))
        context.draw(image, in: CGRect(x: pad, y: pad, width: image.width, height: image.height))
        return context.makeImage()
    }
}
```
The values are tuned against a Cmd-Shift-4 Space shot; if tuning changes a constant, the tests below hold unless the padding changes (then update `theOutputIsPaddedFortyPointsOnEverySide` and the offsets in the other tests).

`TidyShotTests/WindowShadowTests.swift` then replaces the four `windowPixelSize` tests with these (the synthetic shadow; a pixel at (x, y) is counted from the top left, a row of the CG buffer is the image's top row first):
```swift
import CoreGraphics
import Testing
@testable import TidyShot

struct WindowShadowTests {
    /// An opaque red `width` by `height` image, as a window capture's body.
    func window(width: Int, height: Int) -> CGImage {
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()!
    }

    /// RGBA of the pixel at (x, y) counted from the top left.
    func rgba(_ image: CGImage, x: Int, y: Int) -> [Int] {
        let context = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let data = context.data!.assumingMemoryBound(to: UInt8.self)
        let base = y * context.bytesPerRow + x * 4
        return (0..<4).map { Int(data[base + $0]) }
    }

    /// 40 pt on every side, in pixels at the capture's scale.
    @Test func theOutputIsPaddedFortyPointsOnEverySide() throws {
        let shadowed = try #require(WindowShadow.composite(window(width: 200, height: 120), scale: 2))
        #expect(shadowed.width == 200 + 160)
        #expect(shadowed.height == 120 + 160)
        let plain = try #require(WindowShadow.composite(window(width: 100, height: 60), scale: 1))
        #expect(plain.width == 180)
        #expect(plain.height == 140)
    }

    @Test func theWindowKeepsItsPixelsAtItsOffset() throws {
        let shadowed = try #require(WindowShadow.composite(window(width: 100, height: 60), scale: 1))
        #expect(rgba(shadowed, x: 40 + 50, y: 40 + 30) == [255, 0, 0, 255])
        #expect(rgba(shadowed, x: 40, y: 40) == [255, 0, 0, 255])
        #expect(rgba(shadowed, x: 40 + 99, y: 40 + 59) == [255, 0, 0, 255])
    }

    /// The shadow drops 10 pt: just below the window it is darker than just above it.
    @Test func theShadowFallsBelowTheWindow() throws {
        let shadowed = try #require(WindowShadow.composite(window(width: 100, height: 60), scale: 1))
        let below = rgba(shadowed, x: 90, y: 40 + 60 + 5)
        let above = rgba(shadowed, x: 90, y: 40 - 3)
        #expect(below[3] > 0)
        #expect(above[3] > 0)
        #expect(below[3] > above[3])
        // The shadow is black at 0.4 opacity at most.
        #expect(below[3] <= 102)
        #expect(below[0] == 0)
    }

    @Test func theFarCornersStayTransparent() throws {
        let shadowed = try #require(WindowShadow.composite(window(width: 100, height: 60), scale: 1))
        #expect(rgba(shadowed, x: 0, y: 0)[3] <= 2)
        #expect(rgba(shadowed, x: shadowed.width - 1, y: shadowed.height - 1)[3] <= 2)
    }
}
```

### Task 2: Freeze screen

**Files:**
- Create: `TidyShot/Capture/FreezeCrop.swift` (`FrozenSnapshot`, `FreezeCrop`)
- Modify: `TidyShot/Selection/SelectionController.swift` (properties, lines 8-16; `select`, lines 22-60; `overlayWindows`, lines 66-72; `takeSnapshots`, lines 75-89; `dismiss`, lines 92-105; new `frozenCapture(for:)` and `captureFrozenSnapshots(options:)`)
- Modify: `TidyShot/Selection/SelectionView.swift` (`snapshot`, lines 17-25; `draw`, lines 129-161; `punchHole`, lines 163-166)
- Modify: `TidyShot/App/AppCoordinator.swift` (`runSelection`, lines 171-190; new `frozenResult(for:display:)` after it)
- Modify: `TidyShot/Settings/AppSettings.swift` (`Keys`, property, `register` and `init` lines, next to the `windowShadow` ones Task 1 added)
- Modify: `TidyShot/Settings/CaptureSettingsView.swift` (a toggle and caption above `Show cursor in screenshots`)
- Test: `TidyShotTests/FreezeCropTests.swift` (new, struct `FreezeCropTests`), `TidyShotTests/AppSettingsTests.swift` (modified, one test appended)

**Interfaces:**
- Consumes:
  - `main`: `SelectionController.select(mode:content:)` (`SelectionController.swift:22`), `overlayWindows()`, `dismiss()`, `SelectionWindow.displayID` (`SelectionWindow.swift:6`), `SelectionView.snapshot` and `snapshotScale` (`SelectionView.swift:19-25`), `CaptureEngine.capture(_:options:excludingWindows:) -> CaptureResult` (`.image`, `.scale`), `Geometry.displayLocal(_:in:)` and `Geometry.pixelSize(points:scale:)` (`Geometry.swift:20`, `:24`), `AppCoordinator.runSelection(mode:)`, `capture(_:excludingWindows:duringSelection:)`, `save(_:)`, `withCaptureLock`, `loadContent()`.
  - Task 1: `CaptureOptions(settings:duringSelection:)` (a snapshot taken before the overlay is not "during selection", so the pointer follows the setting), `AppCoordinator.capture(_:excludingWindows:duringSelection:)`, the Capture tab layout.
- Produces:
  - `nonisolated struct FrozenSnapshot: Sendable { let displayID: CGDirectDisplayID; let image: CGImage; let scale: CGFloat }` and `enum FreezeCrop` (`Capture/FreezeCrop.swift`):
    - `static func pixelRect(selection: CGRect, displayFrame: CGRect, scale: CGFloat, imageSize: CGSize) -> CGRect?`
    - `static func cropped(_ image: CGImage, selection: CGRect, displayFrame: CGRect, scale: CGFloat) -> CGImage?`
  - `SelectionController.select(mode: SelectionMode, content: SCShareableContent, freeze: CaptureOptions? = nil) async -> Selection?`. `freeze` is the options for the pre-overlay snapshots (nil: no freeze); it takes effect in `.area` mode only. Task 10 (All-in-One) passes the same value.
  - `SelectionController.frozenCapture(for displayID: CGDirectDisplayID) -> FrozenSnapshot?`: the snapshot taken for that display, valid until `dismiss()`; nil when freeze was off, the mode does not freeze, or that display's snapshot failed.
  - `SelectionView.isFrozen: Bool`: when true (and `snapshot` is set) the view draws the snapshot opaque under the dimming.
  - `SelectionController.overlayWindows()` returns `[]` at once when no overlay window exists (it has nothing to look up). Task 3 adds the Quick Access cards' window numbers to the set it looks up, which excludes the cards from the freeze snapshots with no change to this task's code.
  - `AppSettings.freezeScreen: Bool` (key `freezeScreen`, default false).

Behaviour (spec 2.9, Freeze screen):
- Setting `Freeze screen while selecting`, caption `Area selections show a still image of the screen and the capture is cut from it, so menus, tooltips and video stay as they were when you pressed the shortcut.`
- With it on, `select` captures every display before any overlay window appears (one `engine.capture(.display(_:))` per display, in a task group, `showsCursor` from the setting), then shows the overlay with each view's `snapshot` already set and `isFrozen = true`, so the screen appears to stop. After mouse-up the coordinator takes the display's frozen image and crops it to the selection instead of capturing again. The result is saved as an `.area(rect:display:)` capture through `save(_:)` like a live one.
- The crop has the same pixel size as a live capture of the same rect (`FreezeCrop.pixelRect` rounds the size as `Geometry.pixelSize` does).
- A display whose snapshot failed falls back: its view is not frozen (the live screen shows) and the coordinator captures live, with the cursor rule of Task 1 (`duringSelection: true`).
- Window mode and scrolling mode ignore Freeze: a window is captured from its own surface, scrolling is live by nature. With Freeze off nothing changes, and the loupe snapshot is still taken after the overlay is up.
- Freeze applies to Capture Area (`⌃⇧4`) now and to All-in-One's Capture in Task 10.

- [ ] **Step 1: Write the failing tests**

`TidyShotTests/FreezeCropTests.swift`:
```swift
import CoreGraphics
import Testing
@testable import TidyShot

struct FreezeCropTests {
    let primary = CGRect(x: 0, y: 0, width: 1440, height: 900)
    let retinaImage = CGSize(width: 2880, height: 1800)

    @Test func aRetinaSelectionDoublesIntoPixels() {
        let rect = FreezeCrop.pixelRect(selection: CGRect(x: 100, y: 200, width: 300, height: 150),
                                        displayFrame: primary, scale: 2, imageSize: retinaImage)
        #expect(rect == CGRect(x: 200, y: 400, width: 600, height: 300))
    }

    /// The selection is in global points; the display's own origin is taken off first.
    @Test func aSelectionOnAnotherDisplayIsMadeLocalToIt() {
        let left = CGRect(x: -1920, y: 0, width: 1920, height: 1080)
        #expect(FreezeCrop.pixelRect(selection: CGRect(x: -500, y: 200, width: 100, height: 100),
                                     displayFrame: left, scale: 1, imageSize: CGSize(width: 1920, height: 1080))
                == CGRect(x: 1420, y: 200, width: 100, height: 100))
        let above = CGRect(x: 0, y: -900, width: 1440, height: 900)
        #expect(FreezeCrop.pixelRect(selection: CGRect(x: 10, y: -890, width: 50, height: 50),
                                     displayFrame: above, scale: 2, imageSize: retinaImage)
                == CGRect(x: 20, y: 20, width: 100, height: 100))
    }

    /// A frozen crop and a live capture of the same rect must have the same pixel size.
    @Test func aFractionalRectHasTheSizeOfALiveCapture() throws {
        let selection = CGRect(x: 10.3, y: 20.2, width: 100.3, height: 50.4)
        let rect = try #require(FreezeCrop.pixelRect(selection: selection, displayFrame: primary, scale: 2,
                                                     imageSize: retinaImage))
        let live = Geometry.pixelSize(points: selection.size, scale: 2)
        #expect(Int(rect.width) == live.width)
        #expect(Int(rect.height) == live.height)
        #expect(rect == CGRect(x: 21, y: 40, width: 201, height: 101))
    }

    /// Rounding the origin up and the size up can run one pixel past the right edge; the origin
    /// moves back so the size stays that of a live capture.
    @Test func roundingPastTheFarEdgeMovesTheOriginBack() {
        let rect = FreezeCrop.pixelRect(selection: CGRect(x: 0.25, y: 0, width: 1439.75, height: 900),
                                        displayFrame: primary, scale: 2, imageSize: retinaImage)
        #expect(rect == CGRect(x: 0, y: 0, width: 2880, height: 1800))
    }

    @Test func roundingPastTheNearEdgeClampsToZero() {
        let rect = FreezeCrop.pixelRect(selection: CGRect(x: -0.3, y: 0, width: 100, height: 100),
                                        displayFrame: primary, scale: 2, imageSize: retinaImage)
        #expect(rect == CGRect(x: 0, y: 0, width: 200, height: 200))
    }

    /// More than a rounding pixel outside the image is not a crop of it: nil, so the caller
    /// captures live.
    @Test func aRectOutsideTheImageIsNil() {
        for selection in [CGRect(x: 2000, y: 0, width: 100, height: 100),
                          CGRect(x: -50, y: 0, width: 100, height: 100),
                          CGRect(x: 1400, y: 0, width: 100, height: 100),
                          CGRect(x: 0, y: 880, width: 100, height: 100)] {
            #expect(FreezeCrop.pixelRect(selection: selection, displayFrame: primary, scale: 2,
                                         imageSize: retinaImage) == nil)
        }
    }

    @Test func anEmptyOrDegenerateRectIsNil() {
        #expect(FreezeCrop.pixelRect(selection: CGRect(x: 10, y: 10, width: 0, height: 50),
                                     displayFrame: primary, scale: 2, imageSize: retinaImage) == nil)
        // 0.2 pt at scale 2 rounds to no pixel.
        #expect(FreezeCrop.pixelRect(selection: CGRect(x: 10, y: 10, width: 0.2, height: 50),
                                     displayFrame: primary, scale: 2, imageSize: retinaImage) == nil)
        #expect(FreezeCrop.pixelRect(selection: CGRect(x: 10, y: 10, width: 50, height: 50),
                                     displayFrame: primary, scale: 0, imageSize: retinaImage) == nil)
        #expect(FreezeCrop.pixelRect(selection: CGRect(x: 10, y: 10, width: 50, height: 50),
                                     displayFrame: primary, scale: 2, imageSize: .zero) == nil)
    }

    /// A 40 by 20 px image on a display of 20 by 10 pt at (100, 50), scale 2: top left red, top
    /// right green, bottom left blue, bottom right white.
    func quadrants() -> CGImage {
        let context = CGContext(data: nil, width: 40, height: 20, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        // CoreGraphics y runs up, so the top half of the image is y 10 to 20.
        let paint: [(CGRect, [CGFloat])] = [
            (CGRect(x: 0, y: 10, width: 20, height: 10), [1, 0, 0]),
            (CGRect(x: 20, y: 10, width: 20, height: 10), [0, 1, 0]),
            (CGRect(x: 0, y: 0, width: 20, height: 10), [0, 0, 1]),
            (CGRect(x: 20, y: 0, width: 20, height: 10), [1, 1, 1]),
        ]
        for (rect, rgb) in paint {
            context.setFillColor(CGColor(srgbRed: rgb[0], green: rgb[1], blue: rgb[2], alpha: 1))
            context.fill(rect)
        }
        return context.makeImage()!
    }

    /// RGBA of the pixel at (x, y) counted from the top left.
    func rgba(_ image: CGImage, x: Int, y: Int) -> [Int] {
        let context = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let data = context.data!.assumingMemoryBound(to: UInt8.self)
        let base = y * context.bytesPerRow + x * 4
        return (0..<4).map { Int(data[base + $0]) }
    }

    @Test func theCropHoldsTheSelectionsPixels() throws {
        let frame = CGRect(x: 100, y: 50, width: 20, height: 10)
        let topRight = try #require(FreezeCrop.cropped(quadrants(), selection: CGRect(x: 110, y: 50, width: 10, height: 5),
                                                       displayFrame: frame, scale: 2))
        #expect(topRight.width == 20)
        #expect(topRight.height == 10)
        #expect(rgba(topRight, x: 5, y: 5) == [0, 255, 0, 255])
        let bottomLeft = try #require(FreezeCrop.cropped(quadrants(), selection: CGRect(x: 100, y: 55, width: 10, height: 5),
                                                         displayFrame: frame, scale: 2))
        #expect(rgba(bottomLeft, x: 5, y: 5) == [0, 0, 255, 255])
        // A selection spanning two quadrants holds both.
        let across = try #require(FreezeCrop.cropped(quadrants(), selection: CGRect(x: 105, y: 50, width: 10, height: 5),
                                                     displayFrame: frame, scale: 2))
        #expect(rgba(across, x: 2, y: 5) == [255, 0, 0, 255])
        #expect(rgba(across, x: 17, y: 5) == [0, 255, 0, 255])
    }

    @Test func croppingOutsideTheImageGivesNothing() {
        let frame = CGRect(x: 100, y: 50, width: 20, height: 10)
        #expect(FreezeCrop.cropped(quadrants(), selection: CGRect(x: 130, y: 50, width: 10, height: 5),
                                   displayFrame: frame, scale: 2) == nil)
    }
}
```

`TidyShotTests/AppSettingsTests.swift`, append inside the struct after Task 1's `windowShadowDefaultsOffAndPersists`:
```swift

    /// Freeze screen while selecting is off by default and persists (spec 2.9).
    @Test func freezeScreenDefaultsOffAndPersists() {
        let defaults = freshDefaults()
        let first = AppSettings(defaults: defaults)
        #expect(!first.freezeScreen)
        first.freezeScreen = true
        #expect(defaults.object(forKey: "freezeScreen") as? Bool == true)
        #expect(AppSettings(defaults: defaults).freezeScreen)
    }
```

- [ ] **Step 2: Run the new tests and see them fail**

Run the header's full-suite command. Expected: the build fails with `error:` lines `cannot find 'FreezeCrop' in scope` (several) and `value of type 'AppSettings' has no member 'freezeScreen'`. No `Test run` line appears.

- [ ] **Step 3: Implement the pure part**

`TidyShot/Capture/FreezeCrop.swift`:
```swift
import CoreGraphics

/// One display's screenshot taken before the selection overlay appeared (Freeze screen). Pixels
/// run top to bottom as in any `CGImage`; `scale` is the display's pixels per point.
nonisolated struct FrozenSnapshot: Sendable {
    let displayID: CGDirectDisplayID
    let image: CGImage
    let scale: CGFloat
}

/// Cuts a selection out of a frozen display snapshot. Pure.
enum FreezeCrop {
    /// Pixels of slack for rounding: origin and size are rounded separately, so a rect that
    /// touches the far edge can come out one pixel too wide, or one too far left.
    static let roundingSlack: CGFloat = 1

    /// The selection (CoreGraphics global points) as a pixel rect in a snapshot of the display
    /// whose frame is `displayFrame`, top-left origin as `CGImage.cropping(to:)` takes it. The
    /// size is rounded as `Geometry.pixelSize` rounds it, so it equals the size of a live
    /// capture of the same rect. A rect that sticks out by at most `roundingSlack` pixels is
    /// moved inside, keeping its size. Nil when the size rounds to nothing, the scale or the
    /// image is empty, or the rect lies further outside the image.
    static func pixelRect(selection: CGRect, displayFrame: CGRect, scale: CGFloat, imageSize: CGSize) -> CGRect? {
        guard scale > 0, imageSize.width > 0, imageSize.height > 0 else { return nil }
        let local = Geometry.displayLocal(selection, in: displayFrame)
        let size = Geometry.pixelSize(points: local.size, scale: scale)
        let width = CGFloat(size.width)
        let height = CGFloat(size.height)
        guard width >= 1, height >= 1, width <= imageSize.width, height <= imageSize.height else { return nil }
        var x = (local.minX * scale).rounded()
        var y = (local.minY * scale).rounded()
        guard x >= -roundingSlack, y >= -roundingSlack else { return nil }
        x = max(x, 0)
        y = max(y, 0)
        let pastRight = x + width - imageSize.width
        let pastBottom = y + height - imageSize.height
        guard pastRight <= roundingSlack, pastBottom <= roundingSlack else { return nil }
        // Both are at most `x` and `y`, because the size fits the image, so the origin stays >= 0.
        x -= max(pastRight, 0)
        y -= max(pastBottom, 0)
        return CGRect(x: x, y: y, width: width, height: height)
    }

    /// `image` cut to the selection, or nil when `pixelRect` is nil. The result shares the
    /// snapshot's pixels, so it keeps the whole display image alive for as long as it lives:
    /// up to about 60 MB for a 5K display while its Quick Access card shows. That is accepted.
    static func cropped(_ image: CGImage, selection: CGRect, displayFrame: CGRect, scale: CGFloat) -> CGImage? {
        guard let rect = pixelRect(selection: selection, displayFrame: displayFrame, scale: scale,
                                   imageSize: CGSize(width: image.width, height: image.height)) else { return nil }
        return image.cropping(to: rect)
    }
}
```

- [ ] **Step 4: Settings key and toggle**

`AppSettings.swift`, next to Task 1's `windowShadow` lines: `Keys` gets `static let freezeScreen = "freezeScreen"`; after the `windowShadow` property:
```swift
    /// The Capture tab's Freeze screen while selecting (spec 2.9). Area selections then show a still image.
    var freezeScreen: Bool { didSet { defaults.set(freezeScreen, forKey: Keys.freezeScreen) } }
```
`register(defaults:)` gets `Keys.freezeScreen: false,`; `init` gets `freezeScreen = defaults.bool(forKey: Keys.freezeScreen)`.

`CaptureSettingsView.swift`, first in the `Form`, above `Toggle("Show cursor in screenshots", ...)`:
```swift
            Toggle("Freeze screen while selecting", isOn: $settings.freezeScreen)
            Text("Area selections show a still image of the screen and the capture is cut from it, so menus, tooltips and video stay as they were when you pressed the shortcut.")
                .font(.caption)
                .foregroundStyle(.secondary)
```

- [ ] **Step 5: SelectionController: snapshots before the overlay**

`TidyShot/Selection/SelectionController.swift`.

Properties, after `cachedOverlayWindows` (line 16):
```swift
    /// Freeze screen: one snapshot per display, taken before any overlay window existed. Cleared by `dismiss()`.
    private var frozenSnapshots: [CGDirectDisplayID: FrozenSnapshot] = [:]
```

`select` (line 22) takes `freeze: CaptureOptions? = nil`. After `picker = ...` (line 27) and before the `for screen in NSScreen.screens` loop (line 29) add:
```swift
        // Freeze (area mode only): every display is captured before any overlay window appears,
        // so the snapshot holds neither the dimming nor the crosshair. Window and scrolling mode
        // ignore it (spec 2.9). A display that fails is simply absent and stays live.
        frozenSnapshots = [:]
        if mode == .area, let freeze {
            frozenSnapshots = await captureFrozenSnapshots(options: freeze)
        }
```
Inside the loop, right after `view.mode = mode` (line 32):
```swift
            if let frozen = frozenSnapshots[window.displayID] {
                view.snapshotScale = frozen.scale
                view.snapshot = frozen.image
                view.isFrozen = true
            }
```
(set before `window.contentView = view` so the first draw is already frozen). Lines 49-60 stay: activation, hover, `snapshotTask`, the continuation.

New method, after `select`:
```swift
    /// One `engine.capture(.display(_:))` per display, in parallel, with whatever `overlayWindows()`
    /// excludes (nothing yet; Task 3 adds the Quick Access cards). Failures are dropped.
    private func captureFrozenSnapshots(options: CaptureOptions) async -> [CGDirectDisplayID: FrozenSnapshot] {
        let excluded = await overlayWindows()
        let engine = engine
        var found: [CGDirectDisplayID: FrozenSnapshot] = [:]
        await withTaskGroup(of: FrozenSnapshot?.self) { group in
            for display in displays {
                group.addTask { @MainActor in
                    guard let result = try? await engine.capture(.display(display), options: options,
                                                                 excludingWindows: excluded) else { return nil }
                    return FrozenSnapshot(displayID: display.displayID, image: result.image, scale: result.scale)
                }
            }
            for await snapshot in group {
                if let snapshot { found[snapshot.displayID] = snapshot }
            }
        }
        return found
    }

    /// The snapshot taken for `displayID` before the overlay appeared, valid until `dismiss()`.
    /// Nil when freeze was off, the mode does not freeze, or that display's snapshot failed.
    func frozenCapture(for displayID: CGDirectDisplayID) -> FrozenSnapshot? {
        frozenSnapshots[displayID]
    }
```
The child tasks run on the main actor (`@MainActor in`), so they may use `engine` and the non-Sendable `SCDisplay` and `[SCWindow]`; the awaits inside `engine.capture` still overlap, so two displays take about as long as one. Only `FrozenSnapshot` (Sendable) crosses the group's boundary. This compiles under the project's settings (Swift 6, default `MainActor` isolation, approachable concurrency); if a later toolchain rejects a capture, make `excluded` and `display` captures explicit (`[display, excluded]`) before falling back to a sequential `for` loop.

`overlayWindows()` (lines 66-72): after the cache line add `guard !wanted.isEmpty else { return [] }`, so a call with no overlay window (the freeze snapshots, before the windows exist) does no lookup:
```swift
        let wanted = Set(windows.compactMap { $0.windowNumber > 0 ? CGWindowID($0.windowNumber) : nil })
        if let cachedOverlayWindows, cachedOverlayWindows.count >= wanted.count { return cachedOverlayWindows }
        guard !wanted.isEmpty else { return [] }
```
(The first line is the existing line 67 and the second the existing line 68; only the third is new.)

`takeSnapshots()` (lines 75-89): a display with a frozen snapshot already has one. Replace the head and the loop header:
```swift
    private func takeSnapshots() async {
        let pending = displays.filter { frozenSnapshots[$0.displayID] == nil }
        guard !pending.isEmpty else { return }
        let overlays = await overlayWindows()
        // A snapshot taken without every overlay excluded would show the dimming in the loupe; skip instead.
        guard overlays.count >= windows.count else { return }
        for display in pending {
```
and the body of the loop is unchanged.

`dismiss()` (lines 92-105): add `frozenSnapshots = [:]` after `cachedOverlayWindows = nil`.

`finish(_:)` is unchanged: on cancel it dismisses, on success the overlay and the snapshots stay until the coordinator's `dismiss()`.

- [ ] **Step 6: SelectionView: draw the snapshot opaque**

`TidyShot/Selection/SelectionView.swift`.

After `snapshotScale` (line 25) add:
```swift
    /// Freeze screen: draw `snapshot` opaque under the dimming, so the screen looks stopped. Set
    /// with `snapshot`, only on a view whose display has a frozen snapshot.
    var isFrozen = false {
        didSet { if isFrozen != oldValue { needsDisplay = true } }
    }
    private var showsFrozenBackdrop: Bool { isFrozen && snapshot != nil }
    /// Frozen, the view paints every pixel, which lets AppKit skip compositing it over the window.
    override var isOpaque: Bool { showsFrozenBackdrop }
```
`draw` (line 129): make its first statement `drawFrozenBackdrop(in: dirtyRect)`, before `dimColor.setFill()`. Everything after it stays: the dimming, the hole, the crosshair, the loupe.

`punchHole(_:)` (lines 163-166): frozen, the hole shows the snapshot undimmed instead of clearing to the desktop.
```swift
    private func punchHole(_ rect: CGRect) {
        guard showsFrozenBackdrop, let snapshot, let context = NSGraphicsContext.current?.cgContext else {
            NSColor.clear.setFill()
            rect.fill(using: .copy)
            return
        }
        context.saveGState()
        context.clip(to: rect)
        context.interpolationQuality = .none
        context.draw(snapshot, in: bounds)
        context.restoreGState()
    }

    /// The snapshot at one pixel per pixel, clipped to what needs drawing. Row 0 of a `CGImage`
    /// is the top, which is the top of this non-flipped view when the image fills `bounds`.
    private func drawFrozenBackdrop(in dirtyRect: NSRect) {
        guard showsFrozenBackdrop, let snapshot, let context = NSGraphicsContext.current?.cgContext else { return }
        context.saveGState()
        context.clip(to: dirtyRect)
        context.interpolationQuality = .none
        context.draw(snapshot, in: bounds)
        context.restoreGState()
    }
```
The snapshot is `bounds.size * snapshotScale` pixels, so drawing it into `bounds` is 1:1 on the display. The loupe and the crosshair colour already read `snapshot`, so both work from the first frame. If Tim's hand check (Step 9, and Task 8's checklist) finds that dragging stutters on the largest display, the fallback is to put the backdrop in a layer under the view: make the window's `contentView` a plain container, add a backdrop view whose `layer.contents` is the snapshot, and put the `SelectionView` over it unchanged (its existing clear hole then shows the backdrop). It is not built in 6a; it is a follow-up only if that check fails.

- [ ] **Step 7: AppCoordinator: crop instead of capture**

`runSelection(mode:)` (lines 171-190) after Task 1 reads, with the new parts marked:
```swift
    /// Show the overlay, capture with the overlay excluded (or cut the frozen snapshot), dismiss, then save.
    private func runSelection(mode: SelectionMode) async {
        await withCaptureLock {
            guard let content = await loadContent() else { return }
            // Freeze applies to area mode only. The snapshots follow the cursor setting: they are
            // taken before the overlay, so the pointer in them is the real one.
            let freeze = mode == .area && settings.freezeScreen
                ? CaptureOptions(settings: settings, duringSelection: false) : nil
            guard let selection = await selector.select(mode: mode, content: content, freeze: freeze) else { return }

            let result: CaptureResult?
            switch selection {
            case .area(let rect, let display):
                if let frozen = frozenResult(for: rect, display: display) {
                    result = frozen
                } else {
                    let overlays = await selector.overlayWindows()
                    result = await capture(.area(rect: rect, display: display), excludingWindows: overlays, duringSelection: true)
                }
            case .window(let window):
                result = await capture(.window(window), duringSelection: true)
            }
            selector.dismiss()

            if let result {
                await save(result)
            }
        }
    }

    /// The selection cut from the display's frozen snapshot, or nil when there is none (freeze off,
    /// or that display's snapshot failed) or the crop failed; the caller then captures live.
    private func frozenResult(for rect: CGRect, display: SCDisplay) -> CaptureResult? {
        guard let frozen = selector.frozenCapture(for: display.displayID) else { return nil }
        guard let image = FreezeCrop.cropped(frozen.image, selection: rect, displayFrame: display.frame,
                                             scale: frozen.scale) else {
            NSLog("Freeze crop failed for \(rect) on display \(display.displayID); capturing live")
            return nil
        }
        return CaptureResult(image: image, scale: frozen.scale, target: .area(rect: rect, display: display))
    }
```
`captureScrolling` (lines 140-168) passes no `freeze`, so scrolling stays live. `captureWindow` goes through `runSelection(mode: .window)` and `freeze` is nil there.

- [ ] **Step 8: Run the full suite**

Run the header's full-suite command. Expected: no `error:` lines, and `Test run with 620 tests in 79 suites passed`. This task adds 10 tests and 1 suite: `FreezeCropTests` (9: `aRetinaSelectionDoublesIntoPixels`, `aSelectionOnAnotherDisplayIsMadeLocalToIt`, `aFractionalRectHasTheSizeOfALiveCapture`, `roundingPastTheFarEdgeMovesTheOriginBack`, `roundingPastTheNearEdgeClampsToZero`, `aRectOutsideTheImageIsNil`, `anEmptyOrDegenerateRectIsNil`, `theCropHoldsTheSelectionsPixels`, `croppingOutsideTheImageGivesNothing`) and `AppSettingsTests.freezeScreenDefaultsOffAndPersists`. Nothing is removed or renamed; `SelectionOutcomeTests` and `WindowPickerTests` stay green.

- [ ] **Step 9: Hand checks (Tim)**

For Tim; the implementer lists these in its report and goes on to Step 10. Task 8's checklist repeats them. Release build (`-configuration Release -derivedDataPath .build-rel`), re-grant Screen Recording after an ad-hoc rebuild.
- Settings > Capture lists `Freeze screen while selecting` with its caption above `Show cursor in screenshots`. Off by default.
- Freeze off: ⌃⇧4 behaves as before (overlay at once, the loupe image arrives a moment later).
- Freeze on, ⌃⇧4 over a playing video (or a clock with seconds): the screen stops when the overlay appears; drag a region; the saved image shows the frame from the moment of the shortcut, not from mouse-up. The loupe works from the first mouse move. The crosshair stays readable on light and dark content.
- Menus and tooltips: open an app's menu or a hover tooltip that stays while you press ⌃⇧4 (a Safari tab hover card, a Dock label, a context menu that survives the shortcut): it is in the frozen image and in the capture.
- Pixel size: with the size label reading, say, 500 x 300, capture that size with Freeze off and on; both files are 1000 x 600 px on a Retina display. Drag to the very right and bottom edges of the display: the file is the label's size, no off-by-one, no failure notification.
- Cursor: Show cursor on, Freeze on, press ⌃⇧4 with the pointer inside the region you then select: the arrow is in the image. Freeze off, Show cursor on: no pointer and no crosshair in an area image.
- Two displays: both freeze at once; select on the second display; the image is that display's pixels at its scale. A drag that crosses displays still clips to the display under its centre.
- Window mode (⌃⇧2) and scrolling (⌃⇧5) with Freeze on: live, no frozen backdrop, as before. Escape in a frozen overlay cancels and the screen is live again; nothing is saved.
- Latency (probe 3 in `docs/superpowers/research/phase-6-research.md`): with Freeze off and on, one and two displays, the time from the shortcut to the overlay, measured as Task 8's checklist describes (no timing code is added); Tim records the medians in the research notes. Dragging on the largest display must track the mouse without lag; if it does not, the layer backdrop of Step 6 is the follow-up.
- Upload-only mode, the Quick Access overlay, Annotate and Recent Captures treat a frozen capture like any area capture.

- [ ] **Step 10: Commit**

```bash
git add TidyShot/Capture/FreezeCrop.swift TidyShot/Selection/SelectionController.swift TidyShot/Selection/SelectionView.swift TidyShot/App/AppCoordinator.swift TidyShot/Settings/AppSettings.swift TidyShot/Settings/CaptureSettingsView.swift TidyShotTests/FreezeCropTests.swift TidyShotTests/AppSettingsTests.swift
git commit -m "feat: freeze screen while selecting, with the capture cut from the still image"
```

### Task 3: Overlay stack and display choice

**Files:**
- Create: `TidyShot/Overlay/QuickAccessStackLayout.swift` (`QuickAccessStackLayout`, pure)
- Create: `TidyShot/Overlay/OverlayScreenChoice.swift` (`OverlayDisplayChoice`, `OverlayScreenChoice`, pure)
- Modify: `TidyShot/Overlay/QuickAccessController.swift` (whole file, lines 1-95: one panel becomes a list of cards)
- Modify: `TidyShot/Overlay/QuickAccessPanel.swift` (line 18, `isMovableByWindowBackground`)
- Modify: `TidyShot/Settings/AppSettings.swift` (next to the `overlayAutoCloseSeconds` lines: keys after line 42, properties after line 64, registration after line 109, reads after line 126 on `main`; Tasks 1 and 2 added lines below 50, so find them by name)
- Modify: `TidyShot/Settings/OverlaySettingsView.swift` (after line 20)
- Modify: `TidyShot/App/AppCoordinator.swift` (line 29 `overlay`, line 30 `selector`, lines 52-56 doc, lines 121-128 `captureFullscreen`, line 254 and lines 267-268 `persist`, line 305, lines 394-411 `showOverlay`, a helper before `withCaptureLock` at line 1514)
- Modify: `TidyShot/Selection/SelectionController.swift` (line 7 and lines 18-20 init, lines 62-72 `overlayWindows()`, line 78 in `takeSnapshots()`)
- Modify: `TidyShot/Capture/CaptureTarget.swift` (an extension after the enum, line 9)
- Modify: `TidyShot/Capture/CaptureEngine.swift` (lines 59-64 `screen(forDisplayID:)`, an `NSScreen` extension after the class)
- Create: `TidyShotTests/QuickAccessStackLayoutTests.swift` (struct `QuickAccessStackLayoutTests`)
- Create: `TidyShotTests/OverlayScreenChoiceTests.swift` (struct `OverlayScreenChoiceTests`)
- Test: `TidyShotTests/AppSettingsTests.swift` (two tests added)

Line numbers are `main`'s at a1dde71. Tasks 1 and 2 edit `AppCoordinator.runSelection`, `capture(_:excludingWindows:)`, `CaptureEngine.capture` and `SelectionController.select`, so the lines named above may have moved by a few; find them by the code quoted.

**Interfaces:**
- Consumes:
  - `main`: `OverlayGeometry.frame(size:corner:in:margin:)` and `OverlayCorner` (`OverlayGeometry.swift:3`, `:20`); `QuickAccessView.size` (`QuickAccessView.swift:5`); `QuickAccessModel(record:thumbnail:)`, `isHovered`, `isSettled`, the `on…` callbacks (`QuickAccessModel.swift`); `QuickAccessPanel(model:)`; `OverlayWindowLookup.windows(numbers:engine:) async -> [SCWindow]` (`OverlayWindowLookup.swift:10`); `CaptureEngine.screen(forDisplayID:)` and `CaptureEngine.displayID(containing:)` (`CaptureEngine.swift:59`, `:67`); `CaptureResult.target` (`CaptureTarget.swift:19`); `AppSettings.overlayCorner`, `overlayAutoCloseSeconds`, `showOverlay`.
  - Task 1: `AppCoordinator.capture(_ target: CaptureTarget, excludingWindows: [SCWindow] = [], duringSelection: Bool = false) async -> CaptureResult?`.
  - Task 2: `SelectionController.select(mode:content:freeze:)`; `captureFrozenSnapshots(options:)`, which takes its exclusion list from `overlayWindows()` before any selection window exists; `overlayWindows()` with `guard !wanted.isEmpty else { return [] }` after the cache line; `takeSnapshots()` limited to displays without a frozen snapshot.
- Produces (Tasks 4 to 7 rely on these names):
  - `nonisolated enum QuickAccessStackLayout { static let margin: CGFloat = 16; static let spacing: CGFloat = 10; static func frames(count: Int, cardSize: CGSize, corner: OverlayCorner, visibleFrame: CGRect, margin: CGFloat = QuickAccessStackLayout.margin, spacing: CGFloat = QuickAccessStackLayout.spacing) -> [CGRect]; static func capacity(cardHeight: CGFloat, visibleHeight: CGFloat, margin: CGFloat = QuickAccessStackLayout.margin, spacing: CGFloat = QuickAccessStackLayout.spacing, limit: Int) -> Int }`. Index 0 is the newest card, at the corner.
  - `nonisolated enum OverlayDisplayChoice: String, CaseIterable, Identifiable, Sendable { case capture, pointer, main; var id: String; var title: String }` and `nonisolated enum OverlayScreenChoice { static func index(choice: OverlayDisplayChoice, captureDisplayID: CGDirectDisplayID?, pointerIndex: Int?, screenDisplayIDs: [CGDirectDisplayID]) -> Int }`.
  - `AppSettings.overlayDisplay: OverlayDisplayChoice` (key `overlayDisplay`, default `.capture`), `AppSettings.overlayMaxCards: Int` (key `overlayMaxCards`, default 5, read clamped to `AppSettings.overlayMaxCardsRange`), `static let overlayMaxCardsRange: ClosedRange<Int> = 1...8`.
  - `QuickAccessController`:
    - `init(settings: AppSettings)`; reads `settings.overlayCorner` and `settings.overlayMaxCards` at every layout.
    - `func show(record: CaptureRecord, thumbnail: NSImage?, screen: NSScreen, autoCloseSeconds: Double, actions: Actions)`: the new card at the corner of `screen`, the stack moved there with it.
    - `func update(record: CaptureRecord)`, `func close(recordID: UUID)`, `var onDidClose: ((UUID) -> Void)?` (Task 4 adds the reason to the last two).
    - `var windowNumbers: Set<CGWindowID>` (cards on screen), `var shownIDs: [UUID]` (newest first), `func isShowing(recordID: UUID) -> Bool`, `var screen: NSScreen?` (the stack's screen while a card shows, else nil).
    - `Actions` unchanged (`copy`, `retry`, `reveal`, `delete`, `annotate`); Task 5 adds `saveAs` and `copyImage`, Task 6 `prepareDrag` and `dragEnded`.
    - Private, for Tasks 4 to 6 to extend in this file: the card list `private var cards: [Card]` (newest first; `Card` has `model`, `panel`, `autoCloseSeconds`, `closeTask` and `id`), `makeCard(record:thumbnail:autoCloseSeconds:actions:)` (the per-card wiring from `Actions`), `closeCard(_ card: Card)` (takes one card off screen and reports it), `closeGap()` (the slide after a close), `trim(to:)` (closes the oldest past the capacity) and `scheduleClose(_:)` (the per-card countdown, which skips a round while `model.isHovered`).
  - `AppCoordinator`: `private func overlayActions() -> QuickAccessController.Actions` (every card's actions, shared by `showOverlay` and Task 4's restore), `private func overlayScreen(captureDisplayID: CGDirectDisplayID?) -> NSScreen?`, `private func cardWindows() async -> [SCWindow]` (Task 7 calls it for Capture Previous Area).
  - `SelectionController.init(engine: CaptureEngine, cardWindowNumbers: @escaping () -> Set<CGWindowID> = { [] })`; `overlayWindows()` now returns the selection windows and the cards.
  - `extension CaptureTarget { var displayID: CGDirectDisplayID }`, `extension NSScreen { var displayID: CGDirectDisplayID? }`.

Behaviour (spec 2.9, Stacking, Which display, Exclude the overlay from captures):
- The controller holds cards newest first, one `QuickAccessPanel` and `QuickAccessModel` each, all on one screen. A new card appears at the corner; the older ones slide away from it by 114 pt (104 + 10), down from a top corner and up from a bottom corner. At most `QuickAccessStackLayout.capacity(…, limit: settings.overlayMaxCards)` cards show; the oldest beyond that closes (Task 4 calls this `.pushedOut`). With one card and Show up to 1 the card sits where Phase 5 put it.
- Each card runs its own auto-close countdown once its upload settles, restarted while the pointer is over that card, exactly as the one panel did (`QuickAccessController.swift:80-94`). An update that unsettles a card (Retry) stops its countdown.
- After a close (Close button, auto-close, delete, editor opened) the cards below slide into the gap, unless the pointer is inside the stack's last laid-out region (inflated by the 10 pt spacing): then the slide waits until the pointer has left, checked every 250 ms, so no card moves out from under the pointer or into it. A new card and a screen change lay the stack out at once.
- Display: `overlayScreen(captureDisplayID:)` maps `settings.overlayDisplay` through `OverlayScreenChoice.index`. The capture's display is `CaptureResult.target.displayID`: the area's or fullscreen display, or the display under a window's centre; a scrolling capture saves `.area(rect:display:)`, so it uses its area's display. A capture shown on another display moves the existing cards there, unanimated. `NSApplication.didChangeScreenParametersNotification` re-lays the stack out on its display, or on screen 0 when that display is gone, trimming to the new capacity.
- Cards no longer move when dragged (`isMovableByWindowBackground = false`); drag-out arrives in Task 6.
- Exact strings (Overlay tab): picker `Show on` with `Display of the capture`, `Display with the pointer`, `Main display`; stepper `Show up to N overlays`, reading `Show up to 1 overlay` at 1 (header, point 4; Task 8 writes it into 2.9).
- Exclusion: the area capture excludes the selection windows and the cards (one `OverlayWindowLookup` call in `SelectionController.overlayWindows()`); `captureFullscreen()` excludes the cards, with a lookup only when one shows; the loupe snapshots and Task 2's frozen snapshots exclude them, both through `overlayWindows()`; window captures (`desktopIndependentWindow`) never contained them; the scrolling stream already excludes all of TidyShot by application (`ScrollFrameSource.swift:121-136`).
- Animation: the spec names `setFrame(_:display:animate: true)`, which runs its animation synchronously, one window after another. The cards move together through `NSAnimationContext.runAnimationGroup` (0.2 s) and `panel.animator().setFrame(_:display:)`, which does not block the main actor (header, point 5; Task 8 writes it into 2.9).

Every `AppCoordinator` call into the overlay, before and after:

| Call (main) | Today | After this task |
|---|---|---|
| `init`, `overlay.onDidClose` (line 84) | `forgetLatestCapture(id)` when the panel closes | unchanged; fires for each card that closes, pushed-out ones included |
| `showOverlay` → `overlay.show(…corner:…)` (line 401) | closes the previous panel, shows one under the pointer | adds a card at the corner of the chosen screen; older cards stay, slide, or close past the capacity; `latestCapture` set after `show`, as today |
| `refreshOverlay` → `overlay.update(record:)` (line 887; from progress, uploaded, failed, cancelled, retry, editor upload) | updates the panel if it shows the record | updates whichever card shows the record |
| `removeRecord` → `overlay.close(recordID:)` (line 798; delete and remove-from-history) | closes the panel if it shows the record | closes that card; the rest close the gap |
| `presentEditor` → `overlay.close(recordID:)` (line 1088; Annotate) | same | same, per card |
| Card buttons: Copy URL, Retry, Reveal, Delete, Annotate (`Actions`, lines 403-408) | one panel's callbacks | each card's callbacks, built by `overlayActions()` |
| Hover (`model.isHovered`, `QuickAccessView.swift:48`) | pauses the panel's countdown | pauses that card's countdown; also holds back the gap slide |
| Auto-close (`scheduleClose`) | one task | one task per card |

- [ ] **Step 1: Write the failing tests**

`TidyShotTests/QuickAccessStackLayoutTests.swift` (new):
```swift
import CoreGraphics
import Testing
@testable import TidyShot

/// The stack's geometry: the newest card at the corner, the others 10 pt apart away from it,
/// and how many fit (spec 2.9, Stacking). AppKit screen coordinates, origin bottom-left.
struct QuickAccessStackLayoutTests {
    let screen = CGRect(x: 0, y: 25, width: 1440, height: 875)
    let card = CGSize(width: 340, height: 104)

    /// One card is placed exactly as Phase 5 placed the one panel.
    @Test func oneCardSitsWhereOverlayGeometryPutsIt() {
        for corner in OverlayCorner.allCases {
            let frames = QuickAccessStackLayout.frames(count: 1, cardSize: card, corner: corner, visibleFrame: screen)
            #expect(frames == [OverlayGeometry.frame(size: card, corner: corner, in: screen)])
        }
    }

    @Test func topCornersStackDownwardTenPointsApart() {
        let right = QuickAccessStackLayout.frames(count: 3, cardSize: card, corner: .topRight, visibleFrame: screen)
        #expect(right == [
            CGRect(x: 1084, y: 780, width: 340, height: 104),
            CGRect(x: 1084, y: 666, width: 340, height: 104),
            CGRect(x: 1084, y: 552, width: 340, height: 104),
        ])
        let left = QuickAccessStackLayout.frames(count: 2, cardSize: card, corner: .topLeft, visibleFrame: screen)
        #expect(left.map(\.minX) == [16, 16])
        #expect(left.map(\.minY) == [780, 666])
    }

    @Test func bottomCornersStackUpward() {
        let right = QuickAccessStackLayout.frames(count: 3, cardSize: card, corner: .bottomRight, visibleFrame: screen)
        #expect(right.map(\.minY) == [41, 155, 269])
        #expect(right.allSatisfy { $0.minX == 1084 && $0.size == card })
        let left = QuickAccessStackLayout.frames(count: 2, cardSize: card, corner: .bottomLeft, visibleFrame: screen)
        #expect(left == [CGRect(x: 16, y: 41, width: 340, height: 104), CGRect(x: 16, y: 155, width: 340, height: 104)])
    }

    /// A display left of and below the main one has negative coordinates.
    @Test func secondDisplayWithANegativeOriginIsHonoured() {
        let second = CGRect(x: -1920, y: -200, width: 1920, height: 1055)
        let frames = QuickAccessStackLayout.frames(count: 2, cardSize: card, corner: .topLeft, visibleFrame: second,
                                                   margin: 20, spacing: 10)
        #expect(frames == [CGRect(x: -1900, y: 731, width: 340, height: 104),
                           CGRect(x: -1900, y: 617, width: 340, height: 104)])
    }

    @Test func noCardsNoFrames() {
        #expect(QuickAccessStackLayout.frames(count: 0, cardSize: card, corner: .topRight, visibleFrame: screen).isEmpty)
    }

    @Test func capacityIsTheLimitOnATallScreen() {
        #expect(QuickAccessStackLayout.capacity(cardHeight: 104, visibleHeight: 875, limit: 5) == 5)
        // 875 pt fits seven: 16 + 7 x 104 + 6 x 10 + 16 = 820; eight need 934.
        #expect(QuickAccessStackLayout.capacity(cardHeight: 104, visibleHeight: 875, limit: 8) == 7)
    }

    @Test func capacityOnAShortScreen() {
        // 300 pt fits two (250 pt); three need 364.
        #expect(QuickAccessStackLayout.capacity(cardHeight: 104, visibleHeight: 300, limit: 5) == 2)
        #expect(QuickAccessStackLayout.capacity(cardHeight: 104, visibleHeight: 364, limit: 5) == 3)
    }

    /// The newest card always shows, as the one panel did on any screen.
    @Test func capacityIsAtLeastOne() {
        #expect(QuickAccessStackLayout.capacity(cardHeight: 104, visibleHeight: 80, limit: 5) == 1)
        #expect(QuickAccessStackLayout.capacity(cardHeight: 104, visibleHeight: 875, limit: 0) == 1)
    }
}
```

`TidyShotTests/OverlayScreenChoiceTests.swift` (new):
```swift
import CoreGraphics
import Testing
@testable import TidyShot

/// Which screen the stack goes to (spec 2.9, Which display). Indices are into `NSScreen.screens`.
struct OverlayScreenChoiceTests {
    let ids: [CGDirectDisplayID] = [1, 7, 42]

    @Test func captureChoiceUsesTheCaptureDisplay() {
        #expect(OverlayScreenChoice.index(choice: .capture, captureDisplayID: 42, pointerIndex: 1, screenDisplayIDs: ids) == 2)
        #expect(OverlayScreenChoice.index(choice: .capture, captureDisplayID: 1, pointerIndex: 2, screenDisplayIDs: ids) == 0)
    }

    /// A display unplugged since the capture, or no capture display (a restored card): the
    /// pointer's screen, then screen 0.
    @Test func aMissingCaptureDisplayFallsBackToThePointerThenScreenZero() {
        #expect(OverlayScreenChoice.index(choice: .capture, captureDisplayID: 99, pointerIndex: 1, screenDisplayIDs: ids) == 1)
        #expect(OverlayScreenChoice.index(choice: .capture, captureDisplayID: nil, pointerIndex: 2, screenDisplayIDs: ids) == 2)
        #expect(OverlayScreenChoice.index(choice: .capture, captureDisplayID: 99, pointerIndex: nil, screenDisplayIDs: ids) == 0)
    }

    @Test func pointerChoiceIgnoresTheCaptureDisplay() {
        #expect(OverlayScreenChoice.index(choice: .pointer, captureDisplayID: 42, pointerIndex: 1, screenDisplayIDs: ids) == 1)
        #expect(OverlayScreenChoice.index(choice: .pointer, captureDisplayID: 42, pointerIndex: nil, screenDisplayIDs: ids) == 0)
        #expect(OverlayScreenChoice.index(choice: .pointer, captureDisplayID: 42, pointerIndex: 5, screenDisplayIDs: ids) == 0)
    }

    @Test func mainChoiceIsScreenZero() {
        #expect(OverlayScreenChoice.index(choice: .main, captureDisplayID: 42, pointerIndex: 1, screenDisplayIDs: ids) == 0)
        #expect(OverlayScreenChoice.index(choice: .capture, captureDisplayID: 42, pointerIndex: nil, screenDisplayIDs: []) == 0)
    }

    @Test func titlesAndStoredValues() {
        #expect(OverlayDisplayChoice.allCases.map(\.title) == ["Display of the capture", "Display with the pointer", "Main display"])
        #expect(OverlayDisplayChoice.allCases.map(\.rawValue) == ["capture", "pointer", "main"])
    }
}
```

`TidyShotTests/AppSettingsTests.swift`, two tests appended inside `AppSettingsTests`:
```swift
    /// Phase 6a: the stack shows up to five cards on the display of the capture (spec 2.9).
    @Test func overlayStackSettingsDefaultAndPersist() {
        let defaults = freshDefaults()
        let first = AppSettings(defaults: defaults)
        #expect(first.overlayDisplay == .capture)
        #expect(first.overlayMaxCards == 5)
        first.overlayDisplay = .main
        first.overlayMaxCards = 3
        #expect(defaults.string(forKey: "overlayDisplay") == "main")
        #expect(defaults.integer(forKey: "overlayMaxCards") == 3)
        let second = AppSettings(defaults: defaults)
        #expect(second.overlayDisplay == .main)
        #expect(second.overlayMaxCards == 3)
    }

    /// A stored value outside the Stepper's 1 to 8, or an unknown display choice, reads as the
    /// nearest valid one.
    @Test func overlayStackSettingsOutOfRangeReadAsValid() {
        let defaults = freshDefaults()
        defaults.set("elsewhere", forKey: "overlayDisplay")
        defaults.set(0, forKey: "overlayMaxCards")
        let low = AppSettings(defaults: defaults)
        #expect(low.overlayDisplay == .capture)
        #expect(low.overlayMaxCards == 1)
        defaults.set(20, forKey: "overlayMaxCards")
        #expect(AppSettings(defaults: defaults).overlayMaxCards == 8)
    }
```

- [ ] **Step 2: Run the tests and see them fail**

Run the header's full-suite command. Expected: the build fails with `cannot find 'QuickAccessStackLayout' in scope`, `cannot find 'OverlayScreenChoice' in scope`, `cannot find 'OverlayDisplayChoice' in scope` and `value of type 'AppSettings' has no member 'overlayDisplay'`.

- [ ] **Step 3: The pure helpers**

`TidyShot/Overlay/QuickAccessStackLayout.swift`:
```swift
import CoreGraphics

/// Where each Quick Access card goes. `visibleFrame` is an AppKit screen rect (origin
/// bottom-left). Index 0 is the newest card, at the corner (`OverlayGeometry.frame`); each older
/// card sits one card height plus `spacing` further from the corner: below it from a top
/// corner, above it from a bottom corner.
nonisolated enum QuickAccessStackLayout {
    static let margin: CGFloat = 16
    static let spacing: CGFloat = 10

    static func frames(count: Int, cardSize: CGSize, corner: OverlayCorner, visibleFrame: CGRect,
                       margin: CGFloat = QuickAccessStackLayout.margin,
                       spacing: CGFloat = QuickAccessStackLayout.spacing) -> [CGRect] {
        guard count > 0 else { return [] }
        let first = OverlayGeometry.frame(size: cardSize, corner: corner, in: visibleFrame, margin: margin)
        let step = cardSize.height + spacing
        let direction: CGFloat = switch corner {
        case .topLeft, .topRight: -1
        case .bottomLeft, .bottomRight: 1
        }
        return (0..<count).map { first.offsetBy(dx: 0, dy: direction * step * CGFloat($0)) }
    }

    /// How many cards fit `visibleHeight` with `margin` above and below, at most `limit` and
    /// never fewer than one.
    static func capacity(cardHeight: CGFloat, visibleHeight: CGFloat,
                         margin: CGFloat = QuickAccessStackLayout.margin,
                         spacing: CGFloat = QuickAccessStackLayout.spacing, limit: Int) -> Int {
        let fits = Int(((visibleHeight - 2 * margin + spacing) / (cardHeight + spacing)).rounded(.down))
        return max(1, min(limit, fits))
    }
}
```

`TidyShot/Overlay/OverlayScreenChoice.swift`:
```swift
import CoreGraphics

/// The Overlay tab's `Show on` (spec 2.9).
nonisolated enum OverlayDisplayChoice: String, CaseIterable, Identifiable, Sendable {
    case capture, pointer, main

    var id: String { rawValue }

    var title: String {
        switch self {
        case .capture: "Display of the capture"
        case .pointer: "Display with the pointer"
        case .main: "Main display"
        }
    }
}

/// Picks the screen for the card stack, as an index into `NSScreen.screens`
/// (`screenDisplayIDs` in the same order; index 0 is the main display).
nonisolated enum OverlayScreenChoice {
    /// `.capture`: the screen showing `captureDisplayID`, else the pointer's, else 0.
    /// `.pointer`: the pointer's screen, else 0. `.main`: 0. A `pointerIndex` outside the list
    /// counts as none.
    static func index(choice: OverlayDisplayChoice, captureDisplayID: CGDirectDisplayID?,
                      pointerIndex: Int?, screenDisplayIDs: [CGDirectDisplayID]) -> Int {
        let pointer = pointerIndex.flatMap { screenDisplayIDs.indices.contains($0) ? $0 : nil }
        switch choice {
        case .capture:
            if let captureDisplayID, let index = screenDisplayIDs.firstIndex(of: captureDisplayID) {
                return index
            }
            return pointer ?? 0
        case .pointer:
            return pointer ?? 0
        case .main:
            return 0
        }
    }
}
```

- [ ] **Step 4: Settings**

`TidyShot/Settings/AppSettings.swift`:
- `Keys` (after `overlayAutoCloseSeconds`, line 42): `static let overlayDisplay = "overlayDisplay"`, `static let overlayMaxCards = "overlayMaxCards"`.
- Properties (after the `overlayAutoCloseSeconds` property, line 64):
  ```swift
      /// Which screen the card stack uses (Overlay tab, `Show on`).
      var overlayDisplay: OverlayDisplayChoice { didSet { defaults.set(overlayDisplay.rawValue, forKey: Keys.overlayDisplay) } }
      /// How many cards the stack shows at most (Overlay tab, `Show up to N overlays`).
      var overlayMaxCards: Int { didSet { defaults.set(overlayMaxCards, forKey: Keys.overlayMaxCards) } }
      static let overlayMaxCardsRange: ClosedRange<Int> = 1...8
  ```
- Registration (after `Keys.overlayAutoCloseSeconds: 5.0,`, line 109): `Keys.overlayDisplay: OverlayDisplayChoice.capture.rawValue`, `Keys.overlayMaxCards: 5`.
- Reads (after `overlayAutoCloseSeconds = defaults.double(…)`, line 126):
  ```swift
          overlayDisplay = OverlayDisplayChoice(rawValue: defaults.string(forKey: Keys.overlayDisplay) ?? "") ?? .capture
          overlayMaxCards = min(max(defaults.integer(forKey: Keys.overlayMaxCards), Self.overlayMaxCardsRange.lowerBound),
                                Self.overlayMaxCardsRange.upperBound)
  ```

`TidyShot/Settings/OverlaySettingsView.swift`, after the Auto-close stepper and its `.disabled` (line 20), before the `Keep history for …` stepper:
```swift
            Picker("Show on", selection: $settings.overlayDisplay) {
                ForEach(OverlayDisplayChoice.allCases) { choice in
                    Text(choice.title).tag(choice)
                }
            }
            .disabled(!settings.showOverlay)
            Stepper(value: $settings.overlayMaxCards, in: AppSettings.overlayMaxCardsRange) {
                Text(settings.overlayMaxCards == 1 ? "Show up to 1 overlay" : "Show up to \(settings.overlayMaxCards) overlays")
            }
            .disabled(!settings.showOverlay)
```
Task 6 adds `Close after dragging out` after the stepper.

- [ ] **Step 5: Display ids**

`TidyShot/Capture/CaptureEngine.swift`: below the class add
```swift
extension NSScreen {
    /// The CoreGraphics display id of this screen.
    var displayID: CGDirectDisplayID? {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }
}
```
and make `screen(forDisplayID:)` (lines 59-64) `NSScreen.screens.first { $0.displayID == id }`.

`TidyShot/Capture/CaptureTarget.swift`, after `enum CaptureTarget` (line 9):
```swift
extension CaptureTarget {
    /// The display the capture came from: the area's or the fullscreen display, or the display
    /// under a window's centre. The Quick Access stack goes there with `Show on` set to the capture.
    var displayID: CGDirectDisplayID {
        switch self {
        case .display(let display): display.displayID
        case .area(_, let display): display.displayID
        case .window(let window): CaptureEngine.displayID(containing: window.frame)
        }
    }
}
```

- [ ] **Step 6: The controller**

`TidyShot/Overlay/QuickAccessPanel.swift` line 18: `isMovableByWindowBackground = false` (dragging a card becomes drag-out in Task 6; the stack places its cards). Update the doc comment: "Floating, non-activating card in the Quick Access stack…".

`TidyShot/Overlay/QuickAccessController.swift`, replacing the file. `Actions` is unchanged (lines 6-15). The rest:
```swift
import AppKit

/// Shows the Quick Access cards: a stack on one screen, newest at the configured corner. Each
/// card updates as its upload progresses and closes on its own countdown once the upload has
/// settled, restarted while the pointer is over it.
final class QuickAccessController {
    struct Actions { /* lines 6-15 unchanged */ }

    /// One card: its panel, its model and its auto-close countdown.
    private final class Card {
        let model: QuickAccessModel
        let panel: QuickAccessPanel
        let autoCloseSeconds: Double
        var closeTask: Task<Void, Never>?

        init(model: QuickAccessModel, autoCloseSeconds: Double) {
            self.model = model
            self.panel = QuickAccessPanel(model: model)
            self.autoCloseSeconds = autoCloseSeconds
        }

        var id: UUID { model.record.id }
    }

    /// Called with the record's id each time a card closes, whatever closed it: the Close button,
    /// the auto-close timer, a delete, the editor opening, or a newer card pushing it out.
    var onDidClose: ((UUID) -> Void)?

    private let settings: AppSettings
    /// Newest first; index 0 sits at the corner.
    private var cards: [Card] = []
    /// The display the stack is on: an id, because AppKit replaces its `NSScreen` objects when
    /// the screen configuration changes.
    private var displayID: CGDirectDisplayID?
    /// The union of the frames from the last layout. The pointer inside it (plus the spacing)
    /// holds back the slide after a close.
    private var stackRegion = CGRect.null
    /// A close happened with the pointer over the stack; the cards close the gap once it leaves.
    private var relayoutPending = false
    private var pointerWatch: Task<Void, Never>?
    /// Lives as long as the controller, which `AppCoordinator.shared` owns for the app's life.
    private var screenObserver: (any NSObjectProtocol)?

    init(settings: AppSettings) {
        self.settings = settings
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.screensDidChange() }
        }
    }

    /// The cards on screen, for a capture's `excludingWindows`.
    var windowNumbers: Set<CGWindowID> {
        Set(cards.compactMap { $0.panel.isVisible && $0.panel.windowNumber > 0 ? CGWindowID($0.panel.windowNumber) : nil })
    }

    /// The records the cards show, newest first.
    var shownIDs: [UUID] { cards.map(\.id) }

    /// Whether a card shows `recordID` (restore's check, and Task 6's drag-file hand-over).
    func isShowing(recordID: UUID) -> Bool {
        cards.contains { $0.id == recordID }
    }

    /// The stack's screen while a card shows.
    var screen: NSScreen? {
        cards.isEmpty ? nil : displayID.flatMap(CaptureEngine.screen(forDisplayID:))
    }

    /// Adds a card for `record` at the corner of `screen`, moving the stack there. A card that
    /// already shows the record moves to the corner with the new state instead.
    func show(record: CaptureRecord, thumbnail: NSImage?, screen: NSScreen, autoCloseSeconds: Double, actions: Actions) {
        let sameScreen = displayID == screen.displayID
        displayID = screen.displayID
        let card: Card
        if let index = cards.firstIndex(where: { $0.id == record.id }) {
            card = cards.remove(at: index)
            card.model.record = record
            if let thumbnail { card.model.thumbnail = thumbnail }
        } else {
            card = makeCard(record: record, thumbnail: thumbnail, autoCloseSeconds: autoCloseSeconds, actions: actions)
        }
        cards.insert(card, at: 0)
        trim(to: screen)
        if !card.panel.isVisible {
            let corner = QuickAccessStackLayout.frames(count: 1, cardSize: QuickAccessView.size,
                                                       corner: settings.overlayCorner, visibleFrame: screen.visibleFrame)[0]
            card.panel.setFrame(corner, display: false)
            card.panel.orderFrontRegardless()
        }
        cancelPendingRelayout()
        layout(on: screen, animated: sameScreen)
        if card.model.isSettled {
            scheduleClose(card)
        } else {
            card.closeTask?.cancel()
            card.closeTask = nil
        }
    }

    /// Pushes a new record state into the card that shows that record, if any.
    func update(record: CaptureRecord) {
        guard let card = cards.first(where: { $0.id == record.id }) else { return }
        card.model.record = record
        if card.model.isSettled {
            scheduleClose(card)
        } else {
            card.closeTask?.cancel()
            card.closeTask = nil
        }
    }

    /// Closes the card that shows `recordID` (deleted, or opened in the editor).
    func close(recordID: UUID) {
        guard let card = cards.first(where: { $0.id == recordID }) else { return }
        closeCard(card)
        closeGap()
    }

    private func makeCard(record: CaptureRecord, thumbnail: NSImage?, autoCloseSeconds: Double, actions: Actions) -> Card {
        let model = QuickAccessModel(record: record, thumbnail: thumbnail)
        let id = record.id
        model.onCopy = { actions.copy(id) }
        model.onRetry = { actions.retry(id) }
        model.onReveal = { actions.reveal(id) }
        model.onDelete = { actions.delete(id) }
        model.onAnnotate = { actions.annotate(id) }
        let card = Card(model: model, autoCloseSeconds: autoCloseSeconds)
        model.onClose = { [weak self, weak card] in
            guard let self, let card else { return }
            self.closeCard(card)
            self.closeGap()
        }
        return card
    }

    /// Takes `card` off screen and out of the stack and reports it. The other cards stay put.
    private func closeCard(_ card: Card) {
        guard let index = cards.firstIndex(where: { $0 === card }) else { return }
        cards.remove(at: index)
        card.closeTask?.cancel()
        card.closeTask = nil
        card.panel.orderOut(nil)
        onDidClose?(card.id)
    }

    /// Closes the oldest cards until the stack fits `screen` and `settings.overlayMaxCards`.
    private func trim(to screen: NSScreen) {
        let capacity = QuickAccessStackLayout.capacity(cardHeight: QuickAccessView.size.height,
                                                       visibleHeight: screen.visibleFrame.height,
                                                       limit: settings.overlayMaxCards)
        while cards.count > capacity, let oldest = cards.last {
            closeCard(oldest)
        }
    }

    /// Moves every card to its slot; a card already there is not touched.
    private func layout(on screen: NSScreen, animated: Bool) {
        let frames = QuickAccessStackLayout.frames(count: cards.count, cardSize: QuickAccessView.size,
                                                   corner: settings.overlayCorner, visibleFrame: screen.visibleFrame)
        stackRegion = frames.reduce(CGRect.null) { $0.union($1) }
        let moves = zip(cards, frames).filter { $0.0.panel.frame != $0.1 }
        guard !moves.isEmpty else { return }
        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.2
                for (card, frame) in moves {
                    card.panel.animator().setFrame(frame, display: true)
                }
            }
        } else {
            for (card, frame) in moves {
                card.panel.setFrame(frame, display: true)
            }
        }
    }

    /// After a close: the cards slide into the gap now, or once the pointer has left the stack.
    private func closeGap() {
        guard !cards.isEmpty, let screen = stackScreen() else {
            cancelPendingRelayout()
            return
        }
        if pointerIsOverStack {
            relayoutPending = true
            watchPointer()
        } else {
            cancelPendingRelayout()
            layout(on: screen, animated: true)
        }
    }

    private var pointerIsOverStack: Bool {
        let spacing = QuickAccessStackLayout.spacing
        return !stackRegion.isNull && stackRegion.insetBy(dx: -spacing, dy: -spacing).contains(NSEvent.mouseLocation)
    }

    /// Polls every 250 ms while a slide is pending, and runs it once the pointer is outside.
    private func watchPointer() {
        guard pointerWatch == nil else { return }
        pointerWatch = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(250))
                guard let self, !Task.isCancelled else { return }
                guard self.relayoutPending else {
                    self.pointerWatch = nil
                    return
                }
                if !self.pointerIsOverStack {
                    self.pointerWatch = nil
                    self.closeGap()
                    return
                }
            }
        }
    }

    private func cancelPendingRelayout() {
        relayoutPending = false
        pointerWatch?.cancel()
        pointerWatch = nil
    }

    /// The stack's screen, or screen 0 when it is gone.
    private func stackScreen() -> NSScreen? {
        displayID.flatMap(CaptureEngine.screen(forDisplayID:)) ?? NSScreen.screens.first
    }

    /// A display was added, removed or rearranged, or the Dock or menu bar changed the visible
    /// frame: lay the stack out again at once, on its screen or screen 0.
    private func screensDidChange() {
        guard !cards.isEmpty, let screen = stackScreen() else { return }
        displayID = screen.displayID
        cancelPendingRelayout()
        trim(to: screen)
        layout(on: screen, animated: false)
    }

    /// Waits the card's `autoCloseSeconds`; while the pointer is over the card the countdown
    /// restarts (as `scheduleClose` did for the one panel).
    private func scheduleClose(_ card: Card) {
        card.closeTask?.cancel()
        card.closeTask = nil
        let seconds = card.autoCloseSeconds
        guard seconds > 0 else { return }
        card.closeTask = Task { [weak self, weak card] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(seconds))
                guard !Task.isCancelled else { return }
                if card?.model.isHovered == true { continue }
                break
            }
            guard !Task.isCancelled, let self, let card else { return }
            self.closeCard(card)
            self.closeGap()
        }
    }
}
```

- [ ] **Step 7: Exclusion in the selection**

`TidyShot/Selection/SelectionController.swift`:
- Add `private let cardWindowNumbers: () -> Set<CGWindowID>` after `engine` (line 7); `init(engine: CaptureEngine, cardWindowNumbers: @escaping () -> Set<CGWindowID> = { [] })` (lines 18-20) stores both.
- `overlayWindows()` (lines 62-72 on `main`, with Task 2's `guard !wanted.isEmpty` line) becomes:
  ```swift
      /// Our overlay windows and the Quick Access cards as ScreenCaptureKit sees them, for
      /// `excludingWindows`, through `OverlayWindowLookup` (by window number, with a short retry).
      /// A complete result is cached until `dismiss()`; it is reused while it covers every window
      /// wanted now, because a card can close (auto-close) or appear (Task 4's restore) meanwhile.
      func overlayWindows() async -> [SCWindow] {
          let wanted = Set(windows.compactMap { $0.windowNumber > 0 ? CGWindowID($0.windowNumber) : nil })
              .union(cardWindowNumbers())
          if let cachedOverlayWindows, Set(cachedOverlayWindows.map(\.windowID)).isSuperset(of: wanted) {
              return cachedOverlayWindows
          }
          guard !wanted.isEmpty else { return [] }
          let found = await OverlayWindowLookup.windows(numbers: wanted, engine: engine)
          if found.count >= wanted.count { cachedOverlayWindows = found }
          return found
      }
  ```
  Task 2's `captureFrozenSnapshots(options:)` takes its exclusion list from `overlayWindows()` before any selection window exists, so it now excludes exactly the cards, with no change to Task 2's code; a later call with the selection windows up misses the cards-only cache by the superset check and looks up again. The frozen image is what a frozen area capture is cut from, so this keeps the cards out of it.
- `takeSnapshots()` (the loupe), the line `guard overlays.count >= windows.count else { return }` (line 78 on `main`, kept by Task 2): the loupe needs every selection window excluded, and the cards in the result must not count toward that:
  ```swift
          let selectionNumbers = Set(windows.map { CGWindowID($0.windowNumber) })
          // A snapshot taken without every overlay excluded would show the dimming in the loupe; skip instead.
          guard selectionNumbers.isSubset(of: Set(overlays.map(\.windowID))) else { return }
  ```

- [ ] **Step 8: The coordinator**

`TidyShot/App/AppCoordinator.swift`:
- Line 29: `private let overlay = QuickAccessController(settings: AppSettings.shared)`.
- Line 30: `@ObservationIgnored private lazy var selector = SelectionController(engine: engine, cardWindowNumbers: { [weak self] in self?.overlay.windowNumbers ?? [] })`.
- Lines 52-55, the `latestCapture` doc: "…Cleared when its card closes, by the next capture and by `removeRecord`. Older cards in the stack load from the file or the bucket."
- `captureFullscreen()` (line 125): `guard let result = await capture(.display(display), excludingWindows: await cardWindows()) else { return }` (Task 1's `duringSelection` stays defaulted).
- `runSelection` needs no change: its area capture uses `selector.overlayWindows()`, which now holds the cards; its window capture never shows them.
- `save(_:)` line 254 passes `captureDisplayID: result.target.displayID` to `persist`; `persist` (lines 267-268) gains the parameter `captureDisplayID: CGDirectDisplayID` last and passes it on at line 305: `showOverlay(for: record, image: image.image, scale: image.scale, captureDisplayID: captureDisplayID)`.
- `showOverlay` (lines 394-411):
  ```swift
      private func showOverlay(for record: CaptureRecord, image: CGImage?, scale: CGFloat, captureDisplayID: CGDirectDisplayID) {
          guard settings.showOverlay, let screen = overlayScreen(captureDisplayID: captureDisplayID) else { return }
          // lines 396-400 unchanged: the well's crop and the NSImage
          overlay.show(record: record, thumbnail: thumbnail, screen: screen,
                       autoCloseSeconds: settings.overlayAutoCloseSeconds, actions: overlayActions())
          // After `show`: a card it pushed out of the stack has already reported its capture.
          latestCapture = image.map { (id: record.id, image: ScaledImage(image: $0, scale: scale)) }
      }

      /// Every card's buttons. Shared by new captures' cards and restored ones (Task 4).
      private func overlayActions() -> QuickAccessController.Actions {
          QuickAccessController.Actions(
              copy: { [weak self] id in self?.copyLinkOrFile(recordID: id) },
              retry: { [weak self] id in self?.retryUpload(recordID: id) },
              reveal: { [weak self] id in self?.reveal(recordID: id) },
              delete: { [weak self] id in Task { await self?.deleteCapture(recordID: id) } },
              annotate: { [weak self] id in self?.openEditorAfterMenuTracking(recordID: id) })
      }

      /// The screen for the card stack under `settings.overlayDisplay`; nil without screens.
      private func overlayScreen(captureDisplayID: CGDirectDisplayID?) -> NSScreen? {
          let screens = NSScreen.screens
          guard !screens.isEmpty else { return nil }
          let pointer = screens.firstIndex { $0.frame.contains(NSEvent.mouseLocation) }
          let index = OverlayScreenChoice.index(choice: settings.overlayDisplay, captureDisplayID: captureDisplayID,
                                                pointerIndex: pointer, screenDisplayIDs: screens.map { $0.displayID ?? 0 })
          return screens[index]
      }
  ```
- In `// MARK: Helpers`, before `withCaptureLock` (line 1514):
  ```swift
      /// The Quick Access cards as ScreenCaptureKit sees them, for a capture taken without the
      /// selection overlay; no lookup when no card shows.
      private func cardWindows() async -> [SCWindow] {
          let numbers = overlay.windowNumbers
          guard !numbers.isEmpty else { return [] }
          return await OverlayWindowLookup.windows(numbers: numbers, engine: engine)
      }
  ```
`removeRecord` (line 798), `presentEditor` (line 1088) and `refreshOverlay` (line 887) keep their calls; they now act on the card for that record.

- [ ] **Step 9: Run the suite**

Run the header's full-suite command. Expected: no `error:` lines and `Test run with 635 tests in 81 suites passed`. This task adds 15 tests and 2 suites: `QuickAccessStackLayoutTests` (8), `OverlayScreenChoiceTests` (5), and 2 in `AppSettingsTests`. `OverlayGeometryTests` is unchanged.

- [ ] **Step 10: Hand checks (Tim)**

For Tim; the implementer lists these in its report and goes on to Step 11. Task 8's checklist repeats them. Release build (`-configuration Release -derivedDataPath .build-rel`), re-grant Screen Recording after an ad-hoc rebuild. Settings > Overlay: Position Top right, Auto-close 10 s, Show on `Display of the capture`, Show up to 5.
- Take six area captures in a row: each new card appears at the top right, the older ones slide down 10 pt apart, and the sixth capture closes the oldest card. With Position Bottom left, the stack grows upward from the bottom left.
- Show up to 1: one card at the corner, replaced by the next capture, as in Phase 5.
- Hover the second card past its countdown: it stays, the others close on their own timers. Close the newest card with its Close button while the pointer stays where it was: the others slide up only after the pointer leaves the stack.
- Delete a middle card and Annotate another: each closes and the gap closes.
- With an upload-only capture uploading in one card and an older card settled: the uploading card stays until its URL is copied, then counts down.
- Dragging a card does not move it.
- Two displays at mixed scales: a capture on the second display puts the stack on the second display and moves existing cards there; `Display with the pointer` follows the pointer; `Main display` keeps it on the main display. Unplug the display the stack is on: the stack moves to the main display. Move the Dock or change resolution: the stack re-lays out at its corner.
- With three cards showing: ⌃⇧3 fullscreen, ⌃⇧4 over a card, and (with Freeze screen on, Task 2) ⌃⇧4 over a card: no card in any image, and the loupe shows the screen without the cards. ⌃⇧2 on a window behind a card: the window alone. ⌃⇧5 over a card: no card in the stitched image.

- [ ] **Step 11: Commit**

```bash
git add TidyShot/Overlay/QuickAccessStackLayout.swift TidyShot/Overlay/OverlayScreenChoice.swift TidyShot/Overlay/QuickAccessController.swift TidyShot/Overlay/QuickAccessPanel.swift TidyShot/Settings/AppSettings.swift TidyShot/Settings/OverlaySettingsView.swift TidyShot/App/AppCoordinator.swift TidyShot/Selection/SelectionController.swift TidyShot/Capture/CaptureTarget.swift TidyShot/Capture/CaptureEngine.swift TidyShotTests/QuickAccessStackLayoutTests.swift TidyShotTests/OverlayScreenChoiceTests.swift TidyShotTests/AppSettingsTests.swift
git commit -m "feat: stack of Quick Access cards on the capture's display, left out of captures"
```

### Task 4: Close badge, context menu and restore

**Files:**
- Create: `TidyShot/Overlay/ClosedOverlays.swift` (`ClosedOverlays`, pure)
- Modify: `TidyShot/Overlay/QuickAccessController.swift` (`QuickAccessCloseReason`; `onDidClose`, `close(recordID:)`, `closeCard`, `trim`, `scheduleClose` and `makeCard` from Task 3)
- Modify: `TidyShot/Overlay/QuickAccessModel.swift` (callbacks after line 16, `canReveal` after line 26)
- Modify: `TidyShot/Overlay/QuickAccessView.swift` (lines 9-49 `body`, lines 67-73 `thumbnail`, lines 81-124 `status`)
- Modify: `TidyShot/App/Shortcuts.swift` (after line 7)
- Modify: `TidyShot/App/StatusMenuController.swift` (after line 78 in `rebuild()`, lines 99-104 `captureItem`, an action after line 113)
- Modify: `TidyShot/Settings/ShortcutsSettingsView.swift` (after line 10)
- Modify: `TidyShot/App/AppCoordinator.swift` (line 84 `init`, `registerShortcuts()` lines 100-119, Task 3's `overlayActions()`, line 798 in `removeRecord`, lines 1061-1069 `openEditorAfterMenuTracking`, line 1088 in `presentEditor`; new members)
- Create: `TidyShotTests/ClosedOverlaysTests.swift` (struct `ClosedOverlaysTests`)
- Test: `TidyShotTests/ShortcutsTests.swift` (one test added)

Line numbers are `main`'s at a1dde71; Tasks 1 to 3 move some of them, so find each by the code named.

**Interfaces:**
- Consumes:
  - `main`: `ThumbnailProvider.thumbnail(for:) async -> NSImage?` (`ThumbnailProvider.swift:51`), `HistoryStore.record(id:)`, `CaptureRecord.linkURL`, `fileURL`, `fileIsTemporary`, `isUploading`, `uploadState` (`CaptureRecord.swift`), `AppCoordinator.copyLinkOrFile(recordID:)`, `retryUpload(recordID:)`, `reveal(recordID:)`, `deleteCapture(recordID:) async`, `openEditor(recordID:)`, `forgetLatestCapture(_:)`, `KeyboardShortcuts.getShortcut(for:)`, `KeyboardShortcuts.onKeyUp(for:)`.
  - Task 3: `QuickAccessController.show(record:thumbnail:screen:autoCloseSeconds:actions:)`, `update(record:)`, `close(recordID:)`, `onDidClose: ((UUID) -> Void)?`, `shownIDs`, `isShowing(recordID:)`, `screen`, the private `cards`, `closeCard(_:)`, `closeGap()`, `trim(to:)`, `scheduleClose(_:)`, `makeCard(record:thumbnail:autoCloseSeconds:actions:)`; `AppCoordinator.overlayActions()` and `overlayScreen(captureDisplayID:)`.
- Produces:
  - `nonisolated enum QuickAccessCloseReason: Equatable, Sendable { case user, autoClose, pushedOut, draggedOut, deleted, editorOpened; var isRestorable: Bool }` in `QuickAccessController.swift`.
  - `QuickAccessController.onDidClose: ((UUID, QuickAccessCloseReason) -> Void)?` and `func close(recordID: UUID, reason: QuickAccessCloseReason)`. Task 6 closes a dragged card with `close(recordID: id, reason: .draggedOut)`.
  - `nonisolated struct ClosedOverlays: Equatable, Sendable { static let limit = 10; private(set) var ids: [UUID]; mutating func didClose(_ id: UUID, reason: QuickAccessCloseReason); mutating func popRestorable(exists: (UUID) -> Bool, shown: Set<UUID>) -> UUID?; func hasRestorable(exists: (UUID) -> Bool, shown: Set<UUID>) -> Bool }`.
  - `QuickAccessModel.onSaveAs: () -> Void` and `onCopyImage: () -> Void` (`@ObservationIgnored`, default `{}`), called by the card's `Save As…` button and its `Save As…` and `Copy Image` menu items; Task 5 sets them in `makeCard` from `Actions.saveAs` and `Actions.copyImage` and needs no view change. `QuickAccessModel.canReveal: Bool`.
  - `KeyboardShortcuts.Name.restoreOverlay` (stored name `restoreOverlay`, no initial shortcut).
  - `AppCoordinator.restoreClosedOverlay() async`, `var canRestoreClosedOverlay: Bool`, `private func overlayDidClose(_ id: UUID, reason: QuickAccessCloseReason)` (the one handler of every card close; Task 6 adds the drag-folder clean-up to it), `private func afterMenuTracking(_ work: @escaping @MainActor () -> Void)` (Task 5's `saveAs` runs through it).

Behaviour (spec 2.9, Card layout, Close and restore):
- Close leaves the right column and becomes a badge at the card's top-left, shown only while the pointer is over the card: `xmark.circle.fill` on a material circle, help `Close`. The panel is the card's size, so the badge sits inside the corner, 4 pt in, over the thumbnail's corner. VoiceOver reaches Close through a named accessibility action and the context menu.
- The right column is Annotate (`pencil.tip.crop.circle`, help `Annotate`) and Delete (`trash`, help strings unchanged). Task 12 (6b) puts Pin between them.
- The status column's button row: `Copy URL  Save As…` once uploaded, `Retry  Save As…` after a failure, `Save As…` while uploading and after a plain save. The failure message drops to one line, with the full text as its help, so the row fits the 104 pt card. Save As… and Copy Image do nothing until Task 5 wires them.
- Right-click anywhere on the card: `Copy URL` (disabled without a link), `Copy Image`, `Save As…`, `Annotate`, `Reveal in Finder` (only with a save-folder file), a separator, `Close`, `Delete…`. 6b adds `Pin to Screen` after Annotate.
- The thumbnail's click reveals a save-folder file, as the spec says; a pending upload-only file in the container is no longer shown in Finder from the card (today `hasLocalFile` also revealed it). Both use `model.canReveal`.
- Delete, Close and Annotate run once menu tracking has ended (`RunLoop.main.perform(inModes: [.default])`), so the delete alert's `runModal()` never starts inside the context menu's tracking loop, and a card is never torn down inside its own hosting view's event.
- Every close reports a reason: the badge and the menu's Close `.user`, the countdown `.autoClose`, a newer card past the capacity `.pushedOut`, a delete or remove-from-history `.deleted`, Annotate `.editorOpened`; Task 6 adds `.draggedOut`. The first four push the id onto `ClosedOverlays` (newest first, at most 10, no duplicates); the last two take it off the list.
- **Restore Closed Overlay** pops the newest id that still has a history record and is not on screen (ids whose record is gone are dropped on the way; shown ones stay), loads its stored thumbnail through `ThumbnailProvider`, and shows its card at the corner of the stack's screen (or, with no card showing, the screen `overlayScreen(captureDisplayID: nil)` picks: the pointer's for `Display of the capture` and `Display with the pointer`, screen 0 for `Main display`), with the record's current state, the normal actions and the normal auto-close. Repeated use walks back through the list. `latestCapture` is not involved: a restored card's Annotate loads from the file or the bucket through `openEditor`, as Recent Captures does. The list lives in memory only.
- Menu item `Restore Closed Overlay` after Recent Captures, enabled while the list holds a restorable id; the title carries the shortcut once one is recorded, as the capture items do. Shortcuts tab: `Restore closed overlay:` after the four existing recorders (Task 7 puts `Capture previous area:` before it).

- [ ] **Step 1: Write the failing tests**

`TidyShotTests/ClosedOverlaysTests.swift` (new):
```swift
import Foundation
import Testing
@testable import TidyShot

/// The recently closed cards that Restore Closed Overlay walks back through (spec 2.9).
struct ClosedOverlaysTests {
    let a = UUID()
    let b = UUID()
    let c = UUID()

    @Test func newestFirst() {
        var closed = ClosedOverlays()
        closed.didClose(a, reason: .autoClose)
        closed.didClose(b, reason: .user)
        closed.didClose(c, reason: .pushedOut)
        #expect(closed.ids == [c, b, a])
    }

    @Test func keepsTheTenNewest() {
        var closed = ClosedOverlays()
        let ids = (0..<12).map { _ in UUID() }
        for id in ids {
            closed.didClose(id, reason: .autoClose)
        }
        #expect(ClosedOverlays.limit == 10)
        #expect(closed.ids == Array(ids.reversed().prefix(10)))
    }

    /// A card closed, restored and closed again is listed once, at the front.
    @Test func aSecondCloseMovesTheIdToTheFront() {
        var closed = ClosedOverlays()
        closed.didClose(a, reason: .user)
        closed.didClose(b, reason: .autoClose)
        closed.didClose(a, reason: .draggedOut)
        #expect(closed.ids == [a, b])
    }

    /// Deleted captures and captures now in the editor are not restorable, and leave the list.
    @Test func onlyUserAutoPushedAndDraggedClosesAreRestorable() {
        let restorable: [QuickAccessCloseReason] = [.user, .autoClose, .pushedOut, .draggedOut]
        #expect(restorable.allSatisfy(\.isRestorable))
        #expect(!QuickAccessCloseReason.deleted.isRestorable)
        #expect(!QuickAccessCloseReason.editorOpened.isRestorable)

        var closed = ClosedOverlays()
        closed.didClose(a, reason: .deleted)
        closed.didClose(b, reason: .editorOpened)
        #expect(closed.ids.isEmpty)
        closed.didClose(a, reason: .user)
        closed.didClose(c, reason: .autoClose)
        closed.didClose(a, reason: .editorOpened)
        #expect(closed.ids == [c])
    }

    /// The newest id with a record that is not on screen. Ids without a record are dropped for
    /// good; a shown one stays for later.
    @Test func popSkipsDeletedAndShownIds() {
        var closed = ClosedOverlays()
        closed.didClose(a, reason: .user)
        closed.didClose(b, reason: .user)
        closed.didClose(c, reason: .user)
        let deleted = c
        #expect(closed.popRestorable(exists: { $0 != deleted }, shown: [b]) == a)
        #expect(closed.ids == [b])
        #expect(closed.popRestorable(exists: { _ in true }, shown: [b]) == nil)
        #expect(closed.ids == [b])
        #expect(closed.popRestorable(exists: { _ in true }, shown: []) == b)
        #expect(closed.ids.isEmpty)
    }

    @Test func repeatedRestoresWalkBack() {
        var closed = ClosedOverlays()
        closed.didClose(a, reason: .autoClose)
        closed.didClose(b, reason: .pushedOut)
        closed.didClose(c, reason: .user)
        var restored: [UUID] = []
        while let id = closed.popRestorable(exists: { _ in true }, shown: []) {
            restored.append(id)
        }
        #expect(restored == [c, b, a])
    }

    /// What the menu item's enabled state reads; it changes nothing.
    @Test func hasRestorableMatchesPop() {
        var closed = ClosedOverlays()
        #expect(!closed.hasRestorable(exists: { _ in true }, shown: []))
        closed.didClose(a, reason: .user)
        #expect(closed.hasRestorable(exists: { _ in true }, shown: []))
        #expect(!closed.hasRestorable(exists: { _ in false }, shown: []))
        #expect(!closed.hasRestorable(exists: { _ in true }, shown: [a]))
        #expect(closed.ids == [a])
    }
}
```

`TidyShotTests/ShortcutsTests.swift`, inside `ShortcutsTests`:
```swift
    /// Restore Closed Overlay has a recorder in the Shortcuts tab but no default (spec 2.9).
    @Test func restoreOverlayHasNoInitialShortcut() {
        #expect(KeyboardShortcuts.Name.restoreOverlay.rawValue == "restoreOverlay")
        #expect(KeyboardShortcuts.Name.restoreOverlay.initialShortcut == nil)
    }
```

- [ ] **Step 2: Run the tests and see them fail**

Run the header's full-suite command. Expected: the build fails with `cannot find 'ClosedOverlays' in scope`, `cannot find type 'QuickAccessCloseReason' in scope` and `type 'KeyboardShortcuts.Name' has no member 'restoreOverlay'`.

- [ ] **Step 3: The close reason and the list**

`TidyShot/Overlay/QuickAccessController.swift`, above the class:
```swift
/// Why a Quick Access card closed (spec 2.9, Close and restore).
nonisolated enum QuickAccessCloseReason: Equatable, Sendable {
    /// The Close badge or the context menu's Close.
    case user
    case autoClose
    /// A newer card took the last place in the stack.
    case pushedOut
    /// Dragged out with Close after dragging out on (Task 6).
    case draggedOut
    /// The capture was deleted or removed from history.
    case deleted
    /// Annotate: the editor holds the capture now.
    case editorOpened

    /// Restore Closed Overlay brings these back; a deleted capture is gone and an edited one is
    /// in its editor.
    var isRestorable: Bool {
        switch self {
        case .user, .autoClose, .pushedOut, .draggedOut: true
        case .deleted, .editorOpened: false
        }
    }
}
```

`TidyShot/Overlay/ClosedOverlays.swift`:
```swift
import Foundation

/// The ids of recently closed Quick Access cards, newest first, at most `limit`, each once.
/// In memory only: it empties at quit, and Recent Captures is the long-term way back.
nonisolated struct ClosedOverlays: Equatable, Sendable {
    static let limit = 10

    private(set) var ids: [UUID] = []

    /// A restorable close puts `id` at the front; any other takes it off the list.
    mutating func didClose(_ id: UUID, reason: QuickAccessCloseReason) {
        ids.removeAll { $0 == id }
        guard reason.isRestorable else { return }
        ids.insert(id, at: 0)
        if ids.count > Self.limit {
            ids.removeLast(ids.count - Self.limit)
        }
    }

    /// Removes and returns the newest id that `exists` (still has a history record) and is not
    /// `shown`. Ids without a record are dropped on the way; shown ones stay.
    mutating func popRestorable(exists: (UUID) -> Bool, shown: Set<UUID>) -> UUID? {
        ids.removeAll { !exists($0) }
        guard let index = ids.firstIndex(where: { !shown.contains($0) }) else { return nil }
        return ids.remove(at: index)
    }

    /// Whether `popRestorable` would return an id, without changing the list.
    func hasRestorable(exists: (UUID) -> Bool, shown: Set<UUID>) -> Bool {
        ids.contains { exists($0) && !shown.contains($0) }
    }
}
```

- [ ] **Step 4: Reasons in the controller**

`TidyShot/Overlay/QuickAccessController.swift` (Task 3's code):
- `var onDidClose: ((UUID, QuickAccessCloseReason) -> Void)?`, doc "Called with the record's id and the reason each time a card closes."
- `closeCard(_ card: Card, reason: QuickAccessCloseReason)` ends with `onDidClose?(card.id, reason)`.
- `func close(recordID: UUID, reason: QuickAccessCloseReason)`: the same body, passing `reason`; doc "Closes the card that shows `recordID`: `.deleted`, `.editorOpened`, or `.draggedOut` (Task 6)."
- `trim(to:)`: `closeCard(oldest, reason: .pushedOut)`. `scheduleClose`: `closeCard(card, reason: .autoClose)`.
- `makeCard`: `model.onSaveAs` and `model.onCopyImage` keep their no-op defaults (Task 5 sets them). `model.onClose`, from the badge or the context menu, now runs after menu tracking:
  ```swift
          model.onClose = { [weak self, weak card] in
              // After the context menu's tracking, and outside the hosting view's own click.
              RunLoop.main.perform(inModes: [.default]) {
                  MainActor.assumeIsolated {
                      guard let self, let card else { return }
                      self.closeCard(card, reason: .user)
                      self.closeGap()
                  }
              }
          }
  ```

- [ ] **Step 5: Model and view**

`TidyShot/Overlay/QuickAccessModel.swift`, after line 16:
```swift
    /// Task 5 wires these to `AppCoordinator.saveAs(recordID:)` and `copyImage(recordID:)`.
    @ObservationIgnored var onSaveAs: () -> Void = {}
    @ObservationIgnored var onCopyImage: () -> Void = {}
```
and after `isSettled`:
```swift
    /// A file in the save folder to show in Finder. A pending upload-only file lives in the
    /// container and is not revealed.
    var canReveal: Bool {
        record.fileURL != nil && !record.fileIsTemporary
    }
```

`TidyShot/Overlay/QuickAccessView.swift` (doc line 3: "Thumbnail, upload status with Copy URL, Retry and Save As…, Annotate and Delete, a hover Close badge, and a context menu with every action."):
- `body` (lines 9-49):
  ```swift
      var body: some View {
          HStack(spacing: 12) {
              thumbnail
              VStack(alignment: .leading, spacing: 4) {
                  status
                  buttonRow
              }
              .frame(maxWidth: .infinity, alignment: .leading)
              VStack(spacing: 8) {
                  Button {
                      model.onAnnotate()
                  } label: {
                      Image(systemName: "pencil.tip.crop.circle")
                          .foregroundStyle(.secondary)
                  }
                  .buttonStyle(.plain)
                  .help("Annotate")
                  .accessibilityLabel("Annotate")
                  Button {
                      model.onDelete()
                  } label: {
                      Image(systemName: "trash")
                          .foregroundStyle(.secondary)
                  }
                  .buttonStyle(.plain)
                  .help(model.record.isUploading ? "Cancel the upload and delete this capture" : "Delete this capture")
              }
          }
          .padding(12)
          .frame(width: Self.size.width, height: Self.size.height)
          .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
          .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.quaternary))
          .overlay(alignment: .topLeading) { closeBadge }
          .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
          .contextMenu { menuItems }
          .onHover { model.isHovered = $0 }
          .accessibilityAction(named: "Close") { model.onClose() }
      }

      /// Shown while the pointer is over the card, as the macOS screenshot thumbnail does.
      @ViewBuilder
      private var closeBadge: some View {
          if model.isHovered {
              Button {
                  model.onClose()
              } label: {
                  Image(systemName: "xmark.circle.fill")
                      .font(.system(size: 16))
                      .symbolRenderingMode(.hierarchical)
                      .foregroundStyle(.secondary)
                      .background(.regularMaterial, in: Circle())
              }
              .buttonStyle(.plain)
              .help("Close")
              .accessibilityLabel("Close")
              .padding(4)
          }
      }

      @ViewBuilder
      private var menuItems: some View {
          Button("Copy URL") { model.onCopy() }
              .disabled(model.record.linkURL == nil)
          Button("Copy Image") { model.onCopyImage() }
          Button("Save As…") { model.onSaveAs() }
          Button("Annotate") { model.onAnnotate() }
          if model.canReveal {
              Button("Reveal in Finder") { model.onReveal() }
          }
          Divider()
          Button("Close") { model.onClose() }
          Button("Delete…") { model.onDelete() }
      }

      /// Copy URL or Retry when they apply, then Save As… in every state.
      private var buttonRow: some View {
          HStack(spacing: 6) {
              switch model.record.uploadState {
              case .uploaded:
                  Button("Copy URL") { model.onCopy() }
              case .failed:
                  Button("Retry") { model.onRetry() }
              case .uploading, .none:
                  EmptyView()
              }
              Button("Save As…") { model.onSaveAs() }
          }
          .controlSize(.small)
      }
  ```
  `Copy URL` in the menu runs `onCopy` (`copyLinkOrFile`), and is disabled without a link, so from the menu it only ever copies the link.
- `thumbnail` (lines 67-73): `if model.canReveal` in place of `if model.record.hasLocalFile`.
- `status` (lines 81-124): the same lines with `Button("Copy URL")` (line 104) and `Button("Retry")` (line 113) removed (they live in `buttonRow`), and the failure message `.lineLimit(1)` with `.help(message)` in place of `.lineLimit(2)`.

- [ ] **Step 6: Shortcut, menu and Settings**

`TidyShot/App/Shortcuts.swift`, after line 7:
```swift
    /// Restore Closed Overlay. No default; the Shortcuts tab records one.
    static let restoreOverlay = Self("restoreOverlay")
```

`TidyShot/Settings/ShortcutsSettingsView.swift`, after line 10: `KeyboardShortcuts.Recorder("Restore closed overlay:", name: .restoreOverlay)`.

`TidyShot/App/StatusMenuController.swift`:
- `captureItem` (lines 99-104) builds its title through a new helper, which the restore item shares:
  ```swift
      /// "Title  ⌃⇧4" when `name` has a shortcut, otherwise the title alone.
      private func title(_ title: String, shortcut name: KeyboardShortcuts.Name) -> String {
          KeyboardShortcuts.getShortcut(for: name).map { "\(title)  \($0)" } ?? title
      }
  ```
- `rebuild()`, after `menu.addItem(recentCaptures.item)` (line 78):
  ```swift
          let restore = item(title("Restore Closed Overlay", shortcut: .restoreOverlay), #selector(restoreClosedOverlay))
          restore.isEnabled = coordinator.canRestoreClosedOverlay
          menu.addItem(restore)
  ```
  It is not disabled while a capture runs: restoring captures nothing.
- After line 113: `@objc private func restoreClosedOverlay() { Task { await coordinator.restoreClosedOverlay() } }`.

- [ ] **Step 7: The coordinator**

`TidyShot/App/AppCoordinator.swift`:
- New stored property after `latestCapture` (line 56):
  ```swift
      /// Recently closed cards for Restore Closed Overlay. In memory only.
      @ObservationIgnored private var closedOverlays = ClosedOverlays()
  ```
- `init`, line 84: `overlay.onDidClose = { [weak self] id, reason in self?.overlayDidClose(id, reason: reason) }`.
- `registerShortcuts()`, after the ⌃⇧5 registration (line 112):
  ```swift
          KeyboardShortcuts.onKeyUp(for: .restoreOverlay) { [weak self] in
              Task { await self?.restoreClosedOverlay() }
          }
  ```
- `removeRecord` (line 798): `overlay.close(recordID: id, reason: .deleted)`. `presentEditor` (line 1088): `overlay.close(recordID: record.id, reason: .editorOpened)`.
- `openEditorAfterMenuTracking` (lines 1061-1069) becomes the general helper plus its one-line use:
  ```swift
      /// Runs `work` when the run loop is back in its default mode, after any menu tracking (the
      /// card's context menu, the status menu), as `RecentCapturesMenu.afterMenusClose` does for rows.
      private func afterMenuTracking(_ work: @escaping @MainActor () -> Void) {
          RunLoop.main.perform(inModes: [.default]) {
              MainActor.assumeIsolated { work() }
          }
      }

      /// The card's Annotate.
      private func openEditorAfterMenuTracking(recordID: UUID) {
          afterMenuTracking { [weak self] in self?.openEditor(recordID: recordID) }
      }
  ```
- `overlayActions()` (Task 3): `delete: { [weak self] id in self?.afterMenuTracking { Task { await self?.deleteCapture(recordID: id) } } }`; the other actions are unchanged.
- New, after `overlayScreen(captureDisplayID:)`:
  ```swift
      /// Every card close: the retained image goes with the newest card, and a restorable close is
      /// remembered.
      private func overlayDidClose(_ id: UUID, reason: QuickAccessCloseReason) {
          forgetLatestCapture(id)
          closedOverlays.didClose(id, reason: reason)
      }

      /// Whether Restore Closed Overlay has a card to bring back (the menu item's state).
      var canRestoreClosedOverlay: Bool {
          closedOverlays.hasRestorable(exists: { history.record(id: $0) != nil }, shown: Set(overlay.shownIDs))
      }

      /// Restore Closed Overlay: the newest closed card whose capture still exists and is not
      /// showing, again at the corner of the stack's screen, with the record as it is now and its
      /// stored thumbnail. Annotate on it loads from the file or the bucket.
      func restoreClosedOverlay() async {
          guard let id = closedOverlays.popRestorable(exists: { history.record(id: $0) != nil },
                                                      shown: Set(overlay.shownIDs)),
                let record = history.record(id: id) else { return }
          let thumbnail = await thumbnailProvider.thumbnail(for: record)
          // Deleted during the read, or shown by a second restore meanwhile.
          guard let current = history.record(id: id), !overlay.isShowing(recordID: id),
                let screen = overlay.screen ?? overlayScreen(captureDisplayID: nil) else { return }
          overlay.show(record: current, thumbnail: thumbnail, screen: screen,
                       autoCloseSeconds: settings.overlayAutoCloseSeconds, actions: overlayActions())
      }
  ```
  Restore does not check `settings.showOverlay`: it is an explicit request, and with the overlay off no card closes, so the list is empty unless the setting changed after cards had closed.

- [ ] **Step 8: Run the suite**

Run the header's full-suite command. Expected: no `error:` lines and `Test run with 643 tests in 82 suites passed`. This task adds 8 tests and 1 suite: `ClosedOverlaysTests` (7) and 1 in `ShortcutsTests`.

- [ ] **Step 9: Hand checks (Tim)**

For Tim; the implementer lists these in its report and goes on to Step 10. Task 8's checklist repeats them. Release build (`-configuration Release -derivedDataPath .build-rel`). Settings > Shortcuts: record a shortcut for `Restore closed overlay:` (say ⌃⇧7).
- Hover a card: the Close badge appears at its top-left and goes when the pointer leaves; clicking it closes the card. The right column holds Annotate and Delete.
- Button row: `Save As…` while uploading, `Copy URL  Save As…` after the upload, `Retry  Save As…` after a failure (turn Wi-Fi off), `Save As…` alone in Save mode. Save As… and Copy Image do nothing yet (Task 5).
- Right-click a card: the menu lists `Copy URL`, `Copy Image`, `Save As…`, `Annotate`, `Reveal in Finder` (Save mode only), a separator, `Close`, `Delete…`. `Copy URL` is disabled while uploading and copies the link after. `Delete…` brings the confirmation alert to the front, and Cancel leaves the card. `Close` closes it. `Annotate` opens the editor and closes the card. The menu must appear on a card although the panel is non-activating and TidyShot is not frontmost. If it does not, the fallback, an `NSHostingView` subclass whose `menu(for:)` returns an `NSMenu` with the same items, is a follow-up; it is not built in 6a.
- Clicking the thumbnail of an upload-only card does nothing; of a Save-mode card it reveals the file.
- Restore after each close reason: close one with the badge, let one auto-close, push one out with a sixth capture; ⌃⇧7 three times brings them back newest first, each with its thumbnail, and each counts down again. The menu item reads `Restore Closed Overlay  ⌃⇧7` and is disabled once nothing is left.
- Delete a card's capture, and Annotate another: neither comes back. Delete a closed capture from Recent Captures: restore skips it.
- Upload-only mode: close a card after its URL is copied, restore it, and Annotate it: the editor opens from the downloaded object.
- With the stack on the second display, restore: the card joins that stack. With no card showing, restore puts the card on the pointer's display.

- [ ] **Step 10: Commit**

```bash
git add TidyShot/Overlay/ClosedOverlays.swift TidyShot/Overlay/QuickAccessController.swift TidyShot/Overlay/QuickAccessModel.swift TidyShot/Overlay/QuickAccessView.swift TidyShot/App/Shortcuts.swift TidyShot/App/StatusMenuController.swift TidyShot/Settings/ShortcutsSettingsView.swift TidyShot/App/AppCoordinator.swift TidyShotTests/ClosedOverlaysTests.swift TidyShotTests/ShortcutsTests.swift
git commit -m "feat: card close badge, context menu and Restore Closed Overlay"
```

### Task 5: Save As… and Copy Image from the card

**Files:**
- Modify: `TidyShot/App/AppCoordinator.swift` (`imageData(of:downloadTitle:)` doc, lines 608-612; `editorActions(for:)`, lines 1099-1102; `editorSaveAs(recordID:image:to:)`, lines 1264-1295; `editorSaveAsSuggestion(recordID:)`, lines 1297-1303; the `QuickAccessController.Actions` builder, Task 3's `overlayActions()` (it replaced `showOverlay`'s inline `Actions(...)`, lines 403-408 on `main`; Task 4 changed its `delete:`); new `saveAs(recordID:)` and `saveCopy(recordID:)` after `copyImage(recordID:)`, line 606. Line numbers are `main`'s; Tasks 1 to 4 add lines above some of them, so find each by its name.)
- Modify: `TidyShot/Overlay/QuickAccessController.swift` (`Actions`, lines 6-15 on `main`; Task 3's per-card wiring, where `model.onAnnotate = { actions.annotate(id) }` is set)
- Modify: `TidyShot/Editor/Persistence/EditorNaming.swift` (imports, line 1; new `savePanel(for:)` after line 27)
- Modify: `TidyShot/Editor/Window/EditorWindowController.swift` (`performSaveAs()`, lines 241-247)
- Test: `TidyShotTests/EditorNamingTests.swift` (two tests added after `noFolderLeavesTheDirectoryToThePanel`, line 49). The other `EditorNamingTests` and the rest of the suite stay as they are and must stay green.

`QuickAccessView.swift` is not touched: Task 4 already puts `Save As…` in the status row in every state and `Copy Image` and `Save As…` in the context menu, calling `model.onSaveAs()` and `model.onCopyImage()`. This task gives those callbacks something to do.

**Interfaces:**
- Consumes:
  - `main`: `AppCoordinator.copyImage(recordID:) async` (`AppCoordinator.swift:588`), `imageData(of:downloadTitle:) async throws -> Data` (`:612`, the local file or a signed GET that posts `Downloading <key>` under the given title), `Notifier.notifySaved(fileURL:title:)` and `notifyError(_:title:)`, `EditorNaming.saveAsSuggestion(for:saveFolder:namer:currentCounter:) -> EditorNaming.SaveAsSuggestion` (`EditorNaming.swift:17`), `settings.currentCounter`, `settings.fileNameTemplate`, `saveLocation.currentURL`.
  - Task 3: `QuickAccessController` with one `QuickAccessModel` per card, each wired in `makeCard(record:thumbnail:autoCloseSeconds:actions:)` from the `Actions` passed to `show(record:thumbnail:screen:autoCloseSeconds:actions:)`; `AppCoordinator.overlayActions() -> QuickAccessController.Actions`, the one builder of the actions, shared by `showOverlay` and Task 4's `restoreClosedOverlay()`.
  - Task 4: `QuickAccessModel.onSaveAs: () -> Void` and `onCopyImage: () -> Void` (both `@ObservationIgnored`, default `{}`, left as no-ops by Task 4), called by the card's `Save As…` button and its `Save As…` and `Copy Image` menu items; `AppCoordinator.afterMenuTracking(_:)`, the after-menu-tracking helper.
- Produces:
  - `AppCoordinator.saveAs(recordID: UUID)` (internal, not async): runs the card's Save As… through Task 4's `afterMenuTracking`, so after any menu tracking. Task 12 calls it from the pin's context menu.
  - `AppCoordinator.saveAsSuggestion(recordID: UUID) -> EditorNaming.SaveAsSuggestion` (private; the renamed `editorSaveAsSuggestion`). Task 6 uses it for the drag file's name.
  - `AppCoordinator.writeSaveAsCopy(_ png: Data, to url: URL) async -> Bool` (private): the one Save As… write, shared by the editor and the card.
  - `EditorNaming.savePanel(for suggestion: EditorNaming.SaveAsSuggestion) -> NSSavePanel` (`@MainActor`): PNG only, the suggestion's name and folder. Shared by the editor's sheet and the card's panel.
  - `QuickAccessController.Actions.saveAs: (UUID) -> Void` and `.copyImage: (UUID) -> Void`.

Behaviour (spec 2.9, Save As… and Card layout):
- `Save As…` from the card's button or its menu activates TidyShot and opens an `NSSavePanel` as a window, not a sheet (the card is a non-activating panel that cannot become key). PNG is the only type. Name and folder are what the editor's Save As… suggests for the same record: the record's own file name in the save folder, otherwise the file name template's name with the current `{counter}` (none drawn). With no save folder set (upload-only mode), the panel opens where it last was.
- After OK the PNG is read through `imageData(of:)`: the local file (save folder or `pending`), or for an upload-only capture whose file is gone a signed GET, with `Downloading <key>` posted under the title `Saving a copy…` while it runs (header, point 3; Task 6 puts the card's drag copy between the local file and the GET). The bytes are written as they are, no decode and no re-encode, atomically, to the panel's URL; the panel's grant covers the write under the sandbox (`com.apple.security.files.user-selected.read-write` is already in `TidyShot.entitlements`).
- Success posts `Saved` with the file name when Show notification is on (a click reveals the copy). A failed read or write posts the error titled `Not saved`. Cancel does nothing.
- Save As… exports a copy: the record, its link, its thumbnail, `lastCaptureURL` and the clipboard do not change. The card stays open and its auto-close is unchanged.
- `Copy Image` from the card's menu is Recent Captures' Copy Image (`copyImage(recordID:)`): the PNG and TIFF on the clipboard, from the file or a signed GET (`Copying image…`), then `Image copied`. The card stays open.
- The editor's Save As… keeps its behaviour. It now builds its panel with `EditorNaming.savePanel(for:)` and writes through `writeSaveAsCopy`, so `Saved` is posted before the clipboard rule runs instead of after; nothing a user sees changes.

- [ ] **Step 1: Write the tests**

`TidyShotTests/EditorNamingTests.swift`, after `noFolderLeavesTheDirectoryToThePanel` (line 49), add:
```swift
    /// The card's Save As… (spec 2.9) uses this suggestion. An upload-only capture before its
    /// upload finished (its pending `<id>.png`, uploading or failed) has no key: the template's
    /// name, in the save folder when one is set, else where the panel last was.
    @Test func uploadOnlyCaptureWithoutAKeySuggestsTheTemplateName() {
        let pending = URL(fileURLWithPath: "/tmp/pending/\(UUID().uuidString).png")
        let uploading = CaptureRecord(fileURL: pending, fileIsTemporary: true, pixelWidth: 64, pixelHeight: 48,
                                      appName: nil, uploadState: .uploading(fraction: 0.4))
        let failed = CaptureRecord(fileURL: pending, fileIsTemporary: true, pixelWidth: 64, pixelHeight: 48,
                                   appName: nil, uploadState: .failed(message: "Upload not configured."))
        for record in [uploading, failed] {
            #expect(EditorNaming.saveAsSuggestion(for: record, saveFolder: folder, namer: namer(), currentCounter: 7)
                    == EditorNaming.SaveAsSuggestion(fileName: "Screenshot 2026-10-20 at 09.15.02.png", directory: folder))
            #expect(EditorNaming.saveAsSuggestion(for: record, saveFolder: nil, namer: namer(), currentCounter: 7)
                    == EditorNaming.SaveAsSuggestion(fileName: "Screenshot 2026-10-20 at 09.15.02.png", directory: nil))
        }
    }

    /// With a key: an uploaded upload-only capture (no file) still gets the template's name, not the
    /// key (the key names the drag file, Task 6); `{counter}` is the current one. A save-folder file
    /// that was also uploaded keeps its own name.
    @Test func uploadedCaptureWithAKeySuggestsTheTemplateOrItsOwnName() {
        let link = URL(string: "https://snap.example.com/shots/aSIS7.png")!
        let uploadedOnly = CaptureRecord(fileURL: nil, pixelWidth: 64, pixelHeight: 48, appName: nil,
                                         uploadState: .uploaded(url: link, key: "shots/aSIS7.png"))
        #expect(EditorNaming.saveAsSuggestion(for: uploadedOnly, saveFolder: nil, namer: namer(), currentCounter: 7)
                == EditorNaming.SaveAsSuggestion(fileName: "Screenshot 2026-10-20 at 09.15.02.png", directory: nil))
        #expect(EditorNaming.saveAsSuggestion(for: uploadedOnly, saveFolder: folder, namer: namer("shot-{counter}"),
                                              currentCounter: 12).fileName == "shot-12.png")

        let file = folder.appending(path: "Bug 12.png")
        let savedAndUploaded = CaptureRecord(fileURL: file, pixelWidth: 64, pixelHeight: 48, appName: nil,
                                             uploadState: .uploaded(url: link, key: "shots/aSIS7.png"))
        #expect(EditorNaming.saveAsSuggestion(for: savedAndUploaded, saveFolder: folder, namer: namer(), currentCounter: 7)
                == EditorNaming.SaveAsSuggestion(fileName: "Bug 12.png", directory: folder))
    }
```

- [ ] **Step 2: Run the tests**

Run the header's full-suite command. Expected: both new tests pass at once. They pin the suggestion the card now relies on (`EditorNaming.swift:20-25` already treats a pending `<id>.png` and a missing file alike and never looks at the key); the card-side code is AppKit wiring, covered by the hand checks in Step 6.

- [ ] **Step 3: The shared panel and the shared write**

`TidyShot/Editor/Persistence/EditorNaming.swift`: replace `import Foundation` (line 1) with
```swift
import AppKit
import UniformTypeIdentifiers
```
and after `saveAsSuggestion(for:saveFolder:namer:currentCounter:)` (after line 27, inside the enum) add:
```swift
    /// The Save As… panel for `suggestion`: PNG only, its name, and its folder when it has one
    /// (otherwise the panel opens where it last was). The editor shows it as a sheet, a Quick
    /// Access card as a window.
    @MainActor
    static func savePanel(for suggestion: SaveAsSuggestion) -> NSSavePanel {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = suggestion.fileName
        if let directory = suggestion.directory {
            panel.directoryURL = directory
        }
        return panel
    }
```
The type doc (line 3) becomes `/// What a Save As… panel suggests, for the editor and for a Quick Access card.`

`TidyShot/Editor/Window/EditorWindowController.swift`, `performSaveAs()`: replace lines 241-247 (`let suggestion = ...` through the closing brace of `if let directory`) with
```swift
        let panel = EditorNaming.savePanel(for: actions.saveAsSuggestion())
```
The `beginSheetModal` line and the rest stay.

`TidyShot/App/AppCoordinator.swift`:
- Rename `editorSaveAsSuggestion(recordID:)` (lines 1297-1303) to `saveAsSuggestion(recordID:)`, doc `/// The Save As… suggestion for `recordID`, the editor's and the card's: its file name in the save folder, or the file name template's name with the current `{counter}` (none is drawn).`, and update its one caller in `editorActions(for:)` (line 1100) to `self?.saveAsSuggestion(recordID: recordID)`.
- Replace `editorSaveAs(recordID:image:to:)`'s body from `let png: Data` (line 1278) to the end of the function (line 1295) with:
```swift
        let png: Data
        do {
            png = try await Task.detached(priority: .userInitiated) {
                try ImageEncoder.pngData(from: image.image, scale: image.scale)
            }.value
        } catch {
            NSLog("Save As failed: \(error.localizedDescription)")
            notifier.notifyError(error.localizedDescription, title: "Not saved")
            return false
        }
        guard await writeSaveAsCopy(png, to: url) else { return false }
        await replaceClipboardIfStillOriginal(recordID: recordID, png: png, image: image)
        return true
    }

    /// The one Save As… write, for the editor and for a card: `png` as it is, atomically, to a
    /// URL a save panel returned. The panel's URL is user-selected, so the sandbox grants the
    /// write, and no bookmark is kept. Posts `Saved` with the file name when notifications are on,
    /// or the error as `Not saved`. Touches no record.
    @discardableResult
    private func writeSaveAsCopy(_ png: Data, to url: URL) async -> Bool {
        do {
            try await Task.detached(priority: .userInitiated) {
                try png.write(to: url, options: .atomic)
            }.value
        } catch {
            NSLog("Save As failed: \(error.localizedDescription)")
            notifier.notifyError(error.localizedDescription, title: "Not saved")
            return false
        }
        if settings.showNotification {
            notifier.notifySaved(fileURL: url, title: "Saved")
        }
        return true
    }
```
The doc comment of `editorSaveAs` (lines 1264-1269) stays; the `saveAsWritesOverOwnFile` branch (lines 1271-1277) stays as it is.

- [ ] **Step 4: The card's Save As…**

`TidyShot/App/AppCoordinator.swift`, after `copyImage(recordID:)` (after line 606), add:
```swift
    /// Save As… from a Quick Access card (and from a pin's menu, 6b): runs `saveCopy` after any
    /// menu tracking (`afterMenuTracking`, Task 4).
    func saveAs(recordID: UUID) {
        afterMenuTracking { [weak self] in
            Task { await self?.saveCopy(recordID: recordID) }
        }
    }

    /// Activates the app, asks for a place with the editor's suggestion, then writes the capture's
    /// PNG there unchanged (`imageData(of:)`: the local file, or a signed GET). A copy only: the
    /// record, its link, `lastCaptureURL` and the clipboard stay as they are.
    private func saveCopy(recordID: UUID) async {
        guard history.record(id: recordID) != nil else { return }
        let panel = EditorNaming.savePanel(for: saveAsSuggestion(recordID: recordID))
        // Reached from a non-activating card while another app is active; a plain activate() can
        // be refused and the panel would open behind that app (as in SaveLocation.chooseFolder).
        NSApplication.shared.activate(ignoringOtherApps: true)
        guard await panel.begin() == .OK, let url = panel.url else { return }
        // Read again: the upload may have finished, or the capture been deleted, while the panel was open.
        guard let record = history.record(id: recordID) else {
            NSLog("Save As: \(recordID) was deleted while the panel was open")
            return
        }
        let png: Data
        do {
            png = try await imageData(of: record, downloadTitle: "Saving a copy…")
        } catch {
            notifier.notifyError(error.localizedDescription, title: "Not saved")
            return
        }
        await writeSaveAsCopy(png, to: url)
    }
```
Doc of `imageData(of:downloadTitle:)` (lines 608-611): add `Copy Image, Annotate and the card's Save As… use it.`

- [ ] **Step 5: Actions and wiring**

`TidyShot/Overlay/QuickAccessController.swift`, `Actions` (after `annotate`, line 14 on `main`):
```swift
        /// Save As… for the card's button and menu item; see `AppCoordinator.saveAs(recordID:)`.
        var saveAs: (UUID) -> Void
        /// Copy Image for the card's menu item; see `AppCoordinator.copyImage(recordID:)`.
        var copyImage: (UUID) -> Void
```
In Task 3's `makeCard`, next to `model.onAnnotate = { actions.annotate(id) }`, add
```swift
        model.onSaveAs = { actions.saveAs(id) }
        model.onCopyImage = { actions.copyImage(id) }
```
(`id` is the card's record id, as the other callbacks use it.)

`TidyShot/App/AppCoordinator.swift`, the `Actions(...)` in Task 3's `overlayActions()`, after `annotate:`:
```swift
            saveAs: { [weak self] id in self?.saveAs(recordID: id) },
            copyImage: { [weak self] id in Task { await self?.copyImage(recordID: id) } }
```
A restored card gets the same actions through `overlayActions()`.

- [ ] **Step 6: Run the suite**

Run the header's full-suite command. Expected: no `error:` lines, and `Test run with 645 tests in 82 suites passed`. This task adds 2 tests (`uploadOnlyCaptureWithoutAKeySuggestsTheTemplateName`, `uploadedCaptureWithAKeySuggestsTheTemplateOrItsOwnName`) and no suite.

- [ ] **Step 7: Hand checks (Tim)**

For Tim; the implementer lists these in its report and goes on to Step 8. Task 8's checklist repeats them. Build Release (`-configuration Release -derivedDataPath .build-rel`) and run it; keep another app (Safari) frontmost while you click the card.
- Save mode: take an area capture, click the card's `Save As…`. TidyShot comes forward with a save panel (a window, not attached to the card), PNG only, named as the saved file, in the save folder. Save to the Desktop: `cmp` of the copy and the original reports no difference; `Saved` with the copy's name appears, and a click on it reveals the copy. Recent Captures still points at the original, Reveal Last Capture reveals the original, and the clipboard still holds what the capture put there.
- Same capture, `Save As…` from the right-click menu: same panel. Cancel: nothing is written, no notification. Pick the original file and confirm Replace: the file is unchanged byte for byte.
- Upload-only mode (Tim's): `Save As…` while `Uploading…` shows: the template's name (not `<uuid>.png`), the panel where it last was; the copy equals the pending file (`cmp` against `~/Library/Containers/io.tky.tidyshot/Data/Library/Application Support/TidyShot/pending/<id>.png` before the upload ends). After the upload: `Save As…` posts `Saving a copy…` / `Downloading <key>`, then `Saved` (from Task 6 on, a card that showed through the upload reads its kept drag copy instead, with no download); the copy equals `curl -s <url> | cmp - <copy>`.
- A failed upload (`Retry  Save As…` row): `Save As…` writes the pending file.
- With notifications off in General: no `Saved`, the file is written.
- Right-click > `Copy Image`: paste into Preview (File > New from Clipboard): it pastes at point size; `Image copied` is posted; the card stays. In upload-only mode after the upload, `Copying image…` / `Downloading <key>` first.
- Editor regression: Annotate a capture, draw an arrow, ⇧⌘S: the sheet suggests the same name as before, the edited copy is written, `Saved` appears, and with the capture's image still on the clipboard the clipboard now holds the edit.
- Activation: after the panel closes, clicking back into Safari works as usual; a second card's buttons still work without activating TidyShot.

- [ ] **Step 8: Commit**

```bash
git add TidyShot/App/AppCoordinator.swift TidyShot/Overlay/QuickAccessController.swift TidyShot/Editor/Persistence/EditorNaming.swift TidyShot/Editor/Window/EditorWindowController.swift TidyShotTests/EditorNamingTests.swift
git commit -m "feat: Save As… and Copy Image from the Quick Access card"
```

### Task 6: Drag-out

**Files:**
- Create: `TidyShot/Output/DragFileStore.swift` (`DragFileStore`, nonisolated, Sendable)
- Create: `TidyShot/Overlay/DragFileName.swift` (`DragFileName`, pure)
- Create: `TidyShot/Overlay/QuickAccessCardDragSource.swift` (`QuickAccessCardDragSource`, an `NSViewRepresentable`, and `QuickAccessCardDragView`, an `NSView` that is the `NSDraggingSource`)
- Modify: `TidyShot/Overlay/QuickAccessModel.swift` (properties, lines 9-16 on `main`)
- Modify: `TidyShot/Overlay/QuickAccessController.swift` (`Actions`, after Task 5's `copyImage`; Task 3's `makeCard` and `scheduleClose`, as Tasks 4 and 5 left them; new `setDragFile(_:for:)`)
- Modify: `TidyShot/Overlay/QuickAccessView.swift` (as Task 4 left it: the card root modifiers of `body`; `thumbnail`; the uploaded URL text in `status`; the status column's labels and texts)
- Modify: `TidyShot/App/AppCoordinator.swift` (stored properties, after line 25 and after line 64; `init`, lines 81-82; `start()`, line 88; `overlayActions()` (Task 3, as Tasks 4 and 5 left it); `overlayDidClose(_:reason:)` and `restoreClosedOverlay()` (Task 4); `imageData(of:downloadTitle:)`, lines 608-630; `downloadImage(of:title:)`, lines 632-642; `removeRecord(id:)`, lines 785-800; `handle(_:at:)` `.uploaded`, lines 915-920; new `// MARK: Drag-out` section before `// MARK: Editor`, line 998. Line numbers are `main`'s; Tasks 1 to 5 add lines above most of them, so find each by its name.)
- Modify: `TidyShot/Settings/AppSettings.swift` (`Keys`, after line 50; properties, after line 78; `register`, after line 114; `init`, after line 137)
- Modify: `TidyShot/Settings/OverlaySettingsView.swift` (before `Keep history…`, line 21 on `main`)
- Create: `TidyShotTests/DragFileStoreTests.swift` (struct `DragFileStoreTests`), `TidyShotTests/DragFileNameTests.swift` (struct `DragFileNameTests`)
- Test: `TidyShotTests/AppSettingsTests.swift` (one test at the end of the struct); the rest of the suite stays as it is and must stay green.

**Interfaces:**
- Consumes:
  - `main`: `CaptureRecord` (`uploadedKey`, `priorUpload`, `fileURL`, `fileIsTemporary`, `objectLocation`, `hasLocalFile`), `PriorUpload`, `ObjectLocation`, `EditorNaming.SaveAsSuggestion`, `PendingFileStore.remove(_:)`, `AppCoordinator.removePendingFile(at:context:failureTitle:)` (`:806`), `loadCredentials()`, `S3Destination.download(key:)`, `SaveLocation.readScoped(_:folder:)`, `settings.showNotification`.
  - Task 3: `QuickAccessController`'s card list `cards: [Card]` (one `QuickAccessModel` per card, newest first; `Card.id` is the record id), `makeCard(record:thumbnail:autoCloseSeconds:actions:)` with the per-card wiring from `Actions`, the per-card countdown `scheduleClose(_:)` that skips a round while `model.isHovered`, `isShowing(recordID: UUID) -> Bool`; `QuickAccessPanel.isMovableByWindowBackground = false`; the Overlay tab's `Show up to N overlays` stepper; `AppCoordinator.overlayActions()`.
  - Task 4: `QuickAccessCloseReason` (`.user`, `.autoClose`, `.pushedOut`, `.draggedOut`, `.deleted`, `.editorOpened`); `QuickAccessController.close(recordID: UUID, reason: QuickAccessCloseReason)`; `onDidClose: ((UUID, QuickAccessCloseReason) -> Void)?`, set in `AppCoordinator.init` to `overlayDidClose(_:reason:)`, which pushes restorable ids onto `ClosedOverlays`; `AppCoordinator.restoreClosedOverlay()`; `QuickAccessModel.canReveal`; the card layout (`body` with `buttonRow`, the hover Close badge and the context menu).
  - Task 5: `AppCoordinator.saveAsSuggestion(recordID:) -> EditorNaming.SaveAsSuggestion`; `QuickAccessController.Actions.saveAs` and `.copyImage`.
- Produces:
  - `DragFileStore` (`Output/DragFileStore.swift`): `static let directoryName = "Drag"`, `let directory: URL`, `init(directory: URL)`, `init(temporaryDirectory: URL)`, `func folder(for id: UUID) -> URL`, `func stagedFile(id: UUID) -> URL?`, `@discardableResult func stage(id: UUID, name: String, from source: URL, scope: URL?) throws -> URL`, `@discardableResult func adopt(id: UUID, name: String, moving source: URL) throws -> URL`, `@discardableResult func write(_ data: Data, id: UUID, name: String) throws -> URL`, `func remove(id: UUID)`, `func sweep()`.
  - `DragFileName.name(for record: CaptureRecord, suggestion: EditorNaming.SaveAsSuggestion) -> String` (pure, nonisolated).
  - `QuickAccessModel.dragFileURL: URL?`, `isDraggingOut: Bool`, `onPrepareDrag: () -> Void`, `onDragEnded: (Bool) -> Void` (all `@ObservationIgnored`).
  - `QuickAccessController.Actions.prepareDrag: (UUID) -> Void`, `.dragEnded: (UUID, Bool) -> Void`; `QuickAccessController.setDragFile(_ url: URL?, for recordID: UUID)`.
  - `AppCoordinator.dragFiles: DragFileStore`, `prepareDragFile(recordID:)`, `static let dragCleanupDelay: Duration` (60 s).
  - `AppSettings.overlayCloseAfterDrag: Bool` (key `overlayCloseAfterDrag`, default true); Overlay tab toggle `Close after dragging out`.
  - `imageData(of:downloadTitle:)` reads the drag copy between the local file and the signed GET (Task 12's `loadImage(for:)` and every caller get it). `downloadImage(of:title:)` takes `title: String?`; nil downloads quietly.

**Where the files live (sandbox).** Under the App Sandbox `FileManager.default.temporaryDirectory` is the container's `tmp`, so a card's drag file is `~/Library/Containers/io.tky.tidyshot/Data/tmp/Drag/<record UUID>/<name>.png` (Debug and Release share the container: same bundle id). One file per record folder; a folder per record keeps two cards with the same name apart and lets the receiver see the real name. The app writes only inside its own container, so no entitlement is added. `history.json`, `pending/` and `thumbnails/` live in `…/Data/Library/Application Support/TidyShot/`, on the same volume as `tmp`, so `adopt` is a rename and a stage from `pending` is an APFS clone.

**Naming.** `DragFileName.name(for:suggestion:)`: the last path component of the key behind the record's link (`uploadedKey`, or `priorUpload.key` while the editor uploads over a link; the clipboard holds that link), so a key `shots/2026/aSIS7.png` gives `aSIS7.png`. A key name gets `:` replaced by `-`, a leading `.` by `_`, and `.png` appended when it does not end in `.png` (any case). A key ending in `/`, or no key, gives the Save As suggestion's file name (`saveAsSuggestion(recordID:)`): the save-folder file's own name, otherwise the file name template's name with the current `{counter}`.

**Lifetime.**
- *Stage.* At mouse-down on a card (and when a restored card appears) the coordinator works out the name and the source on the main actor and runs `stage` in a detached task: a save-folder file is copied with `FileManager.copyItem` inside the save folder's security scope (an APFS clone when the save folder is on the container's volume, a full copy when it is not); a `pending` file is cloned with no scope; a record with no local file uses the file already in its folder (adopted or downloaded). The card's `dragFileURL` is nil until the stage is done; a drag that passes the threshold before that waits for the next mouse-dragged event, so the drag starts as soon as the file exists. Each stage replaces what the folder held.
- *Upload-only, kept while a card shows.* On `.uploaded` for a record whose file is temporary, if a card shows that record the pending file is moved (`adopt`) to `Drag/<id>/<key name>` instead of being deleted, and the card gets that URL. The record changes exactly as before: `fileURL = nil`, `fileIsTemporary = false`, the link on the clipboard. Delete, retention, Recent Captures and Retry see no file, as today. With no card showing, or when the move fails (logged), the pending file is removed as before.
- *From the bucket.* A restored card whose record has no local file and no kept copy starts a quiet signed GET (no notification) into its folder when it appears; until it lands, dragging the card does nothing. A failure is logged only.
- *Clean-up.* Every card close (any reason) schedules the record's folder for removal after 60 s, so a receiver that copies after the drop (Slack, Chrome uploads) can still read it; showing the card again (restore) cancels that. Delete removes the folder at once. `start()` removes the whole `Drag` folder before anything else, which also clears what a crash or quit left. A stage or download that finishes after its folder was removed (a generation counter per record says so) deletes what it recreated, unless a card shows the record again.
- *Reads.* `imageData(of:)` reads the record's local file, then the kept drag copy, then the bucket, so Copy Image, Save As… and Annotate on an upload-only card after its upload need no download while the card's copy exists.

The copy starting at mouse-down rather than at drag start, and the session starting once the file exists, go beyond 2.9's "made at drag start" (header, point 2); Task 8 writes it into 2.9.

**The drag.** `QuickAccessCardDragView` (an `NSView`, `NSDraggingSource`) lies in the card's background and over the thumbnail; every SwiftUI view on the card that is not a button has `.allowsHitTesting(false)`, so a press anywhere except a button reaches it. A press stages the file; a move of 3 pt starts `beginDraggingSession(with:event:source:)` with one `NSDraggingItem` whose pasteboard writer is the staged file URL as `NSURL` (NSURL writes `public.file-url` and its legacy companions; no image data, no promise) and whose image is the card's thumbnail fitted in 96 x 72 pt under the pointer. `sourceOperationMaskFor` returns `.copy` outside the app and `[]` inside it; modifier keys are ignored. A press and release without a drag on the thumbnail reveals a local file, as the thumbnail's click did. When the session ends with an operation other than none, and `Close after dragging out` is on, the card closes as `.draggedOut` (restorable). While a drag runs the card's auto-close does not count down.

**Fallback if a receiver refuses the file URL.** Not built in 6a (header, point 6). Step 9 writes it out as a follow-up, built only if Tim's receiver checks (Step 8, Task 8's checklist) show a receiver refusing the file URL: `QuickAccessFilePromise`, an `NSFilePromiseProvider` subclass that also writes `public.file-url` for the same staged file (Apple's file-promise sample pattern), replaces the `NSURL` writer. Receivers that take promises (Finder, Mail, Photos) get a copy written into the folder they pick; the rest read the file URL as before. Nothing else changes.

- [ ] **Step 1: Write the failing tests**

`TidyShotTests/DragFileNameTests.swift` (new):
```swift
import Foundation
import Testing
@testable import TidyShot

struct DragFileNameTests {
    let suggestion = EditorNaming.SaveAsSuggestion(fileName: "Screenshot 2026-10-21 at 09.15.02.png", directory: nil)
    let location = ObjectLocation(endpoint: "https://s3.us-west-2.amazonaws.com", region: "us-west-2", bucket: "snap",
                                  usePathStyle: false)

    func record(file: URL? = nil, temporary: Bool = false, state: CaptureRecord.UploadState = .none,
                prior: PriorUpload? = nil) -> CaptureRecord {
        CaptureRecord(fileURL: file, fileIsTemporary: temporary, pixelWidth: 64, pixelHeight: 48, appName: nil,
                      uploadState: state, priorUpload: prior)
    }

    func uploaded(_ key: String) -> CaptureRecord.UploadState {
        .uploaded(url: URL(string: "https://snap.example.com/\(key)")!, key: key)
    }

    /// The key's name, so the dropped file matches the link on the clipboard: for an uploaded
    /// upload-only capture (no file) and for a save-folder file that was uploaded too.
    @Test func uploadedKeyNamesTheFile() {
        #expect(DragFileName.name(for: record(state: uploaded("aSIS7.png")), suggestion: suggestion) == "aSIS7.png")
        let saved = record(file: URL(fileURLWithPath: "/Users/tim/Pictures/TidyShot/Bug 12.png"), state: uploaded("aSIS7.png"))
        let own = EditorNaming.SaveAsSuggestion(fileName: "Bug 12.png", directory: nil)
        #expect(DragFileName.name(for: saved, suggestion: own) == "aSIS7.png")
    }

    @Test func nestedKeyGivesItsLastComponent() {
        #expect(DragFileName.name(for: record(state: uploaded("shots/2026/x.png")), suggestion: suggestion) == "x.png")
    }

    /// No key: the Save As suggestion, which is the save-folder file's own name or the template's
    /// name (never a pending `<id>.png`).
    @Test func withoutAKeyTheSaveAsSuggestionNamesTheFile() {
        let own = EditorNaming.SaveAsSuggestion(fileName: "Bug 12.png", directory: nil)
        #expect(DragFileName.name(for: record(file: URL(fileURLWithPath: "/Users/tim/Pictures/TidyShot/Bug 12.png")),
                                  suggestion: own) == "Bug 12.png")
        let pending = URL(fileURLWithPath: "/tmp/pending/\(UUID().uuidString).png")
        for state in [.uploading(fraction: 0.5), .failed(message: "Upload failed."), .none] as [CaptureRecord.UploadState] {
            #expect(DragFileName.name(for: record(file: pending, temporary: true, state: state), suggestion: suggestion)
                    == "Screenshot 2026-10-21 at 09.15.02.png")
        }
    }

    /// While the editor uploads over a link, the clipboard still holds that link: its key names the file.
    @Test func anUploadOverALinkUsesThePriorKey() {
        let prior = PriorUpload(url: URL(string: "https://snap.example.com/p/aSIS7.png")!, key: "p/aSIS7.png",
                                location: location, isReplace: true)
        #expect(DragFileName.name(for: record(state: .uploading(fraction: 0.2), prior: prior), suggestion: suggestion)
                == "aSIS7.png")
    }

    /// A key's name is made safe for a file: `.png` added when missing, `:` and a leading dot
    /// replaced. A key ending in `/` has no name, so the suggestion is used.
    @Test func keyNamesAreMadeSafeForAFile() {
        #expect(DragFileName.name(for: record(state: uploaded("p/aSIS7")), suggestion: suggestion) == "aSIS7.png")
        #expect(DragFileName.name(for: record(state: uploaded("p/.hidden.png")), suggestion: suggestion) == "_hidden.png")
        #expect(DragFileName.name(for: record(state: uploaded("p/a:b.PNG")), suggestion: suggestion) == "a-b.PNG")
        #expect(DragFileName.name(for: record(state: uploaded("shots/")), suggestion: suggestion) == suggestion.fileName)
    }
}
```

`TidyShotTests/DragFileStoreTests.swift` (new):
```swift
import Foundation
import Testing
@testable import TidyShot

struct DragFileStoreTests {
    let root: URL
    let store: DragFileStore

    init() {
        root = FileManager.default.temporaryDirectory
            .appending(path: "DragFileStoreTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        store = DragFileStore(temporaryDirectory: root)
    }

    /// A file outside the drag folder, standing in for a save-folder or `pending` file.
    func source(_ name: String, _ bytes: [UInt8]) throws -> URL {
        let folder = root.appending(path: "pending", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appending(path: name)
        try Data(bytes).write(to: url)
        return url
    }

    func exists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path(percentEncoded: false))
    }

    /// The names in `id`'s folder, sorted.
    func names(_ id: UUID) -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: store.folder(for: id).path(percentEncoded: false))) ?? []).sorted()
    }

    /// `<tmp>/Drag/<id>/<name>`, a copy with the source's bytes; the source stays.
    @Test func stageCopiesTheSourceIntoTheRecordsFolder() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let id = UUID()
        let original = try source("\(id.uuidString).png", [1, 2, 3])
        let staged = try store.stage(id: id, name: "aSIS7.png", from: original, scope: nil)
        #expect(store.directory.lastPathComponent == DragFileStore.directoryName)
        #expect(staged.lastPathComponent == "aSIS7.png")
        #expect(staged.deletingLastPathComponent().lastPathComponent == id.uuidString)
        #expect(staged.deletingLastPathComponent().deletingLastPathComponent().lastPathComponent == "Drag")
        #expect(try Data(contentsOf: staged) == Data([1, 2, 3]))
        #expect(exists(original))
        #expect(store.stagedFile(id: id)?.lastPathComponent == "aSIS7.png")
    }

    /// A later stage replaces the earlier file, under a new name or the same one.
    @Test func aSecondStageReplacesTheFirst() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let id = UUID()
        try store.stage(id: id, name: "Screenshot 2026-10-21 at 09.15.02.png", from: try source("a.png", [1]), scope: nil)
        let second = try store.stage(id: id, name: "aSIS7.png", from: try source("b.png", [2]), scope: nil)
        #expect(names(id) == ["aSIS7.png"])
        #expect(try Data(contentsOf: second) == Data([2]))
        let third = try store.stage(id: id, name: "aSIS7.png", from: try source("c.png", [3]), scope: nil)
        #expect(names(id) == ["aSIS7.png"])
        #expect(try Data(contentsOf: third) == Data([3]))
    }

    /// Staging the staged file as itself keeps it.
    @Test func stagingTheStagedFileItselfKeepsIt() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let id = UUID()
        let staged = try store.stage(id: id, name: "aSIS7.png", from: try source("a.png", [1]), scope: nil)
        let again = try store.stage(id: id, name: "aSIS7.png", from: staged, scope: nil)
        #expect(again.lastPathComponent == "aSIS7.png")
        #expect(names(id) == ["aSIS7.png"])
        #expect(try Data(contentsOf: again) == Data([1]))
    }

    /// A source that is gone throws and leaves the earlier file in place.
    @Test func stagingAMissingSourceThrowsAndKeepsTheStagedFile() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let id = UUID()
        try store.stage(id: id, name: "aSIS7.png", from: try source("a.png", [1]), scope: nil)
        let gone = root.appending(path: "pending/gone.png")
        #expect(throws: (any Error).self) { try store.stage(id: id, name: "other.png", from: gone, scope: nil) }
        #expect(names(id) == ["aSIS7.png"])
    }

    /// The pending file moves (it is gone afterwards) and replaces the earlier clone.
    @Test func adoptMovesThePendingFile() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let id = UUID()
        try store.stage(id: id, name: "Screenshot 2026-10-21 at 09.15.02.png", from: try source("clone.png", [1]), scope: nil)
        let pending = try source("\(id.uuidString).png", [9, 9])
        let adopted = try store.adopt(id: id, name: "aSIS7.png", moving: pending)
        #expect(!exists(pending))
        #expect(names(id) == ["aSIS7.png"])
        #expect(try Data(contentsOf: adopted) == Data([9, 9]))
        #expect(throws: (any Error).self) { try store.adopt(id: id, name: "x.png", moving: pending) }
        #expect(names(id) == ["aSIS7.png"])
    }

    /// A restored card's download lands in its folder like a stage.
    @Test func writePutsDownloadedBytesInTheFolder() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let id = UUID()
        let url = try store.write(Data([4, 5]), id: id, name: "aSIS7.png")
        #expect(names(id) == ["aSIS7.png"])
        #expect(try Data(contentsOf: url) == Data([4, 5]))
        #expect(store.stagedFile(id: id)?.lastPathComponent == "aSIS7.png")
    }

    /// One record's folder goes; another's stays; removing it again is no error.
    @Test func removeDeletesOneRecordsFolder() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let kept = UUID()
        let removed = UUID()
        try store.write(Data([1]), id: kept, name: "a.png")
        try store.write(Data([2]), id: removed, name: "b.png")
        store.remove(id: removed)
        #expect(!exists(store.folder(for: removed)))
        #expect(store.stagedFile(id: removed) == nil)
        #expect(names(kept) == ["a.png"])
        store.remove(id: removed)
    }

    /// The launch sweep removes `Drag` and everything in it; a second sweep is no error.
    @Test func sweepRemovesTheWholeDragFolder() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        try store.write(Data([1]), id: UUID(), name: "a.png")
        try store.write(Data([2]), id: UUID(), name: "b.png")
        store.sweep()
        #expect(!exists(store.directory))
        store.sweep()
    }
}
```

`TidyShotTests/AppSettingsTests.swift`, at the end of the struct:
```swift
    /// Close after dragging out is on by default and persists (spec 2.9).
    @Test func overlayCloseAfterDragDefaultsOnAndPersists() {
        let defaults = freshDefaults()
        let first = AppSettings(defaults: defaults)
        #expect(first.overlayCloseAfterDrag)
        first.overlayCloseAfterDrag = false
        #expect(defaults.object(forKey: "overlayCloseAfterDrag") as? Bool == false)
        #expect(!AppSettings(defaults: defaults).overlayCloseAfterDrag)
    }
```

- [ ] **Step 2: Run the tests and see them fail**

Run the header's full-suite command. Expected: the build fails with `cannot find 'DragFileName' in scope` in `DragFileNameTests.swift`, `cannot find type 'DragFileStore' in scope` in `DragFileStoreTests.swift`, and `value of type 'AppSettings' has no member 'overlayCloseAfterDrag'` in `AppSettingsTests.swift`.

- [ ] **Step 3: DragFileName, DragFileStore and the setting**

`TidyShot/Overlay/DragFileName.swift`:
```swift
import Foundation

/// The name of a Quick Access card's drag file (spec 2.9, Drag-out).
nonisolated enum DragFileName {
    /// The last path component of the key behind the record's link (`uploadedKey`, or
    /// `priorUpload.key` while the editor uploads over a link), so the dropped file matches the
    /// link on the clipboard; `:` becomes `-`, a leading `.` becomes `_`, and `.png` is added when
    /// the name does not end in it. Without a key, or for a key ending in `/`, the Save As
    /// suggestion's file name.
    static func name(for record: CaptureRecord, suggestion: EditorNaming.SaveAsSuggestion) -> String {
        guard let key = record.uploadedKey ?? record.priorUpload?.key,
              let last = key.split(separator: "/", omittingEmptySubsequences: false).last, !last.isEmpty else {
            return suggestion.fileName
        }
        var name = last.replacingOccurrences(of: ":", with: "-")
        if name.hasPrefix(".") {
            name = "_" + name.dropFirst()
        }
        if !name.lowercased().hasSuffix(".png") {
            name += ".png"
        }
        return name
    }
}
```

`TidyShot/Output/DragFileStore.swift`:
```swift
import Foundation

/// The `Drag` folder in the container's temporary directory: one folder per record, holding the
/// one file a Quick Access card hands out when it is dragged (spec 2.9). Never the user's save
/// folder: a save-folder file is copied in here, an upload-only capture's pending file is moved
/// in here after its upload, and a restored card's download is written here. Under the App
/// Sandbox the folder is `~/Library/Containers/io.tky.tidyshot/Data/tmp/Drag`. Every method
/// touches only the file system, so stages run in detached tasks.
nonisolated struct DragFileStore: Sendable {
    static let directoryName = "Drag"

    let directory: URL

    init(directory: URL) {
        self.directory = directory
    }

    /// `Drag` in `temporaryDirectory` (`FileManager.default.temporaryDirectory`, the container's `tmp`).
    init(temporaryDirectory: URL) {
        self.init(directory: temporaryDirectory.appending(path: Self.directoryName, directoryHint: .isDirectory))
    }

    /// `Drag/<id>`.
    func folder(for id: UUID) -> URL {
        directory.appending(path: id.uuidString, directoryHint: .isDirectory)
    }

    /// The file in `id`'s folder, or nil. A folder holds one file, except for a moment while two
    /// operations on it overlap; then the first by name.
    func stagedFile(id: UUID) -> URL? {
        Self.entries(in: folder(for: id)).min { $0.lastPathComponent < $1.lastPathComponent }
    }

    /// Copies `source` to `Drag/<id>/<name>` and returns it, replacing what the folder held.
    /// `FileManager.copyItem` clones on APFS when source and folder share a volume (`pending`
    /// always does; a save folder on the startup disk does), and copies the bytes otherwise.
    /// `scope` (the save folder) is held for the copy; nil for a file in the container. Staging
    /// the staged file as itself returns it. Throws, leaving the folder as it was, when `source`
    /// does not exist or cannot be read.
    @discardableResult
    func stage(id: UUID, name: String, from source: URL, scope: URL?) throws -> URL {
        let fileManager = FileManager.default
        let destination = folder(for: id).appending(path: name)
        let accessing = scope?.startAccessingSecurityScopedResource() ?? false
        defer { if accessing { scope?.stopAccessingSecurityScopedResource() } }
        guard fileManager.fileExists(atPath: source.path(percentEncoded: false)) else {
            throw CocoaError(.fileNoSuchFile)
        }
        if source.standardizedFileURL.path(percentEncoded: false) == destination.standardizedFileURL.path(percentEncoded: false) {
            return destination
        }
        return try place(destination) { try fileManager.copyItem(at: source, to: $0) }
    }

    /// Moves an upload-only capture's pending file to `Drag/<id>/<name>` (a rename: `pending` and
    /// `tmp` are both in the container) and returns it, replacing what the folder held. Throws,
    /// leaving the folder as it was, when `source` is gone.
    @discardableResult
    func adopt(id: UUID, name: String, moving source: URL) throws -> URL {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: source.path(percentEncoded: false)) else {
            throw CocoaError(.fileNoSuchFile)
        }
        return try place(folder(for: id).appending(path: name)) { try fileManager.moveItem(at: source, to: $0) }
    }

    /// Writes downloaded bytes (a restored card's prefetch) as `Drag/<id>/<name>`, replacing what
    /// the folder held.
    @discardableResult
    func write(_ data: Data, id: UUID, name: String) throws -> URL {
        try place(folder(for: id).appending(path: name)) { try data.write(to: $0, options: .atomic) }
    }

    /// Removes `id`'s folder. One that is already gone is not an error; another failure is logged,
    /// and the launch sweep gets the folder later.
    func remove(id: UUID) {
        Self.removeLogged(folder(for: id))
    }

    /// Removes `Drag` and everything in it. Run at launch, before any card exists.
    func sweep() {
        Self.removeLogged(directory)
    }

    /// Puts a file at `destination` with `put`, then removes what the folder held before. The
    /// folder is listed before `put` runs, so two operations that overlap (a stage from a
    /// mouse-down and an adopt from a finished upload) never remove each other's new file.
    private func place(_ destination: URL, _ put: (URL) throws -> Void) throws -> URL {
        let fileManager = FileManager.default
        let folder = destination.deletingLastPathComponent()
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        let earlier = Self.entries(in: folder).filter { $0.lastPathComponent != destination.lastPathComponent }
        if fileManager.fileExists(atPath: destination.path(percentEncoded: false)) {
            try fileManager.removeItem(at: destination)
        }
        try put(destination)
        for entry in earlier {
            try? fileManager.removeItem(at: entry)
        }
        return destination
    }

    private static func entries(in folder: URL) -> [URL] {
        (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
    }

    private static func removeLogged(_ url: URL) {
        do {
            try FileManager.default.removeItem(at: url)
        } catch let error as CocoaError where error.code == .fileNoSuchFile {
            return
        } catch {
            NSLog("Could not remove \(url.lastPathComponent) from the drag folder: \(error.localizedDescription)")
        }
    }
}
```

`TidyShot/Settings/AppSettings.swift`:
- `Keys`, after `scrollingAutoScroll` (line 50): `static let overlayCloseAfterDrag = "overlayCloseAfterDrag"`.
- Properties, with the other overlay settings (after Task 3's `overlayMaxCards`):
```swift
    /// Close a Quick Access card once it was dragged out and dropped (Overlay tab).
    var overlayCloseAfterDrag: Bool { didSet { defaults.set(overlayCloseAfterDrag, forKey: Keys.overlayCloseAfterDrag) } }
```
- `register`: `Keys.overlayCloseAfterDrag: true,`.
- `init`: `overlayCloseAfterDrag = defaults.bool(forKey: Keys.overlayCloseAfterDrag)`.

Run the header's full-suite command: the new tests pass; the app builds.

- [ ] **Step 4: Model, controller and settings view**

`TidyShot/Overlay/QuickAccessModel.swift`, after `isHovered` (line 9 on `main`):
```swift
    /// The card's staged drag file (`DragFileStore`), or nil while none is ready; set by
    /// `QuickAccessController.setDragFile(_:for:)`. Read by the drag view, not drawn.
    @ObservationIgnored var dragFileURL: URL?
    /// True while a drag-out session from this card runs; the auto-close countdown waits meanwhile.
    @ObservationIgnored var isDraggingOut = false
```
and with the other callbacks:
```swift
    /// A press on the card's drag surface: stage the drag file now.
    @ObservationIgnored var onPrepareDrag: () -> Void = {}
    /// A drag-out session ended; true when a receiver took the file.
    @ObservationIgnored var onDragEnded: (Bool) -> Void = { _ in }
```

`TidyShot/Overlay/QuickAccessController.swift`:
- `Actions`, after Task 5's `copyImage`:
```swift
        /// Stages the card's drag file; see `AppCoordinator.prepareDragFile(recordID:)`.
        var prepareDrag: (UUID) -> Void
        /// A drag-out ended; true when a receiver took the file.
        var dragEnded: (UUID, Bool) -> Void
```
- Task 3's `makeCard`, next to Task 5's `model.onSaveAs`:
```swift
        model.onPrepareDrag = { actions.prepareDrag(id) }
        model.onDragEnded = { accepted in actions.dragEnded(id, accepted) }
```
- Task 3's `scheduleClose(_:)`: the round is skipped while the card is hovered or dragged out. A card must not close under a running drag session:
```swift
                if card?.model.isHovered == true || card?.model.isDraggingOut == true { continue }
```
  (was `if card?.model.isHovered == true { continue }`).
- New method, after `update(record:)`:
```swift
    /// Hands the card showing `recordID` its staged drag file, or nil while one is being made.
    /// Does nothing when no card shows the record.
    func setDragFile(_ url: URL?, for recordID: UUID) {
        cards.first { $0.id == recordID }?.model.dragFileURL = url
    }
```

`TidyShot/Settings/OverlaySettingsView.swift`, after Task 3's `Show up to N overlays` stepper and before `Keep history for …` (line 21 on `main`):
```swift
            Toggle("Close after dragging out", isOn: $settings.overlayCloseAfterDrag)
                .disabled(!settings.showOverlay)
```

- [ ] **Step 5: The drag view and the card**

`TidyShot/Overlay/QuickAccessCardDragSource.swift`:
```swift
import AppKit
import SwiftUI

/// Wraps `QuickAccessCardDragView` for SwiftUI. The card puts one in its background (a press
/// does nothing but drag) and one over its thumbnail (a click reveals a local file).
struct QuickAccessCardDragSource: NSViewRepresentable {
    let model: QuickAccessModel
    /// A press and release without a drag. Nil: nothing.
    var onClick: (() -> Void)? = nil
    var toolTip: String? = nil

    func makeNSView(context: Context) -> QuickAccessCardDragView {
        let view = QuickAccessCardDragView()
        updateNSView(view, context: context)
        return view
    }

    func updateNSView(_ view: QuickAccessCardDragView, context: Context) {
        view.model = model
        view.onClick = onClick
        view.toolTip = toolTip
    }
}

/// The drag-out surface of a Quick Access card (spec 2.9). A press asks for the drag file to be
/// staged; once the pointer has moved `dragThreshold` points and the file exists, a session starts
/// with the file URL. A file that is not staged yet makes the drag wait for the next
/// mouse-dragged event; for a restored card still downloading, the drag does nothing.
final class QuickAccessCardDragView: NSView, NSDraggingSource {
    /// How far the pointer moves, in points, before a press becomes a drag.
    static let dragThreshold: CGFloat = 3
    /// The drag image's box: the card's thumbnail well.
    static let dragImageBox = CGSize(width: 96, height: 72)

    weak var model: QuickAccessModel?
    var onClick: (() -> Void)?
    private var mouseDownEvent: NSEvent?
    private var dragStarted = false

    // The card's panel never becomes key and TidyShot is usually not active.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    override func mouseDown(with event: NSEvent) {
        // Control-click is the context menu (Task 4): leave it to the responder chain.
        if event.modifierFlags.contains(.control) {
            super.mouseDown(with: event)
            return
        }
        mouseDownEvent = event
        dragStarted = false
        model?.onPrepareDrag()
    }

    override func mouseDragged(with event: NSEvent) {
        guard !dragStarted, let down = mouseDownEvent, let model else { return }
        let dx = event.locationInWindow.x - down.locationInWindow.x
        let dy = event.locationInWindow.y - down.locationInWindow.y
        guard dx * dx + dy * dy >= Self.dragThreshold * Self.dragThreshold else { return }
        guard let fileURL = model.dragFileURL else { return }
        dragStarted = true
        model.isDraggingOut = true
        let item = NSDraggingItem(pasteboardWriter: fileURL as NSURL)
        let image = model.thumbnail ?? NSImage(systemSymbolName: "photo", accessibilityDescription: nil) ?? NSImage()
        item.setDraggingFrame(Self.dragFrame(imageSize: image.size, centredOn: convert(down.locationInWindow, from: nil)),
                              contents: image)
        let session = beginDraggingSession(with: [item], event: event, source: self)
        session.animatesToStartingPositionsOnCancelOrFail = true
    }

    override func mouseUp(with event: NSEvent) {
        defer { mouseDownEvent = nil }
        if mouseDownEvent != nil, !dragStarted {
            onClick?()
        }
    }

    /// The image fitted in `dragImageBox` (never enlarged), centred on `point`.
    static func dragFrame(imageSize: CGSize, centredOn point: CGPoint) -> CGRect {
        let fit = imageSize.width > 0 && imageSize.height > 0
            ? min(1, dragImageBox.width / imageSize.width, dragImageBox.height / imageSize.height)
            : 1
        let size = CGSize(width: imageSize.width * fit, height: imageSize.height * fit)
        return CGRect(x: point.x - size.width / 2, y: point.y - size.height / 2, width: size.width, height: size.height)
    }

    // MARK: NSDraggingSource

    /// Copy is the only operation, and only to other apps: nothing in TidyShot takes a drop.
    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        context == .outsideApplication ? .copy : []
    }

    func ignoreModifierKeys(for session: NSDraggingSession) -> Bool { true }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        mouseDownEvent = nil
        dragStarted = false
        model?.isDraggingOut = false
        model?.onDragEnded(operation != [])
    }
}
```

`TidyShot/Overlay/QuickAccessView.swift` (on Task 4's layout):
- Card root, in Task 4's `body`: add `.background(QuickAccessCardDragSource(model: model))` directly before `.background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))`, so the drag view lies over the material and under the content. The other root modifiers Task 4 set (`.overlay(alignment: .topLeading) { closeBadge }`, `.contentShape`, `.contextMenu { menuItems }`, `.onHover`, `.accessibilityAction(named: "Close")`) stay.
- `thumbnail`: drop Task 4's `if model.canReveal { image.onTapGesture { … }.help(…) } else { image }` branch. The thumbnail is always `image` with
```swift
            .allowsHitTesting(false)
            .overlay(QuickAccessCardDragSource(model: model,
                                               onClick: model.canReveal ? { model.onReveal() } : nil,
                                               toolTip: model.canReveal ? "Reveal in Finder" : nil))
```
so a drag starting on the thumbnail drags out, and a click without a drag reveals a save-folder file as Task 4 made it (a pending upload-only file is not revealed). (`.allowsHitTesting(false)` goes on the image group, before the overlay, so the overlay keeps its hits.)
- The uploaded URL `Text` in Task 4's `status` (`main` lines 99-103): drop `.textSelection(.enabled)`; a drag on the link is drag-out, and `Copy URL` copies it.
- Every view on the card that is not a button (the status `Label`s, `Text`s and the `ProgressView`) gets `.allowsHitTesting(false)`, so a press there reaches the background drag view. The buttons in Task 4's `buttonRow` and right column, the hover Close badge and the context menu keep theirs.

- [ ] **Step 6: The coordinator**

`TidyShot/App/AppCoordinator.swift`:
- After `let pendingFiles: PendingFileStore` (line 25):
```swift
    /// Drag-out copies, `<container tmp>/Drag/<id>/` (spec 2.9).
    let dragFiles: DragFileStore
```
  and in `init`, after `pendingFiles = …` (line 82): `dragFiles = DragFileStore(temporaryDirectory: FileManager.default.temporaryDirectory)`.
- After `clipboardOwner` (line 64):
```swift
    /// Bumped when a record's drag folder is removed or its pending file adopted. A stage or
    /// download that started before compares it at its end and drops what it made.
    @ObservationIgnored private var dragGenerations: [UUID: Int] = [:]
    /// Drag folders waiting `dragCleanupDelay` after their card closed.
    @ObservationIgnored private var dragCleanups: [UUID: Task<Void, Never>] = [:]
    /// Restored cards whose drag file is downloading, so a press does not start a second GET.
    @ObservationIgnored private var prefetchingDragIDs: Set<UUID> = []
```
- Task 4's `overlayDidClose(_:reason:)`: add `scheduleDragCleanup(id)` as its last line, for every reason. The `onDidClose` closure in `init` is unchanged.
- `start()`, first line: `dragFiles.sweep()` (with the comment `// Drag copies from the last run, also after a crash.`).
- `overlayActions()` (Task 3's builder), after Task 5's `copyImage:`:
```swift
            prepareDrag: { [weak self] id in self?.prepareDragFile(recordID: id) },
            dragEnded: { [weak self] id, accepted in self?.dragDidEnd(recordID: id, accepted: accepted) }
```
- `restoreClosedOverlay()` (Task 4), right after `overlay.show(…)`: `prepareDragFile(recordID: id)` (with the comment `// A record without a local file starts its quiet download now.`).
- `downloadImage(of:title:)` (lines 632-642): `title: String?`; the notification line becomes
```swift
        if let title, settings.showNotification {
            notifier.notify(title: title, body: "Downloading \(key)")
        }
```
  and its doc gains `A nil title downloads quietly (a restored card's drag file).`
- `imageData(of:downloadTitle:)` (lines 612-630): replace the body with
```swift
        let fileURL = record.fileURL
        let temporary = record.fileIsTemporary
        let folder = temporary ? nil : saveLocation.currentURL
        let drag = dragFiles
        let id = record.id
        let local = await Task.detached(priority: .userInitiated) { () -> Data? in
            if let fileURL {
                let data: Data?
                if temporary {
                    data = try? Data(contentsOf: fileURL)
                } else {
                    data = folder.flatMap { try? SaveLocation.readScoped(fileURL, folder: $0) }
                }
                if let data { return data }
            }
            // The drag copy: an upload-only capture's file kept while its card shows, or a download.
            return drag.stagedFile(id: id).flatMap { try? Data(contentsOf: $0) }
        }.value
        if let local { return local }
        // The record is read again: an upload-only capture whose upload finished during the read
        // has lost its `pending` file and gained the key that the snapshot above lacks.
        let current = history.record(id: record.id) ?? record
        if record.fileURL != nil, current.uploadedKey == nil || current.objectLocation == nil {
            // The file is recorded but cannot be read, and there is no upload to fall back on.
            throw CopyImageError.unreadableFile
        }
        return try await downloadImage(of: current, title: downloadTitle)
```
  and add to its doc: `Between the two, the record's drag copy (DragFileStore), which an upload-only capture keeps while its card shows.`
- `removeRecord(id:)` (lines 789-800), after the `overlay.close(…)` line: `removeDragFolder(id)`.
- `handle(_:at:)`, `.uploaded`: replace lines 915-920 (the comment, `var removedTemporaryFile` and its `if`) with
```swift
            // Upload-only mode: the temporary file has done its job. While a card shows the
            // capture it moves into the drag folder under the key's name, so the card can still be
            // dragged out (spec 2.9); otherwise it is removed. Either way the record drops it
            // below. If it can be neither moved nor removed the record keeps pointing at it, so
            // Delete can still remove it later.
            var removedTemporaryFile = false
            if before.fileIsTemporary, let fileURL = before.fileURL {
                removedTemporaryFile = keepForDragOut(fileURL, record: before, url: url, key: key)
                    || removePendingFile(at: fileURL, context: "after upload")
            }
```
- New section before `// MARK: Editor` (line 998):
```swift
    // MARK: Drag-out

    /// How long a closed card's drag folder stays, for a receiver still reading the dropped file.
    static let dragCleanupDelay: Duration = .seconds(60)

    /// Stages the record's drag file for its card: at a press on the card, and when a restored
    /// card appears. The name and the source are worked out here; the copy runs detached. The
    /// card's `dragFileURL` is nil until it is done. A record with no readable file uses its kept
    /// copy, or, uploaded, a quiet download (`prefetchDragFile`).
    func prepareDragFile(recordID: UUID) {
        guard let record = history.record(id: recordID), overlay.isShowing(recordID: recordID) else { return }
        dragCleanups.removeValue(forKey: recordID)?.cancel()
        let name = DragFileName.name(for: record, suggestion: saveAsSuggestion(recordID: recordID))
        let generation = dragGenerations[recordID, default: 0]
        overlay.setDragFile(nil, for: recordID)
        let store = dragFiles
        let source = record.fileURL
        let scope = record.fileIsTemporary ? nil : saveLocation.currentURL
        Task { [weak self] in
            let staged = await Task.detached(priority: .userInitiated) { () -> URL? in
                if let source, let url = try? store.stage(id: recordID, name: name, from: source, scope: scope) {
                    return url
                }
                // An adopted or downloaded copy, or the last copy of a file that has gone since.
                return store.stagedFile(id: recordID)
            }.value
            guard let self else { return }
            guard self.dragGenerations[recordID, default: 0] == generation else {
                self.dropStaleDragFolder(recordID)
                return
            }
            if let staged {
                self.overlay.setDragFile(staged, for: recordID)
            } else {
                await self.prefetchDragFile(recordID: recordID, name: name)
            }
        }
    }

    /// A quiet signed GET (no notification) of an uploaded capture that has no local file, into
    /// its drag folder. A failure is only logged; the card then cannot be dragged.
    private func prefetchDragFile(recordID: UUID, name: String) async {
        guard !prefetchingDragIDs.contains(recordID), let record = history.record(id: recordID),
              record.uploadedKey != nil, record.objectLocation != nil else { return }
        prefetchingDragIDs.insert(recordID)
        defer { prefetchingDragIDs.remove(recordID) }
        let generation = dragGenerations[recordID, default: 0]
        let store = dragFiles
        do {
            let data = try await downloadImage(of: record, title: nil)
            let url = try await Task.detached(priority: .utility) {
                try store.write(data, id: recordID, name: name)
            }.value
            guard dragGenerations[recordID, default: 0] == generation else {
                dropStaleDragFolder(recordID)
                return
            }
            overlay.setDragFile(url, for: recordID)
        } catch {
            NSLog("Drag-out download for \(recordID) failed: \(error.localizedDescription)")
        }
    }

    /// `.uploaded` for an upload-only capture: when a card shows it, moves the pending file to
    /// `Drag/<id>/<key name>` and hands it to the card. False when no card shows the record or the
    /// move failed (logged); the caller then removes the pending file as before.
    private func keepForDragOut(_ fileURL: URL, record: CaptureRecord, url: URL, key: String) -> Bool {
        guard overlay.isShowing(recordID: record.id) else { return false }
        var uploaded = record
        uploaded.uploadState = .uploaded(url: url, key: key)
        let name = DragFileName.name(for: uploaded, suggestion: saveAsSuggestion(recordID: record.id))
        do {
            let kept = try dragFiles.adopt(id: record.id, name: name, moving: fileURL)
            dragGenerations[record.id, default: 0] += 1
            overlay.setDragFile(kept, for: record.id)
            return true
        } catch {
            NSLog("Could not keep \(fileURL.lastPathComponent) for drag-out: \(error.localizedDescription)")
            return false
        }
    }

    /// A drag-out ended. With `Close after dragging out` on, a drop that a receiver took closes the
    /// card as `.draggedOut` (restorable).
    private func dragDidEnd(recordID: UUID, accepted: Bool) {
        guard accepted, settings.overlayCloseAfterDrag else { return }
        overlay.close(recordID: recordID, reason: .draggedOut)
    }

    /// A card closed, for any reason: its drag folder goes after `dragCleanupDelay`, unless the
    /// card shows again first (`prepareDragFile` cancels this).
    private func scheduleDragCleanup(_ id: UUID) {
        dragCleanups[id]?.cancel()
        dragCleanups[id] = Task { [weak self] in
            try? await Task.sleep(for: Self.dragCleanupDelay)
            guard !Task.isCancelled, let self else { return }
            self.dragCleanups[id] = nil
            guard !self.overlay.isShowing(recordID: id) else { return }
            self.removeDragFolder(id)
        }
    }

    /// Removes the record's drag folder now (Delete, or the delayed clean-up), and makes any stage
    /// or download still running for it drop what it makes.
    private func removeDragFolder(_ id: UUID) {
        dragCleanups.removeValue(forKey: id)?.cancel()
        dragGenerations[id, default: 0] += 1
        dragFiles.remove(id: id)
    }

    /// A stage or download finished after its folder was removed or replaced: unless a card shows
    /// the record, the folder it recreated goes again.
    private func dropStaleDragFolder(_ id: UUID) {
        guard !overlay.isShowing(recordID: id) else { return }
        dragFiles.remove(id: id)
    }
```
Notes for the implementer:
- `removeDragFolder` and `dropStaleDragFolder` delete one small folder on the main actor; the copy, the download and its write run detached or async, as 2.6's concurrency rule asks.
- A stage from a mouse-down and an adopt from a finished upload can overlap (the stage is detached, the adopt runs on the main actor). `DragFileStore.place` lists the folder before it puts its file, so neither removes the other's new file; the adopt bumps the generation, so the stage's result is dropped and the card keeps the adopted URL.
- The adopt changes nothing in the record update below it (lines 921-935): `removedTemporaryFile` is true, so `fileURL` becomes nil and `fileIsTemporary` false, exactly as when the file is deleted.
- `removeRecord` runs `overlay.close(…, reason: .deleted)` first, which schedules a clean-up through `onDidClose`; `removeDragFolder` then cancels it and removes the folder at once.

- [ ] **Step 7: Run the suite**

Run the header's full-suite command. Expected: no `error:` lines, and `Test run with 659 tests in 84 suites passed`. This task adds 14 tests (5 in `DragFileNameTests`, 8 in `DragFileStoreTests`, `overlayCloseAfterDragDefaultsOnAndPersists`) and two suites.

- [ ] **Step 8: Hand checks (Tim)**

For Tim; the implementer lists these in its report and goes on to Step 10 (Step 9 is not built). Task 8's checklist repeats them. Build Release (`-configuration Release -derivedDataPath .build-rel`), run it, and keep a Terminal with `ls -lR ~/Library/Containers/io.tky.tidyshot/Data/tmp/Drag` at hand.
- Gesture: press on the card's blank area, the status text, the link text and the thumbnail and drag: each starts a drag with the thumbnail under the pointer; Copy URL, Save As…, Annotate, Delete and the Close badge still click; a click on the thumbnail of a saved capture reveals it; right-click and Control-click show the context menu. The card does not move. During a long drag held over another app the card does not auto-close.
- Receivers, each in Save mode, Upload mode and Upload-only mode, and in Upload-only both while `Uploading…` shows and after `URL copied`: Finder (Desktop), Slack (message field), Chrome (a Gmail compose window, and a page with an `<input type=file>` drop zone), Safari (a Gmail compose window), Mail (new message), Messages, Notes. Each must attach or copy the PNG. Note for each whether macOS shows a "would like to access data from other apps" prompt, and the file name the receiver shows: the template name before an upload, `aSIS7.png` style after it. Record the table for Task 8's checklist.
- Container: while the card shows, `Drag/<UUID>/` holds one file with that name; in Upload-only mode after the upload, `pending/<UUID>.png` is gone and `Drag/<UUID>/<key>.png` exists, the record still shows no local file in Recent Captures, and Copy Image, Save As… and Annotate on the card need no download (no `Downloading` notification). About 60 s after the card closes the folder is gone; Delete on a card removes it at once; quit and relaunch with a folder present: `Drag` is gone.
- Close after dragging out on: a drop on Finder closes the card, and Restore Closed Overlay brings it back and it drags again. A drag cancelled with Escape or dropped on the menu bar leaves the card open. Off: the card stays after a drop.
- Restored card without a local file (Upload-only, close the card before the upload ends, wait for `URL copied`, restore): no notification appears, and after a moment the card drags `aSIS7.png`. With Wi-Fi off the restore still works and dragging does nothing.
- A save folder on an external disk, if one is at hand: drag a fresh capture; the drag starts once the copy is made.
- Finder drop: the copy on the Desktop equals the original (`cmp`), and the original in the save folder is untouched.

Tim records which receivers took the file, the names they showed and any access prompt in Task 8's checklist table. A receiver that refuses the file URL, or shows the access prompt, makes Step 9 a follow-up.

- [ ] **Step 9: Follow-up, not built in 6a: the file-promise fallback**

Skip this step in 6a. It is built later, in its own commit, only if Tim's checklist shows a receiver refusing the file URL.

`TidyShot/Overlay/QuickAccessCardDragSource.swift`: add `import UniformTypeIdentifiers` to the imports and, at the end:
```swift
/// A file promise for the staged drag file that also writes `public.file-url` for it (Apple's
/// file-promise sample pattern): receivers that take promises get a copy in the folder they pick,
/// the rest read the file URL.
final class QuickAccessFilePromise: NSFilePromiseProvider {
    private let writer: QuickAccessFilePromiseWriter

    init(stagedURL: URL) {
        writer = QuickAccessFilePromiseWriter(stagedURL: stagedURL)
        super.init(fileType: UTType.png.identifier, delegate: writer)
    }

    override func writableTypes(for pasteboard: NSPasteboard) -> [NSPasteboard.PasteboardType] {
        super.writableTypes(for: pasteboard) + [.fileURL]
    }

    override func writingOptions(forType type: NSPasteboard.PasteboardType,
                                 pasteboard: NSPasteboard) -> NSPasteboard.WritingOptions {
        type == .fileURL ? [] : super.writingOptions(forType: type, pasteboard: pasteboard)
    }

    override func pasteboardPropertyList(forType type: NSPasteboard.PasteboardType) -> Any? {
        type == .fileURL
            ? (writer.stagedURL as NSURL).pasteboardPropertyList(forType: .fileURL)
            : super.pasteboardPropertyList(forType: type)
    }
}

/// Writes the promise by copying (cloning) the staged file into the receiver's folder, on a queue
/// of its own. The provider's `delegate` is weak, so the provider keeps this alive.
nonisolated final class QuickAccessFilePromiseWriter: NSObject, NSFilePromiseProviderDelegate, Sendable {
    let stagedURL: URL

    init(stagedURL: URL) {
        self.stagedURL = stagedURL
    }

    func filePromiseProvider(_ provider: NSFilePromiseProvider, fileNameForType fileType: String) -> String {
        stagedURL.lastPathComponent
    }

    func filePromiseProvider(_ provider: NSFilePromiseProvider, writePromiseTo url: URL,
                             completionHandler: @escaping (Error?) -> Void) {
        do {
            try FileManager.default.copyItem(at: stagedURL, to: url)
            completionHandler(nil)
        } catch {
            completionHandler(error)
        }
    }

    func operationQueue(for provider: NSFilePromiseProvider) -> OperationQueue {
        let queue = OperationQueue()
        queue.qualityOfService = .userInitiated
        return queue
    }
}
```
If the SDK isolates `NSFilePromiseProviderDelegate` to the main actor, conform with `@preconcurrency NSFilePromiseProviderDelegate`. In `mouseDragged`, the writer becomes `NSDraggingItem(pasteboardWriter: QuickAccessFilePromise(stagedURL: fileURL))`; nothing else changes. When it is built: re-run the suite, have Tim repeat every receiver of Step 8, and say in the commit message that the fallback was needed and for which receiver.

- [ ] **Step 10: Commit**

```bash
git add TidyShot/Output/DragFileStore.swift TidyShot/Overlay/DragFileName.swift TidyShot/Overlay/QuickAccessCardDragSource.swift TidyShot/Overlay/QuickAccessModel.swift TidyShot/Overlay/QuickAccessController.swift TidyShot/Overlay/QuickAccessView.swift TidyShot/App/AppCoordinator.swift TidyShot/Settings/AppSettings.swift TidyShot/Settings/OverlaySettingsView.swift TidyShotTests/DragFileStoreTests.swift TidyShotTests/DragFileNameTests.swift TidyShotTests/AppSettingsTests.swift
git commit -m "feat: drag a capture out of its Quick Access card as a file in the container"
```

### Task 7: Capture Previous Area

**Files:**
- Create: `TidyShot/Capture/PreviousArea.swift`
- Create: `TidyShotTests/PreviousAreaTests.swift`
- Modify: `TidyShot/Settings/AppSettings.swift` (`Keys` enum, after line 50 `scrollingAutoScroll`; the property, after line 78; `init`, after line 137; a store function, after `storeS3Config()` at line 156; Tasks 1, 2, 3 and 6 added lines next to these, so find each by name)
- Modify: `TidyShot/App/Shortcuts.swift` (after line 7, the `captureScrolling` name, before Task 4's `restoreOverlay`)
- Modify: `TidyShot/App/AppCoordinator.swift` (`registerShortcuts()`, after line 112; `captureScrolling()`, after the height guard at line 157; new `capturePreviousArea()` after line 168; `runSelection(mode:)`, the `.area` case at line 178)
- Modify: `TidyShot/App/StatusMenuController.swift` (`rebuild()`, after the `Capture Scrolling` item, line 75; one `@objc` action after line 111)
- Modify: `TidyShot/Settings/ShortcutsSettingsView.swift` (after line 10, the `Capture scrolling:` recorder)
- Test: `TidyShotTests/PreviousAreaTests.swift` (new suite), `TidyShotTests/AppSettingsTests.swift`, `TidyShotTests/ShortcutsTests.swift`

Line numbers are from `main` at a1dde71. Tasks 1 to 6 shift them, so find each place by the quoted code.

**Interfaces:**
- Consumes:
  - `AppCoordinator.capture(_ target: CaptureTarget, excludingWindows: [SCWindow] = [], duringSelection: Bool = false) async -> CaptureResult?` (Task 1): the capture options come from `CaptureOptions(settings:duringSelection:)`, so a call that does not pass `duringSelection` takes the cursor from `settings.showsCursor`. This task relies on that default and passes nothing.
  - `AppCoordinator.cardWindows() async -> [SCWindow]` (Task 3, private): the Quick Access cards on screen as ScreenCaptureKit windows, from `QuickAccessController.windowNumbers: Set<CGWindowID>`, with no lookup while no card shows.
  - `AppCoordinator.loadContent()`, `withCaptureLock(_:)`, `save(_:)` and `notifier.notifyError(_:title:)` from `main`.
  - `Selection.area(rect: CGRect, display: SCDisplay)`: the rect is in CoreGraphics global points, origin top left of the primary display (`TidyShot/Selection/Selection.swift`).
  - `KeyboardShortcuts.Name.restoreOverlay` (Task 4), only in the shortcut test.
- Produces:
  ```swift
  nonisolated struct StoredRect: Codable, Equatable, Sendable {
      var x: Double; var y: Double; var width: Double; var height: Double
      init(_ rect: CGRect)
      var cgRect: CGRect { get }
  }

  nonisolated enum PreviousArea {
      struct Display: Equatable, Sendable { let id: CGDirectDisplayID; let frame: CGRect }
      enum Resolution: Equatable, Sendable {
          case none
          case offScreen
          case area(CGRect, CGDirectDisplayID)
      }
      static func resolve(rect: CGRect?, displays: [Display]) -> Resolution
  }

  // AppSettings
  var lastAreaRect: StoredRect?            // key "lastAreaRect", JSON, nil until an area is captured

  // Shortcuts.swift
  static let capturePreviousArea            // stored name "capturePreviousArea", initial ⌃⇧6

  // AppCoordinator
  func capturePreviousArea() async
  ```
  The rule later tasks follow: every capture that selects an area writes `settings.lastAreaRect = StoredRect(rect)` with the rect it selected, before capturing. This task adds it for Capture Area and Capture Scrolling. Task 10 (All-in-One), Task 11 (Self-Timer) and Task 13 (a URL rect) add their own writes. Capture Previous Area itself does not write: a clipped rect would shrink the memory, and the original comes back when a display is plugged in again.

Behaviour (spec 2.9, Capture Previous Area): the stored rect is captured again, live, with no selection overlay. `PreviousArea.resolve` picks the display that holds the rect's centre and clips the rect to it. Freeze does not apply. The cards are excluded. The pointer shows or not by `Show cursor in screenshots`, like a fullscreen capture. Without a stored rect the notification `Capture an area first.` titled `No previous area` appears; with the rect on no connected display, `The previous area is not on a connected display.` with the same title.

- [ ] **Step 1: Write the failing tests**

`TidyShotTests/PreviousAreaTests.swift`:
```swift
import CoreGraphics
import Foundation
import Testing
@testable import TidyShot

struct PreviousAreaTests {
    /// CoreGraphics global points, origin top left of the primary display. `main` is the primary
    /// display, `right` sits beside it, `left` is above-left of the origin with a negative x.
    let main = PreviousArea.Display(id: 1, frame: CGRect(x: 0, y: 0, width: 1920, height: 1080))
    let right = PreviousArea.Display(id: 2, frame: CGRect(x: 1920, y: 0, width: 2560, height: 1440))
    let left = PreviousArea.Display(id: 3, frame: CGRect(x: -1440, y: 180, width: 1440, height: 900))

    @Test func noRectResolvesToNone() {
        #expect(PreviousArea.resolve(rect: nil, displays: [main]) == .none)
    }

    @Test func aRectUnderOnePointResolvesToNone() {
        #expect(PreviousArea.resolve(rect: CGRect(x: 10, y: 10, width: 0, height: 300), displays: [main]) == .none)
        #expect(PreviousArea.resolve(rect: CGRect(x: 10, y: 10, width: 300, height: 0.5), displays: [main]) == .none)
    }

    @Test func aRectOnTheMainDisplayComesBackUnchanged() {
        let rect = CGRect(x: 100, y: 200, width: 640, height: 480)
        #expect(PreviousArea.resolve(rect: rect, displays: [main, right, left]) == .area(rect, 1))
    }

    @Test func aRectOnADisplayWithANegativeOriginPicksThatDisplay() {
        let rect = CGRect(x: -1000, y: 300, width: 400, height: 300)
        #expect(PreviousArea.resolve(rect: rect, displays: [main, right, left]) == .area(rect, 3))
    }

    @Test func aRectPartlyOffItsDisplayIsClippedToIt() {
        let rect = CGRect(x: 1800, y: 900, width: 200, height: 200)
        #expect(PreviousArea.resolve(rect: rect, displays: [main])
                == .area(CGRect(x: 1800, y: 900, width: 120, height: 180), 1))
    }

    @Test func aRectBetweenTwoDisplaysGoesToTheOneHoldingItsCentre() {
        let displays = [main, right]
        // Centre x 1950: on the right display, clipped to its left edge.
        #expect(PreviousArea.resolve(rect: CGRect(x: 1800, y: 800, width: 300, height: 200), displays: displays)
                == .area(CGRect(x: 1920, y: 800, width: 180, height: 200), 2))
        // Centre x 1850: on the main display, clipped to its right edge.
        #expect(PreviousArea.resolve(rect: CGRect(x: 1700, y: 800, width: 300, height: 200), displays: displays)
                == .area(CGRect(x: 1700, y: 800, width: 220, height: 200), 1))
    }

    @Test func aRectOnARemovedDisplayIsOffScreen() {
        let rect = CGRect(x: 2000, y: 100, width: 500, height: 400)
        #expect(PreviousArea.resolve(rect: rect, displays: [main, right]) == .area(rect, 2))
        #expect(PreviousArea.resolve(rect: rect, displays: [main]) == .offScreen)
    }

    @Test func noDisplaysIsOffScreen() {
        #expect(PreviousArea.resolve(rect: CGRect(x: 0, y: 0, width: 100, height: 100), displays: []) == .offScreen)
    }

    @Test func aCentreInTheGapBetweenDisplaysIsOffScreen() {
        // `lower` starts at y 1200, so a centre at (1950, 1100) is on neither display.
        let lower = PreviousArea.Display(id: 4, frame: CGRect(x: 1920, y: 1200, width: 1280, height: 720))
        let rect = CGRect(x: 1900, y: 1000, width: 100, height: 200)
        #expect(PreviousArea.resolve(rect: rect, displays: [main, lower]) == .offScreen)
    }

    @Test func mirroredDisplaysResolveToTheFirstOne() {
        let mirror = PreviousArea.Display(id: 5, frame: main.frame)
        let rect = CGRect(x: 100, y: 100, width: 300, height: 200)
        #expect(PreviousArea.resolve(rect: rect, displays: [main, mirror]) == .area(rect, 1))
    }

    @Test func aStoredRectRoundTripsThroughJSON() throws {
        let rect = CGRect(x: -1000.5, y: 300.25, width: 400, height: 300.75)
        let data = try JSONEncoder().encode(StoredRect(rect))
        let decoded = try JSONDecoder().decode(StoredRect.self, from: data)
        #expect(decoded == StoredRect(rect))
        #expect(decoded.cgRect == rect)
    }

    /// The stored shape is part of the settings file: Task 10 and Task 13 read the same value.
    @Test func aStoredRectIsFourNamedNumbers() throws {
        let json = Data(#"{"x":1,"y":2,"width":3,"height":4}"#.utf8)
        let decoded = try JSONDecoder().decode(StoredRect.self, from: json)
        #expect(decoded.cgRect == CGRect(x: 1, y: 2, width: 3, height: 4))
    }
}
```

In `TidyShotTests/AppSettingsTests.swift`, add inside `struct AppSettingsTests`, after the `s3ConfigRoundTripsThroughDefaults` test:
```swift
    @Test func lastAreaRectIsNilUntilAnAreaIsCaptured() {
        #expect(AppSettings(defaults: freshDefaults()).lastAreaRect == nil)
    }

    @Test func lastAreaRectRoundTripsThroughASecondInstanceAndClears() {
        let defaults = freshDefaults()
        let rect = StoredRect(CGRect(x: -300, y: 120.5, width: 640, height: 480))
        let first = AppSettings(defaults: defaults)
        first.lastAreaRect = rect
        #expect(AppSettings(defaults: defaults).lastAreaRect == rect)
        #expect(defaults.data(forKey: "lastAreaRect") != nil)

        first.lastAreaRect = nil
        #expect(AppSettings(defaults: defaults).lastAreaRect == nil)
        #expect(defaults.object(forKey: "lastAreaRect") == nil)
    }

    @Test func anUnreadableLastAreaRectReadsAsNil() {
        let defaults = freshDefaults()
        defaults.set(Data("not json".utf8), forKey: "lastAreaRect")
        #expect(AppSettings(defaults: defaults).lastAreaRect == nil)
    }
```

In `TidyShotTests/ShortcutsTests.swift`, add inside `struct ShortcutsTests`:
```swift
    /// ⌃⇧6 sits after ⌃⇧5. No two names share a key or a default shortcut (Restore Closed
    /// Overlay has none; Task 4's `restoreOverlayHasNoInitialShortcut` checks that).
    @Test func capturePreviousAreaIsControlShiftSix() {
        #expect(KeyboardShortcuts.Name.capturePreviousArea.initialShortcut == .init(.six, modifiers: [.control, .shift]))
        let names: [KeyboardShortcuts.Name] = [.captureArea, .captureWindow, .captureFullscreen, .captureScrolling,
                                               .capturePreviousArea, .restoreOverlay, .cancelScrollingCapture]
        #expect(Set(names.map(\.rawValue)).count == names.count)
        #expect(Set(names.compactMap(\.initialShortcut)).count == names.count - 1)
    }
```

- [ ] **Step 2: Run the tests and see them fail**

Run:
```bash
xcodegen generate && xcodebuild test -project TidyShot.xcodeproj -scheme TidyShot -destination 'platform=macOS' -derivedDataPath .build 2>&1 | grep -E "Test run with|error:|TEST"
```
Expected: the build fails with `error:` lines such as `cannot find 'PreviousArea' in scope`, `cannot find 'StoredRect' in scope`, `value of type 'AppSettings' has no member 'lastAreaRect'` and `type 'KeyboardShortcuts.Name' has no member 'capturePreviousArea'`, and `** TEST FAILED **` or `** BUILD FAILED **`. No test runs.

- [ ] **Step 3: Implement `PreviousArea`**

`TidyShot/Capture/PreviousArea.swift`:
```swift
import CoreGraphics

/// A rectangle kept in UserDefaults as JSON (`lastAreaRect`): CoreGraphics global points, origin
/// top left of the primary display, as `Selection.area` carries them. Four named numbers, so the
/// stored value is readable and Task 10 and Task 13 can share it.
nonisolated struct StoredRect: Codable, Equatable, Sendable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double

    init(_ rect: CGRect) {
        x = rect.origin.x
        y = rect.origin.y
        width = rect.size.width
        height = rect.size.height
    }

    var cgRect: CGRect { CGRect(x: x, y: y, width: width, height: height) }
}

/// Capture Previous Area (spec 2.9). Pure: which display the stored rect belongs to now, and the
/// rect clipped to it. All rects are CoreGraphics global points.
nonisolated enum PreviousArea {
    /// A connected display as the decision needs it. The coordinator builds these from `SCDisplay`.
    struct Display: Equatable, Sendable {
        let id: CGDirectDisplayID
        let frame: CGRect
    }

    enum Resolution: Equatable, Sendable {
        /// No usable rect: none stored, or smaller than one point on a side.
        case none
        /// A rect whose centre is on no connected display.
        case offScreen
        /// The rect clipped to the display holding its centre, and that display.
        case area(CGRect, CGDirectDisplayID)
    }

    /// The display holding the rect's centre (the first, when frames overlap, as with mirrored
    /// displays), and the rect clipped to it. The centre decides, not the larger overlap, so a rect
    /// that a display change split between two displays still lands on one.
    static func resolve(rect: CGRect?, displays: [Display]) -> Resolution {
        guard let rect, !rect.isNull, !rect.isInfinite, rect.width >= 1, rect.height >= 1 else { return .none }
        let centre = CGPoint(x: rect.midX, y: rect.midY)
        guard let display = displays.first(where: { $0.frame.contains(centre) }) else { return .offScreen }
        return .area(rect.intersection(display.frame), display.id)
    }
}
```

- [ ] **Step 4: Add the setting**

In `TidyShot/Settings/AppSettings.swift`:
- In `Keys` (after line 50, `static let scrollingAutoScroll = "scrollingAutoScroll"`) add `static let lastAreaRect = "lastAreaRect"`.
- After the `scrollingAutoScroll` property (line 78) add:
  ```swift
  /// The rect of the last area capture (Capture Area, Capture Scrolling, and the later area
  /// kinds), for Capture Previous Area. Stored as JSON; nil until an area has been captured.
  var lastAreaRect: StoredRect? { didSet { storeLastAreaRect() } }
  ```
- In `init`, after `scrollingAutoScroll = defaults.bool(forKey: Keys.scrollingAutoScroll)` (line 137) add:
  ```swift
  // Not registered: a missing or unreadable value means no previous area.
  lastAreaRect = defaults.data(forKey: Keys.lastAreaRect).flatMap { try? JSONDecoder().decode(StoredRect.self, from: $0) }
  ```
- After `storeS3Config()` (it ends at line 156) add:
  ```swift
  /// Writes `lastAreaRect` as JSON, or removes it when nil. An encoding failure is logged and
  /// leaves the stored value as it was.
  private func storeLastAreaRect() {
      guard let lastAreaRect else {
          defaults.removeObject(forKey: Keys.lastAreaRect)
          return
      }
      do {
          defaults.set(try JSONEncoder().encode(lastAreaRect), forKey: Keys.lastAreaRect)
      } catch {
          NSLog("The last area could not be encoded, so the stored one is kept: \(error.localizedDescription)")
      }
  }
  ```

- [ ] **Step 5: Add the shortcut name**

In `TidyShot/App/Shortcuts.swift`, after the `captureScrolling` line (line 7), before Task 4's `restoreOverlay`:
```swift
    static let capturePreviousArea = Self("capturePreviousArea", initial: .init(.six, modifiers: [.control, .shift]))
```

- [ ] **Step 6: Wire the coordinator**

All in `TidyShot/App/AppCoordinator.swift`.

1. `registerShortcuts()`: after the `.captureScrolling` handler (lines 110 to 112), before Task 4's `.restoreOverlay` handler, add
   ```swift
        KeyboardShortcuts.onKeyUp(for: .capturePreviousArea) { [weak self] in
            Task { await self?.capturePreviousArea() }
        }
   ```
2. `runSelection(mode:)`: the first statement of `case .area(let rect, let display):` (line 178) becomes
   ```swift
                settings.lastAreaRect = StoredRect(rect)
   ```
   It goes before the capture, and (after Task 2) before the frozen-crop branch, so a frozen area and a live area both remember. The `.window` case does not write.
3. `captureScrolling()`: after the `guard rect.height >= CGFloat(ScrollCaptureLimits.minimumAreaHeightPoints)` block (ends at line 157) and before `selector.dismiss()` (line 158) add
   ```swift
            settings.lastAreaRect = StoredRect(rect)
   ```
   A refused area (under 100 pt tall) is not remembered. A window pick is: its frame is the rect.
4. After `captureScrolling()` (line 168) add:
   ```swift
    /// Capture Previous Area: the last area capture's rect again, live, with no selection overlay.
    /// `PreviousArea.resolve` clips the stored rect to the display under its centre. The cards are
    /// excluded and the pointer follows Show cursor, as for a fullscreen capture. It does not
    /// write `lastAreaRect`: a clipped rect would shrink the memory.
    func capturePreviousArea() async {
        await withCaptureLock {
            guard let content = await loadContent() else { return }
            let displays = content.displays.map { PreviousArea.Display(id: $0.displayID, frame: $0.frame) }
            switch PreviousArea.resolve(rect: settings.lastAreaRect?.cgRect, displays: displays) {
            case .none:
                notifier.notifyError("Capture an area first.", title: "No previous area")
            case .offScreen:
                notifier.notifyError("The previous area is not on a connected display.", title: "No previous area")
            case .area(let rect, let displayID):
                guard let display = content.displays.first(where: { $0.displayID == displayID }) else { return }
                let cards = await cardWindows()
                guard let result = await capture(.area(rect: rect, display: display), excludingWindows: cards) else { return }
                await save(result)
            }
        }
    }
   ```
   `cardWindows()` is Task 3's helper; this task adds no lookup of its own.

- [ ] **Step 7: Add the menu item and the Shortcuts row**

`TidyShot/App/StatusMenuController.swift`:
- In `rebuild()`, after the `Capture Scrolling` item (line 75) add
  ```swift
        menu.addItem(captureItem("Capture Previous Area", .capturePreviousArea, #selector(capturePreviousArea)))
  ```
  `captureItem` appends the shortcut to the title (`Capture Previous Area  ⌃⇧6`) and disables the item while a capture runs. The item stays enabled with no stored rect: the notification explains.
- After `captureScrolling()` (line 111) add
  ```swift
    @objc private func capturePreviousArea() { Task { await coordinator.capturePreviousArea() } }
  ```

`TidyShot/Settings/ShortcutsSettingsView.swift`: directly after the `Capture scrolling:` recorder (line 10), before any row Task 4 added, add
```swift
            KeyboardShortcuts.Recorder("Capture previous area:", name: .capturePreviousArea)
```

- [ ] **Step 8: Run the full suite**

Run:
```bash
xcodegen generate && xcodebuild test -project TidyShot.xcodeproj -scheme TidyShot -destination 'platform=macOS' -derivedDataPath .build 2>&1 | grep -E "Test run with|error:|TEST"
```
Expected: no `error:` lines, `** TEST SUCCEEDED **`, and `Test run with 675 tests in 85 suites passed`. This task adds 16 tests in 1 new suite: 12 in `PreviousAreaTests`, 3 in `AppSettingsTests`, 1 in `ShortcutsTests`.

- [ ] **Step 9: Hand checks (Tim)**

For Tim; the implementer builds the Release configuration, lists these in its report and goes on to Step 10. Task 8's checklist repeats them.
```bash
xcodebuild -project TidyShot.xcodeproj -scheme TidyShot -configuration Release -derivedDataPath .build-rel build -quiet
```
Tim opens `.build-rel/Build/Products/Release/TidyShot.app`.
- With no stored rect (`defaults delete io.tky.tidyshot lastAreaRect`, then relaunch), press ⌃⇧6: a notification titled `No previous area` says `Capture an area first.` Nothing is captured and no overlay appears.
- Capture an area with ⌃⇧4 (about 600 by 400 pt), then press ⌃⇧6: no dimmed overlay appears, a second capture of the same region is saved, and `sips -g pixelWidth -g pixelHeight` of both files reports the same size. ⌃⇧6 again repeats it.
- Capture a window with ⌃⇧2, then ⌃⇧6: it repeats the earlier area, not the window. Capture Fullscreen does not change it either.
- Capture Scrolling (⌃⇧5) over an area at least 100 pt tall and finish it: ⌃⇧6 captures that area once. A scrolling area under 100 pt (refused) does not replace the stored one.
- With a Quick Access card showing over the stored area, ⌃⇧6 captures the area without the card in the image.
- Show cursor in screenshots on: the pointer, placed inside the area, is in the ⌃⇧6 capture. Off: it is not.
- Menu bar menu: `Capture Previous Area  ⌃⇧6` follows Capture Scrolling, is disabled while a scrolling session runs, and clicking it captures. Settings > Shortcuts has `Capture previous area:` with ⌃⇧6; change it, confirm the new keys work and ⌃⇧6 does not, then reset it.
- With a second display (skip if there is none): capture an area on it, press ⌃⇧6 (captured on that display), unplug it, press ⌃⇧6: the notification reads `The previous area is not on a connected display.` Plug it back in: ⌃⇧6 works again.

- [ ] **Step 10: Commit**

```bash
git add TidyShot/Capture/PreviousArea.swift TidyShot/Settings/AppSettings.swift TidyShot/App/Shortcuts.swift TidyShot/App/AppCoordinator.swift TidyShot/App/StatusMenuController.swift TidyShot/Settings/ShortcutsSettingsView.swift TidyShotTests/PreviousAreaTests.swift TidyShotTests/AppSettingsTests.swift TidyShotTests/ShortcutsTests.swift
git commit -m "feat: Capture Previous Area and the remembered last area"
```
Check `git status` is clean afterwards (`TidyShot.xcodeproj` is ignored).

### Task 8: 6a checklist and spec close-out

**Files:**
- Create: `docs/testing/phase-6a-manual-checklist.md`
- Modify: `README.md` (the `## Default shortcuts` table, after the `| Capture scrolling | ⌃⇧5 |` row at line 57; two new sections between `## Scrolling capture` and `## Upload`, which starts at line 102; one line after the Phase 5 entry in `## Documents`, line 252)
- Modify: `docs/superpowers/specs/2026-10-19-tidyshot-screenshot-design.md` (the 2.1 rows at lines 29, 30, 34 and 35; the Dragging sentence in section 3 at line 786; section 2.9, lines 619-766: the sentences the plan header's six points change, the "Phase 6a (built)" paragraph as its last paragraph, and elsewhere only where Step 1 finds a divergence; the Phase 6 block of section 6 at lines 881-884; decision 6 in section 7 at line 902)
- Modify, only when Step 4 finds a divergence: `docs/superpowers/plans/2026-10-21-phase-6a-overlay-and-capture-polish.md` (the "Test totals" table)
- Test: none (documentation only; no new tests)

**Interfaces:**
- Consumes (behaviour, names and strings the checklist, README and spec check describe; each is produced by Tasks 1 to 7 or by `main`):
  - Task 1: `CaptureOptions.init(settings:duringSelection:)` (a capture taken while the selection overlay is up passes `showsCursor = false`; a frozen snapshot, a fullscreen and a previous-area capture pass the setting), `CaptureOptions.windowShadow` and `AppSettings.windowShadow` (`Include window shadow`, default off), the system shadow sized by `CaptureEngine.windowPixelSize(frame:contentRect:pointPixelScale:displayScale:includeShadow:)`, and `probes/window-shadow/probe.swift`, which Tim runs, with its result in `docs/superpowers/research/phase-6-research.md`. `WindowShadow.composite(_:scale:)` is written in Task 1 as a fallback and is not built.
  - Task 2: `AppSettings.freezeScreen` (`Freeze screen while selecting`, default off), `SelectionController.select(mode:content:freeze:)` and `frozenCapture(for:)`, `FreezeCrop.pixelRect(selection:displayFrame:scale:imageSize:)`, the live-capture fallback for a display whose snapshot failed, and freeze ignored by window mode and scrolling.
  - Task 3: `QuickAccessController` as a stack (newest at the corner, older cards 10 pt apart, `Show up to N overlays` 1 to 8, default 5, further limited to what fits `visibleFrame`), `OverlayScreenChoice` and `AppSettings.overlayDisplay` (`Show on`: `Display of the capture`, `Display with the pointer`, `Main display`), `QuickAccessController.windowNumbers`, cards not movable, the stack re-laid out by `NSApplication.didChangeScreenParametersNotification` and not while the pointer is over it, and cards excluded from area, fullscreen and freeze captures.
  - Task 4: the hover close badge (`xmark.circle.fill`, help `Close`), the right column (Annotate, Delete), the context menu (`Copy URL`, `Copy Image`, `Save As…`, `Annotate`, `Reveal in Finder`, `Close`, `Delete…`), `QuickAccessCloseReason`, `ClosedOverlays` (10 ids, newest first), `Restore Closed Overlay` in the menu after Recent Captures (the title carries the shortcut once one is recorded), `KeyboardShortcuts.Name.restoreOverlay` (`Restore closed overlay:`, no default), the context-menu fallback (an `NSHostingView` subclass) not built.
  - Task 5: `AppCoordinator.saveAs(recordID:)` (a save panel, PNG only, `EditorNaming.saveAsSuggestion`, the bytes written as is, a download posted as `Downloading <key>` under the title `Saving a copy…`, `Saved` with the file name), the `Save As…` button in every status state, and Copy Image on the card.
  - Task 6: `DragFileStore` (`<container tmp>/Drag/<record id>/<name>.png`, the copy started at mouse-down and the drag session begun once the file exists, `adopt` on upload, removal 60 s after the card closes, at once on delete, a sweep at launch), `DragFileName`, `QuickAccessCardDragSource`, the quiet prefetch for a restored card, `AppSettings.overlayCloseAfterDrag` (`Close after dragging out`, default on). The file-promise fallback (Task 6, Step 9) is not built.
  - Task 7: `PreviousArea`, `StoredRect`, `AppSettings.lastAreaRect`, `KeyboardShortcuts.Name.capturePreviousArea` (⌃⇧6), the menu item `Capture Previous Area  ⌃⇧6`, `Capture previous area:` in Settings > Shortcuts, the notifications `Capture an area first.` and `The previous area is not on a connected display.` titled `No previous area`.
  - `main`, unchanged: the Phase 5 checklist's shape (`docs/testing/phase-5-manual-checklist.md`), the README sections `## Default shortcuts`, `## Scrolling capture` and `## Documents`, `history.json` and the container layout (`thumbnails`, `pending`), the three after-capture actions, and `ImageEncoder.pngData(from:scale:)`.
- Produces: documentation only. Nothing in 6a depends on it. Task 14 (the 6b close-out) adds its own paragraph after the one written here.

Three points differ from the Phase 5 close-out, so follow them here:
- Every GUI check is Tim's (plan header). The three probes of the research notes (`docs/superpowers/research/phase-6-research.md`) that belong to 6a, window shadow (probe 1, `probes/window-shadow/probe.swift` from Task 1), drag-out receivers (probe 2) and freeze latency (probe 3), are checklist items: Tim runs them and records the results in the research notes and in the "Phase 6a (built)" paragraph. This task writes the checklist and the documents, builds the Release app, and does not run a GUI check or wait for one. The scheme-ownership probe belongs to 6b and is not in this checklist.
- Decision 6 in section 7 is amended now, as 2.9's decision 2 chose. If Tim's receiver run later shows a receiver refusing the file URL, the file-promise fallback (Task 6, Step 9) is a follow-up, and that follow-up amends 2.9 and decision 6 again; nothing of it is built or documented as built here.
- 2.9 is amended where the build differs from it, which includes the six points of the plan header. Nothing in the 6b text of 2.9 is touched.

- [ ] **Step 1: Read the finished code the documents describe**

The checklist, the README and the spec check must match the build, not the plan. Run:
```bash
ls TidyShot/Overlay TidyShot/Capture TidyShot/Output
git ls-files | grep -i "research\|probe"
grep -rn "windowNumbers\|QuickAccessCloseReason\|ClosedOverlays\|DragFileStore\|FreezeCrop\|PreviousArea" TidyShot --include=*.swift -l
grep -rn "static let" TidyShot/Overlay/QuickAccessStackLayout.swift TidyShot/Overlay/ClosedOverlays.swift TidyShot/Output/DragFileStore.swift | cut -c1-170
grep -rn "margin\|spacing" TidyShot/Overlay/QuickAccessController.swift TidyShot/Overlay/QuickAccessStackLayout.swift | head -12
grep -rn "ignoreShadows\|contentRect\|pointPixelScale" TidyShot/Capture | cut -c1-170
grep -rn "overlayDisplay\|overlayMaxCards\|overlayCloseAfterDrag\|freezeScreen\|windowShadow\|lastAreaRect" TidyShot/Settings/AppSettings.swift | cut -c1-170
grep -rn "seconds(60)\|60" TidyShot/Overlay/QuickAccessController.swift TidyShot/Output/DragFileStore.swift | head -6
git diff main --stat -- TidyShot/TidyShot.entitlements project.yml
while IFS= read -r s; do grep -rqF -- "$s" TidyShot || echo "MISSING: $s"; done <<'EOF'
Freeze screen while selecting
Area selections show a still image of the screen
Show cursor in screenshots
TidyShot never captures its own crosshair.
Include window shadow
Window captures keep transparent rounded corners either way.
Display of the capture
Display with the pointer
Main display
Show up to 1 overlay
Close after dragging out
Restore Closed Overlay
Restore closed overlay:
Capture Previous Area
Capture previous area:
Capture an area first.
No previous area
The previous area is not on a connected display.
Save As…
Copy Image
Reveal in Finder
Delete…
Copy URL
Saving a copy…
EOF
```
Expected: the files Tasks 1 to 7 list; `docs/superpowers/research/phase-6-research.md` and `probes/window-shadow/probe.swift` tracked (report either if it is not); the constants of 2.9 (card 340 x 104, spacing 10, margin 16, 10 closed ids, 60 s drag-folder delay, 1 to 8 cards, default 5); `ignoreShadows` set from `windowShadow` for `.window` and the shadow sized from `contentRect` times `pointPixelScale` through `windowPixelSize`, with no `WindowShadow.swift`; the five new keys with their defaults; no `MISSING:` line (a string the code splits over two lines is checked by its first half); an empty `git diff` for the entitlements file and `project.yml` (Phase 6a adds no entitlement and no package). Where the code differs from the wording in Step 2, in the README text of Step 3 or in 2.9, write the code's behaviour in the documents and list each change in the report. A `MISSING:` string, a constant or an entitlement change that looks like a bug rather than a decision is not documented away: stop and report it. Do not change code.

- [ ] **Step 2: Write the manual checklist**

`docs/testing/phase-6a-manual-checklist.md`:
````markdown
# Phase 6a manual test checklist

Run after any change to `TidyShot/Overlay/`, the freeze path in `TidyShot/Selection/`, the capture
options in `TidyShot/Capture/`, `DragFileStore`, Save As… from the card, Capture Previous Area, or
the capture functions of `AppCoordinator`. Automated tests cover the capture options and the cursor
rule, the stack layout, the display choice, the closed-overlay list, the drag file names and the
drag file store, the freeze crop, the previous-area decision, the new settings keys and the
shortcuts; everything here needs real windows, real receivers, real displays and eyes. The 4a and 4b
checklists still cover the editor and the Phase 5 checklist the scrolling session; run them too
after a change to those paths.

Setup: a fresh **Release** build (`xcodebuild -project TidyShot.xcodeproj -scheme TidyShot
-configuration Release -derivedDataPath .build-rel build`), Screen Recording granted, save folder
set to Desktop, a working destination saved in Settings > Upload, "Show notification" on in
Settings > General, "Show Quick Access overlay after capture" on in Settings > Overlay, Network
Link Conditioner installed (profiles `100% Loss` and a slow one), and a second display if you have
one, ideally at a different scale. Capture only made-up data: a capture may be uploaded and the link
may be shared. Note how the build is signed (`Config/Local.xcconfig`).

Make the test pages once.
```bash
mkdir -p ~/Desktop/p6 && cd ~/Desktop/p6
cat > freeze.html <<'HTML'
<!doctype html><meta charset="utf-8"><title>Freeze test</title>
<style>body{font:28px -apple-system,sans-serif;margin:40px}#t{font:700 120px ui-monospace,monospace}#b{width:120px;height:120px;background:#e11;animation:r 2s linear infinite}@keyframes r{to{transform:rotate(360deg)}}</style>
<div id="t">0</div><div id="b"></div>
<p><span title="Tooltip text for the freeze check">Hover here for a tooltip</span></p>
<script>setInterval(function(){document.getElementById('t').textContent=(performance.now()/1000).toFixed(2)},16)</script>
HTML
cat > drop.html <<'HTML'
<!doctype html><meta charset="utf-8"><title>Drop test</title>
<style>body{font:18px -apple-system,sans-serif;margin:40px}#z{border:3px dashed #888;padding:60px;border-radius:12px;text-align:center}#z.over{background:#cde}</style>
<div id="z">Drop a file here</div><p><input type="file" id="f"></p><pre id="o"></pre>
<script>
var z=document.getElementById('z'),o=document.getElementById('o');
function show(files){o.textContent=Array.from(files).map(function(f){return f.name+'  '+f.type+'  '+f.size+' bytes'}).join('\n')||'(no files)'}
['dragenter','dragover'].forEach(function(n){z.addEventListener(n,function(e){e.preventDefault();z.classList.add('over')})});
['dragleave','drop'].forEach(function(n){z.addEventListener(n,function(e){e.preventDefault();z.classList.remove('over')})});
z.addEventListener('drop',function(e){show(e.dataTransfer.files)});
document.getElementById('f').addEventListener('change',function(e){show(e.target.files)});
</script>
HTML
cat > alpha.swift <<'SWIFT'
import AppKit
guard CommandLine.arguments.count > 1, let image = NSImage(contentsOfFile: CommandLine.arguments[1]),
      let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { fatalError("usage: alpha file.png") }
let rep = NSBitmapImageRep(cgImage: cg)
func alpha(_ x: Int, _ y: Int) -> Int { Int(((rep.colorAt(x: x, y: y)?.alphaComponent ?? 0) * 255).rounded()) }
let w = rep.pixelsWide, h = rep.pixelsHigh
print("size \(w) x \(h)")
print("corners", alpha(0, 0), alpha(w - 1, 0), alpha(0, h - 1), alpha(w - 1, h - 1), " middle", alpha(w / 2, h / 2))
print("alpha up the middle column from the bottom row, every 8 px:",
      stride(from: h - 1, through: max(0, h - 160), by: -8).map { alpha(w / 2, $0) })
SWIFT
swiftc -O alpha.swift -o alpha
```
`freeze.html` shows a counter in seconds that ticks every 16 ms, a spinning square and a tooltip.
`drop.html` lists the name, type and size of every file the browser receives; open either with
`open -a Safari ~/Desktop/p6/drop.html` (Chrome the same way). `alpha file.png` prints the PNG's
size and the alpha at the corners, the middle and up the middle column.

Receivers for the drag-out section, all signed in with made-up content: Finder, Slack (a private
channel or a conversation with yourself), Chrome and Safari (Gmail compose windows and `drop.html`),
Mail (a compose window addressed to yourself, never sent), Messages (a conversation with yourself)
and Notes. Quit other apps that take drops.

`history.json` is in `~/Library/Containers/io.tky.tidyshot/Data/Library/Application Support/TidyShot/`;
`thumbnails` and `pending` are next to it. The drag copies are in
`~/Library/Containers/io.tky.tidyshot/Data/tmp/Drag/<record id>/`. Settings are read with
`defaults read io.tky.tidyshot <key>`.

## Settings and strings
- [ ] Settings > Capture lists, in this order, `Freeze screen while selecting` with the caption `Area selections show a still image of the screen and the capture is cut from it, so menus, tooltips and video stay as they were when you pressed the shortcut.`, `Show cursor in screenshots` with the caption `Fullscreen, previous-area, self-timer and URL captures show the pointer where it is. Area captures show it only with Freeze screen on. TidyShot never captures its own crosshair.`, and `Include window shadow` with the caption `Window captures keep transparent rounded corners either way.` The first and third are off on a fresh install. (Reset them without touching the save folder or the destination: `for k in freezeScreen windowShadow showsCursor overlayDisplay overlayMaxCards overlayCloseAfterDrag lastAreaRect; do defaults delete io.tky.tidyshot $k; done`, then relaunch.)
- [ ] Settings > Overlay lists the existing toggle, Position and Auto-close, then `Show on` (a picker: `Display of the capture` selected, `Display with the pointer`, `Main display`), `Show up to 5 overlays` (a stepper from 1 to 8; at 1 it reads `Show up to 1 overlay`), `Close after dragging out` (on), then history retention. With the overlay toggle off the new rows that depend on it are disabled like Position.
- [ ] Settings > Shortcuts lists `Capture area:`, `Capture window:`, `Capture fullscreen:`, `Capture scrolling:`, `Capture previous area:` (⌃⇧6) and `Restore closed overlay:` (empty). Change `Capture previous area:` to another combination, confirm the new keys work and ⌃⇧6 does not, then reset it. Set a combination for `Restore closed overlay:` for the restore section and clear it at the end.
- [ ] The menu bar menu lists Capture Area, Capture Window, Capture Fullscreen, Capture Scrolling, `Capture Previous Area  ⌃⇧6`, a separator, Recent Captures, `Restore Closed Overlay`, Retry Failed Uploads (only after a failure), Reveal Last Capture, a separator, Settings…, Quit TidyShot. The capture items are disabled while a capture or a scrolling session runs.
- [ ] Settings persist: change each of the five settings (`Show on` to `Main display`, `Show up to` 3, `Close after dragging out` off, freeze on, shadow on), quit and reopen, and check the panes still show them. `defaults read io.tky.tidyshot <key>` reads `main`, `3`, `0`, `1`, `1` for `overlayDisplay`, `overlayMaxCards`, `overlayCloseAfterDrag`, `freezeScreen` and `windowShadow` (one key per call; a key never changed does not exist yet, which is the default). Set them back afterwards.

## The cursor (bug fix)
Before this phase, with `Show cursor in screenshots` on, an area or window capture contained TidyShot's own crosshair at the mouse-up point. Test with it on, then off, with `Freeze screen while selecting` off.
- [ ] On: ⌃⇧4 over a plain region, drag from the top left to the bottom right, release. Zoom into the bottom-right corner of the saved image: no crosshair and no arrow. Repeat dragging to the other three corners. The saved image has no pointer at all.
- [ ] On: ⌃⇧2, click a window: no crosshair and no arrow in the image, with the pointer inside the window.
- [ ] On: ⌃⇧3 with the pointer resting on a recognisable spot (a text field): the arrow or I-beam is in the image at that spot. Off: it is not.
- [ ] On: ⌃⇧6 (after an area capture) with the pointer inside the stored area: the pointer is in the image. Off: it is not. The selection overlay's dimming, loupe and size label are never in any image.

## Cards stay out of captures (bug fix)
Take three captures so three cards stand in the corner, and repeat at each of the four corners (Settings > Overlay > Position) and on the second display.
- [ ] ⌃⇧3 (fullscreen) with three cards showing: no card is in the image. Where they stood, the windows or desktop under them show.
- [ ] ⌃⇧4 over the stack: select an area that covers the cards. The image has no card in it, and the loupe shows the screen without the cards. The cards come back, unmoved, afterwards.
- [ ] ⌃⇧2 on a window that lies partly behind a card: the image is the window alone.
- [ ] ⌃⇧6 with cards over the stored area: no card in the image.
- [ ] Press ⌃⇧3 twice a second apart: the second image has no card even though the first capture's card was still sliding in.
- [ ] With `Freeze screen while selecting` on and three cards showing, press ⌃⇧4: the frozen picture under the dimming shows what lies under the cards, with no card-shaped ghost. Escape: the cards are still there.
- [ ] An open editor window, the menu bar and the Dock are still in a fullscreen capture (only the cards are left out).
- [ ] A scrolling capture over an area with a card on it has no card in the image (the Phase 5 item still holds).
- [ ] ⌃⇧3 with no card showing feels as quick as before this phase.

## Window shadow (probe 1)
The build uses the system shadow (`ignoreShadows = false`, the size from the filter's `contentRect` times `pointPixelScale`). The probe checks that this holds; if the probe or an item below fails, the synthetic shadow written at the end of Task 1 is built as a follow-up.
- [ ] The probe: open a Finder window and a Slack window, then, in a terminal with the Screen Recording grant, from the repository: `mkdir -p .build && swiftc -parse-as-library -O probes/window-shadow/probe.swift -o .build/window-shadow-probe && .build/window-shadow-probe com.apple.finder com.tinyspeck.slackmacgap`. For each app: a header line and four capture lines. Open the `shadow-filter` and `noshadow-default` PNGs it names. Pass, for both windows: the shadowed image is larger than frame x scale on every side (about 20 pt or more at the bottom); its corner alphas are 0 and the last row's alpha is 0 or small while the alpha 20 pt above it is above 0; the window's title bar and traffic lights are the same pixel size in both PNGs. Write the printed lines, pass or fail, `pointPixelScale` and the macOS build under probe 1 in `docs/superpowers/research/phase-6-research.md`.
- [ ] Off (default): ⌃⇧2 on a Finder window and a Slack window. `alpha` reports corners 0 and a middle of 255; the pixel size equals the window's size in points times the display scale, as before this phase; the image has transparent rounded corners and no shadow.
- [ ] On: the same two windows. The image is larger than the window by the shadow, the window's text is at 1:1 (no softness), `alpha` reports corners 0 and a middle of 255, and the alpha up the bottom of the middle column runs from 0 at the last row up through partial values to 255 inside the window. Write down both sizes and the first lines of `alpha`'s output.
- [ ] Take a system shot of the same window (⌘⇧4, Space, click the window; the system keeps the shadow) and compare: window content, the shadow's extent and softness, and its offset agree. Write down the difference.
- [ ] On a window at the edge of the screen, a window partly off screen, a window on the second display at the other scale, and in dark mode and light mode: the shadow is whole, nothing is clipped at the image edge, and the scale is right on each display.
- [ ] The overlay's thumbnail, Annotate (the editor shows the transparent surround), Save from the editor, pasting from the clipboard into Notes over a dark background, and an upload (open the uploaded PNG) keep the alpha.
- [ ] Switching the setting takes effect on the next capture without a restart. Area, fullscreen and scrolling captures are unaffected by it.

## Freeze screen (probe 3)
Open `freeze.html` in Safari and play a video in another window.
- [ ] Off: ⌃⇧4 behaves as before; the counter keeps running under the dimming.
- [ ] On: press ⌃⇧4. The counter, the spinning square and the video stop at once (the screen is a still picture), the crosshair and loupe work, and the readout shows the right size. Wait 3 seconds, then drag over the counter and release. The saved image shows the counter at the value it had when you pressed the shortcut, not 3 seconds later.
- [ ] A menu: open Safari's File menu in the menu bar and press ⌃⇧4. With freeze on, the open menu is in the frozen picture and in a capture of it; with freeze off it is not. The same with a tooltip (hold the pointer over the tooltip text, press the shortcut with the tooltip showing).
- [ ] Cursor: with `Show cursor in screenshots` on, the pointer is in the frozen picture where it was when you pressed the shortcut and stays there while the crosshair moves; a capture that includes that spot contains it, one that does not has none. With it off, no pointer is in the picture or the capture. The crosshair is never in a capture.
- [ ] Edges: with freeze on, drag to the very right and bottom edges of the display: the file has the size the label read, with no off-by-one and no failure notification.
- [ ] Same pixels: close every window that changes (the counter page, video). Capture the same rectangle twice with the pointer outside it, once with freeze on and once off, `Show cursor` off: `sips -s format bmp a.png --out a.bmp && sips -s format bmp b.png --out b.bmp && cmp a.bmp b.bmp && echo SAME` prints `SAME`, and both have the same pixel size. Repeat with a rectangle at odd point positions on a Retina display.
- [ ] Two displays at different scales: pressing ⌃⇧4 freezes both at once. Select on the second display (and on one with a negative origin, if the arrangement has one): the crop is at that display's scale, correct in size and position, with the same checks as above. A drag that crosses displays clips to the display under its centre.
- [ ] Drawing: dragging a selection on the largest display tracks the mouse without lag, frozen as live. If it lags, write it down: the layer-backed backdrop of Task 2, Step 6 is then a follow-up.
- [ ] A frozen capture goes through upload-only mode, the card, Annotate and Recent Captures like any area capture.
- [ ] Window mode (⌃⇧2) and Capture Scrolling (⌃⇧5) show no frozen picture; the window highlight follows live content. Capture Previous Area has no selection, so freeze does not apply.
- [ ] Escape and a click without a drag leave nothing frozen on screen afterwards, and the next capture is live again.
- [ ] Latency: film the screen and keyboard with a phone in slow motion (240 fps), press ⌃⇧4 ten times with freeze off and ten with it on, and count the frames from the key going down to the first frame of the dimmed overlay. Write down the median for one display and, with a second display, for two, here and under probe 3 in `docs/superpowers/research/phase-6-research.md`. The spec's limit is about 150 ms at two displays; above it, report it (the snapshots would move to a stream started at the hotkey, or freeze would become area-only on the pointer's display first).

## The stack
Settings > Overlay > Show up to 5 overlays, auto-close 60 s so the cards stay while you look.
- [ ] Position top right: take five captures. The newest card is at the corner, each older one is one card height plus 10 pt below it, and the cards slide into place with an animation. A sixth capture pushes the oldest off; it is gone from the screen. Repeat for top left, bottom left and bottom right (older cards go up from a bottom corner).
- [ ] `Show up to` 1: a new capture replaces the card, as before this phase. 8: eight cards stand, and on a small or scaled-down display the stack stops at what fits between the menu bar and the Dock (set the display to a low resolution to see it).
- [ ] Auto-close 5 s: every card closes by its own timer, the oldest first. Holding the pointer over one card pauses only that card's countdown; it restarts when the pointer leaves. Auto-close "never" keeps all cards.
- [ ] While the pointer is over a card, let another card close: the cards under the pointer do not move out from under it until the pointer leaves, then the stack settles. Close the newest card with its badge and keep the pointer still: the others slide up only after the pointer leaves the stack.
- [ ] Delete a card in the middle of the stack and Annotate another: each closes and the gap closes.
- [ ] Upload-only mode, a capture uploading in one card and an older card settled: the uploading card stays until its URL is copied, then counts down; the settled one closes on its own timer.
- [ ] A card cannot be moved: pressing on its background and dragging does not move the panel (it starts a drag-out, see below).
- [ ] The stack is on every Space and over a full-screen app: take a capture in a full-screen Safari window and the stack shows there.
- [ ] Dock and menu bar: with the Dock at the bottom, at the side, hidden and shown, the stack stays inside the visible frame, 16 pt from the corner's edges.

## Which display (needs a second display)
- [ ] `Display of the capture` (default): ⌃⇧6 on an area stored on the second display, with the pointer on the first: the card appears on the second display. A fullscreen capture (⌃⇧3) puts it on the display under the pointer, which is the display captured. A window capture puts it on the display under the window's centre (drag a window so its centre is on the second display, with most of it visible on the first). A scrolling capture puts it on the area's display.
- [ ] `Display with the pointer`: the same ⌃⇧6 puts the card on the first display, where the pointer is. `Main display`: the card is on the main display whatever the capture or the pointer.
- [ ] The whole stack lives on one screen: with three cards on the first display, a capture shown on the second moves all four there, with an animation. Cards never split across displays.
- [ ] Unplug (or put to sleep) the display that holds the stack: the stack moves to the main display and nothing crashes. Plug it in again, change the resolution and the arrangement in System Settings > Displays with a stack showing: the stack stays on screen in its corner.
- [ ] Cards are 340 by 104 points on a 1x and on a 2x display.

## The card
- [ ] Hover a card: a round close badge (an `xmark` on a material circle, help `Close`) appears at its top-left corner and is gone when the pointer leaves. The right column holds Annotate (`pencil.tip.crop.circle`, help `Annotate`) and Delete (a trash can; help `Delete this capture`, or `Cancel the upload and delete this capture` while uploading) and nothing else; there is no Pin button yet.
- [ ] The status column's buttons: `Copy URL` and `Save As…` once the upload has finished; `Retry` and `Save As…` after a failure (Wi-Fi off, then a capture); `Save As…` alone while the upload runs and after a plain "Save and copy image" save.
- [ ] With another app (Safari) frontmost, right-click a card: the menu appears although the card's panel is non-activating. If it does not, write it down: the `NSHostingView` menu fallback of Task 4 is then a follow-up. It lists `Copy URL` (greyed while uploading and without a link), `Copy Image`, `Save As…`, `Annotate`, `Reveal in Finder` (only when the capture has a file in the save folder), a separator, `Close`, `Delete…`. There is no `Pin to Screen` item yet. Control-click shows the same menu. Each item does what its name says; `Delete…` brings the confirmation alert to the front, Cancel leaves the card, and OK deletes everywhere, as the trash button does.
- [ ] A click on the thumbnail reveals a save-folder file in Finder; on an upload-only card with no file it does nothing and nothing breaks. A click on a button does not start a drag.
- [ ] Copy Image, from the context menu, with each kind of capture: a saved file; an uploaded capture that kept its file; an upload-only capture whose file is gone (a signed download runs; `Copying image…` is posted). Preview > File > New from Clipboard shows the same image, with the same pixel size as the file.
- [ ] Annotate from a card opens the editor and closes the card (not restorable, see below).

## Close and restore
Bind `Restore closed overlay:` to a combination for this section.
- [ ] Close a card with the badge, with the context menu `Close`, by auto-close, by pushing it out with a sixth capture, and by dragging it out. Each time `Restore Closed Overlay` in the menu is enabled and the shortcut brings back that card at the corner, with the record's current state (a link that arrived since, a failed upload) and its thumbnail, and with the normal auto-close. With a shortcut recorded, the menu item reads `Restore Closed Overlay  <shortcut>`.
- [ ] With the stack on the second display, restore: the card joins that stack. With no card showing, restore puts the card on the pointer's display (`Display of the capture` and `Display with the pointer`) or the main display (`Main display`).
- [ ] Delete a capture from its card, and open the editor from another card: neither can be restored. When only those were closed, `Restore Closed Overlay` is disabled.
- [ ] Close four cards one after the other and restore four times: they come back newest-closed first. A fifth restore does nothing and the menu item is disabled.
- [ ] Close eleven cards (set `Show up to` 1 and take eleven captures; each pushes the last one out) and restore repeatedly: ten come back, the eleventh is gone.
- [ ] A card showing is not restored a second time: with the newest closed record's card already on screen, restore skips it and brings back the next one.
- [ ] Delete a closed card's capture from Recent Captures: restore skips it.
- [ ] A restored card's Annotate opens the editor from the file or, for an uploaded upload-only capture, from the bucket (the same as the Annotate button in Recent Captures).
- [ ] Quit and reopen: the list is empty and the menu item is disabled. Recent Captures still holds everything.

## Save As… and Copy Image from the card
Keep another app (Safari) frontmost while you click the card.
- [ ] Click `Save As…` on a card of a capture that has a file in the save folder. TidyShot comes forward with an ordinary save panel (a window, not attached to the card), PNG is the only type, and the name and folder are the capture's own file in the save folder. Open the editor on the same capture and press ⇧⌘S: the suggestion is the same.
- [ ] Save to the Desktop: `shasum -a 256` of the copy equals that of the original (no re-encode); `Saved` with the copy's name is posted (when notifications are on; nothing is posted when they are off, and the file is still written), and a click on it reveals the copy. Pick the original file instead and confirm Replace: the file is unchanged byte for byte.
- [ ] For an upload-only capture the suggestion is the file name template's name with the current counter (none is drawn), in the save folder when one is set, otherwise where the panel last was. While `Uploading…` shows, the copy equals the pending file (`pending/<id>.png`); after a failed upload (`Retry  Save As…`) it writes the pending file too.
- [ ] After the upload, on a card that showed through it: the panel opens, and the copy is written from the card's kept drag copy, with no `Downloading` notification; it equals `curl -s <url> | shasum -a 256`. On a restored upload-only card before its quiet download has landed (Network Link Conditioner on a slow profile): the panel opens first, then after Save `Saving a copy…` with `Downloading <key>` is posted while the download runs, then `Saved`. With Wi-Fi off the failure is posted as `Not saved` and nothing crashes.
- [ ] Save into a folder other than the save folder (Documents): it works under the sandbox. Cancel the panel: nothing is written and nothing is posted.
- [ ] Save As… changes nothing about the capture: the card, its link, Recent Captures, `history.json`, Reveal Last Capture and the clipboard are as before.
- [ ] Open the panel and wait for the card's auto-close to run out: the panel keeps working and saves the capture.
- [ ] Use Save As… from the button and from the context menu, from a restored card, and from a card in the middle of the stack: each saves that card's capture.
- [ ] After the panel closes, clicking back into Safari works as usual; a second card's buttons still work without activating TidyShot.
- [ ] Editor regression: Annotate a capture, draw an arrow, ⇧⌘S: the sheet suggests the same name as before, the edited copy is written, `Saved` appears, and with the capture's image still on the clipboard the clipboard now holds the edit.

## Drag-out (probe 2)
- [ ] During a drag, `ls -R ~/Library/Containers/io.tky.tidyshot/Data/tmp/Drag` shows `<record id>/<name>.png` and `shasum -a 256` of it equals the source file's. The original in the save folder is untouched and stays where it was after every drop below.
- [ ] A drag starts from the thumbnail, the status text, the link text and the empty margin of a card, shows the card's thumbnail as the drag image, and offers copy only (the green plus, never a move). A press on a button, the badge or the right column does not start a drag. A click without moving still works everywhere. Hold a drag over another app longer than the auto-close time: the card does not close under it.
- [ ] Names: an uploaded capture's file is named like the end of its URL (`aSIS7.png` for `.../aSIS7.png`), so it matches the link on the clipboard; with the key template `shots/{random:6}` it is the last part only. A capture that was never uploaded is named like its Save As… suggestion.
- [ ] Receivers. Use "Upload and copy URL" and wait for the upload to finish, then drag the card onto each receiver. Fill in the table: accepted (yes/no), the name the receiver shows, whether the image arrives whole (same pixel size), and whether a prompt about data from another app appears.

  | Receiver | Accepted | Name shown | Whole | Prompt |
  |---|---|---|---|---|
  | Finder (Desktop and a folder window) | | | | |
  | Slack (message box, then send) | | | | |
  | Chrome (Gmail compose and `drop.html`) | | | | |
  | Safari (Gmail compose and `drop.html`) | | | | |
  | Mail (compose body and attachment area) | | | | |
  | Messages (the conversation with yourself) | | | | |
  | Notes (note body) | | | | |

  Finder copies the file, never moves it. Dropping on the Trash does not delete or move the original. Copy the table under probe 2 in `docs/superpowers/research/phase-6-research.md`. If any receiver refuses the file URL or shows the prompt, write down which: the file-promise fallback (Task 6, Step 9; a provider that also writes the file URL) is then built as a follow-up, not in 6a.
- [ ] Modes, with Finder and Slack: "Save and copy image" (drag at once); "Upload and copy URL" before the upload ends (Network Link Conditioner on a slow profile) and after; "Upload only, keep no local file" before the upload ends and after it (the URL is on the clipboard, the file in `pending` is gone). Each time the dropped file is the capture, whole.
- [ ] Upload only, after the upload: the card is still on screen, and dragging it still works, from a file in the `Drag` folder that took the place of the pending file. `history.json` shows the record as before (no `fileURL`), and Recent Captures shows no local file. Copy Image, Save As… and Annotate on that card need no download (no `Downloading` notification). 60 seconds after the card closes `ls ~/Library/Containers/io.tky.tidyshot/Data/tmp/Drag` no longer lists the record's folder (Slack may still read the file in those seconds).
- [ ] Start a drag during a slow upload, hold the card in the air until the upload finishes, then drop: the file still arrives whole.
- [ ] A restored card with no local file (upload-only, restored after closing): it starts a quiet download when it appears (no notification). Network Link Conditioner on a slow profile: dragging before the download ends does nothing and the card stays; after it ends, dragging works. With Wi-Fi off the restore still works and dragging does nothing. A restored card with a save-folder file drags at once.
- [ ] A save folder on an external disk, if one is at hand: drag a fresh capture; the drag starts once the copy is made, and the receiver gets the file whole.
- [ ] `Close after dragging out` on: a drop onto a receiver closes the card, which is restorable and drags again once restored. A drag cancelled with Escape, or released over nothing, leaves the card. Off: the card stays after a drop.
- [ ] Drag the same card to two receivers one after the other: both get the file. Drag a card from the middle of the stack: it is that card's capture.
- [ ] Delete the capture whose card was dragged from: its `Drag/<record id>` folder is gone at once. Put a stray folder in `Drag` (`mkdir -p ~/Library/Containers/io.tky.tidyshot/Data/tmp/Drag/stale && touch ~/Library/Containers/io.tky.tidyshot/Data/tmp/Drag/stale/x`), quit and reopen: the `Drag` folder is empty.
- [ ] Drag the 65,536 px capture of the Phase 5 checklist: the drag starts at once (a clone, not a copy) and Finder receives it whole.

## Capture Previous Area
- [ ] With no stored area (`defaults delete io.tky.tidyshot lastAreaRect`, then quit and reopen TidyShot) ⌃⇧6 posts `Capture an area first.` titled `No previous area`, and nothing is captured.
- [ ] Capture an area with ⌃⇧4, then press ⌃⇧6: no dimmed overlay appears, a second capture of the same region is saved, and both files have the same pixel size. A third press repeats it.
- [ ] The rect survives a relaunch. A window capture and a fullscreen capture do not change it. A Capture Scrolling area (at least 100 pt tall, window or drag) replaces it; a refused scrolling area (under 100 pt) does not.
- [ ] On a two-display setup: capture an area on the second display, press ⌃⇧6 (it captures there, at that display's scale), unplug the display and press ⌃⇧6: `The previous area is not on a connected display.` titled `No previous area`. Plug it in again: ⌃⇧6 works again, so the stored rect was not shrunk.
- [ ] A stored area that lies partly beyond a display's edge after a resolution change is clipped to the display and captured.
- [ ] The menu item is disabled while a capture or a scrolling session runs, and ⌃⇧6 does nothing then.
- [ ] Freeze does not apply: with freeze on, ⌃⇧6 still captures live (put the counter page under the stored area and check the counter in the image is not frozen from earlier).

## VoiceOver
Turn VoiceOver on (⌘F5) with a card showing.
- [ ] VO-arrow through a card: the thumbnail, the status, `Copy URL`/`Retry`, `Save As…`, `Annotate`, `Delete` and the close badge are each read by name, and the badge can be reached with VoiceOver even though it is drawn only on hover. The context-menu actions are listed in the VoiceOver actions menu.
- [ ] Turn VoiceOver off. Everything above behaves as before.

## Regression
- [ ] Capture Area, Capture Window and Capture Fullscreen: normal saves, uploads and thumbnails; a window capture keeps its transparent corners; the overlay's Annotate and Delete work; Recent Captures rows, Retry Failed Uploads and Reveal Last Capture are as before.
- [ ] A scrolling capture (Phase 5): the panel, Start, Done and the result work; the card appears on the area's display and is not in the image.
- [ ] Upload-only mode, end to end: capture, URL on the clipboard, drag the card, Save As…, Annotate, Delete. No file is left in `pending` or `Drag` after Delete.
- [ ] Quit TidyShot with cards showing: the cards go and nothing is left on screen. Relaunch: no card, and the menu item `Restore Closed Overlay` is disabled.

## Probe results
Write these under the probes in `docs/superpowers/research/phase-6-research.md` and into the "Phase 6a (built)" paragraph of spec 2.9 (which lists them as still to be written down):
- Window shadow: the probe's lines, pass or fail; sizes; the comparison with the system shot.
- Drag-out receivers: the table above; any prompt; any refusal (which makes the file-promise fallback a follow-up).
- Freeze latency: the medians for off and on, one display and two.
- Timings and observations the items above ask for.
````

- [ ] **Step 3: Update the README**

In `README.md`:

In the shortcuts table, after `| Capture scrolling | ⌃⇧5 |` (line 57) add:
```markdown
| Capture previous area | ⌃⇧6 |
| Restore closed overlay | none; set one in Settings > Shortcuts |
```

Insert before `## Upload` (line 102) these two sections:
````markdown
## Capture options

Settings > Capture has three options. *Freeze screen while selecting* shows a still picture of the
screen while you drag an area and cuts the capture from it, so menus, tooltips and video stay as
they were when you pressed the shortcut; window mode and scrolling capture are live. *Show cursor in
screenshots* puts the pointer into fullscreen and previous-area captures, and into area captures
only with freeze on; TidyShot never captures its own crosshair. *Include window shadow* keeps the
system shadow around a window capture; the corners are transparent either way.

Capture Previous Area (⌃⇧6) captures the rectangle of your last area capture (or scrolling capture)
again, with no selection. It says so when there is no previous area or its display is gone.

## Quick Access overlay

Each capture shows a card in a corner of the screen. Several cards stack, newest at the corner, up
to the number set in Settings > Overlay. Settings > Overlay also chooses the display they appear
on: the capture's display (default), the pointer's, or the main display. The cards are not in any
capture.

A card shows the upload status and has Annotate and Delete buttons, `Save As…` and `Copy URL` or
`Retry`, and a close badge when you point at it; a right-click opens a menu with every action,
including Copy Image. Closing a card does not delete the capture: Restore Closed Overlay in the menu
(or its shortcut) brings back the ten most recently closed cards, newest first.

Drag a card to drop the screenshot into Finder, Slack, a browser, Mail, Messages or Notes. What
you drop is a copy of the file kept in TidyShot's container until a minute after the card closes,
named like the link when the capture was uploaded; the original stays where it was. In upload-only
mode the file is kept for as long as the card shows, so you can drag it after the link is on the
clipboard. A card for an older upload-only capture downloads its file when it is restored, and can
be dragged once that has finished. Settings > Overlay has *Close after dragging out*.
````

In `## Documents`, after the Phase 5 entry (line 252) add:
```markdown
- Phase 6a manual test checklist: `docs/testing/phase-6a-manual-checklist.md`
```

Then confirm no stale text remains:
```bash
grep -ni "limitation\|not yet\|coming\|later phase\|phase 6\|promise" README.md
```
Expected: only the Documents entry. A README line that says the overlay cannot be dragged or stacked is deleted. If the build differs from the README text above (for example the retention of the drag copy, or a restore that needs another key), write the code's behaviour.

- [ ] **Step 4: Run the full suite and check the totals table**

Run:
```bash
xcodegen generate && xcodebuild test -project TidyShot.xcodeproj -scheme TidyShot -destination 'platform=macOS' -derivedDataPath .build 2>&1 | grep -E "Test run with|error:|TEST"
```
Expected: no `error:` lines, `** TEST SUCCEEDED **`, and `Test run with 675 tests in 85 suites passed`. This task adds no tests, so that count must equal the Task 7 row of the "Test totals" table in the plan's header section.

Reconcile the table against the repo:
```bash
grep -rhE '^(@MainActor )?(nonisolated )?struct [A-Za-z0-9]+Tests\b' TidyShotTests | wc -l; grep -rhE '^\s*@Test' TidyShotTests | wc -l
grep -c '[{][{]' docs/superpowers/plans/2026-10-21-phase-6a-overlay-and-capture-polish.md
```
Expected: the first count is the suites and the second the tests in the Task 7 row (one `struct …Tests` per suite; Swift Testing counts a parameterized `@Test` as one test per argument in the run, so the run's count is the one to trust and the greps only help find which suites differ), and the last count is `0`, so no placeholder is left in the plan. The branch starts from the baseline of 602 tests in 76 suites. If the run differs from the Task 7 row, a review fix added or removed tests. Find which task with:
```bash
git log --oneline --stat a1dde71..HEAD -- TidyShotTests
```
Correct that task's row and every row after it in the table, and add one line under the table: `Task 8 correction: <commit> <what changed>; the real run reads <the line>.` Change nothing else in the plan. If the run equals the row, change nothing.

Then check the new files against the task list:
```bash
git diff --name-only --diff-filter=A a1dde71...HEAD -- TidyShot TidyShotTests project.yml | sort
git diff --name-only --diff-filter=A a1dde71...HEAD -- TidyShot TidyShotTests | while read -r f; do grep -q "$(basename "$f")" docs/superpowers/plans/2026-10-21-phase-6a-overlay-and-capture-polish.md || echo "NOT IN PLAN: $f"; done
for f in Capture/FreezeCrop Capture/PreviousArea Overlay/QuickAccessStackLayout Overlay/OverlayScreenChoice Overlay/ClosedOverlays Overlay/DragFileName Overlay/QuickAccessCardDragSource Output/DragFileStore; do test -f TidyShot/$f.swift || echo "NO FILE: $f"; done
for t in CaptureOptionsTests WindowShadowTests FreezeCropTests QuickAccessStackLayoutTests OverlayScreenChoiceTests ClosedOverlaysTests DragFileNameTests DragFileStoreTests PreviousAreaTests AppSettingsTests ShortcutsTests EditorNamingTests; do test -f TidyShotTests/$t.swift || echo "NO TEST: $t"; done
test -f TidyShot/Capture/WindowShadow.swift && echo "UNEXPECTED: WindowShadow.swift (the synthetic shadow is a fallback, not built in 6a)"
grep -rl "NSFilePromiseProvider" TidyShot && echo "UNEXPECTED: a file promise (the drag-out fallback is not built in 6a)"
```
Expected: the first command lists the files Tasks 1 to 7 add: the 8 sources of the loop above, the 9 new test files (`CaptureOptionsTests`, `WindowShadowTests`, `FreezeCropTests`, `QuickAccessStackLayoutTests`, `OverlayScreenChoiceTests`, `ClosedOverlaysTests`, `DragFileNameTests`, `DragFileStoreTests`, `PreviousAreaTests`), and nothing under `project.yml` (`probes/window-shadow/probe.swift` is outside the paths listed); no `UNEXPECTED:` line; `AppSettingsTests`, `ShortcutsTests` and `EditorNamingTests` exist on `main` and are modified, not added. No `NOT IN PLAN:` line (every added file is named in a task section; a stray file means a review fix added it, so say which). No `NO FILE:` or `NO TEST:` line. A listed file that a task section moved or renamed is fixed in this loop, not in the code.

- [ ] **Step 5: Build the Release app and hand the checklist to Tim**

Run:
```bash
xcodebuild -project TidyShot.xcodeproj -scheme TidyShot -configuration Release -derivedDataPath .build-rel build -quiet && echo RELEASE_BUILT
swiftc -parse-as-library -O probes/window-shadow/probe.swift -o .build/window-shadow-probe && echo PROBE_BUILT
```
Expected: `RELEASE_BUILT` and `PROBE_BUILT`. Do not open the app, run the probe or work through the checklist: every item of `docs/testing/phase-6a-manual-checklist.md` is Tim's (plan header), as are the observations it asks for (the window-shadow probe and the comparison with the system shot, the receiver table, the freeze latency medians, any prompt a receiver showed). Fix nothing in code. Step 6 writes the "Phase 6a (built)" paragraph with those observations listed as still to be written down by Tim, as Phase 5's close-out did.

- [ ] **Step 6: Amend the spec, and mark Phase 6a delivered**

Always amend these places. The first four follow the planned design and need no observation, except where marked.

1. The 2.1 rows. Replace the rows at lines 29 and 30 with:
```markdown
| Capture previous area | Re-capture the last rectangle | P1 | Built in Phase 6a (2.9): ⌃⇧6 captures the rect of the last area capture again, with no selection overlay |
| Quick Access Overlay | Thumbnail in a screen corner after capture with copy, save, annotate, share, drag-out, auto-close, restore closed overlay, multi-display | P0 (minimal), P1 (full) | MVP shows upload status plus copy/save/drag; Phase 6a (2.9) built the stack of cards, close and restore, the choice of display, Save As…, Copy Image and drag-out of a file; Pin is 6b, swipe gestures and hide-temporarily are deferred |
```
   Replace the rows at lines 34 and 35 with:
```markdown
| Transparent window / shadow toggle | Keep or drop the window shadow | P1 | Built in Phase 6a (2.9): `ignoreShadows` follows `Include window shadow`; the system shadow, sized from the filter's contentRect and pointPixelScale |
| Freeze screen | Snapshot the display before selecting, so moving content is capturable | P1 | Built in Phase 6a (2.9): every display is captured before the overlay appears and the capture is cut from that picture |
```

2. Section 3, the overlay rule at line 786. Replace `Dragging it out drags the local file.` with `Dragging a card out drops a file: a copy of the capture kept in TidyShot's container, handed over as a file URL (2.9).`

3. The Phase 6 block of section 6 (lines 881-884). After the "6b:" bullet add a blank line and:
```markdown
Delivered <date of this run, YYYY-MM-DD>: 6a on `phase-6-polish`. 6b follows in its own PR; Phase 6 is released when both have merged. Design and what was built: 2.9.
```
Write the real date (`date +%F`), not the placeholder.

4. Decision 6 in section 7 (line 902). Replace `drag-out from the overlay uses `NSFilePromiseProvider`;` with `drag-out from the overlay hands over a file URL to a copy in the container, not a file promise (amended in Phase 6, see 2.9);`.

5. Section 2.9, the plan header's six points, rewritten in place (each also gets a line in the paragraph of item 6):
   - The opening paragraph's `Sources and the probes to run: `research.md` next to this draft.` becomes `Sources and the probes to run: `docs/superpowers/research/phase-6-research.md`.`; so does each `research.md` in the 6a text of 2.9 (the Why a file URL paragraph; the Window shadow paragraph is rewritten below). The 6b text is left alone.
   - **Stacking**: `animated with `setFrame(_:display:animate: true)`` becomes `moved together through `NSAnimationContext` and `animator().setFrame(_:display:)` (0.2 s), which does not block the main actor`, and `Show up to N overlays`, there and in the Settings summary, gains `(`Show up to 1 overlay` at 1)`.
   - **Save As…**: `with `Downloading <key>` posted while it runs` becomes `with `Downloading <key>` posted under the title `Saving a copy…` while it runs`.
   - **Drag-out**: `made at drag start by `DragFileStore`` becomes `started at mouse-down on the card by `DragFileStore`, in a detached task; the drag session begins once the file exists (a drag that passes the 3 pt threshold earlier waits for the next mouse-dragged event)`.
   - **Why a file URL**: after its last sentence add `The fallback is written in the Phase 6a plan (Task 6, Step 9) and is not built; it is built only if Tim's checklist run shows a receiver refusing the file URL.`
   - **Window shadow**: from `Whether `contentRect` grows by the shadow` to the end of the paragraph becomes `Whether `contentRect` grows by the shadow, and whether `SCScreenshotManager` draws the shadow at 1:1 into that size, is not documented. Phase 6a builds the system shadow, sized by `CaptureEngine.windowPixelSize` (a degenerate filter falls back to the frame), and commits the probe `probes/window-shadow/probe.swift`, which captures a Finder and a Slack window both ways and records `contentRect`, the output size and the alpha at the corners; running it is Tim's checklist item, with the result in `docs/superpowers/research/phase-6-research.md`. If the system shadow does not come out at 1:1, the synthetic one written in the plan (Task 1's fallback) is built: `WindowShadow.composite(_:scale:)` (pure) captures without the shadow, pads the image by 40 pt on each side and draws a black shadow under it with blur radius 20 pt, offset 0 by 10 pt downward and opacity 0.4. Either way the result keeps alpha outside the shadow.` The Risks bullet `*Window shadow.* The probe may find…` becomes `*Window shadow.* The system shadow is built; if Tim's probe finds that `SCScreenshotManager` squashes or clips it, the synthetic shadow written in the plan is built as a follow-up.`; decision 11 becomes `Window shadow off by default; the system shadow, with a synthetic one written as the fallback if Tim's probe fails.` In the Architecture list, `Capture/WindowShadow.swift` (only if the probe fails) stays as written.

6. Section 2.9: after the Decisions list, as the last paragraph of 2.9, add `**Phase 6a (built).**` followed by: the date and branch (`Delivered <date> on phase-6-polish`), the real test count and the checklist's name (`docs/testing/phase-6a-manual-checklist.md`); then one line each for the six points of the plan header and for every other place where the build differs from the text above (a constant, a name, a string, a size or a behaviour, found by Step 1); then `Not built, by decision: the synthetic window shadow, the layer-backed freeze backdrop, the NSHostingView context-menu fallback and the file-promise drag-out fallback, each a follow-up only if Tim's checklist shows the failure it answers.`; then, as Phase 5's paragraph does, `Observations from the checklist run are still to be written down here by Tim:` the window-shadow probe (pass or fail, sizes) and the comparison with the system shot; the drag-out receiver table (accepted, name, whole, prompt) for Finder, Slack, Chrome, Safari, Mail, Messages and Notes; the freeze latency medians for one and two displays; and that none of the GUI checks had been run when this was written. Where a sentence of 2.9 is simply wrong after the build (a number, a name, a string), rewrite that sentence in place as well, as 4b did for 2.6.

Compare at least these against the code and rewrite 2.9 where they differ: the card size (340 x 104), spacing (10 pt), corner margin (16 pt) and the cap of 1 to 8 cards; the close reasons and the 10-id list; every exact string of Step 1; the drag file's folder, name and the 60 s delay; the shadow values if the synthetic shadow is built; the keys and defaults of `AppSettings`; the shortcut names and defaults; the file list in "Architecture" for the 6a files. For a divergence that looks like a bug rather than a decision (the code contradicts a sentence of 2.9 that was the intended behaviour), stop and report it; do not amend 2.9 to match a bug. Record every amendment as one line in the report.

Check the result:
```bash
grep -n "Delivered\|Phase 6a (built)" docs/superpowers/specs/2026-10-19-tidyshot-screenshot-design.md
grep -n "NSFilePromiseProvider" docs/superpowers/specs/2026-10-19-tidyshot-screenshot-design.md | cut -c1-140
grep -n "Dragging it out drags the local file\|probe may find\|made at drag start\|animate: true\|probes to run: .research.md" docs/superpowers/specs/2026-10-19-tidyshot-screenshot-design.md
```
Expected: the `Delivered` line in section 6 (next to Phase 5's and earlier ones) and the `Phase 6a (built)` paragraph in 2.9; `NSFilePromiseProvider` only in 2.9 (the "Why a file URL" paragraph, and the 6a paragraph if it names it) and nowhere in decision 6; no output from the third command.

- [ ] **Step 7: Commit**

```bash
git add docs/testing/phase-6a-manual-checklist.md README.md docs/superpowers/specs/2026-10-19-tidyshot-screenshot-design.md
git add docs/superpowers/plans/2026-10-21-phase-6a-overlay-and-capture-polish.md
git commit -m "docs: Phase 6a checklist, README and spec close-out"
```
The plan is in the list so that a Step 4 correction lands in this commit; when the table is unchanged, `git add` leaves it out. Check `git status` is clean afterwards.

- [ ] **Step 8: Stop here**

Phase 6a's code and documents are done when the last test run reads `Test run with 675 tests in 85 suites passed`; the checklist is left for Tim. Do not push and do not open a PR: the controller pushes and opens the PR after the whole-branch review. Report the final test line, that the checklist (with the three probes) is Tim's and was not run, every checklist, README or 2.9 sentence changed in Step 1 to follow the code, and every amendment made in Step 4 or Step 6.
