# TidyShot Phase 5: Scrolling Capture, Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Capture content taller than the screen: the user picks an area or window with Capture Scrolling (⌃⇧5), scrolls (manual mode) or lets TidyShot scroll (auto-scroll, behind the post-event permission), sees a live stitched preview, and on Done the stitched image goes through the normal save, overlay and upload path.

**Architecture:** New code in `TidyShot/Scrolling/` (spec 2.8): one `SCStream` per session with all of TidyShot excluded feeds BGRA frames to a pure `OverlapFinder` and `ScrollStitcher`; pure helpers (`FrameSettler`, `ScrollEndDetector`, `AutoScrollPlan`, `ScrollCaptureStatus`, `ScrollPanelGeometry`) carry every decision; a MainActor `ScrollCaptureSession` and controller drive a small panel; `AutoScrollDriver` posts scroll events through a `ScrollEventPoster`; `AppCoordinator.captureScrolling()` hands the stitched `ScaledImage` to the existing `save(_:)` path.

**Tech Stack:** Swift 6 language mode with default `MainActor` isolation and `NonisolatedNonsendingByDefault`, ScreenCaptureKit (`SCStream`, `SCStreamOutput`, `SCContentFilter` excluding applications), Core Graphics (`CGEvent` scroll-wheel events, `CGPreflightPostEventAccess`, `CGRequestPostEventAccess`, bitmap `CGContext`), AppKit (`NSPanel`, `NSHostingView`), KeyboardShortcuts, Swift Testing, XcodeGen 2.46.

Spec: `docs/superpowers/specs/2026-10-19-tidyshot-screenshot-design.md`, section 2.8 (all of it) and section 6 (Phase 5). Section 2.8 is the authority for behaviour, names and exact strings; when this plan and 2.8 disagree, stop and ask.

Builds on Phase 4 (plans `docs/superpowers/plans/2026-10-20-phase-4a-annotation-editor.md` and `2026-10-20-phase-4b-annotation-tools.md`, merged as PRs 7 and 9). Work happens on the branch `phase-5-scrolling`, created from `main` at 23fdff8, which also holds the spec commit e6bf136. Confirm:

```bash
git switch phase-5-scrolling
git merge-base --is-ancestor e6bf136 HEAD && echo SPEC_PRESENT
```
Expected: `Already on 'phase-5-scrolling'` (or `Switched to branch 'phase-5-scrolling'`) then `SPEC_PRESENT`.

## How code is specified in this plan

Each task gives the exact Swift interfaces it produces, complete Swift Testing test code, and complete code for pure helpers and algorithms (frame copy, overlap finder, stitcher, settling, end detection, step plan, panel geometry, the session and the driver). AppKit windows, the panel, the SwiftUI view and menu wiring are specified by structure, exact names, behaviour and hand checks, and the implementer writes that code. The tests and the interfaces are the contract: a reviewer rejects a task whose names, signatures, strings or test assertions differ from this plan or from spec 2.8.

Two decisions in this plan go beyond 2.8's text, and Task 7 writes both into 2.8: auto-scroll's `.shrinkStep` scrolls back by the lost step before halving it, and a `.still` on the very first auto-scroll step tries the other direction once before the end detector may end the session (Task 6).

## Global Constraints

- Every Phase 0 to 3.1 constraint still applies: minimum macOS `26.0`, Xcode 27.1 with the macOS 27.0 SDK, App Sandbox on with no new entitlements, Swift 6 language mode with `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` and `SWIFT_APPROACHABLE_CONCURRENCY = YES`, `KeyboardShortcuts` as the only package, credentials only in the Keychain, files in the save folder only through the security-scoped bookmark, thumbnails and upload-only files in the container next to `history.json`, one token engine for file names and object keys, keys named when the upload starts, HEAD before PUT for template keys, and no GPL-licensed code read or copied.
- New code lives in `TidyShot/Scrolling/` (plus the files spec 2.8 names in `Capture/`, `Selection/`, `App/` and `Output/`). New tests live in `TidyShotTests/`, shared helpers in `TidyShotTests/Support/`. XcodeGen's recursive source paths pick new folders up; run `xcodegen generate` after adding files.
- Concurrency: any `nonisolated async` function that must run off the main actor is marked `@concurrent`. Tests never block the main actor with a semaphore; fakes wait on an async gate.
- Tests use Swift Testing, run with:
  ```bash
  xcodegen generate && xcodebuild test -project TidyShot.xcodeproj -scheme TidyShot -destination 'platform=macOS' -derivedDataPath .build 2>&1 | grep -E "Test run with|error:|TEST"
  ```
  Baseline `Test run with 468 tests in 58 suites passed`; the totals after each task are in the table below.
- Commit after every task with a conventional commit message and no attribution lines. Never include a Claude Code session URL in a commit or PR. This plan never pushes or opens a PR: the last task stops after its commit, and the controller pushes and opens the PR after the whole-branch review.
- Phase 5 specifics:
  - One save path: the stitched image reaches records, the overlay, uploads and Annotate only through `AppCoordinator.save(_:)`. Nothing is written, recorded or uploaded before Done.
  - Stream frames are copied out of their `CVPixelBuffer` before the callback returns; stitching runs off the main actor; nothing blocks the main actor waiting for a frame.
  - Height cap `ScrollCaptureLimits.maxPixelHeight` = 16,384 px. Exact strings come from `ScrollCaptureStatus` and spec 2.8.
  - Auto-scroll posts events only while the pointer is over the captured area and only with the post-event permission granted; without it, manual mode works unchanged. No new entitlement. Whether posted events arrive after a real grant is a hand check for Tim (Task 6, Steps 9 and 11), never an agent's; the code is written and tested with fakes either way, and if delivery fails auto-scroll stays off, the panel's checkbox says why, and manual mode is unaffected.
  - Shortcut ⌃⇧5 (Capture Scrolling); Escape is a global hotkey only while a session runs.

## Test totals

| After | New tests | New suites | Total |
|---|---|---|---|
| Baseline | | | 468 tests in 58 suites |
| Task 1 | 27 | 3 | 495 tests in 61 suites |
| Task 2 | 44 | 6 | 539 tests in 67 suites |
| Task 3 | 5 | 2 | 544 tests in 69 suites |
| Task 4 | 3 | 1 | 547 tests in 70 suites |
| Task 5 | 7 | 1 | 554 tests in 71 suites |
| Task 6 | 11 | 1 | 565 tests in 72 suites |
| Task 7 | 0 | 0 | 565 tests in 72 suites |

The totals come from each task's declared tests. Task 7 checks them against a real run and adds a note for any difference.

---

### Task 1: Stitching core

**Files:**
- Create: `TidyShot/Scrolling/ScrollCaptureLimits.swift`
- Create: `TidyShot/Scrolling/ScrollFrame.swift`
- Create: `TidyShot/Scrolling/OverlapFinder.swift`
- Create: `TidyShot/Scrolling/ScrollStitcher.swift`
- Create: `TidyShotTests/Support/SyntheticPage.swift` (shared test helper, no tests of its own)
- Test: `TidyShotTests/ScrollFrameTests.swift` (new suite `ScrollFrameTests`)
- Test: `TidyShotTests/OverlapFinderTests.swift` (new suite `OverlapFinderTests`)
- Test: `TidyShotTests/ScrollStitcherTests.swift` (new suite `ScrollStitcherTests`)

**Interfaces:**
- Consumes: nothing from `main` or earlier tasks. Only Foundation and Core Graphics. `TidyShotTests/Support/` does not exist yet; this task creates it. `xcodegen generate` picks up `TidyShot/Scrolling/` and `Support/` through the recursive source paths in `project.yml` (`project.yml:24` and `:66`).
- Produces (all `nonisolated`, `Sendable`; later tasks rely on these names):
  - `ScrollCaptureLimits`: `maxPixelHeight = 16_384`, `minimumAreaHeightPoints: CGFloat = 100`, `scrollbarStripPoints: CGFloat = 16`, `previewMaxWidth = 360`.
  - `ScrollFrame { width: Int; height: Int; bgra: Data; gray: [UInt8] }` with `init(bgra: UnsafeRawPointer, width:height:bytesPerRow:)` (copies the rows out, packs them, builds the grey plane) and `init(bgra: Data, width:height:bytesPerRow:)`.
  - `OverlapMatch`: `.still`, `.moved(dy: Int, top: Int, bandEnd: Int, score: Double)`, `.lost`. `OverlapFinder` with `init(scale: CGFloat = 2)`, `init(scrollbarColumns: Int)` and `find(previous: ScrollFrame, current: ScrollFrame, predicted: Int?) -> OverlapMatch`.
  - `StitchedImage { width; height; bgra: Data }`, `StitchStep { match: OverlapMatch; committedRows: Int; isFull: Bool }` and `PreviewStrip { width; height; bgra: Data; isEmpty }`.
  - `ScrollStitcher` with `init(first: ScrollFrame, maxPixelHeight: Int = ScrollCaptureLimits.maxPixelHeight, finder: OverlapFinder = OverlapFinder())`, `mutating add(_ frame: ScrollFrame, predicted: Int? = nil) -> StitchStep`, `mutating finish() -> StitchedImage`, `mutating previewRows(maxWidth: Int = ScrollCaptureLimits.previewMaxWidth) -> PreviewStrip`, `isFull`, `committedHeight`, `width`.
  - Test side: `SyntheticPage` (frames and the ideal stitched image), reused by Task 3's engine test.

Behaviour (spec 2.8, Overlap finder and Stitcher). This is the stitching probe's `stitch.swift` as production code: the algorithm, the constants and the five scenarios are the probe's. Where the code differs from the probe, on purpose:
- The finder reads `ScrollFrame.gray`, and its scrollbar strip is a constructor value (`16 * scale` columns), so tests with small frames can set it.
- Ties between equally voted shifts end with the forward one, so the result never depends on dictionary order. Frames of different sizes give `.lost` instead of trapping.
- The stitcher starts a commit at the first row the output lacks (`committedHeight - offset`), not at the pair's measured header height, and has no precondition on it. In content coordinates the two are the same unless a pair over-reads a header, and then this keeps the output contiguous instead of trapping. `add` also ignores frames once the output is full, and takes an optional `predicted` shift (auto mode passes its posted step; without it the last accepted shift is used).
- `StitchStep` wraps the finder's `OverlapMatch` with the rows committed and the cap flag, so Task 2's `ScrollEndDetector` and Task 3's `StitchProgress` take `step.match` and `step.isFull`.

Test geometry: the synthetic frames are 160 by 900 pixels, with the probe's row geometry (80 row header, 50 row footer, 770 row band, 9,000 row page, a 40 row animated square), a 40 column sidebar, an 8 column scrollbar and 112 page columns. Only the width is narrower than the probe's 1200, to keep the Debug test run short. The scenarios use the probe's step lists unchanged.

- [ ] **Step 1: Write the failing tests**

`TidyShotTests/Support/SyntheticPage.swift` (new folder and file). It renders the page and the frames, and compares a stitched image with the ideal one:
```swift
import Foundation
@testable import TidyShot

/// A tall synthetic page and the frames a scrolling viewer shows of it, as the stitching probe
/// rendered them (spec 2.8, Tests). A frame is `width` by `height` pixels: a sticky header on top,
/// a sticky footer at the bottom, a fixed sidebar on the left and a scrollbar on the right whose
/// thumb moves with the scroll offset. In between, the band shows rows `offset..<offset + band` of
/// the page. An optional animated square sits at a fixed screen position and changes every frame.
///
/// The page is text lines (pixel rows that differ glyph row by glyph row), blank gaps, repeated
/// list items and noisy image blocks, so it has the content that defeats naive matching.
nonisolated struct SyntheticPage {
    let width: Int
    let height: Int
    let header: Int
    let footer: Int
    let sidebar: Int
    let scrollbar: Int
    let pageHeight: Int
    let spinnerWidth: Int
    let spinnerHeight: Int
    let spinnerX: Int
    /// Rows below the header where the spinner starts.
    let spinnerY: Int
    /// The page's pixels, `pageWidth * pageHeight`, grey.
    let page: [UInt8]
    private var frameNumber = 0

    var bandHeight: Int { height - header - footer }
    var pageWidth: Int { width - sidebar - scrollbar }
    /// The largest offset the viewer can scroll to.
    var maxOffset: Int { pageHeight - bandHeight }
    /// The finder these frames need: it ignores the scrollbar's columns plus a pixel or two.
    var finder: OverlapFinder { OverlapFinder(scrollbarColumns: scrollbar + 2) }

    init(width: Int = 160, height: Int = 900, header: Int = 80, footer: Int = 50, sidebar: Int = 40,
         scrollbar: Int = 8, pageHeight: Int = 9000, seed: UInt64 = 42, period: Int? = nil) {
        self.width = width
        self.height = height
        self.header = header
        self.footer = footer
        self.sidebar = sidebar
        self.scrollbar = scrollbar
        self.pageHeight = pageHeight
        spinnerWidth = 12
        spinnerHeight = 40
        spinnerX = 100
        spinnerY = 200
        let pageWidth = width - sidebar - scrollbar
        page = period.map { Self.periodicPage(width: pageWidth, height: pageHeight, period: $0, seed: seed) }
            ?? Self.mixedPage(width: pageWidth, height: pageHeight, seed: seed)
    }

    // MARK: Fixed pieces

    func headerPixel(_ x: Int, _ y: Int) -> UInt8 { UInt8(100 + (x * 7 + y * 13) % 120) }
    func footerPixel(_ x: Int, _ y: Int) -> UInt8 { UInt8(60 + (x * 11 + y * 5) % 90) }
    func sidebarPixel(_ x: Int, _ y: Int) -> UInt8 { UInt8(200 + (x + y) % 40) }

    // MARK: Frames

    /// The frame at scroll offset `offset`. `thumbTop` overrides where the scrollbar thumb is drawn.
    mutating func frame(at offset: Int, animated: Bool = true, scrollbarVisible: Bool = true,
                        thumbTop: Int? = nil) -> ScrollFrame {
        frameNumber += 1
        var generator = LCG(seed: UInt64(frameNumber) &* 7919)
        var bgra = [UInt8](repeating: 255, count: width * height * 4)
        let thumb = thumbTop ?? header + (offset * bandHeight) / pageHeight
        for y in 0..<height {
            for x in 0..<width {
                let value: UInt8
                if y < header {
                    value = headerPixel(x, y)
                } else if y >= height - footer {
                    value = footerPixel(x, y)
                } else if x < sidebar {
                    value = sidebarPixel(x, y)
                } else if x >= width - scrollbar {
                    value = scrollbarVisible && y >= thumb && y < thumb + 20 ? 120 : 245
                } else {
                    let pageY = offset + (y - header)
                    value = pageY < pageHeight ? page[pageY * pageWidth + (x - sidebar)] : 250
                }
                let i = (y * width + x) * 4
                bgra[i] = value; bgra[i + 1] = value; bgra[i + 2] = value
            }
        }
        if animated {
            for y in (header + spinnerY)..<(header + spinnerY + spinnerHeight) {
                for x in spinnerX..<(spinnerX + spinnerWidth) {
                    let v = UInt8(truncatingIfNeeded: generator.next())
                    let i = (y * width + x) * 4
                    bgra[i] = v; bgra[i + 1] = v; bgra[i + 2] = v
                }
            }
        }
        return ScrollFrame(bgra: Data(bgra), width: width, height: height, bytesPerRow: width * 4)
    }

    /// An all-blank frame of the same size.
    func blankFrame() -> ScrollFrame {
        ScrollFrame(bgra: Data(repeating: 255, count: width * height * 4), width: width, height: height,
                    bytesPerRow: width * 4)
    }

    // MARK: Expected output

    struct Comparison {
        let expectedHeight: Int
        let actualHeight: Int
        /// Page-column pixels that differ from the ideal tall image.
        let mismatched: Int
        /// Of those, the ones outside the animated square's columns.
        let mismatchedOutsideSpinner: Int
    }

    /// Compares a stitched image with the ideal one for a scroll that reached `reached`:
    /// header, page rows `0..<reached + band`, footer. Only the page's columns are compared; the
    /// sidebar and the scrollbar differ by design.
    func compare(_ out: StitchedImage, reached: Int) -> Comparison {
        let expectedHeight = header + reached + bandHeight + footer
        var bad = 0, badOutside = 0
        for y in 0..<min(out.height, expectedHeight) {
            for x in sidebar..<(width - scrollbar) {
                let want: UInt8
                if y < header { want = headerPixel(x, y) }
                else if y >= expectedHeight - footer { want = footerPixel(x, y - (expectedHeight - height)) }
                else { want = page[(y - header) * pageWidth + (x - sidebar)] }
                if out.bgra[(y * out.width + x) * 4] != want {
                    bad += 1
                    if !(spinnerX..<(spinnerX + spinnerWidth)).contains(x) { badOutside += 1 }
                }
            }
        }
        return Comparison(expectedHeight: expectedHeight, actualHeight: out.height, mismatched: bad,
                          mismatchedOutsideSpinner: badOutside)
    }

    /// The B channel of output pixel (x, y).
    static func value(_ image: StitchedImage, _ x: Int, _ y: Int) -> UInt8 { image.bgra[(y * image.width + x) * 4] }

    // MARK: Page generators

    struct LCG {
        var state: UInt64
        init(seed: UInt64) { state = seed }
        mutating func next() -> UInt64 {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return state >> 33
        }
    }

    /// Text, gaps, list items and image blocks, as the probe generated them.
    static func mixedPage(width: Int, height: Int, seed: UInt64) -> [UInt8] {
        var g = LCG(seed: seed)
        let margin = min(20, width / 8)
        var px = [UInt8](repeating: 250, count: width * height)
        var y = 0
        while y < height {
            let kind = g.next() % 10
            if kind < 5 {                       // a text line: 22 rows, glyph strokes differ per pixel row
                let lineHeight = 22
                for yy in y..<min(height, y + lineHeight) where (yy - y) > 4 && (yy - y) < 18 {
                    var x = margin
                    var g2 = LCG(seed: UInt64(y) &* 31 &+ seed)
                    while x < width - margin {
                        let run = Int(g2.next() % 14) + 3
                        let ink = g2.next() % 3 == 0
                        let glyph = Int(g2.next() % 97)
                        let r = yy - y
                        for xx in x..<min(width, x + run) {
                            px[yy * width + xx] = ink && ((xx * 3 + r * glyph) % 7 < 3) ? UInt8(30 + (glyph % 60)) : 250
                        }
                        x += run
                    }
                }
                y += lineHeight + 8
            } else if kind < 7 {                // a blank gap
                y += Int(g.next() % 60) + 10
            } else if kind < 9 {                // a repeated list item: identical rows
                let itemHeight = 40
                for yy in y..<min(height, y + itemHeight) {
                    for xx in margin..<(width / 2) {
                        px[yy * width + xx] = (yy - y) < 2 ? 180 : ((xx / 7 + (yy - y)) % 5 == 0 ? 90 : 240)
                    }
                }
                y += itemHeight
            } else {                            // an image block: gradient plus noise
                let blockHeight = Int(g.next() % 200) + 80
                for yy in y..<min(height, y + blockHeight) {
                    for xx in (2 * margin)..<(width - 2 * margin) { px[yy * width + xx] = UInt8((xx + yy * 3 + Int(g.next() % 7)) & 0xff) }
                }
                y += blockHeight + 10
            }
        }
        return px
    }

    /// `period` rows of noise repeated down the page, for tests of repeated content.
    static func periodicPage(width: Int, height: Int, period: Int, seed: UInt64) -> [UInt8] {
        var g = LCG(seed: seed)
        let base = (0..<(width * period)).map { _ in UInt8(truncatingIfNeeded: g.next()) }
        var px = [UInt8](repeating: 0, count: width * height)
        for y in 0..<height {
            for x in 0..<width { px[y * width + x] = base[(y % period) * width + x] }
        }
        return px
    }
}
```

`TidyShotTests/ScrollFrameTests.swift`:
```swift
import Foundation
import Testing
@testable import TidyShot

struct ScrollFrameTests {
    /// BGRA bytes of one pixel.
    func pixel(r: UInt8, g: UInt8, b: UInt8) -> [UInt8] { [b, g, r, 255] }

    @Test func greyIsTheIntegerLuminanceOfEachPixel() {
        var pixels: [UInt8] = []
        for (r, g, b) in [(0, 0, 0), (255, 255, 255), (255, 0, 0), (0, 255, 0), (0, 0, 255), (30, 20, 10)] as [(UInt8, UInt8, UInt8)] {
            pixels += pixel(r: r, g: g, b: b)
        }
        let frame = ScrollFrame(bgra: Data(pixels), width: 3, height: 2, bytesPerRow: 12)
        // (77 R + 150 G + 29 B) >> 8
        #expect(frame.gray == [0, 255, 76, 149, 28, 21])
        #expect(frame.width == 3)
        #expect(frame.height == 2)
        #expect(frame.bgra == Data(pixels))
    }

    /// Rows from a `CVPixelBuffer` are padded; the frame packs them.
    @Test func paddedRowsAreRepacked() {
        let row0: [UInt8] = pixel(r: 10, g: 20, b: 30) + pixel(r: 40, g: 50, b: 60)
        let row1: [UInt8] = pixel(r: 70, g: 80, b: 90) + pixel(r: 100, g: 110, b: 120)
        let padding = [UInt8](repeating: 0xEE, count: 8)
        let padded = Data(row0 + padding + row1)
        let frame = ScrollFrame(bgra: padded, width: 2, height: 2, bytesPerRow: 16)
        #expect(frame.bgra == Data(row0 + row1))
        #expect(frame.gray.count == 4)
        let expected: Int = (77 * 70 + 150 * 80 + 29 * 90) >> 8
        #expect(Int(frame.gray[2]) == expected)
    }

    @Test func thePointerInitCopiesIntoTheFrame() {
        var bytes: [UInt8] = pixel(r: 1, g: 2, b: 3) + pixel(r: 4, g: 5, b: 6)
        let original = Data(bytes)
        let frame = bytes.withUnsafeBytes { ScrollFrame(bgra: $0.baseAddress!, width: 2, height: 1, bytesPerRow: 8) }
        bytes[0] = 99
        #expect(frame.bgra == original)
    }
}
```

`TidyShotTests/OverlapFinderTests.swift`:
```swift
import Foundation
import Testing
@testable import TidyShot

struct OverlapFinderTests {
    /// The finder's verdict for a viewer scrolled from offset `a` to offset `b`.
    func match(_ page: inout SyntheticPage, from a: Int, to b: Int, predicted: Int? = nil,
               animated: Bool = true) -> OverlapMatch {
        let before = page.frame(at: a, animated: animated)
        let after = page.frame(at: b, animated: animated)
        return page.finder.find(previous: before, current: after, predicted: predicted)
    }

    func dy(of match: OverlapMatch) -> Int? {
        if case .moved(let dy, _, _, _) = match { return dy }
        return nil
    }

    @Test func findsTheExactShiftForStepsFromOneRowToNearlyTheBand() {
        var page = SyntheticPage()
        // 462 is 60 % of the 770 row band, 754 leaves 16 rows of overlap. That overlap has to hold
        // text, which the page does at offset 400 (blank stretches would make the pair lost).
        for step in [1, 3, 40, 462, page.bandHeight - 16] {
            let result = match(&page, from: 400, to: 400 + step)
            #expect(dy(of: result) == step, "step \(step) gave \(result)")
        }
    }

    @Test func identicalFramesAreStill() {
        var page = SyntheticPage()
        #expect(match(&page, from: 800, to: 800, animated: false) == .still)
    }

    /// A spinner, caret or GIF must not read as movement, and must not make the pair lost.
    @Test func framesDifferingOnlyInTheAnimatedSquareAreStill() {
        var page = SyntheticPage()
        #expect(match(&page, from: 800, to: 800, animated: true) == .still)
    }

    @Test func measuresTheStickyHeaderAndFooter() {
        var page = SyntheticPage()
        guard case .moved(let dy, let top, let bandEnd, let score) = match(&page, from: 600, to: 700) else {
            Issue.record("not moved")
            return
        }
        #expect(dy == 100)
        #expect(top == page.header)
        #expect(bandEnd == page.height - page.footer)
        #expect(score >= 0.8)
    }

    @Test func aWideFixedSidebarIsIgnored() {
        var page = SyntheticPage(width: 260, sidebar: 140)
        #expect(dy(of: match(&page, from: 600, to: 640)) == 40)
        #expect(dy(of: match(&page, from: 600, to: 1062)) == 462)
    }

    /// The scrollbar's columns are never hashed, so a thumb that moved with no content change is still.
    @Test func scrollbarThumbMovementIsIgnored() {
        var page = SyntheticPage()
        let before = page.frame(at: 800, animated: false, thumbTop: 40)
        let after = page.frame(at: 800, animated: false, thumbTop: 120)
        #expect(before.gray != after.gray)
        #expect(page.finder.find(previous: before, current: after, predicted: nil) == .still)
    }

    /// Rows that repeat every 230 rows (a 900 row band holds each at most four times): a shift of
    /// 115 matches as +115 and as -115 with equal votes, and the prediction (or, without one, the
    /// forward direction) picks between them.
    @Test func repeatedContentIsResolvedByThePrediction() {
        var page = SyntheticPage(header: 0, footer: 0, sidebar: 0, scrollbar: 0, period: 230)
        #expect(dy(of: match(&page, from: 0, to: 115, predicted: 115, animated: false)) == 115)
        #expect(dy(of: match(&page, from: 0, to: 115, predicted: -115, animated: false)) == -115)
        #expect(dy(of: match(&page, from: 0, to: 115, predicted: nil, animated: false)) == 115)
    }

    @Test func aStepLargerThanTheBandIsLost() {
        var page = SyntheticPage()
        #expect(match(&page, from: 600, to: 1500) == .lost)
    }

    @Test func scrollingBackUpGivesANegativeShift() {
        var page = SyntheticPage()
        #expect(dy(of: match(&page, from: 700, to: 550)) == -150)
    }

    @Test func anAllBlankPairIsStill() {
        let page = SyntheticPage()
        #expect(page.finder.find(previous: page.blankFrame(), current: page.blankFrame(), predicted: nil) == .still)
    }

    @Test func framesOfDifferentSizesAreLost() {
        var page = SyntheticPage()
        var other = SyntheticPage(height: 880)
        let result = page.finder.find(previous: page.frame(at: 0), current: other.frame(at: 0), predicted: nil)
        #expect(result == .lost)
    }

    @Test func scaleSetsTheScrollbarStrip() {
        #expect(OverlapFinder(scale: 2).scrollbarColumns == 32)
        #expect(OverlapFinder(scale: 1).scrollbarColumns == 16)
    }
}
```

`TidyShotTests/ScrollStitcherTests.swift`:
```swift
import Foundation
import Testing
@testable import TidyShot

struct ScrollStitcherTests {
    struct Run {
        var image: StitchedImage
        var reached: Int
        var frames: Int
        var moved = 0, still = 0, lost = 0, backwards = 0
    }

    /// Drives a viewer through `steps` (rows scrolled between frames, clamped to the page) and
    /// finishes. The viewer starts at offset 0.
    func run(_ page: inout SyntheticPage, steps: [Int], animated: Bool = true, scrollbarVisible: Bool = true,
             maxPixelHeight: Int = ScrollCaptureLimits.maxPixelHeight) -> Run {
        var stitcher = ScrollStitcher(first: page.frame(at: 0, animated: animated, scrollbarVisible: scrollbarVisible),
                                      maxPixelHeight: maxPixelHeight, finder: page.finder)
        var offset = 0
        var counts = (moved: 0, still: 0, lost: 0, backwards: 0)
        for step in steps {
            offset = max(0, min(page.maxOffset, offset + step))
            let result = stitcher.add(page.frame(at: offset, animated: animated, scrollbarVisible: scrollbarVisible))
            switch result.match {
            case .still: counts.still += 1
            case .lost: counts.lost += 1
            case .moved(let dy, _, _, _): if dy > 0 { counts.moved += 1 } else { counts.backwards += 1 }
            }
        }
        let image = stitcher.finish()
        return Run(image: image, reached: offset, frames: steps.count + 1, moved: counts.moved, still: counts.still,
                   lost: counts.lost, backwards: counts.backwards)
    }

    /// The stitched image equals header + page + footer, apart from the animated square.
    func expectExact(_ run: Run, _ page: SyntheticPage, animated: Bool, sourceLocation: SourceLocation = #_sourceLocation) {
        let comparison = page.compare(run.image, reached: run.reached)
        #expect(comparison.actualHeight == comparison.expectedHeight, sourceLocation: sourceLocation)
        #expect(comparison.mismatchedOutsideSpinner == 0, sourceLocation: sourceLocation)
        let allowed = animated ? page.spinnerWidth * page.spinnerHeight * run.frames : 0
        #expect(comparison.mismatched <= allowed, "\(comparison.mismatched) mismatched", sourceLocation: sourceLocation)
    }

    // MARK: The probe's five scenarios, with the probe's steps

    /// Auto mode: 60 % of the band per step down to the end, then still frames.
    @Test func autoSixtyPercentStepsToTheEnd() {
        var page = SyntheticPage()
        let result = run(&page, steps: Array(repeating: 462, count: 20) + [0, 0])
        #expect(result.reached == page.maxOffset)
        #expect(result.lost == 0)
        #expect(result.still >= 2)
        expectExact(result, page, animated: true)
    }

    /// Manual mode: irregular small and large steps, a scroll back up and a momentum tail.
    @Test func manualIrregularStepsWithAScrollBack() {
        var page = SyntheticPage()
        let steps = [12, 40, 90, 180, 300, 420, 500, 380, 200, 90, 30, 6, 2, 0, -150, 60, 200, 400, 600, 640, 300, 100, 20, 0]
        let result = run(&page, steps: steps)
        #expect(result.lost == 0)
        #expect(result.backwards >= 1)
        expectExact(result, page, animated: true)
    }

    /// One jump larger than the band loses the place; scrolling back into overlap recovers against
    /// the last accepted frame and nothing is missing.
    @Test func tooFastThenRecover() {
        var page = SyntheticPage()
        let result = run(&page, steps: [300, 300, 900, -500, 200, 300])
        #expect(result.lost == 1)
        #expect(result.reached == 1500)
        expectExact(result, page, animated: true)
    }

    @Test func plainPageWithNoScrollbarAndNoSpinner() {
        var page = SyntheticPage()
        let result = run(&page, steps: Array(repeating: 500, count: 18), animated: false, scrollbarVisible: false)
        #expect(result.lost == 0)
        expectExact(result, page, animated: false)
    }

    /// Smooth scrolling caught mid-animation: thirty steps of 1 row and thirty of 3.
    @Test func tinySteps() {
        var page = SyntheticPage()
        let result = run(&page, steps: Array(repeating: 1, count: 30) + Array(repeating: 3, count: 30))
        #expect(result.lost == 0)
        #expect(result.reached == 120)
        expectExact(result, page, animated: true)
    }

    // MARK: Edge cases

    @Test func aSingleFrameFinishesAsItself() {
        var page = SyntheticPage()
        let first = page.frame(at: 400, animated: false)
        var stitcher = ScrollStitcher(first: first, finder: page.finder)
        #expect(stitcher.committedHeight == 0)
        let image = stitcher.finish()
        #expect(image.width == page.width)
        #expect(image.height == page.height)
        #expect(image.bgra == first.bgra)
        #expect(stitcher.committedHeight == page.height)
    }

    @Test func stillAndLostFramesCommitNothing() {
        var page = SyntheticPage()
        var stitcher = ScrollStitcher(first: page.frame(at: 0, animated: false), finder: page.finder)
        let still = stitcher.add(page.frame(at: 0, animated: false))
        #expect(still == StitchStep(match: .still, committedRows: 0, isFull: false))
        let lost = stitcher.add(page.frame(at: 2100, animated: false))
        #expect(lost == StitchStep(match: .lost, committedRows: 0, isFull: false))
        #expect(stitcher.committedHeight == 0)
        // Back inside the overlap: the first forward move commits the first frame's rows to its band end.
        let moved = stitcher.add(page.frame(at: 300, animated: false))
        #expect(moved.committedRows == page.height - page.footer)
        #expect(stitcher.committedHeight == page.height - page.footer)
    }

    /// The footer is the last frame's and appears once, at the very end.
    @Test func theFooterAppearsOnce() {
        var page = SyntheticPage()
        let result = run(&page, steps: Array(repeating: 462, count: 20), animated: false)
        let image = result.image
        func rowMatchesFooter(_ y: Int, footerRow k: Int) -> Bool {
            (page.sidebar..<(page.width - page.scrollbar)).allSatisfy {
                SyntheticPage.value(image, $0, y) == page.footerPixel($0, page.height - page.footer + k)
            }
        }
        let firstFooterRow = image.height - page.footer
        for k in 0..<page.footer { #expect(rowMatchesFooter(firstFooterRow + k, footerRow: k)) }
        // No row above the footer is a footer row, so no pair committed one in the middle.
        #expect((0..<firstFooterRow).allSatisfy { !rowMatchesFooter($0, footerRow: 0) })
    }

    @Test func outputStopsAtTheCapExactly() {
        var page = SyntheticPage()
        var stitcher = ScrollStitcher(first: page.frame(at: 0, animated: false), maxPixelHeight: 2000, finder: page.finder)
        var offset = 0
        var fullAt: Int?
        for i in 0..<12 {
            offset += 462
            let step = stitcher.add(page.frame(at: offset, animated: false))
            #expect(stitcher.committedHeight <= 2000)
            if step.isFull, fullAt == nil { fullAt = i }
        }
        #expect(stitcher.isFull)
        #expect(stitcher.committedHeight == 2000)
        #expect(fullAt != nil)
        // Frames after the cap are ignored.
        let after = stitcher.add(page.frame(at: offset + 462, animated: false))
        #expect(after == StitchStep(match: .still, committedRows: 0, isFull: true))
        let image = stitcher.finish()
        #expect(image.height == 2000)
        #expect(image.bgra.count == 2000 * page.width * 4)
        // The 2000 rows are the top of the ideal image.
        let comparison = page.compare(image, reached: 2000)
        #expect(comparison.mismatched == 0)
    }

    @Test func aCapShorterThanTheFirstFrameCutsIt() {
        var page = SyntheticPage()
        var stitcher = ScrollStitcher(first: page.frame(at: 0, animated: false), maxPixelHeight: 100, finder: page.finder)
        let image = stitcher.finish()
        #expect(image.height == 100)
        #expect(stitcher.isFull)
    }

    // MARK: Preview

    @Test func previewRowsAreTheBoxAverageOfWhatWasCommittedSinceTheLastCall() {
        var page = SyntheticPage()
        var stitcher = ScrollStitcher(first: page.frame(at: 0, animated: false), finder: page.finder)
        #expect(stitcher.previewRows(maxWidth: 40).isEmpty)
        _ = stitcher.add(page.frame(at: 462, animated: false))
        let first = stitcher.previewRows(maxWidth: 40)
        #expect(first.width == 40)
        #expect(first.height == stitcher.committedHeight / 4)
        #expect(stitcher.previewRows(maxWidth: 40).isEmpty)
        _ = stitcher.add(page.frame(at: 924, animated: false))
        let second = stitcher.previewRows(maxWidth: 40)
        let committed = stitcher.committedHeight
        #expect(first.height + second.height == committed / 4)

        // Compare with the average of the same 4 by 4 boxes of the finished image.
        var copy = stitcher
        let image = copy.finish()
        func average(_ ox: Int, _ oy: Int, channel: Int) -> UInt8 {
            var sum = 0
            for fy in 0..<4 { for fx in 0..<4 { sum += Int(image.bgra[((oy * 4 + fy) * image.width + ox * 4 + fx) * 4 + channel]) } }
            return UInt8((sum + 8) / 16)
        }
        for (ox, oy) in [(0, 0), (37, 5), (39, first.height - 1)] {
            for channel in 0..<4 {
                #expect(first.bgra[(oy * first.width + ox) * 4 + channel] == average(ox, oy, channel: channel))
            }
        }
        for (ox, oy) in [(0, 0), (20, second.height - 1)] {
            for channel in 0..<4 {
                #expect(second.bgra[(oy * second.width + ox) * 4 + channel] == average(ox, first.height + oy, channel: channel))
            }
        }
    }

    @Test func previewIsACopyWhenTheFrameIsNarrow() {
        var page = SyntheticPage()
        var stitcher = ScrollStitcher(first: page.frame(at: 0, animated: false), finder: page.finder)
        let strip = stitcher.previewRows(maxWidth: page.width)
        #expect(strip.isEmpty)
        #expect(strip.width == page.width)
        _ = stitcher.add(page.frame(at: 100, animated: false))
        let rows = stitcher.previewRows(maxWidth: page.width)
        #expect(rows.width == page.width)
        #expect(rows.height == stitcher.committedHeight)
    }
}
```

- [ ] **Step 2: Run them and see them fail**

Run:
```bash
xcodegen generate && xcodebuild test -project TidyShot.xcodeproj -scheme TidyShot -destination 'platform=macOS' -derivedDataPath .build 2>&1 | grep -E "Test run with|error:|TEST"
```
Expected: the build fails with `error:` lines such as `cannot find 'ScrollFrame' in scope`, `cannot find 'OverlapFinder' in scope`, `cannot find 'ScrollStitcher' in scope` and `cannot find 'ScrollCaptureLimits' in scope`, and no test runs.

- [ ] **Step 3: Implement**

`TidyShot/Scrolling/ScrollCaptureLimits.swift`:
```swift
import CoreGraphics

/// Numbers shared by the scrolling capture code (spec 2.8).
nonisolated enum ScrollCaptureLimits {
    /// The stitched image never grows past this many pixel rows (8,192 pt at 2x). The editor shows a
    /// capture as one texture, and 16,384 is within every Apple GPU's limit.
    static let maxPixelHeight = 16_384
    /// A selected area shorter than this many points is refused.
    static let minimumAreaHeightPoints: CGFloat = 100
    /// The rightmost columns, in points, that matching ignores: overlay scrollbars appear and move.
    static let scrollbarStripPoints: CGFloat = 16
    /// The live preview is at most this many pixels wide.
    static let previewMaxWidth = 360
}
```

`TidyShot/Scrolling/ScrollFrame.swift`:
```swift
import Foundation

/// One captured frame of the scrolled area: tightly packed BGRA plus a grey plane for matching.
/// Built on the stream's sample-handler queue (spec 2.8, Frame source), so it is a plain value.
nonisolated struct ScrollFrame: Sendable {
    let width: Int
    let height: Int
    /// `width * height * 4` bytes, rows packed with no padding, blue first.
    let bgra: Data
    /// `width * height` bytes of luminance, `(77 R + 150 G + 29 B) >> 8` (white stays 255).
    let gray: [UInt8]

    /// Copies `height` rows of `width` BGRA pixels out of `source`, whose rows are `bytesPerRow`
    /// apart, so the caller can release a `CVPixelBuffer` as soon as this returns.
    init(bgra source: UnsafeRawPointer, width: Int, height: Int, bytesPerRow: Int) {
        precondition(width > 0 && height > 0 && bytesPerRow >= width * 4, "bad frame geometry")
        let rowBytes = width * 4
        var plane = [UInt8](repeating: 0, count: width * height)
        var packed = Data(count: rowBytes * height)
        packed.withUnsafeMutableBytes { out in
            plane.withUnsafeMutableBufferPointer { grey in
                for y in 0..<height {
                    let row = source.advanced(by: y * bytesPerRow).assumingMemoryBound(to: UInt8.self)
                    (out.baseAddress! + y * rowBytes).copyMemory(from: row, byteCount: rowBytes)
                    for x in 0..<width {
                        let p = row + x * 4
                        grey[y * width + x] = UInt8((77 * Int(p[2]) + 150 * Int(p[1]) + 29 * Int(p[0])) >> 8)
                    }
                }
            }
        }
        self.width = width
        self.height = height
        self.bgra = packed
        self.gray = plane
    }

    init(bgra source: Data, width: Int, height: Int, bytesPerRow: Int) {
        precondition(source.count >= bytesPerRow * (height - 1) + width * 4, "bgra is too short")
        self = source.withUnsafeBytes {
            ScrollFrame(bgra: $0.baseAddress!, width: width, height: height, bytesPerRow: bytesPerRow)
        }
    }
}
```

`TidyShot/Scrolling/OverlapFinder.swift`:
```swift
import CoreGraphics

/// How a new frame relates to the last accepted one (spec 2.8, Overlap finder).
nonisolated enum OverlapMatch: Equatable, Sendable {
    /// Nothing that matters moved.
    case still
    /// The content moved up by `dy` rows: row y of the new frame shows row y + dy of the old one.
    /// A negative `dy` is a scroll back up. Rows before `top` are a sticky header and rows from
    /// `bandEnd` on a sticky footer.
    case moved(dy: Int, top: Int, bandEnd: Int, score: Double)
    /// No believable overlap (scrolled further than the band, or nothing to match on).
    case lost
}

/// Finds how far the content of a frame moved relative to the previous frame. Pure.
nonisolated struct OverlapFinder: Sendable {
    /// The rightmost columns that are never hashed.
    var scrollbarColumns: Int
    /// A row hash seen more often than this in a band is uninformative (blank rows, rules, list items).
    var maxRepeat = 4
    /// This fraction of informative rows equal at the same y means nothing moved.
    var stillFraction = 0.9
    /// A candidate shift needs this fraction of its informative cells to agree.
    var acceptScore = 0.8
    var minInformativeRows = 8
    /// The header and the footer are each at most this fraction of the frame.
    var maxStaticFraction = 0.4
    /// Each row of the band is hashed in this many vertical stripes, so an animated element
    /// spoils one stripe of the rows it covers instead of whole rows.
    var stripes = 8

    init(scale: CGFloat = 2) {
        scrollbarColumns = Int((ScrollCaptureLimits.scrollbarStripPoints * scale).rounded())
    }

    init(scrollbarColumns: Int) {
        self.scrollbarColumns = scrollbarColumns
    }

    func find(previous a: ScrollFrame, current b: ScrollFrame, predicted: Int?) -> OverlapMatch {
        guard a.width == b.width, a.height == b.height else { return .lost }
        let h = a.height
        let usable = Array(0..<max(1, a.width - scrollbarColumns))

        // 1. Still: informative rows equal at the same y.
        let fa = rowHashes(a, columns: usable), fb = rowHashes(b, columns: usable)
        let freqA = counts(fa[...])
        var informative = 0, same = 0
        for y in 0..<h where freqA[fa[y]]! <= maxRepeat {
            informative += 1
            if fa[y] == fb[y] { same += 1 }
        }
        if informative == 0 || Double(same) / Double(informative) >= stillFraction { return .still }

        // 2. Moving columns: drop columns identical at the same position in every row (fixed sidebars).
        var moving: [Int] = []
        a.gray.withUnsafeBufferPointer { pa in
            b.gray.withUnsafeBufferPointer { pb in
                for x in usable {
                    var y = 0
                    while y < h && pa[y * a.width + x] == pb[y * a.width + x] { y += 1 }
                    if y < h { moving.append(x) }
                }
            }
        }
        if moving.isEmpty { return .still }
        let per = max(1, (moving.count + stripes - 1) / stripes)
        let groups = stride(from: 0, to: moving.count, by: per).map { Array(moving[$0..<min(moving.count, $0 + per)]) }
        let ha = groups.map { rowHashes(a, columns: $0) }, hb = groups.map { rowHashes(b, columns: $0) }
        let whole = rowHashes(a, columns: moving), wholeB = rowHashes(b, columns: moving)

        // 3. Header and footer: rows equal at the same y from each edge.
        let cap = Int(Double(h) * maxStaticFraction)
        var top = 0
        while top < cap && whole[top] == wholeB[top] { top += 1 }
        var bottom = 0
        while bottom < cap && whole[h - 1 - bottom] == wholeB[h - 1 - bottom] { bottom += 1 }
        let bandEnd = h - bottom
        guard bandEnd - top >= 16 else { return .lost }

        // 4. Vote per stripe cell: B[y] == A[y + dy].
        var votes: [Int: Int] = [:]
        var freqs: [[UInt64: Int]] = []
        for s in 0..<groups.count {
            let freq = counts(ha[s][top..<bandEnd])
            freqs.append(freq)
            var index: [UInt64: [Int]] = [:]
            for y in top..<bandEnd where freq[ha[s][y]]! <= maxRepeat { index[ha[s][y], default: []].append(y) }
            for y in top..<bandEnd {
                guard let ys = index[hb[s][y]] else { continue }
                for ya in ys where ya != y { votes[ya - y, default: 0] += 1 }
            }
        }
        // Most votes, then closest to the prediction, then the smaller shift, then forward.
        let ranked = votes.sorted { l, r in
            if l.value != r.value { return l.value > r.value }
            if let p = predicted, abs(l.key - p) != abs(r.key - p) { return abs(l.key - p) < abs(r.key - p) }
            if abs(l.key) != abs(r.key) { return abs(l.key) < abs(r.key) }
            return l.key > r.key
        }

        // 5. Verify the best few candidates over every informative cell of the overlap.
        for (dy, _) in ranked.prefix(5) {
            var inf = 0, ok = 0
            for s in 0..<groups.count {
                for y in top..<bandEnd {
                    let ya = y + dy
                    guard ya >= top, ya < bandEnd else { continue }
                    guard (freqs[s][ha[s][ya]] ?? 0) <= maxRepeat else { continue }
                    inf += 1
                    if ha[s][ya] == hb[s][y] { ok += 1 }
                }
            }
            guard inf >= minInformativeRows * groups.count / 2 else { continue }
            let score = Double(ok) / Double(inf)
            if score >= acceptScore { return .moved(dy: dy, top: top, bandEnd: bandEnd, score: score) }
        }
        return .lost
    }

    /// FNV-1a (64 bit) of each row over `columns` of the grey plane.
    private func rowHashes(_ f: ScrollFrame, columns: [Int]) -> [UInt64] {
        var out = [UInt64](repeating: 0, count: f.height)
        f.gray.withUnsafeBufferPointer { p in
            for y in 0..<f.height {
                var h: UInt64 = 0xcbf29ce484222325
                let base = y * f.width
                for x in columns { h = (h ^ UInt64(p[base + x])) &* 0x100000001b3 }
                out[y] = h
            }
        }
        return out
    }

    private func counts(_ hashes: ArraySlice<UInt64>) -> [UInt64: Int] {
        var c: [UInt64: Int] = [:]
        for h in hashes { c[h, default: 0] += 1 }
        return c
    }
}
```

`TidyShot/Scrolling/ScrollStitcher.swift`:
```swift
import Foundation

/// The finished stitch: `height` rows of `width` BGRA pixels, rows packed, blue first.
nonisolated struct StitchedImage: Sendable {
    let width: Int
    let height: Int
    let bgra: Data
}

/// What one `ScrollStitcher.add` did.
nonisolated struct StitchStep: Equatable, Sendable {
    /// The finder's verdict. A `.moved` with `dy <= 0` is a scroll back up and commits nothing.
    let match: OverlapMatch
    /// Output rows this call appended.
    let committedRows: Int
    /// The output has reached `maxPixelHeight`.
    let isFull: Bool
}

/// Rows committed since the last `previewRows` call, box-downscaled for the live preview.
nonisolated struct PreviewStrip: Equatable, Sendable {
    let width: Int
    let height: Int
    let bgra: Data
    var isEmpty: Bool { height == 0 }
}

/// Builds the tall image from frames of a scrolling area (spec 2.8, Stitcher). Pure.
///
/// Output row equals content row of the first frame. The stitcher holds the last accepted frame
/// and its content offset, and commits rows of that frame, from where the output stops up to the
/// band end, whenever a new frame has moved forward. Scrolling back, stillness and a lost place
/// commit nothing and matching stays against the last accepted frame, so scrolling back into
/// overlap recovers.
nonisolated struct ScrollStitcher: Sendable {
    let width: Int
    let maxPixelHeight: Int
    /// Output rows written so far.
    private(set) var committedHeight = 0
    var isFull: Bool { committedHeight >= maxPixelHeight }

    private var output = Data()
    private var last: ScrollFrame
    /// Content row of `last`'s row 0.
    private var lastOffset = 0
    private var lastDy: Int?
    private var previewCursor = 0
    private let finder: OverlapFinder

    init(first: ScrollFrame, maxPixelHeight: Int = ScrollCaptureLimits.maxPixelHeight,
         finder: OverlapFinder = OverlapFinder()) {
        precondition(maxPixelHeight > 0)
        width = first.width
        self.maxPixelHeight = maxPixelHeight
        self.finder = finder
        last = first
        // Reserved for the cap; the pages are committed only as rows are written.
        output.reserveCapacity(first.width * 4 * maxPixelHeight)
    }

    /// Matches `frame` against the last accepted frame and commits what it newly shows.
    /// `predicted` is the expected shift in pixels (auto mode passes the posted step); without it
    /// the previous accepted shift is used.
    mutating func add(_ frame: ScrollFrame, predicted: Int? = nil) -> StitchStep {
        if isFull { return StitchStep(match: .still, committedRows: 0, isFull: true) }
        let match = finder.find(previous: last, current: frame, predicted: predicted ?? lastDy)
        var committed = 0
        if case .moved(let dy, _, let bandEnd, _) = match, dy > 0 {
            committed = commit(from: last, offset: lastOffset, upTo: bandEnd)
            lastOffset += dy
            lastDy = dy
            last = frame
        }
        return StitchStep(match: match, committedRows: committed, isFull: isFull)
    }

    /// Commits the last frame down to its bottom, footer included, and returns the image.
    mutating func finish() -> StitchedImage {
        _ = commit(from: last, offset: lastOffset, upTo: last.height)
        return StitchedImage(width: width, height: committedHeight, bgra: output)
    }

    /// Appends rows of `frame` (whose row 0 is content row `offset`) from the first row the output
    /// does not have yet up to `end`, never past `maxPixelHeight`. Starting from the output's end,
    /// not from the pair's header height, keeps the output contiguous even when one pair over-reads
    /// a header or footer (blank rows equal at the same y).
    private mutating func commit(from frame: ScrollFrame, offset: Int, upTo end: Int) -> Int {
        let start = max(committedHeight - offset, 0)
        let stop = min(end, maxPixelHeight - offset)
        guard start < stop else { return 0 }
        let rowBytes = width * 4
        frame.bgra.withUnsafeBytes { raw in
            output.append(raw.baseAddress!.advanced(by: start * rowBytes).assumingMemoryBound(to: UInt8.self),
                          count: (stop - start) * rowBytes)
        }
        committedHeight = offset + stop
        return stop - start
    }

    /// A box-downscaled copy of the rows committed since the last call, at most `maxWidth` wide,
    /// for the live preview. The factor is a whole number, so a few trailing columns drop, and a
    /// remainder of rows waits for the next call, so the strips join without a seam.
    mutating func previewRows(maxWidth: Int = ScrollCaptureLimits.previewMaxWidth) -> PreviewStrip {
        let limit = max(1, maxWidth)
        let factor = (width + limit - 1) / limit
        let outWidth = width / factor
        let rows = (committedHeight - previewCursor) / factor * factor
        guard rows > 0 else { return PreviewStrip(width: outWidth, height: 0, bgra: Data()) }
        let outHeight = rows / factor
        let area = factor * factor
        var out = Data(count: outWidth * outHeight * 4)
        output.withUnsafeBytes { src in
            out.withUnsafeMutableBytes { dst in
                for oy in 0..<outHeight {
                    for ox in 0..<outWidth {
                        var sums = (0, 0, 0, 0)
                        for fy in 0..<factor {
                            let rowStart = ((previewCursor + oy * factor + fy) * width + ox * factor) * 4
                            for fx in 0..<factor {
                                let p = rowStart + fx * 4
                                sums.0 += Int(src[p]); sums.1 += Int(src[p + 1])
                                sums.2 += Int(src[p + 2]); sums.3 += Int(src[p + 3])
                            }
                        }
                        let o = (oy * outWidth + ox) * 4
                        dst[o] = UInt8((sums.0 + area / 2) / area); dst[o + 1] = UInt8((sums.1 + area / 2) / area)
                        dst[o + 2] = UInt8((sums.2 + area / 2) / area); dst[o + 3] = UInt8((sums.3 + area / 2) / area)
                    }
                }
            }
        }
        previewCursor += rows
        return PreviewStrip(width: outWidth, height: outHeight, bgra: out)
    }
}
```

Every type is `nonisolated` because the target defaults to `MainActor`; the engine in Task 3 runs the finder and stitcher inside an actor, off the main thread. Do not add `@MainActor` or `@concurrent` to anything here: there is no `async` function in this task.

- [ ] **Step 4: Run the full suite**

Run:
```bash
xcodegen generate && xcodebuild test -project TidyShot.xcodeproj -scheme TidyShot -destination 'platform=macOS' -derivedDataPath .build 2>&1 | grep -E "Test run with|error:|TEST"
```
Expected: no `error:` lines and `Test run with 495 tests in 61 suites passed`. This task adds 27 tests in 3 new suites: `ScrollFrameTests` (3), `OverlapFinderTests` (12) and `ScrollStitcherTests` (12). The two scenario-heavy suites take about 10 s in a Debug build. If `findsTheExactShiftForStepsFromOneRowToNearlyTheBand` reports `.lost` for the 754 row step, the 16 row overlap at offset 400 holds no text: do not loosen the finder, pick another start offset (0, 200 and 1000 also hold text; 600 and 800 do not).

- [ ] **Step 5: Hand checks**

None. The task is pure logic with no UI.

- [ ] **Step 6: Commit**

```bash
git add TidyShot/Scrolling/ScrollCaptureLimits.swift TidyShot/Scrolling/ScrollFrame.swift TidyShot/Scrolling/OverlapFinder.swift TidyShot/Scrolling/ScrollStitcher.swift TidyShotTests/Support/SyntheticPage.swift TidyShotTests/ScrollFrameTests.swift TidyShotTests/OverlapFinderTests.swift TidyShotTests/ScrollStitcherTests.swift
git commit -m "feat: overlap finder and stitcher for scrolling capture"
```

### Task 2: Control logic

**Files:**
- Create: `TidyShot/Scrolling/FrameSettler.swift`
- Create: `TidyShot/Scrolling/ScrollEndDetector.swift`
- Create: `TidyShot/Scrolling/AutoScrollPlan.swift`
- Create: `TidyShot/Scrolling/ScrollCaptureStatus.swift`
- Create: `TidyShot/Scrolling/ScrollPanelGeometry.swift`
- Create: `TidyShot/Selection/SelectionOutcome.swift`
- Modify: `TidyShot/Selection/Selection.swift` (`SelectionMode`, lines 4-7: add `case scrolling`)
- Test: `TidyShotTests/FrameSettlerTests.swift` (new suite `FrameSettlerTests`)
- Test: `TidyShotTests/ScrollEndDetectorTests.swift` (new suite `ScrollEndDetectorTests`)
- Test: `TidyShotTests/AutoScrollPlanTests.swift` (new suite `AutoScrollPlanTests`)
- Test: `TidyShotTests/ScrollCaptureStatusTests.swift` (new suite `ScrollCaptureStatusTests`)
- Test: `TidyShotTests/ScrollPanelGeometryTests.swift` (new suite `ScrollPanelGeometryTests`)
- Test: `TidyShotTests/SelectionOutcomeTests.swift` (new suite `SelectionOutcomeTests`)

**Interfaces:**
- Consumes:
  - From Task 1: `ScrollFrame { width; height; gray }` (`FrameSettler.contentHash`), `OverlapMatch` (`ScrollEndDetector`), `ScrollCaptureLimits.maxPixelHeight` (`ScrollCaptureStatus`). The tests build `ScrollFrame` through `init(bgra: Data, width:height:bytesPerRow:)`.
  - From `main` (23fdff8): `enum SelectionMode { case area, window }` (`Selection.swift:4-7`). Every use of it is an `==` comparison (`SelectionController.swift:27, 55, 120`, `SelectionView.swift:104, 138, 153, 157`) and there is no `switch` over it, so a third case changes no behaviour and breaks no build.
- Produces:
  - `SelectionMode.scrolling` (so Task 4 consumes it; Task 4's list should not add it again).
  - `SelectionOutcome` (MainActor by default, `Equatable`): `.area(CGRect)`, `.window`, `.cancel`; `static func resolve(mode: SelectionMode, dragRect: CGRect?, hasHighlight: Bool) -> SelectionOutcome`; `static let minimumDragSide: CGFloat = 2`.
  - `FrameSettler` (`nonisolated`, `Sendable`): `enum Observation { case frame(hash: UInt64, at: ContinuousClock.Instant); case idle(at: ContinuousClock.Instant) }`, `init(stepStart:baselineHash:quiet:timeout:)` (defaults 150 ms and 1.5 s), `mutating observe(_:) -> Bool`, `isSettled(at:) -> Bool`, `static contentHash(of: ScrollFrame, ignoringRightColumns: Int) -> UInt64`.
  - `ScrollEndDetector` (`nonisolated`): `enum EndDecision { continue, retryAfter(Duration), reverseDirection, shrinkStep, handOver, end(EndReason) }`, `enum EndReason { reachedEnd, heightLimit }`, `mutating decide(after: OverlapMatch, isFull: Bool = false) -> EndDecision`, `static retryDelay` (700 ms).
  - `AutoScrollPlan` (`nonisolated enum`): `events(forPoints:) -> [CGFloat]`, `firstStep(areaHeightPoints:) -> CGFloat`, `nextStep(bandHeightPixels: Int, scale: CGFloat) -> CGFloat`, `shrunk(_:) -> CGFloat`, `eventSpacing` (10 ms), `maxEventPoints` (50), `minimumStepPoints` (40).
  - `ScrollCaptureStatus` (`nonisolated enum`, `Equatable`): the ten cases `readyManual, readyAuto, manualCapturing, manualLost, autoScrolling, autoPaused, autoHandedOver, autoReachedEnd, heightLimit, finishing`, `var text: String`, `static ready(autoScroll:)`, `static sizeText(width:height:locale:)`.
  - `ScrollPanelGeometry` (`nonisolated enum`): `frame(panelSize:area:visibleFrame:) -> CGRect`, `height(wanted:areaHeight:) -> CGFloat`, `panelWidth` (240), `gap` (12), `minimumHeight` (220), `maximumHeight` (560).

Behaviour (spec 2.8: The session, Exact strings, Settling and the end, Starting a capture):
- `ScrollEndDetector` follows the spec, and settles the cases it leaves open. Two auto-scroll moves live in Task 6's driver, not here: a `.still` on the session's very first step tries the other direction once before the detector sees any match, and `.shrinkStep` scrolls back by the lost step before the smaller one. Backwards motion on the first decision is `.reverseDirection`; backwards later counts as a loss, so a page that scrolls the wrong way hands over instead of looping. A `.still` breaks a run of losses and a loss restarts the still count (the page changed, so the end is not reached). `isFull` wins over any match.
- `AutoScrollPlan` works in whole points, because the wheel delta is an integer. Steps: the first is half the area's height, later ones 0.6 of the last band in points, a loss halves the next one down to 40 points and never grows it.
- `FrameSettler.contentHash` hashes the grey plane of every third row and leaves out the scrollbar strip, which fades after a scroll. The driver (Task 6) seeds `baselineHash` with the hash of the frame on screen before the step, passes the finder's scrollbar strip (`scrollbarStripPoints` times the scale) as `ignoringRightColumns`, and stamps each frame with the time the session read it (frames carry no timestamp).
- `ScrollPanelGeometry` takes AppKit coordinates (y up). The controller converts the CG area with `Geometry.appKitRect(fromCG:primaryHeight:)` (`Geometry.swift:11`). Beside the area the panel is top aligned with it. `height(wanted:areaHeight:)` is for Task 5's panel sizing; an area shorter than 220 points still gets 220.
- `SelectionOutcome.resolve` reproduces `SelectionView.mouseUp` (`SelectionView.swift:104-115`) for `.area` and `.window` exactly, and adds `.scrolling`, which drags like `.area` and clicks like `.window`. This task does not touch `SelectionView`; Task 4 replaces those lines with a call to `resolve`.

- [ ] **Step 1: Write the failing tests**

`TidyShotTests/FrameSettlerTests.swift`:
```swift
import Foundation
import Testing
@testable import TidyShot

struct FrameSettlerTests {
    let t0 = ContinuousClock.now

    func at(_ milliseconds: Int) -> ContinuousClock.Instant { t0 + .milliseconds(milliseconds) }

    func frame(_ hash: UInt64, _ milliseconds: Int) -> FrameSettler.Observation {
        .frame(hash: hash, at: at(milliseconds))
    }

    /// A grey frame of `width` by `height` whose pixels are `value(x, y)`.
    func grey(width: Int = 12, height: Int = 9, _ value: (Int, Int) -> UInt8) -> ScrollFrame {
        var bytes = [UInt8](repeating: 255, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let v = value(x, y)
                let i = (y * width + x) * 4
                bytes[i] = v; bytes[i + 1] = v; bytes[i + 2] = v
            }
        }
        return ScrollFrame(bgra: Data(bytes), width: width, height: height, bytesPerRow: width * 4)
    }

    /// The answer to each observation, in order, from a fresh settler.
    func settled(_ observations: [FrameSettler.Observation], baseline: UInt64? = nil,
                 quiet: Duration = FrameSettler.defaultQuiet,
                 timeout: Duration = FrameSettler.defaultTimeout) -> [Bool] {
        var settler = FrameSettler(stepStart: t0, baselineHash: baseline, quiet: quiet, timeout: timeout)
        return observations.map { settler.observe($0) }
    }

    @Test func settlesOnceNothingNewArrivedForTheQuietTime() {
        let answers = settled([frame(1, 20), frame(2, 60), .idle(at: at(150)), .idle(at: at(209)), .idle(at: at(210))])
        #expect(answers == [false, false, false, false, true])
    }

    /// A repeat of the same hash is not new content, so it does not restart the quiet time.
    @Test func framesWithTheSameHashDoNotRestartTheQuietTime() {
        #expect(settled([frame(7, 10), frame(7, 100), frame(7, 159), frame(7, 160)]) == [false, false, false, true])
    }

    /// A display that keeps changing (a video, a spinner) settles at the timeout.
    @Test func changingContentSettlesAtTheTimeout() {
        let times = Array(stride(from: 50, through: 2000, by: 50))
        let answers = settled(times.enumerated().map { frame(UInt64($0.offset), $0.element) })
        #expect(times[answers.firstIndex(of: true)!] == 1500)
        #expect(answers.filter { $0 }.count == times.filter { $0 >= 1500 }.count)
    }

    @Test func aBaselineHashMeansTheFirstUnchangedFrameIsNotNews() {
        #expect(settled([frame(9, 150)], baseline: 9) == [true])
        #expect(settled([frame(9, 150)], baseline: 8) == [false])
        #expect(settled([frame(9, 10), frame(9, 150), frame(9, 160)]) == [false, false, true])
    }

    @Test func idleFramesCountAsUnchanged() {
        #expect(settled([.idle(at: at(100)), .idle(at: at(150))], baseline: 1) == [false, true])
    }

    /// A timer can ask without a frame: the quiet time runs from the step when nothing arrived.
    @Test func settledCanBeAskedWithoutAnObservation() {
        let settler = FrameSettler(stepStart: t0)
        #expect(!settler.isSettled(at: at(149)))
        #expect(settler.isSettled(at: at(150)))
        var busy = FrameSettler(stepStart: t0)
        let answer = busy.observe(frame(1, 1000))
        #expect(!answer)
        #expect(!busy.isSettled(at: at(1100)))
        #expect(busy.isSettled(at: at(1500)))
    }

    @Test func customQuietAndTimeoutApply() {
        let quiet = Duration.milliseconds(40), timeout = Duration.milliseconds(100)
        #expect(settled([frame(1, 10), frame(1, 50)], quiet: quiet, timeout: timeout) == [false, true])
        #expect(settled([frame(1, 30), frame(2, 60), frame(3, 100)], quiet: quiet, timeout: timeout) == [false, false, true])
    }

    @Test func contentHashIsStableAndSeesContentChanges() {
        let a = grey { x, y in UInt8((x * 7 + y * 13) % 200) }
        let same = grey { x, y in UInt8((x * 7 + y * 13) % 200) }
        #expect(FrameSettler.contentHash(of: a, ignoringRightColumns: 2) == FrameSettler.contentHash(of: same, ignoringRightColumns: 2))
        let changed = grey { x, y in x == 4 && y == 3 ? 0 : UInt8((x * 7 + y * 13) % 200) }
        #expect(FrameSettler.contentHash(of: a, ignoringRightColumns: 2) != FrameSettler.contentHash(of: changed, ignoringRightColumns: 2))
        let scrolled = grey { x, y in UInt8((x * 7 + (y + 1) * 13) % 200) }
        #expect(FrameSettler.contentHash(of: a, ignoringRightColumns: 2) != FrameSettler.contentHash(of: scrolled, ignoringRightColumns: 2))
    }

    /// The scrollbar fades in and out after a scroll; its columns are not content.
    @Test func contentHashIgnoresTheScrollbarColumns() {
        let a = grey { x, y in UInt8((x * 7 + y * 13) % 200) }
        let fading = grey { x, y in x >= 10 ? 5 : UInt8((x * 7 + y * 13) % 200) }
        #expect(FrameSettler.contentHash(of: a, ignoringRightColumns: 2) == FrameSettler.contentHash(of: fading, ignoringRightColumns: 2))
        #expect(FrameSettler.contentHash(of: a, ignoringRightColumns: 0) != FrameSettler.contentHash(of: fading, ignoringRightColumns: 0))
    }
}
```

`TidyShotTests/ScrollEndDetectorTests.swift`:
```swift
import Foundation
import Testing
@testable import TidyShot

struct ScrollEndDetectorTests {
    func moved(_ dy: Int) -> OverlapMatch { .moved(dy: dy, top: 80, bandEnd: 850, score: 1) }

    let retry = ScrollEndDetector.EndDecision.retryAfter(.milliseconds(700))

    /// The decision for each match, in order, from a fresh detector.
    func decisions(_ matches: [OverlapMatch]) -> [ScrollEndDetector.EndDecision] {
        var detector = ScrollEndDetector()
        return matches.map { detector.decide(after: $0) }
    }

    @Test func movingForwardContinues() {
        #expect(decisions([moved(462), moved(300)]) == [.continue, .continue])
    }

    @Test func twoStillsEndAfterTheLazyLoadRetry() {
        #expect(decisions([moved(462), .still, .still]) == [.continue, retry, .end(.reachedEnd)])
    }

    @Test func movementAfterTheRetryResetsTheStillCount() {
        // The lazy-loaded content arrived: the page moved after all.
        #expect(decisions([.still, moved(200), .still, .still]) == [retry, .continue, retry, .end(.reachedEnd)])
    }

    @Test func aFirstStepBackwardsReversesTheDirectionOnce() {
        // Backwards later is not a second reversal: it counts as a loss.
        #expect(decisions([moved(-231), moved(231), moved(-100)]) == [.reverseDirection, .continue, .shrinkStep])
        #expect(decisions([moved(-231), moved(-231)]) == [.reverseDirection, .shrinkStep])
    }

    @Test func aBackwardsStepAfterAForwardOneIsNotReversed() {
        #expect(decisions([moved(231), moved(-100)]) == [.continue, .shrinkStep])
    }

    @Test func lossesShrinkTheStepAndThreeInARowHandOver() {
        #expect(decisions([moved(231), .lost, .lost, .lost]) == [.continue, .shrinkStep, .shrinkStep, .handOver])
    }

    @Test func movementOrStillnessBreaksTheRunOfLosses() {
        let expected: [ScrollEndDetector.EndDecision] = [.shrinkStep, .shrinkStep, .continue, .shrinkStep, .shrinkStep,
                                                         retry, .shrinkStep, .shrinkStep, .handOver]
        #expect(decisions([.lost, .lost, moved(100), .lost, .lost, .still, .lost, .lost, .lost]) == expected)
    }

    /// A loss between two stills means the page changed, so the end has not been reached.
    @Test func aLossRestartsTheStillCount() {
        #expect(decisions([.still, .lost, .still]) == [retry, .shrinkStep, retry])
    }

    @Test func theHeightCapEndsWhateverTheMatchWas() {
        for match in [moved(462), .lost, .still, moved(-5)] as [OverlapMatch] {
            var detector = ScrollEndDetector()
            #expect(detector.decide(after: match, isFull: true) == .end(.heightLimit))
        }
        // After a normal step, too.
        var detector = ScrollEndDetector()
        let first = detector.decide(after: moved(462))
        let second = detector.decide(after: moved(462), isFull: true)
        #expect(first == .continue)
        #expect(second == .end(.heightLimit))
    }

    @Test func aSessionThatNeverMovesEndsOnTheSecondStill() {
        #expect(decisions([.still, .still]) == [retry, .end(.reachedEnd)])
    }
}
```

`TidyShotTests/AutoScrollPlanTests.swift`:
```swift
import CoreGraphics
import Testing
@testable import TidyShot

struct AutoScrollPlanTests {
    @Test func aStepSplitsIntoEventsOfAtMostFiftyPoints() {
        #expect(AutoScrollPlan.events(forPoints: 120) == [50, 50, 20])
        #expect(AutoScrollPlan.events(forPoints: 50) == [50])
        #expect(AutoScrollPlan.events(forPoints: 231) == [50, 50, 50, 50, 31])
        #expect(AutoScrollPlan.events(forPoints: 1) == [1])
        #expect(AutoScrollPlan.events(forPoints: 400).reduce(0, +) == 400)
        #expect(AutoScrollPlan.events(forPoints: 400).allSatisfy { $0 <= 50 })
    }

    /// Events are whole points, because the wheel delta is an integer.
    @Test func eventsAreWholePoints() {
        #expect(AutoScrollPlan.events(forPoints: 120.4) == [50, 50, 20])
        #expect(AutoScrollPlan.events(forPoints: 120.6) == [50, 50, 21])
    }

    @Test func noEventsForNothingToScroll() {
        #expect(AutoScrollPlan.events(forPoints: 0).isEmpty)
        #expect(AutoScrollPlan.events(forPoints: -30).isEmpty)
        #expect(AutoScrollPlan.events(forPoints: 0.4).isEmpty)
    }

    @Test func eventsArePostedTenMillisecondsApart() {
        #expect(AutoScrollPlan.eventSpacing == .milliseconds(10))
    }

    @Test func theFirstStepIsHalfTheAreasHeight() {
        #expect(AutoScrollPlan.firstStep(areaHeightPoints: 800) == 400)
        #expect(AutoScrollPlan.firstStep(areaHeightPoints: 100) == 50)
    }

    /// 0.6 of the last band: 770 rows at 2x are 385 points, 0.6 of which is 231.
    @Test func laterStepsAreSixtyPercentOfTheLastBandInPoints() {
        #expect(AutoScrollPlan.nextStep(bandHeightPixels: 770, scale: 2) == 231)
        #expect(AutoScrollPlan.nextStep(bandHeightPixels: 770, scale: 1) == 462)
        #expect(AutoScrollPlan.nextStep(bandHeightPixels: 1600, scale: 2) == 480)
        #expect(AutoScrollPlan.nextStep(bandHeightPixels: 0, scale: 2) == 1)
    }

    @Test func aLossHalvesTheStepDownToFortyPoints() {
        #expect(AutoScrollPlan.shrunk(400) == 200)
        #expect(AutoScrollPlan.shrunk(231) == 116)
        #expect(AutoScrollPlan.shrunk(60) == 40)
        #expect(AutoScrollPlan.shrunk(40) == 40)
        // Never grows a step that is already below the floor.
        #expect(AutoScrollPlan.shrunk(30) == 30)
    }
}
```

`TidyShotTests/ScrollCaptureStatusTests.swift`:
```swift
import Foundation
import Testing
@testable import TidyShot

struct ScrollCaptureStatusTests {
    @Test func everyStatusLineMatchesTheSpec() {
        #expect(ScrollCaptureStatus.readyManual.text == "Click Start, then scroll down slowly.")
        #expect(ScrollCaptureStatus.readyAuto.text == "Click Start, then hold the pointer over the area.")
        #expect(ScrollCaptureStatus.manualCapturing.text == "Scroll down slowly. Click Done at the end.")
        #expect(ScrollCaptureStatus.manualLost.text == "Too fast. Scroll back up a little.")
        #expect(ScrollCaptureStatus.autoScrolling.text == "Scrolling… Move the pointer away to pause.")
        #expect(ScrollCaptureStatus.autoPaused.text == "Paused. Move the pointer over the area to continue.")
        #expect(ScrollCaptureStatus.autoHandedOver.text == "Auto-scroll lost its place. Scroll back up a little, or click Done.")
        #expect(ScrollCaptureStatus.autoReachedEnd.text == "Reached the end.")
        #expect(ScrollCaptureStatus.heightLimit.text == "Reached the 16,384 pixel limit.")
        #expect(ScrollCaptureStatus.finishing.text == "Stitching…")
    }

    @Test func theReadyLineFollowsTheAutoScrollSetting() {
        #expect(ScrollCaptureStatus.ready(autoScroll: false) == .readyManual)
        #expect(ScrollCaptureStatus.ready(autoScroll: true) == .readyAuto)
    }

    @Test func theHeightLimitLineNamesTheLimit() {
        #expect(ScrollCaptureLimits.maxPixelHeight == 16_384)
    }

    @Test func theSizeReadoutGroupsDigitsAndUsesATimesSign() {
        let us = Locale(identifier: "en_US")
        #expect(ScrollCaptureStatus.sizeText(width: 2560, height: 7340, locale: us) == "2,560 × 7,340 px")
        #expect(ScrollCaptureStatus.sizeText(width: 640, height: 900, locale: us) == "640 × 900 px")
        #expect(ScrollCaptureStatus.sizeText(width: 2560, height: 16384, locale: us) == "2,560 × 16,384 px")
        let german = ScrollCaptureStatus.sizeText(width: 2560, height: 7340, locale: Locale(identifier: "de_DE"))
        #expect(german == "2.560 × 7.340 px")
    }
}
```

`TidyShotTests/ScrollPanelGeometryTests.swift`:
```swift
import CoreGraphics
import Testing
@testable import TidyShot

struct ScrollPanelGeometryTests {
    /// AppKit coordinates: origin bottom left. The visible frame has a 25 pt menu bar gap on top
    /// and a 70 pt Dock at the bottom.
    let screen = CGRect(x: 0, y: 70, width: 1920, height: 985)
    let panel = CGSize(width: 240, height: 400)

    @Test func sitsTwelvePointsRightOfTheAreaTopAligned() {
        let area = CGRect(x: 200, y: 300, width: 800, height: 600)
        #expect(ScrollPanelGeometry.frame(panelSize: panel, area: area, visibleFrame: screen)
                == CGRect(x: 1012, y: 500, width: 240, height: 400))
    }

    @Test func fitsExactlyAgainstTheRightEdge() {
        let area = CGRect(x: 200, y: 300, width: 1468, height: 600)
        // 1668 + 12 + 240 = 1920.
        #expect(ScrollPanelGeometry.frame(panelSize: panel, area: area, visibleFrame: screen).minX == 1680)
    }

    @Test func goesLeftWhenTheRightHasNoRoom() {
        let area = CGRect(x: 900, y: 300, width: 900, height: 600)
        #expect(ScrollPanelGeometry.frame(panelSize: panel, area: area, visibleFrame: screen)
                == CGRect(x: 648, y: 500, width: 240, height: 400))
    }

    @Test func goesInsideTheBottomRightCornerWhenNeitherSideHasRoom() {
        let area = CGRect(x: 100, y: 200, width: 1700, height: 700)
        #expect(ScrollPanelGeometry.frame(panelSize: panel, area: area, visibleFrame: screen)
                == CGRect(x: 1548, y: 212, width: 240, height: 400))
    }

    @Test func isClampedBelowTheMenuBar() {
        // The area reaches the top of the visible frame, and a tall panel top-aligned to it stays inside.
        let area = CGRect(x: 200, y: 700, width: 600, height: 355)
        let frame = ScrollPanelGeometry.frame(panelSize: panel, area: area, visibleFrame: screen)
        #expect(frame.maxY == screen.maxY)
        #expect(frame.minX == 812)
    }

    @Test func isClampedAboveTheDock() {
        // A short area near the bottom: top alignment would push the panel below the visible frame.
        let area = CGRect(x: 200, y: 80, width: 600, height: 120)
        let frame = ScrollPanelGeometry.frame(panelSize: panel, area: area, visibleFrame: screen)
        #expect(frame.minY == screen.minY)
        #expect(frame.minX == 812)
    }

    @Test func usesTheVisibleFrameOfAScreenNotAtTheOrigin() {
        let right = CGRect(x: 1920, y: 0, width: 1440, height: 875)
        let area = CGRect(x: 2300, y: 200, width: 1000, height: 500)
        // 3300 + 12 + 240 is past 3360, so left: 2300 - 12 - 240. The top aligns with the area's: 700 - 400.
        #expect(ScrollPanelGeometry.frame(panelSize: panel, area: area, visibleFrame: right)
                == CGRect(x: 2048, y: 300, width: 240, height: 400))
        // Neither side has room on this screen: inside the corner, never onto the first screen.
        let wide = CGRect(x: 2000, y: 200, width: 1300, height: 500)
        #expect(ScrollPanelGeometry.frame(panelSize: panel, area: wide, visibleFrame: right)
                == CGRect(x: 3048, y: 212, width: 240, height: 400))
    }

    @Test func theResultAlwaysStaysInsideTheVisibleFrame() {
        let areas = [CGRect(x: 0, y: 70, width: 1920, height: 985), CGRect(x: 1800, y: 900, width: 120, height: 155),
                     CGRect(x: 0, y: 70, width: 120, height: 100), CGRect(x: 960, y: 500, width: 400, height: 200)]
        for area in areas {
            let frame = ScrollPanelGeometry.frame(panelSize: panel, area: area, visibleFrame: screen)
            #expect(screen.contains(frame), "area \(area) gave \(frame)")
            #expect(frame.size == panel)
        }
    }

    @Test func heightFollowsThePreviewBetween220AndTheAreaHeight() {
        #expect(ScrollPanelGeometry.height(wanted: 100, areaHeight: 800) == 220)
        #expect(ScrollPanelGeometry.height(wanted: 380, areaHeight: 800) == 380)
        #expect(ScrollPanelGeometry.height(wanted: 700, areaHeight: 800) == 560)
        #expect(ScrollPanelGeometry.height(wanted: 700, areaHeight: 300) == 300)
        // An area shorter than the minimum still gets the minimum.
        #expect(ScrollPanelGeometry.height(wanted: 400, areaHeight: 150) == 220)
    }

    @Test func thePanelIs240PointsWide() {
        #expect(ScrollPanelGeometry.panelWidth == 240)
        #expect(ScrollPanelGeometry.gap == 12)
    }
}
```

`TidyShotTests/SelectionOutcomeTests.swift`:
```swift
import CoreGraphics
import Testing
@testable import TidyShot

struct SelectionOutcomeTests {
    let drag = CGRect(x: 40, y: 50, width: 300, height: 200)

    @Test func areaModeTakesADraggedRect() {
        #expect(SelectionOutcome.resolve(mode: .area, dragRect: drag, hasHighlight: false) == .area(drag))
    }

    @Test func areaModeCancelsOnAClickOrATinyDrag() {
        #expect(SelectionOutcome.resolve(mode: .area, dragRect: nil, hasHighlight: false) == .cancel)
        let tiny = CGRect(x: 10, y: 10, width: 1, height: 30)
        #expect(SelectionOutcome.resolve(mode: .area, dragRect: tiny, hasHighlight: false) == .cancel)
        #expect(SelectionOutcome.resolve(mode: .area, dragRect: CGRect(x: 10, y: 10, width: 30, height: 1.9), hasHighlight: false) == .cancel)
        #expect(SelectionOutcome.resolve(mode: .area, dragRect: CGRect(x: 10, y: 10, width: 2, height: 2), hasHighlight: false)
                == .area(CGRect(x: 10, y: 10, width: 2, height: 2)))
    }

    @Test func windowModePicksTheHighlightAndIgnoresDrags() {
        #expect(SelectionOutcome.resolve(mode: .window, dragRect: nil, hasHighlight: true) == .window)
        #expect(SelectionOutcome.resolve(mode: .window, dragRect: drag, hasHighlight: true) == .window)
        #expect(SelectionOutcome.resolve(mode: .window, dragRect: nil, hasHighlight: false) == .cancel)
        #expect(SelectionOutcome.resolve(mode: .window, dragRect: drag, hasHighlight: false) == .cancel)
    }

    /// Scrolling takes a drag like area mode and a click on the highlight like window mode.
    @Test func scrollingModeDragsAnAreaOrClicksAWindow() {
        #expect(SelectionOutcome.resolve(mode: .scrolling, dragRect: drag, hasHighlight: false) == .area(drag))
        // A drag wins over a highlight that happens to be under the pointer.
        #expect(SelectionOutcome.resolve(mode: .scrolling, dragRect: drag, hasHighlight: true) == .area(drag))
        #expect(SelectionOutcome.resolve(mode: .scrolling, dragRect: nil, hasHighlight: true) == .window)
        // A jittery click on a highlighted window is a click.
        let jitter = CGRect(x: 10, y: 10, width: 1, height: 1)
        #expect(SelectionOutcome.resolve(mode: .scrolling, dragRect: jitter, hasHighlight: true) == .window)
        #expect(SelectionOutcome.resolve(mode: .scrolling, dragRect: nil, hasHighlight: false) == .cancel)
        #expect(SelectionOutcome.resolve(mode: .scrolling, dragRect: jitter, hasHighlight: false) == .cancel)
    }
}
```

- [ ] **Step 2: Run them and see them fail**

Run:
```bash
xcodegen generate && xcodebuild test -project TidyShot.xcodeproj -scheme TidyShot -destination 'platform=macOS' -derivedDataPath .build 2>&1 | grep -E "Test run with|error:|TEST"
```
Expected: the build fails with `error:` lines such as `cannot find 'FrameSettler' in scope`, `cannot find 'ScrollEndDetector' in scope`, `cannot find 'AutoScrollPlan' in scope`, `cannot find 'ScrollCaptureStatus' in scope`, `cannot find 'ScrollPanelGeometry' in scope`, `cannot find 'SelectionOutcome' in scope` and `type 'SelectionMode' has no member 'scrolling'`, and no test runs.

- [ ] **Step 3: Add the selection mode**

`TidyShot/Selection/Selection.swift`, lines 4-7: replace the enum with
```swift
enum SelectionMode {
    case area
    case window
    /// Capture Scrolling: the crosshair and loupe of `.area` plus the window highlight of `.window`.
    case scrolling
}
```
Nothing else in the file changes.

- [ ] **Step 4: Implement**

`TidyShot/Selection/SelectionOutcome.swift`:
```swift
import CoreGraphics

/// What a mouse-up in the selection overlay means, for the three modes. Pure, so it is tested
/// without a window. The overlay keeps converting the rect to screen coordinates.
enum SelectionOutcome: Equatable {
    /// A dragged area, in the overlay view's coordinates.
    case area(CGRect)
    /// The window under the pointer, the one the overlay highlighted.
    case window
    case cancel

    /// A drag smaller than this in either side is a click.
    static let minimumDragSide: CGFloat = 2

    /// `.area` and `.scrolling` take a dragged rect of at least 2 by 2; a click (no drag, or a
    /// tiny one) picks the highlighted window when there is one; `.window` ignores drags and only
    /// picks the highlight. With neither, the selection is cancelled.
    static func resolve(mode: SelectionMode, dragRect: CGRect?, hasHighlight: Bool) -> SelectionOutcome {
        if mode != .window, let rect = dragRect,
           rect.width >= minimumDragSide, rect.height >= minimumDragSide {
            return .area(rect)
        }
        return hasHighlight ? .window : .cancel
    }
}
```

`TidyShot/Scrolling/FrameSettler.swift`:
```swift
import Foundation

/// Decides when the display has stopped changing after an auto-scroll step (spec 2.8, Settling).
///
/// Content is compared, not the frame status, because a complete frame also arrives for a change
/// elsewhere on the display. The driver feeds each observation; the area is settled when no frame
/// with a new content hash arrived for `quiet`, or `timeout` after the step, whichever comes first.
nonisolated struct FrameSettler: Sendable {
    enum Observation: Equatable, Sendable {
        /// A complete frame whose content hash is `hash`.
        case frame(hash: UInt64, at: ContinuousClock.Instant)
        /// The stream reported that the display did not change. It counts as unchanged.
        case idle(at: ContinuousClock.Instant)
    }

    static let defaultQuiet: Duration = .milliseconds(150)
    static let defaultTimeout: Duration = .milliseconds(1500)

    let quiet: Duration
    let timeout: Duration
    private let stepStart: ContinuousClock.Instant
    private var lastHash: UInt64?
    private var lastChange: ContinuousClock.Instant

    /// `baselineHash` is the content hash of the frame before the step. A frame that still has
    /// it is not a change; without one the first frame is.
    init(stepStart: ContinuousClock.Instant, baselineHash: UInt64? = nil,
         quiet: Duration = defaultQuiet, timeout: Duration = defaultTimeout) {
        self.stepStart = stepStart
        self.quiet = quiet
        self.timeout = timeout
        lastHash = baselineHash
        lastChange = stepStart
    }

    /// Records an observation and reports whether the area has settled as of its time.
    mutating func observe(_ observation: Observation) -> Bool {
        switch observation {
        case .frame(let hash, let time):
            if hash != lastHash {
                lastHash = hash
                lastChange = time
            }
            return isSettled(at: time)
        case .idle(let time):
            return isSettled(at: time)
        }
    }

    /// For a timer that wakes the driver when no frames arrive at all.
    func isSettled(at now: ContinuousClock.Instant) -> Bool {
        now - lastChange >= quiet || now - stepStart >= timeout
    }

    /// A cheap content hash of a frame: FNV-1a (64 bit) over the grey plane of every third row,
    /// leaving out the rightmost `ignoringRightColumns` columns, where overlay scrollbars fade in
    /// and out. Scrolling changes every row, so sampling rows loses nothing here.
    static func contentHash(of frame: ScrollFrame, ignoringRightColumns: Int) -> UInt64 {
        let columns = max(1, frame.width - ignoringRightColumns)
        var hash: UInt64 = 0xcbf29ce484222325
        frame.gray.withUnsafeBufferPointer { grey in
            for y in stride(from: 0, to: frame.height, by: 3) {
                let base = y * frame.width
                for x in 0..<columns { hash = (hash ^ UInt64(grey[base + x])) &* 0x100000001b3 }
            }
        }
        return hash
    }
}
```

`TidyShot/Scrolling/ScrollEndDetector.swift`:
```swift
import Foundation

/// Turns the result of each auto-scroll step into the next move (spec 2.8, Settling and the end).
/// One detector per session. Manual mode has none: the user clicks Done.
nonisolated struct ScrollEndDetector: Sendable {
    enum EndReason: Equatable, Sendable {
        case reachedEnd
        case heightLimit
    }

    enum EndDecision: Equatable, Sendable {
        /// The step worked; scroll again.
        case `continue`
        /// Nothing moved: wait, then look again (lazy loading may add content).
        case retryAfter(Duration)
        /// The first step moved backwards: flip the scroll direction, once.
        case reverseDirection
        /// The place was lost: halve the next step.
        case shrinkStep
        /// Three losses in a row: stop scrolling and let the user take over.
        case handOver
        case end(EndReason)
    }

    /// How long the first `.still` waits before the second look.
    static let retryDelay: Duration = .milliseconds(700)
    /// Losses in a row that hand over to manual mode.
    static let lossesBeforeHandOver = 3

    private var decisions = 0
    private var stills = 0
    private var losses = 0

    /// `isFull` is `StitchStep.isFull`: the output reached `ScrollCaptureLimits.maxPixelHeight`.
    ///
    /// - `.moved` forward resets both counts. Backwards on the very first step reverses the
    ///   direction once (natural scrolling may invert synthetic deltas); backwards later counts as
    ///   a loss, so a page that scrolls the wrong way hands over instead of looping.
    /// - The first `.still` retries after 700 ms and a second one ends with `.reachedEnd`; a loss
    ///   in between restarts that count.
    /// - `.lost` halves the next step; the third in a row (a `.still` breaks the run) hands over.
    mutating func decide(after match: OverlapMatch, isFull: Bool = false) -> EndDecision {
        let isFirst = decisions == 0
        decisions += 1
        if isFull { return .end(.heightLimit) }
        switch match {
        case .moved(let dy, _, _, _):
            if dy > 0 {
                stills = 0
                losses = 0
                return .continue
            }
            if isFirst { return .reverseDirection }
            return registerLoss()
        case .still:
            losses = 0
            stills += 1
            return stills == 1 ? .retryAfter(Self.retryDelay) : .end(.reachedEnd)
        case .lost:
            return registerLoss()
        }
    }

    private mutating func registerLoss() -> EndDecision {
        stills = 0
        losses += 1
        return losses >= Self.lossesBeforeHandOver ? .handOver : .shrinkStep
    }
}
```

`TidyShot/Scrolling/AutoScrollPlan.swift`:
```swift
import CoreGraphics
import Foundation

/// How far auto-scroll moves and how it posts the move (spec 2.8, Settling and the end). Pure.
nonisolated enum AutoScrollPlan {
    /// One wheel event moves at most this many points.
    static let maxEventPoints: CGFloat = 50
    /// Wheel events of one step are posted this far apart.
    static let eventSpacing: Duration = .milliseconds(10)
    /// A shrunk step never goes below this many points.
    static let minimumStepPoints: CGFloat = 40
    /// Each step after the first is this fraction of the last band's height.
    static let bandFraction: CGFloat = 0.6

    /// A step of `points` as whole-point wheel events of at most 50: 120 gives 50, 50, 20.
    static func events(forPoints points: CGFloat) -> [CGFloat] {
        var remaining = points.rounded()
        var events: [CGFloat] = []
        while remaining > 0 {
            let event = min(maxEventPoints, remaining)
            events.append(event)
            remaining -= event
        }
        return events
    }

    /// Half the area's height.
    static func firstStep(areaHeightPoints: CGFloat) -> CGFloat {
        (areaHeightPoints / 2).rounded()
    }

    /// 0.6 of the last accepted band (rows between the sticky header and footer), in whole points.
    static func nextStep(bandHeightPixels: Int, scale: CGFloat) -> CGFloat {
        max(1, (CGFloat(bandHeightPixels) * bandFraction / scale).rounded())
    }

    /// The step after a `.lost`: half, but not below 40 points and never larger than `points`.
    static func shrunk(_ points: CGFloat) -> CGFloat {
        min(points, max(minimumStepPoints, (points / 2).rounded()))
    }
}
```

`TidyShot/Scrolling/ScrollCaptureStatus.swift`:
```swift
import Foundation

/// The panel's status line for each session state, and the size readout (spec 2.8, Exact strings).
nonisolated enum ScrollCaptureStatus: Equatable, Sendable {
    case readyManual
    case readyAuto
    case manualCapturing
    /// Manual mode lost its place; clears on the next movement.
    case manualLost
    case autoScrolling
    /// Auto mode is waiting for the pointer, or paused because it left.
    case autoPaused
    case autoHandedOver
    case autoReachedEnd
    case heightLimit
    case finishing

    static func ready(autoScroll: Bool) -> ScrollCaptureStatus {
        autoScroll ? .readyAuto : .readyManual
    }

    var text: String {
        switch self {
        case .readyManual: "Click Start, then scroll down slowly."
        case .readyAuto: "Click Start, then hold the pointer over the area."
        case .manualCapturing: "Scroll down slowly. Click Done at the end."
        case .manualLost: "Too fast. Scroll back up a little."
        case .autoScrolling: "Scrolling… Move the pointer away to pause."
        case .autoPaused: "Paused. Move the pointer over the area to continue."
        case .autoHandedOver: "Auto-scroll lost its place. Scroll back up a little, or click Done."
        case .autoReachedEnd: "Reached the end."
        case .heightLimit: "Reached the \(Self.grouped(ScrollCaptureLimits.maxPixelHeight, locale: Locale(identifier: "en_US"))) pixel limit."
        case .finishing: "Stitching…"
        }
    }

    /// `2,560 × 7,340 px`: the stitched image's size in pixels, with the locale's digit grouping.
    static func sizeText(width: Int, height: Int, locale: Locale = .current) -> String {
        "\(grouped(width, locale: locale)) × \(grouped(height, locale: locale)) px"
    }

    private static func grouped(_ value: Int, locale: Locale) -> String {
        value.formatted(.number.grouping(.automatic).locale(locale))
    }
}
```

`TidyShot/Scrolling/ScrollPanelGeometry.swift`:
```swift
import CoreGraphics

/// Where the scrolling capture's control panel goes (spec 2.8, The session). Pure. All rects are
/// AppKit screen coordinates (origin bottom left, y up): convert the area with
/// `Geometry.appKitRect(fromCG:primaryHeight:)` first.
nonisolated enum ScrollPanelGeometry {
    static let panelWidth: CGFloat = 240
    /// Between the area and the panel, and from the area's edges for the inside placement.
    static let gap: CGFloat = 12
    static let minimumHeight: CGFloat = 220
    static let maximumHeight: CGFloat = 560

    /// The panel height for a wanted height: between 220 and `min(560, areaHeight)`. An area
    /// shorter than 220 still gets 220, since the controls need that much.
    static func height(wanted: CGFloat, areaHeight: CGFloat) -> CGFloat {
        let upper = max(minimumHeight, min(maximumHeight, areaHeight))
        return min(max(wanted, minimumHeight), upper)
    }

    /// 12 pt right of the area, top aligned, else 12 pt left of it, else inside its bottom-right
    /// corner, 12 pt from both edges; then clamped into `visibleFrame` (the area's screen).
    static func frame(panelSize: CGSize, area: CGRect, visibleFrame: CGRect) -> CGRect {
        var origin: CGPoint
        if area.maxX + gap + panelSize.width <= visibleFrame.maxX {
            origin = CGPoint(x: area.maxX + gap, y: area.maxY - panelSize.height)
        } else if area.minX - gap - panelSize.width >= visibleFrame.minX {
            origin = CGPoint(x: area.minX - gap - panelSize.width, y: area.maxY - panelSize.height)
        } else {
            origin = CGPoint(x: area.maxX - gap - panelSize.width, y: area.minY + gap)
        }
        origin.x = max(visibleFrame.minX, min(origin.x, visibleFrame.maxX - panelSize.width))
        origin.y = max(visibleFrame.minY, min(origin.y, visibleFrame.maxY - panelSize.height))
        return CGRect(origin: origin, size: panelSize)
    }
}
```

Note for the tests above: `#expect` cannot call a `mutating` method on a local (the macro captures it as an immutable closure parameter), so the settler and detector tests drive a fresh value through a helper (`settled(_:)`, `decisions(_:)`) or bind the result with `let` first. Keep that shape when adding cases.

- [ ] **Step 5: Run the full suite**

Run:
```bash
xcodegen generate && xcodebuild test -project TidyShot.xcodeproj -scheme TidyShot -destination 'platform=macOS' -derivedDataPath .build 2>&1 | grep -E "Test run with|error:|TEST"
```
Expected: no `error:` lines and `Test run with 539 tests in 67 suites passed`. This task adds 44 tests in 6 new suites: `FrameSettlerTests` (9), `ScrollEndDetectorTests` (10), `AutoScrollPlanTests` (7), `ScrollCaptureStatusTests` (4), `ScrollPanelGeometryTests` (10) and `SelectionOutcomeTests` (4). `WindowPickerTests` and the rest stay as they were.

- [ ] **Step 6: Hand checks**

None. Everything here is pure, and the one change to existing code is an unused enum case. Task 4 wires `SelectionOutcome` into the overlay.

- [ ] **Step 7: Commit**

```bash
git add TidyShot/Scrolling/FrameSettler.swift TidyShot/Scrolling/ScrollEndDetector.swift TidyShot/Scrolling/AutoScrollPlan.swift TidyShot/Scrolling/ScrollCaptureStatus.swift TidyShot/Scrolling/ScrollPanelGeometry.swift TidyShot/Selection/SelectionOutcome.swift TidyShot/Selection/Selection.swift TidyShotTests/FrameSettlerTests.swift TidyShotTests/ScrollEndDetectorTests.swift TidyShotTests/AutoScrollPlanTests.swift TidyShotTests/ScrollCaptureStatusTests.swift TidyShotTests/ScrollPanelGeometryTests.swift TidyShotTests/SelectionOutcomeTests.swift
git commit -m "feat: scrolling capture control logic"
```

### Task 3: Frame source and engine

**Files:**
- Create: `TidyShot/Scrolling/ScrollFrameSource.swift` (`FrameEvent`, `FrameSource`, `ScrollFrameSource`)
- Create: `TidyShot/Scrolling/ScrollStitchEngine.swift` (`StitchProgress`, `ScrollStitchEngine`)
- Create: `TidyShot/Selection/OverlayWindowLookup.swift` (the lookup moved out of `SelectionController.overlayWindows()`)
- Modify: `TidyShot/Selection/SelectionController.swift` (`overlayWindows()`, lines 62-83)
- Create: `TidyShotTests/ScrollStitchEngineTests.swift` (struct `ScrollStitchEngineTests`)
- Create: `TidyShotTests/ScrollFrameSourceTests.swift` (struct `ScrollFrameSourceTests`; not in the task list's entry, added so the frame copy and the buffer rule are tested without ScreenCaptureKit)

**Interfaces:**
- Consumes:
  - `main`: `CaptureEngine.shareableContent()` and `CaptureEngine.scale(forDisplayID:)` (`CaptureEngine.swift:7`, `:50`), `Geometry.displayLocal(_:in:)` and `Geometry.pixelSize(points:scale:)` (`Geometry.swift:20`, `:24`), `ScaledImage(image:scale:)` (`ScaledImage.swift:6`), `ImageEncoder.pngData(from:scale:)` and `ImageEncoder.decode(_:)` (`ImageEncoder.swift:21`, `:42`).
  - Task 1: `ScrollFrame(bgra: UnsafeRawPointer, width:height:bytesPerRow:)` and `ScrollFrame(bgra: Data, ...)` (both copy and pack, and build `gray`); `OverlapFinder(scale:)`; `OverlapMatch`; `ScrollStitcher(first:maxPixelHeight:finder:)`, `add(_:predicted:) -> StitchStep`, `finish() -> StitchedImage`, `previewRows(maxWidth:) -> PreviewStrip`; `StitchStep(match:committedRows:isFull:)`; `PreviewStrip` (`height`, `isEmpty`); `StitchedImage(width:height:bgra:)`; `ScrollCaptureLimits.maxPixelHeight`. Test side: `SyntheticPage` (`frame(at:animated:scrollbarVisible:)`, `finder`, `compare(_:reached:)`, `header`, `footer`, `bandHeight`, `maxOffset`).
- Produces (Task 5 and 6 rely on these names):
  - `nonisolated enum FrameEvent: Sendable { case frame(ScrollFrame); case idle(ContinuousClock.Instant); case stopped((any Error)?) }`. A `.frame` carries no time: the session stamps it with its own clock when it reads it (for `FrameSettler.Observation.frame(hash:at:)`). `.stopped` comes only when the stream stops by itself (`SCStreamDelegate`); `stop()` does not send it.
  - `protocol FrameSource: AnyObject { func start() async throws -> AsyncStream<FrameEvent>; func stop() async }` (main actor by the module default, so a test fake is a plain class). Contract: one run per source; events are buffered one deep, newest first, and an `.idle` never pushes out an unread `.frame`; `stop()` finishes the sequence after any frame still buffered, so Done awaits `stop()` and then drains the events before `finish`.
  - `ScrollFrameSource` (`nonisolated final class`, `NSObject`, `FrameSource`, `SCStreamOutput`, `SCStreamDelegate`): `@MainActor init(rect: CGRect, display: SCDisplay, engine: CaptureEngine)` (rect in CG global points, on `display`); `let scale: CGFloat`, `let colorSpace: CGColorSpace`, `let pixelWidth: Int`, `let pixelHeight: Int`; `@MainActor start()` and `stop()`; `static func streamColorSpace(forDisplayID:) -> CGColorSpace`, `static func copyFrame(from: CVPixelBuffer) -> ScrollFrame?`, `static func send(_: FrameEvent, to: AsyncStream<FrameEvent>.Continuation)`.
  - `nonisolated struct StitchProgress: Sendable { let heightPixels: Int; let step: StitchStep; let previewDelta: PreviewStrip }`. `heightPixels` is the height Done would give now (the first frame's height before any movement, at most the cap); the cap is `step.isFull`.
  - `actor ScrollStitchEngine`: `init(finder: OverlapFinder = OverlapFinder(), maxPixelHeight: Int = ScrollCaptureLimits.maxPixelHeight)`, `begin(first: ScrollFrame)`, `add(_ frame: ScrollFrame, predicted: Int? = nil) -> StitchProgress`, `finish(scale: CGFloat, colorSpace: CGColorSpace) -> ScaledImage?`.
  - `enum OverlayWindowLookup { static func windows(numbers: Set<CGWindowID>, engine: CaptureEngine) async -> [SCWindow] }` (main actor). `SelectionController.overlayWindows()` keeps its signature and cache.
  - Wiring for Task 5: the controller builds the source after the panel and the area frame are on screen (the filter is made in `start()`, which the session calls at Start), the engine as `ScrollStitchEngine(finder: OverlapFinder(scale: source.scale))`, and finishes with `finish(scale: source.scale, colorSpace: source.colorSpace)`. The first frame's rows reach `previewDelta` only once a move commits them; until then the panel's preview is the session's to draw.

Behaviour (spec 2.8, Frame source and Stitcher):
- Stream setup, all in `start()` on the main actor: filter `SCContentFilter(display:excludingApplications: [own] exceptingWindows: [])` with `own` the `SCRunningApplication`s whose `processID` is ours, from a shareable-content fetch made at Start (after the panel and frame are up), so the panel, the area frame, the Quick Access overlay and any editor are all excluded with no window-number race. Fallback when TidyShot is not listed: our visible windows by number through `OverlayWindowLookup`. Configuration: `sourceRect = Geometry.displayLocal(rect, in: display.frame)`; `width`, `height` = `Geometry.pixelSize(points: rect.size, scale:)` with `CaptureEngine.scale(forDisplayID:)`, the same numbers a one-shot area capture uses; `minimumFrameInterval` 1/30 s; `queueDepth` 4; `pixelFormat` `kCVPixelFormatType_32BGRA`; `showsCursor = false`; `colorSpaceName` the display's own colour space's name (`CGDisplayCopyColorSpace`), or sRGB when that space has no name, and `colorSpace` reports which, so the stitched CGImage is tagged with the space the pixels are in.
- Sample handler: a private serial queue (`io.tky.tidyshot.scrolling-frames`, `.userInitiated`). A `.complete` sample is locked read-only, copied into a `ScrollFrame` by Task 1's pointer initialiser (packed BGRA plus the grey plane, one pass) and unlocked by `defer` before the callback returns; nothing keeps the sample buffer, so the stream's pool of 4 is never held. `.idle` becomes `.idle(.now)`; other statuses (blank, started, suspended, stopped) are ignored.
- One-deep buffer: `AsyncStream.makeStream(bufferingPolicy: .bufferingNewest(1))`, so a busy stitcher gets the newest frame. Plain `bufferingNewest(1)` would let the idle that follows the last scroll push out the last moved frame before the session reads it, so `send` puts a pushed-out frame back when the newcomer is an idle (`yield` reports the element it dropped).
- Concurrency: the class is `nonisolated` so the `SCStreamOutput`/`SCStreamDelegate` callbacks run on ScreenCaptureKit's queues; its main-actor members (`init`, `start`, `stop`, the filter, `stream`, `started`) touch `SCStream`, `NSApp` and `CaptureEngine`; the callbacks touch only `let` state (`continuation` is Sendable) and static functions. Nothing mutable is shared, so there is no lock and no `@unchecked Sendable`; the class is not Sendable and never crosses an actor (the session holds it on the main actor).
- The engine is an `actor`: the session's `await engine.add(frame)` hops off the main actor, and finding and committing (about 24 ms for a 2560 x 1800 pair) run on the actor's executor. Only Sendable values cross: `ScrollFrame` (its `Data` is copy-on-write, so sending it copies nothing), `StitchProgress`, `ScaledImage`. No `@concurrent` is needed: nothing here is a nonisolated async function that must leave the caller's actor.
- `finish` wraps the stitcher's `Data` in a `CGDataProvider` (no pixel copy) and builds the image at native pixels: 8 bits per component, `bytesPerRow` width x 4, `byteOrder32Little | noneSkipFirst` (BGRA in memory, alpha ignored), the given colour space. The PNG then carries 72 x scale DPI through `ImageEncoder.pngData(from:scale:)` like every capture. The engine is empty afterwards.

- [ ] **Step 1: Write the failing tests**

`TidyShotTests/ScrollStitchEngineTests.swift` (new):
```swift
import CoreGraphics
import Foundation
import Testing
@testable import TidyShot

/// The engine actor end to end: synthetic BGRA frames in, a CGImage out, through the PNG
/// encoder and decoder every capture goes through.
struct ScrollStitchEngineTests {
    let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!

    /// The plain scenario's viewer (no spinner, no scrollbar thumb, so every pixel is known):
    /// the frame at offset 0, then one per step of 500 rows, clamped to the page.
    func plainFrames(_ page: inout SyntheticPage, steps: Int) -> (frames: [ScrollFrame], reached: Int) {
        var offset = 0
        var frames = [page.frame(at: 0, animated: false, scrollbarVisible: false)]
        for _ in 0..<steps {
            offset = min(page.maxOffset, offset + 500)
            frames.append(page.frame(at: offset, animated: false, scrollbarVisible: false))
        }
        return (frames, offset)
    }

    /// `image` drawn into a BGRA bitmap in its own colour space, so no colour conversion happens:
    /// `width * height * 4` bytes, blue first, the fourth byte undefined.
    func bgra(of image: CGImage) throws -> Data {
        let space = try #require(image.colorSpace)
        var data = Data(count: image.width * image.height * 4)
        try data.withUnsafeMutableBytes { raw in
            let context = try #require(CGContext(
                data: raw.baseAddress, width: image.width, height: image.height, bitsPerComponent: 8,
                bytesPerRow: image.width * 4, space: space,
                bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue))
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        return data
    }

    @Test func stitchesThroughTheActorToAnExactPNGAtScale2() async throws {
        var page = SyntheticPage()
        let (frames, reached) = plainFrames(&page, steps: 18)
        let engine = ScrollStitchEngine(finder: page.finder)
        await engine.begin(first: frames[0])
        var last: StitchProgress?
        var committed = 0
        var previewRows = 0
        for frame in frames.dropFirst() {
            let progress = await engine.add(frame)
            #expect(progress.step.match != .lost)
            committed += progress.step.committedRows
            previewRows += progress.previewDelta.height
            last = progress
        }
        // The preview is 160 px wide, under 360, so its strips are the committed rows one to one.
        #expect(previewRows == committed)

        let scaled = try #require(await engine.finish(scale: 2, colorSpace: sRGB))
        let expectedHeight = page.header + reached + page.bandHeight + page.footer
        #expect(scaled.scale == 2)
        #expect(scaled.image.width == page.width)
        #expect(scaled.image.height == expectedHeight)
        #expect(last?.heightPixels == expectedHeight)

        // The same frames straight through a stitcher: the reference for every column.
        var stitcher = ScrollStitcher(first: frames[0], finder: page.finder)
        for frame in frames.dropFirst() { _ = stitcher.add(frame) }
        let reference = stitcher.finish()

        let png = try ImageEncoder.pngData(from: scaled.image, scale: scaled.scale)
        let decoded = try #require(ImageEncoder.decode(png))
        #expect(decoded.scale == 2)
        #expect(decoded.image.width == reference.width)
        #expect(decoded.image.height == reference.height)
        let pixels = try bgra(of: decoded.image)
        var mismatched = 0
        for i in stride(from: 0, to: reference.bgra.count, by: 4)
        where pixels[i] != reference.bgra[i] || pixels[i + 1] != reference.bgra[i + 1] || pixels[i + 2] != reference.bgra[i + 2] {
            mismatched += 1
        }
        #expect(mismatched == 0)
        // And the page's columns are the ideal page: header, every page row reached, footer.
        let comparison = page.compare(StitchedImage(width: reference.width, height: reference.height, bgra: pixels),
                                      reached: reached)
        #expect(comparison.actualHeight == comparison.expectedHeight)
        #expect(comparison.mismatched == 0)
    }

    @Test func theCapEndsTheStitchAtExactlyTheLimit() async throws {
        var page = SyntheticPage()
        let engine = ScrollStitchEngine(finder: page.finder, maxPixelHeight: 2000)
        await engine.begin(first: page.frame(at: 0, animated: false))
        var offset = 0
        var full: StitchProgress?
        while full == nil, offset < page.maxOffset {
            offset = min(page.maxOffset, offset + 400)
            let progress = await engine.add(page.frame(at: offset, animated: false))
            #expect(progress.heightPixels <= 2000)
            if progress.step.isFull { full = progress }
        }
        #expect(full?.heightPixels == 2000)
        // Frames after the cap change nothing.
        let after = await engine.add(page.frame(at: offset + 300, animated: false))
        #expect(after.step == StitchStep(match: .still, committedRows: 0, isFull: true))
        #expect(after.previewDelta.isEmpty)
        let image = try #require(await engine.finish(scale: 2, colorSpace: sRGB))
        #expect(image.image.height == 2000)
    }

    /// Done with no movement gives the first frame alone; nothing before `begin` and nothing
    /// after `finish`.
    @Test func aLoneFrameFinishesAsItselfAndTheEngineEmpties() async throws {
        var page = SyntheticPage()
        let engine = ScrollStitchEngine(finder: page.finder)
        let before = await engine.finish(scale: 2, colorSpace: sRGB)
        #expect(before == nil)

        let first = page.frame(at: 300, animated: false)
        let progress = await engine.add(first)
        #expect(progress.step == StitchStep(match: .still, committedRows: 0, isFull: false))
        #expect(progress.heightPixels == page.height)
        #expect(progress.previewDelta.isEmpty)

        let image = try #require(await engine.finish(scale: 1, colorSpace: sRGB))
        #expect(image.scale == 1)
        #expect(image.image.width == page.width)
        #expect(image.image.height == page.height)
        #expect(image.image.colorSpace?.name == CGColorSpace.sRGB)
        let pixels = try bgra(of: image.image)
        #expect(stride(from: 0, to: first.bgra.count, by: 4).allSatisfy { pixels[$0] == first.bgra[$0] })
        let again = await engine.finish(scale: 1, colorSpace: sRGB)
        #expect(again == nil)
    }
}
```
The first test drives the plain scenario (no animated square and no visible thumb, so every pixel is known) through the actor, encodes and decodes the PNG, and compares every pixel with the same frames run straight through a `ScrollStitcher`, and the page's columns with the ideal page. Drawing the decoded image into a bitmap in its own colour space means no colour conversion, so the comparison is exact.

`TidyShotTests/ScrollFrameSourceTests.swift` (new):
```swift
import CoreVideo
import Foundation
import Testing
@testable import TidyShot

/// The parts of the stream source that run without ScreenCaptureKit: the copy out of a pixel
/// buffer and the one-deep buffer rule. The stream itself is a manual check.
struct ScrollFrameSourceTests {
    func makePixelBuffer(width: Int, height: Int, format: OSType) throws -> CVPixelBuffer {
        var buffer: CVPixelBuffer?
        let attributes = [kCVPixelBufferBytesPerRowAlignmentKey: 64] as CFDictionary
        try #require(CVPixelBufferCreate(nil, width, height, format, attributes, &buffer) == kCVReturnSuccess)
        return try #require(buffer)
    }

    func frame(_ value: UInt8) -> ScrollFrame {
        ScrollFrame(bgra: Data(repeating: value, count: 2 * 2 * 4), width: 2, height: 2, bytesPerRow: 8)
    }

    /// The first byte of a frame event, which `frame(_:)` fills with its value; nil otherwise.
    func value(of event: FrameEvent?) -> UInt8? {
        guard case .frame(let frame)? = event else { return nil }
        return frame.bgra.first
    }

    /// 37 pixels are 148 bytes, which CoreVideo pads to 192 per row. The frame holds the 148
    /// bytes of each row and none of the padding, which is filled with 0xEE here.
    @Test func copyFramePacksAPaddedPixelBuffer() throws {
        let buffer = try makePixelBuffer(width: 37, height: 5, format: kCVPixelFormatType_32BGRA)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
        try #require(bytesPerRow > 37 * 4)
        var expected: [UInt8] = []
        CVPixelBufferLockBaseAddress(buffer, [])
        let base = try #require(CVPixelBufferGetBaseAddress(buffer)).assumingMemoryBound(to: UInt8.self)
        for y in 0..<5 {
            for x in 0..<bytesPerRow {
                let value = x < 37 * 4 ? UInt8((x * 7 + y * 31) & 0xFF) : 0xEE
                base[y * bytesPerRow + x] = value
                if x < 37 * 4 { expected.append(value) }
            }
        }
        CVPixelBufferUnlockBaseAddress(buffer, [])

        let frame = try #require(ScrollFrameSource.copyFrame(from: buffer))
        #expect(frame.width == 37)
        #expect(frame.height == 5)
        #expect(Array(frame.bgra) == expected)
        #expect(frame.gray.count == 37 * 5)

        let argb = try makePixelBuffer(width: 4, height: 4, format: kCVPixelFormatType_32ARGB)
        #expect(ScrollFrameSource.copyFrame(from: argb) == nil)
    }

    /// One event is buffered. A newer frame replaces an unread one, an idle never does, and
    /// finishing still delivers the frame that is buffered.
    @Test func anIdleNeverPushesOutAPendingFrame() async throws {
        let (events, continuation) = AsyncStream.makeStream(of: FrameEvent.self, bufferingPolicy: .bufferingNewest(1))
        var iterator = events.makeAsyncIterator()

        ScrollFrameSource.send(.frame(frame(1)), to: continuation)
        ScrollFrameSource.send(.idle(.now), to: continuation)
        ScrollFrameSource.send(.idle(.now), to: continuation)
        #expect(value(of: await iterator.next(isolation: #isolation)) == 1)

        ScrollFrameSource.send(.idle(.now), to: continuation)
        guard case .idle? = await iterator.next(isolation: #isolation) else {
            Issue.record("an idle with nothing pending is delivered")
            return
        }

        ScrollFrameSource.send(.frame(frame(2)), to: continuation)
        ScrollFrameSource.send(.frame(frame(3)), to: continuation)
        #expect(value(of: await iterator.next(isolation: #isolation)) == 3)

        ScrollFrameSource.send(.frame(frame(4)), to: continuation)
        continuation.finish()
        #expect(value(of: await iterator.next(isolation: #isolation)) == 4)
        let end = await iterator.next(isolation: #isolation)
        #expect(end == nil)
    }
}
```
`next(isolation: #isolation)` keeps the iterator on the test's actor; a plain `next()` here fails to build with `sending 'iterator' risks causing data races`.

- [ ] **Step 2: Run the tests and see them fail**

Run the header's full-suite command. Expected: no test runs; the build fails with `cannot find 'ScrollStitchEngine' in scope`, `cannot find type 'StitchProgress' in scope`, `cannot find 'ScrollFrameSource' in scope` and `cannot find type 'FrameEvent' in scope`.

- [ ] **Step 3: Move the overlay lookup**

`TidyShot/Selection/OverlayWindowLookup.swift` (new), the body of `overlayWindows()` without the cache:
```swift
import AppKit
import ScreenCaptureKit

/// TidyShot's own windows as ScreenCaptureKit sees them, matched by window number, for a
/// filter's `excludingWindows`. Used for the selection overlay and as the scrolling stream's
/// fallback when TidyShot is missing from the shareable applications.
enum OverlayWindowLookup {
    /// Retries briefly because ScreenCaptureKit can lag the window server, and returns whatever
    /// was found after the last attempt.
    static func windows(numbers wanted: Set<CGWindowID>, engine: CaptureEngine) async -> [SCWindow] {
        var found: [SCWindow] = []
        for attempt in 0..<4 {
            if attempt > 0 {
                try? await Task.sleep(for: .milliseconds(50))
            }
            guard let fresh = try? await engine.shareableContent() else { continue }
            found = fresh.windows.filter { wanted.contains($0.windowID) }
            if found.count >= wanted.count { break }
        }
        if found.count < wanted.count {
            NSLog("Overlay exclusion incomplete: found \(found.count) of \(wanted.count) overlay windows")
        }
        return found
    }
}
```

`TidyShot/Selection/SelectionController.swift`, `overlayWindows()` (lines 62-83). Doc (lines 62-65): `Our overlay windows as ScreenCaptureKit sees them, for excludingWindows, through OverlayWindowLookup (by window number, so other TidyShot windows are unaffected, with a short retry). A complete result is cached until dismiss(), so the capture after selection does not look up again.` Replace lines 69-80 (from `var found: [SCWindow] = []` through the `NSLog` block) with
```swift
        let found = await OverlayWindowLookup.windows(numbers: wanted, engine: engine)
```
Lines 66-68 (`wanted`, the cache check) and 81-82 (fill the cache only with a complete result, return) stay. Behaviour is unchanged: four attempts 50 ms apart, the same log line, the same cache rule. `runSelection` (`AppCoordinator.swift:137`) and `takeSnapshots` (`SelectionController.swift:87`) still call `overlayWindows()`; window capture never used it. Everything after line 80 moves up by 11 lines; Task 4 cites `main`'s line numbers and says so.

- [ ] **Step 4: Implement the frame source**

`TidyShot/Scrolling/ScrollFrameSource.swift`:
```swift
import AppKit
import CoreMedia
import CoreVideo
import ScreenCaptureKit

/// What a frame source reports to the scrolling-capture session.
nonisolated enum FrameEvent: Sendable {
    /// A complete frame whose pixels changed, copied out of the stream's buffer.
    case frame(ScrollFrame)
    /// The display did not change since the last frame (`SCFrameStatus.idle`).
    case idle(ContinuousClock.Instant)
    /// The stream stopped by itself, with the reason when ScreenCaptureKit gave one. `stop()`
    /// does not send this: it ends the events after any frame still buffered.
    case stopped((any Error)?)
}

/// Where a session's frames come from: the stream in the app, synthetic frames in tests. One
/// source serves one run: `start()` once, then `stop()`, both from the main actor.
protocol FrameSource: AnyObject {
    /// Starts capturing. Frames are buffered newest-first, one deep, so a busy consumer gets the
    /// newest frame and the older ones are dropped; an idle never pushes out a pending frame.
    func start() async throws -> AsyncStream<FrameEvent>
    /// Stops capturing and finishes the events. A frame already buffered is still delivered, then
    /// the sequence ends. Safe to call more than once, and before `start()`.
    func stop() async
}

/// One `SCStream` of a rect of one display for a scrolling capture, with all of TidyShot
/// excluded. Setup and teardown run on the main actor; each sample is copied out of its
/// `CVPixelBuffer` on `queue` before the callback returns, so the stream's buffer pool never
/// starves and no pixel buffer outlives its callback.
nonisolated final class ScrollFrameSource: NSObject, FrameSource, SCStreamOutput, SCStreamDelegate {
    /// Pixels per point of the display: the stream's output and the stitched image's scale.
    let scale: CGFloat
    /// What the frames' pixels are in: the display's own colour space when it has a name the
    /// stream can take, otherwise sRGB. The stitched CGImage is tagged with it.
    let colorSpace: CGColorSpace
    /// Output size in pixels.
    let pixelWidth: Int
    let pixelHeight: Int

    private let rect: CGRect
    private let display: SCDisplay
    private let engine: CaptureEngine
    private let events: AsyncStream<FrameEvent>
    private let continuation: AsyncStream<FrameEvent>.Continuation
    private let queue = DispatchQueue(label: "io.tky.tidyshot.scrolling-frames", qos: .userInitiated)
    @MainActor private var stream: SCStream?
    @MainActor private var started = false

    /// `rect` is in CoreGraphics global points and lies on `display` (the selection clips it).
    @MainActor init(rect: CGRect, display: SCDisplay, engine: CaptureEngine) {
        self.rect = rect
        self.display = display
        self.engine = engine
        scale = CaptureEngine.scale(forDisplayID: display.displayID)
        let pixels = Geometry.pixelSize(points: rect.size, scale: scale)
        pixelWidth = pixels.width
        pixelHeight = pixels.height
        colorSpace = Self.streamColorSpace(forDisplayID: display.displayID)
        (events, continuation) = AsyncStream.makeStream(of: FrameEvent.self, bufferingPolicy: .bufferingNewest(1))
        super.init()
    }

    /// The display's colour space when it is named (the stream takes a name, not a space),
    /// otherwise sRGB.
    static func streamColorSpace(forDisplayID id: CGDirectDisplayID) -> CGColorSpace {
        let display = CGDisplayCopyColorSpace(id)
        if display.name != nil { return display }
        return CGColorSpace(name: CGColorSpace.sRGB)!
    }

    @MainActor func start() async throws -> AsyncStream<FrameEvent> {
        guard !started else { return events }
        started = true
        let filter = try await makeFilter()
        let config = SCStreamConfiguration()
        config.sourceRect = Geometry.displayLocal(rect, in: display.frame)
        config.width = pixelWidth
        config.height = pixelHeight
        config.minimumFrameInterval = CMTime(value: 1, timescale: 30)
        config.queueDepth = 4
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.showsCursor = false
        config.colorSpaceName = colorSpace.name ?? CGColorSpace.sRGB

        let stream = SCStream(filter: filter, configuration: config, delegate: self)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
        try await stream.startCapture()
        self.stream = stream
        return events
    }

    @MainActor func stop() async {
        if let stream {
            self.stream = nil
            try? await stream.stopCapture()
            try? stream.removeStreamOutput(self, type: .screen)
        }
        continuation.finish()
    }

    /// Everything of TidyShot excluded, by application: the panel, the area frame, the Quick
    /// Access overlay and any editor. When this process is not in the list, our on-screen windows
    /// by number instead.
    @MainActor private func makeFilter() async throws -> SCContentFilter {
        let content = try await engine.shareableContent()
        let pid = ProcessInfo.processInfo.processIdentifier
        let own = content.applications.filter { $0.processID == pid }
        if !own.isEmpty {
            return SCContentFilter(display: display, excludingApplications: own, exceptingWindows: [])
        }
        let numbers = Set(NSApp.windows.compactMap { window in
            window.isVisible && window.windowNumber > 0 ? CGWindowID(window.windowNumber) : nil
        })
        let windows = await OverlayWindowLookup.windows(numbers: numbers, engine: engine)
        return SCContentFilter(display: display, excludingWindows: windows)
    }

    // MARK: SCStreamOutput and SCStreamDelegate (on `queue` and ScreenCaptureKit's queue)

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, sampleBuffer.isValid,
              let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false)
                as? [[SCStreamFrameInfo: Any]],
              let raw = attachments.first?[.status] as? Int,
              let status = SCFrameStatus(rawValue: raw) else { return }
        switch status {
        case .complete:
            guard let buffer = sampleBuffer.imageBuffer, let frame = Self.copyFrame(from: buffer) else { return }
            Self.send(.frame(frame), to: continuation)
        case .idle:
            Self.send(.idle(.now), to: continuation)
        default:
            break
        }
    }

    func stream(_ stream: SCStream, didStopWithError error: any Error) {
        continuation.yield(.stopped(error))
        continuation.finish()
    }

    /// Copies a BGRA pixel buffer into a `ScrollFrame` while it is locked. Nil for any other
    /// pixel format or a buffer without a base address.
    static func copyFrame(from buffer: CVPixelBuffer) -> ScrollFrame? {
        guard CVPixelBufferGetPixelFormatType(buffer) == kCVPixelFormatType_32BGRA,
              CVPixelBufferLockBaseAddress(buffer, .readOnly) == kCVReturnSuccess else { return nil }
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(buffer) else { return nil }
        let width = CVPixelBufferGetWidth(buffer)
        let height = CVPixelBufferGetHeight(buffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
        return ScrollFrame(bgra: UnsafeRawPointer(base), width: width, height: height, bytesPerRow: bytesPerRow)
    }

    /// Yields `event`. The buffer holds one event; when an idle pushes out a frame the consumer
    /// has not read yet, the frame goes back in and the idle is the one dropped, so the last frame
    /// before the page goes still is never lost.
    static func send(_ event: FrameEvent, to continuation: AsyncStream<FrameEvent>.Continuation) {
        guard case .dropped(let old) = continuation.yield(event), case .frame = old, case .idle = event else { return }
        continuation.yield(old)
    }
}
```
Notes:
- `start()` calls `stream.startCapture()` and `stopCapture()` with `await` on the main actor; under Swift 6 with `NonisolatedNonsendingByDefault` this builds with no warning, as `CaptureEngine`'s `SCScreenshotManager` call does. The stream holds the source as its output and delegate; `stop()` removes the output and drops the stream, which breaks that cycle.
- `start()` throws whatever ScreenCaptureKit throws (no permission, display gone); the session turns `error.localizedDescription` into the failure notification.
- When the stream stops by itself, `.stopped(error)` may push out a frame the session had not read; the session saves what was already stitched (spec: `The capture stopped early: ...`).

- [ ] **Step 5: Implement the engine**

`TidyShot/Scrolling/ScrollStitchEngine.swift`:
```swift
import CoreGraphics
import Foundation

/// What one frame did to the stitch, for the session's readout, status line and live preview.
nonisolated struct StitchProgress: Sendable {
    /// The height in pixels that Done would give now: the last accepted frame's content offset
    /// plus its height, at most the cap. Before any movement, the first frame's height.
    let heightPixels: Int
    /// The stitcher's verdict on the frame; `step.isFull` reports the cap.
    let step: StitchStep
    /// Rows committed since the last call, downscaled for the preview. Empty when none were.
    let previewDelta: PreviewStrip
}

/// Owns the `ScrollStitcher` off the main actor (spec 2.8, Stitcher). The session hands it each
/// frame with `await`; matching and committing (about 24 ms for a 2560 x 1800 pair) run on the
/// actor's executor, never on the main actor. Everything that crosses in or out is a Sendable
/// value: `ScrollFrame`, `StitchProgress`, `ScaledImage`.
actor ScrollStitchEngine {
    private let finder: OverlapFinder
    private let maxPixelHeight: Int
    private var stitcher: ScrollStitcher?
    /// Content row of the last accepted frame's row 0, advanced exactly as the stitcher advances
    /// its own (a forward `.moved`), and that frame's height, for `heightPixels`.
    private var offset = 0
    private var frameHeight = 0

    /// `finder` carries the scrollbar strip for the display's scale: `OverlapFinder(scale:)`.
    init(finder: OverlapFinder = OverlapFinder(), maxPixelHeight: Int = ScrollCaptureLimits.maxPixelHeight) {
        self.finder = finder
        self.maxPixelHeight = maxPixelHeight
    }

    /// Starts a stitch with the first frame, the page as the user arranged it. Starting again
    /// discards what was stitched before.
    func begin(first: ScrollFrame) {
        stitcher = ScrollStitcher(first: first, maxPixelHeight: maxPixelHeight, finder: finder)
        offset = 0
        frameHeight = first.height
    }

    /// Matches `frame` against the last accepted frame and commits what it newly shows.
    /// `predicted` is auto mode's posted step in pixels; manual mode passes nil and the stitcher
    /// uses the previous shift. A frame before `begin` begins the stitch and reports `.still`.
    func add(_ frame: ScrollFrame, predicted: Int? = nil) -> StitchProgress {
        guard stitcher != nil else {
            begin(first: frame)
            return progress(StitchStep(match: .still, committedRows: 0, isFull: false))
        }
        let step = stitcher!.add(frame, predicted: predicted)
        if case .moved(let dy, _, _, _) = step.match, dy > 0 {
            offset += dy
        }
        return progress(step)
    }

    /// Commits the last frame, footer included, and wraps the rows in a CGImage at native pixels
    /// without copying them: `bitsPerComponent` 8, `bytesPerRow` width x 4, BGRA in memory
    /// (`byteOrder32Little | noneSkipFirst`), tagged with `colorSpace`, the space the stream
    /// delivered the frames in. Returns it with `scale`, the display's. Nil before `begin`; the
    /// engine is empty afterwards, so a second call is nil too.
    func finish(scale: CGFloat, colorSpace: CGColorSpace) -> ScaledImage? {
        guard var stitcher else { return nil }
        self.stitcher = nil
        let stitched = stitcher.finish()
        guard stitched.width > 0, stitched.height > 0,
              let provider = CGDataProvider(data: stitched.bgra as CFData) else { return nil }
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipFirst.rawValue
                                      | CGBitmapInfo.byteOrder32Little.rawValue)
        guard let image = CGImage(width: stitched.width, height: stitched.height, bitsPerComponent: 8,
                                  bitsPerPixel: 32, bytesPerRow: stitched.width * 4, space: colorSpace,
                                  bitmapInfo: bitmapInfo, provider: provider, decode: nil,
                                  shouldInterpolate: false, intent: .defaultIntent) else { return nil }
        return ScaledImage(image: image, scale: scale)
    }

    private func progress(_ step: StitchStep) -> StitchProgress {
        StitchProgress(heightPixels: min(offset + frameHeight, maxPixelHeight), step: step,
                       previewDelta: stitcher!.previewRows())
    }
}
```
`heightPixels` follows the stitcher's own bookkeeping: `ScrollStitcher.add` advances its offset exactly on a forward `.moved` (and returns `.still` once full), and `finish()` commits the last frame to its bottom, so the image is `offset + frame height` rows, capped. The engine test checks that the last progress and the finished image agree.

- [ ] **Step 6: Run the suite**

Run the header's full-suite command. Expected: no `error:` lines, and `Test run with 544 tests in 69 suites passed`. This task adds 5 tests in 2 new suites: `ScrollStitchEngineTests` (`stitchesThroughTheActorToAnExactPNGAtScale2`, `theCapEndsTheStitchAtExactlyTheLimit`, `aLoneFrameFinishesAsItselfAndTheEngineEmpties`) and `ScrollFrameSourceTests` (`copyFramePacksAPaddedPixelBuffer`, `anIdleNeverPushesOutAPendingFrame`). The engine test runs the full 160 x 900 synthetic frames and adds about two seconds to a Debug run.

- [ ] **Step 7: Hand checks**

Nothing calls the stream until Task 5, so the stream itself is checked there and in `docs/testing/phase-5-manual-checklist.md` (Task 7): the screen-recording indicator shows only while a session captures, TidyShot's panel and frame never appear in the stitched image, and a one-shot area capture of the same region matches the stitched image's first screen pixel for pixel. Here, check that moving the lookup changed nothing (build and run, re-grant Screen Recording after an ad-hoc rebuild):
- ⌃⇧4 and drag an area: the saved image has no dimming and no selection border; the loupe shows the screen without the overlay's dimming.
- ⌃⇧2 and click a window: the window is saved with transparent corners, as before.
- On two displays, ⌃⇧4 on the second display: the loupe there also shows the undimmed screen.

- [ ] **Step 8: Commit**

```bash
git add TidyShot/Scrolling/ScrollFrameSource.swift TidyShot/Scrolling/ScrollStitchEngine.swift TidyShot/Selection/OverlayWindowLookup.swift TidyShot/Selection/SelectionController.swift TidyShotTests/ScrollStitchEngineTests.swift TidyShotTests/ScrollFrameSourceTests.swift
git commit -m "feat: scrolling frame source and stitch engine"
```

### Task 4: Entry points and the save path

**Files:**
- Modify: `TidyShot/Selection/SelectionController.swift` (`select`, lines 26-27, 38-41 and 55-57; `updateHover`, lines 118-120; `finishArea`, lines 136-150; line numbers are `main`'s; Task 3 replaced lines 69-80 of `overlayWindows()` with one line, so `updateHover` and `finishArea` now sit 11 lines higher, and the lines before 69 have not moved)
- Modify: `TidyShot/Selection/SelectionView.swift` (`mouseUp`, lines 104-115; `draw`, lines 138, 153 and 157)
- Modify: `TidyShot/App/Shortcuts.swift` (lines 3-7)
- Modify: `TidyShot/App/StatusMenuController.swift` (`rebuild`, line 74; actions, line 110)
- Modify: `TidyShot/Settings/ShortcutsSettingsView.swift` (line 9)
- Modify: `TidyShot/App/AppCoordinator.swift` (`registerShortcuts`, lines 99-109; after `captureWindow`, line 126; `save(_:)`, lines 168-207; `showOverlay`, lines 342-344)
- Modify: `TidyShot/Output/ThumbnailMaker.swift` (type doc, lines 5-6; `thumbnail(from:maxSide:)`, lines 21-23)
- Create: `TidyShotTests/ShortcutsTests.swift` (struct `ShortcutsTests`)
- Test: `TidyShotTests/ThumbnailMakerTests.swift` (modified), `TidyShotTests/ShortcutsTests.swift` (new); `WindowPickerTests`, `ImageEncoderTests` and the rest of the suite stay as they are and must stay green.

**Interfaces:**
- Consumes:
  - `main`: `SelectionController.select(mode:content:)`, `dismiss()`, `overlayWindows()` (after Task 3 a thin cache over `OverlayWindowLookup.windows(numbers:engine:)`), `WindowPicker(content:)`, `Geometry.cgRect(fromAppKit:primaryHeight:)`, `AppCoordinator.withCaptureLock(_:)`, `loadContent()`, `capture(_:excludingWindows:)`, `save(_:)`, `persist(...)`, `Notifier.notifyError(_:title:)`, `Pasteboard.copy(pngData:tiffData:)` and `Pasteboard.tiffData(of:scale:)` (`Pasteboard.swift:21`, `:43`, both already used by the editor's Copy), `ImageEncoder.pngData(from:scale:)`, `KeyboardShortcuts.onKeyUp(for:action:)` and `disable(_:)`.
  - Task 1: `ScrollCaptureLimits.minimumAreaHeightPoints` (100).
  - Task 2: `SelectionMode.scrolling` (Task 2 adds the case to `Selection.swift`; this task does not touch that file) and `SelectionOutcome.resolve(mode:dragRect:hasHighlight:) -> SelectionOutcome` (MainActor, `Equatable`) with cases `.area(CGRect)`, `.window`, `.cancel`: `.area` for a drag of at least 2 by 2 points in `.area` and `.scrolling`, `.window` when a window is highlighted and there is no such drag (in `.window` mode whatever the drag), `.cancel` otherwise.
- Produces:
  - Scrolling mode in the overlay: `select(mode: .scrolling, content:)` shows the crosshair, the loupe with its snapshot, the drag rectangle and the window hover highlight, and always resolves to `.area(rect:display:)` (a drag, or the picked window's frame clipped to the display under its centre) or nil.
  - `KeyboardShortcuts.Name.captureScrolling` (raw value `captureScrolling`, initial ⌃⇧5) and `KeyboardShortcuts.Name.cancelScrollingCapture` (raw value `cancelScrollingCapture`, initial Escape with no modifiers, no recorder row). `registerShortcuts()` registers ⌃⇧5 and disables the Escape name at launch; Task 5 adds its `onKeyUp` handler and enables it only while a session runs (`KeyboardShortcuts.enable`/`disable`).
  - `AppCoordinator.captureScrolling() async`: lock, `loadContent()`, `selector.select(mode: .scrolling, content:)`, the 100 pt refusal, then (until Task 5 replaces the capture lines) one area capture with the overlay excluded, `selector.dismiss()` and `save(_:)`.
  - `save(_:)`: the PNG, and the clipboard TIFF when `copyImageNow` holds, made in `Task.detached(priority: .userInitiated)`; the clipboard write is `Pasteboard.copy(pngData:tiffData:)`. Signature unchanged; it is still the one save path for every capture.
  - `ThumbnailMaker.cropForThumbnail(_ pixelSize: CGSize) -> CGRect` (pure): the whole image, or for an image taller than 3 times its width its top `width * 3 / 2` rows (integer division), top-left origin as `CGImage.cropping(to:)` takes it. `thumbnail(from:maxSide:)` applies it before scaling, and `showOverlay` applies it to the overlay well's image.

Behaviour (spec 2.8, Starting a capture and One save path):
- The menu gets `Capture Scrolling  ⌃⇧5` after Capture Fullscreen, built by `captureItem`, so it shows the current shortcut and is disabled while `isCapturing`. Settings > Shortcuts gets `Capture scrolling:` after `Capture fullscreen:`. Escape gets no row.
- In scrolling mode a drag selects an area; a click without a drag picks the highlighted window, whose `SCWindow.frame` (CG global points) is clipped to the display under its centre, as a dragged area is. Either result is `.area(rect:display:)`, captured from the display, so a window's rounded corners show what lies behind them.
- An area shorter than 100 pt closes the overlay and posts `Select an area at least 100 points tall.` titled `Scrolling capture`; nothing is captured.
- `CaptureResult.target` is read nowhere downstream (research 4), so the single frame now, and the stitched image from Task 5, travel as `.area(rect:display:)` through `save(_:)` unchanged: after-capture action, file or pending file, record, thumbnail, overlay with Annotate, upload.
- Moving the window-number lookup into `OverlayWindowLookup` (Task 3) keeps both existing selection captures: area capture (`runSelection`, `AppCoordinator.swift:137`) and the loupe snapshot (`takeSnapshots`, `SelectionController.swift:87`) still call `selector.overlayWindows()`, which keeps its cache (filled only by a complete result, cleared by `dismiss()`); window capture never used it (`SCContentFilter(desktopIndependentWindow:)`, `CaptureEngine.swift:33`). The scrolling stub calls it the same way. Step 8 checks all three by hand.

- [ ] **Step 1: Write the failing tests**

`TidyShotTests/ThumbnailMakerTests.swift`. Before `thumbnailPNGRoundTrip` (line 60) add:
```swift
    /// Taller than 3:1 is cut to the top `width * 3 / 2` rows (integer division); 3:1 and
    /// anything flatter are kept whole.
    @Test func cropForThumbnailKeepsTheTopOfTallImages() {
        #expect(ThumbnailMaker.cropForThumbnail(CGSize(width: 2560, height: 16384)) == CGRect(x: 0, y: 0, width: 2560, height: 3840))
        #expect(ThumbnailMaker.cropForThumbnail(CGSize(width: 100, height: 301)) == CGRect(x: 0, y: 0, width: 100, height: 150))
        #expect(ThumbnailMaker.cropForThumbnail(CGSize(width: 101, height: 1000)) == CGRect(x: 0, y: 0, width: 101, height: 151))
        #expect(ThumbnailMaker.cropForThumbnail(CGSize(width: 100, height: 300)) == CGRect(x: 0, y: 0, width: 100, height: 300))
        #expect(ThumbnailMaker.cropForThumbnail(CGSize(width: 2880, height: 1800)) == CGRect(x: 0, y: 0, width: 2880, height: 1800))
        #expect(ThumbnailMaker.cropForThumbnail(CGSize(width: 0, height: 50)) == CGRect(x: 0, y: 0, width: 0, height: 50))
    }

    /// A 400 x 4000 page, red in its top 600 rows and blue below: the thumbnail is the top
    /// 400 x 600 scaled to fit 320, so 213 x 320 and red to its last row.
    @Test func thumbnailOfATallImageShowsItsTop() throws {
        let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try #require(CGContext(data: nil, width: 400, height: 4000, bitsPerComponent: 8, bytesPerRow: 0,
                                             space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 400, height: 4000))
        // CGContext's y runs up, so the image's top 600 rows are the context's last 600.
        context.setFillColor(CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 3400, width: 400, height: 600))
        let page = try #require(context.makeImage())

        let thumbnail = try #require(ThumbnailMaker.thumbnail(from: page))
        #expect(thumbnail.width == 213)
        #expect(thumbnail.height == 320)
        let data = try #require(thumbnail.dataProvider?.data) as Data
        for y in [0, 160, 319] {
            let offset = y * thumbnail.bytesPerRow + 106 * 4
            #expect(data[offset] > 250 && data[offset + 2] < 5, "row \(y) is red")
        }
    }
```
Without the crop the same page gives a 32 x 320 thumbnail, mostly blue, so both assertions on it fail.

`TidyShotTests/ShortcutsTests.swift` (new):
```swift
import KeyboardShortcuts
import Testing
@testable import TidyShot

struct ShortcutsTests {
    /// ⌃⇧5 sits next to the other three; Escape cancels a scrolling capture. No two names share a
    /// key or a default shortcut.
    @Test func scrollingShortcutsHaveTheirInitialKeys() {
        #expect(KeyboardShortcuts.Name.captureScrolling.initialShortcut == .init(.five, modifiers: [.control, .shift]))
        #expect(KeyboardShortcuts.Name.cancelScrollingCapture.initialShortcut == .init(.escape))
        let names: [KeyboardShortcuts.Name] = [.captureArea, .captureWindow, .captureFullscreen,
                                               .captureScrolling, .cancelScrollingCapture]
        #expect(Set(names.map(\.rawValue)).count == names.count)
        #expect(Set(names.compactMap(\.initialShortcut)).count == names.count)
    }
}
```
The test bundle imports `KeyboardShortcuts` through the host app, as the app target links it; `Name` and `Shortcut` are `Hashable` and `Sendable` in the package (`Name.swift:16`, `Shortcut.swift:10`).

- [ ] **Step 2: Run the tests and see them fail**

Run the header's full-suite command. Expected: the build fails with `type 'ThumbnailMaker' has no member 'cropForThumbnail'` in `ThumbnailMakerTests.swift` and `type 'KeyboardShortcuts.Name' has no member 'captureScrolling'` (and `cancelScrollingCapture`) in `ShortcutsTests.swift`.

- [ ] **Step 3: Thumbnail crop**

`TidyShot/Output/ThumbnailMaker.swift`. Type doc (lines 5-6): append `An image taller than three times its width is cut to its top first (cropForThumbnail).` Replace the doc and first line of `thumbnail(from:maxSide:)` (lines 21-23) with:
```swift
    /// The part of an image of `pixelSize` that its thumbnail shows, top-left origin as
    /// `CGImage.cropping(to:)` takes it: all of it, or for an image taller than three times its
    /// width (a scrolling capture) its top `width * 3 / 2` rows, so the thumbnail shows the start of
    /// the page instead of a sliver.
    static func cropForThumbnail(_ pixelSize: CGSize) -> CGRect {
        let width = Int(pixelSize.width)
        let height = Int(pixelSize.height)
        guard width > 0, height > width * 3 else { return CGRect(origin: .zero, size: pixelSize) }
        return CGRect(x: 0, y: 0, width: width, height: width * 3 / 2)
    }

    /// Draws `image`, cut by `cropForThumbnail(_:)`, into a smaller bitmap. Used at capture time,
    /// when the CGImage is already in memory.
    static func thumbnail(from image: CGImage, maxSide: Int = maxSide) -> CGImage? {
        let crop = cropForThumbnail(CGSize(width: image.width, height: image.height))
        let image = crop.height < CGFloat(image.height) ? (image.cropping(to: crop) ?? image) : image
        let size = targetSize(for: CGSize(width: image.width, height: image.height), maxSide: maxSide)
```
The rest of the function is unchanged and draws the shadowing `image`. Both capture-time callers (`makeThumbnail`, `AppCoordinator.swift:324`, and the editor's `replaceThumbnail`, `:1182`) get the crop. `thumbnail(fromPNGData:)` (the Recent Captures fallback and hover preview, decoded by ImageIO with a max pixel size) is left as it is: cropping there would mean decoding the whole image.

`TidyShot/App/AppCoordinator.swift`, `showOverlay` (lines 342-344). Replace the `let thumbnail = ...` line with:
```swift
        // The well shows the top of a tall capture, as its thumbnail does. The crop shares the pixels.
        let shown = image.map { full in
            full.cropping(to: ThumbnailMaker.cropForThumbnail(CGSize(width: full.width, height: full.height))) ?? full
        }
        let thumbnail = shown.map { NSImage(cgImage: $0, size: NSSize(width: CGFloat($0.width) / scale, height: CGFloat($0.height) / scale)) }
```
`latestCapture` (line 354) still keeps the full `image`, so Annotate opens the whole capture.

- [ ] **Step 4: Selection mode, view and controller**

`TidyShot/Selection/SelectionView.swift`:
- `mouseUp` (lines 104-115): replace the `if mode == .area ... else { onCancel?() }` chain (the `defer` stays) with
```swift
        switch SelectionOutcome.resolve(mode: mode, dragRect: dragRect, hasHighlight: highlightedRect != nil) {
        case .area(let rect):
            guard let window else {
                onCancel?()
                return
            }
            completedRect = rect
            onComplete?(window.convertToScreen(convert(rect, to: nil)))
        case .window:
            onPickWindow?()
        case .cancel:
            onCancel?()
        }
```
- `draw`: line 138 `let isDragging = mode != .window && dragStart != nil && dragRect != nil`; line 153 `if let cursor, !isDragging, mode != .window {`; line 157 `if let cursor, mode != .window {`. The highlight branch (lines 144-151) already draws whenever there is no drag, so in scrolling mode the hovered window's hole and border show under the crosshair, and a drag replaces them with the drag rectangle.

`TidyShot/Selection/SelectionController.swift`:
- Lines 26-27:
```swift
        // Window picking is offered in window and scrolling mode; area mode shows just the crosshair.
        picker = mode == .area ? nil : WindowPicker(content: content)
```
- `onPickWindow` (lines 38-41): keep the comment and the `let picked` line; the `Task` becomes `Task { self?.finishPick(picked) }`.
- Line 55: `if mode != .window {` (the snapshot feeds the loupe in area and scrolling mode).
- `updateHover` (lines 118-120): doc `No-op in area mode.` and `guard mode != .area else { return }`.
- Replace `finishArea(_:)` (lines 136-150) with these three; the body of `finishArea(cgRect:)` is the old body from `let centre` on, unchanged:
```swift
    /// A picked window: itself in window mode; in scrolling mode its frame, as an area of the
    /// display under its centre. Nil cancels.
    private func finishPick(_ window: SCWindow?) {
        guard let window else {
            finish(nil)
            return
        }
        if mode == .scrolling {
            finishArea(cgRect: window.frame)
        } else {
            finish(.window(window))
        }
    }

    private func finishArea(_ appKitRect: CGRect) {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        finishArea(cgRect: Geometry.cgRect(fromAppKit: appKitRect, primaryHeight: primaryHeight))
    }

    /// `cgRect` (CoreGraphics global points) clipped to the display under its centre, or the
    /// first display. Cancels when nothing of it is on that display.
    private func finishArea(cgRect: CGRect) {
        let centre = CGPoint(x: cgRect.midX, y: cgRect.midY)
        guard let display = displays.first(where: { $0.frame.contains(centre) }) ?? displays.first else {
            finish(nil)
            return
        }
        let clipped = cgRect.intersection(display.frame)
        guard !clipped.isEmpty else {
            finish(nil)
            return
        }
        finish(.area(rect: clipped, display: display))
    }
```
`overlayWindows()`, `takeSnapshots()`, `dismiss()` and `finish(_:)` are not touched here.

- [ ] **Step 5: Shortcuts, menu and settings**

`TidyShot/App/Shortcuts.swift`, after `captureFullscreen` (line 6):
```swift
    static let captureScrolling = Self("captureScrolling", initial: .init(.five, modifiers: [.control, .shift]))
    /// Escape, live only while a scrolling capture runs (disabled at launch). It has no recorder
    /// row: the recorder refuses keys without modifiers, the hotkey itself does not.
    static let cancelScrollingCapture = Self("cancelScrollingCapture", initial: .init(.escape))
```
`TidyShot/App/StatusMenuController.swift`: after line 74 add `menu.addItem(captureItem("Capture Scrolling", .captureScrolling, #selector(captureScrolling)))`; after line 110 add `@objc private func captureScrolling() { Task { await coordinator.captureScrolling() } }`.

`TidyShot/Settings/ShortcutsSettingsView.swift`, after line 9: `KeyboardShortcuts.Recorder("Capture scrolling:", name: .captureScrolling)`. The caption about ⌘⇧3, ⌘⇧4 and ⌘⇧5 stays.

`TidyShot/App/AppCoordinator.swift`, `registerShortcuts()`: after the `.captureWindow` handler (line 108) add
```swift
        KeyboardShortcuts.onKeyUp(for: .captureScrolling) { [weak self] in
            Task { await self?.captureScrolling() }
        }
        // Escape must never be swallowed outside a scrolling capture; the session enables it.
        KeyboardShortcuts.disable(.cancelScrollingCapture)
```
With the name disabled and no handler, KeyboardShortcuts registers no Carbon hotkey for Escape (`registerIfNeeded(for:)` needs an active handler, `KeyboardShortcuts.swift:224`), and a later `onKeyUp` for a disabled name registers nothing until `enable`.

- [ ] **Step 6: captureScrolling and the detached encode**

`TidyShot/App/AppCoordinator.swift`, after `captureWindow()` (line 126):
```swift
    /// Capture Scrolling: select an area or a window's frame, then (Task 5) run the scrolling
    /// session. Until then one frame of the area is captured and saved like an area capture.
    func captureScrolling() async {
        await withCaptureLock {
            guard let content = await loadContent() else { return }
            guard let selection = await selector.select(mode: .scrolling, content: content) else { return }
            guard case .area(let rect, let display) = selection else {
                selector.dismiss()
                return
            }
            guard rect.height >= CGFloat(ScrollCaptureLimits.minimumAreaHeightPoints) else {
                selector.dismiss()
                notifier.notifyError("Select an area at least 100 points tall.", title: "Scrolling capture")
                return
            }
            let overlays = await selector.overlayWindows()
            let result = await capture(.area(rect: rect, display: display), excludingWindows: overlays)
            selector.dismiss()
            if let result {
                await save(result)
            }
        }
    }
```
The `.window` branch cannot happen in scrolling mode and only closes the overlay. `CGFloat(...)` compiles whether Task 1 declared the limit as `Int` or `CGFloat`. Task 5 replaces the three lines from `let overlays` to `selector.dismiss()` with `selector.dismiss()` and `scrollCapture.run(rect:display:)`, and turns its outcome into the `CaptureResult` for `save(_:)`.

`save(_:)` (lines 168-207). Remove the encode block at lines 176-185 (`let png: Data` through its `catch`). Keep `action`, `destination` and `copyImageNow` (lines 187-198) where they are, so they now come right after `let image = result.scaled`; the destination's keychain read now happens before the encode, which changes nothing a user sees. Replace `let copiedChangeCount ...` (lines 199-200) with:
```swift
        // A scrolling capture can be 16,384 px tall: encode it, and the clipboard's TIFF, off the
        // main actor. Every capture takes this path; for a normal one the cost is one hop.
        let encoded: (png: Data, tiff: Data?)
        do {
            encoded = try await Task.detached(priority: .userInitiated) { () throws -> (png: Data, tiff: Data?) in
                (try ImageEncoder.pngData(from: image.image, scale: image.scale),
                 copyImageNow ? Pasteboard.tiffData(of: image.image, scale: image.scale) : nil)
            }.value
        } catch {
            NSLog("Encode failed: \(error.localizedDescription)")
            // Never drop a capture: without PNG data the clipboard still gets the image as TIFF.
            Pasteboard.copy(image: image.image, scale: image.scale)
            notifier.notifyError(error.localizedDescription)
            return
        }
        let png = encoded.png
        let copiedChangeCount: Int? = copyImageNow ? Pasteboard.copy(pngData: png, tiffData: encoded.tiff) : nil
```
The `persist` call and the `clipboardOwner` lines after it are unchanged. Extend the doc comment (lines 168-172) with: `The PNG, and the TIFF when the image goes on the clipboard now, are made in a detached task, so a tall capture does not hold up the main actor.` The closure captures only `image` (`ScaledImage`, Sendable) and the `Bool`; `ImageEncoder` and `Pasteboard.tiffData` are nonisolated. `save(_:)` is only called inside `withCaptureLock` (lines 116 and 145, and `captureScrolling`), so the new suspension point lets no second capture start. The rare fallbacks that copy on the main actor (`keepOnClipboard`, the TIFF-only copy above) stay as they are.

- [ ] **Step 7: Run the suite**

Run the header's full-suite command. Expected: no `error:` lines, and `Test run with 547 tests in 70 suites passed`. This task adds 3 tests (`cropForThumbnailKeepsTheTopOfTallImages`, `thumbnailOfATallImageShowsItsTop`, `scrollingShortcutsHaveTheirInitialKeys`) and one suite (`ShortcutsTests`). `WindowPickerTests`, `ImageEncoderTests` and the other `ThumbnailMakerTests` are unchanged and pass.

- [ ] **Step 8: Hand checks**

Build and run the app (re-grant Screen Recording after an ad-hoc rebuild).
- The menu reads Capture Area, Capture Window, Capture Fullscreen, `Capture Scrolling  ⌃⇧5`. Settings > Shortcuts has a `Capture scrolling:` row showing ⌃⇧5 and no Escape row. Record another shortcut for it and the menu title follows.
- ⌃⇧5: crosshair and loupe as in area mode; moving over windows highlights them as in window mode. Drag a 300 pt tall area: one file saved, the Quick Access overlay shows it with Annotate, the record's pixel size is the area at the display's scale. With the after-capture action set to upload, it uploads as an area capture does.
- ⌃⇧5 and click a window without dragging: the saved image is the window's frame captured from the display, with whatever lies behind its corners; a window half off its display is clipped to the display under its centre.
- ⌃⇧5 and drag a 60 pt tall area: the overlay closes, the notification `Select an area at least 100 points tall.` titled `Scrolling capture` appears, nothing is saved. Escape in the overlay cancels as before.
- Escape outside a capture: in another app (a Safari full-screen video, a TextEdit autocomplete list), Escape still reaches that app. TidyShot has not registered it.
- Overlay exclusion after Task 3's move: ⌃⇧4 area capture has no dimming in the saved image and the loupe shows the screen without the dimming; ⌃⇧2 window capture still saves the window with transparent corners; both menu items are disabled while a capture runs.
- Encode off the main actor: with Copy image to clipboard on, take an area capture and paste into Preview (File > New from Clipboard): it pastes at point size, and a paste into a text field of Slack or Mail attaches the PNG. With Upload only, the pending file uploads and the URL lands on the clipboard. Thumbnails of normal captures in Recent Captures and the overlay look as before (a tall capture comes with Task 5; the unit tests cover the crop).

- [ ] **Step 9: Commit**

```bash
git add TidyShot/Selection/SelectionController.swift TidyShot/Selection/SelectionView.swift TidyShot/App/Shortcuts.swift TidyShot/App/StatusMenuController.swift TidyShot/Settings/ShortcutsSettingsView.swift TidyShot/App/AppCoordinator.swift TidyShot/Output/ThumbnailMaker.swift TidyShotTests/ThumbnailMakerTests.swift TidyShotTests/ShortcutsTests.swift
git commit -m "feat: Capture Scrolling entry points, off-main encode in save and thumbnail top crop"
```

### Task 5: Manual session

**Files:**
- Create: `TidyShot/Scrolling/ScrollClock.swift` (`ScrollClock`, `SystemScrollClock`)
- Create: `TidyShot/Scrolling/ScrollCaptureSession.swift` (`ScrollMode`, `ScrollCapturePhase`, `ScrollCaptureOutcome`, `ScrollCaptureSession`)
- Create: `TidyShot/Scrolling/ScrollCaptureController.swift`
- Create: `TidyShot/Scrolling/ScrollCapturePanel.swift`
- Create: `TidyShot/Scrolling/ScrollCaptureView.swift`
- Create: `TidyShot/Scrolling/ScrollAreaFrameWindow.swift` (`ScrollAreaFrameWindow`, `ScrollAreaFrameView`)
- Modify: `TidyShot/App/AppCoordinator.swift` (the `selector` property, line 30 on `main`; `registerShortcuts()`, lines 99-109 plus Task 4's additions; Task 4's `captureScrolling()`, added after `captureWindow()`, line 126 on `main`)
- Create: `TidyShotTests/Support/ScrollSessionFakes.swift` (`FakeFrameSource`, `FakeScrollClock`, `FakeClockTimedOut`, `stitchedPixels(of:)`; no tests of its own)
- Test: `TidyShotTests/ScrollCaptureSessionTests.swift` (create, struct `ScrollCaptureSessionTests`)

**Interfaces:**
- Consumes:
  - `main`: `CaptureEngine` and `CaptureEngine.screen(forDisplayID:)` (`CaptureEngine.swift:59`), `CaptureError.noImage` (`CaptureTarget.swift:22-29`), `CaptureResult(image:scale:target:)` (`CaptureTarget.swift:15`), `ScaledImage` (`ScaledImage.swift:6`), `Geometry.appKitRect(fromCG:primaryHeight:)` and `Geometry.pixelSize(points:scale:)` (`Geometry.swift:11`, `:24`), `CrosshairStyle.haloAlpha` (`Luminance.swift:55`), `Notifier.notifyError(_:title:)` (`Notifier.swift:36`), `AppCoordinator.save(_:)`, `withCaptureLock(_:)`, `loadContent()`, `KeyboardShortcuts.onKeyUp(for:action:)`, `enable(_:)`, `disable(_:)`; the global test helper `eventually(_:)` (`UploadQueueTests.swift:115`).
  - Task 1: `ScrollFrame` (`width`, `height`, `bgra`), `OverlapMatch`, `OverlapFinder(scale:)`, `StitchStep` (`match`, `isFull`), `PreviewStrip` (`width`, `height`, `bgra`, `isEmpty`), `StitchedImage(width:height:bgra:)`, `ScrollCaptureLimits.maxPixelHeight` and `previewMaxWidth`; test side `SyntheticPage(width:height:header:footer:pageHeight:)`, `frame(at:animated:)`, `finder`, `compare(_:reached:)`, `maxOffset`.
  - Task 2: `ScrollCaptureStatus` (`readyManual`, `manualCapturing`, `manualLost`, `heightLimit`, `finishing`, `text`, `sizeText(width:height:locale:)`), `ScrollPanelGeometry.frame(panelSize:area:visibleFrame:)`, `height(wanted:areaHeight:)`, `panelWidth`.
  - Task 3: `FrameEvent` (`.frame`, `.idle`, `.stopped`), `protocol FrameSource` (main actor; `start() async throws -> AsyncStream<FrameEvent>`, `stop() async`; `stop()` finishes the sequence after any frame still buffered), `ScrollFrameSource(rect:display:engine:)` with `scale` and `colorSpace`, `StitchProgress` (`heightPixels`, `step`, `previewDelta`), `ScrollStitchEngine(finder:maxPixelHeight:)`, `begin(first:)`, `add(_:predicted:) -> StitchProgress`, `finish(scale:colorSpace:) -> ScaledImage?`.
  - Task 4: `SelectionMode.scrolling`, `KeyboardShortcuts.Name.captureScrolling` and `.cancelScrollingCapture` (disabled at launch, no handler yet), `AppCoordinator.captureScrolling()` with its single-frame stub.
- Produces (Task 6 relies on these names):
  - `protocol ScrollClock: AnyObject { var now: ContinuousClock.Instant { get }; func sleep(for duration: Duration) async throws }` (main actor by the module default) and `final class SystemScrollClock: ScrollClock`.
  - `nonisolated enum ScrollMode: Equatable, Sendable { case manual, auto }`, `nonisolated enum ScrollCapturePhase: Equatable, Sendable { case ready, capturing(ScrollMode), finishing, ended }`.
  - `nonisolated enum ScrollCaptureOutcome: Sendable { case image(ScaledImage), cancelled, failed(String, partial: ScaledImage?) }` with `var imageToSave: ScaledImage?` and `var failureNotice: (title: String, body: String)?`.
  - `@Observable final class ScrollCaptureSession`: `init(source: any FrameSource, engine: ScrollStitchEngine, area: CGRect, scale: CGFloat, colorSpace: CGColorSpace, clock: any ScrollClock = SystemScrollClock())`; `let area` (CG global points), `let scale`, `let widthPixels`, `let clock`; `private(set) var phase`, `heightPixels`, `status`, `preview: CGImage?`, `hasFirstFrame`, `outcome: ScrollCaptureOutcome?`, `framesRead`, `latestFrame: ScrollFrame?`, `latestFrameAt: ContinuousClock.Instant?`, `frameSerial: Int`; `var onEnd: ((ScrollCaptureOutcome) -> Void)?`; `func start() async`, `func done() async`, `func cancel() async`, `func advance() async` (Start, then Done), `func finish(showing line: ScrollCaptureStatus) async`; `static let endLineDelay: Duration` (400 ms), `static let previewInterval: Duration` (250 ms); `nonisolated static func image(bgra:width:height:colorSpace:) -> CGImage?`.
  - `final class ScrollCaptureController`: `init(engine: CaptureEngine)`, `var isRunning: Bool`, `func run(rect: CGRect, display: SCDisplay) async -> ScrollCaptureOutcome`, `func advance()`, `func cancel()`.
  - `final class ScrollCapturePanel: NSPanel` (`init(session:)`), `struct ScrollCaptureView: View` (`static let padding`, `static let chromeHeight`, `static var previewWidth`, `static func previewHeight(for:) -> CGFloat`), `final class ScrollAreaFrameWindow: NSWindow` (`init(area:)`, AppKit global points).
  - Test side: `FakeFrameSource` (`startCount`, `stopCount`, `startError`, `send(_:)`), `FakeScrollClock` (`now`, `advance(by:)`, `run(until:limit:)`, `run(for:)`), `FakeClockTimedOut`, `stitchedPixels(of:) throws -> StitchedImage`.

Behaviour (spec 2.8, The session, Exact strings, Session model, One save path):
- After selection the overlay is gone and two windows appear: the dashed area frame just outside the area, and the 240 pt panel placed by `ScrollPanelGeometry` on the area's screen. The panel shows the preview (anchored to its bottom), the readout `ScrollCaptureStatus.sizeText` in image pixels, the status line, and **Cancel** (`.cancelAction`) with **Start** (`.defaultAction`) before Start, **Cancel** with **Done** (`.defaultAction`) after. The panel's height follows the preview through `ScrollPanelGeometry.height(wanted:areaHeight:)`.
- The stream starts at Start (`ScrollFrameSource.start()` builds the filter then, with the panel and the frame on screen). The first frame begins the stitch and is the preview until the first move commits rows; after that the preview is the stitched rows (`StitchProgress.previewDelta`), rebuilt at most 4 times a second. The readout is `StitchProgress.heightPixels`.
- Manual mode feeds every frame to the engine. A `.lost` shows `Too fast. Scroll back up a little.`; the next `.moved` puts back `Scroll down slowly. Click Done at the end.`. When `step.isFull`, the line `Reached the 16,384 pixel limit.` shows for 0.4 s, then the session finishes as Done does.
- Done is ignored until the first frame has arrived (the button is disabled meanwhile). Done stops the stream, stitches the frame still buffered, and ends with `.image`; with no movement that is the first frame alone. Cancel and Escape end with `.cancelled` at once, from any phase but `.ended`, and nothing is written. A stream that stops by itself ends with `.failed(reason, partial:)`, partial being what was stitched when there was a first frame; a stream that cannot start ends with `.failed(reason, partial: nil)`.
- Escape is the `cancelScrollingCapture` hotkey: enabled when the panel appears, disabled when the session ends, so it works with another app frontmost and is never swallowed outside a session. The Capture Scrolling shortcut, pressed while a session runs, acts as Start, then as Done.
- `AppCoordinator.captureScrolling()` keeps Task 4's lock, selection, and 100 pt refusal, then dismisses the overlay and runs the controller. `.image` and a `.failed` with a partial image go to `save(_:)` as `CaptureResult(image:scale:target: .area(rect:display:))`, so the after-capture action, the file, the record, the thumbnail, the overlay with Annotate and the upload behave as for any capture. Failures post `The capture stopped early: <reason> TidyShot saved what it had.` titled `Scrolling capture stopped`, or `<reason>` titled `Scrolling capture failed`.

- The session follows Task 3's event contract. The source keeps the last moved frame when an idle follows it, so a trailing idle never drops it. `stop()` sends no `.stopped` and still delivers a buffered frame before the sequence ends, so `done()` awaits `stop()`, then the read task (which stitches what was buffered), and only then calls the engine's `finish`. `.frame` carries no time, so `take(_:)` stamps each frame with the session's clock (`latestFrameAt`) for Task 6's `FrameSettler`. The first frame's rows reach `previewDelta` only after the first move commits them, so the session draws that frame as the preview itself.

Two choices the spec leaves open, settled here:
- `.stopped(nil)` (the stream stopped and ScreenCaptureKit gave no error) is a failure like any other, with the reason `The screen recording stream stopped.` (`ScrollCaptureSession.streamStoppedReason`). Engine `finish` returning nil (a CGImage that could not be made) ends with `.failed(CaptureError.noImage.localizedDescription, partial: nil)`.
- TidyShot is the active app after the selection overlay, and stays so: the panel is made key with `makeKeyAndOrderFront`, so Return and Escape reach it, and the app below still scrolls under the pointer without a click (wheel events go to the window under the pointer whether or not its app is active).

- [ ] **Step 1: Write the failing tests**

`TidyShotTests/Support/ScrollSessionFakes.swift` (new):
```swift
import CoreGraphics
import Foundation
import Testing
@testable import TidyShot

/// A `FrameSource` the tests feed by hand. Unlike the stream, it buffers without limit, so every
/// frame a test sends reaches the session, in order. `stop()` finishes the events after what is
/// buffered, as `ScrollFrameSource` does.
final class FakeFrameSource: FrameSource {
    private(set) var startCount = 0
    private(set) var stopCount = 0
    /// Thrown by `start()` when set.
    var startError: (any Error)?
    private var continuation: AsyncStream<FrameEvent>.Continuation?

    func start() async throws -> AsyncStream<FrameEvent> {
        startCount += 1
        if let startError { throw startError }
        let (events, continuation) = AsyncStream.makeStream(of: FrameEvent.self)
        self.continuation = continuation
        return events
    }

    func stop() async {
        stopCount += 1
        continuation?.finish()
        continuation = nil
    }

    func send(_ event: FrameEvent) {
        continuation?.yield(event)
    }
}

struct FakeClockTimedOut: Error {}

/// A `ScrollClock` that moves only when the test moves it. Sleepers wait on continuations, never
/// on a thread, so nothing blocks the main actor the tests run on.
final class FakeScrollClock: ScrollClock {
    private struct Sleeper {
        let id: Int
        let deadline: ContinuousClock.Instant
        let continuation: CheckedContinuation<Void, any Error>
    }

    private(set) var now = ContinuousClock.now
    private var sleepers: [Sleeper] = []
    private var nextID = 0

    func sleep(for duration: Duration) async throws {
        try Task.checkCancellation()
        let id = nextID
        nextID += 1
        let deadline = now + duration
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                sleepers.append(Sleeper(id: id, deadline: deadline, continuation: continuation))
            }
        } onCancel: {
            Task { @MainActor in self.resume(id, throwing: CancellationError()) }
        }
    }

    /// Moves time forward by `duration`, waking each sleeper it passes in deadline order and
    /// letting the woken code run on the main actor before the next. Tasks created just before
    /// the call run first, so a sleep they are about to start counts from the time before.
    func advance(by duration: Duration) async {
        await Self.letOthersRun()
        let target = now + duration
        while let next = earliest(), next.deadline <= target {
            now = max(now, next.deadline)
            resume(next.id, throwing: nil)
            await Self.letOthersRun()
        }
        now = target
        await Self.letOthersRun()
    }

    /// Wakes sleepers in deadline order until `condition` holds. After each wake-up it waits in
    /// real time, up to two seconds, until something sleeps on the clock again or the condition
    /// holds, so work on other actors (the stitch engine) finishes between steps.
    func run(until condition: () -> Bool, limit: Duration = .seconds(300)) async throws {
        let end = now + limit
        while !condition() {
            guard try await waitForSleeper(orUntil: condition, realTime: .seconds(2)) else { throw FakeClockTimedOut() }
            if condition() { return }
            guard let next = earliest(), next.deadline <= end else { throw FakeClockTimedOut() }
            now = max(now, next.deadline)
            resume(next.id, throwing: nil)
        }
    }

    /// Lets `duration` pass, waking sleepers as `run(until:)` does. When nothing sleeps on the
    /// clock for 250 ms of real time, the rest of the time passes at once.
    func run(for duration: Duration) async throws {
        let target = now + duration
        while true {
            guard try await waitForSleeper(orUntil: { false }, realTime: .milliseconds(250)),
                  let next = earliest(), next.deadline <= target else { break }
            now = max(now, next.deadline)
            resume(next.id, throwing: nil)
        }
        now = max(now, target)
    }

    private func waitForSleeper(orUntil condition: () -> Bool, realTime: Duration) async throws -> Bool {
        await Self.letOthersRun()
        let giveUp = ContinuousClock.now + realTime
        while sleepers.isEmpty && !condition() {
            guard ContinuousClock.now < giveUp else { return false }
            try await Task.sleep(for: .milliseconds(1))
        }
        return true
    }

    /// The sleeper with the earliest deadline; among equal deadlines, the first to sleep.
    private func earliest() -> Sleeper? {
        sleepers.min { $0.deadline < $1.deadline }
    }

    private func resume(_ id: Int, throwing error: (any Error)?) {
        guard let index = sleepers.firstIndex(where: { $0.id == id }) else { return }
        let sleeper = sleepers.remove(at: index)
        if let error {
            sleeper.continuation.resume(throwing: error)
        } else {
            sleeper.continuation.resume()
        }
    }

    private static func letOthersRun() async {
        for _ in 0..<10 { await Task.yield() }
    }
}

/// The stitched image's own bytes. The engine wraps the stitcher's BGRA rows in the CGImage
/// without copying them, so the provider's data is exactly what the stitcher wrote.
func stitchedPixels(of image: ScaledImage) throws -> StitchedImage {
    let cgImage = image.image
    #expect(cgImage.bytesPerRow == cgImage.width * 4)
    let data = try #require(cgImage.dataProvider?.data)
    return StitchedImage(width: cgImage.width, height: cgImage.height, bgra: data as Data)
}
```

`TidyShotTests/ScrollCaptureSessionTests.swift` (new):
```swift
import CoreGraphics
import Foundation
import Testing
@testable import TidyShot

/// The manual scrolling session on synthetic frames (spec 2.8, Session model): a fake source, the
/// real stitch engine, a fake clock. Frames are 160 x 400 pixels at scale 2: a 40 row header, a
/// 30 row footer and a 330 row band over a 2,000 row page.
struct ScrollCaptureSessionTests {
    let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!

    nonisolated struct StreamBroke: LocalizedError {
        var errorDescription: String? { "The display went to sleep." }
    }

    func makePage() -> SyntheticPage {
        SyntheticPage(width: 160, height: 400, header: 40, footer: 30, pageHeight: 2000)
    }

    func makeSession(_ page: SyntheticPage, maxPixelHeight: Int = ScrollCaptureLimits.maxPixelHeight)
        -> (session: ScrollCaptureSession, source: FakeFrameSource, clock: FakeScrollClock) {
        let source = FakeFrameSource()
        let clock = FakeScrollClock()
        let session = ScrollCaptureSession(
            source: source, engine: ScrollStitchEngine(finder: page.finder, maxPixelHeight: maxPixelHeight),
            area: CGRect(x: 100, y: 100, width: CGFloat(page.width) / 2, height: CGFloat(page.height) / 2),
            scale: 2, colorSpace: sRGB, clock: clock)
        return (session, source, clock)
    }

    func send(_ page: inout SyntheticPage, _ source: FakeFrameSource, offsets: [Int]) {
        for offset in offsets {
            source.send(.frame(page.frame(at: offset, animated: false)))
        }
    }

    /// Start, frames scrolled by the user, Done: the page from the top down to where the user
    /// stopped, header once, footer once, pixel for pixel.
    @Test func startFramesAndDoneGiveTheStitchedPage() async throws {
        var page = makePage()
        let (session, source, _) = makeSession(page)
        var ended: [ScrollCaptureOutcome] = []
        session.onEnd = { ended.append($0) }
        #expect(session.phase == .ready)
        #expect(session.status == .readyManual)
        #expect(session.widthPixels == 160)
        #expect(session.heightPixels == 400)
        #expect(source.startCount == 0)

        await session.start()
        #expect(source.startCount == 1)
        #expect(session.phase == .capturing(.manual))
        #expect(session.status == .manualCapturing)
        send(&page, source, offsets: [0, 60, 120, 200, 300])
        try await eventually { session.heightPixels == 700 }
        #expect(session.framesRead == 5)

        await session.done()
        #expect(source.stopCount == 1)
        #expect(session.phase == .ended)
        #expect(ended.count == 1)
        guard case .image(let image)? = session.outcome else {
            Issue.record("no image")
            return
        }
        #expect(image.scale == 2)
        let comparison = page.compare(try stitchedPixels(of: image), reached: 300)
        #expect(comparison.actualHeight == comparison.expectedHeight)
        #expect(comparison.mismatched == 0)
        #expect(session.outcome?.failureNotice == nil)

        // A second Done, a Cancel or a Start after the end change nothing.
        await session.done()
        await session.cancel()
        await session.start()
        #expect(ended.count == 1)
        #expect(source.startCount == 1)
    }

    /// Cancel discards everything at once and stops the stream; before Start it never starts it.
    @Test func cancelGivesNothingAndStopsTheStream() async throws {
        var page = makePage()
        let (session, source, _) = makeSession(page)
        await session.start()
        send(&page, source, offsets: [0, 80])
        try await eventually { session.heightPixels == 480 }

        await session.cancel()
        guard case .cancelled? = session.outcome else {
            Issue.record("not cancelled")
            return
        }
        #expect(session.phase == .ended)
        #expect(source.stopCount >= 1)
        #expect(session.outcome?.imageToSave == nil)
        #expect(session.outcome?.failureNotice == nil)

        let (unstarted, idleSource, _) = makeSession(page)
        await unstarted.cancel()
        guard case .cancelled? = unstarted.outcome else {
            Issue.record("not cancelled")
            return
        }
        #expect(idleSource.startCount == 0)
    }

    /// `advance()` is Start, then Done. Done waits for the first frame; with no movement the
    /// result is that frame alone, which is also the preview until rows are stitched.
    @Test func doneWithoutMovementGivesTheFirstFrame() async throws {
        var page = makePage()
        let (session, source, _) = makeSession(page)
        await session.advance()
        #expect(session.phase == .capturing(.manual))
        await session.advance()
        #expect(session.phase == .capturing(.manual))
        #expect(!session.hasFirstFrame)
        #expect(source.stopCount == 0)

        let first = page.frame(at: 0, animated: false)
        source.send(.frame(first))
        source.send(.frame(page.frame(at: 0, animated: false)))
        try await eventually { session.hasFirstFrame }
        #expect(session.preview?.width == 160)
        #expect(session.preview?.height == 400)

        await session.advance()
        guard case .image(let image)? = session.outcome else {
            Issue.record("no image")
            return
        }
        let stitched = try stitchedPixels(of: image)
        #expect(stitched.height == 400)
        #expect(stitched.bgra == first.bgra)
    }

    /// At the cap the limit line shows for `endLineDelay`, then the session finishes by itself
    /// with exactly `maxPixelHeight` rows.
    @Test func theCapFinishesByItselfAfterTheLimitLine() async throws {
        var page = makePage()
        let (session, source, clock) = makeSession(page, maxPixelHeight: 600)
        await session.start()
        send(&page, source, offsets: [0, 100, 200, 300, 400])
        try await eventually { session.status == .heightLimit }
        #expect(session.heightPixels == 600)
        #expect(session.phase == .capturing(.manual))
        #expect(session.outcome == nil)

        await clock.advance(by: ScrollCaptureSession.endLineDelay)
        try await eventually { session.phase == .ended }
        guard case .image(let image)? = session.outcome else {
            Issue.record("no image")
            return
        }
        let stitched = try stitchedPixels(of: image)
        #expect(stitched.height == 600)
        #expect(page.compare(stitched, reached: 400).mismatched == 0)
    }

    /// A jump past the band loses the place: the too-fast line shows until a frame overlaps the
    /// last accepted one again, and the output has no gap.
    @Test func tooFastShowsTheLineUntilTheNextMovement() async throws {
        var page = makePage()
        let (session, source, _) = makeSession(page)
        await session.start()
        send(&page, source, offsets: [0, 100])
        try await eventually { session.heightPixels == 500 }
        #expect(session.status == .manualCapturing)

        send(&page, source, offsets: [700])
        try await eventually { session.status == .manualLost }
        #expect(session.status.text == "Too fast. Scroll back up a little.")
        #expect(session.heightPixels == 500)

        send(&page, source, offsets: [200])
        try await eventually { session.status == .manualCapturing && session.heightPixels == 600 }

        await session.done()
        guard case .image(let image)? = session.outcome else {
            Issue.record("no image")
            return
        }
        let comparison = page.compare(try stitchedPixels(of: image), reached: 200)
        #expect(comparison.actualHeight == comparison.expectedHeight)
        #expect(comparison.mismatched == 0)
    }

    /// A stream that stops by itself keeps what was stitched; with nothing stitched, or a stream
    /// that cannot start, there is only the reason. The notices use the spec's exact strings.
    @Test func aStreamErrorKeepsWhatWasStitched() async throws {
        var page = makePage()
        let (session, source, _) = makeSession(page)
        await session.start()
        send(&page, source, offsets: [0, 100])
        try await eventually { session.heightPixels == 500 }
        source.send(.stopped(StreamBroke()))
        try await eventually { session.phase == .ended }
        guard case .failed(let reason, let partial?)? = session.outcome else {
            Issue.record("no partial image")
            return
        }
        #expect(reason == "The display went to sleep.")
        let comparison = page.compare(try stitchedPixels(of: partial), reached: 100)
        #expect(comparison.actualHeight == 500)
        #expect(comparison.mismatched == 0)
        #expect(session.outcome?.imageToSave?.image.height == 500)
        #expect(session.outcome?.failureNotice?.title == "Scrolling capture stopped")
        #expect(session.outcome?.failureNotice?.body
                == "The capture stopped early: The display went to sleep. TidyShot saved what it had.")

        let (empty, emptySource, _) = makeSession(page)
        await empty.start()
        emptySource.send(.stopped(StreamBroke()))
        try await eventually { empty.phase == .ended }
        guard case .failed(let emptyReason, nil)? = empty.outcome else {
            Issue.record("expected a failure without an image")
            return
        }
        #expect(emptyReason == "The display went to sleep.")
        #expect(empty.outcome?.imageToSave == nil)
        #expect(empty.outcome?.failureNotice?.title == "Scrolling capture failed")
        #expect(empty.outcome?.failureNotice?.body == "The display went to sleep.")

        let (refused, refusedSource, _) = makeSession(page)
        refusedSource.startError = StreamBroke()
        await refused.start()
        guard case .failed("The display went to sleep.", nil)? = refused.outcome else {
            Issue.record("expected the start error")
            return
        }
        #expect(refused.phase == .ended)
    }

    /// The preview grows with the stitched rows, rebuilt at most every `previewInterval`, and
    /// is never wider than `ScrollCaptureLimits.previewMaxWidth`.
    @Test func previewFollowsTheStitchAtMostFourTimesASecond() async throws {
        var page = makePage()
        let (session, source, clock) = makeSession(page)
        #expect(ScrollCaptureSession.previewInterval == .milliseconds(250))
        await session.start()
        // The first move commits the first frame's header and band: 370 rows.
        send(&page, source, offsets: [0, 60])
        try await eventually { session.preview?.height == 370 }
        #expect(session.preview?.width == 160)
        #expect((session.preview?.width ?? .max) <= ScrollCaptureLimits.previewMaxWidth)

        // The next 60 rows come too soon after; they show once the interval has passed.
        send(&page, source, offsets: [120])
        try await eventually { session.heightPixels == 520 }
        #expect(session.preview?.height == 370)
        await clock.advance(by: .milliseconds(250))
        try await eventually { session.preview?.height == 430 }
        await session.cancel()
    }
}
```

Expected numbers, all from the page geometry (band 330): a frame at offset `o` makes `heightPixels` `o + 400`; the stitch that reached offset `o` is `40 + o + 330 + 30` rows; after a move to `o` the committed rows end at the previous accepted offset plus the band end (370), which is the preview's height.

- [ ] **Step 2: Run the tests and watch them fail**

Run:
```bash
xcodegen generate && xcodebuild test -project TidyShot.xcodeproj -scheme TidyShot -destination 'platform=macOS' -derivedDataPath .build 2>&1 | grep -E "Test run with|error:|TEST"
```
Expected: compile errors, among them `cannot find type 'ScrollClock' in scope`, `cannot find 'ScrollCaptureSession' in scope` and `cannot find type 'ScrollCaptureOutcome' in scope`, then `** TEST FAILED **` and no `Test run with` line.

- [ ] **Step 3: The clock**

`TidyShot/Scrolling/ScrollClock.swift`:
```swift
import Foundation

/// The time the scrolling session and the auto-scroll driver run on: the continuous clock in the
/// app, a clock the test moves in tests (spec 2.8, Session model). `sleep` throws
/// `CancellationError` when the task is cancelled.
protocol ScrollClock: AnyObject {
    var now: ContinuousClock.Instant { get }
    func sleep(for duration: Duration) async throws
}

final class SystemScrollClock: ScrollClock {
    var now: ContinuousClock.Instant { .now }

    func sleep(for duration: Duration) async throws {
        try await Task.sleep(for: duration)
    }
}
```

- [ ] **Step 4: The session**

`TidyShot/Scrolling/ScrollCaptureSession.swift`:
```swift
import CoreGraphics
import Foundation
import Observation

/// How the page moves during a capture: the user scrolls, or TidyShot posts wheel events.
nonisolated enum ScrollMode: Equatable, Sendable {
    case manual
    case auto
}

/// Where a scrolling capture is. `.finishing` stitches the last frame; `.ended` has an outcome.
nonisolated enum ScrollCapturePhase: Equatable, Sendable {
    case ready
    case capturing(ScrollMode)
    case finishing
    case ended
}

/// What a scrolling capture gave (spec 2.8, Session model).
nonisolated enum ScrollCaptureOutcome: Sendable {
    case image(ScaledImage)
    case cancelled
    /// The stream failed. `partial` is what was stitched before, when a first frame had arrived.
    case failed(String, partial: ScaledImage?)

    /// What `AppCoordinator.save(_:)` gets: the stitched image, or the partial one.
    var imageToSave: ScaledImage? {
        switch self {
        case .image(let image): image
        case .failed(_, let partial): partial
        case .cancelled: nil
        }
    }

    /// The failure notification (spec 2.8, Exact strings), or nil when there is none.
    var failureNotice: (title: String, body: String)? {
        switch self {
        case .image, .cancelled:
            nil
        case .failed(let reason, .some):
            (title: "Scrolling capture stopped", body: "The capture stopped early: \(reason) TidyShot saved what it had.")
        case .failed(let reason, .none):
            (title: "Scrolling capture failed", body: reason)
        }
    }
}

/// One scrolling capture, from Start to Done or Cancel (spec 2.8, Session model). It reads the
/// frame source, feeds the stitch engine, and keeps what the panel shows: the phase, the size
/// readout, the status line and the live preview. It is built with a `FrameSource` and a clock,
/// so its tests run on synthetic frames.
@Observable
final class ScrollCaptureSession {
    /// How long an end line (the height limit, and in auto mode "Reached the end.") shows before
    /// the session finishes.
    static let endLineDelay: Duration = .milliseconds(400)
    /// The live preview is rebuilt at most this often (4 times a second).
    static let previewInterval: Duration = .milliseconds(250)
    /// The reason when the stream stops by itself without an error.
    static let streamStoppedReason = "The screen recording stream stopped."

    /// The captured area in CoreGraphics global points.
    let area: CGRect
    /// Pixels per point of the area's display.
    let scale: CGFloat
    let widthPixels: Int
    let clock: any ScrollClock

    private(set) var phase: ScrollCapturePhase = .ready
    /// What Done would give now, in pixels, for the size readout. The area's height before the
    /// first frame.
    private(set) var heightPixels: Int
    private(set) var status: ScrollCaptureStatus = .readyManual
    /// The first frame until rows are stitched, then the stitched rows, at most
    /// `ScrollCaptureLimits.previewMaxWidth` pixels wide.
    private(set) var preview: CGImage?
    /// True once the first frame has arrived. Done waits for it.
    private(set) var hasFirstFrame = false
    private(set) var outcome: ScrollCaptureOutcome?
    /// Frame events read so far, for the tests.
    @ObservationIgnored private(set) var framesRead = 0
    /// The newest frame read, when the session read it (frames carry no time, so the session
    /// stamps them with its clock), and a count that changes with each one. The auto-scroll
    /// driver (Task 6) settles on them through `FrameSettler`.
    @ObservationIgnored private(set) var latestFrame: ScrollFrame?
    @ObservationIgnored private(set) var latestFrameAt: ContinuousClock.Instant?
    @ObservationIgnored private(set) var frameSerial = 0
    /// Called once, when the session ends.
    @ObservationIgnored var onEnd: ((ScrollCaptureOutcome) -> Void)?

    private let source: any FrameSource
    private let engine: ScrollStitchEngine
    private let colorSpace: CGColorSpace
    @ObservationIgnored private var readTask: Task<Void, Never>?
    @ObservationIgnored private var endTask: Task<Void, Never>?
    @ObservationIgnored private var previewTask: Task<Void, Never>?
    @ObservationIgnored private var previewRows = PreviewRows()
    @ObservationIgnored private var lastPreviewAt: ContinuousClock.Instant?

    /// `area` is in CoreGraphics global points on one display of backing scale `scale`;
    /// `colorSpace` is the space the source delivers frames in.
    init(source: any FrameSource, engine: ScrollStitchEngine, area: CGRect, scale: CGFloat, colorSpace: CGColorSpace,
         clock: any ScrollClock = SystemScrollClock()) {
        self.source = source
        self.engine = engine
        self.area = area
        self.scale = scale
        self.colorSpace = colorSpace
        self.clock = clock
        let pixels = Geometry.pixelSize(points: area.size, scale: scale)
        widthPixels = pixels.width
        heightPixels = pixels.height
    }

    // MARK: Commands

    /// Starts the stream. The first frame is the page as the user arranged it.
    func start() async {
        guard phase == .ready else { return }
        phase = .capturing(.manual)
        status = .manualCapturing
        do {
            let events = try await source.start()
            // Cancelled while the stream was starting: stop it again.
            guard phase != .ended else {
                await source.stop()
                return
            }
            readTask = Task { await self.read(events) }
        } catch {
            guard phase != .ended else { return }
            end(.failed(error.localizedDescription, partial: nil))
        }
    }

    /// Stops the stream, stitches what is still buffered, and ends with the image. Ignored
    /// before the first frame and outside `.capturing`.
    func done() async {
        guard case .capturing = phase, hasFirstFrame else { return }
        phase = .finishing
        status = .finishing
        await source.stop()
        // `stop()` finishes the events after the frame still buffered; the read loop takes it.
        await readTask?.value
        guard phase != .ended else { return }
        let image = await engine.finish(scale: scale, colorSpace: colorSpace)
        end(image.map(ScrollCaptureOutcome.image) ?? .failed(CaptureError.noImage.localizedDescription, partial: nil))
    }

    /// Discards everything at once. Works in every phase but `.ended`.
    func cancel() async {
        guard phase != .ended else { return }
        end(.cancelled)
        readTask?.cancel()
        await source.stop()
    }

    /// The panel's default button and the Capture Scrolling shortcut: Start, then Done.
    func advance() async {
        switch phase {
        case .ready: await start()
        case .capturing: await done()
        case .finishing, .ended: break
        }
    }

    /// Shows an end line for `endLineDelay`, then finishes as Done does.
    func finish(showing line: ScrollCaptureStatus) async {
        guard case .capturing = phase else { return }
        status = line
        try? await clock.sleep(for: Self.endLineDelay)
        await done()
    }

    // MARK: Frames

    private func read(_ events: AsyncStream<FrameEvent>) async {
        for await event in events {
            guard phase != .ended else { return }
            switch event {
            case .frame(let frame):
                framesRead += 1
                await take(frame)
            case .idle:
                break
            case .stopped(let error):
                await streamStopped(error)
                return
            }
        }
    }

    private func take(_ frame: ScrollFrame) async {
        latestFrame = frame
        latestFrameAt = clock.now
        frameSerial += 1
        // The first frame begins the stitch and is the preview: its rows reach `previewDelta`
        // only once a move commits them.
        guard hasFirstFrame else {
            await engine.begin(first: frame)
            hasFirstFrame = true
            heightPixels = frame.height
            preview = Self.image(bgra: frame.bgra, width: frame.width, height: frame.height, colorSpace: colorSpace)
            return
        }
        apply(await engine.add(frame))
    }

    /// The readout, the preview, the manual status line and the cap, from one stitched frame.
    private func apply(_ progress: StitchProgress) {
        guard phase != .ended else { return }
        heightPixels = progress.heightPixels
        if !progress.previewDelta.isEmpty {
            previewRows.append(progress.previewDelta)
            showPreview()
        }
        guard phase == .capturing(.manual) else { return }
        switch progress.step.match {
        case .lost: status = .manualLost
        case .moved: status = .manualCapturing
        case .still: break
        }
        if progress.step.isFull, endTask == nil {
            endTask = Task { await self.finish(showing: .heightLimit) }
        }
    }

    /// The stream stopped by itself: keep what was stitched, if anything, and say why.
    private func streamStopped(_ error: (any Error)?) async {
        guard case .capturing = phase else { return }
        phase = .finishing
        status = .finishing
        await source.stop()
        let reason = error?.localizedDescription ?? Self.streamStoppedReason
        var partial: ScaledImage?
        if hasFirstFrame {
            partial = await engine.finish(scale: scale, colorSpace: colorSpace)
        }
        end(.failed(reason, partial: partial))
    }

    private func end(_ outcome: ScrollCaptureOutcome) {
        guard self.outcome == nil else { return }
        self.outcome = outcome
        phase = .ended
        endTask?.cancel()
        previewTask?.cancel()
        onEnd?(outcome)
    }

    // MARK: Preview

    /// Rebuilds the preview from the stitched rows, at most every `previewInterval`; rows that
    /// come sooner show when the interval has passed.
    private func showPreview() {
        guard !previewRows.isEmpty, phase != .ended else { return }
        let now = clock.now
        if let lastPreviewAt, now - lastPreviewAt < Self.previewInterval {
            guard previewTask == nil else { return }
            let wait = Self.previewInterval - (now - lastPreviewAt)
            previewTask = Task {
                try? await clock.sleep(for: wait)
                previewTask = nil
                showPreview()
            }
            return
        }
        preview = previewRows.image(colorSpace: colorSpace)
        lastPreviewAt = now
    }

    /// A CGImage over packed BGRA rows (`byteOrder32Little | noneSkipFirst`), as the engine
    /// builds the stitched image.
    nonisolated static func image(bgra: Data, width: Int, height: Int, colorSpace: CGColorSpace) -> CGImage? {
        guard width > 0, height > 0, bgra.count >= width * height * 4,
              let provider = CGDataProvider(data: bgra as CFData) else { return nil }
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipFirst.rawValue
                                      | CGBitmapInfo.byteOrder32Little.rawValue)
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                       space: colorSpace, bitmapInfo: bitmapInfo, provider: provider, decode: nil,
                       shouldInterpolate: true, intent: .defaultIntent)
    }
}

/// The preview's rows so far: each `PreviewStrip` appended below the last.
nonisolated private struct PreviewRows {
    private(set) var width = 0
    private(set) var height = 0
    private var bgra = Data()

    var isEmpty: Bool { height == 0 }

    mutating func append(_ strip: PreviewStrip) {
        guard !strip.isEmpty else { return }
        if width == 0 { width = strip.width }
        guard strip.width == width else { return }
        bgra.append(strip.bgra)
        height += strip.height
    }

    func image(colorSpace: CGColorSpace) -> CGImage? {
        ScrollCaptureSession.image(bgra: bgra, width: width, height: height, colorSpace: colorSpace)
    }
}
```
Notes for the implementer:
- `done()` never awaits a task it runs in: the cap's `finish(showing:)` runs in `endTask`, not in the read loop, and the read loop's own stop (`streamStopped`) does not await `readTask`. Keep it that way, or Done deadlocks.
- A frame read while `.finishing` (the one `stop()` lets through) is still stitched; `apply` changes no status line then.
- The `Task { }` closures inherit the main actor; nothing here leaves it except the `await engine...` calls, which hop to the engine actor.

- [ ] **Step 5: The area frame**

`TidyShot/Scrolling/ScrollAreaFrameWindow.swift`. Structure and behaviour (the implementer writes the AppKit code):
- `final class ScrollAreaFrameWindow: NSWindow`, `init(area: CGRect)` with `area` in AppKit global points. Content rect `area.insetBy(dx: -outset, dy: -outset)` with `outset = lineWidth + 2`; `styleMask: .borderless`, `backing: .buffered`, `defer: false`; `isOpaque = false`, `backgroundColor = .clear`, `hasShadow = false`, `level = .floating`, `ignoresMouseEvents = true`, `collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]`, `isReleasedWhenClosed = false`; `canBecomeKey` and `canBecomeMain` false. `static let lineWidth: CGFloat = 2`, `static let dash: [CGFloat] = [6, 4]`.
- `final class ScrollAreaFrameView: NSView`, the content view, draws the adaptive two-tone stroke of spec 2.6 in its white-over-black colours, entirely outside the area:
  ```swift
  override func draw(_ dirtyRect: NSRect) {
      let halo = ScrollAreaFrameWindow.lineWidth + 2 / (window?.backingScaleFactor ?? 2)
      let area = bounds.insetBy(dx: inset, dy: inset)
      // Centred half the halo outside the area, so neither stroke covers an area pixel.
      let path = NSBezierPath(rect: area.insetBy(dx: -halo / 2, dy: -halo / 2))
      path.setLineDash(ScrollAreaFrameWindow.dash, count: ScrollAreaFrameWindow.dash.count, phase: 0)
      NSColor(white: 0, alpha: CrosshairStyle.haloAlpha).setStroke()
      path.lineWidth = halo
      path.stroke()
      NSColor.white.setStroke()
      path.lineWidth = ScrollAreaFrameWindow.lineWidth
      path.stroke()
  }
  ```
  `inset` is the window's `outset`, passed to the view's initialiser.
- It never takes a click or a scroll, so wheel events go to the app beneath. The stream excludes it with the rest of TidyShot.

- [ ] **Step 6: The panel and its view**

`TidyShot/Scrolling/ScrollCapturePanel.swift`:
- `final class ScrollCapturePanel: NSPanel`, `init(session: ScrollCaptureSession)`: content rect `ScrollPanelGeometry.panelWidth` by `ScrollPanelGeometry.minimumHeight`, `styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView]`, `level = .floating`, `isFloatingPanel = true`, `hidesOnDeactivate = false` (the user clicks their own app to scroll), `collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]`, `isOpaque = false`, `backgroundColor = .clear`, `hasShadow = true`, `isMovableByWindowBackground = false` (the controller places it), `animationBehavior = .utilityWindow`. Content: `NSHostingView(rootView: ScrollCaptureView(session: session))` with `sizingOptions = []`, so the panel's frame decides the view's size and not the reverse.
- `override var canBecomeKey: Bool { true }` (Return and Escape reach the buttons while TidyShot is active), `override var canBecomeMain: Bool { false }`. Compare `QuickAccessPanel` (`QuickAccessPanel.swift:6-25`), which refuses key.

`TidyShot/Scrolling/ScrollCaptureView.swift` (SwiftUI, `struct ScrollCaptureView: View`, `let session: ScrollCaptureSession`):
```swift
    static let padding: CGFloat = 12
    /// The panel's height without the preview, in points: the readout, the status line at two
    /// lines, the buttons, the spacing and the padding. Measured in Step 9 and fixed here.
    static let chromeHeight: CGFloat = 120
    static var previewWidth: CGFloat { ScrollPanelGeometry.panelWidth - 2 * padding }

    /// The preview's height when drawn `previewWidth` wide; 0 without one.
    static func previewHeight(for image: CGImage?) -> CGFloat {
        guard let image, image.width > 0 else { return 0 }
        return CGFloat(image.height) * previewWidth / CGFloat(image.width)
    }
```
Layout, top to bottom, in a `VStack(alignment: .leading, spacing: 8)` with `.padding(Self.padding)`, `.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)` and `.background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))`:
1. The preview in a `GeometryReader` that takes the remaining height: `Image(decorative: preview, scale: 1).resizable().interpolation(.medium)` at the reader's width and `Self.previewHeight`-style height for that width, inside `.frame(width: geometry.size.width, height: geometry.size.height, alignment: .bottom).clipped()`, so the newest rows show at the bottom. Without a preview, a `RoundedRectangle(cornerRadius: 6).fill(.quaternary)`. `.accessibilityLabel("Preview")`.
2. `Text(ScrollCaptureStatus.sizeText(width: session.widthPixels, height: session.heightPixels))` in `.font(.callout.monospacedDigit())`.
3. `Text(session.status.text)`, `.font(.callout)`, `.foregroundStyle(.secondary)`, `.fixedSize(horizontal: false, vertical: true)`, `.accessibilityAddTraits(.updatesFrequently)`.
4. `HStack { Spacer(); … }` with `Button("Cancel") { Task { await session.cancel() } }.keyboardShortcut(.cancelAction)`, then, when `session.phase == .ready`, `Button("Start") { Task { await session.start() } }.keyboardShortcut(.defaultAction)`, otherwise `Button("Done") { Task { await session.done() } }.keyboardShortcut(.defaultAction)` disabled unless the phase is `.capturing` and `session.hasFirstFrame` (so also while `.finishing`). Cancel stays enabled until the session ends.

- [ ] **Step 7: The controller**

`TidyShot/Scrolling/ScrollCaptureController.swift`: `final class ScrollCaptureController` (main actor by default), shaped like `SelectionController`: one run at a time, resolved through a continuation.
```swift
    private let engine: CaptureEngine
    private var session: ScrollCaptureSession?
    private var panel: ScrollCapturePanel?
    private var frameWindow: ScrollAreaFrameWindow?
    private var continuation: CheckedContinuation<ScrollCaptureOutcome, Never>?
    /// The area in AppKit global points and its screen's visible frame, for placing the panel.
    private var appKitArea: CGRect = .zero
    private var visibleFrame: CGRect = .zero

    init(engine: CaptureEngine) {
        self.engine = engine
    }

    /// A session is on screen. The Capture Scrolling shortcut then means Start or Done.
    var isRunning: Bool { session != nil }
```
`func run(rect: CGRect, display: SCDisplay) async -> ScrollCaptureOutcome` (`rect` in CG global points, on `display`, as `SelectionController` returns it):
1. `guard session == nil else { return .cancelled }`.
2. `appKitArea = Geometry.appKitRect(fromCG: rect, primaryHeight: NSScreen.screens.first?.frame.height ?? 0)`; `visibleFrame = (CaptureEngine.screen(forDisplayID: display.displayID) ?? NSScreen.main ?? NSScreen.screens[0]).visibleFrame`.
3. Show `ScrollAreaFrameWindow(area: appKitArea)` with `orderFrontRegardless()`.
4. Build `let source = ScrollFrameSource(rect: rect, display: display, engine: engine)` and
   ```swift
   let session = ScrollCaptureSession(source: source, engine: ScrollStitchEngine(finder: OverlapFinder(scale: source.scale)),
                                      area: rect, scale: source.scale, colorSpace: source.colorSpace)
   session.onEnd = { [weak self] outcome in self?.close(with: outcome) }
   ```
   The source makes its filter at Start, when the panel and the frame are already on screen, so the application exclusion covers both.
5. Build `ScrollCapturePanel(session:)`, store all three, call `layoutPanel()` and `observePreview()`, then `panel.makeKeyAndOrderFront(nil)`. TidyShot is already active after the selection overlay; do not activate again.
6. `KeyboardShortcuts.enable(.cancelScrollingCapture)`.
7. `return await withCheckedContinuation { continuation = $0 }`.

The rest:
```swift
    /// The Capture Scrolling shortcut during a session: Start, then Done.
    func advance() {
        guard let session else { return }
        Task { await session.advance() }
    }

    /// Escape, from any app, while a session runs.
    func cancel() {
        guard let session else { return }
        Task { await session.cancel() }
    }

    private func close(with outcome: ScrollCaptureOutcome) {
        KeyboardShortcuts.disable(.cancelScrollingCapture)
        panel?.orderOut(nil)
        frameWindow?.orderOut(nil)
        panel = nil
        frameWindow = nil
        session = nil
        continuation?.resume(returning: outcome)
        continuation = nil
    }

    /// Sizes the panel to the preview (220 to min(560, area height) points) and places it.
    private func layoutPanel() {
        guard let session, let panel else { return }
        let wanted = ScrollCaptureView.chromeHeight + ScrollCaptureView.previewHeight(for: session.preview)
        let size = CGSize(width: ScrollPanelGeometry.panelWidth,
                          height: ScrollPanelGeometry.height(wanted: wanted, areaHeight: appKitArea.height))
        let frame = ScrollPanelGeometry.frame(panelSize: size, area: appKitArea, visibleFrame: visibleFrame)
        if panel.frame != frame { panel.setFrame(frame, display: true) }
    }

    /// Lays the panel out again whenever the preview changes. Observation calls `onChange` once
    /// per registration, so it registers again, as `StatusMenuController.updateIcon` does.
    private func observePreview() {
        guard let session else { return }
        withObservationTracking {
            _ = session.preview
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.layoutPanel()
                self?.observePreview()
            }
        }
    }
```
`close(with:)` runs inside the session's `end`, so the panel is ordered out the moment Cancel, Escape or Done's stitch finishes; the stream may still be stopping, and the screen-recording indicator goes away when it has.

- [ ] **Step 8: Wire the coordinator**

`TidyShot/App/AppCoordinator.swift`:
- After `selector` (line 30):
  ```swift
      @ObservationIgnored private lazy var scrollCapture = ScrollCaptureController(engine: engine)
  ```
- In `registerShortcuts()`, after Task 4's `KeyboardShortcuts.disable(.cancelScrollingCapture)`:
  ```swift
          // Live only while a scrolling session runs: the controller enables and disables it.
          KeyboardShortcuts.onKeyUp(for: .cancelScrollingCapture) { [weak self] in
              self?.scrollCapture.cancel()
          }
  ```
- In Task 4's `captureScrolling()`: make the first statement, before `withCaptureLock`,
  ```swift
          // During a session the shortcut is Start, then Done (the lock is held meanwhile).
          if scrollCapture.isRunning {
              scrollCapture.advance()
              return
          }
  ```
  and replace the stub's capture (from `let overlays = await selector.overlayWindows()` to the closing brace of `if let result { await save(result) }`) with:
  ```swift
              selector.dismiss()
              let outcome = await scrollCapture.run(rect: rect, display: display)
              if let notice = outcome.failureNotice {
                  notifier.notifyError(notice.body, title: notice.title)
              }
              if let image = outcome.imageToSave {
                  await save(CaptureResult(image: image.image, scale: image.scale,
                                           target: .area(rect: rect, display: display)))
              }
  ```
  Update the doc comment to: `Capture Scrolling: select an area or a window's frame, run the scrolling session, and save the stitched image like any capture. During a session the shortcut is Start, then Done.`

`isCapturing` stays true for the whole session (it runs inside `withCaptureLock`), so the four capture items and the other three shortcuts do nothing meanwhile. The stitched image reaches records, the overlay, uploads and Annotate only through `save(_:)`, and nothing is written before Done.

- [ ] **Step 9: Run the suite**

Run:
```bash
xcodegen generate && xcodebuild test -project TidyShot.xcodeproj -scheme TidyShot -destination 'platform=macOS' -derivedDataPath .build 2>&1 | grep -E "Test run with|error:|TEST"
```
Expected: no `error:` lines, `Test run with 554 tests in 71 suites passed`, then `** TEST SUCCEEDED **`. This task adds 7 tests in 1 new suite: `ScrollCaptureSessionTests` (`startFramesAndDoneGiveTheStitchedPage`, `cancelGivesNothingAndStopsTheStream`, `doneWithoutMovementGivesTheFirstFrame`, `theCapFinishesByItselfAfterTheLimitLine`, `tooFastShowsTheLineUntilTheNextMovement`, `aStreamErrorKeepsWhatWasStitched`, `previewFollowsTheStitchAtMostFourTimesASecond`). `ScrollSessionFakes.swift` has no tests.

- [ ] **Step 10: Check by hand**

Build and run (re-grant Screen Recording after an ad-hoc rebuild):
```bash
xcodebuild -project TidyShot.xcodeproj -scheme TidyShot -configuration Debug -derivedDataPath .build build -quiet && open .build/Build/Products/Debug/TidyShot.app
```
Open a long article in Safari, scrolled to its top.

Expected:
- **Panel and frame.** ⌃⇧5, drag an area over the article: the overlay closes, a white dashed outline with a dark halo sits just outside the area, and the panel appears 12 pt to its right, top aligned (12 pt left when there is no room on the right; inside the bottom-right corner when neither side fits, as with a full-width area). It reads `Click Start, then scroll down slowly.`, the readout is the area's pixel size (for example `1,600 × 1,200 px` for 800 x 600 pt on Retina) and the buttons are Cancel and Start. The outline takes no clicks: scrolling over the area scrolls Safari. Safari's window looks inactive while the panel is key (TidyShot stays the active app), which is expected; it still scrolls under the pointer without a click.
- **Chrome height.** With the status line at two lines, nothing in the panel is clipped and the preview fills the space above the readout. Adjust `ScrollCaptureView.chromeHeight` until that holds, and note the value.
- **Start.** Press Return: the screen-recording indicator appears, the preview shows the area, the status reads `Scroll down slowly. Click Done at the end.`, the default button is Done. Scroll down gently with the trackpad: the readout's height grows with monospaced digits, the preview grows and shows the newest rows at its bottom, and the panel grows up to `min(560, area height)` points.
- **Too fast.** Flick hard: `Too fast. Scroll back up a little.` appears; scroll back up a little until it returns to `Scroll down slowly. Click Done at the end.`, and keep going.
- **Done.** Click Done: `Stitching…` shows briefly, the panel, the frame and the indicator go, and the normal Quick Access overlay shows the capture with Annotate. The saved PNG is the article from the top to where scrolling stopped, Safari's toolbar is not in it, no row is doubled or missing at the joins, TidyShot's panel and outline appear nowhere, and its pixel width is the area's. With the after-capture action set to upload (and then to Upload only), it uploads and the link lands on the clipboard. Annotate opens it in the editor.
- **No movement.** ⌃⇧5, select, Start, Done without scrolling: one image the size of the area, as an area capture would give.
- **Shortcut.** ⌃⇧5, select, then ⌃⇧5 again: it starts; scroll, ⌃⇧5 once more: it finishes as Done. Capture Area, Window and Fullscreen and their shortcuts do nothing while the panel shows.
- **Escape.** Start a session, click into Safari so Safari is frontmost, scroll, press Escape: the session ends at once, nothing is saved or uploaded, no overlay appears, and Recent Captures has no new row. After that, Escape in Safari's address bar reverts the address again, as it does without TidyShot running.
- **Cancel.** Cancel before Start and after Start both close everything and save nothing.
- **Cap.** In a very long page (a long GitHub file view), scroll until the line `Reached the 16,384 pixel limit.` shows; about half a second later the session finishes by itself and the saved PNG is exactly 16,384 px tall.
- **Stream failure.** Start a session, scroll a little, then lock the screen (⌃⌘Q) and unlock: if ScreenCaptureKit stops the stream, the notification `Scrolling capture stopped` says `The capture stopped early: <reason> TidyShot saved what it had.` (the reason is `The screen recording stream stopped.` when ScreenCaptureKit gives none) and the rows stitched so far are saved. If the stream survives the lock, note that and move on.

- [ ] **Step 11: Commit**

```bash
git add TidyShot/Scrolling/ScrollClock.swift TidyShot/Scrolling/ScrollCaptureSession.swift TidyShot/Scrolling/ScrollCaptureController.swift TidyShot/Scrolling/ScrollCapturePanel.swift TidyShot/Scrolling/ScrollCaptureView.swift TidyShot/Scrolling/ScrollAreaFrameWindow.swift TidyShot/App/AppCoordinator.swift TidyShotTests/Support/ScrollSessionFakes.swift TidyShotTests/ScrollCaptureSessionTests.swift
git commit -m "feat: manual scrolling capture session, panel and area frame"
```

### Task 6: Auto-scroll

**Files:**
- Create: `TidyShot/Capture/PostEventPermission.swift`
- Create: `TidyShot/Capture/AutoScrollPermissionWindowController.swift` (`AutoScrollPermissionView`, `AutoScrollPermissionWindowController`)
- Create: `TidyShot/Scrolling/ScrollEventPoster.swift` (`ScrollEventPoster`, `HIDScrollEventPoster`)
- Create: `TidyShot/Scrolling/AutoScrollDriver.swift` (`AutoScrollEnvironment`, `AutoScrollDriver`)
- Modify: `TidyShot/Scrolling/ScrollCaptureSession.swift` (Task 5: properties, `init`, `start()`, `done()`, `take(_:)`, `apply(_:)`, `end(_:)`, and a new `// MARK: Auto-scroll` section)
- Modify: `TidyShot/Scrolling/ScrollCaptureView.swift` and `TidyShot/Scrolling/ScrollCapturePanel.swift` (Task 5: the checkbox, the link, the permission poll)
- Modify: `TidyShot/Scrolling/ScrollCaptureController.swift` (Task 5: `init`, the session and panel in `run`)
- Modify: `TidyShot/Settings/AppSettings.swift` (`Keys`, line 49; properties, line 75; `register`, line 110; `init`, line 132)
- Modify: `TidyShot/App/AppCoordinator.swift` (Task 5's `scrollCapture` property after line 30)
- Create: `TidyShotTests/Support/FakeScrollWorld.swift` (no tests of its own)
- Test: `TidyShotTests/AutoScrollDriverTests.swift` (create, struct `AutoScrollDriverTests`)
- Test: `TidyShotTests/ScrollCaptureSessionTests.swift` (Task 5, modify), `TidyShotTests/AppSettingsTests.swift` (modify, before the closing brace at line 103)

**Interfaces:**
- Consumes:
  - `main`: `ScreenCapturePermission` (`ScreenCapturePermission.swift:6-23`) and `PermissionView` / `PermissionWindowController` (`PermissionWindowController.swift:4-60`) as the pattern; `Geometry.cgPoint(fromAppKit:primaryHeight:)` (`Geometry.swift:15`); `AppSettings(defaults:)` and its `Keys` / `register` / `init` pattern (`AppSettings.swift:31-133`).
  - Task 1: `ScrollFrame`, `OverlapMatch`, `StitchStep` (`match`, `isFull`), `ScrollCaptureLimits.scrollbarStripPoints`; test side `SyntheticPage`.
  - Task 2: `FrameSettler(stepStart:baselineHash:)`, `observe(_:)` with `.frame(hash:at:)` and `.idle(at:)`, `FrameSettler.contentHash(of:ignoringRightColumns:)`; `ScrollEndDetector()`, `decide(after:isFull:) -> EndDecision` (`.continue`, `.retryAfter(Duration)`, `.reverseDirection`, `.shrinkStep`, `.handOver`, `.end(.reachedEnd | .heightLimit)`); `AutoScrollPlan.events(forPoints:)`, `firstStep(areaHeightPoints:)`, `nextStep(bandHeightPixels:scale:)`, `shrunk(_:)`, `eventSpacing`; `ScrollCaptureStatus` (`readyAuto`, `autoScrolling`, `autoPaused`, `autoHandedOver`, `autoReachedEnd`, `heightLimit`, `ready(autoScroll:)`).
  - Task 3: `ScrollStitchEngine.add(_:predicted:) -> StitchProgress`.
  - Task 5: `ScrollClock`, `ScrollCaptureSession` (`area`, `scale`, `clock`, `phase`, `status`, `hasFirstFrame`, `latestFrame`, `latestFrameAt` (the session's clock time of reading, since frames carry none), `frameSerial`, `start()`, `done()`, `cancel()`, `finish(showing:)`, `endLineDelay`), `ScrollCaptureController`, `ScrollCaptureView`, `ScrollCapturePanel`; test side `FakeFrameSource`, `FakeScrollClock` (`run(until:)`, `run(for:)`), `stitchedPixels(of:)`, `eventually(_:)`.
- Produces:
  - `enum PostEventPermission { static var isGranted: Bool; static func request() -> Bool; static func openSystemSettings() }`.
  - `final class AutoScrollPermissionWindowController { func show() }` and `struct AutoScrollPermissionView: View`.
  - `protocol ScrollEventPoster { func post(points: CGFloat) }` (main actor by the module default) and `nonisolated struct HIDScrollEventPoster: ScrollEventPoster`.
  - `struct AutoScrollEnvironment { var poster: any ScrollEventPoster; var pointerLocation: () -> CGPoint; var isPermitted: () -> Bool; static func live() -> AutoScrollEnvironment }`.
  - `final class AutoScrollDriver`: `init(environment: AutoScrollEnvironment, clock: any ScrollClock)`, `func run(session: ScrollCaptureSession) async`, `static let pollInterval: Duration` (50 ms).
  - On `ScrollCaptureSession`: `init(source:engine:area:scale:colorSpace:clock:autoScrollEnvironment:prefersAutoScroll:)` (the two new parameters default to `nil` and `false`); `var autoScroll: Bool`; `private(set) var isAutoScrollPermitted: Bool`; `var usesAutoScroll: Bool`; `var onAutoScrollChanged: ((Bool) -> Void)?`; `func refreshAutoScrollPermission()`, `func integrate(_ frame: ScrollFrame, predicted: Int) async -> StitchProgress?`, `func handOver()`, `func showAutoStatus(_ line: ScrollCaptureStatus)`.
  - `AppSettings.scrollingAutoScroll: Bool` (key `scrollingAutoScroll`, default true); `ScrollCaptureController.init(engine:settings:)`; `ScrollCaptureView(session:onAllowAutoScroll:)` and `ScrollCapturePanel(session:onAllowAutoScroll:)`.
  - For Task 7: the result of Tim's hand checks in Steps 9 and 11 (the date, the probe's lines `sandboxed=… postEvent=…` and `received=…`, and whether TidyShot's own events moved the page), which settles the spec's "Auto-scroll delivery is unverified" risk either way.

Behaviour (spec 2.8, Auto-scroll permission, Settling and the end, Auto-scroll driver):
- Before Start the panel shows **Scroll automatically** (`AppSettings.scrollingAutoScroll`, default on). Without the PostEvent grant it shows off and disabled, with the **Allow Auto-Scroll…** link under it, which opens the permission window; the panel checks the grant once a second, so allowing it while the panel shows enables the checkbox. The ready line follows: `Click Start, then hold the pointer over the area.` when auto-scroll will run, `Click Start, then scroll down slowly.` otherwise. The menu has no item for this permission.
- At Start with auto-scroll on, the session is `.capturing(.auto)` and shows `Paused. Move the pointer over the area to continue.` until the pointer is over the area. The driver polls the pointer 20 times a second, posts only while it is over the area, and shows `Scrolling… Move the pointer away to pause.` while it scrolls. TidyShot never moves the pointer: moving it out pauses after the step in progress, moving it back resumes.
- One step: the first is half the area's height, later ones 0.6 of the last band (`AutoScrollPlan`), posted as wheel events of at most 50 pt, 10 ms apart. Then the driver waits for `FrameSettler` (no new content for 150 ms, or 1.5 s), hands the settled frame to the engine with the step in pixels as `predicted`, and applies `ScrollEndDetector`'s decision:
  - Before the detector: a `.still` on the very first step of the session flips the direction once and posts again, as a fresh first step the detector has not seen. At the top of a page in an app that inverts synthetic deltas, the first step pushes against the top and nothing moves; without this, the retry below would end the session on the first frame. A page that moves neither way still ends, after the other direction's retry. Spec 2.8 does not have this; Task 7 adds it.
  - `.continue`: the next step from the band just measured.
  - `.retryAfter(700 ms)`: the first still after a step waits, then posts the same step again (lazy loading). A second still ends: `Reached the end.` for 0.4 s, then the session finishes as Done does.
  - `.reverseDirection`: the first step moved the page backwards (natural scrolling applied to synthetic deltas); later steps go the other way.
  - `.shrinkStep`: the step lost the place. The driver scrolls back by that step, so the page returns to overlap with the last accepted frame, and halves the next step down to 40 pt. This scroll-back is this plan's reading of "a `.lost` halves the next step": without it, every later step starts from beyond the overlap and loses too. Spec 2.8 does not say it; Task 7 adds it.
  - `.handOver` (three losses in a row): manual mode from here, with `Auto-scroll lost its place. Scroll back up a little, or click Done.` until the next movement; frames go to the engine as in manual mode.
  - `.end(.heightLimit)`: `Reached the 16,384 pixel limit.` for 0.4 s, then finish.
- The grant is checked before every step; if it is gone, the driver hands over to manual. Done, Cancel and Escape stop the driver at once.
- Events: `CGEvent(scrollWheelEvent2Source: CGEventSource(stateID: .hidSystemState), units: .pixel, wheelCount: 1, wheel1: -points, wheel2: 0, wheel3: 0)` with `scrollWheelEventIsContinuous` 1, posted at `.cghidEventTap`, so they go to the window under the pointer. No entitlement is added; `project.yml` keeps its four.

Delivery of posted events after a real grant is not verified yet (spec 2.8, Risks), and only Tim can grant a TCC permission. So the code is written and tested with fakes either way, and delivery is a hand check for Tim (Step 9 with the probe, Step 11 with TidyShot itself). An implementing agent never toggles System Settings.

- [ ] **Step 1: Write the failing tests**

`TidyShotTests/Support/FakeScrollWorld.swift` (new):
```swift
import CoreGraphics
import Foundation
@testable import TidyShot

/// A synthetic page behind a fake stream and a fake scroll wheel, for the auto-scroll tests.
/// Each posted event scrolls the page and the source sends the frame at the new offset, as an
/// app that redraws at once would.
final class FakeScrollWorld: ScrollEventPoster {
    var page: SyntheticPage
    let source = FakeFrameSource()
    let clock: FakeScrollClock
    /// Pixels per point of the fake display.
    let scale: CGFloat
    /// Page rows one posted pixel moves; 5 makes every step jump past the band.
    var gain: CGFloat = 1
    /// The app inverts synthetic deltas, as natural scrolling might.
    var inverted = false
    /// Lazy loading: the page cannot scroll past this offset until a post finds it held there
    /// for `loadDelay`.
    var loadedLimit: Int?
    var loadDelay: Duration = .milliseconds(300)
    /// The pointer in CoreGraphics global points.
    var pointer: CGPoint
    var permitted = true
    private(set) var offset: Int
    private(set) var posted: [CGFloat] = []
    /// Posts that found the page held at `loadedLimit`.
    private(set) var blockedPosts = 0
    private var blockedSince: ContinuousClock.Instant?

    init(page: SyntheticPage, clock: FakeScrollClock, scale: CGFloat = 2, offset: Int = 0, pointer: CGPoint) {
        self.page = page
        self.clock = clock
        self.scale = scale
        self.offset = offset
        self.pointer = pointer
    }

    var environment: AutoScrollEnvironment {
        AutoScrollEnvironment(poster: self,
                              pointerLocation: { [unowned self] in self.pointer },
                              isPermitted: { [unowned self] in self.permitted })
    }

    func post(points: CGFloat) {
        posted.append(points)
        if let loadedLimit, offset >= loadedLimit {
            blockedPosts += 1
            if let blockedSince {
                if clock.now - blockedSince >= loadDelay { self.loadedLimit = nil }
            } else {
                blockedSince = clock.now
            }
        }
        let rows = Int((points * scale * gain).rounded()) * (inverted ? -1 : 1)
        let limit = min(page.maxOffset, loadedLimit ?? page.maxOffset)
        offset = max(0, min(limit, offset + rows))
        showFrame()
    }

    /// Sends the frame at the current offset.
    func showFrame() {
        source.send(.frame(page.frame(at: offset, animated: false)))
    }

    /// The user scrolls to `newOffset` (manual mode after a hand-over).
    func scroll(to newOffset: Int) {
        offset = newOffset
        showFrame()
    }
}
```

`TidyShotTests/AutoScrollDriverTests.swift` (new):
```swift
import CoreGraphics
import Foundation
import Testing
@testable import TidyShot

/// Auto-scroll on a fake world (spec 2.8, Auto-scroll driver): the real session, engine, end
/// detector, settler and step plan; a fake wheel, pointer, grant and clock. The area is 80 x 200
/// points at scale 2, so frames are 160 x 400 pixels: a 40 row header, a 330 row band and a
/// 30 row footer over a 2,000 row page (largest offset 1,670).
struct AutoScrollDriverTests {
    let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!
    static let area = CGRect(x: 100, y: 100, width: 80, height: 200)
    static let inside = CGPoint(x: 140, y: 200)
    static let outside = CGPoint(x: 20, y: 20)

    func makeWorld(clock: FakeScrollClock, offset: Int = 0, pointer: CGPoint = inside) -> FakeScrollWorld {
        FakeScrollWorld(page: SyntheticPage(width: 160, height: 400, header: 40, footer: 30, pageHeight: 2000),
                        clock: clock, offset: offset, pointer: pointer)
    }

    func makeSession(_ world: FakeScrollWorld, maxPixelHeight: Int = ScrollCaptureLimits.maxPixelHeight) -> ScrollCaptureSession {
        ScrollCaptureSession(source: world.source,
                             engine: ScrollStitchEngine(finder: world.page.finder, maxPixelHeight: maxPixelHeight),
                             area: Self.area, scale: 2, colorSpace: sRGB, clock: world.clock,
                             autoScrollEnvironment: world.environment, prefersAutoScroll: true)
    }

    /// Start, then the first frame: the page as the user arranged it.
    func start(_ session: ScrollCaptureSession, _ world: FakeScrollWorld) async throws {
        await session.start()
        world.showFrame()
        try await eventually { session.hasFirstFrame }
    }

    func image(of session: ScrollCaptureSession) throws -> StitchedImage {
        guard case .image(let image)? = session.outcome else {
            Issue.record("no image")
            throw FakeClockTimedOut()
        }
        return try stitchedPixels(of: image)
    }

    /// Steps of half the area, then 0.6 of the band, down to the end; one still retries, the
    /// second shows the end line and finishes. The image is the whole page.
    @Test func scrollsToTheEndAndFinishesOnTheSecondStill() async throws {
        let clock = FakeScrollClock()
        let world = makeWorld(clock: clock)
        let session = makeSession(world)
        #expect(session.usesAutoScroll)
        #expect(session.status == .readyAuto)
        try await start(session, world)
        #expect(session.phase == .capturing(.auto))

        try await clock.run(until: { session.status == .autoReachedEnd })
        #expect(session.phase == .capturing(.auto))
        #expect(world.offset == world.page.maxOffset)
        // Whole-point events of at most 50, all downwards; the first step is 100 pt.
        #expect(world.posted.allSatisfy { $0 > 0 && $0 <= 50 })
        #expect(Array(world.posted.prefix(2)) == [50, 50])
        // Later steps are at most 0.6 of the 330 row band at scale 2, 99 pt (a blank stretch under
        // the header can measure the band shorter), and together they cover the page.
        #expect(world.posted.reduce(0, +) * 2 >= CGFloat(world.page.maxOffset))

        try await clock.run(until: { session.phase == .ended })
        let comparison = world.page.compare(try image(of: session), reached: world.page.maxOffset)
        #expect(comparison.actualHeight == comparison.expectedHeight)
        #expect(comparison.mismatched == 0)
    }

    /// A page that loads more when the user reaches its bottom: the first still waits 700 ms and
    /// tries again, finds new content, and goes on to the real end.
    @Test func waitsForLazyLoadingBeforeEnding() async throws {
        let clock = FakeScrollClock()
        let world = makeWorld(clock: clock)
        world.loadedLimit = 600
        let session = makeSession(world)
        try await start(session, world)
        try await clock.run(until: { session.phase == .ended })
        #expect(world.blockedPosts > 0)
        #expect(world.loadedLimit == nil)
        let comparison = world.page.compare(try image(of: session), reached: world.page.maxOffset)
        #expect(comparison.actualHeight == comparison.expectedHeight)
        #expect(comparison.mismatched == 0)
    }

    /// Nothing is posted while the pointer is outside the area; moving it in starts, moving it
    /// out pauses after the step in progress.
    @Test func postsOnlyWhileThePointerIsOverTheArea() async throws {
        let clock = FakeScrollClock()
        let world = makeWorld(clock: clock, pointer: Self.outside)
        let session = makeSession(world)
        try await start(session, world)
        try await clock.run(for: .seconds(1))
        #expect(world.posted.isEmpty)
        #expect(session.status == .autoPaused)
        #expect(session.status.text == "Paused. Move the pointer over the area to continue.")

        world.pointer = Self.inside
        try await clock.run(until: { world.posted.count >= 2 })
        #expect(session.status == .autoScrolling)

        world.pointer = Self.outside
        try await clock.run(for: .seconds(2))
        let count = world.posted.count
        try await clock.run(for: .seconds(2))
        #expect(world.posted.count == count)
        #expect(session.status == .autoPaused)
        #expect(session.phase == .capturing(.auto))
        await session.cancel()
        guard case .cancelled? = session.outcome else {
            Issue.record("not cancelled")
            return
        }
    }

    /// The app inverts synthetic deltas: the first step moves the page up, so the driver flips
    /// the direction once and stitches from where the user started down to the end.
    @Test func reversesOnceWhenTheFirstStepGoesBackwards() async throws {
        let clock = FakeScrollClock()
        let world = makeWorld(clock: clock, offset: 600)
        world.inverted = true
        let session = makeSession(world)
        try await start(session, world)
        try await clock.run(until: { session.phase == .ended })
        #expect(Array(world.posted.prefix(2)) == [50, 50])
        #expect(world.posted.dropFirst(2).allSatisfy { $0 < 0 })
        #expect(world.offset == world.page.maxOffset)
        // Header, page rows 600 to the end, footer.
        #expect(try image(of: session).height == 40 + (world.page.maxOffset - 600) + 330 + 30)
    }

    /// At the top of a page in an app that inverts synthetic deltas, the first step pushes
    /// against the top and nothing moves. The driver tries the other direction once, as a fresh
    /// first step, and stitches the whole page.
    @Test func triesTheOtherDirectionWhenTheFirstStepIsStill() async throws {
        let clock = FakeScrollClock()
        let world = makeWorld(clock: clock)
        world.inverted = true
        let session = makeSession(world)
        try await start(session, world)
        try await clock.run(until: { session.phase == .ended })
        #expect(Array(world.posted.prefix(2)) == [50, 50])
        #expect(world.posted.dropFirst(2).allSatisfy { $0 < 0 })
        #expect(world.offset == world.page.maxOffset)
        let comparison = world.page.compare(try image(of: session), reached: world.page.maxOffset)
        #expect(comparison.actualHeight == comparison.expectedHeight)
        #expect(comparison.mismatched == 0)
    }

    /// A pane that does not scroll either way: the first step, the other direction, its 700 ms
    /// retry, then `Reached the end.` and the first frame alone.
    @Test func aPageThatNeverMovesEndsAfterTryingBothDirections() async throws {
        let clock = FakeScrollClock()
        let world = makeWorld(clock: clock)
        world.gain = 0
        let session = makeSession(world)
        try await start(session, world)
        try await clock.run(until: { session.status == .autoReachedEnd })
        #expect(world.posted == [50, 50, -50, -50, -50, -50])
        try await clock.run(until: { session.phase == .ended })
        #expect(try image(of: session).height == world.page.height)
    }

    /// Every step jumps past the band: each loss scrolls back and halves the step (100, 50,
    /// then the 40 pt floor), and the third hands over. Then the user scrolls and Done saves.
    @Test func shrinksThenHandsOverAfterThreeLosses() async throws {
        let clock = FakeScrollClock()
        let world = makeWorld(clock: clock)
        world.gain = 5
        let session = makeSession(world)
        try await start(session, world)
        try await clock.run(until: { session.phase == .capturing(.manual) })
        #expect(session.status == .autoHandedOver)
        #expect(session.status.text == "Auto-scroll lost its place. Scroll back up a little, or click Done.")
        #expect(world.posted == [50, 50, -50, -50, 50, -50, 40])

        // Manual from here: the user scrolls back into overlap with the first frame.
        world.scroll(to: 200)
        try await eventually { session.status == .manualCapturing }
        try await clock.run(for: .seconds(1))
        #expect(world.posted.count == 7)
        await session.done()
        let comparison = world.page.compare(try image(of: session), reached: 200)
        #expect(comparison.actualHeight == comparison.expectedHeight)
        #expect(comparison.mismatched == 0)
    }

    /// The grant is checked before every step: once it is gone, the driver hands over and posts
    /// nothing more.
    @Test func handsOverWhenTheGrantGoes() async throws {
        let clock = FakeScrollClock()
        let world = makeWorld(clock: clock)
        let session = makeSession(world)
        try await start(session, world)
        try await clock.run(until: { world.posted.count >= 2 })
        world.permitted = false
        try await clock.run(until: { session.phase == .capturing(.manual) })
        #expect(session.status == .autoHandedOver)
        let count = world.posted.count
        try await clock.run(for: .seconds(2))
        #expect(world.posted.count == count)
        await session.cancel()
    }

    /// At the cap the limit line shows for 0.4 s and the session finishes with exactly the
    /// limit's rows, posting nothing more.
    @Test func theCapEndsAutoScroll() async throws {
        let clock = FakeScrollClock()
        let world = makeWorld(clock: clock)
        let session = makeSession(world, maxPixelHeight: 700)
        try await start(session, world)
        try await clock.run(until: { session.status == .heightLimit })
        #expect(session.phase == .capturing(.auto))
        let count = world.posted.count
        try await clock.run(until: { session.phase == .ended })
        #expect(world.posted.count == count)
        let stitched = try image(of: session)
        #expect(stitched.height == 700)
        #expect(world.page.compare(stitched, reached: world.offset).mismatched == 0)
    }
}
```

In `TidyShotTests/ScrollCaptureSessionTests.swift` (Task 5), add after `previewFollowsTheStitchAtMostFourTimesASecond`:
```swift
    /// The checkbox counts only with the grant: without it the ready line is manual's and Start
    /// starts manual mode; the grant arriving while the panel shows enables it, and unticking
    /// the box is reported for `AppSettings`.
    @Test func autoScrollNeedsTheGrantAndTheCheckbox() async throws {
        let clock = FakeScrollClock()
        let world = FakeScrollWorld(page: makePage(), clock: clock, pointer: CGPoint(x: 140, y: 200))
        world.permitted = false
        let session = ScrollCaptureSession(
            source: world.source, engine: ScrollStitchEngine(finder: world.page.finder),
            area: CGRect(x: 100, y: 100, width: 80, height: 200), scale: 2, colorSpace: sRGB, clock: clock,
            autoScrollEnvironment: world.environment, prefersAutoScroll: true)
        var stored: [Bool] = []
        session.onAutoScrollChanged = { stored.append($0) }
        #expect(session.autoScroll)
        #expect(!session.isAutoScrollPermitted)
        #expect(!session.usesAutoScroll)
        #expect(session.status == .readyManual)

        world.permitted = true
        session.refreshAutoScrollPermission()
        #expect(session.isAutoScrollPermitted)
        #expect(session.status == .readyAuto)
        #expect(session.status.text == "Click Start, then hold the pointer over the area.")

        session.autoScroll = false
        #expect(session.status == .readyManual)
        #expect(stored == [false])

        await session.start()
        #expect(session.phase == .capturing(.manual))
        world.showFrame()
        try await eventually { session.hasFirstFrame }
        try await clock.run(for: .seconds(1))
        #expect(world.posted.isEmpty)
        await session.cancel()
    }
```

In `TidyShotTests/AppSettingsTests.swift`, after `rgbaStoredAsJSON` (before the closing brace, line 103):
```swift
    /// The Scroll automatically checkbox is on by default and persists (spec 2.8).
    @Test func scrollingAutoScrollDefaultsOnAndPersists() {
        let defaults = freshDefaults()
        let first = AppSettings(defaults: defaults)
        #expect(first.scrollingAutoScroll)
        first.scrollingAutoScroll = false
        #expect(defaults.object(forKey: "scrollingAutoScroll") as? Bool == false)
        #expect(!AppSettings(defaults: defaults).scrollingAutoScroll)
    }
```

Expected numbers: after a move to offset `o` the stitch that reached it is `40 + o + 330 + 30` rows. With the cap at 700, the steps reach 200, 398 and 596, and the commit after the third crosses 700.

- [ ] **Step 2: Run the tests and watch them fail**

Run:
```bash
xcodegen generate && xcodebuild test -project TidyShot.xcodeproj -scheme TidyShot -destination 'platform=macOS' -derivedDataPath .build 2>&1 | grep -E "Test run with|error:|TEST"
```
Expected: compile errors, among them `cannot find type 'ScrollEventPoster' in scope`, `cannot find type 'AutoScrollEnvironment' in scope`, an `extra arguments` error for the session's two new parameters and `value of type 'AppSettings' has no member 'scrollingAutoScroll'`, then `** TEST FAILED **` and no `Test run with` line.

- [ ] **Step 3: The permission**

`TidyShot/Capture/PostEventPermission.swift`:
```swift
import AppKit
import CoreGraphics

/// The PostEvent privilege auto-scroll needs (spec 2.8, Auto-scroll permission). It is
/// compatible with the App Sandbox and needs no entitlement; System Settings lists it under
/// Privacy & Security > Accessibility. Mirrors `ScreenCapturePermission`.
enum PostEventPermission {
    /// True when this app may post events. Does not prompt.
    static var isGranted: Bool {
        CGPreflightPostEventAccess()
    }

    /// Shows the system prompt the first time. Later calls return the current state.
    @discardableResult
    static func request() -> Bool {
        CGRequestPostEventAccess()
    }

    /// Opens System Settings > Privacy & Security > Accessibility.
    static func openSystemSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }
}
```

`TidyShot/Capture/AutoScrollPermissionWindowController.swift`, built like `PermissionWindowController.swift`:
```swift
import AppKit
import SwiftUI

struct AutoScrollPermissionView: View {
    @State private var isGranted = PostEventPermission.isGranted

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Accessibility access for auto-scroll", systemImage: "scroll")
                .font(.title2.bold())
            Text("To scroll other apps for you during a scrolling capture, TidyShot posts scroll-wheel events. macOS lists this under Privacy & Security > Accessibility. TidyShot posts them only while a scrolling capture runs. Without it, you scroll and TidyShot captures as you go.")
                .fixedSize(horizontal: false, vertical: true)
            if isGranted {
                Label("Access granted. Auto-scroll is ready.", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                HStack {
                    Button("Request Access") {
                        PostEventPermission.request()
                    }
                    .keyboardShortcut(.defaultAction)
                    Button("Open System Settings") {
                        PostEventPermission.openSystemSettings()
                    }
                }
            }
            Text("If auto-scroll stays unavailable after you allow it, quit and reopen TidyShot.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(24)
        .frame(width: 440)
        .task {
            while !Task.isCancelled {
                isGranted = PostEventPermission.isGranted
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }
}

/// Shows the auto-scroll permission window from the scrolling panel's link. Reuses the window.
final class AutoScrollPermissionWindowController {
    private var window: NSWindow?

    func show() {
        if window == nil {
            let newWindow = NSWindow(contentViewController: NSHostingController(rootView: AutoScrollPermissionView()))
            newWindow.title = "TidyShot"
            newWindow.styleMask = [.titled, .closable]
            newWindow.isReleasedWhenClosed = false
            newWindow.center()
            window = newWindow
        }
        NSApplication.shared.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}
```

- [ ] **Step 4: The event poster**

`TidyShot/Scrolling/ScrollEventPoster.swift`:
```swift
import CoreGraphics

/// Posts scroll-wheel events for auto-scroll (spec 2.8, Auto-scroll driver). Positive `points`
/// move the content up, showing what lies below, as scrolling down does. Main actor by the module
/// default; the real poster is nonisolated, the tests' fake is a main-actor class.
protocol ScrollEventPoster {
    func post(points: CGFloat)
}

/// One continuous, pixel-unit wheel event at the HID tap. It goes to the window under the
/// pointer, so the driver posts only while the pointer is over the area. Without the PostEvent
/// grant macOS drops it silently.
nonisolated struct HIDScrollEventPoster: ScrollEventPoster {
    func post(points: CGFloat) {
        guard let event = CGEvent(scrollWheelEvent2Source: CGEventSource(stateID: .hidSystemState), units: .pixel,
                                  wheelCount: 1, wheel1: Int32(-points.rounded()), wheel2: 0, wheel3: 0) else { return }
        event.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
        event.post(tap: .cghidEventTap)
    }
}
```

- [ ] **Step 5: The driver**

`TidyShot/Scrolling/AutoScrollDriver.swift`:
```swift
import AppKit
import CoreGraphics
import Foundation

/// What auto-scroll needs from the system, so the tests drive it with fakes.
struct AutoScrollEnvironment {
    var poster: any ScrollEventPoster
    /// The pointer in CoreGraphics global points (top-left origin), like the session's area.
    var pointerLocation: () -> CGPoint
    /// Whether the PostEvent grant holds; asked before Start and before every step.
    var isPermitted: () -> Bool

    /// The HID poster, `NSEvent.mouseLocation` (polling it needs no permission) and
    /// `PostEventPermission`.
    static func live() -> AutoScrollEnvironment {
        AutoScrollEnvironment(
            poster: HIDScrollEventPoster(),
            pointerLocation: {
                Geometry.cgPoint(fromAppKit: NSEvent.mouseLocation, primaryHeight: NSScreen.screens.first?.frame.height ?? 0)
            },
            isPermitted: { PostEventPermission.isGranted })
    }
}

/// Scrolls the captured area for a session in auto mode (spec 2.8, Auto-scroll driver). It
/// posts a step only while the pointer is over the area and the grant holds, waits for the
/// screen to settle, hands the settled frame to the session, and follows `ScrollEndDetector`.
/// TidyShot never moves the pointer: moving it away pauses, moving it back resumes.
final class AutoScrollDriver {
    /// The pointer is polled, and settling checked, this often: 20 times a second.
    static let pollInterval: Duration = .milliseconds(50)

    private let environment: AutoScrollEnvironment
    private let clock: any ScrollClock

    init(environment: AutoScrollEnvironment, clock: any ScrollClock) {
        self.environment = environment
        self.clock = clock
    }

    /// Runs until the session leaves auto mode: the end, a hand-over, Done or Cancel (which
    /// cancel this task).
    func run(session: ScrollCaptureSession) async {
        var detector = ScrollEndDetector()
        var direction: CGFloat = 1
        var step = AutoScrollPlan.firstStep(areaHeightPoints: session.area.height)
        // Set once a step has gone to the end detector, and once the other direction was tried.
        var decided = false
        var triedOtherDirection = false
        while session.phase == .capturing(.auto) {
            guard environment.isPermitted() else {
                session.handOver()
                return
            }
            guard session.hasFirstFrame, session.area.contains(environment.pointerLocation()) else {
                session.showAutoStatus(.autoPaused)
                guard await pause(Self.pollInterval) else { return }
                continue
            }
            session.showAutoStatus(.autoScrolling)
            guard let frame = await scroll(by: step * direction, in: session),
                  let progress = await session.integrate(frame, predicted: Int((step * session.scale).rounded()))
            else { return }
            // Nothing moved on the very first step: at the top of a page in an app that inverts
            // synthetic deltas, the step pushed against the top. Try the other direction once,
            // as a fresh first step, before the end detector may count it as the end.
            if !decided, !triedOtherDirection, progress.step.match == .still, !progress.step.isFull {
                triedOtherDirection = true
                direction = -direction
                continue
            }
            decided = true
            switch detector.decide(after: progress.step.match, isFull: progress.step.isFull) {
            case .continue:
                if case .moved(_, let top, let bandEnd, _) = progress.step.match {
                    step = AutoScrollPlan.nextStep(bandHeightPixels: bandEnd - top, scale: session.scale)
                }
            case .retryAfter(let delay):
                guard await pause(delay) else { return }
            case .reverseDirection:
                direction = -direction
            case .shrinkStep:
                // Back over the step that lost the place, so the smaller one overlaps the last
                // accepted frame again.
                guard await scroll(by: -step * direction, in: session) != nil else { return }
                step = AutoScrollPlan.shrunk(step)
            case .handOver:
                session.handOver()
                return
            case .end(let reason):
                await session.finish(showing: reason == .reachedEnd ? .autoReachedEnd : .heightLimit)
                return
            }
        }
    }

    /// Posts `points` (positive scrolls down) as events of at most 50 pt, 10 ms apart, then
    /// waits until the area settles and returns the newest frame. Nil when the session left auto
    /// mode or the task was cancelled.
    private func scroll(by points: CGFloat, in session: ScrollCaptureSession) async -> ScrollFrame? {
        let ignored = Int((ScrollCaptureLimits.scrollbarStripPoints * session.scale).rounded())
        let baseline = session.latestFrame.map { FrameSettler.contentHash(of: $0, ignoringRightColumns: ignored) }
        var seen = session.frameSerial
        for (index, size) in AutoScrollPlan.events(forPoints: abs(points)).enumerated() {
            if index > 0 {
                guard await pause(AutoScrollPlan.eventSpacing) else { return nil }
            }
            guard session.phase == .capturing(.auto) else { return nil }
            environment.poster.post(points: points < 0 ? -size : size)
        }
        var settler = FrameSettler(stepStart: clock.now, baselineHash: baseline)
        while session.phase == .capturing(.auto) {
            guard await pause(Self.pollInterval) else { return nil }
            if session.frameSerial != seen, let frame = session.latestFrame {
                seen = session.frameSerial
                _ = settler.observe(.frame(hash: FrameSettler.contentHash(of: frame, ignoringRightColumns: ignored),
                                           at: session.latestFrameAt ?? clock.now))
            }
            if settler.observe(.idle(at: clock.now)) { return session.latestFrame }
        }
        return nil
    }

    /// Sleeps on the session's clock; false when the task was cancelled.
    private func pause(_ duration: Duration) async -> Bool {
        do {
            try await clock.sleep(for: duration)
            return true
        } catch {
            return false
        }
    }
}
```
The settler is seeded with the hash of the frame on screen before the step (Task 2 says "the last accepted frame"; after a retry or a scroll-back the frame on screen is the one that matters, and before the first move the two are the same). The driver runs on the main actor; the only work off it is the stitch inside `session.integrate`. Hashing every third row of the newest frame, at most 20 times a second, stays on the main actor.

- [ ] **Step 6: Auto mode in the session**

`TidyShot/Scrolling/ScrollCaptureSession.swift` (Task 5):

After `@ObservationIgnored var onEnd: ((ScrollCaptureOutcome) -> Void)?` add:
```swift
    /// The Scroll automatically checkbox (`AppSettings.scrollingAutoScroll`). It takes effect
    /// only while `isAutoScrollPermitted`; a change is reported through `onAutoScrollChanged`.
    var autoScroll: Bool {
        didSet {
            if phase == .ready { status = .ready(autoScroll: usesAutoScroll) }
            onAutoScrollChanged?(autoScroll)
        }
    }
    /// The PostEvent grant as last checked; always false without an environment.
    private(set) var isAutoScrollPermitted: Bool
    @ObservationIgnored var onAutoScrollChanged: ((Bool) -> Void)?
    /// Start begins in auto mode.
    var usesAutoScroll: Bool { autoScroll && isAutoScrollPermitted }
```
(`latestFrame`, `latestFrameAt` and `frameSerial`, which the driver settles on, are Task 5's.)
After `private let colorSpace: CGColorSpace` add `private let autoScrollEnvironment: AutoScrollEnvironment?`, and after `readTask` add `@ObservationIgnored private var driverTask: Task<Void, Never>?`.

Replace `init` with:
```swift
    /// `area` is in CoreGraphics global points on one display of backing scale `scale`;
    /// `colorSpace` is the space the source delivers frames in. Without `autoScrollEnvironment`
    /// the session is manual only.
    init(source: any FrameSource, engine: ScrollStitchEngine, area: CGRect, scale: CGFloat, colorSpace: CGColorSpace,
         clock: any ScrollClock = SystemScrollClock(), autoScrollEnvironment: AutoScrollEnvironment? = nil,
         prefersAutoScroll: Bool = false) {
        self.source = source
        self.engine = engine
        self.area = area
        self.scale = scale
        self.colorSpace = colorSpace
        self.clock = clock
        self.autoScrollEnvironment = autoScrollEnvironment
        let pixels = Geometry.pixelSize(points: area.size, scale: scale)
        widthPixels = pixels.width
        heightPixels = pixels.height
        let permitted = autoScrollEnvironment?.isPermitted() ?? false
        autoScroll = prefersAutoScroll
        isAutoScrollPermitted = permitted
        status = .ready(autoScroll: prefersAutoScroll && permitted)
    }
```

In `start()`, replace
```swift
        phase = .capturing(.manual)
        status = .manualCapturing
```
with
```swift
        let mode: ScrollMode = usesAutoScroll ? .auto : .manual
        phase = .capturing(mode)
        // Auto mode waits for the pointer over the area.
        status = mode == .auto ? .autoPaused : .manualCapturing
```
and after `readTask = Task { await self.read(events) }` add
```swift
            if mode == .auto, let autoScrollEnvironment {
                let driver = AutoScrollDriver(environment: autoScrollEnvironment, clock: clock)
                driverTask = Task { await driver.run(session: self) }
            }
```
In `done()`, after the `guard`, add `driverTask?.cancel()` (no scrolling while the last frame is stitched; frames drained after `stop()` are stitched as in manual mode). In `end(_:)`, after `phase = .ended`, add `driverTask?.cancel()`. Neither awaits the driver: the driver itself calls `finish(showing:)`, which calls `done()`.

In `take(_:)`, replace its last line, `apply(await engine.add(frame))`, with:
```swift
        // In auto mode the driver stitches the settled frames itself (`integrate`).
        guard phase != .capturing(.auto) else { return }
        apply(await engine.add(frame))
```
The frame is still stamped (`latestFrame`, `latestFrameAt`, `frameSerial`) and the first frame still begins the stitch, as in Task 5.
In `apply(_:)`, replace `case .lost: status = .manualLost` with
```swift
        // After a hand-over the hand-over line stays until the user finds the overlap again.
        case .lost: if status != .autoHandedOver { status = .manualLost }
```

Before `// MARK: Frames` add:
```swift
    // MARK: Auto-scroll

    /// Checks the PostEvent grant again; the panel does once a second before Start.
    func refreshAutoScrollPermission() {
        let permitted = autoScrollEnvironment?.isPermitted() ?? false
        guard permitted != isAutoScrollPermitted else { return }
        isAutoScrollPermitted = permitted
        if phase == .ready { status = .ready(autoScroll: usesAutoScroll) }
    }

    /// Auto mode: stitches a settled frame, `predicted` being the posted step in pixels. Nil once
    /// the session has left auto mode.
    func integrate(_ frame: ScrollFrame, predicted: Int) async -> StitchProgress? {
        guard phase == .capturing(.auto) else { return nil }
        let progress = await engine.add(frame, predicted: predicted)
        apply(progress)
        return phase == .capturing(.auto) ? progress : nil
    }

    /// Auto-scroll gives up: the user scrolls from here, and frames go to the engine again.
    func handOver() {
        guard phase == .capturing(.auto) else { return }
        phase = .capturing(.manual)
        status = .autoHandedOver
    }

    /// The driver's line while it scrolls or waits for the pointer.
    func showAutoStatus(_ line: ScrollCaptureStatus) {
        guard phase == .capturing(.auto), status != line else { return }
        status = line
    }
```

- [ ] **Step 7: Settings, the panel and the controller**

`TidyShot/Settings/AppSettings.swift`:
- In `Keys`, after line 49: `static let scrollingAutoScroll = "scrollingAutoScroll"`.
- After line 75:
  ```swift
      /// The scrolling panel's Scroll automatically checkbox. Effective only with the PostEvent grant.
      var scrollingAutoScroll: Bool { didSet { defaults.set(scrollingAutoScroll, forKey: Keys.scrollingAutoScroll) } }
  ```
- In `register(defaults:)`, after line 110: `Keys.scrollingAutoScroll: true,`.
- In `init`, after line 132: `scrollingAutoScroll = defaults.bool(forKey: Keys.scrollingAutoScroll)`.

`TidyShot/Scrolling/ScrollCaptureView.swift`: add `let onAllowAutoScroll: () -> Void` after `session`. Between the status line and the buttons, only while `session.phase == .ready`:
```swift
            if session.phase == .ready {
                Toggle("Scroll automatically", isOn: Binding(get: { session.usesAutoScroll },
                                                              set: { session.autoScroll = $0 }))
                    .disabled(!session.isAutoScrollPermitted)
                if !session.isAutoScrollPermitted {
                    Button("Allow Auto-Scroll…", action: onAllowAutoScroll)
                        .buttonStyle(.link)
                }
            }
```
and on the root view, so the grant is noticed while the panel waits for Start:
```swift
        .task {
            while !Task.isCancelled, session.phase == .ready {
                session.refreshAutoScrollPermission()
                try? await Task.sleep(for: .seconds(1))
            }
        }
```
Measure `chromeHeight` again with the checkbox and the link showing (Step 11) and raise the constant so nothing clips before Start; after Start the rows go and the preview gets the space.

`TidyShot/Scrolling/ScrollCapturePanel.swift`: `init(session: ScrollCaptureSession, onAllowAutoScroll: @escaping () -> Void)`, passed to `ScrollCaptureView(session:onAllowAutoScroll:)`.

`TidyShot/Scrolling/ScrollCaptureController.swift`:
- `init(engine: CaptureEngine, settings: AppSettings)`, storing `private let settings: AppSettings`, plus `private let permissionWindow = AutoScrollPermissionWindowController()`.
- In `run`, build the session with the two new arguments and persist the checkbox:
  ```swift
  let session = ScrollCaptureSession(source: source, engine: ScrollStitchEngine(finder: OverlapFinder(scale: source.scale)),
                                     area: rect, scale: source.scale, colorSpace: source.colorSpace,
                                     autoScrollEnvironment: .live(), prefersAutoScroll: settings.scrollingAutoScroll)
  session.onAutoScrollChanged = { [settings] value in settings.scrollingAutoScroll = value }
  ```
  and the panel as `ScrollCapturePanel(session: session, onAllowAutoScroll: { [weak self] in self?.permissionWindow.show() })`.

`TidyShot/App/AppCoordinator.swift`: Task 5's property becomes
```swift
    @ObservationIgnored private lazy var scrollCapture = ScrollCaptureController(engine: engine, settings: settings)
```

- [ ] **Step 8: Run the suite**

Run:
```bash
xcodegen generate && xcodebuild test -project TidyShot.xcodeproj -scheme TidyShot -destination 'platform=macOS' -derivedDataPath .build 2>&1 | grep -E "Test run with|error:|TEST"
```
Expected: no `error:` lines, `Test run with 565 tests in 72 suites passed`, then `** TEST SUCCEEDED **`. This task adds 11 tests and 1 new suite: `AutoScrollDriverTests` (9: `scrollsToTheEndAndFinishesOnTheSecondStill`, `waitsForLazyLoadingBeforeEnding`, `postsOnlyWhileThePointerIsOverTheArea`, `reversesOnceWhenTheFirstStepGoesBackwards`, `triesTheOtherDirectionWhenTheFirstStepIsStill`, `aPageThatNeverMovesEndsAfterTryingBothDirections`, `shrinksThenHandsOverAfterThreeLosses`, `handsOverWhenTheGrantGoes`, `theCapEndsAutoScroll`), `ScrollCaptureSessionTests.autoScrollNeedsTheGrantAndTheCheckbox` and `AppSettingsTests.scrollingAutoScrollDefaultsOnAndPersists`. `FakeScrollWorld.swift` has no tests. The driver tests run on the fake clock, so a 2 s pause costs no real time.

- [ ] **Step 9: Hand check for Tim: posted events arrive after a real grant**

Ask Tim to run the probe check from `probes/README-probes.txt` (about a minute) and paste the output. The probe app is ad-hoc signed with TidyShot's four sandbox entitlements (bundle id `io.tky.tidyshot.p5probe`). The README starts the 20 s listener first; here it starts after the grant, so the grant does not race it.
```bash
cd /private/tmp/claude-501/-Users-tim-git-tidyshot/9a2da3be-945b-4f0e-b67d-e80f9e2ec325/scratchpad/p5/probes
open -n -W --stdout "$PWD/req.txt" PostProbe.app --args request
# The system asks to allow PostProbe; in System Settings > Privacy & Security > Accessibility, turn PostProbe on.
./post listen 20 > listen.txt &
sleep 1
open -n -W --stdout "$PWD/send.txt" PostProbe.app --args send $(head -1 listen.txt | sed 's/pid=\([0-9]*\).*/\1/')
wait
cat req.txt send.txt listen.txt
```
Expected: `send.txt` has `sandboxed=true postEvent=true` and three `posted N to <pid>` lines; `listen.txt` has three `got scroll dy=…` lines and ends `received=3`. Afterwards Tim removes PostProbe from the Accessibility list (select it, press −) and runs `rm -rf ~/Library/Containers/io.tky.tidyshot.p5probe`.

Read the result:
- `postEvent=true` and `received=3`: delivery works for a sandboxed process. Record the date and the two lines for Task 7, then do Steps 10 and 11.
- `postEvent=false`: the grant did not take (a stale entry is common with ad-hoc signing). Tim removes PostProbe from the list, runs the `request` line again, allows it, and repeats the check once.
- `postEvent=true` and `received` below 3: record the three files and `sw_vers`, and still do Steps 10 and 11. The probe posts with `postToPid` to a listener with no window, while TidyShot posts at the HID tap to the window under the pointer, so Step 11's **Delivery** item with TidyShot itself decides.

**If delivery fails** (Step 11's **Delivery** item: the page never moves with the grant held and the pointer over the area): keep this task's code and tests and commit them as below, and report to the controller with the probe output. The controller adds one follow-up commit: `ScrollCaptureController.run` builds the session with `autoScrollEnvironment: nil`, so every session is manual and auto-scroll stays off; the panel shows **Scroll automatically** off and disabled with the caption `Auto-scroll is unavailable: macOS did not deliver TidyShot's scroll events.` in place of the **Allow Auto-Scroll…** link, so the checkbox says why. Manual mode, its tests and the rest of the panel are unaffected. Task 7 records the result in the checklist and in 2.8 (Risks).

- [ ] **Step 10: Check the grant flow by hand**

Build and run. TidyShot's own grant is separate from the probe's, and an ad-hoc rebuild (`Config/Local.xcconfig`, `CODE_SIGN_IDENTITY = -`) loses it as it loses Screen Recording.
```bash
xcodebuild -project TidyShot.xcodeproj -scheme TidyShot -configuration Debug -derivedDataPath .build build -quiet && open .build/Build/Products/Debug/TidyShot.app
```
Expected:
- Without the grant, ⌃⇧5 and select: the panel shows **Scroll automatically** off and disabled, **Allow Auto-Scroll…** under it, and `Click Start, then scroll down slowly.`. The menu bar menu has no auto-scroll item.
- **Allow Auto-Scroll…** opens a window titled TidyShot with the scroll symbol, `Accessibility access for auto-scroll`, the body text of spec 2.8, **Request Access** (default) and **Open System Settings**, and the caption `If auto-scroll stays unavailable after you allow it, quit and reopen TidyShot.`. Request Access shows the system prompt; Open System Settings opens Privacy & Security > Accessibility. Allow TidyShot there: within a second the window shows `Access granted. Auto-scroll is ready.` in green, and the panel's checkbox turns on and enabled, the link goes, and the line reads `Click Start, then hold the pointer over the area.`.
- Untick the box, Cancel, start another scrolling capture: the box is still unticked (`scrollingAutoScroll` persisted). Tick it again.
- After an ad-hoc rebuild the box is disabled again even if System Settings still shows TidyShot switched on (a stale entry): remove TidyShot from the list with −, add it again, and the box enables.

- [ ] **Step 11: Check auto-scroll by hand**

With the grant, open a long article in Safari scrolled to its top.
- **Delivery.** ⌃⇧5, select the article, Start with the pointer away from the area: `Paused. Move the pointer over the area to continue.` and nothing scrolls. Move the pointer over the area: the page scrolls by itself in steps, `Scrolling… Move the pointer away to pause.`, the preview and readout grow. If the page never moves with the grant held and the pointer over the area, delivery fails: skip the rest of this step and follow **If delivery fails** in Step 9.
- **Pause.** Move the pointer out mid-page: scrolling stops after the current step and the paused line shows; move it back: it resumes, and the saved image has no gap or doubled rows where it paused.
- **End.** Let it run: at the bottom it waits briefly, tries once more, shows `Reached the end.` for about half a second, and finishes as Done would: the Quick Access overlay, the file, the upload. The image is the whole article.
- **Lazy loading.** On a page that loads more as you reach the bottom (a long Slack channel, an infinite feed): the 700 ms retry picks up the new content at least once before the end; an infinite feed runs to `Reached the 16,384 pixel limit.`.
- **Natural scrolling.** In System Settings > Trackpad, toggle Natural scrolling and repeat from a page scrolled halfway down: either way the capture runs downwards (on the inverted setting, the first step goes up once, then it reverses). Repeat from the very top of the page: on the inverted setting the first step pushes against the top and nothing moves, then TidyShot tries the other direction once and runs down to the end.
- **Hand-over.** In an app that ignores continuous wheel events or scrolls by more than asked, or by revoking the grant in System Settings mid-capture: `Auto-scroll lost its place. Scroll back up a little, or click Done.` appears, posting stops, and scrolling by hand continues the capture as in manual mode.
- **Done and Escape.** Done mid-scroll stops scrolling at once and saves what was stitched; Escape with Safari frontmost cancels and saves nothing.
- **Panel height.** With the checkbox and link showing, nothing in the panel is clipped; adjust `ScrollCaptureView.chromeHeight` if it is.

- [ ] **Step 12: Commit**

```bash
git add TidyShot/Capture/PostEventPermission.swift TidyShot/Capture/AutoScrollPermissionWindowController.swift TidyShot/Scrolling/ScrollEventPoster.swift TidyShot/Scrolling/AutoScrollDriver.swift TidyShot/Scrolling/ScrollCaptureSession.swift TidyShot/Scrolling/ScrollCaptureView.swift TidyShot/Scrolling/ScrollCapturePanel.swift TidyShot/Scrolling/ScrollCaptureController.swift TidyShot/Settings/AppSettings.swift TidyShot/App/AppCoordinator.swift TidyShotTests/Support/FakeScrollWorld.swift TidyShotTests/AutoScrollDriverTests.swift TidyShotTests/ScrollCaptureSessionTests.swift TidyShotTests/AppSettingsTests.swift
git commit -m "feat: auto-scroll for scrolling capture behind the PostEvent permission"
```

### Task 7: Docs and checklist

**Files:**
- Create: `docs/testing/phase-5-manual-checklist.md`
- Modify: `README.md` (line 3, the intro sentence; one paragraph after line 38 in `## Permissions`; one row after line 46 in `## Default shortcuts`; a new `## Scrolling capture` section between `## Default shortcuts` and `## Upload`, which starts at line 50; one line after line 199 in `## Documents`)
- Modify: `docs/superpowers/specs/2026-10-19-tidyshot-screenshot-design.md` (the 2.1 Scrolling capture row at line 38; the 2.4 "Scrolling capture" paragraph at line 86; section 2.8, lines 474-593: always the scope sentence, the delivery risk and feasibility sentences, the driver's scroll-back and first-step reversal, and the frame-source contract, elsewhere only where Step 6 finds a divergence, plus its closing "Phase 5 (built)" paragraph; the Phase 5 block of section 6 at lines 700-704, always)
- Modify, only when Step 4 finds a divergence: `docs/superpowers/plans/2026-10-21-phase-5-scrolling-capture.md` (the "Test totals" table)
- Test: none (documentation only; no new tests)

**Interfaces:**
- Consumes (behaviour, names and strings the checklist, README and spec check describe; each is produced by Tasks 1 to 6 or by `main`):
  - Task 1: `OverlapFinder` (scrollbar strip of 16 pt, header and footer detection capped at 0.4 of the height, stripes, `predicted`), `ScrollStitcher` (`isFull`, `committedHeight`, header kept once, footer once at the end), `ScrollCaptureLimits.maxPixelHeight` = 16,384 and `minimumAreaHeightPoints` = 100.
  - Task 2: `ScrollCaptureStatus.text` (the ten status lines of 2.8), `ScrollEndDetector` (700 ms retry then `.reachedEnd`, reverse once, 40 pt floor, three losses hand over), `AutoScrollPlan` (events of at most 50 pt, 10 ms apart; first step half the area height, later steps 0.6 of the band), `ScrollPanelGeometry.frame(panelSize:area:visibleFrame:)` (12 pt right, else left, else inside the bottom-right corner), `SelectionOutcome.resolve(mode:dragRect:hasHighlight:)`, and `SelectionMode.scrolling` (Task 2 adds the case to `Selection.swift`).
  - Task 3: `ScrollFrameSource` (one `SCStream`, TidyShot excluded by application, display colour space), `ScrollStitchEngine.finish(scale:colorSpace:)` returning a `ScaledImage` at the display's scale.
  - Task 4: `KeyboardShortcuts.Name.captureScrolling` (⌃⇧5) and `.cancelScrollingCapture` (Escape, no recorder row), the menu item `Capture Scrolling` and the Shortcuts row `Capture scrolling:`, `AppCoordinator.captureScrolling()`, the detached encode in `save(_:)`, `ThumbnailMaker.cropForThumbnail(_:)` (an image taller than 3 times its width is cut to its top `width * 3 / 2` rows).
  - Task 5: `ScrollCaptureController.run(rect:display:)`, the panel (240 pt wide, 220 to `min(560, area height)` pt tall, non-activating, `canBecomeKey`), the dashed area frame, the live preview anchored to the bottom, the size readout `2,560 × 7,340 px`, **Cancel** / **Start** / **Done**, Return and Escape, the Capture Scrolling shortcut acting as Start and then Done, the failure notifications `Scrolling capture stopped` and `Scrolling capture failed`, and `ScrollCaptureSession.streamStoppedReason` (`The screen recording stream stopped.`, the reason when the stream stops without an error). TidyShot stays the active app with the panel key, so the app being captured looks inactive but still scrolls under the pointer. The cap shows `Reached the 16,384 pixel limit.` for 0.4 s, then finishes as Done does. Escape (`cancelScrollingCapture`) is enabled only while a session is on screen.
  - Task 6: `PostEventPermission`, `AutoScrollPermissionWindowController` with the title `Accessibility access for auto-scroll`, **Request Access**, **Open System Settings**, `Access granted. Auto-scroll is ready.`, the **Allow Auto-Scroll…** link, the **Scroll automatically** checkbox (`AppSettings.scrollingAutoScroll`, default true, disabled without the grant), the panel polling the grant once a second before Start, `AutoScrollDriver` (pointer gating, settling, the other direction tried once when the very first step is still, the scroll-back before a halved step, hand-over), and the result of Tim's delivery hand checks (Task 6, Steps 9 and 11), with the controller's fallback if delivery failed (auto-scroll off, the checkbox showing `Auto-scroll is unavailable: macOS did not deliver TidyShot's scroll events.`, manual mode unaffected).
  - `main`, unchanged: the 4b checklist's shape (`docs/testing/phase-4b-manual-checklist.md`), the README sections `## Permissions`, `## Default shortcuts` and `## Documents`, `ImageEncoder.pngData(from:scale:)` writing 72 x scale DPI, `history.json` records with `pixelWidth` and `pixelHeight`, the Quick Access overlay with Annotate and Delete, and the three after-capture actions.
- Produces: documentation only. Nothing depends on it. It is the last task of the plan.

Two points differ from the Phase 4b close-out, so follow them here:
- The section 6 bullets for Phase 5 were already written as "manual first, then auto-scroll behind the post-event permission flow, later horizontal" in the spec commit e6bf136. Step 6 only adds the "Delivered" line to that block. The 2.1 row and the 2.4 sketch still describe the first plan (Accessibility permission, auto first, a manual mode afterwards) and are always amended.
- Section 2.8 is amended where the build differs from it, and always where this plan decided something 2.8 does not state: the driver's scroll-back before a halved step, the other direction tried once when the first step is still, and the frame-source contract (Step 6). Tim's delivery checks in Task 6 settle the "Auto-scroll delivery is unverified" risk either way, so that bullet is always rewritten.

- [ ] **Step 1: Read the finished code the documents describe**

The checklist, the README and the spec check must match the build, not the plan. Run:
```bash
ls TidyShot/Scrolling
grep -rn "captureScrolling\|cancelScrollingCapture" TidyShot | cut -c1-180
grep -n "static let\|static var" TidyShot/Scrolling/ScrollCaptureLimits.swift
grep -rn "scrollingAutoScroll" TidyShot | cut -c1-160
grep -rn "scrollbarStripPoints\|maxRepeat\|stillFraction\|maxStaticFraction\|acceptScore\|minInformativeRows\|stripes" TidyShot/Scrolling/OverlapFinder.swift | head -20
grep -rn "quiet\|timeout" TidyShot/Scrolling/FrameSettler.swift | head -8
grep -rn "Duration\|milliseconds\|seconds" TidyShot/Scrolling/ScrollEndDetector.swift TidyShot/Scrolling/AutoScrollPlan.swift | head -12
grep -rn "minimumFrameInterval\|queueDepth\|colorSpaceName\|showsCursor" TidyShot/Scrolling/ScrollFrameSource.swift
grep -rn "CGPreflightPostEventAccess\|CGRequestPostEventAccess\|Privacy_Accessibility" TidyShot/Capture
git diff main --stat -- TidyShot/TidyShot.entitlements project.yml
while IFS= read -r s; do grep -rqF -- "$s" TidyShot || echo "MISSING: $s"; done <<'EOF'
Click Start, then scroll down slowly.
Click Start, then hold the pointer over the area.
Scroll down slowly. Click Done at the end.
Too fast. Scroll back up a little.
Scrolling… Move the pointer away to pause.
Paused. Move the pointer over the area to continue.
Auto-scroll lost its place. Scroll back up a little, or click Done.
Reached the end.
pixel limit.
Stitching…
Select an area at least 100 points tall.
Scrolling capture stopped
Scrolling capture failed
The capture stopped early:
TidyShot saved what it had.
The screen recording stream stopped.
Accessibility access for auto-scroll
To scroll other apps for you during a scrolling capture, TidyShot posts scroll-wheel events.
Access granted. Auto-scroll is ready.
If auto-scroll stays unavailable after you allow it, quit and reopen TidyShot.
Request Access
Open System Settings
Allow Auto-Scroll…
Scroll automatically
Capture Scrolling
Capture scrolling:
EOF
```
Expected: the files Tasks 1 to 6 list in `TidyShot/Scrolling`; the shortcut names registered once and used where 2.8 says; the constants of 2.8 (16, 4, 0.9, 0.4, 0.8, 8 stripes; 150 ms and 1.5 s; 700 ms; 50 pt events 10 ms apart; 1/30 s; queue depth 4); no `MISSING:` line; an empty `git diff` for the entitlements file and `project.yml` (Phase 5 adds no entitlement). Where the code differs from the wording in Step 2, in the README text of Step 3 or in 2.8, write the code's behaviour in the documents and list each change in the report. A `MISSING:` string, a constant or an entitlement change that looks like a bug rather than a decision is not documented away: stop and report it. Do not change code.

- [ ] **Step 2: Write the manual checklist**

`docs/testing/phase-5-manual-checklist.md`:
````markdown
# Phase 5 manual test checklist

Run after any change to `TidyShot/Scrolling/`, the Capture Scrolling entry points (the selection
overlay's scrolling mode, the shortcut, the menu item), `AppCoordinator.save(_:)`, `ThumbnailMaker`
or the post-event permission. Automated tests cover the overlap finder and the stitcher on synthetic
pages, every decision (settling, end detection, step plan, status lines, panel placement, selection
outcome), the engine's pixels through the PNG encoder, the session with a fake frame source, the
thumbnail crop and the new setting; everything here needs the real stream, real windows, real
apps, real scroll events, the real permission and eyes. The 4a and 4b checklists still cover the
overlay's buttons, Annotate, Save, Upload and caches; run them too after a change to those paths.

Setup: fresh build, Screen Recording granted, save folder set to Desktop, a working destination
saved in Settings > Upload, "Show notification" on in Settings > General, "Show Quick Access
overlay after capture" on in Settings > Overlay, Network Link Conditioner installed, and TidyShot
**not** in the Accessibility list of System Settings > Privacy & Security (remove it with the minus
button), so the first sections run without the post-event permission. Note how the build is signed
(`Config/Local.xcconfig`: ad-hoc or Apple Development); the permission section depends on it.
Capture only made-up data: a capture may be uploaded and the link may be shared.

Make the test page once. It has a sticky header, a fixed footer, a fixed spinner, 120 numbered
sections of distinct colour and text (about 21,000 pt tall), and two modes: `#lazy` appends 20
sections 400 ms after the end is reached, and `#jump` scrolls 1.6 screens on every wheel event, so
each auto-scroll step is too big.
```bash
mkdir -p ~/Desktop/p5 && cd ~/Desktop/p5
{
cat <<'HTML'
<!doctype html><meta charset="utf-8"><title>Long test page</title>
<style>
body{font:18px/1.5 -apple-system,sans-serif;margin:0;padding-bottom:60px}
header{position:sticky;top:0;z-index:2;background:#1d4ed8;color:#fff;padding:14px 24px;font-weight:600}
footer{position:fixed;bottom:0;left:0;right:0;z-index:2;background:#111;color:#fff;padding:12px 24px}
section{padding:20px 24px;border-bottom:1px solid #ccc}
section div{height:70px;margin-top:8px;border-radius:6px}
.spin{position:fixed;top:90px;right:60px;z-index:1;width:30px;height:30px;border:5px solid #999;border-top-color:#000;border-radius:50%;animation:s 1s linear infinite}
@keyframes s{to{transform:rotate(360deg)}}
</style>
<header>Long test page: sticky header</header>
<div class="spin"></div>
HTML
for i in $(seq 1 120); do
  printf '<section><b>Section %03d</b><br>Each section has its own number, colour and text, so no two screens look alike. Item %03d.<div style="background:hsl(%d,70%%,60%%)"></div></section>\n' $i $i $(( (i*37) % 360 ))
done
cat <<'HTML'
<footer>Footer: this site uses cookies (fixed)</footer>
<script>
if(location.hash==='#lazy'){var loaded=false;addEventListener('scroll',function(){if(!loaded&&innerHeight+scrollY>=document.body.scrollHeight-5){loaded=true;setTimeout(function(){for(var i=1;i<=20;i++){var s=document.createElement('section');s.innerHTML='<b>Late section '+i+'</b><br>Loaded after the page reached its end.<div style="background:hsl('+(i*17)+',70%,60%)"></div>';document.body.insertBefore(s,document.querySelector('footer'))}},400)}})}
if(location.hash==='#jump'){addEventListener('wheel',function(e){e.preventDefault();scrollBy(0,innerHeight*1.6)},{passive:false})}
</script>
HTML
} > long.html
grep -v 'class="spin"' long.html > long-still.html
```
`long-still.html` has no spinner, so it holds still for the pixel comparison. Open them with
`open -a Safari ~/Desktop/p5/long.html` (add `"file://$HOME/Desktop/p5/long.html#lazy"` for the other
modes). Also have ready:
- a Terminal window about 900 by 700 pt with `seq -f "line %05g  the quick brown fox jumps over the lazy dog" 1 3000` run in it (every row differs by its number);
- a chat with 300 or more messages: a private Slack channel or a conversation with yourself in Messages, with a header that stays put (never a real conversation);
- Settings > Overlay and Settings > General as in the 4b setup, and the Terminal's cursor blinking (the default);
- optional: a second display, ideally at a different scale, and Chrome.

`history.json` is in `~/Library/Containers/io.tky.tidyshot/Data/Library/Application Support/TidyShot/`;
thumbnails are in its `thumbnails` folder. Where an item says "compare with a one-shot", the one-shot is
a `⌃⇧4` capture of the same region made with the pointer outside it.

## Starting a capture
- [ ] The menu bar menu lists `Capture Scrolling  ⌃⇧5` after Capture Fullscreen. Settings > Shortcuts has a `Capture scrolling:` row with ⌃⇧5; change it to another combination, confirm the menu and the new keys work and ⌃⇧5 does not, then reset it. There is no recorder row for Escape.
- [ ] ⌃⇧5 opens the selection overlay with the crosshair, the loupe and the dimension readout of Capture Area, and hovering a window highlights it, as in Capture Window. Escape cancels the overlay and nothing else appears.
- [ ] Drag an area about 700 by 500 pt: the overlay closes and two things appear, a dashed outline just outside the area (white line, black halo, visible over both light and dark content) and a panel. Click a window instead (no drag): the window's whole frame becomes the area.
- [ ] Drag an area 400 pt wide and 60 pt tall: no session starts and a notification titled `Scrolling capture` says `Select an area at least 100 points tall.` The next ⌃⇧5 works. An area exactly 100 pt tall is accepted.
- [ ] A click on a window that is partly off the screen, or taller than the screen, takes the part on its display. Nothing crashes.
- [ ] While a session is open (panel on screen), the menu's Capture Area, Capture Window, Capture Fullscreen and Capture Scrolling items are disabled and ⌃⇧4, ⌃⇧2 and ⌃⇧3 do nothing; ⌃⇧5 acts as Start, then as Done. All of them work as before after Done or Cancel.

## The panel and the frame
- [ ] The panel is 240 pt wide and sits 12 pt to the right of the area. Make the area touch the right edge of the screen: the panel moves 12 pt to the left of it. Make the area fill the screen's width: the panel sits inside the area's bottom-right corner, 12 pt from its edges. In every case it stays on the screen of the area, and under the menu bar and the Dock.
- [ ] The panel shows, top to bottom: the preview, the size readout, the status line, the **Scroll automatically** checkbox and the buttons **Cancel** and **Start**. Before Start the status line reads `Click Start, then scroll down slowly.` (checkbox off or on without the grant: see the permission section for the checkbox).
- [ ] The panel is key and TidyShot stays the active app, so Return presses Start (then Done) and Escape cancels. Safari's window therefore looks inactive while the panel is up; that is expected. After Start the trackpad and the mouse wheel still scroll Safari under the pointer without a click first, and the capture follows.
- [ ] Neither the panel nor the dashed frame is in the stitched image, even when the panel sits inside the area (see the last item of the previous section) and when the Quick Access overlay of an earlier capture is on screen over the area. Take such a capture and look for them.
- [ ] The dashed frame never takes a click or a scroll: with the pointer over its outline, scrolling still moves the page below.
- [ ] The screen-recording indicator appears in the menu bar after Start and is gone after Done and after Cancel.

## Manual mode on a long web page (Safari)
Open `long-still.html` in Safari at the top, with the window about 1100 by 800 pt. Take a `⌃⇧4` one-shot of the page area (not the toolbar) first and keep it. Drag the same area for ⌃⇧5.
- [ ] Click Start, scroll down slowly with the trackpad (about a screen every two seconds), watch, and click Done at the end of the page. The panel's preview grows from the bottom, showing the newest rows; the readout counts up with comma separators (`2,200 × 7,340 px` style) and its digits do not jitter; the status line reads `Scroll down slowly. Click Done at the end.`
- [ ] The saved capture is one tall PNG of the whole page: sections 001 to 120 in order, none missing or repeated, no seams, no doubled rows at the joins. The sticky header is there once, at the top; the fixed footer is there once, at the end (if the area covers them).
- [ ] Pixel check against the one-shot: `sips -c <h> <w> --cropOffset 0 0 <stitched.png> --out /tmp/top.png`, using the one-shot's pixel height and width, then `sips -s format bmp /tmp/top.png --out /tmp/a.bmp && sips -s format bmp <one-shot.png> --out /tmp/b.bmp && cmp /tmp/a.bmp /tmp/b.bmp && echo SAME`. Expected `SAME`: the first screen of the stitched image equals a one-shot of the same region. `sips -g profile -g dpiWidth -g pixelWidth` reports the same profile and `dpiWidth` as the one-shot (144 on a 2x display, 72 on a 1x display).
- [ ] Scroll with the trackpad, a mouse wheel and the Space and Page Down keys (about a screen at a time): all work. Scroll up a little in the middle of the capture, then on down: the page is still contiguous and nothing is repeated.
- [ ] Click Start and Done at once without scrolling: a single-frame capture of the area, like an ordinary area capture. Pressing ⌃⇧5 again acts as Start, and then as Done.
- [ ] Open `long.html` (with the spinner) and capture it. The spinner does not break the match. Look at its trace: the spinner is fixed on the screen inside the band, so it appears once per screen of content, in whatever rotation it had. This is the documented behaviour for fixed overlays; write down what you see (how many, where) for the spec.
- [ ] The overlay scrollbar appears and moves while scrolling. The stitch is not thrown off by it; write down whether fragments of the scrollbar thumb show along the right edge of the result.
- [ ] Safari with the window as the pick: click the Safari window instead of dragging an area. The toolbar and tab bar are at the top of the result exactly once, the page follows, and the corners behind the window's rounded corners show what lay behind them (the desktop), not transparency. Pick the same window with another window overlapping part of it: the overlapping window is in the capture where it covers, which is expected (the capture is of the display).
- [ ] Repeat the capture in Chrome, if installed: same page, same result. Write down what Chrome does with the fixed spinner and footer compared with Safari.

## The too-fast line
- [ ] Safari at the top, Start, scroll a little, then press End (the whole page jumps far past the area's height): the status line becomes `Too fast. Scroll back up a little.` and the preview stops growing. Press Home, then scroll down slowly: the line clears at the first matched movement and the capture goes on. Done: the result is still contiguous; the content jumped over is missing only if you never scrolled back to it (it is not in the result then).
- [ ] A hard trackpad flick (a 3000 pt fling) does the same: the line shows while the page is too far from the last accepted screen and clears after you scroll back into overlap. A slow flick that you let coast never shows the line.
- [ ] Done while the line shows saves what was stitched before the loss, at the right size, with no half-written rows at the end.

## Manual mode on Terminal scrollback
Terminal with the `seq` output run, scrolled up to about line 1500.
- [ ] Drag the Terminal's text area, Start, scroll down slowly to the prompt, Done. The result shows consecutive numbered lines to the prompt. Check them with Live Text: open the PNG in Preview, ⌘A, ⌘C, then `pbpaste | grep -o 'line [0-9]\{5\}' | sed 's/line //' | awk 'NR>1 && $1!=p+1 {print "gap or repeat at " $1} {p=$1}'`. Expected: no output (every line appears once, in order). A few Live Text misreads are not failures; note them.
- [ ] The Terminal's blinking cursor at the prompt row does not confuse the match. The last rows of the result show the prompt once.
- [ ] Click the Terminal window instead of dragging: the title bar and window edges stay at the top of the result once (a static header), the lines follow.
- [ ] Run `yes "same line" | head -200` and capture a stretch of it taller than the area. Expected: the content is identical row after row, so TidyShot cannot place the screens: the too-fast line shows when you scroll there, and Done saves what came before. This is the documented limit (content with no distinctive rows); write down what happens.

## Manual mode in a chat window
The chat from the setup, scrolled so a few hundred messages lie below the view.
- [ ] Click the chat window as the pick (header, message list and composer in one frame), Start, scroll down slowly to the newest message, Done. The window header is at the top once and the composer at the bottom once; no message is repeated or missing; day separators and avatars line up across the joins.
- [ ] A sticky date label that floats over the messages and changes while you scroll: write down whether it is stitched in once per screen (as with the spinner) or not at all.
- [ ] Drag only the message list instead (no header, no composer): the result is messages only, with no static rows at the ends.
- [ ] Typing indicators, presence dots and a blinking caret in the composer do not break the match.
- [ ] Messages loading in at the bottom while you capture (send a few from another device): the capture stays contiguous or shows the too-fast line and recovers; it never crashes.

## The height cap
`long.html` is about 21,000 pt tall, so a Retina capture reaches 16,384 px (8,192 pt) before the end. On a 1x display the cap is 16,384 pt.
- [ ] Capture from the top of `long.html` with a 1000 pt tall area and keep scrolling. When the height reaches the cap the status line reads `Reached the 16,384 pixel limit.`, the session ends by itself and `Stitching…` may flash. No Done click is needed. Write down whether the result appears without your input.
- [ ] `sips -g pixelHeight -g pixelWidth <file>` reports a height of exactly 16384 and the area's width in pixels. The content stops at a row, not in the middle of a half-written one: the last section is simply cut by the bottom edge.
- [ ] The menu bar menu opens without delay while the cap capture is encoding after Done (the encode is off the main actor), and the overlay appears within a few seconds. Write down the time from Done to the overlay.
- [ ] Memory: Activity Monitor shows TidyShot using well under 1 GB at the cap, and back near its idle size a few seconds after the overlay appears.
- [ ] A capture that ends just below the cap by Done, and one that ends exactly at it, both save and open.

## Escape and Cancel
- [ ] Before Start, Escape closes the panel and the frame and nothing is saved. Before Start, **Cancel** does the same.
- [ ] After Start with Safari frontmost, Escape cancels at once: the panel, the frame and the indicator go, nothing is written to the save folder, no row appears in Recent Captures, no upload starts, `history.json` is unchanged, and the Quick Access overlay does not appear.
- [ ] Same with **Cancel**, after scrolling a few screens: nothing is saved, and a new ⌃⇧5 starts a fresh session with an empty preview.
- [ ] Escape is not swallowed outside a session. After Done or Cancel, type some text in Safari's address bar and press Escape: the address reverts, as it does without TidyShot running. Escape also works normally in a Terminal running `vim` and in a full-screen video.
- [ ] Escape is not swallowed during the selection overlay either way: it cancels the overlay and the next Escape in another app behaves normally.
- [ ] Click **Done** in the panel while another app is frontmost: it finishes the capture and the overlay appears; the other app stays frontmost.

## Window versus area
- [ ] Capture the same Safari window twice, once by clicking it and once by dragging a rectangle over exactly the same frame. The widths in pixels match, the contents match, and both images come out the same way, window chrome included; no transparent corners in either (the capture is of the display).
- [ ] An area inside a page with a pane on the left and a pane on the right (Finder's list view with its sidebar, or Notes): put the pointer over the pane to scroll. The pane that scrolls is stitched; the fixed sidebar columns are copied from the screen, and the result has no seam where the sidebar meets the list.
- [ ] A window on a display other than the main one: the capture is of that display (not the main one), at that display's scale.
- [ ] Mixed scales (needs two displays): repeat the Safari capture on a 1x display. The PNG is in points (width in pixels equals the area's width in points), `dpiWidth` is 72, and the first screen equals a one-shot taken there.

## Auto-scroll and the post-event permission
Run this section after the manual ones. TidyShot is still not in the Accessibility list.
- [ ] Open a session. **Scroll automatically** is off and disabled, and an **Allow Auto-Scroll…** link sits under it. Start still works and behaves as manual mode, with the manual status lines. Cancel.
- [ ] The link opens a window titled `Accessibility access for auto-scroll` with a scroll icon, the body text about posting scroll-wheel events (`Without it, you scroll and TidyShot captures as you go.`), the buttons **Request Access** (default) and **Open System Settings**, and the caption `If auto-scroll stays unavailable after you allow it, quit and reopen TidyShot.` The menu bar menu has no item for this permission.
- [ ] **Request Access** shows the system prompt. **Open System Settings** opens Privacy & Security > Accessibility. Add or switch on TidyShot there. Within about a second the window shows `Access granted. Auto-scroll is ready.` in green, without reopening it.
- [ ] With a session open before Start when the grant happens, the panel notices within about a second: the checkbox turns on and enabled, the link goes, and the status line reads `Click Start, then hold the pointer over the area.` A new session shows the same.
- [ ] Uncheck the checkbox, finish the session, open another: it is still off. Check it again for the next items.
- [ ] Delivery, first of all: with the grant held, Start with the pointer over the area moves the page. If no wheel event reaches the app, skip the rest of this section, write it down and report it: Task 6's fallback applies (auto-scroll stays off, the checkbox shows off and disabled with `Auto-scroll is unavailable: macOS did not deliver TidyShot's scroll events.` under it instead of the link, and every manual item above is unaffected). If the fallback is already in the build, check exactly that and that manual mode works.
- [ ] Safari, `long.html` at the top, area dragged over the page: Start with the pointer outside the area: the status line reads `Paused. Move the pointer over the area to continue.` and nothing scrolls. Move the pointer into the area: the line reads `Scrolling… Move the pointer away to pause.` and the page scrolls by itself, first by about half the area, then by about 0.6 of the part between any sticky header and footer, with a short settle between steps. Move the pointer out: it pauses within a fraction of a second, and TidyShot never moves the pointer. Move it back in: it resumes.
- [ ] Let it run to the end of the page: after two unchanged screens (with a short wait before the second) the line reads `Reached the end.` and, after a moment, the capture finishes by itself and the overlay appears. The result is the whole page in order, the footer once at the end, no repeat of the last screen, the same checks as the manual page capture. Write down the time per screen.
- [ ] `long.html#lazy`: auto-scroll reaches the bottom, waits, the 20 late sections load, and the capture goes on through them to a second end. The result includes `Late section 20`. If the late sections never load, scroll by hand to the bottom once to check the page.
- [ ] `long.html#jump`: every wheel event jumps the page 1.6 screens down, so each step loses the match. After each loss TidyShot posts a step back and halves the next one (the page jumps again, since this page turns every wheel event into a jump down); after three losses in a row the line reads `Auto-scroll lost its place. Scroll back up a little, or click Done.` and no more events are posted. Continue by hand with the keyboard (this page turns the wheel into jumps): press Home, then hold the Down arrow; the line changes to `Scroll down slowly. Click Done at the end.` at the first matched movement and the capture continues in manual mode. Done saves what was stitched.
- [ ] Natural scrolling: run the Safari auto-scroll capture with System Settings > Trackpad > Scroll & Zoom > Natural scrolling on, then off (and a mouse set to the opposite). Both finish at the end of the page. Start once from halfway down and once from the very top. From halfway, if the first step moves the page up, TidyShot flips the direction once and carries on. From the top, if the first step pushes against the top and nothing moves, TidyShot tries the other direction once and runs down to the end; it does not end on the first screen. Write down which setting caused either, if any.
- [ ] Terminal scrollback and the chat from the earlier sections: auto-scroll with the pointer over the area scrolls them to the end and the result matches the manual one (the `awk` check passes for Terminal).
- [ ] A page with the pointer over a pane that does not scroll (a toolbar, a sidebar): wheel events go to the view under the pointer, so nothing scrolls. TidyShot tries the other direction once, waits 700 ms, tries again, then shows `Reached the end.` and saves the first screen alone. Write down what the result is.
- [ ] Revoke while it runs: start an auto-scroll capture, remove TidyShot from the Accessibility list. The next step hands over to manual (the hand-over line); no event is posted afterwards, and the capture finishes by hand.
- [ ] Re-granting after an ad-hoc rebuild: rebuild and relaunch the app (ad-hoc signing). Open a session: the checkbox is off and disabled again, even though System Settings may still show TidyShot switched on (a stale entry). Remove TidyShot from the list with the minus button, press **Request Access** in the permission window, switch it on: the window shows `Access granted. Auto-scroll is ready.` and auto-scroll delivers events again. Screen Recording needs the same re-grant after an ad-hoc rebuild. With Apple Development signing, a rebuild keeps both: write down which signing you tested.
- [ ] Afterwards, quit and reopen TidyShot with the grant in place: the checkbox is on, as the caption on the permission window says to do when it stays unavailable.

## The result: overlay, save and upload
Use the three after-capture actions in turn (Settings > General), each with a Safari capture of `long.html` of two or three screens.
- [ ] "Save and copy image": the overlay appears with the top of the page in its 96 by 72 well. The PNG is in the save folder, named by the file name template; `sips -g pixelWidth -g pixelHeight -g dpiWidth` reports the stitched size and 144 (or 72 on a 1x display). Preview > File > New from Clipboard shows the whole tall image, and pasting into Notes works.
- [ ] "Upload and copy URL": the overlay shows the upload; when it finishes the URL is on the clipboard. `curl -s <url> -o /tmp/tall.png && sips -g pixelWidth -g pixelHeight /tmp/tall.png` reports the same size as the file; `history.json` has that `pixelWidth` and `pixelHeight` (the full size, not the thumbnail's).
- [ ] "Upload only, keep no local file": nothing appears in the save folder, the upload finishes, the URL is on the clipboard and the temporary file is deleted. With Wi-Fi off, the upload fails and `pending/<UUID>.png` keeps the tall PNG until Retry Failed Uploads succeeds.
- [ ] With Network Link Conditioner on a slow profile, a tall capture's upload shows progress on the overlay and the overlay's Delete during the upload cancels it and removes what was written.
- [ ] The overlay's Delete on a stitched capture, after one confirmation: the file, the history row, the thumbnail and (when uploaded) the object are gone.
- [ ] Nothing is written or uploaded before Done: during a session, the save folder, `history.json` and the bucket do not change, in all three actions.
- [ ] The overlay appears, and the other captures work, while a previous tall capture is still encoding or uploading.
- [ ] A stream that stops by itself (optional, needs a second display): start a capture on the second display, scroll a few screens, then unplug that display or put it to sleep. A notification titled `Scrolling capture stopped` says `The capture stopped early: <reason> TidyShot saved what it had.` (the reason is `The screen recording stream stopped.` when ScreenCaptureKit gives none) and the rows stitched so far are saved like any capture. Stopped before the first frame arrived: `Scrolling capture failed` with the reason only, and nothing saved.

## Annotate a stitched capture
- [ ] The pencil button on the overlay opens the editor on a stitched capture of three screens. The picture shows complete at Fit, and ⌘1 (actual size) and ⌘0 (fit) work; scrolling and Space-drag pan along the whole height.
- [ ] Draw a redaction near the top, a text in the middle and an arrow near the bottom; the strokes sit on the content under the pointer at every height. Crop to the middle third: the saved size is the crop's. ⌘S writes the file; the unsaved dot behaves as for any capture.
- [ ] ⌘U on an uploaded stitched capture replaces the object under the same link; `curl` shows the edit at the full height.
- [ ] Annotate on the capture at the cap (the 16,384 px one): the editor opens and shows the picture, with no blank or black canvas, at Fit and at 100%. Scroll to the very bottom at 100% and draw a rectangle there; ⌘S saves it. Write down whether the pan and the drawing keep up (this is the check behind the 16,384 px cap).
- [ ] Recent Captures: the Annotate button on the row of a stitched capture opens the editor as above; "Upload only" captures that finished uploading download the object first and open it.

## Thumbnails of tall images
- [ ] A capture taller than three times its width (drag an area 300 pt wide and 400 pt tall, scroll through three screens): the overlay's well and the Recent Captures thumbnail show the **top** of the page, filling the well, not a thin sliver of the whole page. In the `thumbnails` folder `sips -g pixelWidth -g pixelHeight` on its file reports a height of 320 and a width of about 213 (2:3).
- [ ] The Recent Captures hover preview of the same row shows the top of the page too (write down whether it shows the thumbnail or the full image).
- [ ] A capture only 2.5 times as tall as it is wide (area 400 by 1000 pt, Start and Done at once): no crop; the thumbnail is the whole capture, about 128 by 320.
- [ ] A normal area, window and fullscreen capture still produce the thumbnails they did before (compare with an earlier row).
- [ ] `history.json` has the full `pixelWidth` and `pixelHeight` for each stitched row, and the row's subtitle shows the full size.

## Other apps and conditions
Capture each from a start of the content to its end by hand, then by auto-scroll, and write down the result (OK, or what went wrong).
- [ ] Notes with a long note; Finder in list view with a few hundred items (select the list, not the sidebar); Xcode's source editor on a long file; Slack's long channel, as above; Chrome, as above.
- [ ] Dark mode, system-wide: the dashed frame is visible over dark content and the panel is legible. Switch the appearance mid-session: nothing breaks.
- [ ] A site with a sticky header and a cookie footer: header once at the top, footer once at the end, in Safari and in Chrome.
- [ ] Natural scrolling on and off, both modes (see the permission section).
- [ ] Two displays at mixed scales: see the window-versus-area section.
- [ ] Reduce Motion on, and Increase Contrast on: the panel is usable, and a capture still completes.

## VoiceOver
Turn VoiceOver on (⌘F5) and open a session.
- [ ] VO-arrow around the panel: the preview, the size readout, the status line, the checkbox, **Cancel**, **Start** and then **Done** are each read by name or value, and the status line is read again when it changes. The Return and Escape keys work with the VoiceOver cursor in the panel.
- [ ] Turn VoiceOver off. Everything above behaves as before.

## Regression
- [ ] Capture Area, Capture Window and Capture Fullscreen after a scrolling capture: normal, with the Quick Access overlay, uploads and thumbnails as before; a window capture with transparent corners keeps them.
- [ ] Quit TidyShot during a session (⌘Q from the menu): the panel and frame go, the indicator goes, and no file is written.
````

- [ ] **Step 3: Update the README**

In `README.md`:

Replace lines 3-5 (the intro sentence) with:
```markdown
A macOS menu bar screenshot tool. Capture an area, a window, a display, or content taller than the
screen; it is saved as a Retina-correct PNG, copied to the clipboard, and uploaded to your own
S3-compatible bucket with the URL on your clipboard.
```

After line 38 (`` `DEVELOPMENT_TEAM`, then run `xcodegen generate` again. ``) add a blank line and:
```markdown
Auto-scroll in Scrolling capture needs a second, optional permission: Accessibility (the "post
event" privilege that lets TidyShot send scroll-wheel events), under the same Privacy & Security
pane. Without it you scroll yourself and everything else works. See Scrolling capture below; ad-hoc
rebuilds lose this grant like they lose Screen Recording.
```

In the shortcuts table, after the `| Capture fullscreen | ⌃⇧3 |` row (line 46) add:
```markdown
| Capture scrolling | ⌃⇧5 |
```

Insert before `## Upload` (line 50) this section:
````markdown
## Scrolling capture

Capture Scrolling (⌃⇧5, or the menu bar item) captures content taller than the screen: a long web
page, a terminal's scrollback, a chat channel. Drag an area at least 100 points tall, or click a
window to take its frame. A dashed outline marks the area and a small panel shows a live preview of
the stitched image, its size in pixels and a status line. Nothing is saved or uploaded until you
click Done; Cancel or Escape (which works from any app while a session runs) throws everything away.

**Manual mode.** Click Start (or press Return, or ⌃⇧5 again), scroll down slowly yourself, and click
Done (Return, or ⌃⇧5 again) at the end. If you scroll so fast that two screens no longer overlap,
the panel says "Too fast. Scroll back up a little."; scroll back until it clears and go on. Scrolling
up a little is harmless. Done straight after Start saves the area as an ordinary capture.

**Auto-scroll.** With "Scroll automatically" checked, hold the pointer over the area after Start and
TidyShot sends the scroll-wheel events itself, waits for the page to settle, and finishes when two
screens in a row show no change (after a short wait for lazy loading). Move the pointer out of the
area to pause; TidyShot never moves it. If it loses its place three times, it hands over to manual
mode. Auto-scroll needs the Accessibility permission (the "post event" privilege). The Allow
Auto-Scroll… link in the panel opens a window that requests it and opens System Settings. The grant
is tied to the app's code signature, so with ad-hoc signing every rebuild loses it: remove TidyShot
from the Accessibility list, add it again, and quit and reopen TidyShot if it still reads as
unavailable. Apple Development signing (see Permissions) keeps it.

**What to expect.** A header or footer that stays put (a toolbar, a sticky nav bar, a composer) is
kept once, at the top or bottom, and a fixed sidebar is ignored. A floating element inside the area
(a chat button, a spinner) is stitched in each time it appears. A capture ends at 16,384 pixels
tall (8,192 points on a Retina display); at that point the panel says so and the capture finishes.
An endless feed therefore runs to that limit. Content with no distinctive rows (a long run of
identical lines or a blank stretch taller than the area) cannot be placed, so the "Too fast" line
shows until you scroll back. A window pick captures the window's frame from the display, so a window
that overlaps it is in the picture. The macOS screen-recording indicator shows while a session runs.

After Done the capture goes through the same path as any other: the after-capture action, the
Quick Access overlay with Annotate and Delete, Recent Captures and the upload. A very tall capture's
thumbnail shows the top of the page. Annotate works on captures up to the 16,384 pixel limit.
Horizontal scrolling is not supported.
````

In `## Documents`, after the Phase 4b line (line 199) add:
```markdown
- Phase 5 manual test checklist: `docs/testing/phase-5-manual-checklist.md`
```

Then confirm no stale text remains:
```bash
grep -ni "limitation\|not yet\|coming\|later phase\|phase 5" README.md
```
Expected: only the Documents entry and, in the Scrolling capture text, no "not yet" or "coming" wording. A README line that says scrolling capture is missing or coming is deleted.

- [ ] **Step 4: Run the full suite and check the totals table**

Run:
```bash
xcodegen generate && xcodebuild test -project TidyShot.xcodeproj -scheme TidyShot -destination 'platform=macOS' -derivedDataPath .build 2>&1 | grep -E "Test run with|error:|TEST"
```
Expected: no `error:` lines, `** TEST SUCCEEDED **`, and `Test run with 565 tests in 72 suites passed`. This task adds no tests, so that count must equal the Task 6 row of the "Test totals" table in the plan's header section.

Reconcile the table against the repo:
```bash
grep -rhE '^(@MainActor )?(nonisolated )?struct [A-Za-z0-9]+Tests\b' TidyShotTests | wc -l; grep -rhE '^\s*@Test' TidyShotTests | wc -l
grep -c '[{][{]' docs/superpowers/plans/2026-10-21-phase-5-scrolling-capture.md
```
Expected: the first count is the suites and the second the tests in the Task 6 row (one `struct …Tests` per suite; Swift Testing counts a parameterized `@Test` as one test per argument in the run, so the run's count is the one to trust and the greps only help find which suites differ), and the last count is `0`, so no placeholder is left in the plan. The branch starts from the baseline of 468 tests in 58 suites. If the run differs from the Task 6 row, a review fix added or removed tests. Find which task with:
```bash
git log --oneline --stat 23fdff8..HEAD -- TidyShotTests
```
Correct that task's row and every row after it in the table, and add one line under the table: `Task 7 correction: <commit> <what changed>; the real run reads <the line>.` Change nothing else in the plan. If the run equals the row, change nothing.

Then check the new files against the task list:
```bash
git diff --name-only --diff-filter=A main...HEAD -- TidyShot TidyShotTests project.yml | sort
git diff --name-only --diff-filter=A main...HEAD -- TidyShot TidyShotTests | while read -r f; do grep -q "$(basename "$f")" docs/superpowers/plans/2026-10-21-phase-5-scrolling-capture.md || echo "NOT IN PLAN: $f"; done
for f in Scrolling/ScrollCaptureLimits Scrolling/ScrollFrame Scrolling/OverlapFinder Scrolling/ScrollStitcher Scrolling/FrameSettler Scrolling/ScrollEndDetector Scrolling/AutoScrollPlan Scrolling/ScrollCaptureStatus Scrolling/ScrollPanelGeometry Selection/SelectionOutcome Scrolling/ScrollFrameSource Scrolling/ScrollStitchEngine Selection/OverlayWindowLookup Scrolling/ScrollClock Scrolling/ScrollCaptureSession Scrolling/ScrollCaptureController Scrolling/ScrollCapturePanel Scrolling/ScrollCaptureView Scrolling/ScrollAreaFrameWindow Capture/PostEventPermission Capture/AutoScrollPermissionWindowController Scrolling/ScrollEventPoster Scrolling/AutoScrollDriver; do test -f TidyShot/$f.swift || echo "NO FILE: $f"; done
for t in ScrollFrameTests OverlapFinderTests ScrollStitcherTests FrameSettlerTests ScrollEndDetectorTests AutoScrollPlanTests ScrollCaptureStatusTests ScrollPanelGeometryTests SelectionOutcomeTests ScrollStitchEngineTests ScrollFrameSourceTests ShortcutsTests ScrollCaptureSessionTests AutoScrollDriverTests; do test -f TidyShotTests/$t.swift || echo "NO TEST: $t"; done
for h in SyntheticPage ScrollSessionFakes FakeScrollWorld; do test -f TidyShotTests/Support/$h.swift || echo "NO HELPER: $h"; done
```
Expected: the first command lists 40 added files: the 23 sources of the loop above (Tasks 1, 2, 3, 5 and 6), the 14 test files of the second loop (Tasks 1 to 6; `ShortcutsTests` is Task 4's) and the 3 `Support` helpers (`SyntheticPage` from Task 1, `ScrollSessionFakes` from Task 5, `FakeScrollWorld` from Task 6), and nothing under `project.yml`; no `NOT IN PLAN:` line (every added file is named in a task section; a stray file means a review fix added it, so say which); no `NO FILE:`, `NO TEST:` or `NO HELPER:` line. A listed file that a task section moved or renamed is fixed in this loop, not in the code.

- [ ] **Step 5: Build, run and work through the checklist**

Run:
```bash
xcodebuild -project TidyShot.xcodeproj -scheme TidyShot -configuration Debug -derivedDataPath .build build -quiet && open .build/Build/Products/Debug/TidyShot.app
```
End-to-end first: make the test page from the checklist's setup, open `long-still.html` in Safari at the top, `⌃⇧5`, drag the page area, Start, scroll to the end, Done. Expect one tall PNG in the save folder, the overlay showing the top of the page, and the first-screen `cmp` of the checklist printing `SAME`. Then work through `docs/testing/phase-5-manual-checklist.md`, with Tim at the Mac for the permission, VoiceOver, second display and Chrome items. Write down the observations the checklist asks for (fixed overlays in Safari and Chrome, scrollbar fragments, time at the cap, time from Done to the overlay, natural scrolling, the colour comparison, the editor at the cap, the hover preview) and report which items were run and which were skipped (a 1x display, a second display, Chrome, VoiceOver, an ad-hoc rebuild or Apple Development signing).

Fix nothing in code. A failing item is reported with its section and wording; a failure that follows from a documented limit is recorded for the spec, not fixed.

- [ ] **Step 6: Amend the spec, and mark Phase 5 delivered**

Always amend these four places. The first two follow the planned design and need no observation.

1. The 2.1 row (line 38). Replace the row with:
```markdown
| Scrolling capture | Captures content taller than the screen, any app | P1 (own phase) | Hardest screenshot feature; gets Phase 5, designed in 2.8. Manual mode first (the user scrolls, TidyShot captures and stitches; Screen Recording only), then opt-in auto-scroll that posts scroll-wheel events behind the PostEvent permission (listed as Accessibility in System Settings). Vertical only; horizontal is deferred |
```

2. The 2.4 paragraph (line 86). Replace the whole paragraph with:
```markdown
**Scrolling capture.** Promoted from "extras" to its own phase (see the Scrolling capture row). The user picks an area or a window and TidyShot stitches frames of it by locating the overlap with a row-signature match. The first sketch had the app post scroll-wheel events (`CGEvent`, then thought to need the Accessibility permission as a second first-run flow), stop when two consecutive frames are identical or the user clicks, and add a manual "scroll yourself" mode and horizontal scrolling after vertical worked. Phase 5 reversed that order and changed the permission: manual mode comes first and needs only Screen Recording; auto-scroll is an opt-in layer on the same engine behind the PostEvent permission (`CGPreflightPostEventAccess`, which System Settings lists under Accessibility; no Accessibility API and no entitlement), and it ends after two unchanged screens or when the user clicks Done. Horizontal scrolling is deferred. See 2.8.
```

3. The Phase 5 block of section 6 (lines 700-704). After the "Later: horizontal scrolling." bullet add a blank line and:
```markdown
Delivered <date of this run, YYYY-MM-DD>: manual and auto-scroll on `phase-5-scrolling`. Phase 5 is released when its PR merges. Design and what was built: 2.8.
```
Write the real date (`date +%F`), not the placeholder.

4. Section 2.8, five places:
   - In the "Scope and order" paragraph, change `both are amended in the last task` to `both were amended on delivery`.
   - Rewrite the risk bullet that starts `*Auto-scroll delivery is unverified*` (line 573) to the settled result of Tim's delivery checks with the real grant (Task 6, Steps 9 and 11, and this checklist): when events were delivered, `*Auto-scroll delivery (verified <date>).* Posted wheel events reached <app list> after the grant (Task 6's probe, TidyShot itself, and the checklist); …` and drop the "If it fails, Phase 5 ships manual mode only and the checkbox stays hidden" clause; when they were not, say what was seen, and that auto-scroll stays off with the checkbox off and disabled and `Auto-scroll is unavailable: macOS did not deliver TidyShot's scroll events.` under it (not hidden), manual mode unaffected; report that to the controller before committing. Also change the sentence in "Feasibility under the App Sandbox" (`Delivery after a grant is not yet verified on this Mac; the first auto-scroll task starts with that check`) to the verified result in one sentence.
   - In "Settling and the end", after "A `.lost` halves the next step down to 40 pt;", add that the driver first scrolls back by the step that lost the place, so the smaller step starts from overlap with the last accepted frame. In the same paragraph, after the sentence on reversing the direction once, add: "When the first step of a session shows `.still` (at the top of a page in an app that inverts synthetic deltas, the step pushes against the top), the driver tries the other direction once, as a fresh first step, before the end detector counts any still." Both are Task 6's driver decisions, tested in `AutoScrollDriverTests` (`shrinksThenHandsOverAfterThreeLosses`, `triesTheOtherDirectionWhenTheFirstStepIsStill`, `aPageThatNeverMovesEndsAfterTryingBothDirections`).
   - In "Session model" or "Frame source", add one sentence each where they belong: `stop()` sends no `.stopped` and still delivers a buffered frame, so Done awaits it and drains the events before finishing; the source puts back a frame an idle would push out; the session stamps each frame with its clock (frames carry no time); a stream that stops without an error gives the reason `The screen recording stream stopped.`.
   - After the Decisions list, as the last paragraph of 2.8, add `**Phase 5 (built).**` followed by one line each for: every place where the build differs from the text above (a constant, a name, a string, a size or a behaviour, found by Step 1 and the checklist run), the observations Step 5 wrote down (what Safari and Chrome do with fixed overlays and the overlay scrollbar, time at the cap and from Done to the overlay, natural scrolling, the stitched-versus-one-shot comparison, how the editor behaves at 16,384 px, the hover preview), the real test count and the checklist's name. When the build matches 2.8 everywhere, the paragraph says so in one line and still gives the observations. Where a sentence of 2.8 is simply wrong after the build (a number, a name, a string), rewrite that sentence in place as well, as 4b did for 2.6.

Compare at least these against the code and rewrite 2.8 where they differ: the constants of Step 1; the ten status strings and the notification strings; the panel size, gap and height range; the preview width (360 px) and update rate (4 a second); the end delay (0.4 s); the step plan (50 pt events, 10 ms apart, half the area first, 0.6 of the band later, 40 pt floor); the pointer poll rate (20 a second); the shortcut names and defaults; the thumbnail crop (3 times, `width * 3 / 2`); the file list in "Architecture". For a divergence that looks like a bug rather than a decision (the code contradicts a sentence of 2.8 that was the intended behaviour), stop and report it; do not amend 2.8 to match a bug. Record every amendment as one line in the report.

Check the result:
```bash
grep -n "Delivered\|Phase 5 (built)" docs/superpowers/specs/2026-10-19-tidyshot-screenshot-design.md
grep -n "not yet verified\|is unverified\|amended in the last task" docs/superpowers/specs/2026-10-19-tidyshot-screenshot-design.md
```
Expected: the `Delivered` line in section 6 and the `Phase 5 (built)` paragraph in 2.8; no output from the second command.

- [ ] **Step 7: Commit**

```bash
git add docs/testing/phase-5-manual-checklist.md README.md docs/superpowers/specs/2026-10-19-tidyshot-screenshot-design.md
git add docs/superpowers/plans/2026-10-21-phase-5-scrolling-capture.md
git commit -m "docs: Phase 5 checklist and README"
```
The plan is in the list so that a Step 4 correction lands in this commit; when the table is unchanged, `git add` leaves it out. Check `git status` is clean afterwards.

- [ ] **Step 8: Stop here**

Phase 5 is done when the last test run reads `Test run with 565 tests in 72 suites passed` and the checklist passes. Do not push and do not open a PR: the controller pushes and opens the PR after the whole-branch review. Report the final test line, which checklist items were run (and which were skipped), every checklist, README or 2.8 sentence changed in Step 1 or Step 5 to follow the code, the observations Step 5 recorded, and every amendment made in Step 4 or Step 6.
