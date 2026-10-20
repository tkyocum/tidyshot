# TidyShot Phase 3: Recent Captures Gallery, Upload-Only Mode and Key Templates Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the text "Recent Captures" submenu with a thumbnail gallery that copies, retries and deletes captures (object in the bucket included), add a Delete action to the Quick Access overlay that cancels an in-flight upload first, add an "Upload only, keep no local file" after-capture action, turn the object key into a template that shares one token engine with the file-name template, and add a Forget Credentials button.

**Architecture:** A pure `TemplateExpander` parses `{token}` templates and expands them in a file-name or an object-key style; `FileNamer` and a rewritten `ObjectKeyNamer` both use it, and `S3DestinationConfig` migrates its Phase 2 prefix and random length into a `keyTemplate` when it decodes. `CaptureRecord` gains an optional thumbnail file name, an optional local file, a temporary-file flag and the capture counter, and decodes Phase 2 history files with defaults. `ThumbnailMaker` (CoreGraphics at capture time, ImageIO for files on disk) writes 320 px PNGs into a `ThumbnailStore` next to `history.json`; a `PendingFileStore` next to it holds upload-only PNGs until they are uploaded. `UploadQueue` gains `cancel(recordID:)` and a `.cancelled` terminal event. `AppCoordinator.deleteCapture` is the one delete path (cancel, DELETE Object, local file, thumbnail, record) used by the overlay and by a new `GalleryWindowController`, which hosts a SwiftUI `GalleryView` (a `LazyVGrid` plus a preview pane) over an `@Observable GalleryModel` and a `ThumbnailProvider` that generates thumbnails lazily for records from before this phase.

**Tech Stack:** Swift 6 language mode with default `MainActor` isolation, SwiftUI (`LazyVGrid`, `ContentUnavailableView`, `.contextMenu`, `.onHover`), AppKit (`NSWindow` subclass with `NSHostingController`, `NSAlert`, file URLs on `NSPasteboard`), CoreGraphics and ImageIO (`CGImageSourceCreateThumbnailAtIndex`), `gethostname(2)`, Swift Testing, XcodeGen 2.46.

Spec: `docs/superpowers/specs/2026-10-19-tidyshot-screenshot-design.md`, sections 2.4 (all five paragraphs except blur and scrolling), 3, 5, 6 (Phase 3) and 7 (decision 3 as amended).

Builds on Phase 2 (`docs/superpowers/plans/2026-10-19-phase-2-s3-upload.md`), which is on `main` (PR 2); `main` is at `ba394f1`. Create the branch and confirm:

```bash
git checkout -b phase-3-gallery main
git merge-base --is-ancestor ba394f1 HEAD && echo PHASE2_PRESENT
```
Expected: `Switched to a new branch 'phase-3-gallery'` then `PHASE2_PRESENT`.

## Global Constraints

- Minimum macOS `26.0`. Xcode 27.1, macOS 27.0 SDK. Everything from the Phase 0, 1 and 2 constraints still applies.
- App Sandbox on, no new entitlements. Thumbnails and upload-only files live inside the container next to `history.json`: `~/Library/Application Support/TidyShot/thumbnails/<record id>.png` and `~/Library/Application Support/TidyShot/pending/<record id>.png`. Files in the user's save folder are still reached only through the security-scoped bookmark (`SaveLocation.read(contentsOf:)` and the new `SaveLocation.remove(at:)`).
- Swift 6 language mode, `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, `SWIFT_APPROACHABLE_CONCURRENCY = YES`. Everything the upload actor or a detached task touches is `nonisolated` and `Sendable`: `TemplateContext`, `TemplateExpander`, `HostName`, `ObjectKeyNamer`, `ThumbnailMaker`, `ThumbnailStore`, `PendingFileStore`, `CaptureDeletion`, and `ImageEncoder` (which becomes `nonisolated`).
- One token set for file names and object keys: `{date}` (yyyy-MM-dd), `{year}`, `{month}`, `{day}`, `{time}`, `{datetime}`, `{hostname}`, `{app}`, `{counter}`, `{random}` (6 characters) and `{random:N}` (N clamped to 1...64). File-name style keeps Phase 1 output: `{time}` is `HH.mm.ss`, `{datetime}` is `yyyy-MM-dd HH.mm.ss`. Object-key style: `{time}` is `HH-mm-ss`, `{datetime}` is `yyyy-MM-dd_HH-mm-ss`, and every token value is reduced to `[A-Za-z0-9._-]` (`Google Chrome` becomes `Google-Chrome`). Unknown or unterminated `{...}` text stays literal.
- Object key template: default `{random:6}`, so a fresh install produces `aSIS7x.png` exactly as Phase 2 did. Literal text between tokens is limited to `[A-Za-z0-9._-/]`; `/` makes folders; leading, trailing and doubled slashes are folded; a folder that is only dots is rejected; an unknown token is rejected; `.png` is appended by the namer. HEAD-before-PUT stays, 5 attempts. The Upload tab shows a warning when the template has neither `{random}` nor `{counter}`. A stored Phase 2 `S3DestinationConfig` (keys `keyPrefix` and `keyLength`) decodes to `<prefix>/{random:<length>}`; the Phase 2 keys are never written again.
- `{hostname}` comes from `gethostname(2)`: lowercased, a trailing `.local` removed, normalised to `[a-z0-9.-]`, `mac` when empty (`Tims-MacBook-Pro.local` becomes `tims-macbook-pro`). Never `Host`/`NSHost` (marked `API_TO_BE_DEPRECATED` in the macOS 27 SDK) and never `ProcessInfo.processInfo.hostName` (can block on DNS).
- Thumbnails are PNG, longest side 320 px, never upscaled, alpha kept (window captures have transparent rounded corners). Generated at capture time from the `CGImage`; for a record without one, the gallery generates it from the local file the first time the record is shown and updates the record; a record with neither shows a placeholder. The gallery's hover preview is decoded from the local file at up to 1200 px on a detached task and falls back to the thumbnail.
- Upload-only mode writes `pending/<record id>.png`, never prompts for a save folder, does not set `lastCaptureURL`, deletes the file on `.uploaded` (the record then has `fileURL == nil` and `fileIsTemporary == false`), and keeps it on failure for retry. Without a configured destination the capture is still written there, recorded as failed with "No upload destination is configured.", and the image goes on the clipboard.
- Delete is one path, `AppCoordinator.deleteCapture(recordID:)`, for the overlay and the gallery: one `NSAlert` confirmation whose text names what will be removed; then cancel an in-flight upload, `DELETE` every object key that may hold the capture, remove the local file (save folder through the bookmark, or the pending folder), remove the thumbnail, remove the record, close the overlay if it shows the record. A failed `DELETE` keeps the record and posts a "Not deleted" notification so it can be tried again. A local file that is already gone is not an error.
- `UploadQueue.cancel(recordID:) async -> CancelResult` returns `.notFound` or `.stopped(reservedKey:)` and returns only after the job's single terminal event, `.cancelled(id:)`, has been delivered; `.failed` never follows `.cancelled`; later jobs continue.
- Retention pruning now also deletes the thumbnails and pending files of pruned records through `HistoryStore.didPrune`; files in the save folder are never touched.
- Tests use Swift Testing, run with `xcodebuild test`. Baseline is `Test run with 105 tests in 17 suites passed`; the plan ends at `153 tests in 24 suites`. Phase 1 and 2 tests stay green throughout (FileNamerTests gains a `hostname:` argument in its helper and one test; ObjectKeyNamerTests is rewritten for templates).
- No GPL-licensed code may be read or copied. Commit after every task with a conventional commit message. Never include a Claude Code session URL in a commit or PR. Do not push or open a PR until the last step of Task 8.

## Build and test commands used throughout

```bash
# regenerate the project after any project.yml change or after adding files
xcodegen generate
```

```bash
# build (exit code 0 on success)
xcodebuild -project TidyShot.xcodeproj -scheme TidyShot -configuration Debug -derivedDataPath .build build -quiet
```

```bash
# run all unit tests; the summary line is the last "Test run with N tests in M suites" line
xcodebuild -project TidyShot.xcodeproj -scheme TidyShot -destination 'platform=macOS' -derivedDataPath .build test 2>&1 | grep -E "error:|warning: .*TidyShot/|Test run|✘"
```

```bash
# launch the built app
open .build/Build/Products/Debug/TidyShot.app
```

XcodeGen only sees files that exist when it runs. Every task that creates a Swift file runs `xcodegen generate` before building; a "cannot find 'X' in scope" error for a type you just wrote means the project was not regenerated. The test output always contains two `History file could not be read or decoded` log lines (from the corrupt-file tests) and some `com.apple.linkd.autoShortcut` noise; neither is a failure.

Code signing note: this Mac has ad-hoc signing (`CODE_SIGN_IDENTITY = -`), so Screen Recording must be re-granted after each rebuild and the keychain may ask "TidyShot wants to use your confidential information" once per build (click Always Allow). A rebuilt app shares the container of the previous build, so `history.json`, `thumbnails/` and `pending/` carry over between runs, which is what the migration checks in Task 7 rely on.

## File structure

```
TidyShot/
  App/
    AppCoordinator.swift                     modified (Tasks 2, 4, 5), replaced (Task 6), modified (Task 7): thumbnails, upload-only, delete, gallery
    MenuContent.swift                        modified (Task 2), replaced (Task 7): "Recent Captures…" opens the gallery
  Gallery/                                   new
    ThumbnailProvider.swift                  thumbnails and previews for the gallery, lazy generation for old records
    GalleryModel.swift                       @Observable: records, hovered id, preview image
    GalleryView.swift                        GalleryActions, GalleryView, GalleryCell, GalleryStatusBadge, GalleryMenuItems, GalleryPreviewPane
    GalleryWindowController.swift            GalleryWindowController, GalleryWindow (Escape and ⌘W close)
  History/
    CaptureRecord.swift                      replaced: optional fileURL, fileIsTemporary, thumbnailFileName, counter, migration decode
    HistoryStore.swift                       modified: didPrune hook
    ThumbnailStore.swift                     new: thumbnails/ folder next to history.json
    CaptureDeletion.swift                    new: which keys to DELETE, confirmation text (pure)
  Output/
    TemplateExpander.swift                   new: TemplateContext, TemplateExpander (pure)
    HostName.swift                           new: gethostname wrapper
    FileNamer.swift                          replaced: thin wrapper over TemplateExpander
    ThumbnailMaker.swift                     new: 320 px thumbnails via CoreGraphics and ImageIO
    PendingFileStore.swift                   new: pending/ folder for upload-only captures
    ImageEncoder.swift                       modified: nonisolated
    Pasteboard.swift                         modified: copy(fileURL:)
    SaveLocation.swift                       modified: remove(at:)
  Overlay/
    QuickAccessModel.swift                   replaced: onDelete
    QuickAccessController.swift              replaced: Actions.delete, close(recordID:)
    QuickAccessView.swift                    modified (Task 2), replaced (Task 6): trash button, optional file name
  Settings/
    AppSettings.swift                        modified: AfterCaptureAction.uploadOnly
    GeneralSettingsView.swift                modified: upload-only caption
    UploadSettingsView.swift                 replaced (Task 4): key template field, warning; modified (Task 8): Forget Credentials
  Upload/
    ObjectKeyNamer.swift                     replaced: template based
    S3DestinationConfig.swift                replaced: keyTemplate with migration of keyPrefix and keyLength
    Destination.swift                        modified: UploadJob.naming, UploadEvent.cancelled
    UploadQueue.swift                        modified (Task 4), replaced (Task 5): cancel(recordID:)
    ConnectionTester.swift                   modified: probe goes into the template's folder
TidyShotTests/
  TemplateExpanderTests.swift                new
  CaptureRecordTests.swift                   new
  ThumbnailMakerTests.swift                  new
  ThumbnailStoreTests.swift                  new
  PendingFileStoreTests.swift                new
  CaptureDeletionTests.swift                 new
  ThumbnailProviderTests.swift               new
  ObjectKeyNamerTests.swift                  rewritten
  FileNamerTests.swift                       modified
  HistoryStoreTests.swift                    modified
  UploadQueueTests.swift                     modified
  S3DestinationConfigTests.swift             modified
  ConnectionTesterTests.swift                modified
  AppSettingsTests.swift                     modified
docs/testing/phase-3-manual-checklist.md     new
README.md                                    modified
```

## Design decisions made while planning

- **Gallery window:** an `NSWindow` subclass hosted through `NSHostingController` and owned by a small controller, the pattern `PermissionWindowController` already uses, not a SwiftUI `Window` scene. The coordinator opens it from AppKit code, an `LSUIElement` app has to call `NSApplication.activate(ignoringOtherApps: true)` for the window to come to the front, and Escape and ⌘W need `NSWindow` overrides because a menu bar agent has no main menu to supply a Close item.
- **Hover preview:** a fixed preview pane to the right of the grid that shows the hovered capture at up to 1200 px with its details and action buttons. A SwiftUI `.popover` driven by `.onHover` dismisses as soon as the mouse moves towards it and flickers between cells. The pane keeps the last hovered capture when the mouse leaves a cell and shows the newest capture when nothing has been hovered.
- **Click behaviour:** click copies the public URL for an uploaded capture, and puts the local file on the pasteboard (as a file URL, so Finder pastes a copy and Slack attaches it) for one that was never uploaded.
- **Thumbnail format:** PNG. A JPEG would turn the transparent rounded corners of window captures black.
- **Two thumbnail paths:** at capture time the `CGImage` is already decoded, so `ThumbnailMaker.thumbnail(from: CGImage)` draws into a `CGContext` (exact size from `targetSize(for:maxSide:)`); for files on disk `CGImageSourceCreateThumbnailAtIndex` with `kCGImageSourceThumbnailMaxPixelSize` is used, which never upscales. Both give `320 × 200` for a `640 × 400` source (verified).
- **Capture counter on the record:** `{counter}` is drawn once per capture, used for the file name and the object key, and stored in `CaptureRecord.counter`, so a retry expands to the same value. A retry also expands `{date}` from the record's timestamp, not the retry time, so folders stay stable.
- **Connection test probe:** goes into the folder the key template produces right now (for `shots/{year}/{month}/{random}` that is `shots/2026/10/tidyshot-probe-XXXXXXXX.txt`), so a bucket policy scoped to a folder is tested too.
- **Cancellation:** `UploadQueue` runs each job in its own `Task` so `cancel` can cancel it; URLSession's async methods and `Task.sleep` throw on cancellation, the catch block emits `.cancelled` when the id is in `cancelledIDs`, and `cancel` awaits the task so the event has been delivered before it returns. The reserved key is reported because the PUT may have completed server-side in the same instant; the delete flow deletes it (a 404 is a success for `S3Destination.delete`).
- **Pruning cleans up:** `HistoryStore.didPrune` reports the records dropped by retention; the coordinator removes their thumbnails and pending files. There is no startup sweep of the folders, because an empty history (for example after a corrupt file was set aside) would then delete pending captures that were never uploaded.

---

### Task 1: Shared template engine, hostname token, and FileNamer on top of it (TDD)

**Files:**
- Create: `TidyShot/Output/TemplateExpander.swift`
- Create: `TidyShot/Output/HostName.swift`
- Modify: `TidyShot/Output/FileNamer.swift` (full replacement below)
- Create: `TidyShotTests/TemplateExpanderTests.swift`
- Modify: `TidyShotTests/FileNamerTests.swift` (two edits below)

**Interfaces:**
- Consumes: `FileNamer.randomString(length:)` (Phase 1).
- Produces:
  - `nonisolated struct TemplateContext: Sendable, Equatable { var date: Date; var appName: String?; var counter: Int; var hostname: String }` with `init(date: Date = Date(), appName: String? = nil, counter: Int = 0, hostname: String = HostName.local())`.
  - `nonisolated struct TemplateExpander: Sendable` with `enum Style { case fileName, objectKey }`, `enum Token: Equatable, Sendable { case date, year, month, day, time, datetime, hostname, app, counter; case random(length: Int); init?(name: String) }`, `enum Segment: Equatable, Sendable { case literal(String); case token(Token) }`, `static let tokenList: String`, `static let defaultRandomLength = 6`, `static let randomLengthRange = 1...64`, `init(randomString: @escaping @Sendable (Int) -> String = FileNamer.randomString)`, `static func parse(_ template: String) -> [Segment]`, `static func hasCollisionGuard(_ template: String) -> Bool`, `func expand(_ template: String, context: TemplateContext, style: Style) -> String`, `static func format(_ date: Date, _ pattern: String) -> String`, `static let keySafeCharacters: Set<Character>`, `static func keySafe(_ value: String) -> String`, `static func normalizeHostname(_ raw: String) -> String`.
  - `nonisolated enum HostName { static func local() -> String }`.
  - `struct FileNamer` keeps `name(appName:counter:)`, `sanitize`, `randomString`, `uniqueURL`; its init becomes `init(template: String = FileNamer.defaultTemplate, now: @escaping () -> Date = { Date() }, randomString: @escaping @Sendable (Int) -> String = FileNamer.randomString, hostname: String = HostName.local())`. `FileNamer.format` moves to `TemplateExpander.format` (nothing else called it).

- [ ] **Step 1: Write the failing tests**

`TidyShotTests/TemplateExpanderTests.swift`:
```swift
import Foundation
import Testing
@testable import TidyShot

struct TemplateExpanderTests {
    /// 2026-10-19 11:56:03 in the current time zone, matching what DateFormatter will print.
    let fixedDate = DateComponents(calendar: .current, year: 2026, month: 10, day: 19, hour: 11, minute: 56, second: 3).date!
    let expander = TemplateExpander(randomString: { String(repeating: "X", count: $0) })

    func context(app: String? = "Safari", counter: Int = 7) -> TemplateContext {
        TemplateContext(date: fixedDate, appName: app, counter: counter, hostname: "miffle")
    }

    @Test func parsesLiteralsAndTokens() {
        #expect(TemplateExpander.parse("shots/{year}/{random:8}")
                == [.literal("shots/"), .token(.year), .literal("/"), .token(.random(length: 8))])
    }

    @Test func unknownAndUnterminatedBracesStayLiteral() {
        #expect(TemplateExpander.parse("{foo}-{date") == [.literal("{foo}-{date")])
        #expect(TemplateExpander.parse("{{date}") == [.literal("{"), .token(.date)])
        #expect(TemplateExpander.parse("") == [])
    }

    @Test func randomLengthDefaultsAndClamps() {
        #expect(TemplateExpander.parse("{random}") == [.token(.random(length: 6))])
        #expect(TemplateExpander.parse("{random:0}") == [.token(.random(length: 1))])
        #expect(TemplateExpander.parse("{random:999}") == [.token(.random(length: 64))])
        #expect(TemplateExpander.parse("{random:x}") == [.literal("{random:x}")])
    }

    @Test func dateTokens() {
        #expect(expander.expand("{date}|{year}|{month}|{day}", context: context(), style: .objectKey)
                == "2026-10-19|2026|10|19")
    }

    @Test func timeAndDatetimeDifferByStyle() {
        #expect(expander.expand("{time}", context: context(), style: .fileName) == "11.56.03")
        #expect(expander.expand("{time}", context: context(), style: .objectKey) == "11-56-03")
        #expect(expander.expand("{datetime}", context: context(), style: .fileName) == "2026-10-19 11.56.03")
        #expect(expander.expand("{datetime}", context: context(), style: .objectKey) == "2026-10-19_11-56-03")
    }

    @Test func appHostnameCounterAndRandom() {
        #expect(expander.expand("{app}/{hostname}-{counter}-{random:3}", context: context(), style: .objectKey)
                == "Safari/miffle-7-XXX")
        #expect(expander.expand("{app}", context: context(app: nil), style: .fileName) == "Screen")
    }

    @Test func objectKeyStyleSanitisesTokenValuesOnly() {
        let chrome = context(app: "Google Chrome (Beta)")
        #expect(expander.expand("{app}", context: chrome, style: .fileName) == "Google Chrome (Beta)")
        #expect(expander.expand("{app}", context: chrome, style: .objectKey) == "Google-Chrome-Beta")
        // Literal text is the template author's business; the key namer validates it.
        #expect(expander.expand("a b/{counter}", context: chrome, style: .objectKey) == "a b/7")
    }

    @Test func hasCollisionGuard() {
        #expect(TemplateExpander.hasCollisionGuard("{random:6}"))
        #expect(TemplateExpander.hasCollisionGuard("shots/{counter}"))
        #expect(!TemplateExpander.hasCollisionGuard("{date}/{hostname}"))
        #expect(!TemplateExpander.hasCollisionGuard("{random"))
    }

    @Test func keySafe() {
        #expect(TemplateExpander.keySafe("Google Chrome") == "Google-Chrome")
        #expect(TemplateExpander.keySafe("..hidden..") == "hidden")
        #expect(TemplateExpander.keySafe("a//b  c") == "a-b-c")
        #expect(TemplateExpander.keySafe("") == "x")
        #expect(TemplateExpander.keySafe("é") == "x")
        #expect(TemplateExpander.keySafe("2026-10-19_11-56-03") == "2026-10-19_11-56-03")
    }

    @Test func normalizeHostname() {
        #expect(TemplateExpander.normalizeHostname("Tims-MacBook-Pro.local") == "tims-macbook-pro")
        #expect(TemplateExpander.normalizeHostname("miffle.alligator-in.ts.net") == "miffle.alligator-in.ts.net")
        #expect(TemplateExpander.normalizeHostname("Tim's Mac\n") == "tim-s-mac")
        #expect(TemplateExpander.normalizeHostname("") == "mac")
        #expect(TemplateExpander.normalizeHostname(".local") == "mac")
    }

    /// Runs inside the sandboxed test host, so this also proves `gethostname` works there.
    @Test func localHostNameIsNonEmptyAndKeySafe() {
        let name = HostName.local()
        #expect(!name.isEmpty)
        #expect(!name.hasSuffix(".local"))
        #expect(name.allSatisfy { $0.isASCII && ($0.isLowercase || $0.isNumber || $0 == "-" || $0 == ".") })
    }
}
```

In `TidyShotTests/FileNamerTests.swift`, make the helper pass a fixed hostname and add one test:

Replace:

```swift
        FileNamer(template: template, now: { fixedDate }, randomString: { String(repeating: "X", count: $0) })
```

with:

```swift
        FileNamer(template: template, now: { fixedDate }, randomString: { String(repeating: "X", count: $0) }, hostname: "miffle")
```

Replace:

```swift
    @Test func sanitizeReplacesPathSeparatorsAndColons() {
```

with:

```swift
    @Test func yearMonthDayAndHostnameTokens() {
        #expect(namer("{year}/{month}/{day} {hostname}").name(appName: nil, counter: 1) == "2026-10-19 miffle")
    }

    @Test func sanitizeReplacesPathSeparatorsAndColons() {
```

- [ ] **Step 2: Run the tests to verify they fail**

Run:
```bash
xcodegen generate && xcodebuild -project TidyShot.xcodeproj -scheme TidyShot -destination 'platform=macOS' -derivedDataPath .build test 2>&1 | grep -E "error:|Test run" | head
```
Expected: compile errors including `cannot find 'TemplateExpander' in scope` and `extra argument 'hostname' in call`.

- [ ] **Step 3: Write the template engine**

`TidyShot/Output/TemplateExpander.swift`:
```swift
import Foundation

/// The values a naming template is expanded against. Built once per capture and stored with the
/// record (timestamp, app name, counter), so a retried upload names its object the same way.
nonisolated struct TemplateContext: Sendable, Equatable {
    var date: Date
    var appName: String?
    var counter: Int
    /// Already normalised (see `TemplateExpander.normalizeHostname`).
    var hostname: String

    init(date: Date = Date(), appName: String? = nil, counter: Int = 0, hostname: String = HostName.local()) {
        self.date = date
        self.appName = appName
        self.counter = counter
        self.hostname = hostname
    }
}

/// The one token engine behind local file names (`FileNamer`) and object keys (`ObjectKeyNamer`).
///
/// Tokens: `{date}` yyyy-MM-dd, `{year}`, `{month}`, `{day}`, `{time}`, `{datetime}`, `{hostname}`,
/// `{app}`, `{counter}`, `{random}` (6 characters) and `{random:N}` (1 to 64). `{time}` and
/// `{datetime}` differ by style: file names use `HH.mm.ss` and a space, object keys use
/// `HH-mm-ss` and an underscore, so a key never contains a space or a dot-separated time.
/// In the object-key style every token value is passed through `keySafe`, so tokens never emit
/// a character outside `[A-Za-z0-9._-]`. Unknown or unterminated `{...}` text is left as literal.
nonisolated struct TemplateExpander: Sendable {
    enum Style: Sendable {
        case fileName
        case objectKey
    }

    enum Token: Equatable, Sendable {
        case date, year, month, day, time, datetime, hostname, app, counter
        case random(length: Int)

        /// `nil` for a name that is not a token.
        init?(name: String) {
            switch name {
            case "date": self = .date
            case "year": self = .year
            case "month": self = .month
            case "day": self = .day
            case "time": self = .time
            case "datetime": self = .datetime
            case "hostname": self = .hostname
            case "app": self = .app
            case "counter": self = .counter
            case "random": self = .random(length: TemplateExpander.defaultRandomLength)
            default:
                guard let match = name.wholeMatch(of: /random:(\d{1,3})/), let requested = Int(match.output.1) else { return nil }
                self = .random(length: min(max(requested, TemplateExpander.randomLengthRange.lowerBound),
                                           TemplateExpander.randomLengthRange.upperBound))
            }
        }
    }

    enum Segment: Equatable, Sendable {
        case literal(String)
        case token(Token)
    }

    /// For settings captions.
    static let tokenList = "{date} {year} {month} {day} {time} {datetime} {hostname} {app} {counter} {random} {random:8}"
    static let defaultRandomLength = 6
    static let randomLengthRange = 1...64

    var randomString: @Sendable (Int) -> String

    init(randomString: @escaping @Sendable (Int) -> String = FileNamer.randomString) {
        self.randomString = randomString
    }

    /// Splits `template` into literal runs and known tokens. `{foo}` and an unterminated `{` are
    /// literals; `{{date}` is a literal `{` followed by the date token.
    static func parse(_ template: String) -> [Segment] {
        var segments: [Segment] = []
        var literal = ""
        var rest = Substring(template)
        while let open = rest.firstIndex(of: "{") {
            literal += rest[..<open]
            let afterOpen = rest.index(after: open)
            guard let close = rest[afterOpen...].firstIndex(of: "}") else {
                literal += rest[open...]
                rest = ""
                break
            }
            let name = String(rest[afterOpen..<close])
            if name.contains("{") {
                literal += "{"
                rest = rest[afterOpen...]
                continue
            }
            if let token = Token(name: name) {
                if !literal.isEmpty {
                    segments.append(.literal(literal))
                    literal = ""
                }
                segments.append(.token(token))
            } else {
                literal += rest[open...close]
            }
            rest = rest[rest.index(after: close)...]
        }
        literal += rest
        if !literal.isEmpty {
            segments.append(.literal(literal))
        }
        return segments
    }

    /// True when `template` contains `{random}`, `{random:N}` or `{counter}`, the tokens that make
    /// two captures in the same second produce different names.
    static func hasCollisionGuard(_ template: String) -> Bool {
        parse(template).contains { segment in
            switch segment {
            case .token(.random), .token(.counter): true
            default: false
            }
        }
    }

    func expand(_ template: String, context: TemplateContext, style: Style) -> String {
        Self.parse(template).map { segment in
            switch segment {
            case .literal(let text): text
            case .token(let token): value(of: token, context: context, style: style)
            }
        }.joined()
    }

    private func value(of token: Token, context: TemplateContext, style: Style) -> String {
        let raw: String
        switch token {
        case .date: raw = Self.format(context.date, "yyyy-MM-dd")
        case .year: raw = Self.format(context.date, "yyyy")
        case .month: raw = Self.format(context.date, "MM")
        case .day: raw = Self.format(context.date, "dd")
        case .time: raw = Self.format(context.date, style == .fileName ? "HH.mm.ss" : "HH-mm-ss")
        case .datetime: raw = Self.format(context.date, style == .fileName ? "yyyy-MM-dd HH.mm.ss" : "yyyy-MM-dd_HH-mm-ss")
        case .hostname: raw = context.hostname
        case .app: raw = context.appName ?? "Screen"
        case .counter: raw = String(context.counter)
        case .random(let length): raw = randomString(length)
        }
        return style == .objectKey ? Self.keySafe(raw) : raw
    }

    static func format(_ date: Date, _ pattern: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = pattern
        return formatter.string(from: date)
    }

    /// Characters a token may emit into an object key (`/` is reserved for literal folders).
    static let keySafeCharacters = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._-")

    /// Maps every run of characters outside `keySafeCharacters` to one `-`, then trims `-` and
    /// `.` from both ends (so a value can never be `.` or `..`). An empty result becomes `x`.
    static func keySafe(_ value: String) -> String {
        var output = ""
        var pendingDash = false
        for character in value {
            if keySafeCharacters.contains(character) {
                if pendingDash, !output.isEmpty { output.append("-") }
                pendingDash = false
                output.append(character)
            } else {
                pendingDash = true
            }
        }
        let trimmed = output.trimmingCharacters(in: CharacterSet(charactersIn: "-."))
        return trimmed.isEmpty ? "x" : trimmed
    }

    /// `Tims-MacBook-Pro.local` becomes `tims-macbook-pro`: lowercased, a trailing `.local`
    /// removed, anything outside `[a-z0-9.-]` replaced by `-`, ends trimmed. Empty becomes `mac`.
    static func normalizeHostname(_ raw: String) -> String {
        var name = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if name.hasSuffix(".local") {
            name.removeLast(".local".count)
        }
        let safe = keySafe(name)
        return safe == "x" && !name.contains("x") ? "mac" : safe
    }
}
```

- [ ] **Step 4: Write the hostname wrapper**

`TidyShot/Output/HostName.swift`:
```swift
import Darwin
import Foundation

/// The Mac's local host name for the `{hostname}` token: what `gethostname(2)` reports (the
/// Sharing pane's local hostname, for example `Tims-MacBook-Pro.local`), lowercased and without
/// `.local`. A plain syscall, so it never blocks on DNS the way `ProcessInfo.hostName` can, and
/// it works inside the App Sandbox. `Host` (NSHost) is marked for deprecation and is not used.
nonisolated enum HostName {
    static func local() -> String {
        var buffer = [CChar](repeating: 0, count: 256)
        let status = buffer.withUnsafeMutableBufferPointer { gethostname($0.baseAddress, $0.count - 1) }
        guard status == 0 else { return TemplateExpander.normalizeHostname("") }
        let raw = buffer.withUnsafeBufferPointer { String(cString: $0.baseAddress!) }
        return TemplateExpander.normalizeHostname(raw)
    }
}
```

- [ ] **Step 5: Put FileNamer on top of the engine**

`TidyShot/Output/FileNamer.swift` (full replacement; `name(appName:counter:)` output is unchanged for every Phase 1 template):
```swift
import Foundation

/// Expands the local file name template with `TemplateExpander` in the file-name style and
/// sanitises the result for the file system. The extension is not part of the template.
struct FileNamer {
    static let defaultTemplate = "Screenshot {date} at {time}"

    var template: String
    var now: () -> Date
    var randomString: @Sendable (Int) -> String
    var hostname: String

    init(template: String = FileNamer.defaultTemplate,
         now: @escaping () -> Date = { Date() },
         randomString: @escaping @Sendable (Int) -> String = FileNamer.randomString,
         hostname: String = HostName.local()) {
        self.template = template
        self.now = now
        self.randomString = randomString
        self.hostname = hostname
    }

    func name(appName: String?, counter: Int) -> String {
        let context = TemplateContext(date: now(), appName: appName, counter: counter, hostname: hostname)
        let expanded = TemplateExpander(randomString: randomString).expand(template, context: context, style: .fileName)
        let sanitized = Self.sanitize(expanded)
        return sanitized.isEmpty ? "Screenshot" : sanitized
    }

    /// Removes characters that are illegal or awkward in file names.
    static func sanitize(_ input: String) -> String {
        var output = input
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if output.hasPrefix(".") {
            output = "_" + output.dropFirst()
        }
        return output
    }

    /// `nonisolated` so it can be the default for the non-isolated `randomString` closure parameter.
    nonisolated static func randomString(length: Int) -> String {
        let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789")
        return String((0..<length).map { _ in alphabet.randomElement()! })
    }

    /// Returns `baseName.ext` in `directory`, or `baseName 2.ext`, `baseName 3.ext`, ... if taken.
    static func uniqueURL(baseName: String, ext: String, in directory: URL, fileManager: FileManager = .default) -> URL {
        var candidate = directory.appendingPathComponent(baseName).appendingPathExtension(ext)
        var suffix = 2
        while fileManager.fileExists(atPath: candidate.path) {
            candidate = directory.appendingPathComponent("\(baseName) \(suffix)").appendingPathExtension(ext)
            suffix += 1
        }
        return candidate
    }
}
```

- [ ] **Step 6: Run the tests to verify they pass**

Run:
```bash
xcodegen generate && xcodebuild -project TidyShot.xcodeproj -scheme TidyShot -destination 'platform=macOS' -derivedDataPath .build test 2>&1 | grep -E "error:|warning: .*TidyShot/|Test run|✘"
```
Expected: no `error:` or `warning:` lines, and `Test run with 117 tests in 18 suites passed` (105 plus 11 `TemplateExpanderTests` plus 1 in `FileNamerTests`). `localHostNameIsNonEmptyAndKeySafe` runs inside the sandboxed app, so it also proves `gethostname` works there.

- [ ] **Step 7: Commit**

```bash
git add TidyShot/Output/TemplateExpander.swift TidyShot/Output/HostName.swift TidyShot/Output/FileNamer.swift TidyShotTests/TemplateExpanderTests.swift TidyShotTests/FileNamerTests.swift
git commit -m "feat: shared TemplateExpander with year, month, day and hostname tokens"
```

---

### Task 2: Capture records with an optional file, a thumbnail name and the counter; prune hook (TDD)

**Files:**
- Modify: `TidyShot/History/CaptureRecord.swift` (full replacement below)
- Modify: `TidyShot/History/HistoryStore.swift` (two edits below)
- Modify: `TidyShot/App/AppCoordinator.swift` (two edits below, for the optional `fileURL`)
- Modify: `TidyShot/App/MenuContent.swift` (one edit below)
- Modify: `TidyShot/Overlay/QuickAccessView.swift` (one edit, two occurrences)
- Create: `TidyShotTests/CaptureRecordTests.swift`
- Modify: `TidyShotTests/HistoryStoreTests.swift` (one test added)

**Interfaces:**
- Consumes: `HistoryStore` (Phase 2), `TemplateContext` is not needed yet.
- Produces:
  - `CaptureRecord`: `var fileURL: URL?`, `var fileIsTemporary: Bool`, `var thumbnailFileName: String?`, `var counter: Int`, `init(id: UUID = UUID(), timestamp: Date = Date(), fileURL: URL?, fileIsTemporary: Bool = false, thumbnailFileName: String? = nil, pixelWidth: Int, pixelHeight: Int, appName: String?, counter: Int = 0, uploadState: UploadState = .none)`, `var uploadedKey: String?`, `var hasLocalFile: Bool`; `uploadedURL`, `isFailed`, `isUploading` unchanged. A custom `init(from:)` defaults the three new fields for Phase 2 files; encoding is synthesised and always writes them.
  - `HistoryStore`: `@ObservationIgnored var didPrune: (([CaptureRecord]) -> Void)?`, called from `load()` and `add(_:)` with the records that retention dropped.
- Every other `CaptureRecord(...)` call in the app and tests still compiles because `fileURL:` accepts a non-optional `URL` and the new parameters have defaults.

- [ ] **Step 1: Write the failing tests**

`TidyShotTests/CaptureRecordTests.swift`:
```swift
import Foundation
import Testing
@testable import TidyShot

struct CaptureRecordTests {
    let dir: URL

    init() throws {
        dir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    func store() -> HistoryStore {
        HistoryStore(fileURL: dir.appending(path: "history.json"), retentionDays: { 3650 },
                     now: { Date(timeIntervalSince1970: 1_792_411_200) })
    }

    /// A record exactly as Phase 2 wrote it: no thumbnail, no temporary flag, no counter.
    let phase2JSON = """
    [
      {
        "appName" : "Safari",
        "fileURL" : "file:///Users/tim/Desktop/Screenshot%202026-10-19%20at%2011.56.03.png",
        "id" : "0B2E8A4C-1C3D-4E5F-8A9B-0C1D2E3F4A5B",
        "pixelHeight" : 100,
        "pixelWidth" : 200,
        "timestamp" : "2026-10-19T16:56:03.000Z",
        "uploadState" : {
          "uploaded" : {
            "key" : "aSIS7x.png",
            "url" : "https://snap.tky.io/aSIS7x.png"
          }
        }
      }
    ]
    """

    @Test func phase2HistoryFileDecodesWithDefaults() throws {
        try Data(phase2JSON.utf8).write(to: dir.appending(path: "history.json"))
        let history = store()
        history.load()

        let record = try #require(history.record(id: UUID(uuidString: "0B2E8A4C-1C3D-4E5F-8A9B-0C1D2E3F4A5B")!))
        #expect(record.fileURL?.lastPathComponent == "Screenshot 2026-10-19 at 11.56.03.png")
        #expect(record.hasLocalFile)
        #expect(record.fileIsTemporary == false)
        #expect(record.thumbnailFileName == nil)
        #expect(record.counter == 0)
        #expect(record.appName == "Safari")
        #expect(record.uploadedKey == "aSIS7x.png")
        #expect(record.uploadedURL?.absoluteString == "https://snap.tky.io/aSIS7x.png")
    }

    /// Timestamps are stored with millisecond precision, so the fixtures use whole seconds.
    @Test func recordWithoutLocalFileRoundTrips() throws {
        let now = Date(timeIntervalSince1970: 1_792_411_200)
        let uploaded = CaptureRecord(timestamp: now, fileURL: nil, thumbnailFileName: "thumb.png", pixelWidth: 20, pixelHeight: 10,
                                     appName: nil, counter: 12,
                                     uploadState: .uploaded(url: URL(string: "https://snap.tky.io/a.png")!, key: "a.png"))
        let pending = CaptureRecord(timestamp: now.addingTimeInterval(-1), fileURL: dir.appending(path: "pending/x.png"),
                                    fileIsTemporary: true, pixelWidth: 20, pixelHeight: 10, appName: "Notes",
                                    uploadState: .failed(message: "offline"))
        let first = store()
        first.add(uploaded)
        first.add(pending)

        let second = store()
        second.load()
        #expect(second.record(id: uploaded.id) == uploaded)
        #expect(second.record(id: pending.id) == pending)
        #expect(second.record(id: uploaded.id)?.hasLocalFile == false)
        #expect(second.record(id: pending.id)?.fileIsTemporary == true)
    }

    @Test func uploadedKeyIsNilUnlessUploaded() {
        let record = CaptureRecord(fileURL: nil, pixelWidth: 1, pixelHeight: 1, appName: nil, uploadState: .failed(message: "x"))
        #expect(record.uploadedKey == nil)
        #expect(record.uploadedURL == nil)
        #expect(record.isFailed)
    }
}
```

In `TidyShotTests/HistoryStoreTests.swift`, add a test before `missingFileLoadsEmpty`:

Replace:

```swift
    @Test func missingFileLoadsEmpty() {
```

with:

```swift
    @Test func didPruneReportsDroppedRecordsOnAddAndLoad() {
        let first = store(retentionDays: 30)
        var pruned: [[UUID]] = []
        first.didPrune = { pruned.append($0.map(\.id)) }
        let old = record(age: 31 * 86_400)
        first.add(old)
        #expect(pruned == [[old.id]])
        first.add(record(age: 29 * 86_400))
        #expect(pruned == [[old.id]])

        let second = store(retentionDays: 7)
        var prunedOnLoad: [UUID] = []
        second.didPrune = { prunedOnLoad = $0.map(\.id) }
        second.load()
        #expect(prunedOnLoad.count == 1)
        #expect(second.records.isEmpty)
    }

    @Test func missingFileLoadsEmpty() {
```

- [ ] **Step 2: Run the tests to verify they fail**

Run:
```bash
xcodegen generate && xcodebuild -project TidyShot.xcodeproj -scheme TidyShot -destination 'platform=macOS' -derivedDataPath .build test 2>&1 | grep -E "error:|Test run" | head
```
Expected: compile errors including `extra argument 'thumbnailFileName' in call` and `value of type 'HistoryStore' has no member 'didPrune'`.

- [ ] **Step 3: Replace CaptureRecord**

`TidyShot/History/CaptureRecord.swift`:
```swift
import Foundation

/// One capture: where its PNG is (if it still exists), its thumbnail, how big it is, and how
/// its upload went.
nonisolated struct CaptureRecord: Codable, Identifiable, Equatable, Sendable {
    enum UploadState: Codable, Equatable, Sendable {
        case none
        case uploading(fraction: Double)
        case uploaded(url: URL, key: String)
        case failed(message: String)
    }

    let id: UUID
    let timestamp: Date
    /// The PNG on disk. Nil once an upload-only capture has been uploaded and its temporary
    /// file removed; such a record has only its thumbnail and URL.
    var fileURL: URL?
    /// True while `fileURL` points into the app container's `pending` folder (upload-only mode).
    /// Such a file is deleted after a successful upload; a file in the user's save folder is kept.
    var fileIsTemporary: Bool
    /// File name inside the `thumbnails` folder next to `history.json`. Nil for records written
    /// before thumbnails existed; the gallery generates one from the local file when it can.
    var thumbnailFileName: String?
    var pixelWidth: Int
    var pixelHeight: Int
    var appName: String?
    /// The `{counter}` value drawn at capture time, reused when the upload is retried so the
    /// object key does not change. 0 for records from before key templates.
    var counter: Int
    var uploadState: UploadState

    init(id: UUID = UUID(), timestamp: Date = Date(), fileURL: URL?, fileIsTemporary: Bool = false,
         thumbnailFileName: String? = nil, pixelWidth: Int, pixelHeight: Int, appName: String?,
         counter: Int = 0, uploadState: UploadState = .none) {
        self.id = id
        self.timestamp = timestamp
        self.fileURL = fileURL
        self.fileIsTemporary = fileIsTemporary
        self.thumbnailFileName = thumbnailFileName
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.appName = appName
        self.counter = counter
        self.uploadState = uploadState
    }

    private enum CodingKeys: String, CodingKey {
        case id, timestamp, fileURL, fileIsTemporary, thumbnailFileName, pixelWidth, pixelHeight, appName, counter, uploadState
    }

    /// Phase 2 history files have no `fileIsTemporary`, `thumbnailFileName` or `counter`, and
    /// always have a `fileURL`; they decode with the defaults. Encoding is synthesised.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        timestamp = try container.decode(Date.self, forKey: .timestamp)
        fileURL = try container.decodeIfPresent(URL.self, forKey: .fileURL)
        fileIsTemporary = try container.decodeIfPresent(Bool.self, forKey: .fileIsTemporary) ?? false
        thumbnailFileName = try container.decodeIfPresent(String.self, forKey: .thumbnailFileName)
        pixelWidth = try container.decode(Int.self, forKey: .pixelWidth)
        pixelHeight = try container.decode(Int.self, forKey: .pixelHeight)
        appName = try container.decodeIfPresent(String.self, forKey: .appName)
        counter = try container.decodeIfPresent(Int.self, forKey: .counter) ?? 0
        uploadState = try container.decode(UploadState.self, forKey: .uploadState)
    }

    var uploadedURL: URL? {
        if case .uploaded(let url, _) = uploadState { return url }
        return nil
    }

    /// The object key in the bucket, once uploaded.
    var uploadedKey: String? {
        if case .uploaded(_, let key) = uploadState { return key }
        return nil
    }

    var hasLocalFile: Bool { fileURL != nil }

    var isFailed: Bool {
        if case .failed = uploadState { return true }
        return false
    }

    var isUploading: Bool {
        if case .uploading = uploadState { return true }
        return false
    }
}
```

- [ ] **Step 4: Add the prune hook to HistoryStore**

In `TidyShot/History/HistoryStore.swift`:

Replace:

```swift
    private(set) var records: [CaptureRecord] = []

    @ObservationIgnored let fileURL: URL
```

with:

```swift
    private(set) var records: [CaptureRecord] = []

    /// Called with the records dropped by retention on `load()` and `add(_:)`, so their
    /// thumbnails and temporary files can be removed. Files in the user's save folder are never
    /// touched.
    @ObservationIgnored var didPrune: (([CaptureRecord]) -> Void)?
    @ObservationIgnored let fileURL: URL
```

Replace:

```swift
        records = Self.sortedNewestFirst(Self.pruned(loaded, retentionDays: retentionDays(), now: now()))
        if interrupted { save() }
    }

    func add(_ record: CaptureRecord) {
        records.insert(record, at: 0)
        records = Self.sortedNewestFirst(Self.pruned(records, retentionDays: retentionDays(), now: now()))
        save()
    }
```

with:

```swift
        records = Self.sortedNewestFirst(prune(loaded))
        if interrupted { save() }
    }

    func add(_ record: CaptureRecord) {
        records.insert(record, at: 0)
        records = Self.sortedNewestFirst(prune(records))
        save()
    }

    /// Drops expired records and reports them through `didPrune`.
    private func prune(_ input: [CaptureRecord]) -> [CaptureRecord] {
        let kept = Self.pruned(input, retentionDays: retentionDays(), now: now())
        if kept.count != input.count, let didPrune {
            let keptIDs = Set(kept.map(\.id))
            didPrune(input.filter { !keptIDs.contains($0.id) })
        }
        return kept
    }
```

- [ ] **Step 5: Fix the three call sites that assumed a non-optional file**

In `TidyShot/App/AppCoordinator.swift` (inside `retry(recordID:destination:)` and `reveal(recordID:)`):

Replace:

```swift
        guard let record = history.record(id: recordID) else { return }
        do {
            let data = try saveLocation.read(contentsOf: record.fileURL)
            startUpload(recordID: recordID, data: data, destination: destination)
        } catch {
            markFailed(recordID, message: UploadError.fileUnreadable(record.fileURL.lastPathComponent).localizedDescription)
        }
```

with:

```swift
        guard let record = history.record(id: recordID) else { return }
        guard let fileURL = record.fileURL else {
            markFailed(recordID, message: UploadError.fileUnreadable("no local file").localizedDescription)
            return
        }
        do {
            let data = try saveLocation.read(contentsOf: fileURL)
            startUpload(recordID: recordID, data: data, destination: destination)
        } catch {
            markFailed(recordID, message: UploadError.fileUnreadable(fileURL.lastPathComponent).localizedDescription)
        }
```

Replace:

```swift
        guard let record = history.record(id: recordID) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([record.fileURL])
```

with:

```swift
        guard let fileURL = history.record(id: recordID)?.fileURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([fileURL])
```

In `TidyShot/App/MenuContent.swift` (inside `title(for:)`):

Replace:

```swift
        let name = record.uploadedURL?.lastPathComponent ?? record.fileURL.lastPathComponent
```

with:

```swift
        let name = record.uploadedURL?.lastPathComponent ?? record.fileURL?.lastPathComponent ?? "Upload only"
```

In `TidyShot/Overlay/QuickAccessView.swift` (inside `status`, the `.uploading` and `.none` cases):

Replace (both occurrences):

```swift
            Text(model.record.fileURL.lastPathComponent)
```

with:

```swift
            Text(model.record.fileURL?.lastPathComponent ?? "Upload only")
```

- [ ] **Step 6: Run the tests to verify they pass**

Run:
```bash
xcodebuild -project TidyShot.xcodeproj -scheme TidyShot -destination 'platform=macOS' -derivedDataPath .build test 2>&1 | grep -E "error:|warning: .*TidyShot/|Test run|✘"
```
Expected: no `error:` or `warning:` lines, and `Test run with 121 tests in 19 suites passed`. If `phase2HistoryFileDecodesWithDefaults` fails on `fileURL`, the Phase 2 encoder wrote URLs differently from the fixture; check with `cat ~/Library/Containers/io.tky.tidyshot/Data/Library/Application\ Support/TidyShot/history.json` and copy one real record into the fixture (the fixture's `fileURL` is a plain string because that is how `JSONEncoder` writes `URL` values; it decoded correctly when this plan was verified).

- [ ] **Step 7: Commit**

```bash
git add TidyShot/History/CaptureRecord.swift TidyShot/History/HistoryStore.swift TidyShot/App/AppCoordinator.swift TidyShot/App/MenuContent.swift TidyShot/Overlay/QuickAccessView.swift TidyShotTests/CaptureRecordTests.swift TidyShotTests/HistoryStoreTests.swift
git commit -m "feat: capture records with optional local file, thumbnail name and counter; prune hook"
```

---

### Task 3: Thumbnail maker, thumbnail store and pending file store (TDD)

**Files:**
- Create: `TidyShot/Output/ThumbnailMaker.swift`
- Create: `TidyShot/History/ThumbnailStore.swift`
- Create: `TidyShot/Output/PendingFileStore.swift`
- Modify: `TidyShot/Output/ImageEncoder.swift` (one word)
- Create: `TidyShotTests/ThumbnailMakerTests.swift`
- Create: `TidyShotTests/ThumbnailStoreTests.swift`
- Create: `TidyShotTests/PendingFileStoreTests.swift`

**Interfaces:**
- Consumes: `ImageEncoder.pngData(from:scale:)` (Phase 1).
- Produces:
  - `nonisolated enum ThumbnailMaker` with `static let maxSide = 320`, `static let previewMaxSide = 1200`, `static func targetSize(for pixelSize: CGSize, maxSide: Int) -> CGSize`, `static func thumbnail(from image: CGImage, maxSide: Int = maxSide) -> CGImage?`, `static func thumbnail(contentsOf url: URL, maxSide: Int = maxSide) -> CGImage?`, `static func thumbnail(fromPNGData data: Data, maxSide: Int = maxSide) -> CGImage?`, `static func thumbnail(from source: CGImageSource, maxSide: Int) -> CGImage?`, `static func pngData(_ image: CGImage) throws -> Data`.
  - `nonisolated struct ThumbnailStore: Sendable { static let directoryName = "thumbnails"; let directory: URL; init(directory: URL); init(nextTo historyFileURL: URL); func fileName(for id: UUID) -> String; func url(forFileName name: String) -> URL; func write(_ png: Data, id: UUID) throws -> String; func remove(fileName: String); @discardableResult func removeOrphans(keeping names: Set<String>) -> Int }`.
  - `nonisolated struct PendingFileStore: Sendable { static let directoryName = "pending"; let directory: URL; init(directory: URL); init(nextTo historyFileURL: URL); func write(_ data: Data, id: UUID, ext: String) throws -> URL; func contains(_ url: URL) -> Bool; func remove(_ url: URL); @discardableResult func removeOrphans(keeping urls: Set<URL>) -> Int }`.
  - `ImageEncoder` becomes `nonisolated enum ImageEncoder` so `ThumbnailMaker` and detached tasks can call it.

- [ ] **Step 1: Write the failing tests**

`TidyShotTests/ThumbnailMakerTests.swift`:
```swift
import CoreGraphics
import Foundation
import Testing
@testable import TidyShot

struct ThumbnailMakerTests {
    /// Opaque red with a transparent top-left quarter, so alpha handling is visible.
    func makeImage(width: Int, height: Int) -> CGImage {
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.clear(CGRect(x: 0, y: height / 2, width: width / 2, height: height / 2))
        return context.makeImage()!
    }

    @Test func targetSizeFitsTheLongestSide() {
        #expect(ThumbnailMaker.targetSize(for: CGSize(width: 2880, height: 1800), maxSide: 320) == CGSize(width: 320, height: 200))
        #expect(ThumbnailMaker.targetSize(for: CGSize(width: 400, height: 640), maxSide: 320) == CGSize(width: 200, height: 320))
        #expect(ThumbnailMaker.targetSize(for: CGSize(width: 1000, height: 999), maxSide: 320) == CGSize(width: 320, height: 320))
    }

    @Test func targetSizeNeverUpscalesOrReachesZero() {
        #expect(ThumbnailMaker.targetSize(for: CGSize(width: 100, height: 50), maxSide: 320) == CGSize(width: 100, height: 50))
        #expect(ThumbnailMaker.targetSize(for: CGSize(width: 320, height: 320), maxSide: 320) == CGSize(width: 320, height: 320))
        #expect(ThumbnailMaker.targetSize(for: CGSize(width: 5000, height: 1), maxSide: 320) == CGSize(width: 320, height: 1))
    }

    @Test func thumbnailFromImageKeepsAspectAndAlpha() throws {
        let thumbnail = try #require(ThumbnailMaker.thumbnail(from: makeImage(width: 640, height: 400)))
        #expect(thumbnail.width == 320)
        #expect(thumbnail.height == 200)
        #expect(thumbnail.alphaInfo != .none && thumbnail.alphaInfo != .noneSkipLast && thumbnail.alphaInfo != .noneSkipFirst)

        let small = try #require(ThumbnailMaker.thumbnail(from: makeImage(width: 100, height: 50)))
        #expect(small.width == 100)
        #expect(small.height == 50)
    }

    @Test func thumbnailFromPNGDataMatchesImageIOBounds() throws {
        let wide = try ImageEncoder.pngData(from: makeImage(width: 640, height: 400), scale: 2)
        let thumbnail = try #require(ThumbnailMaker.thumbnail(fromPNGData: wide))
        #expect(thumbnail.width == 320)
        #expect(thumbnail.height == 200)

        let tall = try ImageEncoder.pngData(from: makeImage(width: 400, height: 640), scale: 1)
        let tallThumbnail = try #require(ThumbnailMaker.thumbnail(fromPNGData: tall))
        #expect(tallThumbnail.width == 200)
        #expect(tallThumbnail.height == 320)

        let small = try ImageEncoder.pngData(from: makeImage(width: 100, height: 50), scale: 1)
        let smallThumbnail = try #require(ThumbnailMaker.thumbnail(fromPNGData: small))
        #expect(smallThumbnail.width == 100)
        #expect(smallThumbnail.height == 50)

        #expect(ThumbnailMaker.thumbnail(fromPNGData: Data("not a png".utf8)) == nil)
    }

    @Test func thumbnailFromFileAndPNGRoundTrip() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appending(path: "shot.png")
        try ImageEncoder.pngData(from: makeImage(width: 1280, height: 800), scale: 2).write(to: file)

        let thumbnail = try #require(ThumbnailMaker.thumbnail(contentsOf: file, maxSide: 160))
        #expect(thumbnail.width == 160)
        #expect(thumbnail.height == 100)

        let png = try ThumbnailMaker.pngData(thumbnail)
        #expect(Array(png.prefix(8)) == [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        let reread = try #require(ThumbnailMaker.thumbnail(fromPNGData: png, maxSide: 1000))
        #expect(reread.width == 160)
        #expect(ThumbnailMaker.thumbnail(contentsOf: dir.appending(path: "missing.png")) == nil)
    }
}
```

`TidyShotTests/ThumbnailStoreTests.swift`:
```swift
import Foundation
import Testing
@testable import TidyShot

struct ThumbnailStoreTests {
    let dir: URL

    init() {
        dir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    }

    @Test func storeSitsNextToHistoryFile() {
        let store = ThumbnailStore(nextTo: dir.appending(path: "TidyShot/history.json"))
        #expect(store.directory.path(percentEncoded: false) == dir.appending(path: "TidyShot/thumbnails").path(percentEncoded: false) + "/")
    }

    @Test func writeCreatesFolderAndReturnsFileName() throws {
        let store = ThumbnailStore(directory: dir.appending(path: "thumbnails"))
        defer { try? FileManager.default.removeItem(at: dir) }
        let id = UUID()
        let name = try store.write(Data([1, 2, 3]), id: id)
        #expect(name == "\(id.uuidString).png")
        #expect(try Data(contentsOf: store.url(forFileName: name)) == Data([1, 2, 3]))

        store.remove(fileName: name)
        #expect(!FileManager.default.fileExists(atPath: store.url(forFileName: name).path(percentEncoded: false)))
        store.remove(fileName: name)
    }

    @Test func removeOrphansKeepsNamedFiles() throws {
        let store = ThumbnailStore(directory: dir.appending(path: "thumbnails"))
        defer { try? FileManager.default.removeItem(at: dir) }
        #expect(store.removeOrphans(keeping: []) == 0)

        let keep = try store.write(Data([1]), id: UUID())
        let orphanA = try store.write(Data([2]), id: UUID())
        let orphanB = try store.write(Data([3]), id: UUID())
        #expect(store.removeOrphans(keeping: [keep]) == 2)

        let remaining = try FileManager.default.contentsOfDirectory(atPath: store.directory.path(percentEncoded: false))
        #expect(remaining == [keep])
        #expect(!remaining.contains(orphanA) && !remaining.contains(orphanB))
    }
}
```

`TidyShotTests/PendingFileStoreTests.swift`:
```swift
import Foundation
import Testing
@testable import TidyShot

struct PendingFileStoreTests {
    let dir: URL

    init() {
        dir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    }

    @Test func writePutsTheFileInsideTheFolder() throws {
        let store = PendingFileStore(nextTo: dir.appending(path: "history.json"))
        defer { try? FileManager.default.removeItem(at: dir) }
        let id = UUID()
        let url = try store.write(Data("png".utf8), id: id, ext: "png")
        #expect(url.lastPathComponent == "\(id.uuidString).png")
        #expect(store.contains(url))
        #expect(!store.contains(dir.appending(path: "elsewhere.png")))
        #expect(try Data(contentsOf: url) == Data("png".utf8))

        store.remove(url)
        #expect(!FileManager.default.fileExists(atPath: url.path(percentEncoded: false)))
        store.remove(url)
    }

    @Test func removeOrphansKeepsReferencedFiles() throws {
        let store = PendingFileStore(directory: dir.appending(path: "pending"))
        defer { try? FileManager.default.removeItem(at: dir) }
        #expect(store.removeOrphans(keeping: []) == 0)

        let keep = try store.write(Data([1]), id: UUID(), ext: "png")
        _ = try store.write(Data([2]), id: UUID(), ext: "png")
        #expect(store.removeOrphans(keeping: [keep]) == 1)
        #expect(try FileManager.default.contentsOfDirectory(atPath: store.directory.path(percentEncoded: false)) == [keep.lastPathComponent])
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run:
```bash
xcodegen generate && xcodebuild -project TidyShot.xcodeproj -scheme TidyShot -destination 'platform=macOS' -derivedDataPath .build test 2>&1 | grep -E "error:|Test run" | head
```
Expected: compile errors including `cannot find 'ThumbnailMaker' in scope`, `cannot find 'ThumbnailStore' in scope`, `cannot find 'PendingFileStore' in scope`.

- [ ] **Step 3: Make ImageEncoder callable off the main actor**

In `TidyShot/Output/ImageEncoder.swift`:

Replace:

```swift
enum ImageEncoder {
```

with:

```swift
nonisolated enum ImageEncoder {
```

- [ ] **Step 4: Write ThumbnailMaker**

`TidyShot/Output/ThumbnailMaker.swift`:
```swift
import CoreGraphics
import Foundation
import ImageIO

/// Small previews of captures: longest side `maxSide` pixels (320 by default), aspect ratio kept,
/// never upscaled, alpha kept (window captures have transparent rounded corners, so PNG, not JPEG).
nonisolated enum ThumbnailMaker {
    static let maxSide = 320
    /// For the gallery's hover preview, built from the local file when there is one.
    static let previewMaxSide = 1200

    /// The size that fits `pixelSize` inside a `maxSide` square without upscaling. Sides are
    /// rounded to whole pixels and never below 1.
    static func targetSize(for pixelSize: CGSize, maxSide: Int) -> CGSize {
        let longest = max(pixelSize.width, pixelSize.height)
        let scale = longest > CGFloat(maxSide) ? CGFloat(maxSide) / longest : 1
        return CGSize(width: max(1, (pixelSize.width * scale).rounded()),
                      height: max(1, (pixelSize.height * scale).rounded()))
    }

    /// Draws `image` into a smaller bitmap. Used at capture time, when the CGImage is already in memory.
    static func thumbnail(from image: CGImage, maxSide: Int = maxSide) -> CGImage? {
        let size = targetSize(for: CGSize(width: image.width, height: image.height), maxSide: maxSide)
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8,
                                      bytesPerRow: 0, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(origin: .zero, size: size))
        return context.makeImage()
    }

    /// Decodes a PNG file into a thumbnail through ImageIO. Used for records from before
    /// thumbnails existed and for the gallery's larger preview.
    static func thumbnail(contentsOf url: URL, maxSide: Int = maxSide) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return thumbnail(from: source, maxSide: maxSide)
    }

    static func thumbnail(fromPNGData data: Data, maxSide: Int = maxSide) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return thumbnail(from: source, maxSide: maxSide)
    }

    /// `kCGImageSourceThumbnailMaxPixelSize` bounds the longest side; ImageIO never upscales.
    static func thumbnail(from source: CGImageSource, maxSide: Int) -> CGImage? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxSide,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    /// PNG bytes for a thumbnail. 72 DPI: thumbnails are displayed, never pasted.
    static func pngData(_ image: CGImage) throws -> Data {
        try ImageEncoder.pngData(from: image, scale: 1)
    }
}
```

- [ ] **Step 5: Write the two stores**

`TidyShot/History/ThumbnailStore.swift`:
```swift
import Foundation

/// The `thumbnails` folder next to `history.json`: one PNG per capture, named by record id.
/// Thumbnails belong to the app, so the store may delete them; the user's screenshots never
/// live here.
nonisolated struct ThumbnailStore: Sendable {
    static let directoryName = "thumbnails"

    let directory: URL

    init(directory: URL) {
        self.directory = directory
    }

    /// `thumbnails` in the folder that holds `historyFileURL`.
    init(nextTo historyFileURL: URL) {
        self.init(directory: historyFileURL.deletingLastPathComponent().appending(path: Self.directoryName, directoryHint: .isDirectory))
    }

    func fileName(for id: UUID) -> String {
        id.uuidString + ".png"
    }

    func url(forFileName name: String) -> URL {
        directory.appending(path: name)
    }

    /// Writes `png` for `id` (creating the folder) and returns the file name to store in the record.
    func write(_ png: Data, id: UUID) throws -> String {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let name = fileName(for: id)
        try png.write(to: url(forFileName: name), options: .atomic)
        return name
    }

    /// Removes the thumbnail; a missing file is not an error.
    func remove(fileName: String) {
        try? FileManager.default.removeItem(at: url(forFileName: fileName))
    }

    /// Deletes every file in the folder whose name is not in `keeping` (thumbnails of pruned
    /// records). Returns how many were removed; a missing folder counts as empty.
    @discardableResult
    func removeOrphans(keeping names: Set<String>) -> Int {
        guard let present = try? FileManager.default.contentsOfDirectory(atPath: directory.path(percentEncoded: false)) else { return 0 }
        var removed = 0
        for name in present where !names.contains(name) {
            if (try? FileManager.default.removeItem(at: url(forFileName: name))) != nil {
                removed += 1
            }
        }
        return removed
    }
}
```

`TidyShot/Output/PendingFileStore.swift`:
```swift
import Foundation

/// The `pending` folder next to `history.json`. Upload-only captures are written here instead of
/// the user's save folder (no folder prompt, no security scope) and deleted once uploaded; a
/// failed upload keeps its file here until the retry succeeds or the record is deleted.
nonisolated struct PendingFileStore: Sendable {
    static let directoryName = "pending"

    let directory: URL

    init(directory: URL) {
        self.directory = directory
    }

    /// `pending` in the folder that holds `historyFileURL`.
    init(nextTo historyFileURL: URL) {
        self.init(directory: historyFileURL.deletingLastPathComponent().appending(path: Self.directoryName, directoryHint: .isDirectory))
    }

    /// Writes `data` as `<id>.<ext>` (creating the folder) and returns the file URL.
    func write(_ data: Data, id: UUID, ext: String) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appending(path: "\(id.uuidString).\(ext)")
        try data.write(to: url, options: .atomic)
        return url
    }

    /// True when `url` is a file directly inside this folder.
    func contains(_ url: URL) -> Bool {
        url.deletingLastPathComponent().standardizedFileURL.path(percentEncoded: false)
            == directory.standardizedFileURL.path(percentEncoded: false)
    }

    /// Removes the file; a missing file is not an error.
    func remove(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    /// Deletes every file in the folder that no record in `keeping` points at. Returns how many
    /// were removed; a missing folder counts as empty.
    @discardableResult
    func removeOrphans(keeping urls: Set<URL>) -> Int {
        guard let present = try? FileManager.default.contentsOfDirectory(atPath: directory.path(percentEncoded: false)) else { return 0 }
        let kept = Set(urls.map { $0.standardizedFileURL.path(percentEncoded: false) })
        var removed = 0
        for name in present {
            let url = directory.appending(path: name)
            guard !kept.contains(url.standardizedFileURL.path(percentEncoded: false)) else { continue }
            if (try? FileManager.default.removeItem(at: url)) != nil {
                removed += 1
            }
        }
        return removed
    }
}
```

- [ ] **Step 6: Run the tests to verify they pass**

Run:
```bash
xcodegen generate && xcodebuild -project TidyShot.xcodeproj -scheme TidyShot -destination 'platform=macOS' -derivedDataPath .build test 2>&1 | grep -E "error:|warning: .*TidyShot/|Test run|✘"
```
Expected: no `error:` or `warning:` lines, and `Test run with 131 tests in 22 suites passed` (5 + 3 + 2 new tests in three new suites).

- [ ] **Step 7: Commit**

```bash
git add TidyShot/Output/ThumbnailMaker.swift TidyShot/History/ThumbnailStore.swift TidyShot/Output/PendingFileStore.swift TidyShot/Output/ImageEncoder.swift TidyShotTests/ThumbnailMakerTests.swift TidyShotTests/ThumbnailStoreTests.swift TidyShotTests/PendingFileStoreTests.swift
git commit -m "feat: thumbnail maker, thumbnail store and pending file store"
```

---

### Task 4: Object key templates end to end (TDD)

**Files:**
- Modify: `TidyShot/Upload/ObjectKeyNamer.swift` (full replacement below)
- Modify: `TidyShot/Upload/S3DestinationConfig.swift` (full replacement below)
- Modify: `TidyShot/Upload/Destination.swift` (one edit: `UploadJob.naming`)
- Modify: `TidyShot/Upload/UploadQueue.swift` (two edits)
- Modify: `TidyShot/Upload/ConnectionTester.swift` (two edits)
- Modify: `TidyShot/App/AppCoordinator.swift` (six edits)
- Modify: `TidyShot/Settings/UploadSettingsView.swift` (full replacement below)
- Modify: `TidyShotTests/ObjectKeyNamerTests.swift` (full replacement below)
- Modify: `TidyShotTests/S3DestinationConfigTests.swift`, `TidyShotTests/UploadQueueTests.swift`, `TidyShotTests/ConnectionTesterTests.swift`, `TidyShotTests/AppSettingsTests.swift` (edits below)

**Interfaces:**
- Consumes: `TemplateExpander`, `TemplateContext`, `HostName` (Task 1), `CaptureRecord.counter` (Task 2).
- Produces:
  - `nonisolated struct ObjectKeyNamer: Sendable` with `static let defaultTemplate = "{random:6}"`, `static let literalCharacters: Set<Character>`, `enum TemplateError: LocalizedError, Equatable, Sendable { case empty; case illegalCharacter(Character); case unknownToken(String); case unbalancedBraces; case dotSegment(String) }`, `var template: String`, `var randomString: @Sendable (Int) -> String`, `init(template: String = ObjectKeyNamer.defaultTemplate, randomString: @escaping @Sendable (Int) -> String = FileNamer.randomString)`, `func makeKey(ext: String, context: TemplateContext) -> String`, `static func normalize(_ template: String) -> String`, `static func fold(_ key: String) -> String`, `static func validate(_ template: String) -> TemplateError?`, `static func collisionWarning(for template: String) -> String?`, `static func folder(of key: String) -> String`, `static func migratedTemplate(prefix: String, length: Int) -> String`. The Phase 2 members `prefix`, `length`, `lengthRange`, `defaultLength`, `clamp`, `join`, `normalizePrefix` are gone.
  - `S3DestinationConfig`: `var keyTemplate: String` replaces `keyPrefix` and `keyLength`; `init(endpoint:region:bucket:usePathStyle:sendPublicReadACL:publicURLTemplate:keyTemplate:)` with `keyTemplate` defaulting to `ObjectKeyNamer.defaultTemplate`; `ConfigError.invalidKeyTemplate(String)`; `normalized` folds the template; `validationError` reports an invalid template; custom `init(from:)` migrates `keyPrefix`/`keyLength`.
  - `UploadJob` gains `let naming: TemplateContext` and `init(id:data:contentType:fileExtension:naming: TemplateContext = TemplateContext())`.
  - `UploadQueue` expands the key for every attempt with `keyNamer.makeKey(ext: job.fileExtension, context: job.naming)`.
  - `ConnectionTester.run(destination:session:randomString:)` keeps its signature (`randomString` becomes `@escaping`) and puts the probe into `ObjectKeyNamer.folder(of:)` the template's expansion.
  - `AppCoordinator` draws the counter once per capture, stores it on the record, builds the queue with `ObjectKeyNamer(template: destination.config.keyTemplate)`, and gives every job `TemplateContext(date: record.timestamp, appName: record.appName, counter: record.counter)`.
  - `UploadSettingsView` replaces the prefix field and length stepper with a "Key template" field, a live example, a red validation message, and the orange collision warning.

- [ ] **Step 1: Write the failing tests**

`TidyShotTests/ObjectKeyNamerTests.swift` (full replacement):
```swift
import Foundation
import Testing
@testable import TidyShot

struct ObjectKeyNamerTests {
    let fixedDate = DateComponents(calendar: .current, year: 2026, month: 10, day: 19, hour: 11, minute: 56, second: 3).date!

    func namer(_ template: String = ObjectKeyNamer.defaultTemplate) -> ObjectKeyNamer {
        ObjectKeyNamer(template: template, randomString: { String(repeating: "X", count: $0) })
    }

    func context(app: String? = "Safari", counter: Int = 7) -> TemplateContext {
        TemplateContext(date: fixedDate, appName: app, counter: counter, hostname: "miffle")
    }

    @Test func defaultTemplateIsSixRandomCharactersPlusExtension() {
        #expect(ObjectKeyNamer.defaultTemplate == "{random:6}")
        #expect(namer().makeKey(ext: "png", context: context()) == "XXXXXX.png")
    }

    @Test func literalFoldersAndTokens() {
        #expect(namer("shots/{year}/{month}/{hostname}-{random:8}").makeKey(ext: "png", context: context())
                == "shots/2026/10/miffle-XXXXXXXX.png")
        #expect(namer("{app}/{date}_{time}-{counter}").makeKey(ext: "png", context: context())
                == "Safari/2026-10-19_11-56-03-7.png")
        #expect(namer("{datetime}").makeKey(ext: "txt", context: context()) == "2026-10-19_11-56-03.txt")
    }

    @Test func slashesAreFoldedAndEmptyExpansionFallsBackToRandom() {
        #expect(namer("/a//b/{random:2}/").makeKey(ext: "png", context: context()) == "a/b/XX.png")
        #expect(namer("   ").makeKey(ext: "png", context: context()) == "XXXXXX.png")
        #expect(ObjectKeyNamer.fold("///") == "")
        #expect(ObjectKeyNamer.normalize("  shots/{random}  ") == "shots/{random}")
    }

    @Test func tokenValuesAreKeySafe() {
        #expect(namer("{app}/{random:2}").makeKey(ext: "png", context: context(app: "Google Chrome (Beta)")) == "Google-Chrome-Beta/XX.png")
        #expect(namer("{app}").makeKey(ext: "png", context: context(app: nil)) == "Screen.png")
    }

    @Test func validateAcceptsGoodTemplates() {
        #expect(ObjectKeyNamer.validate("{random:6}") == nil)
        #expect(ObjectKeyNamer.validate("shots/{year}/{month}/{hostname}-{random:8}") == nil)
        #expect(ObjectKeyNamer.validate("a.b_c-d/{date}") == nil)
        #expect(ObjectKeyNamer.validate(" /{counter}/ ") == nil)
    }

    @Test func validateRejectsBadTemplates() {
        #expect(ObjectKeyNamer.validate("") == .empty)
        #expect(ObjectKeyNamer.validate("  /// ") == .empty)
        #expect(ObjectKeyNamer.validate("my shots/{random}") == .illegalCharacter(" "))
        #expect(ObjectKeyNamer.validate("{random}?x") == .illegalCharacter("?"))
        #expect(ObjectKeyNamer.validate("ünïcode") == .illegalCharacter("ü"))
        #expect(ObjectKeyNamer.validate("{foo}") == .unknownToken("foo"))
        #expect(ObjectKeyNamer.validate("{random:x}") == .unknownToken("random:x"))
        #expect(ObjectKeyNamer.validate("{date") == .unbalancedBraces)
        #expect(ObjectKeyNamer.validate("date}") == .unbalancedBraces)
        #expect(ObjectKeyNamer.validate("../{random}") == .dotSegment(".."))
        #expect(ObjectKeyNamer.validate("a/./{random}") == .dotSegment("."))
    }

    @Test func templateErrorsHaveMessages() {
        #expect(ObjectKeyNamer.TemplateError.illegalCharacter(" ").localizedDescription.contains("\" \" is not allowed"))
        #expect(ObjectKeyNamer.TemplateError.unknownToken("foo").localizedDescription.hasPrefix("{foo} is not a token."))
        #expect(ObjectKeyNamer.TemplateError.dotSegment("..").localizedDescription == "A folder cannot be \"..\".")
    }

    @Test func collisionWarningOnlyWithoutRandomOrCounter() {
        #expect(ObjectKeyNamer.collisionWarning(for: "{random:6}") == nil)
        #expect(ObjectKeyNamer.collisionWarning(for: "{date}/{counter}") == nil)
        #expect(ObjectKeyNamer.collisionWarning(for: "{date}/{hostname}")?.hasPrefix("This template has neither {random} nor {counter}.") == true)
    }

    @Test func folderOfKey() {
        #expect(ObjectKeyNamer.folder(of: "shots/2026/10/aB3dE9.png") == "shots/2026/10")
        #expect(ObjectKeyNamer.folder(of: "aB3dE9.png") == "")
    }

    @Test func migratedTemplateFromPhase2Settings() {
        #expect(ObjectKeyNamer.migratedTemplate(prefix: "shots", length: 8) == "shots/{random:8}")
        #expect(ObjectKeyNamer.migratedTemplate(prefix: "", length: 6) == "{random:6}")
        #expect(ObjectKeyNamer.migratedTemplate(prefix: " /a/b/ ", length: 1) == "a/b/{random:4}")
        #expect(ObjectKeyNamer.migratedTemplate(prefix: "p", length: 99) == "p/{random:32}")
    }

    @Test func realKeysUseTheFileNamerAlphabet() {
        let key = ObjectKeyNamer(template: "{random:10}").makeKey(ext: "png", context: context())
        #expect(key.count == 14)
        #expect(key.hasSuffix(".png"))
        #expect(key.dropLast(4).allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber) })
    }
}
```

In `TidyShotTests/S3DestinationConfigTests.swift`:

Replace:

```swift
        padded.keyPrefix = " shots "
        #expect(padded.validationError == nil)

        let clean = padded.normalized
        #expect(clean.bucket == "my-bucket")
        #expect(clean.region == "us-west-2")
        #expect(clean.endpoint == "https://s3.us-west-2.amazonaws.com")
        #expect(clean.keyPrefix == "shots")
```

with:

```swift
        padded.keyTemplate = " /shots//{random}/ "
        #expect(padded.validationError == nil)

        let clean = padded.normalized
        #expect(clean.bucket == "my-bucket")
        #expect(clean.region == "us-west-2")
        #expect(clean.endpoint == "https://s3.us-west-2.amazonaws.com")
        #expect(clean.keyTemplate == "shots/{random}")
```

Replace:

```swift
    @Test func roundTripsThroughJSON() throws {
        let data = try JSONEncoder().encode(aws)
        #expect(try JSONDecoder().decode(S3DestinationConfig.self, from: data) == aws)
    }
```

with:

```swift
    @Test func roundTripsThroughJSON() throws {
        let data = try JSONEncoder().encode(aws)
        #expect(try JSONDecoder().decode(S3DestinationConfig.self, from: data) == aws)
        let json = String(decoding: data, as: UTF8.self)
        #expect(json.contains("\"keyTemplate\""))
        #expect(!json.contains("keyPrefix") && !json.contains("keyLength"))
    }

    /// Phase 2 stored a prefix folder and a random length; both fold into the template.
    @Test func phase2PrefixAndLengthMigrateToTemplate() throws {
        func decode(_ json: String) throws -> S3DestinationConfig {
            try JSONDecoder().decode(S3DestinationConfig.self, from: Data(json.utf8))
        }
        let common = """
        "endpoint":"https://s3.us-west-2.amazonaws.com","region":"us-west-2","bucket":"snap",
        "usePathStyle":false,"sendPublicReadACL":false,"publicURLTemplate":"https://snap.tky.io/{key}"
        """
        #expect(try decode("{\(common),\"keyPrefix\":\"shots\",\"keyLength\":8}").keyTemplate == "shots/{random:8}")
        #expect(try decode("{\(common),\"keyPrefix\":\"\",\"keyLength\":6}").keyTemplate == "{random:6}")
        #expect(try decode("{\(common),\"keyPrefix\":\"/a/b/\",\"keyLength\":99}").keyTemplate == "a/b/{random:32}")
        #expect(try decode("{\(common)}").keyTemplate == "{random:6}")
        #expect(try decode("{\(common),\"keyTemplate\":\"{date}/{random}\",\"keyPrefix\":\"ignored\"}").keyTemplate == "{date}/{random}")
    }

    @Test func invalidKeyTemplateIsAValidationError() {
        var spaced = aws
        spaced.keyTemplate = "my shots/{random}"
        #expect(spaced.validationError == .invalidKeyTemplate(ObjectKeyNamer.TemplateError.illegalCharacter(" ").localizedDescription))
        var unknown = aws
        unknown.keyTemplate = "{foo}"
        #expect(unknown.validationError == .invalidKeyTemplate(ObjectKeyNamer.TemplateError.unknownToken("foo").localizedDescription))
        #expect(!unknown.isComplete)
    }
```

In `TidyShotTests/UploadQueueTests.swift` (the namer is built in five places; the first edit is the `makeQueue` helper, the second covers the other four):

Replace:

```swift
ObjectKeyNamer(prefix: "s", length: 6, randomString:
```

with:

```swift
ObjectKeyNamer(template: "s/{random}", randomString:
```

Replace (all 4 occurrences):

```swift
ObjectKeyNamer(length: 6, randomString:
```

with:

```swift
ObjectKeyNamer(template: "{random}", randomString:
```

Replace:

```swift
    @Test func regeneratesKeyWhenHeadReturns200() async throws {
```

with:

```swift
    @Test func keyUsesTheJobsNamingContext() async throws {
        let destination = FakeDestination()
        let log = EventLog()
        let queue = UploadQueue(destination: destination,
                                keyNamer: ObjectKeyNamer(template: "{app}/{date}/{counter}-{random:2}",
                                                         randomString: { String(repeating: "K", count: $0) }),
                                policy: .immediate, sleep: { _ in }, events: { log.events.append($0) })
        let id = UUID()
        let captured = DateComponents(calendar: .current, year: 2026, month: 10, day: 19, hour: 11, minute: 56, second: 3).date!
        let naming = TemplateContext(date: captured, appName: "Safari", counter: 3, hostname: "miffle")

        await queue.enqueue(UploadJob(id: id, data: data, contentType: "image/png", fileExtension: "png", naming: naming))
        try await eventually { log.events.contains(.uploaded(id: id, url: URL(string: "https://snap.tky.io/Safari/2026-10-19/3-KK.png")!,
                                                              key: "Safari/2026-10-19/3-KK.png")) }
    }

    @Test func regeneratesKeyWhenHeadReturns200() async throws {
```

In `TidyShotTests/ConnectionTesterTests.swift`:

Replace:

```swift
                                     keyPrefix: "p", publicURLTemplate: "https://snap.tky.io/{key}")
```

with:

```swift
                                     publicURLTemplate: "https://snap.tky.io/{key}", keyTemplate: "p/{random:6}")
```

In `TidyShotTests/AppSettingsTests.swift`:

Replace:

```swift
                                         keyPrefix: "p", usePathStyle: true, sendPublicReadACL: true,
                                         publicURLTemplate: "https://snap.tky.io/{key}", keyLength: 8)
```

with:

```swift
                                         usePathStyle: true, sendPublicReadACL: true,
                                         publicURLTemplate: "https://snap.tky.io/{key}", keyTemplate: "p/{random:8}")
```

- [ ] **Step 2: Run the tests to verify they fail**

Run:
```bash
xcodebuild -project TidyShot.xcodeproj -scheme TidyShot -destination 'platform=macOS' -derivedDataPath .build test 2>&1 | grep -E "error:|Test run" | head
```
Expected: compile errors including `extra argument 'template' in call`, `extra argument 'keyTemplate' in call` and `extra argument 'naming' in call`.

- [ ] **Step 3: Replace ObjectKeyNamer**

`TidyShot/Upload/ObjectKeyNamer.swift`:
```swift
import Foundation

/// Builds S3 object keys from a template such as `shots/{year}/{month}/{hostname}-{random:8}`,
/// expanded by `TemplateExpander` in the object-key style and followed by the extension. The
/// default `{random:6}` gives the Phase 2 behaviour: `aSIS7x.png`.
///
/// Keys stay URL-safe: literal text is limited to `[A-Za-z0-9._-/]` (checked by `validate`) and
/// tokens never emit anything outside `[A-Za-z0-9._-]`. `/` separates folders; leading, trailing
/// and doubled slashes are folded away.
nonisolated struct ObjectKeyNamer: Sendable {
    static let defaultTemplate = "{random:6}"
    static let literalCharacters = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._-/")

    enum TemplateError: LocalizedError, Equatable, Sendable {
        case empty
        case illegalCharacter(Character)
        case unknownToken(String)
        case unbalancedBraces
        case dotSegment(String)

        var errorDescription: String? {
            switch self {
            case .empty: "The key template is empty."
            case .illegalCharacter(let character): "\"\(character)\" is not allowed in a key template; use letters, digits, . _ - and / outside tokens."
            case .unknownToken(let name): "{\(name)} is not a token. Tokens: \(TemplateExpander.tokenList)."
            case .unbalancedBraces: "Every { needs a matching }."
            case .dotSegment(let segment): "A folder cannot be \"\(segment)\"."
            }
        }
    }

    var template: String
    var randomString: @Sendable (Int) -> String

    init(template: String = ObjectKeyNamer.defaultTemplate,
         randomString: @escaping @Sendable (Int) -> String = FileNamer.randomString) {
        self.template = template
        self.randomString = randomString
    }

    /// `shots/2026/10/miffle-aB3dE9fG.png`: the template expanded for `context`, folded, plus
    /// `.ext` (`ext` without a dot). A template that expands to nothing falls back to six random
    /// characters so a key is never just `.png`.
    func makeKey(ext: String, context: TemplateContext) -> String {
        let expander = TemplateExpander(randomString: randomString)
        var name = Self.normalize(expander.expand(template, context: context, style: .objectKey))
        if name.isEmpty {
            name = randomString(TemplateExpander.defaultRandomLength)
        }
        return name + "." + ext
    }

    /// Trims whitespace and folds slashes. Saved templates, validation and expanded keys all go
    /// through this.
    static func normalize(_ template: String) -> String {
        fold(template.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// Removes leading, trailing and repeated slashes: `/a//b/` becomes `a/b`.
    static func fold(_ key: String) -> String {
        key.split(separator: "/", omittingEmptySubsequences: true).joined(separator: "/")
    }

    /// The first problem with `template`, or nil when it can be saved.
    static func validate(_ template: String) -> TemplateError? {
        let normalized = normalize(template)
        guard !normalized.isEmpty else { return .empty }
        for case .literal(let text) in TemplateExpander.parse(normalized) {
            if let open = text.firstIndex(of: "{") {
                guard let close = text[open...].firstIndex(of: "}") else { return .unbalancedBraces }
                return .unknownToken(String(text[text.index(after: open)..<close]))
            }
            if text.contains("}") { return .unbalancedBraces }
            if let bad = text.first(where: { !literalCharacters.contains($0) }) { return .illegalCharacter(bad) }
        }
        for segment in normalized.split(separator: "/") where segment.allSatisfy({ $0 == "." }) {
            return .dotSegment(String(segment))
        }
        return nil
    }

    /// Shown in Settings when nothing in the template varies between two captures in the same
    /// second. Nil when the template has `{random}`, `{random:N}` or `{counter}`.
    static func collisionWarning(for template: String) -> String? {
        TemplateExpander.hasCollisionGuard(template)
            ? nil
            : "This template has neither {random} nor {counter}. Two captures in the same second would want the same key; only the check before each upload keeps them apart."
    }

    /// `shots/2026/10` for `shots/2026/10/aB3dE9.png`, empty for a key without folders. The
    /// connection test uses it to put its probe object next to real uploads.
    static func folder(of key: String) -> String {
        guard let slash = key.lastIndex(of: "/") else { return "" }
        return String(key[..<slash])
    }

    /// The Phase 2 settings (optional prefix folder plus random length 4...32) as a template:
    /// prefix `shots` and length 8 become `shots/{random:8}`; no prefix and 6 become `{random:6}`.
    static func migratedTemplate(prefix: String, length: Int) -> String {
        let folder = fold(prefix.trimmingCharacters(in: .whitespacesAndNewlines))
        let name = "{random:\(min(max(length, 4), 32))}"
        return folder.isEmpty ? name : "\(folder)/\(name)"
    }
}
```

- [ ] **Step 4: Replace S3DestinationConfig**

`TidyShot/Upload/S3DestinationConfig.swift`:
```swift
import Foundation

/// Everything about an S3-compatible destination except the credentials. Persisted as JSON in
/// UserDefaults by `AppSettings.s3Config`; credentials live in the Keychain.
nonisolated struct S3DestinationConfig: Codable, Equatable, Sendable {
    /// Service endpoint without the bucket, for example `https://s3.us-west-2.amazonaws.com`,
    /// `https://<account>.r2.cloudflarestorage.com`, `https://s3.us-west-004.backblazeb2.com`,
    /// or `http://localhost:9000`.
    var endpoint: String
    /// `us-west-2`, `auto` (R2), `us-west-004` (B2). MinIO accepts any value.
    var region: String
    var bucket: String
    /// `https://host/bucket/key` instead of `https://bucket.host/key`. Needed for MinIO and for
    /// bucket names containing dots over HTTPS.
    var usePathStyle: Bool
    /// Adds `x-amz-acl: public-read` to every PUT. Off by default; most buckets use a policy or CDN.
    var sendPublicReadACL: Bool
    /// Where the object is readable from, with `{key}` standing for the full object key.
    var publicURLTemplate: String
    /// Object key template, see `ObjectKeyNamer`. Replaces the Phase 2 prefix and random length,
    /// which are migrated on decode.
    var keyTemplate: String

    static let keyToken = "{key}"

    static let empty = S3DestinationConfig(endpoint: "", region: "", bucket: "",
                                           usePathStyle: false, sendPublicReadACL: false,
                                           publicURLTemplate: "", keyTemplate: ObjectKeyNamer.defaultTemplate)

    init(endpoint: String, region: String, bucket: String,
         usePathStyle: Bool = false, sendPublicReadACL: Bool = false,
         publicURLTemplate: String, keyTemplate: String = ObjectKeyNamer.defaultTemplate) {
        self.endpoint = endpoint
        self.region = region
        self.bucket = bucket
        self.usePathStyle = usePathStyle
        self.sendPublicReadACL = sendPublicReadACL
        self.publicURLTemplate = publicURLTemplate
        self.keyTemplate = keyTemplate
    }

    private enum CodingKeys: String, CodingKey {
        case endpoint, region, bucket, usePathStyle, sendPublicReadACL, publicURLTemplate, keyTemplate
    }

    /// Phase 2 stored these instead of `keyTemplate`.
    private enum LegacyCodingKeys: String, CodingKey {
        case keyPrefix, keyLength
    }

    /// A Phase 2 config (prefix and length, no template) decodes to the equivalent template, so
    /// existing uploads keep their folder and name length. Encoding is synthesised and writes
    /// only the current keys.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        endpoint = try container.decode(String.self, forKey: .endpoint)
        region = try container.decode(String.self, forKey: .region)
        bucket = try container.decode(String.self, forKey: .bucket)
        usePathStyle = try container.decode(Bool.self, forKey: .usePathStyle)
        sendPublicReadACL = try container.decode(Bool.self, forKey: .sendPublicReadACL)
        publicURLTemplate = try container.decode(String.self, forKey: .publicURLTemplate)
        if let template = try container.decodeIfPresent(String.self, forKey: .keyTemplate) {
            keyTemplate = template
        } else {
            let legacy = try decoder.container(keyedBy: LegacyCodingKeys.self)
            keyTemplate = ObjectKeyNamer.migratedTemplate(
                prefix: try legacy.decodeIfPresent(String.self, forKey: .keyPrefix) ?? "",
                length: try legacy.decodeIfPresent(Int.self, forKey: .keyLength) ?? TemplateExpander.defaultRandomLength)
        }
    }

    enum ConfigError: LocalizedError, Equatable {
        case invalidEndpoint
        case missingBucket
        case missingRegion
        case invalidPublicURLTemplate
        case invalidKeyTemplate(String)

        var errorDescription: String? {
            switch self {
            case .invalidEndpoint: "Endpoint must be an http or https URL such as https://s3.us-west-2.amazonaws.com."
            case .missingBucket: "Bucket name is required."
            case .missingRegion: "Region is required (use \"auto\" for Cloudflare R2)."
            case .invalidPublicURLTemplate: "Public URL must be an http or https URL containing {key}."
            case .invalidKeyTemplate(let reason): "Key template: \(reason)"
            }
        }
    }

    /// A copy with surrounding whitespace removed from every text field and the key template
    /// folded. Pasted values often carry a trailing space or newline; trimming here means
    /// " my-bucket " is used as "my-bucket" instead of producing a broken host name or signature.
    var normalized: S3DestinationConfig {
        var copy = self
        copy.endpoint = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        copy.region = region.trimmingCharacters(in: .whitespacesAndNewlines)
        copy.bucket = bucket.trimmingCharacters(in: .whitespacesAndNewlines)
        copy.publicURLTemplate = publicURLTemplate.trimmingCharacters(in: .whitespacesAndNewlines)
        copy.keyTemplate = ObjectKeyNamer.normalize(keyTemplate)
        return copy
    }

    /// The first problem with this configuration (after trimming), or nil when it can be used.
    var validationError: ConfigError? {
        let config = normalized
        guard let endpointURL = config.endpointURL, ["http", "https"].contains(endpointURL.scheme ?? ""),
              endpointURL.host() != nil else {
            return .invalidEndpoint
        }
        if config.bucket.isEmpty { return .missingBucket }
        if config.region.isEmpty { return .missingRegion }
        if config.expandTemplate(encodedKey: "probe") == nil { return .invalidPublicURLTemplate }
        if let problem = ObjectKeyNamer.validate(config.keyTemplate) { return .invalidKeyTemplate(problem.localizedDescription) }
        return nil
    }

    var isComplete: Bool { validationError == nil }

    var endpointURL: URL? {
        URL(string: endpoint.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// Path-style is used when the user asked for it or when the bucket name contains a dot.
    /// AWS wildcard certificates (`*.s3.<region>.amazonaws.com`) cover a single label, so a
    /// virtual-host URL such as `snap.tky.io.s3.amazonaws.com` fails TLS; AWS requires path-style
    /// for such buckets over HTTPS, and the other providers accept it.
    var effectivePathStyle: Bool {
        usePathStyle || normalized.bucket.contains(".")
    }

    /// The decoded request path for `key`: `/key` (virtual-host) or `/bucket/key` (path-style).
    func objectPath(for key: String) -> String {
        effectivePathStyle ? "/\(normalized.bucket)/\(key)" : "/\(key)"
    }

    /// The URL the signed request is sent to.
    func objectURL(for key: String) throws -> URL {
        guard let endpointURL, var components = URLComponents(url: endpointURL, resolvingAgainstBaseURL: false),
              let host = components.host, !host.isEmpty else {
            throw ConfigError.invalidEndpoint
        }
        if !effectivePathStyle {
            components.host = "\(normalized.bucket).\(host)"
        }
        components.percentEncodedPath = S3Signer.uriEncode(objectPath(for: key), keepSlash: true)
        components.query = nil
        guard let url = components.url else { throw ConfigError.invalidEndpoint }
        return url
    }

    /// The value for the `host` header that URLSession will send for `objectURL(for:)`:
    /// the host plus `:port` when the endpoint names a port.
    func hostHeader(for url: URL) -> String {
        guard let host = url.host() else { return "" }
        if let port = url.port { return "\(host):\(port)" }
        return host
    }

    /// The public URL for `key`, from `publicURLTemplate`.
    func publicURL(for key: String) throws -> URL {
        guard let url = expandTemplate(encodedKey: S3Signer.uriEncode(key, keepSlash: true)) else {
            throw ConfigError.invalidPublicURLTemplate
        }
        return url
    }

    /// The one template check, shared by `validationError` and `publicURL(for:)`: the trimmed
    /// template with `{key}` replaced, or nil when it has no `{key}` or is not an http(s) URL.
    private func expandTemplate(encodedKey: String) -> URL? {
        let template = normalized.publicURLTemplate
        guard template.contains(Self.keyToken),
              let url = URL(string: template.replacingOccurrences(of: Self.keyToken, with: encodedKey)),
              ["http", "https"].contains(url.scheme ?? "") else {
            return nil
        }
        return url
    }
}
```

- [ ] **Step 5: Give upload jobs a naming context and expand it in the queue**

In `TidyShot/Upload/Destination.swift`:

Replace:

```swift
nonisolated struct UploadJob: Sendable, Identifiable {
    /// Matches the `CaptureRecord.id` this upload belongs to.
    let id: UUID
    let data: Data
    let contentType: String
    /// Without a dot, for example `png`.
    let fileExtension: String
}
```

with:

```swift
nonisolated struct UploadJob: Sendable, Identifiable {
    /// Matches the `CaptureRecord.id` this upload belongs to.
    let id: UUID
    let data: Data
    let contentType: String
    /// Without a dot, for example `png`.
    let fileExtension: String
    /// What the object key template is expanded against (capture time, app, counter, hostname).
    /// The queue expands it afresh for every key attempt, so only `{random}` changes on a collision.
    let naming: TemplateContext

    init(id: UUID, data: Data, contentType: String, fileExtension: String, naming: TemplateContext = TemplateContext()) {
        self.id = id
        self.data = data
        self.contentType = contentType
        self.fileExtension = fileExtension
        self.naming = naming
    }
}
```

In `TidyShot/Upload/UploadQueue.swift`:

Replace:

```swift
                let key = try await reserveKey(ext: job.fileExtension)
```

with:

```swift
                let key = try await reserveKey(ext: job.fileExtension, context: job.naming)
```

Replace:

```swift
    /// Generates keys until HEAD reports one unused.
    private func reserveKey(ext: String) async throws -> String {
        for _ in 0..<Self.maxKeyAttempts {
            let key = keyNamer.makeKey(ext: ext)
```

with:

```swift
    /// Generates keys until HEAD reports one unused.
    private func reserveKey(ext: String, context: TemplateContext) async throws -> String {
        for _ in 0..<Self.maxKeyAttempts {
            let key = keyNamer.makeKey(ext: ext, context: context)
```

In `TidyShot/Upload/ConnectionTester.swift`:

Replace:

```swift
                    randomString: @Sendable (Int) -> String = FileNamer.randomString) async -> ConnectionTestResult {
```

with:

```swift
                    randomString: @escaping @Sendable (Int) -> String = FileNamer.randomString) async -> ConnectionTestResult {
```

Replace:

```swift
        let key = ObjectKeyNamer.join(prefix: destination.config.keyPrefix, name: "tidyshot-probe-\(randomString(8)).txt")
```

with:

```swift
        // The probe goes into the folder real uploads would use right now, so a bucket policy
        // scoped to that folder is tested too.
        let namer = ObjectKeyNamer(template: destination.config.keyTemplate, randomString: randomString)
        let folder = ObjectKeyNamer.folder(of: namer.makeKey(ext: "txt", context: TemplateContext(appName: "TidyShot")))
        let key = (folder.isEmpty ? "" : folder + "/") + "tidyshot-probe-\(randomString(8)).txt"
```

- [ ] **Step 6: Wire the template and the counter through AppCoordinator**

In `TidyShot/App/AppCoordinator.swift`, six edits, listed in the order to apply them (not file order): the queue's namer in `startUpload`, the job it enqueues, the counter in `save`, the signature of `writeFile`, the counter line inside `writeFile` (which moves to `save`), and the record in `save`:

Replace:

```swift
                                keyNamer: ObjectKeyNamer(prefix: config.keyPrefix, length: config.keyLength),
```

with:

```swift
                                keyNamer: ObjectKeyNamer(template: config.keyTemplate),
```

Replace:

```swift
        let job = UploadJob(id: recordID, data: data, contentType: "image/png", fileExtension: "png")
        Task { await queue.enqueue(job) }
```

with:

```swift
        guard let record = history.record(id: recordID) else { return }
        let job = UploadJob(id: recordID, data: data, contentType: "image/png", fileExtension: "png",
                            naming: TemplateContext(date: record.timestamp, appName: record.appName, counter: record.counter))
        Task { await queue.enqueue(job) }
```

Replace:

```swift
        guard let url = await writeFile(png, result: result, appName: appName, alreadyOnClipboard: copyImageNow) else { return }
```

with:

```swift
        // One counter per capture, shared by the file name and the object key.
        let needsCounter = settings.fileNameTemplate.contains("{counter}")
            || destination?.config.keyTemplate.contains("{counter}") == true
        let counter = needsCounter ? settings.nextCounter() : 0
        guard let url = await writeFile(png, result: result, appName: appName, counter: counter, alreadyOnClipboard: copyImageNow) else { return }
```

Replace:

```swift
    private func writeFile(_ png: Data, result: CaptureResult, appName: String?, alreadyOnClipboard: Bool) async -> URL? {
```

with:

```swift
    private func writeFile(_ png: Data, result: CaptureResult, appName: String?, counter: Int, alreadyOnClipboard: Bool) async -> URL? {
```

Replace:

```swift
            let counter = settings.fileNameTemplate.contains("{counter}") ? settings.nextCounter() : 0
            let baseName
```

with:

```swift
            let baseName
```

Replace:

```swift
        let record = CaptureRecord(fileURL: url, pixelWidth: result.image.width, pixelHeight: result.image.height,
                                   appName: appName, uploadState: destination != nil ? .uploading(fraction: 0) : .none)
```

with:

```swift
        let record = CaptureRecord(fileURL: url, pixelWidth: result.image.width, pixelHeight: result.image.height,
                                   appName: appName, counter: counter,
                                   uploadState: destination != nil ? .uploading(fraction: 0) : .none)
```

- [ ] **Step 7: Replace the Upload tab**

`TidyShot/Settings/UploadSettingsView.swift`:
```swift
import SwiftUI

/// Destination fields, credentials (saved to the Keychain), the object key template, and Save
/// and Test Connection.
struct UploadSettingsView: View {
    private let coordinator = AppCoordinator.shared

    @State private var draft = S3DestinationConfig.empty
    @State private var accessKeyID = ""
    @State private var secretAccessKey = ""
    @State private var sessionToken = ""
    /// Set when the stored credentials exist but could not be read; shown under the fields.
    @State private var keychainError: String?
    @State private var statusMessage: String?
    @State private var statusIsError = false
    @State private var isTesting = false

    var body: some View {
        Form {
            Section("Destination") {
                TextField("Endpoint", text: $draft.endpoint, prompt: Text("https://s3.us-west-2.amazonaws.com"))
                TextField("Region", text: $draft.region, prompt: Text("us-west-2, or auto for R2"))
                TextField("Bucket", text: $draft.bucket)
                Toggle("Use path-style URLs (MinIO)", isOn: $draft.usePathStyle)
                Text("Buckets whose name contains a dot always use path-style URLs; the provider's TLS certificate cannot cover them as a subdomain.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Toggle("Send public-read ACL with each upload", isOn: $draft.sendPublicReadACL)
                TextField("Public URL", text: $draft.publicURLTemplate, prompt: Text("https://snap.tky.io/{key}"))
                Text("{key} is replaced with the full object key, including any folders from the key template.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Credentials") {
                TextField("Access key ID", text: $accessKeyID)
                SecureField("Secret access key", text: $secretAccessKey)
                SecureField("Session token (optional)", text: $sessionToken)
                if let keychainError {
                    Text(keychainError)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                }
                Text("Stored in your login keychain, never in preferences. A session token is only needed for temporary credentials.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Object keys") {
                TextField("Key template", text: $draft.keyTemplate, prompt: Text(ObjectKeyNamer.defaultTemplate))
                    .font(.body.monospaced())
                Text("Tokens: \(TemplateExpander.tokenList). Letters, digits, . _ - and / between tokens; / makes folders. The .png extension is added.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let problem = ObjectKeyNamer.validate(draft.keyTemplate) {
                    Text(problem.localizedDescription)
                        .font(.caption)
                        .foregroundStyle(.red)
                } else {
                    Text("Example: \(exampleKey)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let warning = ObjectKeyNamer.collisionWarning(for: draft.keyTemplate) {
                        Label(warning, systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
            }
            Section {
                HStack {
                    Button("Save") { save() }
                        .keyboardShortcut(.defaultAction)
                        .disabled(isTesting)
                    Button("Save and Test Connection") { Task { await test() } }
                        .disabled(isTesting)
                    if isTesting {
                        ProgressView().controlSize(.small)
                    }
                }
                if let statusMessage {
                    Text(statusMessage)
                        .font(.caption)
                        .foregroundStyle(statusIsError ? .red : .secondary)
                        .textSelection(.enabled)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear(perform: load)
    }

    /// The template expanded for a capture of this Mac's frontmost app right now, with `x` for
    /// every random character.
    private var exampleKey: String {
        let context = TemplateContext(appName: NSWorkspace.shared.frontmostApplication?.localizedName ?? "Safari", counter: 42)
        return ObjectKeyNamer(template: draft.keyTemplate, randomString: { String(repeating: "x", count: $0) })
            .makeKey(ext: "png", context: context)
    }

    /// Fills the form. No stored item leaves the credential fields empty; a keychain error is
    /// shown under them so an unreadable item is not mistaken for "never set up".
    private func load() {
        draft = coordinator.settings.s3Config ?? .empty
        do {
            keychainError = nil
            if let credentials = try coordinator.credentialStore.load(account: KeychainCredentialStore.defaultAccount) {
                accessKeyID = credentials.accessKeyID
                secretAccessKey = credentials.secretAccessKey
                sessionToken = credentials.sessionToken ?? ""
            }
        } catch {
            keychainError = "Could not read S3 credentials from the keychain: \(error.localizedDescription)"
        }
    }

    /// Returns false (and shows why) when the form cannot be saved.
    @discardableResult
    private func save() -> Bool {
        if let error = draft.validationError {
            show(error.localizedDescription, isError: true)
            return false
        }
        draft = draft.normalized
        let trimmedID = accessKeyID.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedSecret = secretAccessKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedToken = sessionToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedID.isEmpty, !trimmedSecret.isEmpty else {
            show("Access key ID and secret access key are required.", isError: true)
            return false
        }
        do {
            try coordinator.credentialStore.save(AWSCredentials(accessKeyID: trimmedID, secretAccessKey: trimmedSecret,
                                                                sessionToken: trimmedToken.isEmpty ? nil : trimmedToken),
                                                 account: KeychainCredentialStore.defaultAccount)
        } catch {
            show(error.localizedDescription, isError: true)
            return false
        }
        keychainError = nil
        coordinator.settings.s3Config = draft
        coordinator.destinationDidChange()
        show("Saved.", isError: false)
        return true
    }

    /// Saves the form, then runs the connection test against what was saved.
    private func test() async {
        guard save() else { return }
        guard let destination = coordinator.makeDestination() else {
            show("Saved, but the credentials could not be read back from the keychain. Check the keychain prompt or re-enter them.",
                 isError: true)
            return
        }
        isTesting = true
        defer { isTesting = false }
        let result = await ConnectionTester.run(destination: destination)
        // A leaked probe object is reported on its own line under the outcome.
        let message = [result.summary, result.warning].compactMap { $0 }.joined(separator: "\n")
        show(message, isError: result.outcome != .readable || result.warning != nil)
    }

    private func show(_ message: String, isError: Bool) {
        statusMessage = message
        statusIsError = isError
    }
}
```

- [ ] **Step 8: Run the tests to verify they pass**

Run:
```bash
xcodebuild -project TidyShot.xcodeproj -scheme TidyShot -destination 'platform=macOS' -derivedDataPath .build test 2>&1 | grep -E "error:|warning: .*TidyShot/|Test run|✘"
```
Expected: no `error:` or `warning:` lines, and `Test run with 140 tests in 22 suites passed` (ObjectKeyNamerTests goes from 5 to 11, S3DestinationConfigTests gains 2, UploadQueueTests gains 1).

- [ ] **Step 9: Check the migration against the real preferences**

Run:
```bash
defaults read io.tky.tidyshot s3DestinationConfig | head -c 400; echo
```
Expected: the stored JSON still has `keyPrefix` and `keyLength` (nothing has been rewritten yet). Build and launch, open Settings > Upload: the "Key template" field shows `{random:6}` for an empty prefix and length 6, or `<prefix>/{random:<length>}` otherwise, with an example such as `xxxxxx.png`. Click Save. Run the `defaults read` again. Expected: the JSON now has `keyTemplate` and neither `keyPrefix` nor `keyLength`. Quit the app.

```bash
xcodebuild -project TidyShot.xcodeproj -scheme TidyShot -configuration Debug -derivedDataPath .build build -quiet && open .build/Build/Products/Debug/TidyShot.app
```

- [ ] **Step 10: Commit**

```bash
git add TidyShot/Upload/ObjectKeyNamer.swift TidyShot/Upload/S3DestinationConfig.swift TidyShot/Upload/Destination.swift TidyShot/Upload/UploadQueue.swift TidyShot/Upload/ConnectionTester.swift TidyShot/App/AppCoordinator.swift TidyShot/Settings/UploadSettingsView.swift TidyShotTests/ObjectKeyNamerTests.swift TidyShotTests/S3DestinationConfigTests.swift TidyShotTests/UploadQueueTests.swift TidyShotTests/ConnectionTesterTests.swift TidyShotTests/AppSettingsTests.swift
git commit -m "feat: object key templates with migration of the Phase 2 prefix and length"
```

---

### Task 5: Cancel a pending or in-flight upload (TDD)

**Files:**
- Modify: `TidyShot/Upload/UploadQueue.swift` (full replacement below)
- Modify: `TidyShot/Upload/Destination.swift` (one edit: `UploadEvent.cancelled`)
- Modify: `TidyShot/App/AppCoordinator.swift` (one edit: handle `.cancelled`)
- Modify: `TidyShotTests/UploadQueueTests.swift` (three edits: `FakeDestination` learns to block, five tests added)

**Interfaces:**
- Consumes: `UploadJob.naming` (Task 4).
- Produces:
  - `UploadEvent.cancelled(id: UUID)`: terminal, emitted exactly once for a cancelled job, never followed by `.failed`.
  - `UploadQueue.CancelResult` (`nonisolated enum ... Sendable, Equatable { case notFound; case stopped(reservedKey: String?) }`) and `func cancel(recordID: UUID) async -> CancelResult`, which returns after the `.cancelled` event has been delivered to the handler. `enqueue`, `isIdle`, `init` are unchanged.
  - `AppCoordinator.handle` on `.cancelled`: removes the id from `uploadingIDs`, marks the record `.failed(message: "Upload cancelled.")`, refreshes the overlay, posts no notification (Task 6's delete flow removes the record right after).
  - `FakeDestination.State.blockingUploadsRemaining: Int` (tests): that many uploads sleep for 60 s and throw `CancellationError` when cancelled.

- [ ] **Step 1: Write the failing tests**

In `TidyShotTests/UploadQueueTests.swift`:

Replace:

```swift
        /// Every call to `upload`, including ones that throw.
        var uploadAttempts = 0
    }
```

with:

```swift
        /// Every call to `upload`, including ones that throw.
        var uploadAttempts = 0
        /// This many uploads (after any scripted failures) wait a minute instead of finishing,
        /// so a test can cancel them; the wait throws `CancellationError` when the task is cancelled.
        var blockingUploadsRemaining = 0
    }
```

Replace:

```swift
        if let failure { throw failure }
        progress(0.5)
```

with:

```swift
        if let failure { throw failure }
        let blocks = state.withLock {
            guard $0.blockingUploadsRemaining > 0 else { return false }
            $0.blockingUploadsRemaining -= 1
            return true
        }
        if blocks {
            try await Task.sleep(for: .seconds(60))
        }
        progress(0.5)
```

Replace:

```swift
    @Test func processesJobsInOrderOneAtATime() async throws {
```

with:

```swift
    @Test func cancelInFlightEndsWithASingleCancelledEvent() async throws {
        let destination = FakeDestination(.init(blockingUploadsRemaining: 1))
        let log = EventLog()
        let queue = makeQueue(destination: destination, log: log)
        let id = UUID()

        await queue.enqueue(UploadJob(id: id, data: data, contentType: "image/png", fileExtension: "png"))
        try await eventually { destination.state.withLock { $0.uploadAttempts } == 1 }

        let result = await queue.cancel(recordID: id)
        #expect(result == .stopped(reservedKey: "s/KKKKKK.png"))
        #expect(log.events == [.started(id: id, attempt: 1), .cancelled(id: id)])
        try await eventually { await queue.isIdle }
        #expect(destination.state.withLock { $0.uploads.isEmpty })
        #expect(log.events.count == 2)
    }

    @Test func cancelDropsAPendingJobWithoutUploadingIt() async throws {
        let destination = FakeDestination(.init(blockingUploadsRemaining: 1))
        let log = EventLog()
        let queue = makeQueue(destination: destination, log: log)
        let first = UUID()
        let second = UUID()

        await queue.enqueue(UploadJob(id: first, data: data, contentType: "image/png", fileExtension: "png"))
        await queue.enqueue(UploadJob(id: second, data: data, contentType: "image/png", fileExtension: "png"))
        try await eventually { destination.state.withLock { $0.uploadAttempts } == 1 }

        #expect(await queue.cancel(recordID: second) == .stopped(reservedKey: nil))
        #expect(log.events.contains(.cancelled(id: second)))
        #expect(await queue.cancel(recordID: first) == .stopped(reservedKey: "s/KKKKKK.png"))
        try await eventually { await queue.isIdle }
        #expect(destination.state.withLock { $0.uploadAttempts } == 1)
        #expect(!log.events.contains { if case .started(second, _) = $0 { return true } else { return false } })
    }

    @Test func cancelUnknownIDIsNotFound() async throws {
        let destination = FakeDestination()
        let log = EventLog()
        let queue = makeQueue(destination: destination, log: log)
        #expect(await queue.cancel(recordID: UUID()) == .notFound)
        #expect(log.events.isEmpty)

        let id = UUID()
        await queue.enqueue(UploadJob(id: id, data: data, contentType: "image/png", fileExtension: "png"))
        try await eventually { log.events.contains { if case .uploaded(id, _, _) = $0 { return true } else { return false } } }
        try await eventually { await queue.isIdle }
        #expect(await queue.cancel(recordID: id) == .notFound)
    }

    @Test func cancelDuringBackoffDoesNotRetry() async throws {
        let destination = FakeDestination(.init(failuresRemaining: 1, failure: .httpStatus(503, body: "")))
        let log = EventLog()
        let sleeping = Mutex(false)
        let queue = UploadQueue(destination: destination,
                                keyNamer: ObjectKeyNamer(template: "{random}", randomString: { String(repeating: "K", count: $0) }),
                                policy: .default,
                                sleep: { _ in
                                    sleeping.withLock { $0 = true }
                                    try await Task.sleep(for: .seconds(60))
                                },
                                events: { log.events.append($0) })
        let id = UUID()

        await queue.enqueue(UploadJob(id: id, data: data, contentType: "image/png", fileExtension: "png"))
        try await eventually { sleeping.withLock { $0 } }

        #expect(await queue.cancel(recordID: id) == .stopped(reservedKey: "KKKKKK.png"))
        #expect(log.events == [.started(id: id, attempt: 1), .cancelled(id: id)])
        try await eventually { await queue.isIdle }
        #expect(destination.state.withLock { $0.uploadAttempts } == 1)
    }

    @Test func queueContinuesWithTheNextJobAfterACancel() async throws {
        let destination = FakeDestination(.init(blockingUploadsRemaining: 1))
        let log = EventLog()
        let queue = makeQueue(destination: destination, log: log)
        let first = UUID()
        let second = UUID()

        await queue.enqueue(UploadJob(id: first, data: data, contentType: "image/png", fileExtension: "png"))
        await queue.enqueue(UploadJob(id: second, data: data, contentType: "image/png", fileExtension: "png"))
        try await eventually { destination.state.withLock { $0.uploadAttempts } == 1 }

        _ = await queue.cancel(recordID: first)
        try await eventually { log.events.contains(.uploaded(id: second, url: URL(string: "https://snap.tky.io/s/KKKKKK.png")!, key: "s/KKKKKK.png")) }
        try await eventually { await queue.isIdle }
        #expect(log.events.contains(.cancelled(id: first)))
        #expect(destination.state.withLock { $0.uploads.count } == 1)
    }

    @Test func processesJobsInOrderOneAtATime() async throws {
```

- [ ] **Step 2: Run the tests to verify they fail**

Run:
```bash
xcodebuild -project TidyShot.xcodeproj -scheme TidyShot -destination 'platform=macOS' -derivedDataPath .build test 2>&1 | grep -E "error:|Test run" | head
```
Expected: compile errors including `value of type 'UploadQueue' has no member 'cancel'` and `type 'UploadEvent' has no member 'cancelled'`.

- [ ] **Step 3: Add the event**

In `TidyShot/Upload/Destination.swift`:

Replace:

```swift
    case uploaded(id: UUID, url: URL, key: String)
    case failed(id: UUID, message: String)
}
```

with:

```swift
    case uploaded(id: UUID, url: URL, key: String)
    case failed(id: UUID, message: String)
    /// Terminal, like `.failed`, after `UploadQueue.cancel(recordID:)`. Never followed by `.failed`.
    case cancelled(id: UUID)
}
```

- [ ] **Step 4: Replace UploadQueue**

`TidyShot/Upload/UploadQueue.swift`:
```swift
import Foundation

/// Uploads jobs one at a time, in order, with HEAD-before-PUT key reservation and retry with
/// backoff. Reports progress and results through `events`, which runs on the main actor. A job
/// can be cancelled while pending or in flight; it then ends with a single `.cancelled` event.
actor UploadQueue {
    typealias EventHandler = @MainActor @Sendable (UploadEvent) -> Void
    typealias Sleeper = @Sendable (Duration) async throws -> Void

    /// What `cancel(recordID:)` found.
    nonisolated enum CancelResult: Sendable, Equatable {
        /// Nothing pending or in flight had that id: it already finished (its `.uploaded` or
        /// `.failed` event has been delivered) or was never enqueued.
        case notFound
        /// The job has ended and its `.cancelled` event has been delivered. `reservedKey` is the
        /// object key the job had claimed with HEAD-before-PUT, nil when it was cancelled before
        /// that. The PUT for that key may have completed on the server just as it was cancelled,
        /// so a caller that is deleting the capture deletes this key too.
        case stopped(reservedKey: String?)
    }

    static let maxKeyAttempts = 5

    private let destination: any Destination
    private let keyNamer: ObjectKeyNamer
    private let policy: RetryPolicy
    private let sleep: Sleeper
    private let events: EventHandler
    private var pending: [UploadJob] = []
    private var isDraining = false
    /// The job being processed and the task running it, so `cancel` can stop it and wait for it.
    private var current: (id: UUID, task: Task<Void, Never>)?
    private var cancelledIDs: Set<UUID> = []
    /// Key reserved by the in-flight job, kept after a cancellation for `cancel` to report.
    private var reservedKeys: [UUID: String] = [:]

    init(destination: any Destination,
         keyNamer: ObjectKeyNamer,
         policy: RetryPolicy = .default,
         sleep: @escaping Sleeper = { try await Task.sleep(for: $0) },
         events: @escaping EventHandler) {
        self.destination = destination
        self.keyNamer = keyNamer
        self.policy = policy
        self.sleep = sleep
        self.events = events
    }

    var isIdle: Bool { pending.isEmpty && !isDraining }

    func enqueue(_ job: UploadJob) {
        pending.append(job)
        guard !isDraining else { return }
        isDraining = true
        Task { await drain() }
    }

    /// Stops the job for `recordID`. A pending job is dropped and reports `.cancelled` at once. An
    /// in-flight job has its task cancelled, which makes the HEAD, the PUT, or the backoff sleep
    /// throw; the job then reports `.cancelled` instead of `.failed`, and this call returns once
    /// that event has been delivered. Later jobs continue.
    func cancel(recordID: UUID) async -> CancelResult {
        if let index = pending.firstIndex(where: { $0.id == recordID }) {
            pending.remove(at: index)
            await events(.cancelled(id: recordID))
            return .stopped(reservedKey: nil)
        }
        guard let current, current.id == recordID else { return .notFound }
        cancelledIDs.insert(recordID)
        current.task.cancel()
        await current.task.value
        cancelledIDs.remove(recordID)
        return .stopped(reservedKey: reservedKeys.removeValue(forKey: recordID))
    }

    private func drain() async {
        while !pending.isEmpty {
            let job = pending.removeFirst()
            let task = Task { await process(job) }
            current = (job.id, task)
            await task.value
            current = nil
        }
        isDraining = false
    }

    private func process(_ job: UploadJob) async {
        var attempt = 1
        while true {
            await events(.started(id: job.id, attempt: attempt))
            do {
                let key = try await reserveKey(ext: job.fileExtension, context: job.naming)
                reservedKeys[job.id] = key
                let id = job.id
                let events = events
                try await destination.upload(job.data, key: key, contentType: job.contentType) { fraction in
                    Task { await events(.progress(id: id, fraction: fraction)) }
                }
                let url = try destination.publicURL(for: key)
                reservedKeys[job.id] = nil
                await events(.uploaded(id: job.id, url: url, key: key))
                return
            } catch {
                if cancelledIDs.contains(job.id) {
                    // `reservedKeys` is left for `cancel` to report.
                    await events(.cancelled(id: job.id))
                    return
                }
                if UploadError.isRetryable(error), attempt < policy.maxAttempts {
                    attempt += 1
                    do {
                        try await sleep(policy.delay(beforeAttempt: attempt))
                    } catch {
                        if cancelledIDs.contains(job.id) {
                            await events(.cancelled(id: job.id))
                            return
                        }
                        // A backoff sleep that fails on its own ends the job instead of retrying.
                        reservedKeys[job.id] = nil
                        await events(.failed(id: job.id, message: error.localizedDescription))
                        return
                    }
                    continue
                }
                reservedKeys[job.id] = nil
                await events(.failed(id: job.id, message: error.localizedDescription))
                return
            }
        }
    }

    /// Generates keys until HEAD reports one unused.
    private func reserveKey(ext: String, context: TemplateContext) async throws -> String {
        for _ in 0..<Self.maxKeyAttempts {
            let key = keyNamer.makeKey(ext: ext, context: context)
            if try await destination.exists(key: key) == false {
                return key
            }
        }
        throw UploadError.keyCollisionsExhausted
    }
}
```

- [ ] **Step 5: Handle the event in the coordinator**

In `TidyShot/App/AppCoordinator.swift` (the `switch` in `handle(_:)` is exhaustive, so this is also what makes the app compile again):

Replace:

```swift
        case .failed(let id, let message):
            markFailed(id, message: message)
        }
```

with:

```swift
        case .failed(let id, let message):
            markFailed(id, message: message)
        case .cancelled(let id):
            // Requested by the delete flow, which removes the record next; no notification.
            uploadingIDs.remove(id)
            history.update(id: id) { $0.uploadState = .failed(message: "Upload cancelled.") }
            refreshOverlay(for: id)
        }
```

- [ ] **Step 6: Run the tests to verify they pass**

Run:
```bash
xcodebuild -project TidyShot.xcodeproj -scheme TidyShot -destination 'platform=macOS' -derivedDataPath .build test 2>&1 | grep -E "error:|warning: .*TidyShot/|Test run|✘"
```
Expected: no `error:` or `warning:` lines, and `Test run with 145 tests in 22 suites passed`. The existing `cancelledBackoffEmitsFailedAndStops` still passes: a sleep that throws `CancellationError` without anyone calling `cancel` ends the job with `.failed`, because the id is not in `cancelledIDs`.

- [ ] **Step 7: Commit**

```bash
git add TidyShot/Upload/UploadQueue.swift TidyShot/Upload/Destination.swift TidyShot/App/AppCoordinator.swift TidyShotTests/UploadQueueTests.swift
git commit -m "feat: cancel a pending or in-flight upload with a single cancelled event"
```

---

### Task 6: Upload-only mode, thumbnails at capture, and Delete everywhere (TDD for the pure parts)

**Files:**
- Create: `TidyShot/History/CaptureDeletion.swift`
- Create: `TidyShotTests/CaptureDeletionTests.swift`
- Modify: `TidyShot/Settings/AppSettings.swift` (one edit: `AfterCaptureAction.uploadOnly`)
- Modify: `TidyShot/Settings/GeneralSettingsView.swift` (one edit)
- Modify: `TidyShot/Output/Pasteboard.swift` (one edit: `copy(fileURL:)`)
- Modify: `TidyShot/Output/SaveLocation.swift` (one edit: `remove(at:)`)
- Modify: `TidyShot/Overlay/QuickAccessModel.swift`, `QuickAccessController.swift`, `QuickAccessView.swift` (full replacements below)
- Modify: `TidyShot/App/AppCoordinator.swift` (full replacement below)

**Interfaces:**
- Consumes: `CaptureRecord` fields and `HistoryStore.didPrune` (Task 2), `ThumbnailMaker`, `ThumbnailStore`, `PendingFileStore` (Task 3), `ObjectKeyNamer`, `TemplateContext` (Task 4), `UploadQueue.cancel(recordID:)`, `UploadEvent.cancelled` (Task 5), `S3Destination.delete(key:)` (Phase 2).
- Produces:
  - `AfterCaptureAction.uploadOnly` (title "Upload only, keep no local file", raw value `uploadOnly`) and `var uploads: Bool` (true for `.upload` and `.uploadOnly`).
  - `Pasteboard.copy(fileURL: URL)`.
  - `SaveLocation.remove(at fileURL: URL) throws` (a missing file is not an error; throws `CocoaError(.fileNoSuchFile)` when no folder is set).
  - `nonisolated enum CaptureDeletion { static func objectKeys(for record: CaptureRecord, afterCancel: CaptureRecord?, reservedKey: String?) -> [String]; static func confirmationText(for record: CaptureRecord) -> String }`.
  - `QuickAccessController.Actions` gains `var delete: (UUID) -> Void`; `QuickAccessController.close(recordID:)`; `QuickAccessModel.onDelete`; the view shows a trash button under the X, hides "Reveal in Finder" when the record has no local file, and labels an upload-only capture "Upload only, no local file".
  - `AppCoordinator`: `let thumbnails: ThumbnailStore`, `let pendingFiles: PendingFileStore`, `func readLocalFile(of record: CaptureRecord) throws -> Data`, `func copyLinkOrFile(recordID: UUID)` (replaces `copyURL(recordID:)`), `func deleteCapture(recordID: UUID) async`, `func historyItemSelected(_:)` kept for the menu until Task 7. `save(_:appName:)`, `retryUpload`, `retryFailedUploads`, `reveal`, `makeDestination`, `destinationDidChange` keep their signatures.

Flow of `save` now: encode; `action.uploads` decides whether `makeDestination()` is called (one keychain read); copy the image now under the same three rules as Phase 2; draw one counter if either template contains `{counter}`; write the file (upload-only: `pendingFiles.write`, no prompt, `lastCaptureURL` untouched; otherwise the save folder as before); warn once if upload was wanted but there is no destination (two different messages); shutter sound; make the thumbnail; add the record (`uploading` with a destination, `failed("No upload destination is configured.")` for upload-only without one, `none` otherwise); overlay; enqueue or post the Phase 1 "saved" notification (save mode only). On `.uploaded` of a temporary file the file is removed and the record loses its `fileURL`.

- [ ] **Step 1: Write the failing tests**

`TidyShotTests/CaptureDeletionTests.swift`:
```swift
import Foundation
import Testing
@testable import TidyShot

struct CaptureDeletionTests {
    let url = URL(string: "https://snap.tky.io/aB3dE9.png")!

    func record(state: CaptureRecord.UploadState, fileURL: URL? = URL(fileURLWithPath: "/Users/tim/Desktop/Shot.png"),
                temporary: Bool = false) -> CaptureRecord {
        CaptureRecord(fileURL: fileURL, fileIsTemporary: temporary, pixelWidth: 10, pixelHeight: 10, appName: "Safari", uploadState: state)
    }

    @Test func objectKeysForUploadedCapture() {
        let uploaded = record(state: .uploaded(url: url, key: "aB3dE9.png"))
        #expect(CaptureDeletion.objectKeys(for: uploaded, afterCancel: uploaded, reservedKey: nil) == ["aB3dE9.png"])
    }

    @Test func objectKeysForCancelledUploadIncludeReservedAndLateSuccess() {
        let uploading = record(state: .uploading(fraction: 0.5))
        #expect(CaptureDeletion.objectKeys(for: uploading, afterCancel: uploading, reservedKey: "Qx12Zz.png") == ["Qx12Zz.png"])

        let finishedAnyway = record(state: .uploaded(url: url, key: "aB3dE9.png"))
        #expect(CaptureDeletion.objectKeys(for: uploading, afterCancel: finishedAnyway, reservedKey: "aB3dE9.png") == ["aB3dE9.png"])
        #expect(CaptureDeletion.objectKeys(for: uploading, afterCancel: nil, reservedKey: nil) == [])
    }

    @Test func objectKeysForLocalOnlyCaptureAreEmpty() {
        #expect(CaptureDeletion.objectKeys(for: record(state: .none), afterCancel: nil, reservedKey: nil) == [])
        #expect(CaptureDeletion.objectKeys(for: record(state: .failed(message: "offline")), afterCancel: nil, reservedKey: nil) == [])
    }

    @Test func confirmationTextNamesWhatIsRemoved() {
        #expect(CaptureDeletion.confirmationText(for: record(state: .uploaded(url: url, key: "aB3dE9.png")))
                == "This removes the uploaded object https://snap.tky.io/aB3dE9.png, the file Shot.png, and its entry in Recent Captures. It cannot be undone.")
        #expect(CaptureDeletion.confirmationText(for: record(state: .uploaded(url: url, key: "aB3dE9.png"), fileURL: nil))
                == "This removes the uploaded object https://snap.tky.io/aB3dE9.png and its entry in Recent Captures. It cannot be undone.")
        #expect(CaptureDeletion.confirmationText(for: record(state: .none))
                == "This removes the file Shot.png and its entry in Recent Captures. It cannot be undone.")
        #expect(CaptureDeletion.confirmationText(for: record(state: .uploading(fraction: 0.2), fileURL: URL(fileURLWithPath: "/tmp/p.png"), temporary: true))
                == "This removes the upload in progress, the temporary file, and its entry in Recent Captures. It cannot be undone.")
        #expect(CaptureDeletion.confirmationText(for: record(state: .failed(message: "x"), fileURL: nil))
                == "This removes its entry in Recent Captures. It cannot be undone.")
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run:
```bash
xcodegen generate && xcodebuild -project TidyShot.xcodeproj -scheme TidyShot -destination 'platform=macOS' -derivedDataPath .build test 2>&1 | grep -E "error:|Test run" | head
```
Expected: compile errors containing `cannot find 'CaptureDeletion' in scope`.

- [ ] **Step 3: Write CaptureDeletion**

`TidyShot/History/CaptureDeletion.swift`:
```swift
import Foundation

/// The pure parts of deleting a capture, shared by the overlay and the gallery: which objects to
/// remove from the bucket and what the confirmation says. `AppCoordinator.deleteCapture` does the I/O.
nonisolated enum CaptureDeletion {
    /// Object keys to DELETE, in order and without duplicates: the key the capture is uploaded
    /// under; the key it ended up under if its upload finished while it was being cancelled
    /// (`afterCancel` is the record re-read after `UploadQueue.cancel`); and the key a cancelled
    /// upload had reserved, because its PUT may have completed on the server.
    static func objectKeys(for record: CaptureRecord, afterCancel: CaptureRecord?, reservedKey: String?) -> [String] {
        var keys: [String] = []
        for key in [record.uploadedKey, afterCancel?.uploadedKey, reservedKey].compactMap({ $0 }) where !keys.contains(key) {
            keys.append(key)
        }
        return keys
    }

    /// The informative text of the one confirmation, naming exactly what will be removed.
    static func confirmationText(for record: CaptureRecord) -> String {
        var parts: [String] = []
        if let url = record.uploadedURL {
            parts.append("the uploaded object \(url.absoluteString)")
        } else if record.isUploading {
            parts.append("the upload in progress")
        }
        if let fileURL = record.fileURL {
            parts.append(record.fileIsTemporary ? "the temporary file" : "the file \(fileURL.lastPathComponent)")
        }
        parts.append("its entry in Recent Captures")
        let list: String
        switch parts.count {
        case 1: list = parts[0]
        case 2: list = "\(parts[0]) and \(parts[1])"
        default: list = parts.dropLast().joined(separator: ", ") + ", and " + parts[parts.count - 1]
        }
        return "This removes \(list). It cannot be undone."
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run:
```bash
xcodegen generate && xcodebuild -project TidyShot.xcodeproj -scheme TidyShot -destination 'platform=macOS' -derivedDataPath .build test 2>&1 | grep -E "error:|warning: .*TidyShot/|Test run|✘"
```
Expected: `Test run with 149 tests in 23 suites passed`.

- [ ] **Step 5: Add the after-capture action, the file pasteboard write and the save-folder delete**

In `TidyShot/Settings/AppSettings.swift`:

Replace:

```swift
enum AfterCaptureAction: String, CaseIterable, Identifiable {
    /// Save the file, upload it, and put the URL on the clipboard when the upload finishes.
    case upload
    /// Save the file and copy the image (Phase 1 behaviour).
    case save

    var id: String { rawValue }

    var title: String {
        switch self {
        case .upload: "Upload and copy URL"
        case .save: "Save and copy image"
        }
    }
}
```

with:

```swift
enum AfterCaptureAction: String, CaseIterable, Identifiable {
    /// Save the file, upload it, and put the URL on the clipboard when the upload finishes.
    case upload
    /// Upload from a temporary file inside the app container, copy the URL, and delete the file
    /// once the upload succeeds. No save folder is needed; the gallery keeps a thumbnail.
    case uploadOnly
    /// Save the file and copy the image (Phase 1 behaviour).
    case save

    var id: String { rawValue }

    var title: String {
        switch self {
        case .upload: "Upload and copy URL"
        case .uploadOnly: "Upload only, keep no local file"
        case .save: "Save and copy image"
        }
    }

    var uploads: Bool { self != .save }
}
```

In `TidyShot/Settings/GeneralSettingsView.swift`:

Replace:

```swift
            if settings.afterCaptureAction == .upload {
                Toggle("Also copy image (the URL replaces it when the upload finishes)", isOn: $settings.alsoCopyImageWhenUploading)
            } else {
                Toggle("Copy image to clipboard", isOn: $settings.copyImageToClipboard)
            }
```

with:

```swift
            if settings.afterCaptureAction.uploads {
                Toggle("Also copy image (the URL replaces it when the upload finishes)", isOn: $settings.alsoCopyImageWhenUploading)
            } else {
                Toggle("Copy image to clipboard", isOn: $settings.copyImageToClipboard)
            }
            if settings.afterCaptureAction == .uploadOnly {
                Text("The PNG is kept inside TidyShot only until the upload succeeds. Recent Captures keeps a thumbnail and the URL; a failed upload keeps the file until you retry or delete it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
```

In `TidyShot/Output/Pasteboard.swift`:

Replace:

```swift
    /// Replaces the pasteboard contents with `url`, as plain text and as a URL.
```

with:

```swift
    /// Replaces the pasteboard contents with a file reference, so a paste in Finder copies the
    /// file and a paste in Slack or Mail attaches it.
    static func copy(fileURL: URL) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([fileURL as NSURL])
    }

    /// Replaces the pasteboard contents with `url`, as plain text and as a URL.
```

In `TidyShot/Output/SaveLocation.swift`:

Replace:

```swift
    private func withAccess<T>(to folder: URL, _ body: () throws -> T) rethrows -> T {
```

with:

```swift
    /// Deletes a file inside the save folder, holding security-scoped access. A file that is
    /// already gone is not an error.
    func remove(at fileURL: URL) throws {
        guard let currentURL else { throw CocoaError(.fileNoSuchFile) }
        try withAccess(to: currentURL) {
            do {
                try FileManager.default.removeItem(at: fileURL)
            } catch let error as CocoaError where error.code == .fileNoSuchFile {
                return
            }
        }
    }

    private func withAccess<T>(to folder: URL, _ body: () throws -> T) rethrows -> T {
```

- [ ] **Step 6: Replace the overlay model, controller and view**

`TidyShot/Overlay/QuickAccessModel.swift`:
```swift
import AppKit
import Observation

/// State behind the Quick Access panel: the capture it shows and the actions its buttons run.
@Observable
final class QuickAccessModel {
    var record: CaptureRecord
    var thumbnail: NSImage?
    var isHovered = false

    @ObservationIgnored var onCopy: () -> Void = {}
    @ObservationIgnored var onRetry: () -> Void = {}
    @ObservationIgnored var onReveal: () -> Void = {}
    @ObservationIgnored var onDelete: () -> Void = {}
    @ObservationIgnored var onClose: () -> Void = {}

    init(record: CaptureRecord, thumbnail: NSImage?) {
        self.record = record
        self.thumbnail = thumbnail
    }

    /// True once the upload has finished (or there was none), which starts the auto-close timer.
    var isSettled: Bool {
        !record.isUploading
    }
}
```

`TidyShot/Overlay/QuickAccessController.swift`:
```swift
import AppKit

/// Shows one Quick Access panel for the latest capture, updates it as the upload progresses,
/// and closes it a few seconds after the upload settles (unless the mouse is over it).
final class QuickAccessController {
    struct Actions {
        var copy: (UUID) -> Void
        var retry: (UUID) -> Void
        var reveal: (UUID) -> Void
        /// Deletes the capture everywhere after one confirmation; see `AppCoordinator.deleteCapture`.
        var delete: (UUID) -> Void
    }

    private var panel: QuickAccessPanel?
    private var model: QuickAccessModel?
    private var closeTask: Task<Void, Never>?
    private var autoCloseSeconds: Double = 5

    func show(record: CaptureRecord, thumbnail: NSImage?, corner: OverlayCorner, autoCloseSeconds: Double, actions: Actions) {
        close()
        let model = QuickAccessModel(record: record, thumbnail: thumbnail)
        model.onCopy = { actions.copy(record.id) }
        model.onRetry = { actions.retry(record.id) }
        model.onReveal = { actions.reveal(record.id) }
        model.onDelete = { actions.delete(record.id) }
        model.onClose = { [weak self] in self?.close() }
        self.model = model
        self.autoCloseSeconds = autoCloseSeconds

        let panel = QuickAccessPanel(model: model)
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main ?? NSScreen.screens[0]
        panel.setFrame(OverlayGeometry.frame(size: QuickAccessView.size, corner: corner, in: screen.visibleFrame), display: false)
        panel.orderFrontRegardless()
        self.panel = panel

        if model.isSettled {
            scheduleClose()
        }
    }

    /// Pushes a new record state into the visible panel, if it shows that record.
    func update(record: CaptureRecord) {
        guard let model, model.record.id == record.id else { return }
        model.record = record
        if model.isSettled {
            scheduleClose()
        } else {
            closeTask?.cancel()
            closeTask = nil
        }
    }

    /// Closes the panel if it shows `recordID` (the capture was deleted).
    func close(recordID: UUID) {
        guard model?.record.id == recordID else { return }
        close()
    }

    func close() {
        closeTask?.cancel()
        closeTask = nil
        panel?.orderOut(nil)
        panel = nil
        model = nil
    }

    /// Waits `autoCloseSeconds`; while the mouse is over the panel the countdown restarts.
    private func scheduleClose() {
        closeTask?.cancel()
        let seconds = autoCloseSeconds
        guard seconds > 0 else { return }
        closeTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(seconds))
                guard !Task.isCancelled else { return }
                if self?.model?.isHovered == true { continue }
                break
            }
            guard !Task.isCancelled else { return }
            self?.close()
        }
    }
}
```

`TidyShot/Overlay/QuickAccessView.swift`:
```swift
import SwiftUI

/// Thumbnail, upload status, and copy, retry, delete and close buttons. Hosted in `QuickAccessPanel`.
struct QuickAccessView: View {
    static let size = CGSize(width: 340, height: 104)

    let model: QuickAccessModel

    var body: some View {
        HStack(spacing: 12) {
            thumbnail
            VStack(alignment: .leading, spacing: 6) {
                status
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            VStack(spacing: 10) {
                Button {
                    model.onClose()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Close")
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
        .onHover { model.isHovered = $0 }
    }

    @ViewBuilder
    private var thumbnail: some View {
        let image = Group {
            if let image = model.thumbnail {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                Image(systemName: "photo")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 96, height: 72)
        .background(Color.black.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        if model.record.hasLocalFile {
            image
                .onTapGesture { model.onReveal() }
                .help("Reveal in Finder")
        } else {
            image
        }
    }

    /// The file name, or what stands in for it for an upload-only capture.
    private var fileLabel: String {
        model.record.fileURL?.lastPathComponent ?? "Upload only, no local file"
    }

    @ViewBuilder
    private var status: some View {
        switch model.record.uploadState {
        case .uploading(let fraction):
            HStack(spacing: 8) {
                ProgressView(value: fraction)
                    .progressViewStyle(.circular)
                    .controlSize(.small)
                Text("Uploading…")
            }
            Text(fileLabel)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        case .uploaded(let url, _):
            Label("URL copied", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
            Text(url.absoluteString)
                .font(.caption)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
            Button("Copy URL") { model.onCopy() }
                .controlSize(.small)
        case .failed(let message):
            Label("Upload failed", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Button("Retry") { model.onRetry() }
                .controlSize(.small)
        case .none:
            Label("Saved", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
            Text(fileLabel)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }
}
```

- [ ] **Step 7: Replace AppCoordinator**

`TidyShot/App/AppCoordinator.swift`:
```swift
import AppKit
import KeyboardShortcuts
import Observation
import ScreenCaptureKit

/// Owns app-wide state and wires hotkeys, selection, capture, output, upload, and history together.
@Observable
final class AppCoordinator {
    static let shared = AppCoordinator()

    let engine = CaptureEngine()
    let saveLocation = SaveLocation()
    let settings = AppSettings.shared
    let history: HistoryStore
    /// `thumbnails` and `pending` folders next to `history.json`.
    let thumbnails: ThumbnailStore
    let pendingFiles: PendingFileStore
    let credentialStore: any CredentialStore = KeychainCredentialStore()
    private let notifier = Notifier()
    private let permissionWindow = PermissionWindowController()
    private let overlay = QuickAccessController()
    @ObservationIgnored private lazy var selector = SelectionController(engine: engine)
    @ObservationIgnored private var queue: UploadQueue?
    /// Set after the first "Upload not configured" notification so later captures stay quiet.
    @ObservationIgnored private var warnedUploadNotConfigured = false

    private(set) var isCapturing = false
    /// The last capture written to the save folder (upload-only captures do not count).
    private(set) var lastCaptureURL: URL?
    /// Records with an upload in flight; drives the menu bar icon.
    private(set) var uploadingIDs: Set<UUID> = []

    var permissionGranted: Bool { ScreenCapturePermission.isGranted }
    var isUploading: Bool { !uploadingIDs.isEmpty }

    init() {
        let url = (try? HistoryStore.defaultFileURL())
            ?? FileManager.default.temporaryDirectory.appending(path: HistoryStore.fileName)
        history = HistoryStore(fileURL: url, retentionDays: { AppSettings.shared.historyRetentionDays })
        thumbnails = ThumbnailStore(nextTo: url)
        pendingFiles = PendingFileStore(nextTo: url)
        history.didPrune = { [weak self] records in self?.removeFiles(ofPruned: records) }
    }

    func start() {
        notifier.setUp()
        history.load()
        registerShortcuts()
        if !ScreenCapturePermission.isGranted {
            permissionWindow.show()
        }
    }

    func showPermissionWindow() {
        permissionWindow.show()
    }

    private func registerShortcuts() {
        KeyboardShortcuts.onKeyUp(for: .captureFullscreen) { [weak self] in
            Task { await self?.captureFullscreen() }
        }
        KeyboardShortcuts.onKeyUp(for: .captureArea) { [weak self] in
            Task { await self?.captureArea() }
        }
        KeyboardShortcuts.onKeyUp(for: .captureWindow) { [weak self] in
            Task { await self?.captureWindow() }
        }
    }

    func captureFullscreen() async {
        await withCaptureLock {
            let frontApp = NSWorkspace.shared.frontmostApplication?.localizedName
            guard let content = await loadContent() else { return }
            guard let display = Self.display(under: NSEvent.mouseLocation, in: content.displays) else { return }
            guard let result = await capture(.display(display)) else { return }
            await save(result, appName: frontApp)
        }
    }

    func captureArea() async {
        await runSelection(mode: .area)
    }

    func captureWindow() async {
        await runSelection(mode: .window)
    }

    /// Show the overlay, capture with the overlay excluded, dismiss, then save.
    private func runSelection(mode: SelectionMode) async {
        await withCaptureLock {
            let frontApp = NSWorkspace.shared.frontmostApplication?.localizedName
            guard let content = await loadContent() else { return }
            guard let selection = await selector.select(mode: mode, content: content) else { return }

            let result: CaptureResult?
            let appName: String?
            switch selection {
            case .area(let rect, let display):
                let overlays = await selector.overlayWindows()
                result = await capture(.area(rect: rect, display: display), excludingWindows: overlays)
                appName = frontApp
            case .window(let window):
                result = await capture(.window(window))
                appName = window.owningApplication?.applicationName
            }
            selector.dismiss()

            if let result {
                await save(result, appName: appName)
            }
        }
    }

    func revealLastCapture() {
        guard let lastCaptureURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([lastCaptureURL])
    }

    /// Runs the engine. On failure posts a notification and returns nil.
    func capture(_ target: CaptureTarget, excludingWindows: [SCWindow] = []) async -> CaptureResult? {
        do {
            return try await engine.capture(target, options: CaptureOptions(showsCursor: settings.showsCursor), excludingWindows: excludingWindows)
        } catch {
            NSLog("Capture failed: \(error.localizedDescription)")
            notifier.notifyError(error.localizedDescription)
            return nil
        }
    }

    // MARK: Save and upload

    /// Encode, copy to clipboard (image now, or URL later), write the file (save folder, or the
    /// container's `pending` folder in upload-only mode), make the thumbnail, record in history,
    /// show the overlay, and start the upload. A file is always written before the upload starts;
    /// if it cannot be written the image stays on the clipboard, so a capture is never dropped.
    func save(_ result: CaptureResult, appName: String?) async {
        let png: Data
        do {
            png = try ImageEncoder.pngData(from: result.image, scale: result.scale)
        } catch {
            NSLog("Encode failed: \(error.localizedDescription)")
            notifier.notifyError(error.localizedDescription)
            return
        }

        let action = settings.afterCaptureAction
        // One keychain read per capture; the result is passed to startUpload below.
        let destination = action.uploads ? makeDestination() : nil
        let copyImageNow: Bool
        if destination != nil {
            copyImageNow = settings.alsoCopyImageWhenUploading
        } else if action.uploads {
            // Upload wanted but not possible: the clipboard gets the image instead of a URL.
            copyImageNow = true
        } else {
            copyImageNow = settings.copyImageToClipboard
        }
        if copyImageNow {
            Pasteboard.copy(image: result.image, pngData: png, scale: result.scale)
        }

        // One counter per capture, shared by the file name and the object key, and kept on the
        // record so a retry names the object the same way.
        let needsCounter = settings.fileNameTemplate.contains("{counter}")
            || destination?.config.keyTemplate.contains("{counter}") == true
        let counter = needsCounter ? settings.nextCounter() : 0
        let id = UUID()
        let fileURL: URL
        if action == .uploadOnly {
            guard let url = writePendingFile(png, id: id, result: result, alreadyOnClipboard: copyImageNow) else { return }
            fileURL = url
        } else {
            guard let url = await writeFile(png, result: result, appName: appName, counter: counter, alreadyOnClipboard: copyImageNow) else { return }
            fileURL = url
            lastCaptureURL = url
        }
        if action.uploads, destination == nil {
            warnUploadNotConfiguredOnce(action == .uploadOnly
                ? "Set up a destination in Settings > Upload, then retry from Recent Captures. The image is on the clipboard."
                : "Set up a destination in Settings > Upload. The capture was saved and the image is on the clipboard.")
        }
        if settings.playSound {
            SoundPlayer.playShutter()
        }

        let state: CaptureRecord.UploadState
        if destination != nil {
            state = .uploading(fraction: 0)
        } else if action == .uploadOnly {
            // Nowhere to upload to yet; the pending file stays until a retry succeeds.
            state = .failed(message: UploadError.notConfigured.localizedDescription)
        } else {
            state = .none
        }
        let record = CaptureRecord(id: id, fileURL: fileURL, fileIsTemporary: action == .uploadOnly,
                                   thumbnailFileName: makeThumbnail(from: result.image, id: id),
                                   pixelWidth: result.image.width, pixelHeight: result.image.height,
                                   appName: appName, counter: counter, uploadState: state)
        history.add(record)
        showOverlay(for: record, image: result.image, scale: result.scale)

        if let destination {
            startUpload(recordID: record.id, data: png, destination: destination)
        } else if action == .save, settings.showNotification {
            notifier.notifySaved(fileURL: fileURL)
        }
    }

    /// Posts "Upload not configured" the first time per launch only. With the default
    /// after-capture action set to upload, a user without a destination would otherwise get a
    /// notification for every capture.
    private func warnUploadNotConfiguredOnce(_ message: String) {
        guard !warnedUploadNotConfigured else { return }
        warnedUploadNotConfigured = true
        notifier.notifyError(message, title: "Upload not configured")
    }

    /// Writes the PNG into the save folder. Returns nil after notifying, with the image left on
    /// the clipboard, when there is no folder or the write fails.
    private func writeFile(_ png: Data, result: CaptureResult, appName: String?, counter: Int, alreadyOnClipboard: Bool) async -> URL? {
        guard let folder = await saveLocation.ensureFolder() else {
            keepOnClipboard(result, png: png, alreadyOnClipboard: alreadyOnClipboard)
            notifier.notifyError("No folder was chosen. The image is on the clipboard.", title: "Not saved")
            return nil
        }
        do {
            let baseName = FileNamer(template: settings.fileNameTemplate).name(appName: appName, counter: counter)
            return try saveLocation.write(png, baseName: baseName, ext: "png", in: folder)
        } catch {
            NSLog("Save failed: \(error.localizedDescription)")
            keepOnClipboard(result, png: png, alreadyOnClipboard: alreadyOnClipboard)
            notifier.notifyError("\(error.localizedDescription) The image is on the clipboard.", title: "Not saved")
            return nil
        }
    }

    /// Upload-only mode: writes the PNG into the container's `pending` folder, no folder prompt.
    private func writePendingFile(_ png: Data, id: UUID, result: CaptureResult, alreadyOnClipboard: Bool) -> URL? {
        do {
            return try pendingFiles.write(png, id: id, ext: "png")
        } catch {
            NSLog("Pending write failed: \(error.localizedDescription)")
            keepOnClipboard(result, png: png, alreadyOnClipboard: alreadyOnClipboard)
            notifier.notifyError("\(error.localizedDescription) The image is on the clipboard.", title: "Not saved")
            return nil
        }
    }

    private func keepOnClipboard(_ result: CaptureResult, png: Data, alreadyOnClipboard: Bool) {
        if !alreadyOnClipboard {
            Pasteboard.copy(image: result.image, pngData: png, scale: result.scale)
        }
    }

    /// Writes the 320 px thumbnail and returns its file name, or nil (logged) when that fails;
    /// the capture goes ahead without one and the gallery shows a placeholder.
    private func makeThumbnail(from image: CGImage, id: UUID) -> String? {
        do {
            guard let small = ThumbnailMaker.thumbnail(from: image) else { return nil }
            return try thumbnails.write(try ThumbnailMaker.pngData(small), id: id)
        } catch {
            NSLog("Thumbnail failed: \(error.localizedDescription)")
            return nil
        }
    }

    private func showOverlay(for record: CaptureRecord, image: CGImage?, scale: CGFloat) {
        guard settings.showOverlay else { return }
        let thumbnail = image.map { NSImage(cgImage: $0, size: NSSize(width: CGFloat($0.width) / scale, height: CGFloat($0.height) / scale)) }
        overlay.show(record: record, thumbnail: thumbnail, corner: settings.overlayCorner,
                     autoCloseSeconds: settings.overlayAutoCloseSeconds,
                     actions: QuickAccessController.Actions(
                        copy: { [weak self] id in self?.copyLinkOrFile(recordID: id) },
                        retry: { [weak self] id in self?.retryUpload(recordID: id) },
                        reveal: { [weak self] id in self?.reveal(recordID: id) },
                        delete: { [weak self] id in Task { await self?.deleteCapture(recordID: id) } }))
    }

    /// The configured destination, or nil when the Upload tab is incomplete, no credentials are
    /// stored, or the keychain could not be read. "No item" is the normal not-configured case and
    /// stays silent here; any other keychain error is logged and reported once per launch.
    func makeDestination() -> S3Destination? {
        guard let config = settings.s3Config, config.isComplete else { return nil }
        let stored: AWSCredentials?
        do {
            stored = try credentialStore.load(account: KeychainCredentialStore.defaultAccount)
        } catch {
            NSLog("Keychain read failed: \(error.localizedDescription)")
            warnUploadNotConfiguredOnce("Could not read S3 credentials from the keychain: \(error.localizedDescription)")
            return nil
        }
        guard let credentials = stored, !credentials.accessKeyID.isEmpty, !credentials.secretAccessKey.isEmpty else {
            return nil
        }
        return S3Destination(config: config, credentials: credentials)
    }

    /// Called by the Upload settings tab after saving or forgetting credentials, so the next
    /// upload uses the new settings.
    func destinationDidChange() {
        queue = nil
    }

    /// Enqueues `data` for `recordID`. `destination` is only used when the queue has to be
    /// created (first upload, or after the Upload tab was saved); callers read it once.
    private func startUpload(recordID: UUID, data: Data, destination: S3Destination) {
        if queue == nil {
            queue = UploadQueue(destination: destination,
                                keyNamer: ObjectKeyNamer(template: destination.config.keyTemplate),
                                events: { [weak self] event in self?.handle(event) })
        }
        guard let queue, let record = history.record(id: recordID) else { return }
        uploadingIDs.insert(recordID)
        // `save` adds new records already marked uploading and shows them in the overlay, so
        // only a retry (a record in another state) needs the write and the overlay refresh.
        if !record.isUploading {
            history.update(id: recordID) { $0.uploadState = .uploading(fraction: 0) }
            refreshOverlay(for: recordID)
        }
        let job = UploadJob(id: recordID, data: data, contentType: "image/png", fileExtension: "png",
                            naming: TemplateContext(date: record.timestamp, appName: record.appName, counter: record.counter))
        Task { await queue.enqueue(job) }
    }

    /// Re-reads the file and uploads it again.
    func retryUpload(recordID: UUID) {
        // Ignore a second click while the record is already in flight; otherwise it would upload twice.
        guard history.record(id: recordID) != nil, !uploadingIDs.contains(recordID) else { return }
        guard let destination = makeDestination() else {
            markFailed(recordID, message: UploadError.notConfigured.localizedDescription)
            return
        }
        retry(recordID: recordID, destination: destination)
    }

    /// Retries every failed upload with one keychain read. Without a destination, posts one
    /// notification instead of one per record.
    func retryFailedUploads() {
        let failed = history.failedRecords
        guard !failed.isEmpty else { return }
        guard let destination = makeDestination() else {
            notifier.notifyError("Set up a destination in Settings > Upload, then retry.", title: "Upload not configured")
            return
        }
        for record in failed {
            retry(recordID: record.id, destination: destination)
        }
    }

    /// Reads the record's file and starts its upload with `destination`.
    private func retry(recordID: UUID, destination: S3Destination) {
        guard let record = history.record(id: recordID) else { return }
        do {
            let data = try readLocalFile(of: record)
            startUpload(recordID: recordID, data: data, destination: destination)
        } catch {
            markFailed(recordID, message: UploadError.fileUnreadable(record.fileURL?.lastPathComponent ?? "no local file").localizedDescription)
        }
    }

    /// The record's PNG: straight from the container for a temporary file, through the save
    /// folder's security scope otherwise. Throws when the record has no file any more.
    func readLocalFile(of record: CaptureRecord) throws -> Data {
        guard let fileURL = record.fileURL else { throw UploadError.fileUnreadable("no local file") }
        return record.fileIsTemporary ? try Data(contentsOf: fileURL) : try saveLocation.read(contentsOf: fileURL)
    }

    /// Copies the public URL, or the local file for a capture that was never uploaded.
    func copyLinkOrFile(recordID: UUID) {
        guard let record = history.record(id: recordID) else { return }
        if let url = record.uploadedURL {
            Pasteboard.copy(url: url)
        } else if let fileURL = record.fileURL {
            Pasteboard.copy(fileURL: fileURL)
        }
    }

    func reveal(recordID: UUID) {
        guard let fileURL = history.record(id: recordID)?.fileURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([fileURL])
    }

    /// Menu action for a history row: copy the URL, retry a failed upload, or reveal the file.
    /// Replaced by the gallery in the next task.
    func historyItemSelected(_ recordID: UUID) {
        guard let record = history.record(id: recordID) else { return }
        switch record.uploadState {
        case .uploaded: copyLinkOrFile(recordID: recordID)
        case .failed: retryUpload(recordID: recordID)
        case .none, .uploading: reveal(recordID: recordID)
        }
    }

    // MARK: Delete

    /// Shared by the overlay and the gallery. One confirmation; then, in order, the object in the
    /// bucket (cancelling an in-flight upload first), the local file, the thumbnail, and the
    /// history record. If the object cannot be deleted the record stays, with a notification, so
    /// Delete can be tried again; a local file that is already gone is not an error.
    func deleteCapture(recordID: UUID) async {
        guard let record = history.record(id: recordID), confirmDelete(of: record) else { return }

        var reservedKey: String?
        if uploadingIDs.contains(recordID), let queue,
           case .stopped(let key) = await queue.cancel(recordID: recordID) {
            reservedKey = key
        }
        let keys = CaptureDeletion.objectKeys(for: record, afterCancel: history.record(id: recordID), reservedKey: reservedKey)
        if !keys.isEmpty {
            guard let destination = makeDestination() else {
                notifier.notifyError("Set up the destination in Settings > Upload so the uploaded object can be removed, then try again.",
                                     title: "Not deleted")
                return
            }
            for key in keys {
                do {
                    try await destination.delete(key: key)
                } catch {
                    notifier.notifyError("Could not delete \(key): \(error.localizedDescription)", title: "Not deleted")
                    return
                }
            }
        }

        guard let current = history.record(id: recordID) else { return }
        if let fileURL = current.fileURL {
            if current.fileIsTemporary {
                pendingFiles.remove(fileURL)
            } else {
                do {
                    try saveLocation.remove(at: fileURL)
                } catch {
                    NSLog("Could not delete \(fileURL.lastPathComponent): \(error.localizedDescription)")
                }
            }
            if lastCaptureURL == fileURL {
                lastCaptureURL = nil
            }
        }
        if let name = current.thumbnailFileName {
            thumbnails.remove(fileName: name)
        }
        history.remove(id: recordID)
        overlay.close(recordID: recordID)
    }

    /// The one confirmation. The app is activated first so the alert appears in front even when
    /// it was triggered from the non-activating overlay panel.
    private func confirmDelete(of record: CaptureRecord) -> Bool {
        let alert = NSAlert()
        alert.messageText = "Delete this capture?"
        alert.informativeText = CaptureDeletion.confirmationText(for: record)
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Delete").hasDestructiveAction = true
        alert.addButton(withTitle: "Cancel")
        NSApplication.shared.activate(ignoringOtherApps: true)
        return alert.runModal() == .alertFirstButtonReturn
    }

    /// Thumbnails and temporary files of records dropped by retention. Files in the save folder
    /// are left alone.
    private func removeFiles(ofPruned records: [CaptureRecord]) {
        for record in records {
            if let name = record.thumbnailFileName {
                thumbnails.remove(fileName: name)
            }
            if record.fileIsTemporary, let fileURL = record.fileURL {
                pendingFiles.remove(fileURL)
            }
        }
    }

    // MARK: Upload events

    private func markFailed(_ recordID: UUID, message: String) {
        uploadingIDs.remove(recordID)
        history.update(id: recordID) { $0.uploadState = .failed(message: message) }
        refreshOverlay(for: recordID)
        notifier.notifyError(message, title: "Upload failed")
    }

    /// Pushes the record's current state into the overlay, if the overlay is showing it.
    private func refreshOverlay(for id: UUID) {
        if let record = history.record(id: id) {
            overlay.update(record: record)
        }
    }

    private func handle(_ event: UploadEvent) {
        switch event {
        case .started(let id, let attempt):
            if attempt > 1 {
                NSLog("Upload retry \(attempt) for \(id)")
                // Start the bar again rather than leaving the failed attempt's fraction.
                if history.setProgress(id: id, fraction: 0) {
                    refreshOverlay(for: id)
                }
            }
        case .progress(let id, let fraction):
            if history.setProgress(id: id, fraction: fraction) {
                refreshOverlay(for: id)
            }
        case .uploaded(let id, let url, let key):
            uploadingIDs.remove(id)
            // Upload-only mode: the temporary file has done its job.
            if let record = history.record(id: id), record.fileIsTemporary, let fileURL = record.fileURL {
                pendingFiles.remove(fileURL)
            }
            history.update(id: id) { record in
                record.uploadState = .uploaded(url: url, key: key)
                if record.fileIsTemporary {
                    record.fileURL = nil
                    record.fileIsTemporary = false
                }
            }
            Pasteboard.copy(url: url)
            if settings.showNotification {
                notifier.notifyUploaded(url: url)
            }
            refreshOverlay(for: id)
        case .failed(let id, let message):
            markFailed(id, message: message)
        case .cancelled(let id):
            // Requested by the delete flow, which removes the record next; no notification.
            uploadingIDs.remove(id)
            history.update(id: id) { $0.uploadState = .failed(message: "Upload cancelled.") }
            refreshOverlay(for: id)
        }
    }

    // MARK: Helpers

    /// Fetches shareable content, or shows the permission window and returns nil.
    func loadContent() async -> SCShareableContent? {
        do {
            return try await engine.shareableContent()
        } catch {
            NSLog("Shareable content failed: \(error.localizedDescription)")
            if ScreenCapturePermission.isGranted {
                notifier.notifyError("Could not list screens and windows: \(error.localizedDescription)")
            } else {
                permissionWindow.show()
            }
            return nil
        }
    }

    private func withCaptureLock(_ body: () async -> Void) async {
        guard !isCapturing else { return }
        isCapturing = true
        defer { isCapturing = false }
        await body()
    }

    /// The SCDisplay under an AppKit-global point, falling back to the first display.
    static func display(under appKitPoint: CGPoint, in displays: [SCDisplay]) -> SCDisplay? {
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        let cgPoint = Geometry.cgPoint(fromAppKit: appKitPoint, primaryHeight: primaryHeight)
        return displays.first { $0.frame.contains(cgPoint) } ?? displays.first
    }
}
```

- [ ] **Step 8: Build and run the tests**

Run:
```bash
xcodebuild -project TidyShot.xcodeproj -scheme TidyShot -destination 'platform=macOS' -derivedDataPath .build test 2>&1 | grep -E "error:|warning: .*TidyShot/|Test run|✘"
```
Expected: no `error:` or `warning:` lines, and `Test run with 149 tests in 23 suites passed`.

- [ ] **Step 9: Smoke-run upload-only and the overlay's Delete**

Run:
```bash
xcodebuild -project TidyShot.xcodeproj -scheme TidyShot -configuration Debug -derivedDataPath .build build -quiet && open .build/Build/Products/Debug/TidyShot.app
```
With a working destination configured: in Settings > General choose "Upload only, keep no local file" (a caption appears under the picker). Press `⌃⇧3`. Expected: no folder prompt, the overlay shows the thumbnail, "Uploading…" with "Upload only, no local file", then "URL copied"; pasting gives the URL; "Reveal Last Capture" in the menu is disabled; the overlay has a trash button under the X and clicking the thumbnail does nothing. Run:
```bash
ls ~/Library/Containers/io.tky.tidyshot/Data/Library/Application\ Support/TidyShot/pending ~/Library/Containers/io.tky.tidyshot/Data/Library/Application\ Support/TidyShot/thumbnails
```
Expected: `pending` is empty (or absent) and `thumbnails` holds one `<UUID>.png`; `open` that PNG: it is at most 320 px on its longest side. Now click the trash button. Expected: an alert "Delete this capture?" whose text names the uploaded object URL and "its entry in Recent Captures"; click Delete; the overlay closes, `curl -I <url>` returns 403 or 404, the thumbnail file is gone, and `history.json` no longer lists the capture. Take another capture and click the trash while the ring is still moving (a fullscreen capture on a slow connection, or Network Link Conditioner). Expected: the alert names "the upload in progress" and "the temporary file"; after Delete nothing is left in `pending`, in the bucket, or in `history.json`, and the menu bar icon is the viewfinder again. Switch back to "Upload and copy URL" and quit.

- [ ] **Step 10: Commit**

```bash
git add TidyShot/History/CaptureDeletion.swift TidyShotTests/CaptureDeletionTests.swift TidyShot/Settings/AppSettings.swift TidyShot/Settings/GeneralSettingsView.swift TidyShot/Output/Pasteboard.swift TidyShot/Output/SaveLocation.swift TidyShot/Overlay/QuickAccessModel.swift TidyShot/Overlay/QuickAccessController.swift TidyShot/Overlay/QuickAccessView.swift TidyShot/App/AppCoordinator.swift
git commit -m "feat: upload-only mode, thumbnails at capture, and delete from the overlay"
```

---

### Task 7: Recent Captures gallery (TDD for the thumbnail provider, then the window)

**Files:**
- Create: `TidyShot/Gallery/ThumbnailProvider.swift`
- Create: `TidyShot/Gallery/GalleryModel.swift`
- Create: `TidyShot/Gallery/GalleryView.swift`
- Create: `TidyShot/Gallery/GalleryWindowController.swift`
- Create: `TidyShotTests/ThumbnailProviderTests.swift`
- Modify: `TidyShot/App/AppCoordinator.swift` (four edits below)
- Modify: `TidyShot/App/MenuContent.swift` (full replacement below)

**Interfaces:**
- Consumes: `HistoryStore` (observable `records`, `update`), `ThumbnailStore`, `ThumbnailMaker`, `CaptureRecord` fields, `AppCoordinator.readLocalFile(of:)`, `copyLinkOrFile`, `retryUpload`, `reveal`, `deleteCapture` (Tasks 2 to 6).
- Produces:
  - `final class ThumbnailProvider` (main actor) with `static let previewCacheLimit = 8`, `init(store: ThumbnailStore, history: HistoryStore, readFile: @escaping (CaptureRecord) throws -> Data)`, `func thumbnail(for record: CaptureRecord) -> NSImage?`, `func preview(for record: CaptureRecord) async -> NSImage?`, `func forget(_ id: UUID)`.
  - `@Observable final class GalleryModel` with `let history: HistoryStore`, `let provider: ThumbnailProvider`, `private(set) var hoveredID: UUID?`, `private(set) var preview: NSImage?`, `var records: [CaptureRecord]`, `var previewRecord: CaptureRecord?`, `func thumbnail(for:) -> NSImage?`, `func hover(_ id: UUID)`, `func loadPreview()`.
  - `struct GalleryActions { var copy, retry, reveal, delete: (UUID) -> Void }`, `struct GalleryView: View { static let minimumSize: CGSize; let model: GalleryModel; let actions: GalleryActions }`, plus `GalleryCell`, `GalleryStatusBadge` (with `static func title(for:) -> String`), `GalleryMenuItems`, `GalleryPreviewPane`.
  - `final class GalleryWindowController { init(model: GalleryModel, actions: GalleryActions); func show(); func close() }` and `final class GalleryWindow: NSWindow` (Escape and ⌘W close).
  - `AppCoordinator.showGallery()`; `historyItemSelected(_:)` is removed; `MenuContent.title(for:)` is removed. The menu gets "Recent Captures…" and keeps "Retry Failed Uploads" (only while something is failed).

- [ ] **Step 1: Write the failing tests**

`TidyShotTests/ThumbnailProviderTests.swift`:
```swift
import AppKit
import Foundation
import Testing
@testable import TidyShot

struct ThumbnailProviderTests {
    let dir: URL
    let history: HistoryStore
    let store: ThumbnailStore

    init() throws {
        dir = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        history = HistoryStore(fileURL: dir.appending(path: "history.json"))
        store = ThumbnailStore(nextTo: dir.appending(path: "history.json"))
    }

    func png(width: Int, height: Int) throws -> Data {
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(red: 0, green: 0, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return try ImageEncoder.pngData(from: context.makeImage()!, scale: 1)
    }

    func record(thumbnail: String? = nil, file: URL? = URL(fileURLWithPath: "/Users/tim/Desktop/Shot.png")) -> CaptureRecord {
        CaptureRecord(fileURL: file, thumbnailFileName: thumbnail, pixelWidth: 640, pixelHeight: 400, appName: "Safari")
    }

    @Test func storedThumbnailIsUsedWithoutReadingTheFile() throws {
        let item = record()
        let name = try store.write(try png(width: 320, height: 200), id: item.id)
        var stored = item
        stored.thumbnailFileName = name
        history.add(stored)
        var reads = 0
        let provider = ThumbnailProvider(store: store, history: history) { _ in reads += 1; throw CocoaError(.fileNoSuchFile) }

        let image = provider.thumbnail(for: stored)
        #expect(image?.size == CGSize(width: 320, height: 200))
        #expect(reads == 0)
        #expect(provider.thumbnail(for: stored) === image)
    }

    @Test func legacyRecordGetsAThumbnailGeneratedAndStored() throws {
        let item = record()
        history.add(item)
        let data = try png(width: 640, height: 400)
        let provider = ThumbnailProvider(store: store, history: history) { _ in data }

        let image = provider.thumbnail(for: item)
        #expect(image?.size == CGSize(width: 320, height: 200))
        let name = history.record(id: item.id)?.thumbnailFileName
        #expect(name == "\(item.id.uuidString).png")
        #expect(FileManager.default.fileExists(atPath: store.url(forFileName: name ?? "").path(percentEncoded: false)))
    }

    @Test func recordWithoutFileOrThumbnailGetsPlaceholder() {
        let item = record(file: nil)
        history.add(item)
        let provider = ThumbnailProvider(store: store, history: history) { _ in throw CocoaError(.fileNoSuchFile) }
        #expect(provider.thumbnail(for: item) == nil)
        #expect(history.record(id: item.id)?.thumbnailFileName == nil)
    }

    @Test func previewComesFromTheFileOrFallsBackToTheThumbnail() async throws {
        let withFile = record()
        let data = try png(width: 2000, height: 1000)
        let provider = ThumbnailProvider(store: store, history: history) { record in
            guard record.fileURL != nil else { throw CocoaError(.fileNoSuchFile) }
            return data
        }
        let preview = await provider.preview(for: withFile)
        #expect(preview?.size == CGSize(width: 1200, height: 600))
        #expect(await provider.preview(for: withFile) === preview)

        let uploadOnly = record(thumbnail: try store.write(try png(width: 300, height: 150), id: UUID()), file: nil)
        let fallback = await provider.preview(for: uploadOnly)
        #expect(fallback?.size == CGSize(width: 300, height: 150))

        provider.forget(withFile.id)
        #expect(await provider.preview(for: withFile) !== preview)
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run:
```bash
xcodegen generate && xcodebuild -project TidyShot.xcodeproj -scheme TidyShot -destination 'platform=macOS' -derivedDataPath .build test 2>&1 | grep -E "error:|Test run" | head
```
Expected: compile errors containing `cannot find 'ThumbnailProvider' in scope`.

- [ ] **Step 3: Write ThumbnailProvider**

`TidyShot/Gallery/ThumbnailProvider.swift`:
```swift
import AppKit

/// Thumbnails and larger previews for the gallery. Thumbnails come from the `thumbnails` folder;
/// a record from before thumbnails existed gets one generated from its local file the first time
/// it is shown (and the record is updated), or a placeholder (nil) when it has no file either.
/// Previews are decoded from the local file off the main thread and fall back to the thumbnail.
final class ThumbnailProvider {
    static let previewCacheLimit = 8

    private let store: ThumbnailStore
    private let history: HistoryStore
    private let readFile: (CaptureRecord) throws -> Data
    private var thumbnails: [UUID: NSImage] = [:]
    private var previews: [UUID: NSImage] = [:]
    private var previewOrder: [UUID] = []

    /// `readFile` returns the record's PNG, or throws when there is none (see
    /// `AppCoordinator.readLocalFile(of:)`).
    init(store: ThumbnailStore, history: HistoryStore, readFile: @escaping (CaptureRecord) throws -> Data) {
        self.store = store
        self.history = history
        self.readFile = readFile
    }

    /// The 320 px thumbnail, or nil for a placeholder.
    func thumbnail(for record: CaptureRecord) -> NSImage? {
        if let cached = thumbnails[record.id] { return cached }
        if let name = record.thumbnailFileName, let image = NSImage(contentsOf: store.url(forFileName: name)) {
            thumbnails[record.id] = image
            return image
        }
        guard let data = try? readFile(record),
              let small = ThumbnailMaker.thumbnail(fromPNGData: data),
              let png = try? ThumbnailMaker.pngData(small),
              let name = try? store.write(png, id: record.id) else { return nil }
        history.update(id: record.id) { $0.thumbnailFileName = name }
        let image = NSImage(cgImage: small, size: .zero)
        thumbnails[record.id] = image
        return image
    }

    /// Up to 1200 px from the local file, or the thumbnail when the record has no file left.
    func preview(for record: CaptureRecord) async -> NSImage? {
        if let cached = previews[record.id] { return cached }
        guard let data = try? readFile(record) else { return thumbnail(for: record) }
        let decoded = await Task.detached(priority: .userInitiated) {
            ThumbnailMaker.thumbnail(fromPNGData: data, maxSide: ThumbnailMaker.previewMaxSide)
        }.value
        guard let decoded else { return thumbnail(for: record) }
        let image = NSImage(cgImage: decoded, size: .zero)
        previews[record.id] = image
        previewOrder.append(record.id)
        if previewOrder.count > Self.previewCacheLimit {
            previews[previewOrder.removeFirst()] = nil
        }
        return image
    }

    /// Drops cached images for a deleted record.
    func forget(_ id: UUID) {
        thumbnails[id] = nil
        previews[id] = nil
        previewOrder.removeAll { $0 == id }
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run:
```bash
xcodegen generate && xcodebuild -project TidyShot.xcodeproj -scheme TidyShot -destination 'platform=macOS' -derivedDataPath .build test 2>&1 | grep -E "error:|warning: .*TidyShot/|Test run|✘"
```
Expected: `Test run with 153 tests in 24 suites passed`. If `previewComesFromTheFileOrFallsBackToTheThumbnail` reports a Sendable error on the detached task, the SDK's `CGImage` lost its `Sendable` conformance; return `try? ThumbnailMaker.pngData(...)` (a `Data`) from the detached task instead and build the `NSImage` from that data on the main actor.

- [ ] **Step 5: Write the model, the views and the window**

`TidyShot/Gallery/GalleryModel.swift`:
```swift
import AppKit
import Observation

/// State behind the gallery window: the history (newest first), which cell is hovered, and the
/// larger preview for it.
@Observable
final class GalleryModel {
    let history: HistoryStore
    @ObservationIgnored let provider: ThumbnailProvider

    /// The last cell the mouse entered. Kept when the mouse leaves, so the preview pane does not
    /// flicker back to the newest capture between cells.
    private(set) var hoveredID: UUID?
    private(set) var preview: NSImage?
    @ObservationIgnored private var previewTask: Task<Void, Never>?

    init(history: HistoryStore, provider: ThumbnailProvider) {
        self.history = history
        self.provider = provider
    }

    var records: [CaptureRecord] { history.records }

    /// The hovered record, or the newest one, or nil when the history is empty.
    var previewRecord: CaptureRecord? {
        if let hoveredID, let record = history.record(id: hoveredID) { return record }
        return records.first
    }

    func thumbnail(for record: CaptureRecord) -> NSImage? {
        provider.thumbnail(for: record)
    }

    func hover(_ id: UUID) {
        guard id != hoveredID else { return }
        hoveredID = id
        loadPreview()
    }

    /// Loads the preview for `previewRecord`; a newer request cancels an older one.
    func loadPreview() {
        previewTask?.cancel()
        guard let record = previewRecord else {
            preview = nil
            return
        }
        previewTask = Task { [provider] in
            let image = await provider.preview(for: record)
            guard !Task.isCancelled else { return }
            preview = image
        }
    }
}
```

`TidyShot/Gallery/GalleryView.swift`:
```swift
import SwiftUI

/// What the gallery's cells and preview pane can do with a capture. All run on the coordinator.
struct GalleryActions {
    /// Copies the public URL, or the local file when the capture was never uploaded.
    var copy: (UUID) -> Void
    var retry: (UUID) -> Void
    var reveal: (UUID) -> Void
    /// Deletes everywhere after one confirmation.
    var delete: (UUID) -> Void
}

/// Grid of thumbnails, newest first, with a preview pane for the hovered capture.
struct GalleryView: View {
    static let minimumSize = CGSize(width: 820, height: 520)

    let model: GalleryModel
    let actions: GalleryActions

    var body: some View {
        HStack(spacing: 0) {
            if model.records.isEmpty {
                ContentUnavailableView("No captures yet", systemImage: "photo.on.rectangle",
                                       description: Text("Captures appear here newest first."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 170, maximum: 220), spacing: 12)], spacing: 12) {
                        ForEach(model.records) { record in
                            GalleryCell(record: record, thumbnail: model.thumbnail(for: record),
                                        isHovered: model.hoveredID == record.id, actions: actions)
                                .onHover { inside in
                                    if inside { model.hover(record.id) }
                                }
                        }
                    }
                    .padding(16)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            Divider()
            GalleryPreviewPane(record: model.previewRecord, image: model.preview, actions: actions)
                .frame(width: 320)
        }
        .frame(minWidth: Self.minimumSize.width, minHeight: Self.minimumSize.height)
        .onAppear { model.loadPreview() }
        .onChange(of: model.records.first?.id) { model.loadPreview() }
    }
}

/// One thumbnail with a status badge. Click copies; the context menu has everything else.
struct GalleryCell: View {
    let record: CaptureRecord
    let thumbnail: NSImage?
    let isHovered: Bool
    let actions: GalleryActions

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .bottomTrailing) {
                Group {
                    if let thumbnail {
                        Image(nsImage: thumbnail)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                    } else {
                        Image(systemName: "photo")
                            .font(.largeTitle)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 120)
                .background(Color.black.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                GalleryStatusBadge(state: record.uploadState)
                    .padding(6)
            }
            Text(record.timestamp.formatted(date: .abbreviated, time: .shortened))
                .font(.caption)
            Text(record.uploadedURL?.lastPathComponent ?? record.fileURL?.lastPathComponent ?? record.appName ?? "Capture")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(8)
        .background(isHovered ? Color.accentColor.opacity(0.12) : Color.clear, in: RoundedRectangle(cornerRadius: 10))
        .contentShape(Rectangle())
        .onTapGesture { actions.copy(record.id) }
        .contextMenu { GalleryMenuItems(record: record, actions: actions) }
        .help(record.uploadedURL != nil ? "Click to copy the URL" : record.hasLocalFile ? "Click to copy the file" : "")
        .accessibilityLabel(GalleryStatusBadge.title(for: record.uploadState))
    }
}

/// `Uploaded`, `Uploading`, `Failed` or `Saved`, as a small capsule on the thumbnail.
struct GalleryStatusBadge: View {
    let state: CaptureRecord.UploadState

    static func title(for state: CaptureRecord.UploadState) -> String {
        switch state {
        case .none: "Saved"
        case .uploading: "Uploading"
        case .uploaded: "Uploaded"
        case .failed: "Failed"
        }
    }

    var body: some View {
        Text(Self.title(for: state))
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.9), in: Capsule())
            .foregroundStyle(.white)
    }

    private var color: Color {
        switch state {
        case .none: .gray
        case .uploading: .blue
        case .uploaded: .green
        case .failed: .red
        }
    }
}

/// Shared by the cell's context menu and the preview pane's buttons.
struct GalleryMenuItems: View {
    let record: CaptureRecord
    let actions: GalleryActions

    var body: some View {
        if record.uploadedURL != nil {
            Button("Copy URL") { actions.copy(record.id) }
        } else if record.hasLocalFile {
            Button("Copy File") { actions.copy(record.id) }
        }
        if record.isFailed {
            Button("Retry Upload") { actions.retry(record.id) }
        }
        if record.hasLocalFile {
            Button("Reveal in Finder") { actions.reveal(record.id) }
        }
        Divider()
        Button("Delete…", role: .destructive) { actions.delete(record.id) }
    }
}

/// The hovered capture, larger, with its details and actions.
struct GalleryPreviewPane: View {
    let record: CaptureRecord?
    let image: NSImage?
    let actions: GalleryActions

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let record {
                Group {
                    if let image {
                        Image(nsImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                    } else {
                        Image(systemName: "photo")
                            .font(.system(size: 48))
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 220)
                .background(Color.black.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                .clipShape(RoundedRectangle(cornerRadius: 10))

                Text(record.timestamp.formatted(date: .long, time: .standard))
                    .font(.headline)
                Text("\(record.pixelWidth) × \(record.pixelHeight) px" + (record.appName.map { "  ·  \($0)" } ?? ""))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                statusLine(for: record)
                if let fileURL = record.fileURL {
                    Text(record.fileIsTemporary ? "Temporary file, deleted after upload" : fileURL.path(percentEncoded: false))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .truncationMode(.middle)
                } else {
                    Text("No local file")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                HStack {
                    GalleryMenuItems(record: record, actions: actions)
                }
                .controlSize(.small)
                Spacer()
            } else {
                Spacer()
                Text("Hover a capture to preview it.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                Spacer()
            }
        }
        .padding(16)
    }

    @ViewBuilder
    private func statusLine(for record: CaptureRecord) -> some View {
        switch record.uploadState {
        case .uploaded(let url, _):
            Text(url.absoluteString)
                .font(.caption)
                .textSelection(.enabled)
                .lineLimit(2)
                .truncationMode(.middle)
        case .uploading(let fraction):
            ProgressView(value: fraction) { Text("Uploading…") }
                .controlSize(.small)
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(.red)
                .lineLimit(3)
        case .none:
            Label("Saved locally, not uploaded", systemImage: "checkmark.circle")
                .font(.caption)
        }
    }
}
```

`TidyShot/Gallery/GalleryWindowController.swift`:
```swift
import AppKit
import SwiftUI

/// The Recent Captures window. One instance, reused; `show()` brings it to the front.
final class GalleryWindowController {
    private let model: GalleryModel
    private let actions: GalleryActions
    private var window: NSWindow?

    init(model: GalleryModel, actions: GalleryActions) {
        self.model = model
        self.actions = actions
    }

    func show() {
        if window == nil {
            let hosting = NSHostingController(rootView: GalleryView(model: model, actions: actions))
            let newWindow = GalleryWindow(contentViewController: hosting)
            newWindow.title = "Recent Captures"
            newWindow.styleMask = [.titled, .closable, .resizable, .miniaturizable]
            newWindow.isReleasedWhenClosed = false
            newWindow.setContentSize(NSSize(width: 900, height: 600))
            newWindow.center()
            newWindow.setFrameAutosaveName("RecentCaptures")
            window = newWindow
        }
        // A menu bar agent is not the active app when its menu is used; activate so the window
        // comes to the front and takes keyboard focus.
        NSApplication.shared.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        model.loadPreview()
    }

    func close() {
        window?.performClose(nil)
    }
}

/// Closes on Escape and ⌘W. A menu bar agent has no main menu, so the usual Close item that
/// would provide ⌘W does not exist.
final class GalleryWindow: NSWindow {
    override func cancelOperation(_ sender: Any?) {
        performClose(nil)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
           event.charactersIgnoringModifiers == "w" {
            performClose(nil)
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}
```

- [ ] **Step 6: Wire the gallery into the coordinator and the menu**

In `TidyShot/App/AppCoordinator.swift`, four edits: two lazy properties next to `selector`, `showGallery()` after `showPermissionWindow()`, the removal of `historyItemSelected(_:)`, and one line at the end of `deleteCapture`:

Replace:

```swift
    @ObservationIgnored private lazy var selector = SelectionController(engine: engine)
    @ObservationIgnored private var queue: UploadQueue?
```

with:

```swift
    @ObservationIgnored private lazy var selector = SelectionController(engine: engine)
    @ObservationIgnored private lazy var thumbnailProvider = ThumbnailProvider(store: thumbnails, history: history) { [unowned self] record in
        try self.readLocalFile(of: record)
    }
    @ObservationIgnored private lazy var gallery = GalleryWindowController(
        model: GalleryModel(history: history, provider: thumbnailProvider),
        actions: GalleryActions(
            copy: { [weak self] id in self?.copyLinkOrFile(recordID: id) },
            retry: { [weak self] id in self?.retryUpload(recordID: id) },
            reveal: { [weak self] id in self?.reveal(recordID: id) },
            delete: { [weak self] id in Task { await self?.deleteCapture(recordID: id) } }))
    @ObservationIgnored private var queue: UploadQueue?
```

Replace:

```swift
    func showPermissionWindow() {
        permissionWindow.show()
    }

```

with:

```swift
    func showPermissionWindow() {
        permissionWindow.show()
    }

    /// Opens (or brings forward) the Recent Captures gallery.
    func showGallery() {
        gallery.show()
    }

```

Delete this block:

```swift
    /// Menu action for a history row: copy the URL, retry a failed upload, or reveal the file.
    /// Replaced by the gallery in the next task.
    func historyItemSelected(_ recordID: UUID) {
        guard let record = history.record(id: recordID) else { return }
        switch record.uploadState {
        case .uploaded: copyLinkOrFile(recordID: recordID)
        case .failed: retryUpload(recordID: recordID)
        case .none, .uploading: reveal(recordID: recordID)
        }
    }


```

Replace:

```swift
        history.remove(id: recordID)
        overlay.close(recordID: recordID)
    }
```

with:

```swift
        history.remove(id: recordID)
        thumbnailProvider.forget(recordID)
        overlay.close(recordID: recordID)
    }
```

`TidyShot/App/MenuContent.swift` (full replacement):
```swift
import KeyboardShortcuts
import SwiftUI

struct MenuContent: View {
    private let coordinator = AppCoordinator.shared

    var body: some View {
        if !coordinator.permissionGranted {
            Button("Screen Recording permission needed…") {
                coordinator.showPermissionWindow()
            }
            Divider()
        }
        Button(menuTitle("Capture Area", .captureArea)) {
            Task { await coordinator.captureArea() }
        }
        .disabled(coordinator.isCapturing)
        Button(menuTitle("Capture Window", .captureWindow)) {
            Task { await coordinator.captureWindow() }
        }
        .disabled(coordinator.isCapturing)
        Button(menuTitle("Capture Fullscreen", .captureFullscreen)) {
            Task { await coordinator.captureFullscreen() }
        }
        .disabled(coordinator.isCapturing)
        Divider()
        Button("Recent Captures…") {
            coordinator.showGallery()
        }
        if !coordinator.history.failedRecords.isEmpty {
            Button("Retry Failed Uploads") {
                coordinator.retryFailedUploads()
            }
        }
        Button("Reveal Last Capture") {
            coordinator.revealLastCapture()
        }
        .disabled(coordinator.lastCaptureURL == nil)
        Divider()
        SettingsLink {
            Text("Settings…")
        }
        .keyboardShortcut(",")
        Button("Quit TidyShot") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }

    private func menuTitle(_ title: String, _ name: KeyboardShortcuts.Name) -> String {
        guard let shortcut = KeyboardShortcuts.getShortcut(for: name) else { return title }
        return "\(title)  \(shortcut)"
    }
}
```

- [ ] **Step 7: Build and run the tests**

Run:
```bash
xcodegen generate && xcodebuild -project TidyShot.xcodeproj -scheme TidyShot -destination 'platform=macOS' -derivedDataPath .build test 2>&1 | grep -E "error:|warning: .*TidyShot/|Test run|✘"
```
Expected: no `error:` or `warning:` lines, and `Test run with 153 tests in 24 suites passed`.

- [ ] **Step 8: Smoke-run the gallery**

Run:
```bash
xcodebuild -project TidyShot.xcodeproj -scheme TidyShot -configuration Debug -derivedDataPath .build build -quiet && open .build/Build/Products/Debug/TidyShot.app
```
Open the menu. Expected: "Recent Captures…" where the submenu was. Click it. Expected: a resizable window titled "Recent Captures" comes to the front with a grid of thumbnails newest first (the Phase 2 captures whose files still exist get thumbnails now; `thumbnails/` fills up and `history.json` gains `thumbnailFileName` entries), a status capsule on each, and the newest capture large in the right-hand pane with date, pixel size, app, URL and buttons. Hover another cell: it highlights and the pane switches to it. Click an Uploaded cell, paste into Notes: the URL. Right-click a cell: Copy URL or Copy File, Retry Upload (Failed only), Reveal in Finder (local file only), Delete…. Press Escape: the window closes; reopen it from the menu; press ⌘W: it closes. Take a capture with the window open: the new cell appears at the top and its badge goes Uploading, then Uploaded, without reopening. Quit.

- [ ] **Step 9: Commit**

```bash
git add TidyShot/Gallery TidyShotTests/ThumbnailProviderTests.swift TidyShot/App/AppCoordinator.swift TidyShot/App/MenuContent.swift
git commit -m "feat: recent captures gallery window replacing the history submenu"
```

---

### Task 8: Forget Credentials, manual checklist, README, end-to-end check, PR

**Files:**
- Modify: `TidyShot/Settings/UploadSettingsView.swift` (two edits below)
- Create: `docs/testing/phase-3-manual-checklist.md`
- Modify: `README.md` (edits below)

**Interfaces:**
- Consumes: `CredentialStore.delete(account:)` (Phase 2), `AppCoordinator.destinationDidChange()`.
- Produces: a "Forget Credentials" button in the Credentials section that deletes the keychain item, clears the three fields, resets the queue and reports "Credentials removed from the keychain. Uploads stay off until new ones are saved." The destination fields are kept.

- [ ] **Step 1: Add the button and its action**

In `TidyShot/Settings/UploadSettingsView.swift`:

Replace:

```swift
                Text("Stored in your login keychain, never in preferences. A session token is only needed for temporary credentials.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
```

with:

```swift
                Text("Stored in your login keychain, never in preferences. A session token is only needed for temporary credentials.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Forget Credentials", role: .destructive) { forgetCredentials() }
                    .disabled(isTesting)
            }
```

Replace:

```swift
    /// Saves the form, then runs the connection test against what was saved.
```

with:

```swift
    /// Deletes the keychain item and clears the three fields. The destination fields stay, so
    /// entering a new key pair and saving is all it takes to upload again.
    private func forgetCredentials() {
        do {
            try coordinator.credentialStore.delete(account: KeychainCredentialStore.defaultAccount)
        } catch {
            show(error.localizedDescription, isError: true)
            return
        }
        accessKeyID = ""
        secretAccessKey = ""
        sessionToken = ""
        keychainError = nil
        coordinator.destinationDidChange()
        show("Credentials removed from the keychain. Uploads stay off until new ones are saved.", isError: false)
    }

    /// Saves the form, then runs the connection test against what was saved.
```

- [ ] **Step 2: Build and run the tests**

Run:
```bash
xcodebuild -project TidyShot.xcodeproj -scheme TidyShot -destination 'platform=macOS' -derivedDataPath .build test 2>&1 | grep -E "error:|warning: .*TidyShot/|Test run|✘"
```
Expected: no `error:` or `warning:` lines, and `Test run with 153 tests in 24 suites passed`.

- [ ] **Step 3: Write the manual checklist**

`docs/testing/phase-3-manual-checklist.md`:
````markdown
# Phase 3 manual test checklist

Run after any change to Gallery, Overlay, History, Upload naming, or AppCoordinator. Automated
tests cover the template engine, key validation and migration, thumbnails and the two stores,
record migration, queue cancellation, deletion bookkeeping and the thumbnail provider; everything
here needs a real bucket and eyes.

Setup: fresh build, Screen Recording granted, save folder set to Desktop, a working destination
saved in Settings > Upload, after-capture action "Upload and copy URL", three or more captures in
history including at least one Phase 2 capture (made before this build).

## Gallery
- [ ] The menu shows "Recent Captures…" and no submenu; with an empty history the window shows "No captures yet".
- [ ] The grid lists captures newest first with a thumbnail and a status capsule each; Phase 2 captures whose files exist get thumbnails on first display (`thumbnails/` gains files, `history.json` gains `thumbnailFileName`); a Phase 2 capture whose file was deleted shows the placeholder icon.
- [ ] Hovering a cell highlights it and the right-hand pane shows it larger with date, `W × H px`, app, URL or status, and file path.
- [ ] Clicking an Uploaded cell copies the URL (paste into Notes); clicking a Saved cell copies the file (paste in Finder makes a copy).
- [ ] Context menu offers Copy URL or Copy File, Retry Upload (Failed only), Reveal in Finder (local file only), Delete….
- [ ] Delete… on an uploaded capture: the alert names the object URL and the file; Cancel changes nothing; Delete removes the row, `curl -I <url>` gives 403 or 404, the file is gone from the save folder, the thumbnail is gone from `thumbnails/`.
- [ ] Delete… while offline on an uploaded capture: notification "Not deleted" and the row stays; back online, Delete… works.
- [ ] Retry Upload on a Failed capture with the network restored turns the capsule Uploaded and copies the URL.
- [ ] The window remembers its size and position across close and reopen; Escape and ⌘W close it.
- [ ] With the window open, a new capture appears at the top and its capsule goes Uploading, then Uploaded.

## Overlay delete
- [ ] Trash button during an upload (fullscreen capture or Network Link Conditioner): the alert names "the upload in progress"; after Delete the overlay closes, the menu bar icon returns to the viewfinder, no object is in the bucket (list it, or GET the URL the overlay would have shown), no row, no file, no thumbnail.
- [ ] Trash button after the upload finished: object, row, file and thumbnail gone.
- [ ] Cancel in the alert keeps everything and the overlay stays.
- [ ] Clicking the thumbnail of an upload-only capture does nothing (no Finder reveal).

## Upload only
- [ ] Settings > General, "Upload only, keep no local file": the caption appears; with no save folder chosen, a capture shows no folder prompt, the overlay goes to "URL copied", pasting gives the URL, `pending/` is empty afterwards, the gallery row shows "No local file" and no Reveal item, "Reveal Last Capture" is disabled.
- [ ] Wi-Fi off, capture: overlay "Upload failed" with Retry, `pending/<UUID>.png` exists; Wi-Fi on, Retry from the gallery: Uploaded, and the pending file is gone.
- [ ] Forget Credentials, then capture in upload-only: one "Upload not configured" notification, the image is on the clipboard, the row is Failed and the pending file stays; re-enter credentials, Retry Upload: Uploaded.
- [ ] "Also copy image" on: paste gives the image until the upload finishes, then the URL.

## Key templates
- [ ] After updating from Phase 2 with prefix `shots` and length 8 saved, Settings > Upload shows `shots/{random:8}`; after Save, `defaults read io.tky.tidyshot s3DestinationConfig` contains `keyTemplate` and no `keyPrefix` or `keyLength`.
- [ ] Template `shots/{year}/{month}/{hostname}-{random:8}`: the example updates as you type; Save; capture: the URL is `https://snap.tky.io/shots/2026/10/<hostname>-XXXXXXXX.png` with the hostname lowercased and without `.local`.
- [ ] Template `{date}/{app}`: the orange warning appears; Save works; two captures within one second: the second fails with "Could not find an unused object key after 5 tries." and keeps its file for retry.
- [ ] Template `my shots/{random}`: red message `" " is not allowed…`; Save shows "Key template: …" and does not save. Template `{foo}`: red `{foo} is not a token.`
- [ ] Save and Test Connection with a folder template: the status line's probe URL is inside that folder and the probe is gone afterwards.
- [ ] File name template `{year}-{month}-{day} {hostname} {app}` names local files as expected; the default template still gives `Screenshot 2026-10-19 at 11.56.03.png`.
- [ ] A retried failed upload lands under the capture's own date folder, not today's, and with the same `{counter}` value.

## Forget credentials
- [ ] Forget Credentials: the three fields clear, the status reads "Credentials removed from the keychain…", Keychain Access no longer has "TidyShot S3 credentials"; a capture gives "Upload not configured"; re-enter and Save: uploads work again.

## History hygiene
- [ ] Retention 1 day with older captures present, then capture: older rows disappear, their files in `thumbnails/` and `pending/` are gone, and their files in the save folder remain.
- [ ] Quit, replace `history.json` with `not json`, relaunch: the gallery is empty, `thumbnails/` and `pending/` are untouched, and `history.json.corrupt-<number>` exists.
````

- [ ] **Step 4: Update the README**

In `README.md`, replace the whole `## Upload` section (from the heading to the line before `## Documents`) with:

````markdown
## Upload

Settings > Upload takes an S3-compatible endpoint (AWS S3, Cloudflare R2, Backblaze B2, MinIO),
region, bucket, a public URL template such as `https://snap.tky.io/{key}`, and an object key
template. Credentials are stored in your login keychain; Forget Credentials removes them again.
Save and Test Connection saves the form, then uploads a small probe object into the folder your
key template would use, fetches it through the public URL without credentials, and deletes it.

The key template defaults to `{random:6}` (`aSIS7x.png`). Tokens: `{date}` `{year}` `{month}`
`{day}` `{time}` `{datetime}` `{hostname}` `{app}` `{counter}` `{random}` `{random:N}`; letters,
digits, `.`, `_`, `-` and `/` are allowed between tokens, and `/` makes folders, so
`shots/{year}/{month}/{hostname}-{random:8}` is valid. The same tokens work in the file name
template. The app checks that a key is unused before uploading; a template without `{random}` or
`{counter}` gets a warning because only that check then keeps two captures apart. By default no
ACL header is sent; turn on "Send public-read ACL" only if your bucket relies on object ACLs
rather than a bucket policy or CDN.

After capture, "Upload and copy URL" saves the file locally first, then uploads it; the public
URL replaces the clipboard contents when the upload finishes. "Upload only, keep no local file"
writes the PNG inside TidyShot's container instead, uploads it, copies the URL and deletes the
file; a failed upload keeps it until a retry succeeds or the capture is deleted.

## Recent Captures

The menu's Recent Captures… item opens a gallery of thumbnails, newest first. Hover for a larger
preview, click to copy the URL (or the file when it was never uploaded), and use the context menu
to retry a failed upload, reveal the file, or delete the capture, which removes the object from
the bucket, the local file, the thumbnail and the history entry after one confirmation. The
Quick Access overlay has the same Delete; while an upload is still running it cancels it first.
Thumbnails live in `~/Library/Containers/io.tky.tidyshot/Data/Library/Application Support/TidyShot/thumbnails`.
````

Then add one line to the `## Documents` list after the Phase 2 checklist:

```markdown
- Phase 3 manual test checklist: `docs/testing/phase-3-manual-checklist.md`
```

- [ ] **Step 5: Run the end-to-end check**

Run:
```bash
xcodebuild -project TidyShot.xcodeproj -scheme TidyShot -configuration Debug -derivedDataPath .build build -quiet && open .build/Build/Products/Debug/TidyShot.app
```
Set the key template to `shots/{year}/{month}/{hostname}-{random:8}`, Save and Test Connection, press `⌃⇧4`, drag a rectangle, paste into Slack: a working `https://snap.tky.io/shots/2026/10/<hostname>-XXXXXXXX.png` link. Open Recent Captures…, hover the new capture, right-click, Delete…, confirm: the link now returns 403 or 404. Then work through `docs/testing/phase-3-manual-checklist.md` and, because Task 4 changed the Upload tab and Task 6 the save flow, the "Upload settings" and "Capture and upload" sections of `docs/testing/phase-2-manual-checklist.md` (read "key template" where it says "key prefix" and skip the random name length stepper item).

- [ ] **Step 6: Commit**

```bash
git add TidyShot/Settings/UploadSettingsView.swift docs/testing/phase-3-manual-checklist.md README.md
git commit -m "feat: forget credentials, Phase 3 checklist and README"
```

- [ ] **Step 7: Push and open the PR**

Phase 3 is done when both checklists pass. Push `phase-3-gallery` and open a PR against `main` with the results in the description (no Claude Code session URL):

```bash
git push -u origin phase-3-gallery
gh pr create --base main --head phase-3-gallery --title "Phase 3: recent captures gallery, upload-only mode and key templates" --body "$(cat <<'BODY'
Replaces the Recent Captures submenu with a thumbnail gallery (hover preview, click to copy, retry, delete from bucket plus history plus disk), adds Delete to the Quick Access overlay with cancellation of an in-flight upload, adds the "Upload only, keep no local file" action, turns the object key into a template sharing one token engine with the file name template (with migration of the Phase 2 prefix and length), and adds Forget Credentials.

- Unit tests: `Test run with 153 tests in 24 suites passed`.
- Manual checklist `docs/testing/phase-3-manual-checklist.md`: all items pass.
- Phase 2 checklist sections "Upload settings" and "Capture and upload": pass.
BODY
)"
```
Expected: `gh` prints the PR URL.

---

## Out of scope for this plan (next plans)

- Phase 4 annotation (editor window, blur, pixelate, redact), Phase 5 scrolling capture, Phase 6 overlay and capture polish (save-as, drag-out with `NSFilePromiseProvider`, stacking, All-in-One mode, freeze screen, self-timer, pin to screen, URL scheme), Phase 7 extras.
- Per-destination image format override (JPEG, HEIC, quality) and multiple destinations.
- Hover popovers instead of the preview pane, keyboard navigation and multi-select in the gallery, and a search field.
- Deleting from the bucket when a record is pruned by retention (pruning only removes thumbnails and pending files).
- Data-protection keychain migration once Developer ID signing exists.
